#!/usr/bin/env Rscript
# Assemble one Delta site's events.json from the monitoring product. Parameterized.
# Usage: step3_delta_assemble.R <label> <parcel_id> <crop_code> <synth_year> <start> <end>

suppressPackageStartupMessages({ library(arrow); library(dplyr); library(jsonlite) })
options(arrow.unsafe_metadata = TRUE)

a <- commandArgs(trailingOnly = TRUE)
LABEL <- a[1]; PARCEL <- as.integer(a[2]); CROP <- a[3]
SYNTH_YEAR <- as.integer(a[4]); RUN_START <- as.Date(a[5]); RUN_END <- as.Date(a[6])

TMP <- "/projectnb2/dietzelab/ccmmf/usr/adey2/tmp"
EVDIR <- file.path(TMP, paste0(LABEL, "_events"))
FERT <- "/projectnb2/dietzelab/ccmmf/usr/akash/event_files/fertilization.parquet"
OUT <- file.path(EVDIR, paste0(LABEL, "_events.json"))

median_doy <- function(doy) {
  doy <- na.omit(doy); doy[doy == 366] <- 365
  stopifnot(all(doy >= 1 & doy <= 365)); doy <- sort(doy)
  if (length(doy) < 2) return(doy)
  if (diff(range(doy)) <= 182) return(median(doy))
  gaps <- c(diff(doy), doy[1] + 365 - tail(doy, 1)); cut <- which.max(gaps)
  doy <- c(doy[(cut + 1):length(doy)], doy[1:cut] + 365); ((median(doy) - 1) %% 365) + 1
}
doy_of <- function(d) as.integer(format(as.Date(d), "%j"))
dfd <- function(y, doy) format(as.Date(paste0(y,"-01-01")) + (round(doy)-1), "%Y-%m-%d")
rd <- function(f) if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE) else NULL

plant <- rd(file.path(EVDIR,"own_planting.csv"))
harv  <- rd(file.path(EVDIR,"own_harvest.csv"))
irr   <- rd(file.path(EVDIR,"own_irrigation.csv"))
if (!is.null(irr) && "ens_id" %in% names(irr)) {
  m <- if ("irr_ens_001" %in% irr$ens_id) "irr_ens_001" else sort(unique(irr$ens_id))[1]
  irr <- irr[irr$ens_id == m, ]
}
fert <- tryCatch(open_dataset(FERT) |> filter(site_id==PARCEL, event_member_id=="ens_001") |>
                   collect() |> as.data.frame(), error=function(e) NULL)
if (!is.null(fert) && nrow(fert)) { fert$date <- as.Date(fert$date)
  for (n in c("nh4_n_kg_m2","no3_n_kg_m2","org_c_kg_m2","org_n_kg_m2")) fert[[n]] <- as.numeric(fert[[n]]) }

# crop-matched cycles for synthesis (season 2)
cp <- plant[plant$code==CROP & plant$season==2, ]
ch <- harv[harv$CLASS_SUBCLASS==CROP & harv$season==2, ]
cf <- if (!is.null(fert) && nrow(fert)) fert[grepl(CROP, fert$crop_code), ] else fert[0,]

p17 <- if (nrow(cp)) dfd(SYNTH_YEAR, median_doy(doy_of(cp$date))) else NA
h17 <- if (nrow(ch)) dfd(SYNTH_YEAR, median_doy(doy_of(ch$date))) else NA
f17 <- if (!is.null(cf) && nrow(cf)) dfd(SYNTH_YEAR, median_doy(doy_of(cf$date))) else NA
cat("synth ", SYNTH_YEAR, ": planting=", p17, " harvest=", h17, " fert=", f17, "\n", sep="")

events <- list(); add <- function(e) events[[length(events)+1]] <<- e
keep <- function(d) as.Date(d) >= RUN_START & as.Date(d) <= RUN_END

for (i in seq_len(nrow(plant))) { r <- plant[i,]; if (!keep(r$date)) next
  add(list(event_type="planting", date=as.character(r$date), source="monitoring_product:planting/v1.0",
           crop_code=r$code, crop_display=r$code, leaf_c_kg_m2=round(as.numeric(r$C_LEAF),8))) }
if (!is.na(p17) && keep(p17)) add(list(event_type="planting", date=p17, source="synthesized:median_doy",
           crop_code=CROP, crop_display=CROP, leaf_c_kg_m2=round(mean(as.numeric(cp$C_LEAF)),8),
           prior_filled=paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

for (i in seq_len(nrow(harv))) { r <- harv[i,]; if (!keep(r$date)) next
  add(list(event_type="harvest", date=as.character(r$date), source="monitoring_product:harvest/v1.0",
           crop_display=r$CLASS_SUBCLASS, frac_above_removed_0to1=round(as.numeric(r$frac_above_removed_0to1),4))) }
if (!is.na(h17) && keep(h17)) add(list(event_type="harvest", date=h17, source="synthesized:median_doy",
           crop_display=CROP, frac_above_removed_0to1=round(mean(as.numeric(ch$frac_above_removed_0to1)),4),
           prior_filled=paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

if (!is.null(irr)) for (i in seq_len(nrow(irr))) { r <- irr[i,]; if (!keep(r$date)) next
  add(list(event_type="irrigation", date=as.character(r$date), source="monitoring_product:irrigation/v1.1",
           amount_mm=round(as.numeric(r$amount_mm),4), method=r$method)) }

if (!is.null(fert) && nrow(fert)) for (i in seq_len(nrow(fert))) { r <- fert[i,]; if (!keep(r$date)) next
  add(list(event_type="fertilization", date=as.character(r$date), source="akash:fertilization.parquet",
           nh4_n_kg_m2=round(r$nh4_n_kg_m2,8), no3_n_kg_m2=round(r$no3_n_kg_m2,8), org_n_kg_m2=round(r$org_n_kg_m2,8))) }
if (!is.na(f17) && keep(f17)) add(list(event_type="fertilization", date=f17, source="synthesized:median_doy",
           nh4_n_kg_m2=round(mean(cf$nh4_n_kg_m2),8), no3_n_kg_m2=round(mean(cf$no3_n_kg_m2),8),
           org_n_kg_m2=round(mean(cf$org_n_kg_m2),8),
           prior_filled=paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

events <- events[order(vapply(events, \(e) e$date, character(1)))]
doc <- list(pecan_events_version="0.1.1", site_id=LABEL,
            provenance=list(parcel_id=PARCEL, crop=CROP, member="ens_001",
              generator="adey2:step3_delta_assemble",
              note=paste0("single-member; ", SYNTH_YEAR, " synthesized; events filtered to run window")),
            events=events)
write_json(doc, OUT, auto_unbox=TRUE, pretty=TRUE, digits=8)
cat("wrote", length(events), "events ->", OUT, "\n")
print(table(vapply(events, \(e) e$event_type, character(1))))
cat("date range:", min(vapply(events,\(e) e$date,character(1))), "to",
    max(vapply(events,\(e) e$date,character(1))), "\n")
