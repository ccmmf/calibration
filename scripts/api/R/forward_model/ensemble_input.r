# forward_model/ensemble_input.r


# Constants: prefixes used to mark values as model input slots or metadata.
INPUT_PREFIX <- "input_"
METADATA_PREFIX <- "metadata_"

#' Base class for ensemble model input
#'
#' The base parent class for \code{EnsembleInput} objects. Subclasses include:
#' - \code{EnsembleInputList}
#' - \code{EnsembleInputTable}
#' - \code{EnsembleInputBroadcast}
#'
#' @details
#' An \code{EnsembleInput} is simply an ordered collection of \code{ModelInput}
#' objects, with run IDs defined for each run. Optionally, metadata related
#' to the ensemble as a whole can also be stored (it is recommended to store
#' run-dependent metadata in the \code{ModelInput} objects themselves). The
#' \code{EnsembleInput()} constructor is a generic that will dispatch to either
#' \code{EnsembleInput.EnsembleInputList()}, 
#' \code{EnsembleInput.EnsembleInputTable()}, or
#' \code{EnsembleInput.EnsembleInputBroadcast()} depending on the input type.
#' 
#'
#' @param x An object that can be used to define an \code{EnsembleInput}.
#' @return An \code{EnsembleInput} object.
#' 
#' @seealso \code{\link{EnsembleInput.EnsembleInputList()}},
#'  \code{\link{EnsembleInput.EnsembleInputTable()}},
#'  \code{\link{EnsembleInput.EnsembleInputBroadcast()}}
#' 
#' @author Andrew Roberts
#' @export
EnsembleInput <- function(x, ...) {
  UseMethod("EnsembleInput")
}


#' @export
EnsembleInput.default <- function(x, ...) {
  raise_default_method_error(x, "EnsembleInput")
}


#' Check if object inherits from \code{EnsembleInput}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{EnsembleInput}.
#' 
#' @seealso \code{\link{EnsembleInput}}
#' @author Andrew Roberts
#' @export
is_ensemble_input <- function(x) {
  inherits(x, "EnsembleInput")
}


#' Throw error if object is not \code{EnsembleInput}
#' 
#' @param x An object
#' @returns Invisibly returns \code{TRUE} if \code{x} is an \code{EnsembleInput}.
#'  Otherwise throws an error.
#' 
#' @seealso \code{\link{EnsembleInput}}
#' @author Andrew Roberts
#' @export
check_ensemble_input_type <- function(x) {
  if (!is_ensemble_input(x)) stop("`x` is not an EnsembleInput object.")
  
  invisible(TRUE)
}


#' Return slot names of an EnsembleInput
#'
#' Returns the names of slots (input fields) present in the \code{ModelInput}
#' objects making up the ensemble run. The individual inputs may have different
#' slot names. By default, this method returns the union of all slot names
#' (i.e., the unique set of slot names over all \code{ModelInput}s). If 
#' \code{unique_only = FALSE} then returns a list of the slot names of each
#' individual \code{ModelInput} object.
#'
#' @param x An code{EnsembleInput} object.
#' @param unique_only Logical; if \code{TRUE} (default), returns only the
#'   unique set of slot names across runs. If \code{FALSE}, returns a list of 
#'   length \code{n_runs(x)} containing the slot names for each model input.
#' @param ... Not used.
#'
#' @return A character vector of slot names if \code{unique_only = TRUE},
#'   otherwise a list of character vectors (per run/input).
#' @seealso \code{\link{input_keys.ModelInput}}
#'   
#' @author Andrew Roberts
#' @export
input_keys.EnsembleInput <- function(x, unique_only=TRUE, ...) {
  input_keys_per_run <- lapply(as_ensemble_input_list(x)$inputs, input_keys)
  
  if(unique_only) unique(unlist(input_keys_per_run, use.names=FALSE)) 
  else input_keys_per_run
}


#' Analogous to \code{input_keys.EnsembleInput}, but for metadata leaves.
#' @export
metadata_keys.EnsembleInput <- function(x, unique_only=TRUE, ...) {
  metadata_keys_per_run <- lapply(as_ensemble_input_list(x)$inputs, metadata_keys)
  
  if(unique_only) unique(unlist(metadata_keys_per_run, use.names=FALSE)) 
  else metadata_keys_per_run
}


#' Run IDs Generic
#'
#' Returns a character vector of length equal to the number of runs, where each
#' value is the run ID for the respective run. Since each run is defined by 
#' a particular model input, then these run IDs can also be thought of as 
#' "model input IDs".
#'
#' @param x An \code{EnsembleInput} object.
#' @param ... Further arguments passed to methods.
#'
#' @return A character vector of run IDs of length \code{n_runs(x)}.
#' 
#' @author Andrew Roberts
#' @export
run_ids <- function(x, ...) {
  UseMethod("run_ids")
}


#' @export
run_ids.default <- function(x, ...) {
  raise_default_method_error(x, "run_ids")
}


#' Return number of slots in an EnsembleInput
#'
#' Returns the number of slots (input fields) present in an \code{EnsembleInput}
#' object. 
#' 
#' @details
#' As the model inputs comprising \code{EnsembleInput} can contain varying
#' numbers of slots, the number of slots of an \code{EnsembleInput} is defined
#' as the number of elements in the union of all model input slots (i.e., 
#' the total number of unique slots). This also corresponds to the number of
#' "slot columns" in an \code{\link{EnsembleInputTable}}.
#' However, note that \code{EnsembleInputTable} will always have more columns
#' than \code{n_inputs(x)} due to the presence of the \code{run_id} column and
#' possibly additional metadata columns.
#'
#' @param x An \code{EnsembleInput} object.
#' @param ... Not used.
#'
#' @return Integer, number of slots.
#' 
#' @author Andrew Roberts
#' @export
n_inputs.EnsembleInput <- function(x, ...) {
  length(input_keys(x))
}


#' Return total number of inputs (i.e., runs) in an EnsembleInput
#'
#' Returns the number of model inputs comprising an \code{EnsembleInput}
#' object. Each model input defines a "run"; hence, this is also the total
#' number of runs.
#'
#' @param x An \code{EnsembleInput} object.
#' @param ... Not used.
#'
#' @return Integer, number of runs. Throws error if \code{x} is not an 
#'  \code{EnsembleInput}.
#' 
#' @author Andrew Roberts
#' @export
n_runs <- function(x) {
  check_ensemble_input_type(x)
  length(run_ids(x))
}


#' Generic Getter for ModelInput for Specific Run 
#'
#' Returns the \code{ModelInput} object for run identified by the specified
#' \code{run_id}. 
#'
#' @param x An \code{EnsembleInput}
#' @param run_id character(1), the run ID.
#' @param ... Further arguments passed to methods.
#'
#' @return The \code{ModelInput} for the selected run. Throws error if 
#'  \code{run_id} is not found.
#' 
#' @author Andrew Roberts
#' @export
get_run_input <- function(x, run_id, ...) {
  UseMethod("get_run_input")
}


#' @export
get_run_input.default <- function(x, run_id, ...) {
  raise_default_method_error(x, "get_run_input")
}


#' Append two or more EnsembleInput 
#'
#' Returns the \code{EnsembleInput} object defined by concatenating
#' the runs specified by \code{...}. The total number of runs of the new object
#' will be the sum of the runs of the objects being concatenated.
#'
#' @param ... \code{EnsembleInput} objects.
#' 
#' @details When concatenating \code{EnsembleInput}s no attempt is made to
#' identify shared slot values across the different ensembles. This is primarily
#' relevant for \code{EnsembleInputBroadcast}, which is the only representation
#' that explicitly stores the unique set of values for each slot. Therefore,
#' even if there are shared values across ensembles, they will be treated as
#' distinct values in the concatenated \code{EnsembleInput}. This avoids
#' the challenges of comparing structured objects, numerical imprecision, etc.
#'
#' @returns The concatenated \code{EnsembleInput} objects. The total number of 
#' runs of the new object will be the sum of the runs of the objects being 
#' concatenated. The slot names will be the union of the slot names of the
#' individual objects.
#' 
#' @author Andrew Roberts
#' @export
concatenate_ensemble_inputs <- function(..., output_class="EnsembleInputList") {

  assert_that(output_class %in% c("EnsembleInputBroadcast", 
                                  "EnsembleInputTable", 
                                  "EnsembleInputList"))
  
  l <- list(...)
  
  # Ensure all objects are EnsembleInputs.
  is_valid_ens_input <- vapply(l, is_ensemble_input, logical(1))
  if(!all(is_valid_ens_input)) {
    stop("`concatenate_ensemble_inputs()` can only concatenate objects of type EnsembleInput.")
  }
  
  # Convert all objects to the same type.
  convert_class <- if(output_class == "EnsembleInputBroadcast") as_ensemble_input_broadcast
                   else if(output_class == "EnsembleInputTable") as_ensemble_input_table
                   else as_ensemble_input_list
  l <- lapply(l, convert_class)
  
  # Concatenate.
  concat_func <- if(output_class == "EnsembleInputBroadcast") .concat_ensemble_input_broadcasts
                 else if(output_class == "EnsembleInputTable") .concat_ensemble_input_tables
                 else .concat_ensemble_input_lists
  
  Reduce(concat_func, l)
}


#' Summarize an EnsembleInput
#'
#' Provide a unified summary of an \code{EnsembleInput} object, irrespective of
#' of the underlying data structure (list, table, broadcast). The convention 
#' us for \code{summarize()} to provide a data structure independent summary,
#' while \code{print()} may differ based on the particular sub-class.
#'
#' @returns Invisibly returns \code{x}. Prints a summary to standard output.
#' @author Andrew Roberts
#' @export
summary.EnsembleInput <- function(x, ...) {
  cat("<", class(x)[1], ">\n", sep="")
  cat(" Number of runs:", n_runs(x), "\n")
  cat(" Number of slots:", n_inputs(x), "\n")
  
  slot_nm <- input_keys(x)
  if(length(slot_nm) == 0L) {
    cat("  (no slots)\n")
  } else {
    cat(" slots:", paste(slot_nm, collapse = ", "), "\n")
  }
  
  invisible(x)
}


#' Run Model at Each Model Input in Ensemble
#'
#' Calls  \code{run_model(model_obj, model_input, ...)} for each \code{ModelInput}
#' in \code{EnsembleInput}. Returns a list of the results of each call.
#'
#' @details
#' \code{run_model(model_obj, model_input, ...)} is the run model generic;
#' specific methods are dispatched based on the class of \code{model_obj}, which
#' encodes the model.
#' 
#' @param ens_input An \code{EnsembleInput} object.
#' @param model_obj An R object, for which a \code{run_model()} method is defined.
#' @param ... Additional arguments passed to \code{run_model()}.
#' 
#' @returns list of length \code{n_runs(ens_input)}. The order is determined
#'  by the order of \code{run_ids(ens_input)}, and these run IDs are assigned
#'  as the names attribute of the returned list. Element \code{i} of the
#'  returned list contains the output of the call 
#'  \code{run_model(model_obj, get_run_input(ens_input, run_ids(ens_input)[i]), ...)}.
#'  
#' @seealso \code{\link{lapply_ensemble_input}}, \code{\link{run_model}}
#'
#' @author Andrew Roberts
#' @export
lapply_model_ensemble_run <- function(ens_input, model_obj, ...) {
  
  check_ensemble_input_type(ens_input)
  
  model_func <- function(model_input, ...) run_model(model_obj, model_input, ...)
  lapply_ensemble_input(ens_input, model_func, ...)
}


#' Apply Function to Each Model Input in Ensemble
#'
#' Given a function \code{func} with signature \code{func(model_input, ...)},
#' applies the function to each \code{ModelInput} object in the 
#' \code{EnsembleInput} and returns the results of these calls in a list of
#' length \code{n_runs(ens_input)}.
#' 
#' @returns list of length \code{n_runs(ens_input)}. The order is determined
#'  by the order of \code{run_ids(ens_input)}, and these run IDs are assigned
#'  as the names attribute of the returned list. Element \code{i} of the
#'  returned list contains the output of the call 
#'  \code{func(get_run_input(ens_input, run_ids(ens_input)[i]), ...)}.
#' @seealso \code{\link{lapply_model_ensemble_run}}
#'
#' @author Andrew Roberts
#' @export
lapply_ensemble_input <- function(ens_input, func, ...) {
  
  check_ensemble_input_type(ens_input)
  
  apply_func_to_run <- function(run_id) {
    model_input <- get_run_input(ens_input, run_id)
    func(model_input, ...)
  }
  
  r_ids <- run_ids(ens_input)
  results <- lapply(r_ids, apply_func_to_run)
  names(results) <- r_ids
  
  return(results)
}


#' Error when a requested run ID is not present
#' 
#' @author Andrew Roberts
raise_run_id_not_found_error <- function(run_id) {
  stop("Run ID `", run_id, "` not found in EnsembleInput.")
}




