# Route battery

A fixed set of 120 trips to measure a change of the routing (the engine,
its graph, the API's check) before and after, on the production backend.

| file | what |
|---|---|
| `trips.sql` | how the trips were drawn: motorhome areas without a height limit, five bands of straight-line distance (3 to 15, 15 to 80, 80 to 400, 400 to 800, 800 to 2 300 km), 12 starts in France and 12 in the graph's other countries per band, ordered by an md5 with a fixed salt |
| `trips.csv` | the trips drawn on 2026-10-11, the list every measurement uses: `band, from France, from country, to country, from lat, from lon, to lat, to lon, straight km`, no header, numbered from 0 in file order |
| `battery.py` | the app's route request for each trip, one at a time, against the API |
| `engine_sizes.py` | the engine alone, with the API's body: size and time of its answer by number of alternatives |
| `compare.py` | two passes trip by trip: times by band of route length, recalculations, statuses and lengths that changed |

Positions: © OpenStreetMap contributors, ODbL 1.0. Each endpoint is the
position of the OpenStreetMap record of a place; `trips.sql` keeps no other
source.

## Running it

On the backend, against the loopback, from a copy of this directory
(`scp -F ~/.config/lunaway/ssh_config -r infra/routing/bench lunaway:/tmp/`):

```bash
cd /tmp/bench
at=2026-10-12T12:00:00Z                                       # the same departure for every pass
python3 battery.py trips.csv base1.jsonl --depart-at $at                 # warms the engine's tiles
python3 battery.py trips.csv base2.jsonl --depart-at $at --offset 200    # the reference pass
python3 battery.py trips.csv later.jsonl --depart-at $at --offset 400 --later   # the app from 0.4
python3 battery.py trips.csv motorways.jsonl --avoid motorways --depart-at $at --offset 600
python3 engine_sizes.py trips.csv sizes.jsonl --only 101,117 --avoid motorways
python3 compare.py before-base2.jsonl after-base2.jsonl
```

- One request at a time with a pause of a second: a pass takes 4 to 6
  minutes and holds at most one of the engine's slots.
- Each request carries its own client address (`198.18.0.0/15`, the
  benchmarking range) so the route quota of 30 every ten minutes never
  applies; give each pass of the same ten minutes its own `--offset`.
- Without `--later` a request is the app 0.1.0's, every route in one
  answer; with it, the app's from 0.4: the best route alone, then
  `routeAlternatives` at once (`later_ms`, `alt_routes`).
- Each line of the output holds the trip number, its band, the status, the
  client's time (`ms`), each route's length (`m`) and duration, the
  digests of their shapes, the API's `recalculations`, the road events it
  went round (`avoided`), the size of the OSRM answer and any error. The
  API's journal (`route computed`) gives the time spent in the engine, the
  corridor and the check for the same requests, by their end time.
- Compare passes trip by trip: same status, the first route's length within
  1 %, the recalculations. Times compare between second passes only (the
  first reads the tiles from disk).
- Road events count at the hour the vehicle reaches them: give every pass
  of a comparison the same `--depart-at`. Without it a trip departs now,
  and a route can drop out between two passes at different hours with
  nothing changed in the code. Trip 104 kept its three routes at 17:55 UTC
  on 2026-10-11 and lost the fastest at 19:35, which reached a slip road of
  the N176 closed from 07:00 UTC the next morning 12.5 hours after the
  start, at 06:27 from the first departure and 08:07 from the second
  (plan/research/131-memoire-serveur.md). Trips 82 and 83 lost their best
  route between 20:28 UTC on 2026-10-11 and 05:28 the next morning to a
  closure of the N70 from 06:00 UTC on 2026-10-12, reached about four
  hours after the start. Trip 52 had lost its best route at 20:27 to 16
  Dutch night-work closures 172 to 188 km from its start, in force until
  03:00 or 04:00 UTC, which the feed had dropped by 05:27
  (plan/research/135-routage-ancien-chemin.md). With a fixed departure,
  an event a feed adds or ends between two passes still changes them.
- Until 2026-10-12 a best route blocked beside a safe alternative was
  dropped without a recalculation in a request with its alternatives; it
  is now computed again around its blockers and the faster answer kept
  (`docs/architecture.md`, "Alternatives after the best route").

Redraw the list only for a reason a report states: every earlier
measurement is tied to this one.
