#!/usr/bin/env Rscript
# Subset the statewide monitoring product to one parcel and write the per-parcel
# CSVs the step3_* scripts read. This is the "step2" those scripts refer to; it
# previously lived only on SCC, so the chain could not be re-run from a clean
# checkout.
#
# Usage: extract_parcel_csvs.R <label> <parcel_id>
#        extract_parcel_csvs.R us_bi2 565118

suppressPackageStartupMessages({ library(arrow); library(dplyr) })
options(arrow.unsafe_metadata = TRUE)

a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2) stop("usage: extract_parcel_csvs.R <label> <parcel_id>")
LABEL <- a[1]; PARCEL <- as.integer(a[2])

CCMMF_BASE         <- Sys.getenv("CCMMF_BASE", path.expand("~"))
CCMMF_ROOT         <- Sys.getenv("CCMMF_ROOT", file.path(CCMMF_BASE, "ccmmf"))
PRODUCTS_ROOT      <- Sys.getenv("PRODUCTS_ROOT", file.path(CCMMF_ROOT, "products"))
PRODUCTS_INVENTORY <- Sys.getenv("PRODUCTS_INVENTORY", file.path(PRODUCTS_ROOT, "inventory"))
CCMMF_WORK         <- Sys.getenv("CCMMF_WORK", file.path(CCMMF_ROOT, "work"))

PLANTING_VERSION     <- Sys.getenv("PLANTING_VERSION", "v1.0")
HARVEST_VERSION      <- Sys.getenv("HARVEST_VERSION", "v1.0")
IRRIGATION_VERSION   <- Sys.getenv("IRRIGATION_VERSION", "v1.1")

MGMT  <- file.path(PRODUCTS_INVENTORY, "management")
EVDIR <- file.path(CCMMF_WORK, paste0(LABEL, "_events"))
dir.create(EVDIR, recursive = TRUE, showWarnings = FALSE)

# Column types are not stable across the per-year files: site_id is int32 in some
# and string in others, and date is character in planting_statewide_2016 but Date
# from 2018 on. rbind over that mix silently yields NA dates, so normalise both to
# character in each file before stacking.
read_years <- function(dir) {
  f <- list.files(dir, pattern = "\\.parquet$", full.names = TRUE)
  if (!length(f)) stop("no parquet files under ", dir, " -- run pull_inputs.sh first")
  do.call(rbind, lapply(f, function(x) {
    d <- open_dataset(x) |> collect() |> as.data.frame()
    d$site_id <- as.character(d$site_id)
    d$date    <- as.character(as.Date(d$date))
    d[d$site_id == as.character(PARCEL), , drop = FALSE]
  }))
}

plant <- read_years(file.path(MGMT, "planting", PLANTING_VERSION))
harv  <- read_years(file.path(MGMT, "harvest",  HARVEST_VERSION))

# Irrigation shards are keyed on parcel_id and their named ranges overlap, so a
# parcel is not guaranteed to be in the shard whose name brackets it. Read every
# shard present and filter.
idir <- file.path(MGMT, "irrigation", IRRIGATION_VERSION)
ifiles <- list.files(idir, pattern = "\\.parquet$", full.names = TRUE)
if (!length(ifiles)) stop("no irrigation shards under ", idir, " -- run pull_inputs.sh first")
irr <- do.call(rbind, lapply(ifiles, function(x)
  open_dataset(x) |> filter(parcel_id == PARCEL) |> collect() |> as.data.frame()))

# step3 reads a `date` column of plain YYYY-MM-DD and an `ens_id` on irrigation.
for (nm in c("plant", "harv", "irr")) {
  d <- get(nm)
  if (!is.null(d) && nrow(d)) { d$date <- as.character(as.Date(d$date)); assign(nm, d[order(d$date), ]) }
}

write.csv(plant, file.path(EVDIR, "own_planting.csv"),   row.names = FALSE)
write.csv(harv,  file.path(EVDIR, "own_harvest.csv"),    row.names = FALSE)
write.csv(irr,   file.path(EVDIR, "own_irrigation.csv"), row.names = FALSE)

cat("parcel ", PARCEL, " -> ", EVDIR, "\n", sep = "")
cat("  own_planting.csv   ", nrow(plant), " rows\n", sep = "")
cat("  own_harvest.csv    ", nrow(harv),  " rows\n", sep = "")
cat("  own_irrigation.csv ", nrow(irr),   " rows",
    if (nrow(irr)) paste0(" (", length(unique(irr$ens_id)), " ensemble members)") else "", "\n", sep = "")
