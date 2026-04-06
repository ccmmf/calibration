# forward_model/ensemble_input_broadcast.r

# The broadcast format for an `EnsembleInput` is typically the most 
# efficient data structure, relative to the list and table formats. An
# `EnsembleInputBroadcast` object is defined by a unique set of values per slot,
# in addition to a `(n_runs, n_inputs)` matrix of indices describing how the 
# slot values map to particular runs. Instead of explicitly passing this matrix,
# an `EnsembleInputBroadcast` object can be constructed by passing a 
# "broadcast rule" function that produces this matrix.

# `EnsembleInputBroadcast` currently does not support run metadata.
# It also currently requires all runs to have the same slots. All
# of these can eventually be accommodated. For the latter, `mat_rule` could be
# allowed to have NA values.


EnsembleInputBroadcast <- function(slots, list_rule=NULL, fn_rule=NULL, mat_rule=NULL) {
  x <- .new_ensemble_input_broadcast(slots, list_rule, fn_rule, mat_rule)
  validate_ensemble_input_broadcast(x)
  
  return(x)
}


#' Construct ensemble model input in broadcast format from index matrix
#' 
#' Constructs an object of class \code{EnsembleInputBroadcast}, which consists
#' of a set of unique values for each slot, along with a matrix containing 
#' indices of these values that encodes how to construct the corresponding 
#' \code{EnsembleInputTable}.
#' 
#' @details
#' An \code{EnsembleInputBroadcast} is defined by two fields: \code{slots} and
#' \code{mat_rule}. The former is a named list of input fields/types ("slots").
#' The names defined the slot names. The values must themselves be lists 
#' containing a unique set of values for each slot. \code{mat_rule} is an
#' integer matrix of shape \code{(n_runs, n_inputs)}. The \code{(i,j)} element 
#' contains the index of the list \code{slots[[j]]}, which is the value to use 
#' in the jth slot for the ith run. The row names of this matrix define the 
#' run IDs for each run. The column names are set to the corresponding slot names.
#' While this index matrix can be defined by hand, it is typically more 
#' convenient and self-documenting to instead implicitly define this matrix via 
#' a "broadcast rule". See the alternative constructor 
#' \code{\link{EnsembleInput.function}} for more information.
#'
#' @param mat_rule An integer matrix of dimension \code{(n_runs, n_inputs)}.
#'  The \code{(i,j)} element contains the index of the list \code{slots[[j]]},
#'  which is the value to use in the jth slot for the ith run. Row names will
#'  be interpreted as run IDs, with defaults defined if not explicitly provided.
#' @param slots A named list of slot value sets. The jth element of \code{slots}
#'  is itself a list, containing a unique set of values for that slot.
#'  
#' @return An object of class \code{EnsembleInputBroadcast}, inheriting from 
#'  \code{EnsembleInput}.
#' @seealso \code{\link{EnsembleInput.function}}
#'
#' @author Andrew Roberts
#' @export
EnsembleInput.matrix <- function(mat_rule, slots) {
  
  x <- .new_ensemble_input_broadcast(slots, mat_rule=mat_rule,
                                     broadcast_rule=NULL)
  validate_ensemble_input_broadcast(x)

  return(x)
}


#' Construct ensemble model input in broadcast format from broadcast rule
#' 
#' Constructs an object of class \code{EnsembleInputBroadcast}, which consists
#' of a set of unique values for each slot, along with a broadcast rule that
#' encodes how to construct the corresponding \code{EnsembleInputTable}.
#' 
#' @details
#' This is an alternative to \code{\link{EnsembleInput.matrix}}, which instead
#' takes a matrix of indices that describes how to construct the ensemble table
#' (see \code{\link{EnsembleInput.matrix}} for more detailed documentation on
#' the definition of an \code{EnsembleInputBroadcast}).
#' This constructor instead takes a broadcast rule, which is used to construct
#' \code{mat_rule}. Let \code{lens <- sapply(slots, length)} denote the length 
#' of each slot dimension. When called like \code{broadcast_rule(lens)}, the 
#' broadcast rule must return an integer matrix of shape \code{(n_runs, n_inputs)}.
#' The \code{(i,j)} element contains the index of the list \code{slots[[j]]},
#' which is the value to use in the jth slot for the ith run. 
#' 
#' Most common input combination patterns can be reproduced by combining a few
#' simple rules. See the broadcast rule documentation 
#' (e.g., \code{\link{get_composite_rule}}) for common rules that have already
#' been implemented, and functions for combining them.
#'
#' @param broadcast_rule A broadcast rule function. See details for requirements.
#' @param slots A named list of slot value sets. The jth element of \code{slots}
#'  is itself a list, containing a unique set of values for that slot.
#'  
#' @return An object of class \code{EnsembleInputBroadcast}, inheriting from 
#'  \code{EnsembleInput}.
#' @seealso \code{\link{EnsembleInput.matrix}}, \code{\link{rule_cartesian}},
#'  \code{\link{rule_match}}, \code{\link{rule_broadcast}}, \code{\link{rule_recycle}} 
#'
#' @author Andrew Roberts
#' @export
EnsembleInput.function <- function(broadcast_rule, slots) {

  x <- .new_ensemble_input_broadcast(slots, mat_rule=NULL,
                                     broadcast_rule=broadcast_rule)
  validate_ensemble_input_broadcast(x)
  
  return(x)
}
  

#' Internal constructor for EnsembleInputBroadcast
#' 
#' Instantiates an \code{EnsembleInputBroadcast} object. Limited validation is 
#' done in this function. See \code{\link{EnsembleInput.matrix}} for the 
#' public interface and additional documentation.
#' 
#' @details
#' Exactly one of \code{mat_rule} or \code{broadcast_rule} must be non-\code{NULL}.
#' If the latter is provided, then \code{mat_rule} is constructed using the
#' broadcast rule. The row names of \code{mat_rule} are interpreted as run IDs,
#' and therefore should be unique. Default run IDs of the form `run_<row-idx>`
#' are assigned if not provided.
#' 
#' @param slots A named list of slot value sets. The jth element of \code{slots}
#'  is itself a list, containing a unique set of values for that slot.
#' @param list_rule list, a list representation of a broadcast rule.
#' @param fn_rule function, a broadcast rule function. See details for requirements.
#' @param mat_rule matrix, an integer matrix of dimension \code{(n_runs, n_inputs)}.
#'  The \code{(i,j)} element contains the index of the list \code{slots[[j]]},
#'  which is the value to use in the jth slot for the ith run.
#' 
#' @returns An object of class \code{EnsembleInputBroadcast}, inheriting from 
#'  \code{EnsembleInput}.
#' 
#' @seealso \code{\link{get_broadcast_rule}}
#' @author Andrew Roberts
.new_ensemble_input_broadcast <- function(slots, list_rule, fn_rule, mat_rule) {

  rule_formats <- list(list_rule, fn_rule, mat_rule)
  if(sum(vapply(rule_formats, Negate(is.null), logical(1))) != 1L) {
    stop("Exactly one of `list_rule`, `fn_rule`, `mat_rule` must be non-NULL.")
  }
  
  if(!is_named_or_empty_list(slots)) {
    stop("`slots` must be named or empty list.")
  }

  if(!is.null(list_rule)) fn_rule <- get_broadcast_rule(names(slots), list_rule, drop_absent_axes=FALSE)
  if(!is.null(fn_rule)) mat_rule <- .broadcast_slots(slots, fn_rule) 

  # Assign default run IDs if needed.
  if(is.null(rownames(mat_rule))) {
    rownames(mat_rule) <- paste0("run_", seq_len(nrow(mat_rule)))
  }
  
  # Assign slot names as column names, if needed. Sort columns to align with
  # slots order.
  if(is.null(colnames(mat_rule))) {
    message("No column names provided for `mat_rule`. Setting to `names(slots)`,",
            " which assumes column order aligns with slot order.")
    
    colnames(mat_rule) <- names(slots)
  } else {
    mat_rule <- mat_rule[,names(slots)]
  }
  
  structure(list(slots=slots, list_rule=list_rule, fn_rule=fn_rule, mat_rule=mat_rule),
            class = c("EnsembleInputBroadcast", "EnsembleInput"))
}


#' Check if object inherits from \code{EnsembleInputBroadcast}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{EnsembleInputBroadcast}.
#' 
#' @author Andrew Roberts
#' @export
is_ensemble_input_broadcast <- function(x) {
  is_ensemble_input(x) && inherits(x, "EnsembleInputBroadcast")
}


#' Throw error if object is not an \code{EnsembleInputBroadcast}
#' 
#' @param x An object
#' @returns Invisibly returns \code{TRUE} if \code{x} is an \code{EnsembleInputBroadcast}.
#'  Otherwise throws an error.
#' 
#' @seealso \code{\link{EnsembleInput}}
#' @author Andrew Roberts
#' @export
check_ensemble_input_broadcast_type <- function(x) {
  if (!is_ensemble_input_broadcast(x)) {
    stop("`x` is not an EnsembleInputBroadcast object.")
  }
  
  invisible(TRUE)
}


#' Validate an EnsembleInputBroadcast
#'
#' Validates the general structure of a \code{EnsembleInputBroadcast} object. 
#'
#' @details
#' Must contain \code{slots}, \code{mat_rule}, and \code{rule} fields.
#' \code{slots} must be a named list (or empty list). All elements of 
#' \code{slots} must themselves be lists. \code{mat_rule} must be an integer 
#' matrix with number of cols equal to \code{length(slots)}. The values in 
#' column \code{j} of \code{mat_rule} must be integers between 1 and
#' \code{length(slots[[j]])}. \code{rule} must be a function, or \code{NULL}.
#' \code{mat_rule} must have unique and non-missing row names for all rows, 
#' as the row names are interpreted as the run IDs. \code{mat_rule} must 
#' have column names set to \code{names(slots)}, in the same order.
#'
#' @param x An object.
#' @return Invisibly returns \code{TRUE} if validation tests are passed, 
#'  or throws an error if invalid.
#'  
#' @author Andrew Roberts
#' @export
validate_ensemble_input_broadcast <- function(x) {
  
  check_ensemble_input_broadcast_type(x)
  
  required_fields <- c("slots", "list_rule", "fn_rule", "mat_rule")
  missing_fields <- setdiff(names(x), required_fields)
  
  if(length(missing_fields) > 0L) {
    stop("EnsembleInputBroadcast is missing fields: ", 
         paste(missing_fields, collapse=", "))
  }

  slots <- x$slots
  list_rule <- x$list_rule
  fn_rule <- x$fn_rule
  mat_rule <- x$mat_rule
  
  assert_that(is.list(slots), msg="`slots` must be a list.")
  if(length(slots) > 0L && !has_unique_names(slots)) {
    stop("EnsembleInputBroadcast$slots must be a named list with unique names.")
  }

  # Ensure list_rule is a valid broadcast list representation.
  if(!is.null(list_rule)) {
    tryCatch({
      .standardize_list_rule(names(slots), list_rule, drop_absent_axes=FALSE)
    }, error = function(e) {
      stop("`list_rule` is invalid: ", e$message)
    })
  }
  
  if(!is.function(fn_rule) && !is.null(fn_rule)) {
    stop("EnsembleInputBroadcast$fn_rule must be a function or NULL.")
  }
  
  if(!is.matrix(mat_rule) || !assertthat:::is.integerish(mat_rule)) {
    stop("EnsembleInputBroadcast$mat_rule must be an integer matrix.")
  }
  
  if(is.null(rownames(mat_rule))) {
    stop("EnsembleInputBroadcast$mat_rule is missing row names (run IDs).")
  }
  
  row_names <- rownames(mat_rule)
  
  if(is.null(row_names)) {
    stop("EnsembleInputBroadcast$mat_rule is missing row names (run IDs).")
  }
  
  if(!all(nzchar(row_names)) || anyDuplicated(row_names)) {
    stop("EnsembleInputBroadcast$mat_rule has duplicate or missing row names (run IDs).")
  }
  
  if(!all(colnames(mat_rule) == names(slots))) {
    stop("EnsembleInputBroadcast$mat_rule must have column names identical to `names(slots)`.")
  }
  
  if(!all(vapply(slots, is_slot_value_set, logical(1)))) {
    stop("EnsembleInputBroadcast$slots must be a list of valid slot value sets.")
  }
  
  if(ncol(mat_rule) != length(slots)) {
    stop("EnsembleInputBroadcast dimension mismatch between `mat_rule` and `slots`.")
  }
  
  if(ncol(mat_rule) > 0L) {
    for(j in seq_len(ncol(mat_rule))) {
      max_idx <- length(slots[[j]])
      if(!all(mat_rule[,j] >= 1L & mat_rule[,j] <= max_idx)) {
        stop("`mat_rule` contains invalid entries in column ", j,
             " Entries must be between 1 and length(slots[[", j, "]]) = ", max_idx)
      }
    }
  }
  
  invisible(TRUE)
}


#' @details
#' Defines what constitues a valid set of slot values. Each element 
#' \code{slots[[i]]} of the slot list must be a valid set of slot values.
#' Currently supports lists of values and matrices of values (one per row).
#' Vectors are wrapped as one row matrices.
is_slot_value_set <- function(x) {
  
  is.list(x) || is_array_like(x) 
  
}


#' Return character vector of run IDs
#'
#' See \code{\link{run_ids}}
#'
#' @param An \code{EnsembleInputBroadcast}
#' @param ... Not used
#' 
#' @return A character vector of run IDs of length \code{n_runs(x)}.
#' @seealso \code{\link{run_ids}}
#' 
#' @author Andrew Roberts
#' @export
run_ids.EnsembleInputBroadcast <- function(x, ...) {
  rownames(x$mat_rule)
}


#' Get input slot names
#'
#' Returns the names of slots (input fields) present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputBroadcast} object.
#' @param unique_only Logical; if \code{TRUE} (default), returns only the
#'   unique set of slot names across runs. If \code{FALSE}, returns
#'   per-run slot names (a list).
#' @param ... Not used.
#'
#' @return A character vector of slot names if \code{unique_only = TRUE},
#'   otherwise a list of character vectors (per run).
#' @seealso \code{\link{input_keys}}, \code{\link{input_keys.ModelInput}}
#'   
#' @author Andrew Roberts
#' @export
input_keys.EnsembleInputBroadcast <- function(x, ...) {
  names(x$slots)
}


#' Get metadata names
#'
#' Returns the names of metadata fields present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputBroadcast} object.
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
metadata_names.EnsembleInputBroadcast <- function(x, ...) {
  .NotYetImplemented()
}


#' Convert an EnsembleInput to broadcast format
#'
#' Converts an \code{EnsembleInput} object (e.g., in list or table format)
#' into an \code{EnsembleInputBroadcast} object. The result will still inherit
#' from \code{EnsembleInput}.
#'
#' @param An \code{EnsembleInput}
#' @param ... Additional arguments to be used by methods.
#' 
#' @returns An \code{EnsembleInputBroadcast} object.
#' 
#' @author Andrew Roberts
#' @export
as_ensemble_input_broadcast <- function(x, ...) {
  UseMethod("as_ensemble_input_broadcast")
}


#' @export
as_ensemble_input_broadcast.default <- function(x, ...) {
  raise_default_method_error(x, "as_ensemble_input_broadcast")
}


#' Identity function - input is already an \code{EnsembleInputBroadcast}.
#' @export
as_ensemble_input_broadcast.EnsembleInputBroadcast <- function(x, ...) {
  x
}


#' Get ModelInput for Specific Run from EnsembleInputBroadcast
#'
#' Returns the \code{ModelInput} object for run identified by the specified
#' \code{run_id}. 
#'
#' @param x An \code{EnsembleInputBroadcast}
#' @param run_id character(1), the run ID.
#' @param ... Further arguments passed to methods.
#'
#' @return The \code{ModelInput} for the selected run. Throws error if 
#'  \code{run_id} is not found.
#' 
#' @author Andrew Roberts
#' @export
get_run_input.EnsembleInputBroadcast <- function(x, run_id, ...) {
  stopifnot(is_character_scalar(run_id))  

  if(!(run_id %in% rownames(x$mat_rule))) raise_run_id_not_found_error(run_id)
  
  # Construct ModelInput object.
  slot_idxs <- x$mat_rule[run_id,] # Has names set to slot names
  slots <- instantiate_slots(slot_idxs, x$slots)

  unflatten_model_input(slots)
}


#' Replace Index Matrix with String Label Matrix for Easier Interpretation
#' 
#' Convenience function to help visualize the ensemble inputs. In particular,
#' returns a matrix of the same shape as \code{x$mat_rule}, where the integer
#' indices have been replaced by character labels of the form 
#' \code{<slot_name>_j} for the jth value of a slot.
#' 
#' @param x An \code{EnsembleInputBroadcast}.
#'  
#' @returns character matrix. The \code{(i,j)} entry contains the value
#'  \code{paste(input_keys(x)[[j]], x$mat_rule[i,j], sep="_")}. Note that this
#'  is just a label that provides the index of the value within the slot. This
#'  is NOT the slot value itself (which may be a structured object, not just
#'  a string).
#'  
#' @author Andrew Roberts
#' @export
get_labeled_mat_rule <- function(x) {
  check_ensemble_input_broadcast_type(x)
  run_table <- visualize_slot_grid(x$mat_rule, input_keys(x))
  rownames(run_table) <- rownames(x$mat_rule)
  
  return(run_table)
}


# Default to Cartesian product
ensemble_broadcast_from_tree <- function(tree, keys, slot_groups=NULL,
                                         group_broadcast_rules=NULL) {
  
  slot_list <- slot_list_from_tree(tree, keys)
  rule <- .determine_tree_broadcast_rule(keys, slot_groups, group_broadcast_rules)
  
  EnsembleInput(rule, slot_list)
}


#' Extract slot lists from a hierarchical tree
#'
#' This function traverses a hierarchical \code{list} structure and collects 
#' values corresponding to specified slot names. If an element of the tree 
#' matches a slot name, its value is interpreted as a list of values; if the 
#' value is not a list, it is wrapped in a list of length one. All such values 
#' are concatenated into the corresponding slot in the output.
#'
#' @param tree A hierarchical \code{list} structure, possibly nested, 
#' containing slot elements.
#' @param keys A character vector of slot keys to extract.
#'
#' @return A named \code{list} with one element for each slot in 
#' \code{input_keys}. Each element is itself a \code{list} of collected values.
#'
#' @details
#' * If a slot is not found anywhere in \code{tree}, it is included in the 
#'   result as an empty \code{list}, and a warning is issued.  
#' * The elements of the sub-lists in the output may be any R object.  
#' * Output guarantees consistent slot ordering (given by \code{input_keys}).  
#' * Slots are identified in the tree by name. An element matching a slot name
#'   is assumed to be a list of values within that slot. If not a list, assumed
#'   to be a single value.
#'
#' @examples
#' site_settings <- list(
#'   site1 = list(met = "met_site1",
#'                ic = list("ic_site1_1", "ic_site1_2", "ic_site1_3")),
#'   site2 = list(met = "met_site2",
#'                ic = list("ic_site2_1", "ic_site2_2", "ic_site2_3")),
#'   site3 = list(met = "met_site3",
#'                ic = list("ic_site3_1", "ic_site3_2", "ic_site3_3")),
#'   par = list("p1", "p2")
#' )
#'
#' .slot_list_from_tree(site_settings, c("met", "ic", "par"), depth=1) 
#' .slot_list_from_tree(site_settings, c("met", "par"))
#' .slot_list_from_tree(site_settings, c("met", "par", "not_a_slot"))
#'
#' @export
slot_list_from_tree <- function(tree, keys) {
  
  result <- setNames(vector("list", length(keys)), keys)
  found   <- setNames(logical(length(keys)), keys)
  
  recurse <- function(node) {
    if (!is.list(node)) return(NULL)
    for (nm in names(node)) {
      if (nm %in% keys) {
        val <- node[[nm]]
        if (!is.list(val)) {
          val <- list(val)
        }
        result[[nm]] <<- c(result[[nm]], val)
        found[[nm]] <<- TRUE
      } else {
        recurse(node[[nm]])
      }
    }
  }
  
  recurse(tree)
  
  # warn about missing slots
  for (nm in keys) {
    if (!found[[nm]]) {
      warning(sprintf("Slot '%s' not found in tree. Slot will be empty.", nm))
    }
  }
  
  result
}


#' @export
print.EnsembleInputBroadcast <- function(x, ...) {
  cat("<EnsembleInputBroadcast>\n")
  print(get_labeled_mat_rule(x))
}


.determine_tree_broadcast_rule <- function(keys, slot_groups, group_broadcast_rules) {
  
  if(is.null(slot_groups) && is.null(group_broadcast_rules)) {
    rule <- rule_cartesian
  } else if(is.null(slot_groups)) {
    if(is.list(group_broadcast_rules)) group_broadcast_rules <- group_broadcast_rules[[1]]
    
    assertthat::assert_that(is.function(group_broadcast_rules),
                            msg=paste0("If `slot_groups` is NULL, then `group_broadcast_rules` ",
                                       "must be a single broadcast rule."))
    rule <- group_broadcast_rules
  } else if(!is.null(slot_groups) && !is.null(group_broadcast_rules)) {
    assert_that(length(slot_groups) == length(group_broadcast_rules))
    slot_idx_groups <- .slot_group_names_to_idx(slot_groups, keys)
    rule <- get_composite_rule(groups=slot_idx_groups, rules=group_broadcast_rules)
  } else {
    stop("If `slot_groups` is specified, `group_broadcast_rules` cannot be NULL.")
  }
  
  return(rule)
}


.slot_group_names_to_idx <- function(slot_groups, keys) {
  
  assert_that(is.character(keys) && !anyDuplicated(keys))
  assert_that(is.list(slot_groups))
  
  all_names <- Reduce(c, slot_groups)
  assert_that(is.character(all_names))
  
  if((anyDuplicated(all_names) > 0) || !setequal(all_names, keys)) {
    stop("`slot_groups` must be a (disjoint) partition of `keys`.")
  }
  
  lapply(slot_groups, function(x) match(x, keys))
}


#' Compute index matrix from broadcast rule
#' 
#' Helper function which constructs \code{mat_rule} by applying the 
#' broadcast rule function to the slot list.
#' 
#' @param broadcast_rule A broadcast rule function. 
#' @param slots A named list of slot value sets. The jth element of \code{slots}
#'  is itself a list, containing a unique set of values for that slot.
#'  
#' @returns integer matrix with \code{length(slots)} columns, provided the 
#'  broadcast rule is valid.
#' @author Andrew Roberts
.broadcast_slots <- function(slots, broadcast_rule) {
  lens <- vapply(slots, n_vals_in_slot, integer(1))
  names(lens) <- names(slots)
  
  broadcast_rule(lens)
}


#' Get the number of values stored in a slot value set.
n_vals_in_slot <- function(x) {
  if(is.list(x)) length(x)
  else nrow(.wrap_vector_as_flat_array(x))
}


#' Concatenate two EnsembleInputBroadcast objects
#' 
#' @details
#' When slots are shared across the objects, the slot values are appended
#' (no attempt is made to match values across objects). The objects do not
#' need to have the same set of input slots.
#' Currently this drops ensemble metadata, and defines new run IDs.
#'
#' @param x,y \code{EnsembleInputList} objects
#' @returns Concatenated \code{EnsembleInputList}
#' 
#' @author Andrew Roberts
.concat_ensemble_input_broadcasts <- function(x, y) {
  
  # Create new slots lists (union of the slots of x and y).
  input_keys_x <- input_keys(x)
  input_keys_y <- input_keys(y)
  new_input_keys <- union(input_keys_x, input_keys_y)
  new_slots <- lapply(new_input_keys, function(nm) c(x$slots[[nm]], y$slots[[nm]]))
  names(new_slots) <- new_input_keys
  
  # Create new index matrix.
  n_runs_x <- n_runs(x)
  n_runs_y <- n_runs(y)
  new_n_runs <- n_runs_x + n_runs_y
  new_run_ids <- paste0("run_", seq_len(new_n_runs))
  
  new_mat_rule <- matrix(nrow = new_n_runs,
                        ncol = length(new_input_keys),
                        dimnames = list(new_run_ids, new_input_keys))
  
  for(i in seq_along(new_input_keys)) {
    nm <- new_input_keys[[i]]
    
    if(nm %in% input_keys_x) new_mat_rule[1:n_runs_x, nm] <- x$mat_rule[,nm]
    if(nm %in% input_keys_y) {
      shift <- length(x$slots[[nm]])
      new_mat_rule[(n_runs_x+1L):new_n_runs, nm] <- y$mat_rule[,nm] + shift
    }
  }
  
  # Construct new EnsembleInputBroadcast
  EnsembleInput(new_mat_rule, new_slots)
}

