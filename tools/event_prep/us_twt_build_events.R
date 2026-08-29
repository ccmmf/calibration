#!/usr/bin/env Rscript
# Build the US-Twt 2010-2016 events.json from the curated Knox et al. 2016 records.
# 2016 is synthesized: the monitoring product's export omits this parcel.

suppressMessages(library(jsonlite))

KNOX <- "10.1002/2015JG003247"
SITE <- "US-Twt"
CROP <- "R1"
LEAF_C_KG_M2 <- 0.02455947   # median of the monitoring-product values for this site and crop
FRAC_ABOVE_REMOVED <- 0.8
LB_AC_TO_KG_HA <- 1.12085
KG_HA_TO_KG_M2 <- 1e-4
FLOOD_AFTER_PLANTING_D <- c(45, 60)
DRAIN_BEFORE_HARVEST_D <- c(30, 45)

installed_schema_version <- function(default = "0.1.0") {
  hits <- Sys.glob(file.path(path.expand("~/R"), "*", "*", "PEcAn.data.land",
                             "events_schema_v*.json"))
  if (!length(hits)) return(default)
  v <- sub("^events_schema_v", "", sub("\\.json$", "", basename(hits)))
  sort(v)[length(v)]
}

n_from_grade <- function(rate_lb_ac, grade) {
  n_pct <- as.numeric(strsplit(as.character(grade), "-", fixed = TRUE)[[1]][1])
  # sprintf, not round(): R's round() is documented as unreliable for digits > 0
  # and disagrees with the committed values on rates that land near a tie
  as.numeric(sprintf("%.8f", rate_lb_ac * LB_AC_TO_KG_HA * (n_pct / 100) * KG_HA_TO_KG_M2))
}

d10 <- function(s) {
  s <- substr(if (is.na(s)) "" else s, 1, 10)
  if (s %in% c("", "NA")) "" else s
}

med_doy <- function(dates) as.integer(median(as.integer(format(as.Date(dates), "%j"))))
from_doy <- function(doy, year = 2016) format(as.Date(paste0(year, "-01-01")) + (doy - 1), "%Y-%m-%d")

build <- function(rows, years) {
  events <- list()
  add <- function(ev, cls, src, note = NULL) {
    ev$provenance_class <- cls; ev$source <- src
    if (!is.null(note) && nzchar(note)) ev$provenance_note <- note
    events[[length(events) + 1L]] <<- ev
  }
  plantings <- list()
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    md <- d10(r$min_date)
    if (!nzchar(md)) next
    yr <- as.integer(substr(md, 1, 4))
    if (!(yr %in% years)) next
    estimated <- identical(tolower(as.character(r$estimated)), "true")
    cls <- if (estimated) "derived" else "published"
    note <- if (estimated)
      sprintf("source reports a window %s..%s; earliest date used", md, d10(r$max_date)) else NULL
    src <- paste0("calval:managements/", r$event_id)

    if (identical(r$mgmttype, "planting")) {
      plantings[[as.character(yr)]] <- md
      add(list(event_type = "planting", date = md, crop_code = CROP,
               crop_display = if (is.na(r$crop_name)) CROP else r$crop_name,
               leaf_c_kg_m2 = LEAF_C_KG_M2,
               prior_filled = "leaf_c_kg_m2<-prior:us_twt_monitoring_product_median"),
          cls, src, note)
    } else if (identical(r$mgmttype, "harvest")) {
      add(list(event_type = "harvest", date = md,
               crop_display = if (is.na(r$crop_name)) CROP else r$crop_name,
               frac_above_removed_0to1 = FRAC_ABOVE_REMOVED,
               prior_filled = "frac_above_removed_0to1<-prior:R1_default"),
          cls, src, note)
    } else if (identical(r$mgmttype, "fertilization")) {
      rate <- as.numeric(r$level); grade <- r$reported_material
      n <- n_from_grade(rate, grade)
      add(list(event_type = "fertilization", date = md,
               nh4_n_kg_m2 = n, no3_n_kg_m2 = 0, org_n_kg_m2 = 0,
               reported_rate_lb_ac = rate, reported_grade = grade),
          cls, src,
          paste0(if (!is.null(note)) paste0(note, "; ") else "",
                 sprintf(paste("%s lb/ac of %s -> %s kg N m-2, all as ammonium (these are",
                               "ammonium/urea-based products); source reports product and rate,",
                               "not N form"), rate, grade, n)))
    }
  }
  # tillage: Knox describes disking and ring rolling before planting, without dates
  for (yr in sort(names(plantings))) {
    p <- as.Date(plantings[[yr]])
    for (k in 1:2) {
      off <- c(-21, -7)[k]; mat <- c("disking", "ring rolling")[k]; eff <- c(0.5, 0.2)[k]
      add(list(event_type = "tillage", date = format(p + off, "%Y-%m-%d"),
               tillage_eff_0to1 = eff, implement = mat),
          "assumed",
          paste0("calval:managements/delta-tillage-000", if (mat == "disking") 1 else 2),
          sprintf("Knox reports %s before planting without dates; placed %d d before planting",
                  mat, abs(off)))
    }
  }
  events
}

water_events_from_ranges <- function(pl, hv) {
  out <- list()
  for (yr in sort(intersect(names(pl), names(hv)))) {
    p <- as.Date(pl[[yr]]); h <- as.Date(hv[[yr]])
    flood <- p + sum(FLOOD_AFTER_PLANTING_D) %/% 2
    drain <- h - sum(DRAIN_BEFORE_HARVEST_D) %/% 2
    out[[length(out) + 1L]] <- list(
      list(event_type = "irrigation", date = format(flood, "%Y-%m-%d"),
           amount_mm = 150, method = "flood"),
      "assumed", "calval:managements/delta-flooding-0006",
      sprintf("Knox reports flood-up %d-%d d after planting; midpoint used. Replace with WTD-derived date.",
              FLOOD_AFTER_PLANTING_D[1], FLOOD_AFTER_PLANTING_D[2]))
    out[[length(out) + 1L]] <- list(
      list(event_type = "irrigation", date = format(drain, "%Y-%m-%d"),
           amount_mm = 0, method = "flood"),
      "assumed", "calval:managements/delta-drainage-0001",
      sprintf(paste("Knox reports drain %d-%d d before harvest; midpoint used.",
                    "amount 0 marks the drain. Replace with WTD-derived date."),
              DRAIN_BEFORE_HARVEST_D[1], DRAIN_BEFORE_HARVEST_D[2]))
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
calval <- if (length(args) >= 1) args[1] else "../cal-val-data/data/managements.csv"
outfile <- if (length(args) >= 2) args[2] else "/tmp/us_twt_events_2010_2016.json"

mg <- read.csv(calval, colClasses = "character")
rows <- mg[grepl("Twt", mg$sites.name) & mg$citation == KNOX, , drop = FALSE]
events <- build(rows, 2010:2015)

getd <- function(ev, t) {
  x <- Filter(function(e) identical(e$event_type, t), ev)
  setNames(lapply(x, function(e) e$date), vapply(x, function(e) substr(e$date, 1, 4), character(1)))
}
for (tr in water_events_from_ranges(getd(events, "planting"), getd(events, "harvest"))) {
  ev <- tr[[1]]; ev$provenance_class <- tr[[2]]; ev$source <- tr[[3]]; ev$provenance_note <- tr[[4]]
  events[[length(events) + 1L]] <- ev
}

# --- synthesize 2016: absent from the monitoring product export (site_id 0..99999) ---
pl <- getd(events, "planting"); hv <- getd(events, "harvest")
ferts <- Filter(function(e) identical(e$event_type, "fertilization"), events)
add_tr <- function(ev, cls, src, note) {
  ev$provenance_class <- cls; ev$source <- src; ev$provenance_note <- note
  events[[length(events) + 1L]] <<- ev
}
pd_ <- from_doy(med_doy(unlist(pl))); hd_ <- from_doy(med_doy(unlist(hv)))
add_tr(list(event_type = "planting", date = pd_, crop_code = CROP, crop_display = CROP,
            leaf_c_kg_m2 = LEAF_C_KG_M2,
            prior_filled = "date<-synthesized:median_doy(2010-2015)"),
       "assumed", "synthesized:median_doy",
       paste("2016 absent from the monitoring product export (covers site_id 0..99999);",
             "date is the 2010-2015 median day of year"))
add_tr(list(event_type = "harvest", date = hd_, crop_display = CROP,
            frac_above_removed_0to1 = FRAC_ABOVE_REMOVED,
            prior_filled = "date<-synthesized:median_doy(2010-2015)"),
       "assumed", "synthesized:median_doy",
       "2016 absent from the monitoring product export; date is the 2010-2015 median DOY")
recent <- Filter(function(f) substr(f$date, 1, 4) %in% c("2013", "2014", "2015"), ferts)
if (length(recent)) {
  rate <- median(vapply(recent, function(f) as.numeric(f$reported_rate_lb_ac), numeric(1)))
  grade <- recent[[length(recent)]]$reported_grade
  n <- n_from_grade(rate, grade)
  fdoy <- med_doy(vapply(recent, function(f) f$date, character(1)))
  add_tr(list(event_type = "fertilization", date = from_doy(fdoy),
              nh4_n_kg_m2 = n, no3_n_kg_m2 = 0, org_n_kg_m2 = 0,
              reported_rate_lb_ac = rate, reported_grade = grade,
              prior_filled = "date,rate<-synthesized:median(2013-2015)"),
         "assumed", "synthesized:median_doy",
         paste("2016 absent from the monitoring product export; rate and date are the",
               "median of the 2013-2015 single-application regime"))
}
# tillage and water events for the synthesized year, so every crop year matches
p16d <- as.Date(pd_)
for (k in 1:2) {
  off <- c(-21, -7)[k]; mat <- c("disking", "ring rolling")[k]; eff <- c(0.5, 0.2)[k]
  add_tr(list(event_type = "tillage", date = format(p16d + off, "%Y-%m-%d"),
              tillage_eff_0to1 = eff, implement = mat),
         "assumed", paste0("calval:managements/delta-tillage-000", if (mat == "disking") 1 else 2),
         sprintf(paste("Knox reports %s before planting without dates; placed %d d before",
                       "the synthesized 2016 planting"), mat, abs(off)))
}
for (tr in water_events_from_ranges(list("2016" = pd_), list("2016" = hd_))) {
  ev <- tr[[1]]; ev$provenance_class <- tr[[2]]; ev$source <- tr[[3]]; ev$provenance_note <- tr[[4]]
  events[[length(events) + 1L]] <- ev
}

ord <- order(vapply(events, function(e) e$date, character(1)),
             vapply(events, function(e) e$event_type, character(1)))
events <- events[ord]

doc <- list(
  pecan_events_version = installed_schema_version(), site_id = SITE,
  provenance = list(parcel_id = 590073L, crop = CROP,
                    generator = "tools/event_prep/us_twt_build_events.R",
                    note = paste("2010-2015 management from curated Knox et al. 2016 records",
                                 "(cal-val-data); water events from Knox intervals pending WTD;",
                                 "2016 synthesized, absent from the monitoring product export")),
  events = events)
write(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = 1, digits = NA), outfile)

cat(sprintf("wrote %d events -> %s\n", length(events), outfile))
print(table(vapply(events, function(e) e$event_type, character(1))))
print(table(vapply(events, function(e) e$provenance_class, character(1))))
