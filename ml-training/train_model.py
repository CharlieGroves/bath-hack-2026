from __future__ import annotations

import argparse
import json
import math
import os
import pickle
import random
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("NUMEXPR_NUM_THREADS", "1")
os.environ.setdefault("KMP_INIT_AT_FORK", "FALSE")

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import mean_absolute_percentage_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from torch import nn

from pipeline import (
    BACKEND_ROOT,
    CATEGORICAL_FEATURES,
    DEFAULT_ARTIFACTS_DIR,
    DEFAULT_DATASET_PATH,
    METADATA_COLUMNS,
    NUMERIC_FEATURES,
    PREDICTION_HORIZON_MONTHS,
    PriceForecastNet,
    TARGET_NOTE,
    build_dataset_frame,
    build_growth_reference,
    build_inference_payload,
    matrix_from_frame,
    make_preprocessor,
    predict_future_prices,
    stabilize_future_price_predictions,
)


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def run_dataset_export(output_path: Path) -> None:
    env = os.environ.copy()
    env["OUTPUT"] = str(output_path)
    subprocess.run(
        ["mise", "exec", "ruby@3.4.4", "--", "bundle", "exec", "rake", "ml:export_dataset"],
        cwd=BACKEND_ROOT,
        env=env,
        check=True,
    )


def train_with_validation(
    train_matrix: np.ndarray,
    train_targets: np.ndarray,
    val_matrix: np.ndarray,
    val_targets: np.ndarray,
    seed: int,
    max_epochs: int = 800,
) -> tuple[PriceForecastNet, int]:
    set_seed(seed)
    model = PriceForecastNet(train_matrix.shape[1])
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    criterion = nn.SmoothL1Loss()

    train_tensor = torch.tensor(train_matrix, dtype=torch.float32)
    train_target_tensor = torch.tensor(train_targets.reshape(-1, 1), dtype=torch.float32)
    val_tensor = torch.tensor(val_matrix, dtype=torch.float32)
    val_target_tensor = torch.tensor(val_targets.reshape(-1, 1), dtype=torch.float32)

    best_state = None
    best_val_loss = math.inf
    best_epoch = 0
    patience = 50
    stale_epochs = 0

    for epoch in range(1, max_epochs + 1):
        model.train()
        optimizer.zero_grad()
        predictions = model(train_tensor)
        train_loss = criterion(predictions, train_target_tensor)
        train_loss.backward()
        optimizer.step()

        model.eval()
        with torch.no_grad():
            val_loss = criterion(model(val_tensor), val_target_tensor).item()

        if val_loss < best_val_loss - 1e-7:
            best_val_loss = val_loss
            best_epoch = epoch
            best_state = {key: value.detach().clone() for key, value in model.state_dict().items()}
            stale_epochs = 0
        else:
            stale_epochs += 1

        if stale_epochs >= patience:
            break

    if best_state is None:
        best_state = model.state_dict()
        best_epoch = max_epochs

    model.load_state_dict(best_state)
    model.eval()
    return model, best_epoch


def train_fixed_epochs(matrix: np.ndarray, targets: np.ndarray, input_dim: int, epochs: int, seed: int) -> PriceForecastNet:
    set_seed(seed)
    model = PriceForecastNet(input_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    criterion = nn.SmoothL1Loss()
    tensor = torch.tensor(matrix, dtype=torch.float32)
    target_tensor = torch.tensor(targets.reshape(-1, 1), dtype=torch.float32)

    for _ in range(max(epochs, 50)):
        model.train()
        optimizer.zero_grad()
        loss = criterion(model(tensor), target_tensor)
        loss.backward()
        optimizer.step()

    model.eval()
    return model


def metrics_for_predictions(actual_pence: np.ndarray, predicted_pence: np.ndarray) -> dict[str, float]:
    return {
        "holdout_rmse_pounds": float(math.sqrt(mean_squared_error(actual_pence / 100.0, predicted_pence / 100.0))),
        "holdout_mape": float(mean_absolute_percentage_error(actual_pence, predicted_pence)),
        "holdout_r2": float(r2_score(actual_pence, predicted_pence)),
    }


def generate_property_forecasts(
    frame: pd.DataFrame,
    model: PriceForecastNet,
    preprocessor,
    metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    forecasts = []
    for record in frame.to_dict(orient="records"):
        payload = {
            "id": record["id"],
            "rightmove_id": record["rightmove_id"],
            "address_line_1": record["address_line_1"],
            "postcode": record["postcode"],
            "price_pence": record["current_price_pence"],
            "price_per_sqft_pence": record["price_per_sqft_pence"],
            "bedrooms": record["bedrooms"],
            "bathrooms": record["bathrooms"],
            "size_sqft": record["size_sqft"],
            "property_type": record["property_type"],
            "tenure": record["tenure"],
            "lease_years_remaining": record["lease_years_remaining"],
            "service_charge_annual_pence": record["service_charge_annual_pence"],
            "latitude": record["latitude"],
            "longitude": record["longitude"],
            "has_floor_plan": bool(record["has_floor_plan"]),
            "has_virtual_tour": bool(record["has_virtual_tour"]),
            "postcode": record["postcode"],
            "address_line_1": record["address_line_1"],
            "status": record["status"],
            "photo_count": record["photo_count"],
            "key_feature_count": record["key_feature_count"],
            "nearest_stations": [
                {
                    "walking_minutes": record["nearest_station_walking_minutes"],
                    "distance_miles": record["nearest_station_distance_miles"],
                }
            ]
            if record["nearest_station_walking_minutes"] is not None or record["nearest_station_distance_miles"] is not None
            else [],
            "crime": {"avg_monthly_crimes": record["crime_avg_monthly"]},
            "air_quality": {"daqi_index": record["air_quality_daqi_index"]},
            "noise": {
                "flight_data": {"metrics": {"lden": record["flight_lden"]}},
                "rail_data": {"metrics": {"lden": record["rail_lden"]}},
                "road_data": {"metrics": {"lden": record["road_lden"]}},
            },
            "area_price_growth": {"area_slug": record["growth_area"]} if record["growth_area"] != "citywide" else None,
            "raw_address": {"outcode": record["postcode"]},
        }
        inference_payload = build_inference_payload(payload, model, preprocessor, metadata)
        inference_payload["id"] = record["id"]
        inference_payload["rightmove_id"] = record["rightmove_id"]
        inference_payload["address_line_1"] = record["address_line_1"]
        inference_payload["postcode"] = record["postcode"]
        forecasts.append(inference_payload)
    return forecasts


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a local one-year house price forecast model.")
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET_PATH, help="Dataset JSON path.")
    parser.add_argument("--artifacts-dir", type=Path, default=DEFAULT_ARTIFACTS_DIR, help="Artifact output directory.")
    parser.add_argument("--collect", action="store_true", help="Export the latest dataset from Rails before training.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    args = parser.parse_args()

    dataset_path = args.dataset.resolve()
    artifacts_dir = args.artifacts_dir.resolve()
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    if args.collect or not dataset_path.exists():
        dataset_path.parent.mkdir(parents=True, exist_ok=True)
        run_dataset_export(dataset_path)

    with dataset_path.open("r", encoding="utf-8") as file_handle:
        dataset_payload = json.load(file_handle)

    growth_reference = build_growth_reference()
    frame = build_dataset_frame(dataset_payload["properties"], growth_reference)
    if len(frame) < 12:
        raise SystemExit(f"Need at least 12 priced properties to train; only found {len(frame)}.")

    active_numeric_features = [feature for feature in NUMERIC_FEATURES if frame[feature].notna().any()]
    active_categorical_features = [feature for feature in CATEGORICAL_FEATURES if frame[feature].notna().any()]
    feature_columns = active_numeric_features + active_categorical_features
    targets = np.log1p(frame["target_future_price_pence"].to_numpy(dtype=np.float64))

    train_indices, test_indices = train_test_split(
        np.arange(len(frame)),
        test_size=max(8, round(len(frame) * 0.2)),
        random_state=args.seed,
    )

    train_frame = frame.iloc[train_indices].reset_index(drop=True)
    test_frame = frame.iloc[test_indices].reset_index(drop=True)

    inner_train_indices, val_indices = train_test_split(
        np.arange(len(train_frame)),
        test_size=max(3, round(len(train_frame) * 0.2)),
        random_state=args.seed,
    )

    dev_preprocessor = make_preprocessor(active_numeric_features, active_categorical_features)
    dev_preprocessor.fit(train_frame[feature_columns])
    dev_train_matrix = matrix_from_frame(dev_preprocessor, train_frame.iloc[inner_train_indices])
    dev_val_matrix = matrix_from_frame(dev_preprocessor, train_frame.iloc[val_indices])
    dev_test_matrix = matrix_from_frame(dev_preprocessor, test_frame)

    dev_train_targets = np.log1p(train_frame.iloc[inner_train_indices]["target_future_price_pence"].to_numpy(dtype=np.float64))
    dev_val_targets = np.log1p(train_frame.iloc[val_indices]["target_future_price_pence"].to_numpy(dtype=np.float64))
    dev_model, best_epoch = train_with_validation(
        dev_train_matrix,
        dev_train_targets,
        dev_val_matrix,
        dev_val_targets,
        seed=args.seed,
    )

    holdout_predictions = stabilize_future_price_predictions(
        predict_future_prices(dev_model, dev_test_matrix),
        test_frame["current_price_pence"].to_numpy(dtype=np.float64),
    )
    holdout_actual = test_frame["target_future_price_pence"].to_numpy(dtype=np.float64)
    training_summary = {
        "sample_count": int(len(frame)),
        "holdout_count": int(len(test_frame)),
        "best_epoch": int(best_epoch),
        "trained_at": datetime.now(timezone.utc).isoformat(),
        **metrics_for_predictions(holdout_actual, holdout_predictions),
    }

    final_preprocessor = make_preprocessor(active_numeric_features, active_categorical_features)
    final_preprocessor.fit(frame[feature_columns])
    final_matrix = matrix_from_frame(final_preprocessor, frame)
    final_model = train_fixed_epochs(final_matrix, targets, final_matrix.shape[1], best_epoch, args.seed)

    final_predictions = stabilize_future_price_predictions(
        predict_future_prices(final_model, final_matrix),
        frame["current_price_pence"].to_numpy(dtype=np.float64),
    )
    training_summary["full_fit_rmse_pounds"] = float(
        math.sqrt(mean_squared_error(frame["target_future_price_pence"].to_numpy(dtype=np.float64) / 100.0, final_predictions / 100.0))
    )

    metadata = {
        "prediction_horizon_months": PREDICTION_HORIZON_MONTHS,
        "target_note": TARGET_NOTE,
        "feature_columns": feature_columns,
        "numeric_features": active_numeric_features,
        "categorical_features": active_categorical_features,
        "transformed_feature_names": final_preprocessor.get_feature_names_out().tolist(),
        "growth_reference": growth_reference,
        "training_summary": training_summary,
    }

    with (artifacts_dir / "preprocessor.pkl").open("wb") as file_handle:
        pickle.dump(final_preprocessor, file_handle)
    torch.save(
        {
            "input_dim": final_matrix.shape[1],
            "state_dict": final_model.state_dict(),
        },
        artifacts_dir / "model.pt",
    )
    with (artifacts_dir / "metadata.json").open("w", encoding="utf-8") as file_handle:
        json.dump(metadata, file_handle, indent=2)

    predictions_output = frame[METADATA_COLUMNS].copy()
    predictions_output["predicted_future_price_pence"] = final_predictions.round().astype(int)
    predictions_output["predicted_growth_pct"] = (
        (predictions_output["predicted_future_price_pence"] / predictions_output["current_price_pence"]) - 1.0
    ) * 100.0
    predictions_output.to_json(artifacts_dir / "training_predictions.json", orient="records", indent=2)

    property_forecasts = generate_property_forecasts(frame, final_model, final_preprocessor, metadata)
    with (artifacts_dir / "property_forecasts.json").open("w", encoding="utf-8") as file_handle:
        json.dump(property_forecasts, file_handle, indent=2)

    print(f"Trained model on {len(frame)} properties")
    print(f"Holdout RMSE: £{training_summary['holdout_rmse_pounds']:,.0f}")
    print(f"Artifacts written to {artifacts_dir}")


if __name__ == "__main__":
    main()
