# Salinas SOCS events

One `events.json` per system of the Salinas Organic Cropping Systems trial (White et al. 2020,
`white_salinas_2020`), `events_socs_sys1.json` to `events_socs_sys8.json`, 30 September 2003 to
7 August 2011. They are rebuilt for
[ccmmf/organization#297](https://github.com/ccmmf/organization/issues/297) from the papers'
management calendar alone, and they replace the uncertainty#6 fills, none of which they reuse.

Built by `tools/event_prep/salinas_build_events.R` from the cal-val-data calendar
(`data/managements.csv`, `treatments.csv` and `crops.csv` on the `calval-metadata` branch, PR #24,
commit `779d38e`; `managements.csv` md5 `e6e9e0027eb2443b4d9f62ed4aa38ac0`, recorded in each
file's `provenance`). Its `data_raw/white_salinas_2020/data_entry_report.md` ("Dates") explains every
window used here. Every event comes from a calendar row (`calval_event_id` names it), plus the end
of each winter cover crop at its spring flail mowing and spading; nothing else is inserted. What
the papers do not give is filled in the order of
[`tools/event_prep/README.md`, "Filling missing events"](../../tools/event_prep/README.md#filling-missing-events):
the papers, then the monitoring product near SOCS (`monitoring_near_salinas.csv`, from
`tools/event_prep/salinas_monitoring.R`), then guidance. Every event carries `source`,
`provenance_class` and `provenance_note`; `fill_summary.csv` counts every value that is not
published.

| system | events | planting | harvest | fertilization | irrigation | tillage |
|---|---|---|---|---|---|---|
| `socs_sys1` | 364 | 17 | 17 | 28 | 276 | 26 |
| `socs_sys2` | 379 | 17 | 17 | 43 | 276 | 26 |
| `socs_sys3` to `socs_sys8`, each | 417 | 23 | 23 | 43 | 302 | 26 |

`socs_sys1` and `socs_sys2` grow the legume-rye cover crop in 2006-07 and 2010-11 only; the other
six every winter from 2003. `socs_sys1` gets no compost.

## How the rows become events

**Dates.** A row with one date keeps it (`published`, except the spading on a cover crop's
termination day, which is the calendar's own assumption). For a window, the event takes the
monitoring product's median timing for the crop and operation near SOCS when it falls inside
the window (`imputed`), otherwise the window's midpoint (`assumed`; the note gives the window).
Windows the calendar orders around another event are first narrowed to the dates chosen for it:
preplant compost and pellets to before the crop's planting (and, before the second crop, after
the lettuce harvest), liquid fertilizer to the crop's season, and tillage to after the harvest
it follows (for the fall residue incorporation, the last vegetable harvested by the end of its
window) and before the planting it prepares (the lettuce for the spring spading, a cover crop sown
that fall). Planting and harvest medians are days of year; tillage medians are
days after the harvest or before the planting they belong to, as for Russell Ranch, because the
product's tillage days of year wrap the new year.

**Crops.** Lettuce, spinach and broccoli are planted as the calendar gives. Marketed lettuce and
broccoli remove White et al. (2020b)'s harvest index, 0.26 and 0.24 of the shoot, with the rest
and the roots to litter (`harv 0.26 0 0.74 1`, `harv 0.24 0 0.76 1`). The 2004 spinach and 2005
broccoli, incorporated unharvested, and every cover crop at its flail mowing and spading go wholly
to litter (`harv 0 0 1 1`). All four fractions are written with `harvest_fractions()`.

**Fertilization.** Compost: 7.6 Mg/ha oven dry, C at White et al. (2020b)'s measured
317 g C/kg (0.24092 kg C/m2), N at the calendar's 15 g N/kg (0.0114 kg N/m2). Pelleted
fertilizer: the calendar's N as organic N, with C at a C:N of 5.81, the mean of the two products
White et al. (2020b) analysed (280 g C/kg in the 4-4-2, 370 in the 8-1-1: C:N 7.00 and 4.63).
Liquid fertilizer: the calendar's N as mineral N (`nh4_n_kg_m2`), without C.

**Irrigation.** Cover crop establishment: Brennan and Boyd (2012) Fig. 2's total split equally
over its application days, the first on the planting day, the last on the published last
irrigation and the others evenly between, method `canopy` (linear move sprinkler). Vegetables
(drip, method `soil`): the monitoring product's median irrigation rate of irrigated seasons of
the matching class and months times the season's days, applied every 3 days from planting to the
day before harvest (the scenarios `irrigation_drip` interval). The product estimates water use
minus rain, so this is a lower bound.

**Tillage.** One event per row, with `depth_m` and `implement` from the row and
`tillage_eff_0to1` the monitoring product's median intensity for the matching pass: the last
tillage before a May T30 planting for the spring spading, the first after the harvest of the
crop it follows for the fall residue incorporation, subsoiling and the 2011 passes, and the
median of all tillage events for the 2003 buckwheat incorporation.

## Fills and assumptions

Totals over the eight files; `fill_summary.csv` breaks them down by system.

| value | rule | class | events |
|---|---|---|---|
| vegetable planting date | monitoring median day (lettuce 56, spinach 8, broccoli 48) | imputed | 112 |
| vegetable planting date | window midpoint: 2009 lettuce, 24 to 31 May | assumed | 8 |
| vegetable harvest date | monitoring median day: 2006 broccoli, 16 October | imputed | 8 |
| vegetable harvest date | window midpoint (lettuce 64, spinach 8, broccoli 40) | assumed | 112 |
| cover crop end date | window midpoint: 2011 in `socs_sys3` to `sys8`, 2007 and 2011 in `socs_sys1` and `sys2` (the other 42 are Table 2 dates) | assumed | 10 |
| planting leaf C | monitoring median (lettuce 64, spinach 8, broccoli 48, cover crops 52) | imputed | 172 |
| fertilization date | window midpoint (compost 105, pellets 120, liquid 104) | assumed | 329 |
| compost C | tonnage x 317 g C/kg | derived | 105 |
| compost N | calendar `N_content_g_kg = 15`, no published source | assumed | 105 |
| pellet C | mean C:N of the two products | assumed | 120 |
| liquid N | mineral N without C | assumed | 104 |
| cover crop irrigation day | spaced evenly between planting and the last irrigation | assumed | 136 |
| cover crop irrigation amount | total over application days | derived | 180 |
| vegetable irrigation amount | monitoring T30 rate x season days (lettuce 1064, broccoli 1008, spinach 104) | imputed | 2176 |
| vegetable irrigation day | every 3 days from planting (guidance) | imputed | 2176 |
| spinach irrigation method | not reported; `soil`, the drip of the other vegetables | assumed | 104 |
| tillage date | the calendar's spading on the cover crop termination day | assumed | 42 |
| tillage date | monitoring median days after harvest or before planting | imputed | 44 |
| tillage date | window midpoint | assumed | 90 |
| tillage intensity | monitoring median (T30 preplant 64, T4 postharvest 96, T30 postharvest after lettuce 24 and spinach 16, all events 8) | imputed | 208 |

An event's `provenance_class` is the weakest of its parts (published, derived, assumed, imputed).
Per file: `socs_sys3` to `sys8` have 8 published, 7 derived, 80 assumed and 322 imputed events;
`socs_sys1` 1, 1, 46 and 316; `socs_sys2` 1, 1, 61 and 316.

## Monitoring values used

From `monitoring_near_salinas.csv`: parcels within 25 km of SOCS, events 2015 to 2024 (planting,
harvest, tillage and irrigation v5.0, fertilization v2.0, crop table v4.1; S3 paths in
`salinas_monitoring.R`). The product has no lettuce, spinach, broccoli or cover crop class, so
each crop is a class and its planting months.

| crop | class, planted | used |
|---|---|---|
| romaine lettuce | T30, May | planting day 128, 8 May (n = 15,437); leaf C 0.00275 kg/m2; harvest day 213 (outside every June-July window); irrigation 2.646 mm/day (5,641 irrigated of 10,122 seasons); spring tillage 94 days before planting, intensity 1.0 (n = 4,647); tillage 53 days after harvest, intensity 0.8178 (n = 6,101) |
| baby leaf spinach | T30, July | planting day 196, 15 July; leaf C 0.00189; harvest day 268 (outside); irrigation 3.783 mm/day (5,509 of 6,636); tillage 35 days after harvest, intensity 0.9369 |
| broccoli | T4 (cole crops), July or August | planting day 206, 25 July; leaf C 0.00456; harvest day 289, 16 October; tillage 33 days after harvest, intensity 0.936 (n = 4,390) |
| broccoli irrigation | T30, July or August | 3.901 mm/day (9,414 of 11,255 seasons). T4 is irrigated in 11 % of its July and August seasons, at 1.738 mm/day, implausibly little for broccoli (its water model probably gives T4 a mustard crop coefficient; not checked for v5.0). Its dates and leaf C are kept |
| cover crops | G6 (miscellaneous grain and hay), October or November | leaf C 0.00416 (n = 629) |
| all tillage | | intensity 0.7869 (n = 95,194), for the 2003 buckwheat incorporation |

The fertilization product puts one application per season on the planting day (median 0 days),
so it dates neither the preplant nor the in-season applications, and every fertilization date is
a window midpoint. The seasons here (35 to 83 days) are mostly shorter than the product's
(medians 71 to 78 days in the pools the rates come from), which is why irrigation scales a daily
rate rather than taking a season total.

## Left out

- The pre-study establishment compost (`compost_application-0001`, about 22 Mg/ha wet weight):
  it belongs to no system row, has no moisture or C to convert it, and the papers put it in the
  year before the trial, while its calendar window is still to be re-dated (data entry report,
  Open follow-ups).
- The buckwheat and the 2002-03 legume-rye grown before the trial: no planting rows. The
  2003-09-30 buckwheat incorporation is kept as tillage.
- Transplant potting mix C (White et al. 2020b, 137 g C/kg): no calendar row and no mass.
- Bed formation, top shaping, the bed reshaping after the lettuce and the fallow-winter weed
  control in `socs_sys1` and `sys2`: not on the calendar (an open follow-up in cal-val-data).
- The Year 8 spading follows the ripping in the paper but lands on the same day, 7 August 2011.

## Checks

- The builder stops unless each file has as many planting, tillage and fertilization events as the
  calendar has rows, one harvest per harvest row plus one per cover crop, every calendar row in its
  events and a cover crop irrigation row once per application day; plantings and ends alternate
  with the same crop, so one crop grows at a time, once a year; every event lies in 2003 to 2011;
  every harvest passes `check_harvest_fractions()`; every event has a source and a class.
- All eight files validate against `events_schema_v0.1.1` (PEcAn `develop`) with `jsonvalidate`,
  and `tools/event_prep/write_events_in.R` writes an `events.in` for each with as many lines as
  events: 30 `irrig ... 0` (sprinkler) lines in `socs_sys3`, every drip line `1`.
- `tests/testthat/test_salinas_events.R` checks the harvest fractions, the compost and N totals
  against the papers, the cover crop water against Fig. 2, the drip schedule inside each season
  and the `events.in` written from `socs_sys3`.
- Rerunning both scripts reproduces `monitoring_near_salinas.csv`, the eight files and
  `fill_summary.csv` byte for byte.

## Rebuild

```bash
Rscript tools/event_prep/salinas_monitoring.R <monitoring_dir> runs/salinas_socs/monitoring_near_salinas.csv
Rscript tools/event_prep/salinas_build_events.R <cal-val-data checkout> runs/salinas_socs
```

`<monitoring_dir>` holds the products as listed in the header of `salinas_monitoring.R`.

## Using them

`write_events_in.R events_socs_sysN.json <dir>` gives `events-socs_sysN.in`. The single-site
configuration here (`salinas_user_config.yaml`) copies one `data/events.in` into every run, so
each system needs its own run directory. The joint calibration's SOCS blocks start in 2005: clip
the JSON to the block window before writing `events.in`, which drops the 2004-05 cover crop
planting but not its spring end.
