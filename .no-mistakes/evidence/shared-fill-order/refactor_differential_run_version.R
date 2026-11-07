# usage: Rscript run_version.R <generator script> <out.rds>
a <- commandArgs(TRUE); script <- a[1]; out_rds <- a[2]
STACKED <- "runs/russell_ranch/events_treatments/generator_stacked"
commandArgs <- function(trailingOnly = FALSE)
  if (trailingOnly) c(STACKED, ".nm-scratch/no_century", ".nm-scratch/no_out") else
    c("/usr/lib/R/bin/exec/R", paste0("--file=", script))
exprs <- parse(script, keep.source = FALSE)
lhs <- vapply(exprs, function(e) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]])) as.character(e[[2]]) else "", "")
stop_at <- which(lhs == "ps_all")[1]                      # first read of the Century package
for (e in exprs[seq_len(stop_at - 1L)]) eval(e, globalenv())  # the real preamble: tables, constants, helpers
rm(commandArgs)

# synthetic stand-ins for values the Century package would supply
SYS <- unname(SYSTEMS)
c_pct <- c("1994" = 22.1, "1995" = 18.7, "1997" = 25.3, "2001" = 19.9, "2006" = 21.4, "2010" = 16.8)
n_pct <- c("1994" = 2.9, "1996" = 3.1, "1997" = 2.4, "2001" = 3.3, "2006" = 2.8, "2012" = 2.6)
set.seed(1)
med <- do.call(rbind, lapply(seq_along(SYS), function(i) do.call(rbind, lapply(c("harvest_doy", "cc_doy", "till_doy"), function(k) {
  n <- (i + nchar(k)) %% 8                                # 0 to 7 records: some systems below MIN_MEDIAN_N
  if (k == "till_doy") n <- 0L                             # a kind no system has
  if (!n) return(NULL)
  data.frame(system = SYS[i], kind = k, value = sample(80:300, n), stringsAsFactors = FALSE)
}))))
d <- function(x) as.Date(x)
fert_n <- data.frame(system_name = SYS[1], phase = "p1", date = d(c("1995-03-01", "2003-04-11", "2013-05-02")),
                     value = c(120.5, 87.25, 150), material_applied = c("urea", "UAN32", "ammonium sulfate"),
                     n_plots_treated = c(3L, 3L, 2L), stringsAsFactors = FALSE)
FERT_PLOT_ADDS <- data.frame(system_name = SYS[1], phase = "p1", date = d(c("2004-05-01", "2014-05-01")), n = c(40, 35),
                             material = "UAN32", logged = "1-2", plot = "3", id = c("fa1", "fa2"), stringsAsFactors = FALSE)
n_plots <- c(3, 3); names(n_plots) <- c(paste(SYS[1], "p1", sep = "|"), paste(SYS[2], "p2", sep = "|"))
yrs <- 1994:2014
compost <- data.frame(system_name = SYS[2], phase = "p2", date = d(sprintf("%d-10-15", yrs)), value = 4 + (yrs %% 5) / 2,
                      n_plots_treated = 3L, stringsAsFactors = FALSE)

want <- c("CORRECTIONS", "corrections", "HAY", "hay_for", "apply_lookup", "dates_of", "alfalfa_cuts", "AMOUNT_FIELDS",
          "planting_amount", "median_for", "fert_events", "sp", "c_mean", "n_mean", "COMPOST_MEAN", "compost_pct")
for (i in which(lhs %in% want)) eval(exprs[[i]], globalenv())

files <- list.files("runs/russell_ranch/events_treatments", pattern = "__.*\\.json$", full.names = TRUE)
phase <- lapply(files, function(f) jsonlite::fromJSON(f, simplifyDataFrame = FALSE)$events)
tids <- sub("^russell_ranch_tautges_2019_(.*)__.*$", "\\1", basename(files))
site_plantings <- Filter(function(e) e$event_type == "planting", unlist(phase, recursive = FALSE))
try_ <- function(expr) tryCatch(expr, error = function(e) paste("ERROR:", conditionMessage(e)))
FR <- c("frac_above_removed_0to1", "frac_below_removed_0to1", "frac_above_to_litter_0to1", "frac_below_to_litter_0to1")
strip <- function(e) { e[c(FR, "harvest_lookup_row", "harvest_fraction_note")] <- NULL; e }
placeholder <- function(e) { e <- strip(e); k <- match("crop_display", names(e)); append(e, list(frac_above_removed_0to1 = NA), k) }

res <- list()
for (j in seq_along(files)) {
  sys <- SYSTEMS[[tids[j]]]
  hv <- Filter(function(e) identical(e$event_type, "harvest"), phase[[j]])
  res$apply_lookup_as_is[[j]] <- lapply(hv, function(e) try_(apply_lookup(e, sys)))
  res$apply_lookup_stripped[[j]] <- lapply(hv, function(e) try_(apply_lookup(strip(e), sys)))
  res$apply_lookup_placeholder[[j]] <- lapply(hv, function(e) try_(apply_lookup(placeholder(e), sys)))
  res$alfalfa_cuts[[j]] <- try_(alfalfa_cuts(lapply(phase[[j]], function(e)
    if (identical(e$crop_display, "Alfalfa") && e$event_type == "harvest") strip(e) else e)))
  pool <- Filter(function(e) e$event_type == "planting", phase[[j]])
  res$planting_amount[[j]] <- lapply(names(CROP_DISPLAY), function(cr) list(phase = try_(planting_amount(cr, pool)),
                                                                            none = try_(planting_amount(cr, list()))))
}
res$median_for <- lapply(SYS, function(s) lapply(c("harvest_doy", "cc_doy", "till_doy"), function(k) try_(median_for(s, k))))
res$fert_events <- list(n = try_(fert_events(SYS[1], "p1", 2014)), n_2010 = try_(fert_events(SYS[1], "p1", 2010)),
                        compost = try_(fert_events(SYS[2], "p2", 2014)))
saveRDS(res, out_rds)
cat("ran", script, "\n")
