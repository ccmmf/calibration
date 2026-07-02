# plots for a calibration run: the per iteration prediction ensemble
# against the observations (member spaghetti, 90% ribbon, obs points), faceted by
# treatment, and the prior/posterior parameter densities. generic over the
# observation slots; the y label (the calibrated variable and its unit) is passed
# by the caller.

##' long form of a prediction matrix joined to the observation meta.
##' @keywords internal
ensemble_long <- function(G, meta) {
  tibble::as_tibble(G, rownames = "member") |>
    dplyr::mutate(member = as.integer(member)) |>
    tidyr::pivot_longer(-member, names_to = "slot", values_to = "value") |>
    dplyr::left_join(dplyr::distinct(meta, slot, treatment_id, study_year),
                     by = "slot")
}

##' observation table for plotting (mean and sd band from the cell variance).
##' @keywords internal
obs_long <- function(meta) {
  dplyr::transmute(meta, treatment_id, study_year, obs = value,
                   obs_sd = sqrt(var_obs))
}

##' @title Ensembles-vs-truth plot for one iteration
##' @name plot_ensembles_vs_truth
##' @author Akash BV
##'
##' @description Member spaghetti, the 90% ensemble ribbon, and the observation
##' points with their uncertainty, faceted by treatment, against study year.
##'
##' @param G the iteration's prediction matrix (members x slots).
##' @param meta observation meta.
##' @param ylab y-axis label (the calibrated variable and its unit).
##' @param title panel title.
##' @return a ggplot object.
##' @export
plot_ensembles_vs_truth <- function(G, meta, ylab = "value", title = NULL) {
  el <- ensemble_long(G, meta)
  band <- el |>
    dplyr::summarise(q05 = stats::quantile(value, 0.05),
                     q95 = stats::quantile(value, 0.95),
                     m = mean(value),
                     .by = c(treatment_id, study_year))
  ol <- obs_long(meta)
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = band,
      ggplot2::aes(study_year, ymin = q05, ymax = q95),
      fill = "grey75", alpha = 0.55) +
    ggplot2::geom_line(data = el,
      ggplot2::aes(study_year, value, group = member),
      color = "steelblue", alpha = 0.35, linewidth = 0.3) +
    ggplot2::geom_line(data = band, ggplot2::aes(study_year, m), linewidth = 0.7) +
    ggplot2::geom_pointrange(data = ol,
      ggplot2::aes(study_year, obs, ymin = obs - obs_sd, ymax = obs + obs_sd),
      color = "firebrick", linewidth = 0.3, size = 0.25) +
    ggplot2::facet_wrap(~treatment_id, ncol = 2) +
    ggplot2::labs(x = "study year", y = ylab, title = title) +
    ggplot2::theme_minimal(base_size = 11)
}

##' @title Save one ensembles vs truth page per iteration to a pdf
##' @name save_iterations_pdf
##' @author Akash BV
##' @param G_list named list of prediction matrices, one per iteration.
##' @param meta observation meta.
##' @param pdf_file output path.
##' @param ylab y-axis label.
##' @param width,height page size in inches.
##' @return pdf_file, invisibly.
##' @export
save_iterations_pdf <- function(G_list, meta, pdf_file, ylab = "value",
                                width = 9, height = 10) {
  grDevices::pdf(pdf_file, width = width, height = height)
  on.exit(grDevices::dev.off())
  for (nm in names(G_list)) {
    print(plot_ensembles_vs_truth(G_list[[nm]], meta, ylab = ylab, title = nm))
  }
  invisible(pdf_file)
}

##' @title Prior/posterior parameter densities, one parameter per page
##' @name plot_param_densities
##' @author Akash BV
##' @param U_list named list of parameter matrices (e.g. prior, posterior).
##' @param pdf_file output path.
##' @param width,height page size in inches.
##' @return pdf_file, invisibly.
##' @export
plot_param_densities <- function(U_list, pdf_file, width = 7, height = 4) {
  params <- colnames(U_list[[1]])
  grDevices::pdf(pdf_file, width = width, height = height)
  on.exit(grDevices::dev.off())
  for (p in params) {
    df <- dplyr::bind_rows(lapply(names(U_list), function(nm)
      tibble::tibble(stage = nm, value = U_list[[nm]][, p])))
    print(
      ggplot2::ggplot(df, ggplot2::aes(value, color = stage)) +
        ggplot2::geom_density(linewidth = 1) +
        ggplot2::labs(title = p, x = "value", y = "density", color = NULL) +
        ggplot2::theme_minimal(base_size = 12)
    )
  }
  invisible(pdf_file)
}
