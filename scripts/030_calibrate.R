#!/usr/bin/env Rscript
# run the calibration and save the result. launching is left to pecan and
# the prepared host block (see forward_sipnet.R); nothing here touches it.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

options(warn = 1)
options(error = quote({
  if (!interactive()) q(status = 1)
}))

obs   <- readRDS(file.path(config$cache_dir, "obs.rds"))
prior <- readRDS(file.path(config$cache_dir, "prior.rds"))

# fit only study years at or after fit_from_study_year. the earliest year stays
# the initial condition; the state prior in 020 anchors there, so it is dropped
# from the fitted target here but not from the run.
fit_from <- if (is.null(config$fit_from_study_year)) {
  min(obs$meta$study_year)
} else {
  config$fit_from_study_year
}
keep <- obs$meta$slot[obs$meta$study_year >= fit_from]
obs$y     <- obs$y[keep]
obs$Sigma <- obs$Sigma[keep, keep, drop = FALSE]
obs$meta  <- obs$meta[obs$meta$study_year >= fit_from, ]
PEcAn.logger::logger.info("fitting study_year >= ", fit_from, ": ", length(obs$y), " slots")

settings <- PEcAn.settings::read.settings(
  file.path(config$scc, config$forward$run_dir, "settings.xml")
)

forward <- make_forward_sipnet(
  settings = settings, obs = obs, n_particles = config$eki$n_particles,
  harvest_var = config$forward$harvest_var,
  from_unit = config$forward$from_unit, to_unit = config$forward$to_unit,
  soil_pft = config$soil_pft,
  state_prefix = config$priors$state$prefix,
  state_pool = config$forward$state_pool
)

control <- calibration_control(
  method = "eki", n_particles = config$eki$n_particles,
  n_iterations = config$eki$n_iterations, seed = config$eki$seed
)

result <- calibrate(obs, prior, forward, control)

out <- file.path(config$cache_dir, "result.rds")
saveRDS(result, out)
PEcAn.logger::logger.info("cached result -> ", out)
