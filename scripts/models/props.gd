class_name Props
extends RefCounted
## Elementi di scenario generati in codice (Agente F): alberi, rocce, edifici, crateri. Tutte statiche, in metri, origine a terra.
## tree_mesh(kind) restituisce una mesh unica (2 superfici: tronco + chioma) adatta a MultiMesh (in cache).

const TREE_KINDS := ["pine", "broadleaf", "palm", "dead", "birch", "cypress", "bush"]
const SEASONS := ["", "autumn", "snow", "dry"]
const BARK := Color(0.27, 0.2, 0.14)
const BARK_GRAY := Color(0.36, 0.33, 0.3)

static var _tree_cache := {}
static var _crater_mesh: ArrayMesh = null

# ============================================================== alberi
## kind: "pine" | "broadleaf" | "palm" | "dead" | "birch" | "cypress" | "bush"
## season: "" (estate) | "autumn" | "snow" (artico/inverno: neve sulle chiome) | "dry" (deserto/estate arida)
static func tree(kind: String, rng: RandomNumberGenerator, season: String = "") -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Tree_" + kind
	mi.mesh = tree_mesh(kind, season)
	var s := rng.randf_range(0.8, 1.25)
	mi.scale = Vector3(s, s * rng.randf_range(0.9, 1.12), s)
	mi.rotation.y = rng.randf() * TAU
	return mi

static func tree_mesh(kind: String, season: String = "") -> Mesh:
	var key := kind + "|" + season
	if _tree_cache.has(key):
		return _tree_cache[key]
	var b := ModelKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"pine": _pine(b, rng, season)
		"palm": _palm(b, rng, season)
		"dead": _dead(b, rng, season)
		"birch": _birch(b, rng, season)
		"cypress": _cypress(b, rng, season)
		"bush": _bush(b, rng, season)
		_: _broadleaf(b, rng, season)
	var m := b.commit()
	m.set_meta("tris", b.tri_count())
	_tree_cache[key] = m
	return m

const SNOW := Color(0.88, 0.91, 0.95)

## Colore di una porzione di chioma secondo la stagione; `up` = quanto la faccia guarda in alto (0..1), `t` = variazione 0..1.
static func _leaf(col: Color, season: String, up: float, t: float, conifer: bool = false) -> Color:
	var c := col
	match season:
		"autumn":
			if not conifer:
				c = [Color(0.55, 0.28, 0.07), Color(0.62, 0.42, 0.1), Color(0.48, 0.16, 0.07), Color(0.42, 0.4, 0.12)][int(t * 3.99)] as Color
				c *= 0.85 + 0.25 * up
		"dry":
			c = c.lerp(Color(0.38, 0.36, 0.18), 0.55)
		"snow":
			if conifer:
				c = c * 0.8
			else:
				c = c.lerp(Color(0.32, 0.28, 0.22), 0.6)
			if up > 0.35:
				c = c.lerp(SNOW, clampf((up - 0.35) * 2.6 + (t - 0.5) * 0.4, 0.0, 0.95))
	return c

static func _bark(season: String) -> Color:
	return BARK * (0.85 if season == "snow" else 1.0)

static func _pine(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	b.cyl("matte", 0.28, 0.06, 13.0, 7, Transform3D(Basis.IDENTITY, Vector3(0, 6.5, 0)), _bark(season))
	var tiers := 8
	for i in tiers:
		var f := float(i) / float(tiers - 1)
		var y := lerpf(2.2, 11.4, f) + rng.randf_range(-0.2, 0.2)
		var r := lerpf(3.0, 0.75, f) * rng.randf_range(0.88, 1.1)
		var h := lerpf(2.8, 2.0, f)
		var base := Color(0.1, 0.19, 0.11).lerp(Color(0.16, 0.27, 0.14), f) * rng.randf_range(0.88, 1.08)
		var rot := Basis(Vector3.UP, rng.randf() * TAU)
		var n := 12
		var ring: Array = []
		var tipr: Array = []
		for k in n:
			var a := TAU * float(k) / float(n)
			var rr := r * (1.0 if k % 2 == 0 else 0.68) * rng.randf_range(0.9, 1.1)
			var droop := (0.55 if k % 2 == 0 else 0.15) + rng.randf_range(0.0, 0.15)
			ring.append(rot * Vector3(cos(a) * rr, 0, sin(a) * rr) + Vector3(0, y - droop, 0))
			tipr.append(rot * Vector3(cos(a) * rr * 0.45, 0, sin(a) * rr * 0.45) + Vector3(0, y + h * 0.45, 0))
		var tip := Vector3(rng.randf_range(-0.1, 0.1), y + h, rng.randf_range(-0.1, 0.1))
		for k in n:
			var j := (k + 1) % n
			var p0: Vector3 = ring[k]
			var p1: Vector3 = ring[j]
			var q0: Vector3 = tipr[k]
			var q1: Vector3 = tipr[j]
			var o0 := (p0 - Vector3(0, y, 0)).normalized()
			var o1 := (p1 - Vector3(0, y, 0)).normalized()
			var n0 := (o0 + Vector3(0, 0.55, 0)).normalized()
			var n1 := (o1 + Vector3(0, 0.55, 0)).normalized()
			var t := float((k * 7 + i * 3) % 10) / 10.0
			# fascia bassa (ramo che ricade) più scura, fascia alta verso la punta più chiara
			b.tri_s("foliage", p0, p1, q1, n0, n1, (n1 + Vector3.UP).normalized(), _leaf(base * 0.85, season, 0.3, t, true))
			b.tri_s("foliage", p0, q1, q0, n0, (n1 + Vector3.UP).normalized(), (n0 + Vector3.UP).normalized(), _leaf(base * 0.85, season, 0.3, t, true))
			b.tri_s("foliage", q0, q1, tip, (n0 + Vector3.UP).normalized(), (n1 + Vector3.UP).normalized(), Vector3.UP, _leaf(base * 1.05, season, 0.85, t, true))
		b.face("foliage", ring, base * 0.55, Vector3(0, y + 0.6, 0))
	b.sphere("foliage", Vector3(0, 13.0, 0), Vector3(0.35, 0.9, 0.35), 6, 3, _leaf(Color(0.15, 0.25, 0.13), season, 0.9, 0.5, true))

static func _broadleaf(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	var bk := _bark(season)
	b.cyl("matte", 0.38, 0.24, 4.6, 8, Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0)), bk)
	b.cyl_ab("matte", Vector3(0, 3.8, 0), Vector3(1.6, 6.2, 0.3), 0.17, 0.07, 6, bk)
	b.cyl_ab("matte", Vector3(0, 4.2, 0), Vector3(-1.3, 6.5, -0.7), 0.16, 0.07, 6, bk)
	b.cyl_ab("matte", Vector3(0, 4.4, 0), Vector3(-0.2, 7.4, 1.2), 0.15, 0.06, 6, bk)
	var blobs := [[Vector3(0, 7.2, 0), 2.8], [Vector3(1.9, 6.4, 0.6), 2.1], [Vector3(-1.8, 6.6, -0.9), 2.2], [Vector3(0.3, 8.6, -0.4), 2.0],
		[Vector3(-0.5, 6.1, 1.8), 1.9], [Vector3(1.0, 5.6, -1.7), 1.7], [Vector3(-1.2, 8.0, 0.9), 1.6], [Vector3(1.4, 8.0, -1.0), 1.5]]
	for bl in blobs:
		var col := Color(0.17, 0.28, 0.09).lerp(Color(0.27, 0.37, 0.13), rng.randf()) * rng.randf_range(0.85, 1.05)
		_crown(b, bl[0], float(bl[1]), col, rng, 0.28, season, false)

## Ciuffo di chioma irregolare con ombreggiatura verticale e colori stagionali per faccia.
static func _crown(b: ModelKit, c: Vector3, r: float, col: Color, rng: RandomNumberGenerator, jit: float, season: String, conifer: bool) -> void:
	var seg := 9
	var rings := 6
	var G: Array = []
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / float(rings))
		var row: Array = []
		for s in seg:
			var lo := TAU * float(s) / float(seg) + (0.35 if i % 2 == 1 else 0.0)
			var u := Vector3(cos(lat) * cos(lo), sin(lat) * 0.82, cos(lat) * sin(lo))
			if i == 0 or i == rings:
				u = Vector3(0, signf(sin(lat)) * 0.82, 0)
			row.append(c + u * r * (1.0 + rng.randf_range(-jit, jit)))
		G.append(row)
	var tv := rng.randf()
	# colori e normali per vertice: la normale unisce quella del ciuffo e quella "radiale" dell'intera chioma (tronco = asse Y),
	# così i ciuffi si fondono in un'unica massa morbida invece di sembrare sfaccettati
	var NC: Array = []
	var CC: Array = []
	for i in rings + 1:
		var nrow: Array = []
		var crow: Array = []
		for s in seg:
			var p: Vector3 = G[i][s]
			var nb := (p - c).normalized()
			var rad := Vector3(p.x, 0.0, p.z)
			var nn := nb + (rad.normalized() * 0.55 if rad.length() > 0.05 else Vector3.ZERO) + Vector3(0, 0.15, 0)
			nrow.append(nn.normalized())
			var up := nb.y * 0.5 + 0.5
			var shade := 0.68 + 0.45 * float(i) / float(rings)
			crow.append(_leaf(col * shade, season, up, fmod(tv + float(s) * 0.13 + float(i) * 0.07, 1.0), conifer))
		NC.append(nrow)
		CC.append(crow)
	for i in rings:
		for s in seg:
			var s2 := (s + 1) % seg
			b.tri_c("foliage", G[i][s], G[i][s2], G[i + 1][s2], NC[i][s], NC[i][s2], NC[i + 1][s2], CC[i][s], CC[i][s2], CC[i + 1][s2])
			b.tri_c("foliage", G[i][s], G[i + 1][s2], G[i + 1][s], NC[i][s], NC[i + 1][s2], NC[i + 1][s], CC[i][s], CC[i + 1][s2], CC[i + 1][s])

## compatibilità: vecchio nome usato da altri stili
static func _lumpy(b: ModelKit, k: String, c: Vector3, r: float, col: Color, rng: RandomNumberGenerator, jit: float) -> void:
	var seg := 8
	var rings := 5
	var G: Array = []
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / float(rings))
		var row: Array = []
		for s in seg:
			var lo := TAU * float(s) / float(seg) + (0.4 if i % 2 == 1 else 0.0)
			var u := Vector3(cos(lat) * cos(lo), sin(lat) * 0.85, cos(lat) * sin(lo))
			if i == 0 or i == rings:
				u = Vector3(0, signf(sin(lat)) * 0.85, 0)
			row.append(c + u * r * (1.0 + rng.randf_range(-jit, jit)))
		G.append(row)
	for i in rings:
		for s in seg:
			var s2 := (s + 1) % seg
			var a: Vector3 = G[i][s]
			var bb: Vector3 = G[i][s2]
			var cc: Vector3 = G[i + 1][s2]
			var d: Vector3 = G[i + 1][s]
			var shade := 0.82 + 0.3 * float(i) / float(rings)
			b.tri_s(k, a, bb, cc, (a - c).normalized(), (bb - c).normalized(), (cc - c).normalized(), col * shade)
			b.tri_s(k, a, cc, d, (a - c).normalized(), (cc - c).normalized(), (d - c).normalized(), col * shade)

static func _birch(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	var white := Color(0.78, 0.76, 0.7)
	b.cyl("matte", 0.2, 0.12, 9.0, 8, Transform3D(Basis.IDENTITY, Vector3(0, 4.5, 0)), white)
	for i in 6:
		b.cyl("matte", 0.205, 0.2, 0.18, 8, Transform3D(Basis.IDENTITY, Vector3(0, 1.0 + i * 1.3 + rng.randf() * 0.4, 0)), Color(0.12, 0.11, 0.1))
	for i in 5:
		var a := rng.randf() * TAU
		var y := rng.randf_range(4.0, 7.0)
		b.cyl_ab("matte", Vector3(0, y, 0), Vector3(cos(a) * 1.4, y + 1.4, sin(a) * 1.4), 0.07, 0.03, 4, white * 0.9)
	var blobs := [[Vector3(0, 8.6, 0), 1.8], [Vector3(0.9, 7.4, 0.4), 1.5], [Vector3(-0.9, 7.1, -0.5), 1.5], [Vector3(0.2, 6.2, 0.9), 1.3], [Vector3(-0.3, 9.8, 0.2), 1.2]]
	for bl in blobs:
		_crown(b, bl[0], float(bl[1]), Color(0.3, 0.4, 0.14) * rng.randf_range(0.9, 1.1), rng, 0.3, season, false)

static func _cypress(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	b.cyl("matte", 0.22, 0.1, 3.0, 6, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), _bark(season))
	var sections := [[1.4, 1.0], [3.0, 1.35], [5.0, 1.4], [7.0, 1.2], [8.8, 0.9], [10.2, 0.5], [11.2, 0.15]]
	for i in sections.size() - 1:
		var y0: float = sections[i][0]
		var y1: float = sections[i + 1][0]
		var r0: float = sections[i][1]
		var r1: float = sections[i + 1][1]
		var col := Color(0.09, 0.17, 0.09) * rng.randf_range(0.9, 1.15)
		for k in 10:
			var a0 := TAU * float(k) / 10.0
			var a1 := TAU * float(k + 1) / 10.0
			var j0 := 1.0 + rng.randf_range(-0.12, 0.12)
			var p0 := Vector3(cos(a0) * r0 * j0, y0, sin(a0) * r0 * j0)
			var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var q1 := Vector3(cos(a1) * r1 * j0, y1, sin(a1) * r1 * j0)
			var n0 := Vector3(cos(a0), 0.25, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.25, sin(a1)).normalized()
			var up := 0.3 + 0.4 * float(r0 > r1)
			b.tri_s("foliage", p0, p1, q1, n0, n1, n1, _leaf(col, season, up, float(k) / 10.0, true))
			b.tri_s("foliage", p0, q1, q0, n0, n1, n0, _leaf(col, season, up, float(k) / 10.0, true))

static func _bush(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	for i in 4:
		var p := Vector3(rng.randf_range(-0.8, 0.8), 0.7 + rng.randf() * 0.3, rng.randf_range(-0.8, 0.8))
		_crown(b, p, rng.randf_range(0.8, 1.2), Color(0.18, 0.27, 0.1) * rng.randf_range(0.85, 1.1), rng, 0.3, season, false)

static func _palm(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	var pts: Array = []
	for i in 8:
		var f := float(i) / 7.0
		pts.append(Vector3(sin(f * 1.4) * 1.6, f * 10.0, 0))
	for i in 7:
		b.cyl_ab("matte", pts[i], pts[i + 1], lerpf(0.3, 0.2, float(i) / 7.0) * 1.08, lerpf(0.3, 0.2, float(i + 1) / 7.0), 7, BARK_GRAY * (0.9 if i % 2 == 0 else 1.05))
	var top: Vector3 = pts[7]
	for i in 11:
		var a := TAU * float(i) / 11.0 + rng.randf() * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		var L := rng.randf_range(4.0, 5.4)
		var col := Color(0.2, 0.33, 0.12) * rng.randf_range(0.85, 1.1)
		if season == "dry" and i % 3 == 0:
			col = Color(0.45, 0.38, 0.2)
		var prev_c := top
		var prev_w := 0.05
		for k in 6:
			var f := float(k + 1) / 6.0
			var cpt := top + d * L * f + Vector3(0, 1.0 * sin(f * 2.2) - 2.2 * f * f, 0)
			var w := 0.8 * sin(f * PI) + 0.05
			var mid := (prev_c + cpt) * 0.5 + Vector3(0, 0.12, 0)
			var n := Vector3.UP
			# foglia a V (nervatura centrale rialzata)
			b.tri_s("foliage", prev_c - side * prev_w, mid, cpt - side * w, n, n, n, _leaf(col * 0.9, season, 0.6, 0.5))
			b.tri_s("foliage", prev_c + side * prev_w, cpt + side * w, mid, n, n, n, _leaf(col, season, 0.6, 0.5))
			b.tri_s("foliage", prev_c - side * prev_w, prev_c + side * prev_w, mid, n, n, n, _leaf(col, season, 0.6, 0.5))
			b.tri_s("foliage", mid, cpt + side * w, cpt - side * w, n, n, n, _leaf(col * 0.95, season, 0.6, 0.5))
			prev_c = cpt
			prev_w = w
	for i in 4:
		var a := TAU * float(i) / 4.0
		b.sphere("matte", top + Vector3(cos(a) * 0.3, -0.35, sin(a) * 0.3), Vector3(0.16, 0.18, 0.16), 6, 3, Color(0.3, 0.24, 0.12))

static func _dead(b: ModelKit, rng: RandomNumberGenerator, season: String) -> void:
	var c := BARK_GRAY * 0.8
	b.cyl("matte", 0.32, 0.14, 7.0, 7, Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0)), c)
	for i in 7:
		var y := rng.randf_range(2.8, 6.2)
		var a := rng.randf() * TAU
		var L := rng.randf_range(1.4, 2.8) * (1.0 - (y - 2.8) / 6.0)
		var e := Vector3(cos(a) * L, y + L * rng.randf_range(0.4, 0.9), sin(a) * L)
		b.cyl_ab("matte", Vector3(0, y, 0), e, 0.1, 0.03, 5, c * 0.95)
		var e2 := e + Vector3(cos(a + 0.8) * L * 0.4, L * 0.35, sin(a + 0.8) * L * 0.4)
		b.cyl_ab("matte", e, e2, 0.035, 0.015, 4, c * 0.95)
		if season == "snow":
			b.cyl_ab("matte", Vector3(0, y + 0.08, 0), e + Vector3(0, 0.08, 0), 0.07, 0.025, 4, SNOW)

# ============================================================== rocce
const ROCK_STYLES := ["rock", "desert", "mountain", "arctic"]
static var _rock_mats := {}

## Masso irregolare (~2-4 m) in metri, origine a terra. style: "rock" (grigio con muschio), "desert" (arenaria stratificata),
## "mountain" (granito grigio-bruno, spigoloso), "arctic" (grigio scuro con neve sulle facce rivolte in alto).
## detail: suddivisioni dell'icosaedro (2 = 320 triangoli, 3 = 1280). Compatibile con la vecchia firma rock_mesh(rng).
static func rock_mesh(rng: RandomNumberGenerator, style: String = "rock", detail: int = 3) -> Mesh:
	var verts: Array = []
	var faces: Array = []
	_icosphere(clampi(detail, 1, 4), verts, faces)
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz.frequency = 0.9
	nz.fractal_type = FastNoiseLite.FRACTAL_RIDGED if style in ["mountain", "arctic"] else FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	nz.fractal_gain = 0.5
	var sx := rng.randf_range(1.0, 1.9)
	var sz := rng.randf_range(0.9, 1.5)
	var sy := rng.randf_range(0.6, 1.0) * (1.25 if style == "mountain" else 1.0)
	if style == "desert":
		sy *= 0.8
	# piani di frattura: tagli netti che danno facce di roccia spaccata
	var cuts: Array = []
	for i in rng.randi_range(2, 4):
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1)).normalized()
		cuts.append([n, rng.randf_range(0.62, 0.85)])
	var P := PackedVector3Array()
	for v in verts:
		var u: Vector3 = v
		var d := 1.0 + 0.32 * nz.get_noise_3dv(u * 1.3) + 0.08 * nz.get_noise_3dv(u * 4.0 + Vector3(9, 3, 1))
		var p := u * d
		for c in cuts:
			var cn: Vector3 = c[0]
			var off: float = c[1]
			var dd := p.dot(cn) - off
			if dd > 0.0:
				p -= cn * dd * 0.85
		p = Vector3(p.x * sx, p.y * sy, p.z * sz)
		if style == "desert":
			# erosione a strati orizzontali (gradini)
			var band := 0.22
			var fy := p.y / band
			var st := floorf(fy) + smoothstep(0.75, 1.0, fy - floorf(fy))
			p.y = lerpf(p.y, st * band, 0.55)
			var rim := 1.0 - 0.06 * absf(sin(p.y * 14.0))
			p.x *= rim
			p.z *= rim
		p.y = maxf(p.y, -0.35 * sy) + 0.3 * sy
		P.append(p)
	# normali lisce accumulate
	var N := PackedVector3Array()
	N.resize(P.size())
	for f in faces:
		var a: Vector3 = P[f[0]]
		var b: Vector3 = P[f[1]]
		var c: Vector3 = P[f[2]]
		var fn := (b - a).cross(c - a)
		for k in 3:
			N[f[k]] += fn
	for i in N.size():
		N[i] = N[i].normalized()
	# colori per vertice
	var base: Color
	var alt: Color
	match style:
		"desert":
			base = Color(0.6, 0.42, 0.28)
			alt = Color(0.74, 0.58, 0.4)
		"mountain":
			base = Color(0.4, 0.38, 0.35)
			alt = Color(0.52, 0.5, 0.46)
		"arctic":
			base = Color(0.3, 0.31, 0.33)
			alt = Color(0.42, 0.43, 0.45)
		_:
			base = Color(0.38, 0.37, 0.34)
			alt = Color(0.5, 0.48, 0.44)
	var tint := rng.randf_range(0.88, 1.1)
	var C := PackedColorArray()
	for i in P.size():
		var p: Vector3 = P[i]
		var n: Vector3 = N[i]
		var t := 0.5 + 0.5 * nz.get_noise_3dv(p * 2.2 + Vector3(17, 0, 5))
		var col := base.lerp(alt, t) * tint
		if style == "desert":
			col = col.lerp(Color(0.5, 0.3, 0.2), 0.35 * (0.5 + 0.5 * sin(p.y * 9.0 + t * 2.0)))
		# cavità e base più scure (occlusione finta)
		var ao := clampf(0.55 + p.y / maxf(sy * 1.6, 0.1), 0.55, 1.0)
		col *= ao
		if style == "rock" and n.y > 0.55:
			col = col.lerp(Color(0.27, 0.32, 0.17), clampf((n.y - 0.55) * 2.2, 0.0, 0.7) * t)
		if style == "arctic" and n.y > 0.35:
			col = col.lerp(Color(0.9, 0.93, 0.97), clampf((n.y - 0.35) * 3.0 + (t - 0.5), 0.0, 1.0))
		if style == "mountain" and t > 0.7:
			col = col.lerp(Color(0.62, 0.6, 0.55), 0.4)   # venature chiare
		col.a = 1.0
		C.append(col)
	var idx := PackedInt32Array()
	for f in faces:
		var a: Vector3 = P[f[0]]
		var b: Vector3 = P[f[1]]
		var c: Vector3 = P[f[2]]
		var fn := (c - a).cross(b - a)
		# senso orario visto dall'esterno (convenzione Godot)
		if fn.dot(N[f[0]] + N[f[1]] + N[f[2]]) >= 0.0:
			idx.append(f[0]); idx.append(f[1]); idx.append(f[2])
		else:
			idx.append(f[0]); idx.append(f[2]); idx.append(f[1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = P
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, rock_material(style))
	m.set_meta("tris", idx.size() / 3)
	return m

## Materiale di roccia: colore per vertice × dettaglio triplanare + mappa di normali a grana fine.
static func rock_material(style: String = "rock") -> Material:
	if _rock_mats.has(style):
		return _rock_mats[style]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.88 if style != "arctic" else 0.75
	m.metallic_specular = 0.35
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = 31
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.035
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	nt.noise = nz
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.72, 0.72, 0.72), Color(0.95, 0.95, 0.95), Color(1.08, 1.08, 1.08)])
	nt.color_ramp = g
	m.albedo_texture = nt
	var nn := NoiseTexture2D.new()
	var nz2 := FastNoiseLite.new()
	nz2.seed = 77
	nz2.frequency = 0.05
	nz2.fractal_octaves = 4
	nn.noise = nz2
	nn.width = 256
	nn.height = 256
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 10.0
	m.normal_enabled = true
	m.normal_texture = nn
	m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 3.0
	m.uv1_scale = Vector3.ONE * 0.45
	_rock_mats[style] = m
	return m

static func _icosphere(level: int, verts: Array, faces: Array) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((p as Vector3).normalized())
	var F := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for l in level:
		var cache := {}
		var nf: Array = []
		for f in F:
			var m: Array = []
			for k in 3:
				var a: int = f[k]
				var b: int = f[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					verts.append(((verts[a] as Vector3) + (verts[b] as Vector3)).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			nf.append([f[0], m[0], m[2]])
			nf.append([f[1], m[1], m[0]])
			nf.append([f[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		F = nf
	faces.append_array(F)

# ============================================================== edifici (fase 2: più stili)
## Stili: "block" (palazzo con tetto tecnico), "office" (torre a vetri), "house", "garden" (villetta con giardino nel lotto),
## "industrial", "shed" (capannone ad arco), "station" (stazione di servizio), "ruin" (rovina bombardata).
## `size` = ingombro (x, altezza, z); per "garden" e "station" è il lotto intero.
const BUILDING_STYLES := ["block", "office", "house", "garden", "industrial", "shed", "station", "ruin"]

static func building(size: Vector3, style: String, rng: RandomNumberGenerator) -> Node3D:
	var b := ModelKit.new()
	match style:
		"house": _house(b, size, rng)
		"garden": _garden(b, size, rng)
		"industrial": _industrial(b, size, rng)
		"shed": _shed(b, size, rng)
		"station": _station(b, size, rng)
		"ruin": _ruin(b, size, rng)
		"office": _office(b, size, rng)
		_: _block(b, size, rng)
	var mi := MeshInstance3D.new()
	mi.name = "Building_" + style
	var m := b.commit()
	m.set_meta("tris", b.tri_count())
	mi.mesh = m
	var root := Node3D.new()
	root.name = "Building"
	root.add_child(mi)
	root.set_meta("tris", b.tri_count())
	root.set_meta("style", style)
	return root

## Impianti sul tetto piano a quota h dentro l'area (w × d): condizionatori con ventole, locale ascensore, antenne, parabole,
## serbatoio su tralicci, pannelli solari.
static func _roof_tech(b: ModelKit, w: float, d: float, h: float, wall: Color, rng: RandomNumberGenerator) -> void:
	var gray := Color(0.55, 0.55, 0.53)
	b.box("matte", Vector3(minf(3.2, w * 0.3), 2.8, minf(3.6, d * 0.3)), Vector3(w * 0.18, h + 1.4, d * 0.12), wall * 0.92)   # locale scale
	b.box("matte", Vector3(2.2, 1.6, 2.4), Vector3(w * 0.18 + 2.6, h + 0.8, d * 0.12), wall * 0.85)                           # locale ascensore
	for i in rng.randi_range(2, 5):
		var p := Vector3(rng.randf_range(-0.38, 0.38) * w, h, rng.randf_range(-0.38, 0.38) * d)
		b.box("metal", Vector3(1.4, 0.9, 1.1), p + Vector3(0, 0.45, 0), gray, 0.04)
		b.cyl("rubber", 0.42, 0.42, 0.06, 10, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.93, 0)), Color(0.08, 0.08, 0.08), true, false)
	if rng.randf() < 0.7:
		var p := Vector3(-w * 0.28, h, -d * 0.25)
		b.cyl_ab("metal", p, p + Vector3(0, 7.0, 0), 0.08, 0.04, 5, Color(0.6, 0.6, 0.6))
		for k in 3:
			b.cyl_ab("metal", p + Vector3(0, 2.0 + k * 1.8, 0), p + Vector3(0.9, 2.0 + k * 1.8, 0), 0.03, 0.03, 4, Color(0.6, 0.6, 0.6))
		b.box("matte", Vector3(0.3, 1.2, 0.15), p + Vector3(0.15, 5.0, 0.12), Color(0.85, 0.85, 0.82))
	for i in rng.randi_range(0, 3):
		var p := Vector3(rng.randf_range(-0.4, 0.4) * w, h + 0.6, rng.randf_range(0.2, 0.42) * d)
		b.sphere("paint", p, Vector3(0.45, 0.45, 0.12), 10, 3, Color(0.86, 0.86, 0.84), true, Basis(Vector3.RIGHT, -1.0) * Basis(Vector3.UP, rng.randf() * TAU))
		b.cyl_ab("metal", p - Vector3(0, 0.6, 0), p, 0.04, 0.04, 4, Color(0.4, 0.4, 0.4))
	if rng.randf() < 0.5:
		var p := Vector3(-w * 0.2, h, d * 0.25)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.cyl_ab("metal", p + Vector3(sx * 0.8, 0, sz * 0.8), p + Vector3(sx * 0.8, 2.0, sz * 0.8), 0.06, 0.06, 4, Color(0.3, 0.3, 0.3))
		b.cyl("metal", 1.2, 1.2, 1.8, 12, Transform3D(Basis.IDENTITY, p + Vector3(0, 2.9, 0)), Color(0.42, 0.38, 0.32))
		b.cyl("metal", 1.25, 0.2, 0.5, 12, Transform3D(Basis.IDENTITY, p + Vector3(0, 4.05, 0)), Color(0.38, 0.35, 0.3))
	elif w > 12.0:
		for r in 3:
			b.box("glass", Vector3(w * 0.4, 0.06, 1.1), Vector3(w * 0.05, h + 0.55, -d * 0.05 + r * 1.6), Color(0.08, 0.12, 0.22), 0.0, Basis(Vector3.RIGHT, -0.5))
			b.box("metal", Vector3(w * 0.4, 0.5, 0.06), Vector3(w * 0.05, h + 0.25, -d * 0.05 + r * 1.6 + 0.45), Color(0.4, 0.4, 0.4))

static func _block(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var tones := [Color(0.62, 0.6, 0.55), Color(0.55, 0.52, 0.47), Color(0.66, 0.62, 0.54), Color(0.5, 0.5, 0.5), Color(0.6, 0.55, 0.48), Color(0.58, 0.47, 0.4)]
	var wall: Color = tones[rng.randi() % tones.size()]
	var fh := 3.2
	var floors := maxi(1, int(s.y / fh))
	var h := float(floors) * fh + 0.6
	b.box("stained", Vector3(s.x, h, s.z), Vector3(0, h * 0.5, 0), wall)
	# zoccolo e marcapiani
	b.box("matte", Vector3(s.x + 0.1, 1.0, s.z + 0.1), Vector3(0, 0.5, 0), wall * 0.7)
	for f in range(1, floors):
		b.box("matte", Vector3(s.x + 0.16, 0.18, s.z + 0.16), Vector3(0, f * fh + 0.25, 0), wall * 0.85)
	var frame := wall * 1.12
	_windows(b, Vector3(0, 0, -s.z * 0.5), Vector3(0, 0, -1), s.x, 0.25, floors, fh, 1.4, 1.6, 3.0, rng, frame)
	_windows(b, Vector3(0, 0, s.z * 0.5), Vector3(0, 0, 1), s.x, 0.25, floors, fh, 1.4, 1.6, 3.0, rng, frame)
	_windows(b, Vector3(-s.x * 0.5, 0, 0), Vector3(-1, 0, 0), s.z, 0.25, floors, fh, 1.4, 1.6, 3.0, rng, frame)
	_windows(b, Vector3(s.x * 0.5, 0, 0), Vector3(1, 0, 0), s.z, 0.25, floors, fh, 1.4, 1.6, 3.0, rng, frame)
	# balconi sulla facciata principale (metà dei palazzi)
	if rng.randf() < 0.5 and floors > 1:
		var cols := maxi(1, int(floor((s.x - 1.0) / 6.0)))
		for f in range(1, floors):
			for i in cols:
				var x := -float(cols - 1) * 3.0 + float(i) * 6.0
				var y := f * fh + 0.3
				b.box("matte", Vector3(4.2, 0.2, 1.3), Vector3(x, y, -s.z * 0.5 - 0.65), wall * 0.9)
				b.box("matte", Vector3(4.2, 0.9, 0.08), Vector3(x, y + 0.55, -s.z * 0.5 - 1.28), wall * 0.75)
	# negozi al piano terra con insegne e tende
	var shopc := [Color(0.55, 0.15, 0.12), Color(0.15, 0.3, 0.2), Color(0.2, 0.25, 0.4), Color(0.6, 0.45, 0.15)]
	for i in maxi(1, int(s.x / 7.0)):
		var x := -s.x * 0.5 + (float(i) + 0.5) * s.x / float(maxi(1, int(s.x / 7.0)))
		if absf(x) < 2.0:
			continue
		b.box("glass", Vector3(3.6, 2.2, 0.1), Vector3(x, 1.5, -s.z * 0.5 - 0.06), Color(0.12, 0.16, 0.18))
		b.box("matte", Vector3(4.0, 0.15, 1.2), Vector3(x, 2.95, -s.z * 0.5 - 0.55), shopc[rng.randi() % shopc.size()], 0.0, Basis(Vector3.RIGHT, 0.25))
	# porta d'ingresso con pensilina
	b.box("glass", Vector3(2.2, 2.4, 0.1), Vector3(0, 1.2, -s.z * 0.5 - 0.05), Color(0.05, 0.07, 0.08))
	b.box("matte", Vector3(3.2, 0.2, 1.4), Vector3(0, 2.7, -s.z * 0.5 - 0.7), wall * 0.8)
	# tetto: parapetto, guaina, impianti
	for sd: float in [-1.0, 1.0]:
		b.box("matte", Vector3(s.x + 0.2, 0.9, 0.25), Vector3(0, h + 0.45, sd * (s.z * 0.5 - 0.02)), wall * 0.9)
		b.box("matte", Vector3(0.25, 0.9, s.z), Vector3(sd * (s.x * 0.5 - 0.02), h + 0.45, 0), wall * 0.9)
	b.box("stained", Vector3(s.x - 0.4, 0.05, s.z - 0.4), Vector3(0, h + 0.03, 0), Color(0.3, 0.3, 0.29))
	_roof_tech(b, s.x, s.z, h, wall, rng)

## Torre per uffici con facciata continua a vetri, fasce di piano e coronamento tecnico.
static func _office(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var fh := 3.6
	var floors := maxi(3, int(s.y / fh))
	var h := float(floors) * fh
	var glass := [Color(0.16, 0.24, 0.3), Color(0.12, 0.18, 0.2), Color(0.22, 0.27, 0.3)][rng.randi() % 3] as Color
	var frame := Color(0.62, 0.63, 0.64)
	b.box("matte", Vector3(s.x + 0.6, 4.2, s.z + 0.6), Vector3(0, 2.1, 0), Color(0.42, 0.42, 0.42))           # basamento
	b.box("glass", Vector3(s.x - 0.1, h - 4.2, s.z - 0.1), Vector3(0, 4.2 + (h - 4.2) * 0.5, 0), glass)
	for f in range(1, floors):
		b.box("matte", Vector3(s.x + 0.08, 0.35, s.z + 0.08), Vector3(0, f * fh + 0.6, 0), frame * 0.9)
	var nmx := int(s.x / 1.8)
	for i in nmx + 1:
		var x := -s.x * 0.5 + float(i) * s.x / float(nmx)
		for sd: float in [-1.0, 1.0]:
			b.box("metal", Vector3(0.1, h - 4.2, 0.12), Vector3(x, 4.2 + (h - 4.2) * 0.5, sd * (s.z * 0.5)), frame)
	var nmz := int(s.z / 1.8)
	for i in nmz + 1:
		var z := -s.z * 0.5 + float(i) * s.z / float(nmz)
		for sd: float in [-1.0, 1.0]:
			b.box("metal", Vector3(0.12, h - 4.2, 0.1), Vector3(sd * (s.x * 0.5), 4.2 + (h - 4.2) * 0.5, z), frame)
	b.box("glass", Vector3(s.x * 0.5, 3.0, 0.1), Vector3(0, 1.6, -s.z * 0.5 - 0.32), Color(0.1, 0.13, 0.15))
	b.box("matte", Vector3(s.x * 0.6, 0.3, 3.0), Vector3(0, 3.7, -s.z * 0.5 - 1.6), frame * 0.8)
	# coronamento: fascia piena e impianti
	b.box("matte", Vector3(s.x + 0.1, 1.6, s.z + 0.1), Vector3(0, h + 0.8, 0), frame * 0.85)
	_roof_tech(b, s.x * 0.8, s.z * 0.8, h + 1.6, frame * 0.8, rng)

static func _house(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var tones := [Color(0.82, 0.76, 0.62), Color(0.78, 0.66, 0.5), Color(0.86, 0.84, 0.78), Color(0.72, 0.6, 0.48), Color(0.75, 0.72, 0.62)]
	var wall: Color = tones[rng.randi() % tones.size()]
	var roofc := [Color(0.5, 0.24, 0.16), Color(0.42, 0.22, 0.17), Color(0.3, 0.29, 0.3)][rng.randi() % 3] as Color
	var hw := maxf(s.y - s.x * 0.3, 2.8)
	b.box("stained", Vector3(s.x, hw, s.z), Vector3(0, hw * 0.5, 0), wall)
	b.box("matte", Vector3(s.x + 0.08, 0.5, s.z + 0.08), Vector3(0, 0.25, 0), wall * 0.7)
	var floors := maxi(1, int(hw / 2.9))
	var shutter := [Color(0.2, 0.3, 0.2), Color(0.35, 0.22, 0.15), Color(0.25, 0.3, 0.38)][rng.randi() % 3] as Color
	for n in [Vector3(0, 0, -1), Vector3(0, 0, 1)]:
		_windows(b, n * s.z * 0.5, n, s.x, 0.1, floors, hw / float(floors), 1.0, 1.3, 2.4, rng, shutter)
	for n in [Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		_windows(b, n * s.x * 0.5, n, s.z, 0.1, floors, hw / float(floors), 1.0, 1.3, 2.6, rng, shutter)
	b.box("matte", Vector3(1.1, 2.1, 0.1), Vector3(s.x * 0.2, 1.05, -s.z * 0.5 - 0.04), Color(0.3, 0.2, 0.13))
	# tetto a due falde con sporto e tegole a file
	var rh := s.x * 0.32
	var ox := s.x * 0.5 + 0.4
	var t_old := b.t
	b.t = t_old * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	b.prism_x("matte", [Vector2(-ox, hw - 0.15), Vector2(0, hw + rh), Vector2(ox, hw - 0.15)], -s.z * 0.5 - 0.35, s.z * 0.5 + 0.35, roofc)
	b.prism_x("matte", [Vector2(-s.x * 0.5, hw), Vector2(0, hw + rh - 0.25), Vector2(s.x * 0.5, hw)], -s.z * 0.5, s.z * 0.5, wall * 0.95)
	var slope := atan2(rh + 0.15, ox)
	for k in 5:
		var f := (float(k) + 0.5) / 5.0
		for sd: float in [-1.0, 1.0]:
			var y := hw - 0.15 + (rh + 0.15) * (1.0 - f) + 0.02
			b.box("matte", Vector3(s.z + 0.7, 0.07, 0.1), Vector3(0, y + 0.02, sd * ox * f), roofc * 0.8, 0.0, Basis(Vector3.RIGHT, -sd * slope))
	b.t = t_old
	# comignolo
	b.box("matte", Vector3(0.7, 1.6, 0.7), Vector3(s.x * 0.25, hw + rh * 0.6, s.z * 0.2), wall * 0.8)

## Villetta al centro di un lotto con prato, siepe/recinzione, vialetto, albero, auto e tettoia.
static func _garden(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var lawn := Color(0.26, 0.33, 0.15) * rng.randf_range(0.85, 1.1)
	b.box("matte", Vector3(s.x, 0.08, s.z), Vector3(0, 0.04, 0), lawn)
	# recinzione: muretto e siepe
	var hedge := Color(0.16, 0.24, 0.1)
	for sd: float in [-1.0, 1.0]:
		b.box("matte", Vector3(0.6, 1.2, s.z - 0.6), Vector3(sd * (s.x * 0.5 - 0.3), 0.6, 0), hedge, 0.2)
		b.box("matte", Vector3(s.x, 0.6, 0.3), Vector3(0, 0.3, sd * (s.z * 0.5 - 0.15)), Color(0.7, 0.68, 0.62))
		if sd > 0.0:
			b.box("matte", Vector3(s.x - 0.6, 1.1, 0.5), Vector3(0, 0.75, sd * (s.z * 0.5 - 0.6)), hedge, 0.2)
	for i in int(s.x / 0.5):
		var x := -s.x * 0.5 + 0.25 + float(i) * 0.5
		if absf(x - s.x * 0.2) < 1.6:
			continue
		b.box("metal", Vector3(0.04, 0.8, 0.04), Vector3(x, 0.9, -s.z * 0.5 + 0.15), Color(0.15, 0.15, 0.15))
	# casa nel lotto
	var hs := Vector3(s.x * 0.55, minf(s.y, 8.5), s.z * 0.45)
	var old := b.t
	b.t = Transform3D(Basis.IDENTITY, Vector3(-s.x * 0.08, 0.08, s.z * 0.08))
	_house(b, hs, rng)
	b.t = old
	# vialetto e posto auto con tettoia
	b.box("matte", Vector3(2.6, 0.1, s.z * 0.3), Vector3(s.x * 0.2, 0.06, -s.z * 0.35), Color(0.52, 0.5, 0.46))
	var cp := Vector3(s.x * 0.33, 0.0, -s.z * 0.05)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.cyl_ab("metal", cp + Vector3(sx * 1.5, 0, sz * 2.4), cp + Vector3(sx * 1.5, 2.4, sz * 2.4), 0.06, 0.06, 5, Color(0.3, 0.3, 0.3))
	b.box("metal", Vector3(3.4, 0.1, 5.4), cp + Vector3(0, 2.45, 0), Color(0.35, 0.36, 0.36))
	_car(b, cp + Vector3(0, 0, 0.2), rng)
	# albero da giardino e cespugli
	var tc := cp + Vector3(-s.x * 0.62, 0, -s.z * 0.28)
	b.cyl_ab("matte", tc, tc + Vector3(0, 2.6, 0), 0.18, 0.12, 6, BARK)
	_lumpy(b, "foliage", tc + Vector3(0, 3.6, 0), 1.7, Color(0.2, 0.32, 0.12), rng, 0.2)
	for i in 3:
		_lumpy(b, "foliage", Vector3(rng.randf_range(-0.4, 0.4) * s.x, 0.5, -s.z * 0.38), 0.6, hedge * 1.2, rng, 0.25)

## Auto civile semplice (berlina, ~4.4 m).
static func _car(b: ModelKit, p: Vector3, rng: RandomNumberGenerator) -> void:
	var cc := [Color(0.6, 0.6, 0.62), Color(0.15, 0.17, 0.2), Color(0.45, 0.1, 0.08), Color(0.8, 0.8, 0.78), Color(0.2, 0.28, 0.4)][rng.randi() % 5] as Color
	b.box("paint_plain", Vector3(1.75, 0.6, 4.4), p + Vector3(0, 0.6, 0), cc, 0.15)
	b.hexa("paint_plain", [p + Vector3(-0.82, 0.88, -1.0), p + Vector3(0.82, 0.88, -1.0), p + Vector3(0.82, 0.88, 1.3), p + Vector3(-0.82, 0.88, 1.3),
		p + Vector3(-0.7, 1.4, -0.4), p + Vector3(0.7, 1.4, -0.4), p + Vector3(0.7, 1.4, 1.0), p + Vector3(-0.7, 1.4, 1.0)], cc)
	b.box("glass", Vector3(1.4, 0.4, 0.05), p + Vector3(0, 1.15, -0.72), Color(0.08, 0.1, 0.12), 0.0, Basis(Vector3.RIGHT, 0.75))
	for sd: float in [-1.0, 1.0]:
		b.box("glass", Vector3(0.05, 0.38, 1.3), p + Vector3(sd * 0.77, 1.12, 0.3), Color(0.08, 0.1, 0.12))
		for z: float in [-1.35, 1.35]:
			b.cyl("rubber", 0.32, 0.32, 0.22, 10, Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(sd * 0.8, 0.32, z)), Color(0.06, 0.06, 0.06))

static func _industrial(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var tones := [Color(0.42, 0.46, 0.5), Color(0.55, 0.53, 0.48), Color(0.45, 0.38, 0.3), Color(0.5, 0.52, 0.48)]
	var wall: Color = tones[rng.randi() % tones.size()]
	var h := maxf(s.y, 5.0)
	b.box("metal", Vector3(s.x, h, s.z), Vector3(0, h * 0.5, 0), wall)
	b.box("matte", Vector3(s.x + 0.1, 1.2, s.z + 0.1), Vector3(0, 0.6, 0), Color(0.5, 0.48, 0.44))
	var n := int(s.x / 1.2)
	for i in n:
		var x := -s.x * 0.5 + 0.6 + float(i) * (s.x - 1.2) / float(maxi(n - 1, 1))
		for sd: float in [-1.0, 1.0]:
			b.box("metal", Vector3(0.12, h - 1.2, 0.1), Vector3(x, 1.2 + (h - 1.2) * 0.5, sd * (s.z * 0.5 + 0.04)), wall * 0.85)
	var nz := int(s.z / 1.2)
	for i in nz:
		var z := -s.z * 0.5 + 0.6 + float(i) * (s.z - 1.2) / float(maxi(nz - 1, 1))
		for sd: float in [-1.0, 1.0]:
			b.box("metal", Vector3(0.1, h - 1.2, 0.12), Vector3(sd * (s.x * 0.5 + 0.04), 1.2 + (h - 1.2) * 0.5, z), wall * 0.85)
	var teeth := maxi(2, int(s.z / 7.0))
	var tz := s.z / float(teeth)
	for i in teeth:
		var z0 := -s.z * 0.5 + float(i) * tz
		b.prism_x("metal", [Vector2(z0, h), Vector2(z0, h + 2.2), Vector2(z0 + tz, h)], -s.x * 0.5, s.x * 0.5, Color(0.36, 0.37, 0.38))
		b.box("glass", Vector3(s.x - 0.4, 1.9, 0.06), Vector3(0, h + 1.05, z0 - 0.04), Color(0.2, 0.27, 0.3))
	for i in maxi(1, int(s.x / 12.0)):
		var x := -s.x * 0.5 + (float(i) + 0.5) * s.x / float(maxi(1, int(s.x / 12.0)))
		b.box("metal", Vector3(4.5, 4.5, 0.15), Vector3(x, 2.25, -s.z * 0.5 - 0.1), Color(0.55, 0.42, 0.18) if rng.randf() < 0.5 else Color(0.3, 0.33, 0.36))
		b.box("matte", Vector3(4.9, 0.3, 0.3), Vector3(x, 4.65, -s.z * 0.5 - 0.15), Color(0.2, 0.2, 0.2))
	b.box("glass", Vector3(s.x * 0.85, 0.9, 0.06), Vector3(0, h - 1.2, s.z * 0.5 + 0.1), Color(0.18, 0.24, 0.28))
	if rng.randf() < 0.8:
		var cx := s.x * 0.5 + 2.0
		b.cyl("matte", 1.2, 0.9, h * 2.6, 12, Transform3D(Basis.IDENTITY, Vector3(cx, h * 1.3, s.z * 0.3)), Color(0.55, 0.36, 0.28))
		for k in 2:
			b.cyl("matte", 1.0 - k * 0.05, 0.98 - k * 0.05, 1.2, 12, Transform3D(Basis.IDENTITY, Vector3(cx, h * 2.6 - 1.0 - k * 2.6, s.z * 0.3)), Color(0.85, 0.85, 0.82) if k == 0 else Color(0.65, 0.2, 0.15))
	if rng.randf() < 0.6:
		b.cyl("metal", 2.4, 2.4, h * 1.4, 14, Transform3D(Basis.IDENTITY, Vector3(-s.x * 0.5 - 3.0, h * 0.7, -s.z * 0.2)), Color(0.62, 0.63, 0.62))
		b.cyl("metal", 2.4, 0.4, 1.2, 14, Transform3D(Basis.IDENTITY, Vector3(-s.x * 0.5 - 3.0, h * 1.4 + 0.6, -s.z * 0.2)), Color(0.55, 0.56, 0.55))

## Capannone con tetto a botte in lamiera, portone scorrevole, banchina di carico e container.
static func _shed(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var col := [Color(0.5, 0.52, 0.48), Color(0.45, 0.4, 0.32), Color(0.38, 0.42, 0.45), Color(0.55, 0.5, 0.4)][rng.randi() % 4] as Color
	var hw := maxf(s.y * 0.6, 4.0)
	var r := s.z * 0.5
	var rise := minf(r * 0.45, s.y * 0.5)
	var prof: Array = [Vector2(-r, 0.0), Vector2(r, 0.0)]
	for i in 13:
		var a := float(i) / 12.0
		var z := r - 2.0 * r * a
		prof.append(Vector2(z, hw + rise * sqrt(maxf(0.0, 1.0 - (z / r) * (z / r)))))
	b.prism_x("metal", prof, -s.x * 0.5, s.x * 0.5, col)
	# nervature della lamiera sull'arco
	for i in int(s.x / 1.5):
		var x := -s.x * 0.5 + 0.75 + float(i) * 1.5
		for k in 12:
			var p0: Vector2 = prof[2 + k]
			var p1: Vector2 = prof[3 + k]
			b.cyl_ab("metal", Vector3(x, p0.y + 0.05, p0.x), Vector3(x, p1.y + 0.05, p1.x), 0.05, 0.05, 3, col * 0.8, false)
	b.box("matte", Vector3(s.x + 0.1, 1.0, s.z + 0.1), Vector3(0, 0.5, 0), Color(0.48, 0.46, 0.42))
	# portone sul timpano e lucernari
	b.box("metal", Vector3(0.15, hw * 0.85, s.z * 0.45), Vector3(-s.x * 0.5 - 0.08, hw * 0.43, 0), Color(0.3, 0.32, 0.33))
	for k in 6:
		b.box("metal", Vector3(0.18, 0.06, s.z * 0.45), Vector3(-s.x * 0.5 - 0.1, 0.5 + k * hw * 0.14, 0), Color(0.22, 0.24, 0.25))
	b.box("glass", Vector3(s.x * 0.8, 0.06, 1.0), Vector3(0, hw + rise + 0.05, 0), Color(0.25, 0.3, 0.32))
	# banchina di carico e container
	b.box("matte", Vector3(s.x * 0.6, 1.2, 3.0), Vector3(0, 0.6, -s.z * 0.5 - 1.5), Color(0.5, 0.49, 0.46))
	for i in 3:
		b.box("metal", Vector3(3.0, 3.2, 0.15), Vector3(-s.x * 0.2 + i * s.x * 0.2, 1.6, -s.z * 0.5 - 0.08), Color(0.32, 0.34, 0.35))
	var cc := [Color(0.55, 0.2, 0.12), Color(0.15, 0.3, 0.45), Color(0.6, 0.48, 0.15), Color(0.25, 0.4, 0.25)]
	for i in rng.randi_range(1, 3):
		var p := Vector3(s.x * 0.5 + 2.0, 1.3 + float(i / 2) * 2.6, -s.z * 0.3 + float(i % 2) * 2.6)
		var ccol: Color = cc[rng.randi() % cc.size()]
		b.box("metal", Vector3(6.0, 2.55, 2.45), p, ccol, 0.03)
		for k in 9:
			b.box("metal", Vector3(0.06, 2.4, 2.5), p + Vector3(-2.8 + k * 0.7, 0, 0), ccol * 0.75)

## Stazione di servizio: piazzale, pensilina su pilastri con fascia colorata, isole con erogatori, chiosco, cartello prezzi.
static func _station(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var brand := [Color(0.7, 0.12, 0.1), Color(0.1, 0.45, 0.25), Color(0.85, 0.6, 0.1), Color(0.12, 0.3, 0.6)][rng.randi() % 4] as Color
	b.box("stained", Vector3(s.x, 0.12, s.z), Vector3(0, 0.06, 0), Color(0.45, 0.45, 0.43))
	var cw := s.x * 0.6
	var cd := s.z * 0.45
	var cp := Vector3(-s.x * 0.12, 0, -s.z * 0.15)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box("paint_plain", Vector3(0.5, 5.0, 0.5), cp + Vector3(sx * cw * 0.32, 2.5, sz * cd * 0.3), Color(0.85, 0.85, 0.83))
	b.box("paint_plain", Vector3(cw, 0.5, cd), cp + Vector3(0, 5.25, 0), Color(0.9, 0.9, 0.88))
	b.box("paint_plain", Vector3(cw + 0.06, 0.32, cd + 0.06), cp + Vector3(0, 5.3, 0), brand)
	b.box("light", Vector3(cw - 0.6, 0.04, cd - 0.6), cp + Vector3(0, 4.98, 0), Color(1, 0.98, 0.9))
	for k in 2:
		var ip := cp + Vector3((float(k) - 0.5) * cw * 0.5, 0, 0)
		b.box("matte", Vector3(1.2, 0.25, cd * 0.6), ip + Vector3(0, 0.18, 0), Color(0.62, 0.6, 0.55))
		for j in 2:
			var pp := ip + Vector3(0, 0.3, (float(j) - 0.5) * cd * 0.3)
			b.box("paint_plain", Vector3(0.7, 1.7, 0.5), pp + Vector3(0, 0.85, 0), Color(0.85, 0.85, 0.83), 0.05)
			b.box("paint_plain", Vector3(0.72, 0.35, 0.52), pp + Vector3(0, 1.5, 0), brand)
			b.box("glass", Vector3(0.5, 0.3, 0.53), pp + Vector3(0, 1.05, 0), Color(0.1, 0.13, 0.15))
	# chiosco
	var kp := Vector3(s.x * 0.3, 0, s.z * 0.2)
	b.box("stained", Vector3(s.x * 0.3, 3.4, s.z * 0.35), kp + Vector3(0, 1.7, 0), Color(0.82, 0.8, 0.76))
	b.box("glass", Vector3(s.x * 0.26, 2.2, 0.08), kp + Vector3(0, 1.4, -s.z * 0.175 - 0.04), Color(0.12, 0.16, 0.18))
	b.box("paint_plain", Vector3(s.x * 0.31, 0.5, s.z * 0.36), kp + Vector3(0, 3.2, 0), brand)
	_roof_tech(b, s.x * 0.2, s.z * 0.25, 3.4, Color(0.7, 0.7, 0.68), rng)
	# cartello dei prezzi
	var sp := Vector3(-s.x * 0.42, 0, -s.z * 0.42)
	b.box("metal", Vector3(0.3, 6.0, 0.3), sp + Vector3(0, 3.0, 0), Color(0.3, 0.3, 0.3))
	b.box("paint_plain", Vector3(2.0, 3.0, 0.3), sp + Vector3(0, 6.5, 0), Color(0.9, 0.9, 0.88))
	b.box("paint_plain", Vector3(2.04, 0.9, 0.34), sp + Vector3(0, 7.5, 0), brand)
	for k in 3:
		b.box("rubber", Vector3(1.6, 0.4, 0.34), sp + Vector3(0, 5.4 + k * 0.55, 0), Color(0.05, 0.05, 0.05))
	_car(b, cp + Vector3(-cw * 0.12, 0.12, cd * 0.12), rng)

## Rovina bombardata: muri perimetrali spezzati ad altezze irregolari, solai crollati, macerie, ferri d'armatura, annerimenti.
static func _ruin(b: ModelKit, s: Vector3, rng: RandomNumberGenerator) -> void:
	var wall := [Color(0.55, 0.53, 0.5), Color(0.6, 0.55, 0.47), Color(0.5, 0.49, 0.47)][rng.randi() % 3] as Color
	var soot := Color(0.12, 0.11, 0.1)
	var fh := 3.2
	var hmax := maxf(s.y, 4.0)
	b.box("stained", Vector3(s.x, 0.3, s.z), Vector3(0, 0.15, 0), wall * 0.6)
	var seg := 1.6
	for side in 4:
		var along_x := side < 2
		var L := s.x if along_x else s.z
		var n := maxi(2, int(L / seg))
		var sw := L / float(n)
		var hprev := hmax * rng.randf_range(0.3, 1.0)
		for i in n:
			var hh := clampf(hprev + rng.randf_range(-0.35, 0.35) * hmax, 0.4, hmax)
			if rng.randf() < 0.15:
				hh = rng.randf_range(0.3, 1.2)
			hprev = hh
			var off := -L * 0.5 + (float(i) + 0.5) * sw
			var p: Vector3
			var sz: Vector3
			if along_x:
				p = Vector3(off, hh * 0.5, (s.z * 0.5 - 0.2) * (1.0 if side == 0 else -1.0))
				sz = Vector3(sw + 0.02, hh, 0.4)
			else:
				p = Vector3((s.x * 0.5 - 0.2) * (1.0 if side == 2 else -1.0), hh * 0.5, off)
				sz = Vector3(0.4, hh, sw + 0.02)
			# vani finestra: la colonna è più bassa o mostra un'apertura a ogni piano
			var c := wall * rng.randf_range(0.85, 1.05)
			b.box("stained", sz, p, c)
			if i % 2 == 1 and hh > fh:
				for f in int(hh / fh):
					var wp := p + Vector3(0, -hh * 0.5 + f * fh + 1.6, 0)
					var nn := Vector3(0, 0, signf(p.z)) if along_x else Vector3(signf(p.x), 0, 0)
					b.box("rubber", Vector3(sw * 0.6, 1.4, 0.06) if along_x else Vector3(0.06, 1.4, sw * 0.6), wp + nn * 0.21, Color(0.04, 0.04, 0.04))
					b.box("rubber", Vector3(sw * 0.6, 1.4, 0.06) if along_x else Vector3(0.06, 1.4, sw * 0.6), wp - nn * 0.21, Color(0.04, 0.04, 0.04))
			# bruciature sopra le aperture e ferri sporgenti
			if rng.randf() < 0.4:
				b.box("matte", sz * Vector3(1.01, 0.35, 1.01) + Vector3(0, 0, 0), p + Vector3(0, hh * 0.3, 0), soot)
			if rng.randf() < 0.35:
				var top := p + Vector3(0, hh * 0.5, 0)
				for k in 3:
					var o := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.1, 0.1))
					if not along_x:
						o = Vector3(o.z, 0, o.x)
					b.cyl_ab("metal", top + o, top + o + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.5, 1.1), rng.randf_range(-0.3, 0.3)), 0.025, 0.02, 3, Color(0.3, 0.18, 0.1))
	# solai crollati inclinati
	for f in mini(2, int(hmax / fh)):
		var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35)) * Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25))
		b.box("stained", Vector3(s.x * rng.randf_range(0.4, 0.7), 0.3, s.z * rng.randf_range(0.4, 0.7)), Vector3(rng.randf_range(-0.15, 0.15) * s.x, fh * (f + 1) * 0.55, rng.randf_range(-0.15, 0.15) * s.z), wall * 0.75, 0.0, tilt)
	# cumuli di macerie
	for i in int(s.x * s.z / 18.0) + 3:
		var p := Vector3(rng.randf_range(-0.55, 0.55) * s.x, 0.3, rng.randf_range(-0.55, 0.55) * s.z)
		_lumpy(b, "matte", p, rng.randf_range(0.8, 2.0), (wall * rng.randf_range(0.5, 0.9)).lerp(soot, rng.randf() * 0.4), rng, 0.35)
	for i in 14:
		var p := Vector3(rng.randf_range(-0.7, 0.7) * s.x, 0.25, rng.randf_range(-0.7, 0.7) * s.z)
		b.box("stained", Vector3(rng.randf_range(0.4, 1.4), rng.randf_range(0.2, 0.5), rng.randf_range(0.4, 1.0)), p, wall * rng.randf_range(0.6, 0.95), 0.05,
			Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)))

## Finestre su una facciata. `n` = normale esterna (asse X o Z), `w` = larghezza facciata, centro facciata `c`.
static func _windows(b: ModelKit, c: Vector3, n: Vector3, w: float, y0: float, floors: int, fh: float, ww: float, wh: float, step: float, rng: RandomNumberGenerator, frame: Color) -> void:
	var t := Vector3(-n.z, 0, n.x)
	var cols := maxi(1, int(floor((w - 1.0) / step)))
	var span := float(cols - 1) * step
	for f in floors:
		for i in cols:
			var off := -span * 0.5 + float(i) * step
			var p := c + t * off + Vector3(0, y0 + fh * float(f) + fh * 0.55, 0) + n * 0.04
			var gc := Color(0.08, 0.11, 0.14).lerp(Color(0.32, 0.4, 0.45), rng.randf() * 0.6)
			var sz := Vector3(ww, wh, 0.08) if absf(n.z) > 0.5 else Vector3(0.08, wh, ww)
			if rng.randf() < 0.06:
				gc = Color(0.02, 0.02, 0.02)   # vetro rotto
			b.box("glass", sz, p, gc)
			var sill := Vector3(ww + 0.3, 0.12, 0.25) if absf(n.z) > 0.5 else Vector3(0.25, 0.12, ww + 0.3)
			b.box("matte", sill, p + Vector3(0, -wh * 0.5 - 0.06, 0) + n * 0.06, frame)

# ============================================================== cratere
static func crater() -> Node3D:
	if _crater_mesh == null:
		var b := ModelKit.new()
		var R := 3.0
		var seg := 16
		var rings := [[0.0, 0.03], [0.35, 0.05], [0.7, 0.12], [0.95, 0.42], [1.12, 0.4], [1.4, 0.14], [1.8, 0.0]]
		var cols := [Color(0.07, 0.06, 0.05), Color(0.09, 0.08, 0.06), Color(0.14, 0.12, 0.09), Color(0.28, 0.23, 0.17), Color(0.3, 0.25, 0.18), Color(0.25, 0.21, 0.15), Color(0.24, 0.21, 0.16)]
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var G: Array = []
		for r in rings.size():
			var row: Array = []
			for s in seg:
				var a := TAU * float(s) / float(seg)
				var rr: float = float(rings[r][0]) * R * (1.0 + (rng.randf_range(-0.12, 0.12) if r > 0 and r < rings.size() - 1 else 0.0))
				var y: float = float(rings[r][1]) + (rng.randf_range(-0.06, 0.08) if r > 0 and r < rings.size() - 1 else 0.0)
				row.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			G.append(row)
		for r in rings.size() - 1:
			for s in seg:
				var s2 := (s + 1) % seg
				var p := [G[r][s], G[r][s2], G[r + 1][s2], G[r + 1][s]]
				var col: Color = cols[r]
				var n := ((p[2] as Vector3) - (p[0] as Vector3)).cross((p[1] as Vector3) - (p[0] as Vector3))
				var below: Vector3 = (p[0] as Vector3) - (n.normalized() * (1.0 if n.y > 0 else -1.0))
				b.face("matte", [p[0], p[1], p[2]], col, below)
				b.face("matte", [p[0], p[2], p[3]], col, below)
		for i in 7:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(1.05, 1.7) * R
			b.box("matte", Vector3(0.3, 0.2, 0.25) * rng.randf_range(0.6, 1.4), Vector3(cos(a) * rr, 0.12, sin(a) * rr), Color(0.2, 0.17, 0.13), 0.04, Basis(Vector3.UP, rng.randf() * TAU))
		_crater_mesh = b.commit()
		_crater_mesh.set_meta("tris", b.tri_count())
	var mi := MeshInstance3D.new()
	mi.name = "Crater"
	mi.mesh = _crater_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
