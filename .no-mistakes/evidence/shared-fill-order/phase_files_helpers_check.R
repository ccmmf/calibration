source("tools/event_prep/fill_order.R")
files <- list.files("runs/russell_ranch/events_treatments", pattern = "__.*\\.json$", full.names = TRUE)
cat("phase files:", length(files), "\n\n")
tot_h <- 0L; tot_p <- 0L
for (f in files) {
  doc <- jsonlite::fromJSON(f, simplifyDataFrame = FALSE)
  check_harvest_fractions(doc$events)                         # what the generator runs on every phase file
  nh <- sum(vapply(doc$events, function(e) identical(e$event_type, "harvest"), TRUE))
  # every tagged event passes set_provenance with its own class, note and source, unchanged
  np <- 0L
  for (e in doc$events) {
    if (is.null(e$provenance_class)) next
    again <- set_provenance(e, e$provenance_class, e$provenance_note)
    stopifnot(identical(again, e))
    np <- np + 1L
  }
  classes <- table(vapply(Filter(function(e) !is.null(e$provenance_class), doc$events), `[[`, "", "provenance_class"))
  cat(sprintf("OK %-80s harvests=%3d tagged=%3d  %s\n", basename(f), nh, np,
              paste(names(classes), classes, sep = "=", collapse = " ")))
  tot_h <- tot_h + nh; tot_p <- tot_p + np
}
cat(sprintf("\nAll %d phase files pass check_harvest_fractions (%d harvests) and set_provenance (%d tagged events).\n\n",
            length(files), tot_h, tot_p))

cat("== adversarial: the same files with one harvest broken ==\n")
alf <- jsonlite::fromJSON(grep("__tomato-alfalfa", files, value = TRUE), simplifyDataFrame = FALSE)$events
i <- which(vapply(alf, function(e) identical(e$crop_display, "Alfalfa"), TRUE))[3]
bare <- alf; bare[[i]][c("frac_below_removed_0to1", "frac_above_to_litter_0to1", "frac_below_to_litter_0to1")] <- NULL
cat("alfalfa cutting with only frac_above_removed_0to1:\n  ")
cat(tryCatch({check_harvest_fractions(bare); "NO ERROR (unexpected)"}, error = conditionMessage), "\n")
over <- alf; over[[i]]$frac_above_to_litter_0to1 <- 0.5
cat("alfalfa cutting with 0.85 removed + 0.5 to litter:\n  ")
cat(tryCatch({check_harvest_fractions(over); "NO ERROR (unexpected)"}, error = conditionMessage), "\n")
na <- alf; na[[i]]$frac_below_to_litter_0to1 <- NA
cat("alfalfa cutting with a NA fraction:\n  ")
cat(tryCatch({check_harvest_fractions(na); "NO ERROR (unexpected)"}, error = conditionMessage), "\n")
j <- which(vapply(alf, function(e) identical(e$provenance_class, "imputed"), TRUE))[1]
cat("re-tagging an imputed event without a note:\n  ")
cat(tryCatch({set_provenance(alf[[j]], "imputed"); "NO ERROR (unexpected)"}, error = conditionMessage), "\n")
cat("re-tagging it with source = NA:\n  ")
cat(tryCatch({set_provenance(alf[[j]], "imputed", alf[[j]]$provenance_note, source = NA_character_); "NO ERROR (unexpected)"},
             error = conditionMessage), "\n")
cat("tagging with a class outside PROVENANCE_CLASSES ('estimated'):\n  ")
cat(tryCatch({set_provenance(alf[[j]], "estimated", "x"); "NO ERROR (unexpected)"}, error = conditionMessage), "\n")
