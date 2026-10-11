"""Tests of the photos' encrypted off-site copy on the backend
(infra/files/usr/local/sbin/lunaway-media-offsite), on a copy of the
script whose directories are scratch ones, with stand-ins for age (which
copies the file, or fails on a chosen call) and mountpoint. Needs bash
and GNU find, date and du, as on the backend; skipped elsewhere (the CI
runs it on Ubuntu).

    python3 infra/tests/media-offsite.py

The copy follows the photos (one copy for one photo, a deleted photo's copy
removed and dated in media/deletions), refuses a mass removal unless
LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL names its count, and whatever way it ends, its list
(media/manifest) names exactly the copies it holds: the Mac reads that list
to tell a deleted photo from a new one, and a list left from the night
before made it take the night's 202 new copies for deleted ones on
2026-10-11. The variable lets through exactly the count the refusal
prints, so a value left behind lets no later removal through.
"""

import datetime
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

INFRA = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = INFRA / "files" / "usr" / "local" / "sbin" / "lunaway-media-offsite"
PATHS = {
    "src=/srv/data/media/photos": "src={root}/media/photos",
    "media=/srv/data/backups/offsite/media": "media={root}/offsite/media",
    "recipients=/etc/lunaway/backup-recipient": "recipients={root}/backup-recipient",
}


def gnu_tools():
    try:
        find = subprocess.run(["find", "--version"], capture_output=True, text=True)
        du = subprocess.run(["du", "--version"], capture_output=True, text=True)
    except OSError:
        return False
    return "GNU" in find.stdout and "GNU" in du.stdout and shutil.which("bash") is not None


# The stand-in for age: `age --encrypt --recipients-file F -o OUT IN` copies
# IN to OUT; the call number FAKE_AGE_FAIL_AT fails instead.
FAKE_AGE = """#!/bin/bash
set -eu
out="" in=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --recipients-file) shift 2 ;;
    --encrypt) shift ;;
    *) in="$1"; shift ;;
  esac
done
n=$(( $(cat "$FAKE_AGE_CALLS" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_AGE_CALLS"
[ "$n" != "${FAKE_AGE_FAIL_AT:-0}" ] || { echo "age: failed" >&2; exit 1; }
cp "$in" "$out"
"""


def rel(i):
    """The name of photo number i, as the API writes it."""
    digest = f"{i:064x}"
    return f"{digest[:2]}/{digest[2:4]}/{digest}.webp"


@unittest.skipUnless(gnu_tools(), "needs bash and GNU find and du (the CI runs it)")
class MediaOffsite(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="lunaway-media-offsite-test-")
        self.root = pathlib.Path(self.scratch.name)
        text = SCRIPT.read_text()
        for line, scratch in PATHS.items():
            self.assertIn(f"\n{line}\n", text, f"the script no longer sets {line}")
            text = text.replace(f"\n{line}\n", "\n" + scratch.format(root=self.root) + "\n")
        (self.root / "script").write_text(text)
        (self.root / "backup-recipient").write_text("age1test\n")
        (self.root / "media" / "photos").mkdir(parents=True)
        (self.root / "offsite" / "media").mkdir(parents=True)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        (bin_dir / "age").write_text(FAKE_AGE)
        (bin_dir / "mountpoint").write_text("#!/bin/sh\nexit 0\n")
        for tool in ("age", "mountpoint"):
            (bin_dir / tool).chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        FAKE_AGE_CALLS=str(self.root / "age-calls"))
        self.env.pop("LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL", None)
        self.today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")

    def tearDown(self):
        self.scratch.cleanup()

    def photos(self, numbers):
        for i in numbers:
            path = self.root / "media" / "photos" / rel(i)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"photo {i}".encode())

    def delete(self, numbers):
        for i in numbers:
            (self.root / "media" / "photos" / rel(i)).unlink()

    def run_copy(self, **env):
        return subprocess.run(["bash", str(self.root / "script")], env=dict(self.env, **env),
                              capture_output=True, text=True)

    def offsite(self, name):
        return self.root / "offsite" / "media" / name

    def copies(self):
        base = self.offsite("photos")
        return sorted(f"photos/{p.relative_to(base)}" for p in base.rglob("*.webp.age"))

    def manifest(self):
        return self.offsite("manifest").read_text().splitlines()

    def test_every_photo_is_copied_once_and_listed(self):
        self.photos(range(1, 4))
        (self.root / "media" / "photos" / "notes.txt").write_text("not ours")
        done = self.run_copy()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.copies(), [f"photos/{rel(i)}.age" for i in range(1, 4)])
        self.assertEqual(self.manifest(), self.copies())
        self.assertRegex(self.offsite("last-success").read_text(), r"^\d{8}T\d{6}Z\n$")
        self.assertIn("photos: 3 encrypted, 0 removed, 3 in the copy", done.stdout)
        again = self.run_copy()
        self.assertIn("photos: 0 encrypted, 0 removed, 3 in the copy", again.stdout)

    def test_a_deleted_photo_loses_its_copy_dated_today(self):
        self.photos(range(1, 4))
        self.run_copy()
        self.delete([2])
        done = self.run_copy()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.manifest(), [f"photos/{rel(i)}.age" for i in (1, 3)])
        self.assertEqual(self.offsite("deletions").read_text(), f"{self.today} photos/{rel(2)}.age\n")

    def test_a_refused_mass_removal_still_lists_every_copy(self):
        self.photos(range(1, 61))
        self.run_copy()
        self.offsite("last-success").write_text("20260101T000000Z\n")
        self.delete(range(1, 56))
        self.photos([61, 62])
        done = self.run_copy()
        self.assertEqual(done.returncode, 1)
        self.assertEqual(len(self.copies()), 62)
        # The night's two new copies are listed, so the Mac keeps them.
        self.assertEqual(self.manifest(), self.copies())
        self.assertEqual(self.offsite("last-success").read_text(), "20260101T000000Z\n")
        self.assertEqual(self.offsite("deletions").read_text(), "")
        self.assertIn("refused: 55 of 62 photo copies would go", done.stderr)
        self.assertIn("LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL=55 lets exactly this removal through", done.stderr)

    def test_a_leave_for_another_count_lets_nothing_through(self):
        # A value left in systemd's environment, or the former "1", is
        # the count of no other removal.
        self.photos(range(1, 61))
        self.run_copy()
        self.delete(range(1, 56))
        for value in ("1", "54", "56", "yes"):
            done = self.run_copy(LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL=value)
            self.assertEqual(done.returncode, 1, value)
            self.assertEqual(len(self.copies()), 60, value)
            self.assertEqual(self.offsite("deletions").read_text(), "", value)

    def test_the_operator_lets_a_mass_removal_through(self):
        self.photos(range(1, 61))
        self.run_copy()
        self.delete(range(1, 56))
        done = self.run_copy(LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL="55")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("photos: 0 encrypted, 55 removed, 5 in the copy", done.stdout)
        self.assertEqual(self.manifest(), [f"photos/{rel(i)}.age" for i in range(56, 61)])
        dated = self.offsite("deletions").read_text().splitlines()
        self.assertEqual(sorted(dated), sorted(f"{self.today} photos/{rel(i)}.age" for i in range(1, 56)))

    def test_a_missing_photo_directory_is_refused_and_every_copy_listed(self):
        self.photos(range(1, 4))
        self.run_copy()
        self.delete(range(1, 4))
        for d in sorted((self.root / "media" / "photos").rglob("*"), reverse=True):
            d.rmdir()
        (self.root / "media" / "photos").rmdir()
        done = self.run_copy()
        self.assertEqual(done.returncode, 1)
        self.assertIn("is missing while the copy holds 3 photos", done.stderr)
        self.assertEqual(len(self.copies()), 3)
        self.assertEqual(self.manifest(), self.copies())

    def test_a_failed_encryption_still_lists_the_copies_made(self):
        self.photos(range(1, 4))
        self.run_copy()
        self.offsite("last-success").write_text("20260101T000000Z\n")
        self.photos(range(4, 8))
        # Calls 1 to 3 were the first run; the second new photo fails.
        done = self.run_copy(FAKE_AGE_FAIL_AT="5")
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(len(self.copies()), 4)
        self.assertEqual(self.manifest(), self.copies())
        self.assertEqual(self.offsite("last-success").read_text(), "20260101T000000Z\n")


if __name__ == "__main__":
    unittest.main()
