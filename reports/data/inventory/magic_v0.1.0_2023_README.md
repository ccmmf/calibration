# MAGiC historical inventory SOC and biomass v0.1.0

This review candidate contains modeled total soil carbon (`TotSoilCarb`) and
aboveground biomass (`AGB`) for the MAGiC historical inventory. The prediction
tables represent the **December 2023 monthly mean**. Difference tables are
**December 2023 monthly mean minus January 2016 monthly mean**.

The release retains all 20 original parameter-member identifiers (`ensemble`
1–20) and both crop strata. It covers 385,234 fields and 3,485,601.6801 ha.
Another 9,679 classified fields (41,260.9767 ha) are excluded because required
covariates were missing. State totals therefore mean totals over the covered
fields, not a wall-to-wall California inventory.

## Contents

- `field/`: compressed field-by-member predictions and endpoint changes.
- `state-county/`: county and covered-state member tables and summaries.
- `data-definitions.md`: columns, units and summary definitions.
- `provenance/input-manifest.csv`: concise source and run-input references.
- `manifest.json` and `SHA256SUMS`: measured file inventory and checksums.

`TotSoilCarb` density is Mg C ha-1 and totals are Mg C. `AGB` uses the same
units. AGB is standing aboveground biomass at the modeled monthly endpoint; it
is not annual production.

N2O: spatial inventory results are pending. CH4: spatial results are pending.
Missing gas results are not zero, and this is not a complete GHG inventory.

## Reproducibility references

- Model: [SIPNET v2.2.0](https://github.com/PecanProject/sipnet/releases/tag/v2.2.0),
  commit `3ccc41c1ad2db426b7eb857881a32ca685bf57f1`. The historical run also used a
  preserved zero-carbon/N repair, so its results should not be attributed to an
  unmodified later release.
- Downscaling: [ccmmf/downscaling](https://github.com/ccmmf/downscaling), commit
  `6b1402f6a6cd67be17508a933fe26b6e60ecd1fd`, plus the preserved compatibility
  patch used by the run.

This is a preliminary `v0.1.0` review release. Once uploaded, these versioned
objects should be treated as immutable; corrections or gas additions should use
a new version rather than replace this release.
