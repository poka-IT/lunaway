"""Lunaway's translation server (docs/deploy.md, "Translation").

Translates the reviews and descriptions the API sends it, with the OPUS-MT
models (CC BY 4.0) converted for CTranslate2 (MIT) by
lunaway-translate-models: no third-party service ever sees a text. It
listens on the loopback for the backend's Caddy alone, keeps
nothing, and logs no text and no address.

  POST /translate  {"source": "de", "target": "fr", "text": "..."}
                   200 {"text": "...", "engine": "opus-mt", "model": "..."}
                   422 no model for the pair, 400 a malformed request,
                   503 every slot taken (nothing done), 504 past the
                   deadline (work done and dropped)
  GET  /health     200 {"engine": "opus-mt", "pairs": [...]} once a short
                   text went through a model, 503 otherwise

A pair without its own model goes through English when both halves exist
(Portuguese to French: pt-en then en-fr).

Settings, from the environment (lunaway-translate.service):
  LUNAWAY_TRANSLATE_LISTEN     address and port, 127.0.0.1:2324
  LUNAWAY_TRANSLATE_MODELS     the models' directory, /srv/translate/models
  LUNAWAY_TRANSLATE_WORKERS    texts translated at once, 2
  LUNAWAY_TRANSLATE_THREADS    threads per text, 2
  LUNAWAY_TRANSLATE_BEAM       beam size, 4 (the models' own setting)
  LUNAWAY_TRANSLATE_QUEUE      texts waiting beyond the workers before 503, 8
  LUNAWAY_TRANSLATE_DEADLINE   seconds a text may take, 14: the API waits 15
"""

import json
import logging
import os
import re
import sys
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import ctranslate2
import sentencepiece

ENGINE = "opus-mt"
# Longest text taken, in characters: the longest review stored holds 4 000.
MAX_TEXT_CHARS = 5000
# Largest request body read.
MAX_BODY_BYTES = 64 * 1024
# Longest sentence fed to a model, in pieces: the models were trained on
# sentences, and a run-on text without punctuation is cut into pieces of
# this size rather than truncated.
MAX_PIECES = 200
# Sentences translated together, between two looks at the deadline: twelve
# descriptions of 1 300 to 2 000 characters held 14 to 26 sentences, and
# batches of 8 made such a text slower than one batch (median 3.6 s
# against 3.0 s through the API, 2026-10-08).
BATCH = 16
LANG = re.compile(r"^[a-z]{2,3}$")
# Ends of sentences: a stop, a question or exclamation mark, an ellipsis,
# followed by white space.
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")
# Characters the OPUS-MT preprocessing replaces (Tatoeba-MT's
# preprocess.sh): full-width and typographic forms the models never saw.
REPLACED = str.maketrans(
    {
        "，": ",",
        "、": ",",
        "”": '"',
        "“": '"',
        "∶": ":",
        "：": ":",
        "？": "?",
        "《": '"',
        "》": '"',
        "）": ")",
        "！": "!",
        "（": "(",
        "；": ";",
        "」": '"',
        "「": '"',
        "～": "~",
        "’": "'",
        "━": "-",
        "〈": "<",
        "〉": ">",
        "【": "[",
        "】": "]",
        "％": "%",
    }
)

log = logging.getLogger("lunaway-translate")


def normalise(line):
    """The line as the models were trained on it: the preprocessing's
    replacements, no control character, single spaces."""
    line = line.translate(REPLACED).replace("…", "...")
    line = "".join(
        " " if unicodedata.category(c).startswith("C") else c for c in line
    )
    return re.sub(r" {2,}", " ", line).strip()


def sentences(paragraph):
    """The sentences of one paragraph, in order."""
    return [s for s in SENTENCE_END.split(normalise(paragraph)) if s]


# What SentencePiece prints for a piece outside a vocabulary.
UNKNOWN = re.compile(r"\s*⁇\s*")


def restore_unknowns(text, unknowns, target):
    """A sentence's translation with what its model could not spell put
    back. The vocabularies of some models lack a character their texts
    need: French to English has no "€" on either side, German to French no
    "Ç" (measured on reviews, 2026-10-08), and the model then writes an
    unknown piece. Each one takes, in order, the source's own unknown
    character (the euro sign the model copied as unknown); a French "Ça"
    the target vocabulary cannot spell gets its "Ç"; any other is dropped,
    a missing sign reading better than a "⁇". A sentence without one is
    returned as the model wrote it."""
    if "⁇" not in text:
        return text
    pending = [u.replace("▁", "") for u in unknowns]
    pending = [u for u in pending if u]
    out = []
    pos = 0
    for found in UNKNOWN.finditer(text):
        out.append(text[pos : found.start()])
        rest = text[found.end() :]
        if pending:
            out.append(" " + pending.pop(0) + " ")
        elif target == "fr" and rest[:1] == "a" and not rest[1:2].isalpha():
            out.append(" Ç" if "".join(out).strip() else "Ç")
        else:
            out.append(" ")
        pos = found.end()
    out.append(text[pos:])
    joined = re.sub(r" {2,}", " ", "".join(out)).strip()
    return re.sub(r" ([,.)])", r"\1", joined)


class Deadline(Exception):
    """The text took longer than the API waits for it."""


class Model:
    """One language pair: the CTranslate2 model and its two SentencePiece
    vocabularies, as lunaway-translate-models installed them."""

    def __init__(self, directory, workers, threads, beam):
        meta = json.loads((directory / "lunaway.json").read_text())
        self.name = meta["model"]
        # The pair's directory is named source-target.
        self.target_lang = directory.parent.name.rpartition("-")[2]
        self.beam = beam
        self.translator = ctranslate2.Translator(
            str(directory / "ct2"),
            device="cpu",
            compute_type="int8",
            inter_threads=workers,
            intra_threads=threads,
        )
        self.source = sentencepiece.SentencePieceProcessor(
            model_file=str(directory / "source.spm")
        )
        self.target = sentencepiece.SentencePieceProcessor(
            model_file=str(directory / "target.spm")
        )

    def __call__(self, text, deadline=None):
        paragraphs = [sentences(p) for p in text.split("\n")]
        pieces = []
        for paragraph in paragraphs:
            for sentence in paragraph:
                encoded = self.source.encode(sentence, out_type=str)
                # A sentence longer than a model takes is cut, never
                # dropped: every part of the text is translated.
                chunks = [
                    encoded[i : i + MAX_PIECES]
                    for i in range(0, len(encoded), MAX_PIECES)
                ] or [[]]
                pieces.append(chunks)
        flat = [chunk for chunks in pieces for chunk in chunks]
        if not flat:
            return text
        unknown = self.source.unk_id()
        translated = []
        # A few sentences at a time, the deadline checked between them: a
        # text the API stopped waiting for does not hold a worker longer.
        for start in range(0, len(flat), BATCH):
            if deadline is not None and time.monotonic() > deadline:
                raise Deadline()
            batch = flat[start : start + BATCH]
            results = self.translator.translate_batch(
                batch,
                beam_size=self.beam,
                # A translation runs about as long as its source: twice the
                # longest sentence, so a model that loops stops early.
                max_decoding_length=2 * max(len(c) for c in batch) + 16,
            )
            for chunk, result in zip(batch, results):
                translated.append(
                    restore_unknowns(
                        self.target.decode(result.hypotheses[0]),
                        [p for p in chunk if self.source.piece_to_id(p) == unknown],
                        self.target_lang,
                    )
                )
        decoded = iter(translated)
        out = []
        it = iter(pieces)
        for paragraph in paragraphs:
            parts = []
            for _ in paragraph:
                chunks = next(it)
                parts.append(" ".join(next(decoded) for _ in chunks))
            out.append(" ".join(parts))
        return "\n".join(out)


class Server:
    def __init__(self, models_dir, workers, threads, beam, queue, deadline=14.0):
        # Seconds a text may take; past it the server stops between two
        # batches and answers 504.
        self.deadline = deadline
        self.models = {}
        for directory in sorted(Path(models_dir).iterdir()):
            current = directory / "current"
            if not (current / "lunaway.json").exists():
                continue
            self.models[directory.name] = Model(
                current.resolve(), workers, threads, beam
            )
        if not self.models:
            raise SystemExit(f"no model under {models_dir}")
        # Texts in the server at once: the workers' and those waiting.
        self.slots = threading.BoundedSemaphore(workers + queue)
        log.info("models loaded: %s", ", ".join(sorted(self.models)))

    def route(self, source, target):
        """The models a text goes through, or None."""
        if f"{source}-{target}" in self.models:
            return [self.models[f"{source}-{target}"]]
        first = self.models.get(f"{source}-en")
        second = self.models.get(f"en-{target}")
        if first and second:
            return [first, second]
        return None

    def translate(self, source, target, text):
        route = self.route(source, target)
        if route is None:
            return None
        deadline = time.monotonic() + self.deadline
        for model in route:
            text = model(text, deadline)
        return {
            "text": text,
            "engine": ENGINE,
            "model": " + ".join(m.name for m in route),
        }


def handler_for(server):
    class Handler(BaseHTTPRequestHandler):
        server_version = "lunaway-translate"
        sys_version = ""

        # No access log: a line would name the client, and the API's
        # requests carry the reviews' languages.
        def log_message(self, *args):
            pass

        def answer(self, status, body):
            data = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path != "/health":
                return self.answer(404, {"error": "not found"})
            try:
                pair = "fr-en" if "fr-en" in server.models else sorted(server.models)[0]
                server.models[pair]("Bonjour.")
            except Exception:
                log.exception("the health check could not translate")
                return self.answer(503, {"error": "a model failed"})
            return self.answer(
                200, {"engine": ENGINE, "pairs": sorted(server.models)}
            )

        def do_POST(self):
            if self.path != "/translate":
                return self.answer(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length") or 0)
            if not 0 < length <= MAX_BODY_BYTES:
                return self.answer(400, {"error": "body size"})
            try:
                ask = json.loads(self.rfile.read(length))
                source, target, text = ask["source"], ask["target"], ask["text"]
            except (ValueError, KeyError, TypeError):
                return self.answer(400, {"error": "malformed request"})
            if (
                not isinstance(source, str)
                or not isinstance(target, str)
                or not isinstance(text, str)
                or not LANG.match(source)
                or not LANG.match(target)
                or not text.strip()
                or len(text) > MAX_TEXT_CHARS
            ):
                return self.answer(400, {"error": "invalid request"})
            if not server.slots.acquire(blocking=False):
                return self.answer(503, {"error": "busy"})
            try:
                made = server.translate(source, target, text)
            except Deadline:
                return self.answer(504, {"error": "past the deadline"})
            except Exception:
                # The cause, never the text.
                log.exception("a translation failed (%s to %s)", source, target)
                return self.answer(500, {"error": "translation failed"})
            finally:
                server.slots.release()
            if made is None:
                return self.answer(422, {"error": "no model for this pair"})
            return self.answer(200, made)

    return Handler


def main():
    logging.basicConfig(
        level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr
    )
    host, _, port = os.environ.get(
        "LUNAWAY_TRANSLATE_LISTEN", "127.0.0.1:2324"
    ).rpartition(":")
    server = Server(
        os.environ.get("LUNAWAY_TRANSLATE_MODELS", "/srv/translate/models"),
        workers=int(os.environ.get("LUNAWAY_TRANSLATE_WORKERS", "2")),
        threads=int(os.environ.get("LUNAWAY_TRANSLATE_THREADS", "2")),
        beam=int(os.environ.get("LUNAWAY_TRANSLATE_BEAM", "4")),
        queue=int(os.environ.get("LUNAWAY_TRANSLATE_QUEUE", "8")),
        deadline=float(os.environ.get("LUNAWAY_TRANSLATE_DEADLINE", "14")),
    )
    httpd = ThreadingHTTPServer((host, int(port)), handler_for(server))
    httpd.daemon_threads = True
    log.info("listening on %s:%s", host, port)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
