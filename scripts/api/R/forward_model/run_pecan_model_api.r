# forward_model/run_model_api.r
#
# Depends: PEcAn.settings, PEcAn.utils

# Implements standardized protocols for running PEcAn models, ensuring a 
# consistent interface for specifying outputs and returning outputs in a standard
# format. The lowest-level building block consists of an API for prepping a 
# model run (i.e., writing configs). Higher level protocols define interfaces
# for starting model runs (prepping then executing) and running a model 
# (prepping, executing, and reading inputs). APIs are provided for both
# single runs and ensemble model runs. 
#
# APIs for single model run:
#   run_model(), prep_pecan_model_run(), start_pecan_model_run()    
# 
# APIs for ensemble model run:
#   run_model_ensemble(), prep_pecan_ensemble_run(), start_pecan_ensemble_run()
#
# `run_model.Settings()` and `run_model_ensemble.Settings()` are the PEcAn methods
# for the run model and run model ensemble generics.


# ------------------------------------------------------------------------------
# Single Model Run
# ------------------------------------------------------------------------------


#' Run a PEcAn model and return outputs
#'
#' A standardized API for a single PEcAn model run, which entails writing a
#' model config, starting the model run, and reading outputs from file.
#' 
#' @details
#' At present, this API is defined so that PEcAn's standard model run workflow
#' can be executed without modification. The PEcAn \code{settings} object contains
#' settings that will remain fixed, while the PEcAn \code{model_input} object
#' contains model inputs that may vary across executions of the model. This
#' object serves a dual purpose: (1) it overwrites values in \code{settings},
#' and (2) it stores arguments to pass to the write config function. 
#' \code{model_input} is not allowed to contain certain settings that should 
#' not be overwritten, including the outdir, rundir, and modeloutdir filepaths
#' and information from the "model" block. See \code{\link{PecanModelInput}}
#' for more details.
#'
#' @param model_obj A PEcAn \code{Settings} object.
#' @param model_input A PEcAn \code{ModelInput} object.
#' @param run_id character(1), a unique string identifier for the run. Will be 
#'  auto-generated if not provided.
#' @param overwrite_runs_file logical(1), if \code{TRUE}, overwrites any existing
#'  \code{runs.txt} file in the run directory. Otherwise, appends to this file.
#'  If appending, note that any runs executed from this directory using
#'  \code{PEcAn.workflow::start_model_runs()} will run both the newly appended
#'  and old runs. Even in this case, this method will still only return the 
#'  results associated with \code{run_id}, the current run. 
#' @param read_output_args Additional named arguments passed to \code{PEcAn.utils::read.output()}.
#' @param ... Not used.
#'
#' @returns The model outputs corresponding to the model run with ID \code{run_id}.
#'  The outputs are formatted as returned by \code{PEcAn.utils::read.output()}.
#'  An attribute \code{run_id} is attached to the output object.
#'  
#' @author Andrew Roberts
#' @export
run_model.Settings <- function(model_obj, model_input, run_id=NULL, 
                               overwrite_runs_file=FALSE, read_output_args=list(), ...) {
  
  # Write configs, start model run, write outputs to file.
  run_id <- start_pecan_model_run(settings=model_obj,
                                  model_input=model_input,
                                  run_id=run_id,
                                  overwrite_runs_file=overwrite_runs_file)
  
  # Read outputs from file.
  run_output_path <- file.path(model_obj$modeloutdir, run_id)
  read_output_args <- merge_named_lists(read_output_args, 
                                        list(runid=run_id, outdir=run_output_path))
  model_output <- do.call(PEcAn.utils::read.output, read_output_args)
  attr(model_output, "run_id") <- run_id
  
  return(model_output)
}


#' Prep and Execute PEcAn Model Run
#'
#' This function behaves like \code{\link{run_model.Settings}}, but differs
#' in that it does not attempt to read the model output from file.
#'
#' @returns the run ID (invisibly).
#'
#' @author Andrew Roberts
#' @export
start_pecan_model_run <- function(settings, model_input, run_id=NULL,
                                  overwrite_runs_file=FALSE) {
  
  run_id <- prep_pecan_model_run(settings=settings, 
                                 model_input=model_input, 
                                 run_id=run_id, 
                                 overwrite_runs_file=overwrite_runs_file)
  
  PEcAn.workflow::start_model_runs(settings, write=FALSE)
  
  return(invisible(run_id))
  
}


#' Prep a PEcAn Model Run
#'
#' Writes PEcAn config to file, and writes the \code{run_id} to the
#' \code{runs.txt} file. Does not actually run the model. See 
#' \code{\link{run_model.Settings}} and \code{\link{start_pecan_model_run}}.
#'
#' @returns Invisibly returns the \code{run_id}. Loads the PEcAn model package
#'  and uses the write config function from this package to write configuration
#'  files to disk.
#'
#' @author Andrew Roberts
#' @export
prep_pecan_model_run <- function(settings, model_input, run_id=NULL, 
                                 overwrite_runs_file=FALSE) {

  .check_pecan_model_input_type(model_input)
  
  # Overwrite defaults in `settings` with values specified in `model_input`.
  settings <- update_pecan_settings(settings, model_input)
  
  # If run ID is not provided, randomly generate one.
  if(is.null(run_id) || is.na(run_id)) run_id <- uuid::UUIDgenerate()

  # Load model package.
  model_type <- settings$model$type
  PEcAn.utils::load.modelpkg(model_type)
  
  # Create run and output directories.
  dir.create(file.path(settings$rundir, run_id), recursive=TRUE)
  dir.create(file.path(settings$modeloutdir, run_id), recursive=TRUE)
  
  # Write model config to file.
  model_write_config <- paste0("write.config.", model_type)
  config_args <- list(settings=settings, defaults=settings$pfts, run.id=run_id)
  config_args <- c(config_args, config_args(model_input))
  
  # TODO: temporary - adding so that "traits.values" can be passed as a vector.
  # This should probably be changed at the write config level rather than here.
  if("trait.values" %in% names(config_args)) {
    trait_values <-  config_args[["trait.values"]]
  
    if(is.atomic(trait_values)) {
      config_args[["trait.values"]] <- list(pft = trait_values)
    }
  }
  
  do.call(model_write_config, args=config_args)
  
  # Either append to or overwrite existing "runs.txt" file.
  cat(as.character(run_id),
      file=file.path(settings$rundir, "runs.txt"),
      sep="\n",
      append=!overwrite_runs_file)
  
  return(invisible(run_id))
}


# ------------------------------------------------------------------------------
# Model Ensemble Run
# ------------------------------------------------------------------------------

#' Run PEcAn model ensemble and return outputs
#'
#' The PEcAn method for the \code{run_model_ensemble()} generic.
#' 
#' @details
#' Writes configs to file for each run within the ensemble. All run IDs are 
#' written to the file \code{file.path(settings$rundir, "runs.txt")}. The 
#' \code{PEcAn.workflow::start_model_runs()} function is used to execute all 
#' model runs. The output from the runs is then read into a list (one element
#' per run) by calling \code{PEcAn.utils::read.output()} for each run.
#' 
#' @param model_obj A PEcAn \code{settings} file.
#' @param ens_input A PEcAn \code{EnsembleInput} object.
#' @param overwrite_runs_file logical(1), if \code{TRUE} then any existing 
#'  \code{runs.txt} file is overwritten. Otherwise it is appended to.
#' @param read_output_args Additional named arguments passed to \code{PEcAn.utils::read.output()}.
#' @param ... Not used.
#' 
#' @returns list of length equal to the number of runs in the ensemble, with
#'  each element storing the output for the respective run. The list names are
#'  set to the run IDs.
#'  
#' @author Andrew Roberts
#' @export
run_model_ensemble.Settings <- function(model_obj, ens_input,
                                        overwrite_runs_file=FALSE,
                                        read_output_args=list(), ...) {

  run_ids <- start_pecan_model_ensemble_run(model_obj, ens_input,
                                            overwrite_runs_file=overwrite_runs_file)
  
  read_single_run_output <- function(run_id) {
    args <- merge_named_lists(read_output_args, 
                              list(runid=run_id, 
                                   outdir=file.path(model_obj$modeloutdir, run_id)))
    do.call(PEcAn.utils::read.output, args)
  }
  
  # Read list of model output from each run
  model_ens_output <- lapply(run_ids, read_single_run_output)
  setNames(model_ens_output, run_ids)
}


start_pecan_model_ensemble_run <- function(settings, ens_input,
                                           overwrite_runs_file=FALSE) {
  
  run_ids <- prep_pecan_model_ensemble_run(settings, ens_input, 
                                           overwrite_runs_file=overwrite_runs_file)
  
  # TODO: need to enforce requirement that rundir is constant across all runs.
  # Need to identify what components of settings is used by start_model_runs().
  # If it is just rundir then we can create a settings object with the 
  # constant rundir value and pass that here.
  PEcAn.workflow::start_model_runs(settings, write=FALSE)
  
  return(invisible(run_ids))
}


prep_pecan_model_ensemble_run <- function(settings, ens_input, 
                                          overwrite_runs_file=FALSE) {
  
  # TODO: need to fix `run_ids` method to avoid confusion with common variable name.
  r_ids <- run_ids(ens_input)
  
  prep_single_run <- function(i) {
    run_id <- r_ids[i]
    overwrite <- (i == 1) && overwrite_runs_file

    prep_pecan_model_run(settings = settings, 
                         model_input = get_run_input(ens_input, run_id),
                         run_id = run_id,
                         overwrite_runs_file = overwrite)
  }
  
  r_ids <- vapply(seq_along(r_ids), prep_single_run, character(1))
  
  invisible(r_ids)
}


#' Determine modeloutdir for a particular run in the ensemble
#'
#' Given the \code{run_id}, determines the `modeloutdir` used for that run.
#' This value will be taken from `ens_input` if it is overwritten; otherwise,
#' it will be the default in `settings`.
#' 
#' @param settings PEcAn \code{Settings} object containing defaults.
#' @param ens_input An \code{EnsembleInput} object.
#' @param run_id character(1), the run ID.
#' 
#' @returns The `modeloutdir` value for the run.
#' 
#' @author Andrew Roberts
#' @export
get_run_modeloutdir <- function(settings, ens_input, run_id) {
  model_input <- get_run_input(ens_input, run_id)
  resolve_pecan_settings_value(settings, model_input, "modeloutdir")
}


# ------------------------------------------------------------------------------
# Model Wrappers
# ------------------------------------------------------------------------------

#' Generate a PEcAn specific wrapper around \code{run_model_ensemble()} for batch inputs
#'
#' A PEcAn-specific wrapper around \code{wrap_partial_slot_batch()} that provides
#' additional special functionality for PEcAn runs. Note that 
#' \code{wrap_partial_slot_batch()} can also be used with PEcAn models, but 
#' this function is typically recommended for common PEcAn use cases.
#' 
#' @details
#' See \code{\link{wrap_partial_slot_batch}} for information on how the model 
#' is wrapped. Only the additional PEcAn-specific functionality is discussed here.
#' This PEcAn helper is set up to provide dynamic creation of output paths
#' (rundir and modeloutdir). The base path \code{settings$outdir} will be
#' fixed. The argument \code{dynamic_subdir} should be a quoted expression
#' that may depend on variables in the calling scope of the wrapped model.
#' When the wrapped model is run, the quoted expression is evaluated like
#' Let \code{val <- eval(dynamic_subdir, envir=parent.frame())}. The rundir
#' and modeloutdir paths are then set to 
#' \code{file.path(settings$outdir, val, "run")} and 
#' \code{file.path(settings$outdir, val, "out")}, respectively.
#' This allows the paths to change based on the context in the calling 
#' environment of the wrapped model (e.g., an iteration value of an algorithm).
#'
#' @param dynamic_subdir A quoted expression or NULL. If NULL, no dynamic
#'  path creation is done. Otherwise, \code{dynamic_subdir} is used for 
#'  dynamic path creation as described in details.
#'  
#' @author Andrew Roberts  
#' @export
wrap_pecan_partial_slot_batch <- function(settings, default, slot_names, 
                                          output_operator=NULL, 
                                          verbose=TRUE, dynamic_subdir=NULL,
                                          read_output_args=list()) {

  if(is.null(dynamic_subdir)) {
    .arg_update_fn <- NULL
    .dynamic_args <- NULL
  } else {
    
    # Variable used to dynamically update filepaths.
    .dynamic_args <- list(subdir = dynamic_subdir)
    
    # Dynamically update rundir and modeloutdir. 
    .arg_update_fn <- function(args) {
      settings <- args$model_obj
      args$model_obj$rundir <- file.path(settings$outdir, args$subdir, "run")
      args$model_obj$modeloutdir <- file.path(settings$outdir, args$subdir, "out")
      return(args)
    }
  }
  
  wrap_partial_slot_batch(model_obj = settings,
                          default = default,
                          slot_names = slot_names,
                          output_operator = output_operator,
                          verbose = verbose,
                          .fixed_args = list(overwrite_runs_file=TRUE,
                                             read_output_args=read_output_args),
                          .dynamic_args = .dynamic_args,
                          .arg_update_fn = .arg_update_fn)
}





