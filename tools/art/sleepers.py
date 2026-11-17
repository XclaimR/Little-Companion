# Sleeping positions (48x36, side view, head to the right), alongside the chin-on-paws "sleep" frame:
#   curl  — curled up nose-to-tail
#   side  — sprawled on its side, legs stretched out
#   belly — on its back, belly up, paws in the air
# and the two tumble frames (a roll, then a sprawl). Breed-aware: set BREED (a compose.BREEDS key) and the body length,
# thickness, leg length, ears, tail and markings follow it.
# Keys as compose.py: o outline, d deep, s shade, b base, l light, c white, k white shade, e saddle, f saddle light,
# a ear, i inner ear, y eye, w eye highlight.
W, H, FLOOR = 48, 36, 33
BREED = 'pudding'

def breed():
    import compose
    P = compose.BREEDS[BREED]
    return P, P['L'] / 12.5, P['ry'] / 6.2, P['leg'] / 8

class Canvas:
    def __init__(self):
        self.g = [[None] * W for _ in range(H)]; self.sh = [[None] * W for _ in range(H)]; self.zones = {}
    def put(self, x, y, sid, k='b'):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H: self.g[y][x] = k; self.sh[y][x] = sid
    def ell(self, sid, cx, cy, rx, ry, k='b'):
        self.zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: self.put(x, y, sid, k)
    def tri(self, sid, pts, k='b'):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        self.zones.setdefault(sid, (sum(xs) / 3, sum(ys) / 3, 2.5, 2.5))
        for y in range(H):
            for x in range(W):
                px, py, inside, j = x + .5, y + .5, False, len(pts) - 1
                for i in range(len(pts)):
                    (xi, yi), (xj, yj) = pts[i], pts[j]
                    if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi: inside = not inside
                    j = i
                if inside: self.put(x, y, sid, k)
    def stick(self, sid, x0, y0, x1, y1, w=3):   # a leg as a thick line
        self.zones.setdefault(sid, ('leg',))
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(n + 1):
            t = i / n; cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for dx in range(w):
                for dy in range(w - 1): self.put(cx + dx - w / 2, cy + dy - w / 2 + .5, sid)
    def shade(self, beagle):
        for y in range(H):
            for x in range(W):
                sid = self.sh[y][x]
                if not sid or self.g[y][x] != 'b': continue
                z = self.zones[sid]
                if z[0] == 'leg': self.g[y][x] = 's' if self.sh[min(H - 1, y + 1)][x] != sid else 'b'; continue
                cx, cy, rx, ry = z
                t = (y + .5 - cy) / ry * .85 + (x + .5 - cx) / rx * .25
                self.g[y][x] = 'l' if t < -.6 else 'd' if t > .92 else 's' if t > .5 else 'b'
        for y in range(H):   # ear edges darker
            for x in range(W):
                if self.g[y][x] == 'a' and (x + 1 < W and self.g[y][x + 1] != 'a' or y + 1 < H and self.g[y + 1][x] != 'a'): self.g[y][x] = 'e' if beagle else 'd'
    def paint(self, test, light, dark, only):
        for y in range(H):
            for x in range(W):
                if self.g[y][x] and self.g[y][x] in 'bsld' and self.sh[y][x] in only and test(x + .5, y + .5):
                    self.g[y][x] = dark if self.g[y][x] in 'sd' else light
    def finish(self, eye, open=False):
        out = [r[:] for r in self.g]
        for y in range(H):
            for x in range(W):
                if self.g[y][x] is None and any(0 <= x + dx < W and 0 <= y + dy < H and self.g[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    out[y][x] = 'o'
        if open:                                     # awake (mid-tumble): a round eye with a highlight
            x, y = eye[1]
            for (dx, dy, k) in ((0, -1, 'w'), (1, -1, 'y'), (0, 0, 'y'), (1, 0, 'y')): out[y + dy][x + dx] = k
        else:
            for (x, y) in eye: out[y][x] = 'y'      # closed eye: a short lid line
        return out

def ear(c, P, hx, hy, lying, flip=False):
    """The breed's ear on a head at (hx, hy). Floppy and long ears lie flat; upright ones fold back when asleep."""
    e = P['ear']
    if e in ('floppy', 'long'):
        if flip: c.ell('ear', hx - 1.5, hy - 4.5, 3.2, 2.2, 'i')                      # flipped inside-out, the pale side up
        elif lying == 'up': c.ell('ear', hx - 1.5, hy - 3.7, 3.4, 2.1, 'a')
        elif lying == 'down': c.ell('ear', hx - 1.5, hy + 3.7, 3.2, 1.6 + (.6 if e == 'long' else 0), 'a')
        else: c.ell('ear', hx + 2.5, hy - 2, 2.6, 3.4 + (.6 if e == 'long' else 0), 'a')
    else:
        h = {'pointy': 3.6, 'folded': 2.8, 'small': 2.2}[e]
        if lying == 'down': c.tri('ear', [(hx - 2, hy + 3), (hx + 1.5, hy + 3), (hx - 1.5, hy + 3 + h)])
        else: c.tri('ear', [(hx - 3, hy - 2.5), (hx + .5, hy - 3.5), (hx - 2.5, hy - 3 - h)])
        if e == 'folded': c.put(hx - 2.5, hy - 2.2 - h, 'ear', 'a')

def tail(c, P, x, y, d, wrap=False):
    """The breed's tail from (x, y), pointing d (-1 left / +1 right). wrap: curled round the front (the curl position)."""
    t = P['tail']
    if wrap:
        if t == 'curl': c.ell('tail', x, y - 1, 3.4, 2.6); return
        r = {'plume': 2.6, 'brush': 2.2, 'flag': 1.6, 'thin': 1.1}[t]
        for xx in range(int(x - 9), int(x + 10)):
            for yy in range(int(y - 3), int(y + 4)):
                if ((xx + .5 - x) / 9.5) ** 2 + ((yy + .5 - y - 1) / r) ** 2 <= 1: c.put(xx, yy, 'tail')
        c.zones['tail'] = (x, y, 9, r); return
    if t == 'curl': c.ell('tail', x + 2 * d, y - 2.5, 3, 2.6); return
    if t == 'plume': c.ell('tail', x + 4 * d, y - .5, 4.8, 2.4); return
    th = {'brush': 2, 'flag': 1, 'thin': 0}[t]
    for i in range(9):
        for k in range(th + 1): c.put(x + d * i, y - (i * .2) + k, 'tail')
    c.zones['tail'] = (x + 4 * d, y, 4, 1.5)

def marks(c, P):
    if P['marks'] in ('beagle', 'collie', 'shiba'):
        c.paint(lambda x, y: True, 'c', 'k', ('muzzle', 'paw'))

def white_tip(c, P, side):
    if P['marks'] not in ('beagle', 'collie'): return
    xs = [x for y in range(H) for x in range(W) if c.sh[y][x] == 'tail']
    if not xs: return
    lim = min(xs) + 2 if side < 0 else max(xs) - 2
    c.paint(lambda x, y: (x < lim + .5) if side < 0 else (x > lim + .5), 'c', 'k', ('tail',))

def curl(twitch=False):
    P, k, th, lg = breed(); c = Canvas()
    bx, brx, bry = 21, 13 * k, 6.5 * th
    hx = min(41, bx + brx - 4 + 3 * (k - 1))
    tail(c, P, bx - 4, 32, 1, wrap=True)                          # tail wrapped along the front
    c.ell('body', bx, 33.5 - bry, brx, bry)
    if P['tail'] == 'curl': tail(c, P, bx - brx + 4, 33.5 - bry * 1.6, 1)   # a shiba's curl stays on top
    c.ell('head', hx, 28.5, 5.6 * (P['head'][1] / 5.8), 4.6)
    c.ell('muzzle', hx - 4, 31.2, 3.2 * min(1.3, P['muz'][0] / 4.6), 2)
    ear(c, P, hx + (1 if P['ear'] in ('floppy', 'long') else 1.5), 27 - (1.5 if twitch else 0), 'side')
    c.ell('paw', hx - 5, 32.4, 1.8, 1.1)                         # a paw tucked under the chin
    if twitch:
        for x in (bx + 2, bx + 3, bx + 4): c.put(x, 29, 'tail')   # tail tip twitches up
    c.shade(P['marks'] == 'beagle')
    if P['marks'] == 'beagle': c.paint(lambda x, y: y < 33.5 - bry * 1.25, 'f', 'e', ('body',))   # saddle on top
    if P['marks'] == 'shiba': c.paint(lambda x, y: y > 31.5, 'c', 'k', ('body',))                   # cream underside
    marks(c, P)
    white_tip(c, P, 1)
    for x in range(W):                                             # a line along the top of the tail, so it reads apart from the body
        ys = [y for y in range(H) if c.sh[y][x] == 'tail']
        if ys and ys[0] > 0 and c.sh[ys[0] - 1][x] == 'body': c.g[ys[0]][x] = 'o'
    return c.finish([(int(hx - 2), 28), (int(hx - 1), 29), (int(hx), 29)])

def side(twitch=False, awake=False):
    P, k, th, lg = breed(); c = Canvas()
    kk = 2 if twitch else 0                                        # dreaming: legs paddle, near pair forward, far pair back
    bx, brx, bry = 19, 13 * k, 5 * th
    cx0, cx1 = bx - brx + 3, bx + brx - 3                          # hips and shoulders
    ln = 3 + 6 * lg                                                # leg reach from the body
    by = 27.5 + (5 - bry) * .6
    for (x, far) in ((cx0, True), (cx1, True), (cx0 + 2, False), (cx1 + 2, False)):
        out = 1 if x > bx else -1
        c.stick('paw' if not far else 'leg', x, by + 2, x + out * (ln * .9 + (kk if not far else -kk)), by + 4.5 + (1 if far else 0))
    tail(c, P, bx - brx + 1, by - 1, -1)
    c.ell('body', bx, by, brx, bry)
    hx = min(42, bx + brx + 4)
    c.ell('head', hx, by - 2, 5.6 * (P['head'][1] / 5.8), 4.6)
    c.ell('muzzle', hx + 5.5, by - .5, 3.4 * min(1.3, P['muz'][0] / 4.6), 2.1)
    ear(c, P, hx, by - 2, 'up')
    c.shade(P['marks'] == 'beagle')
    if P['marks'] == 'beagle': c.paint(lambda x, y: y < by - 3, 'f', 'e', ('body',))
    if P['marks'] in ('beagle', 'collie', 'shiba'): c.paint(lambda x, y: y > by + 2 and cx0 < x < cx1 + 4, 'c', 'k', ('body',))   # light belly toward us
    marks(c, P)
    white_tip(c, P, -1)
    return c.finish([(int(hx + 1), int(by - 3.5)), (int(hx + 2), int(by - 3.5)), (int(hx + 3), int(by - 3.5))], awake)

def belly(twitch=False, awake=False):
    P, k, th, lg = breed(); c = Canvas()
    bx, brx, bry = 21, 13 * k, 5 * th
    by = 29 + (5 - bry) * .5
    reach = 3 + 4 * lg                                             # paws in the air (kicking while dreaming)
    xs = (bx - brx + 5, bx - brx + 9, bx + brx - 8, bx + brx - 4)
    leans = (1, -1, 2, 0) if twitch else (-1, 0, 1, 2)
    for x0, lean in zip(xs, leans):
        c.stick('paw', x0, by - bry + 1, x0 + lean, by - bry - reach + (1 if twitch and lean > 0 else 0))
    tail(c, P, bx - brx + 1, by + 3, -1)
    c.ell('body', bx, by, brx, bry)
    hx = min(42, bx + brx + 2)
    c.ell('head', hx, by + .5, 5.6 * (P['head'][1] / 5.8), 4.6)
    c.ell('muzzle', hx + 5.4, by + 2.2, 3.2 * min(1.3, P['muz'][0] / 4.6), 2)
    ear(c, P, hx, by + .5, 'down')
    c.shade(P['marks'] == 'beagle')
    if P['marks'] in ('beagle', 'collie', 'shiba', 'mochi'): c.paint(lambda x, y: y < by - 1, 'c', 'k', ('body',))   # light belly up top
    marks(c, P)
    white_tip(c, P, -1)
    return c.finish([(int(hx + 1), int(by)), (int(hx + 2), int(by)), (int(hx + 3), int(by))], awake)

def tumble_roll():
    """Head over heels: a tucked ball tilted forward, legs splayed every which way, ears flung up, head upside-down."""
    P, k, th, lg = breed(); c = Canvas()
    bx, by = 21, 25.5
    ln = 3.5 + 4 * lg
    for (a, b, far) in ((bx - 7, by - 4, True), (bx - 2, by - 7, False), (bx + 5, by - 6, True), (bx + 8, by - 1, False)):
        dx, dy = a - bx, b - by; n = (dx * dx + dy * dy) ** .5
        c.stick('leg' if far else 'paw', a, b, a + dx / n * ln, b + dy / n * ln)
    tail(c, P, bx - 9 * k, by + 2, -1)
    c.ell('body', bx, by, 9 * k, 7 * th)
    hx, hy = bx + 8 * k, by + 5
    c.ell('head', hx, hy, 5.2 * (P['head'][1] / 5.8), 4.4)
    c.ell('muzzle', hx - 3, hy + 3.2, 3 * min(1.3, P['muz'][0] / 4.6), 2)    # nose tucked back down at the floor
    if P['ear'] in ('floppy', 'long'): c.ell('ear', hx + 3, hy - 4.5, 2.2, 3.6, 'a')   # flung up in the air
    else: c.tri('ear', [(hx + 1, hy - 3), (hx + 4, hy - 2.5), (hx + 4.5, hy - 7)])
    c.shade(P['marks'] == 'beagle')
    if P['marks'] == 'beagle': c.paint(lambda x, y: y < by - 3, 'f', 'e', ('body',))
    marks(c, P)
    white_tip(c, P, -1)
    return c.finish([(int(hx - 1), int(hy)), (int(hx), int(hy + 1)), (int(hx + 1), int(hy))], True)

def tumble_sprawl():
    """Splat: flat on its tummy, legs splayed four ways, one ear flipped inside-out, eyes wide."""
    P, k, th, lg = breed(); c = Canvas()
    bx, brx, bry = 21, 13 * k, 3.8 * th
    by = 33.5 - bry
    ln = 4 + 5 * lg
    tail(c, P, bx - brx + 2, by - 1, -1)
    c.ell('body', bx, by, brx, bry)
    c.stick('leg', bx + brx - 5, by - bry + 1, bx + brx - 5 + ln * .6, by - bry - ln * .7)   # far front leg flung up in the air
    c.stick('leg', bx - brx + 5, by - bry + 1, bx - brx + 5 - ln * .6, by - bry - ln * .6)   # far hind leg flung up
    c.stick('paw', bx + brx - 6, by + 2, bx + brx - 6 + ln, 33)                # near front leg flat forward
    c.stick('paw', bx - brx + 6, by + 2, bx - brx + 6 - ln, 33)                # near hind leg flat back
    hx = min(42, bx + brx + 3)
    c.ell('head', hx, 30, 5.4 * (P['head'][1] / 5.8), 4)                        # chin on the floor
    c.ell('muzzle', hx + 5, 31.5, 3 * min(1.3, P['muz'][0] / 4.6), 1.8)
    ear(c, P, hx, 30, 'up', flip=P['ear'] in ('floppy', 'long'))
    c.shade(P['marks'] == 'beagle')
    if P['marks'] == 'beagle': c.paint(lambda x, y: y < by - 1, 'f', 'e', ('body',))
    marks(c, P)
    white_tip(c, P, -1)
    return c.finish([(int(hx + 1), 28), (int(hx + 2), 28), (int(hx + 3), 28)], True)

POSITIONS = {'curl': curl, 'side': side, 'belly': belly,
             'curlT': lambda: curl(True), 'sideT': lambda: side(True), 'bellyT': lambda: belly(True)}
