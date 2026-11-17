# Walk-in cabin kennel (64x44 px, side-on) as two layers, packed with the other objects into
# Resources/objects.png + objects.json.  Usage: python3 kennel.py <path-to-Resources>
# kennelBack: the dark interior seen through the doorway (drawn behind the dog).
# kennelFront: roof and walls with the doorway cut out (drawn in front of the dog while it's at the door).
import json, struct, sys, zlib

KW, KH = 66, 52
WINDOW = (10, 33, 31, 44)        # square window, low enough to show a lying dog's shadow
DOOR = (52, 14, 61, KH - 1)      # the whole right end is a full-height doorway: the dog walks straight in

def in_window(x, y): return WINDOW[0] <= x <= WINDOW[2] and WINDOW[1] <= y <= WINDOW[3] and x != 20 and y != 38   # cross bars

def in_door(x, y):
    if not (DOOR[0] <= x <= DOOR[2] and DOOR[1] <= y <= DOOR[3]): return False
    if y >= DOOR[1] + 4 or x >= DOOR[0] + 5: return True
    return ((x + .5 - (DOOR[0] + 5)) / 5) ** 2 + ((y + .5 - DOOR[1] - 4) / 4) ** 2 <= 1   # rounded inner corner

def kennel_front():
    """The cabin: plank walls taller than the dog, a short roof (2 px overhang), window and doorway cut out."""
    g = [[None] * KW for _ in range(KH)]
    for y in range(2, 12):
        inset = max(0, 3 - (y - 2))
        for x in range(2 + inset, KW - 2 - inset): g[y][x] = 'R' if (y - 2) % 4 == 3 else 'r'
    for x in range(4, KW - 4): g[3][x] = 'L'
    for y in range(12, KH):
        for x in range(4, KW - 4): g[y][x] = 'W' if (y - 12) % 6 == 0 else 'w'
        g[y][4] = g[y][5] = 'l'; g[y][KW - 6] = g[y][KW - 5] = 'W'
    for x in range(34, 44):                       # name plate
        for y in range(16, 19): g[y][x] = 'p'
    for x in (36, 39, 42): g[17][x] = 'i'
    holes = {(x, y) for y in range(KH) for x in range(KW) if in_window(x, y) or in_door(x, y)}
    for (x, y) in holes: g[y][x] = None
    for (x, y) in list(holes):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= x + dx < KW and 0 <= y + dy < KH and g[y + dy][x + dx] and (x + dx, y + dy) not in holes: g[y + dy][x + dx] = 'W'
    return outline(g, skip=lambda x, y: (x, y) in holes)

def kennel_back():
    """The lamp-lit interior behind the walls: what shows through the window and the doorway."""
    g = [[None] * KW for _ in range(KH)]
    for y in range(12, KH):
        for x in range(5, KW - 5): g[y][x] = 'f' if y >= KH - 3 else 'a'
    return g

def bed():
    """A roomy donut bed (54x18) that fits Ollie in any sleeping position."""
    w, h = 54, 18
    g = [[None] * w for _ in range(h)]
    def ell(cx, cy, rx, ry, k, only=False):
        for y in range(h):
            for x in range(w):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1 and (not only or g[y][x]): g[y][x] = k
    ell(27, 9.5, 26, 8, 'r')                       # rim
    ell(27, 8, 23, 4, 'L', True)                   # lit top of the rim
    ell(27, 10.5, 21, 5, 'c')                      # cushion
    ell(27, 9, 20, 2.6, 'C', True)                 # cushion shading toward the back
    ell(27, 11, 20, 4, 'c', True)
    for x in range(4, w - 4): g[15][x] = 'D'      # rim underside
    for x in range(8, w - 8): g[16][x] = 'D'
    return outline(g)

def outline(g, skip=lambda x, y: False):
    H, W = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and not skip(x, y) and any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'o'
    return out

KEYS = {
    'kennelFront': dict(o='kennel-outline', r='kennel-roof', R='kennel-roofDark', L='kennel-roofLight', w='kennel-wood', W='kennel-woodDark', l='kennel-woodLight', p='kennel-plate', i='kennel-ink'),
    'kennelBack': dict(a='kennel-plate', f='kennel-woodLight'),
    'bed': dict(o='bed-outline', r='bed-rim', L='bed-rimLight', D='bed-rimDark', c='bed-cushion', C='bed-cushionShade'),
}

if __name__ == '__main__':
    res = sys.argv[1]
    here = __file__.rsplit('/', 1)[0] or '.'
    hexes = json.load(open(here + '/palette.json'))
    items = json.load(open(here + '/objects_grids.json'))['items']
    grids = {'kennelBack': kennel_back(), 'kennelFront': kennel_front(), 'bed': bed()}
    for k in ('rug', 'window', 'plant', 'foodBowl', 'waterBowl', 'bone', 'ball', 'tennis', 'plush', 'rope', 'foodBowlHalf', 'foodBowlEmpty', 'waterBowlRipple'):
        it = items[k]
        grids[k] = [[None if ch == '.' else ch for ch in row.replace('|', '')] for row in it['rows']]
        KEYS[k] = {ch: tok for ch, tok in it['keys'].items() if ch != '.'}
    order = list(grids)
    H = max(len(g) for g in grids.values()); gap = 2
    rects, x = {}, 0
    for k in order:
        w, h = len(grids[k][0]), len(grids[k]); rects[k] = [x, H - h, w, h]; x += w + gap
    W = x - gap
    px = [[(0, 0, 0, 0)] * W for _ in range(H)]
    for k in order:
        x0, y0, _, _ = rects[k]
        for y, row in enumerate(grids[k]):
            for i, ch in enumerate(row):
                if ch: hx = hexes[KEYS[k][ch]]; px[y0 + y][x0 + i] = tuple(int(hx[j:j + 2], 16) for j in (1, 3, 5)) + (255,)
    raw = b''.join(b'\x00' + bytes(sum(r, ())) for r in px)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(res + '/objects.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    json.dump(rects, open(res + '/objects.json', 'w'))
    print(W, H, rects)
