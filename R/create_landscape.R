# ## NOT FINISHED _ NON FUNCTIONAL DO NOT USE WITH FIXING
#
# # Function to simulate a landscape with autocorrelated elevation
#
# simulate_autocorrelated_landscape <- function(extent, resolution,
#                                               mean_elev, variance_elev,
#                                               nugget, sill, range,
#                                               model = "exponential") {
#
#   # Create empty raster object
#   elev <- terra::rast(extent, resolution, crs = "+proj=longlat +datum=WGS84")
#
#   # Generate spatial coordinates
#   coords <- terra::crds(elev)
#   x <- coords[, 1]
#   y <- coords[, 2]
#
#   # Create distance matrix
#   dist <- geosphere::distm(cbind(x, y))
#
#   # Define semivariogram function
#   variogram <- variogram(dist, log(elev[]), model = model,
#                          nugget = nugget, sill = sill, range = range)
#
#   # Generate random field with specified semivariogram
#   elev[] <- krige(log(elev[]), dist, variogram)$fitted
#
#   # Transform back to original scale
#   elev[] <- exp(elev[])
#
#   # Return the simulated landscape
#   return(list(elevation = elev))
# }
#
# # Example usage
# # Define parameters
# extent <- terra::ext(c(xmin = -10, xmax = 10, ymin = -10, ymax = 10))
# resolution <- 0.1
# mean_elev <- 100
# variance_elev <- 25
# nugget <- 0.2
# sill <- 0.8
# range <- 500
# model <- "exponential" # Other options: "spherical", "gaussian"
#
# # Simulate the landscape
# landscape <- simulate_autocorrelated_landscape(extent, resolution,
#                                                mean_elev, variance_elev,
#                                                nugget, sill, range, model)
#
# # Visualize the results
# plot(landscape$elevation, main = "Simulated Landscape with Autocorrelation")
#
# # Further analysis on the simulated landscape
