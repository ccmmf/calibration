import json
from pathlib import Path
import unittest
from prepare_pilot import calendar, doy

SPEC = json.loads((Path(__file__).parent/'pilot_spec.json').read_text())

class TestCalendar(unittest.TestCase):
    def test_no_change_control(self):
        for system in ['annual','rice']:
            for year in range(2000,2024):
                self.assertEqual(calendar(SPEC,system,year,'baseline'), calendar(SPEC,system,year,'no_change'))

    def test_irrigation_is_only_rice_change(self):
        for year in [2016,2017]:
            base=calendar(SPEC,'rice',year,'baseline')
            for variant,n in [('one_interruption',14),('two_interruptions',28)]:
                treatment=calendar(SPEC,'rice',year,variant)
                self.assertEqual(len(base)-len(treatment),n)
                self.assertTrue(all(' irrig ' in x for x in set(base)-set(treatment)))
                self.assertEqual(set(treatment)-set(base),set())

    def test_cover_keeps_cash_management(self):
        for year in [2016,2017]:
            base=calendar(SPEC,'annual',year,'baseline')
            treatment=calendar(SPEC,'annual',year,'cover')
            self.assertTrue(set(base).issubset(set(treatment)))
            extra=set(treatment)-set(base)
            self.assertEqual(len(extra),1 if year==2016 else 3)
            self.assertFalse(any(' fert ' in x or ' irrig ' in x or ' till ' in x for x in extra))

    def test_planting_has_required_live_pools(self):
        for system in ['annual', 'rice']:
            values = SPEC[system]['cash_plant_C_g_m2']
            self.assertGreater(values[1], 0)
            self.assertGreater(values[2]+values[3], 0)
        values = SPEC['annual']['cover_plant_C_g_m2']
        self.assertGreater(values[1], 0)
        self.assertGreater(values[2]+values[3], 0)

    def test_order_and_leap_dates(self):
        self.assertEqual(doy(2016,'05-01'),doy(2017,'05-01')+1)
        for system in ['annual','rice']:
            for variant in SPEC[system]['variants']:
                for year in range(2016,2024):
                    days=[int(x.split()[1]) for x in calendar(SPEC,system,year,variant)]
                    self.assertEqual(days,sorted(days))

if __name__=='__main__': unittest.main()
