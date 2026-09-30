"""Summarize actual pilot states, treatment effects, and expansion diagnostics."""
import argparse
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_output(path):
    with Path(path).open() as stream:
        names = stream.readline().split()
        required = {'year','day','soil','litter','soilWater','plantLeafC','fineRootC','gpp','ch4'}
        if not required.issubset(names): raise ValueError('Output contract mismatch')
        return [dict(zip(names, map(float,line.split()))) for line in stream if line.strip()]


def write_csv(path, rows):
    if not rows: raise ValueError('No output rows for '+str(path))
    with Path(path).open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)


def summarize(workspace):
    root=Path(workspace);tasks=json.loads((root/'tasks.json').read_text())
    summaries=[];effects=[];daily=[]
    for task in tasks:
        parent=Path(task['path']);params={}
        for line in (parent/'sipnet.param').read_text().splitlines():
            parts=line.split()
            if len(parts)>=2:
                try: params[parts[0]]=float(parts[1])
                except ValueError: pass
        # Only events may differ among evaluation variants.
        for name in ['sipnet.in', 'sipnet.param', 'sipnet.clim']:
            if len({sha(parent/v/name) for v in task['variants']}) != 1:
                raise ValueError('Unpaired input '+name)
        all_rows={}
        for variant in task['variants']:
            path=parent/variant
            receipt=json.loads((path/'receipt.json').read_text())
            if receipt['exit_code'] != 0: raise ValueError('Incomplete run '+str(path))
            data=read_output(path/'sipnet.out');all_rows[variant]=data
            if set(int(r['year']) for r in data)!=set(range(2016,2024)):
                raise ValueError('Incomplete evaluation years')
            by_day={}
            for r in data: by_day.setdefault((int(r['year']),int(r['day'])),[]).append(r)
            if len(by_day)!=2922: raise ValueError('Missing/extra days')
            bare_gpp=0.;bare_leaf=0.;bare_root=0.;dry=[];flood=[]
            for (year,day),rows in sorted(by_day.items()):
                date=dt.date(year,1,1)+dt.timedelta(days=day-1); md=date.strftime('%m-%d')
                gpp=sum(r['gpp'] for r in rows)
                leaf=max(r['plantLeafC'] for r in rows);root_c=max(r['fineRootC'] for r in rows)
                water_min=min(r['soilWater']/params['soilWHC'] for r in rows)
                water_mean=sum(r['soilWater']/params['soilWHC'] for r in rows)/len(rows)
                bare=(task['system']=='annual' and (md>='10-02' or md<='04-30'))
                if variant=='cover': bare=task['system']=='annual' and '04-03'<=md<='04-30' and year>2016
                if bare: bare_gpp+=gpp;bare_leaf=max(bare_leaf,leaf);bare_root=max(bare_root,root_c)
                if task['system']=='rice':
                    interruption=('06-15'<=md<='06-28') or (variant=='two_interruptions' and '07-15'<=md<='07-28')
                    if interruption: dry.append(water_min)
                    if '05-15'<=md<='09-10': flood.append(water_min)
                daily.append(dict(site_id=task['site_id'],system=task['system'],prep_years=task['prep_years'],
                    variant=variant,year=year,day=day,soil_C_Mg_ha=rows[-1]['soil']*0.01,
                    litter_C_Mg_ha=rows[-1]['litter']*0.01,water_ratio=water_mean,
                    leaf_C_g_m2=leaf,fine_root_C_g_m2=root_c,gpp_g_C_m2=gpp,
                    ch4_kg_C_ha=sum(r['ch4'] for r in rows)*10))
            summaries.append(dict(site_id=task['site_id'],system=task['system'],prep_years=task['prep_years'],
                variant=variant,rows=len(data),days=len(by_day),soil_C_end_Mg_ha=data[-1]['soil']*0.01,
                annual_mean_gpp_g_C_m2=sum(r['gpp'] for r in data)/8,
                maximum_leaf_area_index=max(r['lai'] for r in data),
                bare_period_gpp_g_C_m2=bare_gpp,bare_period_max_leaf_C_g_m2=bare_leaf,
                bare_period_max_fine_root_C_g_m2=bare_root,
                min_water_ratio_interruption=min(dry) if dry else '',
                proportion_season_days_below_saturation=sum(x<1 for x in flood)/len(flood) if flood else '',
                state_sha256=receipt['initial_state_sha256'],output_sha256=sha(path/'sipnet.out')))
        base=all_rows['baseline']
        if sha(parent/'baseline/sipnet.out')!=sha(parent/'no_change/sipnet.out'):
            raise ValueError('No-change control differs')
        states=[json.loads((parent/v/'receipt.json').read_text())['initial_state_sha256'] for v in task['variants']]
        if len(set(states))!=1: raise ValueError('Unpaired initial states')
        for variant in task['variants']:
            data=all_rows[variant]
            if [(r['year'],r['day'],r['time']) for r in base]!=[(r['year'],r['day'],r['time']) for r in data]:
                raise ValueError('Unpaired time support')
            # Month/day filtering is used for scientific seasonal totals, including leap years.
            def season(rows):
                return sum(r['ch4'] for r in rows if '05-15' <=
                    (dt.date(int(r['year']),1,1)+dt.timedelta(days=int(r['day'])-1)).strftime('%m-%d') <= '09-10')*10
            b_ch4=season(base);t_ch4=season(data)
            effects.append(dict(site_id=task['site_id'],system=task['system'],prep_years=task['prep_years'],
                variant=variant,soil_C_difference_Mg_ha=(data[-1]['soil']-base[-1]['soil'])*0.01,
                soil_C_difference_per_year=(data[-1]['soil']-base[-1]['soil'])*0.01/8,
                soil_C_RR=data[-1]['soil']/base[-1]['soil'] if base[-1]['soil']>0 else '',
                seasonal_ch4_baseline_kg_C_ha=b_ch4,seasonal_ch4_practice_kg_C_ha=t_ch4,
                seasonal_ch4_RR=t_ch4/b_ch4 if b_ch4>0 else '',
                no_change_verified=True,common_initial_state=True,common_non_treatment_inputs=True))
    out=root/'summary';out.mkdir(exist_ok=True)
    write_csv(out/'run_diagnostics.csv',summaries);write_csv(out/'paired_effects.csv',effects)
    write_csv(out/'daily_diagnostics.csv',daily)
    print('Summarized {} completed evaluation runs; all no-change and restart checks pass'.format(len(summaries)))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('workspace');a=ap.parse_args();summarize(a.workspace)
