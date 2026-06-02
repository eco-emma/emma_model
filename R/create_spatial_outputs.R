# Spatial Predictions

create_spatial_outputs <- function(envdata, envvars, model_results,data_training) {

  td <- envdata %>%
    left_join(dplyr::select(data_training, cellID, pid))

  xmat=as.matrix(td[,envvars])

  betas=model_results %>%
    filter(type=="beta") %>%
    mutate(term=sub("_.*$","",parameter)) %>%
    dplyr::select(term,median,xname)

  td$gamma = as.vector(xmat%*%filter(betas,term=="gamma")$median)
  td$lambda = as.vector(xmat%*%filter(betas,term=="lambda")$median)
  td$A = as.vector(xmat%*%filter(betas,term=="A")$median)
  td$RT=td$lambda*log(200*td$gamma) #calculate recovery time

  # get the template raster to align the predictions
  template="data/template.tif"
  if(!file.exists(template))
    download.file("https://github.com/eco-emma/emma_envdata/releases/download/processed_static/template.tif",destfile=template)
  domain=raster(template)

  vmat=left_join(data.frame(cellID=values(domain)),
                 dplyr::select(td,cellID, gamma, lambda, A,RT)) %>%
                dplyr::select(-cellID)

  # create a raster for each variable
  rasters =  foreach(i=1:ncol(vmat),.combine=stack) %do% {
    tdomain=domain
    values(tdomain)=vmat[,i]
    names(tdomain)=colnames(vmat)[i]
    return(tdomain)
  }
  crs(rasters)=CRS("+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs")

 return(rasters)
}
# =======
# # Spatial Predictions
#
# create_spatial_outputs <- function(envdata, envvars, model_results,data_training) {
#
#   td <- envdata %>%
#     left_join(dplyr::select(data_training, cellID, pid))
#
#   xmat=as.matrix(td[,envvars])
#
#   betas=model_results %>%
#     filter(type=="beta") %>%
#     mutate(term=sub("_.*$","",parameter)) %>%
#     dplyr::select(term,median,xname)
#
#   td$gamma = as.vector(xmat%*%filter(betas,term=="gamma")$median)
#   td$lambda = as.vector(xmat%*%filter(betas,term=="lambda")$median)
#   td$A = as.vector(xmat%*%filter(betas,term=="A")$median)
#   td$RT=td$lambda*log(200*td$gamma) #calculate recovery time
#
#   # get the template raster to align the predictions
#   template="data/template.tif"
#   if(!file.exists(template))
#     download.file("https://github.com/eco-emma/emma_envdata/releases/download/processed_static/template.tif",destfile=template)
#   domain=raster(template)
#
#   vmat=left_join(data.frame(cellID=values(domain)),
#                  dplyr::select(td,cellID, gamma, lambda, A,RT)) %>%
#                 dplyr::select(-cellID)
#
#   # create a raster for each variable
#   rasters =  foreach(i=1:ncol(vmat),.combine=stack) %do% {
#     tdomain=domain
#     values(tdomain)=vmat[,i]
#     names(tdomain)=colnames(vmat)[i]
#     return(tdomain)
#   }
#   crs(rasters)=CRS("+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs")
#
#  return(rasters)
# }
# >>>>>>> origin/dev-brian
