# Notte 3 — convertitore dei modelli esterni dei mezzi (vedi assets/models/LICENZA.txt e SPEC3D.md, "Modelli esterni").
# Uso (Python 3 con numpy, FUORI dal progetto i file scaricati):
#   python -I tools/modelli/convert.py tools/modelli <cartella dei .glb scaricati> <cartella di uscita> <cartella anteprime> [nomi...]
# La cartella dei download ha una sottocartella per modello: <src>/<src>.glb (nomi in CFG qui sotto: q_tank1..3 = i tre
# "Tank" di Quaternius su poly.pizza, z_heli = "Helicopter" di Zsky, j_jet = "Jet" di jeremy). L'uscita va copiata in
# assets/models/ e poi importata con `node tools/godot_run.js --timeout=300 -- --headless --path . --import`.
# Le anteprime PNG (parti e ruoli colorati) servono a controllare assi, parti e perni senza aprire Godot.
# Converte i modelli scaricati nel contratto UnitModels: Y su, avanti -Z, origine a terra, nodi Body/Turret/Barrel/Muzzle/Rotor,
# superfici per ruolo (paint, metal, track, glass, rubber, faction) con colore di vertice = moltiplicatore di luminosità.
import sys, numpy as np
sys.path.insert(0, sys.argv[1]); import glbkit as g
DL, OUT, PREV = sys.argv[2], sys.argv[3], sys.argv[4]
only = sys.argv[5:] 

PARTCOL = {'Body': (0.55, 0.6, 0.45), 'Turret': (0.8, 0.55, 0.3), 'Barrel': (0.85, 0.3, 0.3), 'Rotor': (0.3, 0.6, 0.9), 'TailRotor': (0.9, 0.3, 0.8)}
ROLECOL = {'paint': (0.45, 0.5, 0.35), 'metal': (0.25, 0.25, 0.28), 'track': (0.15, 0.14, 0.12), 'glass': (0.2, 0.5, 0.7), 'rubber': (0.1, 0.1, 0.1), 'faction': (0.9, 0.2, 0.2), 'matte': (0.5, 0.45, 0.35)}

def quat_tank(pc):
    n = pc['node']
    return 'Turret' if n == 'Tank_Turret' else ('Barrel' if n == 'Tank_Gun' else 'Body')

def quat_role(pc):
    n, m = pc['node'], pc['mat']
    if n.startswith('TrackMesh'): return ('track', 1.0)
    if n == 'Tank_Gun': return ('paint', 0.8)
    return {'Main': ('paint', 1.0), 'Main_Dark': ('paint', 0.74), 'Main_Light': ('paint', 1.16), 'Main_Details': ('metal', 1.0), 'Wheels': ('paint', 0.8)}.get(m, ('paint', 1.0))

def zheli_part(pc):
    lo, hi = g.bbox(pc)   # coordinate sorgente (prima della scala): rotore = pale grigie e mozzo sopra y 3.4
    if pc['mat'] == 'Gray_Aircraft' and lo[1] > 5.0: return 'Rotor'
    if pc['mat'] == 'Black_Aircraft' and lo[1] > 3.4 and abs(lo[0] + hi[0]) < 0.5: return 'Rotor'
    return 'Body'

def zheli_role(pc):
    lo, hi = g.bbox(pc)
    m = pc['mat']
    if m == 'Orange_Airplane': return ('faction', 1.0) if hi[1] - lo[1] < 0.3 else ('metal', 0.9)   # piani di coda = colore fazione; razziere
    return {'DarkGreen': ('paint', 1.0), 'DarkYellow_Aircraft': ('paint', 1.14), 'Windows_Aircraft': ('glass', 1.0), 'Black_Aircraft': ('metal', 0.55),
            'Gray_Aircraft': ('metal', 1.0), 'Red_Airplane': ('faction', 1.0)}.get(m, ('paint', 1.0))

def jet_role(pc):
    return {'455A64': ('paint', 1.0), '78909C': ('paint', 1.18), '1A1A1A': ('metal', 0.5), '80DEEA': ('glass', 1.0)}.get(pc['mat'], ('paint', 1.0))

def zlight_part(pc):
    # semovente a casamatta di Zsky usato come contraerea: la casamatta gira (Turret), le due canne si alzano (Barrel)
    lo, hi = g.bbox(pc)
    m = pc['mat']
    if m == 'Yellow_LightTank' and lo[1] > 0.25 and hi[1] > 1.2 and hi[0] - lo[0] > 1.5: return 'Turret'
    if abs(lo[0]) < 0.15 and abs(hi[0]) < 0.15 and lo[1] > 0.7 and hi[2] > 0.8 and m in ('Yellow_LightTank', 'Black_LightTank'): return 'Barrel'
    return 'Body'

def zlight_role(pc):
    lo, hi = g.bbox(pc)
    m = pc['mat']
    if m == 'Yellow_LightTank':
        return ('paint', 0.8) if abs(lo[0]) > 0.6 and hi[0] - lo[0] < 0.3 else ('paint', 1.0)   # ruote più scure
    return {'Green_LightTank': ('paint', 0.78), 'Black_LightTank': ('metal', 0.55), 'Gray_LightTank': ('track', 1.0), 'GasTank_LightTank': ('metal', 0.9)}.get(m, ('paint', 1.0))

CFG = {
  # nome uscita: sorgente, imbardata (gradi attorno a Y per portare l'avanti su -Z), scala, allungamento lungo Z, parti, ruoli
  'tank':    dict(src='q_tank3', yaw=-90, s=0.46, sx=0.8, part=quat_tank, role=quat_role),
  'tank_f0': dict(src='q_tank1', yaw=-90, s=0.46, sx=0.8, part=quat_tank, role=quat_role),
  'tank_f3': dict(src='q_tank2', yaw=-90, s=0.46, sx=0.8, part=quat_tank, role=quat_role),
  'aa':      dict(src='z_light', yaw=180, s=1.4, split=True, part=zlight_part, role=zlight_role, turret_pivot=lambda lo, hi: np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2]), barrel_y=0.5),
  'heli':    dict(src='z_heli', yaw=180, s=0.31, split=True, part=zheli_part, role=zheli_role, center='Rotor', nose='Muzzle'),
  'jet':     dict(src='j_jet', yaw=180, s=1.4, part=lambda pc: 'Body', role=jet_role, nose='Muzzle'),
}

def run(name, c):
    pcs = g.pieces('%s/%s/%s.glb' % (DL, c['src'], c['src']))
    if c.get('split'):
        pcs = [q for pc in pcs for q in g.split_components(pc)]
    for pc in pcs:
        pc['part'] = c['part'](pc)
        pc['role'], pc['mult'] = c['role'](pc)
    M = np.diag([c.get('sx', 1.0), 1.0, c.get('sz', 1.0)]) @ g.rot_y(c['yaw'])
    g.transform(pcs, M, s=c['s'])
    # origine: centro in pianta dello scafo, terra a y = 0
    body = [pc for pc in pcs if pc['part'] == c.get('center', 'Body')]
    lo = np.min([g.bbox(pc)[0] for pc in body], 0); hi = np.max([g.bbox(pc)[1] for pc in body], 0)
    alo = np.min([g.bbox(pc)[0] for pc in pcs], 0)
    t = np.array([-(lo[0] + hi[0]) / 2, -alo[1] + c.get('lift', 0.0), -(lo[2] + hi[2]) / 2])
    g.transform(pcs, np.eye(3), t=t)
    parts = {}; tree = {}
    def surf(lst):
        d = {}
        for pc in lst:
            used = np.unique(pc['T']); remap = -np.ones(len(pc['P']), dtype=np.int64); remap[used] = np.arange(len(used))
            d.setdefault(pc['role'], []).append((pc['P'][used], pc['N'][used], np.full(len(used), pc['mult']), remap[pc['T']]))
        out = {}
        for r, L in d.items():
            off = 0; Ps = []; Ns = []; Cs = []; Ts = []
            for P, N, C, T in L:
                Ps.append(P); Ns.append(N); Cs.append(C); Ts.append(T + off); off += len(P)
            out[r] = (np.concatenate(Ps), np.concatenate(Ns), np.concatenate(Cs), np.concatenate(Ts))
        return out
    def box(pn):
        L = [pc for pc in pcs if pc['part'] == pn]
        return np.min([g.bbox(pc)[0] for pc in L], 0), np.max([g.bbox(pc)[1] for pc in L], 0), L
    names = sorted(set(pc['part'] for pc in pcs), key=lambda n: ['Body', 'Turret', 'Barrel', 'Rotor', 'TailRotor'].index(n))
    for pn in names:
        lo, hi, L = box(pn)
        if pn == 'Body':
            o = np.zeros(3)
        elif pn == 'Turret':
            o = c['turret_pivot'](lo, hi) if 'turret_pivot' in c else L[0]['origin'].copy()
            o[1] = lo[1]
        elif pn == 'Barrel':
            o = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2]])    # culatta: estremo posteriore della canna
            if 'barrel_y' in c: o[1] = lo[1] + (hi[1] - lo[1]) * c['barrel_y']
            parts['Muzzle'] = {'origin': np.array([o[0], o[1], lo[2] - 0.03])}
            tree['Muzzle'] = 'Barrel'
        elif pn == 'Rotor':
            o = c['rotor_pivot'](lo, hi) if 'rotor_pivot' in c else np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
        elif pn == 'TailRotor':
            o = (lo + hi) / 2
        parts[pn] = {'origin': o, 'surf': surf(L)}
        tree[pn] = {'Barrel': 'Turret' if 'Turret' in names else None}.get(pn)
        print('  %-9s tris %5d  lo %s hi %s  origine %s' % (pn, sum(len(pc['T']) for pc in L), np.round(lo, 2), np.round(hi, 2), np.round(o, 2)))
    if 'nose' in c:
        lo, hi, L = box('Body')
        parts[c['nose']] = {'origin': np.array([0.0, lo[1] + (hi[1] - lo[1]) * 0.35, lo[2]])}
    order = ['Body', 'Turret', 'Barrel', 'Muzzle', 'Rotor', 'TailRotor']
    parts = {k: parts[k] for k in sorted(parts, key=lambda n: order.index(n) if n in order else 99)}
    g.write_glb('%s/%s.glb' % (OUT, name), parts, tree)
    tris = np.concatenate([pc['P'][pc['T']] for pc in pcs])
    c1 = np.concatenate([np.tile(np.array(PARTCOL[pc['part']]), (len(pc['T']), 1)) for pc in pcs])
    c2 = np.concatenate([np.tile(np.array(ROLECOL[pc['role']]) * min(pc['mult'], 1.3), (len(pc['T']), 1)) for pc in pcs])
    g.preview('%s/%s_parti.png' % (PREV, name), tris, c1)
    g.preview('%s/%s_ruoli.png' % (PREV, name), tris, c2)
    print('  %s: %d triangoli, ingombro %s' % (name, len(tris), np.round(np.ptp(tris.reshape(-1, 3), axis=0), 2)))

for name, c in CFG.items():
    if only and name not in only: continue
    print('==', name, c['src'])
    run(name, c)
