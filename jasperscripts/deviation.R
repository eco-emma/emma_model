### Figures for Jasper's MEDECOS 2022 talk

library(targets)
library(tidyverse)
library(doParallel)
library(raster)
library(lubridate)
library(sf)
# library(plotly)
library(leaflet)
library(ggridges)
library(viridis)
# library(hrbrthemes)

### Read in targets data
tar_load(c(
  envdata,
  envvars,
  # stan_data,
  data_training,
  dyndata_testing,
  dyndata_training,
  model_results,
  spatial_outputs,
  model_prediction
))

### Demo recovery curve
model_prediction %>%
  filter(cellID == 2934870) %>%
  ggplot(aes(x = date)) +
  geom_ribbon(aes(ymin = q5, ymax = q95), alpha = 0.5) +
  geom_line(aes(y = y_obs), colour = "darkred", lwd = 0.5) +
  geom_line(aes(y = median), colour = "blue") +
  # facet_wrap(~cellID) +
  labs(x = "time since fire (years)", y = "NDVI") +
  theme_bw()

### Make predictions for 2015-2022

# Make vectors of estimated recovery parameters

mr_cid <- model_results[-c(1, 2), ] %>%
  mutate(pid = as.numeric(pid)) %>%
  left_join(dplyr::select(data_training, cellID, pid))

phi <- mr_cid %>% filter(type == "other" & parameter == "phi")

parests <- mr_cid %>%
  filter(type %in% c("other", "spatial") & parameter %in% c("A", "alpha", "gamma", "lambda")) %>%
  dplyr::select(parameter, median, cellID) %>%
  pivot_wider(names_from = parameter, values_from = median)

test_pred <- dyndata_testing %>%
  drop_na() %>%
  left_join(parests) %>%
  mutate(phi = phi$median) %>%
  mutate(ndvi_pred = alpha + gamma - gamma * exp(-(age / lambda))
    + sin((phi + (firemonth - 1) * pi / 6) + 2 * pi * age) * A) %>%
  mutate(Year = year(date), Difference = ndvi - ndvi_pred)


### Plot predictions
cells_with_long_records <-
  test_pred %>%
  group_by(cellID) %>%
  summarize(n = n()) %>%
  arrange(desc(n)) %>%
  slice(1:20) # top 20 cells with the most observations

test_pred %>%
  filter(cellID %in% cells_with_long_records$cellID) %>%
  ggplot(aes(x = date)) +
  # geom_ribbon(aes(ymin=q5,ymax=q95),alpha=0.5)+
  geom_line(aes(y = ndvi), colour = "darkred", lwd = 0.5) +
  geom_line(aes(y = ndvi_pred), colour = "blue") +
  facet_wrap(~cellID) +
  labs(x = "time since fire (years)", y = "NDVI") +
  theme_bw()


### Maps of spatial parameters
# rast=projectRaster(spatial_outputs,crs = "+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs +type=crs")

# leaflet() %>% setView(lng = 18.577, lat = -33.998707, zoom = 10) %>%
#   addProviderTiles(providers$Esri.WorldImagery) %>%
#   addRasterImage(rast[[1]],group=names(rast)[1]) %>% #, color = ~pal(values(rast)[,1])
#   addRasterImage(rast[[2]],group=names(rast)[2]) %>%
#   addRasterImage(rast[[3]],group=names(rast)[3]) %>%
#   addRasterImage(rast[[4]],group=names(rast)[4]) %>%
#   addLayersControl(
#     baseGroups = names(rast),
#     options = layersControlOptions(collapsed = FALSE))


### Map exceedances by veg type

## Get veg types, trim extra columns and remove self-intersections
fynbos <- st_read("data/fynbos.gpkg") %>%
  dplyr::select(Name_18, BIOREGION_) %>%
  st_make_valid()

## Plot labelled bioregions
fynbos %>%
  filter(str_detect(BIOREGION_, "Fynbos")) %>%
  mutate(Bioregion = fct_drop(BIOREGION_)) %>%
  group_by(Bioregion) %>%
  summarize() %>%
  mutate(Bioregion = as.character(Bioregion)) %>%
  ggplot() +
  geom_sf(aes(fill = Bioregion, color = Bioregion)) + # + #, colour = as.numeric(as.factor(Name_18)))) +
  scale_fill_viridis(discrete = T) +
  scale_color_viridis(discrete = T)

## Get sites
sites <- model_prediction %>%
  dplyr::select(cellID, x, y) %>%
  unique() %>%
  st_as_sf(coords = c("x", "y"), crs = crs(spatial_outputs)) %>%
  st_transform(crs = st_crs(fynbos)) %>%
  st_intersection(fynbos)

## Plot sampled pixels on veg types
ggplot() +
  geom_sf(data = fynbos, aes(fill = as.numeric(as.factor(Name_18)), colour = as.numeric(as.factor(Name_18)))) +
  scale_fill_viridis() +
  scale_color_viridis() +
  geom_sf(
    data = sites, size = 1, # alpha = .25,
    colour = "white", fill = "black", shape = 21
  ) +
  theme(legend.position = "none")

## Trim and combine predicted exceedences (2015-2021) with training period (2014-2021)
test_pred_exceed <- test_pred %>%
  dplyr::select(cellID, Year, Difference, age)

exceed <- model_prediction %>%
  mutate(Year = year(date), Difference = y_obs - median) %>%
  dplyr::select(cellID, Year, Difference, age) %>%
  bind_rows(test_pred_exceed) %>%
  left_join(sites)


## Ridgeline Plot

# Whole region
exceed %>%
  filter(Year %in% 2010:2021 & str_detect(BIOREGION_, "Fynbos")) %>%
  ggplot(aes(x = `Difference`, y = "", fill = ..x..)) +
  geom_density_ridges_gradient(scale = 1, rel_min_height = 0.01) +
  scale_fill_viridis(name = "Temp. [F]", option = "C") +
  labs(title = "Observed - Expected NDVI by Bioregion") +
  #    theme_ipsum() +
  theme(
    legend.position = "none",
    #  panel.spacing = unit(0.1, "lines"),
    strip.text.x = element_text(size = 8)
  ) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  xlim(c(-0.2, 0.2)) +
  ylab("Fynbos Biome") +
  xlab("Difference in NDVI") +
  facet_grid(~Year)

# 2010 to 2014
exceed %>%
  filter(Year %in% 2010:2014 & str_detect(BIOREGION_, "Fynbos")) %>%
  ggplot(aes(x = `Difference`, y = `BIOREGION_`, fill = ..x..)) +
  geom_density_ridges_gradient(scale = 2, rel_min_height = 0.01) +
  scale_fill_viridis(name = "Temp. [F]", option = "C") +
  labs(title = "Observed - Expected NDVI by Bioregion") +
  #    theme_ipsum() +
  theme(
    legend.position = "none",
    #  panel.spacing = unit(0.1, "lines"),
    strip.text.x = element_text(size = 8)
  ) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  xlim(c(-0.2, 0.2)) +
  ylab("Bioregion") +
  xlab("Difference in NDVI") +
  facet_grid(~Year)

# 2010 to 2021
exceed %>%
  filter(Year %in% 2010:2021 & str_detect(BIOREGION_, "Fynbos")) %>%
  ggplot(aes(x = `Difference`, y = `BIOREGION_`, fill = ..x..)) +
  geom_density_ridges_gradient(scale = 2, rel_min_height = 0.01) +
  scale_fill_viridis(name = "Temp. [F]", option = "C") +
  labs(title = "Observed - Expected NDVI by Bioregion") +
  #    theme_ipsum() +
  theme(
    legend.position = "none",
    #  panel.spacing = unit(0.1, "lines"),
    strip.text.x = element_text(size = 8)
  ) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  xlim(c(-0.2, 0.2)) +
  ylab("Bioregion") +
  xlab("Difference in NDVI") +
  facet_grid(~Year)


# Anomalies by age
exceed %>%
  filter(Year > 2010 & str_detect(BIOREGION_, "Fynbos")) %>%
  ggplot(aes(x = age, y = Difference)) +
  geom_hex(bins = 60) +
  scale_fill_viridis_c() +
  labs(x = "Vegetation age", y = "Observed - Expected NDVI") +
  theme_bw() +
  facet_wrap(~BIOREGION_) #+
# coord_equal()


# Maps by year by bioregion
bioregiondiff <- exceed %>%
  # select(!geometry) %>%
  filter(Year %in% 2010:2021 & str_detect(BIOREGION_, "Fynbos")) %>%
  group_by(BIOREGION_, Year) %>%
  #  mean(Difference, na.rm = T)
  summarise(Mean_difference = mean(Difference, na.rm = T))

fynbos %>%
  left_join(bioregiondiff) %>%
  drop_na() %>%
  ggplot() +
  geom_sf(aes(fill = Mean_difference, colour = Mean_difference)) +
  facet_wrap(~Year) +
  scale_fill_viridis(option = "A") +
  scale_color_viridis(option = "A")

# Maps by year by veg type
vegtypediff <- exceed %>%
  # select(!geometry) %>%
  filter(Year %in% 2010:2021 & str_detect(Name_18, "Fynbos")) %>%
  group_by(Name_18, Year) %>%
  #  mean(Difference, na.rm = T)
  summarise(Mean_difference = mean(Difference, na.rm = T))

fynbos %>%
  left_join(vegtypediff) %>%
  drop_na() %>%
  ggplot() +
  geom_sf(aes(fill = Mean_difference, colour = Mean_difference)) +
  facet_wrap(~Year) +
  scale_fill_viridis(option = "A") +
  scale_color_viridis(option = "A")
