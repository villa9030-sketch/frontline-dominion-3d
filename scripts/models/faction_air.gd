class_name FactionAir
extends RefCounted
## Velivoli per fazione (Agente F4): elicotteri, caccia, droni. Vedi FactionModels.
## AAN: elicottero d'attacco generico (tandem con radar in testa d'albero), caccia a bassa osservabilità con derive inclinate,
##      drone MALE con coda a V e antenna satellitare. FO: elicottero d'attacco coassiale con piloni carichi, caccia pesante bimotore
##      con alette canard e gondole separate, drone bitrave. CP: elicottero navale con rotore di coda intubato, caccia leggero a delta
##      con canard, drone ala volante a getto. UL: elicottero da trasporto armato, aereo da attacco a turboelica, munizione circuitante a delta.

const DARK := Color(0.11, 0.11, 0.1)
const GUNMETAL := Color(0.2, 0.2, 0.21)
const GLASS := Color(0.1, 0.16, 0.2)
const RUST := Color(0.4, 0.24, 0.14)
const BLADE := Color(0.14, 0.15, 0.14)

static func build_into(root: Node3D, kind: String, c: Color, lod: int, burnt: bool, tint: float, fac: int) -> bool:
	match kind + "_" + String(FactionModels.ID[fac]):
		"heli_fo": _heli_fo(root, c, lod, burnt, tint)
		"heli_cp": _heli_cp(root, c, lod, burnt, tint)
		"heli_ul": _heli_ul(root, c, lod, burnt, tint)
		"jet_aan": _jet_aan(root, c, lod, burnt, tint)
		"jet_fo": _jet_fo(root, c, lod, burnt, tint)
		"jet_cp": _jet_cp(root, c, lod, burnt, tint)
		"jet_ul": _jet_ul(root, c, lod, burnt, tint)
		"drone_aan": _drone_aan(root, c, lod, burnt, tint)
		"drone_fo": _drone_fo(root, c, lod, burnt, tint)
		"drone_cp": _drone_cp(root, c, lod, burnt, tint)
		"drone_ul": _drone_ul(root, c, lod, burnt, tint)
		_:
			return false
	return true

static func _m(key: String, c: Color, lod: int, burnt: bool, tint: float, fn: Callable) -> ArrayMesh:
	return UnitModels._cached(key, c, lod, burnt, tint, fn)

static func _mi(n: String, mesh: ArrayMesh, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return UnitModels._mi(n, mesh, pos)

static func _mk(n: String, pos: Vector3) -> Marker3D:
	return UnitModels._marker(n, pos)

static func _rx() -> Basis:
	return Basis(Vector3.BACK, PI * 0.5)

static func _meta(root: Node3D, L: float, h: float) -> void:
	root.set_meta("length", L)
	root.set_meta("height", h)
	root.set_meta("air", true)

## Ala/deriva speculare: profilo (x,z) per il lato destro, specchiato a sinistra con scaled_local.
static func _pair(b: ModelKit, k: String, prof: Array, th: float, col: Color, tr: Transform3D) -> void:
	for s: float in [-1.0, 1.0]:
		b.plate(k, prof, th, col, tr.scaled_local(Vector3(s, 1, 1)))

## Deriva verticale (profilo (altezza, z)) alla posizione p, inclinata di `cant` verso l'esterno.
static func _fin(b: ModelKit, k: String, prof: Array, th: float, col: Color, p: Vector3, cant: float) -> void:
	b.plate(k, prof, th, col, Transform3D(Basis(Vector3.BACK, cant) * Basis(Vector3.BACK, PI * 0.5), p))

## Lanciarazzi a cilindro (asse Z).
static func _pod(b: ModelKit, p: Vector3, r: float, l: float, col: Color, sg: int) -> void:
	b.cyl_ab("paint", p + Vector3(0, 0, l * 0.5), p - Vector3(0, 0, l * 0.5), r, r, sg, col)
	b.cyl_ab("paint", p - Vector3(0, 0, l * 0.5), p - Vector3(0, 0, l * 0.5 + 0.15), r, r * 0.7, sg, col * 0.9)
	b.cyl_ab("metal", p - Vector3(0, 0, l * 0.5 + 0.14), p - Vector3(0, 0, l * 0.5 + 0.16), r * 0.6, r * 0.6, sg, DARK)

static func _missile(b: ModelKit, p: Vector3, r: float, l: float, col: Color) -> void:
	b.cyl_ab("paint", p + Vector3(0, 0, l * 0.5), p - Vector3(0, 0, l * 0.4), r, r, 6, col)
	b.cyl_ab("paint", p - Vector3(0, 0, l * 0.4), p - Vector3(0, 0, l * 0.5), r, 0.0, 6, col)

## Rotore: n pale lunghe `len` con punta della fazione. y = quota del disco relativa al mozzo.
static func _blades(b: ModelKit, n: int, len: float, chord: float, y: float, off: float) -> void:
	for i in n:
		var r := Basis(Vector3.UP, TAU * float(i) / float(n) + off)
		b.box("paint", Vector3(chord, 0.05, len), r * Vector3(0, y, -len * 0.5 - 0.2), BLADE, 0.0, r * Basis(Vector3.FORWARD, 0.06))
		b.box("faction", Vector3(chord + 0.01, 0.06, 0.3), r * Vector3(0, y, -len - 0.05), b.fac, 0.0, r)

# ============================================================== ELICOTTERI
## FO: elicottero d'attacco con rotori coassiali (niente rotore di coda), cabina affiancata, ali con tre piloni, derive gemelle.
static func _heli_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.HELI_GREEN, c, tint)
	var sg := 12 if lod == 0 else (8 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("fo_heli_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-6.1, 1.45, 0.06, 0.06], [-5.8, 1.48, 0.45, 0.4, 3.0], [-4.9, 1.62, 0.78, 0.66, 4.0], [-3.2, 1.8, 0.88, 0.86, 5.0],
			[-1.0, 1.92, 0.92, 0.96, 6.0], [1.0, 1.95, 0.82, 0.9, 5.0], [2.5, 2.1, 0.42, 0.5, 4.0], [5.4, 2.22, 0.22, 0.26, 3.0], [6.2, 2.25, 0.16, 0.22, 3.0]], sg, pc)
		# tettuccio affiancato a vetri piani
		b.hexa("glass", [Vector3(-0.7, 1.95, -5.3), Vector3(0.7, 1.95, -5.3), Vector3(0.8, 2.3, -3.0), Vector3(-0.8, 2.3, -3.0),
			Vector3(-0.45, 2.45, -4.4), Vector3(0.45, 2.45, -4.4), Vector3(0.55, 2.82, -3.0), Vector3(-0.55, 2.82, -3.0)], GLASS)
		b.box("paint", Vector3(1.1, 0.08, 0.1), Vector3(0, 2.83, -3.02), pc * 0.75)
		b.cyl_ab("paint", Vector3(0, 2.45, -4.4), Vector3(0, 2.83, -3.02), 0.04, 0.04, 4, pc * 0.7)
		# carenatura motori e trasmissione
		b.hexa("paint", [Vector3(-0.6, 2.7, -2.9), Vector3(0.6, 2.7, -2.9), Vector3(0.6, 2.75, 1.8), Vector3(-0.6, 2.75, 1.8),
			Vector3(-0.35, 3.2, -2.3), Vector3(0.35, 3.2, -2.3), Vector3(0.35, 3.15, 1.3), Vector3(-0.35, 3.15, 1.3)], pc * 0.95)
		for s: float in [-1.0, 1.0]:
			var tr := Transform3D(Basis.IDENTITY, Vector3(s * 1.05, 0, 0))
			b.t = tr
			b.loft("paint", [[-1.4, 2.6, 0.05, 0.05], [-1.2, 2.6, 0.32, 0.32], [0.9, 2.6, 0.36, 0.36], [1.6, 2.6, 0.3, 0.3]], sg, pc * 0.9, true)
			b.cyl_ab("metal", Vector3(0, 2.6, -1.25), Vector3(0, 2.6, -1.27), 0.26, 0.26, sg, DARK)
			b.t = Transform3D.IDENTITY
			# ali corte con tre piloni
			b.plate("paint", [Vector2(0, -0.8), Vector2(2.7, -0.5), Vector2(2.7, 0.3), Vector2(0, 0.5)], 0.14, pc,
				Transform3D(Basis(Vector3.BACK, s * -0.12), Vector3(s * 0.8, 1.75, -0.3)).scaled_local(Vector3(s, 1, 1)))
			for k in 3:
				var px := s * (1.3 + k * 0.7)
				b.box("paint", Vector3(0.1, 0.28, 0.6), Vector3(px, 1.6 - k * 0.08, -0.3), pc * 0.7)
				if k < 2:
					FactionAir._pod(b, Vector3(px, 1.4 - k * 0.08, -0.4), 0.24, 1.6, pc * 0.7, sg)
				elif lod < 2:
					for j in 3:
						FactionAir._missile(b, Vector3(px + (j - 1) * 0.17, 1.38 - k * 0.08, -0.4), 0.075, 1.8, Color(0.32, 0.34, 0.28))
			b.box("faction", Vector3(0.02, 0.5, 1.0), Vector3(s * 0.85, 1.95, 0.9), b.fac)
			# carrello
			b.cyl("rubber", 0.33, 0.33, 0.2, 10, Transform3D(_rx(), Vector3(s * 1.0, 0.33, -3.0)), DARK)
			b.cyl_ab("metal", Vector3(s * 1.0, 0.4, -3.0), Vector3(s * 0.55, 1.3, -2.8), 0.06, 0.06, 6, GUNMETAL)
		# coda: piano orizzontale con derive gemelle alle estremità, ruotino
		b.plate("paint", [Vector2(-1.6, -0.3), Vector2(1.6, -0.3), Vector2(1.6, 0.4), Vector2(-1.6, 0.4)], 0.1, pc, Transform3D(Basis.IDENTITY, Vector3(0, 2.25, 5.6)))
		for s: float in [-1.0, 1.0]:
			_fin(b, "paint", [Vector2(-0.6, -0.4), Vector2(0.9, -0.1), Vector2(0.9, 0.55), Vector2(-0.6, 0.45)], 0.1, pc, Vector3(s * 1.6, 2.4, 5.7), 0.0)
			_fin(b, "faction", [Vector2(0.45, -0.25), Vector2(0.9, -0.1), Vector2(0.9, 0.55), Vector2(0.45, 0.5)], 0.12, b.fac, Vector3(s * 1.6, 2.4, 5.7), 0.0)
		b.cyl_ab("metal", Vector3(0, 1.8, 5.6), Vector3(0, 0.25, 5.6), 0.05, 0.05, 6, GUNMETAL)
		b.cyl("rubber", 0.2, 0.2, 0.12, 8, Transform3D(_rx(), Vector3(0, 0.2, 5.6)), DARK)
		# sensori del muso e albero rotore alto
		b.sphere("paint", Vector3(0, 1.15, -5.3), Vector3(0.36, 0.36, 0.36), 10, 6, pc * 0.8)
		b.box("glass", Vector3(0.3, 0.22, 0.05), Vector3(0, 1.15, -5.66), Color(0.18, 0.12, 0.05))
		b.cyl_ab("metal", Vector3(0, 3.1, -0.3), Vector3(0, 3.5, -0.3), 0.2, 0.15, 10, GUNMETAL)
		)))
	var gun := _mi("Turret", _m("fo_heli_gunmount", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("paint", Vector3(0.36, 0.36, 1.1), Vector3.ZERO, pc * 0.8, 0.05)
		), Vector3(0.95, 1.55, -1.6))
	root.add_child(gun)
	var gb := _mi("Barrel", _m("fo_heli_gun", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("metal", Vector3(0, 0, 0), Vector3(0, 0, -2.1), 0.06, 0.05, 6, DARK)
		b.cyl_ab("metal", Vector3(0, 0, -1.9), Vector3(0, 0, -2.15), 0.085, 0.085, 6, DARK)
		), Vector3(0, -0.05, -0.5))
	gun.add_child(gb)
	gb.add_child(_mk("Muzzle", Vector3(0, 0, -2.2)))
	var rotor := _mi("Rotor", _m("fo_heli_rotor", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.3, 0.26, 0.22, 10, Transform3D(Basis.IDENTITY, Vector3.ZERO), GUNMETAL)
		b.cyl("metal", 0.12, 0.12, 1.05, 8, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), GUNMETAL)
		b.cyl("metal", 0.26, 0.22, 0.2, 10, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), GUNMETAL)
		b.cyl("metal", 0.14, 0.05, 0.25, 8, Transform3D(Basis.IDENTITY, Vector3(0, 1.15, 0)), GUNMETAL)
		FactionAir._blades(b, 3, 6.6, 0.5, 0.02, 0.2)
		FactionAir._blades(b, 3, 6.6, 0.5, 0.97, 0.2 + PI / 3.0)
		), Vector3(0, 3.5, -0.3))
	root.add_child(rotor)
	_meta(root, 13.2, 4.8)

## CP: elicottero navale multiruolo: fusoliera liscia, cabina con portellone, sfera sensori, rotore di coda intubato, pilone con siluro/missile.
static func _heli_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.HELI_GREEN, c, tint)
	var sg := 14 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("cp_heli_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-6.3, 1.35, 0.08, 0.08], [-6.0, 1.42, 0.5, 0.45, 2.4], [-5.0, 1.6, 0.85, 0.78, 2.8], [-3.4, 1.75, 1.0, 1.0, 3.2],
			[0.0, 1.8, 1.02, 1.02, 3.6], [1.8, 1.92, 0.85, 0.86, 3.2], [3.0, 2.2, 0.36, 0.42, 2.5], [6.3, 2.45, 0.2, 0.25, 2.5], [6.9, 2.55, 0.18, 0.3, 2.5]], sg, pc)
		# parabrezza avvolgente e finestrini
		b.hexa("glass", [Vector3(-0.8, 1.8, -5.5), Vector3(0.8, 1.8, -5.5), Vector3(0.95, 2.1, -3.6), Vector3(-0.95, 2.1, -3.6),
			Vector3(-0.55, 2.4, -4.75), Vector3(0.55, 2.4, -4.75), Vector3(0.75, 2.72, -3.6), Vector3(-0.75, 2.72, -3.6)], GLASS)
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.03, 0.5, 0.75), Vector3(s * 1.01, 2.1, -4.0), GLASS)
			b.box("paint", Vector3(0.03, 1.1, 1.5), Vector3(s * 1.03, 1.65, -1.6), pc * 0.88)   # portellone scorrevole
			b.box("glass", Vector3(0.035, 0.4, 0.5), Vector3(s * 1.04, 2.0, -1.6), GLASS)
			b.box("faction", Vector3(0.02, 0.5, 0.7), Vector3(s * 0.98, 1.85, 0.6), b.fac)
			# sponsoni con carrello
			b.box("paint", Vector3(0.6, 0.45, 1.6), Vector3(s * 1.2, 1.05, 0.0), pc * 0.9, 0.18)
			b.cyl("rubber", 0.32, 0.32, 0.22, 10, Transform3D(_rx(), Vector3(s * 1.25, 0.32, 0.2)), DARK)
		# pilone sinistro con siluro leggero
		b.box("paint", Vector3(1.0, 0.1, 0.6), Vector3(-1.4, 1.5, -1.2), pc * 0.8)
		FactionAir._missile(b, Vector3(-1.85, 1.2, -1.2), 0.16, 2.6, Color(0.6, 0.6, 0.52))
		# motori e carenatura
		b.hexa("paint", [Vector3(-0.75, 2.65, -3.4), Vector3(0.75, 2.65, -3.4), Vector3(0.7, 2.75, 1.9), Vector3(-0.7, 2.75, 1.9),
			Vector3(-0.5, 3.15, -2.8), Vector3(0.5, 3.15, -2.8), Vector3(0.45, 3.1, 1.4), Vector3(-0.45, 3.1, 1.4)], pc * 0.95)
		for s: float in [-1.0, 1.0]:
			b.box("rubber", Vector3(0.35, 0.3, 0.05), Vector3(s * 0.45, 2.88, -3.12), DARK)
			b.box("rubber", Vector3(0.05, 0.25, 0.4), Vector3(s * 0.72, 2.85, 1.4), DARK)
		# sfera sensori sotto il muso
		b.sphere("paint", Vector3(0, 1.0, -5.2), Vector3(0.32, 0.32, 0.32), 10, 6, Color(0.6, 0.62, 0.62))
		b.box("glass", Vector3(0.26, 0.2, 0.04), Vector3(0, 1.0, -5.52), Color(0.18, 0.12, 0.05))
		# antenne EW
		if lod < 2:
			for z: float in [-1.5, 0.3]:
				b.cyl_ab("metal", Vector3(0, 2.75, z), Vector3(0, 3.0, z + 0.25), 0.02, 0.01, 4, DARK)
			b.box("paint", Vector3(0.3, 0.12, 0.6), Vector3(0, 0.82, -2.2), pc * 0.7, 0.03)
		# coda: deriva con condotto del rotore intubato e piano orizzontale
		var ring := 14 if lod < 2 else 8
		for i in ring:
			var a := TAU * float(i) / float(ring)
			var p := Vector3(0, 2.75 + sin(a) * 0.62, 6.6 + cos(a) * 0.62)
			b.box("paint", Vector3(0.36, 0.3, 0.12), p, pc * 0.95, 0.0, Basis(Vector3.RIGHT, -a))
		_fin(b, "paint", [Vector2(0.3, -0.5), Vector2(2.1, 0.2), Vector2(2.1, 0.75), Vector2(0.3, 0.55)], 0.14, pc, Vector3(0, 2.75, 6.6), 0.0)
		_fin(b, "faction", [Vector2(1.6, 0.0), Vector2(2.1, 0.2), Vector2(2.1, 0.75), Vector2(1.6, 0.6)], 0.16, b.fac, Vector3(0, 2.75, 6.6), 0.0)
		b.plate("paint", [Vector2(-1.1, -0.25), Vector2(1.1, -0.25), Vector2(1.0, 0.3), Vector2(-1.0, 0.3)], 0.08, pc, Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 5.4)))
		b.cyl_ab("metal", Vector3(0, 3.05, -0.4), Vector3(0, 3.45, -0.4), 0.18, 0.14, 10, GUNMETAL)
		)))
	var gun := _mi("Turret", _m("cp_heli_mg", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.2, 0.2, 0.3), Vector3.ZERO, GUNMETAL, 0.03)
		), Vector3(1.05, 1.8, -1.6))
	root.add_child(gun)
	var gb := _mi("Barrel", _m("cp_heli_mgb", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.12, 0.15, 0.6), Vector3(0, 0, -0.1), DARK)
		b.cyl_ab("metal", Vector3(0, 0, -0.4), Vector3(0, 0, -1.2), 0.03, 0.03, 6, DARK)
		), Vector3(0.15, 0.05, 0))
	gun.add_child(gb)
	gb.add_child(_mk("Muzzle", Vector3(0, 0, -1.25)))
	var rotor := _mi("Rotor", _m("cp_heli_rotor", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.36, 0.3, 0.26, 10, Transform3D(Basis.IDENTITY, Vector3.ZERO), GUNMETAL)
		FactionAir._blades(b, 4, 6.8, 0.48, 0.04, 0.4)
		), Vector3(0, 3.5, -0.4))
	root.add_child(rotor)
	var tr := _mi("TailRotor", _m("cp_heli_fan", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.12, 0.12, 0.16, 8, Transform3D(_rx(), Vector3.ZERO), GUNMETAL)
		for i in 8:
			var r := Basis(Vector3.RIGHT, TAU * float(i) / 8.0)
			b.box("paint", Vector3(0.03, 0.5, 0.12), r * Vector3(0, 0.27, 0), BLADE, 0.0, r * Basis(Vector3.UP, 0.4))
		), Vector3(0, 2.75, 6.6))
	root.add_child(tr)
	_meta(root, 14.6, 4.3)

## UL: elicottero da trasporto armato: grande cabina, muso vetrato, piloni laterali con lanciarazzi, mitragliatrice al portellone, colori misti.
static func _heli_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.HELI_GREEN, c, tint)
	var sand := UnitModels._paint(Color(0.55, 0.48, 0.35), c, tint * 0.6)
	var sg := 14 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("ul_heli_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-7.4, 1.55, 0.1, 0.1], [-7.1, 1.6, 0.62, 0.6, 2.5], [-6.2, 1.82, 1.02, 1.05, 3.0], [-4.8, 2.0, 1.18, 1.25, 4.0],
			[0.0, 2.1, 1.22, 1.32, 5.0], [1.4, 2.2, 1.1, 1.15, 4.0], [2.8, 2.6, 0.42, 0.52, 3.0]], sg, sand)
		b.loft("paint", [[2.6, 2.62, 0.45, 0.55, 3.0], [8.0, 2.85, 0.22, 0.3, 3.0], [8.6, 2.92, 0.2, 0.34, 3.0]], sg, pc)   # trave di coda verde di recupero
		# muso vetrato a pannelli e finestrini tondi della cabina
		b.sphere("glass", Vector3(0, 1.75, -6.75), Vector3(0.8, 0.72, 0.62), 10, 5, GLASS)
		b.hexa("glass", [Vector3(-0.95, 2.1, -6.4), Vector3(0.95, 2.1, -6.4), Vector3(1.05, 2.4, -5.1), Vector3(-1.05, 2.4, -5.1),
			Vector3(-0.7, 2.75, -6.0), Vector3(0.7, 2.75, -6.0), Vector3(0.8, 3.05, -5.1), Vector3(-0.8, 3.05, -5.1)], GLASS)
		for s: float in [-1.0, 1.0]:
			for i in 4:
				b.cyl("glass", 0.24, 0.24, 0.04, 10, Transform3D(_rx(), Vector3(s * 1.22, 2.35, -3.4 + i * 1.05)), GLASS, true, false)
			b.box("faction", Vector3(0.02, 0.55, 0.8), Vector3(s * 0.55, 2.7, 4.2), b.fac)
			# chiazze di vernice diversa e ruggine
			b.box("paint", Vector3(0.03, 0.8, 1.3), Vector3(s * 1.22, 1.6, 0.4), RUST * 1.2, 0.0)
		# portellone aperto (buio) con mitragliatrice
		b.box("rubber", Vector3(0.03, 1.4, 1.3), Vector3(-1.23, 1.85, -1.5), Color(0.03, 0.03, 0.03))
		# piloni laterali con due lanciarazzi per lato
		for s: float in [-1.0, 1.0]:
			b.box("paint", Vector3(2.4, 0.12, 0.7), Vector3(s * 2.1, 1.35, 0.6), sand * 0.85)
			b.cyl_ab("metal", Vector3(s * 1.1, 1.0, 0.6), Vector3(s * 2.6, 1.32, 0.6), 0.04, 0.04, 4, GUNMETAL)
			for k in 2:
				FactionAir._pod(b, Vector3(s * (2.0 + k * 0.9), 1.05, 0.5), 0.26, 1.7, Color(0.3, 0.32, 0.26), sg)
		# carrello triciclo fisso
		b.cyl("rubber", 0.3, 0.3, 0.2, 10, Transform3D(_rx(), Vector3(0, 0.3, -5.6)), DARK)
		b.cyl_ab("metal", Vector3(0, 0.35, -5.6), Vector3(0, 1.0, -5.4), 0.06, 0.06, 6, GUNMETAL)
		for s: float in [-1.0, 1.0]:
			b.cyl("rubber", 0.4, 0.4, 0.26, 10, Transform3D(_rx(), Vector3(s * 1.55, 0.4, 0.9)), DARK)
			b.cyl_ab("metal", Vector3(s * 1.55, 0.45, 0.9), Vector3(s * 1.0, 1.1, 0.9), 0.07, 0.07, 6, GUNMETAL)
		# motori sopra la cabina con prese d'aria e scarichi
		b.loft("paint", [[-4.8, 3.3, 0.05, 0.05], [-4.6, 3.3, 0.85, 0.36, 3.0], [-1.0, 3.42, 0.95, 0.48, 3.0], [1.2, 3.3, 0.7, 0.36, 3.0], [1.8, 3.2, 0.3, 0.2]], sg, pc * 0.95)
		for s: float in [-1.0, 1.0]:
			b.cyl_ab("rubber", Vector3(s * 0.45, 3.35, -4.66), Vector3(s * 0.45, 3.35, -4.7), 0.22, 0.22, 8, DARK)
			b.cyl_ab("metal", Vector3(s * 0.9, 3.25, -0.5), Vector3(s * 1.25, 3.2, 0.3), 0.18, 0.2, 8, Color(0.16, 0.14, 0.12))
		# deriva, piano orizzontale
		_fin(b, "paint", [Vector2(0.0, -0.6), Vector2(1.9, 0.0), Vector2(1.9, 0.6), Vector2(0.0, 0.5)], 0.14, pc, Vector3(0, 3.0, 8.1), 0.0)
		b.plate("paint", [Vector2(-1.3, -0.3), Vector2(1.3, -0.3), Vector2(1.2, 0.3), Vector2(-1.2, 0.3)], 0.08, pc, Transform3D(Basis.IDENTITY, Vector3(0, 2.75, 7.2)))
		b.cyl_ab("metal", Vector3(0, 3.55, -1.2), Vector3(0, 4.0, -1.2), 0.2, 0.15, 10, GUNMETAL)
		)))
	var gun := _mi("Turret", _m("ul_heli_door", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("metal", Vector3(0, -0.3, 0), Vector3(0, 0.05, 0), 0.04, 0.04, 6, GUNMETAL)
		), Vector3(-1.35, 1.9, -1.5))
	root.add_child(gun)
	var gb := _mi("Barrel", _m("ul_heli_mg", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.14, 0.16, 0.7), Vector3(0, 0, 0.0), DARK)
		b.cyl_ab("metal", Vector3(0, 0.02, -0.35), Vector3(0, 0.02, -1.4), 0.035, 0.03, 6, DARK)
		), Vector3(0, 0.1, 0))
	gun.add_child(gb)
	gb.add_child(_mk("Muzzle", Vector3(0, 0.02, -1.45)))
	var rotor := _mi("Rotor", _m("ul_heli_rotor", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.42, 0.36, 0.3, 10, Transform3D(Basis.IDENTITY, Vector3.ZERO), GUNMETAL)
		FactionAir._blades(b, 5, 8.2, 0.52, 0.05, 0.0)
		), Vector3(0, 4.05, -1.2))
	root.add_child(rotor)
	var tr := _mi("TailRotor", _m("ul_heli_tail", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.12, 0.12, 0.2, 8, Transform3D(_rx(), Vector3.ZERO), GUNMETAL)
		for i in 3:
			var r := Basis(Vector3.RIGHT, TAU * float(i) / 3.0)
			b.box("paint", Vector3(0.04, 1.6, 0.22), r * Vector3(-0.06, 0.8, 0), BLADE, 0.0, r)
		), Vector3(-0.25, 3.95, 8.55))
	root.add_child(tr)
	_meta(root, 16.5, 5.0)

# ============================================================== CACCIA
## AAN: caccia a bassa osservabilità: fusoliera a spigoli (chine), ali trapezoidali, derive inclinate, ugelli rettangolari.
static func _jet_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.AIR_GRAY, c, tint * 0.9)
	var sg := 16 if lod == 0 else (12 if lod == 1 else 8)
	root.add_child(_mi("Body", _m("aan_jet_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-8.6, 1.1, 0.03, 0.02], [-7.6, 1.12, 0.48, 0.24, 1.5], [-5.0, 1.2, 1.05, 0.5, 1.5], [-2.0, 1.2, 2.0, 0.58, 1.7],
			[2.5, 1.15, 2.1, 0.55, 1.8], [6.4, 1.15, 1.7, 0.45, 1.8], [8.2, 1.15, 1.25, 0.32, 1.6]], sg, pc)
		b.sphere("glass", Vector3(0, 1.55, -4.6), Vector3(0.5, 0.48, 1.7), sg, 6, Color(0.2, 0.17, 0.08), true)
		for s: float in [-1.0, 1.0]:
			# prese d'aria oblique
			b.hexa("paint", [Vector3(s * 0.9, 0.75, -3.4), Vector3(s * 1.75, 0.75, -3.0), Vector3(s * 1.75, 0.75, 0.0), Vector3(s * 0.9, 0.75, 0.0),
				Vector3(s * 0.9, 1.45, -3.0), Vector3(s * 1.6, 1.4, -2.7), Vector3(s * 1.6, 1.4, 0.0), Vector3(s * 0.9, 1.45, 0.0)], pc * 0.95)
			b.face("rubber", [Vector3(s * 0.95, 0.8, -3.36), Vector3(s * 1.7, 0.8, -2.98), Vector3(s * 1.56, 1.36, -2.7), Vector3(s * 0.95, 1.4, -2.98)], Color(0.02, 0.02, 0.02), Vector3(s * 1.3, 1.1, -2.0))
			# ugelli rettangolari
			b.box("metal", Vector3(0.9, 0.42, 0.8), Vector3(s * 0.6, 1.12, 8.4), Color(0.22, 0.21, 0.2))
			b.box("rubber", Vector3(0.75, 0.3, 0.04), Vector3(s * 0.6, 1.12, 8.81), Color(0.04, 0.03, 0.03))
		# ali trapezoidali (bordi paralleli alle derive) e piani di coda
		var wing := [Vector2(1.6, -2.4), Vector2(6.0, 2.6), Vector2(6.0, 3.6), Vector2(1.6, 4.6)]
		_pair(b, "paint", wing, 0.16, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
		_pair(b, "paint", [Vector2(1.2, 6.1), Vector2(3.6, 8.1), Vector2(3.6, 8.8), Vector2(1.2, 8.9)], 0.1, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
		for s: float in [-1.0, 1.0]:
			# fascia della fazione a bassa visibilità sulle ali e derive inclinate di 27°
			b.plate("faction", [Vector2(4.4, 1.0), Vector2(6.02, 2.65), Vector2(6.02, 3.4), Vector2(4.4, 3.4)], 0.18, b.fac, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)).scaled_local(Vector3(s, 1, 1)))
			var fin := Transform3D(Basis(Vector3.BACK, s * -0.47) * Basis(Vector3.BACK, PI * 0.5), Vector3(s * 1.45, 1.45, 0))
			b.plate("paint", [Vector2(0, 4.4), Vector2(2.6, 6.3), Vector2(2.6, 7.4), Vector2(0, 7.8)], 0.1, pc, fin)
			b.plate("faction", [Vector2(1.7, 5.65), Vector2(2.6, 6.3), Vector2(2.6, 7.4), Vector2(1.7, 7.53)], 0.12, b.fac, fin)
		# pannelli dei vani armi interni
		if lod < 2:
			b.box("rubber", Vector3(1.2, 0.02, 3.0), Vector3(0, 0.63, 0.5), pc * 0.6)
		)))
	root.add_child(_mk("Muzzle", Vector3(-1.0, 1.5, -5.0)))
	_meta(root, 17.4, 4.3)

## FO: caccia pesante bimotore: muso lungo, gondole motori separate, canard, alte derive verticali, molti missili.
static func _jet_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.AIR_GRAY, c, tint * 0.9)
	var sg := 16 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("fo_jet_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-10.8, 1.55, 0.03, 0.03], [-10.0, 1.56, 0.36, 0.36], [-7.6, 1.62, 0.72, 0.7], [-5.0, 1.72, 0.92, 0.8, 2.4],
			[-2.4, 1.55, 1.25, 0.55, 3.0], [3.0, 1.45, 1.15, 0.45, 3.0], [7.0, 1.45, 0.55, 0.35], [9.8, 1.45, 0.22, 0.22]], sg, pc)
		b.sphere("glass", Vector3(0, 2.15, -6.3), Vector3(0.5, 0.58, 1.5), sg, 6, GLASS, true)
		for s: float in [-1.0, 1.0]:
			# gondole motori separate con prese squadrate sotto l'ala
			b.box("paint", Vector3(1.0, 0.95, 1.6), Vector3(s * 1.45, 0.95, -3.6), pc * 0.92, 0.06)
			b.box("rubber", Vector3(0.85, 0.8, 0.04), Vector3(s * 1.45, 0.95, -4.41), Color(0.02, 0.02, 0.02))
			var tn := Transform3D(Basis.IDENTITY, Vector3(s * 1.45, 0, 0))
			b.t = tn
			b.loft("paint", [[-2.8, 1.0, 0.52, 0.5, 2.6], [5.0, 1.02, 0.6, 0.58, 2.2], [8.0, 1.05, 0.55, 0.55], [8.6, 1.05, 0.5, 0.5]], sg, pc * 0.94, false)
			b.cyl_ab("metal", Vector3(0, 1.05, 8.5), Vector3(0, 1.05, 9.5), 0.55, 0.48, sg, Color(0.24, 0.23, 0.22))
			b.cyl_ab("rubber", Vector3(0, 1.05, 9.48), Vector3(0, 1.05, 9.51), 0.42, 0.42, sg, Color(0.05, 0.04, 0.04))
			b.t = Transform3D.IDENTITY
		# grande ala con estensioni alla radice, canard, piani di coda
		_pair(b, "paint", [Vector2(1.6, -1.6), Vector2(7.6, 3.4), Vector2(7.6, 4.3), Vector2(1.6, 5.2)], 0.18, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)))
		_pair(b, "paint", [Vector2(1.0, -5.6), Vector2(1.9, -1.4), Vector2(1.9, 0.0), Vector2(1.0, 0.0)], 0.14, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.48, 0)))
		_pair(b, "paint", [Vector2(1.0, -5.0), Vector2(2.6, -4.2), Vector2(2.6, -3.8), Vector2(1.0, -3.6)], 0.08, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)))
		_pair(b, "paint", [Vector2(1.8, 6.6), Vector2(4.8, 8.6), Vector2(4.8, 9.4), Vector2(1.8, 9.6)], 0.12, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
		for s: float in [-1.0, 1.0]:
			b.cyl("faction", 0.75, 0.75, 0.02, 20, Transform3D(Basis.IDENTITY, Vector3(s * 5.4, 1.5, 3.0)), b.fac, true, false)
			# derive verticali alte (dritte) sopra le gondole
			var fin := Transform3D(Basis(Vector3.BACK, s * -0.05) * Basis(Vector3.BACK, PI * 0.5), Vector3(s * 1.55, 1.55, 0))
			b.plate("paint", [Vector2(0, 4.6), Vector2(3.6, 7.2), Vector2(3.6, 8.2), Vector2(0, 8.6)], 0.12, pc, fin)
			b.plate("faction", [Vector2(2.3, 6.26), Vector2(3.6, 7.2), Vector2(3.6, 8.2), Vector2(2.3, 8.46)], 0.14, b.fac, fin)
			# armamento: tre missili per ala e due fra le gondole
			if lod < 2:
				for k in 3:
					var x := s * (3.2 + k * 1.5)
					b.box("paint", Vector3(0.1, 0.22, 0.9), Vector3(x, 1.22, 1.8 + k * 0.6), pc * 0.8)
					FactionAir._missile(b, Vector3(x, 1.02, 1.6 + k * 0.6), 0.1 if k < 2 else 0.07, 3.6 if k < 2 else 2.8, Color(0.82, 0.82, 0.78))
				FactionAir._missile(b, Vector3(s * 0.55, 0.85, 1.0), 0.12, 4.0, Color(0.82, 0.82, 0.78))
		b.cyl_ab("paint", Vector3(0, 1.45, 9.5), Vector3(0, 1.45, 10.8), 0.22, 0.12, 8, pc * 0.9)   # pungiglione di coda
		)))
	root.add_child(_mk("Muzzle", Vector3(-1.0, 1.75, -6.5)))
	_meta(root, 21.5, 5.4)

## CP: caccia leggero monomotore a delta con canard, presa d'aria ventrale, deriva singola, grigio navale.
static func _jet_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.AIR_GRAY, c, tint * 0.9)
	var sg := 16 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("cp_jet_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-7.8, 1.3, 0.03, 0.03], [-7.0, 1.31, 0.3, 0.3], [-4.6, 1.38, 0.56, 0.6], [-2.0, 1.35, 0.72, 0.66, 2.4],
			[3.0, 1.3, 0.7, 0.62, 2.4], [6.0, 1.3, 0.52, 0.52], [6.6, 1.3, 0.47, 0.47]], sg, pc)
		b.sphere("glass", Vector3(0, 1.85, -4.5), Vector3(0.44, 0.5, 1.5), sg, 6, GLASS, true)
		b.loft("paint", [[-3.1, 1.75, 0.38, 0.32], [0.0, 1.75, 0.4, 0.3], [3.0, 1.6, 0.22, 0.15]], sg, pc * 0.97, false)
		# presa d'aria ventrale
		b.box("paint", Vector3(1.1, 0.65, 3.2), Vector3(0, 0.75, -1.2), pc * 0.92, 0.12)
		b.box("rubber", Vector3(0.9, 0.5, 0.04), Vector3(0, 0.75, -2.81), Color(0.02, 0.02, 0.02))
		b.cyl_ab("metal", Vector3(0, 1.3, 6.5), Vector3(0, 1.3, 7.3), 0.5, 0.42, sg, Color(0.24, 0.23, 0.22))
		b.cyl_ab("rubber", Vector3(0, 1.3, 7.28), Vector3(0, 1.3, 7.31), 0.36, 0.36, sg, Color(0.05, 0.04, 0.04))
		# ala a delta, canard
		_pair(b, "paint", [Vector2(0.6, -1.6), Vector2(4.7, 4.5), Vector2(4.7, 5.3), Vector2(0.6, 5.6)], 0.16, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
		_pair(b, "paint", [Vector2(0.6, -4.2), Vector2(2.2, -3.0), Vector2(2.2, -2.7), Vector2(0.6, -2.6)], 0.08, pc, Transform3D(Basis(Vector3.BACK, 0.08), Vector3(0, 1.55, 0)))
		for s: float in [-1.0, 1.0]:
			b.cyl("faction", 0.6, 0.6, 0.02, 18, Transform3D(Basis.IDENTITY, Vector3(s * 2.9, 1.2, 3.8)), b.fac, true, false)
			if lod < 2:
				b.cyl_ab("paint", Vector3(s * 4.75, 1.1, 3.0), Vector3(s * 4.75, 1.1, 5.4), 0.08, 0.08, 6, Color(0.85, 0.85, 0.82))
				b.box("paint", Vector3(0.1, 0.25, 0.9), Vector3(s * 2.5, 0.9, 2.5), pc * 0.8)
				FactionAir._missile(b, Vector3(s * 2.5, 0.65, 2.3), 0.12, 3.4, Color(0.6, 0.62, 0.58))
		# deriva singola alta a freccia
		var fin := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 1.85, 0))
		b.plate("paint", [Vector2(0, 2.4), Vector2(3.4, 5.4), Vector2(3.4, 6.4), Vector2(0, 6.8)], 0.14, pc, fin)
		b.plate("faction", [Vector2(2.2, 4.34), Vector2(3.4, 5.4), Vector2(3.4, 6.4), Vector2(2.2, 6.56)], 0.16, b.fac, fin)
		)))
	root.add_child(_mk("Muzzle", Vector3(-0.6, 1.55, -4.8)))
	_meta(root, 15.5, 5.2)

## UL: aereo da attacco leggero a turboelica: elica anteriore (Prop), ali dritte basse, razzi e gondole cannone, colori misti.
static func _jet_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.AIR_GRAY, c, tint * 0.9)
	var sand := UnitModels._paint(Color(0.55, 0.49, 0.37), c, tint * 0.6)
	var sg := 14 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _m("ul_jet_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-5.5, 1.55, 0.28, 0.32], [-4.6, 1.55, 0.48, 0.55, 2.4], [-2.6, 1.62, 0.55, 0.72, 2.6], [0.5, 1.62, 0.48, 0.7, 2.6],
			[3.2, 1.75, 0.25, 0.35], [5.4, 1.85, 0.12, 0.18]], sg, sand)
		b.cyl_ab("rubber", Vector3(-0.5, 1.2, -4.6), Vector3(-0.2, 1.2, -4.0), 0.12, 0.12, 6, DARK)   # scarico
		# tettuccio biposto in tandem
		b.loft("glass", [[-3.2, 2.05, 0.05, 0.05], [-2.6, 2.1, 0.42, 0.4], [0.2, 2.15, 0.4, 0.42], [0.8, 2.12, 0.1, 0.1]], sg, GLASS)
		# ali dritte basse con piccolo diedro, piani di coda
		_pair(b, "paint", [Vector2(0.4, -1.4), Vector2(5.4, -0.9), Vector2(5.4, -0.1), Vector2(0.4, 0.5)], 0.18, pc, Transform3D(Basis(Vector3.BACK, 0.06), Vector3(0, 1.15, 0)))
		_pair(b, "paint", [Vector2(0.2, 3.9), Vector2(2.1, 4.4), Vector2(2.1, 4.9), Vector2(0.2, 5.3)], 0.1, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.85, 0)))
		_fin(b, "paint", [Vector2(0, 3.4), Vector2(1.9, 4.6), Vector2(1.9, 5.3), Vector2(0, 5.4)], 0.12, sand, Vector3(0, 2.0, 0), 0.0)
		_fin(b, "faction", [Vector2(1.0, 4.03), Vector2(1.9, 4.6), Vector2(1.9, 5.3), Vector2(1.0, 5.35)], 0.14, b.fac, Vector3(0, 2.0, 0), 0.0)
		for s: float in [-1.0, 1.0]:
			b.box("faction", Vector3(1.1, 0.2, 1.0), Vector3(s * 3.8, 1.37, -0.5), b.fac)
			b.box("paint", Vector3(1.2, 0.2, 0.9), Vector3(s * 2.0, 1.22, -0.4), RUST * 1.2)   # pannello sostituito
			# armamento: lanciarazzi esterno, gondola cannone interna
			b.box("paint", Vector3(0.1, 0.25, 0.8), Vector3(s * 3.4, 1.0, -0.5), pc * 0.8)
			FactionAir._pod(b, Vector3(s * 3.4, 0.72, -0.6), 0.2, 1.5, Color(0.3, 0.32, 0.26), sg)
			b.box("paint", Vector3(0.1, 0.25, 0.8), Vector3(s * 1.8, 1.0, -0.5), pc * 0.8)
			b.cyl_ab("paint", Vector3(s * 1.8, 0.75, 0.4), Vector3(s * 1.8, 0.75, -1.2), 0.16, 0.16, 8, pc * 0.7)
			b.cyl_ab("metal", Vector3(s * 1.8, 0.75, -1.2), Vector3(s * 1.8, 0.75, -1.8), 0.04, 0.04, 6, DARK)
		)))
	var prop := _mi("Prop", _m("ul_jet_prop", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("paint", Vector3(0, 0, 0.2), Vector3(0, 0, -0.5), 0.3, 0.02, 10, Color(0.2, 0.2, 0.2))
		for i in 4:
			var r := Basis(Vector3.BACK, TAU * float(i) / 4.0)
			b.box("paint", Vector3(0.18, 1.25, 0.04), r * Vector3(0, 0.65, 0), BLADE, 0.0, r * Basis(Vector3.UP, 0.3))
		), Vector3(0, 1.55, -5.6))
	root.add_child(prop)
	root.add_child(_mk("Muzzle", Vector3(-1.8, 0.75, -1.9)))
	_meta(root, 11.5, 3.6)

# ============================================================== DRONI
## AAN: drone MALE con gobba satellitare, ali lunghissime, coda a V, sfera sensori, elica spingente.
static func _drone_aan(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.DRONE_GRAY, c, tint * 0.8)
	var sg := 12 if lod == 0 else 8
	root.add_child(_mi("Body", _m("aan_drone_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-3.6, 0.75, 0.05, 0.05], [-3.35, 0.8, 0.38, 0.4], [-2.5, 0.9, 0.48, 0.55], [-1.0, 0.8, 0.4, 0.42], [2.0, 0.75, 0.28, 0.3], [3.5, 0.75, 0.12, 0.12]], sg, pc)
		_pair(b, "paint", [Vector2(0, -0.55), Vector2(7.6, -0.2), Vector2(7.6, 0.14), Vector2(0, 0.32)], 0.1, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.5)))
		_pair(b, "faction", [Vector2(6.6, -0.24), Vector2(7.62, -0.2), Vector2(7.62, 0.15), Vector2(6.6, 0.17)], 0.12, b.fac, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.5)))
		for s: float in [-1.0, 1.0]:
			b.plate("paint", [Vector2(0, 2.2), Vector2(1.6, 2.9), Vector2(1.6, 3.25), Vector2(0, 3.3)], 0.06, pc,
				Transform3D(Basis(Vector3.BACK, s * 0.75), Vector3(0, 0.8, 0)).scaled_local(Vector3(s, 1, 1)))
			if lod < 2:
				b.box("paint", Vector3(0.08, 0.2, 0.5), Vector3(s * 2.6, 0.85, -0.5), pc * 0.8)
				FactionAir._missile(b, Vector3(s * 2.6, 0.68, -0.6), 0.07, 1.6, Color(0.4, 0.42, 0.36))
		b.cyl_ab("paint", Vector3(0, 0.38, -2.4), Vector3(0, 0.5, -2.4), 0.08, 0.08, 6, pc * 0.8)
		b.sphere("paint", Vector3(0, 0.28, -2.4), Vector3(0.22, 0.22, 0.22), 10, 6, Color(0.3, 0.3, 0.3))
		b.box("glass", Vector3(0.2, 0.14, 0.03), Vector3(0, 0.28, -2.62), Color(0.05, 0.05, 0.06))
		b.box("faction", Vector3(0.3, 0.02, 1.0), Vector3(0, 1.08, 0.6), b.fac)
		)))
	var prop := _mi("Prop", _m("aan_drone_prop", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.sphere("metal", Vector3.ZERO, Vector3(0.1, 0.1, 0.14), 8, 4, GUNMETAL)
		for i in 3:
			var r := Basis(Vector3.BACK, TAU * float(i) / 3.0)
			b.box("paint", Vector3(0.1, 0.75, 0.03), r * Vector3(0, 0.38, 0), BLADE, 0.0, r)
		), Vector3(0, 0.75, 3.6))
	root.add_child(prop)
	root.add_child(_mk("Muzzle", Vector3(0, 0.3, -2.6)))
	_meta(root, 7.2, 1.2)

## FO: drone bitrave robusto: ala alta, travi di coda con impennaggio a H, elica spingente fra le travi, sfera sensori.
static func _drone_fo(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.DRONE_GRAY, c, tint * 0.8)
	var sg := 12 if lod == 0 else 8
	root.add_child(_mi("Body", _m("fo_drone_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-2.7, 0.8, 0.05, 0.05], [-2.4, 0.85, 0.38, 0.38, 2.6], [-1.0, 0.9, 0.5, 0.5, 3.0], [1.2, 0.9, 0.45, 0.45, 3.0], [1.7, 0.9, 0.28, 0.28]], sg, pc)
		_pair(b, "paint", [Vector2(0, -0.8), Vector2(4.2, -0.5), Vector2(4.2, 0.1), Vector2(0, 0.3)], 0.12, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.38, -0.2)))
		_pair(b, "faction", [Vector2(3.4, -0.56), Vector2(4.22, -0.5), Vector2(4.22, 0.11), Vector2(3.4, 0.14)], 0.14, b.fac, Transform3D(Basis.IDENTITY, Vector3(0, 1.38, -0.2)))
		for s: float in [-1.0, 1.0]:
			b.cyl_ab("paint", Vector3(s * 1.25, 1.3, -0.6), Vector3(s * 1.25, 1.3, 3.6), 0.09, 0.07, 8, pc * 0.9)
			_fin(b, "paint", [Vector2(-0.3, 3.0), Vector2(0.75, 3.35), Vector2(0.75, 3.8), Vector2(-0.3, 3.75)], 0.06, pc, Vector3(s * 1.25, 1.3, 0), 0.0)
			if lod < 2:
				FactionAir._missile(b, Vector3(s * 2.4, 1.15, -0.4), 0.08, 1.6, Color(0.36, 0.38, 0.3))
		b.plate("paint", [Vector2(-1.25, 3.25), Vector2(1.25, 3.25), Vector2(1.25, 3.7), Vector2(-1.25, 3.7)], 0.05, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)))
		b.sphere("paint", Vector3(0, 0.38, -1.5), Vector3(0.24, 0.24, 0.24), 10, 6, Color(0.3, 0.3, 0.3))
		b.box("glass", Vector3(0.2, 0.15, 0.03), Vector3(0, 0.38, -1.74), Color(0.05, 0.05, 0.06))
		b.cyl_ab("rubber", Vector3(0, 0.5, -0.8), Vector3(0, 0.15, -0.8), 0.03, 0.03, 4, DARK)
		)))
	var prop := _mi("Prop", _m("fo_drone_prop", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.sphere("metal", Vector3.ZERO, Vector3(0.12, 0.12, 0.16), 8, 4, GUNMETAL)
		b.box("paint", Vector3(1.6, 0.14, 0.04), Vector3.ZERO, BLADE)
		), Vector3(0, 0.9, 1.85))
	root.add_child(prop)
	root.add_child(_mk("Muzzle", Vector3(0, 0.38, -1.8)))
	_meta(root, 6.4, 1.5)

## CP: drone da combattimento a ala volante con motore a getto: pianta a freccia con bordo d'uscita seghettato, presa dorsale, niente coda.
static func _drone_cp(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.DRONE_GRAY, c, tint * 0.8)
	var sg := 14 if lod == 0 else 8
	root.add_child(_mi("Body", _m("cp_drone_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-4.3, 0.9, 0.06, 0.03], [-3.1, 0.95, 0.75, 0.25, 1.8], [-0.6, 1.0, 1.35, 0.4, 2.2], [2.0, 0.95, 1.05, 0.32, 2.2], [3.3, 0.9, 0.5, 0.14]], sg, pc)
		_pair(b, "paint", [Vector2(0.3, -2.7), Vector2(6.4, 2.5), Vector2(5.9, 3.1), Vector2(0.3, 1.2)], 0.12, pc, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
		_pair(b, "paint", [Vector2(0.3, 1.0), Vector2(3.1, 2.25), Vector2(0.3, 3.4)], 0.1, pc, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
		_pair(b, "faction", [Vector2(5.0, 1.3), Vector2(6.42, 2.52), Vector2(5.92, 3.12), Vector2(5.0, 2.55)], 0.14, b.fac, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
		# presa d'aria dorsale e scarico appiattito
		b.hexa("paint", [Vector3(-0.45, 1.3, -1.6), Vector3(0.45, 1.3, -1.6), Vector3(0.5, 1.3, 0.6), Vector3(-0.5, 1.3, 0.6),
			Vector3(-0.4, 1.55, -1.6), Vector3(0.4, 1.55, -1.6), Vector3(0.3, 1.38, 0.6), Vector3(-0.3, 1.38, 0.6)], pc * 0.95)
		b.box("rubber", Vector3(0.75, 0.2, 0.03), Vector3(0, 1.43, -1.62), Color(0.02, 0.02, 0.02))
		b.box("metal", Vector3(1.0, 0.16, 0.3), Vector3(0, 0.95, 3.25), Color(0.18, 0.17, 0.16))
		if lod < 2:
			b.box("rubber", Vector3(0.9, 0.02, 2.2), Vector3(0, 0.62, -0.2), pc * 0.55)   # portelli del vano armi
			b.box("glass", Vector3(0.3, 0.06, 0.4), Vector3(0, 0.6, -3.0), Color(0.05, 0.05, 0.06))
		)))
	root.add_child(_mk("Muzzle", Vector3(0, 0.6, -3.3)))
	_meta(root, 7.6, 1.2)

## UL: munizione circuitante a delta con elica spingente (economica, in serie), vernice sabbia.
static func _drone_ul(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := UnitModels._paint(UnitModels.DRONE_GRAY, c, tint * 0.8)
	var sg := 10 if lod == 0 else 6
	root.add_child(_mi("Body", _m("ul_drone_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.loft("paint", [[-2.1, 0.7, 0.05, 0.05], [-1.8, 0.72, 0.2, 0.22], [0.9, 0.72, 0.2, 0.22], [1.5, 0.72, 0.13, 0.13]], sg, pc)
		_pair(b, "paint", [Vector2(0, -1.0), Vector2(1.55, 1.15), Vector2(1.55, 1.4), Vector2(0, 1.4)], 0.07, pc, Transform3D(Basis.IDENTITY, Vector3(0, 0.72, 0)))
		for s: float in [-1.0, 1.0]:
			_fin(b, "paint", [Vector2(-0.25, 0.85), Vector2(0.35, 1.15), Vector2(0.35, 1.4), Vector2(-0.25, 1.4)], 0.05, pc, Vector3(s * 1.55, 0.72, 0), 0.0)
			b.box("faction", Vector3(0.5, 0.09, 0.3), Vector3(s * 1.1, 0.72, 1.1), b.fac)
		b.box("faction", Vector3(0.2, 0.02, 0.5), Vector3(0, 0.93, -0.6), b.fac)
		b.cyl_ab("paint", Vector3(0, 0.72, -2.1), Vector3(0, 0.72, -2.25), 0.05, 0.0, 6, RUST)
		)))
	var prop := _mi("Prop", _m("ul_drone_prop", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.sphere("metal", Vector3.ZERO, Vector3(0.06, 0.06, 0.08), 6, 3, GUNMETAL)
		b.box("paint", Vector3(0.9, 0.09, 0.03), Vector3.ZERO, BLADE)
		), Vector3(0, 0.72, 1.6))
	root.add_child(prop)
	root.add_child(_mk("Muzzle", Vector3(0, 0.72, -2.3)))
	_meta(root, 3.8, 0.9)
