release_posteriors<-function(model_results,repo = "eco-emma/emma_model",tag = tag){
library(piggyback)

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail
  tryCatch(expr =   pb_new_release(repo = repo,
                                   tag =  tag),
           error = function(e){message("Previous release found")})

  pb_upload(file="_targets/objects/model_results",
            repo=repo,
            tag=tag,
            name = "posteriors.parquet")

}


if(F) t1=arrow::read_parquet("_targets/objects/model_output_batch")
