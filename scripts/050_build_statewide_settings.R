#!/usr/bin/env Rscript
# build the PEcAn settings for the statewide treatment-effect matrix: one run
# section per (site, treatment arm), each pointing at that arm's events file and
# the site's shared met and initial conditions. writes settings.xml and the
# pinned default.param. builds settings only; configs and runs come from
# scripts/052_run_statewide_matrix.R.

library(PEcAn.settings)
library(PEcAn.logger)
suppressPackageStartupMessages(library(dplyr))

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)
logger.info("building statewide settings")

pkg <- config$event_package$root
inputs <- config$model_inputs$root
workspace <- config$workspace
dir.create(workspace, recursive = TRUE, showWarnings = FALSE)

## pinned parameters ----------------------------------------------------------
# write.config.SIPNET reads default.param then overwrites it from the pft trait
# samples, so pinning takes both halves: the value here and the trait dropped
# from the samples in 052. one half alone loses to the posterior.
settings <- read.settings(config$forward$template)
rev_num <- numeric_version(sub("^v", "", settings$model$revision, ignore.case = TRUE),
                           strict = FALSE)
if (is.na(rev_num)) {
  logger.severe("cannot parse model revision '", settings$model$revision, "'")
}
stock <- system.file(paste0("template.param_", if (rev_num >= "2.0") "v2" else "v1"),
                     package = "PEcAn.SIPNET")
if (!nzchar(stock)) {
  logger.severe("no stock template.param for revision ", settings$model$revision)
}
param <- utils::read.table(stock, stringsAsFactors = FALSE)
# defaults a pft posterior is still allowed to override
for (nm in names(config$default_param)) {
  hit <- param[[1]] == nm
  if (!any(hit)) logger.severe("no '", nm, "' row in ", stock)
  param[hit, 2] <- config$default_param[[nm]]
}
for (nm in names(config$fixed_params)) {
  sipnet_name <- config$fixed_params[[nm]]$sipnet
  hit <- param[[1]] == sipnet_name
  if (!any(hit)) logger.severe("no '", sipnet_name, "' row in ", stock)
  param[hit, 2] <- config$fixed_params[[nm]]$value
}
default_param <- file.path(workspace, "sipnet.default.param")
utils::write.table(param, default_param, quote = FALSE, row.names = FALSE,
                   col.names = FALSE)

## runs: one per (site, arm) --------------------------------------------------
sites <- utils::read.csv(file.path(pkg, "sites.csv"),
                         colClasses = c(site_id = "character"))
pairs <- utils::read.csv(file.path(pkg, "run_pairs.csv"),
                         colClasses = c(site_id = "character"))
asg <- utils::read.csv(config$pfts$assignment,
                       colClasses = c(site_id = "character"))

grid_label <- function(lat, lon) {
  g <- function(x) sprintf("%g", round(x * 2) / 2)
  paste0(g(lat), "N_", g(abs(lon)), "W")
}
clim_name <- sprintf("ERA5.%d.%s.%s.clim", config$model_inputs$met_member,
                     config$window$start, config$window$end)

arms <- pairs |>
  tidyr::pivot_longer(c(treatment, reference), values_to = "arm") |>
  distinct(site_id, arm) |>
  inner_join(sites |> select(site_id, lat, lon), by = "site_id") |>
  inner_join(asg |> select(site_id, veg_pft, soil_pft), by = "site_id") |>
  mutate(
    met_path = file.path(inputs, "data/ERA5_SIPNET", grid_label(lat, lon), clim_name),
    ic_path = file.path(inputs, "IC_files", site_id,
                        sprintf("IC_site_%s_%d.nc", site_id,
                                config$model_inputs$ic_member)),
    events_path = file.path(pkg, "events", site_id, arm, "events.in")
  )
missing <- arms |> filter(!file.exists(met_path) | !file.exists(ic_path) |
                            !file.exists(events_path))
if (nrow(missing) > 0) {
  logger.severe(nrow(missing), " runs are missing an input, first: ",
                missing$site_id[1], " ", missing$arm[1])
}

# a site whose initial conditions carry no usable pools cannot be configured;
# drop it here with the reason rather than failing mid-write.configs
usable <- vapply(unique(arms$site_id), function(s) {
  p <- PEcAn.data.land::prepare_pools(
    arms$ic_path[match(s, arms$site_id)], constants = list(sla = 10))
  !is.null(p) && all(c("soil", "wood") %in% names(p))
}, logical(1))
blocked <- names(usable)[!usable]
# the arms that survive are the ones write.configs records in runs_manifest.csv,
# so coverage against the design is read from there rather than tracked here
if (length(blocked) > 0) {
  logger.warn(length(blocked), " site(s) dropped for unusable initial pools: ",
              paste(blocked, collapse = ", "))
  arms <- arms |> filter(!site_id %in% blocked)
}

## expand the template --------------------------------------------------------
site_info <- data.frame(
  id = paste(arms$site_id, arms$arm, sep = "."),
  lat = arms$lat, lon = arms$lon,
  name = paste(arms$site_id, arms$arm, sep = "."),
  site_id = arms$site_id, arm = arms$arm,
  veg_pft = arms$veg_pft, soil_pft = arms$soil_pft,
  met_path = arms$met_path, ic_path = arms$ic_path,
  events_path = arms$events_path,
  stringsAsFactors = FALSE
)

set_run <- function(s) {
  site <- s$run$site
  s$run$start.date <- config$window$start
  s$run$end.date <- config$window$end
  s$run$site$met.start <- config$window$start
  s$run$site$met.end <- config$window$end
  s$run$site$site.pft <- list(veg = site$veg_pft, soil = site$soil_pft)
  s
}
set_inputs <- function(s) {
  site <- s$run$site
  s$run$inputs$met$path <- list(path1 = site$met_path)
  s$run$inputs$poolinitcond$path <- list(path1 = site$ic_path)
  s$run$inputs$poolinitcond$ensemble <- 1
  s$run$inputs$events$path <- list(path1 = site$events_path)
  s$run$inputs$pft.site <- NULL
  s
}

settings$model$binary <- config$model$binary
settings$model$default.param <- default_param
settings <- settings |>
  createMultiSiteSettings(site_info) |>
  papply(set_run) |>
  papply(set_inputs)

settings$ensemble$size <- 1
settings$ensemble$start.year <- as.integer(substr(config$window$start, 1, 4))
settings$ensemble$end.year <- as.integer(substr(config$window$end, 1, 4))

out <- file.path(workspace, "output")
settings$outdir <- out
settings$modeloutdir <- file.path(out, "out")
settings$rundir <- file.path(out, "run")
settings$host$outdir <- file.path(out, "out")
settings$host$rundir <- file.path(out, "run")

# the array launcher path in the host block is relative to the run directory
launcher_dir <- file.path(workspace, "scripts")
dir.create(launcher_dir, recursive = TRUE, showWarnings = FALSE)
file.copy(config$forward$launcher, file.path(launcher_dir, "sge_array_launcher.sh"),
          overwrite = TRUE)
Sys.chmod(file.path(launcher_dir, "sge_array_launcher.sh"), "0755")

write.settings(settings, outputfile = "settings.xml", outputdir = workspace)
logger.info("wrote ", file.path(workspace, "settings.xml"), ": ",
            nrow(site_info), " runs at ",
            dplyr::n_distinct(site_info$site_id), " sites")
