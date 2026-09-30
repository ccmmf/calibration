"""Stage a bounded diagnostic using existing PEcAn inputs; never edit source runs."""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def doy(year, date):
    return dt.datetime.strptime(str(year) + '-' + date, '%Y-%m-%d').date().timetuple().tm_yday


def calendar(spec, system, year, variant):
    s = spec[system]
    rows = []
    def add(date, typ, vals=()):
        rows.append((doy(year, date), len(rows), typ, list(vals)))
    add(s['tillage'], 'till', [s['tillage_intensity']])
    add(s['cash_establishment'], 'plant', s['cash_plant_C_g_m2'])
    add(s['cash_harvest'], 'harv', s['cash_harvest_fractions'])
    # LEAFOFF is one day after harvest to keep tissue removal unambiguous.
    off = dt.datetime.strptime(str(year)+'-'+s['cash_harvest'], '%Y-%m-%d').date() + dt.timedelta(days=1)
    add(off.strftime('%m-%d'), 'leafoff')
    for date, amount in s['mineral_n_g_m2'].items():
        add(date, 'fert', [0, 0, amount])
    start, stop = doy(year, s['irrigation_start']), doy(year, s['irrigation_stop'])
    windows = s.get('interruptions', [])[:(1 if variant == 'one_interruption' else 2 if variant == 'two_interruptions' else 0)]
    for day in range(start, stop + 1, s['irrigation_every_days']):
        if not any(doy(year, a) <= day <= doy(year, b) for a, b in windows):
            rows.append((day, len(rows), 'irrig', [s['irrigation_cm'], 1]))
    if system == 'annual' and variant == 'cover':
        # No fictitious cover exists before the first autumn establishment.
        if year > spec['evaluation_years'][0]:
            add(s['cover_termination'], 'harv', s['cover_harvest_fractions'])
            date = dt.datetime.strptime(str(year)+'-'+s['cover_termination'], '%Y-%m-%d').date() + dt.timedelta(days=1)
            add(date.strftime('%m-%d'), 'leafoff')
        add(s['cover_establishment'], 'plant', s['cover_plant_C_g_m2'])
    return ['{} {} {}{}\n'.format(year, day, typ, ''.join(' '+str(v) for v in vals))
            for day, _, typ, vals in sorted(rows)]


def prepare(spec_path, source, workspace):
    spec = json.loads(Path(spec_path).read_text())
    workspace = Path(workspace)
    workspace.mkdir(parents=True, exist_ok=False)
    shutil.copy2(spec_path, workspace/'pilot_spec.json')
    (workspace/'logs').mkdir()
    binary = Path(source)/'sipnet_v2.2.0-3ccc41c'
    expected = '16a626ae36bc94f995f606f7f5a32d630796971617310ada888c2ec591c6c0c9'
    if digest(binary) != expected:
        raise ValueError('Pinned executable checksum mismatch')
    tasks, manifest = [], []
    for case in spec['cases']:
        site = case['site_id']; system = case['system']
        src = Path(source)/'output/run'/('ENS-00001-'+site+'.'+case['source_scenario'])
        for prep in spec['preparation_years']:
            task = workspace/(site+'_prep'+str(prep)); task.mkdir()
            for name in ['sipnet.in', 'sipnet.param']:
                shutil.copy2(src/name, task/name)
            # Retain source forcing bytes for evaluation and record their identity.
            shutil.copyfile(src/'sipnet.clim', task/'evaluation.clim')
            lines = (task/'evaluation.clim').read_text().splitlines()
            years = sorted(set(int(x.split()[0]) for x in lines))
            if years != list(range(2016, 2024)):
                raise ValueError('Expected 2016-2023 forcing')
            climate = []
            for offset in range(-prep, 0, 8):
                for line in lines:
                    fields = line.split(); fields[0] = str(int(fields[0])+offset)
                    climate.append(' '.join(fields)+'\n')
            (task/'preparation.clim').write_text(''.join(climate))
            prep_events = sum([calendar(spec, system, y, 'baseline') for y in range(2016-prep, 2016)], [])
            (task/'preparation.events').write_text(''.join(prep_events))
            for variant in spec[system]['variants']:
                events = sum([calendar(spec, system, y, variant) for y in range(2016, 2024)], [])
                (task/(variant+'.events')).write_text(''.join(events))
            tasks.append(dict(path=str(task), site_id=site, system=system, prep_years=prep,
                              variants=spec[system]['variants'], binary=str(binary)))
            manifest.append(dict(site_id=site, system=system, prep_years=prep,
                source_run=str(src), parameters_sha256=digest(task/'sipnet.param'),
                config_sha256=digest(task/'sipnet.in'), weather_sha256=digest(task/'evaluation.clim'),
                binary_sha256=digest(binary), spec_sha256=digest(spec_path)))
    (workspace/'tasks.json').write_text(json.dumps(tasks, indent=2)+'\n')
    (workspace/'input_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('Prepared {} tasks; original inputs unchanged'.format(len(tasks)))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', required=True); ap.add_argument('--source', required=True)
    ap.add_argument('--workspace', required=True)
    a = ap.parse_args(); prepare(a.spec, a.source, a.workspace)
