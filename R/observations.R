# build a calibration target (y, Sigma, meta) from curated cal/val observations.
#
# the curated data holds replicate-level measurements. the Gaussian likelihood
# covariance Sigma is the variance of each (site, treatment, year) cell mean,
# computed from the replicate spread rather than read from a column, with a
# relative floor so a cell whose replicates happen to agree cannot drive its
# variance to zero and make Sigma singular. y is the per-cell replicate mean;
# meta carries the date and depth window per slot so the observation operator can
# align model output to y.

##' @title Read the curated cal/val observations table
##' @name read_cal_val_observations
##'
##' @description Reads the single observations tsv exported from the cal/val
##' workbook, drops empty trailing sheet rows, and strips thousands-separator
##' commas from the numeric columns so coercion does not silently produce NA.
##'
##' @param cal_val_dir directory holding the observations tsv export.
##' @return tibble of observation rows, value and study_year coerced to numeric.
##' @keywords internal
read_cal_val_observations <- function(cal_val_dir) {
  f <- list.files(cal_val_dir, pattern = "observations\\.tsv$", full.names = TRUE)
  if (length(f) != 1L) {
    PEcAn.logger::logger.severe(
      "expected exactly one observations tsv in ", cal_val_dir, ", found ", length(f)
    )
  }
  strip_commas <- function(x) as.numeric(gsub(",", "", as.character(x)))
  readr::read_tsv(f, show_col_types = FALSE) |>
    dplyr::filter(!is.na(variable), variable != "") |>
    dplyr::mutate(value = strip_commas(value), study_year = strip_commas(study_year))
}

##' @title Build the calibration target from cal/val observations
##' @name build_obs
##' @author Akash BV
##'
##' @description Assembles the observation vector `y`, its diagonal likelihood
##' covariance `Sigma`, and the per-slot `meta` for one variable at one or more
##' sites. Each (site, treatment, year) cell becomes one slot: `y` is the
##' replicate mean, `Sigma` the variance of that mean floored relative to its
##' magnitude. Nothing here is variable- or site specific; the caller names them.
##'
##' @param cal_val_dir directory of the cal/val tsv export.
##' @param target_var the cal/val variable to calibrate to.
##' @param sites character vector of sitenames to include.
##' @param rel_var_floor relative floor on each cell variance: the variance is at
##'   least `(rel_var_floor * value)^2`, so an agreeing cell cannot make Sigma
##'   singular. Set 0 to disable.
##' @return list(y, Sigma, meta): `y` named numeric (length P), `Sigma` a P x P
##'   diagonal variance matrix named to match `y`, `meta` one row per slot.
##' @export
build_obs <- function(cal_val_dir, target_var, sites, rel_var_floor = 0.05) {
  raw <- read_cal_val_observations(cal_val_dir) |>
    dplyr::filter(variable == target_var, sitename %in% sites,
                  observation_level == "replicate")
  if (nrow(raw) == 0L) {
    PEcAn.logger::logger.severe(
      "no replicate-level ", target_var, " rows for site(s) ",
      paste(sites, collapse = ", ")
    )
  }

  cells <- raw |>
    dplyr::summarize(
      cell_mean = mean(value, na.rm = TRUE),
      cell_sd   = stats::sd(value, na.rm = TRUE),
      n_rep     = sum(!is.na(value)),
      min_date  = dplyr::first(min_date),
      max_date  = dplyr::first(max_date),
      min_depth = dplyr::first(min_depth),
      max_depth = dplyr::first(max_depth),
      .by = c(sitename, treatment_id, study_year)
    ) |>
    dplyr::arrange(sitename, treatment_id, study_year) |>
    dplyr::mutate(
      var_mean = dplyr::if_else(n_rep > 1L, cell_sd^2 / n_rep, NA_real_),
      var_obs  = pmax(var_mean, (rel_var_floor * abs(cell_mean))^2, na.rm = TRUE)
    )

  if (any(!is.finite(cells$var_obs))) {
    bad <- paste0(cells$treatment_id, "_y", cells$study_year)[!is.finite(cells$var_obs)]
    PEcAn.logger::logger.severe(
      "non-finite observation variance for: ", paste(utils::head(bad), collapse = ", ")
    )
  }

  slot <- paste(cells$sitename, cells$treatment_id,
                paste0("y", cells$study_year), sep = "__")
  y <- stats::setNames(cells$cell_mean, slot)
  Sigma <- diag(cells$var_obs, nrow = length(y))
  dimnames(Sigma) <- list(slot, slot)

  meta <- tibble::tibble(
    slot = slot,
    sitename = cells$sitename,
    treatment_id = cells$treatment_id,
    study_year = cells$study_year,
    min_date = cells$min_date,
    max_date = cells$max_date,
    min_depth = cells$min_depth,
    max_depth = cells$max_depth,
    n_rep = cells$n_rep,
    value = cells$cell_mean,
    var_obs = cells$var_obs
  )

  PEcAn.logger::logger.info(
    length(y), " observation slots for ", target_var, " across ",
    dplyr::n_distinct(cells$treatment_id), " treatments, ",
    dplyr::n_distinct(cells$study_year), " years"
  )
  list(y = y, Sigma = Sigma, meta = meta)
}
