class_name BattleStrategic
extends RefCounted
## Vista strategica della battaglia (zoom continuo, stile plancia di comando). Solo vista: legge la simulazione, non la cambia.
## - `k` (0..1): quanto la telecamera è "alta"; guida tutte le dissolvenze (velatura del fronte, frecce, obiettivi, pedine).
## - Mappa d'influenza 48×27 sul campo (R attaccante, G difensore), aggiornata 2 volte al secondo dalle posizioni note
##   (proprie sempre, nemiche solo se avvistate); lo shader del terreno la sfuma e disegna la linea del fronte.
## - Frecce di movimento: unità raggruppate per lato e destinazione dell'ordine.
## - Obiettivi: bunker, ponti, guadi e alture, colorati secondo chi li controlla.

const GW := 48
const GH := 27
const K_START := 380.0     # distanza della telecamera (m) da cui inizia la vista strategica
const K_FULL := 640.0

var b                      # Battle3D
var k := 0.0
var img: Image
var tex: ImageTexture
var inf_a := PackedFloat32Array()
var inf_d := PackedFloat32Array()
var arrows: Array = []     # [{side, from: Vector3, to: Vector3, n, own}]
var objectives: Array = [] # [{kind, name, pos: Vector3, x, y (px sim), owner: -1|0|1}]
var _t := 0.0

func _init(battle) -> void:
	b = battle
	img = Image.create(GW, GH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tex = ImageTexture.create_from_image(img)
	inf_a.resize(GW * GH)
	inf_d.resize(GW * GH)
	_find_objectives()
	var m: ShaderMaterial = b.terrain.terrain_mat
	m.set_shader_parameter("front_tex", tex)
	m.set_shader_parameter("front_k", 0.0)
	m.set_shader_parameter("front_col_a", b.side_color(0))
	m.set_shader_parameter("front_col_d", b.side_color(1))

func update(dt: float, cam_dist: float) -> void:
	var nk := smoothstep(K_START, K_FULL, cam_dist)
	if absf(nk - k) > 0.001:
		k = nk
		b.terrain.terrain_mat.set_shader_parameter("front_k", k)
	if k <= 0.001:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		_update_influence()
		_update_objectives()
	_update_arrows()

# ---------------------------------------------------------------------------- influenza e fronte
func _update_influence() -> void:
	var sim = b.sim
	inf_a.fill(0.0)
	inf_d.fill(0.0)
	for u in sim.units:
		if u.dead or u.air:
			continue
		if not b.is_visible_unit(u):
			continue
		var gx := clampi(int(u.x / sim.W * GW), 0, GW - 1)
		var gy := clampi(int(u.y / sim.H * GH), 0, GH - 1)
		var w := clampf(u.hp / u.hp_max, 0.3, 1.0) * (2.5 if u.stat else 1.0)
		var arr := inf_a if u.side == 0 else inf_d
		# 3×3 con peso al centro: lo shader completa la sfumatura
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var cx := gx + ox
				var cy := gy + oy
				if cx < 0 or cy < 0 or cx >= GW or cy >= GH:
					continue
				arr[cy * GW + cx] += w * (1.0 if ox == 0 and oy == 0 else 0.4)
	for i in GW * GH:
		img.set_pixel(i % GW, i / GW, Color(clampf(inf_a[i] / 3.0, 0.0, 1.0), clampf(inf_d[i] / 3.0, 0.0, 1.0), 0.0, 1.0))
	tex.update(img)

## Lato che controlla il punto (px sim): -1 conteso/nessuno.
func owner_at(x: float, y: float) -> int:
	var gx := clampi(int(x / b.sim.W * GW), 0, GW - 1)
	var gy := clampi(int(y / b.sim.H * GH), 0, GH - 1)
	var a := 0.0
	var d := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var cx := gx + ox
			var cy := gy + oy
			if cx < 0 or cy < 0 or cx >= GW or cy >= GH:
				continue
			a += inf_a[cy * GW + cx]
			d += inf_d[cy * GW + cx]
	if a + d < 0.5:
		return -1
	if a > d * 1.6:
		return 0
	if d > a * 1.6:
		return 1
	return -1

# ---------------------------------------------------------------------------- obiettivi
func _find_objectives() -> void:
	var sim = b.sim
	# obiettivi veri della simulazione (docs/omogeneita.md §1): le bandierine seguono chi li tiene davvero
	if "objectives" in sim and not sim.objectives.is_empty():
		for o in sim.objectives:
			var w := BattleTerrain.sim_to_world(float(o["x"]), float(o["y"]))
			objectives.append({"kind": String(o["kind"]), "name": String(o["name"]), "x": float(o["x"]), "y": float(o["y"]), "owner": int(o["owner"]),
				"pos": Vector3(w.x, b.terrain.height(w.x, w.y) + 2.0, w.y), "sim": o})
		return
	for bp in sim.bunker_pos:
		_obj("bunker", "Bunker", bp.x, bp.y)
	if sim.relief != null:
		for rv in sim.relief.rivers:
			for xg in rv.get("xings", []):
				_obj(String(xg["k"]), "Ponte" if xg["k"] == "bridge" else "Guado", float(xg["x"]), float(xg["y"]))
	# alture: le due quote più alte dentro il campo, distanti tra loro
	var best := []
	for j in range(2, 14):
		for i in range(2, 30):
			var x: float = sim.W * i / 32.0
			var y: float = sim.TOP + (sim.BOTTOM - sim.TOP) * j / 16.0
			var w := BattleTerrain.sim_to_world(x, y)
			best.append([b.terrain.height(w.x, w.y), x, y])
	best.sort_custom(func(p, q): return p[0] > q[0])
	var taken := 0
	for c in best:
		if taken >= 2 or float(c[0]) < 6.0:
			break
		var far_ok := true
		for o in objectives:
			if Vector2(o["x"], o["y"]).distance_to(Vector2(c[1], c[2])) < sim.W * 0.2:
				far_ok = false
		if far_ok:
			_obj("hill", "Quota %d" % int(round(float(c[0]) + 100.0)), c[1], c[2])
			taken += 1

func _obj(kind: String, name: String, x: float, y: float) -> void:
	var w := BattleTerrain.sim_to_world(x, y)
	objectives.append({"kind": kind, "name": name, "x": x, "y": y, "owner": -1,
		"pos": Vector3(w.x, b.terrain.height(w.x, w.y) + 2.0, w.y)})

func _update_objectives() -> void:
	for o in objectives:
		if o.has("sim"):
			o["owner"] = int(o["sim"]["owner"])
		else:
			o["owner"] = owner_at(o["x"], o["y"])

# ---------------------------------------------------------------------------- frecce di movimento
func _update_arrows() -> void:
	arrows.clear()
	var sim = b.sim
	var groups := {}
	var Q: float = 640.0   # px sim (~160 m): destinazioni vicine = stesso gruppo
	for u in sim.units:
		if u.dead or u.stat or u.air:
			continue
		var dx: float
		var dy: float
		if u.order == BattleSim.MOVE or u.order == BattleSim.AMOVE:
			dx = u.ox; dy = u.oy
		elif u.order == BattleSim.ATTACK and u.otgt != null and not u.otgt.dead:
			dx = u.otgt.x; dy = u.otgt.y
		else:
			continue
		if Vector2(dx - u.x, dy - u.y).length() < 160.0:
			continue
		if not b.is_visible_unit(u):
			continue
		# stesso lato, destinazione e partenza vicine (le partenze lontane fanno frecce diverse)
		var key := "%d_%d_%d_%d_%d_%d" % [u.side, int(dx / Q), int(dy / Q), int(u.x / (Q * 1.5)), int(u.y / (Q * 1.5)), 0 if u.order == BattleSim.MOVE else 1]
		if not groups.has(key):
			groups[key] = {"side": u.side, "sx": 0.0, "sy": 0.0, "dx": 0.0, "dy": 0.0, "n": 0, "atk": u.order != BattleSim.MOVE}
		var g: Dictionary = groups[key]
		g["sx"] += u.x; g["sy"] += u.y; g["dx"] += dx; g["dy"] += dy; g["n"] += 1
	for key in groups:
		var g: Dictionary = groups[key]
		var n: int = g["n"]
		if n < 2:
			continue   # unità isolate: niente freccia (la linea d'ordine dei selezionati basta)
		var f := BattleTerrain.sim_to_world(g["sx"] / n, g["sy"] / n)
		var t := BattleTerrain.sim_to_world(g["dx"] / n, g["dy"] / n)
		arrows.append({"side": g["side"], "n": n, "atk": g["atk"], "own": sim.hs < 0 or g["side"] == sim.hs,
			"from": Vector3(f.x, b.terrain.height(f.x, f.y) + 1.0, f.y), "to": Vector3(t.x, b.terrain.height(t.x, t.y) + 1.0, t.y)})
