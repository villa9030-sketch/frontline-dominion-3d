"""Analisi spettrale dei WAV generati da render_audio.gd (solo numpy).

    python docs/audio_review/analyze.py docs/audio_review/wav/before [docs/audio_review/wav/after]

Per ogni file: livello RMS, centroide spettrale (brillantezza), quota d'energia per banda, piattezza spettrale
(0 = tonale, 1 = rumore), "squareness" (energia delle armoniche dispari rispetto alle pari sui frame intonati:
>3 = onda quadra/triangolare da chiptune), quota di frame intonati con fondamentale > 300 Hz (melodie acute),
attacchi intonati al secondo (note brevi/arpeggi), terza maggiore vs minore nel cromagramma.
"""
import sys, os, wave
import numpy as np

BANDS = [(20, 120), (120, 500), (500, 2000), (2000, 5000), (5000, 16000)]


def load(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate(); n = w.getnframes(); ch = w.getnchannels()
        x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def frames(x, n, hop):
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    k = 1 + (len(x) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(k)[:, None]
    return x[idx]


def analyze(path):
    x, sr = load(path)
    dur = len(x) / sr
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    peak = np.max(np.abs(x)) + 1e-12
    N = 4096; hop = 1024
    F = frames(x, N, hop) * np.hanning(N)[None, :]
    S = np.abs(np.fft.rfft(F, axis=1)) ** 2
    f = np.fft.rfftfreq(N, 1.0 / sr)
    e = S.sum(axis=1) + 1e-18
    loud = e > np.percentile(e, 30) * 0.5 + 1e-15
    Sl = S[loud]; el = e[loud]
    cent = float(np.sum((Sl * f[None, :]).sum(axis=1)) / np.sum(el))
    tot = Sl.sum()
    mb = f >= 150
    cent_mid = float(np.sum(Sl[:, mb] * f[None, mb]) / (np.sum(Sl[:, mb]) + 1e-18))
    flat_mid = float(np.mean(np.exp(np.mean(np.log(Sl[:, (f > 200) & (f < 4000)] + 1e-18), axis=1)) / (np.mean(Sl[:, (f > 200) & (f < 4000)], axis=1) + 1e-18)))
    bands = [float(Sl[:, (f >= a) & (f < b)].sum() / tot) for a, b in BANDS]
    flat = float(np.mean(np.exp(np.mean(np.log(Sl[:, 1:] + 1e-18), axis=1)) / (np.mean(Sl[:, 1:], axis=1) + 1e-18)))
    # pitch per frame: picco dell'autocorrelazione (60-2000 Hz)
    pitched = 0; high = 0; odd_even = []; f0s = []
    lag_min = int(sr / 2000); lag_max = int(sr / 60)
    chroma = np.zeros(12)
    for i in np.nonzero(loud)[0]:
        sp = S[i]
        ac = np.fft.irfft(sp)
        ac = ac[: lag_max + 1] / (ac[0] + 1e-18)
        neg = np.nonzero(ac[lag_min:lag_max] < 0)[0]
        if len(neg) == 0:
            continue
        z = lag_min + int(neg[0])
        L = z + int(np.argmax(ac[z:lag_max]))
        if ac[L] > 0.6:
            pitched += 1
            f0 = sr / L
            f0s.append(f0)
            if f0 > 300:
                high += 1
            hs = []
            for h in range(1, 9):
                fh = f0 * h
                if fh > sr / 2 - 50:
                    break
                j = int(round(fh * N / sr))
                hs.append(sp[max(0, j - 2): j + 3].sum())
            if len(hs) >= 6:
                odd = hs[2] + hs[4] + (hs[6] if len(hs) > 6 else 0)
                even = hs[1] + hs[3] + hs[5] + 1e-18
                odd_even.append(odd / even)
        # cromagramma 80-2000 Hz
        m = (f > 80) & (f < 2000)
        pc = np.round(12 * np.log2(f[m] / 440.0)).astype(int) % 12
        np.add.at(chroma, pc, sp[m])
    nl = max(1, int(loud.sum()))
    # attacchi intonati: salti d'energia > 6 dB in frame intonati
    db = 10 * np.log10(e + 1e-18)
    onsets = int(np.sum(np.diff(db) > 6.0))
    # terza maggiore/minore rispetto alla classe di altezza dominante
    root = int(np.argmax(chroma)); c = chroma / (chroma.sum() + 1e-18)
    maj = c[(root + 4) % 12]; mnr = c[(root + 3) % 12]
    return {
        "dur": dur, "rms_db": 20 * np.log10(rms), "crest_db": 20 * np.log10(peak / rms), "centroid": cent, "cent_mid": cent_mid, "flat_mid": flat_mid,
        "bands": bands, "flat": flat, "pitched": pitched / nl, "high": high / nl,
        "square": float(np.median(odd_even)) if odd_even else 0.0, "onsets_s": onsets / dur,
        "maj_min": float(maj / (mnr + 1e-9)), "f0_med": float(np.median(f0s)) if f0s else 0.0,
    }


def main():
    dirs = sys.argv[1:] or ["docs/audio_review/wav/before"]
    hdr = "%-26s %5s %6s %5s %6s %6s %5s  %-29s %4s %4s %4s %5s %5s %5s %6s" % (
        "file", "dur", "rms", "crest", "centr", "c>150", "flatM", "band% <120/500/2k/5k/>5k", "flat", "pitc", "high", "squar", "ons/s", "M/m", "f0")
    for d in dirs:
        print("==", d)
        print(hdr)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".wav"):
                continue
            r = analyze(os.path.join(d, fn))
            b = "/".join("%2d" % round(100 * v) for v in r["bands"])
            print("%-26s %5.1f %6.1f %5.1f %6.0f %6.0f %5.2f  %-29s %4.2f %4.2f %4.2f %5.1f %5.2f %5.2f %6.0f" % (
                fn[:-4], r["dur"], r["rms_db"], r["crest_db"], r["centroid"], r["cent_mid"], r["flat_mid"], b, r["flat"], r["pitched"], r["high"],
                r["square"], r["onsets_s"], r["maj_min"], r["f0_med"]))


if __name__ == "__main__":
    main()
