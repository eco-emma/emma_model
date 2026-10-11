#' Function to find pixels with some % of ndvi observations and a fire that occurs in the record by specifying needed age range
#' The default range c(2,10) will ensure that at least one fire happens within 2 years of the start of the record and it runs for at least 10 years.
#' @param age_range vector length 2 - include pixels with ages in this range
#' @param max_years_to_first_fire cells without fires occurring between the start of the record and this many years after will be excluded.  Set to NULL to ignore, Default is 2
#' @param min_years_without_fire the min number of years without fire that occur after the start of record. Set to NULL to ignore. Default is 10.
#' @param ndvi_prob The fraction of NDVI values that should be available for records that are kept.  Default is 0.8.  Set to 0 to ignore.

find_long_records <- function(env_files,
                              max_years_to_first_fire = 2,
                              min_years_without_fire = 10,
                              # age_range = c(2,10),
                              ndvi_prob = 0.8) {
  age_files <- open_dataset(sources = list.files(env_files, "dynamic_parquet-time_since_fire", full = T))
  ndvi_files <- open_dataset(sources = list.files(env_files, "dynamic_parquet-ndvi", full = T))

  # long_aged_pixels <-
  #   age_files  %>%
  #   filter(value!=0,value>age_range[1]*365,value>age_range[2]*365) %>%
  #   collect() %>%
  #   group_by(cellID) %>%
  #   summarize(n_age=sum(n())) %>%
  #   as_tibble()

  # Get the first date of the time series

  start_of_record <- age_files %>%
    dplyr::select(date) %>%
    unique() %>%
    collect() %>%
    pull(date) %>%
    min()


  # Figure out which cells match the time to first fire criterion

  if (is.null(max_years_to_first_fire)) {
    # If NULL, take everything

    pixels_w_early_fire <-
      age_files %>%
      filter(value > 0) %>% # exclude valueless cells and nonsensical ones
      collect() %>%
      pull(cellID) %>%
      unique()
  } else {
    pixels_w_early_fire <-
      age_files %>%
      filter(value > 0) %>% # exclude valueless cells and nonsensical ones
      filter(date <= (max_years_to_first_fire * 365.25) + start_of_record &
        value < max_years_to_first_fire * 365.35) %>% # only take pixels with fire within the first n years
      collect() %>%
      pull(cellID) %>%
      unique()
  }


  # Figure out which cells match the running time criterion

  if (is.null(min_years_without_fire)) {
    pixels_w_long_runs <-
      age_files %>%
      filter(value > 0) %>%
      collect() %>%
      pull(cellID) %>%
      unique()
  } else {
    pixels_w_long_runs <-
      age_files %>%
      filter(value > 0) %>%
      filter(value >= 365.25 * min_years_without_fire &
        date >= start_of_record + (365.25 * min_years_without_fire)) %>%
      collect() %>%
      pull(cellID) %>%
      unique()
  }


  # combine the criteria for first fire and length of record

  long_aged_pixels <- data.frame(cellID = intersect(
    pixels_w_early_fire,
    pixels_w_long_runs
  ))


  # add in the ndvi constraint
  good_ndvi_pixels <-
    ndvi_files %>%
    filter(!is.na(value)) %>%
    filter(cellID %in% long_aged_pixels$cellID) %>% # new line to save space
    collect() %>%
    as_tibble() %>%
    group_by(cellID) %>%
    summarize(n = sum(n()))

  max_number_ndvi <- max(good_ndvi_pixels$n)

  keep_pixels <- long_aged_pixels %>%
    left_join(good_ndvi_pixels, by = "cellID") %>%
    filter(n > (max_number_ndvi * ndvi_prob)) %>%
    dplyr::select(cellID)

  return(keep_pixels)
}
#' =======
#' #' Function to find pixels with some % of ndvi observations and a fire that occurs in the record by specifying needed age range
#' #' The default range c(2,10) will ensure that at least one fire happens within 2 years of the start of the record and it runs for at least 10 years.
#' #' @param age_range vector length 2 - include pixels with ages in this range
#'
#'
#' find_long_records<-function(env_files,age_range=c(2,10),ndvi_prob=0.8){
#'
#'   age_files <- open_dataset(sources = list.files("data/envdata","dynamic_parquet-time_since_fire",full=T))
#'   ndvi_files <- open_dataset(sources = list.files("data/envdata","dynamic_parquet-ndvi",full=T))
#'
#'   long_aged_pixels <-
#'     age_files  %>%
#'     filter(value!=0,value>age_range[1]*365,value>age_range[2]*365) %>%
#'     collect() %>%
#'     group_by(cellID) %>%
#'     summarize(n_age=sum(n())) %>%
#'     as_tibble()
#'
#'   good_ndvi_pixels <-
#'     ndvi_files  %>%
#'     filter(!is.na(value)) %>%
#'     collect() %>%
#'     as_tibble() %>%
#'     group_by(cellID) %>%
#'     summarize(n=sum(n()))
#'
#'   max_number_ndvi=max(good_ndvi_pixels$n)
#'
#'   keep_pixels <- long_aged_pixels %>%
#'     left_join(good_ndvi_pixels, by="cellID") %>%
#'     filter(n>(max_number_ndvi*ndvi_prob)) %>%
#'     dplyr::select(cellID)
#'
#'   return(keep_pixels)
#' }
#' >>>>>>> origin/dev-brian
