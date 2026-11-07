#!/usr/bin/env Rscript
# Build the SIPNET events for the eight systems of the Salinas Organic Cropping Systems trial
# (SOCS, white_salinas_2020) from its management calendar in ccmmf/cal-val-data, one file per
# system, filling what the papers do not give in the order of tools/event_prep/README.md
# ("Filling missing events"): the papers first, then the monitoring product near SOCS, then
# guidance. Only operations on the calendar rows become events, plus the end of each crop the
# calendar implies (a cover crop's termination); nothing is inserted (ccmmf/organization#297).
#
# usage: salinas_build_events.R <cal-val-data checkout> <out_dir>
#   The checkout's data/ holds managements.csv, treatments.csv and crops.csv. The files in
#     runs/salinas_socs were built from the calval-metadata branch (cal-val-data PR #24).
#   out_dir must hold monitoring_near_salinas.csv, written by salinas_monitoring.R.
# Writes events_<system>.json for socs_sys1 to socs_sys8 and fill_summary.csv, the count of
# every filled or assumed value, into out_dir. The fill helpers it shares with the other
# generators are in fill_order.R, next to this script.

suppressMessages(library(jsonlite))
script_file <- gsub("~+~", " ", sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)),
                    fixed = TRUE)
source(file.path(if (length(script_file)) dirname(script_file) else "tools/event_prep", "fill_order.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: salinas_build_events.R <cal-val-data checkout> <out_dir>")
cal_dir <- file.path(args[1], "data")
if (!file.exists(file.path(cal_dir, "managements.csv")))
  stop(args[1], " is not a cal-val-data checkout: no data/managements.csv")
out_dir <- args[2]
mon_csv <- file.path(out_dir, "monitoring_near_salinas.csv")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

rd <- function(f) read.csv(file.path(cal_dir, f), stringsAsFactors = FALSE, colClasses = "character",
                           na.strings = character())
cal <- rd("managements.csv")
treatments <- rd("treatments.csv")
crops <- rd("crops.csv")
SYSTEMS <- sprintf("socs_sys%d", 1:8)
cal <- cal[cal$sites.name == "salinas_socs" & cal$treatments.name %in% SYSTEMS, ]
stopifnot(setequal(unique(cal$treatments.name), SYSTEMS), !anyDuplicated(cal$event_id))
FIRST_DATE <- as.Date("2003-01-01")
LAST_DATE <- as.Date("2011-12-31")

# The calendar's sources
BB2012 <- "10.2134/agronj2011.0330"       # Brennan and Boyd 2012
WHITE_2020B <- "10.1371/journal.pone.0228677"
MON_SOURCE <- "calibration:runs/salinas_socs/monitoring_near_salinas.csv"
PRIORS_SOURCE <- "ccmmf/scenarios:data/management_priors.yaml"

# Crops: the calendar's crop key, the crops.csv common name, and the monitoring slot
# (salinas_monitoring.R) that stands in for it
CROPS <- data.frame(
  key = c("romaine_lettuce", "baby_leaf_spinach", "broccoli", "legume-rye", "mustard", "rye"),
  display = c("romaine lettuce", "baby leaf spinach", "broccoli", "legume-rye mix", "mustard", "cereal rye"),
  slot = c("lettuce", "spinach", "broccoli", "cover_crop", "cover_crop", "cover_crop"),
  stringsAsFactors = FALSE)
stopifnot(all(CROPS$display %in% crops$common.name))
VEGETABLES <- CROPS$key[CROPS$slot != "cover_crop"]
COVER_CROPS <- CROPS$key[CROPS$slot == "cover_crop"]
display_of <- function(k) CROPS$display[match(k, CROPS$key)]
slot_of <- function(k) CROPS$slot[match(k, CROPS$key)]

# Monitoring medians near SOCS (salinas_monitoring.R)
MON <- read.csv(mon_csv, stringsAsFactors = FALSE)
mon <- function(slot, quantity) {
  r <- MON[MON$slot == slot & MON$quantity == quantity, ]
  stopifnot(nrow(r) == 1L, !is.na(r$value))
  r
}
mon_where <- function(r) sprintf("%s planted in %s within %d km of SOCS, %s", r$crop_code,
                                 paste(month.name[as.integer(strsplit(r$planting_months, ";")[[1]])], collapse = " or "),
                                 r$radius_km, r$years)

# Amounts the papers give (ccmmf/cal-val-data data_raw/white_salinas_2020/data_entry_report.md)
KG_HA_TO_KG_M2 <- 1e-4
MG_HA_TO_KG_M2 <- 0.1
# White et al. 2020b measured the C of every input it counts: 317 g C kg-1 for the compost, 280
# for the Foster 4-4-2 pellets and 370 for the True Organic 8-1-1 pellets. The compost's C:N was
# measured in 4 of the 8 years, 18 to 28, mean 22. Its N concentration is not published; the
# calendar rows carry N_content_g_kg = 15, curated without a source (data entry report, Open
# follow-ups), which with the 317 gives a C:N of 21, within that range.
COMPOST_C_G_KG <- 317
# The pellets' C:N from those C concentrations and the products' N grades (4 % and 8 % N). Which
# product went on in which year is not reported, so the pellets take the mean of the two.
PELLET_CN <- c(foster_4_4_2 = 280 / 40, true_organic_8_1_1 = 370 / 80)
# Drip schedule (guidance, step 3): the monitoring product's events are its 150 mm bucket refills,
# not a drip schedule, so the vegetables' season water goes on every IRRIGATION_EVERY_DAYS days
# from planting to the day before harvest, the most probable interval of the scenarios priors'
# irrigation_drip practice (every 2, 3 or 4 days; 3 with p = 0.5).
IRRIGATION_EVERY_DAYS <- 3L
# Harvest fractions. A marketed lettuce or broccoli removes the harvest index of the shoot
# (White et al. 2020b: hearts 0.26, broccoli 0.24, the rest left as residue); a crop
# incorporated unharvested and a terminated cover crop end in the field.
ALL_TO_LITTER <- harvest_fractions(above_removed = 0, below_removed = 0, above_to_litter = 1, below_to_litter = 1)
marketed <- function(hi) harvest_fractions(above_removed = hi, below_removed = 0, above_to_litter = 1 - hi, below_to_litter = 1)

kv <- function(x) {
  if (is.na(x) || x == "NA" || !nzchar(x)) return(list())
  p <- strsplit(strsplit(x, ";\\s*")[[1]], "=")
  setNames(lapply(p, `[`, 2), vapply(p, `[`, "", 1))
}
num <- function(x) { x[x == "NA"] <- NA; as.numeric(x) }
yr <- function(d) as.integer(format(d, "%Y"))

# Provenance parts. Each value of an event (its date, each amount) carries a class and a note;
# the event takes the weakest class (published < derived < assumed < imputed) and every note.
part <- function(class, note, source = NULL, item = "date", rule = class)
  list(class = class, note = note, source = source, item = item, rule = rule)
# Every value that is not published is also counted in FILLS, by what the event is (the crop,
# or the material, implement or irrigated crop), for fill_summary.csv; a part without a source of
# its own rests on the calendar row.
FILLS <- list()
tag <- function(e, parts, sys, row_source, what = display_of(e$crop_code)) {
  cls <- PROVENANCE_CLASSES[max(match(vapply(parts, `[[`, "", "class"), PROVENANCE_CLASSES))]
  srcs <- unique(c(row_source, unlist(lapply(parts, `[[`, "source"))))
  for (p in parts) if (p$class != "published")
    FILLS[[length(FILLS) + 1L]] <<- data.frame(system = sys, event_type = e$event_type, what = what,
      item = p$item, rule = p$rule, class = p$class,
      source = if (is.null(p$source)) "calendar row" else p$source, stringsAsFactors = FALSE)
  set_provenance(e, cls, paste(vapply(parts, `[[`, "", "note"), collapse = " "), paste(srcs, collapse = " + "))
}

# One date for a calendar row (David's order): the row's own date when it has one; for a window,
# the monitoring product's median day for the crop and operation near SOCS when that falls inside
# it, otherwise the window's midpoint. lo and hi narrow the window by the order the calendar
# states (after a harvest, before a planting), using the dates already chosen for those events.
# A candidate is a planting or harvest's median day of year, or, for tillage, a median number of
# days after the harvest or before the planting it belongs to, as in russell_split_phases.R: the
# product's tillage days of year wrap the new year (a quarter of the first passes after a July or
# August cole crop fall in January or February), so their median is not a day.
midpoint <- function(lo, hi) as.Date(floor((as.numeric(lo) + as.numeric(hi)) / 2), origin = "1970-01-01")
# A monitoring day of year as a calendar day, read in a non-leap year so it lands on the same
# month and day every year
day_in_year <- function(doy, y) as.Date(sprintf("%d-%s", y, format(as.Date("2001-01-01") + round(doy) - 1, "%m-%d")))
pick_date <- function(r, cand = NULL, lo = NULL, hi = NULL, why = NULL) {
  a <- as.Date(r$min_date); b <- as.Date(r$max_date)
  if (a == b) {
    if ((!is.null(lo) && a < lo) || (!is.null(hi) && a > hi))
      stop(sprintf("%s: its date %s is outside %s to %s", r$event_id, a, format(lo), format(hi)))
    return(list(date = a, part = part("published", sprintf("Date from the calendar (%s).", r$event_id))))
  }
  wlo <- max(c(a, lo)); whi <- min(c(b, hi))
  if (wlo > whi) stop(sprintf("%s: nothing is left of its window %s to %s after %s", r$event_id, a, b, why))
  win <- sprintf("The calendar gives a window, %s to %s (%s)%s.", a, b, r$event_id,
                 if (wlo != a || whi != b) sprintf(", narrowed to %s to %s %s", wlo, whi, why) else "")
  if (!is.null(cand)) {
    stopifnot(yr(a) == yr(b))
    d <- if (is.null(cand$date)) day_in_year(cand$value, yr(a)) else cand$date
    desc <- if (is.null(cand$date)) sprintf("day %d", as.integer(round(cand$value))) else cand$desc
    if (d >= wlo && d <= whi)
      return(list(date = d, part = part("imputed", sprintf(
        "%s The monitoring product's median for %s, %s, falls in it (%s, n = %d).",
        win, cand$label, desc, mon_where(cand), cand$n), MON_SOURCE, "date", "monitoring median timing")))
    win <- sprintf("%s The monitoring product's median for %s, %s, falls outside it.", win, cand$label, desc)
  }
  list(date = midpoint(wlo, whi), part = part("assumed", sprintf("%s Dated at its midpoint.", win), NULL, "date",
                                              "window midpoint"))
}
cand <- function(slot, quantity, label) { r <- mon(slot, quantity); r$label <- label; r }

build_system <- function(sys) {
  r <- cal[cal$treatments.name == sys, ]
  r <- r[order(r$min_date, r$event_id), ]
  K <- lapply(r$attributes_keyvalue, kv)
  events <- list()
  add <- function(e) events[[length(events) + 1L]] <<- e
  crop_of <- function(i) if (!is.null(K[[i]]$crop)) K[[i]]$crop else r$crop_name[i]
  src_of <- function(i) r$citation[i]
  base <- function(i, type, d) list(event_type = type, date = format(d), calval_event_id = r$event_id[i])

  # Plantings and crop ends come first; the rows that the calendar orders around them follow
  sown <- data.frame(crop = character(), date = as.Date(character()), stringsAsFactors = FALSE)
  ended <- sown
  when <- function(tbl, crop, y) {
    d <- tbl$date[tbl$crop == crop & yr(tbl$date) == y]
    if (length(d) != 1L) stop(sprintf("%s: %d %s dates in %d", sys, length(d), crop, y))
    d
  }

  for (i in which(r$mgmttype == "planting")) {
    k <- crop_of(i); stopifnot(k %in% CROPS$key)
    cover <- r$cover_crop[i] == "TRUE"
    stopifnot(cover == (slot_of(k) == "cover_crop"))
    pd <- if (cover) pick_date(r[i, ]) else
      pick_date(r[i, ], cand(slot_of(k), "planting_doy", sprintf("plantings of %s", display_of(k))))
    lc <- mon(slot_of(k), "leaf_c_kg_m2")
    leaf_note <- if (cover) sprintf(paste(
      "leaf_c_kg_m2 is the median planting leaf C of G6 (miscellaneous grain and hay) sown in October or",
      "November within %d km of SOCS, %s (n = %d), the closest class: the product has no cover crop",
      "class."), lc$radius_km, lc$years, lc$n) else sprintf(
      "leaf_c_kg_m2 is the median planting leaf C of %s (n = %d).", mon_where(lc), lc$n)
    e <- c(base(i, "planting", pd$date), list(crop_code = k, crop_display = display_of(k),
                                               leaf_c_kg_m2 = round(lc$value, 5)))
    add(tag(e, list(pd$part, part("imputed", leaf_note, MON_SOURCE, "leaf_c_kg_m2",
                                  sprintf("monitoring %s (%s) median", lc$crop_code, slot_of(k)))), sys, src_of(i)))
    sown <- rbind(sown, data.frame(crop = k, date = pd$date))
  }

  for (i in which(r$mgmttype == "harvest")) {
    k <- crop_of(i); stopifnot(k %in% VEGETABLES)
    y <- yr(as.Date(r$min_date[i]))
    pl <- when(sown, k, y)
    hd <- pick_date(r[i, ], cand(slot_of(k), "harvest_doy", sprintf("harvests of %s", display_of(k))),
                    lo = pl + 1, why = sprintf("to after the %s planting (%s)", display_of(k), pl))
    comp <- K[[i]]$harvested_component
    if (identical(comp, "none")) {
      fr <- ALL_TO_LITTER
      fnote <- "Incorporated, not harvested (the crop did not meet market standards), so all of it goes to litter."
    } else {
      hi <- num(K[[i]]$harvest_index); stopifnot(!is.na(hi), comp %in% c("heart", "floret"))
      fr <- marketed(hi)
      fnote <- sprintf(paste("The harvest removes the harvest index, %s of the shoot (White et al. 2020b, one value",
                             "for the whole study); the rest of the shoot and the roots stay in the field as residue."), hi)
    }
    e <- c(base(i, "harvest", hd$date), list(crop_code = k, crop_display = display_of(k)), fr)
    add(tag(e, list(hd$part, part("published", fnote)), sys, src_of(i)))
    ended <- rbind(ended, data.frame(crop = k, date = hd$date))
  }

  # The vegetable ended last before a date, for the tillage the calendar puts after it
  last_vegetable <- function(d) {
    x <- ended[ended$date < d & ended$crop %in% VEGETABLES, ]
    if (!nrow(x)) return(NULL)
    x[which.max(x$date), ]
  }

  for (i in which(r$mgmttype == "tillage")) {
    k <- K[[i]]; imp <- k$implement; stopifnot(!is.null(imp))
    a <- as.Date(r$min_date[i]); y <- yr(a)
    after <- identical(k$relative_timing, "after_harvest")
    fall <- identical(k$relative_to, "cover_crop_or_fallow")
    # The crop events the row is ordered around: the harvest of the crop it follows (for the fall
    # residue incorporation, the last vegetable harvested by the end of its window) and the
    # planting it prepares (the lettuce for the spring spading, a cover crop sown that fall).
    # Which monitoring operation stands in: the first tillage after that harvest, or, for the
    # spring spading, the last tillage before the lettuce planting
    prev <- NULL; nxt <- NULL
    if (after || fall) {
      prev <- if (after) data.frame(crop = k$relative_to, date = when(ended, k$relative_to, y)) else
        last_vegetable(as.Date(r$max_date[i]) + 1)
      if (fall) {
        nxt <- sown[sown$crop %in% COVER_CROPS & yr(sown$date) == y, ]
        if (!nrow(nxt)) nxt <- NULL
      }
      op <- if (is.null(prev)) NULL else list(slot = slot_of(prev$crop), q = "postharvest", crop = prev$crop)
    } else {
      stopifnot(grepl("spader", imp), as.integer(format(a, "%m")) <= 4L)
      nxt <- data.frame(crop = "romaine_lettuce", date = when(sown, "romaine_lettuce", y))
      op <- list(slot = "lettuce", q = "preplant", crop = "romaine_lettuce")
    }
    c_doy <- if (is.null(op)) NULL else {
      post <- op$q == "postharvest"
      x <- cand(op$slot, paste0(op$q, "_tillage_days"), sprintf(
        "the %s tillage event %s %s", if (post) "first" else "last",
        if (post) "after a harvest of" else "before a planting of", display_of(op$crop)))
      anchor <- if (post) prev$date else nxt$date
      x$date <- anchor + if (post) round(x$value) else -round(x$value)
      x$desc <- sprintf("%d days %s the %s %s (%s), %s", as.integer(round(x$value)), if (post) "after" else "before",
                        display_of(op$crop), if (post) "harvest" else "planting", anchor, x$date)
      x
    }
    td <- pick_date(r[i, ], c_doy, lo = if (!is.null(prev)) prev$date + 1, hi = if (!is.null(nxt)) nxt$date - 1,
                    why = paste("to", paste(c(
                      if (!is.null(prev)) sprintf("after the %s harvest (%s)", display_of(prev$crop), prev$date),
                      if (!is.null(nxt)) sprintf("before the %s planting (%s)", display_of(nxt$crop), nxt$date)),
                      collapse = " and ")))
    if (identical(td$part$class, "published") && grepl("(assumed)", r$notes[i], fixed = TRUE))
      td$part <- part("assumed", sprintf(paste("Date from the calendar (%s), which takes the spading as the",
                                               "termination day; the paper does not date it."), r$event_id[i]),
                      NULL, "date", "calendar: spading on the termination day")
    eff <- if (is.null(op)) mon("all", "tillage_eff") else mon(op$slot, paste0(op$q, "_tillage_eff"))
    eff_note <- if (is.null(op)) sprintf(paste(
      "tillage_eff_0to1 is the median of all %d tillage events within %d km of SOCS, %s: no vegetable",
      "precedes this incorporation of the pre-study buckwheat."), eff$n, eff$radius_km, eff$years) else
      sprintf("tillage_eff_0to1 is the median intensity of %s (%s, n = %d).", c_doy$label, mon_where(eff), eff$n)
    e <- c(base(i, "tillage", td$date), list(tillage_eff_0to1 = round(eff$value, 4)))
    if (!is.na(num(r$level[i])) && r$units[i] == "cm depth") e$depth_m <- num(r$level[i]) / 100
    e$implement <- imp
    add(tag(e, list(td$part, part("imputed", eff_note, MON_SOURCE, "tillage_eff_0to1",
                                  if (is.null(op)) "monitoring median of all events" else
                                    sprintf("monitoring %s %s median", eff$crop_code, op$q))), sys, src_of(i),
            what = sprintf("%s%s", imp, if (is.null(op)) "" else sprintf(" (%s %s)", if (op$q == "postharvest")
              "after" else "before", display_of(op$crop)))))
    # A flail mowing and spading in spring ends the winter cover crop sown before it
    if (grepl("flail_mower", imp) && !fall) {
      cc <- sown[sown$crop %in% COVER_CROPS & sown$date < td$date, ]
      cc <- cc[which.max(cc$date), ]
      stopifnot(nrow(cc) == 1L, td$date - cc$date < 200)
      e <- c(list(event_type = "harvest", date = format(td$date), calval_event_id = r$event_id[i],
                  crop_code = cc$crop, crop_display = display_of(cc$crop)), ALL_TO_LITTER)
      dpart <- td$part
      if (dpart$class == "assumed" && dpart$rule == "calendar: spading on the termination day")
        dpart <- part("published", sprintf("Date from the calendar (%s), the termination (flail mowing) day.", r$event_id[i]))
      add(tag(e, list(dpart, part("published", paste(
        "Cover crop termination: flail mowed and spaded in (Brennan and Boyd 2012), so all of it goes to litter.",
        "The calendar has no harvest row for it; the end follows from its tillage row."))), sys, src_of(i)))
      ended <- rbind(ended, data.frame(crop = cc$crop, date = td$date))
    }
  }

  for (i in which(r$mgmttype == "fertilization")) {
    k <- K[[i]]; y <- yr(as.Date(r$min_date[i])); lvl <- num(r$level[i]); stopifnot(!is.na(lvl))
    target <- if (!is.null(k$relative_to)) k$relative_to else k$crop
    stopifnot(target %in% VEGETABLES)
    if (identical(k$relative_timing, "before_planting")) {
      # Preplant, at bed formation; before the second crop also after the lettuce harvest, when
      # the beds were reshaped (White et al. 2020b; the calendar's window for it)
      hi <- when(sown, target, y) - 1
      lo <- if (target != "romaine_lettuce") when(ended, "romaine_lettuce", y) + 1
      why <- sprintf("to %sbefore the %s planting (%s)", if (is.null(lo)) "" else
        sprintf("after the romaine lettuce harvest (%s) and ", lo - 1), display_of(target), hi + 1)
    } else {
      # Liquid fertilizer through the drip, during the crop
      stopifnot(identical(k$method, "drip_fertigation"))
      lo <- when(sown, target, y); hi <- when(ended, target, y)
      why <- sprintf("to the %s season (%s to %s)", display_of(target), lo, hi)
    }
    # The monitoring fertilization product has no day for a preplant or an in-season application:
    # it puts the season's one application on the planting day
    fo <- mon(slot_of(target), "fertilization_days_from_planting")
    fn <- mon(slot_of(target), "fertilization_events_per_season")
    fd <- pick_date(r[i, ], NULL, lo = lo, hi = hi, why = why)
    fd$part$note <- paste(fd$part$note, sprintf(paste(
      "The monitoring fertilization product gives no day for it: for %s it has a median of %g application",
      "a season, %g days from planting."), mon_where(fo), fn$value, fo$value))
    e <- base(i, "fertilization", fd$date)
    if (r$units[i] == "Mg ha-1 (oven-dry)") {
      stopifnot(identical(k$material, "composted_green_waste"))
      n_g_kg <- num(k$N_content_g_kg); stopifnot(!is.na(n_g_kg))
      e <- c(e, list(org_c_kg_m2 = round(lvl * MG_HA_TO_KG_M2 * COMPOST_C_G_KG / 1000, 7),
                     org_n_kg_m2 = round(lvl * MG_HA_TO_KG_M2 * n_g_kg / 1000, 7),
                     material = k$material, compost_oven_dry_mg_ha = lvl, compost_c_g_kg = COMPOST_C_G_KG,
                     compost_n_g_kg = n_g_kg))
      amounts <- list(
        part("derived", sprintf(paste("org_c_kg_m2 is the %s Mg ha-1 oven dry compost times its C, %d g C kg-1",
                                      "(White et al. 2020b)."), lvl, COMPOST_C_G_KG), WHITE_2020B, "org_c_kg_m2",
             "compost C from tonnage and 317 g C/kg"),
        part("assumed", sprintf(paste("org_n_kg_m2 takes the calendar's N_content_g_kg = %s, which has no",
                                      "published source (C:N %.1f against the published 18 to 28, mean 22)."),
                                k$N_content_g_kg, COMPOST_C_G_KG / n_g_kg), NULL, "org_n_kg_m2",
             "compost N from the unsourced calendar N_content_g_kg"))
    } else {
      stopifnot(r$units[i] == "kg N ha-1")
      if (identical(k$material, "pelleted_poultry_manure_feather_meal")) {
        cn <- mean(PELLET_CN)
        e <- c(e, list(org_c_kg_m2 = round(lvl * KG_HA_TO_KG_M2 * cn, 7), org_n_kg_m2 = round(lvl * KG_HA_TO_KG_M2, 7),
                       material = k$material, n_kg_ha = lvl, c_to_n = round(cn, 4)))
        amounts <- list(part("assumed", sprintf(paste(
          "Pelleted organic fertilizer, %s kg N ha-1 as organic N; org_c_kg_m2 at a C:N of %.2f, the mean of",
          "the two products' C (White et al. 2020b: 280 g C kg-1 in the 4-4-2, 370 in the 8-1-1) over their N",
          "grades (C:N 7.00 and 4.63), as the product used each year is not reported."), lvl, cn),
          WHITE_2020B, "org_c_kg_m2", "pellet C: mean C:N of the two products"))
      } else {
        stopifnot(identical(k$material, "liquid_organic_fertilizer"))
        e <- c(e, list(nh4_n_kg_m2 = round(lvl * KG_HA_TO_KG_M2, 7), material = k$material, n_kg_ha = lvl))
        amounts <- list(part("assumed", sprintf(paste(
          "Liquid organic fertilizer through the drip, %s kg N ha-1 (the calendar's total less the pellets).",
          "Its C is not published and no guidance gives a C:N, so the N goes in as mineral N (nh4_n_kg_m2)",
          "without C."), lvl), NULL, "nh4_n_kg_m2", "liquid N as mineral N without C"))
      }
    }
    add(tag(e, c(list(fd$part), amounts), sys, src_of(i), what = sprintf("%s (%s)", k$material, display_of(target))))
  }

  for (i in which(r$mgmttype == "irrigation")) {
    k <- K[[i]]
    if (identical(k$purpose, "cover_crop_establishment")) {
      # Published total, days and last day (Brennan and Boyd 2012 Fig. 2 and Table 2). Each
      # application day gets an equal share, the first on the planting day and the rest evenly to
      # the last irrigation, which the papers date.
      a <- as.Date(r$min_date[i]); b <- as.Date(r$max_date[i])
      nd <- as.integer(k$application_days); tot <- num(r$level[i])
      stopifnot(nd >= 1L, !is.na(tot), identical(k$method, "sprinkler_linear_move"), nd == 1L || b > a)
      days <- if (nd == 1L) b else as.Date(round(seq(as.numeric(a), as.numeric(b), length.out = nd)), origin = "1970-01-01")
      stopifnot(!anyDuplicated(days))
      for (j in seq_along(days)) {
        e <- c(base(i, "irrigation", days[j]), list(amount_mm = round(tot / nd, 3), method = "canopy"))
        dp <- if (nd == 1L) part("published", sprintf("Date from the calendar (%s).", r$event_id[i])) else
          if (j == nd) part("published", sprintf("The last cover crop irrigation, dated in the calendar (%s).", r$event_id[i])) else
            part("assumed", sprintf(paste("Application %d of %d: the calendar gives the planting day and the last",
                                          "irrigation (%s to %s, %s), and the days between are spaced evenly."),
                                    j, nd, a, b, r$event_id[i]), NULL, "date", "cover crop irrigation day spaced evenly")
        ap <- part(if (nd == 1L) "published" else "derived", sprintf(
          "%s mm of sprinkler irrigation to establish the cover crop, %s. Method canopy: a linear move sprinkler.",
          tot, if (nd == 1L) "on one day" else sprintf("on %d days, %s mm each", nd, round(tot / nd, 3))),
          NULL, "amount_mm", "cover crop irrigation total over days")
        add(tag(e, list(dp, ap), sys, src_of(i), what = "cover crop establishment"))
      }
      next
    }
    # Vegetables: no paper gives the amount. Season water from the monitoring product's median
    # irrigation rate over irrigated seasons of the matching class and months, times this season's
    # length, on a drip schedule
    crop <- k$crop; stopifnot(crop %in% VEGETABLES)
    y <- yr(as.Date(r$min_date[i]))
    pl <- when(sown, crop, y); hv <- when(ended, crop, y)
    stopifnot(pl >= as.Date(r$min_date[i]), hv <= as.Date(r$max_date[i]))
    islot <- if (crop == "broccoli") "broccoli_irrigation" else slot_of(crop)
    rate <- mon(islot, "irrigated_mm_per_day")
    days <- seq(pl, hv - 1, by = IRRIGATION_EVERY_DAYS)
    season_mm <- rate$value * as.numeric(hv - pl)
    amt <- round(season_mm / length(days), 3)
    method <- if (identical(k$method, "drip")) "drip" else NA_character_
    for (j in seq_along(days)) {
      e <- c(base(i, "irrigation", days[j]), list(amount_mm = amt, method = "soil"))
      add(tag(e, list(
        part("imputed", sprintf(paste(
          "No paper gives the amount. %.1f mm for the %s season (%s to %s, %d days): the median irrigation rate,",
          "%.3f mm a day, of irrigated seasons of %s (n = %d; %d %% of seasons irrigated)%s, an ET based lower bound."),
          season_mm, display_of(crop), pl, hv, as.integer(hv - pl), rate$value, mon_where(rate), rate$n,
          as.integer(round(100 * mon(islot, "irrigated_share")$value)),
          if (crop == "broccoli") sprintf(paste(", standing in for broccoli: the product's own cole crop class, T4, is",
                                                "irrigated in only %d %% of its July and August seasons, implausibly little"),
                                          as.integer(round(100 * mon("broccoli", "irrigated_share")$value))) else ""),
          MON_SOURCE, "amount_mm", sprintf("monitoring %s irrigation rate times season", rate$crop_code)),
        part("imputed", sprintf("Event %d of %d, one every %d days from planting (scenarios irrigation_drip guidance).",
                                j, length(days), IRRIGATION_EVERY_DAYS), PRIORS_SOURCE, "date", "drip schedule every 3 days"),
        if (is.na(method)) part("assumed", paste(
          "Method soil: the papers do not report the spinach's irrigation method; taken as the drip the",
          "site's other vegetables had."), NULL, "method", "spinach method taken as drip") else
          part("published", "Method soil: drip.")), sys, src_of(i), what = display_of(crop)))
    }
  }

  events <- events[order(vapply(events, `[[`, "", "date"), vapply(events, `[[`, "", "event_type"))]
  list(events = events, sown = sown, ended = ended, rows = r)
}

# Checks on a system's events against its calendar rows
check_system <- function(sys, b) {
  ev <- b$events; r <- b$rows
  check_harvest_fractions(ev)
  d <- as.Date(vapply(ev, `[[`, "", "date"))
  stopifnot(all(d >= FIRST_DATE & d <= LAST_DATE))
  type <- vapply(ev, `[[`, "", "event_type")
  n_cal <- table(factor(r$mgmttype, c("planting", "harvest", "tillage", "fertilization", "irrigation")))
  n_cc <- sum(r$mgmttype == "planting" & r$cover_crop == "TRUE")
  stopifnot(sum(type == "planting") == n_cal[["planting"]], sum(type == "harvest") == n_cal[["harvest"]] + n_cc,
            sum(type == "tillage") == n_cal[["tillage"]], sum(type == "fertilization") == n_cal[["fertilization"]])
  # Every calendar row is in the events, and a cover crop irrigation row once per application day
  ids <- vapply(ev, `[[`, "", "calval_event_id")
  stopifnot(setequal(ids, r$event_id))
  cc_irr <- r[r$mgmttype == "irrigation" & grepl("cover_crop_establishment", r$attributes_keyvalue), ]
  stopifnot(all(table(factor(ids, cc_irr$event_id)) ==
                  as.integer(sub(".*application_days=([0-9]+).*", "\\1", cc_irr$attributes_keyvalue))))
  # One crop at a time: plantings and ends alternate, each end of the crop planted before it
  pe <- ev[type %in% c("planting", "harvest")]
  seq_type <- vapply(pe, `[[`, "", "event_type"); seq_crop <- vapply(pe, `[[`, "", "crop_code")
  stopifnot(all(seq_type == rep(c("planting", "harvest"), length.out = length(pe))),
            all(seq_crop[seq_type == "planting"] == seq_crop[seq_type == "harvest"]))
  # One cycle of each crop a year
  pl <- ev[type == "planting"]
  key <- paste(vapply(pl, `[[`, "", "crop_code"), substr(vapply(pl, `[[`, "", "date"), 1, 4))
  stopifnot(!anyDuplicated(key))
  # Each tillage on its side of the crop events its row is ordered around: after the harvest it
  # follows (a fall residue incorporation after every vegetable harvest of its year) and before the
  # planting it prepares (the spring spading before the lettuce, a fall pass before a cover crop
  # sown that fall)
  dates_of <- function(t, crops, y) as.Date(vapply(Filter(function(e) e$event_type == t && e$crop_code %in% crops &&
                                                             startsWith(e$date, y), ev), `[[`, "", "date"))
  for (e in ev[type == "tillage"]) {
    k <- kv(r$attributes_keyvalue[r$event_id == e$calval_event_id])
    fall <- identical(k$relative_to, "cover_crop_or_fallow")
    follows <- if (fall) VEGETABLES else if (identical(k$relative_timing, "after_harvest")) k$relative_to
    prepares <- if (fall) COVER_CROPS else if (is.null(k$relative_timing)) "romaine_lettuce"
    d <- as.Date(e$date); y <- substr(e$date, 1, 4)
    if (!all(dates_of("harvest", follows, y) < d) || !all(dates_of("planting", prepares, y) > d))
      stop(sprintf("%s: the tillage of %s on %s is not after the harvest it follows and before the planting it prepares",
                   sys, e$calval_event_id, d))
  }
  for (e in ev) stopifnot(!is.null(e$source), e$provenance_class %in% PROVENANCE_CLASSES,
                          e$provenance_class == "published" || nzchar(e$provenance_note))
  invisible(TRUE)
}

calendar_md5 <- unname(tools::md5sum(file.path(cal_dir, "managements.csv")))
FILL_NOTE <- paste(
  "Built from the SOCS management calendar (cal-val-data managements.csv): an event for each operation",
  "on its rows (a cover crop irrigation row on each of its application days, a vegetable irrigation row as",
  "a drip schedule), plus the termination of each winter cover crop at its spring flail mowing and spading; nothing from",
  "the earlier uncertainty#6 fills. Where a row gives a window, the event takes the monitoring product's",
  "median day for the crop and operation near SOCS when it falls in the window (imputed), otherwise the",
  "window's midpoint (assumed); windows the calendar orders around a planting or harvest are narrowed to",
  "the dates chosen for those. Planting leaf C, vegetable irrigation and tillage intensity come from the",
  "monitoring product near SOCS (monitoring_near_salinas.csv), the drip interval from the scenarios",
  "priors. Harvests remove White et al. 2020b's harvest index (lettuce 0.26, broccoli 0.24) with the",
  "rest and the roots to litter; the 2004 spinach, the 2005 broccoli and the cover crops go wholly to",
  "litter. Compost C is the published 317 g C kg-1; its N is the calendar's unsourced 15 g N kg-1.",
  "See runs/salinas_socs/README.md.")

fills_all <- list()
for (sys in SYSTEMS) {
  FILLS <- list()
  b <- build_system(sys)
  check_system(sys, b)
  tr <- treatments[treatments$name == sys, ]
  stopifnot(nrow(tr) == 1L)
  out <- list(
    pecan_events_version = "0.1.1",
    site_id = sys,
    provenance = list(
      dataset_id = "white_salinas_2020", treatment = sys, treatment_definition = tr$definition,
      generator = "calibration:tools/event_prep/salinas_build_events.R",
      calendar = "ccmmf/cal-val-data:data/managements.csv (calval-metadata)", calendar_md5 = calendar_md5,
      monitoring = MON_SOURCE, monitoring_products = MON$products[1], note = FILL_NOTE),
    events = b$events)
  fn <- file.path(out_dir, sprintf("events_%s.json", sys))
  write(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = 1, digits = NA), fn)
  type <- vapply(b$events, `[[`, "", "event_type")
  cat(sprintf("%s %3d events (%s) -> %s\n", sys, length(b$events),
              paste(sprintf("%s %d", names(table(type)), table(type)), collapse = ", "), basename(fn)))
  fills_all[[sys]] <- do.call(rbind, FILLS)
}

fills <- do.call(rbind, fills_all)
grp <- c("event_type", "what", "item", "rule", "class", "source")
key <- do.call(paste, c(fills[grp], sep = "\r"))
smry <- unique(fills[grp])
smry$n_events <- as.integer(table(key)[do.call(paste, c(smry[grp], sep = "\r"))])
smry$by_system <- vapply(do.call(paste, c(smry[grp], sep = "\r")), function(k) {
  s <- fills$system[key == k]
  paste(sprintf("%s=%d", SYSTEMS, as.integer(table(factor(s, SYSTEMS)))), collapse = ";")
}, "")
smry <- smry[order(smry$event_type, smry$what, smry$item, smry$rule), ]
write.csv(smry, file.path(out_dir, "fill_summary.csv"), row.names = FALSE)
cat(sprintf("wrote %d fill rows to fill_summary.csv\n", nrow(smry)))
