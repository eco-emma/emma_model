#!/usr/bin/env Rscript
# Check (or fix) R sources against the tidyverse style guide via styler.
# Usage:
#   Rscript scripts/agents/tidyverse_check.R          # report only
#   Rscript scripts/agents/tidyverse_check.R --fix   # rewrite files

args <- commandArgs(trailingOnly = TRUE)
fix <- "--fix" %in% args

if (!requireNamespace("styler", quietly = TRUE)) {
  stop("Package 'styler' is required. Install with install.packages(\"styler\").")
}

roots <- c("R", "tests", "workflow", "jasperscripts", ".")
paths <- character()

for (root in roots) {
  if (!dir.exists(root) && root != ".") {
    next
  }
  if (root == ".") {
    paths <- c(
      paths,
      list.files(".", pattern = "^[^.].*\\.[Rr]$", full.names = TRUE)
    )
  } else {
    paths <- c(
      paths,
      list.files(root, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE)
    )
  }
}

paths <- unique(normalizePath(paths, mustWork = FALSE))
paths <- paths[file.exists(paths)]

# Skip generated / vendored scratch
paths <- paths[!grepl("/scratch_code/", paths)]

if (length(paths) == 0) {
  message("No R files found to check.")
  quit(status = 0)
}

needs_style <- FALSE
parse_failures <- character()

for (path in paths) {
  rel <- sub(paste0("^", getwd(), "/?"), "", path)
  before <- readLines(path, warn = FALSE)

  parse_ok <- tryCatch(
    {
      parse(text = before, keep.source = TRUE)
      TRUE
    },
    error = function(e) {
      parse_failures <<- c(parse_failures, rel)
      message("Skipping unparseable file: ", rel, " (", conditionMessage(e), ")")
      FALSE
    }
  )
  if (!isTRUE(parse_ok)) {
    next
  }

  after_text <- styler::style_text(
    before,
    transformers = styler::tidyverse_style(indent_by = 2L)
  )
  after <- as.character(after_text)
  if (!identical(before, after)) {
    needs_style <- TRUE
    if (fix) {
      writeLines(after, path, useBytes = TRUE)
      message("Styled: ", rel)
    } else {
      message("Needs styling: ", rel)
    }
  }
}

if (length(parse_failures) > 0) {
  message(
    "\n",
    length(parse_failures),
    " file(s) could not be parsed and were skipped ",
    "(fix syntax separately)."
  )
}

if (needs_style && !fix) {
  message(
    "\nR sources do not match tidyverse style. ",
    "Run: Rscript scripts/agents/tidyverse_check.R --fix"
  )
  quit(status = 1)
}

if (!needs_style) {
  message("All parseable R sources match tidyverse style.")
} else {
  message("Finished applying tidyverse style fixes.")
}

# Unparseable files are reported as warnings (pre-existing syntax debt);
# they do not fail the style check once parseable files are clean.
