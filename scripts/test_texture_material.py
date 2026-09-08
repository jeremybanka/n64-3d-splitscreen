"""Texture asset and benchmark identity checks without the N64 SDK."""
import importlib.util
from pathlib import Path
import unittest

from texture_workload import check_texture_workload

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('make_texture', ROOT / 'scripts/make-texture.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class TextureTests(unittest.TestCase):
    def test_checked_in_texture_matches_editable_source(self):
        expected = converter.convert((ROOT / 'assets/textures/ground.ppm').read_text())
        self.assertEqual((ROOT / 'src/generated/ground_texture.h').read_text(), expected)

    def test_rgba5551_packing_and_opaque_alpha(self):
        source = 'P3\n16 16\n255\n' + ('255 0 0\n' * 256)
        result = converter.convert(source)
        self.assertEqual(result.count('0xf801'), 256)

    def test_wrong_dimensions_channel_count_and_range_fail(self):
        for source in ('P3 32 16 255', 'P3 16 16 255 0 0 0',
                       'P3 16 16 255 ' + '256 0 0 ' * 256):
            with self.subTest(source=source[:25]), self.assertRaises(ValueError):
                converter.convert(source)

    def test_benchmark_identity_rejects_mixed_and_missing_modes(self):
        row = 'PERF views=4 phase=0 fps=60 cpu_us=1 submit_us=1 triangles=42'
        self.assertIn('textured=1', check_texture_workload(row + ' textured=1 content=robot-courtyard', 'on', 'robot-courtyard'))
        self.assertIn('Historical', check_texture_workload(row, 'legacy'))
        for capture in (row, row + ' textured=0 content=meadow',
                        row + ' textured=1 content=meadow\n' + row + ' textured=0 content=meadow'):
            with self.subTest(capture=capture), self.assertRaises(ValueError):
                check_texture_workload(capture, 'on')
        with self.assertRaises(ValueError):
            check_texture_workload(row + ' textured=0 content=meadow', 'legacy')


if __name__ == '__main__':
    unittest.main()
