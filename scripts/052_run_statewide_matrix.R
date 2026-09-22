#!/usr/bin/env Rscript
# run the statewide treatment-effect matrix through the PEcAn workflow: write
# configs at the pft trait medians, submit the runs, and convert the raw model
# output. resumable through the workflow STATUS file.

library(PEcAn.all)
library(PEcAn.logger)
library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]"),
  optparse::make_option("--continue", action = "store_true", default = FALSE,
    help = "resume an interrupted run [default: %default]")
)))
config <- config::get(file = args$config)
workspace <- config$workspace

options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  if (!interactive()) q(status = 1)
}))

# these settings are database free, so prepare.settings is not run: its
# check.settings half needs a bety connection, and its site-to-pft linkage is
# already done at build time
settings <- PEcAn.settings::read.settings(file.path(workspace, "settings.xml"))

status_file <- file.path(settings$outdir, "STATUS")
if (!args$continue && file.exists(status_file)) file.remove(status_file)
dir.create(settings$outdir, recursive = TRUE, showWarnings = FALSE)

# status.check returns -1 for a stage that ended in ERROR. the stage gates
# below only test for "not yet done", so without this a resumed run would step
# straight over a failure and build on incomplete state
for (stage in c("CONFIG", "MODEL", "OUTPUT")) {
  if (PEcAn.utils::status.check(stage) == -1L) {
    logger.severe(stage, " previously failed; resolve before continuing")
  }
}

# the matrix is a deterministic run at the trait medians, so the one ensemble
# member carries the median of each pft posterior rather than a draw. traits
# pinned in default.param are dropped here, otherwise the posterior overwrites
# them when write.config.SIPNET applies the sample.
medians <- baseline_trait_samples(settings$pfts, 1, names(config$fixed_params))
input_design <- list(
  design_matrix = data.frame(param = 1L, poolinitcond = 1L, met = 1L, events = 1L),
  samples = list(
    ensemble.samples = medians,
    trait.samples = lapply(medians, as.list),
    sa.samples = NULL, runs.samples = list(), env.samples = list()
  )
)

# host$modellauncher$binary is relative to the run directory and qsub runs with
# -cwd, so configuring and launching happen from the workspace
old_wd <- setwd(workspace)
on.exit(setwd(old_wd), add = TRUE)

if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- PEcAn.workflow::runModule.run.write.configs(
    settings, input_design = input_design)
  # write.config.SIPNET takes soilInit from each site's initial conditions but
  # never sets soilOrgNInit, so the soil C:N is applied to the written configs
  couple_soil_orgn(settings$rundir, config$parameterization$soil_cn)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml"))
}

if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = FALSE)
  PEcAn.utils::status.end()
}

if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}

logger.info("statewide matrix complete: ", length(settings), " runs under ",
            settings$modeloutdir)
