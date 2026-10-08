#' Tidy dynamic VI + fire-age observations for the model.
#'
#' New emma_envdata contract:
#' - VI parquet: `vi_modis_YYYYMMDD.parquet` with `pid, date, sensor, value`
#'   where `value` is **EVI × 100** (decode with `value / 100`).
#' - Fire age: `fireage_modis_*.parquet` joined on `(pid, date, sensor)`.
#'
#' Output keeps historical column names expected by [create_stan_data()]:
#' `cellID`, `date`, `ndvi` (here: EVI in native [-1, 1]-ish units), `age`,
#' `firemonth`.
#'
#' @param data Static tidy table with a `sample` flag and `cellID`.
#' @param date_window Length-2 Date vector (start, stop).
#' @param envdata_files Root envdata directory (default `data/envdata`).
tidy_dynamic_data <- function(data,
                              date_window,
                              envdata_files = "data/envdata") {
  vi_files <- list.files(
    file.path(envdata_files, "vi_modis"),
    pattern = "^vi_modis_.*\\.parquet$",
    full.names = TRUE
  )
  fire_files <- list.files(
    file.path(envdata_files, "fireage"),
    pattern = "^fireage_modis_.*\\.parquet$",
    full.names = TRUE
  )

  if (!length(vi_files)) {
    stop("No VI parquet files under ", file.path(envdata_files, "vi_modis"))
  }
  if (!length(fire_files)) {
    stop("No fireage_modis parquet files under ",
         file.path(envdata_files, "fireage"))
  }

  cells_to_keep <- data |>
    dplyr::filter(.data$sample) |>
    dplyr::select(cellID) |>
    dplyr::mutate(pid = as.integer(.data$cellID))

  start_date <- as.numeric(lubridate::as_date(date_window[1]))
  stop_date <- as.numeric(lubridate::as_date(date_window[2]))

  vi_ds <- arrow::open_dataset(sources = vi_files)
  fire_ds <- arrow::open_dataset(sources = fire_files)

  dyndata <- vi_ds |>
    dplyr::semi_join(cells_to_keep, by = "pid") |>
    dplyr::filter(date > start_date, date < stop_date) |>
    dplyr::left_join(
      fire_ds,
      by = c("pid", "date", "sensor")
    ) |>
    dplyr::collect() |>
    dplyr::mutate(
      cellID = as.integer(.data$pid),
      # EVI packed as integer × 100 (not the legacy NDVI (v/100)-1 encoding).
      ndvi = .data$value / 100,
      age = .data$fire_age_days / 365.25,
      firemonth = dplyr::if_else(
        is.na(.data$last_burn_date) | .data$last_burn_date == 0,
        NA_integer_,
        as.integer(lubridate::month(lubridate::as_date(.data$last_burn_date)))
      ),
      date = lubridate::as_date(.data$date)
    ) |>
    dplyr::filter(!is.na(.data$ndvi), !is.na(.data$age)) |>
    dplyr::select(
      cellID, pid, date, sensor, ndvi, age, firemonth,
      last_burn_date, fire_age_days, fire_count, fire_source
    ) |>
    tibble::as_tibble()

  dyndata
}
