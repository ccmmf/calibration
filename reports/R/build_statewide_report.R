# Run from the repository root: Rscript reports/R/build_statewide_report.R
# The report uses archived estimates; no model execution or rescoring occurs here.
input <- "reports/data/statewide"
out <- "reports/generated"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
manifest <- jsonlite::fromJSON(file.path(input, "manifest.json"))
for (i in seq_len(nrow(manifest$files))) {
  record <- manifest$files[i, ]
  stopifnot(identical(digest::digest(file = file.path(input, record$file),
                                   algo = "sha256"), record$sha256))
}
read_csv <- function(name) utils::read.csv(file.path(input, name),
                                          stringsAsFactors = FALSE,
                                          check.names = FALSE)
score <- read_csv("original_scorecard.csv")
effects <- read_csv("site_pair_effects.csv")
annual <- read_csv("annual_outputs.csv")
stopifnot(!anyDuplicated(score$pair_id),
          !anyDuplicated(effects[c("site_id", "treatment", "reference")]),
          !anyDuplicated(annual[c("site", "arm", "year")]))

labels <- c(cover_soc = "Cover crop / no cover crop",
  till_reduced_soc = "Reduced / conventional tillage",
  till_zero_soc = "No tillage / conventional tillage",
  org_sub = "Organic substitution / fertilizer baseline",
  rice_one_ch4 = "One irrigation interruption / flooded baseline",
  rice_two_ch4 = "Two interruptions / flooded baseline",
  till_zero_n2o = "No tillage: modeled N2O-N",
  rice_one_n2o = "One interruption: modeled N2O-N",
  rice_two_n2o = "Two interruptions: modeled N2O-N",
  minN_dEFdN_N_fixing_crops = "Fertilizer response: N-fixing crops",
  minN_dEFdN_non_N_fixing_crops = "Fertilizer response: other crops",
  minN_EF_level = "Fertilizer-induced N2O-N / N applied")
main_ids <- names(labels)[seq_len(6)]
retained <- score[match(names(labels), score$pair_id), ]
stopifnot(!anyNA(retained$pair_id))
retained$comparison <- unname(labels[retained$pair_id])
retained$is_ratio <- grepl("lrr", retained$metric)
retained$display_model <- ifelse(retained$is_ratio, exp(retained$model_effect),
                                 retained$model_effect)
retained$display_evidence <- ifelse(retained$is_ratio, exp(retained$target_center),
                                    retained$target_center)
retained$display_units <- ifelse(retained$is_ratio, "Response ratio",
                                  retained$target_units)
retained$display_units[retained$pair_id == "cover_soc"] <- "Mg soil + litter C/ha/cover year"
retained$display_units[retained$pair_id %in% c("till_reduced_soc", "till_zero_soc")] <-
  "Mg soil + litter C/ha/simulation year"
utils::write.csv(retained, file.path(out, "display_values.csv"), row.names = FALSE)

fmt <- function(x) ifelse(is.na(x), "—", formatC(x, format = "g", digits = 2))
fmt_ratio <- function(x) {
  ifelse(is.na(x), "—", formatC(x, format = "g", digits = 2, flag = "#"))
}
write_table <- function(x, name) {
  writeLines(as.character(knitr::kable(x, format = "pipe", row.names = FALSE)),
             file.path(out, name))
}
values <- data.frame(Comparison = retained$comparison,
  Quantity = retained$display_units,
  Model = ifelse(retained$is_ratio, fmt_ratio(retained$display_model),
                   fmt(retained$display_model)), Literature = fmt(retained$display_evidence),
  check.names = FALSE)
write_table(values[seq_len(6), ], "effects_table.md")
write_table(values[-seq_len(6), ], "proxy_table.md")

# Preserve archived site populations and reproduce only their archived estimators.
for (id in main_ids) {
  s <- score[score$pair_id == id, ]
  x <- effects[effects$treatment == s$treatment &
                 effects$reference == s$reference & effects$pair_ok, s$metric]
  x <- x[is.finite(x)]
  stopifnot(length(x) == s$model_n_sites,
            isTRUE(all.equal(mean(x), s$model_effect, tolerance = 1e-10)))
}

panel_names <- c("Carbon difference / reported denominator (Mg C/ha/year)",
                 "Soil carbon response ratio", "Seasonal methane response ratio")
main <- retained[seq_len(6), ]
main$panel <- factor(rep(panel_names, c(3, 1, 2)), levels = panel_names)
main$label <- main$comparison
main$label[1] <- "Cover crop / no cover crop; per cover year"
main$label <- vapply(main$label, function(x) paste(strwrap(x, width = 43), collapse = "\n"), character(1))
main$label <- factor(main$label, levels = rev(main$label))
# Literature bars retain their distinct meanings: SD or approximate 95% CI.
main$half_width <- ifelse(main$target_spread_type == "sd", main$target_spread,
                           1.96 * main$target_spread)
main$lower <- ifelse(main$is_ratio, exp(main$target_center - main$half_width),
                     main$target_center - main$half_width)
main$upper <- ifelse(main$is_ratio, exp(main$target_center + main$half_width),
                     main$target_center + main$half_width)
reference <- data.frame(panel = factor(panel_names, levels = panel_names),
                        null = c(0, 1, 1))
plot_theme <- ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_blank(),
    strip.text.y = ggplot2::element_text(angle = 0),
    strip.text = ggplot2::element_text(face = "bold", hjust = 0),
    legend.position = "top", plot.margin = ggplot2::margin(10, 16, 10, 8))
p <- ggplot2::ggplot(main, ggplot2::aes(y = label)) +
  ggplot2::geom_vline(data = reference, ggplot2::aes(xintercept = null),
                      colour = "grey60", linetype = 2) +
  ggplot2::geom_errorbar(ggplot2::aes(xmin = lower, xmax = upper),
                        orientation = "y", width = 0.12, colour = "#D55E00",
                        position = ggplot2::position_nudge(y = -0.12)) +
  ggplot2::geom_point(ggplot2::aes(x = display_evidence, colour = "Literature", shape = "Literature"),
                     size = 3, position = ggplot2::position_nudge(y = -0.12)) +
  ggplot2::geom_point(ggplot2::aes(x = display_model, colour = "Model", shape = "Model"),
                     size = 3, position = ggplot2::position_nudge(y = 0.12)) +
  ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free") +
  ggplot2::scale_colour_manual(values = c(Model = "#0072B2", Literature = "#D55E00")) +
  ggplot2::scale_shape_manual(values = c(Model = 16, Literature = 18)) +
  ggplot2::labs(x = NULL, y = NULL, colour = NULL, shape = NULL) + plot_theme
ggplot2::ggsave(file.path(out, "effects.png"), p, width = 10, height = 8.5, dpi = 180, bg = "white")

points <- do.call(rbind, lapply(seq_len(nrow(main)), function(i) {
  m <- main[i, ]
  x <- effects[effects$treatment == m$treatment &
                 effects$reference == m$reference & effects$pair_ok, ]
  x <- x[is.finite(x[[m$metric]]), ]
  data.frame(site_id = x$site_id, panel = m$panel, label = m$label,
    value = if (m$is_ratio) 100 * expm1(x[[m$metric]]) else x[[m$metric]])
}))
points$panel <- factor(points$panel, levels = panel_names,
  labels = c(panel_names[1], "Soil carbon change (%)", "Seasonal methane change (%)"))
points$label <- factor(points$label, levels = levels(main$label))
medians <- stats::aggregate(value ~ panel + label, points, stats::median)
p <- ggplot2::ggplot(points, ggplot2::aes(x = value, y = label)) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linetype = 2) +
  ggplot2::geom_point(position = ggplot2::position_jitter(width = 0, height = 0.15, seed = 41),
                     size = 1.8, alpha = 0.65, colour = "#0072B2") +
  ggplot2::geom_point(data = medians, shape = 18, size = 4, colour = "black") +
  ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free") +
  ggplot2::labs(x = NULL, y = NULL) + plot_theme
ggplot2::ggsave(file.path(out, "locations-v4.png"), p, width = 10, height = 8.5, dpi = 180, bg = "white")
utils::write.csv(points, file.path(out, "location_display_values.csv"), row.names = FALSE)

# Endpoint trajectories use the same pairs; no rate denominator is introduced.
trajectories <- do.call(rbind, lapply(c("cover_soc", "rice_one_ch4", "rice_two_ch4"), function(id) {
  s <- score[score$pair_id == id, ]
  valid <- effects[effects$treatment == s$treatment & effects$reference == s$reference & effects$pair_ok, ]
  a <- annual[annual$arm == s$treatment & annual$site %in% valid$site_id, ]
  b <- annual[annual$arm == s$reference & annual$site %in% valid$site_id, ]
  z <- merge(a, b, by = c("site", "year"), suffixes = c("_practice", "_baseline"))
  is_cover <- id == "cover_soc"
  data.frame(site = z$site, year = z$year,
    panel = if (is_cover) "Cover crop: soil + litter C difference (Mg C/ha)" else
      paste0(if (id == "rice_one_ch4") "One interruption" else "Two interruptions", ": annual CH4 difference (kg C/ha)"),
    value = if (is_cover) z$soc_last_practice - z$soc_last_baseline else
      10000 * (z$ch4_sum_practice - z$ch4_sum_baseline))
}))
median_time <- stats::aggregate(value ~ panel + year, trajectories, stats::median)
p <- ggplot2::ggplot(trajectories, ggplot2::aes(year, value, group = site)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey70", linetype = 2) +
  ggplot2::geom_line(colour = "#0072B2", alpha = 0.3, linewidth = 0.4) +
  ggplot2::geom_line(data = median_time, ggplot2::aes(group = 1), colour = "black", linewidth = 0.8) +
  ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(2016, 2023)) +
  ggplot2::labs(x = NULL, y = NULL) + plot_theme
ggplot2::ggsave(file.path(out, "trajectories.png"), p, width = 10, height = 8, dpi = 180, bg = "white")
writeLines(c("Archived estimators reproduced for all six main comparisons.",
             "All finite location effects retained; no axis limits or trimming.",
             capture.output(utils::sessionInfo())), file.path(out, "verification.txt"))
