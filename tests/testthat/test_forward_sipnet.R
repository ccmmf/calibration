# a shared soil rate reaching only one PFT returns a plausible number rather
# than an error, so these assert the write reaches every named PFT and that an
# absent one is loud.

test_that("inject_traits writes the shared rate into every soil PFT", {
  baseline <- list(
    soil        = data.frame(som_respiration_rate = rep(0.01, 3), kCN = rep(80, 3)),
    soil_rice   = data.frame(som_respiration_rate = rep(0.01, 3), kCN = rep(80, 3)),
    soil_nfixer = data.frame(som_respiration_rate = rep(0.01, 3), kCN = rep(80, 3)),
    annual_crop = data.frame(SLA = rep(19, 3))
  )
  U <- matrix(c(0.02, 0.03, 0.04), ncol = 1,
              dimnames = list(NULL, "som_respiration_rate"))
  out <- inject_traits(baseline, c("soil", "soil_rice", "soil_nfixer"), U)

  for (pft in c("soil", "soil_rice", "soil_nfixer")) {
    expect_equal(out[[pft]]$som_respiration_rate, c(0.02, 0.03, 0.04))
    expect_equal(out[[pft]]$kCN, rep(80, 3))          # uncalibrated column untouched
  }
  expect_equal(out$annual_crop$SLA, rep(19, 3))       # veg PFT untouched
})

test_that("inject_traits fails when a named soil PFT is absent", {
  baseline <- list(soil = data.frame(som_respiration_rate = rep(0.01, 2)))
  U <- matrix(0.02, nrow = 2, ncol = 1,
              dimnames = list(NULL, "som_respiration_rate"))
  expect_error(inject_traits(baseline, c("soil", "soil_rice"), U), "soil_rice")
})

test_that("run_window reads each treatment's own years from the settings", {
  fake <- function(id, a, b) list(run = list(site = list(id = id),
                                             start.date = a, end.date = b))
  settings <- list(fake("early", "2005-01-01", "2011-12-31"),
                   fake("late",  "2017-01-01", "2023-12-31"))
  w <- run_window(settings)
  expect_equal(w[, "early"], c(2005L, 2011L))
  expect_equal(w[, "late"],  c(2017L, 2023L))
})
