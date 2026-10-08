#' Spatial Predictions
#'
#' Maps model parameters onto the emma_envdata `domain.tif` grid (EPSG:9221).
#' Band 1 of `domain.tif` stores `pid` (== model `cellID`).
create_spatial_outputs <- function(envdata,
                                   envvars,
                                   model_results,
                                   data_training,
                                   envdata_files = "data/envdata") {
  td <- envdata |>
    dplyr::left_join(dplyr::select(data_training, cellID, pid))

  xmat <- as.matrix(td[, envvars])

  betas <- model_results |>
    dplyr::filter(type == "beta") |>
    dplyr::mutate(term = sub("_.*$", "", parameter)) |>
    dplyr::select(term, median, xname)

  td$gamma <- as.vector(xmat %*% dplyr::filter(betas, term == "gamma")$median)
  td$lambda <- as.vector(xmat %*% dplyr::filter(betas, term == "lambda")$median)
  td$A <- as.vector(xmat %*% dplyr::filter(betas, term == "A")$median)
  td$RT <- td$lambda * log(200 * td$gamma)

  template <- file.path(envdata_files, "static", "domain.tif")
  if (!file.exists(template)) {
    template_fallback <- "data/template.tif"
    if (!file.exists(template_fallback)) {
      utils::download.file(
        "https://github.com/eco-emma/emma_envdata/releases/download/static_data/domain.tif",
        destfile = template_fallback,
        mode = "wb"
      )
    }
    template <- template_fallback
  }

  # Band 1 = pid; use terra (multi-band COG) then hand values to raster stack
  # for compatibility with existing raster/foreach workflow.
  domain_terra <- terra::rast(template)
  pid_band <- domain_terra[[1]]
  domain <- raster::raster(pid_band)

  vmat <- dplyr::left_join(
    data.frame(cellID = as.integer(raster::values(domain))),
    dplyr::select(td, cellID, gamma, lambda, A, RT)
  ) |>
    dplyr::select(-cellID)

  rasters <- NULL
  for (i in seq_len(ncol(vmat))) {
    tdomain <- domain
    raster::values(tdomain) <- vmat[, i]
    names(tdomain) <- colnames(vmat)[i]
    rasters <- if (is.null(rasters)) tdomain else raster::stack(rasters, tdomain)
  }
  raster::crs(rasters) <- as.character(terra::crs(domain_terra))

  rasters
}
