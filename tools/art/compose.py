# Parametric 48x36 side-view dog composer: breed (ears, tail, markings, palette) x pose skeleton.
# Output: per dog per pose, rows of single-char keys; plus a PNG contact sheet for review.
import json, math, struct, sys, zlib

W, H, FLOOR = 48, 36, 33   # FLOOR = last paw row

BREEDS = {
  'biscuit': dict(L=13, ry=6, leg=8, head=(6.6, 5.6), muz=(4.2, 2.6), ear='pointy', tail='curl', marks='shiba', collar=True),
  'pudding': dict(L=12.5, ry=6.2, leg=8, head=(6.4, 5.8), muz=(4.6, 3.0), ear='floppy', tail='flag', marks='beagle', collar=True),
  'mochi':   dict(L=12, ry=7, leg=7, head=(7.0, 6.2), muz=(3.6, 2.4), ear='small', tail='plume', marks='mochi', collar=True, fluffy=True),
  'bean':    dict(L=16, ry=5, leg=4, head=(5.8, 5.0), muz=(5.0, 2.4), ear='long', tail='thin', marks='bean', collar=True),
  'pepper':  dict(L=13, ry=6, leg=8, head=(6.4, 5.6), muz=(4.4, 2.5), ear='folded', tail='brush', marks='collie', collar=True),
}

def compose(breed, pose):
    P = BREEDS[breed]
    g = [[None] * W for _ in range(H)]          # tone key
    sh = [[None] * W for _ in range(H)]         # shape id
    zones = {}
    def put(x, y, sid, key='b'):
        if 0 <= x < W and 0 <= y < H: g[y][x] = key; sh[y][x] = sid
    def ell(sid, cx, cy, rx, ry, key='b'):
        zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: put(x, y, sid, key)
    def poly(sid, pts, zone, key='b'):
        zones.setdefault(sid, zone)
        for y in range(H):
            for x in range(W):
                px, py, inside, j = x + .5, y + .5, False, len(pts) - 1
                for i in range(len(pts)):
                    (xi, yi), (xj, yj) = pts[i], pts[j]
                    if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi: inside = not inside
                    j = i
                if inside: put(x, y, sid, key)
    def leg(sid, x0, y0, y1, w=4, far=False, paw=1):
        zones[sid] = ('leg', x0, w, far)
        for y in range(int(y0), y1 + 1):
            for x in range(int(x0), int(x0) + w): put(x, y, sid)
        for y in range(y1 + 1, FLOOR + 1):        # paw, pointing forward
            for x in range(int(x0) - (1 if paw < 0 else 0), int(x0) + w + (1 if paw > 0 else 0)): put(x, y, sid)

    def sleg(sid, xtop, ytop, xbot, w=4, far=False, paw=1, ybot=FLOOR - 1):
        # a leg as a slanted strip from (xtop, ytop) to (xbot, ybot), with a paw on the row below
        zones[sid] = ('leg', xtop, w, far)
        y0, y1 = int(ytop), ybot
        for y in range(y0, y1 + 1):
            t = (y - y0) / max(1, y1 - y0)
            xs = xtop + (xbot - xtop) * t
            for x in range(int(round(xs)), int(round(xs)) + w): put(x, y, sid)
        xb = int(round(xbot))
        for x in range(xb - (1 if paw < 0 else 0), xb + w + (1 if paw > 0 else 0)): put(x, y1 + 1, sid)
    L, ry, legH = P['L'], P['ry'], P['leg']
    hrx, hry = P['head']; mrx, mry = P['muz']
    walk = {'walkA': 1, 'walkB': -1}.get(pose, 0)
    marks = P['marks']
    A = {}   # anchors used by markings

    if pose in ('stand', 'walkA', 'walkB', 'pawUp', 'shakeA', 'shakeB', 'crouch'):
        cx = 22 - (L - 13) * 0.7
        cy = FLOOR - legH - ry + 1.5 + (3 if pose == 'crouch' else 0)   # crouch: gathering itself to spring / soaking up a landing
        if pose == 'walkB': cy -= 0.6
        top = cy + ry - 1.5
        bx, fx = cx - L + 1, cx + L - 5
        leg('farback', bx + 6 - 2 * walk, top + 1, FLOOR - 2 - (1 if walk == -1 else 0), w=3, far=True)
        leg('farfront', fx + 4 + 2 * walk, top, FLOOR - 2 - (1 if walk == 1 else 0), w=3, far=True)
        A['tail'] = (cx - L + 2.5, cy - ry * 0.75)
        draw_tail(P, A['tail'], ell, poly, 'stand')
        ell('body', cx, cy, L, ry)
        ell('haunch', cx - L + 4.5, cy + 2, 5, ry * 0.85)
        hx, hy = cx + L + 1, cy - ry - 3
        hy += {'pawUp': 3.5, 'shakeA': -2, 'shakeB': 2.5, 'crouch': 1}.get(pose, 0)   # head down at the ball / flicking a toy up / down
        hx += {'pawUp': .5, 'shakeB': .5}.get(pose, 0)
        chx = cx + L - 0.5
        poly('neck', [(hx - 7, hy + .5), (hx + 1, hy - 1.5), (chx + 4.5, cy + 1.5), (chx - 5.5, cy + .5)], (chx, cy - 3, 6, 7))
        ell('chest', chx, cy, 4.6, ry)
        leg('legBN', bx + 2 * walk, top, FLOOR - 2, paw=-1)
        if pose == 'pawUp':   # near front paw raised, reaching forward to bat at the ball
            zones['legFN'] = ('leg', fx, 4, False)
            for y in range(int(top - .5), FLOOR - 4):
                t = (y - top) / max(1, FLOOR - 4 - top)
                for x in range(int(fx + 4 * t), int(fx + 4 * t) + 4): put(x, y, 'legFN')
            for x in range(int(fx + 4), int(fx + 9)): put(x, FLOOR - 4, 'legFN'); put(x, FLOOR - 5, 'legFN')
        else:
            leg('legFN', fx - 2 * walk, top - .5, FLOOR - 2, paw=1)
        A.update(cx=cx, cy=cy, L=L, ry=ry, chx=chx, belly=(cx - L + 6, cx + L - 4, cy + ry - 1.6))
    elif pose in ('runJU', 'runJD'):   # airborne: JU takes off (hind legs thrust back, fronts folded), JD comes down (fronts reach for the floor, hinds tucked)
        up = pose == 'runJU'
        cx = 22 - (L - 13) * 0.7
        cy = FLOOR - legH - ry + 1.5
        top = cy + ry - 1.5
        bx, fx = cx - L + 3, cx + L - 6
        hind, front = ((-7, FLOOR - 1), (3, FLOOR - 5)) if up else ((3, FLOOR - 5), (6, FLOOR - 1))
        sleg('farback', bx + 3, top + 1, bx + 3 + hind[0] + 1, w=3, far=True, ybot=hind[1] - 1)
        sleg('farfront', fx + 3, top, fx + 3 + front[0] - 1, w=3, far=True, ybot=front[1] - 1)
        A['tail'] = (cx - L + 2.5, cy - ry * 0.75)
        draw_tail(P, A['tail'], ell, poly, 'run')
        ell('body', cx, cy, L + .5, ry - .3)
        ell('haunch', cx - L + 4.5, cy + 1.5, 5, ry * 0.85)
        hx, hy = cx + L + 1.5, cy - ry - (2.5 if up else 1)
        chx = cx + L - 0.5
        poly('neck', [(hx - 7, hy + .5), (hx + 1, hy - 1.5), (chx + 4.5, cy + 1.5), (chx - 5.5, cy + .5)], (chx, cy - 3, 6, 7))
        ell('chest', chx, cy, 4.6, ry - .3)
        sleg('legBN', bx, top, bx + hind[0], paw=-1, ybot=hind[1])
        sleg('legFN', fx, top - .5, fx + front[0], paw=1, ybot=front[1])
        A.update(cx=cx, cy=cy, L=L, ry=ry, chx=chx, belly=(cx - L + 6, cx + L - 4, cy + ry - 1.6))
    elif pose in ('runA', 'runB', 'zoomA', 'zoomB'):
        zoom = pose.startswith('zoom')
        ext = pose.endswith('A')                     # A: legs fully extended; B: gathered under the body
        cx = 22 - (L - 13) * 0.7
        cy = FLOOR - legH - ry + 1.5 + (1.5 if zoom else 0) - (0 if ext else 1.5)
        top = cy + ry - 1.5
        bx, fx = cx - L + 3, cx + L - 6
        reach = (7 if zoom else 5) if ext else -(3 if zoom else 2)
        sleg('farback', bx + 3, top + 1, bx + 3 - reach - 1, w=3, far=True)
        sleg('farfront', fx + 3, top, fx + 3 + reach + 1, w=3, far=True)
        A['tail'] = (cx - L + 2.5, cy - ry * 0.75)
        draw_tail(P, A['tail'], ell, poly, 'zoom' if zoom else 'run')
        ell('body', cx, cy, L + (1 if zoom else 0), ry - (0.5 if zoom else 0))
        ell('haunch', cx - L + 4.5, cy + 1.5, 5, ry * 0.85)
        hx, hy = cx + L + (2 if zoom else 1), cy - ry - (0.5 if zoom else 2)
        chx = cx + L - 0.5
        poly('neck', [(hx - 7, hy + .5), (hx + 1, hy - 1.5), (chx + 4.5, cy + 1.5), (chx - 5.5, cy + .5)], (chx, cy - 3, 6, 7))
        ell('chest', chx, cy, 4.6, ry - (0.5 if zoom else 0))
        sleg('legBN', bx, top, bx - reach, paw=-1)
        sleg('legFN', fx, top - .5, fx + reach, paw=1)
        A.update(cx=cx, cy=cy, L=L, ry=ry, chx=chx, belly=(cx - L + 6, cx + L - 4, cy + ry - 1.6), zoom=zoom)
    elif pose in ('sit', 'lickA', 'lickB', 'scratchA', 'scratchB'):
        lick, scratch = pose.startswith('lick'), pose.startswith('scratch')
        cx = 19
        hx, hy = cx + 10, 10.5
        if lick: hx, hy = cx + 12.5, 16 + (1 if pose == 'lickB' else 0)       # head bowed to the raised paw, bobbing as it licks
        if scratch: hx, hy = cx + 9, 13                                     # head tipped down toward the scratching foot
        A['tail'] = (cx - 6.5, 25)
        leg('farfront', cx + 10.5, 21, FLOOR - 2, w=3, far=True)
        ell('haunch', cx - 1.5, 27.5, 7.5, 6)
        draw_tail(P, A['tail'], ell, poly, 'sit')
        ell('body', cx + 4, 21, 5.5, 8.5)
        chx = cx + 7.5
        poly('neck', [(hx - 6.5, hy + .5), (hx + 1, hy - 1.5), (chx + 4, 21), (chx - 5, 20)], (chx, 15, 6, 7))
        ell('chest', chx, 20.5, 4.4, 6.5)
        if lick:   # near front leg lifted and bent, paw held up under the chin
            zones['legFN'] = ('leg', cx + 6.5, 4, False)
            for y in range(23, 28):
                for x in range(int(cx + 6.5 + (27 - y) * .8), int(cx + 10.5 + (27 - y) * .8)): put(x, y, 'legFN')
            for y in range(21, 24):
                for x in range(int(cx + 11), int(cx + 17)): put(x, y, 'legFN', 'c')   # white paw up at the mouth
        else:
            leg('legFN', cx + 6.5, 22, FLOOR - 2, paw=1)
        if scratch:   # near hind leg brought forward under the belly and up, foot raking behind the ear (A/B: two kick positions)
            k = 0 if pose == 'scratchA' else 2
            zones['legBN'] = ('leg', cx, 4, False)
            kx, ky = cx + 5, 27                               # knee raised forward, at the front of the haunch
            fx, fy = hx - 11 + k / 2, hy + k                  # foot up behind the back of the head
            for y in range(int(fy + 2), ky + 1):              # lower leg: a shaded bar with its own outline, so it reads over the body
                t = (y - (fy + 2)) / max(1, ky - (fy + 2))
                xs = int(round(fx + (kx - fx) * t))
                put(xs - 1, y, 'legBN', 'o'); put(xs + 3, y, 'legBN', 'o')
                for x in range(xs, xs + 3): put(x, y, 'legBN', 's' if x == xs + 2 else 'b')
            for y in range(ky - 2, ky + 4):                   # the knee: a rounded joint where the thigh folds
                for x in range(int(kx) - 3, int(kx) + 3):
                    if (x - kx + .5) ** 2 / 9 + (y - ky - .5) ** 2 / 9 <= 1: put(x, y, 'legBN', 's')
            for y in range(int(fy - 1), int(fy + 3)):         # white foot, outlined
                for x in range(int(fx - 2), int(fx + 4)):
                    edge = y in (int(fy - 1), int(fy + 2)) or x in (int(fx - 2), int(fx + 3))
                    put(x, y, 'legBN', 'o' if edge else 'c')
        else:
            for y in (32, 33):
                for x in range(int(cx - 5), int(cx + 3)): put(x, y, 'pawB')
            zones['pawB'] = ('leg', cx - 5, 8, False)
        A.update(cx=cx + 4, cy=21, L=5.5, ry=8.5, chx=chx, belly=None)
    elif pose in ('sleep', 'sleepT'):
        cx = 20 - (L - 13) * 0.6
        bry = max(ry - .5, 4.5)
        cy = FLOOR + 1 - bry
        A['tail'] = (cx - L + 3, cy - bry + 1 - (1.5 if pose == 'sleepT' else 0))   # tail tip flicks up
        ell('body', cx, cy, L + 1, bry)
        draw_tail(P, A['tail'], ell, poly, 'sleep')
        hx, hy = cx + L + .5, FLOOR + 1.5 - hry
        twitch = pose == 'sleepT'   # dreaming: front paws paddle forward
        for y in (32, 33):
            for x in range(int(hx - 3), int(hx + (11 if twitch else 6))): put(x, y, 'pawF')
        if twitch:
            for x in range(int(hx + 8), int(hx + 12)): put(x, 31, 'pawF')   # one paw kicking up
        zones['pawF'] = ('leg', hx - 3, 9, False)
        A.update(cx=cx, cy=cy, L=L + 1, ry=bry, chx=cx + L - 1, belly=None)
    else:  # bow: rear up, chest down, front legs flat forward, tail high (trip: the same but the front legs buckle under and the nose hits the floor)
        trip = pose == 'trip'
        cx = 19
        A['tail'] = (cx - 9, 12)
        leg('farback', cx - 6, 19, FLOOR - 2, w=3, far=True)
        draw_tail(P, A['tail'], ell, poly, 'bow')
        ell('body', cx - 3, 18, 8, ry - .5)
        ell('chest', cx + 6, 24, 6.5, ry - 1)
        poly('torso', [(cx - 8, 13), (cx + 2, 15), (cx + 10, 22), (cx + 6, 29), (cx - 6, 23)], (cx, 20, 9, 7))
        leg('legBN', cx - 10, 20, FLOOR - 2, paw=-1)
        fx0, fx1 = (cx + 1, cx + 9) if trip else (cx + 6, cx + 18)   # tripping: paws folded back under the chest
        for y in range(29, 31):
            for x in range(int(fx0 + 2), int(fx1 + 1)): put(x, y, 'farpaw', 'd')
        for y in range(31, FLOOR + 1):
            for x in range(int(fx0), int(fx1)): put(x, y, 'pawF')
        zones['pawF'] = ('leg', fx0, 12, False)
        zones['farpaw'] = ('leg', fx0 + 2, 11, True)
        hx, hy = (cx + 14, 26.5) if trip else (cx + 15, 21.5)
        A.update(cx=cx - 3, cy=18, L=8, ry=ry - .5, chx=cx + 6, belly=None)

    # head, muzzle, ears
    A.update(hx=hx, hy=hy)
    sleeping = pose in ('sleep', 'sleepT')
    ell('head', hx, hy, hrx, hry * (.92 if sleeping else 1))
    mx, my = (hx + hrx - .5, FLOOR - .6) if sleeping else (hx + hrx, hy + 2.7)
    if pose == 'shakeA': mx, my = hx + hrx - .3, hy + 1.2   # muzzle tipped up
    if pose == 'shakeB': mx, my = hx + hrx - .2, hy + 3.4   # muzzle tipped down
    ell('muzzle', mx, my, mrx, mry * (.85 if sleeping else 1))
    A.update(mx=mx, my=my)
    P = dict(P, _gait=('zoom' if pose.startswith('zoom') else 'run' if pose.startswith('run') or pose in ('shakeA', 'sleepT') else None))
    draw_ears(P, hx, hy, hrx, hry, ell, poly, sleeping)

    # tones from zones (light from the top-left)
    for y in range(H):
        for x in range(W):
            sid = sh[y][x]
            if not sid or g[y][x] != 'b': continue
            z = zones[sid]
            if z[0] == 'leg':
                far = z[3]
                row = [xx for xx in range(W) if sh[y][xx] == sid]
                left, right = min(row), max(row)
                if far: g[y][x] = 's' if x == left else 'd'
                else: g[y][x] = 'l' if x == left else ('s' if x == right and right > left + 1 else 'b')
                continue
            cx_, cy_, rx_, ry_ = z
            t = (y + .5 - cy_) / ry_ * .85 + (x + .5 - cx_) / rx_ * .25
            g[y][x] = 'l' if t < -.6 else 'd' if t > .92 else 's' if t > .5 else 'b'
    for y in range(H):
        for x in range(W):
            if sh[y][x] in ('earF', 'tailF') and g[y][x] in 'bl': g[y][x] = 's'

    if P['tail'] == 'curl' and pose not in ('sleep', 'sleepT'):
        tx, ty = A['tail']
        for y in range(H):
            for x in range(W):
                if sh[y][x] == 'tail' and ((x + .5 - (tx - .7)) / 2.1) ** 2 + ((y + .5 - (ty - 3.7)) / 1.9) ** 2 <= 1: g[y][x] = None; sh[y][x] = None
    for y in range(H):
        for x in range(W):
            if g[y][x] == 'a' and (y + 1 >= H or g[y + 1][x] != 'a' or x + 1 >= W or g[y][x + 1] != 'a'): g[y][x] = 'e' if P['marks'] == 'beagle' else 'd'
    if P['ear'] in ('pointy', 'folded', 'small') and pose not in ('sleep', 'sleepT'):   # inner ear: pixels fully inside the near ear
        inner = [(x, y) for y in range(1, H - 1) for x in range(1, W - 1) if sh[y][x] == 'earN' and all(sh[y + dy][x + dx] == 'earN' for dx, dy in ((1, 0), (-1, 0), (0, -1)))]
        for (x, y) in inner: g[y][x] = 'i'
    apply_marks(P, pose, g, sh, A)

    if P.get('fluffy'):   # scalloped fur along the top and back edges
        for x in range(W):
            for y in range(H):
                if g[y][x] and sh[y][x] in ('body', 'head', 'chest', 'haunch', 'tail'):
                    if x % 3 == 0 and y > 0 and g[y - 1][x] is None: g[y - 1][x] = 'l'
                    break

    # outline
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'o'
    g = out
    # remove lone outline corner nubs (outline pixel with a single outline neighbour and no fill neighbour diagonally) — keep simple: none

    draw_face(P, g, A, sleeping)
    if P.get('collar') and pose not in ('sleep', 'sleepT', 'bow'): draw_collar(g, A, pose)
    global LAST_ANCHORS
    LAST_ANCHORS = dict(A, mrx=P['muz'][0])   # mouth/head positions, for baking toys into frames
    return g

WAG = 0   # tail wag: -1 tip back/down, +1 tip forward/up (set by the sheet builder)
def draw_tail(P, at, ell, poly, pose):
    tx, ty = at; w = WAG
    if w and not (P['tail'] == 'flag' or (P['tail'] in ('thin', 'brush') and pose == 'sit')): tx += 1.5 * w; ty -= .5 * abs(w)   # other tails: the whole tail swings
    t = P['tail']
    if t == 'curl':
        if pose in ('sleep', 'sleepT'): ell('tail', tx, ty - 1, 4.5, 3.2)
        else:
            ell('tail', tx - 1, ty - 4, 5, 4.6)
            poly('tailbase', [(tx + 1, ty - 2), (tx + 5, ty - 1), (tx + 5, ty + 2), (tx + 1, ty + 1)], (tx, ty, 4, 3))
    elif t in ('flag', 'thin', 'brush') and pose == 'sit':
        lift = (2 + 1.5 * w) if w else 0
        poly('tail', [(tx + 3, 29), (tx - 6, 31.5 - lift), (tx - 7, 33.9 - lift), (tx + 3, 33.9)], (tx - 2, 31.5, 5, 2))   # wag: sweeps the floor
    elif t == 'flag' and pose in ('run', 'zoom'):
        if pose == 'zoom': poly('tail', [(tx + 2, ty + 2), (tx - 9, ty - 1), (tx - 9.5, ty + 1), (tx + 2, ty + 4)], (tx - 3, ty + 1, 5, 2))
        else: poly('tail', [(tx + 2, ty + 2), (tx - 3, ty - 4), (tx - 6, ty - 7), (tx - 4.5, ty - 8), (tx - 1, ty - 4.5), (tx + 3.5, ty)], (tx - 2, ty - 3, 4, 4))
    elif t == 'flag':
        if pose in ('sleep', 'sleepT'): poly('tail', [(tx, ty), (tx - 7, ty + 3), (tx - 7, ty + 5), (tx, ty + 3)], (tx - 3, ty + 2, 4, 2))
        else: poly('tail', [(tx + 2, ty + 2), (tx - 1 + w, ty - 2), (tx - 3 + 3 * w, ty - 8), (tx - 1.5 + 3 * w, ty - 9.5), (tx + .5 + w, ty - 3), (tx + 3.5, ty)], (tx, ty - 4, 3, 5))
    elif t == 'plume':
        if pose in ('sleep', 'sleepT'): ell('tail', tx, ty, 5, 3)
        else: ell('tail', tx + 1, ty - 3, 5, 3.6); ell('tail', tx + 4.5, ty - 5.2, 3.6, 2.6)
    elif t == 'thin':
        if pose == 'bow': poly('tail', [(tx + 2, ty + 3), (tx - 3, ty - 4), (tx - 2, ty - 5), (tx + 3, ty + 1)], (tx, ty, 3, 4))
        else: poly('tail', [(tx + 2, ty + 1.5), (tx - 6, ty + 5), (tx - 6.5, ty + 4), (tx + 2, ty - .5)], (tx - 2, ty + 2, 5, 3))
    elif t == 'brush':
        if pose == 'bow': poly('tail', [(tx + 3, ty + 3), (tx - 1, ty - 1), (tx - 4, ty - 6), (tx - 2, ty - 7), (tx + 2, ty - 2), (tx + 5, ty + 1)], (tx, ty - 2, 4, 5))
        elif pose in ('sleep', 'sleepT'): poly('tail', [(tx, ty), (tx - 8, ty + 3), (tx - 8, ty + 6), (tx, ty + 4)], (tx - 4, ty + 3, 5, 3))
        else: poly('tail', [(tx + 2, ty), (tx - 2, ty + 3), (tx - 4, ty + 9), (tx - 2, ty + 11), (tx, ty + 6), (tx + 3, ty + 3)], (tx, ty + 4, 3, 6))

def draw_ears(P, hx, hy, hrx, hry, ell, poly, sleeping):
    top = hy - hry
    e = P['ear']
    if e in ('pointy', 'folded', 'small'):
        if sleeping:
            poly('earN', [(hx - 6, top + 2.5), (hx - 3.5, top - 1.5), (hx + .5, top + 1.5)], (hx - 3, top, 3, 2))
            return
        h = {'pointy': 5.4, 'folded': 3.8, 'small': 3.2}[e]
        poly('earF', [(hx + .2, top + .8), (hx + 3.6, top + .6 - h), (hx + 5.6, top + 2.2)], (hx + 3, top, 3, 3))
        poly('earN', [(hx - 5.5, top + 2.2), (hx - 2.8, top + .6 - h - .5), (hx + .8, top + .6)], (hx - 2.5, top - 1, 3, 3))
        if e == 'folded':   # tips fold forward
            poly('earN', [(hx - 3.6, top - 3.4), (hx - .2, top - 2.6), (hx - 1.8, top - 1.4)], (hx - 2, top - 3, 2, 1), 'd')
    elif e == 'floppy' and P.get('_gait'):
        if P['_gait'] == 'zoom': ell('earN', hx - 5, hy - .5, 4.8, 2.4, 'a')       # flat back in the wind
        else: ell('earN', hx - 3.6, hy + .8, 3.4, 3.6, 'a')                        # lifted, flapping
    elif e == 'floppy':
        ell('earN', hx - 2.4, hy + (2.5 if sleeping else 1.6), 2.8, 5.4 if not sleeping else 3.6, 'a')
    elif e == 'long':
        ell('earN', hx - 2.2, hy + (2.5 if sleeping else 2), 2.5, 5.2 if not sleeping else 3.4, 'a')

def apply_marks(P, pose, g, sh, A):
    m, hx, hy = P['marks'], A['hx'], A['hy']
    def paint(test, light='c', dark='k', only=None):
        for y in range(H):
            for x in range(W):
                if g[y][x] and g[y][x] in 'bslde' and (only is None or sh[y][x] in only) and test(x + .5, y + .5):
                    g[y][x] = dark if g[y][x] in 'sd' else light
    legs = ('legBN', 'legFN', 'pawB', 'pawF', 'farback', 'farfront', 'farpaw')
    sleeping = pose in ('sleep', 'sleepT')
    muzzle_lower = lambda x, y: ((x - A['mx'] + .8) / (P['muz'][0] + 1.2)) ** 2 + ((y - A['my'] - .6) / (P['muz'][1] + .2)) ** 2 <= 1 and y > A['my'] - .6
    cheek = lambda x, y: ((x - hx - 1.5) / 3.2) ** 2 + ((y - hy - 3.2) / 2.2) ** 2 <= 1
    chest = lambda x, y: ((x - A['chx'] - 1.5) / 3.2) ** 2 + ((y - A['cy'] - .5) / (A['ry'] * .8)) ** 2 <= 1
    socks = lambda x, y: y > FLOOR - 2.5
    tailtip = lambda k: (lambda x, y: sh[int(y)][int(x)] == 'tail' and (y < A['tail'][1] - 7 if k == 'up' else y > A['tail'][1] + 8))
    if m == 'shiba':
        paint(muzzle_lower); paint(cheek, only=('head', 'muzzle'))
        if not sleeping: paint(chest, only=('chest', 'neck', 'body'))
        if A.get('belly'):
            x0, x1, yb = A['belly']; paint(lambda x, y: x0 < x < x1 and y > yb, only=('body',))
        paint(lambda x, y: y > A['tail'][1] - 3.2, only=('tail',))
        paint(socks, only=legs)
        if not sleeping:
            for (dx, dy) in ((1, -2), (2, -2)): set_if(g, int(hx + dx), int(hy + dy), 'c')
    elif m == 'beagle':
        cx, cy, L, ry = A['cx'], A['cy'], A['L'], A['ry']
        paint(lambda x, y: y < cy - ry * .15 and cx - L + 2 < x < cx + L - 3, light='f', dark='e', only=('body', 'haunch', 'torso'))
        paint(muzzle_lower); paint(lambda x, y: ((x - A['mx']) / (P['muz'][0] + .5)) ** 2 + ((y - A['my']) / (P['muz'][1] + .5)) ** 2 <= 1, only=('muzzle',))
        if not sleeping:
            paint(lambda x, y: abs(x - (hx + 2.2)) < 1.1 and hy - P['head'][1] + 1 < y < hy + 2, only=('head',))   # blaze
            paint(chest, only=('chest', 'neck', 'body'))
        if A.get('belly'):
            x0, x1, yb = A['belly']; paint(lambda x, y: x0 < x < x1 and y > yb - .5, only=('body',))
        paint(lambda x, y: y > FLOOR - 4.5, only=legs)
        if pose.startswith('zoom'): paint(lambda x, y: x < A['tail'][0] - 7, only=('tail',))
        elif pose.startswith('run'): paint(lambda x, y: y < A['tail'][1] - 5.5, only=('tail',))
        else: paint(tailtip('up' if pose not in ('sleep', 'sleepT') else 'x'), only=('tail',))
        if pose in ('sleep', 'sleepT'): paint(lambda x, y: x < A['tail'][0] - 4, only=('tail',))
    elif m == 'collie':
        paint(muzzle_lower); paint(lambda x, y: ((x - A['mx']) / (P['muz'][0] + .5)) ** 2 + ((y - A['my']) / (P['muz'][1] + .5)) ** 2 <= 1, only=('muzzle',))
        if not sleeping:
            paint(lambda x, y: abs(x - (hx + 2.4)) < 1.1 and hy - P['head'][1] < y < hy + 2, only=('head',))  # blaze
            paint(chest, only=('chest', 'neck', 'body'))
            paint(lambda x, y: abs((x - A['hx']) - (y - A['hy']) * .2 + 3) < 2.2 and y > A['hy'] + 3, only=('neck',))  # white ruff
        paint(lambda x, y: y > FLOOR - 3.5, only=legs)
        if pose in ('stand', 'walkA', 'walkB', 'sit'): paint(lambda x, y: y > A['tail'][1] + 8.5, only=('tail',))
        elif pose == 'bow': paint(lambda x, y: y < A['tail'][1] - 5, only=('tail',))
        else: paint(lambda x, y: x < A['tail'][0] - 5.5, only=('tail',))
    elif m == 'mochi':
        pass
    elif m == 'bean':
        paint(lambda x, y: ((x - A['mx']) / (P['muz'][0] + .3)) ** 2 + ((y - A['my'] - .3) / (P['muz'][1])) ** 2 <= 1 and y > A['my'], light='c', dark='s', only=('muzzle',))

def set_if(g, x, y, k):
    if 0 <= x < W and 0 <= y < H and g[y][x]: g[y][x] = k

def draw_face(P, g, A, sleeping):
    hx, hy = A['hx'], A['hy']
    ex, ey = int(hx + 3), int(hy - 1.5)
    if sleeping:
        for x, y in ((ex - 1, ey + 1), (ex, ey + 2), (ex + 1, ey + 2), (ex + 2, ey + 1)): set_if(g, x, y, 'y')
    else:
        for (dx, dy, k) in ((0, 0, 'w'), (1, 0, 'y'), (0, 1, 'y'), (1, 1, 'y')): set_if(g, ex + dx, ey + dy, k)
        if P['marks'] == 'mochi': set_if(g, ex - 1, ey + 3, 'p'); set_if(g, ex, ey + 3, 'p')
    # nose at the muzzle tip, mouth under it
    mx, my, mrx = A['mx'], A['my'], P['muz'][0]
    tip = int(mx + mrx - .6)
    ny = int(my - (1.2 if not sleeping else .8))
    for (x, y) in ((tip - 1, ny), (tip, ny), (tip, ny + 1)):
        if 0 <= x < W and 0 <= y < H and g[y][x] and g[y][x] != 'o': g[y][x] = 'n'
        elif 0 <= x < W and 0 <= y < H and g[y][x] == 'o' and x == tip: g[y][x] = 'n'
    if not sleeping:
        my2 = int(my + 1.4)
        for x in (tip - 4, tip - 3, tip - 2):
            if 0 <= x < W and g[my2][x] and g[my2][x] not in 'oyn': g[my2][x] = 'm'

def draw_collar(g, A, pose):
    hx, hy = A['hx'], A['hy']
    x0, y0 = int(hx - 5), int(hy + 2)
    pts = [(x0, y0), (x0 + 1, y0 + 1), (x0 + 1, y0 + 2), (x0 + 2, y0 + 3), (x0 + 2, y0 + 4), (x0 + 3, y0 + 5), (x0 + 3, y0 + 6)]
    for (x, y) in pts:
        if 0 <= y < H and g[y][x] and g[y][x] not in 'o':
            g[y][x] = 'r'
            if g[y][x - 1] and g[y][x - 1] != 'o': g[y][x - 1] = 'q'
    tx, ty = pts[-1][0] + 1, pts[-1][1] + 1
    for y in (ty, ty + 1): set_if(g, tx, y, 't')

PAL = {   # key -> token per dog
  'biscuit': dict(a='biscuit-ear', o='biscuit-outline', d='biscuit-deep', s='biscuit-shade', b='biscuit-base', l='biscuit-light', c='biscuit-mark', k='biscuit-creamshade', i='biscuit-inner', y='biscuit-eye', w='mochi-light', n='biscuit-eye', m='biscuit-mouth', r='biscuit-collar', q='biscuit-collardark', t='biscuit-tag'),
  'pudding': dict(o='pudding-outline', d='pudding-deep', s='pudding-shade', b='pudding-base', l='pudding-light', c='pudding-mark', k='pudding-creamshade', e='pudding-saddle', f='pudding-saddlelight', a='pudding-ear', y='pudding-eye', w='mochi-light', n='pudding-eye', m='pudding-mouth', r='pudding-collar', q='pudding-collardark', t='biscuit-tag'),
  'mochi': dict(a='mochi-ear', c='mochi-mark', k='mochi-shade', o='mochi-outline', d='mochi-deep', s='mochi-shade', b='mochi-base', l='mochi-light', i='plush-e', p='mochi-blush', y='mochi-eye', w='mochi-light', n='mochi-nose', m='mochi-mouth', r='mochi-collar', q='mochi-collardark', t='biscuit-tag'),
  'bean': dict(o='bean-outline', d='bean-deep', s='bean-shade', b='bean-base', l='bean-light', c='bean-mark', a='bean-ear', y='bean-eye', w='mochi-light', n='bean-eye', m='bean-mouth', r='bean-collar', q='bean-collardark', t='biscuit-tag'),
  'pepper': dict(a='pepper-ear', o='pepper-outline', d='pepper-shade', s='pepper-shade', b='pepper-base', l='pepper-light', c='pepper-mark', k='pepper-markshade', i='pepper-inner', y='pepper-eye', w='mochi-light', n='pepper-nose', m='pepper-markshade', r='biscuit-tag', q='pepper-collardark', t='biscuit-collar'),
}
HEX = {}   # token -> hex, filled from palette.json
FALLBACK = {'e': 's', 'f': 'b', 'a': 's', 'c': 'l', 'k': 's', 'i': 'l', 'p': 'l', 'w': 'l'}   # beagle-only keys (saddle etc.) on other breeds
def hexof(breed, k):
    if k.startswith('#'): return k
    pal = PAL[breed]
    return HEX[pal[k] if k in pal else pal[FALLBACK.get(k, 'b')] if FALLBACK.get(k, 'b') in pal else pal['b']]

def finalize(breed, g):
    """Merge keys that share a palette slot (the studio rejects two keys for one colour)."""
    pal = PAL[breed]
    slot = {k: HEX[t].lower() for k, t in pal.items()}
    first = {}
    for k in pal:
        first.setdefault(slot[k], k)
    rows = []
    for r in g:
        s = ''.join(first[slot[c]] if c in pal else ('.' if c is None else '?' + c) for c in r)
        rows.append('|'.join(s[i:i + 8] for i in range(0, W, 8)))
    keys = {k: pal[k] for k in set(first.values())}
    keys['.'] = 'transparent'
    return rows, keys

def png(path, frames, scale=6):
    cols = len(frames[0]); rws = len(frames)
    PW, PH = cols * (W + 2) * scale, rws * (H + 2) * scale
    img = [[(231, 225, 214)] * PW for _ in range(PH)]
    for ri, row in enumerate(frames):
        for ci, (breed, g) in enumerate(row):
            for y in range(H):
                for x in range(W):
                    k = g[y][x]
                    if not k: continue
                    hx = hexof(breed, k)
                    c = tuple(int(hx[i:i + 2], 16) for i in (1, 3, 5))
                    for sy in range(scale):
                        for sx in range(scale):
                            img[(ri * (H + 2) + y + 1) * scale + sy][(ci * (W + 2) + x + 1) * scale + sx] = c
    raw = b''.join(b'\x00' + bytes(sum(r, ())) for r in img)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', PW, PH, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

POSES = ['stand', 'walkA', 'walkB', 'sit', 'sleep', 'bow', 'runA', 'runB', 'zoomA', 'zoomB']
if __name__ == '__main__':
    out = sys.argv[1]
    HEX.update(json.load(open(out + '/palette.json')))
    sheet, data = [], {}
    for b in BREEDS:
        row = []
        data[b] = {}
        for p in POSES:
            g = compose(b, p); row.append((b, g))
            data[b][p] = finalize(b, g)
        sheet.append(row)
    png(out + '/sheet.png', sheet)
    json.dump(data, open(out + '/hd_frames.json', 'w'))
    bad = [(b, p) for b in data for p in data[b] if any('?' in r for r in data[b][p][0])]
    print('frames:', sum(len(v) for v in data.values()), 'unmapped keys:', bad)
