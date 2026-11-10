class_name MapDecor
extends Node3D
## Arredo del tabellone strategico ("tabellone più ricco"): boschi in ciuffi per bioma, città 3D (MultiMesh con finestre
## accese di notte), strutture visibili quando costruite (porti sulla costa, aeroporti, fabbriche con fumo, caserme,
## fortificazioni, impianti, cantieri), compound del QG con bandiera, anelli di trincee/mine/bunker secondo i livelli,
## fronte animato sui confini contesi (scintille di fuoco, fumo, vampate d'artiglieria) e fumo sui territori appena conquistati.
## Legge lo stato di gioco a ogni aggiornamento (nessun aggancio a main.gd): rigenera solo ciò che è cambiato.

const D = preload("res://scripts/core/data.gd")
const NT := 42
const VIS_STRUCT := 64.0
const VIS_CITY := 110.0
const VIS_FOREST := 50.0
const MAX_SPECKS := 1100
const SLOT_ANGLES := [0.45, 1.05, 1.62, 2.15, 2.72, 3.3]
const CAPTURE_SMOKE_T := 45.0

var wm = null              # WorldMap
var data: Dictionary = {}
var quality := "alto"

var _k: PackedFloat32Array = PackedFloat32Array()   # fattore di scala per territorio (densità dei vicini)
var _centers: Array = []
var _slots: Array = []     # per territorio: Array[{pos: Vector3, ang: float}]
var _coast: Array = []     # per territorio: {pos, ang} oppure {}
var _forest_root: Node3D = null
var _forest_density := -1.0
var _tree_mat: ShaderMaterial = null
var _city_mat: ShaderMaterial
var _city_mmi: MultiMeshInstance3D = null
var _terr_root: Node3D
var _terr_nodes: Array = []
var _terr_sig: PackedStringArray = PackedStringArray()
var _chimneys: Array = []  # per territorio: Array[Vector3] (mondo)
var _acc := 0.0
# fronte
var _border_pts := {}      # "a,b" (a<b) -> PackedVector3Array
var _pair_heat := {}       # "a,b" -> tempo reale dell'ultimo attacco
var _captures := {}        # idx -> tempo reale della conquista
var _mm_add: MultiMeshInstance3D
var _mm_mix: MultiMeshInstance3D
var _specks_mat_add: ShaderMaterial
var _specks_mat_mix: ShaderMaterial
var _specks_sig := ""
var _real_t := 0.0
var _rng := RandomNumberGenerator.new()
var _last_pairs: Array = []
var _terr_heat: PackedFloat32Array = PackedFloat32Array()

# ====================================================================== impostazione
func setup(world_map) -> void:
	wm = world_map
	data = wm.data
	name = "Decor"
	_rng.seed = 777
	_k.resize(NT)
	_terr_heat.resize(NT)
	_terr_heat.fill(0.0)
	for t in D.TERRITORIES:
		var i: int = t["idx"]
		var md := 1e9
		for u in D.TERRITORIES:
			if u["idx"] == i:
				continue
			md = minf(md, Vector2(float(t["x"]) - float(u["x"]), float(t["y"]) - float(u["y"])).length())
		_k[i] = clampf(md / 85.0, 0.58, 1.0)
		_centers.append(wm.map_to_world(float(t["x"]), float(t["y"])))
		_slots.append(_make_slots(i))
		_coast.append(_find_coast(i))
		_chimneys.append([])
	_terr_root = Node3D.new()
	_terr_root.name = "Structures"
	add_child(_terr_root)
	for i in NT:
		var nd := Node3D.new()
		nd.name = "T%d" % i
		nd.position = _centers[i]
		_terr_root.add_child(nd)
		_terr_nodes.append(nd)
		_terr_sig.append("")
	_build_border_points()
	_build_cities()
	_build_specks()

## Materiali che seguono il ciclo giorno/notte (WorldMap imposta daynight/sun_lon/sun_decl).
func dn_materials() -> Array:
	return [_city_mat, MapProps.lights_mat(), MapProps.struct_mat(), _tree_mat]

func _h(mx: float, my: float) -> float:
	return MapGen.height_at(data, mx, my)

func _tid(mx: float, my: float) -> int:
	return MapGen.territory_at(data, mx, my)

func _w2m(p: Vector3) -> Vector2:
	return wm.world_to_map(p)

## Punto del mondo a terra per coordinate mappa.
func _ground(mx: float, my: float) -> Vector3:
	return wm.map_to_world(mx, my)

## Pendenza approssimata (differenza di quota su ~0.6 unità).
func _slope(mx: float, my: float) -> float:
	var h0 := _h(mx, my)
	var s := 0.0
	for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		s = maxf(s, absf(_h(mx + o.x, my + o.y) - h0))
	return s

## Punto valido per una struttura: terra, stesso territorio, pendio dolce.
func _ok_spot(i: int, mx: float, my: float, same := true) -> bool:
	if _h(mx, my) < 0.03:
		return false
	if same and _tid(mx, my) != i:
		return false
	return _slope(mx, my) < 0.09

## Sei posti per le strutture sul lato sud del distintivo (verso la telecamera), in coordinate mappa; se il posto cade in
## mare o fuori dal territorio si prova più vicino/lontano o ruotando un po'.
func _make_slots(i: int) -> Array:
	var T: Dictionary = D.TERRITORIES[i]
	var out: Array = []
	var k := _k[i]
	for a in SLOT_ANGLES:
		var found := false
		var best := Vector2(float(T["x"]) + cos(a) * 29.0 * k, float(T["y"]) + sin(a) * 29.0 * k)
		var bang: float = a
		for rr in [29.0, 24.0, 34.0, 20.0, 39.0]:
			for da in [0.0, 0.18, -0.18, 0.36, -0.36]:
				var ang: float = a + da
				var mx: float = float(T["x"]) + cos(ang) * rr * k
				var my: float = float(T["y"]) + sin(ang) * rr * k
				if _ok_spot(i, mx, my):
					best = Vector2(mx, my)
					bang = ang
					found = true
					break
			if found:
				break
		if not found:
			# almeno sulla terraferma, anche fuori dal territorio
			for rr in [29.0, 22.0, 36.0]:
				for da in [0.0, 0.3, -0.3, 0.6, -0.6]:
					var ang: float = a + da
					var mx: float = float(T["x"]) + cos(ang) * rr * k
					var my: float = float(T["y"]) + sin(ang) * rr * k
					if _ok_spot(i, mx, my, false):
						best = Vector2(mx, my)
						bang = ang
						found = true
						break
				if found:
					break
		out.append({"map": best, "pos": _ground(best.x, best.y), "ang": bang, "ok": found})
	return out

## Punto di costa più vicino al centro (per il porto): raggi dal centro fino al mare; preferisce la costa del territorio stesso.
func _find_coast(i: int) -> Dictionary:
	var T: Dictionary = D.TERRITORIES[i]
	var cx := float(T["x"])
	var cy := float(T["y"])
	var best := {}
	var bd := 1e9
	var best_any := {}
	var bd_any := 1e9
	for s in 28:
		var a := TAU * float(s) / 28.0
		var dx := cos(a)
		var dy := sin(a)
		var last_land := Vector2(cx, cy)
		var r := 2.0
		while r < 110.0:
			var mx := cx + dx * r
			var my := cy + dy * r
			if mx < 2 or my < 2 or mx > D.MAP_W - 2 or my > D.MAP_H - 2:
				break
			if _h(mx, my) < 0.0:
				# costa trovata: la banchina parte un po' nell'entroterra
				var sx := cx + dx * (r - 3.5)
				var sy := cy + dy * (r - 3.5)
				var e := {"map": Vector2(sx, sy), "pos": _ground(sx, sy), "dir": Vector3(dx, 0, dy), "r": r}
				if _tid(sx, sy) == i and r < bd and r > 14.0:
					bd = r
					best = e
				if r < bd_any and r > 10.0:
					bd_any = r
					best_any = e
				break
			last_land = Vector2(mx, my)
			r += 1.5
	if best.is_empty():
		best = best_any
	return best

# ====================================================================== boschi
## Ciuffi di alberi per bioma: conifere a nord e in montagna, latifoglie temperate, palme ai tropici e nei deserti (rade),
## conifere innevate ai margini artici. Evita la zona del distintivo (pedine, città, strutture).
func set_forest(density: float, q: String) -> void:
	quality = q
	if is_equal_approx(density, _forest_density):
		return
	_forest_density = density
	if _forest_root != null:
		_forest_root.queue_free()
		_forest_root = null
	if density <= 0.0:
		return
	var props = MapProps.global_class_script("Props")
	if props == null or not props.has_method("tree_mesh"):
		return
	var t0 := Time.get_ticks_msec()
	_forest_root = Node3D.new()
	_forest_root.name = "Forest"
	add_child(_forest_root)
	var ter1: Image = data["ter1"]
	var ter2: Image = data["ter2"]
	var tw: int = data["tw"]
	var th: int = data["th"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	const CX := 8
	const CZ := 5
	var buckets := {}   # "cx,cz,kind|season" -> Array[Transform3D]
	var step := 7.0     # px mappa tra i candidati di ciuffo
	var y := step * 0.5
	var total := 0
	var clumps := 0
	while y < D.MAP_H:
		var x := step * 0.5
		while x < D.MAP_W:
			var px := x + rng.randf_range(-step, step) * 0.5
			var py := y + rng.randf_range(-step, step) * 0.5
			x += step
			var h := _h(px, py)
			if h < 0.06:
				continue
			var ti := _tid(px, py)
			if ti < 0:
				continue
			# zona libera attorno al distintivo
			var T: Dictionary = D.TERRITORIES[ti]
			var dc := Vector2(px - float(T["x"]), py - float(T["y"])).length()
			if dc < 36.0 * _k[ti]:
				continue
			var tx := clampi(int(px / D.MAP_W * tw), 0, tw - 1)
			var ty := clampi(int(py / D.MAP_H * th), 0, th - 1)
			var c1 := ter1.get_pixel(tx, ty)
			var c2 := ter2.get_pixel(tx, ty)
			var w_for := c1.a
			var w_mtn := c1.r
			var w_arc := c1.b
			var w_des := c1.g
			var w_pia := c2.g
			var w_urb := c2.r
			var p := w_for * 0.95 + w_mtn * 0.32 + w_pia * 0.16 + w_des * 0.035 + w_urb * 0.08
			p *= (1.0 - w_arc * 0.92) * density
			if h > 0.85:
				p *= 0.15
			elif h > 0.6:
				p *= 0.6
			if rng.randf() > p:
				continue
			# bioma
			var kind := "broadleaf"
			var season := ""
			var north: bool = py < 215.0
			var tropic: bool = py > 380.0 and py < 560.0
			if w_arc > 0.25 or (north and rng.randf() < 0.85):
				kind = "pine"
				if w_arc > 0.25 or py < 140.0:
					season = "snow"
			elif w_mtn > 0.35:
				kind = "pine" if rng.randf() < 0.8 else "broadleaf"
			elif w_des > 0.4:
				kind = "palm"
				season = "dry" if rng.randf() < 0.5 else ""
			elif tropic:
				kind = "palm" if rng.randf() < 0.55 else "broadleaf"
			elif w_for > 0.4 and rng.randf() < 0.4:
				kind = "pine"
			elif rng.randf() < 0.12:
				kind = "birch"
			# ciuffo di 2–7 alberi
			var nn := 1 if w_des > 0.4 else rng.randi_range(2, 7)
			if w_pia > 0.5 and rng.randf() < 0.5:
				nn = rng.randi_range(1, 3)
			var cr := 2.0 + nn * 0.9
			var base_s := 0.026 if kind == "pine" else (0.036 if kind == "broadleaf" else (0.03 if kind == "palm" else 0.032))
			for q2 in nn:
				var ang := rng.randf() * TAU
				var rr := sqrt(rng.randf()) * cr
				var qx := px + cos(ang) * rr
				var qy := py + sin(ang) * rr
				var hh := _h(qx, qy)
				if hh < 0.04:
					continue
				var wp := Vector3(qx * wm.SCALE - wm.HALF.x, hh - 0.012, qy * wm.SCALE - wm.HALF.y)
				var s := base_s * rng.randf_range(0.8, 1.25)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s))
				var cx := clampi(int((wp.x + wm.HALF.x) / (160.0 / CX)), 0, CX - 1)
				var cz := clampi(int((wp.z + wm.HALF.y) / (90.0 / CZ)), 0, CZ - 1)
				var key := "%d,%d,%s|%s" % [cx, cz, kind, season]
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(Transform3D(b, wp))
				total += 1
			clumps += 1
		y += step
	if _tree_mat == null:
		_tree_mat = ShaderMaterial.new()
		_tree_mat.shader = load("res://scripts/map/map_tree.gdshader")
	var mat := _tree_mat
	for key in buckets:
		var arr: Array = buckets[key]
		var ks: String = String(key).get_slice(",", 2)
		var kind: String = ks.get_slice("|", 0)
		var season: String = ks.get_slice("|", 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = props.tree_mesh(kind, season)
		mm.instance_count = arr.size()
		for k in arr.size():
			mm.set_instance_transform(k, arr[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality == "alto" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VIS_FOREST
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_forest_root.add_child(mmi)
	print("[MapDecor] boschi: ", total, " alberi in ", clumps, " ciuffi, ", buckets.size(), " gruppi in ", Time.get_ticks_msec() - t0, " ms")

# ====================================================================== città
## Un unico MultiMesh di parallelepipedi: isolati su una griglia ruotata per territorio, a nord del distintivo; più grandi e fitti
## per i territori urbani e di alto valore. Il colore dei muri varia col bioma (cemento, mattoni, sabbia, bianco mediterraneo).
func _build_cities() -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var xf: Array = []
	var cols: Array = []
	var cust: Array = []
	for t in D.TERRITORIES:
		var i: int = t["idx"]
		var k := _k[i]
		var ter: String = t["ter"]
		var amt := float(t.get("amt", 1.0))
		var urban := ter == "urbano"
		var n := int((9.0 + 20.0 * amt / 1.2) * (2.3 if urban else 1.0) * (0.55 + 0.45 * k))
		if ter == "artico":
			n = int(n * 0.45)
		elif ter == "montagna" or ter == "deserto":
			n = int(n * 0.7)
		var cc_map := Vector2(float(t["x"]) - 4.0 * k, float(t["y"]) - 22.0 * k)
		var rc := (12.5 + 2.5 * (1.0 if urban else 0.0)) * k
		var ga := rng.randf() * PI
		var gx := Vector2(cos(ga), sin(ga))
		var gz := Vector2(-sin(ga), cos(ga))
		var cell := 2.2   # px mappa (0.22 unità)
		var palette: Array
		match ter:
			"deserto": palette = [Color(0.80, 0.70, 0.52), Color(0.74, 0.62, 0.45), Color(0.85, 0.78, 0.62)]
			"artico": palette = [Color(0.62, 0.64, 0.66), Color(0.55, 0.50, 0.44), Color(0.70, 0.70, 0.68)]
			"montagna": palette = [Color(0.64, 0.60, 0.54), Color(0.55, 0.47, 0.40), Color(0.70, 0.68, 0.62)]
			"urbano": palette = [Color(0.66, 0.66, 0.64), Color(0.58, 0.60, 0.64), Color(0.72, 0.70, 0.66), Color(0.5, 0.52, 0.56), Color(0.62, 0.55, 0.48)]
			_: palette = [Color(0.70, 0.66, 0.60), Color(0.62, 0.52, 0.44), Color(0.74, 0.72, 0.66), Color(0.58, 0.58, 0.56)]
		var placed := 0
		var tries := 0
		var used := {}
		while placed < n and tries < n * 6:
			tries += 1
			var gxi := rng.randi_range(-8, 8)
			var gzi := rng.randi_range(-8, 8)
			var key := gxi * 100 + gzi
			if used.has(key):
				continue
			var off := gx * (gxi * cell) + gz * (gzi * cell)
			# densità che cala dal centro della città, con un po' di rumore
			var dcen := off.length() / rc
			if dcen > 1.0 or rng.randf() < dcen * dcen * 0.9:
				continue
			var m := cc_map + off
			# fuori dal territorio, in mare, troppo vicino alle pedine o troppo in pendenza: niente
			if _tid(m.x, m.y) != i or _h(m.x, m.y) < 0.03 or _slope(m.x, m.y) > 0.07:
				continue
			if Vector2(m.x - float(t["x"]), m.y - float(t["y"])).length() < 12.5 * k:
				continue
			used[key] = true
			var tall := (1.0 - dcen) * (1.0 if urban else 0.55)
			var h := 0.06 + rng.randf() * (0.08 + 0.3 * tall)
			if urban and dcen < 0.35 and rng.randf() < 0.35:
				h += 0.18 + rng.randf() * 0.22   # grattacieli nel centro
			var w := cell * 0.1 * rng.randf_range(0.5, 0.86)
			var d := cell * 0.1 * rng.randf_range(0.5, 0.86)
			var industrial := (not urban and rng.randf() < 0.2) or (dcen > 0.75 and rng.randf() < 0.4)
			if industrial:
				h = 0.05 + rng.randf() * 0.04
				w = cell * 0.1 * 0.9
				d = cell * 0.1 * 0.7
			var pos := _ground(m.x, m.y)
			pos.y -= 0.01
			var b := Basis(Vector3.UP, -ga + (0.0 if rng.randf() < 0.9 else rng.randf_range(-0.3, 0.3))).scaled(Vector3(w, h, d))
			xf.append(Transform3D(b, pos))
			var col: Color = palette[rng.randi() % palette.size()]
			if industrial:
				col = Color(0.55, 0.58, 0.62).lerp(Color(0.62, 0.5, 0.42), rng.randf())
			col = col * rng.randf_range(0.88, 1.08)
			col.a = 1.0
			cols.append(col)
			cust.append(Color(rng.randf(), 0.12 + 0.3 * rng.randf(), 0.55 + 0.4 * rng.randf(), 1.0 if industrial else 0.0))
			placed += 1
	var mesh := _unit_box()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		mm.set_instance_color(k, cols[k])
		mm.set_instance_custom_data(k, cust[k])
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = load("res://scripts/map/city.gdshader")
	_city_mmi = MultiMeshInstance3D.new()
	_city_mmi.name = "Cities"
	_city_mmi.multimesh = mm
	_city_mmi.material_override = _city_mat
	_city_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_city_mmi.visibility_range_end = VIS_CITY
	_city_mmi.visibility_range_end_margin = 15.0
	_city_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_city_mmi)
	print("[MapDecor] città: ", xf.size(), " isolati in ", Time.get_ticks_msec() - t0, " ms")

## Parallelepipedo unitario con base in y = 0 (normali per faccia).
func _unit_box() -> ArrayMesh:
	var k := MapProps.Kit.new()
	k.box(Vector3(1, 1, 1), Vector3(0.5, 0.5, 0.5), Color.WHITE, Basis.IDENTITY, false, 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = k.v
	arrays[Mesh.ARRAY_NORMAL] = k.n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

# ====================================================================== strutture
## Firma dello stato che conta per le strutture del territorio.
func _struct_sig(game, i: int) -> String:
	var st: Dictionary = game.terr[i]
	var bl = st.get("buildings", [])
	var parts: PackedStringArray = PackedStringArray()
	if bl is Array:
		for b in bl:
			parts.append(String(b))
	var sig := ",".join(parts)
	var bp = st.get("building")
	if bp is Dictionary and bp.has("key"):
		sig += "|c:" + String(bp["key"])
	var f = st.get("fort")
	if f is Dictionary:
		sig += "|f:%d%d%d" % [int(f.get("trench", 0)), int(f.get("mines", 0)), int(f.get("bunker", 0))]
	var o := int(st["owner"])
	var hq := false
	for p in game.players:
		if int(p.get("hq", -1)) == i and bool(p.get("alive", true)) and int(p.get("idx", -1)) == o:
			hq = true
	if hq:
		sig += "|hq:" + wm._owner_color(o).to_html(false)
	if bl is Array and (bl as Array).has("caserma"):
		sig += "|o:" + wm._owner_color(o).to_html(false)
	return sig

func _rebuild_structures(game, i: int) -> void:
	var nd: Node3D = _terr_nodes[i]
	for c in nd.get_children():
		c.queue_free()
	_chimneys[i] = []
	var st: Dictionary = game.terr[i]
	var o := int(st["owner"])
	var col: Color = wm._owner_color(o)
	var k := _k[i]
	var ss := 0.72 + 0.28 * k
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + i
	var slot_i := 0
	var hq := false
	for p in game.players:
		if int(p.get("hq", -1)) == i and bool(p.get("alive", true)) and int(p.get("idx", -1)) == o:
			hq = true
	if hq:
		var sl: Dictionary = _slots[i][2]
		var n := MapProps.structure("hq", col, rng, VIS_STRUCT)
		n.position = sl["pos"] - _centers[i]
		n.rotation.y = -float(sl["ang"]) + PI / 2
		n.scale = Vector3.ONE * ss * 1.1
		nd.add_child(n)
		slot_i = 1   # il QG occupa il posto centrale: gli altri edifici si dispongono ai lati
	var bl = st.get("buildings", [])
	var keys: Array = []
	if bl is Array:
		for b in bl:
			keys.append(String(b))
	var bp = st.get("building")
	if bp is Dictionary and bp.has("key"):
		keys.append("scaffold")
	var order := [0, 4, 1, 3, 5, 2] if hq else [2, 1, 3, 0, 4, 5]
	var used_slots := {}
	if hq:
		used_slots[2] = true
	for key in keys:
		var n: Node3D
		if key == "porto" and not _coast[i].is_empty():
			var cst: Dictionary = _coast[i]
			n = MapProps.structure("porto", col, rng, VIS_STRUCT)
			n.position = cst["pos"] - _centers[i]
			var dir: Vector3 = cst["dir"]
			n.rotation.y = atan2(-dir.x, -dir.z)
			n.scale = Vector3.ONE * ss
			nd.add_child(n)
			continue
		var si := -1
		for cand in order:
			if not used_slots.has(cand):
				si = cand
				break
		if si < 0:
			break
		used_slots[si] = true
		var sl: Dictionary = _slots[i][si]
		n = MapProps.structure(key, col, rng, VIS_STRUCT)
		n.position = sl["pos"] - _centers[i]
		# l'ingresso (-Z) guarda il distintivo; la pista dell'aeroporto è tangente
		n.rotation.y = -float(sl["ang"]) + PI / 2 + (0.0 if key != "aeroporto" else 0.0)
		n.scale = Vector3.ONE * ss
		nd.add_child(n)
		for cp in MapProps.structure_smoke(key):
			_chimneys[i].append(n.position + n.basis * (cp as Vector3) + _centers[i])
	if OS.is_stdout_verbose() or wm._shot_arg("decor_debug") != "":
		print("[MapDecor] strutture ", D.TERRITORIES[i]["id"], " hq=", hq, " keys=", keys, " slots ok=", _slots[i].map(func(x): return x["ok"]), " coast=", not _coast[i].is_empty(), " k=", k)
	# fortificazioni a livelli attorno al distintivo
	var f = st.get("fort")
	if f is Dictionary:
		var tr := int(f.get("trench", 0))
		var mn := int(f.get("mines", 0))
		var bk := int(f.get("bunker", 0))
		if tr > 0 or mn > 0 or bk > 0:
			var fr := MapProps.fort_rings(tr, mn, bk, 1.95 * (0.8 + 0.2 * k), rng, VIS_STRUCT)
			fr.scale = Vector3.ONE * ss
			nd.add_child(fr)

# ====================================================================== fronte animato
## Punti di confine tra coppie di territori confinanti via terra, dal raster (uno ogni ~3 celle).
func _build_border_points() -> void:
	var W: int = data["w"]
	var H: int = data["h"]
	var tid: PackedInt32Array = data["tid"]
	var border: PackedByteArray = data["border"]
	var nbr: PackedByteArray = data["nbr"]
	var hh: PackedFloat32Array = data["height"]
	var S: int = data["s"]
	var tmp := {}
	for y in range(1, H - 1, 2):
		for x in range(1, W - 1, 2):
			var i := y * W + x
			var a := tid[i]
			if a < 0 or border[i] > 22:
				continue
			var b := int(nbr[i]) - 1
			if b < 0 or b == a:
				continue
			var key := "%d,%d" % [mini(a, b), maxi(a, b)]
			if not tmp.has(key):
				tmp[key] = []
			var mx := (x + 0.5) * S
			var my := (y + 0.5) * S
			var wp := Vector3(mx * wm.SCALE - wm.HALF.x, maxf(hh[i], 0.0), my * wm.SCALE - wm.HALF.y)
			(tmp[key] as Array).append(wp)
	var total := 0
	for key in tmp:
		var src: Array = tmp[key]
		var pts := PackedVector3Array()
		var nmax := 48
		if src.size() > nmax:
			for k in nmax:
				pts.append(src[int(float(k) / nmax * src.size())])
		else:
			for q in src:
				pts.append(q)
		_border_pts[key] = pts
		total += pts.size()
	print("[MapDecor] fronti: ", _border_pts.size(), " coppie, ", total, " punti")

func _specks_shader(additive: bool) -> Shader:
	var base := load("res://scripts/map/specks.gdshader") as Shader
	if additive:
		return base
	var s := Shader.new()
	s.code = base.code.replace("blend_add", "blend_mix")
	return s

func _build_specks() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	for additive in [true, false]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "SpecksAdd" if additive else "SpecksMix"
		mmi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = _specks_shader(additive)
		mat.render_priority = 3 if additive else 2
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-90, -2, -50), Vector3(180, 10, 100))
		add_child(mmi)
		if additive:
			_mm_add = mmi
			_specks_mat_add = mat
		else:
			_mm_mix = mmi
			_specks_mat_mix = mat

## Attacco tra due territori (chiamato da WorldMap su turn_arrow/divisioni): il fronte si scalda per un po'.
func note_attack(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= NT or to >= NT:
		return
	_pair_heat["%d,%d" % [mini(from, to), maxi(from, to)]] = _real_t
	_specks_sig = ""

## Territorio appena conquistato: fumo per qualche decina di secondi.
func note_capture(idx: int) -> void:
	if idx < 0 or idx >= NT:
		return
	_captures[idx] = _real_t
	_specks_sig = ""

## Calore attuale di una coppia (0..1): base per confine ostile + attacco recente + truppe ammassate.
func pair_heat(game, a: int, b: int) -> float:
	var key := "%d,%d" % [mini(a, b), maxi(a, b)]
	var h := 0.3
	if _pair_heat.has(key):
		var age := _real_t - float(_pair_heat[key])
		h += 0.7 * clampf(1.0 - age / 75.0, 0.0, 1.0)
	var units := Data.total_units(game.terr[a]["forces"]) + Data.total_units(game.terr[b]["forces"])
	h += 0.35 * clampf(float(units) / 28.0, 0.0, 1.0)
	return clampf(h, 0.0, 1.0)

## Coppia più calda tra quelle attive ([a, b] oppure [] se nessuna): per la telecamera delle demo.
func hottest_pair(game, pairs: Array) -> Array:
	var best: Array = []
	var bh := -1.0
	for pr in pairs:
		var key := "%d,%d" % [mini(int(pr[0]), int(pr[1])), maxi(int(pr[0]), int(pr[1]))]
		var npts: int = (_border_pts[key] as PackedVector3Array).size() if _border_pts.has(key) else 0
		# per la demo conta anche la lunghezza del confine (un istmo di due celle non si vede)
		var h := pair_heat(game, int(pr[0]), int(pr[1])) * (0.4 + 0.6 * clampf(npts / 24.0, 0.0, 1.0))
		if h > bh:
			bh = h
			best = [int(pr[0]), int(pr[1])]
	return best

## Calore per territorio (massimo sulle coppie attive), per la texture del terreno.
func terr_heat() -> PackedFloat32Array:
	return _terr_heat

## pairs: Array di [a, b] confini ostili (calcolati da WorldMap con nebbia e patti).
func _update_specks(game, pairs: Array, cam_dist: float) -> void:
	_specks_mat_add.set_shader_parameter("cam_dist", cam_dist)
	_specks_mat_mix.set_shader_parameter("cam_dist", cam_dist)
	var sig := PackedStringArray()
	var heats := {}
	_terr_heat.fill(0.0)
	for pr in pairs:
		var a := int(pr[0])
		var b := int(pr[1])
		var h := pair_heat(game, a, b)
		var key := "%d,%d" % [mini(a, b), maxi(a, b)]
		heats[key] = h
		_terr_heat[a] = maxf(_terr_heat[a], h)
		_terr_heat[b] = maxf(_terr_heat[b], h)
		sig.append("%s:%d" % [key, int(h * 6.0)])
	var caps: Array = []
	for idx in _captures.keys():
		var age := _real_t - float(_captures[idx])
		if age > CAPTURE_SMOKE_T:
			_captures.erase(idx)
			continue
		var h := clampf(1.0 - (age - CAPTURE_SMOKE_T * 0.6) / (CAPTURE_SMOKE_T * 0.4), 0.0, 1.0)
		caps.append([int(idx), h])
		sig.append("c%d:%d" % [int(idx), int(h * 4.0)])
	var chim := 0
	for i in NT:
		chim += (_chimneys[i] as Array).size()
	sig.append("ch%d" % chim)
	var s := ";".join(sig)
	if s == _specks_sig:
		return
	_specks_sig = s
	var add_xf: Array = []
	var add_c: Array = []
	var mix_xf: Array = []
	var mix_c: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	# fronte
	var budget := MAX_SPECKS
	for key in heats:
		var h: float = heats[key]
		if not _border_pts.has(key):
			continue
		var pts: PackedVector3Array = _border_pts[key]
		var n := mini(pts.size(), int(5 + 30 * h))
		for k in n:
			if budget <= 0:
				break
			var p: Vector3 = pts[int(float(k) / n * pts.size())]
			p += Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
			var seed := rng.randf()
			add_xf.append(Transform3D(Basis.IDENTITY, p))
			add_c.append(Color(rng.randf(), 0.0, h, seed))
			budget -= 1
			if rng.randf() < 0.45 * h + 0.15:
				mix_xf.append(Transform3D(Basis.IDENTITY, p))
				mix_c.append(Color(rng.randf(), 1.0, h, rng.randf()))
				budget -= 1
			if rng.randf() < 0.12 + 0.25 * h:
				add_xf.append(Transform3D(Basis.IDENTITY, p))
				add_c.append(Color(rng.randf(), 2.0, h, rng.randf()))
				budget -= 1
	# conquiste
	for cp in caps:
		var i: int = cp[0]
		var h: float = cp[1]
		var c: Vector3 = _centers[i]
		for k in 9:
			var a := rng.randf() * TAU
			var r := rng.randf() * 1.1 * _k[i]
			mix_xf.append(Transform3D(Basis.IDENTITY, c + Vector3(cos(a) * r, 0.0, sin(a) * r)))
			mix_c.append(Color(rng.randf(), 4.0, h, rng.randf()))
		for k in 4:
			var a := rng.randf() * TAU
			var r := rng.randf() * 0.9 * _k[i]
			add_xf.append(Transform3D(Basis.IDENTITY, c + Vector3(cos(a) * r, 0.0, sin(a) * r)))
			add_c.append(Color(rng.randf(), 0.0, h * 0.8, rng.randf()))
	# ciminiere
	for i in NT:
		for cp in _chimneys[i]:
			for k in 2:
				mix_xf.append(Transform3D(Basis.IDENTITY, cp))
				mix_c.append(Color(rng.randf(), 3.0, 0.6, rng.randf()))
	_fill_mm(_mm_add.multimesh, add_xf, add_c)
	_fill_mm(_mm_mix.multimesh, mix_xf, mix_c)

func _fill_mm(mm: MultiMesh, xf: Array, cust: Array) -> void:
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		mm.set_instance_custom_data(k, cust[k])

# ====================================================================== aggiornamento
## Chiamato da WorldMap a ogni fotogramma. `vis`: visibilità per territorio (nebbia); `pairs`: confini ostili [a, b].
func update(game, vis: Array, pairs: Array, cam_dist: float, real_t: float, delta: float) -> void:
	_real_t = real_t
	_acc += delta
	if game == null:
		return
	var full := _acc > 0.25
	if full:
		_acc = 0.0
	for i in NT:
		var nd: Node3D = _terr_nodes[i]
		if full:
			var sig := _struct_sig(game, i)
			if sig != _terr_sig[i]:
				_terr_sig[i] = sig
				_rebuild_structures(game, i)
				_specks_sig = ""
		nd.visible = bool(vis[i]) if i < vis.size() else true
	if full or _specks_sig == "":
		_update_specks(game, pairs, cam_dist)
	else:
		_specks_mat_add.set_shader_parameter("cam_dist", cam_dist)
		_specks_mat_mix.set_shader_parameter("cam_dist", cam_dist)

## Statistiche per il resoconto.
func stats() -> Dictionary:
	var ns := 0
	for nd in _terr_nodes:
		ns += (nd as Node).get_child_count()
	return {"cities": _city_mmi.multimesh.instance_count if _city_mmi else 0, "structures": ns,
		"specks": (_mm_add.multimesh.instance_count + _mm_mix.multimesh.instance_count) if _mm_add else 0}
