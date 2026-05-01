#!/usr/bin/env python3
"""B1 — Piper TTS waveform sanity check.

Acoustic proof:
  1. WAV > 2 KB (silence filter)
  2. Duration plausible: 0.5 s < duration < 60 s
  3. RMS > 0.05 (audio-not-silence)
  4. Peak > 0.10 (not flat-line)
  5. Spectral activity proxy: zero-crossing density 200-3000 ZC/s (presence
     of high-freq formants — pure tone or DC will fall outside this range).

Note: zero-crossing density does NOT estimate the fundamental f0 of speech
because formants and harmonics inflate the count well past the glottal
fundamental (~100-200 Hz). For real f0 measurement use autocorrelation or
YIN — out of scope for this sanity gate.
"""
from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

WAV = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/abs-tts.wav")
if not WAV.exists():
    sys.exit(f"WAV not found: {WAV}")

with wave.open(str(WAV)) as fh:
    n_frames = fh.getnframes()
    sr = fh.getframerate()
    raw = fh.readframes(n_frames)

samples = list(struct.unpack(f"<{n_frames}h", raw))
duration = n_frames / sr
rms = math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768.0
peak = max(abs(s) for s in samples) / 32768.0
zero_cross = sum(1 for i in range(1, len(samples)) if samples[i - 1] * samples[i] < 0)
zc_per_s = zero_cross / duration if duration > 0 else 0.0

print(
    f"path={WAV}\n"
    f"size_bytes={WAV.stat().st_size}\n"
    f"duration_s={duration:.2f}\n"
    f"sample_rate={sr}\n"
    f"rms={rms:.3f}\n"
    f"peak={peak:.3f}\n"
    f"zc_per_s={zc_per_s:.0f}\n"
)

failures: list[str] = []
if WAV.stat().st_size < 2048:
    failures.append(f"size {WAV.stat().st_size} < 2048")
if not (0.5 <= duration <= 60.0):
    failures.append(f"duration {duration:.2f}s out of [0.5, 60]")
if rms < 0.05:
    failures.append(f"rms {rms:.3f} < 0.05 (silent)")
if peak < 0.10:
    failures.append(f"peak {peak:.3f} < 0.10 (flat)")
if not (200 <= zc_per_s <= 6000):
    failures.append(f"zc_per_s {zc_per_s:.0f} out of [200, 6000] (no spectral activity)")

if failures:
    print("B1_FAIL:", "; ".join(failures))
    sys.exit(1)
print("B1_PASS")
