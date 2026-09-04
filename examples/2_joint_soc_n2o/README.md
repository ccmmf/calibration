# Joint cal/val calibration

One inversion over the cal/val treatments the curated record supports, rather
than a per site pass. The fitted target is the salinas SOC period mean level
plus its treatment contrasts; the modesto N2O treatment contrast is held out of
the likelihood and scored as validation. Physiological parameters are held at
strong priors; the compost events carry an amendment quality
scaling documented beside the prepared inputs in the workspace.

This directory holds configuration only, the same shape as
`examples/1_salinas_soc`. The code is the generic numbered scripts in
`../../scripts`, and the run artifacts live in the workspace.

| file | what it is |
|---|---|
| `config.yml` | targets, priors, pinned parameters, PFTs, EKI settings, workspace path |
| `template.xml` | whole-run PEcAn settings; expanded per block by `015_build_settings.R` |
| `blocks.csv` | one row per fitted treatment: dates, PFTs, and the exact met, template IC, and events file each block runs |

## Running it

```sh
CFG=examples/2_joint_soc_n2o/config.yml
Rscript scripts/010_prepare_observations.R -c $CFG   # raw observation cache
Rscript scripts/012_build_target.R         -c $CFG   # contract to the fitted target
Rscript scripts/015_build_settings.R       -c $CFG   # settings + default.param + template ICs
Rscript scripts/020_build_priors.R         -c $CFG
Rscript scripts/030_calibrate.R            -c $CFG   # add --dry-run --particles 3 for a proof pass
Rscript scripts/040_plot.R                 -c $CFG
```

Run from the workspace: the settings carry the array launcher as
`./scripts/sge_array_launcher.sh` and `qsub` runs with `-cwd`, so the working
directory has to be the workspace (`scripts/` sits beside `settings.xml` in
every working run tree).

## Workspace

`/projectnb/dietzelab/ccmmf/usr/akash/cal_val_joint/`, on geo.

```
template.xml                    global sections; expanded per block by 015
pass5/                          run workspace: settings.xml, sipnet.default.param,
                                scripts/, per iteration output
inputs/                         events prepared from the curated management record
cache_pass5/                    obs.rds, target.rds, prior.rds, result.rds
```
