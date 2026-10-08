"""Tests of the translation server (infra/translate/lunaway-translate.py)
without its models: CTranslate2 and SentencePiece are replaced by fakes
that mark what went through them, so the splitting, the route through
English, the bounds and the HTTP answers are checked on any machine.

    python3 infra/tests/translate-server.py
"""

import importlib.util
import io
import json
import sys
import tempfile
import threading
import types
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

SERVER = Path(__file__).resolve().parent.parent / "translate" / "lunaway-translate.py"


class FakeTranslator:
    """Translates a list of pieces into the same pieces, upper-cased and
    tagged with the model's directory name; a piece holding the euro sign
    comes out unknown, as from a model whose vocabulary lacks it."""

    calls = []

    def __init__(self, path, **_):
        self.tag = Path(path).parent.parent.name

    def translate_batch(self, batch, **_):
        FakeTranslator.calls.append((self.tag, [list(b) for b in batch]))
        return [
            types.SimpleNamespace(
                hypotheses=[
                    [f"<{self.tag}>"]
                    + ["<unk>" if "€" in p else p.upper() for p in pieces]
                ]
            )
            for pieces in batch
        ]


class FakeProcessor:
    """Pieces are words; one holding the euro sign is out of the
    vocabulary."""

    def __init__(self, model_file):
        pass

    def encode(self, text, out_type=str):
        return text.split()

    def unk_id(self):
        return 0

    def piece_to_id(self, piece):
        return 0 if "€" in piece else 1

    def decode(self, pieces):
        return " ".join(" ⁇ " if p == "<unk>" else p for p in pieces)


sys.modules["ctranslate2"] = types.SimpleNamespace(Translator=FakeTranslator)
sys.modules["sentencepiece"] = types.SimpleNamespace(SentencePieceProcessor=FakeProcessor)
spec = importlib.util.spec_from_file_location("lunaway_translate", SERVER)
lt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lt)


def models_dir(test, pairs):
    """A models directory as lunaway-translate-models leaves it, removed
    with the test."""
    scratch = tempfile.TemporaryDirectory(prefix="lunaway-translate-test-")
    test.addCleanup(scratch.cleanup)
    root = Path(scratch.name)
    for pair in pairs:
        release = root / pair / "0123456789ab"
        release.mkdir(parents=True)
        (release / "lunaway.json").write_text(json.dumps({"model": f"{pair} test"}))
        (root / pair / "current").symlink_to("0123456789ab")
    return root


class Splitting(unittest.TestCase):
    def test_typographic_forms_become_what_the_models_were_trained_on(self):
        self.assertEqual(lt.normalise("C’est  “top”…​"), "C'est \"top\"...")

    def test_sentences_end_at_stops_and_marks(self):
        self.assertEqual(
            lt.sentences("Sehr schön. Sauber! Wieder? Ja"),
            ["Sehr schön.", "Sauber!", "Wieder?", "Ja"],
        )


class Translating(unittest.TestCase):
    def setUp(self):
        FakeTranslator.calls = []
        self.server = lt.Server(models_dir(self, ["de-fr", "pt-en", "en-fr"]), 1, 1, 4, 0)

    def test_paragraphs_keep_their_breaks_and_every_sentence_is_translated(self):
        made = self.server.translate("de", "fr", "Gut. Ruhig.\nSauber.")
        self.assertEqual(made["text"], "<de-fr> GUT. <de-fr> RUHIG.\n<de-fr> SAUBER.")
        self.assertEqual(made["model"], "de-fr test")
        self.assertEqual(len(FakeTranslator.calls), 1, "one batch for the whole text")

    def test_a_sentence_longer_than_a_model_takes_is_cut_never_dropped(self):
        words = [f"w{i}" for i in range(lt.MAX_PIECES + 5)]
        made = self.server.translate("de", "fr", " ".join(words))
        _, batch = FakeTranslator.calls[0]
        self.assertEqual([len(b) for b in batch], [lt.MAX_PIECES, 5])
        self.assertIn("W204", made["text"])

    def test_a_pair_without_its_model_goes_through_english(self):
        made = self.server.translate("pt", "fr", "Muito bom.")
        self.assertEqual(made["text"], "<en-fr> <PT-EN> MUITO BOM.")
        self.assertEqual(made["model"], "pt-en test + en-fr test")

    def test_a_pair_no_route_reaches_is_refused(self):
        self.assertIsNone(self.server.translate("nl", "fr", "Rustig."))

    def test_a_sign_the_model_cannot_spell_is_put_back(self):
        made = self.server.translate("de", "fr", "Preis 20 € pro Nacht.")
        self.assertEqual(made["text"], "<de-fr> PREIS 20 € PRO NACHT.")

    def test_a_text_past_its_deadline_stops(self):
        late = lt.Server(models_dir(self, ["de-fr"]), 1, 1, 4, 0, deadline=-1)
        with self.assertRaises(lt.Deadline):
            late.translate("de", "fr", "Ruhig.")


class Unknowns(unittest.TestCase):
    def test_the_source_s_own_sign_takes_the_place_of_an_unknown_piece(self):
        self.assertEqual(
            lt.restore_unknowns("We paid  ⁇ 20 for 2 people.", ["€"], "en"),
            "We paid € 20 for 2 people.",
        )

    def test_a_french_ca_gets_its_cedilla_back(self):
        self.assertEqual(
            lt.restore_unknowns(" ⁇ a vaut vraiment le coup.", [], "fr"),
            "Ça vaut vraiment le coup.",
        )
        self.assertEqual(
            lt.restore_unknowns("Calme. ⁇ a vaut le coup.", [], "fr"),
            "Calme. Ça vaut le coup.",
        )

    def test_any_other_unknown_piece_is_dropped(self):
        self.assertEqual(lt.restore_unknowns("Bonjour  ⁇  ami.", [], "en"), "Bonjour ami.")
        self.assertEqual(lt.restore_unknowns("Fin ⁇ .", [], "fr"), "Fin.")


class Http(unittest.TestCase):
    def setUp(self):
        self.server = lt.Server(models_dir(self, ["fr-en", "de-fr"]), 1, 1, 4, 0)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), lt.handler_for(self.server))
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.stderr = sys.stderr
        sys.stderr = io.StringIO()

    def tearDown(self):
        logged = sys.stderr.getvalue()
        sys.stderr = self.stderr
        self.httpd.shutdown()
        self.httpd.server_close()
        self.assertNotIn("Ruhig", logged, "no text in any log line")
        self.assertNotIn("127.0.0.1", logged, "no client address in any log line")

    def post(self, body):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        request = urllib.request.Request(
            f"{self.base}/translate", data=data, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            return error.code, json.load(error)

    def test_a_text_is_translated(self):
        status, body = self.post({"source": "de", "target": "fr", "text": "Ruhig."})
        self.assertEqual(status, 200)
        self.assertEqual(body, {"text": "<de-fr> RUHIG.", "engine": "opus-mt", "model": "de-fr test"})

    def test_a_pair_without_a_model_is_422(self):
        status, _ = self.post({"source": "nl", "target": "fr", "text": "Ruhig."})
        self.assertEqual(status, 422, "the API tells the app to stop offering it")

    def test_a_malformed_or_oversized_request_is_400(self):
        self.assertEqual(self.post(b"{not json")[0], 400)
        self.assertEqual(self.post({"source": "DE", "target": "fr", "text": "x"})[0], 400)
        self.assertEqual(self.post({"source": "de", "target": "fr", "text": "  "})[0], 400)
        too_long = "a" * (lt.MAX_TEXT_CHARS + 1)
        self.assertEqual(self.post({"source": "de", "target": "fr", "text": too_long})[0], 400)

    def test_a_text_past_its_deadline_is_504(self):
        self.server.deadline = -1
        status, _ = self.post({"source": "de", "target": "fr", "text": "Ruhig."})
        self.assertEqual(status, 504, "work done and dropped: the API keeps the client's use")

    def test_every_slot_taken_is_503(self):
        held = [self.server.slots.acquire(blocking=False)]
        self.assertTrue(held[0])
        try:
            status, _ = self.post({"source": "de", "target": "fr", "text": "Ruhig."})
            self.assertEqual(status, 503, "the API waits and tells the client to retry")
        finally:
            self.server.slots.release()

    def test_health_names_the_pairs_once_a_text_went_through(self):
        with urllib.request.urlopen(f"{self.base}/health") as response:
            self.assertEqual(json.load(response), {"engine": "opus-mt", "pairs": ["de-fr", "fr-en"]})


if __name__ == "__main__":
    unittest.main(verbosity=1)
