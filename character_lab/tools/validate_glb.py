"""Audit the shipped GLB without loading Blender or Godot."""
import json
import struct
import sys
from pathlib import Path

REQUIRED = {"Idle", "Walk", "Jog", "Talk", "SitDown", "Seated", "StandUp"}


def review(path):
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from("<4sII", raw)
    assert (magic, version, total) == (b"glTF", 2, len(raw)), f"Invalid GLB header in {path}"
    json_size, chunk = struct.unpack_from("<I4s", raw, 12)
    assert chunk == b"JSON" and 20 + json_size < total
    data = json.loads(raw[20:20 + json_size])
    binary_size, binary_kind = struct.unpack_from("<I4s", raw, 20 + json_size)
    assert binary_kind == b"BIN\x00" and 28 + json_size + binary_size == total
    assert len(data["skins"]) == 1
    assert 45 <= len(data["skins"][0]["joints"]) <= 75
    assert len([n for n in data["nodes"] if n.get("skin") == 0]) >= 3
    animations = {a["name"]: a for a in data["animations"]}
    assert animations.keys() >= REQUIRED, REQUIRED - animations.keys()
    joints = set(data["skins"][0]["joints"])
    for name in REQUIRED:
        rotation_channels = [c for c in animations[name]["channels"]
                             if c["target"]["path"] == "rotation" and c["target"]["node"] in joints]
        assert len(rotation_channels) >= 20, f"{name} has insufficient joint animation"
    meshes = data["meshes"]
    assert any("Smile" in mesh.get("extras", {}).get("targetNames", []) for mesh in meshes)
    primitives = [p for mesh in meshes for p in mesh["primitives"]]
    triangles = 0
    for primitive in primitives:
        assert primitive.get("mode", 4) == 4
        indices = data["accessors"][primitive["indices"]]
        assert indices["count"] % 3 == 0
        triangles += indices["count"] // 3
    assert triangles <= 36000, "Review geometry budget"
    assert len(primitives) <= 24, "Review draw submission budget"
    assert all(image.get("bufferView") is not None for image in data.get("images", []))
    assert all("uri" not in buffer for buffer in data["buffers"])
    return {"bytes": total, "triangles": triangles, "surfaces": len(primitives),
            "joints": len(joints), "materials": len(data["materials"]),
            "images": len(data.get("images", [])), "animations": sorted(animations)}


if __name__ == "__main__":
    print(json.dumps(review(Path(sys.argv[1])), indent=2))
