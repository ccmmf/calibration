# forward_model/model_input.r

#' Tag for an input slot in ModelInput
#'
#' A light wrapper around an object that identifies that the object should
#' be treated as a leaf in the \code{ModelInput} tree, and designates the leaf 
#' as a component of the model input.
#' 
#' @author Andrew Roberts
#' @export
InputSlot <- function(x) {
  structure(list(value=x), class="InputSlot")
}


#' Tag for a metadata slot in ModelInput
#'
#' A light wrapper around an object that identifies that the object should
#' be treated as a leaf in the \code{ModelInput} tree, and designates the leaf 
#' as metadata.
#' 
#' @author Andrew Roberts
#' @export
MetadataSlot <- function(x) {
  structure(list(value=x), class="MetadataSlot")
}


#' Check if object inherits from \code{InputSlot}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{InputSlot}.
#' 
#' @author Andrew Roberts
#' @export
is_input_slot <- function(x) {
  inherits(x, "InputSlot")
}


#' Check if object inherits from \code{MetadataSlot}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{MetadataSlot}.
#' 
#' @author Andrew Roberts
#' @export
is_metadata_slot <- function(x) {
  inherits(x, "MetadataSlot")
}


#' Convert object to an \code{InputSlot}
#' @export
as_input_slot <- function(x) {
  if(is_input_slot(x)) x
  else InputSlot(x)
}


#' Convert object to a \code{MetadataSlot}
#' @export
as_metadata_slot <- function(x) {
  if(is_metadata_slot(x)) x
  else MetadataSlot(x)
}


#' Print method for \code{InputSlot}
#' @export
print.InputSlot <- function(x, ...) {
  cat("InputSlot:\n")
  print(x$value, ...)
  invisible(x)
}


#' Print method for \code{MedadataSlot}
#' @export
print.MetadataSlot <- function(x, ...) {
  cat("MetadataSlot:\n")
  print(x$value, ...)
  invisible(x)
}


#' Check if object has class identical to "list"
#'
#' This returns true only for "pure" lists. It returns false for objects
#' like data.frames that inherit from list.
#'
#' @author Andrew Roberts
#' @export
is_pure_list <- function(x) {
  is.list(x) && identical(class(x), "list")
}


#' Defines a leaf in a \code{ModelInput} object
#' 
#' A leaf is any object that is either:
#' 1. Not a pure list
#' 2. Is directly tagged as an \code{InputSlot} or \code{MetadataSlot}.
#' 
#' @details
#' A \code{ModelInput} object itself is not considered a leaf. By excluding
#' only pure lists, this means that objects like data.frames are treated
#' as leaves. Objects of any class can be treated as a leaf by wrapping them
#' as an \code{InputSlot} or \code{MetadataSlot}.
#' 
#' @author Andrew Roberts 
#' @export
is_model_input_leaf <- function(x) {
  
  # Ensure the whole tree is not treated as leaf.
  if(is_model_input(x)) return(FALSE)
  
  !is_pure_list(x) ||
  is_input_slot(x) ||
  is_metadata_slot(x)
}


#' Defines a branch in a \code{ModelInput} object
#' 
#' A branch is any object that is not a leaf.
#' 
#' @author Andrew Roberts 
#' @export
is_model_input_branch <- function(x) {
  !is_model_input_leaf(x)
}
 

#' Test whether object is explicitly tagged as a ModelInput leaf
#'
#' @returns logical(1), \code{TRUE} if \code{x} is an \code{InputSlot} or \code{MetadataSlot}.
#' @export
is_tagged_leaf <- function(x) {
  is_input_slot(x) || is_metadata_slot(x)
}


#' ModelInput Constructor
#' 
#' Wraps a pure R nested list as a \code{ModelInput} object.
#' 
#' @details
#' The nested list must have names for all elements. The names at any branch
#' of the list must be unique.
#' 
#' 
ModelInput <- function(x, untagged_is_input=TRUE) {
  assertthat::assert_that(is_pure_list(x), msg="ModelInput constructor expects a list.")
  x <- .validate_and_wrap_model_input(x, path=character(), untagged_is_input)
  
  structure(list(.data=x), class="ModelInput")
}


#' Check if object inherits from \code{ModelInput}
#' 
#' @param x An object
#' @returns Logical, whether or not the object inherits from \code{ModelInput}.
#' 
#' @author Andrew Roberts
#' @export
is_model_input <- function(x) {
  inherits(x, "ModelInput")
}


#' Construct a \code{ModelInput} from a nested list.
#'  
#' Leaves existing \code{ModelInput} objects unchanged.
#'
#' @export
as_model_input <- function(x, untagged_is_input=TRUE) {
  if(is_model_input(x)) x
  else ModelInput(x, untagged_is_input)
}

#' Generic for conversion to list
#' @export
as_list <- function(x, ...) {
  UseMethod("as_list")
}


#' @export
as_list.default <- function(x, ...) {
  raise_default_method_error(x, "as_list")
}


#' Convert \code{ModelInput} to flat or nested list
#' 
#' Converts to a pure R list. If \code{flatten = TRUE}, converts to a flat
#' list of length equal to the number of leaves in the tree. Otherwise,
#' retains the tree structure as a nested list.
#' 
#' @param x A \code{ModelInput}
#' @param drop_slot_wrappers logical(1), if \code{TRUE} the items in the 
#'  list will contain the raw leaf values without \code{InputSlot} or
#'  \code{MetadataSlot} wrappers. Otherwise will retain the wrappers.
#' @param flatten logical(1), if \code{TRUE} converts to flat list of leaves. 
#'  Otherwise retains the nested list structure.
#' 
#' @author Andrew Roberts
#' @export
as_list.ModelInput <- function(x, drop_slot_wrappers=FALSE, flatten=FALSE) {
  
  if(drop_slot_wrappers) f <- function(x, ...) x$value
  else f <- function(x, ...) x
  
  apply_to_leaves(x, f, flatten)
}


#' Return flat list of ModelInput leaves 
#'
#' Alias for \code{as_list(x, drop_slot_wrappers, flatten=TRUE)}.
#'
#' @author Andrew Roberts
#' @export
flatten_model_input <- function(x, drop_slot_wrappers=FALSE) {
  .check_model_input_type(x)
  as_list(x, drop_slot_wrappers=drop_slot_wrappers, flatten=TRUE)
}


#' Apply function to leaves of ModelInput tree
#'
#' @details
#' Traverses leaves in left-to-right, depth first order. A function with 
#' signature \code{f(node, node_path, ...)} is applied to each leaf. The values
#' returned from these calls can either be returned in a flattened list format,
#' or maintain the nested tree format of the input.
#' 
#' @param x A \code{ModelInput} object
#' @param f A function with signature \code{f(node, node_path, ...)} that is
#'  applied to each leaf. The \code{node_path} is in the vector format
#'  (e.g., \code{"a", "b", "c"}).
#' @param flatten logical(1), if \code{TRUE} returns flattened list. Otherwise
#'  returns nested list.
#' @param drop_null logical(1), if \code{TRUE} drops \code{NULL} values. Otherwise,
#'  they are maintained as elements of the returned list.
#' @param ... additional arguments passed to \code{f}.
#' 
#' @returns list, either nested/tree-like or flat. In either case, \code{drop_null}
#'  will determine whether \code{NULL} values returned by \node{f} are dropped 
#'  entirely from the list, or if \code{NULL} elements are retained in the list.
#'  If all values are \code{NULL} then an empty list \code{list()} is returned 
#'  in either case.
#'  
#' 1. \code{flatten = FALSE}: Returns a nested list that echoes the structure
#'  of the \code{ModelInput} tree. If \code{drop_null = FALSE} then the tree 
#'  structure is guaranteed to actually follow the structure of \code{x}.
#'  Otherwise, the two can deviate due to dropping of \code{NULL} elements.
#' 2. \code{flatten = TRUE}: Returns a flat list, with names set to the string
#'  key paths of each node. The length of the list is equal to the number of
#'  leaves in \code{x} if \code{drop_null = FALSE}. Otherwise can contain fewer
#'  elements due to dropping of \code{NULL} values.
#' 
#' @author Andrew Roberts
#' @export
apply_to_leaves <- function(x, f, flatten=FALSE, drop_null=FALSE, ...) {
  .check_model_input_type(x)
  .apply_to_leaves(x$.data, f, flatten, drop_null, ...)
}


#' Determine whether ModelInput tree contains any nodes
#'
#' If the \code{ModelInput} contains any nodes (including empty branches) then
#' it is considered non-empty. An empty \code{ModelInput} is thus just an
#' empty list. 
#'
#' @param x A \code{ModelInput}.
#' 
#' @author Andrew Roberts
#' @export
model_input_is_empty <- function(x) {
  .check_model_input_type(x)
  length(x$.data) == 0L
}


#' Extract input slots from a ModelInput
#' 
#' Returns the input slots (a named list) within a \code{ModelInput} object.
#'
#' @param x A \code{ModelInput} object.
#' @returns List of input slot leaves containing the raw values of the nodes.
#'
#' @author Andrew Roberts
#' @export
input_slots <- function(x) {
  
  f <- function(x, ...) if(is_input_slot(x)) x$value else NULL
  apply_to_leaves(x, f, flatten=TRUE, drop_null=TRUE)
}


#' Extract metadata slots from a ModelInput
#' 
#' Returns the metadata slots (a named list) within a \code{ModelInput} object.
#'
#' @param x A \code{ModelInput} object.
#' @returns List of metadata slot leaves containing the raw values of the nodes.
#'
#' @author Andrew Roberts
#' @export
metadata_slots <- function(x) {
  
  f <- function(x, ...) if(is_metadata_slot(x)) x$value else NULL
  apply_to_leaves(x, f, flatten=TRUE, drop_null=TRUE)
}


#' Construct ModelInput tree from flat list
#'
#' @details
#' Acts as a quasi-inverse to the methods \code{\link{input_slots}} and
#' \code{\link{metadata_slots}}. Feeding the returned values of these methods
#' to this function is guaranteed to construct a tree with the same leaves,
#' where the input slot leaves are in the same order, and the metadata leaves
#' are in the same order. However, the overall ordering of the leaves may be
#' different, as this function provides no way to specify how the input slot
#' and metadata leaves should be interleaved when inserting them into the tree.
#'
#' @param inputs a flat list of the form returned by \code{\link{input_slots}}.
#' @param metadata a flat list of the form returned by \code{\link{metadata_slots}}.
#'
#' @returns A \code{ModelInput} object, with leaves set to the elements of
#'  \code{slots} and \code{metadata}.
#'
#' @author Andrew Roberts
#' @export
unflatten_model_input <- function(inputs=list(), metadata=list()) {

  tree <- list()
  
  # Insert slots
  for(nm in names(inputs)) {
    path <- .node_key_to_path(nm)
    val <- as_input_slot(inputs[[nm]])
    tree <- .assign_tree_node_at_path(tree, path, val, allow_overwrite=FALSE)
  }
  
  # Insert metadata
  if(length(metadata) > 0L) {
    for(nm in names(metadata)) {
      path <- .node_key_to_path(nm)
      val <- as_metadata_slot(metadata[[nm]])
      tree <- .assign_tree_node_at_path(tree, path, val, allow_overwrite=FALSE)
    }
  }

  ModelInput(tree)
}


#' Extract ModelInput nodes using bracket indexing
#' 
#' @details
#' Return \code{NULL} if a key path does not exist in the tree, which is 
#' consistent with the idea that \code{NULL} represents the absence of a
#' leaf/branch in a tree. For single-item paths (e.g., \code{"a"}), this 
#' behaves like the typical R list selection operator (which selects a value
#' at the top layer without recursing into the nested list).
#' 
#' @param x A ModelInput object
#' @param i character, either a string key path of the form \code{a/b/c} or
#'  a vector path of the form \code{c("a", "b", "c")}. The special keyword
#'  \code{.data} will extract the internal list (i.e., strips the \code{ModelInput})
#'  class).
#' 
#' @returns If a node at the key path exists (is non-NULL), returns either a 
#' sub-tree or the leaf value. In the former case, the sub-tree retains the
#' \code{ModelInput} class. In the latter case, the actual value of the node
#' is returned (i.e., the \code{InputSlot}/\code{MetadataSlot} class attribute is
#' stripped).
#' 
#' @author Andrew Roberts
#' @export
`[[.ModelInput` <- function(x, i, ...) {
  
  # Allow access to internal data.
  if(identical(i, ".data")) return(unclass(x)[[i]])
  
  node <- .get_tree_node_at_path(x$.data, i, error_if_missing=FALSE)

  if(is_model_input_leaf(node)) {
    return(node$value)
  } else {
    structure(list(.data=node), class=class(x))
  }
}


#' Extract ModelInput nodes using \code{`$`} indexing
#'
#' Identical to \code{`[[.ModelInput`}.
#' 
#' @author Andrew Roberts
#' @export
`$.ModelInput` <- function(x, name) {
  
  # Allow access to internal data.
  if(name == ".data") return(unclass(x)$.data)
  
  node <- .get_tree_node_at_path(x$.data, name, error_if_missing=FALSE)
  if(is.null(node)) return(NULL)
  
  if(is_model_input_leaf(node)) {
    return(node$value)
  } else {
    structure(list(.data=node), class=class(x))
  }
}


#' Set leaf or branch value in \code{ModelInput}
#'
#' Alias for \code{set_model_input_value(..., untagged_is_input=TRUE, allow_overwrite=TRUE)}.
#'
#' @author Andrew Roberts
#' @export
`[[<-.ModelInput` <- function(x, i, value) {
  set_model_input_value(x, i, value, untagged_is_input=TRUE, allow_overwrite=TRUE)
}


#' Set leaf or branch value in \code{ModelInput}
#'
#' Alias for \code{set_model_input_value(..., untagged_is_input=TRUE, allow_overwrite=TRUE)}.
#'
#' @author Andrew Roberts
#' @export
`$<-.ModelInput` <- function(x, name, value) {
  set_model_input_value(x, name, value, untagged_is_input=TRUE, allow_overwrite=TRUE)
}


#' Set leaf or branch value in \code{ModelInput}
#'
#' Set a leaf value or branch at a specified key path in a \code{ModelInput}
#' tree. Allows for overwriting a leaf with a new leaf, branch with a new
#' branch, leaf with a new branch, and branch with a new leaf.
#' 
#' @param x A \code{ModelInput} object.
#' @param key A vector or string key path pointing to a node in the tree.
#' @param value The value to set at the path. Can be a leaf value, or a branch
#'  (including a \code{ModelInput} sub-tree).
#' @param untagged_is_input logical(1), If \code{value} is an untagged leaf, 
#'  then will be wrapped as a model input slot if \code{untagged_is_input=TRUE};
#'  otherwise will be wrapped as a metadata slot.
#'  
#' @returns The updated \code{ModelInput} object.
#' 
#' @author Andrew Roberts
#' @export
set_model_input_value <- function(x, key, value, untagged_is_input=TRUE, allow_overwrite=TRUE) {
  .check_model_input_type(x)
  if(is_model_input(value)) value <- value$.data
  
  new_tree <- .assign_tree_node_at_path(x$.data, key, value, allow_overwrite=allow_overwrite)
  new_tree <- .validate_and_wrap_model_input(new_tree, untagged_is_input=untagged_is_input)
  
  structure(list(.data=new_tree), class=class(x))
}


#' Return vector of leaf keys
#'
#' @param x A \code{ModelInput} object.
#'
#' @returns character, vector of leaf keys, using \code{a/b/c} convention.
#'  Ordered by the flattening convention in \code{\link{traverse_leaves}}.
#' 
#' @author Andrew Roberts
#' @export
leaf_keys <- function(x) {
  .check_model_input_type(x)
  nm <- names(flatten_model_input(x))
  
  if(is.null(nm)) character(0)
  else nm
}


#' Return vector of input slot keys
#'
#' Returns the names of the input slot keys present in a model input object.
#' Defined for both \code{ModelInput} and \code{EnsembleInput}.
#'
#' @param x A \code{ModelInput} or \code{EnsembleInput} object.
#' @param ... Further arguments passed to methods.
#'
#' @return character vector of input slot names.
#' @seealso \code{\link{input_keys.ModelInput}}, \code{\link{input_keys.EnsembleInput}}
#'
#' @author Andrew Roberts
#' @export
input_keys <- function(x, ...) {
  UseMethod("input_keys")
}


#' @export
input_keys.default <- function(x, ...) {
  raise_default_method_error(x, "input_keys")
}


#' Extract input slot names from a \code{ModelInput}.
#' @export
input_keys.ModelInput <- function(x) {
  nm <- names(input_slots(x))
  
  if(is.null(nm)) character(0)
  else nm
}


#' Return vector of metadata slot keys
#'
#' Returns the names of the metadata slot keys present in a model input object.
#' Defined for both \code{ModelInput} and \code{EnsembleInput}.
#'
#' @param x A \code{ModelInput} or \code{EnsembleInput} object.
#' @param ... Further arguments passed to methods.
#'
#' @return character vector of metadata slot names.
#' @seealso \code{\link{metadata_keys.ModelInput}}, \code{\link{metadata_keys.EnsembleInput}}
#'
#' @author Andrew Roberts
#' @export
metadata_keys <- function(x, ...) {
  UseMethod("metadata_keys")
}


#' @export
metadata_keys.default <- function(x, ...) {
  raise_default_method_error(x, "metadata_keys")
}


#' Extract keys for metadata slots from a \code{ModelInput}.
#' @export
metadata_keys.ModelInput <- function(x) {
  nm <- names(metadata_slots(x))
  
  if(is.null(nm)) character(0)
  else nm
}


#' Return the names (not full keys) of leaves in ModelInput tree
#' @export
leaf_names <- function(x) {
  basename(leaf_keys(x))
}


#' Return the names (not full keys) of input slot leaves in ModelInput tree
#' @export
input_names <- function(x) {
  basename(input_keys(x))
}


#' Return the names (not full keys) of metadata slot leaves in ModelInput tree
#' @export
metadata_names <- function(x) {
  basename(metadata_keys(x))
}


#' Number of leaves in a ModelInput tree
#' @export
n_leaves <- function(x) {
  length(flatten_model_input(x))  
}


#' Number of Input Slots Generic
#'
#' Returns the number of input slots present in a model input object.
#' Defined for both single \code{ModelInput} and \code{EnsembleInput}.
#'
#' @param x A \code{ModelInput} or \code{EnsembleInput} object.
#' @param ... Further arguments passed to methods.
#'
#' @return Integer, number of slots.
#' @seealso \code{\link{n_inputs.ModelInput}}, \code{\link{n_inputs.EnsembleInput}}
#' 
#' @author Andrew Roberts
#' @export
n_inputs <- function(x, ...) {
  UseMethod("n_inputs")
}


#' @export
n_inputs.default <- function(x, ...) {
  raise_default_method_error(x, "n_inputs")
}


#' Number of input slots in a ModelInput
#' @export
n_inputs.ModelInput <- function(x) {
  length(input_slots(x))
}


#' Number of metadata leaves in a ModelInput tree
#' @export
n_metadata <- function(x) {
  length(metadata_slots(x))
}


#' Depth of a ModelInput tree
#'
#' The root of the tree is defined to have depth zero. A flat list has depth
#' one, and so on.
#' 
#' @param x A \code{ModelInput} object.
#' 
#' @author Andrew Roberts
#' @export
tree_depth <- function(x) {
  .check_model_input_type(x)
  
  recurse <- function(node, depth) {
    if(is_model_input_leaf(node)) return(depth)
    if(length(node) == 0L) return(depth) # Empty list
    max(vapply(node, recurse, integer(1), depth=depth+1L))
  }
  
  recurse(x$.data, depth=0L)
}


#' Print method for a \code{ModelInput}
#' @export
print.ModelInput <- function(x) {
  
  input_summary <- sprintf("ModelInput(n_slots = %s, n_metadata = %s, depth = %s)\n",
                           as.character(n_inputs(x)), as.character(n_metadata(x)), 
                           as.character(tree_depth(x)))
  
  cat(input_summary)
}


#' Summary method for a \code{ModelInput}
#' @export
summary.ModelInput <- function(x, ...) {
  
  .check_model_input_type(x)
  
  input_nm <- input_keys(x)
  meta_nm <- metadata_keys(x)
  num_slots <- length(input_nm)
  num_meta <- length(meta_nm)
  
  cat(sprintf("ModelInput with %d slots, %d metadata, depth %d\n",
              num_slots, num_meta, tree_depth(x)))
  
  if(num_slots > 0L) {
    cat("Slots:    ", paste(input_nm, collapse = ", "), "\n")
  }
  
  if(num_meta > 0L) {
    cat("Metadata: ", paste(meta_nm, collapse = ", "), "\n")
  }
  
  invisible(x)
}


#' Visualize ModelInput tree structure 
#'
#' Uses a directory-like visualization to print the tree structure.
#'
#' @param x A \code{ModelInput} object.
#' @param prefix character(1), string prefix to print at beginning of each line.
#' @param include_leaf_class logical(1), if \code{TRUE} prints the class of the 
#'  value of each leaf, in addition to its input slot or metadata slot label.
#'
#' @export
print_tree <- function(x, prefix="", include_leaf_class=TRUE) {
  .check_model_input_type(x)
  if(length(x$.data) == 0L) cat("Empty tree\n")
  
  recurse <- function(node, name=NULL, prefix="", is_last=TRUE) {
    connector <- if (is_last) "└── " else "├── "
    new_prefix <- if (is_last) paste0(prefix, "    ") else paste0(prefix, "│   ")
    
    # Leaf label
    if(is_tagged_leaf(node)) {
      if(is_input_slot(node)) label <- paste0(name, " [InputSlot")
      else if(is_metadata_slot(node)) label <- paste0(name, " [MetadataSlot")
      else stop("No tag defined for leaf with class: ", paste(class(node), collapse=", "))
      
      if(include_leaf_class) label <- paste(label, class(node$value)[1], sep=", ")
      label <- paste0(label, "]")
    } else {
      label <- name
    }
    
    # Print this node (skip root if NULL name)
    if(!is.null(name)) {
      cat(prefix, connector, label, "\n", sep="")
    }
    
    # Recurse on sub-tree
    if(is_model_input_branch(node)) {
      nms <- names(node)
      for(i in seq_along(nms)) {
        recurse(node[[i]], nms[i], new_prefix, i == length(nms))
      }
    }
  }
  
  recurse(x$.data, name=NULL, prefix=prefix, is_last=TRUE)
  invisible(x)
}


#' Convert between string and vector node key paths
#'
#' Converts between string format (e.g., \code{a/b/c}) and vector format
#' (e.g., \code{c("a", "b", "c")}) for node key paths.
#' 
#' @param path character string or vector key path.
#' @param as_string logical(1), if \code{TRUE} (default), convert to string 
#'  format. Otherwise convert to vector format.
#'  
#' @returns Either string or vector key path format. If the argument is already
#'  in the desired format, returns as is. Throws error if argument is not character.
#'
#' @author Andrew Roberts
.parse_key_path <- function(path, as_string=TRUE) {
  
  if(!is.character(path)) {
    stop("Key path must be string or character vector.")
  }
  
  already_is_string <- assertthat:::is.string(path)
  
  if(as_string) {
    if(already_is_string) path
    else .node_path_to_key(path)
  } else {
    if(already_is_string) .node_key_to_path(path)
    else path
  }
}


#' Convert vector key path to string
#'
#' Given a node path of the form \code{c("a", "b", "c")}, converts to 
#' the string \code{"a/b/c"}.
#'
#' @author Andrew Roberts
.node_path_to_key <- function(node_path) {
  paste(node_path, collapse="/")
}


#' Convert string key path to vector
#'
#' Given a node key of the form \code{"a/b/c"}, converts to  the vector 
#' \code{c("a", "b", "c")}. Key should not begin with "/".
#'
#' @author Andrew Roberts
.node_key_to_path <- function(node_key) {
  strsplit(node_key, split="/", fixed=TRUE)[[1]]
}


#' Validate a Nested List and Identify Leaves
#'
#' Recursive validator to determine whether a nested list can be wrapped as a
#' \code{ModelInput}. Any leaves that are not already tagged as an \code{InputSlot}
#' or \code{MetadataSlot} will be wrapped. If \code{untagged_is_input = TRUE} 
#' they will be wrapped as input slots; else metadata slots.
#'
#' @param x 
#' @param path character, key path in vector format.
#' 
#' @author Andrew Roberts
#' @export
.validate_and_wrap_model_input <- function(x, path, untagged_is_input) {
  
  .check_arg_is_not_model_input(x)
  
  if(is_model_input_leaf(x)) {
    if(is_input_slot(x) || is_metadata_slot(x)) return(x)
    
    # Object is not a list so is treated as a leaf. Assigned either as an
    # input slot or metadata slot.
    if(untagged_is_input) return(InputSlot(x))
    else return(MetadataSlot(x))
  } else {
    if(!has_unique_names(x) && length(x) > 0L) {
      stop(sprintf("All list elements must have unique names at level '%s'.",
                   .node_path_to_key(path)))
    }
  }
  
  # Recurse on sub-tree
  out <- list()
  for(nm in names(x)) {
    out[[nm]] <- .validate_and_wrap_model_input(x[[nm]], c(path, nm), untagged_is_input)
  }
  
  return(out)
}


#' Apply function to leaves of nested list
#'
#' See \code{\link{apply_to_leaves}}, which is a light wrapper that requires
#' \code{x} to be a \code{ModelInput}. This function allows \code{x} to be
#' a generic nested named list.
#' 
#' @author Andrew Roberts
.apply_to_leaves <- function(x, f, flatten=FALSE, drop_null=FALSE, ...) {
  
  .check_arg_is_not_model_input(x)
  
  # Recursive function
  recurse <- function(node, path=character()) {
    if(is_model_input_leaf(node)) {
      if(flatten) {
        key <- .node_path_to_key(path)
        return(setNames(list(f(node, path, ...)), key))
      } else {
        return(f(node, path, ...))
      }
    } else if(is_model_input_branch(node)) {
      branch_nodes <- lapply(names(node), function(nm) {
        recurse(node[[nm]], c(path, nm))
      })
      
      names(branch_nodes) <- names(node)
      if(flatten) {
        flat_branch <- Reduce(append, branch_nodes, init=list())
        if(drop_null) flat_branch <- Filter(Negate(is.null), flat_branch)
        return(flat_branch)
      } else {
        if(drop_null) {
          branch_nodes <- branch_nodes[!vapply(branch_nodes, is.null, logical(1))]
          if(length(branch_nodes) == 0L) branch_nodes <- NULL
        }
        
        return(branch_nodes)
      }
    } else {
      .raise_input_node_type_error(path=path)
    }
  }
  
  out <- recurse(x, path=character())
  if(length(out) == 0L) list()
  else out
}


#' Extract node from a nested list by its key path
#'
#' Given a key path (in string or vector form), extract the value at that
#' path. The object is extracted and returned as is. If no node is found at the 
#' key path, either an error is thrown or \code{NULL} is returned, depending on 
#' the argument \code{error_if_missing}.
#' 
#' @param tree A nested named list. Cannot be a \code{ModelInput} object.
#' @param path character, either a string key path of the form \code{a/b/c} or
#'  a vector path of the form \code{c("a", "b", "c")}.
#' @param error_if_missing logical(1), if \code{TRUE} throws an error if no node
#'  exists at the path; otherwise returns \code{NULL} in this case.
#'  
#' @returns The node at the key path. May return \code{NULL}
#'  if \code{error_if_missing = TRUE} and no node exists at the path.
#'  
#' @author Andrew Roberts  
.get_tree_node_at_path <- function(tree, path, error_if_missing=TRUE) {

  .check_arg_is_not_model_input(tree)
  path <- .parse_key_path(path, as_string=FALSE)

  for(node_name in path) {
    if(is_model_input_branch(tree) && !is.null(tree[[node_name]])) {
      tree <- tree[[node_name]]
    } else {
      if(error_if_missing) stop(sprintf("Path %s does not exist", .node_path_to_key(path)))
      else return(NULL)
    }
  }
  
  return(tree)
}


#' Extract a tree leaf by its key path
#'
#' This is a wrapper around `.get_tree_node_at_path()`, which can extract
#' leaves or sub-trees/branches. This function only returns leaves; if the
#' key path points to a branch then \code{NULL} is returned.
#'
#' @author Andrew Roberts
.get_tree_leaf_at_path <- function(tree, path, error_if_missing=TRUE) {
  val <- .get_tree_node_at_path(tree, path, error_if_missing)
  
  if(is_model_input_leaf(val)) return(val)
  else return(NULL)
}


#' Assign value in nested list by key path
#' 
#' Helper for \code{ModelInput} constructor.
#' 
#' @details
#' This function assigns a value at a specific entry in a nested list.
#' Leaves and branches are differentiated via the logic in 
#' \code{\link{is_model_input_leaf}}.
#' 
#' @param tree named list, potentially nested. Cannot be a \code{ModelInput}.
#' @param path character, vector key path to a node in the tree.
#' @param value R object to assign as the node value at the specified path.
#' @param allow_overwrite logical(1), if \code{FALSE} (default), throws error
#'  if non-NULL value already exists at the path. Otherwise, overwrites any
#'  existing value.
#' 
#' @returns The updated nested list with the value assigned at the specified
#'  path. If \code{allow_overwrite = TRUE} throws error if a value is already 
#'  found at that path.
#'
#' @author Andrew Roberts
.assign_tree_node_at_path <- function(tree, path, value, allow_overwrite=FALSE) {
  
  .check_arg_is_not_model_input(tree)
  path <- .parse_key_path(path, as_string=FALSE)
  
  if(length(path) == 1L) { # At terminal node in recursion
    if(!allow_overwrite && !is.null(tree[[path]])) {
      stop(sprintf("Conflict: value already exists at key '%s'", 
                   .node_path_to_key(path)))
    }
    
    tree[[path]] <- value
  } else {
    nm <- path[1]
    rest_of_path <- path[-1]
    
    if(is.null(tree[[nm]])) tree[[nm]] <- list()
    if(!allow_overwrite && is_model_input_leaf(tree[[nm]])) {
      stop(sprintf("Conflict: path '%s' tries to overwrite an existing leaf",
                   .node_path_to_key(path)))
    }
    
    # Turning a leaf into a branch.
    if(is_model_input_leaf(tree[[nm]])) tree[[nm]] <- list()
    
    tree[[nm]] <- .assign_tree_node_at_path(tree[[nm]], rest_of_path, value,
                                        allow_overwrite=allow_overwrite)
  }
  
  return(tree)
}


.raise_input_node_type_error <- function(path="", key=NULL) {
  if(is.null(key)) key <- .node_path_to_key(path)
  
  stop("Invalid node type at level: ", key,
       ". ModelInput nodes must be InputSlots, MetadataSlots, or pure lists.")
}


#' Throw error if object is not \code{ModelInput}
#' 
#' @param x An object
#' @returns Invisibly returns \code{TRUE} if \code{x} is an \code{ModelInput}.
#'  Otherwise throws an error.
#' 
#' @seealso \code{\link{ModelInput}}
#' @author Andrew Roberts
#' @export
.check_model_input_type <- function(x) {
  if (!is_model_input(x)) stop("Object is not a ModelInput.")
  
  invisible(TRUE)
}


# Primarily for functions that construct ModelInputs from nested lists. These
# functions are designed to operate on pure lists. Trying to pass ModelInput
# may result in weird results due to the overloading of `[[` and `$`.
# Extracts the name of the calling function to use in the error message.
.check_arg_is_not_model_input <- function(x) {
  if(is_model_input(x)) {
    fun_name <- as.character((sys.call(1)[[1]]))
    stop("Function `", fun_name, "()` does not support ModelInput argument")
  }
}


