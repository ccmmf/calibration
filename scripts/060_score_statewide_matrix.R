#!/usr/bin/env Rscript
# post-process the completed statewide matrix into the model_vs_evidence
# scorecard: paired treatment effects per site, MODEL-SIDE AGGREGATION FIRST
# (one model estimate per target cell against one synthesis estimate), mapped
# to summarized_targets.csv. the target table for read. no pseudo
# observations, no calibration; likelihood cells, sign checks, structural and
# blocked cells are kept distinct.

suppressPackageStartupMessages(library(dplyr))

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)
ws <- config$workspace
pkg <- config$event_package$root
t0 <- config$soc_endpoints[1]
t1 <- config$soc_endpoints[2]
# practice years are inclusive of both endpoints
n_window <- t1 - t0 + 1

# annual reduction of the standard model output, cached: the scorer re-reads it
# on every pass but the runs do not change. reads the netcdf written by
# model2netcdf.SIPNET rather than the raw model file, so variable names and
# units come from the model package
ann_path <- file.path(ws, "annual_outputs.csv")
read_run_years <- function(dir) {
  files <- list.files(dir, pattern = "^[0-9]{4}\\.nc$", full.names = TRUE)
  dplyr::bind_rows(lapply(files, function(f) {
    nc <- ncdf4::nc_open(f)
    on.exit(ncdf4::nc_close(nc))
    get <- function(v) as.numeric(ncdf4::ncvar_get(nc, v))
    # kg C m-2 -> Mg C ha-1; fluxes are per second over the output step
    tot <- get("TotSoilCarb") * 10
    lit <- get("litter_carbon_content") * 10
    step <- diff(as.numeric(nc$dim$time$vals)[1:2]) * 86400
    tibble::tibble(
      year = as.integer(sub("\\.nc$", "", basename(f))),
      soc_first = tot[1], soc_last = tot[length(tot)],
      soil_first = (tot - lit)[1], soil_last = (tot - lit)[length(tot)],
      n2o_sum = sum(get("N2O_flux")) * step,
      ch4_sum = sum(get("CH4_flux")) * step
    )
  }))
}
if (!file.exists(ann_path)) {
  runs <- list.dirs(file.path(ws, "output", "out"), recursive = FALSE)
  ann <- dplyr::bind_rows(lapply(runs, function(d) {
    id <- sub("^ENS-[0-9]+-", "", basename(d))
    read_run_years(d) |>
      mutate(site = sub("\\..*$", "", id), arm = sub("^[^.]*\\.", "", id),
             .before = 1)
  }))
  utils::write.csv(ann, ann_path, row.names = FALSE)
}
ann <- utils::read.csv(ann_path, colClasses = c(site = "character"))
pairs <- utils::read.csv(file.path(pkg, "run_pairs.csv"),
                         colClasses = c(site_id = "character"))
tm <- utils::read.csv(config$scoring$treatment_matrix)
targets <- utils::read.csv(config$scoring$summarized_targets,
                           check.names = FALSE)

# prepared cover-years per site: the denominator for the per-cover-year rate
exposure <- utils::read.csv(file.path(pkg, "exposure.csv"),
                            colClasses = c(site_id = "character"))
cover_years <- exposure |>
  filter(practice == "cover_annual", status == "prepared") |>
  count(site_id, name = "n_cover_years")

## site-level paired effects --------------------------------------------------
# paired SOC effect = last-timestep(t1) arm difference. pre-simulation states
# are identical within a pair (shared sipnet.param), so no output-row anchor
# is needed; day-1 events are applied BEFORE the first output row, which made
# a first-row anchor wrong for sites with a day-1 amendment. annual means are
# contaminated by within-year transient timing (large harvest litter
# transfers land on different days across arms), so they are not used either.
soc_of <- function(site, arm, yr, col) {
  v <- ann[[col]][ann$site == site & ann$arm == arm & ann$year == yr]
  if (length(v) != 1) NA_real_ else v
}
sum_of <- function(site, arm, var, y0, y1) {
  sel <- ann$site == site & ann$arm == arm & ann$year >= y0 & ann$year <= y1
  if (!any(sel)) NA_real_ else sum(ann[[var]][sel])
}

staged_pairs <- pairs |>
  mutate(pair_ok = vapply(seq_len(n()), function(i) {
    !is.na(soc_of(site_id[i], treatment[i], t1, "soc_last")) &&
      !is.na(soc_of(site_id[i], reference[i], t1, "soc_last"))
  }, logical(1)))

ty0 <- config$scoring$tillage_n2o_years[1]
ty1 <- config$scoring$tillage_n2o_years[2]
eff <- staged_pairs |>
  filter(pair_ok) |>
  rowwise() |>
  mutate(
    dd_soc = soc_of(site_id, treatment, t1, "soc_last") -
      soc_of(site_id, reference, t1, "soc_last"),
    dd_soc_per_window_yr = dd_soc / n_window,
    lrr_n2o_till = log(sum_of(site_id, treatment, "n2o_sum", ty0, ty1) /
                         sum_of(site_id, reference, "n2o_sum", ty0, ty1)),
    lrr_n2o_full = log(sum_of(site_id, treatment, "n2o_sum", t0, t1) /
                         sum_of(site_id, reference, "n2o_sum", t0, t1)),
    lrr_ch4_full = log(sum_of(site_id, treatment, "ch4_sum", t0, t1) /
                         sum_of(site_id, reference, "ch4_sum", t0, t1)),
    # amendment operator is a stock ratio at a common time point, not a rate.
    # reported on both pools: sipnet routes amendment orgC to the litter pool
    # (events.c eventLitterC), so soil+litter counts undecomposed compost that
    # a measured 0-30 cm SOC stock would not
    soc_lrr_end = log(soc_of(site_id, treatment, t1, "soc_last") /
                        soc_of(site_id, reference, t1, "soc_last")),
    soil_lrr_end = log(soc_of(site_id, treatment, t1, "soil_last") /
                         soc_of(site_id, reference, t1, "soil_last"))
  ) |>
  ungroup() |>
  left_join(cover_years, by = "site_id") |>
  mutate(dd_soc_per_cover_yr = ifelse(treatment == "cover_annual",
                                      dd_soc / n_cover_years, NA_real_))

## rice operators are season totals, so the flooded season is read per site --
# non-rice months carry identical CH4 in both arms and would dilute the ratio
season_windows <- function(site) {
  f <- file.path(pkg, "events", site, "rice_irrigated_reference", "events.in")
  p <- strsplit(trimws(grep("[[:space:]]irrig[[:space:]]", readLines(f, warn = FALSE),
                            value = TRUE)), "[[:space:]]+")
  p <- p[vapply(p, function(x) x[5] == "1", logical(1))]
  y <- as.integer(vapply(p, `[`, character(1), 1))
  d <- as.integer(vapply(p, `[`, character(1), 2))
  lapply(split(d, y), range)
}
season_sum <- function(site, arm, win, var) {
  d <- file.path(ws, "output", "out", paste0("ENS-00001-", site, ".", arm))
  sum(vapply(names(win), function(y) {
    nc <- ncdf4::nc_open(file.path(d, paste0(y, ".nc")))
    on.exit(ncdf4::nc_close(nc))
    day <- as.numeric(nc$dim$time$vals) + 1
    step <- diff(as.numeric(nc$dim$time$vals)[1:2]) * 86400
    x <- as.numeric(ncdf4::ncvar_get(nc, var))
    w <- win[[y]]
    sum(x[day >= w[1] & day <= w[2] + 1]) * step
  }, numeric(1)))
}
var_nc <- list(n2o = "N2O_flux", ch4 = "CH4_flux")
rice <- eff$treatment %in% c("rice_one_dry", "rice_two_dry")
eff$lrr_n2o_season <- NA_real_
eff$lrr_ch4_season <- NA_real_
for (i in which(rice)) {
  win <- season_windows(eff$site_id[i])
  for (v in c("n2o", "ch4")) {
    tr <- season_sum(eff$site_id[i], eff$treatment[i], win, var_nc[[v]])
    rf <- season_sum(eff$site_id[i], eff$reference[i], win, var_nc[[v]])
    eff[[paste0("lrr_", v, "_season")]][i] <- log(tr / rf)
  }
}
utils::write.csv(eff, file.path(ws, "site_pair_effects.csv"), row.names = FALSE)

## fertilizer operator is the SLOPE of the emission factor against N rate ----
# (shcherbak nonlinearity), not a treatment contrast, so it is computed once
# across the 0.5x, 1x and 1.5x arms rather than per pair
# mineral N applied, g N m-2 in the event file, returned as kg N m-2 to match
# the model output units
n_applied <- function(site) {
  f <- file.path(pkg, "events", site, "fertilizer_reference", "events.in")
  p <- strsplit(trimws(grep("[[:space:]]fert[[:space:]]", readLines(f, warn = FALSE),
                            value = TRUE)), "[[:space:]]+")
  if (!length(p)) return(0)
  sum(as.numeric(vapply(p, `[`, character(1), 6))) / 1000
}
n2o_win <- function(site, arm) sum_of(site, arm, "n2o_sum", t0, t1)
fert_sites <- unique(eff$site_id[eff$treatment == "mineral_N_zero"])
ef_slope <- vapply(fert_sites, function(s) {
  # kg N m-2 over the window -> kg N ha-1 yr-1
  rate <- n_applied(s) * 1e4 / n_window
  if (rate <= 0) return(NA_real_)
  z <- n2o_win(s, "mineral_N_zero")
  # shcherbak 2014 defines EF as a PERCENTAGE of N applied and dEF/dN as the
  # percent change in EF per kg N ha-1, so the model side is scaled to match
  ef <- function(arm, mult) 100 * (n2o_win(s, arm) - z) / (n_applied(s) * mult)
  (ef("mineral_N_one_half", 1.5) - ef("mineral_N_half", 0.5)) / rate
}, numeric(1))

## model-side aggregation: ONE estimate per treatment x metric ---------------
agg <- function(x) {
  x <- x[is.finite(x)]
  c(mean = mean(x), sd = stats::sd(x), n = length(x),
    median = stats::median(x), frac_pos = mean(x > 0),
    # a treatment the model cannot respond to returns bit-identical output;
    # this separates a small effect from an absent mechanism
    frac_zero = mean(x == 0))
}
model_effect <- function(trt, metric) {
  agg(eff[[metric]][eff$treatment == trt])
}
# which metric feeds which pair row of the treatment matrix
metric_of <- c(
  cover_soc = "dd_soc_per_cover_yr",
  # bai operator is a measured soil stock ratio; sipnet routes amendment orgC
  # to the litter pool, so soil only is the matching pool and soil+litter is
  # carried alongside as model_effect_soil_plus_litter
  org_sub = "soil_lrr_end",
  till_reduced_soc = "dd_soc_per_window_yr",
  till_zero_soc = "dd_soc_per_window_yr",
  till_zero_n2o = "lrr_n2o_till",
  rice_one_n2o = "lrr_n2o_season",
  rice_two_n2o = "lrr_n2o_season",
  rice_one_ch4 = "lrr_ch4_season",
  rice_two_ch4 = "lrr_ch4_season",
  # SOC is bit-identical to reference for the scaled arms (mineral N feeds
  # nitrification/N2O only; growth is not N limited), so N2O is the response
  minN_zero = "lrr_n2o_full",
  minN_half = "lrr_n2o_full",
  minN_onehalf = "lrr_n2o_full"
)

rows <- list()
for (i in seq_len(nrow(tm))) {
  r <- tm[i, ]
  metric <- metric_of[r$pair_id]
  structural <- grepl("STRUCTURALLY UNREACHABLE|NO RUNNABLE PAIR",
                      r$structural_flags)
  if (r$pair_id == "minN_ef_slope") {
    m <- agg(ef_slope)
  } else if (is.na(r$treatment) || r$treatment == "" || structural ||
             is.na(metric)) {
    m <- c(mean = NA, sd = NA, n = 0, median = NA, frac_pos = NA,
           frac_zero = NA)
  } else {
    m <- model_effect(r$treatment, metric)
  }
  # target lookup, read only. the table is keyed practice x outcome x subclass;
  # stratified cells carry several rows and must be matched on all three
  cell <- strsplit(r$target_cell, " x ")[[1]]
  trow <- if (length(cell) == 2) {
    targets |> filter(practice_table6 == cell[1], outcome == cell[2],
                      subclass == r$target_subclass)
  } else targets[0, ]
  rows[[r$pair_id]] <- tibble::tibble(
    pair_id = r$pair_id, treatment = r$treatment, reference = r$reference,
    metric = ifelse(is.na(metric), "", metric),
    target_cell = r$target_cell,
    target_use = if (nrow(trow) == 1) trow$use else "",
    target_center = if (nrow(trow) == 1) trow$center else NA,
    target_spread = if (nrow(trow) == 1) trow$spread else NA,
    target_spread_type = if (nrow(trow) == 1) trow$spread_type else "",
    target_units = if (nrow(trow) == 1) trow[["scale/units"]] else "",
    model_effect = unname(m["mean"]),
    model_median = unname(m["median"]),
    model_sd_across_sites = unname(m["sd"]),
    model_n_sites = unname(m["n"]),
    model_frac_positive = unname(m["frac_pos"]),
    model_frac_exact_zero = unname(m["frac_zero"]),
    model_effect_soil_plus_litter = if (r$pair_id == "org_sub") {
      mean(eff$soc_lrr_end[eff$treatment == r$treatment], na.rm = TRUE)
    } else NA_real_,
    model_effect_per_window_yr = if (r$pair_id == "cover_soc") {
      mean(eff$dd_soc[eff$treatment == r$treatment] / n_window, na.rm = TRUE)
    } else NA_real_,
    model_direction = ifelse(is.na(m["mean"]), "",
                             ifelse(m["mean"] > 0, "increase", "decrease")),
    # z against the target's own spread, and against the model's across-site
    # spread. which one is meaningful depends on spread_type: an se on the
    # mean answers "does the model match the synthesis estimate", a
    # population sd answers "does it sit inside the observed heterogeneity"
    z_vs_target_spread = if (nrow(trow) == 1 && !is.na(m["mean"]) &&
                             !is.na(trow$spread) && trow$spread > 0) {
      unname((m["mean"] - trow$center) / trow$spread)
    } else NA_real_,
    z_vs_model_spread = if (nrow(trow) == 1 && !is.na(m["mean"]) &&
                            !is.na(m["sd"]) && m["sd"] > 0) {
      unname((m["mean"] - trow$center) / m["sd"])
    } else NA_real_,
    status = dplyr::case_when(
      structural ~ "structural_unrunnable",
      nrow(trow) == 1 && trow$use == "none" && r$target_cell != "" ~
        "target_retired_upstream",
      is.na(metric) && r$pair_id != "minN_ef_slope" ~ "no_metric",
      m["n"] == 0 ~ "no_pairs",
      # most sites bit-identical between arms = no mechanism, not a small
      # effect; do not present the mean of a near-all-zero set as an estimate
      !is.na(m["frac_zero"]) && m["frac_zero"] >= 0.5 ~ "structural_no_response",
      TRUE ~ "scored"
    ),
    structural_flags = r$structural_flags
  )
}
score <- dplyr::bind_rows(rows)

## fertilizer dose response --------------------------------------------------
# the cell is a slope across the N arms rather than a pair, so it is scored
# once per crop class. the published groups other than N fixers do not differ
# from each other, so the panel splits in two on N fixation
fert_cell <- targets |>
  filter(practice_table6 == "+/- N Fertilization", outcome == "N2O",
         subclass %in% c("non N fixing crops", "N fixing crops"))
pft <- utils::read.csv(config$pfts$assignment,
                       colClasses = c(site_id = "character"))
crop_rows <- tibble::tibble(site_id = names(ef_slope), slope = unname(ef_slope)) |>
  filter(!is.na(slope)) |>
  left_join(pft |> select(site_id, veg_pft), by = "site_id") |>
  mutate(subclass = ifelse(veg_pft == "annual_crop_alfalfa",
                           "N fixing crops", "non N fixing crops")) |>
  summarise(model_effect = mean(slope), model_median = stats::median(slope),
            model_sd_across_sites = stats::sd(slope), model_n_sites = dplyr::n(),
            .by = subclass) |>
  left_join(fert_cell |> select(subclass, use, center, spread, spread_type,
                                units = `scale/units`), by = "subclass") |>
  mutate(pair_id = paste0("minN_dEFdN_", gsub(" ", "_", subclass)),
         metric = "ef_slope",
         target_cell = "+/- N Fertilization x N2O",
         target_subclass = subclass, target_use = use,
         target_center = center, target_spread = spread,
         target_spread_type = spread_type, target_units = units,
         z_vs_target_spread = (model_effect - center) / spread,
         status = "scored",
         structural_flags = paste("N2O is first order in the mineral N pool,",
                                  "so the emission factor is constant in N rate")) |>
  select(-subclass, -use, -center, -spread, -spread_type, -units)
score <- dplyr::bind_rows(score, crop_rows)

utils::write.csv(score, file.path(ws, "model_vs_evidence_scorecard.csv"),
                 row.names = FALSE)
cat("pairs scored:", sum(staged_pairs$pair_ok), "of", nrow(pairs),
    "(blocked:", sum(!staged_pairs$pair_ok), ")\n\n")
print(score |>
        filter(target_use != "" | status != "no_metric") |>
        select(pair_id, target_use, target_center, target_spread_type,
               model_effect, z_vs_target_spread, model_frac_exact_zero,
               status) |>
        as.data.frame(), digits = 3)
