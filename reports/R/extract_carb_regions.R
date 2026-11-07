# Extract CARB's cropland area and soil carbon by county, region and year for the regional
# inventory comparison (organization#226). Run from the repository root with the path to the table:
#   Rscript reports/R/extract_carb_regions.R path/to/NWL_Carbon_Inventory_2025_aggregated_data_table.xlsx
# The table is CARB's aggregated data for the 2025 Natural and Working Lands Carbon Inventory,
# https://ww2.arb.ca.gov/sites/default/files/2026-04/NWL_Carbon_Inventory_2025_aggregated_data_table.xlsx
# Its Region column is CARB's assignment of each 30 m pixel to the nine California Fifth Climate
# Change Assessment regions (Appendix B, Regional Assessment), so county by region rows give CARB's
# own county-to-region split. Rows are summed over ownership, air district and ecoregion; units stay
# as published (acres, metric tons C). UNDEFINED rows are kept as published.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1, file.exists(args[1]))
out <- "reports/data/inventory"
table <- as.data.frame(readxl::read_excel(args[1], sheet = "Aggregated Data"))
stopifnot(identical(names(table),
                    c("Year", "County", "Air District", "Ownership", "Region", "Ecoregion",
                      "Land Cover", "Acreage", "Biomass Carbon MT C", "Soil Carbon MT C",
                      "Total Carbon MT C", "GHG MT CO2e")))
crop <- table[table$`Land Cover` == "Cropland" & table$Year %in% 2014:2022,
              c("Year", "County", "Region", "Acreage", "Soil Carbon MT C")]
names(crop) <- c("year", "county", "region", "acres", "soil_c_mt_c")
stopifnot(!anyNA(crop), setequal(crop$year, 2014:2022))
crop <- stats::aggregate(cbind(acres, soil_c_mt_c) ~ year + county + region, crop, sum)
crop <- crop[order(crop$year, crop$county, crop$region), ]
utils::write.csv(crop, file.path(out, "carb_2025_cropland_county_region.csv"), row.names = FALSE)
cat("source sha256:", digest::digest(file = args[1], algo = "sha256"), "\n")
