#!/usr/bin/env Rscript
# assign per-site veg and soil pfts for the statewide matrix, the statewide
# analog of the cal/val blocks.csv columns: one (veg_pft, soil_pft) per site,
# derived deterministically from the site's LandIQ crop history rather than
# hand curated. dominant class over the run window picks the crop pft
# (annual_crop_row/corn/alfalfa/rice, grass, temperate.deciduous_almond);
# alfalfa-dominant sites pair with soil_nfixer and the package's rice-arm
# sites with soil_rice, mirroring the cal/val pairing. sipnet parameters are
# run constant, so rotation years off the dominant crop keep the site's
# assignment; the manifest records alfalfa/rice year counts so that residual
# is visible, not silent.
#
# run under R/4.5.2 (arrow with zstd for the crops parquet).

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

args <- optparse::parse_args(optparse::OptionParser(option_list = list(
  optparse::make_option(c("-c", "--config"), default = "config.yml",
    help = "project config yaml [default: %default]")
)))
config <- config::get(file = args$config)
ws <- config$workspace
pkg <- config$event_package$root

sites <- read.csv(file.path(pkg, "sites.csv"),
                  colClasses = c(site_id = "character"))
pairs <- read.csv(file.path(pkg, "run_pairs.csv"),
                  colClasses = c(site_id = "character"))
rice_sites <- unique(pairs$site_id[grepl("^rice", pairs$treatment)])

yr0 <- as.integer(format(as.Date(config$window$start), "%Y"))
yr1 <- as.integer(format(as.Date(config$window$end), "%Y"))
crops <- read_parquet(config$pfts$crops_parquet) |>
  mutate(parcel_id = as.character(parcel_id)) |>
  filter(parcel_id %in% sites$site_id, year >= yr0, year <= yr1,
         !is.na(CLASS), nzchar(trimws(CLASS))) |>
  mutate(code = paste0(CLASS, SUBCLASS))

dominant <- crops |>
  count(parcel_id, code) |>
  slice_max(n, n = 1, with_ties = FALSE, by = parcel_id) |>
  select(parcel_id, dominant_class = code)
year_counts <- crops |>
  summarise(n_alfalfa_years = n_distinct(year[code == "P1"]),
            n_rice_years = n_distinct(year[CLASS == "R"]),
            .by = parcel_id)

asg <- sites |>
  select(site_id, design_pft, source_site_pft) |>
  left_join(dominant, by = c(site_id = "parcel_id")) |>
  left_join(year_counts, by = c(site_id = "parcel_id")) |>
  mutate(
    n_alfalfa_years = coalesce(n_alfalfa_years, 0L),
    n_rice_years = coalesce(n_rice_years, 0L),
    veg_pft = case_when(
      source_site_pft == "temperate.deciduous" ~ "temperate.deciduous_almond",
      is.na(source_site_pft) & design_pft == "woody perennial crop" ~
        "temperate.deciduous_almond",
      dominant_class == "P1" ~ "annual_crop_alfalfa",
      substr(dominant_class, 1, 1) == "R" ~ "annual_crop_rice",
      dominant_class == "F16" ~ "annual_crop_corn",
      source_site_pft == "grass" ~ "grass",
      TRUE ~ "annual_crop_row"
    ),
    soil_pft = case_when(
      veg_pft == "annual_crop_alfalfa" ~ "soil_nfixer",
      site_id %in% rice_sites ~ "soil_rice",
      TRUE ~ "soil"
    )
  )

dir.create(ws, recursive = TRUE, showWarnings = FALSE)
write.csv(asg, file.path(ws, "site_pft_assignment.csv"), row.names = FALSE)
cat("veg pft counts:\n"); print(table(asg$veg_pft))
cat("soil pft counts:\n"); print(table(asg$soil_pft))
cat("sites with alfalfa years but a non-nfixer soil (rotation residual):",
    sum(asg$n_alfalfa_years > 0 & asg$soil_pft != "soil_nfixer"), "\n")
