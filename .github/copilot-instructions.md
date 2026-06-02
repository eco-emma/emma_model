# EMMA Model Copilot Instructions

## Project Overview

This is the EMMA (Environmental Monitoring & Modeling Application) modeling module - a Bayesian hierarchical model predicting post-fire NDVI recovery in South African fynbos shrublands. The model estimates recovery trajectories as a function of time-since-fire, seasonal effects, and environmental covariates.

**Architecture**: Part of a 4-module pipeline:
1. [emma_envdata](https://github.com/AdamWilsonLab/emma_envdata) - Environmental data preparation
2. **emma_model** (this repo) - Bayesian modeling & change detection
3. [emma_change_classification](https://github.com/AdamWilsonLab/emma_change_classification) - Classification
4. [emma_report](https://github.com/AdamWilsonLab/emma_report) - Reporting

## Core Workflow (targets)

The entire pipeline is orchestrated by the `targets` package via [_targets.R](_targets.R):

```r
# Run the full pipeline
Rscript run.R
# Or directly: targets::tar_make()
```

**Key target groups**:
- **Data download**: `envdata_files` uses `piggyback` to download data from GitHub releases (`emma_envdata` repo)
- **Data filtering**: `long_pixels` → `envdata` → `data_training` filters pixels with sufficient fire-free periods
- **Stan data prep**: `create_stan_data()` assembles list for Stan with training/testing splits
- **Model fitting**: `tar_stan_vb()` runs variational Bayes (VB) inference on [postfire_season.stan](postfire_season.stan)
- **Prediction**: `model_w_pred` uses [postfire_season_predict.stan](postfire_season_predict.stan) for new data
- **Outputs**: `spatial_outputs`, `release_stan_outputs`, `release_html` publish to GitHub releases

**Time windows** (configured in [_targets.R](_targets.R) lines 70-73):
```r
training_window = c("2000-01-01","2014-07-01")
testing_window = c("2014-07-01","2022-01-01")
predicting_window = c("2021-01-01","2022-01-01")
```

## Stan Model Architecture

The core model ([postfire_season.stan](postfire_season.stan)) is a hierarchical nonlinear growth model with seasonal component:

```stan
mu[i] = alpha[pid] + gamma[pid] - gamma[pid]*exp(-(age[i]/lambda[pid])) + 
        sin((phi + ((firemonth[i]-1)*π/6)) + 2π*age[i]) * A[pid]
```

**Parameters** (all pixel-specific except phi):
- `alpha`: baseline NDVI (intercept)
- `gamma`: asymptotic recovery magnitude
- `lambda`: recovery rate (time constant)
- `A`: seasonal amplitude
- `phi`: global phase shift for seasonality

**Environmental effects**: `gamma`, `lambda`, and `A` have hierarchical priors linked to environmental covariates via regression (`x*beta` in transformed parameters block).

**Fitting approach**: Uses variational Bayes (`tar_stan_vb`) with ~1M iterations, not MCMC (too slow for this scale). Output format is Parquet for memory efficiency.

### Alternative: State Space Model

**File**: [postfire_ssm.stan](postfire_ssm.stan) - Separates process variance from observation noise

**Structure**:
- Latent state `z[t]`: True vegetation state (unobserved)
- State equation: `z[t] ~ Normal(μ[t] + ρ(z[t-1] - μ[t-1]), σ)` (Ornstein-Uhlenbeck)
- Observation: `y[t] ~ Normal(z[t], τ)` (measurement error)

**Advantages**: Smoothing, handles missing data, separates real variation (σ) from sensor noise (τ), forecasting with proper uncertainty

**Use when**: Noisy data, irregular sampling, missing observations, or need forecasts. ~2-3× slower but worth it for degraded data quality.

**Functions**: `create_stan_data_ssm()`, `extract_latent_states()`, `extract_forecasts()` in [R/state_space_functions.R](R/state_space_functions.R)

## Data Pipeline Patterns

### Spatial filtering workflow
1. **Find long records** ([R/find_long_records.R](R/find_long_records.R)): Identifies pixels with sufficient pre/post-fire data
2. **Tidy static data** ([R/tidy_static_data.R](R/tidy_static_data.R)): Filters by region, remnant distance (2km buffer), samples pixels
3. **Tidy dynamic data** ([R/tidy_dynamic_data.R](R/tidy_dynamic_data.R)): Filters NDVI time series by date window
4. **Filter training data** ([R/filter_training_data.R](R/filter_training_data.R)): Selects environmental variables (`envvars` target)

### Environmental variables
Selected in `envvars` target ([_targets.R](_targets.R) lines 119-132):
- CHELSA bioclimatic variables (precipitation, temperature)
- MODIS cloud frequency metrics
- ALOS topographic diversity

**Convention**: Rename covariates using named vector for clarity in outputs.

### Stan data structure
Created by [R/create_stan_data.R](R/create_stan_data.R):
```r
stan_data = list(
  N = nrow(dyndata),        # total observations
  J = nrow(data),           # number of pixels
  P = ncol(xvar),           # number of environmental vars
  pid = dyndata$pid,        # pixel ID vector (links obs to pixel)
  age = dyndata$age,        # time since fire
  firemonth = dyndata$firemonth,  # month of fire (1-12)
  y_obs = dyndata$ndvi,     # observed NDVI
  x = xvar,                 # environmental matrix (J x P)
  fit = 1, predict = 1      # switches for likelihood/prediction
)
```

## Release & Data Management

**piggyback** is used throughout for large file transfers via GitHub releases:

- **Download**: `robust_pb_download()` (from emma_envdata repo) fetches input data from `emma_envdata` releases
- **Upload**: `robust_pb_upload()` ([R/robust_pb_upload.R](R/robust_pb_upload.R)) and `release_stan_objects()` ([R/release_stan_objects.R](R/release_stan_objects.R)) publish outputs
- **Robustness**: Functions implement retry logic (`max_attempts`, `sleep_time`) for API rate limits
- **Formats**: Stan objects saved as both RDS and Parquet for compatibility

**Convention**: Use `tag = "current"` for latest data, `tag = "model_output"` for results.

## HPC Execution

For cluster deployment, use SLURM scripts:
- [slurm_verbose.sbatch](slurm_verbose.sbatch): 160GB RAM, 10-day time limit
- Uses Singularity/Apptainer containers (`AdamWilsonLab-emma_docker-latest.sif`)
- Key paths: `/panasas/scratch/grp-adamw/` for cache, `/projects/academic/adamw/users/` for code

**cmdstan installation**: [_targets.R](_targets.R) auto-installs cmdstan if not found (lines 56-64).

## Development Conventions

- **Function files**: Each R function in `R/` is a single file (e.g., `R/create_stan_data.R`)
- **No interactive execution**: Pipeline designed for batch execution via `targets::tar_make()`
- **Debugging**: Use `tar_option_set(debug = "target_name")` to step into specific target
- **Testing**: Minimal tests in `tests/testthat/` - focus is on pipeline integrity via targets
- **Sampling**: Control via `sample_proportion` ([_targets.R](_targets.R) line 78) - set to 1 for full data, <1 for testing

## Key Files Reference

- [_targets.R](_targets.R): Complete pipeline definition
- [postfire_season.stan](postfire_season.stan): Core fitting model
- [postfire_season_predict.stan](postfire_season_predict.stan): Prediction model
- [R/model_functions.R](R/model_functions.R): `summarize_model_output()`, `summarize_predictions()`
- [R/create_stan_data.R](R/create_stan_data.R): Data assembly for Stan
- [run.R](run.R): Entry point with GitHub PAT authorization
- [index.Rmd](index.Rmd): Report rendering (via `tar_render()`)

## When Making Changes

- **Adding covariates**: Update `envvars` target in [_targets.R](_targets.R), ensure data exists in emma_envdata
- **Modifying model**: Edit [postfire_season.stan](postfire_season.stan), recompile happens automatically
- **Changing time windows**: Update `training_window`/`testing_window`/`predicting_window` in [_targets.R](_targets.R)
- **New functions**: Add to `R/` directory, sourced automatically (see [_targets.R](_targets.R) lines 36-39)
- **Output formats**: Modify `output_samples` ([_targets.R](_targets.R) line 80) - fewer samples = faster but less posterior resolution
