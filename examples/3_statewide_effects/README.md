# Statewide treatment-effect forward matrix

Paired forward runs at the first 100 statewide design sites, one run per
(site, treatment arm), scoring modelled practice effects against the
synthesis targets in `summarized_targets.csv`. The runs are driven entirely
by the standard PEcAn workflow: settings, configuration writing, submission
and output conversion are PEcAn's, not this repository's.

## Workflow

    Rscript scripts/050_build_statewide_settings.R -c examples/3_statewide_effects/config.yml
    Rscript scripts/052_run_statewide_matrix.R     -c examples/3_statewide_effects/config.yml
    Rscript scripts/060_score_statewide_matrix.R   -c examples/3_statewide_effects/config.yml

Run under R 4.4.3, where PEcAn is installed.

`050` expands `template.xml` into one run section per (site, arm) with
`createMultiSiteSettings`, sets each run's vegetation and soil PFT, points it
at that arm's events file and the site's shared met and initial conditions,
and writes `settings.xml` plus the pinned `sipnet.default.param`.

`052` is the PEcAn workflow: `runModule.run.write.configs` writes each run's
`sipnet.param`, `sipnet.in`, `events.in` and `job.sh`;
`runModule_start_model_runs` submits them through the host block as SGE array
jobs; `runModule.get.results` converts the raw output. Each stage is guarded
by the workflow `STATUS` file, so an interrupted run resumes with
`--continue`.

`060` reads the standard netCDF written by `model2netcdf.SIPNET`, forms the
paired effects, aggregates the model side to one estimate per target cell,
and writes the scorecard.

## What this repository supplies, and what PEcAn does

PEcAn owns the model machinery. The parameter file is built by
`write.config.SIPNET` from the stock `template.param_v2`, the PFT trait
samples and `default.param`; initial pools come from `prepare_pools` reading
the site's `poolinitcond`; the met driver is symlinked by `job.sh`; model
options are rendered into `sipnet.in`; submission and output conversion are
`start_model_runs` and `model2netcdf.SIPNET`.

This repository supplies only what is specific to the experiment:

- which runs exist, and which events, met and initial conditions each uses;
- the parameter values pinned across the matrix;
- the soil C:N coupling, which `write.config.SIPNET` does not set;
- the mapping from treatment pairs to synthesis target cells, and the scoring.

## Parameterization

Vegetation and soil traits are the PFT posterior medians from the pinned
input package, taken with `PEcAn.priors::get.sample(p = 0.5)`. The matrix is
deterministic: one ensemble member carrying those medians rather than a draw.

Pinning a parameter takes both halves, the value in `default.param` and the
trait dropped from the samples, since `write.config.SIPNET` overwrites
`default.param` from the trait values. `fixed_params` in the config does
both. `default_param` sets a default a PFT posterior may still override,
which is how the rice soil keeps its own drainage rate.

The soil C:N coupling is applied to the written configs by
`couple_soil_orgn`, because `write.config.SIPNET` sets `soilInit` from the
initial conditions but never sets `soilOrgNInit`.

## Treatment matrix

`treatment_matrix.csv` maps each pair to its effect definition and target
cell. The target table is keyed practice by outcome by subclass, so the
mapping carries `target_subclass`; the two stratified cells match on all
three, rice methane by number of drying events and nitrogen fertilization by
crop class.

Model-side aggregation happens before any cell is scored: one modelled
estimate per cell against one synthesis estimate.

## Effect definitions

The paired soil carbon effect is the end-of-window arm difference. Cover is
expressed per prepared cover year. The amendment cell is a stock log ratio on
the soil pool alone, matching its operator, since amendment organic carbon
enters the litter pool. Rice log ratios are flooded-season totals derived per
site-year from the irrigation events. Tillage nitrous oxide is the log ratio
of cumulative emissions over the first five years. Nitrogen fertilization is
the slope of the emission factor against nitrogen rate across the three
fertilized arms, scored once per crop class.

## Reproducibility

The run is determined by this repository at the build commit, `config.yml`,
which pins every input path and checksum and every parameter value, the PFT
input package version, and the generated `settings.xml`. `pecan.CONFIGS.xml`
records the settings actually used.
