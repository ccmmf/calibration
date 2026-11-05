# Run from the repository root: Rscript reports/R/build_inventory_comparison.R
# Compares the MAGiC historical inventory v0.1.0 (2023) with CARB's 2025 Natural and Working
# Lands cropland inventory (organization#226). Reads frozen copies only; no model is run.
# MAGiC totals cover a fixed set of fields, while CARB totals change with cropland area, so
# changes are compared per hectare; CARB's 2014-2022 years are summarized together rather than
# by picking single end years.
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
# Every lookup must return exactly one value, so a missed key stops the build.
one <- function(x) {
  stopifnot(length(x) == 1, !is.na(x))
  x
}
pred <- read_csv("magic_v0.1.0_2023_state_predictions_by_ensemble_soc_agb.csv")
changes <- read_csv("magic_v0.1.0_2023_state_differences_by_ensemble_soc_agb.csv")
stocks <- read_csv("carb_2025_cropland_stocks.csv")
perennial <- read_csv("carb_2025_perennial_biomass_area.csv")
density_change <- read_csv("carb_2025_regional_soil_density_change.csv")
area_change <- read_csv("carb_2025_regional_area_change.csv")
reference <- read_csv("carb_reference_values.csv")
key <- c("model_output", "pft", "ensemble")
stopifnot(nrow(pred) == 80, !anyDuplicated(pred[key]), !anyDuplicated(changes[key]),
          setequal(pred$ensemble, 1:20))
acre_to_ha <- 0.40468564224
t_per_acre_to_mg_per_ha <- 1 / acre_to_ha

# MAGiC: per member, Dec 2023 totals and Jan 2016 totals (Dec 2023 minus the endpoint change),
# summed over the two crop strata within each member. Mg C to MMT C; ha to Mha.
magic <- merge(pred, changes[c(key, "delta_total_state")], by = key)
magic$end <- magic$total_per_state / 1e6
magic$start <- (magic$total_per_state - magic$delta_total_state) / 1e6
magic$mha <- magic$total_ha / 1e6
all_crops <- stats::aggregate(cbind(end, start, mha) ~ model_output + ensemble, magic, sum)
all_crops$pft <- "all crops"
members <- rbind(magic[c("model_output", "pft", "ensemble", "end", "start", "mha")],
                 all_crops[c("model_output", "pft", "ensemble", "end", "start", "mha")])
members$change <- members$end - members$start
magic_summary <- do.call(rbind, lapply(split(members, list(members$model_output, members$pft)),
  function(d) {
    data.frame(model_output = d$model_output[1], pft = d$pft[1], mha = d$mha[1],
               start_mean = mean(d$start), start_sd = stats::sd(d$start),
               end_mean = mean(d$end), end_sd = stats::sd(d$end),
               change_mean = mean(d$change), change_median = stats::median(d$change),
               change_min = min(d$change), change_max = max(d$change),
               members_losing = sum(d$change < 0))
  }))
utils::write.csv(magic_summary, file.path(out, "magic_state_totals.csv"), row.names = FALSE)
m <- function(output, pft, col) {
  one(magic_summary[[col]][magic_summary$model_output == output & magic_summary$pft == pft])
}
soil_mha <- m("TotSoilCarb", "all crops", "mha")
woody_mha <- m("AGB", "woody perennial crop", "mha")

# CARB soil (Appendix Figure 59): the 2014-2022 years summarized together.
soil_years <- stocks[stocks$pool == "Soil" & stocks$year %in% 2014:2022, ]
stopifnot(nrow(soil_years) == 9)
trend <- stats::lm(mmt_c ~ year, soil_years)
trend_ci <- stats::confint(trend)["year", ]
carb_soil <- list(mean = mean(soil_years$mmt_c), sd = stats::sd(soil_years$mmt_c),
                  min = min(soil_years$mmt_c), max = max(soil_years$mmt_c),
                  slope = unname(stats::coef(trend)["year"]), lower = trend_ci[[1]],
                  upper = trend_ci[[2]])
# CARB average soil carbon density change, 2014-2022, by region (Appendix Figure 70).
regional <- density_change[density_change$period == "2014-2022", ]
regional$mg_c_per_ha <- regional$soil_c_density_change_t_per_acre * t_per_acre_to_mg_per_ha
stopifnot(nrow(regional) == 9)
region_change <- function(name) one(regional$mg_c_per_ha[regional$region == name])
cropland_growth_macres <- sum(area_change$area_change_million_acres[area_change$period == "2014-2022"])
# CARB perennial biomass and area by year (Appendix Figure 66), and their density.
per_year <- stats::aggregate(cbind(acres, biomass_mmt_c) ~ year, perennial, sum)
per_year$mha <- per_year$acres * acre_to_ha / 1e6
per_year$density <- per_year$biomass_mmt_c / per_year$mha
per <- function(year, col) one(per_year[[col]][per_year$year == year])
ref <- function(q) one(reference$value[reference$quantity == q])

soil_density <- function(col) m("TotSoilCarb", "all crops", col) / soil_mha
start_vs_carb <- m("TotSoilCarb", "all crops", "start_mean") / carb_soil$mean - 1
# The report text quotes these; stop if the frozen data no longer give them.
near <- function(x, target, tol) abs(x - target) < tol
stopifnot(
  near(m("TotSoilCarb", "all crops", "start_mean"), 238.3, 0.05),
  near(m("TotSoilCarb", "all crops", "end_mean"), 201.2, 0.05),
  near(m("TotSoilCarb", "all crops", "change_mean"), -37.2, 0.05),
  near(m("TotSoilCarb", "all crops", "change_median"), -25.9, 0.05),
  near(m("TotSoilCarb", "all crops", "change_min"), -95.0, 0.05),
  near(m("TotSoilCarb", "all crops", "change_max"), -0.5, 0.05),
  m("TotSoilCarb", "all crops", "members_losing") == 20,
  near(soil_density("start_mean"), 68.4, 0.05), near(soil_density("end_mean"), 57.7, 0.05),
  near(soil_density("change_mean"), -10.7, 0.05),
  near(100 * m("TotSoilCarb", "all crops", "change_mean") /
         m("TotSoilCarb", "all crops", "start_mean"), -15.6, 0.05),
  near(m("AGB", "woody perennial crop", "start_mean"), 10.69, 0.005),
  near(m("AGB", "woody perennial crop", "end_mean"), 1.15, 0.005),
  near(m("AGB", "woody perennial crop", "start_mean") / woody_mha, 6.4, 0.05),
  near(m("AGB", "woody perennial crop", "end_mean") / woody_mha, 0.7, 0.05),
  near(m("AGB", "annual crop", "start_mean") / m("AGB", "annual crop", "mha"), 4.0, 0.05),
  near(carb_soil$mean, 219.5, 0.05), near(carb_soil$slope, 0.50, 0.005),
  near(carb_soil$lower, -1.67, 0.005), near(carb_soil$upper, 2.67, 0.005),
  near(100 * start_vs_carb, 8.6, 0.05),
  sum(regional$mg_c_per_ha < 0) == 7,
  near(region_change("San Joaquin Valley"), -3.0, 0.05),
  near(region_change("Sacramento Valley"), -4.3, 0.05),
  near(cropland_growth_macres, 0.65, 0.005),
  near(per(2016, "density"), 34.2, 0.05), near(per(2022, "density"), 33.9, 0.05),
  near(per(2016, "mha"), 1.74, 0.005), near(per(2022, "mha"), 1.90, 0.005),
  near(per(2022, "biomass_mmt_c") - per(2016, "biomass_mmt_c"), 5.07, 0.005),
  near(one(stocks$mmt_c[stocks$year == 2022 & stocks$pool == "Biomass"]), 65.0, 0.05),
  near(per(2022, "biomass_mmt_c"), 64.5, 0.05))

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ",")
comparison <- data.frame(
  Quantity = c("Soil carbon stock (MMT C)",
               "Soil carbon change",
               "Perennial crop biomass density (Mg C/ha)",
               "Perennial crop biomass (MMT C)",
               "Area (Mha)",
               "N2O and CH4"),
  MAGiC = c(
    paste0(fmt(m("TotSoilCarb", "all crops", "start_mean")), " in Jan 2016, ",
           fmt(m("TotSoilCarb", "all crops", "end_mean")), " in Dec 2023 (soil plus litter)"),
    paste0(fmt(soil_density("change_mean")), " Mg C/ha on fixed fields, Jan 2016 to Dec 2023 (",
           fmt(soil_density("start_mean")), " to ", fmt(soil_density("end_mean")),
           "); all 20 members lose, median ", fmt(m("TotSoilCarb", "all crops", "change_median")),
           " MMT C, range ", fmt(m("TotSoilCarb", "all crops", "change_min")), " to ",
           fmt(m("TotSoilCarb", "all crops", "change_max"))),
    paste0(fmt(m("AGB", "woody perennial crop", "start_mean") / woody_mha), " in Jan 2016, ",
           fmt(m("AGB", "woody perennial crop", "end_mean") / woody_mha),
           " in Dec 2023 (woody crops; aboveground wood and leaves)"),
    paste0(fmt(m("AGB", "woody perennial crop", "start_mean"), 2), " in Jan 2016, ",
           fmt(m("AGB", "woody perennial crop", "end_mean"), 2), " in Dec 2023"),
    paste0(fmt(woody_mha, 2), " woody and ", fmt(m("AGB", "annual crop", "mha"), 2),
           " annual; fixed over the run"),
    "pending in v0.1.0"),
  CARB = c(
    paste0(fmt(carb_soil$mean), " mean over 2014-2022 (range ", fmt(carb_soil$min), " to ",
           fmt(carb_soil$max), "; top 30 cm); 2018 inventory: ",
           fmt(ref("Mineral soil organic carbon in the top 30 cm"), 2), " mineral plus ",
           fmt(ref("Drained organic soil organic carbon"), 2), " drained organic"),
    paste0("total ", sprintf("%+.2f", carb_soil$slope), " MMT C/yr over 2014-2022 (95% CI ",
           fmt(carb_soil$lower, 2), " to ", fmt(carb_soil$upper, 2),
           "), with cropland area growing; average density falls in ",
           sum(regional$mg_c_per_ha < 0), " of 9 regions, by ",
           fmt(-region_change("San Joaquin Valley")), " (San Joaquin Valley) and ",
           fmt(-region_change("Sacramento Valley")), " Mg C/ha (Sacramento Valley)"),
    paste0(fmt(per(2016, "density")), " in 2016, ", fmt(per(2022, "density")),
           " in 2022 (roots, trunks and branches)"),
    paste0(fmt(per(2016, "biomass_mmt_c"), 2), " in 2016, ", fmt(per(2022, "biomass_mmt_c"), 2),
           " in 2022, as perennial area grew"),
    paste0(fmt(per(2016, "mha"), 2), " perennial in 2016, ", fmt(per(2022, "mha"), 2),
           " in 2022; all cropland grew by ", fmt(cropland_growth_macres * acre_to_ha, 2),
           " Mha over 2014-2022"),
    paste0(ref("Cropland N2O"), " Gg N2O/yr; rice CH4 about ", ref("Rice methane"),
           " MMT CO2e/yr")),
  check.names = FALSE)
writeLines(as.character(knitr::kable(comparison, format = "pipe", row.names = FALSE)),
           file.path(out, "comparison_table.md"))
utils::write.csv(regional[c("region", "soil_c_density_change_t_per_acre", "mg_c_per_ha")],
                 file.path(out, "carb_regional_density_change_2014_2022.csv"), row.names = FALSE)

# Figure: CARB cropland soil and biomass series with the MAGiC start and end points.
carb_plot <- stocks[stocks$pool %in% c("Soil", "Biomass"), ]
carb_plot$pool <- factor(carb_plot$pool, levels = c("Soil", "Biomass"),
                         labels = c("Soil carbon", "Biomass carbon"))
endpoint <- function(output, col, pft = "all crops") m(output, pft, col)
magic_plot <- data.frame(
  pool = factor(rep(c("Soil carbon", "Biomass carbon"), each = 2),
                levels = c("Soil carbon", "Biomass carbon")),
  year = c(2016, 2023.95, 2016, 2023.95),
  mean = c(endpoint("TotSoilCarb", "start_mean"), endpoint("TotSoilCarb", "end_mean"),
           endpoint("AGB", "start_mean", "woody perennial crop"),
           endpoint("AGB", "end_mean", "woody perennial crop")),
  sd = c(endpoint("TotSoilCarb", "start_sd"), endpoint("TotSoilCarb", "end_sd"),
         endpoint("AGB", "start_sd", "woody perennial crop"),
         endpoint("AGB", "end_sd", "woody perennial crop")))
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
                caption = paste0("MAGiC: Jan 2016 and Dec 2023, mean ± SD over 20 parameter\nmembers, ",
                                 "fixed fields; biomass is woody perennial crops only.\nCARB: annual totals, ",
                                 "which change with cropland area;\nbiomass is interpolated in some years.")) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank(),
                 strip.text = ggplot2::element_text(face = "bold", hjust = 0),
                 plot.caption.position = "plot", plot.caption = ggplot2::element_text(hjust = 0))
ggplot2::ggsave(file.path(out, "inventory_series.png"), p, width = 7.5, height = 7, dpi = 180,
                bg = "white")
writeLines(c("Frozen input checksums verified; the quoted values above are reproduced.",
             capture.output(utils::sessionInfo())), file.path(out, "verification.txt"))
