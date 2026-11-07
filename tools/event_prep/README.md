# events.json generators

The scripts that produced the `events.json` files under `runs/`. They are here so the
derivation is reviewable and re-runnable; previously the files named a generator in their
`provenance.generator` field that existed only on SCC or in a scratch directory.

| script | produces | source of truth |
|---|---|---|
| `pull_inputs.sh` | local copy of the monitoring product | CCMMF S3 (`s3://carb/management/`) |
| `extract_parcel_csvs.R` | per-parcel `own_*.csv` | the pulled statewide products |
| `us_bi1_build_events.R` | `runs/us_bi1/events.json` | `cal-val-data` managements (the site record), `us_bi1_cuttings.csv`, monitoring planting v1.0 and irrigation v1.1 |
| `us_bi2_build_events.R` | `runs/us_bi2/events.json` | `cal-val-data` managements (the site record), Anthony and Silver 2021, monitoring planting and harvest v5.0 and irrigation v1.1 |
| `us_twt_build_events.R` | `runs/us_twt/events.json`, 2010-2023 | `cal-val-data` managements (Knox et al. 2016), `us_twt_wtd_water_dates.csv`, monitoring planting and harvest v1.0, irrigation v1.1, fertilization v1.0 |
| `delta_inputs.R` | no file: the paths, product readers and writer the three Delta builders share | |
| `step3_delta_ensemble.R` | 20-member event ensembles for one Delta site | its builder, run once per member of the monitoring product |
| `russell_split_phases.R` | Russell Ranch, one file per treatment and rotation phase | `generator_stacked/` + Century Experiment package (`10.1002/ecy.2105`) + `russell_treatments.csv`, `russell_source_corrections.csv`, `russell_harvest_lookup.csv` |
| `russell_monitoring_tillage.R` | `monitoring_tillage_near_russell.csv`, tillage timing and intensity near Russell Ranch | monitoring tillage, harvest and planting v5.0 + crop table v4.1 |
| `russell_monitoring_irrigation.R` | `monitoring_irrigation_near_russell.csv`, corn, tomato and alfalfa season irrigation totals and timing near Russell Ranch | monitoring irrigation, harvest and planting v5.0 + crop table v4.1 |
| `write_events_in.R` | `events.in` from `events.json` | `PEcAn.SIPNET::write.events.SIPNET` equivalent |
| `fill_order.R` | no file: the fill helpers the generators share (below), sourced by `russell_split_phases.R` and the three Delta builders | |

## Building the Delta towers

Each tower has one builder that writes its whole `events.json`; nothing is edited by hand
afterwards. After `pull_inputs.sh` (below), from the repository root:

```bash
MG=../cal-val-data/data/managements.csv   # cal-val-data develop; 8f88e95 built the committed files
Rscript tools/event_prep/extract_parcel_csvs.R us_bi1 328163
Rscript tools/event_prep/extract_parcel_csvs.R us_bi2 565118
Rscript tools/event_prep/extract_parcel_csvs.R us_twt 590073
Rscript tools/event_prep/us_bi1_build_events.R $MG runs/us_bi1/events.json
Rscript tools/event_prep/us_bi2_build_events.R $MG runs/us_bi2/events.json
Rscript tools/event_prep/us_twt_build_events.R $MG runs/us_twt/events.json
Rscript tools/event_prep/write_events_in.R runs/us_twt/events.json <outdir>   # events.in for SIPNET
```

A builder takes an optional third argument, the member of the monitoring product's irrigation
(`irr_ens_NNN`) and fertilization (`ens_NNN`) ensembles, 1 by default.
`step3_delta_ensemble.R <site> $MG <out_dir> 20` runs the builder once per member, so every
member has the structure of the committed file, which is member 1. Only the product's events
vary: US-Bi1's irrigation, US-Bi2's two 2021 and 2022 irrigation events, and US-Twt's 2017-2023
irrigation and fertilization and with them its 2010-2017 flood amount (each member's own mean,
55 to 81 mm across the 20). US-Bi2's winter floods use the fixed 70 mm rule and do not vary.

These replace `step3_assemble_events.R` (US-Bi2) and `step3_delta_assemble.R` (US-Bi1, US-Twt
2017-2023), which wrote the monitoring product's events as they were, and the US-Twt chain of
`us_twt_build_events.R` for 2010-2016, a hand edit putting in the WTD flood and drain dates,
`us_twt_irrigation_schedule.R` and `us_twt_merge_2010_2023.R`, which did not reproduce the
committed file. What each tower's file now rests on is under "Delta towers" below.

## Filling missing events

When a site's records lack an event that is known to have happened (a crop that was
harvested, a cover crop that was incorporated), or lack its date or amount, the generators
fill it in this order (David, calibration#10):

1. **The paper or its source data.** Use what they record, including dates relative to
   another recorded operation (a termination before the next planting) and medians over the
   site's own records of the same system.
2. **The monitoring product** (`s3://carb/management/`). For a field and season it covers,
   use that field's values. Before 2016, when it starts, use average calendar or relative
   dates and amounts for comparable crops and operations in the same area.
3. **Guidance documents**, as a last resort; ideally their information is already in the
   monitoring product, as it is for fertilization.

This applies to amounts as well as dates. Every filled or imputed event says where it came
from (`source`, `provenance_class`, `provenance_note`).

The helpers for this are in `fill_order.R`, base R only. `russell_split_phases.R` and the three
Delta builders source it from their own directory; a new generator should do the same and use
them rather than set these fields by hand:

- `first_available(candidates, min_n)` takes the first of a named list of candidates, in order
  of preference, that has at least `min_n` records (non-missing values, list elements or data
  frame rows), and returns it with `from`, the name of the one taken, and `n`, its count. Name
  the candidates by source (the paper, the monitoring product, guidance) or by pool (this phase,
  the site); `min_n = c(5, 1)` takes the first only when it has at least five records and
  otherwise falls back to the second. It returns NULL when no candidate has enough, so the caller
  must handle that. Russell uses it for the medians that date imputed events,
  filled planting amounts, the cover crop end date, the 2014 fertilization template and the
  compost %C and %N.
- `set_provenance(e, class, note, source)` tags an event. `class` must be one of
  `PROVENANCE_CLASSES`: `published` (a source records the value), `derived` (computed from
  recorded values), `assumed` (rests on a stated reading of a source) or `imputed` (no record
  gives it). Every class but `published` needs a note, and every event a `source`. Fields the
  event already has keep their place in it.
- `harvest_fractions(above_removed, below_removed, above_to_litter, below_to_litter)` returns all
  four `frac_*_0to1` fields and has no defaults. `PEcAn.SIPNET::write.events.SIPNET` fills a
  missing transfer to litter as 1 - removed, so an alfalfa cutting given only 0.85 removed sends
  the rest of the shoots and all the roots to litter and ends the stand; written as
  `harvest_fractions(0.85, 0, 0, 0)` it leaves them alive.
- `check_harvest_fractions(events)` stops if a harvest lacks one of the four fractions or has one
  outside 0 to 1, or if removed and to litter add up to more than 1. Run it on the events before
  writing them.

`tests/testthat/test_fill_order.R` covers them, including a cutting written through
`write.events.SIPNET`.

How the generators here follow it:

| generator | step 1 | step 2 | step 3 |
|---|---|---|---|
| `russell_split_phases.R` | the Century package: `plot_system.csv` for missing plantings and harvests (the 1993 sudangrass uniformity crop included), its corn and tomato hand harvest samples for those crops' harvest fractions (the tomato's green fruit left in the field), the cutting and cover crop samples, the package's per-system medians for dates it does not give, its records for fertilization gaps, single applications missing from a season that has others (copied within the treatments that share synthetic N management) and 2014 fertilization, its logged herbicide incorporation passes, and its metadata for the irrigation method (furrow flood) and the 1993 and 2012 hay cuts; Tautges et al. 2019 for the corn and wheat N rates where the log has none, the wheat irrigation of every irrigated system, every corn and tomato season's irrigation amount (its "mm" read as inches), the organic 2008 sudangrass compost year the package lacks (annual compost; the nearest recorded year is copied), the tillage operations, the month of the wheat straw disking and the four fallow diskings of the wheat-fallow systems. Its fixes to package records are rows in `russell_source_corrections.csv`, with the evidence (see `runs/russell_ranch/events_treatments/README.md`) | the monitoring product within 25 km of Russell Ranch: tillage timing and intensity (`russell_monitoring_tillage.R`; it shows one pass in most gaps after a wheat harvest, two in 9 of 722, so the fallow diskings take only its intensity, and their even spacing through the fallow is an assumption); the irrigated corn and tomato seasons as a lower bound that rules out reading the paper's irrigation as centimetres, and their median last irrigation before harvest, which ends the corn and tomato schedule (it starts at planting); the sudangrass (F16) and alfalfa (P1) irrigation, which the paper does not give (`russell_monitoring_irrigation.R`); the shared harvest lookup the monitoring harvest product carries, for wheat, alfalfa and hay (`russell_harvest_lookup.csv`) | planting amounts: the generator's priors (ccmmf/scenarios `data/management_priors.yaml`, a processing tomato baseline from the UC Davis Cost Study 2023), a filled planting taking their median in its phase, as agreed on calibration#10; the monitoring planting medians near the site are close (0.0038 to 0.0053 kg C/m2 leaf C against 0.0034) |
| `us_bi1_build_events.R` | the stand's age (Paw U et al. 2018), so one stand for the run; the recorded 2020-06-04 mowing; about six cuttings a year (`delta-harvest-0010`); cutting dates read from the tower NDVI (Wang 2024 Fig. 3.1) and daily NEE (Hemes et al. 2019 Fig. S2) | the planting leaf C (median of the parcel's P1 plantings); the irrigation, kept as it was; the shared harvest lookup's P1 share for the cuttings, with nothing sent to litter (calibration#10) | |
| `us_bi2_build_events.R` | the site record: corn every year, UAN 118 kg N/ha once at planting, the 2019-09-11 harvest, silage, the dated winter flood windows; the 2019 and 2020 planting and fertilization days from Anthony and Silver 2021 Fig. 2 | the parcel's v5.0 planting and harvest days and planting leaf C where the record gives none; its 2021 and 2022 irrigation (v1.1); the US-Twt flood rule (70 mm every 7 d) that holds each winter flood; the shared harvest lookup's hay row for silage | |
| `us_twt_build_events.R` | Knox et al. 2016 for 2010-2015 and their medians for 2016; its disking and ring rolling, placed before every planting; the AmeriFlux WTD flood onsets and drains, 2010 to March 2017 | 2017-2023 events for parcel 590073; the flood rate and interval (70 mm every 7 d) that holds each WTD flood; leaf C at the Knox plantings | |

The Delta builders tag events by their own rule, which is narrower than `fill_order.R`'s
definition (there, the monitoring product for the field and season counts as `published`):

- A value from the monitoring product is `imputed` where the site record has the operation but
  not its date or amount (US-Bi2 planting and harvest days and its 2021 and 2022 irrigation, leaf C
  at the US-Bi1, US-Bi2 and Knox plantings, US-Bi1 irrigation), and `published` only where no site
  record covers the season (US-Twt 2017-2023).
- A date read from a figure is `derived` when it dates an operation the record has (the UAN
  application on the fertilization line of Anthony and Silver 2021 Fig. 2, the US-Twt flood
  onsets in the WTD record) and `imputed` when it infers one the record does not date (the US-Bi1
  cuttings read from NDVI and NEE).
- An amount from a rule is `imputed` (the 70 mm flood rule at US-Twt and US-Bi2).
- An event's class is the weakest of what it rests on, in the order published, derived, assumed,
  imputed. So a US-Twt flood onset, a WTD date carrying the rule's 70 mm, is `imputed`, and the
  US-Bi1 2020-06-04 cutting, a recorded date with the lookup's P1 fractions (0.85 removed, from
  IPCC, and nothing to litter, David's call), is `assumed`. Russell (`russell_split_phases.R`)
  tags its alfalfa cuttings `published`, or leaves them untagged, with the same fractions; making
  the two agree is a follow-up for calibration#15.

Harvests carry `harvest_lookup_row` and `harvest_fraction_note` for the fractions.

## Delta towers

What each file rests on, event by event. Counts are the committed files, built from
cal-val-data develop 8f88e95 and member 1 of the monitoring product.

### US-Bi1, Bouldin alfalfa, parcel 328163, 2017-2023 (58 events)

| events | what | class |
|---|---|---|
| 1 planting | 2017-01-01, P1, leaf C 0.00896323 kg C/m2, the median of the parcel's 6 P1 plantings in the monitoring product (planting v1.0, 2018-2023; the parcel's seventh planting, 2016, is F16). It sets the state of a stand that went in about 2013 (in alfalfa about three years when the tower went in on 2016-08-12; Paw U et al. 2018, Field Campaign Report, Appendix B, p. B-SI-8) and is not an operation: the roots start at seedling scale, so 2017 behaves as spin-up. Starting instead from an initial condition with a plant is David's call. The date is assumed; leaf C from the monitoring product is the weaker part, so the event is imputed | imputed |
| 39 cuttings | `us_bi1_cuttings.csv`, 6 a year and 3 in 2022, each `harvest_fractions(0.85, 0, 0, 0)`. 36 dated from the tower NDVI cycles in Wang 2024 (UC Berkeley PhD dissertation) Fig. 3.1, p. 52, to within about 3 to 5 days; 2017-04-23 and 2017-05-22 from the daily NEE in Hemes et al. 2019 Fig. S2a (accepted manuscript p. 45), which the NDVI record (from 2017-06-05) does not cover; 2020-06-04 recorded ("Mowed five days ago, baling today" on 2020-06-09, AmeriFlux BADM, `delta-harvest-0012`). The table's `note` column gives, for each date, the figure, panel and feature it is read from and how it was checked | 38 imputed, 1 assumed (2020-06-04) |
| 18 irrigation | the monitoring product's (irrigation v1.1, `irr_ens_001`), canopy, 142.86 mm each, as before. The site record has the field irrigated mainly below the surface from the adjacent ditches, with sporadic flash floods (`delta-irrigation-0008`, `0009`), and no dates or amounts | imputed |

Why 2022 has three cuttings: after the 2022-07-06 fall the 2022 panel of Fig. 3.1 never regrows to
the 0.6 to 0.7 NDVI canopy that precedes every other cutting. It stays at about 0.30 to 0.45
through September (with a gap in the record in early to mid August), rises slowly to about 0.50
by mid October, and falls to about 0.35 to 0.40 in late October and again in late December. Neither
fall is from a regrown canopy, so no cutting is written; the late October one could be a late
cutting or the start of grazing. 2022 is also the only year of the run in which the tower's annual
NEE is a net source (+307.6 g C m-2, FLUXNET-1F, cal-val-data). The Fig. 3.1 dates were digitized
from the figure image in the organization#298 research and checked by eye against the figure, not
re-digitized; the two Hemes dates were rechecked by digitizing Fig. S2a.

Removed: the old file's 7 P1 plantings and 7 harvests (the product's six, 2018-2023, and a 2017
fill), which kept only the removed share (0.75) and so reached SIPNET as `harv 0.75 0 0.25 1`,
killing the stand every year. Not written:
tillage (none), fertilization (none in the site record; the fertilization product's organic
amendments on P1 in some members, such as `ens_002` on 2020-11-15, are not used) and the winter
sheep grazing (`delta-grazing-0002`: no dates or stocking, and SIPNET has no grazing event).

### US-Bi2, Bouldin corn, parcel 565118, 2016-2023 (88 events)

| events | what | class |
|---|---|---|
| 8 plantings | one corn (F16) a year. 2019-05-01 and 2020-05-04 are read from the fertilization line of Anthony and Silver 2021 Fig. 2 (to within 1 to 2 days; UAN goes on at planting); 2019 also lies in the record's May-June (`delta-planting-0014`). The product has 2019-05-17 and 2020-04-05, the second a month before the application. The other years take the v5.0 day; the record gives only the year (`delta-planting-0012` to `0018`). The product labels 2016 G2; it is written as corn, assumed, to keep the field's continuous corn. Leaf C is the season's v5.0 F16 planting, 0.0041 to 0.0051 kg C/m2 (2016: the median of the parcel's 7, 0.00497966). Leaf C makes every planting imputed, the 2019 and 2020 dates being derived | 8 imputed |
| 8 fertilization | UAN, 118 kg N/ha (0.0118 kg N/m2, written as `nh4_n_kg_m2`; SIPNET adds NH4 and NO3 into one pool) on the planting day. The rate is published for 2017-2020 (`delta-fertilization-0013`, `0014`, Anthony and Silver 2021) and carried to 2016 and 2021-2023 | 2 derived, 6 imputed |
| 8 harvests | 2019-09-11 recorded (`delta-harvest-0016`; the paper delayed the 2019 harvest, so the product's 2019-10-03 is not ruled out); the other years the v5.0 day. Silage (`delta-harvest-0014`): `harvest_fractions(0.892, 0, 0.108, 1)`, the shared lookup's hay row in place of the F16 grain row (0.752), assumed, a proposal for David | 1 assumed, 7 imputed |
| 2 irrigation | the monitoring product's (irrigation v1.1, `irr_ens_001`), 2021-09-08 and 2022-10-16, 124.14 mm canopy each, kept as decided on 2026-07-16 (Akash and Alexey): the product's zero years are real zeros and these two stay. The record has the field irrigated through spud ditches (`delta-irrigation-0003`) but not on these dates; v5.0 has no irrigation rows for the parcel | imputed |
| 62 flood events | every winter flood the record dates, held by the US-Twt rule, 70 mm every 7 d from the first day of the window to its last, `method: "soil"`, "Flood irrigation" in the note: `delta-flooding-0012`, 2017-12-01 to 2018-02-28, a reported duration (Hemes et al. 2019), 13 events, 910 mm; `0013`, 2018-11-01 to 2019-03-31, and `0014`, 2020-11-01 to 2021-03-31, the field's November-March regime (Anthony and Silver 2024 Table 1) after that year's corn, 22 events and 1540 mm each; `0009`, 2019-12-01 to 2019-12-31, which bounds only the December 2019 onset, so the flood is held only through December, 5 events, 350 mm. The record gives no onset, drain or depth for any of them | imputed |

Water follows the 2026-07-16 decision (Akash and Alexey): Bouldin's water comes off a shallow
water table, and SIPNET does not draw water up from a water table, so a run with neither the
floods nor the flood configuration goes too dry. The winters the record does not date (2016-17,
2021-22 and 2022-23, and the undated autumn flooding of `delta-flooding-0008`) have no flood events.

Removed: the product's 2019 G6 cycle (planted 2019-02-05, harvested 2019-05-22 with the corn's
fractions five days after the corn went in, while the field was flooded and anoxic until mid
March 2019); the 9 fertilization events built from the fertilization product (8 rows and a 2017
fill, 172 to 343 kg N/ha a year in member 1, 343 in 2019). Not written: the product's tillage
(v5.0 has 7 detections, 2017-2023); the spud ditch irrigation (`delta-irrigation-0004` to `0007`),
which is subsurface water left to the water table and the run's flood configuration; the record's
2019 tillage and disking (`delta-tillage-0003`, May-June; `0004`, September-October) and
2020-06-09 furrowing (`delta-furrowing-0001`), whose dates and intensities are not resolved.

**Open: the run's flood configuration.** The events stand in for the floods only. The run still
needs SIPNET's flood setup (`--flooding` and `--anaerobic`, with a low `waterDrainFrac` to hold the
water table up), which is not in this repository's run config (`runs/us_bi2/us_bi2_user_config.yaml`,
`runs/template.xml`). Whether `0009` should be held to the end of March 2020, like the November-March
regime of `0013` and `0014`, is also open.

### US-Twt, Twitchell rice, parcel 590073, 2010-2023 (404 events)

| events | what | class |
|---|---|---|
| 2010-2015 plantings, harvests, fertilization | Knox et al. 2016 Table 1 through the cal-val-data rows; a reported window takes its first day. Leaf C at planting is the median of the parcel's 5 R1 plantings in the monitoring product, 0.02455947 kg C/m2. Harvests `harvest_fractions(0.5, 0, 0.5, 1)`: grain removed, straw chopped and left (the 2014 residue treatment is not reported); the 0.5 comes from `prior:rice_harvest_index`, not from Knox. Fertilization N is computed from the reported rate (lb/ac) and the product grade's %N. Every event notes its Knox row | plantings imputed (leaf C from the monitoring product), harvests assumed (fractions from the prior), fertilization derived (N from rate and grade) |
| 2016 planting, harvest, fertilization | no record: the medians of the Knox years (2016-04-18, 2016-10-06; 100 lb/ac of 15-15-15 on 2016-05-30, the 2013-2015 regime). Tagged `imputed` (was `assumed`) | imputed |
| 2017-2023 plantings, harvests, fertilization | the monitoring product (planting and harvest v1.0, fertilization v1.0 `ens_001`), its four harvest fractions written out (0.8, 0, 0.2, 1). 2017, which the planting and harvest products lack, takes the median day of its other R1 years and the median of each amount (David's rule): leaf C 0.02455947 kg C/m2, fractions 0.8, 0, 0.2, 1, and 133.7 kg N/ha mineral N with no organic N or C, since one of the six R1 applications carries organic N. The fertilization events now carry the product's organic C, which the old file left out (0.44 kg C/m2 with 0.019 kg N/m2 on 2018-02-02) | published; 2017 imputed |
| 14 flood onsets | dated from the AmeriFlux US-Twt BASE-BADM 7-5 water table record, `us_twt_wtd_water_dates.csv`: 7 growing season and 7 winter onsets, 2010-06-15 to 2016-11-17. The date is derived but the 70 mm is the rule's, so each onset is imputed and its `source` names both | imputed |
| 179 flood repeats | each WTD flood held from its onset (or, for the winter flood in place on 2010-01-01, from the first day) to its WTD drain by 70 mm every 7 d, the mean amount (69.7 mm) and modal interval of the product's 129 flood events for the parcel in 2017-2023. The 2016-11-17 winter flood now runs to its drain on 2017-03-11 (17 events) instead of stopping at 2016-12-31 (7) | imputed |
| 137 monitoring irrigation | the product's irrigation v1.1 (`irr_ens_001`), 2017-2023: 129 flood events and 8 canopy events of 157.44 mm (four in July-October 2017, a year the planting product has no crop for the parcel, and four in 2022, when it has G2), kept as canopy | published |
| 28 tillage | Knox's disking (`delta-tillage-0001`, tillage_eff 0.5) and ring rolling (`delta-tillage-0002`, 0.2) at 21 and 7 d before every planting, the monitoring years included (decided 2026-08-29, literature first). Ring rolling in 2017-2023 cited `delta-tillage-0001` before. In 2010-2015 Knox reports the operations and only the offsets are assumed; in 2016-2023 the practice is carried from Knox 2010-2015 into years no site record covers and dated from that year's imputed or monitoring planting | 12 assumed (2010-2015), 16 imputed (2016-2023) |

Leaf C changed in two places when the means became medians (David's rule, median not mean, for
values backfilled from the monitoring product): the US-Bi1 planting from 0.00994096 to
0.00896323 kg C/m2 and the US-Twt 2017 fill from 0.02618692 to 0.02455947 kg C/m2. The 2017 fill's
fertilization went from a mean of 114.4 kg N/ha mineral N plus 31.1 kg N/ha and 0.073 kg C/m2
organic to the medians above. The flood rule still takes the mean amount (69.7 mm); its median,
69.5 mm, rounds to the same 70.

**Open questions for David (US-Twt from 2017).** The monitoring years differ from the Knox years
in ways nobody has decided:

- Harvests remove the product's 0.8 of the aboveground biomass (0.8, 0, 0.2, 1), where the Knox
  years leave the straw (0.5, 0, 0.5, 1).
- Mineral N is 125 to 153 kg N/ha a year in the product's rice years (2018-2021, 2023; 115 in
  2022, which it calls G2), against 17 to 80 in Knox's 2010-2015.
- Member 1 adds 0.44 kg C/m2 of organic C with 186 kg N/ha of organic N on 2018-02-02, in the
  season Knox's fields are reflooded, although the file has no flood events between 2017-03-09
  and 2018-05-30.
- The 2017 fill: a mean took a share of that organic-only row; the median now leaves it out.
  Which is meant?
- 2017 is a rice year (the 2017-05-20 planting fill) with no growing season flood: the product's
  only 2017 irrigation is four canopy events of 157.44 mm, July to October.
- Should Knox's disking and ring rolling carry into 2016-2023 at all (16 events), or should those
  years take the product's tillage detections, or none?

All flood water is `method: "soil"` (SIPNET method 1), with "Flood irrigation" in the note:
SIPNET's flood method (2) is a placeholder the build in use rejects, and `write.events.SIPNET`
writes anything but `soil` as canopy irrigation (method 0), which evaporates part of each
application at once. Ponding comes from the run's `FLOODING` setting.

`us_twt_wtd_water_dates.csv` holds the flood onsets and drains derived on 2026-08-20 from the
AmeriFlux US-Twt BASE-BADM 7-5 WTD series (commits f9202d5 and c543f9a): an onset is the first of
14 consecutive observed days with the water table at or above the surface, short breaks of up to
7 days merged; a drain is the first observed day back below it. Its notes are those commits'
per-event notes. The 2017-03-11 drain was not written then, as it fell after the 2010-2016 window;
it is the onset plus the 114 flooded days that note gives. The derivation itself, and the BADM
data, are not in this repository: **re-deriving the table from `AMF_US-Twt_BASE-BADM` is a
follow-up.**

The monitoring product does record tillage for this parcel (tillage v1.0 has 5 NDTI detections
in 2018-2022, v5.0 has 6 in 2017-2022), although the 2026-08-29 merge said it records none.
Knox's pattern is carried forward instead, as decided then; whether to use the detections is
open.

## Notes

- The monitoring product's planting and harvest v1.0 do not cover parcel 590073 before 2017;
  their 2016 export is truncated at `site_id` 99999. That is why US-Twt 2010-2016 is built
  from the literature instead.
- `validate_events_json` needs `jsonvalidate` installed or it silently returns `NA` rather
  than validating, and it needs `events_schema_v0.1.1`, which not every PEcAn install ships:
  one with only v0.1.0 logs an ERROR for every file here, the old ones included, and
  `write.events.SIPNET` carries on. The three Delta files validate against v0.1.1 from the PEcAn
  source (`modules/data.land/inst/events_schema_v0.1.1.json`).

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

### Two version schemes in the same bucket -- don't mix them up

`carb` carries two independently versioned prefixes, and they sit on opposite sides of these
scripts:

| prefix | what | latest | relation to event_prep |
|---|---|---|---|
| `management/<product>/vN.M` | upstream monitoring product | per product: planting, harvest, tillage and irrigation `v5.0`, fertilization `v2.0` | **input** -- what `pull_inputs.sh` reads |
| `calval_sa_inputs/vN.M` | staged IC / met / events for the SA runs | **`v0.3`** (2026-08-20) | **output** -- where the results get published |

So `v0.3` is the latest *staged run inputs*, not a monitoring product version, and it is
downstream of everything here: `management/` -> these scripts -> `runs/*/events.json` ->
`calval_sa_inputs/v0.3/<site>/`. Bumping `calval_sa_inputs` does not change what to pull, and
the product versions below are unrelated to it. The v0.3 README on S3 records the same chain
under "Event provenance".

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
| planting | `v1.0`; `v5.0` for US-Bi2 | `v2.0` |
| harvest | `v1.0`; `v5.0` for US-Bi2 | `v2.0`, `beta` |
| irrigation | `v1.1` | `v1.0`, `v2.0`, `v5.0` |
| tillage | `v1.0` | `v5.0` |
| fertilization | `v1.0` | `v2.0` |

These match the `source` strings recorded in each event, so an events.json says which
version produced it. US-Bi2 reads planting and harvest `v5.0` (pinned in `pull_inputs.sh`; the builder reads v5.0's schema), which has the
2017 season `v1.0` lacks. A newer version is not a drop-in replacement: for parcel 565118,
fertilization `v2.0` moves every event date and puts all N in NH4 with NO3 at zero, where
`v1.0` splits N evenly. Moving a pin is a deliberate change — override
`FERTILIZATION_VERSION` and friends, re-run, and diff `runs/*/events.json` before keeping it.

`russell_monitoring_tillage.R` and `russell_monitoring_irrigation.R` read outside these pins:
tillage, irrigation, harvest and planting `v5.0` and the crop table `crops/v4.1` (paths in
their headers), which give `monitoring_tillage_near_russell.csv` and
`monitoring_irrigation_near_russell.csv` in `runs/russell_ranch/events_treatments/`.

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
| `management/planting/v5.0/`, `management/harvest/v5.0/` | `$PRODUCTS_INVENTORY/management/{planting,harvest}/v5.0/` | `us_bi2_build_events.R` |
| `management/tillage/v1.0/` | `$PRODUCTS_INVENTORY/management/tillage/v1.0/` | none of the builders; kept for checking the US-Twt tillage |
| `management/fertilization/v1.0/` | `$EVENT_OUTPUT_DIR/fertilization.parquet/` | `us_twt_build_events.R` |

Fertilization is Hive-partitioned by `event_member_id`; it is opened as an Arrow dataset, so
the local name `fertilization.parquet` is a directory, not a file.

Irrigation is 121 shards totalling roughly 4 GB, so only the shards that can hold the
requested parcels are fetched.

### Full run, from nothing

```bash
export CCMMF_BASE=/path/to/scratch
tools/event_prep/pull_inputs.sh                 # the three Delta parcels, about 1.7 GB
Rscript tools/event_prep/extract_parcel_csvs.R us_bi1 328163
Rscript tools/event_prep/extract_parcel_csvs.R us_bi2 565118
Rscript tools/event_prep/extract_parcel_csvs.R us_twt 590073
Rscript tools/event_prep/us_bi1_build_events.R ../cal-val-data/data/managements.csv runs/us_bi1/events.json
Rscript tools/event_prep/us_bi2_build_events.R ../cal-val-data/data/managements.csv runs/us_bi2/events.json
Rscript tools/event_prep/us_twt_build_events.R ../cal-val-data/data/managements.csv runs/us_twt/events.json
```

Run from an empty `CCMMF_BASE` on a laptop (pulled 2026-11-07) with cal-val-data develop 8f88e95,
this reproduces the three committed files byte for byte. The old chain did not: its US-Twt
steps never met (the monitoring build is labelled `us_twt`, the literature build `US-Twt`) and
its WTD dates were a hand edit.

### Gotchas

- **Irrigation shard names are nominal ranges and they overlap.** Twelve shards have a name
  bracketing parcel 328163. A parcel inside a shard's named range is not necessarily in that
  shard: `241361_602889.parquet` covers 565118 by name but holds none of its rows. Pull every
  matching shard and filter on `parcel_id`, which is what these scripts do.
- **Column types are not stable across the per-year files.** `site_id` is `int32` in planting
  and `string` in harvest, and `date` is `character` in `planting_statewide_2016` but `Date`
  from 2018 on. Stacking those with `rbind` silently yields `NA` dates rather than an error,
  so `extract_parcel_csvs.R` normalises both to character per file first.
- **Planting and harvest v1.0 have no 2017.** That is why US-Twt fills a 2017 cycle from the
  median day of year of its other years. v5.0 has 2017 (2017-05-05 and 2017-11-08 for US-Twt);
  US-Bi2 takes it from there.
- **v5.0 keys rows on `parcel_id` and calls the crop `crop_code`**, where v1.0 has `site_id` and
  `code` or `CLASS_SUBCLASS`, so `extract_parcel_csvs.R` reads only v1.0; `us_bi2_build_events.R`
  reads v5.0 itself (`v5_parcel_rows()` in `delta_inputs.R`).
- **v5.0 irrigation has no rows for parcel 565118** (its shard `564_567501.parquet` holds 565117
  and 565119 but not 565118), which is why US-Bi2 has no irrigation events.
- The fertilization product has rows for US-Bi1 (an F16 application in 2016, and organic
  amendments on P1 in some members from 2020); the US-Bi1 and US-Bi2 builders use none of it.
