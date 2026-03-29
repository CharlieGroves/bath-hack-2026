#!/usr/bin/env python3
"""
Batch-embed image URLs with Meta DINOv2 (torch.hub).

Input:  JSON stdin: {"urls": ["https://...", ...], "hub_model": "dinov2_vitb14"}
        hub_model: dinov2_vits14 | dinov2_vitb14 | dinov2_vitl14 | dinov2_vitg14
Output: JSON stdout: {"embeddings": [[float]|null, ...], "dimensions": N}
  null entries mean download/decode/encode failed for that URL (same order as input).

Default dinov2_vitb14 → 768-d L2-normalized CLS embeddings (matches property_image_embeddings).

Install: pip install -r requirements-image-embed.txt

Device: CUDA if available, else Apple Silicon MPS (Metal), else CPU.
First run downloads weights via torch.hub (needs network).
"""
from __future__ import annotations

import json
import sys
from io import BytesIO

import requests
import torch
from PIL import Image
from torchvision import transforms


def pick_device() -> str:
    if torch.cuda.is_available():
        return "cuda"
    try:
        if torch.backends.mps.is_available():
            return "mps"
    except (AttributeError, NotImplementedError):
        pass
    return "cpu"


def fetch_image(url: str, timeout: int = 45) -> Image.Image | None:
    try:
        headers = {"User-Agent": "BathHack/1.0 (property images; embedding)"}
        r = requests.get(url, timeout=timeout, headers=headers)
        r.raise_for_status()
        return Image.open(BytesIO(r.content)).convert("RGB")
    except Exception:
        return None


def build_preprocess() -> transforms.Compose:
    # DINOv2 ImageNet-style preprocessing (224)
    return transforms.Compose(
        [
            transforms.Resize(256, interpolation=transforms.InterpolationMode.BICUBIC),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize((0.485, 0.456, 0.406), (0.229, 0.224, 0.225)),
        ]
    )


def main() -> None:
    req = json.load(sys.stdin)
    urls = req.get("urls") or []
    hub_model = req.get("hub_model") or "dinov2_vitb14"
    batch_size = int(req.get("batch_size") or 8)

    if not urls:
        json.dump({"embeddings": [], "dimensions": 0}, sys.stdout)
        sys.stdout.write("\n")
        return

    device = pick_device()
    model = torch.hub.load("facebookresearch/dinov2", hub_model, pretrained=True)
    model = model.to(device)
    model.eval()
    preprocess = build_preprocess()

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
                feats = model.forward_features(batch)
                emb = feats["x_norm_clstoken"]
                emb = torch.nn.functional.normalize(emb, dim=-1, p=2, eps=1e-6)
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
