# forward/ensemble_input_table.r
#
# Depends: model_input.r, ensemble_input.r, ensemble_input_list.r, ensemble_input_broadcast.r

#' Construct ensemble model input in table format
#' 
#' Constructs an object of class \code{EnsembleInputTable}, which is a 
#' \code{(n_runs, n_slots)} tibble with each row defining the inputs for 
#' a single run.
#' 
#' @details
#' The column names are set to \code{input_keys(ens_input)}, where 
#' \code{ens_input} is an \code{EnsembleInput} object. The prefix \code{slot_}
#' is prepended to these column names. If different inputs
#' have different slots, then this will result in \code{NA} values in the
#' table. Objects of the \code{EnsembleInputTable} class also inherit from 
#' \code{EnsembleInput}. The column name \code{run_id} is a special reserved
#' name that will not be treated as a slot. By default, all columns other than
#' \code{run_id} will be interpreted as slots. To include metadata columns 
#' that are not slots or \code{run_id}, the slot columns can be explicitly
#' be provided with the \code{slot_names} argument. In this case, all columns
#' other than \code{c(run_id, slot_names)} will be treated as metadata.
#' The prefix \code{metadata_} will be appended to all of these columns. 
#' The table is required to be a \code{tibble} due to its support of list 
#' columns; input slots are not required to be atomic, so the table columns
#' in this representation must be able to store arbitrary structured objects.
#'
#' @param input_table A tibble (\code{df_tbl}) or object that can be converted 
#'  to a tibble. An \code{NA} value in the \code{(i,j)} entry is interpreted as 
#'  run \code{i} not having an input in slot \code{j}.
#' @param slot_names Optional, character vector specifying the column names of 
#'  \code{input_table} that correspond to input slots.
#'  
#' @return An object of class \code{EnsembleInputTable}, inheriting from 
#'  \code{EnsembleInput}.
#' @export
EnsembleInput.tbl_df <- function(input_table, slot_names=NULL) {

  x <- .new_ensemble_input_table(input_table, slot_names)
  validate_ensemble_input_table(x)
  
  return(x)
}


#' Internal constructor for EnsembleInputTable
#' 
#' Instantiates an \code{EnsembleInputTable} object. No validation is done in 
#' this function. See \code{\link{EnsembleInput.tbl_df}} for the public interface
#' and additional documentation.
#' 
#' @param input_table A tibble (\code{df_tbl}) or object that can be converted 
#'  to a tibble. An \code{NA} value in the \code{(i,j)} entry is interpreted as 
#'  run \code{i} not having an input in slot \code{j}.
#' @param slot_names Optional, character vector specifying the column names of 
#'  \code{input_table} that correspond to input slots.
#' 
#' @returns An object of class \code{EnsembleInputTable}, inheriting from 
#'  \code{EnsembleInput}.
#' 
#' @seealso \code{\link{EnsembleInput}}
#' @author Andrew Roberts
.new_ensemble_input_table <- function(input_table, slot_names) {
  
  # Attempt conversion to tibble.
  input_table <- tryCatch(
    tibble::as_tibble(x),
    error = function(e) {
      stop("Conversion to tibble failed when trying to create EnsembleInputTable: ", e$message)
    }
  )
  
  # Default run IDs.
  if(!("run_id" %in% names(input_table))) {
    input_table <- input_table %>% mutate(run_id=paste0("run_", dplyr::row_number()))
  }
  
  # All non slot column and non run ID columns are interpreted as metadata.
  metadata_names <- setdiff(names(input_table), c("run_id", slot_names))
  
  # Tag slot and metadata columns
  input_table <- input_table %>% rename_with(~paste0(INPUT_PREFIX, .x), all_of(slot_names))
  input_table <- input_table %>% rename_with(~paste0(METADATA_PREFIX, .x), all_of(metadata_names))
  
  input_table <- set_ensemble_input_table_class(input_table)
  return(input_table)
}


#' Defines class hierarchy for EnsembleInputTable
#' 
#' Given an R object, returns an updated version of the object where the 
#' class attribute has been set to inherit directly from \code{EnsembleInputTable},
#' followed by \code{EnsembleInputTable}, and then the classes which define 
#' a \code{tibble}.
#' 
#' @param x An R object
#' 
#' @returns \code{x} with updated class attribute.
#' 
#' @author Andrew Roberts
set_ensemble_input_table_class <- function(x) {
  class(x) <- c("EnsembleInputTable", "EnsembleInput", class(tibble::tibble()))
  x
}


#' Check if object inherits from \code{EnsembleInputTable}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{EnsembleInputTable}.
#' 
#' @author Andrew Roberts
#' @export
is_ensemble_input_table <- function(x) {
  is_ensemble_input(x) && inherits(x, "EnsembleInputTable")
}


#' Validate an EnsembleInputTable
#'
#' Validates the general structure of a \code{EnsembleInputTable} object. 
#'
#' @details
#' Must be a tibble and include a \code{run_id} column with unique values.
#' All other columns must start with \code{slot_} or \code{metadata_}.
#'
#' @param x An object.
#' @return Invisibly returns \code{TRUE} if validation tests are passed, 
#'  or throws an error if invalid.
#'  
#' @author Andrew Roberts
#' @export
validate_ensemble_input_table <- function(x) {
  if(!is_ensemble_input_table(x)) {
    stop("`x` is not an `EnsembleInputTable` object.")
  }
  
  if(!tibble::is_tibble(x)) {
    stop("EnsembleInputTable must be a tibble.")
  }
  
  if(!("run_id" %in% names(x))) {
    stop("`EnsembleInputTable$run_id` column is missing.")
  }
  
  if(!dplyr::n_distinct(x$run_id) == nrow(x)) {
    stop("`EnsembleInputTable$run_id` contains duplicate values.")
  }
  
  tagged_cols <- c("run_id", 
                   .get_col_block_names(x, INPUT_PREFIX, strip_prefix=FALSE),
                   .get_col_block_names(x, METADATA_PREFIX, strip_prefix=FALSE))
  invalid_cols <- setdiff(names(x), tagged_cols)
    
  if(length(invalid_cols) > 0L) {
    stop("EnsembleInputTable columns must be `run_id` or tagged with ",
         "`input_` or `metadata_`. Tibble has extra columns: ",
         paste(invalid_cols, collapse=", "))
  }
  
  invisible(TRUE)
}


#' Get input slot names
#'
#' Returns the names of slots (input fields) present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputTable} object.
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
slot_names.EnsembleInputTable <- function(x, ...) {
  .get_col_block_names(x, INPUT_PREFIX, strip_prefix=TRUE)
}


#' Get metadata names
#'
#' Returns the names of metadata fields present in the \code{ModelInput}
#' objects making up the ensemble run.
#'
#' @param x An \code{EnsembleInputTable} object.
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
metadata_names.EnsembleInputTable <- function(x, ...) {
  .get_col_block_names(x, METADATA_PREFIX, strip_prefix=TRUE)
}


#' Convert an EnsembleInput to table format
#'
#' Converts an \code{EnsembleInput} object (e.g., in list or broadcast format)
#' into an \code{EnsembleInputTable} object. The result will still inherit
#' from \code{EnsembleInput}.
#'
#' @param An \code{EnsembleInput}
#' @param ... Additional arguments to be used by methods.
#' 
#' @returns An \code{EnsembleInputTable} object.
#' 
#' @author Andrew Roberts
#' @export
as_ensemble_input_table <- function(x, ...) {
  UseMethod("as_ensemble_input_table")
}


#' @export
as_ensemble_input_table.default <- function(x, ...) {
  raise_default_method_error(x, "as_ensemble_input_table")
}


#' Identity function - input is already an \code{EnsembleInputTable}.
#' @export
as_ensemble_input_table.EnsembleInputTable <- function(x, ...) {
  x
}


#' Convert an EnsembleInputList to EnsembleInputTable
#'
#' @param An \code{EnsembleInputList}
#' @param ... Not used
#' 
#' @returns An \code{EnsembleInputTable} object.
#' 
#' @author Andrew Roberts
#' @export
as_ensemble_input_table.EnsembleInputList <- function(x, ...) {

  all_slot_names <- input_keys(x)
  all_metadata_names <- metadata_keys(x)
  all_run_ids <- run_ids(x)
  model_input_list <- x$inputs
  
  # Create list of row information. 
  make_row <- function(run_id) .make_ensemble_input_table_row(run_id, 
                                                              model_input_list, 
                                                              all_slot_names, 
                                                              all_metadata_names)
  row_list <- lapply(all_run_ids, make_row) 
  
  # run_id is a character column; all other columns default to list column.
  tbl <- tibble::tibble(run_id=all_run_ids)

  for(slot_col in all_slot_names) {
    slot_col_with_prefix <- paste0(INPUT_PREFIX, slot_col)
    tbl[[slot_col_with_prefix]] <- lapply(row_list, function(x) x[[slot_col]])
  }
  
  for(metadata_col in all_metadata_names) {
    metadata_col_with_prefix <- paste0(METADATA_PREFIX, metadata_col)
    tbl[[metadata_col_with_prefix]] <- lapply(row_list, function(x) x[[metadata_col]])
  }
  
  tbl <- set_ensemble_input_table_class(tbl)
  validate_ensemble_input_table(tbl)
  return(tbl)
}


#' Convert an EnsembleInputBroadcast to EnsembleInputTable
#'
#' @param An \code{EnsembleInputBroadcast}
#' @param ... Not used
#' 
#' @returns An \code{EnsembleInputTable} object.
#' 
#' @author Andrew Roberts
#' @export
as_ensemble_input_table.EnsembleInputBroadcast <- function(x, ...) {
  tbl <- instantiate_slot_grid(x$mat_rule, x$slots, include_rownames=TRUE, 
                               rownames_col="run_id")
  
  slot_colnames <- setdiff(names(tbl), "run_id")
  tbl <- tbl %>% dplyr::rename_with(~paste0(INPUT_PREFIX, .x), .cols=slot_colnames)
  
  tbl <- set_ensemble_input_table_class(tbl)
  validate_ensemble_input_table(tbl)
  
  return(tbl)
}


#' Return character vector of run IDs
#'
#' See \code{\link{run_ids}}
#'
#' @param An \code{EnsembleInputTable}
#' @param ... Not used
#' 
#' @return A character vector of run IDs of length \code{n_runs(x)}.
#' @seealso \code{\link{run_ids}}
#' 
#' @author Andrew Roberts
#' @export
run_ids.EnsembleInputTable <- function(x, ...) {
  x$run_id
}


#' Get ModelInput for Specific Run from EnsembleInputTable
#'
#' Returns the \code{ModelInput} object for run identified by the specified
#' \code{run_id}. 
#'
#' @param x An \code{EnsembleInputTable}
#' @param run_id character(1), the run ID.
#' @param ... Further arguments passed to methods.
#'
#' @return The \code{ModelInput} for the selected run. Throws error if 
#'  \code{run_id} is not found.
#' 
#' @author Andrew Roberts
#' @export
get_run_input.EnsembleInputTable <- function(x, run_id, ...) {
  stopifnot(is_character_scalar(run_id))
  
  # Avoid clash with column name.
  rid <- run_id
  input_row <- dplyr::filter(x, run_id == rid)
  
  if(nrow(input_row) == 0L) raise_run_id_not_found_error(run_id)
  
  # Construct ModelInput object.
  slot_block <- .get_col_block(input_row, INPUT_PREFIX, strip_prefix=TRUE)
  metadata_block <- .get_col_block(input_row, INPUT_PREFIX, strip_prefix=TRUE)
  model_input_args <- c(as.list(slot_block), list(metadata=as.list(metadata_block)))
  
  do.call(ModelInput, model_input_args)
}


#' Extract subset of column names with matching prefix
#'
#' Return the subset of column names that start with the pattern specified by
#' the argument \code{prefix}. Optionally strip this prefix out of the column
#' names before returning. The function \code{\link{.get_col_block}}
#' but returns the actual subsetted table rather than just the column names.
#'
#' @param x A \code{data.frame}.
#' @param prefix character, the string prefix.
#' @param strip_prefix logical, if \code{TRUE} removes the prefix from the
#'  names. Otherwise returns the names unchanged.
#' 
#' @returns A character vector column names matching the pattern, potentially
#'  with the prefix removed. Returns \code{character(0)} is no column names match
#'  the pattern.
#' 
#' @author Andrew Roberts
.get_col_block_names <- function(x, prefix, strip_prefix=FALSE) {
  nm <- names(x)
  col_block <- nm[startsWith(nm, prefix)]
  
  if(strip_prefix) sub(paste0("^", prefix), "", col_block)
  else col_block
}


#' Extract subset of columns with names matching prefix
#'
#' Return the subset of columns whose names start with the pattern specified by
#' the argument \code{prefix}. Optionally strip this prefix out of the column
#' names before returning. The function \code{\link{.get_col_block_names}}
#' is similar but only returns column names.
#'
#' @param x A \code{data.frame}.
#' @param prefix character, the string prefix.
#' @param strip_prefix logical, if \code{TRUE} removes the prefix from the
#'  names. Otherwise the names are unchanged.
#' 
#' @returns A \code{data.frame} with the subset of columns selected. If 
#'  \code{strip_prefix = TRUE} then the columns are renamed to remove the prefix.
#'  If a column name is identical to the prefix, an error will be thrown. If
#'  no columns are selected, a zero column tibble is returned.
#' 
#' @author Andrew Roberts
.get_col_block <- function(x, prefix, strip_prefix=FALSE) {
  
  col_block <- dplyr::select(x, starts_with(prefix))
  if(ncol(col_block) == 0L) return(col_block)
  
  if(strip_prefix) col_block %>% dplyr::rename_with(~sub(paste0("^", prefix), "", .))
  else col_block
}


#' Helper function for converting ensemble input list to table
#'
#' Used by \code{as_ensemble_input_table.EnsembleInputList}. Returns a list
#' with data to create one row of a \code{EnsembleInputTable} object, excluding
#' the \code{run_id} column.
#'
#' @param run_id character, used to select element of \code{input_list}.
#' @param input_list list of \code{ModelInput} objects. Names attribute set to run IDs.
#' @param slot_names character, the full vector of slot names that are being used
#'  to construct the table. The slot names for the particular input
#'  \code{input_list[[run_id]]} may be a strict subset of \code{slot_names}.
#' @param metadata_names character, same as \code{slot_names} but for the metadata.
#' 
#' @returns list with values for all slot and metadata columns for the row of 
#'  the table associated with \code{run_id}. The \code{run_id} itself is not
#'  included in the return.
#' 
#' @author Andrew Roberts
.make_ensemble_input_table_row <- function(run_id, input_list, slot_names, 
                                           metadata_names) {
  
  model_input <- input_list[[run_id]]
  slots <- input_slots(model_input)
  metadata <- metadata_slots(model_input)
  
  row_slots <- lapply(slot_names, 
                  function(nm) {
                    if(nm %in% names(slots)) slots[[nm]] else NA
                  })
  
  row_metadata <- lapply(metadata_names, 
                    function(nm) {
                      if(nm %in% names(metadata)) metadata[[nm]] else NA
                    })
  
  names(row_slots) <- slot_names
  names(row_metadata) <- metadata_names
  c(row_slots, row_metadata)
}
