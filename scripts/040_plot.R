#!/usr/bin/env Rscript
# plot and score the calibration result

library(calibration)

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)

result <- readRDS(file.path(config$cache_dir, "result.rds"))
dir.create("figures", showWarnings = FALSE, recursive = TRUE)

# per iteration prediction matrices, the tempered forwards through the posterior
G_list <- c(lapply(result$eki$eki_list, function(s) s$G), list(result$eki$G))
names(G_list) <- paste("iteration", seq_along(G_list))

save_iterations_pdf(G_list, result$obs$meta,
                    file.path("figures", "ensembles_vs_truth.pdf"),
                    ylab = config$observations$target_var)

plot_param_densities(list(prior = result$U0, posterior = result$U),
                     file.path("figures", "param_prior_posterior.pdf"))

scores <- score_table(G_list, result$obs$meta)
readr::write_csv(scores, file.path("figures", "scores.csv"))
PEcAn.logger::logger.info("wrote figures/ (ensembles_vs_truth, param_prior_posterior, scores)")
