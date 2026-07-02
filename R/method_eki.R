# ensemble kalman inversion calibration method.
#
# compute_enkf_update / run_eki_step / run_eki are the update itself. the forward
# model is passed in as a closure, so this method knows nothing about the model or
# the data. calibrate_eki() is what calibrate() dispatches to for method "eki".

##' @title Calibrate by ensemble Kalman inversion
##' @name calibrate_eki
##' @author Meng Lai and Akash BV
##'
##' @description The EKI method behind calibrate(). Draws the initial ensemble
##' from the prior, builds the transport maps that carry the bounded parameters
##' into the unconstrained space the Kalman update assumes, and runs the tempered
##' inversion run_eki().
##'
##' @param obs,prior,forward,control see calibrate().
##' @return list with U (posterior ensemble, native space), U0 (prior ensemble),
##'   prior, obs, eki (the run_eki output), and control.
##' @keywords internal
calibrate_eki <- function(obs, prior, forward, control) {
  U0 <- sample_initial_ensemble(prior, control$n_particles, control$seed)
  par_map <- get_par_map_funcs(prior)
  res <- run_eki(
    y = obs$y, U = U0, fwd = forward, Sig = obs$Sigma,
    n_itr = control$n_iterations, par_map = par_map
  )
  list(U = res$U, U0 = U0, prior = prior, obs = obs, eki = res, control = control)
}

##' @title Ensemble Kalman analysis step update
##' @name compute_enkf_update
##' @author Meng Lai and Akash BV
##'
##' @description Evaluates the EnKF update U + C_uy C_y^-1 (y - Y) for the given
##' covariances via a Cholesky solve for stability. No sample moments are
##' estimated here; this only applies the update equation.
##'
##' @param U matrix (J, D): J ensemble members, D parameters.
##' @param y numeric vector length P: the observation being conditioned on.
##' @param Y matrix (J, P): ensemble of simulated (perturbed) observations.
##' @param C_uy matrix (D, P): parameter output cross-covariance.
##' @param C_y matrix (P, P): output covariance; optional if L_y is given.
##' @param L_y matrix (P, P): lower Cholesky factor of C_y; computed from C_y if NULL.
##' @return matrix (J, D): the updated ensemble.
##' @keywords internal
compute_enkf_update <- function(U, y, Y, C_uy, C_y = NULL, L_y = NULL) {
  stopifnot(!(is.null(C_y) && is.null(L_y)))
  if (is.null(L_y)) L_y <- t(chol(C_y))
  Y_diff <- add_vec_to_mat_rows(y, -Y)
  U + t(C_uy %*% backsolve(t(L_y), forwardsolve(L_y, t(Y_diff))))
}

##' @title One ensemble Kalman inversion iteration
##' @name run_eki_step
##' @author Meng Lai and Akash BV
##'
##' @description Estimates the sample moments of the current ensemble, perturbs
##' the observation as Y = G + eps with eps ~ N(0, Sig), and applies
##' compute_enkf_update(). Assumes the forward model has already run at U with
##' outputs G; parameter transforms are handled by run_eki(), not here.
##'
##' @param U matrix (J, D): current parameter ensemble.
##' @param y numeric vector length P: the observation.
##' @param G matrix (J, P): forward model outputs at U.
##' @param Sig matrix (P, P): Gaussian likelihood covariance.
##' @return list with the updated U plus the estimated moments and Cholesky factor.
##' @keywords internal
run_eki_step <- function(U, y, G, Sig) {
  m_u <- colMeans(U)
  m_y <- colMeans(G)

  C_u <- stats::cov(U)
  C_y <- stats::cov(G) + Sig
  C_uy <- stats::cov(U, G)
  L_y <- t(chol(C_y))

  P <- ncol(Sig)
  J <- nrow(U)
  eps <- matrix(stats::rnorm(P * J), nrow = J, ncol = P) %*% chol(Sig)
  Y <- G + eps

  U_updated <- compute_enkf_update(U, y, Y, C_uy, L_y = L_y)

  list(
    U = U_updated, G = G, m_u = m_u, m_y = m_y,
    C_u = C_u, C_y = C_y, L_y = L_y, C_uy = C_uy
  )
}

##' @title Run ensemble Kalman inversion with likelihood tempering
##' @name run_eki
##' @author Meng Lai and Akash BV
##'
##' @description Tempers the one-step update over n_itr iterations. Each iteration
##' evaluates the forward model, applies the EnKF update in unconstrained space
##' (if par_map is given), and maps back. The final ensemble approximates the
##' posterior p(u | y): exact for a linear-Gaussian problem, approximate
##' otherwise. The update combines columns positionally, so the forward output,
##' the observation, and the likelihood covariance are aligned by slot name up
##' front; a differently ordered forward output would otherwise condition each
##' observation on the wrong model output and yield a plausible but wrong
##' posterior with no error.
##'
##' @param y numeric vector length P: the observation.
##' @param U matrix (J, D): initial parameter ensemble (constrained space).
##' @param fwd function(U, itr) -> matrix (J, P): the forward model, vectorized
##'   over ensemble members (rows).
##' @param Sig matrix (P, P): Gaussian likelihood covariance.
##' @param n_itr integer: number of tempering iterations.
##' @param par_map list(fwd, inv) of transport maps from get_par_map_funcs(); if
##'   NULL the update runs in the native space.
##' @param G0 matrix (J, P): optional precomputed fwd(U) for the first iteration.
##' @return list with U (final ensemble, constrained space), par_map, eki_list
##'   (per iteration run_eki_step outputs), and G (last forward outputs).
##' @export
run_eki <- function(y, U, fwd, Sig, n_itr = 1L, par_map = NULL, G0 = NULL) {
  if (!is.null(names(y)) && !is.null(colnames(Sig))) {
    if (!identical(colnames(Sig), names(y))) {
      PEcAn.logger::logger.severe("Sig columns do not match the obs slot order")
    }
  }
  align_G <- function(G) {
    if (is.null(names(y)) || is.null(colnames(G))) return(G)
    if (!setequal(colnames(G), names(y))) {
      PEcAn.logger::logger.severe(
        "forward model output columns do not match the observation slots"
      )
    }
    G[, names(y), drop = FALSE]
  }

  eki_list <- vector("list", n_itr)
  G <- NULL
  for (k in seq_len(n_itr + 1L)) {
    if (k == 1L && !is.null(G0)) {
      G <- align_G(G0)
    } else {
      G <- align_G(fwd(U, k))
    }
    if (k == n_itr + 1L) break

    U_unbound <- if (!is.null(par_map)) par_map$fwd(U) else U
    Sig_scaled <- n_itr * Sig
    step <- run_eki_step(U = U_unbound, y = y, G = G, Sig = Sig_scaled)
    eki_list[[k]] <- step
    U <- if (!is.null(par_map)) par_map$inv(step$U) else step$U
  }
  list(U = U, par_map = par_map, eki_list = eki_list, G = G)
}
