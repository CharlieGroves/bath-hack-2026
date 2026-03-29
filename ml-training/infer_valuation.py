from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from valuation_pipeline import (
    DEFAULT_VALUATION_ARTIFACTS_DIR,
    build_valuation_inference_payload,
    load_valuation_artifacts,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run current-price valuation inference for a single property JSON payload.")
    parser.add_argument("--artifacts-dir", type=Path, default=DEFAULT_VALUATION_ARTIFACTS_DIR, help="Path to trained artifacts.")
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Optional property JSON file. If omitted, JSON is read from stdin.",
    )
    args = parser.parse_args()

    if args.input:
        raw_payload = args.input.read_text(encoding="utf-8")
    else:
        raw_payload = sys.stdin.read()

    property_payload = json.loads(raw_payload)
    model, preprocessor, metadata, fold_models, fold_preprocessors = load_valuation_artifacts(args.artifacts_dir)
    result = build_valuation_inference_payload(
        property_payload,
        model,
        preprocessor,
        metadata,
        fold_models=fold_models,
        fold_preprocessors=fold_preprocessors,
    )
    sys.stdout.write(json.dumps(result))


if __name__ == "__main__":
    main()
