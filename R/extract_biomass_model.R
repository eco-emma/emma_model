#' Extract biomass-NDVI relationship from SSM output
#' 
#' @param model_output Stan model summary
#' @return Tibble with regression parameters

extract_biomass_relationship <- function(model_output) {
  
  library(dplyr)
  
  params <- model_output %>%
    filter(variable %in% c("beta_0", "beta_1", "beta_2", "tau_biomass")) %>%
    select(variable, mean, median, sd, q5, q95)
  
  # Create interpretation
  beta_0 <- params %>% filter(variable == "beta_0") %>% pull(median)
  beta_1 <- params %>% filter(variable == "beta_1") %>% pull(median)
  beta_2 <- params %>% filter(variable == "beta_2") %>% pull(median)
  
  interpretation <- list(
    intercept = beta_0,
    linear_slope = beta_1,
    quadratic_term = beta_2,
    relationship = if_else(
      abs(beta_2) < 0.01,
      sprintf("Linear: biomass ≈ %.1f + %.1f × NDVI", beta_0, beta_1),
      sprintf("Quadratic: biomass ≈ %.1f + %.1f × NDVI + %.1f × NDVI²", 
              beta_0, beta_1, beta_2)
    )
  )
  
  return(list(
    parameters = params,
    interpretation = interpretation
  ))
}


#' Extract biomass predictions from SSM
#' 
#' @param model_output Stan model output
#' @param stan_data Stan data used for fitting
#' @return Tibble with biomass predictions

extract_biomass_predictions <- function(model_output, stan_data) {
  
  library(dplyr)
  library(lubridate)
  
  # Extract biomass predictions
  biomass_vars <- paste0("biomass_pred[", 1:stan_data$N, "]")
  
  biomass_preds <- model_output %>%
    filter(variable %in% biomass_vars) %>%
    arrange(variable) %>%
    select(variable, mean, median, sd, q5, q95) %>%
    mutate(
      index = as.integer(gsub("biomass_pred\\[|\\]", "", variable)),
      cellID = stan_data$y_cellID[index],
      date = as_date(stan_data$y_date[index], origin = "1970-01-01"),
      obs_biomass = stan_data$biomass_obs[index],
      biomass_available = stan_data$biomass_available[index],
      obs_ndvi = stan_data$y_obs[index]
    ) %>%
    select(-variable, -index)
  
  return(biomass_preds)
}


#' Validate biomass-NDVI model
#' 
#' @param biomass_preds Output from extract_biomass_predictions
#' @return Validation metrics

validate_biomass_model <- function(biomass_preds) {
  
  library(dplyr)
  
  # Only use observations where biomass was actually measured
  obs <- biomass_preds %>%
    filter(biomass_available == 1)
  
  if(nrow(obs) == 0) {
    stop("No biomass observations available for validation")
  }
  
  metrics <- list(
    n_observations = nrow(obs),
    rmse = sqrt(mean((obs$median - obs$obs_biomass)^2)),
    mae = mean(abs(obs$median - obs$obs_biomass)),
    r_squared = cor(obs$median, obs$obs_biomass)^2,
    coverage_90 = mean(obs$obs_biomass >= obs$q5 & obs$obs_biomass <= obs$q95),
    mean_biomass = mean(obs$obs_biomass),
    sd_biomass = sd(obs$obs_biomass)
  )
  
  # Prediction intervals
  obs <- obs %>%
    mutate(
      residual = obs_biomass - median,
      std_residual = residual / sd,
      in_ci = obs_biomass >= q5 & obs_biomass <= q95
    )
  
  return(list(
    metrics = metrics,
    predictions = obs
  ))
}


#' Plot biomass-NDVI relationship
#' 
#' @param model_output Stan model summary
#' @param biomass_preds Biomass predictions
#' @return ggplot object

plot_biomass_ndvi_relationship <- function(model_output, biomass_preds) {
  
  library(ggplot2)
  library(dplyr)
  
  # Extract parameters
  rel <- extract_biomass_relationship(model_output)
  beta_0 <- rel$parameters %>% filter(variable == "beta_0") %>% pull(median)
  beta_1 <- rel$parameters %>% filter(variable == "beta_1") %>% pull(median)
  beta_2 <- rel$parameters %>% filter(variable == "beta_2") %>% pull(median)
  
  # Create prediction curve
  ndvi_seq <- seq(-0.5, 1, length.out = 100)
  curve_data <- tibble(
    ndvi = ndvi_seq,
    biomass = beta_0 + beta_1 * ndvi + beta_2 * ndvi^2
  )
  
  # Plot
  obs_data <- biomass_preds %>%
    filter(biomass_available == 1)
  
  p <- ggplot() +
    # Observed data
    geom_point(data = obs_data, 
               aes(x = obs_ndvi, y = obs_biomass),
               alpha = 0.5, size = 2) +
    # Predicted curve
    geom_line(data = curve_data,
              aes(x = ndvi, y = biomass),
              color = "blue", size = 1) +
    # 1:1 line for predictions vs observations
    geom_point(data = obs_data,
               aes(x = obs_ndvi, y = median),
               color = "red", alpha = 0.3) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", alpha = 0.5) +
    labs(
      title = "Biomass-NDVI Relationship",
      subtitle = rel$interpretation$relationship,
      x = "NDVI",
      y = "Biomass (g/m² or units in data)",
      caption = "Black = observed, Red = predicted, Blue line = fitted curve"
    ) +
    theme_minimal()
  
  return(p)
}


#' Convert NDVI to biomass using fitted relationship
#' 
#' @param ndvi Vector of NDVI values
#' @param model_output Stan model summary with beta parameters
#' @param uncertainty Whether to return uncertainty intervals
#' @return Vector of biomass estimates (or tibble if uncertainty=TRUE)

ndvi_to_biomass <- function(ndvi, model_output, uncertainty = FALSE) {
  
  library(dplyr)
  
  # Extract parameters
  beta_0 <- model_output %>% 
    filter(variable == "beta_0") %>% 
    pull(median)
  beta_1 <- model_output %>% 
    filter(variable == "beta_1") %>% 
    pull(median)
  beta_2 <- model_output %>% 
    filter(variable == "beta_2") %>% 
    pull(median)
  
  # Point estimate
  biomass_est <- beta_0 + beta_1 * ndvi + beta_2 * ndvi^2
  
  if(!uncertainty) {
    return(biomass_est)
  }
  
  # With uncertainty
  beta_0_sd <- model_output %>% filter(variable == "beta_0") %>% pull(sd)
  beta_1_sd <- model_output %>% filter(variable == "beta_1") %>% pull(sd)
  beta_2_sd <- model_output %>% filter(variable == "beta_2") %>% pull(sd)
  tau_biomass <- model_output %>% filter(variable == "tau_biomass") %>% pull(median)
  
  # Simple uncertainty (ignoring covariance between betas)
  biomass_sd <- sqrt(
    beta_0_sd^2 +
    (ndvi * beta_1_sd)^2 +
    (ndvi^2 * beta_2_sd)^2 +
    tau_biomass^2
  )
  
  return(tibble(
    ndvi = ndvi,
    biomass_median = biomass_est,
    biomass_sd = biomass_sd,
    biomass_lower = biomass_est - 1.96 * biomass_sd,
    biomass_upper = biomass_est + 1.96 * biomass_sd
  ))
}
