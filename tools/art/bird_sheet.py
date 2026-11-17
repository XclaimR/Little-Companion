# Mango the cockatiel: a 32x32 side-view bird, facing right, feet on row 30.
# python3 bird_sheet.py tools/art  -> tools/art/build/mango.png (+ mango_preview.png); copy mango.png to Sources/LittleCompanion/Resources/.
# The body is built in its own frame (y toward the tail) and rotated by `theta`, so perching, flying, pecking and
# tumbling all come from the same shapes. Light from the top-left, dark outline, same palette rules as the dogs.
import json, math, os, struct, sys, zlib

W = H = 32
FOOT = 30
HERE = __file__.rsplit('/', 1)[0] or '.'
HEX = json.load(open(HERE + '/palette.json'))
KEY = dict(o='mango-outline', g='mango-grey', G='mango-greyLight', s='mango-greyShade', w='mango-wing', W='mango-wingBar', d='mango-dark',
           y='mango-yellow', Y='mango-yellowLight', Z='mango-yellowShade', c='mango-cheek', k='mango-beak', K='mango-beakShade',
           e='mango-eye', h='mango-shine', f='mango-feet', b='waterBowl-W', B='waterBowl-w')
LIGHT = dict(g='G', y='Y', w='g', d='w')
SHADE = dict(g='s', y='Z', w='d', G='g')

def rot(cx, cy, th):
    c, s = math.cos(th), math.sin(th)
    to_g = lambda lx, ly: (cx + lx * c - ly * s, cy + lx * s + ly * c)
    to_l = lambda gx, gy: ((gx - cx) * c + (gy - cy) * s, -(gx - cx) * s + (gy - cy) * c)
    return to_g, to_l

def inside_poly(px, py, pts):
    inside, j = False, len(pts) - 1
    for i in range(len(pts)):
        (xi, yi), (xj, yj) = pts[i], pts[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi: inside = not inside
        j = i
    return inside

def near_seg(px, py, a, b, r):
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / max(1e-9, dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy) <= r

WINGS = {   # body frame: x+ is the belly side, x- the back; y+ toward the tail. Shoulder about (0, -4).
    'up':     [(1, -6), (1, 0), (-13, 0), (-14, -6)],
    'down':   [(0, -6), (-1, 0), (11, 3), (12, -3)],
    'half':   [(0, -5), (-1, 1), (-7, 6), (-7, -1)],
    'flare':  [(1, -6), (0, 0), (-11, -6), (-12, -12)],
    'spread': [(1, -6), (0, 1), (-10, 3), (-11, -4)],
    'stretch': [(0, -4), (-2, 0), (-4, 14), (-1, 13)],
}

def bird(theta=12, cx=14.0, cy=None, fluff=0.0, wing='fold', far=None, head=None, crest='mid', eyes='open',
         legs='perch', tail=0.0, extra=()):
    head = dict(dict(dx=0, dy=0, rot=0, back=False, tuck=False), **(head or {}))
    th = math.radians(theta)
    if cy is None:   # stand on the perch: the hips sit 3 rows above the feet (fewer when crouched)
        _, s_ = math.cos(th), math.sin(th)
        hip_ly = 6.2 + fluff
        cy = (FOOT - (2 if legs == 'bent' else 3.5)) - (0.8 * s_ + hip_ly * math.cos(th))
    to_g, to_l = rot(cx, cy, th)
    g = [[None] * W for _ in range(H)]
    grp = [[None] * W for _ in range(H)]
    def paint(group, key, test):
        for y in range(H):
            for x in range(W):
                if test(x + .5, y + .5): g[y][x] = key(x, y) if callable(key) else key; grp[y][x] = group
    def body_test(f):
        return lambda px, py: f(*to_l(px, py))
    rx, ry = 5 + fluff, 7.5 + fluff

    # far wing (behind everything), tail
    if (far or wing) in WINGS and wing != 'fold' and wing != 'stretch':
        pts = [(x - 1.5, y + 0.5) for x, y in WINGS[far or wing]]
        paint('fw', 'd', body_test(lambda lx, ly: inside_poly(lx, ly, pts)))
    tt = math.radians(tail)
    tpts = [(-1.8, 4), (1.8, 4), (1.3 + 15 * math.sin(tt), 15 * math.cos(tt)), (-1.3 + 15 * math.sin(tt), 15 * math.cos(tt))]
    paint('tail', lambda x, y: 'd' if (x + y) % 3 == 0 else 'w', body_test(lambda lx, ly: inside_poly(lx, ly, tpts)))
    # legs (in screen space: straight down to the perch, or tucked/dangling in the air)
    for side in (-0.8, 1.2):
        hx, hy = to_g(side, 6.0 + fluff)
        if legs in ('perch', 'bent'):
            fx = round(hx - .5)
            for y in range(int(hy), FOOT): g[y][fx] = 'f'; grp[y][fx] = 'leg'
            for x in (fx - 1, fx, fx + 1): g[FOOT][x] = 'f'; grp[FOOT][x] = 'leg'
        elif legs in ('dangle', 'forward', 'back'):
            ex, ey = {'dangle': (0, 4), 'forward': (3.5, 3), 'back': (-4.5, 2.5)}[legs]
            paint('leg', 'f', lambda px, py, hx=hx, hy=hy: near_seg(px, py, (hx, hy), (hx + ex, hy + ey), 0.6))
            paint('leg', 'f', lambda px, py, hx=hx, hy=hy: near_seg(px, py, (hx + ex - 1, hy + ey), (hx + ex + 1, hy + ey), 0.55))
    # body, folded wing
    paint('body', 'g', body_test(lambda lx, ly: (lx / rx) ** 2 + (ly / ry) ** 2 <= 1))
    if wing in ('fold', 'stretch'):
        paint('wing', 'w', body_test(lambda lx, ly: ((lx + 1.8) / 3.6) ** 2 + ((ly - .5) / (6.5 + fluff)) ** 2 <= 1 or inside_poly(lx, ly, [(-4.4, 2), (-0.6, 2), (-1.4, 10), (-3.4, 9.5)])))
        paint('wing', 'W', body_test(lambda lx, ly: ((lx + 1.6) / 2.4) ** 2 + ((ly + 2.6) / 1.5) ** 2 <= 1))
    if wing in WINGS:
        pts = WINGS[wing]
        paint('wing', 'w', body_test(lambda lx, ly: inside_poly(lx, ly, pts)))
        sx, sy = pts[0]; tx, ty = (pts[2][0] + pts[3][0]) / 2, (pts[2][1] + pts[3][1]) / 2
        paint('wing', 'W', body_test(lambda lx, ly: inside_poly(lx, ly, pts) and near_seg(lx, ly, (sx, sy + 2), (sx + (tx - sx) * .45, sy + 2 + (ty - sy) * .45), 1.2)))
    if wing == 'mid':   # level: the near wing spread toward you, seen from the side as a broad fan over the body
        paint('wing', 'w', body_test(lambda lx, ly: ((lx + .5) / 5.5) ** 2 + ((ly + .5) / 7) ** 2 <= 1 and lx < 3))
        paint('wing', 'W', body_test(lambda lx, ly: ((lx + .5) / 3.8) ** 2 + ((ly + 3) / 1.6) ** 2 <= 1))

    # head: its own frame at the neck, x toward the beak
    nx, ny = to_g(1.6, -8.0 - fluff * .6)
    hcx, hcy = nx + head['dx'], ny + head['dy']
    hth = math.radians(head['rot'])
    m = -1 if head['back'] else 1
    hg, hl = rot(hcx, hcy, hth * m)
    def ht(f): return lambda px, py: f(hl(px, py)[0] * m, hl(px, py)[1])
    R = 4.3
    if not head['tuck']:
        CREST = {'up':   [[(-0.5, -3.5), (-1.6, -7), (-2.6, -9.5)], [(0.6, -3.8), (0, -7.5), (-0.6, -10.5)], [(1.6, -3.4), (1.6, -6.5), (1.2, -8.5)]],
                 'mid':  [[(-0.5, -3.5), (-3.5, -6.5), (-6, -8)], [(0.6, -3.8), (-2, -7.5), (-3.8, -9.3)], [(1.6, -3.4), (0, -6.6), (-1.2, -8)]],
                 'flat': [[(-0.5, -3.6), (-3.5, -4.6), (-6.5, -4.8)], [(0.8, -4), (-2.5, -5.6), (-5.6, -6.2)], [(1.8, -3.6), (-1, -5.3), (-3.5, -6)]]}[crest]
        for a, b, c in CREST:
            tip = (b[0] + (c[0] - b[0]) * .45, b[1] + (c[1] - b[1]) * .45)
            paint('crest', 'y', ht(lambda lx, ly, a=a, b=b, tip=tip: near_seg(lx, ly, a, b, .62) or near_seg(lx, ly, b, tip, .6)))
            paint('crest', 's', ht(lambda lx, ly, tip=tip, c=c: near_seg(lx, ly, tip, c, .55)))
    nape = lambda lx, ly: lx < -1.4 + .35 * ly
    paint('head', 'g', ht(lambda lx, ly: lx * lx + ly * ly <= R * R and nape(lx, ly)))
    paint('head', 'y', ht(lambda lx, ly: lx * lx + ly * ly <= R * R and not nape(lx, ly)))
    if head['tuck']:   # beak buried in its back feathers: a round grey head, a yellow crown and one cheek showing
        paint('head', 'g', ht(lambda lx, ly: lx * lx + ly * ly <= R * R))
        paint('head', 'y', ht(lambda lx, ly: lx * lx + ly * ly <= R * R and ly < -1.8 and lx > -2.5))
        paint('cheek', 'c', ht(lambda lx, ly: ((lx + .2) / 1.5) ** 2 + ((ly - .6) / 1.3) ** 2 <= 1))
    else:
        paint('cheek', 'c', ht(lambda lx, ly: ((lx - 1.0) / 1.7) ** 2 + ((ly - 1.8) / 1.5) ** 2 <= 1))
        paint('beak', 'k', ht(lambda lx, ly: inside_poly(lx, ly, [(3.6, -1.2), (6.2, 0), (5.3, 2.5), (3.5, 1.8)])))
        paint('beak', 'K', ht(lambda lx, ly: inside_poly(lx, ly, [(4.8, 1.2), (6.2, 0), (5.3, 2.5), (4.4, 2.2)])))
        X, Y = (int(v) for v in hg(1.5 * m, -1.3))
        if eyes in ('open', 'wide'): g[Y][X] = 'e'
        if eyes == 'wide': g[Y - 1][X] = 'e'; g[Y - 1][X - m] = 'h'
        if eyes == 'half': g[Y][X] = 'e'; g[Y - 1][X] = 's'
        if eyes == 'shut': g[Y][X] = 's'; g[Y][X - m] = 's'
    for (x, y, k) in extra:
        if 0 <= x < W and 0 <= y < H: g[y][x] = k; grp[y][x] = 'fx'
    return finish(g, grp)

def finish(g, grp):
    out = [r[:] for r in g]
    for y in range(H):   # light from the top-left, shade underneath
        for x in range(W):
            k = g[y][x]
            if not k or grp[y][x] in ('leg', 'fx'): continue
            up = g[y - 1][x] if y else None
            left = g[y][x - 1] if x else None
            down = g[y + 1][x] if y < H - 1 else None
            if (up is None or (left is None and up is None)) and k in LIGHT: out[y][x] = LIGHT[k]
            elif down is None and k in SHADE: out[y][x] = SHADE[k]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] and grp[y + dy][x + dx] != 'fx'
                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'o'
    return out

def front(crest='up', eyes='open'):
    """Facing you: round body, wings at its sides, both orange cheeks."""
    g = [[None] * W for _ in range(H)]
    grp = [[None] * W for _ in range(H)]
    def paint(group, k, test):
        for y in range(H):
            for x in range(W):
                if test(x + .5, y + .5): g[y][x] = k; grp[y][x] = group
    for fx in (13, 18):
        for y in range(26, FOOT): g[y][fx] = 'f'; grp[y][fx] = 'leg'
        for x in (fx - 1, fx, fx + 1): g[FOOT][x] = 'f'; grp[FOOT][x] = 'leg'
    paint('tail', 'd', lambda px, py: abs(px - 16) < 1.6 and 24 < py < 31)
    paint('body', 'g', lambda px, py: ((px - 16) / 6) ** 2 + ((py - 20) / 7) ** 2 <= 1)
    for side in (-1, 1):
        paint('wing', 'w', lambda px, py, s=side: ((px - 16 - s * 5) / 2.2) ** 2 + ((py - 20.5) / 6) ** 2 <= 1)
        paint('wing', 'W', lambda px, py, s=side: ((px - 16 - s * 5.2) / 1.6) ** 2 + ((py - 17.5) / 1.4) ** 2 <= 1)
    if crest == 'up':
        for a, b in (((15.2, 8), (13.6, 1.5)), ((16.5, 8), (16.3, 0.8)), ((17.6, 8), (19, 2.5))):
            paint('crest', 'y', lambda px, py, a=a, b=b: near_seg(px, py, a, b, .6))
            paint('crest', 's', lambda px, py, a=a, b=b: near_seg(px, py, ((a[0] + 2 * b[0]) / 3, (a[1] + 2 * b[1]) / 3), b, .55))
    else:
        paint('crest', 'y', lambda px, py: near_seg(px, py, (16, 8), (15, 4.5), .7))
    paint('head', 'y', lambda px, py: (px - 16) ** 2 + (py - 10.5) ** 2 <= 4.6 ** 2)
    for cx in (13.2, 18.8): paint('cheek', 'c', lambda px, py, cx=cx: ((px - cx) / 1.5) ** 2 + ((py - 12) / 1.4) ** 2 <= 1)
    paint('beak', 'k', lambda px, py: abs(px - 16) < 1.2 and 11 < py < 13.6)
    g[13][15] = g[13][16] = 'K'
    for ex in (14, 17):
        g[10][ex] = 'e' if eyes == 'open' else 's'
        if eyes == 'open': g[9][ex] = 'h' if ex == 14 else g[9][ex]
    return finish(g, grp)

def drops(*pts): return [(x, y, 'b') for x, y in pts]

FRAMES = [
    ('idle',      lambda: bird()),
    ('idleCrest', lambda: bird(crest='up', eyes='wide')),
    ('front',     lambda: front()),
    ('lookBack',  lambda: bird(head=dict(back=True, dx=-1.5))),
    ('bobA',      lambda: bird(head=dict(dx=1, dy=1.5, rot=20))),
    ('bobB',      lambda: bird(head=dict(dx=.5, dy=-.5, rot=-8), crest='up')),
    ('lookUp',    lambda: bird(head=dict(rot=-35, dy=-.5), crest='up')),
    ('tilt',      lambda: bird(head=dict(rot=28, dx=.5), crest='up')),
    ('blink',     lambda: bird(eyes='shut')),
    ('hopA',      lambda: bird(theta=30, legs='bent', head=dict(dy=1))),
    ('hopB',      lambda: bird(theta=25, cy=19, legs='dangle', crest='up', wing='half')),
    ('peckA',     lambda: bird(theta=42, head=dict(rot=80, dx=3, dy=7), crest='flat')),
    ('peckB',     lambda: bird(theta=34, head=dict(rot=45, dx=2, dy=3.5), crest='flat')),
    ('takeoff',   lambda: bird(theta=42, legs='bent', wing='half', crest='up', head=dict(dy=1.5))),
    ('flapUp',    lambda: bird(theta=78, cx=15, cy=19, wing='up', legs='tuck', crest='mid', head=dict(rot=-60, dx=-1))),
    ('flapMid',   lambda: bird(theta=80, cx=15, cy=17, wing='mid', legs='tuck', crest='mid', head=dict(rot=-60, dx=-1))),
    ('flapDown',  lambda: bird(theta=82, cx=15, cy=15, wing='down', legs='tuck', crest='mid', head=dict(rot=-62, dx=-1))),
    ('glide',     lambda: bird(theta=96, cx=15, cy=16, wing='mid', legs='tuck', crest='flat', tail=-4, head=dict(rot=-82, dx=-1))),
    ('flare',     lambda: bird(theta=35, cx=15, cy=17, wing='flare', legs='forward', crest='up', head=dict(rot=-20))),
    ('wobble',    lambda: bird(theta=-14, wing='half', crest='up', eyes='wide', head=dict(dx=-.5, rot=-12))),
    ('preenA',    lambda: bird(head=dict(back=True, dx=-3, dy=4, rot=40), crest='flat', eyes='half')),
    ('preenB',    lambda: bird(head=dict(back=True, dx=-2, dy=6, rot=60), crest='flat', eyes='half', wing='half')),
    ('stretch',   lambda: bird(theta=18, wing='stretch', far='stretch', crest='mid', eyes='half', tail=-6)),
    ('eatA',      lambda: bird(theta=42, head=dict(rot=75, dx=3, dy=6), crest='flat')),
    ('eatB',      lambda: bird(theta=40, head=dict(rot=25, dx=1.5, dy=1.5), crest='flat', extra=[(26, 17, 'k')])),
    ('splashA',   lambda: bird(theta=45, wing='spread', crest='mid', head=dict(rot=40, dx=1, dy=3),
                               extra=drops((4, 21), (7, 17), (27, 19), (24, 15), (2, 26)))),
    ('splashB',   lambda: bird(theta=30, wing='up', crest='up', head=dict(rot=10),
                               extra=drops((3, 23), (6, 14), (28, 22), (26, 13), (9, 10), (22, 9)))),
    ('swing',     lambda: bird(theta=8, crest='mid', eyes='half', tail=6)),
    ('bellA',     lambda: bird(theta=18, crest='up', head=dict(rot=-25, dx=1.5, dy=-.5))),
    ('bellB',     lambda: bird(theta=26, crest='up', head=dict(rot=15, dx=2.5, dy=1))),
    ('nap',       lambda: bird(fluff=1.2, crest='flat', eyes='half', head=dict(dy=1.5))),
    ('sleep',     lambda: bird(fluff=1.4, crest='flat', head=dict(back=True, tuck=True, dx=-2.5, dy=3))),
    ('dream',     lambda: bird(fluff=1.4, crest='mid', head=dict(back=True, tuck=True, dx=-2.5, dy=2.5), tail=4)),
    ('startled',  lambda: bird(theta=2, wing='half', far='half', crest='up', eyes='wide', head=dict(dy=-1))),
    ('fallA',     lambda: bird(theta=150, cx=16, cy=16, wing='up', far='down', legs='dangle', crest='up', eyes='wide', head=dict(rot=40))),
    ('fallB',     lambda: bird(theta=220, cx=16, cy=16, wing='down', far='up', legs='dangle', crest='up', eyes='wide', head=dict(rot=-30))),
    ('recover',   lambda: bird(theta=50, cx=15, cy=17, wing='up', far='up', legs='dangle', crest='up', eyes='wide', head=dict(rot=-30))),
    ('frontBlink', lambda: front(crest='flat', eyes='shut')),
]
NAMES = [n for n, _ in FRAMES]

def rgb(k): hx = HEX[KEY[k]]; return tuple(int(hx[i:i + 2], 16) for i in (1, 3, 5))

def write_png(path, px, w, h, alpha=True):
    raw = b''.join(b'\x00' + bytes(sum(r, ())) for r in px)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6 if alpha else 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

if __name__ == '__main__':
    out = (sys.argv[1] if len(sys.argv) > 1 else HERE) + '/build'
    os.makedirs(out, exist_ok=True)
    frames = [f() for _, f in FRAMES]
    sheet = [[(0, 0, 0, 0)] * (W * len(frames)) for _ in range(H)]
    for i, f in enumerate(frames):
        for y in range(H):
            for x in range(W):
                if f[y][x]: sheet[y][i * W + x] = rgb(f[y][x]) + (255,)
    write_png(out + '/mango.png', sheet, W * len(frames), H)
    cols, S = 10, 5   # preview: labelled by position (see NAMES), on the dogs' cream backdrop
    rows = (len(frames) + cols - 1) // cols
    PW, PH = cols * (W + 2) * S, rows * (H + 2) * S
    img = [[(231, 225, 214)] * PW for _ in range(PH)]
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        for y in range(H):
            for x in range(W):
                if f[y][x]:
                    for sy in range(S):
                        for sx in range(S): img[(r * (H + 2) + y + 1) * S + sy][(c * (W + 2) + x + 1) * S + sx] = rgb(f[y][x])
    write_png(out + '/mango_preview.png', img, PW, PH, alpha=False)
    print(len(frames), 'frames:', ' '.join(f'{i}:{n}' for i, n in enumerate(NAMES)))
