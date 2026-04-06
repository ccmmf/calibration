# mcmc/mcmc_kernels.r

MetropolisProposal <- R6::R6Class(
  classname = "MetropolisProposal",
  public = list(
    initialize = function(...) {
      stop("Abstract base MetropolisProposal class cannot be instantiated.")
    }, 
    
    propose = function(state) {
      stop("`propose()` must be implemented by MetropolisProposal subclasses.")
    }, 
    
    log_density = function(old_state, new_state) {
      stop("`log_density()` must be implemented by MetropolisProposal subclasses.")
    }
  )
)


#' A basic Metropolis-Hastings kernel for MCMC
#'
#' An R6 class implementing a random walk Metropolis-Hastings (MH) kernel, 
#' using a symmetric multivariate normal proposal. The kernel is defined 
#' by specifying a proposal covariance matrix \eqn{C}. Given the current 
#' state \eqn{x}, a new state is proposed as 
#' \deqn{\tilde{x} \sim \mathcal{N}(x, C)}. With probability 
#' \deqn{\alpha(x, \tilde{x}) = \min[1, \exp(\ell(\tilde{x} - x))]} the
#' state \eqn{\tilde{x}} is returned; otherwise \eqn{x} is returned. 
#'
#' @section Public fields:
#' \describe{
#'   \item{\code{L}}{The upper-triangular Cholesky factor of the proposal covariance matrix.}
#'   \item{\code{d}}{Dimension of the state space (\code{ncol(L)}).}
#' }
#'
#' @section Public methods:
#' \describe{
#'   \item{\code{initialize(cov)}}{Constructs the kernel with the given covariance matrix.}
#'   \item{\code{step(state)}}{Samples the new state.}
#' }
#'
#' @examples
#' # 2D example
#' cov <- matrix(c(1, 0.5, 0.5, 2), nrow = 2)
#' kernel <- MetropolisKernel$new(cov)
#' kernel$d <- 2
#' old_state <- c(0, 0)
#' new_state <- kernel$step(old_state)
#'
#' @seealso \code{\link{MarkovKernel}}
#'
#' @docType class
#' @name MetropolisKernel
MetropolisKernel <- R6::R6Class(
  classname = "MetropolisKernel",
  inherit = MarkovKernel,
  public = list(
    initialize = function(log_density, proposal) {
      self$log_density <- log_density
      self$proposal <- proposal
    }, 
    
    step = function(state) {
      proposed_state <- self$proposal$propose(state)
      
      # Target densities.
      log_p_current <- self$state_info$log_density
      if(is.null(log_p_current)) log_p_current <- self$log_density(state)
      log_p_proposed <- self$log_density(proposed_state)
      
      # Proposal densities.
      log_q_fwd <- self$proposal$log_density(state, proposed_state)
      log_q_back <- self$proposal$log_density(proposed_state, state)
      
      log_alpha = (log_p_proposed - log_p_current) + (log_q_back - log_q_fwd)
      
      if(log(runif()) < log_alpha) {
        self$state_info <- list(log_density=log_p_proposed)
        return(proposed_state)
      } else {
        return(state)
      }
    }
  )
)
