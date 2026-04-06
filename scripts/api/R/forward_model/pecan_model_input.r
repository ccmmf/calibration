# forward_model/pecan_model_input.r
#
# A ModelInput designed to interface with PEcAn's model run workflow.
# Depends: model_input.r


SETTINGS_BRANCH_KEY <- "settings"
CONFIG_BRANCH_KEY <- "config"


#' PEcAn ModelInput Constructor
#' 
#' Generate a PEcAn \code{ModelInput} by combining PEcAn \code{Settings} and 
#' other model inputs.
#' 
#' @details
#' A PEcAn \code{ModelInput} is simply a \code{ModelInput} tree with the additional
#' requirement that there be sub-trees located at key paths \code{SETTINGS_BRANCH_KEY}
#' and \code{CONFIG_BRANCH_KEY}. The former is intended to store a PEcAn 
#' \code{Settings} object (or a subset of the information in a \code{Settings} 
#' object). The names of the nodes in this sub-tree should follow those of the 
#' PEcAn settings exactly. For example, the PEcAn settings stored in 
#' \code{settings$run$inputs$met} would be found at the 
#' \code{ModelInput} key \code{SETTINGS_BRANCH_KEY/run/inputs/met}.
#' 
#' The config branch is intended to store inputs that are 
#' 
#' All input slots not contained
#' in this branch are unconstrained, but will typically store inputs that 
#' are directly passed to the write config functions when running models.
#' See \code{\link{run_model.Settings}} for more details.
#' 
#' If \code{x} already contains the PEcAn branch, then \code{pecan_settings}
#' should be \code{NULL}. If it does not contain the branch already, then
#' \code{pecan_settings} must be provided and will be inserted within \code{x}
#' at the key path \code{SETTINGS_BRANCH_KEY}.
#' 
#' @param config_tree named list, \code{ModelInput}, or \code{Settings} object
#'  that will be used as the config sub-tree.
#' @param pecan_settings named list, \code{ModelInput}, or \code{Settings} object
#'  that will be used as the settings sub-tree.
#' @param base_tree named list, \code{ModelInput}, or \code{Settings} object. An
#'  existing tree to which the config and settings sub-trees will be added.
#'  Defaults ot empty tree.
#' @param ... Additional arguments passed to \code{.new_pecan_model_input()}.
#' 
#' @returns A \code{ModelInput} object.
#' 
#' @author Andrew Roberts
#' @export
PecanModelInput <- function(config_tree=list(), settings_tree=list(), base_tree=list(), ...) {
  x <- .new_pecan_model_input(base_tree, config_tree, settings_tree, ...)
  validate_pecan_model_input(x)
  
  return(x)
}


#' Low level helper to generate a PEcAn model input object
.new_pecan_model_input <- function(base_tree, config_tree, settings_tree, ...) {
  
  x <- as_model_input(base_tree)
  
  x <- set_model_input_value(x, CONFIG_BRANCH_KEY, config_tree, 
                             untagged_is_input=TRUE, allow_overwrite=FALSE)
  x <- set_model_input_value(x, SETTINGS_BRANCH_KEY, settings_tree, 
                             untagged_is_input=TRUE, allow_overwrite=FALSE)

  return(x)
}


#' Determine if an object is a PEcAn \code{ModelInput}
#'
#' A PEcAn \code{ModelInput} does not formally subclass \code{ModelInput}.
#' Rather, it is simply a \code{ModelInput} with the additional requirement
#' that there be subtrees located at key \code{SETTINGS_BRANCH_KEY} and
#' \code{CONFIG_BRANCH_KEY}. The leaf names in the latter tree are required
#' to be unique (stronger than the usual requirement of having unique key
#' paths). This is because these names are interpreted as arguments to 
#' write config functions.
#' 
#' @param x An R object
#' @returns logical(1), \code{TRUE} if \code{x} is a PEcAn \code{ModelInput}.
#'
#' @author Andrew Roberts
#' @export
is_pecan_model_input <- function(x) {
  is_model_input(x) && 
    is_model_input(x[[SETTINGS_BRANCH_KEY]]) &&
    is_model_input(x[[CONFIG_BRANCH_KEY]]) &&
    anyDuplicated(leaf_names(x[[CONFIG_BRANCH_KEY]])) == 0L
}


#' Throw error if object is not PEcAn \code{ModelInput}
#' 
#' @param x An object
#' @returns Invisibly returns \code{TRUE} if \code{x} is a PEcAn \code{ModelInput}.
#'  Otherwise throws an error.
#' 
#' @seealso \code{\link{is_pecan_model_input}}
#' @author Andrew Roberts
#' @export
.check_pecan_model_input_type <- function(x) {
  if(!is_pecan_model_input(x)) {
    stop("Object is not a PEcAn model input.")
  }
}


#' Validate a PEcAn ModelInput object
#'
#' Currently an alias for \code{\link{.check_pecan_model_input_type}}.
#' Included so that additional validation can easily be included in the future.
#'
#' @export
validate_pecan_model_input <- function(x) {
  .check_pecan_model_input_type(x)
}


#' Return the PEcAn settings sub-tree from a PEcAn \code{ModelInput}
#'
#' @param x A PEcAn \code{ModelInput}.
#' @returns A \code{ModelInput}, the PEcAn setting branch from \code{x}.
#' 
#' @author Andrew Roberts
#' @export
settings_tree <- function(x) {
  .check_pecan_model_input_type(x)
  x[[SETTINGS_BRANCH_KEY]]
}


#' Return the PEcAn config sub-tree from a PEcAn \code{ModelInput}
#'
#' @param x A PEcAn \code{ModelInput}.
#' @returns A \code{ModelInput}, the PEcAn config branch from \code{x}.
#' 
#' @author Andrew Roberts
#' @export
config_tree <- function(x) {
  .check_pecan_model_input_type(x)
  x[[CONFIG_BRANCH_KEY]]
}


#' Return input slots from settings sub-tree of a PEcAn ModelInput
#'
#' @param x A PEcAn \code{ModelInput}
#' @returns list, flat list containing input slots from the settings sub-tree.
#'  Names are set to key paths of the sub-tree (not key paths of \code{x}).
#'  
#' @author Andrew Roberts
#' @export
settings_input_slots <- function(x) {
  input_slots(settings_tree(x))
}


#' Return input slots from config sub-tree in a PEcAn \code{ModelInput}
#' 
#' This list is interpreted as a list of named arguments to pass to a write
#' config function. 
#'
#' @param x A PEcAn \code{ModelInput}
#' @returns list, flat list containing input slots from the config sub-tree.
#'  Names are set to the input leaf names of this sub-tree (not the key paths).
#'  
#' @author Andrew Roberts
#' @export
config_args <- function(x) {
  settings <- config_tree(x)
  args <- input_slots(settings)
  names(args) <- input_names(settings)
  
  return(args)
}


#' Names of config argument list of a PEcAn \code{ModelInput}
#'
#' The leaf names of the config branch are required to be unique.
#' 
#' @author Andrew Roberts
#' @export
config_arg_names <- function(x) {
  names(config_args(x))
}


#' Key paths of settings sub-tree of a PEcAn \code{ModelInput}
#' 
#' @author Andrew Roberts
#' @export
settings_keys <- function(x) {
  .check_pecan_model_input_type(x)
  input_keys(settings_tree(x))
}


#' Overwrite values in PEcAn \code{Settings} object
#' 
#' Settings from the PEcAn sub-tree of a PEcAn \code{ModelInput} are used to
#' overwrite (or add) values in a PEcAn \code{Settings} object. A common use
#' case is where the \code{Settings} object contains defaults that should
#' be overwritten by values in \code{model_input}.
#' 
#' @details
#' Values are set by key path. For example, a \code{model_input} value at 
#' \code{SETTINGS_BRANCH_KEY/run/inputs/met} will set a value at
#' \code{settings$run$inputs$met}. If a key exists only in \code{settings}
#' it will be untouched. If a key exists in both objects, then the value in 
#' \code{settings} will be overwritten by the value in \code{model_input}.
#' If a key only exists in \code{model_input}, it will be added to \code{settings}.
#' Empty branches in \code{model_input} are ignored; only leaves are considered.
#' Note that values outside of the settings branch in the \code{model_input}
#' object will be ignored. 
#'
#' @param settings named list, PEcAn \code{Settings} object, or \code{ModelInput} object.
#'                 Does not support PEcAn \code{MultiSettings} objects.
#' @param model_input A PEcAn \code{ModelInput}.
#'
#' @returns A PEcAn \code{Settings} object containing the updated settings.
#'
#' @author Andrew Roberts
#' @export
update_pecan_settings <- function(settings, model_input) {
  .check_is_pecan_settings_like(settings)
  
  settings_override <- settings_tree(model_input)
  if(is_model_input(settings)) settings <- settings$.data
  if(PEcAn.settings::is.Settings(settings)) settings <- unclass(settings)
  
  for(key in input_keys(settings_override)) {
    val <- .get_tree_leaf_at_path(settings_override$.data, key, error_if_missing=FALSE)$value
    settings <- .assign_tree_node_at_path(settings, key, val, allow_overwrite=TRUE)
  }
  
  PEcAn.settings::as.Settings(settings)
}


#' Resolve particular settings value without performing entire settings update
#' 
#' \code{update_pecan_settings()} updates all values in \code{settings}
#' with overrides from \code{model_input}. This function updates one particular
#' value, specified by \code{settings_key}.
#' 
#' @param settings named list, PEcAn \code{Settings} object, or a \code{ModelInput},
#'  This represents the default settings.
#' @param model_input A PEcAn \code{ModelInput} containing settings overrides in
#'  the settings sub-tree.
#' @param settings_key The key path identifying the settings value to extract.
#' 
#' @returns The value extracted either from \code{model_input} (which takes
#' precedence) or \code{settings} (the default). Throws error if the path is
#' found is neither. This function only operates on leaves; if \code{settings_key}
#' points to a branch then an error will be thrown.
#'
#' @author Andrew Roberts
#' @export
resolve_pecan_settings_value <- function(settings, model_input, settings_key) {
  settings_override <- settings_tree(model_input)
  if(is_model_input(settings)) settings <- settings$.data
  
  # Value in `model_input` takes precedence. 
  val <- .get_tree_leaf_at_path(settings_override$.data, settings_key, 
                                error_if_missing=FALSE)
  
  # Fall back on default value. Class is stripped from settings since PEcAn
  # `settings` object causes issues with `.get_tree_node_at_path`
  if(is.null(val)) {
    val <- .get_tree_leaf_at_path(unclass(settings), settings_key, 
                                  error_if_missing=FALSE)
  }
  
  if(is.null(val)) {
    stop("No leaf found at key `", .parse_key_path(settings_key, as_string=TRUE), 
         "` in either `settings` or `model_input` settings sub-tree.")
  }
  
  if(is_tagged_leaf(val)) return(val$value)
  else return(val)
}


#' Check that an object can be interpreted as a PEcAn \code{Settings} object
#'
#' This function is not a substitute for validating the validity of a PEcAn
#' settings object. Rather, it simply checks if the input is a pure R list,
#' \code{ModelInput} object, or a \code{Settings} object. A PEcAn 
#' \code{MultiSettings} object is NOT considered settings-like.
#' This function is primarily intended for use by \code{update_pecan_settings}.
.check_is_pecan_settings_like <- function(settings) {
  
  msg <- "`settings` is not PEcAn settings-like. PEcAn run model API requires 
          `settings` to be a PEcAn `Settings` object, a pure R list, or a 
          `ModelInput` object."
  
  if(PEcAn.settings::is.MultiSettings(settings)) {
    msg <- paste(msg, "PEcAn MultiSettings object not supported.")
    PEcAn.logger::logger.severe(msg)
  }
  
  is_settings_like <- is_pure_list(settings) || 
                      PEcAn.settings::is.Settings(settings) || 
                      is_model_input(settings)
  
  if(!is_settings_like) {
    PEcAn.logger::logger.severe(msg)
  }
  
  invisible(TRUE)
}





