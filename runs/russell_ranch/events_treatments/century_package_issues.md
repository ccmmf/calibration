# Century package: records that look missing or inconsistent

Records in the Century Experiment data package that look missing, duplicated, misfiled or
inconsistent: Wolf et al. 2018, "The century experiment: the first twenty years of UC Davis'
Mediterranean agroecological experiment", *Ecology* 99:503, doi `10.1002/ecy.2105`, supporting
information `RR_2014_datasets/`. They are what the package maintainers would need to hear: where
we expected data and found none, and where the files disagree with each other, with the package
metadata or with Tautges et al. 2019 (doi `10.1111/gcb.14762`) (David on calibration#10). How the
event files handle each one is in [README.md](README.md); this file only records the package.

The list came from three independent passes over the package: the fix lists and notes in
`tools/event_prep/russell_split_phases.R`, a cross-file audit of the operation logs against
`plot_system.csv` and the crop sample files, and a comparison of Tautges et al. 2019 and the
package metadata with the records. Each item was then re-derived from the raw CSVs by a separate
check that tried to refute it; 26 items had details corrected and none was refuted. Items are
numbered
through the file and cite each other by number.

## Conventions

Plot ids, system names and dates are quoted as they appear in each file. Line numbers count the
header as line 1. `wheat_harvests_all.csv` stores dates as spreadsheet serial numbers, so for
that file we give the serial and the date it converts to. Where we cite Tautges et al. 2019 we
use its system codes; item 57 gives how we map those codes to the package names.

## Records

### `operations_fertilizers.csv`

1. Legume/Corn/Tomato corn has no nitrogen row in any year. This covers plots 2-4, 4-4, 6-9
   (corn in even years) and 1-1, 6-3, 6-7 (corn in odd years), for the corn seasons 1994 to 2007
   and 2013. Of the 128 Legume/Corn/Tomato rows, 104 are Tomato, 18 Wheat, 3 Sudangrass and 3
   Corn. The three Corn rows are Super Triple Phosphate with 0 N on 5/20/1999 (lines 282 to
   284). None of these plots appears under another system name. The corn was seeded every corn
   year: `operations_planting.csv` has seedings from 5/5/1994 to 5/14/2007 and on 3/25/2013, and
   1998 is in `plot_system.csv` only (item 21). By calendar year of application, recorded N over
   1994 to 2012 averages 79.07 kg N/ha per plot and year for Legume/Corn/Tomato. Conventional
   Corn/Tomato averages 185.23, and its corn has N rows in every corn year (130.28 to 314.35 kg
   N/ha a season). We expected starter and sidedress rows. The metadata describes LMT as mineral
   fertilizer plus WCC. Tautges et al. 2019 give CONV+WCC synthetic N at 168 kg/ha a year, and
   for maize in CONV and CONV+WCC a 56 kg N/ha starter plus a 180 kg N/ha sidedress. The 1994 to
   2007 yields (3392 to 8027 kg/ha, against 8996 to 13427 for Conventional Corn/Tomato) would
   fit little or no N. In 2013, though, the two systems yielded about the same (12154 and 12635
   kg/ha). Was this corn fertilized?

2. No corn nitrogen in 2013, although the seeding rows say Seed_fertilize. Conventional
   Corn/Tomato 1-3, 4-5, 8-9 and Legume/Corn/Tomato 1-1, 6-3, 6-7 were seeded to corn on
   3/25/2013 and harvested 10/1/2013. Their six seeding rows (`operations_planting.csv` lines
   26, 63, 118, 449, 538, 569) are the only Seed_fertilize rows in that file. Yet
   `operations_fertilizers.csv` has no row dated 3/25/2013, and no Corn row after 5/24/2007 in
   any system. The only 2013 N in these two systems is UAN 32 at 134.5 kg N/ha on 5/10/2013, on
   their tomato plots. We expected starter and sidedress rows, as Conventional Corn/Tomato corn
   has in every corn year from 1994 to 2007. Another combined operation does have its fertilizer
   row: the 2/11/1997 Apply_Fertilizer_Herbicide rows on Transitional 2-2, 5-7, 7-4 match a Urea
   row that day. The 2013 yields are among the highest in the record, which fits N having been
   applied.

3. Legume/Corn/Tomato tomato in 2004 to 2007 has the starter but no sidedress. This covers plots
   1-1, 6-3, 6-7 (2004, 2006) and 2-4, 4-4, 6-9 (2005, 2007). The only N rows are NPK_new at
   50.44 kg N/ha on 4/20/2004, 5/4/2005, 5/11/2006 and 5/8/2007 (lines 480 to 482, 519 to 521,
   552 to 554, 597 to 599). Every other Legume/Corn/Tomato tomato year has at least 112.16 kg
   N/ha per plot. In the same years Conventional Corn/Tomato tomato got NPK_new plus an Ammonium
   sulfate sidedress of 112.16 (162.6 a season), and Conventional Wheat/Tomato got the same
   sidedress. Tautges et al. 2019 give CONV and CONV+WCC tomato a 112 kg N/ha ammonium sulfate
   sidedress. The samples suggest the sidedress really was skipped. Legume/Corn/Tomato fruit
   Total N is the lowest of the four tomato systems each year, and its 2005 to 2007 fresh yields
   were 53.8 to 62.2 Mg/ha against 73.7 to 89.1 for Conventional Corn/Tomato. Could you confirm
   either way?

4. Tomato seasons with no starter: 1999, and 2013 except Conventional Wheat/Tomato.
   - In 1999 the only N on the tomato plots of Conventional Corn/Tomato 1-4, 5-5, 7-8,
     Conventional Wheat/Tomato 1-5, 4-3, 7-9 and Legume/Corn/Tomato 2-4, 4-4, 6-9 is Ammonium
     sulfate at 112.16 kg N/ha on 6/7/1999 (lines 288 to 296).
   - In 2013 Conventional Corn/Tomato 1-4, 5-5, 7-8, Legume/Corn/Tomato 2-4, 4-4, 6-9 and
     Alfalfa/Corn/Tomato 4-7, 5-1, 7-6 have only UAN 32 at 134.5 on 5/10/2013. Conventional
     Wheat/Tomato 1-5, 4-3, 7-9 also has 'Pre-plant starter 8-24-6' on 4/5/2013 (lines 849 to
     851).
   - 1994 tomato also has a single N application (Ammonium sulfate 135.68 on 5/26/1994).

   The other tomato seasons from 1995 to 2012 have an early application, apart from
   Legume/Corn/Tomato 6-7 in 1998 (item 5) and the 2004 to 2007 case in item 3. Tautges et al.
   2019 give tomato 56 kg N/ha of 8-24-6 starter at planting, so we expected a starter row, or
   confirmation that none was applied. The 1994 and 1999 transplanting rows are missing too
   (item 21). Possibly related, possibly by design: Transitional 2-2, 5-7, 7-4 have only NPK_new
   46.24 on 7/8/1998 for their 1998 corn. Conventional Corn/Tomato 1998 corn has NPK_new on
   5/21/1998 and Urea 179.43 on 6/12/1998.

5. Two 1998 tomato applications miss one plot of their phase.
   - Conventional Wheat/Tomato: the 6/9/1998 Ammonium sulfate (113.11 kg N/ha) is on 2-5 and 6-6
     (lines 259, 260) but not on 5-3. Plot 5-3 grew tomato (`plot_system.csv` 1998-04-22 to
     1998-08-14) and has the 4/20/1998 NPK_new (line 249).
   - Legume/Corn/Tomato: the 4/20/1998 NPK_new (46.24) is on 1-1 and 6-3 (lines 251, 252) but
     not on 6-7, which has the 6/9/1998 sidedress (line 263).

   Grouped by system, date, material and rate, every other application in the file covers three
   plots. We expected both applications on all three plots.

6. Fertilized wheat harvested 1998 to 2002 lacks the fall preplant, and some crops have no N at
   all. These are the N rows labelled Wheat on the plots that were in wheat:
   - Conventional Wheat/Tomato 1-5, 4-3, 7-9: 1998 none; 2002 only Urea 56.2 on 4/21/2002. Plots
     2-5, 5-3, 6-6: 1999 only Urea 56.04 on 3/4/1999; 2001 only Urea 56.2 on 4/28/2001.
   - Irrigated Wheat/Fallow 2-6, 3-4, 8-4: 1998 none; 2002 only Urea 56.2 on 4/21/2002. Plots
     4-2, 4-6, 8-5: 1999 none; 2001 only Urea 56.2 on 4/28/2001.
   - Rainfed Wheat/Fallow 1-9, 5-9, 8-2: 1998 only Urea 28 on 2/28/1998; 2002 only Urea 27.84 on
     4/21/2002. Plots 2-9, 5-8, 7-2: 1999 none.

   The file has no row of any kind from June to December 1997, August to December 1998 or June
   to December 2001. In fall 2000 only Rainfed Wheat/Fallow has a preplant (Can_27 84.13 on
   11/13/2000). The crops were sown: the fall 1997 and fall 2000 seedings are in
   `operations_planting.csv`, and the fall 1998 and fall 2001 seedings are in `plot_system.csv`
   only. `wheat_harvests_all.csv` has their yields. Every other season from 1994 to 2013 in
   these systems has a fall preplant (Ammonium nitrate or Can_27) and a spring Urea, apart from
   items 8 and 9. We expected both here. Item 7 covers the 3/4/1999 urea on these systems'
   fallow plots.

7. Spring 1999 urea is logged on the plots that were fallow. Urea labelled Wheat on 3/4/1999 is
   on Irrigated Wheat/Fallow 2-6, 3-4, 8-4 (56.04 kg N/ha, lines 273 to 275) and Rainfed
   Wheat/Fallow 1-9, 5-9, 8-2 (29.54, lines 276 to 278). `plot_system.csv` has these plots
   harvesting wheat on 1998-07-07 and seeding wheat again on 1999-11-14 (Irrigated) or
   1999-11-13 (Rainfed), so they were fallow on that date. The plots that carried the 1999 wheat
   have no N row for it: 4-2, 4-6, 8-5 and 2-9, 5-8, 7-2, harvested 1999-07-01 with yields at
   serial 36342. Conventional Wheat/Tomato's 3/4/1999 urea is on its 1999 wheat plots, 2-5, 5-3,
   6-6. We expected the 1999 topdress, and a fall 1998 preplant, on 4-2, 4-6, 8-5 and 2-9, 5-8,
   7-2. We can't tell whether these rows have the wrong plots or the wrong year. A wrong year
   would fit the Irrigated plots, whose 1998 wheat has no N. It would not fit the Rainfed plots,
   which already have Urea 28 on 2/28/1998. Checked against `plot_system.csv`, these rows and
   the rows in items 8 and 10 are the only Wheat N rows that fall outside a wheat crop on their
   own plot.

8. Conventional Wheat/Tomato spring 2011 urea is on the plots growing tomato. Lines 750 to 752
   log Urea at 56.2 kg N/ha, crop_fertilized Wheat, on 3/24/2011, on 1-5, 4-3, 7-9. Those plots
   harvested wheat on 7/9/2010 and were transplanted to tomato on 4/21/2011. The plots that
   harvested wheat on 7/9/2011 are 2-5, 5-3, 6-6. They have their 11/2/2010 Can_27 preplant but
   no spring urea. Every other system's 3/24/2011 urea is on its wheat plots. We expected this
   topdress on 2-5, 5-3, 6-6. A plot mislabel is our guess; the files don't show it.

9. Irrigated Wheat/Fallow 2013 wheat has no spring urea. Plots 4-2, 4-6, 8-5 were seeded
   11/12/2012 and harvested 7/1/2013. Their only N row is Can_27 at 111.97 kg N/ha on 10/29/2012
   (lines 831 to 833). The only spring 2013 urea rows are on Conventional Wheat/Tomato 2-5, 5-3,
   6-6 (56.2) and Rainfed Wheat/Fallow 2-9, 5-8, 7-2 (27.84), on 3/20/2013. Every other
   Irrigated Wheat/Fallow season has a spring urea except 1998 and 1999 (items 6 and 7), and the
   paper gives the irrigated system 112 kg/ha urea in March. We expected a spring 2013 urea row
   on 4-2, 4-6, 8-5.

10. Can_27 labelled Wheat on Conventional Corn/Tomato 1-3, 4-5, 8-9 on 11/12/2012. Lines 837 to
    839 log Can_27 at 414.71 kg/ha, 111.97 kg N/ha. These plots grew tomato in 2012 (harvested
    2012-09-05) and corn in 2013 (seeded 3/25/2013), and no wheat was seeded on them after
    11/17/2011. Conventional Wheat/Tomato 2-5, 5-3, 6-6 have the identical row that day (lines
    840 to 842), and those plots were seeded to wheat on that date. Two readings fit the files.
    Either those rows were repeated under the wrong plot ids, or this is a preplant for the 2013
    corn, 133 days before seeding, with the wrong crop label. The files don't show which.

11. The Conventional Wheat/Tomato 2011 wheat preplant is logged twice. Can_27 (414.71 kg/ha,
    111.97 kg N/ha) is on 11/5/2011 (lines 780 to 782, on '5-Jan', 4-3, 7-9) and again on
    11/14/2011 (lines 792 to 794, on 1-5, 4-3, 7-9). Both dates are before the 11/17/2011
    seeding, and the 3/26/2012 urea follows. As logged, that crop got 280.14 kg N/ha, against
    168.17 to 169.8 in the system's other complete seasons. Irrigated Wheat/Fallow and Rainfed
    Wheat/Fallow have this preplant only on 11/5/2011, and Conventional Corn/Tomato and
    Legume/Corn/Tomato only on 11/14/2011. We expected one preplant per plot and can't tell
    which date is right.

12. Transitional crop labels in 1995 to 1997 name the wrong crop. Plots 2-2, 5-7, 7-4 grew corn
    in 1995 (seeded 5/18/1995), tomato in 1996 (transplanted 4/25/1996) and then wheat (seeded
    11/10/1996, harvested 1997-06-17). `operations_planting.csv`, `plot_system.csv`,
    `operations_harvest.csv` and the sample files all agree on that.
    `operations_fertilizers.csv` labels them otherwise:
    - the 1995 rows say Tomato (lines 71 to 73, 86 to 88, 101 to 103, 116 to 118);
    - the spring 1996 rows say Corn (lines 149 to 151, 161 to 163, 179 to 181);
    - the wheat's 10/11/1996 Ammonium nitrate and 2/11/1997 Urea say Tomato (lines 185 to 187,
      203 to 205).

    `operations_pesticides.csv` has the same swap (Tomato in 1995, Corn on 8/5/1996, Tomato on
    2/11/1997). The amounts are not affected, only the crop they are attributed to. Separately,
    the 10/25/2013 Phosphorus fertilizer (0-32-16) rows on Rainfed Wheat/Legume 1-6, 3-8, 7-3
    (lines 885 to 887) say Cover Crop. Those plots were seeded to wheat on 11/10/2013, and every
    other 10/25/2013 row of that product is labelled Wheat. Either the label should be Wheat, or
    the plots should be the cover crop phase 2-8, 3-7, 8-1 (seeded 10/28/2013).

13. Conventional Corn/Tomato corn starter is dated weeks after seeding from 1998 on. This one is
    low priority, and the timing may be real. Each corn season has one N application that is not
    urea: Ammonium sulfate up to 1996, NPK_new from 1997. It falls 1 to 13 days before seeding
    in 1994 to 1997 and 1999, but 14 to 42 days after seeding in 1998 and 2000 to 2007. For
    example, the corn was seeded 3/24/2000 with NPK_new on 5/4/2000, and seeded 4/19/2005 with
    NPK_new on 5/31/2005. The 1998 figure is counted from the 4/19/1998 reseeding; from the
    3/21/1998 seeding it is 61 days. In 2006 the Urea (185.1 kg N/ha, 5/7/2006) comes before the
    NPK_new (5/16/2006). That is the only season in that order, so those two dates may be
    swapped. The paper puts the starter at planting.

14. Phosphorus and potassium are swapped for the two 2013 products. 'Pre-plant starter 8-24-6'
    at 350.27 kg/ha (lines 849 to 851) has phosphorus 21.0162 and potassium 84.0648. 'Phosphorus
    fertilizer (0-32-16)' at 336.26 kg/ha (15 rows, lines 867 to 872, 876 to 881, 885 to 887)
    has phosphorus 53.8016 and potassium 107.6032. By grade, P2O5 should be 84.06 and 107.60 and
    K2O 21.02 and 53.80. Every other product has its values in the right columns; Super Triple
    Phosphate, for example, puts 45% in phosphorus. A separate unit problem: the data dictionary
    gives phosphorus as PO4, potassium as K2O and sulfur as SO4. The values actually follow the
    P2O5 grade and elemental S: Ammonium sulfate rows carry 24.3% S, and as SO4 it would be
    about 73%. The dictionary also lists potassium before phosphorus, while the CSV has
    phosphorus first. No N is affected.

15. Six rows are dated only '1999', with no amounts. Lines 2 to 7 are Irrigated Wheat Control
    2-7, 6-1, 8-7 and Rainfed Wheat Control 1-7, 4-9, 8-3, Phosphorus fertilizer (0-32-16), date
    '1999'. Their total_applied_material_kg/ha, phosphorus and potassium are blank. The other
    880 rows have month/day/year dates as the dictionary specifies, and the 10/25/2013
    application of the same product on the same plots is complete. The metadata says these
    systems got supplemental P and K in 1999 and 2013, so we expected a full date and the
    amounts. No N is involved.

16. Plot id '5-Jan'. Line 780 (Conventional Wheat/Tomato, 11/5/2011, Can_27) has plot '5-Jan'.
    It is the only plot id in the file that is not two digits joined by a hyphen, and
    `plot_system.csv` has no such plot. It reads as '1-5' converted to a date by a spreadsheet:
    the same operation lists 4-3 and 7-9, and the 11/14/2011 repeat (item 11) lists 1-5.

### `operations_compost.csv`

17. Every compost application is listed twice. The 252 rows hold 126 plot and year applications.
    Each plot's block gives its full history twice in a row (for example 1-2 on lines 2 to 15
    and 16 to 29, and 2-2 on lines 30 to 41 and 42 to 53). 123 pairs are identical. Three differ
    only in date, all at 4 tons/acre in 2005:
    - 2-3: line 63 5/20/2005, line 79 4/20/2005
    - 6-4: line 119 5/20/2005, line 135 4/20/2005
    - 6-8: line 179 4/20/2005, line 195 5/20/2005

    Summing the file as published doubles the compost input, and the metadata's 252 entries
    describe the duplicated file. We expected 126 rows and one date per 2005 application. The
    other Organic Corn/Tomato phase has 4/20/2005 in both copies. Plots 2-3, 6-4, 6-8 were
    seeded to corn on 5/24/2005, so both dates come before planting.

18. Several Organic Corn/Tomato and Transitional years have no compost, including corn and
    tomato years. Compost years in the file:
    - Organic Corn/Tomato 1-2, 6-5, 8-8: 1994 to 1997, 2000 to 2007, 2009, 2011
    - Organic Corn/Tomato 2-3, 6-4, 6-8: 1994 to 1997, 2000 to 2007, 2009, 2010, 2012, 2013
    - Transitional 2-2, 5-7, 7-4: 2000 to 2007, 2009, 2010, 2012, 2013

    The gaps include cash crops in `plot_system.csv`:
    - 1998: corn on 1-2, 6-5, 8-8; tomato on 2-3, 6-4, 6-8
    - 1999: tomato on 1-2, 6-5, 8-8 and on Transitional; corn on 2-3, 6-4, 6-8
    - 2008: tomato on 2-3, 6-4, 6-8
    - 2013: tomato on 1-2, 6-5, 8-8, transplanted 4/17/2013

    No plot has a compost row for 1998, 1999 or 2008, and no other file records compost or
    manure. Counting phase years from 1994 to 2013 (Transitional from 2000), compost appears in
    none of the 5 wheat phase years and in 42 of the other 49. We read the amounts as short
    tons/acre wet weight and multiplied by each year's Total C (the mean where a year has no
    analysis). On that basis the recorded applications give 29.47 and 31.34 Mg C/ha over 1994 to
    2012 for the two Organic phases. The paper gives 40.4 Mg C/ha over 19 years. At minimum we
    expected compost before every organic corn and tomato crop. If application was annual, as
    the paper's totals imply, we also expected it in the wheat and sudangrass years. The
    Transitional 1999 gap may be by design, since that system still got Ammonium sulfate on
    6/7/1999.

19. The compost rate unit. material_units is 'tons/acre' in all 252 rows. 216 rows are at 4; the
    others are 3, 4.5, 7, 8, 8.8 and 12, all in 1994 to 1997. The package doesn't say whether
    these are short tons or metric tonnes: 4 tons/acre is 8.97 t/ha in short tons and 9.88 t/ha
    in metric. The Methods of Tautges et al. 2019 twice give an average rate of 4 t/ha, while
    the Discussion has annual inputs of 9 t/ha. 4 tons/acre fits the 9 t/ha. It also fits the
    40.4 Mg C/ha, at about 2.20 Mg C/ha per Organic Corn/Tomato application, if compost went on
    every year. 4 t/ha fits the paper's 700 to 800 kg C/ha a year instead. Which rate is right,
    and which ton is meant?

### `operations_planting.csv`

20. No fall 1998 or fall 2001 seedings, and no fall 2004 cover crop seedings. The file has 18
    rows in 1998 (none after 4/22/1998) and 24 in 2001 (none after 5/18/2001), against 45 to 72
    in other full years. It has no Cover Crop row dated 2004; other years have 9 to 21.
    `plot_system.csv` lists these plantings, and the sample files confirm them. Three of the
    fall 1998 `plot_system.csv` cells have the wrong year (item 41), and 2-4 and 6-9 have no
    fall 2004 entry (item 40).
    - Fall 1998 wheat: Conventional Wheat/Tomato 2-5, 5-3, 6-6; Irrigated Wheat Control 3-5,
      5-6, 7-7; Irrigated Wheat/Fallow 4-2, 4-6, 8-5; Irrigated Wheat/Legume 4-8, 5-2, 7-5;
      Rainfed Wheat Control 1-8, 3-9, 6-2; Rainfed Wheat/Fallow 2-9, 5-8, 7-2; Rainfed
      Wheat/Legume 2-8, 3-7, 8-1.
    - Fall 1998 cover crop: Irrigated Wheat/Legume 4-7, 5-1, 7-6; Rainfed Wheat/Legume 1-6, 3-8,
      7-3; Legume/Corn/Tomato 1-1, 6-3, 6-7; Organic Corn/Tomato 1-2, 6-5, 8-8 and 2-3, 6-4,
      6-8; Transitional 2-2, 5-7, 7-4.
    - Fall 2001 wheat ('11/10/2001 - 11/23/2001'): Conventional Wheat/Tomato 1-5, 4-3, 7-9;
      Irrigated Wheat Control 2-7, 6-1, 8-7; Irrigated Wheat/Fallow 2-6, 3-4, 8-4; Irrigated
      Wheat/Legume 4-7, 5-1, 7-6; Rainfed Wheat Control 1-7, 4-9, 8-3; Rainfed Wheat/Fallow 1-9,
      5-9, 8-2; Rainfed Wheat/Legume 1-6, 3-8, 7-3.
    - Fall 2001 cover crop: Irrigated Wheat/Legume 4-8, 5-2, 7-5; Legume/Corn/Tomato 2-4, 4-4,
      6-9; Organic Corn/Tomato 1-2, 6-5, 8-8 and 2-3, 6-4, 6-8; Rainfed Wheat/Legume 2-8, 3-7,
      8-1; Transitional 2-2, 5-7, 7-4.
    - Fall 2004 cover crop ('11/17/2004 - 11/20/2004'; the wheat that fall is logged): Irrigated
      Wheat/Legume 4-7, 5-1, 7-6; Legume/Corn/Tomato 1-1, 6-3, 6-7 and 2-4, 4-4, 6-9; Organic
      Corn/Tomato 1-2, 6-5, 8-8 and 2-3, 6-4, 6-8; Rainfed Wheat/Legume 1-6, 3-8, 7-3;
      Transitional 2-2, 5-7, 7-4.

    That is 42 wheat and 57 cover crop plot plantings. The crops were harvested or incorporated.
    `wheat_harvests_all.csv` has yields at serials 36342 (7/1/1999) and 37445, 37446 (7/8/2002,
    7/9/2002). `wcc_harvests_all.csv` has samples on 3/30/1999, 4/10/2002 and 3/30/2005 for
    every cover crop plot listed. `plot-system.csv` notes say these dates came from sources
    outside the logs, such as a 'Farmops_Denison 1993-2000' file and an email dated 3/1/2017.
    The metadata describes this file as covering 1993 to 2013 and says every tractor operation
    was logged and checked.

21. Tomato transplanting is missing for 1994 and 1999, and some 1998 and 2002 corn seeding is
    missing.
    - (a) 1994 has no Tomato row. `plot_system.csv` lists 12 plantings: Conventional Corn/Tomato
      1-3, 4-5, 8-9, Legume/Corn/Tomato 1-1, 6-3, 6-7 and Organic Corn/Tomato 2-3, 6-4, 6-8 on
      1994-05-04, and Conventional Wheat/Tomato 2-5, 5-3, 6-6 on 1994-03-23.
    - (b) In 1998 corn is logged only for Conventional Corn/Tomato 1-4, 5-5, 7-8 (3/21/1998 and
      4/19/1998). Missing are Legume/Corn/Tomato 2-4, 4-4, 6-9, Organic Corn/Tomato 1-2, 6-5,
      8-8 and Transitional 2-2, 5-7, 7-4, all 1998-04-19 in `plot_system.csv`.
    - (c) 1999 has no Tomato row. The missing plots are Conventional Corn/Tomato 1-4, 5-5, 7-8;
      Conventional Wheat/Tomato 1-5, 4-3, 7-9; Legume/Corn/Tomato 2-4, 4-4, 6-9; Organic
      Corn/Tomato 1-2, 6-5, 8-8; and Transitional 2-2, 5-7, 7-4. `plot_system.csv` gives
      1999-05-01, an assigned date (item 42).
    - (d) In 2002 corn is logged for Legume/Corn/Tomato, Organic Corn/Tomato and Transitional
      (6/3/2002) but not for Conventional Corn/Tomato 1-4, 5-5, 7-8 (`plot_system.csv`
      2002-04-03). That corn's harvest is logged on 10/18/2002.

    All of these crops were harvested: tomato samples exist on 8/26/1994, 8/27/1994, 8/31/1999
    and 9/1/1999, and corn samples on 11/3/1998 and 10/19/2002. With item 20, 48 plantings of
    1998 on the ten original systems and Transitional are missing. The count is 49 with the corn
    variety trial on Native Grass 3-6, which is flagged core and was planted 1998-06-05.

22. Transitional 2006 is logged as tomato, but the plots grew corn. Lines 1054, 1082, 1109 have
    Tomato transplanted on 5/25/2006 ('Heinz_9780', 8712 plants/acre) on 2-2, 5-7, 7-4.
    `operations_harvest.csv` lines 909 to 911 have Tomato harvested 9/13/2006. Three other files
    say corn:
    - `plot_system.csv` has Corn planted 2006-05-25 and harvested 2006-09-13, with the anomaly
      'Corn planted instead of tomato.'
    - `corn_harvests_all.csv` has Transitional corn samples on 10/24/2006 (lines 257 to 262).
    - `tomato_harvests_all.csv` has no Transitional row in 2006.

    The logged dates are the 2006 Legume/Corn/Tomato and Organic Corn/Tomato tomato dates. Those
    systems' corn was seeded 6/1/2006, and every other 2006 corn harvest and sample is dated
    10/24/2006. The Transitional 2006 herbicide rows also match the conventional tomato rows
    (item 38). We expected corn rows with the corn's own dates. The crop is clear, but the files
    can't tell us whether the corn was seeded 5/25/2006, or whether it was harvested 9/13/2006
    or 10/24/2006.

23. Transitional cover crop seedings of fall 2005 and fall 2011 are missing. `plot_system.csv`
    has cover crop planted on 2-2, 5-7, 7-4 on 2005-10-28 and 2011-11-15. `wcc_harvests_all.csv`
    has their incorporation samples on 4/25/2006 and 4/4/2012. This file has no Transitional
    cover crop row in either fall, while the other cover crop systems are logged 10/28/2005 and
    11/15/2011. `plot-system.csv` says the 2005 Transitional date was defaulted from those other
    plots.

24. Organic Corn/Tomato tomato in 2003 and 2005 is filed under 6-8 instead of 8-8. Line 760
    (5/8/2003, 'Hailey 3155') and line 764 (5/13/2005, 'Heinz_9780') put tomato transplanting on
    6-8. Plot 6-8 has its own corn seeding in those years (line 761, 5/10/2003; line 765,
    5/24/2005). Plot 8-8 has no tomato row in either year. `plot_system.csv`,
    `operations_harvest.csv` and `tomato_harvests_all.csv` all have 8-8 in tomato and 6-8 in
    corn. We expected these two rows under 8-8, which with 1-2 and 6-5 makes up the tomato
    phase.

25. A cover crop seeding on Conventional Wheat/Tomato 7-9 is filed under Irrigated Wheat/Legume.
    Line 419 reads: 7-9, Irrigated Wheat/Legume, 11/2/2002, Cover Crop, 'Vetch and peas
    (120lbs)'. The same seeding is logged that day on Irrigated Wheat/Legume 4-7, 5-1, 7-6, so
    that phase has four rows. `plot_system.csv` has 7-9 only in Conventional Wheat/Tomato, with
    no fall 2002 crop and tomato in 2003. In the planting, harvest, compost and pesticide logs,
    this is the only row whose plot and system pair never occurs in `plot_system.csv`. The
    `plot-system.csv` note for 7-9 in 2002 already questions it. The files can't say which plot,
    if any, was meant.

26. Irrigated Wheat/Legume was seeded in December 2007, though it was fallow from 2007. Lines
    355, 380, 418 have Wheat ('Cal Rojo') on 4-7, 5-1, 7-6 on 12/15/2007. Lines 368, 393, 406
    have Cover Crop ('Bell bean, vetch and oats 125 lbs/acre') on 4-8, 5-2, 7-5 on 12/12/2007.
    In `plot_system.csv`, harvest year 2007 has crop_B_planted 'Fallow' with the anomaly 'IWL
    was fallow after wheat or CC harvested in 2007'. The 2008 to 2011 rows say IWL was fallow
    from 2007 to 2012, and the metadata says IWL was terminated in 2007 and fallowed through 2012.
    No harvest, yield or cover crop sample follows either seeding. The next rows on these
    plots are Alfalfa/Corn/Tomato operations from 10/4/2012. We expected either no seedings, or
    a harvest or incorporation record.

27. One corn seeding row gives 'plants/acre'. Line 650 reads: 2-3, Organic Corn/Tomato,
    5/10/2003, ST7570, 32500 'plants/acre'. The other 152 corn rows say 'seeds/acre', including
    6-4 and 6-8 in the same operation.

### `operations_harvest.csv`

28. The file has no rows at all for 1998. Every other year from 1994 to 2013 has 30 to 93 rows
    (70 in 1997, 45 in 1999), and the harvest year column has no 1998 either. The metadata
    describes the file as covering 1994 to 2013 with 949 entries. `plot_system.csv` records 45
    cash crop harvests in 1998 on the ten original systems and Transitional:
    - Wheat on 1998-07-07 on all 21 wheat plots: Conventional Wheat/Tomato 1-5, 4-3, 7-9;
      Irrigated Wheat Control 2-7, 6-1, 8-7; Irrigated Wheat/Fallow 2-6, 3-4, 8-4; Irrigated
      Wheat/Legume 4-7, 5-1, 7-6; Rainfed Wheat Control 1-7, 4-9, 8-3; Rainfed Wheat/Fallow 1-9,
      5-9, 8-2; Rainfed Wheat/Legume 1-6, 3-8, 7-3.
    - Tomato on 1998-08-14 on Conventional Corn/Tomato 1-3, 4-5, 8-9 and Conventional
      Wheat/Tomato 2-5, 5-3, 6-6, and on 1998-08-17 on Legume/Corn/Tomato 1-1, 6-3, 6-7 and
      Organic Corn/Tomato 2-3, 6-4, 6-8.
    - Corn on 1998-11-03 on Conventional Corn/Tomato 1-4, 5-5, 7-8; Legume/Corn/Tomato 2-4, 4-4,
      6-9; Organic Corn/Tomato 1-2, 6-5, 8-8; Transitional 2-2, 5-7, 7-4.

    Native Grass 3-6, flagged core, adds a corn variety trial harvested 1998-11-05, making 46
    harvests on plots flagged core. The sample files confirm these harvests:
    `wheat_harvests_all.csv` has 21 rows at serial 35983 (7/7/1998), `tomato_harvests_all.csv`
    has 24 rows on 8/18/1998, and `corn_harvests_all.csv` has 19 rows on 11/3/1998.
    `plot-system.csv` marks the 1998 harvests as retrieved from paper data.

29. More harvests in `plot_system.csv` have no row here, including every sudangrass crop.
    - 1994 wheat ('6/15/1994 - 6/17/1994'): Conventional Wheat/Tomato 1-5, 4-3, 7-9; Irrigated
      Wheat Control 2-7, 6-1, 8-7; Irrigated Wheat/Fallow 2-6, 3-4, 8-4.
    - 1995 tomato (1995-08-24): Conventional Wheat/Tomato 1-5, 4-3, 7-9; Organic Corn/Tomato
      1-2, 6-5, 8-8.
    - 1997 tomato: Conventional Corn/Tomato 5-5 (1997-08-13). Its phase mates 1-4 and 7-8 are
      logged on 8/15/1997 and 8/22/1997.
    - 2000 wheat (2000-06-26): Irrigated Wheat/Legume 4-7, 5-1, 7-6. Six other wheat systems are
      logged that day.
    - 2001 corn (2001-10-19): Conventional Corn/Tomato 1-3, 4-5, 8-9; Legume/Corn/Tomato 1-1,
      6-3, 6-7; Organic Corn/Tomato 2-3, 6-4, 6-8. The file has no Corn row in 2001.
    - 2011 wheat (2011-07-09): Organic Corn/Tomato 2-3, 6-4, 6-8; Transitional 2-2, 5-7, 7-4.
    - 2012 wheat: Rainfed Wheat/Fallow 1-9, 5-9, 8-2 (2012-07-09).
    - Sudangrass: the file has no Sudangrass row at all. `plot_system.csv` has it harvested
      2008-08-05 on Organic Corn/Tomato 1-2, 6-5, 8-8. It has it harvested 2009-10-28 on
      Conventional Corn/Tomato 1-3, 4-5, 8-9, Legume/Corn/Tomato 1-1, 6-3, 6-7, Organic
      Corn/Tomato 2-3, 6-4, 6-8 and Transitional 2-2, 5-7, 7-4. The metadata says the sudangrass
      was sampled and plowed under with no hay removed, so we expected a record of the plow
      down.

    Most of these have sample rows; for example, `corn_harvests_all.csv` has all nine 2001 corn
    plots on 10/19/2001. `plot-system.csv` marks the 2001 corn, the 2000 Irrigated Wheat/Legume
    wheat and the 1997 tomato on 5-5 as retrieved from paper data.

30. The 2012 wheat in Legume/Corn/Tomato and Organic Corn/Tomato. Both phases were seeded to
    wheat on 11/17/2011: Legume/Corn/Tomato 2-4, 4-4, 6-9 and Organic Corn/Tomato 1-2, 6-5, 8-8.
    The metadata says the 2012 wheat in these systems was not harvested for grain and all the
    biomass was cut for hay.
    - For Legume/Corn/Tomato, lines 585 to 587 log 'Harvest Wheat' with a Case 1680 Harvester on
      6/25/2012, and `plot_system.csv` gives Wheat harvested 2012-06-25. The anomaly on those
      same `plot_system.csv` rows says the LMT plots were NOT harvested for wheat in 2012.
    - For Organic Corn/Tomato, `plot_system.csv` has NA and there is no harvest row.

    Neither file records the hay removal or its date. `plot-system.csv` says the Organic wheat
    was swathed and baled before 7/9/2012, with no dates recorded. We expected one account per
    system: a hay removal row with its date, and `plot_system.csv` fields that agree with the
    anomaly.

31. The 1999 wheat harvest is logged on Rainfed Wheat/Legume 7-3, a cover crop plot that year,
    and none is logged on Rainfed Wheat/Fallow 7-2. Line 896 reads: 7-3, Rainfed Wheat/Legume,
    7/1/1999, Wheat. That phase's 1999 wheat plots, 2-8, 3-7 and 8-1, already have rows that day
    (lines 893 to 895). `plot_system.csv` and `wcc_harvests_all.csv` put 7-3 in cover crop
    (sampled 3/30/1999), with no 1999 wheat yield. Rainfed Wheat/Fallow 7-2 has no row, though
    its phase mates 2-9 and 5-8 are logged 7/1/1999. `plot_system.csv` has 7-2 harvested
    1999-07-01, and `wheat_harvests_all.csv` has its yield (line 377, serial 36342). We expected
    a 7/1/1999 row for 7-2 and none for 7-3. That line 896 is the 7-2 record under the wrong
    plot and system is only our guess.

32. Rainfed Wheat Control 4-9 in 1996. Line 757 logs a wheat harvest on 6/20/1996 on 4-9, as on
    1-7 and 8-3. `plot_system.csv` line 233 has crop_B_harvested NA for 4-9, while 1-7 and 8-3
    have Wheat on 1996-06-20. The 4-9 anomaly also lists the other phase's plots ('2-5, 2-8,
    2-9, 3-7, 4-2, ...'), the same text as its 1995 and 1997 rows, where 1-7 and 8-3 list '1-5,
    1-6, 1-9, 2-6, ...'. We expected one harvest status for all three plots in both files, and
    the 1996 plot list in the 4-9 anomaly.

33. Half plot id '6-9E'. Line 535 reads: 6-9E, Legume/Corn/Tomato, 8/19/2003, Tomato, 'Machine
    Harvest'. It is the only one of the 949 rows with an E or W suffix (no other operation file
    has one), and there is no row for 6-9 in 2003. `plot_system.csv` gives 6-9 a tomato harvest
    on 2003-08-14 rather than the 8/19/2003 of 2-4 and 4-4. We expected '6-9' and one harvest
    date for the phase. The metadata says the 2003 to 2007 corn and tomato data come from the
    standard tillage half of each plot, which might explain the suffix (a guess). However, the
    other 2003 samples are on 2-4E and 4-4W.

### Across the operation logs

34. There are no tillage, mowing, cultivation, bed forming or crop termination records. Apart
    from planting passes, the only soil working logged is in `operations_pesticides.csv`, by
    method_application: Incorporate 189 rows, Mulch_Beds 153, Perfecta 6,
    Apply_Fertilizer_Herbicide 3. No crop that ended without a harvest has a termination row:
    - the 2008 and 2009 sudangrass (item 29);
    - the 2012 Organic Corn/Tomato wheat, which has no end date in any file (item 30);
    - the cover crops, whose ends are known only from sample dates.

    Tautges et al. 2019 describe these operations:
    - stalk chopping and disking;
    - bed listing and rolling;
    - cover crop mowing and two to three diskings;
    - straw incorporation by two shallow diskings;
    - four fallow diskings;
    - in season cultivations.

    The metadata says every tractor operation was logged with plot, date, tractor, equipment and
    passes. `plot-system.csv` cites farm logs that hold these operations ('farmops_old.xlsx',
    'Farmops.xlsx', 'RR Field Operations 2012 original.xls'). One example note: 'Preplant
    cultivate occurred 4/25/99, mulched 4/26/99, irrigated 5/1/99'. The metadata lists no
    tillage file, so this may be by design, and we list it as data we expected. Those farm logs
    would help us a lot if they can be shared.

35. There are no 2014 planting, harvest, fertilizer or compost rows. Those logs end on
    11/10/2013, 10/20/2013, 10/25/2013 and 2/24/2013. `operations_pesticides.csv` runs to
    6/18/2014. `plot_system.csv` has 63 plantings and 48 crop harvests in 2014, not counting
    Fallow entries. The sample files also have 2014 rows: seven alfalfa cuttings in
    `alfalfa_harvests_all.csv`, plus corn, tomato and wcc samples. The end dates match the
    metadata's stated coverage, so this is data we expected rather than an error. It does leave
    2014 N and compost unknown.

36. The Native Grass plots and plot 5-4 are in no operation file. `plot_system.csv` has Native
    Grass planted 2012-11-13 on 3-6, 7-1 and 8-6. It also lists earlier trial crops on those
    plots: wheat and cover crops in 1994 to 1996, and corn variety trials in 1994, 1997, 1998,
    2002 and 2003. No operation file has a row for these plots in any year. Their only other
    rows are soil rows from 10/8/2012 (item 54) and one wheat sample on 8-6 (item 48). The same
    holds for 5-4: system 'Conventional Corn/Tomato - Unassigned', old_system_name 'Duplicate of
    plot 5-5', Century_Experiment_Core N. `plot_system.csv` gives 5-4 plantings from 1993 to
    2007 and in 2009, and harvests up to 2010-07-08. No package file of any kind has a 5-4 row.
    We expected rows for the 2012 seeding, or a note that these plots are outside the logs.

37. The 1993 sudangrass uniformity crop is not in the operation logs. This is low priority and
    possibly by design. `plot_system.csv` lists Sudangrass planted '5/12/1993 - 5/14/1993' on
    all 67 plots and harvested 1993-08-02 or 1993-08-03. `sudangrass_harvests_all.csv` has 63
    samples on 8/3/1993. However, the 1993 rows of `operations_planting.csv` begin on 11/9/1993,
    and `operations_harvest.csv` begins on 6/15/1994.

### `operations_pesticides.csv`

38. Synthetic products were applied on the organic and transitional plots after conversion.
    'Bifen 2 AG Gold' (bifenthrin) went on at 12 ounces/acre on 5/14/2014 on Organic Corn/Tomato
    2-3, 6-4, 6-8 and Transitional 2-2, 5-7, 7-4 (lines 221 to 226). Transitional 2-2, 5-7, 7-4
    also have Triap (Mulch_Beds 5/11/2006 and Incorporate 6/10/2006, 0.75 pints/acre) and Dual
    (6/10/2006, 1.5 quarts/acre), with crop_applied Corn (lines 491 to 496, 1520 to 1522). These
    match the conventional tomato rows on those days in product and rate. The metadata says the
    organic systems received only OMRI approved products and that Transitional was fully organic
    by 2000. We suspect the 2006 rows are copies of conventional rows, like the 2006
    Transitional planting and harvest rows (item 22).

39. One verbatim duplicate. Lines 251 and 257 are identical: 4-7, Alfalfa/Corn/Tomato, 4/5/2013,
    Tomato, Mulch_Beds, Triap, 0.75 pints/acre. Plots 5-1 and 7-6 have one such row each that
    day (lines 253, 255). This is the only verbatim duplicate in the file. Low priority.

### `plot_system.csv`

40. Legume/Corn/Tomato 2-4 and 6-9 have no fall 2004 cover crop. In harvest year 2004, lines 750
    (2-4) and 787 (6-9) have NA for crop_B_planned, crop_B_planted and crop_B_date_planted.
    Their phase mate 4-4 (line 764) and the other phase (1-1, 6-3, 6-7) have Cover Crop
    '11/17/2004 - 11/20/2004'. All three of 2-4, 4-4 and 6-9 have Cover Crop harvested
    2005-03-30, and `wcc_harvests_all.csv` has 3/30/2005 samples on 2-4E, 4-4W and 6-9E. We
    expected '11/17/2004 - 11/20/2004' on 2-4 and 6-9.

41. Wrong year and odd date cells.
    - (a) In harvest year 1998, crop_B_date_planted is 1996-11-11 for Rainfed Wheat/Legume 3-7
      (line 357) and 8-1 (line 395), and 2000-11-27 for Irrigated Wheat/Fallow 8-5 (line 399).
      Their phase mates have '11/2/1998 - 11/6/1998'. 2000-11-27 is the planting log date of the
      fall 2000 seeding on 8-5, and `plot_system.csv` itself gives that seeding as 2000-11-20
      (line 533). These are the only date cells whose year differs from harvest_year.
    - (b) Conventional Wheat/Tomato 1-5, harvest year 1995 (line 140), has crop_A_date_planted
      '0' for a tomato crop harvested 1995-08-24. The planting log has 4/22/1995
      (`operations_planting.csv` line 120), the same date this file gives for 4-3 and 7-9.
    - (c) Native Grass 7-1, harvest year 2003 (line 721), has an empty crop_A_date_harvested for
      a corn variety trial whose anomaly says no harvest date was found. Elsewhere a missing
      date is NA.
    - (d) The four date columns hold 5,896 cells: 2,572 ISO dates, 193 month/day/year ranges,
      six alfalfa ranges with a count, the '0', the empty cell and 3,123 NA. The logs use
      month/day/year. Part (d) is low priority.

42. Some tomato planting dates are assigned, or mix conventions, with no flag.
    - (a) All 15 core 1999 tomato plots, and 5-4, have crop_A_date_planted 1999-05-01, with
      nothing in the anomalies. The `plot-system.csv` note on these rows says the date was
      assigned ('Going to assign a plant date of 5/1/99 unless find evidence otherwise'). The
      same note says the beds were incorporated on 5/20/99, after the assigned date. It also
      gives a harvest date of 8/3/1999, while `operations_harvest.csv` has the 1999 tomato
      harvests on 9/1/1999, 9/2/1999 and 9/3/1999.
    - (b) In 1994, Conventional Corn/Tomato, Legume/Corn/Tomato and Organic Corn/Tomato use
      1994-05-04, but Conventional Wheat/Tomato 2-5, 5-3, 6-6 use 1994-03-23. The
      `plot-system.csv` notes on the nine 1994-05-04 plots give 3/23/94 as the planting date and
      5/4/94 as the transplant date. So the Conventional Wheat/Tomato date reads as a greenhouse
      seeding date. That is our reading; the paper says the tomatoes were started in a
      greenhouse.
    - (c) Two more placeholders are flagged only in `plot-system.csv`: the Transitional 2005
      cover crop date (item 23), and the Native Grass 8-6 1995 wheat harvest (1995-07-06, set
      from the dates of other plots).

    We expected recorded transplant dates, one convention for 1994, or a flag in
    `plot_system.csv` wherever a date is assumed.

43. Small date differences for the same operation. We found 34 cases where a single
    `plot_system.csv` date differs by 1 to 7 days from the log for the same plot and crop. They
    include:
    - fall 1993 wheat on Rainfed Wheat Control 1-7, Rainfed Wheat/Fallow 1-9 and Rainfed
      Wheat/Legume 1-6, 3-8: 1993-11-18, while their phase mates and the log have 11/19/1993;
    - Organic Corn/Tomato 6-4, 6-5, 6-8, 8-8 cover crop: 1993-11-03 (log 11/9/1993);
    - Legume/Corn/Tomato 4-4: 1993-11-08 (log 11/9/1993);
    - Irrigated Wheat/Fallow 8-5: 2000-11-20 (log 11/27/2000);
    - the 1995 Rainfed Wheat Control, Rainfed Wheat/Fallow and Rainfed Wheat/Legume wheat
      harvests: 1995-07-06 (log 7/5/1995 and 7/7/1995);
    - the 1996 Conventional Wheat/Tomato, Irrigated Wheat Control, Irrigated Wheat/Fallow and
      Irrigated Wheat/Legume wheat harvests: 1996-06-20 (log 6/21/1996);
    - Legume/Corn/Tomato 1-1 tomato: 2000-08-21 (log 8/22/2000);
    - Organic Corn/Tomato 6-8 tomato: 2004-08-16 (log 8/18/2004 and 8/19/2004);
    - 6-9 in 2003 (item 33).

    Low priority; we can send the full list.

44. The 2014 alfalfa cutting count. Lines 1438, 1441, 1462 (Alfalfa/Corn/Tomato 4-8, 5-2, 7-5)
    give '4/17/2014 - 10/8/2014 (x6)'. `alfalfa_harvests_all.csv` has seven 2014 cuttings with
    six rows each: 4/17/2014, 5/16/2014, 6/12/2014, 7/10/2014, 8/9/2014, 9/11/2014 and
    10/8/2014. For 2013 both files have six. We expected '(x7)'. Low priority.

### Crop harvest and analysis files

45. `wcc_harvests_all.csv` dates the 2004 incorporation after the following crops were planted.
    All 30 rows in 2004 are dated 5/17/2004, across Irrigated Wheat/Legume, Legume/Corn/Tomato,
    Organic Corn/Tomato, Rainfed Wheat/Legume and Transitional. The 60 `wcc_analyses_all.csv`
    rows and the 21 `plot_system.csv` cover crop harvest dates (2004-05-17) agree. But the cash
    crops went in earlier:
    - corn was seeded on 5/2/2004 on Legume/Corn/Tomato 2-4, 4-4, 6-9, Organic Corn/Tomato 1-2,
      6-5, 8-8 and Transitional 2-2, 5-7, 7-4;
    - tomato was transplanted on 5/5/2004 on Legume/Corn/Tomato 1-1, 6-3, 6-7 and Organic
      Corn/Tomato 2-3, 6-4, 6-8.

    On those 15 plots the recorded incorporation comes 12 to 15 days after planting, and after
    the 3/29/2004 and 3/30/2004 compost. In every other year the dates fall between 2/20 and
    4/29. 2004 is the only year in which a cash crop on these systems goes in before the plot's
    wcc date. The dictionary defines this date as the incorporation date, and the paper says the
    cover crops were incorporated in March. We expected a March or April date.

46. Some cover crops have no biomass row.
    - (a) Transitional 2-2, 5-7, 7-4, seeded 11/4/1999. Neither `wcc_harvests_all.csv` nor
      `wcc_analyses_all.csv` has a Transitional row in 2000, and `plot_system.csv` has NA. The
      anomaly says there is no evidence the crop was harvested and the plots appear to have been
      cultivated 3/1/2000 and/or mowed 4/5/2000.
    - (b) Legume/Corn/Tomato 2-4, 4-4, 6-9, seeded 10/28/2005 and harvested 2006-04-25 per
      `plot_system.csv`. `wcc_analyses_all.csv` has 4/25/2006 Total N and Total C on 2-4E, 4-4W
      and 6-9E, but `wcc_harvests_all.csv` has no biomass row for them. The other phase and the
      other systems have 4/25/2006 rows.
    - (c) Rainfed Wheat/Legume 2-8, 3-7, 8-1, seeded 10/28/2013 and harvested 2014-03-13 per
      `plot_system.csv`. `wcc_harvests_all.csv` has no 2014 row for them, though
      `plot-system.csv` says the harvest data were retrieved from paper. Legume/Corn/Tomato,
      Organic Corn/Tomato and Transitional have 3/13/2014 rows.

    The metadata describes `wcc_harvests_all.csv` as the complete WCC harvest record for 1994 to 2014.
    We expected a biomass row for each incorporation, or a note that a crop was not
    sampled.

47. `wheat_harvests_all.csv` dates and the missing 2012 rows. All 538 dates are spreadsheet
    serial numbers, from 34501 (6/16/1994) to 41456 (7/1/2013). The dictionary says
    month/day/year, and no other sample file uses serials. The file has no 2012 row: the serials
    jump from 40721 (6/27/2011) to 41456. Yet `operations_harvest.csv` logs 2012 wheat harvests
    on 6/25/2012 for Conventional Corn/Tomato, Conventional Wheat/Tomato, Irrigated Wheat
    Control, Irrigated Wheat/Fallow, Legume/Corn/Tomato, Rainfed Wheat Control and Rainfed
    Wheat/Legume. The 2012 anomalies say only that the straw was not harvested. The metadata
    describes the file as the complete wheat record for 1994 to 2013. We expected month/day/year
    dates and 2012 grain yields for the systems that were harvested.

48. Some sample rows have a system name that doesn't match `plot_system.csv`.
    - `wheat_harvests_all.csv` line 95: 8-3 labelled 'Irrigated Wheat/Fallow' at serial 38896
      (6/28/2006). Plot 8-3 is Rainfed Wheat Control and has its own row that day (line 124),
      and Irrigated Wheat/Fallow 8-4 has no 2006 row.
    - `wheat_harvests_all.csv` line 448: 8-6 labelled 'Irrigated Wheat/Fallow' at serial 34885
      (7/5/1995). Plot 8-6 is Native Grass. Irrigated Wheat/Fallow 8-5 is on the 1995 hand
      harvest list but has no 1995 row.
    - For lines 95 and 448 we'd guess 8-4 and 8-5 were meant.
    - `tomato_harvests_all.csv` lines 249 to 254: 4-7, 5-1, 7-6 on 8/20/2013 labelled 'Irrigated
      Wheat/Legume'. These plots were Alfalfa/Corn/Tomato in 2013.
    - `corn_analyses_all.csv` lines 21 (10/13/1995) and 33 (10/18/1995): 8-8 labelled
      'Conventional Corn/Tomato'; it is Organic Corn/Tomato.
    - `corn_analyses_all.csv` line 571: 7-7 labelled 'Transitional' on 10/13/1995; it is
      Irrigated Wheat Control.
    - `tomato_analyses_all.csv` line 677: 5-5 labelled 'Conventional Wheat/Tomato' on 8/31/2002;
      it is Conventional Corn/Tomato.
    - `tomato_analyses_all.csv` line 1157: 4-5 labelled 'Legume/Corn/Tomato' on 8/24/2005; it is
      Conventional Corn/Tomato.
    - `tomato_analyses_all.csv` line 1627: 6-9 labelled 'Organic Corn/Tomato' on 10/4/2007; it
      is Legume/Corn/Tomato.
    - `wcc_analyses_all.csv` line 450: 6-7 labelled 'Organic Corn/Tomato' on 3/29/2001; it is
      Legume/Corn/Tomato.

    No other row in the harvest or analysis files disagrees.

49. Duplicated sample rows.
    - `tomato_harvests_all.csv`: each of the 30 plot sides harvested on 9/4/2012 appears twice
      verbatim. The rows are Conventional Corn/Tomato lines 95 to 106, Conventional Wheat/Tomato
      227 to 238, Legume/Corn/Tomato 342 to 353, Organic Corn/Tomato 459 to 470 and Transitional
      519 to 530.
    - `wheat_harvests_all.csv`: the same plot and date appear two or three times with no E or W
      suffix. These are 6-2 at 39260 (lines 48, 51), 2-7 at 39636 (52, 53), 8-2 at 38896 (119,
      122), 3-8 at 37445 (303, 304), 3-8 at 40367 (331, 332), 5-2 at 36342 (392, 393), 5-1 at
      36703 (509, 511, 513; line 511 says 'Potentially average value?') and 2-7 at 36703 (510,
      512).

    The machine harvest values within each set agree to within 0.2 percent. The 3-8 hand harvest
    values differ, so those pairs may be E and W rows missing the suffix (a guess). A ninth
    repeat, 8-3 at 38896, carries two system names (item 48). We expected one row per plot side
    and date.

50. Some sample dates are far from the logged harvest date. The dictionary says the date in the
    corn, tomato and wheat files is the mechanical harvest date. The larger gaps:
    - Conventional Wheat/Tomato tomato 2005 (1-5, 4-3, 7-9): sampled 8/24/2005. The log and
      `plot_system.csv` say 7/26/2005, which is only 72 days after the 5/15/2005 transplanting.
    - 2011 wheat in every system: serial 40721 (6/27/2011) against 7/9/2011 in the log.
    - 2002 tomato in Conventional Corn/Tomato, Conventional Wheat/Tomato, Legume/Corn/Tomato and
      Organic Corn/Tomato: 8/31/2002 against 8/19/2002 to 8/22/2002.
    - 2006 tomato: 9/27/2006 (Legume/Corn/Tomato) and 9/28/2006 (Organic Corn/Tomato) against
      9/13/2006.
    - 2004 tomato: 8/7/2004 against 8/17/2004 to 8/19/2004 (Legume/Corn/Tomato, Organic
      Corn/Tomato) and against 8/11/2004 and 8/12/2004 (Conventional Corn/Tomato).
    - Conventional Wheat/Tomato tomato 2001: 9/5/2001 against 8/29/2001.
    - Legume/Corn/Tomato 6-3E: 8/3/2010, against 9/3/2010 on the other plots and 9/6/2010 in the
      log. This may be a typo for 9/3/2010.
    - 2011 Legume/Corn/Tomato and Organic Corn/Tomato tomato: 9/19/2011 against 9/13/2011.
    - 1996 tomato on 4-5 and 2-5: 8/16/1996 against 8/22/1996.
    - The 2006 Transitional corn (item 22).
    - 2009 sudangrass on Conventional Corn/Tomato and Organic Corn/Tomato: 10/7/2009 against
      2009-10-28 in `plot_system.csv`.

    There are also many offsets of 1 to 3 days. We expected matching dates, or the difference
    explained.

### `compost_analyses_summary.csv`

51. Compost analyses are missing for several years. The file has no parameter at all for 1998,
    1999, 2000, 2005, 2006, 2008 or 2010. Compost was applied in 2000, 2005, 2006 and 2010. 1994
    to 1997 have Total C (In-house Costech) but no Total N; Total N starts in 2001. The file
    ends in 2013. The metadata says total C and N were analyzed from 1994 to 2014, and Tautges
    et al. 2019 say they were determined each year. We expected Total C and N for every
    application year.

52. The lab and basis for compost C and N. Every Total C and Total N row for 2001 to 2004, 2007
    and 2009 has analytical_lab 'UC Analytical Lab'. In-house Costech values exist only for
    Total C in 1994 to 1997, and for C and N in 2011 to 2013. The metadata credits the UC Davis
    lab only with additional properties in 2001 to 2009, and Tautges et al. 2019 describe
    Costech combustion every year. No parameter gives moisture or dry matter, and no basis is
    stated for %C and %N, while `operations_compost.csv` amounts are wet weight. Applied as is
    to the wet tonnage, %N gives a median of 171.3 kg N/ha per application (111.2 to 239.4).
    That is close to the paper's 150 to 200; a dry basis would lower it. Which basis are the
    values on, and are there moisture data?

53. Two Total N values for 2011 to 2013. Denele Analytical gives 3.01, 2.62 and 2.58%, against
    In-house Costech means of 2.670, 1.677 and 1.573% (ratios 1.13, 1.56 and 1.64). The metadata
    says Denele analyzed properties other than total C and N, though the same paragraph gives a
    Leco combustion method for total N. Which values should we use? Low priority.

### `soil_bulkdensities_all.csv`

54. Implausible bulk densities on 10/8/2012. Of 4,452 rows, 41 exceed 2.0 g/cm3 and 7 exceed
    2.2. All of them are from the 10/8/2012 sampling, where the median is 1.53. Three exceed the
    2.65 density of mineral particles:
    - 4.48 (5-1E, Irrigated Wheat/Legume, 0 to 15 cm, line 2780)
    - 4.47 (1-6W, Rainfed Wheat/Legume, 0 to 15 cm, line 1561)
    - 2.82 (7-8W, Conventional Corn/Tomato, 30 to 60 cm, line 3960)

    The other values above 2.2 are 2.63 (5-8W, Rainfed Wheat/Fallow, 15 to 30 cm), 2.46 (1-3W,
    Conventional Corn/Tomato, 15 to 30 cm), 2.39 (8-5E, Irrigated Wheat/Fallow, 30 to 60 cm) and
    2.26 (5-1W, Irrigated Wheat/Legume, 200 to 250 cm). Each is one of three cores for that plot
    and depth, and the other two are much lower; for 5-1E at 0 to 15 cm they are 1.26 and 1.57.
    Gravel doesn't explain them: residue_gravel_wt_g is 0, and the paper says the soils had no
    rock fragments. Separately, the Native Grass ids on that date carry stray spaces (' 7-1E ',
    ' 7-1W ', ' 8-6E ', ' 8-6W ').

### Metadata and `plot-system.csv`

55. `plot-system.csv` is not documented. It has 1776 rows and 23 columns for 1993 to 2016 (74
    plots a year). `plot_system.csv` has 1474 rows and 20 columns for 1993 to 2014 (67 plots).
    The 1474 plot years they share are identical cell for cell. `plot-system.csv` adds
    new_system_code, old_system_code and data_retrieval_notes (845 filled). It also adds rows
    for plots 2-1, 3-1, 3-2, 4-1, 3-3, B-1 and B-2, and for 2015 and 2016. Its notes are the
    only record of where many dates came from and which dates are placeholders. The metadata
    never mentions it and says the archive has 29 CSV files, while RR_2014_datasets.zip holds 30.
    The metadata also lists new_system_name twice for `plot_system.csv`; the second entry
    describes old_system_name. Could `plot-system.csv` be documented, or its notes folded into
    `plot_system.csv`? Both files are CP1252 encoded.

56. Metadata counts and descriptions that don't match the files. Low priority.
    - (a) `operations_fertilizers.csv` is described as 883 entries and has 886 rows.
    - (b) `soil_extracts_N_all.csv` is described as 3486 entries and has 3484.
    - (c) `alfalfa_harvests_all.csv` is described as holding wheat harvest records.
    - (d) The `operations_compost.csv` dictionary names the date column 'Date' (the header is
      'date') and describes it as the date the harvest was performed.
    - (e) The metadata mentions the 2013 corn replanting only for OMT, but Transitional 2-2,
      5-7, 7-4 were also seeded on 3/25/2013 and again on 5/15/2013.
    - (f) Some header names differ in case from the dictionary. `operations_planting.csv` has
      'Date', 'Crop_planted', 'Tractor', 'Equipment', 'Material_planted' and
      'Additional_description' where the dictionary has lower case.
      `sudangrass_harvests_all.csv` has 'date' and `plot_system.csv` has 'plot', where the
      dictionary has 'Date' and 'Plot'.
    - (g) `water_analyses_summary.csv` is described as having 19 cells a row but has 18 columns,
      and Section B calls it `water_analyses_all.csv`.

### Points about Tautges et al. 2019

We used the paper to fill in management the package doesn't record. These points are about the
paper, not the package.

57. System codes. Based on Table 1's inputs and `operations_fertilizers.csv`, we read the
    paper's systems this way:
    - CONV = Conventional Corn/Tomato
    - CONV+WCC = Legume/Corn/Tomato
    - ORG = Organic Corn/Tomato
    - RWF = Rainfed Wheat Control
    - RWF+N = Rainfed Wheat/Fallow
    - RWF+WCC = Rainfed Wheat/Legume
    - IWF = Irrigated Wheat Control
    - IWF+N = Irrigated Wheat/Fallow

    That means RWF and IWF name different systems in the paper and in the package. In places the
    Results switch to the package codes ('RWC, RWF+N, and IWC'). The text also says nine
    cropping systems, while Tables 1 and 3 list eight. Is our mapping right?

58. Irrigation amounts. The paper gives maize an average of 33.6 mm a year (17.6 mm in 1995,
    43.5 mm in 2004) and says tomato was irrigated the same way. In `weather_all.csv`, April to
    September rain is 22.3 to 139.2 mm, and May to September ET0 is 873.3 to 1001.5 mm (2010
    on). Against that, those figures look far too low as millimetres for furrow irrigated summer
    crops. Read as inches, they would average 853 mm a season (447 to 1105); read as
    centimetres, 336 mm. The metadata says irrigation is left out of the package by design.
    Which unit is meant, and where do the yearly amounts come from?

59. Table 1 N rates. Per crop season, the records give Conventional Corn/Tomato maize 235.38 kg
    N/ha on average over 1994 to 2007, which matches the Methods' 56 plus 180. They give its
    tomato 161.91, close to 56 plus 112. Table 1's 168 for CONV and CONV+WCC equals the tomato
    rate only, and CONV+WCC maize has no N rows at all (item 1). Table 1 gives IWF 168 kg N/ha
    with fertilizer source 'None', and the records have no N for Irrigated Wheat Control. Table
    1 gives RWF+N 146 (56 plus 90 in the Methods), but the records show about 112 a season.
    Which annual rates were used?

60. Maize and tomato N materials. 'Pre-plant starter 8-24-6' appears in only three rows:
    Conventional Wheat/Tomato tomato on 4/5/2013, at 28.0216 kg N/ha. Otherwise the early
    application is Ammonium sulfate at 56.55 kg N/ha up to 1996, then NPK_new (a YaraMila
    product with 15% N, 15% P2O5 and 15% K2O) at 46.24 to 55.99. The maize sidedress is always
    Urea (51 rows, 1994 to 2007). The tomato sidedress is Ammonium sulfate through 2009 and UAN
    32 from 2010. Organic Corn/Tomato has no fertilizer rows at all, though the Methods give the
    8-24-6 starter to all maize and tomato systems. Are the Methods a simplification, or are
    records missing?

61. Wheat N split. In Rainfed Wheat/Fallow and Irrigated Wheat/Fallow, a complete season has two
    N applications:
    - a preplant on or before seeding: Ammonium nitrate, then Can_27 from 10/12/1999; about 84
      kg N/ha rainfed and about 112 irrigated;
    - a Urea topdress, mostly in March: about 28 rainfed, and 56.04 or 56.2 irrigated.

    No wheat row is 15-15-15, and NPK_new never appears on wheat. The paper gives 56 kg/ha of
    15-15-15 at planting, then 90 or 112 kg/ha urea in March, for totals of 146 and 168. The
    irrigated total agrees, but the split is reversed, and the rainfed total in the records is
    about 112. Which is right?

62. No maize from 2008 to 2012. In Conventional Corn/Tomato, Legume/Corn/Tomato and Organic
    Corn/Tomato, `plot_system.csv` and the logs show fallow, sudangrass, wheat and tomato in
    those years, and no maize. Maize was grown in 14 of the paper's 19 years, and the metadata
    describes the change. The paper's Table 1 and Methods describe these systems as maize and
    tomato throughout. Do the paper's C inputs reflect what was actually grown in those five
    years?

63. Cover crops in Legume/Corn/Tomato. The planting log and `wcc_harvests_all.csv` show a cover
    crop:
    - before corn only, in 1994 to 2003;
    - on both phases from 2004 to 2009, and in 2013 and 2014;
    - before tomato only, in 2010 to 2012.

    The metadata describes the same pattern. Table 1 gives CONV+WCC a WCC before both crops.
    Does the CONV+WCC input split (30% from WCC) use the years as grown?

64. Wheat straw in 1994 to 1997. The `plot_system.csv` anomalies say the hand harvest in these
    years was actually done by machine baling, counting the bales in the plot. They contrast
    these plots with plots that 'had straw incorporated back into the ground'. The baled plots
    were:
    - 1994: 1-5, 1-9, 2-6, 3-4, 4-3, 5-9, 7-9, 8-2, 8-4
    - 1995 and 1997: 2-5, 2-8, 2-9, 3-7, 4-2, 4-6, 4-8, 5-2, 5-3, 5-8, 6-6, 7-2, 7-5, 8-1, 8-5
    - 1996: 1-5, 1-6, 1-9, 2-6, 3-4, 3-8, 4-3, 4-7, 5-1, 5-9, 7-3, 7-6, 7-9, 8-2, 8-4

    `operations_harvest.csv` has 15 'Swath1' rows on 7/10/1995, on exactly the 1995 plots. The
    paper says straw was incorporated and counts it as a C input. Were the bales removed from
    the plots?

65. Cover crop mix. `operations_planting.csv` has 'Vetch and peas (120lbs)' for every seeding
    from 11/9/1993 to 10/28/2005. Fall 2006 has 'Bell bean, vetch, oats 135 lbs/acre', and
    seedings from 11/13/2007 have 'Bell bean, vetch and oats 125 lbs/acre'. The paper's maize
    section puts the change in 2002. Its wheat section puts it in 2007, which fits if those
    years are termination years. The metadata puts it in 2006, at a rate that matches the 125
    lbs/acre rows but not the 135 of fall 2006. When did the mix change?

66. Metribuzin. `operations_pesticides.csv` has no metribuzin, and no Sencor, Lexone or TriCor.
    Conventional Corn/Tomato and Legume/Corn/Tomato maize got Dual, Bladex and Round-up
    products, and Conventional Corn/Tomato also got Goal and Gramoxone. The paper says
    metribuzin and glyphosate were applied before maize in CONV and CONV+WCC. Was metribuzin
    used?

67. Operation months. Several months in the Methods differ from the records:
    - Legume/Corn/Tomato and Organic Corn/Tomato maize was seeded in May or June in every logged
      year, from 5/2/2004 at the earliest to 6/4/1999 at the latest. Only 3 of 39 system seasons
      fall in early April, all of them Conventional Corn/Tomato.
    - Organic compost went on in March only once before maize (3/29/2004); otherwise it was
      April or May.
    - Tomato was transplanted in May in 26 of 52 phase seasons.
    - 24 of 36 maize harvests fell between 10/17 and 10/24.
    - Cover crops ended in April in 11 of 19 years.

    Are the Methods' months meant as typical ones?

68. Irrigation method. Table 1 gives IWF and IWF+N 'Supplemental Sprinkler', but its caption
    describes 'Supplemental flood'. The metadata says all irrigated systems were furrow flood
    irrigated through 2014, and its listed exceptions don't include the irrigated wheat. Which
    method did the wheat get?
