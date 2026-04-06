# forward_model/model_wrappers.r

# ------------------------------------------------------------------------------
# wrap_partial_slot_batch()
#
# Wrapper that allows passing in batches of slot values in matrix format
# for a model ensemble run.
# ------------------------------------------------------------------------------


#' Generate a wrapper around \code{run_model_ensemble()} for batch inputs
#'
#' A model wrapper generator defined by fixing certain input slots. The wrapper
#' is defined so that batches of values are passed in for the free slots. 
#' This wrapper is thus defined purely for ensemble model runs, and has no
#' analog for single model runs.
#' 
#' @details
#' This wrapper takes an existing \code{EnsembleInputBroadcast}, and provides
#' the means for users to pass in batches of values in the \code{slots} field.
#' It is important to realize that the wrapper interface expects batches of
#' values of a pre-defined size to be passed in, rather than vectorizing over 
#' a single slot value. This means that the size and structure of the ensemble
#' run is completely determined when generating the wrapper, which can be 
#' convenient in that parallelization settings can be fixed in advance. The
#' batch size of the free slots is determined from the values in \code{default}. 
#' If multiple free slots are specified by \code{slot_names}, then the batch
#' sizes for these slots are required to be equal. Let \code{n} denote the 
#' batch size and \code{l1, ..., ls} denote the lengths of each free slot. The 
#' length of a slot is the number of scalar entries making up a single value.
#' The model wrapper is defined such that it expects an input matrix of shape
#' \code{(n, l1 + ... + ls)}, with columns ordered according to \code{slot_names}.
#' That is, the first \code{l1} columns correspond to \code{slot_names[1]}, the
#' next \code{l2} columns to \code{slot_names[2]}, and so on. At present, it
#' is required that the values in the free slots within \code{default} are 
#' stored in matrix format. There is no reason for this to be the case in the 
#' future; this can be generalized to any array-like values, in which case
#' the matrix input will simply have to be re-shaped before filling in the 
#' \code{default} template.
#' 
#' \code{output_operator} is an optional R function that is applied to the 
#' return value of \code{run_model_ensemble()}. The user must ensure that this
#' function is defined correctly with respect to the return value.
#' 
#' @param model_obj An R object representing the model.
#' @param default An \code{EnsembleInputBroadcast} object acting as a template for
#'  the ensemble run. The exact structure and number of runs can be inferred
#'  from this template. The model wrapper will simply update the values of the 
#'  free slots within this template.
#' @param slot_names \code{character}, vector of slot names for the free slots.
#' @param output_operator \code{function} or \code{NULL}. If provided, the
#'  model wrapper represents the composition of the \code{run_model_ensemble()}
#'  call with the \code{output_operator} function.
#' @param verbose \code{logical(1)}, if \code{TRUE} prints information about
#'  the wrapped model.
#' @param .fixed_args named list of additional arguments to `run_model_ensemble()`
#'  that are treated as immutable (fixed across all calls of model wrapper).
#' @param .dynamic_args named list of additional arguments to 
#'  `run_model_ensemble()` that are treated as mutable. In particular, the 
#'  values of this list must consist of symbols or quoted expressions. These 
#'  will be evaluated in the calling environment of the wrapped model, meaning
#'  that their values will vary based on the current state of the calling environment.
#' @param .arg_update_fn function or NULL. If a function, must be a pure function
#'  (no side effects), accept a named list of arguments to `run_model_ensemble()`, 
#'  and return a named list of (potentially modified) arguments. This may be useful 
#'  when some auxiliary arguments of the model should be updated dynamically based 
#'  on the current value of the dynamic arguments.
#'
#' @returns \code{function}, the wrapped model with signature 
#'  \code{function(input_mat, ...)}, where \code{input_mat} is a matrix of shape
#'  \code{(n, l1 + l2 + ... + ls)}, as described in the details section.
#'  
#' @author Andrew Roberts
#' @export
wrap_partial_slot_batch <- function(model_obj, default, slot_names, output_operator=NULL, 
                                    verbose=TRUE, .fixed_args=list(),
                                    .dynamic_args=list(), .arg_update_fn=NULL) {

  # Freeze arguments (except for dynamic arguments)
  force(model_obj); force(default); force(slot_names); force(output_operator); force(.arg_update_fn)
  for(nm in names(.fixed_args)) force(.fixed_args[[nm]])
  
  # Determine dimension of matrix that must be input into the model wrapper.
  slot_dims <- .validate_partial_slot_batch(default, slot_names, output_operator, 
                                            .fixed_args, .dynamic_args, .arg_update_fn)
  ncol_per_slot <- vapply(slot_dims, function(x) x[2], integer(1))
  input_dim <- c(slot_dims[[1]][1], sum(ncol_per_slot))
  
  if(verbose) .print_partial_slot_batch_info(model_obj, default, slot_names, input_dim, 
                                             output_operator, .fixed_args, 
                                             .dynamic_args, .arg_update_fn)
  
  function(input_mat, ...) {

    # Evaluate dynamic arguments from calling scope.
    dyn_vals <- lapply(.dynamic_args, function(expr) eval(expr, envir=parent.frame()))
    names(dyn_vals) <- names(.dynamic_args)    
    
    # Update model inputs.
    ens_input <- .update_free_slots_batch(default, input_mat, slot_names, input_dim, ncol_per_slot)
    
    # Combine all arguments in order of priority (later overrides earlier)
    extra_args <- merge_named_lists(.fixed_args, dyn_vals, list(...))
    all_args <- c(list(model_obj=model_obj, ens_input=ens_input), extra_args)
    
    # Optionally update arguments (potentially based on values of dynamics args).
    if(!is.null(.arg_update_fn)) {
      all_args <- .arg_update_fn(all_args)
      if(!is.list(all_args) || !has_unique_names(all_args)) stop(".arg_update_fn() must return a named list.")
    }

    # Return model ensemble output
    output <- do.call(run_model_ensemble, all_args)
    if(is.null(output_operator)) output else output_operator(output) 
  }
  
}


#' Update Batches of Values in Input Slots from Matrix
#'
#' A helper function for \code{\link{wrap_partial_slot_batch}}.
#'
#' @details
#' Updates the batches of values (the entire value sets, not just a single
#' value) in the slots specified by \code{free_slot_names}. These slots are 
#' constrained to all have the same batch sizes. The new values are provided
#' within a matrix \code{input_mat} with number of rows corresponding to the
#' batch size. The columns contain the values for the slots, with different 
#' contiguous column subsets allocated to different slots. This allocation is 
#' done in the order of \code{free_slot_names} (i.e., the columns of \code{input_mat}
#' and order of \code{free_slot_names} must be ordered correctly). 
#' 
#' @param ens_input An \code{EnsembleInputBroadcast} object.
#' @param input_mat A matrix with number of rows equal to the batch size. Each
#'  row contains a single value for each free slot, concatenated into a vector
#'  in the order given by \code{free_slot_names}.
#' @param input_dim The required dimension of the input matrix containing the 
#'  new values. Used to validate \code{input_mat}.
#' @param ncol_per_slot list of length equal to \code{length(free_slot_names}).
#'  The number of columns of \code{input_mat} that should be allocated to 
#'  each free slot. 
#'
#' @returns An \code{EnsembleInputBroadcast} object with updated \code{slots} field.
#' 
#' @author Andrew Roberts
.update_free_slots_batch <- function(ens_input, input_mat, free_slot_names,
                                     input_dim, ncol_per_slot) {
  
  input_mat <- wrap_as_multidim_array(input_mat)
  assert_that(is.matrix(input_mat))
  
  if(!all(dim(input_mat) == input_dim)) {
    stop("Forward model input has dimension ", .get_vector_string(dim(input_mat)),
         ". Expected dimension ", .get_vector_string(input_dim))
  }
  
  # Allocate values to each slot. Order of free_slot_names matters here.
  idx_start <- 1L
  for(i in seq_along(free_slot_names)) {
    nm <- free_slot_names[[i]]
    idx_end <- idx_start + ncol_per_slot[i] - 1L
    ens_input$slots[[nm]] <- input_mat[,idx_start:idx_end, drop=FALSE]
    idx_start <- idx_end + 1L
  }
  
  return(ens_input)
}


#' Validate free slots for partial slot matrix wrapper
#'
#' Validation for \code{\link{wrap_partial_slot_batch}}. Ensures that the selected
#' slots are matrix-like and all have the same batch size.
#' 
#' @param default An \code{EnsembleInputBroadcast} object.
#' @param slot_names \code{character}, the names of the free slots.
#' @param output_operator \code{function} or \code{NULL}. If provided, the
#'  model wrapper represents the composition of the \code{run_model_ensemble()}
#'  call with the \code{output_operator} function.
#' @param .fixed_args list of fixed arguments. See \code{wrap_partial_slot_batch}.
#' @param .dynamic_args list of dynamic arguments. See \code{wrap_partial_slot_batch}.
#' @param .arg_update_fn function or NULL. See \code{wrap_partial_slot_batch}.
#' 
#' @returns Invisibly returns list of dimensions of each free batch slot. 
#'  At present, the free slot batches are constrained to be matrices (one row
#'  per slot value). Therefore, each element of this list will be a two 
#'  element integer vector representing the matrix dimensions. The first axis
#'  of each vector corresponds to the batch dimension, and will be equal across 
#'  all slots. Throws error if free slots do not meet requirements.
#'
#' @author Andrew Roberts
.validate_partial_slot_batch <- function(default, slot_names, output_operator,
                                         .fixed_args, .dynamic_args, .arg_update_fn) {
  
  # validate_broadcast_fwd_model_slots(default, slot_names)
  
  assert_that(is.function(output_operator) || is.null(output_operator),
              msg=paste0("`output_operator` must be a function or NULL. Got ", 
                         paste(class(output_operator), collapse=", ")))
  
  assert_that(is.function(.arg_update_fn) || is.null(.arg_update_fn),
              msg=paste0("`.arg_update_fn` must be a function or NULL. Got ", 
                         paste(class(.arg_update_fn), collapse=", ")))
  
  # Ensure all selected slots are flattened batch arrays (matrix). Slot values
  # are stored in the rows of the matrix.
  free_slots <- default$slots[slot_names]
  
  if(!all(vapply(free_slots, is_matrix_like, logical(1)))) {
    stop("Matrix forward model requires all free slots to be matrices ",
         "(one row per value)")
  }
  
  free_slots <- lapply(free_slots, wrap_as_multidim_array)
  n_batch_per_slot <- vapply(free_slots, nrow, integer(1))
  if(length(unique(n_batch_per_slot)) > 1L) {
    stop("`wrap_partial_slot_mat()` requires all slots to have same batch size ",
         "(number of rows).")
  }
  
  # Validate fixed and dynamic arguments.
  .check_fixed_and_dynamic_args(.fixed_args, .dynamic_args)
  
  # Return dimensions of each slot.
  invisible(lapply(free_slots, dim))
}


#' Print information about partial slot matrix wrapper
#'
#' Prints information summarizing the setup of the model wrapper constructed
#' by \code{\link{wrap_partial_slot_batch}}.
#' 
#' @param obj R object representing the model.
#' @param default An \code{EnsembleInputBroadcast} object.
#' @param slot_names \code{character}, the names of the free slots.
#' @param input_dim \code{integer}, two-element vector representing the matrix
#'  dimensions for the matrix input to the model wrapper.
#' @param output_operator function or \code{NULL}. See \code{wrap_partial_slot_batch}.
#' @param .fixed_args list of fixed arguments. See \code{wrap_partial_slot_batch}.
#' @param .dynamic_args list of dynamic arguments. See \code{wrap_partial_slot_batch}.
#' @param .arg_update_fn function or NULL. See \code{wrap_partial_slot_batch}.
#'  
#' @returns none. Prints to standard output.
#' @author Andrew Roberts
.print_partial_slot_batch_info <- function(obj, default, slot_names, input_dim,
                                           output_operator, .fixed_args, 
                                           .dynamic_args, .arg_update_fn) {
  
  cat("--- Model wrapper: partial slot with matrix input ---\n\n")
  
  cat("Forward model signature: function(input_mat, ...)\n")
  cat("input_mat shape: ", .get_vector_string(input_dim), "\n", sep="")
  cat("Free slots: ")
  cat(paste(slot_names, collapse=", "), "\n\n")
  
  method_name <- paste0("run_model.", class(obj)[1])
  cat("Run model method:", method_name,"\n\n")
  
  if(length(.fixed_args) > 0L) cat("Fixed arguments:", paste(names(.fixed_args), collapse=", "), "\n")
  if(length(.dynamic_args) > 0L) cat("Dynamic arguments:", paste(names(.dynamic_args), collapse=", "), "\n\n")
  
  cat("Output operator specified:", !is.null(output_operator), "\n")
  cat("Arg update function specified:", !is.null(.arg_update_fn), "\n\n")
  
  cat("Default EnsembleInput:\n")
  summary(default)
}


# ------------------------------------------------------------------------------
# TODO:
# - This code is incomplete/in flux. It is intended to define a wrapped model
#   that allows users to pass in a single value of a slot, or multiple values
#   in which case the behavior will be vectorized over that slot.
# - Need to determine how best to define this. It probably makes sense to provide
#   an interface like `wrap_model_vectorized_slots(obj, fixed_slots, broadcast_rule, free_slot_dims, ...)`.
#   Here, `free_slot_dims` would be a named list of dimensions for each slot.
#   The wrapped model would then expect a matrix, with one value per row. This
#   batch of values for the free slots would be Cartesian product'd against
#   the ensemble input consisting of the fixed slots.
# ------------------------------------------------------------------------------

#' Generate a forward model function
#'
#' Returns an R function that accepts as an argument a representation of the
#' values of "free" input slots. Other input slots are fixed. An \code{EnsembleInput}
#' serves as a template, which both defines the values of the fixed slots, and 
#' is used to determine the correct format for the argument that will be 
#' accepted by the returned forward model.
#'
#' @details
#' The \code{EnsembleInputBroadcast} object \code{ens_template} defines the
#' input slots required by the model \code{model_obj}. The slots specified by
#' \code{slot_names} are designated as "free", while the remaining slots will
#' be fixed using the values in \code{ens_template}. The free slots are required
#' to be array-like. If \code{nm} is one of the specified free slot names, this
#' means that \code{ens_template$slots[[nm]]} must be array-like. The first 
#' dimension of this array is interpreted as indexing over different values
#' within this slots. The remaining dimensions thus define the dimension of a
#' single value that the slot accepts. The generated forward model is defined
#' to accept values of this dimension. 
#' 
#' The two input modes require different constraints on the inputs:
#' 1. \code{matrix}: The forward model expects a matrix of shape \code{(n, len)},
#'  where \code{n} is a variable batch size and \code{len} is the total number
#'  of scalar elements summed across all free slots. The relevant column subset
#'  for each slot is extracted and re-shaped to align with the slot dimension.
#'  The columns are assumed to be concatenated in the order given in 
#'  \code{free_slot_names}. Because this mode restricts the input as a matrix,
#'  the batch size is constrained to be the same for all free slots. This may
#'  be too restrictive in certain settings. In such cases, one can consider 
#'  re-defining the slots, or opt for \code{list} model.
#' 2. \code{list}: The forward model expects a list of length equal to 
#'  \code{length(free_slot_names)}, where element \code{i} is an array with
#'  dimension \code{(ni, d1, ..., dp)}. \code{ni} is the batch size (allowed
#'  to vary by slot) while \code{(d1, ..., dp)} is the dimension of a value
#'  in that slot.
#'  
#' This method of forward model generation allows for vectorization; the forward
#' model accepts batches of arbitrary size. One must keep in mind that the 
#' broadcast rule encoded in \code{ens_template} will not change. This means
#' that trying to run the forward model with certain sized batches may result
#' in an error due to incompatibility with the broadcast rule. Each call to the
#' forward model will result in the generation of a new \code{EnsembleInput}
#' object, with the free slot values updated and a new \code{idx_mat} matrix
#' generated.
#'  
#' @param model_obj An object for which a \code{run_model} method is defined.
#' @param ens_template An \code{EnsembleInputBroadcast} object, which is required
#'  to have its \code{rule} field defined.
#' @param free_slot_names character, the subset of \code{slot_names(ens_template)}
#'  that will be used to define the input to the forward model.
#' @param input_type character, either "matrix" or "list".
#' @param output_operator function or \code{NULL}. If provided, the function
#'  is applied to the output of the model; i.e., the forward model return will
#'  be of the form \code{output_operator(run_model(model_obj, ens_input, ...))}.
#' @param verbose logical, if \code{TRUE} (default), prints a description of the 
#'  forward model.
#'  
#' @returns function, the forward model.
#'
#' @author Andrew Roberts
#' @export
gen_forward_model <- function(model_obj, ens_template, free_slot_names, input_type="matrix",
                              output_operator=NULL, verbose=TRUE) {
  
  # Freeze arguments.
  force(model_obj); force(ens_template); force(free_slot_names); 
  force(input_type); force(output_operator)
  
  slot_base_dims <- .validate_forward_model(model_obj, ens_template, free_slot_names, input_type)
  param_len <- sum(vapply(slot_base_dims, function(x) prod(x)))
  
  if(verbose) .print_forward_model(model_obj, ens_template, free_slot_names,
                                   slot_base_dims, param_len, input_type, output_operator)
  
  function(input_mat, ...) {
    ens_input <- update_free_slots(default, input_mat, slot_names, input_dim, ncol_per_slot)
    output <- run_model_ensemble(obj, ens_input, ...)
    if(!is.null(output_operator)) output_operator(output)
  }
  
}


.validate_forward_model <- function(model_obj, ens_template, free_slot_names, input_type) {
  
  # Ensure valid input type.
  valid_input_types <- c("matrix", "list")
  if(!(input_type %in% valid_input_types)) {
    stop("`input_type` must be one of: ", paste(valid_input_types, collapse=", "),
         ". Got ", input_type)
  }
  
  # Validate free slots.
  .validate_free_slots(default, slot_names, require_rule=TRUE)
  free_slots <- .wrap_and_validate_array_slots(ens_template$slots[slot_names])
  
  # Ensure model run method exists.
  method_name <- paste0("run_model.", class(obj)[1])
  if(!(method_name %in% methods("run_model"))) {
    stop("No run_model() method exists for `model_obj` of class ", class(model_obj)[1])
  }
  
  # Dimension of a single array value for each free slot.
  slot_base_dims <- lapply(free_slots, function(x) dim(x)[-1])
  
  invisible(slot_base_dims)
}


.print_forward_model <- function(model_obj, ens_template, free_slot_names,
                                 slot_base_dims, param_len, input_type, output_operator) {
  
  cat("--- Generating forward model ---\n\n")
  
  cat("Forward model signature: function(input, ...)\n")
  if(input_type == "array") {
    batch_input_shape <- paste0("(n,", param_len, ")")
    cat("input type: array\n")
    cat("input shape: ", batch_input_shape, "\n", sep="")
  } else {
    batch_dims <- lapply(slot_base_dims, function(x) .get_vector_string(c("n", x)))
    str_list_spec <- paste0("list{", paste(batch_dims, collapse=", "), "}")
    cat("input type: list\n")
    cat("input shape: ", str_list_spec, "\n", sep="")
  }
  
  cat("Free slots: ")
  cat(paste(slot_names, collapse=", "), "\n\n")
  
  method_name <- paste0("run_model.", class(obj)[1])
  cat("Run model method:", method_name,"\n\n")
  
  cat("Default EnsembleInput:\n")
  summary(default)
}


.validate_free_slots <- function(ens_template, free_slot_names, require_rule=FALSE) {
  
  # General EnsembleBroadcastInput validation. 
  check_ensemble_input_broadcast_type(ens_template)
  if(require_rule && is.null(ens_template$rule)) {
    stop("`ens_template` requires specification of a broadcast rule.")
  }
  
  if(anyDuplicated(free_slot_names) > 0L) {
    stop("`free_slot_names` contains duplicates.")
  }
  
  invalid_slot_names <- setdiff(free_slot_names, slot_names(ens_template))
  if(length(invalid_slot_names) > 0L) {
    stop("Invalid slot names: ", paste(invalid_slot_names, collapse=", "))
  }
}


.wrap_and_validate_array_slots <- function(array_slots) {
  
  if(!all(vapply(array_slots, is_array_like, logical(1)))) {
    stop("Forward model requires all free slots to be array-like ",
         "(first dimension is batch dimension)")
  }
  
  lapply(free_slots, wrap_as_multidim_array)
}


# ------------------------------------------------------------------------------
# Helper/utility functions for model wrappers
# ------------------------------------------------------------------------------

#' Apply modifyList to multiple lists.
#'
#' Later arguments take precedence over earlier ones. All elements must be
#' named.
#'
#' @export
merge_named_lists <- function(...) {
  arglists <- list(...)
  Reduce(modifyList, arglists)
}


#' Get string representation of vector
#'
#' Given a vector of the form \code{c("a", "b", "c")}, returns a string of the
#' form \code{`("a","b","c")`}.
#'
#' @author Andrew Roberts
.get_vector_string <- function(dims) {
  paste0("(", paste(dims, collapse=","), ")")
}


#' Validation for fixed and dynamic arguments
#'
#' Ensures these arguments are named lists with unique, non-overlapping names.
#' Also ensures that all dynamic arguments are symbols or quoted expressions.
#' 
#' @returns \code{TRUE} (invisibly) if validation passed. Otherwise throws error.
#' @author Andrew Roberts
.check_fixed_and_dynamic_args <- function(.fixed_args, .dynamic_args) {
  
  assert_that(is.list(.fixed_args) && is.list(.dynamic_args))
  
  nm <- c(names(.fixed_args), names(.dynamic_args))
  if(anyDuplicated(nm) > 0L) {
    stop("`.fixed_args` and `.dynamic_args` must have unique, non-overlapping names.")
  }
  
  # Ensure dynamic args ars symbols or quoted expressions.
  invalid_arg <- !vapply(.dynamic_args, is_quoted, logical(1))
  if(any(invalid_arg)) {
    stop(
      sprintf("Each element of `.dynamic_args` must be a quoted symbol or expression. Problematic arguments: %s",
              paste(names(.dynamic_args)[invalid_arg], collapse=", ")),
      call.=FALSE
    )
  }
  
  invisible(TRUE)
}


is_quoted <- function(x) {
  inherits(x, "name") || inherits(x, "call")
}






















#' Forward model factory with multiple vectorized free slots
#'
#' This factory generates a closure that accepts multiple free slots as lists of values.
#' Each combination of free slot values is automatically broadcast over fixed slots
#' using the provided broadcasting rule.
#'
#' @param slots Named list of slot value sets. Use `NULL` for free slots.
#' @param rule Broadcasting rule function (produces index matrix).
#' @param model_fn Function to run a single model input.
#' @param ensemble_runner Function that executes the ensemble.
#' @param return_ensemble Logical; if TRUE, return a `forward_model_run` object.
#'
#' @return A closure whose arguments are the free slots. Returns either the raw results
#'   or a `forward_model_run` object containing the ensemble and results.
#' @export
forward_model_factory <- function(slots, rule, model_fn, ensemble_runner, return_ensemble = FALSE) {
  free_slots  <- names(slots)[vapply(slots, is.null, logical(1))]
  fixed_slots <- slots[!vapply(slots, is.null, logical(1))]
  
  force(slots); force(rule); force(model_fn); force(ensemble_runner); force(return_ensemble)
  
  function(...) {
    args <- list(...)
    
    # Check that all free slots provided
    if (!setequal(names(args), free_slots)) {
      stop("Must provide exactly the free slots: ", paste(free_slots, collapse = ", "))
    }
    
    # Convert all values to lists if they are not already
    for (nm in free_slots) {
      val <- args[[nm]]
      if (!is.list(val)) args[[nm]] <- as.list(val)
    }
    
    # Merge fixed slots with user-provided free slots
    full_slots <- c(fixed_slots, args)
    
    # Construct broadcasted ensemble using the provided rule
    emb <- ensemble_model_input_broadcast(full_slots, rule)
    
    # Run ensemble
    results <- ensemble_runner(emb, model_fn)
    
    if (return_ensemble) {
      structure(
        list(ensemble = emb, results = results),
        class = c("forward_model_run", "ensemble_model_input_broadcast", "ensemble_model_input")
      )
    } else {
      results
    }
  }
}


# ============================================================
# Partial evaluation for forward models
# ============================================================

#' Partially fix slots in a forward model
#'
#' Returns a new forward model closure where some slots are fixed.
#' Remaining slots become the new free slots of the returned function.
#'
#' @param fwd A forward model closure created by `forward_model_factory`.
#' @param fixed_slots Named list of slots to fix. Must be subset of original free slots.
#'
#' @return A new forward model closure with fewer free slots.
#' @export
partial_forward_model <- function(fwd, fixed_slots) {
  stopifnot(is.function(fwd), is.list(fixed_slots))
  
  function(...) {
    args <- list(...)
    # Merge fixed_slots into current args
    all_args <- c(fixed_slots, args)
    
    # Call the original forward model
    do.call(fwd, all_args)
  }
}


# ============================================================
# Peek a slice of an ensemble
# ============================================================

#' Peek a slice of an ensemble model input
#'
#' Returns the slot values for specific runs or conditions without running the model.
#'
#' @param emb An ensemble_model_input object (list, table, or broadcast).
#' @param run_indices Optional integer vector of run indices to peek.
#' @param slot_filters Optional named list of slot values to filter by.
#' @param as_tibble Logical; if TRUE and tibble is available, return a tibble.
#'
#' @return A data.frame or tibble with one row per matching run and one column per slot.
#' @export
peek_ensemble_slice <- function(emb, run_indices = NULL, slot_filters = NULL, as_tibble = TRUE) {
  tbl <- as_table(emb)
  idx <- tbl$index
  
  # Filter by run_indices if provided
  if (!is.null(run_indices)) {
    idx <- idx[run_indices, , drop = FALSE]
  }
  
  # Filter by slot_filters if provided
  if (!is.null(slot_filters)) {
    for (nm in names(slot_filters)) {
      if (!nm %in% names(tbl$slots)) stop("Unknown slot: ", nm)
      values <- slot_filters[[nm]]
      mask <- idx[[nm]] %in% match(values, tbl$slots[[nm]])
      idx <- idx[mask, , drop = FALSE]
    }
  }
  
  # Materialize the slot values for the selected runs
  df <- as.data.frame(
    lapply(names(tbl$slots), function(nm) tbl$slots[[nm]][idx[[nm]]]),
    stringsAsFactors = FALSE
  )
  names(df) <- names(tbl$slots)
  
  if (as_tibble && requireNamespace("tibble", quietly = TRUE)) {
    df <- tibble::as_tibble(df)
  }
  
  df
}


# ============================================================
# Peek a slice of an ensemble
# ============================================================

#' Peek a slice of an ensemble model input
#'
#' Returns the slot values for specific runs or conditions without running the model.
#'
#' @param emb An ensemble_model_input object (list, table, or broadcast).
#' @param run_indices Optional integer vector of run indices to peek.
#' @param slot_filters Optional named list of slot values to filter by.
#' @param as_tibble Logical; if TRUE and tibble is available, return a tibble.
#'
#' @return A data.frame or tibble with one row per matching run and one column per slot.
#' @export
peek_ensemble_slice <- function(emb, run_indices = NULL, slot_filters = NULL, as_tibble = TRUE) {
  tbl <- as_table(emb)
  idx <- tbl$index
  
  # Filter by run_indices if provided
  if (!is.null(run_indices)) {
    idx <- idx[run_indices, , drop = FALSE]
  }
  
  # Filter by slot_filters if provided
  if (!is.null(slot_filters)) {
    for (nm in names(slot_filters)) {
      if (!nm %in% names(tbl$slots)) stop("Unknown slot: ", nm)
      values <- slot_filters[[nm]]
      mask <- idx[[nm]] %in% match(values, tbl$slots[[nm]])
      idx <- idx[mask, , drop = FALSE]
    }
  }
  
  # Materialize the slot values for the selected runs
  df <- as.data.frame(
    lapply(names(tbl$slots), function(nm) tbl$slots[[nm]][idx[[nm]]]),
    stringsAsFactors = FALSE
  )
  names(df) <- names(tbl$slots)
  
  if (as_tibble && requireNamespace("tibble", quietly = TRUE)) {
    df <- tibble::as_tibble(df)
  }
  
  df
}


#' Slice a forward model to selected runs
#'
#' Returns a new forward model closure that only runs a subset of the original ensemble.
#'
#' @param fwd A forward model closure created by `forward_model_factory`.
#' @param run_indices Optional vector of run indices to keep.
#' @param slot_filters Optional named list of slot values to filter runs.
#'
#' @return A new forward model closure with the same interface as the original, but only executing the selected runs.
#' @export
slice_forward_model <- function(fwd, run_indices = NULL, slot_filters = NULL) {
  stopifnot(is.function(fwd))
  
  function(...) {
    # Generate full ensemble using the original closure with the provided args
    full <- fwd(...)
    
    # Determine which runs to keep
    if (!is_forward_model_run(full)) {
      stop("The forward model must be created with return_ensemble = TRUE to slice.")
    }
    
    emb <- full$ensemble
    
    # Use peek_ensemble_slice to get indices matching the filters
    slice_df <- peek_ensemble_slice(emb, run_indices = run_indices, slot_filters = slot_filters)
    
    # Map filtered rows back to indices in the original broadcast
    idx_to_keep <- sapply(seq_len(nrow(slice_df)), function(i) {
      match(
        paste0(as.list(slice_df[i, ]), collapse = "_"),
        paste0(lapply(get_broadcast_run(emb, seq_len(nrow(emb$index))), function(mi) {
          paste0(unlist(mi$slots), collapse = "_")
        }), collapse = "_")
      )
    })
    
    # Run only the selected indices
    results <- full$results[idx_to_keep]
    
    # Return sliced forward_model_run object
    structure(
      list(ensemble = peek_ensemble_slice(emb, run_indices = idx_to_keep, as_tibble = FALSE),
           results = results),
      class = c("forward_model_run_slice", "forward_model_run", "ensemble_model_input_broadcast", "ensemble_model_input")
    )
  }
}







#' @export
print.forward_model_run <- function(x, ...) {
  cat("<forward_model_run>\n")
  cat("Ensemble:\n")
  NextMethod()  # uses the ensemble_model_input print
  cat("Number of results:", length(x$results), "\n")
  invisible(x)
}

#' @export
summary.forward_model_run <- function(object, ...) {
  cat("<forward_model_run summary>\n")
  cat("Ensemble:\n")
  NextMethod()  # ensemble_model_input summary
  cat("Number of results:", length(object$results), "\n")
  invisible(object)
}































.make_fwd_model <- function(settings, input_template, obs_op=NULL, 
                            run_id_prefix="run", ensemble_prefix="ens",
                            include_uuid=TRUE, ...) {
  
}


make_fwd_model <- function(settings, output_vars=NULL, obs_op=NULL,
                           run_id_prefix="run", include_uuid=TRUE, ...) {
  
  run_counter <- 1L
  
  # Default to identity
  if(is.null(obs_op)) obs_op <- function(x) x
  
  function(input) {
    run_id <- paste0(run_id_prefix, run_counter)
    id_counter <<- id_counter + 1L
    if(include_uuid) run_id <- paste(run_id, uuid::UUIDgenerate(), sep="_")
      
    out <- run_model_and_read_output(settings, runtime_input=input, run_id=run_id, 
                                     append_run=FALSE, stop_on_error=TRUE, 
                                     output_vars=output_vars, ...)
    obs_op(out)
  }
  
}


make_fwd_ensemble_model <- function(settings, output_vars = NULL, obs_op = NULL, append_run = TRUE, ...) {
  id_counter <- 1L
  
  if (is.null(obs_op)) obs_op <- function(x) x  # identity
  
  function(input_matrix) {
    # input_matrix: rows are individual inputs (matrix or tibble)
    n <- if (is.matrix(input_matrix)) nrow(input_matrix) else length(input_matrix)
    
    # Generate unique run IDs for ensemble members
    run_ids <- paste0("run", seq(id_counter, length.out = n))
    id_counter <<- id_counter + n
    
    # Construct runtime_input list
    # If using matrix: each row must be converted to a RuntimeInput; customize this per your protocol
    runtime_inputs <- lapply(seq_len(n), function(i) {
      # Assumes you have a function `make_runtime_input`
      make_runtime_input(param = as.numeric(input_matrix[i, ]))
      # Optionally, deal with IC etc. if needed
    })
    
    # EnsembleInput tibble
    ensemble_input <- tibble::tibble(
      run_id = run_ids,
      settings = rep(list(settings), n),
      runtime_input = runtime_inputs
    )
    
    out <- run_model_ensemble_and_read_output(
      ensemble_input, variables = output_vars, append_run = append_run, ...
    )
    
    obs_op(out)
  }
}


make_fwd_ensemble_model_matrix <- function(settings, output_vars = NULL, obs_op = NULL, append_run = TRUE, ...) {
  id_counter <- 1L
  if (is.null(obs_op)) obs_op <- function(x) x
  
  function(input_matrix) {
    n <- if (is.matrix(input_matrix)) nrow(input_matrix) else length(input_matrix)
    run_ids <- paste0("run", seq(id_counter, length.out = n))
    id_counter <<- id_counter + n
    
    runtime_inputs <- lapply(seq_len(n), function(i) {
      param_vec <- if (is.matrix(input_matrix)) input_matrix[i, ] else input_matrix[[i]]
      make_runtime_input(param = param_vec)
    })
    
    ensemble_input <- tibble::tibble(
      run_id = run_ids,
      settings = rep(list(settings), n),
      runtime_input = runtime_inputs
    )
    
    out <- run_model_ensemble_and_read_output(
      ensemble_input, variables = output_vars, append_run = append_run, ...
    )
    
    obs_op(out)  # often you want to extract just what you need (e.g. a filtered set); customize here
  }
}











