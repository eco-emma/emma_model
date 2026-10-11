library("rnoaa")
library("tidyverse")
# library("lawn")
# library("leaflet")
library("lubridate")
library("sf")
library(readr)
library(viridis)

## Get veg types, trim extra columns and remove self-intersections
fynbos <- st_read("data/fynbos.gpkg") %>%
  dplyr::select(Name_18, BIOREGION_) %>%
  st_make_valid()

### Search for stations (can try map instead and search by name)
station_data <- read_csv("jasperscripts/station_data.csv") # Takes a while to run
# station_data <- ghcnd_stations() # Takes a while to run
# head(station_data)
#
# lat_lon_df <- data.frame(id = "somewhere",
#                          latitude = -34.35,
#                          longitude = 18.48)
# nearby_stations <-  meteo_nearby_stations(lat_lon_df = lat_lon_df,
#                                           station_data = station_data, radius = 100)
#
# nearby_stations$somewhere

## Intersect stations with veg types
ext <- c(16, -35, 29, -20)
names(ext) <- c("xmin", "ymin", "xmax", "ymax")

stations <- station_data %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) %>%
  st_crop(ext) %>%
  st_transform(crs = st_crs(fynbos)) %>%
  st_intersection(fynbos) %>%
  filter(last_year > 2020)


### Select stations by name and filter
stations <- c(
  "CAPE TOWN INTL",
  "ROBERTSON",
  "GEORGE AIRPORT",
  "MALMESBURY",
  "PORT ELIZABETH INTL"
)

stas <- station_data %>%
  filter(element == "PRCP") %>%
  filter(name %in% stations)

stas <- stas[-6, ]

dat <- meteo_pull_monitors(stas$id, var = c("TMAX", "TMIN", "PRCP"), date_min = "1980-01-01", date_max = "2021-12-31")

stas$shortname <- c("ROB", "GEO", "MAL", "CPT", "PE")
dat <- left_join(dat, stas[, c("id", "name", "shortname")])
dat$year <- substr(dat$date, 1, 4)

mdat <- dat %>%
  group_by(shortname, year) %>%
  summarise(rain = sum(prcp, na.rm = T) / 10) # Get annual totals

mdat$year <- as.numeric(mdat$year)
mdat$rain <- as.numeric(mdat$rain)

ymean <- mdat %>%
  group_by(shortname) %>%
  summarise(mean = mean(rain, na.rm = T))
mdat <- left_join(mdat, ymean, by = "shortname")
mdat$positive <- mdat$rain - mdat$mean
mdat$positive[which(mdat$positive < 0)] <- 0
mdat$negative <- mdat$rain - mdat$mean
mdat$negative[which(mdat$negative > 0)] <- 0

# 7994b5

### Plot
ggplot(mdat, aes(x = year)) +
  geom_ribbon(aes(ymin = 0, ymax = positive, fill = "positive")) +
  geom_ribbon(aes(ymin = negative, ymax = 0, fill = "negative")) +
  scale_fill_manual(name = "", values = c("#D6604D", "#7994b5")) +
  facet_grid(shortname ~ ., scales = "free_y") +
  ylab("rainfall anomaly in mm")

## Plot labelled bioregions

stas <- stas %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(crs = st_crs(fynbos))

hmm <- fynbos %>%
  filter(str_detect(BIOREGION_, "Fynbos")) %>%
  mutate(Bioregion = fct_drop(BIOREGION_)) %>%
  group_by(Bioregion) %>%
  summarize() %>%
  mutate(Bioregion = as.character(Bioregion))

ggplot() +
  geom_sf(data = hmm, aes(fill = Bioregion, color = Bioregion)) + # + #, colour = as.numeric(as.factor(Name_18)))) +
  scale_fill_viridis(discrete = T) +
  scale_color_viridis(discrete = T) +
  geom_sf_text(data = stas, aes(label = shortname))
