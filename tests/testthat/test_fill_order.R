# The fill helpers the events.json generators share live in tools/event_prep, outside the
# package, so they are sourced from the source tree; R CMD check runs the tests elsewhere and
# skips this file.
helpers <- testthat::test_path("..", "..", "tools", "event_prep", "fill_order.R")
skip_if_not(file.exists(helpers), "tools/event_prep/fill_order.R is not in this tree")
source(helpers, local = TRUE)

test_that("first_available takes the first candidate that has a value and names it", {
  pick <- first_available(list(paper = NULL, monitoring = c(120, 135), guidance = 150))
  expect_equal(pick$value, c(120, 135))
  expect_equal(pick$from, "monitoring")
  expect_equal(pick$n, 2L)
  expect_equal(first_available(list(paper = NA_real_, monitoring = numeric(), guidance = 150))$from,
               "guidance")
  expect_null(first_available(list(paper = NULL, monitoring = NA)))
})

test_that("first_available falls back to the broader pool when the narrow one is too small", {
  doy <- list(system = c(150, 160, 170), site = c(150, 160, 170, 180, 190, 200))
  pick <- first_available(doy, min_n = c(5, 1))
  expect_equal(pick$from, "site")
  expect_equal(pick$n, 6L)
  doy$system <- c(doy$system, 155, 165)
  expect_equal(first_available(doy, min_n = c(5, 1))$from, "system")
})

test_that("first_available returns only the values it counted", {
  doy <- list(system = c(150, NA, NA, NA, NA, 160, 170, 180, 190), site = 1:20)
  pick <- first_available(doy, min_n = c(5, 1))
  expect_equal(pick$from, "system")
  expect_equal(pick$n, 5L)
  expect_equal(pick$value, c(150, 160, 170, 180, 190))
  expect_length(pick$value, pick$n)
  expect_equal(median(pick$value), 170)
  dates <- first_available(list(paper = as.Date(c(NA, "2004-04-01"))))
  expect_equal(dates$value, as.Date("2004-04-01"))
})

test_that("first_available counts events in a list and rows in a data frame", {
  plantings <- list(phase = list(), site = list(list(date = "2010-05-01"), list(date = "2011-05-03")))
  pick <- first_available(plantings)
  expect_equal(pick$from, "site")
  expect_equal(pick$n, 2L)
  dates <- list(sample = data.frame(date = as.Date(character())),
                plot_table = data.frame(date = as.Date("2004-04-01")))
  expect_equal(first_available(dates)$from, "plot_table")
})

test_that("first_available needs every candidate named", {
  expect_error(first_available(list(1, 2)), "named list")
  expect_error(first_available(list(paper = 1, 2)), "named list")
})

test_that("set_provenance tags an event and keeps its fields where they are", {
  e <- list(event_type = "irrigation", date = "2004-06-01", source = "10.1111/gcb.14762", amount_mm = 80)
  tagged <- set_provenance(e, "assumed", "The paper's mm read as inches.")
  expect_equal(names(tagged), c(names(e), "provenance_class", "provenance_note"))
  expect_equal(tagged$provenance_class, "assumed")
  expect_equal(tagged$provenance_note, "The paper's mm read as inches.")

  copied <- set_provenance(tagged, "imputed", "Copies the 2003 application.")
  expect_equal(names(copied), names(tagged))
  expect_equal(copied$provenance_class, "imputed")

  ended <- set_provenance(list(event_type = "harvest", date = "2005-04-02"), "published",
                          source = "10.1002/ecy.2105:wcc_harvests_all.csv")
  expect_equal(names(ended), c("event_type", "date", "source", "provenance_class"))
})

test_that("set_provenance rejects a class the generators do not use", {
  e <- list(event_type = "tillage", date = "2004-06-01", source = "monitoring")
  expect_error(set_provenance(e, "estimated", "Median of 40 events."), "provenance_class must be one of")
  expect_error(set_provenance(e, c("imputed", "assumed"), "Median of 40 events."), "provenance_class")
  expect_error(set_provenance(e, NA_character_, "Median of 40 events."), "provenance_class")
})

test_that("a filled event must say where it came from and what it rests on", {
  e <- list(event_type = "tillage", date = "2004-06-01")
  expect_error(set_provenance(e, "imputed", "Median of 40 events."), "needs a source")
  expect_error(set_provenance(e, "imputed", "Median of 40 events.", source = NA_character_), "needs a source")
  # a field whose name starts with "source" is not a source
  expect_error(set_provenance(list(event_type = "tillage", source_file = "x.csv"), "published"),
               "needs a source")
  expect_error(set_provenance(c(e, source = NA_character_), "published"), "needs a source")
  expect_error(set_provenance(e, "published", source = ""), "needs a source")
  e$source <- "monitoring"
  expect_error(set_provenance(e, "imputed"), "needs a provenance_note")
  expect_error(set_provenance(e, "assumed", ""), "needs a provenance_note")
  expect_no_error(set_provenance(e, "published"))
})

test_that("a generator finds fill_order.R next to it when its path has a space", {
  skip_if_not_installed("jsonlite")
  generator <- testthat::test_path("..", "..", "tools", "event_prep", "russell_split_phases.R")
  skip_if_not(file.exists(generator), "tools/event_prep/russell_split_phases.R is not in this tree")
  dir <- file.path(withr::local_tempdir(), "Google Drive", "event prep")
  dir.create(dir, recursive = TRUE)
  file.copy(c(generator, helpers), dir)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                  shQuote(file.path(dir, "russell_split_phases.R")),
                                  stdout = TRUE, stderr = TRUE))
  expect_false(any(grepl("cannot open", out)), info = paste(out, collapse = "\n"))
  expect_match(paste(out, collapse = "\n"), "usage: russell_split_phases.R")
})

test_that("harvest_fractions writes all four fractions in SIPNET's order", {
  fr <- harvest_fractions(above_removed = 0.462, below_removed = 0, above_to_litter = 0.538, below_to_litter = 1)
  expect_equal(names(fr), c("frac_above_removed_0to1", "frac_below_removed_0to1",
                            "frac_above_to_litter_0to1", "frac_below_to_litter_0to1"))
  expect_equal(unlist(fr, use.names = FALSE), c(0.462, 0, 0.538, 1))
})

test_that("harvest_fractions has no defaults", {
  expect_error(harvest_fractions(0.85), "missing")
  expect_error(harvest_fractions(above_removed = 0.85, below_removed = 0, above_to_litter = 0), "missing")
})

test_that("harvest_fractions rejects shares outside 0 to 1 or adding up past 1", {
  expect_error(harvest_fractions(1.2, 0, 0, 0), "from 0 to 1")
  expect_error(harvest_fractions(0.85, 0, NA, 0), "from 0 to 1")
  expect_error(harvest_fractions(0.85, 0, 0.3, 0), "aboveground")
  expect_error(harvest_fractions(0, 0.5, 0, 0.6), "belowground")
})

test_that("check_harvest_fractions stops on a harvest missing a fraction", {
  cut <- c(list(event_type = "harvest", date = "2013-05-20", crop_display = "Alfalfa"),
           harvest_fractions(0.85, 0, 0, 0))
  bare <- list(event_type = "harvest", date = "2013-06-20", crop_display = "Alfalfa",
               frac_above_removed_0to1 = 0.85)
  till <- list(event_type = "tillage", date = "2013-07-01", tillage_eff_0to1 = 0.2)
  expect_no_error(check_harvest_fractions(list(cut, till)))
  expect_error(check_harvest_fractions(list(cut, bare)),
               "Alfalfa harvest on 2013-06-20 lacks frac_below_removed_0to1, frac_above_to_litter_0to1")
  bad <- cut; bad$frac_above_to_litter_0to1 <- 0.5
  expect_error(check_harvest_fractions(list(bad)), "aboveground removed and to litter")
})

test_that("a perennial cutting reaches SIPNET as written, not with its transfer as 1 - removed", {
  skip_if_not_installed("PEcAn.SIPNET")
  skip_if_not_installed("jsonlite")
  old <- PEcAn.logger::logger.setLevel("OFF")
  withr::defer(PEcAn.logger::logger.setLevel(old))
  cut <- c(list(event_type = "harvest", date = "2013-05-20", crop_display = "Alfalfa"),
           harvest_fractions(0.85, 0, 0, 0))
  bare <- list(event_type = "harvest", date = "2013-06-20", crop_display = "Alfalfa",
               frac_above_removed_0to1 = 0.85)
  dir <- withr::local_tempdir()
  json <- file.path(dir, "events.json")
  jsonlite::write_json(list(pecan_events_version = "0.1.1", site_id = "cut", events = list(cut, bare)),
                       json, auto_unbox = TRUE, digits = NA)
  PEcAn.SIPNET::write.events.SIPNET(json, dir)
  harv <- grep(" harv ", readLines(file.path(dir, "events-cut.in")), value = TRUE)
  expect_length(harv, 2L)
  expect_match(harv[1], "harv +0.85 0 0 0$")
  # the same cutting with only the removed share: the writer sends the rest of the shoots and
  # all the roots to litter, which ends the stand
  expect_match(harv[2], "harv +0.85 0 0.15 1$")
})
