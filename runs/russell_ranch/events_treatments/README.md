# Russell Ranch treatment events

One `events.json` per Tautges et al. (2019) treatment **and rotation phase**, 1993 to 2014,
23 files across 12 treatments. These are treatments (farming systems run side by side) and
phases (the same system on offset rotations), not ensemble members. Using them as ensemble
members would conflate treatment effect with management uncertainty.

Built by `tools/event_prep/russell_split_phases.R` from `generator_stacked/` and the Century
Experiment package (Wolf et al. 2018, `10.1002/ecy.2105`, supporting information
`RR_2014_datasets/`). `phase_year_summary.csv` lists every phase-year's cash crops, mineral
N, compost C and N, and irrigation so the files can be reviewed without opening them.

Events the operation logs lack are filled, and dates no record gives are imputed, in the
order set out in [`tools/event_prep/README.md`, "Filling missing events"](../../../tools/event_prep/README.md#filling-missing-events):
the package's own records first. Amounts are a different matter: 2014 fertilization copies the
package's own records, while filled planting and irrigation amounts are medians of the
generator's priors (see "Imputed dates and amounts"). Every imputed event carries
`provenance_class: imputed` and a `provenance_note` that names the rule and the median, or the
copied season, it used.

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
| irrigation, irrigated systems | every event kept | 22 generator artifacts dropped: 17 events outside any one-season cash-crop window and 5 more than 10 days from the midpoint of the season they fall in; 61 seasons had none: 51, alfalfa production years included, get the system's usual irrigation; 5 irrigated wheat seasons in Tautges' no-irrigation years and the 5 sudangrass green manure seasons do not (below) |
| harvest fractions | drawn from a grain-harvest prior | harvest lookup rows; alfalfa cuttings leave the stand alive (below) |
| cover crops | planted, never terminated | end on their incorporation date, all to litter (below) |
| plantings and harvests missing from the logs | none, so crops were harvested that were never planted and planted ones never harvested | filled from `plot_system.csv` and the alfalfa cutting samples (below) |
| 2014 | none (the logs end in 2013) | built from `plot_system.csv` and the cutting samples, fertilization imputed (below) |
| `alf_corn_tomato` before 2012 | no events | the plots' Irrigated Wheat/Legume history (below) |
| zero-N applications (P, K, Zn) | written as 0/0/0 events, two dated an invented 1999-01-01 | dropped; SIPNET reads only N and C |

Fertilization is rebuilt from `operations_fertilizers.csv` and `operations_compost.csv`.
Planting, harvest and irrigation are the generator's events, assigned to a phase by plot id,
plus what the logs miss. **Planting and irrigation amounts are still the generator's prior
fills** (`prior_filled` on each event): planting leaf C from a processing-tomato baseline for
every crop, and irrigation from a sprinkler prior placed at each cash-crop window midpoint
(median 480 to 560 mm per crop year). A filled planting or season takes the median of those
same priors, so it matches its neighbours. Those priors are remaining weaknesses listed when
ccmmf/uncertainty#6 was closed.

## Harvest fractions

Every harvest takes its crop's row of the harvest lookup the other calibration sites use
(rows as given on calibration#10, the same values the monitoring harvest product carries),
named in `harvest_lookup_row`. The generator's draw from a grain-harvest prior is dropped.
Each of these takes 100% of the biomass as removed or to litter, so it ends the crop.

| crop | lookup row | above removed | above to litter | below removed | below to litter |
|---|---|---|---|---|---|
| corn | F16 | 0.752 | 0.248 | 0 | 1 |
| tomato | T32 | 0.33 | 0.67 | 0 | 1 |
| wheat | G2 | 0.713 | 0.287 | 0 | 1 |
| alfalfa, last cutting before another crop | P1 | 0.85 | 0.15 | 0 | 1 |
| alfalfa, intermediate cutting | P1 share | 0.85 | 0 | 0 | 0 |
| sudangrass | none | 0 | 1 | 0 | 1 |
| cover crop | none | 0 | 1 | 0 | 1 |

- Alfalfa is cut six or seven times a year. With the full P1 row the roots went to litter
  at the first cutting, so SIPNET killed the stand on 2013-04-10 and the later cuttings acted
  on nothing. An intermediate cutting now removes the P1 aboveground share and leaves the
  stubble and roots alive (David on calibration#10). Only the last cutting before the next
  planting would take the full row; the stand planted 2012-10-04 is still growing at the end
  of 2014, so all 13 cuttings in the files are intermediate. The monitoring product has one
  P1 harvest a year with the full row, so it has no cutting values to use instead.
- Sudangrass has no row and needs none. In 2008 and 2009 it "was sampled prior to plowing
  under at every harvest and no hay was removed from the plots" (Wolf et al. 2018 metadata),
  so its harvests send everything to litter.

## Cover crop termination

The package has no termination or tillage records. The data dictionary for
`wcc_harvests_all.csv` gives its `date` as "the date of the WCC incorporation" (the methods put
the biomass sample in the week before it). Each cover crop ends with a harvest event that
removes nothing and sends all biomass, above and below ground, to litter. Of 124 cover crop
plantings (98 from the generator, 26 filled below):

- 109 end on that date, the one most of the phase's plots share.
- 2 have no sample and end on the cover crop harvest date in `plot_system.csv`, which
  equals the sample date in 342 of 353 plot-years (`leg_corn_tomato` 2006-04-25,
  `rf_wheat_legume` 2014-03-13).
- 7 have no usable date and are imputed (below): the five 2004 cover crops in the corn and
  tomato systems, whose recorded date is 5/17 for every plot of every system, after the 5/2
  and 5/5 corn and tomato plantings, so it cannot be the incorporation; `transitional`
  planted fall 1999, with no date in either file; and `irr_wheat_legume` `CC-wheat` planted
  2007-12-12.
- 6, planted in fall 2014, are still growing when the files end.

## Filled from `plot_system.csv` and the cutting samples

`plot_system.csv` records every plot-year's planting and harvest, and
`alfalfa_harvests_all.csv` has a sample "at each alfalfa cutting". The operation logs miss
some of these and stop at the end of 2013. A recorded operation is filled when the phase has
no event of the same crop within 30 days (7 days for a cutting), dated by the day most of the
phase's plots share (the first day where a range is given), with `source` naming the file.

| | 1993 to 2013 | 2014 |
|---|---|---|
| plantings | 47: wheat 14, tomato 9, corn 4, cover crop 20 | 21: wheat 6, tomato 5, corn 4, cover crop 6 |
| harvests | 32: wheat 14, corn 7, tomato 6, sudangrass 5 | 15: wheat 6, tomato 5, corn 4 |
| alfalfa cuttings | none missing | 7 |

- The pre-2014 plantings are whole seasons the planting log lacks, at least 336 days from
  any logged planting of the same crop: fall 1998 and fall 2001 wheat in the wheat systems,
  1994 and 1999 tomato in the corn and tomato systems, corn in `conv_corn_tomato` 2002,
  `leg_corn_tomato` and `org_corn_tomato` 1998 and `transitional` 2006 (below), and fall
  1998, 2001 and 2004 cover crops. Before, 25 harvests had no planting before them.
- A filled planting takes the median amounts of the generator's plantings of the same crop
  in the phase (`prior_filled` says which and how many).
- A cash crop that `plot_system.csv` records within 30 days of a logged planting of another
  cash crop is a conflict between the files. The script prints it and does not fill it, so
  one field is never planted with two cash crops. None remains.
- `transitional` grew corn in 2006, not tomato. `plot_system.csv` lists corn planted
  2006-05-25 and harvested 2006-09-13 ("Corn planted instead of tomato"), and
  `corn_harvests_all.csv` has the 2006 corn samples, dated 10/24/2006, while
  `tomato_harvests_all.csv` has none that year. The planting and harvest logs record a tomato
  transplanting and harvest on 5/25 and 9/13 on its three plots. The script drops those six
  records and the generator's two tomato events from an explicit list, and the corn planting
  and harvest are filled from `plot_system.csv`.
- A cash crop planting with no same-crop harvest within 365 days takes the plot_system
  harvest date. A planting followed within 30 days by another of the same crop is a replant
  and is not filled. For example, the 1998 `conv_corn_tomato` tomato has no harvest
  operation, while `plot_system.csv` dates it 1998-08-14 and `tomato_harvests_all.csv` has
  its samples.
- Crops planted in fall 2014 (wheat, cover crops) are still growing when the files end.
- Left out: the 1992 and 1993 sudangrass uniformity crops grown before the experiment
  (`plot_system.csv` lists the 1993 one). The files start with the first experiment
  operations in fall 1993.
- `operations_harvest.csv` also lists the 7/1/1999 Rainfed Wheat/Legume wheat harvest under
  plot 7-3, a `wheat-CC` plot that grew a cover crop that winter; the three `CC-wheat` plots
  carry the harvest. The script drops the 7-3 row from an explicit list, as it does the
  repeated fertilizer record below.

## Imputed dates and amounts

Where neither the logs nor `plot_system.csv` give a date, it comes from the package's own
records for the same system (the site's when the system has fewer than five), following the
order in `tools/event_prep/README.md`. Its step 2, the monitoring product, was not needed: the
package's own records and per-system medians gave every filled date. Amounts differ by kind:
2014 fertilization copies the package's own records, while a filled planting's amounts and a
filled season's irrigation are medians of the generator's priors (decisions 3 and 5 on
calibration#10; the irrigation amounts are open, see "Open" below).

| what | rule | events |
|---|---|---|
| cover crop end, a cash crop follows | the system's median gap between a recorded cover crop end and the next cash crop planting: 37 days in `org_corn_tomato` (n = 37), 42 in `leg_corn_tomato` (n = 25) and `transitional` (n = 11) | 6 (the 2004 five and `transitional` 1999) |
| cover crop end, no cash crop follows | the system's median day of a recorded cover crop end: day 96 in `irr_wheat_legume` (n = 14) | 1 (2008-04-05) |
| unharvested wheat | the median day of a recorded wheat harvest, day 182 (about 1 July), all biomass to litter, `not_harvested: true` | 2 |
| 2014 fertilization | the most recent same-crop season of the treatment with fertilization records that land in 2014 once shifted to the 2014 planting | 17 |
| irrigation of a season with none | the treatment's median season total for that crop, one event at the season midpoint | 51 |

- Unharvested wheat: the `org_corn_tomato` `corn/CC-tomato/CC` wheat planted 2011-11-17,
  which `plot_system.csv` says was "NOT harvested for wheat in 2012", ends 2012-06-30
  (`org_corn_tomato` has two wheat harvests, so the site median applies). The
  `irr_wheat_legume` `wheat-CC` wheat planted 2007-12-15 ends 2008-06-30.
- The December 2007 `irr_wheat_legume` plantings conflict with `plot_system.csv`, which says
  "IWL was fallow from 2007-2012". `operations_planting.csv` records the seeding, so the
  plantings are kept and given imputed ends.
- 2014 fertilization: only copied events that land in 2014, inside the 2014 season, are kept,
  and a season none of whose records would land there is never used as the template, because
  the fertilizer log has gaps. It has no 2013 corn N in any corn and tomato system, though it
  has two corn applications a year in 2005 to 2007, so 2014 corn copies 2007 corn. A partial
  gap is skipped the same way: the `irr_wheat_fallow` `fallow-wheat` wheat planted 2012-11-12
  has only its 2012-10-29 preplant, which would land in 2013, and no spring 2013 topdress
  (its 2009 and 2011 wheat had one), so the `wheat-fallow` 2014 harvest year copies the
  2011-planted season's 2012-03-26 urea to 2014-03-20 (56.2 kg N/ha). `alf_corn_tomato` has
  no corn before 2014 and copies `conv_corn_tomato`'s. A treatment whose log has no
  fertilization for a crop gets nothing; that includes `leg_corn_tomato` corn, which has no
  mineral N in the log in any year (see "Open" below). The shift runs from the copied
  season's first planting, not a replant: the `org_corn_tomato` 2014 compost lands on
  2014-03-17, 29 days before the 2014-04-15 corn planting, as the 2013-02-24 compost was 29
  days before the 2013-03-25 planting (replanted 5/15 and 6/1).
- Generator irrigation artifacts: the generator put one event at the midpoint of a window per
  planting, sometimes paired with the wrong harvest (one in the other phase or a year later)
  and once per planting of a replanted crop. 22 such events are dropped: 17 fall outside
  every one-season window, and 5 sit more than 10 days from the midpoint of the season they
  fall in (25.5 to 78.5 days). Those 5 are the later replant windows' events (2 in
  `org_corn_tomato` 2013, 1 in `transitional` 2013) and two winter events in
  `conv_wheat_tomato` wheat seasons from a tomato planting paired with the next year's harvest
  (`wheat-tomato` 1995-12-19, `tomato-wheat` 1998-12-26). The 185 kept events all sit within
  2 days of their season's midpoint.
- Irrigation: 61 seasons in irrigated systems had none: the filled seasons, 2014, the alfalfa
  production years, the sudangrass seasons, and seasons whose only generator event was
  dropped as an artifact. 51 get the usual irrigation (corn 11, tomato 20, wheat 18,
  alfalfa 2). 5 irrigated wheat seasons in Tautges' no-irrigation years do not (below), and
  neither do the 5 sudangrass green manure seasons (`org_corn_tomato` `corn/CC-tomato/CC`
  2008, and 2009 in `conv_corn_tomato` `tomato-corn`, `leg_corn_tomato` and
  `org_corn_tomato` `tomato/CC-corn/CC`, and `transitional`): no sudangrass season has
  irrigation to take a median from. The script prints every season it leaves without
  irrigation. Each of the 51 gets one event at the season midpoint with the median season
  total of the treatment's other seasons of that crop (for example 545.75 mm for
  `conv_wheat_tomato` wheat, n = 16; 546.87 mm site wheat, n = 67).
  Those totals are the generator's sprinkler prior; the package records no irrigation, and
  Tautges et al. 2019 gives different amounts (see "Open" below).
- A replanted crop (corn in `conv_corn_tomato` 1998 and in `org_corn_tomato` and
  `transitional` 2013) is one season from its first planting to its harvest, with one
  irrigation event: the event nearest its midpoint, the others being artifacts (above);
  `conv_corn_tomato` 1998 had none and gets one imputed event. Each counts once in the
  medians: the `org_corn_tomato` corn median is 575.55 mm (n = 13) and the site corn median,
  used for `alf_corn_tomato` 2014, 558.15 mm (n = 44).
- The irrigated wheat systems (`irr_wheat_control`, `irr_wheat_fallow`, `irr_wheat_legume`)
  got no irrigation "in 1995, 1998, 2000, 2005, and 2008–2012" (Tautges et al. 2019), so their
  seasons harvested in those years get no imputed irrigation; this skips five (1998 in all
  three, 2000 and 2008 in `irr_wheat_legume`). Generator events already in those years are
  kept, pending the amounts question. `conv_wheat_tomato` is not covered by that statement and
  keeps the fill.
- Alfalfa: each calendar year's run of cuttings, first to last, is a production season, so
  2013 and 2014 each get one event at their midpoint. Their amount, 490.87 mm, is the median
  of the site's irrigated alfalfa seasons, and there is only one: the stand's establishment
  season, whose single generator event is that 490.87 mm on 2013-01-06. So both rest on one
  generator event.

## `alf_corn_tomato` history

The six Alfalfa/Corn/Tomato plots were the six Irrigated Wheat/Legume plots, one phase to one
phase (`corn-tomato-alfalfa-alfalfa-alfalfa-tomato` = `wheat-CC`, plots 4-7, 5-1 and 7-6;
`tomato-alfalfa-alfalfa-alfalfa-tomato-corn` = `CC-wheat`, plots 4-8, 5-2 and 7-5), fallow from
2008 until the switch in 2012. The package files their operations from 1993 to 2007 under
the old system name, and the generator built each treatment from its own system name, so the
`alf_corn_tomato` files started at the 2012 alfalfa planting and ran bare from the start of
the run. Each `alf_corn_tomato` phase now starts with its plots' `irr_wheat_legume` events (72
in all, each tagged `history_of`), then the fallow years, then its own events.

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
  2006, 2010; N also 1994 to 1997) take the mean over measured years and the event is
  tagged `provenance_class: assumed`. A 2014 application copied from an earlier season keeps
  that season's tonnage and analysis.
- **The package has no compost records for some years**, although the paper describes
  annual application: 1998, 1999 and 2008 in both organic phases, plus 2010, 2012 and 2013
  in `corn/CC-tomato/CC` and 2011 in `tomato/CC-corn/CC`; `transitional` lacks 2008 and
  2011. Those years carry no compost here; whether to fill them is open on calibration#10.
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
takes the date most plots share (earliest on a tie) and lists the original dates in
`merged_dates`. A merged planting takes the mean of the generator's amounts; a merged harvest
takes its fractions from the harvest lookup, like every other harvest. Alfalfa cuttings,
about a month apart, stay separate.

Left as recorded: corn replanted four weeks later (`conv_corn_tomato` 1998;
`org_corn_tomato` and `transitional` 2013, twice in organic). For irrigation and 2014
fertilization the replants are one season from the first planting to the harvest, with one
irrigation event (see "Imputed dates and amounts").

`operations_planting.csv` lists the 2003 and 2005 tomato transplanting in `org_corn_tomato`
under plot 6-8, two days before its own corn seeding, and none under 8-8. `plot_system.csv`
has 6-8 in corn and 8-8 in tomato both years, and 8-8 has the tomato harvest samples, so
the script moves those two records to 8-8. Before, the corn phase got a tomato planting
that was never harvested.

## Open (calibration#10)

- **Tillage is not in these files.** The package has no tillage or cultivation table; it logs
  only herbicide incorporation passes in `operations_pesticides.csv` (`Incorporate` 189,
  `Mulch_Beds` 153, `Perfecta` 6 rows), and its metadata describes the 2003 to 2007 standard
  versus conservation tillage split (all included data are from the standard halves).
  Tautges et al. 2019 (Methods 2.1 to 2.3) describes the operations and when they happen:
  disking to 15 to 20 cm and tillage to at most 25 cm; maize stalks chopped and disked after
  harvest; tomato residue shallow disked after harvest; beds listed and rolled before
  tomato and rolled before maize; compost broadcast and incorporated in March or April; cover
  crops mowed and incorporated with two to three diskings; one cultivation per crop phase in
  the conventional systems and three to four in ORG; wheat straw incorporated by two shallow
  diskings after the July harvest, and four diskings during the wheat fallow. It gives no
  intensity, and a tillage event needs `tillage_eff_0to1`.
- **Irrigation amounts.** Tautges et al. 2019 gives the irrigated wheat systems
  "supplemental irrigation of 80 mm per year except in 1995, 1998, 2000, 2005, and
  2008–2012", while the generator's sprinkler prior puts several hundred mm into each wheat
  season. For furrow irrigated maize and tomato it gives "an average of 33.6 mm per year"
  (17.6 in 1995 to 43.5 in 2004), which is too little for furrow irrigation and is probably
  in other units; its Table S1 is not in hand. For alfalfa it gives nothing, and the
  490.87 mm a production year gets here rests on one generator event. The five 2008 and
  2009 sudangrass green manure seasons get no irrigation here, because no sudangrass season
  has any to take a median from; whether and how much they were irrigated is open. The files
  keep the generator's amounts, including its events in the irrigated wheat systems'
  no-irrigation years; only the imputed irrigation skips those years.
- **Fertilization gaps and a conflict.** The fertilizer log has no corn N for
  `leg_corn_tomato` in any year, although Tautges Table 1 gives CONV+WCC synthetic N at
  168 kg/ha and its Methods sidedress CONV+WCC maize to 180 kg N/ha. It also has no 2013
  corn N in `conv_corn_tomato`, and the compost years listed under Compost are missing.
  None of these is filled.

## Checks

- All 23 files validate against `events_schema_v0.1.1` from PEcAn `develop` (the stacked
  organic and transitional files still fail it), and `PEcAn.SIPNET::write.events.SIPNET`
  writes an `events.in` for each: 467 harvest events give 467 `harv` lines, and the 13
  alfalfa cuttings are `harv 0.85 0 0 0`.
- The 323 recorded fertilization events are identical to the previous version's; their
  phase-year totals were recomputed independently from the package then (261 nonzero
  totals, 0 differences).
- Every planting before 2014 has an end (a same-crop harvest within 365 days, or a cover crop
  end), every harvest has a planting before it, no cover crop ends after the next cash
  crop planting, and no phase has overlapping seasons of two cash crops.
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
