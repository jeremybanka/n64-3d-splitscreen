#!/usr/bin/env python3
"""Validate one runtime MEMORY capture; this does not certify its physical source."""
import argparse
from pathlib import Path
import re


def records(text, kind):
    result = []
    for line in text.splitlines():
        if line.startswith(kind + " "):
            fields = line.split()[1:]
            if any("=" not in field for field in fields):
                raise ValueError(f"Malformed {kind} record")
            row = dict(field.split("=", 1) for field in fields)
            if len(row) != len(fields):
                raise ValueError(f"Duplicate {kind} field")
            result.append(row)
    return result


def check(text, *, require_base_memory=False, tv=None, minimum_seconds=60,
          minimum_free=256 * 1024, content=None, audio=None, textured=None, collision=None):
    if re.search(r"RDPQ_VALIDATION|ASSERTION|capacity.*exceeded|Invalid heap accounting", text, re.I):
        raise ValueError("Diagnostic errors in the capture")
    configs = records(text, "CONFIG")
    capacities = records(text, "CAPACITY")
    rows = records(text, "MEMORY")
    if len(configs) != 1 or len(capacities) != 1:
        raise ValueError("Capture must contain exactly one boot CONFIG and CAPACITY record")
    config, capacity = configs[0], capacities[0]
    if config["schema"] != "1" or any(config[key] not in ("0", "1") for key in ("audio", "textured", "collision", "benchmark", "validate")):
        raise ValueError("Unsupported or invalid CONFIG")
    if not config["content"]:
        raise ValueError("Missing content identity")
    if not 1 <= int(config["initial_views"]) <= 4:
        raise ValueError("Invalid initial view count")
    for key, expected in (("content", content), ("audio", audio), ("textured", textured), ("collision", collision)):
        if expected is not None and config[key] != str(expected):
            raise ValueError(f"Expected {key}={expected}; capture has {config[key]}")
    capacity = {key: int(value) for key, value in capacity.items()}
    if any(value <= 0 for value in capacity.values()):
        raise ValueError("Invalid zero/negative capacity")
    if capacity["animation_bytes"] != capacity["animated_vertices"] // 2 * capacity["packed_bytes"] * capacity["frame_slots"] * capacity["ports"]:
        raise ValueError("Animation storage does not match reported ABI capacities")
    color_bytes = capacity["width"] * capacity["height"] * capacity["color_bpp"] * capacity["color_buffers"]
    depth_bytes = capacity["depth_stride"] * capacity["depth_height"]
    if len(rows) < 2 or rows[0]["stage"] != "init":
        raise ValueError("Need initialization and later runtime memory samples")
    previous_time = -1
    low_water = None
    identity = None
    for row in rows:
        label = row["stage"]
        video = row["tv"]
        data = {key: int(value) for key, value in row.items() if key not in ("stage", "tv")}
        if data["schema"] != 1 or video not in ("NTSC", "PAL", "MPAL"):
            raise ValueError("Unsupported MEMORY schema or video region")
        if data["ram"] not in (4 * 1024 * 1024, 8 * 1024 * 1024) or data["expanded"] != int(data["ram"] == 8 * 1024 * 1024):
            raise ValueError("Unsupported/inconsistent RAM report")
        if require_base_memory and data["ram"] != 4 * 1024 * 1024:
            raise ValueError("Base-memory verification requires an actual 4 MiB runtime report")
        if tv is not None and video != tv:
            raise ValueError(f"Expected {tv} video; capture reports {video}")
        current_identity = (data["ram"], video, data["resident"], data["heap_total"], data["reserved"], data["zero_bytes"])
        if identity is not None and current_identity != identity:
            raise ValueError("Mixed runtime memory/region identities")
        identity = current_identity
        if data["elapsed_ms"] <= previous_time or (previous_time < 0 and data["elapsed_ms"] != 0) or (previous_time >= 0 and label != "run"):
            raise ValueError("Nonmonotonic time or multiple boots in capture")
        if previous_time >= 0 and data["elapsed_ms"] - previous_time > 15000:
            raise ValueError("Memory sample gap exceeds 15 seconds; capture must be continuous")
        previous_time = data["elapsed_ms"]
        if any(value < 0 for value in data.values()) or data["resident"] < data["zero_bytes"]:
            raise ValueError("Invalid memory accounting")
        if data["heap_total"] <= 0 or data["reserved"] <= 0 or data["heap_used"] + data["heap_free"] != data["heap_total"]:
            raise ValueError("Heap used/free accounting does not balance")
        if data["resident"] + data["heap_total"] + data["reserved"] != data["ram"]:
            raise ValueError("Resident/heap/reserved accounting does not balance")
        if data["color_bytes"] != color_bytes or data["depth_bytes"] != depth_bytes:
            raise ValueError("Surface storage does not match display configuration")
        low_water = min(low_water, data["heap_free"]) if low_water is not None else data["heap_free"]
        if data["sampled_min_free"] != low_water:
            raise ValueError("Sampled low-water mark is inconsistent")
    if previous_time < minimum_seconds * 1000:
        raise ValueError(f"Capture needs at least {minimum_seconds} seconds")
    if low_water < minimum_free:
        raise ValueError(f"Sampled headroom {low_water} is below project policy {minimum_free}")
    return f"PASS: {len(rows)} samples over {previous_time / 1000:.1f}s; {identity[0] // (1024 * 1024)} MiB {identity[1]}; sampled free minimum {low_water} bytes"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--require-base-memory", action="store_true")
    parser.add_argument("--tv", choices=("NTSC", "PAL", "MPAL"))
    parser.add_argument("--minimum-seconds", type=int, default=60)
    parser.add_argument("--minimum-free", type=int, default=256 * 1024)
    parser.add_argument("--content")
    for name in ("audio", "textured", "collision"):
        parser.add_argument("--" + name, type=int, choices=(0, 1))
    args = parser.parse_args()
    if args.minimum_seconds < 0 or args.minimum_free < 0:
        parser.error("Minimum duration/headroom cannot be negative")
    try:
        print(check(args.log.read_text(), require_base_memory=args.require_base_memory, tv=args.tv,
                    minimum_seconds=args.minimum_seconds, minimum_free=args.minimum_free,
                    content=args.content, audio=args.audio, textured=args.textured, collision=args.collision))
    except (KeyError, ValueError) as error:
        raise SystemExit(f"FAIL: {error}") from error


if __name__ == "__main__":
    main()
