# scoring metrics for a calibration run: per iteration fit of the prediction
# ensemble against the observations (rmse, bias, coverage, interval width, CRPS)
# and the prior -> posterior parameter shift. pure computation, no plotting.

##' empirical continuous ranked probability score for one ensemble vs one obs.
##' CRPS = mean|x - o| - 0.5 mean|x - x'|, the sample estimator over the ensemble.
##' @keywords internal
crps_sample <- function(ens, obs) {
  J <- length(ens)
  mean(abs(ens - obs)) - sum(abs(outer(ens, ens, "-"))) / (2 * J^2)
}

##' @title Fit scores for one iteration's prediction matrix
##' @name score_iteration
##' @author Akash BV
##'
##' @description Scores a J x P prediction ensemble G against the observations in
##' meta: RMSE and bias of the ensemble mean, coverage and mean width of the 90%
##' band, and the mean CRPS. Columns of G are matched to observations by slot.
##'
##' @param G matrix (J x P), columns named by observation slot.
##' @param meta observation meta (slot, value = obs mean).
##' @return one row tibble: rmse, bias, coverage, mean_width, crps.
##' @export
score_iteration <- function(G, meta) {
  G <- G[, meta$slot, drop = FALSE]
  m   <- colMeans(G)
  q05 <- apply(G, 2, stats::quantile, 0.05)
  q95 <- apply(G, 2, stats::quantile, 0.95)
  obs <- meta$value
  crps <- mean(vapply(seq_along(obs), function(j) crps_sample(G[, j], obs[j]),
                      numeric(1)))
  tibble::tibble(
    rmse       = sqrt(mean((m - obs)^2)),
    bias       = mean(m - obs),
    coverage   = mean(obs >= q05 & obs <= q95),
    mean_width = mean(q95 - q05),
    crps       = crps
  )
}

##' @title Per iteration score table
##' @name score_table
##' @author Akash BV
##' @param G_list named list (e.g. iteration 1, ...) of prediction matrices.
##' @param meta observation meta.
##' @return tibble of score_iteration() rows, one per named element.
##' @export
score_table <- function(G_list, meta) {
  dplyr::bind_rows(lapply(names(G_list), function(nm) {
    dplyr::mutate(score_iteration(G_list[[nm]], meta), iteration = nm, .before = 1)
  }))
}

##' @title Prior to posterior parameter shift and variance reduction
##' @name param_shift
##' @author Akash BV
##' @param U_prior,U_post matrices (J x D) with the same columns.
##' @return tibble: per parameter prior/posterior mean and sd, the shift in prior
##'   sd units, and the fractional variance reduction.
##' @export
param_shift <- function(U_prior, U_post) {
  tibble::tibble(
    param      = colnames(U_prior),
    prior_mean = colMeans(U_prior),
    prior_sd   = apply(U_prior, 2, stats::sd),
    post_mean  = colMeans(U_post),
    post_sd    = apply(U_post, 2, stats::sd)
  ) |>
    dplyr::mutate(
      shift_sd      = (post_mean - prior_mean) / prior_sd,
      var_reduction = 1 - (post_sd^2 / prior_sd^2)
    )
}
