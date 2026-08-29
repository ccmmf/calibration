"""Merge the two US-Twt configs into one continuous 2010-2023 site.

Decided in the 2026-08-29 review call: the split existed only because the input
data differs either side of 2017, and "you don't want to split it up simply
because the input data is wrong or is inconsistent. We want to have consistent
input data for the model."

Tillage is the inconsistency. The 2010-2016 events carry 14 tillage events from
Knox; the 2017-2023 monitoring product carries none, which is a gap in the product
rather than a change in practice. Per the call, the literature is primary and
monitoring is the fallback, so the documented Knox pattern is extended forward:

    disking      planting - 21 d,  tillage_eff 0.5
    ring rolling planting -  7 d,  tillage_eff 0.2

That interval is exact in all seven Knox years, not fitted.
"""
import json, datetime, copy

CAL = "/home/aritra/Downloads/projects/ccmmf/calibration"
D = datetime.date.fromisoformat

a = json.load(open(f"{CAL}/runs/us_twt_2010/events.json"))   # 2010-2016, literature
b = json.load(open(f"{CAL}/runs/us_twt/events.json"))        # 2017-2023, monitoring

assert a["site_id"] == b["site_id"] == "US-Twt"

# --- verify the tillage rule holds in the literature years before extending it ---
lit_till = [e for e in a["events"] if e["event_type"] == "tillage"]
lit_plant = {e["date"][:4]: D(e["date"]) for e in a["events"] if e["event_type"] == "planting"}
offsets = {}
for e in lit_till:
    yr = e["date"][:4]
    if yr in lit_plant:
        offsets.setdefault(e["implement"], set()).add((lit_plant[yr] - D(e["date"])).days)
for imp, offs in sorted(offsets.items()):
    print(f"  {imp}: planting minus {sorted(offs)} d")
    assert len(offs) == 1, f"{imp} offset is not constant: {sorted(offs)}"
DISK_D, ROLL_D = offsets["disking"].pop(), offsets["ring rolling"].pop()

# --- backfill tillage for the monitoring years from that rule ---
new_till = []
for e in sorted(b["events"], key=lambda x: x["date"]):
    if e["event_type"] != "planting":
        continue
    p = D(e["date"])
    for imp, off, eff in (("disking", DISK_D, 0.5), ("ring rolling", ROLL_D, 0.2)):
        new_till.append({
            "event_type": "tillage",
            "date": (p - datetime.timedelta(days=off)).isoformat(),
            "tillage_eff_0to1": eff,
            "implement": imp,
            "provenance_class": "assumed",
            "source": "calval:managements/delta-tillage-0001",
            "provenance_note": (
                f"The monitoring product records no tillage for this parcel, which is a gap in the "
                f"product rather than a change in practice. Knox documents {imp} every year at "
                f"planting minus {off} d with tillage_eff {eff}, exact in all seven of 2010-2016, so "
                f"that pattern is carried forward onto the monitoring planting date of {e['date']}."
            ),
        })
print(f"  backfilled tillage events for 2017-2023: {len(new_till)}")

merged = copy.deepcopy(b)
merged["pecan_events_version"] = "0.1.1"
merged["provenance"] = {
    "parcel_id": 590073,
    "crop": "R1",
    "generator": "merge of the 2010-2016 literature build and the 2017-2023 monitoring build",
    "note": (
        "One continuous 2010-2023 series. 2010-2016 management is derived from Knox et al. 2016 "
        "with flood and drain dates from the AmeriFlux WTD series; 2017-2023 comes from the "
        "statewide monitoring product, which does not cover this parcel before 2017. Tillage for "
        "2017-2023 is carried forward from the Knox pattern because the product records none. "
        "Per-event source and provenance_class record which applies to each event."
    ),
}
merged["events"] = sorted(a["events"] + b["events"] + new_till,
                          key=lambda e: (e["date"], e["event_type"]))

out = f"{CAL}/runs/us_twt/events.json"
json.dump(merged, open(out, "w"), indent=1)

import collections
ds = [e["date"] for e in merged["events"]]
print(f"  merged: {len(merged['events'])} events  {ds[0]} -> {ds[-1]}")
print(f"  by type: {dict(collections.Counter(e['event_type'] for e in merged['events']))}")
till_yr = collections.Counter(e["date"][:4] for e in merged["events"] if e["event_type"]=="tillage")
print(f"  tillage per year: {dict(sorted(till_yr.items()))}")
