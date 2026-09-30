# Reuse the installed PEcAn converter for successful evaluation runs only.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2)
tasks <- jsonlite::fromJSON(file.path(args[1], "tasks.json"), simplifyVector = FALSE)
sites <- utils::read.csv(args[2], colClasses = c(site_id = "character"))
versions <- c(paste("R", getRversion()),
  "modules: R/4.4.3 udunits/2.2.28 gdal/3.10.2",
  paste("PEcAn.SIPNET", utils::packageVersion("PEcAn.SIPNET")),
  find.package("PEcAn.SIPNET"),
  paste("converter source md5", tools::md5sum(system.file("R", "PEcAn.SIPNET.rdb", package = "PEcAn.SIPNET"))))
writeLines(versions, file.path(args[1], "converter_provenance.txt"))
checks <- list()
for (task in tasks) {
  location <- sites[sites$site_id == task$site_id, ]
  stopifnot(nrow(location) == 1)
  for (variant in task$variants) {
    directory <- file.path(task$path, variant)
    # This installed converter skips a metadata line; SIPNET 2.2 emits the header
    # first. Supply a derived compatibility input without modifying raw output.
    prefix <- "sipnet.pecan-input"
    adapted <- file.path(directory, prefix)
    writeLines("# SIPNET raw output; metadata line for PEcAn 1.9.1", adapted)
    stopifnot(file.append(adapted, file.path(directory, "sipnet.out")))
    PEcAn.SIPNET::model2netcdf.SIPNET(outdir = directory,
      sitelat = location$lat, sitelon = location$lon,
      start_date = "2016-01-01", end_date = "2023-12-31",
      delete.raw = FALSE, revision = "2.2.0", prefix = prefix)
    unlink(adapted)
    raw <- utils::read.table(file.path(directory, "sipnet.out"), header = TRUE)
    for (year in 2016:2023) {
      nc <- ncdf4::nc_open(file.path(directory, paste0(year, ".nc")))
      soil <- ncdf4::ncvar_get(nc, "TotSoilCarb") - ncdf4::ncvar_get(nc, "litter_carbon_content")
      # raw C pools g/m2; netCDF pools kg/m2.
      difference <- abs(tail(as.numeric(soil), 1)*1000 - tail(raw$soil[raw$year == year], 1))
      # GPP is a per-step raw flux, converted to kg C/m2/s.
      gpp_difference <- abs(sum(ncdf4::ncvar_get(nc, "GPP"))*10800*1000 -
        sum(raw$gpp[raw$year == year]))
      ncdf4::nc_close(nc)
      stopifnot(difference < 0.02, gpp_difference < 0.001)
      checks[[length(checks)+1]] <- data.frame(site_id = task$site_id,
        prep_years = task$prep_years, variant = variant, year = year,
        soil_conversion_difference_g_m2 = difference,
        gpp_conversion_difference_g_m2 = gpp_difference)
    }
  }
}
utils::write.csv(do.call(rbind, checks), file.path(args[1], "summary/conversion_checks.csv"), row.names = FALSE)
