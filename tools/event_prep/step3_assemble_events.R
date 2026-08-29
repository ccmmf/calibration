#!/usr/bin/env Rscript
# Assemble US-Bi2 (parcel 565118) events.json from the statewide monitoring product
# and the fertilization parquet. 2017 is absent from the product and is synthesized.

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(jsonlite)
})
options(arrow.unsafe_metadata = TRUE)

PARCEL     <- 565118
SITE_NAME  <- "US-Bi2"
MEMBER     <- "ens_001"
SYNTH_YEAR <- 2017L
CORN       <- "F16"

TMP    <- "/projectnb2/dietzelab/ccmmf/usr/adey2/tmp"
EVDIR  <- file.path(TMP, "us_bi2_events")
FERT   <- "/projectnb2/dietzelab/ccmmf/usr/akash/event_files/fertilization.parquet"
OUT    <- file.path(EVDIR, "us_bi2_events.json")

## ------------------------------------------------------------- helpers
# David's circular median day-of-year. Assumes a single crop cycle.
median_doy <- function(doy) {
  doy <- na.omit(doy); doy[doy == 366] <- 365
  stopifnot(all(doy >= 1 & doy <= 365)); doy <- sort(doy)
  if (length(doy) < 2) return(doy)
  if (diff(range(doy)) <= 182) return(median(doy))
  gaps <- c(diff(doy), doy[1] + 365 - tail(doy, 1)); cut <- which.max(gaps)
  doy <- c(doy[(cut + 1):length(doy)], doy[1:cut] + 365)
  ((median(doy) - 1) %% 365) + 1
}
doy_of      <- function(d) as.integer(format(as.Date(d), "%j"))
date_of_doy <- function(y, doy) format(as.Date(paste0(y, "-01-01")) + (round(doy) - 1), "%Y-%m-%d")

## ------------------------------------------------------------- read sources
plant <- read.csv(file.path(EVDIR, "own_planting.csv"), stringsAsFactors = FALSE)
harv  <- read.csv(file.path(EVDIR, "own_harvest.csv"),   stringsAsFactors = FALSE)
irr   <- read.csv(file.path(EVDIR, "own_irrigation.csv"), stringsAsFactors = FALSE)
# irrigation has 10 ensemble members (irr_ens_001..010) with the SAME dates but
# different amounts. Single-member build -> keep one member only.
if ("ens_id" %in% names(irr)) {
  irr_mem <- if ("irr_ens_001" %in% irr$ens_id) "irr_ens_001" else sort(unique(irr$ens_id))[1]
  irr <- irr[irr$ens_id == irr_mem, ]
  cat("irrigation member kept: ", irr_mem, "\n", sep = "")
}

fert <- open_dataset(FERT) |>
  filter(site_id == PARCEL, event_member_id == MEMBER) |>
  collect() |> as.data.frame()
fert$date <- as.Date(fert$date)
num <- c("nh4_n_kg_m2","no3_n_kg_m2","org_c_kg_m2","org_n_kg_m2")
fert[num] <- lapply(fert[num], as.numeric)

cat("read: plant=", nrow(plant), " harv=", nrow(harv),
    " irr=", nrow(irr), " fert=", nrow(fert), " rows\n", sep = "")

## ------------------------------------------------------------- 2017 synthesis
# corn cycle = F16, season 2
cp <- plant[plant$code == CORN & plant$season == 2, ]
ch <- harv[harv$CLASS_SUBCLASS == CORN & harv$season == 2, ]
cf <- fert[grepl(CORN, fert$crop_code), ]

p17_date <- date_of_doy(SYNTH_YEAR, median_doy(doy_of(cp$date)))
h17_date <- date_of_doy(SYNTH_YEAR, median_doy(doy_of(ch$date)))
f17_date <- date_of_doy(SYNTH_YEAR, median_doy(doy_of(cf$date)))

cat("\nsynthesized 2017 (corn): planting=", p17_date,
    " harvest=", h17_date, " fert=", f17_date, "\n", sep = "")

## ------------------------------------------------------------- build events
events <- list()
add <- function(e) events[[length(events) + 1]] <<- e

# --- planting (all real events + synthesized 2017) ---
for (i in seq_len(nrow(plant))) {
  r <- plant[i, ]
  add(list(event_type = "planting", date = as.character(r$date),
           source = "monitoring_product:planting/v1.0",
           crop_code = r$code, crop_display = r$code,
           leaf_c_kg_m2 = round(as.numeric(r$C_LEAF), 8)))
}
add(list(event_type = "planting", date = p17_date,
         source = "synthesized:median_doy(2018-2023 F16)",
         crop_code = CORN, crop_display = CORN,
         leaf_c_kg_m2 = round(mean(as.numeric(cp$C_LEAF)), 8),
         prior_filled = "date<-synthesized:2017_excluded_year"))

# --- harvest (all real + synthesized 2017) ---
for (i in seq_len(nrow(harv))) {
  r <- harv[i, ]
  add(list(event_type = "harvest", date = as.character(r$date),
           source = "monitoring_product:harvest/v1.0",
           crop_display = r$CLASS_SUBCLASS,
           frac_above_removed_0to1 = round(as.numeric(r$frac_above_removed_0to1), 4)))
}
add(list(event_type = "harvest", date = h17_date,
         source = "synthesized:median_doy(2018-2023 F16)",
         crop_display = CORN,
         frac_above_removed_0to1 = round(mean(as.numeric(ch$frac_above_removed_0to1)), 4),
         prior_filled = "date<-synthesized:2017_excluded_year"))

# --- irrigation (real 2021-2022 only; zeros elsewhere are real) ---
for (i in seq_len(nrow(irr))) {
  r <- irr[i, ]
  add(list(event_type = "irrigation", date = as.character(r$date),
           source = "monitoring_product:irrigation/v1.1",
           amount_mm = round(as.numeric(r$amount_mm), 4),
           method = r$method))
}

# --- fertilization (all real + synthesized 2017) ---
for (i in seq_len(nrow(fert))) {
  r <- fert[i, ]
  add(list(event_type = "fertilization", date = as.character(r$date),
           source = "akash:fertilization.parquet",
           nh4_n_kg_m2 = round(r$nh4_n_kg_m2, 8),
           no3_n_kg_m2 = round(r$no3_n_kg_m2, 8),
           org_n_kg_m2 = round(r$org_n_kg_m2, 8)))
}
add(list(event_type = "fertilization", date = f17_date,
         source = "synthesized:median_doy(2018-2023 F16)",
         nh4_n_kg_m2 = round(mean(cf$nh4_n_kg_m2), 8),
         no3_n_kg_m2 = round(mean(cf$no3_n_kg_m2), 8),
         org_n_kg_m2 = round(mean(cf$org_n_kg_m2), 8),
         prior_filled = "date<-synthesized:2017_excluded_year"))

# sort by date
ord <- order(vapply(events, function(e) e$date, character(1)))
events <- events[ord]

## ------------------------------------------------------------- write json
doc <- list(
  pecan_events_version = "0.1.1",
  site_id = SITE_NAME,
  provenance = list(
    parcel_id = PARCEL,
    member = MEMBER,
    generator = "adey2:step3_assemble_events",
    note = "single-member; 2017 synthesized (corn); irrigation zeros are real; flood config handled separately"
  ),
  events = events
)

write_json(doc, OUT, auto_unbox = TRUE, pretty = TRUE, digits = 8)

cat("\nwrote ", length(events), " events -> ", OUT, "\n", sep = "")
cat("event-type counts:\n")
print(table(vapply(events, function(e) e$event_type, character(1))))
cat("date range: ",
    min(vapply(events, function(e) e$date, character(1))), " to ",
    max(vapply(events, function(e) e$date, character(1))), "\n", sep = "")
