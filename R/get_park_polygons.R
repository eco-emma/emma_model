library(sf)
library(tidyverse)
library(piggyback)
library(dplyr)

#' @param temp_directory Temporary working directory (will be deleted)
#' @param sacad_filename filename of the sacad shapefile
#' @param sapad_filename filename of the sapad shapefile
#' @note This function uses the emma_envdata domain to crop the park polygons
#' @return sf dataframe object containing the parks
get_park_polygons <- function(temp_directory = "data/temp/parks",
                              sacad_filename = "data/manual_downloads/protected_areas/SACAD_OR_2021_Q4.shp",
                              sapad_filename = "data/manual_downloads/protected_areas/SAPAD_OR_2021_Q4.shp",
                              cape_nature_filename = "data/manual_downloads/protected_areas/Provincial_Nature_Reserves/CapeNature_Reserves_gw.shp"){

  # Pull in different protected areas

    sacad <- st_read(sacad_filename)
    sapad <- st_read(sapad_filename)

  # Pull in CapeNature reserves

    cn <- st_read(cape_nature_filename)

  # Combine the two pa datasets

    sacad %>%
      mutate( PROC_DOC = NA) %>%
      dplyr::select(colnames(sapad)) %>%
      bind_rows(sapad) -> all_pas

  rm(sacad,sapad)


  # Create directory if needed

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  # Download domain

    pb_download(file = "domain.gpkg",
                tag = "raw_static",
                repo = "eco-emma/emma_envdata",
                dest = temp_directory)

  # Read domain

    domain <- st_read(file.path(temp_directory, "domain.gpkg"))

  # Match projections

    all_pas <- st_transform(x = all_pas,
                           crs = st_crs(domain))

    cn <- st_transform(x = cn,
                            crs = st_crs(domain))

  # Filter to National Parks only

    all_pas %>%
      filter(grepl(pattern = "national park",
                   x = SITE_TYPE,ignore.case = TRUE)) -> all_pas


  # Crop PAs

    #Use this if you want the park boundaries cropped
    # all_pas <-
    # st_intersection(x = domain,
    #                 y = st_make_valid(all_pas))%>%
    #   dplyr::select(-domain)

    #Use this if you just want intersecting parks, even the bits outside our domain
    all_pas <- all_pas[which(as.logical(st_intersects(x = all_pas, y = domain))),] %>%
                  st_make_valid()

    cn <- cn[which(as.logical(st_intersects(x = cn, y = domain))),]%>%
              st_make_valid()

  # update projection
    pb_download(file = "template.tif",
                dest = temp_directory,
                repo = "eco-emma/emma_envdata",
                tag = "processed_static")

    template <- terra::rast(file.path(temp_directory,"template.tif"))

    all_pas <-
    st_transform(x = all_pas,
                 crs = st_crs(template))

    cn <-
      st_transform(x = cn,
                   crs = st_crs(template))

  # cleanup
    unlink(file.path(temp_directory),recursive = TRUE,force = TRUE)


  # make output

    out <-
      list("cape_nature" = cn,
         "national_parks" = all_pas)

  # return data product
    return(out)

}
############################################



