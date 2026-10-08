#' Tidy static covariates from the new emma_envdata contract.
#'
#' Expects `stable_data.parquet` produced by [make_stable_data_parquet()],
#' with spatial key `cellID` (== envdata `pid`), planar `x`/`y` in EPSG:9221,
#' and remnant distance in **metres**.
#'
#' @param envdata_files Root envdata directory.
#' @param region Named bbox in EPSG:4326 (`xmin`, `xmax`, `ymin`, `ymax`).
#' @param remnant_distance Minimum distance to remnant edge in **metres**
#'   (legacy pipelines used kilometres; 2 km → 2000).
#' @param sample_proportion Fraction of model-domain pixels kept for training.
#' @param long_pixels Tibble of `cellID` values from [find_long_records()].
tidy_static_data <- function(envdata_files,
                             region,
                             remnant_distance,
                             sample_proportion,
                             long_pixels) {
  stable_path <- file.path(envdata_files, "static", "stable_data.parquet")
  if (!file.exists(stable_path)) {
    # Backward-friendly fallback if prepare step wrote a different name.
    alt <- file.path(envdata_files, "static", "static_covariates.parquet")
    stable_path <- if (file.exists(alt)) alt else stable_path
  }

  data <- arrow::open_dataset(sources = stable_path)

  # Region filter: WGS84 bbox → EPSG:9221 (Hartebeesthoek94 / ZAF BSU Albers).
  region_bbox <- sf::st_bbox(region, crs = sf::st_crs(4326)) |>
    sf::st_as_sfc() |>
    sf::st_transform(crs = 9221) |>
    sf::st_bbox()

  td <- data |>
    dplyr::collect() |>
    tibble::as_tibble()

  if (!"cellID" %in% names(td) && "pid" %in% names(td)) {
    td$cellID <- as.integer(td$pid)
  }

  # Unify remnant-distance column name (new: remnants_distance, metres).
  if (!"remnants_distance" %in% names(td) &&
      "remnant_distance.tif" %in% names(td)) {
    td$remnants_distance <- td[["remnant_distance.tif"]]
  }

  td <- td |>
    dplyr::left_join(dplyr::bind_cols(long_pixels, long = 1L), by = "cellID") |>
    dplyr::mutate(
      fynbos = dplyr::case_when(
        remnants_distance > 0 ~ TRUE,
        TRUE ~ FALSE
      ),
      model_domain = dplyr::case_when(
        remnants_distance >= remnant_distance &
          long == 1 &
          x > region_bbox$xmin & x < region_bbox$xmax &
          y > region_bbox$ymin & y < region_bbox$ymax ~ TRUE,
        TRUE ~ FALSE
      )
    ) |>
    dplyr::group_by(model_domain) |>
    dplyr::mutate(
      training = sample(
        c(TRUE, FALSE),
        size = dplyr::n(),
        replace = TRUE,
        prob = c(sample_proportion, 1 - sample_proportion)
      ),
      sample = ifelse(model_domain, training, FALSE)
    ) |>
    dplyr::ungroup()

  # Scale numeric env covariates; keep IDs / flags / coordinates untouched.
  keep_unscaled <- intersect(
    c("x", "y", "cellID", "pid", "long", "fynbos", "model_domain",
      "training", "sample", "remnants", "remnants_distance",
      "vegbiome", "vegbioregion", "vegtype"),
    names(td)
  )
  numeric_cols <- names(td)[vapply(td, is.numeric, logical(1))]
  scale_cols <- setdiff(numeric_cols, keep_unscaled)
  other_cols <- setdiff(names(td), scale_cols)

  hmm1 <- td[other_cols]
  hmm2 <- if (length(scale_cols)) {
    as.data.frame(scale(td[scale_cols]))
  } else {
    td[scale_cols]
  }
  cbind(hmm1, hmm2)
}
