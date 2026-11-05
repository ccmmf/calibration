# Extract the CARB cropland numbers used by the inventory comparison (organization#226).
# Run from the repository root with the path to the CARB workbook:
#   Rscript reports/R/extract_carb_appendix_c.R path/to/CARB_2025_NWL_Carbon_Inventory_Appendix_C-Croplands_figure_data.xlsx
# The workbook holds the data behind the cropland figures of CARB's Natural and Working Lands
# Carbon Inventory (2025), Supplementary Document C. Values are copied, not converted; units
# stay as published (MMT C, acres).
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1, file.exists(args[1]))
xlsx <- args[1]
out <- "reports/data/inventory"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
read <- function(sheet) as.data.frame(readxl::read_excel(xlsx, sheet = sheet))

# Appendix Figure 59: biomass, soil and total cropland carbon stocks by year.
stocks <- read("CL_Fig1")
stopifnot(identical(names(stocks), c("Year", "Land_Type", "Carbon Pool", "MMT C")))
names(stocks) <- c("year", "land_type", "pool", "mmt_c")
# Appendix Figure 66: perennial cropland biomass carbon and area by year and category.
perennial <- read("CL_Fig6")
stopifnot(identical(names(perennial), c("Year", "Category", "Acres", "Total_MMT")))
names(perennial) <- c("year", "category", "acres", "biomass_mmt_c")
# Appendix Figure 65: perennial cropland biomass carbon in 2022 with 95% Monte Carlo intervals.
orchard <- read("CL_Fig5")
stopifnot(identical(names(orchard), c("Orchard", "AverageBiomassC_MMT", "95PercentCI_MMT")))
names(orchard) <- c("category", "biomass_mmt_c", "ci95_half_width_mmt_c")
# Appendix Figure 69: net change in cropland soil carbon stocks by region and period.
soil_change <- read("CL_Fig7")
stopifnot(identical(names(soil_change), c("Region", "LandType", "Period", "SoilC_NetChange_MMT")))
names(soil_change) <- c("region", "land_type", "period", "soil_c_net_change_mmt_c")

write_out <- function(x, name) {
  utils::write.csv(x, file.path(out, name), row.names = FALSE)
}
write_out(stocks, "carb_2025_cropland_stocks.csv")
write_out(perennial, "carb_2025_perennial_biomass_area.csv")
write_out(orchard, "carb_2025_perennial_biomass_2022.csv")
write_out(soil_change, "carb_2025_regional_soil_change.csv")
cat("source sha256:", digest::digest(file = xlsx, algo = "sha256"), "\n")
