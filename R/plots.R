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
    dplyr::left_join(dplyr::distinct(meta, slot, treatment_id, obs_year),
                     by = "slot")
}

##' observation table for plotting (mean and sd band from the cell variance).
##' @keywords internal
obs_long <- function(meta) {
  dplyr::transmute(meta, treatment_id, obs_year, obs = value,
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
    dplyr::summarize(q05 = stats::quantile(value, 0.05),
                     q95 = stats::quantile(value, 0.95),
                     m = mean(value),
                     .by = c(treatment_id, obs_year))
  ol <- obs_long(meta)
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = band,
      ggplot2::aes(obs_year, ymin = q05, ymax = q95),
      fill = "grey75", alpha = 0.55) +
    ggplot2::geom_line(data = el,
      ggplot2::aes(obs_year, value, group = member),
      color = "steelblue", alpha = 0.35, linewidth = 0.3) +
    ggplot2::geom_line(data = band, ggplot2::aes(obs_year, m), linewidth = 0.7) +
    ggplot2::geom_pointrange(data = ol,
      ggplot2::aes(obs_year, obs, ymin = obs - obs_sd, ymax = obs + obs_sd),
      color = "firebrick", linewidth = 0.3, size = 0.25) +
    ggplot2::facet_wrap(~treatment_id, ncol = 2) +
    ggplot2::labs(x = "year", y = ylab, title = title) +
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
        # no page title: the x label already names the parameter and its unit, and a
        # title that repeats the axis is noise
        ggplot2::labs(x = param_label_unit(p), y = "density", color = NULL) +
        ggplot2::theme_minimal(base_size = 12)
    )
  }
  invisible(pdf_file)
}

##' axis and strip labels for calibrated parameters; unmapped names fall back to
##' the trait name with underscores as spaces.
##' @keywords internal
param_label <- function(x) {
  labels <- c(
    som_respiration_rate  = "SOM respiration rate",
    fracLitterRespired    = "Litter fraction respired",
    n_volatilization_rate = "N volatilization rate",
    soil_respiration_Q10  = "Soil respiration Q10",
    litterBreakdownRate   = "Litter breakdown rate"
  )
  trait <- sub("^[^.]+\\.", "", x)
  out <- labels[trait]
  fallback <- is.na(out)
  out[fallback] <- gsub("_", " ", trait[fallback])
  unname(out)
}

##' units as SIPNET reads them, not always as documented: baseSoilResp is read in
##' per year and divided by 365 at setup in sipnet.c, so a calibrated value is a
##' per year rate; wrong on an axis is a factor of 365.
##' @keywords internal
param_unit <- function(x) {
  units <- c(
    som_respiration_rate  = "g C g-1 soil C yr-1",
    fracLitterRespired    = "unitless",
    n_volatilization_rate = "unitless",
    soil_respiration_Q10  = "unitless",
    litterBreakdownRate   = "yr-1"
  )
  trait <- sub("^[^.]+\\.", "", x)
  out <- units[trait]
  out[is.na(out)] <- ""
  unname(out)
}

##' parameter label with its unit appended, for a facet strip or page label.
##' @keywords internal
param_label_unit <- function(x) {
  u <- param_unit(x)
  lab <- param_label(x)
  ifelse(nzchar(u) & u != "unitless", paste0(lab, " (", u, ")"), lab)
}

##' @title Parameter trace across tempering steps
##' @author Akash BV
##'
##' @description Ensemble mean and 5-95 % spread of each calibrated parameter at the
##'   prior and after each tempering step, with its declared support drawn in where
##'   finite. Shows whether a parameter settles inside its support or moves onto a
##'   bound, and whether it walks there or jumps.
##'
##' @param trace named list of parameter matrices, prior first then one per step.
##' @param prior the dist_list the run used, for the support lines.
##' @return a ggplot object.
##' @export
plot_param_trace <- function(trace, prior = NULL) {
  long <- dplyr::bind_rows(lapply(seq_along(trace), function(i) {
    U <- trace[[i]]
    dplyr::bind_rows(lapply(colnames(U), function(k) {
      tibble::tibble(step = i - 1L, param = k,
                     m = mean(U[, k]),
                     lo = stats::quantile(U[, k], 0.05),
                     hi = stats::quantile(U[, k], 0.95))
    }))
  }))
  long$label <- param_label_unit(long$param)

  bounds <- NULL
  if (!is.null(prior)) {
    bounds <- dplyr::bind_rows(lapply(names(prior), function(k) {
      lim <- prior[[k]]$constraint
      tibble::tibble(param = k, label = param_label_unit(k), bound = lim[is.finite(lim)])
    }))
  }

  p <- ggplot2::ggplot(long, ggplot2::aes(step, m))
  if (!is.null(bounds) && nrow(bounds) > 0) {
    p <- p + ggplot2::geom_hline(data = bounds,
      ggplot2::aes(yintercept = bound), color = "grey70", linetype = 2)
  }
  p +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo, ymax = hi), fill = "grey75", alpha = 0.55) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~label, scales = "free_y",
                        labeller = ggplot2::label_wrap_gen(26)) +
    ggplot2::labs(x = "tempering step", y = "value") +
    ggplot2::theme_minimal(base_size = 11)
}

##' @title Held-out validation: predicted against observed
##' @author Akash BV
##'
##' @description Ensemble mean prediction against the observation for slots kept out
##'   of the likelihood, with the 5-95 % ensemble range and a 1:1 line.
##'
##'   Panels are on free scales: variables held out together can span very different
##'   ranges, and a shared scale would flatten the smaller one.
##'
##' @param G prediction matrix covering the validation slots.
##' @param meta observation meta for those slots, carrying `value` and `units`.
##' @return a ggplot object.
##' @export
plot_validation <- function(G, meta) {
  G <- G[, meta$slot, drop = FALSE]
  d <- tibble::tibble(
    variable = meta$variable,
    obs = meta$value,
    m = colMeans(G),
    lo = apply(G, 2, stats::quantile, 0.05),
    hi = apply(G, 2, stats::quantile, 0.95)
  )
  d$label <- label_variable(d$variable)
  # the axis unit comes from the observations the model output was converted onto;
  # slots spanning more than one unit cannot share an axis pair
  unit <- unique(meta$units)
  if (length(unit) != 1L) {
    PEcAn.logger::logger.severe(
      "validation slots span more than one unit: ", paste(unit, collapse = ", ")
    )
  }
  # a log axis silently drops every non-positive point, and a treatment contrast is
  # signed by construction, so the scale follows the data rather than the variable.
  positive <- all(c(d$obs, d$m, d$lo, d$hi) > 0, na.rm = TRUE)
  scales <- if (positive) {
    list(ggplot2::scale_x_log10(), ggplot2::scale_y_log10())
  } else {
    list(ggplot2::geom_hline(yintercept = 0, color = "grey85", linewidth = 0.3),
         ggplot2::geom_vline(xintercept = 0, color = "grey85", linewidth = 0.3))
  }

  ggplot2::ggplot(d, ggplot2::aes(obs, m)) +
    scales +
    ggplot2::geom_abline(slope = 1, intercept = 0, color = "grey70") +
    ggplot2::geom_linerange(ggplot2::aes(ymin = lo, ymax = hi),
                            color = "grey50", linewidth = 0.3) +
    ggplot2::geom_point(color = "firebrick", size = 2) +
    ggplot2::facet_wrap(~label, scales = "free") +
    ggplot2::labs(x = paste0("observed (", unit, ")"),
                  y = paste0("predicted (", unit, ")")) +
    ggplot2::theme_minimal(base_size = 11)
}

##' readable variable label: the variable name with underscores as spaces.
##' @keywords internal
label_variable <- function(x) {
  gsub("_", " ", x)
}

##' @title Fitted target slots against observations
##' @name plot_target_slots
##' @author Akash BV
##'
##' @description A contracted target has no year axis (obs_year is NA by
##'   construction), so its slots go on a categorical axis: member points,
##'   ensemble mean, observation +/- sd.
##'
##' @param G prediction matrix covering the slots in `meta`.
##' @param meta observation meta of the fitted slots.
##' @param ylab y axis label.
##' @param title optional factual page label for a multi page pdf.
##' @return a ggplot object.
##' @export
plot_target_slots <- function(G, meta, ylab = "value", title = NULL) {
  lab <- sub("_vs_", " - ", meta$treatment_id)
  d <- data.frame(
    slot = factor(rep(lab, each = nrow(G)), levels = lab),
    value = as.vector(G[, meta$slot, drop = FALSE])
  )
  m <- data.frame(slot = factor(lab, levels = lab),
                  value = colMeans(G[, meta$slot, drop = FALSE]))
  o <- data.frame(slot = factor(lab, levels = lab), obs = meta$value,
                  obs_sd = sqrt(meta$var_obs))
  ggplot2::ggplot() +
    ggplot2::geom_jitter(data = d, ggplot2::aes(slot, value),
      width = 0.12, height = 0, color = "steelblue", alpha = 0.35, size = 0.8) +
    ggplot2::geom_point(data = m, ggplot2::aes(slot, value), shape = 95, size = 8) +
    ggplot2::geom_pointrange(data = o,
      ggplot2::aes(slot, obs, ymin = obs - obs_sd, ymax = obs + obs_sd),
      color = "firebrick", linewidth = 0.4, size = 0.3) +
    ggplot2::labs(x = NULL, y = ylab, title = title) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1))
}

##' @title Measured against modeled treatment effect, before and after calibration
##' @name plot_treatment_effect
##' @author Akash BV
##'
##' @description Per year treatment minus control from the prior and posterior
##'   forward ensembles against the measured contrast, as the absolute effect and
##'   as percent of control. Bands are the 5-95 % ensemble range around the mean;
##'   measurement bars are one standard deviation, the two arms' variances added
##'   (delta method for the relative form).
##'
##' @param G_prior,G_post prediction matrices on the raw slots (members x slots).
##' @param meta raw observation meta covering the paired slots.
##' @param variable the per treatment per year variable the effect is on.
##' @param treatment,control treatment ids to compare.
##' @return a ggplot object.
##' @export
plot_treatment_effect <- function(G_prior, G_post, meta, variable, treatment, control) {
  sub <- meta[meta$variable == variable &
                meta$treatment_id %in% c(treatment, control), , drop = FALSE]
  yrs <- sort(unique(sub$obs_year))
  slot_of <- function(t, y) sub$slot[sub$treatment_id == t & sub$obs_year == y]
  ok <- vapply(yrs, function(y) {
    length(slot_of(treatment, y)) == 1L && length(slot_of(control, y)) == 1L
  }, logical(1))
  if (length(yrs) == 0L || !all(ok)) {
    PEcAn.logger::logger.severe(
      "treatment effect needs one ", treatment, " and one ", control,
      " slot per year of ", variable, "; unpaired: ",
      paste(yrs[!ok], collapse = ", ")
    )
  }

  summarize_effect <- function(G, stage) {
    dplyr::bind_rows(lapply(yrs, function(y) {
      gt <- G[, slot_of(treatment, y)]
      gc <- G[, slot_of(control, y)]
      eff <- list(absolute = gt - gc, relative = 100 * (gt - gc) / gc)
      tibble::tibble(
        year = y, stage = stage, form = names(eff),
        m  = vapply(eff, mean, numeric(1)),
        lo = vapply(eff, stats::quantile, numeric(1), 0.05),
        hi = vapply(eff, stats::quantile, numeric(1), 0.95)
      )
    }))
  }
  bands <- dplyr::bind_rows(summarize_effect(G_prior, "before calibration"),
                            summarize_effect(G_post, "after calibration"))
  bands$stage <- factor(bands$stage, levels = c("before calibration", "after calibration"))

  mt <- sub[match(paste(treatment, yrs), paste(sub$treatment_id, sub$obs_year)), ]
  mc <- sub[match(paste(control, yrs), paste(sub$treatment_id, sub$obs_year)), ]
  vt <- mt$value
  vc <- mc$value
  obs <- tibble::tibble(
    year = rep(yrs, 2),
    form = rep(c("absolute", "relative"), each = length(yrs)),
    obs = c(vt - vc, 100 * (vt - vc) / vc),
    obs_sd = c(sqrt(mt$var_obs + mc$var_obs),
               100 * sqrt(mt$var_obs / vc^2 + vt^2 * mc$var_obs / vc^4))
  )

  form_labels <- c(absolute = paste0("absolute effect (", unique(sub$units), ")"),
                   relative = "relative effect (% of control)")
  ggplot2::ggplot() +
    ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.3) +
    ggplot2::geom_ribbon(data = bands,
      ggplot2::aes(year, ymin = lo, ymax = hi, fill = stage), alpha = 0.4) +
    ggplot2::geom_line(data = bands, ggplot2::aes(year, m, color = stage),
                       linewidth = 0.7) +
    ggplot2::geom_pointrange(data = obs,
      ggplot2::aes(year, obs, ymin = obs - obs_sd, ymax = obs + obs_sd),
      color = "firebrick", linewidth = 0.4, size = 0.3) +
    ggplot2::scale_fill_manual(values = c("before calibration" = "grey75",
                                          "after calibration" = "steelblue"), name = NULL) +
    ggplot2::scale_color_manual(values = c("before calibration" = "grey40",
                                           "after calibration" = "steelblue4"), name = NULL) +
    ggplot2::facet_wrap(~form, scales = "free_y",
                        labeller = ggplot2::labeller(form = form_labels)) +
    ggplot2::labs(x = "year", y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
}
