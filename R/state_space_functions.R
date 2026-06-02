#' Create Stan data for state space model
#' 
#' @param data Static data (environmental covariates)
#' @param dyndata Dynamic data (NDVI time series)
#' @param fit Whether to fit (1) or sample from prior (0)
#' @param forecast Whether to generate forecasts
#' @param n_forecast Number of forecast steps per pixel (e.g., 23 for 1 year at 16-day intervals)
#' @return List formatted for postfire_ssm.stan

create_stan_data_ssm <- function(data, dyndata, fit = 1, 
                                 forecast = 0, n_forecast = 23,
                                 ndvi_priors = NULL) {
  
  library(dplyr)
  
  # Link cellID to pid
  pid_lookup <- data %>%
    dplyr::select(cellID, pid) %>%
    arrange(pid)
  
  # Sort by pixel, then time
  dyndata2 <- dyndata %>%
    left_join(pid_lookup) %>%
    filter(!is.na(pid), !is.na(ndvi)) %>%
    arrange(pid, date)
  
  # Flag missing/cloudy observations
  # Could use additional criteria (e.g., cloud flags, NDVI quality flags)
  dyndata2 <- dyndata2 %>%
    mutate(
      y_missing = as.integer(is.na(ndvi) | ndvi < -0.5),  # Flag bad values
      ndvi = if_else(y_missing == 1, 0, ndvi),  # Replace with dummy for Stan
      age = if_else(is.na(age) | age < 0, 0, age),
      firemonth = if_else(is.na(firemonth), 4, firemonth)
    )
  
  # Calculate pixel indices
  pixel_info <- dyndata2 %>%
    group_by(pid) %>%
    summarize(
      n_obs = n(),
      start_idx = min(row_number()),
      end_idx = max(row_number()),
      .groups = 'drop'
    ) %>%
    arrange(pid) %>%
    mutate(
      start_idx = cumsum(c(1, n_obs[-n()])),
      end_idx = cumsum(n_obs)
    )
  
  # Time variable (days since first observation)
  min_date <- min(dyndata2$date)
  dyndata2 <- dyndata2 %>%
    mutate(obs_time = as.numeric(difftime(date, min_date, units = "days")))
  
  # Extract environment covariates
  xvar <- data %>%
    arrange(pid) %>%
    dplyr::select(-cellID, -pid)
  
  # Set defaults for NDVI priors (will be overridden if ndvi_priors provided)
  informative_ndvi_priors <- 0
  ndvi_beta_0_mean <- 0
  ndvi_beta_0_sd <- 1
  ndvi_beta_1_mean <- 0
  ndvi_beta_1_sd <- 1
  ndvi_beta_2_mean <- 0
  ndvi_beta_2_sd <- 1
  
  # If informative priors provided, use them
  if (!is.null(ndvi_priors)) {
    if (isTRUE(ndvi_priors$use_informative)) {
      informative_ndvi_priors <- 1
      ndvi_beta_0_mean <- ndvi_priors$beta_0_mean %||% 0
      ndvi_beta_0_sd <- ndvi_priors$beta_0_sd %||% 1
      ndvi_beta_1_mean <- ndvi_priors$beta_1_mean %||% 0
      ndvi_beta_1_sd <- ndvi_priors$beta_1_sd %||% 1
      ndvi_beta_2_mean <- ndvi_priors$beta_2_mean %||% 0
      ndvi_beta_2_sd <- ndvi_priors$beta_2_sd %||% 1
    }
  }
  
  # Assemble Stan data
  stan_data <- list(
    # Dimensions
    N = nrow(dyndata2),
    J = nrow(data),
    P = ncol(xvar),
    
    # Pixel structure
    pixel_start = pixel_info$start_idx,
    pixel_end = pixel_info$end_idx,
    n_obs = pixel_info$n_obs,
    
    # Observations
    obs_time = dyndata2$obs_time,
    y_obs = dyndata2$ndvi,
    y_missing = dyndata2$y_missing,
    
    # Fire information
    age = dyndata2$age,
    firemonth = dyndata2$firemonth,
    
    # Environment
    x = as.matrix(xvar),
    
    # Switches
    fit = fit,
    forecast = forecast,
    n_forecast = n_forecast,
    
    # NDVI priors (biomass-to-NDVI regression)
    informative_ndvi_priors = informative_ndvi_priors,
    ndvi_beta_0_mean = ndvi_beta_0_mean,
    ndvi_beta_0_sd = ndvi_beta_0_sd,
    ndvi_beta_1_mean = ndvi_beta_1_mean,
    ndvi_beta_1_sd = ndvi_beta_1_sd,
    ndvi_beta_2_mean = ndvi_beta_2_mean,
    ndvi_beta_2_sd = ndvi_beta_2_sd,
    
    # Metadata
    y_date = as.numeric(dyndata2$date),
    y_cellID = dyndata2$cellID,
    x_cellID = data$cellID[order(data$pid)],
    min_date = as.numeric(min_date)
  )
  
  return(stan_data)
}


#' Extract latent states from SSM output
#' 
#' @param model_output Stan model output (summary)
#' @param stan_data The Stan data used for fitting
#' @return Tibble with latent state estimates

extract_latent_states <- function(model_output, stan_data) {
  
  library(dplyr)
  library(lubridate)
  
  # Extract state variables
  z_vars <- paste0("z[", 1:stan_data$N, "]")
  
  states <- model_output %>%
    filter(variable %in% z_vars) %>%
    arrange(variable) %>%
    select(variable, mean, median, sd, q5, q95) %>%
    mutate(
      index = as.integer(gsub("z\\[|\\]", "", variable)),
      cellID = stan_data$y_cellID[index],
      date = as_date(stan_data$y_date[index], origin = "1970-01-01"),
      obs_ndvi = stan_data$y_obs[index],
      missing = stan_data$y_missing[index]
    ) %>%
    select(-variable, -index)
  
  return(states)
}


#' Extract forecasts from SSM
#' 
#' @param model_output Stan model output
#' @param stan_data Stan data with forecast enabled
#' @return Tibble with forecasts

extract_forecasts <- function(model_output, stan_data) {
  
  if(stan_data$forecast == 0) {
    stop("Forecasts not generated. Set forecast=1 in stan_data")
  }
  
  n_forecast_total <- stan_data$J * stan_data$n_forecast
  
  # Extract forecast variables
  z_forecast_vars <- paste0("z_forecast[", 1:n_forecast_total, "]")
  y_forecast_vars <- paste0("y_forecast[", 1:n_forecast_total, "]")
  
  z_forecasts <- model_output %>%
    filter(variable %in% z_forecast_vars) %>%
    arrange(variable)
  
  y_forecasts <- model_output %>%
    filter(variable %in% y_forecast_vars) %>%
    arrange(variable)
  
  # Reconstruct pixel and time structure
  min_date <- as_date(stan_data$min_date, origin = "1970-01-01")
  
  forecasts <- tibble(
    pixel_idx = rep(1:stan_data$J, each = stan_data$n_forecast),
    forecast_step = rep(1:stan_data$n_forecast, stan_data$J)
  ) %>%
    mutate(
      cellID = stan_data$x_cellID[pixel_idx],
      # Calculate forecast dates (16-day MODIS intervals)
      days_ahead = forecast_step * 16,
      # Last observation date per pixel
      last_obs_date = min_date + 
        sapply(pixel_idx, function(j) {
          max(stan_data$obs_time[stan_data$pixel_start[j]:stan_data$pixel_end[j]])
        }),
      forecast_date = last_obs_date + days_ahead,
      
      # State forecasts
      z_mean = z_forecasts$mean,
      z_median = z_forecasts$median,
      z_sd = z_forecasts$sd,
      z_q5 = z_forecasts$q5,
      z_q95 = z_forecasts$q95,
      
      # Observation forecasts
      y_mean = y_forecasts$mean,
      y_median = y_forecasts$median,
      y_sd = y_forecasts$sd,
      y_q5 = y_forecasts$q5,
      y_q95 = y_forecasts$q95
    )
  
  return(forecasts)
}


#' Compare SSM vs deterministic model
#' 
#' @param ssm_states Output from extract_latent_states
#' @param deterministic_preds Predictions from standard model
#' @return Comparison metrics

compare_ssm_deterministic <- function(ssm_states, deterministic_preds) {
  
  library(dplyr)
  
  comparison <- ssm_states %>%
    left_join(
      deterministic_preds %>% select(cellID, date, det_median = median),
      by = c("cellID", "date")
    ) %>%
    filter(!is.na(det_median), missing == 0)
  
  metrics <- list(
    # State uncertainty (unique to SSM)
    mean_state_uncertainty = mean(ssm_states$sd),
    
    # Prediction comparison
    ssm_rmse = sqrt(mean((comparison$median - comparison$obs_ndvi)^2)),
    det_rmse = sqrt(mean((comparison$det_median - comparison$obs_ndvi)^2)),
    
    # Coverage
    ssm_coverage = mean(comparison$obs_ndvi >= comparison$q5 & 
                        comparison$obs_ndvi <= comparison$q95),
    
    # Correlation with observations
    ssm_cor = cor(comparison$median, comparison$obs_ndvi),
    det_cor = cor(comparison$det_median, comparison$obs_ndvi)
  )
  
  return(list(
    comparison = comparison,
    metrics = metrics
  ))
}


#' Smooth vs filter (diagnostic)
#' 
#' @description Compare filtered estimates (using only past data) vs 
#'   smoothed estimates (using all data) to assess state estimation
#' @param model_output Full Stan draws (not summary)
#' @return Smoothing gain metric

diagnose_smoothing <- function(model_output) {
  
  # This would require running forward filtering separately
  # and comparing to full posterior (which includes future info)
  
  # For now, just check state autocorrelation
  z_draws <- model_output %>%
    select(starts_with("z[")) %>%
    as.matrix()
  
  # Calculate autocorrelation in states
  acf_values <- apply(z_draws, 2, function(col) {
    acf(col, lag.max = 1, plot = FALSE)$acf[2]
  })
  
  return(tibble(
    mean_acf = mean(acf_values),
    median_acf = median(acf_values),
    interpretation = if_else(
      mean_acf > 0.5,
      "High autocorrelation: smoothing is helpful",
      "Low autocorrelation: similar to independent observations"
    )
  ))
}
