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
  # an assumed date with the monitoring product's leaf C: the weaker part makes it imputed
  expect_equal(field(of_type(ev, "planting"), "provenance_class"), "imputed")
  # backfilled leaf C is a median, not a mean
  expect_match(field(of_type(ev, "planting"), "prior_filled"), "^leaf_c_kg_m2<-median of")
  cuts <- read.csv(file.path(root, "tools", "event_prep", "us_bi1_cuttings.csv"), colClasses = "character")
  # every date says what it is read from
  expect_equal(names(cuts), c("date", "basis", "note"))
  expect_true(all(nchar(cuts$note) > 40))
  expect_equal(dates(of_type(ev, "harvest")), cuts$date)
  expect_equal(nrow(cuts), 39L)
  expect_equal(as.vector(table(substr(cuts$date, 1, 4))), c(6L, 6L, 6L, 6L, 6L, 3L, 6L))
  # the recorded mowing has a published date but the lookup's fractions, so it is assumed
  cls <- setNames(field(of_type(ev, "harvest"), "provenance_class"), dates(of_type(ev, "harvest")))
  expect_equal(unname(cls[names(cls) == "2020-06-04"]), "assumed")
  expect_true(all(cls[names(cls) != "2020-06-04"] == "imputed"))
  expect_length(c(of_type(ev, "tillage"), of_type(ev, "fertilization")), 0L)
  # the water comes up from the ditches, so the product's irrigation goes on as soil, not canopy
  irr <- of_type(ev, "irrigation")
  expect_length(irr, 18L)
  expect_true(all(field(irr, "method") == "soil"))

  ln <- sipnet_lines("us_bi1")
  expect_true(all(vapply(lines_of(ln, "irrig"), function(l) l$values[2], 0) == 1))
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
  expect_length(of_type(ev, "tillage"), 0L)
  # the site record's days in 2019 and Anthony and Silver 2021 Fig. 2's in 2019 and 2020
  expect_true(all(c("2019-05-01", "2020-05-04") %in% dates(of_type(ev, "planting"))))
  expect_true("2019-09-11" %in% dates(of_type(ev, "harvest")))
  # the monitoring product's G6 cycle of 2019 is gone
  expect_false(any(c("2019-02-05", "2019-05-22") %in% dates(ev)))

  ln <- sipnet_lines("us_bi2")
  codes <- vapply(lines_of(ln, "irrig"), function(l) l$values[2], 0)
  expect_equal(sum(codes == 1), sum(field(of_type(ev, "irrigation"), "method") == "soil"))
  fert <- lines_of(ln, "fert")
  n_kg_ha <- tapply(vapply(fert, function(l) l$values[3], 0) * 10, vapply(fert, `[[`, 0L, "year"), sum)
  expect_equal(as.vector(n_kg_ha), rep(118, 8))
  expect_true(all(vapply(fert, function(l) all(l$values[1:2] == 0), TRUE)))
  for (h in lines_of(ln, "harv")) expect_equal(h$values, c(0.892, 0, 0.108, 1))
  expect_equal(as.vector(table(vapply(lines_of(ln, "plant"), `[[`, 0L, "year"))), rep(1L, 8))
})

test_that("US-Bi2 gets its water: the product's 2021 and 2022 irrigation and the record's winter floods", {
  ev <- read_events("us_bi2")$events
  irr <- of_type(ev, "irrigation")
  product <- Filter(function(e) startsWith(e$source, "monitoring_product:irrigation/v1.1"), irr)
  expect_equal(dates(product), c("2021-09-08", "2022-10-16"))
  floods <- Filter(function(e) startsWith(e$source, "calval:managements/delta-flooding-"), irr)
  expect_equal(length(product) + length(floods), length(irr))
  expect_true(all(field(irr, "provenance_class") == "imputed"))
  expect_true(all(field(floods, "method") == "soil"))
  expect_true(all(grepl("^Flood irrigation", field(floods, "provenance_note"))))
  # each dated window of the site record, held weekly from its first day to its last
  windows <- list("delta-flooding-0012" = c("2017-12-01", "2018-02-28"),
                  "delta-flooding-0013" = c("2018-11-01", "2019-03-31"),
                  # 0009 dates only the December 2019 onset; it is held to the other winters' 31 March drain
                  "delta-flooding-0009" = c("2019-12-01", "2020-03-31"),
                  "delta-flooding-0014" = c("2020-11-01", "2021-03-31"))
  expect_setequal(unique(sub("^calval:managements/", "", field(floods, "source"))), names(windows))
  for (id in names(windows)) {
    got <- dates(Filter(function(e) e$source == paste0("calval:managements/", id), floods))
    expect_equal(got, format(seq(as.Date(windows[[id]][1]), as.Date(windows[[id]][2]), by = 7)), info = id)
  }
  # the floods fall in the fallow: the last crop event before each is a harvest
  crop <- Filter(function(e) e$event_type %in% c("planting", "harvest"), ev)
  for (d in dates(floods)) {
    before <- Filter(function(e) e$date < d, crop)
    expect_equal(before[[length(before)]]$event_type, "harvest", info = d)
  }
  # held by the same rule as US-Twt's floods
  twt_rule <- Filter(function(e) e$provenance_class == "imputed" && grepl("^Flood irrigation", e$provenance_note),
                     of_type(read_events("us_twt")$events, "irrigation"))
  expect_equal(unique(vapply(floods, `[[`, 0, "amount_mm")), unique(vapply(twt_rule, `[[`, 0, "amount_mm")))
})

test_that("US-Twt flood water reaches SIPNET as soil irrigation, never canopy", {
  ev <- read_events("us_twt")$events
  irr <- of_type(ev, "irrigation")
  method <- field(irr, "method")
  flood <- grepl("^Flood irrigation", field(irr, "provenance_note"))
  expect_false("flood" %in% method)
  expect_true(all(method[flood] == "soil"))
  # the only canopy events are the monitoring product's own, which it does not call flood, outside
  # a rice season: its four 2017 canopy events fall inside the rice season and are read as flood
  expect_true(all(!flood[method == "canopy"]))
  expect_true(all(startsWith(field(irr, "source")[method == "canopy"], "monitoring_product:irrigation/v1.1")))
  expect_equal(sum(method == "canopy"), 4L)
  expect_true(all(substr(dates(irr)[method == "canopy"], 1, 4) == "2022"))
  rice_canopy <- grepl("inside the rice season", field(irr, "provenance_note"))
  expect_equal(sum(rice_canopy), 4L)
  expect_true(all(method[rice_canopy] == "soil" & flood[rice_canopy]))
  expect_true(all(field(irr, "provenance_class")[rice_canopy] == "assumed"))

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
  onsets <- Filter(function(e) startsWith(e$source, "ameriflux:US-Twt BASE-BADM 7-5 WTD"), irr)
  expect_equal(dates(onsets), wtd$flood_onset[nzchar(wtd$flood_onset)])
  expect_length(onsets, 14L)
  # a WTD date carrying the rule's 69 mm: imputed, and its source names both
  expect_true(all(field(onsets, "provenance_class") == "imputed"))
  expect_true(all(grepl("; monitoring_product:irrigation/v1.1", field(onsets, "source"), fixed = TRUE)))
  expect_false("derived" %in% field(irr, "provenance_class"))
  rule <- Filter(function(e) e$provenance_class == "imputed" && startsWith(e$source, "monitoring_product:irrigation/v1.1"), irr)
  # each flood: weekly from its onset (or the first day of the run) to the last week before its drain
  d <- as.Date(dates(c(onsets, rule)))
  for (i in seq_len(nrow(wtd))) {
    start <- as.Date(if (nzchar(wtd$flood_onset[i])) wtd$flood_onset[i] else "2010-01-01")
    span <- sort(d[d >= start & d < as.Date(wtd$drain[i])])
    expect_equal(span, seq(start, as.Date(wtd$drain[i]) - 1, by = 7), info = wtd$drain[i])
  }
  # the 2016 winter flood is no longer cut at the end of 2016
  expect_equal(max(d), as.Date("2017-03-09"))
  # the median of the monitoring product's 2017-2023 flood amounts (69.46 mm), rounded
  expect_equal(unique(vapply(c(onsets, rule), `[[`, 0, "amount_mm")), 69)
})

test_that("US-Twt Knox events cite their row and take the weakest class among their parts", {
  ev <- Filter(function(e) e$event_type != "tillage" && startsWith(e$source, "calval:managements/"),
               read_events("us_twt")$events)
  expect_true(all(startsWith(field(ev, "provenance_note"), "Knox et al. 2016 Table 1")))
  # leaf C from the monitoring product, fractions from a prior, N from the reported rate and grade
  cls <- lapply(split(field(ev, "provenance_class"), field(ev, "event_type")), unique)
  expect_equal(cls, list(fertilization = "derived", harvest = "assumed", planting = "imputed"))
})

test_that("US-Twt tillage cites the record for each implement in every year", {
  till <- of_type(read_events("us_twt")$events, "tillage")
  expect_length(till, 28L)
  expect_equal(as.vector(table(substr(dates(till), 1, 4))), rep(2L, 14))
  src <- setNames(field(till, "source"), field(till, "implement"))
  expect_true(all(src[names(src) == "disking"] == "calval:managements/delta-tillage-0001"))
  expect_true(all(src[names(src) == "ring rolling"] == "calval:managements/delta-tillage-0002"))
  # Knox's years rest on assumed offsets; later years carry the practice where no site record covers them
  yr <- as.integer(substr(dates(till), 1, 4))
  expect_equal(field(till, "provenance_class"), ifelse(yr <= 2015L, "assumed", "imputed"))
})

test_that("US-Twt's 2017 fill is dated from the product's other years", {
  ev <- read_events("us_twt")$events
  fill <- Filter(function(e) substr(e$date, 1, 4) == "2017" && !is.null(e$prior_filled) &&
                   grepl("2017_excluded_year", e$prior_filled), ev)
  expect_setequal(vapply(fill, `[[`, "", "event_type"), c("planting", "harvest"))
  expect_true(all(grepl("median day of year", field(fill, "provenance_note"))))
})

test_that("US-Twt carries Knox's rice harvest fraction and fertilizer regime into 2017-2023", {
  ev <- read_events("us_twt")$events
  late <- Filter(function(e) e$date >= "2017-01-01", ev)
  harv <- of_type(late, "harvest")
  rice <- vapply(harv, function(e) e$crop_display == "R1", TRUE)
  fr <- function(e) unlist(e[c("frac_above_removed_0to1", "frac_below_removed_0to1",
                               "frac_above_to_litter_0to1", "frac_below_to_litter_0to1")])
  # every rice harvest keeps the straw as in the Knox years; 2022, a G2 grain crop, keeps the product's
  for (e in harv[rice]) expect_equal(unname(fr(e)), c(0.5, 0, 0.5, 1), info = e$date)
  # a carried practice is imputed, the weakest class, as the carried fertilization and tillage are
  expect_true(all(field(harv[rice], "provenance_class") == "imputed"))
  expect_true(all(grepl("rice_harvest_index", field(harv[rice], "prior_filled"))))
  expect_equal(dates(harv[!rice]), "2022-10-25")
  expect_equal(unname(fr(harv[!rice][[1]])), c(0.8, 0, 0.2, 1))
  # one application of the 2013-2015 regime in every rice year: 100 lb/ac of 15-15-15 on 30 or 31 May
  fert <- of_type(late, "fertilization")
  yrs <- substr(dates(fert), 1, 4)
  knox <- fert[yrs != "2022"]
  expect_equal(sort(unique(substr(dates(knox), 1, 4))), c("2017", "2018", "2019", "2020", "2021", "2023"))
  expect_length(knox, 6L)
  expect_true(all(substr(dates(knox), 6, 10) %in% c("05-30", "05-31")))
  expect_true(all(field(knox, "reported_rate_lb_ac") == "100"))
  expect_true(all(field(knox, "reported_grade") == "15-15-15"))
  # 1 lb/ac = 1.12085 kg/ha and 15-15-15 is 15 % N: 16.8 kg N/ha, 0.00168 kg N/m2
  expect_equal(as.numeric(field(knox, "nh4_n_kg_m2")), rep(100 * 1.12085 * 0.15 * 1e-4, 6L), tolerance = 1e-5)
  expect_true(all(field(knox, "org_n_kg_m2") == 0))
  expect_true(all(field(knox, "source") == "10.1002/2015JG003247"))
  # no organic application from the product survives, and 2022 keeps the product's one row
  expect_false(any(vapply(fert, function(e) isTRUE(e$org_c_kg_m2 > 0), TRUE)))
  expect_true(startsWith(fert[yrs == "2022"][[1]]$source, "monitoring_product:fertilization/v1.0"))
})
