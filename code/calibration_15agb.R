library(PEcAn.settings)
library(PEcAn.workflow)
library(PEcAn.logger)
library(PEcAn.utils)
library(PEcAn.remote)
library(PEcAn.uncertainty)
library(dplyr)
library(assertthat)
library(purrr)
library(tidyr)

base_dir <- "/projectnb/dietzelab/menglai/pecan_calibration"
code_dir <- paste0(base_dir, "/scripts")
api_dir <- file.path(code_dir, "api/R")
fwd_dir <- file.path(api_dir, "forward_model")

source(file.path(api_dir, "utils.r"))
source(file.path(api_dir, "types.r"))
source(file.path(api_dir, "batched_array.r"))
source(file.path(fwd_dir, "broadcast_rules.r"))
source(file.path(fwd_dir, "model_input.r"))
source(file.path(fwd_dir, "pecan_model_input.r"))
source(file.path(fwd_dir, "run_model_api.r"))
source(file.path(fwd_dir, "run_pecan_model_api.r"))
source(file.path(fwd_dir, "forward_model_generators.r"))
source(file.path(fwd_dir, "ensemble_input.r"))
source(file.path(fwd_dir, "ensemble_input_list.r"))
source(file.path(fwd_dir, "ensemble_input_table.r"))
source(file.path(fwd_dir, "ensemble_input_broadcast.r"))

source(paste0(code_dir,"/dist_map.r"))
source(paste0(code_dir,"/extract_xml.r"))
source(paste0(code_dir,"/obs_helper.r"))
source(paste0(code_dir,"/eki.r"))
source(paste0(code_dir,"/workflow_edits.r"))
source(paste0(code_dir,"/sipnet_config_temp_hack.r"))


# source("/projectnb/dietzelab/menglai/sipnet/tutorial/sipnet_calibration/runs/sipnet_calibration_2024/scripts/prob_dists.r")
# source("/projectnb/dietzelab/menglai/sipnet/tutorial/sipnet_calibration/runs/sipnet_calibration_2024/scripts/param_calibration_functions.r")
# src_dir <- file.path("/projectnb", "dietzelab", "arober", "gp-calibration", "src")
# source(file.path(src_dir, "general_helper_functions.r"))
# source("/projectnb/dietzelab/menglai/pecan_calibration/tests/multi_eki/mulsite_ens_helper.r")

# <site>
# <id>1000004945</id>
# <met.start>2012/01/01</met.start>
# <met.end>2021/12/31</met.end>
# <lat>42.52917</lat>
# <lon>-72.1875</lon>
# <name>Harvard Forest</name>
# <site>
# 
# <site>
# <id>1000004924</id>
# <met.start>2012/01/01</met.start>
# <met.end>2021/12/31</met.end>
# <lat>44.06388</lat>
# <lon>-71.28731</lon>
# <name>Bartlett Experimental Forest (NEON-D01-BART)</name>
# </site>
# site_ids <- c("1000004945", "1000004924")

pft_mix <- read.csv("/projectnb/dietzelab/menglai/pecan_calibration/tests/mpj/files/pft_mix15.csv")
site_ids <- as.character(pft_mix$site)[1:2]

set.seed(556688)
constraint_vars <- c("AbvGrndWood")
#----- constraint data
# load("/projectnb/dietzelab/dongchen/All_NEON_SDA/test_OBS/NEON39_obs/obs.mean.Rdata")
# load("/projectnb/dietzelab/dongchen/All_NEON_SDA/test_OBS/NEON39_obs/obs.cov.Rdata")
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.mean.Rdata")
load("/projectnb/dietzelab/dongchen/NEON_SDA_Files/obs.cov.Rdata")

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
get_stacked <- function(obs.mean, obs.cov, site_ids, varname) {
  # use only dates present in both lists (so mean/var align)
  dates <- intersect(names(obs.mean), names(obs.cov))
  year  <- format(as.Date(dates), "%Y")
  month <- as.integer(format(as.Date(dates), "%m"))
  
  mean_list <- vector("list", length(site_ids))
  var_list  <- vector("list", length(site_ids))
  
  for (i in seq_along(site_ids)) {
    sid <- site_ids[i]
    
    m <- get_obs(obs.mean, sid, varname)[dates]
    v <- get_cov(obs.mean, obs.cov, sid, varname)[dates]  # this is already diagonal element
    
    nm <- paste0("site_", i, "_", varname, "_", year, "_", month)
    names(m) <- nm
    names(v) <- nm
    
    mean_list[[i]] <- m
    var_list[[i]]  <- v
  }
  
  list(
    mean = unlist(mean_list, use.names = TRUE),
    var  = unlist(var_list,  use.names = TRUE)
  )
}
res <- get_stacked(obs.mean, obs.cov, site_ids, "AbvGrndWood")

# abg_vec_mgha <- res$mean[!is.na(res$mean)]
# abg_vec <- PEcAn.utils::ud_convert(abg_vec_mgha,  "Mg/ha", "g/m^2")
# abg_vec <- abg_vec_mgha*1000
abg_vec <- res$mean[!is.na(res$mean)]
obs_order <- names(abg_vec)
Sigma <- res$var[obs_order]

# ---- ic prior
extract_year <- function(x, year) {
  year <- as.character(year)
  x[grepl(paste0("_", year, "_"), names(x))]
}

extract_year(abg_vec, 2012)
# > extract_year(abg_vec, 2012)
# site_1_AbvGrndWood_2012_7 site_2_AbvGrndWood_2012_7 
# 197                       153 

#----- setting template

# source("/projectnb/dietzelab/menglai/pecan_calibration/tests/mpj/scripts/extract_xml.r")
# settings_path <- "/projectnb/dietzelab/dongchen/anchorSites/NA_runs/SDA_8k_site/shashank/pecan.xml"
settings_path <- paste0(base_dir,"/reference/pecan.xml")
# settings_path <- "/projectnb/dietzelab/menglai/pecan_calibration/templates/pecan.xml"
multisettings <- PEcAn.settings::read.settings(settings_path)
settings_samp <- multisettings[[1]]

base_out_dir <- paste0(base_dir,"/output/test/")

settings_list <- list(
  
  outdir = file.path(base_out_dir),
  modeloutdir = file.path(base_out_dir, "out"),
  rundir = file.path(base_out_dir, "run"),
  
  host = list(name="localhost"),
  
  pfts = settings_samp$pfts,
  
  model = settings_samp$model,
  
  settings.info = settings_samp$settings.info,
  
  run = settings_samp$run
)

settings <- PEcAn.settings::as.Settings(settings_list)



#----- loading prior ens
prior_list <- readRDS("/projectnb/dietzelab/menglai/pecan_calibration/tests/ic/prior_list_WITHic.rds")

num_site <- length(site_ids)
# pecan_ic_names <- c("abvGrndWoodFrac", "coarseRootFrac", "fineRootFrac", 
#                     "AbvGrndWood", "soil", "wood_frac_pars")
pecan_ic_names <- c("wood_frac_pars") # "abvGrndWoodFrac", "coarseRootFrac", "fineRootFrac"

samp_prior_list <- c(
  unlist(lapply(names(prior_list), function(name) {
    if (name %in% pecan_ic_names) {
      rep_items <- lapply(seq_len(num_site), function(i) {
        new_item <- prior_list[[name]]
        if ("param_name" %in% names(new_item)) {
          #print(1)
          new_item$param_name <- paste("site", i, new_item$param_name, sep = "_")  
        } 
        if ("scalar_names" %in% names(new_item)){
          new_item$scalar_names <- paste("site", i, new_item$scalar_names, sep = "_")
        }
        new_item
      })
      setNames(rep_items, paste0(name, "_site", seq_len(num_site)))
    } else {
      setNames(list(prior_list[[name]]), name)
    }
  }), recursive = FALSE)
)

samp_prior_list$wueConst <- list(
  param_name = "wueConst",
  dist_name = "Normal",
  constraint = c(1, 50),
  length = 1L,
  dist_params = list(mean = 13, sd = 5)
)

wood_2012_names <- grep("_AbvGrndWood_2012_7$", names(abg_vec), value = TRUE)

new_priors <- setNames(
  lapply(wood_2012_names, function(nm) {
    param_base <- sub("_2012_7$", "", nm)
    
    list(
      param_name = param_base,
      dist_name = "Normal",
      constraint = c(0, Inf),
      length = 1L,
      dist_params = list(
        mean = unname(abg_vec[nm]),
        sd   = unname(sqrt(Sigma[nm]))
      )
    )
  }),
  sub("_2012_7$", "", wood_2012_names)
)

# append into existing list
samp_prior_list[names(new_priors)] <- new_priors

rprior <- get_sampling_func(samp_prior_list)

par_maps <- get_par_map_funcs(samp_prior_list)
# rprior <- get_sampling_func(prior_list)
size <- 5
U <- rprior(as.integer(size))
# U <- U[rep(1, nrow(U)), , drop = FALSE]
# U[U < 0] <- 0
U[U < 0] <- -U[U < 0]

#----- ens rule

# trait_values_ens <- as.matrix(U)

res <- build_site_inputs(multisettings, site_ids, ens = 10)
site_vals <- res$site_vals
met_vals  <- res$met_vals
ic_vals   <- res$ic_vals
soil_vals <- res$soil_vals

site_key  <- "settings/run/site"
ic_key    <- "settings/run/inputs/poolinitcond/path"
met_key   <- "settings/run/inputs/met/path"
soil_key <- "settings/run/inputs/soil_physics/path"
trait_key <- "config/trait.values"  # keep as the only identity slot

broadcast_rule <- list(recycle  = c(site_key, ic_key, met_key, soil_key),
                       identity = trait_key)

#----- obs
# obs_order <- names(lai_vec)
y_obs <- abg_vec

# Sigma <- rep(0.6, length(y_obs))
Sig <- diag(Sigma)
colnames(Sig) <- rownames(Sig) <- names(Sigma)


#------ run eki
# outp <- "/projectnb/dietzelab/menglai/pecan_calibration/tests/ic/files/"
# G_init <- fwd(U,1)

base_out_dir <- paste0(base_dir,"/output/init/")
G_init <- fwd(U,1)

base_out_dir <- paste0(base_dir,"/output/total1")
eki1_lst <- run_eki(y=y_obs, fwd=fwd, Sig=Sig, n_itr=1, U=U, par_map=par_maps, G0=G_init)
saveRDS(eki1_lst, file = paste0(outp, "eki15_itr1_en50_agb.rds"))












