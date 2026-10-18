import numpy as np, soundfile as sf, glob, os, sys
sr = 48000
out = '/Users/erikplacido/Documents/FOTEBA/jogo/assets/audio/sfx/'
os.makedirs(out, exist_ok=True)
def load(p): return np.frombuffer(open(p,'rb').read()[44:], dtype='<f4').reshape(-1, 2).astype(np.float64)
PEAK = {'ui_': .45, 'chute': .7, 'apito_': .8, 'gol': .95, 'revelar_lendario': .95, 'carta_brilho': .55,
        'pacote_': .7, 'substituicao': .7, 'escanteio': .7}
def peak_for(n):
    for k, v in PEAK.items():
        if n == k or (k.endswith('_') and n.startswith(k)): return v
    return .85
names = sys.argv[1:] or [os.path.basename(f)[4:-4] for f in sorted(glob.glob('sfx_*.wav'))]
for n in names:
    a = load('sfx_%s.wav' % n); m = np.abs(a).max(1)
    if m.max() < 1e-3: print('%-26s SILENCIO!' % n); continue
    o = int(np.argmax(m > 1e-4))
    if n == 'torcida_ambiente':
        x = a[o + 8 * sr : o + 16 * sr].copy()
        N = int(.15 * sr); w = np.linspace(0, np.pi / 2, N)[:, None]
        x[-N:] = x[-N:] * np.cos(w) + a[o + 8 * sr - N : o + 8 * sr] * np.sin(w)
        x *= 10 ** (-24 / 20) / np.sqrt((x ** 2).mean())
    else:
        x = a[max(0, o - 48):]                     # 1 ms antes do primeiro som
        env = np.convolve(np.abs(x).max(1), np.ones(480) / 480, 'same')
        end = len(x) - int(np.argmax(env[::-1] > 10 ** (-46 / 20) * np.abs(x).max()))
        x = x[: min(len(x), end + int(.05 * sr))].copy()
        f = min(int(.3 * sr), len(x) // 3); x[-f:] *= np.linspace(1, 0, f)[:, None]
        x *= peak_for(n) / np.abs(x).max()
    sf.write(out + n + '.ogg', x.astype(np.float32), sr, format='OGG', subtype='VORBIS', compression_level=.4)
    rms = 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)
    print('%-26s %5.2fs  pico %.2f  rms %5.1f dB' % (n, len(x) / sr, np.abs(x).max(), rms))
