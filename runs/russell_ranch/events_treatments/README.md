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
| irrigation, irrigated systems | every event kept | 18 events outside any one-season cash-crop window dropped (below) |
| zero-N applications (P, K, Zn) | written as 0/0/0 events, two dated an invented 1999-01-01 | dropped; SIPNET reads only N and C |

Fertilization is rebuilt entirely from `operations_fertilizers.csv` and
`operations_compost.csv`. Planting, harvest and irrigation are the generator's events,
assigned to a phase by plot id; **their amounts are still the generator's prior fills**
(`prior_filled` on each event): planting leaf C from a processing-tomato baseline for every
crop, harvest fractions drawn from a grain-harvest prior, and irrigation from a sprinkler
prior placed at each cash-crop window midpoint (median 480 to 560 mm per crop year). Those are
the remaining weaknesses listed when ccmmf/uncertainty#6 was closed; this change does not
fix them.

Each irrigation event goes to the phase whose cash-crop window has the nearest midpoint. A
window is one season: from a cash-crop planting to the first harvest of the same crop
within 365 days. A planting with no such harvest gets no window. The generator also paired
a planting in one phase with a harvest in the other and put irrigation at that midpoint,
in winter or in a year the phase had no crop. Those 18 events fall outside every window and
are dropped as generator artifacts (`conv_corn_tomato` 4, `conv_wheat_tomato` 3,
`org_corn_tomato` 3, the irrigated wheat systems and `leg_corn_tomato` 2 each; the script
prints the count per treatment). Unbounded windows had stacked them onto one phase, for
example 1873 mm in `conv_corn_tomato` `tomato-corn` 1999. A phase-year whose only
irrigation was such an artifact now has none (for example `conv_corn_tomato` `corn-tomato`
1998 and 1999). Nothing is filled in.

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

## Synthetic N and unplaced records

- Excel turned one plot id in `operations_fertilizers.csv` into a date. `5-Jan` is plot 1-5
  (Conventional Wheat/Tomato, 11/5/2011, Can_27, 111.97 kg N/ha). The script maps it back
  before the phase lookup.
- The 2011 wheat pre-plant on the `conv_wheat_tomato` `wheat-tomato` plots (1-5, 4-3,
  7-9) is listed on 11/5 and again on 11/14 at the same 111.97 kg N/ha. Every other wheat
  year has one. As with compost, it is kept once per plot on the earlier date, so
  `wheat-tomato` 2011 carries 330.7 kg N/ha rather than 405.35. The script drops it from an
  explicit list of known duplicate records rather than by a rule, because split
  applications are real: `conv_corn_tomato` 1996 tomato got 56.55 kg N/ha on both 4/16 and
  5/13.
- Left as recorded, but likely a plot mislabel in the source: the spring 2011 urea topdress
  (3/24/2011, 56.2 kg N/ha) is recorded on the same plots, which grew tomato that year.
  `wheat-tomato` therefore gets it, and `tomato-wheat`, which harvested wheat in 2011, gets
  no N that year.
- Two operation rows name a plot that `plot_system.csv` does not place in that system. The
  script prints both and leaves them out; no event depends on either:
  - `operations_planting.csv`: cover crop seeded on plot 7-9 under Irrigated Wheat/Legume,
    11/2/2002. Plot 7-9 is a Conventional Wheat/Tomato plot.
  - `operations_harvest.csv`: tomato harvested on plot 6-9E under Legume/Corn/Tomato,
    8/19/2003.

## Merging multi-day operations

The package often records one planting or harvest on several dates: the three plots done on
different days, or the same plots over a multi-day job (wheat "Harvest" on two days then
"Swath1"; corn "Machine Harvest" then "Cleanup"). Same-crop operations in a phase-year are
merged when they fall within 14 days of the first or touch disjoint plots. The merged event
takes the date most plots share (earliest on a tie) and the mean of the generator's amounts,
and lists the original dates in `merged_dates`. Alfalfa cuttings, about a month apart, stay
separate.

Left as recorded: corn replanted four weeks later (`conv_corn_tomato` 1998;
`org_corn_tomato` and `transitional` 2013, twice in organic).

`operations_planting.csv` lists the 2003 and 2005 tomato transplanting in `org_corn_tomato`
under plot 6-8, two days before its own corn seeding, and none under 8-8. `plot_system.csv`
has 6-8 in corn and 8-8 in tomato both years, and 8-8 has the tomato harvest samples, so
the script moves those two records to 8-8. Before, the corn phase got a tomato planting
that was never harvested.

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
