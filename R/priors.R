# priors for the calibrated parameters, plus the initial ensemble draw.
#
# priors are not hand tuned. they come from a pft's meta-analysis posterior
# (post.distns, read straight off disk), from an explicit specification, or, for
# a calibrated initial state, anchored to an observation with its measurement
# uncertainty as the spread. each returns the same dist_list the transport maps
# (transport.R) and the sampler consume. records carry the PEcAn (distn, parama,
# paramb) triple, so PEcAn.priors does the drawing here and the estimating
# upstream (fit.dist for samples, prior.fn for elicited quantiles); this file
# only constructs dist_lists from sources that already exist.

##' distn family -> support the transport map uses. positive-support families get
##' a log map, beta and unif a logit onto their own bounds, normal an identity.
##'
##' there is deliberately no default branch: a family falling through to
##' c(-Inf, Inf) estimates a bounded parameter on the whole real line, and the
##' posterior can leave the physical range without anything objecting. a new
##' family must state its support rather than inherit an unbounded one.
##' @param distn family name.
##' @param parama,paramb distribution parameters; uniform takes its support from them.
##' @keywords internal
.distn_support <- function(distn, parama = NULL, paramb = NULL) {
  distn <- as.character(distn)
  if (identical(distn, "unif")) {
    if (length(parama) != 1L || length(paramb) != 1L || anyNA(c(parama, paramb))) {
      PEcAn.logger::logger.severe(
        "uniform prior needs parama and paramb to define its support"
      )
    }
    return(c(parama, paramb))
  }
  switch(distn,
    weibull = ,
    lnorm   = ,
    gamma   = ,
    exp     = ,
    pois    = ,
    geom    = c(0, Inf),
    beta    = c(0, 1),
    norm    = c(-Inf, Inf),
    PEcAn.logger::logger.severe(
      "no declared support for distribution family '", distn,
      "'. Add it to .distn_support rather than letting it default to the real line."
    )
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
    if (!p %in% rownames(pd)) {
      PEcAn.logger::logger.severe("no posterior for '", p, "' in ", post_distns_path)
    }
    row <- pd[p, ]
    list(param_name = p, len = 1L,
         constraint = .distn_support(row$distn, row$parama, row$paramb),
         distn = as.character(row$distn),
         parama = row$parama, paramb = row$paramb)
  }), params)
}

##' @title Prior for a rate shared across several PFTs
##' @name prior_from_shared_postdistns
##' @author Akash BV
##'
##' @description A rate written into several PFTs is one calibrated quantity, so
##'   there must be one prior for it. This reads the requested traits from each
##'   named PFT's posterior and requires them to agree before returning a single
##'   record; disagreement is an error rather than a quiet choice of the first.
##'
##' @param params character vector of PEcAn trait names to calibrate.
##' @param posterior_files named character vector of post.distns paths, one per soil PFT.
##' @return a dist_list, one record per trait.
##' @export
prior_from_shared_postdistns <- function(params, posterior_files) {
  stopifnot(length(posterior_files) >= 1L, !is.null(names(posterior_files)))
  per_pft <- lapply(posterior_files, function(f) prior_from_postdistns(params, f))
  reference <- per_pft[[1]]
  for (i in seq_along(per_pft)[-1]) {
    for (p in params) {
      a <- reference[[p]][c("distn", "parama", "paramb")]
      b <- per_pft[[i]][[p]][c("distn", "parama", "paramb")]
      if (!isTRUE(all.equal(a, b))) {
        PEcAn.logger::logger.severe(
          "prior for '", p, "' differs between soil PFTs '", names(posterior_files)[1],
          "' (", a$distn, " ", a$parama, ", ", a$paramb, ") and '",
          names(posterior_files)[i], "' (", b$distn, " ", b$parama, ", ", b$paramb,
          "). One shared calibrated rate needs one prior; reconcile the PFTs or ",
          "calibrate them separately."
        )
      }
    }
  }
  reference
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
    constraint <- .distn_support(distn, a, b)
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
##' @param meta observation meta (variable, treatment_id, obs_year, value, var_obs).
##' @param prefix column prefix marking the state entries (e.g. "soilInit.").
##' @param variable the observed variable whose slots anchor the state; the joint
##'   meta can span several variables and an unscoped anchor would take the wrong one.
##' @param from_unit unit the observation is reported in (udunits string).
##' @param to_unit unit the model state is in (udunits string).
##' @param anchor_year observation year to anchor on; defaults to the earliest.
##' @return a dist_list keyed <prefix><site>, in site order.
##' @export
state_prior_from_obs <- function(meta, prefix, from_unit, to_unit, variable,
                                 anchor_year = NULL) {
  # scope to one variable before anchoring: a joint meta can span several
  # variables and sites, and an unscoped selection would anchor the state
  # on whichever variable sorts first.
  base <- meta[meta$variable == variable, ]
  if (nrow(base) == 0L) {
    PEcAn.logger::logger.severe("no ", variable, " slots to anchor an initial state on")
  }
  if (is.null(anchor_year)) anchor_year <- min(base$obs_year)
  base <- base[base$obs_year == anchor_year, ]
  if (nrow(base) == 0L) {
    PEcAn.logger::logger.severe("no ", variable, " slots in anchor year ", anchor_year)
  }
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
