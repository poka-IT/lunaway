---
name: job-watching
description: Watch a long-running job (CI run, image build, fleet rollout, bench, cross-compile) or supervise a delegated sub-agent without going blind. Use whenever you are about to wait on something that can hang, or whenever you hand a multi-step mission to a sub-agent. Encodes the health-probe + time-budget + liveness-clause discipline that two real incidents cost hours to learn.
---

# Watching jobs and agents: silence is NOT progress

Two hard-won rules, both from real losses on a sibling project (Warren). They apply together:
one covers processes, the other covers agents.

## Job-watching discipline (learned 2026-07-08)

A completion-only watcher (`gh run watch`, "notify me when it exits") NEVER fires
on a hung job: a wedged build looks identical to a slow one, and an operator was
left waiting for hours on a rustc zombie deadlock a completion watcher could not
see.

Whenever you wait on ANY long-running job, systematically pair the completion
watcher with all three of:

1. **A periodic health probe** (every ~5 min): is there a live progress signal,
   CPU activity on the worker, a log line advancing, a step changing? A job
   `in_progress` with a dead progress signal is stalled. Investigate IMMEDIATELY,
   do not keep waiting.
2. **An explicit time budget** stated up front (e.g. "cold build: 90 min").
   Budget exceeded means investigate proactively, even if the health probe looks
   alive.
3. **Network-tolerant watchers**: a transient API error must not silently kill
   the watch (retry in a loop). A watcher that dies is re-armed, and its death is
   never read as a job verdict.

Every Lunaway CI job carries `timeout-minutes`, so an `in_progress` job past
its timeout is always investigable infrastructure, never a slow build.

## Agent-liveness discipline (learned 2026-07-21)

The rule above also applies to AGENTS, not just jobs. During a fleet rollout a deploy
sub-agent ended its turn "standing by for the monitor" after the rollout
process exited: nothing ever re-woke it, and its remaining mission sat idle for
50 minutes, invisibly, because the orchestrator's only monitor watched for the
teardown of machines that had never been created.

Two rules, BOTH mandatory whenever you delegate a long-running mission:

1. **Liveness clause in the agent's prompt.** The agent must never end its turn
   while mission steps remain. Passive "standing by" / "watching" states are
   forbidden: when the watched process exits (success OR failure), it immediately
   executes the remaining steps; if genuinely blocked, it reports the blockage
   instead of waiting.

   Paste this into every delegated mission prompt:

   > Liveness: never end your turn while mission steps remain. Do not "stand by"
   > or "wait for" anything. When the process you are watching exits, for any
   > reason, immediately execute the remaining steps. If you are genuinely
   > blocked, report the blockage and what you need; never idle.

2. **Orchestrator-side stall watchdog.** Pair every delegated mission with an
   independent monitor on a LIVE PROGRESS signal (agent transcript mtime
   advancing, log line moving, expected artifact appearing), with an explicit
   stall threshold (~15 min) that fires an alert so the orchestrator wakes or
   replaces the agent.

**A completion-only or teardown-only watcher is blind by construction when the
thing it watches was never created.** That is the failure mode both incidents
share: the watcher was correct about a state that never arrived.

## The mechanical half

`tool/harness/hooks/agent_liveness.py` is a Stop hook: it refuses to end the
orchestrator's turn while background agents run with no watchdog, or while
one has been silent for more than 15 minutes. Its block message gives the
`watch` command to run with `run_in_background`.

## Applying it

- Prefer `run_in_background` with a real progress probe over a blocking wait.
- State the time budget in your message to the user before you start waiting, so
  an overrun is visible to them too.
- When several nodes or repos are independent work, parallelize with one agent
  each and give every one of them the liveness clause.
