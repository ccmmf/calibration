#!/usr/bin/env Rscript
# Build the US-Bi2 (Bouldin corn, parcel 565118) events.json, 2016-2023: one corn cycle a year,
# the site record first and the monitoring product's planting and harvest days only where the
# record gives none.
#
# usage: us_bi2_build_events.R <managements.csv> <out.json> [member]
#   managements.csv: cal-val-data data/managements.csv (develop), the site record
#   member: the monitoring product's irrigation member, irr_ens_NNN (1 by default)
# Reads the planting and harvest v5.0 products under $PRODUCTS_INVENTORY/management
# (pull_inputs.sh) and $CCMMF_WORK/us_bi2_events/own_irrigation.csv (extract_parcel_csvs.R
# us_bi2 565118, irrigation v1.1).
#
# The site record (cal-val-data, US-Bi2__management_field) has corn planted every year from 2017
# to 2023, UAN applied once a year at planting at 118 kg N/ha (Anthony and Silver 2021), the 2019
# planting in May-June and the 2019 harvest on 2019-09-11, and the corn usually cut for silage.
# The monitoring product disagrees where the two overlap: it has a G6 winter cereal planted
# 2019-02-05 and harvested 2019-05-22, five days after the corn went in, when the field was
# flooded and anoxic until mid March 2019; N from the fertilization product (member 1) at 172 to
# 343 kg N/ha a year, 343 in 2019; and the 2019 harvest on 2019-10-03. So the G6 cycle and every
# fertilization product row are dropped, and the product gives only the days the record lacks.
#
# Water (decided 2026-07-16, Akash and Alexey): the irrigation product's zeros in the other years
# are real, its 2021 and 2022 events are kept, and the field's water table is represented by the
# winter floods and the run's flood configuration, since SIPNET does not draw water up from a water
# table and a run without them goes too dry. The winters the record dates are written as floods
# held by the rule US-Twt uses; the spud ditch sub-irrigation is not written.

script_file <- gsub("~+~", " ", sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)),
                    fixed = TRUE)
here <- if (length(script_file)) dirname(script_file) else "tools/event_prep"
source(file.path(here, "fill_order.R"))
source(file.path(here, "delta_inputs.R"))

args <- builder_args("us_bi2_build_events.R <managements.csv> <out.json> [member]")
SITE <- "US-Bi2"; PARCEL <- 565118L; CORN <- "F16"; YEARS <- 2016:2023
ANTHONY <- "10.1111/gcb.15802 (Anthony and Silver 2021)"
BIF <- "10.17190/AMF/1419513 (AmeriFlux US-Bi2 BIF)"
PRODUCT <- "monitoring_product:%s/v5.0 (parcel 565118)"
KG_HA_TO_KG_M2 <- 1e-4

# The hold rule us_twt_build_events.R uses: 70 mm every 7 d, the mean amount and modal interval of
# the monitoring product's flood events for US-Twt (parcel 590073, irrigation v1.1, irr_ens_001,
# 2017-2023). A reported winter flood window is held from its first day to its last.
FLOOD_MM <- 70; FLOOD_EVERY_D <- 7L; FLOOD_METHOD <- "soil"
FLOOD_RULE <- paste("70 mm every 7 d, the hold rule US-Twt uses (the mean amount and modal interval of the",
                    "monitoring product's flood events for parcel 590073, 2017-2023)")

# Days read from the fertilization line of Anthony and Silver 2021 Fig. 2, to within 1 to 2 days.
# UAN went on once a year at planting, so the corn was planted the same day. In 2020 the
# sensors came out in April-May for the field work; the product's 2020-04-05 planting is a month
# before the application.
FIG2 <- c("2019" = "2019-05-01", "2020" = "2020-05-04")

# The site record says the corn is usually cut for silage (delta-harvest-0014), which takes the
# whole aboveground plant, not the grain the F16 row (0.752 removed) stands for. The shared harvest
# lookup has no silage row; its hay row (class P, PFT hay, swat, n = 8; 0.892 as rounded on
# calibration#10, the row russell_harvest_lookup.csv carries) stands in, an assumption put to
# David on organization#298.
SILAGE <- harvest_fractions(above_removed = 0.892, below_removed = 0, above_to_litter = 0.108, below_to_litter = 1)
SILAGE_NOTE <- paste(
  "Assumed: the site record says the corn is usually cut for silage (delta-harvest-0014), which",
  "takes the whole aboveground plant. The shared harvest lookup has no silage row, so its hay row",
  "(0.892 removed, 0.108 to litter, the roots to litter) stands in for the F16 grain row (0.752);",
  "a proposal for David (organization#298).")

## ------------------------------------------------------------- site record
rec <- site_record(args$managements, c(
  "delta-fertilization-0013", "delta-fertilization-0014", "delta-harvest-0014", "delta-harvest-0016",
  sprintf("delta-planting-%04d", 12:18)))
stopifnot(all(rec$sites.name == "US-Bi2__management_field"),
          rec["delta-fertilization-0013", "level"] == "118",
          rec["delta-fertilization-0013", "units"] == "kg N ha-1 yr-1",
          rec["delta-fertilization-0014", "reported_material"] == "urea-ammonium nitrate (UAN)",
          rec["delta-fertilization-0014", "relative_timing"] == "at_planting",
          rec["delta-harvest-0014", "reported_material"] == "silage cattle feed",
          substr(rec["delta-harvest-0016", "min_date"], 1, 10) == "2019-09-11",
          all(rec[sprintf("delta-planting-%04d", 12:18), "crop_name"] == "corn"),
          substr(rec["delta-planting-0014", "min_date"], 1, 10) == "2019-05-01",
          substr(rec["delta-planting-0014", "max_date"], 1, 10) == "2019-06-30",
          FIG2[["2019"]] >= "2019-05-01", FIG2[["2019"]] <= "2019-06-30")
N_RATE_KG_HA <- as.numeric(rec["delta-fertilization-0013", "level"])
N_PUBLISHED_YEARS <- as.integer(fromJSON(rec["delta-fertilization-0014", "attributes_json"])$applicable_study_years)
planting_record <- setNames(sprintf("delta-planting-%04d", 12:18), 2017:2023)

## ------------------------------------------------------------- monitoring product, v5.0
pl <- v5_parcel_rows("planting", PARCEL)
hv <- v5_parcel_rows("harvest", PARCEL)
yr <- function(d) as.integer(substr(d, 1, 4))
# One crop cycle a year: drop the G6 cycle of 2019 and expect exactly one planting and one harvest
# in each year after it.
dropped <- rbind(pl[pl$crop_code == "G6", c("date", "crop_code")], hv[hv$crop_code == "G6", c("date", "crop_code")])
stopifnot(identical(dropped$date, c("2019-02-05", "2019-05-22")))
pl <- pl[pl$crop_code != "G6" & yr(pl$date) %in% YEARS, ]
hv <- hv[hv$crop_code != "G6" & yr(hv$date) %in% YEARS, ]
stopifnot(identical(yr(pl$date), YEARS), identical(yr(hv$date), YEARS),
          all(pl$crop_code[yr(pl$date) > 2016] == CORN), all(hv$crop_code[yr(hv$date) > 2016] == CORN))
f16_leaf <- pl$leaf_c_kg_m2[pl$crop_code == CORN]

events <- list()
add <- function(e) events[[length(events) + 1L]] <<- e
for (y in YEARS) {
  p <- pl[yr(pl$date) == y, ]; h <- hv[yr(hv$date) == y, ]
  label_note <- if (p$crop_code != CORN) sprintf(paste(
    "The product labels this crop %s; written as corn, assumed, to keep the field's continuous corn",
    "(the site record has corn every year from 2017, delta-planting-0012 to 0018)."), p$crop_code) else NULL
  record <- if (as.character(y) %in% names(planting_record)) planting_record[[as.character(y)]] else NULL

  # planting: the Fig. 2 day where the record dates the season, the product's day otherwise
  leaf <- first_available(list("this season's v5.0 F16 planting" = if (p$crop_code == CORN) p$leaf_c_kg_m2,
                               "the parcel's v5.0 F16 plantings, median" = f16_leaf))
  if (is.null(leaf)) stop("no v5.0 F16 planting for parcel ", PARCEL, " to take leaf C from")
  leaf_c <- if (leaf$n == 1L) leaf$value else median(leaf$value)
  plant_date <- if (as.character(y) %in% names(FIG2)) FIG2[[as.character(y)]] else p$date
  e <- list(event_type = "planting", date = plant_date, crop_code = CORN, crop_display = "Corn",
            leaf_c_kg_m2 = round(leaf_c, 8),
            prior_filled = sprintf("leaf_c_kg_m2<-%s%s", leaf$from, if (leaf$n > 1L) sprintf(" (%d)", leaf$n) else ""))
  e <- if (plant_date != p$date) {
    set_provenance(e, "imputed", source = paste0(ANTHONY, ", Fig. 2"), note = paste(
      "Planted on the day UAN was applied, read from the fertilization line of Fig. 2 (to within 1",
      "to 2 days); the paper applies UAN once a year at planting (delta-fertilization-0014).",
      if (y == 2019) "The record puts the 2019 planting in May-June (delta-planting-0014)."
      else "The sensors came out in April-May 2020 for the field work.",
      sprintf("The monitoring product has %s.", p$date),
      "Leaf C is the season's v5.0 planting, so the event is imputed (the date is derived)."))
  } else {
    set_provenance(e, "imputed", source = sprintf(PRODUCT, "planting"), note = paste(c(
      sprintf("The monitoring product's planting day; the site record gives %s.",
              if (is.null(record)) "no planting this year" else sprintf("the year only (%s)", record)),
      label_note), collapse = " "))
  }
  add(e)

  # fertilization: UAN once at planting, 118 kg N/ha (published for 2017-2020, carried to the
  # other years), all of it written as nh4_n_kg_m2: SIPNET takes NH4 and NO3 as one mineral N pool
  n_published <- y %in% N_PUBLISHED_YEARS
  f <- list(event_type = "fertilization", date = plant_date,
            nh4_n_kg_m2 = round(N_RATE_KG_HA * KG_HA_TO_KG_M2, 8), no3_n_kg_m2 = 0, org_n_kg_m2 = 0,
            material = "urea-ammonium nitrate (UAN)")
  rate_note <- if (n_published)
    sprintf("%g kg N/ha, the rate Anthony and Silver 2021 give for 2017-2020 (delta-fertilization-0013).", N_RATE_KG_HA)
  else sprintf("%g kg N/ha, the rate Anthony and Silver 2021 give for 2017-2020 (delta-fertilization-0013), carried to %d.", N_RATE_KG_HA, y)
  add(set_provenance(f, if (plant_date != p$date) "derived" else "imputed", source = ANTHONY, note = paste(
    "UAN once a year at planting (delta-fertilization-0014), on the planting day.", rate_note,
    "The N is written as nh4_n_kg_m2; SIPNET adds NH4 and NO3 into one mineral N pool.",
    "The fertilization product's rows for this parcel are not used.")))

  # harvest: the recorded 2019 day, the product's day otherwise; silage fractions
  h <- c(list(event_type = "harvest", crop_display = "Corn"), SILAGE,
         list(harvest_lookup_row = "P (hay)", harvest_fraction_note = SILAGE_NOTE))
  h <- if (y == 2019) {
    set_provenance(c(list(date = substr(rec["delta-harvest-0016", "min_date"], 1, 10)), h), "assumed",
                   source = paste0(BIF, "; cal-val-data delta-harvest-0016"), note = paste(
      "The date is recorded: the corn biomass harvest on the crop height measurement day",
      "(delta-harvest-0016). The paper delayed its 2019 harvest, so the monitoring product's",
      sprintf("%s is not ruled out. The fractions are assumed (harvest_fraction_note).", hv$date[yr(hv$date) == y])))
  } else {
    set_provenance(c(list(date = hv$date[yr(hv$date) == y]), h), "imputed", source = sprintf(PRODUCT, "harvest"),
                   note = paste(c("The monitoring product's harvest day; the site record gives no harvest date this year.",
                                  label_note, "The fractions are assumed (harvest_fraction_note)."), collapse = " "))
  }
  add(h[c("event_type", "date", setdiff(names(h), c("event_type", "date")))])
}

## ------------------------------------------------------------- water
year_of <- function(t) setNames(vapply(Filter(function(e) e$event_type == t, events), `[[`, "", "date"),
                                vapply(Filter(function(e) e$event_type == t, events), function(e) substr(e$date, 1, 4), ""))
plant_on <- year_of("planting"); harvest_on <- year_of("harvest")

# Surface irrigation: the monitoring product's events for this parcel, kept (2026-07-16). The record
# has the field irrigated through spud ditches (delta-irrigation-0003) but not on these dates; v5.0
# has no irrigation rows for this parcel.
irr_src <- paste0("monitoring_product:irrigation/v1.1:", args$irrigation_member)
irr <- irrigation_member_rows(parcel_csv("us_bi2", "irrigation"), args$irrigation_member,
                              sprintf("%d-01-01", min(YEARS)), sprintf("%d-12-31", max(YEARS)))
for (i in seq_len(nrow(irr))) {
  r <- irr[i, ]
  add(set_provenance(list(event_type = "irrigation", date = r$date, amount_mm = round(as.numeric(r$amount_mm), 4),
                          method = r$method),
                     "imputed", source = irr_src, note = paste(
    "Date, amount and method from the monitoring product for this parcel (irrigation v1.1), kept as",
    "decided on 2026-07-16: the product's zero years are real zeros and its 2021 and 2022 events stay.",
    "The site record has the field irrigated (spud ditches, delta-irrigation-0003) but not on this",
    "date, so the event is imputed. Irrigation v5.0 has no rows for this parcel.")))
}

# Winter floods: every US-Bi2 flooding row of the site record with a dated window, held by the
# US-Twt rule from the window's first day to its last. The record gives no onset, drain or depth
# for any of them; delta-flooding-0008 (autumn flooding of the fallow field) has no dates and is not
# written. The windows mean different things, which the notes keep apart.
mg <- read.csv(args$managements, colClasses = "character", na.strings = character())
fl <- mg[mg$sites.name == "US-Bi2__management_field" & startsWith(mg$event_id, "delta-flooding-"), ]
fl <- fl[substr(fl$min_date, 1, 2) == "20" & substr(fl$max_date, 1, 2) == "20", ]
fl <- fl[order(fl$min_date), ]
WINDOWS <- c(
  "delta-flooding-0012" = "reported event duration",
  "delta-flooding-0013" = "seasonal occurrence constraint",
  "delta-flooding-0009" = "flood-onset timing constraint",
  "delta-flooding-0014" = "seasonal occurrence constraint")
stopifnot(identical(sort(fl$event_id), sort(names(WINDOWS))),
          identical(vapply(fl$attributes_json, function(j) fromJSON(j)$interval_semantics, "", USE.NAMES = FALSE),
                    unname(WINDOWS[fl$event_id])))
WINDOW_NOTE <- c(
  "reported event duration" = "the record reports the field flooded through this window (Hemes et al. 2019)",
  "seasonal occurrence constraint" = paste(
    "the window is the field's November-March winter flood regime (Anthony and Silver 2024, Table 1)",
    "after the year's corn, not a reported duration"),
  "flood-onset timing constraint" = paste(
    "the window bounds only the onset (December 2019, after the 2019-09-11 harvest); the duration and",
    "the spring 2020 drain (delta-drainage-0006) are not dated, so the flood is held only to the end of",
    "the window"))
for (i in seq_len(nrow(fl))) {
  w <- fl[i, ]
  start <- as.Date(substr(w$min_date, 1, 10)); end <- as.Date(substr(w$max_date, 1, 10))
  y <- format(start, "%Y"); y_next <- as.character(as.integer(y) + 1L)
  # the flood falls between that year's harvest and the next year's planting
  stopifnot(format(start) > harvest_on[[y]], format(end) < plant_on[[y_next]])
  for (d in format(seq(start, end, by = FLOOD_EVERY_D), "%Y-%m-%d"))
    add(set_provenance(list(event_type = "irrigation", date = d, amount_mm = FLOOD_MM, method = FLOOD_METHOD),
                       "imputed", source = paste0("calval:managements/", w$event_id), note = paste(
      "Flood irrigation, written as soil irrigation (method 1); SIPNET's flood method is a placeholder.",
      sprintf("Holds the winter flood of %s, %s to %s: %s.", w$event_id, start, end, WINDOW_NOTE[[WINDOWS[[w$event_id]]]]),
      sprintf("Dated and sized by the rule, %s, from the window's first day to its last;", FLOOD_RULE),
      "the record gives no onset, drain or depth, so the event is imputed.")))
}

## ------------------------------------------------------------- write
write_events(SITE, list(
  parcel_id = PARCEL, crop = CORN, irrigation_member = args$irrigation_member,
  generator = "tools/event_prep/us_bi2_build_events.R",
  note = paste(
    "One corn cycle a year, 2016-2023, from the site record first (cal-val-data,",
    "US-Bi2__management_field) and the monitoring product's planting and harvest v5.0 days where",
    "the record gives none. The monitoring product's 2019 G6 cycle (planted 2019-02-05, harvested",
    "2019-05-22) is dropped: the field is continuous corn and was flooded and anoxic until mid",
    "March 2019. UAN at 118 kg N/ha once a year at planting (Anthony and Silver 2021) replaces the",
    "fertilization product's rows. The 2019 and 2020 planting and fertilization days are read from",
    "Anthony and Silver 2021 Fig. 2; the 2019 harvest is the recorded 2019-09-11. Harvests use the",
    "shared lookup's hay row for silage, an assumption for David. No tillage: the monitoring",
    "product's tillage is not used. Water, as decided on 2026-07-16: the irrigation product's 2021",
    "and 2022 events, and the record's dated winter floods (delta-flooding-0009, 0012, 0013, 0014)",
    sprintf("held by %d mm every %d d as soil irrigation. The spud ditch sub-irrigation", FLOOD_MM, FLOOD_EVERY_D),
    "(delta-irrigation-0004 to 0007) is subsurface water left to the water table and the run's flood",
    "configuration, which this file does not set. See tools/event_prep/README.md.")),
  events, args$out)
