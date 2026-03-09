
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

###### AGB ######
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.mean.Rdata")
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.cov.Rdata")

# one site
agb_vals <- get_obs(obs.mean, "1000004944", "AbvGrndWood")
lai_var <- get_cov(obs.mean, obs.cov, site_id = "1000004944", varname = "AbvGrndWood")


