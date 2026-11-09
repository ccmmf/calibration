# Behaviour of the Russell Ranch phase files as built by tools/event_prep/russell_split_phases.R
# (runs/russell_ranch/events_treatments). They live outside the package, so R CMD check, which
# runs the tests elsewhere, skips this file.
events_dir <- testthat::test_path("..", "..", "runs", "russell_ranch", "events_treatments")
skip_if_not(dir.exists(events_dir), "runs/russell_ranch/events_treatments is not in this tree")
skip_if_not_installed("jsonlite")

russell_events <- function(tid, phase) {
  f <- file.path(events_dir, sprintf("russell_ranch_tautges_2019_%s__%s.json", tid, phase))
  jsonlite::read_json(f, simplifyVector = FALSE)$events
}
of_type <- function(ev, type, crop = NULL) Filter(function(e) e$event_type == type &&
  (is.null(crop) || identical(e$crop_display, crop)), ev)
dates <- function(ev) as.Date(vapply(ev, `[[`, "", "date"))
n_kg_ha <- function(ev) vapply(ev, function(e) if (is.null(e$nh4_n_kg_m2)) 0 else e$nh4_n_kg_m2 * 1e4, 0)

# The fertilization of the wheat planted on `planted`: from 90 days before it to its harvest
wheat_season_fert <- function(ev, planted) {
  hv <- dates(of_type(ev, "harvest", "Wheat"))
  harvested <- min(hv[hv > planted & hv <= planted + 365])
  fert <- of_type(ev, "fertilization")
  fert[dates(fert) >= planted - 90 & dates(fert) <= harvested]
}

test_that("rainfed wheat carries the logged rate, not the paper's 146", {
  # Rainfed Wheat/Fallow (RWF+N): the log has every season at about 112 kg N/ha, the paper 146.
  totals <- unlist(lapply(c("wheat-fallow", "fallow-wheat"), function(ph) {
    ev <- russell_events("rf_wheat_fallow", ph)
    pl <- dates(of_type(ev, "planting", "Wheat"))
    pl <- pl[pl >= as.Date("1993-09-01") & pl < as.Date("2013-01-01")]
    vapply(pl, function(p) sum(n_kg_ha(wheat_season_fert(ev, p))), 0)
  }))
  expect_length(totals, 20L)
  expect_true(all(totals > 111.5 & totals < 114), info = paste(round(totals, 2), collapse = " "))
})

test_that("the spring 1999 rainfed urea is on the wheat plots, not the fallow ones", {
  # The log files the 3/4/1999 urea under the fallow plots 1-9, 5-9 and 8-2; the wheat that spring
  # was on 2-9, 5-8 and 7-2 (rwf_wheat_urea_plot_1999). Their season keeps that logged urea and
  # copies only its missing preplant.
  wheat <- wheat_season_fert(russell_events("rf_wheat_fallow", "fallow-wheat"), as.Date("1998-11-02"))
  urea <- Filter(function(e) identical(e$material, "Urea"), wheat)
  expect_length(urea, 1L)
  expect_equal(urea[[1]]$date, "1999-03-04")
  expect_equal(n_kg_ha(urea), 29.54, tolerance = 1e-6)
  expect_identical(urea[[1]]$provenance_class, "published")
  pre <- Filter(function(e) !identical(e$material, "Urea"), wheat)
  expect_length(pre, 1L)
  expect_identical(pre[[1]]$provenance_class, "imputed")
  expect_equal(sum(n_kg_ha(wheat)), 84.13 + 29.54, tolerance = 1e-6)

  fallow <- of_type(russell_events("rf_wheat_fallow", "wheat-fallow"), "fertilization")
  on_bare_soil <- dates(fallow) > as.Date("1998-08-01") & dates(fallow) < as.Date("1999-09-01")
  expect_false(any(on_bare_soil))
})

test_that("irrigated wheat with no N record keeps the paper's 56 kg N/ha starter and 112 urea", {
  # The paper's irrigated total, 168, is what the log records, so these seasons keep its rates.
  gap <- wheat_season_fert(russell_events("irr_wheat_fallow", "fallow-wheat"), as.Date("1998-11-02"))
  expect_equal(sort(n_kg_ha(gap)), c(56, 112), tolerance = 1e-6)
})

# For each harvest of `from` whose next planting is of `to`, the tillage events between them
tillage_between <- function(ev, from, to) {
  pl <- of_type(ev, "planting"); pd <- dates(pl)
  til <- dates(of_type(ev, "tillage"))
  out <- list()
  for (h in of_type(ev, "harvest", from)) {
    hd <- as.Date(h$date); nxt <- which(pd > hd)
    if (!length(nxt)) next
    k <- nxt[which.min(pd[nxt])]
    if (identical(pl[[k]]$crop_display, to)) out[[h$date]] <- til[til > hd & til < pd[k]]
  }
  out
}

test_that("a wheat-fallow fallow gets the two straw passes and four fallow diskings, six in all", {
  # David on calibration#10 (2026-11-02): "two straw incorporation passes + four fallow disking".
  # The straw passes are one event by 31 July, the four diskings four events after it.
  for (tid in c("irr_wheat_control", "irr_wheat_fallow", "rf_wheat_control", "rf_wheat_fallow"))
    for (ph in c("wheat-fallow", "fallow-wheat")) {
      fallows <- tillage_between(russell_events(tid, ph), "Wheat", "Wheat")
      expect_gt(length(fallows), 0L)
      for (h in names(fallows)) {
        jul31 <- as.Date(sprintf("%s-07-31", substr(h, 1, 4)))
        expect_equal(sum(fallows[[h]] <= jul31), 1L, info = paste(tid, ph, h))
        expect_equal(sum(fallows[[h]] > jul31), 4L, info = paste(tid, ph, h))
      }
    }
})

test_that("the wheat and cover crop systems get no tillage in the summer fallow after the cover crop", {
  # Tautges et al. 2019 fallow the wheat "with the exception of RWF+WCC", whose cover crop is
  # terminated in March or April and whose soil then "remained fallow until planting of wheat";
  # the package logs the fallow herbicide on the wheat-fallow systems only.
  for (tid in c("rf_wheat_legume", "irr_wheat_legume"))
    for (ph in c("wheat-cc", "cc-wheat")) {
      ev <- russell_events(tid, ph)
      summer <- tillage_between(ev, "Cover Crop", "Wheat")
      expect_gt(length(summer), 0L)
      expect_equal(unique(lengths(summer)), 0L, info = paste(tid, ph))
      # after the wheat harvest only the straw disking, before the cover crop is sown
      expect_equal(unique(lengths(tillage_between(ev, "Wheat", "Cover Crop"))), 1L, info = paste(tid, ph))
      # the cover crop's termination diskings are one event on its end date
      ends <- dates(of_type(ev, "harvest", "Cover Crop"))
      til <- dates(of_type(ev, "tillage"))
      expect_true(all(vapply(ends, function(d) sum(til == d) == 1L, TRUE)), info = paste(tid, ph))
    }
})
