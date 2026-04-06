get_run_list <- function(setting_temp) {
  if (is.null(setting_temp$run) || !is.list(setting_temp$run)) {
    stop("Expected `setting_temp$run` to be a list. Please check the object structure.")
  }
  setting_temp$run
}

find_set_id <- function(setting_temp, site_id) {
  run_list <- get_run_list(setting_temp)
  
  hits <- vapply(run_list, function(s) {
    sid <- tryCatch(s$site$id, error = function(e) NA)
    identical(as.character(sid), as.character(site_id))
  }, logical(1))
  
  idx <- which(hits)
  
  if (length(idx) == 0) return(NULL)
  
  if (length(idx) > 1) {
    stop(sprintf(
      "Non-unique match: site_id=%s matched %d settings under `setting_temp$run`: %s",
      as.character(site_id), length(idx), paste(names(run_list)[idx], collapse = ", ")
    ))
  }
  
  run_list[[idx]]
}

find_set_latlon <- function(setting_temp, lat, lon, tol = 0.5) {
  run_list <- get_run_list(setting_temp)
  
  latv <- vapply(run_list, function(s) suppressWarnings(as.numeric(s$site$lat)), numeric(1))
  lonv <- vapply(run_list, function(s) suppressWarnings(as.numeric(s$site$lon)), numeric(1))
  
  ok <- is.finite(latv) & is.finite(lonv)
  if (!any(ok)) stop("No finite site$lat/site$lon found under `setting_temp$run`.")
  
  hits <- ok & (abs(latv - lat) <= tol) & (abs(lonv - lon) <= tol)
  idx <- which(hits)
  
  if (length(idx) == 0) return(NULL)
  
  if (length(idx) > 1) {
    stop(sprintf(
      "Non-unique match: (lat,lon)=(%.8f, %.8f) with tol=%g matched %d settings: %s",
      lat, lon, tol, length(idx), paste(names(run_list)[idx], collapse = ", ")
    ))
  }
  
  run_list[[idx]]
}

# helper: normalize a path field that might be
# - list of lists with $path
# - list of character
# - plain character vector
.as_path_vec <- function(x) {
  if (is.null(x)) return(character(0))
  
  if (is.character(x)) return(x)
  
  if (is.list(x)) {
    if (all(vapply(x, function(e) is.list(e) && !is.null(e$path), logical(1)))) {
      return(vapply(x, function(e) as.character(e$path)[1], character(1)))
    }
    if (all(vapply(x, is.character, logical(1)))) {
      return(unlist(x, use.names = FALSE))
    }
  }
  
  stop("Unsupported path container type; expected character, list-of-$path, or list-of-character.")
}

# MET paths
get_met_path_by_ens <- function(s, ens, check_exists = TRUE) {
  paths <- .as_path_vec(s$inputs$met$path)
  if (length(paths) == 0)
    stop("No met paths found at `s$inputs$met$path`.")
  
  ens <- as.character(ens)
  
  ens_id <- sub("^.*ERA5\\.(\\d+)\\..*$", "\\1", paths)
  ok <- grepl("ERA5\\.(\\d+)\\.", paths) & !is.na(ens_id)
  
  hits <- which(ok & (ens_id == ens))
  
  if (length(hits) == 0) {
    available <- sort(unique(ens_id[ok]))
    stop(sprintf(
      "met ensemble member %s not found. Available ensemble members: %s",
      ens, paste(available, collapse = ", ")
    ))
  }
  if (length(hits) > 1) {
    stop(sprintf(
      "met ensemble member %s matched %d paths (ambiguous).",
      ens, length(hits)
    ))
  }
  
  path <- paths[hits]
  
  if (check_exists && !file.exists(path)) {
    stop(sprintf(
      "met file for ensemble member %s does not exist on disk:\n  %s",
      ens, path
    ))
  }
  
  path
}

# IC paths
get_ic_path_by_ens <- function(s, ens, check_exists = TRUE) {
  paths <- .as_path_vec(s$inputs$poolinitcond$path)
  if (length(paths) == 0)
    stop("No IC paths found at `s$inputs$poolinitcond$path`.")
  
  ens <- as.character(ens)
  
  ens_id <- sub("^.*_([0-9]+)\\.nc$", "\\1", paths)
  ok <- grepl("_([0-9]+)\\.nc$", paths) & !is.na(ens_id)
  
  hits <- which(ok & (ens_id == ens))
  
  if (length(hits) == 0) {
    available <- sort(unique(ens_id[ok]))
    stop(sprintf(
      "IC ensemble member %s not found. Available ensemble members: %s",
      ens, paste(available, collapse = ", ")
    ))
  }
  if (length(hits) > 1) {
    stop(sprintf(
      "IC ensemble member %s matched %d paths (ambiguous).",
      ens, length(hits)
    ))
  }
  
  path <- paths[hits]
  
  if (check_exists && !file.exists(path)) {
    stop(sprintf(
      "IC file for ensemble member %s does not exist on disk:\n  %s",
      ens, path
    ))
  }
  
  path
}

# soil physics

get_soil_path_by_ens <- function(s, ens, check_exists = TRUE) {
  paths <- .as_path_vec(s$inputs$soil_physics$path)
  if (length(paths) == 0)
    stop("No soil physics paths found at `s$inputs$soil_physics$path`.")
  
  ens <- as.character(ens)
  
  ens_id <- sub("^.*_([0-9]+)\\.nc$", "\\1", paths)
  ok <- grepl("_([0-9]+)\\.nc$", paths) & !is.na(ens_id)
  
  hits <- which(ok & (ens_id == ens))
  
  if (length(hits) == 0) {
    available <- sort(unique(ens_id[ok]))
    stop(sprintf(
      "soil physics ensemble member %s not found. Available ensemble members: %s",
      ens, paste(available, collapse = ", ")
    ))
  }
  if (length(hits) > 1) {
    stop(sprintf(
      "soil physics ensemble member %s matched %d paths (ambiguous).",
      ens, length(hits)
    ))
  }
  
  path <- paths[hits]
  
  if (check_exists && !file.exists(path)) {
    stop(sprintf(
      "soil physics file for ensemble member %s does not exist on disk:\n  %s",
      ens, path
    ))
  }
  
  path
}

# func
build_site_inputs <- function(setting_temp, site_ids, ens,
                              check_exists = TRUE,
                              keep_site_settings = FALSE) {
  site_ids <- as.character(site_ids)
  
  settings_list <- setNames(vector("list", length(site_ids)), site_ids)
  
  for (i in seq_along(site_ids)) {
    sid <- site_ids[i]
    s <- find_set_id(setting_temp, sid)
    if (is.null(s)) stop(sprintf("Site id not found in `setting_temp$run`: %s", sid))
    settings_list[[i]] <- s
  }
  
  site_vals <- setNames(vector("list", length(site_ids)), site_ids)
  met_vals  <- setNames(vector("list", length(site_ids)), site_ids)
  ic_vals   <- setNames(vector("list", length(site_ids)), site_ids)
  soil_vals <- setNames(vector("list", length(site_ids)), site_ids)
  
  for (i in seq_along(site_ids)) {
    sid <- site_ids[i]
    s   <- settings_list[[i]]
    
    site_vals[[i]] <- s$site
    met_vals[[i]]  <- get_met_path_by_ens(s, ens, check_exists = check_exists)
    ic_vals[[i]]   <- get_ic_path_by_ens(s, ens, check_exists = check_exists)
    soil_vals[[i]] <- get_soil_path_by_ens(s, ens, check_exists = check_exists)
  }
  
  out <- list(site_vals = site_vals, met_vals  = met_vals,
              ic_vals   = ic_vals, soil_vals = soil_vals)
  
  if (keep_site_settings) out$settings <- settings_list
  out
}