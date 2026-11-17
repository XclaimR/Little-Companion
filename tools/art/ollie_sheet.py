# A dog's full sheet (python3 ollie_sheet.py tools/art <breed>): composer poses, front/back sits, sleep positions,
# toys, wags, jumps, falls and grooming. Writes tools/art/build/<name>.png.
import sys, json, struct, zlib, base64
o = sys.argv[1]; sys.path.insert(0, o); import compose as hd2
hd2.HEX.update(json.load(open(o + '/palette.json')))
import front, sleepers, toys, os
B = sys.argv[2] if len(sys.argv) > 2 else 'pudding'
NAME = {'pudding': 'ollie'}.get(B, B)
front.EARS = 'floppy' if hd2.BREEDS[B]['ear'] in ('floppy', 'long') else hd2.BREEDS[B]['ear']
toys.BREED = sleepers.BREED = front.BREED = B
def frame(p):
    if p in sleepers.POSITIONS: return sleepers.POSITIONS[p]()
    if p == 'front': return front.front_sit()
    if p == 'back': return front.back_sit()
    if p == 'look':   # glancing back: the body as it stands, the head turned round about its own centre
        hd2.HEAD = 'none'; g = hd2.compose(B, 'stand')
        hd2.HEAD = 'only'; head = hd2.compose(B, 'stand'); hx = hd2.LAST_ANCHORS['hx']
        hd2.HEAD = 'all'
        for y in range(hd2.H):
            for x in range(hd2.W):
                x2 = int(round(2 * hx - x - 1))
                if head[y][x] and 0 <= x2 < hd2.W: g[y][x2] = head[y][x]
        return g
    g = hd2.compose(B, p)
    if p == 'sit' and B == 'pudding':   # studio touch-up on Ollie's sit
        for y in range(13, 20):
            for x in (20, 21): g[y][x] = 'l' if (x == 20 and y < 15) else 'b'
    return g
poses = hd2.POSES + ['look', 'front', 'pawUp', 'shakeA', 'shakeB', 'back', 'sleepT', 'curl', 'side', 'belly', 'curlT', 'sideT', 'bellyT']
frames = [frame(p) for p in poses] + toys.all_frames()   # + 4 toys x 8 poses, baked in
def wag(p, w):
    hd2.WAG = w
    try: return front.front_sit(w) if p == 'front' else front.back_sit(w) if p == 'back' else frame(p)
    finally: hd2.WAG = 0
frames += [wag(p, w) for p in ('stand', 'sit', 'front', 'back', 'walkA', 'walkB', 'look', 'bow') for w in (-1, 1)]   # 55-70: tail wag A/B for each awake pose
frames += [frame(p) for p in ('crouch', 'runJU', 'runJD')]   # 71-73: jump crouch, take-off, coming down
frames += [frame('trip'), sleepers.tumble_roll(), sleepers.tumble_sprawl()]   # 74-76: trip, head over heels, splat
def lick(p):
    g = hd2.compose(B, p)
    a = hd2.LAST_ANCHORS
    x, y = int(a['mx'] + a['mrx'] - 2), int(a['my'] + 2)    # tongue out at the front of the mouth, onto the paw
    for (dx, dy) in ((0, 0), (1, 0), (0, 1)) if p == 'lickA' else ((0, 0), (1, 0), (1, 1), (0, 1)):
        g[y + dy][x + dx] = '#e8798c'
    return g
frames += [lick('lickA'), lick('lickB'), frame('scratchA'), frame('scratchB')]   # 77-80: licking a paw, scratching an ear
def blink(p):
    hd2.BLINK = front.BLINK = True
    try: return front.front_sit() if p == 'front' else frame(p)
    finally: hd2.BLINK = front.BLINK = False
frames += [blink(p) for p in ('stand', 'sit', 'front')]   # 81-83: an idle blink standing, sitting, sitting facing you
W, H = hd2.W, hd2.H
rows = []
for y in range(H):
    r = bytearray(b'\x00')
    for f in frames:
        for x in range(W):
            k = f[y][x]
            if k: hx = k if k.startswith('#') else hd2.hexof(B, k); r += bytes(int(hx[i:i+2], 16) for i in (1, 3, 5)) + b'\xff'
            else: r += b'\x00\x00\x00\x00'
    rows.append(bytes(r))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W * len(frames), H, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
os.makedirs(o + '/build', exist_ok=True); open(o + f'/build/{NAME}.png', 'wb').write(data)
cols = 11   # preview: equal rows (the png helper sizes the sheet from the first row)
hd2.png(o + f'/build/{NAME}_preview.png', [[(B, f) for f in frames[r:r + cols]] for r in range(0, len(frames), cols)], scale=3)
print(poses, len(data), 'bytes')
