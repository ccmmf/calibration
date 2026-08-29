# Russell Ranch treatment events

One `events.json` per Tautges et al. (2019) treatment, covering 1993-2013. These are
**treatments** - different farming systems run side by side - not ensemble members. Using
them as ensemble members would conflate treatment effect with management uncertainty.

Source: `10.1002/ecy.2105`, via the curated managements in `ccmmf/cal-val-data`.

## Not yet included

`org_corn_tomato` and `transitional` are **withheld because they do not validate**. Both
carry fertilization events with none of `org_c_kg_m2`, `nh4_n_kg_m2` or `no3_n_kg_m2`,
which the schema requires at least one of:

```
/events/1: must have required property 'nh4_n_kg_m2'; must match a schema in anyOf
```

24 of 24 fertilization events fail in `org_corn_tomato`, 12 of 23 in `transitional`.

The amounts are not missing from the underlying data. `cal-val-data/data/managements.csv`
has 180 and 72 curated rows respectively for those dates, carrying N levels of 3 to 12
kg N ha-1. They were dropped somewhere between the curated managements and these JSON
files. Repairing them means re-deriving the generator's aggregation, since the curated rows
are per replicate and the events are per treatment, so the two are added once that mapping
is confirmed rather than guessed.

## Which treatment the run uses

The committed `russell_user_config.yaml` runs `conv_corn_tomato`. The other files are here so
the alternatives are available and reviewable, not because all twelve are run.
