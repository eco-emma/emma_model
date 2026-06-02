

sync_envdata <- function(repo="eco-emma/emma_envdata",
                         path="data/envdata/")  {

  # if running on github - delete the data files and get them again
  #if(Sys.getenv("CI")!="") file.remove(list.files(path,full=T)) # delete all old files

  # piggyback::pb_download(repo = repo,
  #                        tag = "current",
  #                        dest = path,
  #                        overwrite = F,
  #                        show_progress = F)
  #

    robust_pb_download(repo=repo,
                        tag = "current",
                        dest = path,
                      overwrite = F)


    return(path)
}
