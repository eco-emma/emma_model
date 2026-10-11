# Claude Code — Project Instructions

## Agent personas

All agent personas live in **`.github/agents/*.agent.md`** as the single source
of truth (shared with GitHub Copilot and Cline). The `.claude/agents/` stubs
below delegate to those files — do not duplicate content.

Available subagents (invoke with `@<name>` or let Claude auto-delegate):

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

## Project context

This is the `emma_model` R/targets pipeline for Bayesian post-fire NDVI recovery
modeling in the EMMA project. Key files:
- `_targets.R` — pipeline definition
- `R/` — all pipeline functions
- `postfire_season*.stan` — Stan model definitions
- `.github/workflows/targets.yaml` — Actions workflow

## R style

Follow the [tidyverse style guide](https://style.tidyverse.org). See
`.github/instructions/r-style.instructions.md` and `AGENTS.md`.
