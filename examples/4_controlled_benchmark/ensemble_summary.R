# Report-local aggregation of coherent paired members, not an inference engine.
# Each member must contain the same named locations within a comparison group.
summarize_paired_ensemble <- function(x, expected_direction = c("increase", "decrease")) {
  expected_direction <- match.arg(expected_direction)
  required <- c("comparison", "group", "site_id", "member_id", "effect")
  if (!all(required %in% names(x))) stop("Missing ensemble columns")
  if (nrow(x) == 0L || anyNA(x[required[-5]]) ||
      any(vapply(x[required[-5]], function(z) any(!nzchar(as.character(z))), logical(1)))) {
    stop("Missing ensemble identities")
  }
  if (any(!is.finite(x$effect))) stop("Nonfinite effects must be resolved before aggregation")
  if (anyDuplicated(x[required[-5]])) stop("Duplicate site-member effect")
  by_group <- split(x, interaction(x$comparison, x$group, drop = TRUE))
  identities <- lapply(by_group, function(g) sort(unique(as.character(g$member_id))))
  if (!all(vapply(identities, identical, logical(1), identities[[1]]))) {
    stop("Comparison groups contain different member identities")
  }
  do.call(rbind, lapply(by_group, function(g) {
    members <- split(g, g$member_id)
    locations <- lapply(members, function(m) sort(as.character(m$site_id)))
    if (!all(vapply(locations, identical, logical(1), locations[[1]]))) {
      stop("Members contain different location sets")
    }
    d <- vapply(members, function(m) mean(m$effect), numeric(1))
    bounds <- stats::quantile(d, c(0.05, 0.5, 0.95), names = FALSE)
    data.frame(comparison = g$comparison[1], group = g$group[1],
      locations = length(locations[[1]]), members = length(d),
      lower90 = bounds[1], median = bounds[2], upper90 = bounds[3],
      fraction_increase = mean(d > 0), fraction_decrease = mean(d < 0),
      fraction_zero = mean(d == 0),
      fraction_expected_direction = if (expected_direction == "increase") mean(d > 0) else mean(d < 0))
  }))
}
