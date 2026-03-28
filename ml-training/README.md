# ML Training

This folder contains the local training and inference pipeline for the one-year house-price forecast shown on the property detail page.

## What the model does

- Collects the current property records from the Rails database.
- Builds a feature set from each house's structured fields, transport/noise/crime/air-quality enrichments, and a recent area growth prior.
- Trains a small PyTorch MLP to predict a proxy one-year-forward price.
- Runs Integrated Gradients on each prediction so the app can show feature-level attribution for a clicked house.

## Important limitation

The repo does not currently store realized house prices one year later. Because of that, the training target is a proxy:

- `future_price ≈ current_asking_price * (1 + recent_area_growth_prior)`

The growth prior comes from [`backend/data/london_area_house_growth_per_year.csv`](/Users/aonghus/Documents/bath-hack-2026/backend/data/london_area_house_growth_per_year.csv), filtered to recent sane values and clipped to avoid the extreme outliers in that file.

This means the pipeline is useful for local experimentation and UI integration, but not for claiming production-quality forecasting accuracy.

## Commands

Export the current dataset:

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

Artifacts are written to [`ml-training/artifacts/latest`](/Users/aonghus/Documents/bath-hack-2026/ml-training/artifacts/latest).

## Better historical data to add next

- Land Registry sale-price history joined to each property or postcode.
- Relisting/sold outcomes so the target is an observed forward price, not a proxy.
- More complete postcode or borough labels for every listing.
- Interest rates, mortgage affordability, and local supply/demand indicators by month.
- Planning applications, school scores, and deprivation indices at postcode/LSOA level.
- More complete enrichment coverage for crime, transport, noise, EPC, and air quality.
