##' @title Calibration control settings
##' @name calibration_control
##' @author Akash BV
##'
##' @description Control-list constructor for `calibrate()`: the method and its
##' ensemble settings collected in one place with documented defaults, rather than
##' threaded as loose arguments (cf. `SDA_control` in the PEcAn SDA module).
##'
##' @param method calibration method to dispatch to. Currently "eki".
##' @param n_particles ensemble size (number of parameter particles, J).
##' @param n_iterations number of tempering iterations the method takes.
##' @param seed integer RNG seed for the initial ensemble draw so a run is
##'   reproducible; NULL leaves the stream untouched.
##' @return a named list of control settings consumed by `calibrate()`.
##' @export
calibration_control <- function(method = "eki", n_particles = 50L,
                                n_iterations = 3L, seed = NULL) {
  list(
    method = method,
    n_particles = n_particles,
    n_iterations = n_iterations,
    seed = seed
  )
}
