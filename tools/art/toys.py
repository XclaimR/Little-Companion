# Ollie holding each toy: 4 toys x 8 poses, the toy baked into the frame at his mouth (or tossed above his head).
# Frames come back as grids of hex colours.
import json, compose as hd2
HERE = __file__.rsplit('/', 1)[0] or '.'
HEX = json.load(open(HERE + '/palette.json'))
ITEMS = json.load(open(HERE + '/objects_grids.json'))['items']
TOYS = ['ball', 'tennis', 'plush', 'rope']
BREED = 'pudding'
POSES = ['walkA', 'walkB', 'runA', 'runB', 'stand', 'shakeA', 'shakeB', 'toss']

def toy_grid(name):
    it = ITEMS[name]
    return [[None if ch == '.' else HEX[it['keys'][ch]] for ch in row.replace('|', '')] for row in it['rows']]

def frame(toy, pose):
    base = 'shakeA' if pose == 'toss' else pose
    g = hd2.compose(BREED, base)
    A = hd2.LAST_ANCHORS
    out = [[hd2.hexof(BREED, k) if k else None for k in row] for row in g]
    t = toy_grid(toy); th, tw = len(t), len(t[0])
    tip = A['mx'] + A['mrx'] - 1                     # front of the muzzle
    if pose == 'toss':                               # flung up in front of his face (the app adds a little hop)
        left, top = min(48 - tw, int(tip - tw / 2 + 1)), 0
    elif toy in ('ball', 'tennis'):                  # held in the front teeth
        left, top = min(48 - tw, int(tip - tw + 3)), int(A['my'] - 1)
    elif toy == 'plush':                             # carried by the scruff, dangling
        left, top = int(tip - tw / 2 - 1), int(A['my'] + .5)
    else:                                            # rope across the jaw, ends either side
        left, top = int(tip - tw + 5), int(A['my'] + .5)
    for y in range(th):
        for x in range(tw):
            if t[y][x] and 0 <= top + y < 36 and 0 <= left + x < 48: out[top + y][left + x] = t[y][x]
    return out

def all_frames():
    return [frame(toy, pose) for toy in TOYS for pose in POSES]
