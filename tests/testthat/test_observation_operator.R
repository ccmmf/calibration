# Five years, three treatments, none of them a rigid offset of another: a contrast with
# no year to year spread is degenerate and would make the covariance singular for a
# reason the real data does not have.
fake_series_obs <- function() {
  yrs <- 2005:2009
  trts <- c("c", "a", "b")
  vals <- c(10, 12, 11, 14, 13,
            16, 17, 18, 19, 20,
            15, 16, 14, 18, 16)
  meta <- tibble::tibble(
    slot = paste0("SOC__", rep(trts, each = length(yrs)), "__", rep(yrs, length(trts))),
    variable = "SOC", sitename = "salinas",
    treatment_id = rep(trts, each = length(yrs)),
    obs_year = rep(yrs, length(trts)),
    min_date = paste0(rep(yrs, length(trts)), "-10-01"),
    max_date = paste0(rep(yrs, length(trts)), "-10-01"),
    min_depth = 0, max_depth = 30,
    units = "Mg C ha-1", observation_level = "replicate", n_rep = 4L,
    value = vals, var_obs = 1
  )
  Sigma <- diag(1, nrow(meta)); dimnames(Sigma) <- list(meta$slot, meta$slot)
  list(y = stats::setNames(vals, meta$slot), Sigma = Sigma, meta = meta)
}

series <- function(t) fake_series_obs()$y[paste0("SOC__", t, "__", 2005:2009)]

test_that("period_mean_contrast returns one level plus one contrast per treatment", {
  out <- period_mean_contrast(fake_series_obs(), "SOC", control = "c")
  expect_equal(length(out$y), 3L)
  expect_equal(out$meta$treatment_id, c("c", "a_vs_c", "b_vs_c"))
  expect_equal(unname(out$y[1]), mean(series("c")))
  expect_equal(unname(out$y[2]), mean(series("a") - series("c")))
  expect_true(all(out$meta$variable == "SOC_periodmean"))
  expect_equal(unique(out$meta$n_rep), 5L)
})

test_that("the transform reproduces the fitted values from the raw slots", {
  obs <- fake_series_obs()
  out <- period_mean_contrast(obs, "SOC", control = "c")
  raw <- obs$y[colnames(out$transform)]
  expect_equal(as.numeric(out$transform %*% raw), as.numeric(out$y))
})

test_that("a constant added to every year moves the level and leaves contrasts alone", {
  obs <- fake_series_obs()
  out <- period_mean_contrast(obs, "SOC", control = "c")
  shifted <- obs; shifted$y <- shifted$y + 7
  out2 <- period_mean_contrast(shifted, "SOC", control = "c")
  expect_equal(unname(out2$y[1]), unname(out$y[1]) + 7)
  expect_equal(unname(out2$y[-1]), unname(out$y[-1]))
})

test_that("uncertainty is the standard error of the period mean across years", {
  out <- period_mean_contrast(fake_series_obs(), "SOC", control = "c")
  n <- 5
  expect_equal(sqrt(out$Sigma[1, 1]), stats::sd(series("c")) / sqrt(n))
  expect_equal(sqrt(out$Sigma[2, 2]),
               stats::sd(series("a") - series("c")) / sqrt(n))
  # and it is the paired spread, not the sum of the two levels' spreads
  expect_lt(out$Sigma[2, 2],
            stats::var(series("a")) / n + stats::var(series("c")) / n)
})

test_that("the covariance is positive definite so the EnKF can factor it", {
  out <- period_mean_contrast(fake_series_obs(), "SOC", control = "c")
  expect_true(isSymmetric(unname(out$Sigma)))
  expect_gt(min(eigen(out$Sigma, symmetric = TRUE, only.values = TRUE)$values), 0)
  expect_false(inherits(try(chol(out$Sigma), silent = TRUE), "try-error"))
})

test_that("shrinking to positive definiteness leaves the marginal variances alone", {
  S <- matrix(c(4, 2, -4,
                2, 1, -2,
                -4, -2, 4), 3, 3)          # rank 1, singular by construction
  out <- calibration:::.shrink_to_pd(S, label = "test")
  expect_equal(diag(out), diag(S))
  expect_gt(min(eigen(out, symmetric = TRUE, only.values = TRUE)$values), 0)
  # off-diagonals are damped toward zero, never sign flipped
  expect_true(all(sign(out[upper.tri(out)]) == sign(S[upper.tri(S)])))
  expect_true(all(abs(out[upper.tri(out)]) <= abs(S[upper.tri(S)])))
})

test_that("an unbalanced panel is refused rather than averaged", {
  obs <- fake_series_obs()
  drop <- obs$meta$treatment_id == "a" & obs$meta$obs_year == 2007
  obs$meta <- obs$meta[!drop, ]
  obs$y <- obs$y[obs$meta$slot]
  obs$Sigma <- obs$Sigma[obs$meta$slot, obs$meta$slot, drop = FALSE]
  expect_error(period_mean_contrast(obs, "SOC", control = "c"),
               "exactly one slot per treatment per year")
})

test_that("too short a period is refused, since the mean has no estimable error", {
  expect_error(
    period_mean_contrast(fake_series_obs(), "SOC", control = "c", years = 2005:2006),
    "needs at least"
  )
})

test_that("an absent control is an error naming what is present", {
  expect_error(period_mean_contrast(fake_series_obs(), "SOC", control = "nope"),
               "Present: ")
})

test_that("contrast_target pairs treatments by date and refuses unpaired dates", {
  meta <- tibble::tibble(
    slot = c("n__t__d1", "n__t__d2", "n__c__d1", "n__c__d2"),
    variable = "n2o", sitename = "s",
    treatment_id = c("t", "t", "c", "c"),
    obs_year = 2019L,
    min_date = c("2019-01-01", "2019-02-01", "2019-01-01", "2019-02-01"),
    max_date = c("2019-01-01", "2019-02-01", "2019-01-01", "2019-02-01"),
    units = "g ha-1 day-1", value = c(3, 5, 1, 4), var_obs = c(1, 1, 1, 1)
  )
  S <- diag(1, 4); dimnames(S) <- list(meta$slot, meta$slot)
  obs <- list(y = stats::setNames(meta$value, meta$slot), Sigma = S, meta = meta)

  ct <- contrast_target(obs, "n2o", treatment = "t", control = "c",
                        new_variable = "n2o_c")
  expect_equal(unname(ct$y), c(2, 1))
  # independent cells: variances add
  expect_equal(unname(diag(ct$Sigma)), c(2, 2))
  # the difference form records its contraction
  expect_equal(as.numeric(ct$transform %*% obs$y[colnames(ct$transform)]),
               as.numeric(ct$y))

  short <- subset_obs(obs, obs$meta$slot != "n__c__d2")
  expect_error(contrast_target(short, "n2o", "t", "c"), "cannot form a")
})

test_that("bind_obs stacks targets block diagonally and refuses duplicate slots", {
  obs <- fake_series_obs()
  a <- period_mean_contrast(obs, "SOC", control = "c", new_variable = "pm1")
  b <- period_mean_contrast(obs, "SOC", control = "c", new_variable = "pm2")
  both <- bind_obs(a, b)
  expect_equal(length(both$y), length(a$y) + length(b$y))
  # off blocks are zero, within blocks carried through
  expect_equal(unname(both$Sigma[a$meta$slot, b$meta$slot]),
               matrix(0, nrow(a$meta), nrow(b$meta)))
  expect_equal(unname(both$Sigma[a$meta$slot, a$meta$slot]), unname(a$Sigma))
  expect_error(bind_obs(a, a), "duplicate slot")
})

# the operator reads real model output, so these mock read.output and assert on
# the window it is asked for and on what happens at the window edge.

make_meta <- function(slot, treat, a, b, variable = "SOC_stock") {
  tibble::tibble(slot = slot, variable = variable, treatment_id = treat,
                 min_date = a, max_date = b)
}

test_that("each treatment is harvested over its own run window", {
  skip_if_not_installed("PEcAn.utils")
  out_root <- withr::local_tempdir()
  dir.create(file.path(out_root, "ENS-00001-early"))
  dir.create(file.path(out_root, "ENS-00001-late"))

  asked <- list()
  fake_read <- function(runid, outdir, start.year, end.year, variables, ...) {
    asked[[sub("^ENS-[0-9]+-", "", runid)]] <<- c(start.year, end.year)
    days <- seq(as.Date(paste0(start.year, "-01-01")),
                as.Date(paste0(end.year, "-12-31")), by = "day")
    data.frame(posix = days, TotSoilCarb = rep(start.year / 1000, length(days)))
  }
  testthat::local_mocked_bindings(read.output = fake_read, .package = "PEcAn.utils")

  meta <- rbind(
    make_meta("early_slot", "early", "2005-06-01", "2005-06-01"),
    make_meta("late_slot",  "late",  "2020-06-01", "2020-06-01")
  )
  win <- cbind(early = c(2005L, 2011L), late = c(2017L, 2023L))
  vm <- list(SOC_stock = list(model_var = "TotSoilCarb", from = "kg/m2",
                              to = "kg/m2"))

  G <- harvest_output_to_G(out_root, meta, vm, win)

  expect_equal(asked$early, c(2005L, 2011L))
  expect_equal(asked$late,  c(2017L, 2023L))          # not the first block's window
  expect_equal(unname(G[1, "early_slot"]), 2.005)
  expect_equal(unname(G[1, "late_slot"]),  2.017)
})

test_that("an observation outside the run window fails instead of returning a neighbor", {
  skip_if_not_installed("PEcAn.utils")
  out_root <- withr::local_tempdir()
  dir.create(file.path(out_root, "ENS-00001-site"))

  fake_read <- function(runid, outdir, start.year, end.year, variables, ...) {
    days <- seq(as.Date("2017-01-01"), as.Date("2023-12-31"), by = "day")
    data.frame(posix = days, TotSoilCarb = seq_along(days) / 1000)
  }
  testthat::local_mocked_bindings(read.output = fake_read, .package = "PEcAn.utils")

  win <- cbind(site = c(2017L, 2023L))
  vm <- list(SOC_stock = list(model_var = "TotSoilCarb", from = "kg/m2",
                              to = "kg/m2"))

  inside <- make_meta("in_slot", "site", "2020-06-01", "2020-06-01")
  expect_silent(harvest_output_to_G(out_root, inside, vm, win))

  # 2024 is past the run end: nearest-date substitution would answer with
  # 2023-12-31 and look clean
  outside <- make_meta("out_slot", "site", "2024-06-01", "2024-06-01")
  expect_error(harvest_output_to_G(out_root, outside, vm, win),
               "outside the")
})

test_that("apply_transform is the same linear map the observations went through", {
  obs <- fake_series_obs()
  out <- period_mean_contrast(obs, "SOC", control = "c")
  G <- rbind(obs$y, obs$y * 2)
  fitted <- apply_transform(G, out$transform)
  expect_equal(unname(fitted[1, ]), unname(out$y))
  expect_equal(colnames(fitted), out$meta$slot)
})

