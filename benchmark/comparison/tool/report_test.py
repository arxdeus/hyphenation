import copy
import math
import statistics
import unittest

import report


def measurement(values):
    return {'trials_ns': values, 'mean_ns': statistics.mean(values),
            'median_us': statistics.median(values) / 1000,
            'cv': statistics.stdev(values) / statistics.mean(values)}


class ReportTest(unittest.TestCase):
    def test_zero_variance_ratio_is_bounded(self):
        self.assertEqual(report.ratio_interval(measurement([20, 20]), measurement([10, 10])), (2, 2, 2))

    def test_interval_contains_known_proportional_ratio(self):
        ratio, low, high = report.ratio_interval(measurement([20, 22, 18, 20, 20]), measurement([10, 11, 9, 10, 10]))
        self.assertAlmostEqual(ratio, 2)
        self.assertLess(low, 2)
        self.assertGreater(high, 2)

    def test_unbounded_denominator_is_not_fabricated(self):
        ratio, low, high = report.ratio_interval(measurement([20, 20]), measurement([0.01, 100]))
        self.assertTrue(math.isfinite(ratio))
        self.assertIsNone(low)
        self.assertIsNone(high)

    def test_validation_recomputes_stats_from_raw_samples(self):
        suite = {'rows': [{'packages': {'a': measurement([10, 20, 30])}}]}
        report.validate(suite)
        wrong = copy.deepcopy(suite)
        wrong['rows'][0]['packages']['a']['median_us'] = 999
        with self.assertRaises(AssertionError):
            report.validate(wrong)

    def test_no_missing_or_nonfinite_trials(self):
        with self.assertRaises(ValueError):
            report.raw({'median_us': 1})
        with self.assertRaises(AssertionError):
            report.validate({'rows': [{'packages': {'a': {'trials_ns': [math.nan, 1]}}}]})


if __name__ == '__main__':
    unittest.main()
