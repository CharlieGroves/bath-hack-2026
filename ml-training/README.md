# ML Training

This folder contains the local training and inference pipeline for the 1-year, 2-year, and 3-year price forecasts shown on the property detail page.

## Training basis

The model is now trained on official historical data:

- HM Land Registry Price Paid Data transactions for London local authorities, filtered from yearly files for `2020` through `2024`.
- HM Land Registry UK HPI data, using the latest bundled file in this pipeline for `2025-12`.

For each historical sale, the 1-year, 2-year, and 3-year targets are built from the actual subsequent UK HPI movement for that same London area and property type, applied to the historical sale price.

This is materially better than the earlier proxy based only on current listings and a growth prior, but it is still not a perfect observed repeat-sale target for the exact same house.

## Commands

Export the current property dataset from Rails:

```bash
python3 ml-training/collect_dataset.py
```

Train and refresh artifacts:

```bash
python3 ml-training/train_model.py --collect
```

Run inference for one property payload:

```bash
python3 ml-training/infer_property.py --input path/to/property.json
```

Runtime artifacts used by the app are stored in [ml-training/artifacts/latest](/Users/aonghus/Documents/bath-hack-2026/ml-training/artifacts/latest).

Downloaded historical caches are written under `ml-training/data/historical/` and are ignored by git.

## Current limitation

The historical sales data does not carry the same house-level detail we have on current listings, such as bedrooms, bathrooms, listing photos, and most Rightmove-only metadata. So the current historical model is strongest on market context, price level, property type, and postcode/borough context, and weaker on rich house-specific attributes.

## Best next data to add

- Exact sold-price histories matched to the same address over time.
- EPC/open property records to recover floor area and other structured house traits for historical sales.
- Interest-rate, affordability, and supply-demand features by month.
- Local planning, school, and deprivation datasets at postcode or LSOA level.
- More complete enrichment coverage for the current-property side: crime, stations, air quality, and noise.
