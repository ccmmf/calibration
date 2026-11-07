#!/usr/bin/env Rscript
# Build the US-Twt (Twitchell rice, parcel 590073) events.json, one series for 2010-2023:
# 2010-2015 from Knox et al. 2016, 2016 from their medians, 2017-2023 from the monitoring
# product, and the flooding of 2010 to early 2017 from the tower's water table record.
#
# usage: us_twt_build_events.R <managements.csv> <out.json> [member]
#   managements.csv: cal-val-data data/managements.csv (develop); its Knox et al. 2016 rows
#   member: the monitoring product's irrigation member irr_ens_NNN and fertilization member
#     ens_NNN (1 by default)
# Reads $CCMMF_WORK/us_twt_events/own_planting.csv, own_harvest.csv and own_irrigation.csv
# (extract_parcel_csvs.R us_twt 590073), the fertilization product (pull_inputs.sh), and
# us_twt_wtd_water_dates.csv next to this script.
#
# This replaces a chain of four steps (literature build, a hand edit putting in the WTD flood
# and drain dates, us_twt_irrigation_schedule.R, us_twt_merge_2010_2023.R) that did not reproduce
# the committed file; the WTD dates are now a table the script reads.

script_file <- gsub("~+~", " ", sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)),
                    fixed = TRUE)
here <- if (length(script_file)) dirname(script_file) else "tools/event_prep"
source(file.path(here, "fill_order.R"))
source(file.path(here, "delta_inputs.R"))

args <- builder_args("us_twt_build_events.R <managements.csv> <out.json> [member]")
LABEL <- "us_twt"; SITE <- "US-Twt"; PARCEL <- 590073L; CROP <- "R1"
RUN_START <- "2010-01-01"; RUN_END <- "2023-12-31"
LITERATURE_YEARS <- 2010:2015       # Knox et al. 2016 Table 1
LITERATURE_FILL_YEAR <- 2016L       # no record: Knox ends with 2015, the product starts in 2017
MONITORING_START <- "2017-01-01"    # the product covers the parcel from 2017
MONITORING_FILL_YEAR <- 2017L       # the planting and harvest products have no 2017
KNOX <- "10.1002/2015JG003247"
WTD <- "ameriflux:US-Twt BASE-BADM 7-5 WTD"
LB_AC_TO_KG_HA <- 1.12085
KG_HA_TO_KG_M2 <- 1e-4

# Rice straw is not removed at this site: the curated Knox records say the residue is chopped and
# left on the soil surface over the winter fallow, and the fields are reflooded November to
# February to decompose it. Grain is about half the aboveground biomass.
STRAW_LEFT <- harvest_fractions(above_removed = 0.5, below_removed = 0, above_to_litter = 0.5, below_to_litter = 1)
STRAW_NOTE <- paste(
  "Grain removed, straw chopped and left on the field as Knox et al. (2016) describe. 0.5 is the",
  "harvest index for medium-grain Calrose rice (M-104, M-206), so grain is about half of",
  "aboveground biomass. Replaces the monitoring product's generic annual-crop default of 0.8, which",
  "is not rice- or site-specific and would remove the straw the source says stayed.")
RESIDUE_UNRESOLVED_YEARS <- 2014L   # delta-residue_treatment-0003

# Knox describes disking and then ring rolling before planting, without dates. They go on at
# planting minus 21 and 7 days in every year, the monitoring years included, as decided when the
# two windows were merged (2026-08-29, literature first). That decision said the monitoring
# product records no tillage for this parcel; it does (tillage v1.0 has 5 NDTI detections for
# 590073 in 2018-2022, v5.0 has 6 in 2017-2022), and they are not used here.
TILLAGE <- data.frame(implement = c("disking", "ring rolling"), days_before = c(21L, 7L),
                      eff = c(0.5, 0.2), record = c("delta-tillage-0001", "delta-tillage-0002"))

# Flood water is written as soil irrigation (method 1). SIPNET's flood method (2) is a placeholder
# that the build in use rejects, and write.events.SIPNET writes anything but "soil" as canopy
# irrigation (method 0), which evaporates part of each application at once (organization#298).
# Ponding itself comes from the run's FLOODING setting, not from these events.
FLOOD_METHOD <- "soil"
FLOOD_NOTE <- "Flood irrigation, written as soil irrigation (method 1); SIPNET's flood method is a placeholder."

## ------------------------------------------------------------- site record (Knox et al. 2016)
mg <- read.csv(args$managements, colClasses = "character", na.strings = character())
knox <- mg[mg$sites.name == SITE & mg$citation == KNOX, , drop = FALSE]
rec <- site_record(args$managements, c("delta-tillage-0001", "delta-tillage-0002", "delta-residue_treatment-0003"))
stopifnot(rec["delta-tillage-0001", "reported_material"] == "disking",
          rec["delta-tillage-0002", "reported_material"] == "ring rolling",
          grepl("2014 residue treatment remains unresolved", rec["delta-residue_treatment-0003", "notes"]))
d10 <- function(s) if (s %in% c("", "NA")) "" else substr(s, 1, 10)

# Leaf C at planting for every rice planting Knox records: the median of the monitoring product's
# R1 plantings for this parcel
plant <- parcel_csv(LABEL, "planting")
r1_leaf <- as.numeric(plant$C_LEAF[plant$code == CROP])
stopifnot(length(r1_leaf) >= 3L)
LEAF_C <- round(median(r1_leaf), 8)

n_from_grade <- function(rate_lb_ac, grade) {
  n_pct <- as.numeric(strsplit(grade, "-", fixed = TRUE)[[1]][1])
  # sprintf, not round(): R's round() disagrees with the committed values on rates near a tie
  as.numeric(sprintf("%.8f", rate_lb_ac * LB_AC_TO_KG_HA * (n_pct / 100) * KG_HA_TO_KG_M2))
}
fert_note <- function(rate, grade, n) sprintf(paste(
  "%s lb/ac of %s -> %s kg N m-2, all as ammonium (these are ammonium/urea-based products);",
  "source reports product and rate, not N form"), format(rate), grade, n)

events <- list()
add <- function(e) events[[length(events) + 1L]] <<- e
plantings <- character()   # year -> planting date, for tillage
for (i in seq_len(nrow(knox))) {
  r <- knox[i, ]
  md <- d10(r$min_date)
  if (!nzchar(md) || !as.integer(substr(md, 1, 4)) %in% LITERATURE_YEARS) next
  y <- as.integer(substr(md, 1, 4))
  window <- identical(tolower(r$estimated), "true")
  dnote <- if (window) sprintf("Knox et al. 2016 Table 1 window (%s): source reports a window %s..%s; earliest date used.",
                               r$event_id, md, d10(r$max_date))
           else paste0("Knox et al. 2016 Table 1 date (", r$event_id, ").")
  src <- paste0("calval:managements/", r$event_id)
  if (r$mgmttype == "planting") {
    plantings[as.character(y)] <- md
    add(set_provenance(list(event_type = "planting", date = md, crop_code = CROP, crop_display = r$crop_name,
                            leaf_c_kg_m2 = LEAF_C,
                            prior_filled = "leaf_c_kg_m2<-prior:us_twt_monitoring_product_median"),
                       "imputed", paste(dnote, "Leaf C is the median of the parcel's R1 plantings in the",
                                        "monitoring product, so the event is imputed."), src))
  } else if (r$mgmttype == "harvest") {
    note <- paste(c(dnote, STRAW_NOTE, if (y %in% RESIDUE_UNRESOLVED_YEARS) sprintf(paste(
      "Knox does not state the %d residue treatment, so this year's fraction is carried from the",
      "others rather than sourced."), y), paste("The fractions come from prior:rice_harvest_index,",
      "not from Knox, so the event is assumed.")), collapse = " ")
    e <- c(list(event_type = "harvest", date = md, crop_display = r$crop_name), STRAW_LEFT,
           list(prior_filled = "frac_above_removed_0to1,frac_above_to_litter_0to1<-prior:rice_harvest_index"))
    if (y %in% RESIDUE_UNRESOLVED_YEARS) e$residue_treatment_resolved <- FALSE
    add(set_provenance(e, "assumed", note, src))
  } else if (r$mgmttype == "fertilization") {
    rate <- as.numeric(r$level); n <- n_from_grade(rate, r$reported_material)
    add(set_provenance(list(event_type = "fertilization", date = md, nh4_n_kg_m2 = n, no3_n_kg_m2 = 0,
                            org_n_kg_m2 = 0, reported_rate_lb_ac = rate, reported_grade = r$reported_material),
                       "derived", paste(dnote, paste0(fert_note(rate, r$reported_material, n), "."),
                                        "N is computed from the reported rate and the grade's %N, so the event is derived."),
                       src))
  }
}
stopifnot(identical(names(plantings), as.character(LITERATURE_YEARS)))

## ------------------------------------------------------------- 2016, from the Knox medians
lit <- function(t) Filter(function(e) e$event_type == t, events)
fill_y <- LITERATURE_FILL_YEAR
lit_plant <- vapply(lit("planting"), `[[`, "", "date")
lit_harv <- vapply(lit("harvest"), `[[`, "", "date")
p16 <- date_of_doy(fill_y, median_doy(doy_of(lit_plant))); h16 <- date_of_doy(fill_y, median_doy(doy_of(lit_harv)))
plantings[as.character(fill_y)] <- p16
no_2016 <- sprintf(paste("No record dates the %d crop: Knox et al. 2016 end with 2015 and the monitoring product",
                         "(planting and harvest v1.0) has no %d rows for this parcel."), fill_y, fill_y)
add(set_provenance(list(event_type = "planting", date = p16, crop_code = CROP, crop_display = CROP,
                        leaf_c_kg_m2 = LEAF_C, prior_filled = "date<-synthesized:median_doy(2010-2015)"),
                   "imputed", paste(no_2016, sprintf("Dated by the median day of year of the %d Knox plantings, %s.",
                                                     length(lit_plant), "2010-2015")), KNOX))
add(set_provenance(c(list(event_type = "harvest", date = h16, crop_display = CROP), STRAW_LEFT,
                     list(prior_filled = "date<-synthesized:median_doy(2010-2015)")),
                   "imputed", paste(no_2016, "Dated by the median day of year of the Knox harvests, 2010-2015.", STRAW_NOTE),
                   KNOX))
# fertilization: the single application regime of 2013-2015, its median rate and day
recent <- Filter(function(e) substr(e$date, 1, 4) %in% c("2013", "2014", "2015"), lit("fertilization"))
stopifnot(length(recent) == 3L)
rate <- median(vapply(recent, function(e) e$reported_rate_lb_ac, 0))
grade <- recent[[length(recent)]]$reported_grade
n <- n_from_grade(rate, grade)
add(set_provenance(list(event_type = "fertilization", date = date_of_doy(fill_y, median_doy(doy_of(vapply(recent, `[[`, "", "date")))),
                        nh4_n_kg_m2 = n, no3_n_kg_m2 = 0, org_n_kg_m2 = 0, reported_rate_lb_ac = rate,
                        reported_grade = grade, prior_filled = "date,rate<-synthesized:median(2013-2015)"),
                   "imputed", paste(no_2016, "Rate and day are the medians of the 2013-2015 single application regime;",
                                    fert_note(rate, grade, n)), KNOX))

## ------------------------------------------------------------- 2017-2023, the monitoring product
harv <- parcel_csv(LABEL, "harvest")
irr <- irrigation_member_rows(parcel_csv(LABEL, "irrigation"), args$irrigation_member, MONITORING_START, RUN_END)
fert <- fertilization_member_rows(PARCEL, args$fertilization_member)
in_monitoring <- function(d) d >= MONITORING_START & d <= RUN_END
mon_y <- MONITORING_FILL_YEAR
fill_note <- sprintf("The planting and harvest products have no %d for this parcel; ", mon_y)

for (i in which(in_monitoring(plant$date))) {
  r <- plant[i, ]
  plantings[substr(r$date, 1, 4)] <- r$date
  add(set_provenance(list(event_type = "planting", date = r$date, crop_code = r$code, crop_display = r$code,
                          leaf_c_kg_m2 = round(as.numeric(r$C_LEAF), 8)),
                     "published", sprintf("Monitoring product planting row for parcel %s, %s.", PARCEL, substr(r$date, 1, 4)),
                     source = "monitoring_product:planting/v1.0"))
}
cp <- plant[plant$code == CROP & plant$season == 2, ]
p17 <- date_of_doy(mon_y, median_doy(doy_of(cp$date)))
plantings[as.character(mon_y)] <- p17
add(set_provenance(list(event_type = "planting", date = p17, crop_code = CROP, crop_display = CROP,
                        leaf_c_kg_m2 = round(median(as.numeric(cp$C_LEAF)), 8),
                        prior_filled = sprintf("date<-synthesized:%d_excluded_year", mon_y)),
                   "imputed", paste0(fill_note, sprintf(paste(
                     "dated by the median day of year of the parcel's %d R1 plantings (%s to %s), leaf C",
                     "their median."), nrow(cp), substr(min(cp$date), 1, 4), substr(max(cp$date), 1, 4))),
                   "monitoring_product:planting/v1.0"))

for (i in which(in_monitoring(harv$date))) {
  r <- harv[i, ]
  add(set_provenance(c(list(event_type = "harvest", date = r$date, crop_display = r$CLASS_SUBCLASS),
                       harvest_fractions(round(r$frac_above_removed_0to1, 4), round(r$frac_below_removed_0to1, 4),
                                         round(r$frac_above_to_litter_0to1, 4), round(r$frac_below_to_litter_0to1, 4))),
                     "published", sprintf("Monitoring product harvest row for parcel %s, %s, with its four fractions.",
                                          PARCEL, substr(r$date, 1, 4)),
                     source = "monitoring_product:harvest/v1.0"))
}
ch <- harv[harv$CLASS_SUBCLASS == CROP & harv$season == 2, ]
add(set_provenance(c(list(event_type = "harvest", date = date_of_doy(mon_y, median_doy(doy_of(ch$date))), crop_display = CROP),
                     harvest_fractions(round(median(ch$frac_above_removed_0to1), 4), round(median(ch$frac_below_removed_0to1), 4),
                                       round(median(ch$frac_above_to_litter_0to1), 4), round(median(ch$frac_below_to_litter_0to1), 4)),
                     list(prior_filled = sprintf("date<-synthesized:%d_excluded_year", mon_y))),
                   "imputed", paste0(fill_note, sprintf("dated by the median day of year of the parcel's %d R1 harvests, fractions their median.", nrow(ch))),
                   "monitoring_product:harvest/v1.0"))

fert_src <- paste0("monitoring_product:fertilization/v1.0:", args$fertilization_member)
for (i in which(in_monitoring(fert$date))) {
  r <- fert[i, ]
  add(set_provenance(list(event_type = "fertilization", date = r$date, nh4_n_kg_m2 = round(r$nh4_n_kg_m2, 8),
                          no3_n_kg_m2 = round(r$no3_n_kg_m2, 8), org_n_kg_m2 = round(r$org_n_kg_m2, 8),
                          org_c_kg_m2 = round(r$org_c_kg_m2, 8)),
                     "published", sprintf("Monitoring product fertilization row (%s) for parcel %s, %s.",
                                          args$fertilization_member, PARCEL, substr(r$date, 1, 4)),
                     source = fert_src))
}
cf <- fert[grepl(CROP, fert$crop_code), ]
if (nrow(cf)) add(set_provenance(list(
  event_type = "fertilization", date = date_of_doy(mon_y, median_doy(doy_of(cf$date))),
  nh4_n_kg_m2 = round(median(cf$nh4_n_kg_m2), 8), no3_n_kg_m2 = round(median(cf$no3_n_kg_m2), 8),
  org_n_kg_m2 = round(median(cf$org_n_kg_m2), 8), org_c_kg_m2 = round(median(cf$org_c_kg_m2), 8),
  prior_filled = sprintf("date<-synthesized:%d_excluded_year", mon_y)),
  "imputed", sprintf(paste("The planting and harvest products have no %d; dated by the median day of year of",
                           "the parcel's %d R1 applications in the fertilization product, each amount the median",
                           "of that amount over them (David's rule); %d of the %d carry organic N and C."),
                     mon_y, nrow(cf), sum(cf$org_n_kg_m2 > 0), nrow(cf)), fert_src))

irr_src <- paste0("monitoring_product:irrigation/v1.1:", args$irrigation_member)
for (i in seq_len(nrow(irr))) {
  r <- irr[i, ]
  flood <- r$method == "flood"
  add(set_provenance(list(event_type = "irrigation", date = r$date, amount_mm = round(r$amount_mm, 4),
                          method = if (flood) FLOOD_METHOD else r$method),
                     "published", source = irr_src, note = if (flood)
                       paste(FLOOD_NOTE, "The monitoring product gives the method as flood.")
                     else sprintf("The monitoring product gives %s irrigation here, not flood; kept as given.", r$method)))
}

## ------------------------------------------------------------- flooding, 2010 to early 2017
# Each flood the tower's water table record shows, from its onset to its drain, held by repeated
# applications: SIPNET has no persistent flood state or drain event, and a 0 mm irrigation does
# nothing. The amount and interval are the median amount and modal interval of the monitoring
# product's flood events for this parcel, 2017-2023.
mon_flood <- irr[irr$method == "flood", ]
FLOOD_MM <- round(median(mon_flood$amount_mm))
gaps <- as.integer(diff(as.Date(mon_flood$date)))
FLOOD_EVERY_D <- as.integer(names(which.max(table(gaps))))
rule <- sprintf(paste("%d mm every %d d, the median amount (%.1f mm) and modal interval of the monitoring product's",
                      "%d flood events for this parcel, 2017-2023 (%s)"),
                FLOOD_MM, FLOOD_EVERY_D, median(mon_flood$amount_mm), nrow(mon_flood), irr_src)

wtd <- read.csv(file.path(here, "us_twt_wtd_water_dates.csv"), colClasses = "character")
stopifnot(all(nzchar(wtd$drain)), sum(!nzchar(wtd$flood_onset)) == 1L, !nzchar(wtd$flood_onset[1]),
          all(wtd$flood_onset[-1] < wtd$drain[-1]), all(wtd$drain[-nrow(wtd)] < wtd$flood_onset[-1]),
          max(wtd$drain) < min(c(mon_flood$date, "9999")))
for (i in seq_len(nrow(wtd))) {
  w <- wtd[i, ]
  onset <- nzchar(w$flood_onset)
  start <- as.Date(if (onset) w$flood_onset else RUN_START); end <- as.Date(w$drain)
  d <- seq(start, end - 1L, by = FLOOD_EVERY_D)
  for (k in seq_along(d)) {
    e <- list(event_type = "irrigation", date = format(d[k], "%Y-%m-%d"), amount_mm = FLOOD_MM, method = FLOOD_METHOD)
    add(if (k == 1L && onset) {
      set_provenance(e, "imputed", source = paste0(WTD, "; ", irr_src), note = paste(
        FLOOD_NOTE, w$onset_note, sprintf("Held by %s, to the WTD-derived drain on %s.", rule, w$drain),
        "The date is derived from the WTD record but the amount is the rule's, so the event is imputed."))
    } else {
      set_provenance(e, "imputed", source = irr_src, note = paste(FLOOD_NOTE, if (onset)
        sprintf("Holds the %s flood that began %s (WTD onset) until the WTD-derived drain on %s;", w$season, w$flood_onset, w$drain)
        else sprintf("Holds the winter flood in place before the run starts until the WTD-derived drain on %s;", w$drain),
        sprintf("dated by the rule of %s.", rule)))
    })
  }
}

## ------------------------------------------------------------- tillage, every year
for (y in sort(names(plantings))) {
  p <- as.Date(plantings[[y]])
  carried <- !as.integer(y) %in% LITERATURE_YEARS
  for (k in seq_len(nrow(TILLAGE))) {
    t <- TILLAGE[k, ]
    add(set_provenance(list(event_type = "tillage", date = format(p - t$days_before, "%Y-%m-%d"),
                            tillage_eff_0to1 = t$eff, implement = t$implement),
                       if (carried) "imputed" else "assumed", source = paste0("calval:managements/", t$record), note = paste(c(
      if (carried)
        sprintf(paste("Knox's %s before planting (2010-2015, no dates) is carried into %s, which no site record covers,",
                      "so the event is imputed; dated %d d before that year's planting with"), t$implement, y, t$days_before)
      else
        sprintf("Knox reports %s before planting without dates; placed %d d before the %s planting with", t$implement,
                t$days_before, y),
      sprintf("tillage_eff %s.", t$eff),
      if (as.integer(y) >= as.integer(substr(MONITORING_START, 1, 4)))
        "The monitoring product's tillage detections for this parcel are not used."),
      collapse = " ")))
  }
}

## ------------------------------------------------------------- write
write_events(SITE, list(
  parcel_id = PARCEL, crop = CROP, irrigation_member = args$irrigation_member,
  fertilization_member = args$fertilization_member,
  generator = "tools/event_prep/us_twt_build_events.R",
  note = paste(
    "One continuous 2010-2023 series. 2010-2015 management is from Knox et al. 2016 (cal-val-data),",
    "2016 from their medians, and 2017-2023 from the statewide monitoring product, which does not",
    "cover this parcel before 2017. Floods from 2010 to March 2017 follow the AmeriFlux WTD record,",
    sprintf("each held by %d mm every %d d from its onset to its drain; all flood water is soil", FLOOD_MM, FLOOD_EVERY_D),
    "irrigation (method 1). Tillage in every year follows Knox's disking and ring rolling before",
    "planting. Per-event source and provenance_class record which applies to each event.",
    "See tools/event_prep/README.md.")),
  events, args$out)
