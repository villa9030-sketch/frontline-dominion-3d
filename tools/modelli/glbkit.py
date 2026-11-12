# Lettura/scrittura GLB minima (numpy) per ripulire i modelli scaricati: cuoce trasformazioni e skin a riposo,
# divide in pezzi (nodo sorgente, materiale, componente connessa) e riscrive un glTF secondo il contratto UnitModels.
import json, struct, zlib
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load_glb(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'glTF'
    l = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + l])
    off = 20 + l
    bl = struct.unpack('<I', d[off:off + 4])[0]
    return j, d[off + 8:off + 8 + bl]


def accessor(j, bin_, i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    n = NC[a['type']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0)
    if stride and stride != dt.itemsize * n:
        out = np.zeros((a['count'], n), dtype=dt)
        for k in range(a['count']):
            out[k] = np.frombuffer(bin_, dtype=dt, count=n, offset=start + k * stride)
    else:
        out = np.frombuffer(bin_, dtype=dt, count=a['count'] * n, offset=start).reshape(a['count'], n).copy()
    if a.get('normalized'):
        out = out.astype(np.float64) / np.iinfo(dt).max
    return out


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_local(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = quat_mat(n.get('rotation', [0, 0, 0, 1])) * np.array(n.get('scale', [1, 1, 1]))[None, :]
    m[:3, 3] = n.get('translation', [0, 0, 0])
    return m


def world_mats(j):
    W = {}

    def rec(i, parent):
        W[i] = parent @ node_local(j['nodes'][i])
        for c in j['nodes'][i].get('children', []) or []:
            rec(c, W[i])
    for s in j['scenes'][j.get('scene', 0)]['nodes']:
        rec(s, np.eye(4))
    return W


def pieces(path):
    """-> lista di dict {node, mat, color, P (n,3), N (n,3), T (m,3)} in spazio mondo del file."""
    j, bin_ = load_glb(path)
    W = world_mats(j)
    out = []
    for ni, n in enumerate(j['nodes']):
        if 'mesh' not in n or ni not in W:
            continue
        skin = j['skins'][n['skin']] if 'skin' in n else None
        if skin:
            ibm = accessor(j, bin_, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
            JM = np.stack([W[jn] @ ibm[k] for k, jn in enumerate(skin['joints'])])
        for pr in j['meshes'][n['mesh']]['primitives']:
            at = pr['attributes']
            P = accessor(j, bin_, at['POSITION']).astype(np.float64)
            Nn = accessor(j, bin_, at['NORMAL']).astype(np.float64) if 'NORMAL' in at else None
            if 'indices' in pr:
                T = accessor(j, bin_, pr['indices']).reshape(-1, 3).astype(np.int64)
            else:
                T = np.arange(len(P)).reshape(-1, 3)
            Ph = np.concatenate([P, np.ones((len(P), 1))], 1)
            if skin:
                Jt = accessor(j, bin_, at['JOINTS_0']).astype(np.int64)
                Wt = accessor(j, bin_, at['WEIGHTS_0']).astype(np.float64)
                Wt = Wt / np.maximum(Wt.sum(1, keepdims=True), 1e-9)
                M = np.einsum('vk,vkij->vij', Wt, JM[Jt])
            else:
                M = np.broadcast_to(W[ni], (len(P), 4, 4))
            Pw = np.einsum('vij,vj->vi', M, Ph)[:, :3]
            if Nn is None:
                Nw = np.zeros_like(Pw)
            else:
                Minv = np.linalg.inv(M[:, :3, :3]).transpose(0, 2, 1)
                Nw = np.einsum('vij,vj->vi', Minv, Nn)
                Nw /= np.maximum(np.linalg.norm(Nw, axis=1, keepdims=True), 1e-12)
            mi = pr.get('material')
            m = j['materials'][mi] if mi is not None else {}
            col = m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3]
            out.append({'node': n.get('name', ''), 'mat': m.get('name', ''), 'color': col, 'P': Pw, 'N': Nw, 'T': T, 'origin': W[ni][:3, 3].copy()})
    return out


def split_components(pc, tol=1e-4):
    """Divide un pezzo in componenti connesse (vertici saldati per posizione)."""
    P, T = pc['P'], pc['T']
    span = max(float(np.ptp(P, axis=0).max()), 1e-9)
    key = np.round(P / (span * tol)).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    parent = np.arange(inv.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for t in inv[T]:
        a, b, c = find(t[0]), find(t[1]), find(t[2])
        parent[b] = a
        parent[c] = a
    roots = np.array([find(a) for a in inv[T[:, 0]]])
    res = []
    for r in np.unique(roots):
        q = dict(pc)
        q['T'] = T[roots == r]
        res.append(q)
    return res


def bbox(pc):
    V = pc['P'][np.unique(pc['T'])]
    return V.min(0), V.max(0)


def transform(pcs, M3, t=(0, 0, 0), s=1.0):
    for pc in pcs:
        pc['P'] = (pc['P'] @ M3.T) * s + np.array(t)
        pc['origin'] = (pc['origin'] @ M3.T) * s + np.array(t)
        Ni = pc['N'] @ np.linalg.inv(M3)
        pc['N'] = Ni / np.maximum(np.linalg.norm(Ni, axis=1, keepdims=True), 1e-12)


def rot_y(deg):
    a = np.radians(deg)
    return np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])


def write_glb(path, parts, tree):
    """parts: {nome: {'origin': (x,y,z) assoluto, 'surf': {ruolo: (P assoluti, N, C grigio, T)}}};
    tree: {nome: genitore | None}; nodi senza superfici = vuoti (Muzzle). Posizioni scritte relative all'origine del nodo."""
    bin_ = bytearray()
    views, accs, meshes, nodes, mats = [], [], [], [], []
    matidx = {}

    def add(arr, target=None, minmax=False):
        nonlocal bin_
        while len(bin_) % 4:
            bin_ += b'\0'
        b = arr.tobytes()
        v = {'buffer': 0, 'byteOffset': len(bin_), 'byteLength': len(b)}
        if target:
            v['target'] = target
        views.append(v)
        bin_ += b
        a = {'bufferView': len(views) - 1, 'componentType': 5126 if arr.dtype == np.float32 else 5125, 'count': int(arr.shape[0]),
             'type': 'SCALAR' if arr.ndim == 1 else ('VEC3' if arr.shape[1] == 3 else 'VEC4')}
        if minmax:
            a['min'] = [float(x) for x in arr.min(0)]
            a['max'] = [float(x) for x in arr.max(0)]
        accs.append(a)
        return len(accs) - 1
    names = list(parts.keys())
    idx = {n: i for i, n in enumerate(names)}
    for n in names:
        p = parts[n]
        o = np.array(p['origin'], dtype=np.float64)
        par = tree.get(n)
        po = np.array(parts[par]['origin'], dtype=np.float64) if par else np.zeros(3)
        node = {'name': n, 'translation': [float(x) for x in (o - po)]}
        prims = []
        for role in sorted(p.get('surf', {}).keys()):
            P, N, C, T = p['surf'][role]
            # salda i vertici identici (posizione, normale, colore)
            key = np.round(np.concatenate([P, N, C[:, None]], 1), 5)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            inv = inv.reshape(-1)
            P2 = (P[first] - o).astype(np.float32)
            N2 = N[first].astype(np.float32)
            C2 = np.concatenate([np.repeat(C[first][:, None], 3, 1), np.ones((len(first), 1))], 1).astype(np.float32)
            T2 = inv[T].astype(np.uint32).reshape(-1)
            if role not in matidx:
                matidx[role] = len(mats)
                mats.append({'name': role, 'pbrMetallicRoughness': {'baseColorFactor': [0.5, 0.5, 0.5, 1], 'metallicFactor': 0.1, 'roughnessFactor': 0.8}})
            prims.append({'attributes': {'POSITION': add(P2, 34962, True), 'NORMAL': add(N2, 34962), 'COLOR_0': add(C2, 34962)},
                          'indices': add(T2, 34963), 'material': matidx[role]})
        if prims:
            meshes.append({'name': n, 'primitives': prims})
            node['mesh'] = len(meshes) - 1
        ch = [idx[c] for c in names if tree.get(c) == n]
        if ch:
            node['children'] = ch
        nodes.append(node)
    roots = [idx[n] for n in names if not tree.get(n)]
    j = {'asset': {'version': '2.0', 'generator': 'frontline3d glbkit'}, 'scene': 0, 'scenes': [{'nodes': roots}], 'nodes': nodes,
         'meshes': meshes, 'materials': mats, 'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(bin_)}]}
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    while len(bin_) % 4:
        bin_ += b'\0'
    total = 12 + 8 + len(js) + 8 + len(bin_)
    with open(path, 'wb') as f:
        f.write(b'glTF' + struct.pack('<II', 2, total))
        f.write(struct.pack('<I', len(js)) + b'JSON' + js)
        f.write(struct.pack('<I', len(bin_)) + b'BIN\0' + bytes(bin_))


def write_png(path, img):
    h, w, _ = img.shape
    raw = b''.join(b'\0' + img[y].astype(np.uint8).tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def render(tris, cols, R, size=360):
    """tris (m,3,3) mondo, cols (m,3) 0..1, R matrice 3x3 di vista (righe: destra, su, verso l'osservatore)."""
    V = tris @ R.T
    lo = V.reshape(-1, 3).min(0)
    hi = V.reshape(-1, 3).max(0)
    sc = (size - 16) / max(hi[0] - lo[0], hi[1] - lo[1], 1e-9)
    img = np.full((size, size, 3), 40.0)
    zb = np.full((size, size), -1e18)
    nrm = np.cross(V[:, 1] - V[:, 0], V[:, 2] - V[:, 0])
    nl = np.linalg.norm(nrm, axis=1)
    L = np.array([0.35, 0.6, 0.72])
    for i in range(len(V)):
        if nl[i] < 1e-12:
            continue
        sh = 0.35 + 0.65 * abs(float(nrm[i] @ L) / nl[i])
        p = V[i].copy()
        px = (p[:, 0] - lo[0]) * sc + 8
        py = size - 1 - ((p[:, 1] - lo[1]) * sc + 8)
        x0, x1 = int(max(np.floor(px.min()), 0)), int(min(np.ceil(px.max()), size - 1))
        y0, y1 = int(max(np.floor(py.min()), 0)), int(min(np.ceil(py.max()), size - 1))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-12:
            continue
        a = ((py[1] - py[2]) * (xs - px[2]) + (px[2] - px[1]) * (ys - py[2])) / d
        b = ((py[2] - py[0]) * (xs - px[2]) + (px[0] - px[2]) * (ys - py[2])) / d
        c = 1 - a - b
        z = a * p[0, 2] + b * p[1, 2] + c * p[2, 2]
        m = (a >= -0.01) & (b >= -0.01) & (c >= -0.01) & (z > zb[y0:y1 + 1, x0:x1 + 1])
        zb[y0:y1 + 1, x0:x1 + 1][m] = z[m]
        img[y0:y1 + 1, x0:x1 + 1][m] = np.clip(cols[i] * sh, 0, 1) * 255
    return img


VIEWS = {
    'lato': np.array([[0, 0, -1.0], [0, 1, 0], [1, 0, 0]]),      # visto da +X (avanti -Z a destra)
    'alto': np.array([[1.0, 0, 0], [0, 0, -1], [0, 1, 0]]),      # dall'alto, avanti (-Z) in su
    'fronte': np.array([[-1.0, 0, 0], [0, 1, 0], [0, 0, -1]]),   # visto da davanti
}


def preview(path, tris, cols, size=360):
    a = np.radians(35)
    e = np.radians(25)
    right = np.array([np.cos(a), 0, np.sin(a)])
    fwd = np.array([-np.sin(a) * np.cos(e), np.sin(e), np.cos(a) * np.cos(e)])   # verso l'osservatore (davanti a destra)
    fwd[2] = -fwd[2]
    right = np.cross(np.array([0, 1.0, 0]), fwd)
    right /= np.linalg.norm(right)
    up = np.cross(fwd, right)
    R34 = np.stack([right, up, fwd])
    ims = [render(tris, cols, VIEWS['lato'], size), render(tris, cols, VIEWS['alto'], size), render(tris, cols, VIEWS['fronte'], size), render(tris, cols, R34, size)]
    write_png(path, np.concatenate(ims, 1))
