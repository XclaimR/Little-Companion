# Ollie's full sheet: the 10 composer poses + a look-back frame, with the studio touch-ups.
import sys, json, struct, zlib, base64
o = sys.argv[1]; sys.path.insert(0, o); import compose as hd2
hd2.HEX.update(json.load(open(o + '/palette.json')))
import front, sleepers, toys
def frame(p):
    if p in sleepers.POSITIONS: return sleepers.POSITIONS[p]()
    if p == 'front': return front.front_sit()
    if p == 'back': return front.back_sit()
    if p == 'look':
        g = hd2.compose('pudding', 'stand')
        region = [row[30:48] for row in g[:18]]
        for y in range(18):
            for i, k in enumerate(region[y][::-1]):
                if k is not None or y < 14: g[y][30 + i] = k
        for y in range(18):                      # collar pixels mirrored onto the far side become ear
            for x in range(40, 48):
                if g[y][x] in ('r', 'q'): g[y][x] = 'a'
        return g
    g = hd2.compose('pudding', p)
    if p == 'sit':
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
W, H = hd2.W, hd2.H
rows = []
for y in range(H):
    r = bytearray(b'\x00')
    for f in frames:
        for x in range(W):
            k = f[y][x]
            if k: hx = k if k.startswith('#') else hd2.HEX[hd2.PAL['pudding'][k]]; r += bytes(int(hx[i:i+2], 16) for i in (1, 3, 5)) + b'\xff'
            else: r += b'\x00\x00\x00\x00'
    rows.append(bytes(r))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W * len(frames), H, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(o + '/ollie11.png', 'wb').write(data); open(o + '/ollie11.b64', 'w').write(base64.b64encode(data).decode())
cols = 11   # preview: equal rows (the png helper sizes the sheet from the first row)
hd2.png(o + '/ollie11_preview.png', [[('pudding', f) for f in frames[r:r + cols]] for r in range(0, len(frames), cols)], scale=3)
print(poses, len(data), 'bytes')
