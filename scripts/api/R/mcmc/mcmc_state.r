# mcmc/mcmc_state.r

#' Create a new MCMC state object
#'
#' A state object contains the current parameter values and cached
#' evaluations of expensive quantities like the log-density.
#'
#' @param params An R object (e.g., numeric vector) representing the state parameters.
#' @param log_density Numeric scalar giving the target log density evaluated at the parameters.
#'
#' @seealso \code{\link{run_mcmc_chain}}, \code{\link{MarkovKernel}}
#'
#' @return An object of class \code{MCMCState}.
#' @author Andrew Roberts
#' @export
make_state <- function(params, log_density=NULL) {
  structure(
    list(params=params, log_density=log_density),
    class = "MCMCState"
  )
}
