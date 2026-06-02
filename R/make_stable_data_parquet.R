make_stable_data_parquet <- function(envdata_files,
                                     filename = "stable_data.gz.parquet"){

  # get list of stable parquets

      files <- data.frame(file=list.files(file.path(envdata_files))) %>%
        filter(grepl(pattern = ".gz.parquet",x=file)) %>%
        filter(!grepl(pattern = "stable",x=file)) %>%
        filter(!grepl(pattern = "-dynamic",x=file))

  # process data

      for(i in 1:nrow(files)){

        data_i <- open_dataset(sources = file.path(envdata_files,files$file[i])) %>% collect()

        if(i == 1){

          data_i <-
          data_i %>%
            relocate(cellID, .after = y)

          stable_data <- data_i

        }else{

          stable_data <- full_join(stable_data,data_i,
                                   by = join_by(x, y, cellID))

            }

      }


  # Filter out Non-land using SA NLC

    stable_data <-
    stable_data %>%
      filter(SA_NLC_2020_GEO.tif != 0)

  # Write parquet

    message("Creating gzip file ", Sys.time())

    stable_data %>%
    write_parquet(sink = file.path(envdata_files,"stable_data.gz.parquet"),
                  compression = "gzip",
                  chunk_size = 1000) #note: chunk size here details the number of chunks written at once

  # cleanup

    rm(data_i, stable_data)
    gc()

  # Return filename

  message("Finished processing stable model data")
  return(file.path(envdata_files,"stable_data.gz.parquet"))

}
