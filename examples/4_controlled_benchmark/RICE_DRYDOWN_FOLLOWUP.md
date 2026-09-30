# Rice dry-down and methane follow-up

## Decision

Do not lengthen the archived irrigation-omission calendar. That would create a
42- to 70-day drought sensitivity, not a California mid-season drain. Retain
that run as evidence that omission alone does not realize the intended
hydrologic treatment. The new experiment separates a California field-reference
trajectory, a California-timed threshold-crossing stress test, a
calendar-matched reproductive-stage severe-field trajectory, and a one-time
drain followed by SIPNET's own water balance. The prescribed trajectories are
suitable methane-formulation diagnostics. The one-time-drain result directly
tests the available hydrologic mechanism, but none is a validated field
simulation.

This change cannot be implemented faithfully in the calibration repository
alone. SIPNET v2.2.0 has irrigation inputs and a global drainage parameter, but
no event that drains a field. The PEcAn SIPNET event writer likewise translates
irrigation only as a positive water addition. A model-supported drain event is
therefore the next implementation check. Until that exists, a forced water-state
experiment can test the methane equation but must remain labeled as a
formulation diagnostic rather than a field treatment. A model-supported drain
event remains the preferred implementation.

## Acceptance status

| Criterion | Status | Evidence |
|---|---|---|
| California timing and duration | Met | One June 19–28 interruption, followed by June 29 reflood |
| Reproductive severe-field timing and duration | Met | The July 15–24 model interval starts 61 days after planting and lasts 10 days; observed first cycles started 57–66 days after sowing and lasted 7–13 days before reflooding |
| Realized water trajectory below `fAnoxia` | Met only when prescribed | June ratios reach 0.238 and 0.232 and reproductive-stage ratios reach 0.240 and 0.231 for two days per year |
| One-time drain followed by model-evolved drying | Does not meet threshold | Removing water above `soilWHC` once yields minima of 0.838 and 0.698, with no threshold crossings |
| Endpoint above permanent wilting | Supported, not validated | SSURGO available-water mapping places stress minima at VWC 0.287–0.286 and 0.181–0.182, above mapped 15-bar values |
| Field precedent below `fAnoxia` | Met for severe stress | A USDA Arkansas field treatment reached 15% VWC, equivalent to an available-water ratio of 0.117 |
| Combined field timing and below-threshold endpoint | Demonstrated as a prescribed trajectory, not as model hydrology | Timing and severity both match field bounds, but SIPNET does not produce that trajectory after a one-time drain |
| Model-supported drainage process | Not met | Water is removed through explicit restart-state edits because SIPNET has no drain event |
| Methane response | Met as a deterministic diagnostic | Dry-period methane falls 94%–96%; seasonal methane falls 8%–11%, including the model-evolved one-time-drain path |

## Evidence

The archived pilot omits 1 cm/day irrigation for 14 days. With the source
`waterDrainFrac` of 0.05355/day, the minimum soil-water ratios are 1.002 and
0.816 at locations 413887 and 535358, respectively. Neither location reaches
the source-run `fAnoxia` value of 0.286 in any of the eight forcing years. Seasonal
methane ratios are 0.999995 and 0.999935. The original result is therefore a
failure to realize sustained drainage, not evidence that SIPNET methane is
insensitive to soil water.

A local sensitivity run set `waterDrainFrac` to 1, so all water above holding
capacity could drain each day. This is a diagnostic proxy, not an event-specific
management representation. With the same 14-day omission, minimum water ratios
fall to 0.756 and 0.610, still above `fAnoxia`, while seasonal methane ratios
fall to 0.865 and 0.833 relative to matching continuous-irrigation baselines.
The methane formulation responds before the water state reaches `fAnoxia`.

Longer fixed omissions do not repair the experiment. A 42-day sensitivity
reaches `fAnoxia` in zero of eight years at location 413887 and two of eight
years at location 535358. A 70-day sensitivity reaches it in four and seven
years, respectively. Only the full-season no-irrigation bound reaches it in all
years. Under that bound, the first crossing occurs 30 to 80 days after May 15.
These durations do not represent the intended field practice.

The one-timestep response test independently verifies the methane calculation
for the archived source-run parameters. With `fAnoxia = 0.28624` and
`anaerobicTransExp = 99.98298`, the implemented
moisture multiplier is 1 at saturation, 0.244 at a water ratio of 0.99, and
0.000702 at 0.95. The pinned SIPNET run reproduces the 0.99 response within its
printed output precision and prints zero by 0.95. At or below `fAnoxia`, the
multiplier is exactly zero. This separates methane-formulation response from
the hydrologic failure in the archived pilot.

## Field-timed drainage and state-forcing experiment

The bounded follow-up starts one dry-down on June 19, 35 days after the May 15
planting date, and refloods on June 29, 45 days after planting. This matches the
California timing window. A reproductive-stage path starts July 15, reaches its
endpoint July 24 at 70 days after planting, and refloods July 25. This timing is
directly bracketed by the Arkansas field protocol: first cycles began 57–66
days after May 9 sowing and lasted 7–13 days before reflooding. During each
prescribed ten-day dry-down, the script changes only `envi.soilWater` in daily
restart checkpoints and omits scheduled irrigation. A fourth treatment removes
only ponded excess at the July start, then lets SIPNET evaporation and
transpiration determine the trajectory until the same reflood date. All paths
reflood to holding capacity plus 5 cm.

The primary field-reference path declines from a ratio of 1.0 to a target of
0.595, the upper end of the 0.48–0.596 dry/flood VWC ratio reported for the
severe California AWD25 treatment. A stronger soil-based comparison uses the
published field coordinates and mapped available water: the observed 24%–28%
VWC corresponds to 0.469–0.719 of available water. Subsequent model losses
produce realized daily minima of 0.528 at location 413887 and 0.477 at location
535358, both within that observed field range under the survey mapping. Neither
location crosses `fAnoxia`. The separate severe-stress diagnostic continues to
0.25 and realizes minima of 0.238 and 0.232. It crosses `fAnoxia` on exactly two
days in every year. The reproductive-stage severe-field path uses the same
target schedule and realizes minima of 0.240 and 0.231, also crossing
`fAnoxia` on exactly two days in every year. These endpoints remain above mapped
15-bar water content at both modeled sites. They are drier than the Carrijo
observations and are treated as severe-stress diagnostics, not safe AWD.

The one-time-drain comparator does not reproduce the field severity. After
water above `soilWHC` is removed once, ten irrigation-free days reach minimum
ratios of only 0.838 and 0.698. Neither site crosses `fAnoxia`. This is stronger
evidence than the earlier omission-only run: even explicit initial removal of
ponded excess leaves SIPNET's modeled evaporation and transpiration too small
to produce the observed severe dry-down with these crop states and parameters.
Reaching the 0.25 target from `soilWHC` requires 9 cm of net storage loss, or
0.9 cm/day. The maximum realized losses are only 1.94 and 3.63 cm, equivalent
to 0.19 and 0.36 cm/day. The required loss is therefore 4.63 and 2.48 times the
maximum modeled loss at the two sites. This is a net storage comparison, not a
partitioned flux budget.

The flux diagnostics identify the associated crop-state limitation. Mean
dry-period evapotranspiration is 0.170 and 0.268 cm/day, but transpiration is
only 0.0034 and 0.0008 cm/day—2.0% and 0.3% of evapotranspiration. Simulated LAI
ranges from 0.030 to 0.072 m²/m². The current crop state therefore contributes
almost no transpiration to the dry-down. A drainage-event implementation alone
cannot establish a realistic experiment without first resolving crop
establishment and canopy water use.

On the June reflood date, minimum ratios return to 1.452 and 1.418; the July
path returns to 1.458 and 1.446. Baseline and all four treatments use the same
restart segmentation, retain 2,922 complete days and eight subdaily steps per
day, and have identical 23,376-row time support. Each treatment matches its
baseline before its first dry-down.

Methane responds strongly without threshold crossing. In the field-reference
path, dry-down-period methane ratios are 0.0480 at location 413887 and 0.0420 at
location 535358, decreases of about 95%. May 15–September 10 ratios are
0.9082–0.9083 and 0.8966–0.8967 across the two preparation lengths, seasonal
decreases of 9.2%–10.3%. Continuing to the June 0.25 threshold-stress endpoint
changes the seasonal ratios only to 0.9057–0.9058 and 0.8935–0.8937. Moving the
same severe schedule to July gives dry-down methane ratios of 0.0475–0.0476 and
0.0336–0.0337, decreases of 95.2% and 96.6%, and seasonal ratios of
0.9057–0.9058 and 0.8945–0.8946. These are deterministic responses to
prescribed state paths and the archived parameter files, not estimated field
effects.

The model-evolved one-time-drain path still produces a strong methane response
without approaching `fAnoxia`. Dry-period methane ratios are 0.0555 at location
413887 and 0.0368 at location 535358, decreases of 94.4% and 96.3%. Seasonal
ratios are 0.9161 and 0.9068 across preparation lengths, decreases of 8.4% and
9.3%. With the source-run transition exponent near 100, crossing `fAnoxia` is
not required for near-complete dry-period suppression.

Parameter provenance materially qualifies those methane magnitudes. The
archived PFT bundle and statewide experiment configuration explicitly fix
`anaerobicTransExp = 99.98298` as a common soil value. The configuration writes
that value into `sipnet.default.param`; the runner removes
`anaerobic_trans_exp` from the PFT samples so PEcAN cannot overwrite it. This is
a documented modeling decision, not a fitted value or an accidental
`woodCN` substitution. The exact package build used on September 17 was later
replaced, but the archived default, generated parameter files, configuration,
and runner agree on the fixed-parameter contract.

The same archived `soil_rice` posterior retains a lognormal
`anaerobic_trans_exp` distribution with a median of 9.97418. An exact
sensitivity rerun used that posterior median on the threshold-stress path while
changing no other input. The realized water trajectory was unchanged. Dry-down methane
ratios increased to 0.111–0.116, an 88.4%–88.9% decrease rather than the
95.2%–95.8% decrease under the source-run value. Seasonal methane ratios became
0.900–0.912, an 8.8%–10.0% decrease. The source-run exponent therefore sharpens
the diagnosed methane response, but resolving it does not close the field
comparison gap. The posterior-median value is a comparator, not an accepted
correction or calibrated replacement. The remaining provenance question is the
unrecorded exact PEcAn package build, not the source experiment's intent; the
remaining scientific question is whether the fixed exponent is defensible.

The field-reference seasonal response is substantially smaller than the closest California
field comparison. Perry et al. (2022) tested single drains lasting about 5, 8,
or 12 days and starting 34–49 or 45–59 days after seeding; seasonal methane
fell 38%–66% relative to continuous flooding. Those plots and soils are an
external comparator, not validation data for these two model locations. Within
the same field-supported 34–49 day start range, only 4.4%–11.4% of baseline
SIPNET seasonal methane occurs in the best 5–12 day window. Even forcing methane
to zero only within the best window therefore cannot reproduce the field
seasonal response. The current methane calculation depends on the current soil
water ratio, temperature, and carbon pools, with no explicit redox or microbial
state that preserves suppression after reflooding. Changing the drain date
alone cannot resolve this discrepancy. See the [field study](https://doi.org/10.1016/j.fcr.2021.108312)
and the [window upper bounds](results/methane_window_upper_bounds.csv).

The intervention is intentionally explicit about its hydrologic limitation.
Across eight years the field-reference path externally removes 125–136 cm of
water and adds 85–87 cm at reflooding; the June threshold-stress path removes
153–166 cm and adds 113 cm. The reproductive-stage path removes 159–177 cm and
adds about 113 cm. The one-time-drain path removes 101–113 cm and adds 54–61 cm
across eight years. The largest single removal is 14.4 cm because the archived
state begins the interruption far above holding capacity. Those adjustments are
not SIPNET fluxes or a validated water budget. The one-time drain isolates the
remaining model-evolved loss, while the prescribed paths show the methane
response to field-supported endpoints.

The archived source run uses `soilWHC = 12 cm` and does not identify a
depth-resolved soil-physics file. SIPNET v2.2.0 documents `soilWater` as
plant-available soil water and `soilWHC` as its cap, so a ratio of zero should
be interpreted as the wilting-point end of the available-water range rather
than zero absolute VWC. Even so, the integrated `soilWater / soilWHC` ratio is
not a direct measurement of 0–15 cm VWC because the configured storage depth
and site hydraulic profile are absent. The survey-based conversions below are
therefore physical plausibility checks, not site calibrations.

Current PEcAn interfaces do not resolve that missing contract consistently.
The generic water-balance code defines holding capacity as field capacity minus
wilting point, but the SIPNET configuration writer integrates saturation VWC
when a soil profile is supplied, and the output adapter labels SIPNET's
available-water fraction as `SoilMoistFrac`. The archived runs supplied no soil
profile and retained the fixed 12 cm value, so the adapter behavior does not
change their interpretation. It is an integration issue to resolve before a
production hydrology experiment.

A bounded conversion check makes that mismatch explicit. Carrijo et al. (2018)
reported 47%–50% VWC under continuous flooding and minimum 0–15 cm VWC ranges
of 41%–44%, 30%–33%, and 24%–28% for increasingly severe dry-downs lasting
about 3, 7, and 11 days. Dividing dry by flooded VWC without a residual-water
correction gives ratios of 0.82–0.94, 0.60–0.70, and 0.48–0.60. Those are useful
zero-residual sensitivity bounds, not the documented SIPNET available-water
mapping.

A point query to USDA SSURGO adds site-specific survey bounds, not field
validation. The dominant surface component at location 413887 is mapped as
Rindge muck, with available water of 0.270 and 15-bar VWC of 0.222. Location
535358 is mapped as Tehama silt loam, with available water of 0.210 and 15-bar
VWC of 0.133. Using the documented available-water interpretation,
`theta = theta_15bar + ratio * AWC`, maps `fAnoxia` to VWC of 0.299 and 0.193.
The 0.25 target maps to 0.290 and 0.186. The realized June stress minima map to
0.286 and 0.182, and the reproductive-stage minima map to 0.287 and 0.181. All
are above the mapped 15-bar values.

The published Carrijo field coordinate maps to an Esquon surface horizon with
47% clay, close to the paper's reported 45%, 15-bar VWC of 0.165, and available
water of 0.160. The observed 24%–28% VWC therefore maps to available-water
ratios of 0.469–0.719. Both field-reference minima fall within that interval;
the threshold-stress minima fall below it. At this field site, `fAnoxia` maps
to VWC 0.211 and the 0.25 target maps to 0.205, 3–8 percentage points below the
observed minima. The observed AWD25 treatment reached approximately −69 to
−73 kPa and did not reduce yield, but it does not support the drier modeled
endpoint. The old zero-based saturation
calculation is retained in the evidence table as an alternative interpretation,
but it maps `fAnoxia` below wilting and conflicts with the fixed-WHC run's
documented plant-available-water semantics. SSURGO describes mapped components
rather than sampled field soil, and the source run did not use these values, so
the result establishes physical plausibility rather than validating hydrology.
See the
[field study](https://doi.org/10.1016/j.fcr.2018.02.026) and
[conversion bounds](results/field_moisture_mapping.csv), plus the
[site soil mapping](results/site_soil_hydraulic_mapping.csv) and
[field-site soil mapping](results/field_site_soil_hydraulic_mapping.csv).

A second field comparison establishes a more severe bound. USDA experiments at
the Dale Bumpers National Rice Research Center identify the soil as Dewitt silt
loam. The mapped surface horizon has 15-bar VWC of 0.129 and available water of
0.180. One four-cycle AWD30 experiment reached minimum 5-cm VWC of 0.23, an
available-water ratio of 0.561, still above `fAnoxia`. A separate two-year
severity experiment reached approximately 0.30, 0.21, and 0.15 VWC under low,
medium, and high reproductive-stage AWD stress. Using a facility-point SSURGO
mapping that returns the same Dewitt series, these map to available-water
ratios of 0.95, 0.45, and 0.117. The high field treatment therefore crossed the
equivalent SIPNET threshold; the current 0.25 target is bracketed by the medium
and high field severities. The precise experimental plot coordinate is not
reported, so this is evidence that the endpoint is field attainable as severe
stress, not a site calibration or evidence that it is safe AWD: high stress
reduced rice and red-rice yields by as much as 50% and 60%. The separate July
model path starts 61 days after planting and lasts 10 days, within the observed
first-cycle ranges of 57–66 days after sowing and 7–13 days from drain to
reflood. Exact emergence and plot-coordinate information remain unavailable.
See the
[timing record](https://www.ars.usda.gov/research/publications/publication/?seqNo115=370626),
[severity record](https://www.ars.usda.gov/research/publications/publication/?seqNo115=378751),
[AWD30 study](https://doi.org/10.3389/fpls.2020.612054), and
[field-severity mapping](results/field_severity_comparators.csv).

SIPNET reports one nitrogen-balance warning per harvest year in the baseline
and all four treatment runs. The counts and maximum absolute deltas match within
each task (maximum 0.004162), with no carbon-balance warnings or error lines.
This makes the warnings pre-existing rather than specific to the forced
dry-down, but it does not resolve them.

The [candidate results](results/rice_drydown_followup.csv),
[one-timestep response](results/methane_moisture_response.csv), and
[original provenance record](results/rice_drydown_provenance.json) retain the
earlier bounds. The [forced-run summary](results/forced_drydown_summary.csv),
[realized trajectory](results/forced_drydown_trajectory.csv),
[external water ledger](results/forced_water_adjustments.csv),
[log audit](results/forced_drydown_log_audit.csv),
[methane-window bounds](results/methane_window_upper_bounds.csv),
[model-evolved storage-loss gap](results/natural_drydown_gap.csv),
[forced-run provenance](results/forced_drydown_provenance.json),
[parameter sensitivity](results/anaerobic_exponent_audit.csv), and
[parameter-audit provenance](results/anaerobic_exponent_audit_provenance.json),
[field-moisture bounds](results/field_moisture_mapping.csv), and
[field-moisture provenance](results/field_moisture_mapping_provenance.json),
[site soil mapping](results/site_soil_hydraulic_mapping.csv), and
[field-site soil mapping](results/field_site_soil_hydraulic_mapping.csv), and
[field-severity mapping](results/field_severity_comparators.csv) with its
[provenance](results/field_severity_comparators_provenance.json), and
[site soil provenance](results/site_soil_hydraulic_mapping_provenance.json)
retain the new support checks, inputs, revisions, comparators, and diagnostic
status. These local runs did not submit cluster jobs and do not replace the
archived controlled-benchmark results.

## Field interpretation and revised acceptance criteria

UC ANR guidance for California rice recommends one mid-season drain, beginning
about 35–40 days after planting and reflooding around 45–50 days after planting.
The field should remain dry for about 7–10 days after it is no longer flooded;
reported total drain periods are commonly 8–12 days. Multiple dry-downs are not
the preferred California comparison. See [Agronomy Fact Sheet 23](https://ucanr.edu/sites/default/files/2026-04/February%202025%231.pdf)
and the [California Rice Production Workshop manual](https://rice.ucanr.edu/files/288574.pdf).

The next rice experiment should therefore require all of the following before
methane magnitude is interpreted:

1. one mid-season drain in the California timing window;
2. explicit removal of ponded excess rather than only omission of future inputs;
3. 7–10 realized days below saturation before reflooding, with the endpoint
   checked against a field-supported dry/flood moisture ratio;
4. prompt return to the flooded state after the dry period;
5. matched initial state, weather, crop operations, and methane parameters;
6. daily and subdaily water-ratio, anaerobic-index, and methane diagnostics.

Crossing `fAnoxia` should remain a reported severe-stress test, not the
field-practice acceptance threshold. The corrected available-water mapping
shows that both threshold-stress paths are above permanent wilting, and the
Arkansas high-stress experiment demonstrates that a rice field can pass the
equivalent threshold. That treatment imposed reproductive-stage stress and a
large yield penalty. The July path matches the first-cycle field timing range,
but only the prescribed path reaches the observed severity. The one-time drain
does not, so timing agreement does not validate SIPNET hydrology or the
California-timed modeled path.
With the deliberately fixed source-run transition
exponent near 100, SIPNET methane is already strongly suppressed just below
saturation. The state-forced run crosses the threshold within the field timing
window only because the water path is prescribed. The one-time-drain comparator
confirms that the current water balance does not produce that normalized value.

## Next check

Do not encode drainage as negative irrigation. SIPNET v2.2.0 accepts a negative
soil-method irrigation amount and records negative `eventSoilWater`, but the
documented interface defines irrigation as water added, and the PEcAN adapter
does not define this as a drain. Using that behavior would exploit missing input
validation rather than establish a supported management contract.

A defensible next experiment needs four ordered prerequisites: credible rice
establishment, canopy growth, and evapotranspiration under the flooded baseline;
a site- and depth-specific mapping between SIPNET storage, residual water, and
measured volumetric water content; a model-supported event that removes ponded
water and reports its destination; and an explicit decision about whether
post-drain methane suppression requires a redox or microbial state. The first
check should trace why a 1 g C/m² leaf planting event produces July LAI below
0.08 rather than tuning water parameters to compensate for the sparse canopy.
Only after those gates should the two-location pilot be repeated and compared
with the state-forced diagnostic. A parameter ensemble or statewide experiment
would otherwise propagate known structural and parameter-justification gaps. Before that repeat,
decide whether the common fixed `anaerobicTransExp` is scientifically justified
or whether the rice-soil posterior should govern the experiment, and record the
exact installed package revision with the regenerated configurations.
