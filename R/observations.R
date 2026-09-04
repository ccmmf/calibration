# build a calibration target (y, Sigma, meta) from the curated cal/val observations.
#
# the estimator aligns by slot name only, so this layer owns everything about the
# curated table: it reads replicate level records only, every record must carry
# its target's declared unit, two unit bases never average into one cell, the
# likelihood variance comes from replicate spread or the reported standard error,
# and cells are keyed by depth so two depth increments cannot collapse into one
# mean.
#
# dates come from min_date/max_date, never from study_year, because study_year can
# be a study offset at one site and a calendar year at another.

##' read the observations table from a cal-val-data checkout.
##' @keywords internal
read_cal_val_observations <- function(cal_val_dir) {
  f <- file.path(cal_val_dir, "data", "observations.csv")
  if (!file.exists(f)) {
    PEcAn.logger::logger.severe("curated observations not found at ", f)
  }
  readr::read_csv(f, show_col_types = FALSE, progress = FALSE) |>
    dplyr::filter(!is.na(variable))
}

##' variance of each cell mean: replicate spread where the cell has replicates,
##' otherwise the reported standard error. no relative floor -- it would override
##' a reported error by orders of magnitude.
##' @keywords internal
cell_variance <- function(cells) {
  v <- dplyr::case_when(
    cells$n_rep > 1L & is.finite(cells$cell_sd) & cells$cell_sd > 0 ~ cells$cell_sd^2 / cells$n_rep,
    is.finite(cells$reported_se) & cells$reported_se > 0            ~ cells$reported_se^2,
    TRUE                                                            ~ NA_real_
  )

  # small-n sd^2/n lands near zero often enough that one cell can take most of a
  # target's inverse-variance weight; pooled_cv instead estimates one relative
  # measurement error across the target's cells and scales it by each cell's mean.
  pooled <- cells$variance_model == "pooled_cv"
  for (v_name in unique(cells$variable[pooled])) {
    idx <- pooled & cells$variable == v_name
    rel <- ifelse(is.finite(cells$cell_sd[idx]) & cells$cell_sd[idx] > 0,
                  cells$cell_sd[idx], cells$reported_se[idx]) / abs(cells$cell_mean[idx])
    cv <- stats::median(rel, na.rm = TRUE)
    if (!is.finite(cv) || cv <= 0) {
      PEcAn.logger::logger.severe(
        "target ", v_name, " declares pooled_cv but no cell has usable replicate ",
        "spread to pool from"
      )
    }
    v[idx] <- (cv * abs(cells$cell_mean[idx]))^2 / pmax(cells$n_rep[idx], 1L)
  }
  v
}

##' @title Build the calibration target from the curated cal/val observations
##' @name build_obs
##' @author Akash BV
##'
##' @description Assembles the observation vector `y`, its diagonal likelihood
##'   covariance `Sigma`, and the per-slot `meta`, stacking every target into one
##'   vector. A cell is one (variable, site, treatment, year, depth) group; the slot
##'   name carries all of them so the estimator, which aligns by name only, never has
##'   to know what a site or a variable is.
##'
##' @param cal_val_dir the cal-val-data checkout root.
##' @param targets list of target specs: `variable`, `sites`, `units` (the unit
##'   every source record must carry), and optionally `source_variables` (raw names
##'   feeding it, default `variable`), `years` (inclusive c(first, last) filter),
##'   `variance` ("replicate", the default, or "pooled_cv"), and `cell_period`
##'   ("year", the default, or "date" for an episodic sub-annual flux).
##' @return list(y, Sigma, meta).
##' @export
build_obs <- function(cal_val_dir, targets) {
  raw_all <- read_cal_val_observations(cal_val_dir)

  cells <- dplyr::bind_rows(lapply(targets, function(tg) {
    rows <- target_rows(raw_all, tg)
    rows |>
      dplyr::summarize(
        cell_mean   = mean(value, na.rm = TRUE),
        cell_sd     = stats::sd(value, na.rm = TRUE),
        n_rep       = sum(!is.na(value)),
        reported_se = mean(reported_se, na.rm = TRUE),
        min_date    = as.character(min(obs_date_start)),
        max_date    = as.character(max(obs_date_end)),
        variable    = dplyr::first(target_variable),
        units       = dplyr::first(target_units),
        variance_model = dplyr::first(variance_model),
        observation_level = dplyr::first(observation_level),
        .by = c(cell, sitename, treatment_id, obs_year, cell_period, min_depth, max_depth)
      )
  }))

  cells$var_obs <- cell_variance(cells)
  bad <- !is.finite(cells$var_obs) | cells$var_obs <= 0
  if (any(bad)) {
    PEcAn.logger::logger.severe(
      sum(bad), " observation cell(s) have no usable variance (no replicate ",
      "spread, no reported standard error): ",
      paste(utils::head(cells$cell[bad]), collapse = ", "),
      ". Give them a reported error in the curated source or drop them from the target."
    )
  }
  cells <- dplyr::arrange(cells, variable, sitename, treatment_id, obs_year)

  if (any(duplicated(cells$cell))) {
    PEcAn.logger::logger.severe(
      "duplicate observation slot(s): ",
      paste(utils::head(cells$cell[duplicated(cells$cell)]), collapse = ", ")
    )
  }

  y <- stats::setNames(cells$cell_mean, cells$cell)
  Sigma <- diag(cells$var_obs, nrow = length(y))
  dimnames(Sigma) <- list(cells$cell, cells$cell)

  meta <- dplyr::select(cells, slot = cell, variable, sitename, treatment_id,
                        obs_year, min_date, max_date, min_depth, max_depth, units,
                        observation_level, n_rep, value = cell_mean, var_obs)

  PEcAn.logger::logger.info(
    length(y), " observation slots across ", dplyr::n_distinct(meta$variable),
    " variable(s) and ", dplyr::n_distinct(meta$sitename), " site(s)"
  )
  list(y = y, Sigma = Sigma, meta = meta)
}

##' filter, unit-check and key one target's rows (see build_obs for the spec).
##' @keywords internal
target_rows <- function(raw_all, tg) {
  stopifnot(!is.null(tg$variable), !is.null(tg$sites), !is.null(tg$units))

  srcs <- if (is.null(tg$source_variables)) tg$variable else tg$source_variables
  rows <- dplyr::filter(raw_all, variable %in% srcs,
                        sitename %in% as.character(tg$sites),
                        observation_level == "replicate")
  if (nrow(rows) == 0L) {
    PEcAn.logger::logger.severe("no rows for target ", tg$variable,
                                " at site(s) ", paste(tg$sites, collapse = ", "))
  }

  # dates come from min_date/max_date; study_year is not a usable key here.
  rows <- rows |>
    dplyr::mutate(
      obs_date_start = as.Date(min_date),
      obs_date_end   = as.Date(max_date)
    )
  undated <- is.na(rows$obs_date_start) | is.na(rows$obs_date_end)
  if (any(undated)) {
    PEcAn.logger::logger.severe(
      sum(undated), " row(s) of target ", tg$variable,
      " have no min_date/max_date, so the operator cannot place them in a run window. ",
      "Exclude them from the target or date them in the curated source."
    )
  }
  rows$obs_year <- as.integer(format(rows$obs_date_start, "%Y"))
  if (!is.null(tg$years)) {
    rows <- dplyr::filter(rows, obs_year >= tg$years[1], obs_year <= tg$years[2])
    if (nrow(rows) == 0L) {
      PEcAn.logger::logger.severe("target ", tg$variable, ": year filter removed every row")
    }
  }

  rows$target_variable <- tg$variable
  rows$target_units <- tg$units
  rows$variance_model <- if (is.null(tg$variance)) "replicate" else tg$variance

  # an episodic sub-annual flux keyed by year averages its peaks away before the
  # estimator sees them, so a target measured on discrete dates declares
  # cell_period = "date" and keeps one cell per measurement date.
  period <- if (is.null(tg$cell_period)) "year" else tg$cell_period
  rows$cell_period <- switch(period,
    year = paste0("y", rows$obs_year),
    date = as.character(rows$obs_date_start),
    PEcAn.logger::logger.severe("unknown cell_period '", period,
                                "' for target ", tg$variable, "; use 'year' or 'date'")
  )
  rows$cell <- paste(tg$variable, rows$sitename, rows$treatment_id, rows$cell_period,
                     paste0("d", rows$min_depth, "_", rows$max_depth), sep = "__")

  off <- unique(rows$reported_units[rows$reported_units != tg$units])
  if (length(off) > 0L) {
    PEcAn.logger::logger.severe(
      "target ", tg$variable, " declares '", tg$units, "' but records carry [",
      paste(off, collapse = ", "), "]; convert or correct the curated source"
    )
  }

  rows$reported_se <- suppressWarnings(as.numeric(rows$stat))
  rows
}

##' @title Split an observation target into fitted and validation parts
##' @name subset_obs
##' @author Akash BV
##'
##' @description Keeps slots in the run without letting them into the likelihood;
##'   a held-out variable is still predicted and still scored, which is what a
##'   validation target is.
##'
##' @param obs a build_obs target list(y, Sigma, meta).
##' @param keep logical vector over rows of `obs$meta`, TRUE to retain.
##' @return an obs list of the same shape carrying only the kept slots.
##' @export
subset_obs <- function(obs, keep) {
  if (length(keep) != nrow(obs$meta)) {
    PEcAn.logger::logger.severe(
      "keep must be one logical per observation slot: got ", length(keep),
      " for ", nrow(obs$meta), " slots"
    )
  }
  if (!any(keep)) {
    PEcAn.logger::logger.severe("subset_obs would leave no slots")
  }
  slots <- obs$meta$slot[keep]
  list(
    y = obs$y[slots],
    Sigma = obs$Sigma[slots, slots, drop = FALSE],
    meta = obs$meta[keep, , drop = FALSE]
  )
}
