# events.json generators

The scripts that produced the `events.json` files under `runs/`. They are here so the
derivation is reviewable and re-runnable; previously the files named a generator in their
`provenance.generator` field that existed only on SCC or in a scratch directory.

| script | produces | source of truth |
|---|---|---|
| `step3_assemble_events.R` | US-Bi2 | statewide monitoring product + fertilization parquet |
| `step3_delta_assemble.R` | US-Bi1, US-Twt 2017-2023 | as above, Delta sites |
| `step3_delta_ensemble.R` | 20-member event ensembles | as above, one realization per member |
| `us_twt_build_events.R` | US-Twt 2010-2016 | Knox et al. 2016 + curated `cal-val-data` managements |
| `us_twt_irrigation_schedule.R` | rewrites US-Twt irrigation | 2017-2023 monitoring rate and interval |
| `us_twt_merge_2010_2023.R` | merges the two US-Twt windows | both of the above |
| `write_events_in.R` | `events.in` from `events.json` | `PEcAn.SIPNET::write.events.SIPNET` equivalent |

## Order for US-Twt

```
us_twt_build_events.R        # 2010-2016 from literature
us_twt_irrigation_schedule.R # replace the 150/0 flood pair with a weekly schedule
us_twt_merge_2010_2023.R     # fold in 2017-2023 and backfill tillage
write_events_in.R            # emit events.in for SIPNET
```

## Notes

- `us_twt_merge_2010_2023.R` **asserts** the Knox tillage offsets (planting minus 21 d for
  disking, minus 7 d for ring rolling) are constant across all seven literature years before
  extending them forward. If they were not, it stops rather than fitting something.
- The monitoring product does not cover parcel 590073 before 2017; its 2016 export is
  truncated at `site_id` 99999. That is why 2010-2016 is built from the literature instead.
- `validate_events_json` needs `jsonvalidate` installed or it silently returns `NA` rather
  than validating, and it needs `events_schema_v0.1.1`, which not every PEcAn install ships.

## Inputs and environment

The three `step3_*` scripts read the statewide monitoring product and the fertilization
parquet. No path is hardcoded. They chain from the environment exactly as the CCMMF setup
script does, so setting `CCMMF_BASE` alone is enough:

```
CCMMF_BASE          default ~
CCMMF_ROOT          default $CCMMF_BASE/ccmmf
PRODUCTS_ROOT       default $CCMMF_ROOT/products
PRODUCTS_INVENTORY  default $PRODUCTS_ROOT/inventory
EVENT_OUTPUT_DIR    default $PRODUCTS_INVENTORY/event_files   fertilization.parquet
CCMMF_WORK          default $CCMMF_ROOT/work                  extracted monitoring product tabs
```

Any of them can be overridden individually. Set them up by sourcing the project script
rather than by hand:

- Environment and account setup:
  <https://github.com/ccmmf/magic-training/blob/main/CARB-PEcAn-setup.md>
- Canonical variable names and the chaining above:
  <https://github.com/PecanProject/pecan/blob/develop/modules/data.remote/inst/ccmmf/documentation/setup_env.sh>
- The pattern these scripts should follow for pulling inputs, as used in the phenology
  session:
  <https://github.com/PecanProject/pecan/blob/develop/modules/data.remote/inst/ccmmf/documentation/sessions/02-phenology.md>

### Not yet done

Inputs are still read from a shared filesystem rather than pulled from S3 into a local
path. Moving to an S3 pull following the phenology session pattern is tracked separately
and does not block this PR.
