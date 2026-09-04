#!/usr/bin/env Rscript
# contract the raw curated observations into the fitted target. config$target is
# a list of contraction specs, each dispatched on its `type` (period_mean or
# contrast), so adding a variable or a site pair is a config edit, not a code
# edit.
#
# kept separate from 010 because 010's job is to read the curated data faithfully.
# what we choose to fit is a modeling decision and belongs where it can be read.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

if (length(config$target) == 0L) {
  PEcAn.logger::logger.severe(
    "config declares no target contractions; drop the target block to fit the ",
    "raw slots, or list entries with type period_mean or contrast"
  )
}

raw <- readRDS(file.path(config$cache_dir, "obs.rds"))

contract <- function(tg) {
  switch(tg$type,
    period_mean = period_mean_contrast(
      raw, variable = tg$variable, control = tg$control,
      years = if (is.null(tg$years)) NULL else seq(tg$years[[1]], tg$years[[2]]),
      new_variable = tg$new_variable
    ),
    contrast = contrast_target(
      raw, variable = tg$variable, treatment = tg$treatment, control = tg$control,
      new_variable = tg$new_variable
    ),
    PEcAn.logger::logger.severe("unknown target type '", tg$type, "'")
  )
}
obs <- do.call(bind_obs, lapply(config$target, contract))

out <- file.path(config$cache_dir, "target.rds")
saveRDS(obs, out)

PEcAn.logger::logger.info(length(obs$y), " target slots across ",
                          dplyr::n_distinct(obs$meta$variable), " variables")
PEcAn.logger::logger.info("cached target -> ", out)
