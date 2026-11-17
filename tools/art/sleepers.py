# Ollie's extra sleeping positions (48x36, side view, head to the right), alongside the chin-on-paws "sleep" frame:
#   curl  — curled up nose-to-tail
#   side  — sprawled on its side, legs stretched out
#   belly — on its back, belly up, paws in the air
# Same keys as compose.py (pudding palette): o outline, d deep, s shade, b base, l light, c white, k white shade,
# e saddle, f saddle light, a ear, y eye.
W, H, FLOOR = 48, 36, 33

class Canvas:
    def __init__(self):
        self.g = [[None] * W for _ in range(H)]; self.sh = [[None] * W for _ in range(H)]; self.zones = {}
    def put(self, x, y, sid, k='b'):
        if 0 <= x < W and 0 <= y < H: self.g[y][x] = k; self.sh[y][x] = sid
    def ell(self, sid, cx, cy, rx, ry, k='b'):
        self.zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: self.put(x, y, sid, k)
    def rect(self, sid, x0, y0, x1, y1, k='b'):
        self.zones.setdefault(sid, ((x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2, (x1 - x0 + 1) / 2, (y1 - y0 + 1) / 2))
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1): self.put(x, y, sid, k)
    def shade(self):
        for y in range(H):
            for x in range(W):
                sid = self.sh[y][x]
                if not sid or self.g[y][x] != 'b': continue
                cx, cy, rx, ry = self.zones[sid]
                t = (y + .5 - cy) / ry * .85 + (x + .5 - cx) / rx * .25
                self.g[y][x] = 'l' if t < -.6 else 'd' if t > .92 else 's' if t > .5 else 'b'
        for y in range(H):   # ear edges darker
            for x in range(W):
                if self.g[y][x] == 'a' and (x + 1 < W and self.g[y][x + 1] != 'a' or y + 1 < H and self.g[y + 1][x] != 'a'): self.g[y][x] = 'e'
    def paint(self, test, light, dark, only):
        for y in range(H):
            for x in range(W):
                if self.g[y][x] and self.g[y][x] in 'bsld' and self.sh[y][x] in only and test(x + .5, y + .5):
                    self.g[y][x] = dark if self.g[y][x] in 'sd' else light
    def finish(self, eye):
        out = [r[:] for r in self.g]
        for y in range(H):
            for x in range(W):
                if self.g[y][x] is None and any(0 <= x + dx < W and 0 <= y + dy < H and self.g[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    out[y][x] = 'o'
        for (x, y) in eye: out[y][x] = 'y'          # closed eye: a short lid line
        return out

def curl(twitch=False):
    c = Canvas()
    for (x, y) in [(x, y) for y in range(30, 34) for x in range(8, 26) if ((x - 17) / 9.5) ** 2 + ((y - 33) / 3.2) ** 2 <= 1]:
        c.put(x, y, 'tail')                          # tail wrapped along the front
    c.zones['tail'] = (17, 32, 9, 2)
    c.ell('body', 21, 27.5, 13, 6.5)
    c.ell('head', 30, 28.5, 5.6, 4.6)
    c.ell('muzzle', 26, 31.2, 3.2, 2)
    c.ell('ear', 32.5, 26.5 - (1.5 if twitch else 0), 2.6, 3.4 - (0.6 if twitch else 0), 'a')   # dreaming: the ear flicks up
    if twitch:
        for x in (23, 24, 25): c.put(x, 29, 'tail')   # tail tip twitches up
    c.shade()
    c.paint(lambda x, y: y < 25.5, 'f', 'e', ('body',))                   # saddle on top
    c.paint(lambda x, y: True, 'c', 'k', ('muzzle',))
    c.paint(lambda x, y: x > 22, 'c', 'k', ('tail',))                     # white tail tip under its nose
    return c.finish([(28, 28), (29, 29), (30, 29)])

def side(twitch=False):
    c = Canvas()
    k = 2 if twitch else 0                          # dreaming: legs paddle, near pair forward, far pair back
    c.rect('backlegs', 10 + k, 31 - (1 if twitch else 0), 22 + k, 32 - (1 if twitch else 0)); c.rect('frontlegs', 27 + k, 31 - (1 if twitch else 0), 39 + k, 32 - (1 if twitch else 0))
    c.rect('backlegs2', 12 - k, 33, 21 - k, 33); c.rect('frontlegs2', 28 - k, 33, 37 - k, 33)
    for (x, y) in [(x, y) for y in range(26, 29) for x in range(1, 9)]: c.put(x, y, 'tail')
    c.zones['tail'] = (5, 27, 4, 1.5)
    c.ell('body', 19, 27.5, 13, 5)
    c.ell('head', 36, 25.5, 5.6, 4.6)
    c.ell('muzzle', 41.5, 27, 3.4, 2.1)
    c.ell('ear', 34.5, 21.8, 3.4, 2.1, 'a')        # ear flopped up off the floor
    c.shade()
    c.paint(lambda x, y: y < 24.5, 'f', 'e', ('body',))
    c.paint(lambda x, y: y > 29.5 and 9 < x < 29, 'c', 'k', ('body',))  # white belly toward us
    c.paint(lambda x, y: True, 'c', 'k', ('muzzle',))
    c.paint(lambda x, y: x > 35 + k or x < 13 - k, 'c', 'k', ('frontlegs', 'frontlegs2', 'backlegs', 'backlegs2'))   # white paws
    c.paint(lambda x, y: x < 3.5, 'c', 'k', ('tail',))
    return c.finish([(37, 24), (38, 24), (39, 24)])

def belly(twitch=False):
    c = Canvas()
    legs = ((13, 1, 20), (17, -1, 18), (26, 2, 19), (30, 0, 17)) if twitch else ((13, -1, 19), (17, 0, 19), (26, 1, 19), (30, 2, 19))
    for x0, lean, top in legs:                                       # paws in the air (kicking while dreaming)
        for y in range(top, 25):
            dx = lean if y < top + 2 else 0
            c.rect('leg%d' % x0, x0 + dx, y, x0 + 2 + dx, y)
        c.zones['leg%d' % x0] = (x0 + 1, 22, 1.5, 3)
    for (x, y) in [(x, y) for y in range(32, 34) for x in range(2, 10)]: c.put(x, y, 'tail')
    c.zones['tail'] = (6, 33, 4, 1)
    c.ell('body', 21, 29, 13, 5)
    c.ell('head', 36, 29.5, 5.6, 4.6)
    c.ell('muzzle', 41.4, 31.2, 3.2, 2)
    c.ell('ear', 34.5, 33.2, 3.2, 1.6, 'a')        # ears flopped onto the floor
    c.shade()
    c.paint(lambda x, y: y < 28, 'c', 'k', ('body',))                     # white belly up top
    c.paint(lambda x, y: y < 21 if not twitch else y < 20, 'c', 'k', tuple('leg%d' % x0 for x0 in (13, 17, 26, 30)))
    c.paint(lambda x, y: True, 'c', 'k', ('muzzle',))
    c.paint(lambda x, y: x < 4, 'c', 'k', ('tail',))
    return c.finish([(37, 29), (38, 29), (39, 29)])

POSITIONS = {'curl': curl, 'side': side, 'belly': belly,
             'curlT': lambda: curl(True), 'sideT': lambda: side(True), 'bellyT': lambda: belly(True)}
