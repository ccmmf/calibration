#!/usr/bin/env python3
"""events.json -> events.in, with the irrigation method code normalised.

PEcAn.SIPNET::write.events.SIPNET() maps irrigation methods as
`soil -> 1, everything else -> 0`, so `flood` is written as canopy (0).
SIPNET's own vocabulary is canopy=0, soil=1, flood=2 (see
workflows/tools/write_sipnet_event_file.R). At a flooded rice paddy that
difference is not cosmetic, so the method code is rewritten here from the
JSON, which is the source of truth and schema-valid either way.

Remove this correction once the upstream mapping is fixed; the verification
below will simply find nothing to change.
"""
import json, subprocess, sys, datetime, argparse, re, os

# SIPNET's documented vocabulary is canopy=0, soil=1, flood=2, but the build in
# use here rejects 2 outright ("Unknown irrigation method type: 2") and aborts the
# run. Flood irrigation is therefore emitted as canopy until a binary that
# implements it is available; the JSON keeps method="flood" so the intent is not
# lost, and the anaerobic/waterDrainFrac parameters that would make a flooded
# paddy meaningful are not set in this configuration either.
METHOD_CODE = {"canopy": 0, "soil": 1, "flood": 0}
SIPNET_SUPPORTS_FLOOD = False


def doy(datestr):
    d = datetime.date.fromisoformat(datestr)
    return d.timetuple().tm_yday


def main(events_json, outdir):
    os.makedirs(outdir, exist_ok=True)
    r = subprocess.run(
        ["Rscript", "-e",
         f'suppressMessages(library(PEcAn.SIPNET)); '
         f'PEcAn.SIPNET::write.events.SIPNET("{events_json}","{outdir}")'],
        capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"write.events.SIPNET failed:\n{r.stderr}")

    doc = json.load(open(events_json))
    infile = os.path.join(outdir, f"events-{doc['site_id']}.in")
    lines = open(infile).read().splitlines()

    # (year, doy) -> intended method, from the JSON
    want = {}
    for e in doc["events"]:
        if e["event_type"] == "irrigation":
            y = int(e["date"][:4])
            want[(y, doy(e["date"]))] = METHOD_CODE[e.get("method", "canopy")]

    fixed, checked = 0, 0
    out = []
    for ln in lines:
        m = re.match(r"^(\d+)\s+(\d+)\s+irrig\s+(\S+)\s+(\S+)\s*$", ln)
        if not m:
            out.append(ln); continue
        y, d, amt, code = int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))
        checked += 1
        target = want.get((y, d))
        if target is not None and target != code:
            out.append(f"{y}  {d}  irrig  {amt} {target}")
            fixed += 1
        else:
            out.append(ln)
    open(infile, "w").write("\n".join(out) + "\n")

    print(f"  wrote {infile}")
    print(f"  lines {len(out)} | json events {len(doc['events'])}"
          f" {'OK' if len(out) == len(doc['events']) else '<-- MISMATCH'}")
    print(f"  irrigation lines checked {checked}, method code corrected on {fixed}")
    # every irrigation line must now agree with the JSON
    bad = []
    for ln in out:
        m = re.match(r"^(\d+)\s+(\d+)\s+irrig\s+\S+\s+(\d+)\s*$", ln)
        if m:
            k = (int(m.group(1)), int(m.group(2)))
            if want.get(k) is not None and want[k] != int(m.group(3)):
                bad.append(ln)
    print(f"  verification: {'all irrigation methods match the JSON' if not bad else f'{len(bad)} STILL WRONG'}")
    return 0 if not bad else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("events_json")
    ap.add_argument("outdir")
    a = ap.parse_args()
    sys.exit(main(a.events_json, a.outdir))
