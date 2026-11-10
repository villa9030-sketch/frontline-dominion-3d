class_name NavalModels
extends RefCounted
## Navi generate in codice (Agente F2), usate da UnitModels.build("ship"|"transport").
## Origine = linea di galleggiamento al centro nave, avanti = -Z, metri reali.
## Lo scafo è un loft di sezioni (carena rossa antivegetativa, fascia nera di bagnasciuga, opera morta grigia),
## con cavallino (prua più alta), svasatura a prua e specchio di poppa piatto.

const HAZE := Color(0.44, 0.47, 0.5)
const HAZE_D := Color(0.37, 0.4, 0.43)
const HAZE_L := Color(0.52, 0.55, 0.57)
const DECK := Color(0.24, 0.25, 0.26)
const ANTIFOUL := Color(0.34, 0.12, 0.09)
const BOOT := Color(0.05, 0.05, 0.05)
const DARK := Color(0.09, 0.09, 0.09)
const GUNMETAL := Color(0.2, 0.2, 0.21)
const GLASS := Color(0.06, 0.1, 0.13)
const WHITE := Color(0.84, 0.84, 0.81)
const RUST := Color(0.32, 0.2, 0.13)
const SEG_COL := [0, 0, 0, 0, 1, 2, 2, 3, 2]   # colore di ogni segmento della sezione: 0 carena, 1 bagnasciuga, 2 scafo, 3 fascia

# ============================================================== scafo
## Sezione (metà destra, x >= 0): dalla chiglia al trincarino. B = mezza larghezza in coperta, Bw = al galleggiamento,
## D = altezza della coperta, K = pescaggio.
static func _profile(B: float, Bw: float, D: float, K: float) -> Array:
	return [Vector2(0, -K), Vector2(Bw * 0.45, -K * 0.97), Vector2(Bw * 0.8, -K * 0.8), Vector2(Bw * 0.97, -maxf(K * 0.4, 0.7)), Vector2(Bw, -0.4),
		Vector2(lerpf(Bw, B, 0.06), 0.6), Vector2(lerpf(Bw, B, 0.55), D * 0.5), Vector2(lerpf(Bw, B, 0.93), D - 1.1),
		Vector2(lerpf(Bw, B, 0.97), D - 0.55), Vector2(B, D)]

static func _cr(a: float, b: float, c: float, d: float, t: float) -> float:
	var t2 := t * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t2 * t)

## Stazioni dense interpolate (Catmull-Rom) dalle stazioni chiave [z, B, Bw, D, K].
static func stations(keys: Array, step: float) -> Array:
	var out: Array = []
	var n := keys.size()
	for i in n - 1:
		var z0: float = keys[i][0]
		var z1: float = keys[i + 1][0]
		var cnt := maxi(1, int(ceil((z1 - z0) / step)))
		for k in cnt:
			var t := float(k) / float(cnt)
			var row: Array = [lerpf(z0, z1, t)]
			for c in range(1, 5):
				var a: float = keys[maxi(i - 1, 0)][c]
				var b: float = keys[i][c]
				var cc: float = keys[i + 1][c]
				var d: float = keys[mini(i + 2, n - 1)][c]
				row.append(maxf(_cr(a, b, cc, d, t), 0.0))
			out.append(row)
	out.append(keys[n - 1].duplicate())
	return out

## Valore interpolato di una colonna delle stazioni in z (1 = B, 3 = D).
static func at(st: Array, z: float, col: int) -> float:
	if z <= float(st[0][0]):
		return float(st[0][col])
	for i in st.size() - 1:
		var z0: float = st[i][0]
		var z1: float = st[i + 1][0]
		if z <= z1:
			return lerpf(float(st[i][col]), float(st[i + 1][col]), (z - z0) / maxf(z1 - z0, 0.001))
	return float(st[st.size() - 1][col])

static func hull(b: ModelKit, st: Array, hc: Color, dc: Color, band_z: Vector2, lod: int) -> void:
	var P: Array = []
	for s in st:
		var pr := _profile(s[1], s[2], s[3], s[4])
		var row: Array = []
		for q in pr:
			row.append(Vector3(q.x, q.y, float(s[0])))
		P.append(row)
	var n := P.size()
	var m: int = (P[0] as Array).size()
	var N: Array = []
	for i in n:
		var nrow: Array = []
		for j in m:
			var a: Vector3 = P[maxi(i - 1, 0)][j]
			var c: Vector3 = P[mini(i + 1, n - 1)][j]
			var d: Vector3 = P[i][maxi(j - 1, 0)]
			var e: Vector3 = P[i][mini(j + 1, m - 1)]
			var nn := (c - a).cross(e - d)
			var p: Vector3 = P[i][j]
			var outv := Vector3(p.x + 0.01, p.y - float(st[i][3]) * 0.3, 0.0)
			if nn.dot(outv) < 0.0:
				nn = -nn
			if nn.length_squared() < 1e-8:
				nn = outv
			nrow.append(nn.normalized())
		N.append(nrow)
	var cols := [ANTIFOUL, BOOT, hc, b.fac]
	for sd: float in [1.0, -1.0]:
		var f := Vector3(sd, 1, 1)
		for i in n - 1:
			var zc := (float(st[i][0]) + float(st[i + 1][0])) * 0.5
			for j in m - 1:
				var ci: int = SEG_COL[j]
				if ci == 3 and (zc < band_z.x or zc > band_z.y):
					ci = 2
				var k := "matte" if ci < 2 else ("faction" if ci == 3 else "stained")
				var col: Color = cols[ci]
				if ci == 2:
					col = hc * (0.96 + 0.06 * float(j) / float(m))
				var p00: Vector3 = (P[i][j] as Vector3) * f
				var p01: Vector3 = (P[i][j + 1] as Vector3) * f
				var p10: Vector3 = (P[i + 1][j] as Vector3) * f
				var p11: Vector3 = (P[i + 1][j + 1] as Vector3) * f
				var n00: Vector3 = (N[i][j] as Vector3) * f
				var n01: Vector3 = (N[i][j + 1] as Vector3) * f
				var n10: Vector3 = (N[i + 1][j] as Vector3) * f
				var n11: Vector3 = (N[i + 1][j + 1] as Vector3) * f
				b.tri_s(k, p00, p10, p11, n00, n10, n11, col)
				b.tri_s(k, p00, p11, p01, n00, n11, n01, col)
	# coperta
	for i in n - 1:
		var s0: Array = st[i]
		var s1: Array = st[i + 1]
		var B0: float = s0[1]
		var B1: float = s1[1]
		b.face("matte", [Vector3(-B0, s0[3], s0[0]), Vector3(B0, s0[3], s0[0]), Vector3(B1, s1[3], s1[0]), Vector3(-B1, s1[3], s1[0])],
			dc, Vector3(0, float(s0[3]) - 1.0, (float(s0[0]) + float(s1[0])) * 0.5))
		if lod == 0:
			# battagliola: corrimano e candelieri
			for sd: float in [-1.0, 1.0]:
				var a := Vector3(sd * (B0 - 0.1), float(s0[3]) + 1.0, s0[0])
				var e := Vector3(sd * (B1 - 0.1), float(s1[3]) + 1.0, s1[0])
				b.cyl_ab("metal", a, e, 0.03, 0.03, 3, HAZE_L, false)
				if i % 2 == 0:
					b.cyl_ab("metal", a - Vector3(0, 1.0, 0), a, 0.03, 0.03, 3, HAZE_L, false)
	# specchio di poppa e dritto di prua
	for end: int in [0, n - 1]:
		var s: Array = st[end]
		var pr := _profile(s[1], s[2], s[3], s[4])
		var z: float = s[0]
		var ctr := Vector3(0, (float(s[3]) - float(s[4])) * 0.5, z)
		var ins := ctr + Vector3(0, 0, 1.0 if end == 0 else -1.0)
		for j in pr.size() - 1:
			var q0: Vector2 = pr[j]
			var q1: Vector2 = pr[j + 1]
			var ci: int = SEG_COL[j]
			b.face("matte" if ci < 2 else "paint", [Vector3(-q0.x, q0.y, z), Vector3(q0.x, q0.y, z), Vector3(q1.x, q1.y, z), Vector3(-q1.x, q1.y, z)],
				[ANTIFOUL, BOOT, hc * 0.92, hc * 0.92][ci], ins)

# ============================================================== dettagli comuni
## Pannello ottagonale (radar a scansione elettronica) centrato in `c`, rivolto verso `nrm` (orizzontale).
static func _octa(b: ModelKit, c: Vector3, nrm: Vector3, r: float, col: Color) -> void:
	var nn := nrm.normalized()
	var tg := Vector3.UP.cross(nn).normalized()
	var pts: Array = []
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	var front: Array = []
	var back: Array = []
	for p in pts:
		front.append(c + tg * p.x + Vector3.UP * p.y + nn * 0.12)
		back.append(c + tg * p.x + Vector3.UP * p.y - nn * 0.05)
	b.face("paint", front, col, c - nn)
	for i in 8:
		var j := (i + 1) % 8
		b.face("paint", [front[i], back[i], back[j], front[j]], col * 0.85, c - nn * 0.02)

static func _ciws(b: ModelKit, p: Vector3, yaw: float) -> void:
	b.cyl("paint", 0.9, 0.95, 1.2, 12, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6, 0)), HAZE_D)
	b.cyl("paint", 0.75, 0.75, 1.3, 12, Transform3D(Basis.IDENTITY, p + Vector3(0, 1.85, 0)), WHITE * 0.95)
	b.sphere("paint", p + Vector3(0, 2.5, 0), Vector3(0.75, 1.1, 0.75), 12, 4, WHITE, true)
	var d := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	b.cyl_ab("metal", p + Vector3(0, 1.6, 0) + d * 0.6, p + Vector3(0, 1.75, 0) + d * 2.4, 0.12, 0.1, 8, DARK)

## Lanciatori verticali: piastra con portelli quadrati (n_x × n_z celle).
static func _vls(b: ModelKit, c: Vector3, nx: int, nz: int, lod: int) -> void:
	var cw := 0.68
	var w := float(nx) * cw + 0.3
	var l := float(nz) * cw + 0.3
	b.box("paint", Vector3(w, 0.45, l), c + Vector3(0, 0.22, 0), HAZE_D * 0.95)
	if lod < 2:
		for i in nx:
			for k in nz:
				var p := c + Vector3((float(i) - float(nx - 1) * 0.5) * cw, 0.47, (float(k) - float(nz - 1) * 0.5) * cw)
				b.box("paint", Vector3(cw * 0.86, 0.05, cw * 0.86), p, HAZE * (0.86 if (i + k) % 3 == 0 else 0.95))
				if lod == 0 and (i % 4 == 3) and i < nx - 1:
					b.box("metal", Vector3(0.05, 0.08, l - 0.3), Vector3(p.x + cw * 0.5, p.y, c.z), DARK)

## Battello pneumatico a chiglia rigida sulla gru.
static func _rhib(b: ModelKit, p: Vector3) -> void:
	var old := b.t
	b.t = b.t * Transform3D(Basis.IDENTITY, p)
	b.loft("matte", [[-3.6, 0.35, 0.05, 0.05], [-3.2, 0.4, 0.8, 0.35], [-1.5, 0.4, 1.15, 0.42], [2.8, 0.4, 1.2, 0.42], [3.4, 0.4, 1.15, 0.42]], 10, Color(0.15, 0.15, 0.15))
	b.box("paint", Vector3(1.6, 0.12, 5.6), Vector3(0, 0.62, 0.2), Color(0.38, 0.4, 0.42))
	b.box("paint", Vector3(0.9, 0.6, 0.9), Vector3(0, 0.95, 0.4), Color(0.4, 0.42, 0.44))
	b.t = old

## Elicottero navale (grigio, rotore ripiegato all'indietro) appoggiato sul ponte in `p`.
static func _helo(b: ModelKit, p: Vector3, yaw: float, lod: int) -> void:
	var old := b.t
	b.t = b.t * Transform3D(Basis(Vector3.UP, yaw), p)
	var c := Color(0.5, 0.53, 0.55)
	var sg := 12 if lod == 0 else 8
	b.loft("paint", [[-6.3, 1.4, 0.05, 0.05], [-6.0, 1.45, 0.7, 0.55, 2.6], [-5.0, 1.6, 1.15, 0.95, 3.0], [-3.0, 1.75, 1.3, 1.15, 3.6],
		[0.5, 1.8, 1.3, 1.15, 3.6], [2.0, 2.05, 0.75, 0.7, 2.6], [8.5, 2.6, 0.22, 0.28], [9.6, 2.7, 0.15, 0.2]], sg, c)
	b.box("glass", Vector3(2.2, 0.75, 0.9), Vector3(0, 2.2, -5.3), GLASS, 0.1, Basis(Vector3.RIGHT, 0.55))
	for sd: float in [-1.0, 1.0]:
		b.box("glass", Vector3(0.05, 0.6, 1.4), Vector3(sd * 1.22, 2.0, -4.2), GLASS)
		b.cyl("rubber", 0.33, 0.33, 0.22, 8, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sd * 1.5, 0.33, 0.8)), DARK)
		b.box("paint", Vector3(0.9, 0.25, 0.4), Vector3(sd * 1.2, 0.9, 0.8), c * 0.85)
	b.cyl("rubber", 0.22, 0.22, 0.15, 8, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.22, 7.2)), DARK)
	# motori, mozzo e pale ripiegate
	b.loft("paint", [[-1.5, 3.0, 0.1, 0.1], [-1.2, 3.0, 0.9, 0.35], [1.8, 3.05, 0.8, 0.35], [2.6, 2.9, 0.4, 0.2]], sg, c * 0.95)
	b.cyl("metal", 0.35, 0.3, 0.5, 10, Transform3D(Basis.IDENTITY, Vector3(0, 3.55, -0.3)), GUNMETAL)
	for i in 4:
		var ang := (float(i) - 1.5) * 0.09
		b.box("paint", Vector3(0.5, 0.06, 8.0), Vector3(ang * 9.0, 3.75 + i * 0.05, 3.8), Color(0.16, 0.16, 0.17), 0.0, Basis(Vector3.UP, ang))
	b.plate("paint", [Vector2(0, -0.5), Vector2(1.6, 0.4), Vector2(1.6, 1.0), Vector2(0, 0.6)], 0.12, c, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 2.6, 8.9)))
	b.box("faction", Vector3(0.02, 0.5, 1.2), Vector3(1.31, 1.6, -1.5), b.fac)
	b.box("faction", Vector3(0.02, 0.5, 1.2), Vector3(-1.31, 1.6, -1.5), b.fac)
	b.t = old

static func _flag(b: ModelKit, top: Vector3) -> void:
	b.face("faction", [top, top + Vector3(0, -1.0, 0), top + Vector3(0, -0.5, 1.6)], b.fac, top + Vector3(0.3, -0.5, 0.5))
	b.face("faction", [top, top + Vector3(0, -1.0, 0), top + Vector3(0, -0.5, 1.6)], b.fac, top + Vector3(-0.3, -0.5, 0.5))

# ============================================================== cacciatorpediniere lanciamissili (~120 m)
const DDG_KEYS := [[-60.0, 0.15, 0.0, 8.7, 0.0], [-57.5, 1.5, 0.25, 8.45, 0.6], [-53.0, 3.3, 1.4, 8.1, 3.0], [-45.0, 5.2, 3.5, 7.6, 4.6],
	[-34.0, 6.6, 5.3, 7.15, 5.0], [-18.0, 7.4, 6.6, 6.8, 5.2], [2.0, 7.6, 7.0, 6.4, 5.2], [26.0, 7.4, 6.9, 6.0, 4.8],
	[45.0, 7.0, 6.5, 5.6, 3.4], [60.0, 6.4, 6.0, 5.4, 1.1]]

static func destroyer(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var st := stations(DDG_KEYS, 2.5 if lod == 0 else (4.0 if lod == 1 else 7.0))
	var hc := UnitModels._paint(HAZE, c, tint * 0.5)
	var y0 := at(st, -10.0, 3)
	root.add_child(UnitModels._mi("Body", UnitModels._cached("ddg_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		hull(b, st, hc, DECK, Vector2(-52.0, -38.0), lod)
		# frangiflutti e verricelli a prua
		var yb := at(st, -44.0, 3)
		b.prism_y("paint", [Vector2(0, -45.0), Vector2(3.6, -43.2), Vector2(3.6, -42.8), Vector2(0, -44.5), Vector2(-3.6, -42.8), Vector2(-3.6, -43.2)], yb - 0.3, yb + 0.9, hc)
		if lod < 2:
			var ya := at(st, -50.0, 3)
			for sd: float in [-1.0, 1.0]:
				b.cyl("metal", 0.35, 0.35, 0.5, 10, Transform3D(Basis.IDENTITY, Vector3(sd * 1.2, ya + 0.25, -50.0)), GUNMETAL)
				b.box("rubber", Vector3(0.12, 0.8, 0.9), Vector3(sd * (at(st, -53.5, 1) - 0.15), ya - 0.8, -53.5), DARK)   # cubie
			b.cyl_ab("metal", Vector3(0, ya + 0.05, -50.0), Vector3(0, ya + 0.05, -57.0), 0.06, 0.06, 4, DARK)
		# VLS prodiero
		var yv := at(st, -30.5, 3)
		_vls(b, Vector3(0, yv - 0.15, -30.5), 8, 8, lod)
		# tuga prodiera con radar SPY e plancia
		var dh := [Vector2(-3.4, -24.0), Vector2(3.4, -24.0), Vector2(6.3, -19.5), Vector2(6.3, -2.5), Vector2(3.6, 1.5), Vector2(-3.6, 1.5), Vector2(-6.3, -2.5), Vector2(-6.3, -19.5)]
		b.prism_y("paint", dh, y0 - 0.6, y0 + 7.2, hc, 0.9)
		var br := [Vector2(-3.0, -20.0), Vector2(3.0, -20.0), Vector2(5.4, -17.0), Vector2(5.4, -6.0), Vector2(-5.4, -6.0), Vector2(-5.4, -17.0)]
		b.prism_y("paint", br, y0 + 7.0, y0 + 10.6, hc * 1.02, 0.93)
		b.prism_y("paint", [Vector2(-7.6, -18.8), Vector2(7.6, -18.8), Vector2(7.6, -16.6), Vector2(-7.6, -16.6)], y0 + 9.2, y0 + 10.0, hc * 0.96)   # alette di plancia
		b.box("glass", Vector3(5.6, 1.0, 0.1), Vector3(0, y0 + 9.35, -19.88), GLASS, 0.0, Basis(Vector3.RIGHT, 0.06))
		for sd: float in [-1.0, 1.0]:
			b.box("glass", Vector3(2.7, 1.0, 0.1), Vector3(sd * 4.12, y0 + 9.35, -18.4), GLASS, 0.0, Basis(Vector3.UP, sd * -0.9))
			b.box("glass", Vector3(0.1, 0.9, 5.0), Vector3(sd * 5.34, y0 + 9.35, -13.0), GLASS)
		# pannelli radar ottagonali
		var yr := y0 + 4.6
		_octa(b, Vector3(4.95, yr, -21.85), Vector3(4.5, 0, -2.9), 1.9, Color(0.4, 0.43, 0.46))
		_octa(b, Vector3(-4.95, yr, -21.85), Vector3(-4.5, 0, -2.9), 1.9, Color(0.4, 0.43, 0.46))
		_octa(b, Vector3(5.0, yr, -0.6), Vector3(4.0, 0, 2.7), 1.9, Color(0.4, 0.43, 0.46))
		_octa(b, Vector3(-5.0, yr, -0.6), Vector3(-4.0, 0, 2.7), 1.9, Color(0.4, 0.43, 0.46))
		# CIWS prodiero sul tetto della tuga
		_ciws(b, Vector3(0, y0 + 7.0, -22.0), 0.0)
		# albero a traliccio carenato
		b.prism_y("paint", [Vector2(-1.8, -12.0), Vector2(1.8, -12.0), Vector2(1.8, -7.5), Vector2(-1.8, -7.5)], y0 + 10.6, y0 + 19.0, hc, 0.42, Vector2(0, 0.6))
		b.cyl_ab("metal", Vector3(0, y0 + 18.8, -9.2), Vector3(0, y0 + 27.5, -9.0), 0.22, 0.08, 6, HAZE_L)
		b.box("paint", Vector3(7.0, 0.25, 0.4), Vector3(0, y0 + 16.5, -9.4), hc)          # pennone
		b.box("paint", Vector3(2.6, 0.2, 2.2), Vector3(0, y0 + 19.0, -9.2), hc * 0.95)    # piattaforma del radar
		b.sphere("paint", Vector3(0, y0 + 23.0, -9.1), Vector3(0.5, 0.5, 0.5), 8, 4, WHITE)
		b.sphere("paint", Vector3(2.2, y0 + 16.9, -9.4), Vector3(0.35, 0.35, 0.35), 8, 4, WHITE)
		b.sphere("paint", Vector3(-2.2, y0 + 16.9, -9.4), Vector3(0.35, 0.35, 0.35), 8, 4, WHITE)
		_flag(b, Vector3(0, y0 + 27.3, -9.0))
		# tuga centrale, fumaioli inclinati con fascia della fazione
		b.prism_y("paint", [Vector2(-5.6, 1.0), Vector2(5.6, 1.0), Vector2(5.6, 21.0), Vector2(-5.6, 21.0)], y0 - 0.9, y0 + 3.4, hc * 0.98, 0.95)
		for fz: float in [4.0, 15.0]:
			var fu := [Vector2(-2.3, fz - 2.6), Vector2(2.3, fz - 2.6), Vector2(3.0, fz - 1.0), Vector2(3.0, fz + 2.6), Vector2(-3.0, fz + 2.6), Vector2(-3.0, fz - 1.0)]
			var fh := 8.5 if fz < 10.0 else 7.5
			b.prism_y("paint", fu, y0 + 3.4, y0 + 3.4 + fh, hc * 1.03, 0.78, Vector2(0, 1.2))
			var tp: Array = []
			var cz := fz + 0.0
			for p in fu:
				var q: Vector2 = Vector2(0, cz) + (p - Vector2(0, cz)) * 0.8 + Vector2(0, 1.15)
				tp.append(q)
			b.prism_y("faction", tp, y0 + 3.4 + fh * 0.82, y0 + 3.4 + fh * 0.93, b.fac, 0.99)
			var tq: Array = []
			for p in fu:
				tq.append(Vector2(0, cz) + (p - Vector2(0, cz)) * 0.77 + Vector2(0, 1.2))
			b.prism_y("matte", tq, y0 + 3.4 + fh, y0 + 3.4 + fh + 0.25, DARK, 0.97)
		# missili antinave tra i fumaioli
		if lod < 2:
			for sd: float in [-1.0, 1.0]:
				for i in 4:
					var px := sd * (0.9 + float(i % 2) * 1.1)
					var py := y0 + 3.9 + float(i / 2) * 0.75
					b.box("paint", Vector3(0.7, 0.7, 4.2), Vector3(px, py, 9.8), HAZE_D, 0.05, Basis(Vector3.UP, sd * 0.5) * Basis(Vector3.RIGHT, 0.12))
		# lance a motore e zattere
		if lod < 2:
			for sd: float in [-1.0, 1.0]:
				_rhib(b, Vector3(sd * 6.6, y0 + 1.8, 8.5))
				b.box("metal", Vector3(0.25, 3.5, 0.25), Vector3(sd * 5.7, y0 + 2.2, 6.0), HAZE_L)
				b.box("metal", Vector3(0.25, 3.5, 0.25), Vector3(sd * 5.7, y0 + 2.2, 11.0), HAZE_L)
				for i in 4:
					b.cyl("paint", 0.42, 0.42, 1.3, 8, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sd * 5.4, y0 + 3.9, 14.0 + i * 1.6)), WHITE)
		# VLS poppiero, hangar, CIWS e radar di poppa
		var ya2 := at(st, 23.5, 3)
		_vls(b, Vector3(0, ya2 - 0.15, 23.5), 8, 4, lod)
		var hg := [Vector2(-6.0, 26.0), Vector2(6.0, 26.0), Vector2(6.6, 28.0), Vector2(6.6, 37.0), Vector2(-6.6, 37.0), Vector2(-6.6, 28.0)]
		var yh := at(st, 31.0, 3)
		b.prism_y("paint", hg, yh - 0.6, yh + 6.2, hc, 0.94)
		for sd: float in [-1.0, 1.0]:
			b.box("matte", Vector3(4.8, 4.8, 0.1), Vector3(sd * 3.0, yh + 2.5, 36.86), hc * 0.78, 0.0, Basis(Vector3.RIGHT, -0.035))
			for i in 6:
				b.box("matte", Vector3(4.6, 0.04, 0.12), Vector3(sd * 3.0, yh + 0.5 + i * 0.8, 36.94), hc * 0.65, 0.0, Basis(Vector3.RIGHT, -0.035))
		_ciws(b, Vector3(0, yh + 6.0, 34.0), PI)
		b.cyl_ab("metal", Vector3(0, yh + 6.0, 28.5), Vector3(0, yh + 10.0, 28.5), 0.18, 0.1, 6, HAZE_L)
		# ponte di volo: cerchio, linee, rete
		var yd := at(st, 48.0, 3)
		b.cyl("faction", 5.2, 5.2, 0.04, 28, Transform3D(Basis.IDENTITY, Vector3(0, yd + 0.03, 48.0)), b.fac, true, false)
		b.cyl("matte", 4.6, 4.6, 0.05, 28, Transform3D(Basis.IDENTITY, Vector3(0, yd + 0.04, 48.0)), DECK, true, false)
		b.box("matte", Vector3(0.3, 0.06, 22.0), Vector3(0, yd + 0.05, 48.0), WHITE * 0.9)
		b.box("matte", Vector3(9.0, 0.06, 0.3), Vector3(0, yd + 0.05, 48.0), WHITE * 0.9)
		if lod < 2:
			_helo(b, Vector3(0.6, yd, 47.0), 0.08, lod)
		# numero di scafo in fazione a poppa (sullo specchio)
		b.box("faction", Vector3(4.0, 0.9, 0.06), Vector3(0, 3.3, 60.03), b.fac)
		)))
	# cannone da 127 mm prodiero: torretta e canna orientabili
	var yg := at(st, -39.0, 3)
	var tur := UnitModels._mi("Turret", UnitModels._cached("ddg_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.cyl("paint", 2.1, 2.1, 0.5, 16, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.3)), hc * 0.9)
		b.prism_y("paint", [Vector2(-1.3, -2.4), Vector2(1.3, -2.4), Vector2(2.1, -0.6), Vector2(2.1, 2.6), Vector2(-2.1, 2.6), Vector2(-2.1, -0.6)],
			0.2, 2.5, hc * 1.04, 0.72, Vector2(0, 0.45))
		b.box("matte", Vector3(0.7, 1.0, 0.2), Vector3(0, 1.2, -2.2), DARK, 0.0, Basis(Vector3.RIGHT, 0.4))
		), Vector3(0, yg, -39.0))
	root.add_child(tur)
	var bar := UnitModels._mi("Barrel", UnitModels._cached("ddg_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("paint", Vector3(0, 0, -0.2), Vector3(0, 0, -7.0), 0.16, 0.12, 10, hc * 0.95)
		b.cyl_ab("paint", Vector3(0, 0, -0.2), Vector3(0, 0, -1.6), 0.32, 0.22, 10, hc * 0.9)
		b.cyl_ab("metal", Vector3(0, 0, -6.95), Vector3(0, 0, -7.05), 0.08, 0.08, 8, Color(0.02, 0.02, 0.02))
		), Vector3(0, 1.25, -1.9))
	tur.add_child(bar)
	bar.add_child(UnitModels._marker("Muzzle", Vector3(0, 0, -7.2)))
	# radar di scoperta rotante in testa d'albero
	var radar := UnitModels._mi("Radar", UnitModels._cached("ddg_radar", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.3, 0.3, 0.5, 8, Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), GUNMETAL)
		b.box("paint", Vector3(4.6, 0.9, 0.18), Vector3(0, 0.95, 0.0), HAZE_L, 0.04, Basis(Vector3.RIGHT, 0.2))
		b.box("metal", Vector3(4.4, 0.12, 0.6), Vector3(0, 0.5, 0.25), GUNMETAL)
		), Vector3(0, y0 + 19.1, -9.2))
	root.add_child(radar)
	root.set_meta("length", 120.0)
	root.set_meta("height", y0 + 27.5)
	root.set_meta("air", false)
	root.set_meta("naval", true)

# ============================================================== nave anfibia da trasporto (~115 m)
const LPD_KEYS := [[-57.0, 0.6, 0.0, 10.4, 0.0], [-54.5, 3.4, 1.2, 10.2, 1.0], [-49.0, 6.2, 3.6, 10.0, 3.6], [-40.0, 8.4, 6.2, 9.8, 4.8],
	[-26.0, 9.6, 8.2, 9.6, 5.2], [0.0, 10.0, 9.0, 9.5, 5.3], [30.0, 10.0, 9.1, 9.4, 5.1], [48.0, 9.8, 9.0, 9.3, 4.2], [58.0, 9.5, 8.8, 9.3, 2.6]]

static func transport(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var st := stations(LPD_KEYS, 2.5 if lod == 0 else (4.0 if lod == 1 else 7.0))
	var hc := UnitModels._paint(HAZE, c, tint * 0.5)
	var y0 := at(st, 0.0, 3)
	root.add_child(UnitModels._mi("Body", UnitModels._cached("lpd_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		hull(b, st, hc, DECK, Vector2(-50.0, -36.0), lod)
		# portellone di poppa del bacino allagabile
		b.box("matte", Vector3(13.0, 7.0, 0.12), Vector3(0, 4.0, 58.04), hc * 0.7)
		for i in 5:
			b.box("matte", Vector3(12.6, 0.06, 0.1), Vector3(0, 1.2 + i * 1.4, 58.12), hc * 0.55)
		b.box("faction", Vector3(5.0, 1.0, 0.06), Vector3(0, 8.4, 58.06), b.fac)
		# portellone laterale per i mezzi
		for sd: float in [-1.0, 1.0]:
			b.box("matte", Vector3(0.12, 4.0, 8.0), Vector3(sd * (at(st, 5.0, 1) - 0.25), 5.6, 5.0), hc * 0.75)
		# castello prodiero: gru, verricelli, mezzi rizzati in coperta
		var yb := at(st, -44.0, 3)
		if lod < 2:
			for sd: float in [-1.0, 1.0]:
				b.cyl("metal", 0.4, 0.4, 0.5, 10, Transform3D(Basis.IDENTITY, Vector3(sd * 1.5, yb + 0.25, -46.0)), GUNMETAL)
		_ciws(b, Vector3(0, yb, -42.0), 0.0)
		# sovrastruttura a castello (ponte, alberi a torre ottagonale)
		var sp := [Vector2(-7.0, -32.0), Vector2(7.0, -32.0), Vector2(9.0, -28.0), Vector2(9.0, 4.0), Vector2(-9.0, 4.0), Vector2(-9.0, -28.0)]
		b.prism_y("paint", sp, y0 - 0.5, y0 + 6.5, hc, 0.95)
		var sp2 := [Vector2(-5.5, -29.0), Vector2(5.5, -29.0), Vector2(7.5, -26.0), Vector2(7.5, 0.0), Vector2(-7.5, 0.0), Vector2(-7.5, -26.0)]
		b.prism_y("paint", sp2, y0 + 6.5, y0 + 10.5, hc * 1.02, 0.94)
		var sp3 := [Vector2(-4.5, -27.0), Vector2(4.5, -27.0), Vector2(6.2, -24.5), Vector2(6.2, -16.0), Vector2(-6.2, -16.0), Vector2(-6.2, -24.5)]
		b.prism_y("paint", sp3, y0 + 10.5, y0 + 14.0, hc * 1.04, 0.93)
		b.box("glass", Vector3(8.0, 1.1, 0.1), Vector3(0, y0 + 12.9, -26.85), GLASS, 0.0, Basis(Vector3.RIGHT, 0.07))
		for sd: float in [-1.0, 1.0]:
			b.box("glass", Vector3(2.8, 1.1, 0.1), Vector3(sd * 5.25, y0 + 12.9, -25.6), GLASS, 0.0, Basis(Vector3.UP, sd * -0.95))
			b.box("glass", Vector3(0.1, 1.0, 7.0), Vector3(sd * 6.0, y0 + 12.9, -20.5), GLASS)
			b.prism_y("paint", [Vector2(sd * 6.0, -25.5), Vector2(sd * 9.8, -25.5), Vector2(sd * 9.8, -23.0), Vector2(sd * 6.0, -23.0)], y0 + 12.4, y0 + 13.1, hc)
			# finestrini e porte stagne sui fianchi della sovrastruttura
			if lod < 2:
				for i in 6:
					b.box("glass", Vector3(0.1, 0.5, 0.7), Vector3(sd * 8.95, y0 + 4.6, -24.0 + i * 4.5), GLASS)
				b.box("matte", Vector3(0.1, 2.0, 1.0), Vector3(sd * 9.0, y0 + 1.0, -2.0), hc * 0.7)
		# torri radar ottagonali (stile "albero integrato")
		for mz: float in [-13.0, -1.0]:
			var oc: Array = []
			for i in 8:
				var a := TAU * (float(i) + 0.5) / 8.0
				oc.append(Vector2(cos(a) * 3.0, mz + sin(a) * 3.0))
			var h0 := y0 + (14.0 if mz < -5.0 else 10.5)
			var hh := 11.0 if mz < -5.0 else 9.0
			b.prism_y("paint", oc, h0, h0 + hh, HAZE_L * 0.95, 0.55)
			b.prism_y("matte", oc.map(func(p: Vector2) -> Vector2: return Vector2(p.x * 0.6, mz + (p.y - mz) * 0.6)), h0 + hh, h0 + hh + 0.3, DARK, 0.95)
			b.cyl_ab("metal", Vector3(0, h0 + hh + 0.3, mz), Vector3(0, h0 + hh + 5.0, mz), 0.16, 0.06, 6, HAZE_L)
			if mz < -5.0:
				_flag(b, Vector3(0, h0 + hh + 4.8, mz))
		# fumaiolo
		var fu := [Vector2(-2.6, 2.0), Vector2(2.6, 2.0), Vector2(3.2, 4.0), Vector2(3.2, 8.0), Vector2(-3.2, 8.0), Vector2(-3.2, 4.0)]
		b.prism_y("paint", fu, y0 + 6.5, y0 + 13.0, hc, 0.8, Vector2(0, 1.0))
		var tq: Array = []
		for p in fu:
			tq.append(Vector2(0, 5.0) + (p - Vector2(0, 5.0)) * 0.78 + Vector2(0, 1.0))
		b.prism_y("faction", tq, y0 + 11.6, y0 + 12.4, b.fac, 0.99)
		b.prism_y("matte", tq.map(func(p: Vector2) -> Vector2: return Vector2(0, 6.0) + (p - Vector2(0, 6.0)) * 0.98), y0 + 13.0, y0 + 13.25, DARK, 0.97)
		# zona centrale: gru e mezzi rizzati
		var yc := at(st, 12.0, 3)
		b.cyl("paint", 0.8, 0.9, 6.0, 10, Transform3D(Basis.IDENTITY, Vector3(-6.5, yc + 3.0, 10.0)), hc)
		b.cyl_ab("paint", Vector3(-6.5, yc + 5.6, 10.0), Vector3(2.0, yc + 12.0, 13.0), 0.35, 0.25, 8, Color(0.62, 0.5, 0.18))
		b.cyl_ab("metal", Vector3(2.0, yc + 12.0, 13.0), Vector3(2.0, yc + 5.0, 13.0), 0.03, 0.03, 3, DARK)
		if lod < 2:
			for i in 3:
				for sd: float in [-1.0, 1.0]:
					_deck_vehicle(b, Vector3(sd * 3.6, yc, 8.0 + i * 5.5), c, i)
			for sd: float in [-1.0, 1.0]:
				_rhib(b, Vector3(sd * 8.8, y0 - 1.5, -8.0))
		# ponte di volo con due piazzole
		var yd := at(st, 40.0, 3)
		b.box("matte", Vector3(18.6, 0.04, 34.0), Vector3(0, yd + 0.02, 40.0), DECK * 1.08)
		for pz: float in [30.0, 48.0]:
			b.cyl("faction", 4.6, 4.6, 0.04, 24, Transform3D(Basis.IDENTITY, Vector3(0, yd + 0.05, pz)), b.fac, true, false)
			b.cyl("matte", 4.0, 4.0, 0.05, 24, Transform3D(Basis.IDENTITY, Vector3(0, yd + 0.06, pz)), DECK * 1.08, true, false)
			b.box("matte", Vector3(0.25, 0.07, 6.0), Vector3(0, yd + 0.07, pz), WHITE * 0.9)
		b.box("matte", Vector3(0.3, 0.06, 34.0), Vector3(-9.0, yd + 0.05, 40.0), Color(0.75, 0.62, 0.18))
		b.box("matte", Vector3(0.3, 0.06, 34.0), Vector3(9.0, yd + 0.05, 40.0), Color(0.75, 0.62, 0.18))
		if lod < 2:
			_helo(b, Vector3(-0.4, yd, 48.5), -0.12, lod)
		_ciws(b, Vector3(6.5, yd, 21.5), PI)
		)))
	root.add_child(UnitModels._marker("Muzzle", Vector3(0, at(st, -42.0, 3) + 2.6, -44.5)))
	root.set_meta("length", 115.0)
	root.set_meta("height", y0 + 30.0)
	root.set_meta("air", false)
	root.set_meta("naval", true)

## Mezzo rizzato in coperta (container o camion telonato).
static func _deck_vehicle(b: ModelKit, p: Vector3, c: Color, i: int) -> void:
	var olive := UnitModels._paint(UnitModels.OLIVE, c, 0.15)
	if i == 1:
		b.box("matte", Vector3(2.45, 2.6, 6.0), p + Vector3(0, 1.3, 0), Color(0.38, 0.42, 0.33))
		for k in 7:
			b.box("matte", Vector3(2.5, 2.4, 0.08), p + Vector3(0, 1.3, -2.7 + k * 0.9), Color(0.32, 0.36, 0.28))
		return
	b.box("paint", Vector3(2.3, 1.2, 1.6), p + Vector3(0, 1.4, -2.0), olive, 0.08)
	b.box("matte", Vector3(2.35, 1.5, 3.4), p + Vector3(0, 1.6, 0.8), Color(0.3, 0.31, 0.22), 0.15)
	for z: float in [-2.0, 0.4, 1.8]:
		for sd: float in [-1.0, 1.0]:
			b.cyl("rubber", 0.5, 0.5, 0.35, 8, Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(sd * 1.0, 0.5, z)), DARK)
