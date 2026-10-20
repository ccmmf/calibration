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
SOURCE <- "10.1002/ecy.2105"
TON_AC_TO_KG_M2 <- 907.18474 / 4046.8564224  # US short ton per acre (per David)
KG_HA_TO_KG_M2 <- 1e-4

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
hrv <- rd("operations_harvest.csv")
frt <- rd("operations_fertilizers.csv")
cmp <- rd("operations_compost.csv")
ana <- rd("compost_analyses_summary.csv")

op_table <- function(df, date_col, crop_col) {
  d <- data.frame(system = df$system_name, plot = df$plot, date = as_date(df[[date_col]]),
                  crop = tolower(df[[crop_col]]), stringsAsFactors = FALSE)
  d$phase <- unname(phase_of[sp(d$system, d$plot)])
  d[!is.na(d$phase) & !is.na(d$date), ]
}
ops <- list(planting = op_table(plt, "Date", "Crop_planted"),
            harvest = op_table(hrv, "date", "crop_harvested"))

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
frt$phase <- unname(phase_of[sp(frt$system_name, frt$plot)])
frt <- frt[!is.na(frt$phase), ]
frt <- unique(frt)  # the package repeats some plot rows verbatim
frt <- frt[!is.na(frt$n) & frt$n > 0, ]
fert_n <- field_mean(frt, "n")
mats <- aggregate(material_applied ~ system_name + phase + date, data = frt,
                  FUN = function(m) paste(sort(unique(m)), collapse = "; "))
fert_n <- merge(fert_n, mats, all.x = TRUE)

cmp$date <- as_date(cmp$date)
cmp$wet <- as.numeric(cmp$compost_applied_wet_weight)
cmp$phase <- unname(phase_of[sp(cmp$system_name, cmp$plot)])
stopifnot(all(cmp$material_units == "tons/acre"), !anyNA(cmp$phase), !anyNA(cmp$date))
cmp <- unique(cmp[, c("system_name", "phase", "date", "plot", "wet")])
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
# disjoint plots; the merged event takes the date most plots share (earliest on a tie) and
# the mean of the generator's amounts. Alfalfa cuttings, about a month apart, stay separate.
MERGE_DAYS <- 14
AMOUNT_FIELDS <- c("leaf_c_kg_m2", "wood_c_kg_m2", "fine_root_c_kg_m2", "coarse_root_c_kg_m2",
                   "frac_above_removed_0to1", "frac_below_removed_0to1",
                   "frac_above_to_litter_0to1", "frac_below_to_litter_0to1")
merge_events <- function(grp, plots) {
  if (length(grp) == 1L) return(grp[[1]])
  base <- grp[[order(-lengths(plots), vapply(grp, `[[`, "", "date"))[1]]]
  for (f in intersect(AMOUNT_FIELDS, names(base)))
    base[[f]] <- round(mean(vapply(grp, function(e) as.numeric(e[[f]]), 0)), 4)
  base$merged_dates <- paste(vapply(grp, `[[`, "", "date"), collapse = ";")
  base$merge_note <- sprintf(paste("One operation recorded on %d dates; dated by the day most",
                                   "plots share (earliest on a tie), generator amounts averaged."),
                             length(grp))
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

summary_rows <- list()
for (tid in names(SYSTEMS)) {
  sys <- SYSTEMS[[tid]]
  src <- jsonlite::fromJSON(file.path(stacked_dir, sprintf("russell_ranch_tautges_2019_%s.json", tid)),
                            simplifyDataFrame = FALSE)
  ev <- src$events
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

  last_year <- max(as.integer(substr(vapply(ev, `[[`, "", "date"), 1, 4)))
  for (ph in phases) keep[[ph]] <- c(keep[[ph]], fert_events(sys, ph, last_year))

  # irrigation was injected at the midpoint of each cash crop window; give each event to
  # the phase whose own window midpoint it sits on. Rainfed systems get none.
  irr <- Filter(function(e) identical(e$event_type, "irrigation"), ev)
  dropped_irr <- 0L
  if (tid %in% RAINFED) {
    dropped_irr <- length(irr)
  } else {
    win <- do.call(rbind, lapply(phases, function(ph) {
      pe <- keep[[ph]]
      pl <- Filter(function(e) e$event_type == "planting" && tolower(e$crop_display) %in% CASH_CROPS, pe)
      hv <- Filter(function(e) e$event_type == "harvest" && tolower(e$crop_display) %in% CASH_CROPS, pe)
      if (!length(pl)) return(NULL)
      do.call(rbind, lapply(pl, function(p) {
        h <- Filter(function(x) tolower(x$crop_display) == tolower(p$crop_display) &&
                      as.Date(x$date) > as.Date(p$date), hv)
        if (!length(h)) return(NULL)
        hd <- min(as.Date(vapply(h, `[[`, "", "date")))
        data.frame(phase = ph, start = as.Date(p$date), end = hd,
                   mid = as.Date(p$date) + as.numeric(hd - as.Date(p$date)) / 2)
      }))
    }))
    for (e in irr) {
      d <- as.Date(e$date)
      cand <- win[win$start <= d & win$end >= d, ]
      if (!nrow(cand)) { dropped_irr <- dropped_irr + 1L; next }
      ph <- cand$phase[which.min(abs(as.numeric(cand$mid - d)))]
      keep[[ph]][[length(keep[[ph]]) + 1L]] <- e
    }
  }

  for (ph in phases) {
    pe <- keep[[ph]]
    ord <- order(vapply(pe, `[[`, "", "date"), vapply(pe, `[[`, "", "event_type"))
    pe <- pe[ord]
    slug <- gsub("-+", "-", gsub("[^a-z0-9]+", "-", tolower(ph)))
    out <- list(
      pecan_events_version = "0.1.1",
      site_id = sprintf("%s__%s", tid, slug),
      provenance = list(
        dataset_id = "russell_ranch_tautges_2019", treatment = tid, rotation_phase = ph,
        generator = "calibration:tools/event_prep/russell_split_phases.R",
        stacked_input = sprintf("generator_stacked/russell_ranch_tautges_2019_%s.json", tid),
        note = paste(
          "One rotation phase of the treatment. Planting, harvest and irrigation events come",
          "from the stacked generator output, assigned to this phase by the plot ids in the",
          "Century package; their amounts are still the generator's prior fills",
          "(prior_filled). Fertilization is rebuilt from the package.")),
      events = pe)
    fn <- file.path(out_dir, sprintf("russell_ranch_tautges_2019_%s__%s.json", tid, slug))
    write(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = 1, digits = NA), fn)

    yrs <- substr(vapply(pe, `[[`, "", "date"), 1, 4)
    for (y in sort(unique(yrs))) {
      ye <- pe[yrs == y]
      g <- function(f) sum(vapply(ye, function(e) as.numeric(if (is.null(e[[f]])) 0 else e[[f]]), 0))
      cash <- function(t) paste(sort(vapply(Filter(function(e) e$event_type == t &&
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
  if (dropped_irr) cat(sprintf("%-18s irrigation events dropped: %d (%s)\n", tid, dropped_irr,
                               if (tid %in% RAINFED) "rainfed system" else "outside any cash crop window"))
}

smry <- do.call(rbind, summary_rows)
write.csv(smry, file.path(out_dir, "phase_year_summary.csv"), row.names = FALSE)
cat(sprintf("wrote %d phase-year rows to phase_year_summary.csv\n", nrow(smry)))
