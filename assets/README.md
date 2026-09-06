# Rabbit source asset

Original character created for this repository in Blender 5.2.1.

- `rabbit.blend`: editable named character parts, materials, camera and lights.
- `rabbit-preview.png`: Blender studio rendering.
- `../scripts/make-rabbit.py`: deterministic source recipe and mesh exporter.
- `../src/generated/rabbit.zig`: 130 vertices and 188 flat-shaded triangles.

Coordinates exported to the ROM are integer Q8: Blender X/Z/−Y becomes game
X/Y/Z, with Y up and +Z forward. Material 3 is the per-player jersey color.
Each face stores a baked directional-light shade. Animation tags identify
opposing limbs and ears for simple procedural motion in Zig. The preview
floor, lights and camera are excluded from the exported mesh.
