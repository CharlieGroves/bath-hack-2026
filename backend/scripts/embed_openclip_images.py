#!/usr/bin/env python3
"""
Batch-embed image URLs with OpenCLIP ViT-L/14 (LAION weights by default).

Input:  JSON stdin: {"urls": ["https://...", ...], "model": "ViT-L-14", "pretrained": "laion2b_s32b_b82k"}
Output: JSON stdout: {"embeddings": [[float]|null, ...], "dimensions": 768}
  null entries mean download/decode/encode failed for that URL (same order as input).

Install: pip install -r requirements-image-embed.txt
"""
from __future__ import annotations

import json
import sys
from io import BytesIO

import requests
import torch
from PIL import Image


def fetch_image(url: str, timeout: int = 45) -> Image.Image | None:
    try:
        headers = {"User-Agent": "BathHack/1.0 (property images; embedding)"}
        r = requests.get(url, timeout=timeout, headers=headers)
        r.raise_for_status()
        return Image.open(BytesIO(r.content)).convert("RGB")
    except Exception:
        return None


def main() -> None:
    req = json.load(sys.stdin)
    urls = req.get("urls") or []
    model_name = req.get("model") or "ViT-L-14"
    pretrained = req.get("pretrained") or "laion2b_s32b_b82k"
    batch_size = int(req.get("batch_size") or 8)

    if not urls:
        json.dump({"embeddings": [], "dimensions": 0}, sys.stdout)
        sys.stdout.write("\n")
        return

    import open_clip

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, _, preprocess = open_clip.create_model_and_transforms(
        model_name, pretrained=pretrained, device=device
    )
    model.eval()

    # Map original index -> tensor (only successful loads)
    tensors: list[torch.Tensor] = []
    index_map: list[int] = []
    for i, url in enumerate(urls):
        img = fetch_image(url)
        if img is None:
            continue
        try:
            tensors.append(preprocess(img))
            index_map.append(i)
        except Exception:
            continue

    out: list[list[float] | None] = [None] * len(urls)
    dim = 0

    if tensors:
        for start in range(0, len(tensors), batch_size):
            chunk = tensors[start : start + batch_size]
            batch = torch.stack(chunk).to(device)
            with torch.no_grad():
                emb = model.encode_image(batch)
                emb = emb / emb.norm(dim=-1, keepdim=True)
            emb_cpu = emb.cpu()
            dim = emb_cpu.shape[-1]
            for j in range(emb_cpu.shape[0]):
                orig_idx = index_map[start + j]
                out[orig_idx] = emb_cpu[j].tolist()

    json.dump({"embeddings": out, "dimensions": dim}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.stdout.write("\n")
        sys.exit(1)
