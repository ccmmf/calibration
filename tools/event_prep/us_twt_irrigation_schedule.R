#!/usr/bin/env Rscript
# Replace the flood-on / drain-off pair with a repeating irrigation schedule, since
# SIPNET has no drain event and a 0 mm irrigation is a no-op.

suppressMessages(library(jsonlite))

IRRIGATION_MM <- 70    # 2017-2023 mean 69.7 mm
INTERVAL_D <- 7        # 2017-2023 modal gap 7 d (median 8 d)
RUN_START <- as.Date("2010-01-01")
RUN_END <- as.Date("2016-12-31")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("usage: us_twt_irrigation_schedule.R <events.json>")
path <- args[1]

doc <- jsonlite::fromJSON(path, simplifyDataFrame = FALSE)
ev <- doc$events
is_irr <- vapply(ev, function(e) identical(e$event_type, "irrigation"), logical(1))
irr <- ev[is_irr]
irr <- irr[order(vapply(irr, function(e) e$date, character(1)))]
other <- ev[!is_irr]

# pair each flood with the next drain, in date order; a leading drain is a carry-in
spans <- list(); pending <- NULL
for (e in irr) {
  if (e$amount_mm > 0) {
    if (!is.null(pending)) spans[[length(spans) + 1L]] <- list(flood = pending, drain = NULL)
    pending <- e
  } else {
    spans[[length(spans) + 1L]] <- list(flood = pending, drain = e)
    pending <- NULL
  }
}
if (!is.null(pending)) spans[[length(spans) + 1L]] <- list(flood = pending, drain = NULL)

new <- list()
for (sp in spans) {
  start <- if (!is.null(sp$flood)) as.Date(sp$flood$date) else RUN_START
  end <- if (!is.null(sp$drain)) as.Date(sp$drain$date) else RUN_END
  if (end <= start) {
    message(sprintf("  SKIP non-positive span %s -> %s", start, end)); next
  }
  tmpl <- if (!is.null(sp$flood)) sp$flood else sp$drain
  n <- 0L; d <- start
  while (d < end) {
    e <- tmpl
    e$date <- format(d, "%Y-%m-%d")
    e$amount_mm <- IRRIGATION_MM
    e$method <- "flood"
    e$provenance_note <- if (n == 0L && !is.null(sp$flood)) {
      trimws(paste0(
        if (is.null(tmpl$provenance_note)) "" else tmpl$provenance_note,
        sprintf(paste("  Flood held by repeated application of %d mm every %d d,",
                      "the rate and interval of the 2017-2023 monitoring record,",
                      "because SIPNET has no persistent flood state."),
                IRRIGATION_MM, INTERVAL_D)))
    } else if (n == 0L) {
      sprintf(paste("Carry-in of the winter flood established before the run window;",
                    "held at %d mm every %d d until the WTD-derived drain."),
              IRRIGATION_MM, INTERVAL_D)
    } else if (!is.null(sp$drain)) {
      sprintf("Maintains the flooded period begun %s; ends %s, the WTD-derived drain date.",
              start, end)
    } else {
      sprintf("Maintains the flooded period begun %s to the end of the run window.", start)
    }
    new[[length(new) + 1L]] <- e
    n <- n + 1L
    d <- d + INTERVAL_D
  }
  cat(sprintf("  %s -> %s  (%3d d)  %2d events\n", start, end, as.integer(end - start), n))
}

all_ev <- c(other, new)
ord <- order(vapply(all_ev, function(e) e$date, character(1)),
             vapply(all_ev, function(e) e$event_type, character(1)))
doc$events <- all_ev[ord]
write(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = 1, digits = NA), path)

cat(sprintf("\n  irrigation: %d -> %d   total: %d -> %d\n",
            length(irr), length(new), length(ev), length(doc$events)))
