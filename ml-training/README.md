# ML Training

This folder contains the local training and inference pipelines for:

- the 1-year, 2-year, and 3-year future price forecasts shown on the property detail page
- a separate current-price valuation model that estimates fair value from structured house features and returns Integrated Gradients feature weights

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
/opt/anaconda3/bin/python3 ml-training/train_model.py --collect
```

Train and refresh the current-price valuation model:

```bash
/opt/anaconda3/bin/python3 ml-training/train_valuation_model.py --collect
```

Run inference for one property payload:

```bash
/opt/anaconda3/bin/python3 ml-training/infer_property.py --input path/to/property.json
```

Run current-price valuation inference for one property payload:

```bash
/opt/anaconda3/bin/python3 ml-training/infer_valuation.py --input path/to/property.json
```

Runtime artifacts used by the app are stored in [ml-training/artifacts/latest](/Users/aonghus/Documents/bath-hack-2026/ml-training/artifacts/latest).
The valuation artifacts are stored in `ml-training/artifacts/valuation/latest`.

## Runtime dependency

The ML runtime is pinned to `scikit-learn==1.7.2` in `ml-training/requirements.txt`. The current Rails services use the local Anaconda Python by default:

```bash
/opt/anaconda3/bin/python3
```

Downloaded historical caches are written under `ml-training/data/historical/` and are ignored by git.

## Current limitation

The historical sales data does not carry the same house-level detail we have on current listings, such as bedrooms, bathrooms, listing photos, and most Rightmove-only metadata. So the current historical model is strongest on market context, price level, property type, and postcode/borough context, and weaker on rich house-specific attributes.

The valuation model has the opposite trade-off: it uses richer current-listing features, but it is currently trained on a very small in-database sample, so its fair-value and overpriced signals should be treated as exploratory until the dataset is much larger.

## Best next data to add

- Exact sold-price histories matched to the same address over time.
- EPC/open property records to recover floor area and other structured house traits for historical sales.
- Interest-rate, affordability, and supply-demand features by month.
- Local planning, school, and deprivation datasets at postcode or LSOA level.
- More complete enrichment coverage for the current-property side: crime, stations, air quality, and noise.
