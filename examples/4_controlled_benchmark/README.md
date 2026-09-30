# Controlled management benchmark

This example evaluates controlled baseline–practice comparisons using the existing
100-site environmental frame and prepared PEcAn inputs. It is a model-capability
and experiment-design pilot, not an estimate of adoption benefits.

## Experiment contract

`candidate_comparisons.csv` records whether each proposed comparison retains its
definition, needs revision, or is deferred. Crop systems, evidence, baselines,
practices, durations, outputs, model capabilities, and next actions are explicit.

`pilot_spec.json` is the executable specification. It selects annual-row locations
14 and 54800 (15.0/17.2 °C; 18.8/51.3% clay) and rice locations 413887 and 535358
(16.4/18.3 °C; 42.6/32.3% clay). These environmental values come from the frozen
site metadata, not from new climate extraction. Both rice cases have rice
vegetation and soil parameters; a rice soil alone does not establish a rice crop.

The annual calendar is a processing-tomato management archetype represented by
the existing annual-row PFT. Its 200 kg N/ha lies within the UC guide's
140–280 kg N/ha range. Calendar dates, irrigation, harvest fractions, and planting
carbon are explicit diagnostic assumptions. A winter annual cover is planted
October 15 and terminated April 1; it receives no additional fertilizer or
irrigation. It uses the same PFT, so this is not a species-resolved tomato–cover
rotation. Orchards requiring concurrent vegetation are deferred, not classified
as inappropriate for cover cropping.

Rice has a May–October crop, explicit 160 kg N/ha preplant N, and 1 cm/day soil
irrigation from May 10 through September 10. Treatments omit irrigation during
one or two 14-day windows. This prescribes interruptions, not assured drainage;
water output determines whether an AWD comparison is supported.

Each location has separate 8- and 16-year baseline preparation cases. Preparation
recycles the existing 2016–2023 forcing in whole eight-year blocks preceding 2016,
preserving leap-year alignment. This is synthetic preparation weather, not a
reconstruction of historical climate or a claim of equilibrium. Baseline,
no-change control, and practice scenarios restart from an identical complete
checkpoint within a preparation case. Evaluation is 2016–2023. Cover first
establishes in autumn 2016, so the first completed cover season ends in 2017.

Planting adds explicit leaf, stem and root C. The pinned model requires positive
stem and root pools for a living plant. A planting event already supplies leaves;
no additional leaf-on mobilization is prescribed. Complete harvest removes or
transfers all above- and below-ground biomass; output checks verify the bare
period rather than assuming that input fractions guarantee termination.

## Reuse and boundaries

The example copies the existing PEcAn-written `sipnet.in` and `sipnet.param`,
uses each location's forcing, and runs the exact executable with SHA-256
`16a626ae36bc94f995f606f7f5a32d630796971617310ada888c2ec591c6c0c9`.
It uses SIPNET's restart interface and the existing SGE execution pattern; the
installed `PEcAn.SIPNET::model2netcdf.SIPNET()` converts evaluation outputs.
No original input or run is modified. The experiment does not alter generic
calibration interfaces, authoritative evidence, or SIPNET source code.

The original scenarios remain in the frozen report bundle. They have different
crop histories, treatment exposure and initialization. Comparing their aggregate
effect against this pilot does not isolate standardization alone, so they are
retained as contextual diagnostics rather than combined into a paired test.

## Reproduce on Geo

Use a new output directory each time; staging refuses to overwrite one. The
source workspace is the prepared matrix, not a mutable source repository.

```sh
python3 prepare_pilot.py --spec pilot_spec.json \
  --source /projectnb/dietzelab/ccmmf/usr/akash/statewide_matrix/pecan_v1 \
  --workspace /path/to/new/pilot
```

Copy `run_pilot.py`, `pilot.sge`, `summarize_pilot.py`, `audit_logs.py`,
`convert_pilot.R`, `convert.sge` and the
frozen `sites.csv` into the new workspace. Submit `pilot.sge` with an eight-task
array from that directory. Each task runs one baseline preparation followed by
its paired/control evaluations. Only launch the following after the tasks finish:

```sh
python3 summarize_pilot.py /path/to/new/pilot
python3 audit_logs.py /path/to/new/pilot
module load R/4.4.3 udunits/2.2.28 gdal/3.10.2
export R_LIBS_USER=/projectnb/dietzelab/ccmmf/usr/dlebauer/R/x86_64-pc-linux-gnu-library/4.4
Rscript --vanilla convert_pilot.R /path/to/new/pilot sites.csv
```

`submission.txt` identifies the completed workspace and scheduler jobs.
`input_manifest.json` records source runs and input hashes. Full time-step
outputs, restart checkpoints, logs and converted netCDF remain in that workspace;
compact diagnostics and paired effects are retained locally. The output summary
checks complete dates, common restart identity and byte-identical no-change
outputs. Raw timestep gas totals are converted from g C/m² to kg C/ha; soil
stocks are converted from g C/m² to Mg C/ha. The PEcAn check independently matches
annual soil endpoints and GPP totals after pool and unit conversion. The installed
converter expects a metadata line before the raw header; the wrapper supplies
that line in a temporary derived input and preserves the raw output. This
installed converter does not expose methane, so methane summaries use the
verified raw-output contract. `converter_provenance.txt` records its runtime.
`results/manifest.json` pins the final summary and implementation files.

## Ensemble readiness

`calibrated_process_ensemble.csv` contains the 50 joint draws from the verified
final calibration result. The three column means reproduce the fitted values
used by the existing statewide matrix. The provenance file records the source,
checksum, seed and calibration settings. The experimental initial states for
Salinas systems 1–8 are deliberately excluded.

`ensemble_summary.R` accepts one effect per comparison, group, location and
member. It rejects duplicates, nonfinite effects and differing location sets.
It aggregates locations within each member before reporting 90% intervals and
fractions above, below and equal to zero. Pass differences or log ratios, with
zero as no change; do not pass uncentered RR. These are conditional ensemble
fractions, not calibrated probabilities by assertion. A local test covers the
order of aggregation and missing/duplicate behavior.

Expansion and ensemble simulation require interpretable crop baselines, realized
practices, matched quantities and satisfactory preparation diagnostics. Agreement
in sign or magnitude with the literature is not an expansion condition.

## Verification

From the repository root:

```sh
python3 -m unittest discover -s examples/4_controlled_benchmark -p test_pilot.py
Rscript examples/4_controlled_benchmark/test_ensemble.R
Rscript reports/R/build_controlled_benchmark.R
quarto render reports/controlled_benchmark.qmd
```

The companion report records the evidence-based decision for each pilot comparison.
