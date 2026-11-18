# An owl's home and toys (designs; not in the app yet). The hollow oak was chosen for every owl: it sleeps by day in the
# knothole (its eyes glint in the dark) and perches on the bare branches at night. Toys: mouse (its hunting toy), pinecone,
# feather, lantern (glows dusk to dawn), log perch; it bathes in the birds' water dish.
# python3 owl_home.py tools/art  -> tools/art/build/owl_home_preview.png (the oak with the owls on it, and the toys)
import json, math, os, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')
import bird_sheet as B, owl_sheet as O
from bird_home import blank, put, ell, outline
C = {k[len('owlhome-'):]: v for k, v in B.HEX.items() if k.startswith('owlhome-')}   # colours in palette.json

def hollow_oak(glint=False):
    """A gnarled old oak: a wide trunk with a knothole the owl sleeps in (by day you see its eyes glint in the dark),
    bare crooked branches to perch on, a few leaves left."""
    TW, TH = 70, 84
    g = blank(TW, TH)
    for y in range(18, TH):
        wob = int(1.5 * math.sin(y / 5))
        flare = max(0, 5 - (TH - 1 - y)) if y > TH - 6 else 0
        for x in range(28 + wob - flare, 42 + wob + flare): g[y][x] = 'b'
        g[y][28 + wob - flare] = 'B'; g[y][29 + wob - flare] = 'B'; g[y][41 + wob + flare] = 'k'
        if y % 7 == 3: g[y][34 + wob] = 'k'; g[y][35 + wob] = 'k'
    for (x0, y0, x1, y1) in ((30, 30, 6, 22), (40, 44, 64, 38), (31, 58, 10, 54), (38, 22, 58, 12), (33, 20, 22, 6)):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for t in range(n + 1):
            x, y = round(x0 + (x1 - x0) * t / n), round(y0 + (y1 - y0) * t / n + 1.5 * math.sin(t / 3))
            for d in range(3 if t < n - 4 else 2): put(g, x, y + d, 'B' if d == 0 else 'b' if d == 1 else 'k')
    for (cx, cy, rx, ry) in ((8, 19, 4, 2.5), (60, 10, 5, 3), (22, 5, 4, 2.5), (63, 36, 3.5, 2)):
        ell(g, cx, cy, rx, ry, 'L', lambda x, y: g[y][x] is None)
    ell(g, 35, 48, 4.5, 6, 'a')                       # the knothole
    ell(g, 35, 48, 6, 7.5, 'B', lambda x, y: g[y][x] == 'b')
    if glint: put(g, 33, 47, 'y'); put(g, 37, 47, 'y')   # its eyes glinting inside (the app draws these only while it's home)
    return outline(g, skip=lambda x, y: False)

def mouse():
    g = blank(14, 8)
    ell(g, 6, 4.5, 4.5, 3, 'm'); ell(g, 10, 4, 2.6, 2.2, 'M'); put(g, 11, 2, 'p'); put(g, 9, 2, 'p')
    put(g, 12, 4, 'e'); put(g, 13, 5, 'p')
    for x in range(0, 3): put(g, x, 6 - x // 2, 'p')
    return outline(g)

def pinecone():
    g = blank(9, 11)
    ell(g, 4.5, 6, 3.6, 4.6, 'W')
    for y in range(2, 11):
        for x in range(9):
            if g[y][x] == 'W' and (x + y * 2) % 4 == 0: g[y][x] = 'h'
    put(g, 4, 0, 'g'); put(g, 4, 1, 'g')
    return outline(g)

def feather():
    g = blank(7, 14)
    for y in range(1, 13):
        w = 2 if 3 < y < 10 else 1
        for x in range(3 - w, 4 + w): g[y][x] = 's' if (y % 3) else 'S'
        g[y][3] = 'z'
    return outline(g)

def lantern(lit=True):
    g = blank(9, 14)
    for y in range(0, 3): g[y][4] = 'c'
    for x in range(1, 8): g[3][x] = 'm'; g[12][x] = 'm'
    for y in range(4, 12):
        for x in range(1, 8): g[y][x] = ('F' if lit else 'M') if 2 <= x <= 6 else 'm'
    if lit: g[7][4] = 'f'; g[8][4] = 'f'; g[7][3] = 'f'
    return outline(g)

def log_perch():
    g = blank(28, 8)
    for y in range(1, 7):
        for x in range(3, 26): g[y][x] = 'b' if y % 3 else 'k'
    ell(g, 3, 4, 2.5, 3, 'h'); ell(g, 3, 4, 1.2, 1.5, 'w')
    put(g, 14, 0, 'G'); put(g, 15, 0, 'g'); put(g, 20, 0, 'G')
    return outline(g)

def grids():
    """For the objects atlas (kennel.py): the oak, the toys and the lantern lit and unlit."""
    return {'oak': hollow_oak(), 'mouse': mouse(), 'pinecone': pinecone(), 'feather': feather(), 'log': log_perch(),
            'lantern': lantern(lit=False), 'lanternLit': lantern()}
KEYS = {name: {k: 'owlhome-' + k for k in C} for name in ('oak', 'mouse', 'pinecone', 'feather', 'log', 'lantern', 'lanternLit')}

if __name__ == '__main__':
    out = (sys.argv[1] if len(sys.argv) > 1 else B.HERE) + '/build'
    os.makedirs(out, exist_ok=True)
    S, Wd, Ht, floor = 4, 200, 100, 96
    img = [[(231, 225, 214)] * (Wd * S) for _ in range(Ht * S)]
    def blit(gr, left, bottom, col):
        for y, row in enumerate(gr):
            for x, k in enumerate(row):
                if k:
                    for sy in range(S):
                        for sx in range(S):
                            Y, X = (bottom - len(gr) + y) * S + sy, (left + x) * S + sx
                            if 0 <= Y < Ht * S and 0 <= X < Wd * S: img[Y][X] = col(k)
    hx = lambda k: tuple(int(C[k][i:i + 2], 16) for i in (1, 3, 5))
    oak = hollow_oak(glint=True); left = 20
    blit(oak, left, floor, hx)
    for name, frame, x, h in (('bramble', 'idle', left + 38, 84 - 38 + 1), ('pip', 'front', left + 13, 84 - 55 + 1),
                              ('moth', 'tiltL', left + 50, 0), ('hedwig', 'slowBlink', left + 82, 0)):
        O.use(name); blit(dict(O.FRAMES)[frame](), x - 16, floor - h + 1, B.rgb)
    x = 120
    for t in (mouse(), pinecone(), feather(), lantern(), log_perch()):
        blit(t, x, floor, hx); x += len(t[0]) + 4
    B.write_png(out + '/owl_home_preview.png', img, Wd * S, Ht * S, alpha=False)
    print('ok')
