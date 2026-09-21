#!/usr/bin/env Rscript
# build the prior dist_list and cache it. priors come from the pft
# posterior, from explicit specifications, and (optional) an obs anchored state.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

settings_file <- file.path(
  config$forward$workspace %||% file.path(config$scc, config$forward$run_dir),
  "settings.xml"
)
settings <- PEcAn.settings::read.settings(settings_file)
# config$soil_pft is a vector: the calibrated rates are one shared quantity written
# into every soil PFT. select explicitly and require every named PFT to be present.
soil_pft_names <- as.character(config$soil_pft)
pft_names <- vapply(settings$pfts, `[[`, character(1), "name")
missing_pfts <- setdiff(soil_pft_names, pft_names)
if (length(missing_pfts) > 0L) {
  PEcAn.logger::logger.severe(
    "soil PFT(s) named in the config are not in the settings: ",
    paste(missing_pfts, collapse = ", "), "; settings carry ",
    paste(pft_names, collapse = ", ")
  )
}
posterior_files <- stats::setNames(
  vapply(settings$pfts[match(soil_pft_names, pft_names)],
         `[[`, character(1), "posterior.files"),
  soil_pft_names
)

prior <- c(
  prior_from_shared_postdistns(config$priors$post_distns_params, posterior_files),
  prior_from_specs(config$priors$specified)
)

# calibrated initial state anchored to the observation, when configured.
state <- config$priors$state
if (!is.null(state)) {
  obs <- readRDS(file.path(config$cache_dir, "obs.rds"))
  prior <- c(prior, state_prior_from_obs(
    obs$meta, prefix = state$prefix, variable = state$variable,
    from_unit = state$from_unit, to_unit = state$to_unit,
    anchor_year = state$anchor_year
  ))
}

# a parameter declared in two sources would sample two columns under one name
dup <- names(prior)[duplicated(names(prior))]
if (length(dup) > 0L) {
  PEcAn.logger::logger.severe(
    "parameter(s) declared by more than one prior source: ",
    paste(unique(dup), collapse = ", ")
  )
}

out <- file.path(config$cache_dir, "prior.rds")
saveRDS(prior, out)
PEcAn.logger::logger.info("cached prior (", length(prior), " params) -> ", out)
