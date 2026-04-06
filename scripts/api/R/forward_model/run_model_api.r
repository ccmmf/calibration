# forward_model/run_model_api.r

# Contains the generics `run_model()` and `run_model_ensemble()`, which define
# consistent interfaces for, respectively (1) mapping from inputs to outputs
# via some operation; and (2) applying that same operation to a set of 
# different inputs and collecting the resulting set of outputs. A default
# method for `run_model_ensemble()` is defined, which simply executes the 
# model runs serially and returns the results in a list. This default can be
# overwritten for more complicated ensemble execution (e.g., in parallel).
#
# This file also contains the method `run_model.function()` which provides an
# interface when the action of the model is encoded by a basic R function. 
# For modeling frameworks with more complicated run mechanisms, alternative 
# methods can be defined for the `run_model()` and `run_model_ensemble()` generics.

#' Run Model Generic
#' 
#' A generic API for running a model, which implies mapping inputs 
#' \code{model_input} to some output value. The object \code{model_obj} encodes
#' the mechanism for performing this mapping.
#' 
#' @param model_obj An R object representing the model.
#' @param model_input A \code{ModelInput} object.
#' @param ... Other arguments passed to methods.
#' 
#' @returns An R object that represents the model output.
#' @seealso \code{\link{run_model.function}},  \code{\link{ModelInput}}
#' 
#' @note All \code{run_model()} methods should match the first two argument
#'  names exactly.
#'
#' @author Andrew Roberts
#' @export
run_model <- function(model_obj, model_input, ...) {
  UseMethod("run_model")
}


#' Run Model Ensemble Generic
#' 
#' A generic API for running a model at a set of \code{n} inputs, resulting
#' in a set of \code{n} outputs. We refer to this as a model ensemble run,
#' though it can equivalently be thought of as a vectorization of a model.
#' 
#' @param model_obj An R object encoding the model/forward map.
#' @param ens_input An \code{EnsembleInput} object.
#' @param ... Other arguments passed to methods.
#' 
#' @returns An R object that represents the collection of model outputs.
#' @seealso \code{\link{run_model_ensemble.default}}, \code{\link{EnsembleInput}}
#' 
#' @note All \code{run_model_ensemble()} methods should match the first two 
#'  argument names exactly.
#'
#' @author Andrew Roberts
#' @export
run_model_ensemble <- function(model_obj, ens_input, ...) {
  UseMethod("run_model_ensemble")
}


#' @export
run_model.default <- function(model_obj, model_input, ...) {
  raise_default_method_error(x, "run_model")
}


#' Run Model Ensemble Default
#' 
#' Defaults to serial evaluation. Returns a list of length \code{n_runs(ens_input)} 
#' containing the results of each model call.
#'
#' @param model_obj An R object encoding the model/forward map.
#' @param ens_input An \code{EnsembleInput} object.
#' @param ... Other arguments passed to \code{run_model(model_obj, model_input, ...)}.
#' 
#' @returns list of length \code{n_runs(ens_input)}. The order is determined
#'  by the order of \code{run_ids(ens_input)}, and these run IDs are assigned
#'  as the names attribute of the returned list. Element \code{i} of the
#'  returned list contains the output of the call 
#'  \code{run_model(model_obj, get_run_input(ens_input, run_ids(ens_input)[i]), ...)}.
#'
#' @seealso \code{\link{lapply_model_ensemble_run}}
#'
#' @export
run_model_ensemble.default <- function(model_obj, ens_input, ...) {
  
  lapply_model_ensemble_run(ens_input, model_obj, ...)

}


#' Run Model Represented by R Function
#'
#' Runs a model that is encoded by a simple R function with signature
#' \code{model_func(model_input, ...)}.
#'
#' @param model_func function, with signature \code{model_func(model_input, ...)}.
#' @param model_input A \code{ModelInput} object.
#' @param ... Other arguments passed to \code{model_func()}.
#'
#' @returns The value returned by \code{model_func(model_input, ...)}.
#' 
#' @author Andrew Roberts
#' @export
run_model.function <- function(model_func, model_input, ...) {
  model_func(model_input, ...)
}
