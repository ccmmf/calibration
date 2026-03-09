library(terra)
library(dplyr)
library(purrr)

extract_lai_one_site <- function(root_dir, lon, lat) {
  
  years <- list.dirs(root_dir, recursive = FALSE, full.names = TRUE)
  site_pt <- vect(data.frame(x = lon, y = lat), geom = c("x", "y"),
                  crs  = "EPSG:4326")
  out <- list()
  
  for (yd in years) {
    year <- as.integer(basename(yd))
    doy_dirs <- list.dirs(yd, recursive = FALSE, full.names = TRUE)
    
    for (dd in doy_dirs) {
      doy <- as.integer(basename(dd))
      f   <- file.path(dd, "all_bands.tif")
      if (!file.exists(f)) next
      
      r <- rast(f)
      # RS-safe point
      pt <- if (!same.crs(r, site_pt)) {
        print(paste0("mismatch ",dd))
        project(site_pt, crs(r))
      } else {
        site_pt
      }
      
      # Band 1 = LAI
      vals <- terra::extract(r[[1]], pt)
      lai_raw <- vals[[names(vals)[2]]]
      lai <- lai_raw * 0.1
      
      date <- as.Date(doy - 1, origin = paste0(year, "-01-01"))
      
      out[[length(out) + 1]] <- data.frame(year = year, doy  = doy,
                                           date = date, lai  = lai)
    }
  }
  df <- bind_rows(out) %>% arrange(date)
  df
}


extract_lai_sites <- function(root_dir, site_info, site_ids = NULL) {
  # If site_ids is NULL, use all sites
  if (is.null(site_ids)) {
    idx <- seq_along(site_info$site_ids)
  } else {
    idx <- which(site_info$site_ids %in% site_ids)
    
    if (length(idx) == 0) {
      stop("No matching site_ids found in site_info.")
    }
  }
  purrr::map_dfr(idx, function(i) {
    df <- extract_lai_one_site(root_dir = root_dir, lon = site_info$lon[i],
                               lat = site_info$lat[i])
    
    df %>% mutate(site_id = site_info$site_ids[i], site_name = site_info$site_name[i],
                  lon = site_info$lon[i], lat = site_info$lat[i]) %>%
           select(site_id, site_name, lon, lat, everything())})
}

get_obs <- function(obs.mean, site_id, varname) {
  dates <- names(obs.mean)
  sapply(dates, function(dt) {
    site_entry <- obs.mean[[dt]][[site_id]]
    if (is.null(site_entry) || !(varname %in% names(site_entry))) {
      return(NA_real_)   
    }
    as.numeric(site_entry[[varname]])
  })
}

get_cov <- function(obs.mean, obs.cov, site_id, varname) {
  dates <- intersect(names(obs.mean), names(obs.cov))
  sapply(dates, function(dt) {
    site_mean <- obs.mean[[dt]][[site_id]]
    site_cov  <- obs.cov[[dt]][[site_id]]
    if (is.null(site_mean) || is.null(site_cov)) return(NA_real_)
    
    idx <- match(varname, names(site_mean))
    if (is.na(idx) || idx > nrow(site_cov)) {
      return(NA_real_)
    }
    site_cov[idx, idx]
  })
}



















