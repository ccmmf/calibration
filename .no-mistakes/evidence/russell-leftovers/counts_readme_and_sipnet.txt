# Fertilization counts recounted from the 23 committed phase files (target) and from the previous build
## target
files: 23; fertilization events: 412
cls
  assumed   derived   imputed published 
       19        23        89       281 
kind
gap (season with no record)                       other 
                         49                          22 
         single application 
                         18 
other imputed notes (first 150 chars):
gap events at the paper's rates (source 10.1111/gcb.14762): 43; copied as logged: 6
## previous build (1ac7c8f)
files: 23; fertilization events: 413
cls
  assumed   derived   imputed published 
       19        23        90       281 
kind
gap (season with no record)                       other 
                         51                          22 
         single application 
                         17 
other imputed notes (first 150 chars):
gap events at the paper's rates (source 10.1111/gcb.14762): 43; copied as logged: 8

## README.md lines that state these counts (target)
| fertilization gap | a season the log has no fertilization for, dated from comparable records; corn and irrigated wheat N take Tautges et al. 2019's rates on the copied dates, rainfed wheat N and compost copy the record (see "Fertilization gaps") | 49 (N 43: corn 37 and irrigated wheat 6 at the paper's rates; compost 6) |
| single application | a season with records but without its preplant or its in-season application copies that application, as logged, from the nearest season with both of the treatments that share its synthetic N management (see "Fertilization gaps") | 18 (wheat preplant 8, wheat topdress 1, tomato starter 9) |
  from a season with one preplant record): 18 events, tagged `imputed`. The groups are
  (NPK only, 80 days after planting) and 1999 tomato N stay as logged. No corn starter is ever
  filled: the conventional corn starter is logged 22 to 42 days after the last planting in 8 of
  its 14 seasons (item 13), so fewer than half show a preplant; every recorded corn season has
  both its products.
- All 23 files validate against `events_schema_v0.1.1` from PEcAn `develop` (the stacked
  organic and transitional files still fail it), and `PEcAn.SIPNET::write.events.SIPNET`
  writes an `events.in` for each: 492 `harv`, 496 `plant`, 412 `fert`, 1035 `irrig` and 1075
  `till` lines, one per event; every irrigation line carries SIPNET code 1 (soil), and the 13
  alfalfa cuttings are `harv 0.85 0 0 0`.
- The 323 recorded fertilization events match the package (their phase-year totals,
  recomputed independently from `operations_fertilizers.csv` and `operations_compost.csv`, agree
  in every phase-year, with the moved 1999 and 2011 urea on their wheat plots); the other 89 are
  imputed (19 for 2014, 49 for seasons with no record, 18 single applications, 2 missing plot
  shares, 1 for the compost year).

## PEcAn.SIPNET::write.events.SIPNET over all 23 files (the schema ERRORs it logs come from the installed PEcAn.data.land 1.9.0.9000, which lacks events_schema_v0.1.1; identical in both builds, not this change)
### target
23 files written through PEcAn.SIPNET::write.events.SIPNET; line counts: harv 492, plant 496, fert 412, irrig 1035, till 1075

rf_wheat_fallow fallow-wheat events.in, fert lines 1998-08-01 .. 1999-09-01 (year doy fert org_N org_C min_N ...):
  1998  274  fert   0 0 8.413   # 1998-10-01
  1999  63  fert   0 0 2.954   # 1999-03-04

rf_wheat_fallow wheat-fallow events.in, fert lines 1998-08-01 .. 1999-09-01 (year doy fert org_N org_C min_N ...):
  (none)
### previous build
23 files written through PEcAn.SIPNET::write.events.SIPNET; line counts: harv 492, plant 496, fert 413, irrig 1035, till 1075

rf_wheat_fallow fallow-wheat events.in, fert lines 1998-08-01 .. 1999-09-01 (year doy fert org_N org_C min_N ...):
  1998  274  fert   0 0 8.413   # 1998-10-01
  1999  72  fert   0 0 2.784   # 1999-03-13

rf_wheat_fallow wheat-fallow events.in, fert lines 1998-08-01 .. 1999-09-01 (year doy fert org_N org_C min_N ...):
  1999  63  fert   0 0 2.954   # 1999-03-04
