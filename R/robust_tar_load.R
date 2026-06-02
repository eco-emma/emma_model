
#' @author Brian Maitner
#' @description  Per https://github.com/ropensci/stantargets/discussions/60#discussioncomment-6513371, some targets objects are saved as file types other than .RDS.  This function attempts to figure out the correct file time and load things

robust_tar_load <- function(object_name, location = "_targets/objects/"){


      #first, try rds

      e <- tryCatch(readRDS(file.path(location,object_name)),error = function(e)e)

      if(!inherits(e,"error")){return(e)}

      #then, tryformat = "qs"

      e <- tryCatch(qs::qread(file.path(location,object_name)),error = function(e)e)

      if(!inherits(e,"error")){return(e)}

      #finall try format = "fst"

      e <- tryCatch(fst::read_fst(file.path(location,object_name)),
                    error = function(e)e)

      if(!inherits(e,"error")){return(e)}

      #if that all fails, throw a message

      warning("Object couldn't be loaded")
      stop("Object couldn't be loaded")


} # end fx
