#!/usr/bin/env python3
"""Mix a render of the app's WCAUDIO log onto the silent proof video."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
AUDIO = os.path.join(ROOT, "WaveCatchApp", "WaveCatch", "Audio")
LINE = re.compile(r"WCAUDIO\s+([0-9.]+)\s+(\S+)\s+([-0-9.]+)\s+([-0-9.]+)")


def read_wav(path: str) -> np.ndarray:
    with wave.open(path, "rb") as handle:
        frames = handle.readframes(handle.getnframes())
        rate = handle.getframerate()
        channels = handle.getnchannels()
    pcm = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32767.0
    if channels > 1:
        pcm = pcm.reshape(-1, channels).mean(axis=1)
    if rate != SR:
        raise SystemExit(f"{path} is {rate} Hz, expected {SR}")
    return pcm


def decode(name: str, cache: str) -> np.ndarray:
    source = os.path.join(AUDIO, name + ".m4a")
    if not os.path.exists(source):
        raise SystemExit(f"missing audio file {source}")
    wav_path = os.path.join(cache, name + ".wav")
    if not os.path.exists(wav_path):
        subprocess.check_call(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", source, wav_path]
        )
    return read_wav(wav_path)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: mux-proof-audio.py video log start_time output")
    video, log_path, start_path, output = sys.argv[1:]
    record_start = float(open(start_path).read().strip())
    events = []
    for line in open(log_path, errors="replace"):
        match = LINE.search(line)
        if match:
            events.append((float(match.group(1)), match.group(2), float(match.group(3)), float(match.group(4))))
    if not events:
        raise SystemExit("no WCAUDIO events in the test log")
    print(
        f"record_start {record_start:.3f} first_event {events[0][0]:.3f} "
        f"delta {events[0][0] - record_start:.3f}s events {len(events)}"
    )

    duration = float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video],
        text=True,
    ).strip())
    total = int(duration * SR)
    mix = np.zeros(total, dtype=np.float64)
    cache = "/tmp/wavecatch-audio-cache"
    os.makedirs(cache, exist_ok=True)
    bank = {}

    def clip(name: str) -> np.ndarray:
        if name not in bank:
            bank[name] = decode(name, cache)
        return bank[name]

    music_start = None
    music_gain = 0.18
    wave_gain = 0.14
    wave_spans = []
    wave_open = None
    one_shots = []
    for stamp, name, pan, volume in events:
        if name == "music-base" and music_start is None:
            music_start = stamp
            music_gain = volume
        elif name == "music-wave-on":
            wave_open = stamp
            wave_gain = volume
        elif name == "music-wave-off" and wave_open is not None:
            wave_spans.append((wave_open, stamp))
            wave_open = None
        elif name not in {"music-base", "music-wave-on", "music-wave-off"}:
            one_shots.append((stamp, name, pan, volume))
    if wave_open is not None:
        wave_spans.append((wave_open, record_start + duration))

    if music_start is not None:
        base = clip("music-base")
        layer = clip("music-wave")
        count = len(base)
        video_time = np.arange(total) / SR
        elapsed = record_start + video_time - music_start
        positive = elapsed >= 0
        index = np.mod(elapsed, count / SR) * SR
        index = np.clip(index.astype(np.int64), 0, count - 1)
        music = np.zeros(total)
        music[positive] = base[index[positive]] * music_gain
        if len(layer) == count:
            for begin, end in wave_spans:
                mask = positive & (video_time >= begin - record_start) & (video_time < end - record_start)
                music[mask] += layer[index[mask]] * wave_gain
        for stamp, name, _, _ in one_shots:
            if name in {"tier", "whoosh", "new-best", "fanfare"}:
                start = int((stamp - record_start) * SR)
                music[max(0, start): min(total, start + int(0.85 * SR))] *= 0.7
        mix += music

    for stamp, name, pan, volume in one_shots:
        sample = clip(name)
        if len(sample) < 2:
            continue
        start = int((stamp - record_start) * SR)
        if start >= total or start + len(sample) <= 0:
            continue
        left = max(0, -start)
        right = min(len(sample), total - start)
        dest = max(0, start)
        # A small constant-power pan so a corner still reads in mono playback.
        gain = volume * (0.85 + 0.15 * (1 - min(1, abs(pan))))
        mix[dest: dest + (right - left)] += sample[left:right] * gain

    peak = float(np.max(np.abs(mix))) if total else 0.0
    if peak < 0.01:
        raise SystemExit(f"soundtrack is silent (peak {peak:.5f})")
    if peak > 0.98:
        mix *= 0.98 / peak
    pcm = (np.clip(mix, -1, 1) * 32767).astype(np.int16)
    wav_path = "/tmp/wavecatch-proof/soundtrack.wav"
    with wave.open(wav_path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())

    subprocess.check_call(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", video,
            "-i", wav_path,
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-shortest",
            output,
        ]
    )
    print(f"muxed {len(events)} audio events onto {duration:.1f}s")


if __name__ == "__main__":
    main()
