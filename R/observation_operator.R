# the observation operators: everything that maps between model output, raw
# observation slots, and the fitted target.
#
# harvest_output_to_G reads a model ensemble into the prediction matrix G aligned
# to the raw slots. period_mean_contrast and contrast_target contract raw slots
# into fitted quantities (a period-mean level plus treatment contrasts; a
# per-date treatment contrast), and bind_obs stacks targets. each contraction is
# linear and records itself as a matrix in `transform`, applied identically to
# observations and to G, so the fitted quantity is the same operation on both
# sides by construction.

##' @title Harvest a model ensemble into the prediction matrix G
##' @name harvest_output_to_G
##' @author Akash BV
##'
##' @description For each ENS-<member>-<treatment> run under `out_root`, reads the
##' model outputs the treatment's slots need over that treatment's run window,
##' samples each slot at the midpoint of its date window, converts to the
##' observation unit, and assembles the J x P matrix aligned to the observation
##' slots. Assumes every expected run has finished; a missing run output fails
##' loud in read.output rather than being silently dropped.
##'
##' @param out_root the model output directory holding the ENS-* run dirs.
##' @param meta observation meta (slot, treatment_id, variable, min_date, max_date).
##' @param var_map named list keyed by observation `variable`, each
##'   `list(model_var, from, to)`: the model output to read, its unit, and the
##'   observation unit.
##' @param run_window integer matrix (2 x n_treatments) of first and last run year,
##'   columns named by treatment. Each treatment is read over its own window; a
##'   joint run spans different periods per site.
##' @return matrix (members x slots) named by observation slot, member-ordered.
##' @export
harvest_output_to_G <- function(out_root, meta, var_map, run_window) {
  run_dirs <- list.files(out_root, pattern = "^ENS-")
  rows <- lapply(run_dirs, function(rid) {
    treat  <- sub("^ENS-[0-9]+-", "", rid)
    member <- as.integer(sub("^ENS-0*([0-9]+)-.*", "\\1", rid))
    md <- meta[meta$treatment_id == treat, ]
    if (nrow(md) == 0L) return(NULL)                 # a run with no matching slots
    if (!treat %in% colnames(run_window)) {
      PEcAn.logger::logger.severe("no run window for treatment ", treat)
    }
    win_years <- run_window[, treat]
    model_vars <- unique(vapply(md$variable, function(v) var_map[[v]]$model_var, character(1)))
    o <- PEcAn.utils::read.output(
      runid = rid, outdir = file.path(out_root, rid),
      start.year = win_years[1], end.year = win_years[2],
      variables = model_vars, dataframe = TRUE, verbose = FALSE
    )
    dates <- as.Date(o$posix)
    vals <- vapply(seq_len(nrow(md)), function(i) {
      vm <- var_map[[md$variable[i]]]
      col <- o[[vm$model_var]]
      a <- as.Date(md$min_date[i]); b <- as.Date(md$max_date[i])
      # an observation outside the run window must fail here. substituting the
      # nearest available date returns a finite number from the wrong year and makes
      # a dry run look clean when the slot was never simulated.
      if (a < min(dates) || b > max(dates)) {
        PEcAn.logger::logger.severe(
          "observation slot ", md$slot[i], " spans ", as.character(a), " to ",
          as.character(b), ", outside the ", treat, " run window ",
          as.character(min(dates)), " to ", as.character(max(dates)),
          ". Extend the run or drop the observation; do not substitute a neighbor."
        )
      }
      native <- col[which.min(abs(dates - (a + (b - a) / 2)))]
      PEcAn.utils::ud_convert(native, vm$from, vm$to)
    }, numeric(1))
    tibble::tibble(member = member, slot = md$slot, value = vals)
  })
  long <- do.call(rbind, rows)
  wide <- tidyr::pivot_wider(long, names_from = "slot", values_from = "value")
  wide <- wide[order(wide$member), ]
  G <- as.matrix(wide[, setdiff(colnames(wide), "member"), drop = FALSE])
  rownames(G) <- wide$member
  G
}

##' shrink correlations toward zero by the least amount that restores positive
##' definiteness, leaving the diagonal exactly as estimated. a mean over K years
##' gives an empirical covariance of rank at most K - 1, so more quantities than
##' years is singular by construction and the EnKF's Cholesky of cov(G) + Sigma
##' has no reason to succeed. the marginal variances are well estimated from K
##' years; the correlations are not, so only they are damped.
##' @keywords internal
.shrink_to_pd <- function(S, label = "", tol = 1e-8) {
  if (min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) > tol) return(S)
  D <- diag(diag(S), nrow = nrow(S))
  for (lambda in seq(0.05, 1, by = 0.05)) {
    Sl <- (1 - lambda) * S + lambda * D
    if (min(eigen(Sl, symmetric = TRUE, only.values = TRUE)$values) > tol) {
      PEcAn.logger::logger.info(
        "period mean covariance for ", label, " was singular (rank ",
        qr(S)$rank, " of ", nrow(S), "); correlations shrunk by ", lambda,
        " toward the diagonal, marginal variances kept"
      )
      dimnames(Sl) <- dimnames(S)
      return(Sl)
    }
  }
  PEcAn.logger::logger.severe(
    "period mean covariance for ", label,
    " is not positive definite even with correlations fully removed"
  )
}

##' @title Period mean level and treatment contrasts
##' @name period_mean_contrast
##' @author Akash BV
##'
##' @description Collapses a per treatment per year series into one level slot for
##'   the control and one contrast slot per remaining treatment, all on the mean
##'   over the period. A bijection of the per treatment means: the control level
##'   carries the net rate, the contrasts carry the treatment effects, and one
##'   level slot keeps a calibrated initial state out of the contrasts.
##'
##'   The covariance is the empirical covariance of the annual series divided by
##'   the number of years (the standard error of the mean), which carries the
##'   shared-control structure of the contrasts.
##'
##' @param obs a build_obs target list(y, Sigma, meta).
##' @param variable the per treatment per year variable to collapse.
##' @param control treatment id every contrast is taken against.
##' @param years optional integer vector restricting the period; defaults to every
##'   year present.
##' @param new_variable name for the resulting variable.
##' @return an obs list carrying one level slot and one contrast slot per
##'   treatment, with the contraction recorded in `transform`.
##' @export
period_mean_contrast <- function(obs, variable, control, years = NULL,
                                 new_variable = paste0(variable, "_periodmean")) {
  meta <- obs$meta
  sub <- meta[meta$variable == variable, , drop = FALSE]
  if (nrow(sub) == 0L) {
    PEcAn.logger::logger.severe("no slots for variable '", variable, "'")
  }
  if (!is.null(years)) {
    sub <- sub[sub$obs_year %in% as.integer(years), , drop = FALSE]
  }
  if (!control %in% sub$treatment_id) {
    PEcAn.logger::logger.severe(
      "control treatment '", control, "' is not in variable '", variable,
      "'. Present: ", paste(unique(sub$treatment_id), collapse = ", ")
    )
  }

  yrs <- sort(unique(sub$obs_year))
  trts <- unique(sub$treatment_id)
  others <- setdiff(trts, control)

  # a mean over an unbalanced panel is not the same quantity across treatments,
  # and the contrasts would not be paired by year. refuse rather than average
  # whatever is present.
  cells <- table(sub$treatment_id, sub$obs_year)
  if (any(cells != 1L)) {
    bad <- which(cells != 1L, arr.ind = TRUE)
    PEcAn.logger::logger.severe(
      "period mean needs exactly one slot per treatment per year; ",
      nrow(bad), " cell(s) violate that, e.g. treatment ",
      rownames(cells)[bad[1, "row"]], " year ", colnames(cells)[bad[1, "col"]]
    )
  }
  MIN_YEARS <- 3L
  if (length(yrs) < MIN_YEARS) {
    PEcAn.logger::logger.severe(
      "period mean needs at least ", MIN_YEARS, " years to estimate its own ",
      "standard error; got ", length(yrs)
    )
  }

  slot_of <- function(t, y) sub$slot[sub$treatment_id == t & sub$obs_year == y]
  series <- vapply(trts, function(t) {
    vapply(yrs, function(y) obs$y[[slot_of(t, y)]], numeric(1))
  }, numeric(length(yrs)))
  dimnames(series) <- list(as.character(yrs), trts)

  # columns of the fitted quantity: control level, then each contrast paired by year
  X <- cbind(series[, control, drop = FALSE],
             series[, others, drop = FALSE] - series[, control])
  level_slot <- paste0(new_variable, "__", control, "__level")
  contrast_slots <- paste0(new_variable, "__", others, "__vs_", control)
  colnames(X) <- c(level_slot, contrast_slots)

  n_yr <- length(yrs)
  y_new <- colMeans(X)
  Sigma <- .shrink_to_pd(stats::cov(X) / n_yr, label = new_variable)

  first <- sub[match(c(control, others), sub$treatment_id), , drop = FALSE]
  new_meta <- tibble::tibble(
    slot = colnames(X),
    variable = new_variable,
    sitename = first$sitename,
    treatment_id = c(control, paste0(others, "_vs_", control)),
    obs_year = NA_integer_,
    min_date = min(sub$min_date),
    max_date = max(sub$max_date),
    min_depth = first$min_depth,
    max_depth = first$max_depth,
    units = first$units,
    observation_level = "period_mean",
    n_rep = n_yr,
    value = unname(y_new),
    var_obs = unname(diag(Sigma))
  )

  # no model variable is "the period mean minus the control", so the operation is
  # recorded as a matrix and applied to G. averaging and differencing are both
  # linear; one matrix does both.
  tmat <- matrix(0, ncol(X), nrow(meta), dimnames = list(colnames(X), meta$slot))
  for (y in yrs) tmat[level_slot, slot_of(control, y)] <- 1 / n_yr
  for (k in seq_along(others)) {
    for (y in yrs) {
      tmat[contrast_slots[k], slot_of(others[k], y)] <- 1 / n_yr
      tmat[contrast_slots[k], slot_of(control, y)] <-
        tmat[contrast_slots[k], slot_of(control, y)] - 1 / n_yr
    }
  }

  list(y = stats::setNames(unname(y_new), colnames(X)),
       Sigma = Sigma, meta = new_meta, transform = tmat)
}

##' @title Contract per treatment observations into a treatment contrast
##' @name contrast_target
##' @author Akash BV
##'
##' @description One slot per date, the difference between a treatment and its
##'   control on the dates both were measured. Chamber flux data supports
##'   treatment comparisons rather than absolute magnitudes, which is what this
##'   contraction fits.
##'
##' @param obs a build_obs target list(y, Sigma, meta).
##' @param variable the per treatment variable to contract.
##' @param treatment,control treatment ids to compare.
##' @param new_variable name for the resulting variable.
##' @return an obs list carrying one slot per shared date, with the contraction
##'   recorded in `transform`.
##' @export
contrast_target <- function(obs, variable, treatment, control,
                            new_variable = paste0(variable, "_contrast")) {
  meta <- obs$meta
  sub <- meta[meta$variable == variable, , drop = FALSE]
  if (nrow(sub) == 0L) {
    PEcAn.logger::logger.severe("no slots for variable '", variable, "'")
  }
  present <- unique(sub$treatment_id)
  absent <- setdiff(c(treatment, control), present)
  if (length(absent) > 0L) {
    PEcAn.logger::logger.severe(paste0(
      "contrast needs both treatments; missing: ", paste(absent, collapse = ", "),
      ". Present: ", paste(present, collapse = ", ")
    ))
  }

  a <- sub[sub$treatment_id == treatment, , drop = FALSE]
  b <- sub[sub$treatment_id == control, , drop = FALSE]
  dates <- intersect(a$min_date, b$min_date)
  unpaired <- setdiff(union(a$min_date, b$min_date), dates)
  if (length(unpaired) > 0L) {
    PEcAn.logger::logger.severe(paste0(
      length(unpaired), " date(s) do not carry both treatments and cannot form a ",
      "contrast: ", paste(utils::head(unpaired, 5), collapse = ", ")
    ))
  }

  var_obs <- diag(obs$Sigma)

  rows <- lapply(dates, function(d) {
    ra <- a[a$min_date == d, , drop = FALSE]
    rb <- b[b$min_date == d, , drop = FALSE]
    va <- obs$y[[ra$slot]]
    vb <- obs$y[[rb$slot]]
    r <- ra
    r$slot <- paste0(new_variable, "__", d)
    r$variable <- new_variable
    r$treatment_id <- paste0(treatment, "_vs_", control)
    r$value <- va - vb
    # the two cells are independent measurements, so their variances add
    r$var_obs <- var_obs[[ra$slot]] + var_obs[[rb$slot]]
    r
  })
  new_meta <- dplyr::bind_rows(rows)
  Sigma <- diag(new_meta$var_obs, nrow = nrow(new_meta))
  dimnames(Sigma) <- list(new_meta$slot, new_meta$slot)

  tmat <- matrix(0, nrow(new_meta), nrow(meta),
                 dimnames = list(new_meta$slot, meta$slot))
  for (d in dates) {
    row <- paste0(new_variable, "__", d)
    tmat[row, a$slot[a$min_date == d]] <- 1
    tmat[row, b$slot[b$min_date == d]] <- -1
  }
  list(y = stats::setNames(new_meta$value, new_meta$slot),
       Sigma = Sigma, meta = new_meta, transform = tmat)
}

##' @title Combine observation targets into one
##' @name bind_obs
##' @author Akash BV
##'
##' @description Stacks several obs lists into a single target with a
##'   block-diagonal covariance. Targets from different variables are assumed
##'   independent of each other, which is what block diagonal encodes;
##'   correlations within a target are carried through from the input blocks.
##'
##' @param ... obs lists, each list(y, Sigma, meta, transform).
##' @return a single obs list with the transforms combined.
##' @export
bind_obs <- function(...) {
  parts <- list(...)
  slots <- unlist(lapply(parts, function(p) p$meta$slot), use.names = FALSE)
  if (anyDuplicated(slots) > 0L) {
    PEcAn.logger::logger.severe(
      "duplicate slot name(s) across targets: ",
      paste(unique(slots[duplicated(slots)]), collapse = ", ")
    )
  }
  meta <- dplyr::bind_rows(lapply(parts, function(p) tibble::as_tibble(p$meta)))
  n <- length(slots)
  Sigma <- matrix(0, n, n, dimnames = list(slots, slots))
  for (p in parts) {
    Sigma[p$meta$slot, p$meta$slot] <- p$Sigma[p$meta$slot, p$meta$slot]
  }
  # a target without a transform cannot be combined with contracted ones: the
  # forward applies one map to one G. build_obs already stacks raw targets.
  no_tf <- vapply(parts, function(p) is.null(p$transform), logical(1))
  if (any(no_tf)) {
    PEcAn.logger::logger.severe("target(s) ", paste(which(no_tf), collapse = ", "),
                                " carry no transform")
  }
  raw_slots <- unique(unlist(lapply(parts, function(p) colnames(p$transform))))
  tmat <- matrix(0, length(slots), length(raw_slots),
                 dimnames = list(slots, raw_slots))
  for (p in parts) {
    tmat[rownames(p$transform), colnames(p$transform)] <- p$transform
  }
  list(y = stats::setNames(unlist(lapply(parts, function(p) as.numeric(p$y))), slots),
       Sigma = Sigma, meta = meta, transform = tmat)
}

##' @title Apply a target transform to a prediction matrix
##' @name apply_transform
##' @author Akash BV
##'
##' @description Puts model predictions on the raw slots through the same linear
##'   map the observations went through, so the fitted quantity is the same
##'   operation on both sides.
##'
##' @param G prediction matrix (members x raw slots).
##' @param transform matrix mapping raw slots (columns) to fitted slots (rows).
##' @return matrix (members x fitted slots), columns named by fitted slot.
##' @export
apply_transform <- function(G, transform) {
  out <- G[, colnames(transform), drop = FALSE] %*% t(transform)
  colnames(out) <- rownames(transform)
  out
}
