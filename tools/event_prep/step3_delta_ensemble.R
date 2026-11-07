#!/usr/bin/env Rscript
# Build a member ensemble of one Delta site's events.json by running its builder once per member
# of the monitoring product. Management uncertainty comes only from the product's irrigation
# (irr_ens_NNN) and fertilization (ens_NNN) members, and only where the builder uses them: US-Bi1
# its irrigation, US-Twt its 2017-2023 irrigation and fertilization. US-Bi2 uses neither, so its
# members are identical. Everything else is the same in every member as in runs/<site>/events.json,
# which is member 1.
#
# usage: step3_delta_ensemble.R <us_bi1|us_bi2|us_twt> <managements.csv> <out_dir> [n_members]

script_file <- gsub("~+~", " ", sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)),
                    fixed = TRUE)
here <- if (length(script_file)) dirname(script_file) else "tools/event_prep"

a <- commandArgs(trailingOnly = TRUE)
if (!length(a) %in% 3:4) stop("usage: step3_delta_ensemble.R <us_bi1|us_bi2|us_twt> <managements.csv> <out_dir> [n_members]")
site <- match.arg(a[1], c("us_bi1", "us_bi2", "us_twt"))
managements <- a[2]; out_dir <- a[3]
n_members <- if (length(a) == 4L) as.integer(a[4]) else 20L
builder <- file.path(here, paste0(site, "_build_events.R"))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

rows <- list(); first <- NULL
for (m in seq_len(n_members)) {
  out <- file.path(out_dir, sprintf("events_ens_%03d.json", m))
  log <- system2(file.path(R.home("bin"), "Rscript"), shQuote(c(builder, managements, out, m)),
                 stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(log, "status")) || !file.exists(out)) {
    writeLines(log); stop(sprintf("%s failed for member %d", basename(builder), m))
  }
  ev <- jsonlite::fromJSON(out, simplifyDataFrame = FALSE)$events
  # what varies between members: the events themselves, without the member named in their source
  body <- lapply(ev, function(e) { e$source <- sub(":(irr_)?ens_[0-9]+$", "", e$source); e })
  if (is.null(first)) first <- body
  types <- vapply(ev, `[[`, "", "event_type")
  rows[[m]] <- data.frame(member = m, events = length(ev),
                          planting = sum(types == "planting"), harvest = sum(types == "harvest"),
                          irrigation = sum(types == "irrigation"), fertilization = sum(types == "fertilization"),
                          tillage = sum(types == "tillage"), same_as_member_1 = identical(body, first))
}
s <- do.call(rbind, rows)
cat(sprintf("%s: %d members -> %s\n", site, n_members, out_dir)); print(s, row.names = FALSE)
cat(sprintf("members differing from member 1: %d\n", sum(!s$same_as_member_1)))
