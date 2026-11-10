class_name BattleMarks
extends Node3D
## Fase 8 — segni persistenti della battaglia e distruzione dell'ambiente (vista).
## - Solchi dei cingoli/ruote dipinti a runtime in una texture (canali: r terra smossa, g fango/neve pressata) letta dallo
##   shader del suolo (`track_tex`); fango con la pioggia, neve sollevata nell'artico (particelle in BattleFx).
## - Crateri veri nella mesh (terrain.deform_crater) con coda e budget (uno ogni 0,12 s) + bruciatura (paint_crater).
## - Edifici che si degradano a stadi (crepe/annerimento → crollo parziale → macerie) con polvere e detriti; le macerie
##   restano e diventano copertura pesante nella sim (`sim.add_rubble`). Alberi abbattuti dai mezzi e dalle esplosioni
##   (animazione di caduta, restano a terra), staccionate e siepi schiacciate dai mezzi.
## Lavora sui MultiMesh già creati da BattleTerrain (indice spaziale costruito all'avvio): nessun nodo per albero.

const TRACK_RES := 0.25          # m per texel della texture dei solchi
const CELL := 12.0               # m: cella dell'indice spaziale dei distruttibili
const CRATER_GAP := 0.12         # s tra due deformazioni del suolo
const TREE_FALL_T := 1.5
const HP := {"house": 2.4, "barn": 2.8, "chalet": 2.2, "hut": 1.3, "silo": 2.0, "ruin": 1.2}

var battle                       # Battle3D
var terrain                      # BattleTerrain
var sim
var fx                           # BattleFx
var weather                      # BattleWeather (bagnato/neve)
var track_img: Image
var track_tex: ImageTexture
var _track_dirty := false
var _track_t := 0.0
var _tw := 0
var _th := 0
var _craters: Array = []         # coda [x, y, r_px, depth]
var _crater_t := 0.0
var _cells := {}                 # Vector2i -> Array[item]
var items: Array = []            # distruttibili {mm, i, kind, p, xf, hp, hp0, stage, col, size, alive, h}
var _falling: Array = []         # alberi in caduta {it, axis, t, T, ang}
var fires: Array = []            # focolai {p, until, s} (macerie fumanti) — anche per l'audio
var smokers: Array = []          # edifici danneggiati che fumano {p, until}
var _smk_t := 0.0
var _veh_t := 0.0
var _vpos := {}                  # id -> Vector3 ultima posizione per i solchi
var _rubble_mesh := {}
var stats := {"craters": 0, "trees": 0, "buildings": 0, "collapsed": 0, "stamps": 0}
var _rng := RandomNumberGenerator.new()
var enabled := true
var _silent := false              # avanzamento rapido: niente particelle per i danni applicati

func setup(b, w) -> void:
	battle = b
	terrain = b.terrain
	sim = b.sim
	fx = b.fx
	weather = w
	_rng.seed = int(sim.seed_) * 5 + 9
	_tw = int(BattleTerrain.FIELD_HX * 2.0 / TRACK_RES)
	_th = int(BattleTerrain.FIELD_HZ * 2.0 / TRACK_RES)
	track_img = Image.create(_tw, _th, false, Image.FORMAT_RG8)
	track_img.fill(Color(0, 0, 0))
	track_tex = ImageTexture.create_from_image(track_img)
	terrain.terrain_mat.set_shader_parameter("track_tex", track_tex)
	terrain.terrain_mat.set_shader_parameter("track_on", 1.0)
	var t0 := Time.get_ticks_usec()
	_build_index()
	if battle._demo:
		print("[marks] distruttibili indicizzati: %d in %.1f ms" % [items.size(), (Time.get_ticks_usec() - t0) / 1000.0])

# ---------------------------------------------------------------------------- indice dei distruttibili
func _build_index() -> void:
	var hx := BattleTerrain.FIELD_HX + 40.0
	var hz := BattleTerrain.FIELD_HZ + 40.0
	var wood_nodes := {}
	for w in terrain.woods:
		for n in w["nodes"]:
			wood_nodes[n] = true
	var lm_sizes := {}
	for lm in terrain.landmarks:
		var k := String(lm["kind"])
		if not lm_sizes.has(k):
			lm_sizes[k] = []
		lm_sizes[k].append([lm["pos"], lm["size"]])
	for ch in terrain.get_children():
		if not (ch is MultiMeshInstance3D):
			continue
		var mi := ch as MultiMeshInstance3D
		var mm := mi.multimesh
		if mm == null or mm.mesh == null:
			continue
		var kind := ""
		var nm := String(mi.name)
		if nm.begins_with("LM_"):
			var lk := nm.substr(3)
			if HP.has(lk):
				kind = "bld"
			elif lk == "fence":
				kind = "fence"
			else:
				continue
		elif mm in terrain.grass_mms:
			continue
		elif mm in terrain.deco_mms:
			kind = "bush"
		elif mm.mesh is BoxMesh and mm.use_custom_data:
			kind = "city"
		elif wood_nodes.has(mi) or (mm.use_colors and mm.mesh.get_aabb().size.y > 4.0):
			kind = "tree"
		else:
			continue
		var lk2 := nm.substr(3) if kind == "bld" else ""
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var p := xf.origin
			if absf(p.x) > hx or absf(p.z) > hz:
				continue
			if xf.basis.get_scale().length() < 0.01:
				continue
			var it := {"mm": mm, "i": i, "kind": kind, "p": p, "xf": xf, "stage": 0, "alive": true, "hp": 1.0, "hp0": 1.0,
				"col": mm.get_instance_color(i) if mm.use_colors else Color(1, 1, 1), "size": Vector3.ZERO, "lk": lk2, "h": mm.mesh.get_aabb().size.y * xf.basis.get_scale().y}
			match kind:
				"bld":
					it["hp"] = float(HP[lk2]); it["hp0"] = it["hp"]
					it["size"] = Vector3(10, 7, 8)
					for e in lm_sizes.get(lk2, []):
						if (e[0] as Vector3).distance_squared_to(p) < 4.0:
							it["size"] = e[1]
							break
				"city":
					var sz := xf.basis.get_scale()
					it["size"] = sz
					it["hp"] = 2.4 + sz.y * 0.06 + (sz.x + sz.z) * 0.03; it["hp0"] = it["hp"]
					it["cus"] = mm.get_instance_custom_data(i)
				"tree":
					it["hp"] = 0.6
				_:
					it["hp"] = 0.2
			items.append(it)
			var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
			if not _cells.has(key):
				_cells[key] = []
			_cells[key].append(it)

func _near(p: Vector3, r: float) -> Array:
	var out := []
	var c0 := Vector2i(int(floor((p.x - r) / CELL)), int(floor((p.z - r) / CELL)))
	var c1 := Vector2i(int(floor((p.x + r) / CELL)), int(floor((p.z + r) / CELL)))
	var r2 := r * r
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var lst = _cells.get(Vector2i(cx, cz))
			if lst == null:
				continue
			for it in lst:
				if not it["alive"]:
					continue
				var q: Vector3 = it["p"]
				var dx := q.x - p.x
				var dz := q.z - p.z
				if dx * dx + dz * dz <= r2:
					out.append(it)
	return out

# ---------------------------------------------------------------------------- ciclo
func update(dt: float, frozen: bool) -> void:
	if not enabled:
		return
	_track_t -= dt
	if _track_dirty and _track_t <= 0.0:
		_track_t = 0.25
		_track_dirty = false
		track_tex.update(track_img)
	_crater_t -= dt
	if not _craters.is_empty() and _crater_t <= 0.0:
		_crater_t = CRATER_GAP
		var c: Array = _craters.pop_front()
		terrain.deform_crater(c[0], c[1], c[2], c[3])
		stats["craters"] += 1
	if frozen:
		return
	_update_falling(dt)
	_veh_t -= dt
	if _veh_t <= 0.0:
		_veh_t = 0.2
		_vehicles()
	# fumo dagli edifici danneggiati e dalle macerie
	_smk_t -= dt
	if _smk_t <= 0.0:
		_smk_t = 0.25
		var now: float = battle._wall_time
		var i := 0
		while i < smokers.size():
			var s: Dictionary = smokers[i]
			if now > float(s["until"]):
				smokers.remove_at(i)
				continue
			if _rng.randf() < 0.6:
				fx.burn(s["p"], 0.35)
			i += 1
		i = 0
		while i < fires.size():
			var f: Dictionary = fires[i]
			if now > float(f["until"]):
				fires.remove_at(i)
				continue
			var left: float = float(f["until"]) - now
			fx.burn((f["p"] as Vector3) + Vector3(_rng.randf_range(-2, 2), 0.4, _rng.randf_range(-2, 2)), clampf(0.6 + left / 60.0, 0.4, 1.0) * float(f["s"]))
			if left > 20.0 and _rng.randf() < 0.5:
				fx.light((f["p"] as Vector3) + Vector3(0, 2.5, 0), 1.6, 12.0, 0.3)
			i += 1

## Solchi e abbattimenti dei mezzi in movimento (ogni 0,2 s): legge le posizioni dalla vista (`battle.views`).
func _vehicles() -> void:
	var wet := 0.0
	var snw := 0.0
	if weather != null:
		wet = float(weather.wetness)
		snw = float(weather.snow_cover)
	var cam_p: Vector3 = battle.cam.global_position
	for id in battle.views:
		var v: Dictionary = battle.views[id]
		var u = v["u"]
		if u.dead or u.air or u.stat or u.type == "inf":
			continue
		var p: Vector3 = v["pos"]
		var prev = _vpos.get(id)
		_vpos[id] = p
		if prev == null:
			continue
		var d := Vector2(p.x - (prev as Vector3).x, p.z - (prev as Vector3).z)
		var L := d.length()
		if L < 0.05:
			continue
		var dir := d / L
		var side := Vector2(-dir.y, dir.x)
		var halfw: float = clampf(float(u.r) * BattleTerrain.S * 0.36, 1.0, 2.1)
		var heavy: bool = u.type in ["tank", "art", "aa"]
		var surf := ""
		var near_cam := p.distance_squared_to(cam_p) < 260.0 * 260.0
		if near_cam:
			surf = terrain.surface_at(p.x, p.z)
		var muddy := wet > 0.4 or surf == "mud"
		var snowy := snw > 0.4 or surf == "snow"
		# passi di 0,45 m lungo il tratto percorso
		var n := int(ceil(L / 0.45))
		n = mini(n, 12)
		for k in n:
			var f := (k + 0.5) / n
			var q := Vector2(prev.x, prev.z).lerp(Vector2(p.x, p.z), f)
			for sg in [-1.0, 1.0]:
				var tp: Vector2 = q + side * halfw * float(sg)
				_stamp(tp.x, tp.y, 0.75 if heavy else 0.5, 1.0 if (muddy or snowy) else 0.0, heavy)
		stats["stamps"] += n
		# schizzi di fango / neve sollevata dietro i cingoli (vicino alla telecamera)
		if near_cam and (muddy or snowy) and L > 0.6:
			var back := p - Vector3(dir.x, 0, dir.y) * halfw * 1.8
			if snowy:
				fx.snow_spray(back + Vector3(0, 0.3, 0), 0.8 + L)
			else:
				fx.mud_splash(back + Vector3(0, 0.2, 0), 0.7 + L * 0.6)
		# alberi, siepi e staccionate travolti
		var rr := halfw * 1.25 + 0.5
		for it in _near(p, rr + 2.0):
			var kind: String = it["kind"]
			if kind == "tree":
				if heavy and (it["p"] as Vector3).distance_squared_to(p) < (rr + 0.6) * (rr + 0.6):
					_fell_tree(it, Vector2(dir.x, dir.y))
			elif kind == "bush" or kind == "fence":
				if (it["p"] as Vector3).distance_squared_to(p) < (rr + 1.0) * (rr + 1.0):
					_flatten(it)

func _stamp(X: float, Z: float, v: float, g: float, heavy: bool) -> void:
	var px := int((X + BattleTerrain.FIELD_HX) / TRACK_RES)
	var py := int((Z + BattleTerrain.FIELD_HZ) / TRACK_RES)
	if px < 1 or py < 1 or px >= _tw - 1 or py >= _th - 1:
		return
	var w := 2 if heavy else 1
	for j in range(py - (1 if heavy else 0), py + w):
		for i in range(px - (1 if heavy else 0), px + w):
			var old := track_img.get_pixel(i, j)
			track_img.set_pixel(i, j, Color(minf(1.0, old.r + v * 0.5), minf(1.0, old.g + g * 0.6), 0))
	_track_dirty = true

# ---------------------------------------------------------------------------- crateri
## Cratere vero (coordinate sim, raggio px, profondità m) + bruciatura: in coda, uno ogni CRATER_GAP s.
func crater(x: float, y: float, r_px: float, depth: float) -> void:
	if not enabled:
		return
	if _craters.size() < 40:
		_craters.append([x, y, r_px, depth])

# ---------------------------------------------------------------------------- danni dalle esplosioni
## Esplosione in `p` (mondo) di raggio `r` m e forza `dmg` (1 = colpo d'artiglieria): edifici, alberi, recinzioni.
func blast(p: Vector3, r: float, dmg: float, silent := false) -> void:
	if not enabled:
		return
	_silent = silent
	for it in _near(p, r + 6.0):
		var q: Vector3 = it["p"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		match String(it["kind"]):
			"tree":
				if d < r * 1.1 + 1.0 and _rng.randf() < 0.85:
					var away := Vector2(q.x - p.x, q.z - p.z)
					if away.length() < 0.1:
						away = Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5)
					_fell_tree(it, away.normalized())
			"bush", "fence":
				if d < r * 1.2 + 0.5:
					_flatten(it)
			"bld", "city":
				var reach: float = maxf(it["size"].x, it["size"].z) * 0.5 + r
				if d < reach:
					var k := clampf(1.0 - (d - reach * 0.4) / maxf(reach * 0.6, 0.1), 0.35, 1.0)
					_damage(it, dmg * k)

func _damage(it: Dictionary, dmg: float) -> void:
	if not it["alive"]:
		return
	it["hp"] = float(it["hp"]) - dmg
	var f: float = float(it["hp"]) / float(it["hp0"])
	var want := 0
	if float(it["hp"]) <= 0.0:
		want = 3
	elif f < 0.38:
		want = 2
	elif f < 0.72:
		want = 1
	while int(it["stage"]) < want:
		it["stage"] = int(it["stage"]) + 1
		_apply_stage(it)

func _apply_stage(it: Dictionary) -> void:
	var mm: MultiMesh = it["mm"]
	var i: int = it["i"]
	var xf: Transform3D = it["xf"]
	var col: Color = it["col"]
	var p: Vector3 = it["p"]
	var size: Vector3 = it["size"]
	var city: bool = it["kind"] == "city"
	var now: float = battle._wall_time
	var top := p + Vector3(0, size.y * (0.5 if city else 0.6), 0)
	match int(it["stage"]):
		1:
			stats["buildings"] += 1
			if mm.use_colors:
				mm.set_instance_color(i, col * Color(0.7, 0.66, 0.62))
			smokers.append({"p": top, "until": now + 40.0})
			if not _silent:
				fx.collapse(p + Vector3(0, size.y * 0.5, 0), size * 0.35, col)
		2:
			var b := xf.basis
			var tilt := Basis(Vector3(_rng.randf() - 0.5, 0, _rng.randf() - 0.5).normalized(), 0.07)
			if city:
				var sz := b.get_scale()
				var cus: Color = it.get("cus", Color(0, sz.y, 0, 0))
				var gy := float(cus.r)
				var ny := sz.y * 0.62
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sz.x, ny, sz.z)), Vector3(p.x, gy + ny * 0.5, p.z)))
				mm.set_instance_custom_data(i, Color(gy, gy + ny, cus.b, cus.a))
				mm.set_instance_color(i, col * Color(0.55, 0.52, 0.5))
			else:
				var nb := tilt * b
				nb = nb.scaled_local(Vector3(1.0, 0.72, 1.0))
				mm.set_instance_transform(i, Transform3D(nb, p - Vector3(0, 0.15, 0)))
				if mm.use_colors:
					mm.set_instance_color(i, col * Color(0.55, 0.5, 0.47))
			smokers.append({"p": top - Vector3(0, size.y * 0.25, 0), "until": now + 50.0})
			if not _silent:
				fx.collapse(p + Vector3(0, size.y * 0.3, 0), size * 0.7, col)
				battle._shake(p, 0.5)
		3:
			stats["collapsed"] += 1
			if city:
				var sz := xf.basis.get_scale()
				var cus: Color = it.get("cus", Color(0, sz.y, 0, 0))
				var gy := float(cus.r)
				var ny := maxf(2.0, sz.y * 0.2)
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sz.x * 1.08, ny, sz.z * 1.08)), Vector3(p.x, gy + ny * 0.5, p.z)))
				mm.set_instance_custom_data(i, Color(gy, gy + ny, 2.0, cus.a))
				mm.set_instance_color(i, col * Color(0.42, 0.4, 0.38))
			else:
				mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), p - Vector3(0, 50, 0)))
				_add_rubble(p, size, xf.basis.get_rotation_quaternion().get_euler().y, col)
			if not _silent:
				fx.collapse(p + Vector3(0, size.y * 0.2, 0), size, col)
				fx.light(p + Vector3(0, 3, 0), 3.0, 18.0, 0.25)
				battle._shake(p, 0.9)
			it["alive"] = false
			# copertura pesante per la fanteria tra le macerie (solo in campo)
			if absf(p.x) < BattleTerrain.FIELD_HX and absf(p.z) < BattleTerrain.FIELD_HZ and sim.has_method("add_rubble"):
				var sp := BattleTerrain.world_to_sim(p.x, p.z)
				sim.add_rubble(sp.x, sp.y, maxf(size.x, size.z) * 0.5 / BattleTerrain.S)
			if _rng.randf() < 0.6:
				fires.append({"p": p + Vector3(0, 0.8, 0), "until": now + 60.0 + _rng.randf() * 40.0, "s": clampf(size.x / 10.0, 0.6, 1.4)})

func _rubble(kind_size: int) -> Mesh:
	if _rubble_mesh.has(kind_size):
		return _rubble_mesh[kind_size]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 77 + kind_size
	var n := 10 + kind_size * 4
	for k in n:
		var a := r.randf() * TAU
		var rr := sqrt(r.randf()) * 0.5
		var c := Vector3(cos(a) * rr, r.randf_range(0.05, 0.22) * (1.0 - rr * 0.8), sin(a) * rr)
		var s := Vector3(r.randf_range(0.12, 0.34), r.randf_range(0.08, 0.26), r.randf_range(0.12, 0.3))
		var g := r.randf_range(0.42, 0.68)
		var col := Color(g * 1.05, g * 0.98, g * 0.9) if r.randf() < 0.7 else Color(0.52, 0.3, 0.22) * r.randf_range(0.8, 1.1)
		var b := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, r.randf_range(-0.5, 0.5))
		_box(st, c, s, col, b)
	# cumulo centrale
	_box(st, Vector3(0, 0.12, 0), Vector3(0.7, 0.24, 0.6), Color(0.5, 0.47, 0.42), Basis(Vector3.UP, 0.4))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	_rubble_mesh[kind_size] = mesh
	return mesh

static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b: Basis) -> void:
	var h := s * 0.5
	var P := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var F := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in F:
		var q := []
		for k in 4:
			q.append(c + b * P[f[k]])
		var shade := 0.85 + 0.15 * randf()
		st.set_color(col * shade)
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.add_vertex(q[k])

func _add_rubble(p: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var ks := clampi(int((size.x + size.z) / 8.0), 0, 3)
	mi.mesh = _rubble(ks)
	var gy: float = terrain.height(p.x, p.z)
	mi.position = Vector3(p.x, gy - 0.05, p.z)
	mi.basis = Basis(Vector3.UP, yaw).scaled(Vector3(size.x * 1.15, clampf(size.y * 0.3, 1.2, 3.2), size.z * 1.15))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	# bruciatura attorno
	var sp := BattleTerrain.world_to_sim(p.x, p.z)
	terrain.paint_crater(sp.x, sp.y, maxf(size.x, size.z) * 0.5 / BattleTerrain.S * 0.9)

# ---------------------------------------------------------------------------- alberi, siepi, staccionate
func _fell_tree(it: Dictionary, dir: Vector2) -> void:
	if not it["alive"]:
		return
	it["alive"] = false
	stats["trees"] += 1
	var d3 := Vector3(dir.x, 0, dir.y).normalized()
	var axis := d3.cross(Vector3.UP).normalized()   # ruota attorno all'asse orizzontale perpendicolare alla direzione
	if axis.length() < 0.5:
		axis = Vector3.RIGHT
	if _silent:
		_set_tree_angle(it, -axis, 1.45, true)
		return
	_falling.append({"it": it, "axis": -axis, "t": 0.0, "T": TREE_FALL_T * _rng.randf_range(0.85, 1.15), "ang": 0.0})
	if _falling.size() > 60:
		var old: Dictionary = _falling.pop_front()
		_set_tree_angle(old["it"], old["axis"], 1.45, true)
	fx.tree_fall(it["p"], 1.0)

func _set_tree_angle(it: Dictionary, axis: Vector3, ang: float, final: bool) -> void:
	var mm: MultiMesh = it["mm"]
	var xf: Transform3D = it["xf"]
	var b := Basis(axis, ang) * xf.basis
	var p: Vector3 = xf.origin
	if final:
		p.y -= 0.35
	mm.set_instance_transform(int(it["i"]), Transform3D(b, p))

func _update_falling(dt: float) -> void:
	var i := 0
	while i < _falling.size():
		var f: Dictionary = _falling[i]
		f["t"] = float(f["t"]) + dt
		var k: float = clampf(float(f["t"]) / float(f["T"]), 0.0, 1.0)
		var ang := 1.45 * k * k
		if k >= 1.0:
			_set_tree_angle(f["it"], f["axis"], 1.45, true)
			var p: Vector3 = f["it"]["p"]
			fx.dust(p + Vector3(f["axis"].z, 0.2, -f["axis"].x) * 4.0, 1.4)
			_falling.remove_at(i)
			continue
		_set_tree_angle(f["it"], f["axis"], ang, false)
		i += 1

func _flatten(it: Dictionary) -> void:
	if not it["alive"]:
		return
	it["alive"] = false
	var mm: MultiMesh = it["mm"]
	var xf: Transform3D = it["xf"]
	var b := xf.basis
	if it["kind"] == "fence":
		b = Basis(b.z.normalized(), 1.25 * (1.0 if _rng.randf() < 0.5 else -1.0)) * b
		mm.set_instance_transform(int(it["i"]), Transform3D(b, xf.origin - Vector3(0, 0.1, 0)))
	else:
		mm.set_instance_transform(int(it["i"]), Transform3D(b.scaled_local(Vector3(1.15, 0.28, 1.15)), xf.origin - Vector3(0, 0.05, 0)))
	if not _silent:
		fx.dust(xf.origin + Vector3(0, 0.3, 0), 0.8)
