#!/usr/bin/env python3
"""Measures the routing engine's answer for trips of the battery, without the API.

    python3 engine_sizes.py trips.csv out.jsonl --only 101,117 [--avoid motorways]
        [--alternates 0,1,2] [--engine http://127.0.0.1:8002]

Sends the body the API sends (lunaway_api::routing::valhalla::route_body:
OSRM format, banner and voice instructions, the four shape attributes, the
stops snapped off ferries and tunnels) for the battery's motorhome, once per
number of alternates, and writes the answer's size, the time, each route's
length and its own size once serialised. Run on the backend, the engine on
the loopback; one request at a time.
"""

import argparse
import csv
import json
import time
import urllib.error
import urllib.request

VEHICLE = {"height": 3.3, "width": 2.3, "length": 7.4, "weight": 3.5}


def read_trips(path):
    """The trips of trips.csv (trips.sql's columns, no header), numbered
    from 0 in file order."""
    with open(path, newline="") as f:
        return [
            {"id": n, "band": band, "from_fr": fr == "t", "from_country": oc, "to_country": dc,
             "from_lat": olat, "from_lon": olon, "to_lat": dlat, "to_lon": dlon, "straight_km": km}
            for n, (band, fr, oc, dc, olat, olon, dlat, dlon, km) in enumerate(csv.reader(f))
        ]


def body(t, avoid, alternates):
    auto = dict(VEHICLE)
    if "motorways" in avoid:
        auto["use_highways"] = 0.0
    if "tolls" in avoid:
        auto["use_tolls"] = 0.0
    if "ferries" in avoid:
        auto["use_ferry"] = 0.0

    def loc(lat, lon):
        return {"lat": float(lat), "lon": float(lon), "type": "break", "search_cutoff": 5000,
                "search_filter": {"exclude_ferry": True, "exclude_tunnel": True}}

    b = {
        "locations": [loc(t["from_lat"], t["from_lon"]), loc(t["to_lat"], t["to_lon"])],
        "costing": "auto",
        "costing_options": {"auto": auto},
        "format": "osrm",
        "shape_format": "polyline6",
        "banner_instructions": True,
        "voice_instructions": True,
        "language": "fr-FR",
        "filters": {"attributes": ["shape_attributes.speed", "shape_attributes.speed_limit",
                                   "shape_attributes.time", "shape_attributes.length"],
                    "action": "include"},
    }
    if alternates:
        b["alternates"] = alternates
    return b


def main():
    p = argparse.ArgumentParser()
    p.add_argument("trips")
    p.add_argument("out")
    p.add_argument("--engine", default="http://127.0.0.1:8002")
    p.add_argument("--avoid", action="append", default=[])
    p.add_argument("--alternates", default="0,1,2")
    p.add_argument("--only", required=True)
    args = p.parse_args()
    only = {int(i) for i in args.only.split(",")}
    trips = [t for t in read_trips(args.trips) if t["id"] in only]
    with open(args.out, "a") as out:
        for t in trips:
            for alt in (int(a) for a in args.alternates.split(",")):
                req = urllib.request.Request(
                    f"{args.engine}/route", data=json.dumps(body(t, args.avoid, alt)).encode(),
                    headers={"Content-Type": "application/json",
                             "User-Agent": "lunaway-route-battery (+https://lunaway.net)"})
                t0 = time.monotonic()
                try:
                    with urllib.request.urlopen(req, timeout=120) as resp:
                        raw = resp.read()
                        status = resp.status
                except urllib.error.HTTPError as e:
                    raw, status = e.read(), e.code
                ms = round((time.monotonic() - t0) * 1000)
                row = {"id": t["id"], "straight_km": float(t["straight_km"]), "avoid": args.avoid,
                       "alternates": alt, "http": status, "ms": ms, "bytes": len(raw)}
                if status == 200:
                    answer = json.loads(raw)
                    routes = answer.get("routes") or []
                    row["routes"] = []
                    for r in routes:
                        steps = sum(len(leg.get("steps") or []) for leg in r.get("legs") or [])
                        ann = sum(len(json.dumps(leg.get("annotation") or {})) for leg in r.get("legs") or [])
                        row["routes"].append({"m": r.get("distance"), "bytes": len(json.dumps(r)),
                                              "geometry": len(r.get("geometry") or ""),
                                              "annotation": ann, "steps": steps})
                else:
                    row["error"] = raw[:300].decode(errors="replace")
                out.write(json.dumps(row) + "\n")
                out.flush()
                print(json.dumps(row), flush=True)
                time.sleep(1)


if __name__ == "__main__":
    main()
