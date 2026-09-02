# events.json generators

The scripts that produced the `events.json` files under `runs/`. They are here so the
derivation is reviewable and re-runnable; previously the files named a generator in their
`provenance.generator` field that existed only on SCC or in a scratch directory.

| script | produces | source of truth |
|---|---|---|
| `pull_inputs.sh` | local copy of the monitoring product | CCMMF S3 (`s3://carb/management/`) |
| `extract_parcel_csvs.R` | per-parcel `own_*.csv` | the pulled statewide products |
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

No path is hardcoded. The scripts chain from the environment exactly as the CCMMF setup
script does, so setting `CCMMF_BASE` alone is enough:

```
CCMMF_BASE          default ~
CCMMF_ROOT          default $CCMMF_BASE/ccmmf
PRODUCTS_ROOT       default $CCMMF_ROOT/products
PRODUCTS_INVENTORY  default $PRODUCTS_ROOT/inventory
EVENT_OUTPUT_DIR    default $PRODUCTS_INVENTORY/event_files
CCMMF_WORK          default $CCMMF_ROOT/work
```

Any of them can be overridden individually. Background on the names and on account setup:

- <https://github.com/ccmmf/magic-training/blob/main/CARB-PEcAn-setup.md>
- <https://github.com/PecanProject/pecan/blob/develop/modules/data.remote/inst/ccmmf/documentation/setup_env.sh>
- <https://github.com/PecanProject/pecan/blob/develop/modules/data.remote/inst/ccmmf/documentation/sessions/02-phenology.md>

## Getting the input data from S3

The monitoring product lives in the Garage S3 bucket `carb` under `management/`. You need
an `aws` client and the `ccmmf-garage` profile in `~/.aws/credentials`; on SCC,
`module load awscli/2.13.5` provides the client.

See what exists before pulling anything:

```bash
./pull_inputs.sh --list
```

Then pull. With no arguments it fetches the three Delta parcels; otherwise pass parcel ids:

```bash
./pull_inputs.sh                 # 565118, 328163, 590073
./pull_inputs.sh 565118          # US-Bi2 only
```

### Which version to take

**Not the latest.** `pull_inputs.sh` pins the versions that reproduce the committed
`runs/*/events.json`:

| product | pinned | also on S3 |
|---|---|---|
| planting | `v1.0` | `v2.0` |
| harvest | `v1.0` | `v2.0`, `beta` |
| irrigation | `v1.1` | `v1.0` |
| tillage | `v1.0` | — |
| fertilization | `v1.0` | `v2.0` |

These match the `source` strings recorded in each event, so an events.json says which
version produced it. A newer version is not a drop-in replacement: for parcel 565118,
fertilization `v2.0` moves every event date and puts all N in NH4 with NO3 at zero, where
`v1.0` splits N evenly. Moving a pin is a deliberate change — override
`FERTILIZATION_VERSION` and friends, re-run, and diff `runs/*/events.json` before keeping it.

`management/irrigation/CHANGELOG.txt` is the only changelog in the bucket; the other
products carry no version notes.

### Where it lands

`pull_inputs.sh` writes into exactly the paths the R scripts read, so no further mapping is
needed:

| S3 | local | read by |
|---|---|---|
| `management/planting/v1.0/` | `$PRODUCTS_INVENTORY/management/planting/v1.0/` | `extract_parcel_csvs.R` |
| `management/harvest/v1.0/` | `$PRODUCTS_INVENTORY/management/harvest/v1.0/` | `extract_parcel_csvs.R` |
| `management/irrigation/v1.1/` | `$PRODUCTS_INVENTORY/management/irrigation/v1.1/` | `extract_parcel_csvs.R` |
| `management/tillage/v1.0/` | `$PRODUCTS_INVENTORY/management/tillage/v1.0/` | `us_twt_merge_2010_2023.R` |
| `management/fertilization/v1.0/` | `$EVENT_OUTPUT_DIR/fertilization.parquet/` | `step3_*.R` |

Fertilization is Hive-partitioned by `event_member_id`; it is opened as an Arrow dataset, so
the local name `fertilization.parquet` is a directory, not a file.

Irrigation is 121 shards totalling roughly 4 GB, so only the shards that can hold the
requested parcels are fetched.

### Full run, from nothing

```bash
export CCMMF_BASE=/path/to/scratch
./pull_inputs.sh 565118
Rscript extract_parcel_csvs.R us_bi2 565118
Rscript step3_assemble_events.R
# -> $CCMMF_WORK/us_bi2_events/us_bi2_events.json
```

The Delta sites take their parcel and crop as arguments:

```bash
Rscript extract_parcel_csvs.R us_bi1 328163
Rscript step3_delta_assemble.R us_bi1 328163 P1 2017 2017-01-01 2023-12-31
```

This chain was run from an empty `CCMMF_BASE` on a laptop and on SCC. Both produce a
`us_bi2_events.json` that is byte-identical to the committed `runs/us_bi2/events.json`
(md5 `b9fe0791...`), and `us_bi1` reproduces its committed 32 events with no differences.

### Gotchas

- **Irrigation shard names are nominal ranges and they overlap.** Twelve shards have a name
  bracketing parcel 328163. A parcel inside a shard's named range is not necessarily in that
  shard: `241361_602889.parquet` covers 565118 by name but holds none of its rows. Pull every
  matching shard and filter on `parcel_id`, which is what these scripts do.
- **Column types are not stable across the per-year files.** `site_id` is `int32` in planting
  and `string` in harvest, and `date` is `character` in `planting_statewide_2016` but `Date`
  from 2018 on. Stacking those with `rbind` silently yields `NA` dates rather than an error,
  so `extract_parcel_csvs.R` normalises both to character per file first.
- **The planting and harvest products have no 2017.** That is why the step3 scripts synthesize
  a 2017 cycle from the median day-of-year of the other years.
- Fertilization is legitimately absent for some parcels — US-Bi1 has none, and its committed
  events.json has no fertilization events either.
