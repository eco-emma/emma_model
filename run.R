#!/usr/bin/env Rscript

# This is a helper script to run the pipeline.
# Choose how to execute the pipeline below.
# See https://books.ropensci.org/targets/hpc.html
# to learn about your options.


# Timing

start_time <- Sys.time()

# authorize github.  Note this assumes there is an environmental variable
# called 'GITHUB_PAT", which contains your PAT

gitcreds::gitcreds_approve(list(
  protocol = "https",
  host = "github.com",
  username = NULL,
  password = Sys.getenv("GITHUB_PAT")
))

# Run targets

targets::tar_make(reporter = "verbose")
# targets::tar_make_clustermq(workers = 2) # nolint
# targets::tar_make_future(workers = 2) # nolint

# Print elapsed time
elapsed_time <- difftime(
  time2 = start_time,
  time1 = Sys.time(), units = "hours"
) |> round(digits = 2)

print(paste("Targets workflow ran for a total of ", elapsed_time, " hours.", sep = ""))
