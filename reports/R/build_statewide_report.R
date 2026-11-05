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
  org_sub = "Organic amendments / mineral fertilizer baseline",
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
retained$display_units[retained$pair_id == "cover_soc"] <- "Mg C/ha/cover year"
retained$display_units[retained$pair_id %in% c("till_reduced_soc", "till_zero_soc")] <-
  "Mg C/ha/simulation year"
# Bai et al. (2023) replaced the olive-orchard target; correct the derived note, not the archive.
retained$structural_flags <- sub("target is Mediterranean olive-orchard amendment (partial comparability)",
  "target is the Bai et al. (2023) global synthesis of amended against unamended soil",
  retained$structural_flags, fixed = TRUE)
utils::write.csv(retained, file.path(out, "display_values.csv"), row.names = FALSE)

fmt <- function(x) ifelse(is.na(x), "—", formatC(x, format = "g", digits = 2))
fmt_ratio <- function(x) {
  ifelse(is.na(x), "—", formatC(x, format = "g", digits = 2, flag = "#"))
}
write_table <- function(x, name) {
  writeLines(as.character(knitr::kable(x, format = "pipe", row.names = FALSE)),
             file.path(out, name))
}
# Whether each pair can be judged yet (organization#288): comparable, qualified or blocked.
status <- utils::read.csv("reports/data/comparison_status.csv", stringsAsFactors = FALSE)
stopifnot(!anyDuplicated(status$pair_id), setequal(status$pair_id, names(labels)),
          all(status$status %in% c("comparable", "qualified", "blocked")),
          all(nzchar(status$reason)), all(nzchar(status$follow_up)))
status <- status[match(retained$pair_id, status$pair_id), ]
# The status text quotes these; stop if the frozen results no longer support them.
pair_values <- function(id, metric) {
  s <- score[score$pair_id == id, ]
  x <- effects[effects$treatment == s$treatment &
                 effects$reference == s$reference & effects$pair_ok, metric]
  x[is.finite(x)]
}
stopifnot(score$model_n_sites[score$pair_id == "cover_soc"] == 65,
          all(abs(pair_values("rice_one_ch4", "lrr_ch4_season")) < log(1.002)),
          all(abs(pair_values("rice_two_ch4", "lrr_ch4_season")) < log(1.002)),
          length(pair_values("till_zero_n2o", "lrr_n2o_till")) == 99,
          all(pair_values("till_zero_n2o", "lrr_n2o_till") < 0))
values <- data.frame(Comparison = retained$comparison,
  Quantity = retained$display_units,
  Model = ifelse(retained$is_ratio, fmt_ratio(retained$display_model),
                   fmt(retained$display_model)), Literature = fmt(retained$display_evidence),
  Status = status$status, check.names = FALSE)
write_table(values[seq_len(6), ], "effects_table.md")
write_table(values[-seq_len(6), ], "proxy_table.md")
write_table(data.frame(Comparison = retained$comparison, Status = status$status,
                       Why = status$reason, `Next step` = status$follow_up,
                       check.names = FALSE), "status_table.md")

# Preserve archived site populations and reproduce only their archived estimators.
for (id in main_ids) {
  s <- score[score$pair_id == id, ]
  x <- effects[effects$treatment == s$treatment &
                 effects$reference == s$reference & effects$pair_ok, s$metric]
  x <- x[is.finite(x)]
  stopifnot(length(x) == s$model_n_sites,
            isTRUE(all.equal(mean(x), s$model_effect, tolerance = 1e-10)))
}

# Carbon pool check (organization#288). Each archived carbon effect is the end-of-window
# treatment minus baseline difference in soil + litter carbon, divided by the prepared cover
# years or the simulation years. soil_last gives the same quantity for soil carbon alone.
end_c <- annual[annual$year == max(annual$year), ]
n_years <- length(unique(annual$year))
carbon_ids <- c("cover_soc", "till_reduced_soc", "till_zero_soc")
pools <- do.call(rbind, lapply(carbon_ids, function(id) {
  s <- score[score$pair_id == id, ]
  x <- effects[effects$treatment == s$treatment &
                 effects$reference == s$reference & effects$pair_ok, ]
  x <- x[is.finite(x[[s$metric]]), ]
  at_end <- function(arm, pool) {
    end_c[[pool]][match(paste(x$site_id, arm), paste(end_c$site, end_c$arm))]
  }
  years <- if (s$metric == "dd_soc_per_cover_yr") x$n_cover_years else n_years
  total <- (at_end(s$treatment, "soc_last") - at_end(s$reference, "soc_last")) / years
  soil <- (at_end(s$treatment, "soil_last") - at_end(s$reference, "soil_last")) / years
  stopifnot(isTRUE(all.equal(total, x[[s$metric]], tolerance = 1e-10)))
  data.frame(pair_id = id, n = nrow(x), total_mean = mean(total), soil_mean = mean(soil),
             soil_median = stats::median(soil),
             top5_share = sum(sort(soil, decreasing = TRUE)[1:5]) / sum(soil))
}))
pools <- merge(pools, retained[c("pair_id", "comparison", "display_evidence")], sort = FALSE)
utils::write.csv(pools, file.path(out, "carbon_pools.csv"), row.names = FALSE)
write_table(data.frame(Comparison = pools$comparison, Locations = pools$n,
  `Soil + litter, mean` = fmt(pools$total_mean), `Soil only, mean` = fmt(pools$soil_mean),
  `Soil only, median` = fmt(pools$soil_median),
  `Top 5 locations, share of total` = sprintf("%.0f%%", 100 * pools$top5_share),
  Literature = fmt(pools$display_evidence), check.names = FALSE), "carbon_pools_table.md")

panel_names <- c("Carbon difference (Mg C/ha per reported year)",
                 "Soil carbon response ratio", "Seasonal methane response ratio")
main <- retained[seq_len(6), ]
main$panel <- factor(rep(panel_names, c(3, 1, 2)), levels = panel_names)
main$label <- c("Cover crop; per cover year", "Reduced tillage", "No tillage",
                "Organic amendments", "One irrigation interruption",
                "Two irrigation interruptions")
# The status goes on the axis label only, so the CSVs keep one-line labels.
status_label <- stats::setNames(status$status[seq_len(6)], main$label)
with_status <- function(x) paste0(x, "\n(", status_label[x], ")")
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
# Panel names stay on one line in the CSVs; the break before the units is added only when drawing.
wrap_panel <- ggplot2::as_labeller(function(x) sub(" (Mg", "\n(Mg", x, fixed = TRUE))
plot_theme <- ggplot2::theme_minimal(base_size = 16) +
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
  ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free", labeller = wrap_panel) +
  ggplot2::scale_colour_manual(values = c(Model = "#0072B2", Literature = "#D55E00")) +
  ggplot2::scale_shape_manual(values = c(Model = 16, Literature = 18)) +
  ggplot2::scale_y_discrete(labels = with_status) +
  ggplot2::labs(x = NULL, y = NULL, colour = NULL, shape = NULL,
                caption = paste0("Carbon: model is soil + litter C; literature is measured SOC,\n",
                                 "0-30 cm for tillage, mean depth 22 cm for cover crops.")) +
  plot_theme
ggplot2::ggsave(file.path(out, "effects.png"), p, width = 7.5, height = 8, dpi = 180, bg = "white")

points <- do.call(rbind, lapply(seq_len(nrow(main)), function(i) {
  m <- main[i, ]
  x <- effects[effects$treatment == m$treatment &
                 effects$reference == m$reference & effects$pair_ok, ]
  x <- x[is.finite(x[[m$metric]]), ]
  data.frame(site_id = x$site_id, panel = m$panel, label = m$label,
    value = if (m$is_ratio) 100 * expm1(x[[m$metric]]) else x[[m$metric]])
}))
points$panel <- factor(points$panel, levels = panel_names,
  labels = c("Model soil + litter C difference (Mg C/ha per reported year)",
             "Soil carbon change (%)", "Seasonal methane change (%)"))
points$label <- factor(points$label, levels = levels(main$label))
medians <- stats::aggregate(value ~ panel + label, points, stats::median)
p <- ggplot2::ggplot(points, ggplot2::aes(x = value, y = label)) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linetype = 2) +
  ggplot2::geom_point(position = ggplot2::position_jitter(width = 0, height = 0.15, seed = 41),
                     size = 1.8, alpha = 0.65, colour = "#0072B2") +
  ggplot2::geom_point(data = medians, shape = 18, size = 4, colour = "black") +
  ggplot2::facet_wrap(~ panel, ncol = 1, scales = "free", labeller = wrap_panel) +
  ggplot2::labs(x = NULL, y = NULL) + plot_theme
ggplot2::ggsave(file.path(out, "locations-v4.png"), p, width = 7.5, height = 8, dpi = 180, bg = "white")
utils::write.csv(points, file.path(out, "location_display_values.csv"), row.names = FALSE)

writeLines(c("Archived estimators reproduced for all six main comparisons.",
             "All finite location effects retained; no axis limits or trimming.",
             capture.output(utils::sessionInfo())), file.path(out, "verification.txt"))
# Direction check against Table 6 (organization#164). Each practice contrast is summarized
# once per outcome: the mean log response across locations, and the share of locations with
# that sign. A direction needs a mean change of at least `band` and at least two thirds of
# locations agreeing; smaller means are "no change", and a larger mean that fewer than two
# thirds of locations share is "mixed". Soil C is the soil pool alone at the end of 2023.
# Rice N2O and CH4 use the flooded-season totals, as the archived comparisons and Jiang et
# al. (2019) do; everything else uses 2016-2023. No verdict is given where the cell is out of
# scope, where the archived comparison is blocked (comparison_status.csv), or where the
# audited evidence is not verified.
evidence <- utils::read.csv("reports/data/table6_evidence.csv", stringsAsFactors = FALSE,
                            check.names = FALSE)
practice_names <- c(cover = "+Cover crops", noncrop_c = "+Non-crop C",
  tillage = "Less tillage", less_n = "Less N fertilizer",
  less_flooding = "Less flooding (rice drying)", perennial = "Annual to perennial")
stopifnot(all(evidence$practice %in% names(practice_names)),
          !anyDuplicated(evidence[c("practice", "outcome")]),
          all(evidence$evidence_status %in% c("verified", "variable", "disputed", "unsupported")),
          all(evidence$contrast_direction %in% c("increase", "decrease", "none")),
          all(evidence$scope == "in scope" | startsWith(evidence$scope, "out of scope")),
          all(table(factor(evidence$practice, levels = names(practice_names))) == 3),
          setequal(evidence$outcome, c("Soil C", "N2O", "CH4")))
contrasts <- data.frame(
  practice = c("cover", "noncrop_c", "tillage", "tillage", "less_n", "less_n",
               "less_flooding", "less_flooding"),
  contrast = c("Cover crop / none", "Organic for mineral fertilizer",
               "Reduced / conventional", "No / conventional", "Half / reference N rate",
               "Zero / reference N rate", "One drying / flooded", "Two dryings / flooded"),
  treatment = c("cover_annual", "organic_substitution", "tillage_reduced", "tillage_zero",
                "mineral_N_half", "mineral_N_zero", "rice_one_dry", "rice_two_dry"),
  reference = c("cover_none", "fertilizer_reference", "tillage_reference", "tillage_reference",
                "fertilizer_reference", "fertilizer_reference", "rice_irrigated_reference",
                "rice_irrigated_reference"))
# The archived comparison behind a contrast and outcome, where there is one; its status
# (comparison_status.csv) decides whether a direction can be judged.
archived_pair <- function(treatment, outcome) {
  key <- paste(treatment, outcome)
  ids <- c("cover_annual Soil C" = "cover_soc", "organic_substitution Soil C" = "org_sub",
           "tillage_reduced Soil C" = "till_reduced_soc", "tillage_zero Soil C" = "till_zero_soc",
           "tillage_zero N2O" = "till_zero_n2o", "rice_one_dry N2O" = "rice_one_n2o",
           "rice_two_dry N2O" = "rice_two_n2o", "rice_one_dry CH4" = "rice_one_ch4",
           "rice_two_dry CH4" = "rice_two_ch4")
  if (key %in% names(ids)) ids[[key]] else NA_character_
}
pair_status <- stats::setNames(status$status, retained$pair_id)
outcome_metric <- function(outcome, practice) {
  season <- practice == "less_flooding"
  switch(outcome, "Soil C" = "soil_lrr_end",
         N2O = if (season) "lrr_n2o_season" else "lrr_n2o_full",
         CH4 = if (season) "lrr_ch4_season" else "lrr_ch4_full")
}
classify <- function(x, band) {
  m <- mean(x)
  if (abs(expm1(m)) < band) return("no change")
  if (mean(sign(x) == sign(m)) < 2 / 3) return("mixed")
  if (m > 0) "increase" else "decrease"
}
verdicts <- c("agrees", "disagrees", "no model response", "mixed model response")
agreement <- function(model, ev, blocked) {
  if (ev$scope != "in scope") return("out of scope")
  if (blocked) return("blocked")
  if (ev$evidence_status == "unsupported") return("no evidence")
  expected <- ev$contrast_direction
  if (ev$evidence_status != "verified") {
    if (expected == "none") return("evidence not settled")
    return(if (model == expected) "agrees, evidence not settled" else "differs, evidence not settled")
  }
  if (model == expected || (expected == "none" && model == "no change")) return("agrees")
  if (model == "no change") return("no model response")
  if (model == "mixed") return("mixed model response")
  "disagrees"
}
direction_rows <- function(band) {
  do.call(rbind, lapply(seq_len(nrow(contrasts)), function(i) {
    k <- contrasts[i, ]
    pairs <- effects[effects$treatment == k$treatment & effects$reference == k$reference &
                       effects$pair_ok, ]
    do.call(rbind, lapply(c("Soil C", "N2O", "CH4"), function(outcome) {
      x <- pairs[[outcome_metric(outcome, k$practice)]]
      x <- x[is.finite(x)]
      ev <- evidence[evidence$practice == k$practice & evidence$outcome == outcome, ]
      pid <- archived_pair(k$treatment, outcome)
      blocked <- !is.na(pid) && pair_status[[pid]] == "blocked"
      model <- classify(x, band)
      data.frame(practice = k$practice, contrast = k$contrast, outcome = outcome,
        locations = length(x), mean_change_pct = 100 * expm1(mean(x)),
        share_same_sign = mean(sign(x) == sign(mean(x))), model = model,
        archived_pair = pid, evidence_status = ev$evidence_status,
        expected = ev$contrast_direction, scope = ev$scope,
        agreement = agreement(model, ev, blocked), note = ev$model_note)
    }))
  }))
}
directions <- direction_rows(0.01)
# The report text quotes these verdicts; stop if the results no longer give them.
verdict_of <- function(contrast, outcome) {
  directions$agreement[directions$contrast == contrast & directions$outcome == outcome]
}
stopifnot(verdict_of("Cover crop / none", "Soil C") == "agrees",
          verdict_of("Organic for mineral fertilizer", "Soil C") == "agrees",
          verdict_of("Half / reference N rate", "N2O") == "agrees",
          verdict_of("Zero / reference N rate", "N2O") == "agrees",
          all(directions$agreement[directions$practice == "less_flooding" &
                                     directions$outcome != "Soil C"] == "blocked"),
          all(directions$agreement[directions$outcome == "CH4" &
                                     directions$practice != "less_flooding"] == "out of scope"),
          sum(directions$agreement %in% verdicts) == 4)
utils::write.csv(directions, file.path(out, "direction_check.csv"), row.names = FALSE)
pct <- function(v) ifelse(abs(v) < 0.1, sprintf("%+.2f%%", v), sprintf("%+.1f%%", v))
cell <- function(d) {
  if (d$model %in% c("increase", "decrease")) {
    sprintf("%s, %s (%.0f%% of %d locations) — %s", d$model, pct(d$mean_change_pct),
            100 * d$share_same_sign, d$locations, d$agreement)
  } else {
    sprintf("%s, %s (%d locations) — %s", d$model, pct(d$mean_change_pct), d$locations,
            d$agreement)
  }
}
wide <- do.call(rbind, lapply(split(directions, factor(directions$contrast,
                                                        levels = contrasts$contrast)), function(d) {
  data.frame(Practice = practice_names[[d$practice[1]]], Contrast = d$contrast[1],
             `Soil C` = cell(d[d$outcome == "Soil C", ]), `N2O-N` = cell(d[d$outcome == "N2O", ]),
             CH4 = cell(d[d$outcome == "CH4", ]), check.names = FALSE)
}))
wide <- rbind(wide, data.frame(Practice = practice_names[["perennial"]], Contrast = "—",
  `Soil C` = "not simulated", `N2O-N` = "not simulated", CH4 = "not simulated",
  check.names = FALSE))
write_table(wide, "direction_table.md")
write_table(data.frame(Practice = unname(practice_names[evidence$practice]),
  Outcome = sub("N2O", "N2O-N", evidence$outcome), `Table 6` = evidence$table6,
  `Audited evidence` = paste0(evidence$evidence_status, ": ", evidence$evidence_direction),
  Scope = evidence$scope, `Model note` = evidence$model_note, check.names = FALSE),
  "table6_evidence_table.md")
# How the verdicts change if the no-change band is 0.5% or 2% instead of 1%.
judged <- directions$agreement %in% verdicts
flip_text <- vapply(c(0.005, 0.02), function(b) {
  alt <- direction_rows(b)
  hit <- alt$agreement != directions$agreement & (judged | alt$agreement %in% verdicts)
  if (!any(hit)) {
    return(sprintf("With a %.1f%% band, none of the %d verdicts changes.", 100 * b, sum(judged)))
  }
  sprintf("With a %.1f%% band, %d of the %d verdicts %s: %s.", 100 * b, sum(hit), sum(judged),
          if (sum(hit) == 1) "changes" else "change",
          paste0(directions$contrast[hit], " ", directions$outcome[hit], " becomes ",
                 alt$agreement[hit], collapse = "; "))
}, character(1))
writeLines(paste(flip_text, collapse = " "), file.path(out, "direction_sensitivity.md"))
