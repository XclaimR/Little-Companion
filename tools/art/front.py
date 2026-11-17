# Ollie sitting, facing the viewer (48x36). Shapes + zone shading lit from the top-left + outline.
import json, sys
W, H, FLOOR = 48, 36, 33
def front_sit():
    g = [[None]*W for _ in range(H)]; sh = [[None]*W for _ in range(H)]; zones = {}
    def ell(sid, cx, cy, rx, ry, k='b'):
        zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x+.5-cx)/rx)**2 + ((y+.5-cy)/ry)**2 <= 1: g[y][x] = k; sh[y][x] = sid
    def rect(sid, x0, y0, x1, y1, k='b'):
        zones.setdefault(sid, ((x0+x1+1)/2, (y0+y1+1)/2, (x1-x0+1)/2, (y1-y0+1)/2))
        for y in range(y0, y1+1):
            for x in range(x0, x1+1): g[y][x] = k; sh[y][x] = sid
    # back to front
    ell('tail', 35.5, 21.5, 1.6, 4.2)                       # tail tip peeking up behind the right hip
    ell('hipL', 16.5, 29.5, 6, 4.6); ell('hipR', 31.5, 29.5, 6, 4.6)
    ell('body', 24, 24.5, 7.5, 8.5)
    rect('legL', 19, 25, 22, 31); rect('legR', 25, 25, 28, 31)
    rect('pawL', 18, 32, 22, 33); rect('pawR', 25, 32, 29, 33)
    ell('head', 24, 11, 8.2, 7)
    ell('earL', 15, 13.5, 3.1, 6.6, 'a'); ell('earR', 33, 13.5, 3.1, 6.6, 'a')
    # tones
    for y in range(H):
        for x in range(W):
            sid = sh[y][x]
            if not sid or g[y][x] != 'b': continue
            cx, cy, rx, ry = zones[sid]
            t = (y+.5-cy)/ry*.85 + (x+.5-cx)/rx*.3
            g[y][x] = 'l' if t < -.6 else 'd' if t > .95 else 's' if t > .5 else 'b'
    for y in range(H):   # ear edges darker
        for x in range(W):
            if g[y][x] == 'a' and (x+1 < W and g[y][x+1] not in ('a',) or y+1 < H and g[y+1][x] != 'a'): g[y][x] = 'e'
    def paint(test, light='c', dark='k', only=None):
        for y in range(H):
            for x in range(W):
                if g[y][x] and g[y][x] in 'bsld' and (only is None or sh[y][x] in only) and test(x+.5, y+.5):
                    g[y][x] = dark if g[y][x] in 'sd' else light
    paint(lambda x, y: ((x-24)/4.4)**2 + ((y-14.6)/3.4)**2 <= 1, only=('head',))       # muzzle
    paint(lambda x, y: abs(x-24) < 1.3 and 5 < y < 13, only=('head',))                 # blaze
    paint(lambda x, y: ((x-24)/4.6)**2 + ((y-25)/7)**2 <= 1, only=('body',))           # chest
    paint(lambda x, y: y > 28.5, only=('legL', 'legR', 'pawL', 'pawR'))               # socks
    paint(lambda x, y: y < 20, only=('tail',))                                           # tail tip
    # outline
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and any(0 <= x+dx < W and 0 <= y+dy < H and g[y+dy][x+dx] for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))): out[y][x] = 'o'
    g = out
    # inner lines: between the legs, legs against the chest
    for y in range(26, 34): g[y][23] = 'o' if g[y][23] else g[y][23]; g[y][24] = 'o' if g[y][24] else g[y][24]
    # face
    for (x, y, k) in [(19,10,'w'),(20,10,'y'),(19,11,'y'),(20,11,'y'),(27,10,'w'),(28,10,'y'),(27,11,'y'),(28,11,'y'),
                      (23,13,'y'),(24,13,'y'),(23,14,'y'),(24,14,'y'),(22,16,'m'),(25,16,'m'),(23,17,'m'),(24,17,'m')]:
        g[y][x] = k
    # collar + tag
    for x in range(17, 31):
        if g[18][x] and g[18][x] != 'o': g[18][x] = 'r'
        if g[19][x] and g[19][x] != 'o': g[19][x] = 'q'
    g[20][23] = g[20][24] = g[21][23] = g[21][24] = 't'
    return g
if __name__ == '__main__':
    o = sys.argv[1]; sys.path.insert(0, o); import compose as hd2
    hd2.HEX.update(json.load(open(o + '/palette.json')))
    hd2.png(o + '/front.png', [[('pudding', hd2.compose('pudding', 'sit')), ('pudding', front_sit())]], scale=8)
    print('ok')

def back_sit():
    """Ollie sitting with its back to the viewer: no face, saddle and collar from behind, tail curled up to one side."""
    g = [[None]*W for _ in range(H)]; sh = [[None]*W for _ in range(H)]; zones = {}
    def ell(sid, cx, cy, rx, ry, k='b'):
        zones.setdefault(sid, (cx, cy, rx, ry))
        for y in range(H):
            for x in range(W):
                if ((x+.5-cx)/rx)**2 + ((y+.5-cy)/ry)**2 <= 1: g[y][x] = k; sh[y][x] = sid
    def rect(sid, x0, y0, x1, y1, k='b'):
        zones.setdefault(sid, ((x0+x1+1)/2, (y0+y1+1)/2, (x1-x0+1)/2, (y1-y0+1)/2))
        for y in range(y0, y1+1):
            for x in range(x0, x1+1): g[y][x] = k; sh[y][x] = sid
    rect('pawL', 15, 32, 19, 33); rect('pawR', 29, 32, 33, 33)          # front paws peeking out either side
    ell('hipL', 17.5, 29, 6.2, 4.8); ell('hipR', 30.5, 29, 6.2, 4.8)
    ell('body', 24, 23.5, 8, 9)
    ell('head', 24, 10.5, 7.6, 6.4)
    ell('earL', 16, 13, 3, 6.2, 'a'); ell('earR', 32, 13, 3, 6.2, 'a')
    # tail: up from the base, curling to the right, white tip
    for (x, y) in [(31,30),(32,30),(32,29),(33,29),(33,28),(34,28),(34,27),(35,27),(35,26),(36,26),(35,25),(36,25),(36,24),(37,24),(36,23),(37,23),(37,22),(38,22),(37,21),(38,21),(37,20),(38,20)]:
        g[y][x] = 'b'; sh[y][x] = 'tail'   # curls up past the right hip, thick enough to read
    zones['tail'] = (27, 26, 3, 5)
    for y in range(H):
        for x in range(W):
            sid = sh[y][x]
            if not sid or g[y][x] != 'b': continue
            cx, cy, rx, ry = zones[sid]
            t = (y+.5-cy)/ry*.85 + (x+.5-cx)/rx*.3
            g[y][x] = 'l' if t < -.6 else 'd' if t > .95 else 's' if t > .5 else 'b'
    for y in range(H):
        for x in range(W):
            if g[y][x] == 'a' and (x+1 < W and g[y][x+1] != 'a' or y+1 < H and g[y+1][x] != 'a'): g[y][x] = 'e'
    def paint(test, light, dark, only):
        for y in range(H):
            for x in range(W):
                if g[y][x] and g[y][x] in 'bsld' and sh[y][x] in only and test(x+.5, y+.5): g[y][x] = dark if g[y][x] in 'sd' else light
    paint(lambda x, y: ((x-24)/6)**2 + ((y-22)/6.5)**2 <= 1, 'f', 'e', ('body',))     # the beagle saddle
    paint(lambda x, y: y < 22.5, 'c', 'k', ('tail',))                                 # white tip
    paint(lambda x, y: True, 'c', 'k', ('pawL', 'pawR'))
    out = [r[:] for r in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] is None and any(0 <= x+dx < W and 0 <= y+dy < H and g[y+dy][x+dx] for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))): out[y][x] = 'o'
    g = out
    for x in range(18, 31):                       # collar seen from behind
        if g[16][x] and g[16][x] != 'o': g[16][x] = 'r'
        if g[17][x] and g[17][x] != 'o': g[17][x] = 'q'
    return g
