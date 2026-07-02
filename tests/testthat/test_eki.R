test_that("run_eki recovers the linear gaussian posterior mean", {
  # identity forward, so the one step enkf update is the analytic kalman update:
  # posterior mean = m0 + C0 (C0 + Sig)^-1 (y - m0). check the ensemble mean lands
  # there within monte carlo error.
  set.seed(1)
  J <- 4000
  m0 <- c(2, -3)
  C0 <- diag(c(1, 2))
  U0 <- cbind(a = stats::rnorm(J, m0[1], sqrt(C0[1, 1])),
              b = stats::rnorm(J, m0[2], sqrt(C0[2, 2])))

  y <- c(s1 = 1, s2 = 1)
  Sig <- diag(c(0.5, 0.5))
  dimnames(Sig) <- list(names(y), names(y))
  fwd <- function(U, itr) {
    G <- U
    colnames(G) <- names(y)
    G
  }

  res <- run_eki(y, U0, fwd, Sig, n_itr = 1)

  K <- C0 %*% solve(C0 + Sig)
  post_mean <- m0 + as.numeric(K %*% (y - m0))
  expect_equal(as.numeric(colMeans(res$U)), post_mean, tolerance = 0.1)
})

test_that("run_eki fails loud on misaligned forward output", {
  y <- c(s1 = 1, s2 = 2)
  Sig <- diag(2)
  dimnames(Sig) <- list(names(y), names(y))
  U0 <- cbind(a = stats::rnorm(20))
  bad_fwd <- function(U, itr) {
    G <- cbind(U, U)
    colnames(G) <- c("s1", "wrong")
    G
  }
  expect_error(run_eki(y, U0, bad_fwd, Sig, n_itr = 1))
})
