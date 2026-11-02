#!/usr/bin/env Rscript
# Merge the 2010-2016 literature build and the 2017-2023 monitoring build into one
# series, backfilling tillage by carrying forward the Knox planting-offset rule.

suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L)
  stop("usage: us_twt_merge_2010_2023.R <literature.json> <monitoring.json> <out.json>")

a <- jsonlite::fromJSON(args[1], simplifyDataFrame = FALSE)  # 2010-2016, literature
b <- jsonlite::fromJSON(args[2], simplifyDataFrame = FALSE)  # 2017-2023, monitoring
stopifnot(identical(a$site_id, b$site_id))

etype <- function(ev, t) Filter(function(e) identical(e$event_type, t), ev)

# verify the tillage rule holds in the literature years before extending it
lit_till <- etype(a$events, "tillage")
lit_plant <- setNames(
  lapply(etype(a$events, "planting"), function(e) as.Date(e$date)),
  vapply(etype(a$events, "planting"), function(e) substr(e$date, 1, 4), character(1)))

offsets <- list()
for (e in lit_till) {
  yr <- substr(e$date, 1, 4)
  if (!is.null(lit_plant[[yr]]))
    offsets[[e$implement]] <- union(offsets[[e$implement]],
                                    as.integer(lit_plant[[yr]] - as.Date(e$date)))
}
for (imp in sort(names(offsets))) {
  cat(sprintf("  %s: planting minus %s d\n", imp, paste(sort(offsets[[imp]]), collapse = ", ")))
  if (length(offsets[[imp]]) != 1L)
    stop(sprintf("%s offset is not constant: %s", imp, paste(sort(offsets[[imp]]), collapse = ", ")))
}
DISK_D <- offsets[["disking"]]; ROLL_D <- offsets[["ring rolling"]]

# backfill tillage for the monitoring years from that rule
new_till <- list()
plantings <- etype(b$events, "planting")
plantings <- plantings[order(vapply(plantings, function(e) e$date, character(1)))]
for (e in plantings) {
  p <- as.Date(e$date)
  for (k in seq_len(2L)) {
    imp <- c("disking", "ring rolling")[k]
    off <- c(DISK_D, ROLL_D)[k]
    eff <- c(0.5, 0.2)[k]
    new_till[[length(new_till) + 1L]] <- list(
      event_type = "tillage",
      date = format(p - off, "%Y-%m-%d"),
      tillage_eff_0to1 = eff,
      implement = imp,
      provenance_class = "assumed",
      source = "calval:managements/delta-tillage-0001",
      provenance_note = sprintf(paste(
        "The monitoring product records no tillage for this parcel, which is a gap in the",
        "product rather than a change in practice. Knox documents %s every year at planting",
        "minus %d d with tillage_eff %s, exact in all seven of 2010-2016, so that pattern is",
        "carried forward onto the monitoring planting date of %s."), imp, off, eff, e$date))
  }
}
cat(sprintf("  backfilled tillage events for 2017-2023: %d\n", length(new_till)))

merged <- b
merged$pecan_events_version <- "0.1.1"
merged$provenance <- list(
  parcel_id = 590073L, crop = "R1",
  generator = "merge of the 2010-2016 literature build and the 2017-2023 monitoring build",
  note = paste(
    "One continuous 2010-2023 series. 2010-2016 management is derived from Knox et al. 2016",
    "with flood and drain dates from the AmeriFlux WTD series; 2017-2023 comes from the",
    "statewide monitoring product, which does not cover this parcel before 2017. Tillage for",
    "2017-2023 is carried forward from the Knox pattern because the product records none.",
    "Per-event source and provenance_class record which applies to each event."))

all_ev <- c(a$events, b$events, new_till)
ord <- order(vapply(all_ev, function(e) e$date, character(1)),
             vapply(all_ev, function(e) e$event_type, character(1)))
merged$events <- all_ev[ord]
write(jsonlite::toJSON(merged, auto_unbox = TRUE, pretty = 1, digits = NA), args[3])

ds <- vapply(merged$events, function(e) e$date, character(1))
cat(sprintf("  merged: %d events  %s -> %s\n", length(merged$events), ds[1], ds[length(ds)]))
print(table(vapply(merged$events, function(e) e$event_type, character(1))))
