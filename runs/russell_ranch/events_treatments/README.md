# Russell Ranch treatment events

One `events.json` per Tautges et al. (2019) treatment **and rotation phase**, 1993 to 2014,
23 files across 12 treatments. These are treatments (farming systems run side by side) and
phases (the same system on offset rotations), not ensemble members. Using them as ensemble
members would conflate treatment effect with management uncertainty.

Built by `tools/event_prep/russell_split_phases.R` from `generator_stacked/` and the Century
Experiment package (Wolf et al. 2018, `10.1002/ecy.2105`, supporting information
`RR_2014_datasets/`). `phase_year_summary.csv` lists every phase-year's cash crops, mineral
N, compost C and N, and irrigation so the files can be reviewed without opening them.

Events the operation logs lack are filled, and dates and amounts no record gives are imputed,
in the order set out in [`tools/event_prep/README.md`, "Filling missing events"](../../../tools/event_prep/README.md#filling-missing-events):
the package's own records and Tautges et al. (2019) first, then the monitoring product, then
guidance. Fertilization gaps and 2014 fertilization copy the package's own records, except corn
and wheat N that the log lacks for a season (Legume/Corn/Tomato corn in every year, Conventional
Corn/Tomato corn in 2013, four wheat seasons in 1997 to 1999), which takes Tautges' rates. Every
corn and tomato season and the wheat of every irrigated system are irrigated as Tautges gives,
the corn and tomato on a schedule from planting to the monitoring product's last irrigation
before harvest; sudangrass and alfalfa, for which the paper gives no amount, take the
monitoring product's. Tillage follows the operations Tautges describes and the soil passes the
package logs, with the remaining dates and every intensity from the monitoring product near
Russell Ranch. Filled planting amounts are medians of the generator's priors (see "Imputed
dates and amounts" and "Tillage"). Every imputed event carries `provenance_class: imputed` and a
`provenance_note` that names the rule and the median, or the copied season, it used.

Three tables next to the files hold what the script would otherwise hard-code:
`russell_treatments.csv` (each treatment's package name, Tautges code and the rules that apply
to it), `russell_source_corrections.csv` (each package record the script moves, drops,
re-dates or reinterprets, with the evidence) and `russell_harvest_lookup.csv` (the harvest
fractions). Records in the package that look missing or inconsistent, which many of these fills
work around, are listed for its maintainers in [`century_package_issues.md`](century_package_issues.md).

| file prefix | package system | Tautges et al. 2019 |
|---|---|---|
| `alf_corn_tomato` | Alfalfa/Corn/Tomato | not described |
| `conv_corn_tomato` | Conventional Corn/Tomato | CONV |
| `conv_wheat_tomato` | Conventional Wheat/Tomato | not described |
| `irr_wheat_control` | Irrigated Wheat Control | IWF |
| `irr_wheat_fallow` | Irrigated Wheat/Fallow | IWF+N |
| `irr_wheat_legume` | Irrigated Wheat/Legume | not described |
| `leg_corn_tomato` | Legume/Corn/Tomato | CONV+WCC |
| `org_corn_tomato` | Organic Corn/Tomato | ORG |
| `rf_wheat_control` | Rainfed Wheat Control | RWF |
| `rf_wheat_fallow` | Rainfed Wheat/Fallow | RWF+N |
| `rf_wheat_legume` | Rainfed Wheat/Legume | RWF+WCC |
| `transitional` | Transitional | not described |

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
| irrigation, irrigated systems | one sprinkler event of several hundred mm per cash crop window | none from the generator: its 207 events are dropped. Every corn and tomato season follows Tautges et al. 2019 (33.6 in a season, the paper's "mm" read as inches) and every irrigated system's wheat its 80 mm rule (none in its no-irrigation years); sudangrass and alfalfa, which it gives nothing for, take the monitoring product's medians near the site. All of it is soil irrigation, in events of at most 150 mm (below) |
| tillage | none | one event per operation Tautges et al. 2019 describe, timed and sized from the monitoring product near Russell Ranch, and the herbicide incorporation passes the package logs, on their logged dates (below) |
| fertilization the log lacks | none | copied from comparable records; corn and wheat with no N record take the paper's rates; the organic 2008 sudangrass year copies the nearest recorded compost (below) |
| harvest fractions | drawn from a grain-harvest prior | harvest lookup rows; the 2012 wheat cut for hay takes the hay row; alfalfa cuttings leave the stand alive (below) |
| cover crops | planted, never terminated | end on their incorporation date, all to litter (below) |
| plantings and harvests missing from the logs | none, so crops were harvested that were never planted and planted ones never harvested | filled from `plot_system.csv` and the alfalfa cutting samples, the Transitional plots' 1998 crops included (below) |
| package records that contradict the rest of the package | used as recorded | moved, dropped, re-dated or reinterpreted from `russell_source_corrections.csv`, with the evidence in each row (below) |
| 2014 | none (the logs end in 2013) | built from `plot_system.csv` and the cutting samples, fertilization imputed (below) |
| `alf_corn_tomato` before 2012 | no events | the plots' Irrigated Wheat/Legume history (below) |
| zero-N applications (P, K, Zn) | written as 0/0/0 events, two dated an invented 1999-01-01 | dropped; SIPNET reads only N and C |

Fertilization is rebuilt from `operations_fertilizers.csv` and `operations_compost.csv`, and
irrigation from the rules below. Planting and harvest are the generator's events, assigned to a
phase by plot id, plus what the logs miss. **Planting amounts are still the generator's prior
fills** (`prior_filled` on each event): leaf C from a processing-tomato baseline for every crop,
a median of 0.0034 kg C/m2 (0.0020 to 0.0048). A filled planting takes the median of those same
priors in its phase, so it matches its neighbours (proposed on calibration#10 and agreed by
Akash and David). The monitoring planting product near the site gives similar leaf C: medians of
0.0038 kg C/m2 for G2 wheat, 0.0046 for F16 corn and 0.0053 for T32 tomato (v5.0, within 25 km,
2016 to 2023). The priors are remaining weaknesses listed when ccmmf/uncertainty#6 was closed.

## Harvest fractions

Every harvest takes its crop's row of the harvest lookup the other calibration sites use
(`s3://carb/management/plant_traits/harvest_lookup.csv`, dated 2026-08-06, md5
`defbff0c0b86ae9ff6db07d520813538`), the values the monitoring harvest product carries, rounded
to three decimals as Akash gave them on calibration#10. `russell_harvest_lookup.csv` holds the
rows with the lookup's exact values, and `harvest_lookup_row` on each event names the one used.
The generator's draw from a grain-harvest prior is dropped. Every row takes 100% of the biomass
as removed or to litter, so a harvest ends the crop; an intermediate alfalfa cutting does not
(below). David suggested DSSAT parameters if more values were needed; none were, as the lookup
has a row for every harvested crop here.

| crop | lookup row | above removed | above to litter | below removed | below to litter | events |
|---|---|---|---|---|---|---|
| corn | F16 | 0.752 | 0.248 | 0 | 1 | 56 |
| tomato | T32 | 0.33 | 0.67 | 0 | 1 | 93 |
| wheat | G2 | 0.713 | 0.287 | 0 | 1 | 150 |
| wheat cut for hay, 2012 | hay (P, pasture) | 0.892 | 0.108 | 0 | 1 | 2 |
| alfalfa, last cutting before another crop | P1 | 0.85 | 0.15 | 0 | 1 | 0 |
| alfalfa, intermediate cutting | P1 share | 0.85 | 0 | 0 | 0 | 13 |
| sudangrass | none | 0 | 1 | 0 | 1 | 5 |
| unharvested wheat | none | 0 | 1 | 0 | 1 | 1 |
| cover crop | none | 0 | 1 | 0 | 1 | 119 |

- Alfalfa is cut six or seven times a year. With the full P1 row the roots went to litter
  at the first cutting, so SIPNET killed the stand on 2013-04-10 and the later cuttings acted
  on nothing. An intermediate cutting now removes the P1 aboveground share and leaves the
  stubble and roots alive (David on calibration#10). Only the last cutting before the next
  planting would take the full row; the stand planted 2012-10-04 is still growing at the end
  of 2014, so all 13 cuttings in the files are intermediate. The monitoring product has one
  P1 harvest a year with the full row, so it has no cutting values to use instead.
- Sudangrass falls in F16, which groups corn, sorghum and sudan, but the site record overrides
  that row: in 2008 and 2009 it "was sampled prior to plowing under at every harvest and no hay
  was removed from the plots" (Wolf et al. 2018 metadata), so its harvests send everything to
  litter.
- In 2012 the `org_corn_tomato` and `leg_corn_tomato` wheat "was not harvested for grain.
  Instead, all biomass was harvested for hay" (Wolf et al. 2018 metadata), so both take the
  lookup's hay row (Aritra, 2026-10-30). The `leg_corn_tomato` cut is the "Harvest Wheat" logged
  on 6/25/2012. The `org_corn_tomato` one is not logged (`plot_system.csv`: "NOT harvested for
  wheat in 2012") and is dated like it, tagged imputed.

## Cover crop termination

The package has no termination or tillage records. The data dictionary for
`wcc_harvests_all.csv` gives its `date` as "the date of the WCC incorporation" (the methods put
the biomass sample in the week before it). Each cover crop ends with a harvest event that
removes nothing and sends all biomass, above and below ground, to litter. The monitoring product
cannot date these: it starts in 2016, after the run, and it ends a cover crop at the end of its
greenness, not at an incorporation. Of 125 cover crop plantings (98 from the generator, 27
filled below):

- 108 end on that date, the one most of the phase's plots share.
- 2 have no sample and end on the cover crop harvest date in `plot_system.csv`, which
  equals the sample date in 342 of the 343 plot-years that have both (`leg_corn_tomato` 2006-04-25,
  `rf_wheat_legume` 2014-03-13).
- 9 have no usable date and are imputed (below). Seven are the 2004 cover crops: both files
  record 5/17/2004 for every plot of every system, after the 5/2 and 5/5 corn and tomato
  plantings, so it cannot be the incorporation, and the wheat/legume systems' copies of the same
  date are set aside too (`russell_source_corrections.csv`). The other two are `transitional`
  planted fall 1999, which `plot_system.csv` says has "no evidence that it was harvested" and
  whose plots appear to have been "cultivated 3/1/2000 and/or mowed 4/5/2000" (the imputed
  2000-03-26 falls between, and the script checks that it does), and `irr_wheat_legume`
  `CC-wheat` planted 2007-12-12.
- 6, planted in fall 2014, are still growing when the files end.

## Filled from `plot_system.csv` and the cutting samples

`plot_system.csv` records every plot-year's planting and harvest, and
`alfalfa_harvests_all.csv` has a sample "at each alfalfa cutting". The operation logs miss
some of these and stop at the end of 2013. A recorded operation is filled when the phase has
no event of the same crop within 30 days (7 days for a cutting), dated by the day most of the
phase's plots share (the first day where a range is given), with `source` naming the file.

| | 1993 to 2013 | 2014 |
|---|---|---|
| plantings | 49: wheat 14, tomato 9, corn 5, cover crop 21 | 21: wheat 6, tomato 5, corn 4, cover crop 6 |
| harvests | 33: wheat 14, corn 8, tomato 6, sudangrass 5 | 15: wheat 6, tomato 5, corn 4 |
| alfalfa cuttings | none missing | 7 |

- The pre-2014 plantings are whole seasons the planting log lacks, at least 336 days from
  any logged planting of the same crop: fall 1998 and fall 2001 wheat in the wheat systems,
  1994 and 1999 tomato in the corn and tomato systems, corn in `conv_corn_tomato` 2002,
  `leg_corn_tomato` and `org_corn_tomato` 1998 and `transitional` 1998 and 2006 (below), and
  fall 1998, 2001 and 2004 cover crops. In `generator_stacked/`, 25 harvests had no planting
  before them.
- A filled planting takes the median amounts of the generator's plantings of the same crop
  in the phase (`prior_filled` says which and how many).
- The `transitional` plots were "unassigned" until 1999, when "three of the unassigned plots
  were converted into a transitional organic corn-tomato rotation" (`plot_system.csv`). The
  logs file their earlier operations under Transitional, so the file starts with them: a 1993
  to 1994 cover crop, then corn, tomato, wheat and corn from 1995 to 1998, with mineral N. Their
  unassigned plot-years take the plots' 1999 phase, so the 1998 corn (planted 1998-04-19,
  harvested 1998-11-03, with `corn_harvests_all.csv` samples) and the fall 1998 cover crop
  (1998-11-14 to 1999-03-30) are filled, and the logged 1998-07-08 corn N falls on a crop.
- Five of the 1999 tomato plantings take 1999-05-01, which `plot-system.csv`, the package's
  annotated copy of the table, calls an assigned date: "Going to assign a plant date of 5/1/99
  unless find evidence otherwise"; "Tomato beds incorporated on 5/20/99, so tomatos likely
  planted thereafter". They are tagged `provenance_class: assumed`.
- The `conv_wheat_tomato` 1994 tomato takes its 1994-05-04 transplanting, not the 1994-03-23
  in `plot_system.csv`: the farm log note in `plot-system.csv` gives a "tomato planting date of
  3/23/94 and transplant date of 5/4/94 ... going with the transplant date", and the other
  systems' 1994 tomatoes carry the 5/4/94 transplanting.
- A cash crop that `plot_system.csv` records within 30 days of a logged planting of another
  cash crop is a conflict between the files. The script prints it and does not fill it, so
  one field is never planted with two cash crops. None remains.
- `transitional` grew corn in 2006, not tomato. `plot_system.csv` lists corn planted
  2006-05-25 and harvested 2006-09-13 ("Corn planted instead of tomato"), and
  `corn_harvests_all.csv` has the 2006 corn samples, dated 10/24/2006, while
  `tomato_harvests_all.csv` has none that year. The planting and harvest logs record a tomato
  transplanting and harvest on 5/25 and 9/13 on its three plots. The script drops those six
  records and the generator's two tomato events (`russell_source_corrections.csv`), and the
  corn planting and harvest are filled from `plot_system.csv`.
- A cash crop planting with no same-crop harvest within 365 days takes the plot_system
  harvest date. A planting followed within 30 days by another of the same crop is a replant
  and is not filled. For example, the 1998 `conv_corn_tomato` tomato has no harvest
  operation, while `plot_system.csv` dates it 1998-08-14 and `tomato_harvests_all.csv` has
  its samples.
- Crops planted in fall 2014 (wheat, cover crops) are still growing when the files end.
- Left out: the 1992 and 1993 sudangrass uniformity crops grown before the experiment
  ("In July 1992 and May 1993, irrigated unfertilized S. vulgare (sudan grass) hay was planted
  throughout the Century Experiment area", Wolf et al. 2018 metadata; `plot_system.csv` dates the
  1993 one, 5/12/1993 to 8/2/1993, but not the 1992 one). The files start with the first
  experiment operations in fall 1993, after the September 1993 baseline cores, while the run
  starts on 1992-01-01 (see "Known limitations").
- `operations_harvest.csv` also lists the 7/1/1999 Rainfed Wheat/Legume wheat harvest under
  plot 7-3, a `wheat-CC` plot that grew a cover crop that winter; the three `CC-wheat` plots
  carry the harvest. The script drops the 7-3 row (`russell_source_corrections.csv`), as it
  does the repeated fertilizer record below.

## Imputed dates and amounts

Where neither the logs nor `plot_system.csv` give a date, it comes from the package's own
records for the same system (the site's when the system has fewer than five), following the
order in `tools/event_prep/README.md`. Its step 2, the monitoring product, is used for tillage,
which neither the package nor the paper times or sizes, apart from the passes the package logs
and the paper's month for the wheat straw (see "Tillage"); for the timing of the corn and tomato
irrigation; for the sudangrass and alfalfa irrigation, which the paper does not give; and as
the check on the unit of the paper's maize and tomato irrigation (below). Amounts differ by kind:
fertilization gaps and 2014 fertilization copy the package's own records, except corn and wheat N
the log lacks, which takes the paper's rates; the corn and tomato and the wheat of every irrigated system
are irrigated as Tautges et al. 2019 gives; and a filled planting's amounts are medians of the
generator's priors (above).

| what | rule | events |
|---|---|---|
| cover crop end, a cash crop follows | the system's median gap between a recorded cover crop end and the next cash crop planting: 37 days in `org_corn_tomato` (n = 37), 42 in `leg_corn_tomato` (n = 25), 40 in `transitional` (n = 12), 226 in `irr_wheat_legume` (n = 13) and `rf_wheat_legume` (n = 20) | 8 (the seven 2004 ends and `transitional` 1999) |
| cover crop end, no cash crop follows | the system's median day of a recorded cover crop end: day 96 in `irr_wheat_legume` (n = 13) | 1 (2008-04-05) |
| unharvested wheat | the median day of a recorded wheat harvest, day 182 (about 1 July), all biomass to litter, `not_harvested: true` | 1 |
| wheat cut for hay | the logged `leg_corn_tomato` cut, 6/25/2012 (above) | 1 |
| 2014 fertilization | the most recent same-crop season of the treatment with fertilization records that land in 2014 once shifted to the 2014 planting | 17 |
| fertilization gap | a season the log has no fertilization for, dated from comparable records; corn and wheat N take Tautges et al. 2019's rates on the copied dates, compost copies the record (see "Fertilization gaps") | 51 (N 45, all at the paper's rates: corn 37, wheat 8; compost 6) |
| compost year | an organic rotation year that is not a wheat year and has no compost record copies the nearest recorded year's compost (see "Fertilization gaps") | 1 (2008) |
| wheat irrigation | Tautges et al. 2019's rule for IWF and IWF+N, in every irrigated system: 80 mm at the season midpoint, none in its no-irrigation years; IWF and IWF+N through 2012 are tagged assumed (the paper's amount on an imputed date), 2013 and 2014, after its period, and the systems it does not describe imputed | 47 events (20 assumed, 27 imputed), 43 seasons without |
| corn and tomato irrigation | Tautges et al. 2019, the paper's "mm" read as inches: 33.6 in (853.44 mm) a season, 17.6 in 1995 and 43.5 in 2004, in equal soil events of at most 150 mm from planting to the monitoring product's median last irrigation before harvest; the maize systems through 2012 are tagged assumed (the amount rests on the inches reading), 2013 and 2014, after its period, and the systems it does not describe imputed | 886 events in 149 seasons (582 assumed, 304 imputed) |
| sudangrass irrigation | the monitoring product's median irrigated F16 season near the site, 440.2 mm, in 3 equal soil events | 15 in 5 seasons |
| alfalfa irrigation | the monitoring product's median irrigated P1 year near the site, 579.7 mm, in 4 equal soil events from 12 June to 6 September | 8 in 2 years |
| tillage | the operations Tautges et al. 2019 describe, timed and sized from monitoring medians near Russell Ranch, and the passes the package logs, on their dates (see "Tillage") | 705 |

- Unharvested wheat: the `irr_wheat_legume` `wheat-CC` wheat planted 2007-12-15 has no
  harvest in either file and ends 2008-06-30 (`irr_wheat_legume` has 14 recorded wheat
  harvests, so its own median applies).
- The December 2007 `irr_wheat_legume` plantings conflict with `plot_system.csv`, which says
  "IWL was fallow from 2007-2012". `operations_planting.csv` records the seeding, so the
  plantings are kept and given imputed ends.
- 2014 fertilization: only copied events that land in 2014, inside the 2014 season, are kept,
  and a season none of whose records would land there is never used as the template, because
  the fertilizer log has gaps. It has no 2013 corn N in any corn and tomato system, though it
  has two corn applications a year in 2005 to 2007, so `conv_corn_tomato` 2014 corn copies its
  own 2007 records (50.44 kg N/ha NPK and 185.1 kg N/ha urea), while its 2013 corn, a season
  the log should have, takes the paper's rates (see "Fertilization gaps"). A partial gap is
  skipped the same way: the `irr_wheat_fallow` `fallow-wheat` wheat planted 2012-11-12 has only
  its 2012-10-29 preplant, which would land in 2013, and no spring 2013 topdress (its 2009 and
  2011 wheat had one), so the `wheat-fallow` 2014 harvest year copies the 2011-planted season's
  2012-03-26 urea to 2014-03-20 (56.2 kg N/ha). `alf_corn_tomato` has no corn before 2014 and
  copies `conv_corn_tomato`'s. A treatment whose log has no fertilization for a crop gets
  nothing here; `leg_corn_tomato` corn instead takes the paper's rates through the
  fertilization gap rule (see "Fertilization gaps"). The shift runs from the copied season's
  first planting, not a replant: the `org_corn_tomato` 2014 compost lands on 2014-03-17, 29
  days before the 2014-04-15 corn planting, as the 2013-02-24 compost was 29 days before the
  2013-03-25 planting (replanted 5/15 and 6/1).
- Generator irrigation: the generator put one sprinkler event of several hundred mm at the
  midpoint of each cash crop window. All 207 of its events in the irrigated systems (and the 54
  in the rainfed ones) are dropped, and irrigation is rebuilt by the rules below. The script stops
  if a cash crop season of an irrigated system has no irrigation, other than wheat in the paper's
  no-irrigation years and the alfalfa stand's establishment.
- Method: every irrigated system "received furrow-flood irrigation through 2014, with some
  exceptions" (Wolf et al. 2018 metadata), so every event is `soil`, which
  `PEcAn.SIPNET::write.events.SIPNET` writes as SIPNET irrigation code 1; it writes every
  other method, `flood` included, as the canopy code 0, which loses part of each event to
  evaporation at once. Table 1 of Tautges et al. 2019 lists IWF and IWF+N as "Supplemental
  Sprinkler", but its caption calls the same irrigation "supplemental flood", and the metadata's
  exceptions do not include the wheat (`century_package_issues.md`, item 68).
- A replanted crop (corn in `conv_corn_tomato` 1998 and in `org_corn_tomato` and
  `transitional` 2013) is one season from its first planting to its harvest, irrigated as
  below from its last planting.
- Wheat: Tautges et al. 2019 give the irrigated wheat systems "supplemental irrigation of 80
  mm per year except in 1995, 1998, 2000, 2005, and 2008–2012 due to sufficient
  precipitation". The paper names IWF and IWF+N (`irr_wheat_control` and `irr_wheat_fallow`);
  the wheat of every other irrigated system is irrigated the same way (Aritra, 2026-10-30), as
  the metadata says irrigated wheat rotations "receive supplemental irrigation in early spring
  (Jan–March) in years with low precipitation". Each of the 90 wheat seasons in irrigated
  systems gets one 80 mm event at its midpoint (47 seasons, all of the events in February or
  March), or none when it is harvested in one of those years (43). 20 events (IWF and IWF+N
  through 2012) are tagged assumed, the paper's amount on an imputed date, and 27 imputed.
- Corn and tomato: every season follows Tautges et al. 2019: "Maize in all systems was furrow irrigated with an average of 33.6 mm per
  year, with a minimum of 17.6 mm in 1995 and a maximum of 43.5 mm in 2004", and tomatoes "as
  described for maize". As millimetres that is far too little for furrow irrigation, so the
  unit is read as inches (David, 2026-10-29 call: the conservative assumption, since the crops
  were given enough water and must not become water limited): 853.44 mm, 447.04 mm in 1995 and
  1104.9 mm in 2004, against about 336 mm as centimetres and the generator's prior of about
  575 mm. The monitoring irrigation product near Russell Ranch
  (`monitoring_irrigation_near_russell.csv`, from `tools/event_prep/russell_monitoring_irrigation.R`:
  v5.0, planting to harvest, 2,355 corn F16 seasons on 1,420 parcels and 4,963 tomato T32
  seasons on 1,902 parcels within 25 km, 2016 to 2023, each the median of 20 ensemble members)
  puts the median irrigated season at 440.2 mm for corn and 449.8 mm for tomato. It estimates
  irrigation from evapotranspiration and does not see water that drains, so it is a lower
  bound, and it is already above the centimetre reading. The paper's supporting information
  does not settle the unit either way: Table S1 is precipitation only (winter, October to March,
  and summer, April to September, 1993-94 to 2011-12), S2 soil pH and S3 bulk density. The paper
  describes the maize systems `conv_corn_tomato`, `leg_corn_tomato` and `org_corn_tomato`; the
  corn and tomato of `transitional`, `alf_corn_tomato` and `conv_wheat_tomato`, which it does
  not describe, take the same amounts (Aritra, 2026-10-29). One event of that size would mostly
  drain in SIPNET, whose soil holds about 12 cm, so each season's amount is split into equal
  events of at most 150 mm (Aritra, 2026-10-29): 6 of 142.24 mm for 853.44, 3 of about 149.01
  for 447.04 and 8 of 138.11 for 1104.9. 150 mm is the monitoring product's `irrigation_max`
  from v1.1, set "to avoid unrealistically large irrigation events"
  (`management/irrigation/CHANGELOG.txt`); v5.0 events near the site reach 216 mm. The events
  are spaced evenly from the crop's last planting (a replant) to the product's median days
  between the last irrigation and harvest (30 for corn, 25 for tomato), so the first falls on
  the planting date (Aritra, 2026-10-31). The package records irrigation at transplanting
  (`plot-system.csv`, 1999: "Preplant cultivate occurred 4/25/99, mulched 4/26/99, irrigated
  5/1/99"), and the product, estimated from evapotranspiration, puts a season's first irrigation
  57 days (tomato) and 61 days (corn) after planting at the median, which would leave the young
  crop dry for two months; that offset is not used. The events are 26 days apart for corn and
  19 for tomato at the median (9 to 62 days). 582 events are tagged assumed (the maize systems
  through 2012, whose amount rests on the inches reading) and 304 imputed (2013 and 2014, which
  take the average, and the other three systems).
- Sudangrass: the 2008 and 2009 green manure (`org_corn_tomato` `corn/CC-tomato/CC` 2008, and
  2009 in `conv_corn_tomato` `tomato-corn`, `leg_corn_tomato` and `org_corn_tomato`
  `tomato/CC-corn/CC`, and `transitional`) has no amount in the paper. The metadata says "All
  corn-tomato rotations receive summer irrigation", and sudangrass replaced corn there, so each
  season takes the monitoring product's median irrigated F16 season near the site, 440.2 mm, a
  lower bound, in 3 equal soil events of about 146.73 mm (Aritra, 2026-10-30), on the corn
  schedule: from planting to 30 days before the end. 15 events, imputed.
- Alfalfa: the paper gives no amount either. Each year of cuttings (2013 and 2014) takes the
  monitoring product's median irrigated P1 calendar year near the site, 579.7 mm (3,074
  irrigated of 5,230 parcel-years on 1,508 parcels, 2016 to 2023), a lower bound, in 4 equal
  soil events of 144.925 mm from the product's median first irrigation of the year, 162 days
  after 1 January (12 June), to its median last, 116 days before 31 December (6 September),
  within the year's cuttings. The stand's fall 2012 establishment, before that window, gets
  none. 8 events, imputed.

## `alf_corn_tomato` history

The six Alfalfa/Corn/Tomato plots were the six Irrigated Wheat/Legume plots, one phase to one
phase (`corn-tomato-alfalfa-alfalfa-alfalfa-tomato` = `wheat-CC`, plots 4-7, 5-1 and 7-6;
`tomato-alfalfa-alfalfa-alfalfa-tomato-corn` = `CC-wheat`, plots 4-8, 5-2 and 7-5), fallow from
2008 until the switch in 2012. The package files their operations from 1993 to 2007 under
the old system name, and the generator built each treatment from its own system name, so the
`alf_corn_tomato` files started at the 2012 alfalfa planting and ran bare from the start of
the run. Each `alf_corn_tomato` phase now starts with its plots' `irr_wheat_legume` events (100
in all, tillage included, each tagged `history_of`), then the fallow years, then its own events.

## Compost

`wet tons/acre x 0.22417 (US short ton per acre to kg/m2) x %C or %N`, with %C and %N from
`compost_analyses_summary.csv` for the year applied (in-house Costech replicates averaged
where present, as Tautges used; otherwise the one lab reported). The percentages are applied
to the reported tonnage without a moisture correction because that is the basis that
reproduces the paper. The tonnage is reported as wet tons, so if the analyses are on a dry
basis these amounts are an upper bound on the C and N applied.

| check | these files | Tautges et al. 2019 |
|---|---|---|
| compost C per application year, organic system | 2.08 Mg C/ha (1994 to 2012, both phases) | 40.4 Mg C/ha over 19 years = 2.13 (its conclusions give 0.7 to 0.8 Mg C/ha a year) |
| compost N per application year | median 168 kg N/ha (111 to 505) | 150 to 200 kg N/ha |
| 4 tons/acre in t/ha | 8.97 | "annual inputs of 9 t/ha" |

- %C is measured in 13 years and %N in 9. Years without an analysis (C: 2000, 2005,
  2006, 2010; N also 1994 to 1997) take the mean over measured years and the event is
  tagged `provenance_class: assumed`. A copied application (2014, a fertilization gap or the
  compost year below) keeps the copied season's tonnage and takes %C and %N for the year it is
  applied in the same way: the compost was applied uniformly in the organic and transitional
  systems each year (Wolf et al. 2018), so a year's applications share its analysis.
- **The package has no compost records for some years**, although the paper describes
  annual application: 1998, 1999 and 2008 in both organic phases, plus 2010, 2012 and 2013
  in `corn/CC-tomato/CC` and 2011 in `tomato/CC-corn/CC`; `transitional` lacks 2008 and
  2011. The corn and tomato years among them are filled by the fertilization gap rule (below):
  1998 and 1999 in both phases, 2008 in `tomato/CC-corn/CC` and 2013 in `corn/CC-tomato/CC`.
  The 2008 sudangrass year in `corn/CC-tomato/CC` copies the nearest recorded year's compost
  (see "Fertilization gaps"), as Tautges et al. 2019 give the organic system "annual inputs of
  9 t/ha". The rest are wheat years (2010 and 2012 in `corn/CC-tomato/CC`, 2011 in
  `tomato/CC-corn/CC`, 2008 and 2011 in `transitional`) and stay without (Aritra, 2026-10-29):
  the package has compost in none of these systems' wheat years, 0 of 5, against 42 of the 49
  other phase-years from each phase's first compost to 2013; the metadata says wheat replaced
  corn in 2009 to 2012 because of budget cuts; and the paper times compost only before maize and
  tomato. Over 1994 to 2012 the organic phases get 36.18 and 36.70 Mg C/ha in 17 and 18
  application years, against Tautges' 40.4 over 19 years, a figure its own conclusions do not
  match (700 to 800 kg C/ha a year, 13.3 to 15.2 Mg C/ha over 19 years).

## Fertilization gaps

The fertilizer log lacks every record for some seasons that were fertilized. Each such
season copies a comparable season with records, shifted by the difference in planting dates;
only copies that land inside the season are kept, and each is tagged `imputed` and names the
season it copies.

- `leg_corn_tomato` corn has no N in the log in any year, although Tautges Table 1 gives
  CONV+WCC synthetic N at 168 kg/ha and its Methods plant CONV and CONV+WCC maize "with 56 kg
  N/ha 8-24-6 starter fertilizer" and sidedress it "with ammonium sulfate at a total rate of
  180 kg N/ha" in one or two applications. With no record, the paper's rates apply (David,
  2026-10-29 call). Each of its 16 corn seasons takes the dates of the `conv_corn_tomato` corn
  season of the same year, or the nearest one with records when that year has none (2007, for
  2013 and 2014), shifted from that season's last planting (the 1998 replant) to its own: that
  season's urea applications are the sidedress and share the 180 kg N/ha as they shared their
  own N, and its one other application (NPK or ammonium sulfate) is the
  56 kg N/ha starter, 236 kg N/ha a season: 35 events, `source` `10.1111/gcb.14762`. The
  `conv_corn_tomato` records themselves stay as logged (130.28 to 314.35 kg N/ha a season,
  sidedressed with urea rather than the paper's ammonium sulfate).
- Any other season ending by 2013, of a crop its treatment fertilizes in at least half of its
  seasons, that has no record is dated from the treatment's nearest same-crop season with
  records: `conv_corn_tomato` 2013 corn (dated from 2007, at the paper's rates as above), four
  wheat seasons (below) and the six corn and tomato compost years in Compost, which copy the
  record: 16 events.
- Wheat with no N record takes the paper's rates in the same way (Aritra, 2026-10-31): Tautges
  et al. 2019 give fertilized wheat "56 kg/ha 15-15-15 starter fertilizer at planting, and an
  additional 90 and 112 kg/ha urea in March" in the rainfed and irrigated systems, which make
  Table 1's 146 (RWF+N) and 168 (IWF+N) kg N/ha, so these are N rates. The four seasons, the 1997
  to 1998 wheat in `conv_wheat_tomato` `wheat-tomato` and `irr_wheat_fallow` `wheat-fallow` and
  the 1998 to 1999 `irr_wheat_fallow` and `rf_wheat_fallow` `fallow-wheat` wheat, take the dates
  of the nearest season of the treatment with a complete record (one application on or before
  planting, the starter, and the rest after it, the urea): 168 kg N/ha each in the irrigated
  systems (`conv_wheat_tomato`, which the paper does not describe, takes the irrigated rate) and
  146 in `rf_wheat_fallow`, 8 events, `source` `10.1111/gcb.14762`. The logged complete seasons
  carry about 168 (irrigated) and 112 (rainfed) kg N/ha.
- A season with some records but not all is not filled; for example, the 2012 to 2013
  `irr_wheat_fallow` wheat has its preplant but no spring topdress.
- `leg_corn_tomato` tomato in 2004 to 2007 (`tomato/CC-corn/CC` 2004 and 2006,
  `corn/CC-tomato/CC` 2005 and 2007) has only its 50.44 kg N/ha NPK starter in the log, while
  `conv_corn_tomato` tomato has its 112.16 kg N/ha ammonium sulfate sidedress every one of those
  years and Tautges et al. 2019 sidedress CONV and CONV+WCC tomatoes "with ammonium sulfate to
  apply a total rate of 112 kg N/ha". It stays as logged (Aritra, 2026-10-29). Those are the
  first years the system grew a winter legume cover crop before tomato as well as before corn
  ("after tomatoes and corn from 2004–2007", Wolf et al. 2018 metadata), and the crop data fit
  no sidedress: its tomato fruit N was 1.48 to 1.57%, the lowest of the four tomato systems and
  below organic, against 1.63 to 2.23 in 1999 to 2003, and in 2005 to 2007 its yield was the
  lowest, 54 to 62 Mg/ha against conventional's 74 to 89, with the same transplanting week,
  variety and density.
- The one non-wheat compost year the package lacks that the gap rule does not fill, the 2008
  sudangrass year of `org_corn_tomato` `corn/CC-tomato/CC`, copies the nearest recorded year's
  application, 2007 (the earlier on a tie with 2009), same tonnage, on the same calendar date,
  2008-04-28, before the sudangrass, with the %C and %N of 2008 (the mean of measured years,
  as 2008 has no analysis): 1 event, incorporated (see Tillage). The wheat years have none (see
  Compost).
- `operations_compost.csv` lists every plot's history twice. The copies agree except for
  2005 on plots 2-3, 6-4 and 6-8, dated 4/20 in one and 5/20 in the other at the same
  4 tons/acre. Compost is kept once per plot and year, on the earlier date, which falls in
  the "March or April" window Tautges gives. The curated `managements` in cal-val-data
  repeat the same rows, so summing them there double counts compost.

## Synthetic N and unplaced records

- Excel turned one plot id in `operations_fertilizers.csv` into a date. `5-Jan` is plot 1-5
  (Conventional Wheat/Tomato, 11/5/2011, Can_27, 111.97 kg N/ha). The script maps it back
  before the phase lookup (`russell_source_corrections.csv`).
- The 2011 wheat pre-plant on the `conv_wheat_tomato` `wheat-tomato` plots (1-5, 4-3,
  7-9) is listed on 11/5 and again on 11/14 at the same 111.97 kg N/ha. Every other wheat
  year has one. As with compost, it is kept once per plot on the earlier date, so
  `wheat-tomato` 2011 carries 330.7 kg N/ha rather than 442.67. The script drops it as a known
  duplicate listed in `russell_source_corrections.csv` rather than by a rule, because split
  applications are real: `conv_corn_tomato` 1996 tomato got 56.55 kg N/ha on both 4/16 and
  5/13.
- Left as recorded, but likely a plot mislabel in the source: the spring 2011 urea topdress
  (3/24/2011, 56.2 kg N/ha) is recorded on the same plots, which grew tomato that year.
  `wheat-tomato` therefore gets it, and `tomato-wheat`, which harvested wheat in 2011, gets
  no N that year.
- Also left as recorded: the spring 1999 urea that the log puts on the fallow plots of
  `irr_wheat_fallow` (56.04 kg N/ha) and `rf_wheat_fallow` (29.54), between their 1998 wheat
  harvest and their fall 1999 seeding, so it falls on bare soil, while the plots that grew wheat
  that spring have no record and take the paper's rates (`century_package_issues.md`, item 7).
- Also left as recorded: Can_27 at 111.97 kg N/ha, labelled Wheat, on the `conv_corn_tomato`
  `tomato-corn` plots on 11/12/2012, after their 2012 tomato harvest and 133 days before their
  2013 corn, on plots that grew no wheat. The Conventional Wheat/Tomato plots seeded to wheat that
  day have the identical row, so it may be repeated under the wrong plots, or it may be a
  preplant for the 2013 corn with the wrong crop label (`century_package_issues.md`, item 10). It
  gives `tomato-corn` 274.5 kg N/ha in 2012, against 162.53 in the matching `leg_corn_tomato`
  phase, and with the paper-rate N of the 2013 corn, 347.97 kg N/ha from November 2012 to that
  corn's harvest.
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
`org_corn_tomato` and `transitional` 2013, twice in organic). For irrigation and
fertilization a replanted crop is one season from the first planting to the harvest,
irrigated from the last planting, and the paper-rate corn N dated from the 1998 conventional
corn also counts from its replant (see "Imputed dates and amounts" and "Fertilization gaps").

`operations_planting.csv` lists the 2003 and 2005 tomato transplanting in `org_corn_tomato`
under plot 6-8, two days before its own corn seeding, and none under 8-8. `plot_system.csv`
has 6-8 in corn and 8-8 in tomato both years, and 8-8 has the tomato harvest samples, so
the script moves those two records to 8-8 (`russell_source_corrections.csv`). In
`generator_stacked/`, the corn phase got a tomato planting that was never harvested.

## Tillage

The package has no tillage or cultivation table, but it logs dated soil passes in
`operations_pesticides.csv`: `Mulch_Beds` (153 rows) and `Perfecta` (6), herbicide incorporated
into the beds, as a rule before planting (the 2013 passes come after the tomato transplanting), and `Incorporate` (189), herbicide incorporated by
cultivating between the beds after tomato transplanting. Its metadata describes the 2003 to
2007 standard versus conservation tillage split (all included data are from the standard
halves). Tautges et al. 2019 (Methods 2.1 to 2.3) describe the operations and when they happen
relative to harvest, planting, cover crop termination and compost, but not on which day, apart
from the wheat straw, or how intense they are. So, in David's order, the logged passes keep the
package's dates, the wheat straw disking keeps the paper's month, and the other dates and every
intensity come from the monitoring tillage product near Russell Ranch:
`monitoring_tillage_near_russell.csv`, made by `tools/event_prep/russell_monitoring_tillage.R`
from the v5.0 tillage, harvest and planting products and the v4.1 crop table, for the 11,290
parcels within 25 km, 2016 to 2023. One event per operation, 705 in all, plus 30 copied into
the `alf_corn_tomato` history:

| operation | date | `tillage_eff_0to1` | events |
|---|---|---|---|
| maize stalks chopped and disked after harvest (Tautges et al. 2019) | 32 days after the corn harvest | 0.6435 | 56 |
| tomato residue shallow disked after harvest | 32 days after the tomato harvest | 0.5799 | 93 |
| wheat straw incorporated by two shallow diskings, then fallow diskings | 31 July: the paper harvests in July, incorporates the straw, "then fallowed from August" (the monitoring median, 63 days after the harvest, falls in August or September) | 0.712 | 152 |
| beds rolled before maize | 38 days before the corn planting | 0.5158 | 56 |
| beds listed and rolled before tomato | 90 days before the tomato planting | 0.9537 | 93 |
| cover crops mowed and incorporated with two to three diskings | at the cover crop end | 0.3708 | 119 |
| compost broadcast and incorporated (ORG) | on the compost date | 0.3708 | 51 |
| sudangrass plowed under, unharvested wheat incorporated | at its end | 0.3708 | 6 |
| herbicide incorporation in the beds (`Mulch_Beds`, `Perfecta`, logged) | the logged date | 0.3708 | 43 |
| cultivation between beds with herbicide incorporation (`Incorporate`, logged) | the logged date | 0.3708 | 36 |

- The days and intensities are medians over monitoring events next to harvests and
  plantings of the same crop code (F16 corn, T32 tomato, G2 wheat): the first tillage event
  within 120 days after a harvest, the last within 120 days before a planting. The
  incorporations and the logged passes take the median of all 51,733 tillage events.
- A logged pass is dated by the day its plots share, with dates within 3 days taken as one
  pass. The phases have 42 `Mulch_Beds`, 36 `Incorporate` and 2 `Perfecta` passes, all in the
  files: one `Mulch_Beds` pass, `transitional` 2006-05-11, falls on a compost incorporation and
  goes in with it. The `Incorporate` passes are the conventional tomato systems' in-season
  cultivations (`conv_corn_tomato`, `conv_wheat_tomato` and `leg_corn_tomato`, 2001 to 2012) and
  one in `transitional` 2006.
- A post-harvest disking is kept before the next planting, and a bed preparation after the
  previous crop ends, so in the cover crop systems it falls the day after the cover crop is
  incorporated. With the wheat straw month, that moves 229 events (the 152 wheat diskings to 31
  July, 21 corn diskings and 56 bed preparations), and each one's provenance note gives the
  median date, the date it moved to and why.
- One event per operation: the two to three diskings at cover crop termination and the four
  fallow diskings are one event each. A compost applied on the day a cover crop is
  incorporated goes in with it, one pass whose note says so: `org_corn_tomato`
  `tomato/CC-corn/CC` 2004-03-29 is the only such day, so compost has 51 events for 52
  applications.
- Left out: the in-season cultivations Tautges et al. 2019 describe that the package does not
  log (one per crop phase in the conventional systems, three to four in ORG), which have no
  date, so ORG has no in-season cultivation and conventional corn none; and alfalfa, which the
  paper does not cover.

## Known limitations

- **Harvest fractions against the site's own records.** The lookup removes 0.752 of corn,
  0.713 of wheat and 0.33 of tomato aboveground biomass. The package's samples put corn grain
  at a median 0.462 of aboveground dry biomass (`corn_harvests_all.csv`, n = 280, interquartile
  range 0.41 to 0.50) and tomato fruit at 0.56 to 0.60 (`tomato_harvests_all.csv`, n = 501,
  machine or hand harvested fruit against the vine), and Tautges et al. 2019 chop and disk the
  maize stalks, disk the tomato residue and incorporate the wheat straw. So the lookup removes
  more corn and less tomato than the site did. The lookup is kept because it is the shared
  source across sites (calibration#10); whether Russell should take its own fractions is open.
- **Irrigation amounts are not records.** The corn and tomato amounts rest on reading the
  paper's "mm" as inches, a conservative assumption, and the sudangrass and alfalfa amounts are
  monitoring medians, a lower bound. The schedule spreads a season's total evenly from planting;
  events of up to 150 mm exceed SIPNET's 12 cm soil store, so part of each drains. Alfalfa keeps
  the monitoring product's June to September window, after the year's first two cuttings.
- **Irrigation the metadata describes but the package does not quantify** is not
  represented: sprinkler pre-irrigation of OMT and LMT tomatoes in 2010 to 2012 and of all
  tomato rotations in 2013, and sprinkler irrigation of the cover crops in November 2012 (all
  irrigated rotations) and November 2013 (LMT).
- **Tillage intensity and dose.** The monitoring medians stand in for intensities the paper
  does not give (Aritra, 2026-10-29). The files have one event per operation the paper describes
  or the package logs: 2.1 to 3.75 a year in the corn and tomato phases (1994 to 2013), with
  `tillage_eff_0to1` summing to 1.35 to 1.97 a year. The monitoring product near the site detects
  a median of one tillage episode a year on corn (F16) and tomato (T32) parcels, summing to 0.54
  and 0.69 (`tools/event_prep/russell_monitoring_tillage.R` inputs, 2016 to 2023). SIPNET adds
  each event's intensity to a multiplier on heterotrophic respiration that decays with a 30 day
  time constant, so over 1994 to 2013 that multiplier averages 1.12 to 1.13 in CONV, 1.14 in
  CONV+WCC and 1.16 in ORG, against 1.03 to 1.04 in the wheat systems. Whether to keep one event
  per operation or match the product's yearly dose is open (Aritra, 2026-10-31: kept for
  David).
- **Compost basis.** Compost C and N multiply the reported wet tonnage by the %C and %N of
  dry combustion analyses ("Total C and N of incorporated aboveground biomass and composted
  manure were determined each year, using dry combustion analysis", Tautges et al. 2019), the
  basis that reproduces the paper's 40.4 Mg C/ha; the paper's conclusions give 700 to 800 kg C/ha
  a year, about a third of that. The organic minus conventional soil C difference rests most on
  this input.
- **The run's start.** The run starts on 1992-01-01 and the files in fall 1993, so every phase
  is bare for the 1992 and 1993 sudangrass uniformity crops (above). Adding them, or starting
  the run in fall 1993, is open.
- **CONV+WCC corn N.** The paper's rates fill a log with no corn N in any year (David,
  2026-10-29 call), but that corn yielded at organic levels in 1994 to 2007, 3.4 to 8.0 t/ha
  machine harvested dry yield against conventional's 9.0 to 13.4, while its grain N was close
  to conventional's; late planting after the cover crop could explain the yield. The dates
  follow the conventional corn records from the template's last planting (its 1998 replant), so
  the starter can come weeks after planting, as the conventional starter often does in the log,
  and in 2006 after the sidedress. Both this and the 2004 to 2007 tomato are open questions
  about the package (`century_package_issues.md`, items 1 and 3).

## Checks

- All 23 files validate against `events_schema_v0.1.1` from PEcAn `develop` (the stacked
  organic and transitional files still fail it), and `PEcAn.SIPNET::write.events.SIPNET`
  writes an `events.in` for each: 469 `harv`, 473 `plant`, 392 `fert`, 966 `irrig` and 735
  `till` lines, one per event; every irrigation line carries SIPNET code 1 (soil), and the 13
  alfalfa cuttings are `harv 0.85 0 0 0`.
- The 323 recorded fertilization events match the package (their phase-year totals,
  recomputed independently from `operations_fertilizers.csv` and `operations_compost.csv`, agree
  in every phase-year); the other 69 are imputed (17 for 2014, 51 for gaps, 1 for the compost
  year).
- Every planting before 2014 has an end (a same-crop harvest within 365 days, or a cover crop
  end), every harvest has a planting before it, no cover crop ends after the next cash
  crop planting, and no phase has overlapping seasons of two cash crops.
- The script stops if a `plot_system.csv` planting or cash crop harvest in the run has no event
  of the same crop and kind within 30 days in its phase file (history events do not count), if
  a cash crop season of an irrigated system is left without irrigation other than as described
  above, or if a row of `russell_source_corrections.csv` does not match the records it names.
- Rerunning the script reproduces every output byte for byte.

## Rebuild

```
Rscript tools/event_prep/russell_split_phases.R \
  runs/russell_ranch/events_treatments/generator_stacked \
  <path>/RR_2014_datasets \
  runs/russell_ranch/events_treatments
```

`RR_2014_datasets/` is the zip in the data paper's supporting information (also attached to
the Zotero item for `10.1002/ecy.2105`; on SCC at
`/projectnb/dietzelab/ccmmf/data_raw/russell_ranch_century/`). The script reads
`russell_treatments.csv`, `russell_source_corrections.csv` and `russell_harvest_lookup.csv`,
the tillage medians from `monitoring_tillage_near_russell.csv` and the irrigation amounts and
timing from `monitoring_irrigation_near_russell.csv`, all next to `generator_stacked/` (the two
monitoring files can also be given as the 4th and 5th arguments). To remake the monitoring
files from the monitoring products (paths in the script headers):

```
Rscript tools/event_prep/russell_monitoring_tillage.R <monitoring_dir> \
  runs/russell_ranch/events_treatments/monitoring_tillage_near_russell.csv
```

```
Rscript tools/event_prep/russell_monitoring_irrigation.R <monitoring_dir> \
  runs/russell_ranch/events_treatments/monitoring_irrigation_near_russell.csv
```

## Which treatment the run uses

On SCC, `runs/russell-ranch-1992-conv-corn-tomato` and `runs/russell-ranch-1992-conv-tomato-corn`
run the two `conv_corn_tomato` phase files (20 members, 1992 to 2014, the met, IC and PFT
posterior of `runs/russell-ranch-1992`, which still runs the stacked file). Both phases, like the
stacked run, grow almost no canopy (maximum LAI 0.04 to 0.16 against 3 to 6 for these crops) and
lose most of their soil carbon by 2014, so they are not yet usable for calibration. They ran an
earlier version of these files, without the planting-start irrigation schedule, the 2009
sudangrass irrigation, the logged tillage passes and the July wheat disking, and need repeating
with the current ones.
