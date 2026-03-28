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
import torch
from sklearn.metrics import mean_absolute_percentage_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from torch import nn
from torch.utils.data import DataLoader, TensorDataset

from pipeline import (
    BACKEND_ROOT,
    CATEGORICAL_FEATURES,
    DEFAULT_ARTIFACTS_DIR,
    DEFAULT_CURRENT_LISTINGS_PATH,
    DEFAULT_PPD_YEARS,
    DEFAULT_FILTERED_PPD_PATH,
    METADATA_COLUMNS,
    NUMERIC_FEATURES,
    PREDICTION_HORIZON_MONTHS,
    PriceForecastNet,
    TARGET_NOTE,
    UK_HPI_FULL_FILE_URL,
    build_current_listing_frame,
    build_filtered_ppd_cache,
    build_hpi_context,
    build_inference_payload,
    build_training_frame,
    ensure_hpi_download,
    make_preprocessor,
    matrix_from_frame,
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
    epochs: int = 25,
) -> tuple[PriceForecastNet, int]:
    set_seed(seed)
    model = PriceForecastNet(train_matrix.shape[1])
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    criterion = nn.SmoothL1Loss()

    train_dataset = TensorDataset(
        torch.tensor(train_matrix, dtype=torch.float32),
        torch.tensor(train_targets.reshape(-1, 1), dtype=torch.float32),
    )
    train_loader = DataLoader(train_dataset, batch_size=2048, shuffle=True)
    val_inputs = torch.tensor(val_matrix, dtype=torch.float32)
    val_targets_tensor = torch.tensor(val_targets.reshape(-1, 1), dtype=torch.float32)

    best_state = None
    best_val_loss = math.inf
    best_epoch = 0
    patience = 5
    stale_epochs = 0

    for epoch in range(1, epochs + 1):
        model.train()
        for batch_inputs, batch_targets in train_loader:
            optimizer.zero_grad()
            loss = criterion(model(batch_inputs), batch_targets)
            loss.backward()
            optimizer.step()

        model.eval()
        with torch.no_grad():
            val_loss = criterion(model(val_inputs), val_targets_tensor).item()

        if val_loss < best_val_loss - 1e-6:
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
        best_epoch = epochs

    model.load_state_dict(best_state)
    model.eval()
    return model, best_epoch


def train_fixed_epochs(matrix: np.ndarray, targets: np.ndarray, input_dim: int, epochs: int, seed: int) -> PriceForecastNet:
    set_seed(seed)
    model = PriceForecastNet(input_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    criterion = nn.SmoothL1Loss()
    dataset = TensorDataset(
        torch.tensor(matrix, dtype=torch.float32),
        torch.tensor(targets.reshape(-1, 1), dtype=torch.float32),
    )
    loader = DataLoader(dataset, batch_size=2048, shuffle=True)

    for _ in range(max(epochs, 8)):
        model.train()
        for batch_inputs, batch_targets in loader:
            optimizer.zero_grad()
            loss = criterion(model(batch_inputs), batch_targets)
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


def generate_listing_forecasts(
    listings_path: Path,
    model: PriceForecastNet,
    preprocessor,
    metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    if not listings_path.exists():
        return []

    with listings_path.open("r", encoding="utf-8") as file_handle:
        listing_payload = json.load(file_handle)

    forecasts = []
    for record in listing_payload.get("properties", []):
        frame = build_current_listing_frame(record, metadata)
        if frame.empty:
            continue
        result = build_inference_payload(record, model, preprocessor, metadata)
        result["id"] = record.get("id")
        result["rightmove_id"] = record.get("rightmove_id")
        result["address_line_1"] = record.get("address_line_1")
        result["postcode"] = record.get("postcode")
        forecasts.append(result)
    return forecasts


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a one-year house-price forecast model on historical Land Registry data.")
    parser.add_argument("--collect", action="store_true", help="Export the latest current-property dataset from Rails.")
    parser.add_argument("--artifacts-dir", type=Path, default=DEFAULT_ARTIFACTS_DIR, help="Artifact output directory.")
    parser.add_argument("--listings-path", type=Path, default=DEFAULT_CURRENT_LISTINGS_PATH, help="Current listings dataset path.")
    parser.add_argument("--filtered-ppd-path", type=Path, default=DEFAULT_FILTERED_PPD_PATH, help="Filtered London PPD cache path.")
    parser.add_argument("--sample-limit", type=int, default=120_000, help="Maximum historical training rows to sample.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    args = parser.parse_args()

    artifacts_dir = args.artifacts_dir.resolve()
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    if args.collect or not args.listings_path.exists():
        args.listings_path.parent.mkdir(parents=True, exist_ok=True)
        run_dataset_export(args.listings_path.resolve())

    hpi_path = ensure_hpi_download()
    hpi_context = build_hpi_context(hpi_path)
    filtered_ppd_path = build_filtered_ppd_cache(hpi_context, output_path=args.filtered_ppd_path.resolve())
    training_frame = build_training_frame(
        hpi_context,
        filtered_ppd_path=filtered_ppd_path,
        sample_limit=args.sample_limit,
        seed=args.seed,
    )

    if len(training_frame) < 1_000:
        raise SystemExit(f"Need at least 1000 historical rows to train; only found {len(training_frame)}.")

    active_numeric_features = [feature for feature in NUMERIC_FEATURES if training_frame[feature].notna().any()]
    active_categorical_features = [feature for feature in CATEGORICAL_FEATURES if training_frame[feature].notna().any()]
    feature_columns = active_numeric_features + active_categorical_features
    targets = np.log1p(training_frame["target_future_price_pence"].to_numpy(dtype=np.float64))

    train_indices, test_indices = train_test_split(
        np.arange(len(training_frame)),
        test_size=min(max(5_000, round(len(training_frame) * 0.2)), len(training_frame) // 3),
        random_state=args.seed,
    )

    train_frame = training_frame.iloc[train_indices].reset_index(drop=True)
    test_frame = training_frame.iloc[test_indices].reset_index(drop=True)

    inner_train_indices, val_indices = train_test_split(
        np.arange(len(train_frame)),
        test_size=min(max(2_500, round(len(train_frame) * 0.1)), len(train_frame) // 4),
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
        "sample_count": int(len(training_frame)),
        "holdout_count": int(len(test_frame)),
        "best_epoch": int(best_epoch),
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "historical_years": list(DEFAULT_PPD_YEARS),
        **metrics_for_predictions(holdout_actual, holdout_predictions),
    }

    final_preprocessor = make_preprocessor(active_numeric_features, active_categorical_features)
    final_preprocessor.fit(training_frame[feature_columns])
    final_matrix = matrix_from_frame(final_preprocessor, training_frame)
    final_model = train_fixed_epochs(final_matrix, targets, final_matrix.shape[1], best_epoch, args.seed)

    final_predictions = stabilize_future_price_predictions(
        predict_future_prices(final_model, final_matrix),
        training_frame["current_price_pence"].to_numpy(dtype=np.float64),
    )
    training_summary["full_fit_rmse_pounds"] = float(
        math.sqrt(mean_squared_error(training_frame["target_future_price_pence"].to_numpy(dtype=np.float64) / 100.0, final_predictions / 100.0))
    )

    metadata = {
        "prediction_horizon_months": PREDICTION_HORIZON_MONTHS,
        "target_note": TARGET_NOTE,
        "feature_columns": feature_columns,
        "numeric_features": active_numeric_features,
        "categorical_features": active_categorical_features,
        "transformed_feature_names": final_preprocessor.get_feature_names_out().tolist(),
        "training_summary": training_summary,
        "training_basis": "historical_land_registry_hpi",
        "latest_hpi_period": hpi_context["latest_period"],
        "area_name_by_slug": hpi_context["area_name_by_slug"],
        "latest_hpi_snapshot": hpi_context["latest_snapshot"],
        "historical_source": {
            "uk_hpi_url": UK_HPI_FULL_FILE_URL,
            "ppd_years": list(DEFAULT_PPD_YEARS),
        },
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

    predictions_output = training_frame[METADATA_COLUMNS].copy()
    predictions_output["predicted_future_price_pence"] = final_predictions.round().astype(int)
    predictions_output["predicted_growth_pct"] = (
        (predictions_output["predicted_future_price_pence"] / predictions_output["current_price_pence"]) - 1.0
    ) * 100.0
    predictions_output.to_json(artifacts_dir / "training_predictions.json", orient="records", indent=2)

    listing_forecasts = generate_listing_forecasts(args.listings_path.resolve(), final_model, final_preprocessor, metadata)
    with (artifacts_dir / "property_forecasts.json").open("w", encoding="utf-8") as file_handle:
        json.dump(listing_forecasts, file_handle, indent=2)

    print(f"Trained model on {len(training_frame)} historical rows")
    print(f"Holdout RMSE: £{training_summary['holdout_rmse_pounds']:,.0f}")
    print(f"Artifacts written to {artifacts_dir}")


if __name__ == "__main__":
    main()
