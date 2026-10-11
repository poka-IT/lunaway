#!/usr/bin/env python3
"""Compares two passes of battery.py trip by trip.

    python3 compare.py before.jsonl after.jsonl

Prints, by band of the first route's length (before), the client's p50 and
p95 times and the recalculations before and after; then every trip whose
status changed, whose first route's length moved by more than 1 %, or
whose recalculations changed.
"""

import json
import sys

BANDS = [(0, 20e3, "under 20 km"), (20e3, 100e3, "20 to 100 km"), (100e3, 500e3, "100 to 500 km"),
         (500e3, 1000e3, "500 to 1 000 km"), (1000e3, float("inf"), "1 000 km and more")]


def load(path):
    with open(path) as f:
        return {r["id"]: r for r in map(json.loads, f)}


def pct(values, q):
    if not values:
        return None
    v = sorted(values)
    return v[min(len(v) - 1, int(round(q * (len(v) - 1))))]


def first_m(r):
    routes = r.get("routes") or []
    return routes[0]["m"] if routes else None


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    ids = sorted(set(a) & set(b))
    print("| route (before) | n | p50 before | p50 after | p95 before | p95 after | recalculated before | after |")
    print("|---|---|---|---|---|---|---|---|")
    for lo, hi, name in BANDS:
        sel = [i for i in ids if first_m(a[i]) is not None and lo <= first_m(a[i]) < hi]
        ta = [a[i]["ms"] for i in sel]
        tb = [b[i]["ms"] for i in sel]
        ra = sum(1 for i in sel if (a[i].get("recalculations") or 0) > 0)
        rb = sum(1 for i in sel if (b[i].get("recalculations") or 0) > 0)
        print(f"| {name} | {len(sel)} | {pct(ta, .5)} | {pct(tb, .5)} | {pct(ta, .95)} | {pct(tb, .95)} | {ra} | {rb} |")
    unrouted = [i for i in ids if first_m(a[i]) is None]
    print(f"\nwithout a route before: {len(unrouted)} {unrouted}")
    print(f"recalculations: {sum(a[i].get('recalculations') or 0 for i in ids)} before, "
          f"{sum(b[i].get('recalculations') or 0 for i in ids)} after")
    for i in ids:
        sa, sb = a[i].get("status", a[i].get("errors")), b[i].get("status", b[i].get("errors"))
        ma, mb = first_m(a[i]), first_m(b[i])
        moved = ma and mb and abs(mb - ma) / ma > 0.01
        ca, cb = a[i].get("recalculations"), b[i].get("recalculations")
        if sa != sb or moved or ca != cb:
            print(f"trip {i} band {a[i]['band']}: {sa} -> {sb}, {ma} -> {mb} m, "
                  f"recalculations {ca} -> {cb}, {a[i]['ms']} -> {b[i]['ms']} ms, "
                  f"blockers {a[i].get('blockers')} -> {b[i].get('blockers')}")


if __name__ == "__main__":
    main()
