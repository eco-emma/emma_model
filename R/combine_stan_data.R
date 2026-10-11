combine_stan_data <- function(stan_data, stan_data_predict) {
  names(stan_data_predict) <- paste(names(stan_data_predict), "_predict", sep = "")
  stan_data_combined <- c(stan_data, stan_data_predict)
  return(stan_data_combined)
}
