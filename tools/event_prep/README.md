# events.json generators

The scripts that produced the `events.json` files under `runs/`. They are here so the
derivation is reviewable and re-runnable; previously the files named a generator in their
`provenance.generator` field that existed only on SCC or in a scratch directory.

| script | produces | source of truth |
|---|---|---|
| `step3_assemble_events.R` | US-Bi2 | statewide monitoring product + fertilization parquet |
| `step3_delta_assemble.R` | US-Bi1, US-Twt 2017-2023 | as above, Delta sites |
| `step3_delta_ensemble.R` | 20-member event ensembles | as above, one realization per member |
| `us_twt_build_events.py` | US-Twt 2010-2016 | Knox et al. 2016 + curated `cal-val-data` managements |
| `us_twt_irrigation_schedule.py` | rewrites US-Twt irrigation | 2017-2023 monitoring rate and interval |
| `us_twt_merge_2010_2023.py` | merges the two US-Twt windows | both of the above |
| `write_events_in.py` | `events.in` from `events.json` | `PEcAn.SIPNET::write.events.SIPNET` equivalent |

## Order for US-Twt

```
us_twt_build_events.py        # 2010-2016 from literature
us_twt_irrigation_schedule.py # replace the 150/0 flood pair with a weekly schedule
us_twt_merge_2010_2023.py     # fold in 2017-2023 and backfill tillage
write_events_in.py            # emit events.in for SIPNET
```

## Notes

- `us_twt_merge_2010_2023.py` **asserts** the Knox tillage offsets (planting minus 21 d for
  disking, minus 7 d for ring rolling) are constant across all seven literature years before
  extending them forward. If they were not, it stops rather than fitting something.
- The monitoring product does not cover parcel 590073 before 2017; its 2016 export is
  truncated at `site_id` 99999. That is why 2010-2016 is built from the literature instead.
- `validate_events_json` needs `jsonvalidate` installed or it silently returns `NA` rather
  than validating, and it needs `events_schema_v0.1.1`, which not every PEcAn install ships.
