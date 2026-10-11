filter_training_data <- function(data, envvars) {
  data %>%
    filter(fynbos, model_domain, training) %>%
    ungroup() %>%
    dplyr::select(cellID, !!!envvars) %>% # select and rename
    na.omit() %>%
    arrange(cellID) %>%
    mutate(pid = as.numeric(as.factor(cellID))) # %>% #reset pid to 1:length(pid) to ease in indexing
}
