/*
 * State Space Model for Post-Fire Recovery
 * 
 * Latent state `z[t]` represents true aboveground biomass (g/m² or other units).
 * Observations are primarily NDVI, linked to biomass via a regression model.
 * The recovery trajectory models biomass accumulation post-fire.
 *
 * Structure:
 * - Latent state: z[t] = true biomass (unobserved)
 * - Process model: z[t] follows recovery curve + process noise (Ornstein-Uhlenbeck)
 * - Observation model: y_obs[t] (NDVI) = f(z[t]) + measurement error
 *   where f(z) = β₀ + β₁*z + β₂*z² (biomass → NDVI regression)
 */

data {
  int<lower=0> N;                     // total observations across all pixels
  int<lower=0> J;                     // number of pixels
  int<lower=0> P;                     // number of environmental vars

  // Pixel structure (ragged array) — maps observations to pixels
  array[J] int<lower=1,upper=N> pixel_start;  // first observation index for each pixel
  array[J] int<lower=1,upper=N> pixel_end;    // last observation index for each pixel
  array[J] int<lower=1> n_obs;        // count of observations per pixel

  // Observations — what we actually measure
  vector[N] obs_time;                              // time of each observation (days since start)
  vector<lower=-1,upper=1>[N] y_obs;               // observed NDVI (satellite proxy for biomass)
  array[N] int<lower=0,upper=1> y_missing;         // 1 = skip in likelihood (cloud/sensor error)

  // Fire and season information — recovery curve drivers
  vector<lower=0>[N] age;                          // time since fire in years (x-axis of recovery)
  vector<lower=1,upper=12>[N] firemonth;           // month when fire occurred (1-12, for seasonality)

  // Environmental covariates (pixel-level) — affect recovery parameters via hierarchical regression
  matrix[J,P] x;                                   // environment matrix: J pixels × P predictors

  // Control switches — run modes
  int<lower=0,upper=1> fit;                        // 1=fit to data, 0=sample from prior only
  int<lower=0,upper=1> forecast;                   // 1=generate future projections
  int<lower=0> n_forecast;                         // number of forecast steps per pixel (e.g., 23)

  // Optional informative priors for biomass-to-NDVI regression (from literature)
  int<lower=0,upper=1> informative_ndvi_priors;    // 1=use literature values, 0=weak defaults
  real ndvi_beta_0_mean;  real<lower=0> ndvi_beta_0_sd;    // intercept prior: NDVI @ zero biomass
  real ndvi_beta_1_mean;  real<lower=0> ndvi_beta_1_sd;    // slope prior: NDVI per unit biomass
  real ndvi_beta_2_mean;  real<lower=0> ndvi_beta_2_sd;    // quadratic prior: saturation effect
}

transformed data {
  // Time increments between consecutive observations (in years) — scales process error and mean reversion
  vector[N] dt;
  for (j in 1:J) {
    int start = pixel_start[j];
    int end = pixel_end[j];
    dt[start] = 0;  // no time step before first observation
    for (i in (start + 1):end) {
      dt[i] = (obs_time[i] - obs_time[i - 1]) / 365.23;  // convert days to years
    }
  }
}

parameters {
  // Recovery parameters (pixel-level) — shape the monomolecular biomass trajectory
  vector<lower=0>[J] alpha;           // baseline biomass: post-fire initial value
  vector<lower=0>[J] gamma;           // asymptotic biomass: maximum recovery level
  vector<lower=0.01>[J] lambda;       // recovery time constant: years to reach ~63% recovery
  vector<lower=0>[J] A;               // seasonal amplitude: biomass variation within year

  // Hierarchical parameters (relate recovery parameters to environment via regression)
  vector<lower=0> alpha_mu;                         // baseline log-mean (intercept for alpha)
  vector[P] gamma_beta;                             // environment effects on log(gamma) — affects recovery magnitude
  vector[P] lambda_beta;                            // environment effects on log(lambda) — affects recovery speed
  vector[P] A_beta;                                 // environment effects on log(A) — affects seasonality amplitude
  real phi;                           // global phase shift: temporal offset for seasonal sine wave

  // Variance components — quantify uncertainty at each stage
  real<lower=0> tau_sq;               // NDVI observation error: sensor noise and atmospheric effects
  real<lower=0> sigma_sq;             // biomass process innovation: ecological variation (stochasticity)
  real<lower=0> gamma_tau_sq;         // between-pixel variance in recovery magnitude
  real<lower=0> lambda_tau_sq;        // between-pixel variance in recovery rate
  real<lower=0> alpha_tau_sq;         // between-pixel variance in baseline biomass
  real<lower=0> A_tau_sq;             // between-pixel variance in seasonality amplitude

  // Biomass-to-NDVI regression parameters — link latent biomass to observed NDVI
  real ndvi_beta_0;                   // intercept: expected NDVI when biomass = 0 (typically negative)
  real ndvi_beta_1;                   // linear slope: NDVI increase per unit biomass (typically positive)
  real ndvi_beta_2;                   // quadratic term: NDVI saturation at high biomass (typically negative)

  // Latent state: true aboveground biomass (g/m² or similar units) — primary quantity we estimate
  vector<lower=0>[N] z;               // biomass at each observation: unobserved but inferred from NDVI
}

transformed parameters {
  // Hierarchical means for recovery parameters — environment-dependent trajectories
  vector[J] gamma_mu = x * gamma_beta;        // expected log(gamma) per pixel from environment
  vector[J] lambda_mu = x * lambda_beta;      // expected log(lambda) per pixel from environment
  vector[J] A_mu = x * A_beta;                // expected log(A) per pixel from environment

  // Expected biomass trajectory (deterministic recovery curve) — target for latent state to revert toward
  vector[N] mu;
  for (j in 1:J) {
    int start = pixel_start[j];
    int end = pixel_end[j];
    for (i in start:end) {
      // Monomolecular (logistic-like) recovery with seasonal oscillation
      mu[i] = alpha[j]                                                     // baseline (post-fire minimum)
            + gamma[j] * (1 - exp(-age[i] / lambda[j]))                     // asymptotic approach to climax
            + A[j] * sin(phi + (firemonth[i] - 1) * pi() / 6 + 2 * pi() * age[i]);  // seasonal cycle
    }
  }

  // Expected NDVI from latent biomass (quadratic regression) — used in observation likelihood
  vector[N] ndvi_expected;
  for (i in 1:N) {
    ndvi_expected[i] = ndvi_beta_0                                   // intercept (NDVI at zero biomass)
                     + ndvi_beta_1 * z[i]                             // linear response (main signal)
                     + ndvi_beta_2 * square(z[i]);                    // quadratic saturation term
  }

  // Standard deviations (SD versions of variances for normal distributions)
  real tau = sqrt(tau_sq);             // NDVI measurement error SD
  real sigma = sqrt(sigma_sq);         // biomass process error SD
  real gamma_tau = sqrt(gamma_tau_sq); // SD of between-pixel variation in gamma
  real lambda_tau = sqrt(lambda_tau_sq);  // SD of between-pixel variation in lambda
  real alpha_tau = sqrt(alpha_tau_sq); // SD of between-pixel variation in alpha
  real A_tau = sqrt(A_tau_sq);         // SD of between-pixel variation in A
}

model {
  // Priors for noise components — heavy-tailed Student-t allows occasional large deviations
  tau ~ student_t(4, 0, 0.05);         // NDVI measurement error (satellite sensors are precise)
  sigma ~ student_t(4, 0, 0.1);        // biomass process error (ecological stochasticity)
  gamma_tau ~ student_t(4, 0, 1);      // prior on SD of recovery magnitude variation
  lambda_tau ~ student_t(4, 0, 1);     // prior on SD of recovery rate variation
  alpha_tau ~ student_t(4, 0, 1);      // prior on SD of baseline variation
  A_tau ~ student_t(4, 0, 1);          // prior on SD of seasonality variation

  // Hyperpriors for hierarchical parameters — control environment effects
  alpha_mu ~ normal(0.1, 0.2);         // prior on mean log(alpha) across pixels
  gamma_beta ~ normal(0, 1);           // prior on environment effects on log(gamma)
  lambda_beta ~ normal(0, 1);          // prior on environment effects on log(lambda)
  A_beta ~ normal(0, 0.5);             // prior on environment effects on log(A)
  phi ~ uniform(-pi(), pi());          // prior on seasonal phase (uninformative)

  // Hierarchical priors for recovery parameters — lognormal ensures positivity
  alpha ~ lognormal(alpha_mu, alpha_tau);         // per-pixel baseline biomass (positive)
  gamma ~ lognormal(gamma_mu, gamma_tau);         // per-pixel asymptotic biomass (positive)
  lambda ~ lognormal(lambda_mu, lambda_tau);      // per-pixel recovery time constant (positive)
  A ~ lognormal(A_mu, A_tau);                     // per-pixel seasonal amplitude (positive)

  // Priors for biomass-to-NDVI regression — can be weak or literature-informed
  if (informative_ndvi_priors == 1) {
    // Use literature-derived informative priors (e.g., from published biomass-NDVI studies)
    ndvi_beta_0 ~ normal(ndvi_beta_0_mean, ndvi_beta_0_sd);         // literature intercept
    ndvi_beta_1 ~ normal(ndvi_beta_1_mean, ndvi_beta_1_sd);         // literature slope
    ndvi_beta_2 ~ normal(ndvi_beta_2_mean, ndvi_beta_2_sd);         // literature quadratic
  } else {
    // Weak default priors when literature values unavailable
    ndvi_beta_0 ~ normal(-0.2, 0.5);    // intercept: NDVI typically negative at zero biomass
    ndvi_beta_1 ~ normal(0.001, 0.002); // slope: weak positive relationship with biomass
    ndvi_beta_2 ~ normal(0, 0.0001);    // quadratic: usually weak, allows saturation
  }

  // State space model likelihood (only if fit == 1)
  if (fit == 1) {
    for (j in 1:J) {
      int start = pixel_start[j];
      int end = pixel_end[j];

      // Initial state prior — first biomass is near trajectory with process uncertainty
      z[start] ~ normal(mu[start], sigma);         // biomass starts at trajectory ± process noise

      // State transitions (Ornstein-Uhlenbeck: mean-reverting toward recovery trajectory)
      for (i in (start + 1):end) {
        // Latent biomass pulled toward deterministic trajectory with stochastic noise
        real rho = exp(-dt[i] / 0.5);              // mean-reversion strength: approaches 1 as dt→0
        real z_expected = mu[i] + rho * (z[i - 1] - mu[i - 1]);  // trajectory + weighted persistence
        real innovation_sd = sigma * sqrt(dt[i]);   // process noise scales with time interval
        z[i] ~ normal(z_expected, innovation_sd);   // biomass evolves stochastically
      }

      // NDVI observation model — data likelihood given latent biomass
      for (i in start:end) {
        if (y_missing[i] == 0) {                   // skip cloudy/missing observations
          y_obs[i] ~ normal(ndvi_expected[i], tau);  // observed NDVI from biomass via regression + noise
        }
      }
    }
  }
}

generated quantities {
  // Predictions and diagnostic outputs — for model evaluation and visualization
  array[N] real y_pred;           // NDVI predictions from posterior biomass estimates
  array[N] real z_pred;           // predicted biomass states (with smoothing jitter)
  vector[N] log_lik;              // pointwise NDVI log-likelihood (for leave-one-out cross-validation)

  for (i in 1:N) {
    // NDVI prediction: draw from posterior predictive distribution
    y_pred[i] = normal_rng(ndvi_expected[i], tau);    // predicted NDVI with observation noise
    if (y_missing[i] == 0) {
      log_lik[i] = normal_lpdf(y_obs[i] | ndvi_expected[i], tau);  // likelihood of observed NDVI
    } else {
      log_lik[i] = 0;                                  // no contribution from missing data
    }

    // Biomass state prediction — draw posterior biomass with tiny smoothing jitter
    z_pred[i] = normal_rng(z[i], 0.01);                // posterior biomass (jitter for visualization)
  }

  // Forecasts: probabilistic projections into the future (if forecast == 1)
  array[J * n_forecast] real y_forecast;            // future NDVI observations
  array[J * n_forecast] real z_forecast;            // future latent biomass (accumulating uncertainty)
  if (forecast == 1) {
    int idx = 1;
    for (j in 1:J) {
      int end = pixel_end[j];                        // last observation for pixel j
      real last_age = age[end];                      // fire age at end of time series
      real last_z = z[end];                          // final estimated biomass
      real fm = firemonth[end];                      // fire month (for seasonality)

      for (k in 1:n_forecast) {
        // Project forward by 16-day intervals (MODIS Landsat revisit cycle)
        real future_age = last_age + (k * 16.0) / 365.23;     // fire age in forecast period (years)

        // Expected biomass at future time (deterministic recovery trajectory)
        real mu_future = alpha[j]                                                      // baseline
                       + gamma[j] * (1 - exp(-future_age / lambda[j]))                 // asymptotic approach
                       + A[j] * sin(phi + (fm - 1) * pi() / 6 + 2 * pi() * future_age);  // seasonality

        // Forecast latent biomass (mean-reverting with accumulating process uncertainty)
        real dt_forecast = (k * 16.0) / 365.23;                 // forecast time step (years)
        real rho = exp(-dt_forecast / 0.5);                     // mean-reversion coefficient
        real z_expected = mu_future + rho * (last_z - mu[end]); // expected biomass (persistence + drift)
        real innovation_sd = sigma * sqrt(dt_forecast);          // increasing uncertainty over time
        z_forecast[idx] = normal_rng(z_expected, innovation_sd); // stochastic biomass forecast

        // Forecast NDVI from forecasted biomass (final step: biomass → NDVI)
        y_forecast[idx] = normal_rng(
          ndvi_beta_0 + ndvi_beta_1 * z_forecast[idx] + ndvi_beta_2 * square(z_forecast[idx]),  // regression
          tau                                                     // observation noise
        );

        idx += 1;                                               // increment forecast index
      }
    }
  }
}
