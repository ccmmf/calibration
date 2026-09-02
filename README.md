# calibration

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

Ensemble parameter calibration for process-based ecosystem models.

The package estimates a model's parameters from field observations with Ensemble
Kalman Inversion (EKI): it runs an ensemble of parameter sets through the model
and moves them toward the values that fit the data. It is not tied to any one
model, site, or variable, and it is set up so other calibration methods can be
added alongside EKI.

## Installation

Install from the source directory:

``` r
install.packages("calibration", repos = NULL, type = "source")
```

or, during development:

``` r
pkgload::load_all("calibration")
```

The SIPNET forward model and the workflow scripts also need PEcAn.

## Example

A calibration is one call, `calibrate(obs, prior, forward, control)`. Here the
model is the identity, so the answer is known and we can check the calibration
finds it:

``` r
library(calibration)

prior <- prior_from_specs(list(
  theta1 = list(distn = "norm", parama = 0, paramb = 5),
  theta2 = list(distn = "norm", parama = 0, paramb = 5)
))

y <- c(obs1 = 2, obs2 = -1)
Sigma <- diag(c(0.05, 0.05)); dimnames(Sigma) <- list(names(y), names(y))
obs <- list(y = y, Sigma = Sigma)

forward <- function(U, iteration) { G <- U; colnames(G) <- names(y); G }

result <- calibrate(obs, prior, forward,
                    calibration_control(n_particles = 300, n_iterations = 3, seed = 1))

colMeans(result$U)   # near c(2, -1)
```

## The four pieces

You provide four things to `calibrate()`:

- `obs`: the observations, `list(y, Sigma, meta)`, from `build_obs()`.
- `prior`: the prior over the parameters, from the `prior_from_*()` constructors.
- `forward`: a function that runs the model at a parameter matrix and returns its
  predictions at each observation, from `make_forward_sipnet()` or your own.
- `control`: the method and its settings, from `calibration_control()`.

## Running a real calibration

The numbered scripts run a calibration end to end from a config:

```
Rscript scripts/010_prepare_observations.R --config <config.yml>
Rscript scripts/020_build_priors.R          --config <config.yml>
Rscript scripts/030_calibrate.R             --config <config.yml>
Rscript scripts/040_plot.R                  --config <config.yml>
```

`examples/salinas_soc/` is a worked example (soil carbon at the Salinas organic
cropping systems), and `vignettes/calibration_demo.qmd` walks through the whole
thing step by step.

## Layout

- `R/` the package: the estimator, the transport maps, the priors, the
  observations, the SIPNET forward model, scores, and plots.
- `scripts/` the numbered workflow.
- `examples/` a worked example config and its notes.
- `tests/` unit tests.
- `vignettes/` the demo.
- `runs/` per-site SIPNET run configs for the cal/val sites.
- `tools/event_prep/` the scripts that generate the `events.json` files.

## Cal/val run configs (`runs/`)

One directory per site, plus a combined `site_info.csv` and a shared `template.xml`.

| site | crop | PFT | window |
|---|---|---|---|
| `modesto` | almond | `temperate.deciduous` | 2018-2019 |
| `russell_ranch` | corn / tomato / wheat | `annual_crop` | 1992-2014 |
| `salinas_socs` | lettuce / broccoli | `annual_crop` | 2003-2011 |
| `us_bi1` | alfalfa | `annual_crop` | 2017-2023 |
| `us_bi2` | corn | `annual_crop` | 2016-2023 |
| `us_twt` | rice | `annual_crop` | 2010-2023 |

`modesto` is the only `temperate.deciduous` site, so it keeps its own `template.xml`;
the other five share `runs/template.xml`.

### One site_info for all sites

`runs/site_info.csv` carries all six sites; there are no per-site copies. Every
`user_config.yaml` points at it with `site_info_file: "../site_info.csv"`.

⚠️ **The workflow has no site filter, so this file drives which sites a run covers.**
`01_ERA5_nc_to_clim.R` and `03_xml_build.R` both process every row of whatever
`site_info` they are given, and the run window comes from `--start_date` / `--end_date`
rather than from the file. There is no `--site` option. So invoking one site's config
builds met and settings for all six, using that config's dates.

The six sites have five distinct windows, so a single multi-site run is not currently
correct for all of them. Running one site in isolation needs either a site filter in
the CLI or the window moving into `site_info.csv` as per-row columns. Until then, pass
a one-row `site_info` explicitly with `--site_info_file` when running a single site.

### What is committed and what is not

Committed are inputs only: `*_user_config.yaml`, `*_site_info.csv`, `template.xml` and
`events.json`. **`settings.xml` is not committed** - `03_xml_build.R` generates it into the
run directory and `run-ensembles` reads it from there, so a copy here would never be read.
Met, initial conditions and model output live on the cluster and in
`s3://carb/calval_sa_inputs/`, not in git.

### Running one

`external_paths` are relative to the config's own directory, and the CLI resolves them from
`INVOCATION_CWD`, which defaults to wherever you invoke from. Point it at the site directory:

```bash
SITE=$PWD/runs/us_twt
cd /path/to/workflows
INVOCATION_CWD=$SITE ./magic-ensemble prepare       --config $SITE/us_twt_user_config.yaml
INVOCATION_CWD=$SITE ./magic-ensemble run-ensembles --config $SITE/us_twt_user_config.yaml
```

Running from the workflows checkout without setting it fails at the first step with
`external_paths.template_file: source file not found`. That is the CLI resolving
`template.xml` against the workflows checkout rather than the site directory.

### Known gaps

- `magic-ensemble` replaces the whole `<model>` element from `workflow_manifest.yaml` at
  prepare time, so `<revision>`, `<binary>` and `<options>` set in a template here do not
  survive. That includes `NITROGEN_CYCLE` and `ANAEROBIC`, which modesto needs.
- `events.in` is derived from `events.json` but nothing checks the two agree; they have
  drifted before.
- Sites with multiple treatments do not yet have one `events.json` per treatment.
