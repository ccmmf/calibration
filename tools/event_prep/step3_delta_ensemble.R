#!/usr/bin/env Rscript
# Assemble a member ensemble of events.json for one Delta site; management uncertainty
# comes from the fertilization and irrigation members, other event types are deterministic.

suppressPackageStartupMessages({ library(arrow); library(dplyr); library(jsonlite) })
options(arrow.unsafe_metadata = TRUE)

a <- commandArgs(trailingOnly = TRUE)
LABEL <- a[1]; PARCEL <- as.integer(a[2]); CROP <- a[3]
SYNTH_YEAR <- as.integer(a[4]); RUN_START <- as.Date(a[5]); RUN_END <- as.Date(a[6])
N_MEM <- if (length(a) >= 7) as.integer(a[7]) else 20L

TMP   <- "/projectnb2/dietzelab/ccmmf/usr/adey2/tmp"
EVDIR <- file.path(TMP, paste0(LABEL, "_events"))       # per-site CSVs from step2
OUT   <- file.path(TMP, paste0(LABEL, "_events_ens"))   # ensemble output
FERT  <- "/projectnb2/dietzelab/ccmmf/usr/akash/event_files/fertilization.parquet"
dir.create(OUT, showWarnings = FALSE)

## ---------------------------------------------------------------- helpers
median_doy <- function(doy) {
  doy <- na.omit(doy); doy[doy == 366] <- 365
  stopifnot(all(doy >= 1 & doy <= 365)); doy <- sort(doy)
  if (length(doy) < 2) return(doy)
  if (diff(range(doy)) <= 182) return(median(doy))
  gaps <- c(diff(doy), doy[1] + 365 - tail(doy, 1)); cut <- which.max(gaps)
  doy <- c(doy[(cut + 1):length(doy)], doy[1:cut] + 365); ((median(doy) - 1) %% 365) + 1
}
doy_of <- function(d) as.integer(format(as.Date(d), "%j"))
dfd    <- function(y, doy) format(as.Date(paste0(y, "-01-01")) + (round(doy) - 1), "%Y-%m-%d")
rd     <- function(f) if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE) else NULL
keep   <- function(d) as.Date(d) >= RUN_START & as.Date(d) <= RUN_END

## ---------------------------------------------------- read deterministic parts
plant <- rd(file.path(EVDIR, "own_planting.csv"))
harv  <- rd(file.path(EVDIR, "own_harvest.csv"))
irr_all <- rd(file.path(EVDIR, "own_irrigation.csv"))
stopifnot(!is.null(plant), !is.null(harv))

# all fert members for this parcel, read once
fert_all <- tryCatch(
  open_dataset(FERT) |> filter(site_id == PARCEL) |> collect() |> as.data.frame(),
  error = function(e) NULL)
if (!is.null(fert_all) && nrow(fert_all)) {
  fert_all$date <- as.Date(fert_all$date)
  for (n in c("nh4_n_kg_m2","no3_n_kg_m2","org_c_kg_m2","org_n_kg_m2"))
    fert_all[[n]] <- as.numeric(fert_all[[n]])
}

# crop-matched deterministic cycles (for synthesizing the excluded year)
cp <- plant[plant$code == CROP & plant$season == 2, ]
ch <- harv[harv$CLASS_SUBCLASS == CROP & harv$season == 2, ]
p_syn <- if (nrow(cp)) dfd(SYNTH_YEAR, median_doy(doy_of(cp$date))) else NA
h_syn <- if (nrow(ch)) dfd(SYNTH_YEAR, median_doy(doy_of(ch$date))) else NA

cat("site ", LABEL, " parcel ", PARCEL, " crop ", CROP, " | members ", N_MEM, "\n", sep = "")
cat("deterministic: planting ", nrow(plant), " harvest ", nrow(harv), "\n", sep = "")

## ------------------------------------------------------------- build members
summary_rows <- list()
for (m in seq_len(N_MEM)) {
  fm <- sprintf("ens_%03d", m)         # fert member
  im <- sprintf("irr_ens_%03d", m)     # irrigation member

  fert <- if (!is.null(fert_all) && nrow(fert_all)) fert_all[fert_all$event_member_id == fm, ] else NULL
  irr  <- if (!is.null(irr_all) && "ens_id" %in% names(irr_all)) irr_all[irr_all$ens_id == im, ] else NULL

  cf <- if (!is.null(fert) && nrow(fert)) fert[grepl(CROP, fert$crop_code), ] else NULL
  f_syn <- if (!is.null(cf) && nrow(cf)) dfd(SYNTH_YEAR, median_doy(doy_of(cf$date))) else NA

  events <- list(); add <- function(e) events[[length(events) + 1]] <<- e

  for (i in seq_len(nrow(plant))) { r <- plant[i, ]; if (!keep(r$date)) next
    add(list(event_type = "planting", date = as.character(r$date),
             source = "monitoring_product:planting/v1.0",
             crop_code = r$code, crop_display = r$code,
             leaf_c_kg_m2 = round(as.numeric(r$C_LEAF), 8))) }
  if (!is.na(p_syn) && keep(p_syn))
    add(list(event_type = "planting", date = p_syn, source = "synthesized:median_doy",
             crop_code = CROP, crop_display = CROP,
             leaf_c_kg_m2 = round(mean(as.numeric(cp$C_LEAF)), 8),
             prior_filled = paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

  for (i in seq_len(nrow(harv))) { r <- harv[i, ]; if (!keep(r$date)) next
    add(list(event_type = "harvest", date = as.character(r$date),
             source = "monitoring_product:harvest/v1.0",
             crop_display = r$CLASS_SUBCLASS,
             frac_above_removed_0to1 = round(as.numeric(r$frac_above_removed_0to1), 4))) }
  if (!is.na(h_syn) && keep(h_syn))
    add(list(event_type = "harvest", date = h_syn, source = "synthesized:median_doy",
             crop_display = CROP,
             frac_above_removed_0to1 = round(mean(as.numeric(ch$frac_above_removed_0to1)), 4),
             prior_filled = paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

  if (!is.null(irr)) for (i in seq_len(nrow(irr))) { r <- irr[i, ]; if (!keep(r$date)) next
    add(list(event_type = "irrigation", date = as.character(r$date),
             source = paste0("monitoring_product:irrigation/v1.1:", im),
             amount_mm = round(as.numeric(r$amount_mm), 4), method = r$method)) }

  if (!is.null(fert) && nrow(fert)) for (i in seq_len(nrow(fert))) { r <- fert[i, ]; if (!keep(r$date)) next
    add(list(event_type = "fertilization", date = as.character(r$date),
             source = paste0("akash:fertilization.parquet:", fm),
             nh4_n_kg_m2 = round(r$nh4_n_kg_m2, 8), no3_n_kg_m2 = round(r$no3_n_kg_m2, 8),
             org_n_kg_m2 = round(r$org_n_kg_m2, 8))) }
  if (!is.na(f_syn) && keep(f_syn))
    add(list(event_type = "fertilization", date = f_syn, source = "synthesized:median_doy",
             nh4_n_kg_m2 = round(mean(cf$nh4_n_kg_m2), 8),
             no3_n_kg_m2 = round(mean(cf$no3_n_kg_m2), 8),
             org_n_kg_m2 = round(mean(cf$org_n_kg_m2), 8),
             prior_filled = paste0("date<-synthesized:", SYNTH_YEAR, "_excluded_year")))

  events <- events[order(vapply(events, \(e) e$date, character(1)))]
  doc <- list(pecan_events_version = "0.1.1", site_id = LABEL,
              provenance = list(parcel_id = PARCEL, crop = CROP,
                                member = m, fert_member = fm, irrigation_member = im,
                                generator = "adey2:step3_delta_ensemble",
                                note = "management-uncertainty ensemble; planting/harvest deterministic, fert+irrigation vary by member"),
              events = events)
  jf <- file.path(OUT, sprintf("events_ens_%03d.json", m))
  write_json(doc, jf, auto_unbox = TRUE, pretty = TRUE, digits = 8)

  tt <- table(vapply(events, \(e) e$event_type, character(1)))
  summary_rows[[m]] <- data.frame(member = m, n = length(events),
    planting = ifelse("planting" %in% names(tt), tt[["planting"]], 0),
    harvest  = ifelse("harvest"  %in% names(tt), tt[["harvest"]],  0),
    irrig    = ifelse("irrigation" %in% names(tt), tt[["irrigation"]], 0),
    fert     = ifelse("fertilization" %in% names(tt), tt[["fertilization"]], 0))
}

s <- do.call(rbind, summary_rows)
cat("\n=== ensemble summary ===\n"); print(s, row.names = FALSE)
cat("\nvaries across members? irrigation:", length(unique(s$irrig)) > 1,
    " fert:", length(unique(s$fert)) > 1, "\n")
cat("wrote", N_MEM, "member json ->", OUT, "\n")
