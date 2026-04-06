# prob.tools/utils.r

#' Raise error when default method is not defined
#'
#' A convenience function to stop program execution and print an error
#' message when a default method is dispatched for a generic that does not
#' support a default method.
#'
#' @param x An R object
#' @param method_name character The name of the generic (base name of the method).
#' 
#' @example
#' # When you don't want a default method to be used for a particular generic
#' my_generic.default <- function(x, ...) {
#'  raise_default_method_error(x, "my_generic")
#' }
#' 
#' @author Andrew Roberts
#' @returns None. Raises error.
raise_default_method_error <- function(x, method_name) {
  stop(method_name, "() is not implemented for objects of class ", 
       paste(class(x), collapse = "/"))
}

