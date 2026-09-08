"""Require explicit obstacle workload identity when accepting a capture."""
import re


def check_collision_workload(text, collision='off'):
    samples = [dict(re.findall(r'(\w+)=(\S+)', line)) for line in text.splitlines()
               if line.startswith('PERF ')]
    if not samples:
        raise ValueError('capture has no PERF samples')
    if collision == 'legacy':
        if any('collision' in row for row in samples):
            raise ValueError('legacy collision mode requires an untagged historical capture')
        return 'Historical capture without collision workload tags.'
    if collision not in ('off', 'on'):
        raise ValueError('unknown collision mode')
    expected = '1' if collision == 'on' else '0'
    if any(row.get('collision') != expected for row in samples):
        raise ValueError(f'every PERF sample must identify collision={expected}; capture each configuration separately')
    return f'Collision demo: {collision}.'
