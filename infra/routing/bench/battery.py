#!/usr/bin/env python3
"""Runs the route battery against an API, one trip at a time.

    python3 battery.py trips.csv out.jsonl [--avoid motorways] [--alternatives 2]
        [--api http://127.0.0.1:8484/graphql] [--pause 1] [--only 5,12] [--offset 250]

Sends the app's route request (its latest form: speed limits, reasons,
cruising speed, moved stops) for an alcove motorhome (3.3 m, 2.3 m, 7.4 m,
3.5 t), in French, and writes one JSON line per trip: the status, the time
the client waited, each route's length, duration and geometry digest, the
recalculations the API made, the size of the OSRM answer, the errors. Run
on the backend, the API on the loopback: each request carries its own
address in X-Forwarded-For, so the route quota (30 every ten minutes per
client) never applies, and the pause keeps one route in flight at a time.
Standard library only.
"""

import argparse
import csv
import hashlib
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

DOCUMENT = """
query Route($input: RouteInput!) {
  route(input: $input) {
    status
    osrmJson
    noRouteReasons { kind stopIndex limits { kind limit vehicleValue restriction { ...RouteWarningFields } } }
    movedStops { stopIndex lat lon distanceM }
    routes {
      index distanceM durationS hasToll hasFerry hasMotorway
      warnings { ...RouteWarningFields }
      roadEvents { ...RoadEventWarningFields }
      speedLimits { fromM toM kmh source }
      notices { kind ferry { ...FerryCrossingFields } }
    }
    blockers { ...RouteWarningFields }
    roadEventBlockers { ...RoadEventWarningFields }
    avoidedRoadEvents { ...RouteRoadEventFields }
    roadEventSources { id name attribution lastReadAt dataAt staleAfterSeconds fresh }
    recalculations
    reroute {
      vehicle { kind heightM widthM lengthM weightT axleLoadT trailer { lengthM weightT heightM widthM } cruiseSpeedKph }
      options { avoidTolls avoidMotorways avoidFerries avoidUnpaved }
      language
      topSpeedKph
    }
    graph { ...RoutingGraphFields }
  }
}
fragment RouteWarningFields on RouteWarning {
  kind severity limit vehicleValue distanceFromStartM geometryIndex lat lon
  source certainty place name externalId exceptDestination
}
fragment RouteRoadEventFields on RoadEvent {
  id class source roadNumber roadName validFrom validTo match mayBlock
  position { lat lon } headingDeg limits { maxHeightM maxWidthM }
  sourceUpdatedAt firstSeenAt
}
fragment RoadEventWarningFields on RoadEventWarning {
  event { ...RouteRoadEventFields } severity reason distanceFromStartM lengthM lat lon dataReadAt
}
fragment RoutingGraphFields on RoutingGraph { id osmDataAt ignFetchedAt ignEdition builtAt }
fragment FerryCrossingFields on FerryCrossing {
  name ports fromLat fromLon toLat toLon fromCountry toCountry distanceFromStartM distanceM durationS
}
"""

VEHICLE = {"kind": "OVERCAB", "heightM": 3.3, "widthM": 2.3, "lengthM": 7.4, "weightT": 3.5}


def read_trips(path):
    """The trips of trips.csv (trips.sql's columns, no header), numbered
    from 0 in file order."""
    with open(path, newline="") as f:
        return [
            {"id": n, "band": band, "from_fr": fr == "t", "from_country": oc, "to_country": dc,
             "from_lat": olat, "from_lon": olon, "to_lat": dlat, "to_lon": dlon, "straight_km": km}
            for n, (band, fr, oc, dc, olat, olon, dlat, dlon, km) in enumerate(csv.reader(f))
        ]


def address(n):
    """An address of its own for request n, in the benchmarking range
    198.18.0.0/15 (RFC 2544): 64 000 before one comes back."""
    n %= 250 * 256
    return f"198.18.{n // 250}.{n % 250 + 1}"


def digest(geometry):
    """A short digest of a route's encoded shape: the same route twice has
    the same digest."""
    return hashlib.sha1(geometry.encode()).hexdigest()[:16] if geometry else None


def ask(args, n, t, avoid):
    """One route request; the line written for it."""
    variables = {"input": {
        "origin": {"lat": float(t["from_lat"]), "lon": float(t["from_lon"]), "vehiclePosition": False},
        "destination": {"lat": float(t["to_lat"]), "lon": float(t["to_lon"])},
        "vehicle": VEHICLE,
        "options": avoid,
        "alternatives": args.alternatives,
        "language": "FR",
    }}
    body = json.dumps({"query": DOCUMENT, "variables": variables}).encode()
    req = urllib.request.Request(args.api, data=body, headers={
        "Content-Type": "application/json",
        "X-Forwarded-For": address(n + args.offset),
        "User-Agent": "lunaway-route-battery (+https://lunaway.net)",
    })
    row = {"id": t["id"], "band": int(t["band"]), "straight_km": float(t["straight_km"]),
           "avoid": args.avoid, "started": datetime.now(timezone.utc).isoformat()}
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read()
            row["http"] = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        row["http"] = e.code
    except OSError as e:
        raw = b""
        row["http"] = 0
        row["errors"] = [{"message": str(e)}]
    row["ms"] = round((time.monotonic() - t0) * 1000)
    row["ended"] = datetime.now(timezone.utc).isoformat()
    row["bytes"] = len(raw)
    try:
        answer = json.loads(raw) if raw else {}
    except ValueError:
        answer = {}
    if answer.get("errors"):
        row["errors"] = [
            {"message": e.get("message"), "code": (e.get("extensions") or {}).get("code")}
            for e in answer["errors"]
        ]
    r = (answer.get("data") or {}).get("route")
    if r:
        osrm = json.loads(r.get("osrmJson") or "{}")
        row["status"] = r["status"]
        row["osrm_bytes"] = len(r.get("osrmJson") or "")
        row["recalculations"] = r.get("recalculations")
        row["routes"] = [
            {"m": x["distanceM"], "s": x["durationS"], "warnings": len(x["warnings"]),
             "motorway": x["hasMotorway"]}
            for x in r["routes"]
        ]
        row["geometry"] = [digest(x.get("geometry")) for x in osrm.get("routes", [])]
        row["blockers"] = [b.get("externalId") for b in r.get("blockers") or []]
        row["reasons"] = [x["kind"] for x in r.get("noRouteReasons") or []]
        row["graph"] = (r.get("graph") or {}).get("id")
    return row


def run(args):
    avoid = {f"avoid{a.capitalize()}": True for a in args.avoid}
    only = {int(i) for i in args.only.split(",")} if args.only else None
    trips = [t for t in read_trips(args.trips) if only is None or t["id"] in only]
    with open(args.out, "a") as out:
        for n, t in enumerate(trips):
            row = ask(args, n, t, avoid)
            out.write(json.dumps(row) + "\n")
            out.flush()
            first = (row.get("routes") or [{}])[0].get("m")
            print(f'{row["id"]:4} band {row["band"]} {row.get("status", row.get("errors"))} '
                  f'{row["ms"]} ms {first} m recalc {row.get("recalculations")}', flush=True)
            time.sleep(args.pause)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("trips")
    p.add_argument("out")
    p.add_argument("--api", default="http://127.0.0.1:8484/graphql")
    p.add_argument("--avoid", action="append", default=[],
                   choices=["tolls", "motorways", "ferries", "unpaved"])
    p.add_argument("--alternatives", type=int, default=2)
    p.add_argument("--pause", type=float, default=1.0)
    p.add_argument("--only", help="trip numbers (from 0, in file order), comma separated")
    p.add_argument("--offset", type=int, default=0,
                   help="first client address, to keep series apart within ten minutes")
    run(p.parse_args())


if __name__ == "__main__":
    main()
