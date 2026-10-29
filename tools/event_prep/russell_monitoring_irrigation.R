#!/usr/bin/env Rscript
# Season irrigation totals and timing of the monitoring irrigation product for corn and tomato
# parcels near Russell Ranch. The totals are the check David asked for on calibration#10 before
# reading Tautges et al. (2019)'s "33.6 mm per year" for furrow irrigated maize and tomato as
# inches; the product estimates irrigation from evapotranspiration and does not see water that
# drains, so they are a lower bound. The timing (days from planting to the first event and from
# the last event to harvest) places russell_split_phases.R's furrow schedule.
#
# usage: russell_monitoring_irrigation.R <monitoring_dir> <out_csv>
#   monitoring_dir holds the v5.0 products as on S3 and the v4.1 crop table:
#     crops/crops_all_years.parq          s3://carb/management/crops/v4.1/crops_all_years.parq
#     irrigation/<shard>.parquet           s3://carb/management/irrigation/v5.0/<shard>.parquet
#     harvest/<year>.parquet               s3://carb/management/harvest/v5.0/assigned_year=<year>_harvest.parquet
#     planting/<year>.parquet              s3://carb/management/planting/v5.0/assigned_year=<year>_planting.parquet
#   for 2016 to 2023 (aws --profile ccmmf-garage --endpoint-url https://s3.garage.ccmmf.ncsa.cloud s3 cp ...).

suppressMessages({library(arrow); library(dplyr); library(sf)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: russell_monitoring_irrigation.R <monitoring_dir> <out_csv>")
mon <- args[1]; out_csv <- args[2]

# Russell Ranch, 38°32'24"N 121°52'12"W (Tautges et al. 2019), in the crop table's EPSG:3310
RADIUS_KM <- 25
site <- st_coordinates(st_transform(st_sfc(st_point(c(-(121 + 52 / 60 + 12 / 3600), 38 + 32 / 60 + 24 / 3600)),
                                           crs = 4326), 3310))
# The same crop codes as russell_monitoring_tillage.R
CODES <- c(corn = "F16", tomato = "T32")
MAX_SEASON_DAYS <- 240  # a harvest's season starts at the last same-crop planting this close before it

crops <- as.data.frame(read_parquet(file.path(mon, "crops", "crops_all_years.parq"),
                                    col_select = c("parcel_id", "year", "centx", "centy")))
crops <- crops[crops$year >= 2016, ]
near <- unique(crops$parcel_id[sqrt((crops$centx - site[1])^2 + (crops$centy - site[2])^2) <= RADIUS_KM * 1000])

rd <- function(product) {
  x <- do.call(rbind, lapply(sort(list.files(file.path(mon, product), "\\.parquet$", full.names = TRUE)),
                             function(f) as.data.frame(read_parquet(f, col_select = c("parcel_id", "date", "crop_code")))))
  x <- x[x$parcel_id %in% near & x$crop_code %in% CODES, ]
  x$date <- as.Date(x$date)
  x
}
harv <- rd("harvest")
plnt <- rd("planting")

# Each harvest with a same-crop planting before it is one season, planting to harvest
seasons <- do.call(rbind, lapply(seq_len(nrow(harv)), function(i) {
  p <- plnt$date[plnt$parcel_id == harv$parcel_id[i] & plnt$crop_code == harv$crop_code[i] &
                   plnt$date < harv$date[i] & plnt$date >= harv$date[i] - MAX_SEASON_DAYS]
  if (!length(p)) return(NULL)
  data.frame(parcel_id = harv$parcel_id[i], crop_code = harv$crop_code[i], start = max(p), end = harv$date[i])
}))
seasons <- unique(seasons)

ids <- as.numeric(unique(seasons$parcel_id))
irr <- open_dataset(sort(list.files(file.path(mon, "irrigation"), "\\.parquet$", full.names = TRUE))) |>
  filter(parcel_id %in% ids) |>
  select(parcel_id, ens_id, date, amount_mm) |>
  collect() |>
  as.data.frame()
irr$date <- as.Date(irr$date)
members <- sort(unique(irr$ens_id))

# A season's total is the median over the ensemble members of each member's sum over the season;
# a member with no event in the season counts as 0. Its timing is the median, over the members
# with at least one event, of the number of events, the days from planting to the first and from
# the last to harvest, and the median days between events.
stats <- do.call(rbind, lapply(seq_len(nrow(seasons)), function(i) {
  s <- irr[irr$parcel_id == seasons$parcel_id[i] & irr$date >= seasons$start[i] & irr$date <= seasons$end[i], ]
  by_member <- setNames(numeric(length(members)), members)
  if (!nrow(s)) return(data.frame(total_mm = 0, events = NA, first_days = NA, last_days = NA, interval_days = NA, max_mm = NA))
  sums <- tapply(s$amount_mm, s$ens_id, sum)
  by_member[names(sums)] <- sums
  tm <- do.call(rbind, lapply(split(s$date, s$ens_id), function(d) {
    d <- sort(d)
    data.frame(events = length(d), first_days = as.numeric(d[1] - seasons$start[i]),
               last_days = as.numeric(seasons$end[i] - d[length(d)]),
               interval_days = if (length(d) > 1) median(as.numeric(diff(d))) else NA)
  }))
  data.frame(total_mm = median(by_member), events = median(tm$events), first_days = median(tm$first_days),
             last_days = median(tm$last_days), interval_days = median(tm$interval_days, na.rm = TRUE),
             max_mm = max(s$amount_mm))
}))
seasons <- cbind(seasons, stats)

out <- do.call(rbind, lapply(names(CODES), function(crop) {
  x <- seasons[seasons$crop_code == CODES[[crop]], ]
  t <- x$total_mm; w <- x[t > 0, ]
  q <- quantile(t, c(0.25, 0.5, 0.75), names = FALSE)
  data.frame(crop = crop, crop_code = CODES[[crop]], n_seasons = length(t),
             n_seasons_irrigated = sum(t > 0), median_mm = round(q[2], 1),
             p25_mm = round(q[1], 1), p75_mm = round(q[3], 1),
             median_irrigated_mm = round(median(t[t > 0]), 1),
             median_events = median(w$events), median_first_days = round(median(w$first_days)),
             median_last_days = round(median(w$last_days)), median_interval_days = round(median(w$interval_days, na.rm = TRUE)),
             max_event_mm = round(max(w$max_mm), 1))
}))
out$radius_km <- RADIUS_KM
out$years <- sprintf("%s-%s", format(min(seasons$end), "%Y"), format(max(seasons$end), "%Y"))
out$n_members <- length(members)
out$n_parcels <- length(unique(seasons$parcel_id))
write.csv(out, out_csv, row.names = FALSE)
print(out, row.names = FALSE)
