from __future__ import annotations

import datetime as dt
import json
import math
import os
import pickle
import re
from pathlib import Path
from typing import Any

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("NUMEXPR_NUM_THREADS", "1")
os.environ.setdefault("KMP_INIT_AT_FORK", "FALSE")

import numpy as np
import pandas as pd
import torch
from captum.attr import IntegratedGradients
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from torch import nn

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = PROJECT_ROOT / "backend"
DEFAULT_GROWTH_CSV_PATH = BACKEND_ROOT / "data" / "london_area_house_growth_per_year.csv"
DEFAULT_DATASET_PATH = PROJECT_ROOT / "ml-training" / "data" / "properties.json"
DEFAULT_ARTIFACTS_DIR = PROJECT_ROOT / "ml-training" / "artifacts" / "latest"

PREDICTION_HORIZON_MONTHS = 12
GROWTH_CLIP_MIN = -12.0
GROWTH_CLIP_MAX = 18.0
MIN_RECENT_SALE_PAIRS = 10
TARGET_NOTE = (
    "Targets are proxy one-year prices derived from the current asking price plus a clipped "
    "recent area growth prior. This is a prototype forecast, not observed future sale data."
)

NUMERIC_FEATURES = [
    "current_price_pence",
    "price_per_sqft_pence",
    "bedrooms",
    "bathrooms",
    "size_sqft",
    "lease_years_remaining",
    "service_charge_annual_pence",
    "latitude",
    "longitude",
    "has_floor_plan",
    "has_virtual_tour",
    "photo_count",
    "key_feature_count",
    "growth_prior_pct",
    "growth_sale_pairs",
    "nearest_station_walking_minutes",
    "nearest_station_distance_miles",
    "station_count",
    "crime_avg_monthly",
    "air_quality_daqi_index",
    "flight_lden",
    "rail_lden",
    "road_lden",
]

CATEGORICAL_FEATURES = [
    "property_type",
    "tenure",
    "postcode_outward",
    "growth_area",
    "growth_source",
    "status",
]

METADATA_COLUMNS = [
    "id",
    "rightmove_id",
    "address_line_1",
    "postcode",
    "current_price_pence",
    "target_future_price_pence",
    "growth_prior_pct",
    "growth_area",
    "growth_area_name",
    "growth_source",
]

AREA_ALIASES = {
    "BARKING": "BARKING_AND_DAGENHAM",
    "DAGENHAM": "BARKING_AND_DAGENHAM",
    "HAMMERSMITH": "HAMMERSMITH_AND_FULHAM",
    "FULHAM": "HAMMERSMITH_AND_FULHAM",
    "KENSINGTON": "KENSINGTON_AND_CHELSEA",
    "CHELSEA": "KENSINGTON_AND_CHELSEA",
    "RICHMOND": "RICHMOND_UPON_THAMES",
    "KINGSTON": "KINGSTON_UPON_THAMES",
    "CITY OF LONDON": "CITY_OF_LONDON",
    "CITY_OF_LONDON": "CITY_OF_LONDON",
    "WESTMINSTER": "CITY_OF_WESTMINSTER",
    "ISLINGTON": "ISLINGTON",
    "CAMDEN": "CAMDEN",
    "CROYDON": "CROYDON",
    "ENFIELD": "ENFIELD",
    "NEWHAM": "NEWHAM",
    "WANDSWORTH": "WANDSWORTH",
    "SOUTHWARK": "SOUTHWARK",
    "LAMBETH": "LAMBETH",
    "HOUNSLOW": "HOUNSLOW",
    "HARINGEY": "HARINGEY",
    "EALING": "EALING",
    "BARNET": "BARNET",
    "BRENT": "BRENT",
    "BROMLEY": "BROMLEY",
    "GREENWICH": "GREENWICH",
    "HACKNEY": "HACKNEY",
    "HARROW": "HARROW",
    "HAVERING": "HAVERING",
    "HILLINGDON": "HILLINGDON",
    "LEWISHAM": "LEWISHAM",
    "MERTON": "MERTON",
    "REDBRIDGE": "REDBRIDGE",
    "SUTTON": "SUTTON",
    "TOWER HAMLETS": "TOWER_HAMLETS",
    "TOWER_HAMLETS": "TOWER_HAMLETS",
    "WALTHAM FOREST": "WALTHAM_FOREST",
    "WALTHAM_FOREST": "WALTHAM_FOREST",
}

LOCALITY_ALIASES = {
    "KNIGHTSBRIDGE": "KENSINGTON_AND_CHELSEA",
    "SOUTH KENSINGTON": "KENSINGTON_AND_CHELSEA",
    "NOTTING HILL": "KENSINGTON_AND_CHELSEA",
    "HOLLAND PARK": "KENSINGTON_AND_CHELSEA",
    "BELGRAVIA": "CITY_OF_WESTMINSTER",
    "MAYFAIR": "CITY_OF_WESTMINSTER",
    "MARYLEBONE": "CITY_OF_WESTMINSTER",
    "PADDINGTON": "CITY_OF_WESTMINSTER",
    "BAYSWATER": "CITY_OF_WESTMINSTER",
    "PIMLICO": "CITY_OF_WESTMINSTER",
    "VICTORIA": "CITY_OF_WESTMINSTER",
    "ST JOHN S WOOD": "CITY_OF_WESTMINSTER",
    "ST JOHNS WOOD": "CITY_OF_WESTMINSTER",
    "BRIXTON": "LAMBETH",
    "CLAPHAM": "LAMBETH",
    "BATTERSEA": "WANDSWORTH",
    "WALLINGTON": "SUTTON",
}

POSTCODE_PREFIX_ALIASES = {
    "NW8": "CITY_OF_WESTMINSTER",
    "SM6": "SUTTON",
    "SW10": "KENSINGTON_AND_CHELSEA",
    "SW1W": "CITY_OF_WESTMINSTER",
    "SW1X": "KENSINGTON_AND_CHELSEA",
    "SW2": "LAMBETH",
    "SW7": "KENSINGTON_AND_CHELSEA",
    "SW9": "LAMBETH",
    "W11": "KENSINGTON_AND_CHELSEA",
    "W1D": "CITY_OF_WESTMINSTER",
    "W1G": "CITY_OF_WESTMINSTER",
    "W1J": "CITY_OF_WESTMINSTER",
    "W1K": "CITY_OF_WESTMINSTER",
    "W2": "CITY_OF_WESTMINSTER",
    "W8": "KENSINGTON_AND_CHELSEA",
}

HUMAN_LABELS = {
    "current_price_pence": "Current asking price",
    "price_per_sqft_pence": "Price per sq ft",
    "bedrooms": "Bedrooms",
    "bathrooms": "Bathrooms",
    "size_sqft": "Size",
    "lease_years_remaining": "Lease years remaining",
    "service_charge_annual_pence": "Service charge",
    "latitude": "Latitude",
    "longitude": "Longitude",
    "has_floor_plan": "Has floor plan",
    "has_virtual_tour": "Has virtual tour",
    "photo_count": "Photo count",
    "key_feature_count": "Key feature count",
    "growth_prior_pct": "Area growth prior",
    "growth_sale_pairs": "Recent area sale pairs",
    "nearest_station_walking_minutes": "Nearest station walk time",
    "nearest_station_distance_miles": "Nearest station distance",
    "station_count": "Nearby stations count",
    "crime_avg_monthly": "Crime snapshot",
    "air_quality_daqi_index": "Air quality DAQI",
    "flight_lden": "Flight noise",
    "rail_lden": "Rail noise",
    "road_lden": "Road noise",
}


class PriceForecastNet(nn.Module):
    def __init__(self, input_dim: int) -> None:
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(input_dim, 64),
            nn.ReLU(),
            nn.Dropout(0.08),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Dropout(0.05),
            nn.Linear(32, 1),
        )

    def forward(self, inputs: torch.Tensor) -> torch.Tensor:
        return self.layers(inputs)


def normalise_text(value: Any) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^A-Z0-9 ]+", " ", str(value or "").upper())).strip()


def normalise_slug(value: Any) -> str:
    return normalise_text(value).replace(" ", "_")


def parse_number(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(number) or math.isinf(number):
        return None
    return number


def clip_growth_pct(value: float) -> float:
    return float(np.clip(value, GROWTH_CLIP_MIN, GROWTH_CLIP_MAX))


def make_one_hot_encoder() -> OneHotEncoder:
    try:
        return OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    except TypeError:
        return OneHotEncoder(handle_unknown="ignore", sparse=False)


def extract_outward_code(*values: Any) -> str | None:
    for value in values:
        if not value:
            continue
        first_token = str(value).strip().upper().split()[0]
        match = re.match(r"^[A-Z]{1,2}\d[A-Z0-9]?", first_token)
        if match:
            return match.group(0)
    return None


def extract_noise_metric(noise_payload: dict[str, Any] | None, section: str, metric: str = "lden") -> float | None:
    if not noise_payload:
        return None
    section_payload = noise_payload.get(section) or {}
    metrics = section_payload.get("metrics") or {}
    return parse_number(metrics.get(metric))


def latest_station(stations: list[dict[str, Any]] | None) -> dict[str, Any] | None:
    if not stations:
        return None
    usable = [station for station in stations if station.get("walking_minutes") is not None]
    if usable:
        return sorted(usable, key=lambda station: station.get("walking_minutes"))[0]
    return stations[0]


def weighted_average(values: pd.Series, weights: pd.Series) -> float:
    return float(np.average(values.to_numpy(), weights=weights.to_numpy()))


def build_growth_reference(csv_path: Path = DEFAULT_GROWTH_CSV_PATH) -> dict[str, Any]:
    frame = pd.read_csv(csv_path)
    frame["resale_year"] = pd.to_numeric(frame["resale_year"], errors="coerce")
    frame["average_change_pct_per_year"] = pd.to_numeric(frame["average_change_pct_per_year"], errors="coerce")
    frame["sale_pairs_count"] = pd.to_numeric(frame["sale_pairs_count"], errors="coerce")
    frame["area_slug"] = frame["area_slug"].map(normalise_slug)
    frame = frame.replace([np.inf, -np.inf], np.nan).dropna(
        subset=["resale_year", "average_change_pct_per_year", "sale_pairs_count", "area_slug"]
    )

    current_year = dt.date.today().year
    latest_year = int(frame["resale_year"].max())
    stable_max_year = latest_year - 1 if latest_year >= current_year else latest_year
    stable_max_year = max(int(frame["resale_year"].min()), stable_max_year)
    recent_year_floor = stable_max_year - 2

    recent = frame[
        frame["resale_year"].between(recent_year_floor, stable_max_year)
        & (frame["sale_pairs_count"] >= MIN_RECENT_SALE_PAIRS)
        & frame["average_change_pct_per_year"].between(-50, 50)
    ].copy()

    if recent.empty:
        recent = frame[
            (frame["sale_pairs_count"] >= MIN_RECENT_SALE_PAIRS)
            & frame["average_change_pct_per_year"].between(-50, 50)
        ].copy()

    recent["clipped_growth_pct"] = recent["average_change_pct_per_year"].map(clip_growth_pct)
    recent["clipped_weight"] = recent["sale_pairs_count"].clip(lower=1, upper=1000)

    grouped = recent.groupby("area_slug", as_index=False).apply(
        lambda group: pd.Series(
            {
                "growth_pct": weighted_average(group["clipped_growth_pct"], group["clipped_weight"]),
                "sale_pairs_count": int(group["sale_pairs_count"].sum()),
                "area_name": group["area_name"].iloc[-1],
            }
        ),
        include_groups=False,
    )
    grouped = grouped.reset_index(drop=True)

    citywide_growth_pct = weighted_average(recent["clipped_growth_pct"], recent["clipped_weight"])

    return {
        "recent_year_floor": int(recent["resale_year"].min()),
        "recent_year_ceiling": int(recent["resale_year"].max()),
        "citywide_growth_pct": clip_growth_pct(citywide_growth_pct),
        "growth_pct_by_area": {
            row["area_slug"]: clip_growth_pct(float(row["growth_pct"])) for _, row in grouped.iterrows()
        },
        "sale_pairs_by_area": {row["area_slug"]: int(row["sale_pairs_count"]) for _, row in grouped.iterrows()},
        "area_name_by_slug": {row["area_slug"]: row["area_name"] for _, row in grouped.iterrows()},
    }


def growth_reference_from_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    return {
        "recent_year_floor": metadata["growth_reference"]["recent_year_floor"],
        "recent_year_ceiling": metadata["growth_reference"]["recent_year_ceiling"],
        "citywide_growth_pct": metadata["growth_reference"]["citywide_growth_pct"],
        "growth_pct_by_area": metadata["growth_reference"]["growth_pct_by_area"],
        "sale_pairs_by_area": metadata["growth_reference"]["sale_pairs_by_area"],
        "area_name_by_slug": metadata["growth_reference"]["area_name_by_slug"],
    }


def candidate_texts(record: dict[str, Any]) -> list[str]:
    raw_address = record.get("raw_address") or {}
    items = [
        record.get("address_line_1"),
        record.get("postcode"),
        record.get("town"),
        raw_address.get("display_address"),
        raw_address.get("outcode"),
        raw_address.get("town"),
    ]
    return [normalise_text(item) for item in items if item]


def infer_area_slug(record: dict[str, Any], growth_reference: dict[str, Any]) -> tuple[str | None, str]:
    existing_area = ((record.get("area_price_growth") or {}).get("area_slug") or "").strip()
    if existing_area:
        slug = normalise_slug(existing_area)
        if slug in growth_reference["growth_pct_by_area"]:
            return slug, "linked_area_growth"

    texts = candidate_texts(record)
    joined_text = " ".join(texts)

    for text in texts:
        if text in AREA_ALIASES:
            slug = AREA_ALIASES[text]
            if slug in growth_reference["growth_pct_by_area"]:
                return slug, "address_alias"

    for keyword, slug in LOCALITY_ALIASES.items():
        if keyword in joined_text and slug in growth_reference["growth_pct_by_area"]:
            return slug, "address_locality"

    for slug in growth_reference["growth_pct_by_area"]:
        if slug.replace("_", " ") in joined_text:
            return slug, "address_area_name"

    outward_code = extract_outward_code(record.get("postcode"), (record.get("raw_address") or {}).get("outcode"))
    if outward_code:
        for prefix, slug in POSTCODE_PREFIX_ALIASES.items():
            if outward_code.startswith(prefix) and slug in growth_reference["growth_pct_by_area"]:
                return slug, "postcode_prefix"

    return None, "citywide_fallback"


def resolve_growth_reference(record: dict[str, Any], growth_reference: dict[str, Any]) -> dict[str, Any]:
    area_slug, source = infer_area_slug(record, growth_reference)
    growth_pct_by_area = growth_reference["growth_pct_by_area"]
    area_name_by_slug = growth_reference["area_name_by_slug"]
    sale_pairs_by_area = growth_reference["sale_pairs_by_area"]

    if area_slug and area_slug in growth_pct_by_area:
        return {
            "area_slug": area_slug,
            "area_name": area_name_by_slug.get(area_slug),
            "growth_pct": clip_growth_pct(growth_pct_by_area[area_slug]),
            "sale_pairs_count": int(sale_pairs_by_area.get(area_slug, 0)),
            "source": source,
        }

    return {
        "area_slug": "citywide",
        "area_name": "London-wide fallback",
        "growth_pct": clip_growth_pct(growth_reference["citywide_growth_pct"]),
        "sale_pairs_count": 0,
        "source": "citywide_fallback",
    }


def price_per_sqft_pence(record: dict[str, Any]) -> float | None:
    explicit = parse_number(record.get("price_per_sqft_pence"))
    if explicit:
        return explicit

    price = parse_number(record.get("price_pence"))
    size = parse_number(record.get("size_sqft"))
    if not price or not size:
        return None
    if size <= 0:
        return None
    return price / size


def build_feature_row(record: dict[str, Any], growth_reference: dict[str, Any]) -> dict[str, Any]:
    growth = resolve_growth_reference(record, growth_reference)
    station = latest_station(record.get("nearest_stations"))
    outward_code = extract_outward_code(record.get("postcode"), (record.get("raw_address") or {}).get("outcode"))
    current_price_pence = parse_number(record.get("price_pence"))

    row = {
        "id": record.get("id"),
        "rightmove_id": record.get("rightmove_id"),
        "address_line_1": record.get("address_line_1"),
        "postcode": record.get("postcode"),
        "current_price_pence": current_price_pence,
        "price_per_sqft_pence": price_per_sqft_pence(record),
        "bedrooms": parse_number(record.get("bedrooms")),
        "bathrooms": parse_number(record.get("bathrooms")),
        "size_sqft": parse_number(record.get("size_sqft")),
        "lease_years_remaining": parse_number(record.get("lease_years_remaining")),
        "service_charge_annual_pence": parse_number(record.get("service_charge_annual_pence")),
        "latitude": parse_number(record.get("latitude")),
        "longitude": parse_number(record.get("longitude")),
        "has_floor_plan": 1.0 if record.get("has_floor_plan") else 0.0,
        "has_virtual_tour": 1.0 if record.get("has_virtual_tour") else 0.0,
        "photo_count": float(len(record.get("photo_urls") or [])) if record.get("photo_urls") else parse_number(record.get("photo_count")) or 0.0,
        "key_feature_count": float(len(record.get("key_features") or [])) if record.get("key_features") else parse_number(record.get("key_feature_count")) or 0.0,
        "growth_prior_pct": growth["growth_pct"],
        "growth_sale_pairs": float(growth["sale_pairs_count"]),
        "nearest_station_walking_minutes": parse_number(station.get("walking_minutes") if station else None),
        "nearest_station_distance_miles": parse_number(station.get("distance_miles") if station else None),
        "station_count": float(len(record.get("nearest_stations") or [])),
        "crime_avg_monthly": parse_number((record.get("crime") or {}).get("avg_monthly_crimes")),
        "air_quality_daqi_index": parse_number((record.get("air_quality") or {}).get("daqi_index")),
        "flight_lden": extract_noise_metric(record.get("noise"), "flight_data"),
        "rail_lden": extract_noise_metric(record.get("noise"), "rail_data"),
        "road_lden": extract_noise_metric(record.get("noise"), "road_data"),
        "property_type": (record.get("property_type") or "unknown").strip() or "unknown",
        "tenure": (record.get("tenure") or "unknown").strip() or "unknown",
        "postcode_outward": outward_code or "unknown",
        "growth_area": growth["area_slug"] or "citywide",
        "growth_area_name": growth["area_name"],
        "growth_source": growth["source"],
        "status": (record.get("status") or "unknown").strip() or "unknown",
    }

    if current_price_pence:
        row["target_future_price_pence"] = current_price_pence * (1.0 + growth["growth_pct"] / 100.0)
    else:
        row["target_future_price_pence"] = None

    return row


def build_dataset_frame(properties: list[dict[str, Any]], growth_reference: dict[str, Any]) -> pd.DataFrame:
    rows = [build_feature_row(property_record, growth_reference) for property_record in properties]
    frame = pd.DataFrame(rows)
    if frame.empty:
        return frame
    frame = frame.dropna(subset=["current_price_pence", "target_future_price_pence"]).reset_index(drop=True)
    return frame


def make_preprocessor(numeric_features: list[str], categorical_features: list[str]) -> ColumnTransformer:
    numeric_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )
    categorical_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("one_hot", make_one_hot_encoder()),
        ]
    )
    return ColumnTransformer(
        transformers=[
            ("num", numeric_pipeline, numeric_features),
            ("cat", categorical_pipeline, categorical_features),
        ],
        remainder="drop",
        sparse_threshold=0.0,
    )


def matrix_from_frame(preprocessor: ColumnTransformer, frame: pd.DataFrame) -> np.ndarray:
    transformed = preprocessor.transform(frame[list(preprocessor.feature_names_in_)])
    return np.asarray(transformed, dtype=np.float32)


def predict_log_prices(model: PriceForecastNet, matrix: np.ndarray) -> np.ndarray:
    model.eval()
    with torch.no_grad():
        tensor = torch.tensor(matrix, dtype=torch.float32)
        return model(tensor).cpu().numpy().reshape(-1)


def predict_future_prices(model: PriceForecastNet, matrix: np.ndarray) -> np.ndarray:
    log_predictions = predict_log_prices(model, matrix)
    return np.expm1(log_predictions)


def stabilize_future_price_predictions(predicted_prices: np.ndarray, current_prices: np.ndarray) -> np.ndarray:
    predicted_prices = np.asarray(predicted_prices, dtype=np.float64)
    current_prices = np.asarray(current_prices, dtype=np.float64)
    safe_current_prices = np.where(current_prices > 0, current_prices, np.nan)
    implied_growth_pct = ((predicted_prices / safe_current_prices) - 1.0) * 100.0
    clipped_growth_pct = np.clip(implied_growth_pct, GROWTH_CLIP_MIN, GROWTH_CLIP_MAX)
    stabilized = safe_current_prices * (1.0 + clipped_growth_pct / 100.0)
    return np.where(np.isfinite(stabilized), stabilized, predicted_prices)


def load_artifacts(artifacts_dir: Path) -> tuple[PriceForecastNet, ColumnTransformer, dict[str, Any]]:
    artifacts_dir = Path(artifacts_dir)
    with (artifacts_dir / "metadata.json").open("r", encoding="utf-8") as file_handle:
        metadata = json.load(file_handle)
    with (artifacts_dir / "preprocessor.pkl").open("rb") as file_handle:
        preprocessor = pickle.load(file_handle)
    payload = torch.load(artifacts_dir / "model.pt", map_location="cpu")
    model = PriceForecastNet(int(payload["input_dim"]))
    model.load_state_dict(payload["state_dict"])
    model.eval()
    return model, preprocessor, metadata


def transformed_feature_names(preprocessor: ColumnTransformer) -> list[str]:
    return [str(name) for name in preprocessor.get_feature_names_out()]


def simplify_feature_name(name: str) -> str:
    if name.startswith("num__"):
        return name.replace("num__", "", 1)
    if name.startswith("cat__"):
        return name.replace("cat__", "", 1)
    return name


def humanise_feature_name(name: str) -> str:
    simplified = simplify_feature_name(name)
    if simplified in HUMAN_LABELS:
        return HUMAN_LABELS[simplified]
    if simplified.startswith("property_type_"):
        return f"Property type: {simplified.split('property_type_', 1)[1].replace('_', ' ')}"
    if simplified.startswith("tenure_"):
        return f"Tenure: {simplified.split('tenure_', 1)[1].replace('_', ' ')}"
    if simplified.startswith("postcode_outward_"):
        return f"Postcode area: {simplified.split('postcode_outward_', 1)[1]}"
    if simplified.startswith("growth_area_"):
        return f"Growth area: {simplified.split('growth_area_', 1)[1].replace('_', ' ')}"
    if simplified.startswith("growth_source_"):
        return f"Growth source: {simplified.split('growth_source_', 1)[1].replace('_', ' ')}"
    if simplified.startswith("status_"):
        return f"Status: {simplified.split('status_', 1)[1].replace('_', ' ')}"
    return simplified.replace("_", " ")


def summarize_attributions(
    model: PriceForecastNet,
    transformed_row: np.ndarray,
    feature_names: list[str],
    top_k: int = 8,
) -> tuple[list[dict[str, Any]], float]:
    input_tensor = torch.tensor(transformed_row.reshape(1, -1), dtype=torch.float32)
    baseline_tensor = torch.zeros_like(input_tensor)
    ig = IntegratedGradients(model)
    attributions, delta = ig.attribute(
        input_tensor,
        baselines=baseline_tensor,
        target=0,
        return_convergence_delta=True,
    )
    attribution_values = attributions.detach().cpu().numpy().reshape(-1)
    total_abs = float(np.abs(attribution_values).sum()) or 1.0

    records = []
    for name, value in zip(feature_names, attribution_values, strict=True):
        if abs(value) < 1e-8:
            continue
        records.append(
            {
                "feature": simplify_feature_name(name),
                "label": humanise_feature_name(name),
                "attribution": float(value),
                "direction": "up" if value >= 0 else "down",
                "share_of_abs": float(abs(value) / total_abs),
            }
        )

    records.sort(key=lambda row: abs(row["attribution"]), reverse=True)
    return records[:top_k], float(delta.detach().cpu().numpy().reshape(-1)[0])


def build_inference_payload(
    record: dict[str, Any],
    model: PriceForecastNet,
    preprocessor: ColumnTransformer,
    metadata: dict[str, Any],
    top_k: int = 8,
) -> dict[str, Any]:
    growth_reference = growth_reference_from_metadata(metadata)
    feature_frame = build_dataset_frame([record], growth_reference)

    if feature_frame.empty:
        raise ValueError("Property record is missing the fields required for inference.")

    transformed_row = matrix_from_frame(preprocessor, feature_frame).reshape(1, -1)
    raw_prediction = predict_future_prices(model, transformed_row)
    current_price_pence = float(feature_frame.iloc[0]["current_price_pence"])
    predicted_future_price_pence = float(stabilize_future_price_predictions(raw_prediction, np.array([current_price_pence]))[0])
    baseline_prediction_pence = float(predict_future_prices(model, np.zeros_like(transformed_row))[0])
    feature_names = transformed_feature_names(preprocessor)
    attributions, convergence_delta = summarize_attributions(model, transformed_row[0], feature_names, top_k=top_k)

    predicted_growth_pct = ((predicted_future_price_pence / current_price_pence) - 1.0) * 100.0 if current_price_pence else None

    return {
        "prediction_horizon_months": metadata["prediction_horizon_months"],
        "current_price_pence": int(round(current_price_pence)),
        "predicted_future_price_pence": int(round(predicted_future_price_pence)),
        "predicted_growth_pct": float(predicted_growth_pct) if predicted_growth_pct is not None else None,
        "baseline_prediction_pence": int(round(baseline_prediction_pence)),
        "growth_reference": {
            "matched_area_slug": feature_frame.iloc[0]["growth_area"],
            "matched_area_name": feature_frame.iloc[0]["growth_area_name"],
            "growth_prior_pct": float(feature_frame.iloc[0]["growth_prior_pct"]),
            "growth_source": feature_frame.iloc[0]["growth_source"],
        },
        "training_summary": metadata["training_summary"],
        "target_note": metadata["target_note"],
        "attributions": attributions,
        "attribution_convergence_delta": convergence_delta,
    }
