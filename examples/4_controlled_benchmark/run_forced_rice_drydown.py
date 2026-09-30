"""Run bounded rice drainage and state-forced dry-down diagnostics with SIPNET.

This script does not claim to validate SIPNET hydrology. SIPNET v2.2.0 has no
field-drain event. The script therefore compares a one-time removal of ponded
excess followed by model-evolved drying with prescribed soil-water trajectories.
All imposed water removal and reflooding is recorded separately from model
fluxes.
"""

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

from prepare_pilot import calendar


PLANTING_DATE = "05-15"
DRYDOWN_START = "06-19"  # 35 days after planting
DRYDOWN_END = "06-28"
REFLOOD_DATE = "06-29"  # 45 days after planting
REPRODUCTIVE_DRYDOWN_START = "07-15"
REPRODUCTIVE_DRYDOWN_END = "07-24"
REPRODUCTIVE_REFLOOD_DATE = "07-25"  # target reached about 10 weeks after planting
FIELD_REFERENCE_TARGET_WATER_RATIOS = (
    1.0,
    0.9,
    0.8,
    0.7,
    0.6,
    0.595,
    0.595,
    0.595,
    0.595,
    0.595,
)
THRESHOLD_STRESS_TARGET_WATER_RATIOS = (
    1.0,
    0.9,
    0.8,
    0.7,
    0.6,
    0.5,
    0.4,
    0.3,
    0.25,
    0.25,
)
TARGET_SCHEDULES = {
    "field_reference_drydown": FIELD_REFERENCE_TARGET_WATER_RATIOS,
    "threshold_stress_drydown": THRESHOLD_STRESS_TARGET_WATER_RATIOS,
    "reproductive_severe_field_drydown": THRESHOLD_STRESS_TARGET_WATER_RATIOS,
}
PRESCRIBED_TRAJECTORY = "prescribed_trajectory"
INITIAL_DRAIN_ONLY = "initial_drain_only"
NO_WATER_INTERVENTION = "none"
SCENARIO_SPECS = {
    "field_reference_drydown": {
        "drydown_start": DRYDOWN_START,
        "drydown_end": DRYDOWN_END,
        "reflood_date": REFLOOD_DATE,
        "target_water_ratios": FIELD_REFERENCE_TARGET_WATER_RATIOS,
        "water_intervention": PRESCRIBED_TRAJECTORY,
        "expected_threshold_crossing": False,
    },
    "threshold_stress_drydown": {
        "drydown_start": DRYDOWN_START,
        "drydown_end": DRYDOWN_END,
        "reflood_date": REFLOOD_DATE,
        "target_water_ratios": THRESHOLD_STRESS_TARGET_WATER_RATIOS,
        "water_intervention": PRESCRIBED_TRAJECTORY,
        "expected_threshold_crossing": True,
    },
    "reproductive_severe_field_drydown": {
        "drydown_start": REPRODUCTIVE_DRYDOWN_START,
        "drydown_end": REPRODUCTIVE_DRYDOWN_END,
        "reflood_date": REPRODUCTIVE_REFLOOD_DATE,
        "target_water_ratios": THRESHOLD_STRESS_TARGET_WATER_RATIOS,
        "water_intervention": PRESCRIBED_TRAJECTORY,
        "expected_threshold_crossing": True,
    },
    "reproductive_one_time_drain": {
        "drydown_start": REPRODUCTIVE_DRYDOWN_START,
        "drydown_end": REPRODUCTIVE_DRYDOWN_END,
        "reflood_date": REPRODUCTIVE_REFLOOD_DATE,
        "target_water_ratios": None,
        "water_intervention": INITIAL_DRAIN_ONLY,
        "expected_threshold_crossing": False,
    },
}
REFLOOD_DEPTH_CM = 5.0
EVALUATION_YEARS = tuple(range(2016, 2024))
TASKS = ("413887_prep8", "413887_prep16", "535358_prep8", "535358_prep16")
FIELD_WINDOW_START_DAP = tuple(range(34, 50))
FIELD_WINDOW_DURATIONS = (5, 8, 10, 12)
EXPECTED_DAYS = sum(366 if year % 4 == 0 else 365 for year in EVALUATION_YEARS)
EXPECTED_TIMESTEPS_PER_DAY = 8
TIMESTEP_LENGTH_DAYS = 1.0 / EXPECTED_TIMESTEPS_PER_DAY
EXPECTED_ROWS = EXPECTED_DAYS * EXPECTED_TIMESTEPS_PER_DAY


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_params(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if len(fields) == 2:
            try:
                values[fields[0]] = float(fields[1])
            except ValueError:
                pass
    return values


def read_restart_value(path, key):
    prefix = key + " "
    matches = [line for line in Path(path).read_text().splitlines() if line.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"Expected one {key} value in {path}")
    return float(matches[0].split(maxsplit=1)[1])


def replace_restart_value(source, destination, key, value):
    prefix = key + " "
    lines = Path(source).read_text().splitlines()
    matches = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"Expected one {key} value in {source}")
    lines[matches[0]] = f"{key} {value:.17g}"
    Path(destination).write_text("\n".join(lines) + "\n")


def date_from_year_day(year, day):
    return dt.date(year, 1, 1) + dt.timedelta(days=day - 1)


def group_climate(path):
    grouped = {}
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        fields = line.split()
        key = (int(fields[0]), int(fields[1]))
        grouped.setdefault(key, []).append(line)
    if len(grouped) != EXPECTED_DAYS:
        raise ValueError("Climate file does not contain one complete 2016-2023 record")
    for key, lines in grouped.items():
        lengths = [float(line.split()[3]) for line in lines]
        if len(lengths) != EXPECTED_TIMESTEPS_PER_DAY or not all(
            math.isclose(length, TIMESTEP_LENGTH_DAYS, rel_tol=1e-12)
            for length in lengths
        ):
            raise ValueError(f"Climate day {key} does not contain eight 3-hour steps")
    return grouped


def build_events(spec, variant):
    rows = []
    for year in EVALUATION_YEARS:
        rows.extend(calendar(spec, "rice", year, variant))
    grouped = {}
    for row in rows:
        fields = row.split()
        grouped.setdefault((int(fields[0]), int(fields[1])), []).append(row.rstrip("\n"))
    return grouped


def slice_grouped(grouped, start, end):
    rows = []
    current = start
    while current <= end:
        key = (current.year, current.timetuple().tm_yday)
        rows.extend(grouped.get(key, []))
        current += dt.timedelta(days=1)
    return rows


def run_segment(binary, task_source, run_dir, restart_in, climate_lines, event_lines):
    run_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(task_source / "sipnet.in", run_dir / "sipnet.in")
    shutil.copy2(task_source / "sipnet.param", run_dir / "sipnet.param")
    shutil.copy2(restart_in, run_dir / "input.restart")
    (run_dir / "sipnet.clim").write_text("\n".join(climate_lines) + "\n")
    (run_dir / "events.in").write_text(
        "\n".join(event_lines) + ("\n" if event_lines else "")
    )
    command = [
        str(binary),
        "--restart-in",
        "input.restart",
        "--restart-out",
        "output.restart",
    ]
    with (run_dir / "run.log").open("w") as stream:
        result = subprocess.run(command, cwd=run_dir, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"SIPNET failed in {run_dir}")
    return run_dir / "output.restart", run_dir / "sipnet.out"


def output_rows(path):
    with Path(path).open() as stream:
        names = stream.readline().split()
        return [dict(zip(names, map(float, line.split()))) for line in stream if line.strip()]


def output_keys(rows):
    return [(int(row["year"]), int(row["day"]), row["time"]) for row in rows]


def validate_output_support(
    baseline_rows, treatment_rows, first_drydown_month_day
):
    baseline_keys = output_keys(baseline_rows)
    treatment_keys = output_keys(treatment_rows)
    if len(baseline_keys) != EXPECTED_ROWS or len(treatment_keys) != EXPECTED_ROWS:
        raise ValueError(
            f"Expected {EXPECTED_ROWS} rows in both scenarios; got "
            f"{len(baseline_keys)} baseline and {len(treatment_keys)} treatment"
        )
    if len(set(baseline_keys)) != EXPECTED_ROWS:
        raise ValueError("Baseline output contains duplicate time keys")
    if len(set(treatment_keys)) != EXPECTED_ROWS:
        raise ValueError("Treatment output contains duplicate time keys")
    if baseline_keys != treatment_keys:
        raise ValueError("Baseline and treatment output time support differs")
    first_drydown_day = dt.date.fromisoformat(
        f"{EVALUATION_YEARS[0]}-{first_drydown_month_day}"
    ).timetuple().tm_yday
    baseline_initial = [
        row
        for row in baseline_rows
        if (int(row["year"]), int(row["day"]))
        < (EVALUATION_YEARS[0], first_drydown_day)
    ]
    treatment_initial = [
        row
        for row in treatment_rows
        if (int(row["year"]), int(row["day"]))
        < (EVALUATION_YEARS[0], first_drydown_day)
    ]
    if baseline_initial != treatment_initial:
        raise ValueError("Baseline and treatment differ before the first dry-down")
    day_counts = {}
    for year, day, _ in treatment_keys:
        day_counts[(year, day)] = day_counts.get((year, day), 0) + 1
    if len(day_counts) != EXPECTED_DAYS or set(day_counts.values()) != {
        EXPECTED_TIMESTEPS_PER_DAY
    }:
        raise ValueError("Treatment output does not contain eight steps for every day")
    return {
        "evaluation_days": len(day_counts),
        "timesteps_per_day": EXPECTED_TIMESTEPS_PER_DAY,
        "rows_per_scenario": len(treatment_keys),
        "time_support_identical": True,
        "initial_pre_treatment_rows_identical": True,
    }


def audit_logs(task_output, task_name):
    balance_pattern = re.compile(
        r"(Carbon|Nitrogen) balance check failed \(delta=([-+\d.eE]+)"
    )
    audits = []
    scenarios = {
        scenario: sorted(task_output.glob(f"{scenario}/segment-*/run.log"))
        for scenario in ("baseline", *SCENARIO_SPECS)
    }
    for scenario, logs in scenarios.items():
        carbon = []
        nitrogen = []
        warning_lines = 0
        error_lines = 0
        for path in logs:
            text = path.read_text()
            warning_lines += text.count("[WARNING]")
            error_lines += text.count("[ERROR]")
            for element, value in balance_pattern.findall(text):
                target = carbon if element == "Carbon" else nitrogen
                target.append(abs(float(value)))
        audits.append(
            {
                "task": task_name,
                "scenario": scenario,
                "log_files": len(logs),
                "warning_lines": warning_lines,
                "error_lines": error_lines,
                "carbon_balance_warnings": len(carbon),
                "maximum_absolute_carbon_delta": max(carbon) if carbon else 0.0,
                "nitrogen_balance_warnings": len(nitrogen),
                "maximum_absolute_nitrogen_delta": max(nitrogen) if nitrogen else 0.0,
            }
        )
    if any(row["error_lines"] for row in audits):
        raise ValueError(f"SIPNET reported an error in {task_name}")
    return audits


def summarize(rows, params, drydown_start=None, drydown_end=None):
    daily = {}
    for row in rows:
        key = (int(row["year"]), int(row["day"]))
        daily.setdefault(key, []).append(row)
    selected = []
    for (year, day), values in sorted(daily.items()):
        date = date_from_year_day(year, day)
        month_day = date.strftime("%m-%d")
        if drydown_start is not None and not (
            drydown_start <= month_day <= drydown_end
        ):
            continue
        if drydown_start is None and not (PLANTING_DATE <= month_day <= "09-10"):
            continue
        ratios = [row["soilWater"] / params["soilWHC"] for row in values]
        selected.append(
            {
                "year": year,
                "date": date.isoformat(),
                "minimum_water_ratio": min(ratios),
                "mean_water_ratio": sum(ratios) / len(ratios),
                "maximum_water_ratio": max(ratios),
                "ch4_kg_C_ha": sum(row["ch4"] for row in values) * 10,
                "evapotranspiration_cm": sum(
                    row["evapotranspiration"] for row in values
                ),
                "transpiration_cm": sum(
                    row["fluxestranspiration"] * TIMESTEP_LENGTH_DAYS
                    for row in values
                ),
                "minimum_lai": min(row["lai"] for row in values),
                "maximum_lai": max(row["lai"] for row in values),
                "reaches_f_anoxia": min(ratios) <= params["fAnoxia"],
            }
        )
    return selected


def write_csv(path, rows):
    if not rows:
        raise ValueError(f"No rows to write to {path}")
    with Path(path).open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=list(rows[0]), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)


def compact_trajectory(rows):
    grouped = {}
    for row in rows:
        if row["scenario"] == "baseline":
            continue
        spec = SCENARIO_SPECS[row["scenario"]]
        if not (
            spec["drydown_start"]
            <= row["date"][5:]
            <= spec["reflood_date"]
        ):
            continue
        key = (row["task"], row["scenario"], row["date"][5:])
        grouped.setdefault(key, []).append(row)
    compact = []
    for (task, scenario, month_day), values in sorted(grouped.items()):
        compact.append(
            {
                "task": task,
                "scenario": scenario,
                "month_day": month_day,
                "years": len(values),
                "minimum_water_ratio": min(
                    row["minimum_water_ratio"] for row in values
                ),
                "mean_water_ratio": sum(row["mean_water_ratio"] for row in values)
                / len(values),
                "maximum_water_ratio": max(
                    row["maximum_water_ratio"] for row in values
                ),
                "mean_daily_ch4_kg_C_ha": sum(
                    row["ch4_kg_C_ha"] for row in values
                )
                / len(values),
            }
        )
    return compact


def methane_window_bounds(task_name, baseline_season):
    by_date = {row["date"]: row["ch4_kg_C_ha"] for row in baseline_season}
    seasonal_ch4 = sum(by_date.values())
    bounds = []
    for duration in FIELD_WINDOW_DURATIONS:
        candidates = []
        for start_dap in FIELD_WINDOW_START_DAP:
            window_ch4 = 0.0
            for year in EVALUATION_YEARS:
                planting = dt.date.fromisoformat(f"{year}-{PLANTING_DATE}")
                start = planting + dt.timedelta(days=start_dap)
                for offset in range(duration):
                    date = start + dt.timedelta(days=offset)
                    window_ch4 += by_date[date.isoformat()]
            candidates.append((window_ch4 / seasonal_ch4, start_dap))
        maximum_share, best_start_dap = max(candidates)
        bounds.append(
            {
                "task": task_name,
                "duration_days": duration,
                "best_start_dap": best_start_dap,
                "maximum_baseline_seasonal_ch4_share": maximum_share,
                "interpretation": (
                    "upper bound if methane were zero only within the window; "
                    "excludes post-drain persistence"
                ),
            }
        )
    return bounds


def natural_drydown_gaps(summaries, daily):
    """Quantify the net storage-loss gap after a one-time drain to soilWHC."""
    gaps = []
    scenario = "reproductive_one_time_drain"
    for summary in summaries:
        if summary["scenario"] != scenario:
            continue
        endpoint_rows = [
            row
            for row in daily
            if row["task"] == summary["task"]
            and row["scenario"] == scenario
            and row["date"][5:] == summary["drydown_end"]
        ]
        drydown_rows = [
            row
            for row in daily
            if row["task"] == summary["task"]
            and row["scenario"] == scenario
            and summary["drydown_start"] <= row["date"][5:] <= summary["drydown_end"]
        ]
        if len(endpoint_rows) != len(EVALUATION_YEARS):
            raise ValueError(
                f"{summary['task']} lacks one natural dry-down endpoint per year"
            )
        drydown_days = (
            dt.date.fromisoformat(f"2000-{summary['drydown_end']}")
            - dt.date.fromisoformat(f"2000-{summary['drydown_start']}")
        ).days + 1
        soil_whc = summary["soil_whc_cm"]
        endpoint_ratios = [row["minimum_water_ratio"] for row in endpoint_rows]
        realized_losses = [soil_whc * (1.0 - ratio) for ratio in endpoint_ratios]
        required_loss = soil_whc * (
            1.0 - THRESHOLD_STRESS_TARGET_WATER_RATIOS[-1]
        )
        maximum_realized_loss = max(realized_losses)
        total_evapotranspiration = sum(
            row["evapotranspiration_cm"] for row in drydown_rows
        )
        total_transpiration = sum(row["transpiration_cm"] for row in drydown_rows)
        gaps.append(
            {
                "task": summary["task"],
                "site_id": summary["site_id"],
                "prep_years": summary["prep_years"],
                "drydown_days": drydown_days,
                "years": len(endpoint_rows),
                "minimum_endpoint_water_ratio": min(endpoint_ratios),
                "mean_endpoint_water_ratio": sum(endpoint_ratios)
                / len(endpoint_ratios),
                "maximum_net_storage_loss_cm": maximum_realized_loss,
                "mean_net_storage_loss_cm": sum(realized_losses)
                / len(realized_losses),
                "required_net_storage_loss_to_ratio_0_25_cm": required_loss,
                "maximum_realized_mean_daily_loss_cm": maximum_realized_loss
                / drydown_days,
                "required_mean_daily_loss_to_ratio_0_25_cm": required_loss
                / drydown_days,
                "required_to_realized_loss_factor": required_loss
                / maximum_realized_loss,
                "mean_daily_evapotranspiration_cm": total_evapotranspiration
                / len(drydown_rows),
                "mean_daily_transpiration_cm": total_transpiration
                / len(drydown_rows),
                "transpiration_fraction_of_evapotranspiration": (
                    total_transpiration / total_evapotranspiration
                ),
                "minimum_lai": min(row["minimum_lai"] for row in drydown_rows),
                "maximum_lai": max(row["maximum_lai"] for row in drydown_rows),
            }
        )
    return gaps


def run_segmented_scenario(
    binary,
    source,
    task_output,
    scenario,
    initial_restart,
    climate,
    events,
    params,
    water_intervention,
    drydown_start,
    drydown_end,
    reflood_date,
    target_water_ratios=None,
):
    rows = []
    adjustments = []
    current_restart = initial_restart
    segment_number = 0
    scenario_output = task_output / scenario
    for year in EVALUATION_YEARS:
        start = dt.date(year, 1, 1)
        dry_start = dt.date.fromisoformat(f"{year}-{drydown_start}")
        dry_end = dt.date.fromisoformat(f"{year}-{drydown_end}")
        reflood = dt.date.fromisoformat(f"{year}-{reflood_date}")
        end = dt.date(year, 12, 31)

        segment_number += 1
        current_restart, segment_output = run_segment(
            binary,
            source,
            scenario_output / f"segment-{segment_number:03d}-pre-{year}",
            current_restart,
            slice_grouped(climate, start, dry_start - dt.timedelta(days=1)),
            slice_grouped(events, start, dry_start - dt.timedelta(days=1)),
        )
        rows.extend(output_rows(segment_output))

        drydown_days = (dry_end - dry_start).days + 1
        if water_intervention == PRESCRIBED_TRAJECTORY:
            if target_water_ratios is None or len(target_water_ratios) != drydown_days:
                raise ValueError("Prescribed trajectory must span the dry-down window")
        elif water_intervention not in (INITIAL_DRAIN_ONLY, NO_WATER_INTERVENTION):
            raise ValueError(f"Unknown water intervention: {water_intervention}")

        for offset in range(drydown_days):
            date = dry_start + dt.timedelta(days=offset)
            restart_in = current_restart
            if water_intervention == PRESCRIBED_TRAJECTORY:
                target_ratio = target_water_ratios[offset]
            elif water_intervention == INITIAL_DRAIN_ONLY and offset == 0:
                target_ratio = 1.0
            else:
                target_ratio = None
            if target_ratio is not None:
                water_before = read_restart_value(current_restart, "envi.soilWater")
                target_water = target_ratio * params["soilWHC"]
                water_after = min(water_before, target_water)
                restart_in = scenario_output / f"forced-{date.isoformat()}.restart"
                replace_restart_value(
                    current_restart, restart_in, "envi.soilWater", water_after
                )
                adjustments.append(
                    {
                        "task": source.name,
                        "scenario": scenario,
                        "date": date.isoformat(),
                        "operation": (
                            "prescribed_drydown"
                            if water_intervention == PRESCRIBED_TRAJECTORY
                            else "initial_ponded_water_drain"
                        ),
                        "target_water_ratio": target_ratio,
                        "water_before_cm": water_before,
                        "water_after_cm": water_after,
                        "external_water_change_cm": water_after - water_before,
                    }
                )
            segment_number += 1
            current_restart, segment_output = run_segment(
                binary,
                source,
                scenario_output
                / f"segment-{segment_number:03d}-dry-{date.isoformat()}",
                restart_in,
                climate[(year, date.timetuple().tm_yday)],
                events.get((year, date.timetuple().tm_yday), []),
            )
            rows.extend(output_rows(segment_output))

        restart_in = current_restart
        if water_intervention != NO_WATER_INTERVENTION:
            water_before = read_restart_value(current_restart, "envi.soilWater")
            reflood_water = params["soilWHC"] + REFLOOD_DEPTH_CM
            restart_in = scenario_output / f"forced-{reflood.isoformat()}.restart"
            replace_restart_value(
                current_restart, restart_in, "envi.soilWater", reflood_water
            )
            adjustments.append(
                {
                    "task": source.name,
                    "scenario": scenario,
                    "date": reflood.isoformat(),
                    "operation": "reflood",
                    "target_water_ratio": reflood_water / params["soilWHC"],
                    "water_before_cm": water_before,
                    "water_after_cm": reflood_water,
                    "external_water_change_cm": reflood_water - water_before,
                }
            )
        segment_number += 1
        current_restart, segment_output = run_segment(
            binary,
            source,
            scenario_output / f"segment-{segment_number:03d}-post-{year}",
            restart_in,
            slice_grouped(climate, reflood, end),
            slice_grouped(events, reflood, end),
        )
        rows.extend(output_rows(segment_output))
    return rows, adjustments


def run_task(binary, workspace, output, task_name, spec):
    source = workspace / task_name
    task_output = output / task_name
    task_output.mkdir()
    params = read_params(source / "sipnet.param")
    required = {"soilWHC", "fAnoxia", "anaerobicTransExp"}
    if not required.issubset(params):
        raise ValueError(f"Missing rice moisture parameters in {task_name}")
    climate = group_climate(source / "evaluation.clim")

    baseline_events = build_events(spec, "baseline")
    initial_restart = source / "preparation" / "baseline.restart"
    baseline_rows, baseline_adjustments = run_segmented_scenario(
        binary,
        source,
        task_output,
        "baseline",
        initial_restart,
        climate,
        baseline_events,
        params,
        water_intervention=NO_WATER_INTERVENTION,
        drydown_start=DRYDOWN_START,
        drydown_end=DRYDOWN_END,
        reflood_date=REFLOOD_DATE,
    )
    if baseline_adjustments:
        raise ValueError("Baseline unexpectedly contains external water adjustments")
    baseline_season = summarize(baseline_rows, params)
    baseline_ch4 = sum(row["ch4_kg_C_ha"] for row in baseline_season)
    summaries = []
    daily = [
        {"task": task_name, "scenario": "baseline", **row}
        for row in baseline_season
    ]
    adjustments = []

    for scenario, scenario_spec in SCENARIO_SPECS.items():
        drydown_start = scenario_spec["drydown_start"]
        drydown_end = scenario_spec["drydown_end"]
        reflood_date = scenario_spec["reflood_date"]
        target_water_ratios = scenario_spec["target_water_ratios"]
        water_intervention = scenario_spec["water_intervention"]
        treatment_spec = json.loads(json.dumps(spec))
        treatment_spec["rice"]["interruptions"] = [
            [drydown_start, drydown_end]
        ]
        treatment_events = build_events(treatment_spec, "one_interruption")
        treatment_rows, scenario_adjustments = run_segmented_scenario(
            binary,
            source,
            task_output,
            scenario,
            initial_restart,
            climate,
            treatment_events,
            params,
            water_intervention=water_intervention,
            drydown_start=drydown_start,
            drydown_end=drydown_end,
            reflood_date=reflood_date,
            target_water_ratios=target_water_ratios,
        )
        treatment_season = summarize(treatment_rows, params)
        baseline_dry = summarize(
            baseline_rows, params, drydown_start, drydown_end
        )
        treatment_dry = summarize(
            treatment_rows, params, drydown_start, drydown_end
        )
        baseline_dry_ch4 = sum(
            row["ch4_kg_C_ha"] for row in baseline_dry
        )
        treatment_by_year = {}
        for row in treatment_dry:
            treatment_by_year.setdefault(row["year"], []).append(row)
        days_below = {
            year: sum(row["reaches_f_anoxia"] for row in rows)
            for year, rows in treatment_by_year.items()
        }
        support = validate_output_support(
            baseline_rows, treatment_rows, drydown_start
        )
        drydown_days = (
            dt.date.fromisoformat(f"2000-{drydown_end}")
            - dt.date.fromisoformat(f"2000-{drydown_start}")
        ).days + 1
        if len(treatment_dry) != len(EVALUATION_YEARS) * drydown_days:
            raise ValueError(
                f"{scenario} dry-down summary does not have ten days per year"
            )
        if set(days_below) != set(EVALUATION_YEARS):
            raise ValueError(f"{scenario} does not cover every evaluation year")
        if scenario_spec["expected_threshold_crossing"]:
            if min(days_below.values()) < 1:
                raise ValueError(f"{scenario} did not reach fAnoxia")
        elif max(days_below.values()) != 0:
            raise ValueError(f"{scenario} unexpectedly reached fAnoxia")
        treatment_reflood = [
            row for row in treatment_season if row["date"][5:] == reflood_date
        ]
        if len(treatment_reflood) != len(EVALUATION_YEARS):
            raise ValueError(f"{scenario} lacks one reflood date per year")
        if min(row["minimum_water_ratio"] for row in treatment_reflood) <= 1.0:
            raise ValueError(f"{scenario} did not return above water-holding capacity")

        treatment_ch4 = sum(row["ch4_kg_C_ha"] for row in treatment_season)
        treatment_dry_ch4 = sum(row["ch4_kg_C_ha"] for row in treatment_dry)
        summaries.append(
            {
                "task": task_name,
                "scenario": scenario,
                "site_id": task_name.split("_")[0],
                "prep_years": int(task_name.split("prep")[1]),
                "water_intervention": water_intervention,
                "drydown_start": drydown_start,
                "drydown_end": drydown_end,
                "reflood_date": reflood_date,
                "soil_whc_cm": params["soilWHC"],
                "f_anoxia": params["fAnoxia"],
                "anaerobic_transition_exponent": params["anaerobicTransExp"],
                "minimum_treatment_water_ratio": min(
                    row["minimum_water_ratio"] for row in treatment_dry
                ),
                "years_reaching_f_anoxia": sum(
                    value > 0 for value in days_below.values()
                ),
                "minimum_days_at_or_below_f_anoxia_per_year": min(
                    days_below.values()
                ),
                "maximum_days_at_or_below_f_anoxia_per_year": max(
                    days_below.values()
                ),
                "minimum_reflood_water_ratio": min(
                    row["minimum_water_ratio"] for row in treatment_reflood
                ),
                **support,
                "seasonal_ch4_baseline_kg_C_ha": baseline_ch4,
                "seasonal_ch4_treatment_kg_C_ha": treatment_ch4,
                "seasonal_ch4_ratio": treatment_ch4 / baseline_ch4,
                "drydown_ch4_baseline_kg_C_ha": baseline_dry_ch4,
                "drydown_ch4_treatment_kg_C_ha": treatment_dry_ch4,
                "drydown_ch4_ratio": treatment_dry_ch4 / baseline_dry_ch4,
                "total_external_water_removed_cm": -sum(
                    min(0.0, row["external_water_change_cm"])
                    for row in scenario_adjustments
                ),
                "total_external_reflood_water_added_cm": sum(
                    max(0.0, row["external_water_change_cm"])
                    for row in scenario_adjustments
                    if row["operation"] == "reflood"
                ),
                "maximum_single_external_water_removal_cm": -min(
                    row["external_water_change_cm"]
                    for row in scenario_adjustments
                ),
            }
        )
        daily.extend(
            {"task": task_name, "scenario": scenario, **row}
            for row in treatment_season
        )
        adjustments.extend(scenario_adjustments)
    return (
        summaries,
        daily,
        adjustments,
        audit_logs(task_output, task_name),
        methane_window_bounds(task_name, baseline_season),
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"Output already exists: {args.output}")
    args.output.mkdir(parents=True)

    spec_path = Path(__file__).parent / "pilot_spec.json"
    spec = json.loads(spec_path.read_text())
    summaries = []
    daily = []
    adjustments = []
    log_audits = []
    window_bounds = []
    inputs = []
    for task_name in TASKS:
        (
            task_summaries,
            task_daily,
            task_adjustments,
            task_log_audits,
            task_window_bounds,
        ) = run_task(
            args.binary, args.workspace, args.output, task_name, spec
        )
        summaries.extend(task_summaries)
        daily.extend(task_daily)
        adjustments.extend(task_adjustments)
        log_audits.extend(task_log_audits)
        window_bounds.extend(task_window_bounds)
        source = args.workspace / task_name
        inputs.append(
            {
                "task": task_name,
                "parameters_sha256": sha256(source / "sipnet.param"),
                "config_sha256": sha256(source / "sipnet.in"),
                "weather_sha256": sha256(source / "evaluation.clim"),
                "restart_sha256": sha256(source / "preparation" / "baseline.restart"),
            }
        )

    write_csv(args.output / "forced_drydown_summary.csv", summaries)
    write_csv(args.output / "forced_drydown_daily.csv", daily)
    write_csv(
        args.output / "forced_drydown_trajectory.csv", compact_trajectory(daily)
    )
    write_csv(args.output / "forced_water_adjustments.csv", adjustments)
    write_csv(args.output / "forced_drydown_log_audit.csv", log_audits)
    write_csv(args.output / "methane_window_upper_bounds.csv", window_bounds)
    write_csv(
        args.output / "natural_drydown_gap.csv",
        natural_drydown_gaps(summaries, daily),
    )
    provenance = {
        "status": "local drainage and state-forcing diagnostics; not a validated hydrology simulation",
        "sipnet_revision": "3ccc41c1ad2db426b7eb857881a32ca685bf57f1",
        "sipnet_version": "2.2.0",
        "binary_sha256": sha256(args.binary),
        "script_sha256": sha256(__file__),
        "pilot_spec_sha256": sha256(spec_path),
        "planting_date": PLANTING_DATE,
        "drydown_start": DRYDOWN_START,
        "drydown_end": DRYDOWN_END,
        "reflood_date": REFLOOD_DATE,
        "target_water_ratio_schedules": TARGET_SCHEDULES,
        "scenario_timing": {
            scenario: {
                "drydown_start": scenario_spec["drydown_start"],
                "drydown_end": scenario_spec["drydown_end"],
                "reflood_date": scenario_spec["reflood_date"],
            }
            for scenario, scenario_spec in SCENARIO_SPECS.items()
        },
        "scenario_water_intervention": {
            scenario: scenario_spec["water_intervention"]
            for scenario, scenario_spec in SCENARIO_SPECS.items()
        },
        "reflood_depth_cm": REFLOOD_DEPTH_CM,
        "water_accounting": "Restart-state water changes are external prescribed adjustments and are reported separately from SIPNET fluxes.",
        "natural_drydown_gap_calculation": {
            "initial_ratio_after_one_time_drain": 1.0,
            "severe_field_target_ratio": 0.25,
            "net_storage_loss_cm": "soilWHC * (initial ratio - daily minimum endpoint ratio)",
            "interpretation": "Net modeled storage change after the one-time drain; it is not a partitioned evaporation, transpiration, precipitation, and drainage budget.",
        },
        "support_contract": {
            "evaluation_days": EXPECTED_DAYS,
            "timesteps_per_day": EXPECTED_TIMESTEPS_PER_DAY,
            "rows_per_scenario": EXPECTED_ROWS,
            "baseline_treatment_time_support_identical": True,
            "initial_pre_treatment_rows_identical": True,
        },
        "scenario_interpretation": {
            "field_reference_drydown": "Primary California field-reference diagnostic. The 0.595 target and realized minima are checked against the SSURGO-normalized available-water range from Carrijo et al. (2018).",
            "threshold_stress_drydown": "California-timed severe-stress diagnostic retained to isolate endpoint effects. It crosses fAnoxia but combines California timing with a severity not observed in the California comparator.",
            "reproductive_severe_field_drydown": "Calendar-matched severe-field diagnostic. Its July 15-24 dry-down starts 61 days after planting and lasts 10 days, within the first-cycle field ranges of 57-66 days after sowing and 7-13 days from drain to reflood. The endpoint schedule is prescribed because the one-time-drain comparator does not realize the observed severity.",
            "reproductive_one_time_drain": "Process-oriented comparator. It removes water above soilWHC once at the start, omits irrigation for the observed-length dry interval, and then lets SIPNET evaporation and transpiration determine the trajectory until reflooding.",
        },
        "log_audit_interpretation": "Recurring harvest-date nitrogen-balance warnings occur in baseline and all four treatment runs; zero SIPNET error lines were observed.",
        "severe_field_comparator": {
            "source": "https://www.ars.usda.gov/research/publications/publication/?seqNo115=370626",
            "sowing_date": "May 9 in 2017 and 2018",
            "first_cycle_dates": {
                "2017": {"drain": "July 14", "reflood": "July 21-24"},
                "2018": {"drain": "July 5", "reflood": "July 17-18"},
            },
            "first_cycle_start_days_after_sowing": [57, 66],
            "first_cycle_duration_days": [7, 13],
            "reported_minimum_timing": "approximately 10 and 13 weeks after emergence",
            "reported_vwc_range": [0.15, 0.20],
            "use": "External endpoint, calendar, and phenology comparator; exact emergence date and plot coordinate are unavailable.",
        },
        "field_window_comparator": {
            "source": "https://doi.org/10.1016/j.fcr.2021.108312",
            "start_days_after_planting": [34, 49],
            "durations_days": list(FIELD_WINDOW_DURATIONS),
            "reported_seasonal_ch4_reduction_percent": [38, 66],
            "use": "External comparison only; not a calibration target or validation dataset.",
        },
        "inputs": inputs,
    }
    (args.output / "forced_drydown_provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n"
    )
    print(json.dumps(summaries, indent=2))


if __name__ == "__main__":
    main()
