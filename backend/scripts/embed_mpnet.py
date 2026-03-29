#!/usr/bin/env python3
"""
Embed text with sentence-transformers (all-mpnet-base-v2 by default).

Input:  JSON on stdin: {"text": "...", "model": "optional-huggingface-id"}
Output: JSON on stdout: {"embedding": [float, ...], "dimensions": N}

Install: pip install -r requirements-embed.txt
"""
from __future__ import annotations

import json
import sys


def main() -> None:
    req = json.load(sys.stdin)
    text = (req.get("text") or "").strip()
    model_id = req.get("model") or "sentence-transformers/all-mpnet-base-v2"

    if not text:
        json.dump({"embedding": [], "dimensions": 0}, sys.stdout)
        sys.stdout.write("\n")
        return

    from sentence_transformers import SentenceTransformer

    model = SentenceTransformer(model_id)
    vec = model.encode(text, normalize_embeddings=True)
    out = vec.tolist()
    json.dump({"embedding": out, "dimensions": len(out)}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.stdout.write("\n")
        sys.exit(1)
