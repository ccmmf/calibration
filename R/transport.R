# parameter transport maps: invertible maps that carry constrained ecosystem
# model parameters (positive, bounded, simplex valued) into an unconstrained R^k
# space where the ensemble Kalman update (method_eki.R) operates as if everything
# were Gaussian, and back to the native space. the map is chosen per parameter by
# its support:
#   unbounded (-Inf, Inf)      -> identity
#   strictly positive (a, Inf) -> shifted log
#   upper bounded (-Inf, b)    -> log distance to the upper bound
#   double bounded (a, b)      -> logit
#   simplex valued             -> stan style simplex transform
# supports are validated once at dist_list construction, so the maps assume valid
# bounds and carry no per call input guards.

##' @title Add a vector to every row of a matrix
##' @name add_vec_to_mat_rows
##' @param v numeric vector of length ncol(M).
##' @param M numeric matrix with length(v) columns.
##' @return M with v added to each row.
##' @keywords internal
add_vec_to_mat_rows <- function(v, M) {
  stopifnot(length(v) == ncol(M))
  M + rep(v, each = nrow(M))
}

##' @title Scalar parameter names for a (possibly multivariate) parameter block
##' @name get_scalar_param_names
##' @param dist_info one dist_list record.
##' @return character vector of one name per scalar parameter in the block.
##' @keywords internal
get_scalar_param_names <- function(dist_info) {
  if (!is.null(dist_info$scalar_names)) return(dist_info$scalar_names)
  if (dist_info$len == 1L) return(dist_info$param_name)
  paste(dist_info$param_name, seq_len(dist_info$len), sep = "_")
}

##' @title Parameter names across a dist_list
##' @name get_param_names
##' @param dist_list list of dist_info records.
##' @param flatten if TRUE return one name per scalar parameter; if FALSE the
##'   per-block names.
##' @return character vector of parameter names.
##' @keywords internal
get_param_names <- function(dist_list, flatten = TRUE) {
  if (flatten) {
    do.call(c, lapply(dist_list, get_scalar_param_names))
  } else {
    vapply(dist_list, function(x) x$param_name, character(1))
  }
}

##' @title Forward and inverse parameter transports for a dist_list
##' @name get_par_map_funcs
##' @author Meng Lai and Akash BV
##'
##' @description Builds the pair of maps the ensemble Kalman update needs: `fwd`
##' carries a constrained parameter matrix into the unconstrained space with
##' columns named "_<param>_<k>_", and `inv` maps back and attaches a per row
##' log-Jacobian-determinant attribute "log_det_J".
##'
##' @param dist_list list of dist_info records, each with a `constraint` support.
##' @return list(fwd, inv) of transport functions.
##' @export
get_par_map_funcs <- function(dist_list) {
  param_group_names <- get_param_names(dist_list, flatten = FALSE)
  par_map_list <- lapply(dist_list, get_dist_par_maps)

  par_map <- function(par) {
    if (is.null(dim(par))) {
      par <- matrix(par, nrow = 1L, dimnames = list(NULL, names(par)))
    }
    phi_list <- vector("list", length(dist_list))
    for (i in seq_along(dist_list)) {
      scalar_names <- get_scalar_param_names(dist_list[[i]])
      phi_list[[i]] <- par_map_list[[i]]$fwd(par[, scalar_names, drop = FALSE])
    }
    do.call(cbind, phi_list)
  }

  inv_par_map <- function(phi) {
    if (is.null(dim(phi))) {
      phi <- matrix(phi, nrow = 1L, dimnames = list(NULL, names(phi)))
    }
    par_list <- vector("list", length(dist_list))
    log_det_J <- rep(0, nrow(phi))
    for (i in seq_along(dist_list)) {
      # select this block's columns by exact prefix/suffix: the fwd map writes
      # "_<param>_<k>_", so a "_<param>_" prefix plus a "_" suffix tags the block
      # without interpreting the name as a regex.
      prefix <- paste0("_", param_group_names[i], "_")
      cn <- colnames(phi)
      phi_names <- cn[startsWith(cn, prefix) & endsWith(cn, "_")]
      par_list[[i]] <- par_map_list[[i]]$inv(phi[, phi_names, drop = FALSE])
      log_det_J <- log_det_J + drop(attr(par_list[[i]], "log_det_J"))
    }
    par <- do.call(cbind, par_list)
    attr(par, "log_det_J") <- log_det_J
    par
  }

  list(fwd = par_map, inv = inv_par_map)
}

##' @title Forward and inverse maps for a single parameter block
##' @name get_dist_par_maps
##' @param dist_info one dist_list record (param_name, constraint, len).
##' @return list(fwd, inv) for the block, columns named on the way out.
##' @keywords internal
get_dist_par_maps <- function(dist_info) {
  param_name <- dist_info$param_name
  scalar_names <- get_scalar_param_names(dist_info)
  constraint <- dist_info$constraint

  if (isTRUE(constraint == "simplex")) {
    map_func <- simplex_map
    inv_map_func <- inv_simplex_map
  } else if (is.null(constraint) || isTRUE(constraint == "None")) {
    map_funcs <- get_bound_constraint_map_funcs(c(-Inf, Inf))
    map_func <- map_funcs$fwd
    inv_map_func <- map_funcs$inv
  } else if (length(constraint) == 2L) {
    map_funcs <- get_bound_constraint_map_funcs(constraint)
    map_func <- map_funcs$fwd
    inv_map_func <- map_funcs$inv
  } else {
    PEcAn.logger::logger.severe("constraint ", constraint, " is not supported")
  }

  fwd <- function(par) {
    phi <- map_func(par)
    colnames(phi) <- paste0("_", param_name, "_", seq_len(ncol(phi)), "_")
    phi
  }
  inv <- function(phi) {
    par <- inv_map_func(phi)
    colnames(par) <- scalar_names
    par
  }
  list(fwd = fwd, inv = inv)
}

##' @title Select the transform for a bound constrained parameter
##' @name get_bound_constraint_map_funcs
##' @param bounds length-2 numeric support; Inf on either side selects a one sided
##'   or identity map.
##' @return list(fwd, inv).
##' @keywords internal
get_bound_constraint_map_funcs <- function(bounds) {
  if (is.infinite(bounds[1]) && is.infinite(bounds[2])) {
    fwd <- id_map
    inv <- inv_id_map
  } else if (is.infinite(bounds[1])) {
    fwd <- function(par) log_upper_map(par, b = bounds[2])
    inv <- function(phi) inv_log_upper_map(phi, b = bounds[2])
  } else if (is.infinite(bounds[2])) {
    fwd <- function(par) log_lower_map(par, a = bounds[1])
    inv <- function(phi) inv_log_lower_map(phi, a = bounds[1])
  } else {
    fwd <- function(par) logit_map(par, a = bounds[1], b = bounds[2])
    inv <- function(phi) inv_logit_map(phi, a = bounds[1], b = bounds[2])
  }
  list(fwd = fwd, inv = inv)
}

# logit map, double bounded

##' @keywords internal
logit_map <- function(par, a = 0, b = 1) {
  log((par - a) / (b - par))
}

##' @keywords internal
inv_logit_map <- function(phi, a = 0, b = 1) {
  # split by sign so the exponential cannot overflow for large |phi|.
  inverse_logit <- phi
  sel_geq_0 <- (phi >= 0)
  inverse_logit[sel_geq_0] <- 1 / (1 + exp(-phi[sel_geq_0]))
  inverse_logit[!sel_geq_0] <- exp(phi[!sel_geq_0]) / (1 + exp(phi[!sel_geq_0]))
  par <- a + inverse_logit * (b - a)
  attr(par, "log_det_J") <- log(b - a) + log(inverse_logit) + log(1 - inverse_logit)
  par
}

# shifted log map, one sided

##' @keywords internal
log_lower_map <- function(par, a = 0) {
  log(par - a)
}

##' @keywords internal
inv_log_lower_map <- function(phi, a = 0) {
  par <- a + exp(phi)
  attr(par, "log_det_J") <- phi
  par
}

##' @keywords internal
log_upper_map <- function(par, b) {
  log(b - par)
}

##' @keywords internal
inv_log_upper_map <- function(phi, b) {
  par <- b - exp(phi)
  attr(par, "log_det_J") <- phi
  par
}

# simplex map, stan style

##' @keywords internal
simplex_map <- function(par) {
  if (is.null(dim(par))) par <- matrix(par, nrow = 1L)
  d <- ncol(par)

  if (d == 2L) {
    z <- par[, 1L, drop = FALSE]
  } else {
    par <- par[, 1:(d - 1), drop = FALSE]
    lens <- cbind(
      rep(1, nrow(par)),
      1 - matrixStats::rowCumsums(par[, 1:(d - 2), drop = FALSE])
    )
    z <- par / lens
  }

  # round any z just above 1 back below 1 so the logit stays finite.
  z[z >= 1] <- 1 - .Machine$double.eps
  phi <- logit_map(z)
  shift <- log(d - seq(1, d - 1))
  add_vec_to_mat_rows(shift, phi)
}

##' @keywords internal
inv_simplex_map <- function(phi) {
  if (is.null(dim(phi))) phi <- matrix(phi, nrow = 1L)
  d <- ncol(phi) + 1L

  shift <- -log(d - seq(1, d - 1))
  z <- inv_logit_map(add_vec_to_mat_rows(shift, phi))

  par <- matrix(nrow = nrow(phi), ncol = d)
  g <- matrix(nrow = nrow(phi), ncol = d - 1)
  par[, 1] <- z[, 1]
  g[, 1] <- 1
  lens <- 1 - par[, 1]

  # seq_len(d-1)[-1] is empty for d == 2, so the 2-simplex skips this loop; a
  # seq(2, d-1) here would count downward in R and corrupt the d == 2 inverse.
  for (j in seq_len(d - 1L)[-1L]) {
    par[, j] <- lens * z[, j]
    g[, j] <- par[, j] * (1 - z[, j])
    lens <- lens - par[, j]
  }

  par[, d] <- 1 - rowSums(par[, 1:(d - 1), drop = FALSE])
  attr(par, "log_det_J") <- rowSums(log(g))
  par
}

# identity map

##' @keywords internal
id_map <- function(par) {
  if (is.null(dim(par))) par <- matrix(par, nrow = 1L)
  par
}

##' @keywords internal
inv_id_map <- function(phi) {
  if (is.null(dim(phi))) phi <- matrix(phi, nrow = 1L)
  attr(phi, "log_det_J") <- rep(0, nrow(phi))
  phi
}
