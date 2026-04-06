# batch_array.r
#
# Depends: assertthat

# Contains functions for manipulating and converting between three array-based
# data structures:
# 1.) batch array: An array in which the first dimension is interpreted as
#     a batch dimension. In other words, a batch array is an ordered set of
#     arrays of equal dimension.
# 2.) Array list: A list of arrays, not necessarily of the same dimension.
# 3.) Flattened array: a flattened matrix representation of one or more arrays.
#     The number of rows corresponds to the number of arrays (batch size). Each
#     row is a flattened vector representation of an array or an array list.


#' Check if an object is a batch array
#'
#' A batch array is defined to be an array with at least two dimensions.
#' 
#' @returns logical, \code{TRUE} if \code{x} is an array with two or more dimensions.
#'
#' @author Andrew Roberts
is_batch_array <- function(x) {
  is.array(x) && length(dim(x)) > 1L
}


#' Convert batch array to flattened (matrix) representation
#' 
#' Converts an array (or vector), to a standardized flat representation.
#' 
#' @details
#' The input is \code{x} is an array whose first dimension is interpreted as
#' a batch dimension. For example, an array with dimension \code{(4,2,3)} is
#' interpreted as a batch of 4 two-by-three arrays. This array would be 
#' flattened to a matrix of shape \code{(4,6)} with each row representing a
#' flattened version of one of the \code{(2,3)} arrays. In general, an input
#' with shape \code{c(n, shape)} will be converted to a matrix of shape
#' \code{(n, prod(shape))}. 
#'
#' This method exactly reverses the steps of  \code{\link{.flat_to_array()}} 
#' to ensure consistent and reproducible conversion.
#' 
#' @param x An array. The first dimension is interpreted as the batch dimension.
#'  An array with a single dimension is treated as an array with batch size one.
#'  A vector of length \code{len} is treated as a \code{(1,1,len)} batch
#'  array.
#' 
#' @returns Matrix with number of rows equal to the number of arrays in the
#'  batch and number of columns equal to the number of elements in each 
#'  individual array. See details for specifics.
#' 
#' @author Andrew Roberts
.batch_array_to_flat = function(x) {
  
  x <- .wrap_and_check_batch_array(x)

  dim_x <- dim(x)
  n <- dim_x[1] # Batch size
  n_dims_total <- length(dim_x) # Including batch dimension
  len <- prod(dim_x[2:n_dims_total]) # Number of entries in individual array
  
  x <- aperm(x, c(2:n_dims_total, 1L)) # dim = c(shape, n)
  x_flat <- matrix(x, nrow=len, ncol=n) # dim = (len, n)
  x_flat <- t(x_flat) # dim = (n, len)
  
  return(x_flat)
}


#' Invert the flattening operation for a batch array 
#' 
#' Converts a flattened representation of an array (a vector), or multiple 
#' such vectors, to a (potentially multidimensional) array.
#' 
#' @details
#' Let \code{len} denote \code{prod(target_shape)}, the number of entries in
#' the target array. The input \code{x} is required to be a vector with length 
#' equal to \code{len} or a matrix of shape \code{(n, len)}. In the former 
#' case the input is converted to an array of shape \code{c(1,target_shape)}.
#' In the latter case the input is converted to an array of shape 
#' \code{c(n, target_shape)}. The reshaping is done in row major 
#' order (i.e., "C" style).
#' 
#' @param x values in flat (vector or matrix) format.
#' @param target_shape integer vector, the shape of the target array.
#' 
#' @returns In general, returns array of shape \code{c(n, target_shape)}, when
#'  the input contains \code{n} flattened values.
#'
#' @author Andrew Roberts
.flat_to_batch_array = function(x, target_shape) {
  
  x <- .wrap_and_check_flat_array(x, target_shape)
  
  # x <- .wrap_vector_as_flat(x)
  # .check_input_is_flat(x, target_shape)

  n <- nrow(x)
  n_dims <- length(target_shape)
  
  # R stores in column-major order (columns are contiguous in memory).
  # We thus transpose `x` so that each value becomes a column. Values
  # are assigned to array in column-major order, then permuted afterwards
  # to maintain the convention that the first dimension is the number 
  # of values.
  arr <- array(t(x), dim=c(target_shape, n)) # dim = c(target_shape, n)
  arr <- aperm(arr, c(n_dims + 1L, seq_along(target_shape))) # dim = c(n, target_shape)
  
  return(arr)
}


#' Convert array list to flat representation
#'
#' Converts a list of arrays (possibly of differing dimensions) to a flat
#' representation by flattening each array and then appending them.
#' 
#' @details
#' If \code{arrays_are_batch = FALSE} then each array in the list is viewed
#' as a single array (not a batch array), and the output is a matrix of
#' shape \code{(1, len)}, where \code{len} is the sum of the number of entries
#' across all of the arrays. If \code{arrays_are_batch = TRUE}, then each
#' array is viewed as a batch array and all arrays are required to have equal
#' batch size (i.e., same number of elements in the first dimension). The 
#' remaining dimensions need not be equal. In this case, the returned matrix
#' is of shape \code{(n, len)} where \code{n} is the batch size and 
#' \code{len} is the sum of the number of elements in all of the sub-arrays
#' excluding the first dimension (e.g., a \code{(n,2,3)} batch array has length
#' 6).
#' 
#' @param x list of arrays or batch arrays.
#' @param arrays_are_batch logical(1) whether to view elements of the list as
#'  arrays or batch arrays.
#'  
#' @returns matrix, with number of rows corresponding to the batch size and
#'  number of columns corresponding to the length of the flattened array
#'  representation.
#'
#' @author Andrew Roberts
.array_list_to_flat <- function(x, arrays_are_batch=FALSE) {
  
  assert_that(is.list(x), msg=".array_list_to_flat() expects list.")
  
  # Convert to batch arrays with batch size 1.
  if(arrays_are_batch) {
    .wrap_and_check_batch_array_list(x) # TODO: write this function
  } else {
    x <- lapply(x, .add_batch_axis_to_array)
  }

  x_flat_list <- lapply(x, .batch_array_to_flat)
  do.call(cbind, x_flat_list)
}


#' Inverts .array_list_to_flat
#'
#' Converts flattened matrix representation to a list of batch arrays.
#' 
#' @details
#' The argument \code{target_shapes} provides the blueprint for how to expand
#' the flattened representation. It is a list of array dimensions, containing
#' the dimensions for the individual arrays (i.e., not including the batch
#' dimension). For example, an array list \code{list(c(2,3), c(4,3,6)} implies
#' a target list of length two, in which the two list elements will be arrays
#' of shapes \code{(n,2,3)} and \code{n,4,3,6}, respectively, where \code{n}
#' is the batch dimension. The batch dimension is given by the number of rows
#' in \code{x}. If \code{x} is a single dimension or a vector, then the batch
#' dimension is assumed to be one. 
#'
#' @returns List of length \code{length(target_shapes)}, with each element 
#'  containing a batch array (see details). Throws error if 
#'  \code{target_shapes} is inconsistent with the dimensions of \code{x}.
#'
#' @author Andrew Roberts
.flat_to_batch_array_list <- function(x, target_shapes) {
  
  x <- .wrap_and_check_flat_array(x, target_shapes)
  if(!is.list(target_shapes)) target_shapes <- list(target_shapes)
  
  cutoff_starts <- c(1L, cumsum(vapply(target_shapes, prod, numeric(1))) + 1L)

  # Helper to extract correct subset of x and unflatten.
  unflatten_arr <- function(i) {
    col_idx_start <- cutoff_starts[i] 
    col_idx_end <- cutoff_starts[i+1] - 1L
    
    .flat_to_batch_array(x[,col_idx_start:col_idx_end, drop=FALSE],
                           target_shapes[[i]])
  }
  
  lapply(seq_along(target_shapes), unflatten_arr)
}


#' Check if an object can be converted to a batch array
#'
#' Validates that an object is, or can be converted to, a batch array.
#' Vectors and single-dimension arrays can be converted to batch arrays (they
#' are wrapped as one row matrices).
#'
#' @returns invisibly returns the input \code{x}, potentially modified so that
#'  it can be considered a valid batch array. Throws error if \code{x} cannot
#'  be converted to a batch array.
#'
#' @author Andrew Roberts
.wrap_and_check_batch_array <- function(x) {
  x <- .wrap_vector_as_batch_array(x)
  
  assert_that(is_batch_array(x),
              msg="batch array representation requires array with at least two dimensions.")
  
  invisible(x)
}


#' Validate that input is flattened array (or array list) of particular shape
#' 
#' Checks whether \code{x} can be mapped to a list of batch arrays, with
#' array shapes given by \code{target_shapes}.
#'
#' @param x An R object
#' @param target_shapes list or integer vectors. If a list, then each element
#'  should be an integer vector giving the dimensions of an array. The batch
#'  dimension should not be included in these dimensions. A single integer vector
#'  will be wrapped as a one-element list.
#'  
#' @returns invisibly returns \code{TRUE} if \code{x} can be viewed as a flattened
#'  list of batch arrays of the form determined by \code{target_shapes}.
#'  Otherwise throws an error.  
#'
#' @author Andrew Roberts
.wrap_and_check_flat_array <- function(x, target_shapes) {
  
  x <- .wrap_vector_as_flat_array(x)
  if(!is.list(target_shapes)) target_shapes <- list(target_shapes)
  
  assert_that(is.matrix(x),
              msg="Flattened batch array representation requires matrix.")

  # Ensure dimensions of x are consistent with target_shapes.
  len <- sum(vapply(target_shapes, prod, numeric(1)))
  
  assert_that(ncol(x) == len,
              msg=paste0("Flattened array with length ", ncol(x), " is not ",
                         "in agreement with target length ", len,
                         ". Note that `target_shapes` should not include the ",
                         "batch dimension."))
  
  invisible(x)
}


# batch array list requires every element to be a batch array with equal
# batch size.
.wrap_and_check_batch_array_list <- function(x) {
  
  assert_that(is.list(x))

  # Ensure each element is a batch array.
  for(i in seq_along(x)) {
    tryCatch({
      x[[i]] <- .wrap_and_check_batch_array(x[[i]])
    },
    
    error = function(e) {
      stop(sprintf("Element '%i' in list is not batch array: %s", 
                    i, e$message), call.=FALSE)
    })
  }
  
  # Ensure all batch arrays have the same batch size. 
  arr_dims <- vapply(x, function(arr) dim(arr)[1], integer(1))
  
  if(length(unique(arr_dims)) > 1L) {
    stop("Arrays in list have different batch sizes.")
  }
  
  invisible(x)
}

 
#' Converts single-dimension objects to a batched array
#'
#' Converts vectors and single dimension arrays to a batched array by storing
#' them as a one row matrix. All other objects are returned unmodified.
#'
#' @returns If \code{x} is a vector or single-dimension array, then returns
#'  a one row matrix, with number of columns corresponding to the length of the
#'  input. Otherwise returns \code{x} untouched.
#'
#' @author Andrew Roberts
.wrap_vector_as_batch_array <- function(x) {
  if(is.vector(x) && is.atomic(x)) {
    matrix(x, nrow=1L)
  } else if(is.array(x) && length(dim(x)) == 1L) {
    matrix(drop(x), nrow=1L)
  } else {
    x
  }
}


#' Converts single-dimension objects to a one-row flattened array
#'
#' Converts vectors and single dimension arrays to a flattened batched array 
#' by storing them as a one row matrix. All other objects are returned unmodified.
#'
#' @returns If \code{x} is a vector or single-dimension array, then returns
#'  a one row matrix, with number of columns corresponding to the length of the
#'  input. Otherwise returns \code{x} untouched.
#' @note The logic of this function happens to exactly follow that of
#'  \code{.wrap_vector_as_batch_array()}. These are kept as separate functions
#'  as they conceptually different, and may potentially deviate in the future.
#'
#' @author Andrew Roberts
.wrap_vector_as_flat_array <- function(x) {
  if(is.vector(x) && is.atomic(x)) {
    matrix(x, nrow=1L)
  } else if(is.array(x) && length(dim(x)) == 1L) {
    matrix(drop(x), nrow=1L)
  } else {
    x
  }
}


#' Adds a length one batch axis to a singleton array
#'
#' Given an existing array \code{x}, returns a new array with dimension
#' \code{c(1, dim(x))}, representing a batch array with batch size one.
#' Vectors and single-dimension arrays are also wrapped as batch one arrays,
#' as per \code{.wrap_and_check_batch_array()}.
#'
#' @returns A batch array with batch size one (i.e., the first dimension has
#'  length one). Throws error if \code{x} cannot be converted to a batch array.
#'
#' @author Andrew Roberts
.add_batch_axis_to_array <- function(x) {
  if(is.array(x)) x <- array(x, dim=c(1L, dim(x)))
  .wrap_and_check_batch_array(x)
}


#' Wrap single-dimension objects as 2d array
#'
#' Wraps atomic vectors, one dimensional arrays, and zero dimensional arrays
#' as a one-row matrix (i.e., a 2d array). Existing arrays with at least two
#' dimensions are returned unchanged.
#' 
#' @param x An R object
#' @param err logical(1), if \code{TRUE} throws error if \code{x} is not
#'  array-like. Otherwise, will return non-array like objects unchanged.
#'
#' @returns An array with at least two dimensions. Throws error if 
#'  \code{err = TRUE} and \code{x} is not array-like.
#'  
#' @author Andrew Roberts
wrap_as_multidim_array <- function(x, err=TRUE) {
  
  if(!is_array_like(x)) {
    if(err) stop("`x` must be array-like to be wrapped as an array.")
    else return(x)
  }
  
  if(is.vector(x) || length(dim(x)) < 2L) x <- matrix(x, nrow=1L)
  return(x)
}


#' Extract element from first dimension of an array
#'
#' @details
#' For example, for a 3-d array this returns \code{x[index,,drop=TRUE]}.
#' If the result is a vector and \code{force_array_output = TRUE} then
#' it is wrapped as a one-row matrix so that the function always returns an
#' array. Otherwise, it is returned as is. This helper can be used to select
#' values from batched arrays and flattened batch arrays, since both reserve
#' the first index as the batch dimension.
#' 
#' @author Andrew Roberts
index_first_dim <- function(x, index, force_array_output=TRUE) {
  if(index < 1L) {
    stop("`index` must be an integer >= 1.")
  }
  
  assert_that(is_array_like(x))
  if(is.vector(x) || length(dim(x)) < 2L) x <- matrix(x, nrow=1L)
  
  n_dims <- length(dim(x))
  args <- c(list(index), rep(list(quote(expr=)), n_dims-1), list(drop=TRUE))
  val <- do.call(`[`, c(list(x), args))
  
  if(is.vector(val) && force_array_output) matrix(val, nrow=1L)
  else val
}


#' Extract an element from the batch (first) dimension of a batch array.
#' e.g., for 3-d array extracts \code{x[index,,drop=TRUE]}. The one exception
#' is when this results in a vector. In this case, the vector is wrapped as 
#' a one row matrix to ensure that this function always returns an array for
#' type consistency.  
index_batch_dim <- function(x, index) {
  
  if(index < 1L) {
    stop("`index` must be an integer >= 1.")
  }
  
  x <- .wrap_vector_as_batch_array(x)
  assert_that(is_batch_array(x))
  
  n_dims <- length(dim(x))
  args <- c(list(index), rep(list(quote(expr=)), n_dims-1), list(drop=TRUE))
  val <- do.call(`[`, c(list(x), args))
  
  if(is.vector(val)) matrix(val, nrow=1L)
  else val
}






#
# OLD
#

# Requires x to be a list of arrays, not necessarily of the same dimension.
.check_input_is_array_list <- function(x) {
  assert_that(is.list(x))
  assert_that(all(vapply(x, is_array_like, logical(1))),
              msg="An array list requires each element to be an array or vector.")
  
  invisible(TRUE)
}
