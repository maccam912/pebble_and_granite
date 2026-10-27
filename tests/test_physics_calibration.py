"""Measurement gate tests; synthetic fixtures do not validate the physics."""
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('calibration', ROOT / 'tools/physics_calibration.py')
cal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cal)


class CalibrationTest(unittest.TestCase):
    def case(self, kind='measured'):
        return {'id': 'shot', 'source': {'kind': kind, 'reference': 'synthetic test fixture',
                'method': 'unit test, not real measurement', 'conditions': 'no obstacles'},
                'release': {'vy_mm_s': 2085, 'spin_milli_rps': -120},
                'observed': {'curl_mm': -900}, 'tolerance': {'curl_mm': 20}}

    def test_measurement_gate_requires_provenance_and_tolerances(self):
        case = self.case()
        cal.validate(case)
        case['source'].pop('reference')
        with self.assertRaises(ValueError): cal.validate(case)
        case = self.case()
        case['tolerance'] = {}
        with self.assertRaises(ValueError): cal.validate(case)
        case = self.case()
        case['initial'] = []
        with self.assertRaises(ValueError): cal.validate(case)

    def test_units_nan_and_boolean_are_rejected(self):
        for value in [True, float('nan'), float('inf'), '2085']:
            case = self.case()
            case['release']['vy_mm_s'] = value
            with self.assertRaises(ValueError): cal.validate(case)
        case = self.case()
        case['release']['spin_rad_s'] = .75
        with self.assertRaises(ValueError): cal.validate(case)
        self.assertEqual(cal.fixed(-120), -515396075)

    def test_synthetic_success_cannot_become_measured_success(self):
        metrics = {'curl_mm': -910}
        self.assertEqual(cal.compare(self.case('synthetic'), metrics, False)['status'], 'synthetic')
        self.assertEqual(cal.compare(self.case(), metrics, False)['status'], 'within_tolerance')
        self.assertEqual(cal.compare(self.case(), {'curl_mm': -930}, False)['status'], 'outside_tolerance')
        self.assertEqual(cal.compare(self.case(), metrics, True)['status'], 'truncated')

    def test_projection_and_boundary_exit(self):
        replay = {'release': {'stone': 0, 'pos': {'x': 0, 'y': cal.fixed(-28603)},
                              'vel': {'x': 0, 'y': cal.fixed(2000)}}}
        outcome = {'ticks': 6000, 'sim': {'stones': [{'id': 0, 'pos': {'x': cal.fixed(-900), 'y': 0}, 'turns': cal.fixed(-3000)}]}}
        values, truncated = cal.measure(replay, outcome)
        self.assertFalse(truncated)
        self.assertEqual(values, {'downrange_mm': 28603.0, 'curl_mm': -900.0, 'duration_ms': 25000.0, 'turns_milli': -3000.0})
        outcome['sim']['stones'][0]['pos']['y'] = cal.fixed(2000)
        self.assertTrue(cal.measure(replay, outcome)[1])

    def test_baseline_never_satisfies_check(self):
        # Exercise the real CLI boundary only when its native binary exists.
        server = cal.DEFAULT_SERVER
        if not server.exists(): self.skipTest('native binary not built')
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(cal.run(ROOT / 'validation/calibration/baseline.json', server,
                                     pathlib.Path(folder) / 'report.json', check=True), 2)


if __name__ == '__main__': unittest.main()
