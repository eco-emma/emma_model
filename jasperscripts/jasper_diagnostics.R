### Check collinearity among envvars
library(tidyverse)
targets::tar_load(envdata)
targets::tar_load(envvars)
envdata %>%
  select(all_of(envvars)) %>%
  cor(use = "complete.obs")

### Check distributions of the spatial predictions for the model parameters
library(raster)
library(tidyverse)
targets::tar_load(spatial_outputs)
hist(spatial_outputs)

### Check distributions of the model parameters
library(tidyverse)
targets::tar_load(model_results)
model_results %>%
  filter(parameter %in% c("alpha", "gamma", "lambda", "A", "phi")) %>%
  ggplot() +
  geom_histogram(aes(mean)) +
  facet_wrap(~parameter, scales = "free")

model_results %>%
  filter(parameter == "phi")

### Check the relationship between NDVI and age in the training data
library(tidyverse)
targets::tar_load(dyndata_training)
dyndata_training %>%
  ggplot(aes(x = age, y = ndvi)) +
  geom_hex()
