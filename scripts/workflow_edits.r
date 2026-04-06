# f
# extra functionality/ revision to /projectnb/dietzelab/menglai/pecan/modules/prob.tools/R/forward_model

# Write config function expects IC to be a named list.
# ic_ens <- as.list(site_ics[i,])



#' Prep a PEcAn Model Run
#'
#' Writes PEcAn config to file, and writes the \code{run_id} to the
#' \code{runs.txt} file. Does not actually run the model. See 
#' \code{\link{run_model.Settings}} and \code{\link{start_pecan_model_run}}.
#'
#' @returns Invisibly returns the \code{run_id}. Loads the PEcAn model package
#'  and uses the write config function from this package to write configuration
#'  files to disk.

# added ic processing --- 
prep_pecan_model_run <- function(settings, model_input, run_id=NULL, 
                                 overwrite_runs_file=FALSE, mat_rule=NULL) {
  
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
  # config_args <- list(settings=settings, defaults=settings$pfts, run.id=run_id)
  # config_args <- c(config_args, config_args(model_input))
  
  config_in <- list(settings=settings, defaults=settings$pfts, run.id=run_id)
  config_in <- c(config_in, config_args(model_input))
  
  if("trait.values" %in% names(config_in)) {
    trait_values <-  config_in[["trait.values"]]
    
    if(is.atomic(trait_values)) {
      
      # identify which entries are IC (by prefix)
      ic_idx_all <- grep("^site_[0-9]+_", names(trait_values))
      
      if (length(ic_idx_all) > 0) {
        # figure out site index k for this run
        site_idx <- mat_rule[run_id, "settings/run/site"]
        
        if (is.na(site_idx) || site_idx < 1) {
          stop("Could not determine site for run", run_id)
        }
        
        # extract IC entries for that site and strip prefix
        prefix <- paste0("site_", site_idx, "_")
        ic_idx <- grep(paste0("^", prefix), names(trait_values))
        
        if (length(ic_idx) == 0) {
          stop("No IC entries found in trait.values for", prefix)
        }
        
        ic_vec <- trait_values[ic_idx]
        names(ic_vec) <- sub(paste0("^", prefix), "", names(ic_vec))
      }
      
      # keep only true traits in trait.values (remove ALL site_* entries)
      trait_only <- trait_values[-ic_idx_all]
      
      # write.config.SIPNET expects named list
      # config_in[["trait.values"]] <- as.list(trait_only)
      if(is.atomic(trait_only)) {
        config_in[["trait.values"]] <- list(pft = trait_only)
      }
      config_in[["IC"]] <- as.list(ic_vec)
    }
  }
  do.call(model_write_config, args=config_in)
  
  # Either append to or overwrite existing "runs.txt" file.
  cat(as.character(run_id),
      file=file.path(settings$rundir, "runs.txt"),
      sep="\n",
      append=!overwrite_runs_file)
  
  return(invisible(run_id))
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
                         overwrite_runs_file = overwrite,
                         mat_rule = ens_input$mat_rule)
  }
  
  r_ids <- vapply(seq_along(r_ids), prep_single_run, character(1))
  
  invisible(r_ids)
}