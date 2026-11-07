# The Delta tower events.json files (runs/us_bi1, us_bi2, us_twt) and what SIPNET gets from them.
# The files and the tables their builders read live outside the package, so they are read from
# the source tree; R CMD check runs the tests elsewhere and skips this file.
root <- testthat::test_path("..", "..")
skip_if_not(file.exists(file.path(root, "runs", "us_twt", "events.json")), "runs/ is not in this tree")
source(file.path(root, "tools", "event_prep", "fill_order.R"), local = TRUE)

read_events <- function(site) jsonlite::fromJSON(file.path(root, "runs", site, "events.json"), simplifyDataFrame = FALSE)
of_type <- function(ev, t) Filter(function(e) identical(e$event_type, t), ev)
dates <- function(ev) vapply(ev, `[[`, "", "date")
field <- function(ev, f) vapply(ev, function(e) if (is.null(e[[f]])) NA_character_ else as.character(e[[f]]), "")

# events.in as PEcAn.SIPNET::write.events.SIPNET writes it, split into fields
sipnet_lines <- function(site) {
  skip_if_not_installed("PEcAn.SIPNET")
  old <- PEcAn.logger::logger.setLevel("OFF")
  withr::defer(PEcAn.logger::logger.setLevel(old), envir = parent.frame())
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  PEcAn.SIPNET::write.events.SIPNET(file.path(root, "runs", site, "events.json"), dir)
  f <- list.files(dir, pattern = "^events-.*\\.in$", full.names = TRUE)
  lapply(strsplit(trimws(readLines(f)), "[[:space:]]+"), function(x)
    list(year = as.integer(x[1]), doy = as.integer(x[2]), type = x[3], values = as.numeric(x[-(1:3)])))
}
lines_of <- function(ln, type) Filter(function(l) l$type == type, ln)

test_that("every Delta event says where it came from and stays in its run window", {
  for (site in c("us_bi1", "us_bi2", "us_twt")) {
    doc <- read_events(site)
    cfg <- readLines(file.path(root, "runs", site, paste0(site, "_user_config.yaml")))
    window <- sub('.*"(.*)".*', "\\1", grep("^(start|end)_date:", cfg, value = TRUE))
    expect_equal(doc$pecan_events_version, "0.1.1")
    expect_true(all(dates(doc$events) >= window[1] & dates(doc$events) <= window[2]), info = site)
    expect_true(all(field(doc$events, "provenance_class") %in% PROVENANCE_CLASSES), info = site)
    expect_true(all(nzchar(field(doc$events, "source"))), info = site)
    notes <- field(doc$events, "provenance_note")
    expect_false(anyNA(notes) || !all(nzchar(notes)), info = site)
    expect_no_error(check_harvest_fractions(doc$events))
  }
})

test_that("US-Bi1 is one alfalfa stand: a single planting and 39 cuttings that leave it alive", {
  ev <- read_events("us_bi1")$events
  expect_equal(dates(of_type(ev, "planting")), "2017-01-01")
  cuts <- read.csv(file.path(root, "tools", "event_prep", "us_bi1_cuttings.csv"), colClasses = "character")
  expect_equal(dates(of_type(ev, "harvest")), cuts$date)
  expect_equal(nrow(cuts), 39L)
  expect_equal(as.vector(table(substr(cuts$date, 1, 4))), c(6L, 6L, 6L, 6L, 6L, 3L, 6L))
  published <- Filter(function(e) e$provenance_class == "published", of_type(ev, "harvest"))
  expect_equal(dates(published), "2020-06-04")
  expect_length(c(of_type(ev, "tillage"), of_type(ev, "fertilization")), 0L)

  ln <- sipnet_lines("us_bi1")
  plant <- lines_of(ln, "plant")
  expect_length(plant, 1L)
  expect_equal(c(plant[[1]]$year, plant[[1]]$doy), c(2017L, 1L))
  harv <- lines_of(ln, "harv")
  expect_length(harv, 39L)
  for (h in harv) expect_equal(h$values, c(0.85, 0, 0, 0))
  # nothing goes to litter: a non-zero third or fourth field would end the stand
  expect_false(any(vapply(harv, function(h) any(h$values[3:4] != 0), TRUE)))
})

test_that("US-Bi2 has one corn cycle a year with 118 kg N/ha of UAN at planting", {
  ev <- read_events("us_bi2")$events
  years <- as.character(2016:2023)
  for (t in c("planting", "harvest", "fertilization"))
    expect_equal(substr(dates(of_type(ev, t)), 1, 4), years, info = t)
  expect_true(all(field(of_type(ev, "planting"), "crop_code") == "F16"))
  expect_equal(dates(of_type(ev, "fertilization")), dates(of_type(ev, "planting")))
  expect_true(all(dates(of_type(ev, "planting")) < dates(of_type(ev, "harvest"))))
  expect_length(c(of_type(ev, "irrigation"), of_type(ev, "tillage")), 0L)
  # the site record's days in 2019 and Anthony and Silver 2021 Fig. 2's in 2019 and 2020
  expect_true(all(c("2019-05-01", "2020-05-04") %in% dates(of_type(ev, "planting"))))
  expect_true("2019-09-11" %in% dates(of_type(ev, "harvest")))
  # the monitoring product's G6 cycle of 2019 is gone
  expect_false(any(c("2019-02-05", "2019-05-22") %in% dates(ev)))

  ln <- sipnet_lines("us_bi2")
  fert <- lines_of(ln, "fert")
  n_kg_ha <- tapply(vapply(fert, function(l) l$values[3], 0) * 10, vapply(fert, `[[`, 0L, "year"), sum)
  expect_equal(as.vector(n_kg_ha), rep(118, 8))
  expect_true(all(vapply(fert, function(l) all(l$values[1:2] == 0), TRUE)))
  for (h in lines_of(ln, "harv")) expect_equal(h$values, c(0.892, 0, 0.108, 1))
  expect_equal(as.vector(table(vapply(lines_of(ln, "plant"), `[[`, 0L, "year"))), rep(1L, 8))
})

test_that("US-Twt flood water reaches SIPNET as soil irrigation, never canopy", {
  ev <- read_events("us_twt")$events
  irr <- of_type(ev, "irrigation")
  method <- field(irr, "method")
  flood <- grepl("^Flood irrigation", field(irr, "provenance_note"))
  expect_false("flood" %in% method)
  expect_true(all(method[flood] == "soil"))
  # the only canopy events are the monitoring product's own, which it does not call flood
  expect_true(all(!flood[method == "canopy"]))
  expect_true(all(startsWith(field(irr, "source")[method == "canopy"], "monitoring_product:irrigation/v1.1")))
  expect_equal(sum(method == "canopy"), 8L)

  ln <- sipnet_lines("us_twt")
  codes <- vapply(lines_of(ln, "irrig"), function(l) l$values[2], 0)
  expect_length(codes, length(irr))
  expect_equal(sum(codes == 1), sum(flood))
  expect_equal(sum(codes == 0), sum(method == "canopy"))
})

test_that("US-Twt floods follow the WTD onsets and are held to their drains", {
  ev <- read_events("us_twt")$events
  irr <- of_type(ev, "irrigation")
  wtd <- read.csv(file.path(root, "tools", "event_prep", "us_twt_wtd_water_dates.csv"), colClasses = "character")
  derived <- Filter(function(e) e$provenance_class == "derived", irr)
  expect_equal(dates(derived), wtd$flood_onset[nzchar(wtd$flood_onset)])
  expect_length(derived, 14L)
  expect_true(all(field(derived, "source") == "ameriflux:US-Twt BASE-BADM 7-5 WTD"))
  rule <- Filter(function(e) e$provenance_class == "imputed", irr)
  expect_true(all(startsWith(field(rule, "source"), "monitoring_product:irrigation/v1.1")))
  # each flood: weekly from its onset (or the first day of the run) to the last week before its drain
  d <- as.Date(dates(c(derived, rule)))
  for (i in seq_len(nrow(wtd))) {
    start <- as.Date(if (nzchar(wtd$flood_onset[i])) wtd$flood_onset[i] else "2010-01-01")
    span <- sort(d[d >= start & d < as.Date(wtd$drain[i])])
    expect_equal(span, seq(start, as.Date(wtd$drain[i]) - 1, by = 7), info = wtd$drain[i])
  }
  # the 2016 winter flood is no longer cut at the end of 2016
  expect_equal(max(d), as.Date("2017-03-09"))
  expect_equal(unique(vapply(c(derived, rule), `[[`, 0, "amount_mm")), 70)
})

test_that("US-Twt tillage cites the record for each implement in every year", {
  till <- of_type(read_events("us_twt")$events, "tillage")
  expect_length(till, 28L)
  expect_equal(as.vector(table(substr(dates(till), 1, 4))), rep(2L, 14))
  src <- setNames(field(till, "source"), field(till, "implement"))
  expect_true(all(src[names(src) == "disking"] == "calval:managements/delta-tillage-0001"))
  expect_true(all(src[names(src) == "ring rolling"] == "calval:managements/delta-tillage-0002"))
})
