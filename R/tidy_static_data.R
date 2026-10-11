tidy_static_data <- function(envdata_files, region, remnant_distance, sample_proportion, long_pixels) {
  # Load static parquet file
  data <- open_dataset(sources = file.path(envdata_files, "stable_data.gz.parquet"))

  # define region and reproject to modis sinusoidal
  region_bbox <- st_bbox(region, crs = st_crs(4326)) %>%
    st_as_sfc() %>%
    st_transform(crs = "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs") %>%
    st_bbox()

  # filter by remnant, distance, region, and add training/testing label according to sample_proportion
  td <- data %>%
    collect() %>%
    as_tibble() %>%
    left_join(bind_cols(long_pixels, long = 1), by = "cellID") %>% # add column for pixels with long records
    mutate(
      fynbos = case_when( # all remnants
        remnant_distance.tif > 0 ~ TRUE,
        TRUE ~ FALSE
      ),
      model_domain = case_when( # core remnants within bbox domain
        remnant_distance.tif >= remnant_distance &
          long == 1 & # flag the long records
          x > region_bbox$xmin & x < region_bbox$xmax &
          y > region_bbox$ymin & y < region_bbox$ymax ~ TRUE,
        TRUE ~ FALSE
      )
    ) %>%
    group_by(model_domain) %>%
    mutate(training = sample(c(TRUE, FALSE), size = n(), replace = T, prob = c(sample_proportion, 1 - sample_proportion))) %>%
    mutate(sample = ifelse(model_domain, training, FALSE)) %>%
    compute() %>%
    ungroup()

  # Jasper's inelegant hack to scale the spatial env vars...
  hmm1 <- td %>% dplyr::select(!where(is.numeric) | c(x, y, cellID, long))
  hmm2 <- td %>%
    dplyr::select(where(is.numeric) & !c(x, y, cellID, long)) %>%
    scale()
  td <- cbind(hmm1, hmm2)

  if (F) {
    # map domain for debugging
    ggplot(td, aes(x = x, y = y, fill = sample)) +
      geom_tile() +
      coord_equal()
  }

  return(td)
}
# =======
#
# tidy_static_data <- function(envdata,region,remnant_distance,sample_proportion){
#
# # Load static parquet file
# data <- open_dataset(sources = file.path(envdata,"stable_data.gz.parquet"))
#
# # define region and reproject to modis sinusoidal
# region_bbox = st_bbox(region,crs = st_crs(4326)) %>%
#     st_as_sfc() %>%
#     st_transform(crs = "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs") %>%
#     st_bbox()
#
# # filter by remnant, distance, region, and add training/testing label according to sample_proportion
# td=data %>%
#   collect() %>%
#   mutate(
#     fynbos = case_when( #all remnants
#       remnant_distance.tif>0 ~ TRUE,
#       TRUE ~ FALSE),
#     model_domain = case_when( #core remnants within bbox domain
#       remnant_distance.tif>=remnant_distance &
#       x>region_bbox$xmin & x<region_bbox$xmax &
#       y>region_bbox$ymin & y<region_bbox$ymax ~ TRUE,
#       TRUE ~ FALSE)) %>%
#   group_by(model_domain) %>%
#   mutate(training = sample(c(TRUE,FALSE),size=n(), replace = T,prob = c(sample_proportion, 1-sample_proportion))) %>%
#   mutate(sample = ifelse(model_domain, training, FALSE)) %>%
#   compute() %>%
#   ungroup()
#
#
#
# if(F) {
#   # map domain for debugging
#   ggplot(td,aes(x=x,y=y,fill=sample))+geom_tile()+coord_equal()
# }
#
# return(td)
#
# }
# >>>>>>> origin/dev-brian
