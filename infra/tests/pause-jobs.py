"""Checks infra/server/pause-jobs.sh, which pauses the long jobs of the
lunaway CLI while a deploy migrates the database, on a copy run against
fakes of systemctl, systemd-run, psql (through runuser), sleep and date
(no server, no root):

1. only the running units whose processes run the CLI of a release are
   paused, never the API, the migrations, another program, a unit with an
   unexpected name or one too long for its sessions' name, nor a job none
   of whose sessions carries its name; a resume lets each one go on and
   stops the timer that would resume them otherwise;
2. a job is stopped only between two of its transactions, and started
   again at once when the stop landed inside one;
3. a job that never leaves its transaction, another session that keeps a
   transaction open, or a database that fails the check, ends the pause in
   failure with every job going on;
4. the jobs an interrupted deploy left paused go on before a new pause.

    python3 infra/tests/pause-jobs.py
"""
import json
import os
import pathlib
import stat
import subprocess
import sys

INFRA = pathlib.Path(__file__).resolve().parent.parent
REPO = INFRA.parent
SCRATCH = pathlib.Path(os.environ.get("LUNAWAY_SCRATCH_DIR", REPO / "data/tmp/infra")) / "pause-jobs-test"
CLI = "/opt/lunaway/releases/20261009T100000Z-0123456789ab/lunaway"

FAKE = r'''#!/usr/bin/env python3
"""A fake of %(name)s for infra/tests/pause-jobs.py."""
import json, pathlib, sys
state_path = pathlib.Path(%(state)r)
s = json.loads(state_path.read_text())
args = sys.argv[1:]
out = ""
name = %(name)r
if name == "date":
    out = str(int(s["clock"]))
elif name == "sleep":
    s["clock"] += float(args[0])
elif name == "systemctl":
    if args[0] == "list-units":
        out = "".join(f"{u} loaded active running x\n" for u in s["units"])
        if s.get("list_fails"):
            print(out, end="")
            state_path.write_text(json.dumps(s))
            sys.exit(1)
    elif args[0] == "show":
        out = f"/system.slice/{args[-1]}"
    elif args[0] == "kill":
        sig = next(a.split("=", 1)[1] for a in args if a.startswith("--signal="))
        s["log"].append(f"{sig} {args[-1]}")
    else:
        s["log"].append(" ".join(args))
elif name == "systemd-run":
    s["log"].append("systemd-run " + " ".join(a for a in args if a.startswith("--")))
elif name == "runuser":
    sql = sys.stdin.read()
    var = next((args[i + 1] for i, a in enumerate(args) if a == "-v" and args[i + 1].startswith("name=")), "name=")
    who = var.split("=", 1)[1]
    if "-- sessions" in sql:
        unit = who.removeprefix("lunaway:")
        seq = s["busy"].get(unit, [0])
        busy = seq.pop(0) if len(seq) > 1 else seq[0]
        named = s["named"].get(unit, 2)
        out = f"{named} {min(busy, named)}"
        s["log"].append(f"busy {unit} {out}")
    elif "-- holding" in sql:
        seq = s["holding"]
        out = seq.pop(0) if len(seq) > 1 else seq[0]
        if out == "ERROR":
            state_path.write_text(json.dumps(s))
            sys.exit(2)
state_path.write_text(json.dumps(s))
if out:
    print(out)
'''


def setup(units, busy=None, holding=None, left_paused=None, named=None):
    """A scratch tree for one case: the script, the fakes, /proc and the
    cgroups of `units` ({unit: executable or None for none}), and the
    fakes' state."""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    for sub in ("bin", "proc", "cgroup"):
        (SCRATCH / sub).mkdir(exist_ok=True)
    state = SCRATCH / "state.json"
    script = (INFRA / "server/pause-jobs.sh").read_text()
    for line in ("\nneed_root\n", "STATE=/run/lunaway-paused-jobs\n",
                 "PROC=/proc\n", "CGROUP=/sys/fs/cgroup\n"):
        assert line in script, f"pause-jobs.sh no longer has {line!r}"
    script = script.replace("\nneed_root\n", "\n")
    script = script.replace("STATE=/run/lunaway-paused-jobs\n", f"STATE={SCRATCH}/paused\n")
    script = script.replace("PROC=/proc\n", f"PROC={SCRATCH}/proc\n")
    script = script.replace("CGROUP=/sys/fs/cgroup\n", f"CGROUP={SCRATCH}/cgroup\n")
    (SCRATCH / "pause-jobs.sh").write_text(script)
    for name in ("date", "sleep", "systemctl", "systemd-run", "runuser"):
        f = SCRATCH / "bin" / name
        f.write_text(FAKE % {"name": name, "state": str(state)})
        f.chmod(f.stat().st_mode | stat.S_IXUSR)
    for pid, (unit, exe) in enumerate(units.items(), start=100):
        cg = SCRATCH / "cgroup/system.slice" / unit
        cg.mkdir(parents=True, exist_ok=True)
        (cg / "cgroup.procs").write_text(f"{pid}\n")
        p = SCRATCH / "proc" / str(pid)
        p.mkdir(exist_ok=True)
        link = p / "exe"
        if link.is_symlink():
            link.unlink()
        if exe:
            link.symlink_to(exe)
    paused = SCRATCH / "paused"
    if left_paused:
        paused.write_text("".join(f"{u}\n" for u in left_paused))
    elif paused.exists():
        paused.unlink()
    state.write_text(json.dumps({"clock": 1000.0, "units": list(units), "busy": busy or {},
                                 "named": named or {}, "holding": holding or [""], "log": []}))


def run(action, wait=30):
    env = dict(os.environ, PATH=f"{SCRATCH / 'bin'}:{os.environ['PATH']}", LUNAWAY_PAUSE_WAIT=str(wait))
    r = subprocess.run(["bash", str(SCRATCH / "pause-jobs.sh"), action], env=env,
                       capture_output=True, text=True, timeout=60)
    s = json.loads((SCRATCH / "state.json").read_text())
    paused = (SCRATCH / "paused").read_text().split() if (SCRATCH / "paused").exists() else []
    return r.returncode, [l for l in s["log"] if not l.startswith("busy ")], paused, r.stdout + r.stderr


failures = 0


def check(name, got, want):
    global failures
    if got == want:
        print(f"ok   {name}")
    else:
        failures += 1
        print(f"FAIL {name}\n     got  {got!r}\n     want {want!r}")


A, B = "lunaway-content-refresh.service", "lunaway-conflate-worker.service"
EVERY = {A: CLI, B: CLI, "lunaway-api.service": "/opt/lunaway/releases/20261009T100000Z-0123456789ab/lunaway-api",
         "lunaway-migrate.service": CLI, "lunaway-tiles.service": "/usr/local/bin/pmtiles",
         "lunaway-x;id.service": CLI, f"lunaway-{'a' * 40}.service": CLI}

# 1. Which units, and a resume.
setup(EVERY)
code, log, paused, out = run("pause")
check("pause succeeds", code, 0)
check("the CLI's jobs alone are stopped", [l for l in log if l.startswith("SIG")], [f"SIGSTOP {A}", f"SIGSTOP {B}"])
check("they are kept for the resume", paused, [A, B])
check("a timer resumes them should the deploy not",
      any(l.startswith("systemd-run --quiet --unit=lunaway-resume-jobs --on-active=") for l in log), True)
code, log, paused, out = run("resume")
check("resume succeeds", code, 0)
check("resume lets each one go on", [l for l in log if l.startswith("SIG")], [f"SIGSTOP {A}", f"SIGSTOP {B}", f"SIGCONT {A}", f"SIGCONT {B}"])
check("nothing stays paused", paused, [])
check("the timer is stopped", "stop lunaway-resume-jobs.timer" in log, True)

# 2. Between two transactions only.
setup({A: CLI}, busy={A: [1, 1, 0, 0]})
code, log, paused, out = run("pause")
check("a job in a transaction is stopped once out of it", (code, [l for l in log if l.startswith("SIG")]), (0, [f"SIGSTOP {A}"]))
setup({A: CLI}, busy={A: [0, 1, 0, 0]})
code, log, paused, out = run("pause")
check("a stop inside a transaction is undone, then done again", (code, [l for l in log if l.startswith("SIG")], paused),
      (0, [f"SIGSTOP {A}", f"SIGCONT {A}", f"SIGSTOP {A}"], [A]))

# 3. Failures leave every job going.
setup({B: CLI, A: CLI}, busy={A: [1]})
code, log, paused, out = run("pause", wait=3)
check("a job never out of its transaction fails the pause", code != 0 and "nothing was migrated" in out, True)
check("the jobs paused before it go on", [l for l in log if l.startswith("SIG")], [f"SIGSTOP {B}", f"SIGCONT {B}"])
check("nothing stays paused after a failure", paused, [])
setup({A: CLI}, holding=["pg_dump 4242", "pg_dump 4242", ""])
code, log, paused, out = run("pause")
check("a long transaction elsewhere is waited for", (code, paused), (0, [A]))
setup({A: CLI}, holding=["lunaway:lunaway-ingest-osm.service 4243"])
code, log, paused, out = run("pause", wait=5)
check("a transaction that stays open fails the pause", code != 0 and "lunaway-ingest-osm" in out, True)
check("and the jobs go on", ([l for l in log if l.startswith("SIG")], paused), ([f"SIGSTOP {A}", f"SIGCONT {A}"], []))

setup({A: CLI, B: CLI}, holding=["ERROR"])
code, log, paused, out = run("pause")
check("a database that fails the check fails the pause", code != 0, True)
check("and lets the jobs it stopped go on", ([l for l in log if l.startswith("SIG")], paused),
      ([f"SIGSTOP {A}", f"SIGSTOP {B}", f"SIGCONT {A}", f"SIGCONT {B}"], []))

# An error while listing the jobs, in a subshell, neither resumes the jobs
# nor stops the safety timer while the pause goes on.
setup({A: CLI})
st = json.loads((SCRATCH / "state.json").read_text())
st["list_fails"] = True
(SCRATCH / "state.json").write_text(json.dumps(st))
code, log, paused, out = run("pause")
check("a failed listing still pauses what it listed", (code, paused), (0, [A]))
armed = next(i for i, l in enumerate(log) if l.startswith("systemd-run"))
check("and keeps the safety timer", any(l.startswith("stop lunaway-resume-jobs") for l in log[armed:]), False)

# A job none of whose sessions carries its name (a CLI from before the
# names) is left running: stopped blindly, it could hold its locks.
setup({A: CLI, B: CLI}, named={A: 0})
code, log, paused, out = run("pause")
check("a job without named sessions is not stopped", (code, [l for l in log if l.startswith("SIG")], paused),
      (0, [f"SIGSTOP {B}"], [B]))

# 4. What an interrupted deploy left.
setup({A: CLI}, left_paused=["lunaway-ingest-osm.service"])
code, log, paused, out = run("pause")
check("jobs left paused go on first", [l for l in log if l.startswith("SIG")],
      ["SIGCONT lunaway-ingest-osm.service", f"SIGSTOP {A}"])
check("and only the new pause is kept", paused, [A])

# The scratch files, by name.
for name in ("state.json", "paused", "paused.new", "pause-jobs.sh"):
    f = SCRATCH / name
    if f.exists():
        f.unlink()
if failures:
    print(f"{failures} failure(s)")
    sys.exit(1)
print("all pause-jobs checks passed")
