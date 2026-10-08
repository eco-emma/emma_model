# The EMMA Model

This model predicts vegetation greenness recovery as a function of time since fire and environmental covariates. Observations now come from the **emma_envdata** EVI + fire-age products (historically NDVI).

# EMMA workflow overview

The EMMA workflow consists of four modules, each with a separate Github repo:

1) The Environmental Data module (https://github.com/eco-emma/emma_envdata)

2) The Modelling and Change Detection module (https://github.com/eco-emma/emma_model)

3) The Change Classification module (https://github.com/AdamWilsonLab/emma_change_classification)

4) The Reporting module (https://github.com/AdamWilsonLab/emma_report)

# emma_envdata input contract

`emma_model` downloads typed GitHub release tags from `eco-emma/emma_envdata` into `data/envdata/`:

| Local path | Release tag | Role |
|------------|-------------|------|
| `static/static_covariates.parquet`, `static/domain.tif` | `static_data` | Static covariates + domain grid (EPSG:9221, key `pid`) |
| `vi_modis/vi_modis_*.parquet` | `vi_modis_parquet` | EVI time series (`pid, date, sensor, value` with EVI × 100) |
| `fireage/fireage_modis_*.parquet` | `fireage` | Fire age joined to VI on `(pid, date, sensor)` |

STAC discovery (optional): `https://github.com/eco-emma/emma_envdata/releases/download/stac/catalog.json`

Notes:

- Spatial pixel key from envdata is `pid`; the model keeps a `cellID` alias (`cellID == pid`) for Stan plumbing, while Stan's `pid` remains the remapped `1:J` index.
- Remnant buffers are in **metres** (`remnant_distance = 2000` ≈ former 2 km).
- The observation column passed to Stan is still named `ndvi` but holds **EVI** (`value / 100`).
