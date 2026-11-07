# Shared helpers for filling missing management events in the events.json generators.
#
# A generator fills an event the records lack, or its date or amount, in David's order
# (calibration#10; README.md here, "Filling missing events"): 1. the paper or its source data,
# 2. the monitoring product, 3. guidance documents. These helpers hold what every generator
# repeats: taking the first source in that order that has the value and saying which one it was,
# tagging each filled event with where it came from, and writing harvest fractions that SIPNET
# cannot misread. Base R only; a generator sources this file from its own directory.

#' Provenance classes an event can carry
#'
#' published  a source records the value: the paper, its data, or the monitoring product for
#'            this field and season
#' derived    computed from recorded values (compost C from the recorded tonnage and that year's
#'            measured %C)
#' assumed    rests on a stated reading of a source (the paper's "mm" read as inches, a date the
#'            package's own notes call assigned)
#' imputed    no record gives it; filled by a rule from other records, the monitoring product or
#'            guidance
PROVENANCE_CLASSES <- c("published", "derived", "assumed", "imputed")

#' The four harvest fractions, in the order SIPNET's harv line takes them
HARVEST_FRACTIONS <- c("frac_above_removed_0to1", "frac_below_removed_0to1",
                       "frac_above_to_litter_0to1", "frac_below_to_litter_0to1")

#' Take the first candidate, in order of preference, that has enough records
#'
#' Name the candidates by where they come from. Across David's order that is the paper or its
#' data, then the monitoring product, then guidance; within one source, the narrowest pool of
#' records first (this phase, then the site).
#'
#' @param candidates named list, preferred first. Each is a vector of values, a list of events
#'   or a data frame of records; NULL or NA means not available.
#' @param min_n records a candidate needs to be taken (non-missing values of a vector, elements
#'   of a list, rows of a data frame), recycled over the candidates; c(5, 1) takes the first
#'   candidate when it has at least 5 and otherwise falls back to the second if it has any.
#' @return list(value, from = the candidate's name, n = its record count), or NULL when no
#'   candidate has enough.
first_available <- function(candidates, min_n = 1L) {
  if (!is.list(candidates) || !length(candidates) || is.null(names(candidates)) ||
      !all(nzchar(names(candidates))))
    stop("candidates must be a named list, preferred first")
  min_n <- rep_len(min_n, length(candidates))
  for (i in seq_along(candidates)) {
    x <- candidates[[i]]
    n <- if (is.list(x)) NROW(x) else sum(!is.na(x))
    if (n > 0L && n >= min_n[i]) return(list(value = x, from = names(candidates)[i], n = n))
  }
  NULL
}

#' Tag an event with where it came from
#'
#' Sets `source` (when given), `provenance_class` and `provenance_note`. A field the event already
#' has keeps its place and new ones are added at the end in that order, so an event can be built
#' with its source among its other fields.
#'
#' @param e event, a named list
#' @param class one of PROVENANCE_CLASSES
#' @param note what the value rests on: the record, rule, median or copied season used. Needed for
#'   every class but published.
#' @param source a DOI and file, or a monitoring product path; needed unless `e` has one
#' @return `e`, tagged
set_provenance <- function(e, class, note = NULL, source = NULL) {
  if (!is.character(class) || length(class) != 1L || !class %in% PROVENANCE_CLASSES)
    stop(sprintf("provenance_class must be one of %s, not %s",
                 paste(PROVENANCE_CLASSES, collapse = ", "), paste(deparse(class), collapse = "")))
  if (!is.null(source)) e$source <- source
  if (!is.character(e$source) || length(e$source) != 1L || !nzchar(e$source))
    stop(sprintf("a %s event needs a source", class))
  if (!is.null(note) && (!is.character(note) || length(note) != 1L || is.na(note)))
    stop("provenance_note must be a single string")
  if (class != "published" && (is.null(note) || !nzchar(note)))
    stop(sprintf("a %s event needs a provenance_note saying what it rests on", class))
  e$provenance_class <- class
  if (!is.null(note)) e$provenance_note <- note
  e
}

#' Harvest fractions with all four written out
#'
#' PEcAn.SIPNET::write.events.SIPNET fills a missing transfer to litter as 1 - removed, so a
#' perennial cutting given only frac_above_removed_0to1 = 0.85 sends the rest of the shoots and
#' all the roots to litter, which kills the stand. So none of the four has a default: a cutting
#' that leaves the stubble and roots alive is harvest_fractions(0.85, 0, 0, 0), and a crop that
#' ends in the field is harvest_fractions(0, 0, 1, 1). What is neither removed nor transferred
#' stays alive.
#'
#' @param above_removed,below_removed share of above and belowground biomass removed, 0 to 1
#' @param above_to_litter,below_to_litter share transferred to litter, 0 to 1
#' @return named list of the four HARVEST_FRACTIONS fields
harvest_fractions <- function(above_removed, below_removed, above_to_litter, below_to_litter) {
  fr <- setNames(list(above_removed, below_removed, above_to_litter, below_to_litter), HARVEST_FRACTIONS)
  problem <- fraction_problem(fr)
  if (!is.null(problem)) stop(problem)
  fr
}

#' Stop unless every harvest event carries all four fractions, each valid
#'
#' Run on a generator's events before writing them, so no harvest reaches write.events.SIPNET
#' with a fraction it would fill in.
#'
#' @param events list of events; events other than harvests are skipped
#' @return `events`, invisibly
check_harvest_fractions <- function(events) {
  for (e in events) {
    if (!identical(e$event_type, "harvest")) next
    what <- sprintf("%s harvest on %s", if (is.null(e$crop_display)) "a" else e$crop_display,
                    if (is.null(e$date)) "no date" else e$date)
    missing <- setdiff(HARVEST_FRACTIONS, names(e))
    if (length(missing))
      stop(sprintf("%s lacks %s; write.events.SIPNET would fill it from 1 - removed", what,
                   paste(missing, collapse = ", ")))
    problem <- fraction_problem(e[HARVEST_FRACTIONS])
    if (!is.null(problem)) stop(sprintf("%s: %s", what, problem))
  }
  invisible(events)
}

# What is wrong with a set of the four fractions, or NULL
fraction_problem <- function(fr) {
  ok <- vapply(fr, function(v) is.numeric(v) && length(v) == 1L && !is.na(v) && v >= 0 && v <= 1, TRUE)
  if (!all(ok)) return(sprintf("%s must be a number from 0 to 1", paste(names(fr)[!ok], collapse = ", ")))
  if (fr[[1]] + fr[[3]] > 1 + 1e-9) return("aboveground removed and to litter add up to more than 1")
  if (fr[[2]] + fr[[4]] > 1 + 1e-9) return("belowground removed and to litter add up to more than 1")
  NULL
}
