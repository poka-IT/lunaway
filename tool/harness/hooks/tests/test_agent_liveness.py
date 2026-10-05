#!/usr/bin/env python3
"""Tests for the background-agent liveness guard.
Run: python3 tests/test_agent_liveness.py

The guard exists because an orchestrator waited 20 hours on a wedged agent
(2026-09-26): a stuck agent sends no completion notification, so only a
watchdog on its transcript's mtime can wake the orchestrator.

Dependency-free so it runs on any contributor machine with a bare python.
"""

import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import agent_liveness as live

FAILURES = []


def check(label, got, want):
    if got != want:
        FAILURES.append("%s: got %r, want %r" % (label, got, want))


def transcript(directory, agent_id, last_stop, age_secs, now, description="lot"):
    path = os.path.join(directory, "agent-%s.jsonl" % agent_id)
    entries = [
        {"type": "user", "message": {"content": "go"}},
        {"type": "assistant", "message": {"stop_reason": last_stop, "content": []}},
    ]
    if last_stop == "tool_use":
        entries.append({"type": "user", "message": {"content": [{"type": "tool_result"}]}})
    with open(path, "w") as fh:
        fh.write("\n".join(json.dumps(e) for e in entries) + "\n")
    os.utime(path, (now - age_secs, now - age_secs))
    with open(os.path.join(directory, "agent-%s.meta.json" % agent_id), "w") as fh:
        json.dump({"description": description}, fh)


NOW = 2_000_000_000

with tempfile.TemporaryDirectory() as d:
    transcript(d, "finished", "end_turn", 5 * 3600, NOW)
    transcript(d, "fresh", "tool_use", 60, NOW)
    check(
        "a finished agent does not count, a fresh one runs",
        [a[0] for a in live.running_agents(d, NOW)],
        ["fresh"],
    )
    check("fresh agents alone are running", live.check_once(d, NOW)[0], "running")
    check(
        "running agents without a watchdog keep the turn going",
        live.stop_decision(d, NOW, alive=False) is not None,
        True,
    )
    check(
        "with a watchdog armed the turn may end",
        live.stop_decision(d, NOW, alive=True),
        None,
    )

    transcript(d, "wedged", "tool_use", 20 * 3600, NOW, "Android lot")
    state, agents = live.check_once(d, NOW)
    check("an agent silent 20 h is stale", (state, [a[0] for a in agents]), ("stale", ["wedged"]))
    decision = live.stop_decision(d, NOW, alive=True)
    check(
        "a stale agent blocks the turn even with a watchdog",
        decision is not None and "Android lot" in decision,
        True,
    )

    live.snooze(d, "wedged", minutes=30, now=NOW)

    def stale_ids(at):
        state, agents = live.check_once(d, at)
        return [a[0] for a in agents] if state == "stale" else []

    check(
        "a snoozed agent is not stale until the snooze ends",
        "wedged" in stale_ids(NOW + 29 * 60),
        False,
    )
    check("a snooze expires on its own", "wedged" in stale_ids(NOW + 31 * 60), True)

    with open(os.path.join(d, live.ACK_FILE), "a") as fh:
        fh.write("wedged\n")
    check(
        "an agent stopped and acknowledged no longer counts",
        live.check_once(d, NOW)[0],
        "running",
    )

with tempfile.TemporaryDirectory() as d:
    transcript(d, "only", "end_turn", 10, NOW)
    check("nothing running is done", live.check_once(d, NOW), ("done", []))
    check("an idle session may end its turn", live.stop_decision(d, NOW, alive=False), None)

with tempfile.TemporaryDirectory() as d:
    transcript(d, "resumed", "end_turn", 30, NOW)
    with open(os.path.join(d, "agent-resumed.jsonl"), "a") as fh:
        fh.write(json.dumps({"type": "attachment"}) + "\n")
        fh.write(json.dumps({"type": "user", "message": {"content": "one more fix"}}) + "\n")
    check(
        "an agent resumed after its end_turn runs again",
        [a[0] for a in live.running_agents(d, NOW)],
        ["resumed"],
    )

with tempfile.TemporaryDirectory() as d:
    transcript(d, "only", "end_turn", 10, int(time.time()))
    check(
        "the watchdog waits a few polls before calling it done, so an agent it "
        "was armed for has time to write its first entry",
        live.watch(d, stale_secs=900, poll_secs=0, max_polls=2, done_polls=3),
        1,
    )
    check(
        "then it calls it done",
        live.watch(d, stale_secs=900, poll_secs=0, max_polls=5, done_polls=3),
        0,
    )

check(
    "the subagents dir sits next to the session transcript",
    live.subagents_dir_of("/p/proj/abc.jsonl"),
    "/p/proj/abc/subagents",
)
check("no transcript, no dir", live.subagents_dir_of(None), None)

import time

with tempfile.TemporaryDirectory() as d:
    transcript(d, "wedged", "tool_use", 3600, int(time.time()))
    check(
        "the watchdog exits at once on a stale agent",
        live.watch(d, stale_secs=900, poll_secs=0, max_polls=2),
        3,
    )

if FAILURES:
    print("FAIL")
    for f in FAILURES:
        print("  " + f)
    sys.exit(1)
print("OK")
