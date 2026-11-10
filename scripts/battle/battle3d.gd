class_name Battle3D
extends Node3D
## Battaglia tattica 3D: vista e comandi RTS sopra BattleSim (logica headless).
## API: start(setup: Dictionary); signal finished(result: Dictionary). Esc NON chiude la battaglia.

signal finished(result: Dictionary)

const S := BattleTerrain.S
const ALT := {"heli": 22.0, "jet": 58.0, "drone": 13.0}
const DEMOS := {
	"urbano": [{"inf": 22, "tank": 8, "art": 4, "heli": 2}, {"inf": 22, "tank": 7, "aa": 3, "art": 2}, 3, 4, 0],
	"grande": [{"inf": 24, "tank": 12, "art": 6, "aa": 6, "heli": 6, "jet": 4, "drone": 2}, {"inf": 24, "tank": 12, "art": 6, "aa": 6, "heli": 6, "jet": 4, "drone": 2}, 3, 4, 2],
	"foresta18": [{"inf": 10, "tank": 5, "art": 2, "heli": 1}, {"inf": 6, "tank": 2}, 0, 0, 0],
	"foresta": [{"inf": 18, "tank": 7, "art": 3, "heli": 3}, {"inf": 18, "tank": 6, "aa": 3, "art": 3}, 0, 0, 3],
	"deserto": [{"tank": 12, "inf": 12, "art": 4, "jet": 2, "heli": 2}, {"tank": 10, "inf": 14, "aa": 3, "art": 3}, 0, 3, 0],
	"pianura": [{"inf": 16, "tank": 10, "art": 3, "aa": 2, "drone": 3}, {"inf": 16, "tank": 9, "art": 3, "aa": 2, "heli": 2}, 0, 0, 0],
	"montagna": [{"inf": 20, "tank": 5, "art": 4, "heli": 2}, {"inf": 20, "tank": 4, "aa": 2, "art": 2}, 2, 0, 3],
	"artico": [{"inf": 16, "tank": 8, "aa": 2, "art": 3}, {"inf": 16, "tank": 7, "art": 2, "jet": 1}, 0, 0, 0],
	# fase 5: carri all'assalto di boschi tenuti dalla fanteria (imboscate), e battaglia campale 60 contro 60
	"imboscata": [{"tank": 10, "inf": 6, "art": 2}, {"inf": 20, "tank": 2}, 0, 0, 0],
	"campale": [{"inf": 24, "tank": 14, "art": 6, "aa": 6, "heli": 4, "jet": 2, "drone": 4}, {"inf": 24, "tank": 14, "art": 6, "aa": 6, "heli": 4, "jet": 2, "drone": 4}, 2, 4, 4],
}

var sim: BattleSim
var setup: Dictionary
var terrain: BattleTerrain
var fx: BattleFx
var cam: BattleCamera
var hud: BattleHud
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var views := {}            # id -> Dictionary
var wrecks: Array = []
var falling: Array = []
var pending: Array = []    # effetti ritardati [t, kind, pos, s]
var screen_list: Array = []
var mode := ""             # "", "amove", "barrage"
var drag_active := false
var drag_from := Vector2.ZERO
var drag_to := Vector2.ZERO
var _drag_shift := false
var _emitted := false
var _end_t := 0.0
var _msg_shown := false
var _sfx_t := {}
var _ring_mesh: TorusMesh
var _ring_mats := {}
var _markers: Array = []
var _cursor_ring: MeshInstance3D
var _demo := false
var _last_group_tap := {}
var _hover_enemy = null
var _wall_time := 0.0
var _shell_trail_t := 0.0
# fase 2
var deploying := false        # fase di schieramento (battaglia in pausa)
var deploy_left := 0.0
const DEPLOY_TIME := 20.0
var _deploy_zone: MeshInstance3D
var alerts: Array = []        # [{p: Vector3, t: float}] unità umane colpite fuori schermo
var _alert_sfx_t := -100.0
var mood := "pomeriggio"
var mood_text := ""
var quality := "alto"
var ultra := false               # qualità "ultra": come "alto" più illuminazione globale (SSIL + SDFGI)
var _shadow_k := 1.0
var _occ_i := 0
var _end_wait := 0.0
var _continue := false
var _msaa_set := false
var _old_msaa := 0
var fps_avg := 0.0
var _um_damage := false        # UnitModels.set_damage disponibile
var _ships: Array = []
# fase 3
var orders: BattleOrderMarks
var coast: BattleCoast
const INTRO_T := 3.8
var intro_t := -1.0            # >= 0 durante l'introduzione cinematica
var _intro_a := {}             # inquadratura iniziale {t, d, y}
var _intro_b := {}             # inquadratura finale (quella di gioco)
var _intro_deploy := false
const OUTRO_T := 1.6           # uscita cinematica: la telecamera risale prima di tornare al tabellone
var _outro_t := -1.0
var _outro_a := {}
var _last_order_t := -100.0
var _last_kill_p := Vector3.INF
var _last_kill_t := -100.0
var slowmo := 0.0              # secondi reali di rallentatore finale rimasti
var _slow_done := false
var _danger: Array = []        # [Vector3, t] esplosioni recenti (fanteria che si accovaccia)
var _inf_i := 0
# fase 4
var _fog_base := 0.0
var _fog_hbase := 0.0
var _jets: Array = []          # passaggi del supporto aereo {n, T, fwd, t, trail, snd}
var _focus: Array = []         # posizioni delle unità da tenere visibili (boschi trasparenti)
var _wood_t := 0.0
# fase 5: battaglia tattica (visibilità, pedine a distanza, anelli, imboscate)
const ICON_NEAR := 150.0       # distanza (m) da cui compaiono le pedine tattiche
const ICON_FAR := 290.0        # oltre: solo pedine piene
const MODEL_FAR := 560.0
const CHIP_NEAR := 55.0        # distanza (m) da cui sopra le unità compare il gettone con tipo e integrità       # oltre (e con pedina piena) il modello 3D è nascosto
const MODEL_FAR_INF := 400.0
var _tactical := false         # la sim ha la visibilità tattica (visible_to)
var floaters: Array = []       # scritte fluttuanti {p: Vector3, text, col: Color, t, T, big}
var pings: Array = []          # avvistamenti sulla minimappa {p: Vector3, t, col}
var toasts: Array = []         # righe di registro {text, col, t}
var _float_t := {}             # id bersaglio -> ultimo istante di scritta (limite di frequenza)
var _spot_n := 0.0             # limite di scritte "AVVISTATO" al secondo
var hover_info := ""           # testo del suggerimento sotto il cursore (copertura, fianco)
var _hover_t := 0.0
var _mouse := Vector2.ZERO
const FORT_SCRIPT := preload("res://scripts/battle/battle_fort.gd")
var fort: Node3D
var audio: BattleAudio
var weather: BattleWeather      # Fase 8: meteo/ora (ambiente, precipitazioni, razzi illuminanti)
var marks: BattleMarks          # Fase 8: solchi, crateri, distruzione
var _env_base := {}             # valori dell'ambiente di base (BattleWeather li modula)
var _sky_mat: ProceduralSkyMaterial
var photo := false              # modalità foto (F10): battaglia in pausa, interfaccia nascosta, telecamera libera
var _photo_was_paused := false
var _photo_attr: CameraAttributesPractical
var _photo_dof := 0.0
# profondità di campo "tilt-shift" della vista di gioco (effetto plastico): forte da camera alta, quasi nulla da vicino
var _tilt_attr: CameraAttributesPractical
var _tilt_k := 0.0
var strat: BattleStrategic       # vista strategica: fronte, frecce, obiettivi (zoom continuo)
var _tac_dist := 150.0           # ultima distanza tattica (per tornarci con Tab)               # per qualità: 0 spenta (basso), medio 0.8, alto 1
var _photo_shot_pending := false
var _booms: Array = []          # demo (--boom=t1,t2): esplosioni di prova sul bersaglio della telecamera
var _boom_frames: Array = []    # demo (--boomf=f1,f2): idem, per numero di frame (screenshot deterministici)
var _frame_n := 0
var fog_vp: SubViewport
var fog_draw: Control
var _fog_t := 0.0

func _ready() -> void:
	var d := ""
	if has_node("/root/Shot"):
		d = String(get_node("/root/Shot").call("arg", "demo"))
	if d != "":
		_demo = true
		start(_demo_setup(d))

func _shot_arg(n: String, def := "") -> String:
	if has_node("/root/Shot"):
		return String(get_node("/root/Shot").call("arg", n, def))
	return def

# ---------------------------------------------------------------------------- avvio
func start(s: Dictionary) -> void:
	setup = s
	# Fase 8: meteo dal seed (la vista 3D chiede sempre il piano; i test e la formula strategica no)
	if not s.has("weather") or String(s["weather"]) == "":
		s["weather"] = "auto"
	if _demo and _shot_arg("weather", "") != "":
		s["weather"] = _shot_arg("weather", "")
	sim = BattleSim.new(s)
	if _demo and _shot_arg("human", "0") == "1":
		sim.ai_assist[maxi(0, sim.hs)] = true
	_build_env()
	terrain = BattleTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(sim)
	# Fase 8: il rilievo deve leggersi anche a media distanza (ombreggiatura e AO più marcate; di più col cielo coperto)
	terrain.terrain_mat.set_shader_parameter("relief_k", 1.5 if sim.tkey == "artico" else (1.35 if mood in ["coperto", "notte"] else 1.2))
	cam = BattleCamera.new()
	cam.name = "Camera"
	cam.terrain = terrain
	add_child(cam)
	cam.configure_field(BattleTerrain.FIELD_HX, BattleTerrain.FIELD_HZ)
	cam.current = true
	fx = BattleFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(cam, terrain.terrain_mat.get_shader_parameter("noise_tex"), -sun.global_transform.basis.z)
	fx.dust_color = _dust_color()
	fx.night_k = 2.4 if mood == "notte" else 1.0
	weather = BattleWeather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(self, world_env.environment, sun, _sky_mat, _env_base, terrain.terrain_mat, fx)
	fx.set_lighting(sun.light_color, sun.light_energy, world_env.environment.ambient_light_color)   # fumo illuminato come la scena
	terrain.terrain_mat.set_shader_parameter("horizon_col", world_env.environment.fog_light_color)   # foschia d'orizzonte del paesaggio
	marks = BattleMarks.new()
	marks.name = "Marks"
	add_child(marks)
	marks.setup(self, weather)
	mood_text = _conditions_text()
	if _demo:
		# screenshot: stato del suolo già raggiunto (--wet=1 bagnato, --snowcover=1 neve accumulata)
		weather.wetness = float(_shot_arg("wet", "0"))
		weather.snow_cover = maxf(weather.snow_cover, float(_shot_arg("snowcover", "0")))
	audio = BattleAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self, sim, cam)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	for u in sim.units:
		_make_view(u)
	_cursor_ring = MeshInstance3D.new()
	_cursor_ring.mesh = _ring_mesh
	_cursor_ring.visible = false
	_cursor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cursor_ring)
	var UM = BattleProps.ext("UnitModels")
	_um_damage = UM != null and UM.has_method("set_damage")
	_build_ships()
	orders = BattleOrderMarks.new()
	orders.name = "Orders"
	add_child(orders)
	orders.setup(self, _ring_mesh)
	_tactical = sim.has_method("visible_to")
	_setup_fog()
	fort = FORT_SCRIPT.new()
	fort.name = "Fort"
	add_child(fort)
	fort.setup(self)
	if sim.sea:
		coast = BattleCoast.new()
		coast.name = "Coast"
		add_child(coast)
		coast.setup(self, _ships)
	# impostazioni (qualità, telecamera) e musica
	var st = get_node_or_null("/root/Settings")
	if st != null:
		if st.has_signal("changed"):
			st.changed.connect(_on_setting_changed)
	_read_settings()
	var mus = get_node_or_null("/root/Music")
	if mus != null and mus.has_method("play"):
		mus.call("play", "battle")
	strat = BattleStrategic.new(self)
	hud = BattleHud.new()
	add_child(hud)
	hud.build(self)
	hud.pressed.connect(_on_button)
	# camera iniziale: dietro al proprio esercito, a distanza RTS comoda, rivolta al nemico
	frame_army()
	_prewarm()
	# fase di schieramento (solo con un lato umano; disattivabile con setup.deploy = false o --deploy=0)
	var want_deploy := sim.hs >= 0 and bool(s.get("deploy", true))
	var want_intro := bool(s.get("intro", true))
	if _demo:
		want_deploy = sim.hs >= 0 and _shot_arg("deploy", "0") == "1"
		want_intro = _shot_arg("intro", "0") != "0"
	if want_intro:
		_begin_intro(want_deploy)
	elif want_deploy:
		_begin_deploy()
	if _demo:
		if intro_t < 0:
			_demo_prepare()
		if _shot_arg("prof", "0") == "1":
			_prof = 1
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
			_pt_cur.resize(PT_NAMES.size()); _pt_last.resize(PT_NAMES.size()); _pt_max.resize(PT_NAMES.size())
	_update_views(0.0)

## Inquadra il proprio esercito (o l'attaccante se la battaglia è tra IA).
func frame_army(dist := 150.0) -> void:
	var si := sim.hs if sim.hs >= 0 else 0
	var c := Vector2.ZERO
	var n := 0
	for u in sim.units:
		if u.dead or u.side != si or u.stat:
			continue
		if u.air and n > 0:
			continue
		c += Vector2(u.x, u.y); n += 1
	if n == 0:
		c = Vector2(float(sim.W) * (0.25 if si == 0 else 0.75), float(sim.H) * 0.5)
	else:
		c /= n
	var w := BattleTerrain.sim_to_world(c.x, c.y)
	var fwd := 1.0 if si == 0 else -1.0
	# vista di tre quarti (un po' di lato) per non avere i mezzi aerei di rincalzo davanti all'obiettivo
	var yaw := (-PI / 2 + 0.42) if si == 0 else (PI / 2 + 0.42)
	cam.place(Vector3(w.x + fwd * 14.0, 0, w.y), dist, yaw)

# ---------------------------------------------------------------------------- introduzione cinematica
const CLOCK := {"mattino": [6, 7], "pomeriggio": [14, 16], "tramonto": [18, 19], "coperto": [10, 12], "notte": [22, 23]}

func _intro_lines() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = sim.seed_ * 7 + 3
	var hh: Array = CLOCK.get(mood, [12, 13])
	var h := r.randi_range(int(hh[0]), int(hh[1]))
	var m := r.randi_range(0, 11) * 5
	var meteo := "sereno"
	if weather != null and String(sim.weather) != "sereno":
		meteo = String(BattleWeather.NAMES.get(String(sim.weather), String(sim.weather)))
		if String(sim.weather) == "notte":
			meteo = "notte serena"
	elif mood == "coperto":
		meteo = "cielo coperto"
	elif sim.tkey == "foresta":
		meteo = "foschia"
	elif mood == "tramonto":
		meteo = "luce radente"
	var tname := String(Data.TERRAINS[sim.tkey]["name"])
	var line1 := "Ore %02d:%02d · %s" % [h, m, meteo]
	var mname := MOOD_NAMES[mood] as String
	var line2 := tname + (" · costa, sbarco dal mare" if sim.sea else "") + ("" if mname == meteo else " · " + mname)
	var title := String(setup.get("terrName", "Battaglia"))
	return [title, line1, line2]

func _side_center(si: int) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for u in sim.units:
		if u.dead or u.side != si or u.air:
			continue
		c += Vector2(u.x, u.y); n += 1
	if n == 0:
		return Vector2(float(sim.W) * (0.25 if si == 0 else 0.75), float(sim.H) * 0.5)
	return c / n

func _begin_intro(deploy_after: bool) -> void:
	intro_t = 0.0
	_intro_deploy = deploy_after
	sim.paused = true
	_intro_b = {"t": cam._t_target, "d": cam._t_dist, "y": cam._t_yaw}
	# parte alta sopra lo schieramento nemico e scivola sul proprio esercito con un ampio giro
	var si := sim.hs if sim.hs >= 0 else 0
	var e := BattleTerrain.sim_to_world(_side_center(1 - si).x, _side_center(1 - si).y)
	var t0 := Vector3(e.x * 0.6, 0, e.y * 0.6 + 30.0)
	_intro_a = {"t": t0, "d": cam.max_dist, "y": float(_intro_b["y"]) + (1.25 if si == 0 else -1.25)}
	cam.keys_enabled = false
	cam.edge_pan = false
	var L := _intro_lines()
	hud.show_intro(L[0], L[1], L[2])
	_update_intro(0.0)

func _update_intro(dt: float) -> void:
	intro_t += dt
	var f := clampf(intro_t / INTRO_T, 0.0, 1.0)
	var e := f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
	var tg: Vector3 = (_intro_a["t"] as Vector3).lerp(_intro_b["t"], e)
	var d := lerpf(float(_intro_a["d"]), float(_intro_b["d"]), e)
	var y := lerp_angle(float(_intro_a["y"]), float(_intro_b["y"]), e)
	cam.place(tg, d, y)
	hud.set_intro(f)
	if f >= 1.0:
		end_intro()

## Fine (o salto) dell'introduzione: la telecamera raggiunge dolcemente l'inquadratura di gioco.
func end_intro() -> void:
	if intro_t < 0:
		return
	intro_t = -1.0
	cam._t_target = _intro_b["t"]
	cam._t_dist = _intro_b["d"]
	cam._t_yaw = _intro_b["y"]
	cam.keys_enabled = true
	if not _demo:
		cam.edge_pan = bool(_settings_value("edge_scroll", true))
	hud.hide_intro()
	if _intro_deploy:
		_begin_deploy()
	else:
		sim.paused = false
	if _demo:
		_demo_prepare()

# ---------------------------------------------------------------------------- schieramento
func _begin_deploy() -> void:
	deploying = true
	deploy_left = DEPLOY_TIME
	sim.paused = true
	var z := sim.deploy_zone(sim.hs)
	var a := BattleTerrain.sim_to_world(z.position.x, z.position.y)
	var b := BattleTerrain.sim_to_world(z.end.x, z.end.y)
	_deploy_zone = terrain.make_zone_mesh(Rect2(a, b - a), side_color(sim.hs))
	add_child(_deploy_zone)
	if sim.hs >= 0:
		sim.select_all()

func end_deploy() -> void:
	if not deploying:
		return
	deploying = false
	sim.paused = false
	if _deploy_zone != null:
		_deploy_zone.queue_free()
		_deploy_zone = null
	_sfx("alert", 0)

# ---------------------------------------------------------------------------- impostazioni
func _settings_value(key: String, def):
	var st = get_node_or_null("/root/Settings")
	if st != null and st.has_method("get_value"):
		var v = st.call("get_value", key)
		if v != null:
			return v
	return def

func _read_settings() -> void:
	quality = String(_settings_value("quality", "alto"))
	ultra = quality == "ultra"
	if not quality in ["basso", "medio", "alto"]:
		quality = "alto"
	cam.speed_mul = float(_settings_value("camera_speed", 1.0))
	if not _demo:
		cam.edge_pan = bool(_settings_value("edge_scroll", true))
	_apply_quality()

func _on_setting_changed(key) -> void:
	if sim == null:
		return
	if String(key) in ["quality", "upscale", "camera_speed", "edge_scroll"]:
		_read_settings()

func _apply_quality() -> void:
	var env := world_env.environment
	env.ssao_enabled = quality == "alto"
	env.glow_enabled = quality != "basso"
	# ultra: luce indiretta in spazio schermo (rimbalzi di colore tra terreno, mezzi ed edifici) e SDFGI
	env.ssil_enabled = ultra
	if ultra:
		env.ssil_radius = 6.0
		env.ssil_intensity = 0.9
		env.ssil_sharpness = 0.98
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	env.sdfgi_enabled = ultra and _shot_arg("sdfgi", "1") != "0"
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_max_distance = 410.0
		env.sdfgi_energy = 0.7
		env.sdfgi_bounce_feedback = 0.4
	match quality:
		"alto":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_shadow_k = 1.0
		"medio":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_shadow_k = 0.8
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			_shadow_k = 0.55
	terrain.set_density({"alto": 1.0, "medio": 0.6, "basso": 0.3}[quality])
	# tilt-shift: spento su basso; sfocatura a qualità bassa su medio (costo ~0.3 ms), media su alto
	_tilt_k = {"alto": 1.0, "medio": 0.8, "basso": 0.0}[quality]
	fx.detail = {"alto": 1.0, "medio": 0.7, "basso": 0.45}[quality]
	if _shot_arg("dof", "") != "":
		_tilt_k = float(_shot_arg("dof", "0"))
	if _tilt_k > 0.0:
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_MEDIUM if quality == "alto" else RenderingServer.DOF_BLUR_QUALITY_LOW, quality == "alto")
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	_update_tilt()
	if weather != null:
		weather.quality_k = {"alto": 1.0, "medio": 0.6, "basso": 0.3}[quality]
	# MSAA: lo gestisce Settings se c'è; altrimenti la battaglia lo imposta e lo ripristina all'uscita
	if get_node_or_null("/root/Settings") == null and is_inside_tree():
		var vp := get_viewport()
		if not _msaa_set:
			_old_msaa = vp.msaa_3d
			_msaa_set = true
		vp.msaa_3d = Viewport.MSAA_4X if quality == "alto" else (Viewport.MSAA_2X if quality == "medio" else Viewport.MSAA_DISABLED)

func _demo_setup(kind: String) -> Dictionary:
	if not DEMOS.has(kind):
		kind = "pianura"
	var D: Array = DEMOS[kind]
	var tk := kind
	if kind == "grande":
		tk = "urbano"
	elif kind == "foresta18" or kind == "imboscata":
		tk = "foresta"
	elif kind == "campale":
		tk = "pianura"
	tk = _shot_arg("terrain", tk)
	var T: Dictionary = Data.TERRAINS[tk]
	var human := _shot_arg("human", "0") == "1"
	var fa := int(_shot_arg("att", "0"))
	var fd := int(_shot_arg("def", "1"))
	var sd := int(_shot_arg("seed", "7"))
	var sea := _shot_arg("sea", "0") == "1"
	var f0: Dictionary = Data.empty_forces()
	var f1: Dictionary = Data.empty_forces()
	for k in D[0]: f0[k] = D[0][k]
	for k in D[1]: f1[k] = D[1][k]
	var vets := _shot_arg("vet", "0,0").split(",")
	var va := int(vets[0])
	var vd := int(vets[1]) if vets.size() > 1 else 0
	# --side=1: il giocatore comanda il difensore; --fort=N: fortificazioni del difensore (trincee, mine, bunker) di livello N
	var hside := int(_shot_arg("side", "0")) if human else -1
	var fl := int(_shot_arg("fort", "0"))
	# omogeneità (docs/omogeneita.md): --buildings=fabbrica,porto --hq=1 --reinf=1 (rinforzi a 20 s) per vedere obiettivi e rinforzi
	var bl: Array = []
	for bk in _shot_arg("buildings", "").split(","):
		if bk != "":
			bl.append(bk)
	var s := {
		"terrIdx": 0, "terrain": tk, "terrName": _shot_arg("name", "Battaglia di prova — " + String(T["name"])), "sea": sea, "seed": sd,
		"att": {"player": fa, "faction": fa, "name": Data.FACTIONS[fa]["name"], "color": Data.faction_color(fa), "forces": f0,
			"mods": {"atk": 1.0, "unit": T["mul"], "hp": {}}, "human": human and hside == 0, "vet": va, "manual": human and hside == 0},
		"def": {"player": fd, "faction": fd, "name": Data.FACTIONS[fd]["name"], "color": Data.faction_color(fd), "forces": f1,
			"mods": {"atk": float(T["def"]), "unit": T["mul"], "hp": {}}, "human": human and hside == 1, "bunkers": D[2], "vet": vd,
			"fort": {"trench": fl, "mines": fl, "bunker": mini(fl, 1)}, "manual": human and hside == 1},
		"support": {"att": D[3], "def": D[4]},
		"buildings": bl, "hq": _shot_arg("hq", "0") == "1",
	}
	if _shot_arg("reinf", "0") == "1":
		s["att"]["reinf"] = {"forces": {"inf": 4, "tank": 2}, "t": 20.0, "dir": -1}
		s["def"]["reinf"] = {"forces": {"inf": 3, "tank": 1}, "t": 25.0, "dir": 1}
	return s

func _demo_prepare() -> void:
	if _shot_arg("shadow", "1") == "0":
		sun.shadow_enabled = false
	cam.edge_pan = false
	cam.keys_enabled = false
	cam.mouse_enabled = false
	var warp := float(_shot_arg("warp", "0"))
	var t := 0.0
	var until := _shot_arg("until", "")
	var found = null
	var vt := 0.0
	while t < warp and not sim.done:
		sim.step(0.05)
		t += 0.05
		vt += 0.05
		if vt >= 0.4:
			# anche durante l'avanzamento rapido i mezzi lasciano i solchi (posizioni dalla vista)
			vt = 0.0
			_update_views(0.0)
			marks._vehicles()
		if until != "":
			for e in sim.fx:
				if e["e"] == until and (until != "ambush" or sim.hs < 0 or true):
					found = e
		_consume_fx(true)
		if until == "ghost" and sim.hs >= 0 and "ghosts" in sim and (sim.ghosts[sim.hs] as Array).size() >= int(_shot_arg("ghosts", "2")):
			var g0: Dictionary = sim.ghosts[sim.hs][0]
			found = {"x": g0["x"], "y": g0["y"]}
		if found != null:
			break
	if found != null:
		print("[battle] evento '%s' a t=%.1f" % [until, sim.time])
		if until == "ambush" and found.has("e"):
			_on_ambush(found)
		var fw := BattleTerrain.sim_to_world(float(found["x"]), float(found["y"]))
		_update_views(0.0)
		if sim.hs >= 0:
			sim.select_all()
		cam.place(Vector3(fw.x, 0, fw.y), float(_shot_arg("dist", "90")), deg_to_rad(float(_shot_arg("yaw", "0"))))
		return
	if sim.hs >= 0:
		sim.select_all()
		if _shot_arg("order", "0") == "1":
			# prova degli indicatori d'ordine: carri avanti, il resto in attacco in movimento
			var c := _side_center(sim.hs)
			var fw := 1.0 if sim.hs == 0 else -1.0
			sim.set_selection([], false)
			var tanks := []
			for u in sim.units:
				if u.side == sim.hs and u.type == "tank":
					tanks.append(u)
			sim.select_units(tanks, false)
			sim.order_move(c.x + fw * 150.0, c.y - 60.0)
			_mark(c.x + fw * 150.0, c.y - 60.0, "move", 3.0)
			sim.select_all()
		# prova delle abilità: --smoke=1 (fumo sulle unità selezionate), --air=1 (supporto aereo sul grosso nemico)
		if _shot_arg("smoke", "0") == "1":
			sim.human_smoke()
		if _shot_arg("air", "0") == "1":
			var ec := _side_center(1 - sim.hs)
			sim.human_air_strike(ec.x, ec.y)
			_mark(ec.x, ec.y, "barrage", BattleSim.AIR_R * S)
		if _shot_arg("holdpos", "0") == "1":
			sim.hold_position()
		# --sel=tank,art: selezione ridotta (anelli di gittata)
		if _shot_arg("sel", "") != "":
			var types := _shot_arg("sel", "").split(",")
			var lst := []
			for u in sim.units:
				if u.side == sim.hs and not u.dead and String(u.type) in types:
					lst.append(u)
			sim.set_selection([], false)
			sim.select_units(lst, false)
	if _shot_arg("photo", "0") == "1":
		# screenshot della modalità foto (interfaccia nascosta, pannello sliders)
		call_deferred("set_photo", true)
	# razzi illuminanti già in volo nella sim (avanzamento silenzioso): ricrea la parte visiva
	for f in sim.flares:
		var left: float = float(f["until"]) - sim.time
		if left > 2.0:
			weather.on_flare({"x": f["x"], "y": f["y"], "side": f["side"], "t": left})
			var fl: Dictionary = weather.flares[weather.flares.size() - 1]
			fl["t"] = maxf(0.0, float(BattleRules.FLARE_T) - left)
			fl["p"] = (fl["p"] as Vector3) - Vector3(0, 2.6 * float(fl["t"]) - 14.0, 0)
	# --boom=t1,t2,...: esplosioni di prova (bomba) sul distruttibile più vicino al bersaglio della telecamera
	if _shot_arg("boom", "") != "":
		for bt in _shot_arg("boom", "").split(","):
			_booms.append(float(bt))
	if _shot_arg("boomf", "") != "":
		for bf in _shot_arg("boomf", "").split(","):
			_boom_frames.append(int(bf))
	# --flare=1: razzo illuminante sopra il bersaglio della telecamera (screenshot notturni)
	if _shot_arg("tab", "0") == "1":
		toggle_strategic.call_deferred()   # demo: prova del tasto Tab (vista strategica)
	if _shot_arg("flare", "0") == "1":
		var fs := BattleTerrain.world_to_sim(cam._t_target.x, cam._t_target.z)
		sim.add_flare(fs.x + 120.0, fs.y, 0)
	if _shot_arg("cam", "") == "army" or (_shot_arg("cam", "") == "" and warp <= 0):
		frame_army(float(_shot_arg("dist", "150")))
		return
	if _shot_arg("cam", "") == "overview":
		cam.place(Vector3(0, 0, BattleTerrain.FIELD_HZ * 0.12), float(_shot_arg("dist", str(cam.max_dist))), deg_to_rad(float(_shot_arg("yaw", "0"))))
		return
	# inquadra lo scontro: per ogni unità di terra il punto medio col nemico a terra più vicino (entro 1600 px);
	# vince il punto con più unità di entrambi i lati entro 300 px (a parità, la coppia più vicina)
	var best := Vector2(float(sim.W) * 0.5, float(sim.H) * 0.5)
	var bscore := -1.0
	var ground := []
	for u in sim.units:
		if not u.dead and not u.air and not u.stat:
			ground.append(u)
	for a in ground:
		if a.side != 0:
			continue
		var nb = null
		var bd := 1600.0 * 1600.0
		for b in ground:
			if b.side != 1:
				continue
			var d: float = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
			if d < bd:
				bd = d; nb = b
		if nb == null:
			continue
		var c := Vector2((a.x + nb.x) * 0.5, (a.y + nb.y) * 0.5)
		var n0 := 0
		var n1 := 0
		for u in ground:
			if Vector2(u.x, u.y).distance_squared_to(c) < 300.0 * 300.0:
				if u.side == 0: n0 += 1
				else: n1 += 1
		var score := float(mini(n0, n1) * 3 + n0 + n1) - sqrt(bd) / 800.0
		if score > bscore:
			bscore = score
			# baricentro delle unità intorno: la telecamera guarda i mezzi, non il terreno vuoto tra i due schieramenti
			var cc := Vector2.ZERO
			var nn := 0
			for u in ground:
				if Vector2(u.x, u.y).distance_squared_to(c) < 300.0 * 300.0:
					cc += Vector2(u.x, u.y); nn += 1
			best = cc / maxf(1.0, nn) if nn > 0 else c
	if bscore < 4.0:
		# eserciti ancora lontani: inquadra il gruppo di testa dell'attaccante
		var lead = null
		for a in ground:
			if a.side == 0 and (lead == null or a.x > lead.x):
				lead = a
		if lead != null:
			var c := Vector2.ZERO
			var n := 0
			for u in ground:
				if u.side == 0 and Vector2(u.x, u.y).distance_squared_to(Vector2(lead.x, lead.y)) < 260.0 * 260.0:
					c += Vector2(u.x, u.y); n += 1
			best = c / maxf(1.0, n)
	var w := BattleTerrain.sim_to_world(best.x, best.y)
	var dist := float(_shot_arg("dist", "120"))
	var yaw := deg_to_rad(float(_shot_arg("yaw", "-62")))
	if _shot_arg("cam", "") == "wide":
		w = Vector2(0, 0)
	elif _shot_arg("cam", "") == "coast" and coast != null and not coast.crafts.is_empty():
		var c: Dictionary = coast.crafts[int(_shot_arg("craft", "0")) % coast.crafts.size()]
		var rp: Vector3 = c["ramp"]
		w = Vector2(rp.x + 14.0, rp.z)
	elif _shot_arg("cam", "") == "inf":
		# fanteria più vicina a un riparo (edificio, bosco, roccia)
		var bi := 1e9
		for u in sim.units:
			if u.dead or u.type != "inf" or (u.side != int(_shot_arg("side", "0"))):
				continue
			var off := _cover_offset(u)
			var dd := off.length() if off != Vector2.ZERO else 1e6
			if bool(views[u.id].get("in_wood", false)):
				dd = 50.0
			if dd < bi:
				bi = dd
				w = BattleTerrain.sim_to_world(u.x, u.y)
	elif _shot_arg("cam", "") == "farm":
		# edificio distruttibile più vicino al centro del campo (prova della distruzione)
		var bd2 := 1e18
		for it in marks.items:
			if String(it["kind"]) in ["bld", "city"] and it["alive"]:
				var q: Vector3 = it["p"]
				var d2 := q.x * q.x + q.z * q.z
				if d2 < bd2:
					bd2 = d2
					w = Vector2(q.x, q.z)
	elif _shot_arg("cam", "") == "rock":
		for o in sim.obs:
			if not o["rect"]:
				w = BattleTerrain.sim_to_world(o["x"], o["y"])
				break
	elif _shot_arg("cam", "").contains(","):
		var p := _shot_arg("cam", "").split(",")
		w = Vector2(float(p[0]), float(p[1]))
	cam.place(Vector3(w.x, 0, w.y), dist, yaw)

func _dust_color() -> Color:
	match sim.tkey:
		"deserto": return Color(0.72, 0.6, 0.42)
		"artico": return Color(0.85, 0.88, 0.92)
		"urbano": return Color(0.55, 0.53, 0.5)
		"foresta": return Color(0.4, 0.36, 0.28)
		_: return Color(0.52, 0.46, 0.36)

const MOODS := ["mattino", "pomeriggio", "tramonto", "coperto"]
const MOOD_NAMES := {"mattino": "mattino", "pomeriggio": "pomeriggio", "tramonto": "tramonto", "coperto": "cielo coperto", "notte": "notte"}

func _pick_mood() -> String:
	var a := _shot_arg("mood", "")
	if a in MOODS:
		return a
	if sim != null and String(sim.weather) == "notte":
		return "notte"
	if sim != null and String(sim.weather) in ["pioggia", "temporale", "neve"] and a == "":
		# con le precipitazioni il sole è coperto: niente tramonti dorati sotto la pioggia
		return "coperto"
	var r := RandomNumberGenerator.new()
	r.seed = sim.seed_ * 131 + 17
	var w := {"mattino": 1.0, "pomeriggio": 1.3, "tramonto": 0.75, "coperto": 0.8}
	match sim.tkey:
		"deserto": w["coperto"] = 0.25
		"artico": w["coperto"] = 1.3; w["tramonto"] = 0.5
		"foresta": w["mattino"] = 1.4
	var tot := 0.0
	for k in MOODS: tot += float(w[k])
	var x := r.randf() * tot
	for k in MOODS:
		x -= float(w[k])
		if x <= 0:
			return k
	return "pomeriggio"

func _build_env() -> void:
	var t := sim.tkey
	var sky_top := Color(0.22, 0.42, 0.7)
	var sky_hor := Color(0.66, 0.74, 0.8)
	var fog := Color(0.68, 0.74, 0.8)
	var sun_col := Color(1.0, 0.95, 0.86)
	var sun_e := 1.3
	var fog_d := 0.0011
	var elev := 38.0
	var az := -38.0
	var amb := 0.62
	var expo := 1.0
	match t:
		"deserto":
			sky_top = Color(0.3, 0.5, 0.75); sky_hor = Color(0.85, 0.78, 0.66); fog = Color(0.86, 0.78, 0.64); sun_col = Color(1.0, 0.93, 0.8); sun_e = 1.35; fog_d = 0.0012; elev = 50.0
		"artico":
			sky_top = Color(0.42, 0.55, 0.72); sky_hor = Color(0.82, 0.86, 0.9); fog = Color(0.84, 0.88, 0.92); sun_col = Color(1.0, 0.94, 0.88); sun_e = 0.95; fog_d = 0.0016; elev = 24.0; expo = 0.86
		"foresta":
			sky_top = Color(0.26, 0.44, 0.66); sky_hor = Color(0.66, 0.72, 0.74); fog = Color(0.6, 0.67, 0.68); fog_d = 0.001; elev = 42.0
		"montagna":
			sky_top = Color(0.2, 0.4, 0.7); sky_hor = Color(0.7, 0.76, 0.84); fog = Color(0.72, 0.78, 0.86); fog_d = 0.0007; elev = 34.0
		"urbano":
			sky_top = Color(0.28, 0.42, 0.62); sky_hor = Color(0.72, 0.73, 0.74); fog = Color(0.66, 0.67, 0.68); fog_d = 0.0013; elev = 40.0; sun_e = 1.15
	mood = _pick_mood()
	var extra := ""
	match mood:
		"mattino":
			elev = minf(elev, 24.0); az = 62.0
			sun_col = sun_col.lerp(Color(1.0, 0.84, 0.66), 0.55)
			sky_hor = sky_hor.lerp(Color(0.92, 0.82, 0.7), 0.35)
			fog = fog.lerp(Color(0.86, 0.8, 0.72), 0.35)
			fog_d *= 1.35; amb = 0.66
		"tramonto":
			elev = 11.0; az = -112.0
			sun_col = Color(1.0, 0.7, 0.45); sun_e *= 1.1
			sky_top = sky_top.lerp(Color(0.2, 0.25, 0.42), 0.4)
			sky_hor = Color(0.95, 0.7, 0.5).lerp(sky_hor, 0.35)
			fog = Color(0.78, 0.68, 0.6).lerp(fog, 0.5)
			amb = 0.9; expo *= 1.06
			if t == "artico":
				sun_col = sun_col.lerp(Color(1, 0.95, 0.9), 0.5)
				sky_hor = sky_hor.lerp(Color(0.85, 0.86, 0.9), 0.4)
				fog = fog.lerp(Color(0.85, 0.86, 0.9), 0.5)
		"coperto":
			sun_e *= 0.42; elev = maxf(elev, 48.0)
			sun_col = Color(0.92, 0.94, 0.98)
			sky_top = Color(0.48, 0.52, 0.57).lerp(sky_top, 0.15)
			sky_hor = Color(0.7, 0.72, 0.74).lerp(sky_hor, 0.2)
			fog = Color(0.66, 0.68, 0.7).lerp(fog, 0.3)
			# cielo coperto: luce diffusa e un po' di foschia in più, ma il campo deve restare leggibile
			amb = 1.05; fog_d *= 1.15
		"notte":
			# luna alta e fredda: il campo si legge appena; razzi illuminanti, incendi e vampate fanno la luce
			elev = 46.0; az = 140.0
			sun_col = Color(0.42, 0.56, 0.98); sun_e = 1.35
			sky_top = Color(0.02, 0.03, 0.07); sky_hor = Color(0.07, 0.095, 0.16)
			fog = Color(0.06, 0.08, 0.14); fog_d *= 1.2
			amb = 1.4; expo = 1.12
	if t == "foresta":
		extra = ", foschia"
	mood_text = MOOD_NAMES[mood] + extra
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	_sky_mat = sm
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = sky_hor
	sm.ground_horizon_color = sky_hor
	sm.ground_bottom_color = sky_hor.darkened(0.5)
	sm.sun_angle_max = 30.0 if mood != "notte" else 4.0
	sm.sky_curve = 0.12
	if mood == "coperto":
		sm.sun_angle_max = 0.0
		sm.sky_cover_modulate = Color(1, 1, 1, 0)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = amb
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85 if mood != "notte" else 0.35
	env.ambient_light_color = fog.lerp(Color(0.62, 0.58, 0.5), 0.5) if mood != "notte" else Color(0.3, 0.38, 0.58)
	# AgX + LUT 1D (ombre fredde, luci calde): proposta polish_battle.md
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = expo * 1.08
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.5
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.25
	env.ssao_ao_channel_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_intensity = 0.4 if mood != "notte" else 0.75
	env.glow_strength = 0.9
	env.glow_hdr_threshold = 1.1 if mood != "notte" else 0.85
	env.set_glow_level(1, 0.0); env.set_glow_level(2, 0.6); env.set_glow_level(3, 1.0); env.set_glow_level(4, 0.8); env.set_glow_level(5, 0.4)
	env.fog_enabled = true
	env.fog_light_color = fog
	env.fog_density = fog_d * 0.55   # Fase 7: meno foschia che sbiadisce il rilievo
	_fog_base = env.fog_density
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.35 if mood != "coperto" else 0.22
	env.fog_sun_scatter = 0.15 if mood != "tramonto" else 0.35
	# foschia radente: bassa nelle valli (foresta) e base per la nebbia della Fase 8
	env.fog_height = 4.0
	env.fog_height_density = 0.0007 if t == "foresta" else 0.0
	_fog_hbase = env.fog_height_density
	env.adjustment_enabled = true
	# Fase 8: grading per atmosfera (tramonto caldo, coperto freddo, notte blu) con più contrasto: niente pastello
	var sat := 1.18
	var contrast := 1.16
	match mood:
		"coperto": sat = 1.02; contrast = 1.12
		"tramonto": sat = 1.22; contrast = 1.18
		"notte": sat = 0.9; contrast = 1.2
		"mattino": sat = 1.14
	env.adjustment_contrast = contrast
	env.adjustment_saturation = sat
	_env_base = {"sky_top": sky_top, "sky_hor": sky_hor, "fog": fog, "sun_col": sun_col, "sun_e": sun_e, "fog_d": _fog_base,
		"fog_hd": _fog_hbase, "fog_h": 4.0, "amb": amb, "sat": sat, "shadow_op": 0.55 if mood == "coperto" else 1.0,
		"sun_ang": 0.6 if mood != "coperto" else 3.0, "sun_amax": sm.sun_angle_max}
	var cc := Gradient.new()
	cc.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	cc.colors = PackedColorArray([Color(0.0, 0.01, 0.03), Color(0.16, 0.18, 0.21), Color(0.5, 0.5, 0.49), Color(0.84, 0.82, 0.77), Color(1, 0.98, 0.94)])
	var lut := GradientTexture1D.new()
	lut.gradient = cc
	lut.width = 256
	if _shot_arg("lut", "0") == "1":    # LUT fredda/calda della proposta: rende il suolo troppo blu nelle zone in ombra, spenta
		env.adjustment_color_correction = lut
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.9
	sun.shadow_blur = 1.2
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_opacity = 0.55 if mood == "coperto" else 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 350.0
	sun.light_angular_distance = 0.6 if mood != "coperto" else 3.0
	add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(az), 0)

## Battaglie costiere: qualche nave al largo (solo scena) con i colori dei due lati.
func _build_ships() -> void:
	if not sim.sea:
		return
	var UM = BattleProps.ext("UnitModels")
	if UM == null:
		return
	var r := RandomNumberGenerator.new()
	r.seed = sim.seed_ + 77
	var list := [["ship", 1], ["ship", 1], ["transport", 0], ["ship", 0]]
	for i in list.size():
		var n = BattleProps.unit_model(list[i][0], side_color(list[i][1]), faction(list[i][1]))
		if not (n is Node3D):
			continue
		var Z := (-90.0 + i * 60.0 + r.randf_range(-15, 15)) * BattleTerrain.FIELD_HZ / 112.5
		var X := terrain.coast_x(Z) - r.randf_range(38, 90)
		add_child(n)
		n.position = Vector3(X, 0, Z)
		n.rotation.y = r.randf_range(-0.6, 0.6) + (PI * 0.5 if r.randf() < 0.5 else -PI * 0.5)
		_ships.append([n, r.randf() * TAU, int(list[i][1])])

# ---------------------------------------------------------------------------- veterani, linee d'ordine
## Stelle di esperienza del lato (0..3) da setup.att.vet / setup.def.vet: solo visualizzazione,
## l'effetto numerico è già nei mods calcolati dal nucleo.
func vet(si: int) -> int:
	var S = setup.get("att" if si == 0 else "def", {})
	if S is Dictionary:
		return clampi(int(S.get("vet", 0)), 0, 3)
	return 0

## Linee d'ordine delle unità selezionate: tenendo premuto Shift, o per un attimo dopo aver dato un ordine.
func show_order_lines() -> bool:
	return order_lines_alpha() > 0.01

func order_lines_alpha() -> float:
	if Input.is_key_pressed(KEY_SHIFT) or _shot_arg("lines", "0") == "1":
		return 1.0
	return clampf(1.0 - (_wall_time - _last_order_t - 1.2) / 0.6, 0.0, 1.0)

# ---------------------------------------------------------------------------- viste delle unità
func side_color(si: int) -> Color:
	return sim.sides[si]["color"]

## Fazione del lato (setup.att.faction / setup.def.faction, aggiunte dal nucleo in fase 4; -1 = generico/neutrale).
func faction(si: int) -> int:
	var S = setup.get("att" if si == 0 else "def", {})
	if S is Dictionary and S.has("faction") and S["faction"] != null:
		return int(S["faction"])
	return -1

func _ring_mat(key: String, col: Color) -> StandardMaterial3D:
	if _ring_mats.has(key):
		return _ring_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	m.render_priority = 3
	_ring_mats[key] = m
	return m

# ---------------------------------------------------------------------------- sagome attraverso la vegetazione
## Passata sovrapposta ai modelli: disegna la sagoma (colore del lato) solo dove l'unità è coperta da alberi,
## edifici o rilievi: si confronta la profondità della scena con quella del centro del modello meno il suo raggio,
## così le parti del modello coperte dal modello stesso non si accendono.
const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, blend_mix;
uniform vec4 col : source_color = vec4(1.0);
uniform float radius = 4.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float center_z = -NODE_POSITION_VIEW.z;
	if (scene_z > center_z - radius) {
		discard;
	}
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALBEDO = col.rgb;
	ALPHA = col.a * (0.35 + 0.65 * rim * rim);
}
"""
var _xray_shader: Shader
var _xray_shader_rig: Shader   # fanteria animata: la sagoma segue la posa dei soldati (scheletro di UnitModels)
var _xray_mats := {}

func _xray_mat(si: int, selected: bool, radius: float, rig := false) -> ShaderMaterial:
	var key := "%d%s%d%s" % [si, "s" if selected else "", roundi(radius), "r" if rig else ""]
	if _xray_mats.has(key):
		return _xray_mats[key]
	if _xray_shader == null:
		_xray_shader = Shader.new()
		_xray_shader.code = XRAY_SHADER
	if rig and _xray_shader_rig == null:
		_xray_shader_rig = Shader.new()
		_xray_shader_rig.code = XRAY_SHADER.replace("void fragment() {", "#include \"res://scripts/models/soldier_rig.gdshaderinc\"
void vertex() {
	soldier_pose(VERTEX, NORMAL, UV, UV2, TIME);
}
void fragment() {")
	var m := ShaderMaterial.new()
	m.shader = _xray_shader_rig if rig else _xray_shader
	var c := side_color(si).lightened(0.25)
	if selected:
		c = Color(0.55, 1.0, 0.6)
	m.set_shader_parameter("col", Color(c.r, c.g, c.b, 0.85 if selected else 0.55))
	m.set_shader_parameter("radius", float(roundi(radius)))
	m.render_priority = 2
	_xray_mats[key] = m
	return m

func _set_xray(v: Dictionary, selected: bool) -> void:
	if _demo and _shot_arg("xray", "1") == "0":
		return
	var u: BattleSim.Unit = v["u"]
	var m := _xray_mat(u.side, selected, float(v["xr"]), bool(v.get("rig", false)))
	for mi in v["meshes"]:
		(mi as GeometryInstance3D).material_overlay = m

func _model_count(u: BattleSim.Unit) -> int:
	if u.stat:
		return 1
	if u.g <= 1:
		return 1
	return mini(u.g, 3)

func _make_view(u: BattleSim.Unit) -> void:
	var root := Node3D.new()
	root.name = "U%d" % u.id
	add_child(root)
	var col := side_color(u.side)
	var n := _model_count(u)
	var models := []
	var turrets := []
	var barrels := []
	var rotors := []
	var tails := []
	var muzzles := []
	var r := u.r * S
	var offs := [Vector3.ZERO]
	if n == 2:
		offs = [Vector3(-r * 0.42, 0, r * 0.1), Vector3(r * 0.42, 0, -r * 0.1)]
	elif n == 3:
		offs = [Vector3(0, 0, -r * 0.4), Vector3(-r * 0.5, 0, r * 0.35), Vector3(r * 0.5, 0, r * 0.35)]
	# fanteria ingrandita per leggibilità alle distanze RTS; mezzi leggermente ridotti per non sovrapporsi
	var sc := 0.9 if n == 1 else 0.78
	if u.type == "inf":
		sc = 1.5 if n == 1 else 1.3
	elif u.air or u.stat:
		sc = 1.0 if n == 1 else 0.85
	for i in n:
		var m: Node3D = BattleProps.unit_model(u.type, col, faction(u.side))
		m.position = offs[i]
		m.scale = Vector3.ONE * sc
		root.add_child(m)
		models.append(m)
		var tn := m.find_child("Turret", true, false)
		turrets.append(tn)
		barrels.append(m.find_child("Barrel", true, false))
		var rt := m.find_child("Rotor", true, false)
		if rt: rotors.append(rt)
		for pn in ["Prop"]:
			for pr in m.find_children(pn + "*", "Node3D", true, false):
				rotors.append(pr)
		var tr := m.find_child("TailRotor", true, false)
		if tr: tails.append(tr)
		muzzles.append(m.find_child("Muzzle", true, false))
	# vista dei mezzi: ruote/cingoli (parametri per istanza dello scafo), radar che girano, vomeri dell'artiglieria,
	# posizione a riposo delle canne (rinculo), numero tattico per modello, ombra a terra dei velivoli
	var UM = BattleProps.ext("UnitModels")
	var radars := []
	var spades := []
	var bar_pos := []
	for i in n:
		var m: Node3D = models[i]
		var rd := m.find_child("Radar", true, false)
		if rd: radars.append(rd)
		var sp := m.find_child("Spades", true, false)
		if sp: spades.append(sp)
		bar_pos.append((barrels[i] as Node3D).position if barrels[i] != null else Vector3.ZERO)
		if UM != null and UM.has_method("set_number") and u.type in ["tank", "art", "aa", "truck"]:
			UM.set_number(m, (u.id * 37 + i * 11 + u.side * 400) % 900 + 100)
	var blob: Node3D = null
	if u.air:
		var V = BattleProps.ext("Vfx")
		if V != null and V.has_method("shadow_blob"):
			var L0: float = (models[0] as Node3D).get_meta("length", 10.0) * sc
			blob = V.shadow_blob(self, L0 * 1.15)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = _ring_mat("side%d" % u.side, Color(col.r, col.g, col.b, 0.32))
	add_child(ring)
	var p := _unit_pos(u)
	root.position = p
	var yaw := -u.ang - PI / 2
	root.basis = Basis(Vector3.UP, yaw)
	var inf_mesh = null
	if u.type == "inf" and not models.is_empty():
		var bd = (models[0] as Node3D).get_node_or_null("Body")
		if bd is MeshInstance3D:
			inf_mesh = (bd as MeshInstance3D).mesh
	var meshes := []
	var ab := AABB()
	for m in models:
		for mi in (m as Node).find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi)
			if m == models[0]:
				var t := (m as Node3D).transform.affine_inverse() * (mi as Node3D).global_transform if (mi as Node3D).is_inside_tree() else Transform3D.IDENTITY
				var a := t * (mi as MeshInstance3D).get_aabb()
				ab = a if ab.size == Vector3.ZERO else ab.merge(a)
	# raggio del modello (m, con la scala) per la sagoma: le parti interne non devono accendersi
	var xr := clampf(ab.size.length() * 0.5 * sc + 0.8, 2.0, 12.0)
	views[u.id] = {"meshes": meshes, "xr": xr, "combat": 0.0, "offs": offs, "inf_mesh": inf_mesh, "inf_var": "base", "thr": 0.0, "cov": Vector2.ZERO, "cov_t": Vector2.ZERO,
		"cov_k": randf() * 0.4, "spread": 1.0, "was_sel": false, "pulse": 0.0,
		"u": u, "root": root, "models": models, "turrets": turrets, "barrels": barrels, "rotors": rotors,
		"tails": tails, "muzzles": muzzles, "ring": ring, "yaw": yaw, "pos": p, "prev": Vector2(u.x, u.y), "vis": n,
		"dead_t": -1.0, "bank": 0.0, "pitch": 0.0, "q": root.basis.get_rotation_quaternion(), "elev": 0.0,
		"hp": u.hp, "smk": randf() * 0.4, "occ": false,
		"radars": radars, "spades": spades, "bar_pos": bar_pos, "blob": blob, "um": UM != null and UM.has_method("set_motion"),
		"roll": 0.0, "mud": 0.0, "pv": 0.0, "gp": 0.0, "groll": 0.0, "spd_prev": 0.0, "rec_t": 9.0, "rec_k": 0, "dep": 0.0,
		"dust_t": randf() * 0.3, "ctrail": 0.0, "moved": false}
	_set_xray(views[u.id], false)
	if u.type == "inf":
		_inf_rig_init(views[u.id])
		if views[u.id].get("rig", false):
			_set_xray(views[u.id], false)

func _unit_pos(u: BattleSim.Unit) -> Vector3:
	var w := BattleTerrain.sim_to_world(u.x, u.y)
	var h := terrain.height(w.x, w.y)
	if u.air:
		h = maxf(h, 0.0) + float(ALT[u.type]) + sin(_wall_time * 1.3 + u.bob) * (0.6 if u.type != "jet" else 1.5)
	return Vector3(w.x, h, w.y)

func _target_point(u: BattleSim.Unit) -> Vector3:
	if views.has(u.id):
		var v: Dictionary = views[u.id]
		var p: Vector3 = v["pos"]
		return p + Vector3(0, 0.3 if u.air else (1.0 if u.type == "inf" else 1.4), 0)
	return _unit_pos(u)

## Separazione solo visiva dei mezzi a terra: se due modelli si compenetrano li scosta (max 3 m), senza toccare la sim.
func _visual_separation() -> void:
	var grid := {}
	var list := []
	for id in views:
		var v: Dictionary = views[id]
		var u: BattleSim.Unit = v["u"]
		if u.dead or u.air:
			continue
		var p: Vector3 = v["pos"]
		var c := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
		if not grid.has(c):
			grid[c] = []
		grid[c].append(v)
		list.append(v)
	for v in list:
		var u: BattleSim.Unit = v["u"]
		var p: Vector3 = v["pos"]
		var ra := u.r * S * 0.92
		var c := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
		var off := Vector2.ZERO
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var k := c + Vector2i(dx, dz)
				if not grid.has(k):
					continue
				for o in grid[k]:
					if o == v:
						continue
					var q: Vector3 = o["pos"]
					var d := Vector2(p.x - q.x, p.z - q.z)
					var R: float = ra + (o["u"] as BattleSim.Unit).r * S * 0.92
					var l := d.length()
					if l < R:
						if l < 0.01:
							d = Vector2(1, 0).rotated(float(u.id)); l = 1.0
						off += d / l * (R - l) * 0.5
		v["voff_t"] = off.limit_length(3.0)

func _update_views(dt: float) -> void:
	_visual_separation()
	var cpos := cam.global_position
	var focal := get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	screen_list.clear()
	_focus.clear()
	for id in views.keys():
		var v: Dictionary = views[id]
		var u: BattleSim.Unit = v["u"]
		var root: Node3D = v["root"]
		if u.dead:
			if v["dead_t"] < 0:
				v["dead_t"] = 0.0
				v["ring"].visible = false
				if v.get("blob") != null:
					(v["blob"] as Node3D).visible = false
				if v.get("rig", false) and root.visible:
					# fanteria animata: i soldati cadono a terra, poi spariscono (vedi _inf_anim_dying)
					for i in (v["models"] as Array).size():
						if (v["models"][i] as Node3D).visible:
							_inf_model_alive(v, i, false)
				else:
					root.visible = false
			elif v.get("rig", false) and root.visible:
				v["dead_t"] = float(v["dead_t"]) + dt
				_inf_anim_dying(v, dt)
				if float(v["dead_t"]) > 7.0:
					root.visible = false
			continue
		# visibilità tattica: i nemici non avvistati non si vedono (né modello né pedina)
		if not is_visible_unit(u):
			if v.get("shown", true):
				v["shown"] = false
				root.visible = false
				v["ring"].visible = false
				if v.get("blob") != null:
					(v["blob"] as Node3D).visible = false
			v["hp"] = u.hp
			v["pos"] = _unit_pos(u)    # i colpi di un'unità nascosta partono comunque dal punto giusto
			continue
		if not v.get("shown", true):
			v["shown"] = true
			v["mshow"] = true
			root.visible = true
		var p := _unit_pos(u)
		if u.air and u.type != "jet" and sim.tkey == "urbano":
			# elicotteri e droni sorvolano i tetti invece di attraversarli
			var roof := terrain.roof_height(p.x, p.z) + 7.0
			var lift: float = v.get("lift", 0.0)
			var want := maxf(0.0, roof - p.y)
			lift = lerpf(lift, want, minf(1.0, dt * 2.0)) if dt > 0 else want
			v["lift"] = lift
			p.y += lift
		if not u.air:
			var vo: Vector2 = v.get("voff", Vector2.ZERO)
			vo = vo.lerp(v.get("voff_t", Vector2.ZERO), minf(1.0, dt * 5.0)) if dt > 0 else v.get("voff_t", Vector2.ZERO)
			v["voff"] = vo
			if vo.length_squared() > 0.0001:
				p.x += vo.x; p.z += vo.y
				p.y = terrain.height(p.x, p.z)
				if sim.sea:
					p.y = maxf(p.y, 0.0)
		var spd := Vector2(u.vx, u.vy).length()
		var land := Vector3.ZERO
		if coast != null and not u.air:
			land = coast.land_offset(u, p)
			if land != Vector3.ZERO:
				p += land
				p.y = maxf(terrain.height(p.x, p.z), -0.6)
		if u.type == "inf":
			p = _inf_view(u, v, p, spd, dt)
		var yaw := -u.ang - PI / 2
		if u.air:
			var turn := wrapf(yaw - float(v["yaw"]), -PI, PI) / maxf(dt, 0.001)
			var bank_t := clampf(-turn * (0.35 if u.type == "jet" else 0.12), -1.1, 1.1)
			v["bank"] = lerpf(v["bank"], bank_t, minf(1.0, dt * 3.0))
			var pitch_t := -clampf(spd / u.speed, 0.0, 1.0) * (0.18 if u.type == "heli" else 0.05)
			v["pitch"] = lerpf(v["pitch"], pitch_t, minf(1.0, dt * 2.0))
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, v["pitch"]) * Basis(Vector3.BACK, v["bank"])
			root.basis = b
		else:
			var n := terrain.normal(p.x, p.z) if not u.stat else Vector3.UP
			var f := Vector3(cos(u.ang), 0, sin(u.ang))
			if land.length_squared() > 0.25:
				f = -Vector3(land.x, 0, land.z).normalized()
			var fz := (f - n * f.dot(n)).normalized()
			var z := -fz
			var x := n.cross(z).normalized()
			var target_q := Basis(x, n, z).orthonormalized().get_rotation_quaternion()
			var q: Quaternion = v["q"]
			q = q.slerp(target_q, minf(1.0, dt * 10.0)) if dt > 0 else target_q
			v["q"] = q
			var extra := Basis.IDENTITY
			if not u.stat and u.type != "inf":
				extra = _vehicle_motion(u, v, spd, dt, p)
			root.basis = Basis(q) * extra
		v["yaw"] = yaw
		root.position = p
		v["pos"] = p
		# LOD: da lontano solo la pedina tattica (niente modello 3D), in mezzo dissolvenza della pedina
		var depth := (p - cpos).length()
		var icon_k := smoothstep(ICON_NEAR, ICON_FAR, depth)
		var mshow := icon_k < 0.999 or depth < (MODEL_FAR_INF if u.type == "inf" else MODEL_FAR)
		if mshow != v.get("mshow", true):
			v["mshow"] = mshow
			root.visible = mshow
		if u.air:
			_air_view(u, v, p, yaw, spd, dt, depth, mshow)
		# proprie unità nascoste dalla copertura: aspetto semitrasparente
		var conc: bool = u.side == sim.hs and u.get("concealed") == true
		if conc != v.get("conc", false):
			v["conc"] = conc
			for mi in v["meshes"]:
				(mi as GeometryInstance3D).transparency = 0.45 if conc else 0.0
		# unità importanti per la dissolvenza dei boschi: selezionate o in combattimento
		if u.fire_t > 0.0 or u.hit_t > 0.0:
			v["combat"] = 2.5
		elif dt > 0.0:
			v["combat"] = maxf(0.0, float(v["combat"]) - dt)
		if not u.air and (u.sel or float(v["combat"]) > 0.0):
			_focus.append(p + Vector3(0, 1.2, 0))
		# danni: fumo dai mezzi danneggiati, allarme se un'unità umana viene colpita fuori schermo
		var frac: float = u.hp / u.hp_max
		if _um_damage and u.type != "inf" and absf(frac - float(v.get("dmg_f", 1.0))) > 0.04:
			# fumo/fiamme sul modello (UnitModels.set_damage dell'Agente F): cambia solo al cambio di fascia
			v["dmg_f"] = frac
			for m in v["models"]:
				if (m as Node3D).visible:
					BattleProps.ext("UnitModels").set_damage(m, 1.0 - frac)
		elif not _um_damage and dt > 0 and u.type != "inf" and frac < 0.55:
			v["smk"] -= dt
			if v["smk"] <= 0:
				v["smk"] = lerpf(0.16, 0.5, frac / 0.55)
				fx.burn(p + Vector3(0, (1.6 if not u.air else 0.0), 0), clampf(1.0 - frac * 1.6, 0.2, 0.95) if not u.air else 0.5)
		if u.smoke_t > 0.0 and dt > 0.0 and not u.air:
			v["smk2"] = float(v.get("smk2", 0.0)) - dt
			if v["smk2"] <= 0.0:
				v["smk2"] = 0.5 + randf() * 0.2
				fx.smoke_screen(p, 1.1 if u.type != "inf" else 0.9, 2)
		if u.hp < float(v["hp"]) - 0.01:
			if u.side == sim.hs and not deploying:
				_on_human_hit(u, p)
		v["hp"] = u.hp
		# torrette, canne, rotori
		var tur_local := wrapf(u.ang - u.tur, -PI, PI)
		var elev := 0.0
		if u.tgt != null and not u.tgt.dead:
			if u.type == "art":
				elev = 0.55
			elif u.type == "aa" and u.tgt.air:
				elev = 0.7
			elif u.type == "aa" or u.type == "tank" or u.type == "bunker":
				elev = 0.03
		if u.type == "art":
			# piazzata: canna alzata (di più con un bersaglio) e vomeri a terra; in marcia canna bassa e vomeri alzati
			var dpt = u.get("deploy_t")
			var deployed := spd < 1.0 and (dpt == null or float(dpt) <= 0.0)
			v["dep"] = move_toward(float(v["dep"]), 1.0 if deployed else 0.0, dt * 0.6)
			var dep: float = v["dep"]
			elev = 0.04 + (elev if elev > 0.0 else 0.3) * dep
			for sp in v["spades"]:
				(sp as Node3D).rotation.x = lerpf(-1.3, 0.35, dep)
		v["elev"] = lerpf(v["elev"], elev, minf(1.0, dt * 2.5))
		for t in v["turrets"]:
			if t != null:
				t.rotation.y = tur_local
		for b in v["barrels"]:
			if b != null:
				b.rotation.x = v["elev"]
		if not sim.paused:
			for r in v["rotors"]:
				r.rotate_y(dt * 28.0)
			for r in v["tails"]:
				r.rotate_x(dt * 40.0)
			for r in v["radars"]:
				(r as Node3D).rotate_y(dt * 2.4)
		# gruppi: nascondi i modelli persi
		var models: Array = v["models"]
		if models.size() > 1:
			var vis := clampi(ceili(float(sim.alive(u)) / u.g * models.size() - 0.01), 1, models.size())
			if vis != v["vis"]:
				v["vis"] = vis
				for i in models.size():
					if v.get("rig", false):
						_inf_model_alive(v, i, i < vis)
					else:
						models[i].visible = i < vis
		# anello a terra
		var ring: MeshInstance3D = v["ring"]
		var gy := terrain.height(p.x, p.z)
		if sim.sea:
			gy = maxf(gy, 0.0)
		var rr := u.r * S * (1.05 if not u.air else 0.8)
		if u.sel and not v["was_sel"]:
			v["pulse"] = 0.35
		if u.sel != v["was_sel"]:
			_set_xray(v, u.sel)
		v["was_sel"] = u.sel
		if v["pulse"] > 0.0:
			v["pulse"] = maxf(0.0, v["pulse"] - maxf(dt, 1.0 / 60.0))
			rr *= 1.0 + v["pulse"] * 1.6
		ring.position = Vector3(p.x, gy + 0.25, p.z)
		ring.scale = Vector3(rr, 0.6, rr)
		var hov: bool = u == _hover_enemy
		if u.sel:
			ring.material_override = _ring_mat("sel", Color(0.45, 1.0, 0.55, 0.9))
		elif hov:
			ring.material_override = _ring_mat("hov", Color(1.0, 0.35, 0.3, 0.9))
		else:
			ring.material_override = _ring_mat("side%d" % u.side, Color(side_color(u.side), 0.3))
		ring.visible = mshow or u.sel
		# proiezione per selezione/HUD
		var hp := p + Vector3(0, 1.5 if not u.air else 0.5, 0)
		if not cam.is_position_behind(hp):
			var sp := cam.unproject_position(hp)
			var rad := maxf(8.0, rr * focal / maxf(1.0, (hp - cpos).length()))
			var dst = null
			if u.sel and (u.order == BattleSim.MOVE or u.order == BattleSim.AMOVE or u.order == 4):
				var w := BattleTerrain.sim_to_world(u.ox, u.oy)
				var wp := Vector3(w.x, terrain.height(w.x, w.y) + 0.3, w.y)
				if not cam.is_position_behind(wp):
					dst = cam.unproject_position(wp)
			elif u.sel and u.order == BattleSim.ATTACK and u.otgt != null and not u.otgt.dead:
				var tp := _target_point(u.otgt)
				if not cam.is_position_behind(tp):
					dst = cam.unproject_position(tp)
			# Fase 5: gettone dell'unità già a media distanza (tipo + integrità leggibili da lontano), poi pedina piena
			var chip_k := maxf(icon_k, 0.92 * smoothstep(CHIP_NEAR, CHIP_NEAR + 35.0, depth))
			# velivoli: gettone anche da vicino (sono piccoli e veloci, e in quota non possono essere coperti dal suolo)
			if u.air:
				chip_k = maxf(chip_k, 0.75)
			screen_list.append([u, sp, rad, hov, dst, v["occ"] and icon_k < 0.5 and not u.air, chip_k, conc, icon_k])

## Movimento dei mezzi terrestri (solo vista): ruote che girano e cingoli che scorrono + fango che si accumula (parametri per
## istanza dello scafo, UnitModels.set_motion), beccheggio con accelerazioni/frenate (molla smorzata), rollio in curva,
## rinculo di canna e scafo allo sparo, polvere sollevata dietro. Restituisce la base aggiuntiva da comporre con quella del terreno.
func _vehicle_motion(u: BattleSim.Unit, v: Dictionary, spd: float, dt: float, p: Vector3) -> Basis:
	var spd_m := spd * S
	var rev: bool = u.get("reverse") == true
	var dist := spd_m * dt * (-1.0 if rev else 1.0)
	var accel := 0.0
	if dt > 0.0:
		accel = clampf((spd_m - float(v["spd_prev"])) / dt, -30.0, 30.0)
	v["spd_prev"] = spd_m
	var models: Array = v["models"]
	if absf(dist) > 0.0001:
		v["roll"] = float(v["roll"]) + dist
		v["mud"] = minf(0.75, float(v["mud"]) + absf(dist) * 0.0011)
		v["moved"] = true
	if bool(v["um"]) and bool(v["moved"]) and bool(v.get("mshow", true)):
		var UM = BattleProps.ext("UnitModels")
		var sc: float = (models[0] as Node3D).scale.x
		for m in models:
			if (m as Node3D).visible:
				UM.set_motion(m, float(v["roll"]) / maxf(sc, 0.01), float(v["mud"]))
		if absf(dist) <= 0.0001:
			v["moved"] = false
	# beccheggio: molla smorzata verso l'inclinazione data dall'accelerazione (muso su accelerando, giù frenando)
	var pt := clampf(accel * 0.014, -0.1, 0.1)
	var pv: float = v["pv"]
	var gp: float = v["gp"]
	if dt > 0.0:
		pv += ((pt - gp) * 48.0 - pv * 7.5) * dt
		gp += pv * dt
	v["pv"] = pv
	v["gp"] = clampf(gp, -0.2, 0.2)
	# rollio verso l'esterno della curva
	var yaw := -u.ang - PI / 2
	var turn := wrapf(yaw - float(v["yaw"]), -PI, PI) / maxf(dt, 0.001)
	var roll_t := clampf(turn * spd_m * 0.0035, -0.05, 0.05)
	v["groll"] = lerpf(float(v["groll"]), roll_t, minf(1.0, dt * 4.0)) if dt > 0.0 else float(v["groll"])
	# rinculo della canna (indietro in 70 ms, ritorno in ~0.5 s)
	var rt: float = v["rec_t"]
	if rt < 1.0:
		v["rec_t"] = rt + dt
		var k := rt / 0.07 if rt < 0.07 else maxf(0.0, 1.0 - (rt - 0.07) / 0.5)
		var ki: int = v["rec_k"]
		var barrels: Array = v["barrels"]
		if ki < barrels.size() and barrels[ki] != null:
			var amt := 0.45 if u.type == "tank" else (0.6 if u.type == "art" else 0.12)
			(barrels[ki] as Node3D).position = (v["bar_pos"][ki] as Vector3) + Vector3(0, 0, amt * k)
	# polvere sollevata dietro il mezzo in movimento (solo vicino alla telecamera)
	if spd_m > 1.0 and dt > 0.0:
		var depth := (p - cam.global_position).length()
		if depth < 260.0:
			v["dust_t"] = float(v["dust_t"]) - dt
			if float(v["dust_t"]) <= 0.0:
				v["dust_t"] = 0.14 + depth * 0.0012
				var m0 := models[0] as Node3D
				var L: float = float(m0.get_meta("length", 7.0)) * m0.scale.x
				var vd := Vector3(u.vx, 0, u.vy).normalized()
				var back := p - vd * L * 0.38
				if sim.tkey == "urbano" and terrain.inside_building(back.x, back.z):
					pass   # sotto un tetto (unità dentro un isolato): la polvere attraverserebbe il solaio
				elif u.type in ["tank", "art", "aa"]:
					# cingoli: polvere da entrambi i lati, più densa con la velocità (poca sull'asfalto)
					var side := vd.cross(Vector3.UP) * L * 0.2
					fx.track_dust(back + side, back - side, (0.7 + spd_m * 0.07) * (0.55 if sim.tkey == "urbano" else 1.0))
				else:
					fx.dust(back + Vector3(randf_range(-1.2, 1.2), 0.3, randf_range(-1.2, 1.2)), 0.8 + spd_m * 0.08)
	return Basis(Vector3.RIGHT, float(v["gp"])) * Basis(Vector3.BACK, float(v["groll"]))

## Velivoli (solo vista): ombra a terra che segue il mezzo e scie di condensazione dei caccia.
func _air_view(u: BattleSim.Unit, v: Dictionary, p: Vector3, yaw: float, spd: float, dt: float, depth: float, mshow: bool) -> void:
	var blob = v.get("blob")
	if blob != null:
		var b3 := blob as Node3D
		var gy := terrain.height(p.x, p.z)
		if sim.sea:
			gy = maxf(gy, 0.0)
		b3.position = Vector3(p.x, gy + 0.35, p.z)
		b3.rotation.y = yaw
		var alt := p.y - gy
		var k := clampf(1.0 - (alt - 15.0) / 90.0, 0.35, 1.0)
		var L0: float = (v["models"][0] as Node3D).get_meta("length", 10.0) * (v["models"][0] as Node3D).scale.x * 1.15
		b3.scale = Vector3(L0 * (0.8 + 0.4 * (1.0 - k)), 1.0, L0 * 0.75 * (0.8 + 0.4 * (1.0 - k)))
		b3.visible = mshow and depth < 420.0
	if u.type == "jet" and dt > 0.0 and spd > 0.5 and depth < 620.0:
		v["ctrail"] = float(v["ctrail"]) - dt
		if float(v["ctrail"]) <= 0.0:
			v["ctrail"] = 0.06 + depth * 0.0002
			var root: Node3D = v["root"]
			var sc: float = (v["models"][0] as Node3D).scale.x
			for sx in [-1.0, 1.0]:
				fx.trail(p + root.basis * (Vector3(sx * 6.4, 1.0, 1.6) * sc), 1.1, Color(0.9, 0.9, 0.93, 0.26))

## Rinculo allo sparo: canna indietro (modello k della vista) e colpo di beccheggio dello scafo.
func _recoil(u: BattleSim.Unit, kick: float) -> void:
	if not views.has(u.id):
		return
	var v: Dictionary = views[u.id]
	v["rec_t"] = 0.0
	v["rec_k"] = int(v.get("mz_k", 0))
	v["pv"] = float(v.get("pv", 0.0)) + kick

var _vfx_n := 0   # effetti Vfx (nodi) creati in questo frame: limite per frame

## Effetto Vfx a nodi (vampa con anello di fumo, bossoli) solo vicino alla telecamera e con un tetto per frame.
func _vfx_near(p: Vector3, max_d: float) -> bool:
	if _vfx_n >= 3 or (p - cam.global_position).length() > max_d:
		return false
	_vfx_n += 1
	return true

## Fanteria (solo vista): corre quando si muove, si accovaccia e si sparpaglia sotto tiro, si ripara a ridosso
## di edifici, boschi e rocce quando è ferma. Restituisce la posizione della vista (spostata verso il riparo).
func _inf_view(u: BattleSim.Unit, v: Dictionary, p: Vector3, spd: float, dt: float) -> Vector3:
	var moving := spd > u.speed * 0.25
	if u.hp < float(v["hp"]) - 0.01:
		v["thr"] = 3.5
	v["thr"] = maxf(0.0, float(v["thr"]) - dt)
	# riparo: ricalcolato a rotazione (ogni ~0.4 s per unità)
	v["cov_k"] = float(v["cov_k"]) - dt
	if v["cov_k"] <= 0.0:
		v["cov_k"] = 0.4
		v["cov_t"] = Vector2.ZERO if moving else _cover_offset(u)
		if float(v["thr"]) <= 0.0:
			for d in _danger:
				if (d[0] as Vector3).distance_squared_to(p) < 196.0:
					v["thr"] = 2.5
					break
	var ct: Vector2 = v["cov_t"]
	var cv: Vector2 = (v["cov"] as Vector2).lerp(ct, minf(1.0, dt * 1.5)) if dt > 0 else ct
	v["cov"] = cv
	var in_cover: bool = ct.length_squared() > 0.01 or bool(v.get("in_wood", false))
	var want := "run" if moving else ("cover" if float(v["thr"]) > 0.0 or in_cover else "base")
	var rig: bool = v.get("rig", false)
	if want != v["inf_var"] and v["inf_mesh"] != null and not rig:
		var mesh = v["inf_mesh"] if want == "base" else BattleProps.inf_squad_mesh(side_color(u.side), want)
		if mesh != null:
			v["inf_var"] = want
			for m in v["models"]:
				var bd = (m as Node3D).get_node_or_null("Body")
				if bd is MeshInstance3D:
					(bd as MeshInstance3D).mesh = mesh
	# sparpagliamento e corsa (oscillazione di ogni squadra con fase propria)
	var spread_t := 1.3 if float(v["thr"]) > 0.0 and not moving else 1.0
	v["spread"] = lerpf(float(v["spread"]), spread_t, minf(1.0, dt * 2.0)) if dt > 0 else spread_t
	var models: Array = v["models"]
	var offs: Array = v["offs"]
	for i in models.size():
		var m: Node3D = models[i]
		var o: Vector3 = offs[i] * float(v["spread"])
		if rig:
			pass    # passo, molleggio e inclinazione nello shader dei soldati
		elif moving:
			o.y = absf(sin(_wall_time * 9.5 + i * 1.7 + u.bob)) * 0.14
			m.rotation.x = -0.07
		else:
			m.rotation.x = 0.0
		m.position = o
	if cv.length_squared() > 0.0001:
		p.x += cv.x; p.z += cv.y
		p.y = terrain.height(p.x, p.z)
	if rig:
		_inf_anim(u, v, p, spd if moving else 0.0, dt, in_cover or float(v["thr"]) > 0.0)
	return p

# ---------------------------------------------------------------- animazione dei soldati (UnitModels / soldier.gdshader)
const INF_ANIM_FAR := 450.0    # oltre questa distanza (m) le pose restano ferme: nessun aggiornamento

func _inf_rig_init(v: Dictionary) -> void:
	var models: Array = v["models"]
	var UM = BattleProps.ext("UnitModels")
	if models.is_empty() or UM == null or not UM.has_method("inf_rigged") or not UM.inf_rigged(models[0]):
		return
	var bodies := []
	for m in models:
		var bd := (m as Node3D).get_node_or_null("Body") as GeometryInstance3D
		bodies.append(bd)
		if bd != null:
			bd.set_instance_shader_parameter(&"seed", randf() * 50.0)
	v["rig"] = true
	v["bodies"] = bodies
	v["ph"] = randf() * TAU
	v["asp"] = 0.0
	v["crk"] = 0.0
	v["aimk"] = 0.0
	v["fire_k"] = 0.0
	v["die"] = []
	v["anim_last"] = []
	for i in models.size():
		v["die"].append(-1.0)
		v["anim_last"].append(Vector4(-9, -9, -9, -9))

## Un modello (gruppo di soldati) della squadra cade (alive = false) o torna in piedi (rinforzi).
func _inf_model_alive(v: Dictionary, i: int, alive: bool) -> void:
	var die: Array = v["die"]
	var m: Node3D = v["models"][i]
	if alive:
		die[i] = -1.0
		m.visible = true
	elif float(die[i]) < 0.0 and m.visible:
		die[i] = 0.0

## Stato dei soldati per lo shader: velocità reale (niente piedi che scivolano), in ginocchio al riparo/sotto tiro/quando
## spara da fermo, fucile in spalla con rinculo quando ingaggia, caduta dei gruppi persi. Una chiamata per gruppo e solo
## se lo stato cambia; oltre INF_ANIM_FAR niente aggiornamenti (a quella distanza il passo non si distingue).
func _inf_anim(u: BattleSim.Unit, v: Dictionary, p: Vector3, spd: float, dt: float, cover: bool) -> void:
	var models: Array = v["models"]
	var sc: float = (models[0] as Node3D).scale.x
	var k := minf(1.0, dt * 6.0)
	v["asp"] = lerpf(float(v["asp"]), spd * S / sc, k)
	var asp: float = v["asp"]
	if asp < 0.05:
		asp = 0.0
	var UM = BattleProps.ext("UnitModels")
	v["ph"] = wrapf(float(v["ph"]) + asp * dt * float(UM.inf_step_rate(asp)), 0.0, TAU * 64.0)
	if u.fire_t > 0.0:
		v["fire_k"] = 1.6
	v["fire_k"] = maxf(0.0, float(v["fire_k"]) - dt)
	var engaged := u.tgt != null and not u.tgt.dead
	var firing := float(v["fire_k"]) > 0.0 and asp <= 0.0
	var aim_t := 1.0 if (engaged or firing) and asp <= 0.0 else 0.0
	var crk_t := 1.0 if asp <= 0.0 and (cover or aim_t > 0.0) else 0.0
	v["crk"] = move_toward(float(v["crk"]), crk_t, dt * 2.5)
	v["aimk"] = move_toward(float(v["aimk"]), aim_t, dt * 4.0)
	var far := (p - cam.global_position).length_squared() > INF_ANIM_FAR * INF_ANIM_FAR
	var bodies: Array = v["bodies"]
	var die: Array = v["die"]
	var last: Array = v["anim_last"]
	for i in bodies.size():
		var bd: GeometryInstance3D = bodies[i]
		if bd == null or not (models[i] as Node3D).visible:
			continue
		var a: Vector4
		if float(die[i]) >= 0.0:
			die[i] = float(die[i]) + dt
			if float(die[i]) > 7.0:
				(models[i] as Node3D).visible = false
				continue
			a = UM.inf_anim_vec(float(v["ph"]), 0.0, float(v["crk"]), 0.0, false, float(die[i]))
		elif far:
			continue
		else:
			a = UM.inf_anim_vec(float(v["ph"]), asp, float(v["crk"]), float(v["aimk"]), firing)
		if a != last[i]:
			last[i] = a
			bd.set_instance_shader_parameter(&"anim", a)

## Squadra distrutta: i soldati ancora in piedi cadono e restano a terra qualche secondo.
func _inf_anim_dying(v: Dictionary, dt: float) -> void:
	var UM = BattleProps.ext("UnitModels")
	var models: Array = v["models"]
	var die: Array = v["die"]
	for i in models.size():
		var m: Node3D = models[i]
		if not m.visible or float(die[i]) < 0.0:
			continue
		die[i] = float(die[i]) + dt
		var bd: GeometryInstance3D = v["bodies"][i]
		if bd != null:
			bd.set_instance_shader_parameter(&"anim", UM.inf_anim_vec(float(v["ph"]), 0.0, float(v["crk"]), 0.0, false, float(die[i])))

## Spostamento (m, piano XZ) verso il riparo più vicino entro ~12 m; Vector2.ZERO se allo scoperto.
func _cover_offset(u: BattleSim.Unit) -> Vector2:
	var best := Vector2.ZERO
	var bd := 48.0
	var v: Dictionary = views[u.id]
	v["in_wood"] = false
	for o in sim.obs:
		var q: Vector2
		var d: float
		if o["rect"]:
			q = Vector2(clampf(u.x, o["x"], o["x"] + o["w"]), clampf(u.y, o["y"], o["y"] + o["h"]))
			d = q.distance_to(Vector2(u.x, u.y))
			if d < bd:
				bd = d
				var dir := (q - Vector2(u.x, u.y)) / maxf(0.001, d)
				best = dir * clampf(d - 7.0, 0.0, 16.0)
		else:
			var c := Vector2(o["x"], o["y"])
			var dc := c.distance_to(Vector2(u.x, u.y))
			d = dc - float(o["r"])
			if d < 0.0:
				v["in_wood"] = true
				return Vector2.ZERO
			if d < bd:
				bd = d
				best = (c - Vector2(u.x, u.y)) / maxf(0.001, dc) * clampf(d - 5.0, 0.0, 16.0)
	if bd >= 48.0:
		return Vector2.ZERO
	if best.length_squared() < 0.01:
		return Vector2(0.001, 0)   # già a ridosso: al riparo senza spostarsi
	return best * S

## Precompila materiali/shader degli effetti e dei relitti (evita scatti alla prima esplosione).
func _prewarm() -> void:
	for k in ["tank", "art", "aa", "heli", "jet", "drone", "inf", "bunker"]:
		var n := BattleProps.wreck_model(k, side_color(0))
		add_child(n)
		n.position = cam.global_position - cam.global_transform.basis.z * 25.0
		n.scale = Vector3.ONE * 0.01
		get_tree().create_timer(0.3).timeout.connect(n.queue_free)
	# suoni della battaglia: Sfx li sintetizza alla prima richiesta (~20 ms l'uno) → generali subito
	var sx = get_node_or_null("/root/Sfx")
	if sx != null:
		if sx.has_method("warm_battle"):
			sx.call("warm_battle")
		elif sx.has_method("_get_stream"):
			for nm in ["explosion", "cannon", "gun", "missile", "alert", "select", "order", "click", "victory", "defeat"]:
				sx.call("_get_stream", nm)
		elif sx.has_method("preload_all"):
			sx.call("preload_all")
	if _um_damage:
		var UM = BattleProps.ext("UnitModels")
		for lvl in [1, 2, 3]:
			var m := BattleProps.unit_model("tank", side_color(0), faction(0))
			add_child(m)
			m.position = cam.global_position - cam.global_transform.basis.z * 25.0
			m.scale = Vector3.ONE * 0.01
			UM.set_damage(m, [0.0, 0.3, 0.6, 0.9][lvl])
			get_tree().create_timer(0.3).timeout.connect(m.queue_free)
	for c in [0, 1]:
		for vname in ["run", "cover"]:
			BattleProps.inf_squad_mesh(side_color(c), vname)
	# effetti Vfx a nodi usati in battaglia (vampa con anello, bossoli, esplosione, ombra dei velivoli): compilati subito
	var V = BattleProps.ext("Vfx")
	if V != null and V.has_method("gun_blast"):
		var wp := cam.global_position - cam.global_transform.basis.z * 25.0
		var hold := Node3D.new()
		add_child(hold)
		hold.position = wp
		hold.scale = Vector3.ONE * 0.01
		V.gun_blast(hold, Vector3.ZERO, Vector3.FORWARD, 1.0, -2.0)
		V.casings(hold, Vector3.ZERO, Vector3.RIGHT, 2, 1.0)
		V.explosion(hold, Vector3.ZERO, 0.5)
		V.shadow_blob(hold, 1.0)
		get_tree().create_timer(0.4).timeout.connect(hold.queue_free)

## Barre/simboli nascosti dietro edifici o rilievi: verifica a rotazione (un quarto delle unità per frame).
func _update_occlusion() -> void:
	var ids := views.keys()
	var n := ids.size()
	if n == 0:
		return
	var cpos := cam.global_position
	var per := maxi(6, n / 6 + 1)
	for k in per:
		_occ_i = (_occ_i + 1) % n
		var v: Dictionary = views[ids[_occ_i]]
		var u: BattleSim.Unit = v["u"]
		if u.dead:
			continue
		var p: Vector3 = v["pos"]
		var top := p + Vector3(0, 2.6 if not u.air else 0.8, 0)
		v["occ"] = terrain.occluded(top, cpos)

func _on_human_hit(u: BattleSim.Unit, p: Vector3) -> void:
	var vis := false
	if not cam.is_position_behind(p):
		var sp := cam.unproject_position(p)
		var sz := get_viewport().get_visible_rect().size
		vis = sp.x > 0 and sp.y > 0 and sp.x < sz.x and sp.y < sz.y
	if vis:
		return
	for a in alerts:
		if (a["p"] as Vector3).distance_to(p) < 110.0:
			a["p"] = p
			a["t"] = 4.0
			return
	alerts.append({"p": p, "t": 4.0})
	if _wall_time - _alert_sfx_t > 7.0:
		_alert_sfx_t = _wall_time
		_sfx("alert", 0)
		hud.flash_alert()

func _update_alerts(dt: float) -> void:
	var i := 0
	while i < alerts.size():
		alerts[i]["t"] -= dt
		if alerts[i]["t"] <= 0:
			alerts.remove_at(i)
			continue
		i += 1

func jump_to_alert() -> void:
	if alerts.is_empty():
		return
	var a: Dictionary = alerts[alerts.size() - 1]
	cam.go_to(a["p"])

# ---------------------------------------------------------------------------- effetti dalla sim
func _sfx(name: String, gap: float) -> void:
	var s = get_node_or_null("/root/Sfx")
	if s == null or not s.has_method("play"):
		return
	var last: float = _sfx_t.get(name, -100.0)
	if _wall_time - last < gap:
		return
	_sfx_t[name] = _wall_time
	s.call("play", name)

func _muzzle_of(u: BattleSim.Unit) -> Vector3:
	if views.has(u.id):
		var v: Dictionary = views[u.id]
		var mz: Array = v["muzzles"]
		var models: Array = v["models"]
		var k := randi() % maxi(1, mini(int(v["vis"]), mz.size()))
		v["mz_k"] = k
		if k < mz.size() and mz[k] != null and models[k].visible:
			return (mz[k] as Node3D).global_position
		var p: Vector3 = v["pos"]
		return p + Vector3(cos(u.tur), 0, sin(u.tur)) * u.r * S * 0.9 + Vector3(0, 1.6 if not u.air else -0.5, 0)
	return _unit_pos(u)

func _consume_fx(silent: bool) -> void:
	if sim.fx.is_empty():
		return
	var list := sim.fx
	sim.fx = []
	_vfx_n = 0
	if not silent and audio != null:
		audio.on_fx(list)
	for e in list:
		match e["e"]:
			"fire":
				if not silent:
					_on_fire(e)
					_on_fire_tactical(e)
			"spotted":
				if not silent:
					_on_spotted(e)
			"ambush":
				if not silent:
					_on_ambush(e)
			"mine":
				_on_mine(e, silent)
			"mines_spotted":
				if not silent and sim.hs >= 0:
					var mw := BattleTerrain.sim_to_world(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
					var mp := Vector3(mw.x, maxf(terrain.height(mw.x, mw.y), 0.0) + 3.0, mw.y)
					pings.append({"p": mp, "t": 0.0, "col": Color(1.0, 0.7, 0.2)})
					float_text(mp, "CAMPO MINATO", Color(1.0, 0.6, 0.25), false, 2.0)
					if sim.hs == 0:
						toast("Campo minato individuato: i mezzi devono aggirarlo", Color(1.0, 0.7, 0.35))
			"impact":
				var big: bool = e["big"]
				var r := 5.0 + 5.0 * (0.7 + randf() * 0.5) * (1.3 if big else 1.0)
				terrain.paint_crater(e["x"], e["y"], r)
				if not silent:
					var w := BattleTerrain.sim_to_world(e["x"], e["y"])
					var p := Vector3(w.x, terrain.height(w.x, w.y), w.y)
					if sim.sea and p.y < 0:
						p.y = 0.0
					fx.explosion(p, 1.25 if big else 0.95, true)
					_danger.append([p, _wall_time])
					_shake(p, 0.6)
				# Fase 8: cratere vero e danni all'ambiente (anche nell'avanzamento rapido: restano)
				if marks != null:
					var w2 := BattleTerrain.sim_to_world(e["x"], e["y"])
					var p2 := Vector3(w2.x, terrain.height(w2.x, w2.y), w2.y)
					if not (sim.sea and p2.y <= 0.05):
						marks.crater(e["x"], e["y"], r * (1.1 if big else 0.85), 0.55 if big else 0.4)
					marks.blast(p2, 5.5 if big else 4.0, 1.0 if big else 0.7, silent)
			"weather":
				if not silent and weather != null:
					var old := weather.kind
					var nk := String(e["kind"])
					var txt := weather.change_text(old, nk)
					if txt != "":
						toast(txt, Color(0.8, 0.9, 1.0))
					if hud != null:
						hud.set_conditions(_conditions_text())
			"flare":
				if not silent and weather != null:
					weather.on_flare(e)
					if sim.hs >= 0 and int(e.get("side", 0)) != sim.hs:
						var fw := BattleTerrain.sim_to_world(float(e["x"]), float(e["y"]))
						pings.append({"p": Vector3(fw.x, terrain.height(fw.x, fw.y), fw.y), "t": 0.0, "col": Color(1.0, 0.9, 0.6)})
			"kill":
				_on_kill(e, silent)
			"barrage":
				if not silent:
					_sfx("alert", 0.5)
			"smoke":
				if not silent:
					_on_smoke(e)
			"airstrike":
				if not silent:
					_start_jet(e)
			"bomb":
				_on_bomb(e, silent)
			# omogeneità (docs/omogeneita.md): obiettivi, rinforzi, ritirata
			"objective":
				if not silent:
					var ow := BattleTerrain.sim_to_world(float(e["x"]), float(e["y"]))
					var op := Vector3(ow.x, terrain.height(ow.x, ow.y) + 2.0, ow.y)
					var mine: bool = sim.hs < 0 or int(e["side"]) == sim.hs
					float_text(op, String(e["name"]).to_upper(), side_color(int(e["side"])).lightened(0.2), true, 2.2)
					if sim.hs >= 0:
						toast(("Obiettivo conquistato: " if mine else "Obiettivo perduto: ") + String(e["name"]), Color(0.6, 1.0, 0.6) if mine else Color(1.0, 0.6, 0.5))
						_sfx("capture" if mine else "alert", 0.3)
			"reinf":
				if not silent:
					var rw := BattleTerrain.sim_to_world(float(e["x"]), float(e["y"]))
					pings.append({"p": Vector3(rw.x, terrain.height(rw.x, rw.y) + 2.0, rw.y), "t": 0.0, "col": side_color(int(e["side"]))})
					if sim.hs >= 0:
						var mine2: bool = int(e["side"]) == sim.hs
						toast(("Rinforzi arrivati dal territorio vicino: %d unità" if mine2 else "Rinforzi nemici in campo: %d unità") % int(e["n"]), Color(0.6, 1.0, 0.6) if mine2 else Color(1.0, 0.7, 0.4))
				for u in sim.units:
					if not u.dead and not views.has(u.id):
						_make_view(u)
			"escape":
				_on_kill(e, true)   # il reparto lascia il campo: via dalla vista, senza relitto
			"retreat":
				if not silent and sim.hs >= 0:
					toast("Ritirata ordinata: i reparti ripiegano verso il bordo" if int(e["side"]) == sim.hs else "Il nemico si ritira!", Color(1.0, 0.85, 0.5))

# ---------------------------------------------------------------------------- abilità: fumo e supporto aereo
var _smoke_plumes := 0

func _on_smoke(e: Dictionary) -> void:
	var u: BattleSim.Unit = e["u"]
	if not views.has(u.id):
		return
	var p: Vector3 = views[u.id]["pos"]
	fx.smoke_screen(p, 1.2, 5)
	views[u.id]["smk2"] = 0.3
	# lanciagranate fumogene: pennacchio iniziale (Vfx dell'Agente F, ricolorato bianco e senza fiamme)
	if _smoke_plumes < 8:
		var V = BattleProps.ext("Vfx")
		if V != null and V.has_method("smoke"):
			var n = V.smoke(self, p + Vector3(0, 0.8, 0), 2.5)
			if n is Node3D:
				_smoke_plumes += 1
				get_tree().create_timer(1.0).timeout.connect(func() -> void: _smoke_plumes = maxi(0, _smoke_plumes - 1))
				var parts := (n as Node).find_children("*", "CPUParticles3D", true, false)
				for i in parts.size():
					var cp := parts[i] as CPUParticles3D
					if i == 0:
						var g := Gradient.new()
						g.set_color(0, Color(0.95, 0.95, 0.94, 0.0))
						g.set_color(1, Color(0.85, 0.86, 0.85, 0.0))
						g.add_point(0.1, Color(0.95, 0.95, 0.94, 0.75))
						g.add_point(0.6, Color(0.88, 0.89, 0.88, 0.45))
						cp.color_ramp = g
						cp.gravity = Vector3(0.6, -1.2, 0.2)
					else:
						cp.emitting = false
						cp.visible = false

## Passaggio del caccia: picchiata verso il bersaglio (sopra al punto dopo `delay` s), sgancio, richiamata.
func _start_jet(e: Dictionary) -> void:
	var si: int = e["side"]
	var w := BattleTerrain.sim_to_world(e["x"], e["y"])
	var gy := maxf(terrain.height(w.x, w.y), 0.0)
	var n := BattleProps.unit_model("jet", side_color(si), faction(si))
	add_child(n)
	var fwd := Vector3(float(e["dir"]), 0, 0).rotated(Vector3.UP, 0.18 * float(e["dir"]))
	_jets.append({"n": n, "T": Vector3(w.x, gy, w.y), "fwd": fwd, "t": -float(e["delay"]), "trail": 0.0, "snd": false})
	_sfx("alert", 0.3)
	_update_jets(0.0)

const JET_V := 78.0

func _jet_pos(j: Dictionary, tau: float) -> Vector3:
	var h: float
	if tau < 0.0:
		h = 24.0 + minf(-tau, 3.2) * 19.0
	else:
		h = 24.0 + tau * 9.0 + tau * tau * 12.0
	return (j["T"] as Vector3) + (j["fwd"] as Vector3) * JET_V * tau + Vector3(0, h, 0)

func _update_jets(dt: float) -> void:
	var i := 0
	while i < _jets.size():
		var j: Dictionary = _jets[i]
		j["t"] = float(j["t"]) + dt
		var tau: float = j["t"]
		var n: Node3D = j["n"]
		if tau > 4.5:
			n.queue_free()
			_jets.remove_at(i)
			continue
		var p := _jet_pos(j, tau)
		var q := _jet_pos(j, tau + 0.05)
		n.position = p
		if not p.is_equal_approx(q):
			n.look_at(q, Vector3.UP)
		n.rotate_object_local(Vector3.BACK, sin(clampf(tau, -1.0, 1.5) * 2.0) * 0.25)
		if dt > 0.0:
			j["trail"] = float(j["trail"]) - dt
			if j["trail"] <= 0.0:
				j["trail"] = 0.03
				var back := -(q - p).normalized()
				fx.trail(p + back * 7.0, 0.7, Color(0.8, 0.8, 0.82, 0.35))
			if not j["snd"] and tau > -1.2:
				j["snd"] = true
		i += 1

func _on_bomb(e: Dictionary, silent: bool) -> void:
	var r := 7.0 + randf() * 2.0
	terrain.paint_crater(e["x"], e["y"], r)
	var w := BattleTerrain.sim_to_world(e["x"], e["y"])
	var p := Vector3(w.x, terrain.height(w.x, w.y), w.y)
	if sim.sea and p.y < 0:
		p.y = 0.0
	if marks != null:
		if not (sim.sea and p.y <= 0.05):
			marks.crater(e["x"], e["y"], r * 1.5, 0.9)
		marks.blast(p, 9.0, 2.2, silent)
	if silent:
		return
	fx.explosion(p, 1.7, true)
	var V = BattleProps.ext("Vfx")
	if V != null and V.has_method("explosion") and randf() < 0.5:
		V.explosion(self, p, 1.3)
	_danger.append([p, _wall_time])
	_shake(p, 0.9)

func _shake(p: Vector3, s: float) -> void:
	var d := p.distance_to(cam.global_position)
	if d < 120.0:
		cam.shake = minf(1.0, cam.shake + s * (1.0 - d / 120.0) * 0.5)

func _on_fire(e: Dictionary) -> void:
	var u: BattleSim.Unit = e["u"]
	if not views.has(u.id):
		return
	var a := _muzzle_of(u)
	var dir3 := Vector3(cos(u.tur), 0, sin(u.tur))
	var V = BattleProps.ext("Vfx")
	if e.get("art", false):
		var ad := (dir3 + Vector3(0, 0.6, 0)).normalized()
		fx.muzzle(a, ad, 2.2)
		fx.light(a, 3.0, 12.0, 0.12)
		_recoil(u, 1.4)
		if (a - cam.global_position).length() < 320.0:
			fx.blast_dust(Vector3(a.x, terrain.height(a.x, a.z), a.z), Vector3(ad.x, 0, ad.z).normalized(), 1.3)
		if V != null and V.has_method("gun_blast") and _vfx_near(a, 260.0):
			V.gun_blast(self, a, ad, 1.5, terrain.height(a.x, a.z))
		return
	var t: BattleSim.Unit = e["t"]
	var b := _target_point(t) if not t.dead or views.has(t.id) else _unit_pos(t)
	var jr := t.r * S * 0.5
	b += Vector3((randf() - 0.5) * jr, (randf() - 0.3) * 0.6, (randf() - 0.5) * jr)
	var dist := a.distance_to(b)
	match u.type:
		"inf":
			var v: Dictionary = views[u.id]
			var base: Vector3 = v["pos"]
			# razzo anticarro (BattleAudio ne suona uno ~30% delle volte contro i mezzi): scia di fumo e colpo sul mezzo
			var rk = e.get("rocket")
			if rk == null:
				rk = t.type in ["tank", "art", "aa"] and randf() < 0.3
			if bool(rk):
				var o2 := base + Vector3(0, 1.2, 0)
				var TT := clampf(dist / 120.0, 0.25, 1.6)
				fx.missile(o2, b, TT)
				fx.muzzle(o2, (b - o2).normalized(), 0.6)
				_delay(TT, "hit_big", b, 0.8)
			for k in 2 + randi() % 2:
				var o := base + Vector3((randf() - 0.5) * 3.0, 1.3, (randf() - 0.5) * 3.0)
				fx.tracer(o, b + Vector3((randf() - 0.5) * 2.0, 0, (randf() - 0.5) * 2.0), maxf(0.06, dist / 420.0), 0.05, 2.4, Color(1.0, 0.85, 0.45, 0.9))
				fx.muzzle(o, (b - o).normalized(), 0.25)
			if V != null and V.has_method("casings") and _vfx_near(base, 90.0):
				var fd := (b - base).normalized()
				V.casings(self, base + Vector3(0, 1.1, 0) + fd * 0.6, fd.cross(Vector3.UP), 5, 0.9)
			if not t.air:
				_delay(dist / 420.0, "dust", b, 0.5)
		"tank":
			var d := (b - a).normalized()
			fx.muzzle(a, d, 1.6)
			fx.light(a, 2.5, 10.0, 0.08)
			fx.tracer(a, b, maxf(0.06, dist / 900.0), 0.16, 7.0, Color(1.0, 0.8, 0.5, 1.0))
			_delay(dist / 900.0, "hit_big" if not t.air else "hit", b, 1.0)
			_recoil(u, 1.0)
			if (a - cam.global_position).length() < 300.0:
				var g := a + d * 2.5
				fx.blast_dust(Vector3(g.x, terrain.height(g.x, g.z), g.z), Vector3(d.x, 0, d.z).normalized(), 1.0)
			if V != null and V.has_method("gun_blast") and _vfx_near(a, 240.0):
				V.gun_blast(self, a, d, 1.0, terrain.height(a.x, a.z))
		"aa":
			for k in [-1, 1]:
				var o := a + dir3.cross(Vector3.UP) * 0.5 * float(k)
				for j in 2:
					fx.tracer(o, b + Vector3((randf() - 0.5) * 3.0, (randf() - 0.5) * 3.0, (randf() - 0.5) * 3.0), maxf(0.08, dist / 700.0) + j * 0.03, 0.08, 3.5, Color(1.0, 0.65, 0.35, 0.95))
			fx.muzzle(a, (b - a).normalized(), 0.6)
			_recoil(u, 0.15)
			if V != null and V.has_method("casings") and _vfx_near(a, 120.0):
				V.casings(self, a - dir3 * 3.2 + Vector3(0, -0.4, 0), dir3.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0), 6, 1.6)
			if t.air:
				_delay(dist / 700.0, "flak", b, 1.0)
			else:
				_delay(dist / 700.0, "hit", b, 0.6)
		"heli", "jet":
			var T := 0.3 if u.type == "jet" else 0.36
			fx.missile(a, b, T)
			fx.muzzle(a, (b - a).normalized(), 0.7)
			_delay(T, "hit_big", b, 0.9)
		"drone":
			fx.tracer(a, b, maxf(0.06, dist / 500.0), 0.07, 3.0, Color(0.7, 0.9, 1.0, 0.9))
			_delay(dist / 500.0, "hit", b, 0.5)
		_:
			fx.tracer(a, b, maxf(0.06, dist / 500.0), 0.09, 3.0, Color(1.0, 0.85, 0.5, 0.95))
			fx.muzzle(a, (b - a).normalized(), 0.7)
			_delay(dist / 500.0, "dust", b, 0.7)

func _delay(t: float, kind: String, p: Vector3, s: float) -> void:
	pending.append([t, kind, p, s])

func _run_pending(dt: float) -> void:
	var i := 0
	while i < pending.size():
		var e: Array = pending[i]
		e[0] -= dt
		if e[0] <= 0:
			var p: Vector3 = e[2]
			match e[1]:
				"dust": fx.dust(p, e[3])
				"hit": fx.hit(p, e[3], p.y - terrain.height(p.x, p.z) < 2.5)
				"hit_big":
					fx.hit(p, 1.6 * e[3], p.y - terrain.height(p.x, p.z) < 2.5)
					fx.light(p, 2.0, 9.0, 0.1)
				"flak": fx.flak(p + Vector3((randf() - 0.5) * 4, (randf() - 0.5) * 3, (randf() - 0.5) * 4))
			pending.remove_at(i)
			continue
		i += 1

func _on_kill(e: Dictionary, silent: bool) -> void:
	var u: BattleSim.Unit = e["u"]
	var w := BattleTerrain.sim_to_world(e["x"], e["y"])
	var gy := terrain.height(w.x, w.y)
	if sim.sea:
		gy = maxf(gy, 0.0)
	var ground_p := Vector3(w.x, gy, w.y)
	var t: String = e["type"]
	var big := 0.5 if t == "inf" else (2.0 if t == "bunker" else 1.2)
	_last_kill_p = ground_p if not e["air"] else (_unit_pos(u) if views.has(u.id) else ground_p)
	_last_kill_t = _wall_time
	_danger.append([ground_p, _wall_time])
	if views.has(u.id):
		var v: Dictionary = views[u.id]
		if not (t == "inf" and v.get("rig", false)):   # la fanteria animata cade a terra (_update_views)
			v["root"].visible = false
		v["ring"].visible = false
	if not e["air"]:
		terrain.paint_crater(e["x"], e["y"], 5 + 5 * big * (0.7 + randf() * 0.5))
		if t != "inf" and marks != null:
			marks.blast(ground_p, 4.0 * big, 0.6 * big, silent)
			if not (sim.sea and ground_p.y <= 0.05):
				marks.crater(e["x"], e["y"], 4.0 + 4.0 * big, 0.3)
	if t == "inf":
		if not silent:
			fx.explosion(ground_p, 0.45, true)
		return
	var p := _unit_pos(u) if views.has(u.id) else ground_p
	if e["air"]:
		if t == "drone":
			if not silent:
				fx.explosion(p, 0.5, false)
			return
		if silent:
			_add_wreck(t, ground_p, -u.ang - PI / 2, u.side, 18.0)
		else:
			fx.explosion(p, 1.0, false)
			var node := BattleProps.wreck_model(t, side_color(u.side))
			add_child(node)
			node.position = p
			node.rotation = Vector3(0, -u.ang - PI / 2, 0)
			falling.append({"n": node, "v": Vector3(u.vx * S * 0.6, 0, u.vy * S * 0.6), "t": t, "side": u.side, "spin": randf_range(-3, 3), "smk": 0.0})
		return
	if not silent:
		fx.explosion(ground_p, big, true)
		_shake(ground_p, 0.8 if big > 1.5 else 0.5)
	_add_wreck(t, ground_p, -u.ang - PI / 2, u.side, 0.0)
	if not silent and t in ["tank", "art", "aa"]:
		var near := (ground_p - cam.global_position).length() < 230.0
		var V = BattleProps.ext("Vfx")
		if near and V != null and V.has_method("explosion"):
			V.explosion(self, ground_p, 1.1 if t == "tank" else 1.3)
		# distruzione catastrofica: la torretta salta via e ricade capovolta poco lontano
		if randf() < (0.7 if near else 0.45) and not wrecks.is_empty():
			_turret_pop(wrecks[wrecks.size() - 1]["n"], u)

var _tumbling: Array = []   # torrette in volo {n, v, w, smk}

func _turret_pop(wreck: Node3D, u: BattleSim.Unit) -> void:
	var tur := wreck.find_child("Turret", true, false) as Node3D
	if tur == null:
		return
	var gt := tur.global_transform
	tur.get_parent().remove_child(tur)
	add_child(tur)
	tur.global_transform = gt
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.5, 4.0)
	_tumbling.append({"n": tur, "v": side + Vector3(0, randf_range(9.0, 15.0), 0) + Vector3(u.vx, 0, u.vy) * S * 0.3,
		"w": Vector3(randf_range(-5, 5), randf_range(-6, 6), randf_range(-5, 5)), "smk": 0.0})

func _add_wreck(t: String, p: Vector3, yaw: float, side: int, age: float) -> void:
	var node := BattleProps.wreck_model(t, side_color(side))
	add_child(node)
	node.position = p + Vector3(0, -0.1, 0)
	var n := terrain.normal(p.x, p.z)
	var b := Basis(Vector3.UP, yaw + randf_range(-0.3, 0.3))
	if t == "heli" or t == "jet":
		b = b * Basis(Vector3.BACK, randf_range(-0.6, 0.6)) * Basis(Vector3.RIGHT, randf_range(-0.2, 0.2))
	var x := n.cross(b.z).normalized()
	var z := x.cross(n).normalized()
	node.basis = Basis(x, n, z) if t != "heli" and t != "jet" else b
	if wrecks.size() >= 60:
		var old: Dictionary = wrecks.pop_front()
		old["n"].queue_free()
	wrecks.append({"n": node, "p": p + Vector3(0, 1.2, 0), "age": age, "smk": 0.0})

func _update_wrecks(dt: float) -> void:
	for w in wrecks:
		w["age"] += dt
		w["smk"] -= dt
		# fiamme dense nel primo mezzo minuto, poi fumo nero che si dirada per oltre un minuto
		if w["age"] < 80.0 and w["smk"] <= 0:
			w["smk"] = 0.2 + w["age"] * 0.03
			fx.burn(w["p"], clampf(1.25 - w["age"] / 60.0, 0.1, 1.0))
	# torrette saltate in aria: parabola con rotazione, impatto a terra con polvere, poi relitto fumante
	var j := 0
	while j < _tumbling.size():
		var f: Dictionary = _tumbling[j]
		var n: Node3D = f["n"]
		f["v"].y -= 12.0 * dt
		n.position += f["v"] * dt
		n.rotation += f["w"] * dt
		f["smk"] -= dt
		if f["smk"] <= 0:
			f["smk"] = 0.06
			fx.burn(n.position, 0.9)
		var gy := terrain.height(n.position.x, n.position.z)
		if sim.sea:
			gy = maxf(gy, 0.0)
		if n.position.y <= gy + 0.45 and f["v"].y < 0.0:
			n.position.y = gy + 0.25
			n.rotation = Vector3(randf_range(-0.35, 0.35), n.rotation.y, (randf_range(2.7, 3.5) if randf() < 0.55 else randf_range(-0.4, 0.4)))
			fx.dust(n.position, 2.2)
			fx.dust(n.position + Vector3(1.0, 0, 0), 1.6)
			_shake(n.position, 0.3)
			if wrecks.size() >= 60:
				var old: Dictionary = wrecks.pop_front()
				old["n"].queue_free()
			wrecks.append({"n": n, "p": n.position + Vector3(0, 0.6, 0), "age": 30.0, "smk": 0.0})
			_tumbling.remove_at(j)
			continue
		j += 1
	var i := 0
	while i < falling.size():
		var f: Dictionary = falling[i]
		var n: Node3D = f["n"]
		f["v"].y -= 14.0 * dt
		n.position += f["v"] * dt
		n.rotate_y(f["spin"] * dt)
		n.rotate_object_local(Vector3.BACK, dt * 0.8)
		f["smk"] -= dt
		if f["smk"] <= 0:
			f["smk"] = 0.04
			fx.burn(n.position, 1.0)
		var gy := terrain.height(n.position.x, n.position.z)
		if sim.sea:
			gy = maxf(gy, 0.0)
		if n.position.y <= gy + 0.5:
			var p := Vector3(n.position.x, gy, n.position.z)
			fx.explosion(p, 1.3, true)
			_shake(p, 0.6)
			var sp := BattleTerrain.world_to_sim(p.x, p.z)
			terrain.paint_crater(sp.x, sp.y, 9)
			n.queue_free()
			_add_wreck(f["t"], p, n.rotation.y, f["side"], 0.0)
			falling.remove_at(i)
			continue
		i += 1

func _update_shells(dt: float) -> void:
	_shell_trail_t -= dt
	var trail := _shell_trail_t <= 0
	if trail:
		_shell_trail_t = 0.03
	for s in sim.shells:
		if not s.on:
			continue
		var f: float = clampf(s.t / s.T, 0.0, 1.0)
		var a := BattleTerrain.sim_to_world(s.x0, s.y0)
		var b := BattleTerrain.sim_to_world(s.x1, s.y1)
		var h0 := 2.5 if not s.barrage else 90.0
		if not s.barrage:
			h0 += terrain.height(a.x, a.y)
		var h1 := terrain.height(b.x, b.y)
		var d := a.distance_to(b)
		var peak := maxf(14.0, d * 0.32)
		var p2 := a.lerp(b, f)
		var y := lerpf(h0, h1, f) + 4.0 * peak * f * (1.0 - f)
		var f2 := minf(1.0, f + 0.02)
		var p3 := a.lerp(b, f2)
		var y2 := lerpf(h0, h1, f2) + 4.0 * peak * f2 * (1.0 - f2)
		var pos := Vector3(p2.x, y, p2.y)
		fx.shell_draw(pos, Vector3(p3.x, y2, p3.y) - pos, trail)

# ---------------------------------------------------------------------------- ciclo
func _process(delta: float) -> void:
	if sim == null:
		return
	var dt := minf(delta, 0.1)
	if slowmo > 0.0:
		slowmo -= dt
		dt *= 0.25
	_wall_time += dt
	if intro_t >= 0:
		_update_intro(dt)
	if delta > 0:
		fps_avg = lerpf(fps_avg, 1.0 / delta, 0.05) if fps_avg > 0 else 1.0 / delta
		if _demo and _shot_arg("fps", "0") == "1":
			_fps_probe(delta)
	if deploying:
		deploy_left -= dt
		if deploy_left <= 0:
			end_deploy()
	_pt(-1)
	_frame_n += 1
	if not _booms.is_empty() and _wall_time >= float(_booms[0]):
		_booms.pop_front()
		_demo_boom()
	if not _boom_frames.is_empty() and _frame_n >= int(_boom_frames[0]):
		_boom_frames.pop_front()
		_demo_boom()
	if not sim.done:
		sim.step(dt)
	_pt(0)
	_consume_fx(false)
	if audio != null:
		audio.update(dt)
	_pt(1)
	var frozen := sim.paused and sim.ending == null and not sim.done and intro_t < 0
	var vdt := 0.0 if frozen else dt
	_update_views(vdt)
	if photo:
		# modalità foto: niente anelli di selezione, cursore, indicatori d'ordine
		for id in views:
			(views[id]["ring"] as MeshInstance3D).visible = false
		_cursor_ring.visible = false
		orders.visible = false
		for m in _markers:
			if m is Dictionary and m.has("n"):
				(m["n"] as Node3D).visible = false
	elif not orders.visible:
		orders.visible = true
	_pt(2)
	_update_occlusion()
	_pt(3)
	if not _danger.is_empty() and _wall_time - float(_danger[0][1]) > 2.0:
		var k := 0
		while k < _danger.size() and _wall_time - float(_danger[k][1]) > 2.0:
			k += 1
		_danger = _danger.slice(k)
	if not frozen:
		_run_pending(dt)
		_update_jets(dt)
		_update_wrecks(dt)
		_update_alerts(dt)
	_pt(4)
	_update_shells(vdt)
	fx.update(dt, frozen)
	_pt(5)
	terrain.update_view(cam.dist, dt)   # crateri, vista d'insieme (carta tattica), suolo deformato
	_wood_t -= delta
	terrain.update_woods(cam.global_position, _focus, minf(delta, 0.1), _wood_t <= 0.0)
	if _wood_t <= 0.0:
		_wood_t = 0.15
	weather.update(dt, frozen or photo, cam, cam.dist)
	marks.update(dt, frozen or photo)
	_update_tilt()
	if strat != null:
		strat.update(delta, cam.dist)
	_pt(6)
	sun.directional_shadow_max_distance = clampf(cam.dist * 2.2 + 40.0, 120.0, 400.0) * _shadow_k
	# vista d'insieme: niente ombre (le cascate molto ampie scuriscono il suolo a fasce e costano), le pedine bastano
	var want_sh := cam.dist < (150.0 if sun.shadow_enabled else 135.0) and _shot_arg("shadow", "1") != "0"
	if want_sh != sun.shadow_enabled:
		sun.shadow_enabled = want_sh
	for sh in _ships:
		var n: Node3D = sh[0]
		n.position.y = sin(_wall_time * 0.6 + sh[1]) * 0.25
		n.rotation.z = sin(_wall_time * 0.45 + sh[1]) * 0.02
	if coast != null:
		coast.update(dt, frozen or intro_t >= 0)
	orders.update(dt)
	_update_markers(dt)
	_update_cursor()
	_update_tactical(delta)
	fort.update(dt)
	_pt(7)
	hud.refresh()
	_pt(8)
	_check_end(dt)
	_pt_end(delta)

# profilatura (--prof=1): tempi per sezione del frame, stampa dei frame lenti
const PT_NAMES := ["sim", "fx_ev", "views", "occl", "pend/wreck", "shell/fx", "scorch", "misc", "hud"]
var _prof := 0
var _pt_t := 0
var _pt_cur := PackedInt32Array()
var _pt_last := PackedInt32Array()
var _pt_max := PackedInt32Array()
var _pt_slow := 0
var _pt_acc := 0.0
func _pt(i: int) -> void:
	if _prof == 0:
		return
	var now := Time.get_ticks_usec()
	if i >= 0:
		_pt_cur[i] = int(now - _pt_t)
	else:
		_pt_cur.fill(0)
	_pt_t = now

func _pt_end(delta: float) -> void:
	if _prof == 0:
		return
	var tot := 0
	for i in _pt_cur.size():
		tot += _pt_cur[i]
		_pt_max[i] = maxi(_pt_max[i], _pt_cur[i])
	# un delta lungo riflette il frame precedente (script + rendering)
	if delta > 0.022 and _wall_time > 3.0:
		_pt_slow += 1
		var parts := []
		for i in _pt_last.size():
			if _pt_last[i] > 300:
				parts.append("%s %.1f" % [PT_NAMES[i], _pt_last[i] / 1000.0])
		var rid := get_viewport().get_viewport_rid()
		print("[prof] frame %.1f ms  (script prec. %s)  render cpu %.1f gpu %.1f  draw %d  t=%.1f" % [delta * 1000.0, ", ".join(PackedStringArray(parts)),
			RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(rid),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), sim.time])
	_pt_last = _pt_cur.duplicate()
	_pt_acc += delta
	if _pt_acc >= 10.0:
		_pt_acc = 0.0
		var parts := []
		for i in _pt_max.size():
			parts.append("%s %.1f" % [PT_NAMES[i], _pt_max[i] / 1000.0])
		print("[prof] max 10s: ", ", ".join(PackedStringArray(parts)), "  lenti ", _pt_slow, "  fx ", fx.counts(), "  draw ", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_pt_max.fill(0)
		_pt_slow = 0

var _fps_acc := [0.0, 0, 0.0, 0.0]   # tempo, frame, peggior frame, prossima stampa
func _fps_probe(delta: float) -> void:
	if _wall_time < 3.0:
		return
	_fps_acc[0] += delta
	_fps_acc[1] += 1
	_fps_acc[2] = maxf(_fps_acc[2], delta)
	var rid := get_viewport().get_viewport_rid()
	_fps_acc[3] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if _fps_acc[0] >= 5.0:
		if _prof == 1:
			print("[gpu] media %.2f ms/frame  qualità %s%s" % [_fps_acc[3] / maxf(1.0, _fps_acc[1]), "ultra" if ultra else quality, "" if get_viewport().scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2 else " +FSR2"])
		var n := 0
		for u in sim.units:
			if not u.dead: n += 1
		print("[fps] media %.1f  peggiore %.1f  unità %d  t=%.0f  risoluzione %s" % [_fps_acc[1] / _fps_acc[0], 1.0 / _fps_acc[2], n, sim.time, str(get_viewport().get_visible_rect().size)])
		_fps_acc = [0.0, 0, 0.0, 0.0]

## Perdite per lato (unità iniziali − superstiti), per il riepilogo finale.
func losses(si: int) -> Dictionary:
	var orig: Dictionary = sim.sides[si]["forces"]
	var surv: Dictionary = sim.result[("att" if si == 0 else "def")] if sim.result != null else sim.live_forces(si)
	var out := {}
	for k in Data.UNIT_KEYS:
		var l := int(orig.get(k, 0)) - int(surv.get(k, 0))
		if l > 0:
			out[k] = l
	return out

func _check_end(dt: float) -> void:
	if sim.ending != null and not sim.done and not _slow_done and sim.result != null:
		_slow_done = true
		if _wall_time - _last_kill_t < 2.0 and _last_kill_p.x != INF:
			slowmo = 1.7
			if _demo:
				print("[battle] rallentatore finale t=%.1f" % sim.time)
			cam.go_to(_last_kill_p, clampf(cam._t_dist * 0.8, 45.0, 90.0))
	if slowmo > 0.0 and not sim.done:
		return
	if (sim.ending != null or sim.done) and not _msg_shown and sim.result != null:
		_msg_shown = true
		if deploying:
			end_deploy()
		var r: Dictionary = sim.result
		var w: String = r["winner"]
		var txt: String
		var col: Color
		if sim.hs >= 0:
			var win := (w == "att") == (sim.hs == 0)
			txt = "VITTORIA" if win else "SCONFITTA"
			col = Color(0.35, 0.9, 0.45) if win else Color(0.95, 0.3, 0.25)
			_sfx("victory" if win else "defeat", 0)
		else:
			txt = "VINCE L'ATTACCANTE" if w == "att" else "VINCE IL DIFENSORE"
			col = side_color(0 if w == "att" else 1).lightened(0.2)
		var sub: String
		if r.get("retreated", false):
			sub = "Ritirata: le forze superstiti ripiegano"
			txt = "RITIRATA"
			col = Color(0.95, 0.7, 0.3)
		elif r.get("autoRest", false):
			sub = "Il resto dello scontro viene risolto in automatico (sotto: le perdite sul campo finora)"
			txt = "RISOLUZIONE AUTOMATICA"
			col = Color(0.85, 0.85, 0.75)
		elif sim.ending != null and sim.ending["why"] == "stallo":
			sub = "Stallo: il difensore mantiene la posizione"
		else:
			sub = "Il territorio è stato conquistato" if w == "att" else "L'attacco è stato respinto"
		hud.show_message(txt, sub, col, [losses(0), losses(1)])
		if _demo:
			print("[battle] messaggio: ", txt, " wall=%.1f" % _wall_time)
		mode = ""
		drag_active = false
		alerts.clear()
		var quick: bool = r.get("retreated", false) or r.get("autoRest", false)
		_end_wait = 1.2 if quick else (7.0 if sim.hs >= 0 else 3.5)
		if _demo and _shot_arg("hold", "0") == "1":
			_end_wait = 1e9
	if sim.done and not _emitted and _msg_shown:
		_end_t += dt
		if (_end_t >= _end_wait or _continue) and _outro_t < 0.0:
			# uscita: la telecamera risale verso il cielo (il tabellone riparte dallo stesso punto), poi il risultato
			_outro_t = 0.0
			_outro_a = {"t": cam.target, "d": cam.dist, "y": cam.yaw}
			cam.keys_enabled = false
			cam.edge_pan = false
		if _outro_t >= 0.0:
			_outro_t += dt
			var f := clampf(_outro_t / OUTRO_T, 0.0, 1.0) if (OUTRO_T > 0.0 and not _demo) else 1.0
			var e := f * f * (3.0 - 2.0 * f)
			cam.place(_outro_a["t"], lerpf(float(_outro_a["d"]), cam.max_dist, e), float(_outro_a["y"]))
			if f >= 1.0:
				_emitted = true
				finished.emit(sim.result)

## Pulsante "Continua" del riepilogo finale.
func continue_now() -> void:
	_continue = true

## Demo: bomba sull'edificio/albero più vicino al bersaglio della telecamera (o sul bersaglio stesso).
func _demo_boom() -> void:
	var tg: Vector3 = cam.target
	var p := Vector3(tg.x, terrain.height(tg.x, tg.z), tg.z)
	var bd := 1e18
	for it in marks.items:
		if not it["alive"] or not (String(it["kind"]) in ["bld", "city"]):
			continue
		var d: float = (it["p"] as Vector3).distance_squared_to(tg)
		if d < bd and d < 60.0 * 60.0:
			bd = d
			p = it["p"] as Vector3
			p.y = terrain.height(p.x, p.z)
	p += Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
	var sp := BattleTerrain.world_to_sim(p.x, p.z)
	terrain.paint_crater(sp.x, sp.y, 9.0)
	fx.explosion(p, 1.8, true)
	marks.crater(sp.x, sp.y, 13.0, 0.9)
	marks.blast(p, 9.0, 1.3)
	_shake(p, 1.0)
	print("[battle] boom di prova in (%.0f, %.0f) t=%.1f" % [p.x, p.z, _wall_time])

## Testo delle condizioni per l'HUD: "pomeriggio · pioggia".
func _conditions_text() -> String:
	var t := String(MOOD_NAMES.get(mood, mood))
	if weather != null and weather.kind != "sereno" and weather.kind != "notte":
		t += " · " + weather.describe()
	elif sim.tkey == "foresta" and (weather == null or weather.kind == "sereno"):
		t += ", foschia"
	return t

# ---------------------------------------------------------------------------- Fase 8: modalità foto (F10)
## Pausa la battaglia, nasconde l'interfaccia e libera la telecamera (WASD + mouse, Q/E quota, rotella = zoom ottico).
## Invio/F12 o il pulsante «Scatta» salvano un PNG in user://screenshots. Esc esce. Mai attivata dai test (solo input).
func toggle_photo() -> void:
	set_photo(not photo)

func set_photo(on: bool) -> void:
	if on == photo or sim == null:
		return
	photo = on
	if on:
		if intro_t >= 0:
			end_intro()
		_photo_was_paused = sim.paused
		sim.paused = true
		mode = ""
		drag_active = false
		cam.set_photo(true)
		hud.set_photo(true)
		if _photo_attr == null:
			_photo_attr = CameraAttributesPractical.new()
			_photo_attr.dof_blur_far_enabled = false
			_photo_attr.dof_blur_near_enabled = false
		cam.attributes = _photo_attr
		photo_dof(_photo_dof)
	else:
		cam.set_photo(false)
		cam.attributes = null
		_update_tilt()
		hud.set_photo(false)
		if not deploying:
			sim.paused = _photo_was_paused
	if audio != null and audio.has_method("set_photo"):
		audio.set_photo(on)

## Tab: dalla vista tattica a quella strategica (in alto sopra il punto sotto il cursore) e ritorno alla distanza tattica di prima.
func toggle_strategic() -> void:
	var mp := get_viewport().get_mouse_position()
	var g := terrain.raycast(cam.project_ray_origin(mp), cam.project_ray_normal(mp))
	if cam._t_dist < BattleStrategic.K_START:
		_tac_dist = cam._t_dist
		cam.go_to(g if g.x != INF else cam._t_target, maxf(BattleStrategic.K_FULL + 80.0, cam.max_dist * 0.75))
	else:
		cam.go_to(g if g.x != INF else cam._t_target, clampf(_tac_dist, 60.0, BattleStrategic.K_START - 40.0))

## Tilt-shift della vista di gioco: a fuoco il punto osservato, sfocati il fondo e (da camera alta) il primo piano.
## L'intensità cresce con la distanza della telecamera: da vicino è quasi nulla, dalla vista alta dà l'effetto plastico.
func _update_tilt() -> void:
	if photo or cam == null:
		return
	var k := _tilt_k * smoothstep(45.0, 320.0, cam.dist)
	if k <= 0.01:
		if cam.attributes != null:
			cam.attributes = null
		return
	if _tilt_attr == null:
		_tilt_attr = CameraAttributesPractical.new()
	if cam.attributes != _tilt_attr:
		cam.attributes = _tilt_attr
	var d := cam.dist
	_tilt_attr.dof_blur_far_enabled = true
	_tilt_attr.dof_blur_far_distance = d * 1.18 + 10.0
	_tilt_attr.dof_blur_far_transition = d * 0.9 + 20.0
	# primo piano sfocato solo da camera alta (inquadratura inclinata): da vicino resterebbe sfocata l'unità sotto il cursore
	var nk := smoothstep(110.0, 400.0, d)
	_tilt_attr.dof_blur_near_enabled = nk > 0.05
	_tilt_attr.dof_blur_near_distance = d * lerpf(0.5, 0.72, nk)
	_tilt_attr.dof_blur_near_transition = d * 0.3
	_tilt_attr.dof_blur_amount = 0.03 + 0.07 * k

## Profondità di campo (0 = spenta .. 1 = forte), a fuoco sul terreno al centro dello schermo.
func photo_dof(v: float) -> void:
	_photo_dof = clampf(v, 0.0, 1.0)
	if _photo_attr == null:
		return
	var on := _photo_dof > 0.02
	_photo_attr.dof_blur_far_enabled = on
	_photo_attr.dof_blur_near_enabled = on
	_photo_attr.dof_blur_amount = 0.02 + 0.14 * _photo_dof
	var sz := get_viewport().get_visible_rect().size
	var g := terrain.raycast(cam.project_ray_origin(sz * 0.5), cam.project_ray_normal(sz * 0.5))
	var d := cam.global_position.distance_to(g) if g.x != INF else 60.0
	_photo_attr.dof_blur_far_distance = d + 8.0 + d * 0.25
	_photo_attr.dof_blur_far_transition = 20.0 + d * 0.6
	_photo_attr.dof_blur_near_distance = maxf(1.0, d * 0.45)
	_photo_attr.dof_blur_near_transition = maxf(1.0, d * 0.3)

## Scatta: nasconde il pannello, attende il frame disegnato e salva user://screenshots/foto_<data>.png.
func photo_shoot() -> void:
	if not photo or _photo_shot_pending:
		return
	_photo_shot_pending = true
	hud.set_photo_panel_visible(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
	var name := "foto_%s.png" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("T", "_").replace(" ", "_")
	var path := "user://screenshots/" + name
	var err := img.save_png(path)
	_photo_shot_pending = false
	if photo:
		hud.set_photo_panel_visible(true)
		hud.flash_photo()
	if err == OK:
		toast("Foto salvata: " + ProjectSettings.globalize_path(path), Color(0.8, 1.0, 0.8))
	else:
		toast("Impossibile salvare la foto (errore %d)" % err, Color(1.0, 0.5, 0.4))
	_sfx("click", 0)

func _exit_tree() -> void:
	if sim != null:
		sim.dispose()
	if _msaa_set and is_inside_tree():
		get_viewport().msaa_3d = _old_msaa

# ---------------------------------------------------------------------------- indicatori a terra
## Indicatore d'ordine animato (kind: move, amove, attack, deploy, barrage); u = bersaglio da seguire.
func _mark(sim_x: float, sim_y: float, kind: String, r: float, u = null) -> void:
	var w := BattleTerrain.sim_to_world(sim_x, sim_y)
	var gy := terrain.height(w.x, w.y)
	if sim.sea:
		gy = maxf(gy, 0.0)
	orders.spawn(Vector3(w.x, gy, w.y), kind, r, u, 1.3 if kind == "barrage" else BattleOrderMarks.DUR)
	if kind != "barrage" and kind != "deploy":
		_last_order_t = _wall_time

func _marker(sim_x: float, sim_y: float, col: Color, r: float, dur: float) -> void:
	var w := BattleTerrain.sim_to_world(sim_x, sim_y)
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.render_priority = 3
	mi.material_override = m
	mi.position = Vector3(w.x, terrain.height(w.x, w.y) + 0.3, w.y)
	add_child(mi)
	_markers.append({"n": mi, "m": m, "t": dur, "T": dur, "r": r, "c": col})

func _update_markers(dt: float) -> void:
	var i := 0
	while i < _markers.size():
		var k: Dictionary = _markers[i]
		k["t"] -= dt
		if k["t"] <= 0:
			k["n"].queue_free()
			_markers.remove_at(i)
			continue
		var f: float = k["t"] / k["T"]
		var r: float = k["r"] * (0.6 + 0.4 * (1.0 - f)) if k["r"] < 10 else k["r"]
		k["n"].scale = Vector3(r, 1.0, r)
		var c: Color = k["c"]
		k["m"].albedo_color = Color(c.r, c.g, c.b, c.a * f)
		i += 1

func _update_cursor() -> void:
	if mode == "" or sim.hs < 0:
		_cursor_ring.visible = false
		return
	var g := _ground_at(get_viewport().get_mouse_position())
	if g.x == INF:
		_cursor_ring.visible = false
		return
	_cursor_ring.visible = true
	_cursor_ring.position = g + Vector3(0, 0.4, 0)
	var r := BattleSim.BARRAGE_R * S if mode == "barrage" else (BattleSim.AIR_R * S if mode == "air" else (AREA_R if mode == "area" else 2.5))
	_cursor_ring.scale = Vector3(r, 1, r)
	var cc := Color(1.0, 0.7, 0.3, 0.9)
	if mode == "barrage":
		cc = Color(1.0, 0.3, 0.25, 0.8)
	elif mode == "air":
		cc = Color(1.0, 0.85, 0.3, 0.85)
	elif mode == "area":
		cc = Color(1.0, 0.5, 0.25, 0.85)
	_cursor_ring.material_override = _ring_mat("cur_" + mode, cc)

# ---------------------------------------------------------------------------- input
func _ground_at(sp: Vector2) -> Vector3:
	return terrain.raycast(cam.project_ray_origin(sp), cam.project_ray_normal(sp))

func _pick(sp: Vector2, side: int):
	var best = null
	var bd := 1e9
	for e in screen_list:
		var u = e[0]
		if u.dead or (side >= 0 and u.side != side):
			continue
		var d: float = (e[1] as Vector2).distance_to(sp)
		var lim: float = maxf(14.0, e[2] * 1.15)
		if d < lim and d < bd:
			bd = d; best = u
	return best

func _on_button(id: String) -> void:
	_sfx("click", 0)
	if intro_t >= 0:
		end_intro()
	match id:
		"pause":
			if not deploying:
				sim.toggle_pause()
		"auto":
			if deploying:
				end_deploy()
			sim.auto_resolve()
		"retreat":
			if deploying:
				end_deploy()
			sim.retreat()
		"all":
			sim.select_all(); _sfx("select", 0.05)
		"amove":
			if sim.hs >= 0 and not sim.sel_alive().is_empty() and not deploying:
				mode = "" if mode == "amove" else "amove"
		"stop":
			if sim.hs >= 0 and not deploying:
				sim.stop(); mode = ""
		"start": end_deploy()
		"continue": continue_now()
		"alert": jump_to_alert()
		"home": frame_army(cam._t_dist)
		"barrage":
			if sim.hs >= 0 and float(sim.sides[sim.hs]["barrage_cd"]) <= 0 and not deploying:
				mode = "" if mode == "barrage" else "barrage"
		"air":
			if sim.hs >= 0 and int(sim.sides[sim.hs]["air_uses"]) > 0 and not deploying:
				mode = "" if mode == "air" else "air"
		"area":
			if sim.hs >= 0 and not deploying and sim.ending == null and sel_has_art():
				mode = "" if mode == "area" else "area"
		"smoke":
			if sim.hs >= 0 and not deploying and sim.ending == null:
				if sim.human_smoke():
					_last_order_t = _wall_time
		"hold":
			if sim.hs >= 0 and not deploying and sim.ending == null and not sim.sel_alive().is_empty():
				sim.hold_position()
				mode = ""
				_sfx("order", 0.05)
		"focus":
			_focus_selection()
		"photo":
			toggle_photo()
		"photo_shot":
			photo_shoot()
		"photo_exit":
			set_photo(false)

## Tab va intercettato prima dell'interfaccia (altrimenti sposta il fuoco tra i pulsanti).
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and sim != null and not photo:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		if code == KEY_TAB and not ev.ctrl_pressed and not ev.alt_pressed:
			toggle_strategic()
			get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if sim == null or sim.done:
		return
	if photo:
		# modalità foto: Esc esce, Invio/F12 scatta; il resto va alla telecamera libera
		if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
			var pk := (ev as InputEventKey).physical_keycode if (ev as InputEventKey).physical_keycode != 0 else (ev as InputEventKey).keycode
			if pk == KEY_ESCAPE or pk == KEY_F10:
				set_photo(false)
				get_viewport().set_input_as_handled()
			elif pk in [KEY_ENTER, KEY_KP_ENTER, KEY_F12]:
				photo_shoot()
				get_viewport().set_input_as_handled()
			elif pk == KEY_H:
				hud.toggle_photo_panel()
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var pk0 := (ev as InputEventKey).physical_keycode if (ev as InputEventKey).physical_keycode != 0 else (ev as InputEventKey).keycode
		if pk0 == KEY_F10 and not (_demo and _shot_arg("input", "0") != "1"):
			toggle_photo()
			get_viewport().set_input_as_handled()
			return
	if intro_t >= 0:
		var skip := false
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			skip = true
		elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
			var kc := (ev as InputEventKey).keycode
			skip = kc in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]
		if skip:
			end_intro()
			get_viewport().set_input_as_handled()
		return
	if _demo and _shot_arg("input", "0") != "1":
		return
	if ev is InputEventMouseMotion:
		var mp: Vector2 = ev.position
		_mouse = mp
		if drag_active:
			drag_to = mp
		if sim.hs >= 0:
			_hover_enemy = _pick(mp, 1 - sim.hs)
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var human := sim.hs >= 0 and sim.ending == null
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not human:
				return
			if mb.pressed:
				if mb.double_click:
					var u = _pick(mb.position, sim.hs)
					if u != null and not u.stat:
						sim.select_type(u.type)
						_sfx("select", 0.05)
					drag_active = false
					return
				if mode == "amove":
					_order_at(mb.position, true)
					if not mb.shift_pressed:
						mode = ""
					return
				if mode == "air":
					var ga := _ground_at(mb.position)
					if ga.x != INF:
						var sa := BattleTerrain.world_to_sim(ga.x, ga.z)
						if sim.human_air_strike(sa.x, sa.y):
							_mark(sa.x, sa.y, "barrage", BattleSim.AIR_R * S)
					mode = ""
					return
				if mode == "area":
					var ga2 := _ground_at(mb.position)
					if ga2.x != INF and sim.has_method("order_fire_area"):
						var s2 := BattleTerrain.world_to_sim(ga2.x, ga2.z)
						sim.call("order_fire_area", s2.x, s2.y)
						_mark(s2.x, s2.y, "barrage", AREA_R)
						_sfx("order", 0.05)
					if not mb.shift_pressed:
						mode = ""
					return
				if mode == "barrage":
					var g := _ground_at(mb.position)
					if g.x != INF:
						var s := BattleTerrain.world_to_sim(g.x, g.z)
						if sim.human_barrage(s.x, s.y):
							_mark(s.x, s.y, "barrage", BattleSim.BARRAGE_R * S)
							_sfx("alert", 0.5)
					mode = ""
					return
				drag_active = true
				drag_from = mb.position
				drag_to = mb.position
				_drag_shift = mb.shift_pressed
			else:
				if not drag_active:
					return
				drag_active = false
				var add := mb.shift_pressed or _drag_shift
				if drag_from.distance_to(mb.position) > 6.0:
					var r := Rect2(drag_from, mb.position - drag_from).abs()
					var list := []
					for e in screen_list:
						var u = e[0]
						if u.side == sim.hs and not u.stat and not u.dead and r.grow(e[2] * 0.5).has_point(e[1]):
							list.append(u)
					if add:
						sim.select_units(list, true)
					else:
						sim.set_selection([], false)
						sim.select_units(list, false)
					if not list.is_empty():
						_sfx("select", 0.05)
				else:
					var u = _pick(mb.position, sim.hs)
					if u != null and not u.stat:
						if add:
							sim.toggle_unit(u)
						else:
							sim.set_selection([], false)
							sim.select_units([u], false)
						_sfx("select", 0.05)
					elif not add:
						sim.set_selection([], false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not human:
				return
			if mode != "":
				mode = ""
				return
			if deploying:
				var g := _ground_at(mb.position)
				if g.x != INF and not sim.sel_alive().is_empty():
					var sp := BattleTerrain.world_to_sim(g.x, g.z)
					sim.deploy_place(sim.sel_alive(), sp.x, sp.y)
					_mark(sp.x, sp.y, "deploy", 3.0)
					_sfx("order", 0.05)
				return
			_order_at(mb.position, false)
		return
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.echo or not k.pressed:
			return
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		var human := sim.hs >= 0 and sim.ending == null
		# WASD/Q/E sono sempre della telecamera; comandi delle unità su tasti dedicati
		match code:
			KEY_P, KEY_SPACE:
				if deploying:
					end_deploy()
				else:
					sim.toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if deploying:
					end_deploy()
				elif sim.done or sim.ending != null:
					continue_now()
			KEY_ESCAPE:
				if mode != "":
					mode = ""
				elif human:
					sim.set_selection([], false)
				get_viewport().set_input_as_handled()
			KEY_A:
				if human and k.ctrl_pressed:
					sim.select_all(); _sfx("select", 0.05)
			KEY_G:
				_on_button("amove")
			KEY_H:
				_on_button("stop")
			KEY_B:
				if human:
					_on_button("barrage")
			KEY_F:
				if human:
					_on_button("smoke")
			KEY_J:
				if human:
					_on_button("air")
			KEY_T:
				if human:
					_on_button("hold")
			KEY_C:
				_focus_selection()
			KEY_X:
				if human:
					_on_button("area")
			KEY_V:
				jump_to_alert()
			KEY_HOME, KEY_BACKSPACE:
				frame_army(cam._t_dist)
			_:
				if code >= KEY_1 and code <= KEY_9 and human:
					var g := int(code - KEY_0)
					if k.ctrl_pressed:
						sim.store_group(g)
						_sfx("click", 0)
					else:
						sim.recall_group(g)
						var now := _wall_time
						if now - float(_last_group_tap.get(g, -10.0)) < 0.4:
							_focus_selection()
						_last_group_tap[g] = now

func _focus_selection() -> void:
	var list := sim.sel_alive()
	if list.is_empty():
		return
	var c := Vector2.ZERO
	for u in list:
		c += Vector2(u.x, u.y)
	c /= list.size()
	var w := BattleTerrain.sim_to_world(c.x, c.y)
	cam.go_to(Vector3(w.x, 0, w.y))

func _order_at(sp: Vector2, amove: bool) -> void:
	if sim.sel_alive().is_empty():
		return
	var enemy = _pick(sp, 1 - sim.hs)
	if enemy != null:
		if amove:
			sim.order_attack_move(enemy.x, enemy.y, enemy)
		else:
			sim.order_attack(enemy)
		_mark(enemy.x, enemy.y, "attack", enemy.r * S * 1.25, enemy)
		_sfx("order", 0.05)
		return
	var g := _ground_at(sp)
	if g.x == INF:
		return
	var s := BattleTerrain.world_to_sim(g.x, g.z)
	if amove:
		sim.order_attack_move(s.x, s.y)
		_mark(s.x, s.y, "amove", 3.0)
	else:
		sim.order_move(s.x, s.y)
		_mark(s.x, s.y, "move", 3.0)
	_sfx("order", 0.05)

# ============================================================================ fase 5: battaglia tattica
const AREA_R := 22.0           # raggio indicativo (m) del fuoco d'area dell'artiglieria
const FLANK_TXT := {"side": "FIANCO", "rear": "RETRO"}
var _ring_n := 0

## Vero se l'unità è visibile al giocatore (proprie sempre; nemici solo se avvistati; spettatore: tutto).
func is_visible_unit(u) -> bool:
	if not _tactical or sim.hs < 0 or u.side == sim.hs:
		return true
	return bool(sim.call("visible_to", sim.hs, u))

func sel_has_art() -> bool:
	for u in sim.sel_alive():
		if u.type == "art":
			return true
	return false

func _unit_by_id(id: int):
	if views.has(id):
		return views[id]["u"]
	return null

func _ev_world(e: Dictionary, u) -> Vector3:
	if u != null and views.has(u.id) and not u.dead and not e.has("x"):
		return (views[u.id]["pos"] as Vector3) + Vector3(0, 2.0, 0)
	var w := BattleTerrain.sim_to_world(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	return Vector3(w.x, maxf(terrain.height(w.x, w.y), 0.0) + 2.0, w.y)

## Scritta fluttuante sopra un punto (FIANCO, RETRO, IMBOSCATA!, AVVISTATO).
func float_text(p: Vector3, text: String, col: Color, big := false, dur := 1.6) -> void:
	if floaters.size() > 24:
		floaters.pop_front()
	floaters.append({"p": p, "text": text, "col": col, "t": 0.0, "T": dur, "big": big})

## Riga nel registro della battaglia (sotto la barra in alto).
func toast(text: String, col := Color(1.0, 0.85, 0.5)) -> void:
	for t in toasts:
		if t["text"] == text:
			t["t"] = 0.0
			return
	toasts.append({"text": text, "col": col, "t": 0.0})
	if toasts.size() > 4:
		toasts.pop_front()

func _uname(u) -> String:
	if u == null:
		return "Unità"
	if u.type == "bunker":
		return "Bunker"
	return String(Data.UNITS[u.type]["name"]) if Data.UNITS.has(u.type) else String(u.type)

func _on_fire_tactical(e: Dictionary) -> void:
	if not e.has("flank") or sim.hs < 0:
		return
	var t = e.get("t")
	var u = e.get("u")
	if t == null or u == null:
		return
	var fl := String(e.get("flank", ""))
	var cov := int(e.get("cover", 0))
	var mine: bool = u.side == sim.hs
	if not mine and t.side != sim.hs:
		return
	var key: int = t.id
	var last := float(_float_t.get(key, -10.0))
	if _wall_time - last < 0.9:
		return
	var p := _target_point(t) + Vector3(0, 2.5, 0)
	if FLANK_TXT.has(fl):
		_float_t[key] = _wall_time
		var col := Color(1.0, 0.86, 0.3) if mine else Color(1.0, 0.42, 0.32)
		if fl == "rear":
			col = Color(1.0, 0.62, 0.2) if mine else Color(1.0, 0.3, 0.25)
		float_text(p, FLANK_TXT[fl], col, fl == "rear", 1.4)
	elif cov >= 2 and mine and _wall_time - last > 2.5:
		_float_t[key] = _wall_time
		float_text(p, "AL RIPARO", Color(0.75, 0.78, 0.8), false, 1.2)

func _on_spotted(e: Dictionary) -> void:
	if sim.hs < 0:
		return
	var side := int(e.get("side", -1))
	if side == sim.hs:
		return
	var u = e.get("u")
	if u == null:
		u = _unit_by_id(int(e.get("id", -1)))
	var p := _ev_world(e, u)
	pings.append({"p": p, "t": 0.0, "col": Color(1.0, 0.35, 0.28)})
	if pings.size() > 30:
		pings.pop_front()
	if _spot_n < 3.0:
		_spot_n += 1.0
		float_text(p + Vector3(0, 2.0, 0), "AVVISTATO", Color(1.0, 0.9, 0.45), false, 1.5)
	if bool(e.get("first", false)):
		_sfx("select", 0.8)

func _on_ambush(e: Dictionary) -> void:
	var u = e.get("u")
	if u == null:
		u = _unit_by_id(int(e.get("id", -1)))
	var side := int(e.get("side", u.side if u != null else -1))
	var p := _ev_world(e, u)
	var mine := sim.hs >= 0 and side == sim.hs
	float_text(p + Vector3(0, 3.0, 0), "IMBOSCATA!", Color(1.0, 0.55, 0.15) if mine or sim.hs < 0 else Color(1.0, 0.25, 0.2), true, 2.4)
	pings.append({"p": p, "t": 0.0, "col": Color(1.0, 0.6, 0.15)})
	var nm := _uname(u).to_lower()
	if sim.hs < 0:
		toast("Imboscata: fuoco da posizione nascosta (%s)" % nm, Color(1.0, 0.75, 0.4))
	elif mine:
		toast("Imboscata riuscita! Fuoco da posizione nascosta (%s): danni ×2 per 4 s" % nm, Color(1.0, 0.8, 0.35))
	else:
		toast("IMBOSCATA NEMICA! Fuoco da posizione nascosta sulle tue unità (%s)" % nm, Color(1.0, 0.45, 0.35))
		alerts.append({"p": p, "t": 4.0})
	_sfx("alert", 1.5)

## Scritte, avvistamenti, registro, suggerimento sotto il cursore, anelli di gittata e nebbia tattica.
func _update_tactical(delta: float) -> void:
	var dt := minf(delta, 0.1)
	_spot_n = maxf(0.0, _spot_n - dt * 2.0)
	var i := 0
	while i < floaters.size():
		floaters[i]["t"] = float(floaters[i]["t"]) + dt
		if float(floaters[i]["t"]) >= float(floaters[i]["T"]):
			floaters.remove_at(i)
			continue
		i += 1
	i = 0
	while i < pings.size():
		pings[i]["t"] = float(pings[i]["t"]) + dt
		if float(pings[i]["t"]) > 3.0:
			pings.remove_at(i)
			continue
		i += 1
	i = 0
	while i < toasts.size():
		toasts[i]["t"] = float(toasts[i]["t"]) + dt
		if float(toasts[i]["t"]) > 6.0:
			toasts.remove_at(i)
			continue
		i += 1
	_hover_t -= delta
	if _hover_t <= 0.0:
		_hover_t = 0.12
		_update_hover()
	_update_rings()
	_fog_t -= delta
	if _fog_t <= 0.0 and fog_vp != null:
		_fog_t = 0.2
		fog_draw.queue_redraw()
		fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

const COVER_TXT := ["Terreno scoperto", "Copertura leggera (bosco, terreno accidentato)", "Copertura pesante (città, bunker)"]

## Fianco del bersaglio esposto a un tiratore in (sx, sy): "front" | "side" | "rear".
func flank_from(t, sx: float, sy: float) -> String:
	var R = BattleProps.ext("BattleRules")
	if R != null:
		var f: Array = R.flank(t.type, t.ang, sx - t.x, sy - t.y)
		_flank_mul = float(f[0])
		return String(f[1]) if String(f[1]) != "" else "front"
	var a := atan2(sy - t.y, sx - t.x)
	var d := absf(wrapf(a - t.ang, -PI, PI))
	_flank_mul = 1.0
	if d <= deg_to_rad(45.0):
		return "front"
	if d >= deg_to_rad(135.0):
		return "rear"
	_flank_mul = 1.6 if t.type == "tank" else 1.25
	return "side"
var _flank_mul := 1.0

func _update_hover() -> void:
	hover_info = ""
	if sim.hs < 0 or intro_t >= 0 or sim.done:
		return
	if _demo:
		# demo: --hover=x,y (coordinate dello schermo) simula il cursore
		var hv := _shot_arg("hover", "")
		if hv == "":
			return
		var pp := hv.split(",")
		_mouse = Vector2(float(pp[0]), float(pp[1]))
		_hover_enemy = _pick(_mouse, 1 - sim.hs)
	var sel := sim.sel_alive()
	if _hover_enemy != null and (_hover_enemy.dead or not is_visible_unit(_hover_enemy)):
		_hover_enemy = null
	if _hover_enemy != null:
		var t = _hover_enemy
		var line := ("%s nemica" if t.type == "inf" else "%s nemici") % _uname(t)
		if t.type == "bunker":
			line = "Bunker nemico"
		var cv = t.get("cover")
		if cv != null and int(cv) > 0:
			line += " · " + ("al riparo leggero" if int(cv) == 1 else "al riparo pesante")
		var veh: bool = t.type in ["tank", "art", "aa"]
		if veh and not sel.is_empty():
			var c := Vector2.ZERO
			var n := 0
			for u in sel:
				if u.type == "tank" or u.type == "inf" or u.type == "aa":
					c += Vector2(u.x, u.y); n += 1
			if n > 0:
				c /= n
				var fl := flank_from(t, c.x, c.y)
				var heavy: bool = t.type == "tank"
				var mul: float = _flank_mul if fl != "rear" or _flank_mul > 1.0 else (2.5 if heavy else 1.5)
				var nm: String = {"front": "FRONTE", "side": "FIANCO", "rear": "RETRO"}[fl]
				line += "\nI tuoi lo colpirebbero sul %s (danni ×%s)" % [nm, String.num(mul, 2).replace(".", ",")]
				if fl == "front" and heavy:
					line += " · aggiralo per colpire il fianco"
		hover_info = line
		return
	if not sim.has_method("cover_at"):
		return
	if sel.is_empty() and mode == "":
		return
	var g := _ground_at(_mouse)
	if g.x == INF:
		return
	var sp := BattleTerrain.world_to_sim(g.x, g.z)
	if sp.x < 0 or sp.y < 0 or sp.x > float(sim.W) or sp.y > float(sim.H):
		return
	var cv := clampi(int(sim.call("cover_at", sp.x, sp.y)), 0, 2)
	hover_info = COVER_TXT[cv]
	if cv > 0 and not sel.is_empty():
		for u in sel:
			if u.type == "inf":
				hover_info += "\nLa fanteria qui resta nascosta finché non spara"
				break

## Anelli di gittata (pieno), vista (tratteggio) e gittata minima (rosso) delle unità selezionate, disegnati dal terreno.
func _update_rings() -> void:
	var mat: ShaderMaterial = terrain.terrain_mat
	var list := PackedVector4Array()
	if sim.hs >= 0 and intro_t < 0 and not sim.done and (_demo == false or _shot_arg("rings", "1") != "0"):
		var sel := sim.sel_alive()
		# gittata minima solo se la selezione è (quasi) tutta artiglieria: altrimenti i cerchi rossi coprono il campo
		var n_art := 0
		for u in sel:
			if u.type == "art":
				n_art += 1
		var min_ok := n_art * 2 >= sel.size()
		for kind in [0, 2, 1]:
			for u in sel:
				if list.size() >= 48:
					break
				if kind == 2 and not min_ok:
					continue
				var r := 0.0
				match kind:
					0: r = u.range_ * S
					1:
						var vw = u.get("view")
						r = float(vw) * S if vw != null else 0.0
					2: r = u.min_range * S
				if r <= 1.0:
					continue
				var w := BattleTerrain.sim_to_world(u.x, u.y)
				var dup := false
				for q in list:
					if int(q.w) == kind and absf(q.z - r) < r * 0.1 and Vector2(q.x, q.y).distance_to(w) < r * 0.15:
						dup = true
						break
				if not dup:
					list.append(Vector4(w.x, w.y, r, kind))
	var n := list.size()
	if photo:
		n = 0
		list.clear()
	if n == 0 and _ring_n == 0:
		return
	_ring_n = n
	while list.size() < 48:
		list.append(Vector4(0, 0, 0, 0))
	mat.set_shader_parameter("rings", list)
	mat.set_shader_parameter("ring_n", n)
	if n > 0:
		mat.set_shader_parameter("ring_col", side_color(sim.hs).lightened(0.35))

# ---------------------------------------------------------------------------- nebbia tattica (minimappa e terreno)
## Disegna i cerchi di vista delle proprie unità in una piccola texture (bianco = in vista, grigio = non osservato).
class FogDraw extends Control:
	var b
	var tex: Texture2D
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.5, 0.5))
		var sim = b.sim
		if sim == null or sim.hs < 0:
			return
		var k: float = size.x / float(sim.W)
		for u in sim.units:
			if u.dead or u.side != sim.hs:
				continue
			var vr = u.get("view")
			if vr == null:
				continue
			var r: float = float(vr) * k * 1.06
			draw_texture_rect(tex, Rect2(Vector2(u.x, u.y) * k - Vector2(r, r), Vector2(r, r) * 2.0), false)

func _setup_fog() -> void:
	if not _tactical or sim.hs < 0:
		return
	if _demo and _shot_arg("fog", "1") == "0":
		return
	fog_vp = SubViewport.new()
	fog_vp.name = "FogMap"
	fog_vp.disable_3d = true
	fog_vp.transparent_bg = false
	fog_vp.size = Vector2i(256, maxi(16, int(256.0 * float(sim.H) / float(sim.W))))
	fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(fog_vp)
	fog_draw = FogDraw.new()
	fog_draw.b = self
	fog_draw.size = Vector2(fog_vp.size)
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.7, Color(1, 1, 1, 1))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	fog_draw.tex = g
	fog_vp.add_child(fog_draw)
	terrain.terrain_mat.set_shader_parameter("fog_tex", fog_vp.get_texture())
	terrain.terrain_mat.set_shader_parameter("fog_on", 1.0)

func fog_texture() -> Texture2D:
	return fog_vp.get_texture() if fog_vp != null else null

## Mina esplosa sotto un mezzo dell'attaccante.
func _on_mine(e: Dictionary, silent: bool) -> void:
	terrain.paint_crater(float(e["x"]), float(e["y"]), 9.0)
	if silent:
		return
	var w := BattleTerrain.sim_to_world(float(e["x"]), float(e["y"]))
	var p := Vector3(w.x, maxf(terrain.height(w.x, w.y), 0.0), w.y)
	fx.explosion(p, 1.2, true)
	_danger.append([p, _wall_time])
	_shake(p, 0.7)
	if audio != null:
		audio.play_at("hit_armor", p, "expl")
	var u = _unit_by_id(int(e.get("id", -1)))
	if u != null and is_visible_unit(u):
		float_text(p + Vector3(0, 4.0, 0), "MINA!", Color(1.0, 0.4, 0.25), true, 1.8)
	if sim.hs == 0:
		toast("Campo minato! Un tuo mezzo è saltato su una mina: aggira l'area segnalata", Color(1.0, 0.5, 0.35))
	elif sim.hs == 1:
		toast("Le tue mine hanno colpito un mezzo nemico", Color(0.75, 1.0, 0.6))
