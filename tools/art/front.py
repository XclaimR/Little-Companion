# A dog sitting facing the viewer, or with its back to the viewer (48x36). Shapes + zone shading lit from the top-left + outline.
# Breed-aware: set BREED (a compose.BREEDS key) — leg length, ears, tail and markings follow the breed.
import json, sys
W, H, FLOOR = 48, 36, 33
BLINK = False   # eyes shut (an idle blink)
BREED = 'pudding'
EARS = 'floppy'   # or 'pointy', 'folded', 'small': upright ears for breeds that have them

def breed():
    import compose
    return compose.BREEDS[BREED]

def upright_ears(put, cy):
    h = {'pointy': 7, 'folded': 5, 'small': 4}[EARS]
    for side in (-1, 1):
        bx0, bx1 = (16, 22) if side < 0 else (26, 32)
        tipx = (bx0 + 1) if side < 0 else (bx1 - 1)
        for y in range(cy - h, cy + 1):
            t = (y - (cy - h)) / h
            for x in range(bx0, bx1 + 1):
                if abs(x - (tipx + ((bx0 + bx1) / 2 - tipx) * t)) <= (bx1 - bx0) / 2 * t + .5:
                    put(x, y, 'ear' + ('L' if side < 0 else 'R'), 'a' if EARS == 'folded' and y < cy - h + 2 else 'b')

def _canvas():
    g = [[None]*W for _ in range(H)]; sh = [[None]*W for _ in range(H)]; zones = {}
    def ell(sid, cx, cy, rx, ry, k='b'):
        zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x+.5-cx)/rx)**2 + ((y+.5-cy)/ry)**2 <= 1: g[y][x] = k; sh[y][x] = sid
    def rect(sid, x0, y0, x1, y1, k='b'):
        zones.setdefault(sid, ((x0+x1+1)/2, (y0+y1+1)/2, (x1-x0+1)/2, (y1-y0+1)/2))
        for y in range(int(y0), int(y1)+1):
            for x in range(int(x0), int(x1)+1): g[y][x] = k; sh[y][x] = sid
    def put(x, y, sid, k='b'):
        if 0 <= x < W and 0 <= y < H: g[y][x] = k; sh[y][x] = sid
    return g, sh, zones, ell, rect, put

def _shade(g, sh, zones, beagle):
    for y in range(H):
        for x in range(W):
            sid = sh[y][x]
            if not sid or g[y][x] != 'b': continue
            cx, cy, rx, ry = zones[sid]
            t = (y+.5-cy)/ry*.85 + (x+.5-cx)/rx*.3
            g[y][x] = 'l' if t < -.6 else 'd' if t > .95 else 's' if t > .5 else 'b'
    for y in range(H):   # ear edges darker
        for x in range(W):
            if g[y][x] == 'a' and (x+1 < W and g[y][x+1] != 'a' or y+1 < H and g[y+1][x] != 'a'): g[y][x] = 'e' if beagle else 'd'

def _outline(g):
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and any(0 <= x+dx < W and 0 <= y+dy < H and g[y+dy][x+dx] for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))): out[y][x] = 'o'
    return out

def _front_tail(ell, P, wag, o):
    x, y = 35.5 + 2 * wag, 21.5 - abs(wag) + o
    t = P['tail']
    if t == 'curl': ell('tail', x - .5, y + 1, 3.2, 3.4)          # the curled tail over the hip, seen end-on
    elif t == 'plume': ell('tail', x, y - 1, 3.6, 5.2)            # a fluffy plume
    elif t == 'thin': ell('tail', x + .5, y + 1.5, 1.1, 4.2)      # a whippy thin tail
    elif t == 'brush': ell('tail', x, y, 2.3, 4.8)                # a bushy brush
    else: ell('tail', x, y, 1.6, 4.2)                             # the beagle's flag

def front_sit(wag=0):
    P = breed(); m = P['marks']
    o = round(max(0, 8 - P['leg']) * .6)        # short legs: the chest and head sit lower
    g, sh, zones, ell, rect, put = _canvas()
    _front_tail(ell, P, wag, o)
    ell('hipL', 16.5, 29.5, 6, 4.6); ell('hipR', 31.5, 29.5, 6, 4.6)
    ell('body', 24, 24.5 + o, 7.5, 8.5 - o / 2)
    rect('legL', 19, 25 + o, 22, 31); rect('legR', 25, 25 + o, 28, 31)
    rect('pawL', 18, 32, 22, 33); rect('pawR', 25, 32, 29, 33)
    ell('head', 24, 11 + o, 8.2, 7)
    if EARS == 'floppy': ell('earL', 15, 13.5 + o, 3.1, 6.6 if P['ear'] != 'long' else 7.4, 'a'); ell('earR', 33, 13.5 + o, 3.1, 6.6 if P['ear'] != 'long' else 7.4, 'a')
    else: upright_ears(lambda x, y, sid, k: (put(x, y, sid, k), zones.setdefault(sid, (24, 4 + o, 8, 4))), 6 + o)
    _shade(g, sh, zones, m == 'beagle')
    def paint(test, light='c', dark='k', only=None):
        for y in range(H):
            for x in range(W):
                if g[y][x] and g[y][x] in 'bsld' and (only is None or sh[y][x] in only) and test(x+.5, y+.5):
                    g[y][x] = dark if g[y][x] in 'sd' else light
    if m != 'bean':
        paint(lambda x, y: ((x-24)/4.4)**2 + ((y-14.6-o)/3.4)**2 <= 1, only=('head',))       # muzzle
    if m in ('beagle', 'collie'):
        paint(lambda x, y: abs(x-24) < 1.3 and 5 + o < y < 13 + o, only=('head',))           # blaze
    if m in ('beagle', 'collie', 'shiba'):
        paint(lambda x, y: ((x-24)/4.6)**2 + ((y-25-o)/7)**2 <= 1, only=('body',))           # chest
        paint(lambda x, y: y > 28.5, only=('legL', 'legR', 'pawL', 'pawR'))                 # socks
    if m in ('beagle', 'collie'):
        paint(lambda x, y: y < 20 + o, only=('tail',))                                       # white tail tip
    if m == 'shiba':
        paint(lambda x, y: x > 35.5, only=('tail',))                                         # cream underside of the curl
    g = _outline(g)
    for y in range(26 + o, 34):                   # inner lines: between the legs
        for x in (23, 24):
            if g[y][x]: g[y][x] = 'o'
    eyes = [(18,11,'y'),(19,11,'y'),(20,11,'y'),(27,11,'y'),(28,11,'y'),(29,11,'y')] if BLINK else \
           [(19,10,'w'),(20,10,'y'),(19,11,'y'),(20,11,'y'),(27,10,'w'),(28,10,'y'),(27,11,'y'),(28,11,'y')]
    for (x, y, k) in eyes + [(23,13,'y'),(24,13,'y'),(23,14,'y'),(24,14,'y'),(22,16,'m'),(25,16,'m'),(23,17,'m'),(24,17,'m')]:
        g[y + o][x] = k
    for x in range(17, 31):                       # collar + tag
        if g[18 + o][x] and g[18 + o][x] != 'o': g[18 + o][x] = 'r'
        if g[19 + o][x] and g[19 + o][x] != 'o': g[19 + o][x] = 'q'
    g[20 + o][23] = g[20 + o][24] = g[21 + o][23] = g[21 + o][24] = 't'
    return g

BACK_FLAG = [(31,30),(32,30),(32,29),(33,29),(33,28),(34,28),(34,27),(35,27),(35,26),(36,26),(35,25),(36,25),(36,24),(37,24),(36,23),(37,23),(37,22),(38,22),(37,21),(38,21),(37,20),(38,20)]

def back_sit(wag=0):
    """Sitting with its back to the viewer: no face, collar from behind, the breed's own tail and markings."""
    P = breed(); m = P['marks']
    o = round(max(0, 8 - P['leg']) * .6)
    g, sh, zones, ell, rect, put = _canvas()
    rect('pawL', 15, 32, 19, 33); rect('pawR', 29, 32, 33, 33)          # front paws peeking out either side
    ell('hipL', 17.5, 29, 6.2, 4.8); ell('hipR', 30.5, 29, 6.2, 4.8)
    ell('body', 24, 23.5 + o, 8, 9 - o / 2)
    ell('head', 24, 10.5 + o, 7.6, 6.4)
    if EARS == 'floppy': ell('earL', 16, 13 + o, 3, 6.2, 'a'); ell('earR', 32, 13 + o, 3, 6.2, 'a')
    else: upright_ears(lambda x, y, sid, k: (put(x, y, sid, k), zones.setdefault(sid, (24, 4 + o, 8, 4))), 6 + o)
    t = P['tail']
    sw = lambda y: round(wag * max(0, 27 - y) / 7 * 2.5)   # wag: the upper tail swings side to side
    if t == 'curl':      # curled up over the back, to the right
        cx, cy = 30 + 1.5 * wag, 17 + o
        for y in range(H):
            for x in range(W):
                d = ((x + .5 - cx) / 4.2) ** 2 + ((y + .5 - cy) / 3.6) ** 2
                if .35 < d <= 1: put(x, y, 'tail')
        zones['tail'] = (cx, cy, 4, 3.5)
    elif t == 'plume':   # a big plume over the right hip
        ell('tail', 34 + wag, 21 + o, 3.6, 6); ell('tail', 36 + 2 * wag, 15 + o, 3.2, 3.2)
    else:                # the flag/brush/thin tail, up from the base and curling to the right
        for (x, y) in BACK_FLAG:
            x += sw(y); put(x, y, 'tail')
            if t == 'brush': put(x + 1, y, 'tail')
        zones['tail'] = (27, 26, 3, 5)
    _shade(g, sh, zones, m == 'beagle')
    def paint(test, light, dark, only):
        for y in range(H):
            for x in range(W):
                if g[y][x] and g[y][x] in 'bsld' and sh[y][x] in only and test(x+.5, y+.5): g[y][x] = dark if g[y][x] in 'sd' else light
    if m == 'beagle': paint(lambda x, y: ((x-24)/6)**2 + ((y-22-o)/6.5)**2 <= 1, 'f', 'e', ('body',))     # the beagle saddle
    if m in ('beagle', 'collie'): paint(lambda x, y: y < 22.5, 'c', 'k', ('tail',))                       # white tip
    if m in ('beagle', 'collie', 'shiba'): paint(lambda x, y: True, 'c', 'k', ('pawL', 'pawR'))
    if m == 'collie': paint(lambda x, y: y < 18 + o, 'c', 'k', ('body',))                                 # the white ruff
    g = _outline(g)
    for x in range(18, 31):                       # collar seen from behind
        if g[16 + o][x] and g[16 + o][x] != 'o': g[16 + o][x] = 'r'
        if g[17 + o][x] and g[17 + o][x] != 'o': g[17 + o][x] = 'q'
    return g

if __name__ == '__main__':
    o = sys.argv[1]; sys.path.insert(0, o); import compose as hd2
    hd2.HEX.update(json.load(open(o + '/palette.json')))
    hd2.png(o + '/front.png', [[('pudding', hd2.compose('pudding', 'sit')), ('pudding', front_sit())]], scale=8)
    print('ok')
