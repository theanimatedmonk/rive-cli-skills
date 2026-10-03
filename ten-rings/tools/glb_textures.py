#!/usr/bin/env python3
"""Extract the images embedded in a .glb to files next to it.

    python3 tools/glb_textures.py rive/ring.glb
    -> rive/ring-image0.png (one file per embedded image)

Add the PNG to the Rive project as an ImageAsset and set GLBModel's
`textureImage` input to its name. Needed for the web runtime, which cannot
decode images from inside a script.
"""
import json
import os
import struct
import sys

EXT = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}


def main(path: str) -> None:
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        sys.exit(f"{path}: not a glTF 2.0 binary (.glb)")
    offset, gltf, bin_start = 12, None, None
    while offset + 8 <= len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif kind == 0x004E4942 and bin_start is None:
            bin_start = offset + 8
        offset += 8 + length
    if gltf is None:
        sys.exit(f"{path}: no JSON chunk")
    base = os.path.splitext(path)[0]
    images = gltf.get("images", [])
    if not images:
        print("no embedded images")
    for i, image in enumerate(images):
        if "bufferView" not in image:
            print(f"image {i}: external or data URI, skipped")
            continue
        view = gltf["bufferViews"][image["bufferView"]]
        start = bin_start + view.get("byteOffset", 0)
        blob = data[start : start + view["byteLength"]]
        out = f"{base}-image{i}.{EXT.get(image.get('mimeType', ''), 'bin')}"
        open(out, "wb").write(blob)
        used = [m.get("name", f"material {n}") for n, m in enumerate(gltf.get("materials", []))
                if m.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index") is not None
                and gltf["textures"][m["pbrMetallicRoughness"]["baseColorTexture"]["index"]].get("source") == i]
        print(f"wrote {out} ({len(blob)} bytes)" + (f", base colour of {', '.join(used)}" if used else ""))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
