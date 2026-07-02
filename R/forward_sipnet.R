# sipnet forward model. wraps a prepared pecan multisite run as the
# fwd(U, iteration) -> G the calibration calls. only this file knows sipnet and
# the pecan run machinery; the estimator in method_eki.R knows neither.
#
# one iteration is one ensemble where only the calibrated parameters change; met,
# events, and the pools we do not calibrate are built once and held fixed. a call
# writes the proposal into the sample object and, when an initial state is
# calibrated, the ic files, runs the pecan config and model steps, and harvests
# the output into G.
#
# launching is left to pecan and the prepared host block. runModule_start_model_runs
# submits through the settings host (qsub, sge_array_launcher.sh, Njobmax, qstat)
# exactly as written and blocks on qstat until the ensemble finishes. nothing here
# touches those launcher fields; each iteration only points its own output dirs.

##' @title Build the SIPNET forward model closure
##' @name make_forward_sipnet
##' @author Akash BV
##'
##' @description Returns fwd(U, iteration): run one SIPNET ensemble at the
##' parameter matrix U (J particles x D, columns named by PEcAn trait, plus
##' optional <state_prefix><site> columns for a calibrated initial pool) and
##' return the prediction matrix G (J x P) in observation-slot order. Everything
##' other than the calibrated parameters is built once and held fixed.
##'
##' @param settings a prepared PEcAn multisite settings object (the forward run).
##' @param obs the build_obs target list(y, Sigma, meta); names(y) are the slots.
##' @param n_particles ensemble size J.
##' @param harvest_var the model output variable to compare to the observations.
##' @param from_unit the model unit of harvest_var (udunits string).
##' @param to_unit the observation unit to convert the harvest to.
##' @param soil_pft name of the PFT whose traits U overwrites.
##' @param state_prefix column prefix marking calibrated initial-state entries in
##'   U; when present each is written into the initial condition per particle.
##' @param state_pool the initial condition pool variable the state writes into.
##' @param base_out_dir parent directory for the per iteration model output.
##' @return function(U, iteration) -> matrix (J, P) aligned to names(obs$y).
##' @export
make_forward_sipnet <- function(settings, obs, n_particles,
                                harvest_var, from_unit, to_unit,
                                soil_pft = "soil",
                                state_prefix = "soilInit.",
                                state_pool = "soil_organic_carbon_content",
                                base_out_dir = settings$outdir) {
  obs_order <- names(obs$y)
  meta <- obs$meta
  start_year <- as.integer(format(as.Date(settings[[1]]$run$start.date), "%Y"))
  end_year   <- as.integer(format(as.Date(settings[[1]]$run$end.date), "%Y"))

  inputs   <- settings[[1]]$run$inputs
  n_met    <- length(inputs$met$path)
  n_events <- length(inputs$events$path)
  n_ic     <- length(inputs$poolinitcond$path)

  # the multisite site ids, iterated in settings order
  treatments <- vapply(settings, function(x) x$run$site$id, character(1))

  # one existing ic per site supplies the fixed (uncalibrated) pools held
  # constant across particles when the initial state is calibrated.
  ic_template_paths <- stats::setNames(
    lapply(seq_along(settings),
           function(i) settings[[i]]$run$inputs$poolinitcond$path[[1]]),
    treatments)

  baseline <- baseline_trait_samples(settings$pfts, n_particles)
  # config + model steps run from the prepared run dir: the host's launcher path
  # is relative to it.
  run_dir <- dirname(settings$outdir)

  function(U, itr) {
    out_itr <- file.path(base_out_dir, paste0("itr", itr))
    s <- settings
    s$outdir <- out_itr
    s$modeloutdir <- file.path(out_itr, "out")
    s$rundir <- file.path(out_itr, "run")
    s$host$outdir <- s$modeloutdir
    s$host$rundir <- s$rundir
    dir.create(s$outdir, recursive = TRUE, showWarnings = FALSE)

    state_cols <- grep(paste0("^", state_prefix), colnames(U), value = TRUE)
    trait_cols <- setdiff(colnames(U), state_cols)

    ensemble.samples <- inject_traits(baseline, soil_pft, U[, trait_cols, drop = FALSE])
    write_samples_rdata(ensemble.samples, file.path(s$outdir, "samples.Rdata"))

    # calibrated initial state: write one ic per (site, particle) with the pool
    # set to that particle's proposal and point the run's poolinitcond at them, so
    # particle j uses its own ic and the design indexes 1:J. otherwise recycle the
    # prepared run's ic ensemble.
    if (length(state_cols) > 0L) {
      ic_paths <- write_state_ensemble(U, state_cols, state_prefix, state_pool,
                                       treatments, file.path(out_itr, "IC_files"),
                                       ic_template_paths)
      s <- repoint_poolinitcond(s, treatments, ic_paths)
      poolinitcond_idx <- seq_len(n_particles)
    } else {
      poolinitcond_idx <- rep_len(seq_len(n_ic), n_particles)
    }
    input_design <- tibble::tibble(
      param        = seq_len(n_particles),
      poolinitcond = poolinitcond_idx,
      met          = rep_len(seq_len(n_met), n_particles),
      events       = rep_len(seq_len(n_events), n_particles)
    )

    old_wd <- setwd(run_dir)
    on.exit(setwd(old_wd), add = TRUE)
    s <- PEcAn.workflow::runModule.run.write.configs(s, input_design = input_design)
    PEcAn.workflow::runModule_start_model_runs(s, stop.on.error = FALSE)

    G <- harvest_output_to_G(s$modeloutdir, meta, harvest_var,
                             start_year, end_year, from_unit, to_unit)
    G[, obs_order, drop = FALSE]
  }
}

##' fixed baseline trait samples: every parameter at its prior median (the
##' PEcAn.priors::get.sample p = 0.5 of the post.distns row, so it matches the
##' family the pft carries), replicated over particles, one data.frame per pft.
##' the calibrated columns are overwritten by U; the rest stay fixed so the
##' prediction spread reflects only the estimated parameters.
##' @keywords internal
baseline_trait_samples <- function(pfts, n_particles) {
  out <- list()
  for (pft in pfts) {
    e <- new.env()
    load(pft$posterior.files, envir = e)
    pd <- get(ls(e)[[1]], envir = e)
    med <- vapply(seq_len(nrow(pd)), function(i) {
      PEcAn.priors::get.sample(pd[i, c("distn", "parama", "paramb")], p = 0.5)
    }, numeric(1))
    names(med) <- rownames(pd)
    df <- as.data.frame(matrix(rep(med, each = n_particles), nrow = n_particles))
    colnames(df) <- names(med)
    out[[pft$name]] <- df
  }
  out
}

##' overwrite the pft's calibrated trait columns with the proposal U.
##' @keywords internal
inject_traits <- function(baseline, soil_pft, U_traits) {
  es <- baseline
  for (nm in colnames(U_traits)) es[[soil_pft]][[nm]] <- U_traits[, nm]
  es
}

##' write samples.Rdata in the object run.write.configs expects.
##' @keywords internal
write_samples_rdata <- function(ensemble.samples, file) {
  trait.samples <- lapply(ensemble.samples, as.list)
  pft.names <- names(ensemble.samples)
  trait.names <- lapply(ensemble.samples, names)
  sa.samples <- NULL
  runs.samples <- list()
  env.samples <- list()
  save(ensemble.samples, trait.samples, sa.samples, runs.samples,
       pft.names, trait.names, env.samples, file = file)
}

##' write the per-(site, particle) initial condition ensemble for a calibrated
##' state. for each site, read its fixed pools once from an existing ic, then
##' write one ic per particle with `state_pool` set to that particle's proposal
##' (in the model's native ic units, as drawn). returns the written paths per site.
##' @keywords internal
write_state_ensemble <- function(U, state_cols, prefix, state_pool, treatments,
                                 ic_dir, ic_template_paths) {
  paths <- list()
  for (t in treatments) {
    col <- paste0(prefix, t)
    if (!col %in% state_cols) next
    ic_pools <- PEcAn.data.land::pool_ic_netcdf2list(ic_template_paths[[t]])
    dir.create(file.path(ic_dir, t), recursive = TRUE, showWarnings = FALSE)
    paths[[t]] <- vapply(seq_len(nrow(U)), function(j) {
      ic_pools$vals[[state_pool]] <- U[j, col]
      PEcAn.SIPNET::veg2model.SIPNET(
        outfolder = file.path(ic_dir, t), poolinfo = ic_pools, siteid = t, ens = j
      )$file
    }, character(1))
  }
  paths
}

##' point each site's poolinitcond path at the freshly written per particle ics,
##' so particle j uses its own ic at every site and the design indexes 1:J.
##' @keywords internal
repoint_poolinitcond <- function(settings, treatments, ic_paths) {
  for (i in seq_along(treatments)) {
    settings[[i]]$run$inputs$poolinitcond$path <- as.list(ic_paths[[treatments[i]]])
  }
  settings
}
