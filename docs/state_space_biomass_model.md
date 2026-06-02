# State Space Model for Post-Fire Biomass Recovery

## Overview

The restructured state space model treats **latent biomass as the primary state** and uses NDVI as an observation linked via a regression model. This reflects the ecological reality that:

- True aboveground biomass (the quantity of interest) is unobserved at most timepoints
- NDVI is a noisy satellite-derived proxy for biomass
- Recovery trajectories describe biomass accumulation, not NDVI change directly

## Model Structure

### Latent State: Biomass $z_t$

The true biomass at each observation time is a latent variable $z_i$, measured in units determined by the data (e.g., g/m², kg/ha).

**Process Model** (mean-reverting toward recovery trajectory):
$$z_i \mid z_{i-1} \sim N(\mu_i + \rho(z_{i-1} - \mu_{i-1}), \sigma\sqrt{\Delta t_i})$$

where:
- $\mu_i$ = deterministic recovery trajectory at time $t_i$
- $\rho = e^{-\Delta t_i / 0.5}$ = mean-reversion rate (state pulled toward trajectory)
- $\sigma$ = process innovation std dev (represents real ecological variation)
- $\Delta t_i$ = time interval (years)

**Deterministic Recovery Curve** (per pixel $j$):
$$\mu_{i,j} = \alpha_j + \gamma_j(1 - e^{-\text{age}_i / \lambda_j}) + A_j \sin(\phi + \text{season}_i + 2\pi \cdot \text{age}_i)$$

Parameters:
- $\alpha_j$ = baseline biomass (post-fire minimum)
- $\gamma_j$ = asymptotic recovery (climax biomass)
- $\lambda_j$ = recovery rate (time constant, years)
- $A_j$ = seasonal amplitude
- $\phi$ = global phase shift

Recovery parameters are related to environmental covariates $\mathbf{x}_j$ via hierarchical regression:
$$\log(\gamma_j) = \mathbf{x}_j^T \boldsymbol{\beta}_\gamma, \quad \log(\lambda_j) = \mathbf{x}_j^T \boldsymbol{\beta}_\lambda, \quad \log(A_j) = \mathbf{x}_j^T \boldsymbol{\beta}_A$$

### Observation Model: NDVI $y_i$

NDVI observations are regressed on latent biomass:
$$y_i \mid z_i \sim N(\beta_0 + \beta_1 z_i + \beta_2 z_i^2, \tau^2)$$

where:
- $y_i$ = observed NDVI (range $[-1, 1]$)
- $\beta_0, \beta_1, \beta_2$ = biomass-to-NDVI regression coefficients
- $\tau$ = NDVI observation error std dev (typically ~0.05–0.1)

**Key Features:**
- Quadratic term $\beta_2 z_i^2$ allows saturation (NDVI plateaus at high biomass)
- This is a **regularization model**: NDVI observations constrain biomass estimates
- No direct biomass observations needed (they can be absent)

## Information Flow

```
Recovery trajectory (μ) 
    ↓
  Latent biomass (z_t) ← observed at time t
    ↓
  NDVI regression → Predicted NDVI
    ↓
  Observation likelihood: y_obs ~ Normal(pred_NDVI, τ)
```

## Implementation Details

### Stan Blocks

**Data block:**
- `y_obs[N]`: observed NDVI (primary data)
- `y_missing[N]`: missing/cloudy flag (1 = skip likelihood)
- `age[N]`, `firemonth[N]`: fire-relative timing
- `informative_ndvi_priors`: flag (1 = use literature values)
- `ndvi_beta_0_mean`, `ndvi_beta_1_mean`, `ndvi_beta_2_mean`: prior means
- `ndvi_beta_0_sd`, `ndvi_beta_1_sd`, `ndvi_beta_2_sd`: prior sds

**Parameters:**
- `z[N]`: latent biomass (lower bound = 0)
- `alpha[J]`, `gamma[J]`, `lambda[J]`, `A[J]`: per-pixel recovery parameters
- `ndvi_beta_0`, `ndvi_beta_1`, `ndvi_beta_2`: biomass-to-NDVI regression
- Hierarchical parameters and variance components

**Priors (on log-scale for multiplicative parameters):**
$$\alpha_j \sim \text{LogNormal}(\alpha_\mu, \alpha_\tau), \quad \gamma_j \sim \text{LogNormal}(\mathbf{x}_j \boldsymbol{\beta}_\gamma, \gamma_\tau)$$

**Biomass-to-NDVI regression priors (from literature or weak):**
- If `informative_ndvi_priors = 1`: use provided means/sds
- Else: weak priors ($\beta_1 \sim N(0.001, 0.002)$ to keep positive)

### R Helper Functions

**`create_stan_data_ssm(data, dyndata, fit=1, forecast=0, n_forecast=23, ndvi_priors=NULL)`**
- Assembles data list for `postfire_ssm.stan`
- If `ndvi_priors` list provided with `use_informative=TRUE`, sets `informative_ndvi_priors=1`
- Returns list with all required Stan inputs

**`extract_latent_states(model_output, stan_data)`**
- Extracts posterior summaries for latent biomass `z[i]`
- Returns tibble with estimates, CIs, and associated metadata

**`extract_forecasts(model_output, stan_data)`**
- Projects biomass and NDVI into future (if `forecast=1`)
- Returns per-pixel forecast paths with uncertainty

## Using Informative Priors

If you have literature-derived regression parameters (e.g., from a published biomass–NDVI study):

```r
ndvi_priors <- list(
  use_informative = TRUE,
  beta_0_mean = -0.15,    # literature intercept
  beta_0_sd = 0.05,       # uncertainty in intercept
  beta_1_mean = 0.0012,   # slope (NDVI per unit biomass)
  beta_1_sd = 0.0003,
  beta_2_mean = -0.00001, # quadratic (saturation)
  beta_2_sd = 0.000005
)

stan_data <- create_stan_data_ssm(
  data, dyndata, fit=1, forecast=1, n_forecast=23,
  ndvi_priors = ndvi_priors
)
```

## Advantages of This Structure

1. **Directly models biomass**: Recovery curves describe the quantity of interest
2. **Flexible observations**: Works without direct biomass data; NDVI provides indirect evidence
3. **Regularization via regression**: Biomass is regularized by the relationship to NDVI
4. **Forecasts**: Can project future biomass and NDVI with proper uncertainty
5. **Missing data handling**: Handles clouds and gaps naturally via SSM filtering
6. **Process vs. observation error**: Separates real ecological variation ($\sigma$) from sensor noise ($\tau$)

## Example Workflow

```r
library(targets)

# In _targets.R, create SSM-specific targets:
tar_target(
  ssm_data,
  create_stan_data_ssm(
    tidy_data,
    dyndata_tidy,
    fit = 1,
    forecast = 1,
    n_forecast = 23,
    ndvi_priors = list(use_informative = TRUE, ...)
  )
)

tar_stan_vb(
  ssm_fit,
  stan_file = "postfire_ssm.stan",
  data = ssm_data,
  iter_sampling = 5000,
  ...
)

# Extract results
latent_biomass <- extract_latent_states(ssm_fit, ssm_data)
forecasts <- extract_forecasts(ssm_fit, ssm_data)
```

## Comparison to Original Model

| Aspect | Original (deterministic) | SSM with NDVI |
|--------|--------------------------|---------------|
| State variable | NDVI recovery curve | Latent biomass trajectory |
| Observations | NDVI directly | NDVI via biomass regression |
| Biomass data | Optional, separate likelihood | Not needed (inferred) |
| Uncertainty quantification | Posterior on curve parameters | Posterior on latent states + observation error |
| Missing data | Skipped in likelihood | Smoothed via state transitions |
| Forecasts | Deterministic curve extension | Probabilistic biomass/NDVI paths |

## References

Ornstein–Uhlenbeck process: State mean-reversion toward a deterministic trajectory with Brownian noise (time-scaled by $\Delta t$).

Regression observation model: NDVI is a proxy, not the state; this keeps the focus on biomass recovery while leveraging satellite observations.
