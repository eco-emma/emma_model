#' Prepare a model-ready static parquet from the new emma_envdata product.
#'
#' Reads `static/static_covariates.parquet` (GeoParquet, key = `pid`), ensures
#' planar `x`/`y` coordinates (EPSG:9221), and writes `stable_data.parquet`
#' with a `cellID` alias equal to envdata `pid` so existing Stan plumbing keeps
#' working.
#'
#' @param envdata_files Root envdata directory (from `download_emma_envdata()`).
#' @param filename Output basename written under `envdata_files/static/`.
#' @return Path to the written parquet file.
make_stable_data_parquet <- function(envdata_files,
                                     filename = "stable_data.parquet") {
  src <- file.path(envdata_files, "static", "static_covariates.parquet")
  if (!file.exists(src)) {
    stop("Expected static covariates at: ", src)
  }

  data <- NULL
  if (requireNamespace("sfarrow", quietly = TRUE)) {
    data <- tryCatch(sfarrow::st_read_parquet(src), error = function(e) NULL)
  }
  if (is.null(data) && requireNamespace("sf", quietly = TRUE)) {
    data <- tryCatch(sf::st_read(src, quiet = TRUE), error = function(e) NULL)
  }
  if (is.null(data)) {
    data <- arrow::read_parquet(src)
  }

  required <- c("pid", "remnants", "remnants_distance")
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop("static_covariates.parquet missing columns: ",
         paste(missing, collapse = ", "))
  }

  if (inherits(data, "sf")) {
    xy <- sf::st_coordinates(data)
    data <- sf::st_drop_geometry(data)
    data$x <- xy[, "X"]
    data$y <- xy[, "Y"]
  } else if (!all(c("x", "y") %in% names(data))) {
    # Derive coordinates from domain.tif (band 1 = pid).
    domain_tif <- file.path(envdata_files, "static", "domain.tif")
    if (!file.exists(domain_tif)) {
      stop("Need geometry, x/y columns, or static/domain.tif to build coordinates")
    }
    domain_df <- terra::as.data.frame(terra::rast(domain_tif)[[1]],
                                      xy = TRUE, na.rm = TRUE)
    names(domain_df) <- c("x", "y", "pid")
    domain_df$pid <- as.integer(domain_df$pid)
    data$geometry <- NULL
    data <- dplyr::left_join(
      tibble::as_tibble(data),
      domain_df,
      by = "pid"
    )
  }

  if ("geometry" %in% names(data)) {
    data$geometry <- NULL
  }

  # Model pipeline historically used cellID as the spatial pixel key.
  # New envdata uses pid; keep both (identical) for a soft migration.
  data$cellID <- as.integer(data$pid)

  if ("domain" %in% names(data)) {
    data <- dplyr::filter(data, is.na(.data$domain) | .data$domain == 1)
  }

  out <- file.path(envdata_files, "static", filename)
  arrow::write_parquet(
    tibble::as_tibble(data),
    sink = out,
    compression = "zstd"
  )

  message("Wrote model-ready static parquet: ", out)
  normalizePath(out, mustWork = TRUE)
}
