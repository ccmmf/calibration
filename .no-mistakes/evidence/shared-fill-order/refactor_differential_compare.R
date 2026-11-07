b <- readRDS(".nm-scratch/base.rds"); h <- readRDS(".nm-scratch/head.rds")
cat("Base bb842cc vs HEAD 242e6ce: refactored russell_split_phases.R functions on the same inputs\n")
cat("(identical() compares values, types and field order)\n\n")
leaves <- function(x) if (is.list(x) && is.null(names(x)) && length(x) && !is.null(x[[1]]) && is.list(x[[1]]) && is.null(x[[1]]$event_type)) unlist(lapply(x, leaves), recursive = FALSE) else list(x)
errs <- function(x) sum(rapply(list(x), function(v) grepl("^ERROR:", v), classes = "character", how = "unlist"))
for (k in names(b)) {
  same <- identical(b[[k]], h[[k]])
  n <- length(unlist(lapply(b[[k]], function(x) if (is.list(x)) x else list(x)), recursive = FALSE))
  cat(sprintf("%-26s identical=%-5s  items=%4d  error results base/head=%d/%d\n", k, same, n, errs(b[[k]]), errs(h[[k]])))
}
cat("\n== median_for for a kind no system has (the one documented error-path change) ==\n")
cat("base:", deparse(b$median_for[[1]][[3]]), "\nhead:", h$median_for[[1]][[3]], "\n")
cat("\n== median_for: base vs head where they agree (first system, first two kinds) ==\n")
str(h$median_for[[1]][1:2])
cat("\n== a harvest after apply_lookup from a stripped event: field order (HEAD) ==\n")
cat(names(h$apply_lookup_placeholder[[3]][[1]]), sep = ", "); cat("\n")
cat("\n== compost events from fert_events: years, %C source, class (HEAD) ==\n")
for (e in h$fert_events$compost) cat(e$date, e$provenance_class, round(e$compost_total_c_pct, 4), round(e$compost_total_n_pct, 4),
                                     sub(".*(C from [^.]*)\\..*", "\\1", e$provenance_note), "\n")
