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
