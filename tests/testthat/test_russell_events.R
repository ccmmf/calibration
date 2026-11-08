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

test_that("rainfed wheat with no N record carries its treatment's logged rate, not the paper's 146", {
  # Rainfed Wheat/Fallow (RWF+N): the log has every season at about 112 kg N/ha, the paper 146.
  # The 1998 to 1999 wheat (plots 2-9, 5-8, 7-2) has no record and copies the nearest complete
  # season as logged.
  totals <- unlist(lapply(c("wheat-fallow", "fallow-wheat"), function(ph) {
    ev <- russell_events("rf_wheat_fallow", ph)
    pl <- dates(of_type(ev, "planting", "Wheat"))
    pl <- pl[pl >= as.Date("1993-09-01") & pl < as.Date("2013-01-01")]
    vapply(pl, function(p) sum(n_kg_ha(wheat_season_fert(ev, p))), 0)
  }))
  expect_length(totals, 20L)
  expect_true(all(totals > 111.5 & totals < 113.5), info = paste(round(totals, 2), collapse = " "))

  gap <- wheat_season_fert(russell_events("rf_wheat_fallow", "fallow-wheat"), as.Date("1998-11-02"))
  expect_equal(sum(n_kg_ha(gap)), 84.13 + 27.84, tolerance = 1e-6)
  expect_setequal(vapply(gap, `[[`, "", "material"), c("Can_27", "Urea"))
  expect_true(all(vapply(gap, function(e) identical(e$provenance_class, "imputed"), TRUE)))
})

test_that("irrigated wheat with no N record keeps the paper's 56 kg N/ha starter and 112 urea", {
  # The paper's irrigated total, 168, is what the log records, so these seasons keep its rates.
  gap <- wheat_season_fert(russell_events("irr_wheat_fallow", "fallow-wheat"), as.Date("1998-11-02"))
  expect_equal(sort(n_kg_ha(gap)), c(56, 112), tolerance = 1e-6)
})
