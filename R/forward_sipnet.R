# sipnet forward model. wraps a prepared pecan multisite run as the
# fwd(U, iteration) -> G the calibration calls. only this file knows sipnet and
# the pecan run machinery; the estimator in method_eki.R knows neither.
#
# one iteration is one ensemble where only the calibrated parameters change: met,
# events, and uncalibrated pools are pinned to one member, otherwise the prediction
# spread measures the input draw and cov(U, G) in the kalman gain is sampling
# noise. input uncertainty belongs in a separate forward pass.
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
##' @param var_map named list keyed by observation variable, each
##'   `list(model_var, from, to)` (see harvest_output_to_G): the crosswalk from
##'   each observed variable to its model output and units.
##' @param soil_pfts character vector of soil PFT names that share the calibrated
##'   rates; the same proposal column is written into each (see inject_traits).
##' @param state_prefix column prefix marking calibrated initial-state entries in
##'   U; when present each is written into the initial condition per particle.
##' @param state_pool the initial condition pool variable the state writes into.
##' @param base_out_dir parent directory for the per iteration model output.
##' @param fixed_traits trait names pinned through the run dir `default.param`,
##'   dropped from the baseline sample so the pinned value is not overwritten by
##'   the PFT posterior median.
##' @param raw_obs the untransformed target the model output is harvested against;
##'   its `transform` (the linear map from raw to fitted slots) is applied to G so
##'   model and observations are the same quantity. NULL fits the raw slots.
##' @return function(U, iteration) -> matrix (J, P) aligned to names(obs$y).
##' @export
make_forward_sipnet <- function(settings, obs, n_particles, var_map,
                                soil_pfts,
                                state_prefix = "soilInit.",
                                state_pool = "soil_organic_carbon_content",
                                base_out_dir = settings$outdir,
                                fixed_traits = character(0),
                                raw_obs = NULL) {
  transform <- raw_obs$transform
  if (!is.null(raw_obs) && is.null(transform)) {
    PEcAn.logger::logger.severe(
      "raw_obs carries no transform; the fitted target cannot be reached from the ",
      "model output without one"
    )
  }
  harvest_meta <- if (is.null(raw_obs)) obs$meta else raw_obs$meta
  obs_order <- names(obs$y)
  meta <- obs$meta
  window <- run_window(settings)

  # the multisite site ids, iterated in settings order
  treatments <- vapply(settings, function(x) x$run$site$id, character(1))

  # one existing ic per site supplies the fixed (uncalibrated) pools held
  # constant across particles when the initial state is calibrated.
  ic_template_paths <- stats::setNames(
    lapply(seq_along(settings),
           function(i) settings[[i]]$run$inputs$poolinitcond$path[[1]]),
    treatments)

  baseline <- baseline_trait_samples(settings$pfts, n_particles, fixed_traits)

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

    ensemble.samples <- inject_traits(baseline, soil_pfts, U[, trait_cols, drop = FALSE])

    # calibrated initial state: write one ic per (site, particle) with the pool
    # set to that particle's proposal and point the run's poolinitcond at them, so
    # particle j uses its own ic and the design indexes 1:J. otherwise recycle the
    # prepared run's ic ensemble.
    if (length(state_cols) > 0L) {
      ic_paths <- write_state_ensemble(U, state_cols, state_prefix, state_pool,
                                       treatments, file.path(out_itr, "IC_files"),
                                       ic_template_paths)
      s <- repoint_poolinitcond(s, treatments, ic_paths, n_particles)
      poolinitcond_idx <- seq_len(n_particles)
    } else {
      poolinitcond_idx <- rep(1L, n_particles)
    }
    # a design's `param` column indexes into the samples it was drawn with, so the
    # two arrive together; supplying both also keeps pecan from generating its own
    # design, which pins met and events to the first member.
    input_design <- list(
      design_matrix = data.frame(
        param        = seq_len(n_particles),
        poolinitcond = poolinitcond_idx,
        met          = 1L,
        events       = 1L
      ),
      samples = list(
        ensemble.samples = ensemble.samples,
        trait.samples    = lapply(ensemble.samples, as.list),
        sa.samples       = NULL,
        runs.samples     = list(),
        env.samples      = list()
      )
    )

    s <- PEcAn.workflow::runModule.run.write.configs(s, input_design = input_design)
    PEcAn.workflow::runModule_start_model_runs(s, stop.on.error = FALSE)

    G <- harvest_output_to_G(s$modeloutdir, harvest_meta, var_map, window)
    if (!is.null(transform)) G <- apply_transform(G, transform)
    missing <- setdiff(obs_order, colnames(G))
    if (length(missing) > 0L) {
      PEcAn.logger::logger.severe(
        length(missing), " observation slots have no forward output (e.g. ",
        paste(utils::head(missing, 5), collapse = ", "),
        "); every treatment's ensemble runs must finish before harvest"
      )
    }
    G[, obs_order, drop = FALSE]
  }
}

##' baseline trait samples: every parameter at its prior median, replicated over
##' particles, one data.frame per pft. calibrated columns are overwritten by U.
##' traits named in `fixed` are dropped so the run dir default.param value stands;
##' a trait left in here overwrites it.
##' @keywords internal
baseline_trait_samples <- function(pfts, n_particles, fixed = character(0)) {
  out <- list()
  for (pft in pfts) {
    e <- new.env()
    load(pft$posterior.files, envir = e)
    pd <- get(ls(e)[[1]], envir = e)
    keep <- setdiff(rownames(pd), fixed)
    pd <- pd[keep, , drop = FALSE]
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

##' write the proposal U into each named soil pft: the calibrated rates are one
##' shared quantity, not one per pft. fails if a named pft is absent rather than
##' silently calibrating a subset.
##' @keywords internal
inject_traits <- function(baseline, soil_pfts, U_traits) {
  missing_pfts <- setdiff(soil_pfts, names(baseline))
  if (length(missing_pfts) > 0L) {
    PEcAn.logger::logger.severe(
      "soil PFT(s) not present in the prepared settings: ",
      paste(missing_pfts, collapse = ", "), "; the run carries ",
      paste(names(baseline), collapse = ", ")
    )
  }
  es <- baseline
  for (pft in soil_pfts) {
    for (nm in colnames(U_traits)) es[[pft]][[nm]] <- U_traits[, nm]
  }
  es
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
##' so particle j uses its own ic at every site and the design indexes 1:J. sites
##' without a calibrated state (no `ic_paths` entry) keep their template ic,
##' recycled to J paths so the shared design column stays in range; overwriting
##' them with an empty list silently drops every one of their run dirs.
##' @keywords internal
repoint_poolinitcond <- function(settings, treatments, ic_paths, n_particles) {
  for (i in seq_along(treatments)) {
    t <- treatments[i]
    if (!is.null(ic_paths[[t]])) {
      settings[[i]]$run$inputs$poolinitcond$path <- as.list(ic_paths[[t]])
    } else {
      have <- unlist(settings[[i]]$run$inputs$poolinitcond$path, use.names = FALSE)
      if (length(have) == 0L) {
        PEcAn.logger::logger.severe(
          "block ", t, " has neither a calibrated state column nor a pinned ",
          "poolinitcond path; every block needs an initial condition"
        )
      }
      settings[[i]]$run$inputs$poolinitcond$path <-
        as.list(rep_len(have, n_particles))
    }
  }
  settings
}

##' @title Run years per treatment from a multisite settings object
##' @name run_window
##' @author Akash BV
##'
##' @description First and last run year of each treatment, for reading model
##'   output over that treatment's own window; a joint run spans different
##'   periods per site.
##'
##' @param settings a PEcAn multisite settings object.
##' @return integer matrix (2 x n_treatments), columns named by treatment.
##' @export
run_window <- function(settings) {
  win <- vapply(settings, function(x) {
    c(as.integer(format(as.Date(x$run$start.date), "%Y")),
      as.integer(format(as.Date(x$run$end.date), "%Y")))
  }, integer(2))
  colnames(win) <- vapply(settings, function(x) x$run$site$id, character(1))
  win
}
