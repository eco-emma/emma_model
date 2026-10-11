## Download the most recent release from the emma_envdata
tidy_dynamic_data <- function(data, date_window) {
  # Data pre-processing

  dynfiles <- open_dataset(sources = list.files("data/envdata", "dynamic", full = T))

  cells_to_keep <- data %>%
    dplyr::filter(sample) %>%
    dplyr::select(cellID)

  start_date <- as.numeric(as_date(date_window[1]))
  stop_date <- as.numeric(as_date(date_window[2]))

  dyndata <- dynfiles %>%
    semi_join(cells_to_keep, by = "cellID") %>% # keep only pixels in data
    filter(date > start_date & date < stop_date) %>%
    collect() %>%
    pivot_wider(names_from = variable, values_from = value, values_fn = first) %>% # not sure why ages are repeated twice in this
    mutate(
      firemonth = ifelse(most_recent_burn_date == 0, NA, # use median fire date
        month(as_date(most_recent_burn_date))
      ),
      date = as_date(date),
      ndvi = (ndvi / 100) - 1,
      age = time_since_fire / 365.23
    ) %>% # convert age from days to years
    as_tibble()

  return(dyndata)
}
