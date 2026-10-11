# Data simulation functions

# Define functions

make_landscape <- function(nrow = 10, ncol = 10, nvar = 3, model = RandomFields::RMgauss(scale = 200), ...) {
  x <- raster::raster(nrows = nrow, ncols = ncol, vals = 1)
  env <- stack(x, scale(simulate_data(x, n = nvar, model = model, ...)))
  names(env) <- c("intercept", paste0("env_", 1:nvar))
  return(env)
}


make_static_data <- function(env, # landscape output from make_landscape()
                             alpha_beta,
                             gamma_beta,
                             lambda_beta,
                             phi_beta,
                             A_beta) {
  envmatrix <- as.matrix(env)

  return(
    tibble(
      cellID = 1:nrow(envmatrix),
      x = coordinates(env)[, 1],
      y = coordinates(env)[, 2],
      alpha = as.vector(envmatrix %*% alpha_beta),
      gamma = as.vector(envmatrix %*% gamma_beta),
      lambda = as.vector(envmatrix %*% lambda_beta),
      A = as.vector(envmatrix %*% A_beta),
      phi = as.vector(envmatrix %*% phi_beta)
    )
  )
}

make_recovery_data <- function(static, # landscape output from make_landscape()
                               ntime = 100, # number of time steps
                               maxage = 30, # max age of pixels
                               nseasons = 10 # number of 'seasonal' cycles in maxage
) {
  dyn <- tibble(
    date = as.Date(30 * 1:ntime, origin = as.Date("2020-01-01")),
    age = seq(0, maxage, len = ntime),
    month = rep(seq(0, 1, len = ntime / nseasons), nseasons)
  )

  res <- expand_grid(static, dyn) %>%
    mutate(
      exp = alpha + gamma - gamma * exp(-(age / lambda)), # just the exponential part
      mu = exp + sin((phi + (2 * pi * month))) * A, # add seasonality
      error = rnorm(n(), 0, .1),
      obs = mu + error, # add some noise
      obs = ifelse(obs > 1, 1, obs),
      obs = ifelse(obs > -1, obs, -1)
    )

  return(res)
}

generate_stan_data <- function() {
  env <- make_landscape()

  # define the regression coefs
  params <- tibble(
    xname = names(env),
    alpha_beta = c(runif(1, 0.05, .2), rnorm(nlayers(env) - 1, 0, .2)),
    gamma_beta = c(runif(1, 0.2, .6), rnorm(nlayers(env) - 1, 0, .2)),
    lambda_beta = c(runif(1, 3, 10), rnorm(nlayers(env) - 1, 0, 1)),
    phi_beta = c(runif(1, -.5, .5), rnorm(nlayers(env) - 1, 0, 1)),
    A_beta = c(runif(1, 0, .5), rnorm(nlayers(env) - 1, 0, 0.5)),
  )

  # generate the dynamic data
  static <- make_static_data(
    env = env,
    alpha_beta = params$alpha_beta,
    gamma_beta = params$gamma_beta,
    lambda_beta = params$lambda_beta,
    phi_beta = params$phi_beta,
    A_beta = params$A_beta
  )

  # generate the dynamic data
  dynamic <- make_recovery_data(static)

  # make the data for stan
  stan_data <- list(
    N = nrow(dynamic),
    J = nrow(static),
    y_obs = dynamic$obs, # select variable to model
    age = dynamic$age,
    pid = dynamic$cellID,
    month = dynamic$month,
    x = as.matrix(env),
    x_pid = static$cellID,
    P = ncol(as.matrix(env)),
    fit = 1,
    predict = 1,
    # keeping the following for easier matching later - not needed for model
    y_cellID = dynamic$cellID,
    x_cellID = static$cellID,
    y_date = as.integer(dynamic$date)
  )

  return(list(params = params, static = static, dynamic - dynamic, stan_data = stan_data))
}
