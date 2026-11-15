#!/usr/bin/env python3
"""Pack the licensed Lee Perry-Smith glTF scan into Spatial Studio's native mesh."""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

source, output = map(Path, sys.argv[1:])
raw = source.read_bytes()
expected = "402b8a8ac9f03232e6d64b5962929703a069daf99d3c49ac8eb0e48bedc9c576"
if hashlib.sha256(raw).hexdigest() != expected:
    raise SystemExit("Source doesn't match the recorded scan")
json_length, = struct.unpack_from("<I", raw, 12)
metadata = json.loads(raw[20:20 + json_length])
buffer = memoryview(raw)[28 + json_length:]
primitive = metadata["meshes"][0]["primitives"][0]

def values(index, fmt):
    accessor = metadata["accessors"][index]
    view = metadata["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    length = view["byteLength"] - accessor.get("byteOffset", 0)
    return list(struct.iter_unpack(fmt, buffer[offset:offset + length]))

positions = values(primitive["attributes"]["POSITION"], "<3f")
normals = values(primitive["attributes"]["NORMAL"], "<3f")
indices = values(primitive["indices"], "<3H")
minimum_height = -1.22
vertices = []
triangles = []
lookup = {}
cut = set()

def vertex(pos, normal):
    key = (pos, normal)
    if key not in lookup:
        index = len(vertices)
        # Scan viewer-right → acoustic left; glTF front +Z → SceneKit front -Z.
        # Both signs change together, so the original normals and winding survive.
        x, y, z = pos
        nx, ny, nz = normal
        vertices.append((-(x + 0.09) * .085, (y - 1.47) * .085, -(z - 0.15) * .085,
                         -nx, ny, -nz))
        lookup[key] = index
    return lookup[key]

def lerp(a, b, t):
    return tuple(a[i] + t * (b[i] - a[i]) for i in range(3))

for triangle in indices:
    polygon = [(positions[i], normals[i]) for i in triangle]
    clipped = []
    for (p, n), (q, m) in zip(polygon[-1:] + polygon[:-1], polygon):
        inside_p, inside_q = p[1] >= minimum_height, q[1] >= minimum_height
        if inside_p != inside_q:
            t = (minimum_height - p[1]) / (q[1] - p[1])
            x, _, z = lerp(p, q, t)
            crossing = (round(x, 7), minimum_height, round(z, 7))
            cut.add(crossing)
            clipped.append((crossing, lerp(n, m, t)))
        if inside_q:
            clipped.append((q, m))
    if len(clipped) >= 3:
        ids = [vertex(p, n) for p, n in clipped]
        triangles.extend((ids[0], ids[i], ids[i + 1]) for i in range(1, len(ids) - 1))

if cut:
    x = sum(p[0] for p in cut) / len(cut)
    z = sum(p[2] for p in cut) / len(cut)
    center = vertex((x, minimum_height, z), (0, -1, 0))
    ring = sorted(cut, key=lambda p: math.atan2(p[2] - z, p[0] - x))
    edge = [vertex(p, (0, -1, 0)) for p in ring]
    triangles.extend((center, a, b) for a, b in zip(edge, edge[1:] + edge[:1]))

with output.open("wb") as model:
    model.write(struct.pack("<4sII", b"SDM1", len(vertices), len(triangles)))
    for v in vertices:
        model.write(struct.pack("<6f", *v))
    for t in triangles:
        model.write(struct.pack("<3I", *t))
print(f"{len(vertices):,} vertices, {len(triangles):,} triangles")
