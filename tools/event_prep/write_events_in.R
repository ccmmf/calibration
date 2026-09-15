#!/usr/bin/env Rscript
# events.json -> events.in, rewriting the irrigation method code from the JSON, which
# PEcAn.SIPNET::write.events.SIPNET would otherwise collapse to canopy.

suppressMessages({
  library(jsonlite)
  library(PEcAn.SIPNET)
})

# SIPNET documents canopy=0, soil=1, flood=2, but the build in use rejects 2
# ("Unknown irrigation method type: 2") and aborts, so flood is emitted as canopy.
METHOD_CODE <- c(canopy = 0L, soil = 1L, flood = 0L)

main <- function(events_json, outdir) {
  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
  PEcAn.SIPNET::write.events.SIPNET(events_json, outdir)

  doc <- jsonlite::fromJSON(events_json, simplifyDataFrame = FALSE)
  infile <- file.path(outdir, paste0("events-", doc$site_id, ".in"))
  lines <- readLines(infile)

  # (year, doy) -> intended method code, from the JSON
  want <- new.env(parent = emptyenv())
  for (e in doc$events) {
    if (!identical(e$event_type, "irrigation")) next
    d <- as.Date(e$date)
    key <- paste(format(d, "%Y"), as.integer(format(d, "%j")))
    m <- if (is.null(e$method)) "canopy" else e$method
    assign(key, unname(METHOD_CODE[[m]]), envir = want)
  }

  pat <- "^(\\d+)\\s+(\\d+)\\s+irrig\\s+(\\S+)\\s+(\\S+)\\s*$"
  checked <- 0L; fixed <- 0L
  out <- vapply(lines, function(ln) {
    if (!grepl(pat, ln)) return(ln)
    g <- regmatches(ln, regexec(pat, ln))[[1]]
    yr <- g[2]; dy <- as.integer(g[3]); amt <- g[4]; code <- as.integer(g[5])
    checked <<- checked + 1L
    key <- paste(yr, dy)
    if (!exists(key, envir = want, inherits = FALSE)) return(ln)
    target <- get(key, envir = want, inherits = FALSE)
    if (identical(target, code)) return(ln)
    fixed <<- fixed + 1L
    sprintf("%s  %d  irrig  %s %d", yr, dy, amt, target)
  }, character(1), USE.NAMES = FALSE)

  writeLines(out, infile)

  cat("  wrote", infile, "\n")
  cat("  lines", length(out), "| json events", length(doc$events),
      if (length(out) == length(doc$events)) "OK" else "<-- MISMATCH", "\n")
  cat("  irrigation lines checked", checked, ", method code corrected on", fixed, "\n")

  bad <- 0L
  for (ln in out) {
    if (!grepl(pat, ln)) next
    g <- regmatches(ln, regexec(pat, ln))[[1]]
    key <- paste(g[2], as.integer(g[3]))
    if (exists(key, envir = want, inherits = FALSE) &&
        !identical(get(key, envir = want, inherits = FALSE), as.integer(g[5]))) bad <- bad + 1L
  }
  cat("  verification:", if (bad == 0L) "all irrigation methods match the JSON"
      else paste(bad, "STILL WRONG"), "\n")
  invisible(if (bad == 0L) 0L else 1L)
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: write_events_in.R <events.json> <outdir>")
quit(status = main(args[1], args[2]))
