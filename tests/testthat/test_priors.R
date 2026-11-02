# one calibrated rate shared across PFTs needs one prior, and a state anchored
# on a joint meta must scope to its variable; both failure modes are silent
# without these contracts.

test_that("a shared prior is returned only when the soil PFTs agree", {
  skip_if_not_installed("PEcAn.priors")
  make_post <- function(path, parama) {
    post.distns <- data.frame(distn = "weibull", parama = parama, paramb = 0.0112,
                              row.names = "som_respiration_rate")
    save(post.distns, file = path)
    path
  }
  d <- withr::local_tempdir()
  agree <- c(soil = make_post(file.path(d, "a.Rdata"), 2.21),
             soil_rice = make_post(file.path(d, "b.Rdata"), 2.21))
  pr <- prior_from_shared_postdistns("som_respiration_rate", agree)
  expect_equal(pr$som_respiration_rate$parama, 2.21)

  differ <- c(soil = make_post(file.path(d, "c.Rdata"), 2.21),
              soil_rice = make_post(file.path(d, "e.Rdata"), 9.99))
  expect_error(prior_from_shared_postdistns("som_respiration_rate", differ),
               "differs between soil PFTs")
})

test_that("state_prior_from_obs anchors on one variable, not the whole joint meta", {
  meta <- tibble::tibble(
    slot = paste0("s", 1:4),
    variable = c("SOC_stock", "SOC_stock", "N2O_flux", "N2O_flux"),
    treatment_id = c("t1", "t2", "t1", "t2"),
    obs_year = c(2005, 2005, 2005, 2005),
    value = c(40, 44, 0.3, 0.5),
    var_obs = c(4, 4, 0.01, 0.01)
  )
  pr <- state_prior_from_obs(meta, prefix = "soilInit.", from_unit = "Mg/ha",
                             to_unit = "kg/m2", variable = "SOC_stock",
                             anchor_year = 2005)
  expect_length(pr, 2)                                 # only the two SOC treatments
  expect_named(pr, c("soilInit.t1", "soilInit.t2"))
  expect_error(state_prior_from_obs(meta, "soilInit.", "Mg/ha", "kg/m2",
                                    variable = "AbvGrndWood"), "AbvGrndWood")
})
