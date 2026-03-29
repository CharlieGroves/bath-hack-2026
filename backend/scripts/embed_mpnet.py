#!/usr/bin/env python3
"""
Embed text with sentence-transformers (all-MiniLM-L6-v2 by default).

Input:  JSON on stdin: {"text": "...", "model": "optional-huggingface-id"}
Output: JSON on stdout: {"embedding": [float, ...], "dimensions": N}

Install: pip install -r requirements-embed.txt

Device: CUDA if available, else Apple Silicon MPS (Metal), else CPU.
"""
from __future__ import annotations

import json
import sys


def pick_device() -> str:
    import torch

    if torch.cuda.is_available():
        return "cuda"
    try:
        if torch.backends.mps.is_available():
            return "mps"
    except (AttributeError, NotImplementedError):
        pass
    return "cpu"


def main() -> None:
    req = json.load(sys.stdin)
    text = (req.get("text") or "").strip()
    model_id = req.get("model") or "sentence-transformers/all-MiniLM-L6-v2"

    if not text:
        json.dump({"embedding": [], "dimensions": 0}, sys.stdout)
        sys.stdout.write("\n")
        return

    from sentence_transformers import SentenceTransformer

    device = pick_device()
    model = SentenceTransformer(model_id, device=device)
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
