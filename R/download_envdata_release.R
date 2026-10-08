#' Download assets from one GitHub release tag into a local directory.
#'
#' Uses the GitHub Releases API with pagination so tags with >30 assets work.
#' Skips files that already exist locally. Checksum sidecars (`*_SHA256SUMS.txt`)
#' are skipped by default.
#'
#' @param repo "owner/repo" string.
#' @param tag Release tag.
#' @param dest Local directory for assets.
#' @param pattern Optional regex; only matching asset names are downloaded.
#' @param overwrite Overwrite existing local files.
#' @param token GitHub token (defaults to GITHUB_TOKEN / GH_TOKEN).
#' @param sleep_time Pause between downloads to reduce rate-limit pressure.
#' @return Character vector of local file paths (existing + newly downloaded).
download_release_tag <- function(repo,
                                 tag,
                                 dest,
                                 pattern = NULL,
                                 overwrite = FALSE,
                                 token = NULL,
                                 sleep_time = 0.25) {
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)

  if (is.null(token) || !nzchar(token)) {
    token <- Sys.getenv("GITHUB_TOKEN", unset = Sys.getenv("GH_TOKEN", unset = ""))
  }

  owner_repo <- strsplit(repo, "/", fixed = TRUE)[[1]]
  if (length(owner_repo) != 2) {
    stop("repo must be 'owner/repo', got: ", repo)
  }

  gh_args <- list(
    endpoint = "GET /repos/{owner}/{repo}/releases/tags/{tag}",
    owner = owner_repo[1],
    repo = owner_repo[2],
    tag = tag
  )
  if (nzchar(token)) gh_args[[".token"]] <- token

  rel <- tryCatch(
    do.call(gh::gh, gh_args),
    error = function(e) {
      stop("Failed to fetch release tag '", tag, "' from ", repo, ": ",
           conditionMessage(e), call. = FALSE)
    }
  )

  asset_args <- list(
    endpoint = "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
    owner = owner_repo[1],
    repo = owner_repo[2],
    release_id = rel$id,
    .limit = Inf
  )
  if (nzchar(token)) asset_args[[".token"]] <- token

  assets <- do.call(gh::gh, asset_args)
  if (length(assets) == 0) {
    warning("Release tag '", tag, "' has no assets.")
    return(character(0))
  }

  names <- vapply(assets, `[[`, character(1), "name")
  urls <- vapply(assets, `[[`, character(1), "url")
  keep <- !grepl("_SHA256SUMS\\.txt$", names)
  if (!is.null(pattern)) {
    keep <- keep & grepl(pattern, names)
  }
  names <- names[keep]
  urls <- urls[keep]

  local_paths <- character(length(names))
  for (i in seq_along(names)) {
    dest_path <- file.path(dest, names[[i]])
    local_paths[[i]] <- dest_path
    if (file.exists(dest_path) && !overwrite) next

    headers <- c(Accept = "application/octet-stream")
    if (nzchar(token)) {
      headers <- c(headers, Authorization = paste("token", token))
    }

    resp <- httr::RETRY(
      "GET",
      urls[[i]],
      httr::add_headers(.headers = headers),
      httr::write_disk(dest_path, overwrite = TRUE),
      times = 5,
      terminate_on = c(401, 404),
      pause_base = 10,
      pause_cap = 120
    )
    if (httr::http_error(resp)) {
      warning("Failed to download ", names[[i]], " from tag ", tag,
              " (HTTP ", httr::status_code(resp), ")")
      if (file.exists(dest_path)) file.remove(dest_path)
      local_paths[[i]] <- NA_character_
    }
    if (sleep_time > 0) Sys.sleep(sleep_time)
  }

  local_paths[!is.na(local_paths) & file.exists(local_paths)]
}


#' Download the emma_envdata products needed by emma_model.
#'
#' New envdata contract (multi-tag releases):
#' - `static_data`: `static_covariates.parquet`, `domain.tif`
#' - `vi_modis_parquet`: `vi_modis_YYYYMMDD.parquet` (EVI × 100)
#' - `fireage`: `fireage_modis_*.parquet` (+ optional VIIRS / snapshot)
#'
#' Local layout under `dest`:
#' ```
#' dest/static/...
#' dest/vi_modis/...
#' dest/fireage/...
#' ```
#'
#' @param repo emma_envdata GitHub repo.
#' @param dest Root download directory.
#' @param include_viirs_fireage Also download `fireage_viirs_*.parquet`.
#' @param overwrite Overwrite existing files.
#' @return Path to `dest` (directory tracked by the `envdata_files` target).
download_emma_envdata <- function(repo = "eco-emma/emma_envdata",
                                  dest = "data/envdata",
                                  include_viirs_fireage = FALSE,
                                  overwrite = FALSE) {
  static_dir <- file.path(dest, "static")
  vi_dir <- file.path(dest, "vi_modis")
  fire_dir <- file.path(dest, "fireage")

  message("Downloading static_data release assets...")
  download_release_tag(
    repo = repo,
    tag = "static_data",
    dest = static_dir,
    pattern = "^(static_covariates\\.parquet|domain\\.(tif|parquet))$",
    overwrite = overwrite
  )

  message("Downloading vi_modis_parquet release assets...")
  download_release_tag(
    repo = repo,
    tag = "vi_modis_parquet",
    dest = vi_dir,
    pattern = "^vi_modis_.*\\.parquet$",
    overwrite = overwrite
  )

  fire_pattern <- if (include_viirs_fireage) {
    "^(fireage_(modis|viirs)_.*\\.parquet|fireage_current\\.tif)$"
  } else {
    "^(fireage_modis_.*\\.parquet|fireage_current\\.tif)$"
  }

  message("Downloading fireage release assets...")
  download_release_tag(
    repo = repo,
    tag = "fireage",
    dest = fire_dir,
    pattern = fire_pattern,
    overwrite = overwrite
  )

  required <- c(
    file.path(static_dir, "static_covariates.parquet"),
    file.path(static_dir, "domain.tif")
  )
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("Missing required envdata assets after download:\n  ",
         paste(missing, collapse = "\n  "))
  }

  if (!length(list.files(vi_dir, pattern = "^vi_modis_.*\\.parquet$"))) {
    stop("No VI parquet files found in ", vi_dir)
  }
  if (!length(list.files(fire_dir, pattern = "^fireage_modis_.*\\.parquet$"))) {
    stop("No fireage_modis parquet files found in ", fire_dir)
  }

  normalizePath(dest, mustWork = TRUE)
}
