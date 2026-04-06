# prob.tools/R/types.r

# Helper functions for checking that R objects satisfy the requirements of
# particular user-defined "types".

#' Check if object is array or vector
#' 
#' A vector is viewed as a single-row matrix (which is an array).
#'
#' @returns logical, \code{TRUE} is \code{x} is an array or vector, else
#'  \code{FALSE}.
#' 
#' @author Andrew Roberts
is_array_like <- function(x) {
  is.array(x) || (is.vector(x) && is.atomic(x))
}


#' Check if object is matrix or vector
#' 
#' A vector is viewed as a single-row matrix.
#'
#' @returns logical, \code{TRUE} is \code{x} is a matrix or vector, else
#'  \code{FALSE}.
#' 
#' @author Andrew Roberts
is_matrix_like <- function(x) {
  is.array(x) || (is.vector(x) && is.atomic(x))
}


#' Check that R object has full set of names
#' 
#' Check if an R object has a unique set of names. Every element of the object
#' must have a non-NA, non-empty string name. 
#' 
#' @param x An R object
#' 
#' @returns logical, \code{TRUE} if object has full set of unique names.
#' 
#' @author Andrew Roberts
#' @export
has_unique_names <- function(x) {
  assertthat:::is.named(x) && !anyDuplicated(names(x))
}


#' Check that R object has full set of names (NOTE: slated for deletion)
#' 
#' Check if an R object has names, and that every element of the object
#' has a name (empty string does not count as a name). Optionally check 
#' that the names are unique. An object without a names attribute is considered 
#' to not have names.
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness requirement on names.
#' 
#' @returns logical, \code{TRUE} if object has full set of (unique) names.
#' @author Andrew Roberts
has_names <- function(x, check_unique_names=TRUE) {
  !is.null(names(x)) &&
    length(names(x)) == length(x) &&
    all(nzchar(names(x))) && # Ensure no "" names.
    (!check_unique_names || !anyDuplicated(names(x)))
}


#' Check if an R object is an atomic scalar
#' 
#' Must be atomic and length one. Singleton arrays, scalars, etc. are not
#' considered scalars.
#' 
#' @param x An R object
#' @returns logical, \code{TRUE} if an atomic scalar.
#' @seealso \code{\link{is_numeric_scalar}}, \code{\link{is_integer_scalar}}
#' @author Andrew Roberts
is_scalar <- function(x) {
  is.atomic(x) &&
    !is.array(x) &&
    length(x) == 1L
}


#' Check if an R object can be safely converted to integer
#' 
#' Returns \code{TRUE} if the input value is of integer atomic type,
#' or double type but can be converted to an integer without loss of 
#' information (e.g., 2.0). Returns \code{FALSE} if any values are \code{NA}.
#' 
#' @param x An R object
#' @returns logical, \code{TRUE} if is integer-like. 
#' @author Andrew Roberts
is_integer_like <- function(x) {
  !anyNA(x) &&
    (is.integer(x) || is.double(x)) &&
    all(x %% 1 == 0)
}


#' Check if an R object is a named vector, with all names provided (empty
#' strings are not allowed).
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness 
#'  requirement on names.
#' @returns logical, \code{TRUE} if a vector with all names provided. 
#' @author Andrew Roberts
is_named_vector <- function(x, check_unique_names=TRUE) {
    is.atomic(x) &&
    !is.array(x) &&
    has_names(x, check_unique_names)
}


#' Check if an R object is a numeric scalar
#' 
#' A numeric scalar must be numeric, atomic, and length one. Singleton arrays,
#' data.frames, etc. are not considered scalars.
#' 
#' @param x An R object
#' @returns logical, \code{TRUE} if a numeric scalar.
#' @seealso \code{\link{is_scalar}}, \code{\link{is_integer_scalar}}
#' @author Andrew Roberts
is_numeric_scalar <- function(x) {
  is_scalar(x) && is.numeric(x)
}


#' Check if an R object is a character scalar
#' 
#' The object is considered a character scalar if it is an atomic character
#' vector of length one.
#' 
#' @param x An R object
#' @returns logical, \code{TRUE} if a character scalar.
#' @seealso \code{\link{is_scalar}}, \code{\link{is_numeric_scalar}}
#' @author Andrew Roberts
is_character_scalar <- function(x) {
  is_scalar(x) && is.character(x)
}


#' Check if an R object is an integer scalar
#' 
#' The object is considered an integer scalar if it is a numeric scalar and
#' can be safely coerced to an integer; that is, both 5.0 and 5L are considered
#' integer scalars.
#' 
#' @param x An R object
#' @returns logical, \code{TRUE} if an integer scalar.
#' @seealso \code{\link{is_numeric_scalar}}
#' @author Andrew Roberts
is_integer_scalar <- function(x) {
  is_numeric_scalar(x) && is_integer_like(x)
}


#' Check if an R object is a named character vector, with all names provided 
#' (empty strings are not allowed).
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness 
#'  requirement on names.
#' @returns logical, \code{TRUE} if a character vector with all names provided. 
#' @author Andrew Roberts
is_named_numeric_vector <- function(x, check_unique_names=TRUE) {
  is.numeric(x) && is_named_vector(x, check_unique_names)
}


#' Check if an R object is a named vector, with values that can be safely
#' converted to integers
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness 
#'  requirement on names.
#' @returns logical, \code{TRUE} if integer vector with all names provided. 
#' @author Andrew Roberts
is_named_integer_vector <- function(x, check_unique_names=TRUE) {
  is_integer_like(x) && is_named_vector(x, check_unique_names)
}


#' Check if an R object is a named list, with all names provided (empty
#' strings are not allowed).
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness requirement on names.
#' @returns logical, \code{TRUE} if a list with all names provided. 
#' @author Andrew Roberts
is_named_list <- function(x, check_unique_names=TRUE) {
  is.list(x) &&
  length(x) > 0 &&
  has_names(x, check_unique_names)
}


#' Check if named or empty list.
#' 
#' Returns \code{TRUE} if \code{is_named_list(x, check_unique_names)} is TRUE,
#' or if \code{x} is an empty list (i.e., list of length zero).
#' 
#' @param x An R object
#' @param check_unique_names logical, if \code{TRUE} then impose uniqueness requirement on names.
#' @returns logical, \code{TRUE} if a named list or an empty list. 
#' @author Andrew Roberts
is_named_or_empty_list <- function(x, check_unique_names=TRUE) {
  (is.list(x) && length(x) == 0L) ||
    is_named_list(x, check_unique_names)
}


#' Check for integer-like vector with non-negative entries
#' 
#' @param x An R object
#' @author Andrew Roberts
is_nonneg_integer_vector <- function(x) {
  is.atomic(x) &&
    is_integer_like(x) &&
    all(x >= 0)
}


#' Check if a matrix is positive definite, and return Cholesky factor
#'
#' Defines "positive definite" in the numerical sense of being able to run 
#' \code{chol(m)} without an error. To avoid wasting this computation, returns 
#' the result of \code{chol(m)} (the upper Cholesky factor) in addition to the logical.
#' 
#' @param m A matrix 
#'
#' @returns A \code{list} with names \code{is_pos_def} and \code{chol_upper}.
#' @author Andrew Roberts
is_positive_definite <- function(m) {
  out <- tryCatch({
    chol_upper <- chol(m)
    list(is_pos_def=TRUE, chol_upper=chol_upper)
  }, error = function(e) {
    list(is_pos_def=FALSE, chol_upper=NULL)
  })
  return(out)
}


#' Check if a matrix is lower triangular
#'
#' A lower triangular matrix is one in which all entries strictly above the 
#' main diagonal are zero. Note that this function will run for non-square 
#' matrices, but it is primarily designed for square matrices.
#' 
#' @param m A matrix 
#'
#' @returns \code{TRUE} if \code{m} is lower triangular, else \code{FALSE}.
#' @seealso \code{\link{is_upper_tri}}
#' @author Andrew Roberts
is_lower_tri <- function(m) {
  all(m[upper.tri(m)] == 0)
}

#' Check if a matrix is upper triangular
#'
#' A upper triangular matrix is one in which all entries strictly above the 
#' main diagonal are zero. Note that this function will run for non-square 
#' matrices, but it is primarily designed for square matrices.
#' 
#' @param m A matrix 
#'
#' @returns \code{TRUE} if \code{m} is upper triangular, else \code{FALSE}.
#' @seealso \code{\link{is_upper_tri}}
#' @author Andrew Roberts
is_upper_tri <- function(m) {
  all(m[lower.tri(m)] == 0)
}
