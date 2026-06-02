library(targets)
library(piggyback)

release_model_outputs <- function(model_results,
                                  spatial_outputs,
                                  model_prediction,
                                  temp_directory = "data/temp/release/"){

  # create temp dir if needed
    if(!dir.exists(temp_directory)){
      dir.create(temp_directory)
    }

  #specify release internally, since we don't intend to change it much

    release <- "current"

  # check/create release

    assets <- pb_list(repo = "eco-emma/emma_model")

    if(!release %in% assets$tag){

      pb_new_release(repo = "eco-emma/emma_model",
                     tag = release)
    }

  #temporarily save objects
    saveRDS(object = model_results,
            file = file.path(temp_directory, "model_results.rds"))

    saveRDS(object = spatial_outputs,
            file = file.path(temp_directory, "spatial_outputs.rds"))

    saveRDS(object = model_prediction,
            file = file.path(temp_directory, "model_prediction.rds"))

  #uploads

    pb_upload(file = c(file.path(temp_directory, "model_results.rds"),
                       file.path(temp_directory, "spatial_outputs.rds"),
                       file.path(temp_directory, "model_prediction.rds")
                       ),
              repo = "eco-emma/emma_model",
              tag = release
              )

  #cleanup

    file.remove(c(file.path(temp_directory, "model_results.rds"),
                  file.path(temp_directory, "spatial_outputs.rds"),
                  file.path(temp_directory, "model_prediction.rds")
                  )
                )


}
