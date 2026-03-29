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
from sklearn.model_selection import KFold, train_test_split
from torch import nn
from torch.utils.data import DataLoader, TensorDataset

from valuation_pipeline import (
    BACKEND_ROOT,
    CATEGORICAL_FEATURES,
    DEFAULT_VALUATION_ARTIFACTS_DIR,
    DEFAULT_VALUATION_DATASET_PATH,
    DEFAULT_VALUATION_LIVE_DATASET_PATH,
    HouseValuationNet,
    MAX_PREDICTED_LOG_PRICE,
    MIN_PREDICTED_LOG_PRICE,
    NUMERIC_FEATURES,
    TARGET_NOTE,
    build_valuation_inference_payload,
    build_valuation_training_frame,
    interval_quantiles_for_predictions,
    make_preprocessor,
    matrix_from_frame,
    predict_current_prices,
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


def run_live_dataset_collection(
    output_path: Path,
    min_price_gbp: int,
    max_price_gbp: int,
    band_size_gbp: int,
    per_band_limit: int,
    max_listings: int,
    delay_seconds: float,
) -> None:
    env = os.environ.copy()
    env["OUTPUT"] = str(output_path)
    env["MIN_PRICE"] = str(min_price_gbp)
    env["MAX_PRICE"] = str(max_price_gbp)
    env["BAND_SIZE"] = str(band_size_gbp)
    env["PER_BAND_LIMIT"] = str(per_band_limit)
    env["MAX_LISTINGS"] = str(max_listings)
    env["DELAY"] = str(delay_seconds)
    subprocess.run(
        ["mise", "exec", "ruby@3.4.4", "--", "bundle", "exec", "rake", "ml:collect_live_dataset"],
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
    epochs: int = 320,
) -> tuple[HouseValuationNet, int]:
    set_seed(seed)
    model = HouseValuationNet(train_matrix.shape[1])
    optimizer = torch.optim.AdamW(model.parameters(), lr=6e-4, weight_decay=5e-5)
    criterion = nn.SmoothL1Loss()

    batch_size = max(8, min(32, len(train_matrix)))
    train_dataset = TensorDataset(
        torch.tensor(train_matrix, dtype=torch.float32),
        torch.tensor(train_targets.reshape(-1, 1), dtype=torch.float32),
    )
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_inputs = torch.tensor(val_matrix, dtype=torch.float32)
    val_targets_tensor = torch.tensor(val_targets.reshape(-1, 1), dtype=torch.float32)

    best_state = None
    best_epoch = 0
    best_val_loss = math.inf
    patience = 40
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


def train_fixed_epochs(matrix: np.ndarray, targets: np.ndarray, input_dim: int, epochs: int, seed: int) -> HouseValuationNet:
    set_seed(seed)
    model = HouseValuationNet(input_dim)
    optimizer = torch.optim.AdamW(model.parameters(), lr=6e-4, weight_decay=5e-5)
    criterion = nn.SmoothL1Loss()
    dataset = TensorDataset(
        torch.tensor(matrix, dtype=torch.float32),
        torch.tensor(targets.reshape(-1, 1), dtype=torch.float32),
    )
    loader = DataLoader(dataset, batch_size=max(8, min(32, len(matrix))), shuffle=True)

    for _ in range(max(epochs, 40)):
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
        "oof_rmse_pounds": float(math.sqrt(mean_squared_error(actual_pence / 100.0, predicted_pence / 100.0))),
        "oof_mape": float(mean_absolute_percentage_error(actual_pence, predicted_pence)),
        "oof_r2": float(r2_score(actual_pence, predicted_pence)),
    }


def prediction_log_price_bounds(targets: np.ndarray) -> dict[str, float]:
    lower = max(MIN_PREDICTED_LOG_PRICE, float(np.quantile(targets, 0.005) - 0.08))
    upper = min(MAX_PREDICTED_LOG_PRICE, float(np.quantile(targets, 0.995) + 0.08))
    return {"lower": lower, "upper": max(lower + 0.1, upper)}


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a current-price valuation model on the exported listings dataset.")
    parser.add_argument("--collect", action="store_true", help="Export the latest current-property dataset from Rails.")
    parser.add_argument(
        "--collect-live",
        action="store_true",
        help="Collect a larger live Rightmove current-listings dataset before training.",
    )
    parser.add_argument("--artifacts-dir", type=Path, default=DEFAULT_VALUATION_ARTIFACTS_DIR, help="Artifact output directory.")
    parser.add_argument("--listings-path", type=Path, default=DEFAULT_VALUATION_DATASET_PATH, help="Current listings dataset path.")
    parser.add_argument("--live-listings-path", type=Path, default=DEFAULT_VALUATION_LIVE_DATASET_PATH, help="Collected live listings dataset path.")
    parser.add_argument("--live-min-price-gbp", type=int, default=200_000, help="Minimum listing price for live collection.")
    parser.add_argument("--live-max-price-gbp", type=int, default=10_000_000, help="Maximum listing price for live collection.")
    parser.add_argument("--live-band-size-gbp", type=int, default=250_000, help="Price band width for live collection.")
    parser.add_argument("--live-per-band-limit", type=int, default=30, help="Maximum ids to collect per price band.")
    parser.add_argument("--live-max-listings", type=int, default=1_200, help="Maximum listing payloads to fetch.")
    parser.add_argument("--live-delay-seconds", type=float, default=0.15, help="Delay between live listing fetches.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed.")
    args = parser.parse_args()

    artifacts_dir = args.artifacts_dir.resolve()
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    listings_path = args.listings_path.resolve()
    if args.collect_live:
        listings_path = args.live_listings_path.resolve()
        listings_path.parent.mkdir(parents=True, exist_ok=True)
        run_live_dataset_collection(
            listings_path,
            min_price_gbp=args.live_min_price_gbp,
            max_price_gbp=args.live_max_price_gbp,
            band_size_gbp=args.live_band_size_gbp,
            per_band_limit=args.live_per_band_limit,
            max_listings=args.live_max_listings,
            delay_seconds=args.live_delay_seconds,
        )
    elif args.collect or not listings_path.exists():
        listings_path.parent.mkdir(parents=True, exist_ok=True)
        run_dataset_export(listings_path)

    training_frame = build_valuation_training_frame(listings_path)
    if len(training_frame) < 20:
        raise SystemExit(f"Need at least 20 priced properties to train valuation model; only found {len(training_frame)}.")

    fold_count = min(5, max(3, len(training_frame) // 8))
    minimum_observed_values = max(3, fold_count)
    active_numeric_features = [
        feature
        for feature in NUMERIC_FEATURES
        if feature in training_frame.columns
        and training_frame[feature].notna().sum() >= minimum_observed_values
        and training_frame[feature].notna().any()
        and training_frame[feature].nunique(dropna=False) > 1
    ]
    active_categorical_features = [
        feature
        for feature in CATEGORICAL_FEATURES
        if feature in training_frame.columns
        and training_frame[feature].notna().sum() >= 2
        and training_frame[feature].fillna("missing").nunique() > 1
    ]
    feature_columns = active_numeric_features + active_categorical_features
    if not feature_columns:
        raise SystemExit("No varying features were available to train the valuation model.")

    with listings_path.open("r", encoding="utf-8") as file_handle:
        listing_payload = json.load(file_handle)

    targets = np.log1p(training_frame["target_price_pence"].to_numpy(dtype=np.float64))
    actual_prices = training_frame["target_price_pence"].to_numpy(dtype=np.float64)
    log_price_bounds = prediction_log_price_bounds(targets)
    prediction_metadata = {"prediction_log_price_bounds": log_price_bounds}

    kfold = KFold(n_splits=fold_count, shuffle=True, random_state=args.seed)

    oof_predictions = np.zeros(len(training_frame), dtype=np.float64)
    fold_assignments: dict[str, str] = {}
    fold_models_payload: dict[str, Any] = {}
    fold_preprocessors: dict[str, Any] = {}
    best_epochs: list[int] = []

    for fold_index, (train_indices, val_indices) in enumerate(kfold.split(training_frame), start=1):
        train_frame = training_frame.iloc[train_indices].reset_index(drop=True)
        val_frame = training_frame.iloc[val_indices].reset_index(drop=True)

        inner_train_indices, inner_val_indices = train_test_split(
            np.arange(len(train_frame)),
            test_size=max(2, min(len(train_frame) // 3, round(len(train_frame) * 0.2))),
            random_state=args.seed + fold_index,
        )

        fold_preprocessor = make_preprocessor(active_numeric_features, active_categorical_features)
        fold_preprocessor.fit(train_frame[feature_columns])

        dev_train_matrix = matrix_from_frame(fold_preprocessor, train_frame.iloc[inner_train_indices])
        dev_val_matrix = matrix_from_frame(fold_preprocessor, train_frame.iloc[inner_val_indices])
        dev_train_targets = np.log1p(
            train_frame.iloc[inner_train_indices]["target_price_pence"].to_numpy(dtype=np.float64)
        )
        dev_val_targets = np.log1p(
            train_frame.iloc[inner_val_indices]["target_price_pence"].to_numpy(dtype=np.float64)
        )

        _, best_epoch = train_with_validation(
            dev_train_matrix,
            dev_train_targets,
            dev_val_matrix,
            dev_val_targets,
            seed=args.seed + fold_index,
        )
        best_epochs.append(best_epoch)

        full_fold_matrix = matrix_from_frame(fold_preprocessor, train_frame)
        full_fold_targets = np.log1p(train_frame["target_price_pence"].to_numpy(dtype=np.float64))
        fold_model = train_fixed_epochs(
            full_fold_matrix,
            full_fold_targets,
            full_fold_matrix.shape[1],
            best_epoch,
            seed=args.seed + fold_index,
        )

        val_matrix = matrix_from_frame(fold_preprocessor, val_frame)
        val_predictions = predict_current_prices(fold_model, val_matrix, prediction_metadata)
        oof_predictions[val_indices] = val_predictions

        fold_key = str(fold_index)
        fold_models_payload[fold_key] = {
            "input_dim": int(full_fold_matrix.shape[1]),
            "state_dict": fold_model.state_dict(),
        }
        fold_preprocessors[fold_key] = fold_preprocessor

        for sample_id in training_frame.iloc[val_indices]["sample_id"]:
            fold_assignments[str(sample_id)] = fold_key

    final_preprocessor = make_preprocessor(active_numeric_features, active_categorical_features)
    final_preprocessor.fit(training_frame[feature_columns])
    final_matrix = matrix_from_frame(final_preprocessor, training_frame)
    final_epochs = int(round(float(np.median(best_epochs)))) if best_epochs else 40
    final_model = train_fixed_epochs(final_matrix, targets, final_matrix.shape[1], final_epochs, args.seed)
    final_predictions = predict_current_prices(final_model, final_matrix, prediction_metadata)

    prediction_intervals = interval_quantiles_for_predictions(actual_prices, oof_predictions)
    data_source = str(listing_payload.get("source") or "current_listings")
    if data_source == "rightmove_live_collection":
        training_basis = "rightmove_live_structured_valuation"
    elif data_source == "rightmove_live_plus_local_export":
        training_basis = "rightmove_live_plus_local_export_valuation"
    else:
        training_basis = "current_listings_structured_valuation"
    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "training_basis": training_basis,
        "data_source": data_source,
        "target_note": TARGET_NOTE,
        "sample_count": int(len(training_frame)),
        "feature_columns": feature_columns,
        "numeric_features": active_numeric_features,
        "categorical_features": active_categorical_features,
        "transformed_feature_names": final_preprocessor.get_feature_names_out().tolist(),
        "sample_fold_assignments": fold_assignments,
        "prediction_intervals": prediction_intervals,
        "prediction_log_price_bounds": log_price_bounds,
        "best_epoch_median": final_epochs,
        **metrics_for_predictions(actual_prices, oof_predictions),
        "full_fit_rmse_pounds": float(
            math.sqrt(mean_squared_error(actual_prices / 100.0, final_predictions / 100.0))
        ),
    }

    with (artifacts_dir / "preprocessor.pkl").open("wb") as file_handle:
        pickle.dump(final_preprocessor, file_handle)
    torch.save(
        {
            "input_dim": int(final_matrix.shape[1]),
            "state_dict": final_model.state_dict(),
        },
        artifacts_dir / "model.pt",
    )
    with (artifacts_dir / "metadata.json").open("w", encoding="utf-8") as file_handle:
        json.dump(metadata, file_handle, indent=2)
    with (artifacts_dir / "fold_preprocessors.pkl").open("wb") as file_handle:
        pickle.dump(fold_preprocessors, file_handle)
    torch.save({"models": fold_models_payload}, artifacts_dir / "fold_models.pt")

    prediction_rows = training_frame[["sample_id", "target_price_pence"]].copy()
    prediction_rows["predicted_current_price_pence"] = oof_predictions.round().astype(int)
    prediction_rows["full_model_prediction_pence"] = final_predictions.round().astype(int)
    prediction_rows["pricing_gap_pence"] = (
        prediction_rows["target_price_pence"] - prediction_rows["predicted_current_price_pence"]
    ).astype(int)
    with (artifacts_dir / "valuation_predictions.json").open("w", encoding="utf-8") as file_handle:
        json.dump(prediction_rows.to_dict(orient="records"), file_handle, indent=2)

    runtime_fold_models: dict[str, HouseValuationNet] = {}
    for fold_key, fold_payload in fold_models_payload.items():
        runtime_model = HouseValuationNet(int(fold_payload["input_dim"]))
        runtime_model.load_state_dict(fold_payload["state_dict"])
        runtime_model.eval()
        runtime_fold_models[fold_key] = runtime_model

    property_valuations = []
    for record in listing_payload.get("properties", []):
        try:
            result = build_valuation_inference_payload(
                record,
                final_model,
                final_preprocessor,
                metadata,
                fold_models=runtime_fold_models,
                fold_preprocessors=fold_preprocessors,
            )
        except ValueError:
            continue
        result["id"] = record.get("id")
        result["rightmove_id"] = record.get("rightmove_id")
        property_valuations.append(result)

    with (artifacts_dir / "property_valuations.json").open("w", encoding="utf-8") as file_handle:
        json.dump(property_valuations, file_handle, indent=2)

    print(f"Trained valuation model on {len(training_frame)} properties")
    print(f"OOF RMSE £{round(metadata['oof_rmse_pounds']):,} | OOF MAPE {metadata['oof_mape']:.3f}")
    print(f"Artifacts written to {artifacts_dir}")


if __name__ == "__main__":
    main()
