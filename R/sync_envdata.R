#' Sync emma_envdata release products into a local directory.
#'
#' Downloads the new multi-tag envdata contract (`static_data`,
#' `vi_modis_parquet`, `fireage`) rather than the legacy `current` tag.
sync_envdata <- function(repo = "eco-emma/emma_envdata",
                         path = "data/envdata/") {
  download_emma_envdata(
    repo = repo,
    dest = path,
    overwrite = FALSE
  )
}
