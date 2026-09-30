import math
from pathlib import Path
import unittest

from rice_drydown_diagnostics import (
    anaerobic_index,
    methane_moisture_multiplier,
    required_residual_vwc,
    validate_frozen_results,
)


class TestRiceDrydownDiagnostics(unittest.TestCase):
    def test_methane_moisture_endpoints(self):
        f_anoxia = 0.286236668022783
        exponent = 99.98298
        self.assertEqual(anaerobic_index(1.2, f_anoxia), 1.0)
        self.assertEqual(methane_moisture_multiplier(1.0, f_anoxia, exponent), 1.0)
        self.assertEqual(methane_moisture_multiplier(f_anoxia, f_anoxia, exponent), 0.0)
        self.assertEqual(methane_moisture_multiplier(0.2, f_anoxia, exponent), 0.0)

    def test_near_saturation_response_is_sharp(self):
        multiplier = methane_moisture_multiplier(0.99, 0.286236668022783, 99.98298)
        self.assertTrue(math.isclose(multiplier, 0.24397452380096862, rel_tol=1e-12))

    def test_soil_rice_posterior_comparator_is_less_sharp(self):
        source = methane_moisture_multiplier(0.99, 0.286236668022783, 99.98298)
        comparator = methane_moisture_multiplier(
            0.99,
            0.286236668022783,
            9.97418245481472,
        )
        self.assertGreater(comparator, source)
        self.assertLess(comparator, 1.0)

    def test_field_vwc_mapping_requires_explicit_residual(self):
        f_anoxia = 0.286236668022783
        self.assertGreater(0.24 / 0.50, f_anoxia)
        residual = required_residual_vwc(0.24, 0.50, f_anoxia)
        mapped = (0.24 - residual) / (0.50 - residual)
        self.assertTrue(math.isclose(mapped, f_anoxia, rel_tol=1e-12))

    def test_frozen_followup_results(self):
        validate_frozen_results(Path(__file__).parent / "results")


if __name__ == "__main__":
    unittest.main()
