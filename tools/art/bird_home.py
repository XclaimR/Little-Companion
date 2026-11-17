# A bird's home, packed into the objects atlas by kennel.py: a tall tree with four branches and a birdhouse on
# the trunk, a swing, a bell, and seed and water dishes. Heights are in pixels above the floor (h); a surface at
# height h has its top row at r = TH - h. Perch numbers are mirrored in Sources/PetCore/Bird.swift (enum Tree, × 1.5).
# Preview: python3 bird_home.py -> build/bird_home_preview.png (with Mango posed on each perch).
import json, math, os

TW, TH, CX = 64, 84, 32                     # tree: width, height, trunk centre column (dx 0)
BRANCHES = [(-1, 30, 44), (1, 23, 40), (-1, 30, 64), (1, 25, 66)]   # side, reach (px from the trunk centre), top height
HOUSE = dict(left=-9, right=9, bottom=46, top=62, roof=68)          # birdhouse on the trunk, about two-thirds up
ENTRANCE = (0, 54, 3.3)                                              # dx, h, radius: the round doorway (its shadow shows here)
PEG = 48                                                             # the little perch under the doorway
SWING = (-19, 41, 10)                                                # dx, top of the ropes (just under b0), seat top height
BELL = (20, 63, 59)                                                  # dx, string top (under b3), bell centre height

def blank(w, h): return [[None] * w for _ in range(h)]
def put(g, x, y, k):
    if 0 <= y < len(g) and 0 <= x < len(g[0]): g[y][x] = k
def ell(g, cx, cy, rx, ry, k, test=lambda x, y: True):
    for y in range(len(g)):
        for x in range(len(g[0])):
            if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1 and test(x, y): g[y][x] = k

def outline(g, skip=lambda x, y: False):
    H, W = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and not skip(x, y) and any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] not in (None, 'i')
                                                      for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'o'
    return out

def row(h): return TH - h          # top row of a surface at height h

def tree():
    g = blank(TW, TH)
    # trunk with a root flare
    for y in range(row(80), TH):
        flare = max(0, 4 - (TH - 1 - y)) if y > TH - 5 else 0
        for x in range(CX - 4 - flare, CX + 4 + flare): g[y][x] = 'b'
        g[y][CX - 4 - flare] = 'B'; g[y][CX + 3 + flare] = 'k'
        if y % 6 == 0: g[y][CX + 1] = 'k'
    # branches: three rows thick, level where it perches, tapering to a leafy tip
    for side, reach, h in BRANCHES:
        r = row(h)
        for d in range(4, reach + 1):
            x = CX + side * d - (1 if side < 0 else 0)
            thick = 3 if d < reach - 3 else 2
            for t in range(thick): g[r + t][x] = 'B' if t == 0 else 'b' if t == 1 else 'k'
        tip = CX + side * reach
        ell(g, tip + side * 2, r - 1, 3.2, 2.4, 'L')
        put(g, tip + side * 1, r - 2, 'l'); put(g, tip + side * 3, r, 'D')
    # crown: overlapping leaf clumps, lit from the top-left
    for (cx, cy, rx, ry) in ((32, 10, 21, 8), (13, 13, 8, 4.5), (51, 13, 8, 4.5), (32, 4, 14, 4.5), (22, 15, 9, 3.5), (42, 15, 9, 3.5)):
        ell(g, cx, cy, rx, ry, 'L')
    for y in range(TH):
        for x in range(TW):
            if g[y][x] == 'L':
                if y + 1 < TH and g[y + 1][x] is None or y > 15 or (x * 3 + y * 7) % 11 == 0 and y > 6: g[y][x] = 'D'   # shade under the clumps
                elif y == 0 or g[y - 1][x] is None or (x * 5 + y * 3) % 13 == 0 and y < 11: g[y][x] = 'l'           # lit tops, glints of leaves
    # birdhouse: a little wooden box with a red roof, round doorway and a peg
    L, R = CX + HOUSE['left'], CX + HOUSE['right']
    for y in range(row(HOUSE['top']), row(HOUSE['bottom']) + 1):
        for x in range(L, R): g[y][x] = 'W' if x == R - 1 or y == row(HOUSE['bottom']) else 'w' if (y - row(HOUSE['top'])) % 5 else 'W'
        g[y][L] = 'h'
    for i, y in enumerate(range(row(HOUSE['roof']), row(HOUSE['top']) + 1)):
        half = 2 + i * 2
        for x in range(CX - half, CX + half): g[y][x] = 'R' if (x + i) % 4 == 0 else 'r'
        g[y][CX - half] = 'T'
    dx, h, rad = ENTRANCE
    for y in range(TH):
        for x in range(TW):
            if math.hypot(x + .5 - (CX + dx), y + .5 - row(h) + .5) <= rad: g[y][x] = 'i'   # lit inside (the bird's shadow is drawn over it)
    for x in range(CX - 1, CX + 4): g[row(PEG)][x] = 'k'
    return outline(g)

def swing():
    dx, top, seat = SWING
    w, h = 15, top - seat + 2
    g = blank(w, h)
    for y in range(h - 2):
        g[y][1] = g[y][w - 2] = 'c'
    for x in range(w):
        g[h - 2][x] = 'w'; g[h - 1][x] = 'W'
    return outline(g)

def bell():
    g = blank(7, BELL[1] - BELL[2] + 4)
    top = len(g) - 7
    for y in range(top): g[y][3] = 'c'
    ell(g, 3.5, top + 3.5, 3, 3.2, 'y', lambda x, y: y >= top + 1)
    for x in range(7): g[top + 5][x] = 'Y' if 0 < x < 6 else None
    g[top + 2][2] = 'l'; g[top + 6][3] = 'Y'
    return outline(g)

def dish(fill):
    g = blank(16, 6)
    for x in range(1, 15): g[1][x] = fill[0]; g[2][x] = fill[1]
    for y in range(1, 5):
        for x in range(y - 1 if y > 2 else 0, 16 - (y - 1 if y > 2 else 0)):
            if y >= 3 or x in (0, 15): g[y][x] = 'P' if y == 3 else 'p'
    for x in range(2, 14, 3): g[1][x] = fill[2]
    return outline(g)

KEYS = {
    'tree': dict(o='kennel-outline', b='tree-bark', B='tree-barkLight', k='tree-barkDark', L='plant-leaf', l='plant-leafLight', D='tree-leafDark',
                 w='kennel-wood', W='kennel-woodDark', h='kennel-woodLight', r='kennel-roof', R='kennel-roofDark', T='kennel-roofLight', i='kennel-plate'),
    'swing': dict(o='kennel-outline', c='rope-C', w='kennel-woodLight', W='kennel-woodDark'),
    'bell': dict(o='tree-bellOutline', c='rope-C', y='biscuit-tag', Y='pepper-collardark', l='tree-bellShine'),
    'seedDish': dict(o='foodBowl-o', s='tree-seed', S='tree-seedDark', h='tree-seedHusk', p='foodBowl-B', P='foodBowl-R'),
    'waterDish': dict(o='waterBowl-o', s='waterBowl-W', S='waterBowl-W', h='waterBowl-w', p='waterBowl-B', P='waterBowl-w'),
}
def grids():
    return {'tree': tree(), 'swing': swing(), 'bell': bell(), 'seedDish': dish('sSh'), 'waterDish': dish('sSh')}

if __name__ == '__main__':
    import bird_sheet
    here = __file__.rsplit('/', 1)[0] or '.'
    hexes = json.load(open(here + '/palette.json'))
    G = grids()
    S, W, H = 4, 220, 100
    floor = 96
    img = [[(231, 225, 214)] * (W * S) for _ in range(H * S)]
    def blit(gr, keys, left, bottom, rgb=None):
        for y, r in enumerate(gr):
            for x, k in enumerate(r):
                if k:
                    c = rgb(k) if rgb else tuple(int(hexes[keys[k]][i:i + 2], 16) for i in (1, 3, 5))
                    for sy in range(S):
                        for sx in range(S):
                            Y, X = (bottom - len(gr) + y) * S + sy, (left + x) * S + sx
                            if 0 <= Y < H * S and 0 <= X < W * S: img[Y][X] = c
    tx = 150
    blit(G['tree'], KEYS['tree'], tx - CX, floor)
    blit(G['swing'], KEYS['swing'], tx + SWING[0] - 7, floor - SWING[2] + 1)
    blit(G['bell'], KEYS['bell'], tx + BELL[0] - 3, floor - BELL[2] + 3)
    blit(G['seedDish'], KEYS['seedDish'], tx - 75 - 8, floor)
    blit(G['waterDish'], KEYS['waterDish'], tx - 51 - 8, floor)
    frames = dict(bird_sheet.FRAMES)
    for name, dx, h in (('idle', -20, 0), ('swing', SWING[0], SWING[2]), ('bellA', 12, 40), ('nap', -20, 64), ('lookBack', 15, 66), ('front', -100, 0)):
        blit(frames[name](), None, tx + dx - 16, floor - h + 1, rgb=bird_sheet.rgb)
    os.makedirs(here + '/build', exist_ok=True)
    bird_sheet.write_png(here + '/build/bird_home_preview.png', img, W * S, H * S, alpha=False)
    print({k: (len(v[0]), len(v)) for k, v in G.items()})
