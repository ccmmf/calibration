##' @keywords internal
"_PACKAGE"

# column names used non-standardly inside dplyr / ggplot2 verbs; declared so R CMD
# check does not flag them as undefined globals.
utils::globalVariables(c(
  "variable", "sitename", "observation_level", "value", "obs_year",
  "treatment_id", "min_date", "max_date", "min_depth", "max_depth",
  "cell", "cell_period", "reported_se", "reported_units",
  "target_variable", "target_units", "variance_model",
  "obs_date_start", "obs_date_end", "var_obs", "cell_mean", "n_rep",
  "member", "slot", "q05", "q95", "m", "obs", "obs_sd", "stage",
  "step", "lo", "hi", "bound", "label", "year", "form",
  "prior_mean", "prior_sd", "post_mean", "post_sd"
))
