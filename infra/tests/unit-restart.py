"""Checks the retry of the backend's long imports after a failure, on the
unit files of infra/systemd (no server needed).

    python3 infra/tests/unit-restart.py

1. Every import of the `lunaway` CLI (`ingest ...`, `content refresh`,
   `road-events dialog-permanent`) whose next run is a day or more away
   runs again after the database left it (`RestartForceExitStatus=75`, the
   CLI's exit status then, and `RestartSec=`), with a start limit
   (`StartLimitBurst=`, `StartLimitIntervalSec=`), and after no other
   failure (no `Restart=`): a source that refused us is not asked again
   before its next run (`.claude/rules/data-sources.md`). A run killed by
   PostgreSQL's restart would otherwise wait for its next timer, a week for
   some (2026-10-08, `lunaway-content-refresh`).
2. Every one-off unit that retries stops for good: its window holds its
   whole burst of runs, each as long as its timeout allows (systemd arms
   `TimeoutStartSec=` again for every start command), plus the wait for a
   run of the units it is ordered after (`After=`, those of this directory,
   not their own waits), so a fourth start falls inside it and is refused.
   And the window ends before the next timer, so a unit that hit its limit
   still runs at its next date.
"""
import pathlib
import re
import sys

UNITS = pathlib.Path(__file__).resolve().parent.parent / "systemd"
IMPORT = re.compile(
    r"^ExecStart=/opt/lunaway/current/lunaway (ingest |content refresh|road-events dialog-permanent)",
    re.M,
)
SPAN_UNITS = {"us": 1e-6, "ms": 1e-3, "s": 1, "sec": 1, "min": 60, "m": 60, "h": 3600, "d": 86400, "w": 604800}
DAY = 86400.0


def span(text):
    """A systemd time span in seconds ("5d 1h", "15min", "90", "infinity")."""
    if text.strip() == "infinity":
        return float("inf")
    total = 0.0
    parts = re.findall(r"(\d+(?:\.\d+)?)\s*([a-z]*)", text.strip())
    if not parts or re.sub(r"[\d.\sa-z]", "", text):
        raise ValueError(f"unreadable time span {text!r}")
    for value, unit in parts:
        if unit not in SPAN_UNITS and unit != "":
            raise ValueError(f"unknown time unit in {text!r}")
        total += float(value) * SPAN_UNITS.get(unit, 1)
    return total


def period(calendar):
    """Shortest time between two elapses of an OnCalendar= value, seconds;
    only the forms the units use, any other one fails the check."""
    c = calendar.replace(" UTC", "").strip()
    if c == "hourly" or re.fullmatch(r"\*-\*-\* \*:\d\d", c):
        return 3600.0
    if m := re.fullmatch(r"\*:\d\d?/(\d+)", c):
        return float(m.group(1)) * 60
    if m := re.fullmatch(r"\*-\*-\* \d\d/(\d+):\d\d(:\d\d)?", c):
        return float(m.group(1)) * 3600
    if re.fullmatch(r"(Mon|Tue|Wed|Thu|Fri|Sat|Sun|%i)( \*-\*-\*)? \d\d:\d\d(:\d\d)?", c):
        return 7 * DAY
    if re.fullmatch(r"\*-\*-\d\d \d\d:\d\d(:\d\d)?", c):
        return 28 * DAY
    if re.fullmatch(r"\*-\*-\* \d\d:\d\d(:\d\d)?", c):
        return DAY
    raise ValueError(f"OnCalendar={calendar}: unknown form, teach this check")


def value(text, key):
    found = re.findall(rf"^{key}=(.*)$", text, re.M)
    return found[-1].strip() if found else None


def longest_run(text):
    """How long one run of a unit may take: `TimeoutStartSec=` for each of
    its start commands."""
    commands = len(re.findall(r"^ExecStart(Pre|Post)?=", text, re.M))
    return commands * span(value(text, "TimeoutStartSec") or "infinity")


def ordering_wait(text):
    """The longest run of the units of `After=` this directory holds: a
    start waits for theirs to end."""
    longest = 0.0
    for line in re.findall(r"^After=(.+)$", text, re.M):
        for unit in line.split():
            path = UNITS / re.sub(r"@[^.]+\.service$", "@.service", unit)
            if path.exists():
                longest = max(longest, longest_run(path.read_text()))
    return longest


def unit_period(name):
    """The time between two runs of a unit: its timer's, or a day for a unit
    another one pulls in (lunaway-cameras by the daily lunaway-enforcement,
    lunaway-cameras-osm after each daily routing graph)."""
    timer = UNITS / name.replace(".service", ".timer")
    if not timer.exists():
        return DAY
    text = timer.read_text()
    every = [period(c) for c in re.findall(r"^OnCalendar=(.+)$", text, re.M) if c]
    every += [span(s) for s in re.findall(r"^OnUnitActiveSec=(.+)$", text, re.M)]
    if not every:
        raise ValueError(f"{timer.name}: no OnCalendar= nor OnUnitActiveSec=, teach this check")
    return min(every)


failures = 0


def fail(message):
    global failures
    failures += 1
    print(f"FAIL {message}")


checked = 0
for path in sorted(UNITS.glob("*.service")):
    text = path.read_text()
    name = path.name
    restart = value(text, "Restart")
    try:
        every = unit_period(name)
    except ValueError as error:
        fail(f"{name}: {error}")
        continue
    forced = value(text, "RestartForceExitStatus")
    if IMPORT.search(text) and every >= DAY:
        if forced != "75":
            fail(f"{name}: an import run every {every / DAY:g} d without RestartForceExitStatus=75")
            continue
        if restart not in (None, "no"):
            fail(f"{name}: Restart={restart} asks a source that refused us again before its next run")
            continue
    if value(text, "Type") != "oneshot" or (restart in (None, "no") and not forced):
        continue
    checked += 1
    try:
        retry = span(value(text, "RestartSec") or "100ms")
        run = longest_run(text)
        wait = ordering_wait(text)
        window = span(value(text, "StartLimitIntervalSec") or "0")
    except ValueError as error:
        fail(f"{name}: {error}")
        continue
    burst = int(value(text, "StartLimitBurst") or 0)
    longest = burst * (run + retry + wait)
    if retry < 5 * 60:
        fail(f"{name}: RestartSec under 5 minutes retries into the same outage")
    if not 2 <= burst <= 5:
        fail(f"{name}: StartLimitBurst={burst}, wanted 2 to 5 runs")
    if window < longest:
        fail(f"{name}: {burst} runs of up to {run / 3600:g} h, {retry / 60:g} min apart, after"
             f" {wait / 3600:g} h of wait each, outlast StartLimitIntervalSec ({window / 3600:g} h):"
             " the retries never stop")
    if window >= every:
        fail(f"{name}: StartLimitIntervalSec ({window / 3600:g} h) reaches the next run ({every / 3600:g} h later)")
    print(f"ok   {name}: {burst} runs within {window / 3600:g} h (longest {longest / 3600:g} h), every {every / 3600:g} h")

if checked == 0:
    fail("no unit retries: the check found nothing to check")
print(f"{checked} units checked, {failures} failure(s)")
sys.exit(1 if failures else 0)
