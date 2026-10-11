# AI Agent Guidelines — emma_model

## Project overview

`emma_model` is the Bayesian modeling & change-detection module of EMMA
(Environmental Monitoring and Modelling for Africa). It fits hierarchical
post-fire NDVI recovery models (Stan / `stantargets`) over environmental
covariates prepared by `emma_envdata`.

Key files:
- `_targets.R` — pipeline definition
- `R/` — pipeline functions
- `postfire_season*.stan` — core Stan models
- `.github/workflows/targets.yaml` — Actions workflow

## Agent personas

All agent personas live in **`.github/agents/*.agent.md`** as the single source
of truth (shared with GitHub Copilot, Cline, and Claude Code). Tool-specific
stubs under `.claude/agents/` and `.clinerules/` delegate to those files — do
not duplicate content.

| Subagent | Master file | Purpose |
|-----------------|----------------------------------------------|-----------------------------------------------|
| `@ci` | `.github/agents/ci.agent.md` | Full pre-commit orchestrator |
| `@coder-alpha` | `.github/agents/coder_alpha.agent.md` | Correctness-first R coder |
| `@coder-beta` | `.github/agents/coder_beta.agent.md` | Performance-first R coder |
| `@coder-gamma` | `.github/agents/coder_gamma.agent.md` | Minimalist R coder |
| `@commenter` | `.github/agents/commenter.agent.md` | Code documentation reviewer |
| `@geo` | `.github/agents/geo.agent.md` | Geospatial reviewer |
| `@gh-actions` | `.github/agents/gh_actions.agent.md` | GitHub Actions compatibility reviewer |
| `@science` | `.github/agents/science.agent.md` | Scientific methods reviewer |
| `@stats` | `.github/agents/stats.agent.md` | Statistical accuracy reviewer |
| `@targets` | `.github/agents/targets.agent.md` | targets pipeline reviewer |

## R code style (required)

All R code written or edited by agents **must** follow the
[tidyverse style guide](https://style.tidyverse.org).

- Prefer tidyverse idioms (`dplyr`, `tidyr`, `purrr`, `ggplot2`, `readr`, `tibble`).
- Use the native pipe `|>` (not `%>%`).
- Use `<-` for assignment; 2-space indent; max line width 80.
- `snake_case` for functions, arguments, and objects.
- Before committing R changes, run `styler` (tidyverse transformers), e.g.
  `styler::style_dir("R")` or `Rscript scripts/agents/tidyverse_check.R --fix`.
- Do not change program behavior when restyling; formatting only.
- Detailed conventions: `.github/instructions/r-style.instructions.md`.
