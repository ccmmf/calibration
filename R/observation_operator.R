# the observation operator: turn a model ensemble's output into the prediction
# matrix G the calibration compares to y. reads each ensemble member's run,
# samples the calibrated variable at each observation date carried in meta,
# converts it from the model's unit to the observation's unit, and lays the
# members out in run id order so G rows align with the parameter ensemble.

##' @title Harvest a model ensemble into the prediction matrix G
##' @name harvest_output_to_G
##' @author Akash BV
##'
##' @description For each ENS-<member>-<treatment> run under `out_root`, reads
##' `variable`, samples it at the observation date of each of that treatment's
##' slots (the midpoint of the slot's date window in meta), converts to the
##' observation unit, and assembles the J x P matrix aligned to the observation
##' slots. Assumes every expected run has finished; a missing run output fails
##' loud in read.output rather than being silently dropped.
##'
##' @param out_root the model output directory holding the ENS-* run dirs.
##' @param meta observation meta (slot, treatment_id, min_date, max_date).
##' @param variable the model output variable to read.
##' @param start_year,end_year the run year range.
##' @param from_unit the variable's model unit (udunits string).
##' @param to_unit the observation unit to convert to (udunits string).
##' @return matrix (members x slots) named by observation slot, member-ordered.
##' @export
harvest_output_to_G <- function(out_root, meta, variable, start_year, end_year,
                                from_unit, to_unit) {
  run_dirs <- list.files(out_root, pattern = "^ENS-")
  rows <- lapply(run_dirs, function(rid) {
    treat  <- sub("^ENS-[0-9]+-", "", rid)
    member <- as.integer(sub("^ENS-0*([0-9]+)-.*", "\\1", rid))
    o <- PEcAn.utils::read.output(
      runid = rid, outdir = file.path(out_root, rid),
      start.year = start_year, end.year = end_year,
      variables = variable, dataframe = TRUE, verbose = FALSE
    )
    md <- meta[meta$treatment_id == treat, ]
    obs_dates <- as.Date(md$min_date) +
      (as.Date(md$max_date) - as.Date(md$min_date)) / 2
    dates <- as.Date(o$posix)
    native <- vapply(obs_dates,
                     function(d) o[[variable]][which.min(abs(dates - d))],
                     numeric(1))
    tibble::tibble(member = member, slot = md$slot,
                   value = PEcAn.utils::ud_convert(native, from_unit, to_unit))
  })
  long <- do.call(rbind, rows)
  wide <- tidyr::pivot_wider(long, names_from = "slot", values_from = "value")
  wide <- wide[order(wide$member), ]
  G <- as.matrix(wide[, setdiff(colnames(wide), "member"), drop = FALSE])
  rownames(G) <- wide$member
  G
}
