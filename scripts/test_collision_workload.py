"""A collision demo must never silently share a default-scene benchmark."""
import unittest

from collision_workload import check_collision_workload


class CollisionWorkloadTests(unittest.TestCase):
    def test_explicit_modes(self):
        for mode, value in (('off', 0), ('on', 1)):
            self.assertIn(mode, check_collision_workload(
                f'PERF collision={value}\nPERF collision={value}', mode))

    def test_mixed_missing_and_invalid_modes_rejected(self):
        for text in ('PERF collision=0\nPERF collision=1',
                     'PERF collision=0\nPERF fps=60', 'PERF collision=2', ''):
            with self.assertRaises(ValueError):
                check_collision_workload(text)

    def test_legacy_requires_explicit_selection_and_absent_tag(self):
        with self.assertRaises(ValueError):
            check_collision_workload('PERF fps=60')
        self.assertIn('Historical', check_collision_workload('PERF fps=60', 'legacy'))
        with self.assertRaises(ValueError):
            check_collision_workload('PERF collision=0', 'legacy')


if __name__ == '__main__':
    unittest.main()
