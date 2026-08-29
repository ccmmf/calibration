"""Replace the flood-on / drain-off pair with a repeating irrigation schedule.

SIPNET has no drain event type and no persistent flood state. An irrigation event
adds its amount to the soil water pool once and nothing else
(https://github.com/PecanProject/sipnet/blob/master/src/sipnet/events.c, case
IRRIGATION: soilAmount = amount - evapAmount; fluxes.eventSoilWater += soilAmount).
So a 0 mm event is a no-op that still writes a row to events.out, and a single
150 mm application cannot hold a flood.

The flooded period is instead represented the way the 2017-2023 monitoring record
represents it: repeated applications through the season. Rate and interval come
from those events - 129 flood-method applications, mean 69.7 mm, median gap 8 d,
modal gap 7 d. Drainage becomes the absence of further irrigation, which is what
waterDrainFrac then acts on.

The WTD-derived flood and drain dates are kept as the bounds of each schedule, so
that derivation is preserved rather than discarded.

Usage:  us_twt_irrigation_schedule.py <events.json>   (edits in place)
"""
import json, datetime, copy, sys

IRRIGATION_MM = 70.0   # 2017-2023 mean 69.7 mm
INTERVAL_D = 7         # 2017-2023 modal gap 7 d (median 8 d)
RUN_START = datetime.date(2010, 1, 1)
RUN_END = datetime.date(2016, 12, 31)

path = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
doc = json.load(open(path))
ev = doc["events"]
D = datetime.date.fromisoformat

irr = sorted([e for e in ev if e["event_type"] == "irrigation"], key=lambda e: e["date"])
other = [e for e in ev if e["event_type"] != "irrigation"]

# pair each flood with the next drain, in date order; a leading drain is a carry-in
spans, pending = [], None
for e in irr:
    if e["amount_mm"] > 0:
        if pending is not None:
            spans.append((pending, None))
        pending = e
    else:
        spans.append((pending, e))
        pending = None
if pending is not None:
    spans.append((pending, None))

new = []
for flood, drain in spans:
    start = D(flood["date"]) if flood else RUN_START
    end = D(drain["date"]) if drain else RUN_END
    if end <= start:
        print(f"  SKIP non-positive span {start} -> {end}", file=sys.stderr)
        continue
    tmpl = flood or drain
    n, d = 0, start
    while d < end:
        e = copy.deepcopy(tmpl)
        e["date"] = d.isoformat()
        e["amount_mm"] = IRRIGATION_MM
        e["method"] = "flood"
        if n == 0 and flood:
            e["provenance_note"] = (
                flood.get("provenance_note", "") +
                f" Flood held by repeated application of {IRRIGATION_MM:.0f} mm every "
                f"{INTERVAL_D} d, the rate and interval of the 2017-2023 monitoring record, "
                f"because SIPNET has no persistent flood state."
            ).strip()
        elif n == 0:
            e["provenance_note"] = (
                f"Carry-in of the winter flood established before the run window; held at "
                f"{IRRIGATION_MM:.0f} mm every {INTERVAL_D} d until the WTD-derived drain."
            )
        else:
            e["provenance_note"] = (
                f"Maintains the flooded period begun {start.isoformat()}; ends "
                f"{end.isoformat()}, the WTD-derived drain date." if drain else
                f"Maintains the flooded period begun {start.isoformat()} to the end of the run window."
            )
        new.append(e)
        n += 1
        d += datetime.timedelta(days=INTERVAL_D)
    print(f"  {start} -> {end}  ({(end-start).days:3d} d)  {n:2d} events")

doc["events"] = sorted(other + new, key=lambda e: (e["date"], e["event_type"]))
json.dump(doc, open(path, "w"), indent=1)
print(f"\n  irrigation: {len(irr)} -> {len(new)}   total: {len(ev)} -> {len(doc['events'])}")
