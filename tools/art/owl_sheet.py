# The owls (designs; not in the app yet): a 32x32 owl rig on the bird art helpers. Upright, round-headed, the face turned
# toward you even when the body is side-on; ear tufts (where a species has them) show mood like a cockatiel's crest.
# python3 owl_sheet.py tools/art  -> tools/art/build/<owl>.png + <owl>_preview.png  (Moth, Pip, Hedwig, Bramble)
import math, os, sys
sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')
import bird_sheet as B
from bird_sheet import rot, inside_poly, near_seg, W, H, FOOT

OWLS = {
    # rx/ry body, R head: tall slim barn owl, squat flat-headed little owl, big round snowy owl
    'moth':    dict(kind='barn owl', heart=True, tufts=False, brows=False, eye=1.5, dark_eyes=True, spots='speck', legs=2, rx=5.8, ry=8.6, R=6.2),
    'pip':     dict(kind='little owl', heart=False, tufts=False, brows=True, eye=2.0, dark_eyes=False, spots='dots', legs=0, rx=6.4, ry=6.6, R=6.0, neck=1),
    'hedwig':  dict(kind='snowy owl', heart=False, tufts=False, brows=False, eye=2.0, dark_eyes=False, spots='bars', legs=0, rx=7.2, ry=8.2, R=6.6),
    'bramble': dict(kind='long-eared owl', heart=False, tufts=True, brows=False, eye=2.1, dark_eyes=False, spots='streak', legs=0, rx=6.4, ry=8.0, R=6.2),
}
TOK = dict(o='outline', g='body', G='bodyLight', s='bodyShade', w='wing', d='mark', W='belly', y='face', Y='faceLight', Z='rim',
           c='iris', e='pupil', h='shine', k='beak', K='beakShade', f='feet', z='mouse', p='tail')
O = OWLS['moth']
def use(name):
    global O
    O = OWLS[name]
    B.KEY.clear(); B.KEY.update({k: f'{name}-{t}' for k, t in TOK.items()})

def hsh(x, y): return ((x * 73856093) ^ (y * 19349663)) >> 3   # scattered marks, not a grid

def pattern(part):
    """Each owl's markings: barn owl fine grey speckles, little owl white dots, long-eared dark streaks."""
    sp = O['spots']
    if part == 'belly':
        if sp == 'speck': return lambda x, y: 'd' if hsh(x, y) % 11 == 0 else 'W'
        if sp == 'bars': return lambda x, y: 'd' if y % 4 == 0 and (x + y) % 6 in (0, 1) else 'W'
        if sp == 'dots': return lambda x, y: 'd' if hsh(x, y) % 8 == 0 else 'W'
        return lambda x, y: 'd' if (x + (y // 3) * 2) % 5 == 0 and y % 3 != 2 else 'W'   # short staggered streaks
    if sp == 'bars': return lambda x, y: 'd' if y % 3 == 0 and (x + (y // 3) * 2) % 5 in (0, 1) else 'w'   # snowy owl: short black bars
    if sp == 'speck': return lambda x, y: 'd' if hsh(x, y) % 9 == 0 else 'w'
    if sp == 'dots': return lambda x, y: 'W' if hsh(x, y) % 7 == 0 else 'w'
    return lambda x, y: 'd' if (x + 2 * y) % 5 == 0 else 'w'

WINGS = {   # body frame (x+ belly side, y+ toward the tail); broad and round-tipped
    'up':     [(1, -6), (1, 1), (-6, 4), (-14, 3), (-16, -1), (-13, -6)],
    'down':   [(0, -6), (-1, 1), (6, 7), (12, 7), (13, 2), (9, -3)],
    'half':   [(0, -5), (-1, 2), (-6, 7), (-8, 3), (-7, -2)],
    'flare':  [(1, -6), (0, 1), (-9, -4), (-13, -10), (-9, -12)],
    'mantle': [(0, -6), (-1, 2), (5, 10), (11, 11), (12, 4), (6, -4)],   # draped forward to the floor over its catch
    'mantleFar': [(0, -6), (-1, 2), (-7, 1), (-10, -4), (-6, -8)],
    'stretch': [(0, -5), (-2, 1), (-9, 12), (-6, 14), (-1, 9)],
    'glide':  [(1, -7), (0, 3), (-3, 12), (-7, 12), (-11, 4), (-12, -2), (-8, -7)],   # long, swept back past the tail
}

def owl(theta=0, cx=15.0, cy=None, fluff=0.0, thin=0.0, wing='fold', far=None, face=0.6, tilt=0, hdx=0, hdy=0, eyes='open',
        tufts='mid', beak='shut', throat=0.0, legs='perch', extra=()):
    th = math.radians(theta)
    rx, ry = O['rx'] + fluff - thin, O['ry'] + fluff + thin * .5
    if cy is None:
        cy = FOOT - 1 - O['legs'] - (ry - 1.2) * math.cos(th)
    to_g, to_l = rot(cx, cy, th)
    g = [[None] * W for _ in range(H)]; grp = [[None] * W for _ in range(H)]
    def paint(group, key, test):
        for y in range(H):
            for x in range(W):
                if test(x + .5, y + .5): g[y][x] = key(x, y) if callable(key) else key; grp[y][x] = group
    bt = lambda f: (lambda px, py: f(*to_l(px, py)))
    if (far or wing) in WINGS and (far or wing not in ('fold', 'stretch')):
        pts = [(x - 1.5, y + .5) for x, y in WINGS[far or wing]]
        farkey = lambda x, y, p=pattern('wing'): 's' if p(x, y) in ('w', 'W') else p(x, y)
        paint('fw', farkey, bt(lambda lx, ly: inside_poly(lx, ly, pts)))
    paint('tail', 'w', bt(lambda lx, ly: inside_poly(lx, ly, [(-2.5, 4), (1.5, 4), (1, ry + 2.5), (-2.5, ry + 2.5)])))
    # legs: short and feathered, dark talons
    for i, side in enumerate((-1.6, 1.8)):
        hx, hy = to_g(side, ry - 1.5)
        if legs == 'oneleg' and i == 0: continue
        if legs in ('perch', 'oneleg', 'walkA', 'walkB'):
            fx = round(hx - .5) + {'walkA': (2 if i else -1), 'walkB': (-1 if i else 2)}.get(legs, 0)
            for y in range(int(hy), FOOT): g[y][fx] = g[y][fx + 1] = 'G'; grp[y][fx] = grp[y][fx + 1] = 'leg'
            for x in (fx - 1, fx + 2): g[FOOT][x] = 'f'; grp[FOOT][x] = 'leg'
            g[FOOT][fx] = g[FOOT][fx + 1] = 'G'; grp[FOOT][fx] = grp[FOOT][fx + 1] = 'leg'
        elif legs in ('forward', 'dangle'):
            ex, ey = (5, 4) if legs == 'forward' else (0, 4)
            paint('leg', 'G', lambda px, py, hx=hx, hy=hy: near_seg(px, py, (hx, hy), (hx + ex, hy + ey), 1.1))
            paint('leg', 'f', lambda px, py, hx=hx, hy=hy: near_seg(px, py, (hx + ex - 1.5, hy + ey + .9), (hx + ex + 1.5, hy + ey + .9), .55))
    paint('body', pattern('body'), bt(lambda lx, ly: (lx / rx) ** 2 + (ly / ry) ** 2 <= 1))
    paint('belly', pattern('belly'), bt(lambda lx, ly: ((lx - 1.5) / (rx - 1.6)) ** 2 + ((ly - .8) / (ry - 1.2)) ** 2 <= 1 and lx > -.5))
    if wing == 'fold':
        paint('wing', pattern('wing'), bt(lambda lx, ly: ((lx + 2.6) / 4.2) ** 2 + ((ly - .5) / (ry - .6)) ** 2 <= 1))
        paint('wing', 'G', bt(lambda lx, ly: ((lx + 2.6) / 4.2) ** 2 + ((ly - .5) / (ry - .6)) ** 2 <= 1 and lx > -.2 + .1 * ly and lx < .8 + .1 * ly))   # its front edge
    if wing in WINGS:
        pts = WINGS[wing]
        paint('wing', pattern('wing'), bt(lambda lx, ly: inside_poly(lx, ly, pts)))
        # a light leading edge and darker, notched primaries so the wing reads apart from the body
        (sx, sy), tip = pts[0], max(pts, key=lambda p: math.hypot(p[0] - pts[0][0], p[1] - pts[0][1]))
        edge = 'Y' if O['heart'] else 'G'   # cream on the barn owl's gold, where grey looked like scratches
        paint('wing', edge, bt(lambda lx, ly: inside_poly(lx, ly, pts) and near_seg(lx, ly, (sx - .5, sy + .8), tip, .7)))
        far_tip = lambda lx, ly: inside_poly(lx, ly, pts) and math.hypot(lx - tip[0], ly - tip[1]) < 3.2
        paint('wing', lambda x, y: 's' if (x + y) % 3 else 'w', bt(far_tip))
    if wing == 'mid':
        paint('wing', pattern('wing'), bt(lambda lx, ly: ((lx + 3) / 9) ** 2 + ((ly + .5) / 8) ** 2 <= 1 and lx < 3))
        paint('wing', 'G', bt(lambda lx, ly: ((lx + 3) / 9) ** 2 + ((ly + .5) / 8) ** 2 <= 1 and lx < 3 and ly < -6))
    # head: level whatever the body does, face toward you (face: 1 three-quarter right, 0 straight on, -1 over its shoulder)
    nx, ny = to_g(.8, -ry + 1.8)
    R = O['R']
    hcx, hcy = nx + hdx, ny - R * .55 + hdy + O.get('neck', 0)   # a little owl has no neck to speak of
    _, hl = rot(hcx, hcy, math.radians(tilt))
    ht = lambda f: (lambda px, py: f(*hl(px, py)))
    lim = R - 2.5 - 2.7   # keep the near eye inside the head outline
    fx0 = max(-lim, min(lim, 1.9 * face)) if face > -.9 else -2.6
    if O['tufts']:
        tip = {'up': [(-4.2, -10.5), (2.6, -10.5)], 'mid': [(-6, -8.5), (1, -9.5)], 'flat': [(-7.5, -5.5), (-1, -7.8)]}[tufts]
        for base, t in zip([(-3 + fx0 * .3, -4), (1.6 + fx0 * .3, -4.4)], tip):
            paint('tuft', 'w', ht(lambda lx, ly, b=base, t=t: inside_poly(lx, ly, [(b[0] - 1.4, b[1] + 1), (b[0] + 1.3, b[1] + .6), t])))
    paint('head', 'g' if O['spots'] == 'bars' else pattern('body'), ht(lambda lx, ly: lx * lx + ly * ly <= R * R))   # a snowy owl's head is clean white
    if O['heart']:   # barn owl: a white heart, notched at the top, edged in tan
        heart = lambda lx, ly, s=1: (((lx - fx0) / (4.4 * s)) ** 2 + ((ly - .6) / (5 * s)) ** 2 <= 1) and not ((lx - fx0) ** 2 + (ly + 4.6) ** 2 < (1.6 * s) ** 2)
        paint('disc', 'Z', ht(lambda lx, ly: heart(lx, ly, 1.12) and lx * lx + ly * ly <= R * R + 2))
        paint('disc', 'y', ht(heart))
    else:
        paint('disc', 'Z', ht(lambda lx, ly: ((lx - fx0) / 5.2) ** 2 + ((ly - .4) / 4.9) ** 2 <= 1 and lx * lx + ly * ly <= R * R + 1))
        paint('disc', 'y', ht(lambda lx, ly: ((lx - fx0) / 4.5) ** 2 + ((ly - .4) / 4.3) ** 2 <= 1))
    if throat:   # hooting: the white throat puffs out
        puff = lambda lx, ly, s=1: ((lx - fx0) / (2.6 * s)) ** 2 + ((ly - 5.6) / ((1.2 + 1.4 * throat) * s)) ** 2 <= 1
        paint('throat', 'Z', ht(lambda lx, ly: puff(lx, ly, 1.25)))   # edged so it shows even on a white belly
        paint('throat', 'W', ht(puff))
    # eyes, beak (painted pixel by pixel in head space so they stay crisp)
    hg, _ = rot(hcx, hcy, math.radians(tilt))
    gap = max(2.5, 2.6 * (1 - .2 * abs(face)))   # never close enough for the two eyes to touch
    er = O['eye'] * (1.2 if eyes == 'wide' else 1)
    for side in (-1, 1):
        ex, ey = fx0 + side * gap, -.2
        if O['brows']: paint('brow', 'W', ht(lambda lx, ly, ex=ex: near_seg(lx, ly, (ex - 1.6, -2.4), (ex + 1.4, -2.6), .55)))
        if eyes in ('open', 'wide', 'half'):   # a hand-drawn 4x4 eye: iris ring, 2x2 pupil (a pinpoint when startled), one shine
            X, Y = (int(round(v)) for v in hg(ex - .5, ey - .5))
            if O['dark_eyes']:   # barn owl: soft black eyes with a glint
                eye = {'open': ['.dd.', 'dpdd', 'dddd', '.dd.'], 'wide': ['.dd.', 'dpdd', 'dddd', '.dd.'], 'half': ['.YY.', 'YYYY', 'dddd', '.dd.']}[eyes]
            else:
                eye = ['.cc.', 'cpdc', 'cddc', '.cc.'] if eyes != 'wide' else ['.cc.', 'chcc', 'ccdc', '.cc.']
                if eyes == 'half': eye = ['.YY.', 'YYYY', 'cddc', '.cc.']
                if face < -.5 and eyes == 'open': eye = ['.cc.', 'hdcc', 'ddcc', '.cc.']   # looking back over its shoulder
            for j, rowp in enumerate(eye):
                for i, k in enumerate(rowp):
                    xx, yy = X - 1 + i, Y - 1 + j
                    if k != '.' and 0 <= xx < W and 0 <= yy < H: g[yy][xx] = {'p': 'h', 'd': 'e'}.get(k, k); grp[yy][xx] = 'eye'
        else:   # closed: a soft dark crease
            paint('lid', 'e' if O['dark_eyes'] or O['spots'] == 'bars' else 's', ht(lambda lx, ly, ex=ex: near_seg(lx, ly, (ex - 1, ey - .1), (ex, ey + .6), .45) or near_seg(lx, ly, (ex, ey + .6), (ex + 1, ey - .1), .45)))
    # a stamped beak (a drawn triangle collapses into a thin streak when the head tilts): two wide, hooking to a tip
    X, Y = (int(round(v)) for v in hg(fx0 - .5, 1.6))
    for j, rowp in enumerate(['kk', 'kK', '.K'] if beak == 'shut' else ['kk', '..', 'kK']):
        for i, k in enumerate(rowp):
            if k != '.' and 0 <= X + i < W and 0 <= Y + j < H: g[Y + j][X + i] = k; grp[Y + j][X + i] = 'beak'
    for (x, y, k) in extra:
        if 0 <= x < W and 0 <= y < H: g[y][x] = k; grp[y][x] = 'fx'
    return B.finish(g, grp)

def threat():
    """Startled: the threat display, facing you, wings fanned wide around it like a shield."""
    g = owl(theta=0, face=0, eyes='wide', tufts='up', fluff=1.2)
    wide = owl(theta=0, face=0, eyes='wide', tufts='up', fluff=1.2, wing='flare', far='flare')
    mirror = [[wide[y][2 * 15 - x] if 0 <= 2 * 15 - x < W else None for x in range(W)] for y in range(H)]   # both wings, a shield
    return [[g[y][x] if g[y][x] and g[y][x] != 'o' else wide[y][x] or mirror[y][x] or g[y][x] for x in range(W)] for y in range(H)]

MOUSE = [(23, 27, 'o'), (24, 27, 's'), (22, 28, 'o'), (23, 28, 'z'), (24, 28, 'z'), (25, 28, 'z'), (26, 28, 'o'), (21, 29, 'o'), (22, 29, 'z'), (23, 29, 'z'),
         (24, 29, 'z'), (25, 29, 'z'), (26, 29, 'o'), (19, 29, 'p'), (20, 29, 'p'), (22, 30, 'o'), (23, 30, 'o'), (24, 30, 'o'), (25, 30, 'o')]   # its catch: a little grey mouse
TAIL = [(21, 13, 'p'), (21, 14, 'p')]
FRAMES = [
    ('idle',       lambda: owl()),
    ('front',      lambda: owl(face=0)),
    ('blink',      lambda: owl(eyes='shut')),
    ('slowBlink',  lambda: owl(eyes='half')),
    ('swivelBack', lambda: owl(face=-1, hdx=-1.5)),             # head turned right round, looking over its back
    ('tiltL',      lambda: owl(face=0, tilt=-24)),             # the curious owl head-tilt toward the cursor
    ('tiltR',      lambda: owl(face=0, tilt=24)),
    ('alert',      lambda: owl(face=.2, thin=1.4, tufts='up', eyes='wide')),     # tall and thin: something's out there
    ('fluffed',    lambda: owl(fluff=1.3, tufts='flat', eyes='half')),
    ('hootA',      lambda: owl(theta=12, hdy=1, face=.8, beak='open', throat=.5, tufts='mid')),
    ('hootB',      lambda: owl(theta=18, hdy=2, face=.9, beak='open', throat=1.0, tufts='up')),
    ('walkA',      lambda: owl(theta=6, legs='walkA')),
    ('walkB',      lambda: owl(theta=-4, legs='walkB')),
    ('pounce',     lambda: owl(theta=30, cy=16, wing='up', far='up', legs='forward', eyes='wide', face=.9, tufts='flat')),
    ('mantle',     lambda: owl(theta=40, wing='mantle', far='mantleFar', face=.7, hdy=2.5, tufts='flat', extra=MOUSE)),
    ('takeoff',    lambda: owl(theta=35, wing='half', face=.8, tufts='flat')),
    ('flapUp',     lambda: owl(theta=72, cx=15, cy=17, wing='up', legs='tuck', face=.9, tufts='flat')),
    ('flapMid',    lambda: owl(theta=74, cx=15, cy=16, wing='mid', legs='tuck', face=.9, tufts='flat')),
    ('flapDown',   lambda: owl(theta=76, cx=15, cy=15, wing='down', legs='tuck', face=.9, tufts='flat')),
    ('glide',      lambda: owl(theta=84, cx=15, cy=16, wing='glide', far='glide', legs='tuck', face=.9, tufts='flat')),   # long silent glides
    ('flare',      lambda: owl(theta=-8, cx=15, cy=16, wing='flare', far='flare', legs='forward', face=.8, tufts='up')),
    ('preen',      lambda: owl(face=-.6, tilt=35, hdx=-1.5, hdy=2.5, eyes='half', tufts='flat')),
    ('stretch',    lambda: owl(wing='stretch', far='stretch', eyes='half', tufts='mid', legs='oneleg')),
    ('eatA',       lambda: owl(theta=35, hdy=4, hdx=2, face=.9, tilt=20, tufts='flat', extra=MOUSE)),
    ('eatB',       lambda: owl(theta=18, hdy=1, face=.8, tilt=-10, tufts='flat', extra=TAIL)),   # gulp: just the tail left
    ('dayDoze',    lambda: owl(fluff=1, eyes='shut', legs='oneleg', tufts='flat')),       # asleep in daylight, one foot tucked up
    ('sleep',      lambda: owl(fluff=1.3, eyes='shut', hdy=1.5, legs='oneleg', tufts='flat')),
    ('dream',      lambda: owl(fluff=1.3, eyes='half', hdy=1.5, legs='oneleg', tufts='mid')),
    ('startled',   threat),
    ('fallA',      lambda: owl(theta=150, cx=16, cy=16, tilt=40, wing='up', far='half', legs='dangle', eyes='wide', tufts='up')),
    ('fallB',      lambda: owl(theta=330, cx=16, cy=16, tilt=-30, wing='down', far='half', legs='dangle', eyes='wide', tufts='up')),
    ('recover',    lambda: owl(theta=40, cx=15, cy=17, wing='up', far='up', legs='dangle', eyes='wide', tufts='up')),
]
NAMES = [n for n, _ in FRAMES]

if __name__ == '__main__':
    out = (sys.argv[1] if len(sys.argv) > 1 else B.HERE) + '/build'
    os.makedirs(out, exist_ok=True)
    for name in OWLS:
        use(name)
        frames = [f() for _, f in FRAMES]
        B.write_png(f'{out}/{name}.png', B.sheet_px(frames), W * len(frames), H)
        B.use = use   # the shared preview swaps palettes by name: point it at the owls'
        B.preview(f'{out}/{name}_preview.png', [[(name, f) for f in frames[r:r + 11]] for r in range(0, len(frames), 11)])
    print(len(FRAMES), 'frames each:', ' '.join(NAMES))
