library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)

# Build a long table: one row per time x run x constraint_var
build_ens_long <- function(ens_output, meta, constraint_vars) {
  stopifnot(is.list(ens_output))
  stopifnot(all(c("run", "site", "ensemble_member") %in% names(meta)))
  stopifnot(length(constraint_vars) >= 1)
  
  # run ids: prefer names(ens_output); otherwise assume meta$run order matches list order
  run_ids <- names(ens_output)
  if (is.null(run_ids) || all(run_ids == "")) {
    if (nrow(meta) != length(ens_output)) {
      stop("ens_output has no names, and nrow(meta) != length(ens_output). Can't match runs safely.")
    }
    run_ids <- meta$run
  }
  
  # sanity: every run in meta must exist in run_ids
  if (!all(meta$run %in% run_ids)) {
    missing <- setdiff(meta$run, run_ids)
    stop("These meta$run values are not present in ens_output names: ",
         paste(missing, collapse = ", "))
  }
  
  # build per-run dfs and bind
  df <- imap_dfr(ens_output, function(x, nm) {
    # x should be a data.frame with at least posix + constraint_vars
    if (!is.data.frame(x)) stop("Each ens_output[[run]] must be a data.frame. Problem at run: ", nm)
    if (!("posix" %in% names(x))) stop("Missing column 'posix' in run: ", nm)
    if (!all(constraint_vars %in% names(x))) {
      miss <- setdiff(constraint_vars, names(x))
      stop("Missing constraint var(s) in run ", nm, ": ", paste(miss, collapse = ", "))
    }
    
    x %>%
      select(posix, all_of(constraint_vars)) %>%
      mutate(run = nm, .before = 1)
  })
  
  # attach meta and pivot longer for multiple constraint vars
  df_long <- df %>%
    left_join(meta, by = "run") %>%
    pivot_longer(cols = all_of(constraint_vars),
                 names_to = "constraint",
                 values_to = "value") %>%
    mutate(
      ensemble_member = as.factor(ensemble_member),
      site = as.factor(site)
    )
  
  df_long
}

summarise_constraints_time_by_site <- function(df_long, period = c("month", "year")) {
  period <- match.arg(period)
  
  stopifnot(all(c("posix", "site", "ensemble_member", "constraint", "value") %in% names(df_long)))
  
  df2 <- df_long %>%
    mutate(
      year  = as.integer(format(posix, "%Y")),
      month = as.integer(format(posix, "%m")),
      time_bin = if (period == "year") {
        as.character(year)                  # "2012"
      } else {
        paste0(year, "_", month)            # "2012_6"
      }
    ) %>%
    group_by(site, ensemble_member, constraint, time_bin) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    mutate(
      colname = paste0("site_", site, "_", constraint, "_", time_bin)
    ) %>%
    select(ensemble_member, colname, value)
  
  out <- df2 %>%
    pivot_wider(names_from = colname, values_from = value) %>%
    # keep ensemble_member order 1,2,3,... even if stored as factor/character
    mutate(ensemble_member_num = as.integer(as.character(ensemble_member))) %>%
    arrange(ensemble_member_num) %>%
    select(-ensemble_member_num)
  
  out
}
