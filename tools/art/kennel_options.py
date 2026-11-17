# Kennel style options (side-on, doorway on the right), previewed next to Ollie for scale.
# Each option is a list of shapes; the preview shows the outside, and the same kennel with Ollie's shadow inside.
import json, struct, zlib, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')
import compose as hd2

HEX = json.load(open((__file__.rsplit('/', 1)[0] or '.') + '/palette.json'))
C = {k: tuple(int(HEX[t][i:i + 2], 16) for i in (1, 3, 5)) for k, t in dict(
    o='kennel-outline', r='kennel-roof', R='kennel-roofDark', L='kennel-roofLight', w='kennel-wood', W='kennel-woodDark',
    l='kennel-woodLight', p='kennel-plate', i='kennel-ink', a='kennel-woodLight', m='kennel-wood', b='bed-rim',
    c='rope-c', C='rope-C', g='plant-leaf', G='plant-outline', s='bone-S', S='bone-o', q='waterBowl-B', Q='waterBowl-S').items()}
SHADOW = (122, 86, 60)   # a soft shadow against the lamp-lit interior
GLOW = (247, 226, 178)   # warm lamp-lit interior
GLOW_FLOOR = (214, 170, 110)

def blank(w, h): return [[None] * w for _ in range(h)]
def ell(g, cx, cy, rx, ry, k):
    for y in range(len(g)):
        for x in range(len(g[0])):
            if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: g[y][x] = k
def rect(g, x0, y0, x1, y1, k):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= y < len(g) and 0 <= x < len(g[0]): g[y][x] = k
def outline(g, holes):
    H, W = len(g), len(g[0]); out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and (x, y) not in holes and any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'o'
    return out

def cabin():
    """A: plank cabin with a short roof overhang, square window, arched door at the right end."""
    w, h = 64, 44; g = blank(w, h)
    for y in range(4, 14):                                     # roof: 2 px overhang each side
        inset = max(0, 3 - (y - 4))
        rect(g, 2 + inset, y, w - 3 - inset, y, 'R' if (y - 4) % 4 == 3 else 'r')
    rect(g, 4, 5, w - 5, 5, 'L')
    rect(g, 4, 14, w - 5, h - 1, 'w')
    for y in range(14, h, 6): rect(g, 4, y, w - 5, y, 'W')
    rect(g, 4, 14, 5, h - 1, 'l'); rect(g, w - 6, 14, w - 5, h - 1, 'W')
    win = (10, 22, 29, 32); door = (44, 20, 53, h - 1)
    return g, win, door, 'arch'

def barrel():
    """B: a wooden barrel on its side, a round porthole window, the open end on the right."""
    w, h = 64, 44; g = blank(w, h)
    ell(g, 30, 23, 28, 20, 'w')
    for x in (14, 30, 46):                                    # hoops, only on the barrel itself
        for y in range(h):
            for xx in (x - 1, x):
                if g[y][xx]: g[y][xx] = 'W'
    for y in range(h):
        for x in range(w):
            if g[y][x] == 'w' and ((x + .5 - 30) / 28) ** 2 + ((y + .5 - 23) / 20) ** 2 > .8: g[y][x] = 'W'
    for y in range(h):                                        # flat floor
        for x in range(w):
            if y > h - 3 and g[y][x]: g[y][x] = 'W'
    rect(g, 8, h - 1, 52, h - 1, 'W')
    ell(g, 56, 25, 6, 16, 'W')                                 # rim of the open end
    win = ('round', 22, 20, 6); door = ('ellipse', 56, 25, 4.5, 14.5)
    return g, win, door, 'custom'

def dome():
    """C: a rounded hut with a thatch-like roof cap, little round window and a low arched door."""
    w, h = 62, 44; g = blank(w, h)
    ell(g, 31, 30, 29, 27, 'w')
    for y in range(h):
        for x in range(w):
            if y > 43: g[y][x] = None
    ell(g, 31, 15, 26, 12, 'r')
    for y in range(h):
        for x in range(w):
            if g[y][x] == 'r' and y > 19: g[y][x] = 'w'
            if g[y][x] == 'r' and (y + x // 3) % 4 == 0: g[y][x] = 'R'
    for y in range(26, h, 6): rect(g, 3, y, 59, y, None) if False else None
    win = ('round', 20, 31, 5); door = (40, 26, 51, h - 1)
    return g, win, door, 'arch'

def box():
    """D: a big cardboard box on its side — dogs love boxes. Flap open on the right, a cut-out window."""
    w, h = 62, 44; g = blank(w, h)
    rect(g, 3, 10, 52, h - 1, 'c')
    rect(g, 3, 10, 52, 12, 'C'); rect(g, 26, 10, 28, h - 1, 'C')          # tape and seam
    for y in range(13, h): g[y][3] = 'C'
    for i in range(10):                                                  # open flap tipped down to the right
        rect(g, 53 + i // 2, 10 + i, 54 + i // 2, 10 + i, 'C')
    win = (8, 20, 22, 30); door = (41, 18, 51, h - 1)
    return g, win, door, 'square'

def cut(g, win, door, style):
    holes = set()
    H, W = len(g), len(g[0])
    for y in range(H):
        for x in range(W):
            inw = False
            if win[0] == 'round': inw = ((x + .5 - win[1]) / win[3]) ** 2 + ((y + .5 - win[2]) / win[3]) ** 2 <= 1
            else: inw = win[0] <= x <= win[2] and win[1] <= y <= win[3]
            if door[0] == 'ellipse': ind = ((x + .5 - door[1]) / door[3]) ** 2 + ((y + .5 - door[2]) / door[4]) ** 2 <= 1
            else:
                ind = door[0] <= x <= door[2] and door[1] <= y <= door[3]
                if ind and style == 'arch' and y < door[1] + 4:
                    cx = (door[0] + door[2] + 1) / 2
                    ind = ((x + .5 - cx) / ((door[2] - door[0] + 1) / 2)) ** 2 + ((y + .5 - door[1] - 4) / 4) ** 2 <= 1
            if inw or ind: holes.add((x, y))
    front = [[None if (x, y) in holes else g[y][x] for x in range(W)] for y in range(H)]
    for (x, y) in holes:                                                 # window frames
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= x + dx < W and 0 <= y + dy < H and front[y + dy][x + dx] and (x + dx, y + dy) not in holes: front[y + dy][x + dx] = 'W'
    return outline(front, holes), holes

def render(options, path, S=6):
    ollie_stand = hd2.compose('pudding', 'sit')
    cols = []
    for name, (g, win, door, style) in options:
        front, holes = cut(g, win, door, style)
        cols.append((name, front, holes))
    cw, ch = 64 + 2 + 48, 46
    rows = []
    PW = (cw * 2 + 6) * S; PH = (ch + 4) * len(cols) * S
    img = [[(231, 225, 214)] * PW for _ in range(PH)]
    def px(x, y, c):
        for sy in range(S):
            for sx in range(S):
                if 0 <= y * S + sy < PH and 0 <= x * S + sx < PW: img[y * S + sy][x * S + sx] = c
    for ri, (name, front, holes) in enumerate(cols):
        oy = ri * (ch + 4) + 2
        H, W = len(front), len(front[0])
        for side in (0, 1):
            ox = side * (cw + 4) + 1
            for y in range(H):                                           # lit interior behind holes
                for x in range(W):
                    if (x, y) in holes: px(ox + x, oy + (ch - H) + y, GLOW if y < H - 3 else GLOW_FLOOR)
            if side == 1:                                                # Ollie's shadow sitting inside
                for y in range(36):
                    for x in range(48):
                        if ollie_stand[y][x]:
                            X, Y = x - 10 + 4, y - 36 + H
                            if (X, Y) in holes: px(ox + X, oy + (ch - H) + Y, SHADOW)
            for y in range(H):
                for x in range(W):
                    k = front[y][x]
                    if k: px(ox + x, oy + (ch - H) + y, C[k])
            if side == 0:                                                # Ollie standing beside it, for scale
                for y in range(36):
                    for x in range(48):
                        k = ollie_stand[y][x]
                        if k:
                            hx = hd2.HEX[hd2.PAL['pudding'][k]]
                            px(ox + W + 2 + x - 6, oy + ch - 36 + y + 2, tuple(int(hx[i:i + 2], 16) for i in (1, 3, 5)))
    raw = b''.join(b'\x00' + bytes(sum(r, ())) for r in img)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', PW, PH, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

if __name__ == '__main__':
    hd2.HEX.update(HEX)
    render([('A cabin', cabin()), ('B barrel', barrel()), ('C dome hut', dome()), ('D box', box())], sys.argv[1])
    print('ok')
