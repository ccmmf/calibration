# Inputs the Delta tower builders share (us_bi1_build_events.R, us_bi2_build_events.R,
# us_twt_build_events.R): paths, the parcel's monitoring product rows, the cal-val-data site
# record, and writing the events.json. Sourced from the builder's own directory, after
# fill_order.R.

suppressPackageStartupMessages({ library(arrow); library(dplyr); library(jsonlite) })
options(arrow.unsafe_metadata = TRUE)

# Paths come from the environment, chained the same way as the CCMMF setup script
# (pecan modules/data.remote/inst/ccmmf/documentation/setup_env.sh) so that setting
# CCMMF_BASE alone is enough. No absolute path is baked in. See the README.
CCMMF_BASE         <- Sys.getenv("CCMMF_BASE", path.expand("~"))
CCMMF_ROOT         <- Sys.getenv("CCMMF_ROOT", file.path(CCMMF_BASE, "ccmmf"))
PRODUCTS_ROOT      <- Sys.getenv("PRODUCTS_ROOT", file.path(CCMMF_ROOT, "products"))
PRODUCTS_INVENTORY <- Sys.getenv("PRODUCTS_INVENTORY", file.path(PRODUCTS_ROOT, "inventory"))
EVENT_OUTPUT_DIR   <- Sys.getenv("EVENT_OUTPUT_DIR", file.path(PRODUCTS_INVENTORY, "event_files"))
CCMMF_WORK         <- Sys.getenv("CCMMF_WORK", file.path(CCMMF_ROOT, "work"))

#' Builder arguments: <managements.csv> <out.json> [member]
#'
#' member picks the monitoring product's irrigation member irr_ens_NNN and fertilization member
#' ens_NNN (1 by default); step3_delta_ensemble.R runs a builder once per member.
builder_args <- function(usage) {
  a <- commandArgs(trailingOnly = TRUE)
  if (!length(a) %in% 2:3) stop("usage: ", usage)
  member <- if (length(a) == 3L) as.integer(a[3]) else 1L
  if (is.na(member) || member < 1L) stop("member must be a positive integer")
  list(managements = a[1], out = a[2], member = member,
       irrigation_member = sprintf("irr_ens_%03d", member),
       fertilization_member = sprintf("ens_%03d", member))
}

#' The cal-val-data site record rows a builder rests on, by event_id
#'
#' Every id must be present, so a builder stops rather than silently losing a published value
#' when cal-val-data changes.
site_record <- function(path, ids) {
  m <- read.csv(path, colClasses = "character", na.strings = character())
  missing <- setdiff(ids, m$event_id)
  if (length(missing)) stop(sprintf("%s lacks %s", path, paste(missing, collapse = ", ")))
  r <- m[match(ids, m$event_id), , drop = FALSE]
  rownames(r) <- r$event_id
  r
}

#' The per-parcel monitoring product CSVs extract_parcel_csvs.R writes (planting and harvest
#' v1.0, irrigation v1.1)
parcel_csv <- function(label, what) {
  f <- file.path(CCMMF_WORK, paste0(label, "_events"), paste0("own_", what, ".csv"))
  if (!file.exists(f)) stop(f, " not found; run extract_parcel_csvs.R first (README)")
  d <- read.csv(f, stringsAsFactors = FALSE, colClasses = c(date = "character"))
  d[order(d$date), , drop = FALSE]
}

#' One irrigation member's rows within [start, end]
irrigation_member_rows <- function(irr, member, start, end) {
  if (!member %in% irr$ens_id) stop("irrigation member ", member, " is not in the product")
  irr[irr$ens_id == member & irr$date >= start & irr$date <= end, , drop = FALSE]
}

#' One fertilization member's rows for a parcel (fertilization v1.0)
fertilization_member_rows <- function(parcel, member) {
  f <- file.path(EVENT_OUTPUT_DIR, "fertilization.parquet")
  if (!dir.exists(f)) stop(f, " not found; run pull_inputs.sh first (README)")
  d <- open_dataset(f) |> filter(site_id == parcel, event_member_id == member) |>
    collect() |> as.data.frame()
  d$date <- as.character(as.Date(d$date))
  for (n in c("nh4_n_kg_m2", "no3_n_kg_m2", "org_c_kg_m2", "org_n_kg_m2")) d[[n]] <- as.numeric(d[[n]])
  d[order(d$date), , drop = FALSE]
}

#' A v5.0 product's rows for one parcel, read from the per-year files pull_inputs.sh fetches
#'
#' v5.0 keys rows on parcel_id and names the crop crop_code, unlike v1.0 (site_id, code or
#' CLASS_SUBCLASS), so extract_parcel_csvs.R does not read it.
v5_parcel_rows <- function(product, parcel) {
  dir <- file.path(PRODUCTS_INVENTORY, "management", product, "v5.0")
  f <- list.files(dir, pattern = "\\.parquet$", full.names = TRUE)
  if (!length(f)) stop("no parquet files under ", dir, "; run pull_inputs.sh first (README)")
  d <- do.call(rbind, lapply(f, function(x)
    open_dataset(x) |> filter(parcel_id == parcel) |> collect() |> as.data.frame()))
  d$date <- as.character(as.Date(d$date))
  d[order(d$date), , drop = FALSE]
}

#' David's circular median day of year; assumes one crop cycle a year
median_doy <- function(doy) {
  doy <- na.omit(doy); doy[doy == 366] <- 365
  stopifnot(all(doy >= 1 & doy <= 365)); doy <- sort(doy)
  if (length(doy) < 2) return(doy)
  if (diff(range(doy)) <= 182) return(median(doy))
  gaps <- c(diff(doy), doy[1] + 365 - tail(doy, 1)); cut <- which.max(gaps)
  doy <- c(doy[(cut + 1):length(doy)], doy[1:cut] + 365)
  ((median(doy) - 1) %% 365) + 1
}
doy_of      <- function(d) as.integer(format(as.Date(d), "%j"))
date_of_doy <- function(y, doy) format(as.Date(paste0(y, "-01-01")) + (round(doy) - 1), "%Y-%m-%d")

#' Sort events by date, then event type, check the harvests and write the events.json
write_events <- function(site, provenance, events, path) {
  events <- events[order(vapply(events, `[[`, "", "date"), vapply(events, `[[`, "", "event_type"))]
  check_harvest_fractions(events)
  # [[ ]] rather than $, which partially matches; every Delta event carries a note, published ones too
  untagged <- vapply(events, function(e) is.null(e[["provenance_class"]]) || is.null(e[["source"]]) ||
                       is.null(e[["provenance_note"]]) || !nzchar(e[["provenance_note"]]), TRUE)
  if (any(untagged)) stop(sum(untagged), " events lack a source, provenance_class or provenance_note")
  doc <- list(pecan_events_version = "0.1.1", site_id = site, provenance = provenance, events = events)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  write(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = 1, digits = NA), path)
  cat(sprintf("wrote %d events -> %s\n", length(events), path))
  print(table(vapply(events, `[[`, "", "event_type"), vapply(events, `[[`, "", "provenance_class")))
  invisible(doc)
}
