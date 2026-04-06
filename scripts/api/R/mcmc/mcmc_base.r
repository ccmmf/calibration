# mcmc/mcmc_base.r

#' Run an MCMC Chain
#'
#' Runs a Markov chain Monte Carlo (MCMC) simulation for a specified number of 
#' iterations using a given kernel.
#'
#' The function executes an MCMC chain starting from an initial state, 
#' applying the provided kernel at each iteration. The user can supply a kernel
#' as a simple R function, or a \code{\link{MarkovKernel}} object. The latter 
#' case allows for kernel adaptation. No assumptions are made about the data
#' type of the state. The kernel simply takes the current state and returns
#' a new state, and the states are returned in a list.
#'
#' @param init_state The initial state of the Markov chain. Can be a numeric 
#'  vector or a more complex R object, depending on the model and kernel.
#' @param kernel A function or \code{MarkovKernel} object. If the former, must 
#'  accept the current state as an argument, and return the updated state.
#' @param n_iter Integer. The number of MCMC iterations to run.
#' @param adapt Logical (default \code{TRUE}). If \code{TRUE}, allows the kernel 
#'  to adapt during sampling after each step).
#'  This will not have an effect if the user-supplied kernel is a simple function.
#'
#' @return list with names \code{chain} and \code{info}. \code{chain} chains 
#'  a list of states visited by the chain, with one element per iteration. 
#'  \code{info} contains a list of auxiliary information associated with 
#'  each state, with one element per iteration.
#'
#' @examples
#' # Passing a kernel as a function:
#' # kernel <- function(x) x + rnorm(1)
#' # chain <- run_mcmc_chain(init_state=0, kernel=kernel, n_iter=1000, adapt=FALSE)
#' 
#' # Using a kernel object:
#' # log_dens <- function(x) dnorm(x, log=TRUE)
#' # kernel <- AdaptiveGaussMetropolisKernel$new(log_dens)
#' # chain <- run_mcmc_chain(init_state=0, kernel=kernel, n_iter=1000, adapt=TRUE)
#'
#' @seealso \code{\link{MarkovKernel}}, \code{\link{make_kernel}}
#' @author Andrew Roberts
#' @export
run_mcmc_chain <- function(init_state, kernel, n_iter, adapt=TRUE) {
  kernel <- make_kernel(kernel, info_fun)
  chain <- vector("list", n_iter)
  info <- vector("list", n_iter)
  state <- init_state
  
  for (i in seq_len(n_iter)) {
    state <- kernel$step(state)
    chain[[i]] <- state
    info[[i]] <- kernel$state_info # Cached info from previous step.
    if(adapt) kernel$update(state=state, iter=i)
  }
  
  return(list(chain=chain, info=info))
}
