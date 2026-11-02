"""Retain numerical conservation diagnostics separately from execution success."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re

def audit(workspace):
    p=Path(workspace);tasks=json.loads((p/'tasks.json').read_text()); rows=[]
    for t in tasks:
        for v in ['preparation']+t['variants']:
            d=Path(t['path'])/v;text=(d/'run.log').read_text()
            delta=re.findall(r'(Carbon|Nitrogen) balance check failed \(delta=([-+\d.eE]+)',text)
            c=[abs(float(x)) for el,x in delta if el=='Carbon']
            n=[abs(float(x)) for el,x in delta if el=='Nitrogen']
            clamps=[abs(float(x)) for x in re.findall(r'Non-negative stock constraint applied.*?value ([-+\d.eE]+)',text)]
            rows.append(dict(site_id=t['site_id'],prep_years=t['prep_years'],variant=v,
                warnings=text.count('[WARNING]'),carbon_balance_warnings=len(c),
                max_carbon_delta=max(c) if c else 0,nitrogen_balance_warnings=len(n),
                max_nitrogen_delta=max(n) if n else 0,clamp_warnings=len(clamps),
                max_reported_clamp=max(clamps) if clamps else 0,
                log_sha256=hashlib.sha256((d/'run.log').read_bytes()).hexdigest()))
    with (p/'summary/log_audit.csv').open('w') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('workspace');a=ap.parse_args();audit(a.workspace)
