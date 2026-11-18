# README pictures, drawn straight from the app's own sprite sheets (never from a screen recording,
# so nothing of anyone's desktop ends up in the repo).
#   python3 tools/art/readme_media.py      -> docs/hero.gif, docs/dog-<name>.gif, docs/moments.png
# Needs ffmpeg for the GIFs.
import os, struct, subprocess, tempfile, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = ROOT + '/Sources/LittleCompanion/Resources/'
DOCS = ROOT + '/docs/'
FW, FH = 48, 36
CREAM = (251, 247, 240, 255)

def load(path):
    """RGBA PNGs written by our own tools (8-bit RGBA, unfiltered or Sub/Up/Paeth rows)."""
    d = open(path, 'rb').read()
    w, h = struct.unpack('>II', d[16:24])
    i, idat = 8, b''
    while i < len(d):
        n = struct.unpack('>I', d[i:i + 4])[0]; t = d[i + 4:i + 8]
        if t == b'IDAT': idat += d[i + 8:i + 8 + n]
        i += 12 + n
    raw = zlib.decompress(idat); stride = w * 4; rows = []; prev = bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]; line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0; b = prev[x]; c = prev[x - 4] if x >= 4 else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    return w, h, rows

class Canvas:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.px = [[bg(x, y) if callable(bg) else bg for x in range(w)] for y in range(h)]
    def blit(self, img, sx, sy, sw, sh, dx, dy, flip=False, rows=None):
        _, _, src = img
        for y in range(sh):
            if rows and y not in rows: continue
            for x in range(sw):
                xx = sw - 1 - x if flip else x
                o = (sx + xx) * 4; r, g, b, a = src[sy + y][o:o + 4]
                if a < 128: continue
                X, Y = dx + x, dy + y
                if 0 <= X < self.w and 0 <= Y < self.h: self.px[Y][X] = (r, g, b, 255)
    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)): self.px[y][x] = c
    def save(self, path, scale):
        out = b''
        for row in self.px:
            line = b'\x00' + b''.join(bytes(c) * scale for c in row)
            out += line * scale
        def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', self.w * scale, self.h * scale, 8, 6, 0, 0, 0))
                               + chunk(b'IDAT', zlib.compress(out, 9)) + chunk(b'IEND', b''))

def dog(c, sheet, frame, x, y, flip=False):   # x = centre, y = floor line (the art has 2 empty rows under the paws)
    c.blit(sheet, frame * FW, 0, FW, FH, int(x - FW / 2), int(y - FH + 2), flip)

def gif(frames, path, fps):
    with tempfile.TemporaryDirectory() as tmp:
        for i, f in enumerate(frames): f.save(f'{tmp}/f{i:03d}.png', 1)
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(fps), '-i', f'{tmp}/f%03d.png',
                        '-vf', 'split[a][b];[a]palettegen=reserve_transparent=0[p];[b][p]paletteuse=dither=none', '-loop', '0', path], check=True)

def scaled(c, s):   # nearest-neighbour upscale into a new canvas
    n = Canvas(c.w * s, c.h * s, CREAM)
    n.px = [[c.px[y // s][x // s] for x in range(c.w * s)] for y in range(c.h * s)]
    return n

Z = ['111', '001', '010', '100', '111']   # a little pixel "z"

def hero(sheets, objs, atlas):
    W, H, FLOOR = 300, 84, 76
    def wall(x, y):   # soft desktop wallpaper, with the top of a Dock as the floor
        t = y / H
        return (int(244 - 30 * t), int(226 - 40 * t), int(236 - 10 * t), 255)
    def scene(t):
        c = Canvas(W, H, wall)
        c.rect(0, FLOOR, W, H, (60, 56, 70, 255)); c.rect(0, FLOOR, W, FLOOR + 1, (120, 112, 135, 255))   # Dock top edge
        def obj(name, x):
            sx, sy, sw, sh = atlas[name]; c.blit(objs, sx, sy, sw, sh, int(x - sw / 2), FLOOR - sh)
        obj('kennelBack', 40); obj('kennelFront', 40)
        bx = 112; obj('bed', bx)
        dog(c, sheets['biscuit'], 17, bx, FLOOR - 3)                                   # Biscuit curled up asleep in the bed
        sx, sy, sw, sh = atlas['bed']; c.blit(objs, sx, sy, sw, sh, int(bx - sw / 2), FLOOR - sh, rows=set(range(sh - 7, sh)))   # bed rim in front
        for i in range(3):   # z's drifting up
            p = (t * 0.5 + i / 3) % 1
            zx, zy = int(bx + 10 + 6 * p), int(FLOOR - 26 - 22 * p)
            if p < .85:
                for yy, r in enumerate(Z):
                    for xx, ch in enumerate(r):
                        if ch == '1': c.rect(zx + xx, zy + yy, zx + xx + 1, zy + yy + 1, (90, 80, 110, 255))
        obj('foodBowl', 160); obj('waterBowl', 178)
        o = sheets['ollie']   # Ollie's little routine: trot in, wag, a jump, sit and wag at you
        if t < 2.4: x = 196 + 26 * t; f = 1 if int(x / 6) % 2 == 0 else 2; y = 0
        elif t < 3.2: x = 258; f = 55 + int(t * 7) % 2; y = 0
        elif t < 3.35: x = 258; f = 71; y = 0
        elif t < 3.95:
            j = (t - 3.35) / .6; x = 258 + 14 * j; y = 4 * j * (1 - j) * 16; f = 72 if j < .5 else 73
        elif t < 4.1: x = 272; f = 71; y = 0
        else: x = 272; f = 59 + int(t * 7) % 2; y = 0
        c.blit(o, f * FW, 0, FW, FH, int(x - FW / 2), int(FLOOR - FH + 2 - y))
        return c
    fps, secs = 12, 6.5
    gif([scaled(scene(i / fps), 3) for i in range(int(fps * secs))], DOCS + 'hero.gif', fps)

def portraits(sheets):
    for name, s in sheets.items():   # each dog: walks a few steps, then sits facing you, wagging
        frames = []
        for i in range(24):
            c = Canvas(64, 40, CREAM)
            if i < 10: dog(c, s, 1 + (i // 2) % 2, 12 + i * 2, 38)
            else: dog(c, s, 59 + i % 2, 32, 38)
            frames.append(scaled(c, 3))
        gif(frames, DOCS + f'dog-{name}.gif', 6)

BW = 32   # birds are 32x32

def bird(c, sheet, frame, x, y):   # x = centre, y = feet line (1 empty row under the feet)
    c.blit(sheet, frame * BW, 0, BW, BW, int(x - BW / 2), int(y - BW + 1))

def bird_portraits(sheets):
    """Each bird: flies in flapping, flares, lands, then perches, bobs, puts its crest up and turns to face you."""
    flap = [14, 15, 16, 15]
    for name, s in sheets.items():
        frames = []
        for i in range(28):
            c = Canvas(64, 40, CREAM)
            if i < 9:   # flying in on a gentle arc
                u = i / 9; bird(c, s, flap[i % 4], 4 + 28 * u, 22 + 10 * u - 8 * (1 - (2 * u - 1) ** 2))
            elif i < 11: bird(c, s, 18, 34, 38)                   # landing flare
            elif i < 18: bird(c, s, 4 + (i % 2), 34, 38)          # head-bob
            elif i < 22: bird(c, s, 1, 34, 38)                    # crest up
            else: bird(c, s, 2, 34, 38)                           # facing you
            frames.append(scaled(c, 3))
        gif(frames, DOCS + f'bird-{name}.gif', 6)

NIGHT = (35, 39, 69, 255)

def owl_portraits(sheets):
    """Each owl, on a night background: glides in, flares, lands, swivels its head right round, tilts, blinks, hoots, faces you."""
    flap = [16, 17, 18, 19, 19]
    for name, s in sheets.items():
        frames = []
        for i in range(30):
            c = Canvas(64, 40, NIGHT)
            for (x, y) in ((8, 6), (50, 4), (58, 14), (20, 3)): c.rect(x, y, x + 1, y + 1, (200, 200, 230, 255))   # a few stars
            if i < 9:
                u = i / 9; bird(c, s, flap[i % 5], 4 + 28 * u, 22 + 10 * u - 6 * (1 - (2 * u - 1) ** 2))
            elif i < 11: bird(c, s, 20, 34, 38)                   # landing flare
            elif i < 14: bird(c, s, 0, 34, 38)                    # perched
            elif i < 18: bird(c, s, 4, 34, 38)                    # head swivelled right round
            elif i < 20: bird(c, s, 5, 34, 38)                    # a curious tilt
            elif i < 21: bird(c, s, 2, 34, 38)                    # blink
            elif i < 25: bird(c, s, 9 + (i % 2), 34, 38)          # hoot
            else: bird(c, s, 1, 34, 38)                           # facing you
            frames.append(scaled(c, 3))
        gif(frames, DOCS + f'owl-{name}.gif', 6)

def moments(sheet):
    picks = [19, 23, 44, 11, 79, 72, 76, 15]   # belly-up nap, ball carry, plush shake, sit facing you, ear scratch, jump, tumble, sit facing away
    c = Canvas(len(picks) * 52 + 4, 40, CREAM)
    for i, f in enumerate(picks): dog(c, sheet, f, 28 + i * 52, 38)
    c.save(DOCS + 'moments.png', 3)

def icon(outdir):
    """App icon: Ollie sitting facing you on a soft rounded tile, nearest-neighbour so it stays crisp."""
    sheet = load(RES + 'ollie.png')
    art = Canvas(48, 48, (0, 0, 0, 0))
    art.blit(sheet, 11 * FW, 0, FW, FH, 0, 8)
    for base in (16, 32, 128, 256, 512):
        for mult in (1, 2):
            n = base * mult
            c = Canvas(n, n, (0, 0, 0, 0))
            r, pad = n * .22, n * .08
            for y in range(n):
                for x in range(n):
                    dx = max(pad + r - x - .5, 0, x + .5 - (n - pad - r)); dy = max(pad + r - y - .5, 0, y + .5 - (n - pad - r))
                    if dx * dx + dy * dy <= r * r and pad <= x < n - pad and pad <= y < n - pad:
                        t = y / n; c.px[y][x] = (int(250 - 18 * t), int(232 - 30 * t), int(214 - 12 * t), 255)
            inner = n - 2 * pad
            for y in range(int(pad), int(n - pad)):
                for x in range(int(pad), int(n - pad)):
                    sx, sy = int((x - pad) / inner * 48), int((y - pad) / inner * 48)
                    if 0 <= sx < 48 and 0 <= sy < 48 and art.px[sy][sx][3]: c.px[y][x] = art.px[sy][sx]
            c.save(f"{outdir}/icon_{base}x{base}{'@2x' if mult == 2 else ''}.png", 1)

if __name__ == '__main__':
    import json, sys
    if len(sys.argv) > 2 and sys.argv[1] == '--icon': icon(sys.argv[2]); sys.exit()
    os.makedirs(DOCS, exist_ok=True)
    sheets = {n: load(RES + n + '.png') for n in ('ollie', 'biscuit', 'mochi', 'bean', 'pepper')}
    objs = load(RES + 'objects.png'); atlas = json.load(open(RES + 'objects.json'))
    moments(sheets['ollie']); portraits(sheets); hero(sheets, objs, atlas)
    bird_portraits({n: load(RES + n + '.png') for n in ('mango', 'pearl', 'kiwi', 'sunny')})
    owl_portraits({n: load(RES + n + '.png') for n in ('moth', 'pip', 'hedwig', 'bramble')})
    print(sorted(os.listdir(DOCS)))
