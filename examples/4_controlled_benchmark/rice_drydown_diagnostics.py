"""Validate the frozen local rice dry-down and methane-response diagnostics."""

import csv
import json
import math
from pathlib import Path


def anaerobic_index(water_ratio, f_anoxia):
    """Return SIPNET's clipped anaerobic index for soil water / holding capacity."""
    clipped_water = min(1.0, max(0.0, water_ratio))
    return min(1.0, max(0.0, (clipped_water - f_anoxia) / (1.0 - f_anoxia)))


def methane_moisture_multiplier(water_ratio, f_anoxia, exponent):
    """Return SIPNET's methane moisture multiplier, A ** anaerobicTransExp."""
    return anaerobic_index(water_ratio, f_anoxia) ** exponent


def required_residual_vwc(dry_vwc, flood_vwc, f_anoxia):
    """Residual VWC that maps a field endpoint to fAnoxia as available water."""
    return (dry_vwc - f_anoxia * flood_vwc) / (1.0 - f_anoxia)


def read_rows(path):
    with Path(path).open(newline="") as stream:
        return list(csv.DictReader(stream))


def validate_frozen_results(results_dir):
    """Check the evidence contracts used by the rice dry-down follow-up note."""
    results_dir = Path(results_dir)
    candidates = read_rows(results_dir / "rice_drydown_followup.csv")
    curve = read_rows(results_dir / "methane_moisture_response.csv")
    forced = read_rows(results_dir / "forced_drydown_summary.csv")
    trajectory = read_rows(results_dir / "forced_drydown_trajectory.csv")
    water_adjustments = read_rows(results_dir / "forced_water_adjustments.csv")
    log_audit = read_rows(results_dir / "forced_drydown_log_audit.csv")
    window_bounds = read_rows(results_dir / "methane_window_upper_bounds.csv")
    natural_gaps = read_rows(results_dir / "natural_drydown_gap.csv")
    exponent_audit = read_rows(results_dir / "anaerobic_exponent_audit.csv")
    moisture_mapping = read_rows(results_dir / "field_moisture_mapping.csv")
    site_soil_mapping = read_rows(
        results_dir / "site_soil_hydraulic_mapping.csv"
    )
    field_site_soil_mapping = read_rows(
        results_dir / "field_site_soil_hydraulic_mapping.csv"
    )
    field_severity_comparators = read_rows(
        results_dir / "field_severity_comparators.csv"
    )
    provenance = json.loads(
        (results_dir / "forced_drydown_provenance.json").read_text()
    )
    exponent_provenance = json.loads(
        (results_dir / "anaerobic_exponent_audit_provenance.json").read_text()
    )
    moisture_provenance = json.loads(
        (results_dir / "field_moisture_mapping_provenance.json").read_text()
    )
    site_soil_provenance = json.loads(
        (results_dir / "site_soil_hydraulic_mapping_provenance.json").read_text()
    )
    field_severity_provenance = json.loads(
        (results_dir / "field_severity_comparators_provenance.json").read_text()
    )

    by_key = {(row["site_id"], row["candidate"]): row for row in candidates}
    for site_id in ("413887", "535358"):
        source = by_key[(site_id, "source_14_day")]
        rapid = by_key[(site_id, "rapid_drain_14_day")]
        full = by_key[(site_id, "rapid_drain_full_season")]
        assert int(source["years_reaching_f_anoxia"]) == 0
        assert math.isclose(float(source["seasonal_ch4_ratio"]), 1.0, rel_tol=1e-4)
        assert int(rapid["years_reaching_f_anoxia"]) == 0
        assert float(rapid["seasonal_ch4_ratio"]) < 0.9
        assert int(full["years_reaching_f_anoxia"]) == 8
        assert float(full["seasonal_ch4_ratio"]) < 0.02

    for row in curve:
        expected = methane_moisture_multiplier(
            float(row["initial_water_ratio"]),
            float(row["f_anoxia"]),
            float(row["anaerobic_transition_exponent"]),
        )
        assert math.isclose(
            expected,
            float(row["expected_moisture_multiplier"]),
            rel_tol=1e-12,
            abs_tol=1e-15,
        )

    expected_tasks = {
        "413887_prep8",
        "413887_prep16",
        "535358_prep8",
        "535358_prep16",
    }
    expected_scenarios = {
        "field_reference_drydown",
        "threshold_stress_drydown",
        "reproductive_severe_field_drydown",
        "reproductive_one_time_drain",
    }
    expected_timing = {
        "field_reference_drydown": ("06-19", "06-28", "06-29"),
        "threshold_stress_drydown": ("06-19", "06-28", "06-29"),
        "reproductive_severe_field_drydown": ("07-15", "07-24", "07-25"),
        "reproductive_one_time_drain": ("07-15", "07-24", "07-25"),
    }
    expected_water_interventions = {
        "field_reference_drydown": "prescribed_trajectory",
        "threshold_stress_drydown": "prescribed_trajectory",
        "reproductive_severe_field_drydown": "prescribed_trajectory",
        "reproductive_one_time_drain": "initial_drain_only",
    }
    assert {(row["task"], row["scenario"]) for row in forced} == {
        (task, scenario)
        for task in expected_tasks
        for scenario in expected_scenarios
    }
    adjustments_by_key = {}
    for row in water_adjustments:
        adjustments_by_key.setdefault(
            (row["task"], row["scenario"]), []
        ).append(row)
    assert set(adjustments_by_key) == {
        (task, scenario)
        for task in expected_tasks
        for scenario in expected_scenarios
    }
    for row in forced:
        assert (
            row["drydown_start"],
            row["drydown_end"],
            row["reflood_date"],
        ) == expected_timing[row["scenario"]]
        assert row["water_intervention"] == expected_water_interventions[
            row["scenario"]
        ]
        if row["scenario"] == "field_reference_drydown":
            assert int(row["years_reaching_f_anoxia"]) == 0
            assert int(row["minimum_days_at_or_below_f_anoxia_per_year"]) == 0
            assert int(row["maximum_days_at_or_below_f_anoxia_per_year"]) == 0
            assert 0.475 <= float(row["minimum_treatment_water_ratio"]) <= 0.596
        elif row["scenario"] == "reproductive_one_time_drain":
            assert int(row["years_reaching_f_anoxia"]) == 0
            assert int(row["minimum_days_at_or_below_f_anoxia_per_year"]) == 0
            assert int(row["maximum_days_at_or_below_f_anoxia_per_year"]) == 0
            assert 0.697 <= float(row["minimum_treatment_water_ratio"]) <= 0.839
        else:
            assert int(row["years_reaching_f_anoxia"]) == 8
            assert int(row["minimum_days_at_or_below_f_anoxia_per_year"]) == 2
            assert int(row["maximum_days_at_or_below_f_anoxia_per_year"]) == 2
            assert float(row["minimum_treatment_water_ratio"]) <= float(
                row["f_anoxia"]
            )
        assert float(row["minimum_reflood_water_ratio"]) > 1.0
        assert int(row["evaluation_days"]) == 2922
        assert int(row["timesteps_per_day"]) == 8
        assert int(row["rows_per_scenario"]) == 23376
        assert row["time_support_identical"] == "True"
        assert row["initial_pre_treatment_rows_identical"] == "True"
        assert float(row["seasonal_ch4_ratio"]) < 0.92
        assert float(row["drydown_ch4_ratio"]) < 0.06
        assert float(row["total_external_water_removed_cm"]) > 0
        assert float(row["maximum_single_external_water_removal_cm"]) > 14
        adjustments = adjustments_by_key[(row["task"], row["scenario"])]
        expected_adjustments = (
            16 if row["scenario"] == "reproductive_one_time_drain" else 88
        )
        assert len(adjustments) == expected_adjustments
        changes = [float(item["external_water_change_cm"]) for item in adjustments]
        removal = -sum(min(0.0, value) for value in changes)
        reflood = sum(
            max(0.0, float(item["external_water_change_cm"]))
            for item in adjustments
            if item["operation"] == "reflood"
        )
        assert math.isclose(
            removal,
            float(row["total_external_water_removed_cm"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            reflood,
            float(row["total_external_reflood_water_added_cm"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            -min(changes),
            float(row["maximum_single_external_water_removal_cm"]),
            rel_tol=1e-12,
        )

    trajectory_by_task = {}
    for row in trajectory:
        trajectory_by_task.setdefault(
            (row["task"], row["scenario"]), []
        ).append(row)
    assert set(trajectory_by_task) == {
        (task, scenario)
        for task in expected_tasks
        for scenario in expected_scenarios
    }
    for (task, scenario), rows in trajectory_by_task.items():
        rows.sort(key=lambda row: row["month_day"])
        if scenario in (
            "reproductive_severe_field_drydown",
            "reproductive_one_time_drain",
        ):
            expected_dates = [
                "07-15",
                "07-16",
                "07-17",
                "07-18",
                "07-19",
                "07-20",
                "07-21",
                "07-22",
                "07-23",
                "07-24",
                "07-25",
            ]
        else:
            expected_dates = [
                "06-19",
                "06-20",
                "06-21",
                "06-22",
                "06-23",
                "06-24",
                "06-25",
                "06-26",
                "06-27",
                "06-28",
                "06-29",
            ]
        assert [row["month_day"] for row in rows] == expected_dates
        drydown = rows[:-1]
        minimum_ratios = [float(row["minimum_water_ratio"]) for row in drydown]
        assert all(right <= left for left, right in zip(minimum_ratios, minimum_ratios[1:]))
        assert minimum_ratios[0] < 1.0
        if scenario == "field_reference_drydown":
            assert 0.475 <= minimum_ratios[-1] <= 0.596
        elif scenario == "reproductive_one_time_drain":
            assert 0.697 <= minimum_ratios[-1] <= 0.839
        else:
            assert minimum_ratios[-1] <= 0.286236668022783
        daily_ch4 = [float(row["mean_daily_ch4_kg_C_ha"]) for row in drydown]
        if scenario == "reproductive_one_time_drain":
            assert all(
                right <= left for left, right in zip(daily_ch4, daily_ch4[1:])
            )
            assert daily_ch4[0] > 0.0
            assert daily_ch4[-1] == 0.0
        else:
            assert all(value == 0.0 for value in daily_ch4[1:])
        assert float(rows[-1]["minimum_water_ratio"]) > 1.0

    audit_by_key = {(row["task"], row["scenario"]): row for row in log_audit}
    assert set(task for task, _ in audit_by_key) == expected_tasks
    for task in expected_tasks:
        baseline = audit_by_key[(task, "baseline")]
        treatments = [
            audit_by_key[(task, scenario)] for scenario in expected_scenarios
        ]
        for row in (baseline, *treatments):
            assert int(row["log_files"]) == 96
            assert int(row["error_lines"]) == 0
            assert int(row["carbon_balance_warnings"]) == 0
            assert int(row["nitrogen_balance_warnings"]) == 8
        assert all(
            baseline["maximum_absolute_nitrogen_delta"]
            == treatment["maximum_absolute_nitrogen_delta"]
            for treatment in treatments
        )

    bounds_by_task = {}
    for row in window_bounds:
        bounds_by_task.setdefault(row["task"], []).append(row)
    assert set(bounds_by_task) == expected_tasks
    for rows in bounds_by_task.values():
        rows.sort(key=lambda row: int(row["duration_days"]))
        assert [int(row["duration_days"]) for row in rows] == [5, 8, 10, 12]
        shares = [float(row["maximum_baseline_seasonal_ch4_share"]) for row in rows]
        assert all(right > left for left, right in zip(shares, shares[1:]))
        assert shares[-1] < 0.115
        assert all(34 <= int(row["best_start_dap"]) <= 49 for row in rows)

    assert {row["task"] for row in natural_gaps} == expected_tasks
    for row in natural_gaps:
        assert int(row["drydown_days"]) == 10
        assert int(row["years"]) == 8
        endpoint_ratio = float(row["minimum_endpoint_water_ratio"])
        maximum_loss = 12.0 * (1.0 - endpoint_ratio)
        assert math.isclose(
            maximum_loss,
            float(row["maximum_net_storage_loss_cm"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            float(row["required_net_storage_loss_to_ratio_0_25_cm"]),
            9.0,
            rel_tol=1e-12,
        )
        assert math.isclose(
            float(row["required_mean_daily_loss_to_ratio_0_25_cm"]),
            0.9,
            rel_tol=1e-12,
        )
        assert math.isclose(
            float(row["required_to_realized_loss_factor"]),
            9.0 / maximum_loss,
            rel_tol=1e-12,
        )
        assert float(row["required_to_realized_loss_factor"]) > 2.4
        evapotranspiration = float(row["mean_daily_evapotranspiration_cm"])
        transpiration = float(row["mean_daily_transpiration_cm"])
        assert 0.0 < transpiration < evapotranspiration < 0.3
        assert math.isclose(
            transpiration / evapotranspiration,
            float(row["transpiration_fraction_of_evapotranspiration"]),
            rel_tol=1e-12,
        )
        assert 0.0 < float(row["minimum_lai"])
        assert float(row["maximum_lai"]) < 0.08

    exponent_by_key = {
        (row["task"], row["parameter_case"]): row for row in exponent_audit
    }
    expected_cases = {
        "source_run",
        "soil_rice_posterior_median_comparator",
    }
    assert set(exponent_by_key) == {
        (task, case) for task in expected_tasks for case in expected_cases
    }
    for task in expected_tasks:
        source = exponent_by_key[(task, "source_run")]
        comparator = exponent_by_key[
            (task, "soil_rice_posterior_median_comparator")
        ]
        assert math.isclose(
            float(source["anaerobic_transition_exponent"]),
            99.98298,
            rel_tol=1e-12,
        )
        assert math.isclose(
            float(comparator["anaerobic_transition_exponent"]),
            9.97418245481472,
            rel_tol=1e-12,
        )
        assert float(source["drydown_ch4_ratio"]) < 0.05
        assert 0.11 < float(comparator["drydown_ch4_ratio"]) < 0.12
        assert float(source["drydown_ch4_ratio"]) < float(
            comparator["drydown_ch4_ratio"]
        )
        assert float(source["seasonal_ch4_ratio"]) < float(
            comparator["seasonal_ch4_ratio"]
        )
        assert 0.088 < float(comparator["seasonal_ch4_reduction_fraction"]) < 0.101

    assert {row["field_class"] for row in moisture_mapping} == {
        "AWD25",
        "AWD35",
        "AWD_safe",
    }
    for row in moisture_mapping:
        dry_min = float(row["dry_vwc_min_fraction"])
        dry_max = float(row["dry_vwc_max_fraction"])
        flood_min = float(row["flood_vwc_min_fraction"])
        flood_max = float(row["flood_vwc_max_fraction"])
        ratio_min = dry_min / flood_max
        ratio_max = dry_max / flood_min
        residual_min = required_residual_vwc(dry_min, flood_max, 0.286236668022783)
        residual_max = required_residual_vwc(dry_max, flood_min, 0.286236668022783)
        assert math.isclose(
            ratio_min, float(row["zero_residual_ratio_min"]), rel_tol=1e-12
        )
        assert math.isclose(
            ratio_max, float(row["zero_residual_ratio_max"]), rel_tol=1e-12
        )
        assert math.isclose(
            residual_min,
            float(row["residual_vwc_for_f_anoxia_min_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            residual_max,
            float(row["residual_vwc_for_f_anoxia_max_fraction"]),
            rel_tol=1e-12,
        )
        assert ratio_min > 0.286236668022783

    assert {row["site_id"] for row in site_soil_mapping} == {
        "413887",
        "535358",
    }
    field_site = field_site_soil_mapping[0]
    assert len(field_site_soil_mapping) == 1
    assert field_site["study_site_id"] == "Carrijo_2018_Biggs"
    field_wilting = float(field_site["wilting_point_vwc_fraction"])
    field_awc = float(field_site["awc_fraction"])
    observed_ratio_min = (
        float(field_site["awd25_observed_vwc_min_fraction"]) - field_wilting
    ) / field_awc
    observed_ratio_max = (
        float(field_site["awd25_observed_vwc_max_fraction"]) - field_wilting
    ) / field_awc
    assert math.isclose(
        observed_ratio_min,
        float(field_site["awd25_available_water_ratio_min"]),
        rel_tol=1e-12,
    )
    assert math.isclose(
        observed_ratio_max,
        float(field_site["awd25_available_water_ratio_max"]),
        rel_tol=1e-12,
    )
    assert math.isclose(observed_ratio_min, 0.46875, rel_tol=1e-12)
    assert math.isclose(observed_ratio_max, 0.71875, rel_tol=1e-12)

    severity_by_key = {
        (row["study_id"], row["treatment"]): row
        for row in field_severity_comparators
    }
    assert set(severity_by_key) == {
        ("Carrijo_2018", "AWD25"),
        ("Fernandez-Baca_2021", "AWD30"),
        ("Gealy_2021", "Low"),
        ("Gealy_2021", "Medium"),
        ("Gealy_2021", "High"),
    }
    arkansas_wilting = 0.129
    arkansas_awc = 0.18
    for treatment, endpoint in (("Low", 0.30), ("Medium", 0.21), ("High", 0.15)):
        row = severity_by_key[("Gealy_2021", treatment)]
        available_ratio = (endpoint - arkansas_wilting) / arkansas_awc
        assert math.isclose(
            available_ratio,
            float(row["available_water_ratio_min"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            available_ratio,
            float(row["available_water_ratio_max"]),
            rel_tol=1e-12,
        )
    gealy_medium = float(
        severity_by_key[("Gealy_2021", "Medium")]["available_water_ratio_min"]
    )
    gealy_high = float(
        severity_by_key[("Gealy_2021", "High")]["available_water_ratio_min"]
    )
    assert gealy_high < 0.25 < 0.286236668022783 < gealy_medium
    assert severity_by_key[("Gealy_2021", "High")][
        "endpoint_reaches_f_anoxia"
    ] == "True"
    assert all(
        row["endpoint_reaches_f_anoxia"] == "False"
        for key, row in severity_by_key.items()
        if key != ("Gealy_2021", "High")
    )
    assert math.isclose(
        arkansas_wilting + 0.286236668022783 * arkansas_awc,
        field_severity_provenance["calculations"]["f_anoxia_vwc_at_arkansas_site"],
        rel_tol=1e-12,
    )
    assert math.isclose(
        arkansas_wilting + 0.25 * arkansas_awc,
        field_severity_provenance["calculations"]["current_target_vwc_at_arkansas_site"],
        rel_tol=1e-12,
    )
    for row in site_soil_mapping:
        saturation = float(row["satiated_vwc_fraction"])
        wilting = float(row["wilting_point_vwc_fraction"])
        awc = float(row["awc_fraction"])
        f_anoxia = float(row["f_anoxia"])
        threshold_vwc = wilting + f_anoxia * awc
        stress_vwc = wilting + float(row["threshold_stress_target_ratio"]) * awc
        field_reference_vwc = wilting + float(
            row["realized_field_reference_min_ratio"]
        ) * awc
        realized_stress_vwc = wilting + float(
            row["realized_threshold_stress_min_ratio"]
        ) * awc
        realized_reproductive_stress_vwc = wilting + float(
            row["realized_reproductive_stress_min_ratio"]
        ) * awc
        realized_one_time_drain_vwc = wilting + float(
            row["realized_one_time_drain_min_ratio"]
        ) * awc
        assert math.isclose(
            threshold_vwc,
            float(row["f_anoxia_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            stress_vwc,
            float(row["threshold_stress_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            field_reference_vwc,
            float(row["realized_field_reference_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            realized_stress_vwc,
            float(row["realized_threshold_stress_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            realized_reproductive_stress_vwc,
            float(row["realized_reproductive_stress_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            realized_one_time_drain_vwc,
            float(row["realized_one_time_drain_vwc_available_fraction"]),
            rel_tol=1e-12,
        )
        assert threshold_vwc > wilting
        assert stress_vwc > wilting
        assert realized_stress_vwc > wilting
        assert realized_reproductive_stress_vwc > wilting
        assert realized_one_time_drain_vwc > threshold_vwc
        assert row["threshold_stress_above_wilting"] == "True"
        assert observed_ratio_min <= float(
            row["realized_field_reference_min_ratio"]
        ) <= observed_ratio_max
        assert math.isclose(
            12.0 / awc,
            float(row["implied_depth_if_whc_is_awc_cm"]),
            rel_tol=1e-12,
        )
        zero_based_threshold = f_anoxia * saturation
        zero_based_stress = float(row["threshold_stress_target_ratio"]) * saturation
        assert math.isclose(
            zero_based_threshold,
            float(row["f_anoxia_vwc_zero_based_saturation_fraction"]),
            rel_tol=1e-12,
        )
        assert math.isclose(
            zero_based_stress,
            float(row["threshold_stress_vwc_zero_based_saturation_fraction"]),
            rel_tol=1e-12,
        )
        assert zero_based_threshold < wilting
        assert zero_based_stress < wilting
        assert row["zero_based_threshold_below_wilting"] == "True"

    assert provenance["status"] == (
        "local drainage and state-forcing diagnostics; not a validated hydrology simulation"
    )
    assert provenance["support_contract"] == {
        "evaluation_days": 2922,
        "timesteps_per_day": 8,
        "rows_per_scenario": 23376,
        "baseline_treatment_time_support_identical": True,
        "initial_pre_treatment_rows_identical": True,
    }
    assert provenance["target_water_ratio_schedules"] == {
        "field_reference_drydown": [
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
        ],
        "threshold_stress_drydown": [
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
        ],
        "reproductive_severe_field_drydown": [
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
        ],
    }
    assert provenance["scenario_timing"] == {
        scenario: {
            "drydown_start": timing[0],
            "drydown_end": timing[1],
            "reflood_date": timing[2],
        }
        for scenario, timing in expected_timing.items()
    }
    assert provenance["scenario_water_intervention"] == expected_water_interventions
    assert provenance["natural_drydown_gap_calculation"] == {
        "initial_ratio_after_one_time_drain": 1.0,
        "severe_field_target_ratio": 0.25,
        "net_storage_loss_cm": (
            "soilWHC * (initial ratio - daily minimum endpoint ratio)"
        ),
        "interpretation": (
            "Net modeled storage change after the one-time drain; it is not a "
            "partitioned evaporation, transpiration, precipitation, and drainage "
            "budget."
        ),
    }
    assert provenance["severe_field_comparator"] == {
        "source": "https://www.ars.usda.gov/research/publications/publication/?seqNo115=370626",
        "sowing_date": "May 9 in 2017 and 2018",
        "first_cycle_dates": {
            "2017": {"drain": "July 14", "reflood": "July 21-24"},
            "2018": {"drain": "July 5", "reflood": "July 17-18"},
        },
        "first_cycle_start_days_after_sowing": [57, 66],
        "first_cycle_duration_days": [7, 13],
        "reported_minimum_timing": "approximately 10 and 13 weeks after emergence",
        "reported_vwc_range": [0.15, 0.2],
        "use": (
            "External endpoint, calendar, and phenology comparator; exact "
            "emergence date and plot coordinate are unavailable."
        ),
    }
    assert provenance["field_window_comparator"] == {
        "source": "https://doi.org/10.1016/j.fcr.2021.108312",
        "start_days_after_planting": [34, 49],
        "durations_days": [5, 8, 10, 12],
        "reported_seasonal_ch4_reduction_percent": [38, 66],
        "use": "External comparison only; not a calibration target or validation dataset.",
    }
    assert exponent_provenance["status"] == (
        "parameter-choice sensitivity; source-run pin verified; comparator not an accepted replacement"
    )
    assert exponent_provenance["source_run_parameter_choice"] == {
        "trait": "anaerobic_trans_exp",
        "sipnet_parameter": "anaerobicTransExp",
        "value": 99.98298,
        "classification": "fixed by experiment configuration; not fitted",
    }
    assert exponent_provenance["comparator"]["value"] == 9.97418245481472
    assert exponent_provenance["generation_contract"]["runner_commit"] == (
        "1332e63523fa32cfa2195e06a91b45e6265ba9a7"
    )
    assert exponent_provenance["execution"]["changed_input"] == (
        "anaerobicTransExp only"
    )
    assert moisture_provenance["status"] == (
        "field-source mapping diagnostic; not a site-specific SIPNET conversion"
    )
    assert moisture_provenance["field_source"]["doi"] == (
        "https://doi.org/10.1016/j.fcr.2018.02.026"
    )
    assert moisture_provenance["model_source"]["missing_properties"] == [
        "configured modeled storage depth",
        "residual volumetric water content",
        "field-measured site-specific saturation or field-capacity water content",
        "run-time depth-resolved hydraulic properties",
    ]
    assert site_soil_provenance["status"] == (
        "soil-survey mapping diagnostic; supports physical plausibility but not field validation"
    )
    assert site_soil_provenance["soil_data_source"]["mapunit_result"] == [
        {"site_id": "413887", "mukey": "462117"},
        {"site_id": "535358", "mukey": "2766097"},
        {"site_id": "Carrijo_2018_Biggs", "mukey": "461191"},
    ]
    assert field_severity_provenance["status"] == (
        "cross-study field-severity evidence; not validation of the modeled sites or combined timing-and-severity scenario"
    )
    assert field_severity_provenance["arkansas_soil_mapping"]["mapunit_result"] == {
        "mukey": "579269",
        "mapunit_name": "Dewitt silt loam, 0 to 1 percent slopes",
    }
    severity_sources = {
        source["study_id"]: source
        for source in field_severity_provenance["sources"]
    }
    assert severity_sources["Gealy_2021"]["calendar_record"] == (
        "https://www.ars.usda.gov/research/publications/publication/?seqNo115=370626"
    )
    assert "57-66 days after sowing" in severity_sources["Gealy_2021"][
        "evidence"
    ]


if __name__ == "__main__":
    validate_frozen_results(Path(__file__).parent / "results")
    print("Rice dry-down follow-up diagnostics are internally consistent")
