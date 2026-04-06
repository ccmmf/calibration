# forward_model/broadcast_rules.r


#' API for Constructing Broadcast Rule Function
#'
#' Provides a high-level interface to \code{\link{construct_composite_rule}}.
#' 
#' @details
#' \code{axis_names} defines a set of named axes/dimensions.
#' \code{list_rule} is a list that determines how the axes should be broadcast.
#' The list is of the format \code{list(recycle = c("a", "b"), match = c("c", "d"))}. 
#' In this example, the values in the axes \code{a} and \code{b} will be recycled to 
#' the same length, while the values in the axes \code{c} and \code{d} will 
#' be matched in a one-to-one fashion. A Cartesian product will then be taken 
#' across the resulting two sets of combinations. By default, a product will
#' also be taken with respect to any axes not explicitly named in the rule.
#' If \code{drop_absent_axes = TRUE} then any axes not explictly named will be
#' dropped, so that the broadcast rule operates only on a subset of the axes.
#' 
#' When operating on a single axis -- e.g., \code{c} in 
#' \code{list(recycle = c("a", "b"), identity = "c")} most of the supported broadcast
#' rules will have the effect of the identity function. For clarity, it is 
#' recommended to explicitly use the identity rule \code{identity} in this case,
#' which is only defined with respect to a single axis.
#' 
#' @param axis_names character, unique axis names.
#' @param list_rule named list, with names set to valid broadcast rules and 
#'  values set to character vectors defining the axis groups to which each
#'  rule will be applied. Axis names cannot be repeated across multiple rules.
#'  At present, valid rules include 
#'  \code{"recycle", "match", "broadcast", "product", "identity"}.
#' @param drop_absent_axes logical(1), if \code{TRUE} then any axes in \code{axis_names}
#'  but not included in \code{list_rule} will be dropped so that the constructed
#'  broadcast rule operates only on the remaining subset of axes. If \code{FALSE},
#'  (default), then a Cartesian product is taken with all unnamed axes.
#'  
#' @returns A function representing a broadcast rule.
#' 
#' @seealso \code{\link{construct_composite_rule}}
#' 
#' @author Andrew Roberts
#' @export
get_broadcast_rule <- function(axis_names, list_rule, drop_absent_axes=FALSE) {
  
  res <- .standardize_list_rule(axis_names, list_rule, drop_absent_axes)
  axis_names <- res$axis_names; list_rule <- res$list_rule
  rule_funs <- lapply(names(list_rule), match.fun)
  
  construct_composite_rule(groups=list_rule, rules=rule_funs)
}


#' Combine rules by grouping axes
#'
#' Constructs a new broadcasting rule function by combining existing rule
#' functions. The function applies the sub-rules to "axis groups", and then 
#' takes the Cartesian product of the resulting combinations.
#'
#' @param groups A list of integer vectors (giving axis indices), or character
#'  vectors (giving axis names), where the vectors define the axis subset that
#'  will be handled by each sub-rule.
#' @param rules A list of rule functions, one per axis group.
#' 
#' @returns A new rule function, with signature \code{fun(lens)}.
#' 
#' @details
#' This is a lower level version of \code{\link{get_broadcast_rule}}; the
#' latter has more safeguards and is generally recommended for most use cases.
#' While the higher-level API requires named axes, this function supports
#' indexes either by name or integer position. If \code{groups} contains 
#' axis names, then the returned rule function \code{fun(lens)} will require 
#' \code{lens} to be a named vector. If \code{groups} contains integer indices
#' then there is no constraint on \code{lens}, but it must be kept in mind that
#' \code{lens} will be subsetted by index. It is generally recommended to use
#' names, and this recommendation is enforced in \code{\link{get_broadcast_rule}}.
#' There is no mixing of indexing strategy allowed across groups; all must be
#' integer or all must be character.
#' 
#' @examples
#' # By index
#' lens <- c(2, 2, 4, 1)
#' rule_composite <- construct_composite_rule(groups = list(1:2, 3:4), 
#'                                            rules = list(rule_match, rule_recycle))
#' rule_composite(lens) # Outputs 8 by 4 matrix.
#' 
#' # By name (recommended)
#' lens <- c(w=2, x=2, y=4, z=1)
#' rule_composite <- construct_composite_rule(groups = list(c("w", "x"), c("y", "z")), 
#'                                            rules = list(rule_match, rule_recycle))
#' rule_composite(lens) # Same output as before.
#' rule_composite(c(2,2,4,1)) # Trying to index by position will throw error
#' 
#' @seealso \code{\link{get_broadcast_rule}}
#' 
#' @author Andrew Roberts
#' @export
construct_composite_rule <- function(groups, rules) {
  force(groups); force(rules)
  
  if(length(groups) != length(rules)) {
    stop("`construct_composite_rule()` requires `groups` and `rules` to be lists of equal length.")
  }
  
  index_by_name <- is.character(groups[[1]])

  # Composite rule function
  function(lens) {
    
    if(index_by_name) {
      assert_that(assertthat:::is.named(lens),
                  msg="`lens` must provide axis names in names attribute.")
    }
    
    # Apply each rule to its group
    group_mats <- vector("list", length(groups))
    for(k in seq_along(groups)) {
      group_axes <- groups[[k]]
      rule_func <- rules[[k]]
      group_mats[[k]] <- rule_func(lens[group_axes])
    }
    
    # Cartesian product of the sub-results
    group_idx_lists <- lapply(group_mats, function(x) seq_len(nrow(x)))
    index_grid <- do.call(expand.grid, group_idx_lists)
    out <- matrix(NA_integer_, nrow=nrow(index_grid), ncol=length(lens))
    colnames(out) <- names(lens)
    
    for(row_idx in seq_len(nrow(index_grid))) {
      for(group_idx in seq_along(groups)) {
        result_row <- index_grid[row_idx, group_idx]
        output_axes <- groups[[group_idx]]
        out[row_idx, output_axes] <- group_mats[[group_idx]][result_row,]
      }
    }
    
    return(out)
  }
}


#' Identity broadcast rule
#' 
#' Operates on a single axis, and leaves the axis unchanged.
#'
#' @param lens integer(1), the length of the single axis.
#' @returns The single column matrix containing the sequence \code{1:lens}.
#' 
#' @author Andrew Roberts
#' @export
rule_identity <- function(lens) {
  .check_lens(lens)
  
  if(length(lens) != 1L) {
    stop("`rule_identity()` can only operate on a single axis.")
  }
  
  matrix(seq_len(lens), ncol=1L)
}


#' Cartesian product broadcast rule
#' 
#' Full cartesian product of slot values.
#'
#' @param lens Integer vector of dimension/slot lengths.
#' @return A matrix of dimension (prod(lens), length(lens)).
#'
#' @examples
#' # A Cartesian product of three dimensions of size 2, 3 and 2.
#' # Outputs a matrix with 12 rows and 3 columns.
#' rule_product(c(2, 3, 2))
#' 
#' @author Andrew Roberts
#' @export
rule_product <- function(lens) {
  .check_lens(lens)
  grids <- do.call(expand.grid, lapply(lens, seq_len))
  mat <- as.matrix(grids)
  colnames(mat) <- NULL
  
  return(mat)
}


#' Match-by-position rule
#'
#' Each run combines elements at the same position across slots.
#' Slots must all have the same length.
#'
#' @param lens Integer vector of slot lengths.
#' @return A matrix of dimension \code{(n, length(lens))}.
#' # Three slots, each of length 4.
#' # Output: a 4 x 3 matrix, with each row corresponding to positions 1, 2, 3, 4.
#' rule_match(c(4, 4, 4))
#'
#' @author Andrew Roberts
#' @export
rule_match <- function(lens) {
  .check_lens(lens)
  
  if(length(unique(lens)) != 1L) {
    stop("`rule_match()` requires dimension lengths in `lens` to all be equal.")
  }
  
  n <- lens[1]
  idx <- matrix(rep(seq_len(n), each=length(lens)),
                ncol=length(lens), byrow=TRUE)
  return(idx)
}


#' Rule to match and broadcast slot indices
#'
#' Generates a matrix of slot indices for broadcasting, similar to array broadcasting
#' in Python's NumPy, by matching slot lengths. For each slot (dimension), if the
#' corresponding length in \code{lens} is 1, the index is recycled to match the maximal
#' dimension size; if it matches the maximal size, indices range from 1 to that size.
#' Throws an error if a slot length is not 1 or maximal.
#'
#' @param lens An integer vector specifying the lengths of each slot (dimension).
#'   Each element should be either 1 (scalar, to be broadcast) or max(\code{lens}),
#'   representing the dimension size for that slot.
#' @return An integer matrix with \code{max(lens)} rows and \code{length(lens)}
#'   columns. Each row represents one combination of broadcasted slot indices,
#'   with scalars repeated as needed.
#' @examples
#' rule_match(c(1, 3, 1))
#' #      [,1] [,2] [,3]
#' # [1,]    1    1    1
#' # [2,]    1    2    1
#' # [3,]    1    3    1
#'
#' rule_match(c(3, 1, 3))
#' #      [,1] [,2] [,3]
#' # [1,]    1    1    1
#' # [2,]    2    1    2
#' # [3,]    3    1    3
#'
#' # Invalid usage:
#' # rule_match(c(2, 3))
#' # Error: Lengths in `lens` must be either 1 or max(lens) for broadcasting.
#'
#' @seealso For general information on broadcasting in array programming,
#'   see NumPy or rray documentation.
#'
#' @author Andrew Roberts
#' @export
rule_broadcast <- function(lens) {
  .check_lens(lens)
  
  n <- max(lens)
  idx <- matrix(NA_integer_, nrow=n, ncol=length(lens))
  
  for(j in seq_along(lens)) {
    if(lens[j] == 1L) {
      idx[,j] <- 1L # broadcast the scalar index 1
    } else if(lens[j] == n) {
      idx[,j] <- seq_len(n)
    } else {
      stop("Lengths in `lens` must be either 1 or max(lens) for broadcasting.")
    }
  }
  
  return(idx)
}


#' Create recycled slot indices for broadcasting along specific axes
#'
#' Generates a matrix of indices for each slot (dimension), recycling shorter axes
#' so their indices repeat until the longest length is reached. Throws an error if
#' the lengths are not compatible for recycling (i.e., all lens must divide the maximal length).
#'
#' @param lens Integer vector of lengths for each slot (dimension).
#' @return An integer matrix of shape (\code{max_len}, \code{length(lens)}), where
#'   each column is the recycled sequence of indices for that axis.
#' @examples
#' # Recycles: first axis (length 3) recycled to match second axis (length 6)
#' recycle_indices(c(3, 6))
#' # returns:
#' #      [,1] [,2]
#' # [1,]    1    1
#' # [2,]    2    2
#' # [3,]    3    3
#' # [4,]    1    4
#' # [5,]    2    5
#' # [6,]    3    6
#'
#' # Error: incompatible recycling
#' # recycle_indices(c(4, 6))
#' # Error: All dimensions in 'lens' must evenly divide the maximal length for recycling.
#'
#' @author Andrew Roberts
#' @export
rule_recycle <- function(lens) {
  .check_lens(lens)

  max_len <- max(lens)
  if(any(max_len %% lens != 0)) {
    stop("rule_recycle(): All dimensions in `lens` must evenly divide the maximal length for recycling.")
  }
  
  # Create recycled indices for each slot
  idx_mat <- vapply(lens, function(l) rep(seq_len(l), length.out=max_len), integer(max_len))

  # Ensure matrix return value even if `lens` is length 1
  idx_mat <- as.matrix(idx_mat)
  colnames(idx_mat) <- NULL
  idx_mat
}


#' Visualize an index matrix by labeling each slot
#'
#' Returns a character matrix the same shape as \code{idx_mat},
#' where each entry is 
#' \code{paste(slot_names[column], idx_mat[row, column], sep = "_")}.
#'
#' @param idx_mat Integer matrix of indices, with one column per slot.
#' @param slot_names Character vector of slot names (length must match \code{ncol(idx_mat)}).
#' @return Character matrix of same shape as idx_mat.
#' @examples
#' idx <- recycle_indices(c(2, 3))
#' visualize_slot_grid(idx, c("A", "B"))
#' #      [,1]  [,2]
#' # [1,] "A_1" "B_1"
#' # [2,] "A_2" "B_2"
#' # [3,] "A_1" "B_3"
#'
#' @author Andrew Roberts
#' @export
visualize_slot_grid <- function(idx_mat, slot_names) {
  
  if(!is.matrix(idx_mat) || !assertthat:::is.integerish(idx_mat)) {
    stop("`idx_mat` must be a matrix with integer entries.")
  }
  
  if(length(slot_names) != ncol(idx_mat)) {
    stop("Length of `slot_names` must match number of columns of `idx_mat`.")
  }
  
  name_map <- function(col_vals, slot_name) paste(slot_name, col_vals, sep="_")
  char_mat <- Map(name_map, as.data.frame(idx_mat), slot_names)
  name_mat <- do.call(cbind, char_mat)
  dim(name_mat) <- dim(idx_mat) # In case result was flattened to vector
  colnames(name_mat) <- slot_names
  
  
  return(name_mat)
}


#' Fill Index Vector with Slot Values
#'
#' Given an index vector \code{idx}, produces a list of the same length.
#' The values in this list are taken from \code{slots}. The names of 
#' \code{idx} specify which slot to pull from, and the values of \code{idx}
#' specify which value to pull from that slot (by index).
#' 
#' @details
#' The names attribute of \code{idx} contain slot names, so that 
#' \code{nm <- names(idx)[j]} is the slot corresponding to element \code{j}
#' of \code{idx}. Element \code{j} of the returned list is then set to
#' the value \code{slots[[nm]][idx[j]]}. Note that \code{idx} is allowed to 
#' be of different length than \code{slots}; i.e., slots may be repeated or 
#' not used at all. If any names of \code{idx} are not valid slots in \code{slot},
#' an error is thrown. An error is also thrown if a value in \code{slot} is outside
#' the index range of a particular slot.
#' 
#' @param idx named integer vector.
#' @param slots named list of slots, with names defining the slot names. Each 
#' element is either:
#'  1. a list of possible values for that slot
#'  2. a matrix, where each value is contained in one row (a vector is wrapped
#'    as a one row matrix).
#'
#' @return A list of length equal to the length of \code{idx} (see details).
#'
#' @author Andrew Roberts
#' @export
instantiate_slots <- function(idx, slots) {
  stopifnot(is_named_integer_vector(idx, check_unique_names=FALSE))
  stopifnot(is_named_list(slots, check_unique_names=TRUE))
  
  slot_names <- names(idx)
  
  # All slot names must exist in slots
  missing_slots <- setdiff(slot_names, names(slots))
  if(length(missing_slots) > 0L) {
    stop("Slot name(s) not found in `slots`: ", paste(missing_slots, collapse=", "))
  }
  
  slot_vals <- Map(function(nm, i) .get_slot_value(nm, i, slots),
                   slot_names, idx)
  names(slot_vals) <- slot_names
  
  return(slot_vals)
}


#' Fill Index Matrix with Slot Values
#'
#' For each row of idx_mat, uses indices to pull values from slots, constructing
#' a tibble (one column per slot). Handles structured (list-like) values as list 
#' columns.
#'
#' @param idx_mat Integer matrix, with each row an index tuple for the slots.
#' @param slots List of length ncol(idx_mat), each element is a list or vector 
#'    of possible values for that slot.
#' @param include_rownames logical(1), if \code{TRUE} and \code{idx_mat} has 
#'  rownames, then these rownames are added as a column with name specified by
#'  the argument \code{rownames_col}. If \code{FALSE}, this column is not added.
#' @param rownames_col, character(1), the name of the column that stores rownames.
#'  Only used if \code{include_rownames} is \code{TRUE}.
#'
#' @return A tibble where each row is a combination of slot values, and list-like 
#'    slot values become list columns. The tibble has the same number of rows
#'    as \code{idx_mat}.
#' 
#' @examples
#' library(tibble)
#' idx <- rule_recycle(c(4, 2))
#' slots <- list(
#'   c("A", "B", "C", "D"),
#'   list(1:2, 3:4) # slot 2 as a list column
#' )
#' instantiate_slot_grid(idx, slots)
#'
#' @author Andrew Roberts
#' @export
instantiate_slot_grid <- function(idx_mat, slots, include_rownames=FALSE,
                                  rownames_col="row_names") {
  assert_that(is.matrix(idx_mat))
  assert_that(assertthat:::is.integerish(idx_mat))
  assert_that(is.list(slots))
  assert_that(is.character(rownames_col) && assertthat:::is.scalar(rownames_col))
  assert_that(ncol(idx_mat) == length(slots))

  n_slots <- ncol(idx_mat)
  n_combs <- nrow(idx_mat)
  slot_colnames <- names(slots)
  if(is.null(slot_colnames)) slot_colnames <- paste0("slot", seq_len(n_slots))
  
  create_column <- function(j) {
    vals <- slots[[j]]
    idxs <- idx_mat[,j]
    
    # If vals is a list, always create a list column
    if (is.list(vals)) {
      lapply(idxs, function(idx) vals[[idx]]) # allow for slots of length 0
    } else if (is_array_like(vals)) {
      # Different values indexed by first dimension.
      vals <- wrap_as_multidim_array(vals)
      lapply(idxs, function(idx) index_first_dim(vals, idx, force_array_output=FALSE))
    } else {
      stop("Values in slot `", j, "` are stored in unsupported format.")
    }
  }
  
  cols <- lapply(seq_len(n_slots), create_column)
  names(cols) <- slot_colnames
  tbl <- tibble::as_tibble(cols)
  
  # Optionally add a column storing the rownames of `idx_mat`.
  if(include_rownames && !is.null(rownames(idx_mat))) {
    tbl <- tbl %>% dplyr::mutate(!!rownames_col := rownames(idx_mat))
  }
  
  return(tbl)
}


#' Extract Slot Value By Index
#'
#' Helper to extract a value from a particular slot. The slot is selected by
#' name, and the value in that slot is selected by index. No validation is 
#' done in this low-level helper. 
#' 
#' @param slot_name character(1), a string name in \code{names(slots)}
#' @param slot_idx integer(1), an index of the vector/list \code{slots[[slot_name]]}
#' @param slots named list, where each element is either a list or matrix (one row per value).
#'  Atomic vectors are wrapped as one row matrices.
#' 
#' @returns If the slot values are stored in a list, then returns
#'   \code{slots[[slot_name]][[slot_idx]]}. If a matrix, then returns
#'   \code{slots[[slot_name]][slot_idx,]}.
#'   
#' @author Andrew Roberts
.get_slot_value <- function(slot_name, slot_idx, slots) {
  slot_vals <- slots[[slot_name]]
  
  if(is.list(slot_vals)) slot_vals[[slot_idx]]
  else if(is_array_like(slot_vals)) {
    slot_vals <- wrap_as_multidim_array(slot_vals)
    index_first_dim(slot_vals, slot_idx, force_array_output=FALSE)
  } else {
    stop("`slots[[", slot_name, "]] must be a list or array-like.")
  }
}


#' Validation and processing helper function for \code{\link{get_broadcast_rule}}
#' 
#' @details
#' Returns updated/standardized versions of \code{axis_names} and \code{list_rules}.
#' These are standardized so that the axis names contained in the latter are 
#' guaranteed to perform a partition of all axes in \code{axis_names}. The names
#' of \code{list_rules} are also validated, and updated to align with the 
#' broadcast rule function names (e.g., \code{recycle} is updated to 
#' \code{rule_recycle}). If \code{drop_absent_axes} is \code{TRUE}, then 
#' the returned value for \code{axis_names} may contain a strict subset of the
#' axes in the original argument.
#' 
#' @param axis_names character, vector of unique axis names. 
#' @param list_rule named list, with names set to valid broadcast rules and 
#'  values set to character vectors defining the axis groups to which each
#'  rule will be applied. Axis names cannot be repeated across multiple rules.
#'  At present, valid rules include 
#'  \code{"recycle", "match", "broadcast", "product", "identity"}.
#' @param drop_absent_axes logical(1), if \code{TRUE} then any axes in \code{axis_names}
#'  but not included in \code{list_rule} will be dropped so that the constructed
#'  broadcast rule operates only on the remaining subset of axes. If \code{FALSE},
#'  (default), then a Cartesian product is taken with all unnamed axes.
#'
#' @returns list, with names \code{axis_names} and \code{list_rule}.
#' 
#' @author Andrew Roberts
.standardize_list_rule <- function(axis_names, list_rule, drop_absent_axes) {
 
  assert_that(anyDuplicated(axis_names) == 0L,
              msg="`axis_names` must be unique.")
  
  assert_that(is.list(list_rule) && assertthat:::is.named(list_rule),
              msg="`list_rule` must be a named list.")

  axis_names_in_rules <- do.call(c, list_rule)
  
  if(anyDuplicated(axis_names_in_rules) > 0L) {
    stop("Duplicate axis names found in `list_rules`.")
  }
  
  extra_names <- setdiff(axis_names_in_rules, axis_names)
  if(length(extra_names) > 0L) {
    stop("Axis names in `list_rule` not present in `axis_names`: ",
         paste(extra_names, collapse=", "))
  } 
  
  assert_that(length(axis_names_in_rules) > 0L,
              msg="`list_rule` cannot be empty; must specify at least one axis.")
  
  # Unspecified axes are either dropped, or assigned a Cartesian product
  # broadcast rule.
  missing_names <- setdiff(axis_names, axis_names_in_rules)
  if(length(missing_names) > 0L) {
    if(drop_absent_axes) {
      axis_names <- setNames(axis_names_in_rules, NULL)
    } else {
      # If only one axis is missing, assign identity rule (same effect as product
      # rule in this case, but improves clarity).
      rule_tag_for_missing <- if(length(missing_names) == 1L) "identity" else "product"
      list_rule <- c(list_rule, setNames(missing_names, rule_tag_for_missing))
    }
  }
  
  # Set names to broadcast rule function names.
  rule_tags <- names(list_rule)
  valid_rule_tags <- c("identity", "product", "recycle", "match", "broadcast")
  invalid_tags <- setdiff(rule_tags, valid_rule_tags)
  if(length(invalid_tags) > 0L) {
    stop("Invalid broadcast rule tags in `list_rule`: ", paste(invalid_tags, collapse=", "))
  }
  
  names(list_rule) <- paste0("rule_", rule_tags)

  invisible(list(axis_names=axis_names, list_rule=list_rule))
}


#' Validation for vector containing dimension lengths
#'
#' Broadcast rule functions operate on integer vectors, where the jth entry
#' contains the length of the jth dimension. This function checks that 
#' this integer vector is valid.
#'
#' @param lens An R object
#' 
#' @returns logical(1), \code{TRUE} is \code{lens} satisfies the requirements to
#'  be considered proper array dimension lengths.
#'  
#' @author Andrew Roberts
.check_lens <- function(lens) {
  
  if(!is_nonneg_integer_vector(lens) && all(lens > 0)) {
    stop("Slot dimension lengths `lens` must be vector of positive integers.")
  }
  
  if(length(lens) == 0L) {
    stop("Slot dimension lengths `lens` has length zero.")
  }
}
