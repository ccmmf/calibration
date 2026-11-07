"""Independent stdlib-only recomputation of the regional comparison from the frozen inputs."""
import csv, sys, statistics as st
from collections import defaultdict
D = sys.argv[1]
def rows(n): return list(csv.DictReader(open(f"{D}/{n}")))
A2H = 0.40468564224
cr = rows("carb_2025_cropland_county_region.csv")
for r in cr: r["year"]=int(r["year"]); r["acres"]=float(r["acres"]); r["soil"]=float(r["soil_c_mt_c"])
regions = sorted({r["region"] for r in cr if r["region"]!="UNDEFINED"})
assert len(regions)==9
# --- CARB figure reproduction ---
agg = defaultdict(lambda: [0.0,0.0])
state = defaultdict(float)
for r in cr:
    state[r["year"]] += r["soil"]
    if r["region"]=="UNDEFINED": continue
    a = agg[(r["region"], r["year"])]; a[0]+=r["acres"]; a[1]+=r["soil"]
fig70 = {r["region"]: float(r["soil_c_density_change_t_per_acre"]) for r in rows("carb_2025_regional_soil_density_change.csv") if r["period"]=="2014-2022"}
fig69 = {r["region"]: float(r["soil_c_net_change_mmt_c"]) for r in rows("carb_2025_regional_soil_change.csv") if r["period"]=="2014-2022"}
fig63 = {r["region"]: float(r["area_change_million_acres"]) for r in rows("carb_2025_regional_area_change.csv") if r["period"]=="2014-2022"}
fig59 = {int(r["year"]): float(r["mmt_c"]) for r in rows("carb_2025_cropland_stocks.csv") if r["pool"]=="Soil"}
dens = lambda g,y: agg[(g,y)][1]/agg[(g,y)][0]
g70 = max(abs(dens(g,2022)-dens(g,2014)-fig70[g]) for g in regions)
g69 = max(abs((agg[(g,2022)][1]-agg[(g,2014)][1])/1e6-fig69[g]) for g in regions)
g63 = max(abs((agg[(g,2022)][0]-agg[(g,2014)][0])/1e6-fig63[g]) for g in regions)
g59 = max(abs(state[y]/1e6-fig59[y]) for y in range(2014,2023))
print(f"Fig70 worst gap {g70:.4f} t C/acre ({g70/A2H:.4f} Mg C/ha); Fig69 worst {g69:.4f} MMT C; Fig63 worst {g63:.5f} Macres; Fig59 worst {g59:.4f} MMT C")
# --- shares, pooled 2014-2022 ---
pool = defaultdict(float)
for r in cr:
    if r["county"]!="UNDEFINED": pool[(r["county"], r["region"])] += r["acres"]
ctot = defaultdict(float)
for (c,g),a in pool.items(): ctot[c]+=a
share = {(c,g): a/ctot[c] for (c,g),a in pool.items()}
multi = sorted({c for (c,g) in share if sum(1 for (c2,_) in share if c2==c)>1})
below95 = sorted(c for c in ctot if max(s for (c2,_),s in share.items() if c2==c) < 0.95)
print("counties split across regions:", len(multi), multi)
print("counties <95% in one region:", below95)
majority = {}
for c in ctot:
    g = max((s,g) for (c2,g),s in share.items() if c2==c)[1]; majority[(c,g)] = 1.0
# --- MAGiC county members ---
pred = rows("magic_v0.1.0_2023_county_predictions_by_ensemble_soc_agb.csv")
diff = rows("magic_v0.1.0_2023_county_differences_by_ensemble_soc_agb.csv")
k = lambda r: (r["model_output"], r["pft"], r["county"], int(r["ensemble"]))
dd = {k(r): r for r in diff}
assert len(pred)==4440 and len(dd)==4440
def region_members(output, pfts, split):
    acc = defaultdict(lambda: [0.0,0.0,0.0])  # start, delta, ha
    for p in pred:
        if p["model_output"]!=output or p["pft"] not in pfts: continue
        d = dd[k(p)]; end=float(p["total_per_county"]); delta=float(d["delta_total_county"]); ha=float(p["total_ha"])
        for (c,g),s in split.items():
            if c!=p["county"]: continue
            a = acc[(g,int(p["ensemble"]))]; a[0]+=(end-delta)*s; a[1]+=delta*s; a[2]+=ha*s
    out = {}
    for g in regions:
        ms = [acc[(g,e)] for e in range(1,21)]
        ch = [m[1]/m[2] for m in ms]; stt=[m[0]/m[2] for m in ms]; en=[(m[0]+m[1])/m[2] for m in ms]
        out[g] = dict(kha=ms[0][2]/1e3, mean=st.mean(ch), median=st.median(ch), lo=min(ch), hi=max(ch), losing=sum(x<0 for x in ch), start=st.mean(stt), end=st.mean(en))
    return out
soil = region_members("TotSoilCarb", {"annual crop","woody perennial crop"}, share)
soil_maj = region_members("TotSoilCarb", {"annual crop","woody perennial crop"}, majority)
woody = region_members("AGB", {"woody perennial crop"}, share)
T975 = 2.3646242510102993  # t quantile, 7 df
def trend(g):
    xs = list(range(2014,2023)); ys=[dens(g,y)/A2H for y in xs]
    xm, ym = st.mean(xs), st.mean(ys); sxx = sum((x-xm)**2 for x in xs)
    b = sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sxx; a = ym-b*xm
    se = (sum((y-a-b*x)**2 for x,y in zip(xs,ys))/7/sxx)**0.5
    return 8*b, 8*(b-T975*se), 8*(b+T975*se), min(ys), max(ys)
tot = sum(v["kha"] for v in soil.values())
print(f"\n{'region':24s} {'MAGiC kha':>9s} {'CARB kha':>8s} {'ratio':>5s} {'mean':>6s} {'median':>6s} {'range':>14s} {'lose':>4s} {'CARB 22-14':>10s} {'trend8 (95% CI)':>22s} {'maj diff':>8s}")
for g in sorted(regions, key=lambda g: -soil[g]["kha"]):
    s=soil[g]; ck = st.mean(agg[(g,y)][0] for y in range(2014,2023))*A2H/1e3
    t8,lo,hi,mn,mx = trend(g)
    print(f"{g:24s} {s['kha']:9.0f} {ck:8.0f} {s['kha']/ck:5.2f} {s['mean']:6.1f} {s['median']:6.1f} {s['lo']:6.1f} to {s['hi']:5.1f} {s['losing']:4d} {fig70[g]/A2H:10.1f} {t8:6.1f} ({lo:6.1f} to {hi:5.1f}) {abs(s['mean']-soil_maj[g]['mean']):8.2f}")
v = (soil["San Joaquin Valley"]["kha"]+soil["Sacramento Valley"]["kha"])/tot
print(f"\nvalley share of MAGiC area {v:.3f}; state MAGiC soil area {tot/1e3:.3f} Mha")
print("max majority-assignment effect:", round(max(abs(soil[g]['mean']-soil_maj[g]['mean']) for g in regions),3))
sj = trend("San Joaquin Valley"); sa = trend("Sacramento Valley")
print("SJV CI excludes MAGiC median:", not (sj[1] <= soil["San Joaquin Valley"]["median"] <= sj[2]))
print("Sac CI includes MAGiC mean:", sa[1] <= soil["Sacramento Valley"]["mean"] <= sa[2], "; Sac density range", round(sa[3],1), round(sa[4],1))
print("\nwoody AGB by region (Jan 2016 -> Dec 2023, Mg C/ha, members losing):")
for g in regions: print(f"  {g:24s} {woody[g]['start']:5.1f} -> {woody[g]['end']:4.1f}  {woody[g]['losing']}/20  kha {woody[g]['kha']:.0f}")
print("woody all members lose in every region:", all(woody[g]["losing"]==20 for g in regions))
print("SJV share of woody area: %.3f" % (woody["San Joaquin Valley"]["kha"]/sum(w["kha"] for w in woody.values())))
