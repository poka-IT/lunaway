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
python3 battery.py trips.csv base1.jsonl                     # warms the engine's tiles
python3 battery.py trips.csv base2.jsonl --offset 200        # the reference pass
python3 battery.py trips.csv motorways.jsonl --avoid motorways --offset 400
python3 engine_sizes.py trips.csv sizes.jsonl --only 101,117 --avoid motorways
python3 compare.py before-base2.jsonl after-base2.jsonl
```

- One request at a time with a pause of a second: a pass takes 4 to 6
  minutes and holds at most one of the engine's slots.
- Each request carries its own client address (`198.18.0.0/15`, the
  benchmarking range) so the route quota of 30 every ten minutes never
  applies; give each pass of the same ten minutes its own `--offset`.
- Each line of the output holds the trip number, its band, the status, the
  client's time (`ms`), each route's length (`m`) and duration, the
  digests of their shapes, the API's `recalculations`, the size of the OSRM
  answer and any error. The API's journal (`route computed`) gives the
  time spent in the engine, the corridor and the check for the same
  requests, by their end time.
- Compare passes trip by trip: same status, the first route's length within
  1 %, the recalculations. Times compare between second passes only (the
  first reads the tiles from disk).

Redraw the list only for a reason a report states: every earlier
measurement is tied to this one.
