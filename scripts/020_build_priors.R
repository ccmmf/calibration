#!/usr/bin/env Rscript
# build the prior dist_list and cache it. priors come from the pft
# posterior, from explicit specifications, and (optional) an obs anchored state.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

settings <- PEcAn.settings::read.settings(
  file.path(config$scc, config$forward$run_dir, "settings.xml")
)
soil_pft <- Filter(function(p) p$name == config$soil_pft, settings$pfts)[[1]]

prior <- c(
  prior_from_postdistns(config$priors$post_distns_params, soil_pft$posterior.files),
  prior_from_specs(config$priors$specified)
)

# calibrated initial state anchored to the observation, when configured.
state <- config$priors$state
if (!is.null(state)) {
  obs <- readRDS(file.path(config$cache_dir, "obs.rds"))
  prior <- c(prior, state_prior_from_obs(
    obs$meta, prefix = state$prefix,
    from_unit = state$from_unit, to_unit = state$to_unit,
    anchor_year = state$anchor_year
  ))
}

out <- file.path(config$cache_dir, "prior.rds")
saveRDS(prior, out)
PEcAn.logger::logger.info("cached prior (", length(prior), " params) -> ", out)
