# Russell Ranch treatment events

One `events.json` per Tautges et al. (2019) treatment **and rotation phase**, 1993-2013,
23 files across 12 treatments. These are treatments (farming systems run side by side) and
phases (the same system on offset rotations), not ensemble members. Using them as ensemble
members would conflate treatment effect with management uncertainty.

Built by `tools/event_prep/russell_split_phases.R` from `generator_stacked/` and the Century
Experiment package (Wolf et al. 2018, `10.1002/ecy.2105`, supporting information
`RR_2014_datasets/`). `phase_year_summary.csv` lists every phase-year's cash crops, mineral
N, compost C and N, and irrigation so the files can be reviewed without opening them.

## Why one file per phase

Each Century system is six plots: two sets of three on offset rotations, so in any year one
set grows corn and the other tomato (or wheat and fallow). The earlier generator wrote both
sets into one file, so one simulated field was planted with both crops, fertilized for both
and harvested for both every year. In `conv_corn_tomato` 1996 that was 395 kg N/ha against
235 on the corn plots and 159 on the tomato plots. The package carries a plot id on every
operation, and `plot_system.csv` gives each plot's phase, which is what separates them. To
represent a treatment, run both of its phases; observations are per treatment.

`transitional` has one phase only, so it has one file.

## What changed from `generator_stacked/`

| | stacked generator | per-phase files |
|---|---|---|
| phases | merged into one field | one file each |
| synthetic N | 25% NH4, 25% NO3, **50% organic N with no C** | all mineral N (`nh4_n_kg_m2`), field average over the phase's plots |
| compost (`org_corn_tomato`, `transitional`) | no amount, so both files failed the schema and were withheld | organic C and N from the package (below) |
| multi-day operations | one harvest per recorded date, so a crop was harvested 2 to 3 times | merged into one event (below) |
| irrigation, rainfed wheat | 18 sprinkler events of ~600 mm per system | none; Tautges Table 1 lists irrigation "None" |
| zero-N applications (P, K, Zn) | written as 0/0/0 events, two dated an invented 1999-01-01 | dropped; SIPNET reads only N and C |

Fertilization is rebuilt entirely from `operations_fertilizers.csv` and
`operations_compost.csv`. Planting, harvest and irrigation are the generator's events,
assigned to a phase by plot id; **their amounts are still the generator's prior fills**
(`prior_filled` on each event): planting leaf C from a processing-tomato baseline for every
crop, harvest fractions drawn from a grain-harvest prior, and irrigation from a sprinkler
prior placed at each cash-crop window midpoint (median 480 to 560 mm per crop year). Those are
the remaining weaknesses listed when ccmmf/uncertainty#6 was closed; this change does not
fix them.

## Compost

`wet tons/acre x 0.22417 (US short ton per acre to kg/m2) x %C or %N`, with %C and %N from
`compost_analyses_summary.csv` for the year applied (in-house Costech replicates averaged
where present, as Tautges used; otherwise the one lab reported). The percentages are applied
to the reported tonnage without a moisture correction because that is the basis that
reproduces the paper:

| check | these files | Tautges et al. 2019 |
|---|---|---|
| compost C per application year, organic system | 2.09 Mg C/ha | 40.4 Mg C/ha over 19 years = 2.13 |
| compost N per application year | median 168 kg N/ha (111 to 505) | 150 to 200 kg N/ha |
| 4 tons/acre in t/ha | 8.97 | "annual inputs of 9 t/ha" |

- %C is measured in 13 years and %N in 9. Years without an analysis (C: 2000, 2005,
  2006, 2010; N also 1994 to 1997) take the mean over measured years and the event is tagged
  `provenance_class: assumed`.
- **The package has no compost records for some years**, although the paper describes
  annual application: 1998, 1999 and 2008 in both organic phases, plus 2010, 2012 and 2013
  in `corn/CC-tomato/CC` and 2011 in `tomato/CC-corn/CC`; `transitional` lacks 2008 and
  2011. Those years carry no compost here; nothing is filled in.
- `operations_compost.csv` lists every plot's history twice. The copies agree except for
  2005 on plots 2-3, 6-4 and 6-8, dated 4/20 in one and 5/20 in the other at the same
  4 tons/acre. Compost is kept once per plot and year, on the earlier date, which falls in
  the "March or April" window Tautges gives. The curated `managements` in cal-val-data
  repeat the same rows, so summing them there double counts compost.

## Merging multi-day operations

The package often records one planting or harvest on several dates: the three plots done on
different days, or the same plots over a multi-day job (wheat "Harvest" on two days then
"Swath1"; corn "Machine Harvest" then "Cleanup"). Same-crop operations in a phase-year are
merged when they fall within 14 days of the first or touch disjoint plots. The merged event
takes the date most plots share (earliest on a tie) and the mean of the generator's amounts,
and lists the original dates in `merged_dates`. Alfalfa cuttings, about a month apart, stay
separate.

Left as recorded: corn replanted four weeks later (`conv_corn_tomato` 1998;
`org_corn_tomato` and `transitional` 2013, twice in organic), and plot 6-8 in
`org_corn_tomato` showing a tomato transplant two days before corn seeding in 2003 and 2005.

## Checks

- All 23 files validate against `events_schema_v0.1.1` from PEcAn `develop` (the stacked
  organic and transitional files still fail it), and `PEcAn.SIPNET::write.events.SIPNET`
  writes an `events.in` for each, with organic C on all 42 compost events.
- Every phase-year's mineral N, compost C and compost N (261 nonzero totals) recomputed
  independently from the package: 0 differences.
- Rerunning the script reproduces every output byte for byte.

## Rebuild

```
Rscript tools/event_prep/russell_split_phases.R \
  runs/russell_ranch/events_treatments/generator_stacked \
  <path>/RR_2014_datasets \
  runs/russell_ranch/events_treatments
```

`RR_2014_datasets/` is the zip in the data paper's supporting information (also attached to
the Zotero item for `10.1002/ecy.2105`).

## Which treatment the run uses

The SCC run (`runs/russell-ranch-1992`) still uses the stacked `conv_corn_tomato`. Moving it
to `conv_corn_tomato__corn-tomato` and `__tomato-corn` is the next step.
