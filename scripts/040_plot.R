#!/usr/bin/env Rscript
# plot and score the calibration result.
#
# figures go to the run workspace, not the repo: they are run artifacts and belong
# beside the result they were made from. nothing here writes a caption -- the
# figure carries labs(x, y) only and the story goes in the writeup.

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]"),
  optparse::make_option("--result", default = NULL,
    help = "result.rds; defaults to the config cache [default: %default]"),
  optparse::make_option("--figdir", default = NULL,
    help = "output directory [default: <workspace>/figures]")
)))
config <- config::get(file = args$config)

result_file <- args$result %||% file.path(config$cache_dir, "result.rds")
figdir <- args$figdir %||% file.path(
  config$forward$workspace %||% file.path(config$scc, config$forward$run_dir),
  "figures"
)
result <- readRDS(result_file)
dir.create(figdir, showWarnings = FALSE, recursive = TRUE)

# the tempered forwards, prior through posterior
G_list <- c(lapply(result$eki$eki_list, function(s) s$G), list(result$eki$G))
names(G_list) <- paste("iteration", seq_along(G_list))

# ensembles against observations, one page per iteration, site, and variable:
# a page shares one axis, so it holds one unit.
meta <- result$obs$meta
groups <- unique(meta[c("sitename", "variable")])
grDevices::pdf(file.path(figdir, "ensembles_vs_truth.pdf"), width = 9, height = 7)
for (nm in names(G_list)) {
  for (g in seq_len(nrow(groups))) {
    sm <- meta[meta$sitename == groups$sitename[g] &
                 meta$variable == groups$variable[g], , drop = FALSE]
    plot_fn <- if (all(is.na(sm$obs_year))) plot_target_slots else plot_ensembles_vs_truth
    print(plot_fn(
      G_list[[nm]][, sm$slot, drop = FALSE], sm,
      ylab = unique(sm$units),
      title = paste(groups$sitename[g], groups$variable[g], nm)
    ))
  }
}
grDevices::dev.off()

plot_param_densities(list(prior = result$U0, posterior = result$U),
                     file.path(figdir, "param_prior_posterior.pdf"))
readr::write_csv(param_shift(result$U0, result$U),
                 file.path(figdir, "param_shift.csv"))

# parameter trace: does a parameter settle inside its support, or move onto a bound,
# and does it walk there or jump. eki_list holds the update in unconstrained space,
# so it is mapped back before plotting.
pm <- result$eki$par_map
trace <- c(list(result$U0), lapply(result$eki$eki_list, function(s) pm$inv(s$U)))
prior <- readRDS(file.path(config$cache_dir, "prior.rds"))
ggplot2::ggsave(file.path(figdir, "param_trace.png"),
                plot_param_trace(trace, prior),
                width = 8, height = 3.5, dpi = 300)

# measured against modeled treatment effect, before and after calibration
fe <- config$figures$treatment_effect
if (!is.null(fe)) {
  if (is.null(result$G_raw_prior)) {
    PEcAn.logger::logger.info("skipping treatment effect figure: this result ",
                              "carries no raw harvests")
  } else {
    ggplot2::ggsave(file.path(figdir, "treatment_effect.png"),
                    plot_treatment_effect(result$G_raw_prior, result$G_raw_post,
                                          result$raw_meta, variable = fe$variable,
                                          treatment = fe$treatment, control = fe$control),
                    width = 9, height = 4, dpi = 300)
  }
}

# score_iteration already splits by variable, so this is iteration x variable: a
# target that degrades while another improves stays visible rather than averaged away
scores <- score_table(G_list, meta)
readr::write_csv(scores, file.path(figdir, "scores.csv"))

# held-out validation, when the config keeps variables out of the likelihood
val_vars <- as.character(config$validation_variables)
if (length(val_vars) > 0L) {
  if (is.null(result$G_validation)) {
    PEcAn.logger::logger.info("skipping validation figure: this result carries ",
                              "no validation predictions")
  } else {
    vm <- result$obs_all$meta
    vm <- vm[vm$variable %in% val_vars, , drop = FALSE]
    ggplot2::ggsave(file.path(figdir, "validation_predicted_vs_observed.png"),
                    plot_validation(result$G_validation, vm),
                    width = 8, height = 4, dpi = 300)
    readr::write_csv(score_iteration(result$G_validation, vm),
                     file.path(figdir, "scores_validation.csv"))
  }
}

PEcAn.logger::logger.info("wrote ", figdir)
