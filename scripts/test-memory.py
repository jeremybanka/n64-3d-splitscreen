#!/usr/bin/env python3
"""Synthetic checker fixtures, not console or emulator measurements."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("check_memory", Path(__file__).with_name("check-memory.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def capture(ram=4194304):
    total = ram - 500000 - 65536
    boot = "CONFIG schema=1 content=meadow audio=1 textured=1 collision=0 benchmark=1 validate=0 initial_views=4\n"
    boot += "CAPACITY mesh_bytes=37900 mesh_vertices=2048 mesh_batches=64 mesh_indices=4096 animated_vertices=768 packed_bytes=32 frame_slots=3 ports=4 meshes_bytes=75800 animation_bytes=147456 width=320 height=240 color_bpp=2 color_buffers=3 depth_stride=640 depth_height=240\n"
    samples = [("init", 0, 1000000), ("run", 1000, 1100000)]
    samples += [("run", second * 1000, 1200000) for second in range(10, 61, 10)]
    for stage, elapsed, used in samples:
        boot += (f"MEMORY schema=1 stage={stage} elapsed_ms={elapsed} ram={ram} expanded={int(ram == 8388608)} tv=NTSC "
                 f"resident=500000 zero_bytes=250000 heap_total={total} heap_used={used} heap_free={total-used} "
                 f"sampled_min_free={total-used} reserved=65536 color_bytes=460800 depth_bytes=153600\n")
    return boot


class MemoryTests(unittest.TestCase):
    def test_base_memory_capture_with_explicit_modes(self):
        self.assertIn("4 MiB NTSC", checker.check(capture(), require_base_memory=True, tv="NTSC", audio=1, textured=1, collision=0))

    def test_expansion_cannot_certify_base_memory(self):
        self.assertIn("8 MiB", checker.check(capture(8388608)))
        with self.assertRaisesRegex(ValueError, "actual 4 MiB"):
            checker.check(capture(8388608), require_base_memory=True)

    def test_region_modes_duration_and_policy_are_enforced(self):
        for options in ({"tv": "PAL"}, {"audio": 0}, {"collision": 1}, {"content": "robot-courtyard"}, {"minimum_seconds": 600}, {"minimum_free": 3000000}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                checker.check(capture(), **options)

    def test_mixed_boots_or_missing_late_samples_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "exactly one boot"):
            checker.check(capture() + capture())
        with self.assertRaisesRegex(ValueError, "at least"):
            checker.check(capture().rsplit("MEMORY", 1)[0])
        with self.assertRaisesRegex(ValueError, "Mixed"):
            checker.check(capture().replace("elapsed_ms=60000 ram=4194304 expanded=0 tv=NTSC", "elapsed_ms=60000 ram=4194304 expanded=0 tv=PAL"))

    def test_malformed_accounting_and_diagnostic_failures_are_rejected(self):
        for original, replacement in (("reserved=65536", "reserved=0"), ("animation_bytes=147456", "animation_bytes=1"),
                                      ("color_bytes=460800", "color_bytes=1"), ("heap_used=1200000", "heap_used=1200001"),
                                      ("sampled_min_free=2428768", "sampled_min_free=1")):
            with self.subTest(field=original), self.assertRaises(ValueError):
                checker.check(capture().replace(original, replacement))
        with self.assertRaisesRegex(ValueError, "Diagnostic"):
            checker.check(capture() + "ASSERTION failed\n")


if __name__ == "__main__":
    unittest.main()
