#!/usr/bin/env Rscript
# build the calibration target (y, Sigma, meta) and cache it

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

obs <- build_obs(
  cal_val_dir = file.path(config$scc, config$observations$dir),
  targets = config$observations$targets
)

dir.create(config$cache_dir, showWarnings = FALSE, recursive = TRUE)
out <- file.path(config$cache_dir, "obs.rds")
saveRDS(obs, out)
PEcAn.logger::logger.info("cached obs -> ", out)
