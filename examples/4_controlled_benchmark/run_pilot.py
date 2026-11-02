"""Run one staged SGE task using the pinned SIPNET executable and common restart."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time


def run(task, variant):
    parent = Path(task['path']); dest = parent/variant
    dest.mkdir(exist_ok=False)
    for name in ['sipnet.in', 'sipnet.param']:
        shutil.copy2(parent/name, dest/name)
    preparation = variant == 'preparation'
    shutil.copy2(parent/('preparation.clim' if preparation else 'evaluation.clim'), dest/'sipnet.clim')
    shutil.copy2(parent/(variant+'.events'), dest/'events.in')
    cmd = [task['binary'], '--dump-config']
    if preparation:
        cmd += ['--restart-out', 'baseline.restart']
    else:
        checkpoint = parent/'preparation/baseline.restart'
        cmd += ['--restart-in', str(checkpoint)]
    start = time.time()
    with (dest/'run.log').open('w') as log:
        result = subprocess.run(cmd, cwd=str(dest), stdout=log, stderr=subprocess.STDOUT)
    receipt = dict(command=cmd, exit_code=result.returncode, seconds=time.time()-start)
    if not preparation:
        receipt['initial_state_sha256'] = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    (dest/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if result.returncode:
        raise RuntimeError('Model error in '+str(dest))


if __name__ == '__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('workspace'); ap.add_argument('task', type=int)
    args=ap.parse_args(); tasks=json.loads((Path(args.workspace)/'tasks.json').read_text())
    task=tasks[args.task-1]
    run(task, 'preparation')
    for variant in task['variants']:
        run(task, variant)
