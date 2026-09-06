#!/usr/bin/env python3
"""Check sustained one-second samples from make BENCHMARK=1 in ares ISViewer."""
import argparse
from pathlib import Path
import re
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('log', type=Path)
parser.add_argument('--minimum', type=int, default=40)
parser.add_argument('--samples-per-phase', type=int, default=15)
args = parser.parse_args()
text = args.log.read_text()
if re.search(r'RDPQ_VALIDATION|ASSERTION|capacity exceeded', text):
    raise SystemExit('FAIL: diagnostic errors in the capture')
pattern = r'PERF views=(\d+) phase=(\d+) fps=(\d+) cpu_us=(\d+) submit_us=(\d+) triangles=(\d+)'
rows = [tuple(map(int, row)) for row in re.findall(pattern, text)]
if not rows or any(row[0] != 4 for row in rows):
    raise SystemExit('FAIL: capture must contain only four-player samples')
for phase, name in enumerate(('tour', 'independent movement', 'close quarters')):
    samples = [row[2] for row in rows if row[1] == phase]
    if len(samples) < args.samples_per_phase:
        raise SystemExit(f'FAIL: phase {phase} needs {args.samples_per_phase} complete samples')
    print(f'{name}: {len(samples)} samples; {min(samples)}–{max(samples)} FPS; mean {statistics.mean(samples):.1f}')
    if min(samples) < args.minimum:
        raise SystemExit(f'FAIL: phase {phase} fell below {args.minimum} FPS')
print(f'PASS: all {len(rows)} one-second samples reached {args.minimum}+ FPS')
