#!/usr/bin/env Rscript
# run the calibration and save the result. launching is left to pecan and
# the prepared host block (see forward_sipnet.R); nothing here touches it.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]"),
  optparse::make_option("--dry-run", action = "store_true", default = FALSE,
    help = "one iteration, result written to --out [default: %default]"),
  optparse::make_option("--particles", type = "integer", default = NULL,
    help = "override ensemble size [default: config]"),
  optparse::make_option("--iterations", type = "integer", default = NULL,
    help = "override tempering steps [default: config]"),
  optparse::make_option("--out", default = NULL,
    help = "output root; defaults to the settings outdir [default: %default]")
)))
config <- config::get(file = args$config)

options(warn = 1)

# when the config declares a target transform, 012 has written the fitted quantity
# to target.rds and that is what gets calibrated. obs.rds is the raw cache 012
# reads from, so fitting it would silently calibrate the raw per-treatment cells
# instead of the contractions the transform produced. a missing target.rds means
# 012 has not been run against this config.
target_file <- file.path(config$cache_dir, "target.rds")
if (!is.null(config$target)) {
  if (!file.exists(target_file)) {
    PEcAn.logger::logger.severe(
      "config declares a target transform but ", target_file, " does not exist; ",
      "run 012_build_target.R against this config first"
    )
  }
  obs <- readRDS(target_file)
  # the model is harvested on the raw slots and put through the same transform
  raw_obs <- readRDS(file.path(config$cache_dir, "obs.rds"))
  raw_obs$transform <- obs$transform
  PEcAn.logger::logger.info("fitting the transformed target: ", nrow(obs$meta), " slots (",
                            paste(unique(obs$meta$variable), collapse = ", "), ")")
} else {
  obs <- readRDS(file.path(config$cache_dir, "obs.rds"))
  raw_obs <- NULL
}
prior <- readRDS(file.path(config$cache_dir, "prior.rds"))

# drop each site's establishment years: config$fit maps sitename -> the first
# observation year to fit, so the pre-fit years stay the initial condition (the state
# prior in 020 anchors there) but are not fitted. study-year scales differ across
# sites, so the rule is per site; a site absent from config$fit fits every year.
unknown <- setdiff(names(config$fit), obs$meta$sitename)
if (length(unknown) > 0L) {
  PEcAn.logger::logger.severe("config$fit names site(s) with no slots: ",
                              paste(unknown, collapse = ", "))
}
keep <- rep(TRUE, nrow(obs$meta))
for (site in names(config$fit)) {
  keep <- keep & !(obs$meta$sitename == site & obs$meta$obs_year < config$fit[[site]])
}
obs <- subset_obs(obs, keep)
PEcAn.logger::logger.info(length(obs$y), " slots after per-site establishment drop")

# variables held out of the likelihood but still predicted and reported. a target
# the model cannot reach cannot be calibrated through: the estimator answers by
# pushing a parameter to its bound for reasons unrelated to the process it stands
# for. held out, the variable is still simulated and scored.
obs_all <- obs
val_vars <- config$validation_variables
if (!is.null(val_vars)) {
  is_val <- obs$meta$variable %in% as.character(val_vars)
  if (!any(is_val)) {
    PEcAn.logger::logger.severe(
      "validation_variables match no observation: ", paste(val_vars, collapse = ", ")
    )
  }
  obs <- subset_obs(obs_all, !is_val)
  PEcAn.logger::logger.info(
    "fitting ", length(obs$y), " slots; holding ", sum(is_val),
    " out as validation (", paste(unique(obs_all$meta$variable[is_val]), collapse = ", "), ")"
  )
}

settings_file <- file.path(
  config$forward$workspace %||% file.path(config$scc, config$forward$run_dir),
  "settings.xml"
)
settings <- PEcAn.settings::read.settings(settings_file)

n_particles <- args$particles %||% config$eki$n_particles
n_iterations <- args$iterations %||% (if (args$`dry-run`) 1L else config$eki$n_iterations)
base_out_dir <- args$out %||% settings$outdir

forward <- make_forward_sipnet(
  settings = settings, obs = obs, n_particles = n_particles,
  var_map = config$forward$var_map,
  soil_pfts = as.character(config$soil_pft),
  state_prefix = config$priors$state$prefix %||% "soilInit.",
  state_pool = config$forward$state_pool,
  fixed_traits = names(config$fixed_params),
  base_out_dir = base_out_dir,
  raw_obs = raw_obs
)

control <- calibration_control(
  method = "eki", n_particles = n_particles,
  n_iterations = n_iterations, seed = config$eki$seed
)

result <- calibrate(obs, prior, forward, control)
result$obs_all <- obs_all

# validation and figure predictions cost no extra model runs: itr1 holds the
# prior forward and itr(n + 1) the posterior forward, both already on disk.
window <- run_window(settings)
val_meta <- if (is.null(raw_obs)) obs_all$meta else raw_obs$meta
itr_dir <- function(k) file.path(base_out_dir, paste0("itr", k), "out")
result$raw_meta <- val_meta
result$G_raw_prior <- harvest_output_to_G(itr_dir(1L), val_meta,
                                          config$forward$var_map, window)
result$G_raw_post <- harvest_output_to_G(itr_dir(n_iterations + 1L), val_meta,
                                         config$forward$var_map, window)
result$G_validation <- if (is.null(obs_all$transform)) result$G_raw_post else
  apply_transform(result$G_raw_post, obs_all$transform)

out <- file.path(if (args$`dry-run`) base_out_dir else config$cache_dir, "result.rds")
saveRDS(result, out)
PEcAn.logger::logger.info("cached result -> ", out)
