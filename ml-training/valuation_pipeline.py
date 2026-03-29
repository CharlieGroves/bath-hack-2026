from __future__ import annotations

import html
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
from sklearn.compose import ColumnTransformer
from torch import nn

from pipeline import (
    BACKEND_ROOT,
    DEFAULT_CURRENT_LISTINGS_PATH,
    PROJECT_ROOT,
    extract_outward_code,
    make_preprocessor,
    matrix_from_frame,
    parse_number,
)

DEFAULT_VALUATION_DATASET_PATH = DEFAULT_CURRENT_LISTINGS_PATH
DEFAULT_VALUATION_ARTIFACTS_DIR = PROJECT_ROOT / "ml-training" / "artifacts" / "valuation" / "latest"
INTEGRATED_GRADIENTS_STEPS = 48
MIN_PREDICTED_LOG_PRICE = 14.0
MAX_PREDICTED_LOG_PRICE = 23.5

TEXT_FLAG_PATTERNS = {
    "has_garden": (r"\bgarden\b",),
    "has_terrace": (r"\bterrace\b", r"\broof terrace\b"),
    "has_balcony": (r"\bbalcony\b",),
    "has_patio": (r"\bpatio\b",),
    "has_parking": (r"\bparking\b", r"\boff[- ]street\b", r"\ballocated parking\b"),
    "has_garage": (r"\bgarage\b",),
    "has_lift": (r"\blift\b", r"\belevator\b"),
    "has_porter": (r"\bporter\b",),
    "has_concierge": (r"\bconcierge\b",),
    "has_gym": (r"\bgym\b",),
    "has_pool": (r"\bpool\b", r"\bswimming pool\b"),
    "has_sauna": (r"\bsauna\b",),
    "has_jacuzzi": (r"\bjacuzzi\b", r"\bhot tub\b"),
    "has_study": (r"\bstudy\b", r"\boffice\b"),
    "has_cinema": (r"\bcinema\b", r"\bmedia room\b"),
    "has_air_conditioning": (r"\bair conditioning\b", r"\ba/c\b", r"\bcentral a/c\b"),
    "has_underfloor_heating": (r"\bunderfloor heating\b",),
    "has_high_ceilings": (r"\bhigh ceilings\b",),
    "has_wood_floors": (r"\bwood(?:en)? floors\b",),
    "has_new_home": (r"\bnew home\b", r"\bnew build\b"),
    "has_listed_building": (r"\bgrade [ivx]+\b listed\b", r"\blisted building\b"),
    "has_share_of_freehold": (r"\bshare of freehold\b",),
    "has_split_level": (r"\bsplit[- ]level\b",),
}

NUMERIC_FEATURES = [
    "bedrooms",
    "bathrooms",
    "size_sqft",
    "sqft_per_bedroom",
    "bathrooms_per_bedroom",
    "lease_years_remaining",
    "service_charge_annual_pence",
    "latitude",
    "longitude",
    "photo_count",
    "key_feature_count",
    "description_word_count",
    "title_word_count",
    "reception_rooms_count",
    "feature_amenity_count",
    "garden_feature_count",
    "parking_feature_count",
    "heating_feature_count",
    "station_count",
    "min_station_distance_miles",
    "avg_station_distance_miles",
    "min_station_walking_minutes",
    "avg_station_walking_minutes",
    "road_noise_lden",
    "rail_noise_lden",
    "flight_noise_lden",
    "avg_monthly_crimes",
    "air_quality_daqi_index",
    "area_growth_latest_pct",
    "borough_nte_score",
    "borough_life_satisfaction_score",
    "borough_happiness_score",
    "borough_anxiety_score",
    "estate_agent_rating",
    "has_floor_plan",
    "has_virtual_tour",
    "has_garden",
    "has_terrace",
    "has_balcony",
    "has_patio",
    "has_parking",
    "has_garage",
    "has_lift",
    "has_porter",
    "has_concierge",
    "has_gym",
    "has_pool",
    "has_sauna",
    "has_jacuzzi",
    "has_study",
    "has_cinema",
    "has_air_conditioning",
    "has_underfloor_heating",
    "has_high_ceilings",
    "has_wood_floors",
    "has_new_home",
    "has_listed_building",
    "has_share_of_freehold",
    "has_split_level",
]

CATEGORICAL_FEATURES = [
    "property_type",
    "tenure",
    "postcode_outward",
    "town_slug",
    "epc_rating",
    "council_tax_band",
]

TARGET_NOTE = (
    "Model trained on the current property dataset exported from Rails. It predicts the current fair-value "
    "listing price from house characteristics and local context rather than future appreciation."
)

DISPLAY_LABELS = {
    "bedrooms": "Bedrooms",
    "bathrooms": "Bathrooms",
    "size_sqft": "Size (sq ft)",
    "sqft_per_bedroom": "Sq ft per bedroom",
    "bathrooms_per_bedroom": "Bathrooms per bedroom",
    "lease_years_remaining": "Lease years remaining",
    "service_charge_annual_pence": "Service charge",
    "latitude": "Latitude",
    "longitude": "Longitude",
    "photo_count": "Photo count",
    "key_feature_count": "Key feature count",
    "description_word_count": "Description length",
    "title_word_count": "Title length",
    "reception_rooms_count": "Reception rooms",
    "feature_amenity_count": "Amenity count",
    "garden_feature_count": "Structured garden tags",
    "parking_feature_count": "Structured parking tags",
    "heating_feature_count": "Structured heating tags",
    "station_count": "Nearby station count",
    "min_station_distance_miles": "Nearest station distance",
    "avg_station_distance_miles": "Average station distance",
    "min_station_walking_minutes": "Nearest station walking time",
    "avg_station_walking_minutes": "Average station walking time",
    "road_noise_lden": "Road noise",
    "rail_noise_lden": "Rail noise",
    "flight_noise_lden": "Flight noise",
    "avg_monthly_crimes": "Nearby crime rate",
    "air_quality_daqi_index": "Air quality index",
    "area_growth_latest_pct": "Area growth",
    "borough_nte_score": "Borough NTE score",
    "borough_life_satisfaction_score": "Borough life satisfaction",
    "borough_happiness_score": "Borough happiness",
    "borough_anxiety_score": "Borough anxiety",
    "estate_agent_rating": "Agent rating",
    "property_type": "Property type",
    "tenure": "Tenure",
    "postcode_outward": "Postcode area",
    "town_slug": "Town",
    "epc_rating": "EPC rating",
    "council_tax_band": "Council tax band",
    "has_floor_plan": "Has floor plan",
    "has_virtual_tour": "Has virtual tour",
    "has_garden": "Garden",
    "has_terrace": "Terrace",
    "has_balcony": "Balcony",
    "has_patio": "Patio",
    "has_parking": "Parking",
    "has_garage": "Garage",
    "has_lift": "Lift",
    "has_porter": "Porter",
    "has_concierge": "Concierge",
    "has_gym": "Gym",
    "has_pool": "Pool",
    "has_sauna": "Sauna",
    "has_jacuzzi": "Jacuzzi",
    "has_study": "Study",
    "has_cinema": "Cinema room",
    "has_air_conditioning": "Air conditioning",
    "has_underfloor_heating": "Underfloor heating",
    "has_high_ceilings": "High ceilings",
    "has_wood_floors": "Wood floors",
    "has_new_home": "New home",
    "has_listed_building": "Listed building",
    "has_share_of_freehold": "Share of freehold",
    "has_split_level": "Split level",
}


class HouseValuationNet(nn.Module):
    def __init__(self, input_dim: int) -> None:
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(input_dim, 96),
            nn.ReLU(),
            nn.Dropout(0.12),
            nn.Linear(96, 48),
            nn.ReLU(),
            nn.Dropout(0.08),
            nn.Linear(48, 1),
        )

    def forward(self, inputs: torch.Tensor) -> torch.Tensor:
        return self.layers(inputs)


def normalise_text(value: Any) -> str:
    return re.sub(r"\s+", " ", html.unescape(str(value or "")).strip()).lower()


def title_case_label(value: str) -> str:
    return value.replace("_", " ").strip().title()


def sample_id_for_record(record: dict[str, Any]) -> str:
    return str(record.get("rightmove_id") or record.get("id") or "property")


def latest_area_growth_pct(area_price_growth: dict[str, Any] | None) -> float | None:
    yearly_growth = (area_price_growth or {}).get("yearly_growth_data") or {}
    latest_year = None
    latest_value = None
    for year, payload in yearly_growth.items():
        try:
            year_int = int(year)
        except (TypeError, ValueError):
            continue
        pct = parse_number((payload or {}).get("average_change_pct_per_year"))
        if pct is None:
            continue
        if latest_year is None or year_int > latest_year:
            latest_year = year_int
            latest_value = pct
    return latest_value


def structured_feature_entries(raw_property_data: dict[str, Any], group: str) -> list[dict[str, Any]]:
    features = raw_property_data.get("features") or {}
    entries = features.get(group)
    return entries if isinstance(entries, list) else []


def canonical_size_sqft(record: dict[str, Any], raw_property_data: dict[str, Any]) -> float | None:
    direct_size = parse_number(record.get("size_sqft"))
    if direct_size:
        return direct_size

    sized_values: dict[str, float] = {}
    for sizing in raw_property_data.get("sizings") or []:
        unit = str(sizing.get("unit") or "").strip().lower()
        value = parse_number(sizing.get("maximumSize")) or parse_number(sizing.get("minimumSize"))
        if not unit or value is None:
            continue
        sized_values[unit] = value

    if "sqft" in sized_values:
        return sized_values["sqft"]
    if "sqm" in sized_values:
        return sized_values["sqm"] * 10.7639
    if "ac" in sized_values:
        return sized_values["ac"] * 43_560.0
    if "ha" in sized_values:
        return sized_values["ha"] * 107_639.104
    return None


def station_summary(record: dict[str, Any]) -> dict[str, float | None]:
    stations = record.get("nearest_stations") or []
    distances = [parse_number(station.get("distance_miles")) for station in stations]
    walking_minutes = [parse_number(station.get("walking_minutes")) for station in stations]
    distances = [value for value in distances if value is not None]
    walking_minutes = [value for value in walking_minutes if value is not None]
    return {
        "station_count": float(len(stations)),
        "min_station_distance_miles": min(distances) if distances else None,
        "avg_station_distance_miles": float(np.mean(distances)) if distances else None,
        "min_station_walking_minutes": min(walking_minutes) if walking_minutes else None,
        "avg_station_walking_minutes": float(np.mean(walking_minutes)) if walking_minutes else None,
    }


def noise_metric(record: dict[str, Any], key: str) -> float | None:
    noise = record.get("noise") or {}
    section = noise.get(key) or {}
    metrics = section.get("metrics") or {}
    return parse_number(metrics.get("lden"))


def combined_feature_text(record: dict[str, Any], raw_property_data: dict[str, Any]) -> str:
    fragments: list[str] = []
    for value in (
        record.get("title"),
        record.get("description"),
        record.get("parking_text"),
        record.get("utilities_text"),
        " ".join(str(feature) for feature in record.get("key_features") or []),
    ):
        text = normalise_text(value)
        if text:
            fragments.append(text)

    for group in ("garden", "parking", "heating", "accessibility"):
        for entry in structured_feature_entries(raw_property_data, group):
            text = normalise_text(entry.get("displayText") or entry.get("alias"))
            if text:
                fragments.append(text)

    for tag in raw_property_data.get("tags") or []:
        text = normalise_text(tag)
        if text:
            fragments.append(text)

    return " ".join(fragments)


def parse_number_word(value: str) -> int | None:
    value = normalise_text(value)
    if value.isdigit():
        return int(value)
    word_map = {
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
    }
    return word_map.get(value)


def extract_count_from_text(text: str, patterns: tuple[str, ...]) -> float | None:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if not match:
            continue
        value = parse_number_word(match.group(1))
        if value is not None:
            return float(value)
    return None


def keyword_flag(text: str, patterns: tuple[str, ...]) -> float:
    return 1.0 if any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns) else 0.0


def text_boolean_flags(text: str, raw_property_data: dict[str, Any], record: dict[str, Any]) -> dict[str, float]:
    flags = {feature: keyword_flag(text, patterns) for feature, patterns in TEXT_FLAG_PATTERNS.items()}

    parking_aliases = {normalise_text(entry.get("alias")) for entry in structured_feature_entries(raw_property_data, "parking")}
    garden_aliases = {normalise_text(entry.get("alias") or entry.get("displayText")) for entry in structured_feature_entries(raw_property_data, "garden")}
    heating_aliases = {normalise_text(entry.get("alias")) for entry in structured_feature_entries(raw_property_data, "heating")}
    accessibility_aliases = {
        normalise_text(entry.get("alias") or entry.get("displayText"))
        for entry in structured_feature_entries(raw_property_data, "accessibility")
    }
    tags = {normalise_text(tag) for tag in raw_property_data.get("tags") or []}

    flags["has_garden"] = max(flags["has_garden"], 1.0 if "garden" in garden_aliases else 0.0)
    flags["has_terrace"] = max(flags["has_terrace"], 1.0 if "terrace" in garden_aliases else 0.0)
    flags["has_parking"] = max(flags["has_parking"], 1.0 if parking_aliases else 0.0)
    flags["has_garage"] = max(flags["has_garage"], 1.0 if "garage" in parking_aliases else 0.0)
    flags["has_lift"] = max(flags["has_lift"], 1.0 if "lift_access" in accessibility_aliases else 0.0)
    flags["has_new_home"] = max(flags["has_new_home"], 1.0 if "new_home" in tags or "new home" in tags else 0.0)
    flags["has_share_of_freehold"] = max(
        flags["has_share_of_freehold"],
        1.0 if normalise_text(record.get("tenure")) == "share_of_freehold" else 0.0,
    )
    flags["has_air_conditioning"] = max(
        flags["has_air_conditioning"],
        1.0 if "ac" in text or "air conditioning" in text else 0.0,
    )
    flags["has_parking"] = max(flags["has_parking"], 1.0 if normalise_text(record.get("parking_text")) else 0.0)
    flags["has_floor_plan"] = 1.0 if record.get("has_floor_plan") else 0.0
    flags["has_virtual_tour"] = 1.0 if record.get("has_virtual_tour") else 0.0
    flags["has_gas_central_heating"] = 1.0 if "gas_central" in heating_aliases else 0.0
    return flags


def build_valuation_row(record: dict[str, Any], include_target: bool = True) -> dict[str, Any] | None:
    target_price_pence = parse_number(record.get("price_pence"))
    if include_target and not target_price_pence:
        return None

    raw_property_data = record.get("raw_property_data") or {}
    text = combined_feature_text(record, raw_property_data)
    size_sqft = canonical_size_sqft(record, raw_property_data)
    bedrooms = parse_number(record.get("bedrooms"))
    bathrooms = parse_number(record.get("bathrooms"))
    station_features = station_summary(record)
    bool_flags = text_boolean_flags(text, raw_property_data, record)

    row = {
        "sample_id": sample_id_for_record(record),
        "target_price_pence": target_price_pence if include_target else None,
        "bedrooms": bedrooms,
        "bathrooms": bathrooms,
        "size_sqft": size_sqft,
        "sqft_per_bedroom": (size_sqft / bedrooms) if size_sqft and bedrooms else None,
        "bathrooms_per_bedroom": (bathrooms / bedrooms) if bathrooms is not None and bedrooms else None,
        "lease_years_remaining": parse_number(record.get("lease_years_remaining")),
        "service_charge_annual_pence": parse_number(record.get("service_charge_annual_pence")),
        "latitude": parse_number(record.get("latitude")),
        "longitude": parse_number(record.get("longitude")),
        "photo_count": float(len(record.get("photo_urls") or [])),
        "key_feature_count": float(len(record.get("key_features") or [])),
        "description_word_count": float(len(re.findall(r"\w+", str(record.get("description") or "")))),
        "title_word_count": float(len(re.findall(r"\w+", str(record.get("title") or "")))),
        "reception_rooms_count": extract_count_from_text(
            text,
            (r"\b([a-z0-9]+)\s+reception(?: room)?s?\b", r"\breception room(?:s)?[: ]+([a-z0-9]+)\b"),
        ),
        "feature_amenity_count": float(sum(value for key, value in bool_flags.items() if key.startswith("has_"))),
        "garden_feature_count": float(len(structured_feature_entries(raw_property_data, "garden"))),
        "parking_feature_count": float(len(structured_feature_entries(raw_property_data, "parking"))),
        "heating_feature_count": float(len(structured_feature_entries(raw_property_data, "heating"))),
        "road_noise_lden": noise_metric(record, "road_data"),
        "rail_noise_lden": noise_metric(record, "rail_data"),
        "flight_noise_lden": noise_metric(record, "flight_data"),
        "avg_monthly_crimes": parse_number((record.get("crime") or {}).get("avg_monthly_crimes")),
        "air_quality_daqi_index": parse_number((record.get("air_quality") or {}).get("daqi_index")),
        "area_growth_latest_pct": latest_area_growth_pct(record.get("area_price_growth")),
        "borough_nte_score": parse_number((record.get("borough") or {}).get("nte_score")),
        "borough_life_satisfaction_score": parse_number((record.get("borough") or {}).get("life_satisfaction_score")),
        "borough_happiness_score": parse_number((record.get("borough") or {}).get("happiness_score")),
        "borough_anxiety_score": parse_number((record.get("borough") or {}).get("anxiety_score")),
        "estate_agent_rating": parse_number((record.get("estate_agent") or {}).get("rating")),
        "property_type": str(record.get("property_type") or "other").strip().lower() or "other",
        "tenure": str(record.get("tenure") or "unknown").strip().lower() or "unknown",
        "postcode_outward": extract_outward_code(record.get("postcode"), (record.get("raw_address") or {}).get("outcode"))
        or "unknown",
        "town_slug": normalise_text(record.get("town") or (record.get("raw_address") or {}).get("town")).replace(" ", "_")
        or "unknown",
        "epc_rating": str(record.get("epc_rating") or "unknown").strip().upper() or "unknown",
        "council_tax_band": str(record.get("council_tax_band") or "unknown").strip().upper() or "unknown",
    }
    row.update(station_features)
    row.update({key: float(value) for key, value in bool_flags.items() if key in NUMERIC_FEATURES})
    return row


def build_valuation_training_frame(dataset_path: Path = DEFAULT_VALUATION_DATASET_PATH) -> pd.DataFrame:
    dataset_path = Path(dataset_path)
    with dataset_path.open("r", encoding="utf-8") as file_handle:
        payload = json.load(file_handle)

    rows = [build_valuation_row(record, include_target=True) for record in payload.get("properties", [])]
    rows = [row for row in rows if row]
    return pd.DataFrame(rows)


def build_valuation_inference_frame(record: dict[str, Any]) -> pd.DataFrame:
    row = build_valuation_row(record, include_target=False)
    if not row:
        return pd.DataFrame()
    return pd.DataFrame([row])


def predict_log_prices(model: HouseValuationNet, matrix: np.ndarray) -> np.ndarray:
    model.eval()
    with torch.no_grad():
        tensor = torch.tensor(matrix, dtype=torch.float32)
        return model(tensor).cpu().numpy().reshape(-1)


def predict_current_prices(model: HouseValuationNet, matrix: np.ndarray) -> np.ndarray:
    clipped_log_prices = np.clip(predict_log_prices(model, matrix), MIN_PREDICTED_LOG_PRICE, MAX_PREDICTED_LOG_PRICE)
    return np.expm1(clipped_log_prices)


def interval_quantiles_for_predictions(actual_pence: np.ndarray, predicted_pence: np.ndarray) -> dict[str, dict[str, float]]:
    safe_predictions = np.maximum(np.nan_to_num(predicted_pence.astype(np.float64), nan=1.0, posinf=1.0, neginf=1.0), 1.0)
    relative_error = (actual_pence.astype(np.float64) - safe_predictions) / safe_predictions
    return {
        "80": {
            "lower": float(np.quantile(relative_error, 0.10)),
            "upper": float(np.quantile(relative_error, 0.90)),
        },
        "95": {
            "lower": float(np.quantile(relative_error, 0.025)),
            "upper": float(np.quantile(relative_error, 0.975)),
        },
    }


def load_valuation_artifacts(
    artifacts_dir: Path = DEFAULT_VALUATION_ARTIFACTS_DIR,
) -> tuple[HouseValuationNet, ColumnTransformer, dict[str, Any], dict[str, HouseValuationNet], dict[str, ColumnTransformer]]:
    artifacts_dir = Path(artifacts_dir)
    with (artifacts_dir / "metadata.json").open("r", encoding="utf-8") as file_handle:
        metadata = json.load(file_handle)
    with (artifacts_dir / "preprocessor.pkl").open("rb") as file_handle:
        preprocessor = pickle.load(file_handle)

    payload = torch.load(artifacts_dir / "model.pt", map_location="cpu")
    model = HouseValuationNet(int(payload["input_dim"]))
    model.load_state_dict(payload["state_dict"])
    model.eval()

    fold_models: dict[str, HouseValuationNet] = {}
    fold_preprocessors: dict[str, ColumnTransformer] = {}
    fold_models_path = artifacts_dir / "fold_models.pt"
    fold_preprocessors_path = artifacts_dir / "fold_preprocessors.pkl"

    if fold_models_path.exists() and fold_preprocessors_path.exists():
        fold_payload = torch.load(fold_models_path, map_location="cpu")
        with fold_preprocessors_path.open("rb") as file_handle:
            fold_preprocessors = pickle.load(file_handle)

        for fold_key, fold_entry in (fold_payload.get("models") or {}).items():
            fold_model = HouseValuationNet(int(fold_entry["input_dim"]))
            fold_model.load_state_dict(fold_entry["state_dict"])
            fold_model.eval()
            fold_models[str(fold_key)] = fold_model

    return model, preprocessor, metadata, fold_models, fold_preprocessors


def valuation_intervals(predicted_price_pence: float, metadata: dict[str, Any]) -> dict[str, dict[str, int] | None]:
    intervals = {}
    for label in ("80", "95"):
        quantiles = (metadata.get("prediction_intervals") or {}).get(label) or {}
        lower = parse_number(quantiles.get("lower"))
        upper = parse_number(quantiles.get("upper"))
        if lower is None or upper is None:
            intervals[label] = None
            continue
        intervals[label] = {
            "lower_pence": int(round(max(0.0, predicted_price_pence * (1.0 + lower)))),
            "upper_pence": int(round(max(0.0, predicted_price_pence * (1.0 + upper)))),
        }
    return intervals


def pricing_signal(
    actual_price_pence: float | None,
    predicted_price_pence: float,
    intervals: dict[str, dict[str, int] | None],
) -> tuple[str | None, int | None, float | None]:
    if actual_price_pence is None:
        return None, None, None

    gap_pence = int(round(actual_price_pence - predicted_price_pence))
    gap_pct = float(((actual_price_pence / max(predicted_price_pence, 1.0)) - 1.0) * 100.0)
    if gap_pct >= 15.0:
        return "overpriced", gap_pence, gap_pct
    if gap_pct <= -15.0:
        return "underpriced", gap_pence, gap_pct
    return "fairly_priced", gap_pence, gap_pct


def integrated_gradients(
    model: HouseValuationNet,
    inputs: np.ndarray,
    baseline: np.ndarray | None = None,
    steps: int = INTEGRATED_GRADIENTS_STEPS,
) -> np.ndarray:
    model.eval()
    input_tensor = torch.tensor(inputs, dtype=torch.float32)
    baseline_tensor = (
        torch.zeros_like(input_tensor)
        if baseline is None
        else torch.tensor(baseline, dtype=torch.float32)
    )

    scaled_inputs = []
    for step in range(1, steps + 1):
        alpha = float(step) / steps
        scaled = baseline_tensor + alpha * (input_tensor - baseline_tensor)
        scaled.requires_grad_(True)
        scaled_inputs.append(scaled)

    gradients = []
    for scaled in scaled_inputs:
        outputs = model(scaled)
        gradient = torch.autograd.grad(outputs.sum(), scaled)[0]
        gradients.append(gradient.detach())

    average_gradient = torch.stack(gradients).mean(dim=0)
    attributions = (input_tensor - baseline_tensor) * average_gradient
    return attributions.detach().cpu().numpy()


def transformed_feature_label(name: str, metadata: dict[str, Any]) -> tuple[str, str, str]:
    if name.startswith("num__"):
        feature_key = name.removeprefix("num__")
        return feature_key, DISPLAY_LABELS.get(feature_key, title_case_label(feature_key)), feature_key

    if name.startswith("cat__"):
        encoded = name.removeprefix("cat__")
        for feature_key in metadata.get("categorical_features", []):
            prefix = f"{feature_key}_"
            if encoded.startswith(prefix):
                value = encoded.removeprefix(prefix)
                label = f"{DISPLAY_LABELS.get(feature_key, title_case_label(feature_key))}: {title_case_label(value)}"
                return f"{feature_key}:{value}", label, feature_key
        return encoded, title_case_label(encoded), encoded

    return name, title_case_label(name), name


def feature_display_value(feature_key: str, feature_frame: pd.DataFrame) -> str:
    if feature_frame.empty:
        return "unknown"
    row = feature_frame.iloc[0]
    if feature_key in row.index:
        value = row[feature_key]
        if value is None or (isinstance(value, float) and math.isnan(value)):
            return "missing"
        if isinstance(value, (np.integer, int)):
            return f"{int(value):,}"
        if isinstance(value, (np.floating, float)):
            if abs(value) >= 1000:
                return f"{value:,.0f}"
            if abs(value) >= 10:
                return f"{value:.1f}"
            return f"{value:.2f}"
        return str(value)
    return "active"


def feature_weights_from_attributions(
    attributions: np.ndarray,
    transformed_feature_names: list[str],
    feature_frame: pd.DataFrame,
    metadata: dict[str, Any],
) -> list[dict[str, Any]]:
    values = attributions.reshape(-1)
    nonzero = [
        (name, float(value))
        for name, value in zip(transformed_feature_names, values, strict=True)
        if abs(float(value)) > 1e-7
    ]
    if not nonzero:
        return []

    absolute_total = sum(abs(value) for _, value in nonzero) or 1.0
    weights = []
    for name, attribution in sorted(nonzero, key=lambda item: abs(item[1]), reverse=True):
        feature_key, label, display_key = transformed_feature_label(name, metadata)
        weights.append(
            {
                "feature_key": feature_key,
                "label": label,
                "display_value": feature_display_value(display_key, feature_frame),
                "normalized_weight": round(attribution / absolute_total, 4),
                "absolute_weight": round(abs(attribution) / absolute_total, 4),
                "direction": "positive" if attribution >= 0 else "negative",
            }
        )
    return weights[:12]


def select_runtime_model(
    record: dict[str, Any],
    final_model: HouseValuationNet,
    final_preprocessor: ColumnTransformer,
    metadata: dict[str, Any],
    fold_models: dict[str, HouseValuationNet],
    fold_preprocessors: dict[str, ColumnTransformer],
) -> tuple[HouseValuationNet, ColumnTransformer, str]:
    sample_id = sample_id_for_record(record)
    fold_key = (metadata.get("sample_fold_assignments") or {}).get(sample_id)
    if fold_key is not None:
        fold_key = str(fold_key)
        if fold_key in fold_models and fold_key in fold_preprocessors:
            return fold_models[fold_key], fold_preprocessors[fold_key], "out_of_fold"
    return final_model, final_preprocessor, "full_model"


def build_valuation_inference_payload(
    record: dict[str, Any],
    final_model: HouseValuationNet,
    final_preprocessor: ColumnTransformer,
    metadata: dict[str, Any],
    fold_models: dict[str, HouseValuationNet] | None = None,
    fold_preprocessors: dict[str, ColumnTransformer] | None = None,
) -> dict[str, Any]:
    fold_models = fold_models or {}
    fold_preprocessors = fold_preprocessors or {}

    model, preprocessor, model_source = select_runtime_model(
        record,
        final_model,
        final_preprocessor,
        metadata,
        fold_models,
        fold_preprocessors,
    )

    feature_frame = build_valuation_inference_frame(record)
    if feature_frame.empty:
        raise ValueError("Property record is missing the fields required for valuation inference.")

    transformed_row = matrix_from_frame(preprocessor, feature_frame).reshape(1, -1)
    predicted_price_pence = float(predict_current_prices(model, transformed_row)[0])
    intervals = valuation_intervals(predicted_price_pence, metadata)
    actual_price_pence = parse_number(record.get("price_pence"))
    signal, gap_pence, gap_pct = pricing_signal(actual_price_pence, predicted_price_pence, intervals)
    transformed_feature_names = preprocessor.get_feature_names_out().tolist()
    attributions = integrated_gradients(model, transformed_row)
    feature_weights = feature_weights_from_attributions(attributions, transformed_feature_names, feature_frame, metadata)

    return {
        "predicted_current_price_pence": int(round(predicted_price_pence)),
        "pricing_signal": signal,
        "price_gap_pence": gap_pence,
        "price_gap_pct": round(gap_pct, 2) if gap_pct is not None else None,
        "prediction_interval_80": intervals.get("80"),
        "prediction_interval_95": intervals.get("95"),
        "model_source": model_source,
        "feature_weights": feature_weights,
    }
