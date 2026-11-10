class_name BattleAudio
extends Node3D
## Audio posizionale della battaglia 3D: legge `sim.units`, `sim.shells` e gli eventi `fx` della BattleSim e suona tutto
## con i banchi sintetizzati dall'autoload Sfx (nessun file audio).
##
## Uso (da Battle3D):
##   audio = BattleAudio.new(); add_child(audio); audio.setup(self, sim, cam)
##   in _consume_fx(): if not silent: audio.on_fx(list)      (prima di scartare la lista)
##   in _process():    audio.update(dt)
##   altri suoni:      audio.play_at("cannon_far", pos3d, "arty")   (es. cannoni navali di BattleCoast)
##
## Ascoltatore: AudioListener3D sopra il punto osservato dalla telecamera (orientato come la telecamera), più alto quando
## si allontana lo zoom. Voci: MAX_VOICES colpi in un pool di AudioStreamPlayer3D con priorità, limiti per categoria e
## intervallo minimo; i colpi troppo lontani per essere sentiti alimentano invece il "tappeto" di fucileria lontana.
## Loop: i 4 mezzi terrestri e i 2 aerei più udibili (motore + cingoli/gomme), volume e intonazione dalla velocità.
## Lontananza: attenuazione 1/d, filtro passa-basso dell'AudioStreamPlayer3D, varianti "lontane" (rombo cupo) e ritardo
## della velocità del suono. Bus "BattleSfx": riverbero d'esterni secondo il terreno, compressore e limitatore.
## Musica: due volte al secondo passa a Music.set_intensity() quanto è calda la battaglia (colpi pesanti, fucileria, voci).

const MAX_VOICES := 22
const LOOP_VOICES := 10          # 4 mezzi × (motore + cingoli) + 2 aerei
const GROUND_SLOTS := 4
const AIR_SLOTS := 2
const SOUND_SPEED := 340.0       # m/s (1 unità del mondo ≈ 1 m)
const MAX_DELAY := 2.0
const CULL_DB := -40.0           # sotto questo livello stimato il colpo non viene suonato
const GLOBAL_DB := -4.0
const BUS := "BattleSfx"

## categoria: [distanza di riferimento (m), dB, intervallo minimo (s), voci contemporanee, priorità]
const CAT := {
	"rifle": [11.0, -2.0, 0.035, 6, 1],
	"mg": [15.0, -2.0, 0.08, 4, 2],
	"hmg": [20.0, -1.0, 0.12, 2, 2],
	"aa": [28.0, -1.0, 0.12, 3, 3],
	"flak": [30.0, -4.0, 0.08, 3, 2],
	"cannon": [45.0, 0.0, 0.06, 4, 4],
	"arty": [70.0, 0.0, 0.1, 3, 4],
	"expl": [50.0, 0.0, 0.05, 5, 4],
	"big": [80.0, 1.0, 0.07, 4, 5],
	"small": [18.0, -3.0, 0.05, 4, 2],
	"rocket": [22.0, -1.0, 0.09, 3, 3],
	"whistle": [28.0, -3.0, 0.12, 3, 3],
	"misc": [16.0, -3.0, 0.1, 3, 1],
}
## varianti lontane: banco → [banco lontano, distanza oltre la quale si usa]
const FAR := {"cannon": ["cannon_far", 220.0], "explosion": ["explosion_far", 260.0], "arty_impact": ["explosion_far", 340.0],
	"hit_armor": ["explosion_far", 300.0]}
## loop dei mezzi: tipo → [motore, rotolamento, intonazione base, distanza di riferimento, aereo]
const LOOPS := {
	"tank": ["engine_heavy", "tracks", 1.0, 14.0, false],
	"art": ["engine_heavy", "tracks", 1.12, 12.0, false],
	"aa": ["engine_light", "tires", 1.0, 11.0, false],
	"heli": ["heli", "", 1.0, 40.0, true],
	"drone": ["drone", "", 1.0, 14.0, true],
	"jet": ["jet_loop", "", 1.0, 70.0, true],
}
const VEH := ["tank", "art", "aa", "bunker"]
const WIND_DB := {"artico": -9.0, "deserto": -12.0, "montagna": -11.0, "pianura": -15.0, "foresta": -19.0, "urbano": -21.0}
## riverbero del bus: [stanza, smorzamento, wet, predelay ms]
const REVERB := {"urbano": [0.55, 0.45, 0.2, 25.0], "montagna": [0.85, 0.5, 0.17, 90.0], "foresta": [0.6, 0.7, 0.14, 40.0],
	"artico": [0.7, 0.4, 0.1, 70.0], "deserto": [0.7, 0.6, 0.07, 80.0], "pianura": [0.7, 0.6, 0.09, 70.0]}

var sfx: Node = null              # autoload Sfx (sostituibile nei test)
var root: Node3D
var sim
var cam: Camera3D
var listener: AudioListener3D
var stats := {"played": 0, "dropped": 0, "culled": 0}
var cost_us := 0

var _terrain = null
var _pool: Array = []             # [{p, cat, prio, t}]
var _queue: Array = []            # [t, nome, pos, cat, dB, pitch]
var _last := {}                   # categoria -> ultimo avvio
var _time := 0.0
var _lis := Vector3.ZERO
var _ground: Array = []           # slot {a, b, u, g, pitch, spd, kind}
var _air: Array = []
var _pick_t := 0.0
var _whistled := {}               # id proiettile -> Vector2(x1, y1)
var _jets: Array = []
var _wind: AudioStreamPlayer
var _bed: AudioStreamPlayer
var _crackle: AudioStreamPlayer
# Fase 8 — ambiente legato a meteo/ora/terreno (BattleWeather, BattleMarks)
var _rain: AudioStreamPlayer
var _night: AudioStreamPlayer      # grilli (notte) — nel deserto/artico: vento notturno
var _birds: AudioStreamPlayer
var _surf: AudioStreamPlayer
var _fires: Array = []             # 2 sorgenti posizionali di incendio {p: AudioStreamPlayer3D, g: float, src: Vector3}
var _fire_t := 0.0
var _weather = null                # BattleWeather (root.weather) se presente
var _marks = null                  # BattleMarks (root.marks)
var photo := false
var _crackle_rate := 0.0
var _rumble_rate := 0.0
var _radio_t := -100.0
var _rng := RandomNumberGenerator.new()
var _bus_idx := -1
var _music: Node = null
var _mus_t := 0.0
var _inten := 0.45
## categorie pesanti: intonazione casuale spostata verso il basso (alzare un cannone lo rimpicciolisce)
const HEAVY := ["cannon", "arty", "expl", "big"]

func setup(battle_root: Node3D, s, camera: Camera3D) -> void:
	root = battle_root
	sim = s
	cam = camera
	_rng.randomize()
	if sfx == null:
		sfx = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("warm_battle"):
		sfx.warm_battle()
	_setup_bus()
	listener = AudioListener3D.new()
	listener.name = "Listener"
	add_child(listener)
	listener.make_current()
	for i in MAX_VOICES:
		var p := _player3d()
		_pool.append({"p": p, "cat": "", "prio": 0, "t": -100.0})
	for i in GROUND_SLOTS:
		_ground.append({"a": _player3d(), "b": _player3d(), "u": null, "g": 0.0, "pitch": 1.0, "spd": 0.0, "kind": ""})
	for i in AIR_SLOTS:
		_air.append({"a": _player3d(), "b": null, "u": null, "g": 0.0, "pitch": 1.0, "spd": 0.0, "kind": ""})
	_wind = _player2d()
	_bed = _player2d()
	_crackle = _player2d()
	_rain = _player2d()
	_night = _player2d()
	_birds = _player2d()
	_surf = _player2d()
	for i in 2:
		var fp := _player3d()
		fp.max_distance = 160.0
		fp.unit_size = 14.0
		_fires.append({"p": fp, "g": 0.0, "src": Vector3.INF})
	_update_listener()

## Modalità foto: i tappeti continuano, i colpi sono comunque fermi (sim in pausa).
func set_photo(on: bool) -> void:
	photo = on

func _player3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_db = 0.0
	p.attenuation_filter_cutoff_hz = 2500.0
	p.attenuation_filter_db = -20.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p

func _player2d() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS
	p.volume_db = -80.0
	add_child(p)
	return p

func _setup_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS)
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS)
		AudioServer.set_bus_send(_bus_idx, "Master")
		AudioServer.add_bus_effect(_bus_idx, AudioEffectReverb.new())
		var co := AudioEffectCompressor.new()
		co.threshold = -16.0
		co.ratio = 3.0
		co.attack_us = 3000.0
		co.release_ms = 220.0
		co.gain = 3.0
		AudioServer.add_bus_effect(_bus_idx, co)
		var li := AudioEffectLimiter.new()
		li.ceiling_db = -0.8
		li.threshold_db = -2.5
		AudioServer.add_bus_effect(_bus_idx, li)
	var rv = AudioServer.get_bus_effect(_bus_idx, 0)
	if rv is AudioEffectReverb:
		var tk := String(_sget("tkey", "pianura"))
		var R: Array = REVERB.get(tk, REVERB["pianura"])
		rv.room_size = R[0]
		rv.damping = R[1]
		rv.wet = R[2]
		rv.dry = 1.0
		rv.predelay_msec = R[3]
		rv.predelay_feedback = 0.25
		rv.hipass = 0.15
		rv.spread = 0.9

func _sget(k: String, def):
	if sim == null:
		return def
	var v = sim.get(k)
	return def if v == null else v

# ============================================================================================ aggiornamento per frame
func update(dt: float) -> void:
	if sim == null or cam == null:
		return
	var t0 := Time.get_ticks_usec()
	_time += dt
	_apply_volume()
	_update_listener()
	# eventi ritardati (velocità del suono, tempo di volo)
	if not _queue.is_empty():
		var i := 0
		while i < _queue.size():
			var q: Array = _queue[i]
			if float(q[0]) <= _time:
				_queue.remove_at(i)
				_start(q[1], q[2], q[3], q[4], q[5], 0.0)
			else:
				i += 1
	var paused := bool(_sget("paused", false)) or bool(_sget("done", false))
	_pick_t -= dt
	if _pick_t <= 0.0:
		_pick_t = 0.3
		_pick_loops()
	_update_loops(dt, paused)
	_update_shells()
	_update_jets(dt)
	_update_beds(dt, paused)
	_update_music(dt, paused)
	cost_us += Time.get_ticks_usec() - t0

func active_voices() -> int:
	var n := 0
	for v in _pool:
		if (v["p"] as AudioStreamPlayer3D).playing:
			n += 1
	for sl in _ground + _air:
		if (sl["a"] as AudioStreamPlayer3D).playing:
			n += 1
		if sl["b"] != null and (sl["b"] as AudioStreamPlayer3D).playing:
			n += 1
	return n

func _apply_volume() -> void:
	if _bus_idx < 0 or sfx == null:
		return
	var v := float(sfx.get("volume")) if sfx.get("volume") != null else 0.6
	var m := bool(sfx.get("muted")) if sfx.get("muted") != null else false
	AudioServer.set_bus_volume_db(_bus_idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(_bus_idx, m or v <= 0.001)

func _update_listener() -> void:
	var tgt = cam.get("target")
	var dist = cam.get("dist")
	var p: Vector3
	if tgt is Vector3:
		p = tgt
		p.y = _height(p.x, p.z)
	else:
		p = cam.global_position - cam.global_transform.basis.z * 60.0
	var d := float(dist) if dist != null else cam.global_position.distance_to(p)
	_lis = p + Vector3(0, 10.0 + d * 0.2, 0)
	if listener != null:
		listener.global_transform = Transform3D(cam.global_transform.basis, _lis)

func _height(x: float, z: float) -> float:
	if _terrain == null and root != null:
		_terrain = root.get("terrain")
	if _terrain != null and _terrain.has_method("height"):
		var h: float = _terrain.height(x, z)
		return maxf(h, 0.0) if bool(_sget("sea", false)) else h
	return 0.0

func _w(x: float, y: float, up := 1.5) -> Vector3:
	var w := BattleTerrain.sim_to_world(x, y)
	return Vector3(w.x, _height(w.x, w.y) + up, w.y)

func _pos_u(u) -> Vector3:
	if u == null:
		return _lis
	var up := 1.5
	if bool(u.air):
		up = 30.0 if u.type == "jet" else 18.0
	return _w(float(u.x), float(u.y), up)

# ============================================================================================ colpi singoli
## Suona `name` (banco Sfx) in un punto del mondo. Restituisce false se scartato (inudibile, limiti, banco non pronto).
func play_at(name: String, pos: Vector3, cat := "misc", vol_db := 0.0, pitch := 1.0, delay := 0.0) -> bool:
	var c: Array = CAT.get(cat, CAT["misc"])
	var d := maxf(1.0, pos.distance_to(_lis))
	var est := linear_to_db(float(c[0]) / d) + float(c[1]) + vol_db + GLOBAL_DB
	if est < CULL_DB:
		stats["culled"] += 1
		return false
	if FAR.has(name) and d > float(FAR[name][1]):
		name = FAR[name][0]
	var sd := clampf((d - 30.0) / SOUND_SPEED, 0.0, MAX_DELAY)
	if delay + sd > 0.02:
		if _queue.size() < 64:
			_queue.append([_time + delay + sd, name, pos, cat, vol_db, pitch])
			return true
		stats["dropped"] += 1
		return false
	return _start(name, pos, cat, vol_db, pitch, 0.0)

func _start(name: String, pos: Vector3, cat: String, vol_db: float, pitch: float, from: float) -> bool:
	var c: Array = CAT.get(cat, CAT["misc"])
	var prio: int = c[4]
	var gap: float = c[2]
	var busy := 0
	var same := 0
	var free = null
	var oldest_same = null
	var victim = null
	for v in _pool:
		var p: AudioStreamPlayer3D = v["p"]
		if p.playing:
			busy += 1
			if v["cat"] == cat:
				same += 1
				if oldest_same == null or float(v["t"]) < float(oldest_same["t"]):
					oldest_same = v
			elif int(v["prio"]) < prio and (victim == null or int(v["prio"]) < int(victim["prio"])
					or (int(v["prio"]) == int(victim["prio"]) and float(v["t"]) < float(victim["t"]))):
				victim = v
		elif free == null:
			free = v
	if busy > MAX_VOICES * 0.7:
		gap *= 2.0
	if _time - float(_last.get(cat, -100.0)) < gap:
		stats["dropped"] += 1
		return false
	var slot = free
	if same >= int(c[3]):
		slot = oldest_same if _time - float(oldest_same["t"]) > 0.25 else null
	elif slot == null:
		slot = victim
	if slot == null:
		stats["dropped"] += 1
		return false
	var st: AudioStream = sfx.stream(name) if sfx != null else null
	if st == null:
		stats["dropped"] += 1
		return false
	var pl: AudioStreamPlayer3D = slot["p"]
	pl.stop()
	pl.stream = st
	pl.global_position = pos
	pl.unit_size = float(c[0])
	pl.volume_db = float(c[1]) + vol_db + GLOBAL_DB
	pl.pitch_scale = clampf(pitch * (_rng.randf_range(0.93, 1.02) if cat in HEAVY else _rng.randf_range(0.94, 1.06)), 0.3, 3.0)
	pl.play(from)
	slot["cat"] = cat
	slot["prio"] = prio
	slot["t"] = _time
	_last[cat] = _time
	stats["played"] += 1
	return true

func _later(t: float, name: String, pos: Vector3, cat: String, vol_db := 0.0, pitch := 1.0) -> void:
	play_at(name, pos, cat, vol_db, pitch, t)

# ============================================================================================ eventi della sim
func on_fx(list: Array) -> void:
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	for e in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		match String(e.get("e", "")):
			"fire":
				_on_fire(e)
			"impact":
				var big := bool(e.get("big", false))
				play_at("arty_impact", _w(float(e.get("x", 0.0)), float(e.get("y", 0.0)), 0.5), "big", 3.0 if big else 0.0,
					0.92 if big else 1.0)
				_rumble_rate += 1.0
			"kill":
				_on_kill(e)
			"bomb":
				play_at("arty_impact", _w(float(e.get("x", 0.0)), float(e.get("y", 0.0)), 0.5), "big", 4.0, 0.88)
				_rumble_rate += 1.5
			"smoke":
				var u = e.get("u")
				var p := _pos_u(u) if u != null else _w(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
				play_at("smoke_pop", p, "misc", 2.0)
			"airstrike":
				_start_jet(e)
			"spotted":
				if bool(e.get("first", false)):
					_radio(int(e.get("side", -1)), -6.0)
			"ambush":
				_radio(int(e.get("side", -1)), -3.0)
	cost_us += Time.get_ticks_usec() - t0

func _radio(side: int, db: float) -> void:
	var hs := int(_sget("hs", -1))
	if hs < 0 or side == hs or _time - _radio_t < 4.0 or sfx == null:
		return
	_radio_t = _time
	sfx.play("radio", db_to_linear(db))

func _on_fire(e: Dictionary) -> void:
	var u = e.get("u")
	if u == null:
		return
	var src := _pos_u(u)
	if bool(e.get("art", false)):
		play_at("cannon", src, "arty", 2.0, 0.8)
		_rumble_rate += 0.5
		return
	var t = e.get("t")
	var tp: Vector3
	var tair := bool(e.get("tair", false))
	var ttype := ""
	if t != null:
		tp = _pos_u(t)
		tair = bool(t.air)
		ttype = String(t.type)
	else:
		tp = _w(float(e.get("tx", u.x)), float(e.get("ty", u.y)))
	var dist := src.distance_to(tp)
	var veh := ttype in VEH
	var amb := bool(e.get("ambush", false))
	var boost := 2.0 if amb else 0.0
	match String(u.type):
		"inf":
			var ok := false
			var r := _rng.randf()
			var rk = e.get("rocket")   # deciso dalla sim (fanteria anticarro contro un mezzo)
			if (bool(rk) if rk != null else (veh and r < 0.3)):
				ok = play_at("rocket", src, "rocket", boost)
				var tt := clampf(dist / 120.0, 0.25, 1.6)
				_later(tt, "hit_armor", tp, "expl", -2.0)
			elif r < 0.35:
				ok = play_at("mg", src, "mg", boost)
			else:
				ok = play_at("rifle", src, "rifle", boost)
			_crackle_rate += 0.3 if ok else 1.0
		"tank":
			play_at("cannon", src, "cannon", boost)
			if not tair:
				var tt2 := maxf(0.06, dist / 900.0)
				if veh:
					_later(tt2, "hit_armor", tp, "expl")
				else:
					_later(tt2, "expl_small", tp, "small")
			_rumble_rate += 0.4
		"aa":
			play_at("aa", src, "aa", boost)
			if tair:
				_later(maxf(0.08, dist / 700.0), "flak", tp, "flak")
		"heli", "jet":
			play_at("rocket", src, "rocket", boost - 1.0, 1.15)
			var tt3 := 0.3 if u.type == "jet" else 0.36
			_later(tt3, "hit_armor" if veh else "expl_small", tp, "expl" if veh else "small", 1.0)
		"drone":
			play_at("mg", src, "mg", boost - 5.0, 1.3)
		"bunker":
			play_at("hmg", src, "hmg", boost)
		_:
			play_at("mg", src, "mg", boost)

func _on_kill(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	var air := bool(e.get("air", false))
	var p := _w(float(e.get("x", 0.0)), float(e.get("y", 0.0)), 18.0 if air else 0.8)
	var u = e.get("u")
	if air and u != null:
		p = _pos_u(u)
	match t:
		"inf":
			if _rng.randf() < 0.35:
				play_at("expl_small", p, "small", -8.0)
		"drone":
			play_at("expl_small", p, "small", -2.0, 1.2)
		"heli", "jet":
			play_at("explosion", p, "expl", 0.0, 1.05)
			_rumble_rate += 1.0
		"bunker":
			play_at("arty_impact", p, "big", 2.0, 0.9)
			_rumble_rate += 1.0
		_:
			play_at("explosion", p, "expl", 1.0)
			if _rng.randf() < 0.45:
				_later(_rng.randf_range(0.7, 1.8), "cookoff", p, "small", -3.0)
			_rumble_rate += 1.0

# ============================================================================================ proiettili d'artiglieria
func _update_shells() -> void:
	var shells = _sget("shells", null)
	if shells == null:
		return
	for s in shells:
		if s == null or not bool(s.get("on")):
			continue
		var id: int = s.get_instance_id()
		var key := Vector2(float(s.get("x1")), float(s.get("y1")))
		if _whistled.has(id) and _whistled[id] == key:
			continue
		var rem := float(s.get("T")) - float(s.get("t"))
		if rem > 1.9 or rem < 0.3:
			continue
		_whistled[id] = key
		var p := _w(key.x, key.y, 8.0)
		if p.distance_to(_lis) > 240.0:
			continue
		var pitch := _rng.randf_range(0.93, 1.07)
		# il fischio (2 s) termina all'impatto
		_start("whistle", p, "whistle", 0.0, pitch / 1.0, maxf(0.0, 2.0 - rem * pitch))
	if _whistled.size() > 400:
		_whistled.clear()

# ============================================================================================ caccia del supporto aereo
const JET_V := 78.0

func _start_jet(e: Dictionary) -> void:
	if _jets.size() >= 2:
		return
	var w := BattleTerrain.sim_to_world(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
	var dir := float(e.get("dir", 1.0))
	var fwd := Vector3(dir, 0, 0).rotated(Vector3.UP, 0.18 * dir)
	var p := _player3d()
	p.unit_size = 90.0
	p.volume_db = GLOBAL_DB + 2.0
	_jets.append({"p": p, "T": Vector3(w.x, maxf(_height(w.x, w.y), 0.0), w.y), "fwd": fwd, "t": -float(e.get("delay", 3.0)), "on": false})

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
		var p: AudioStreamPlayer3D = j["p"]
		if tau > 4.0:
			p.queue_free()
			_jets.remove_at(i)
			continue
		p.global_position = _jet_pos(j, tau)
		if not j["on"] and tau > -2.6 and sfx != null:
			var st = sfx.stream("jet_flyby")
			if st != null:
				p.stream = st
				p.pitch_scale = _rng.randf_range(0.95, 1.05)
				p.play()
			j["on"] = true
		i += 1

# ============================================================================================ motori (loop)
func _pick_loops() -> void:
	var units = _sget("units", [])
	var gc: Array = []
	var ac: Array = []
	for u in units:
		if u.dead or not LOOPS.has(u.type):
			continue
		var L: Array = LOOPS[u.type]
		var d := maxf(1.0, _pos_u(u).distance_to(_lis))
		var spd := clampf(Vector2(u.vx, u.vy).length() / maxf(1.0, float(u.speed)), 0.0, 1.0)
		var sc := float(L[3]) / d * (1.0 if L[4] else 0.35 + spd)
		if sc < 0.025:
			continue
		if L[4]:
			ac.append([sc, u])
		else:
			gc.append([sc, u])
	_assign(_ground, gc)
	_assign(_air, ac)

func _assign(slots: Array, cands: Array) -> void:
	cands.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var want: Array = []
	for k in mini(slots.size(), cands.size()):
		want.append(cands[k][1])
	for sl in slots:
		if sl["u"] != null and not (sl["u"] in want):
			sl["kind"] = "out"     # sfuma e libera
	for u in want:
		var have := false
		for sl in slots:
			if sl["u"] == u:
				have = true
				if sl["kind"] == "out":
					sl["kind"] = "in"
				break
		if have:
			continue
		for sl in slots:
			if sl["u"] == null:
				_bind(sl, u)
				break

func _bind(sl: Dictionary, u) -> void:
	var L: Array = LOOPS[u.type]
	var a: AudioStreamPlayer3D = sl["a"]
	var st = sfx.stream(L[0]) if sfx != null else null
	if st == null:
		return
	sl["u"] = u
	sl["g"] = 0.0
	sl["kind"] = "in"
	sl["pitch"] = float(L[2]) * _rng.randf_range(0.92, 1.08)
	sl["spd"] = 0.0
	a.stream = st
	a.unit_size = float(L[3])
	a.volume_db = -60.0
	a.play(_rng.randf_range(0.0, 1.8))
	var b = sl["b"]
	if b != null:
		var st2 = sfx.stream(L[1]) if String(L[1]) != "" else null
		if st2 != null:
			(b as AudioStreamPlayer3D).stream = st2
			(b as AudioStreamPlayer3D).unit_size = float(L[3]) * 0.8
			(b as AudioStreamPlayer3D).volume_db = -60.0
			(b as AudioStreamPlayer3D).play(_rng.randf_range(0.0, 1.8))

func _update_loops(dt: float, paused: bool) -> void:
	for sl in _ground + _air:
		var u = sl["u"]
		if u == null:
			continue
		var a: AudioStreamPlayer3D = sl["a"]
		var b = sl["b"]
		var target := 0.0 if (paused or u.dead or sl["kind"] == "out") else 1.0
		sl["g"] = move_toward(float(sl["g"]), target, dt * (2.5 if target > 0.0 else 1.5))
		var g: float = sl["g"]
		if g <= 0.001 and target == 0.0:
			a.stop()
			if b != null:
				(b as AudioStreamPlayer3D).stop()
			sl["u"] = null
			continue
		var p := _pos_u(u)
		a.global_position = p
		var spd_t := clampf(Vector2(u.vx, u.vy).length() / maxf(1.0, float(u.speed)), 0.0, 1.0)
		sl["spd"] = lerpf(float(sl["spd"]), spd_t, minf(1.0, dt * 2.0))
		var spd: float = sl["spd"]
		var gdb := linear_to_db(maxf(g, 0.001))
		var L: Array = LOOPS[u.type]
		if L[4]:
			a.pitch_scale = float(sl["pitch"]) * (0.95 + 0.1 * spd)
			a.volume_db = GLOBAL_DB - 3.0 + gdb
		else:
			a.pitch_scale = float(sl["pitch"]) * (0.8 + 0.42 * spd)
			a.volume_db = GLOBAL_DB - 12.0 + 9.0 * spd + gdb
			if b != null:
				var bp: AudioStreamPlayer3D = b
				bp.global_position = p
				bp.pitch_scale = 0.7 + 0.5 * spd
				bp.volume_db = (GLOBAL_DB - 40.0 + 34.0 * pow(spd, 0.6) if spd > 0.03 else -70.0) + gdb

# ============================================================================================ intensità della musica
## La musica di battaglia (autoload Music) alza percussioni e braam quando la battaglia si scalda: colpi pesanti,
## fucileria, voci attive. Aggiornata due volte al secondo, salita e discesa lente (le rampe le fa Music).
func _update_music(dt: float, paused: bool) -> void:
	_mus_t -= dt
	if _mus_t > 0.0:
		return
	_mus_t = 0.5
	if _music == null:
		_music = get_node_or_null("/root/Music")
		if _music == null or not _music.has_method("set_intensity"):
			_music = null
			_mus_t = 5.0
			return
	var heat := clampf((_rumble_rate + _crackle_rate * 0.35 + float(active_voices()) * 0.12) / 6.0, 0.0, 1.0)
	var tgt := 0.15 if paused else 0.25 + 0.75 * sqrt(heat)
	_inten = lerpf(_inten, tgt, 0.35)
	_music.call("set_intensity", _inten)

# ============================================================================================ tappeti d'ambiente
func _update_beds(dt: float, paused: bool) -> void:
	var dec := exp(-dt / 3.0)
	_crackle_rate *= dec
	_rumble_rate *= dec
	var ok := 0.0
	if cam.has_method("overview_k"):
		ok = float(cam.call("overview_k"))
	var tk := String(_sget("tkey", "pianura"))
	var sea := bool(_sget("sea", false))
	var wdb: float = WIND_DB.get(tk, -15.0) + 4.0 * ok + (1.0 if sea else 0.0)
	# --- Fase 8: meteo e ora (BattleWeather della vista; assente nei test headless)
	if _weather == null and root != null:
		_weather = root.get("weather")
		_marks = root.get("marks")
	var rain := 0.0
	var wk := "sereno"
	var night := false
	var wind_pitch := 1.0
	if _weather != null:
		rain = float(_weather.get("rain"))
		wk = String(_weather.get("kind"))
		night = bool(_weather.get("night"))
		match wk:
			"temporale": wdb += 8.0; wind_pitch = 0.92
			"pioggia": wdb += 3.0
			"neve": wdb += 4.0; wind_pitch = 0.85
			"nebbia": wdb -= 7.0; wind_pitch = 0.8
		if night and tk in ["deserto", "artico"]:
			wdb += 3.0; wind_pitch = 0.72    # vento notturno del deserto / bufera artica
		# tuoni (dopo il lampo, ritardo = distanza)
		var tq = _weather.get("thunder_queue")
		if tq is Array:
			while not (tq as Array).is_empty():
				var th: Array = (tq as Array).pop_front()
				var strength := float(th[1])
				_later(float(th[0]), "amb_thunder", _lis + Vector3(_rng.randf_range(-200, 200), 60.0, _rng.randf_range(-200, 200)), "misc", -6.0 + 8.0 * strength, _rng.randf_range(0.8, 1.1))
	_wind.pitch_scale = lerpf(_wind.pitch_scale, wind_pitch, minf(1.0, dt * 0.5)) if _wind.playing else wind_pitch
	_bed_level(_wind, "amb_wind", wdb, dt)
	var heat := clampf((_rumble_rate + _crackle_rate * 0.3) / 5.0, 0.0, 1.0)
	# pioggia: intensità → livello; da lontano (vista d'insieme) un po' più piatta
	_bed_level(_rain, "amb_rain", (-38.0 + 20.0 * sqrt(rain) - 3.0 * ok) if rain > 0.04 else -70.0, dt)
	# notte: grilli (non nel deserto/artico, dove c'è solo il vento), più timidi quando si spara
	var crick := night and not (tk in ["deserto", "artico"]) and rain < 0.3
	_bed_level(_night, "amb_crickets", (-26.0 - 10.0 * heat - 4.0 * ok) if crick else -70.0, dt)
	# uccelli al mattino quando è tranquillo (niente pioggia/neve/nebbia fitta)
	var morning := String(root.get("mood")) == "mattino" if root != null else false
	var birds := morning and not night and heat < 0.12 and rain < 0.05 and wk != "nebbia" and wk != "neve" and tk != "artico"
	_bed_level(_birds, "amb_birds", (-24.0 - 5.0 * ok) if birds else -70.0, dt)
	# risacca vicino alla costa
	if sea:
		var dcoast := 0.0
		if _terrain != null and _terrain.has_method("coast_x"):
			dcoast = maxf(0.0, _lis.x - float(_terrain.coast_x(_lis.z)))
		_bed_level(_surf, "amb_surf", -14.0 - clampf(dcoast / 25.0, 0.0, 14.0) + 2.0 * ok, dt)
	# incendi: le due sorgenti più vicine (relitti in fiamme, macerie) in posizione
	_fire_t -= dt
	if _fire_t <= 0.0:
		_fire_t = 0.5
		_pick_fires()
	for f in _fires:
		var fp: AudioStreamPlayer3D = f["p"]
		var src: Vector3 = f["src"]
		var tgt := 0.0 if src.x == INF else 1.0
		f["g"] = move_toward(float(f["g"]), tgt, dt * 1.2)
		var g: float = f["g"]
		if g <= 0.001 and tgt == 0.0:
			if fp.playing:
				fp.stop()
			continue
		if not fp.playing:
			if sfx == null:
				continue
			var st = sfx.stream("amb_fire")
			if st == null:
				continue
			fp.stream = st
			fp.play(_rng.randf_range(0.0, 5.0))
		if src.x != INF:
			fp.global_position = src
		fp.volume_db = GLOBAL_DB - 6.0 + linear_to_db(maxf(g, 0.001))
	# fucileria lontana: proporzionale ai colpi di fanteria non suonati singolarmente
	var cl := clampf(_crackle_rate / 8.0, 0.0, 1.0)
	_bed_level(_crackle, "amb_crackle", -70.0 if cl < 0.02 or paused else -34.0 + 24.0 * sqrt(cl), dt)
	var rl := clampf((_rumble_rate + _crackle_rate * 0.2) / 6.0, 0.0, 1.0)
	_bed_level(_bed, "amb_battle", -70.0 if rl < 0.02 or paused else -32.0 + 20.0 * sqrt(rl), dt)

## Sorgenti di incendio attive più vicine all'ascoltatore: relitti in fiamme (root.wrecks, età < 80 s) e macerie (marks.fires).
func _pick_fires() -> void:
	var cands := []
	if root != null:
		var wr = root.get("wrecks")
		if wr is Array:
			for w in wr:
				var age := float(w.get("age", 999.0))
				if age < 75.0:
					var p: Vector3 = w["p"]
					cands.append([p.distance_squared_to(_lis), p])
		if _marks != null:
			var fl = _marks.get("fires")
			if fl is Array:
				for f in fl:
					var p2: Vector3 = f["p"]
					cands.append([p2.distance_squared_to(_lis), p2])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in _fires.size():
		if i < cands.size() and float(cands[i][0]) < 150.0 * 150.0:
			_fires[i]["src"] = cands[i][1]
		else:
			_fires[i]["src"] = Vector3.INF

func _bed_level(p: AudioStreamPlayer, name: String, db: float, dt: float) -> void:
	if not p.playing:
		if db < -60.0 or sfx == null:
			return
		var st = sfx.stream(name)
		if st == null:
			return
		p.stream = st
		p.volume_db = -70.0
		p.play(_rng.randf_range(0.0, 4.0))
	# rampa in dB (~12 dB/s): niente scatti
	p.volume_db = move_toward(p.volume_db, db + GLOBAL_DB, dt * 12.0)
	if p.volume_db < -69.0 and db < -60.0:
		p.stop()
