print("Loading libraries")

  library(stantargets)
  library(targets)
  library(tarchetypes)
  library(tidyverse)
  library(arrow)
  library(piggyback)
  #library(plotly)
  # library(leaflet)
  #library(rnoaa)
  #remotes::install_github("ropensci/stantargets")
  # if(!"basemapR" %in% rownames(installed.packages())){
  #   devtools::install_github('Chrisjb/basemapR')
  # }

print("Attempting to install needed packages")

  if(!"plotly" %in% rownames(installed.packages())){

    # create local user library path (not present by default)
    dir.create(path = Sys.getenv("R_LIBS_USER"), showWarnings = FALSE, recursive = TRUE)
    # install to local user library path
    install.packages("plotly", lib = Sys.getenv("R_LIBS_USER"))

  }


print("Sourcing files")
  source("scratch_code/report_generator.R") #this should be moved
  source("https://raw.githubusercontent.com/AdamWilsonLab/emma_envdata/main/R/robust_pb_download.R")
  # source all files in R folder
  #  lapply(list.files("R",pattern="[.]R",full.names = T), source)

    list.files("R",pattern="[.]R",full.names = T)%>%
    stringr::str_subset(c("R/detect_anomalies.R"), negate=TRUE)%>%
      stringr::str_subset(c("R/predict_the_future.R"), negate=TRUE)%>%
    lapply( source)

print("Setting options")
  options(tidyverse.quiet = TRUE)
  options(clustermq.scheduler = "multicore")

  tar_option_set(packages = c("piggyback","cmdstanr", "posterior", "bayesplot", "tidyverse",
                              "stringr","knitr","sf","stars","units","arrow","lubridate","stantargets",
                              "doParallel","raster"),
                 deployment="main")

#print("Setting env")
#Sys.setenv(HOME="/home/rstudio")

#print("Setting cmdstan path")
#cmdstanr::set_cmdstan_path()#"/home/rstudio/.cmdstanr/cmdstan-2.28.1") #this is causing errors
#cmdstanr::check_cmdstan_toolchain()

# Install cmdstan if needed

    if(!dir.exists(file.path(system(command = "echo $HOME", intern = TRUE),".cmdstan"))){

      message("cmdstan installation not found, installing cmdstan")
      cmdstanr::install_cmdstan()

    }else{

      message("cmdstan installation found, skipping installation")

    }


# tar_destroy(ask = F) #Uncomment this to destroy the targets objects


# Testing and training time windows
  print("setting time windows")
  training_window=c("2000-01-01","2014-07-01")
  testing_window=c("2014-07-01","2022-01-01")
  #predicting_window=c("2000-01-01",as.character(Sys.Date()))
  #predicting_window=c("2022-01-01",as.character(Sys.Date()))
  predicting_window=c("2021-01-01","2022-01-01")

# decide sampling proportion
  total_fynbos_pixels=348911
  #sample_proportion=round(18000/total_fynbos_pixels,2);sample_proportion # ~5% works on github actions
  #sample_proportion=round(34891/total_fynbos_pixels,2);sample_proportion # ~10% sample
  sample_proportion=1;sample_proportion # ~10% sample
  sample_proportion_prediction =1
  output_samples = 10 #number of output samples to characterize the posterior



#tar_option_set(debug = "spatial_outputs")

## Download the most recent data release
list(
  tar_target(
    envdata_files,
    robust_pb_download(file=NULL,
                       repo="AdamWilsonLab/emma_envdata",
                       dest="data/envdata/",
                       tag="current",
                       show_progress=F,
                       overwrite=F,
                       sleep_time=3),
    format="file"),

  tar_target(long_pixels,
             find_long_records(env_files = envdata_files,
                               max_years_to_first_fire = 2,
                               min_years_without_fire = 10,
                               ndvi_prob = 0.8)),

  tar_target(envdata,
             tidy_static_data(
               envdata_files,
               remnant_distance=2, #drop pixels within this distance of remnant edge (km)
               #region=c(xmin = 18.3, xmax = 19.3, ymin = -34.3, ymax = -33.3), #core
               region=c(xmin = 0, xmax = 30, ymin = -36, ymax = -20), #whole region
               #region=c(xmin = 18.301425, xmax = 18.524242, ymin = -34.565951, ymax = -34.055531), #peninsula
               sample_proportion= sample_proportion,
               long_pixels=long_pixels)),

  tar_target(envvars,c( #select and possibly rename envvars to be included in model
#    "Mean_January_Precipitation" = "CHELSA_prec_01_V1.2_land.tif",
    "Mean_July_Precipitation" =  "CHELSA_prec_07_V1.2_land.tif",
#    "Soil_pH" = "soil_pH.tif",
    "Max_Air_Temperature_Warmest" = "CHELSA_bio10_05_V1.2.tif",
    "Min_Air_Temperature_Coldest" =  "CHELSA_bio10_06_V1.2.tif",
#    "Mean_Annual_Air_Temperature"="CHELSA_bio10_01_V1.2.tif", #select env vars to use in model
#    "Mean_Annual_Precipitation"="CHELSA_bio10_12_V1.2.tif",
#    "Mean_Monthly_Precipitation_In_Driest_Quarter"="CHELSA_bio10_17_V1.2.tif",
#    "Mean_Annual_Cloud_Frequency"="MODCF_meanannual.tif",
    "Cloud_Seasonal_Concentration"="MODCF_seasonality_concentration.tif",
    "Topographic_Diversity"="alos_topodiversity.tif")),
#    "ALOS_CHILI"="alos_chili.tif",
#    "ALOS_MTPI"="alos_mtpi.tif")),
  tar_target(
    data_training,
    filter_training_data(envdata,envvars)
  ),
  tar_target(
    dyndata_training,
    tidy_dynamic_data(envdata,
                      date_window=ymd(training_window))
  ),
  tar_target(
    dyndata_testing,
    tidy_dynamic_data(envdata,
                      date_window=ymd(testing_window))
  ),
  tar_target(
    stan_data,
    create_stan_data(
      data=data_training,
      dyndata=dyndata_training,
      fit=1,
      predict=1)
  ),

  #tried mcmc - 500 samples in ~12 hours
  tar_stan_vb(
    model,
    stan_files = "postfire_season.stan",
    data = stan_data,
    quiet=T,
    pedantic=F,
    adapt_engaged=F,
    eta=0.11,
    iter = 1000000, #should be 1000 or more - 100 is just to run quickly - CP converged after 6400
    garbage_collection=T,
    init = 0.5, #list(list(phi = 0.5, tau_sq = 0.1, gamma_tau_sq = 0.1, lambda_tau_sq = 0.1, alpha_tau_sq = 0.1, A_tau_sq = 0.1)),
    tol_rel_obj = 0.001,
    #output_samples = 500,
    output_samples = output_samples, #use smaller numbers if running out of space.
    #error = "continue", # Used it when getting the error - Chain 1 Exception: normal_rng: Location parameter[975276] is -inf, but must be finite! (in '/tmp/Rtmp8DI5YZ/model-2ad6dc5ec5b.stan', line 91, column 4 to column 33)
    format_df="parquet"
    #format="parquet"
  ),
  #
  #Crashes locally, presumably due to memory.  Also may contain errors
    # tar_stan_mcmc(name = model_mcmc,
    #               stan_files = "postfire_season.stan",
    #               data = stan_data,
    #               quiet = FALSE,
    #               pedantic = FALSE,
    #               force_recompile = FALSE,
    #               init = 0.5,
    #               adapt_engaged = F,
    #               garbage_collection = T,
    #               format_df = "parquet",
    #               return_draws = FALSE,parallel_chains = 1),

   tar_target(model_results,
              summarize_model_output(model_summary_postfire_season, stan_data, envdata)),
   tar_target(model_prediction,
             summarize_predictions(model_results,stan_data,envdata)),
  tar_target(spatial_outputs,
             create_spatial_outputs(envdata, envvars, model_results, data_training)),
  # tar_target(name = release_outputs,
  #            command = release_model_outputs(model_results = model_results,
  #                                            spatial_outputs = spatial_outputs,
  #                                            model_prediction = model_prediction,
  #                                            temp_directory = "data/temp/release/")),
 # tar_target(release,
 #            release_posteriors(
 #              model_output,
 #              file="targets/objects/model_results",
 #              repo = "eco-emma/emma_model",
 #              tag = "current")),

# attempts to predict from fitted model ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#set up prediction data

  tar_target(long_pixels_predict,
             find_long_records(env_files = envdata_files,
                               max_years_to_first_fire = NULL,
                               min_years_without_fire = NULL,
                               ndvi_prob = 0)),
  tar_target(envdata_predict,
             tidy_static_data(
               envdata_files,
               remnant_distance=2, #drop pixels within this distance of remnant edge (km)
               #region=c(xmin = 18.3, xmax = 19.3, ymin = -34.3, ymax = -33.3), #core
               region=c(xmin = 0, xmax = 30, ymin = -36, ymax = -20), #whole region
               #region=c(xmin = 18.301425, xmax = 18.524242, ymin = -34.565951, ymax = -34.055531), #peninsula
               sample_proportion= sample_proportion_prediction,
               long_pixels=long_pixels_predict)),
  tar_target(
    data_predicting,
    filter_training_data(envdata_predict,envvars)
  ),
  tar_target(
    dyndata_predicting,
    tidy_dynamic_data(envdata_predict,
                      date_window=ymd(predicting_window))
  ),
  tar_target(
    stan_data_predict,
    create_stan_data(
      data=data_predicting,
      dyndata=dyndata_predicting,
      fit=1,
      predict=1)
  ),
  tar_target(
    stan_data_combined,
    combine_stan_data(stan_data = stan_data,
                      stan_data_predict = stan_data_predict)
  ),

# NOTE: for the prediction, alpha is just a random draw for now.  We need to either make this a function of the environment or else fit all pixels and use the fitted alphas.

tar_stan_vb(
  model_w_pred,
  stan_files = "postfire_season_predict.stan",
  data = stan_data_combined,
  quiet=T,
  pedantic=F,
  adapt_engaged=F,
  eta=0.11,
  iter = 100000, #should be 1000 or more - 100 is just to run quickly - CP converged after 6400
  garbage_collection=T,
  init = 0.5, #list(list(phi = 0.5, tau_sq = 0.1, gamma_tau_sq = 0.1, lambda_tau_sq = 0.1, alpha_tau_sq = 0.1, A_tau_sq = 0.1)),
  tol_rel_obj = 0.001,
  #output_samples = 500,
  output_samples = output_samples, #use smaller numbers if running out of space.
  #error = "continue", # Used it when getting the error - Chain 1 Exception: normal_rng: Location parameter[975276] is -inf, but must be finite! (in '/tmp/Rtmp8DI5YZ/model-2ad6dc5ec5b.stan', line 91, column 4 to column 33)
  format_df="parquet"
  #format="parquet"
),


# Release model output

  tar_target(
    release_stan_outputs,
    release_stan_objects(object_names = c("model_summary_postfire_season",
                                          "model_w_pred_summary_postfire_season_predict"),
                         tag = "model_output",
                         max_attempts = 10,
                         sleep_time = 10,
                         temp_directory="data/temp/pb_upload/",
                         ... = model_w_pred,
                         ... = model
    ),
  ),

  tar_target(
    release_html,
    robust_pb_upload(files = "index.html",
                     repo = "eco-emma/emma_model",
                     tag = "model_output",
                     max_attempts = 10,
                     sleep_time = 10,
                     temp_directory = "data/temp/pb_upload/",
                     ... =  model_w_pred,
                     ... =   model,
                     ... =  report
                     )
    ),



# render report ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   tar_render(report, "index.Rmd")

)
