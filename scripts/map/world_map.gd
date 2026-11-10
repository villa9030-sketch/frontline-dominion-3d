class_name WorldMap
extends Node3D
## FRONTLINE DOMINION 3D — tabellone strategico (Agente D).
## Plastico del mondo generato dai blobs_px dei territori (MapGen), oceano, nuvole, boschi in miniatura, pedine 3D,
## divisioni in viaggio, effetti, telecamera RTS con volo morbido e picking.
## Livelli di dettaglio per zoom:
##   lontano  → solo distintivi compatti (numero + colore) a dimensione costante, sfoltiti senza sovrapposizioni,
##              etichette dei continenti, fronti; niente miniature;
##   medio    → miniature (1 pezzo per tipo prevalente), nomi piazzati senza collisioni, sigle degli edifici;
##   vicino   → miniature 1–3 pezzi secondo la forza, edifici 3D, boschi, segnali testuali.
## NON chiama comandi di gioco: emette segnali che l'interfaccia (E) gestisce.

signal territory_clicked(idx: int, button: int, shift: bool)
signal territory_hovered(idx: int)
signal drag_released(from_idx: int, to_idx: int)

const D = preload("res://scripts/core/data.gd")
const SCALE := 0.1
const HALF := Vector2(80.0, 45.0)
const NT := 42
const DRAG_PX := 8.0
const DIST_FAR := 74.0      # oltre: niente miniature
const DIST_NEAR := 34.0     # sotto: dettaglio pieno
## posizioni (piano mappa) delle etichette dei continenti, in mare accanto alla costa
const CONT_LABEL := {"NA": Vector2(110, 330), "SA": Vector2(300, 640), "EU": Vector2(690, 36),
	"AF": Vector2(800, 700), "AS": Vector2(1500, 360), "OC": Vector2(1400, 722)}

var game = null
var data: Dictionary = {}
var camera: MapCamera
var sun: DirectionalLight3D
var env: Environment
var viewer := -1
var quality := "alto"
var show_names := true

var selected := -1
var hovered := -1
var targets: Array = []          # [{idx, sea, airlift}]
var target_set := {}             # idx -> dict
var marks: Array = []
var mark_color := Color(0.45, 1.0, 0.6)
var drag_from := -1
var drag_to := Vector3.ZERO
var drag_active := false

var _terrain_mi: MeshInstance3D
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _cloud_mi: MeshInstance3D
var _cloud_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _owner_img: Image
var _owner_tex: ImageTexture
var _state_img: Image
var _state_tex: ImageTexture
var _cont_img: Image
var _cont_tex: ImageTexture
var _last_owner_colors: PackedColorArray = PackedColorArray()
var _state_dirty := true
var _centers: Array = []         # Vector3 per territorio
var _markers: Array = []
var _divs := {}
var _fx := {}
var _overlay_top: ImmediateMesh
var _scale_s := 1.0
var _press_pos := Vector2.ZERO
var _press_idx := -1
var _pressing := false
var _own_game := false
var _ov_open := false
var _real_t := 0.0
var _battle_until := {}          # idx -> tempo reale fino a cui mostrare "battaglia in corso"
var _incoming := {}              # idx -> secondi all'arrivo del primo attacco nemico
var _cont_owner := {}            # chiave continente -> proprietario (-1 nessuno)
# sovrimpressione 2D
var _ui_layer: CanvasLayer
var _ov2d: MapOverlay
var _vignette: ColorRect
var _badge_pos: Array = []       # Vector2 per territorio (posizione sullo schermo del distintivo)
var _badge_off: Array = []       # Vector2 spostamento persistente (sfoltimento)
var _badge_vis: Array = []       # bool
var _badge_r := 14.0
# boschi
var _decor: MapDecor = null        # boschi, città, strutture, fronte animato (map_decor.gd)
var _front_img: Image              # 64×1: r calore del fronte per territorio
var _front_tex: ImageTexture
var _front_bytes := PackedByteArray()
var _last_pairs: Array = []
# fase 3: nebbia di guerra, veterani, patti
var _vis_img: Image               # 64×1: r nebbia (0..1 animata), g proprietario+1, b maschera dei partner di patto
var _vis_tex: ImageTexture
var _vis_bytes := PackedByteArray()
var _vis: Array = []              # bool per territorio (visibile al giocatore "viewer")
var _fog_cur := PackedFloat32Array()
var _demo_fog := false
var _demo_pacts: Array = []       # patti finti per lo screenshot se il nucleo non li ha ancora
var _promos: Array = []           # {idx, t, n} promozioni di veterani (stelle che salgono dal distintivo)
var _demo_viewer := -1
var _gold_mat: StandardMaterial3D
# fase 4: ciclo giorno/notte (un giorno ogni DAY_LEN secondi di gioco), obiettivi degli scenari
const DAY_LEN := 360.0
var daynight := true
var _start_hour := 9.0
var _hour := 9.0
var _sun_base_rot := Vector3(-38, -42, 0)
var _obj_list: Array = []          # indici dei territori obiettivo dello scenario
var _obj_nodes := {}               # idx -> {node, flag, ring}
var _demo_objectives: Array = []

# ====================================================================== ciclo di vita
func _ready() -> void:
	data = MapGen.build()
	print("[WorldMap] mondo generato in ", data["ms"], " ms (cache: ", data["cached"], ")")
	_build_textures()
	_build_environment()
	_build_terrain()
	_build_water()
	_build_clouds()
	_build_sea_routes()
	_build_overlay()
	_build_ui_layer()
	camera = MapCamera.new()
	add_child(camera)
	camera.current = true
	_build_markers()
	_decor = MapDecor.new()
	add_child(_decor)
	_decor.setup(self)
	_init_settings()
	visibility_changed.connect(func(): _ui_layer.visible = is_visible_in_tree())
	var demo := _shot_arg("demo")
	if demo != "":
		_start_demo()
	_apply_cam_preset(_shot_arg("cam", "world"))
	if _shot_arg("nodecor") != "" and _decor != null:
		# debug: --nodecor=SpecksAdd,SpecksMix,Cities,Structures,Forest nasconde parti dell'arredo
		for nm in _shot_arg("nodecor").split(","):
			var nd := _decor.get_node_or_null(nm)
			if nd != null:
				nd.visible = false
	if _shot_arg("noglow") != "":
		env.glow_enabled = false
	if _shot_arg("fps") != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _shot_arg(n: String, def := "") -> String:
	var s = get_node_or_null("/root/Shot")
	if s == null:
		return def
	return s.arg(n, def)

# ---------------------------------------------------------------- impostazioni
func _init_settings() -> void:
	var st = get_node_or_null("/root/Settings")
	var q := "alto"
	if st != null and st.has_method("get_value"):
		var v = st.get_value("quality")
		if v != null and String(v) in ["basso", "medio", "alto"]:
			q = String(v)
		var sn = st.get_value("show_names")
		if sn != null:
			show_names = bool(sn)
		var dn = st.get_value("daynight")
		if dn != null:
			daynight = bool(dn)
		if st.has_signal("changed"):
			st.changed.connect(_on_setting_changed)
	if _shot_arg("quality") != "":
		q = _shot_arg("quality")
	if _shot_arg("daynight") != "":
		daynight = _shot_arg("daynight") != "0"
	apply_quality(q)
	_update_daynight()

func _on_setting_changed(key: String) -> void:
	var st = get_node_or_null("/root/Settings")
	if st == null:
		return
	if key == "quality":
		apply_quality(String(st.get_value("quality")))
	elif key == "show_names":
		show_names = bool(st.get_value("show_names"))
	elif key == "daynight":
		var v = st.get_value("daynight")
		daynight = v == null or bool(v)
		_update_daynight()

## "basso" | "medio" | "alto": ombre, risoluzione del rilievo, nuvole, boschi, bagliore.
func apply_quality(q: String) -> void:
	if not q in ["basso", "medio", "alto"]:
		q = "alto"
	quality = q
	var pm := _terrain_mi.mesh as PlaneMesh
	match q:
		"basso":
			sun.shadow_enabled = false
			pm.subdivide_width = 239
			pm.subdivide_depth = 134
			_terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cloud_mi.visible = false
			env.glow_enabled = false
			_terrain_mat.set_shader_parameter("detail", 0.5)
			_terrain_mat.set_shader_parameter("city_lights", 1.0)
			_build_forest(0.0)
		"medio":
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			pm.subdivide_width = 359
			pm.subdivide_depth = 201
			_terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cloud_mi.visible = true
			env.glow_enabled = true
			_terrain_mat.set_shader_parameter("detail", 0.85)
			_terrain_mat.set_shader_parameter("city_lights", 2.0)
			_build_forest(0.55)
		_:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			pm.subdivide_width = 479
			pm.subdivide_depth = 269
			_terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_cloud_mi.visible = true
			env.glow_enabled = true
			_terrain_mat.set_shader_parameter("detail", 1.0)
			_terrain_mat.set_shader_parameter("city_lights", 2.0)
			_build_forest(1.0)

# ====================================================================== API pubblica
func bind(g) -> void:
	game = g
	viewer = -1
	if game != null and "human_idx" in game:
		viewer = int(game.human_idx)
	if _shot_arg("viewer") != "":
		viewer = int(_shot_arg("viewer"))
	_last_owner_colors = PackedColorArray()
	for d in _divs.values():
		d["node"].queue_free()
	_divs.clear()
	for f in _fx.values():
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	_fx.clear()
	_battle_until.clear()
	_turn_lon = 99.0
	for a in _turn_anims:
		if is_instance_valid(a["node"]):
			a["node"].queue_free()
	_turn_anims.clear()
	if _demo_viewer >= 0:
		viewer = _demo_viewer
	_promos.clear()
	# --hour=H (demo): ora sul meridiano centrale nell'istante attuale della partita
	if _shot_arg("hour") != "" and game != null and "time" in game:
		_start_hour = float(_shot_arg("hour")) - float(game.time) / DAY_LEN * 24.0
	for mk in _markers:
		mk["prev_owner"] = -99
		mk["prev_count"] = -99
		mk["prev_vet"] = -1
	if game != null:
		_compute_visibility()
		_update_vis_tex(0.0, true)
		_update_owner_tex()
		_update_markers(true, 0.0)

## Coordinate mappa (0..1600 × 0..900) → mondo (scala 0.1, centro all'origine). y = rilievo (0 sul mare).
func map_to_world(x: float, y: float) -> Vector3:
	var h := 0.0
	if not data.is_empty():
		h = maxf(MapGen.height_at(data, x, y), 0.0)
	return Vector3(x * SCALE - HALF.x, h, y * SCALE - HALF.y)

func world_to_map(p: Vector3) -> Vector2:
	return Vector2((p.x + HALF.x) / SCALE, (p.z + HALF.y) / SCALE)

## Punto del mondo sotto un punto dello schermo (rilievo o mare; piano y=0 se il raggio non colpisce nulla).
func screen_to_world(pos: Vector2) -> Vector3:
	var hit = _ray_terrain(pos)
	if hit != null:
		return hit
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	if absf(d.y) < 0.0001:
		return Vector3(o.x, 0, o.z)
	return o + d * (-o.y / d.y)

func set_selection(idx: int) -> void:
	if idx == selected:
		return
	selected = idx
	_state_dirty = true

func set_targets(list: Array) -> void:
	targets = []
	target_set = {}
	for t in list:
		var e: Dictionary = t if t is Dictionary else {"idx": int(t), "sea": false, "airlift": false}
		targets.append(e)
		target_set[int(e["idx"])] = e
	_state_dirty = true

func set_marks(idxs: Array, color: Color) -> void:
	marks = idxs.duplicate()
	mark_color = color
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("mark_color", color)
	_state_dirty = true

func set_drag(from_idx: int, to_world: Vector3) -> void:
	drag_from = from_idx
	drag_to = to_world
	drag_active = from_idx >= 0

func clear_drag() -> void:
	drag_active = false
	drag_from = -1

## Volo morbido della telecamera sul territorio (si avvicina fino alla vista "media" se si è lontani).
func focus(idx: int) -> void:
	if idx < 0 or idx >= _centers.size():
		return
	camera.fly_to(_centers[idx], minf(camera._goal_dist, 40.0))

## Transizione continua tabellone → battaglia: la telecamera scende sul territorio conteso (la battaglia poi parte
## dall'alto sullo stesso paesaggio). Restituisce la durata del volo in secondi; ricorda la vista di prima per `rise_from`.
var _view_before := {}
func dive_to(idx: int) -> float:
	if idx < 0 or idx >= _centers.size():
		return 0.0
	_view_before = {"t": camera._goal_target, "d": camera._goal_dist, "y": camera._goal_yaw}
	camera.fly_to(_centers[idx], MapCamera.MIN_DIST + 4.0)
	return camera._fly_dur if camera.is_flying() else 0.0

## Ritorno dalla battaglia: la vista riparte bassa sul territorio e risale alla posizione di prima della battaglia.
func rise_from(idx: int) -> void:
	if idx < 0 or idx >= _centers.size():
		return
	var c: Vector3 = _centers[idx]
	var y: float = float(_view_before.get("y", camera._goal_yaw))
	camera.set_view(c, MapCamera.MIN_DIST + 4.0, y, true)
	var d := float(_view_before.get("d", 60.0))
	var t: Vector3 = _view_before.get("t", c)
	# la vista di prima, ma non più lontana della vista "media": il territorio appena conteso resta leggibile
	camera.fly_to(t.lerp(c, 0.5), minf(maxf(d, 34.0), 70.0))

## Territorio sotto il punto dello schermo (-1 = mare/nulla).
func territory_at_screen(pos: Vector2) -> int:
	return int(pick(pos)["idx"])

## Picking: prima i distintivi (sullo schermo), poi il rilievo (ray marching sulla heightmap).
func pick(pos: Vector2) -> Dictionary:
	var hit = _ray_terrain(pos)
	var idx := -1
	var wp := Vector3.ZERO
	if hit != null:
		wp = hit
		var m := world_to_map(wp)
		idx = MapGen.territory_at(data, m.x, m.y)
	var best := _badge_r + 5.0
	for i in _badge_pos.size():
		if not _badge_vis[i]:
			continue
		var d: float = (_badge_pos[i] as Vector2).distance_to(pos)
		if d < best:
			best = d
			idx = i
			if hit == null:
				wp = _centers[i]
	return {"idx": idx, "world": wp}

# ====================================================================== costruzione
func _build_textures() -> void:
	var W: int = data["w"]
	var H: int = data["h"]
	var tid: PackedInt32Array = data["tid"]
	var tb := PackedByteArray(); tb.resize(W * H)
	var fb := PackedByteArray(); fb.resize(W * H * 4)
	var border: PackedByteArray = data["border"]
	var cont: PackedByteArray = data["cont"]
	var coast: PackedByteArray = data["coast"]
	var nbr: PackedByteArray = data["nbr"]
	for i in W * H:
		tb[i] = tid[i] + 1
		fb[i * 4] = border[i]
		fb[i * 4 + 1] = cont[i]
		fb[i * 4 + 2] = coast[i]
		fb[i * 4 + 3] = nbr[i]
	data["tid_tex"] = ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, tb))
	data["field_tex"] = ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, fb))
	var himg := Image.create_from_data(W, H, false, Image.FORMAT_RF, (data["height"] as PackedFloat32Array).to_byte_array())
	data["height_tex"] = ImageTexture.create_from_image(himg)
	data["ter1_tex"] = ImageTexture.create_from_image(data["ter1"])
	data["ter2_tex"] = ImageTexture.create_from_image(data["ter2"])
	_owner_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_owner_img.fill(Color(D.NEUTRAL_COLOR))
	_owner_tex = ImageTexture.create_from_image(_owner_img)
	_state_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_state_img.fill(Color(0, 0, 0, 0))
	_state_tex = ImageTexture.create_from_image(_state_img)
	_cont_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_cont_img.fill(Color(0, 0, 0, 0))
	_cont_tex = ImageTexture.create_from_image(_cont_img)
	_vis_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_vis_img.fill(Color(0, 0, 0, 0))
	_vis_tex = ImageTexture.create_from_image(_vis_img)
	_front_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_front_img.fill(Color(0, 0, 0, 0))
	_front_tex = ImageTexture.create_from_image(_front_img)
	_fog_cur.resize(NT)
	_fog_cur.fill(0.0)
	for t in D.TERRITORIES:
		_vis.append(true)
		_centers.append(map_to_world(t["x"], t["y"]))
		_badge_pos.append(Vector2.ZERO)
		_badge_off.append(Vector2.ZERO)
		_badge_vis.append(false)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.06, 0.10, 0.17)
	psm.sky_horizon_color = Color(0.26, 0.34, 0.42)
	psm.ground_bottom_color = Color(0.02, 0.03, 0.05)
	psm.ground_horizon_color = Color(0.20, 0.26, 0.32)
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.18, 0.26, 0.34)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.07
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	# luce fredda di riempimento da sala operativa (senza ombre)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55, 140, 0)
	fill.light_color = Color(0.55, 0.75, 0.95)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.light_specular = 0.1
	add_child(fill)

func _build_terrain() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 90)
	pm.subdivide_width = 479
	pm.subdivide_depth = 269
	_terrain_mi = MeshInstance3D.new()
	_terrain_mi.name = "Terrain"
	_terrain_mi.mesh = pm
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = load("res://scripts/map/terrain.gdshader")
	for k in ["height_tex", "tid_tex", "field_tex", "ter1_tex", "ter2_tex"]:
		_terrain_mat.set_shader_parameter(k, data[k])
	_terrain_mat.set_shader_parameter("owner_tex", _owner_tex)
	_terrain_mat.set_shader_parameter("state_tex", _state_tex)
	_terrain_mat.set_shader_parameter("cont_tex", _cont_tex)
	_terrain_mat.set_shader_parameter("vis_tex", _vis_tex)
	_terrain_mat.set_shader_parameter("front_tex", _front_tex)
	_terrain_mat.set_shader_parameter("tex_size", Vector2(data["w"], data["h"]))
	_terrain_mat.set_shader_parameter("mark_color", mark_color)
	_terrain_mi.material_override = _terrain_mat
	_terrain_mi.custom_aabb = AABB(Vector3(-80, -1, -45), Vector3(160, 4, 90))
	add_child(_terrain_mi)

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 500)
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://scripts/map/water.gdshader")
	_water_mat.set_shader_parameter("height_tex", data["height_tex"])
	_water_mat.set_shader_parameter("field_tex", data["field_tex"])
	_water_mat.set_shader_parameter("tex_size", Vector2(data["w"], data["h"]))
	mi.material_override = _water_mat
	add_child(mi)

func _build_clouds() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 120)
	_cloud_mi = MeshInstance3D.new()
	_cloud_mi.name = "Clouds"
	_cloud_mi.mesh = pm
	_cloud_mi.position.y = 7.0
	_cloud_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://scripts/map/clouds.gdshader")
	_cloud_mat.set_shader_parameter("height_tex", data["height_tex"])
	_cloud_mat.render_priority = 1
	_cloud_mi.material_override = _cloud_mat
	add_child(_cloud_mi)

func _line_material(top: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := load("res://scripts/map/line.gdshader") as Shader
	if top:
		var code := sh.code.replace("render_mode unshaded,", "render_mode unshaded, depth_test_disabled,")
		var s2 := Shader.new()
		s2.code = code
		sh = s2
	m.shader = sh
	m.render_priority = 2 if top else 0
	return m

func _build_sea_routes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.62, 0.86, 0.95, 0.42)
	for l in D.SEA_LINKS:
		var a: Dictionary = D.TERRITORIES[D.TERR_INDEX[l[0]]]
		var b: Dictionary = D.TERRITORIES[D.TERR_INDEX[l[1]]]
		var wrap := false
		for w in D.WRAP_LINKS:
			if (w[0] == l[0] and w[1] == l[1]) or (w[0] == l[1] and w[1] == l[0]):
				wrap = true
		var A := Vector2(a["x"], a["y"])
		var B := Vector2(b["x"], b["y"])
		if wrap:
			# rotta di Bering: esce da un bordo e rientra dall'altro
			if A.x > B.x:
				var tmp := A; A = B; B = tmp
			var B2 := Vector2(B.x - D.MAP_W, B.y)
			var u := A.x / (A.x - B2.x)
			var E1 := A.lerp(B2, u)
			_route_strip(st, A, E1 + Vector2(-30, 0), col)
			var A2 := Vector2(A.x + D.MAP_W, A.y)
			var E2 := B.lerp(A2, (D.MAP_W - B.x) / (A2.x - B.x))
			_route_strip(st, B, E2 + Vector2(30, 0), col)
		else:
			_route_strip(st, A, B, col)
	var mi := MeshInstance3D.new()
	mi.name = "SeaRoutes"
	mi.mesh = st.commit()
	mi.material_override = _line_material(false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _route_strip(st: SurfaceTool, A: Vector2, B: Vector2, col: Color) -> void:
	var pts := PackedVector3Array()
	var n := maxi(2, int(A.distance_to(B) / 12.0))
	for k in n + 1:
		var p := A.lerp(B, float(k) / n)
		pts.append(Vector3(p.x * SCALE - HALF.x, 0.07, p.y * SCALE - HALF.y))
	_strip_to_surface(st, pts, 0.16, col, 1.8, 0.2)

func _strip_to_surface(st: SurfaceTool, pts: PackedVector3Array, width: float, col: Color, dash: float, speed: float) -> void:
	var dist := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		if dir.length() < 0.0001:
			continue
		var side := Vector3(-dir.z, 0, dir.x).normalized() * width * 0.5
		var L := a.distance_to(b)
		var quad := [[a - side, Vector2(dist, 0)], [a + side, Vector2(dist, 1)], [b + side, Vector2(dist + L, 1)], [b - side, Vector2(dist + L, 0)]]
		for q in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(quad[q][1])
			st.set_uv2(Vector2(dash, speed))
			st.add_vertex(quad[q][0])
		dist += L

func _build_overlay() -> void:
	_overlay_top = ImmediateMesh.new()
	var mt := MeshInstance3D.new()
	mt.mesh = _overlay_top
	mt.material_override = _line_material(true)
	mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mt.custom_aabb = AABB(Vector3(-400, -10, -300), Vector3(800, 60, 600))
	add_child(mt)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://scripts/map/ring.gdshader")

func _build_ui_layer() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 1
	add_child(_ui_layer)
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vm := ShaderMaterial.new()
	vm.shader = load("res://scripts/map/vignette.gdshader")
	_vignette.material = vm
	_ui_layer.add_child(_vignette)
	_ov2d = MapOverlay.new()
	_ui_layer.add_child(_ov2d)

func _ring(parent: Node3D, radius: float, col: Color, inner := 0.82) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(2, 2)
	mi.mesh = qm
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1, radius)
	mi.set_instance_shader_parameter("ring_color", col)
	mi.set_instance_shader_parameter("inner", inner)
	mi.visible = false
	parent.add_child(mi)
	return mi

func _build_markers() -> void:
	for t in D.TERRITORIES:
		var i: int = t["idx"]
		var root := Node3D.new()
		root.name = "T_" + String(t["id"])
		root.position = _centers[i]
		add_child(root)
		var holder := Node3D.new()
		holder.rotation.y = 0.55
		root.add_child(holder)
		var bld := Node3D.new()
		root.add_child(bld)
		# stelline dei veterani (da vicino, davanti alle miniature)
		var vets := Node3D.new()
		vets.visible = false
		root.add_child(vets)
		for k in 3:
			var sm := MeshInstance3D.new()
			sm.mesh = MapProps.star_mesh()
			sm.material_override = _gold_material()
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sm.visible = false
			vets.add_child(sm)
		_markers.append({"root": root, "holder": holder, "bld": bld, "vets": vets, "sig": "", "color": Color(0, 0, 0, 0),
			"count": -2, "bkeys": "", "anim": "", "anim_t": 9.0, "prev_owner": -99, "prev_count": -99, "top": 1.0,
			"vet": 0, "prev_vet": -1, "vis": true})

func _gold_material() -> StandardMaterial3D:
	if _gold_mat == null:
		_gold_mat = StandardMaterial3D.new()
		_gold_mat.albedo_color = Color(1.0, 0.78, 0.28)
		_gold_mat.metallic = 0.85
		_gold_mat.roughness = 0.3
		_gold_mat.emission_enabled = true
		_gold_mat.emission = Color(1.0, 0.7, 0.2)
		_gold_mat.emission_energy_multiplier = 0.9
		_gold_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_gold_mat.billboard_keep_scale = true
	return _gold_mat

# ---------------------------------------------------------------- boschi (MapDecor)
func _build_forest(density: float) -> void:
	if _decor != null:
		_decor.set_forest(density, quality)

# ====================================================================== demo
func _start_demo() -> void:
	var gs = MapProps.global_class_script("Game")
	var minutes := float(_shot_arg("minutes", "7"))
	if _shot_arg("mock") != "":
		gs = null
	if gs != null:
		var opts := {"players": [{"faction": 0, "human": false, "difficulty": "veterano"}, {"faction": 1, "human": false, "difficulty": "veterano"},
			{"faction": 2, "human": false, "difficulty": "veterano"}, {"faction": 3, "human": false, "difficulty": "veterano"}],
			"mode": "conquista", "distribution": "regionale", "seed": int(_shot_arg("seed", "3")), "ask_defense": false, "auto_battles": true}
		if _shot_arg("fog") != "":
			opts["fog"] = true
		game = gs.new(opts)
		print("[WorldMap] demo con Game reale")
	else:
		game = load("res://scripts/map/demo_state.gd").new(int(_shot_arg("seed", "7")))
		print("[WorldMap] demo con stato finto (Game non disponibile)")
	_own_game = true
	var t := 0.0
	var t0 := Time.get_ticks_msec()
	while t < minutes * 60.0:
		game.step(0.25)
		t += 0.25
		if game.over != null:
			break
		if Time.get_ticks_msec() - t0 > 20000:
			break
	print("[WorldMap] demo avanzata a ", snappedf(game.time, 0.1), " s in ", Time.get_ticks_msec() - t0, " ms; divisioni ", game.divisions.size())
	_demo_phase3()
	bind(game)
	var sel := int(_shot_arg("sel", "-1"))
	if sel >= 0:
		set_selection(sel)
		var tl: Array = []
		for a in D.TERRITORIES[sel]["adj"]:
			tl.append({"idx": a, "sea": Data.is_sea_link(sel, a), "airlift": false})
		set_targets(tl)
		if _shot_arg("drag") != "":
			var to: int = tl[0]["idx"]
			set_drag(sel, _centers[to].lerp(_centers[sel], 0.15))
	if _shot_arg("hover") != "":
		hovered = int(_shot_arg("hover"))
		_state_dirty = true
	if _shot_arg("fxtest") != "":
		var tm := float(game.time)
		var T: Array = D.TERRITORIES
		game.effects.append({"type": "missile", "x": T[29]["x"], "y": T[29]["y"], "x2": T[17]["x"], "y2": T[17]["y"], "born": tm, "dur": 4.0})
		game.effects.append({"type": "explosion", "x": T[19]["x"], "y": T[19]["y"], "born": tm, "dur": 3.0})
		game.effects.append({"type": "capture", "x": T[16]["x"], "y": T[16]["y"], "born": tm, "dur": 3.0})
		game.effects.append({"type": "battle", "x": T[18]["x"], "y": T[18]["y"], "born": tm, "dur": 4.0})
	if _shot_arg("attack") != "":
		_demo_attack()
	if _shot_arg("objectives") != "":
		# territori chiave finti per lo screenshot se il nucleo non ne espone
		_demo_objectives = ["alaska", "maghreb", "medioriente", "siberia", "indonesia"]
	if _shot_arg("marks") != "":
		set_marks([13, 14, 15, 16], Color(0.4, 1.0, 0.55))
	if _shot_arg("buildings") != "":
		_demo_buildings()
	if _shot_arg("capture") != "" and _decor != null:
		# demo: fumo di conquista su un territorio (indice)
		_decor.note_capture(int(_shot_arg("capture")))

## Demo (--buildings=1): edifici, cantieri e fortificazioni sui territori del giocatore più grande (o --viewer), per gli screenshot.
func _demo_buildings() -> void:
	var p := _biggest_player() if viewer < 0 else viewer
	var k := 0
	var keys: Array = D.BUILDING_KEYS
	for i in NT:
		if int(game.terr[i]["owner"]) != p:
			continue
		var tr: Dictionary = game.terr[i]
		var bl: Array = []
		var n := 1 + (k % 3)
		for q in n:
			var key := String(keys[(k + q) % keys.size()])
			if key == "porto" and not bool(D.TERRITORIES[i].get("coastal", false)):
				key = "fabbrica"
			if not bl.has(key):
				bl.append(key)
		tr["buildings"] = bl
		if k % 2 == 1:
			tr["building"] = {"key": "aeroporto", "t": 1, "total": 3}
		if tr.has("fort"):
			tr["fort"] = {"trench": k % 4, "mines": (k + 1) % 4, "bunker": (k + 2) % 4}
		k += 1
	print("[WorldMap] demo edifici su ", k, " territori del giocatore ", p)

## Demo della fase 3 (screenshot): --fog=1 nebbia per il giocatore più grande, --vet=1 veterani, --pact=1 patto,
## --ships=1 convogli navali a metà traversata. Usa le API del nucleo se ci sono, altrimenti dati finti locali.
func _demo_phase3() -> void:
	var biggest := _biggest_player()
	if _shot_arg("viewer") != "":
		biggest = int(_shot_arg("viewer"))
	if _shot_arg("fog") != "":
		_demo_viewer = biggest
		if not game.has_method("is_visible"):
			_demo_fog = true
		print("[WorldMap] demo nebbia: viewer ", biggest, " (", "nucleo" if not _demo_fog else "regola di riserva", ")")
	if _shot_arg("vet") != "":
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var any := false
		for i in NT:
			if int(game.terr[i].get("vet", 0)) > 0:
				any = true
		for i in NT:
			if int(game.terr[i].get("vet", 0)) == 0 and Data.total_units(game.terr[i]["forces"]) > 0 and int(game.terr[i]["owner"]) >= 0 and rng.randf() < 0.8:
				game.terr[i]["vet"] = rng.randi_range(1, 2)
		for d in game.divisions:
			if int(d.get("vet", 0)) == 0 and rng.randf() < 0.6:
				d["vet"] = rng.randi_range(1, 3)
		print("[WorldMap] demo veterani (il nucleo ne aveva gia': ", any, ")")
	if _shot_arg("pact") != "":
		# coppia di giocatori con il confine più lungo
		var best_n := 0
		var pa := -1
		var pb := -1
		var cnt := {}
		for i in NT:
			var o := int(game.terr[i]["owner"])
			for a in D.TERRITORIES[i]["adj"]:
				var o2 := int(game.terr[a]["owner"])
				if o >= 0 and o2 >= 0 and o < o2:
					var key := "%d,%d" % [o, o2]
					cnt[key] = int(cnt.get(key, 0)) + 1
					if int(cnt[key]) > best_n:
						best_n = int(cnt[key])
						pa = o
						pb = o2
		if pa >= 0:
			if _demo_viewer < 0:
				_demo_viewer = pa
			var other := pb if _demo_viewer == pa else pa
			if _demo_viewer != pa and _demo_viewer != pb:
				other = pb
			var pact := {"a": _demo_viewer, "b": other, "until": float(game.time) + 247.0}
			if game.get("pacts") is Array:
				game.pacts.append(pact)
			else:
				_demo_pacts.append(pact)
			print("[WorldMap] demo patto tra ", pact["a"], " e ", pact["b"], " (confini in comune ", best_n, ")")
	if _shot_arg("ships") != "":
		_demo_ships()

func _biggest_player() -> int:
	var cnt := {}
	for i in NT:
		var o := int(game.terr[i]["owner"])
		if o >= 0:
			cnt[o] = int(cnt.get(o, 0)) + 1
	var best := 0
	for o in cnt:
		if int(cnt[o]) > int(cnt.get(best, 0)):
			best = o
	return best

## Demo: convogli navali a metà traversata sulle rotte marittime (per lo screenshot delle navi).
func _demo_ships() -> void:
	var nid := 91000
	var made := 0
	for l in D.SEA_LINKS:
		var a: int = D.TERR_INDEX[l[0]]
		var b: int = D.TERR_INDEX[l[1]]
		if _is_wrap(a, b) or int(game.terr[a]["owner"]) < 0:
			continue
		var f: Dictionary = Data.empty_forces()
		f["inf"] = 8 + made * 6
		f["tank"] = 4 + made * 2
		game.divisions.append({"id": nid, "owner": int(game.terr[a]["owner"]), "from": a, "to": b, "forces": f, "t": 12.0, "total": 24.0,
			"sea": true, "airlift": false, "retreat": false, "x": D.TERRITORIES[a]["x"], "y": D.TERRITORIES[a]["y"], "vet": 2})
		nid += 1
		made += 1
		if made >= 4:
			break

## Demo: forza alcune divisioni nemiche in viaggio verso i territori del giocatore "viewer" (per lo screenshot).
func _demo_attack() -> void:
	if viewer < 0:
		var cnt := {}
		for i in NT:
			var o := int(game.terr[i]["owner"])
			if o >= 0:
				cnt[o] = int(cnt.get(o, 0)) + 1
		var best := 0
		for o in cnt:
			if int(cnt[o]) > int(cnt.get(best, 0)):
				best = o
		viewer = best
	var mine: Array = []
	for i in NT:
		if int(game.terr[i]["owner"]) == viewer:
			mine.append(i)
	var made := 0
	var nid := 90000
	for i in mine:
		for a in D.TERRITORIES[i]["adj"]:
			var o := int(game.terr[a]["owner"])
			if o >= 0 and o != viewer and made < 3:
				var f: Dictionary = Data.empty_forces()
				f["tank"] = 4 + made * 3
				f["inf"] = 6
				var sea := Data.is_sea_link(a, i)
				game.divisions.append({"id": nid, "owner": o, "from": a, "to": i, "forces": f, "t": 6.0 + made * 4.0, "total": 24.0,
					"sea": sea, "airlift": false, "retreat": false, "x": D.TERRITORIES[a]["x"], "y": D.TERRITORIES[a]["y"]})
				nid += 1
				made += 1
				break
	print("[WorldMap] demo attacco: viewer ", viewer, ", divisioni ostili ", made)

var _fps_t := 0.0
var _fps_acc := 0
var _test_done := false
var _promo_done := false

## Demo: promuove un territorio visibile vicino al centro dello schermo (per vedere l'effetto nello screenshot).
func _demo_promote() -> void:
	var c := get_viewport().get_visible_rect().get_center()
	var best := -1
	var bd := 1e9
	for i in NT:
		if not _badge_vis[i] or not terr_visible(i) or int(game.terr[i].get("vet", 0)) >= 3 or int(_markers[i]["count"]) <= 0:
			continue
		var d := (_badge_pos[i] as Vector2).distance_to(c)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		game.terr[best]["vet"] = int(game.terr[best].get("vet", 0)) + 1
		print("[WorldMap] demo promozione: ", D.TERRITORIES[best]["id"], " -> ", game.terr[best]["vet"])

## Autoverifica (--picktest=1): proietta il centro di ogni territorio sullo schermo e lo ripesca col picking.
func _pick_test() -> void:
	var ok := 0
	var bad: Array = []
	var vis := 0
	var rect := get_viewport().get_visible_rect()
	for i in NT:
		var c: Vector3 = _centers[i]
		if camera.is_position_behind(c):
			continue
		var sp := camera.unproject_position(c)
		if not rect.has_point(sp):
			continue
		vis += 1
		var ti := territory_at_screen(sp)
		if ti == i: ok += 1
		else: bad.append([D.TERRITORIES[i]["id"], ti])
	var okb := 0
	var nb := 0
	for i in NT:
		if _badge_vis[i]:
			nb += 1
			if territory_at_screen(_badge_pos[i]) == i:
				okb += 1
	print("[WorldMap] picktest: centri ", ok, "/", vis, " corretti; errori: ", bad, "; distintivi ", okb, "/", nb)

func _apply_cam_preset(p: String) -> void:
	match p:
		"europe":
			camera.set_view(map_to_world(830, 250), 40.0, 0.0, true)
		"close":
			camera.set_view(map_to_world(830, 225), 15.0, 0.25, true)
		"relief":
			camera.set_view(map_to_world(1110, 250), 11.0, -0.3, true)
		"asia":
			camera.set_view(map_to_world(1200, 260), 46.0, 0.0, true)
		"div":
			if game != null and game.divisions.size() > 0:
				var dv: Dictionary = game.divisions[0]
				for dd in game.divisions:
					if bool(dd.get("sea", false)):
						dv = dd
				camera.set_view(_div_path_point(dv, float(dv["t"]) / maxf(float(dv["total"]), 0.01)), 16.0, 0.3, true)
		"attack":
			var c := Vector3.ZERO
			var n := 0
			if game != null:
				for dd in game.divisions:
					if int(dd["id"]) >= 90000:
						c += _centers[int(dd["to"])]
						n += 1
			if n > 0:
				camera.set_view(c / n, 38.0, 0.0, true)
			else:
				camera.set_view(map_to_world(830, 250), 40.0, 0.0, true)
		"america":
			camera.set_view(map_to_world(330, 330), 60.0, 0.0, true)
		"pact":
			# centro del confine tra i partner del primo patto
			var c := Vector3.ZERO
			var n := 0
			if game != null:
				_update_vis_tex(0.0, true)
				for i in NT:
					for a in D.TERRITORIES[i]["adj"]:
						var o := int(game.terr[i]["owner"])
						var o2 := int(game.terr[a]["owner"])
						if o != o2 and _has_pact(o, o2) and not Data.is_sea_link(i, a):
							c += (_centers[i] + _centers[a]) * 0.5
							n += 1
			if n > 0:
				camera.set_view(c / n, float(_shot_arg("dist", "34")), 0.0, true)
			else:
				camera.set_view(map_to_world(830, 250), 40.0, 0.0, true)
		"front":
			# confine conteso più caldo (demo): centro tra i due territori
			var pr: Array = []
			if game != null and _decor != null:
				_update_decor(0.0)
				pr = _decor.hottest_pair(game, _last_pairs)
			if pr.size() == 2:
				camera.set_view((_centers[pr[0]] + _centers[pr[1]]) * 0.5, float(_shot_arg("dist", "22")), float(_shot_arg("yaw", "0")), true)
			else:
				camera.set_view(map_to_world(830, 250), 40.0, 0.0, true)
		"hq":
			# QG del giocatore (--viewer o il più grande), vista ravvicinata
			var pl := _biggest_player() if viewer < 0 else viewer
			var ti := int(game.players[pl]["hq"]) if game != null and pl >= 0 else 17
			camera.set_view(_centers[ti] + Vector3(0, 0, 1.2), float(_shot_arg("dist", "15")), float(_shot_arg("yaw", "0")), true)
		"at":
			var ti := int(_shot_arg("at_idx", "17"))
			camera.set_view(_centers[ti], float(_shot_arg("dist", "24")), float(_shot_arg("yaw", "0")), true)
		"xy":
			camera.set_view(map_to_world(float(_shot_arg("mx", "800")), float(_shot_arg("my", "450"))), float(_shot_arg("dist", "12")), float(_shot_arg("yaw", "0")), true)
		"fly":
			camera.set_view(Vector3(-3, 0, -5.5), 132.0, 0.0, true)
			focus(int(_shot_arg("sel", "17")))
		_:
			camera.set_view(Vector3(-3, 0, -5.5), 132.0, 0.0, true)

# ====================================================================== aggiornamento
func _process(delta: float) -> void:
	_real_t += delta
	if _own_game and game != null and _shot_arg("freeze") == "":
		if game.has_method("update"):
			game.update(delta)
		else:
			game.step(delta)
	var dist := camera.dist
	_scale_s = clampf(dist / 34.0, 0.42, 2.6)
	if sun.shadow_enabled:
		sun.directional_shadow_max_distance = clampf(dist * 2.0, 25.0, 220.0)
	var zt := camera.zoom_t()
	var zl := clampf((dist - 12.0) / 110.0, 0.0, 1.0)
	_terrain_mat.set_shader_parameter("tint", lerpf(0.26, 0.55, smoothstep(0.05, 0.7, zl)))
	_terrain_mat.set_shader_parameter("zoom", zl)
	_water_mat.set_shader_parameter("zoom", zl)
	_cloud_mat.set_shader_parameter("fade", smoothstep(45.0, 110.0, dist))
	_update_daynight()
	if game != null:
		_compute_visibility()
		_update_vis_tex(delta)
		_update_owner_tex()
		_update_continents()
		_update_battles()
		_update_markers(false, delta)
		_update_divisions(delta)
		_update_turn_anims(delta)
		_update_effects()
		_update_objectives(delta)
		_update_decor(delta)
	if _state_dirty:
		_update_state_tex()
	_draw_overlay()
	_layout_overlay(delta)
	if _shot_arg("fps") != "":
		_fps_t += delta
		_fps_acc += 1
		if _fps_t > 1.5:
			print("[WorldMap] fps ", snappedf(_fps_acc / _fps_t, 0.1), " draw ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prim ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), " quality ", quality)
			_fps_t = 0.0
			_fps_acc = 0
	if _shot_arg("vet") != "" and _own_game and not _promo_done and Engine.get_process_frames() > int(_shot_arg("promo_at", "40")):
		_promo_done = true
		_demo_promote()
	if _shot_arg("picktest") != "" and not _test_done and Engine.get_process_frames() > 20:
		_test_done = true
		_pick_test()

## Arredo del tabellone: confini ostili (fronte animato), strutture e fumo; calore del fronte nella texture del terreno.
func _update_decor(delta: float) -> void:
	if _decor == null:
		return
	var pairs: Array = []
	for i in NT:
		var o := int(game.terr[i]["owner"])
		if o < 0:
			continue
		for a in D.TERRITORIES[i]["adj"]:
			var j := int(a)
			if j <= i:
				continue
			var o2 := int(game.terr[j]["owner"])
			if o2 < 0 or o2 == o or _has_pact(o, o2):
				continue
			if Data.is_sea_link(i, j):
				continue
			if not terr_visible(i) and not terr_visible(j):
				continue
			pairs.append([i, j])
	_last_pairs = pairs
	_decor.update(game, _vis, pairs, camera.dist, _real_t, delta)
	var heat := _decor.terr_heat()
	var bytes := PackedByteArray()
	bytes.resize(64 * 4)
	for i in NT:
		bytes[i * 4] = int(round(clampf(heat[i], 0.0, 1.0) * 255.0))
		bytes[i * 4 + 3] = 255
	if bytes != _front_bytes:
		_front_bytes = bytes
		_front_img.set_data(64, 1, false, Image.FORMAT_RGBA8, bytes)
		_front_tex.update(_front_img)
		if _shot_arg("decor_debug") != "":
			var mx := 0
			for i in NT:
				mx = maxi(mx, bytes[i * 4])
			print("[WorldMap] fronte: ", pairs.size(), " coppie ostili, calore max ", mx, "/255, texel0 ", _front_img.get_pixel(0, 0))

func _owner_color(o: int) -> Color:
	if o < 0 or game == null or o >= game.players.size():
		return Color(D.NEUTRAL_COLOR)
	var c = game.players[o]["color"]
	return c if c is Color else Color(String(c))

func _update_owner_tex() -> void:
	var cols := PackedColorArray()
	cols.resize(NT)
	for i in NT:
		cols[i] = _owner_color(int(game.terr[i]["owner"]))
	if cols == _last_owner_colors:
		return
	_last_owner_colors = cols
	for i in NT:
		var c := cols[i]
		c.a = 1.0 if int(game.terr[i]["owner"]) >= 0 else 0.0
		_owner_img.set_pixel(i, 0, c)
	_owner_tex.update(_owner_img)

func _update_continents() -> void:
	var changed := false
	for ck in D.CONT_KEYS:
		var o := -2
		for t in D.TERRITORIES:
			if t["c"] != ck:
				continue
			var ow := int(game.terr[t["idx"]]["owner"])
			if o == -2:
				o = ow
			elif o != ow:
				o = -1
				break
		if o < 0:
			o = -1
		if int(_cont_owner.get(ck, -3)) != o:
			_cont_owner[ck] = o
			changed = true
	if not changed:
		return
	for t in D.TERRITORIES:
		var o := int(_cont_owner.get(t["c"], -1))
		var c := Color(0, 0, 0, 0)
		if o >= 0:
			c = _owner_color(o).lightened(0.25)
			c.a = 1.0
		_cont_img.set_pixel(int(t["idx"]), 0, c)
	_cont_tex.update(_cont_img)

# ---------------------------------------------------------------- fase 3: nebbia di guerra, patti, veterani
## Nebbia attiva per il giocatore "viewer" (spettatore = tutto visibile).
func fog_active() -> bool:
	if game == null or viewer < 0:
		return false
	if _demo_fog:
		return true
	if not game.has_method("is_visible"):
		return false
	if "fog" in game and game.get("fog") is bool:
		return bool(game.get("fog"))
	return true

## Territorio visibile al giocatore "viewer" (calcolato una volta per fotogramma).
func terr_visible(t: int) -> bool:
	if t < 0 or t >= _vis.size():
		return true
	return bool(_vis[t])

func _compute_visibility() -> void:
	var on := fog_active()
	var core: bool = on and game.has_method("is_visible") and not _demo_fog
	for i in NT:
		var v := true
		if on:
			v = bool(game.is_visible(viewer, i)) if core else _fallback_visible(i)
		_vis[i] = v

## Regola di riserva (finché il nucleo non ha `is_visible`): propri + adiacenti ai propri.
func _fallback_visible(t: int) -> bool:
	if int(game.terr[t]["owner"]) == viewer:
		return true
	for a in D.TERRITORIES[t]["adj"]:
		if int(game.terr[a]["owner"]) == viewer:
			return true
	return false

## Stima delle forze di un territorio velato (multipli di 5; -1 = ignota).
func _estimate(t: int) -> int:
	if game.has_method("estimate_forces") and not _demo_fog:
		return int(game.estimate_forces(viewer, t))
	var n := Data.total_units(game.terr[t]["forces"])
	var known := int(game.terr[t]["owner"]) < 0
	if not known:
		for a in D.TERRITORIES[t]["adj"]:
			if _fallback_visible(a):
				known = true
				break
	return int(round(n / 5.0)) * 5 if known else -1

## Divisione visibile: propria, oppure parte o arriva in un territorio visibile.
func _div_visible(d: Dictionary) -> bool:
	if not fog_active() or int(d["owner"]) == viewer:
		return true
	if not _demo_fog:
		for m in ["is_division_visible", "division_visible"]:
			if game.has_method(m):
				return bool(game.call(m, viewer, d))
	return terr_visible(int(d["from"])) or terr_visible(int(d["to"]))

var _pact_pairs := {}   # "a,b" (a<b) -> scadenza

func _pacts() -> Array:
	var out: Array = []
	if game == null:
		return out
	var src = game.get("pacts")
	if not (src is Array) or not _demo_pacts.is_empty():
		src = _demo_pacts
	var now := float(game.time)
	for p in src:
		if p is Dictionary and float(p.get("until", 1e9)) > now:
			out.append(p)
	return out

func _has_pact(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	return _pact_pairs.has("%d,%d" % [mini(a, b), maxi(a, b)])

func _pact_until(a: int, b: int) -> float:
	return float(_pact_pairs.get("%d,%d" % [mini(a, b), maxi(a, b)], 0.0))

## Texture per il terreno: nebbia animata (r), proprietario (g), maschera dei partner di patto (b).
func _update_vis_tex(delta: float, snap := false) -> void:
	var on := fog_active()
	var masks := {}
	_pact_pairs.clear()
	for p in _pacts():
		var a := int(p["a"])
		var b := int(p["b"])
		if a < 0 or b < 0 or a > 7 or b > 7:
			continue
		masks[a] = int(masks.get(a, 0)) | (1 << b)
		masks[b] = int(masks.get(b, 0)) | (1 << a)
		_pact_pairs["%d,%d" % [mini(a, b), maxi(a, b)]] = float(p.get("until", 0.0))
	var bytes := PackedByteArray()
	bytes.resize(64 * 4)
	var k := 1.0 if snap else minf(1.0, delta * 2.2)
	for i in NT:
		var target := 0.0 if (not on or _vis[i]) else 1.0
		var v := lerpf(_fog_cur[i], target, k)
		if absf(v - target) < 0.01:
			v = target
		_fog_cur[i] = v
		var o := int(game.terr[i]["owner"])
		bytes[i * 4] = int(round(v * 255.0))
		bytes[i * 4 + 1] = o + 1 if o >= 0 and o < 250 else 0
		bytes[i * 4 + 2] = int(masks.get(o, 0)) & 255 if o >= 0 else 0
		bytes[i * 4 + 3] = _light_density(i)
	if bytes != _vis_bytes:
		_vis_bytes = bytes
		_vis_img.set_data(64, 1, false, Image.FORMAT_RGBA8, bytes)
		_vis_tex.update(_vis_img)

## Densità delle luci notturne del territorio (0..255): edifici, QG, guarnigione.
func _light_density(i: int) -> int:
	var tr: Dictionary = game.terr[i]
	var b := 0.0
	var bl = tr.get("buildings", [])
	if bl is Array:
		b += 0.28 * (bl as Array).size()
	if tr.get("building") != null:
		b += 0.12
	for p in game.players:
		if int(p.get("hq", -1)) == i and bool(p.get("alive", true)):
			b += 0.35
	b += 0.15 * clampf(float(Data.total_units(tr["forces"])) / 30.0, 0.0, 1.0)
	return int(round(clampf(b, 0.0, 1.0) * 255.0))

# ---------------------------------------------------------------- ciclo giorno/notte
## Ora del giorno sul meridiano centrale della carta (0..24).
var _turn_lon := 99.0

func current_hour() -> float:
	return _hour

func _update_daynight() -> void:
	if _terrain_mat == null or sun == null:
		return
	var t := _real_t
	if game != null and "time" in game:
		t = float(game.time)
	_hour = fposmod(_start_hour + t / DAY_LEN * 24.0, 24.0)
	var on := 1.0 if daynight else 0.0
	var lon := (12.0 - _hour) / 24.0 * TAU
	lon = wrapf(lon, -PI, PI)
	# FASE 6 (turni): il giorno segue il giocatore di turno (mezzogiorno sul suo QG) e scorre dolcemente da un turno all'altro,
	# così la zona dove si gioca resta leggibile; game.time ora è solo l'orologio delle animazioni.
	if game != null and game.has_method("end_turn") and "current" in game:
		var cp := int(game.current)
		var tlon := lon
		if cp >= 0 and cp < game.players.size() and int(game.players[cp].get("hq", -1)) >= 0:
			var T: Dictionary = D.TERRITORIES[int(game.players[cp]["hq"])]
			tlon = wrapf((float(T["x"]) / 1600.0 - 0.5) * TAU + 0.35, -PI, PI)   # un po' dopo mezzogiorno: luce radente da ovest
		if _shot_arg("sunat") != "":
			# demo: mezzogiorno su un territorio dato (indice) o sul QG del giocatore più grande ("hq")
			var sx := world_to_map(camera.target).x if camera != null else 800.0
			if _shot_arg("sunat") != "cam":
				var si := int(_shot_arg("sunat")) if _shot_arg("sunat") != "hq" else int(game.players[_biggest_player() if viewer < 0 else viewer]["hq"])
				sx = float(D.TERRITORIES[si]["x"])
			tlon = wrapf((sx / 1600.0 - 0.5) * TAU + float(_shot_arg("sunoff", "0.35")), -PI, PI)
		if _turn_lon > 50.0:
			_turn_lon = tlon
		_turn_lon = lerp_angle(_turn_lon, tlon, 1.0 - exp(-get_process_delta_time() * 1.2))
		lon = wrapf(_turn_lon, -PI, PI)
		_hour = fposmod(12.0 - lon / TAU * 24.0, 24.0)
	# declinazione: oscilla lentamente (stagioni compresse in 8 giorni di gioco)
	var decl := deg_to_rad(14.0) * sin(t / (DAY_LEN * 8.0) * TAU + 0.6)
	var mats: Array = [_terrain_mat, _water_mat, _cloud_mat]
	if _decor != null:
		mats.append_array(_decor.dn_materials())
	for m in mats:
		if m == null:
			continue
		m.set_shader_parameter("daynight", on)
		m.set_shader_parameter("sun_lon", lon)
		m.set_shader_parameter("sun_decl", decl)
	if daynight:
		# da vicino, sul lato notturno, la luce del sole cala (le pedine restano leggibili)
		var focus_day := 1.0
		if camera != null:
			var fp := world_to_map(camera.target)
			var flon := (fp.x / 1600.0 - 0.5) * TAU
			var flt := (0.5 - fp.y / 900.0) * PI * 0.92
			var c := cos(flt) * cos(decl) * cos(flon - lon) + sin(flt) * sin(decl)
			focus_day = smoothstep(-0.13, 0.11, c)
			focus_day = lerpf(focus_day, 1.0, smoothstep(55.0, 100.0, camera.dist))
		sun.light_energy = lerpf(0.45, 1.3, focus_day)
		# il sole gira attorno alla carta: luce radente da est al mattino, da sud a mezzogiorno, da ovest la sera
		sun.rotation_degrees = Vector3(-(38.0 + 14.0 * maxf(cos(lon), 0.0)), rad_to_deg(lon), 0.0)
		var warm := 1.0 - absf(cos(lon))
		sun.light_color = Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.80, 0.62), warm * 0.5)
	else:
		sun.rotation_degrees = _sun_base_rot
		sun.light_color = Color(1.0, 0.94, 0.84)
		sun.light_energy = 1.3

# ---------------------------------------------------------------- obiettivi degli scenari
## Territori chiave dello scenario: game.scenario_targets o game.hold_terrs (indici o id), altrimenti nessuno.
func scenario_objectives() -> Array:
	var raw = null
	if game != null:
		if "scenario_targets" in game:
			raw = game.get("scenario_targets")
		if (raw == null or (raw is Array and raw.is_empty())) and "hold_terrs" in game:
			raw = game.get("hold_terrs")
	if (raw == null or (raw is Array and raw.is_empty())) and not _demo_objectives.is_empty():
		raw = _demo_objectives
	var out: Array = []
	if raw is Array:
		for v in raw:
			var i := -1
			if v is String or v is StringName:
				i = int(D.TERR_INDEX.get(String(v), -1))
			elif v is int or v is float:
				i = int(v)
			elif v is Dictionary and v.has("idx"):
				i = int(v["idx"])
			if i >= 0 and i < NT and not out.has(i):
				out.append(i)
	return out

func _update_objectives(delta: float) -> void:
	var lst := scenario_objectives()
	if lst != _obj_list:
		_obj_list = lst
		for e in _obj_nodes.values():
			e["node"].queue_free()
		_obj_nodes.clear()
		for i in lst:
			_obj_nodes[i] = _make_objective(i)
	if _obj_nodes.is_empty():
		return
	var s := clampf(camera.dist / 34.0, 0.55, 2.4) * 1.3
	for i in _obj_nodes:
		var e: Dictionary = _obj_nodes[i]
		var nd: Node3D = e["node"]
		var o := int(game.terr[i]["owner"])
		var col := _owner_color(o)
		# bandierina un po' a nord-est del distintivo, il pennone ondeggia appena
		nd.position = _centers[i] + Vector3(1.15, 0, -0.75) * s
		nd.scale = Vector3.ONE * s
		var fl: Node3D = e["flag"]
		fl.rotation.y = sin(_real_t * 1.7 + i) * 0.22
		var cloth: MeshInstance3D = e["cloth"]
		(cloth.material_override as StandardMaterial3D).albedo_color = col.lerp(Color(1, 1, 1), 0.15)
		(cloth.material_override as StandardMaterial3D).emission = col
		var ring: MeshInstance3D = e["ring"]
		ring.set_instance_shader_parameter("ring_color", Color(1.0, 0.82, 0.35, 0.85))
		ring.visible = true

func _make_objective(i: int) -> Dictionary:
	var nd := Node3D.new()
	nd.name = "Obiettivo%d" % i
	add_child(nd)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.80, 0.34)
	gold.metallic = 0.8
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.72, 0.25)
	gold.emission_energy_multiplier = 0.6
	# basetta e pennone dorati
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.16; bm.bottom_radius = 0.22; bm.height = 0.08; bm.radial_segments = 20; bm.rings = 1
	base.mesh = bm
	base.material_override = gold
	base.position.y = 0.04
	nd.add_child(base)
	var flag := Node3D.new()
	nd.add_child(flag)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.018; pm.bottom_radius = 0.026; pm.height = 1.25; pm.radial_segments = 8; pm.rings = 1
	pole.mesh = pm
	pole.material_override = gold
	pole.position.y = 0.66
	flag.add_child(pole)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05; sm.height = 0.1; sm.radial_segments = 10; sm.rings = 5
	knob.mesh = sm
	knob.material_override = gold
	knob.position.y = 1.31
	flag.add_child(knob)
	# drappo a coda di rondine nel colore del proprietario, con stella dorata
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := 0.62
	var Hh := 0.36
	var pts := [Vector3(0, 0, 0), Vector3(W, -0.03, 0), Vector3(W * 0.74, -Hh * 0.5, 0), Vector3(W, -Hh + 0.03, 0), Vector3(0, -Hh, 0)]
	for t in [[0, 1, 2], [0, 2, 4], [4, 2, 3]]:
		for k in t:
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(pts[k])
	var cloth := MeshInstance3D.new()
	cloth.mesh = st.commit()
	var cm := StandardMaterial3D.new()
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.roughness = 0.6
	cm.emission_enabled = true
	cm.emission_energy_multiplier = 0.35
	cloth.material_override = cm
	cloth.position = Vector3(0.02, 1.27, 0)
	flag.add_child(cloth)
	var star := Label3D.new()
	star.text = "★"
	star.font_size = 64
	star.pixel_size = 0.0045
	star.modulate = Color(1.0, 0.86, 0.4)
	star.outline_size = 8
	star.outline_modulate = Color(0.15, 0.1, 0.02, 0.8)
	star.position = Vector3(0.24, 1.27 - Hh * 0.5, 0.012)
	star.double_sided = true
	flag.add_child(star)
	var ring := _ring(nd, 0.42, Color(1.0, 0.82, 0.35, 0.85), 0.78)
	ring.set_instance_shader_parameter("dashes", 10.0)
	ring.set_instance_shader_parameter("spin", 0.15)
	ring.position.y = 0.02
	return {"node": nd, "flag": flag, "cloth": cloth, "ring": ring}

func _nearest_terr(x: float, y: float) -> int:
	var best := -1
	var bd := 1e9
	for t in D.TERRITORIES:
		var d := Vector2(float(t["x"]) - x, float(t["y"]) - y).length_squared()
		if d < bd:
			bd = d
			best = int(t["idx"])
	return best

func _update_battles() -> void:
	var pb = game.get("pending_battle") if "pending_battle" in game else null
	if pb is Dictionary and pb.has("terr"):
		_battle_until[int(pb["terr"])] = _real_t + 0.5
	# attacchi nemici in arrivo verso i territori del giocatore
	_incoming.clear()
	if viewer < 0:
		return
	for d in game.divisions:
		if int(d["owner"]) == viewer or bool(d.get("retreat", false)):
			continue
		var to := int(d["to"])
		if to < 0 or to >= NT or int(game.terr[to]["owner"]) != viewer:
			continue
		var eta := maxf(float(d["total"]) - float(d["t"]), 0.0)
		_incoming[to] = minf(float(_incoming.get(to, 1e9)), eta)

func _update_state_tex() -> void:
	_state_dirty = false
	_state_img.fill(Color(0, 0, 0, 0))
	for i in NT:
		var c := Color(0, 0, 0, 0)
		if i == selected: c.r = 1.0
		if i == hovered: c.g = 1.0
		if target_set.has(i):
			var own: bool = game != null and selected >= 0 and game.terr[i]["owner"] == game.terr[selected]["owner"]
			c.b = 0.5 if own else 1.0
		if marks.has(i): c.a = 1.0
		_state_img.set_pixel(i, 0, c)
	_state_tex.update(_state_img)

## Tipi presenti ordinati per peso (punti vita × attacco).
func _kinds_sorted(f: Dictionary) -> Array:
	var arr: Array = []
	for k in D.UNIT_KEYS:
		var n := int(f.get(k, 0))
		if n <= 0:
			continue
		arr.append([n * float(D.UNITS[k]["hp"]) * (1.0 + float(D.UNITS[k]["atk"]) * 0.1), k])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for e in arr:
		out.append(e[1])
	return out

func _main_kind(f: Dictionary) -> String:
	var ks := _kinds_sorted(f)
	return ks[0] if ks.size() > 0 else ""

const FORMATION := [
	[Vector3(0, 0, 0)],
	[Vector3(-0.62, 0, 0.12), Vector3(0.62, 0, -0.12)],
	[Vector3(0, 0, -0.55), Vector3(-0.72, 0, 0.38), Vector3(0.72, 0, 0.38)],
]

func _faction_of(o: int) -> int:
	if game == null or o < 0 or o >= game.players.size():
		return -1
	return int(game.players[o].get("faction", -1))

func _rebuild_minis(mk: Dictionary, kinds: Array, n: int, col: Color, fac := -1) -> void:
	for c in mk["holder"].get_children():
		c.queue_free()
	if kinds.is_empty() or n <= 0:
		mk["top"] = 0.3
		return
	var top := 0.0
	var form: Array = FORMATION[n - 1]
	for k in n:
		var kind: String = kinds[k] if k < kinds.size() else kinds[0]
		var m := MapProps.miniature(kind, col, 1.0 if k == 0 else 0.85, fac)
		m.position = form[k]
		m.rotation.y = [0.0, 0.35, -0.3][k]
		mk["holder"].add_child(m)
		top = maxf(top, 1.25 if D.UNITS.has(kind) and D.UNITS[kind]["air"] else 0.75)
	mk["top"] = top

func _update_markers(force: bool, delta: float) -> void:
	var dist := camera.dist if camera else 100.0
	var show_minis := dist < DIST_FAR
	var mini_s := clampf(dist * 0.048, 0.95, 2.6)
	var near := dist < DIST_NEAR
	for i in NT:
		var mk: Dictionary = _markers[i]
		var st: Dictionary = game.terr[i]
		var o := int(st["owner"])
		var col := _owner_color(o)
		var f = st["forces"]
		var vis := terr_visible(i)
		if viewer >= 0 and game.has_method("visible_forces"):
			f = game.visible_forces(viewer, i)
		if not vis:
			f = null
		var cnt := -1
		var kinds: Array = []
		if f != null:
			cnt = Data.total_units(f)
			kinds = _kinds_sorted(f)
		var vet := clampi(int(st.get("vet", 0)), 0, 3) if vis else 0
		# animazioni: cattura (cambio di proprietario), promozione (stella in più) e rinforzo (aumento delle unità)
		var captured: bool = int(mk["prev_owner"]) != -99 and o != int(mk["prev_owner"])
		if captured:
			mk["anim"] = "capture"
			mk["anim_t"] = 0.0
			_ov_ring(i, col)
			if _decor != null and o >= 0:
				_decor.note_capture(i)
		elif vis and int(mk["prev_vet"]) >= 0 and vet > int(mk["prev_vet"]):
			mk["anim"] = "reinf"
			mk["anim_t"] = 0.0
			_promote_fx(i, vet)
		elif int(mk["prev_count"]) >= 0 and cnt > int(mk["prev_count"]) and mk["anim"] == "":
			mk["anim"] = "reinf"
			mk["anim_t"] = 0.0
		mk["prev_owner"] = o
		mk["prev_count"] = cnt
		mk["prev_vet"] = vet if vis else -1
		mk["vet"] = vet
		mk["vis"] = vis
		var n := 0
		if cnt > 0:
			n = 1 if cnt < 8 else (2 if cnt < 25 else 3)
			if dist >= DIST_NEAR + 10.0:
				n = 1
		var fac := _faction_of(o)
		var sig := "%s|%d|%s|%d" % [",".join(PackedStringArray(kinds.slice(0, 3))), n, col.to_html(), fac]
		if force or sig != mk["sig"]:
			mk["sig"] = sig
			_rebuild_minis(mk, kinds, n, col, fac)
		mk["color"] = col
		mk["count"] = cnt
		var holder: Node3D = mk["holder"]
		holder.visible = show_minis
		var sc := mini_s
		var y := 0.0
		if mk["anim"] != "":
			mk["anim_t"] = float(mk["anim_t"]) + delta
			var at: float = mk["anim_t"]
			if mk["anim"] == "capture":
				var u := clampf(at / 1.1, 0.0, 1.0)
				if u < 0.55:
					y = 2.2 * (1.0 - pow(u / 0.55, 2.0))
				else:
					y = 0.35 * sin((u - 0.55) / 0.45 * PI)
				sc *= 1.0 + 0.2 * sin(u * PI)
				if u >= 1.0:
					mk["anim"] = ""
			else:
				var u := clampf(at / 0.55, 0.0, 1.0)
				sc *= 1.0 + 0.16 * sin(u * PI)
				y = 0.25 * sin(u * PI)
				if u >= 1.0:
					mk["anim"] = ""
		holder.scale = Vector3.ONE * sc
		holder.position.y = y * mini_s * 0.5
		# edifici 3D: li disegna MapDecor (porti, aeroporti, fabbriche...); qui resta solo il nodo vuoto
		mk["bld"].visible = false
		# stelline dei veterani: in fila davanti alle miniature, girano lentamente come medaglie
		var vets: Node3D = mk["vets"]
		var show_v: bool = vet > 0 and show_minis and dist < DIST_NEAR + 14.0 and cnt > 0
		vets.visible = show_v
		if show_v:
			var vs := mini_s
			if mk["anim"] == "reinf":
				vs *= 1.0 + 0.3 * sin(clampf(float(mk["anim_t"]) / 0.55, 0.0, 1.0) * PI)
			for k in 3:
				var sm: MeshInstance3D = vets.get_child(k)
				sm.visible = k < vet
				if k < vet:
					sm.position = Vector3((k - (vet - 1) * 0.5) * 0.36 * vs, 0.3 * vs + y * mini_s * 0.5, 1.15 * vs)
					sm.scale = Vector3.ONE * 0.14 * vs

## Promozione dei veterani: anello dorato e stelle che salgono dal distintivo.
func _promote_fx(i: int, n: int) -> void:
	_cap_rings.append({"idx": i, "t": 0.0, "col": Color(1.0, 0.82, 0.3)})
	_promos.append({"idx": i, "t": 0.0, "n": n})

func _ov_ring(i: int, col: Color) -> void:
	_cap_rings.append({"idx": i, "t": 0.0, "col": col})

var _cap_rings: Array = []

# ---------------------------------------------------------------- sovrimpressione 2D: distintivi, nomi, continenti
func _layout_overlay(delta: float) -> void:
	_ov2d.t = _real_t
	var rect := get_viewport().get_visible_rect()
	var dist := camera.dist
	var far_t := smoothstep(52.0, 84.0, dist)
	var near_t := 1.0 - smoothstep(24.0, DIST_NEAR + 6.0, dist)
	var show_minis := dist < DIST_FAR
	var r := lerpf(17.0, 13.5, far_t)
	_badge_r = r
	var mini_s := clampf(dist * 0.048, 0.95, 2.6)
	var badges: Array = []
	var items: Array = []
	if game == null:
		_ov2d.badges = []
		_ov2d.divs = []
		_ov2d.conts = []
		_ov2d.rings = []
		_ov2d.queue_redraw()
		return
	for i in NT:
		var mk: Dictionary = _markers[i]
		var st: Dictionary = game.terr[i]
		var o := int(st["owner"])
		var wp: Vector3 = _centers[i]
		var lift := 0.0
		if show_minis and int(mk["count"]) > 0:
			lift = float(mk["top"]) * mini_s
		var base := wp + Vector3(0, lift, 0)
		_badge_vis[i] = false
		if camera.is_position_behind(base):
			continue
		var sp := camera.unproject_position(base)
		if lift > 0.0:
			sp.y -= r + 4.0
		if not rect.grow(60).has_point(sp):
			continue
		_badge_vis[i] = true
		var hq: bool = o >= 0 and int(game.players[o]["hq"]) == i
		var prio := 1.0 + (3.0 if hq else 0.0) + (5.0 if i == selected else 0.0) + (4.0 if i == hovered else 0.0)
		prio += 2.0 if (viewer >= 0 and o == viewer) else 0.0
		prio += minf(float(maxi(int(mk["count"]), 0)) / 25.0, 2.0)
		var cnt: int = mk["count"]
		# edifici e segnali
		var chips: Array = []
		var blist: Array = st["buildings"] if st["buildings"] != null else []
		var sab := float(st.get("sabotage", 0.0)) > 0.0
		for key in blist:
			if D.BUILDINGS.has(String(key)):
				chips.append([String(D.BUILDINGS[String(key)]["icon"]), Color(1.0, 0.5, 0.35) if sab else Color(0.95, 0.86, 0.55)])
		var dots: Array = []
		var tags := PackedStringArray()
		if sab:
			dots.append(Color(1.0, 0.5, 0.15))
			tags.append("SABOTATO")
		if float(st.get("unrest", 0.0)) > 0.0:
			dots.append(Color(0.95, 0.3, 0.3))
			tags.append("OCCUPATO")
		var unsup: bool = st.get("supplied", true) == false and o >= 0 and (viewer < 0 or o == viewer)
		if unsup:
			dots.append(Color(1.0, 0.8, 0.2))
			tags.append("SENZA RIFORNIMENTI")
		var pop := 0.0
		if mk["anim"] != "":
			var at: float = mk["anim_t"]
			pop = sin(clampf(at / (1.1 if mk["anim"] == "capture" else 0.55), 0.0, 1.0) * PI)
		var eta := ""
		var warn := _incoming.has(i)
		if warn:
			eta = "%ds" % int(ceil(float(_incoming[i])))
		var vis: bool = mk["vis"]
		var text := "?" if cnt < 0 else str(cnt)
		if not vis:
			# territorio velato: stima approssimata, niente edifici né segnali
			var est := _estimate(i)
			text = "≈%d" % est if est >= 0 else "?"   # "≈": il "~" piccolo sembrava un segno meno
			chips = []
			dots = []
			tags = PackedStringArray()
		# patto: icona sui distintivi del partner (spettatore: territori lungo un confine di patto)
		var pact := false
		if o >= 0 and not _pact_pairs.is_empty():
			if viewer >= 0:
				pact = o != viewer and _has_pact(viewer, o)
			else:
				for a in D.TERRITORIES[i]["adj"]:
					if _has_pact(o, int(game.terr[a]["owner"])):
						pact = true
						break
		var b := {"idx": i, "anchor": sp, "pos": sp + (_badge_off[i] as Vector2), "r": r, "col": _owner_color(o),
			"fog": not vis, "vet": int(mk["vet"]), "pact": pact, "pact_s": lerpf(9.5, 6.5, far_t),
			"text": text, "hq": hq, "alpha": 1.0, "pop": pop, "sel": i == selected, "hov": i == hovered,
			"warn": warn, "eta": eta, "battle": float(_battle_until.get(i, -1.0)) > _real_t,
			"chips": chips, "chip_alpha": 1.0 - far_t, "dots": dots, "prio": prio,
			"name": String(D.TERRITORIES[i]["name"]).to_upper(), "name_alpha": 0.0, "name_pos": sp, "name_size": 13,
			"tags": "", "tagstr": " · ".join(tags)}
		badges.append(b)
	# sfoltimento: spinta reciproca pesata sulla priorità + richiamo elastico verso la posizione reale
	var nbad := badges.size()
	for it in 6:
		for a in nbad:
			var A: Dictionary = badges[a]
			for c in range(a + 1, nbad):
				var B: Dictionary = badges[c]
				var dv: Vector2 = B["pos"] - A["pos"]
				var need: float = A["r"] + B["r"] + 3.0
				var L := dv.length()
				if L >= need:
					continue
				if L < 0.01:
					dv = Vector2(1, 0.3) if (int(A["idx"]) < int(B["idx"])) else Vector2(-1, -0.3)
					L = dv.length()
				var push := (need - L)
				var wa: float = B["prio"] / (A["prio"] + B["prio"])
				var nrm := dv / L
				A["pos"] -= nrm * push * wa
				B["pos"] += nrm * push * (1.0 - wa)
		for b in badges:
			b["pos"] = (b["pos"] as Vector2).lerp(b["anchor"], 0.06)
	for b in badges:
		var i: int = b["idx"]
		var off: Vector2 = b["pos"] - b["anchor"]
		_badge_off[i] = (_badge_off[i] as Vector2).lerp(off, minf(1.0, delta * 12.0)) if delta > 0 else off
		b["pos"] = b["anchor"] + _badge_off[i]
		_badge_pos[i] = b["pos"]
	# nomi: piazzamento goloso per priorità, senza collisioni con distintivi e altri nomi
	var occupied: Array = []
	for b in badges:
		var rr: float = b["r"] + 2.0
		occupied.append(Rect2(b["pos"] - Vector2(rr, rr), Vector2(rr, rr) * 2.0))
		if (b["chips"] as Array).size() > 0 and b["chip_alpha"] > 0.3:
			var w: float = (b["chips"] as Array).size() * 15.0
			occupied.append(Rect2(b["pos"] + Vector2(-w * 0.5, rr + 2 + (5.0 if int(b["vet"]) > 0 else 0.0)), Vector2(w, 13)))
	var order := badges.duplicate()
	order.sort_custom(func(x, y): return x["prio"] > y["prio"])
	var fm := MapOverlay.font(500)
	var name_vis := lerpf(1.0, 0.0, far_t)
	var fs := int(round(lerpf(12.0, 14.0, near_t)))
	for b in order:
		var hi: bool = b["sel"] or b["hov"]
		var want := name_vis if show_names else 0.0
		if hi:
			want = 1.0
		if want <= 0.02:
			continue
		var nm: String = b["name"]
		var tw := fm.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		var has_tags: bool = b["tagstr"] != "" and near_t > 0.3
		var hgt := float(fs + 4) * (2.0 if has_tags else 1.0)
		var p: Vector2 = b["pos"]
		var rr: float = b["r"]
		var chip_h := 15.0 if ((b["chips"] as Array).size() > 0 and b["chip_alpha"] > 0.3) else 0.0
		if int(b["vet"]) > 0:
			chip_h += 5.0
		var cands := [p + Vector2(0, rr + chip_h + 4.0 + fs * 0.5), p + Vector2(0, -rr - 6.0 - fs * 0.5 - (8.0 if b["hq"] else 0.0)),
			p + Vector2(rr + 6.0 + tw * 0.5, 0), p + Vector2(-rr - 6.0 - tw * 0.5, 0)]
		var placed := false
		for cp in cands:
			var nr := Rect2(cp - Vector2(tw * 0.5, fs * 0.5 + 1.0), Vector2(tw, hgt))
			var ok := true
			if not hi:
				for q in occupied:
					if (q as Rect2).intersects(nr):
						ok = false
						break
			if ok:
				b["name_pos"] = cp
				b["name_alpha"] = want
				b["name_size"] = fs + (1 if hi else 0)
				b["tags"] = b["tagstr"] if has_tags else ""
				occupied.append(nr)
				placed = true
				break
		if not placed:
			b["name_alpha"] = 0.0
	# anelli di cattura (2D)
	var rings: Array = []
	for k in range(_cap_rings.size() - 1, -1, -1):
		var cr: Dictionary = _cap_rings[k]
		cr["t"] = float(cr["t"]) + delta
		if cr["t"] > 1.2:
			_cap_rings.remove_at(k)
			continue
		var i: int = cr["idx"]
		if _badge_vis[i]:
			var u: float = cr["t"] / 1.2
			var c: Color = cr["col"].lightened(0.3)
			c.a = (1.0 - u) * 0.95
			rings.append({"pos": _badge_pos[i], "r": r + 4.0 + u * 40.0, "col": c, "w": 3.0 * (1.0 - u) + 1.0})
	# continenti
	var conts: Array = []
	var ca := smoothstep(50.0, 85.0, dist)
	if ca > 0.01:
		for ck in D.CONT_KEYS:
			var lp: Vector2 = CONT_LABEL[ck]
			var w3 := Vector3(lp.x * SCALE - HALF.x, 0.2, lp.y * SCALE - HALF.y)
			if camera.is_position_behind(w3):
				continue
			var o := int(_cont_owner.get(ck, -1))
			var sub := "+%d RINFORZI" % int(D.CONTINENTS[ck]["bonus"])
			if o >= 0:
				sub = "CONTROLLATO · " + _player_short(o)
			conts.append({"pos": camera.unproject_position(w3), "text": MapOverlay.spaced(String(D.CONTINENTS[ck]["name"]).to_upper()),
				"sub": sub, "owned": o >= 0, "col": _owner_color(o), "alpha": ca})
	# divisioni in viaggio
	var dl: Array = []
	for id in _divs:
		var e: Dictionary = _divs[id]
		var d: Dictionary = e["d"]
		var node: Node3D = e["node"]
		if not node.visible:
			continue
		var lift := 0.0
		if show_minis:
			var naval_up: bool = e["ships"] != null and e["ships"].visible
			lift = (1.7 if naval_up else 0.9) * clampf(_scale_s, 0.5, 2.6)
		var pw := node.position + Vector3(0, lift, 0)
		if camera.is_position_behind(pw):
			continue
		var sp := camera.unproject_position(pw)
		if not rect.grow(30).has_point(sp):
			continue
		var ahead := camera.unproject_position(node.position + e["dir"])
		var hostile: bool = viewer >= 0 and int(d["owner"]) != viewer and _incoming.has(int(d["to"]))
		if show_minis:
			sp.y -= 12.0
		dl.append({"pos": sp, "dir": ahead - camera.unproject_position(node.position), "col": _owner_color(int(d["owner"])),
			"text": str(e["n"]), "alpha": 0.6 if bool(d.get("retreat", false)) else 1.0, "hostile": hostile,
			"naval": e["ships"] != null and e["ships"].visible, "vet": clampi(int(d.get("vet", 0)), 0, 3),
			"big": 1.0 + 0.3 * smoothstep(40.0, 80.0, dist)})
	# promozioni dei veterani: stelle che salgono dal distintivo
	var promos: Array = []
	for k in range(_promos.size() - 1, -1, -1):
		var pr: Dictionary = _promos[k]
		pr["t"] = float(pr["t"]) + delta
		if pr["t"] > 1.8:
			_promos.remove_at(k)
			continue
		var i: int = pr["idx"]
		if _badge_vis[i]:
			promos.append({"pos": _badge_pos[i], "u": float(pr["t"]) / 1.8, "n": int(pr["n"]), "r": r})
	_ov2d.promos = promos
	_ov2d.badges = badges
	_ov2d.divs = dl
	_ov2d.conts = conts
	_ov2d.rings = rings
	_ov2d.plate = {}
	if _own_game and hovered >= 0 and _badge_vis[hovered]:
		var o := int(game.terr[hovered]["owner"])
		var T: Dictionary = D.TERRITORIES[hovered]
		_ov2d.plate = {"pos": (_badge_pos[hovered] as Vector2) + Vector2(r + 14.0, -20.0), "title": String(T["name"]).to_upper(),
			"sub": "%s · %s · %s" % [_player_short(o), D.CONTINENTS[T["c"]]["name"], D.TERRAINS[T["ter"]]["name"]], "col": _owner_color(o)}
		if viewer >= 0 and o >= 0 and _has_pact(viewer, o):
			var left := maxf(_pact_until(viewer, o) - float(game.time), 0.0)
			_ov2d.plate["sub"] += " · Patto %d:%02d" % [int(left) / 60, int(left) % 60]
		if not terr_visible(hovered):
			_ov2d.plate["sub"] += " · Nella nebbia"
	_ov2d.queue_redraw()

func _player_short(o: int) -> String:
	if o < 0 or game == null or o >= game.players.size():
		return "Neutrale"
	var P: Dictionary = game.players[o]
	if P.has("fac") and P["fac"] is Dictionary and P["fac"].has("short"):
		return String(P["fac"]["short"])
	return String(P.get("name", "?"))

# ---------------------------------------------------------------- divisioni
func _is_wrap(a: int, b: int) -> bool:
	var ia: String = D.TERRITORIES[a]["id"]
	var ib: String = D.TERRITORIES[b]["id"]
	for w in D.WRAP_LINKS:
		if (w[0] == ia and w[1] == ib) or (w[0] == ib and w[1] == ia):
			return true
	return false

## Posizione della divisione lungo il percorso: archi sul mare, quota per i mezzi aerei.
func _div_path_point(d: Dictionary, f: float) -> Vector3:
	var A: Dictionary = D.TERRITORIES[int(d["from"])]
	var B: Dictionary = D.TERRITORIES[int(d["to"])]
	var ax: float = A["x"]
	var ay: float = A["y"]
	var bx: float = B["x"]
	var by: float = B["y"]
	if _is_wrap(int(d["from"]), int(d["to"])) and absf(bx - ax) > D.MAP_W / 2.0:
		bx += -D.MAP_W if bx > ax else D.MAP_W
	var x := lerpf(ax, bx, f)
	var y := lerpf(ay, by, f)
	var L := Vector2(bx - ax, by - ay).length()
	var air := _div_air(d)
	if bool(d.get("sea", false)) and not air:
		var perp := Vector2(-(by - ay), bx - ax).normalized()
		var bulge := sin(PI * f) * L * 0.14
		x += perp.x * bulge
		y += perp.y * bulge
	x = fposmod(x, D.MAP_W)
	var p := map_to_world(x, y)
	if air:
		p.y = maxf(p.y, 0.0) + 2.2 + sin(PI * f) * L * SCALE * 0.10
	elif bool(d.get("sea", false)):
		p.y = maxf(p.y, 0.02)
	return p

func _div_air(d: Dictionary) -> bool:
	if bool(d.get("airlift", false)):
		return true
	var f: Dictionary = d["forces"]
	var ground := 0
	var air := 0
	for k in D.UNIT_KEYS:
		if D.UNITS[k]["air"]:
			air += int(f.get(k, 0))
		else:
			ground += int(f.get(k, 0))
	return ground == 0 and air > 0

func _update_divisions(_delta: float) -> void:
	var seen := {}
	var show_minis := camera.dist < DIST_FAR
	for d in game.divisions:
		var id := int(d["id"])
		seen[id] = true
		var e: Dictionary = _divs.get(id, {})
		if e.is_empty():
			e = _make_division(d)
			_divs[id] = e
			if _decor != null and int(d["to"]) >= 0 and int(d["to"]) < NT and int(game.terr[int(d["to"])]["owner"]) != int(d["owner"]):
				_decor.note_attack(int(d["from"]), int(d["to"]))
		e["d"] = d
		var f := clampf(float(d["t"]) / maxf(float(d["total"]), 0.001), 0.0, 1.0)
		var p := _div_path_point(d, f)
		var p2 := _div_path_point(d, minf(f + 0.02, 1.0))
		var node: Node3D = e["node"]
		node.position = p
		node.visible = _div_visible(d)
		if e["ships"] != null:
			var mp := world_to_map(p)
			var wet := MapGen.height_at(data, mp.x, mp.y) < 0.02
			e["ships"].visible = wet
			e["land"].visible = not wet
			var foam: bool = wet and node.visible and show_minis
			if foam != bool(e.get("foam", false)):
				e["foam"] = foam
				for w in e["wakes"]:
					for c in (w as Node).get_children():
						if c is CPUParticles3D:
							(c as CPUParticles3D).emitting = foam
		var dir := p2 - p
		dir.y = 0
		if dir.length() > 0.0001 and absf(dir.x) < 50.0:
			node.rotation.y = atan2(-dir.x, -dir.z)
			e["dir"] = dir.normalized()
		var s := clampf(_scale_s, 0.5, 2.6)
		e["models"].scale = Vector3.ONE * maxf(s * 1.3, 1.0)
		e["models"].visible = show_minis
		# beccheggio delle navi
		if e["ships"] != null and e["ships"].visible:
			e["ships"].rotation.z = sin(_real_t * 1.3 + id) * 0.05
			e["ships"].position.y = sin(_real_t * 1.7 + id) * 0.02
		e["n"] = Data.total_units(d["forces"])
	for id in _divs.keys():
		if not seen.has(id):
			_divs[id]["node"].queue_free()
			_divs.erase(id)

func _make_division(d: Dictionary) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var models := Node3D.new()
	node.add_child(models)
	var col := _owner_color(int(d["owner"]))
	var air := _div_air(d)
	var sea := bool(d.get("sea", false)) and not air
	var kinds := _kinds_sorted(d["forces"])
	var kind: String = kinds[0] if kinds.size() > 0 else "inf"
	if air and not D.UNITS[kind]["air"]:
		kind = "jet"
	if not air and kind == "inf":
		kind = "truck"
	var n := Data.total_units(d["forces"])
	var cnt := clampi(int(ceil(n / 6.0)), 1, 3)
	var land := Node3D.new()
	models.add_child(land)
	var ships: Node3D = null
	var wakes: Array = []
	for k in cnt:
		var kk := kind
		if k > 0 and kinds.size() > k and not air:
			kk = kinds[k] if kinds[k] != "inf" else "truck"
		var m := MapProps.miniature(kk, col, 0.75, _faction_of(int(d["owner"])))
		if air:
			m.position = Vector3((k - (cnt - 1) * 0.5) * 0.9, 0, k % 2 * 0.6)
		else:
			m.position = Vector3(0, 0, k * 0.95)
		land.add_child(m)
	if sea:
		# convoglio navale (pedine navali di UnitModels con scia di schiuma Vfx; segnaposto se mancano)
		ships = Node3D.new()
		models.add_child(ships)
		var nsh := clampi(int(ceil(n / 10.0)), 1, 3)
		var um = MapProps.unit_models()
		var naval: bool = um != null and MapProps.um_has("ship") and MapProps.um_has("transport")
		var vfx = MapProps.global_class_script("Vfx")
		var form := [Vector3(0, 0, 0), Vector3(0.85, 0, 2.0), Vector3(-0.85, 0, 2.0)]
		for k in nsh:
			var hold := Node3D.new()
			var skind := "ship" if k == 0 and n >= 12 else "transport"
			var sh: Node3D
			if naval:
				sh = um.miniature(skind, col)
				sh.scale = Vector3.ONE * 0.62
			else:
				sh = MapProps.ship(col, skind)
			hold.add_child(sh)
			hold.position = form[k]
			ships.add_child(hold)
			if vfx != null and vfx.has_method("wake"):
				wakes.append(vfx.wake(hold, Vector3(0, 0.1, 1.0), Vector3(0, 0, -1), 0.03))
		if wakes.is_empty():
			# scia di riserva (texture)
			var wake := MeshInstance3D.new()
			var qm := PlaneMesh.new()
			qm.size = Vector2(0.6, 2.4 + nsh * 1.4)
			wake.mesh = qm
			wake.position = Vector3(0, 0.03, 1.1 + nsh * 0.7)
			var wm := StandardMaterial3D.new()
			wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.albedo_texture = MapProps.wake_texture()
			wm.albedo_color = Color(0.9, 0.97, 1.0, 0.3)
			wake.material_override = wm
			wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ships.add_child(wake)
		else:
			for w in wakes:
				for c in (w as Node).get_children():
					if c is CPUParticles3D:
						(c as CPUParticles3D).emitting = false
		ships.visible = false
	return {"node": node, "models": models, "n": n, "land": land, "ships": ships, "d": d, "dir": Vector3(0, 0, -1), "wakes": wakes, "foam": false}

# ---------------------------------------------------------------- frecce dei turni (FASE 6)
## Le mosse a turni sono istantanee nel nucleo: qui una freccia che si allunga da `from` a `to` con una colonna
## di pedine che la percorre (stessi modelli delle divisioni), poi resta visibile un attimo e svanisce.
## kind: "attack" (freccia rossa vistosa) | "move" (colore della fazione). Chiamata dall'interfaccia sui segnali.
var _turn_anims: Array = []
const TURN_HOLD := 1.4

func turn_arrow(from: int, to: int, owner: int, kind: String = "attack", dur: float = 0.9, forces = null) -> void:
	if from < 0 or to < 0 or from >= NT or to >= NT or from == to:
		return
	var f: Dictionary = forces if forces is Dictionary and Data.total_units(forces) > 0 else {"inf": 4, "tank": 2}
	var sea: bool = D.TERRITORIES[from]["sea"].has(to) if D.TERRITORIES[from].has("sea") else false
	var d := {"id": -1, "owner": owner, "from": from, "to": to, "forces": f, "t": 0.0, "total": 1.0, "sea": sea, "airlift": false}
	var e := _make_division(d)
	e["models"].visible = camera.dist < DIST_FAR
	if kind == "attack" and _decor != null:
		_decor.note_attack(from, to)
	_turn_anims.append({"d": d, "kind": kind, "t": 0.0, "dur": maxf(0.2, dur), "node": e["node"], "e": e, "owner": owner})
	while _turn_anims.size() > 6:
		var old: Dictionary = _turn_anims.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()

func clear_turn_anims() -> void:
	for a in _turn_anims:
		if is_instance_valid(a["node"]):
			a["node"].queue_free()
	_turn_anims.clear()

func turn_anims_active() -> bool:
	return not _turn_anims.is_empty()

func _update_turn_anims(delta: float) -> void:
	var keep: Array = []
	for a in _turn_anims:
		a["t"] = float(a["t"]) + delta
		var f := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		if float(a["t"]) > float(a["dur"]) + TURN_HOLD:
			node.queue_free()
			continue
		var d: Dictionary = a["d"]
		var fe := 1.0 - pow(1.0 - f, 2.0)
		var p := _div_path_point(d, fe)
		var p2 := _div_path_point(d, minf(fe + 0.03, 1.0))
		node.position = p
		var dir := p2 - p
		dir.y = 0
		if dir.length() > 0.0001 and absf(dir.x) < 50.0:
			node.rotation.y = atan2(-dir.x, -dir.z)
		var e: Dictionary = a["e"]
		e["models"].scale = Vector3.ONE * maxf(clampf(_scale_s, 0.5, 2.6) * 1.3, 1.0)
		var dup := false
		for dv in game.divisions:
			if int(dv["from"]) == int(d["from"]) and int(dv["to"]) == int(d["to"]):
				dup = true   # il nucleo anima già la colonna: qui resta solo la freccia
				break
		e["models"].visible = camera.dist < DIST_FAR and not dup
		node.visible = f < 1.0 or float(a["t"]) < float(a["dur"]) + 0.5
		if e["ships"] != null:
			var mp := world_to_map(p)
			var wet := MapGen.height_at(data, mp.x, mp.y) < 0.02
			e["ships"].visible = wet
			e["land"].visible = not wet
		keep.append(a)
	_turn_anims = keep

func _draw_turn_anims(s: float) -> void:
	for a in _turn_anims:
		var d: Dictionary = a["d"]
		if _is_wrap(int(d["from"]), int(d["to"])):
			continue
		var f := clampf(float(a["t"]) / float(a["dur"]), 0.0, 1.0)
		var fe := 1.0 - pow(1.0 - f, 2.0)
		var fade := 1.0 - clampf((float(a["t"]) - float(a["dur"])) / TURN_HOLD, 0.0, 1.0)
		if fe < 0.04 or fade <= 0.0:
			continue
		var pts := PackedVector3Array()
		var steps := 22
		for k in steps + 1:
			var u := fe * float(k) / steps
			var p := _div_path_point(d, u)
			var mp := world_to_map(p)
			p.y = maxf(p.y, MapGen.height_at(data, mp.x, mp.y)) + 0.22
			pts.append(p)
		if String(a["kind"]) == "attack":
			var c := Color(1.0, 0.26, 0.16, 0.95 * fade)
			_arrow(pts, 0.36 * s, c, 0.9 / s, 2.4, 1.3 * s)
		else:
			var c := _owner_color(int(a["owner"])).lightened(0.3)
			c.a = 0.9 * fade
			_arrow(pts, 0.24 * s, c, 1.2 / s, 1.2, 0.9 * s)

# ---------------------------------------------------------------- effetti
func _update_effects() -> void:
	var now := float(game.time)
	var live := {}
	for e in game.effects:
		var key := "%s|%.3f|%.1f|%.1f" % [e["type"], float(e["born"]), float(e["x"]), float(e["y"])]
		var born := float(e["born"])
		var dur := float(e.get("dur", 1.6))
		var p := (now - born) / maxf(dur, 0.01)
		if p < 0.0 or p > 1.0:
			continue
		live[key] = true
		var fx: Dictionary = _fx.get(key, {})
		if fx.is_empty():
			fx = _spawn_fx(e)
			_fx[key] = fx
		_animate_fx(fx, e, p)
	for k in _fx.keys():
		if not live.has(k):
			if is_instance_valid(_fx[k]["node"]):
				_fx[k]["node"].queue_free()
			_fx.erase(k)

func _spawn_fx(e: Dictionary) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var pos := map_to_world(float(e["x"]), float(e["y"]))
	node.position = pos
	var fx := {"node": node, "type": String(e["type"])}
	var vfx = MapProps.global_class_script("Vfx")
	match String(e["type"]):
		"explosion":
			var sm := SphereMesh.new()
			sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 16; sm.rings = 8
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.15)
			m.emission_energy_multiplier = 3.0
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
			fx["ball"] = mi
			fx["mat"] = m
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.3)
			light.omni_range = 6.0
			light.position = Vector3(0, 1.0, 0)
			node.add_child(light)
			fx["light"] = light
			fx["ring"] = _ring(node, 1.0, Color(1.0, 0.85, 0.5, 0.9), 0.9)
			fx["ring"].visible = true
			if vfx != null and vfx.has_method("explosion") and camera.dist < DIST_FAR:
				vfx.explosion(self, pos + Vector3(0, 0.2, 0), 1.6)
		"capture":
			fx["ring"] = _ring(node, 1.0, Color(1, 1, 0.9, 0.9), 0.86)
			fx["ring"].visible = true
			fx["ring"].set_instance_shader_parameter("fill", 0.5)
			fx["ring"].position.y = 0.3
		"battle":
			var ti := _nearest_terr(float(e["x"]), float(e["y"]))
			if ti >= 0:
				_battle_until[ti] = _real_t + 5.0
			fx["ring"] = _ring(node, 2.2, Color(1.0, 0.3, 0.2, 0.9), 0.84)
			fx["ring"].visible = true
			fx["ring"].set_instance_shader_parameter("pulse", 1.0)
			fx["ring"].set_instance_shader_parameter("dashes", 8.0)
			fx["ring"].set_instance_shader_parameter("spin", 0.5)
			fx["ring"].position.y = 0.4
			if vfx != null and vfx.has_method("smoke") and camera.dist < DIST_FAR:
				vfx.smoke(self, pos + Vector3(0, 0.1, 0), 6.0)
		"missile":
			var sm := SphereMesh.new()
			sm.radius = 0.35; sm.height = 0.7
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.95, 0.75)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.5)
			m.emission_energy_multiplier = 6.0
			mi.material_override = m
			node.add_child(mi)
			fx["ball"] = mi
			node.position = Vector3.ZERO
	return fx

func _missile_point(e: Dictionary, u: float) -> Vector3:
	var a := map_to_world(float(e["x"]), float(e["y"]))
	var b := map_to_world(float(e.get("x2", e["x"])), float(e.get("y2", e["y"])))
	var p := a.lerp(b, u)
	p.y = lerpf(a.y, b.y, u) + sin(PI * u) * (a.distance_to(b) * 0.3 + 2.0) + 0.3
	return p

func _animate_fx(fx: Dictionary, e: Dictionary, p: float) -> void:
	match fx["type"]:
		"explosion":
			var r := 0.7 + p * 3.0
			fx["ball"].scale = Vector3.ONE * r * (1.0 - p * 0.4)
			fx["mat"].albedo_color = Color(1.0, 0.7 - p * 0.5, 0.25, (1.0 - p) * 0.85)
			fx["mat"].emission_energy_multiplier = 4.0 * (1.0 - p)
			fx["light"].light_energy = 6.0 * (1.0 - p)
			fx["ring"].scale = Vector3(1, 1, 1) * (0.5 + p * 4.0)
			fx["ring"].set_instance_shader_parameter("ring_color", Color(1.0, 0.85, 0.5, 1.0 - p))
		"capture":
			fx["ring"].scale = Vector3.ONE * (1.0 + p * 4.0)
			fx["ring"].set_instance_shader_parameter("ring_color", Color(1, 1, 0.9, (1.0 - p) * 0.95))
		"battle":
			fx["ring"].set_instance_shader_parameter("ring_color", Color(1.0, 0.3, 0.2, (1.0 - p * 0.7)))
		"missile":
			var q := minf(1.0, p * 1.15)
			fx["ball"].position = _missile_point(e, q)
			fx["ball"].visible = q < 1.0
			fx["q"] = q

# ---------------------------------------------------------------- linee in sovrimpressione
func _ribbon(im: ImmediateMesh, pts: PackedVector3Array, width: float, col: Color, dash: float, speed: float, fade_ends := false) -> void:
	if pts.size() < 2:
		return
	_ov_ensure(im)
	var dist := 0.0
	var n := pts.size()
	for k in n - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		var L := a.distance_to(b)
		if dir.length() < 0.0001:
			continue
		var side := Vector3(-dir.z, 0, dir.x).normalized() * width * 0.5
		var ca := col
		var cb := col
		if fade_ends:
			ca.a *= minf(1.0, float(k) / 3.0)
			cb.a *= minf(1.0, float(k + 1) / 3.0)
		var v := [[a - side, Vector2(dist, 0), ca], [a + side, Vector2(dist, 1), ca], [b + side, Vector2(dist + L, 1), cb], [b - side, Vector2(dist + L, 0), cb]]
		for q in [0, 1, 2, 0, 2, 3]:
			im.surface_set_color(v[q][2])
			im.surface_set_uv(v[q][1])
			im.surface_set_uv2(Vector2(dash, speed))
			im.surface_add_vertex(v[q][0])
		dist += L

func _arrow_head(im: ImmediateMesh, tip: Vector3, dir: Vector3, size: float, col: Color) -> void:
	dir.y = 0
	if dir.length() < 0.0001:
		return
	dir = dir.normalized()
	_ov_ensure(im)
	var side := Vector3(-dir.z, 0, dir.x)
	var base := tip - dir * size
	for v in [tip, base + side * size * 0.6, base - side * size * 0.6]:
		im.surface_set_color(col)
		im.surface_set_uv(Vector2(0, 0.5))
		im.surface_set_uv2(Vector2(0, 0))
		im.surface_add_vertex(v)

func _ov_ensure(im: ImmediateMesh) -> void:
	if not _ov_open:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_ov_open = true

func _arc_points(a: Vector3, b: Vector3, lift: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in n + 1:
		var u := float(k) / n
		var p := a.lerp(b, u)
		p.y = lerpf(a.y, b.y, u) + sin(PI * u) * lift
		pts.append(p)
	return pts

## Freccia completa (nastro + punta), con un bordo scuro sotto per staccarla dal fondo.
func _arrow(pts: PackedVector3Array, width: float, col: Color, dash: float, speed: float, head: float) -> void:
	if pts.size() < 3:
		return
	var cut := pts.size() - 2
	var tip := pts[pts.size() - 1]
	var trimmed := pts.slice(0, cut)
	var dark := Color(0.02, 0.02, 0.03, col.a * 0.55)
	_ribbon(_overlay_top, trimmed, width * 1.9, dark, 0.0, 0.0)
	_arrow_head(_overlay_top, tip + (tip - pts[cut - 1]).normalized() * head * 0.12, tip - pts[cut - 1], head * 1.25, dark)
	_ribbon(_overlay_top, trimmed, width, col, dash, speed)
	_arrow_head(_overlay_top, tip, tip - pts[cut - 1], head, col)

func _draw_overlay() -> void:
	_overlay_top.clear_surfaces()
	_ov_open = false
	var s := clampf(_scale_s, 0.5, 2.6)
	# bersagli validi dal territorio selezionato
	if selected >= 0 and targets.size() > 0:
		var A: Vector3 = _centers[selected] + Vector3(0, 0.25, 0)
		for tg in targets:
			var ti := int(tg["idx"])
			if ti < 0 or ti >= NT or bool(tg.get("airlift", false)):
				continue
			if _is_wrap(selected, ti):
				continue
			var B: Vector3 = _centers[ti] + Vector3(0, 0.25, 0)
			var own: bool = game != null and game.terr[ti]["owner"] == game.terr[selected]["owner"]
			var c := Color(0.45, 0.88, 1.0, 0.5) if own else Color(1.0, 0.62, 0.25, 0.55)
			if ti == hovered:
				c.a = 0.95
			_ribbon(_overlay_top, _arc_points(A, B, A.distance_to(B) * 0.18 + 0.5, 20), 0.13 * s, c, 1.4 / s, 0.8)
	if game != null:
		# percorsi delle divisioni (gli attacchi nemici verso di noi: frecce rosse vistose)
		for d in game.divisions:
			var f := clampf(float(d["t"]) / maxf(float(d["total"]), 0.001), 0.0, 1.0)
			if _is_wrap(int(d["from"]), int(d["to"])):
				continue
			if _divs.has(int(d["id"])) and not (_divs[int(d["id"])]["node"] as Node3D).visible:
				continue
			var hostile: bool = viewer >= 0 and int(d["owner"]) != viewer and _incoming.has(int(d["to"])) and not bool(d.get("retreat", false))
			var pts := PackedVector3Array()
			var steps := 18
			for k in steps + 1:
				var u := lerpf(f, 1.0, float(k) / steps)
				var p := _div_path_point(d, u)
				var mp := world_to_map(p)
				p.y = maxf(p.y, MapGen.height_at(data, mp.x, mp.y)) + 0.15
				pts.append(p)
			if hostile:
				var pul := 0.75 + 0.25 * sin(_real_t * 6.0)
				_arrow(pts, 0.34 * s, Color(1.0, 0.22, 0.14, 0.95 * pul), 0.9 / s, 2.2, 1.2 * s)
			else:
				var c := _owner_color(int(d["owner"])).lightened(0.15)
				c.a = 0.8
				_arrow(pts, 0.12 * s, c, 1.2 / s, 0.6, 0.4 * s)
		# missili: scia
		for key in _fx:
			var fx: Dictionary = _fx[key]
			if fx["type"] != "missile" or not fx.has("q"):
				continue
			var e = null
			for ee in game.effects:
				if ee["type"] == "missile" and "%s|%.3f|%.1f|%.1f" % [ee["type"], float(ee["born"]), float(ee["x"]), float(ee["y"])] == key:
					e = ee
			if e == null:
				continue
			var q: float = fx["q"]
			var pts := PackedVector3Array()
			var n := 30
			for k in n + 1:
				pts.append(_missile_point(e, q * k / n))
			_ribbon(_overlay_top, pts, 0.22 * s, Color(1.0, 0.55, 0.35, 0.8), 0.0, 0.0, true)
	if game != null:
		_draw_turn_anims(s)
	# freccia di trascinamento
	if drag_active and drag_from >= 0:
		var A: Vector3 = _centers[drag_from] + Vector3(0, 0.3, 0)
		var B := drag_to
		var ok := false
		if hovered >= 0 and target_set.has(hovered):
			B = _centers[hovered]
			ok = true
		else:
			for ti in target_set:
				if _centers[ti].distance_to(drag_to) < 2.5:
					B = _centers[ti]
					ok = true
		B.y += 0.3
		var c := Color(1.0, 0.78, 0.3, 0.95) if ok else Color(0.85, 0.85, 0.85, 0.7)
		var L := A.distance_to(B)
		if L > 0.5:
			_arrow(_arc_points(A, B, L * 0.22 + 0.4, 24), 0.42 * s, c, 0.0 if ok else 1.0 / s, 1.0, 1.2 * s)
	if _ov_open:
		_overlay_top.surface_end()
		_ov_open = false

# ====================================================================== input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var idx := territory_at_screen(mm.position)
		if idx != hovered:
			hovered = idx
			_state_dirty = true
			territory_hovered.emit(idx)
		if _pressing and _press_idx >= 0 and (drag_active or mm.position.distance_to(_press_pos) > DRAG_PX):
			var hit = _ray_terrain(mm.position)
			var wp: Vector3 = hit if hit != null else _centers[_press_idx]
			set_drag(_press_idx, wp)
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
				_press_idx = territory_at_screen(mb.position)
			else:
				var idx := territory_at_screen(mb.position)
				if drag_active and _pressing:
					var from := drag_from
					clear_drag()
					drag_released.emit(from, idx)
				elif _pressing:
					territory_clicked.emit(idx, MOUSE_BUTTON_LEFT, mb.shift_pressed)
				_pressing = false
				_press_idx = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			territory_clicked.emit(territory_at_screen(mb.position), MOUSE_BUTTON_RIGHT, mb.shift_pressed)

## Ray marching sulla heightmap: restituisce il punto del rilievo (o del mare a quota 0) o null.
func _ray_terrain(pos: Vector2):
	if camera == null:
		return null
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	if d.y >= -0.0001:
		return null
	var top := 2.5
	var t := maxf(0.0, (o.y - top) / -d.y)
	var tmax := (o.y + 0.01) / -d.y
	var step := 0.2
	var prev := t
	while t <= tmax + step:
		var p := o + d * t
		var m := world_to_map(p)
		var h := maxf(MapGen.height_at(data, m.x, m.y), 0.0)
		if p.y <= h:
			var lo := prev
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				var pm := o + d * mid
				var mm := world_to_map(pm)
				if pm.y <= maxf(MapGen.height_at(data, mm.x, mm.y), 0.0):
					hi = mid
				else:
					lo = mid
			return o + d * hi
		prev = t
		t += step
	return null
