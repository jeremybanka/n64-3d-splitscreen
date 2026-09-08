#!/usr/bin/env python3
"""Focused checks that invalid/mixed benchmark captures cannot pass acceptance."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('performance', Path(__file__).with_name('check-performance.py'))
performance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(performance)


def capture(mode='on'):
    lines = []
    for phase in range(3):
        line = f'PERF views=4 phase={phase} fps=60 cpu_us=1000 submit_us=2000 triangles=900'
        if mode != 'legacy':
            on = mode == 'on'
            line += (f' audio={int(on)} audio_us={100 if on else 0} audio_buffers={50 if on else 0}'
                     f' audio_gap_us={18000 if on else 0} audio_budget_us={80000 if on else 0}'
                     f' audio_sfx={4 if on else 0} audio_overlap={4 if on else 0} workload=2')
        lines.append(line)
    return '\n'.join(lines)


class PerformanceTests(unittest.TestCase):
    def check(self, text, mode=None):
        return performance.check_capture(text, samples_per_phase=1, audio=mode)

    def test_separate_on_off_and_legacy_modes(self):
        for mode in ('on', 'off', 'legacy'):
            self.assertIn(f'Audio: {mode}', self.check(capture(mode), mode)[0])
        self.assertIn('historical pre-audio', self.check(capture('legacy'))[0])

    def test_mixed_modes_and_workloads_rejected(self):
        for extra in (capture('off'), capture('legacy'), capture().replace('workload=2', 'workload=3')):
            with self.assertRaisesRegex(ValueError, 'mixed'):
                self.check(capture() + '\n' + extra)
        with self.assertRaisesRegex(ValueError, 'expected audio'):
            self.check(capture('legacy'), 'on')

    def test_audio_work_and_overlap_required(self):
        for text, reason in ((capture().replace('audio_buffers=50', 'audio_buffers=0'), 'no output'),
                             (capture().replace('audio_overlap=4', 'audio_overlap=3'), 'four overlapping'),
                             (capture().replace('audio_gap_us=18000', 'audio_gap_us=90000'), 'service gap'),
                             (capture('off').replace('audio_us=0', 'audio_us=100'), 'audio-off')):
            with self.assertRaisesRegex(ValueError, reason):
                self.check(text)

    def test_incomplete_or_slow_capture_rejected(self):
        for text in (capture().replace(' audio_buffers=50', ''),
                     capture().replace('fps=60', 'fps=20'),
                     capture().splitlines()[0], capture() + '\nASSERTION failed'):
            with self.assertRaises(ValueError):
                self.check(text)

    def test_future_content_fields_do_not_break_audio_parsing(self):
        self.check(capture().replace('workload=2', 'workload=2 textured=0 content=meadow'))


if __name__ == '__main__':
    unittest.main()
