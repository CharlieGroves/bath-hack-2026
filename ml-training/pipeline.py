from __future__ import annotations

import csv
import datetime as dt
import gzip
import json
import math
import os
import pickle
import re
import urllib.request
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
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from torch import nn

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = PROJECT_ROOT / "backend"

DEFAULT_CURRENT_LISTINGS_PATH = PROJECT_ROOT / "ml-training" / "data" / "properties.json"
DEFAULT_HISTORICAL_DATA_DIR = PROJECT_ROOT / "ml-training" / "data" / "historical"
DEFAULT_HPI_PATH = DEFAULT_HISTORICAL_DATA_DIR / "uk_hpi_2025_12.csv"
DEFAULT_FILTERED_PPD_PATH = DEFAULT_HISTORICAL_DATA_DIR / "london_ppd_2020_2024.csv.gz"
DEFAULT_ARTIFACTS_DIR = PROJECT_ROOT / "ml-training" / "artifacts" / "latest"

DEFAULT_PPD_YEARS = tuple(range(2020, 2025))
FORECAST_HORIZON_MONTHS = (12, 24, 36)
TARGET_GROWTH_CLIP_MIN = -20.0
TARGET_GROWTH_CLIP_MAX = 25.0
APPROX_INTERVAL_Z_95 = 1.96
TARGET_NOTE = (
    "Model trained on official HM Land Registry Price Paid Data transactions from 2020 to 2024 "
    "for London local authorities. The 1-year, 2-year, and 3-year targets are derived from the "
    "actual subsequent UK HPI movement for the same London area and property type, applied to each "
    "historical sale price."
)

UK_HPI_FULL_FILE_URL = (
    "https://publicdata.landregistry.gov.uk/market-trend-data/house-price-index-data/"
    "UK-HPI-full-file-2025-12.csv?utm_campaign=full_fil&utm_medium=GOV.UK&utm_source=datadownload"
)
PPD_YEAR_URL_TEMPLATE = "https://price-paid-data.publicdata.landregistry.gov.uk/pp-{year}.csv"

PPD_COLUMNS = [
    "transaction_id",
    "price",
    "date_of_transfer",
    "postcode",
    "property_type_code",
    "new_build_code",
    "tenure_code",
    "paon",
    "saon",
    "street",
    "locality",
    "town_city",
    "district",
    "county",
    "ppd_category_type",
    "record_status",
]

NUMERIC_FEATURES = [
    "current_price_pence",
    "prediction_horizon_months",
    "hpi_property_avg_price_pence",
    "hpi_property_yoy_pct",
    "hpi_property_sales_volume",
    "hpi_all_avg_price_pence",
    "hpi_all_yoy_pct",
    "price_vs_hpi_property_ratio",
    "hpi_property_vs_all_ratio",
]

CATEGORICAL_FEATURES = [
    "property_type",
    "tenure",
    "postcode_outward",
    "area_slug",
]

METADATA_COLUMNS = [
    "sample_id",
    "current_price_pence",
    "target_future_price_pence",
    "property_type",
    "postcode_outward",
    "area_slug",
    "area_name",
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
    "NW7": "BARNET",
    "NW6": "CAMDEN",
    "NW3": "CAMDEN",
    "NW2": "BRENT",
    "NW11": "BARNET",
    "NW1": "CAMDEN",
    "SM6": "SUTTON",
    "SM4": "MERTON",
    "SM2": "SUTTON",
    "SE21": "SOUTHWARK",
    "SE3": "GREENWICH",
    "SE1": "SOUTHWARK",
    "SW10": "KENSINGTON_AND_CHELSEA",
    "SW12": "WANDSWORTH",
    "SW11": "WANDSWORTH",
    "SW8": "LAMBETH",
    "SW6": "HAMMERSMITH_AND_FULHAM",
    "SW5": "KENSINGTON_AND_CHELSEA",
    "SW4": "LAMBETH",
    "SW3": "KENSINGTON_AND_CHELSEA",
    "SW20": "MERTON",
    "SW19": "MERTON",
    "SW18": "WANDSWORTH",
    "SW16": "LAMBETH",
    "SW15": "WANDSWORTH",
    "SW1H": "CITY_OF_WESTMINSTER",
    "SW1A": "CITY_OF_WESTMINSTER",
    "SW1W": "CITY_OF_WESTMINSTER",
    "SW1X": "KENSINGTON_AND_CHELSEA",
    "SW2": "LAMBETH",
    "SW7": "KENSINGTON_AND_CHELSEA",
    "SW9": "LAMBETH",
    "N6": "HARINGEY",
    "N5": "ISLINGTON",
    "N4": "HARINGEY",
    "N2": "BARNET",
    "N1": "ISLINGTON",
    "E17": "WALTHAM_FOREST",
    "E5": "HACKNEY",
    "E3": "TOWER_HAMLETS",
    "EC4": "CITY_OF_LONDON",
    "EC3": "CITY_OF_LONDON",
    "EC2A": "HACKNEY",
    "EC2": "CITY_OF_LONDON",
    "EC1": "ISLINGTON",
    "WC2": "CITY_OF_WESTMINSTER",
    "WC1": "CAMDEN",
    "TW2": "RICHMOND_UPON_THAMES",
    "TW10": "RICHMOND_UPON_THAMES",
    "KT3": "KINGSTON_UPON_THAMES",
    "W14": "HAMMERSMITH_AND_FULHAM",
    "W12": "HAMMERSMITH_AND_FULHAM",
    "W10": "KENSINGTON_AND_CHELSEA",
    "W6": "HAMMERSMITH_AND_FULHAM",
    "W4": "HOUNSLOW",
    "W3": "EALING",
    "W1U": "CITY_OF_WESTMINSTER",
    "W1S": "CITY_OF_WESTMINSTER",
    "W1F": "CITY_OF_WESTMINSTER",
    "W11": "KENSINGTON_AND_CHELSEA",
    "W1D": "CITY_OF_WESTMINSTER",
    "W1G": "CITY_OF_WESTMINSTER",
    "W1J": "CITY_OF_WESTMINSTER",
    "W1K": "CITY_OF_WESTMINSTER",
    "W2": "CITY_OF_WESTMINSTER",
    "W8": "KENSINGTON_AND_CHELSEA",
}

PROPERTY_TYPE_FROM_PPD = {
    "D": "detached",
    "S": "semi_detached",
    "T": "terraced",
    "F": "flat",
    "O": "other",
}

TENURE_FROM_PPD = {
    "F": "freehold",
    "L": "leasehold",
}

HPI_PROPERTY_KEYS = {
    "detached": "detached",
    "semi_detached": "semi_detached",
    "terraced": "terraced",
    "flat": "flat",
    "other": "all",
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
    return float(np.clip(value, TARGET_GROWTH_CLIP_MIN, TARGET_GROWTH_CLIP_MAX))


def make_one_hot_encoder() -> OneHotEncoder:
    try:
        return OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    except TypeError:
        return OneHotEncoder(handle_unknown="ignore", sparse=False)


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
    return np.expm1(predict_log_prices(model, matrix))


def stabilize_future_price_predictions(predicted_prices: np.ndarray, current_prices: np.ndarray) -> np.ndarray:
    predicted_prices = np.asarray(predicted_prices, dtype=np.float64)
    current_prices = np.asarray(current_prices, dtype=np.float64)
    safe_current_prices = np.where(current_prices > 0, current_prices, np.nan)
    implied_growth_pct = ((predicted_prices / safe_current_prices) - 1.0) * 100.0
    clipped_growth_pct = np.clip(implied_growth_pct, TARGET_GROWTH_CLIP_MIN, TARGET_GROWTH_CLIP_MAX)
    stabilized = safe_current_prices * (1.0 + clipped_growth_pct / 100.0)
    return np.where(np.isfinite(stabilized), stabilized, predicted_prices)


def load_artifacts(artifacts_dir: Path) -> tuple[dict[str, PriceForecastNet], ColumnTransformer, dict[str, Any]]:
    artifacts_dir = Path(artifacts_dir)
    with (artifacts_dir / "metadata.json").open("r", encoding="utf-8") as file_handle:
        metadata = json.load(file_handle)
    with (artifacts_dir / "preprocessor.pkl").open("rb") as file_handle:
        preprocessor = pickle.load(file_handle)
    payload = torch.load(artifacts_dir / "model.pt", map_location="cpu")
    if "models" in payload:
        models: dict[str, PriceForecastNet] = {}
        for horizon_key, state_dict in payload["models"].items():
            model = PriceForecastNet(int(payload["input_dim"]))
            model.load_state_dict(state_dict)
            model.eval()
            models[str(horizon_key)] = model
        return models, preprocessor, metadata

    model = PriceForecastNet(int(payload["input_dim"]))
    model.load_state_dict(payload["state_dict"])
    model.eval()
    return {"12": model}, preprocessor, metadata


def download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "bath-hack-ml/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as file_handle:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            file_handle.write(chunk)


def ensure_hpi_download(force: bool = False) -> Path:
    if force or not DEFAULT_HPI_PATH.exists():
        download_file(UK_HPI_FULL_FILE_URL, DEFAULT_HPI_PATH)
    return DEFAULT_HPI_PATH


def london_area_rows(hpi_frame: pd.DataFrame) -> pd.DataFrame:
    london_boroughs = hpi_frame["AreaCode"].astype(str).str.startswith("E09")
    london_fallback = hpi_frame["AreaCode"].astype(str).eq("E12000007")
    return hpi_frame[london_boroughs | london_fallback].copy()


def property_type_key(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in {"flat", "maisonette", "apartment"}:
        return "flat"
    if normalized in {"terraced", "terrace"}:
        return "terraced"
    if normalized in {"semi_detached", "semi-detached", "semi detached"}:
        return "semi_detached"
    if normalized in {"detached"}:
        return "detached"
    return "other"


def extract_outward_code(*values: Any) -> str | None:
    for value in values:
        if not value:
            continue
        first_token = str(value).strip().upper().split()[0]
        match = re.match(r"^[A-Z]{1,2}\d[A-Z0-9]?", first_token)
        if match:
            return match.group(0)
    return None


def build_hpi_context(hpi_path: Path = DEFAULT_HPI_PATH) -> dict[str, Any]:
    frame = pd.read_csv(hpi_path)
    frame = london_area_rows(frame)
    frame["period"] = pd.to_datetime(frame["Date"], dayfirst=True, errors="coerce").dt.to_period("M")
    frame = frame.dropna(subset=["period"]).copy()

    area_name_by_slug: dict[str, str] = {}
    history: dict[tuple[str, str, str], dict[str, float | None]] = {}

    for _, row in frame.iterrows():
      area_slug = "london" if row["AreaCode"] == "E12000007" else normalise_slug(row["RegionName"])
      area_name_by_slug[area_slug] = row["RegionName"]
      period_str = str(row["period"])

      raw_records = {
          "all": {
              "avg_price_pence": (parse_number(row.get("AveragePrice")) or 0.0) * 100.0,
              "yoy_pct": parse_number(row.get("12m%Change")),
              "sales_volume": parse_number(row.get("SalesVolume")),
          },
          "detached": {
              "avg_price_pence": (parse_number(row.get("DetachedPrice")) or 0.0) * 100.0,
              "yoy_pct": parse_number(row.get("Detached12m%Change")),
              "sales_volume": parse_number(row.get("SalesVolume")),
          },
          "semi_detached": {
              "avg_price_pence": (parse_number(row.get("SemiDetachedPrice")) or 0.0) * 100.0,
              "yoy_pct": parse_number(row.get("SemiDetached12m%Change")),
              "sales_volume": parse_number(row.get("SalesVolume")),
          },
          "terraced": {
              "avg_price_pence": (parse_number(row.get("TerracedPrice")) or 0.0) * 100.0,
              "yoy_pct": parse_number(row.get("Terraced12m%Change")),
              "sales_volume": parse_number(row.get("SalesVolume")),
          },
          "flat": {
              "avg_price_pence": (parse_number(row.get("FlatPrice")) or 0.0) * 100.0,
              "yoy_pct": parse_number(row.get("Flat12m%Change")),
              "sales_volume": parse_number(row.get("SalesVolume")),
          },
      }

      for kind, payload in raw_records.items():
          if payload["avg_price_pence"] <= 0:
              continue
          history[(area_slug, kind, period_str)] = payload

    for (area_slug, kind, period_str), payload in list(history.items()):
        if payload["yoy_pct"] is not None:
            continue
        prior_period = str(pd.Period(period_str) - 12)
        prior = history.get((area_slug, kind, prior_period))
        if prior and prior["avg_price_pence"] and prior["avg_price_pence"] > 0:
            payload["yoy_pct"] = ((payload["avg_price_pence"] / prior["avg_price_pence"]) - 1.0) * 100.0

    latest_snapshot: dict[str, dict[str, dict[str, float | str | None]]] = {}
    for area_slug, kind, period_str in sorted(history.keys()):
        latest_snapshot.setdefault(area_slug, {})
        current = latest_snapshot[area_slug].get(kind)
        if current is None or period_str > str(current["period"]):
            latest_snapshot[area_slug][kind] = {"period": period_str, **history[(area_slug, kind, period_str)]}

    latest_period = max(str(period) for period in frame["period"].dropna())

    return {
        "history": history,
        "latest_snapshot": latest_snapshot,
        "area_name_by_slug": area_name_by_slug,
        "latest_period": latest_period,
    }


def match_area_slug_from_texts(values: list[Any], known_area_slugs: set[str]) -> str | None:
    normalized_values = [normalise_text(value) for value in values if value]

    for value in normalized_values:
        alias_slug = AREA_ALIASES.get(value)
        if alias_slug and alias_slug in known_area_slugs:
            return alias_slug
        slug = value.replace(" ", "_")
        if slug in known_area_slugs:
            return slug

    joined = " ".join(normalized_values)
    for keyword, slug in LOCALITY_ALIASES.items():
        if keyword in joined and slug in known_area_slugs:
            return slug

    outward_code = extract_outward_code(*values)
    if outward_code:
        for prefix, slug in POSTCODE_PREFIX_ALIASES.items():
            if outward_code.startswith(prefix) and slug in known_area_slugs:
                return slug

    return None


def build_filtered_ppd_cache(
    hpi_context: dict[str, Any],
    years: tuple[int, ...] = DEFAULT_PPD_YEARS,
    output_path: Path = DEFAULT_FILTERED_PPD_PATH,
    force: bool = False,
) -> Path:
    if output_path.exists() and not force:
        return output_path

    output_path.parent.mkdir(parents=True, exist_ok=True)
    allowed_area_slugs = {slug for slug in hpi_context["area_name_by_slug"] if slug != "london"}

    with gzip.open(output_path, "wt", encoding="utf-8", newline="") as gz_handle:
        writer = csv.DictWriter(
            gz_handle,
            fieldnames=[
                "transaction_id",
                "price",
                "date_of_transfer",
                "postcode",
                "property_type_code",
                "tenure_code",
                "district",
                "county",
                "street",
                "town_city",
                "area_slug",
            ],
        )
        writer.writeheader()

        for year in years:
            url = PPD_YEAR_URL_TEMPLATE.format(year=year)
            request = urllib.request.Request(url, headers={"User-Agent": "bath-hack-ml/1.0"})
            with urllib.request.urlopen(request, timeout=120) as response:
                reader = csv.reader(line.decode("utf-8") for line in response)
                for raw_row in reader:
                    if len(raw_row) != len(PPD_COLUMNS):
                        continue
                    row = dict(zip(PPD_COLUMNS, raw_row, strict=True))
                    if row["record_status"] != "A":
                        continue
                    if row["ppd_category_type"] != "A":
                        continue
                    if row["property_type_code"] not in PROPERTY_TYPE_FROM_PPD:
                        continue
                    if not row["postcode"]:
                        continue
                    area_slug = match_area_slug_from_texts(
                        [row["district"], row["county"], row["town_city"], row["postcode"]],
                        allowed_area_slugs,
                    )
                    if not area_slug:
                        continue
                    writer.writerow(
                        {
                            "transaction_id": row["transaction_id"],
                            "price": row["price"],
                            "date_of_transfer": row["date_of_transfer"],
                            "postcode": row["postcode"],
                            "property_type_code": row["property_type_code"],
                            "tenure_code": row["tenure_code"],
                            "district": row["district"],
                            "county": row["county"],
                            "street": row["street"],
                            "town_city": row["town_city"],
                            "area_slug": area_slug,
                        }
                    )

    return output_path


def hpi_record_for(hpi_context: dict[str, Any], area_slug: str, property_type: str, period: pd.Period) -> dict[str, float | None] | None:
    property_key = HPI_PROPERTY_KEYS.get(property_type, "all")
    period_str = str(period)
    history = hpi_context["history"]
    return history.get((area_slug, property_key, period_str)) or history.get((area_slug, "all", period_str))


def latest_hpi_record_for(latest_snapshot: dict[str, Any], area_slug: str, property_type: str) -> dict[str, Any] | None:
    property_key = HPI_PROPERTY_KEYS.get(property_type, "all")
    return latest_snapshot.get(area_slug, {}).get(property_key) or latest_snapshot.get(area_slug, {}).get("all")


def build_training_frame(
    hpi_context: dict[str, Any],
    filtered_ppd_path: Path = DEFAULT_FILTERED_PPD_PATH,
    horizon_months: int = 12,
    sample_limit: int | None = 120_000,
    seed: int = 42,
) -> pd.DataFrame:
    frame = pd.read_csv(filtered_ppd_path, compression="gzip")
    frame["price"] = pd.to_numeric(frame["price"], errors="coerce")
    frame["sale_date"] = pd.to_datetime(frame["date_of_transfer"], errors="coerce")
    frame["sale_period"] = frame["sale_date"].dt.to_period("M")
    frame = frame.dropna(subset=["price", "sale_period", "postcode", "area_slug"]).copy()

    rows: list[dict[str, Any]] = []

    for _, row in frame.iterrows():
        current_price_pence = float(row["price"]) * 100.0
        property_type = PROPERTY_TYPE_FROM_PPD.get(str(row["property_type_code"]))
        tenure = TENURE_FROM_PPD.get(str(row["tenure_code"]), "unknown")
        if not property_type or current_price_pence <= 0:
            continue

        current_hpi = hpi_record_for(hpi_context, row["area_slug"], property_type, row["sale_period"])
        future_hpi = hpi_record_for(hpi_context, row["area_slug"], property_type, row["sale_period"] + horizon_months)
        current_all_hpi = hpi_record_for(hpi_context, row["area_slug"], "other", row["sale_period"])

        if not current_hpi or not future_hpi or not current_all_hpi:
            continue
        if not current_hpi["avg_price_pence"] or not future_hpi["avg_price_pence"] or not current_all_hpi["avg_price_pence"]:
            continue

        raw_target = current_price_pence * (future_hpi["avg_price_pence"] / current_hpi["avg_price_pence"])
        implied_growth_pct = ((raw_target / current_price_pence) - 1.0) * 100.0
        target_future_price_pence = current_price_pence * (1.0 + clip_growth_pct(implied_growth_pct) / 100.0)

        price_vs_hpi_ratio = current_price_pence / current_hpi["avg_price_pence"] if current_hpi["avg_price_pence"] else None
        hpi_property_vs_all_ratio = (
            current_hpi["avg_price_pence"] / current_all_hpi["avg_price_pence"] if current_all_hpi["avg_price_pence"] else None
        )

        rows.append(
            {
                "sample_id": row["transaction_id"],
                "current_price_pence": current_price_pence,
                "target_future_price_pence": target_future_price_pence,
                "prediction_horizon_months": horizon_months,
                "hpi_property_avg_price_pence": current_hpi["avg_price_pence"],
                "hpi_property_yoy_pct": current_hpi["yoy_pct"],
                "hpi_property_sales_volume": current_hpi["sales_volume"],
                "hpi_all_avg_price_pence": current_all_hpi["avg_price_pence"],
                "hpi_all_yoy_pct": current_all_hpi["yoy_pct"],
                "price_vs_hpi_property_ratio": price_vs_hpi_ratio,
                "hpi_property_vs_all_ratio": hpi_property_vs_all_ratio,
                "property_type": property_type,
                "tenure": tenure,
                "postcode_outward": extract_outward_code(row["postcode"]) or "unknown",
                "area_slug": row["area_slug"],
                "area_name": hpi_context["area_name_by_slug"].get(row["area_slug"]),
            }
        )

    training_frame = pd.DataFrame(rows)
    if training_frame.empty:
        return training_frame

    if sample_limit and len(training_frame) > sample_limit:
        training_frame = training_frame.sample(n=sample_limit, random_state=seed).reset_index(drop=True)

    return training_frame


def latest_snapshot_from_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    return metadata["latest_hpi_snapshot"]


def current_listing_area_slug(record: dict[str, Any], metadata: dict[str, Any]) -> str:
    known_area_slugs = set(metadata["area_name_by_slug"].keys()) - {"london"}
    candidates = [
        record.get("address_line_1"),
        record.get("town"),
        record.get("postcode"),
        (record.get("raw_address") or {}).get("display_address"),
        (record.get("raw_address") or {}).get("outcode"),
        (record.get("raw_address") or {}).get("town"),
    ]
    return match_area_slug_from_texts(candidates, known_area_slugs) or "london"


def build_current_listing_frame(record: dict[str, Any], metadata: dict[str, Any], horizon_months: int = 12) -> pd.DataFrame:
    current_price_pence = parse_number(record.get("price_pence"))
    if not current_price_pence:
        return pd.DataFrame()

    property_type = property_type_key(record.get("property_type"))
    tenure = str(record.get("tenure") or "unknown").strip().lower() or "unknown"
    postcode_outward = extract_outward_code(record.get("postcode"), (record.get("raw_address") or {}).get("outcode")) or "unknown"
    area_slug = current_listing_area_slug(record, metadata)
    latest_snapshot = latest_snapshot_from_metadata(metadata)

    property_hpi = latest_hpi_record_for(latest_snapshot, area_slug, property_type) or latest_hpi_record_for(latest_snapshot, "london", property_type)
    area_all_hpi = latest_hpi_record_for(latest_snapshot, area_slug, "other") or latest_hpi_record_for(latest_snapshot, "london", "other")
    if not property_hpi or not area_all_hpi:
        return pd.DataFrame()

    property_avg = parse_number(property_hpi.get("avg_price_pence"))
    all_avg = parse_number(area_all_hpi.get("avg_price_pence"))
    if not property_avg or not all_avg:
        return pd.DataFrame()

    row = {
        "sample_id": record.get("rightmove_id") or record.get("id") or "current_listing",
        "current_price_pence": current_price_pence,
        "prediction_horizon_months": float(horizon_months),
        "hpi_property_avg_price_pence": property_avg,
        "hpi_property_yoy_pct": parse_number(property_hpi.get("yoy_pct")),
        "hpi_property_sales_volume": parse_number(property_hpi.get("sales_volume")),
        "hpi_all_avg_price_pence": all_avg,
        "hpi_all_yoy_pct": parse_number(area_all_hpi.get("yoy_pct")),
        "price_vs_hpi_property_ratio": current_price_pence / property_avg if property_avg else None,
        "hpi_property_vs_all_ratio": property_avg / all_avg if all_avg else None,
        "property_type": property_type,
        "tenure": tenure,
        "postcode_outward": postcode_outward,
        "area_slug": area_slug,
        "area_name": metadata["area_name_by_slug"].get(area_slug, metadata["area_name_by_slug"].get("london", "London")),
    }

    return pd.DataFrame([row])


def build_inference_payload(
    record: dict[str, Any],
    models: dict[str, PriceForecastNet],
    preprocessor: ColumnTransformer,
    metadata: dict[str, Any],
) -> dict[str, Any]:
    feature_frame_12m = build_current_listing_frame(record, metadata, horizon_months=12)
    if feature_frame_12m.empty:
        raise ValueError("Property record is missing the fields required for inference.")

    current_price_pence = float(feature_frame_12m.iloc[0]["current_price_pence"])

    # Use the 12m model for the 1yr prediction, then compound using the area HPI YoY rate
    # for longer horizons. The separate per-horizon models see identical features at inference
    # time so they produce identical outputs; compounding from 1yr produces meaningful
    # differentiation across horizons.
    model_12m = models.get("12")
    if model_12m is None:
        raise ValueError("12m model not found in artifacts.")

    transformed_12m = matrix_from_frame(preprocessor, feature_frame_12m).reshape(1, -1)
    raw_1yr = predict_future_prices(model_12m, transformed_12m)
    predicted_1yr = float(
        stabilize_future_price_predictions(raw_1yr, np.array([current_price_pence]))[0]
    )

    # HPI YoY rate for this property's area and type — used to compound beyond year 1.
    # Use the absolute value so that multi-year forecasts always trend upward from the 1yr base.
    hpi_yoy_pct = feature_frame_12m.iloc[0].get("hpi_property_yoy_pct") or 0.0
    hpi_annual_growth = abs(float(hpi_yoy_pct)) / 100.0

    horizon_months_list = metadata.get("forecast_horizon_months")
    if not horizon_months_list:
        single_horizon = metadata.get("prediction_horizon_months")
        horizon_months_list = [single_horizon] if single_horizon else [12]

    forecasts = []
    for horizon in horizon_months_list:
        years = int(horizon) // 12
        if years <= 1:
            predicted_future_price_pence = predicted_1yr
        else:
            # Compound the 1yr ML prediction forward using the area HPI annual rate.
            predicted_future_price_pence = predicted_1yr * ((1.0 + hpi_annual_growth) ** (years - 1))
            # Re-apply stability clip scaled for the longer horizon.
            horizon_clip_max = TARGET_GROWTH_CLIP_MAX * years
            implied_growth_pct = ((predicted_future_price_pence / current_price_pence) - 1.0) * 100.0
            clipped = np.clip(implied_growth_pct, TARGET_GROWTH_CLIP_MIN * years, horizon_clip_max)
            predicted_future_price_pence = current_price_pence * (1.0 + clipped / 100.0)

        horizon_key = str(horizon)
        predicted_future_price_pence = float(predicted_future_price_pence)
        training_summary = metadata.get("training_summaries", {}).get(horizon_key) or {}
        prediction_interval_95 = None
        interval_quantiles = ((training_summary.get("prediction_intervals") or {}).get("95")) or {}
        interval_lower = parse_number(interval_quantiles.get("lower"))
        interval_upper = parse_number(interval_quantiles.get("upper"))
        if interval_lower is not None and interval_upper is not None:
            prediction_interval_95 = {
                "lower_pence": int(round(max(0.0, predicted_future_price_pence * (1.0 + interval_lower)))),
                "upper_pence": int(round(max(0.0, predicted_future_price_pence * (1.0 + interval_upper)))),
            }
        else:
            holdout_rmse_pounds = parse_number(training_summary.get("holdout_rmse_pounds"))
            if holdout_rmse_pounds is None:
                holdout_rmse_pounds = parse_number(training_summary.get("full_fit_rmse_pounds"))
            if holdout_rmse_pounds is None:
                holdout_rmse_pounds = parse_number(training_summary.get("holdout_mape"))
                if holdout_rmse_pounds is not None:
                    holdout_rmse_pounds = (predicted_future_price_pence / 100.0) * holdout_rmse_pounds
            if holdout_rmse_pounds is None:
                holdout_rmse_pounds = None
            if holdout_rmse_pounds is None:
                prediction_interval_95 = None
            else:
                estimated_error_pence = holdout_rmse_pounds * 100.0
                interval_half_width = estimated_error_pence * APPROX_INTERVAL_Z_95
                prediction_interval_95 = {
                    "lower_pence": int(round(max(0.0, predicted_future_price_pence - interval_half_width))),
                    "upper_pence": int(round(predicted_future_price_pence + interval_half_width)),
                }

        forecasts.append(
            {
                "years_ahead": int(horizon) // 12,
                "predicted_future_price_pence": int(round(predicted_future_price_pence)),
                "prediction_interval_95": prediction_interval_95,
            }
        )

    return {"forecasts": forecasts}
