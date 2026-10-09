"""Writes the chime the guidance plays before a spoken alert.

    python3 tool/sounds/chime.py      # from app/, standard library only

The voice says a speed camera, a closure or a new route right after this
sound, in every voice mode that speaks: it tells the driver that what
follows is an alert, not the next turn. Two notes a fourth apart, rising
(G5 then C6), each struck softly and dying away like a small bell, in
300 ms. They sit above the rumble of a cab (road and engine noise lie
mostly under 500 Hz) without the shrillness of a beep, and stay apart from
the system's own notification sounds.

The output is the same bytes on every run: mono, 16-bit, 22 050 Hz, in
assets/sounds/alert_chime.wav, which the app hands to its platform side
once per run (lunaway_nav `PlatformVoice.setChime`).
"""

import math
import os
import struct
import wave

RATE = 22050
LENGTH_S = 0.30

# (start in seconds, frequency in hertz, decay time constant in seconds)
NOTES = [
    (0.000, 783.99, 0.070),
    (0.105, 1046.50, 0.085),
]

# The harmonics over each fundamental, with their share: a little body,
# dying faster than the fundamental, as a struck bar does.
PARTIALS = [(1, 1.0), (2, 0.22), (3, 0.06)]

ATTACK_S = 0.010
FADE_OUT_S = 0.025
PEAK = 0.6


def note(t, start, freq, decay):
    """One struck note at time t: a raised-cosine attack, then an
    exponential decay; silent before it starts."""
    local = t - start
    if local < 0:
        return 0.0
    attack = 0.5 - 0.5 * math.cos(math.pi * local / ATTACK_S) if local < ATTACK_S else 1.0
    value = 0.0
    for harmonic, share in PARTIALS:
        # Upper partials fade faster: a soft mallet, not a hard beep.
        fade = math.exp(-local / (decay / harmonic ** 0.5))
        value += share * fade * math.sin(2 * math.pi * freq * harmonic * local)
    return attack * value


def samples():
    count = int(RATE * LENGTH_S)
    raw = []
    for i in range(count):
        t = i / RATE
        v = sum(note(t, *n) for n in NOTES)
        # The tail goes to silence, so the voice that follows never starts
        # over a click.
        left = LENGTH_S - t
        if left < FADE_OUT_S:
            v *= 0.5 - 0.5 * math.cos(math.pi * left / FADE_OUT_S)
        raw.append(v)
    peak = max(abs(v) for v in raw)
    return [int(round(v / peak * PEAK * 32767)) for v in raw]


def main():
    app = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = os.path.join(app, "assets", "sounds")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "alert_chime.wav")
    data = b"".join(struct.pack("<h", s) for s in samples())
    with wave.open(out, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)
    print("wrote %s (%d bytes, %d ms)" % (out, os.path.getsize(out), int(LENGTH_S * 1000)))


if __name__ == "__main__":
    main()
