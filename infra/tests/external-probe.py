"""Tests of the external probe (infra/ops/probe/external-probe.py) without
the network: the requests go to fakes, so the checks' conditions, the three
attempts, the issue's decisions (open, comment on a change, update, close,
leave alone) and the exit status are checked on any machine.

    python3 infra/tests/external-probe.py
"""

import datetime
import importlib.util
import io
import json
import unittest
import urllib.error
from pathlib import Path

INFRA = Path(__file__).resolve().parent.parent
PROBE = INFRA / "ops" / "probe" / "external-probe.py"
GATUS = INFRA / "ops" / "gatus" / "config.yaml"

spec = importlib.util.spec_from_file_location("external_probe", PROBE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

NOW = "2026-10-10 14:15 UTC"
RUN_URL = "https://github.com/poka-IT/lunaway/actions/runs/42"
ENV = {
    "GITHUB_TOKEN": "token-that-must-not-leak",
    "GITHUB_REPOSITORY": "poka-IT/lunaway",
    "GITHUB_SERVER_URL": "https://github.com",
    "GITHUB_RUN_ID": "42",
}


def response(status=200, body=b"", headers=None):
    if not isinstance(body, bytes):
        body = json.dumps(body).encode()
    return probe.Response(status, headers or {}, body)


GOOD = {
    "https://lunaway.net/": response(body=b"<!doctype html>"),
    "https://api.lunaway.net/health": response(body=b"ok\n"),
    "https://tiles.lunaway.net/planet.json": response(body={"tilejson": "3.0.0", "tiles": []}),
    "https://tiles.lunaway.net/planet/14/8299/5636.mvt": response(body=b"\x1f\x8b" + b"x" * 4000),
}
SEARCH_OK = {"data": {"searchAll": {"addresses": [{"countryCode": "DE"}], "addressesComplete": True}}}
ROUTE_OK = {"data": {"route": {"status": "OK", "routes": [{"distanceM": 1432.5}]}}}


class FakeFetch:
    """Answers each URL from a table; the GraphQL endpoint by the query
    sent. `override` replaces an answer, or raises Failed when it is a
    string."""

    def __init__(self, override=None, search=SEARCH_OK, route=ROUTE_OK):
        self.override = override or {}
        self.search = search
        self.route = route
        self.calls = []

    def __call__(self, method, url, *, body=None, headers=None, timeout=20):
        self.calls.append((method, url, headers or {}, timeout, body))
        key = url
        if url == "https://api.lunaway.net/graphql":
            key = "search" if b"searchAll" in body else "route"
        answer = self.override.get(key)
        if isinstance(answer, str):
            raise probe.Failed(answer)
        if answer is not None:
            return answer
        if key == "search":
            return response(body=self.search)
        if key == "route":
            return response(body=self.route)
        return GOOD[url]


def issue(number, failing=None, title=probe.TITLE, login=probe.BOT_LOGIN, body=None, pull=False):
    if body is None:
        body = "Sonde externe\n\n" + (probe.marker(failing) if failing is not None else "")
    found = {"number": number, "title": title, "user": {"login": login}, "body": body, "state": "open"}
    if pull:
        found["pull_request"] = {"url": "x"}
    return found


class FakeGitHub:
    """Records every write; `issues` is what the list answers, `fail_on`
    the kind of action that answers an error."""

    instances = []

    def __init__(self, issues=(), fail_on=None, list_fails=False):
        self.issues = list(issues)
        self.fail_on = fail_on
        self.list_fails = list_fails
        self.writes = []

    def __call__(self, repo, token):
        self.repo, self.token = repo, token
        return self

    def open_issues(self):
        if self.list_fails:
            raise probe.IssueError("GET /issues: HTTP 503")
        return self.issues

    def apply(self, action):
        if action.kind == self.fail_on:
            raise probe.IssueError(f"{action.kind}: HTTP 403 Resource not accessible by integration")
        self.writes.append(action)
        return f"{action.kind} done"


def run(argv=(), fetch=None, github=None, env=None):
    lines = []
    sleeps = []
    code = probe.run(
        list(argv),
        get=fetch or FakeFetch(),
        sleep=sleeps.append,
        env=ENV if env is None else env,
        github=github or FakeGitHub(),
        clock=lambda: datetime.datetime(2026, 10, 10, 14, 15, tzinfo=datetime.timezone.utc),
        out=lines.append,
    )
    return code, "\n".join(lines), sleeps


class Conditions(unittest.TestCase):
    """Each check against good and bad answers."""

    def check(self, check_id, fetch):
        check = next(c for c in probe.CHECKS if c.id == check_id)
        try:
            check.run(fetch)
        except probe.Failed as error:
            return str(error)
        return None

    def test_good_answers_pass(self):
        for c in probe.CHECKS:
            self.assertIsNone(self.check(c.id, FakeFetch()), c.id)

    def test_site_status(self):
        self.assertEqual(self.check("site", FakeFetch({"https://lunaway.net/": response(503)})), "HTTP 503")

    def test_api_body_must_be_ok(self):
        url = "https://api.lunaway.net/health"
        self.assertEqual(self.check("api", FakeFetch({url: response(body=b"degraded")})), "la réponse n'est pas « ok »")
        self.assertEqual(self.check("api", FakeFetch({url: response(502, b"ok")})), "HTTP 502")

    def test_tilejson_version(self):
        bad = FakeFetch({"https://tiles.lunaway.net/planet.json": response(body={"tilejson": "2.2.0"})})
        self.assertIn("3.0.0", self.check("tiles", bad))
        garbage = FakeFetch({"https://tiles.lunaway.net/planet.json": response(body=b"<html>")})
        self.assertEqual(self.check("tiles", garbage), "TileJSON illisible")

    def test_tile_counts_bytes_received_and_asks_for_gzip(self):
        fetch = FakeFetch({"https://tiles.lunaway.net/planet/14/8299/5636.mvt": response(body=b"x" * 1000)})
        self.assertEqual(self.check("tiles", fetch), "tuile de 1000 octets, plus de 1000 attendus")
        tile_call = next(c for c in fetch.calls if c[1].endswith(".mvt"))
        self.assertEqual(tile_call[2].get("Accept-Encoding"), "gzip")
        tiles = next(c for c in probe.CHECKS if c.id == "tiles")
        self.assertEqual(tiles.run(FakeFetch()), "tile of 4002 bytes")

    def test_search_conditions(self):
        incomplete = {"data": {"searchAll": {"addresses": [{"countryCode": "DE"}], "addressesComplete": False}}}
        self.assertIn("addressesComplete", self.check("search", FakeFetch(search=incomplete)))
        france = {"data": {"searchAll": {"addresses": [{"countryCode": "FR"}], "addressesComplete": True}}}
        self.assertIn("Allemagne", self.check("search", FakeFetch(search=france)))
        empty = {"data": {"searchAll": {"addresses": [], "addressesComplete": True}}}
        self.assertIn("Allemagne", self.check("search", FakeFetch(search=empty)))
        self.assertEqual(self.check("search", FakeFetch(search={"errors": [{"message": "x"}]})), "réponse GraphQL sans données")

    def test_search_request_is_the_gatus_query(self):
        fetch = FakeFetch()
        self.check("search", fetch)
        method, url, headers, timeout, body = fetch.calls[0]
        self.assertEqual((method, url, timeout), ("POST", "https://api.lunaway.net/graphql", 20))
        self.assertEqual(headers.get("Content-Type"), "application/json")
        self.assertEqual(json.loads(body), {"query": probe.SEARCH_QUERY})

    def test_route_conditions(self):
        under_bridge = {"data": {"route": {"status": "OK", "routes": [{"distanceM": 420}]}}}
        self.assertIn("420 m", self.check("route", FakeFetch(route=under_bridge)))
        none = {"data": {"route": {"status": "NO_ROUTE", "routes": []}}}
        self.assertEqual(self.check("route", FakeFetch(route=none)), "statut NO_ROUTE")
        # A status that is not an enum value stays out of the public text.
        odd = {"data": {"route": {"status": "<a href=//x>", "routes": []}}}
        self.assertEqual(self.check("route", FakeFetch(route=odd)), "statut inattendu")
        fetch = FakeFetch()
        self.check("route", fetch)
        self.assertEqual(fetch.calls[0][3], 30)

    def test_queries_match_the_status_page(self):
        """The probe asks what the status page's checks ask: a change to one
        of them must reach the other."""
        lines = GATUS.read_text().splitlines()

        def gatus_query(name):
            start = lines.index(f"  - name: {name}")
            for line in lines[start + 1 :]:
                stripped = line.strip()
                if stripped.startswith('body: "'):
                    return stripped[len('body: "') : -1].replace('\\"', '"')
            raise AssertionError(f"no body for {name}")

        self.assertEqual(probe.SEARCH_QUERY, gatus_query("Addresses (Europe)"))
        self.assertEqual(probe.ROUTE_QUERY, gatus_query("Witness route"))


class Attempts(unittest.TestCase):
    def test_passes_when_one_attempt_of_three_passes(self):
        answers = iter(["HTTP 502", "pas de réponse en 20 s", None])

        def flaky(get):
            reason = next(answers)
            if reason:
                raise probe.Failed(reason)

        sleeps, log = [], []
        reason = probe.run_check(probe.Check("api", "API", flaky), None, sleeps.append, log.append)
        self.assertIsNone(reason)
        self.assertEqual(sleeps, [20, 20])

    def test_fails_only_when_all_three_fail_and_keeps_the_last_reason(self):
        answers = iter(["HTTP 502", "HTTP 503", "HTTP 504"])

        def down(get):
            raise probe.Failed(next(answers))

        sleeps = []
        reason = probe.run_check(probe.Check("api", "API", down), None, sleeps.append, lambda _: None)
        self.assertEqual(reason, "HTTP 504")
        self.assertEqual(sleeps, [20, 20])

    def test_a_bug_counts_as_a_failure(self):
        def broken(get):
            raise KeyError("x")

        reason = probe.run_check(probe.Check("api", "API", broken), None, lambda _: None, lambda _: None)
        self.assertEqual(reason, "erreur interne de la sonde (KeyError)")

    def test_failing_set_is_in_check_order_and_forced_checks_are_not_run(self):
        fetch = FakeFetch({"route": "HTTP 500", "https://lunaway.net/": "connexion impossible"})
        failing = probe.run_checks(fetch, lambda _: None, lambda _: None, forced={"api"})
        self.assertEqual(list(failing), ["site", "api", "route"])
        self.assertEqual(failing["api"], "échec forcé par --fail (exercice)")
        self.assertNotIn("https://api.lunaway.net/health", [c[1] for c in fetch.calls])


class Marker(unittest.TestCase):
    def test_round_trip(self):
        self.assertEqual(probe.marker({"search", "api"}), "<!-- failing: api,search -->")
        self.assertEqual(probe.recorded_failing("text\n<!-- failing: api,search -->"), {"api", "search"})

    def test_missing_marker_is_none(self):
        self.assertIsNone(probe.recorded_failing("edited by hand"))
        self.assertIsNone(probe.recorded_failing(None))


class Decisions(unittest.TestCase):
    failing = {"api": "HTTP 502", "search": "la première adresse trouvée n'est pas en Allemagne"}

    def test_failing_and_no_issue_opens_one(self):
        [action] = probe.plan(self.failing, [], NOW, RUN_URL)
        self.assertEqual((action.kind, action.number), ("create", None))
        body = action.text
        self.assertTrue(body.startswith("Sonde externe (GitHub Actions, toutes les 15 minutes)"))
        self.assertIn("- API (https://api.lunaway.net/health) : HTTP 502", body)
        self.assertIn("Recherche d'adresses en Europe", body)
        self.assertIn(f"Exécution : {RUN_URL}", body)
        self.assertIn("se ferme d'elle-même à la première exécution où tout repasse au vert", body)
        self.assertEqual(probe.recorded_failing(body), {"api", "search"})

    def test_same_failing_set_updates_without_comment(self):
        actions = probe.plan(self.failing, [issue(7, {"api", "search"})], NOW, RUN_URL)
        self.assertEqual([(a.kind, a.number) for a in actions], [("update", 7)])

    def test_changed_failing_set_comments_then_updates(self):
        actions = probe.plan(self.failing, [issue(7, {"api"})], NOW, RUN_URL)
        self.assertEqual([(a.kind, a.number) for a in actions], [("comment", 7), ("update", 7)])
        self.assertIn("ont changé", actions[0].text)
        self.assertEqual(probe.recorded_failing(actions[1].text), {"api", "search"})

    def test_body_without_marker_comments_then_updates(self):
        actions = probe.plan(self.failing, [issue(7, body="edited by hand")], NOW, RUN_URL)
        self.assertEqual([a.kind for a in actions], ["comment", "update"])

    def test_green_closes_with_a_comment(self):
        actions = probe.plan({}, [issue(7, {"api"})], NOW, RUN_URL)
        self.assertEqual([(a.kind, a.number) for a in actions], [("comment", 7), ("close", 7)])
        self.assertTrue(actions[0].text.startswith(f"De nouveau au vert le {NOW}"))

    def test_green_and_no_issue_does_nothing(self):
        self.assertEqual(probe.plan({}, [], NOW, RUN_URL), [])

    def test_issues_of_others_are_left_alone(self):
        others = [
            issue(4, {"api"}, login="poka-IT"),  # the Mac's issue of the same title
            issue(5, {"api"}, title="ops: alerte (copie)"),
            issue(6, {"api"}, pull=True),
        ]
        self.assertEqual(probe.plan({}, others, NOW, RUN_URL), [])
        [create] = probe.plan(self.failing, others, NOW, RUN_URL)
        self.assertEqual(create.kind, "create")

    def test_the_oldest_of_two_probe_issues_is_updated(self):
        actions = probe.plan(self.failing, [issue(9, {"api"}), issue(8, {"api", "search"})], NOW, RUN_URL)
        self.assertEqual([(a.kind, a.number) for a in actions], [("update", 8)])


class Runs(unittest.TestCase):
    """The whole run against fakes: exit status, writes, dry run."""

    def test_green_with_an_open_issue_closes_it(self):
        github = FakeGitHub([issue(7, {"api"}), issue(4, {"api"}, login="poka-IT")])
        code, out, _ = run(github=github)
        self.assertEqual(code, 0)
        self.assertEqual([(a.kind, a.number) for a in github.writes], [("comment", 7), ("close", 7)])
        self.assertEqual(github.token, ENV["GITHUB_TOKEN"])

    def test_failure_opens_an_issue_and_exits_1(self):
        github = FakeGitHub()
        code, out, sleeps = run(fetch=FakeFetch({"route": "HTTP 500"}), github=github)
        self.assertEqual(code, 1)
        self.assertEqual([a.kind for a in github.writes], ["create"])
        self.assertIn("Itinéraire témoin", github.writes[0].text)
        self.assertEqual(sleeps, [20, 20])
        self.assertIn("FAIL route: HTTP 500", out)

    def test_dry_run_writes_nothing_and_needs_no_token(self):
        github = FakeGitHub([issue(7, {"api"})])
        env = {k: v for k, v in ENV.items() if k != "GITHUB_TOKEN"}
        code, out, _ = run(["--dry-run", "--fail", "api", "--fail", "tiles"], github=github, env=env)
        self.assertEqual(code, 1)
        self.assertEqual(github.writes, [])
        self.assertIn("dry-run: would comment issue #7", out)
        self.assertIn("dry-run: would update issue #7", out)
        self.assertIn("<!-- failing: api,tiles -->", out)

    def test_missing_token_fails_the_run(self):
        env = {k: v for k, v in ENV.items() if k != "GITHUB_TOKEN"}
        code, out, _ = run(env=env)
        self.assertEqual(code, 2)
        self.assertIn("GITHUB_TOKEN is not set", out)

    def test_issue_errors_fail_the_run(self):
        code, out, _ = run(github=FakeGitHub(list_fails=True))
        self.assertEqual(code, 2)
        self.assertIn("issue: GET /issues: HTTP 503", out)
        code, out, _ = run(fetch=FakeFetch({"https://lunaway.net/": "HTTP 503"}), github=FakeGitHub(fail_on="create"))
        self.assertEqual(code, 2)

    def test_the_token_is_never_printed(self):
        for kwargs in ({}, {"fetch": FakeFetch({"route": "HTTP 500"})}, {"github": FakeGitHub(fail_on="close")}):
            _, out, _ = run(**kwargs)
            self.assertNotIn(ENV["GITHUB_TOKEN"], out)

    def test_annotations_in_github_actions(self):
        env = dict(ENV, GITHUB_ACTIONS="true")
        _, out, _ = run(fetch=FakeFetch({"https://api.lunaway.net/health": response(body=b"down")}), env=env)
        self.assertIn("::error title=api::API (https://api.lunaway.net/health) : la réponse n'est pas « ok »", out)


class FakeHTTP:
    """Stands for urllib's response object."""

    def __init__(self, status=200, body=b"", headers=None):
        self.status, self.stream, self.headers = status, io.BytesIO(body), headers or {}

    def read(self, n=-1):
        return self.stream.read(n)

    def getcode(self):
        return self.status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Transport(unittest.TestCase):
    """What goes on the wire: the probe's User-Agent, the token only as a
    header to GitHub, the pages of the issue list, the errors mapped."""

    def test_fetch_sends_the_user_agent_and_the_timeout(self):
        seen = []

        def opener(request, timeout):
            seen.append((request, timeout))
            return FakeHTTP(200, b"ok", {"Content-Type": "text/plain"})

        answer = probe.fetch("GET", "https://api.lunaway.net/health", timeout=20, opener=opener)
        self.assertEqual(answer, probe.Response(200, {"content-type": "text/plain"}, b"ok"))
        request, timeout = seen[0]
        self.assertEqual(request.get_header("User-agent"), "Lunaway external probe (+https://lunaway.net)")
        self.assertEqual(timeout, 20)

    def test_fetch_maps_a_timeout_and_returns_an_http_error_status(self):
        def slow(request, timeout):
            raise urllib.error.URLError(TimeoutError("timed out"))

        with self.assertRaises(probe.Failed) as raised:
            probe.fetch("GET", "https://lunaway.net/", timeout=20, opener=slow)
        self.assertEqual(str(raised.exception), "pas de réponse en 20 s")

        def bad_gateway(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 502, "Bad Gateway", {}, io.BytesIO(b"upstream 10.0.0.1"))

        self.assertEqual(probe.fetch("GET", "https://lunaway.net/", opener=bad_gateway).status, 502)

    def test_github_lists_every_page_with_the_token(self):
        pages = [[issue(n) for n in range(100)], [issue(100)]]
        seen = []

        def opener(request, timeout):
            seen.append(request)
            return FakeHTTP(200, json.dumps(pages[len(seen) - 1]).encode())

        issues = probe.GitHub("poka-IT/lunaway", "t0ken", opener).open_issues()
        self.assertEqual(len(issues), 101)
        self.assertEqual(len(seen), 2)
        self.assertTrue(seen[1].full_url.startswith("https://api.github.com/repos/poka-IT/lunaway/issues?state=open"))
        self.assertIn("page=2", seen[1].full_url)
        self.assertEqual(seen[0].get_header("Authorization"), "Bearer t0ken")

    def test_github_writes(self):
        seen = []

        def opener(request, timeout):
            seen.append((request.get_method(), request.full_url, json.loads(request.data)))
            return FakeHTTP(201, b'{"number": 12}')

        gh = probe.GitHub("poka-IT/lunaway", "t0ken", opener)
        self.assertEqual(gh.apply(probe.Action("create", None, "body")), "opened issue #12")
        gh.apply(probe.Action("comment", 12, "note"))
        gh.apply(probe.Action("update", 12, "new body"))
        gh.apply(probe.Action("close", 12, None))
        base = "https://api.github.com/repos/poka-IT/lunaway/issues"
        self.assertEqual(
            seen,
            [
                ("POST", base, {"title": "ops: alerte", "body": "body"}),
                ("POST", f"{base}/12/comments", {"body": "note"}),
                ("PATCH", f"{base}/12", {"body": "new body"}),
                ("PATCH", f"{base}/12", {"state": "closed", "state_reason": "completed"}),
            ],
        )

    def test_github_errors_become_issue_errors_without_the_token(self):
        def forbidden(request, timeout):
            raise urllib.error.HTTPError(
                request.full_url, 403, "Forbidden", {}, io.BytesIO(b'{"message": "Resource not accessible by integration"}')
            )

        with self.assertRaises(probe.IssueError) as raised:
            probe.GitHub("poka-IT/lunaway", "t0ken", forbidden).apply(probe.Action("close", 3, None))
        self.assertEqual(str(raised.exception), "PATCH /issues/3: HTTP 403 Resource not accessible by integration")
        self.assertNotIn("t0ken", str(raised.exception))


if __name__ == "__main__":
    unittest.main(verbosity=1)
