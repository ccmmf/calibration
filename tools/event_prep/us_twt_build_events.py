#!/usr/bin/env python3
"""Build US-Twt events.json for 2010-2016 (ccmmf/organization#261).

Management for 2010-2015 comes from the curated Knox et al. (2016) records in
cal-val-data, not from re-reading the paper. 2016 comes from the statewide
monitoring product. Every event carries a provenance_class:

  published  the source states this date or amount directly
  derived    computed from a source series or a source-stated interval
  assumed    no source value; placed by rule and flagged as such
"""
import csv, json, argparse, datetime, statistics
from collections import Counter, defaultdict

import glob, os
CALVAL = "/home/aritra/Downloads/projects/ccmmf/cal-val-data/data/managements.csv"


def installed_schema_version(default="0.1.0"):
    """Match the schema shipped by the installed PEcAn.data.land.

    write.events.SIPNET() validates with the *installed* package, so writing a
    version it does not ship makes the file fail validation even though the
    event content is identical between 0.1.0 and 0.1.1.
    """
    hits = glob.glob(os.path.expanduser(
        "~/R/*/*/PEcAn.data.land/events_schema_v*.json"))
    vers = sorted(os.path.basename(h)[len("events_schema_v"):-len(".json")] for h in hits)
    return vers[-1] if vers else default
KNOX = "10.1002/2015JG003247"
SITE = "US-Twt"
CROP = "R1"

# leaf carbon at planting is a model input, not an observation. reuse the median
# of the monitoring-product values already used for this site and crop.
LEAF_C_KG_M2 = 0.02455947          # median of the 7 values in examples/us_twt/events.json
FRAC_ABOVE_REMOVED = 0.8           # as used for R1 in the existing file

LB_AC_TO_KG_HA = 1.12085
KG_HA_TO_KG_M2 = 1e-4


def n_from_grade(rate_lb_ac, grade):
    """N applied in kg m-2 from a field rate in lb/ac and an N-P-K grade."""
    n_pct = float(str(grade).split("-")[0])
    return round(rate_lb_ac * LB_AC_TO_KG_HA * (n_pct / 100.0) * KG_HA_TO_KG_M2, 8)


def load_knox():
    rows = [r for r in csv.DictReader(open(CALVAL))
            if "Twt" in (r.get("sites.name") or "") and r.get("citation") == KNOX]
    return rows


def d10(s):
    """date prefix, or empty when the source leaves it blank (curation writes NA)."""
    s = (s or "")[:10]
    return "" if s in ("", "NA") else s


def build(years):
    rows = load_knox()
    events = []

    def add(ev, cls, src, note=None):
        ev["provenance_class"] = cls
        ev["source"] = src
        if note:
            ev["provenance_note"] = note
        events.append(ev)

    plantings = {}
    for r in rows:
        mt, md = r.get("mgmttype"), d10(r.get("min_date"))
        if not md:
            continue
        yr = int(md[:4])
        if yr not in years:
            continue
        estimated = str(r.get("estimated")).lower() == "true"
        # a date the source gives as a range is derived; a single stated date is published
        cls = "derived" if estimated else "published"
        note = None
        if estimated:
            note = f"source reports a window {md}..{d10(r.get('max_date'))}; earliest date used"

        if mt == "planting":
            plantings[yr] = md
            add({"event_type": "planting", "date": md, "crop_code": CROP,
                 "crop_display": (r.get("crop_name") or CROP),
                 "leaf_c_kg_m2": LEAF_C_KG_M2,
                 "prior_filled": "leaf_c_kg_m2<-prior:us_twt_monitoring_product_median"},
                cls, f"calval:managements/{r['event_id']}", note)

        elif mt == "harvest":
            add({"event_type": "harvest", "date": md,
                 "crop_display": (r.get("crop_name") or CROP),
                 "frac_above_removed_0to1": FRAC_ABOVE_REMOVED,
                 "prior_filled": "frac_above_removed_0to1<-prior:R1_default"},
                cls, f"calval:managements/{r['event_id']}", note)

        elif mt == "fertilization":
            rate = float(r["level"])
            grade = r["reported_material"]
            n = n_from_grade(rate, grade)
            add({"event_type": "fertilization", "date": md,
                 "nh4_n_kg_m2": n, "no3_n_kg_m2": 0.0, "org_n_kg_m2": 0.0,
                 "reported_rate_lb_ac": rate, "reported_grade": grade},
                cls, f"calval:managements/{r['event_id']}",
                (note + "; " if note else "") +
                f"{rate} lb/ac of {grade} -> {n} kg N m-2, all as ammonium "
                "(these are ammonium/urea-based products); source reports product and rate, not N form")

    # tillage: Knox describes disking once or twice and ring rolling before planting,
    # with no dates. place relative to planting and mark assumed.
    for yr, pdate in sorted(plantings.items()):
        p = datetime.date.fromisoformat(pdate)
        for off, mat, eff in ((-21, "disking", 0.5), (-7, "ring rolling", 0.2)):
            add({"event_type": "tillage", "date": (p + datetime.timedelta(days=off)).isoformat(),
                 "tillage_eff_0to1": eff, "implement": mat},
                "assumed", "calval:managements/delta-tillage-000{}".format(1 if mat == "disking" else 2),
                f"Knox reports {mat} before planting without dates; placed {abs(off)} d before planting")

    events.sort(key=lambda e: (e["date"], e["event_type"]))
    return events


def assemble(start_year, end_year, with_2016=True):
    """Full event set: curated core, water events, and a synthesized 2016."""
    core_years = set(range(start_year, min(end_year, 2015) + 1))
    events = build(core_years)

    plantings = {e["date"][:4]: e["date"] for e in events if e["event_type"] == "planting"}
    harvests = {e["date"][:4]: e["date"] for e in events if e["event_type"] == "harvest"}
    ferts = [e for e in events if e["event_type"] == "fertilization"]
    pl = {int(k): v for k, v in plantings.items()}
    hv = {int(k): v for k, v in harvests.items()}

    def add(triple):
        ev, cls, src, note = triple
        ev["provenance_class"] = cls
        ev["source"] = src
        if note:
            ev["provenance_note"] = note
        events.append(ev)

    for triple in water_events_from_ranges(pl, hv):
        add(triple)

    if with_2016 and end_year >= 2016:
        for triple in synth_2016(plantings, harvests, ferts):
            add(triple)
        # tillage and water events for the synthesized year too, so every crop
        # year carries the same event structure
        p16date = [e for e in events if e["event_type"] == "planting"
                   and e["date"].startswith("2016")][0]["date"]
        p16d = datetime.date.fromisoformat(p16date)
        for off, mat, eff in ((-21, "disking", 0.5), (-7, "ring rolling", 0.2)):
            add(({"event_type": "tillage",
                  "date": (p16d + datetime.timedelta(days=off)).isoformat(),
                  "tillage_eff_0to1": eff, "implement": mat},
                 "assumed",
                 "calval:managements/delta-tillage-000{}".format(1 if mat == "disking" else 2),
                 f"Knox reports {mat} before planting without dates; placed {abs(off)} d "
                 "before the synthesized 2016 planting"))
        p16 = {2016: [e for e in events if e["event_type"] == "planting"
                      and e["date"].startswith("2016")][0]["date"]}
        h16 = {2016: [e for e in events if e["event_type"] == "harvest"
                      and e["date"].startswith("2016")][0]["date"]}
        for triple in water_events_from_ranges(p16, h16):
            add(triple)

    events.sort(key=lambda e: (e["date"], e["event_type"]))
    return events




# ---------------------------------------------------------------------------
# water management and 2016
# ---------------------------------------------------------------------------

# Knox reports these as intervals, not dates. They are the cross-check for a
# WTD-derived date; used directly only when WTD is unavailable.
FLOOD_AFTER_PLANTING_D = (45, 60)
DRAIN_BEFORE_HARVEST_D = (30, 45)
WINTER_FLOOD_DURATION_D = (65, 135)


def water_events_from_ranges(plantings, harvests):
    """Flood-up and drain placed at the midpoint of the interval Knox reports.

    Every event is `assumed`: the source constrains these to a two-week window,
    not a date. Replace with WTD-derived dates when the BASE product is available
    (ccmmf/organization#261 step 3).
    """
    out = []
    for yr in sorted(set(plantings) & set(harvests)):
        p = datetime.date.fromisoformat(plantings[yr])
        h = datetime.date.fromisoformat(harvests[yr])
        flood = p + datetime.timedelta(days=sum(FLOOD_AFTER_PLANTING_D) // 2)
        drain = h - datetime.timedelta(days=sum(DRAIN_BEFORE_HARVEST_D) // 2)
        out.append(({"event_type": "irrigation", "date": flood.isoformat(),
                     "amount_mm": 150.0, "method": "flood"},
                    "assumed", "calval:managements/delta-flooding-0006",
                    f"Knox reports flood-up {FLOOD_AFTER_PLANTING_D[0]}-{FLOOD_AFTER_PLANTING_D[1]} d "
                    f"after planting; midpoint used. Replace with WTD-derived date."))
        out.append(({"event_type": "irrigation", "date": drain.isoformat(),
                     "amount_mm": 0.0, "method": "flood"},
                    "assumed", "calval:managements/delta-drainage-0001",
                    f"Knox reports drain {DRAIN_BEFORE_HARVEST_D[0]}-{DRAIN_BEFORE_HARVEST_D[1]} d "
                    f"before harvest; midpoint used. amount 0 marks the drain. "
                    f"Replace with WTD-derived date."))
    return out


def synth_2016(plantings, harvests, ferts):
    """2016 carried forward from 2010-2015 by median day-of-year.

    The statewide monitoring product's 2016 export covers site_id 0..99999 only,
    so parcel 590073 is absent; 2017 is missing from the product entirely. This
    mirrors how the existing examples/us_twt/events.json synthesized 2017.
    """
    def med_doy(dates):
        doys = [datetime.date.fromisoformat(d).timetuple().tm_yday for d in dates]
        return int(statistics.median(doys))

    def from_doy(doy):
        return (datetime.date(2016, 1, 1) + datetime.timedelta(days=doy - 1)).isoformat()

    out = []
    pd_ = from_doy(med_doy(list(plantings.values())))
    hd_ = from_doy(med_doy(list(harvests.values())))
    out.append(({"event_type": "planting", "date": pd_, "crop_code": CROP, "crop_display": CROP,
                 "leaf_c_kg_m2": LEAF_C_KG_M2,
                 "prior_filled": "date<-synthesized:median_doy(2010-2015)"},
                "assumed", "synthesized:median_doy",
                "2016 absent from the monitoring product export (covers site_id 0..99999); "
                "date is the 2010-2015 median day of year"))
    out.append(({"event_type": "harvest", "date": hd_, "crop_display": CROP,
                 "frac_above_removed_0to1": FRAC_ABOVE_REMOVED,
                 "prior_filled": "date<-synthesized:median_doy(2010-2015)"},
                "assumed", "synthesized:median_doy",
                "2016 absent from the monitoring product export; date is the 2010-2015 median DOY"))
    # carry the most recent fertilizer regime (2013-2015 used a single 15-15-15 application)
    recent = [f for f in ferts if f["date"][:4] in ("2013", "2014", "2015")]
    if recent:
        rate = statistics.median(float(f["reported_rate_lb_ac"]) for f in recent)
        grade = recent[-1]["reported_grade"]
        n = n_from_grade(rate, grade)
        fdoy = med_doy([f["date"] for f in recent])
        out.append(({"event_type": "fertilization", "date": from_doy(fdoy),
                     "nh4_n_kg_m2": n, "no3_n_kg_m2": 0.0, "org_n_kg_m2": 0.0,
                     "reported_rate_lb_ac": rate, "reported_grade": grade,
                     "prior_filled": "date,rate<-synthesized:median(2013-2015)"},
                    "assumed", "synthesized:median_doy",
                    "2016 absent from the monitoring product export; rate and date are the "
                    "median of the 2013-2015 single-application regime"))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--start-year", type=int, default=2010)
    ap.add_argument("--end-year", type=int, default=2016)
    ap.add_argument("--out", default="/tmp/us_twt_events_2010_2016.json")
    a = ap.parse_args()

    ev = assemble(a.start_year, a.end_year)
    doc = {"pecan_events_version": installed_schema_version(), "site_id": SITE,
           "provenance": {"parcel_id": 590073, "crop": CROP,
                          "generator": "tools/us_twt_2010/build_events.py",
                          "note": "2010-2015 management from curated Knox et al. 2016 records "
                                  "(cal-val-data); water events from Knox intervals pending WTD; "
                                  "2016 synthesized, absent from the monitoring product export"},
           "events": ev}
    json.dump(doc, open(a.out, "w"), indent=1)
    print(f"wrote {len(ev)} events -> {a.out}")
    print("  by type :", dict(Counter(e["event_type"] for e in ev)))
    print("  by class:", dict(Counter(e["provenance_class"] for e in ev)))
    print("  by year :", dict(sorted(Counter(e["date"][:4] for e in ev).items())))
