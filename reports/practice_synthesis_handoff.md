# Management-practice comparisons: handoff for Aritra

Prepared 2026-10-04. Continue the model-versus-synthesis comparisons using the
existing frozen outputs before proposing further simulations. This is a focused
follow-up to [organization #164](https://github.com/ccmmf/organization/issues/164),
not another evidence audit or a replacement for site-level validation.

## Start here

- [Calibration PR #8](https://github.com/ccmmf/calibration/pull/8) is open,
  unmerged, at `86ddeecca42a3db9749d56ae8ff7248587a2ee2b`.
  [Statewide report](https://github.com/ccmmf/calibration/blob/86ddeecca42a3db9749d56ae8ff7248587a2ee2b/reports/statewide_effects.qmd),
  [generator](https://github.com/ccmmf/calibration/blob/86ddeecca42a3db9749d56ae8ff7248587a2ee2b/reports/R/build_statewide_report.R),
  and [manifest](https://github.com/ccmmf/calibration/blob/86ddeecca42a3db9749d56ae8ff7248587a2ee2b/reports/data/statewide/manifest.json)
  already contain the reusable statewide work. Do not copy it into a second pipeline.
- [Cal-val-data PR #13](https://github.com/ccmmf/cal-val-data/pull/13) is open,
  unmerged, at `738a2544a6616d65395c76cef16db862d7006b3a`.
  Its [evidence report](https://github.com/ccmmf/cal-val-data/blob/738a2544a6616d65395c76cef16db862d7006b3a/reports/statewide-evidence.qmd)
  supplies Aritra's explanation of the curated targets and uncertainty.
  The evidence itself is already committed on develop through PR #9/#12;
  the frozen model report pins `b5f65bb7fce5bbd3476bf6d34cd380990a1167d2`.
- [Organization #279](https://github.com/ccmmf/organization/issues/279) reports
  the earlier 61-site cover-only comparison (+0.11 Mg C/ha/year). Keep it
  distinct from the 65-site first-100-design-point comparison below.
- The [controlled pilot](https://github.com/ccmmf/calibration/tree/86ddeecca42a3db9749d56ae8ff7248587a2ee2b/examples/4_controlled_benchmark)
  already includes preparation, summarization, dry-down diagnostics, tests,
  and frozen provenance. Its no-change checks pass; low crop growth and
  inadequate realized rice drying remain limitations. Do not launch it as
  part of this initial handoff.

## Existing results and their quantities

The fixed-parameter paired experiment covers 2016–2023 at 99 usable design
points, excluding one unusable initialization. These are unweighted design-point
averages, not acreage-weighted statewide benefits or propagated posterior results.

| Comparison | Locations | Archived model | Selected synthesis | Quantity |
|---|---:|---:|---:|---|
| Cover / no cover | 65 | 0.1324 | 0.32 | Mg soil + litter C/ha/prepared cover year versus measured SOC rate |
| Reduced / conventional tillage | 99 | 0.1182 | 0.2162 | Mg soil + litter C/ha/simulation year versus SOC rate |
| No / conventional tillage | 99 | 0.1461 | 0.2162 | Same as reduced tillage |
| Organic substitution / mineral fertilizer | 99 | 1.0634 | 1.2690 | Soil-only endpoint response ratio |
| One rice interruption / flooded baseline | 12 | 0.999864 | 0.6710 | Flooded-season CH4 response ratio |
| Two interruptions / flooded baseline | 12 | 0.999963 | 0.5350 | Flooded-season CH4 response ratio |

Ratios above are exponentiated means of site log response ratios. The main
effects figure has three panels containing six comparisons; N2O is in a
separate diagnostic table. The older eleven-panel scorecard is historical
context and mixes SD, SE, and assumed sensitivity spreads.

## Specific decisions for the comparison table

1. Use selected `source_id` plus subclass, statistic, and scale to join evidence;
   a practice/outcome label alone is insufficient. Bai 2023
   ([DOI](https://doi.org/10.1016/j.catena.2023.107343)) supersedes the
   Vicente-Vicente organic-amendment rate target. The frozen scorecard's
   `org_sub.structural_flags` still says Mediterranean olive orchard. Preserve
   that archive and correct the note in a derived table. Bai's global SOC
   contrast does not automatically match nutrient substitution or a California
   subgroup; stock changes and annual rates are different quantities.
2. Match pools, depth, years, and treatment exposure before judging magnitude.
   Cover/tillage use soil plus litter; organic substitution uses soil alone.
   Cover divides the final stock contrast by prepared cover years, tillage by
   eight simulation years. None is interchangeable with a measured SOC slope.
3. Keep annual integrated gas fluxes, flooded-season integrals, endpoint stocks,
   and December endpoint gas rates in separate columns. The paired scorer
   integrates `annual_outputs.csv` fluxes over each year; its rice score uses
   season windows. An endpoint rate multiplied by seconds/year is not an
   observed or simulated annual integral. Do not merge older atlas values
   without a documented operator and run identity.
4. Van Kessel's selected dry-climate area-scaled targets have LRR +0.322
   (short duration; about +38%) and -0.419 (long duration; about -34%). The
   abstract's +57%/-27% are yield-scaled. The model tillage diagnostic is
   -2.36% over 2016–2020, not the long-duration class. Do not join solely on
   the extraction-table evidence identifier or average overlapping subgroups.
5. Model and measured N2O-N share an N-mass basis; nitrogen parameters remain
   uncalibrated. No unit mismatch is established by the name `nVolatilization`.
   Historical scorer/report comments label the EF-level comparison an upper
   bound: retain their status as historical interpretation and confirm the
   actual executable/adapter semantics before carrying that conclusion into
   new prose. The manifest names a configured model revision, not a verified
   runtime executable hash. Keep EF level, EF slope, and flux ratio distinct.
6. Carry SD, SE/CI, and assumed spreads with their referents. Among-plot SD is
   not precision of a synthesis mean; design-point variation is not parameter
   uncertainty. Summarize model sites once per comparable group rather than
   replicate a synthesis estimate as an independent observation at every site.

## Reuse and local preservation

The September benchmark checkout's 17 statewide bundle files and controlled
generator match PR #8 byte for byte. Its two remaining statewide source-file
differences are editorial/plotting changes. This branch salvages the clearer
organic-amendment label, plot sizing/font changes and caption information while
retaining explicit denominators and the existing methods/provenance sections.
All frozen data and numerical estimators are unchanged.

The untracked `cal-val-data/statewide_benchmarking/` briefing and associated
`reports/R/statewide_benchmark_helpers.R` describe an older atlas comparison;
they are separate from the authoritative `data_raw/statewide_benchmarking/`
tables already committed. They remain in their original checkout for context,
without being imported wholesale into this model handoff.

From this repository root, `Rscript reports/R/build_statewide_report.R`
verifies all manifest input hashes and reproduces the six archived estimators.
Then `quarto render reports/statewide_effects.qmd` renders without running SIPNET.
Raw scored outputs remain under Geo's `statewide_matrix/pecan_v1`; the frozen
`run_manifest.csv` describes `setup_v1` staging. Keep these identities separate.

The 2026-10-04 local check reproduced all six estimates, passed all 16 manifest
hashes, retained all 386 finite plotted location effects and the 12-row display
table's numeric values, and rendered the statewide HTML with both linked
figures present. Both revised comparison figures were visually inspected for
legibility. This verifies rendering and preservation, not scientific validation
or an independent rerun of SIPNET.

First deliver a compact comparison specification and updated table/figure from
these outputs, with comparable/qualified/blocked status and reasons. Describe
the minimum remaining crop/water/ensemble work as proposed follow-up; do not
present it as completed or initiate new simulations without separate scope.
