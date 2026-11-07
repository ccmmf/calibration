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

# By region. CARB reports soil carbon density change for the nine California Fifth Climate Change
# Assessment regions (Appendix B, Regional Assessment). The regions cut across county lines, so each
# MAGiC county is split among regions by CARB's own cropland acres in that county and region, summed
# over 2014-2022 (CARB aggregated data table). This assumes MAGiC's fields in a split county are
# spread like CARB's cropland and share the county's density.
county_pred <- read_csv("magic_v0.1.0_2023_county_predictions_by_ensemble_soc_agb.csv")
county_change <- read_csv("magic_v0.1.0_2023_county_differences_by_ensemble_soc_agb.csv")
county_region <- read_csv("carb_2025_cropland_county_region.csv")
county_key <- c("model_output", "pft", "county", "ensemble")
stopifnot(nrow(county_pred) == 4440, nrow(county_change) == 4440,
          !anyDuplicated(county_pred[county_key]), !anyDuplicated(county_change[county_key]))
county <- merge(county_pred[c(county_key, "n", "total_per_county", "total_ha")],
                county_change[c(county_key, "n", "delta_total_county", "total_ha")],
                by = county_key, suffixes = c("", "_change"))
stopifnot(nrow(county) == 4440, identical(county$n, county$n_change),
          isTRUE(all.equal(county$total_ha, county$total_ha_change)))
county$start <- county$total_per_county - county$delta_total_county
# The county tables add up to the state tables used above, member by member.
county_sums <- stats::aggregate(cbind(delta_total_county, total_ha) ~ model_output + pft + ensemble,
                                county, sum)
county_sums <- merge(county_sums, changes[c(key, "delta_total_state", "total_ha")], by = key)
stopifnot(nrow(county_sums) == 80,
          isTRUE(all.equal(county_sums$delta_total_county, county_sums$delta_total_state)),
          isTRUE(all.equal(county_sums$total_ha.x, county_sums$total_ha.y)))

regions <- sort(regional$region)
stopifnot(setequal(county_region$year, 2014:2022),
          setequal(county_region$region, c(regions, "UNDEFINED")),
          all(county_region$county[county_region$region == "UNDEFINED"] == "UNDEFINED"))
undefined_acres <- stats::aggregate(acres ~ year, county_region[county_region$county == "UNDEFINED", ],
                                    sum)
assigned <- county_region[county_region$county != "UNDEFINED", ]
shares <- stats::aggregate(acres ~ county + region, assigned, sum)
shares$share <- shares$acres / stats::ave(shares$acres, shares$county, FUN = sum)
# Every county with CARB cropland in 2014-2022 has MAGiC fields, and the reverse.
stopifnot(setequal(shares$county, county$county), length(unique(shares$county)) == 57)
# Sensitivity: each county wholly in the region holding most of its CARB cropland.
majority <- shares[shares$share == stats::ave(shares$share, shares$county, FUN = max), ]
majority$share <- 1
stopifnot(!anyDuplicated(majority$county))

totals <- c("start", "total_per_county", "delta_total_county", "total_ha")
region_members <- function(output, pfts, split = shares) {
  d <- merge(county[county$model_output == output & county$pft %in% pfts, ],
             split[c("county", "region", "share")], by = "county")
  d[totals] <- d[totals] * d$share
  r <- stats::aggregate(cbind(start, total_per_county, delta_total_county, total_ha) ~
                          region + ensemble, d, sum)
  # Densities from summed totals and areas, never by adding densities.
  r$start_density <- r$start / r$total_ha
  r$end_density <- r$total_per_county / r$total_ha
  r$change_density <- r$delta_total_county / r$total_ha
  r
}
summarize_regions <- function(r) {
  do.call(rbind, lapply(split(r, r$region), function(d) {
    stopifnot(nrow(d) == 20, setequal(d$ensemble, 1:20), diff(range(d$total_ha)) < 1e-6)
    data.frame(region = d$region[1], magic_kha = d$total_ha[1] / 1e3,
               start_mean = mean(d$start_density), end_mean = mean(d$end_density),
               change_mean = mean(d$change_density), change_median = stats::median(d$change_density),
               change_min = min(d$change_density), change_max = max(d$change_density),
               members_losing = sum(d$change_density < 0))
  }))
}
both_strata <- c("annual crop", "woody perennial crop")
soil_members <- region_members("TotSoilCarb", both_strata)
soil_regions <- summarize_regions(soil_members)
woody_regions <- summarize_regions(region_members("AGB", "woody perennial crop"))
majority_regions <- summarize_regions(region_members("TotSoilCarb", both_strata, majority))
stopifnot(identical(soil_regions$region, regions), identical(majority_regions$region, regions),
          nrow(woody_regions) == 9)
# The regional split keeps every member's state total and area.
member_totals <- stats::aggregate(cbind(delta_total_county, total_ha) ~ ensemble, soil_members, sum)
state_soil <- members[members$model_output == "TotSoilCarb" & members$pft == "all crops", ]
state_soil <- state_soil[order(state_soil$ensemble), ]
stopifnot(isTRUE(all.equal(member_totals$delta_total_county / 1e6, state_soil$change)),
          isTRUE(all.equal(member_totals$total_ha / 1e6, state_soil$mha)))
split_effect <- max(abs(soil_regions$change_mean - majority_regions$change_mean))

# CARB by region from the aggregated table: area and density by year. Its 2022 minus 2014 changes
# must reproduce Appendix Figures 70 and 63, which checks the region assignment against CARB's own.
carb_years <- stats::aggregate(cbind(acres, soil_c_mt_c) ~ region + year,
                               county_region[county_region$region != "UNDEFINED", ], sum)
carb_years$t_per_acre <- carb_years$soil_c_mt_c / carb_years$acres
carb_years$mg_c_per_ha <- carb_years$t_per_acre * t_per_acre_to_mg_per_ha
carb_year <- function(name, year, col) {
  one(carb_years[[col]][carb_years$region == name & carb_years$year == year])
}
carb_regions <- do.call(rbind, lapply(regions, function(name) {
  d <- carb_years[carb_years$region == name, ]
  stopifnot(nrow(d) == 9)
  fit <- stats::lm(mg_c_per_ha ~ year, d)
  ci <- stats::confint(fit)["year", ]
  data.frame(region = name, carb_kha = mean(d$acres) * acre_to_ha / 1e3,
             density_min = min(d$mg_c_per_ha), density_max = max(d$mg_c_per_ha),
             endpoint_t_per_acre = carb_year(name, 2022, "t_per_acre") -
               carb_year(name, 2014, "t_per_acre"),
             area_change_macres = (carb_year(name, 2022, "acres") - carb_year(name, 2014, "acres")) / 1e6,
             trend_8yr = 8 * unname(stats::coef(fit)["year"]), trend_8yr_lower = 8 * ci[[1]],
             trend_8yr_upper = 8 * ci[[2]])
}))
fig70_t <- function(name) one(regional$soil_c_density_change_t_per_acre[regional$region == name])
fig63 <- area_change[area_change$period == "2014-2022", ]
stopifnot(nrow(fig63) == 9,
          max(abs(carb_regions$endpoint_t_per_acre - vapply(regions, fig70_t, 0))) < 0.05,
          max(abs(carb_regions$area_change_macres -
                    fig63$area_change_million_acres[match(regions, fig63$region)])) < 0.001)

by_region <- merge(merge(soil_regions, carb_regions, by = "region"),
                   regional[c("region", "mg_c_per_ha")], by = "region")
names(by_region)[names(by_region) == "mg_c_per_ha"] <- "carb_change"
by_region$area_ratio <- by_region$magic_kha / by_region$carb_kha
by_region <- by_region[order(-by_region$magic_kha), ]
r <- function(name, col) one(by_region[[col]][by_region$region == name])
w <- function(name, col) one(woody_regions[[col]][woody_regions$region == name])
valleys <- c("Sacramento Valley", "San Joaquin Valley")
valley_share <- sum(by_region$magic_kha[by_region$region %in% valleys]) / sum(by_region$magic_kha)
share <- function(name, region) one(shares$share[shares$county == name & shares$region == region])
largest_share <- stats::aggregate(share ~ county, shares, max)
others <- by_region[!by_region$region %in% valleys, ]
no_woody <- setdiff(unique(county$county), unique(county$county[county$pft == "woody perennial crop"]))
# The By region text quotes these; stop if the frozen data no longer give them.
stopifnot(
  near(valley_share, 0.76, 0.005),
  all(by_region$change_mean < 0),
  r("Sacramento Valley", "members_losing") == 20, r("San Joaquin Valley", "members_losing") == 20,
  min(others$members_losing) == 9, max(others$members_losing) == 16,
  near(r("Sacramento Valley", "change_mean"), -13.5, 0.05),
  near(r("San Joaquin Valley", "change_mean"), -11.7, 0.05),
  near(r("Sacramento Valley", "change_median"), -9.6, 0.05),
  near(r("San Joaquin Valley", "change_median"), -8.4, 0.05),
  near(r("Sacramento Valley", "carb_change"), -4.3, 0.05),
  near(r("San Joaquin Valley", "carb_change"), -3.0, 0.05),
  near(r("San Joaquin Valley", "trend_8yr_lower"), -4.7, 0.05),
  near(r("San Joaquin Valley", "trend_8yr_upper"), 1.0, 0.05),
  r("San Joaquin Valley", "trend_8yr_lower") > r("San Joaquin Valley", "change_median"),
  near(r("Sacramento Valley", "density_min"), 68.9, 0.05),
  near(r("Sacramento Valley", "density_max"), 84.3, 0.05),
  near(r("Sacramento Valley", "trend_8yr_lower"), -15.3, 0.05),
  near(r("Sacramento Valley", "trend_8yr_upper"), 5.0, 0.05),
  r("Sacramento Valley", "trend_8yr_lower") < r("Sacramento Valley", "change_mean"),
  sum(by_region$carb_change > 0) == 2,
  near(r("San Francisco Bay Area", "carb_change"), 1.7, 0.05),
  near(r("Los Angeles", "carb_change"), 1.6, 0.05),
  near(r("San Francisco Bay Area", "trend_8yr"), -0.5, 0.05),
  near(r("Los Angeles", "trend_8yr"), -0.1, 0.05),
  near(r("San Francisco Bay Area", "change_mean"), -7.5, 0.05),
  near(r("Los Angeles", "change_mean"), -9.4, 0.05),
  identical(by_region$region[order(by_region$carb_change)[1:2]], c("North Coast", "Sierra Nevada")),
  near(r("North Coast", "carb_change"), -16.9, 0.05),
  near(r("Sierra Nevada", "carb_change"), -9.0, 0.05),
  near(r("North Coast", "change_mean"), -6.5, 0.05),
  near(r("Sierra Nevada", "change_mean"), -6.1, 0.05),
  near(r("North Coast", "area_ratio"), 1.7, 0.05), near(r("Sierra Nevada", "area_ratio"), 2.3, 0.05),
  near(r("North Coast", "density_min"), 88.7, 0.05), near(r("North Coast", "density_max"), 122.1, 0.05),
  all(woody_regions$members_losing == 20),
  near(min(woody_regions$start_mean), 5.0, 0.05), near(max(woody_regions$start_mean), 24.6, 0.05),
  near(min(woody_regions$end_mean), 0.4, 0.05), near(max(woody_regions$end_mean), 2.4, 0.05),
  near(w("San Joaquin Valley", "magic_kha") / sum(woody_regions$magic_kha), 0.70, 0.005),
  near(w("San Joaquin Valley", "start_mean"), 5.9, 0.05),
  near(w("San Joaquin Valley", "end_mean"), 0.7, 0.05),
  round(100 * share("Riverside", "Inland Deserts")) == 67,
  round(100 * share("San Bernardino", "Los Angeles")) == 55,
  round(100 * share("Solano", "Sacramento Valley")) == 83,
  round(100 * share("Mono", "Sierra Nevada")) == 52,
  round(100 * share("Los Angeles", "Inland Deserts")) == 95,
  round(100 * share("Ventura", "Central Coast")) == 97,
  setequal(largest_share$county[largest_share$share < 0.9],
           c("Riverside", "San Bernardino", "Solano", "Mono")),
  all(largest_share$share[largest_share$share >= 0.9] >= 0.95),
  near(split_effect, 0.6, 0.05),
  regions[which.max(abs(soil_regions$change_mean - majority_regions$change_mean))] == "Los Angeles",
  max(abs(carb_regions$endpoint_t_per_acre - vapply(regions, fig70_t, 0))) *
    t_per_acre_to_mg_per_ha < 0.1,
  all(others$change_min < -15), all(others$change_max > 0),
  all(fig63$area_change_million_acres > 0),
  near(min(by_region$area_ratio), 0.5, 0.05), near(max(by_region$area_ratio), 2.3, 0.05),
  by_region$region[which.min(by_region$area_ratio)] == "San Diego",
  by_region$region[which.max(by_region$area_ratio)] == "Sierra Nevada",
  identical(no_woody, c("Alpine", "Plumas", "Sierra")),
  near(max(undefined_acres$acres), 236, 0.5))

region_table <- data.frame(
  Region = by_region$region,
  `Area, thousand ha (MAGiC; CARB)` = paste0(fmt(by_region$magic_kha, 0), "; ",
                                              fmt(by_region$carb_kha, 0)),
  `MAGiC mean (median)` = paste0(fmt(by_region$change_mean), " (", fmt(by_region$change_median), ")"),
  `MAGiC member range` = paste0(fmt(by_region$change_min), " to ", fmt(by_region$change_max)),
  `Members losing` = paste(by_region$members_losing, "of 20"),
  `CARB, 2022 minus 2014` = fmt(by_region$carb_change),
  `CARB trend over 8 years (95% CI)` = paste0(fmt(by_region$trend_8yr), " (", fmt(by_region$trend_8yr_lower),
                                              " to ", fmt(by_region$trend_8yr_upper), ")"),
  check.names = FALSE)
writeLines(as.character(knitr::kable(region_table, format = "pipe", row.names = FALSE,
                                     align = c("l", rep("r", 6)))),
           file.path(out, "regional_table.md"))
utils::write.csv(by_region, file.path(out, "regional_soil_density_change.csv"), row.names = FALSE)
utils::write.csv(woody_regions, file.path(out, "regional_woody_biomass.csv"), row.names = FALSE)
utils::write.csv(stats::setNames(shares[order(shares$county, -shares$share), ],
                                 c("county", "region", "carb_cropland_acres_summed_2014_2022", "share")),
                 file.path(out, "county_region_shares.csv"), row.names = FALSE)

# Figure: each MAGiC member's regional change against CARB's change and trend.
level <- rev(by_region$region)
soil_members$y <- match(soil_members$region, level) + 0.15
by_region$y <- match(by_region$region, level)
q <- ggplot2::ggplot() +
  ggplot2::geom_vline(xintercept = 0, colour = "grey60") +
  ggplot2::geom_point(data = soil_members, ggplot2::aes(change_density, y, colour = "MAGiC member"),
                      shape = 16, size = 1.6, alpha = 0.5) +
  ggplot2::geom_point(data = by_region, ggplot2::aes(change_mean, y + 0.15, colour = "MAGiC mean"),
                      shape = 18, size = 4) +
  ggplot2::geom_errorbar(data = by_region, ggplot2::aes(xmin = trend_8yr_lower, xmax = trend_8yr_upper,
                                                        y = y - 0.15, colour = "CARB trend, 95% CI"),
                         width = 0.15, orientation = "y") +
  ggplot2::geom_point(data = by_region, ggplot2::aes(carb_change, y - 0.15, colour = "CARB 2022 minus 2014"),
                      shape = 15, size = 2.6) +
  ggplot2::geom_point(data = by_region, ggplot2::aes(trend_8yr, y - 0.15, colour = "CARB trend, 95% CI"),
                      shape = 21, fill = "white", size = 2.4, stroke = 1.1) +
  ggplot2::scale_y_continuous(breaks = seq_along(level), labels = level,
                              expand = ggplot2::expansion(add = 0.4)) +
  ggplot2::scale_colour_manual(
    values = c("MAGiC member" = "#0072B2", "MAGiC mean" = "#0072B2",
               "CARB 2022 minus 2014" = "#D55E00", "CARB trend, 95% CI" = "#D55E00"),
    breaks = c("MAGiC member", "MAGiC mean", "CARB 2022 minus 2014", "CARB trend, 95% CI")) +
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2, override.aes = list(
    shape = c(16, 18, 15, 21), size = c(1.6, 4, 2.6, 2.4), alpha = c(0.5, 1, 1, 1),
    fill = "white", stroke = c(0.5, 0.5, 0.5, 1.1), linetype = c(0, 0, 0, 1)))) +
  ggplot2::labs(x = "Soil carbon density change (Mg C/ha)", y = NULL, colour = NULL,
                caption = paste0("MAGiC: January 2016 to December 2023, soil plus litter, 20 parameter\n",
                                 "members, fixed fields. CARB: soil organic carbon in the top 30 cm; the\n",
                                 "trend is a line through the 2014-2022 annual densities, times 8 years.\n",
                                 "Regions ordered by MAGiC area.")) +
  ggplot2::theme_minimal(base_size = 13) +
  ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank(),
                 panel.grid.major.y = ggplot2::element_blank(),
                 plot.caption.position = "plot", plot.caption = ggplot2::element_text(hjust = 0))
ggplot2::ggsave(file.path(out, "regional_density_change.png"), q, width = 7.5, height = 6, dpi = 180,
                bg = "white")
writeLines(c("Frozen input checksums verified; the quoted values above are reproduced.",
             capture.output(utils::sessionInfo())), file.path(out, "verification.txt"))
