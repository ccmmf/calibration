test_that("transport maps round trip for each support", {
  dl <- list(
    a = list(param_name = "a", len = 1L, constraint = c(0, Inf)),    # positive
    b = list(param_name = "b", len = 1L, constraint = c(-Inf, Inf)), # unbounded
    c = list(param_name = "c", len = 1L, constraint = c(1, 3)),      # double bounded
    d = list(param_name = "d", len = 1L, constraint = c(-Inf, 5))    # upper bounded
  )
  pm <- get_par_map_funcs(dl)

  set.seed(1)
  U <- cbind(a = stats::rgamma(50, 2), b = stats::rnorm(50),
             c = stats::runif(50, 1, 3), d = 5 - stats::rgamma(50, 2))
  back <- pm$inv(pm$fwd(U))

  for (nm in colnames(U)) {
    expect_equal(as.numeric(back[, nm]), as.numeric(U[, nm]), tolerance = 1e-8)
  }
})

test_that("inverse map attaches a finite log jacobian", {
  dl <- list(a = list(param_name = "a", len = 1L, constraint = c(0, 1)))
  pm <- get_par_map_funcs(dl)
  U <- cbind(a = stats::runif(10, 0, 1))
  ldj <- attr(pm$inv(pm$fwd(U)), "log_det_J")
  expect_length(ldj, nrow(U))
  expect_true(all(is.finite(ldj)))
})
