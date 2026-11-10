extends Node
## Autoload "Sfx": effetti sonori sintetizzati in codice (nessun file audio).
##
## Nomi storici (compatibili): 'click','select','order','build','recruit','research','capture','battle','explosion',
## 'cannon','gun','missile','alert','victory','defeat','card'.
## Banchi nuovi (battaglia, più varianti ciascuno): rifle, mg, hmg, aa, flak, cannon, cannon_far, explosion, explosion_far,
## arty_impact, expl_small, hit_armor, rocket, smoke_pop, cookoff, whistle, jet_flyby, radio;
## loop: engine_heavy, engine_light, tracks, tires, heli, drone, jet_loop, amb_wind, amb_battle, amb_crackle;
## ambiente (Fase 8, meteo/ora): amb_rain, amb_crickets, amb_birds, amb_surf, amb_fire (loop), amb_thunder (3 varianti).
##
## API:
##   Sfx.play(name, vol_scale := 1.0)        suono 2D non posizionale (variante a caso, intonazione ±5%)
##   Sfx.stream(name) -> AudioStreamWAV       variante a caso se già generata, altrimenti null (e la mette in coda)
##   Sfx.stream_sync(name) -> AudioStreamWAV  come sopra ma genera subito se manca (bloccante)
##   Sfx.warm(names, front := false)          genera in sottofondo (WorkerThreadPool, un banco alla volta)
##   Sfx.warm_battle()                        mette in testa alla coda tutti i suoni di battaglia
##   Sfx.is_ready(name) -> bool
##   Sfx.render_raw(name) -> Array[PackedFloat32Array]   sintesi sincrona dei campioni float (test)
##   Sfx.set_volume(v), Sfx.set_muted(m), Sfx.toggle_muted(), Sfx.volume, Sfx.muted
## I campioni sono AudioStreamWAV mono 16 bit (32 kHz armi vicine, 22,05 kHz lontani, loop e interfaccia).

const RATE := 22050
const HI := 32000
const MAX_VOICES := 14

## banco: [varianti, frequenza, durata (s), loop, tipo]   tipo "ui" = interfaccia (generabile al volo, intonazione fissa)
const DEFS := {
	# --- interfaccia (stile consolle/radio militare)
	"click": [1, RATE, 0.06, false, "ui"],
	"select": [1, RATE, 0.12, false, "ui"],
	"order": [1, RATE, 0.24, false, "ui"],
	"build": [1, RATE, 0.5, false, "ui"],
	"recruit": [1, RATE, 0.32, false, "ui"],
	"research": [1, RATE, 0.46, false, "ui"],
	"capture": [1, RATE, 1.3, false, "ui"],
	"battle": [1, RATE, 1.4, false, "ui"],
	"alert": [1, RATE, 0.66, false, "ui"],
	"victory": [1, RATE, 1.9, false, "ui"],
	"defeat": [1, RATE, 2.3, false, "ui"],
	"card": [1, RATE, 0.32, false, "ui"],
	"radio": [2, RATE, 0.3, false, "ui"],
	# --- armi
	"rifle": [5, HI, 1.0, false, "b"],
	"mg": [4, HI, 1.5, false, "b"],
	"hmg": [3, HI, 1.6, false, "b"],
	"aa": [3, HI, 1.9, false, "b"],
	"flak": [3, HI, 1.6, false, "b"],
	"cannon": [4, HI, 3.0, false, "b"],
	"cannon_far": [3, RATE, 3.6, false, "b"],
	"explosion": [4, HI, 2.8, false, "b"],
	"explosion_far": [3, RATE, 3.6, false, "b"],
	"arty_impact": [3, HI, 3.4, false, "b"],
	"expl_small": [3, HI, 1.7, false, "b"],
	"hit_armor": [3, HI, 1.5, false, "b"],
	"rocket": [3, HI, 1.9, false, "b"],
	"smoke_pop": [2, HI, 1.7, false, "b"],
	"cookoff": [2, HI, 2.8, false, "b"],
	"whistle": [3, RATE, 2.0, false, "b"],
	"jet_flyby": [2, RATE, 6.0, false, "b"],
	# --- loop (motori, rotori, ambiente)
	"engine_heavy": [1, RATE, 3.0, true, "b"],
	"engine_light": [1, RATE, 2.0, true, "b"],
	"tracks": [1, RATE, 2.0, true, "b"],
	"tires": [1, RATE, 2.0, true, "b"],
	"heli": [1, RATE, 2.0, true, "b"],
	"drone": [1, RATE, 2.0, true, "b"],
	"jet_loop": [1, RATE, 3.0, true, "b"],
	"amb_wind": [1, RATE, 8.0, true, "b"],
	"amb_battle": [1, RATE, 10.0, true, "b"],
	"amb_crackle": [1, RATE, 8.0, true, "b"],
	# --- ambiente della battaglia (Fase 8): pioggia, grilli, uccelli, risacca, incendio (posizionale), tuono
	"amb_rain": [1, RATE, 8.0, true, "b"],
	"amb_crickets": [1, RATE, 8.0, true, "b"],
	"amb_birds": [1, RATE, 10.0, true, "b"],
	"amb_surf": [1, RATE, 10.0, true, "b"],
	"amb_fire": [1, RATE, 6.0, true, "b"],
	"amb_thunder": [3, RATE, 5.0, false, "b"],
}
## nomi storici → banco nuovo
const ALIAS := {"gun": "rifle", "missile": "rocket"}
## intervallo minimo (s) tra due esecuzioni 2D dello stesso suono
const GAP := {"click": 0.03, "select": 0.05, "order": 0.06, "build": 0.15, "recruit": 0.12, "research": 0.3,
	"capture": 0.25, "battle": 0.4, "explosion": 0.07, "cannon": 0.08, "gun": 0.045, "missile": 0.1,
	"alert": 0.4, "victory": 1.0, "defeat": 1.0, "card": 0.2, "radio": 0.2}
## volume relativo dei suoni 2D (i banchi sono normalizzati in picco)
const GAIN := {"click": 0.3, "select": 0.36, "order": 0.4, "build": 0.42, "recruit": 0.4, "research": 0.36, "card": 0.4,
	"capture": 0.5, "battle": 0.62, "alert": 0.34, "radio": 0.42, "victory": 0.55, "defeat": 0.55,
	"rifle": 0.55, "mg": 0.55, "hmg": 0.6, "explosion": 0.85, "cannon": 0.85, "rocket": 0.7}
## ordine di generazione in sottofondo: prima l'interfaccia, poi le armi principali, poi il resto
const ORDER := ["click", "select", "order", "alert", "card", "build", "recruit", "research", "capture", "battle", "victory",
	"defeat", "radio", "rifle", "cannon", "explosion", "mg", "engine_heavy", "tracks", "arty_impact", "expl_small",
	"cannon_far", "explosion_far", "hit_armor", "rocket", "aa", "flak", "hmg", "whistle", "amb_wind", "amb_crackle",
	"amb_battle", "engine_light", "tires", "heli", "drone", "jet_loop", "jet_flyby", "smoke_pop", "cookoff",
	"amb_rain", "amb_fire", "amb_thunder", "amb_crickets", "amb_birds", "amb_surf"]

signal muted_changed(muted: bool)

var muted := false
var volume := 0.6
var _bank := {}              # nome -> Array[AudioStreamWAV]
var _last := {}
var _players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _mutex := Mutex.new()
var _queue: Array = []
var _task := -1
var _cancel := false
var gen_ms := {}             # nome -> ms di sintesi (diagnostica)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)
	# generazione in sottofondo (non in modalità headless: i test sintetizzano da sé)
	if DisplayServer.get_name() != "headless":
		warm(ORDER)

func _exit_tree() -> void:
	_cancel = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_kick()

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)

func set_muted(m: bool) -> void:
	muted = m
	if muted:
		for p in _players:
			p.stop()
	muted_changed.emit(muted)

func toggle_muted() -> void:
	set_muted(not muted)

func has_sound(name: String) -> bool:
	return DEFS.has(_res(name))

func names() -> Array:
	return DEFS.keys()

func is_loop(name: String) -> bool:
	var d = DEFS.get(_res(name))
	return d != null and bool(d[3])

func _res(name: String) -> String:
	return String(ALIAS.get(name, name))

## Riproduce un suono 2D. vol_scale moltiplica il volume generale (0..1+).
func play(name: String, vol_scale: float = 1.0) -> void:
	if muted or volume <= 0.001:
		return
	var key := _res(name)
	if not DEFS.has(key):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = GAP.get(name, 0.05)
	if _last.has(name) and now - float(_last[name]) < gap:
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		return
	var ui: bool = DEFS[key][4] == "ui"
	var st: AudioStreamWAV = stream_sync(key) if ui else stream(key)
	if st == null:
		return
	_last[name] = now
	player.stream = st
	player.pitch_scale = _rng.randf_range(0.985, 1.015) if ui else _rng.randf_range(0.94, 1.06)
	player.volume_db = linear_to_db(maxf(0.0001, volume * vol_scale * float(GAIN.get(name, GAIN.get(key, 0.9)))))
	player.play()

## Compatibilità (battle3d._prewarm): non blocca per i suoni di battaglia, li mette in coda.
func _get_stream(name: String) -> AudioStreamWAV:
	var key := _res(name)
	if not DEFS.has(key):
		return null
	if DEFS[key][4] == "ui":
		return stream_sync(key)
	warm([key], true)
	return stream(key)

func preload_all() -> void:
	warm(ORDER)

func is_ready(name: String) -> bool:
	_mutex.lock()
	var ok := _bank.has(_res(name))
	_mutex.unlock()
	return ok

## Variante a caso, già generata; altrimenti null (e il banco va in coda).
func stream(name: String, variant := -1) -> AudioStreamWAV:
	var key := _res(name)
	_mutex.lock()
	var arr = _bank.get(key)
	_mutex.unlock()
	if arr == null:
		if DEFS.has(key):
			warm([key], true)
		return null
	var a: Array = arr
	if a.is_empty():
		return null
	return a[variant % a.size()] if variant >= 0 else a[_rng.randi() % a.size()]

func stream_sync(name: String, variant := -1) -> AudioStreamWAV:
	var key := _res(name)
	if not is_ready(key) and DEFS.has(key):
		_build_bank(key)
	return stream(key, variant)

func warm(list: Array, front := false) -> void:
	_mutex.lock()
	for n in list:
		var k := _res(String(n))
		if not DEFS.has(k) or _bank.has(k):
			continue
		var i := _queue.find(k)
		if i >= 0:
			if not front:
				continue
			_queue.remove_at(i)
		if front:
			_queue.push_front(k)
		else:
			_queue.append(k)
	_mutex.unlock()
	_kick()

func warm_battle() -> void:
	var l: Array = []
	for k in ORDER:
		if DEFS[k][4] != "ui":
			l.append(k)
	l.reverse()
	warm(l, true)   # push_front in ordine inverso => ORDER resta l'ordine di generazione

func _kick() -> void:
	if _task >= 0 or _queue.is_empty() or not is_inside_tree():
		return
	_task = WorkerThreadPool.add_task(_work, false, "Sfx")

func _work() -> void:
	while not _cancel:
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			return
		var k: String = _queue.pop_front()
		var have := _bank.has(k)
		_mutex.unlock()
		if not have:
			_build_bank(k)

func _build_bank(key: String) -> void:
	var t0 := Time.get_ticks_usec()
	var raws := render_raw(key)
	var d: Array = DEFS[key]
	var arr: Array = []
	for raw in raws:
		arr.append(_to_wav(raw, int(d[1]), bool(d[3])))
	_mutex.lock()
	if not _bank.has(key):
		_bank[key] = arr
	gen_ms[key] = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.unlock()

static func _to_wav(raw: PackedFloat32Array, sr: int, loop: bool) -> AudioStreamWAV:
	var n := raw.size()
	var half := (n + 1) / 2
	var ints := PackedInt32Array()
	ints.resize(half)
	for i in half:
		var a := int(clampf(raw[2 * i], -1.0, 1.0) * 32767.0)
		var b := 0
		if 2 * i + 1 < n:
			b = int(clampf(raw[2 * i + 1], -1.0, 1.0) * 32767.0)
		ints[i] = (a & 0xFFFF) | ((b & 0xFFFF) << 16)
	var bytes := ints.to_byte_array()
	bytes.resize(n * 2)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = sr
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = n
	return st

## Sintesi sincrona di tutte le varianti di un banco (campioni float, picco ≤ 0,97).
func render_raw(name: String) -> Array:
	var key := _res(name)
	var d: Array = DEFS[key]
	var out: Array = []
	for v in int(d[0]):
		var sy := Syn.new(int(d[1]), float(d[2]), hash(key) % 100000 + v * 7717 + 1)
		sy.loop = bool(d[3])
		_recipe(key, v, sy)
		if bool(d[3]):
			sy.loopify_to(float(d[2]))
		sy.finish(0.97 if d[4] != "ui" else 0.9)
		out.append(sy.b)
	return out

# =================================================================================================== ricette
func _recipe(k: String, v: int, s: Syn) -> void:
	match k:
		# ---------------------------------------------------------------- interfaccia: consolle militare, niente "bip"
		"click":
			# relè: contatto, corpo smorzato, piccolo rimbalzo
			s.nb(0.0, 0.004, 0.7, 0.0001, 0.0008, Syn.BP, 2300, 2300, 1.2)
			s.thump(0.0, 0.03, 0.45, 260, 150, 0.004, 0.0003, 0.006)
			s.nb(0.009, 0.003, 0.25, 0.0001, 0.0006, Syn.BP, 1700, 1700, 1.5)
			s.lp(4500)
			s.hp(90)
		"select":
			# interruttore a levetta, attutito: tonfo + scatto del fermo
			s.thump(0.0, 0.07, 0.9, 170, 95, 0.01, 0.0004, 0.018)
			s.nb(0.0, 0.006, 0.6, 0.0001, 0.0015, Syn.LP, 1800, 1800, 0.7)
			s.metal(0.002, [1150.0, 2630.0], [0.1, 0.05], [0.008, 0.005])
			s.nb(0.045, 0.004, 0.25, 0.0001, 0.001, Syn.BP, 1400, 1400, 1.2)
			s.lp(3800)
			s.hp(60)
		"order":
			# radio: si preme il tasto, gracchio, mezza parola incomprensibile, si rilascia
			s.nb(0.0, 0.004, 0.6, 0.0001, 0.001, Syn.HP, 1800, 1800, 0.7)
			s.nb(0.004, 0.07, 0.55, 0.002, 0.03, Syn.BP, 1500, 1300, 0.6)
			s.chatter(0.05, 0.17, 0.35)
			s.nb(0.23, 0.05, 0.5, 0.001, 0.02, Syn.BP, 1700, 1500, 0.6)
			s.nb(0.235, 0.004, 0.45, 0.0001, 0.001, Syn.HP, 1800, 1800, 0.7)
			s.radio_band()
			s.sat(2.0)
		"build":
			# pressa / bullone: tonfo pesante, lamiera grave, cricchetto
			s.thump(0.0, 0.35, 1.0, 95, 58, 0.03, 0.001, 0.09)
			s.metal(0.0, [182.0, 431.0, 797.0, 1203.0], [0.35, 0.25, 0.16, 0.08], [0.14, 0.09, 0.05, 0.03])
			s.nb(0.0, 0.03, 0.6, 0.0002, 0.008, Syn.LP, 1600, 900, 0.7)
			for j in 5:
				var tj := 0.17 + j * s.r(0.035, 0.05)
				s.nb(tj, 0.004, 0.22, 0.0001, 0.0012, Syn.BP, 2600, 2600, 2.0)
				s.thump(tj, 0.02, 0.12, 320, 220, 0.004, 0.0002, 0.005)
			s.lp(5000)
		"recruit":
			# otturatore di fucile: indietro (scatto + scorrimento), avanti (colpo secco), corpo di legno
			s.nb(0.0, 0.006, 0.55, 0.0001, 0.0015, Syn.BP, 2800, 2800, 1.5)
			s.metal(0.0, [820.0, 1930.0, 3100.0], [0.25, 0.14, 0.06], [0.012, 0.008, 0.005])
			s.nb(0.012, 0.07, 0.1, 0.01, 0.03, Syn.BP, 3200, 2400, 1.0)
			s.nb(0.13, 0.006, 0.7, 0.0001, 0.0015, Syn.BP, 2300, 2300, 1.5)
			s.metal(0.13, [700.0, 1650.0, 2900.0], [0.3, 0.16, 0.07], [0.016, 0.01, 0.006])
			s.thump(0.13, 0.06, 0.45, 210, 120, 0.01, 0.0004, 0.014)
			s.lp(6000)
		"research":
			# telescrivente: ticchettio irregolare, poi il timbro che si posa (inizio turno, voci del registro)
			var tt := 0.0
			for j in 6:
				var aj := s.r(0.5, 1.0)
				s.nb(tt, 0.003, 0.4 * aj, 0.0001, 0.0009, Syn.BP, s.r(2600, 3400), 3000, 2.0)
				s.thump(tt, 0.015, 0.22 * aj, 430, 300, 0.003, 0.0002, 0.004)
				tt += s.r(0.035, 0.06)
			s.rumble(0.0, 0.3, 0.04, 140, 0.01, 0.2, 6, 0.3)
			s.thump(0.33, 0.13, 0.85, 120, 68, 0.02, 0.0006, 0.04)
			s.nb(0.33, 0.012, 0.45, 0.0002, 0.003, Syn.LP, 1100, 700, 0.7)
			s.lp(5500)
		"capture":
			# timbro pesante sulla mappa e tamburo grave lontano
			s.thump(0.0, 0.25, 1.0, 88, 52, 0.02, 0.0008, 0.06)
			s.nb(0.0, 0.015, 0.7, 0.0002, 0.004, Syn.LP, 1300, 800, 0.7)
			s.metal(0.0, [143.0, 337.0, 611.0], [0.35, 0.22, 0.1], [0.08, 0.05, 0.03])
			s.nb(0.0, 0.025, 0.55, 0.0002, 0.006, Syn.BP, 900, 700, 0.8)
			s.thump(0.12, 1.1, 0.6, 62, 38, 0.06, 0.004, 0.4)
			s.rumble(0.14, 1.1, 0.22, 120, 0.05, 0.45, 3, 0.4)
			s.lp(2800)
		"battle":
			# inizio della battaglia: colpo sub, rombo, ottoni gravi a quinta vuota (braam corto)
			s.thump(0.0, 1.1, 0.9, 60, 30, 0.07, 0.005, 0.35)
			s.nb(0.0, 0.8, 0.7, 0.004, 0.2, Syn.LP, 600, 100, 0.7)
			s.rumble(0.05, 1.3, 0.3, 120, 0.1, 0.6, 4, 0.6)
			s.drone(0.02, 1.25, 55.0, 0.5, 0.12, 0.8, 650.0)
			s.drone(0.02, 1.25, 82.4, 0.3, 0.14, 0.8, 700.0)
			s.sat(1.4)
		"alert":
			# allarme grave: due impulsi uguali (stessa nota, nessuna melodia) di sirena smorzata con colpo sub
			for i in 2:
				var ta := i * 0.3
				s.drone(ta, 0.24, 196.0, 0.7, 0.025, 0.08, 900.0, 0.04)
				s.thump(ta, 0.12, 0.45, 110, 70, 0.02, 0.001, 0.04)
			s.nb(0.0, 0.004, 0.3, 0.0001, 0.001, Syn.HP, 1800, 1800, 0.7)
			s.lp(2200)
			s.sat(1.5)
		"victory":
			# timbro grave, poi ottoni bassi a quinte vuote (re-la-re) che si gonfiano: solenne, niente fanfara
			s.thump(0.0, 0.5, 1.0, 90, 52, 0.03, 0.001, 0.12)
			s.nb(0.0, 0.015, 0.5, 0.0002, 0.004, Syn.LP, 1200, 700, 0.7)
			for x in [[73.42, 0.55], [110.0, 0.4], [146.83, 0.3]]:
				s.drone(0.12, 1.75, float(x[0]), float(x[1]), 0.55, 0.8, 900.0)
			s.thump(0.12, 1.6, 0.5, 55, 40, 0.1, 0.01, 0.6)
			s.lp(2400)
		"defeat":
			# braam scuro: seconda minore grave (do-reb) che scende appena, tuono lontano
			s.thump(0.0, 1.6, 0.8, 52, 30, 0.08, 0.004, 0.6)
			s.drone(0.0, 2.2, 65.41, 0.6, 0.35, 1.2, 520.0, 0.03)
			s.drone(0.0, 2.2, 69.3, 0.35, 0.45, 1.2, 480.0, 0.03)
			s.drone(0.0, 2.2, 32.7, 0.4, 0.3, 1.2, 200.0, 0.03)
			s.rumble(0.1, 2.1, 0.25, 110, 0.2, 0.9, 2, 0.5)
			s.lp(1600)
		"card":
			# cartella che scivola sul tavolo e si posa
			s.nb(0.0, 0.13, 0.3, 0.03, 0.06, Syn.BP, 2600, 3800, 0.8)
			s.thump(0.14, 0.15, 0.6, 150, 85, 0.02, 0.001, 0.03)
			s.nb(0.14, 0.04, 0.4, 0.0005, 0.01, Syn.LP, 1300, 500, 0.7)
			s.lp(6000)
		"radio":
			s.nb(0.0, 0.004, 0.5, 0.0001, 0.001, Syn.HP, 2000, 2000, 0.7)
			s.nb(0.004, 0.06, 0.5, 0.002, 0.03, Syn.BP, 1600, 1500, 0.5)
			s.chatter(0.05, 0.12 + v * 0.05, 0.3)
			s.nb(0.2 + v * 0.05, 0.004, 0.4, 0.0001, 0.001, Syn.HP, 2000, 2000, 0.7)
			s.radio_band()
			s.sat(3.0)
		# ---------------------------------------------------------------- armi leggere
		"rifle":
			var n: int = [1, 2, 3, 2, 4][v]
			for i in n:
				var t := 0.0 if i == 0 else s.r(0.05, 0.38)
				s.gunshot(t, {"a": s.r(0.6, 1.0), "crack": s.r(0.4, 0.9), "crack_ms": s.r(0.35, 0.6),
					"blast_f": s.r(3500, 6500), "body_f": s.r(700, 1250), "tf": s.r(130, 210), "thump": s.r(0.25, 0.45),
					"tail_f": s.r(1100, 1800), "tail_tau": s.r(0.12, 0.22), "tail_a": s.r(0.1, 0.16)})
				s.thump(t + 0.002, 0.18, s.r(0.3, 0.45), s.r(105, 135), 55, 0.02, 0.0006, 0.04)
			s.echoes([[s.r(0.09, 0.15), 0.22], [s.r(0.2, 0.32), 0.12]], 2400)
			s.hp(60)
			s.sat(1.3)
		"mg":
			var n2: int = [5, 7, 4, 9][v]
			var it := s.r(0.068, 0.085)
			for i in n2:
				s.gunshot(i * it + s.r(-0.003, 0.003), {"a": s.r(0.85, 1.0), "crack": s.r(0.55, 0.8), "crack_ms": 0.5,
					"blast_f": s.r(3800, 5200), "body_f": 850, "tf": s.r(105, 125), "thump": 0.55, "thump_tau": 0.03,
					"tail_f": 1300, "tail_tau": 0.2, "tail_a": 0.1, "tail": 0.55})
			s.echoes([[s.r(0.1, 0.14), 0.2], [s.r(0.24, 0.3), 0.1]], 2000)
			s.hp(50)
			s.sat(1.4)
		"hmg":
			var n3: int = [4, 6, 8][v]
			for i in n3:
				s.gunshot(i * 0.11 + s.r(-0.004, 0.004), {"a": s.r(0.85, 1.0), "crack": 0.8, "crack_ms": 0.8,
					"blast_f": 3400, "body_f": 650, "tf": s.r(85, 95), "thump": 0.75, "thump_tau": 0.04,
					"tail_f": 1000, "tail_tau": 0.26, "tail_a": 0.13, "tail": 0.7})
			s.echoes([[0.13, 0.22], [0.31, 0.12]], 1500)
			s.hp(35)
			s.sat(1.5)
		"aa":
			var n4: int = [4, 6, 5][v]
			for i in n4:
				var t2 := i * 0.13
				for bb in 2:
					s.gunshot(t2 + bb * 0.062 + s.r(-0.004, 0.004), {"a": s.r(0.85, 1.0), "crack": 1.0, "crack_ms": 0.9,
						"blast_f": 3000, "body_f": 600, "tf": s.r(70, 82), "thump": 0.9, "thump_tau": 0.05,
						"tail_f": 900, "tail_tau": 0.3, "tail_a": 0.16, "tail": 0.9})
			s.echoes([[s.r(0.16, 0.22), 0.25], [s.r(0.4, 0.5), 0.12]], 1100)
			s.hp(30)
			s.sat(1.6)
		"flak":
			var n5: int = [2, 3, 2][v]
			for i in n5:
				var t3 := 0.0 if i == 0 else s.r(0.08, 0.35)
				var a := s.r(0.6, 1.0)
				s.crack(t3, 1.2, a)
				s.nb(t3, 0.2, a * 0.9, 0.0003, 0.03, Syn.LP, 3200, 600, 0.7)
				s.thump(t3, 0.2, a * 0.4, 120, 60, 0.03, 0.001, 0.04)
				s.rumble(t3 + 0.01, 1.2, a * 0.12, 600, 0.02, 0.45, 10, 0.5)
			s.echoes([[s.r(0.25, 0.4), 0.2]], 900)
			s.hp(40)
			s.sat(1.4)
		# ---------------------------------------------------------------- cannoni ed esplosioni
		"cannon":
			s.crack(0.0, s.r(1.0, 1.4), 1.0)
			s.nb(0.001, 0.08, 1.0, 0.0002, 0.012, Syn.LP, 7000, 2500, 0.7)
			s.nb(0.002, 0.6, 0.9, 0.001, 0.09, Syn.LP, s.r(1800, 2600), 140, 0.8)
			s.thump(0.0, 0.8, 1.1, s.r(85, 100), s.r(30, 36), 0.06, 0.002, 0.28)
			s.rumble(0.05, 2.9, 0.4, s.r(170, 240), 0.08, s.r(0.8, 1.1), 6, 0.6)
			s.rumble(0.02, 1.0, 0.14, 1200, 0.02, 0.25, 20, 0.5)
			s.sat(1.6)
			s.echoes([[s.r(0.35, 0.5), 0.3], [s.r(0.8, 1.1), 0.18], [s.r(1.4, 1.8), 0.1]], 700)
			s.hp(25)
		"cannon_far":
			s.nb(0.0, 0.5, 0.7, 0.004, 0.12, Syn.LP, 700, 120, 0.7)
			s.thump(0.0, 1.0, 1.0, s.r(65, 75), s.r(26, 30), 0.08, 0.008, 0.35)
			s.rumble(0.05, 3.5, 0.5, s.r(110, 160), 0.15, 1.2, 4, 0.7)
			s.sat(1.3)
			s.echoes([[s.r(0.5, 0.7), 0.35], [s.r(1.2, 1.5), 0.2], [s.r(1.9, 2.3), 0.12]], 300)
			s.lp(900)
			s.hp(22)
		"explosion":
			s.crack(0.0, s.r(1.5, 2.5), 0.9)
			s.nb(0.0, 0.06, 1.0, 0.0002, 0.01, Syn.LP, 9000, 3000, 0.7)
			s.nb(0.003, 1.0, 1.0, 0.002, s.r(0.18, 0.28), Syn.LP, s.r(2500, 4000), 110, 0.7)
			s.thump(0.0, 1.2, 1.25, s.r(60, 75), s.r(24, 30), 0.08, 0.003, 0.4)
			s.nb(0.0, 0.9, 0.8, 0.003, 0.28, Syn.LP, 220, 90, 0.7)
			s.rumble(0.08, 2.7, 0.38, s.r(140, 200), 0.1, 0.9, 5, 0.6)
			s.sat(1.5)
			s.debris(0.12, 1.9, int(s.r(40, 70)), 0.35)
			s.echoes([[s.r(0.3, 0.5), 0.22], [s.r(0.9, 1.2), 0.12]], 600)
			s.hp(22)
		"explosion_far":
			s.nb(0.0, 0.7, 0.8, 0.005, 0.2, Syn.LP, 900, 100, 0.7)
			s.thump(0.0, 1.2, 1.0, s.r(52, 60), s.r(23, 27), 0.1, 0.008, 0.45)
			s.rumble(0.05, 3.5, 0.55, s.r(100, 150), 0.15, 1.3, 4, 0.7)
			s.sat(1.3)
			s.echoes([[s.r(0.5, 0.8), 0.3], [s.r(1.3, 1.7), 0.16]], 300)
			s.lp(1000)
			s.hp(20)
		"arty_impact":
			s.crack(0.0, s.r(2.0, 3.0), 1.0)
			s.nb(0.0, 0.08, 1.0, 0.0002, 0.012, Syn.LP, 9000, 3000, 0.7)
			s.nb(0.003, 1.3, 1.0, 0.002, s.r(0.3, 0.38), Syn.LP, s.r(2500, 3500), 90, 0.7)
			s.nb(0.0, 0.5, 0.8, 0.003, 0.15, Syn.LP, 320, 160, 0.7)
			s.thump(0.0, 1.6, 1.3, s.r(50, 58), s.r(19, 23), 0.1, 0.003, 0.55)
			s.nb(0.0, 1.0, 0.7, 0.004, 0.32, Syn.LP, 200, 80, 0.7)
			s.rumble(0.08, 3.3, 0.42, s.r(110, 160), 0.12, 1.3, 4, 0.6)
			s.sat(1.7)
			s.debris(0.1, 2.6, int(s.r(80, 110)), 0.4)
			s.echoes([[s.r(0.4, 0.6), 0.25], [s.r(1.1, 1.4), 0.14], [s.r(1.9, 2.3), 0.08]], 500)
			s.hp(20)
		"expl_small":
			s.crack(0.0, 1.0, 0.8)
			s.nb(0.0, 0.4, 1.0, 0.0005, 0.08, Syn.LP, 6000, 400, 0.7)
			s.thump(0.0, 0.5, 0.7, s.r(100, 120), s.r(42, 50), 0.04, 0.002, 0.12)
			s.rumble(0.04, 1.5, 0.2, 260, 0.05, 0.5, 8, 0.5)
			s.sat(1.5)
			s.debris(0.06, 0.9, 15, 0.2)
			s.echoes([[s.r(0.2, 0.35), 0.2]], 900)
			s.hp(30)
		"hit_armor":
			s.crack(0.0, 1.0, 0.9)
			var fb := s.r(300, 420)
			s.metal(0.0, [fb, fb * 2.76 * s.r(0.97, 1.03), fb * 5.4 * s.r(0.97, 1.03), fb * 8.93 * s.r(0.97, 1.03)],
				[0.5, 0.35, 0.25, 0.15], [0.35, 0.2, 0.12, 0.08])
			s.nb(0.0, 0.25, 0.8, 0.0003, 0.05, Syn.LP, 5000, 500, 0.7)
			s.thump(0.0, 0.4, 0.6, 120, 50, 0.04, 0.002, 0.1)
			s.rumble(0.03, 1.2, 0.18, 300, 0.05, 0.45, 8, 0.5)
			s.sat(1.4)
			s.debris(0.02, 0.5, 10, 0.2)
			s.echoes([[s.r(0.22, 0.35), 0.2]], 1000)
			s.hp(30)
		"rocket":
			s.crack(0.0, 0.6, 0.5)
			s.nb(0.0, 0.15, 1.0, 0.0003, 0.03, Syn.LP, 6000, 800, 0.7)
			s.thump(0.0, 0.2, 0.6, 140, 60, 0.03, 0.001, 0.05)
			s.nb(0.02, 1.7, 0.6, 0.015, 0.55, Syn.BP, s.r(2800, 3600), s.r(700, 1000), 0.8)
			s.nb(0.02, 1.4, 0.35, 0.01, 0.35, Syn.LP, 1500, 300, 0.7)
			s.flutter(0.02, 1.6, 0.35, 0.5)
			s.echoes([[s.r(0.2, 0.3), 0.18]], 1500)
			s.hp(40)
			s.sat(1.3)
		"smoke_pop":
			var n6: int = [4, 6][v]
			for i in n6:
				var t4 := i * s.r(0.07, 0.1)
				s.thump(t4, 0.1, 0.7, 220, 100, 0.02, 0.0005, 0.02)
				s.nb(t4, 0.05, 0.6, 0.0003, 0.012, Syn.LP, 1500, 800, 0.7)
				s.crack(t4, 0.3, 0.2)
			s.nb(0.4, 1.25, 0.25, 0.1, 0.5, Syn.BP, 4000, 3000, 0.7)
			s.echoes([[0.15, 0.2]], 1500)
			s.hp(50)
		"cookoff":
			var n7 := int(s.r(12, 20))
			for i in n7:
				var t5 := s.r(0.0, 2.3)
				var a2 := s.r(0.25, 1.0)
				s.crack(t5, 0.5, a2 * 0.5)
				s.nb(t5, 0.08, a2, 0.0003, 0.02, Syn.LP, 3000, 800, 0.7)
				s.thump(t5, 0.12, a2 * 0.5, 90, 50, 0.02, 0.001, 0.05)
			s.debris(0.0, 2.6, 60, 0.12)
			s.rumble(0.0, 2.7, 0.08, 400, 0.2, 2.0, 10, 0.6)
			s.echoes([[0.25, 0.18]], 900)
			s.hp(40)
		"whistle":
			s.whistle(0.0, 2.0, s.r(1700, 2100), s.r(580, 780), 0.6)
		"jet_flyby":
			s.flyby(s.r(2.4, 2.8), s.r(200, 240), s.r(55, 80), s.r(2100, 2600))
		# ---------------------------------------------------------------- loop
		"engine_heavy":
			# diesel: 36 scoppi/s (108 in 3 s, periodo esatto), irregolarità e basso di scarico
			s.rumble(0.0, 3.6, 0.35, 90, 0.0, 100.0, 4, 0.4)
			s.nb(0.0, 3.6, 0.07, 0.0, 100.0, Syn.BP, 1800, 1800, 1.0)
			s.sines(0.0, 3.6, [1300.0, 2600.0], [0.02, 0.008])
			s.loopify_to(3.0)
			var per := 1.0 / 36.0
			for i in 108:
				var aa2 := s.r(0.75, 1.0) * (1.0 if i % 2 == 0 else 0.82)
				var tt := i * per + s.r(-0.0012, 0.0012)
				s.thump(maxf(0.0, tt), 0.07, aa2, s.r(70, 76), 52, 0.02, 0.0015, 0.02)
				s.nb(maxf(0.0, tt), 0.03, aa2 * 0.45, 0.0005, 0.006, Syn.LP, 900, 500, 0.7)
			s.fold(3.0)
			s.lp(1400)
			s.sat(1.4)
		"engine_light":
			s.nb(0.0, 2.6, 0.12, 0.0, 100.0, Syn.BP, 2600, 2600, 1.2)
			s.sines(0.0, 2.6, [700.0, 1400.0], [0.04, 0.012])
			s.loopify_to(2.0)
			var per2 := 1.0 / 60.0
			for i in 120:
				var aa3 := s.r(0.8, 1.0)
				var tt2 := maxf(0.0, i * per2 + s.r(-0.0008, 0.0008))
				s.thump(tt2, 0.04, aa3, s.r(128, 136), 100, 0.01, 0.001, 0.011)
				s.nb(tt2, 0.02, aa3 * 0.5, 0.0003, 0.004, Syn.LP, 2200, 1500, 0.7)
			s.fold(2.0)
			s.lp(2600)
			s.sat(1.3)
		"tracks":
			# cingoli: 12 colpi di maglia al secondo, rinvio ogni 4, stridio metallico periodico
			s.squeal(0.0, 2.6, 0.12)
			s.rumble(0.0, 2.6, 0.35, 350, 0.0, 100.0, 12, 0.5)
			s.loopify_to(2.0)
			for i in 24:
				var tt3 := maxf(0.0, i / 12.0 + s.r(-0.008, 0.008))
				var fb2 := s.r(600, 1100)
				var ac := s.r(0.5, 1.0)
				s.metal(tt3, [fb2, fb2 * 2.3, fb2 * 3.9], [0.5 * ac, 0.3 * ac, 0.2 * ac], [0.025, 0.015, 0.01])
				s.nb(tt3, 0.01, 0.4 * ac, 0.0001, 0.003, Syn.BP, 3000, 3000, 1.0)
				if i % 4 == 0:
					s.thump(tt3, 0.06, 0.5, 160, 90, 0.015, 0.001, 0.03)
			s.fold(2.0)
			s.hp(60)
		"tires":
			s.rumble(0.0, 2.6, 0.6, 600, 0.0, 100.0, 3, 0.3)
			s.rumble(0.0, 2.6, 0.4, 160, 0.0, 100.0, 2, 0.3)
			for i in 30:
				s.nb(s.r(0.0, 2.5), 0.006, s.r(0.1, 0.3), 0.0002, 0.002, Syn.BP, s.r(1500, 4000), 2000, 1.5)
			s.hp(40)
		"heli":
			# rotore principale: 20 battute di pala al secondo, turbina, rotore di coda, flusso d'aria
			s.sines(0.0, 2.6, [3150.0, 6300.0, 100.0, 200.0, 300.0], [0.025, 0.01, 0.06, 0.04, 0.025])
			s.rumble(0.0, 2.6, 0.18, 1800, 0.0, 100.0, 3, 0.4)
			s.loopify_to(2.0)
			for i in 40:
				var am := 0.9 + 0.1 * sin(TAU * i / 40.0) + (0.06 if i % 4 == 0 else 0.0)
				s.nb(i / 20.0, 0.05, am, 0.0008, 0.012, Syn.BP, 500, 300, 0.9)
				s.thump(i / 20.0, 0.06, am * 0.5, 90, 60, 0.02, 0.001, 0.02)
			s.fold(2.0)
			s.lp(5000)
		"drone":
			# motore a due tempi con elica spingente: armoniche di 95 Hz con leggera modulazione periodica
			var fr: Array = []
			var am2: Array = []
			for h in 8:
				fr.append(95.0 * (h + 1))
				am2.append(0.5 / (h + 1))
			s.sines(0.0, 2.6, fr, am2, 0.5, 1.5)
			s.rumble(0.0, 2.6, 0.12, 2500, 0.0, 100.0, 6, 0.5)
			s.lp(3000)
			s.sat(2.0)
		"jet_loop":
			s.rumble(0.0, 3.6, 0.6, 1400, 0.0, 100.0, 2, 0.25)
			s.rumble(0.0, 3.6, 0.5, 280, 0.0, 100.0, 1.5, 0.25)
			s.sines(0.0, 3.6, [2000.0, 4000.0], [0.04, 0.015], 1.0 / 3.0, 0.4)
		"amb_wind":
			s.wind(0.0, 9.0, 0.6, 8.0)
			s.hp(30)
		"amb_battle":
			s.rumble(0.0, 11.0, 0.45, 90, 0.0, 100.0, 0.5, 0.6)
			s.loopify_to(10.0)
			var nb2 := int(s.r(6, 9))
			for i in nb2:
				var tb := s.r(0.0, 9.8)
				var ab := s.r(0.3, 0.8)
				s.nb(tb, 1.0, ab, 0.01, 0.3, Syn.LP, 400, 90, 0.7)
				s.thump(tb, 1.0, ab, 50, 28, 0.1, 0.01, 0.4)
				s.rumble(tb, 2.5, ab * 0.4, 110, 0.1, 1.2, 3, 0.6)
			s.fold(10.0)
			s.lp(700)
		# ---------------------------------------------------------------- ambiente (Fase 8)
		"amb_rain":
			# sibilo largo della pioggia battente + corpo basso + centinaia di gocce singole
			s.nb(0.0, 8.6, 0.5, 0.3, 100.0, Syn.BP, 2600, 2600, 0.6)
			s.nb(0.0, 8.6, 0.32, 0.3, 100.0, Syn.LP, 650, 650, 0.7)
			s.loopify_to(8.0)
			for i in 300:
				var tr := s.r(0.0, 7.95)
				var fr2 := s.r(1800, 6500)
				s.nb(tr, 0.018, s.r(0.15, 0.55), 0.0004, 0.004, Syn.BP, fr2, fr2, 2.0)
			s.fold(8.0)
			s.hp(220)
			s.lp(7500)
		"amb_crickets":
			# due grilli (trilli di 4 impulsi a ~4 kHz e ~3,6 kHz con periodi diversi) su un soffio notturno leggerissimo
			s.rumble(0.0, 8.6, 0.07, 320, 0.0, 100.0, 1, 0.3)
			s.loopify_to(8.0)
			for c in 2:
				var fc2 := 4150.0 if c == 0 else 3620.0
				var per3 := 0.5 if c == 0 else 0.73
				var tc2 := 0.3 * c
				while tc2 < 7.9:
					var ac2 := (0.35 if c == 0 else 0.24) * s.r(0.8, 1.0)
					for kk in 4:
						s.tone(tc2 + kk * 0.027, 0.016, fc2 * s.r(0.995, 1.005), ac2, 1)
					tc2 += per3 * s.r(0.97, 1.03)
			s.fold(8.0)
			s.hp(250)
		"amb_birds":
			# canti di uccelli al mattino: brevi fischi con glissando, in gruppetti, su aria calma
			s.rumble(0.0, 10.6, 0.06, 420, 0.0, 100.0, 0.7, 0.3)
			s.loopify_to(10.0)
			for i in 14:
				var tb2 := s.r(0.0, 9.6)
				var fb3 := s.r(1900, 4200)
				var nb3 := int(s.r(1, 5))
				for kb in nb3:
					s.whistle(tb2 + kb * 0.09, 0.07, fb3 * s.r(0.9, 1.1), fb3 * s.r(0.8, 1.3), s.r(0.2, 0.5))
			s.fold(10.0)
			s.hp(600)
		"amb_surf":
			# risacca: fondo basso continuo e due onde che si rompono (ogni 5 s: il loop di 10 s resta periodico)
			s.nb(0.0, 10.6, 0.22, 0.5, 100.0, Syn.LP, 900, 900, 0.7)
			s.loopify_to(10.0)
			for kw in 2:
				var tw := kw * 5.0 + s.r(-0.3, 0.3)
				s.nb(maxf(0.0, tw), 3.2, 0.9, 1.4, 0.7, Syn.LP, 1400, 500, 0.7)
				s.nb(maxf(0.0, tw) + 0.8, 2.0, 0.5, 0.3, 0.6, Syn.BP, 2500, 1200, 0.8)
			s.fold(10.0)
			s.lp(3500)
			s.hp(60)
		"amb_fire":
			# incendio: rombo caldo, soffio e scoppiettii secchi
			s.rumble(0.0, 6.6, 0.45, 140, 0.0, 100.0, 4, 0.6)
			s.nb(0.0, 6.6, 0.16, 0.0, 100.0, Syn.BP, 1800, 1800, 0.5)
			s.loopify_to(6.0)
			for i in 70:
				var tf := s.r(0.0, 5.9)
				var ff := s.r(2000, 5500)
				s.nb(tf, 0.015, s.r(0.3, 1.0), 0.0003, 0.003, Syn.BP, ff, ff, 1.5)
				if i % 6 == 0:
					s.thump(tf, 0.08, 0.4, 180, 90, 0.02, 0.002, 0.03)
			s.fold(6.0)
			s.lp(6500)
			s.hp(70)
		"amb_thunder":
			# tuono: rombo lungo che rotola, corpo basso; la variante 1 è un fulmine vicino (schiocco iniziale)
			var d0 := s.r(0.0, 0.25)
			s.rumble(d0, 4.6, 1.0, 55, 0.25 if v != 1 else 0.02, 1.4, 2.5, 0.7)
			s.rumble(d0 + 0.3, 3.5, 0.6, 120, 0.4, 1.0, 4, 0.6)
			s.thump(d0, 1.6, 0.7, 60, 28, 0.3, 0.05, 0.5)
			if v == 1:
				s.crack(d0, 25, 0.6)
				s.nb(d0, 0.4, 0.7, 0.004, 0.12, Syn.LP, 2500, 400, 0.7)
			s.lp(900 if v != 1 else 2200)
			s.sat(1.3)
		"amb_crackle":
			var tc := 0.0
			while tc < 7.9:
				var burst := 1 if s.r(0.0, 1.0) < 0.7 else int(s.r(4, 9))
				var ab2 := s.r(0.2, 1.0)
				var ib := s.r(0.07, 0.09)
				for j in burst:
					var tj := tc + j * ib
					s.nb(tj, 0.03, ab2, 0.0003, 0.004, Syn.LP, 2500, 1200, 0.7)
					s.nb(tj + 0.004, 0.3, ab2 * 0.3, 0.01, 0.08, Syn.LP, 700, 400, 0.7)
				tc += s.r(0.03, 0.3) + burst * ib
			s.fold(8.0)
			s.lp(2400)
			s.hp(80)

# =================================================================================================== DSP
## Sintetizzatore a blocchi: ogni funzione scrive (somma) in `b` su un tratto, in un unico ciclo stretto.
class Syn extends RefCounted:
	const LP := 0
	const HP := 1
	const BP := 2
	var sr := 32000
	var loop := false
	var b := PackedFloat32Array()
	var seed_ := 1
	var rng := RandomNumberGenerator.new()

	func _init(rate: int, dur: float, sd: int) -> void:
		sr = rate
		b.resize(int(dur * rate) + 1)
		seed_ = (sd * 2654435761) & 0xFFFFFFFF
		if seed_ == 0:
			seed_ = 1
		rng.seed = sd

	func r(a: float, c: float) -> float:
		return rng.randf_range(a, c)

	## estende il buffer se un evento supera la fine (i loop vengono poi ripiegati o incrociati)
	func _need(n: int) -> void:
		if n > b.size():
			b.resize(n)

	static func _coef(type: int, f: float, q: float, rate: int) -> PackedFloat32Array:
		f = clampf(f, 10.0, rate * 0.45)
		var w0 := TAU * f / rate
		var cw := cos(w0)
		var al := sin(w0) / (2.0 * maxf(0.1, q))
		var a0 := 1.0 + al
		var b0: float; var b1: float; var b2: float
		match type:
			LP:
				b0 = (1.0 - cw) * 0.5; b1 = 1.0 - cw; b2 = b0
			HP:
				b0 = (1.0 + cw) * 0.5; b1 = -(1.0 + cw); b2 = b0
			_:
				b0 = al; b1 = 0.0; b2 = -al
		return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, -2.0 * cw / a0, (1.0 - al) / a0])

	## rumore bianco filtrato (biquad, frequenza in rampa esponenziale f0→f1), attacco lineare, decadimento esponenziale
	func nb(t0: float, dur: float, amp: float, att: float, tau: float, type: int, f0: float, f1: float, q: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var fm := sqrt(f0 * f1)
		var comp := 1.0
		if type == LP:
			comp = sqrt(sr / (2.0 * fm))
		elif type == BP:
			comp = sqrt(q * sr / (2.0 * fm))
		comp = minf(comp, 25.0)
		var na := maxi(1, int(att * sr))
		var kd := exp(-1.0 / maxf(1.0, tau * sr))
		var nf := mini(n, int(0.008 * sr))
		var c := _coef(type, f0, q, sr)
		var b0 := c[0]; var b1 := c[1]; var b2 := c[2]; var a1 := c[3]; var a2 := c[4]
		var sweep := absf(f1 - f0) > 1.0
		var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
		var e := 1.0
		var ls := seed_
		var g0 := amp * comp
		for j in n:
			if sweep and j % 32 == 0:
				c = _coef(type, f0 * pow(f1 / f0, float(j) / n), q, sr)
				b0 = c[0]; b1 = c[1]; b2 = c[2]; a1 = c[3]; a2 = c[4]
			ls = (ls * 1664525 + 1013904223) & 0xFFFFFFFF
			var x := float(ls) * 4.656612873e-10 - 1.0
			var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
			x2 = x1; x1 = x; y2 = y1; y1 = y
			var g := e
			if j < na:
				g = float(j) / na
			else:
				e *= kd
			if j > n - nf:
				g *= float(n - j) / nf
			b[i0 + j] += y * g * g0
		seed_ = ls

	## onda a N supersonica (lo "schiocco" del proiettile/della volata)
	func crack(t0: float, ms: float, amp: float) -> void:
		var i0 := int(t0 * sr)
		var n := maxi(3, int(ms * 0.001 * sr))
		_need(i0 + n + 4)
		for j in n:
			b[i0 + j] += amp * (1.0 - 2.0 * float(j) / (n - 1))
		b[i0 + n] += amp * 0.3
		b[i0 + n + 1] += amp * 0.1

	## sinusoide con caduta di frequenza f0→f1 (costante ts), attacco e decadimento esponenziale: il "corpo" del colpo
	func thump(t0: float, dur: float, amp: float, f0: float, f1: float, ts: float, att: float, tau: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var kd := exp(-1.0 / maxf(1.0, tau * sr))
		var kf := exp(-1.0 / maxf(1.0, ts * sr))
		var na := maxi(1, int(att * sr))
		var nf := mini(n, int(0.01 * sr))
		var df := f0 - f1
		var ph := 0.0
		var e := 1.0
		var inv := TAU / sr
		for j in n:
			ph += (f1 + df) * inv
			df *= kf
			var g := e
			if j < na:
				g = float(j) / na
			else:
				e *= kd
			if j > n - nf:
				g *= float(n - j) / nf
			b[i0 + j] += sin(ph) * g * amp

	## rombo: rumore passa-basso a due poli con modulazione d'ampiezza lenta e casuale (rotolamento dell'eco)
	func rumble(t0: float, dur: float, amp: float, fc: float, att: float, tau: float, mod_hz: float, depth: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var a := 1.0 - exp(-TAU * fc / sr)
		var comp := 1.4 / sqrt(PI * fc / sr)
		var kd := exp(-1.0 / maxf(1.0, tau * sr))
		var na := maxi(1, int(att * sr))
		var nf := mini(n, int(0.02 * sr))
		var mstep := maxi(16, int(sr / maxf(0.1, mod_hz)))
		var m := 0.0; var mt := 0.0; var md := 0.0
		var y1 := 0.0; var y2 := 0.0
		var e := 1.0
		var ls := seed_
		for j in n:
			if j % mstep == 0:
				mt = rng.randf_range(-1.0, 1.0)
				md = (mt - m) / mstep
			m += md
			ls = (ls * 1664525 + 1013904223) & 0xFFFFFFFF
			var x := float(ls) * 4.656612873e-10 - 1.0
			y1 += a * (x - y1)
			y2 += a * (y1 - y2)
			var g := e
			if j < na:
				g = float(j) / na
			else:
				e *= kd
			if j > n - nf:
				g *= float(n - j) / nf
			b[i0 + j] += y2 * comp * g * amp * (1.0 + depth * m)
		seed_ = ls

	## parziali inarmoniche smorzate (metallo, molle, scatti)
	func metal(t0: float, freqs: Array, amps: Array, taus: Array) -> void:
		var i0 := int(t0 * sr)
		for k in freqs.size():
			var tau: float = taus[k]
			var n := int(minf(tau * 7.0, 2.0) * sr)
			_need(i0 + n)
			var w := TAU * float(freqs[k]) / sr
			var cw := cos(w); var sw := sin(w)
			var re := 1.0; var im := 0.0
			var kd := exp(-1.0 / maxf(1.0, tau * sr))
			var e: float = amps[k]
			for j in n:
				var nr := re * cw - im * sw
				im = re * sw + im * cw
				re = nr
				b[i0 + j] += im * e
				e *= kd

	## somma di sinusoidi stazionarie (frequenze multiple di 0,5 Hz => periodiche su loop di 2 s); vibrato opzionale in %
	func sines(t0: float, dur: float, freqs: Array, amps: Array, vib_hz := 0.0, vib_amt := 0.0) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		for k in freqs.size():
			var f: float = freqs[k]
			var a: float = amps[k]
			var ph := 0.0
			var vp := 0.0
			for j in n:
				var fi := f
				if vib_hz > 0.0:
					vp += TAU * vib_hz / sr
					fi = f * (1.0 + vib_amt * 0.01 * sin(vp))
				ph += TAU * fi / sr
				b[i0 + j] += sin(ph) * a

	## tono "consolle": somma di armoniche dispari (onda quasi quadra), attacco e rilascio brevi
	func tone(t0: float, dur: float, f: float, amp: float, harm: int) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var na := maxi(1, int(0.003 * sr))
		var nr := maxi(1, int(0.012 * sr))
		var ph := 0.0
		var w := TAU * f / sr
		for j in n:
			ph += w
			var v := 0.0
			for h in harm:
				var m := 2 * h + 1
				v += sin(ph * m) / m
			var g := 1.0
			if j < na:
				g = float(j) / na
			elif j > n - nr:
				g = float(n - j) / nr
			b[i0 + j] += v * g * amp

	## ottone: dente di sega con filtro che si apre con l'inviluppo, vibrato ritardato
	func brass(t0: float, dur: float, f: float, amp: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var na := int(0.05 * sr)
		var nr := int(minf(0.2, dur * 0.4) * sr)
		var ph := 0.0
		var y := 0.0; var y2 := 0.0
		for j in n:
			var t := float(j) / sr
			var vib := 1.0 + (0.006 * sin(TAU * 5.2 * t) if t > 0.18 else 0.0)
			ph += f * vib / sr
			ph -= floorf(ph)
			var saw := 2.0 * ph - 1.0
			var env := 1.0
			if j < na:
				env = float(j) / na
			elif j > n - nr:
				env = float(n - j) / nr
			else:
				env = 0.85 + 0.15 * exp(-(t - 0.05) * 6.0)
			var fc := 250.0 + 2600.0 * env * env
			var a := minf(0.9, TAU * fc / sr)
			y += a * (saw - y)
			y2 += a * (y - y2)
			b[i0 + j] += y2 * env * amp

	## pila di tre denti di sega stonati (±0,6 %) dentro un passa-basso a due poli che si apre con l'inviluppo:
	## braam / ottone grave / sirena smorzata. bend = calo d'intonazione relativo lungo la nota.
	func drone(t0: float, dur: float, f: float, amp: float, att: float, rel: float, fc: float, bend := 0.0) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var na := maxi(1, int(att * sr))
		var nr := maxi(1, int(rel * sr))
		var p1 := 0.0; var p2 := 0.31; var p3 := 0.67
		var y := 0.0; var y2 := 0.0
		var a := 0.1
		for j in n:
			var x := float(j) / n
			var env := 1.0
			if j < na:
				var q := float(j) / na
				env = q * q * (3.0 - 2.0 * q)
			elif j > n - nr:
				var q2 := float(n - j) / nr
				env = q2 * q2
			if j % 16 == 0:
				a = 1.0 - exp(-TAU * fc * (0.35 + 0.65 * env) / sr)
			var fi := f * (1.0 - bend * x) / sr
			p1 += fi * 0.994; p2 += fi; p3 += fi * 1.006
			p1 -= floorf(p1); p2 -= floorf(p2); p3 -= floorf(p3)
			var saw := (2.0 * p1 - 1.0) + (2.0 * p2 - 1.0) + (2.0 * p3 - 1.0)
			y += a * (saw - y)
			y2 += a * (y - y2)
			b[i0 + j] += y2 * env * amp * 0.4

	## voce radio incomprensibile: sillabe di rumore filtrato su formanti (450-1500 Hz) a ritmo di parlato
	func chatter(t0: float, dur: float, amp: float) -> void:
		var t := t0
		while t < t0 + dur - 0.03:
			var d := rng.randf_range(0.035, 0.085)
			var f1 := rng.randf_range(450.0, 800.0)
			var f2 := rng.randf_range(1000.0, 1600.0)
			var a := amp * rng.randf_range(0.5, 1.0)
			nb(t, d, a, d * 0.3, d * 0.6, BP, f1, f1 * 0.9, 4.0)
			nb(t, d, a * 0.6, d * 0.3, d * 0.5, BP, f2, f2 * 1.05, 5.0)
			t += d + rng.randf_range(0.004, 0.03)

	## detriti: granelli brevi a banda (ghiaia, schegge) e qualche tonfo, sempre più radi
	func debris(t0: float, span: float, count: int, amp: float) -> void:
		for i in count:
			var t := t0 + minf(span, -log(maxf(1e-4, rng.randf())) * span * 0.3)
			var fade := exp(-(t - t0) / (span * 0.5))
			if rng.randf() < 0.18:
				nb(t, 0.05, amp * 0.6 * fade, 0.001, 0.012, LP, 450, 200, 0.7)
			else:
				var d := rng.randf_range(0.002, 0.012)
				nb(t, d, amp * fade * rng.randf_range(0.3, 1.0), 0.0003, d * 0.35, BP, rng.randf_range(1500, 6000),
					rng.randf_range(1500, 6000), rng.randf_range(1.5, 4.0))

	## colpo d'arma da fuoco: schiocco, vampa, corpo, coda d'ambiente
	func gunshot(t0: float, p: Dictionary) -> void:
		var a: float = p.get("a", 1.0)
		crack(t0, p.get("crack_ms", 0.5), a * float(p.get("crack", 0.6)))
		var tb := t0 + float(p.get("gap", 0.0015))
		var bf: float = p.get("blast_f", 4500.0)
		nb(tb, 0.05, a * 0.9, 0.0002, p.get("blast_tau", 0.006), LP, bf, bf * 0.4, 0.8)
		nb(tb, 0.12, a * 0.5, 0.0005, p.get("body_tau", 0.02), LP, p.get("body_f", 900.0), 200.0, 0.7)
		var tf: float = p.get("tf", 160.0)
		thump(tb, 0.14, a * float(p.get("thump", 0.4)), tf, tf * 0.45, 0.02, 0.0005, p.get("thump_tau", 0.025))
		rumble(tb + 0.01, p.get("tail", 0.6), a * float(p.get("tail_a", 0.12)), p.get("tail_f", 1400.0), 0.015,
			p.get("tail_tau", 0.18), 18.0, 0.5)

	## fruscio irregolare del motore a razzo
	func flutter(t0: float, dur: float, amp: float, tau: float) -> void:
		rumble(t0, dur, amp, 2200, 0.01, tau, 40.0, 0.9)

	## fischio del proiettile in arrivo: frequenza discendente, ampiezza crescente, battimento d'aria
	func whistle(t0: float, dur: float, f0: float, f1: float, amp: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr) - 1
		_need(i0 + n)
		var ph := 0.0
		var nf := int(0.015 * sr)
		for j in n:
			var x := float(j) / n
			var f := f0 * pow(f1 / f0, x)
			ph += TAU * f / sr
			var g := pow(x, 1.6) * (1.0 + 0.15 * sin(TAU * 28.0 * x * dur))
			if j > n - nf:
				g *= float(n - j) / nf
			b[i0 + j] += (sin(ph) + 0.15 * sin(2.0 * ph)) * g * amp
		nb(t0, dur, amp * 0.25, dur * 0.9, 10.0, BP, f0, f1, 6.0)

	## passaggio di un caccia: ruggito filtrato dalla distanza, sibilo con effetto Doppler
	func flyby(tc: float, v: float, h: float, f0: float) -> void:
		var n := b.size()
		var c := 340.0
		var ls := seed_
		var y1 := 0.0; var y2 := 0.0; var z1 := 0.0
		var ph := 0.0; var ph2 := 0.0
		var a := 0.5
		var nfi := int(0.4 * sr)
		for j in n:
			var t := float(j) / sr
			if j % 64 == 0:
				var x := v * (t - tc)
				var rr := sqrt(x * x + h * h)
				var vr := v * x / rr
				var fd := c / (c + vr)
				var fc := clampf(9000.0 * h / rr, 250.0, 9000.0)
				a = 1.0 - exp(-TAU * fc / sr)
				ph2 = fd   # fattore Doppler corrente
				z1 = h / rr * (1.4 if x > 0.0 else 1.0)   # i jet sono più forti da dietro
			ls = (ls * 1664525 + 1013904223) & 0xFFFFFFFF
			var nz := float(ls) * 4.656612873e-10 - 1.0
			y1 += a * (nz - y1)
			y2 += 0.02 * (nz - y2)
			ph += TAU * f0 * ph2 / sr
			var g := z1
			if j < nfi:
				g *= float(j) / nfi
			elif j > n - nfi:
				g *= float(n - j) / nfi
			b[j] += (y1 * 2.5 + y2 * 6.0 + sin(ph) * 0.12 + sin(ph * 0.5) * 0.06) * g
		seed_ = ls

	## vento: rumore con taglio e livello modulati periodicamente (raffiche) e un leggero sibilo
	func wind(t0: float, dur: float, amp: float, period: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var ls := seed_
		var y1 := 0.0; var y2 := 0.0
		var a := 0.05
		var g := 1.0
		var x1 := 0.0; var x2 := 0.0; var w1 := 0.0; var w2 := 0.0
		var c := PackedFloat32Array([0, 0, 0, 0, 0])
		for j in n:
			var t := float(j) / sr
			if j % 64 == 0:
				var ph := TAU * t / period
				var fc := 420.0 + 260.0 * sin(ph) + 140.0 * sin(3.0 * ph + 1.3) + 60.0 * sin(7.0 * ph + 0.4)
				a = 1.0 - exp(-TAU * fc / sr)
				g = 0.55 + 0.3 * sin(2.0 * ph + 1.0) + 0.15 * sin(5.0 * ph + 2.1)
				c = _coef(BP, 650.0 + 200.0 * sin(2.0 * ph + 0.5), 9.0, sr)
			ls = (ls * 1664525 + 1013904223) & 0xFFFFFFFF
			var x := float(ls) * 4.656612873e-10 - 1.0
			y1 += a * (x - y1)
			y2 += a * (y1 - y2)
			var w := c[0] * x + c[1] * x1 + c[2] * x2 - c[3] * w1 - c[4] * w2
			x2 = x1; x1 = x; w2 = w1; w1 = w
			b[i0 + j] += (y2 * 5.0 + w * 1.2 * g) * g * amp
		seed_ = ls

	## stridio dei cingoli: tono acuto con glissando lento e raffiche periodiche
	func squeal(t0: float, dur: float, amp: float) -> void:
		var i0 := int(t0 * sr)
		var n := int(dur * sr)
		_need(i0 + n)
		var ph := 0.0
		for j in n:
			var t := float(j) / sr
			var f := 2500.0 + 220.0 * sin(TAU * 0.5 * t) + 90.0 * sin(TAU * 3.5 * t)
			ph += TAU * f / sr
			var gate := pow(maxf(0.0, sin(TAU * 1.5 * t)), 6.0)
			b[i0 + j] += (sin(ph) + 0.3 * sin(2.0 * ph)) * gate * amp

	## filtro "radio" (passa-alto 350 Hz + passa-basso 3,2 kHz)
	func radio_band() -> void:
		hp(350)
		lp(3200)
		lp(3200)

	func lp(fc: float) -> void:
		var a := 1.0 - exp(-TAU * fc / sr)
		var y := 0.0
		if loop:   # stato iniziale dalla coda: nessuna giunta nel loop
			for i in range(maxi(0, b.size() - sr / 10), b.size()):
				y += a * (b[i] - y)
		for i in b.size():
			y += a * (b[i] - y)
			b[i] = y

	func hp(fc: float) -> void:
		var a := exp(-TAU * fc / sr)
		var y := 0.0
		var xp := 0.0
		if loop:
			for i in range(maxi(0, b.size() - sr / 10), b.size()):
				y = a * (y + b[i] - xp)
				xp = b[i]
		for i in b.size():
			var x := b[i]
			y = a * (y + x - xp)
			xp = x
			b[i] = y

	## saturazione morbida (dà corpo e limita i picchi)
	func sat(drive: float) -> void:
		var pk := 0.0
		for i in b.size():
			pk = maxf(pk, absf(b[i]))
		if pk <= 1e-9:
			return
		var k := drive / pk
		var nrm := 1.0 / tanh(drive)
		for i in b.size():
			b[i] = tanh(b[i] * k) * nrm * pk

	## eco discrete: copie ritardate e scurite del suono (riflessioni di colline, boschi, edifici)
	func echoes(taps: Array, lp_hz: float) -> void:
		var src := b.duplicate()
		var a := 1.0 - exp(-TAU * lp_hz / sr)
		var y := 0.0; var y2 := 0.0
		for i in src.size():
			y += a * (src[i] - y)
			y2 += a * (y - y2)
			src[i] = y2
		for tp in taps:
			var d := int(float(tp[0]) * sr)
			var g: float = tp[1]
			var n := b.size()
			for i in range(d, n):
				b[i] += src[i - d] * g

	## ripiega sull'inizio ciò che supera `dur` (eventi periodici => loop perfetto)
	func fold(dur: float) -> void:
		var n := int(dur * sr)
		var tot := b.size()
		if tot <= n:
			b.resize(n)
			return
		for i in range(n, tot):
			b[(i - n) % n] += b[i]
		b.resize(n)

	## loop senza giunte: la coda oltre `dur` sfuma incrociata sull'inizio
	func loopify_to(dur: float) -> void:
		var n := int(dur * sr)
		var tot := b.size()
		if tot <= n:
			return
		var xf := mini(tot - n, n)
		for i in xf:
			var w := float(i) / xf
			b[i] = b[i] * sqrt(w) + b[n + i] * sqrt(1.0 - w)
		b.resize(n)

	## pulizia finale: niente NaN, niente continua, normalizzazione del picco
	func finish(peak: float) -> void:
		var pk := 0.0
		var mean := 0.0
		for i in b.size():
			var v := b[i]
			if is_nan(v) or is_inf(v):
				b[i] = 0.0
				v = 0.0
			mean += v
		mean /= maxf(1.0, b.size())
		for i in b.size():
			b[i] -= mean
			pk = maxf(pk, absf(b[i]))
		if pk > 1e-9:
			var k := peak / pk
			for i in b.size():
				b[i] *= k
		# micro-sfumatura finale (evita il clic all'ultimo campione) solo per i suoni non in loop
		var n := b.size()
		if not loop and n > 64 and absf(b[n - 1]) > 0.002:
			var m := mini(n, 64)
			for i in m:
				b[n - m + i] *= float(m - i) / m
