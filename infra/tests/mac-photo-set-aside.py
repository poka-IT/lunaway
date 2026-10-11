"""Tests of the photo set-aside of the Mac's nightly job
(`set_aside_photos` in infra/ops/mac/lunaway-ops.sh), run as the script
defines it, in sh, on a scratch copy tree: no server, no key.

    python3 infra/tests/mac-photo-set-aside.py

A copy the server's list (media/manifest) no longer names is set aside
under the day the server deleted its photo (media/deletions), or dropped
at once when the server did not date it or dated it before the 26 days of
the hold. Only the copies dropped at once count against the threshold (50
copies and 5% of them): a mass removal the server dated, which its
operator let through, is set aside however large, while a list that lost
lines drops nothing. A mass removal set aside fails that night, once.
"""

import pathlib
import re
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "ops" / "mac" / "lunaway-ops.sh"
FOUND = re.search(r"^set_aside_photos\(\) \{\n.*?^\}\n", SCRIPT.read_text(), re.M | re.S)
HELD_CUTOFF = "20260915"
TODAY = "20261011"
OLD_DAY = "20260901"

# What the job defines around the function: its messages, and failures.
HARNESS = """set -u
failures=""
say() { echo "say: $*"; }
fail() { echo "fail: $1"; failures="${failures}x"; }
dest="$1"
held_cutoff="$2"
"""


def rel(i):
    """The name of copy number i, as the server lists it."""
    digest = f"{i:064x}"
    return f"photos/{digest[:2]}/{digest[2:4]}/{digest}.webp.age"


class SetAside(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(FOUND, "set_aside_photos() not found in lunaway-ops.sh")
        self.scratch = tempfile.TemporaryDirectory(prefix="lunaway-set-aside-test-")
        self.dest = pathlib.Path(self.scratch.name)
        (self.dest / "media").mkdir()
        self.script = self.dest.parent / f"{self.dest.name}.sh"
        self.script.write_text(HARNESS + FOUND.group(0) + 'set_aside_photos\necho "failures=$failures"\n')

    def tearDown(self):
        self.script.unlink()
        self.scratch.cleanup()

    def copies(self, n):
        """n copies on the Mac, numbered 1 to n."""
        for i in range(1, n + 1):
            path = self.dest / "media" / rel(i)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"age")

    def server(self, listed, dated=(), day=TODAY, lines=None):
        """The server's lists: the copies it holds, and the dated deletions."""
        manifest = lines if lines is not None else [rel(i) for i in listed]
        (self.dest / "media" / "manifest").write_text("".join(f"{line}\n" for line in sorted(manifest)))
        (self.dest / "media" / "deletions").write_text("".join(f"{day} {rel(i)}\n" for i in dated))

    def run_job(self):
        done = subprocess.run(["sh", str(self.script), str(self.dest), HELD_CUTOFF],
                              capture_output=True, text=True, check=True)
        return done.stdout

    def on_mac(self, i):
        return (self.dest / "media" / rel(i)).exists()

    def set_aside(self, i, day=TODAY):
        return (self.dest / "media-deleted" / day / rel(i)).exists()

    def test_a_copy_the_server_dated_is_set_aside_under_its_day(self):
        self.copies(10)
        self.server(listed=range(1, 10), dated=[10])
        out = self.run_job()
        self.assertIn("failures=\n", out)
        self.assertFalse(self.on_mac(10))
        self.assertTrue(self.set_aside(10))
        self.assertTrue(all(self.on_mac(i) for i in range(1, 10)))
        self.assertIn("say: 1 photo copies deleted on the server: 1 set aside, 0 dropped", out)

    def test_a_copy_the_server_did_not_date_is_dropped(self):
        self.copies(10)
        self.server(listed=range(1, 10))
        out = self.run_job()
        self.assertIn("failures=\n", out)
        self.assertFalse(self.on_mac(10))
        self.assertFalse((self.dest / "media-deleted").exists())
        self.assertIn("0 set aside, 1 dropped", out)

    def test_a_copy_dated_before_the_hold_is_dropped(self):
        self.copies(10)
        self.server(listed=range(1, 10), dated=[10], day=OLD_DAY)
        self.run_job()
        self.assertFalse(self.on_mac(10))
        self.assertFalse((self.dest / "media-deleted").exists())

    def test_a_mass_removal_the_server_dated_is_set_aside_and_reported_once(self):
        # An operator let 70 removals through on the server, which dated
        # them: the Mac follows and keeps them 26 days, and says so that
        # night, in case the server let them through by mistake.
        self.copies(100)
        self.server(listed=range(1, 31), dated=range(31, 101))
        out = self.run_job()
        self.assertTrue(all(self.set_aside(i) and not self.on_mac(i) for i in range(31, 101)))
        self.assertTrue(all(self.on_mac(i) for i in range(1, 31)))
        self.assertIn("70 set aside, 0 dropped", out)
        self.assertIn("fail: 70 des 100 photos copiées sur le Mac supprimées sur le serveur en une nuit, "
                      "mises de côté dans media-deleted jusqu'à 26 jours après leur date de suppression : "
                      "vérifier que la suppression était voulue", out)
        # The next night nothing is left to set aside, and nothing fails.
        self.assertEqual(self.run_job(), "failures=\n")

    def test_a_list_that_lost_many_lines_drops_nothing(self):
        # The night's new copies missing from a stale list look the same.
        self.copies(100)
        self.server(listed=range(1, 31))
        out = self.run_job()
        self.assertIn("fail: le serveur ne liste plus 70 des 100 photos copiées sur le Mac sans dater "
                      "leur suppression ; rien n'est retiré", out)
        self.assertTrue(all(self.on_mac(i) for i in range(1, 101)))
        self.assertFalse((self.dest / "media-deleted").exists())

    def test_many_copies_dated_before_the_hold_are_not_dropped(self):
        self.copies(100)
        self.server(listed=range(1, 31), dated=range(31, 101), day=OLD_DAY)
        out = self.run_job()
        self.assertIn("fail: le serveur ne liste plus 70 des 100", out)
        self.assertTrue(all(self.on_mac(i) for i in range(1, 101)))

    def test_dated_copies_do_not_let_undated_ones_through(self):
        # 60 dated removals beside 60 undated ones: the 60 undated would be
        # dropped at once, past the threshold, so nothing moves.
        self.copies(200)
        self.server(listed=range(1, 81), dated=range(81, 141))
        out = self.run_job()
        self.assertIn("fail: le serveur ne liste plus 60 des 200", out)
        self.assertTrue(all(self.on_mac(i) for i in range(1, 201)))

    def test_a_list_of_an_unexpected_form_changes_nothing(self):
        self.copies(10)
        self.server(listed=(), lines=[rel(i) for i in range(1, 6)] + ["../../etc/passwd"])
        out = self.run_job()
        self.assertIn("fail: la liste des photos du serveur a une forme inattendue ; rien n'est retiré", out)
        self.assertTrue(all(self.on_mac(i) for i in range(1, 11)))

    def test_every_copy_listed_changes_nothing(self):
        self.copies(10)
        self.server(listed=range(1, 11))
        out = self.run_job()
        self.assertEqual(out, "failures=\n")
        self.assertTrue(all(self.on_mac(i) for i in range(1, 11)))


if __name__ == "__main__":
    unittest.main()
