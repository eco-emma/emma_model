# prep data for stan
create_stan_data <- function(data, dyndata, fit = 1, predict = 0) {
  # table to link cellID to pid
  pid_lookup <- data %>%
    dplyr::select(cellID, pid)

  # subset dynamic data to just these cells
  dyndata2 <- dyndata %>%
    left_join(pid_lookup) %>%
    filter(!is.na(pid), !is.na(ndvi), !is.na(age)) %>%
    arrange(pid, date)

  # keep only x data for matrix multiplication in model
  xvar <- dplyr::select(data, -cellID, -pid)

  # assemble the list for stan
  stan_data <- list(
    N = nrow(dyndata2),
    J = nrow(data),
    y_obs = dyndata2$ndvi, # select variable to model
    age = dyndata2$age,
    pid = dyndata2$pid,
    firemonth = ifelse(is.na(dyndata2$firemonth), 4, dyndata2$firemonth),
    #    month=decimal_date(dyndata2$date)-as.integer(decimal_date(dyndata2$date)),
    x = xvar,
    x_pid = data$pid,
    P = ncol(xvar),
    fit = fit,
    predict = predict,
    # keeping the following for easier matching later - not needed for model
    y_date = as.numeric(dyndata2$date),
    y_cellID = dyndata2$cellID,
    x_cellID = data$cellID
  )
}
