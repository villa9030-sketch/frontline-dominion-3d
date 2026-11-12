class_name BattleDecor
extends RefCounted
## Densità dei dettagli del campo di battaglia (solo vista: nessun effetto su movimento, visibilità o combattimento).
## Rotoballe e pile di fieno nei campi, frutteti, tettoie e cataste, filari d'alberi lungo le strade, sottobosco nei
## boschi, fattorie e casali in più, arredo urbano (lampioni, auto parcheggiate, panchine, cestini).
## Tutto in MultiMesh (via BattleTerrain._lm_add / _add_instances) con distanza di disegno limitata per gli oggetti piccoli.
## Usa un generatore casuale proprio: la disposizione già esistente del terreno non cambia.

var T: BattleTerrain
var rng := RandomNumberGenerator.new()

func build(t: BattleTerrain) -> void:
	T = t
	rng.seed = int(t.sim.seed_) * 31 + 11
	match t.tkey:
		"pianura", "foresta":
			_field_props()
	_wood_undergrowth()
	if t.tkey == "urbano":
		_street_props()
	else:
		_roadside_trees()
		_more_settlements()
	T._flush_landmarks()

# ---------------------------------------------------------------------------- servizi
## Punto adatto a un oggetto basso: pianeggiante, asciutto, fuori da strade e boschi.
func _ok(X: float, Z: float, wood_margin := 3.0) -> bool:
	if T._near_road_world(X, Z):
		return false
	if T.normal(X, Z).y < 0.95:
		return false
	if T.sim.sea and (T.height(X, Z) < 1.5 or X < T.coast_x(Z) + 20.0):
		return false
	for w in T.woods:
		if Vector2(X, Z).distance_to(w["c"]) < float(w["r"]) + wood_margin:
			return false
	var ps: Vector2 = T.world_to_sim(X, Z)
	if T.relief.water_at(ps.x, ps.y) > 0.0:
		return false
	return true

## Il punto è dentro un campo coltivato (non ritagliato da boschi o lago)?
func _in_crop(X: float, Z: float) -> bool:
	if T.field_img == null:
		return false
	var q := T._fq(Vector2(X, Z))
	var fu := q / T._field_L + Vector2(0.5, 0.5)
	if fu.x <= 0.0 or fu.y <= 0.0 or fu.x >= 1.0 or fu.y >= 1.0:
		return false
	var fc := T.field_img.get_pixel(int(fu.x * T.field_img.get_width()), int(fu.y * T.field_img.get_height()))
	return fc.a > 0.9 and fc.r8 > 0

func _ground(X: float, Z: float, sink := 0.1) -> Vector3:
	return Vector3(X, T.height(X, Z) - sink, Z)

func _tree_item(X: float, Z: float, sc: float) -> Array:
	return [_ground(X, Z, 0.2), sc, rng.randf() * TAU, T._tint()]

# ---------------------------------------------------------------------------- campi
func _field_props() -> void:
	var lim := Vector2(T.FIELD_HX + 420.0, T.FIELD_HZ + 360.0)
	var ax := T._fw(Vector2(1, 0)) - T._fw(Vector2.ZERO)   # direzione dei filari (asse q.x) nel mondo
	var row_yaw := atan2(ax.x, ax.y)
	var orchard := []
	for c in T.field_cells:
		var x0: float = c[0]
		var q0: float = c[1]
		var w: float = c[2]
		var h: float = c[3]
		var t: int = c[4]
		var cw := T._fw(Vector2(x0 + w * 0.5, q0 + h * 0.5))
		if absf(cw.x) > lim.x or absf(cw.y) > lim.y:
			continue
		var outside := not T._in_field(cw.x, cw.y, 10.0)
		# prati e medicai: macchie di cespugli e rovi (bassi: non nascondono le unità), più fitte lungo i bordi
		if t <= 0 or t == 5:
			_bush_clumps(x0, q0, w, h, int(w * h / (1800.0 if t <= 0 else 3000.0)))
		if t <= 0:
			continue
		var r := rng.randf()
		if t == 4 and r < 0.6:
			# stoppie: rotoballe sparse su file parallele
			var rows := 1 + rng.randi() % 3
			for k in rows:
				var qy := q0 + h * (k + 0.5) / rows + rng.randf_range(-4.0, 4.0)
				var qx := x0 + 8.0 + rng.randf() * 10.0
				while qx < x0 + w - 8.0:
					var p := T._fw(Vector2(qx, qy + rng.randf_range(-1.2, 1.2)))
					if _in_crop(p.x, p.y) and _ok(p.x, p.y):
						T._lm_add("bale", _ground(p.x, p.y, 0.05), row_yaw + rng.randf_range(-0.5, 0.5), Vector3.ONE * rng.randf_range(0.9, 1.1), _hay_tint())
					qx += rng.randf_range(9.0, 20.0)
		elif (t == 1 or t == 4) and r < 0.75:
			# pila di balle quadre vicino a un angolo del campo
			var p := T._fw(Vector2(x0 + rng.randf_range(6.0, 14.0), q0 + rng.randf_range(6.0, 14.0)))
			if _in_crop(p.x, p.y) and _ok(p.x, p.y):
				T._lm_add("bales", _ground(p.x, p.y, 0.05), row_yaw + rng.randf_range(-0.2, 0.2), Vector3.ONE, _hay_tint())
		elif t == 2 and outside and r < 0.3:
			# frutteto (solo fuori dal campo di battaglia: non nasconde unità che la simulazione considera visibili)
			var qy := q0 + 5.0
			while qy < q0 + h - 4.0:
				var qx := x0 + 5.0
				while qx < x0 + w - 4.0:
					var p := T._fw(Vector2(qx, qy))
					if _in_crop(p.x, p.y) and _ok(p.x, p.y) and not T._in_field(p.x, p.y, 6.0):
						orchard.append(_tree_item(p.x, p.y, rng.randf_range(0.3, 0.4)))
					qx += 7.0
				qy += 8.0
		# tettoia con catasta e abbeveratoio all'angolo di qualche campo fuori dal campo di battaglia
		if outside and rng.randf() < 0.07:
			var p := T._fw(Vector2(x0 + 7.0, q0 + 6.0))
			if _ok(p.x, p.y, 6.0) and T._site_ok(p.x, p.y, 6.0, true):
				T._lm_add("shed", _ground(p.x, p.y, 0.2), row_yaw, Vector3.ONE, Color(1, 1, 1), Vector3(8.2, 4.0, 5.6))
				var q := T._fw(Vector2(x0 + 7.0, q0 + 12.5))
				if _ok(q.x, q.y):
					T._lm_add("woodpile", _ground(q.x, q.y, 0.05), row_yaw + PI * 0.5, Vector3.ONE, Color(1, 1, 1))
				if rng.randf() < 0.5:
					var q2 := T._fw(Vector2(x0 + 14.0, q0 + 4.0))
					if _ok(q2.x, q2.y):
						T._lm_add("trough", _ground(q2.x, q2.y, 0.05), row_yaw, Vector3.ONE, Color(1, 1, 1))
	if not orchard.is_empty():
		T.set_tree_range(T._add_instances("broadleaf", orchard), 900.0)
	if not _clumps.is_empty():
		T.set_tree_range(T._add_instances("bush", _clumps, false), 700.0)

var _clumps := []
func _bush_clumps(x0: float, q0: float, w: float, h: float, n: int) -> void:
	for k in n:
		# vicino a un bordo del campo nel 70% dei casi
		var u := rng.randf()
		var v := rng.randf()
		if rng.randf() < 0.7:
			if rng.randf() < 0.5:
				u = 0.04 if rng.randf() < 0.5 else 0.96
			else:
				v = 0.05 if rng.randf() < 0.5 else 0.95
		var c := T._fw(Vector2(x0 + u * w, q0 + v * h))
		if not _ok(c.x, c.y):
			continue
		for j in 2 + rng.randi() % 3:
			var p := c + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			_clumps.append([_ground(p.x, p.y, 0.15), rng.randf_range(0.45, 0.95), rng.randf() * TAU, T._tint()])

func _hay_tint() -> Color:
	var v := rng.randf_range(0.88, 1.08)
	return Color(v, v * rng.randf_range(0.95, 1.02), v * rng.randf_range(0.85, 1.0))

# ---------------------------------------------------------------------------- boschi
## Sottobosco: cespugli, alberelli giovani e qualche masso dentro ogni bosco (sfumano insieme agli alberi).
func _wood_undergrowth() -> void:
	if T.tkey == "artico" or T.tkey == "urbano":
		return
	var low := "dead" if T.tkey == "deserto" else "bush"
	for w in T.woods:
		var c: Vector2 = w["c"]
		var R: float = w["r"]
		var n := int(PI * R * R / 75.0)
		var bushes := []
		var young := []
		for k in n:
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * R * 0.95
			var X := c.x + cos(a) * rr
			var Z := c.y + sin(a) * rr
			if T._near_road_world(X, Z):
				continue
			if k % 7 == 0 and T.tkey != "deserto":
				young.append(_tree_item(X, Z, rng.randf_range(0.28, 0.45)))
			else:
				bushes.append([_ground(X, Z, 0.15), rng.randf_range(0.6, 1.3), rng.randf() * TAU, T._tint()])
		# chiome di riempimento tra gli alberi del bosco: dall'alto il bosco si legge come una massa continua
		if T.tkey != "deserto":
			var fill := []
			var nf := int(PI * R * R / 140.0)
			for k in nf:
				var a := rng.randf() * TAU
				var rr := sqrt(rng.randf()) * R * 0.9
				var X := c.x + cos(a) * rr
				var Z := c.y + sin(a) * rr
				if T._near_road_world(X, Z):
					continue
				fill.append(_tree_item(X, Z, rng.randf_range(0.65, 1.0)))
			if not fill.is_empty():
				var nodes0: Array = w["nodes"]
				nodes0 += T._add_instances("pine" if T.tkey in ["montagna", "foresta"] and rng.randf() < 0.5 else "broadleaf", fill)
				w["nodes"] = nodes0
		var nodes: Array = w["nodes"]
		var under := T._add_instances(low, bushes, false)
		# sottobosco: si vede solo da vicino (dalla vista alta lo coprono le chiome)
		T.set_tree_range(under, 420.0, 60.0)
		nodes += under
		if not young.is_empty():
			nodes += T._add_instances("birch" if rng.randf() < 0.4 else "broadleaf", young)
		w["nodes"] = nodes

# ---------------------------------------------------------------------------- strade e insediamenti
## Filari d'alberi lungo le strade fuori dal campo di battaglia (cipressi o pioppi/betulle, a tratti).
func _roadside_trees() -> void:
	if T.tkey == "deserto":
		return
	var kind: String = {"pianura": "cypress", "foresta": "birch", "montagna": "pine", "artico": "snowpine"}.get(T.tkey, "broadleaf")
	var items := []
	for road in T.outer_roads:
		var on := rng.randf() < 0.6
		var run := rng.randf_range(80.0, 220.0)
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var s := 0.0
			while s < L:
				run -= 13.0
				if run <= 0.0:
					on = not on
					run = rng.randf_range(60.0, 240.0)
				if on:
					for side in [-1.0, 1.0]:
						var p: Vector2 = a + d * s + nrm * float(side) * rng.randf_range(10.5, 12.0)
						if T._in_field(p.x, p.y, 8.0) or absf(p.x) > T.FIELD_HX + 700.0 or absf(p.y) > T.FIELD_HZ + 560.0:
							continue
						if T.height(p.x, p.y) < 1.2 or T.normal(p.x, p.y).y < 0.85:
							continue
						if T.sim.sea and p.x < T.coast_x(p.y) + 20.0:
							continue
						items.append(_tree_item(p.x, p.y, rng.randf_range(0.75, 1.05)))
				s += 13.0
	if not items.is_empty():
		# fuori dal campo: ombre inutili (la telecamera da vicino guarda il campo)
		T.set_tree_range(T._add_instances(kind, items, false), 900.0)

## Più fattorie e casali attorno al campo, con il generatore casuale della decorazione.
func _more_settlements() -> void:
	var saved := T.rng
	T.rng = rng
	match T.tkey:
		"pianura":
			for k in 4:
				var rs := T._roadside(26.0 + rng.randf() * 30.0, 420.0)
				if not rs.is_empty() and T._site_ok(rs[0].x, rs[0].y, 20.0):
					T._farm(rs[0], rs[1])
					_farm_extras(rs[0], rs[1])
			for k in 2:
				var hs := T._roadside(18.0, 380.0)
				if not hs.is_empty():
					T._hamlet(hs[0], hs[1], "house", 3 + rng.randi() % 3, 34.0)
		"foresta":
			for k in 2:
				var rs := T._roadside(30.0, 380.0)
				if not rs.is_empty() and T._site_ok(rs[0].x, rs[0].y, 20.0):
					T._farm(rs[0], rs[1])
					_farm_extras(rs[0], rs[1])
			var hs := T._roadside(16.0, 380.0)
			if not hs.is_empty():
				T._hamlet(hs[0], hs[1], "chalet", 3, 26.0)
		"montagna", "artico":
			var hs := T._roadside(16.0, 380.0)
			if not hs.is_empty():
				T._hamlet(hs[0], hs[1], "chalet", 2 + rng.randi() % 3, 30.0)
		"deserto":
			var hs := T._roadside(22.0, 400.0)
			if not hs.is_empty():
				T._hamlet(hs[0], hs[1], "hut", 4 + rng.randi() % 3, 30.0)
	T.rng = saved

## Aia della fattoria: balle, catasta di legna, abbeveratoio.
func _farm_extras(c: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for o in [[Vector3(8.0, 0, -10.0), "bales"], [Vector3(-4.0, 0, 10.0), "woodpile"], [Vector3(14.0, 0, 11.0), "trough"], [Vector3(28.0, 0, -10.0), "bale"], [Vector3(31.0, 0, -9.0), "bale"]]:
		var w: Vector3 = b * o[0]
		var p := c + Vector2(w.x, w.z)
		if T.normal(p.x, p.y).y > 0.94 and not T._near_road_world(p.x, p.y):
			T._lm_add(o[1], _ground(p.x, p.y, 0.05), yaw + rng.randf_range(-0.3, 0.3), Vector3.ONE, _hay_tint() if String(o[1]).begins_with("bale") else Color(1, 1, 1))

# ---------------------------------------------------------------------------- città
const CAR_COLORS := [Color(0.62, 0.1, 0.08), Color(0.12, 0.2, 0.42), Color(0.85, 0.85, 0.82), Color(0.15, 0.15, 0.16), Color(0.5, 0.52, 0.54),
	Color(0.2, 0.36, 0.22), Color(0.78, 0.62, 0.2), Color(0.35, 0.3, 0.26)]

## Lampioni e auto parcheggiate lungo i lati degli isolati (dentro e fuori dal campo), panchine e cestini nei parchi.
func _street_props() -> void:
	_roof_props()
	for blk in T.sim.blocks:
		var p: Vector2 = T.sim_to_world(blk["x"], blk["y"])
		var w: float = blk["w"] * T.S
		var d: float = blk["h"] * T.S
		if blk["park"]:
			_park_props(p, w, d)
		else:
			_block_edges(p, w, d, 0.35)
	var G := T.city_grid()
	var px: float = G["bw"] + G["st"]
	var pz: float = G["bh"] + G["st"]
	var lim := T.FIELD_HX + 320.0
	for i in range(int(floor((-lim - G["gx0"]) / px)), int(ceil((lim - G["gx0"]) / px)) + 1):
		for j in range(int(floor((-lim * 0.8 - G["gz0"]) / pz)), int(ceil((lim * 0.8 - G["gz0"]) / pz)) + 1):
			var x: float = G["gx0"] + i * px
			var z: float = G["gz0"] + j * pz
			if T._in_field(x + G["bw"] * 0.5, z + G["bh"] * 0.5, 18.0):
				continue
			if T.sim.sea and x < T.coast_x(z) + 30.0:
				continue
			_block_edges(Vector2(x, z), G["bw"], G["bh"], 0.25)

## Tetti: parapetto perimetrale, torrino delle scale, serbatoi, impianti e lucernari (dalla vista alta i tetti grigi
## piatti erano la parte più "vuota" della città).
func _roof_props() -> void:
	for bx in T.city_boxes:
		var c: Vector3 = bx[0]
		var sz: Vector3 = bx[1]
		var col: Color = bx[2]
		if sz.x < 6.0 or sz.z < 6.0:
			continue
		var top := c.y + sz.y * 0.5
		var pc := col.darkened(0.12)
		var th := 0.35
		var ph := 0.7 + rng.randf() * 0.5
		T._lm_add("slab", Vector3(c.x, top, c.z - sz.z * 0.5 + th * 0.5), 0.0, Vector3(sz.x, ph, th), pc)
		T._lm_add("slab", Vector3(c.x, top, c.z + sz.z * 0.5 - th * 0.5), 0.0, Vector3(sz.x, ph, th), pc)
		T._lm_add("slab", Vector3(c.x - sz.x * 0.5 + th * 0.5, top, c.z), 0.0, Vector3(th, ph, sz.z - 2 * th), pc)
		T._lm_add("slab", Vector3(c.x + sz.x * 0.5 - th * 0.5, top, c.z), 0.0, Vector3(th, ph, sz.z - 2 * th), pc)
		var inner := Vector2(sz.x * 0.5 - 2.5, sz.z * 0.5 - 2.5)
		if inner.x < 1.0 or inner.y < 1.0:
			continue
		# torrino delle scale
		if rng.randf() < 0.75:
			var p := Vector2(c.x + rng.randf_range(-inner.x, inner.x) * 0.7, c.z + rng.randf_range(-inner.y, inner.y) * 0.7)
			T._lm_add("slab", Vector3(p.x, top, p.y), 0.0, Vector3(3.2, 2.6, 3.6), col.darkened(0.05))
		# serbatoio o impianti
		if rng.randf() < 0.35 and sz.x > 12.0:
			var p := Vector2(c.x + rng.randf_range(-inner.x, inner.x) * 0.8, c.z + rng.randf_range(-inner.y, inner.y) * 0.8)
			T._lm_add("tank", Vector3(p.x, top, p.y), rng.randf() * TAU, Vector3.ONE, Color(1, 1, 1))
		for k in rng.randi() % 4:
			var p := Vector2(c.x + rng.randf_range(-inner.x, inner.x), c.z + rng.randf_range(-inner.y, inner.y))
			var g := rng.randf_range(0.55, 0.75)
			if rng.randf() < 0.5:
				T._lm_add("slab", Vector3(p.x, top, p.y), 0.0, Vector3(rng.randf_range(1.2, 2.4), rng.randf_range(0.8, 1.4), rng.randf_range(1.2, 2.0)), Color(g, g, g * 1.02))
			else:
				# lucernario
				T._lm_add("slab", Vector3(p.x, top, p.y), 0.0, Vector3(rng.randf_range(2.0, 4.0), 0.35, rng.randf_range(1.5, 2.5)), Color(0.35, 0.45, 0.52))

## Un isolato rettangolare (angolo p, lati w × d): lampioni ogni ~22 m e auto in sosta sul bordo della strada.
func _block_edges(p: Vector2, w: float, d: float, car_k: float) -> void:
	var sides := [[p, Vector2(1, 0), w, Vector2(0, -1)], [p + Vector2(0, d), Vector2(1, 0), w, Vector2(0, 1)],
		[p, Vector2(0, 1), d, Vector2(-1, 0)], [p + Vector2(w, 0), Vector2(0, 1), d, Vector2(1, 0)]]
	for sd in sides:
		var o: Vector2 = sd[0]
		var dir: Vector2 = sd[1]
		var L: float = sd[2]
		var out: Vector2 = sd[3]
		var yaw := atan2(dir.x, dir.y)
		var s := 6.0
		var lamp_i := 0
		while s < L - 6.0:
			var base := o + dir * s
			if lamp_i % 4 == 0:
				var lp := base + out * 0.7
				# il braccio del lampione guarda verso la strada
				T._lm_add("lamp", _ground(lp.x, lp.y, 0.05), atan2(out.x, out.y), Vector3.ONE, Color(1, 1, 1))
				T.add_glow(lp + out * 1.4, 12.0, 0.8, Color(1.0, 0.85, 0.6), 5.8)
			elif rng.randf() < car_k:
				var cp := base + out * 2.1
				if not (T.sim.sea and T.height(cp.x, cp.y) < 1.2):
					T._lm_add("car", _ground(cp.x, cp.y, 0.02), yaw + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.05, 0.05),
						Vector3.ONE, CAR_COLORS[rng.randi() % CAR_COLORS.size()] * rng.randf_range(0.85, 1.1))
			lamp_i += 1
			s += 5.5

func _park_props(p: Vector2, w: float, d: float) -> void:
	var n := int((w + d) / 12.0)
	for k in n:
		var along := rng.randf()
		var horiz := rng.randf() < 0.5
		var X: float
		var Z: float
		var yaw: float
		if horiz:
			X = p.x + 3.0 + along * (w - 6.0)
			var top := rng.randf() < 0.5
			Z = p.y + (3.0 if top else d - 3.0)
			yaw = 0.0 if top else PI
		else:
			Z = p.y + 3.0 + along * (d - 6.0)
			var left := rng.randf() < 0.5
			X = p.x + (3.0 if left else w - 3.0)
			yaw = PI * 0.5 if left else -PI * 0.5
		T._lm_add("bench" if k % 3 != 2 else "bin", _ground(X, Z, 0.02), yaw, Vector3.ONE, Color(1, 1, 1))
