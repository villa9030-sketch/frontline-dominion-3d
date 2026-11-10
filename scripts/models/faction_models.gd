class_name FactionModels
extends RefCounted
## Mezzi per fazione (Agente F4). Chiamato da UnitModels._make con UnitModels._fac già impostato (cache e vernice di fazione).
## Ogni builder riempie `root` con gli stessi nodi con nome dei modelli generici e restituisce true; false = usa il generico.
## Sagome: AAN squadrate/tecnologiche (sensori, RWS, pannelli radar), FO basse e arrotondate con corazza reattiva e canne lunghe,
## CP su ruote 8x8 con antenne EW, UL improvvisate (tecniche su pick-up, gabbie, sacchetti, camion lanciarazzi).
## Mezzi aerei in FactionAir.

const DARK := Color(0.11, 0.11, 0.1)
const TRACK := Color(0.15, 0.14, 0.12)
const GUNMETAL := Color(0.2, 0.2, 0.21)
const GLASS := Color(0.1, 0.16, 0.2)
const CLOTH := Color(0.33, 0.31, 0.22)
const SANDBAG := Color(0.52, 0.46, 0.33)
const CONCRETE := Color(0.5, 0.49, 0.45)
const EARTH := Color(0.33, 0.27, 0.19)
const RUST := Color(0.4, 0.24, 0.14)
const WOOD := Color(0.36, 0.27, 0.18)
const ID := ["aan", "fo", "cp", "ul"]

static func build_into(root: Node3D, kind: String, c: Color, lod: int, burnt: bool, tint: float, fac: int) -> bool:
	match kind + "_" + String(ID[fac]):
		"tank_aan": _tank_aan(root, c, lod, burnt, tint)
		"tank_fo": _tank_fo(root, c, lod, burnt, tint)
		"tank_cp": _tank_cp(root, c, lod, burnt, tint)
		"tank_ul": _tank_ul(root, c, lod, burnt, tint)
		"art_aan": _art_aan(root, c, lod, burnt, tint)
		"art_fo": _art_fo(root, c, lod, burnt, tint)
		"art_cp": _art_cp(root, c, lod, burnt, tint)
		"art_ul": _art_ul(root, c, lod, burnt, tint)
		"aa_aan": _aa_aan(root, c, lod, burnt, tint)
		"aa_fo": _aa_fo(root, c, lod, burnt, tint)
		"aa_cp": _aa_cp(root, c, lod, burnt, tint)
		"aa_ul": _aa_ul(root, c, lod, burnt, tint)
		"truck_aan": _truck_aan(root, c, lod, burnt, tint)
		"truck_fo": _truck_fo(root, c, lod, burnt, tint)
		"truck_cp": _truck_cp(root, c, lod, burnt, tint)
		"truck_ul": _truck_ul(root, c, lod, burnt, tint)
		"bunker_aan": _bunker_aan(root, c, lod, burnt, tint)
		"bunker_fo": _bunker_fo(root, c, lod, burnt, tint)
		"bunker_cp": _bunker_cp(root, c, lod, burnt, tint)
		"bunker_ul": _bunker_ul(root, c, lod, burnt, tint)
		"inf_aan", "inf_fo", "inf_cp", "inf_ul": _inf(root, c, lod, burnt, tint, fac)
		_:
			return FactionAir.build_into(root, kind, c, lod, burnt, tint, fac)
	return true

# ============================================================== scorciatoie
static func _m(key: String, c: Color, lod: int, burnt: bool, tint: float, fn: Callable) -> ArrayMesh:
	return UnitModels._cached(key, c, lod, burnt, tint, fn)

static func _mi(n: String, mesh: ArrayMesh, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return UnitModels._mi(n, mesh, pos)

static func _mk(n: String, pos: Vector3) -> Marker3D:
	return UnitModels._marker(n, pos)

static func _pc(c: Color, tint: float) -> Color:
	return UnitModels._paint(UnitModels.OLIVE, c, tint)

static func _rx() -> Basis:
	return Basis(Vector3.BACK, PI * 0.5)

static func _meta(root: Node3D, L: float, h: float) -> void:
	root.set_meta("length", L)
	root.set_meta("height", h)
	root.set_meta("air", false)

# ============================================================== componenti comuni
static func _wheel(b: ModelKit, p: Vector3, r: float, w: float, lod: int, hub: Color) -> void:
	var sg := 14 if lod == 0 else (10 if lod == 1 else 7)
	b.wheel(p, r, w, sg, hub, lod, 0.55)

## Treno di rotolamento cingolato. skirt: 0 parafanghi scoperti (vecchio carro), 1 minigonne d'acciaio, 2 bandelle in gomma + ERA.
static func _tracked(b: ModelKit, pc: Color, hl: float, hw: float, tw: float, nw: int, wr: float, lod: int, skirt: int) -> void:
	var segw := 14 if lod == 0 else (10 if lod == 1 else 6)
	for s: float in [-1.0, 1.0]:
		var xo := s * (hw - 0.02)
		var xi := s * (hw - tw)
		b.prism_x("track", [Vector2(-hl + 0.8, 0.0), Vector2(hl - 0.8, 0.0), Vector2(hl + 0.02, 0.55), Vector2(hl + 0.02, 0.86),
			Vector2(hl - 0.3, 0.99), Vector2(-hl + 0.2, 0.99), Vector2(-hl - 0.12, 0.86), Vector2(-hl - 0.12, 0.55)], minf(xo, xi), maxf(xo, xi), TRACK)
		for i in nw:
			var z := lerpf(-hl + 0.95, hl - 1.0, float(i) / float(nw - 1))
			b.wheel(Vector3(s * (hw - 0.07), wr + 0.03, z), wr, 0.13, segw, pc * 0.85, lod, 0.75)
		if lod == 0 and skirt != 0:
			for i in 3:
				var z := lerpf(-hl + 1.6, hl - 1.6, float(i) / 2.0)
				b.wheel(Vector3(s * (hw - 0.1), 0.86, z), 0.11, 0.1, 8, pc * 0.7, 2, 0.5)
		b.wheel_begin(Vector3(s * (hw - 0.12), 0.72, hl - 0.28), 0.37)
		b.cyl("wheel_metal", 0.37, 0.37, 0.2, 12 if lod < 2 else 6, Transform3D(_rx(), Vector3(s * (hw - 0.12), 0.72, hl - 0.28)), GUNMETAL, true, false)
		if lod == 0:
			for k in 6:
				var a := TAU * float(k) / 6.0
				b.box("wheel_metal", Vector3(0.22, 0.1, 0.1), Vector3(s * (hw - 0.12), 0.72 + cos(a) * 0.4, hl - 0.28 + sin(a) * 0.4), GUNMETAL * 1.1, 0.0, Basis(Vector3.RIGHT, -a))
		b.wheel_end()
		b.wheel(Vector3(s * (hw - 0.12), 0.68, -hl + 0.12), 0.31, 0.18, segw, pc * 0.8, lod, 0.7, pc * 0.6)
		match skirt:
			1:
				b.box("paint", Vector3(0.07, 0.52, hl * 2.0 - 0.7), Vector3(s * (hw + 0.03), 0.8, 0.05), pc, 0.02)
				b.box("faction", Vector3(0.02, 0.2, 1.3), Vector3(s * (hw + 0.075), 0.86, -hl + 1.3), b.fac)
			2:
				b.box("rubber", Vector3(0.05, 0.42, hl * 2.0 - 0.4), Vector3(s * (hw + 0.02), 0.8, 0.1), TRACK * 1.3)
				for i in 5:
					b.box("paint", Vector3(0.13, 0.4, 0.5), Vector3(s * (hw + 0.1), 0.86, -hl + 0.5 + i * 0.53), pc * (0.92 + 0.06 * (i % 2)), 0.025)
				b.box("faction", Vector3(0.02, 0.18, 1.0), Vector3(s * (hw + 0.17), 0.9, -hl + 1.0), b.fac)
			_:
				b.box("paint", Vector3(tw + 0.08, 0.04, hl * 2.0 + 0.15), Vector3(s * (hw - tw * 0.5), 1.02, -0.05), pc * 0.9)
				if lod < 2:
					for i in 3:
						b.box("paint", Vector3(tw * 0.8, 0.3, 0.55), Vector3(s * (hw - tw * 0.5), 1.19, -hl + 1.4 + i * 1.6), pc * (0.8 + 0.1 * i), 0.03)
					b.box("faction", Vector3(0.02, 0.2, 0.5), Vector3(s * (hw + 0.03), 1.19, -hl + 1.4), b.fac)

## Scafo superiore di un cingolato (sopra i cingoli) e inferiore (tra i cingoli). gl = lunghezza dello spalto frontale.
static func _hullx(b: ModelKit, pc: Color, hl: float, hw: float, tw: float, deck: float, gl: float, lod: int) -> void:
	b.camo = 1.0
	b.dirt_h = 1.15
	b.prism_x("paint", [Vector2(-hl - 0.05, 1.0), Vector2(-hl + 0.55, 0.42), Vector2(hl - 0.35, 0.42), Vector2(hl - 0.05, 1.0)], -(hw - tw + 0.02), hw - tw + 0.02, pc * 0.9)
	b.prism_x("paint", [Vector2(-hl - 0.05, 1.0), Vector2(-hl - 0.14, 1.14), Vector2(-hl + gl, deck), Vector2(hl - 0.25, deck + 0.02),
		Vector2(hl - 0.04, deck - 0.1), Vector2(hl - 0.04, 1.0)], -hw, hw, pc)
	if lod < 2:
		for i in 4:
			b.box("metal", Vector3(0.48, 0.03, 0.8), Vector3(-0.99 + i * 0.66, deck + 0.025, hl - 1.2), DARK)
		b.cyl("paint", 0.3, 0.3, 0.06, 12, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, lerpf(1.14, deck, 0.75), -hl + gl * 0.72)), pc * 0.9)
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.16, 0.12, 0.06), Vector3(s * (hw - 0.45), 1.2, -hl - 0.12), GLASS)
			b.box("metal", Vector3(0.24, 0.04, 0.16), Vector3(s * (hw - 0.45), 1.29, -hl - 0.12), GUNMETAL)
		b.box("faction", Vector3(1.0, 0.02, 0.55), Vector3(0.0, deck + 0.035, hl - 0.45), b.fac)

## Scafo 8x8 (CP): scafo superiore che sporge sopra le ruote, quattro assi. top = quota del tetto, nose = lunghezza dello spalto.
static func _hull8(b: ModelKit, pc: Color, hl: float, hw: float, top: float, nose: float, lod: int) -> void:
	b.camo = 1.0
	b.dirt_h = 1.0
	b.prism_x("paint", [Vector2(-hl + 0.35, 1.08), Vector2(-hl + 0.95, 0.5), Vector2(hl - 0.7, 0.5), Vector2(hl - 0.15, 1.08)], -(hw - 0.55), hw - 0.55, pc * 0.82)
	b.prism_x("paint", [Vector2(-hl + 0.05, 1.05), Vector2(-hl - 0.18, 1.3), Vector2(-hl + nose, top), Vector2(hl - 0.12, top),
		Vector2(hl, top - 0.2), Vector2(hl, 1.05)], -hw, hw, pc)
	# fianchi superiori inclinati
	for s: float in [-1.0, 1.0]:
		b.hexa("paint", [Vector3(s * hw, 1.05, -hl + 0.1), Vector3(s * (hw + 0.12), 1.05, -hl + 0.3), Vector3(s * (hw + 0.12), 1.05, hl - 0.1),
			Vector3(s * hw, 1.05, hl - 0.05), Vector3(s * hw, top - 0.25, -hl + nose * 0.6), Vector3(s * (hw + 0.01), top - 0.25, -hl + nose * 0.6 + 0.1),
			Vector3(s * (hw + 0.01), top - 0.25, hl - 0.2), Vector3(s * hw, top - 0.25, hl - 0.15)], pc * 0.96)
	var axles := [-hl + 0.95, -hl + 2.3, hl - 2.15, hl - 0.85]
	for z: float in axles:
		for s: float in [-1.0, 1.0]:
			_wheel(b, Vector3(s * (hw - 0.3), 0.6, z), 0.58, 0.42, lod, pc * 0.7)
	if lod < 2:
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.16, 0.42, 1.1), Vector3(s * (hw + 0.17), 1.42, (axles[1] + axles[2]) * 0.5), pc * 0.88, 0.03)
			b.box("faction", Vector3(0.02, 0.18, 0.9), Vector3(s * (hw + 0.26), 1.45, (axles[1] + axles[2]) * 0.5), b.fac)
			b.box("glass", Vector3(0.18, 0.1, 0.05), Vector3(s * (hw - 0.3), 1.22, -hl - 0.12), GLASS)
		for i in 3:
			b.box("glass", Vector3(0.18, 0.06, 0.05), Vector3(-0.85 + i * 0.2, top + 0.02, -hl + nose + 0.05), GLASS)
		for i in 3:
			b.box("metal", Vector3(0.6, 0.03, 0.7), Vector3(0.2 + (i - 1) * 0.7, top + 0.015, -hl + nose + 0.9), DARK)
		b.box("faction", Vector3(0.9, 0.02, 0.6), Vector3(0, top + 0.02, hl - 0.5), b.fac)

## Antenna a frusta di guerra elettronica con base e "pomo" (CP).
static func _ew(b: ModelKit, p: Vector3, h: float, pc: Color) -> void:
	b.cyl("paint", 0.09, 0.11, 0.18, 8, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.09, 0)), pc * 0.75)
	b.cyl_ab("metal", p + Vector3(0, 0.18, 0), p + Vector3(0, h, 0), 0.02, 0.008, 4, DARK)
	b.cyl("rubber", 0.05, 0.05, 0.12, 6, Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.45, 0)), DARK)

## Fila di mattonelle di corazza reattiva lungo il segmento a→e (n per riga, `rows` file verso l'alto di dy).
static func _era(b: ModelKit, a: Vector3, e: Vector3, n: int, rows: int, dy: Vector3, sz: Vector3, bs: Basis, col: Color) -> void:
	for j in rows:
		for i in n:
			var p := a.lerp(e, float(i) / float(maxi(n - 1, 1))) + dy * float(j)
			b.box("paint", sz, p, col * (0.9 + 0.1 * float((i + j) % 2)), 0.015, bs)

## Sacchetti di sabbia lungo il segmento a→e.
static func _bags(b: ModelKit, a: Vector3, e: Vector3, n: int, rows: int, yaw: float) -> void:
	for j in rows:
		for i in n:
			var f := (float(i) + 0.5 * float(j % 2)) / float(n)
			var p := a.lerp(e, f) + Vector3(0, 0.2 * j, 0)
			b.box("matte", Vector3(0.55, 0.22, 0.34), p, SANDBAG * (0.86 + 0.07 * float((i * 7 + j * 3) % 4)), 0.08, Basis(Vector3.UP, yaw + 0.08 * float((i + j) % 3 - 1)))

# ============================================================== CARRI
## AAN: carro occidentale squadrato, torretta a cuneo con lunga controtorretta, visore indipendente, RWS, sensori.
static func _tank_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.7
	root.add_child(_mi("Body", _m("aan_tank_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		UnitModels._chassis(b, pc, hl, 1.82, lod, 7)
		if lod < 2:
			b.box("paint", Vector3(0.9, 0.4, 0.6), Vector3(0.95, 1.85, hl - 0.4), pc * 0.9, 0.04)   # APU
		)))
	var prof := [Vector2(-0.75, -2.25), Vector2(0.75, -2.25), Vector2(1.72, -1.35), Vector2(1.8, 0.6), Vector2(1.72, 2.55),
		Vector2(-1.72, 2.55), Vector2(-1.8, 0.6), Vector2(-1.72, -1.35)]
	var tur := _mi("Turret", _m("aan_tank_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 0.8, pc, 0.97, Vector2(0, 0.03))
		UnitModels._band(b, prof, 0.8, 0.97, Vector2(0, 0.03), 0.3, 0.46, b.fac)
		b.marks_x(1.79, 0.16, -0.2, 0.95, 0.24, 0.07)
		b.box("paint", Vector3(0.95, 0.62, 0.38), Vector3(0, 0.4, -2.35), pc * 0.9, 0.03)
		b.box("faction", Vector3(1.0, 0.025, 0.8), Vector3(0.0, 0.81, 1.4), b.fac)
		# cesto della controtorretta
		b.box("metal", Vector3(3.2, 0.04, 0.6), Vector3(0, 0.15, 2.85), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.box("metal", Vector3(0.04, 0.5, 0.6), Vector3(s * 1.6, 0.4, 2.85), GUNMETAL)
		b.box("metal", Vector3(3.2, 0.04, 0.04), Vector3(0, 0.65, 3.15), GUNMETAL)
		if lod < 2:
			b.box("matte", Vector3(1.2, 0.35, 0.45), Vector3(-0.7, 0.36, 2.85), CLOTH * 0.9, 0.06)
			# visore indipendente del capocarro (sensore panoramico)
			b.cyl("paint", 0.16, 0.18, 0.3, 10, Transform3D(Basis.IDENTITY, Vector3(-0.7, 0.95, -0.1)), pc * 0.8)
			b.box("paint", Vector3(0.46, 0.34, 0.4), Vector3(-0.7, 1.25, -0.1), pc * 0.95, 0.04, Basis(Vector3.UP, 0.35))
			b.box("glass", Vector3(0.32, 0.2, 0.03), Vector3(-0.77, 1.27, -0.31), GLASS, 0.0, Basis(Vector3.UP, 0.35))
			# mirino del cannoniere
			b.box("paint", Vector3(0.5, 0.32, 0.6), Vector3(1.05, 0.95, -1.3), pc, 0.03)
			b.box("glass", Vector3(0.4, 0.2, 0.03), Vector3(1.05, 0.97, -1.61), GLASS)
			# stazione d'arma remotizzata
			b.box("paint", Vector3(0.55, 0.12, 0.55), Vector3(0.75, 0.86, 0.55), pc * 0.85)
			b.box("paint", Vector3(0.18, 0.36, 0.5), Vector3(0.96, 1.08, 0.5), pc * 0.9, 0.02)
			b.box("paint", Vector3(0.22, 0.2, 0.26), Vector3(0.58, 1.12, 0.38), pc * 0.75, 0.02)
			b.box("glass", Vector3(0.16, 0.13, 0.02), Vector3(0.58, 1.12, 0.24), GLASS)
			b.box("metal", Vector3(0.12, 0.16, 0.62), Vector3(0.78, 1.08, 0.35), DARK)
			b.cyl_ab("metal", Vector3(0.78, 1.1, 0.05), Vector3(0.78, 1.1, -0.85), 0.03, 0.03, 6, DARK)
			# rilevatori di allarme laser agli angoli e lanciafumogeni a scatola
			for s: float in [-1.0, 1.0]:
				b.box("metal", Vector3(0.14, 0.1, 0.14), Vector3(s * 1.55, 0.86, -1.2), DARK)
				b.box("metal", Vector3(0.14, 0.1, 0.14), Vector3(s * 1.55, 0.86, 2.3), DARK)
				b.box("paint", Vector3(0.36, 0.3, 0.5), Vector3(s * 1.7, 0.55, -1.0), pc * 0.8, 0.02, Basis(Vector3.UP, s * 0.3))
				for i in 3:
					b.cyl_ab("metal", Vector3(s * 1.72, 0.48 + i * 0.07, -1.2), Vector3(s * 1.85, 0.56 + i * 0.07, -1.32), 0.04, 0.04, 6, DARK)
		if lod == 0:
			# sensore meteo e antenne
			b.cyl_ab("metal", Vector3(0.3, 0.8, 2.3), Vector3(0.3, 1.5, 2.3), 0.025, 0.025, 4, DARK)
			b.box("metal", Vector3(0.12, 0.08, 0.2), Vector3(0.3, 1.52, 2.3), DARK)
			for s: float in [-1.0, 1.0]:
				b.cyl_ab("metal", Vector3(s * 1.3, 0.8, 2.2), Vector3(s * 1.3, 3.0, 2.25), 0.02, 0.008, 4, DARK)
			b.face("faction", [Vector3(-1.3, 2.95, 2.25), Vector3(-1.3, 2.7, 2.25), Vector3(-1.3, 2.82, 2.8)], b.fac, Vector3(-1.4, 2.8, 2.3))
			b.face("faction", [Vector3(-1.3, 2.95, 2.25), Vector3(-1.3, 2.7, 2.25), Vector3(-1.3, 2.82, 2.8)], b.fac, Vector3(-1.2, 2.8, 2.3))
		), Vector3(0, 1.62, 0.2))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("aan_tank_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.1), Vector3(0, 0, -5.3), 0.13, 0.12, sg, pc * 0.92)
		for i in 3:
			b.cyl_ab("paint", Vector3(0, 0, -0.9 - i * 1.4), Vector3(0, 0, -1.0 - i * 1.4), 0.145, 0.145, sg, pc * 0.75)
		b.box("metal", Vector3(0.1, 0.1, 0.18), Vector3(0, 0.17, -5.15), DARK)
		b.cyl_ab("metal", Vector3(0, 0, -5.29), Vector3(0, 0, -5.31), 0.07, 0.07, sg, Color(0.02, 0.02, 0.02))
		), Vector3(0, 0.4, -2.45))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -5.4)))
	_meta(root, 7.4, 2.6)

## FO: carro pesante basso, torretta arrotondata a cupola con mattonelle reattive, cingoli larghi, canna lunga, fusti posteriori.
static func _tank_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.5
	var hw := 1.84
	root.add_child(_mi("Body", _m("fo_tank_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hullx(b, pc, hl, hw, 0.74, 1.48, 1.55, lod)
		_tracked(b, pc, hl, hw, 0.74, 6, 0.37, lod, 2)
		# corazza reattiva a V sullo spalto
		var gb := Basis(Vector3.RIGHT, -0.29)
		for s: float in [-1.0, 1.0]:
			_era(b, Vector3(s * 0.32, 1.2, -hl + 0.12), Vector3(s * 1.45, 1.2, -hl + 0.12), 4, 3, Vector3(0, 0.1, 0.38), Vector3(0.34, 0.12, 0.34), gb * Basis(Vector3.UP, s * 0.15), pc)
		# fusti di carburante esterni sul retro
		if lod < 2:
			for s: float in [-1.0, 1.0]:
				b.cyl("paint", 0.3, 0.3, 0.82, 12, Transform3D(_rx(), Vector3(s * 0.62, 1.45, hl + 0.22)), pc * 0.75)
				b.cyl("metal", 0.31, 0.31, 0.04, 12, Transform3D(_rx(), Vector3(s * 0.62, 1.45, hl + 0.22)), GUNMETAL)
			b.box("metal", Vector3(2.0, 0.06, 0.06), Vector3(0, 1.18, hl + 0.1), GUNMETAL)
			# parafanghi anteriori e cassette
			for s: float in [-1.0, 1.0]:
				b.box("paint", Vector3(0.72, 0.04, 0.5), Vector3(s * (hw - 0.37), 1.0, -hl - 0.12), pc, 0.0, Basis(Vector3.RIGHT, -0.3))
				b.box("paint", Vector3(0.6, 0.3, 1.1), Vector3(s * (hw - 0.35), 1.62, hl - 0.9), pc * 0.85, 0.03)
		if lod == 0:
			b.cyl("matte", 0.13, 0.13, 3.0, 8, Transform3D(_rx(), Vector3(0, 1.62, hl - 0.15)), WOOD)   # trave di disincaglio
		)))
	var secs := [[-2.05, 0.2, 0.5, 0.12, 2.6], [-1.8, 0.28, 1.2, 0.3, 2.6], [-1.25, 0.32, 1.6, 0.42, 2.7], [-0.25, 0.34, 1.78, 0.48, 2.8],
		[0.8, 0.33, 1.72, 0.46, 2.8], [1.45, 0.3, 1.45, 0.38, 2.6], [1.78, 0.25, 0.85, 0.2, 2.4]]
	var tur := _mi("Turret", _m("fo_tank_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var sg := 20 if lod == 0 else (14 if lod == 1 else 10)
		b.loft("paint", secs, sg, pc)
		# fascia della fazione attorno alla cupola
		b.loft("faction", [[-0.6, 0.38, 1.76, 0.17, 2.8], [0.3, 0.38, 1.79, 0.17, 2.8]], sg, b.fac, false)
		b.marks_x(1.745, 0.3, 1.0, 0.75, 0.3)
		b.box("faction", Vector3(0.8, 0.025, 0.7), Vector3(-0.2, 0.83, 0.6), b.fac)
		# mattonelle reattive a "sopracciglio" sulle guance e sul tetto anteriore
		for s: float in [-1.0, 1.0]:
			var yb := Basis(Vector3.UP, -s * 0.72) * Basis(Vector3.RIGHT, 0.4)
			_era(b, Vector3(s * 0.42, 0.5, -1.95), Vector3(s * 1.55, 0.5, -1.0), 4, 2, Vector3(0, 0.2, 0.12), Vector3(0.4, 0.26, 0.16), yb, pc)
		if lod < 2:
			_era(b, Vector3(-0.8, 0.8, -1.25), Vector3(0.8, 0.8, -1.25), 5, 2, Vector3(0, -0.02, 0.38), Vector3(0.3, 0.1, 0.34), Basis(Vector3.RIGHT, -0.12), pc)
			# cupola con mitragliatrice pesante
			b.cyl("paint", 0.36, 0.34, 0.2, 12, Transform3D(Basis.IDENTITY, Vector3(0.68, 0.86, 0.35)), pc)
			b.box("metal", Vector3(0.14, 0.18, 0.7), Vector3(0.68, 1.08, 0.1), DARK, 0.02)
			b.cyl_ab("metal", Vector3(0.68, 1.1, -0.25), Vector3(0.68, 1.1, -1.35), 0.035, 0.03, 6, DARK)
			b.box("paint", Vector3(0.36, 0.22, 0.06), Vector3(0.68, 1.05, -0.25), pc * 0.8)
			# mirino e proiettore
			b.box("paint", Vector3(0.36, 0.34, 0.42), Vector3(-0.8, 0.88, -0.8), pc * 0.95, 0.04)
			b.box("glass", Vector3(0.26, 0.2, 0.03), Vector3(-0.8, 0.9, -1.02), GLASS)
			for s: float in [-1.0, 1.0]:
				for i in 4:
					b.cyl_ab("metal", Vector3(s * (1.5 + i * 0.03), 0.5, -0.6 + i * 0.16), Vector3(s * (1.68 + i * 0.03), 0.62, -0.6 + i * 0.16), 0.05, 0.05, 6, DARK)
			# cassa posteriore e snorkel
			b.box("paint", Vector3(1.8, 0.42, 0.45), Vector3(0, 0.38, 1.95), pc * 0.8, 0.05)
			b.cyl_ab("paint", Vector3(-1.2, 0.3, 1.6), Vector3(-1.2, 0.3, 0.0), 0.11, 0.11, 8, pc * 0.7)
		if lod == 0:
			b.cyl_ab("metal", Vector3(1.1, 0.75, 1.3), Vector3(1.1, 3.0, 1.35), 0.02, 0.008, 4, DARK)
			b.face("faction", [Vector3(1.1, 2.95, 1.35), Vector3(1.1, 2.7, 1.35), Vector3(1.1, 2.82, 1.9)], b.fac, Vector3(1.0, 2.8, 1.4))
			b.face("faction", [Vector3(1.1, 2.95, 1.35), Vector3(1.1, 2.7, 1.35), Vector3(1.1, 2.82, 1.9)], b.fac, Vector3(1.2, 2.8, 1.4))
		), Vector3(0, 1.48, 0.15))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("fo_tank_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.0), Vector3(0, 0, -6.0), 0.12, 0.1, sg, pc * 0.92)
		b.cyl_ab("paint", Vector3(0, 0, 0.1), Vector3(0, 0, -0.5), 0.3, 0.22, sg, pc * 0.85)
		b.cyl_ab("paint", Vector3(0, 0, -2.6), Vector3(0, 0, -3.3), 0.16, 0.16, sg, pc * 0.8)
		for i in 2:
			b.cyl_ab("paint", Vector3(0, 0, -1.2 - i * 2.8), Vector3(0, 0, -1.3 - i * 2.8), 0.135, 0.135, sg, pc * 0.7)
		b.cyl_ab("metal", Vector3(0, 0, -5.99), Vector3(0, 0, -6.01), 0.06, 0.06, sg, Color(0.02, 0.02, 0.02))
		), Vector3(0, 0.38, -1.95))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -6.1)))
	_meta(root, 7.2, 2.3)

## CP: carro leggero su ruote 8x8, torretta compatta angolare, cannone medio con freno di bocca, antenne EW.
static func _tank_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.85
	root.add_child(_mi("Body", _m("cp_tank_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hull8(b, pc, hl, 1.45, 1.78, 1.45, lod)
		if lod < 2:
			_ew(b, Vector3(-1.2, 1.78, hl - 0.4), 2.6, pc)
			_ew(b, Vector3(1.2, 1.78, hl - 0.4), 2.2, pc)
		)))
	var prof := [Vector2(-0.55, -1.45), Vector2(0.55, -1.45), Vector2(1.22, -0.85), Vector2(1.3, 0.9), Vector2(1.12, 1.55),
		Vector2(-1.12, 1.55), Vector2(-1.3, 0.9), Vector2(-1.22, -0.85)]
	var tur := _mi("Turret", _m("cp_tank_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 0.72, pc, 0.86, Vector2(0, 0.08))
		UnitModels._band(b, prof, 0.72, 0.86, Vector2(0, 0.08), 0.28, 0.42, b.fac)
		b.marks_x(1.265, 0.14, 0.35, 0.75, 0.22, 0.25)
		b.box("paint", Vector3(0.7, 0.5, 0.3), Vector3(0, 0.34, -1.5), pc * 0.9, 0.03)
		b.box("faction", Vector3(0.7, 0.02, 0.6), Vector3(0, 0.73, 0.75), b.fac)
		if lod < 2:
			# alberino sensori, disturbatore a cupola e antenne
			b.cyl_ab("metal", Vector3(-0.6, 0.72, 0.7), Vector3(-0.6, 1.5, 0.7), 0.04, 0.04, 6, GUNMETAL)
			b.box("paint", Vector3(0.36, 0.28, 0.3), Vector3(-0.6, 1.6, 0.7), pc * 0.9, 0.03)
			b.box("glass", Vector3(0.24, 0.16, 0.02), Vector3(-0.6, 1.6, 0.54), GLASS)
			b.cyl("paint", 0.22, 0.26, 0.24, 12, Transform3D(Basis.IDENTITY, Vector3(0.55, 0.84, 0.95)), Color(0.75, 0.77, 0.75))
			b.box("paint", Vector3(0.4, 0.26, 0.5), Vector3(0.75, 0.84, -0.7), pc, 0.03)
			b.box("glass", Vector3(0.3, 0.16, 0.03), Vector3(0.75, 0.86, -0.96), GLASS)
			for s: float in [-1.0, 1.0]:
				_ew(b, Vector3(s * 0.95, 0.72, 1.3), 2.0, pc)
				for i in 3:
					b.cyl_ab("metal", Vector3(s * 1.15, 0.36 + i * 0.1, -0.8), Vector3(s * 1.32, 0.44 + i * 0.1, -0.95), 0.045, 0.045, 6, DARK)
		), Vector3(0, 1.78, 0.35))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("cp_tank_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.0), Vector3(0, 0, -4.9), 0.1, 0.085, sg, pc * 0.92)
		b.cyl_ab("paint", Vector3(0, 0, -1.8), Vector3(0, 0, -2.4), 0.13, 0.13, sg, pc * 0.82)
		b.box("metal", Vector3(0.28, 0.2, 0.42), Vector3(0, 0, -5.0), GUNMETAL, 0.02)
		b.box("metal", Vector3(0.3, 0.06, 0.06), Vector3(0, 0, -5.0), DARK)
		), Vector3(0, 0.36, -1.55))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -5.25)))
	_meta(root, 7.7, 2.6)

## UL: vecchio carro con torretta fusa a cupola, gabbia anti-drone sulla torretta, sacchetti di sabbia, cingoli di scorta, colori misti.
static func _tank_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var pt := UnitModels._paint(Color(0.3, 0.32, 0.22), c, tint * 0.7)   # torretta di recupero verde sbiadito
	var hl := 3.15
	var hw := 1.65
	root.add_child(_mi("Body", _m("ul_tank_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hullx(b, pc, hl, hw, 0.58, 1.42, 1.3, lod)
		_tracked(b, pc, hl, hw, 0.58, 5, 0.41, lod, 0)
		b.marks_x(hw + 0.005, 1.22, 0.65, 0.6, 0.26)
		# maglie di cingolo di scorta e sacchetti sullo spalto
		var gb := Basis(Vector3.RIGHT, -0.33)
		for i in 5:
			b.box("rubber", Vector3(0.55, 0.06, 0.16), Vector3(-0.9, 1.22 + i * 0.045, -hl + 0.15 + i * 0.16), TRACK, 0.0, gb)
		_bags(b, Vector3(0.0, 1.32, -hl + 0.55), Vector3(1.3, 1.32, -hl + 0.55), 3, 2, 0.0)
		if lod < 2:
			# sacchetti sui parafanghi e tronchi, fusti arrugginiti sul retro
			for s: float in [-1.0, 1.0]:
				_bags(b, Vector3(s * (hw - 0.3), 1.15, -hl + 0.6), Vector3(s * (hw - 0.3), 1.15, -0.2), 3, 1, PI * 0.5)
			b.cyl("matte", 0.16, 0.16, 2.8, 8, Transform3D(_rx(), Vector3(0, 1.58, hl + 0.05)), WOOD)
			b.cyl("paint", 0.28, 0.28, 0.8, 10, Transform3D(Basis.IDENTITY, Vector3(-0.8, 1.82, hl - 0.6)), RUST)
			b.cyl("paint", 0.28, 0.28, 0.8, 10, Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.82, hl - 0.6)), Color(0.25, 0.3, 0.22))
			b.box("matte", Vector3(1.0, 0.25, 0.7), Vector3(0.75, 1.55, hl - 0.6), CLOTH * 1.1, 0.08)
		)))
	var secs := [[-1.45, 0.2, 0.5, 0.15, 2.0], [-1.2, 0.3, 0.98, 0.38, 2.0], [-0.65, 0.35, 1.22, 0.52, 2.0], [0.15, 0.36, 1.25, 0.55, 2.0],
		[0.85, 0.33, 1.06, 0.46, 2.0], [1.25, 0.28, 0.62, 0.26, 2.0]]
	var tur := _mi("Turret", _m("ul_tank_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var sg := 18 if lod == 0 else (12 if lod == 1 else 8)
		b.loft("paint", secs, sg, pt)
		# simbolo della fazione dipinto a mano sui fianchi
		for s: float in [-1.0, 1.0]:
			b.box("faction", Vector3(0.02, 0.32, 0.55), Vector3(s * 1.2, 0.45, 0.0), b.fac, 0.0, Basis(Vector3.BACK, s * 0.25))
		b.cyl("paint", 0.34, 0.32, 0.14, 12, Transform3D(Basis.IDENTITY, Vector3(-0.45, 0.88, 0.2)), pt * 0.9)
		b.cyl("paint", 0.3, 0.3, 0.1, 12, Transform3D(Basis.IDENTITY, Vector3(0.45, 0.86, 0.3)), pt * 0.85)
		# mitragliatrice pesante con scudo improvvisato
		b.cyl_ab("metal", Vector3(0.45, 0.9, 0.3), Vector3(0.45, 1.15, 0.2), 0.04, 0.04, 6, DARK)
		b.box("metal", Vector3(0.15, 0.17, 0.6), Vector3(0.45, 1.2, 0.0), DARK)
		b.cyl_ab("metal", Vector3(0.45, 1.22, -0.3), Vector3(0.45, 1.22, -1.25), 0.035, 0.03, 6, DARK)
		b.box("paint", Vector3(0.6, 0.38, 0.04), Vector3(0.45, 1.25, -0.35), RUST * 1.3)
		# gabbia anti-drone: pali, correnti e graticcio sopra la torretta
		var posts := [Vector3(-1.4, 0, -0.9), Vector3(1.4, 0, -0.9), Vector3(-1.5, 0, 0.9), Vector3(1.5, 0, 0.9), Vector3(-0.8, 0, 1.45), Vector3(0.8, 0, 1.45)]
		var ytop := 1.75
		for p: Vector3 in posts:
			b.cyl_ab("metal", p + Vector3(0, 0.25, 0), p + Vector3(0, ytop, 0), 0.03, 0.03, 4, GUNMETAL)
		for i in 4:
			var z := lerpf(-1.0, 1.45, float(i) / 3.0)
			b.cyl_ab("metal", Vector3(-1.5, ytop, z), Vector3(1.5, ytop, z), 0.025, 0.025, 4, GUNMETAL)
		for i in 5:
			var x := lerpf(-1.45, 1.45, float(i) / 4.0)
			b.cyl_ab("metal", Vector3(x, ytop + 0.02, -1.0), Vector3(x, ytop + 0.02, 1.45), 0.02, 0.02, 4, GUNMETAL)
		if lod < 2:
			# rete mimetica stracciata sul graticcio e gabbia laterale a doghe
			b.box("matte", Vector3(1.8, 0.03, 1.2), Vector3(0.3, ytop + 0.05, 0.6), CLOTH * 0.9, 0.0, Basis(Vector3.BACK, 0.06))
			for s: float in [-1.0, 1.0]:
				for k in 2:
					b.cyl_ab("metal", Vector3(s * 1.45, 0.45 + k * 0.45, -0.9), Vector3(s * 1.5, 0.45 + k * 0.45, 0.9), 0.02, 0.02, 4, GUNMETAL)
				for k in 6:
					var z := lerpf(-0.9, 0.9, float(k) / 5.0)
					b.box("metal", Vector3(0.03, 0.7, 0.04), Vector3(s * 1.48, 0.65, z), GUNMETAL)
		), Vector3(0, 1.42, -0.25))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("ul_tank_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.0), Vector3(0, 0, -4.4), 0.1, 0.09, sg, pt * 0.9)
		b.cyl_ab("paint", Vector3(0, 0, 0.1), Vector3(0, 0, -0.4), 0.24, 0.2, sg, pt * 0.85)
		b.cyl_ab("paint", Vector3(0, 0, -3.5), Vector3(0, 0, -4.0), 0.15, 0.15, sg, pt * 0.8)
		b.cyl_ab("metal", Vector3(0, 0, -4.39), Vector3(0, 0, -4.41), 0.055, 0.055, sg, Color(0.02, 0.02, 0.02))
		), Vector3(0, 0.36, -1.35))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -4.5)))
	_meta(root, 6.6, 3.2)

# ============================================================== ARTIGLIERIA
## AAN: lanciarazzi multiplo cingolato con cabina blindata e due contenitori di razzi brandeggiabili.
static func _art_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.55
	root.add_child(_mi("Body", _m("aan_art_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		UnitModels._chassis(b, pc, hl, 1.66, lod, 6)
		b.prism_x("paint", [Vector2(-hl + 0.05, 1.55), Vector2(-hl + 0.4, 2.6), Vector2(-hl + 1.9, 2.72), Vector2(-hl + 2.0, 1.55)], -1.5, 1.5, pc)
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.6, 0.32, 0.03), Vector3(s * 0.55, 2.2, -hl + 0.24), GLASS, 0.0, Basis(Vector3.RIGHT, -0.32))
			b.box("glass", Vector3(0.03, 0.3, 0.6), Vector3(s * 1.51, 2.3, -hl + 1.0), GLASS)
			b.box("faction", Vector3(0.02, 0.3, 0.5), Vector3(s * 1.51, 1.9, -hl + 1.6), b.fac)
		b.box("faction", Vector3(1.1, 0.02, 0.6), Vector3(0, 2.73, -hl + 1.1), b.fac)
		b.marks_x(1.505, 1.85, -hl + 0.75, 0.7, 0.3)
		if lod < 2:
			b.box("paint", Vector3(0.3, 0.25, 0.3), Vector3(0.9, 2.85, -hl + 1.2), pc * 0.8, 0.03)
			b.box("metal", Vector3(1.2, 0.04, 0.9), Vector3(-0.2, 2.75, -hl + 1.2), GUNMETAL)
			b.cyl_ab("metal", Vector3(-1.2, 2.72, -hl + 1.6), Vector3(-1.2, 4.6, -hl + 1.62), 0.02, 0.008, 4, DARK)
		)))
	var tur := _mi("Turret", _m("aan_art_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.box("paint", Vector3(2.3, 0.35, 2.6), Vector3(0, 0.18, 0), pc * 0.9, 0.04)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.14, 0.9, 0.7), Vector3(s * 1.1, 0.75, 0.9), pc * 0.85, 0.02)
		b.cyl("metal", 0.12, 0.12, 2.3, 8, Transform3D(_rx(), Vector3(0, 1.12, 0.9)), GUNMETAL)
		), Vector3(0, 1.62, 1.2))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("aan_art_pods", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.98, 0.95, 4.1), Vector3(s * 0.52, 0.42, -1.9), pc, 0.04)
			b.box("faction", Vector3(1.0, 0.2, 0.5), Vector3(s * 0.52, 0.42, -0.4), b.fac)
			if lod < 2:
				for i in 3:
					for j in 2:
						b.cyl("rubber", 0.13, 0.13, 0.04, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.52 + (i - 1) * 0.3, 0.42 + (j - 0.5) * 0.4, -3.96)), Color(0.05, 0.05, 0.05))
				for k in 4:
					b.box("metal", Vector3(1.0, 0.98, 0.05), Vector3(s * 0.52, 0.42, -0.4 - k * 1.1), GUNMETAL)
		), Vector3(0, 1.12, 0.9))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0.42, -4.1)))
	root.add_child(UnitModels.spades(c, lod, burnt, tint, pc, Vector3(0, 1.0, hl + 0.1), 2.4))
	_meta(root, 7.3, 3.2)

## FO: obice semovente pesante: grande torretta arrotondata, canna lunghissima con freno di bocca a doppio deflettore.
static func _art_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.8
	var hw := 1.8
	root.add_child(_mi("Body", _m("fo_art_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hullx(b, pc, hl, hw, 0.7, 1.52, 1.35, lod)
		_tracked(b, pc, hl, hw, 0.7, 7, 0.35, lod, 1)
		if lod < 2:
			b.box("paint", Vector3(0.12, 0.62, 0.12), Vector3(-0.15, 1.82, -hl + 0.75), pc * 0.8)
			b.box("paint", Vector3(0.12, 0.62, 0.12), Vector3(0.15, 1.82, -hl + 0.75), pc * 0.8)
			b.box("paint", Vector3(0.55, 0.1, 0.22), Vector3(0, 2.12, -hl + 0.75), pc * 0.8)
			_era(b, Vector3(-1.2, 1.25, -hl + 0.15), Vector3(1.2, 1.25, -hl + 0.15), 6, 1, Vector3.ZERO, Vector3(0.36, 0.12, 0.36), Basis(Vector3.RIGHT, -0.28), pc)
		)))
	var secs := [[-1.75, 0.55, 1.25, 0.55, 3.2], [-1.5, 0.66, 1.58, 0.66, 3.6], [0.4, 0.68, 1.68, 0.7, 3.8], [2.0, 0.66, 1.64, 0.66, 3.6], [2.45, 0.6, 1.4, 0.56, 3.2]]
	var tur := _mi("Turret", _m("fo_art_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var sg := 20 if lod == 0 else 12
		b.loft("paint", secs, sg, pc)
		b.loft("faction", [[-0.3, 0.86, 1.69, 0.16, 3.8], [1.2, 0.86, 1.68, 0.16, 3.8]], sg, b.fac, false)
		b.box("faction", Vector3(1.2, 0.025, 1.0), Vector3(0, 1.37, 1.2), b.fac)
		b.marks_x(1.635, 0.62, -0.3, 0.8, 0.34)
		b.box("paint", Vector3(1.1, 0.9, 0.4), Vector3(0, 0.7, -1.8), pc * 0.88, 0.06)
		if lod < 2:
			b.cyl("paint", 0.34, 0.3, 0.24, 12, Transform3D(Basis.IDENTITY, Vector3(0.85, 1.45, 0.1)), pc)
			b.box("metal", Vector3(0.13, 0.16, 0.6), Vector3(0.85, 1.65, -0.15), DARK)
			b.cyl_ab("metal", Vector3(0.85, 1.66, -0.45), Vector3(0.85, 1.66, -1.3), 0.03, 0.03, 6, DARK)
			b.box("paint", Vector3(0.42, 0.36, 0.45), Vector3(-0.9, 1.45, -0.9), pc, 0.04)
			b.box("glass", Vector3(0.3, 0.2, 0.03), Vector3(-0.9, 1.47, -1.13), GLASS)
			for s: float in [-1.0, 1.0]:
				b.box("paint", Vector3(0.05, 0.85, 1.1), Vector3(s * 1.7, 0.7, 1.0), pc * 0.82)
				for i in 4:
					b.cyl_ab("metal", Vector3(s * 1.55, 0.95, -0.9 + i * 0.17), Vector3(s * 1.78, 1.08, -1.0 + i * 0.17), 0.05, 0.05, 6, DARK)
			b.box("matte", Vector3(2.4, 0.3, 0.4), Vector3(0, 1.0, 2.55), CLOTH * 0.85, 0.08)
		), Vector3(0, 1.52, 0.95))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("fo_art_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.3), Vector3(0, 0, -8.0), 0.14, 0.11, sg, pc * 0.93)
		b.cyl_ab("paint", Vector3(0, 0, -3.4), Vector3(0, 0, -4.3), 0.18, 0.18, sg, pc * 0.84)
		b.box("metal", Vector3(0.46, 0.32, 0.4), Vector3(0, 0, -8.05), GUNMETAL, 0.04)
		b.box("metal", Vector3(0.46, 0.32, 0.3), Vector3(0, 0, -8.55), GUNMETAL, 0.04)
		b.cyl_ab("metal", Vector3(0, 0, -8.0), Vector3(0, 0, -8.6), 0.12, 0.12, sg, GUNMETAL)
		b.cyl_ab("paint", Vector3(0, 0.24, 0.2), Vector3(0, 0.24, -1.4), 0.09, 0.09, 8, pc * 0.8)
		), Vector3(0, 0.78, -1.85))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -8.75)))
	root.add_child(UnitModels.spades(c, lod, burnt, tint, pc, Vector3(0, 1.0, hl + 0.1), 2.8))
	_meta(root, 7.6, 3.1)

## CP: obice su ruote 8x8 con cabina corazzata anteriore e torretta posteriore angolare; vomeri di stabilizzazione.
static func _art_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 4.05
	root.add_child(_mi("Body", _m("cp_art_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hull8(b, pc, hl, 1.45, 1.75, 1.3, lod)
		# cabina rialzata con vetri blindati
		b.prism_x("paint", [Vector2(-hl + 0.6, 1.7), Vector2(-hl + 0.85, 2.45), Vector2(-hl + 2.1, 2.55), Vector2(-hl + 2.2, 1.7)], -1.4, 1.4, pc)
		b.box("glass", Vector3(2.2, 0.36, 0.03), Vector3(0, 2.1, -hl + 0.72), GLASS, 0.0, Basis(Vector3.RIGHT, -0.32))
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.03, 0.3, 0.7), Vector3(s * 1.41, 2.15, -hl + 1.45), GLASS)
			b.box("paint", Vector3(0.6, 0.12, 0.5), Vector3(s * 0.9, 0.55, hl + 0.1), pc * 0.75, 0.02, Basis(Vector3.RIGHT, 0.6))
		b.box("faction", Vector3(1.0, 0.02, 0.6), Vector3(0, 2.56, -hl + 1.4), b.fac)
		if lod < 2:
			_ew(b, Vector3(-1.1, 2.55, -hl + 1.9), 2.2, pc)
			_ew(b, Vector3(1.1, 2.55, -hl + 1.9), 1.8, pc)
		)))
	var prof := [Vector2(-1.25, -1.45), Vector2(1.25, -1.45), Vector2(1.4, -1.0), Vector2(1.4, 1.95), Vector2(-1.4, 1.95), Vector2(-1.4, -1.0)]
	var tur := _mi("Turret", _m("cp_art_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 1.15, pc, 0.92, Vector2(0, 0.06))
		UnitModels._band(b, prof, 1.15, 0.92, Vector2(0, 0.06), 0.5, 0.68, b.fac)
		b.marks_x(1.375, 0.26, 0.5, 0.9, 0.34, 0.1)
		b.box("paint", Vector3(0.9, 0.75, 0.32), Vector3(0, 0.6, -1.5), pc * 0.9, 0.05)
		b.box("faction", Vector3(1.0, 0.02, 0.9), Vector3(0, 1.16, 1.1), b.fac)
		if lod < 2:
			b.box("paint", Vector3(0.36, 0.3, 0.4), Vector3(-0.8, 1.3, -0.8), pc, 0.03)
			b.box("glass", Vector3(0.26, 0.18, 0.03), Vector3(-0.8, 1.32, -1.01), GLASS)
			b.box("paint", Vector3(0.45, 0.15, 0.45), Vector3(0.75, 1.22, 0.3), pc * 0.85)
			b.cyl_ab("metal", Vector3(0.75, 1.36, 0.25), Vector3(0.75, 1.36, -0.6), 0.025, 0.025, 6, DARK)
			_ew(b, Vector3(-1.0, 1.15, 1.6), 1.7, pc)
		), Vector3(0, 1.75, 1.45))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("cp_art_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.3), Vector3(0, 0, -7.0), 0.12, 0.095, sg, pc * 0.93)
		b.cyl_ab("paint", Vector3(0, 0, -2.6), Vector3(0, 0, -3.3), 0.16, 0.16, sg, pc * 0.84)
		b.box("metal", Vector3(0.38, 0.26, 0.6), Vector3(0, 0, -7.2), GUNMETAL, 0.04)
		), Vector3(0, 0.65, -1.55))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -7.55)))
	root.add_child(UnitModels.spades(c, lod, burnt, tint, pc, Vector3(0, 1.05, hl + 0.05), 2.2))
	_meta(root, 8.1, 3.0)

## UL: camion civile 6x6 a muso lungo con lanciarazzi a tubi sul cassone, teloni e pannelli di colori diversi.
static func _art_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("ul_art_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_old_truck(b, pc, lod)
		b.box("paint", Vector3(2.35, 0.14, 4.3), Vector3(0, 1.32, 1.55), pc * 0.75, 0.02)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.35, 0.6, 0.18), Vector3(s * 0.95, 0.75, 3.55), RUST, 0.02)   # stabilizzatori
		)))
	var tur := _mi("Turret", _m("ul_art_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.cyl("metal", 0.75, 0.8, 0.25, 14, Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.12, 0.75, 0.9), Vector3(s * 0.72, 0.55, 0.0), pc * 0.85, 0.02)
		b.box("metal", Vector3(0.6, 0.35, 0.6), Vector3(-0.95, 0.45, 0.3), DARK, 0.02)   # posto del puntatore
		), Vector3(0, 1.4, 2.35))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("ul_art_tubes", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var sg := 7 if lod == 0 else 5
		var nx := 8 if lod < 2 else 4
		for j in 3:
			for i in nx:
				var x := lerpf(-0.62, 0.62, float(i) / float(nx - 1))
				var y := 0.05 + j * 0.2
				b.cyl_ab("paint", Vector3(x, y, 0.4), Vector3(x, y, -2.75), 0.085, 0.085, sg, pc * (0.85 + 0.1 * float((i + j) % 2)))
		for k in 3:
			b.box("paint", Vector3(1.5, 0.66, 0.1), Vector3(0, 0.25, 0.3 - k * 1.4), pc * 0.7, 0.02)
		b.box("faction", Vector3(1.52, 0.18, 0.5), Vector3(0, 0.35, -0.45), b.fac)
		), Vector3(0, 0.8, 0.0))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0.25, -2.85)))
	root.add_child(UnitModels.spades(c, lod, burnt, tint, pc, Vector3(0, 0.9, 3.75), 2.0))
	_meta(root, 7.8, 3.0)

## Camion civile 6x6 a muso lungo (UL): telaio, ruote, cofano con parafanghi tondi, cabina con vetri. Cassone a carico del chiamante.
static func _old_truck(b: ModelKit, pc: Color, lod: int) -> void:
	b.camo = 1.0
	b.dirt_h = 1.0
	b.box("metal", Vector3(1.05, 0.25, 7.4), Vector3(0, 0.9, 0.2), DARK)
	for z: float in [-2.65, 1.45, 2.8]:
		for s: float in [-1.0, 1.0]:
			_wheel(b, Vector3(s * 1.0, 0.55, z), 0.55, 0.4, lod, pc * 0.6)
	var hood := Color(0.36, 0.38, 0.27)   # cofano di recupero verde
	b.box("paint", Vector3(1.5, 0.7, 1.5), Vector3(0, 1.38, -3.0), UnitModels._paint(hood, b.fac, 0.08), 0.12)
	b.box("metal", Vector3(1.3, 0.55, 0.06), Vector3(0, 1.32, -3.76), DARK)
	for s: float in [-1.0, 1.0]:
		b.box("paint", Vector3(0.52, 0.06, 1.25), Vector3(s * 1.0, 1.2, -2.65), pc * 0.85, 0.0)
		b.box("paint", Vector3(0.52, 0.06, 0.45), Vector3(s * 1.0, 1.05, -3.4), pc * 0.85, 0.0, Basis(Vector3.RIGHT, -0.6))
		b.box("light", Vector3(0.18, 0.18, 0.05), Vector3(s * 0.55, 1.5, -3.78), Color(1, 0.95, 0.8))
	b.box("paint", Vector3(2.3, 1.25, 1.6), Vector3(0, 1.95, -1.55), pc, 0.08)
	b.box("glass", Vector3(1.9, 0.55, 0.04), Vector3(0, 2.25, -2.36), GLASS, 0.0, Basis(Vector3.RIGHT, 0.1))
	for s: float in [-1.0, 1.0]:
		b.box("glass", Vector3(0.04, 0.45, 0.7), Vector3(s * 1.16, 2.22, -1.65), GLASS)
		b.box("faction", Vector3(0.02, 0.4, 0.5), Vector3(s * 1.165, 1.7, -1.4), b.fac)
		b.box("paint", Vector3(0.36, 0.38, 0.95), Vector3(s * 0.85, 1.05, -0.4), RUST * 1.2, 0.05)
	b.box("metal", Vector3(2.2, 0.16, 0.14), Vector3(0, 0.95, -3.85), GUNMETAL)
	b.marks_x(1.155, 1.6, -0.95, 0.42, 0.22)

# ============================================================== CONTRAEREA
## AAN: contraerea missilistica cingolata: torretta piatta, due contenitori da 4 missili, pannello radar rotante, sensore EO.
static func _aa_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("aan_aa_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		UnitModels._chassis(b, pc, 3.45, 1.66, lod, 6))))
	var prof := [Vector2(-1.0, -1.35), Vector2(1.0, -1.35), Vector2(1.2, -0.95), Vector2(1.2, 1.45), Vector2(-1.2, 1.45), Vector2(-1.2, -0.95)]
	var tur := _mi("Turret", _m("aan_aa_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 0.85, pc, 0.92, Vector2(0, 0.05))
		UnitModels._band(b, prof, 0.85, 0.92, Vector2(0, 0.05), 0.32, 0.5, b.fac)
		b.marks_x(1.18, 0.16, 0.3, 0.75, 0.24, 0.11)
		b.box("faction", Vector3(0.8, 0.02, 0.6), Vector3(0, 0.86, -0.3), b.fac)
		# sfera del sensore elettro-ottico
		b.cyl_ab("paint", Vector3(0, 0.85, -0.85), Vector3(0, 1.1, -0.85), 0.14, 0.14, 8, pc * 0.8)
		b.sphere("paint", Vector3(0, 1.3, -0.85), Vector3(0.26, 0.26, 0.26), 12, 6, pc * 0.9)
		b.box("glass", Vector3(0.24, 0.2, 0.06), Vector3(0, 1.3, -1.09), GLASS)
		b.cyl_ab("paint", Vector3(0, 0.85, 1.0), Vector3(0, 1.45, 1.0), 0.13, 0.11, 8, pc * 0.85)
		), Vector3(0, 1.62, 0.35))
	root.add_child(tur)
	var radar := _mi("Radar", _m("aan_aa_radar", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.3, 0.2, 0.3), Vector3(0, 0.1, 0), GUNMETAL)
		b.box("paint", Vector3(1.7, 0.95, 0.16), Vector3(0, 0.7, 0), pc * 1.02, 0.04, Basis(Vector3.RIGHT, 0.2))
		b.box("rubber", Vector3(1.5, 0.8, 0.02), Vector3(0, 0.71, -0.1), Color(0.18, 0.2, 0.2), 0.0, Basis(Vector3.RIGHT, 0.2))
		), Vector3(0, 1.45, 1.0))
	tur.add_child(radar)
	var bar := _mi("Barrel", _m("aan_aa_pods", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.62, 0.66, 2.6), Vector3(s * 1.55, 0, -0.5), pc * 0.95, 0.05)
			b.box("faction", Vector3(0.63, 0.16, 0.45), Vector3(s * 1.55, 0.18, 0.4), b.fac)
			b.cyl_ab("paint", Vector3(s * 1.25, 0, 0), Vector3(s * 1.0, 0, 0), 0.2, 0.2, 10, pc * 0.8)
			for i in 2:
				for j in 2:
					b.box("matte", Vector3(0.24, 0.24, 0.03), Vector3(s * 1.55 + (i - 0.5) * 0.28, (j - 0.5) * 0.28, -1.81), Color(0.7, 0.68, 0.6))
		), Vector3(0, 0.5, -0.1))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(-1.55, 0.0, -1.9)))
	bar.add_child(_mk("Muzzle2", Vector3(1.55, 0.0, -1.9)))
	_meta(root, 6.9, 3.6)

## FO: contraerea cannoni+missili cingolata: torretta arrotondata, due coppie di cannoni, tubi lanciamissili, radar di tiro e di scoperta.
static func _aa_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.6
	var hw := 1.75
	root.add_child(_mi("Body", _m("fo_aa_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hullx(b, pc, hl, hw, 0.68, 1.55, 1.4, lod)
		_tracked(b, pc, hl, hw, 0.68, 6, 0.38, lod, 1))))
	var secs := [[-1.5, 0.5, 1.0, 0.5, 3.0], [-1.2, 0.58, 1.28, 0.58, 3.2], [0.8, 0.6, 1.32, 0.6, 3.2], [1.5, 0.55, 1.15, 0.52, 3.0]]
	var tur := _mi("Turret", _m("fo_aa_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var sg := 18 if lod == 0 else 12
		b.loft("paint", secs, sg, pc)
		b.loft("faction", [[-0.6, 0.72, 1.33, 0.14, 3.2], [0.6, 0.72, 1.33, 0.14, 3.2]], sg, b.fac, false)
		b.marks_x(1.305, 0.42, -0.1, 0.8, 0.3)
		# radar di tiro anteriore a disco
		b.cyl("metal", 0.5, 0.5, 0.18, 16, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.75, -1.6)), Color(0.3, 0.31, 0.3))
		b.sphere("paint", Vector3(0, 0.75, -1.72), Vector3(0.5, 0.5, 0.16), 16, 5, pc * 1.08, true, Basis(Vector3.RIGHT, -PI * 0.5))
		b.cyl_ab("paint", Vector3(0, 1.1, 1.0), Vector3(0, 1.55, 1.0), 0.15, 0.12, 8, pc * 0.85)
		), Vector3(0, 1.55, 0.3))
	root.add_child(tur)
	var radar := _mi("Radar", _m("fo_aa_radar", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.3, 0.2, 0.3), Vector3(0, 0.1, 0), GUNMETAL)
		b.sphere("paint", Vector3(0, 0.55, 0.12), Vector3(1.15, 0.38, 0.14), 16, 6, pc * 1.05, false)
		b.cyl_ab("metal", Vector3(0, 0.55, 0.0), Vector3(0, 0.55, -0.6), 0.03, 0.03, 4, GUNMETAL)
		b.box("metal", Vector3(0.12, 0.12, 0.12), Vector3(0, 0.55, -0.65), GUNMETAL)
		), Vector3(0, 1.55, 1.0))
	tur.add_child(radar)
	var bar := _mi("Barrel", _m("fo_aa_guns", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.5, 0.65, 1.6), Vector3(s * 1.55, 0, -0.1), pc * 0.95, 0.06)
			b.box("faction", Vector3(0.51, 0.14, 0.4), Vector3(s * 1.55, 0.2, 0.45), b.fac)
			b.cyl_ab("paint", Vector3(s * 1.35, 0, 0), Vector3(s * 1.1, 0, 0), 0.2, 0.2, 10, pc * 0.8)
			for g in 2:
				var gx := s * (1.42 + g * 0.26)
				b.cyl_ab("metal", Vector3(gx, -0.12, -0.9), Vector3(gx, -0.12, -3.6), 0.05, 0.04, 8, GUNMETAL)
				b.cyl_ab("metal", Vector3(gx, -0.12, -3.4), Vector3(gx, -0.12, -3.7), 0.075, 0.075, 8, DARK)
			# tubi lanciamissili sopra i cannoni
			for m in 2:
				var mx := s * (1.42 + m * 0.26)
				b.cyl_ab("paint", Vector3(mx, 0.48, 0.4), Vector3(mx, 0.48, -1.6), 0.11, 0.11, 8, pc * 0.85)
				b.cyl_ab("matte", Vector3(mx, 0.48, -1.6), Vector3(mx, 0.48, -1.62), 0.1, 0.1, 8, Color(0.65, 0.62, 0.55))
		), Vector3(0, 0.6, -0.2))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(-1.55, -0.12, -3.75)))
	bar.add_child(_mk("Muzzle2", Vector3(1.55, -0.12, -3.75)))
	_meta(root, 7.2, 3.8)

## CP: contraerea 8x8 con lanciatore di contenitori brandeggiabile e alto albero radar a quattro facce (rotante).
static func _aa_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.95
	root.add_child(_mi("Body", _m("cp_aa_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hull8(b, pc, hl, 1.45, 1.75, 1.3, lod)
		b.prism_x("paint", [Vector2(-hl + 0.55, 1.7), Vector2(-hl + 0.8, 2.4), Vector2(-hl + 1.9, 2.5), Vector2(-hl + 2.0, 1.7)], -1.4, 1.4, pc)
		b.box("glass", Vector3(2.2, 0.32, 0.03), Vector3(0, 2.05, -hl + 0.67), GLASS, 0.0, Basis(Vector3.RIGHT, -0.32))
		b.box("faction", Vector3(1.0, 0.02, 0.5), Vector3(0, 2.51, -hl + 1.35), b.fac)
		b.marks_x(1.405, 1.95, -hl + 1.3, 0.6, 0.28)
		# albero radar ripiegabile dietro la cabina
		b.box("paint", Vector3(0.5, 0.4, 0.5), Vector3(0, 1.95, -hl + 2.45), pc * 0.85, 0.03)
		b.cyl_ab("metal", Vector3(0, 2.1, -hl + 2.45), Vector3(0, 3.6, -hl + 2.45), 0.1, 0.08, 8, GUNMETAL)
		if lod < 2:
			_ew(b, Vector3(-1.15, 1.75, hl - 0.4), 2.2, pc)
			_ew(b, Vector3(1.15, 1.75, hl - 0.4), 2.2, pc)
		)))
	var radar := _mi("Radar", _m("cp_aa_radar", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("paint", Vector3(0.95, 0.9, 0.95), Vector3(0, 0.45, 0), pc * 1.05, 0.04)
		for i in 4:
			var r := Basis(Vector3.UP, PI * 0.5 * i)
			b.box("rubber", Vector3(0.75, 0.72, 0.02), r * Vector3(0, 0.45, -0.48), Color(0.17, 0.19, 0.21), 0.0, r)
		b.box("faction", Vector3(0.97, 0.1, 0.97), Vector3(0, 0.95, 0), b.fac)
		), Vector3(0, 3.6, -hl + 2.45))
	root.add_child(radar)
	var tur := _mi("Turret", _m("cp_aa_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.cyl("metal", 0.85, 0.9, 0.2, 16, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.14, 0.75, 0.8), Vector3(s * 1.05, 0.45, 0.6), pc * 0.85, 0.02)
		), Vector3(0, 1.75, 2.1))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("cp_aa_cans", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		for i in 4:
			for j in 2:
				var p := Vector3(-0.66 + i * 0.44, 0.22 + j * 0.44, -1.6)
				b.box("paint", Vector3(0.4, 0.4, 3.6), p, pc * (0.92 + 0.05 * float((i + j) % 2)), 0.03)
				b.box("matte", Vector3(0.32, 0.32, 0.03), p + Vector3(0, 0, -1.81), Color(0.72, 0.7, 0.62))
		b.box("faction", Vector3(1.8, 0.1, 0.5), Vector3(0, 0.9, -0.3), b.fac)
		), Vector3(0, 0.75, 0.75))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(-0.44, 0.44, -3.45)))
	bar.add_child(_mk("Muzzle2", Vector3(0.44, 0.44, -3.45)))
	_meta(root, 7.9, 4.6)

## UL: "tecnica" con cannone binato contraereo sul cassone di un pick-up.
static func _aa_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("ul_aa_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_pickup(b, pc, lod, 1))))
	var tur := _mi("Turret", _m("ul_aa_mount", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.cyl("metal", 0.55, 0.6, 0.12, 12, Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.1, 0.6, 0.55), Vector3(s * 0.38, 0.38, 0.05), pc * 0.8, 0.02)
			b.box("matte", Vector3(0.3, 0.06, 0.3), Vector3(s * 0.6, 0.45, 0.35), DARK)   # sedili dei serventi
		), Vector3(0, 1.18, 1.25))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("ul_aa_guns", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.box("paint", Vector3(0.62, 0.36, 1.1), Vector3(0, 0, 0.0), pc * 0.9, 0.04)
		for s: float in [-1.0, 1.0]:
			b.cyl_ab("metal", Vector3(s * 0.17, 0.08, -0.4), Vector3(s * 0.17, 0.08, -2.5), 0.04, 0.035, 8, DARK)
			b.cyl_ab("metal", Vector3(s * 0.17, 0.08, -2.35), Vector3(s * 0.17, 0.08, -2.6), 0.06, 0.06, 8, DARK)
			b.box("paint", Vector3(0.24, 0.3, 0.42), Vector3(s * 0.48, 0.05, 0.1), Color(0.25, 0.3, 0.22), 0.02)   # caricatori
		b.box("paint", Vector3(0.7, 0.42, 0.03), Vector3(0, 0.25, -0.45), RUST * 1.2)   # scudo
		b.box("faction", Vector3(0.3, 0.2, 0.02), Vector3(0, 0.3, -0.47), b.fac)
		), Vector3(0, 0.62, 0.0))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(-0.17, 0.08, -2.65)))
	bar.add_child(_mk("Muzzle2", Vector3(0.17, 0.08, -2.65)))
	_meta(root, 5.6, 2.8)

## Pick-up a doppia cabina (tecniche UL), lungo ~5.5 m, avanti -Z. Pannelli di colori diversi (cofano e porte di recupero).
## style 0 = cassone vuoto (per mitragliatrice), 1 = con sponde rinforzate (cannone binato).
static func _pickup(b: ModelKit, pc: Color, lod: int, style: int) -> void:
	b.camo = 1.0
	b.dirt_h = 0.8
	var cab := UnitModels._paint(Color(0.62, 0.6, 0.55), b.fac, 0.06)    # cabina bianca sbiadita
	var hood := UnitModels._paint(Color(0.3, 0.33, 0.24), b.fac, 0.06)   # cofano verde di recupero
	b.box("metal", Vector3(1.0, 0.2, 5.0), Vector3(0, 0.62, 0.0), DARK)
	for z: float in [-1.6, 1.5]:
		for s: float in [-1.0, 1.0]:
			_wheel(b, Vector3(s * 0.82, 0.4, z), 0.4, 0.3, lod, Color(0.5, 0.5, 0.48))
	# muso, parafanghi, cofano
	b.box("paint", Vector3(1.86, 0.5, 1.35), Vector3(0, 0.98, -1.95), pc, 0.08)
	b.box("paint", Vector3(1.6, 0.06, 1.25), Vector3(0, 1.25, -1.98), hood, 0.02, Basis(Vector3.RIGHT, 0.05))
	b.box("metal", Vector3(1.4, 0.32, 0.05), Vector3(0, 1.0, -2.64), DARK)
	b.box("metal", Vector3(1.9, 0.16, 0.16), Vector3(0, 0.75, -2.7), GUNMETAL)
	for s: float in [-1.0, 1.0]:
		b.box("light", Vector3(0.22, 0.12, 0.04), Vector3(s * 0.7, 1.08, -2.64), Color(1, 0.95, 0.8))
	# cabina doppia
	b.box("paint", Vector3(1.86, 0.55, 1.75), Vector3(0, 1.0, -0.42), cab, 0.06)
	for s: float in [-1.0, 1.0]:
		b.box("paint", Vector3(0.03, 0.45, 0.75), Vector3(s * 0.935, 1.0, -0.85), pc if s > 0.0 else hood, 0.0)   # porte spaiate
		b.box("faction", Vector3(0.02, 0.3, 0.42), Vector3(s * 0.955, 1.0, -0.05), b.fac)
	b.marks_x(0.952, 0.98, -0.85, 0.5, 0.24)
	b.hexa("glass", [Vector3(-0.88, 1.27, -1.28), Vector3(0.88, 1.27, -1.28), Vector3(0.88, 1.27, 0.45), Vector3(-0.88, 1.27, 0.45),
		Vector3(-0.8, 1.82, -0.75), Vector3(0.8, 1.82, -0.75), Vector3(0.8, 1.82, 0.4), Vector3(-0.8, 1.82, 0.4)], GLASS)
	b.box("paint", Vector3(1.66, 0.06, 1.2), Vector3(0, 1.84, -0.17), cab, 0.02)
	for z: float in [-1.2, -0.35, 0.42]:
		for s: float in [-1.0, 1.0]:
			var zt := maxf(z, -0.72)
			b.cyl_ab("paint", Vector3(s * 0.87, 1.27, z), Vector3(s * 0.8, 1.83, zt), 0.035, 0.035, 4, cab * 0.9)
	# cassone
	b.box("paint", Vector3(1.8, 0.1, 2.0), Vector3(0, 0.82, 1.5), pc * 0.85)
	for s: float in [-1.0, 1.0]:
		b.box("paint", Vector3(0.06, 0.45, 2.0), Vector3(s * 0.9, 1.08, 1.5), pc * (0.95 if s > 0.0 else 0.8), 0.01)
		b.box("light", Vector3(0.08, 0.2, 0.04), Vector3(s * 0.8, 1.05, 2.53), Color(0.9, 0.2, 0.15))
	b.box("paint", Vector3(1.8, 0.45, 0.06), Vector3(0, 1.08, 2.5), pc * 0.75, 0.01)
	if style == 1 and lod < 2:
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.08, 0.3, 1.9), Vector3(s * 0.92, 1.42, 1.5), RUST * 1.1, 0.0)
	if lod < 2:
		# ruota di scorta, taniche e roll-bar
		b.cyl("rubber", 0.36, 0.36, 0.24, 12, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.5, 1.12, 0.62)), DARK)
		b.box("paint", Vector3(0.18, 0.4, 0.3), Vector3(0.65, 1.07, 0.65), Color(0.24, 0.3, 0.2), 0.02)
		b.cyl_ab("metal", Vector3(-0.85, 1.3, 0.55), Vector3(-0.85, 2.0, 0.55), 0.04, 0.04, 6, GUNMETAL)
		b.cyl_ab("metal", Vector3(0.85, 1.3, 0.55), Vector3(0.85, 2.0, 0.55), 0.04, 0.04, 6, GUNMETAL)
		b.cyl_ab("metal", Vector3(-0.85, 2.0, 0.55), Vector3(0.85, 2.0, 0.55), 0.04, 0.04, 6, GUNMETAL)
		b.cyl_ab("metal", Vector3(0.7, 1.84, -0.3), Vector3(0.7, 3.2, -0.25), 0.015, 0.006, 4, DARK)
		b.face("faction", [Vector3(0.7, 3.15, -0.25), Vector3(0.7, 2.75, -0.25), Vector3(0.7, 2.95, 0.4)], b.fac, Vector3(0.6, 2.95, -0.2))
		b.face("faction", [Vector3(0.7, 3.15, -0.25), Vector3(0.7, 2.75, -0.25), Vector3(0.7, 2.95, 0.4)], b.fac, Vector3(0.8, 2.95, -0.2))

# ============================================================== CAMION / TRASPORTO
## AAN: veicolo protetto 6x6 tipo anti-mina: scafo a V, cabina con vetri spessi, vano truppe squadrato, stazione d'arma remotizzata.
static func _truck_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("aan_truck_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.dirt_h = 1.0
		for z: float in [-2.55, 1.15, 2.6]:
			for s: float in [-1.0, 1.0]:
				_wheel(b, Vector3(s * 1.05, 0.62, z), 0.62, 0.45, lod, pc * 0.7)
		# scafo a V
		b.prism_x("paint", [Vector2(-3.2, 1.2), Vector2(-2.6, 0.75), Vector2(3.4, 0.75), Vector2(3.6, 1.2)], -0.45, 0.45, pc * 0.75)
		b.hexa("paint", [Vector3(-0.45, 0.75, -2.6), Vector3(0.45, 0.75, -2.6), Vector3(0.45, 0.75, 3.4), Vector3(-0.45, 0.75, 3.4),
			Vector3(-1.25, 1.3, -3.3), Vector3(1.25, 1.3, -3.3), Vector3(1.25, 1.3, 3.6), Vector3(-1.25, 1.3, 3.6)], pc * 0.85)
		# cofano corto, cabina e vano truppe
		b.box("paint", Vector3(2.3, 0.6, 1.2), Vector3(0, 1.6, -3.2), pc, 0.06)
		b.box("metal", Vector3(1.6, 0.4, 0.05), Vector3(0, 1.55, -3.82), DARK)
		b.hexa("paint", [Vector3(-1.25, 1.3, -2.65), Vector3(1.25, 1.3, -2.65), Vector3(1.25, 1.3, 3.6), Vector3(-1.25, 1.3, 3.6),
			Vector3(-1.12, 2.85, -1.9), Vector3(1.12, 2.85, -1.9), Vector3(1.12, 2.85, 3.5), Vector3(-1.12, 2.85, 3.5)], pc)
		b.box("glass", Vector3(1.9, 0.5, 0.03), Vector3(0, 2.4, -2.33), GLASS, 0.0, Basis(Vector3.RIGHT, -0.48))
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.03, 0.42, 0.5), Vector3(s * 1.2, 2.35, -1.6), GLASS, 0.0, Basis(Vector3.BACK, s * 0.08))
			b.box("glass", Vector3(0.03, 0.3, 0.3), Vector3(s * 1.19, 2.35, 0.6), GLASS, 0.0, Basis(Vector3.BACK, s * 0.08))
			b.box("glass", Vector3(0.03, 0.3, 0.3), Vector3(s * 1.19, 2.35, 1.8), GLASS, 0.0, Basis(Vector3.BACK, s * 0.08))
			b.box("faction", Vector3(0.02, 0.4, 0.8), Vector3(s * 1.24, 1.75, 0.9), b.fac, 0.0, Basis(Vector3.BACK, s * 0.08))
			b.box("light", Vector3(0.2, 0.12, 0.05), Vector3(s * 0.85, 1.75, -3.82), Color(1, 0.95, 0.8))
		b.box("faction", Vector3(1.2, 0.02, 1.0), Vector3(0, 2.86, 2.2), b.fac)
		b.marks_x(1.212, 1.75, 2.3, 0.7, 0.3, 0.084)
		if lod < 2:
			b.box("paint", Vector3(1.0, 1.3, 0.08), Vector3(0, 2.0, 3.62), pc * 0.9, 0.02)   # portellone posteriore
			b.cyl("rubber", 0.6, 0.6, 0.4, 14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 2.1, 3.85)), DARK)
			for s: float in [-1.0, 1.0]:
				b.cyl_ab("metal", Vector3(s * 0.9, 2.85, 3.0), Vector3(s * 0.9, 5.0, 3.05), 0.02, 0.008, 4, DARK)
			b.box("paint", Vector3(0.4, 0.25, 0.4), Vector3(-0.6, 2.98, -1.5), pc * 0.8, 0.03)   # disturbatore anti-IED
		)))
	var tur := _mi("Turret", _m("aan_truck_rws", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.cyl("paint", 0.42, 0.45, 0.14, 12, Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)), pc * 0.85)
		b.box("paint", Vector3(0.18, 0.4, 0.5), Vector3(0.3, 0.32, 0), pc * 0.9, 0.02)
		b.box("paint", Vector3(0.24, 0.22, 0.28), Vector3(-0.28, 0.36, -0.05), pc * 0.8, 0.02)
		b.box("glass", Vector3(0.18, 0.14, 0.02), Vector3(-0.28, 0.36, -0.2), GLASS)
		), Vector3(0, 2.85, -0.4))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("aan_truck_mg", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.14, 0.18, 0.7), Vector3(0, 0, 0.0), DARK)
		b.cyl_ab("metal", Vector3(0, 0.02, -0.35), Vector3(0, 0.02, -1.25), 0.03, 0.03, 6, DARK)
		), Vector3(0.05, 0.36, 0.0))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0.02, -1.3)))
	_meta(root, 7.6, 3.2)

## FO: camion pesante 6x6 a cabina avanzata (muso piatto), telone, ruota di scorta dietro la cabina.
static func _truck_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("fo_truck_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.dirt_h = 1.0
		b.box("metal", Vector3(1.1, 0.28, 7.8), Vector3(0, 0.95, 0.0), DARK)
		for z: float in [-2.55, 1.35, 2.85]:
			for s: float in [-1.0, 1.0]:
				_wheel(b, Vector3(s * 1.05, 0.62, z), 0.62, 0.48, lod, pc * 0.75)
		# cabina avanzata: muso piatto verticale
		b.box("paint", Vector3(2.5, 1.75, 1.8), Vector3(0, 2.05, -3.0), pc, 0.1)
		b.box("paint", Vector3(2.52, 0.12, 1.7), Vector3(0, 2.96, -3.0), pc * 0.9, 0.04)
		b.box("glass", Vector3(2.2, 0.62, 0.03), Vector3(0, 2.45, -3.91), GLASS)
		b.box("metal", Vector3(1.9, 0.5, 0.05), Vector3(0, 1.5, -3.91), DARK)
		b.box("metal", Vector3(2.5, 0.22, 0.2), Vector3(0, 1.05, -3.95), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.03, 0.5, 0.7), Vector3(s * 1.26, 2.45, -3.2), GLASS)
			b.box("faction", Vector3(0.02, 0.45, 0.6), Vector3(s * 1.265, 1.75, -2.7), b.fac)
			b.box("light", Vector3(0.22, 0.16, 0.05), Vector3(s * 0.95, 1.35, -3.92), Color(1, 0.95, 0.8))
			b.box("paint", Vector3(0.6, 0.08, 1.2), Vector3(s * 1.05, 1.32, -2.55), pc * 0.85)
			b.box("paint", Vector3(0.38, 0.4, 1.0), Vector3(s * 0.9, 1.1, -1.0), pc * 0.7, 0.05)
		# ruota di scorta verticale dietro la cabina
		b.cyl("rubber", 0.6, 0.6, 0.42, 14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.9, -1.75)), DARK)
		# cassone con telone squadrato e centine
		b.box("paint", Vector3(2.5, 0.55, 4.9), Vector3(0, 1.38, 1.3), pc * 0.9, 0.03)
		b.marks_x(1.255, 1.4, 0.0, 0.8, 0.34)
		b.camo = 0.0
		b.box("matte", Vector3(2.48, 1.45, 4.85), Vector3(0, 2.38, 1.3), Color(0.3, 0.31, 0.22), 0.12)
		b.box("faction", Vector3(1.4, 0.02, 1.2), Vector3(0, 3.11, 1.3), b.fac)
		if lod == 0:
			for i in 5:
				b.box("metal", Vector3(2.5, 0.04, 0.05), Vector3(0, 3.0, -0.9 + i * 1.1), GUNMETAL)
		)))
	root.add_child(_mk("Muzzle", Vector3(0, 2.0, -4.0)))
	_meta(root, 7.9, 3.1)

## CP: blindato 8x8 per la fanteria con torretta leggera telecomandata, rampa posteriore, antenne EW.
static func _truck_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	var hl := 3.85
	root.add_child(_mi("Body", _m("cp_truck_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_hull8(b, pc, hl, 1.42, 2.15, 1.55, lod)
		b.marks_x(1.465, 1.5, -2.0, 0.7, 0.3, 0.13)
		if lod < 2:
			b.box("paint", Vector3(1.6, 1.0, 0.08), Vector3(0, 1.55, hl + 0.02), pc * 0.88, 0.02)   # rampa
			_ew(b, Vector3(-1.15, 2.15, hl - 0.35), 2.6, pc)
			_ew(b, Vector3(1.15, 2.15, hl - 0.35), 2.2, pc)
			_ew(b, Vector3(-1.1, 2.15, -hl + 1.9), 1.6, pc)
			for s: float in [-1.0, 1.0]:
				for i in 3:
					b.box("glass", Vector3(0.03, 0.14, 0.2), Vector3(s * 1.47, 1.95, 0.0 + i * 1.0), GLASS)
		)))
	var tur := _mi("Turret", _m("cp_truck_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		var prof := [Vector2(-0.45, -0.7), Vector2(0.45, -0.7), Vector2(0.75, -0.3), Vector2(0.75, 0.75), Vector2(-0.75, 0.75), Vector2(-0.75, -0.3)]
		b.prism_y("paint", prof, 0.0, 0.5, pc, 0.85, Vector2(0, 0.05))
		UnitModels._band(b, prof, 0.5, 0.85, Vector2(0, 0.05), 0.18, 0.3, b.fac)
		b.box("paint", Vector3(0.3, 0.24, 0.32), Vector3(-0.45, 0.62, -0.2), pc * 0.85, 0.02)
		b.box("glass", Vector3(0.22, 0.16, 0.02), Vector3(-0.45, 0.62, -0.37), GLASS)
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(0.28, 0.36, 0.6), Vector3(s * 0.85, 0.3, 0.2), pc * 0.8, 0.03)   # missili controcarro
		), Vector3(0, 2.15, -0.1))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("cp_truck_gun", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("metal", Vector3(0, 0, 0.1), Vector3(0, 0, -2.4), 0.05, 0.045, 8, DARK)
		b.cyl_ab("paint", Vector3(0, 0, 0.1), Vector3(0, 0, -0.8), 0.1, 0.09, 8, pc * 0.8)
		b.cyl_ab("metal", Vector3(0, 0, -2.2), Vector3(0, 0, -2.45), 0.07, 0.07, 8, DARK)
		), Vector3(0, 0.25, -0.65))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -2.5)))
	_meta(root, 7.7, 2.8)

## UL: "tecnica" — pick-up con mitragliatrice pesante su piedistallo e scudo improvvisato.
static func _truck_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("ul_truck_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_pickup(b, pc, lod, 0)
		if lod < 2:
			b.box("matte", Vector3(0.5, 0.3, 0.4), Vector3(-0.5, 1.02, 2.1), CLOTH * 1.1, 0.06)
			b.cyl("paint", 0.22, 0.22, 0.55, 10, Transform3D(Basis.IDENTITY, Vector3(0.55, 1.15, 2.15)), RUST)
		)))
	var tur := _mi("Turret", _m("ul_truck_mount", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("metal", Vector3(0, 0, 0), Vector3(0, 0.75, 0), 0.07, 0.06, 8, GUNMETAL)
		b.cyl("metal", 0.3, 0.32, 0.06, 10, Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), GUNMETAL)
		), Vector3(0, 0.9, 1.35))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("ul_truck_hmg", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.16, 0.2, 0.85), Vector3(0, 0, 0.05), DARK)
		b.cyl_ab("metal", Vector3(0, 0.03, -0.35), Vector3(0, 0.03, -1.55), 0.035, 0.03, 6, DARK)
		b.cyl_ab("metal", Vector3(0, 0.03, -1.45), Vector3(0, 0.03, -1.62), 0.055, 0.055, 6, DARK)
		b.box("paint", Vector3(0.2, 0.18, 0.25), Vector3(0.18, -0.02, 0.0), Color(0.25, 0.3, 0.22))
		b.box("paint", Vector3(0.75, 0.5, 0.04), Vector3(0, 0.12, -0.42), RUST * 1.25)
		b.box("faction", Vector3(0.28, 0.18, 0.02), Vector3(0, 0.18, -0.445), b.fac)
		), Vector3(0, 0.82, 0.0))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0.03, -1.65)))
	_meta(root, 5.5, 2.6)

# ============================================================== BUNKER
## AAN: posto prefabbricato in cemento circondato da gabbioni di terra, palo con telecamera e antenne.
static func _bunker_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	root.add_child(_mi("Body", _m("aan_bunker_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var ring: Array = []
		for i in 12:
			var a := TAU * float(i) / 12.0
			ring.append(Vector2(cos(a) * 4.9, sin(a) * 4.9))
		b.prism_y("matte", ring, -0.05, 0.3, EARTH, 0.85)
		b.box("stained", Vector3(5.4, 2.2, 5.0), Vector3(0, 1.1, 0.2), CONCRETE * 0.95, 0.12)
		b.box("stained", Vector3(5.8, 0.35, 5.4), Vector3(0, 2.35, 0.2), CONCRETE * 0.88, 0.06)
		b.box("rubber", Vector3(2.6, 0.3, 0.3), Vector3(0, 1.5, -2.32), Color(0.03, 0.03, 0.03))
		b.box("faction", Vector3(5.82, 0.12, 5.42), Vector3(0, 2.2, 0.2), b.fac)
		b.box("faction", Vector3(1.6, 0.03, 1.6), Vector3(0, 2.54, 0.6), b.fac)
		# gabbioni di terra (muro anti-scheggia)
		var gab := Color(0.55, 0.5, 0.4)
		for i in 7:
			var x := -3.6 + i * 1.2
			if absf(x) < 0.5:
				continue
			b.box("matte", Vector3(1.1, 1.3, 1.1), Vector3(x, 0.65, -3.6), gab * (0.92 + 0.06 * float(i % 2)), 0.03)
			b.box("matte", Vector3(1.0, 0.05, 1.0), Vector3(x, 1.31, -3.6), EARTH * 1.1)
		for s: float in [-1.0, 1.0]:
			for i in 4:
				b.box("matte", Vector3(1.1, 1.3, 1.1), Vector3(s * 3.9, 0.65, -2.4 + i * 1.2), gab * (0.92 + 0.06 * float(i % 2)), 0.03)
		if lod < 2:
			for i in 7:
				b.box("metal", Vector3(1.12, 0.03, 0.03), Vector3(-3.6 + i * 1.2, 1.0, -4.16), GUNMETAL)
			# palo con telecamera/sensore e antenne
			b.cyl_ab("metal", Vector3(1.9, 2.5, 1.8), Vector3(1.9, 6.2, 1.8), 0.07, 0.05, 6, GUNMETAL)
			b.box("paint", Vector3(0.4, 0.3, 0.5), Vector3(1.9, 6.3, 1.7), CONCRETE * 0.6, 0.03)
			b.box("glass", Vector3(0.24, 0.18, 0.03), Vector3(1.9, 6.3, 1.44), GLASS)
			b.cyl_ab("metal", Vector3(-1.9, 2.5, 1.8), Vector3(-1.9, 5.6, 1.8), 0.03, 0.01, 4, DARK)
			b.box("faction", Vector3(0.03, 0.8, 1.2), Vector3(-1.9, 5.1, 2.45), b.fac)
		)))
	root.add_child(_mk("Muzzle", Vector3(0, 1.5, -2.6)))
	_meta(root, 9.0, 2.6)

## FO: casamatta bassa in cemento con una torretta di carro interrata sopra (ruota con Turret/Barrel).
static func _bunker_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("fo_bunker_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var ring: Array = []
		var hexp: Array = []
		for i in 14:
			var a := TAU * float(i) / 14.0
			ring.append(Vector2(cos(a) * 5.0, sin(a) * 5.0))
		for i in 6:
			var a := TAU * (float(i) + 0.5) / 6.0
			hexp.append(Vector2(cos(a) * 3.5, sin(a) * 3.5))
		b.prism_y("matte", ring, -0.05, 0.9, EARTH, 0.7)
		b.prism_y("stained", hexp, 0.0, 1.7, CONCRETE * 0.9, 0.8)
		UnitModels._band(b, hexp, 1.7, 0.8, Vector2.ZERO, 1.55, 1.68, b.fac)
		b.box("rubber", Vector3(2.0, 0.28, 0.3), Vector3(0, 1.15, -2.95), Color(0.03, 0.03, 0.03))
		b.box("rubber", Vector3(1.0, 1.4, 0.4), Vector3(0, 0.7, 3.0), Color(0.04, 0.04, 0.04))
		if lod < 2:
			for i in 10:
				var a := lerpf(-1.0, 1.0, float(i) / 9.0) - PI * 0.5
				var p := Vector3(cos(a) * 4.2, 1.0, sin(a) * 4.2)
				b.box("matte", Vector3(0.6, 0.24, 0.36), p, SANDBAG * (0.9 + 0.08 * float(i % 2)), 0.08, Basis(Vector3.UP, -a + PI * 0.5))
			# reticolato anticarro
			for s: float in [-1.0, 1.0]:
				var p := Vector3(s * 4.4, 0.0, -4.0)
				for k in 3:
					var r := Basis(Vector3.UP, k * PI / 3.0) * Basis(Vector3.BACK, 0.9)
					b.box("metal", Vector3(0.12, 1.7, 0.12), p + Vector3(0, 0.45, 0), GUNMETAL, 0.0, r)
		)))
	var tur := _mi("Turret", _m("fo_bunker_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-1.2, 0.15, 0.45, 0.12, 2.2], [-0.95, 0.25, 0.95, 0.32, 2.2], [-0.3, 0.3, 1.15, 0.42, 2.2], [0.6, 0.3, 1.1, 0.4, 2.2], [1.1, 0.24, 0.7, 0.22, 2.2]], 14, pc)
		b.cyl("paint", 0.3, 0.28, 0.12, 10, Transform3D(Basis.IDENTITY, Vector3(0.35, 0.72, 0.2)), pc * 0.9)
		b.box("faction", Vector3(0.6, 0.02, 0.5), Vector3(-0.3, 0.71, 0.3), b.fac)
		), Vector3(0, 1.68, 0.2))
	root.add_child(tur)
	var bar := _mi("Barrel", _m("fo_bunker_gun", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("paint", Vector3(0, 0, 0), Vector3(0, 0, -3.6), 0.1, 0.085, 10, pc * 0.9)
		b.cyl_ab("paint", Vector3(0, 0, -2.6), Vector3(0, 0, -3.0), 0.13, 0.13, 10, pc * 0.8)
		), Vector3(0, 0.32, -1.1))
	tur.add_child(bar)
	bar.add_child(_mk("Muzzle", Vector3(0, 0, -3.7)))
	_meta(root, 10.0, 2.7)

## CP: bunker angolare moderno grigio con radome, albero di antenne EW e feritoia orizzontale.
static func _bunker_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _pc(c, tint)
	root.add_child(_mi("Body", _m("cp_bunker_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var ring: Array = []
		for i in 12:
			var a := TAU * float(i) / 12.0
			ring.append(Vector2(cos(a) * 4.8, sin(a) * 4.8))
		b.prism_y("matte", ring, -0.05, 0.45, EARTH * 1.1, 0.82)
		var oct := [Vector2(-1.8, -3.0), Vector2(1.8, -3.0), Vector2(3.2, -1.6), Vector2(3.2, 2.4), Vector2(-3.2, 2.4), Vector2(-3.2, -1.6)]
		b.prism_y("stained", oct, 0.0, 2.3, CONCRETE * Color(0.92, 0.97, 1.04), 0.84, Vector2(0, 0.15))
		UnitModels._band(b, oct, 2.3, 0.84, Vector2(0, 0.15), 2.05, 2.25, b.fac)
		b.box("rubber", Vector3(3.0, 0.24, 0.4), Vector3(0, 1.5, -2.85), Color(0.03, 0.03, 0.03), 0.0, Basis(Vector3.RIGHT, -0.1))
		b.box("matte", Vector3(3.4, 0.1, 0.6), Vector3(0, 1.7, -3.0), CONCRETE * 0.8)
		# radome e albero EW
		b.cyl("paint", 0.7, 0.7, 0.4, 14, Transform3D(Basis.IDENTITY, Vector3(-1.2, 2.5, 0.8)), pc)
		b.sphere("paint", Vector3(-1.2, 2.7, 0.8), Vector3(0.95, 0.95, 0.95), 16, 6, Color(0.82, 0.84, 0.84), true)
		if lod < 2:
			b.cyl_ab("metal", Vector3(1.4, 2.3, 1.2), Vector3(1.4, 7.0, 1.2), 0.08, 0.05, 6, GUNMETAL)
			for i in 3:
				var r := Basis(Vector3.UP, TAU * float(i) / 3.0)
				b.box("paint", Vector3(0.5, 0.9, 0.06), Vector3(1.4, 5.8, 1.2) + r * Vector3(0, 0, -0.18), pc * 0.9, 0.0, r)
				b.cyl_ab("metal", Vector3(1.4, 7.0, 1.2), Vector3(1.4, 7.0, 1.2) + r * Vector3(0.7, 0.5, 0), 0.015, 0.015, 4, DARK)
			b.box("faction", Vector3(0.03, 0.7, 1.1), Vector3(1.4, 6.6, 1.8), b.fac)
		)))
	root.add_child(_mk("Muzzle", Vector3(0, 1.5, -3.2)))
	_meta(root, 9.6, 3.0)

## UL: postazione improvvisata: muri di sacchetti, pneumatici impilati, tettoia di lamiera su pali di legno, fusti, telone.
static func _bunker_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	root.add_child(_mi("Body", _m("ul_bunker_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.prism_y("matte", [Vector2(-4.5, -3.5), Vector2(4.5, -3.5), Vector2(4.8, 3.5), Vector2(-4.8, 3.5)], -0.05, 0.25, EARTH, 0.9)
		# muro di sacchetti a ferro di cavallo
		var rows := 4 if lod < 2 else 2
		_bags(b, Vector3(-3.2, 0.36, -3.0), Vector3(3.2, 0.36, -3.0), 11, rows, 0.0)
		for s: float in [-1.0, 1.0]:
			_bags(b, Vector3(s * 3.4, 0.36, -2.6), Vector3(s * 3.4, 0.36, 1.8), 8, rows - 1, PI * 0.5)
		# pneumatici impilati agli angoli
		for p: Vector3 in [Vector3(-3.9, 0, -3.6), Vector3(3.9, 0, -3.6)]:
			for k in 3:
				b.cyl("rubber", 0.45, 0.45, 0.24, 12, Transform3D(Basis.IDENTITY, p + Vector3(0.05 * k, 0.37 + k * 0.25, 0)), DARK * 1.2)
		# tettoia di lamiera ondulata su pali
		for p: Vector3 in [Vector3(-2.6, 0, -2.4), Vector3(2.6, 0, -2.4), Vector3(-2.6, 0, 1.6), Vector3(2.6, 0, 1.6)]:
			b.cyl_ab("matte", p, p + Vector3(0, 2.25, 0), 0.09, 0.08, 6, WOOD)
		for i in 6:
			b.box("paint", Vector3(1.05, 0.04, 4.8), Vector3(-2.6 + i * 1.04, 2.32 + 0.03 * float(i % 2), -0.4), (RUST if i % 3 == 1 else Color(0.5, 0.5, 0.47)) * (0.9 + 0.08 * float(i % 2)), 0.0, Basis(Vector3.RIGHT, 0.05))
		_bags(b, Vector3(-2.4, 2.48, -2.4), Vector3(2.4, 2.48, -2.4), 7, 1, 0.0)
		b.box("faction", Vector3(1.4, 0.9, 0.03), Vector3(1.2, 1.8, 1.65), b.fac, 0.0, Basis(Vector3.BACK, 0.05))
		if lod < 2:
			b.box("matte", Vector3(3.0, 1.6, 0.04), Vector3(-1.0, 1.4, 1.75), CLOTH, 0.0, Basis(Vector3.RIGHT, 0.08))
			for p: Vector3 in [Vector3(-4.3, 0, 0.5), Vector3(-4.2, 0, 1.4), Vector3(4.3, 0, 1.0)]:
				b.cyl("paint", 0.3, 0.3, 0.9, 10, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.45, 0)), RUST if p.x < 0.0 else Color(0.22, 0.32, 0.38))
			# mitragliatrice su treppiede dietro la feritoia
			b.cyl_ab("metal", Vector3(0.0, 0.3, -2.3), Vector3(0.0, 1.15, -2.3), 0.03, 0.03, 4, DARK)
			b.cyl_ab("metal", Vector3(0.0, 1.2, -2.0), Vector3(0.0, 1.2, -3.4), 0.035, 0.035, 6, DARK)
			b.box("metal", Vector3(0.15, 0.18, 0.6), Vector3(0, 1.22, -1.9), DARK)
		)))
	root.add_child(_mk("Muzzle", Vector3(0, 1.2, -3.5)))
	_meta(root, 9.5, 2.6)

# ============================================================== FANTERIA
## Squadre per fazione (UnitModels.soldier_kit): AAN multicam, portapiastre coyote, elmetti FAST con visori; FO digitale verde,
## elmetti 6B47 con occhiali, passamontagna, AK e RPG; CP tropicale a strisce, tasche pettorali, elmetti e cappelli a tesa larga;
## UL miliziani con abiti misti civili/militari (jeans, felpe, kefiah, berretti, bandane), AK col legno.
static func _inf(root: Node3D, c: Color, lod: int, burnt: bool, tint: float, fac: int) -> void:
	root.add_child(_mi("Body", _m("inf_body_f", c, lod, burnt, tint, func(b: ModelKit) -> void:
		UnitModels.squad_into(b, fac, lod, burnt)
		)))
	root.add_child(_mk("Muzzle", Vector3(0.05, 1.45, -2.4)))
	root.set_meta("length", 4.5)
	root.set_meta("height", 1.8)
	root.set_meta("air", false)
