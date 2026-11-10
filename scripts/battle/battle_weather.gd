class_name BattleWeather
extends Node3D
## Fase 8 — meteo e ora della battaglia (vista). Legge `sim.weather` (pioggia, temporale, nebbia, neve, notte, sereno) e
## modula con dissolvenza l'ambiente costruito da Battle3D._build_env (cielo, foschia, sole, saturazione), gestisce
## precipitazioni (GPUParticles che seguono la telecamera), fulmini e tuoni, razzi illuminanti (luce con ombre in
## movimento), bagnato e neve che si accumulano sul terreno (parametri dello shader del suolo) e il vento degli effetti.
## Niente logica di gioco: la vista della sim è ridotta da `sim.weather_view_mul` (BattleRules.WEATHER_VIEW).

## modificatori per condizione rispetto all'ambiente di base: fog = densità ×, sun = energia del sole ×, amb = ambiente ×,
## sat = saturazione ×, rain/snow = intensità delle precipitazioni, w = peso dei colori di cielo/foschia (skyc/fogc),
## hold = quanto la foschia resta anche nella vista d'insieme (0 = si dirada con la distanza come oggi), hfog = foschia radente
const MOD := {
	"sereno":    {"fog": 1.0, "sun": 1.0, "amb": 1.0, "sat": 1.0, "rain": 0.0, "snow": 0.0, "w": 0.0, "hold": 0.0, "hfog": 0.0,
		"skyc": Color(0.6, 0.66, 0.74), "fogc": Color(0.68, 0.74, 0.8), "wind": Vector3(1.2, 0, 0.4)},
	"pioggia":   {"fog": 2.3, "sun": 0.4, "amb": 0.82, "sat": 0.9, "rain": 0.7, "snow": 0.0, "w": 0.85, "hold": 0.35, "hfog": 0.0006,
		"skyc": Color(0.4, 0.43, 0.47), "fogc": Color(0.55, 0.58, 0.62), "wind": Vector3(3.0, 0, 1.0)},
	"temporale": {"fog": 3.0, "sun": 0.26, "amb": 0.66, "sat": 0.84, "rain": 1.0, "snow": 0.0, "w": 0.95, "hold": 0.45, "hfog": 0.0008,
		"skyc": Color(0.26, 0.28, 0.32), "fogc": Color(0.4, 0.42, 0.46), "wind": Vector3(6.0, 0, 2.2)},
	"nebbia":    {"fog": 6.5, "sun": 0.62, "amb": 1.12, "sat": 0.86, "rain": 0.0, "snow": 0.0, "w": 0.92, "hold": 0.8, "hfog": 0.0035,
		"skyc": Color(0.74, 0.77, 0.8), "fogc": Color(0.8, 0.82, 0.84), "wind": Vector3(0.3, 0, 0.1)},
	"neve":      {"fog": 1.15, "sun": 0.6, "amb": 1.0, "sat": 0.84, "rain": 0.0, "snow": 1.0, "w": 0.75, "hold": 0.3, "hfog": 0.0004,
		"skyc": Color(0.6, 0.64, 0.7), "fogc": Color(0.8, 0.83, 0.88), "wind": Vector3(2.6, 0, 0.8)},
	"notte":     {"fog": 1.3, "sun": 1.0, "amb": 1.0, "sat": 0.9, "rain": 0.0, "snow": 0.0, "w": 0.0, "hold": 0.2, "hfog": 0.0,
		"skyc": Color(0.05, 0.07, 0.12), "fogc": Color(0.05, 0.06, 0.1), "wind": Vector3(0.8, 0, 0.3)},
}
const NAMES := {"sereno": "sereno", "pioggia": "pioggia", "temporale": "temporale", "nebbia": "nebbia fitta", "neve": "nevicata", "notte": "notte"}
## annunci al cambio (toast)
const CHANGE_TXT := {
	"sereno": "Il cielo si apre: la visibilità torna normale",
	"pioggia": "Comincia a piovere: visibilità ridotta, terreno fangoso",
	"temporale": "Temporale: visibilità molto ridotta",
	"nebbia": "Cala la nebbia: si vede solo da vicino, attenzione alle imboscate",
	"neve": "Nevica: visibilità ridotta",
}
const LIFT_TXT := {"nebbia": "La nebbia si dirada", "pioggia": "Smette di piovere", "temporale": "Il temporale si allontana", "neve": "Smette di nevicare"}

var battle                       # Battle3D
var sim
var env: Environment
var sun: DirectionalLight3D
var sky: ProceduralSkyMaterial
var tmat: ShaderMaterial
var fx                           # BattleFx
var base := {}                   # valori dell'ambiente di base (da Battle3D._build_env)
var kind := "sereno"
var night := false
var quality_k := 1.0
# stato dissolto (float e colori)
var cur := {}
var tgt := {}
var _blend := true
var _sky_t := 0.0
var rain := 0.0
var snow := 0.0
var wetness := 0.0
var snow_cover := 0.0
var wind := Vector3(1.2, 0, 0.4)
var lightning := 0.0             # 0..1 lampo in corso
var _light_cd := 0.0
var thunder_queue: Array = []    # [ritardo s, intensità 0..1] per BattleAudio
var flares: Array = []           # {n, light, glow, p, t, T, side, shadow}
var _rain_p: GPUParticles3D
var _snow_p: GPUParticles3D
var _splash_t := 0.0
var _shader_t := 0.0
var _rng := RandomNumberGenerator.new()
var _wet_last := -1.0
var _snow_last := -1.0

func setup(b, e: Environment, s: DirectionalLight3D, sk: ProceduralSkyMaterial, base_vals: Dictionary, terrain_mat: ShaderMaterial, f) -> void:
	battle = b
	sim = b.sim
	env = e
	sun = s
	sky = sk
	tmat = terrain_mat
	fx = f
	base = base_vals
	_rng.seed = int(sim.seed_) * 3 + 11
	night = String(sim.weather) == "notte"
	if b.terrain != null and b.terrain.has_method("set_night"):
		b.terrain.set_night(1.0 if night else 0.0)   # finestre accese, chiazze di luce di lampioni e paesi
	if sim.tkey == "artico":
		snow_cover = 1.0
	set_kind(String(sim.weather), true)

## Cambia condizione: `instant` salta la dissolvenza (avvio).
func set_kind(k: String, instant := false) -> void:
	if not MOD.has(k):
		k = "sereno"
	kind = k
	var m: Dictionary = MOD[k]
	tgt = {"fog": float(m["fog"]), "sun": float(m["sun"]), "amb": float(m["amb"]), "sat": float(m["sat"]), "w": float(m["w"]),
		"hold": float(m["hold"]), "hfog": float(m["hfog"]), "skyc": m["skyc"], "fogc": m["fogc"]}
	if night:
		# di notte l'ambiente di base è già buio: le condizioni aggiungono solo foschia e pioggia
		tgt["w"] = 0.0
		tgt["sun"] = 1.0
		tgt["amb"] = 1.0
	if instant or cur.is_empty():
		cur = tgt.duplicate()
		rain = float(m["rain"])
		snow = float(m["snow"])
		wind = m["wind"]
		if fx != null:
			fx.wind = wind
		_apply_env(true)
	_blend = true
	_ensure_particles()

func describe() -> String:
	var t := String(NAMES.get(kind, kind))
	if night and kind != "notte":
		t = "notte, " + t
	return t

## Testo dell'annuncio al cambio di condizione (vuoto se nulla da dire).
func change_text(old_kind: String, new_kind: String) -> String:
	if new_kind == "sereno" and LIFT_TXT.has(old_kind):
		return String(LIFT_TXT[old_kind]) + ": la visibilità torna normale"
	return String(CHANGE_TXT.get(new_kind, ""))

# ---------------------------------------------------------------------------- ciclo
func update(dt: float, frozen: bool, cam: Camera3D, cam_dist: float) -> void:
	if sim == null:
		return
	var sk := String(sim.weather)
	if sk != kind:
		set_kind(sk)
	var m: Dictionary = MOD[kind]
	# dissolvenze lente (~8 s) dei parametri dell'ambiente
	if _blend:
		var a := 1.0 - exp(-dt / 6.0)
		var done := true
		for key in tgt:
			var v = cur[key]
			var t = tgt[key]
			if v is Color:
				var c: Color = (v as Color).lerp(t, a)
				cur[key] = c
				if absf(c.r - t.r) + absf(c.g - t.g) + absf(c.b - t.b) > 0.004:
					done = false
			else:
				var f := lerpf(float(v), float(t), a)
				cur[key] = f
				if absf(f - float(t)) > 0.003:
					done = false
		_apply_env(false)
		if done:
			cur = tgt.duplicate()
			_apply_env(true)
			_blend = false
	rain = move_toward(rain, float(m["rain"]), dt * 0.08)
	snow = move_toward(snow, float(m["snow"]), dt * 0.08)
	wind = wind.lerp(m["wind"], 1.0 - exp(-dt / 10.0))
	if fx != null:
		fx.wind = wind
	# bagnato: sale in ~25 s di pioggia, asciuga in ~3 minuti; neve: si accumula in ~2 minuti e resta
	if rain > 0.05:
		wetness = minf(1.0, wetness + dt * rain / 25.0)
	else:
		wetness = maxf(0.0, wetness - dt / 180.0)
	if snow > 0.05:
		snow_cover = minf(1.0, snow_cover + dt * snow / 120.0)
	_shader_t -= dt
	if _shader_t <= 0.0 and tmat != null:
		_shader_t = 0.3
		if absf(wetness - _wet_last) > 0.005:
			_wet_last = wetness
			tmat.set_shader_parameter("wetness", wetness)
		if absf(snow_cover - _snow_last) > 0.005:
			_snow_last = snow_cover
			tmat.set_shader_parameter("snow_cover", snow_cover)
	# foschia: più leggera da lontano (leggibilità), ma la nebbia vera resta anche nella vista d'insieme
	var kcam := clampf(110.0 / maxf(cam_dist, 1.0), 0.14, 1.0)
	var hold := float(cur["hold"])
	env.fog_density = float(base["fog_d"]) * lerpf(kcam, 1.0, hold) * float(cur["fog"])
	var hb := float(base.get("fog_hd", 0.0))
	var hf := float(cur["hfog"])
	if hb > 0.0 or hf > 0.0:
		env.fog_height_density = (hb * kcam + hf * lerpf(kcam, 1.0, hold)) * (1.0 - 0.6 * smoothstep(150.0, 400.0, cam_dist))
		env.fog_height = float(base.get("fog_h", 4.0))
	_update_precip(dt, frozen, cam)
	_update_lightning(dt, frozen)
	_update_flares(dt, frozen, cam)

func _apply_env(full: bool) -> void:
	var w := float(cur["w"])
	var skyc: Color = cur["skyc"]
	var fogc: Color = cur["fogc"]
	var fog_col: Color = (base["fog"] as Color).lerp(fogc, w)
	env.fog_light_color = fog_col
	env.ambient_light_energy = float(base["amb"]) * float(cur["amb"])
	env.ambient_light_color = fog_col.lerp(Color(0.62, 0.58, 0.5), 0.4 if not night else 0.1)
	env.adjustment_saturation = float(base["sat"]) * float(cur["sat"])
	sun.light_energy = float(base["sun_e"]) * float(cur["sun"]) * (1.0 + lightning * 5.0)
	sun.light_color = (base["sun_col"] as Color).lerp(Color(0.85, 0.88, 0.95), w * 0.8)
	sun.shadow_opacity = lerpf(float(base.get("shadow_op", 1.0)), 0.45, w)
	sun.light_angular_distance = lerpf(float(base.get("sun_ang", 0.6)), 3.0, w)
	# il cielo rigenera la mappa di radianza: aggiornarlo di rado (ogni 0,35 s durante la dissolvenza)
	_sky_t -= get_process_delta_time()
	if full or _sky_t <= 0.0:
		_sky_t = 0.35
		sky.sky_top_color = (base["sky_top"] as Color).lerp(skyc * 0.85, w)
		sky.sky_horizon_color = (base["sky_hor"] as Color).lerp(skyc, w)
		sky.ground_horizon_color = sky.sky_horizon_color
		sky.ground_bottom_color = sky.sky_horizon_color.darkened(0.5)
		sky.sky_cover_modulate = Color(1, 1, 1, 1.0 - w)
		sky.sun_angle_max = lerpf(float(base.get("sun_amax", 30.0)), 0.0, w)

# ---------------------------------------------------------------------------- precipitazioni
func _ensure_particles() -> void:
	var m: Dictionary = MOD[kind]
	if float(m["rain"]) > 0.0 and _rain_p == null:
		_rain_p = _make_precip(true)
	if float(m["snow"]) > 0.0 and _snow_p == null:
		_snow_p = _make_precip(false)

func _make_precip(is_rain: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain" if is_rain else "Snow"
	p.amount = 3200 if is_rain else 2600
	p.lifetime = 1.4 if is_rain else 9.0
	p.preprocess = p.lifetime
	p.visibility_aabb = AABB(Vector3(-160, -90, -160), Vector3(320, 180, 320))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(120, 2, 120) if is_rain else Vector3(130, 2, 130)
	if is_rain:
		m.direction = Vector3(0.12, -1, 0.05)
		m.spread = 2.0
		m.initial_velocity_min = 26.0
		m.initial_velocity_max = 32.0
		m.gravity = Vector3(0, -4.0, 0)
		m.scale_min = 0.8
		m.scale_max = 1.3
	else:
		m.direction = Vector3(0.3, -1, 0.15)
		m.spread = 12.0
		m.initial_velocity_min = 3.0
		m.initial_velocity_max = 5.0
		m.gravity = Vector3(0, -0.6, 0)
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 0.6
		m.turbulence_noise_scale = 6.0
		m.scale_min = 0.6
		m.scale_max = 1.4
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.75) if is_rain else Vector2(0.24, 0.24)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if is_rain else BaseMaterial3D.BILLBOARD_ENABLED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.8, 0.85, 0.95, 0.42) if is_rain else Color(1, 1, 1, 0.85)
	qm.vertex_color_use_as_albedo = false
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	if is_rain:
		g.fill = GradientTexture2D.FILL_LINEAR
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
	else:
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
	g.width = 32
	g.height = 32
	qm.albedo_texture = g
	q.material = qm
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount_ratio = 0.0
	add_child(p)
	return p

func _update_precip(dt: float, frozen: bool, cam: Camera3D) -> void:
	var ct: Vector3 = battle.cam.target
	var tgt_p: Vector3 = ct + Vector3(0, 48, 0)
	if _rain_p != null:
		var want := rain * quality_k
		_rain_p.amount_ratio = clampf(want, 0.0, 1.0)
		_rain_p.emitting = want > 0.02
		_rain_p.visible = want > 0.02
		_rain_p.global_position = tgt_p + wind * 1.5
		_rain_p.speed_scale = 0.0 if frozen else 1.0
		var pm := _rain_p.process_material as ParticleProcessMaterial
		pm.direction = (Vector3(0, -1, 0) + wind * 0.05).normalized()
	if _snow_p != null:
		var want := snow * quality_k
		_snow_p.amount_ratio = clampf(want, 0.0, 1.0)
		_snow_p.emitting = want > 0.02
		_snow_p.visible = want > 0.02
		_snow_p.global_position = tgt_p + Vector3(0, 7, 0)
		_snow_p.speed_scale = 0.0 if frozen else 1.0
	# schizzi a terra attorno al punto osservato (vicino): piccoli sbuffi chiari
	if rain > 0.1 and not frozen and fx != null and float(battle.cam.dist) < 150.0:
		_splash_t -= dt
		if _splash_t <= 0.0:
			_splash_t = 0.05
			var cd: float = battle.cam.dist
			var n := int(2 + 10 * rain * quality_k * (1.0 - cd / 160.0))
			var c: Vector3 = battle.cam.target
			var R: float = 10.0 + cd * 0.35
			for i in n:
				var a: float = _rng.randf() * TAU
				var r: float = sqrt(_rng.randf()) * R
				var X: float = c.x + cos(a) * r
				var Z: float = c.z + sin(a) * r
				var Y: float = battle.terrain.height(X, Z)
				if sim.sea:
					Y = maxf(Y, 0.0)
				fx.splash_drop(Vector3(X, Y + 0.08, Z))

# ---------------------------------------------------------------------------- fulmini
func _update_lightning(dt: float, frozen: bool) -> void:
	if lightning > 0.0:
		lightning = maxf(0.0, lightning - dt * 7.0)
		sun.light_energy = float(base["sun_e"]) * float(cur["sun"]) * (1.0 + lightning * 5.0)
		env.ambient_light_energy = float(base["amb"]) * float(cur["amb"]) * (1.0 + lightning * 2.5)
		if lightning <= 0.0:
			_apply_env(false)
	if kind != "temporale" or frozen:
		return
	_light_cd -= dt
	if _light_cd <= 0.0:
		_light_cd = 6.0 + _rng.randf() * 12.0
		var strength := 0.5 + _rng.randf() * 0.5
		lightning = strength
		# il tuono arriva dopo 1–5 s (distanza)
		thunder_queue.append([0.8 + _rng.randf() * 4.0, strength])

# ---------------------------------------------------------------------------- razzi illuminanti
## Evento fx della sim: razzo illuminante sopra (x, y) per t secondi. Un solo razzo proietta ombre (il più vicino alla telecamera).
func on_flare(e: Dictionary) -> void:
	var w := BattleTerrain.sim_to_world(float(e["x"]), float(e["y"]))
	var gy: float = battle.terrain.height(w.x, w.y)
	var n := Node3D.new()
	n.name = "Flare"
	add_child(n)
	var L := OmniLight3D.new()
	L.light_color = Color(1.0, 0.9, 0.72)
	L.light_energy = 0.0
	L.omni_range = 190.0
	L.omni_attenuation = 1.3
	L.shadow_enabled = false
	L.shadow_bias = 0.08
	L.shadow_normal_bias = 1.5
	L.light_specular = 0.2
	n.add_child(L)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.0, 3.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.5)
	mat.emission_energy_multiplier = 6.0
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.25, Color(1, 1, 1, 0.6))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 32
	g.height = 32
	mat.albedo_texture = g
	qm.material = mat
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(q)
	var p := Vector3(w.x, gy + 115.0, w.y)
	n.position = p
	flares.append({"n": n, "light": L, "glow": q, "p": p, "t": 0.0, "T": float(e.get("t", 16.0)), "side": int(e.get("side", 0)),
		"ph": _rng.randf() * TAU, "trail": 0.0})
	if flares.size() > 6:
		var old: Dictionary = flares.pop_front()
		(old["n"] as Node3D).queue_free()

func _update_flares(dt: float, frozen: bool, cam: Camera3D) -> void:
	if flares.is_empty():
		return
	var best := -1
	var bd := 1e18
	var i := 0
	while i < flares.size():
		var f: Dictionary = flares[i]
		if not frozen:
			f["t"] = float(f["t"]) + dt
		var t: float = f["t"]
		var T: float = f["T"]
		if t >= T + 1.0:
			(f["n"] as Node3D).queue_free()
			flares.remove_at(i)
			continue
		var n: Node3D = f["n"]
		if not frozen:
			var p: Vector3 = f["p"]
			# salita rapida nel primo secondo, poi discesa lenta col paracadute e deriva col vento
			var rise := 1.0 - minf(t, 1.0)
			p.y += (14.0 * rise - 2.6 * (1.0 - rise)) * dt
			p += wind * dt * 0.6
			var ph: float = f["ph"]
			var sw := Vector3(sin(t * 1.3 + ph), 0, cos(t * 0.9 + ph)) * 0.9 * dt
			p += sw
			f["p"] = p
			n.position = p
			f["trail"] = float(f["trail"]) - dt
			if float(f["trail"]) <= 0.0 and fx != null:
				f["trail"] = 0.12
				fx.trail(p + Vector3(0, 1.0, 0), 0.9, Color(0.7, 0.68, 0.64, 0.4))
		var k := minf(1.0, t / 0.6) * (1.0 - smoothstep(T - 4.0, T + 0.8, t))
		var flick := 0.92 + 0.08 * sin(t * 17.0 + float(f["ph"]) * 3.0)
		var L: OmniLight3D = f["light"]
		L.light_energy = 7.0 * k * flick
		L.omni_range = 190.0 * (0.6 + 0.4 * k)
		(f["glow"] as MeshInstance3D).scale = Vector3.ONE * (0.6 + 1.6 * k)
		(f["glow"] as MeshInstance3D).visible = k > 0.01
		var d := n.position.distance_squared_to(cam.global_position)
		if k > 0.2 and d < bd:
			bd = d; best = i
		i += 1
	# ombre solo dal razzo più vicino (costo), e solo in qualità media/alta
	for j in flares.size():
		var L: OmniLight3D = flares[j]["light"]
		var want := j == best and quality_k > 0.55 and bd < 420.0 * 420.0
		if L.shadow_enabled != want:
			L.shadow_enabled = want

## Luce ambientale della scena per l'audio/HUD (0 notte fonda .. 1 pieno giorno).
func light_level() -> float:
	if not night:
		return 1.0
	return 0.12 + (0.5 if not flares.is_empty() else 0.0)
