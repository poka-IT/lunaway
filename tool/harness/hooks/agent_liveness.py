#!/usr/bin/env python3
"""Liveness of background subagents: a Stop guard and a watchdog.

Ported from the Warren harness, where it was written.

Bought on 2026-09-26: an orchestrator launched four background agents, ended
its turn waiting for their completion notifications, and one of them wedged
inside a tool call. A wedged agent sends no notification, so nothing woke the
orchestrator for 20 hours while the work it owned sat dead. A rule already
said "watch a live progress signal, never completion alone"; it was read and
not applied. This makes it mechanical.

Two halves, one signal (the mtime of each subagent's transcript):

* `watch`: run it with `run_in_background`. It exits as soon as a running agent
  has been silent for more than the stale limit, or when none is running any
  more. A background command that exits wakes the orchestrator, which is the
  one wake-up that does not depend on the stuck agent.
* the Stop hook (no arguments): refuses to end the orchestrator's turn while a
  running agent is stale, or while agents run and no watchdog watches them.

An agent is finished when its last assistant entry ended its turn
(`stop_reason == "end_turn"`). One you stopped on purpose is recorded with
`ack`, so it no longer counts as running.
"""

import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import harness_common as common  # noqa: E402

STALE_SECS = 15 * 60
POLL_SECS = 60
ACK_FILE = ".lunaway-agents-acked"
SNOOZE_FILE = ".lunaway-agents-snoozed"
_TAIL_BYTES = 256 * 1024


def subagents_dir_of(transcript_path):
    """The subagents directory of the session whose transcript is given."""
    if not transcript_path:
        return None
    base = transcript_path[:-6] if transcript_path.endswith(".jsonl") else transcript_path
    return os.path.join(base, "subagents")


def _last_turn_entry(path):
    """The newest user or assistant entry, skipping attachments."""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - _TAIL_BYTES))
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") in ("assistant", "user"):
            return entry
    return None


def is_finished(path):
    """Its newest turn entry is an assistant message that ended the turn. A
    user entry after it is a pending tool result or a resume: running."""
    entry = _last_turn_entry(path)
    if not entry or entry.get("type") != "assistant":
        return False
    return (entry.get("message") or {}).get("stop_reason") == "end_turn"


def acked(subagents_dir):
    try:
        with open(os.path.join(subagents_dir, ACK_FILE)) as fh:
            return {l.strip() for l in fh if l.strip()}
    except OSError:
        return set()


def snoozed(subagents_dir):
    """{agent_id: until_unix} of the agents a human-readable reason let run."""
    out = {}
    try:
        with open(os.path.join(subagents_dir, SNOOZE_FILE)) as fh:
            for line in fh:
                parts = line.split()
                if len(parts) == 2:
                    out[parts[0]] = max(out.get(parts[0], 0), float(parts[1]))
    except (OSError, ValueError):
        pass
    return out


def snooze(subagents_dir, agent_id, minutes, now):
    """Let an agent that is visibly progressing stay silent `minutes` more."""
    with open(os.path.join(subagents_dir, SNOOZE_FILE), "a") as fh:
        fh.write("%s %d\n" % (agent_id, int(now + minutes * 60)))


def _description(subagents_dir, agent_id):
    try:
        with open(os.path.join(subagents_dir, "agent-%s.meta.json" % agent_id)) as fh:
            return json.load(fh).get("description") or ""
    except (OSError, ValueError):
        return ""


def running_agents(subagents_dir, now):
    """[(agent_id, silent_secs, description)] of the agents still running."""
    try:
        names = os.listdir(subagents_dir)
    except OSError:
        return []
    done = acked(subagents_dir)
    out = []
    for name in sorted(names):
        if not (name.startswith("agent-") and name.endswith(".jsonl")):
            continue
        agent_id = name[len("agent-"):-len(".jsonl")]
        if agent_id in done:
            continue
        path = os.path.join(subagents_dir, name)
        if is_finished(path):
            continue
        try:
            silent = max(0, int(now - os.path.getmtime(path)))
        except OSError:
            continue
        out.append((agent_id, silent, _description(subagents_dir, agent_id)))
    return out


def check_once(subagents_dir, now, stale_secs=STALE_SECS):
    """('stale', agents) | ('running', agents) | ('done', [])."""
    running = running_agents(subagents_dir, now)
    if not running:
        return "done", []
    quiet_until = snoozed(subagents_dir)
    stale = [a for a in running if a[1] > stale_secs and now >= quiet_until.get(a[0], 0)]
    if stale:
        return "stale", stale
    return "running", running


def _describe(agents):
    return "\n".join(
        "  - %s (%s): silent for %d min" % (a, d or "no description", s // 60)
        for a, s, d in agents
    )


def stale_advice(agents):
    return (
        "Background agent(s) silent for too long, probably wedged:\n%s\n"
        "Read the last entries of each transcript (tail, never the whole file), "
        "then either let it be if it is visibly progressing (a long build that "
        "writes nothing: say so, then\n"
        "  python3 %s snooze <subagents_dir> <agent_id> <minutes>\n"
        "), or stop it with TaskStop, record it with\n"
        "  python3 %s ack <subagents_dir> <agent_id>\n"
        "and relaunch or report the gap to the user."
        % (_describe(agents), os.path.abspath(__file__), os.path.abspath(__file__))
    )


def watch_command(subagents_dir):
    return 'python3 "%s" watch "%s"' % (os.path.abspath(__file__), subagents_dir)


def watchdog_alive(subagents_dir):
    try:
        out = subprocess.run(
            ["ps", "-axo", "command"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=5
        ).stdout
    except Exception:
        return True  # cannot tell: fail open
    marker = os.path.basename(__file__)
    return any(
        marker in line and " watch " in line and subagents_dir in line
        for line in out.splitlines()
    )


def stop_decision(subagents_dir, now, alive):
    """None to let the turn end, else the message that keeps it going."""
    state, agents = check_once(subagents_dir, now)
    if state == "stale":
        return stale_advice(agents)
    if state == "running" and not alive:
        return (
            "Background agents are running and nothing watches them:\n%s\n"
            "A wedged agent sends no completion notification, so ending the turn "
            "now can leave it dead for hours. Arm the watchdog first, with "
            "run_in_background (its exit wakes you):\n  %s"
            % (_describe(agents), watch_command(subagents_dir))
        )
    return None


def watch(subagents_dir, stale_secs, poll_secs, max_polls=None, done_polls=3):
    """Exit 3 on a stale agent, 0 once none has run for `done_polls` polls in a
    row: an agent the watchdog was armed for may not have written its first
    entry yet. `max_polls` bounds a test."""
    polls = 0
    quiet = 0
    while max_polls is None or polls < max_polls:
        polls += 1
        state, agents = check_once(subagents_dir, time.time(), stale_secs)
        if state == "stale":
            print(stale_advice(agents))
            return 3
        quiet = quiet + 1 if state == "done" else 0
        if quiet >= done_polls:
            print("No background agent is running any more.")
            return 0
        time.sleep(poll_secs)
    return 1


def stop_hook():
    payload = common.read_payload() or {}
    if not common.repo_root(payload.get("cwd")):
        common.allow()
    subagents_dir = subagents_dir_of(payload.get("transcript_path"))
    if not subagents_dir or not os.path.isdir(subagents_dir):
        common.allow()
    message = stop_decision(subagents_dir, time.time(), watchdog_alive(subagents_dir))
    if message:
        common.block(message)
    common.allow()


def main(argv):
    if len(argv) >= 3 and argv[1] == "watch":
        stale = int(os.environ.get("LUNAWAY_AGENT_STALE_MIN", STALE_SECS // 60)) * 60
        return watch(argv[2], stale, POLL_SECS)
    if len(argv) >= 5 and argv[1] == "snooze":
        snooze(argv[2], argv[3].strip(), int(argv[4]), time.time())
        return 0
    if len(argv) >= 4 and argv[1] == "ack":
        with open(os.path.join(argv[2], ACK_FILE), "a") as fh:
            fh.write(argv[3].strip() + "\n")
        return 0
    try:
        stop_hook()
    except SystemExit:
        raise
    except Exception:
        common.allow()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
