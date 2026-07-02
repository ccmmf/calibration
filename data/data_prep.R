
# 8k site info
load("/projectnb/dietzelab/dongchen/anchorSites/NA_runs/SDA_8k_site/site_info.Rdata")
site_info$site_ids[1:5]
site_names <- unique(site_info$site_name)

###### raw LAI extraction ######
lai_dir <- "/projectnb/dietzelab/dongchen/global_LAI/LAI_maps"

# one site
lai_harvard <- extract_lai_one_site(root_dir = lai_dir, lon = -72.1875, lat = 42.52917)

# selected site ids
lai_3 <- extract_lai_sites(root_dir = lai_dir, site_info, site_ids = c(1,3,5))

#or from the xml extracted info site_vals
library(furrr)
library(dplyr)

plan(multisession, workers = 3)

lai_all_sites <- future_map_dfr(site_vals, function(site) {
  lon <- as.numeric(site$lon)
  lat <- as.numeric(site$lat)
  sid <- site$id
  
  df <- extract_lai_one_site(root_dir = lai_dir, lon = lon, lat = lat)
  df %>% mutate(site_id = sid, lon = lon, lat = lat)
})

###### AGB ######
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.mean.Rdata")
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.cov.Rdata")

# one site
agb_vals <- get_obs(obs.mean, "1000004944", "AbvGrndWood")
lai_var <- get_cov(obs.mean, obs.cov, site_id = "1000004944", varname = "AbvGrndWood")

# site ids
site_ids <- as.character(pft$site)
res <- get_stacked(obs.mean, obs.cov, site_ids, "AbvGrndWood")
