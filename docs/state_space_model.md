# State Space Model for Post-Fire Recovery

## Conceptual Framework

### Current Model (Deterministic)
```
NDVI[t] ~ Normal(μ[t], τ)
μ[t] = f(age, parameters, seasonality)
```
- Observations are independent given parameters
- All variation attributed to measurement error
- Cannot distinguish process vs observation noise

### State Space Model (Stochastic)
```
State equation:    z[t] ~ Normal(g(z[t-1], μ[t]), σ)
Observation model: y[t] ~ Normal(z[t], τ)
```

**Two sources of variation**:
1. **Process noise (σ)**: Real environmental variation (weather, disturbance, competition)
2. **Observation noise (τ)**: Sensor error, atmospheric effects, geolocation uncertainty

**Key benefit**: Latent state `z[t]` is smoothed using all observations, reducing noise.

## Model Components

### 1. State Transition (Process Model)

The true vegetation state evolves according to:
```
z[t] | z[t-1] ~ Normal(μ[t] + ρ(z[t-1] - μ[t-1]), σ√Δt)
```

**Interpretation**:
- `μ[t]`: Deterministic recovery trajectory (same as original model)
- `ρ`: Mean reversion parameter (state pulled toward trajectory)
- `σ`: Process noise (environmental stochasticity)
- `Δt`: Time step (irregular sampling handled naturally)

This is an **Ornstein-Uhlenbeck process** - the state is attracted to the deterministic curve but can deviate due to environmental variation.

### 2. Observation Model

Observed NDVI relates to true state:
```
y_obs[t] ~ Normal(z[t], τ)
```

**Handles**:
- Measurement error
- Atmospheric contamination
- Sensor calibration uncertainty
- Missing data (no contribution to likelihood when `y_missing[t] = 1`)

### 3. Recovery Parameters

Same hierarchical structure as original model:
- Pixel-specific: α (baseline), γ (magnitude), λ (rate), A (seasonality)
- Environmental effects: γ, λ, A linked to covariates
- Hyperparameters: population-level distributions

## Advantages Over Deterministic Model

### 1. Separates Noise Sources
```
Total variance = Process variance (σ²) + Observation variance (τ²)
```
- **Process variance** → inherent ecosystem variability (droughts, management, competition)
- **Observation variance** → sensor/atmospheric issues

### 2. Smoothing
Latent states incorporate information from neighboring timepoints:
```
E[z[t] | data] uses past AND future observations
```
Result: Smoother trajectories, better estimates in noisy periods.

### 3. Handles Missing Data
Missing observations (clouds, sensor failures) naturally accommodated:
- State still evolves during gaps
- Uncertainty increases appropriately

### 4. Forecasting
Can project forward with accumulating uncertainty:
```
z[t+k] = μ[t+k] + ρᵏ(z[t] - μ[t]) ± σ√k
```
Uncertainty grows as forecast horizon increases.

### 5. Irregular Sampling
Time step `Δt` scales process noise:
```
σ_effective = σ√Δt
```
Longer gaps → more uncertainty (realistic)

## When to Use State Space vs Deterministic

### Use State Space if:
- High observation noise (cloudy regions, poor sensor quality)
- Interest in underlying "true" trajectory
- Need forecasts with proper uncertainty
- Irregular or sparse sampling
- Missing data common
- Want to estimate process vs observation variance

### Use Deterministic if:
- Clean data with low noise
- Computational constraints (SSM slower ~2-3×)
- Interpretability is priority (simpler model)
- Only care about average trajectory

## Practical Considerations

### Identifiability
Process vs observation variance can be confounded. Helps to:
1. Use informative priors: `τ ~ student_t(4, 0, 0.05)` (NDVI measurement typically precise)
2. Have dense sampling (more time resolution → easier separation)
3. Compare models with known observation error

### Computational Cost
- Latent states add N parameters (one per observation)
- Variational Bayes: ~2-3× slower than deterministic
- MCMC: ~5-10× slower
- Worth it for noisy data

### Prior Specification
```stan
tau ~ student_t(4, 0, 0.05);    // Small: MODIS NDVI is fairly precise
sigma ~ student_t(4, 0, 0.1);   // Moderate: real environmental variation
```

**Rule of thumb**: Set `τ` based on known sensor specs, let data inform `σ`.

## Extensions

### 1. Time-Varying Parameters
Allow recovery rate to change with climate:
```stan
lambda[j,t] = exp(lambda_mu[j] + climate_effect[t])
```

### 2. Non-Gaussian Innovations
Use Student-t for heavy-tailed process noise (extreme events):
```stan
z[i] ~ student_t(df, z_expected, innovation_sd);
```

### 3. Multivariate States
Track multiple vegetation properties (NDVI, EVI, LAI):
```stan
vector[3] z[t];  // [NDVI, EVI, LAI]
z[t] ~ multi_normal(mu[t], Sigma);
```

### 4. Spatial Dependencies
Let nearby pixels have correlated innovations:
```stan
Sigma[i,j] = sigma_sq * exp(-distance[i,j] / range)
```

### 5. Regime Switching
Discrete states (e.g., fire vs no-fire):
```stan
if(regime[t] == FIRE) {
  z[t] ~ normal(0.1, 0.05);  // Post-fire low NDVI
} else {
  z[t] ~ normal(mu[t], sigma);  // Normal recovery
}
```

## Usage Example

```r
# Prepare data
stan_data <- create_stan_data_ssm(
  data = data_training,
  dyndata = dyndata_training,
  fit = 1,
  forecast = 1,
  n_forecast = 23  # 1 year ahead at 16-day intervals
)

# Fit model
model_ssm <- tar_stan_vb(
  model_ssm,
  stan_files = "postfire_ssm.stan",
  data = stan_data,
  iter = 100000,
  output_samples = 50,
  format_df = "parquet"
)

# Extract results
latent_states <- extract_latent_states(model_ssm_summary, stan_data)
forecasts <- extract_forecasts(model_ssm_summary, stan_data)

# Compare to deterministic
comparison <- compare_ssm_deterministic(latent_states, deterministic_preds)
print(comparison$metrics)
```

## Validation

### Check Convergence
- Higher dimensional → more challenging
- Monitor ELBO convergence
- Check if `sigma` and `tau` are separable

### Posterior Predictive Checks
```r
# Should see smoother z than y_obs
ggplot(latent_states) +
  geom_line(aes(date, obs_ndvi), alpha = 0.3) +
  geom_line(aes(date, median), color = "blue") +
  geom_ribbon(aes(date, ymin = q5, ymax = q95), alpha = 0.2)
```

### Compare Models
```r
# LOO cross-validation (use log_lik)
loo_ssm <- loo(model_ssm, "log_lik")
loo_det <- loo(model_det, "log_lik")
loo_compare(loo_ssm, loo_det)
```

## Literature

- **Kalman Filter**: Classic SSM for linear Gaussian systems
- **Particle Filter**: For non-linear/non-Gaussian dynamics
- **Bayesian SSM**: Stan enables full posterior on states AND parameters
- **Ecological applications**: Population dynamics, phenology, disease spread

## References

- Durbin & Koopman (2012) "Time Series Analysis by State Space Methods"
- West & Harrison (1997) "Bayesian Forecasting and Dynamic Models"  
- Auger-Méthé et al. (2021) "A guide to state-space modeling of ecological time series"
