"""Writes assets/map/offline/regions.json: the outlines of the offline packs.

    python3 tool/map_offline/regions.py      # from app/

The packs' manifest gives each pack a bounding box only, and the boxes of
neighbouring regions overlap. The app needs the outline itself to say which
pack covers a point: the one to draw offline, the one to suggest where the
traveller stands. This reads infra/tiles/packs/regions.geojson (the outlines
the backend cuts the packs with, with their margin of 3 to 8 km), simplifies
each ring to under 3 km (Douglas-Peucker in degrees, then rounding to 0.001
degree) and
writes {id: [[[lon, lat], ...], ...]}: outer rings only, since a pack keeps
its enclaves (docs/deploy.md, "Offline packs"). A pack whose id is missing
here falls back to its box in the app.
"""

import json
import math
import os

TOLERANCE = 0.025  # degrees, under 3 km: less than the outlines' own margin


def simplify(points, tolerance):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, index = 0.0, None
        for i in range(a + 1, b):
            px, py = points[i]
            d = abs(dy * px - dx * py + bx * ay - by * ax) / norm if norm else math.hypot(px - ax, py - ay)
            if d > best:
                best, index = d, i
        if index is not None and best > tolerance:
            keep[index] = True
            stack += [(a, index), (index, b)]
    return [p for p, k in zip(points, keep) if k]


def main():
    app = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    src = os.path.join(app, "..", "infra", "tiles", "packs", "regions.geojson")
    data = json.load(open(src))
    out = {}
    for f in data["features"]:
        geometry = f["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        rings = []
        for polygon in polygons:
            ring = simplify(polygon[0], TOLERANCE)
            ring = [[round(x, 3), round(y, 3)] for x, y in ring]
            if len(ring) >= 4:
                rings.append(ring)
        out[f["properties"]["id"]] = rings
    path = os.path.join(app, "assets", "map", "offline", "regions.json")
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
        f.write("\n")
    print("wrote %d outlines, %d vertices, %d bytes" % (
        len(out), sum(len(r) for rs in out.values() for r in rs), os.path.getsize(path)))


if __name__ == "__main__":
    main()
