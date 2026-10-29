#!/usr/bin/env Rscript
# Split the Russell Ranch treatment events into one file per rotation phase, and rebuild
# fertilization (synthetic N and compost) from the Century Experiment package.
#
# Each Century system is two (or more) sets of three plots on offset rotations, so in any
# year one phase grows corn and the other tomato. The generator that wrote
# generator_stacked/ put every phase's events into one file, so a single simulated field
# was planted, fertilized and harvested for both crops each year. The package carries a
# plot id on every operation and plot_system.csv gives each plot's rotation phase, which is
# what lets the events be separated.
#
# usage: russell_split_phases.R <generator_stacked_dir> <century_dir> <out_dir> [tillage_medians_csv [irrigation_medians_csv]]
#   century_dir: the extracted RR_2014_datasets/ folder from the Wolf et al. (2018) data
#   paper supporting information, doi 10.1002/ecy.2105.
#   tillage_medians_csv: written by russell_monitoring_tillage.R; defaults to
#   monitoring_tillage_near_russell.csv next to generator_stacked_dir.
#   irrigation_medians_csv: written by russell_monitoring_irrigation.R; defaults to
#   monitoring_irrigation_near_russell.csv next to generator_stacked_dir.

suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 3:5)
  stop("usage: russell_split_phases.R <generator_stacked_dir> <century_dir> <out_dir> [tillage_medians_csv [irrigation_medians_csv]]")
stacked_dir <- args[1]; century_dir <- args[2]; out_dir <- args[3]
tillage_csv <- if (length(args) >= 4L) args[4] else file.path(dirname(stacked_dir), "monitoring_tillage_near_russell.csv")
irrigation_csv <- if (length(args) == 5L) args[5] else file.path(dirname(stacked_dir), "monitoring_irrigation_near_russell.csv")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

SYSTEMS <- c(
  alf_corn_tomato = "Alfalfa/Corn/Tomato",
  conv_corn_tomato = "Conventional Corn/Tomato",
  conv_wheat_tomato = "Conventional Wheat/Tomato",
  irr_wheat_control = "Irrigated Wheat Control",
  irr_wheat_fallow = "Irrigated Wheat/Fallow",
  irr_wheat_legume = "Irrigated Wheat/Legume",
  leg_corn_tomato = "Legume/Corn/Tomato",
  org_corn_tomato = "Organic Corn/Tomato",
  rf_wheat_control = "Rainfed Wheat Control",
  rf_wheat_fallow = "Rainfed Wheat/Fallow",
  rf_wheat_legume = "Rainfed Wheat/Legume",
  transitional = "Transitional")

# Tautges et al. (2019) Table 1 lists irrigation "None" for the rainfed wheat systems
RAINFED <- c("rf_wheat_control", "rf_wheat_fallow", "rf_wheat_legume")
CASH_CROPS <- c("corn", "tomato", "wheat", "alfalfa", "sudangrass")
SEASON_DAYS <- 365  # longest planting-to-harvest span that counts as one cash crop window
SOURCE <- "10.1002/ecy.2105"
TON_AC_TO_KG_M2 <- 907.18474 / 4046.8564224  # US short ton per acre (per David)
KG_HA_TO_KG_M2 <- 1e-4

# Harvest fractions from the harvest lookup the other calibration sites use (rows as given
# by Akash on PR #10). Aboveground removed and to litter; roots all go to litter.
HARVEST_LOOKUP <- data.frame(
  crop = c("corn", "tomato", "wheat", "alfalfa"),
  lookup_row = c("F16", "T32", "G2", "P1"),
  above_removed = c(0.752, 0.33, 0.713, 0.85),
  above_to_litter = c(0.248, 0.67, 0.287, 0.15),
  stringsAsFactors = FALSE)
# Sudangrass has no lookup row and needs none: the package metadata says that in 2008 and 2009
# it was sampled before plowing under and no hay was removed, so it is a green manure.
GREEN_MANURE <- c("cover crop", "sudangrass")
WCC_WINDOW_DAYS <- 240  # a cover crop is incorporated within this many days of planting
# Alfalfa is cut several times a year. An intermediate cutting removes the lookup's
# aboveground share and leaves the rest as living stubble, with the roots alive (David on
# PR #10: "0.85, 0, 0, 0"); only the stand's last cutting before another crop takes the
# full P1 row.
ALFALFA_CUT <- c(above_removed = 0.85, below_removed = 0, above_to_litter = 0, below_to_litter = 0)
CROP_DISPLAY <- c(corn = "Corn", tomato = "Tomato", wheat = "Wheat", alfalfa = "Alfalfa",
                  sudangrass = "Sudangrass", "cover crop" = "Cover Crop")
# The experiment's first operations are in fall 1993; the 1992 and 1993 sudangrass
# uniformity crops before it are not in these files. The run ends with 2014, a year the
# package's operation logs no longer cover; crops still growing then are left running.
FIRST_DATE <- as.Date("1993-09-01")
LOGS_END <- as.Date("2013-12-31")
LAST_DATE <- as.Date("2014-12-31")
# A missing date comes from the package's own records for the same system, and a filled
# season's irrigation from the treatment's generator events, when there are at least
# MIN_MEDIAN_N of them, otherwise from the whole site (tools/event_prep/README.md, "Filling
# missing events").
MIN_MEDIAN_N <- 5
FERT_LEAD_DAYS <- 90  # fertilization up to this many days before a planting belongs to its season
# Alfalfa/Corn/Tomato has no corn season before 2014 to copy fertilization from
COMPARABLE <- c(alf_corn_tomato = "conv_corn_tomato")

rd <- function(f, enc = "UTF-8")
  read.csv(file.path(century_dir, f), stringsAsFactors = FALSE, check.names = FALSE,
           fileEncoding = enc)
as_date <- function(x) {
  d <- as.Date(x, format = "%m/%d/%Y")
  d[is.na(d)] <- as.Date(x[is.na(d)], format = "%Y-%m-%d")
  d
}

# (system, plot) -> rotation phase. Keyed on both because six plots moved from Irrigated
# Wheat/Legume to Alfalfa/Corn/Tomato. "unassigned" rows are years before a plot joined.
ps <- rd("plot_system.csv", "CP1252")
ps <- ps[ps[["harvest_year_rotation_order_(even-odd)"]] != "unassigned", ]
sp <- function(system, plot) paste(system, plot, sep = "|")
phase_of <- tapply(ps[["harvest_year_rotation_order_(even-odd)"]], sp(ps$new_system_name, ps$plot),
                   function(v) { u <- unique(v); stopifnot(length(u) == 1L); u })

plt <- rd("operations_planting.csv")
# In 2003 and 2005 Organic Corn/Tomato plot 6-8 grew corn and 8-8 tomato (plot_system.csv,
# tomato_harvests_all.csv), but operations_planting.csv lists the tomato transplanting under
# 6-8, next to its own corn seeding, and none under 8-8. Without this the corn phase gets a
# tomato planting that is never harvested.
PLANT_PLOT_FIXES <- data.frame(system_name = "Organic Corn/Tomato", Date = c("5/8/2003", "5/13/2005"),
                               Crop_planted = "Tomato", from = "6-8", to = "8-8")
for (i in seq_len(nrow(PLANT_PLOT_FIXES))) {
  f <- PLANT_PLOT_FIXES[i, ]
  same <- plt$system_name == f$system_name & plt$Date == f$Date & plt$Crop_planted == f$Crop_planted
  stopifnot(sum(same & plt$plot == f$from) == 1L, !any(same & plt$plot == f$to))
  plt$plot[same & plt$plot == f$from] <- f$to
}
hrv <- rd("operations_harvest.csv")
# operations_harvest.csv also lists the 7/1/1999 Rainfed Wheat/Legume wheat harvest under
# plot 7-3, a wheat-CC plot that grew a cover crop that winter (plot_system.csv); the three
# CC-wheat plots carry the harvest. Kept, the wheat-CC phase harvests a wheat it never planted.
HARVEST_RECORD_DROPS <- data.frame(system_name = "Rainfed Wheat/Legume", date = "7/1/1999",
                                   crop_harvested = "Wheat", plot = "7-3")
for (i in seq_len(nrow(HARVEST_RECORD_DROPS))) {
  f <- HARVEST_RECORD_DROPS[i, ]
  drop <- hrv$system_name == f$system_name & hrv$date == f$date & hrv$crop_harvested == f$crop_harvested & hrv$plot == f$plot
  stopifnot(sum(drop) == 1L)
  hrv <- hrv[!drop, ]
}
frt <- rd("operations_fertilizers.csv")
cmp <- rd("operations_compost.csv")
ana <- rd("compost_analyses_summary.csv")
wcc <- rd("wcc_harvests_all.csv")
alf <- rd("alfalfa_harvests_all.csv")

# Operation rows whose (system, plot) has no rotation phase cannot go to any phase file.
# None of them feeds an event, but they are printed rather than dropped silently.
unmapped <- function(file, system, plot, date, what)
  cat(sprintf("%s: %s plot %s, %s, %s: no rotation phase in plot_system.csv (dropped)\n",
              file, system, plot, format(date), what), sep = "")

op_table <- function(df, file, date_col, crop_col, what = df[[crop_col]]) {
  d <- data.frame(system = df$system_name, plot = df$plot, date = as_date(df[[date_col]]),
                  crop = tolower(df[[crop_col]]), stringsAsFactors = FALSE)
  d$phase <- unname(phase_of[sp(d$system, d$plot)])
  miss <- is.na(d$phase)
  unmapped(file, d$system[miss], d$plot[miss], d$date[miss], what[miss])
  d[!miss & !is.na(d$date), ]
}
ops <- list(planting = op_table(plt, "operations_planting.csv", "Date", "Crop_planted",
                                paste(plt$Crop_planted, plt$material_quantity, plt$material_units)),
            harvest = op_table(hrv, "operations_harvest.csv", "date", "crop_harvested"))
# The Transitional plots grew corn in 2006, not tomato: plot_system.csv lists corn planted
# 5/25 and harvested 9/13 ("Corn planted instead of tomato"), corn_harvests_all.csv has corn
# samples dated 10/24/2006, and tomato_harvests_all.csv has none that year. The logs record a
# tomato transplanting and harvest on those dates for the three plots; those records and the
# generator's events made from them are dropped, and plot_system.csv fills the corn.
WRONG_CROP_DROPS <- data.frame(tid = "transitional", event_type = c("planting", "harvest"),
                               date = c("2006-05-25", "2006-09-13"), crop = "Tomato",
                               plots = "2-2, 5-7, 7-4")
for (i in seq_len(nrow(WRONG_CROP_DROPS))) {
  f <- WRONG_CROP_DROPS[i, ]; o <- ops[[f$event_type]]
  drop <- o$system == SYSTEMS[[f$tid]] & o$date == as.Date(f$date) & o$crop == tolower(f$crop)
  stopifnot(identical(sort(o$plot[drop]), strsplit(f$plots, ", ")[[1]]))
  ops[[f$event_type]] <- o[!drop, ]
}

# Compost %C and %N for the year it was applied. Tautges et al. 2019 measured compost on the
# in-house Costech each year, so those replicates are averaged where they exist (2011-2013
# also carry a single external-lab N that runs higher); other years have one lab only.
# Years with no analysis take the mean over measured years and are tagged "assumed".
pct <- function(param) {
  a <- ana[ana$compost_analysis_parameter == param, ]
  a$v <- as.numeric(a$analysis_value)
  sapply(split(a, a$year), function(y) {
    costech <- y$analytical_lab == "In-house Costech"
    mean(if (any(costech)) y$v[costech] else y$v)
  })
}
c_pct <- pct("Total C"); n_pct <- pct("Total N")
c_mean <- mean(c_pct); n_mean <- mean(n_pct)

# The three plots of a phase stand in for one simulated field, so every amount is a field
# average: the sum over the plots treated on a date divided by the phase's plot count. When
# plots were treated on different days the amounts split across those dates and still add
# up to one application.
ph_plots <- unique(ps[, c("new_system_name", "plot", "harvest_year_rotation_order_(even-odd)")])
n_plots <- table(sp(ph_plots$new_system_name, ph_plots[["harvest_year_rotation_order_(even-odd)"]]))
field_mean <- function(df, value) {
  s <- aggregate(df[[value]], by = df[c("system_name", "phase", "date")], FUN = sum)
  s$value <- s$x / as.numeric(n_plots[sp(s$system_name, s$phase)])
  s$n_plots_treated <- aggregate(df$plot, by = df[c("system_name", "phase", "date")],
                                 FUN = function(p) length(unique(p)))$x
  s[, c("system_name", "phase", "date", "value", "n_plots_treated")]
}

frt$date <- as_date(frt$date)
undated <- frt[is.na(frt$date), ]
cat(sprintf("operations_fertilizers rows without a usable date: %d, total N %.2f kg/ha (dropped)\n",
            nrow(undated), sum(as.numeric(undated[["nitrogen_applied_kg/ha"]]), na.rm = TRUE)))
frt <- frt[!is.na(frt$date), ]
frt$n <- as.numeric(frt[["nitrogen_applied_kg/ha"]])
# Excel turned one plot id into a date: "5-Jan" is plot 1-5 (Conventional Wheat/Tomato,
# 11/5/2011, Can_27, 111.97 kg N/ha).
FERT_PLOT_FIXES <- c("5-Jan" = "1-5")
fix <- frt$plot %in% names(FERT_PLOT_FIXES)
frt$plot[fix] <- FERT_PLOT_FIXES[frt$plot[fix]]
frt$phase <- unname(phase_of[sp(frt$system_name, frt$plot)])
miss <- is.na(frt$phase)
unmapped("operations_fertilizers.csv", frt$system_name[miss], frt$plot[miss], frt$date[miss],
         paste(frt$material_applied[miss], frt$n[miss], "kg N/ha"))
frt <- frt[!miss, ]
frt <- unique(frt)  # the package repeats some plot rows verbatim
frt <- frt[!is.na(frt$n) & frt$n > 0, ]
# Known duplicate records: the same application listed on two dates. The 2011 wheat
# pre-plant on the Conventional Wheat/Tomato wheat plots appears on 11/5 and again on 11/14
# at the same rate, while every other wheat year has one. As with compost, it is kept once
# per plot on the earlier date. Listed explicitly, not deduplicated by rule, because split
# applications are real (Conventional Corn/Tomato 1996 tomato: 56.55 kg N/ha on 4/16 and 5/13).
FERT_DUPLICATES <- data.frame(
  system_name = "Conventional Wheat/Tomato", material_applied = "Can_27", n = 111.97,
  keep = as.Date("2011-11-05"), drop = as.Date("2011-11-14"))
for (i in seq_len(nrow(FERT_DUPLICATES))) {
  d <- FERT_DUPLICATES[i, ]
  rec <- frt$system_name == d$system_name & frt$material_applied == d$material_applied & frt$n == d$n
  drop <- rec & frt$date == d$drop
  stopifnot(any(drop), setequal(frt$plot[drop], frt$plot[rec & frt$date == d$keep]))
  cat(sprintf("fertilizer records repeated in the package: %s %s %.2f kg N/ha on %s dropped for plots %s (kept %s)\n",
              d$system_name, d$material_applied, d$n, format(d$drop),
              paste(sort(frt$plot[drop]), collapse = ", "), format(d$keep)))
  frt <- frt[!drop, ]
}
fert_n <- field_mean(frt, "n")
mats <- aggregate(material_applied ~ system_name + phase + date, data = frt,
                  FUN = function(m) paste(sort(unique(m)), collapse = "; "))
fert_n <- merge(fert_n, mats, all.x = TRUE)

cmp$date <- as_date(cmp$date)
cmp$wet <- as.numeric(cmp$compost_applied_wet_weight)
cmp$phase <- unname(phase_of[sp(cmp$system_name, cmp$plot)])
stopifnot(all(cmp$material_units == "tons/acre"), !anyNA(cmp$phase), !anyNA(cmp$date))
# The package lists every plot's compost history twice. The two copies agree except for
# 2005 on plots 2-3, 6-4 and 6-8, dated 4/20 in one and 5/20 in the other at the same
# 4 t/ac, which unique() alone would keep as two applications. Compost went on once a
# year, so keep one per plot and year, on the earlier date: it falls in the "March or
# April" window Tautges et al. (2019) give for compost.
cmp <- cmp[order(cmp$system_name, cmp$plot, cmp$date), c("system_name", "phase", "date", "plot", "wet")]
cmp$year <- format(cmp$date, "%Y")
same_wet <- tapply(cmp$wet, paste(cmp$system_name, cmp$plot, cmp$year), function(w) length(unique(w)) == 1L)
if (!all(same_wet)) stop("a plot-year has differing compost amounts: ", paste(names(same_wet)[!same_wet], collapse = ", "))
dup <- duplicated(cmp[, c("system_name", "plot", "year")])
dropped <- cmp[dup & !duplicated(cmp[, c("system_name", "plot", "date")]), ]
cat(sprintf("compost rows repeated in the package: %d; second-copy dates dropped: %s\n", sum(dup),
            if (nrow(dropped)) paste(sprintf("%s %s", dropped$plot, format(dropped$date)), collapse = ", ") else "none"))
cmp <- cmp[!dup, ]
compost <- field_mean(cmp, "wet")

fert_events <- function(sys, ph, last_year) {
  out <- list()
  f <- fert_n[fert_n$system_name == sys & fert_n$phase == ph, ]
  for (i in seq_len(nrow(f))) {
    if (as.integer(format(f$date[i], "%Y")) > last_year) next
    out[[length(out) + 1L]] <- list(
      event_type = "fertilization", date = format(f$date[i]),
      nh4_n_kg_m2 = round(f$value[i] * KG_HA_TO_KG_M2, 7),
      source = paste0(SOURCE, ":operations_fertilizers.csv"),
      material = f$material_applied[i], n_plots_treated = f$n_plots_treated[i],
      provenance_class = "published",
      provenance_note = paste(
        "Total N applied, field average over this phase's plots. Written as mineral N in",
        "nh4_n_kg_m2; SIPNET reads nh4 + no3 as one mineral pool, so the split does not",
        "reach the model."))
  }
  k <- compost[compost$system_name == sys & compost$phase == ph, ]
  for (i in seq_len(nrow(k))) {
    yr <- format(k$date[i], "%Y")
    if (as.integer(yr) > last_year) next
    cp <- if (yr %in% names(c_pct)) c_pct[[yr]] else c_mean
    np <- if (yr %in% names(n_pct)) n_pct[[yr]] else n_mean
    measured <- yr %in% names(c_pct) && yr %in% names(n_pct)
    mass <- k$value[i] * TON_AC_TO_KG_M2
    out[[length(out) + 1L]] <- list(
      event_type = "fertilization", date = format(k$date[i]),
      org_c_kg_m2 = round(mass * cp / 100, 7), org_n_kg_m2 = round(mass * np / 100, 7),
      source = paste0(SOURCE, ":operations_compost.csv+compost_analyses_summary.csv"),
      material = "composted poultry manure", n_plots_treated = k$n_plots_treated[i],
      compost_wet_tons_acre = round(k$value[i], 4), compost_total_c_pct = round(cp, 4),
      compost_total_n_pct = round(np, 4),
      provenance_class = if (measured) "derived" else "assumed",
      provenance_note = sprintf(paste(
        "Wet tons/acre (US short ton) x %%C and %%N on the reported tonnage. C from %s, N from %s.",
        "This basis reproduces Tautges et al. 2019: ~2.1 Mg C/ha per application year",
        "(40.4 Mg C/ha over 19 years) and 150-200 kg N/ha."),
        if (yr %in% names(c_pct)) paste("the", yr, "analysis") else "the mean of measured years",
        if (yr %in% names(n_pct)) paste("the", yr, "analysis") else "the mean of measured years"))
  }
  out
}

op_match <- function(kind, sys, e) {
  o <- ops[[kind]]
  o[o$system == sys & o$date == as.Date(e$date) & o$crop == tolower(e$crop_display), ]
}
phases_for <- function(kind, sys, e) unique(op_match(kind, sys, e)$phase)
plots_for <- function(kind, sys, e, ph) {
  m <- op_match(kind, sys, e)
  sort(unique(m$plot[m$phase == ph]))
}

# One planting or harvest of a crop is often recorded on several dates: plots of the phase
# done on different days, or the same plots over a multi-day job ("wheat Harvest" on two
# days then "Swath1", corn "Machine Harvest" then "Cleanup"). The generator made each date
# its own event, so the model harvested the same crop two or three times. Same-crop
# operations in a phase-year merge when they fall within MERGE_DAYS of the first, or touch
# disjoint plots; the merged event takes the date most plots share (earliest on a tie) and,
# for a planting, the mean of the generator's amounts (a harvest takes the lookup fractions
# later). Alfalfa cuttings, about a month apart, stay separate.
MERGE_DAYS <- 14
AMOUNT_FIELDS <- c("leaf_c_kg_m2", "wood_c_kg_m2", "fine_root_c_kg_m2", "coarse_root_c_kg_m2")
merge_events <- function(grp, plots) {
  if (length(grp) == 1L) return(grp[[1]])
  base <- grp[[order(-lengths(plots), vapply(grp, `[[`, "", "date"))[1]]]
  avg <- intersect(AMOUNT_FIELDS, names(base))
  for (f in avg)
    base[[f]] <- round(mean(vapply(grp, function(e) as.numeric(e[[f]]), 0)), 4)
  base$merged_dates <- paste(vapply(grp, `[[`, "", "date"), collapse = ";")
  base$merge_note <- paste(c(
    sprintf("One operation recorded on %d dates; dated by the day most plots share (earliest on a tie).",
            length(grp)),
    if (length(avg)) "Generator amounts averaged.",
    if (base$event_type == "harvest") "Fractions from the harvest lookup."), collapse = " ")
  base
}
merge_split_days <- function(pe, sys, ph) {
  is_ph <- vapply(pe, function(e) e$event_type %in% c("planting", "harvest"), TRUE)
  key <- ifelse(is_ph, vapply(pe, function(e) paste(e$event_type, tolower(e$crop_display),
                                                     substr(e$date, 1, 4)), ""), NA)
  out <- pe[!is_ph]; n_merged <- 0L
  for (k in unique(key[is_ph])) {
    grp <- pe[which(key == k)]
    grp <- grp[order(vapply(grp, `[[`, "", "date"))]
    plots <- lapply(grp, function(e) plots_for(e$event_type, sys, e, ph))
    cl <- list(); cl_plots <- list(); cur <- 1L
    for (i in seq_along(grp)) {
      if (i > 1L) {
        start <- as.Date(grp[[cl[[cur]][1]]]$date)
        near <- as.numeric(as.Date(grp[[i]]$date) - start) <= MERGE_DAYS
        disjoint <- !length(intersect(plots[[i]], cl_plots[[cur]]))
        if (!(near || disjoint)) cur <- cur + 1L
      }
      cl[[cur]] <- c(if (cur <= length(cl)) cl[[cur]], i)
      cl_plots[[cur]] <- union(if (cur <= length(cl_plots)) cl_plots[[cur]], plots[[i]])
    }
    for (idx in cl) out <- c(out, list(merge_events(grp[idx], plots[idx])))
    n_merged <- n_merged + length(grp) - length(cl)
  }
  attr(out, "n_merged") <- n_merged
  out
}

# The date most of a phase's plots share, earliest on a tie
shared_date <- function(d) {
  tab <- table(d)
  as.Date(names(tab)[tab == max(tab)][1])
}
first_date <- function(x) {
  m <- regmatches(x, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}", x))
  if (!length(m)) return(as.Date(NA))
  as_date(m)
}
# Groups dates into operations: a new one starts more than `days` after the current one's first date
cluster_dates <- function(d, days) {
  g <- integer(length(d)); cur <- 0L; start <- as.Date(NA)
  for (i in order(d)) {
    if (is.na(start) || as.numeric(d[i] - start) > days) { cur <- cur + 1L; start <- d[i] }
    g[i] <- cur
  }
  g
}
yday <- function(d) as.POSIXlt(d)$yday + 1L
# The first date after `after` that falls on day of year `doy`
doy_after <- function(after, doy) {
  y <- as.integer(format(after, "%Y"))
  d <- as.Date(sprintf("%d-01-01", y)) + doy - 1
  if (d <= after + 30) d <- as.Date(sprintf("%d-01-01", y + 1L)) + doy - 1
  d
}
dates_of <- function(evs) as.Date(vapply(evs, `[[`, "", "date"))

# plot_system.csv records every plot-year's planting and harvest, including operations the
# logs lack and all of 2014, which the logs do not reach.
ps_ops <- function(what) do.call(rbind, lapply(c("A", "B"), function(k) data.frame(
  system = ps$new_system_name, plot = ps$plot, phase = ps[["harvest_year_rotation_order_(even-odd)"]],
  crop = tolower(ps[[sprintf("crop_%s_%s", k, if (what == "planting") "planted" else "harvested")]]),
  date = do.call(c, lapply(ps[[sprintf("crop_%s_date_%s", k, if (what == "planting") "planted" else "harvested")]], first_date)),
  raw = ps[[sprintf("crop_%s_date_%s", k, if (what == "planting") "planted" else "harvested")]],
  stringsAsFactors = FALSE)))
ps_harvests <- ps_ops("harvest")
ps_harvests <- ps_harvests[!is.na(ps_harvests$date) & ps_harvests$crop %in% CASH_CROPS, ]
ps_plantings <- ps_ops("planting")
ps_plantings <- ps_plantings[!is.na(ps_plantings$date) & ps_plantings$crop %in% names(CROP_DISPLAY) &
                               ps_plantings$date >= FIRST_DATE & ps_plantings$date <= LAST_DATE, ]

# A filled planting takes the median amounts of the generator's plantings of the same crop in
# the phase, or across the site when the phase has none.
planting_amount <- function(crop, phase_pool) {
  for (pool in list(list(phase_pool, "this phase's"), list(site_plantings, "the site's"))) {
    same <- Filter(function(e) tolower(e$crop_display) == crop, pool[[1]])
    if (!length(same)) next
    f <- intersect(AMOUNT_FIELDS, unique(unlist(lapply(same, names))))
    vals <- setNames(lapply(f, function(k)
      round(median(vapply(same, function(e) if (is.null(e[[k]])) NA_real_ else as.numeric(e[[k]]), 0), na.rm = TRUE), 4)), f)
    return(list(fields = vals, note = sprintf("%s<-median of %s %d generator %s plantings",
                                              paste(f, collapse = "+"), pool[[2]], length(same), CROP_DISPLAY[[crop]])))
  }
  stop("no ", crop, " planting to take an amount from")
}

# Plantings that plot_system.csv records but operations_planting.csv lacks (25 cash crop
# seasons that were harvested with no planting before them, whole cover crop seasons, and all
# of 2014). A planting of the same crop within 30 days counts as the same operation; a cash
# crop with a logged planting of another cash crop within 30 days is a conflict between the
# files, printed and not filled, so one field is never planted with two cash crops.
missing_plantings <- function(sys, ph, pe) {
  m <- ps_plantings[ps_plantings$system == sys & ps_plantings$phase == ph, ]
  pl <- Filter(function(e) e$event_type == "planting", pe)
  out <- list()
  for (crop in unique(m$crop)) {
    mc <- m[m$crop == crop, ]
    have <- dates_of(Filter(function(e) tolower(e$crop_display) == crop, pl))
    other <- if (crop %in% CASH_CROPS)
      Filter(function(e) tolower(e$crop_display) %in% setdiff(CASH_CROPS, crop), pl) else list()
    cl <- cluster_dates(mc$date, 30)
    for (g in unique(cl)) {
      s <- mc[cl == g, ]
      d <- shared_date(s$date)
      if (any(abs(as.numeric(have - d)) <= 30)) next
      clash <- Filter(function(e) abs(as.numeric(as.Date(e$date) - d)) <= 30, other)
      if (length(clash)) {
        cat(sprintf("%s %s: plot_system.csv %s planting %s conflicts with the logged %s planting %s (not filled)\n",
                    sys, ph, CROP_DISPLAY[[crop]], format(d), clash[[1]]$crop_display, clash[[1]]$date))
        next
      }
      amt <- planting_amount(crop, pl)
      out[[length(out) + 1L]] <- c(
        list(event_type = "planting", date = format(d), source = paste0(SOURCE, ":plot_system.csv"),
             crop_code = CROP_DISPLAY[[crop]], crop_display = CROP_DISPLAY[[crop]]),
        amt$fields,
        list(prior_filled = amt$note, provenance_class = "published",
             provenance_note = sprintf(paste(
               "Missing from operations_planting.csv; date from plot_system.csv crop_*_date_planted",
               "(%s), the date most of the phase's plots share."), paste(unique(s$raw), collapse = "; "))))
    }
  }
  out
}

# Alfalfa cuttings missing from operations_harvest.csv (all of 2014): alfalfa_harvests_all.csv
# has a sample "at each alfalfa cutting" (Wolf et al. 2018 metadata).
alf$base_plot <- sub("[EW]$", "", alf$plot)
alf$date <- as_date(alf$date)
alf$phase <- unname(phase_of[sp(alf$system_name, alf$base_plot)])
missing_cuttings <- function(sys, ph, pe) {
  a <- alf[!is.na(alf$phase) & alf$system_name == sys & alf$phase == ph & !is.na(alf$date) & alf$date <= LAST_DATE, ]
  if (!nrow(a)) return(list())
  have <- dates_of(Filter(function(e) e$event_type == "harvest" && tolower(e$crop_display) == "alfalfa", pe))
  cl <- cluster_dates(a$date, 7)
  out <- list()
  for (g in unique(cl)) {
    d <- shared_date(a$date[cl == g])
    if (any(abs(as.numeric(have - d)) <= 7)) next
    out[[length(out) + 1L]] <- list(
      event_type = "harvest", date = format(d), source = paste0(SOURCE, ":alfalfa_harvests_all.csv"),
      crop_display = "Alfalfa", provenance_class = "published",
      provenance_note = "Missing from operations_harvest.csv; dated by the alfalfa_harvests_all.csv sample taken at the cutting.")
  }
  out
}

# Some cash crop harvests are missing from operations_harvest.csv although the crop was
# harvested (e.g. Conventional Corn/Tomato tomato 1998), and the logs stop before 2014. A cash
# crop planting with no same-crop harvest within SEASON_DAYS takes the plot_system.csv harvest
# date most of the phase's plots share. A crop with no harvest in either (Organic Corn/Tomato
# wheat planted 2011, "NOT harvested for wheat in 2012") ends with all biomass to litter on a
# date imputed later (impute_date); one still growing at the end of the run is left running.
missing_harvests <- function(sys, ph, pe) {
  pl <- Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe)
  hv <- Filter(function(e) e$event_type == "harvest", pe)
  out <- list()
  for (p in pl) {
    crop <- tolower(p$crop_display); pd <- as.Date(p$date)
    has <- any(vapply(hv, function(h) tolower(h$crop_display) == crop &&
                        as.Date(h$date) > pd && as.numeric(as.Date(h$date) - pd) <= SEASON_DAYS, TRUE))
    if (has) next
    later_planting <- any(vapply(pl, function(q) tolower(q$crop_display) == crop &&
                                   as.Date(q$date) > pd && as.Date(q$date) <= pd + 30, TRUE))
    if (later_planting) next  # a replant; the harvest belongs to the later planting
    m <- ps_harvests[ps_harvests$system == sys & ps_harvests$phase == ph & ps_harvests$crop == crop &
                       ps_harvests$date > pd & as.numeric(ps_harvests$date - pd) <= SEASON_DAYS, ]
    if (!nrow(m)) {
      if (pd > LAST_DATE - 240) next  # still growing when the run ends
      cat(sprintf("%s %s: %s planted %s has no harvest record; ends on an imputed date\n",
                  sys, ph, p$crop_display, p$date))
      out[[length(out) + 1L]] <- list(
        event_type = "harvest", date = NA_character_, source = paste0(SOURCE, ":operations_planting.csv"),
        crop_display = p$crop_display, frac_above_removed_0to1 = 0, frac_below_removed_0to1 = 0,
        frac_above_to_litter_0to1 = 1, frac_below_to_litter_0to1 = 1, not_harvested = TRUE,
        provenance_class = "imputed",
        provenance_note = "No harvest in operations_harvest.csv or plot_system.csv; the crop ends with all biomass to litter.",
        impute = list(kind = "harvest_doy", crop = crop, after = p$date))
      next
    }
    hd <- shared_date(m$date)
    out[[length(out) + 1L]] <- list(
      event_type = "harvest", date = format(hd), source = paste0(SOURCE, ":plot_system.csv"),
      crop_display = p$crop_display, frac_above_removed_0to1 = NA,
      provenance_class = "published",
      provenance_note = sprintf(paste(
        "Missing from operations_harvest.csv; date from plot_system.csv crop_*_date_harvested",
        "(%s), the date most of the phase's plots share."),
        paste(unique(m$raw), collapse = "; ")))
  }
  out
}

# Cover crop termination. wcc_harvests_all.csv dates each cover crop sample by "the date of
# the WCC incorporation" (data dictionary; the methods put the sample in the week before
# it), so each cover crop ends on that date, the one most of the phase's plots share, with
# all biomass to litter. Where a planting has no sample, plot_system.csv's cover crop
# harvest date is used (it equals the sample date in 342 of 353 plot-years). A recorded date
# after the next cash crop planting cannot be the incorporation (2004 is 5/17 for every plot
# of every system, after the 5/2 and 5/5 corn and tomato plantings); that and a cover crop
# with no date at all end on a date imputed later (impute_date).
cc_dates <- rbind(
  data.frame(system = wcc$system_name, plot = sub("[EW]$", "", wcc$plot), date = as_date(wcc$date),
             src = "wcc_harvests_all.csv", stringsAsFactors = FALSE),
  data.frame(system = ps$new_system_name, plot = ps$plot,
             date = do.call(c, lapply(ps$crop_B_date_harvested, first_date)),
             src = "plot_system.csv", stringsAsFactors = FALSE)[ps$crop_B_harvested %in% "Cover Crop", ])
cc_dates$phase <- unname(phase_of[sp(cc_dates$system, cc_dates$plot)])
cc_dates <- cc_dates[!is.na(cc_dates$phase) & !is.na(cc_dates$date), ]
CC_NOTES <- c(
  wcc_harvests_all.csv = "Dated by the WCC incorporation date in wcc_harvests_all.csv.",
  plot_system.csv = "No cover crop sample for this planting; dated by the cover crop harvest date in plot_system.csv.")
cover_crop_ends <- function(sys, ph, pe) {
  cc <- Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) == "cover crop", pe)
  cash <- dates_of(Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe))
  out <- list()
  for (p in cc) {
    pd <- as.Date(p$date)
    s <- cc_dates[cc_dates$system == sys & cc_dates$phase == ph & cc_dates$date > pd &
                    as.numeric(cc_dates$date - pd) <= WCC_WINDOW_DAYS, ]
    nxt <- cash[cash > pd]
    ev <- list(event_type = "harvest", date = NA_character_, crop_display = "Cover Crop",
               frac_above_removed_0to1 = 0, frac_below_removed_0to1 = 0,
               frac_above_to_litter_0to1 = 1, frac_below_to_litter_0to1 = 1)
    if (nrow(s)) {
      src <- names(CC_NOTES)[names(CC_NOTES) %in% s$src][1]
      s <- s[s$src == src, ]
      d <- shared_date(as.Date(tapply(s$date, s$plot, min), origin = "1970-01-01"))
      if (!any(nxt < d)) {
        out[[length(out) + 1L]] <- modifyList(ev, list(
          date = format(d), source = paste0(SOURCE, ":", src), provenance_class = "published",
          provenance_note = paste("Cover crop termination.", CC_NOTES[[src]])))
        next
      }
      note <- sprintf("The recorded date (%s, %s) is after the next cash crop planting.", format(d), src)
    } else {
      if (pd > LAST_DATE - WCC_WINDOW_DAYS) next  # still growing when the run ends
      note <- "No incorporation date for this planting."
    }
    out[[length(out) + 1L]] <- modifyList(ev, list(
      source = paste0(SOURCE, ":operations_planting.csv"), provenance_class = "imputed",
      provenance_note = paste("Cover crop termination.", note),
      impute = if (length(nxt)) list(kind = "cc_gap", next_cash = format(min(nxt)), after = p$date)
               else list(kind = "cc_doy", after = p$date)))
  }
  out
}

# Harvests take the lookup fractions, or all to litter for a green manure; the generator's
# harvest prior is dropped.
apply_lookup <- function(e) {
  if (e$event_type != "harvest") return(e)
  if (isTRUE(e$not_harvested)) return(e)
  crop <- tolower(e$crop_display)
  if (crop %in% GREEN_MANURE) {
    e$frac_above_removed_0to1 <- 0
    e$frac_above_to_litter_0to1 <- 1
    if (crop == "sudangrass")
      e$harvest_fraction_note <- paste("Plowed under with no hay removed (2008 and 2009 sudangrass,",
                                       "Wolf et al. 2018 metadata).")
  } else {
    r <- HARVEST_LOOKUP[HARVEST_LOOKUP$crop == crop, ]
    if (!nrow(r)) stop(sprintf("%s harvest on %s has no harvest lookup row", e$crop_display, e$date))
    e$frac_above_removed_0to1 <- r$above_removed
    e$frac_above_to_litter_0to1 <- r$above_to_litter
    e$harvest_lookup_row <- r$lookup_row
  }
  e$frac_below_removed_0to1 <- 0
  e$frac_below_to_litter_0to1 <- 1
  e$prior_filled <- NULL
  e
}

# An alfalfa harvest followed by another before the next planting is an intermediate cutting
# and leaves the stand alive; the last one before the next planting ends it with the full P1
# row. A stand still growing at the end of the run is never ended.
alfalfa_cuts <- function(pe) {
  pl <- dates_of(Filter(function(e) e$event_type == "planting", pe))
  ah <- which(vapply(pe, function(e) e$event_type == "harvest" && tolower(e$crop_display) == "alfalfa", TRUE))
  ad <- dates_of(pe[ah])
  for (j in seq_along(ah)) {
    nxt <- pl[pl > ad[j]]
    e <- pe[[ah[j]]]
    if (length(nxt) && !any(ad > ad[j] & ad < min(nxt))) {
      e$harvest_fraction_note <- "Last cutting before the next planting: ends the stand with the full P1 row."
    } else {
      e$frac_above_removed_0to1 <- ALFALFA_CUT[["above_removed"]]
      e$frac_below_removed_0to1 <- ALFALFA_CUT[["below_removed"]]
      e$frac_above_to_litter_0to1 <- ALFALFA_CUT[["above_to_litter"]]
      e$frac_below_to_litter_0to1 <- ALFALFA_CUT[["below_to_litter"]]
      e$harvest_fraction_note <- paste("Intermediate cutting: removes the P1 aboveground share and leaves",
                                       "the stubble and roots alive.")
    }
    pe[[ah[j]]] <- e
  }
  pe
}

# Cash crop seasons: a planting to the first same-crop harvest within SEASON_DAYS. Plantings
# of a crop that share that first harvest (a replant) are one season from the first planting.
seasons_of <- function(pe) {
  pl <- Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe)
  hv <- Filter(function(e) e$event_type == "harvest" && tolower(e$crop_display) %in% CASH_CROPS, pe)
  out <- do.call(rbind, lapply(pl, function(p) {
    crop <- tolower(p$crop_display); pd <- as.Date(p$date)
    h <- dates_of(Filter(function(x) tolower(x$crop_display) == crop && as.Date(x$date) > pd &&
                           as.numeric(as.Date(x$date) - pd) <= SEASON_DAYS, hv))
    data.frame(crop = crop, start = pd, end = if (length(h)) min(h) else as.Date(NA))
  }))
  if (is.null(out)) return(data.frame(crop = character(), start = as.Date(character()), end = as.Date(character())))
  out <- out[order(out$start), ]
  out[is.na(out$end) | !duplicated(out[c("crop", "end")]), ]
}
# A season's last planting of its crop: the replant when it has one.
last_planting <- function(pe, crop, st, en) max(dates_of(Filter(function(e) e$event_type == "planting" &&
  tolower(e$crop_display) == crop && as.Date(e$date) >= st && as.Date(e$date) < en, pe)))
# Irrigated seasons: the cash crop seasons that end, and each calendar year's run of alfalfa
# cuttings (first to last cutting of the year), the stand's production seasons.
irrigation_seasons <- function(pe) {
  x <- seasons_of(pe); x <- x[!is.na(x$end), ]
  cut <- dates_of(Filter(function(e) e$event_type == "harvest" && tolower(e$crop_display) == "alfalfa", pe))
  if (!length(cut)) return(x)
  yr <- format(cut, "%Y")
  rbind(x, data.frame(crop = "alfalfa", start = as.Date(tapply(cut, yr, min), origin = "1970-01-01"),
                      end = as.Date(tapply(cut, yr, max), origin = "1970-01-01"), row.names = NULL))
}
is_recorded <- function(e) !isTRUE(e$provenance_class %in% c("imputed", "assumed")) &&
  !isTRUE(e$not_harvested) && !is.na(e$date)

# Pass 1: the generator's plantings and harvests, assigned to phases and merged -----------
keep_all <- list(); gen <- list()
for (tid in names(SYSTEMS)) {
  sys <- SYSTEMS[[tid]]
  src <- jsonlite::fromJSON(file.path(stacked_dir, sprintf("russell_ranch_tautges_2019_%s.json", tid)),
                            simplifyDataFrame = FALSE)
  ev <- src$events
  wc <- WRONG_CROP_DROPS[WRONG_CROP_DROPS$tid == tid, ]
  drop <- vapply(ev, function(e) any(wc$event_type == e$event_type & wc$date == e$date &
                                       wc$crop %in% e$crop_display), TRUE)
  stopifnot(sum(drop) == nrow(wc))
  ev <- ev[!drop]
  gen[[tid]] <- ev
  phases <- sort(unique(phase_of[startsWith(names(phase_of), paste0(sys, "|"))]))
  keep <- setNames(vector("list", length(phases)), phases)
  for (e in ev) {
    if (e$event_type %in% c("planting", "harvest")) {
      p <- phases_for(e$event_type, sys, e)
      if (!length(p)) stop(sprintf("%s: unmatched %s %s %s", tid, e$event_type, e$date, e$crop_display))
      for (ph in p) keep[[ph]][[length(keep[[ph]]) + 1L]] <- e
    }
  }
  n_merged <- 0L
  for (ph in phases) {
    m <- merge_split_days(keep[[ph]], sys, ph)
    n_merged <- n_merged + attr(m, "n_merged")
    attributes(m) <- NULL
    keep[[ph]] <- m
  }
  if (n_merged) cat(sprintf("%-18s split-day plantings/harvests merged away: %d\n", tid, n_merged))
  keep_all[[tid]] <- keep
}
site_plantings <- unlist(lapply(keep_all, function(k) unlist(lapply(k, function(pe)
  Filter(function(e) e$event_type == "planting", pe)), recursive = FALSE)), recursive = FALSE)

# Fill what the logs miss from plot_system.csv and the cutting samples, end every crop
for (tid in names(SYSTEMS)) {
  sys <- SYSTEMS[[tid]]
  n <- c(plantings = 0L, cuttings = 0L, harvests = 0L, cover_crop_ends = 0L)
  for (ph in names(keep_all[[tid]])) {
    pe <- keep_all[[tid]][[ph]]
    mp <- missing_plantings(sys, ph, pe); pe <- c(pe, mp)
    mc <- missing_cuttings(sys, ph, pe); pe <- c(pe, mc)
    mh <- missing_harvests(sys, ph, pe)
    ce <- cover_crop_ends(sys, ph, pe)
    n <- n + c(length(mp), length(mc), length(mh), length(ce))
    keep_all[[tid]][[ph]] <- lapply(c(pe, mh, ce), apply_lookup)
  }
  cat(sprintf("%-18s filled plantings %d, alfalfa cuttings %d, harvests %d; cover crop ends %d\n",
              tid, n[[1]], n[[2]], n[[3]], n[[4]]))
}

# Pass 2: dates the records do not give, from medians of the records ------------------------
# (tools/event_prep/README.md, "Filling missing events"): a cover crop ends the system's median
# gap before the next cash crop planting, or on its median incorporation day when no cash
# crop follows; an unharvested crop ends on the system's median harvest day for that crop.
med <- do.call(rbind, lapply(names(SYSTEMS), function(tid) do.call(rbind, lapply(keep_all[[tid]], function(pe) {
  cash <- dates_of(Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe))
  do.call(rbind, lapply(Filter(function(e) e$event_type == "harvest" && is_recorded(e), pe), function(e) {
    crop <- tolower(e$crop_display); d <- as.Date(e$date)
    r <- data.frame(system = SYSTEMS[[tid]], kind = if (crop == "cover crop") "cc_doy" else paste0("doy_", crop),
                    value = yday(d))
    nxt <- cash[cash > d & cash <= d + 365]
    if (crop == "cover crop" && length(nxt))
      r <- rbind(r, data.frame(system = SYSTEMS[[tid]], kind = "cc_gap", value = as.numeric(min(nxt) - d)))
    r
  }))
}))))
median_for <- function(sys, kind) {
  v <- med$value[med$system == sys & med$kind == kind]
  if (length(v) >= MIN_MEDIAN_N) return(list(v = round(median(v)), n = length(v), level = sys))
  v <- med$value[med$kind == kind]
  list(v = round(median(v)), n = length(v), level = "all systems")
}
impute_date <- function(e, sys) {
  k <- e$impute; e$impute <- NULL
  after <- as.Date(k$after)
  if (k$kind == "cc_gap") {
    m <- median_for(sys, "cc_gap")
    d <- as.Date(k$next_cash) - m$v
    rule <- sprintf("%d days before the next cash crop planting (%s), the median gap between a recorded cover crop end and the next cash crop planting (%s, n = %d)",
                    m$v, k$next_cash, m$level, m$n)
  } else {
    what <- if (k$kind == "cc_doy") "cover crop end" else paste(k$crop, "harvest")
    m <- median_for(sys, if (k$kind == "cc_doy") "cc_doy" else paste0("doy_", k$crop))
    d <- doy_after(after, m$v)
    rule <- sprintf("day %d of the year, the median day of a recorded %s (%s, n = %d)", m$v, what, m$level, m$n)
  }
  stopifnot(d > after)
  e$date <- format(d)
  e$provenance_note <- paste(e$provenance_note, sprintf("Dated %s.", rule))
  e
}
for (tid in names(SYSTEMS)) for (ph in names(keep_all[[tid]])) {
  pe <- keep_all[[tid]][[ph]]
  imp <- vapply(pe, function(e) !is.null(e$impute), TRUE)
  pe[imp] <- lapply(pe[imp], impute_date, sys = SYSTEMS[[tid]])
  for (e in pe[imp]) cat(sprintf("%-18s %-44s %s %s imputed: %s\n", tid, ph, e$crop_display, e$date,
                                 sub("^.*Dated ", "", e$provenance_note)))
  keep_all[[tid]][[ph]] <- alfalfa_cuts(pe)
}

# Pass 3: fertilization, irrigation, history -----------------------------------------------
for (tid in names(SYSTEMS)) for (ph in names(keep_all[[tid]]))
  keep_all[[tid]][[ph]] <- c(keep_all[[tid]][[ph]], fert_events(SYSTEMS[[tid]], ph, as.integer(format(LAST_DATE, "%Y"))))

# The logs end in 2013, so a season reaching into 2014 copies the fertilization of the most
# recent same-crop season of the treatment (of COMPARABLE's when it has none), shifted by the
# difference in first planting dates; only the copied events that land in 2014 inside the season
# are kept. A season none of whose records would land there is skipped as a template because
# the log has gaps (no 2013 corn N in any corn/tomato system; only the preplant of the
# Irrigated Wheat/Fallow wheat planted in 2012, which lands in 2013); a treatment that never
# fertilized the crop gets nothing.
fert_2014 <- function(tid, pe) {
  out <- list()
  ss <- seasons_of(pe)
  ss <- ss[is.na(ss$end) | ss$end > LOGS_END, ]
  for (i in seq_len(nrow(ss))) {
    s <- ss[i, ]; end <- if (is.na(s$end)) LAST_DATE else s$end
    tmpl <- NULL
    copies <- function(t2, p2, st, en) Filter(function(e) {
      d <- as.Date(e$date); d2 <- d + as.numeric(s$start - st)
      e$event_type == "fertilization" && d >= st - FERT_LEAD_DAYS && d <= en &&
        d2 > LOGS_END && d2 <= LAST_DATE && d2 >= s$start - FERT_LEAD_DAYS && d2 <= end
    }, keep_all[[t2]][[p2]])
    for (t2 in c(tid, COMPARABLE[tid][!is.na(COMPARABLE[tid])])) {
      cand <- do.call(rbind, lapply(names(keep_all[[t2]]), function(p2) {
        x <- seasons_of(keep_all[[t2]][[p2]])
        x <- x[x$crop == s$crop & !is.na(x$end) & x$end <= LOGS_END, ]
        if (!nrow(x)) return(NULL)
        x$n_copies <- vapply(seq_len(nrow(x)), function(j) length(copies(t2, p2, x$start[j], x$end[j])), 0L)
        cbind(x, phase = p2, tid = t2)
      }))
      if (is.null(cand)) next
      cand <- cand[cand$n_copies > 0, ]
      if (nrow(cand)) tmpl <- cand[which.max(cand$start), ]
      break
    }
    if (is.null(tmpl)) next
    shift <- as.numeric(s$start - tmpl$start)
    for (e in copies(tmpl$tid, tmpl$phase, tmpl$start, tmpl$end)) {
      e$date <- format(as.Date(e$date) + shift)
      e$provenance_class <- "imputed"
      e$provenance_note <- sprintf(paste(
        "The package's operation logs end in 2013. Copies the %s application of the %s %s season",
        "(planted %s) of %s %s, shifted %+d days to this season's planting."),
        format(as.Date(e$date) - shift), s$crop, format(tmpl$start, "%Y"), format(tmpl$start), tmpl$tid,
        tmpl$phase, shift)
      out[[length(out) + 1L]] <- e
    }
  }
  out
}
for (tid in names(SYSTEMS)) {
  n <- 0L
  for (ph in names(keep_all[[tid]])) {
    f <- fert_2014(tid, keep_all[[tid]][[ph]])
    n <- n + length(f)
    keep_all[[tid]][[ph]] <- c(keep_all[[tid]][[ph]], f)
  }
  if (n) cat(sprintf("%-18s 2014 fertilization copied from earlier seasons: %d events\n", tid, n))
}

# Fertilization the log lacks for a season that had it. Tautges et al. (2019) sidedress
# CONV+WCC (Legume/Corn/Tomato) maize like CONV maize, but the log has no corn N for it in any
# year, so each of its corn seasons takes the dates of the Conventional Corn/Tomato corn season
# of the same year, or the nearest one with records when that year has none (2013, 2014). Any
# other season ending by 2013, of a crop its treatment fertilizes in at least half of its
# seasons, that has no record copies the treatment's nearest same-crop season with records: the
# 2013 conventional corn N and the compost of the organic corn and tomato seasons the package
# lacks (a sudangrass year is filled below). Copies are shifted by the
# difference in planting dates, and only the ones landing inside the season are kept.
FERT_LIKE <- list(leg_corn_tomato = c(corn = "conv_corn_tomato"))
# With no record in the log, the amount is the paper's (David on calibration#10). Tautges et al.
# (2019): maize in CONV and CONV+WCC was planted "with 56 kg N/ha 8-24-6 starter fertilizer" and
# sidedressed "in one application, or two split applications, with ammonium sulfate at a total
# rate of 180 kg N/ha". A corn season of those systems with no record keeps its template's dates,
# shifted from the template's last planting (a replant) to its own last planting: the template's
# urea applications are the sidedress and share the 180 kg N/ha as they shared their own N, and
# its one other application is the starter.
PAPER_CORN_N <- c("conv_corn_tomato", "leg_corn_tomato")
CORN_STARTER_N <- 56
CORN_SIDEDRESS_N <- 180
paper_corn_n <- function(recs) {
  side <- vapply(recs, function(e) identical(e$material, "Urea"), TRUE)
  stopifnot(sum(!side) == 1L, any(side))
  n <- vapply(recs, function(e) e$nh4_n_kg_m2, 0)
  ifelse(side, CORN_SIDEDRESS_N * n / sum(n[side]), CORN_STARTER_N)
}
fert_records <- function(pe, st, en) Filter(function(e) e$event_type == "fertilization" &&
  !identical(e$provenance_class, "imputed") && as.Date(e$date) >= st - FERT_LEAD_DAYS && as.Date(e$date) <= en, pe)
fert_seasons <- function(tid, crop) do.call(rbind, lapply(names(keep_all[[tid]]), function(p2) {
  x <- seasons_of(keep_all[[tid]][[p2]])
  x <- x[x$crop == crop & !is.na(x$end) & x$end <= LOGS_END & x$start >= FIRST_DATE, ]
  if (!nrow(x)) return(NULL)
  x$n_fert <- vapply(seq_len(nrow(x)), function(j) length(fert_records(keep_all[[tid]][[p2]], x$start[j], x$end[j])), 0L)
  cbind(x, phase = p2, tid = tid)
}))
fert_gaps <- list()
for (tid in names(SYSTEMS)) for (ph in names(keep_all[[tid]])) {
  ss <- seasons_of(keep_all[[tid]][[ph]])
  ss <- ss[ss$start >= FIRST_DATE, ]
  for (i in seq_len(nrow(ss))) {
    s <- ss[i, ]; end <- if (is.na(s$end)) LAST_DATE else s$end
    if (length(fert_records(keep_all[[tid]][[ph]], s$start, end))) next
    like <- FERT_LIKE[[tid]][s$crop]
    if (!is.null(like) && !is.na(like)) {
      t2 <- like[[1]]; why <- sprintf("Tautges et al. 2019 sidedress CONV+WCC maize like CONV maize; the log has no %s N here", s$crop)
    } else {
      if (end > LOGS_END) next
      own <- fert_seasons(tid, s$crop)
      if (is.null(own) || mean(own$n_fert > 0) < 0.5) next
      t2 <- tid; why <- sprintf("the log has no fertilization for this %s season, which its treatment fertilizes in %d of %d seasons",
                               s$crop, sum(own$n_fert > 0), nrow(own))
    }
    cand <- fert_seasons(t2, s$crop)
    cand <- cand[!is.null(cand) & cand$n_fert > 0 & !(cand$tid == tid & cand$phase == ph & cand$start == s$start), ]
    if (is.null(cand) || !nrow(cand)) next
    tmpl <- cand[which.min(abs(as.numeric(cand$start - s$start))), ]
    paper <- tid %in% PAPER_CORN_N && s$crop == "corn"
    from <- if (paper) last_planting(keep_all[[tmpl$tid]][[tmpl$phase]], s$crop, tmpl$start, tmpl$end) else tmpl$start
    shift <- as.numeric((if (paper) last_planting(keep_all[[tid]][[ph]], s$crop, s$start, end) else s$start) - from)
    recs <- fert_records(keep_all[[tmpl$tid]][[tmpl$phase]], tmpl$start, tmpl$end)
    kg_ha <- if (paper) paper_corn_n(recs)
    for (j in seq_along(recs)) {
      e <- recs[[j]]
      d <- as.Date(e$date) + shift
      if (d < s$start - FERT_LEAD_DAYS || d > end || d > LAST_DATE) {
        if (paper) stop(sprintf("%s %s: a paper corn N application would land outside the %s season", tid, ph, format(s$start)))
        next
      }
      if (paper) {
        side <- identical(e$material, "Urea")
        e <- list(
          event_type = "fertilization", date = format(d), nh4_n_kg_m2 = round(kg_ha[j] * KG_HA_TO_KG_M2, 7),
          source = "10.1111/gcb.14762", material = if (side) "ammonium sulfate" else "8-24-6 starter",
          provenance_class = "imputed",
          provenance_note = sprintf(paste(
            "Fertilization gap: %s. Amount from Tautges et al. 2019, which give CONV and CONV+WCC maize",
            "56 kg N/ha 8-24-6 starter at planting and ammonium sulfate sidedressed to 180 kg N/ha in one",
            "or two applications; this is %s. Dated like the %s %s application of the corn season last",
            "planted %s in %s %s, shifted %+d days to this season's last planting."),
            why, if (side) sprintf("%.2f kg N/ha of the sidedress", kg_ha[j]) else "the starter",
            format(d - shift), e$material, format(from), tmpl$tid, tmpl$phase, shift))
      } else {
        e$date <- format(d)
        e$provenance_class <- "imputed"
        e$provenance_note <- sprintf("Fertilization gap: %s. Copies the %s application of the %s season planted %s in %s %s, shifted %+d days.",
                                     why, format(d - shift), s$crop, format(tmpl$start), tmpl$tid, tmpl$phase, shift)
      }
      fert_gaps[[tid]][[ph]] <- c(fert_gaps[[tid]][[ph]], list(e))
    }
  }
}
for (tid in names(fert_gaps)) {
  for (ph in names(fert_gaps[[tid]])) keep_all[[tid]][[ph]] <- c(keep_all[[tid]][[ph]], fert_gaps[[tid]][[ph]])
  cat(sprintf("%-18s fertilization gaps filled: %d events\n", tid, length(unlist(fert_gaps[[tid]], recursive = FALSE))))
}

# CONV+WCC tomato in 2004 to 2007 has only its NPK starter in the log, although Tautges et al.
# (2019) sidedress CONV and CONV+WCC tomatoes to 112 kg N/ha. It is left as logged
# (calibration#10): those are the first years the system grew a winter legume cover crop before
# tomato (Wolf et al. 2018 metadata), and its tomatoes then had the lowest fruit N and yield of the
# four tomato systems, so the missing sidedress looks like a change in management, not a gap.

# Compost the package lacks in an organic rotation year that is not a wheat year: the 2008
# sudangrass year of Organic Corn/Tomato corn/CC-tomato/CC. Organic Corn/Tomato has compost in
# each of its other years from 1994 except its wheat years, and so does Transitional (managed like
# the organic system, Wolf et al. 2018) from 2000, and Tautges et al. (2019) give ORG "annual
# inputs of 9 t/ha" of compost (calibration#10). Such a year copies the recorded application of
# the nearest year (the earlier one on a tie), same tonnage, on the same calendar date of its
# year. The wheat years (wheat replaced corn in 2009 to 2012) have no compost in the package at
# all, 0 of 5 against 42 of the 49 other years, and the paper times compost only before maize and
# tomato, so a year whose copy would fall in a growing wheat crop stays without (calibration#10).
COMPOST_SYSTEMS <- c("org_corn_tomato", "transitional")
is_compost <- function(e) e$event_type == "fertilization" && !is.null(e$org_c_kg_m2)
year_of <- function(evs) as.integer(substr(vapply(evs, `[[`, "", "date"), 1, 4))
on_growing_wheat <- function(pe, d) {
  w <- seasons_of(pe); w <- w[w$crop == "wheat" & !is.na(w$end), ]
  any(w$start < d & w$end > d)
}
for (tid in COMPOST_SYSTEMS) {
  filled <- character(); wheat_years <- character()
  for (ph in names(keep_all[[tid]])) {
    pe <- keep_all[[tid]][[ph]]
    comp <- Filter(is_compost, pe)
    rec <- Filter(function(e) !identical(e$provenance_class, "imputed"), comp)
    rec_yr <- year_of(rec)
    for (yr in setdiff(seq(min(rec_yr), as.integer(format(LOGS_END, "%Y"))), year_of(comp))) {
      k <- order(abs(rec_yr - yr), rec_yr)[1]
      stopifnot(sum(rec_yr == rec_yr[k]) == 1L)
      e <- rec[[k]]; src <- e$date
      d <- as.Date(sprintf("%d%s", yr, substr(src, 5, 10)), format = "%Y-%m-%d")
      if (is.na(d)) stop(sprintf("%s %s: the %s compost has no date in %d", tid, ph, src, yr))
      if (on_growing_wheat(pe, d)) { wheat_years <- c(wheat_years, sprintf("%s %d", ph, yr)); next }
      e$date <- format(d)
      e$provenance_class <- "imputed"
      e$provenance_note <- sprintf(paste(
        "Compost gap: the package has no compost for this phase in %d, although it has compost in",
        "each of its other years that are not wheat years and Tautges et al. 2019 give the organic",
        "system annual compost (calibration#10). Copies the %s application, the nearest recorded",
        "year (%s wet t/ac), on the same date of %d."), yr, src, format(e$compost_wet_tons_acre), yr)
      pe[[length(pe) + 1L]] <- e
      filled <- c(filled, sprintf("%s %s", ph, e$date))
    }
    keep_all[[tid]][[ph]] <- pe
  }
  if (length(filled)) cat(sprintf("%-18s compost year the package lacks, copied from the nearest recorded year: %s\n",
                                  tid, paste(filled, collapse = ", ")))
  if (length(wheat_years)) cat(sprintf("%-18s wheat years left without compost: %s\n", tid, paste(wheat_years, collapse = ", ")))
}

# A copied compost application (2014, a fertilization gap or a compost year) keeps the copied
# season's tonnage and takes %C and %N for the year it is applied, as the records do: the compost
# was applied uniformly in the organic and transitional systems each year (Wolf et al. 2018), so a
# year's applications share its analysis, or the mean of measured years when it has none.
for (tid in names(keep_all)) for (ph in names(keep_all[[tid]])) {
  keep_all[[tid]][[ph]] <- lapply(keep_all[[tid]][[ph]], function(e) {
    if (!is_compost(e) || !identical(e$provenance_class, "imputed")) return(e)
    yr <- substr(e$date, 1, 4)
    cp <- if (yr %in% names(c_pct)) c_pct[[yr]] else c_mean
    np <- if (yr %in% names(n_pct)) n_pct[[yr]] else n_mean
    mass <- e$compost_wet_tons_acre * TON_AC_TO_KG_M2
    e$org_c_kg_m2 <- round(mass * cp / 100, 7); e$org_n_kg_m2 <- round(mass * np / 100, 7)
    e$compost_total_c_pct <- round(cp, 4); e$compost_total_n_pct <- round(np, 4)
    e$provenance_note <- paste(e$provenance_note, sprintf("C is from %s, N from %s, as for the records.",
      if (yr %in% names(c_pct)) paste("the", yr, "analysis") else "the mean of measured years",
      if (yr %in% names(n_pct)) paste("the", yr, "analysis") else "the mean of measured years"))
    e
  })
}

# irrigation was injected at the midpoint of each cash crop window; give each event to
# the phase whose own window midpoint it sits on. A window is one irrigated season
# (irrigation_seasons): from a cash crop's first planting to the first same-crop harvest
# within SEASON_DAYS, a planting with no such harvest having none, or a year of alfalfa
# cuttings. The generator made one window per planting and sometimes paired it with the wrong
# harvest (one in the other phase or a year later) or gave each planting of a replanted crop its
# own; such an event either falls outside every window or sits more than IRR_MID_DAYS from the
# midpoint of the season it falls in, and is dropped. Rainfed systems get none.
IRR_MID_DAYS <- 10
for (tid in names(SYSTEMS)) {
  irr <- Filter(function(e) identical(e$event_type, "irrigation"), gen[[tid]])
  dropped_irr <- 0L; dropped_off_mid <- 0L
  if (tid %in% RAINFED) {
    dropped_irr <- length(irr)
  } else {
    win <- do.call(rbind, lapply(names(keep_all[[tid]]), function(ph) {
      x <- irrigation_seasons(keep_all[[tid]][[ph]])
      if (nrow(x)) data.frame(phase = ph, start = x$start, end = x$end, mid = x$start + as.numeric(x$end - x$start) / 2)
    }))
    for (e in irr) {
      d <- as.Date(e$date)
      cand <- win[win$start <= d & win$end >= d, ]
      if (!nrow(cand)) { dropped_irr <- dropped_irr + 1L; next }
      k <- which.min(abs(as.numeric(cand$mid - d)))
      if (abs(as.numeric(cand$mid[k] - d)) > IRR_MID_DAYS) { dropped_off_mid <- dropped_off_mid + 1L; next }
      ph <- cand$phase[k]
      keep_all[[tid]][[ph]][[length(keep_all[[tid]][[ph]]) + 1L]] <- e
    }
  }
  if (dropped_irr) cat(sprintf("%-18s irrigation events dropped: %d (%s)\n", tid, dropped_irr,
                               if (tid %in% RAINFED) "rainfed system" else
                                 sprintf("outside any cash crop window of %d days or less: generator artifacts", SEASON_DAYS)))
  if (dropped_off_mid) cat(sprintf("%-18s irrigation events dropped: %d (more than %d days from their season's midpoint: generator artifacts)\n",
                                   tid, dropped_off_mid, IRR_MID_DAYS))
}

# Tautges et al. (2019) give the irrigated wheat systems "supplemental irrigation of 80 mm per
# year except in 1995, 1998, 2000, 2005, and 2008–2012 due to sufficient precipitation". Each
# wheat season in those systems carries that instead of the generator's sprinkler prior: one
# 80 mm event at the season midpoint, and none when the season's harvest year is one of those.
# 2013 and 2014, after the paper's period, take the 80 mm and are tagged imputed, as is
# Irrigated Wheat/Legume, which the paper does not describe and which is irrigated like IWF.
IRRIGATED_WHEAT <- c("irr_wheat_control", "irr_wheat_fallow", "irr_wheat_legume")
WHEAT_PAPER_SYSTEMS <- c("irr_wheat_control", "irr_wheat_fallow")  # IWF and IWF+N
NO_IRRIGATION_YEARS <- c(1995, 1998, 2000, 2005, 2008:2012)
WHEAT_SUPPLEMENTAL_MM <- 80
for (tid in IRRIGATED_WHEAT) {
  n <- c(replaced = 0L, events = 0L)
  for (ph in names(keep_all[[tid]])) {
    pe <- keep_all[[tid]][[ph]]
    x <- irrigation_seasons(pe); x <- x[x$crop == "wheat", ]
    in_wheat <- vapply(pe, function(e) e$event_type == "irrigation" &&
                         any(as.Date(e$date) >= x$start & as.Date(e$date) <= x$end), TRUE)
    n[["replaced"]] <- n[["replaced"]] + sum(in_wheat)
    pe <- pe[!in_wheat]
    for (i in seq_len(nrow(x))) {
      yr <- as.integer(format(x$end[i], "%Y"))
      if (yr %in% NO_IRRIGATION_YEARS) next
      mid <- x$start[i] + floor(as.numeric(x$end[i] - x$start[i]) / 2)
      pe[[length(pe) + 1L]] <- list(
        event_type = "irrigation", date = format(mid), source = "10.1111/gcb.14762",
        amount_mm = WHEAT_SUPPLEMENTAL_MM, method = "canopy",
        provenance_class = if (tid %in% WHEAT_PAPER_SYSTEMS && yr <= 2012) "published" else "imputed",
        provenance_note = sprintf(paste(
          "Tautges et al. 2019: irrigated wheat systems got supplemental irrigation of 80 mm per year",
          "except in 1995, 1998, 2000, 2005 and 2008-2012. One event at the midpoint of the %s to %s",
          "season%s.%s"), format(x$start[i]), format(x$end[i]),
          if (yr <= 2012) "" else "; the paper's period ends in 2012, so this year takes the usual 80 mm",
          if (tid %in% WHEAT_PAPER_SYSTEMS) "" else
            " The paper describes IWF and IWF+N; Irrigated Wheat/Legume is irrigated the same way."))
      n[["events"]] <- n[["events"]] + 1L
    }
    keep_all[[tid]][[ph]] <- pe
  }
  cat(sprintf("%-18s wheat irrigation from Tautges et al. 2019: %d events of %d mm (replaced %d generator events)\n",
              tid, n[["events"]], WHEAT_SUPPLEMENTAL_MM, n[["replaced"]]))
}

# Tautges et al. (2019): "Maize in all systems was furrow irrigated with an average of 33.6 mm per
# year, with a minimum of 17.6 mm in 1995 and a maximum of 43.5 mm in 2004", and tomatoes "as
# described for maize". As millimetres that is far too little for furrow irrigation; the unit is
# taken as inches (David on calibration#10), the conservative reading that keeps the crops from
# being water limited. The monitoring irrigation product near Russell Ranch
# (monitoring_irrigation_near_russell.csv, from russell_monitoring_irrigation.R) estimates
# irrigation from evapotranspiration and misses drainage, so it is a lower bound, and its median
# irrigated corn and tomato season is already above the 336 mm a centimetre reading would give.
# Each corn and tomato season at the site carries its year's amount where the paper gives one
# (1995, 2004), the average otherwise, instead of the generator's sprinkler prior. The paper
# describes the maize systems CONV, CONV+WCC and ORG; the corn and tomato of Transitional,
# Alfalfa/Corn/Tomato and Conventional Wheat/Tomato, which it does not describe, take the same
# amounts (calibration#10), as do 2013 and 2014, after the paper's period; those are tagged
# imputed. One large event would mostly drain in SIPNET, whose soil holds about 12 cm, so the
# season total is split into equal events of at most IRR_EVENT_MAX_MM, spaced evenly from the
# median days between planting and the first irrigation to the median days between the last
# irrigation and harvest of the monitoring product's corn and tomato seasons near Russell Ranch
# (irrigation_csv, from russell_monitoring_irrigation.R), counted from the crop's last planting
# (a replant); a season too short for those offsets is irrigated over its middle half
# (calibration#10). Method soil: furrow water enters the soil, and PEcAn's SIPNET
# writer gives every other method SIPNET's canopy code.
FURROW_PAPER_SYSTEMS <- c("conv_corn_tomato", "leg_corn_tomato", "org_corn_tomato")
FURROW_SYSTEMS <- setdiff(names(SYSTEMS), RAINFED)
FURROW_CROPS <- c("corn", "tomato")
FURROW_YEAR_IN <- c(`1995` = 17.6, `2004` = 43.5)
FURROW_MEAN_IN <- 33.6
MM_PER_IN <- 25.4
# The monitoring irrigation product's irrigation_max from v1.1 on, set "to avoid unrealistically
# large irrigation events" (management/irrigation/CHANGELOG.txt)
IRR_EVENT_MAX_MM <- 150
irm <- read.csv(irrigation_csv, stringsAsFactors = FALSE)
irm_row <- function(crop) { r <- irm[irm$crop == crop, ]; stopifnot(nrow(r) == 1L); r }
IRRIGATION_SOURCE <- if (length(args) == 5L) irrigation_csv else
  "calibration:runs/russell_ranch/events_treatments/monitoring_irrigation_near_russell.csv"
for (tid in FURROW_SYSTEMS) {
  n <- c(replaced = 0L, events = 0L, seasons = 0L)
  for (ph in names(keep_all[[tid]])) {
    pe <- keep_all[[tid]][[ph]]
    x <- irrigation_seasons(pe); x <- x[x$crop %in% FURROW_CROPS, ]
    in_season <- vapply(pe, function(e) e$event_type == "irrigation" &&
                          any(as.Date(e$date) >= x$start & as.Date(e$date) <= x$end), TRUE)
    n[["replaced"]] <- n[["replaced"]] + sum(in_season)
    pe <- pe[!in_season]
    for (i in seq_len(nrow(x))) {
      yr <- format(x$end[i], "%Y")
      inches <- if (yr %in% names(FURROW_YEAR_IN)) FURROW_YEAR_IN[[yr]] else FURROW_MEAN_IN
      total <- inches * MM_PER_IN
      in_paper <- tid %in% FURROW_PAPER_SYSTEMS
      r <- irm_row(x$crop[i])
      planted <- last_planting(pe, x$crop[i], x$start[i], x$end[i])
      first <- planted + r$median_first_days; last <- x$end[i] - r$median_last_days
      short <- last <= first
      if (short) {
        len <- as.numeric(x$end[i] - planted)
        first <- planted + round(len / 4); last <- planted + round(3 * len / 4)
        cat(sprintf("%-18s %-44s %s season %s to %s is shorter than the monitoring offsets; irrigated over its middle half\n",
                    tid, ph, x$crop[i], format(planted), format(x$end[i])))
      }
      k <- ceiling(total / IRR_EVENT_MAX_MM)
      when <- first + round(seq(0, as.numeric(last - first), length.out = k))
      amt <- rep(round(total / k, 4), k); amt[k] <- round(total - sum(amt[-k]), 4)
      for (j in seq_len(k)) {
        pe[[length(pe) + 1L]] <- list(
          event_type = "irrigation", date = format(when[j]), source = "10.1111/gcb.14762",
          amount_mm = amt[j], method = "soil",
          provenance_class = if (in_paper && as.integer(yr) <= 2012) "published" else "imputed",
          provenance_note = paste(c(sprintf(paste(
            "Tautges et al. 2019: maize and tomato in CONV, CONV+WCC and ORG were furrow irrigated with",
            "\"an average of 33.6 mm per year, with a minimum of 17.6 mm in 1995 and a maximum of 43.5 mm",
            "in 2004\", read as inches (David on calibration#10): %s in, %s mm for the %s to %s %s season,",
            "%s."), format(inches), format(round(total, 2)), format(x$start[i]), format(x$end[i]), x$crop[i],
            if (yr %in% names(FURROW_YEAR_IN)) paste("the paper's", yr, "value")
            else if (as.integer(yr) <= 2012) "the average" else "the average, as the paper's period ends in 2012"),
            if (!in_paper) "The paper does not describe this system; its corn and tomato take the maize systems' amounts (calibration#10).",
            if (short) sprintf(paste(
              "Event %d of %d equal events (at most %d mm each) over the middle half of the season from the",
              "%s planting, which is shorter than the monitoring irrigation product's median %d days from",
              "planting to first irrigation and %d from last irrigation to harvest for %s within %d km of",
              "Russell Ranch, %s (%s). Method soil: furrow water."), j, k, IRR_EVENT_MAX_MM, format(planted),
              r$median_first_days, r$median_last_days, x$crop[i], r$radius_km, r$years, IRRIGATION_SOURCE)
            else sprintf(paste(
              "Event %d of %d equal events (at most %d mm each) from %d days after the %s planting to %d days",
              "before harvest, the medians for %s seasons in the monitoring irrigation product within %d km",
              "of Russell Ranch, %s (%s). Method soil: furrow water."), j, k, IRR_EVENT_MAX_MM,
              r$median_first_days, format(planted), r$median_last_days, x$crop[i], r$radius_km, r$years,
              IRRIGATION_SOURCE)), collapse = " "))
        n[["events"]] <- n[["events"]] + 1L
      }
      n[["seasons"]] <- n[["seasons"]] + 1L
    }
    keep_all[[tid]][[ph]] <- pe
  }
  if (n[["events"]]) cat(sprintf("%-18s corn and tomato irrigation from Tautges et al. 2019 (inches): %d seasons, %d events (replaced %d generator events)\n",
                                 tid, n[["seasons"]], n[["events"]], n[["replaced"]]))
}

# A season in an irrigated system with no irrigation (a filled season, 2014, an alfalfa
# production year, or one whose only event was a dropped artifact) takes the treatment's usual
# irrigation: one event at the season midpoint carrying the median season total of its other
# seasons of that crop (the site's when the treatment has fewer than MIN_MEDIAN_N). The amounts
# are the generator's sprinkler prior, so this keeps a filled season like its neighbours; the
# package records no irrigation. The irrigated wheat systems' wheat seasons and every corn and
# tomato season follow Tautges (above), so they neither take the fill nor count toward its
# medians, and the irrigated wheat seasons harvested in the no-irrigation years
# stay without; a crop with no irrigated season anywhere
# (the 2008 and 2009 sudangrass green manure) has no median and gets none. Both are printed.
season_irr <- do.call(rbind, lapply(setdiff(names(SYSTEMS), RAINFED), function(tid)
  do.call(rbind, lapply(keep_all[[tid]], function(pe) {
    x <- irrigation_seasons(pe)
    if (!nrow(x)) return(NULL)
    irr <- Filter(function(e) e$event_type == "irrigation", pe)
    x$mm <- vapply(seq_len(nrow(x)), function(i) sum(vapply(Filter(function(e)
      as.Date(e$date) >= x$start[i] && as.Date(e$date) <= x$end[i], irr), function(e) as.numeric(e$amount_mm), 0)), 0)
    cbind(x, tid = tid)
  }))))
season_irr <- season_irr[season_irr$mm > 0 & !(season_irr$tid %in% IRRIGATED_WHEAT & season_irr$crop == "wheat") &
                           !(season_irr$tid %in% FURROW_SYSTEMS & season_irr$crop %in% FURROW_CROPS), ]
for (tid in setdiff(names(SYSTEMS), RAINFED)) {
  n <- 0L
  for (ph in names(keep_all[[tid]])) {
    pe <- keep_all[[tid]][[ph]]
    x <- irrigation_seasons(pe)
    irr <- dates_of(Filter(function(e) e$event_type == "irrigation", pe))
    for (i in seq_len(nrow(x))) {
      if (any(irr >= x$start[i] & irr <= x$end[i])) next
      skip <- function(why) cat(sprintf("%-18s %-44s %s season %s to %s left without irrigation: %s\n",
                                        tid, ph, x$crop[i], format(x$start[i]), format(x$end[i]), why))
      if (tid %in% IRRIGATED_WHEAT && as.integer(format(x$end[i], "%Y")) %in% NO_IRRIGATION_YEARS) {
        skip("a Tautges et al. 2019 no-irrigation year"); next
      }
      v <- season_irr$mm[season_irr$tid == tid & season_irr$crop == x$crop[i]]; level <- tid
      if (length(v) < MIN_MEDIAN_N) { v <- season_irr$mm[season_irr$crop == x$crop[i]]; level <- "irrigated systems" }
      if (!length(v)) { skip(sprintf("no irrigated %s season to take a median from", x$crop[i])); next }
      mid <- x$start[i] + floor(as.numeric(x$end[i] - x$start[i]) / 2)
      pe[[length(pe) + 1L]] <- list(
        event_type = "irrigation", date = format(mid), source = "calibration:tools/event_prep/russell_split_phases.R",
        amount_mm = round(median(v), 4), method = "canopy", provenance_class = "imputed",
        provenance_note = sprintf(paste(
          "No irrigation in this %s season (%s to %s); the usual irrigation of %s: one event at the",
          "season midpoint with the median season total of %d %s %s. Those amounts are the",
          "generator's sprinkler prior; the package records no irrigation."),
          x$crop[i], format(x$start[i]), format(x$end[i]), level, length(v), x$crop[i],
          ngettext(length(v), "season", "seasons")))
      irr <- c(irr, mid)
      n <- n + 1L
    }
    keep_all[[tid]][[ph]] <- pe
  }
  if (n) cat(sprintf("%-18s seasons given the usual irrigation: %d\n", tid, n))
}

# Tillage. The package has no tillage records. Tautges et al. (2019) describe the operations and
# when they happen relative to harvest, planting, cover crop termination and compost; the
# monitoring product gives their timing and intensity near Russell Ranch (tillage_csv, from
# russell_monitoring_tillage.R: parcels within 25 km, 2016-2023). One event per operation:
# disking after each corn, tomato and wheat harvest, the median days after harvest for that crop
# (and before the next planting); bed preparation before each corn and tomato season, the median
# days before planting (and after the previous crop ends); and incorporation of each cover crop,
# sudangrass and unharvested crop at its end, and of each compost application on its date (one
# pass with another incorporation that day), with the median over all tillage events. tillage_eff_0to1 is the median for the operation. In-season
# cultivations have no date and are left out.
til <- read.csv(tillage_csv, stringsAsFactors = FALSE)
TILLAGE_SOURCE <- if (length(args) >= 4L) tillage_csv else
  "calibration:runs/russell_ranch/events_treatments/monitoring_tillage_near_russell.csv"
til_row <- function(op, crop) { r <- til[til$operation == op & til$crop == crop, ]; stopifnot(nrow(r) == 1L); r }
tillage_event <- function(d, r, what, moved = NULL) list(
  event_type = "tillage", date = format(d), source = TILLAGE_SOURCE,
  tillage_eff_0to1 = r$median_tillage_eff, provenance_class = "imputed",
  provenance_note = paste(c(sprintf(paste(
    "%s (Tautges et al. 2019). tillage_eff_0to1 is the median of %d monitoring tillage events%s",
    "on parcels within %d km of Russell Ranch (%s)."), what, r$n_events,
    if (r$crop == "all") "" else sprintf(" for %s, %d days %s the %s,", r$crop, r$median_days,
                                          if (r$operation == "post_harvest") "after" else "before",
                                          if (r$operation == "post_harvest") "harvest" else "planting"),
    r$radius_km, r$years), moved), collapse = " "))
tillage_events <- function(pe) {
  out <- list()
  pl <- dates_of(Filter(function(e) e$event_type == "planting", pe))
  ends <- Filter(function(e) e$event_type == "harvest", pe)
  inc <- integer()
  for (e in ends) {
    crop <- tolower(e$crop_display); d <- as.Date(e$date)
    if (crop %in% GREEN_MANURE || isTRUE(e$not_harvested)) {
      out[[length(out) + 1L]] <- tillage_event(d, til_row("any", "all"), sprintf("Incorporation of the %s at its end", crop))
      inc[[e$date]] <- length(out)
    } else if (crop %in% c("corn", "tomato", "wheat")) {
      r <- til_row("post_harvest", crop)
      t <- d + r$median_days; nxt <- pl[pl > d]; moved <- NULL
      if (length(nxt) && t >= min(nxt)) {
        moved <- sprintf("Moved from %s to %s, the day before the next planting on %s.",
                         format(t), format(min(nxt) - 1), format(min(nxt)))
        t <- min(nxt) - 1
      }
      if (t > d) out[[length(out) + 1L]] <- tillage_event(t, r, sprintf("Disking after the %s harvest of %s", crop, format(d)), moved)
    }
  }
  ss <- seasons_of(pe); ss <- ss[ss$crop %in% c("corn", "tomato"), ]
  for (i in seq_len(nrow(ss))) {
    r <- til_row("pre_plant", ss$crop[i]); st <- ss$start[i]
    t <- st - r$median_days; prev <- Filter(function(e) as.Date(e$date) < st, ends); moved <- NULL
    if (length(prev)) {
      last <- prev[[which.max(dates_of(prev))]]
      if (t <= as.Date(last$date)) {
        moved <- sprintf("Moved from %s to %s, the day after the previous crop (%s) ends on %s.",
                         format(t), format(as.Date(last$date) + 1), tolower(last$crop_display), last$date)
        t <- as.Date(last$date) + 1
      }
    }
    if (t < st) out[[length(out) + 1L]] <- tillage_event(t, r, sprintf("Bed preparation before the %s planted %s", ss$crop[i], format(st)), moved)
  }
  for (e in Filter(function(e) e$event_type == "fertilization" && !is.null(e$org_c_kg_m2), pe)) {
    k <- inc[e$date]
    if (!is.na(k)) {
      out[[k]]$provenance_note <- paste(out[[k]]$provenance_note, "The compost applied that day is incorporated in the same pass.")
      next
    }
    out[[length(out) + 1L]] <- tillage_event(as.Date(e$date), til_row("any", "all"), "Incorporation of the compost applied that day")
    inc[[e$date]] <- length(out)
  }
  out
}
for (tid in names(SYSTEMS)) {
  n <- 0L
  for (ph in names(keep_all[[tid]])) {
    tl <- tillage_events(keep_all[[tid]][[ph]])
    n <- n + length(tl)
    keep_all[[tid]][[ph]] <- c(keep_all[[tid]][[ph]], tl)
  }
  cat(sprintf("%-18s tillage events: %d\n", tid, n))
}

# The six Alfalfa/Corn/Tomato plots were Irrigated Wheat/Legume, one phase to one phase, until
# fallow from 2008 and the switch in 2012. The package files that history under the old system
# name, so each Alfalfa/Corn/Tomato phase takes its plots' Irrigated Wheat/Legume events.
HISTORY <- list(alf_corn_tomato = "irr_wheat_legume")
plots_of <- function(sys, ph) sort(unique(ps$plot[ps$new_system_name == sys & ps[["harvest_year_rotation_order_(even-odd)"]] == ph]))
history_of <- list()
for (tid in names(HISTORY)) for (ph in names(keep_all[[tid]])) {
  old <- HISTORY[[tid]]
  oph <- Filter(function(p2) identical(plots_of(SYSTEMS[[old]], p2), plots_of(SYSTEMS[[tid]], ph)), names(keep_all[[old]]))
  stopifnot(length(oph) == 1L)
  first_own <- min(dates_of(keep_all[[tid]][[ph]]))
  h <- Filter(function(e) as.Date(e$date) < first_own, keep_all[[old]][[oph]])
  h <- lapply(h, function(e) { e$history_of <- sprintf("%s__%s", old, oph); e })
  keep_all[[tid]][[ph]] <- c(h, keep_all[[tid]][[ph]])
  history_of[[paste(tid, ph)]] <- sprintf("%s %s (plots %s, %d events before %s)", old, oph,
                                         paste(plots_of(SYSTEMS[[tid]], ph), collapse = ", "), length(h), format(first_own))
  cat(sprintf("%-18s %-44s takes %s\n", tid, ph, history_of[[paste(tid, ph)]]))
}

# Write --------------------------------------------------------------------------------------
summary_rows <- list()
for (tid in names(SYSTEMS)) for (ph in names(keep_all[[tid]])) {
  pe <- keep_all[[tid]][[ph]]
  pe <- Filter(function(e) as.Date(e$date) <= LAST_DATE, pe)
  stopifnot(!any(vapply(pe, function(e) is.na(e$date), TRUE)))
  pe <- pe[order(vapply(pe, `[[`, "", "date"), vapply(pe, `[[`, "", "event_type"))]
  slug <- gsub("-+", "-", gsub("[^a-z0-9]+", "-", tolower(ph)))
  hist_note <- history_of[[paste(tid, ph)]]
  out <- list(
    pecan_events_version = "0.1.1",
    site_id = sprintf("%s__%s", tid, slug),
    provenance = list(
      dataset_id = "russell_ranch_tautges_2019", treatment = tid, rotation_phase = ph,
      generator = "calibration:tools/event_prep/russell_split_phases.R",
      stacked_input = sprintf("generator_stacked/russell_ranch_tautges_2019_%s.json", tid),
      note = paste(c(
        "One rotation phase of the treatment. Planting, harvest and irrigation events come",
        "from the stacked generator output, assigned to this phase by the plot ids in the",
        "Century package; planting amounts are still the generator's prior fills",
        "(prior_filled). Plantings, harvests and alfalfa cuttings the operation logs lack,",
        "including all of 2014, are filled from plot_system.csv and the cutting samples.",
        "Harvests take the harvest lookup fractions (harvest_lookup_row), alfalfa cuttings",
        "leave the stand alive, and cover crops and sudangrass go wholly to litter. Dates and",
        "amounts no record gives are imputed (provenance_class imputed) as described in",
        "tools/event_prep/README.md. Fertilization is rebuilt from the package; a season with no",
        "record, of a crop the treatment fertilizes in at least half its seasons, copies the",
        "treatment's nearest same-crop season with records (a fertilization gap).",
        if (tid %in% names(FERT_LIKE)) sprintf(paste(
          "Its %s seasons take the dates of the same-year (or nearest) %s %s season instead, as Tautges",
          "et al. 2019 sidedress CONV+WCC maize like CONV maize."), names(FERT_LIKE[[tid]]), FERT_LIKE[[tid]], names(FERT_LIKE[[tid]])),
        if (tid %in% PAPER_CORN_N) paste(
          "A corn season with no N record takes Tautges et al. 2019's amounts: 56 kg N/ha starter and",
          "180 kg N/ha of ammonium sulfate sidedress."),
        if (tid == "leg_corn_tomato") paste(
          "Its 2004 to 2007 tomato seasons keep the log's starter only: they were the first to follow",
          "a winter legume cover crop, and their fruit N and yield were the lowest of the tomato systems."),
        if (tid %in% COMPOST_SYSTEMS) paste(
          "Copied compost keeps the copied season's tonnage and takes the %C and %N of the year applied;",
          "a year the package lacks that is not a wheat year copies the nearest recorded year, and the",
          "wheat years have no compost."),
        if (tid %in% FURROW_SYSTEMS && any(seasons_of(pe)$crop %in% FURROW_CROPS)) paste(c(
          "Corn and tomato irrigation follows Tautges et al. 2019 instead of the generator: 33.6 in",
          "(853.44 mm) a season, 17.6 in in 1995 and 43.5 in in 2004, the paper's \"mm\" read as inches,",
          "applied to the soil in equal events of at most 150 mm timed from the monitoring irrigation",
          "product near Russell Ranch; 2013 and 2014 take the average, imputed.",
          if (!tid %in% FURROW_PAPER_SYSTEMS) "The paper does not describe this system, so its corn and tomato take the maize systems' amounts, imputed."),
          collapse = " "),
        if (any(c(tid, HISTORY[[tid]]) %in% IRRIGATED_WHEAT)) paste(c(
          "The irrigated wheat systems' wheat irrigation follows Tautges et al. 2019 instead of the",
          "generator: 80 mm per year at the season midpoint, none in 1995, 1998, 2000, 2005 and",
          "2008-2012, and 80 mm, imputed, in 2013 and 2014.",
          if ("irr_wheat_legume" %in% c(tid, HISTORY[[tid]])) "Irrigated Wheat/Legume, which the paper does not describe, is irrigated like IWF, imputed."),
          collapse = " "),
        sprintf(paste(
          "Tillage events are the operations Tautges et al. 2019 describe, one event each, timed and",
          "sized from medians of the monitoring tillage product within %d km of Russell Ranch, %s (%s)."),
          til$radius_km[1], til$years[1], TILLAGE_SOURCE),
        if (!is.null(hist_note)) sprintf("Before 2012 these plots were %s; those events carry history_of.", hist_note)),
        collapse = " ")),
    events = pe)
  fn <- file.path(out_dir, sprintf("russell_ranch_tautges_2019_%s__%s.json", tid, slug))
  write(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = 1, digits = NA), fn)

  yrs <- substr(vapply(pe, `[[`, "", "date"), 1, 4)
  for (y in sort(unique(yrs))) {
    ye <- pe[yrs == y]
    g <- function(f) sum(vapply(ye, function(e) as.numeric(if (is.null(e[[f]])) 0 else e[[f]]), 0))
    cash <- function(t) paste(sort(vapply(Filter(function(e) e$event_type == t && !isTRUE(e$not_harvested) &&
      tolower(e$crop_display) %in% CASH_CROPS, ye), function(e) e$crop_display, "")), collapse = "+")
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      treatment = tid, rotation_phase = ph, year = y,
      cash_planting = cash("planting"), cash_harvest = cash("harvest"),
      mineral_n_kg_ha = round(g("nh4_n_kg_m2") * 1e4, 2),
      compost_c_mg_ha = round(g("org_c_kg_m2") * 10, 3),
      compost_n_kg_ha = round(g("org_n_kg_m2") * 1e4, 2),
      irrigation_mm = round(g("amount_mm"), 1))
  }
  cat(sprintf("%-18s %-44s %3d events -> %s\n", tid, ph, length(pe), basename(fn)))
}

smry <- do.call(rbind, summary_rows)
write.csv(smry, file.path(out_dir, "phase_year_summary.csv"), row.names = FALSE)
cat(sprintf("wrote %d phase-year rows to phase_year_summary.csv\n", nrow(smry)))
