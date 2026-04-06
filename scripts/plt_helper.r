library(dplyr)
library(tidyr)
library(stringr)

ensemble_wide_to_long <- function(ens_wide) {
  ens_wide %>%
    tibble::as_tibble() %>%
    mutate(member = row_number()) %>%   # ensemble id
    pivot_longer(
      cols = -member,
      names_to = "name",
      values_to = "value"
    ) %>%
    extract(
      col = name,
      into = c("site", "var", "year", "month"),
      regex = "^(.*)_([^_]+)_(\\d{4})_(\\d{1,2})$",
      remove = FALSE
    ) %>%
    filter(!is.na(year)) %>%
    mutate(
      year  = as.integer(year),
      month = as.integer(month),
      time  = as.Date(sprintf("%d-%02d-01", year, month))
    )
}
library(ggplot2)

plot_site_variable <- function(ens_long, truth, site_id, var_name, 
                               truth_site_col = "site",
                               truth_year_col = "year",
                               truth_month_col = "month",
                               truth_value_col = NULL, ylims = NULL) {
  
  if (is.null(truth_value_col)) truth_value_col <- var_name
  
  ens_sub <- ens_long %>%
    filter(site == site_id, var == var_name) %>%
    arrange(member, time)
  
  truth_sub <- truth %>%
    filter(.data[[truth_site_col]] == site_id) %>%
    mutate(time = as.Date(sprintf("%d-%02d-01",
                                  .data[[truth_year_col]],
                                  .data[[truth_month_col]]))) %>%
    arrange(time)
  
  ggplot() +
    geom_line(
      data = ens_sub,
      aes(x = time, y = value, group = member, color = factor(member)),
      alpha = 0.8,
      linewidth = 0.7,
      show.legend = FALSE
    ) +
    geom_line(
      data = truth_sub,
      aes(x = time, y = .data[[truth_value_col]]),
      color = "black",
      linewidth = 1.2
    ) +
    labs(
      title = paste(site_id, "—", var_name),
      x = "Time", y = var_name
    ) +
    theme_minimal() +
    if (!is.null(ylims)) coord_cartesian(ylim = ylims)
}
# ens_long <- ensemble_wide_to_long(itr1)
# 
# p1 <- plot_site_variable(ens_long, lai_df, site_id = "site_1", var_name = "LAI")
# print(p1)
# # 
# plots <- plot_all_sites_for_var(ens_wide, truth, "LAI")
# plots[["site_1"]]
plot_all_sites_for_var <- function(ens_wide, truth, var_name) {
  ens_long <- ensemble_wide_to_long(ens_wide)
  sites <- ens_long %>% filter(var == var_name) %>% distinct(site) %>% pull(site)
  
  plots <- setNames(vector("list", length(sites)), sites)
  for (s in sites) {
    plots[[s]] <- plot_site_variable(ens_long, truth, site_id = s, var_name = var_name, ylims = ylims)
  }
  plots
}

save_sites_to_pdf <- function(
    ens_wide,
    truth,
    var_name,
    pdf_file = "ensemble_vs_truth.pdf",
    width = 8,
    height = 4
) {
  # build plots
  plots <- plot_all_sites_for_var(ens_wide, truth, var_name)
  
  # open pdf device
  pdf(pdf_file, width = width, height = height)
  
  # each plot becomes a page
  for (p in plots) {
    print(p)
  }
  
  dev.off()
}
