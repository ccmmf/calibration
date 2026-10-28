#!/usr/bin/env Rscript
# Medians of the monitoring tillage product for parcels near Russell Ranch, which
# russell_split_phases.R uses for the timing and intensity of the tillage operations
# Tautges et al. (2019) describe but do not quantify (tools/event_prep/README.md, "Filling
# missing events", step 2: before 2016, comparable crops and operations in the same area).
#
# usage: russell_monitoring_tillage.R <monitoring_dir> <out_csv>
#   monitoring_dir holds the v5.0 products as on S3 and the v4.1 crop table:
#     crops/crops_all_years.parq          s3://carb/management/crops/v4.1/crops_all_years.parq
#     tillage/<year>.parquet               s3://carb/management/tillage/v5.0/assigned_year=<year>_tillage.parquet
#     harvest/<year>.parquet               s3://carb/management/harvest/v5.0/assigned_year=<year>_harvest.parquet
#     planting/<year>.parquet              s3://carb/management/planting/v5.0/assigned_year=<year>_planting.parquet
#   for 2016 to 2023 (aws --profile ccmmf-garage --endpoint-url https://s3.garage.ccmmf.ncsa.cloud s3 cp ...).

suppressMessages({library(arrow); library(sf)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: russell_monitoring_tillage.R <monitoring_dir> <out_csv>")
mon <- args[1]; out_csv <- args[2]

# Russell Ranch, 38°32'24"N 121°52'12"W (Tautges et al. 2019), in the crop table's EPSG:3310
RADIUS_KM <- 25
site <- st_coordinates(st_transform(st_sfc(st_point(c(-(121 + 52 / 60 + 12 / 3600), 38 + 32 / 60 + 24 / 3600)),
                                           crs = 4326), 3310))
# The monitoring crop codes for the Russell crops: F16 corn (grouped corn, sorghum, sudan),
# T32 tomato (the product has no T15) and G2 wheat, as in the harvest lookup
CODES <- c(corn = "F16", tomato = "T32", wheat = "G2")
WINDOW_DAYS <- 120  # a tillage event belongs to the harvest or planting it falls this close to

crops <- as.data.frame(read_parquet(file.path(mon, "crops", "crops_all_years.parq"),
                                    col_select = c("parcel_id", "year", "centx", "centy")))
crops <- crops[crops$year >= 2016, ]
near <- unique(crops$parcel_id[sqrt((crops$centx - site[1])^2 + (crops$centy - site[2])^2) <= RADIUS_KM * 1000])

rd <- function(product, cols) {
  x <- do.call(rbind, lapply(sort(list.files(file.path(mon, product), "\\.parquet$", full.names = TRUE)),
                             function(f) as.data.frame(read_parquet(f, col_select = all_of(cols)))))
  x <- x[x$parcel_id %in% near, ]
  x$date <- as.Date(x$date)
  x
}
till <- rd("tillage", c("parcel_id", "date", "tillage_eff_0to1"))
harv <- rd("harvest", c("parcel_id", "date", "crop_code"))
plnt <- rd("planting", c("parcel_id", "date", "crop_code"))
till <- till[order(till$parcel_id, till$date), ]
by_parcel <- split(till, till$parcel_id)

# For each harvest, the first tillage event after it; for each planting, the last one before it
nearest <- function(ev, after) do.call(rbind, lapply(seq_len(nrow(ev)), function(i) {
  t <- by_parcel[[as.character(ev$parcel_id[i])]]
  if (is.null(t)) return(NULL)
  dd <- as.numeric(t$date - ev$date[i])
  k <- if (after) which(dd > 0 & dd <= WINDOW_DAYS) else which(dd < 0 & dd >= -WINDOW_DAYS)
  if (!length(k)) return(NULL)
  k <- if (after) k[1] else k[length(k)]
  data.frame(days = abs(dd[k]), eff = t$tillage_eff_0to1[k])
}))

rows <- list()
for (crop in names(CODES)) {
  for (op in c("post_harvest", "pre_plant")) {
    ev <- if (op == "post_harvest") harv[harv$crop_code == CODES[[crop]], ] else plnt[plnt$crop_code == CODES[[crop]], ]
    m <- nearest(ev, op == "post_harvest")
    rows[[length(rows) + 1L]] <- data.frame(operation = op, crop = crop, crop_code = CODES[[crop]],
                                            n_events = nrow(m), median_days = round(median(m$days)),
                                            median_tillage_eff = round(median(m$eff), 4))
  }
}
rows[[length(rows) + 1L]] <- data.frame(operation = "any", crop = "all", crop_code = "all",
                                        n_events = nrow(till), median_days = NA,
                                        median_tillage_eff = round(median(till$tillage_eff_0to1), 4))
out <- do.call(rbind, rows)
out$radius_km <- RADIUS_KM
out$years <- sprintf("%s-%s", format(min(till$date), "%Y"), format(max(till$date), "%Y"))
out$n_parcels <- length(near)
write.csv(out, out_csv, row.names = FALSE)
print(out, row.names = FALSE)
