#!/usr/bin/env python3
"""Synthesize the 120 BPM bed track + UI SFX for the shape-motion loop.

Everything lives on an exact beat grid (1 beat = 0.5 s, 7 bars = 14.0 s).
A spectral-flux pass verifies the grid at the end; the loop point is dry.
"""
import numpy as np
import wave

SR = 44100
BPM = 120.0
BEAT = 60.0 / BPM            # 0.5 s
N_BEATS = 28
DUR = N_BEATS * BEAT         # 14.0 s
N = int(round(DUR * SR))
t_axis = np.arange(N) / SR

rng = np.random.default_rng(7)
mixL = np.zeros(N)
mixR = np.zeros(N)


def beats_to_sec(b):
    return np.asarray(b) * BEAT


def add(sig, at_beat, gain=1.0, pan=0.0):
    """Add a signal starting exactly at a beat position."""
    start = int(round(beats_to_sec(at_beat) * SR))
    end = min(start + len(sig), N)
    if start >= N or end <= start:
        return
    seg = sig[: end - start] * gain
    gl = gain * min(1.0, 1.0 - pan)
    gr = gain * min(1.0, 1.0 + pan)
    mixL[start:end] += seg * gl
    mixR[start:end] += seg * gr


def env_exp(n, decay):
    return np.exp(-np.arange(n) / SR * decay)


def kick(vel=1.0):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = 150 * np.exp(-t * 26) + 46
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env_exp(n, 16)
    clickn = int(0.004 * SR)
    click = np.zeros(n)
    click[:clickn] = rng.uniform(-1, 1, clickn) * env_exp(clickn, 900)
    return (body * 0.95 + click * 0.5) * vel


def hat(open_=False, vel=1.0):
    n = int((0.24 if open_ else 0.045) * SR)
    noise = rng.uniform(-1, 1, n)
    # crude high-pass: difference chain
    hp = np.diff(noise, prepend=0.0)
    hp = np.diff(hp, prepend=0.0)
    hp *= env_exp(n, 55 if open_ else 160)
    return hp * 0.12 * vel


def clap(vel=1.0):
    n = int(0.20 * SR)
    out = np.zeros(n)
    for k, off in enumerate([0.0, 0.011, 0.023]):
        s = int(off * SR)
        m = n - s
        noise = rng.uniform(-1, 1, m)
        bp = np.diff(noise, prepend=0.0)  # band-ish
        bp = bp - np.concatenate([[0], bp[:-1]])
        out[s:] += bp * env_exp(m, 26 - k * 5)
    return out * 0.35 * vel


def bass_note(freq, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.42), (3, 0.20), (4, 0.09)]:
        sig += a * np.sin(2 * np.pi * freq * h * t)
    sig *= env_exp(n, 9)
    rel = int(0.01 * SR)
    sig[-rel:] *= np.linspace(1, 0, rel)
    return sig * 0.30 * vel


def stab(freqs, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for f in freqs:
        for h, a in [(1, 1.0), (2, 0.35), (3, 0.14), (5, 0.05)]:
            sig += a * np.sin(2 * np.pi * f * h * t + rng.uniform(0, 6.28))
    sig *= env_exp(n, 11)
    return sig * 0.045 * vel


# ---------------------------------------------------------------- bed track
A1, C2, E2, G1, G2 = 55.00, 65.41, 82.41, 49.00, 98.00
A2, C3, E3 = 110.0, 130.8, 164.8
BASS_PATTERN = [A1, A1, A2, A1, G1, G1, A2, C2]  # 8 eighths per bar

for b in range(N_BEATS):
    bar = b // 4
    # kick on every beat
    add(kick(1.0 if b % 4 == 0 else 0.9), b)
    # closed hats on 8ths
    for e in range(2):
        pos = b + e * 0.5
        v = 1.0 if e == 0 else 0.62
        if bar == 0 and e == 1:
            v = 0.4
        add(hat(False, v), pos, pan=0.25)
    # open hat on off-beat from bar 3
    if bar >= 2 and bar <= 6:
        add(hat(True, 0.5), b + 0.5, pan=0.3)
    # clap on beats 2 & 4 of each bar, bars 4-6
    if 3 <= bar <= 5 and b % 4 in (1, 3):
        add(clap(0.9), b)

# bassline from bar 3 on
for bar in range(2, 7):
    for e in range(8):
        f = BASS_PATTERN[e]
        dur = BEAT * 0.5 * 0.9
        add(bass_note(f, dur, 1.0 if e % 2 == 0 else 0.8), bar * 4 + e * 0.5)

# chord stabs at bar starts of bars 2/4/6 (Am)
am = [220.0, 261.63, 329.63]
for b in (4, 12, 20):
    add(stab(am, 0.5, 1.0), b)
    add(stab([f * 2 for f in am], 0.4, 0.5), b, pan=0.3)

# ---------------------------------------------------------------- UI SFX
def sfx_click():
    n = int(0.03 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 1800 * t) * env_exp(n, 300)
    nz = np.diff(rng.uniform(-1, 1, n), prepend=0) * env_exp(n, 700)
    return body * 0.5 + nz * 0.25


def sfx_pop(f0=700, f1=220, dur=0.07):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * np.exp(-t * 30) + f1
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_exp(n, 60) * 0.55


def sfx_snap():
    n = int(0.05 * SR)
    nz = np.diff(rng.uniform(-1, 1, n), prepend=0) * env_exp(n, 220)
    tone = np.sin(2 * np.pi * 900 * np.arange(n) / SR) * env_exp(n, 160)
    return (nz * 0.4 + tone * 0.4)


def sfx_whoosh(up=True, dur=0.28):
    n = int(dur * SR)
    nz = rng.uniform(-1, 1, n)
    lp = np.zeros(n)
    acc = 0.0
    sweep = np.linspace(0.06, 0.5 if up else 0.02, n) if up else np.linspace(0.5, 0.06, n)
    for i in range(n):
        acc += sweep[i] * (nz[i] - acc)
        lp[i] = acc
    win = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return lp * win * 2.2


def sfx_blip(seq=(659.26, 880.0), dur=0.09):
    out = np.zeros(int((dur * len(seq)) * SR))
    for i, f in enumerate(seq):
        n = int(dur * SR)
        t = np.arange(n) / SR
        s = np.sin(2 * np.pi * f * t) * env_exp(n, 26)
        out[i * n : (i + 1) * n] += s * 0.30
    return out


def sfx_key():
    n = int(0.025 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 2400 * t) * env_exp(n, 420) * 0.3
            + np.diff(rng.uniform(-1, 1, n), prepend=0) * env_exp(n, 800) * 0.18)


def sfx_riser(dur=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 300 + 1400 * (t / dur) ** 2
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.linspace(0, 1, n) ** 2 * 0.12


add(sfx_click(), 1.0)
add(sfx_pop(), 1.05)                       # button inverts + morph out
for k, b in enumerate([2.0, 2.5, 3.0]):
    add(sfx_key(), b, 0.5)                 # loader percentage ticks
add(sfx_blip((659.26, 880.0)), 3.0)        # checkmark success
add(sfx_whoosh(True), 4.0, 0.8)            # island flies up
add(sfx_pop(600, 180), 5.0)                # island expands to player
add(sfx_click(), 6.0)
add(sfx_blip((880.0,)), 6.05, 0.7)         # play
add(sfx_click(), 7.0, 0.6)                 # grab playhead
for b in (7.5, 8.0, 8.5):
    add(sfx_key(), b, 0.35)                # scrub ticks
add(sfx_snap(), 9.0)                       # release snap
add(sfx_pop(500, 200), 10.0)               # player -> volume slider
add(sfx_riser(0.9), 10.7, 0.8)             # over-drag stretch
add(sfx_snap(), 11.75)                     # over-drag release
add(sfx_pop(700, 260), 12.0)               # -> switch
add(sfx_blip((520.0,)), 13.0, 0.8)         # switch ON
add(sfx_blip((420.0,)), 14.0, 0.8)         # switch OFF
add(sfx_whoosh(True, 0.2), 15.0, 0.5)      # tab sweep 1
add(sfx_whoosh(True, 0.2), 16.0, 0.5)      # tab sweep 2
add(sfx_whoosh(True, 0.45), 17.0, 0.45)    # chart self-draw
add(sfx_pop(900, 400, 0.05), 18.25, 0.7)   # tooltip
add(sfx_click(), 19.0)                     # cmd-K click
add(sfx_pop(750, 300), 19.5)               # palette opens
for b in (20.0, 20.5, 21.0, 21.5, 21.75):
    add(sfx_key(), b)                      # s h a p e
add(sfx_whoosh(True, 0.18), 22.0, 0.6)     # enter
add(sfx_blip((587.33, 783.99)), 22.25, 0.8)  # notification lands
add(sfx_whoosh(False, 0.3), 24.0, 0.6)     # collapse back to button

# ---------------------------------------------------------------- master
mono = np.maximum(1e-9, np.abs(mixL) + np.abs(mixR))
mixL = np.tanh(mixL * 1.4)
mixR = np.tanh(mixR * 1.4)
peak = max(np.abs(mixL).max(), np.abs(mixR).max())
mixL, mixR = mixL / peak * 0.89, mixR / peak * 0.89

stereo = np.stack([mixL, mixR], axis=1)
pcm = (stereo * 32767).astype(np.int16)
with wave.open("audio.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())

# ------------------------------------------------- grid verification (numpy)
flux = np.zeros(N)
hop, win = 256, 1024
prev = None
for i in range(0, N - win, hop):
    seg = np.abs(np.fft.rfft(stereo[i : i + win, 0] * np.hanning(win)))
    if prev is not None:
        flux[i] = np.sum(np.maximum(0, seg - prev))
    prev = seg
flux_s = flux / (flux.max() + 1e-9)

expected = np.arange(N_BEATS) * BEAT
errs = []
for e_t in expected:
    lo, hi = int((e_t - 0.06) * SR), int((e_t + 0.06) * SR)
    seg = flux_s[lo:hi]
    if len(seg) == 0:
        continue
    pk = lo + int(np.argmax(seg))
    errs.append(abs(pk / SR - e_t))
errs = np.array(errs)
print(f"track: {DUR:.2f}s, {len(expected)} beats")
print(f"onset grid deviation: mean {errs.mean()*1000:.1f} ms, max {errs.max()*1000:.1f} ms")
print("GRID OK" if errs.max() < 0.02 else "GRID OFF — inspect!")
