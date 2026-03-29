from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

from pipeline import BACKEND_ROOT, DEFAULT_DATASET_PATH


def main() -> None:
    parser = argparse.ArgumentParser(description="Export the current property dataset from Rails for ML training.")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_DATASET_PATH,
        help="Path to the exported JSON dataset.",
    )
    args = parser.parse_args()

    output_path = args.output.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["OUTPUT"] = str(output_path)

    subprocess.run(
        ["mise", "exec", "ruby@3.4.4", "--", "bundle", "exec", "rake", "ml:export_dataset"],
        cwd=BACKEND_ROOT,
        env=env,
        check=True,
    )
    print(f"Exported dataset to {output_path}")


if __name__ == "__main__":
    main()
