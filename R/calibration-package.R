##' @keywords internal
"_PACKAGE"

# column names used non-standardly inside dplyr / ggplot2 verbs; declared so R CMD
# check does not flag them as undefined globals.
utils::globalVariables(c(
  "variable", "sitename", "observation_level", "value", "study_year",
  "treatment_id", "min_date", "max_date", "min_depth", "max_depth",
  "cell_mean", "cell_sd", "n_rep", "var_mean", "var_obs",
  "member", "slot", "q05", "q95", "m", "obs", "obs_sd", "stage",
  "prior_mean", "prior_sd", "post_mean", "post_sd"
))
