#!/usr/bin/env python3
"""Original Wave Catch music and sound effects.

Every note uses a short attack and release so loops and one-shots do not click.
Run from the repo root. Writes M4A files into WaveCatchApp/WaveCatch/Audio.
"""

from __future__ import annotations

import math
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join("WaveCatchApp", "WaveCatch", "Audio")
BPM = 120
BEAT = 60.0 / BPM
BARS = 16
LOOP = BARS * 4 * BEAT  # 32 seconds

# C major pentatonic
PENTA = [60, 62, 64, 67, 69, 72, 74, 76]


def midi(note: float) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def env(n: int, attack: float, release: float) -> np.ndarray:
    curve = np.ones(n, dtype=np.float64)
    a = min(n, max(1, int(attack * SR)))
    r = min(n - a, max(1, int(release * SR)))
    curve[:a] = np.linspace(0.0, 1.0, a)
    if r > 0:
        curve[-r:] *= np.linspace(1.0, 0.0, r)
    return curve


def silence(seconds: float) -> np.ndarray:
    return np.zeros(max(1, int(seconds * SR)), dtype=np.float64)


def place(buffer: np.ndarray, clip: np.ndarray, at: float) -> None:
    start = int(at * SR)
    if start >= len(buffer):
        return
    end = min(len(buffer), start + len(clip))
    buffer[start:end] += clip[: end - start]


def tone(freq: float, seconds: float, volume: float, attack: float, release: float, partials=None) -> np.ndarray:
    n = max(1, int(seconds * SR))
    t = np.arange(n, dtype=np.float64) / SR
    if partials is None:
        partials = [(1.0, 1.0), (2.0, 0.18)]
    sample = np.zeros(n, dtype=np.float64)
    for ratio, gain in partials:
        sample += gain * np.sin(2 * math.pi * freq * ratio * t)
    sample *= env(n, attack, release) * volume
    return sample


def noise(seconds: float, volume: float, attack: float, release: float, color: float = 0.0) -> np.ndarray:
    n = max(1, int(seconds * SR))
    white = np.random.default_rng(7).uniform(-1, 1, n)
    if color > 0:
        kernel = max(1, int(color * SR))
        white = np.convolve(white, np.ones(kernel) / kernel, mode="same")
    return white * env(n, attack, release) * volume


def wood(freq: float) -> np.ndarray:
    click = noise(0.04, 0.35, 0.001, 0.012, color=0.0008)
    body = tone(freq, 0.04, 0.45, 0.001, 0.018, partials=[(1.0, 1.0), (2.3, 0.35)])
    n = max(len(click), len(body))
    mix = np.zeros(n)
    mix[: len(click)] += click
    mix[: len(body)] += body
    return mix


def marimba(freq: float, seconds: float = 0.42) -> np.ndarray:
    return tone(
        freq,
        seconds,
        0.7,
        0.008,
        0.12,
        partials=[(1.0, 0.55), (4.0, 0.85), (9.2, 0.18)],
    )


def write_wav(path: str, sample: np.ndarray) -> None:
    peak = np.max(np.abs(sample)) if len(sample) else 1
    if peak > 0.98:
        sample = sample / peak * 0.98
    pcm = np.clip(sample, -1, 1)
    ints = (pcm * 32767).astype(np.int16)
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(ints.tobytes())


def to_m4a(wav_path: str, m4a_path: str) -> None:
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", wav_path,
            "-c:a", "aac", "-b:a", "96k",
            m4a_path,
        ]
    )
    os.remove(wav_path)


def save(name: str, sample: np.ndarray) -> None:
    wav_path = os.path.join(OUT, name + ".wav")
    m4a_path = os.path.join(OUT, name + ".m4a")
    write_wav(wav_path, sample)
    to_m4a(wav_path, m4a_path)
    print(name, round(len(sample) / SR, 3), "s")


def lead_notes() -> list[tuple[float, int, float]]:
    pattern = [60, 64, 67, 69, 67, 64, 62, 60]
    notes = []
    for bar in range(BARS):
        phrase = pattern if bar % 4 < 2 else [62, 64, 67, 72, 69, 67, 64, 62]
        for index, note in enumerate(phrase):
            if index % 5 == 4:
                continue
            start = (bar * 4 + index * 0.5) * BEAT
            notes.append((start, note, 0.42 * BEAT))
    return notes


def render_music(layer: str) -> np.ndarray:
    buffer = np.zeros(int(LOOP * SR))
    for start, note, length in lead_notes():
        freq = midi(note if layer == "base" else note + 12)
        volume = 0.20 if layer == "base" else 0.11
        clip = tone(freq, length, volume, 0.05, 0.12, partials=[(1.0, 1.0), (2.0, 0.12), (3.0, 0.03)])
        place(buffer, clip, start)
    # C D E G — the same pentatonic as the lead, an octave down.
    bass_cycle = [36, 43, 38, 40]
    for bar in range(BARS):
        root = bass_cycle[bar % 4]
        for beat in (0, 2):
            start = (bar * 4 + beat) * BEAT
            clip = tone(midi(root), 0.46, 0.14 if layer == "base" else 0.05, 0.05, 0.14, partials=[(1.0, 1.0)])
            place(buffer, clip, start)
    hat_every = 2 if layer == "base" else 1
    for step in range(BARS * 8):
        if step % hat_every != 0:
            continue
        start = step * (BEAT / 2)
        if step % 4 == 0:
            kick = tone(70, 0.14, 0.14 if layer == "base" else 0.08, 0.018, 0.09, partials=[(1.0, 1.0)])
            thump = noise(0.09, 0.06, 0.01, 0.06, color=0.004)
            kick[: len(thump)] += thump
            place(buffer, kick, start)
        else:
            hat = noise(0.05, 0.035 if layer == "base" else 0.05, 0.01, 0.028, color=0.0004)
            place(buffer, hat, start)
    edge = int(0.04 * SR)
    buffer[:edge] *= np.linspace(0, 1, edge)
    buffer[-edge:] *= np.linspace(1, 0, edge)
    return buffer


def build_effects() -> None:
    save("tick", wood(740))
    save("tock", wood(560))
    for index, note in enumerate(PENTA):
        save(f"catch-{index}", marimba(midi(note)))
    golden = silence(0.7)
    for index, note in enumerate([72, 76, 79]):
        place(golden, marimba(midi(note), 0.36), index * 0.14)
    save("golden", golden)
    pop = tone(880, 0.12, 0.45, 0.004, 0.06)
    bubble = tone(1320, 0.1, 0.25, 0.004, 0.05)
    pop[: len(bubble)] += bubble
    save("ring", pop)
    zap = tone(1800, 0.16, 0.28, 0.002, 0.08, partials=[(1.0, 0.4), (1.7, 0.3)])
    hiss = noise(0.12, 0.25, 0.001, 0.06)
    zap[: len(hiss)] += hiss
    thud = tone(78, 0.28, 0.55, 0.004, 0.12, partials=[(1.0, 1.0)])
    sting = np.zeros(max(len(zap), len(thud)))
    sting[: len(zap)] += zap
    sting[: len(thud)] += thud
    save("sting", sting)
    splash = noise(0.28, 0.55, 0.004, 0.16, color=0.003)
    splash[: int(0.2 * SR)] += tone(180, 0.2, 0.2, 0.01, 0.1)
    save("miss", splash)
    whoosh = noise(0.55, 0.4, 0.08, 0.18, color=0.002)
    blip = marimba(midi(76), 0.22)
    tier = np.zeros(len(whoosh) + len(blip))
    tier[: len(whoosh)] += whoosh
    place(tier, blip * 0.8, 0.32)
    save("tier", tier)
    save("whoosh", noise(0.7, 0.45, 0.05, 0.25, color=0.0015))
    crash = noise(0.6, 0.6, 0.002, 0.28, color=0.002)
    boom = tone(90, 0.45, 0.35, 0.004, 0.2)
    crash[: len(boom)] += boom
    save("crash", crash)
    best = silence(0.55)
    place(best, marimba(midi(67), 0.28), 0)
    place(best, marimba(midi(72), 0.32), 0.16)
    save("new-best", best)
    fanfare = silence(1.3)
    for index, note in enumerate([60, 64, 67, 72]):
        place(fanfare, marimba(midi(note), 0.4), index * 0.16)
    save("fanfare", fanfare)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    np.random.seed(7)
    save("music-base", render_music("base"))
    save("music-wave", render_music("wave"))
    build_effects()


if __name__ == "__main__":
    main()
