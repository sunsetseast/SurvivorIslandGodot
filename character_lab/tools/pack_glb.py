"""Encode Web-sized glTF core textures while preserving masked edges."""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image


def pack(source, output):
    glb = source.read_bytes()
    json_size, = struct.unpack_from("<I", glb, 12)
    data = json.loads(glb[20:20 + json_size])
    binary = memoryview(glb)[28 + json_size:]
    masked = {
        data["textures"][m["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
        for m in data["materials"] if m.get("alphaMode") == "MASK"
    }
    replacements = {}
    for index, image in enumerate(data["images"]):
        view_index = image["bufferView"]
        view = data["bufferViews"][view_index]
        offset = view.get("byteOffset", 0)
        with Image.open(io.BytesIO(binary[offset:offset + view["byteLength"]])) as texture:
            buffer = io.BytesIO()
            if index in masked:
                texture = texture.convert("RGBA")
                texture.thumbnail((768, 768), Image.Resampling.LANCZOS)
                texture.quantize(192, method=Image.Quantize.FASTOCTREE).save(buffer, format="PNG", optimize=True)
                image["mimeType"] = "image/png"
            else:
                texture = texture.convert("RGB")
                size = 512 if "normal" in image["name"] else 1024
                texture.thumbnail((size, size), Image.Resampling.LANCZOS)
                texture.save(buffer, format="JPEG", quality=87, subsampling=0, optimize=True)
                image["mimeType"] = "image/jpeg"
            replacements[view_index] = buffer.getvalue()

    payload = bytearray()
    for index, view in enumerate(data["bufferViews"]):
        offset = view.get("byteOffset", 0)
        content = replacements.get(index, binary[offset:offset + view["byteLength"]])
        view["byteOffset"] = len(payload)
        view["byteLength"] = len(content)
        payload.extend(content)
        payload.extend(b"\0" * (-len(payload) % 4))
    data["buffers"][0]["byteLength"] = len(payload)
    header = json.dumps(data, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    output.write_bytes(
        struct.pack("<4sIII4s", b"glTF", 2, 28 + len(header) + len(payload), len(header), b"JSON")
        + header + struct.pack("<I4s", len(payload), b"BIN\0") + payload
    )


if __name__ == "__main__":
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
