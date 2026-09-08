"""Keep texture/content benchmark identity separate from frame-rate acceptance."""
import re


def check_texture_workload(text, textured='off', content='meadow'):
    samples = [dict(re.findall(r'(\w+)=(\S+)', line)) for line in text.splitlines()
               if line.startswith('PERF ')]
    if not samples:
        raise ValueError('capture has no PERF samples')
    if textured == 'legacy':
        if content != 'meadow' or any('textured' in row or 'content' in row for row in samples):
            raise ValueError('legacy mode is only for untagged historical Bunny Meadow captures')
        return 'Historical untextured Bunny Meadow capture (before material/content tags).'
    expected = '1' if textured == 'on' else '0'
    if any(row.get('textured') != expected or row.get('content') != content for row in samples):
        raise ValueError(f'every PERF sample must identify textured={expected} content={content}; use --textured legacy only for historical untagged captures')
    return f'Workload: content={content}, textured={expected} (16x16 RGBA16 ground tile when enabled).'
