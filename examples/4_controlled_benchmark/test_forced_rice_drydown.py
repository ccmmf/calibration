import datetime as dt
from pathlib import Path
import tempfile
import unittest

from run_forced_rice_drydown import (
    DRYDOWN_END,
    DRYDOWN_START,
    FIELD_REFERENCE_TARGET_WATER_RATIOS,
    INITIAL_DRAIN_ONLY,
    PRESCRIBED_TRAJECTORY,
    REFLOOD_DATE,
    REPRODUCTIVE_DRYDOWN_END,
    REPRODUCTIVE_DRYDOWN_START,
    REPRODUCTIVE_REFLOOD_DATE,
    SCENARIO_SPECS,
    THRESHOLD_STRESS_TARGET_WATER_RATIOS,
    natural_drydown_gaps,
    read_restart_value,
    replace_restart_value,
)


class TestForcedRiceDrydown(unittest.TestCase):
    def test_field_timing_contract(self):
        planting = dt.date.fromisoformat("2016-05-15")
        start = dt.date.fromisoformat(f"2016-{DRYDOWN_START}")
        end = dt.date.fromisoformat(f"2016-{DRYDOWN_END}")
        reflood = dt.date.fromisoformat(f"2016-{REFLOOD_DATE}")
        self.assertEqual((start - planting).days, 35)
        self.assertEqual((reflood - planting).days, 45)
        self.assertEqual((end - start).days + 1, 10)
        self.assertEqual(len(FIELD_REFERENCE_TARGET_WATER_RATIOS), 10)
        self.assertEqual(len(THRESHOLD_STRESS_TARGET_WATER_RATIOS), 10)

    def test_reproductive_field_timing_contract(self):
        planting = dt.date.fromisoformat("2016-05-15")
        start = dt.date.fromisoformat(f"2016-{REPRODUCTIVE_DRYDOWN_START}")
        end = dt.date.fromisoformat(f"2016-{REPRODUCTIVE_DRYDOWN_END}")
        reflood = dt.date.fromisoformat(f"2016-{REPRODUCTIVE_REFLOOD_DATE}")
        self.assertEqual((start - planting).days, 61)
        self.assertEqual((end - planting).days, 70)
        self.assertEqual((reflood - planting).days, 71)
        self.assertEqual((end - start).days + 1, 10)
        self.assertEqual(
            SCENARIO_SPECS["reproductive_severe_field_drydown"][
                "target_water_ratios"
            ],
            THRESHOLD_STRESS_TARGET_WATER_RATIOS,
        )
        self.assertEqual(
            SCENARIO_SPECS["reproductive_severe_field_drydown"][
                "water_intervention"
            ],
            PRESCRIBED_TRAJECTORY,
        )

    def test_one_time_drain_uses_model_evolved_drydown(self):
        spec = SCENARIO_SPECS["reproductive_one_time_drain"]
        self.assertEqual(spec["drydown_start"], REPRODUCTIVE_DRYDOWN_START)
        self.assertEqual(spec["drydown_end"], REPRODUCTIVE_DRYDOWN_END)
        self.assertEqual(spec["reflood_date"], REPRODUCTIVE_REFLOOD_DATE)
        self.assertEqual(spec["water_intervention"], INITIAL_DRAIN_ONLY)
        self.assertIsNone(spec["target_water_ratios"])
        self.assertFalse(spec["expected_threshold_crossing"])

    def test_natural_drydown_gap_uses_endpoint_storage_change(self):
        summaries = [
            {
                "task": "example_prep8",
                "scenario": "reproductive_one_time_drain",
                "site_id": "example",
                "prep_years": 8,
                "drydown_start": REPRODUCTIVE_DRYDOWN_START,
                "drydown_end": REPRODUCTIVE_DRYDOWN_END,
                "soil_whc_cm": 12.0,
            }
        ]
        daily = [
            {
                "task": "example_prep8",
                "scenario": "reproductive_one_time_drain",
                "date": f"{year}-{REPRODUCTIVE_DRYDOWN_END}",
                "minimum_water_ratio": 0.75,
                "evapotranspiration_cm": 0.2,
                "transpiration_cm": 0.05,
                "minimum_lai": 2.0,
                "maximum_lai": 3.0,
            }
            for year in range(2016, 2024)
        ]
        gap = natural_drydown_gaps(summaries, daily)[0]
        self.assertEqual(gap["maximum_net_storage_loss_cm"], 3.0)
        self.assertEqual(
            gap["required_net_storage_loss_to_ratio_0_25_cm"], 9.0
        )
        self.assertEqual(gap["required_to_realized_loss_factor"], 3.0)
        self.assertEqual(
            gap["transpiration_fraction_of_evapotranspiration"], 0.25
        )

    def test_field_and_threshold_schedules_have_distinct_endpoints(self):
        for schedule in (
            FIELD_REFERENCE_TARGET_WATER_RATIOS,
            THRESHOLD_STRESS_TARGET_WATER_RATIOS,
        ):
            self.assertEqual(schedule[0], 1.0)
            self.assertTrue(
                all(right <= left for left, right in zip(schedule, schedule[1:]))
            )
        self.assertGreater(
            FIELD_REFERENCE_TARGET_WATER_RATIOS[-1], 0.286236668022783
        )
        self.assertGreaterEqual(FIELD_REFERENCE_TARGET_WATER_RATIOS[-1], 0.48)
        self.assertLessEqual(FIELD_REFERENCE_TARGET_WATER_RATIOS[-1], 0.5958)
        self.assertLess(
            THRESHOLD_STRESS_TARGET_WATER_RATIOS[-1], 0.286236668022783
        )

    def test_restart_edit_is_surgical(self):
        source_text = "boundary.year 2015\nenvi.soilWater 17.5\nenvi.soilC 100\n"
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "source.restart"
            destination = Path(temp_dir) / "destination.restart"
            source.write_text(source_text)
            replace_restart_value(source, destination, "envi.soilWater", 3.0)
            self.assertEqual(read_restart_value(destination, "envi.soilWater"), 3.0)
            changed = destination.read_text()
            self.assertIn("boundary.year 2015", changed)
            self.assertIn("envi.soilC 100", changed)
            self.assertEqual(source.read_text(), source_text)


if __name__ == "__main__":
    unittest.main()
