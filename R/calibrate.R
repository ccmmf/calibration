##' @title Calibrate model parameters against observations
##' @name calibrate
##' @author Akash BV
##'
##' @description Generic, method agnostic entry point for ensemble parameter
##' calibration. It holds nothing model-, site-, or variable specific - given an
##' observation target, a prior, and a forward model closure it dispatches to the
##' method named in `control`. A new method is added as a `calibrate_<method>()`
##' function plus one branch here; the observation, prior, and forward model
##' contracts do not change.
##'
##' @param obs observation target `list(y, Sigma, meta)` from `build_obs()`: `y` a
##'   named numeric vector of length P, `Sigma` its P x P covariance with row/col
##'   names matching `y`, `meta` the per-slot table used to align forward output.
##' @param prior a dist_list from the `prior_from_*()` constructors, one record per
##'   calibrated parameter carrying its distribution and support.
##' @param forward forward model closure `function(U, iteration)` returning a
##'   matrix (J particles x P slots) whose columns match `names(obs$y)`; the only
##'   model specific argument (see `make_forward_sipnet()`).
##' @param control a `calibration_control()` list selecting the method and its
##'   ensemble settings.
##' @return the method's result list; for every method it carries at least `U`,
##'   the posterior parameter ensemble in the model's native (constrained) space.
##' @export
calibrate <- function(obs, prior, forward, control = calibration_control()) {
  run <- switch(control$method,
    eki = calibrate_eki,
    PEcAn.logger::logger.severe(
      "calibration method '", control$method, "' is not supported"
    )
  )
  run(obs, prior, forward, control)
}
