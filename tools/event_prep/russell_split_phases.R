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
# usage: russell_split_phases.R <generator_stacked_dir> <century_dir> <out_dir>
#   century_dir: the extracted RR_2014_datasets/ folder from the Wolf et al. (2018) data
#   paper supporting information, doi 10.1002/ecy.2105.

suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L)
  stop("usage: russell_split_phases.R <generator_stacked_dir> <century_dir> <out_dir>")
stacked_dir <- args[1]; century_dir <- args[2]; out_dir <- args[3]
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
LAST_DATE <- as.Date("2014-12-31")
# A missing date or amount comes from the package's own records for the same system when it
# has at least MIN_MEDIAN_N of them, otherwise from the whole site (tools/event_prep/README.md,
# "Filling missing events").
MIN_MEDIAN_N <- 5

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
# of 2014). A planting of the same crop within 30 days counts as the same operation.
missing_plantings <- function(sys, ph, pe) {
  m <- ps_plantings[ps_plantings$system == sys & ps_plantings$phase == ph, ]
  pl <- Filter(function(e) e$event_type == "planting", pe)
  out <- list()
  for (crop in unique(m$crop)) {
    mc <- m[m$crop == crop, ]
    have <- dates_of(Filter(function(e) tolower(e$crop_display) == crop, pl))
    cl <- cluster_dates(mc$date, 30)
    for (g in unique(cl)) {
      s <- mc[cl == g, ]
      d <- shared_date(s$date)
      if (any(abs(as.numeric(have - d)) <= 30)) next
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

# Cash crop seasons: a planting to the first same-crop harvest within SEASON_DAYS
seasons_of <- function(pe) {
  pl <- Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe)
  hv <- Filter(function(e) e$event_type == "harvest" && tolower(e$crop_display) %in% CASH_CROPS, pe)
  out <- do.call(rbind, lapply(pl, function(p) {
    crop <- tolower(p$crop_display); pd <- as.Date(p$date)
    h <- dates_of(Filter(function(x) tolower(x$crop_display) == crop && as.Date(x$date) > pd &&
                           as.numeric(as.Date(x$date) - pd) <= SEASON_DAYS, hv))
    data.frame(crop = crop, start = pd, end = if (length(h)) min(h) else as.Date(NA))
  }))
  if (is.null(out)) data.frame(crop = character(), start = as.Date(character()), end = as.Date(character())) else out
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

# irrigation was injected at the midpoint of each cash crop window; give each event to
# the phase whose own window midpoint it sits on. A window is one season: from a cash crop
# planting to the first same-crop harvest within SEASON_DAYS, and a planting with no such
# harvest has none. The generator also paired a planting in one phase with a harvest in
# the other and put irrigation in winter; those events fall outside every window and are
# dropped. Rainfed systems get none.
for (tid in names(SYSTEMS)) {
  irr <- Filter(function(e) identical(e$event_type, "irrigation"), gen[[tid]])
  dropped_irr <- 0L
  if (tid %in% RAINFED) {
    dropped_irr <- length(irr)
  } else {
    win <- do.call(rbind, lapply(names(keep_all[[tid]]), function(ph) {
      x <- seasons_of(keep_all[[tid]][[ph]])
      x <- x[!is.na(x$end), ]
      if (nrow(x)) data.frame(phase = ph, start = x$start, end = x$end, mid = x$start + as.numeric(x$end - x$start) / 2)
    }))
    for (e in irr) {
      d <- as.Date(e$date)
      cand <- win[win$start <= d & win$end >= d, ]
      if (!nrow(cand)) { dropped_irr <- dropped_irr + 1L; next }
      ph <- cand$phase[which.min(abs(as.numeric(cand$mid - d)))]
      keep_all[[tid]][[ph]][[length(keep_all[[tid]][[ph]]) + 1L]] <- e
    }
  }
  if (dropped_irr) cat(sprintf("%-18s irrigation events dropped: %d (%s)\n", tid, dropped_irr,
                               if (tid %in% RAINFED) "rainfed system" else
                                 sprintf("outside any cash crop window of %d days or less: generator artifacts", SEASON_DAYS)))
}

# Write --------------------------------------------------------------------------------------
summary_rows <- list()
for (tid in names(SYSTEMS)) for (ph in names(keep_all[[tid]])) {
  pe <- keep_all[[tid]][[ph]]
  pe <- Filter(function(e) as.Date(e$date) <= LAST_DATE, pe)
  stopifnot(!any(vapply(pe, function(e) is.na(e$date), TRUE)))
  pe <- pe[order(vapply(pe, `[[`, "", "date"), vapply(pe, `[[`, "", "event_type"))]
  slug <- gsub("-+", "-", gsub("[^a-z0-9]+", "-", tolower(ph)))
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
        "tools/event_prep/README.md. Fertilization is rebuilt from the package."),
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
