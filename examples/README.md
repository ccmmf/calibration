# Examples

Each directory is one complete calibration configuration for the shared
numbered scripts in `../scripts`. Start with `1_salinas_soc` (one site, one
variable, a prepared run) and move to `2_joint_soc_n2o` (joint multi-variable
target, settings build, holdout validation). The package code in `R/` carries
nothing site or variable specific; everything a run needs is declared here.

## Config reference

Every key the scripts read from a `config.yml`, grouped as in the files.
Optional keys are marked; everything else is required by the script that
consumes it.

| key | consumed by | meaning |
|---|---|---|
| `scc` | 010, 020, 030, 040 | root that relative data and run paths hang off |
| `cache_dir` | all | directory for `obs.rds`, `target.rds`, `prior.rds`, `result.rds` |
| `soil_pft` | 020, 030 | soil PFT name(s); a vector shares the calibrated rates across all of them |
| `observations.dir` | 010 | cal-val-data checkout, relative to `scc` |
| `observations.targets[]` | 010 | one entry per observed variable: `variable`, `sites`, `units`; optional `source_variables`, `years`, `variance` ("replicate" or "pooled_cv"), `cell_period` ("year" or "date") |
| `target[]` (optional) | 012, 030 | contractions from raw slots to the fitted target, one per entry, dispatched on `type`: `period_mean` (`variable`, `control`, optional `years`, `new_variable`) or `contrast` (`variable`, `treatment`, `control`, `new_variable`). Omit the block to fit the raw slots |
| `priors.post_distns_params` | 020 | traits read from the soil PFT meta-analysis posterior |
| `priors.specified` | 020 | explicit priors, one entry per trait: `distn`, `parama`, `paramb` |
| `priors.state` (optional) | 020, 030 | calibrated initial state: `prefix`, `variable`, `from_unit`, `to_unit`, optional `anchor_year` (default earliest) |
| `fit` (optional) | 030 | sitename -> first observation year to fit; earlier years stay initial condition only |
| `validation_variables` (optional) | 030, 040 | fitted-target variables held out of the likelihood, still predicted and scored |
| `fixed_params` | 015, 030 | parameters pinned in `default.param`, one entry per trait: `sipnet` (model name), `value` |
| `forward.workspace` | 015, 020, 030, 040 | run workspace holding `settings.xml`; `forward.run_dir` (relative to `scc`) is the prepared-run alternative |
| `forward.blocks` | 015 | blocks table: one row per treatment with dates, PFTs, and the exact met, IC, and events file |
| `forward.template` | 015 | whole-run PEcAn settings template, expanded per block |
| `forward.prepared_root` (optional) | 015 | root of prepared inputs and the launcher; defaults to the workspace |
| `forward.sa_root` | 015 | staging tree holding `inputs/met` and `inputs/IC` |
| `forward.binary` | 015 | SIPNET binary the run pins |
| `forward.var_map` | 030 | per observed variable: `model_var`, `from`, `to` -- the crosswalk from model output to observation units |
| `forward.state_pool` | 030 | initial condition pool the calibrated state writes into |
| `figures.treatment_effect` (optional) | 040 | measured vs modeled effect figure: `variable`, `treatment`, `control` |
| `eki` | 015, 030 | `n_particles`, `n_iterations`, `seed` |

## Script sequence

`010` observations, `012` fitted target (only when `target` is declared),
`015` settings build (only when the run is not already prepared), `020` prior,
`030` calibration, `040` figures and scores. Each takes
`--config <example>/config.yml`.
