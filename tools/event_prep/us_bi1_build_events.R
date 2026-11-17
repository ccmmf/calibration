#!/usr/bin/env Rscript
# Build the US-Bi1 (Bouldin alfalfa, parcel 328163) events.json, 2017-2023: one alfalfa stand
# for the whole run, cut about six times a year, irrigated as the monitoring product has it.
#
# usage: us_bi1_build_events.R <managements.csv> <out.json> [member]
#   managements.csv: cal-val-data data/managements.csv (develop), the site record
#   member: the monitoring product's irrigation member, irr_ens_NNN (1 by default)
# Reads $CCMMF_WORK/us_bi1_events/own_planting.csv and own_irrigation.csv (extract_parcel_csvs.R
# us_bi1 328163) and us_bi1_cuttings.csv next to this script.
#
# The monitoring product plants P1 every spring and harvests it once a year with only
# frac_above_removed (0.75), which write.events.SIPNET completes as 0.75 0 0.25 1: the stand
# is killed and replanted every year. The field was one stand that had been in alfalfa about
# three years when the tower went in on 2016-08-12 (Paw U et al. 2018), cut about six times a
# year (delta-harvest-0010). So: one planting at the start of the run and cuttings that leave
# the stubble and roots alive.

script_file <- gsub("~+~", " ", sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)),
                    fixed = TRUE)
here <- if (length(script_file)) dirname(script_file) else "tools/event_prep"
source(file.path(here, "fill_order.R"))
source(file.path(here, "delta_inputs.R"))

args <- builder_args("us_bi1_build_events.R <managements.csv> <out.json> [member]")
LABEL <- "us_bi1"; SITE <- "US-Bi1"; PARCEL <- 328163L; CROP <- "P1"
RUN_START <- "2017-01-01"; RUN_END <- "2023-12-31"

# An intermediate cutting removes the shared harvest lookup's P1 share (0.85) and leaves the rest
# as living stubble, with the roots alive (David on calibration#10: "0.85, 0, 0, 0").
CUT <- harvest_fractions(above_removed = 0.85, below_removed = 0, above_to_litter = 0, below_to_litter = 0)
CUT_NOTE <- paste("Alfalfa cutting: the shared harvest lookup's P1 share (0.85) removed, the stubble and",
                  "roots left alive (David on calibration#10).")
STAND_SOURCE <- "Paw U et al. 2018, Field Campaign Report, Appendix B, p. B-SI-8"
WANG <- "Wang 2024, UC Berkeley PhD dissertation, Fig. 3.1 (US-Bi1 tower NDVI)"
HEMES <- "10.1016/j.agrformet.2019.01.017 (Hemes et al. 2019), Fig. S2 (daily NEE)"
BADM <- "10.17190/AMF/1480317 (AmeriFlux US-Bi1 BADM); cal-val-data delta-harvest-0012"

## ------------------------------------------------------------- site record
rec <- site_record(args$managements, c("delta-harvest-0010", "delta-harvest-0012", "delta-grazing-0002",
                                       "delta-irrigation-0008", "delta-irrigation-0009"))
stopifnot(rec["delta-harvest-0012", "sites.name"] == SITE,
          substr(rec["delta-harvest-0012", "min_date"], 1, 10) == "2020-06-04",
          rec["delta-harvest-0012", "reported_material"] == "mowing",
          grepl("six cuttings per year", rec["delta-harvest-0010", "notes"]),
          rec["delta-grazing-0002", "reported_material"] == "sheep grazing")

## ------------------------------------------------------------- planting
# One planting on the first day of the run. It sets the stand's state at the start rather than
# recording an operation: the stand went in about 2013, so its roots here are seedling scale and
# 2017 behaves as spin-up. Whether to start from an initial condition with a plant instead is
# David's call (organization#298).
plant <- parcel_csv(LABEL, "planting")
p1 <- plant[plant$code == CROP & plant$season == 2, ]
leaf <- first_available(list("the parcel's monitoring P1 plantings" = as.numeric(p1$C_LEAF)))
if (is.null(leaf)) stop("no P1 plantings for parcel ", PARCEL, " in the monitoring product")
events <- list(set_provenance(list(
  event_type = "planting", date = RUN_START, crop_code = CROP, crop_display = "Alfalfa",
  leaf_c_kg_m2 = round(median(leaf$value), 8),
  prior_filled = sprintf("leaf_c_kg_m2<-median of %s (%d, planting v1.0)", leaf$from, leaf$n)),
  "imputed", source = paste0(STAND_SOURCE, "; monitoring_product:planting/v1.0"),
  note = paste(
    "Sets the state of the alfalfa stand at the start of the run; it is not a planting operation.",
    "The field had been in alfalfa about three years when the tower went in on 2016-08-12",
    sprintf("(%s), so the stand dates from about 2013 and is kept for the whole run:", STAND_SOURCE),
    "the monitoring product's yearly P1 plantings are not used. The roots start at seedling scale,",
    "so 2017 behaves as spin-up. The date is assumed; leaf C is the median (David's rule) of",
    sprintf("%s (%d, 2018-2023), the weaker part, so the event is imputed.", leaf$from, leaf$n))))

## ------------------------------------------------------------- cuttings
cuts <- read.csv(file.path(here, "us_bi1_cuttings.csv"), colClasses = "character")
stopifnot(identical(names(cuts), c("date", "basis", "note")), all(nzchar(cuts$note)),
          !anyDuplicated(cuts$date), all(cuts$date >= RUN_START & cuts$date <= RUN_END),
          all(cuts$basis %in% c("wang2024_ndvi", "hemes2019_nee", "badm_mowing")),
          identical(cuts$date[cuts$basis == "badm_mowing"], substr(rec["delta-harvest-0012", "min_date"], 1, 10)))
for (i in seq_len(nrow(cuts))) {
  d <- cuts$date[i]
  e <- c(list(event_type = "harvest", date = d, crop_display = "Alfalfa"), CUT,
         list(harvest_lookup_row = "P1", harvest_fraction_note = CUT_NOTE))
  events[[length(events) + 1L]] <- switch(cuts$basis[i],
    badm_mowing = set_provenance(e, "assumed", source = BADM, note = paste(
      "The date is recorded: mowing the site record fixes from 'Mowed five days ago, baling today' on",
      "2020-06-09. The fractions are the shared lookup's P1 share (0.85, IPCC) with nothing sent to",
      "litter (David on calibration#10), so the event is assumed.", cuts$note[i])),
    hemes2019_nee = set_provenance(e, "imputed", source = HEMES, note = paste(
      "No record dates this cutting; dated from the jump in daily NEE in Hemes et al. 2019 Fig. S2,",
      "so the event is imputed. The site record gives about six cuttings a year (delta-harvest-0010).",
      cuts$note[i])),
    wang2024_ndvi = set_provenance(e, "imputed", source = WANG, note = paste(
      "No record dates this cutting; dated from the fall in the tower NDVI cycle in Wang 2024",
      "Fig. 3.1, to within about 3 to 5 days, so the event is imputed. The site record gives about six",
      "cuttings a year (delta-harvest-0010).", cuts$note[i])))
}

## ------------------------------------------------------------- irrigation
# Kept as the monitoring product has it. The site record (delta-irrigation-0008, 0009) has the
# field irrigated mainly below the surface from the adjacent ditches, with sporadic flash floods,
# but gives no dates or amounts, so the product's events fill them.
irr <- irrigation_member_rows(parcel_csv(LABEL, "irrigation"), args$irrigation_member, RUN_START, RUN_END)
for (i in seq_len(nrow(irr))) {
  r <- irr[i, ]
  events[[length(events) + 1L]] <- set_provenance(list(
    event_type = "irrigation", date = r$date, amount_mm = round(as.numeric(r$amount_mm), 4), method = r$method),
    "imputed", source = paste0("monitoring_product:irrigation/v1.1:", args$irrigation_member),
    note = paste(
      "Date, amount and method from the monitoring product for this parcel. The site record",
      "(delta-irrigation-0008, 0009) has the field irrigated mainly below the surface from the",
      "adjacent ditches, with sporadic flash floods, and gives no dates or amounts."))
}

## ------------------------------------------------------------- write
write_events(SITE, list(
  parcel_id = PARCEL, crop = CROP, irrigation_member = args$irrigation_member,
  generator = "tools/event_prep/us_bi1_build_events.R",
  note = paste(
    "One alfalfa stand for the whole run: a planting on the first day sets its state, and the",
    sprintf("%d cuttings each remove 0.85 of the shoots and leave the stubble and roots alive.", nrow(cuts)),
    "Cutting dates are read from the tower NDVI (Wang 2024 Fig. 3.1) and daily NEE (Hemes et al.",
    "2019 Fig. S2), except the recorded 2020-06-04 mowing. No tillage and no fertilization: the",
    "stand is not tilled and the site record gives no fertilizer. Winter sheep grazing",
    "(delta-grazing-0002) is left out: the record has no dates or stocking and SIPNET has no",
    "grazing event. Irrigation is the monitoring product's. See tools/event_prep/README.md.")),
  events, args$out)
