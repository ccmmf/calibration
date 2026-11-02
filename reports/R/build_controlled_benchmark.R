# Run from the repository root after retrieving completed pilot summaries.
base <- "examples/4_controlled_benchmark"
out <- "reports/generated/controlled"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
manifest <- jsonlite::fromJSON(file.path(base, "results/manifest.json"))
for (i in seq_len(nrow(manifest$files))) {
  record <- manifest$files[i, ]
  stopifnot(identical(digest::digest(file = file.path(base, record$file),
                                   algo = "sha256"), record$sha256))
}
diag <- utils::read.csv(file.path(base, "results/run_diagnostics.csv"),
                         colClasses = c(site_id = "character"))
effects <- utils::read.csv(file.path(base, "results/paired_effects.csv"),
                            colClasses = c(site_id = "character"))
daily <- utils::read.csv(file.path(base, "results/daily_diagnostics.csv"),
                          colClasses = c(site_id = "character"))
conversion <- utils::read.csv(file.path(base, "results/conversion_checks.csv"))
stopifnot(nrow(conversion) == 224L,
          all(conversion$soil_conversion_difference_g_m2 < 0.02),
          all(conversion$gpp_conversion_difference_g_m2 < 0.001))
write_table <- function(x, name) writeLines(as.character(knitr::kable(x,
  format = "pipe", row.names = FALSE)), file.path(out, name))
stopifnot(nrow(diag) == 28L, all(diag$days == 2922),
          all(as.logical(effects$no_change_verified)), all(as.logical(effects$common_initial_state)),
          all(as.logical(effects$common_non_treatment_inputs)))
base_diag <- diag[diag$variant == "baseline", ]
write_table(data.frame(Location = base_diag$site_id, System = base_diag$system,
  `Preparation years` = base_diag$prep_years,
  `Mean annual GPP (g C/m²)` = round(base_diag$annual_mean_gpp_g_C_m2, 2),
  `Maximum LAI (m²/m²)` = round(base_diag$maximum_leaf_area_index, 3),
  check.names = FALSE), "baseline.md")
selected <- effects[!effects$variant %in% c("baseline", "no_change"), ]
write_table(data.frame(Location = selected$site_id,
  `Preparation years` = selected$prep_years, Scenario = selected$variant,
  `Soil C difference (Mg C/ha/year)` = signif(selected$soil_C_difference_per_year, 3),
  `Seasonal CH4 RR` = signif(selected$seasonal_ch4_RR, 6),
  check.names = FALSE), "effects.md")
water <- diag[diag$system == "rice" & !diag$variant %in% c("baseline", "no_change"), ]
write_table(data.frame(Location = water$site_id,
  `Preparation years` = water$prep_years, Scenario = water$variant,
  `Minimum water / holding capacity during interruptions` = round(water$min_water_ratio_interruption, 3),
  check.names = FALSE), "water.md")

# Plot calendar-aligned daily means and ranges across eight forcing years.
daily$date <- as.Date(sprintf("%d-01-01", daily$year)) + daily$day - 1
daily$month_day <- format(daily$date, "%m-%d")
daily$plot_day <- as.numeric(as.Date(paste0("2000-", daily$month_day)))
rice <- daily[daily$system == "rice" & daily$prep_years == 8 &
                daily$variant != "no_change" & daily$month_day >= "05-01" &
                daily$month_day <= "08-31", ]
rice_sum <- rice |>
  dplyr::group_by(site_id, variant, plot_day) |>
  dplyr::summarise(mean = mean(water_ratio), low = min(water_ratio),
                   high = max(water_ratio), .groups = "drop")
rice_sum$variant <- factor(rice_sum$variant,
  levels = c("baseline", "one_interruption", "two_interruptions"),
  labels = c("Baseline", "One interruption", "Two interruptions"))
windows <- data.frame(start = as.numeric(as.Date(c("2000-06-15", "2000-07-15"))),
                       end = as.numeric(as.Date(c("2000-06-28", "2000-07-28"))))
p <- ggplot2::ggplot(rice_sum, ggplot2::aes(plot_day, mean, colour = variant, fill = variant)) +
  ggplot2::geom_rect(data = windows, ggplot2::aes(xmin = start, xmax = end, ymin = -Inf, ymax = Inf),
                      inherit.aes = FALSE, fill = "grey90") +
  ggplot2::geom_hline(yintercept = 1, linetype = 2, colour = "black") +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = low, ymax = high), alpha = 0.10, colour = NA) +
  ggplot2::geom_line(ggplot2::aes(linetype = variant), linewidth = 0.7) +
  ggplot2::facet_wrap(~ site_id, ncol = 1, labeller = ggplot2::label_both) +
  ggplot2::scale_x_continuous(breaks = as.numeric(as.Date(paste0("2000-", c("05-01", "06-01", "07-01", "08-01")))),
    labels = c("May", "June", "July", "August")) +
  ggplot2::scale_colour_manual(values = c("#0072B2", "#D55E00", "#009E73")) +
  ggplot2::scale_fill_manual(values = c("#0072B2", "#D55E00", "#009E73")) +
  ggplot2::labs(x = NULL, y = "Soil water / holding capacity", colour = NULL, fill = NULL, linetype = NULL) +
  ggplot2::theme_minimal(base_size = 14) + ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(file.path(out, "rice_water.png"), p, width = 9, height = 6.5, dpi = 180, bg = "white")

annual <- daily[daily$system == "annual" & daily$prep_years == 8 & daily$variant != "no_change", ]
a <- annual |>
  dplyr::group_by(site_id, variant, plot_day) |>
  dplyr::summarise(leaf = mean(leaf_C_g_m2), .groups = "drop")
p <- ggplot2::ggplot(a, ggplot2::aes(plot_day, leaf, colour = variant, linetype = variant)) +
  ggplot2::geom_line(linewidth = 0.8) + ggplot2::facet_wrap(~ site_id, ncol = 1, labeller = ggplot2::label_both) +
  ggplot2::scale_x_continuous(breaks = as.numeric(as.Date(paste0("2000-", c("01-01", "04-01", "07-01", "10-01")))),
    labels = c("January", "April", "July", "October")) +
  ggplot2::scale_colour_manual(values = c(baseline = "#0072B2", cover = "#D55E00")) +
  ggplot2::labs(x = NULL, y = "Daily maximum leaf carbon (g C/m²)\nmean across evaluation years", colour = NULL, linetype = NULL) +
  ggplot2::theme_minimal(base_size = 14) + ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(file.path(out, "annual_growth.png"), p, width = 9, height = 6.5, dpi = 180, bg = "white")
