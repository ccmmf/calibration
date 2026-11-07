# The Salinas (SOCS) events.json files are built by tools/event_prep/salinas_build_events.R and
# kept in runs/salinas_socs, outside the package, so they are read from the source tree; R CMD
# check runs the tests elsewhere and skips this file. These tests check what the files say, not
# how the builder is written.
dir <- testthat::test_path("..", "..", "runs", "salinas_socs")
helpers <- testthat::test_path("..", "..", "tools", "event_prep", "fill_order.R")
skip_if_not(dir.exists(dir) && file.exists(helpers), "runs/salinas_socs is not in this tree")
skip_if_not_installed("jsonlite")
source(helpers, local = TRUE)

SYSTEMS <- sprintf("socs_sys%d", 1:8)
COVER_CROPS <- c("legume-rye", "mustard", "rye")
files <- setNames(lapply(SYSTEMS, function(s) jsonlite::fromJSON(
  file.path(dir, sprintf("events_%s.json", s)), simplifyVector = FALSE)), SYSTEMS)
events_of <- function(s, type = NULL, crop = NULL)
  Filter(function(e) (is.null(type) || e$event_type == type) && (is.null(crop) || identical(e$crop_code, crop)),
         files[[s]]$events)
fractions <- function(e) unlist(e[HARVEST_FRACTIONS], use.names = FALSE)
year <- function(e) substr(e$date, 1, 4)
years <- function(evs) vapply(evs, year, "")

test_that("each system has its own events file", {
  for (s in SYSTEMS) {
    expect_equal(files[[s]]$pecan_events_version, "0.1.1")
    expect_equal(files[[s]]$site_id, s)
    expect_equal(files[[s]]$provenance$treatment, s)
    expect_gt(length(files[[s]]$events), 300)
  }
})

test_that("a marketed lettuce harvest removes the hearts and leaves the rest of the shoot and the roots", {
  for (s in SYSTEMS) {
    h <- events_of(s, "harvest", "romaine_lettuce")
    expect_equal(years(h), as.character(2004:2011))
    for (e in h) expect_equal(fractions(e), c(0.26, 0, 0.74, 1))
  }
})

test_that("a marketed broccoli harvest removes 0.24 of the shoot", {
  for (s in SYSTEMS) {
    h <- events_of(s, "harvest", "broccoli")
    expect_equal(years(h), as.character(2005:2010))
    for (e in h[years(h) != "2005"]) expect_equal(fractions(e), c(0.24, 0, 0.76, 1))
  }
})

test_that("the unharvested 2004 spinach and 2005 broccoli and every cover crop remove nothing", {
  for (s in SYSTEMS) {
    ends <- c(events_of(s, "harvest", "baby_leaf_spinach"),
              Filter(function(e) year(e) == "2005", events_of(s, "harvest", "broccoli")),
              Filter(function(e) e$crop_code %in% COVER_CROPS, events_of(s, "harvest")))
    expect_length(ends, 2L + sum(vapply(events_of(s, "planting"), function(e) e$crop_code %in% COVER_CROPS, TRUE)))
    for (e in ends) expect_equal(fractions(e), c(0, 0, 1, 1))
  }
})

test_that("every harvest carries all four fractions", {
  for (s in SYSTEMS) expect_no_error(check_harvest_fractions(files[[s]]$events))
})

test_that("every event says where it came from and how sure it is", {
  for (s in SYSTEMS) for (e in files[[s]]$events) {
    expect_true(is.character(e$source) && nzchar(e$source))
    expect_true(e$provenance_class %in% PROVENANCE_CLASSES)
    if (e$provenance_class != "published") expect_true(nzchar(e$provenance_note))
    expect_false(is.null(e$calval_event_id))
  }
})

test_that("events stay in 2003-2011 and one crop grows at a time, once a year", {
  for (s in SYSTEMS) {
    ev <- files[[s]]$events
    d <- as.Date(vapply(ev, `[[`, "", "date"))
    expect_true(all(d >= as.Date("2003-01-01") & d <= as.Date("2011-12-31")))
    expect_false(is.unsorted(d))
    pe <- Filter(function(e) e$event_type %in% c("planting", "harvest"), ev)
    type <- vapply(pe, `[[`, "", "event_type")
    crop <- vapply(pe, `[[`, "", "crop_code")
    expect_equal(type, rep(c("planting", "harvest"), length.out = length(pe)))
    expect_equal(crop[type == "planting"], crop[type == "harvest"])
    pl <- events_of(s, "planting")
    expect_false(anyDuplicated(paste(vapply(pl, `[[`, "", "crop_code"), years(pl))) > 0)
  }
})

test_that("the cover crops are sown every winter in socs_sys3 to socs_sys8 and in Years 4 and 8 in socs_sys1 and socs_sys2", {
  sown <- function(s) years(Filter(function(e) e$crop_code %in% COVER_CROPS, events_of(s, "planting")))
  for (s in SYSTEMS[3:8]) expect_equal(sown(s), as.character(2003:2010))
  for (s in SYSTEMS[1:2]) expect_equal(sown(s), c("2006", "2010"))
})

test_that("the control gets no compost and the compost systems 15 applications of 7.6 Mg/ha", {
  compost <- function(s) Filter(function(e) identical(e$material, "composted_green_waste"), events_of(s, "fertilization"))
  expect_length(compost("socs_sys1"), 0L)
  for (s in SYSTEMS[-1]) {
    k <- compost(s)
    expect_length(k, 15L)
    # 0.76 kg m-2 oven dry at 317 g C kg-1 and the calendar's 15 g N kg-1
    for (e in k) {
      expect_equal(e$org_c_kg_m2, 0.76 * 0.317)
      expect_equal(e$org_n_kg_m2, 0.76 * 0.015)
    }
  }
})

test_that("the fertilizer N adds up to the published totals of each year", {
  # pellets plus liquid: lettuce 56 in 2004 and 73 after, spinach 22, broccoli 134 in 2005 and
  # 168 after (Brennan and Boyd 2012)
  want <- c("2004" = 56 + 22, "2005" = 73 + 134, "2006" = 73 + 168, "2007" = 73 + 168, "2008" = 73 + 168,
            "2009" = 73 + 168, "2010" = 73 + 168, "2011" = 73)
  for (s in SYSTEMS) {
    f <- Filter(function(e) !identical(e$material, "composted_green_waste"), events_of(s, "fertilization"))
    n <- vapply(f, function(e) sum(unlist(e[c("org_n_kg_m2", "nh4_n_kg_m2")])), 0) * 1e4
    got <- tapply(n, years(f), sum)
    expect_equal(got[names(want)], want, tolerance = 1e-9, ignore_attr = TRUE)
  }
})

test_that("the cover crop establishment water adds up to Brennan and Boyd's Fig. 2", {
  water <- function(s) {
    i <- Filter(function(e) e$method == "canopy", events_of(s, "irrigation"))
    tapply(vapply(i, `[[`, 0, "amount_mm"), years(i), sum)
  }
  for (s in SYSTEMS[3:8])
    expect_equal(unname(c(water(s))), c(45, 13, 32, 19, 52, 42, 49, 19), tolerance = 1e-3)
  for (s in SYSTEMS[1:2]) expect_equal(unname(c(water(s))), c(19, 19), tolerance = 1e-3)
})

test_that("vegetable irrigation is a soil schedule inside each crop's season", {
  for (s in SYSTEMS) {
    ev <- files[[s]]$events
    pe <- Filter(function(e) e$event_type %in% c("planting", "harvest") && !e$crop_code %in% COVER_CROPS, ev)
    starts <- as.Date(vapply(Filter(function(e) e$event_type == "planting", pe), `[[`, "", "date"))
    ends <- as.Date(vapply(Filter(function(e) e$event_type == "harvest", pe), `[[`, "", "date"))
    drip <- as.Date(vapply(Filter(function(e) e$method == "soil", events_of(s, "irrigation")), `[[`, "", "date"))
    inside <- vapply(drip, function(d) any(d >= starts & d < ends), TRUE)
    expect_true(all(inside))
    # every vegetable season is irrigated
    expect_true(all(vapply(seq_along(starts), function(j) any(drip >= starts[j] & drip < ends[j]), TRUE)))
  }
})

test_that("SIPNET gets the lettuce harvest and the cover crop ends as written", {
  skip_if_not_installed("PEcAn.SIPNET")
  old <- PEcAn.logger::logger.setLevel("OFF")
  withr::defer(PEcAn.logger::logger.setLevel(old))
  out <- withr::local_tempdir()
  PEcAn.SIPNET::write.events.SIPNET(file.path(dir, "events_socs_sys3.json"), out)
  lines <- readLines(file.path(out, "events-socs_sys3.in"))
  expect_length(lines, length(files$socs_sys3$events))
  harv <- grep(" harv ", lines, value = TRUE)
  expect_equal(sum(grepl("harv +0.26 0 0.74 1$", harv)), 8L)
  expect_equal(sum(grepl("harv +0.24 0 0.76 1$", harv)), 5L)
  expect_equal(sum(grepl("harv +0 0 1 1$", harv)), 8L + 2L)
  # drip on the soil (1), the cover crop sprinkler on the canopy (0)
  irrig_code <- sub(".* ", "", grep(" irrig ", lines, value = TRUE))
  expect_equal(sum(irrig_code == "0"), 6L + 2L + 3L + 1L + 7L + 5L + 3L + 3L)
})

# The builder on a one-year calendar, the same in every system: the broccoli harvest is dated in
# or after the window of the fall residue incorporation, and the lettuce planting falls inside the
# window of the spring spading
build_one_year <- function(root, broccoli_harvest) {
  builder <- testthat::test_path("..", "..", "tools", "event_prep", "salinas_build_events.R")
  skip_if_not(file.exists(builder), "tools/event_prep/salinas_build_events.R is not in this tree")
  dir.create(file.path(root, "cv", "data"), recursive = TRUE)
  dir.create(file.path(root, "out"))
  rows <- data.frame(
    id = c("planting-lettuce", "harvest-lettuce", "planting-broccoli", "harvest-broccoli", "tillage-spring",
           "tillage-fall"),
    mgmttype = c("planting", "harvest", "planting", "harvest", "tillage", "tillage"),
    min_date = c("2005-05-01", "2005-07-01", "2005-07-25", broccoli_harvest, "2005-04-15", "2005-09-21"),
    max_date = c("2005-05-01", "2005-07-01", "2005-07-25", broccoli_harvest, "2005-05-20", "2005-09-29"),
    crop_name = c("romaine_lettuce", "romaine_lettuce", "broccoli", "broccoli", "", ""),
    attributes_keyvalue = c("", "harvested_component=heart; harvest_index=0.26", "",
                            "harvested_component=floret; harvest_index=0.24", "implement=spader", paste(
                              "implement=flail_mower+disc_harrow+spring_tooth_harrow+spader+ring_roller;",
                              "relative_timing=before_planting; relative_to=cover_crop_or_fallow")))
  cal <- do.call(rbind, lapply(SYSTEMS, function(s)
    data.frame(event_id = paste(rows$id, s, sep = "-"), sites.name = "salinas_socs", treatments.name = s, rows[-1],
               cover_crop = "FALSE", level = "", units = "", notes = "", citation = "10.2134/agronj2011.0330")))
  write.csv(cal, file.path(root, "cv", "data", "managements.csv"), row.names = FALSE)
  write.csv(data.frame(name = SYSTEMS, definition = "test"), file.path(root, "cv", "data", "treatments.csv"),
            row.names = FALSE)
  write.csv(data.frame(common.name = c("romaine lettuce", "baby leaf spinach", "broccoli", "legume-rye mix",
                                       "mustard", "cereal rye")),
            file.path(root, "cv", "data", "crops.csv"), row.names = FALSE)
  file.copy(file.path(dir, "monitoring_near_salinas.csv"), file.path(root, "out"))
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  shQuote(c(normalizePath(builder), file.path(root, "cv"), file.path(root, "out"))),
                                  stdout = TRUE, stderr = TRUE))
  list(status = attr(out, "status"), log = paste(out, collapse = "\n"), events = function(s) jsonlite::fromJSON(
    file.path(root, "out", sprintf("events_%s.json", s)), simplifyVector = FALSE)$events)
}

test_that("a fall incorporation follows the harvest it incorporates and the spring spading precedes the planting", {
  b <- build_one_year(withr::local_tempdir(), "2005-09-27")
  expect_null(b$status, info = b$log)
  mon <- read.csv(file.path(dir, "monitoring_near_salinas.csv"))
  broccoli_eff <- mon$value[mon$slot == "broccoli" & mon$quantity == "postharvest_tillage_eff"]
  for (s in SYSTEMS) {
    ev <- b$events(s)
    on <- function(id) Filter(function(e) e$calval_event_id == paste(id, s, sep = "-"), ev)[[1]]
    expect_gt(as.Date(on("tillage-fall")$date), as.Date("2005-09-27"))
    expect_equal(on("tillage-fall")$tillage_eff_0to1, round(broccoli_eff, 4))
    expect_lt(as.Date(on("tillage-spring")$date), as.Date(on("planting-lettuce")$date))
  }
})

test_that("the builder stops when a fall incorporation would come before a harvest of its year", {
  b <- build_one_year(withr::local_tempdir(), "2005-10-05")
  expect_false(is.null(b$status))
  expect_match(b$log, "tillage-fall-socs_sys1 on 2005-09-[0-9]+ is not after the harvest it follows")
})
