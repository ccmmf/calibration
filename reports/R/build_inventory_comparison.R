# Run from the repository root: Rscript reports/R/build_inventory_comparison.R
# Compares the MAGiC historical inventory v0.1.0 (2023) with CARB's 2025 Natural and Working
# Lands cropland inventory (organization#226). Reads frozen copies only; no model is run.
input <- "reports/data/inventory"
out <- "reports/generated/inventory"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
manifest <- jsonlite::fromJSON(file.path(input, "manifest.json"))
for (i in seq_len(nrow(manifest$files))) {
  record <- manifest$files[i, ]
  stopifnot(identical(digest::digest(file = file.path(input, record$file), algo = "sha256"),
                      record$sha256))
}
read_csv <- function(name) utils::read.csv(file.path(input, name), stringsAsFactors = FALSE,
                                           check.names = FALSE)
pred <- read_csv("magic_v0.1.0_2023_state_predictions_by_ensemble_soc_agb.csv")
diff <- read_csv("magic_v0.1.0_2023_state_differences_by_ensemble_soc_agb.csv")
stocks <- read_csv("carb_2025_cropland_stocks.csv")
perennial <- read_csv("carb_2025_perennial_biomass_area.csv")
reference <- read_csv("carb_reference_values.csv")
key <- c("model_output", "pft", "ensemble")
stopifnot(nrow(pred) == 80, !anyDuplicated(pred[key]), !anyDuplicated(diff[key]),
          setequal(pred$ensemble, 1:20))

# MAGiC: Dec 2023 totals and Jan 2016 totals (Dec 2023 minus the endpoint change), per member
# and crop stratum, then summed over the strata within each member. Mg C to MMT C.
magic <- merge(pred, diff[c(key, "delta_total_state")], by = key)
magic$end <- magic$total_per_state / 1e6
magic$start <- (magic$total_per_state - magic$delta_total_state) / 1e6
magic$ha <- magic$total_ha / 1e6
all_crops <- stats::aggregate(cbind(end, start, ha) ~ model_output + ensemble, magic, sum)
all_crops$pft <- "all crops"
members <- rbind(magic[c("model_output", "pft", "ensemble", "end", "start", "ha")],
                 all_crops[c("model_output", "pft", "ensemble", "end", "start", "ha")])
summ <- function(x) c(mean = mean(x), sd = stats::sd(x))
magic_summary <- do.call(rbind, lapply(split(members, list(members$model_output, members$pft)),
  function(d) {
    data.frame(model_output = d$model_output[1], pft = d$pft[1], mha = d$ha[1],
               start_mean = mean(d$start), start_sd = stats::sd(d$start),
               end_mean = mean(d$end), end_sd = stats::sd(d$end),
               change_mean = mean(d$end - d$start), change_sd = stats::sd(d$end - d$start))
  }))
utils::write.csv(magic_summary, file.path(out, "magic_state_totals.csv"), row.names = FALSE)
m <- function(output, pft, col) {
  magic_summary[[col]][magic_summary$model_output == output & magic_summary$pft == pft]
}

# CARB: Appendix Figure 59 stocks and Appendix Figure 66 perennial biomass and area.
carb <- function(year, pool) stocks$mmt_c[stocks$year == year & stocks$pool == pool]
per_year <- stats::aggregate(cbind(acres, biomass_mmt_c) ~ year, perennial, sum)
per <- function(year, col) per_year[[col]][per_year$year == year]
acre_to_mha <- 0.40468564224 / 1e6
carb_perennial_mha <- per(2022, "acres") * acre_to_mha
ref <- function(q) reference$value[reference$quantity == q]

# The report text quotes these; stop if the frozen data no longer give them.
stopifnot(abs(m("TotSoilCarb", "all crops", "end_mean") - 201.2) < 0.05,
          abs(m("TotSoilCarb", "all crops", "change_mean") + 37.2) < 0.05,
          abs(m("AGB", "woody perennial crop", "end_mean") - 1.15) < 0.005,
          abs(m("AGB", "woody perennial crop", "start_mean") - 10.69) < 0.005,
          abs(carb(2022, "Soil") - 213.50) < 0.005, abs(carb(2016, "Soil") - 230.42) < 0.005,
          abs(carb(2014, "Soil") - 209.34) < 0.005,
          abs(per(2022, "biomass_mmt_c") - 64.52) < 0.005,
          abs(carb_perennial_mha - 1.905) < 0.0005)

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ",")
pm <- function(mean, sd, d = 1) paste0(fmt(mean, d), " ± ", fmt(sd, d))
density <- function(total, mha) fmt(total / mha, 1)
woody_mha <- m("AGB", "woody perennial crop", "mha")
table <- data.frame(
  Quantity = c("Soil carbon stock (MMT C)",
               "Soil carbon change (MMT C)",
               "Perennial crop biomass (MMT C)",
               "Perennial crop biomass density (Mg C/ha)",
               "Perennial crop biomass change (MMT C)",
               "Area (Mha)",
               "N2O and CH4"),
  MAGiC = c(paste0(pm(m("TotSoilCarb", "all crops", "end_mean"), m("TotSoilCarb", "all crops", "end_sd")),
                   " (Dec 2023; soil plus litter, whole modeled profile)"),
            paste0(pm(m("TotSoilCarb", "all crops", "change_mean"), m("TotSoilCarb", "all crops", "change_sd")),
                   " (Jan 2016 to Dec 2023)"),
            paste0(pm(m("AGB", "woody perennial crop", "end_mean"), m("AGB", "woody perennial crop", "end_sd"), 2),
                   " (Dec 2023, woody crops); ",
                   fmt(m("AGB", "woody perennial crop", "start_mean"), 2), " in Jan 2016"),
            paste0(density(m("AGB", "woody perennial crop", "end_mean"), woody_mha), " (Dec 2023); ",
                   density(m("AGB", "woody perennial crop", "start_mean"), woody_mha), " (Jan 2016)"),
            paste0(pm(m("AGB", "woody perennial crop", "change_mean"), m("AGB", "woody perennial crop", "change_sd"), 2),
                   " (Jan 2016 to Dec 2023)"),
            paste0(fmt(m("AGB", "all crops", "mha"), 2), " covered (",
                   fmt(woody_mha, 2), " woody, ", fmt(m("AGB", "annual crop", "mha"), 2), " annual)"),
            "pending in v0.1.0"),
  CARB = c(paste0(fmt(carb(2022, "Soil")), " (2022, Appendix Fig. 59); report text: ",
                  fmt(ref("Mineral soil organic carbon in the top 30 cm"), 2), " mineral, top 30 cm, plus ",
                  fmt(ref("Drained organic soil organic carbon"), 2), " drained organic"),
           paste0(fmt(carb(2022, "Soil") - carb(2016, "Soil")), " (2016 to 2022); ",
                  fmt(carb(2022, "Soil") - carb(2014, "Soil")), " (2014 to 2022)"),
           paste0(fmt(per(2022, "biomass_mmt_c"), 2), " (2022, Appendix Fig. 66)"),
           density(per(2022, "biomass_mmt_c"), carb_perennial_mha),
           paste0(fmt(per(2022, "biomass_mmt_c") - per(2016, "biomass_mmt_c"), 2), " (2016 to 2022)"),
           paste0(fmt(carb_perennial_mha, 2), " perennial (2022)"),
           paste0(ref("Cropland N2O"), " Gg N2O/yr; rice CH4 about ", ref("Rice methane"), " MMT CO2e/yr")),
  check.names = FALSE)
writeLines(as.character(knitr::kable(table, format = "pipe", row.names = FALSE)),
           file.path(out, "comparison_table.md"))

# Figure: CARB cropland soil and biomass series with the MAGiC start and end points.
carb_plot <- stocks[stocks$pool %in% c("Soil", "Biomass"), ]
carb_plot$pool <- factor(carb_plot$pool, levels = c("Soil", "Biomass"),
                         labels = c("Soil carbon", "Biomass carbon"))
magic_plot <- data.frame(
  pool = factor(rep(c("Soil carbon", "Biomass carbon"), each = 2),
                levels = c("Soil carbon", "Biomass carbon")),
  year = c(2016, 2023.95, 2016, 2023.95),
  mean = c(m("TotSoilCarb", "all crops", "start_mean"), m("TotSoilCarb", "all crops", "end_mean"),
           m("AGB", "all crops", "start_mean"), m("AGB", "all crops", "end_mean")),
  sd = c(m("TotSoilCarb", "all crops", "start_sd"), m("TotSoilCarb", "all crops", "end_sd"),
         m("AGB", "all crops", "start_sd"), m("AGB", "all crops", "end_sd")))
p <- ggplot2::ggplot() +
  ggplot2::geom_line(data = carb_plot, ggplot2::aes(year, mmt_c, colour = "CARB 2025 inventory")) +
  ggplot2::geom_point(data = carb_plot, ggplot2::aes(year, mmt_c, colour = "CARB 2025 inventory"),
                      size = 1.6) +
  ggplot2::geom_errorbar(data = magic_plot, ggplot2::aes(x = year, ymin = mean - sd, ymax = mean + sd,
                                                          colour = "MAGiC v0.1.0"), width = 0.4) +
  ggplot2::geom_point(data = magic_plot, ggplot2::aes(year, mean, colour = "MAGiC v0.1.0"),
                      shape = 18, size = 3.5) +
  ggplot2::facet_wrap(~ pool, ncol = 1, scales = "free_y") +
  ggplot2::scale_colour_manual(values = c("CARB 2025 inventory" = "#D55E00", "MAGiC v0.1.0" = "#0072B2")) +
  ggplot2::expand_limits(y = 0) +
  ggplot2::labs(x = NULL, y = "Million metric tons of carbon", colour = NULL,
                caption = paste0("MAGiC: Jan 2016 and Dec 2023, mean ± SD over 20 parameter members; ",
                                 "soil plus litter, and standing\naboveground biomass. CARB: annual ",
                                 "estimates; biomass is interpolated in some years.")) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank(),
                 strip.text = ggplot2::element_text(face = "bold", hjust = 0))
ggplot2::ggsave(file.path(out, "inventory_series.png"), p, width = 7.5, height = 7, dpi = 180,
                bg = "white")
writeLines(c("Frozen input checksums verified; quoted values reproduced.",
             capture.output(utils::sessionInfo())), file.path(out, "verification.txt"))
