# Export the final calibrated process ensemble; experimental initial states stay local.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2)
fit <- readRDS(args[1])
parameters <- c("turn_over_time", "som_respiration_rate", "fracLitterRespired")
ensemble <- fit$U[, parameters, drop = FALSE]
stopifnot(nrow(ensemble) == 50L, all(is.finite(ensemble)),
  isTRUE(all.equal(unname(colMeans(ensemble)),
    c(0.93109317, 0.07161284, 0.92814278), tolerance = 1e-7)))
utils::write.csv(data.frame(member_id = seq_len(nrow(ensemble)), ensemble),
                 args[2], row.names = FALSE)
writeLines(c(paste("source:", normalizePath(args[1])),
  paste("source_md5:", unname(tools::md5sum(args[1]))),
  "Only the three shared process parameters are exported; soilInit.socs_sys1-8 are excluded.",
  capture.output(fit$control), capture.output(utils::sessionInfo())),
  paste0(args[2], ".provenance.txt"))
