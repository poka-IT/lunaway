#!/usr/bin/env python3
"""Lunaway's external probe (docs/deploy.md, "The external probe").

The status page runs on the server it watches, so an outage of that server
takes the page down with it. This probe runs on GitHub's machines
(.github/workflows/external-probe.yml, every 15 minutes) and meets the
public endpoints the way a client does:

  site    GET https://lunaway.net/ answers 200
  api     GET https://api.lunaway.net/health answers 200 and "ok"
  tiles   the basemap's TileJSON is version 3.0.0, and a z14 tile over
          Paris comes back with more than 1000 bytes as received (gzip)
  search  the status page's check "Addresses (Europe)": complete, the
          first address in Germany
  route   the status page's "Witness route": a 3.3 m motorhome in Limoges
          goes round the 2.7 m bridge, status OK and longer than 1000 m

A check fails when three attempts, 20 seconds apart, all fail. The probe
then opens the GitHub issue "ops: alerte" as github-actions[bot], or
updates the one it opened, and closes it at the first run where every check
passes. The maintainer's Mac writes an issue of the same title as poka-IT
(infra/ops/mac/lunaway-ops.sh): each job only touches the issue its own
account opened.

  python3 infra/ops/probe/external-probe.py                  # the workflow, GITHUB_TOKEN set
  python3 infra/ops/probe/external-probe.py --dry-run        # real checks, nothing written
  python3 infra/ops/probe/external-probe.py --dry-run --fail api   # the failing path

Exit status: 0 when every check passes, 1 when one fails, 2 when the issue
could not be read or written.

The issue and the job's log are public. They carry the checks' names and a
short reason built here (an HTTP status, a timeout, a failed condition, a
size or a distance); the only text taken from a response is an enum value
such as NO_ROUTE, and the only addresses named are the public hostnames
below.

Settings, from the environment (set by GitHub Actions):
  GITHUB_TOKEN        the job's token (issues: write); not needed by --dry-run
  GITHUB_REPOSITORY   owner/name of the issue's repository, poka-IT/lunaway
  GITHUB_SERVER_URL, GITHUB_RUN_ID   the run's link in the issue
"""

import argparse
import datetime
import gzip
import http.client
import json
import os
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from typing import Callable, NamedTuple

USER_AGENT = "Lunaway external probe (+https://lunaway.net)"
SITE = "https://lunaway.net/"
API = "https://api.lunaway.net"
TILES = "https://tiles.lunaway.net"
GITHUB_API = "https://api.github.com"
DEFAULT_REPO = "poka-IT/lunaway"
TITLE = "ops: alerte"
BOT_LOGIN = "github-actions[bot]"

ATTEMPTS = 3
PAUSE_S = 20
# The site's page and a tile weigh well under this; a body past it is
# read no further, which keeps a broken server from filling the runner.
BODY_LIMIT = 8 * 1024 * 1024
# 1000 open issues and pull requests: far beyond what the repository holds.
MAX_ISSUE_PAGES = 10

# The exact queries of the status page's checks "Addresses (Europe)" and
# "Witness route" (infra/ops/gatus/config.yaml); infra/tests/external-probe.py
# fails when the two drift apart.
SEARCH_QUERY = (
    '{ searchAll(text: "unter den linden berlin", near: {lat: 52.5, lon: 13.4},'
    ' addresses: 1, language: "de") { addresses { countryCode } addressesComplete } }'
)
ROUTE_QUERY = (
    "{ route(input: {origin: {lat: 45.84719, lon: 1.28476},"
    " destination: {lat: 45.8451, lon: 1.28637},"
    " vehicle: {kind: OVERCAB, heightM: 3.3, widthM: 2.3, lengthM: 7.4, weightT: 3.5}})"
    " { status routes { distanceM } } }"
)


class Failed(Exception):
    """A failed attempt. Its message goes to the public log and issue, so
    this script writes it; at most an enum value comes from a response
    (_word)."""


class IssueError(Exception):
    """The GitHub issue could not be read or written."""


class Response(NamedTuple):
    status: int
    headers: dict
    body: bytes

    def json(self, what):
        raw = self.body
        try:
            if self.headers.get("content-encoding", "").lower() == "gzip":
                raw = gzip.decompress(raw)
            return json.loads(raw)
        except (OSError, EOFError, ValueError):
            raise Failed(f"{what} illisible") from None


def fetch(method, url, *, body=None, headers=None, timeout=20, opener=urllib.request.urlopen):
    """One request, its body read up to BODY_LIMIT within `timeout` seconds
    in all. An HTTP error status is returned like any answer; what keeps
    the request from completing raises Failed."""
    request = urllib.request.Request(url, data=body, method=method)
    request.add_header("User-Agent", USER_AGENT)
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    deadline = time.monotonic() + timeout
    try:
        try:
            response = opener(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            chunks, size = [], 0
            while size < BODY_LIMIT:
                if time.monotonic() > deadline:
                    raise Failed(f"réponse incomplète après {timeout} s")
                chunk = response.read(65536)
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
            return Response(
                response.getcode(),
                {k.lower(): v for k, v in response.headers.items()},
                b"".join(chunks),
            )
    except Failed:
        raise
    except TimeoutError:
        raise Failed(f"pas de réponse en {timeout} s") from None
    except urllib.error.URLError as error:
        if isinstance(error.reason, TimeoutError):
            raise Failed(f"pas de réponse en {timeout} s") from None
        if isinstance(error.reason, ssl.SSLError):
            raise Failed("échec de la négociation TLS ou du certificat") from None
        raise Failed("connexion impossible") from None
    except ssl.SSLError:
        raise Failed("échec de la négociation TLS ou du certificat") from None
    except (OSError, http.client.HTTPException):
        raise Failed("connexion interrompue") from None


def _status_ok(response, what=""):
    if response.status != 200:
        prefix = f"{what} : " if what else ""
        raise Failed(f"{prefix}HTTP {response.status}")


def _obj(value):
    return value if isinstance(value, dict) else {}


def _first(value):
    return _obj(value[0]) if isinstance(value, list) and value else {}


def _number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _word(value):
    """An enum value from a response, kept only when it looks like one."""
    if isinstance(value, str) and re.fullmatch(r"[A-Z][A-Z_]{0,31}", value):
        return value
    return "inattendu"


def check_site(get):
    _status_ok(get("GET", SITE, timeout=20))


def check_api(get):
    response = get("GET", f"{API}/health", timeout=20)
    _status_ok(response)
    if response.body.strip() != b"ok":
        raise Failed("la réponse n'est pas « ok »")


def check_tiles(get):
    tilejson = get("GET", f"{TILES}/planet.json", timeout=20)
    _status_ok(tilejson, "TileJSON")
    if _obj(tilejson.json("TileJSON")).get("tilejson") != "3.0.0":
        raise Failed("TileJSON : version différente de 3.0.0")
    # The app asks for compressed tiles; the bytes counted are those that
    # crossed the network, as a client receives them.
    tile = get("GET", f"{TILES}/planet/14/8299/5636.mvt", headers={"Accept-Encoding": "gzip"}, timeout=20)
    _status_ok(tile, "tuile")
    if len(tile.body) <= 1000:
        raise Failed(f"tuile de {len(tile.body)} octets, plus de 1000 attendus")
    return f"tile of {len(tile.body)} bytes"


def _graphql(get, query, timeout):
    response = get(
        "POST",
        f"{API}/graphql",
        body=json.dumps({"query": query}).encode(),
        headers={"Content-Type": "application/json"},
        timeout=timeout,
    )
    _status_ok(response)
    data = _obj(response.json("réponse GraphQL")).get("data")
    if not isinstance(data, dict):
        raise Failed("réponse GraphQL sans données")
    return data


def check_search(get):
    found = _obj(_graphql(get, SEARCH_QUERY, 20).get("searchAll"))
    if found.get("addressesComplete") is not True:
        raise Failed("addressesComplete n'est pas vrai (un géocodeur en retard ou arrêté)")
    if _first(found.get("addresses")).get("countryCode") != "DE":
        raise Failed("la première adresse trouvée n'est pas en Allemagne")


def check_route(get):
    route = _obj(_graphql(get, ROUTE_QUERY, 30).get("route"))
    if route.get("status") != "OK":
        raise Failed(f"statut {_word(route.get('status'))}")
    distance = _number(_first(route.get("routes")).get("distanceM"))
    if distance is None:
        raise Failed("itinéraire sans distance")
    if distance <= 1000:
        raise Failed(f"itinéraire de {round(distance)} m, plus de 1000 m attendus (sous le pont de 2,7 m ?)")
    return f"{round(distance)} m"


class Check(NamedTuple):
    id: str
    label: str
    run: Callable


CHECKS = (
    Check("site", "Site web (https://lunaway.net/)", check_site),
    Check("api", "API (https://api.lunaway.net/health)", check_api),
    Check("tiles", "Fond de carte (tiles.lunaway.net : TileJSON et une tuile z14 sur Paris)", check_tiles),
    Check("search", "Recherche d'adresses en Europe (« unter den linden berlin »)", check_search),
    Check("route", "Itinéraire témoin (camping-car de 3,3 m à Limoges)", check_route),
)
LABELS = {c.id: c.label for c in CHECKS}


def run_check(check, get, sleep, log, attempts=ATTEMPTS, pause=PAUSE_S):
    """None when one attempt passes, else the reason of the last one."""
    reason = None
    for attempt in range(1, attempts + 1):
        started = time.monotonic()
        try:
            detail = check.run(get)
        except Failed as error:
            reason = str(error)
        except Exception as error:  # a bug of this script counts as a failure, so the issue shows it
            reason = f"erreur interne de la sonde ({type(error).__name__})"
        else:
            extra = f", {detail}" if detail else ""
            log(f"{check.id}: ok at attempt {attempt} ({time.monotonic() - started:.1f} s{extra})")
            return None
        log(f"{check.id}: attempt {attempt}/{attempts} failed: {reason}")
        if attempt < attempts:
            sleep(pause)
    return reason


def run_checks(get, sleep, log, forced=()):
    """The failing checks, {id: reason} in the order of CHECKS. The checks
    run side by side: one after the other, three slow failures each would
    outlast the job's timeout."""
    failing = {c.id: "échec forcé par --fail (exercice)" for c in CHECKS if c.id in forced}
    to_run = [c for c in CHECKS if c.id not in forced]
    if to_run:
        with ThreadPoolExecutor(max_workers=len(to_run)) as pool:
            futures = {c.id: pool.submit(run_check, c, get, sleep, log) for c in to_run}
        for check_id, future in futures.items():
            reason = future.result()
            if reason is not None:
                failing[check_id] = reason
    return {c.id: failing[c.id] for c in CHECKS if c.id in failing}


MARKER_RE = re.compile(r"<!-- failing: ([a-z,]*) -->")


def marker(check_ids):
    return f"<!-- failing: {','.join(sorted(check_ids))} -->"


def recorded_failing(body):
    """The set of failing checks an issue body records, None without one."""
    found = MARKER_RE.search(body or "")
    if not found:
        return None
    return frozenset(x for x in found.group(1).split(",") if x)


def probe_issues(issues):
    """The open issues this probe opened, oldest first. Anyone can open an
    issue with this title, and the Mac's job writes one as poka-IT: only the
    author tells them apart."""
    mine = [
        i
        for i in issues
        if isinstance(i, dict)
        and i.get("title") == TITLE
        and _obj(i.get("user")).get("login") == BOT_LOGIN
        and "pull_request" not in i
        and i.get("state", "open") == "open"
    ]
    return sorted(mine, key=lambda i: i.get("number", 0))


def _failing_lines(failing):
    return [f"- {LABELS.get(check_id, check_id)} : {reason}" for check_id, reason in failing.items()]


def issue_body(failing, now, run_url):
    return "\n".join(
        [
            "Sonde externe (GitHub Actions, toutes les 15 minutes) : "
            "`.github/workflows/external-probe.yml`, `infra/ops/probe/external-probe.py`.",
            "",
            f"Contrôles en échec le {now}, après trois essais à 20 secondes d'intervalle :",
            "",
            *_failing_lines(failing),
            "",
            f"Exécution : {run_url}",
            "",
            "L'issue se ferme d'elle-même à la première exécution où tout repasse au vert.",
            "",
            marker(failing),
        ]
    )


class Action(NamedTuple):
    kind: str  # create, comment, update, close
    number: int | None
    text: str | None


def plan(failing, issues, now, run_url):
    """The writes that bring the issue in line with the checks.

    A comment notifies whoever watches the repository, a body edit does not:
    the body follows every run, a comment marks only a change in which checks
    fail, so a long outage does not post one every 15 minutes. The comment
    goes before the edit: when the edit then fails, the next run sees the
    old set and comments again, where the other order would lose it."""
    mine = probe_issues(issues)
    if failing:
        body = issue_body(failing, now, run_url)
        if not mine:
            return [Action("create", None, body)]
        issue = mine[0]
        actions = []
        if recorded_failing(issue.get("body")) != frozenset(failing):
            comment = "\n".join(
                [f"Les contrôles en échec ont changé le {now} :", "", *_failing_lines(failing), "", f"Exécution : {run_url}"]
            )
            actions.append(Action("comment", issue["number"], comment))
        actions.append(Action("update", issue["number"], body))
        return actions
    actions = []
    for issue in mine:
        actions.append(Action("comment", issue["number"], f"De nouveau au vert le {now}.\n\nExécution : {run_url}"))
        actions.append(Action("close", issue["number"], None))
    return actions


class GitHub:
    """The few calls of the REST API the probe needs, on one repository."""

    def __init__(self, repo, token, opener=urllib.request.urlopen):
        self.repo = repo
        self.token = token
        self.opener = opener

    def _call(self, method, path, payload=None):
        request = urllib.request.Request(
            f"{GITHUB_API}/repos/{self.repo}{path}",
            data=None if payload is None else json.dumps(payload).encode(),
            method=method,
        )
        request.add_header("User-Agent", USER_AGENT)
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        if payload is not None:
            request.add_header("Content-Type", "application/json")
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        where = f"{method} {path.split('?')[0]}"
        try:
            with self.opener(request, timeout=30) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            raise IssueError(f"{where}: HTTP {error.code} {_github_message(error)}".rstrip()) from None
        except (urllib.error.URLError, OSError, http.client.HTTPException) as error:
            raise IssueError(f"{where}: {type(error).__name__}") from None
        try:
            return json.loads(raw) if raw else None
        except ValueError:
            raise IssueError(f"{where}: unreadable answer") from None

    def open_issues(self):
        # The plain list, not the search API: its index lags behind by
        # seconds to minutes, and the Mac's job opened a second issue through
        # it on 2026-10-06. The list also holds pull requests.
        issues = []
        for page in range(1, MAX_ISSUE_PAGES + 1):
            batch = self._call("GET", f"/issues?state=open&per_page=100&page={page}")
            if not isinstance(batch, list):
                raise IssueError("GET /issues: not a list")
            issues.extend(batch)
            if len(batch) < 100:
                break
        return issues

    def apply(self, action):
        if action.kind == "create":
            created = self._call("POST", "/issues", {"title": TITLE, "body": action.text})
            return f"opened issue #{_obj(created).get('number')}"
        if action.kind == "comment":
            self._call("POST", f"/issues/{action.number}/comments", {"body": action.text})
            return f"commented on issue #{action.number}"
        if action.kind == "update":
            self._call("PATCH", f"/issues/{action.number}", {"body": action.text})
            return f"updated the body of issue #{action.number}"
        if action.kind == "close":
            self._call("PATCH", f"/issues/{action.number}", {"state": "closed", "state_reason": "completed"})
            return f"closed issue #{action.number}"
        raise ValueError(action.kind)


def _github_message(error):
    """GitHub's own error message, short and in plain characters."""
    try:
        message = json.loads(error.read(4096)).get("message", "")
    except (OSError, ValueError, AttributeError):
        return ""
    return message[:200] if isinstance(message, str) and re.fullmatch(r"[\w .,:;'()/-]*", message) else ""


def run_url(env):
    server, repo, run_id = env.get("GITHUB_SERVER_URL"), env.get("GITHUB_REPOSITORY"), env.get("GITHUB_RUN_ID")
    if server and repo and run_id:
        return f"{server}/{repo}/actions/runs/{run_id}"
    return "exécution locale, sans lien"


def run(argv, *, get, sleep, env, github, clock, out):
    parser = argparse.ArgumentParser(description="Checks Lunaway's public endpoints from outside.")
    parser.add_argument("--dry-run", action="store_true", help="run the checks, print what the issue would get, write nothing")
    parser.add_argument(
        "--fail",
        action="append",
        default=[],
        choices=[c.id for c in CHECKS],
        help="count this check as failed without running it (repeatable), to exercise the alert",
    )
    args = parser.parse_args(argv)

    lock = threading.Lock()

    def log(line):
        with lock:
            out(line)

    repo = env.get("GITHUB_REPOSITORY") or DEFAULT_REPO
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        out("GITHUB_REPOSITORY is not owner/name")
        return 2
    token = env.get("GITHUB_TOKEN", "")

    failing = run_checks(get, sleep, log, forced=set(args.fail))
    for check_id, reason in failing.items():
        out(f"FAIL {check_id}: {reason}")
        if env.get("GITHUB_ACTIONS") == "true":
            out(f"::error title={check_id}::{LABELS[check_id]} : {reason}")
    out(f"{len(CHECKS) - len(failing)}/{len(CHECKS)} checks pass")

    if not token and not args.dry_run:
        out("GITHUB_TOKEN is not set: the issue cannot be read or written")
        return 2
    now = clock().strftime("%Y-%m-%d %H:%M UTC")
    try:
        # A dry run reads the open issues too, without a token when there is
        # none: the repository is public.
        client = github(repo, token)
        issues = client.open_issues()
        mine = probe_issues(issues)
        out(f"open issues '{TITLE}' by {BOT_LOGIN}: {', '.join('#%s' % i.get('number') for i in mine) or 'none'}")
        actions = plan(failing, issues, now, run_url(env))
        if not actions:
            out("issue: nothing to do")
        for action in actions:
            if args.dry_run:
                target = "a new issue" if action.number is None else f"issue #{action.number}"
                out(f"dry-run: would {action.kind} {target}" + (":" if action.text else ""))
                if action.text:
                    out("".join(f"    {line}\n" for line in action.text.splitlines()).rstrip("\n"))
            else:
                out(client.apply(action))
    except IssueError as error:
        out(f"issue: {error}")
        return 2
    return 1 if failing else 0


def main():
    return run(
        sys.argv[1:],
        get=fetch,
        sleep=time.sleep,
        env=os.environ,
        github=GitHub,
        clock=lambda: datetime.datetime.now(datetime.timezone.utc),
        out=lambda line: print(line, flush=True),
    )


if __name__ == "__main__":
    sys.exit(main())
