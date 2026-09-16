#!/usr/bin/env Rscript

# build the multisite PEcAn settings for a calibration run, plus a run dir
# default.param carrying the pinned parameters and one template initial
# condition per block.
#
# read a template, expand it with createMultiSiteSettings, fix up the per block
# bits with papply, write with write.settings. blocks come from a table, so
# adding or dropping a treatment is a data edit.

library(PEcAn.settings)

options <- list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml"),
  optparse::make_option("--blocks", default = NULL,
    help = "block table; defaults to the config's forward$blocks"),
  optparse::make_option("--workspace", default = NULL,
    help = "run workspace; defaults to the config's forward$workspace"),
  optparse::make_option("--obs", default = NULL,
    help = "cached obs.rds; every fitted treatment must have a block")
) |>
  purrr::modify(\(x) { x@help <- paste(x@help, "[default: %default]"); x })

args <- optparse::OptionParser(option_list = options) |> optparse::parse_args()
config <- config::get(file = args$config)

blocks_file <- args$blocks %||% config$forward$blocks
workspace <- args$workspace %||% config$forward$workspace
obs_file <- args$obs %||% file.path(config$cache_dir, "obs.rds")

# papply is chatty at DEBUG and drowns the real messages
PEcAn.logger::logger.setLevel("INFO")

# absolute paths for everything the model reads or writes: PEcAn's restart code
# changes working directory, so a relative input silently resolves somewhere
# else. the one exception is host$modellauncher$binary, which stays
# ./scripts/sge_array_launcher.sh and resolves because qsub runs with -cwd from
# the workspace.
abs_path <- function(path) {
  if (substr(path, 1, 1) != "/") path <- file.path(getwd(), path)
  normalizePath(path, mustWork = FALSE)
}
workspace <- abs_path(workspace)
# prepared inputs are shared across runs, so a second workspace can point
# prepared_root at an existing one rather than duplicating them.
prepared_root <- abs_path(config$forward$prepared_root %||% workspace)

blocks <- utils::read.csv(blocks_file, stringsAsFactors = FALSE)
required <- c("block_id", "lat", "lon", "veg_pft", "soil_pft",
              "run_start", "run_end", "met_src", "ic_src", "events_src")
missing_cols <- setdiff(required, names(blocks))
if (length(missing_cols) > 0L) {
  PEcAn.logger::logger.severe("blocks table is missing: ",
                              paste(missing_cols, collapse = ", "))
}
if (anyDuplicated(blocks$block_id) > 0L) {
  PEcAn.logger::logger.severe(
    "block_id must be unique; it becomes site$id and the observation operator ",
    "matches a treatment's output on it. Duplicated: ",
    paste(unique(blocks$block_id[duplicated(blocks$block_id)]), collapse = ", ")
  )
}

obs <- readRDS(obs_file)
fitted <- unique(obs$meta$treatment_id)
orphans <- setdiff(fitted, blocks$block_id)
if (length(orphans) > 0L) {
  PEcAn.logger::logger.severe(
    length(orphans), " fitted treatment(s) have no run block: ",
    paste(orphans, collapse = ", "), ". block_id must equal treatment_id."
  )
}
idle <- setdiff(blocks$block_id, fitted)
if (length(idle) > 0L) {
  PEcAn.logger::logger.warn(
    length(idle), " block(s) carry no fitted slot: ", paste(idle, collapse = ", ")
  )
}

# createMultiSiteSettings copies every non-id column of this frame into run$site,
# so anything the per block fixups need is carried here rather than looked up again.
site_info <- data.frame(
  id = blocks$block_id,
  lat = blocks$lat,
  lon = blocks$lon,
  name = blocks$block_id,
  veg_pft = blocks$veg_pft,
  soil_pft = blocks$soil_pft,
  block_start = blocks$run_start,
  block_end = blocks$run_end,
  met_src = blocks$met_src,
  ic_src = blocks$ic_src,
  events_src = blocks$events_src,
  stringsAsFactors = FALSE
)

settings <- read.settings(config$forward$template)

## pinned parameters -----------------------------------------------------------
# write.config.SIPNET reads default.param and then overwrites it row by row from
# the PFT trait samples, so pinning a parameter takes both halves: the value here
# and the trait dropped from the baseline sample (make_forward_sipnet's
# fixed_traits). one half alone silently loses to the PFT posterior.
default_param <- file.path(workspace, "sipnet.default.param")
# same version mapping write.config.SIPNET applies, so the pinned file is built
# from the template that run would otherwise have read
rev_num <- numeric_version(sub("^v", "", settings$model$revision, ignore.case = TRUE),
                           strict = FALSE)
if (is.na(rev_num)) {
  PEcAn.logger::logger.severe("cannot parse model revision '",
                              settings$model$revision, "' as a version")
}
rev_str <- if (rev_num >= "2.0") "v2" else "v1"
stock_template <- system.file(paste0("template.param_", rev_str), package = "PEcAn.SIPNET")
if (!nzchar(stock_template)) {
  PEcAn.logger::logger.severe("no stock template.param_", rev_str,
                              " for revision ", settings$model$revision)
}
param <- utils::read.table(stock_template, stringsAsFactors = FALSE)
for (nm in names(config$fixed_params)) {
  sipnet_name <- config$fixed_params[[nm]]$sipnet
  value <- config$fixed_params[[nm]]$value
  hit <- param[[1]] == sipnet_name
  if (!any(hit)) {
    PEcAn.logger::logger.severe("no '", sipnet_name, "' row in ", stock_template)
  }
  param[hit, 2] <- value
  PEcAn.logger::logger.info("pinned ", sipnet_name, " = ", value, " (", nm, ")")
}
dir.create(workspace, recursive = TRUE, showWarnings = FALSE)
# provision the workspace the launcher convention expects: modellauncher$binary is
# ./scripts/sge_array_launcher.sh relative to the workspace (see abs_path note above),
# and a workspace without it submits array jobs that die before the model runs.
launcher_src <- file.path(prepared_root, "scripts", "sge_array_launcher.sh")
launcher_dir <- file.path(workspace, "scripts")
if (!file.exists(file.path(launcher_dir, "sge_array_launcher.sh"))) {
  if (!file.exists(launcher_src)) {
    PEcAn.logger::logger.severe("no launcher at ", launcher_src,
                                "; the workspace cannot submit array jobs without it")
  }
  dir.create(launcher_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(launcher_src, launcher_dir)
  Sys.chmod(file.path(launcher_dir, "sge_array_launcher.sh"), "0755")
  PEcAn.logger::logger.info("provisioned ", launcher_dir, "/sge_array_launcher.sh")
}
utils::write.table(param, default_param, quote = FALSE, sep = "\t",
                   row.names = FALSE, col.names = FALSE)
settings$model$default.param <- default_param
settings$model$binary <- abs_path(config$forward$binary)

for (i in seq_along(settings$pfts)) {
  settings$pfts[[i]]$posterior.files <- abs_path(settings$pfts[[i]]$posterior.files)
  if (!is.null(settings$pfts[[i]]$outdir)) {
    settings$pfts[[i]]$outdir <- abs_path(settings$pfts[[i]]$outdir)
  }
}

## per block fixups ------------------------------------------------------------
# the blocks table declares the exact met, template ic, and events file per
# block, relative to the staging trees; the calibration pins each input to that
# one member, so no ic/met/events spread crosses the particles. a calibrated
# initial state overrides its pool per particle in the forward; a block without
# one runs the template ic as-is.
input_file <- function(root, rel, what, id) {
  f <- file.path(root, rel)
  if (!file.exists(f)) {
    PEcAn.logger::logger.severe("block ", id, " ", what, " not found: ", f)
  }
  f
}

set_block <- function(s) {
  site <- s$run$site
  # getRunSettings puts the dates inside run, alongside site and inputs
  s$run$start.date <- site$block_start
  s$run$end.date <- site$block_end
  s$run$site$met.start <- site$block_start
  s$run$site$met.end <- site$block_end
  s$run$site$site.pft <- list(veg = site$veg_pft, soil = site$soil_pft)
  s
}

set_inputs <- function(s) {
  site <- s$run$site
  s$run$inputs$met$path <- list(path1 = input_file(
    file.path(config$forward$sa_root, "inputs", "met"), site$met_src, "met", site$id))
  s$run$inputs$poolinitcond$path <- list(path1 = input_file(
    file.path(config$forward$sa_root, "inputs", "IC"), site$ic_src, "ic", site$id))
  s$run$inputs$poolinitcond$ensemble <- 1
  s$run$inputs$events$path <- list(path1 = input_file(
    file.path(prepared_root, "inputs"), site$events_src, "events", site$id))
  s
}

settings <- settings |>
  createMultiSiteSettings(site_info) |>
  papply(set_block) |>
  papply(set_inputs)

settings$ensemble$size <- config$eki$n_particles
settings$ensemble$start.year <- as.integer(format(as.Date(min(blocks$run_start)), "%Y"))
settings$ensemble$end.year <- as.integer(format(as.Date(max(blocks$run_end)), "%Y"))

out_dir <- file.path(workspace, "output")
settings$outdir <- out_dir
settings$modeloutdir <- file.path(out_dir, "out")
settings$rundir <- file.path(out_dir, "run")
settings$host$outdir <- file.path(out_dir, "out")
settings$host$rundir <- file.path(out_dir, "run")

out_file <- file.path(workspace, "settings.xml")
write.settings(settings, outputfile = basename(out_file), outputdir = dirname(out_file))
PEcAn.logger::logger.info("wrote ", out_file, ": ", nrow(blocks), " blocks, ",
                          "default.param ", default_param)
