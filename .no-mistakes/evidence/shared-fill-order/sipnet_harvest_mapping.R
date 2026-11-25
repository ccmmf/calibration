# Checks the HEAD note that HARVEST_FRACTIONS, harvest_fractions() and check_harvest_fractions()
# follow SIPNET's harv line and write.events.SIPNET: events built with the helpers go through the
# real PEcAn.SIPNET writer, and the harv lines are printed next to the fields that produced them.
args <- commandArgs(trailingOnly = TRUE)
source(args[1]); dir <- args[2]
invisible(PEcAn.logger::logger.setLevel("OFF"))
ev <- list(
  c(list(event_type = "harvest", date = "2013-05-20", crop_display = "Alfalfa cutting"), harvest_fractions(0.85, 0, 0, 0)),
  c(list(event_type = "harvest", date = "2013-09-01", crop_display = "Tomato"), harvest_fractions(0.462, 0, 0.538, 1)),
  c(list(event_type = "harvest", date = "2014-04-01", crop_display = "Cover crop"), harvest_fractions(0, 0, 1, 1)),
  list(event_type = "harvest", date = "2014-06-20", crop_display = "Alfalfa, removed only", frac_above_removed_0to1 = 0.85))
cat("HARVEST_FRACTIONS order:", paste(HARVEST_FRACTIONS, collapse = ", "), "\n\n")
cat("check_harvest_fractions on the first three: ")
check_harvest_fractions(ev[1:3]); cat("ok\n")
cat("check_harvest_fractions on all four: ",
    tryCatch({check_harvest_fractions(ev); "ok"}, error = conditionMessage), "\n\n")
json <- file.path(dir, "events.json")
jsonlite::write_json(list(pecan_events_version = "0.1.1", site_id = "demo", events = ev), json,
                     auto_unbox = TRUE, digits = NA)
PEcAn.SIPNET::write.events.SIPNET(json, dir)
harv <- grep(" harv ", readLines(file.path(dir, "events-demo.in")), value = TRUE)
cat(sprintf("%-22s fields given: %-26s -> events.in: %s\n",
            vapply(ev, `[[`, "", "crop_display"),
            vapply(ev, function(e) paste(unlist(e[intersect(HARVEST_FRACTIONS, names(e))]), collapse = " "), ""),
            harv), sep = "")
