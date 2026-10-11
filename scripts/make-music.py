#!/usr/bin/env python3
"""Generate Mossgate's looping background music.

Writes two seamless-loop stereo WAVs into ios/Mossgate/Resources/Music/:

    dusk.wav    Mossgate Dusk — calm, mysterious, music-box over a deep drone
    ember.wav   Ember Caves  — warmer and more ominous, heartbeat pulse

Both are additive synthesis (no filters, so no aliasing) and are rendered
longer than their loop length, with the overflow wrapped back onto the head,
which makes the loop point mathematically seamless.

    ./scripts/make-music.py            # regenerate both tracks
    ./scripts/make-music.py --preview  # also print a level report
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "ios" / "Mossgate" / "Resources" / "Music"
SR = 44100

# ── note helpers ──────────────────────────────────────────────────────────────

def hz(semitones_from_a4: float) -> float:
    """A4 = 440 Hz."""
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


NOTE = {
    # octave 3
    "D3": hz(-19), "E3": hz(-17), "F3": hz(-16), "G3": hz(-14), "A3": hz(-12), "Bb3": hz(-11), "C4": hz(-9),
    # octave 4
    "D4": hz(-7), "E4": hz(-5), "F4": hz(-4), "G4": hz(-2), "A4": hz(0), "Bb4": hz(1), "C5": hz(3),
    # octave 5
    "D5": hz(5), "E5": hz(7), "F5": hz(8), "G5": hz(10), "A5": hz(12), "C6": hz(15), "D6": hz(17),
    # low
    "A1": hz(-36), "C2": hz(-33), "D2": hz(-31), "F2": hz(-28), "G2": hz(-26), "A2": hz(-24), "Bb2": hz(-22),
}


# ── envelopes ─────────────────────────────────────────────────────────────────

def env_pluck(n: int, attack: float = 0.004, curve: float = 5.0) -> np.ndarray:
    """Fast attack, exponential decay — bells, music box, marimba."""
    t = np.linspace(0, 1, n, endpoint=False)
    a = int(max(1, attack * SR))
    e = np.exp(-curve * t)
    e[:a] *= np.linspace(0, 1, a)
    return e


def env_pad(n: int, attack: float, release: float, level: float = 0.75) -> np.ndarray:
    """Slow swell in, hold, slow fade out."""
    t = np.linspace(0, 1, n, endpoint=False)
    e = np.full(n, level)
    a = int(max(1, attack * SR))
    r = int(max(1, release * SR))
    e[:a] *= np.linspace(0, 1, a) ** 1.5
    e[-r:] *= np.linspace(1, 0, r) ** 1.5
    return e


# ── voices ────────────────────────────────────────────────────────────────────

def voice_pluck(freq: float, dur: float, amp: float, bright: float = 0.35,
                detune: float = 0.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t)
    out += bright * 0.5 * np.sin(2 * np.pi * freq * 2.001 * t)      # octave shimmer
    out += bright * 0.25 * np.sin(2 * np.pi * freq * 3.002 * t)
    if detune:
        out += 0.4 * np.sin(2 * np.pi * (freq + detune) * t)
    return out * env_pluck(n) * amp


def voice_pad(freqs: list[float], dur: float, amp: float,
              attack: float = 1.2, release: float = 1.6) -> np.ndarray:
    """Soft additive pad — each note as a detuned pair, plus a faint 2nd harmonic."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        out += np.sin(2 * np.pi * f * t)
        out += 0.85 * np.sin(2 * np.pi * (f * 1.0035) * t)          # slow beating
        out += 0.12 * np.sin(2 * np.pi * f * 2 * t)
    out /= max(1, len(freqs) * 2)
    return out * env_pad(n, attack, release) * amp


def voice_drone(freq: float, dur: float, amp: float) -> np.ndarray:
    """Deep bed with a very slow amplitude LFO so it breathes."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * freq * t)
    out += 0.7 * np.sin(2 * np.pi * (freq * 1.002) * t)
    out += 0.35 * np.sin(2 * np.pi * freq * 2 * t)
    out += 0.15 * np.sin(2 * np.pi * freq * 3 * t)
    lfo = 0.85 + 0.15 * np.sin(2 * np.pi * 0.055 * t)
    return out * lfo * amp


def voice_noise(dur: float, amp: float, smooth: int = 900, seed: int = 7) -> np.ndarray:
    """Smoothed noise — a soft cave rumble. Moving average is plenty here."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    x = rng.standard_normal(n)
    k = np.ones(smooth) / smooth
    return np.convolve(x, k, mode="same") * amp


def voice_heart(dur: float, amp: float) -> np.ndarray:
    """Muffled low thump for the Ember pulse."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 58 * np.exp(-6 * t)                       # pitch drop
    out = np.sin(2 * np.pi * np.cumsum(f) / SR)
    return out * env_pluck(n, attack=0.008, curve=9.0) * amp


# ── track building ────────────────────────────────────────────────────────────

def place(buf: np.ndarray, x: np.ndarray, at: float, pan: float = 0.0) -> None:
    """Mix `x` into stereo `buf` (shape [n, 2]) at `at` seconds. Wraps past the end
    so notes that cross the loop point land on the head — this is what makes the
    loop seamless without a crossfade."""
    i = int(at * SR)
    n = len(x)
    L = len(buf)
    idx = (np.arange(n) + i) % L
    left = np.sqrt(0.5 * (1 - pan))
    right = np.sqrt(0.5 * (1 + pan))
    buf[idx, 0] += x * left
    buf[idx, 1] += x * right


def write_wav(path: Path, buf: np.ndarray, peak: float = 0.72) -> None:
    m = float(np.max(np.abs(buf))) or 1.0
    data = np.clip(buf / m * peak, -1.0, 1.0)
    ints = (data * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        # interleave L/R
        w.writeframes(ints.astype("<i2").tobytes())


def make_dusk() -> np.ndarray:
    """Mossgate Dusk: A minor, ~48 BPM, 8 bars, music box over a deep drone."""
    bpm = 48.0
    beat = 60.0 / bpm
    bars = 8
    length = bars * 4 * beat                     # 40.0 s
    n = int(length * SR)
    buf = np.zeros((n, 2))

    # Deep bed — always present, exactly the loop length
    place(buf, voice_drone(NOTE["A1"], length, 0.30), 0.0)
    place(buf, voice_drone(NOTE["A2"] * 0.5, length, 0.10), 0.0)

    # Pad progression: Am — Fmaj7 — Cmaj — Gsus4  (2 bars each)
    prog = [
        [NOTE["A3"], NOTE["C4"], NOTE["E4"]],
        [NOTE["F3"], NOTE["A3"], NOTE["C4"], NOTE["E4"]],
        [NOTE["C4"], NOTE["E4"], NOTE["G4"]],
        [NOTE["G3"], NOTE["C4"], NOTE["D4"]],
    ]
    for i, chord in enumerate(prog):
        at = i * 2 * 4 * beat
        dur = 2 * 4 * beat
        place(buf, voice_pad(chord, dur, 0.16, attack=1.4, release=1.8), at, pan=-0.12)

    # Music-box melody — sparse, A minor pentatonic, deterministic
    mel = ["A4", "C5", "E5", "D5", "C5", "A4", "G4", "A4",
           "C5", "D5", "C5", "A4", "G4", "E4", "G4", "A4"]
    for i, name in enumerate(mel):
        at = i * 2 * beat + (beat * 0.5 if i % 4 == 2 else 0.0)
        amp = 0.30 if i % 2 == 0 else 0.22
        place(buf, voice_pluck(NOTE[name], 1.9, amp, bright=0.4),
              at, pan=0.22 if i % 2 else -0.10)

    # Distant high bells on the half-bar
    for i in range(bars):
        if i % 2 == 1:
            place(buf, voice_pluck(NOTE["A5"], 3.2, 0.11, bright=0.6, detune=0.7),
                  i * 4 * beat + beat * 1.5, pan=0.4)
    return buf


def make_ember() -> np.ndarray:
    """Ember Caves: D minor, ~54 BPM, 8 bars, heartbeat under a warm pad."""
    bpm = 54.0
    beat = 60.0 / bpm
    bars = 8
    length = bars * 4 * beat
    n = int(length * SR)
    buf = np.zeros((n, 2))

    # Low bed + cave rumble
    place(buf, voice_drone(NOTE["D2"], length, 0.32), 0.0)
    place(buf, voice_drone(NOTE["A2"] * 0.5, length, 0.11), 0.0)
    place(buf, voice_noise(length, 0.05, smooth=1400, seed=11), 0.0, pan=0.1)

    # Warmer, tenser progression: Dm — Bb — Gm — A
    prog = [
        [NOTE["D3"], NOTE["F3"], NOTE["A3"]],
        [NOTE["Bb2"], NOTE["D3"], NOTE["F3"]],
        [NOTE["G3"], NOTE["Bb3"], NOTE["D4"]],
        [NOTE["A3"], NOTE["C4"] * 0.5, NOTE["E4"]],   # A major = the tension
    ]
    for i, chord in enumerate(prog):
        at = i * 2 * 4 * beat
        dur = 2 * 4 * beat
        place(buf, voice_pad(chord, dur, 0.19, attack=1.0, release=1.4), at, pan=0.10)

    # Heartbeat: soft thump on beats 1 and 3 of each bar
    for b in range(bars):
        base = b * 4 * beat
        place(buf, voice_heart(0.45, 0.30), base, pan=-0.05)
        place(buf, voice_heart(0.40, 0.20), base + 2 * beat, pan=-0.05)

    # Low marimba motif — D minor, sparse
    motif = ["D4", "F4", "A4", "G4", "F4", "D4", "C4", "D4",
             "F4", "A4", "Bb4", "A4", "G4", "F4", "E4", "D4"]
    for i, name in enumerate(motif):
        at = i * 2 * beat
        amp = 0.26 if i % 4 == 0 else 0.18
        place(buf, voice_pluck(NOTE[name] * 0.5, 1.6, amp, bright=0.5),
              at, pan=0.26 if i % 2 else -0.16)

    # Airy high accents, like shifting embers
    for i in range(bars):
        if i % 3 == 2:
            place(buf, voice_pluck(NOTE["D6"], 2.6, 0.10, bright=0.7, detune=1.1),
                  i * 4 * beat + beat * 2.5, pan=0.45)
    return buf


def encode_aac(wav_path: Path, m4a_path: Path, bitrate: int = 128_000) -> bool:
    """WAV -> AAC/m4a via the system afconvert. Returns False if unavailable."""
    m4a_path.parent.mkdir(parents=True, exist_ok=True)
    res = subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-b", str(bitrate),
         str(wav_path), str(m4a_path)],
        capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  afconvert failed: {res.stderr.strip()}", file=sys.stderr)
        return False
    return True


def decoded_seconds(path: Path) -> float:
    """Duration of an audio file, read back with afinfo."""
    res = subprocess.run(["afinfo", str(path)], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if "estimated duration" in line:
            return float(line.split(":")[1].split("sec")[0].strip())
    return 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="print levels after writing")
    ap.add_argument("--keep-wav", action="store_true", help="also keep the WAV files")
    args = ap.parse_args()

    tracks = {"dusk": make_dusk(), "ember": make_ember()}
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for name, buf in tracks.items():
            wav_path = tmpdir / f"{name}.wav"
            write_wav(wav_path, buf)
            secs = len(buf) / SR
            raw_mb = wav_path.stat().st_size / 1024 / 1024

            final = OUT_DIR / f"{name}.wav"
            note = ""
            if encode_aac(wav_path, OUT_DIR / f"{name}.m4a"):
                encoded = OUT_DIR / f"{name}.m4a"
                mb = encoded.stat().st_size / 1024 / 1024
                dec = decoded_seconds(encoded)
                note = (f"AAC {mb:5.2f} MB (from {raw_mb:5.2f} MB WAV), "
                        f"decoded {dec:.2f}s vs source {secs:.2f}s")
                final = encoded
            else:
                shutil.copy(wav_path, OUT_DIR / f"{name}.wav")
                note = f"WAV {raw_mb:5.2f} MB (afconvert unavailable)"

            if args.keep_wav and final.suffix == ".m4a":
                shutil.copy(wav_path, OUT_DIR / f"{name}.wav")

            print(f"{name:6s} {secs:5.1f}s loop  -> {final.relative_to(REPO)}")
            print(f"       {note}")
            if args.preview:
                rms = float(np.sqrt(np.mean(buf ** 2)))
                print(f"       peak={np.max(np.abs(buf)):.3f} rms={rms:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
