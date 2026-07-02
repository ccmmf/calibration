# priors for the calibrated parameters, plus the initial ensemble draw.
#
# priors are not hand tuned. they come from a pft's meta-analysis posterior
# (post.distns, read straight off disk), from an
# explicit specification (a biologically plausible, zero bounded distribution
# written down), or, for a calibrated initial state, anchored to an observation
# with its measurement uncertainty as the spread. each returns the same dist_list
# the transport maps (transport.R) and the sampler consume.

##' distn family -> support the transport map uses. positive-support families get
##' a log map, beta a logit, normal an identity, and a uniform its own bounds
##' (handled by prior_from_specs, not here).
##' @keywords internal
.distn_support <- function(distn) {
  switch(as.character(distn),
    weibull = ,
    lnorm   = ,
    gamma   = ,
    exp     = ,
    pois    = ,
    geom    = c(0, Inf),
    beta    = c(0, 1),
    norm    = c(-Inf, Inf),
    c(-Inf, Inf)
  )
}

##' @title Priors from a PFT meta-analysis posterior
##' @name prior_from_postdistns
##' @author Akash BV
##'
##' @description Reads the requested traits' priors from a PFT's post.distns (the
##' object the PEcAn ensemble workflow samples), so a prior revision in the PFT
##' propagates without an edit here. Fails loud, and names the fix, if a trait has
##' no entry rather than silently substituting one.
##'
##' @param params character vector of PEcAn trait names to calibrate.
##' @param post_distns_path path to the PFT's post.distns.Rdata.
##' @return a dist_list, one record per trait carrying its support `constraint`
##'   and the post.distns `distn`/`parama`/`paramb`.
##' @export
prior_from_postdistns <- function(params, post_distns_path) {
  if (!file.exists(post_distns_path)) {
    PEcAn.logger::logger.severe("post.distns not found: ", post_distns_path)
  }
  e <- new.env()
  load(post_distns_path, envir = e)
  pd <- get(ls(e)[[1]], envir = e)
  missing <- setdiff(params, rownames(pd))
  if (length(missing) > 0L) {
    PEcAn.logger::logger.severe(
      "no prior in post.distns for: ", paste(missing, collapse = ", "),
      "; add it to the pft (PEcAn.priors::fit.dist from data, or ",
      "DEoptim(prior.fn) from a literature CI). post.distns has: ",
      paste(rownames(pd), collapse = ", ")
    )
  }
  stats::setNames(lapply(params, function(p) {
    row <- pd[p, ]
    list(param_name = p, len = 1L,
         constraint = .distn_support(row$distn),
         distn = as.character(row$distn),
         parama = row$parama, paramb = row$paramb)
  }), params)
}

##' @title Priors from an explicit specification
##' @name prior_from_specs
##' @author Akash BV
##'
##' @description Builds priors for parameters the PFT carries no posterior for,
##' from a written down distribution (biologically plausible, zero bounded), not a
##' value tuned to the model output. A uniform is bounded to its own [parama,
##' paramb] (a logit map); every other family takes its distributional support.
##'
##' @param specs named list, param -> list(distn, parama, paramb).
##' @return a dist_list keyed by parameter name.
##' @export
prior_from_specs <- function(specs) {
  stats::setNames(lapply(names(specs), function(p) {
    s <- specs[[p]]
    distn <- as.character(s$distn)
    a <- as.numeric(s$parama)
    b <- as.numeric(s$paramb)
    constraint <- if (identical(distn, "unif")) c(a, b) else .distn_support(distn)
    list(param_name = p, len = 1L, constraint = constraint,
         distn = distn, parama = a, paramb = b)
  }), names(specs))
}

##' @title Per-site prior for a calibrated initial state, anchored to an observation
##' @name state_prior_from_obs
##' @author Akash BV
##'
##' @description One lognormal record per site, centred on that site's observed
##' value at `anchor_year` and spread by that observation's measurement
##' uncertainty. This anchors an estimated initial state to the data instead of
##' letting it float, which would otherwise let the calibration absorb model error
##' into the state. The observation is converted from its reported unit to the
##' model's unit with PEcAn.utils::ud_convert.
##'
##' @param meta observation meta (treatment_id, study_year, value, var_obs).
##' @param prefix column prefix marking the state entries (e.g. "soilInit.").
##' @param from_unit unit the observation is reported in (udunits string).
##' @param to_unit unit the model state is in (udunits string).
##' @param anchor_year study_year to anchor on; defaults to the earliest.
##' @return a dist_list keyed <prefix><site>, in site order.
##' @export
state_prior_from_obs <- function(meta, prefix, from_unit, to_unit,
                                 anchor_year = NULL) {
  if (is.null(anchor_year)) anchor_year <- min(meta$study_year)
  base <- meta[meta$study_year == anchor_year, ]
  base <- base[order(base$treatment_id), ]
  center <- PEcAn.utils::ud_convert(base$value, from_unit, to_unit)
  spread <- PEcAn.utils::ud_convert(sqrt(base$var_obs), from_unit, to_unit)
  stats::setNames(lapply(seq_len(nrow(base)), function(i) {
    sdlog <- sqrt(log1p((spread[i] / center[i])^2))
    list(param_name = paste0(prefix, base$treatment_id[i]), len = 1L,
         constraint = c(0, Inf), distn = "lnorm",
         parama = log(center[i]), paramb = sdlog)
  }), paste0(prefix, base$treatment_id))
}

##' clamp double bounded columns into their open support. get.sample draws are
##' untruncated, so a value can land on a finite bound and make the logit map
##' non-finite; one sided / unbounded supports use log / identity maps that stay
##' finite and are left alone.
##' @keywords internal
clamp_to_constraints <- function(U, dist_list) {
  for (d in dist_list) {
    nm <- get_scalar_param_names(d)
    b <- d$constraint
    if (is.null(b) || length(b) != 2L || any(is.infinite(b))) next
    eps <- 1e-6 * (b[2] - b[1])
    U[, nm] <- pmin(pmax(U[, nm], b[1] + eps), b[2] - eps)
  }
  U
}

##' @title Draw the initial ensemble from a prior
##' @name sample_initial_ensemble
##' @author Akash BV
##'
##' @description Draws J particles per parameter with PEcAn.priors::get.sample
##' (which supports every r<distn> family the prior may use), assembles the named
##' matrix, and clamps each double bounded column into its open support so the
##' first transport is finite.
##'
##' @param dist_list a dist_list from the prior_from_* constructors.
##' @param J ensemble size.
##' @param seed integer RNG seed set by the caller for reproducibility; NULL to
##'   leave the stream untouched.
##' @return matrix (J, D) with named columns, every value within its support.
##' @export
sample_initial_ensemble <- function(dist_list, J, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  cols <- lapply(dist_list, function(d) {
    PEcAn.priors::get.sample(
      tibble::tibble(distn = d$distn, parama = d$parama, paramb = d$paramb),
      n = J
    )
  })
  U <- matrix(unlist(cols), nrow = J, ncol = length(cols),
              dimnames = list(NULL, names(dist_list)))
  clamp_to_constraints(U, dist_list)
}
