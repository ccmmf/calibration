# salinas soc calibration example

worked example that runs the generic `calibration` package on one real dataset:
soil carbon at the salinas organic cropping systems trial, eight management
systems. everything soc and salinas specific lives here; `R/` stays generic.

## run it

from the package root, with the pecan modules loaded:

```
Rscript scripts/010_prepare_observations.R --config examples/salinas_soc/config.yml
Rscript scripts/020_build_priors.R          --config examples/salinas_soc/config.yml
Rscript scripts/030_calibrate.R             --config examples/salinas_soc/config.yml
Rscript scripts/040_plot.R                  --config examples/salinas_soc/config.yml
```

010 caches the target, 020 the prior, 030 runs the ensemble kalman inversion and
caches the result, 040 writes the figures and scores.

## what it calibrates

- `som_respiration_rate` from the soil pft meta-analysis posterior (pecan maps it
  to `baseSoilResp`).
- `soil_respiration_Q10` and `turn_over_time` from the soil pft bety priors, set
  in the config, not tuned to the data.
- per system initial soil carbon (`soilInit.<system>`), anchored to each system's
  year 2 observation and free to update.

launching is left to pecan and the prepared host block in the forward run's
settings (qsub, sge_array_launcher.sh, Njobmax, qstat), used exactly as written.

## what we fit, and why

- **fitting window is study_year 2 to 8.** the measured soil carbon drops sharply
  in the first year, between 2003 and 2004, as the cropping systems are
  established. that first year drop is a one-time disturbance, not gradual
  decomposition, and a first order soil model should not be pushed to reproduce a
  change that large in a single step. so year 0 to 1 is left out of the fitted
  target: the model is initialized at the year-2 stock and the fit runs from
  study_year 2 onward.
- **initial soil carbon** (`soilInit`) is anchored to each system's year-2
  measured stock, converted from the reported Mg/ha to the model's kg/m2.
- **depth:** the observation is a 0-30 cm stock and the harvest reads the whole
  model soil pool (`TotSoilCarb`); the two are aligned by anchoring `soilInit` to
  the measured 0-30 cm stock. meta carries the depth window.
- **treatments as sites:** each treatment is one site in the multisite run, so
  `soilInit.<system>` maps to that system's site id in the settings.
