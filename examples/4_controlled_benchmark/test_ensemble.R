source("examples/4_controlled_benchmark/ensemble_summary.R")
testthat::test_that("aggregation precedes directional fractions", {
  x <- data.frame(comparison = "cover", group = "annual", site_id = rep(c("a", "b"), 2),
                  member_id = rep(1:2, each = 2), effect = c(1, -3, 3, -1))
  s <- summarize_paired_ensemble(x)
  testthat::expect_equal(s$fraction_increase, 0.5)
  testthat::expect_equal(s$median, 0)
  testthat::expect_error(summarize_paired_ensemble(x[-1, ]), "different location")
  testthat::expect_error(summarize_paired_ensemble(rbind(x, x[1, ])), "Duplicate")
  missing_id <- x
  missing_id$site_id[1] <- NA_character_
  testthat::expect_error(summarize_paired_ensemble(missing_id), "Missing ensemble identities")
  other <- x
  other$comparison <- "tillage"
  other$member_id <- other$member_id + 1
  testthat::expect_error(summarize_paired_ensemble(rbind(x, other)), "different member identities")
  x$effect[1] <- NA_real_
  testthat::expect_error(summarize_paired_ensemble(x), "Nonfinite")
})
