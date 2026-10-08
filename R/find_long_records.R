#' Find pixels with long fire-recovery records under the new envdata schema.
#'
#' Uses `fireage_modis_*.parquet` (`fire_age_days`, `fire_count`) and
#' `vi_modis_*.parquet` (`value` = EVI × 100) instead of the legacy
#' `dynamic_parquet-time_since_fire` / `dynamic_parquet-ndvi` long tables.
#'
#' @param env_files Root envdata directory.
#' @param max_years_to_first_fire Cells without a fire in this many years from
#'   the start of the record are excluded. `NULL` disables the filter.
#' @param min_years_without_fire Require observed fire ages at least this many
#'   years. `NULL` disables the filter.
#' @param ndvi_prob Keep cells with at least this fraction of the max VI count.
#' @return Tibble with column `cellID` (envdata `pid`).
find_long_records <- function(env_files,
                              max_years_to_first_fire = 2,
                              min_years_without_fire = 10,
                              ndvi_prob = 0.8) {
  age_files <- list.files(
    file.path(env_files, "fireage"),
    pattern = "^fireage_modis_.*\\.parquet$",
    full.names = TRUE
  )
  vi_files <- list.files(
    file.path(env_files, "vi_modis"),
    pattern = "^vi_modis_.*\\.parquet$",
    full.names = TRUE
  )

  if (!length(age_files)) {
    stop("No fireage_modis parquet files under ",
         file.path(env_files, "fireage"))
  }
  if (!length(vi_files)) {
    stop("No VI parquet files under ", file.path(env_files, "vi_modis"))
  }

  age_ds <- arrow::open_dataset(sources = age_files)
  vi_ds <- arrow::open_dataset(sources = vi_files)

  start_of_record <- age_ds |>
    dplyr::select(date) |>
    dplyr::distinct() |>
    dplyr::collect() |>
    dplyr::pull(date) |>
    min(na.rm = TRUE)

  # Observed burns only (fire_count > 0); censored never-burned rows excluded.
  if (is.null(max_years_to_first_fire)) {
    pixels_w_early_fire <- age_ds |>
      dplyr::filter(.data$fire_count > 0, .data$fire_age_days > 0) |>
      dplyr::distinct(pid) |>
      dplyr::collect() |>
      dplyr::pull(pid)
  } else {
    pixels_w_early_fire <- age_ds |>
      dplyr::filter(
        .data$fire_count > 0,
        .data$fire_age_days > 0,
        .data$date <= (max_years_to_first_fire * 365.25) + start_of_record,
        .data$fire_age_days < max_years_to_first_fire * 365.25
      ) |>
      dplyr::distinct(pid) |>
      dplyr::collect() |>
      dplyr::pull(pid)
  }

  if (is.null(min_years_without_fire)) {
    pixels_w_long_runs <- age_ds |>
      dplyr::filter(.data$fire_count > 0, .data$fire_age_days > 0) |>
      dplyr::distinct(pid) |>
      dplyr::collect() |>
      dplyr::pull(pid)
  } else {
    pixels_w_long_runs <- age_ds |>
      dplyr::filter(
        .data$fire_count > 0,
        .data$fire_age_days >= 365.25 * min_years_without_fire,
        .data$date >= start_of_record + (365.25 * min_years_without_fire)
      ) |>
      dplyr::distinct(pid) |>
      dplyr::collect() |>
      dplyr::pull(pid)
  }

  long_aged_pixels <- data.frame(
    cellID = as.integer(intersect(pixels_w_early_fire, pixels_w_long_runs))
  )

  if (!nrow(long_aged_pixels)) {
    return(tibble::tibble(cellID = integer()))
  }

  good_vi_pixels <- vi_ds |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::filter(pid %in% long_aged_pixels$cellID) |>
    dplyr::collect() |>
    tibble::as_tibble() |>
    dplyr::group_by(pid) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop") |>
    dplyr::rename(cellID = pid)

  max_number_vi <- max(good_vi_pixels$n, na.rm = TRUE)

  long_aged_pixels |>
    dplyr::left_join(good_vi_pixels, by = "cellID") |>
    dplyr::filter(.data$n > (max_number_vi * ndvi_prob)) |>
    dplyr::select(cellID) |>
    tibble::as_tibble()
}
