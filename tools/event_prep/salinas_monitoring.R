#!/usr/bin/env Rscript
# Medians of the monitoring product for parcels near the Salinas Organic Cropping Systems trial
# (SOCS), which salinas_build_events.R uses for what the papers do not give: the day an operation
# dated only by a window most often falls on, the planting leaf C, the vegetable irrigation and the
# tillage intensity (tools/event_prep/README.md, "Filling missing events", step 2: before 2016,
# comparable crops and operations in the same area).
#
# usage: salinas_monitoring.R <monitoring_dir> <out_csv>
#   monitoring_dir holds the products as on S3, for 2016 to 2023
#   (aws --profile ccmmf-garage --endpoint-url https://s3.garage.ccmmf.ncsa.cloud s3 cp ...):
#     crops/crops_all_years.parq     s3://carb/management/crops/v4.1/crops_all_years.parq
#     planting/<year>.parquet        s3://carb/management/planting/v5.0/assigned_year=<year>_planting.parquet
#     harvest/<year>.parquet         s3://carb/management/harvest/v5.0/assigned_year=<year>_harvest.parquet
#     tillage/<year>.parquet         s3://carb/management/tillage/v5.0/assigned_year=<year>_tillage.parquet
#     irrigation/<shard>.parquet     s3://carb/management/irrigation/v5.0/<shard>.parquet
#     fertilization/<shard>.parquet  s3://carb/management/fertilization/v2.0/<shard>.parquet
#
# The product has no lettuce (T8), spinach (T14) or broccoli (T22) class near SOCS, or anywhere in
# the state: lettuce and spinach are in T30, "lettuce or leafy greens grouped for remote sensing
# only", and broccoli in T4, cole crops (the LandIQ legend). The SOCS crops are told apart by the
# months the calendar plants them in, so each is a slot: a class and its planting months. The
# product has no cover crop class either; G6, miscellaneous grain and hay, sown in October or
# November stands in for the winter cover crops' planting leaf C.
#
# A season pairs a planting with the next same-class harvest on the parcel when that harvest's
# latest planting is the same one (no planting in between), within MAX_SEASON_DAYS. The 2017
# planting and harvest files are left out: the crop table has no 2017, and near SOCS they hold
# exactly one planting per parcel, so they look synthesized rather than observed.

suppressMessages({library(arrow); library(data.table); library(sf); library(DBI); library(duckdb)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: salinas_monitoring.R <monitoring_dir> <out_csv>")
mon <- args[1]; out_csv <- args[2]
# The product versions monitoring_dir holds (above), written with the medians
PRODUCTS <- "planting v5.0, harvest v5.0, tillage v5.0, irrigation v5.0, fertilization v2.0, crops v4.1"

# SOCS, 36°37'N 121°32'W (White et al. 2020b), in the crop table's EPSG:3310
RADIUS_KM <- 25
site <- st_coordinates(st_transform(st_sfc(st_point(c(-(121 + 32 / 60), 36 + 37 / 60)), crs = 4326), 3310))
SLOTS <- data.table(
  slot = c("lettuce", "spinach", "broccoli", "broccoli_irrigation", "cover_crop"),
  crop_code = c("T30", "T30", "T4", "T30", "G6"),
  months = list(5L, 7L, 7:8, 7:8, 10:11),
  what = c("romaine lettuce, transplanted in May", "baby leaf spinach, seeded in July",
           "broccoli, transplanted in July or August",
           "broccoli irrigation stand-in: T30 sown or transplanted in July or August",
           "winter cover crops, sown in October or November"))
MAX_SEASON_DAYS <- 240
TILLAGE_WINDOW_DAYS <- 120  # a tillage event belongs to the planting or harvest it falls this close to
SKIP_FILES <- "2017"

crops <- as.data.table(read_parquet(file.path(mon, "crops", "crops_all_years.parq"),
                                    col_select = c("parcel_id", "year", "centx", "centy")))
crops <- crops[year >= 2016]
near <- unique(crops[sqrt((centx - site[1])^2 + (centy - site[2])^2) <= RADIUS_KM * 1000, as.numeric(parcel_id)])
rm(crops); invisible(gc())

# Per-year products, near parcels only; parcel_id and date types differ between files
rd <- function(product, cols) {
  files <- sort(list.files(file.path(mon, product), "\\.parquet$", full.names = TRUE))
  files <- files[!sub("\\.parquet$", "", basename(files)) %in% if (product == "tillage") character() else SKIP_FILES]
  x <- rbindlist(lapply(files, function(f) {
    y <- as.data.table(read_parquet(f, col_select = all_of(cols)))
    y[, parcel_id := as.numeric(as.character(parcel_id))]
    y <- y[parcel_id %in% near]
    y[, date := as.Date(as.character(date))]
  }))
  # the per-year files overlap in time, so the same event can sit in two of them
  unique(x, by = intersect(c("parcel_id", "date", "crop_code"), names(x)))
}
plnt <- rd("planting", c("parcel_id", "date", "crop_code", "leaf_c_kg_m2"))
harv <- rd("harvest", c("parcel_id", "date", "crop_code"))
till <- rd("tillage", c("parcel_id", "date", "tillage_eff_0to1"))

# Seasons: a planting and the next same-class harvest whose latest planting it is
p <- plnt[, .(parcel_id, crop_code, pdate = date, leaf_c_kg_m2, k = as.numeric(date))]
h <- harv[, .(parcel_id, crop_code, hdate = date, k = as.numeric(date))]
nxt <- h[p[, .(parcel_id, crop_code, pdate, k = k + 1)], on = .(parcel_id, crop_code, k), roll = -Inf][!is.na(hdate)]
prv <- p[h[, .(parcel_id, crop_code, hdate, k = k - 1)], on = .(parcel_id, crop_code, k), roll = Inf][!is.na(pdate)]
seasons <- merge(nxt[, .(parcel_id, crop_code, pdate, hdate)], prv[, .(parcel_id, crop_code, pdate, hdate)],
                 by = c("parcel_id", "crop_code", "pdate", "hdate"))
seasons <- seasons[as.numeric(hdate - pdate) <= MAX_SEASON_DAYS]
seasons[, `:=`(sid = .I, days = as.numeric(hdate - pdate), pmonth = month(pdate))]

# Irrigation: a season's total is the median over the ensemble members of each member's sum over
# the season (planting to harvest), a member with no event counting 0, as russell_monitoring_irrigation.R
irr_seasons <- rbindlist(lapply(seq_len(nrow(SLOTS)), function(i)
  seasons[crop_code == SLOTS$crop_code[i] & pmonth %in% SLOTS$months[[i]]]))
irr_seasons <- unique(irr_seasons, by = "sid")
con <- dbConnect(duckdb())
invisible(dbExecute(con, "SET memory_limit='2GB'"))
duckdb_register(con, "seasons", as.data.frame(irr_seasons[, .(sid, parcel_id, start = pdate, end = hdate)]))
glob <- file.path(mon, "irrigation", "*.parquet")
members <- dbGetQuery(con, sprintf("SELECT DISTINCT ens_id FROM read_parquet('%s') ORDER BY 1", glob))$ens_id
sums <- as.data.table(dbGetQuery(con, sprintf("
  SELECT s.sid, i.ens_id, sum(i.amount_mm) AS tot, count(*) AS n
  FROM seasons s JOIN read_parquet('%s') i
    ON i.parcel_id = s.parcel_id AND i.date >= s.start AND i.date <= s.end
  GROUP BY s.sid, i.ens_id", glob)))
dbDisconnect(con, shutdown = TRUE)
M <- length(members)
tot <- sums[, .(total_mm = median(c(tot, rep(0, M - .N))), events = median(c(n, rep(0, M - .N)))), by = sid]
seasons <- merge(seasons, tot, by = "sid", all.x = TRUE)
seasons[is.na(total_mm), `:=`(total_mm = 0, events = 0)]

# Fertilization: the product's events on the slot's seasons (one member; the dates are the same in
# every member), from 30 days before planting to harvest, and their days from planting
fert_files <- sort(list.files(file.path(mon, "fertilization"), "\\.parquet$", full.names = TRUE))
fert <- as.data.table(open_dataset(fert_files) |> dplyr::filter(ens_id == "ens_001") |>
                        dplyr::select(parcel_id, date, crop_code) |> dplyr::collect())
fert[, parcel_id := as.numeric(parcel_id)]
fert <- unique(fert[parcel_id %in% near])

q <- function(x, p) unname(quantile(x, p, na.rm = TRUE))
doy <- function(d) as.integer(format(d, "%j"))
row <- function(slot, quantity, x, unit, note = "") {
  x <- x[!is.na(x)]
  data.table(slot = slot, quantity = quantity, n = length(x), value = if (length(x)) median(x) else NA_real_,
             p25 = if (length(x)) q(x, 0.25) else NA_real_, p75 = if (length(x)) q(x, 0.75) else NA_real_,
             unit = unit, note = note)
}
# The last tillage event before each planting, or the first after each harvest, within the window
nearest_till <- function(ev, date_col, after) {
  e <- ev[, .(parcel_id, d0 = get(date_col))]
  t <- till[, .(parcel_id, tdate = date, eff = tillage_eff_0to1, k = as.numeric(date))]
  m <- t[e[, .(parcel_id, d0, k = as.numeric(d0) + if (after) 1 else -1)], on = .(parcel_id, k),
         roll = if (after) -Inf else Inf]
  m <- m[!is.na(tdate)]
  m[, days := abs(as.numeric(tdate - d0))]
  m[days <= TILLAGE_WINDOW_DAYS]
}

# Tillage days of year can wrap the new year, so the builder times tillage by the days columns
WRAPS <- "days of year can wrap the new year, so for reference only"
rows <- list()
for (i in seq_len(nrow(SLOTS))) {
  s <- SLOTS[i]; sl <- s$slot
  pl <- plnt[crop_code == s$crop_code & month(date) %in% s$months[[1]]]
  se <- seasons[crop_code == s$crop_code & pmonth %in% s$months[[1]]]
  rows[[length(rows) + 1L]] <- row(sl, "planting_doy", doy(pl$date), "day of year")
  rows[[length(rows) + 1L]] <- row(sl, "leaf_c_kg_m2", pl$leaf_c_kg_m2, "kg C m-2")
  if (sl == "cover_crop") next
  rows[[length(rows) + 1L]] <- row(sl, "harvest_doy", doy(se$hdate), "day of year", "harvest of a paired season")
  rows[[length(rows) + 1L]] <- row(sl, "season_days", se$days, "days", "planting to harvest")
  w <- se[total_mm > 0]
  rows[[length(rows) + 1L]] <- row(sl, "irrigated_share", as.numeric(se$total_mm > 0), "fraction",
                                   "seasons with any irrigation; value is the share, not a median")
  rows[[length(rows)]][, `:=`(value = mean(se$total_mm > 0), p25 = NA_real_, p75 = NA_real_)]
  rows[[length(rows) + 1L]] <- row(sl, "irrigated_season_mm", w$total_mm, "mm", "irrigated seasons only")
  rows[[length(rows) + 1L]] <- row(sl, "irrigated_mm_per_day", w$total_mm / w$days, "mm d-1",
                                   "irrigated seasons only: season total over planting to harvest days")
  rows[[length(rows) + 1L]] <- row(sl, "irrigated_events", w$events, "events", "irrigated seasons only")
  if (sl == "broccoli_irrigation") next
  pre <- nearest_till(pl, "date", after = FALSE)
  post <- nearest_till(se, "hdate", after = TRUE)
  rows[[length(rows) + 1L]] <- row(sl, "preplant_tillage_doy", doy(pre$tdate), "day of year",
                                   sprintf("last tillage event within %d days before a planting; %s", TILLAGE_WINDOW_DAYS, WRAPS))
  rows[[length(rows) + 1L]] <- row(sl, "preplant_tillage_days", pre$days, "days", "before planting")
  rows[[length(rows) + 1L]] <- row(sl, "preplant_tillage_eff", pre$eff, "0 to 1")
  rows[[length(rows) + 1L]] <- row(sl, "postharvest_tillage_doy", doy(post$tdate), "day of year",
                                   sprintf("first tillage event within %d days after a harvest; %s", TILLAGE_WINDOW_DAYS, WRAPS))
  rows[[length(rows) + 1L]] <- row(sl, "postharvest_tillage_days", post$days, "days", "after harvest")
  rows[[length(rows) + 1L]] <- row(sl, "postharvest_tillage_eff", post$eff, "0 to 1")
  fs <- fert[crop_code == s$crop_code]
  fm <- fs[se[, .(parcel_id, pdate, hdate, sid)], on = .(parcel_id, date >= pdate, date <= hdate), nomatch = NULL, allow.cartesian = TRUE,
           .(sid, x.date, i.pdate)]
  # the window above is planting to harvest; widen it to 30 days before planting
  pre_f <- fs[se[, .(parcel_id, lo = pdate - 30, pdate, sid)], on = .(parcel_id, date >= lo, date < pdate), nomatch = NULL, allow.cartesian = TRUE,
              .(sid, x.date, i.pdate)]
  fm <- rbind(fm, pre_f)
  setnames(fm, c("sid", "fdate", "pdate"))
  rows[[length(rows) + 1L]] <- row(sl, "fertilization_days_from_planting", as.numeric(fm$fdate - fm$pdate), "days",
                                   "fertilization events from 30 days before planting to harvest")
  per <- fm[, .N, by = sid]
  rows[[length(rows) + 1L]] <- row(sl, "fertilization_events_per_season", c(per$N, rep(0, nrow(se) - nrow(per))), "events")
}
rows[[length(rows) + 1L]] <- row("all", "tillage_eff", till$tillage_eff_0to1, "0 to 1", "every tillage event near SOCS")

out <- rbindlist(rows)
out <- merge(out, SLOTS[, .(slot, crop_code, planting_months = vapply(months, paste, "", collapse = ";"), what)],
             by = "slot", all.x = TRUE, sort = FALSE)
out[slot == "all", `:=`(crop_code = "all", planting_months = "", what = "all tillage events")]
out[, `:=`(value = signif(value, 6), p25 = signif(p25, 6), p75 = signif(p75, 6))]
out[, `:=`(radius_km = RADIUS_KM, n_parcels = length(near),
           years = sprintf("%s-%s", format(min(plnt$date), "%Y"), format(max(harv$date), "%Y")),
           products = PRODUCTS)]
setcolorder(out, c("slot", "crop_code", "planting_months", "what", "quantity", "n", "value", "p25", "p75", "unit", "note"))
fwrite(out, out_csv)
options(width = 250)
print(out[, .(slot, crop_code, quantity, n, value, p25, p75)], nrows = 200)
