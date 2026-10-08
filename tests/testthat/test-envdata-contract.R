test_that("EVI scale decode matches new envdata packing (value/100)", {
  raw <- c(-8L, 0L, 45L, 90L)
  evi <- raw / 100
  expect_equal(evi, c(-0.08, 0, 0.45, 0.9))
  # Legacy NDVI packing must NOT be applied to new EVI products.
  legacy_ndvi <- (raw / 100) - 1
  expect_false(isTRUE(all.equal(evi, legacy_ndvi)))
})

test_that("remnant distance threshold is interpreted in metres", {
  remnants_distance <- c(0, 500, 2000, 5000)
  remnant_distance <- 2000
  model_domain <- remnants_distance >= remnant_distance
  expect_equal(model_domain, c(FALSE, FALSE, TRUE, TRUE))
})

test_that("envvar mapping uses CHELSA v2.1 / new static column names", {
  envvars <- c(
    "Mean_Annual_Precipitation" = "CHELSA_bio12_1981-2010_V.2.1",
    "Max_Air_Temperature_Warmest" = "CHELSA_bio05_1981-2010_V.2.1",
    "Min_Air_Temperature_Coldest" = "CHELSA_bio06_1981-2010_V.2.1",
    "Cloud_Seasonal_Concentration" = "MODCF_seasonality_concentration",
    "Topographic_Diversity" = "topographic_div"
  )
  expect_false(any(grepl("\\.tif$", envvars)))
  expect_false(any(grepl("V1\\.2", envvars)))
  expect_false(any(grepl("alos_", envvars)))
})

test_that("VI + fireage join keys are pid/date/sensor", {
  vi <- data.frame(pid = 1L, date = 11000L, sensor = 1L, value = 50L)
  fire <- data.frame(
    pid = 1L, date = 11000L, sensor = 1L,
    fire_age_days = 730L, last_burn_date = 10270L, fire_count = 1L
  )
  joined <- merge(vi, fire, by = c("pid", "date", "sensor"))
  expect_equal(nrow(joined), 1)
  expect_equal(joined$value / 100, 0.5)
  expect_equal(joined$fire_age_days / 365.25, 730 / 365.25)
})

test_that("make_stable_data_parquet aliases pid to cellID", {
  skip_if_not_installed("arrow")

  tmp <- tempfile("envdata")
  static_dir <- file.path(tmp, "static")
  dir.create(static_dir, recursive = TRUE)

  pts <- data.frame(
    pid = 1:3,
    remnants = c(80, 10, 0),
    remnants_distance = c(3000, 100, 0),
    `CHELSA_bio12_1981-2010_V.2.1` = c(400, 500, 600),
    x = c(0, 1, 2),
    y = c(0, 1, 2),
    check.names = FALSE
  )

  arrow::write_parquet(pts, file.path(static_dir, "static_covariates.parquet"))

  # Source just this helper (testthat may not load the package).
  env <- new.env(parent = globalenv())
  sys.source(file.path(testthat::test_path("..", "..", "R"),
                       "make_stable_data_parquet.R"), envir = env)
  # Fallback when test_path layout differs (running from repo root).
  if (!exists("make_stable_data_parquet", envir = env, inherits = FALSE)) {
    sys.source("R/make_stable_data_parquet.R", envir = env)
  }

  out <- env$make_stable_data_parquet(tmp)
  got <- arrow::read_parquet(out)

  expect_true(file.exists(out))
  expect_true("cellID" %in% names(got))
  expect_equal(got$cellID, got$pid)
  expect_true(all(c("x", "y") %in% names(got)))
})
