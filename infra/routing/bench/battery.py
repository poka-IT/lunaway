#!/usr/bin/env python3
"""Runs the route battery against an API, one trip at a time.

    python3 battery.py trips.csv out.jsonl [--avoid motorways] [--alternatives 2]
        [--api http://127.0.0.1:8484/graphql] [--pause 1] [--only 5,12] [--offset 250]
        [--depart-at 2026-10-12T12:00:00Z] [--later]

Sends the app's route request (speed limits, reasons, cruising speed, moved
stops) for an alcove motorhome (3.3 m, 2.3 m, 7.4 m, 3.5 t), in French, and
writes one JSON line per trip: the status, the time the client waited, each
route's length, duration and geometry digest, the recalculations the API
made, the road events it went round, the size of the OSRM answer, the
errors. Without `--later` the request is the app 0.1.0's, every route in
one answer; with it, the app's from 0.4: the best route alone with
`alternativesToken`, then `routeAlternatives` at once, whose time
(`later_ms`), status and routes (`alt_routes`) the line adds. Run on the
backend, the API on the loopback: each request carries its own address in
X-Forwarded-For, so the route quota (30 every ten minutes per client) never
applies, and the pause keeps one route in flight at a time. Standard
library only.

Road events count at the hour the vehicle reaches them: two passes compare
trip by trip only from the same `--depart-at` (README.md).
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
    osrmJson__TOKEN__
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

ALTERNATIVES = """
query Alternatives($token: String!) {
  routeAlternatives(token: $token) { status osrmJson routes { distanceM durationS } }
}
"""

VEHICLE ={"kind": "OVERCAB", "heightM": 3.3, "widthM": 2.3, "lengthM": 7.4, "weightT": 3.5}


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


def post(args, client, document, variables):
    """One GraphQL request from `client`: its HTTP status, the answer, the
    milliseconds the client waited, its size and its errors."""
    body = json.dumps({"query": document, "variables": variables}).encode()
    req = urllib.request.Request(args.api, data=body, headers={
        "Content-Type": "application/json",
        "X-Forwarded-For": client,
        "User-Agent": "lunaway-route-battery (+https://lunaway.net)",
    })
    errors = []
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read()
            http = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        http = e.code
    except OSError as e:
        raw = b""
        http = 0
        errors.append({"message": str(e)})
    ms = round((time.monotonic() - t0) * 1000)
    try:
        answer = json.loads(raw) if raw else {}
    except ValueError:
        answer = {}
    errors += [
        {"message": e.get("message"), "code": (e.get("extensions") or {}).get("code")}
        for e in answer.get("errors") or []
    ]
    return http, answer, ms, len(raw), errors


def ask(args, n, t, avoid):
    """One route request, and its alternatives with `--later`; the line
    written for it."""
    variables = {"input": {
        "origin": {"lat": float(t["from_lat"]), "lon": float(t["from_lon"]), "vehiclePosition": False},
        "destination": {"lat": float(t["to_lat"]), "lon": float(t["to_lon"])},
        "vehicle": VEHICLE,
        "options": avoid,
        "alternatives": args.alternatives,
        "language": "FR",
    }}
    if args.depart_at:
        variables["input"]["departAt"] = args.depart_at
    document = DOCUMENT.replace("__TOKEN__", "\n    alternativesToken" if args.later else "")
    client = address(n + args.offset)
    row = {"id": t["id"], "band": int(t["band"]), "straight_km": float(t["straight_km"]),
           "avoid": args.avoid, "later": args.later, "depart_at": args.depart_at,
           "started": datetime.now(timezone.utc).isoformat()}
    row["http"], answer, row["ms"], row["bytes"], errors = post(args, client, document, variables)
    row["ended"] = datetime.now(timezone.utc).isoformat()
    if errors:
        row["errors"] = errors
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
        row["avoided"] = [e.get("id") for e in r.get("avoidedRoadEvents") or []]
        row["reasons"] = [x["kind"] for x in r.get("noRouteReasons") or []]
        row["graph"] = (r.get("graph") or {}).get("id")
        token = r.get("alternativesToken")
        if token:
            _, later, row["later_ms"], _, errors = post(args, client, ALTERNATIVES, {"token": token})
            a = (later.get("data") or {}).get("routeAlternatives") or {}
            row["alternatives_status"] = a.get("status") or errors
            osrm = json.loads(a.get("osrmJson") or "{}")
            row["alt_routes"] = [{"m": x["distanceM"], "s": x["durationS"]} for x in a.get("routes") or []]
            row["alt_geometry"] = [digest(x.get("geometry")) for x in osrm.get("routes", [])]
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
    p.add_argument("--depart-at", help="the trips' departure (RFC 3339, an hour ago to 30 days ahead); "
                   "road events count at the hour the vehicle reaches them")
    p.add_argument("--later", action="store_true",
                   help="the best route alone with alternativesToken, then routeAlternatives")
    run(p.parse_args())


if __name__ == "__main__":
    main()
