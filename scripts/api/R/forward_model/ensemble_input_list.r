# forward_model/ensemble_input_list.r


#' Construct EnsembleModelInput in list format
#' 
#' Constructs an object of class \code{EnsembleInputList}, which represents
#' an \code{EnsembleInput} as a list of \code{ModelInput} objects.
#' 
#' @details
#' The model inputs list is accessed via \code{x$inputs}. The field \code{x$metadata}
#' can be used to store metadata related to the ensemble (input/run-specific 
#' metadata should instead be stored in the \code{metadata} field of the 
#' \code{ModelInput} objects). If the \code{inputs} list is named, these names
#' will be interpreted as run IDs associated with each input/run. Default 
#' run IDs of the form \code{run_1, run_2, ...} will be defined otherwise.
#' \code{EnsembleInputList} objects inherit from \code{EnsembleInput}.
#'
#' @param inputs A list of \code{ModelInput} objects, one per run.
#' @param metadata A named list, or empty list.
#' 
#' @returns An object of class \code{EnsembleInputList}, inheriting from 
#'  \code{EnsembleInput}.
#'
#' @author Andrew Roberts
#' @export
EnsembleInput.list <- function(inputs, metadata=list(), ...) {
  
  x <- .new_ensemble_input_list(inputs, metadata)
  validate_ensemble_input_list(x)
  
  return(x)
}


#' Internal constructor for EnsembleInputList
#' 
#' Instantiates an \code{EnsembleInputList} object. No validation is done in 
#' this function. See \code{\link{EnsembleInput.list}} for the public interface.
#' 
#' @param inputs A list of \code{ModelInput} objects, one per run.
#' @param metadata A named list, or empty list.
#' 
#' @returns An object of class \code{EnsembleInputList}, inheriting from 
#'  \code{EnsembleInput}.
#' 
#' @seealso \code{\link{EnsembleInput}}
#' @author Andrew Roberts
.new_ensemble_input_list <- function(inputs, metadata) {
  
  # Set default run IDs if not provided.
  if(is.null(names(inputs))) {
    names(inputs) <- paste0("run_", as.character(seq_along(inputs)))
  }
  
  x <- structure(list(inputs=inputs, metadata=metadata),
                 class=c("EnsembleInputList", "EnsembleInput"))
  return(x)
}


#' Check if object inherits from \code{EnsembleInputList}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{EnsembleInputList}.
#' 
#' @author Andrew Roberts
#' @export
is_ensemble_input_list <- function(x) {
  is_ensemble_input(x) && inherits(x, "EnsembleInputList")
}


#' Validate an EnsembleInputList
#'
#' Validates the general structure of a \code{EnsembleInputList} object. 
#'
#' @details
#' Must have elements \code{inputs} and \code{metadata}. Both of these must
#' be named lists, or empty lists. All elements of \code{inputs} must be of 
#' type \cpde{ModelInput}.
#'
#' @param x An object.
#' @return Invisibly returns \code{TRUE} if validation tests are passed, 
#'  or throws an error if invalid.
#'  
#' @author Andrew Roberts
#' @export
validate_ensemble_input_list <- function(x) {
  if(!is_ensemble_input_list(x)) {
    stop("`x` is not an `EnsembleInputList` object.")
  }
  
  if(!("inputs" %in% names(x))) {
    stop("`EnsembleInputList$inputs` list is missing.")
  }
  
  if(!("metadata" %in% names(x))) {
    stop("`EnsembleInputList$metadata` list is missing.")
  }
  
  if(!is_named_or_empty_list(x$inputs, check_unique_names=TRUE)) {
    stop("EnsembleInputList$inputs must be a named list or empty list.")
  }
  
  if(!is_named_or_empty_list(x$metadata, check_unique_names=TRUE)) {
    stop("EnsembleInputList$metadata must be a named list or empty list.")
  }
  
  if(!all(vapply(x$inputs, is_model_input, logical(1)))) {
    stop("`EnsembleInputList$inputs` list contains element(s) not of class `ModelInput`.")
  }
  
  invisible(TRUE)
}


#' Convert an EnsembleInput to list format
#'
#' Converts an \code{EnsembleInput} object (e.g., in table or broadcast format)
#' into an \code{EnsembleInputList} object. The result will still inherit
#' from \code{EnsembleInput}.
#'
#' @param An \code{EnsembleInput}
#' @param ... Additional arguments to be used by methods.
#' 
#' @returns An \code{EnsembleInputList} object.
#' 
#' @author Andrew Roberts
#' @export
as_ensemble_input_list <- function(x, ...) {
  UseMethod("as_ensemble_input_list")
}


#' @export
as_ensemble_input_list.default <- function(x, ...) {
  raise_default_method_error(x, "as_ensemble_input_list")
}


#' Identity function - input is already an \code{EnsembleInputList}.
#' @export
as_ensemble_input_list.EnsembleInputList <- function(x, ...) {
  x
}


#' Return character vector of run IDs
#'
#' See \code{\link{run_ids}}
#'
#' @param An \code{EnsembleInputList}
#' @param ... Not used
#' 
#' @return A character vector of run IDs of length \code{n_runs(x)}.
#' @seealso \code{\link{run_ids}}
#' 
#' @author Andrew Roberts
#' @export
run_ids.EnsembleInputList <- function(x, ...) {
  names(x$inputs)
}


#' Get input slot names
#'
#' Returns the names of slots (input fields) present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputList} object.
#' @param unique_only Logical; if \code{TRUE} (default), returns only the
#'   unique set of slot names across runs. If \code{FALSE}, returns
#'   per-run slot names (a list).
#' @param ... Not used.
#'
#' @return A character vector of slot names if \code{unique_only = TRUE},
#'   otherwise a list of character vectors (per run).
#' @seealso \code{\link{slot_names}}, \code{\link{slot_names.ModelInput}}
#'   
#' @author Andrew Roberts
#' @export
slot_names.EnsembleInputList <- function(x, unique_only=TRUE, ...) {
  slot_names_per_run <- lapply(x$inputs, slot_names)
  
  if(unique_only) unique(unlist(slot_names_per_run, use.names=FALSE)) 
  else slot_names_per_run
}


#' Get metadata names
#'
#' Returns the names of metadata fields present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputList} object.
#' @param unique_only Logical; if \code{TRUE} (default), returns only the
#'   unique set of metadata names across runs. If \code{FALSE}, returns
#'   per-run metadata names (a list).
#' @param ... Not used.
#'
#' @return A character vector of metadata names if \code{unique_only = TRUE},
#'   otherwise a list of character vectors (per run). Returns character(0)
#'   in the absence of metadata.
#' @seealso \code{\link{metadata_names}}, \code{\link{metadata_names.ModelInput}}
#'   
#' @author Andrew Roberts
#' @export
metadata_names.EnsembleInputList <- function(x, unique_only=TRUE, ...) {
  metadata_names_per_run <- lapply(x$inputs, metadata_names)
  
  if(unique_only) unique(unlist(metadata_names_per_run, use.names=FALSE)) 
  else metadata_names_per_run
}


#' Get ModelInput for Specific Run from EnsembleInputList
#'
#' Returns the \code{ModelInput} object for run identified by the specified
#' \code{run_id}. 
#'
#' @param x An \code{EnsembleInputList}
#' @param run_id character(1), the run ID.
#' @param ... Further arguments passed to methods.
#'
#' @return The \code{ModelInput} for the selected run. Throws error if 
#'  \code{run_id} is not found.
#' 
#' @author Andrew Roberts
#' @export
get_run_input.EnsembleInputList <- function(x, run_id, ...) {
  stopifnot(is_character_scalar(run_id))
  
  model_input <- x$inputs[[run_id]]
  
  if(is.null(model_input)) raise_run_id_not_found_error(run_id)
  else model_input
}


#' Concatenate two EnsembleInputList objects
#'
#' Currently this drops ensemble metadata, and defines new run IDs.
#'
#' @param x,y \code{EnsembleInputList} objects
#' @returns Concatenated \code{EnsembleInputList}
#' 
#' @author Andrew Roberts
.concat_ensemble_input_lists <- function(x, y) {

  new_input_list <- c(x$inputs, y$inputs)
  names(new_input_list) <- NULL # New run IDs will be created.
  
  EnsembleInput(new_input_list)
}

