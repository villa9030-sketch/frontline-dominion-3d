class_name BattleTerrain
extends Node3D
## Terreno 3D della battaglia: rilievo per tipo, shader a strati (erba/terra/sabbia/neve/roccia), strade, alberi in
## MultiMesh, rocce, edifici, mare. Coerente con gli ostacoli della BattleSim (1 px = 0.25 m, centro campo all'origine).

const S := 0.25
# dimensioni derivate da sim.W/sim.H in configure() (valori iniziali = campo classico 1600×900)
static var CX := 800.0          # centro del campo in px sim
static var CY := 450.0
static var FIELD_HX := 200.0
static var FIELD_HZ := 112.5
static var INNER_HX := 250.0    # zona a passo regolare usata anche per campionare l'altezza
static var INNER_HZ := 165.0
static var STEP := 2.0
static var OUTER := 1500.0
static var MASK_HX := 400.0     # maschera strade/città
static var MASK_HZ := 300.0
static var MASK_RES := 0.5
static var KS := 1.0            # scala lineare del campo rispetto al classico 1600 px

## Ricava tutte le dimensioni della vista dal campo della sim (sim.W × sim.H px).
static func configure(s) -> void:
	var w := float(s.W) if s != null else 1600.0
	var h := float(s.H) if s != null else 900.0
	CX = w * 0.5
	CY = h * 0.5
	FIELD_HX = w * 0.5 * S
	FIELD_HZ = h * 0.5 * S
	KS = maxf(1.0, w / 1600.0)
	INNER_HX = FIELD_HX + 50.0
	INNER_HZ = FIELD_HZ + 52.5
	STEP = 2.0 if KS < 1.5 else 3.0
	OUTER = maxf(8000.0, FIELD_HX + 7400.0)   # paesaggio esteso: la regione attorno al campo arriva all'orizzonte
	MASK_HX = FIELD_HX + 200.0
	MASK_HZ = FIELD_HZ + 187.5
	MASK_RES = 0.5 if KS < 1.5 else 0.75

const TTYPE := {"pianura": 0, "deserto": 1, "urbano": 2, "montagna": 3, "foresta": 4, "artico": 5}
# amp_in, amp_out, freq_out, ridged, rock_slope, snow_line
const PARAMS := {
	"pianura": [1.2, 26.0, 0.0022, false, 0.13, 9999.0],
	"deserto": [2.2, 55.0, 0.0028, false, 0.09, 9999.0],
	"urbano": [0.25, 10.0, 0.002, false, 0.2, 9999.0],
	"montagna": [3.5, 190.0, 0.0024, true, 0.075, 240.0],
	"foresta": [2.0, 40.0, 0.0026, false, 0.13, 9999.0],
	"artico": [1.6, 70.0, 0.0022, true, 0.11, -999.0],
}

var sim: BattleSim
var relief: BattleRelief
var micro_amp := 0.3
var tkey := "pianura"
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var noise3 := FastNoiseLite.new()   # montagne lontane (creste)
var noise4 := FastNoiseLite.new()   # dove stanno le catene montuose
const FAR_AMP := {"pianura": 520.0, "foresta": 460.0, "montagna": 1100.0, "artico": 700.0, "deserto": 150.0, "urbano": 260.0}
var xs := PackedFloat32Array()
var zs := PackedFloat32Array()
var hts := PackedFloat32Array()
var _ix0 := 0          # indice di xs dove inizia la zona regolare
var _iz0 := 0
var _mounds: Array = []   # [X, Z, R, H]
var _mound_cells := {}      # Vector2i(cella) -> [mound]
const MOUND_CELL := 32.0
var _flat_rects: Array = [] # rettangoli mondo da appiattire (edifici)
var outer_roads: Array = [] # polilinee in coordinate mondo (Vector2 X,Z)
var mask_img: Image
var scorch_img: Image
var scorch_tex: ImageTexture
var _scorch_dirty := false
var _scorch_t := 0.0
var terrain_mat: ShaderMaterial
var ground_cols: Array = []
var mesh_inst: MeshInstance3D
var chunks: Array = []         # blocchi della mesh del suolo (MeshInstance3D)
var chunks_lo: Array = []      # copie rade (passo 8 m) dei blocchi della zona fitta, visibili da lontano
var _p: Array
var grass_mms: Array = []      # MultiMesh dell'erba (densità regolabile con la qualità)
var deco_mms: Array = []       # MultiMesh decorativi fuori campo (cespugli, sassi)
var woods: Array = []          # boschi in campo: {c: Vector2 (X,Z), r, h (quota cime), nodes: [MultiMeshInstance3D], fade, want}
var _bld_cells := {}           # Vector2i(cella 8 m) -> [AABB] edifici (occlusione delle barre)
var _bld_max := 0.0
var _field_hmax := -1e9
const BLD_CELL := 8.0
# Fase 7: campi coltivati, siepi, fiumi, punti di riferimento, deformazione del suolo
var field_tex: ImageTexture
var field_xf := Vector4(1.0, 0.0, 2000.0, 0.0)
var field_img: Image
var _field_ca := 1.0
var _field_sa := 0.0
var _field_L := 2000.0
var hedges: Array = []        # [Vector2 a, Vector2 b, kind] mondo (X,Z): 0 siepe, 1 capezzagna (sterrato), 2 staccionata, 3 muretto
var city_boxes: Array = []    # [centro Vector3, dimensioni Vector3, colore] degli edifici (per i dettagli dei tetti)
var field_cells: Array = []   # [x, q0, larghezza, altezza, tipo coltura, tinta] nel riferimento ruotato dei campi (per BattleDecor)
var landmarks: Array = []     # {kind, pos: Vector3, yaw, size: Vector3} (fattorie, case, silos, rovine, ponti...) per FX/distruzione
var bridges: Array = []       # {a: Vector3, b: Vector3, yaw, len, deck: float (quota del piano), rv}
var _lm := {}                 # kind -> [[Transform3D, Color]] (MultiMesh dei punti di riferimento)
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _chunk_meta: Array = []   # [i0, i1, j0, j1] per blocco
var _dirty_chunks := {}
var _overview := -1.0
var _no_trees := false        # --trees=0 (solo misure): nessuna vegetazione in MultiMesh
var _noise_img: Image         # rumore condiviso con lo shader (noise_tex): maschera dei boschi del paesaggio
var far_lakes: Array = []     # laghi del paesaggio lontano: [X, Z, R, quota dell'acqua] (solo vista)
var _glows: Array = []        # luci notturne a terra: [Vector3 pos, raggio, intensità, Color]
var _glow_mat: ShaderMaterial
var _night_mat: ShaderMaterial

static func sim_to_world(x: float, y: float) -> Vector2:
	return Vector2((x - CX) * S, (y - CY) * S)

static func world_to_sim(X: float, Z: float) -> Vector2:
	return Vector2(X / S + CX, Z / S + CY)

func build(s: BattleSim) -> void:
	sim = s
	configure(s)
	tkey = s.tkey
	relief = s.relief
	if relief == null:
		relief = BattleRelief.new(s.tkey, s.seed_, s.W, s.H, s.TOP, s.BOTTOM, s.sea, s.coast_ph, true, [])
	micro_amp = {"pianura": 0.3, "deserto": 0.25, "urbano": 0.08, "montagna": 0.6, "foresta": 0.4, "artico": 0.3}[tkey] if not relief.flat else 0.0
	_p = PARAMS[tkey]
	rng.seed = s.seed_ * 7 + 3
	noise.seed = s.seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.012
	noise2.seed = s.seed_ + 101
	noise3.seed = s.seed_ + 211
	noise3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise3.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise3.fractal_octaves = 5
	noise3.frequency = 0.00042
	noise4.seed = s.seed_ + 307
	noise4.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise4.frequency = 0.00016
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.fractal_type = FastNoiseLite.FRACTAL_RIDGED if _p[3] else FastNoiseLite.FRACTAL_FBM
	noise2.fractal_octaves = 5
	noise2.frequency = _p[2]
	var shot: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Shot") if Engine.get_main_loop() is SceneTree else null
	_no_trees = shot != null and String(shot.call("arg", "trees", "1")) == "0"
	if shot != null:
		var lod_arg := String(shot.call("arg", "lod", ""))
		match lod_arg:
			"hi": LOD_T = 1e9
			"lo": LOD_T = 1.0
			"": pass
			_: LOD_T = float(lod_arg)
	_make_noise()
	_prepare_features()
	_make_far_lakes()
	_build_road_cells()
	_build_mesh()
	_build_masks()
	_build_fields()
	_build_material()
	_build_water()
	_build_rivers()
	_build_vegetation()
	_build_grass()
	_build_rocks()
	if tkey == "urbano":
		_build_city()
	_build_landmarks()
	_build_sites()
	# --decor=0 (solo test/misure): senza i dettagli aggiuntivi di BattleDecor
	if shot == null or String(shot.call("arg", "decor", "1")) != "0":
		BattleDecor.new().build(self)
	if shot == null or String(shot.call("arg", "far", "1")) != "0":
		BattleLandscape.new().build(self)
	# diagnostica (solo demo): --dbg=overdraw|wireframe|lighting|unshaded mostra il costo di disegno
	if shot != null:
		var dbg := String(shot.call("arg", "dbg", ""))
		var modes := {"overdraw": Viewport.DEBUG_DRAW_OVERDRAW, "wireframe": Viewport.DEBUG_DRAW_WIREFRAME,
			"lighting": Viewport.DEBUG_DRAW_LIGHTING, "unshaded": Viewport.DEBUG_DRAW_UNSHADED}
		if modes.has(dbg):
			get_viewport().debug_draw = modes[dbg]

# ---------------------------------------------------------------------------- altezza
func _prepare_features() -> void:
	for o in sim.obs:
		var c := sim_to_world(o["x"], o["y"])
		if o["rect"]:
			_flat_rects.append(Rect2(c, Vector2(o["w"] * S, o["h"] * S)))
		elif o["kind"] == "roccia":
			_mounds.append([c.x, c.y, o["r"] * S * 1.45, o["r"] * S * 0.55])
		elif o["kind"] == "ghiaccio":
			_mounds.append([c.x, c.y, o["r"] * S * 1.5, o["r"] * S * 0.35])
		else:
			_mounds.append([c.x, c.y, float(o.get("R", o.get("r", 20.0))) * S * 1.2, 0.6])
	# griglia dei rilievi (celle di 32 m): l'altezza non scorre tutti gli ostacoli a ogni campione
	for i in _mounds.size():
		var m: Array = _mounds[i]
		var R: float = m[2]
		for cz in range(int(floor((m[1] - R) / MOUND_CELL)), int(floor((m[1] + R) / MOUND_CELL)) + 1):
			for cx in range(int(floor((m[0] - R) / MOUND_CELL)), int(floor((m[0] + R) / MOUND_CELL)) + 1):
				var k := Vector2i(cx, cz)
				if not _mound_cells.has(k):
					_mound_cells[k] = []
				_mound_cells[k].append(m)
	# ponti (Fase 7): spalle come piccoli rilievi alle due estremità, così la strada raccorda col piano del ponte
	for rv in relief.rivers:
		for c in rv["xings"]:
			if String(c["k"]) != "bridge":
				continue
			var d: Vector2 = c["dir"]
			var cw: float = rv["cw"]
			var p0 := Vector2(float(c["x"]), float(c["y"]))
			var pa := p0
			var pb := p0
			for k in 200:
				if BattleRelief.river_dist(rv, pa.x, pa.y) > cw * 1.45:
					break
				pa -= d * 3.0
			for k in 200:
				if BattleRelief.river_dist(rv, pb.x, pb.y) > cw * 1.45:
					break
				pb += d * 3.0
			var deck := BattleRelief.river_floor(rv, p0.y) + 0.35
			var wa := sim_to_world(pa.x, pa.y)
			var wb := sim_to_world(pb.x, pb.y)
			var dw := (wb - wa).normalized()
			bridges.append({"a": Vector3(wa.x, deck, wa.y), "b": Vector3(wb.x, deck, wb.y), "yaw": atan2(dw.x, dw.y), "len": wa.distance_to(wb), "deck": deck, "rv": rv})
			for e in [wa - dw * 3.0, wb + dw * 3.0]:
				_mounds.append([e.x, e.y, 9.0, maxf(0.0, deck - relief.h(pa.x, pa.y) + 0.25)])
	# strade prolungate fuori dal campo fino all'orizzonte
	for road in sim.roads:
		var pts := []
		for v in road:
			pts.append(sim_to_world(v.x, v.y))
		if pts.size() >= 2:
			var dir: Vector2 = (pts[0] - pts[1]).normalized()
			var p: Vector2 = pts[0]
			var head := []
			for i in 30:
				dir = dir.rotated((rng.randf() - 0.5) * 0.25)
				p += dir * 22.0
				head.push_front(p)
			dir = (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
			p = pts[pts.size() - 1]
			var tail := []
			for i in 30:
				dir = dir.rotated((rng.randf() - 0.5) * 0.25)
				p += dir * 22.0
				tail.append(p)
			outer_roads.append(head + pts + tail)

func _outside_d(X: float, Z: float) -> float:
	var dx := maxf(0.0, absf(X) - FIELD_HX)
	var dz := maxf(0.0, absf(Z) - FIELD_HZ)
	return sqrt(dx * dx + dz * dz)

func _outside(X: float, Z: float) -> float:
	var dx := maxf(0.0, absf(X) - (FIELD_HX + 8.0))
	var dz := maxf(0.0, absf(Z) - (FIELD_HZ + 8.0))
	return smoothstep(0.0, 260.0, sqrt(dx * dx + dz * dz))

func coast_x(Z: float) -> float:
	return (sim.coast(Z / S + CY) - CX) * S

func _h_raw(X: float, Z: float) -> float:
	# Fase 7: il rilievo vero (colline, creste, fiumi, mesas, lago...) viene da BattleRelief, condiviso con la sim
	# (linee di vista); qui si aggiungono solo dettagli della vista: micro-ondulazioni, rilievi fuori campo, cumuli degli ostacoli.
	var x := X / S + CX
	var y := Z / S + CY
	var o := _outside(X, Z)
	var amp_out: float = _p[1]
	var h := relief._pre(x, y) + noise.get_noise_2d(X, Z) * micro_amp
	if o > 0.0:
		var n2 := noise2.get_noise_2d(X, Z) * 0.5 + 0.5
		if _p[3]:
			n2 = pow(n2, 1.6)
		var rvk := 1.0
		for rv in relief.rivers:
			if x > float(rv["bx0"]) and x < float(rv["bx1"]):
				rvk = minf(rvk, smoothstep(float(rv["cw"]) * 1.5, float(rv["vw"]), BattleRelief.river_dist(rv, x, y)))
		# valli e passi: il rilievo attorno al campo non è un muro uniforme (prima sembrava una conca rettangolare)
		var gap := lerpf(0.2, 1.0, smoothstep(0.32, 0.68, noise4.get_noise_2d(X * 3.0, Z * 3.0) * 0.5 + 0.5))
		h += (n2 * amp_out * o * o * gap + o * amp_out * 0.08) * rvk
	# rilievi degli ostacoli (rocce, ghiaccio, boschi)
	if absf(X) < FIELD_HX + 20 and absf(Z) < FIELD_HZ + 20:
		var mk := Vector2i(int(floor(X / MOUND_CELL)), int(floor(Z / MOUND_CELL)))
		for m in _mound_cells.get(mk, []):
			var dx: float = X - m[0]
			var dz: float = Z - m[1]
			var R: float = m[2]
			var d2 := dx * dx + dz * dz
			if d2 < R * R:
				var t := 1.0 - d2 / (R * R)
				h += t * t * m[3]
	if o > 0.0:
		var fk := 1.0
		for rv in relief.rivers:
			if x > float(rv["bx0"]) and x < float(rv["bx1"]):
				fk = minf(fk, smoothstep(float(rv["cw"]) * 1.5, float(rv["vw"]) * 1.6, BattleRelief.river_dist(rv, x, y)))
		h += _far_term(X, Z) * fk
		# laghi lontani: conca con l'acqua un po' sotto il piano (la quota è decisa quando il lago viene scelto)
		for L in far_lakes:
			var dxl: float = X - L[0]
			var dzl: float = Z - L[1]
			var dl := sqrt(dxl * dxl + dzl * dzl) / float(L[2])
			if dl < 1.25:
				var floor_h: float = float(L[3]) - 1.2 - 5.0 * (1.0 - dl * dl)
				h = lerpf(h, minf(h, floor_h), 1.0 - smoothstep(0.85, 1.25, dl))
	if sim.sea:
		h = relief.shore(h, x, y)
	return h

## Laghi del paesaggio lontano: 1-3 conche in zone dolci a 700-2600 m dal campo (prima della mesh: il rilievo li accoglie).
func _make_far_lakes() -> void:
	var want: int = {"pianura": 3, "foresta": 3, "montagna": 2, "artico": 2, "deserto": 0, "urbano": 1}.get(tkey, 0)
	var tries := 0
	while far_lakes.size() < want and tries < 120:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(700.0, 2600.0)
		var X := cos(a) * (FIELD_HX + d)
		var Z := sin(a) * (FIELD_HZ + d) * 0.85
		if sim.sea and X < coast_x(Z) + 700.0:
			continue
		var R := rng.randf_range(110.0, 260.0)
		var ok := true
		for L in far_lakes:
			if Vector2(X, Z).distance_to(Vector2(L[0], L[1])) < R + float(L[2]) + 500.0:
				ok = false
		if not ok:
			continue
		# zona dolce: quote simili attorno
		var h0 := _h_raw(X, Z)
		var hmax := h0
		var hmin := h0
		for k in 8:
			var q := Vector2(X, Z) + Vector2.RIGHT.rotated(TAU * k / 8.0) * R * 0.9
			var hq := _h_raw(q.x, q.y)
			hmax = maxf(hmax, hq)
			hmin = minf(hmin, hq)
		if hmax - hmin > R * 0.12 or hmin < 1.0:
			continue
		far_lakes.append([X, Z, R, hmin])

func in_far_lake(p: Vector2, margin := 0.0) -> bool:
	for L in far_lakes:
		if p.distance_to(Vector2(L[0], L[1])) < float(L[2]) * 1.25 + margin:
			return true
	return false

## Rilievo del paesaggio lontano (solo vista): colline e catene montuose che crescono allontanandosi dal campo.
func _far_term(X: float, Z: float) -> float:
	var dx := maxf(0.0, absf(X) - FIELD_HX)
	var dz := maxf(0.0, absf(Z) - FIELD_HZ)
	var d := sqrt(dx * dx + dz * dz)
	if d < 450.0:
		return 0.0
	if sim.sea and X < coast_x(Z) + 500.0:
		return 0.0
	var k := smoothstep(450.0, 2800.0, d)
	var where := noise4.get_noise_2d(X, Z) * 0.5 + 0.5 + k * 0.18
	var ridge := noise3.get_noise_2d(X, Z) * 0.5 + 0.5
	ridge = pow(clampf(ridge, 0.0, 1.0), 1.8)
	if tkey == "deserto":
		# altipiani: cime tagliate piatte (mesa), pareti ripide
		ridge = minf(ridge, 0.34) / 0.34
		ridge = smoothstep(0.0, 0.7, ridge)
	var mount := ridge * float(FAR_AMP.get(tkey, 400.0)) * smoothstep(0.42, 0.72, where)
	var hills := (noise2.get_noise_2d(X * 0.3, Z * 0.3) * 0.5 + 0.5) * 70.0
	return (mount + hills) * k

## Altezza del suolo (m) nel punto mondo X,Z (interpolazione bilineare nella zona regolare).
func height(X: float, Z: float) -> float:
	if absf(X) < INNER_HX - STEP and absf(Z) < INNER_HZ - STEP:
		var fx := (X + INNER_HX) / STEP
		var fz := (Z + INNER_HZ) / STEP
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var W := xs.size()
		var a := (_iz0 + iz) * W + _ix0 + ix
		var h0 := lerpf(hts[a], hts[a + 1], tx)
		var h1 := lerpf(hts[a + W], hts[a + W + 1], tx)
		return lerpf(h0, h1, tz)
	return _h_raw(X, Z)

func normal(X: float, Z: float) -> Vector3:
	var e := 1.5
	var hx := height(X + e, Z) - height(X - e, Z)
	var hz := height(X, Z + e) - height(X, Z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func height_sim(x: float, y: float) -> float:
	return height((x - CX) * S, (y - CY) * S)

## Intersezione raggio-terreno (marcia + bisezione). Restituisce Vector3(INF...) se manca.
func raycast(from: Vector3, dir: Vector3) -> Vector3:
	var t := 0.0
	var prev := from
	var step := 2.0
	for i in 1200:
		t += step
		var p := from + dir * t
		if p.y <= height(p.x, p.z):
			var a := t - step
			var b := t
			for k in 14:
				var m := (a + b) * 0.5
				var q := from + dir * m
				if q.y <= height(q.x, q.z):
					b = m
				else:
					a = m
			return from + dir * b
		step = minf(8.0, 1.0 + t * 0.01)
		prev = p
		if t > 3000:
			break
	return Vector3(INF, INF, INF)

# ---------------------------------------------------------------------------- mesh
func _axis(inner: float, outer: float) -> Array:
	var pos := []
	var x := inner
	var stp := STEP
	while x < outer:
		stp *= 1.075
		x += stp
		pos.append(x)
	var out := PackedFloat32Array()
	for i in range(pos.size() - 1, -1, -1):
		out.append(-pos[i])
	var i0 := out.size()
	var v := -inner
	while v <= inner + 0.001:
		out.append(v)
		v += STEP
	for p in pos:
		out.append(p)
	return [out, i0]

func _build_mesh() -> void:
	var ax := _axis(INNER_HX, OUTER)
	var az := _axis(INNER_HZ, OUTER * 0.8)
	xs = ax[0]; _ix0 = ax[1]
	zs = az[0]; _iz0 = az[1]
	var W := xs.size()
	var Hn := zs.size()
	hts.resize(W * Hn)
	for j in Hn:
		var Z := zs[j]
		for i in W:
			hts[j * W + i] = _h_raw(xs[i], Z)
	# cavità e creste (occlusione d'ambiente "cotta" nei colori dei vertici): differenza con la quota sfocata a due scale
	var img := Image.create_from_data(W, Hn, false, Image.FORMAT_RF, hts.to_byte_array())
	var b1: Image = img.duplicate()
	b1.resize(maxi(2, W / 7), maxi(2, Hn / 7), Image.INTERPOLATE_BILINEAR)
	b1.resize(W, Hn, Image.INTERPOLATE_BILINEAR)
	var b2: Image = img.duplicate()
	b2.resize(maxi(2, W / 28), maxi(2, Hn / 28), Image.INTERPOLATE_BILINEAR)
	b2.resize(W, Hn, Image.INTERPOLATE_BILINEAR)
	var f1 := b1.get_data().to_float32_array()
	var f2 := b2.get_data().to_float32_array()
	var verts := _verts
	var norms := _norms
	var cols := _cols
	verts.resize(W * Hn)
	norms.resize(W * Hn)
	cols.resize(W * Hn)
	var wet_rivers := relief.rivers
	for j in Hn:
		var Z := zs[j]
		var y := Z / S + CY
		for i in W:
			var k := j * W + i
			var X := xs[i]
			var hh := hts[k]
			verts[k] = Vector3(X, hh, Z)
			var c1 := f1[k] - hh
			var c2 := f2[k] - hh
			var ao := clampf(1.0 - maxf(0.0, c1) * 0.075 - maxf(0.0, c2) * 0.022, 0.45, 1.0)
			var ridge := clampf(0.5 - c1 * 0.06 - c2 * 0.012, 0.0, 1.0)
			var wet := 0.0
			var ice := 0.0
			var x := X / S + CX
			for rv in wet_rivers:
				if x > rv["bx0"] and x < rv["bx1"]:
					var dp := BattleRelief.river_dist(rv, x, y)
					wet = maxf(wet, 1.0 - smoothstep(float(rv["cw"]) * 0.95, float(rv["cw"]) * 1.9, dp))
			if relief.lake != null:
				var L: Dictionary = relief.lake
				var ex := (x - float(L["x"])) / float(L["rx"])
				var ey := (y - float(L["y"])) / float(L["ry"])
				ice = 1.0 - smoothstep(0.93, 1.03, sqrt(ex * ex + ey * ey))
			cols[k] = Color(ao, ridge, wet, ice)
	for j in Hn:
		var j0 := maxi(0, j - 1)
		var j1 := mini(Hn - 1, j + 1)
		for i in W:
			var i0 := maxi(0, i - 1)
			var i1 := mini(W - 1, i + 1)
			var dhx := (hts[j * W + i1] - hts[j * W + i0]) / (xs[i1] - xs[i0])
			var dhz := (hts[j1 * W + i] - hts[j0 * W + i]) / (zs[j1] - zs[j0])
			norms[j * W + i] = Vector3(-dhx, 1.0, -dhz).normalized()
	# a blocchi (culling per riquadro): ~110 × 90 vertici per blocco. La zona fitta (passo 2-12 m: campo + fascia attorno)
	# ha due livelli di dettaglio: da oltre LOD_D m la mesh a passo 2 m (triangoli di 1-2 px: lo shader del suolo
	# girava 3-4 volte per pixel) lascia il posto a una copia a passo 8 m con "gonna" sui bordi (niente fessure).
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tkey == "montagna" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var nin_x := int(roundf(2.0 * INNER_HX / STEP))
	var nin_z := int(roundf(2.0 * INNER_HZ / STEP))
	var dx0 := maxi(0, _ix0 - 24)
	var dx1 := mini(W - 1, _ix0 + nin_x + 24)
	var dz0 := maxi(0, _iz0 - 24)
	var dz1 := mini(Hn - 1, _iz0 + nin_z + 24)
	var cuts_x := _cuts(W, dx0, dx1, 110)
	var cuts_z := _cuts(Hn, dz0, dz1, 90)
	for zi in cuts_z.size() - 1:
		var j0: int = cuts_z[zi]
		var j1: int = cuts_z[zi + 1]
		for xi in cuts_x.size() - 1:
			var i0: int = cuts_x[xi]
			var i1: int = cuts_x[xi + 1]
			var mi := _chunk(i0, i1, j0, j1, W, verts, norms, cols)
			mi.cast_shadow = shadow
			if i0 >= dx0 and i1 <= dx1 and j0 >= dz0 and j1 <= dz1:
				mi.visibility_range_end = LOD_D
				var lo := MeshInstance3D.new()
				lo.name = "GroundLo"
				lo.mesh = _chunk_mesh(i0, i1, j0, j1, W, verts, norms, cols, 4, 9.0)
				lo.cast_shadow = shadow
				lo.visibility_range_begin = LOD_D
				add_child(lo)
				chunks_lo.append(lo)
			add_child(mi)
			chunks.append(mi)
			_chunk_meta.append([i0, i1, j0, j1])
	mesh_inst = chunks[0]

const LOD_D := 760.0   # distanza (m, dal centro del blocco) oltre la quale il suolo passa alla mesh rada

## Tagli dei blocchi lungo un asse: [0, d0, ..., d1, n-1] con tratti non più lunghi di maxw.
func _cuts(n: int, d0: int, d1: int, maxw: int) -> Array:
	var out := []
	var pts := [0]
	if d0 > 0:
		pts.append(d0)
	if d1 < n - 1 and d1 > d0:
		pts.append(d1)
	pts.append(n - 1)
	for k in pts.size() - 1:
		var a: int = pts[k]
		var b: int = pts[k + 1]
		if b <= a:
			continue
		var parts := int(ceil(float(b - a) / maxw))
		for s in parts:
			out.append(a + (b - a) * s / parts)
	out.append(n - 1)
	return out

func _chunk(i0: int, i1: int, j0: int, j1: int, W: int, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = _chunk_mesh(i0, i1, j0, j1, W, verts, norms, cols)
	return mi

## Mesh di un blocco [i0..i1] × [j0..j1]; `stride` > 1 = sottocampionata (gli indici estremi restano: i bordi coincidono
## con i blocchi vicini), `skirt` > 0 = bordo prolungato verso il basso di tanti metri (copre le fessure fra livelli).
func _chunk_mesh(i0: int, i1: int, j0: int, j1: int, W: int, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, stride := 1, skirt := 0.0) -> ArrayMesh:
	var xi := PackedInt32Array()
	var zj := PackedInt32Array()
	for i in range(i0, i1, stride):
		xi.append(i)
	xi.append(i1)
	for j in range(j0, j1, stride):
		zj.append(j)
	zj.append(j1)
	var nw := xi.size()
	var nh := zj.size()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	v.resize(nw * nh); n.resize(nw * nh); c.resize(nw * nh)
	for j in nh:
		for i in nw:
			var src := zj[j] * W + xi[i]
			var dst := j * nw + i
			v[dst] = verts[src]; n[dst] = norms[src]; c[dst] = cols[src]
	var idx := PackedInt32Array()
	idx.resize((nw - 1) * (nh - 1) * 6)
	var q := 0
	for j in nh - 1:
		for i in nw - 1:
			var a := j * nw + i
			var b := a + 1
			var cc := a + nw
			var d := cc + 1
			idx[q] = a; idx[q + 1] = b; idx[q + 2] = cc
			idx[q + 3] = b; idx[q + 4] = d; idx[q + 5] = cc
			q += 6
	if skirt > 0.0:
		# perimetro: copia dei vertici di bordo abbassata, pareti a doppia faccia
		var ring := PackedInt32Array()
		for i in nw:
			ring.append(i)
		for j in range(1, nh):
			ring.append(j * nw + nw - 1)
		for i in range(nw - 2, -1, -1):
			ring.append((nh - 1) * nw + i)
		for j in range(nh - 2, 0, -1):
			ring.append(j * nw)
		var base := v.size()
		for r in ring:
			var p := v[r]
			p.y -= skirt
			v.append(p); n.append(n[r]); c.append(c[r])
		var m := ring.size()
		for k in m:
			var a := ring[k]
			var b := ring[(k + 1) % m]
			var a2 := base + k
			var b2 := base + (k + 1) % m
			for tri in [[a, b, a2], [b, b2, a2], [a, a2, b], [b, a2, b2]]:
				idx.append(tri[0]); idx.append(tri[1]); idx.append(tri[2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

# ---------------------------------------------------------------------------- maschere
func _mask_rect(x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
	var a := Vector2i(int((x0 + MASK_HX) / MASK_RES), int((z0 + MASK_HZ) / MASK_RES))
	var b := Vector2i(int(ceil((x1 + MASK_HX) / MASK_RES)), int(ceil((z1 + MASK_HZ) / MASK_RES)))
	var r := Rect2i(a, b - a).intersection(Rect2i(0, 0, mask_img.get_width(), mask_img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		mask_img.fill_rect(r, col)

## Strada morbida: distanza dal segmento con bordo sfumato (niente scalini).
func _mask_segment(a: Vector2, b: Vector2, half: float) -> void:
	var pad := half + 1.0
	var x0 := maxi(0, int((minf(a.x, b.x) - pad + MASK_HX) / MASK_RES))
	var x1 := mini(mask_img.get_width() - 1, int((maxf(a.x, b.x) + pad + MASK_HX) / MASK_RES))
	var z0 := maxi(0, int((minf(a.y, b.y) - pad + MASK_HZ) / MASK_RES))
	var z1 := mini(mask_img.get_height() - 1, int((maxf(a.y, b.y) + pad + MASK_HZ) / MASK_RES))
	if x0 > x1 or z0 > z1:
		return
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 1e-6)
	for j in range(z0, z1 + 1):
		var pz := j * MASK_RES - MASK_HZ + MASK_RES * 0.5
		for i in range(x0, x1 + 1):
			var px := i * MASK_RES - MASK_HX + MASK_RES * 0.5
			var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / l2, 0.0, 1.0)
			var dx := a.x + ab.x * t - px
			var dz := a.y + ab.y * t - pz
			var d := sqrt(dx * dx + dz * dz)
			if d >= pad:
				continue
			var v := 1.0 - smoothstep(half - 0.9, half + 0.9, d)
			var old := mask_img.get_pixel(i, j)
			if v > old.r:
				old.r = v
				mask_img.set_pixel(i, j, old)

func _build_masks() -> void:
	var mw := int(MASK_HX * 2 / MASK_RES)
	var mh := int(MASK_HZ * 2 / MASK_RES)
	mask_img = Image.create(mw, mh, false, Image.FORMAT_RGBA8)
	mask_img.fill(Color(0, 0, 0, 0))
	if tkey == "urbano":
		_urban_mask()
	else:
		var half := 2.75  # 22 px di carreggiata
		for road in outer_roads:
			for i in road.size() - 1:
				_mask_segment(road[i], road[i + 1], half)
		# guadi: pista sterrata che scende nell'acqua da entrambe le sponde
		for rv in relief.rivers:
			for c in rv["xings"]:
				if String(c["k"]) == "ford":
					var d: Vector2 = c["dir"]
					var p0 := Vector2(float(c["x"]), float(c["y"]))
					var vw: float = rv["vw"]
					_mask_segment(sim_to_world(p0.x - d.x * vw * 0.7, p0.y - d.y * vw * 0.7), sim_to_world(p0.x + d.x * vw * 0.7, p0.y + d.y * vw * 0.7), 1.8)
	var sw := int(FIELD_HX * 2 / MASK_RES)
	var sh := int(FIELD_HZ * 2 / MASK_RES)
	scorch_img = Image.create(sw, sh, false, Image.FORMAT_L8)
	scorch_img.fill(Color(0, 0, 0))
	scorch_tex = ImageTexture.create_from_image(scorch_img)

## Griglia degli isolati urbani della sim in metri mondo: {st, bw, bh, gx0, gz0 (primo isolato), x0, x1 (estremi in X)}.
## Ricavata da sim.blocks/streets_* così segue qualunque dimensione del campo.
func city_grid() -> Dictionary:
	var st := 34.0
	var bw := 122.0
	var bh := 96.0
	var x0 := 318.0
	var x1 := 1295.0
	var y0 := float(sim.TOP) + 16.0
	if not sim.blocks.is_empty():
		var b0: Dictionary = sim.blocks[0]
		bw = float(b0["w"]); bh = float(b0["h"])
		x0 = 1e9; x1 = -1e9; y0 = 1e9
		for b in sim.blocks:
			x0 = minf(x0, float(b["x"])); x1 = maxf(x1, float(b["x"]) + float(b["w"]))
			y0 = minf(y0, float(b["y"]))
		if sim.streets_x.size() >= 2:
			st = maxf(4.0, float(sim.streets_x[1]) - float(sim.streets_x[0]) - bw)
	return {"st": st * S, "bw": bw * S, "bh": bh * S, "gx0": (x0 - CX) * S, "gz0": (y0 - CY) * S, "x0": (x0 - CX) * S, "x1": (x1 - CX) * S}

func _urban_mask() -> void:
	# sfondo: piazzali in cemento con chiazze (area di schieramento)
	var G := city_grid()
	var st: float = G["st"]
	var bw: float = G["bw"]
	var bh: float = G["bh"]
	# griglia di isolati estesa a tutta la maschera, allineata a quella della sim
	var gx0: float = G["gx0"]
	var gz0: float = G["gz0"]
	var px := bw + st
	var pz := bh + st
	var field_x0: float = G["x0"] - st
	var field_x1: float = G["x1"] + st
	var i0 := int(floor((-MASK_HX - gx0) / px)) - 1
	var i1 := int(ceil((MASK_HX - gx0) / px)) + 1
	var j0 := int(floor((-MASK_HZ - gz0) / pz)) - 1
	var j1 := int(ceil((MASK_HZ - gz0) / pz)) + 1
	# tutto asfalto, poi isolati sopra
	mask_img.fill(Color(1, 0, 0, 0))
	# zone di schieramento dentro il campo (fuori dalla griglia): terreno sterrato/cemento
	_mask_rect(-FIELD_HX - 2, -FIELD_HZ - 30, field_x0 + st * 0.5, FIELD_HZ + 30, Color(0, 0.55, 0, 0))
	_mask_rect(field_x1 - st * 0.5, -FIELD_HZ - 30, FIELD_HX + 2, FIELD_HZ + 30, Color(0, 0.55, 0, 0))
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var x := gx0 + i * px
			var z := gz0 + j * pz
			var cx := x + bw * 0.5
			var cz := z + bh * 0.5
			var in_field := absf(cx) < FIELD_HX and absf(cz) < FIELD_HZ
			if in_field and (cx < field_x0 or cx > field_x1):
				continue
			if sim.sea and cx < coast_x(cz) + 20:
				continue
			# marciapiede
			_mask_rect(x - 1.6, z - 1.6, x + bw + 1.6, z + bh + 1.6, Color(0, 1, 0, 0))
	# parchi dentro il campo
	for blk in sim.blocks:
		var p := sim_to_world(blk["x"], blk["y"])
		if blk["park"]:
			_mask_rect(p.x, p.y, p.x + blk["w"] * S, p.y + blk["h"] * S, Color(0, 0, 1, 0))
	# segnaletica: linee tratteggiate al centro delle strade
	for i in range(i0, i1 + 1):
		var x := gx0 + i * px - st * 0.5
		var z := -MASK_HZ
		while z < MASK_HZ:
			_mask_rect(x - 0.12, z, x + 0.12, z + 3.0, Color(1, 0, 0, 1))
			z += 7.0
	for j in range(j0, j1 + 1):
		var z := gz0 + j * pz - st * 0.5
		var x := -MASK_HX
		while x < MASK_HX:
			_mask_rect(x, z - 0.12, x + 3.0, z + 0.12, Color(1, 0, 0, 1))
			x += 7.0
	# strisce pedonali agli incroci (vicino al campo)
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var x := gx0 + i * px - st * 0.5
			var z := gz0 + j * pz - st * 0.5
			if absf(x) > FIELD_HX + 60 or absf(z) > FIELD_HZ + 68:
				continue
			for k in 5:
				var o := -3.0 + k * 1.5
				_mask_rect(x + o - 0.35, z - st * 0.5 + 0.3, x + o + 0.35, z - st * 0.5 + 2.3, Color(1, 0, 0, 1))
				_mask_rect(x - st * 0.5 + 0.3, z + o - 0.35, x - st * 0.5 + 2.3, z + o + 0.35, Color(1, 0, 0, 1))

## Cratere / bruciatura sul terreno (coordinate sim, raggio in px sim).
func paint_crater(x: float, y: float, r: float) -> void:
	var cx := (x - CX) * S / MASK_RES + scorch_img.get_width() * 0.5
	var cy := (y - CY) * S / MASK_RES + scorch_img.get_height() * 0.5
	var R := r * S / MASK_RES * 1.6
	var w := scorch_img.get_width()
	var h := scorch_img.get_height()
	var ph1 := randf() * TAU
	var ph2 := randf() * TAU
	for j in range(int(cy - R) - 1, int(cy + R) + 2):
		if j < 0 or j >= h:
			continue
		for i in range(int(cx - R) - 1, int(cx + R) + 2):
			if i < 0 or i >= w:
				continue
			var dv := Vector2(i - cx, j - cy)
			var an := dv.angle()
			var d := dv.length() / (R * (1.0 + 0.18 * sin(an * 3.0 + ph1) + 0.1 * sin(an * 7.0 + ph2)))
			if d >= 1.0:
				continue
			var v := (1.0 - d * d) * (0.75 + randf() * 0.25)
			var old := scorch_img.get_pixel(i, j).r
			scorch_img.set_pixel(i, j, Color(maxf(old, v), 0, 0))
	_scorch_dirty = true

func update_scorch(dt: float) -> void:
	_scorch_t -= dt
	if _scorch_dirty and _scorch_t <= 0:
		_scorch_t = 0.25
		_scorch_dirty = false
		scorch_tex.update(scorch_img)

# ---------------------------------------------------------------------------- materiale
const TERRAIN_SHADER := preload("res://scripts/battle/terrain_ground.gdshader")

func _build_material() -> void:
	var T: Dictionary = Data.TERRAINS[tkey]
	var g := Color(String(T["ground"]))
	var g2 := Color(String(T["ground2"]))
	var cols := {
		"pianura": [g.lerp(Color(0.33, 0.42, 0.18), 0.4), g2.lerp(Color(0.42, 0.44, 0.22), 0.35), Color(0.38, 0.31, 0.22), Color(0.42, 0.4, 0.36)],
		"deserto": [g.lerp(Color(0.74, 0.67, 0.5), 0.5), g2.lerp(Color(0.66, 0.59, 0.45), 0.45), Color(0.58, 0.5, 0.38), Color(0.55, 0.46, 0.36)],
		"urbano": [Color(0.36, 0.38, 0.26), Color(0.42, 0.4, 0.3), Color(0.36, 0.32, 0.27), Color(0.45, 0.44, 0.42)],
		"montagna": [Color(0.35, 0.38, 0.24), Color(0.42, 0.4, 0.3), Color(0.4, 0.34, 0.26), Color(0.43, 0.41, 0.39)],
		"foresta": [g.lerp(Color(0.2, 0.32, 0.13), 0.4), g2.lerp(Color(0.3, 0.33, 0.16), 0.3), Color(0.3, 0.24, 0.16), Color(0.38, 0.37, 0.33)],
		"artico": [Color(0.84, 0.88, 0.92), Color(0.74, 0.8, 0.86), Color(0.56, 0.58, 0.6), Color(0.42, 0.44, 0.47)],
	}
	var c: Array = cols[tkey]
	ground_cols = c
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = TERRAIN_SHADER
	terrain_mat.set_shader_parameter("c_ground", c[0])
	terrain_mat.set_shader_parameter("c_ground2", c[1])
	terrain_mat.set_shader_parameter("c_dirt", c[2])
	terrain_mat.set_shader_parameter("c_rock", c[3])
	terrain_mat.set_shader_parameter("c_snow", Color(0.9, 0.93, 0.97))
	terrain_mat.set_shader_parameter("c_sand", Color(0.76, 0.7, 0.55) if tkey == "deserto" else Color(0.78, 0.7, 0.52))
	terrain_mat.set_shader_parameter("c_asphalt", Color(0.2, 0.205, 0.215))
	terrain_mat.set_shader_parameter("c_concrete", Color(0.42, 0.41, 0.39))
	terrain_mat.set_shader_parameter("c_park", Color(0.27, 0.36, 0.17))
	terrain_mat.set_shader_parameter("rock_slope", _p[4])
	terrain_mat.set_shader_parameter("snow_line", _p[5])
	terrain_mat.set_shader_parameter("ttype", TTYPE[tkey])
	terrain_mat.set_shader_parameter("has_sea", sim.sea)
	terrain_mat.set_shader_parameter("river_wet", 1.0 if (relief.rivers.is_empty() or bool(relief.rivers[0]["water"])) else 0.0)
	if field_tex != null:
		terrain_mat.set_shader_parameter("field_tex", field_tex)
		terrain_mat.set_shader_parameter("field_lin", field_tex)
		terrain_mat.set_shader_parameter("field_xf", field_xf)
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.012
	nz.fractal_octaves = 4
	var img: Image = _noise_img.duplicate()
	img.generate_mipmaps()
	terrain_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img))
	var nimg := nz.get_seamless_image(512, 512)
	nimg.bump_map_to_normal_map(6.0)
	nimg.generate_mipmaps()
	terrain_mat.set_shader_parameter("noise_nrm", ImageTexture.create_from_image(nimg))
	var mimg := mask_img.duplicate()
	mimg.generate_mipmaps()
	terrain_mat.set_shader_parameter("mask_tex", ImageTexture.create_from_image(mimg))
	terrain_mat.set_shader_parameter("mask_rect", Vector4(-MASK_HX, -MASK_HZ, MASK_HX * 2, MASK_HZ * 2))
	terrain_mat.set_shader_parameter("scorch_tex", scorch_tex)
	terrain_mat.set_shader_parameter("field_rect", Vector4(-FIELD_HX, -FIELD_HZ, FIELD_HX * 2, FIELD_HZ * 2))
	_bind_photo_textures()
	for ch in chunks + chunks_lo:
		(ch as MeshInstance3D).material_override = terrain_mat

# ---------------------------------------------------------------------------- mare
const WATER_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_always;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 deep : source_color = vec3(0.04, 0.16, 0.22);
uniform vec3 shallow : source_color = vec3(0.12, 0.36, 0.38);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz;
	vec3 n1 = texture(nrm, p / 23.0 + vec2(TIME * 0.012, TIME * 0.007)).rgb;
	vec3 n2 = texture(nrm, p / 9.0 - vec2(TIME * 0.02, -TIME * 0.011)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.9;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	world.xyz /= world.w;
	float depth = clamp(wpos.y - world.y, 0.0, 30.0);
	float t = smoothstep(0.0, 6.0, depth);
	float foam = (1.0 - smoothstep(0.0, 0.7, depth)) * (0.6 + 0.4 * sin(TIME * 1.3 + p.x * 0.4 + p.y * 0.2));
	ALBEDO = mix(shallow, deep, t) + vec3(foam * 0.7);
	ALPHA = clamp(0.45 + t * 0.55 + foam, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
"""

func _build_water() -> void:
	if not sim.sea:
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(OUTER * 2.2, OUTER * 2.2)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = pm
	mi.position = Vector3(0, 0.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var nz := FastNoiseLite.new()
	nz.frequency = 0.03
	var img := nz.get_seamless_image(256, 256)
	img.bump_map_to_normal_map(3.0)
	img.generate_mipmaps()
	m.set_shader_parameter("nrm", ImageTexture.create_from_image(img))
	mi.material_override = m
	add_child(mi)

# ---------------------------------------------------------------------------- erba
func _build_grass() -> void:
	var count: int = {"pianura": 80000, "deserto": 9000, "urbano": 9000, "montagna": 45000, "foresta": 60000, "artico": 0}[tkey]
	count = int(count * clampf(KS * KS * 0.6, 1.0, 2.0))
	if count == 0:
		return
	var dry := tkey == "deserto"
	var mesh := BattleProps.grass_mesh(dry)
	var gn := FastNoiseLite.new()
	gn.seed = sim.seed_ + 5
	gn.frequency = 0.03
	var c0: Color = ground_cols[0]
	var c1: Color = ground_cols[1]
	var dry_c := Color(0.62, 0.55, 0.32)
	var chunks := {}
	var hx := FIELD_HX + 70.0
	var hz := FIELD_HZ + 60.0
	var tries := 0
	var made := 0
	while made < count and tries < count * 3:
		tries += 1
		var X := (rng.randf() * 2 - 1) * hx
		var Z := (rng.randf() * 2 - 1) * hz
		var n := gn.get_noise_2d(X, Z) * 0.5 + 0.5
		if rng.randf() > smoothstep(0.15, 0.55, n) + 0.15:
			continue
		var h := height(X, Z)
		if sim.sea and h < 1.0:
			continue
		if tkey == "urbano":
			var mu := Vector2i(int((X + MASK_HX) / MASK_RES), int((Z + MASK_HZ) / MASK_RES))
			if mu.x < 0 or mu.y < 0 or mu.x >= mask_img.get_width() or mu.y >= mask_img.get_height():
				continue
			if mask_img.get_pixelv(mu).b < 0.5:
				continue
		elif _near_road_world(X, Z) and rng.randf() < 0.85:
			continue
		var nr := normal(X, Z)
		if nr.y < 0.86:
			continue
		var col := c0.lerp(c1, n).lerp(dry_c, smoothstep(0.55, 0.9, gn.get_noise_2d(X * 2.0 + 300, Z * 2.0) * 0.5 + 0.5) * 0.6)
		if dry:
			col = Color(0.72, 0.6, 0.4).lerp(Color(0.55, 0.5, 0.3), n)
		col = col * (0.9 + rng.randf() * 0.25)
		var sc := 0.7 + rng.randf() * 0.7 + n * 0.4
		var key := Vector2i(int(floor(X / 60.0)), int(floor(Z / 60.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([Vector3(X, h - 0.05, Z), sc, rng.randf() * TAU, col])
		made += 1
	for key in chunks:
		var items: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			var it: Array = items[i]
			var sc: float = it[1]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, it[2]).scaled(Vector3(sc, sc, sc)), it[0]))
			mm.set_instance_color(i, it[3])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 125.0
		mi.visibility_range_end_margin = 45.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		grass_mms.append(mm)

# ---------------------------------------------------------------------------- vegetazione
var _road_cells := {}

## Rumore a tasselli (lo stesso di noise_tex nello shader): serve anche alla CPU per la maschera dei boschi.
func _make_noise() -> void:
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.012
	nz.fractal_octaves = 4
	_noise_img = nz.get_seamless_image(512, 512)

func _nz(uv: Vector2) -> float:
	var w := _noise_img.get_width()
	var h := _noise_img.get_height()
	return _noise_img.get_pixel(posmod(int(floor(uv.x * w)), w), posmod(int(floor(uv.y * h)), h)).r

## Maschera dei boschi del paesaggio, 0 aperto .. 1 bosco (stessa formula di forest_mask nello shader): gli alberi 3D
## vicini e le chiome dipinte lontane stanno negli stessi posti.
func forest_at(p: Vector2) -> float:
	if _noise_img == null or tkey == "deserto":
		return 0.0
	var a := _nz(p / 2600.0 + Vector2(0.13, 0.77)) * 0.8 + _nz(p / 700.0 + Vector2(0.51, 0.29)) * 0.2
	var th := 0.69 - 0.4 * float(BattleLandscape.FOREST_AMT.get(tkey, 0.25))
	return smoothstep(th, th + 0.02, a)

func _build_road_cells() -> void:
	for road in outer_roads:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var n := int(ceil(a.distance_to(b) / 2.0))
			for k in n + 1:
				var p := a.lerp(b, float(k) / maxf(1, n))
				var c := Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))
				for oy in range(-2, 3):
					for ox in range(-2, 3):
						_road_cells[c + Vector2i(ox, oy)] = true

func _near_road_world(X: float, Z: float) -> bool:
	return _road_cells.has(Vector2i(int(floor(X / 4.0)), int(floor(Z / 4.0))))

func _in_field(X: float, Z: float, margin: float) -> bool:
	return absf(X) < FIELD_HX + margin and absf(Z) < FIELD_HZ + margin

func _tree_ok(X: float, Z: float, margin := 6.0) -> bool:
	if _in_field(X, Z, margin):
		return false
	var h := height(X, Z)
	if h < 1.2:
		return false
	if tkey == "montagna" and h > 70.0 + rng.randf() * 20.0:
		return false
	var n := normal(X, Z)
	if n.y < 0.8:
		return false
	if _near_road_world(X, Z):
		return false
	return true

func _add_instances(kind: String, list: Array, shadow := true) -> Array:
	var made := []
	if list.is_empty() or _no_trees:
		return made
	# a blocchi per il culling
	var chunks := {}
	for it in list:
		var key := Vector2i(int(floor(it[0].x / 160.0)), int(floor(it[0].z / 160.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(it)
	var mesh: Mesh = BattleProps.tree_mesh(kind)
	var lod: Mesh = BattleProps.tree_lod_mesh(kind)
	for key in chunks:
		var items: Array = chunks[key]
		# due livelli di dettaglio per blocco: modello completo fino a LOD_T, poi l'albero a 20 triangoli
		# (stesse istanze: da lontano ~900 triangoli per albero erano puro costo)
		for lv in (3 if shadow else 2):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh if lv == 0 else lod
			mm.instance_count = items.size()
			for i in items.size():
				var it: Array = items[i]
				var sc: float = it[1]
				var b := Basis(Vector3.UP, it[2]).scaled(Vector3(sc, sc * (0.9 + 0.2 * fposmod(it[2], 1.0)), sc))
				mm.set_instance_transform(i, Transform3D(b, it[0]))
				mm.set_instance_color(i, it[3])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lv == 0:
				mi.visibility_range_end = LOD_T
				mi.set_meta("lod_hi", true)
			elif lv == 1:
				mi.visibility_range_begin = LOD_T
				mi.visibility_range_end = 1400.0
				mi.set_meta("lod_lo", true)
				# gemello del livello vicino: BattleMarks replica abbattimenti e cambi di colore
				(made[made.size() - 1] as Node).set_meta("lod_twin", mm)
			else:
				# ombre: le proietta la sagoma a 20 triangoli (da vicino non si nota, il passaggio d'ombra costa 45 volte meno)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				mi.visibility_range_end = LOD_T
				mi.set_meta("lod_lo", true)
				(made[made.size() - 2] as Node).set_meta("lod_shadow", mm)
			add_child(mi)
			made.append(mi)
			if kind == "bush":
				deco_mms.append(mm)
	return made

var LOD_T := 480.0   # distanza (m, dal centro del blocco) oltre la quale gli alberi passano al modello a 20 triangoli (--lod=hi|lo per confronti)

## Distanza massima di disegno per un gruppo di alberi restituito da _add_instances (solo il livello lontano;
## sotto LOD_T è il livello vicino a fermarsi prima).
func set_tree_range(nodes: Array, end: float, margin := 0.0) -> void:
	for n in nodes:
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		if gi.has_meta("lod_hi"):
			if end < LOD_T:
				gi.visibility_range_end = end
		else:
			if end <= LOD_T:
				gi.visible = false
			else:
				gi.visibility_range_end = end
		if margin > 0.0 and gi.visible:
			gi.visibility_range_end_margin = margin
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _tint() -> Color:
	var v := 0.8 + rng.randf() * 0.4
	return Color(v * (0.95 + rng.randf() * 0.1), v, v * (0.9 + rng.randf() * 0.1))

## `mask_k` > 0: gli alberi seguono la maschera dei boschi del paesaggio (dentro tutti, fuori solo 1 − mask_k):
## masse boscose vere attorno al campo, continue con le chiome dipinte lontane.
func _scatter(kind: String, count: int, smin: float, smax: float, clusters := 0, spread := 40.0, region := 900.0, margin := 6.0, mask_k := 0.0) -> Array:
	var out := []
	var centers := []
	region += FIELD_HX - 200.0
	count = int(count * (1.0 + (KS - 1.0) * 0.5))
	clusters = int(clusters * (1.0 + (KS - 1.0) * 0.5))
	for c in clusters:
		centers.append(Vector2((rng.randf() * 2 - 1) * region, (rng.randf() * 2 - 1) * region * 0.75))
	var tries := 0
	while out.size() < count and tries < count * (12 if mask_k > 0.0 else 6):
		tries += 1
		var X: float
		var Z: float
		if clusters > 0:
			var c: Vector2 = centers[rng.randi() % centers.size()]
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * spread
			X = c.x + cos(a) * r
			Z = c.y + sin(a) * r
		elif mask_k > 0.0:
			# uniforme sulla corona attorno al campo (la maschera decide dove)
			X = (rng.randf() * 2 - 1) * (FIELD_HX + region)
			Z = (rng.randf() * 2 - 1) * (FIELD_HZ + region * 0.75)
			if _in_field(X, Z, margin):
				continue
		else:
			# densità maggiore vicino al campo
			var u := pow(rng.randf(), 1.6)
			var a := rng.randf() * TAU
			X = cos(a) * (FIELD_HX + 10 + u * region)
			Z = sin(a) * (FIELD_HZ + 10 + u * region * 0.75)
		if mask_k > 0.0:
			# fitti vicino al campo, più radi allontanandosi (da lontano bastano le chiome dipinte)
			var fd := _outside_d(X, Z)
			if rng.randf() > lerpf(1.0 - mask_k, 1.0, forest_at(Vector2(X, Z))) / (1.0 + fd / 420.0):
				continue
		if not _tree_ok(X, Z, margin):
			continue
		out.append([Vector3(X, height(X, Z) - 0.2, Z), lerpf(smin, smax, rng.randf()), rng.randf() * TAU, _tint()])
	return out

func _build_vegetation() -> void:
	var pine := []
	var broad := []
	var edge_bush := []
	var edge_tree := []
	# alberi degli ostacoli "bosco" (bloccano le unità nella sim): un gruppo di MultiMesh per bosco, così la vista
	# può renderlo trasparente quando copre le unità; alberi un po' raccolti verso il centro (le unità stanno ai margini)
	for o in sim.obs:
		if o.get("kind", "") != "bosco":
			continue
		var cw := sim_to_world(o["x"], o["y"])
		var wp := []
		var wb := []
		for t in o.get("trees", []):
			var w := sim_to_world(t[0], t[1])
			w = cw + (w - cw) * 0.8
			var sc: float = t[2] * S / 2.0
			var it := [Vector3(w.x, height(w.x, w.y) - 0.2, w.y), sc * (0.9 + rng.randf() * 0.3), rng.randf() * TAU, _tint()]
			if tkey == "foresta" and t[3] < 0.5:
				wp.append(it)
			elif tkey == "artico" or tkey == "deserto":
				wp.append(it)
			else:
				wb.append(it)
		var nodes: Array = []
		if tkey == "artico":
			nodes += _add_instances("snowpine", wp)
		elif tkey == "deserto":
			nodes += _add_instances("palm", wp)   # oasi: palme, non latifoglie
		else:
			nodes += _add_instances("pine", wp)
		nodes += _add_instances("broadleaf", wb)
		var Rm := float(o.get("R", o.get("r", 20.0))) * S
		woods.append({"c": cw, "r": Rm * 0.8 + 3.0, "h": height(cw.x, cw.y) + 15.0, "nodes": nodes, "fade": 0.0, "want": 0.0})
		# margine del bosco: cespugli e alberelli giovani attorno (il limitare si legge anche dall'alto)
		if tkey != "artico":
			var ne := int(Rm / 2.2)
			for k in ne:
				var a := rng.randf() * TAU
				var rr := Rm * (0.86 + rng.randf() * 0.22)
				var pe := cw + Vector2(cos(a), sin(a)) * rr
				if _near_road_world(pe.x, pe.y) or (sim.sea and height(pe.x, pe.y) < 1.0):
					continue
				edge_bush.append([Vector3(pe.x, height(pe.x, pe.y) - 0.15, pe.y), 0.9 + rng.randf() * 0.9, rng.randf() * TAU, _tint()])
				if k % 4 == 0:
					edge_tree.append([Vector3(pe.x, height(pe.x, pe.y) - 0.2, pe.y), 0.45 + rng.randf() * 0.3, rng.randf() * TAU, _tint()])
	match tkey:
		"foresta":
			# masse boscose vere sulla maschera del paesaggio (fitte), più alberi sparsi nelle radure
			pine += _scatter("pine", 15000, 0.8, 1.35, 0, 0, 760, 6.0, 0.92)
			broad += _scatter("broadleaf", 9000, 0.8, 1.3, 0, 0, 760, 6.0, 0.92)
			broad += _scatter("broadleaf", 900, 0.7, 1.2, 0, 0, 760)
			_add_instances("bush", _scatter("bush", 900, 0.8, 1.6, 0, 0, 300, 2.0), false)
		"pianura":
			broad += _scatter("broadleaf", 1600, 0.75, 1.25, 70, 38, 900)
			broad += _scatter("broadleaf", 6000, 0.75, 1.25, 0, 0, 900, 6.0, 0.95)
			pine += _scatter("pine", 2000, 0.8, 1.2, 0, 0, 900, 6.0, 0.95)
			_add_instances("bush", _scatter("bush", 700, 0.8, 1.6, 0, 0, 350, 2.0), false)
		"montagna":
			pine += _scatter("pine", 11000, 0.7, 1.25, 0, 0, 760, 6.0, 0.88)
			_add_instances("bush", _scatter("bush", 400, 0.6, 1.2, 0, 0, 300, 2.0), false)
		"artico":
			# masse scure di conifere sulla neve
			pine += _scatter("snowpine", 8000, 0.7, 1.2, 0, 0, 800, 6.0, 0.95)
		"deserto":
			_add_instances("palm", _scatter("palm", 120, 0.8, 1.2, 6, 25, 700), true)
			_add_instances("dead", _scatter("dead", 140, 0.6, 1.0, 0, 0, 700), true)
		"urbano":
			pass
	if tkey == "artico":
		var sp := _scatter("snowpine", 900, 0.7, 1.2, 25, 60, 800)
		_add_instances("snowpine", sp + pine)
		pine = []
	_add_instances("pine", pine)
	_add_instances("broadleaf", broad)
	_add_instances("broadleaf" if tkey != "montagna" else "pine", edge_tree)
	# cespugli sparsi dentro il campo (solo vista: le unità li attraversano)
	var nb: int = {"pianura": 260, "foresta": 420, "montagna": 300, "deserto": 220, "artico": 0, "urbano": 0}[tkey]
	for i in nb:
		var X := (rng.randf() * 2 - 1) * FIELD_HX
		var Z := (rng.randf() * 2 - 1) * FIELD_HZ
		if _near_road_world(X, Z) or normal(X, Z).y < 0.86:
			continue
		if sim.sea and (height(X, Z) < 1.2 or X < coast_x(Z) + 12.0):
			continue
		var ps := world_to_sim(X, Z)
		if relief.water_at(ps.x, ps.y) > 0.0:
			continue
		edge_bush.append([Vector3(X, height(X, Z) - 0.15, Z), 0.6 + rng.randf() * 0.9, rng.randf() * TAU, _tint()])
	_add_instances("bush" if tkey != "deserto" else "dead", edge_bush, false)

func _build_rocks() -> void:
	var ice := tkey == "artico"
	var variants := []
	for v in 4:
		var tint := Color(0.66, 0.5, 0.36) if tkey == "deserto" else (Color(0.46, 0.44, 0.41) if tkey == "montagna" else Color(0.5, 0.48, 0.44))
		var style: String = {"deserto": "desert", "montagna": "mountain", "artico": "arctic"}.get(tkey, "rock")
		variants.append(BattleProps.rock_mesh(sim.seed_ + v * 13, ice, tint, style))
	var lists := [[], [], [], []]
	for o in sim.obs:
		var kind: String = o.get("kind", "")
		if kind != "roccia" and kind != "ghiaccio":
			continue
		var c := sim_to_world(o["x"], o["y"])
		var R: float = o["r"] * S
		var tall := 1.6 if kind == "ghiaccio" else 1.0
		lists[rng.randi() % 4].append([Vector3(c.x, height(c.x, c.y) - R * 0.25, c.y), Vector3(R * 0.85, R * 0.6 * tall, R * 0.85), rng.randf() * TAU])
		for k in 3 + rng.randi() % 3:
			var a := rng.randf() * TAU
			var d := R * (0.6 + rng.randf() * 0.5)
			var p := c + Vector2(cos(a), sin(a)) * d
			var s := R * (0.25 + rng.randf() * 0.3)
			lists[rng.randi() % 4].append([Vector3(p.x, height(p.x, p.y) - s * 0.2, p.y), Vector3(s, s * 0.7 * tall, s), rng.randf() * TAU])
	# sassi sparsi decorativi (piccoli, anche nel campo) e massi fuori
	var nsmall: int = {"pianura": 120, "deserto": 400, "urbano": 0, "montagna": 500, "foresta": 120, "artico": 260}[tkey]
	nsmall = int(nsmall * minf(KS * KS, 4.0))
	for i in nsmall:
		var X := (rng.randf() * 2 - 1) * (FIELD_HX + 60)
		var Z := (rng.randf() * 2 - 1) * (FIELD_HZ + 50)
		var s := 0.15 + pow(rng.randf(), 3) * 0.6
		if sim.sea and X < coast_x(Z) + 4:
			continue
		lists[i % 4].append([Vector3(X, height(X, Z) - s * 0.25, Z), Vector3(s, s * 0.6, s), rng.randf() * TAU])
	# massi medi sui versanti dentro il campo (solo vista): danno grana ai pendii
	var nmed: int = {"pianura": 40, "deserto": 160, "urbano": 0, "montagna": 260, "foresta": 60, "artico": 120}[tkey]
	for i in nmed * 4:
		if nmed <= 0:
			break
		var X := (rng.randf() * 2 - 1) * (FIELD_HX + 60)
		var Z := (rng.randf() * 2 - 1) * (FIELD_HZ + 50)
		var ny := normal(X, Z).y
		if ny > 0.965 or _near_road_world(X, Z):
			continue
		if sim.sea and (height(X, Z) < 1.2 or X < coast_x(Z) + 6):
			continue
		var ps := world_to_sim(X, Z)
		if relief.water_at(ps.x, ps.y) > 0.0:
			continue
		var s := 0.7 + pow(rng.randf(), 1.5) * 1.8
		lists[i % 4].append([Vector3(X, height(X, Z) - s * 0.3, Z), Vector3(s, s * 0.7, s), rng.randf() * TAU])
		nmed -= 1
	var nbig: int = {"pianura": 60, "deserto": 260, "urbano": 0, "montagna": 700, "foresta": 80, "artico": 300}[tkey]
	nbig = int(nbig * (1.0 + (KS - 1.0) * 0.6))
	for i in nbig:
		var u := pow(rng.randf(), 1.3)
		var a := rng.randf() * TAU
		var X := cos(a) * (FIELD_HX + 15 + u * 700)
		var Z := sin(a) * (FIELD_HZ + 15 + u * 520)
		if _in_field(X, Z, 6) or height(X, Z) < 1.0:
			continue
		var s := 1.0 + pow(rng.randf(), 2) * (7.0 if tkey == "montagna" else 4.0)
		lists[i % 4].append([Vector3(X, height(X, Z) - s * 0.3, Z), Vector3(s, s * 0.7, s), rng.randf() * TAU])
	for v in 4:
		var items: Array = lists[v]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = items.size()
		for i in items.size():
			var it: Array = items[i]
			var b := Basis(Vector3.UP, it[2]).scaled(it[1])
			mm.set_instance_transform(i, Transform3D(b, it[0]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)

# ---------------------------------------------------------------------------- città
const BUILDING_SHADER := """
shader_type spatial;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 inst;
varying vec3 tint;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	inst = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec3 n = normalize(wnrm);
	float base_y = inst.x;
	float top_y = inst.y;
	float style = inst.z;
	float seed = inst.w;
	float nz = texture(noise_tex, wpos.xz / 13.0 + vec2(wpos.y / 17.0)).r;
	vec3 pal[6] = vec3[6](vec3(0.55, 0.53, 0.5), vec3(0.6, 0.5, 0.4), vec3(0.46, 0.45, 0.45), vec3(0.52, 0.4, 0.33), vec3(0.62, 0.6, 0.54), vec3(0.4, 0.42, 0.45));
	vec3 wall = pal[int(seed * 5.99)] * (0.8 + 0.3 * fract(seed * 13.7)) * (0.85 + 0.25 * nz);
	if (style > 0.5 && style < 1.5) { wall = vec3(0.45, 0.5, 0.55) * (0.8 + 0.3 * fract(seed * 7.3)); }
	vec3 col = wall;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	if (n.y > 0.6) {
		col = vec3(0.32, 0.31, 0.3) * (0.8 + 0.35 * nz);
		float edge = 0.0;
		col = mix(col, tint * 0.7, edge);
		rough = 0.95;
	} else if (n.y > -0.5) {
		float u = abs(n.x) > 0.5 ? wpos.z : wpos.x;
		float hy = wpos.y - base_y;
		float floor_h = style > 1.5 ? 3.0 : 3.4;
		float win_w = style > 0.5 && style < 1.5 ? 1.0 : 2.6;
		float cell = style > 0.5 && style < 1.5 ? 1.6 : 3.2;
		float fu = fract(u / cell + seed);
		float fv = fract((hy - 0.6) / floor_h);
		float ground = step(hy, 3.8);
		float win = step(0.18, fu) * step(fu, 0.18 + win_w / cell * 0.82) * step(0.28, fv) * step(fv, 0.82);
		float top_band = step(top_y - 0.8, wpos.y);
		win *= (1.0 - top_band);
		vec2 cid = vec2(floor(u / cell + seed), floor((hy - 0.6) / floor_h));
		float h = hash(cid + seed * 17.0);
		vec3 glass = mix(vec3(0.07, 0.09, 0.11), vec3(0.22, 0.27, 0.3), h * 0.6);
		if (style > 0.5 && style < 1.5) {
			glass = mix(vec3(0.12, 0.18, 0.22), vec3(0.3, 0.38, 0.42), h);
			win = 1.0 - (1.0 - win) * 0.75;
		}
		if (ground > 0.5) {
			float shop = step(0.12, fract(u / 6.0 + seed)) * step(fract(u / 6.0 + seed), 0.88) * step(0.4, hy) * step(hy, 3.2);
			col = mix(wall * 0.55, vec3(0.08, 0.1, 0.12), shop);
			win = 0.0;
			rough = mix(0.85, 0.15, shop);
		}
		col = mix(col, glass, win);
		rough = mix(rough, 0.12, win);
		metal = win * 0.3;
		// marcapiano
		float band = 1.0 - smoothstep(0.0, 0.14, abs(fv - 0.06));
		col = mix(col, col * 0.78, band * (1.0 - win) * (1.0 - ground));
		// sporco alla base
		col *= mix(0.7, 1.0, smoothstep(0.0, 3.0, hy));
	} else {
		col = vec3(0.1);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

func _build_city() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var sh := Shader.new()
	sh.code = BUILDING_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", terrain_mat.get_shader_parameter("noise_tex"))
	box.material = mat
	var items := []   # [center Vector3, size Vector3, color, custom Color]
	var roof_items := []
	var palette := [Color(0.62, 0.6, 0.56), Color(0.66, 0.56, 0.45), Color(0.52, 0.5, 0.5), Color(0.58, 0.45, 0.38), Color(0.7, 0.67, 0.6), Color(0.45, 0.47, 0.5)]
	# edifici della sim (bloccano le unità)
	for o in sim.obs:
		if not o["rect"]:
			continue
		var p := sim_to_world(o["x"], o["y"])
		var w: float = o["w"] * S
		var d: float = o["h"] * S
		var hgt := 7.0 + float(o["shade"] - 0.75) * 34.0 + rng.randf() * 8.0
		var cx := p.x + w * 0.5
		var cz := p.y + d * 0.5
		var gy := minf(minf(height(p.x, p.y), height(p.x + w, p.y + d)), minf(height(p.x + w, p.y), height(p.x, p.y + d))) - 0.5
		var style := 0.0 if rng.randf() < 0.7 else (2.0 if hgt < 12 else 1.0)
		var col: Color = palette[rng.randi() % palette.size()] * float(o["shade"]) * 0.95
		items.append([Vector3(cx, gy + hgt * 0.5, cz), Vector3(w, hgt, d), col, Color(gy, gy + hgt, style, rng.randf())])
		if o.get("ac", false) and w > 5.5 and d > 5.5:
			roof_items.append([Vector3(p.x + w * o["acx"] + 1, gy + hgt + 0.6, p.y + d * o["acy"] + 0.75), Vector3(2.0, 1.2, 1.5)])
			roof_items.append([Vector3(cx, gy + hgt + 0.3, cz), Vector3(w - 0.6, 0.6, d - 0.6) * Vector3(1, 1, 1)])
	# città esterna (solo scena): stessa griglia di isolati
	var G := city_grid()
	var st: float = G["st"]
	var bw: float = G["bw"]
	var bh: float = G["bh"]
	var gx0: float = G["gx0"]
	var gz0: float = G["gz0"]
	var px := bw + st
	var pz := bh + st
	var lim := FIELD_HX + 500.0
	for i in range(int(floor((-lim - gx0) / px)), int(ceil((lim - gx0) / px)) + 1):
		for j in range(int(floor((-lim * 0.8 - gz0) / pz)), int(ceil((lim * 0.8 - gz0) / pz)) + 1):
			var x := gx0 + i * px
			var z := gz0 + j * pz
			var cx := x + bw * 0.5
			var cz := z + bh * 0.5
			if _in_field(cx, cz, 18.0):
				continue
			if sim.sea and cx < coast_x(cz) + 30:
				continue
			var far := clampf((Vector2(cx, cz).length() - 150.0) / 500.0, 0.0, 1.0)
			if rng.randf() < 0.12:
				continue  # piazza / parcheggio
			var n := 1 + rng.randi() % 3
			var horiz := rng.randf() < 0.5
			var L := (bw - 3.0) if horiz else (bh - 3.0)
			var acc := 0.0
			var parts := []
			for k in n:
				var pp := 0.6 + rng.randf()
				parts.append(pp)
				acc += pp
			var off := 0.0
			var gap := 2.0
			var usable := L - gap * (n - 1)
			for k in n:
				var ln: float = usable * parts[k] / acc
				var bx: float
				var bz: float
				var sx: float
				var sz: float
				if horiz:
					bx = x + 1.5 + off; bz = z + 1.5; sx = ln; sz = bh - 3.0
				else:
					bx = x + 1.5; bz = z + 1.5 + off; sx = bw - 3.0; sz = ln
				off += ln + gap
				var hgt := 8.0 + rng.randf() * 18.0 + far * rng.randf() * 70.0
				if rng.randf() < 0.06 + far * 0.12:
					hgt += 40.0 + rng.randf() * 60.0
				var style := 1.0 if hgt > 45 and rng.randf() < 0.7 else (2.0 if hgt < 12 else 0.0)
				var gy := height(bx + sx * 0.5, bz + sz * 0.5) - 1.0
				var col: Color = palette[rng.randi() % palette.size()] * (0.8 + rng.randf() * 0.35)
				if style == 1.0:
					col = Color(0.55, 0.6, 0.65) * (0.8 + rng.randf() * 0.3)
				items.append([Vector3(bx + sx * 0.5, gy + hgt * 0.5, bz + sz * 0.5), Vector3(sx, hgt, sz), col, Color(gy, gy + hgt, style, rng.randf())])
				if rng.randf() < 0.5:
					roof_items.append([Vector3(bx + sx * (0.25 + rng.randf() * 0.5), gy + hgt + 0.7, bz + sz * (0.25 + rng.randf() * 0.5)), Vector3(2.5, 1.4, 2.0)])
	for it in items:
		_register_building(AABB(it[0] - it[1] * 0.5, it[1]))
		city_boxes.append([it[0], it[1], it[2]])
	var chunks := {}
	for it in items:
		var key := Vector2i(int(floor(it[0].x / 200.0)), int(floor(it[0].z / 200.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(it)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = list.size()
		for i in list.size():
			var it: Array = list[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(it[1]), it[0]))
			mm.set_instance_color(i, it[2])
			mm.set_instance_custom_data(i, it[3])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)
	if not roof_items.is_empty():
		var rb := BoxMesh.new()
		rb.size = Vector3.ONE
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.4, 0.4, 0.4)
		rm.roughness = 0.7
		rm.metallic = 0.3
		rb.material = rm
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rb
		mm.instance_count = roof_items.size()
		for i in roof_items.size():
			var it: Array = roof_items[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(it[1]), it[0]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)
	# alberi nei parchi della sim e lungo i viali esterni
	var trees := []
	for blk in sim.blocks:
		if not blk["park"]:
			continue
		var p := sim_to_world(blk["x"], blk["y"])
		var w: float = blk["w"] * S
		var d: float = blk["h"] * S
		for k in 3:
			# alberi solo ai bordi del parco, per non coprire troppo le unità
			var X := p.x + 2.0 + rng.randf() * (w - 4.0)
			var Z := p.y + (1.5 if k % 2 == 0 else d - 1.5)
			trees.append([Vector3(X, height(X, Z) - 0.2, Z), 0.6 + rng.randf() * 0.3, rng.randf() * TAU, _tint()])
	for i in int(500 * KS):
		var X := (rng.randf() * 2 - 1) * (FIELD_HX + 400.0)
		var Z := (rng.randf() * 2 - 1) * (FIELD_HZ + 368.0)
		if _in_field(X, Z, 10):
			continue
		# allinea al bordo marciapiede di una strada verticale
		var gi := roundf((X - gx0 + st * 0.5) / px)
		X = gx0 + gi * px - st * 0.5 + (st * 0.5 - 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		if sim.sea and X < coast_x(Z) + 20:
			continue
		trees.append([Vector3(X, height(X, Z) - 0.2, Z), 0.6 + rng.randf() * 0.35, rng.randf() * TAU, _tint()])
	_add_instances("broadleaf", trees)


# ---------------------------------------------------------------------------- fase 2: servizi per la vista
func _register_building(b: AABB) -> void:
	if absf(b.get_center().x) > FIELD_HX + 70.0 or absf(b.get_center().z) > FIELD_HZ + 78.0:
		return
	_bld_max = maxf(_bld_max, b.end.y)
	var c0 := Vector2i(int(floor(b.position.x / BLD_CELL)), int(floor(b.position.z / BLD_CELL)))
	var c1 := Vector2i(int(floor(b.end.x / BLD_CELL)), int(floor(b.end.z / BLD_CELL)))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var k := Vector2i(cx, cz)
			if not _bld_cells.has(k):
				_bld_cells[k] = []
			_bld_cells[k].append(b)

## Vero se il segmento a→b (a = punto sull'unità, b = telecamera) è coperto da un edificio o dal rilievo.
func occluded(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var L := d.length()
	if L < 1.0:
		return false
	var dir := d / L
	var t := 2.5
	var lim := minf(L, 260.0)
	if _field_hmax < -1e8:
		_field_hmax = 0.0
		var X := -FIELD_HX - 40.0
		while X <= FIELD_HX + 40.0:
			var Z := -FIELD_HZ - 40.0
			while Z <= FIELD_HZ + 40.0:
				_field_hmax = maxf(_field_hmax, height(X, Z))
				Z += 6.0
			X += 6.0
	var top := maxf(_bld_max, _field_hmax)
	while t < lim:
		var p := a + dir * t
		if p.y > top + 2.0 and dir.y > 0:
			return false
		if p.y < height(p.x, p.z) - 0.4:
			return true
		if not _bld_cells.is_empty():
			var k := Vector2i(int(floor(p.x / BLD_CELL)), int(floor(p.z / BLD_CELL)))
			if _bld_cells.has(k):
				for bb in _bld_cells[k]:
					if (bb as AABB).has_point(p):
						return true
		t += 2.0 if t < 60.0 else 4.0
	return false

## Boschi che coprono le unità importanti: `focus` = posizioni (Vector3) di unità selezionate o in combattimento.
## Se il segmento unità→telecamera passa tra le chiome (cilindro del bosco fino alla quota delle cime) il bosco sfuma.
## Da chiamare a intervalli brevi con `check` = true; ogni frame per la dissolvenza.
func update_woods(cam_pos: Vector3, focus: Array, dt: float, check: bool) -> void:
	if woods.is_empty():
		return
	if check:
		for w in woods:
			var c: Vector2 = w["c"]
			var r: float = w["r"]
			var top: float = w["h"]
			var hit := false
			for p in focus:
				var a := Vector2(p.x, p.z)
				if a.distance_squared_to(c) < (r + 2.0) * (r + 2.0):
					hit = true
					break
				var d: Vector3 = cam_pos - p
				var t1 := 1.0
				if d.y > 0.01:
					t1 = clampf((top - p.y) / d.y, 0.0, 1.0)
				var b := a + Vector2(d.x, d.z) * t1
				var ab := b - a
				var l2 := ab.length_squared()
				var k := clampf((c - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
				if (a + ab * k).distance_squared_to(c) < r * r:
					hit = true
					break
			w["want"] = 0.7 if hit else 0.0
	for w in woods:
		var f: float = w["fade"]
		var tg: float = w["want"]
		if absf(f - tg) < 0.001:
			continue
		f = move_toward(f, tg, dt * 2.5)
		w["fade"] = f
		for n in w["nodes"]:
			(n as GeometryInstance3D).transparency = f

## Texture fotografiche CC0 del terreno (Poly Haven): erba, terra, roccia, neve, sabbia, sottobosco.
## Se mancano (o con --tex=0) il terreno resta procedurale come prima.
const PHOTO_TEX := {"grass": "grass_ground_%s_2k", "dirt": "brown_mud_dry_%s_2k", "rock": "aerial_rocks_02_%s_1k",
	"snow": "snow_02_%s_1k", "sand": "aerial_sand_%s_1k", "leaf": "forest_leaves_02_%s_1k"}
func _bind_photo_textures() -> void:
	var shot: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Shot") if Engine.get_main_loop() is SceneTree else null
	if shot != null and String(shot.call("arg", "tex", "1")) == "0":
		terrain_mat.set_shader_parameter("tex_k", 0.0)
		terrain_mat.set_shader_parameter("sat_k", 1.24)
		return
	var ok := true
	for k in PHOTO_TEX:
		var base := "res://assets/textures/terrain/" + String(PHOTO_TEX[k])
		var dname := base % ("diffuse" if k == "leaf" else "diff") + ".jpg"
		var nname := base % "nor_gl" + ".jpg"
		if not ResourceLoader.exists(dname) or not ResourceLoader.exists(nname):
			ok = false
			break
		terrain_mat.set_shader_parameter("t_" + k, load(dname))
		terrain_mat.set_shader_parameter("n_" + k, load(nname))
	terrain_mat.set_shader_parameter("tex_k", 1.0 if ok else 0.0)
	terrain_mat.set_shader_parameter("sat_k", 1.0 if ok else 1.24)

## Densità della vegetazione/erba secondo la qualità (0..1).
func set_density(f: float) -> void:
	if terrain_mat != null:
		terrain_mat.set_shader_parameter("detail_k", 1.0 if f > 0.4 else 0.0)
		terrain_mat.set_shader_parameter("tex_two", 1.0 if f > 0.4 else 0.0)
	for mm in grass_mms:
		(mm as MultiMesh).visible_instance_count = int((mm as MultiMesh).instance_count * f)
	for mm in deco_mms:
		(mm as MultiMesh).visible_instance_count = int((mm as MultiMesh).instance_count * clampf(f * 1.4, 0.0, 1.0))

## Zona di schieramento: velo colorato che segue il terreno, bordo più marcato.
func make_zone_mesh(r: Rect2, col: Color) -> MeshInstance3D:
	var nx := int(ceil(r.size.x / 3.0))
	var nz := int(ceil(r.size.y / 3.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var quad := []
			for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var u := float(i + c.x) / nx
				var v := float(j + c.y) / nz
				var X := r.position.x + u * r.size.x
				var Z := r.position.y + v * r.size.y
				var h := height(X, Z)
				if sim.sea:
					h = maxf(h, 0.0)
				quad.append([Vector3(X, h + 0.35, Z), Vector2(u, v)])
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
	var mesh := st.commit()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color;
uniform vec2 px;
void fragment() {
	vec2 e = min(UV, 1.0 - UV) / px;
	float edge = 1.0 - smoothstep(0.0, 1.2, min(e.x, e.y));
	float stripes = step(0.5, fract((UV.x / px.x + UV.y / px.y) * 0.08));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0);
	ALBEDO = col.rgb;
	ALPHA = clamp(0.05 + stripes * 0.035 + edge * 0.75 * pulse, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", col.lightened(0.25))
	m.set_shader_parameter("px", Vector2(1.0 / r.size.x, 1.0 / r.size.y))
	m.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.name = "DeployZone"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Immagine della minimappa (vista dall'alto, nord in alto) dell'area [-hx,hx]×[-hz,hz].
func minimap_image(w: int, h: int, hx: float, hz: float) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var c0: Color = ground_cols[0]
	var c1: Color = ground_cols[1]
	var cd: Color = ground_cols[2]
	var cr: Color = ground_cols[3]
	var light := Vector3(-0.5, 0.75, -0.45).normalized()
	var sx := 2.0 * hx / w
	var sz := 2.0 * hz / h
	for j in h:
		var Z := -hz + (j + 0.5) * sz
		for i in w:
			var X := -hx + (i + 0.5) * sx
			var hh := height(X, Z)
			var n := normal(X, Z)
			var col := c0.lerp(c1, clampf(noise.get_noise_2d(X * 0.5, Z * 0.5) * 0.8 + 0.5, 0.0, 1.0))
			if n.y < 1.0 - float(_p[4]):
				col = cr
			if tkey == "urbano" or not outer_roads.is_empty():
				var mu := Vector2i(int((X + MASK_HX) / MASK_RES), int((Z + MASK_HZ) / MASK_RES))
				if mu.x >= 0 and mu.y >= 0 and mu.x < mask_img.get_width() and mu.y < mask_img.get_height():
					var m := mask_img.get_pixelv(mu)
					if tkey == "urbano":
						col = col.lerp(Color(0.42, 0.41, 0.39), m.g).lerp(Color(0.27, 0.36, 0.17), m.b).lerp(Color(0.2, 0.2, 0.21), m.r * (1.0 - m.g))
					else:
						col = col.lerp(cd, m.r * 0.85)
			if sim.sea and hh < 0.3:
				col = Color(0.1, 0.27, 0.33).lerp(Color(0.16, 0.38, 0.4), clampf(hh + 2.0, 0.0, 1.0))
			var sh := clampf(0.55 + 0.6 * n.dot(light), 0.45, 1.15)
			img.set_pixel(i, j, Color(col.r * sh, col.g * sh, col.b * sh))
	# ostacoli della sim
	for o in sim.obs:
		if o["rect"]:
			var a := sim_to_world(o["x"], o["y"])
			var r := Rect2i(int((a.x + hx) / sx), int((a.y + hz) / sz), maxi(1, int(o["w"] * S / sx)), maxi(1, int(o["h"] * S / sz)))
			img.fill_rect(r.intersection(Rect2i(0, 0, w, h)), Color(0.55, 0.53, 0.5))
		else:
			var c := sim_to_world(o["x"], o["y"])
			var R: float = o["r"] * S
			var oc := Color(0.14, 0.24, 0.1) if o["kind"] == "bosco" else (Color(0.85, 0.9, 0.95) if o["kind"] == "ghiaccio" else cr.darkened(0.15))
			var ci := int((c.x + hx) / sx)
			var cj := int((c.y + hz) / sz)
			var ri := int(ceil(R / sx))
			for jj in range(cj - ri, cj + ri + 1):
				for ii in range(ci - ri, ci + ri + 1):
					if ii < 0 or jj < 0 or ii >= w or jj >= h:
						continue
					var dx := (ii - ci) * sx
					var dz := (jj - cj) * sz
					if dx * dx + dz * dz <= R * R:
						img.set_pixel(ii, jj, oc.lerp(img.get_pixel(ii, jj), 0.25))
	return img

## Quota del tetto più alto sotto il punto (0 se nessun edificio), con un margine di 6 m attorno.
## Vero se il punto è dentro la pianta di un edificio (senza margine).
func inside_building(X: float, Z: float) -> bool:
	var k := Vector2i(int(floor(X / BLD_CELL)), int(floor(Z / BLD_CELL)))
	if not _bld_cells.has(k):
		return false
	for bb in _bld_cells[k]:
		var b: AABB = bb
		if X > b.position.x and X < b.end.x and Z > b.position.z and Z < b.end.z:
			return true
	return false

func roof_height(X: float, Z: float) -> float:
	if _bld_cells.is_empty():
		return 0.0
	var best := 0.0
	var c := Vector2i(int(floor(X / BLD_CELL)), int(floor(Z / BLD_CELL)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dz)
			if not _bld_cells.has(k):
				continue
			for bb in _bld_cells[k]:
				var b: AABB = bb
				if X > b.position.x - 6.0 and X < b.end.x + 6.0 and Z > b.position.z - 6.0 and Z < b.end.z + 6.0:
					best = maxf(best, b.end.y)
	return best


# ============================================================================ Fase 7 — campi coltivati e siepi
## Riferimento ruotato dei campi (lo stesso dello shader: q = R(-θ)·p).
func _fq(p: Vector2) -> Vector2:
	return Vector2(p.x * _field_ca + p.y * _field_sa, -p.x * _field_sa + p.y * _field_ca)

func _fw(q: Vector2) -> Vector2:
	return Vector2(q.x * _field_ca - q.y * _field_sa, q.x * _field_sa + q.y * _field_ca)

## Patchwork di campi (pianura; radure coltivate in foresta): texture in un riferimento ruotato
## (r = tipo di coltura/255, g = tinta, b > 0.6 = bordo a capezzagna, a = 1 dove ci sono campi), più siepi/staccionate 3D
## e capezzagne sterrate nella maschera delle strade.
func _build_fields() -> void:
	if tkey != "pianura" and tkey != "foresta":
		return
	var N := 1024   # ~2 m per texel: bordi dei campi e ritagli dei boschi senza scalini visibili
	_field_L = (maxf(FIELD_HX, FIELD_HZ) + 420.0) * 2.0
	var L := _field_L
	var ang := (rng.randf() - 0.5) * 0.9
	_field_ca = cos(ang)
	_field_sa = sin(ang)
	field_xf = Vector4(_field_ca, _field_sa, L, 1.0)
	field_img = Image.create(N, N, false, Image.FORMAT_RGBA8)
	field_img.fill(Color(0, 0, 0, 0))
	var ppm := N / L
	var pf := 0.74 if tkey == "pianura" else 0.42
	var lim := Vector2(FIELD_HX + 240.0, FIELD_HZ + 220.0)   # entro: siepi 3D e capezzagne vere
	var segs := []   # [q0: Vector2, q1: Vector2, kind]
	var q0 := -L * 0.5 + rng.randf() * 60.0
	while q0 < L * 0.5:
		var hgt := 60.0 + rng.randf() * 100.0
		var track_row := rng.randf() < 0.3
		var x := -L * 0.5 + rng.randf() * 80.0
		var prev_t := 0
		var ncell := 0
		while x < L * 0.5:
			var wdt := 70.0 + rng.randf() * 130.0
			var t := 0
			if rng.randf() < pf:
				t = 1 + rng.randi() % 5
				if t == prev_t:
					t = 1 + (t % 5)
			var tint := rng.randf()
			var trk := 1.0 if track_row else (0.9 if rng.randf() < 0.18 else 0.2)
			var px0 := int((x + L * 0.5) * ppm)
			var px1 := int((x + wdt + L * 0.5) * ppm)
			var py0 := int((q0 + L * 0.5) * ppm)
			var py1 := int((q0 + hgt + L * 0.5) * ppm)
			# fuori dal campo, dove il paesaggio è bosco (maschera condivisa): niente coltivi, ci stanno gli alberi
			var cwld := _fw(Vector2(x + wdt * 0.5, q0 + hgt * 0.5))
			if not _in_field(cwld.x, cwld.y, 40.0) and forest_at(cwld) > 0.5:
				field_img.fill_rect(Rect2i(px0, py0, maxi(1, px1 - px0), maxi(1, py1 - py0)), Color(0, 0, 0, 0))
				prev_t = 0
				ncell += 1
				x += wdt
				continue
			field_img.fill_rect(Rect2i(px0, py0, maxi(1, px1 - px0), maxi(1, py1 - py0)), Color(t / 255.0, tint, trk, 1.0))
			field_cells.append([x, q0, wdt, hgt, t, tint])
			# confini 3D: lato sinistro della cella (tra due celle) e lato inferiore (tra due righe)
			if ncell > 0 and (t > 0 or prev_t > 0):
				var r := rng.randf()
				var kind := 0 if r < 0.58 else (2 if r < 0.72 else (1 if r < 0.82 else (3 if r < 0.93 else -1)))
				if kind >= 0:
					segs.append([Vector2(x, q0), Vector2(x, q0 + hgt), kind])
			if t > 0 and not track_row:
				var r2 := rng.randf()
				var kind2 := 0 if r2 < 0.5 else (2 if r2 < 0.62 else (3 if r2 < 0.74 else -1))
				if kind2 >= 0:
					segs.append([Vector2(x, q0), Vector2(x + wdt, q0), kind2])
			prev_t = t
			ncell += 1
			x += wdt
		if track_row:
			segs.append([Vector2(-L * 0.5, q0), Vector2(L * 0.5, q0), 1])
		q0 += hgt
	# niente campi nei boschi e nel lago; sfumatura verso l'esterno lontano (orizzonte: prati)
	for o in sim.obs:
		if o.get("kind", "") != "bosco":
			continue
		var cw := _fq(sim_to_world(o["x"], o["y"]))
		var R := float(o.get("R", o.get("r", 20.0))) * S * 1.12
		var c := Vector2i(int((cw.x + L * 0.5) * ppm), int((cw.y + L * 0.5) * ppm))
		var rp := int(ceil(R * ppm)) + 2
		for j in range(c.y - rp, c.y + rp + 1):
			for i in range(c.x - rp, c.x + rp + 1):
				if i < 0 or j < 0 or i >= N or j >= N:
					continue
				var dx := (i - c.x) / ppm
				var dy := (j - c.y) / ppm
				# copertura antialias del bordo (in texel): con il filtro lineare dello shader il cerchio resta tondo
				var cov := clampf((sqrt(dx * dx + dy * dy) - R) * ppm + 0.5, 0.0, 1.0)
				var old := field_img.get_pixel(i, j)
				if cov < old.a:
					old.a = cov
					field_img.set_pixel(i, j, old)
	field_tex = ImageTexture.create_from_image(field_img)
	# siepi, staccionate, capezzagne (solo vicino al campo); i boschi non sono ancora costruiti: cerchi dagli ostacoli
	var bush := []
	var htree := []
	var wood_c := []
	for o in sim.obs:
		if o.get("kind", "") == "bosco":
			wood_c.append([sim_to_world(o["x"], o["y"]), float(o.get("R", o.get("r", 20.0))) * S * 0.85 + 4.0])
	for sg in segs:
		var a := _fw(sg[0])
		var b := _fw(sg[1])
		var kind: int = sg[2]
		var Lseg := a.distance_to(b)
		var n := int(ceil(Lseg / 12.0))
		var piece_a := Vector2.ZERO
		var open_piece := false
		for k in n + 1:
			var p := a.lerp(b, float(k) / maxf(1.0, n))
			var ok := absf(p.x) < lim.x and absf(p.y) < lim.y and not _near_road_world(p.x, p.y) and normal(p.x, p.y).y > 0.9
			if ok and sim.sea and (height(p.x, p.y) < 1.5 or p.x < coast_x(p.y) + 25.0):
				ok = false
			if ok:
				var ps := world_to_sim(p.x, p.y)
				for rv in relief.rivers:
					if ps.x > float(rv["bx0"]) and ps.x < float(rv["bx1"]) and BattleRelief.river_dist(rv, ps.x, ps.y) < float(rv["cw"]) * 2.2:
						ok = false
				for w in wood_c:
					if p.distance_squared_to(w[0]) < w[1] * w[1]:
						ok = false
			if ok and not open_piece:
				piece_a = p
				open_piece = true
			elif (not ok or k == n) and open_piece:
				var pb := p if ok else a.lerp(b, float(k - 1) / maxf(1.0, n))
				open_piece = false
				if piece_a.distance_to(pb) < 6.0:
					continue
				hedges.append([piece_a, pb, kind])
				match kind:
					1:
						_mask_segment(piece_a, pb, 1.3)
					2:
						_fence_line(piece_a, pb)
					3:
						_wall_line(piece_a, pb)
					0:
						var d := piece_a.distance_to(pb)
						var m := int(d / 3.0)
						for i in m:
							if rng.randf() < 0.12:
								continue   # varchi nella siepe
							var hp := piece_a.lerp(pb, (i + 0.5) / m) + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * 0.8
							bush.append([Vector3(hp.x, height(hp.x, hp.y) - 0.2, hp.y), 1.1 + rng.randf() * 0.9, rng.randf() * TAU, _tint()])
							if i % 9 == 4 and rng.randf() < 0.55:
								htree.append([Vector3(hp.x, height(hp.x, hp.y) - 0.2, hp.y), 0.6 + rng.randf() * 0.4, rng.randf() * TAU, _tint()])
	_add_instances("bush", bush, false)
	_add_instances("broadleaf", htree)

# ============================================================================ Fase 7 — fiumi, ponti, guadi
const RIVER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.11, 0.17, 0.15);
uniform vec3 shallow : source_color = vec3(0.26, 0.32, 0.24);
uniform float flow = 1.0;
varying vec3 wpos;
varying vec2 vuv;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vuv = UV;
}
void fragment() {
	vec2 p = wpos.xz;
	vec3 n1 = texture(nrm, p / 6.0 + vec2(TIME * 0.01, TIME * 0.045 * flow)).rgb;
	vec3 n2 = texture(nrm, p / 2.3 + vec2(-TIME * 0.02, TIME * 0.07 * flow)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.45));
	NORMAL_MAP_DEPTH = 0.5;
	float edge = 1.0 - smoothstep(0.0, 0.22, min(vuv.x, 1.0 - vuv.x));
	float ripple = 0.5 + 0.5 * sin(TIME * 1.6 + p.y * 2.1 + p.x * 0.7);
	ALBEDO = mix(deep, shallow, edge * (0.6 + 0.4 * ripple));
	ALPHA = clamp(0.9 - edge * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""

func _build_rivers() -> void:
	for rv in relief.rivers:
		if bool(rv["water"]):
			_river_water(rv)
	for br in bridges:
		_bridge_mesh(br)

## Nastro d'acqua lungo il tracciato (0.5 m sotto le sponde), dall'orizzonte nord a quello sud.
func _river_water(rv: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cw: float = rv["cw"]
	var y := -OUTER * 0.72 / S
	var y_end := float(sim.H) + OUTER * 0.72 / S
	var hw := cw * S * 1.05
	while y <= y_end:
		var x := BattleRelief.river_x(rv, y)
		var sl := BattleRelief.river_slope(rv, y)
		var k := 1.0 / sqrt(1.0 + sl * sl)
		var px := Vector2(1.0, -sl) * k   # perpendicolare (px)
		var c := sim_to_world(x, y)
		var lvl := BattleRelief.river_floor(rv, y) - 0.5
		var o := Vector2(px.x, px.y) * hw
		st.set_uv(Vector2(0, y * 0.01))
		st.add_vertex(Vector3(c.x - o.x, lvl, c.y - o.y))
		st.set_uv(Vector2(1, y * 0.01))
		st.add_vertex(Vector3(c.x + o.x, lvl, c.y + o.y))
		y += 24.0
	var mesh := st.commit()
	var sh := Shader.new()
	sh.code = RIVER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var nz := FastNoiseLite.new()
	nz.seed = 3
	nz.frequency = 0.05
	var img := nz.get_seamless_image(256, 256)
	img.bump_map_to_normal_map(2.5)
	img.generate_mipmaps()
	m.set_shader_parameter("nrm", ImageTexture.create_from_image(img))
	if tkey == "foresta":
		m.set_shader_parameter("deep", Color(0.05, 0.1, 0.09))
		m.set_shader_parameter("shallow", Color(0.18, 0.26, 0.2))
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Ponte: impalcato (landmark "bridge", lungo 1 lungo +Z, largo 7 m) scalato sulla campata, con pila centrale sopra i 16 m.
func _bridge_mesh(br: Dictionary) -> void:
	var a: Vector3 = br["a"]
	var b: Vector3 = br["b"]
	var yaw: float = br["yaw"]
	var L: float = br["len"]
	var mi := MeshInstance3D.new()
	mi.name = "Bridge"
	mi.mesh = BattleProps.landmark_mesh("bridge")
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, L)), a)
	add_child(mi)
	landmarks.append({"kind": "bridge", "pos": (a + b) * 0.5, "yaw": yaw, "size": Vector3(7.0, 1.6, L)})
	if L > 16.0:
		var pier := MeshInstance3D.new()
		pier.mesh = BattleProps.landmark_mesh("pier")
		pier.transform = Transform3D(Basis(Vector3.UP, yaw), (a + b) * 0.5 + Vector3(0, -0.7, 0))
		add_child(pier)

# ============================================================================ Fase 7 — punti di riferimento
func _lm_add(kind: String, pos: Vector3, yaw: float, scale := Vector3.ONE, col := Color(1, 1, 1), size := Vector3.ZERO) -> void:
	if not _lm.has(kind):
		_lm[kind] = []
	_lm[kind].append([Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), col])
	if size != Vector3.ZERO:
		landmarks.append({"kind": kind, "pos": pos, "yaw": yaw, "size": size})
		var r := maxf(size.x, size.z) * 0.5
		_register_building(AABB(Vector3(pos.x - r, pos.y, pos.z - r), Vector3(2 * r, size.y, 2 * r)))

## Staccionata da a a b (mondo): un palo ogni 2 m con le traverse.
func _fence_line(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var L := d.length()
	if L < 2.0:
		return
	var dir := d / L
	var yaw := atan2(dir.x, dir.y)
	var n := int(L / 2.0)
	for i in n:
		var p := a + dir * (i * 2.0)
		var seg := minf(2.0, L - i * 2.0)
		_lm_add("fence", Vector3(p.x, height(p.x, p.y) - 0.05, p.y), yaw, Vector3(1.0, 1.0, seg), Color(0.9 + rng.randf() * 0.2, 0.9 + rng.randf() * 0.2, 0.9 + rng.randf() * 0.15))

## Muretto a secco da a a b (mondo): pezzi da 2 m che seguono il terreno.
func _wall_line(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var L := d.length()
	if L < 2.0:
		return
	var dir := d / L
	var yaw := atan2(dir.x, dir.y)
	var n := int(L / 2.0)
	for i in n:
		var p := a + dir * (i * 2.0)
		var seg := minf(2.0, L - i * 2.0)
		var v := 0.88 + rng.randf() * 0.2
		_lm_add("wall", Vector3(p.x, height(p.x, p.y) - 0.12, p.y), yaw, Vector3(1.0, 0.85 + rng.randf() * 0.3, seg), Color(v, v, v * 0.97))

## Sito adatto a un edificio: pianeggiante, non su strade/boschi/fiumi/lago/acqua, lontano da altri punti di riferimento.
func _site_ok(X: float, Z: float, r: float, allow_in_field := false) -> bool:
	if not allow_in_field and _in_field(X, Z, 14.0):
		return false
	if absf(X) > FIELD_HX + 460.0 or absf(Z) > FIELD_HZ + 360.0:
		return false
	var h := height(X, Z)
	if sim.sea and (h < 1.5 or X < coast_x(Z) + 30.0):
		return false
	if normal(X, Z).y < 0.975:
		return false
	for c in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		if absf(height(X + c.x, Z + c.y) - h) > 1.4:
			return false
	if _near_road_world(X, Z):
		return false
	for w in woods:
		if Vector2(X, Z).distance_to(w["c"]) < w["r"] + r:
			return false
	var ps := world_to_sim(X, Z)
	for rv in relief.rivers:
		if ps.x > float(rv["bx0"]) and ps.x < float(rv["bx1"]) and BattleRelief.river_dist(rv, ps.x, ps.y) < float(rv["vw"]) * 0.6:
			return false
	if relief.lake != null:
		var Lk: Dictionary = relief.lake
		var ex := (ps.x - float(Lk["x"])) / float(Lk["rx"])
		var ey := (ps.y - float(Lk["y"])) / float(Lk["ry"])
		if ex * ex + ey * ey < 1.3 * 1.3:
			return false
	for lm in landmarks:
		var lp: Vector3 = lm["pos"]
		var ls: Vector3 = lm["size"]
		if Vector2(X, Z).distance_to(Vector2(lp.x, lp.z)) < r + maxf(ls.x, ls.z) * 0.5 + 4.0:
			return false
	return true

## Punto a caso lungo una strada, fuori dal campo (entro `far` m dal bordo), scostato di `off` m dalla carreggiata.
func _roadside(off: float, far: float) -> Array:
	if outer_roads.is_empty():
		return []
	for tries in 40:
		var road: Array = outer_roads[rng.randi() % outer_roads.size()]
		var i := rng.randi() % (road.size() - 1)
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var p := a.lerp(b, rng.randf())
		if _in_field(p.x, p.y, 22.0) or absf(p.x) > FIELD_HX + far or absf(p.y) > FIELD_HZ + far:
			continue
		var d := (b - a).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var q := p + Vector2(-d.y, d.x) * off * side
		return [q, atan2(d.x, d.y)]
	return []

## Fattoria: casa colonica, fienile, silo, staccionata e alberi.
func _farm(c: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var house := c
	_lm_add("house", Vector3(house.x, height(house.x, house.y) - 0.3, house.y), yaw, Vector3.ONE, Color(1, 1, 1), Vector3(11.8, 8.4, 8.3))
	var bo := b * Vector3(24.0, 0, 7.0)
	var barn := c + Vector2(bo.x, bo.z)
	_lm_add("barn", Vector3(barn.x, height(barn.x, barn.y) - 0.3, barn.y), yaw + PI * 0.5, Vector3.ONE, Color(1, 1, 1), Vector3(9.8, 10.6, 16.8))
	if rng.randf() < 0.7:
		var so := b * Vector3(24.0, 0, -6.5)
		var silo := c + Vector2(so.x, so.z)
		_lm_add("silo", Vector3(silo.x, height(silo.x, silo.y) - 0.3, silo.y), yaw, Vector3.ONE, Color(1, 1, 1), Vector3(5.4, 14.2, 5.4))
	# aia: staccionata su tre lati
	var corners := []
	for o in [Vector3(-12.0, 0, -14.0), Vector3(36.0, 0, -14.0), Vector3(36.0, 0, 16.0), Vector3(-12.0, 0, 16.0)]:
		var w: Vector3 = b * o
		corners.append(c + Vector2(w.x, w.z))
	for k in 3:
		_fence_line(corners[k], corners[(k + 1) % 4])
	var trees := []
	for k in 4:
		var o := b * Vector3(-8.0 + rng.randf() * 6.0, 0, -18.0 + k * 11.0)
		var tp := c + Vector2(o.x, o.z)
		trees.append([Vector3(tp.x, height(tp.x, tp.y) - 0.2, tp.y), 0.75 + rng.randf() * 0.4, rng.randf() * TAU, _tint()])
	_add_instances("broadleaf", trees)

## Gruppetto di case (`kind`: house/chalet/hut) attorno a un centro.
func _hamlet(c: Vector2, yaw: float, kind: String, n: int, spread: float) -> void:
	var sizes := {"house": Vector3(11.8, 8.4, 8.3), "chalet": Vector3(10.0, 7.2, 8.0), "hut": Vector3(8.4, 4.2, 6.9)}
	var placed := 0
	for tries in n * 6:
		if placed >= n:
			break
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		var p := c + Vector2(cos(a), sin(a)) * r
		if not _site_ok(p.x, p.y, 7.0, false):
			continue
		var yw := yaw + (PI * 0.5) * (rng.randi() % 4) + (rng.randf() - 0.5) * 0.3
		var col := Color(0.85 + rng.randf() * 0.3, 0.85 + rng.randf() * 0.3, 0.85 + rng.randf() * 0.3)
		_lm_add(kind, Vector3(p.x, height(p.x, p.y) - 0.3, p.y), yw, Vector3.ONE, col, sizes[kind])
		placed += 1

## Linea elettrica lungo la strada principale: pali ogni 45 m scostati di 9 m, tre fili per campata.
func _power_line() -> void:
	if outer_roads.is_empty():
		return
	var road: Array = outer_roads[0]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var acc := 45.0 * rng.randf()
	var prev := []   # [Vector3 pos, Basis b]
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var seg := a.distance_to(b)
		var d := (b - a) / maxf(seg, 0.001)
		var t := acc
		while t < seg:
			var p := a + d * t + Vector2(-d.y, d.x) * 9.0 * side
			t += 45.0
			if absf(p.x) > FIELD_HX + 330.0 or absf(p.y) > FIELD_HZ + 260.0:
				prev = []
				continue
			var hgt := height(p.x, p.y)
			if sim.sea and hgt < 1.0:
				prev = []
				continue
			var bad := false
			for w in woods:
				if p.distance_to(w["c"]) < w["r"] + 1.0:
					bad = true
			if bad:
				prev = []
				continue
			var yaw := atan2(d.x, d.y)
			var pos := Vector3(p.x, hgt - 0.2, p.y)
			_lm_add("pole", pos, yaw)
			if not prev.is_empty():
				var p0: Vector3 = prev[0]
				var b0: Basis = prev[1]
				for xo in [-1.4, 0.0, 1.4]:
					var w0 := p0 + b0 * Vector3(xo, 10.75, 0)
					var w1 := pos + Basis(Vector3.UP, yaw) * Vector3(xo, 10.75, 0)
					var dw := w1 - w0
					var Lw := dw.length()
					var yw := atan2(dw.x, dw.z)
					var pitch := -asin(clampf(dw.y / maxf(Lw, 0.001), -1.0, 1.0))
					var bw := Basis(Vector3.UP, yw) * Basis(Vector3.RIGHT, pitch)
					if not _lm.has("wire"):
						_lm["wire"] = []
					_lm["wire"].append([Transform3D(bw.scaled(Vector3(1, 1, Lw)), w0), Color(1, 1, 1)])
			prev = [pos, Basis(Vector3.UP, yaw)]
		acc = t - seg

func _build_landmarks() -> void:
	match tkey:
		"pianura":
			for k in 3:
				var rs := _roadside(26.0 + rng.randf() * 30.0, 300.0)
				if rs.is_empty():
					continue
				var p: Vector2 = rs[0]
				if _site_ok(p.x, p.y, 20.0):
					_farm(p, rs[1])
			var hs := _roadside(18.0, 260.0)
			if not hs.is_empty():
				_hamlet(hs[0], hs[1], "house", 4, 34.0)
			_power_line()
		"foresta":
			var rs := _roadside(30.0, 260.0)
			if not rs.is_empty() and _site_ok(rs[0].x, rs[0].y, 20.0):
				_farm(rs[0], rs[1])
			var hs := _roadside(16.0, 300.0)
			if not hs.is_empty():
				_hamlet(hs[0], hs[1], "chalet", 3, 26.0)
			_power_line()
		"montagna":
			for k in 2:
				var hs := _roadside(16.0, 320.0)
				if not hs.is_empty():
					_hamlet(hs[0], hs[1], "chalet", 3 + rng.randi() % 3, 30.0)
		"deserto":
			var hs := _roadside(22.0, 320.0)
			if not hs.is_empty():
				_hamlet(hs[0], hs[1], "hut", 6 + rng.randi() % 4, 36.0)
			var hs2 := _roadside(22.0, 320.0)
			if not hs2.is_empty():
				_hamlet(hs2[0], hs2[1], "hut", 3, 24.0)
			_power_line()
		"artico":
			var hs := _roadside(18.0, 300.0)
			if not hs.is_empty():
				_hamlet(hs[0], hs[1], "chalet", 3, 26.0)
		"urbano":
			pass
	# rovine ai margini del campo (in campo: le unità ci passano attraverso, sono basse)
	if tkey != "urbano":
		var nr := 2 if tkey != "deserto" else 3
		for k in nr:
			for tries in 20:
				var X := (rng.randf() * 2 - 1) * (FIELD_HX - 30.0)
				var Z := (rng.randf() * 2 - 1) * (FIELD_HZ + 40.0)
				if absf(Z) < FIELD_HZ * 0.72 and absf(X) < FIELD_HX * 0.8:
					continue
				if _site_ok(X, Z, 5.0, true):
					_lm_add("ruin", Vector3(X, height(X, Z) - 0.25, Z), rng.randf() * TAU, Vector3.ONE, Color(0.95, 0.95, 0.95))
					landmarks.append({"kind": "ruin", "pos": Vector3(X, height(X, Z), Z), "yaw": 0.0, "size": Vector3(8.0, 2.8, 6.0)})
					break
	_flush_landmarks()

## Edifici del territorio sul campo (`sim.landmarks`, omogeneità campagna→battaglia: {key, name, x, y, w, h} in px sim):
## compound con i pezzi dei punti di riferimento, registrati come edifici (occlusione, distruzione di BattleMarks).
func _build_sites() -> void:
	if not ("landmarks" in sim):
		return
	for lm in sim.landmarks:
		var key := String(lm["key"])
		var w: float = float(lm["w"]) * S
		var h: float = float(lm["h"]) * S
		var c := sim_to_world(float(lm["x"]) + float(lm["w"]) * 0.5, float(lm["y"]) + float(lm["h"]) * 0.5)
		var gy := height(c.x, c.y)
		var at := func(ox: float, oz: float) -> Vector3:
			return Vector3(c.x + ox, height(c.x + ox, c.y + oz) - 0.25, c.y + oz)
		var grey := Color(0.62, 0.62, 0.6)
		match key:
			"fabbrica":
				# capannoni, ciminiera, serbatoi, silos
				_lm_add("shed", at.call(-10.0, -6.0), 0.0, Vector3(2.4, 2.2, 2.2), Color(0.9, 0.88, 0.84), Vector3(20.0, 8.5, 12.5))
				_lm_add("shed", at.call(10.0, -6.0), 0.0, Vector3(2.4, 2.2, 2.2), Color(0.86, 0.84, 0.8), Vector3(20.0, 8.5, 12.5))
				_lm_add("slab", at.call(-18.0, 9.0), 0.0, Vector3(2.4, 19.0, 2.4), Color(0.5, 0.42, 0.38), Vector3(2.4, 19.0, 2.4))
				_lm_add("tank", at.call(4.0, 10.0), 0.3, Vector3(2.0, 1.6, 2.0), Color(0.75, 0.74, 0.7), Vector3(5.2, 6.0, 5.2))
				_lm_add("silo", at.call(14.0, 10.0), 0.0, Vector3.ONE, Color(1, 1, 1), Vector3(5.4, 14.2, 5.4))
				_lm_add("silo", at.call(20.0, 10.0), 0.0, Vector3.ONE, Color(1, 1, 1), Vector3(5.4, 14.2, 5.4))
			"aeroporto":
				# pista in cemento, hangar, torretta, luci di pista
				_lm_add("slab", Vector3(c.x, gy - 0.1, c.y + 11.0), 0.0, Vector3(w * 0.98, 0.3, 9.0), Color(0.5, 0.5, 0.48))
				for k in 6:
					_lm_add("slab", Vector3(c.x - w * 0.45 + k * w * 0.18, gy + 0.2, c.y + 11.0), 0.0, Vector3(3.0, 0.05, 0.5), Color(0.95, 0.95, 0.9))
				_lm_add("shed", at.call(-12.0, -8.0), 0.0, Vector3(2.6, 2.6, 2.6), Color(0.6, 0.62, 0.6), Vector3(21.0, 10.0, 14.5))
				_lm_add("shed", at.call(12.0, -8.0), 0.0, Vector3(2.6, 2.6, 2.6), Color(0.58, 0.6, 0.6), Vector3(21.0, 10.0, 14.5))
				_lm_add("slab", at.call(-22.0, -12.0), 0.0, Vector3(3.0, 11.0, 3.0), grey, Vector3(3.0, 11.0, 3.0))
				_lm_add("slab", at.call(-22.0, -12.0), 0.0, Vector3(5.0, 2.0, 5.0), Color(0.4, 0.55, 0.65))
			"porto":
				_lm_add("barn", at.call(-12.0, -4.0), PI * 0.5, Vector3(1.3, 1.2, 1.3), Color(0.8, 0.8, 0.82), Vector3(12.0, 8.0, 21.0))
				_lm_add("barn", at.call(6.0, -4.0), PI * 0.5, Vector3(1.3, 1.2, 1.3), Color(0.78, 0.76, 0.8), Vector3(12.0, 8.0, 21.0))
				_lm_add("tank", at.call(18.0, 8.0), 0.0, Vector3(1.8, 1.5, 1.8), Color(0.8, 0.5, 0.3), Vector3(4.6, 5.5, 4.6))
				_lm_add("slab", at.call(-4.0, 12.0), 0.0, Vector3(1.0, 14.0, 1.0), Color(0.75, 0.6, 0.2), Vector3(1.0, 14.0, 1.0))
				_lm_add("slab", at.call(-4.0, 12.0 + 7.0), 0.0, Vector3(0.6, 0.6, 14.0), Color(0.75, 0.6, 0.2))
				for k in 8:
					_lm_add("slab", at.call(-20.0 + k * 5.5, 14.0), 0.0, Vector3(4.8, 2.6, 2.4), Color(0.5 + 0.1 * (k % 3), 0.4, 0.3 + 0.2 * (k % 2)), Vector3(4.8, 2.6, 2.4))
			"impianto":
				for k in 4:
					_lm_add("tank", at.call(-15.0 + k * 10.0, 6.0), 0.0, Vector3(2.6, 2.2, 2.6), Color(0.78, 0.78, 0.74), Vector3(6.8, 8.0, 6.8))
				_lm_add("silo", at.call(-16.0, -9.0), 0.0, Vector3(0.8, 1.8, 0.8), Color(0.7, 0.7, 0.7), Vector3(4.4, 25.0, 4.4))
				_lm_add("slab", at.call(-2.0, -9.0), 0.0, Vector3(16.0, 1.2, 1.0), Color(0.55, 0.55, 0.52))
				_lm_add("slab", at.call(-2.0, -11.0), 0.0, Vector3(16.0, 2.4, 0.8), Color(0.5, 0.52, 0.5))
				_lm_add("shed", at.call(14.0, -9.0), 0.0, Vector3(1.6, 1.6, 1.6), Color(0.85, 0.85, 0.8), Vector3(13.0, 6.0, 9.0))
			"caserma":
				for k in 3:
					_lm_add("house", at.call(-16.0 + k * 16.0, -6.0), 0.0, Vector3(1.4, 0.9, 1.1), Color(0.72, 0.74, 0.66), Vector3(16.0, 7.5, 9.0))
				_lm_add("slab", at.call(0.0, 9.0), 0.0, Vector3(0.3, 9.0, 0.3), Color(0.8, 0.8, 0.8))
				_lm_add("slab", at.call(0.9, 9.0 + 0.0), 0.0, Vector3(1.8, 1.1, 0.05), Color(0.85, 0.2, 0.15))
				_lm_add("car", at.call(-20.0, 10.0), PI * 0.5, Vector3(1.3, 1.2, 1.4), Color(0.33, 0.36, 0.28))
				_lm_add("car", at.call(-16.0, 10.0), PI * 0.5, Vector3(1.3, 1.2, 1.4), Color(0.33, 0.36, 0.28))
			_:
				# fortino: casamatta bassa in cemento con feritoie e muretti
				_lm_add("slab", at.call(0.0, 0.0), 0.0, Vector3(9.0, 2.6, 7.0), Color(0.5, 0.5, 0.47), Vector3(9.0, 2.6, 7.0))
				_lm_add("slab", at.call(0.0, -3.4), 0.0, Vector3(6.0, 0.6, 0.4), Color(0.15, 0.15, 0.15))
				_lm_add("ruin", at.call(-12.0, 6.0), 0.4, Vector3.ONE, Color(0.9, 0.9, 0.9))
				_wall_line(c + Vector2(-14.0, -10.0), c + Vector2(14.0, -10.0))
		# recinzione sul perimetro (tre lati) e nome registrato per gli effetti
		var hw := w * 0.5
		var hh := h * 0.5
		var corners := [c + Vector2(-hw, -hh), c + Vector2(hw, -hh), c + Vector2(hw, hh), c + Vector2(-hw, hh)]
		for k in 3:
			_fence_line(corners[k], corners[(k + 1) % 4])
	_flush_landmarks()

# oggetti piccoli: distanza massima di disegno (sfumano), senza ombra, densità ridotta sulle qualità basse
const LM_RANGE := {"fhouse": 12000.0, "church": 12000.0, "wire": 520.0, "fence": 520.0, "wall": 700.0, "bale": 560.0, "bales": 650.0, "woodpile": 380.0, "lamp": 480.0,
	"car": 620.0, "bench": 300.0, "bin": 300.0, "trough": 380.0}
const LM_NO_SHADOW := ["wire", "fence", "lamp", "bench", "bin", "fhouse", "church"]
const LM_DECO := ["bale", "car", "bench", "bin", "woodpile", "trough"]

const NIGHT_KINDS := ["fhouse", "house", "church", "hut", "chalet", "barn"]   # finestre accese di notte

func _flush_landmarks() -> void:
	for kind in _lm:
		var items: Array = _lm[kind]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = BattleProps.landmark_mesh(kind)
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.name = "LM_" + kind
		mi.multimesh = mm
		if kind in NIGHT_KINDS:
			mi.material_override = _night_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in LM_NO_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = float(LM_RANGE.get(kind, 2200.0))
		if LM_RANGE.has(kind):
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.visibility_range_end_margin = 60.0
		if kind in LM_DECO:
			deco_mms.append(mm)   # densità secondo la qualità (set_density)
		add_child(mi)
	_lm.clear()

# ---------------------------------------------------------------------------- notte: finestre accese e chiazze di luce
const NIGHT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
varying flat float inst;
void vertex() { inst = float(INSTANCE_ID); }
void fragment() {
	vec3 c = COLOR.rgb;
	vec3 alb = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ALBEDO = alb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
	// finestre (scure nel modello): di notte si accendono, non tutte e con toni diversi
	float win = step(c.r + c.g + c.b, 0.5);
	float h = fract(sin(inst * 12.9898 + 7.1) * 43758.5453);
	float on = step(h, 0.78);
	vec3 warm = mix(vec3(1.0, 0.72, 0.38), vec3(0.95, 0.9, 0.75), step(0.5, fract(h * 7.0)));
	EMISSION = warm * 2.8 * night * win * on;
}
"""
const GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float night = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(max(0.0, 1.0 - d), 2.4);
	// da lontano (vista strategica) le chiazze restano leggibili: un po' più intense con la distanza
	float dc = length(VERTEX);
	a *= 1.0 + smoothstep(300.0, 1200.0, dc) * 1.2;
	ALBEDO = COLOR.rgb * a * night;
	ALPHA = a * night;
}
"""

func _night_material() -> ShaderMaterial:
	if _night_mat == null:
		var sh := Shader.new()
		sh.code = NIGHT_SHADER
		_night_mat = ShaderMaterial.new()
		_night_mat.shader = sh
	return _night_mat

## Registra una chiazza di luce a terra (lampione, casa, piazza) che si vede solo di notte.
func add_glow(p: Vector2, r: float, k: float, col := Color(1.0, 0.8, 0.5)) -> void:
	_glows.append([Vector3(p.x, height(p.x, p.y) + 0.25, p.y), r, k, col])

## Notte (BattleWeather): finestre accese e luci dei lampioni/paesi (k 0 = giorno).
func set_night(k: float) -> void:
	_night_material().set_shader_parameter("night", k)
	if _glow_mat == null and k > 0.001 and not _glows.is_empty():
		var sh := Shader.new()
		sh.code = GLOW_SHADER
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		pm.material = _glow_mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pm
		mm.instance_count = _glows.size()
		for i in _glows.size():
			var g: Array = _glows[i]
			var r: float = g[1]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), g[0]))
			var c: Color = g[3]
			mm.set_instance_color(i, Color(c.r * g[2], c.g * g[2], c.b * g[2], 1.0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "NightGlows"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 6000.0
		add_child(mi)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("night", k)

# ============================================================================ Fase 7 — servizi per vista e FX
## Da chiamare ogni frame: crateri, parametro "vista d'insieme" dello shader (carta tattica) e blocchi del suolo deformati.
func update_view(cam_dist: float, dt: float) -> void:
	update_scorch(dt)
	var ov := smoothstep(420.0, 700.0, cam_dist)   # carta tattica solo dalla vista strategica: sotto resta il terreno fotografico
	if absf(ov - _overview) > 0.02 or (ov == 0.0 and _overview != 0.0):
		_overview = ov
		terrain_mat.set_shader_parameter("overview", ov)
	if not _dirty_chunks.is_empty():
		var ci: int = _dirty_chunks.keys()[0]
		_dirty_chunks.erase(ci)
		var m: Array = _chunk_meta[ci]
		(chunks[ci] as MeshInstance3D).mesh = _chunk_mesh(m[0], m[1], m[2], m[3], xs.size(), _verts, _norms, _cols)

## HOOK FX — cratere vero nel suolo (coordinate sim, raggio in px, profondità in m): abbassa la mesh del terreno
## (bordo rialzato), aggiorna `height()` (unità, relitti e decalcomanie seguono il buco) e ricostruisce i blocchi toccati
## a uno per frame in `update_view`. Solo vista: la quota della sim (BattleRelief) non cambia. Chiamare anche `paint_crater`.
func deform_crater(x: float, y: float, r_px: float, depth := 0.7) -> void:
	var c := sim_to_world(x, y)
	var R := r_px * S
	if R < STEP * 0.6 or absf(c.x) > INNER_HX - R - STEP * 2 or absf(c.y) > INNER_HZ - R - STEP * 2:
		return
	var W := xs.size()
	var i0 := _ix0 + int(floor((c.x - R + INNER_HX) / STEP))
	var i1 := _ix0 + int(ceil((c.x + R + INNER_HX) / STEP))
	var j0 := _iz0 + int(floor((c.y - R + INNER_HZ) / STEP))
	var j1 := _iz0 + int(ceil((c.y + R + INNER_HZ) / STEP))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * W + i
			var dx := xs[i] - c.x
			var dz := zs[j] - c.y
			var d := sqrt(dx * dx + dz * dz) / R
			if d >= 1.0:
				continue
			var bowl := (1.0 - d * d) * (1.0 - d * d)
			var rim := smoothstep(0.5, 0.8, d) * (1.0 - smoothstep(0.8, 1.0, d))
			var dh := -depth * bowl + depth * 0.22 * rim
			hts[k] += dh
			var v := _verts[k]
			v.y = hts[k]
			_verts[k] = v
	# normali della zona toccata
	var Hn := zs.size()
	for j in range(maxi(1, j0 - 1), mini(Hn - 2, j1 + 1) + 1):
		for i in range(maxi(1, i0 - 1), mini(W - 2, i1 + 1) + 1):
			var dhx := (hts[j * W + i + 1] - hts[j * W + i - 1]) / (xs[i + 1] - xs[i - 1])
			var dhz := (hts[(j + 1) * W + i] - hts[(j - 1) * W + i]) / (zs[j + 1] - zs[j - 1])
			_norms[j * W + i] = Vector3(-dhx, 1.0, -dhz).normalized()
	for ci in _chunk_meta.size():
		var m: Array = _chunk_meta[ci]
		if i1 + 1 >= m[0] and i0 - 1 <= m[1] and j1 + 1 >= m[2] and j0 - 1 <= m[3]:
			_dirty_chunks[ci] = true

## HOOK FX — tipo di superficie nel punto mondo (X, Z): "water", "ice", "mud", "gravel", "sand", "snow", "rock",
## "asphalt", "concrete", "dirt" (strada sterrata/capezzagna), "field" (coltivo), "forest", "grass".
func surface_at(X: float, Z: float) -> String:
	var h := height(X, Z)
	if sim.sea and h < 0.3:
		return "water"
	if sim.sea and h < 1.5:
		return "sand"
	var ps := world_to_sim(X, Z)
	for rv in relief.rivers:
		if ps.x > float(rv["bx0"]) and ps.x < float(rv["bx1"]):
			var dp := BattleRelief.river_dist(rv, ps.x, ps.y)
			var cw: float = rv["cw"]
			if dp < cw * 0.85:
				return "water" if bool(rv["water"]) else "sand"
			if dp < cw * 2.0:
				return "mud" if bool(rv["water"]) else "gravel"
	if relief.lake != null:
		var Lk: Dictionary = relief.lake
		var ex := (ps.x - float(Lk["x"])) / float(Lk["rx"])
		var ey := (ps.y - float(Lk["y"])) / float(Lk["ry"])
		if ex * ex + ey * ey < 1.0:
			return "ice"
	if mask_img != null:
		var mu := Vector2i(int((X + MASK_HX) / MASK_RES), int((Z + MASK_HZ) / MASK_RES))
		if mu.x >= 0 and mu.y >= 0 and mu.x < mask_img.get_width() and mu.y < mask_img.get_height():
			var m := mask_img.get_pixelv(mu)
			if tkey == "urbano":
				if m.g > 0.5:
					return "concrete"
				if m.b > 0.5:
					return "grass"
				if m.r > 0.5:
					return "asphalt"
			elif m.r > 0.45:
				return "dirt"
	if normal(X, Z).y < 1.0 - float(_p[4]):
		return "rock"
	if tkey == "artico" or h > float(_p[5]):
		return "snow"
	if tkey == "deserto":
		return "sand"
	for w in woods:
		if Vector2(X, Z).distance_squared_to(w["c"]) < w["r"] * w["r"]:
			return "forest"
	if field_img != null:
		var q := _fq(Vector2(X, Z))
		var fu := q / _field_L + Vector2(0.5, 0.5)
		if fu.x > 0.0 and fu.y > 0.0 and fu.x < 1.0 and fu.y < 1.0:
			var fc := field_img.get_pixel(int(fu.x * field_img.get_width()), int(fu.y * field_img.get_height()))
			if fc.a > 0.5 and fc.r8 > 0:
				return "field"
	return "grass"
