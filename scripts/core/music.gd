extends Node
## Autoload "Music": colonna sonora cinematografica militare generata in codice (nessun file audio).
## Identità sonora: scura e trattenuta (R.U.S.E., Wargame, Company of Heroes, "Sicario"): bordoni gravi e pulsazioni sub,
## tessiture di rumore filtrato, pad lenti di dente di sega / sinusoidi stonate tra loro dentro passa-basso che si aprono
## e chiudono piano, "braam" profondi, taiko / tamburi bassi e rullante militare sintetizzati, rari motivi gravi
## (violoncello / ottoni bassi) in modo minore/frigio. Niente melodie acute a onda quadra, niente arpeggi, niente maggiore.
##
## API:
##   Music.play(mood, fade := 2.5)   mood: "menu" | "map" | "tension" | "battle" | "victory" | "defeat"
##                                   (alias: "ai"/"ai_turn" = "tension"); la dissolvenza incrociata dura almeno FADE[mood]
##   Music.stop(fade := 2.0)
##   Music.set_volume(v)             0..1 (il master lo gestisce Settings sul bus Master)
##   Music.set_intensity(x)          0..1, solo in battaglia: alza percussioni e braam (BattleAudio la chiama da sé)
##   Music.current -> String         mood in riproduzione ("" se ferma)
##   Music.is_ready(mood) -> bool    traccia già generata
##   Music.render(mood) -> AudioStreamWAV         generazione sincrona del mix completo (test, revisione)
##   Music.layers(mood) / render_layer(mood, ly)  livelli separati (battaglia: base, perc, hi)
## Le tracce sono loop di 40-64 s (2-4 sezioni diverse ciascuna, giunte senza scatti: tutto si avvolge sull'inizio)
## in AudioStreamWAV mono 16 bit a 22,05 kHz, generati in un thread di lavoro all'avvio, una traccia alla volta.
## La battaglia è un AudioStreamSynchronized di 3 livelli il cui volume segue l'intensità.
## Bus "Music": compressore dolce, riverbero ampio e scuro, limitatore.

const SR := 22050
const BASE := 250.0          # frequenza delle tabelle d'onda (periodo di 1 s esatto => loop perfetti)
const MOODS := ["menu", "map", "battle", "tension", "victory", "defeat"]
const ALIAS := {"ai": "tension", "ai_turn": "tension"}
## dissolvenza minima (s) entrando nel mood
const FADE := {"menu": 4.0, "map": 6.0, "tension": 4.5, "battle": 2.5, "victory": 3.0, "defeat": 4.0}
## lunghezza delle sezioni (s): ripartendo si sceglie una sezione a caso (0 = sempre dall'inizio)
const SECTION := {"menu": 0.0, "map": 16.0, "tension": 0.0, "battle": 0.0, "victory": 0.0, "defeat": 0.0}
## livello RMS del mix (dBFS): la mappa resta discreta per non stancare
const TARGET_DB := {"menu": -20.0, "map": -24.0, "tension": -22.0, "battle": -18.5, "victory": -20.0, "defeat": -21.0}
## livelli della battaglia: volume (dB) a intensità 0 e 1
const BATTLE_LAYERS := ["base", "perc", "hi"]
const LAYER_DB := {"base": [0.0, 0.0], "perc": [-16.0, 0.0], "hi": [-26.0, 0.0]}

var current := ""
var gen_ms := {}             # mood -> ms di sintesi (diagnostica)
var _vol := 0.55
var _players: Array = []     # [AudioStreamPlayer, gain, target, rate]
var _streams := {}           # mood -> AudioStream (WAV o Synchronized)
var _mutex := Mutex.new()
var _task := -1
var _queue: Array = []
var _cancel := false
var _want := ""
var _want_fade := 2.5
var _bus := "Master"
var _inten := 0.45
var _inten_target := 0.45
var _played := {}            # mood -> già suonato almeno una volta

# cache di sintesi (usata solo dal thread di generazione)
var _tones := {}
var _hits := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = _bus
		p.volume_db = -80.0
		add_child(p)
		_players.append([p, 0.0, 0.0, 1.0])
	var st := get_node_or_null("/root/Settings")
	if st != null and st.has_method("get_value"):
		var v = st.call("get_value", "vol_music")
		if v != null:
			_vol = clampf(float(v), 0.0, 1.0)
	# pre-generazione in sottofondo (non in modalità headless: test e simulazioni non ne hanno bisogno)
	if DisplayServer.get_name() != "headless":
		for m in ["menu", "map", "battle", "tension", "victory", "defeat"]:
			_enqueue(m)

func _exit_tree() -> void:
	_cancel = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _setup_bus() -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	while AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, 0)
	var co := AudioEffectCompressor.new()      # compressione dolce: tiene insieme percussioni e bordoni
	co.threshold = -20.0
	co.ratio = 2.2
	co.attack_us = 25000.0
	co.release_ms = 400.0
	co.gain = 1.5
	AudioServer.add_bus_effect(idx, co)
	var rv := AudioEffectReverb.new()          # sala ampia e scura
	rv.room_size = 0.86
	rv.damping = 0.72
	rv.spread = 0.95
	rv.hipass = 0.12
	rv.wet = 0.3
	rv.dry = 0.85
	rv.predelay_msec = 55.0
	rv.predelay_feedback = 0.3
	AudioServer.add_bus_effect(idx, rv)
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	lim.threshold_db = -3.0
	AudioServer.add_bus_effect(idx, lim)
	_bus = "Music"

# ============================================================== API
func play(mood: String, fade: float = 2.5) -> void:
	mood = String(ALIAS.get(mood, mood))
	if not mood in MOODS:
		push_warning("Music: mood sconosciuto " + mood)
		return
	fade = maxf(fade, float(FADE.get(mood, 2.5)))
	if mood == current and _want == "":
		return
	_mutex.lock()
	var ok := _streams.has(mood)
	_mutex.unlock()
	if not ok:
		_want = mood
		_want_fade = fade
		_enqueue(mood, true)
		return
	_want = ""
	_start(mood, fade)

func stop(fade: float = 2.0) -> void:
	_want = ""
	current = ""
	for e in _players:
		e[2] = 0.0
		e[3] = 1.0 / maxf(fade, 0.05)

func set_volume(v: float) -> void:
	_vol = clampf(v, 0.0, 1.0)
	_apply_gain()

func set_intensity(x: float) -> void:
	_inten_target = clampf(x, 0.0, 1.0)

func is_ready(mood: String) -> bool:
	mood = String(ALIAS.get(mood, mood))
	_mutex.lock()
	var r := _streams.has(mood)
	_mutex.unlock()
	return r

func layers(mood: String) -> Array:
	return BATTLE_LAYERS.duplicate() if mood == "battle" else []

func _start(mood: String, fade: float) -> void:
	_mutex.lock()
	var s: AudioStream = _streams[mood]
	_mutex.unlock()
	current = mood
	var rate := 1.0 / maxf(fade, 0.05)
	# il lettore più silenzioso prende la nuova traccia, l'altro sfuma
	var a: Array = _players[0]
	var b: Array = _players[1]
	var nw: Array = a if float(a[1]) <= float(b[1]) else b
	var old: Array = b if nw == a else a
	old[2] = 0.0
	old[3] = rate
	if mood == "battle":
		_inten = 0.45
		_inten_target = 0.45
		_apply_intensity(s)
	var p: AudioStreamPlayer = nw[0]
	p.stream = s
	var from := 0.0
	var sec: float = SECTION.get(mood, 0.0)
	if sec > 0.0 and _played.has(mood) and s is AudioStreamWAV:
		var nsec := maxi(1, int((s as AudioStreamWAV).get_length() / sec + 0.01))
		from = float(_rng.randi() % nsec) * sec
	_played[mood] = true
	p.play(from)
	nw[1] = 0.0
	nw[2] = 1.0
	nw[3] = rate
	_apply_gain()

func _process(delta: float) -> void:
	if _want != "" and is_ready(_want):
		var m := _want
		_want = ""
		_start(m, _want_fade)
	for e in _players:
		var g: float = e[1]
		var tg: float = e[2]
		if g != tg:
			g = move_toward(g, tg, delta * float(e[3]))
			e[1] = g
			if g <= 0.0:
				(e[0] as AudioStreamPlayer).stop()
	if _inten != _inten_target:
		# sale in ~4 s, scende in ~12 s
		_inten = move_toward(_inten, _inten_target, delta * (0.25 if _inten_target > _inten else 0.08))
		if current == "battle":
			_mutex.lock()
			var s = _streams.get("battle")
			_mutex.unlock()
			_apply_intensity(s)
	_apply_gain()

func _apply_intensity(s) -> void:
	if not (s is AudioStreamSynchronized):
		return
	var ss: AudioStreamSynchronized = s
	for i in mini(ss.stream_count, BATTLE_LAYERS.size()):
		var L: Array = LAYER_DB[BATTLE_LAYERS[i]]
		var k := _inten if i == 1 else pow(_inten, 1.6)
		ss.set_sync_stream_volume(i, lerpf(float(L[0]), float(L[1]), k))

func _apply_gain() -> void:
	for e in _players:
		var g: float = float(e[1]) * _vol
		# curva percettiva: dissolvenza "equal power"
		(e[0] as AudioStreamPlayer).volume_db = linear_to_db(maxf(sin(float(e[1]) * PI * 0.5) * _vol, 0.00001)) if g > 0.0 else -80.0

# ============================================================== generazione in sottofondo
func _enqueue(mood: String, urgent: bool = false) -> void:
	_mutex.lock()
	if not _streams.has(mood):
		_queue.erase(mood)
		if urgent:
			_queue.push_front(mood)
		else:
			_queue.append(mood)
	var start := _task < 0 and not _queue.is_empty()
	_mutex.unlock()
	if start:
		_task = WorkerThreadPool.add_task(_worker, false, "Music")
		set_process(true)

func _worker() -> void:
	while not _cancel:
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			break
		var m: String = _queue.pop_front()
		var have := _streams.has(m)
		_mutex.unlock()
		if have:
			continue
		var s := _render_stream(m)
		_mutex.lock()
		if s != null:
			_streams[m] = s
		_mutex.unlock()
	call_deferred("_worker_done")

func _worker_done() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_mutex.lock()
	var more := not _queue.is_empty()
	_mutex.unlock()
	if more and not _cancel:
		_task = WorkerThreadPool.add_task(_worker, false, "Music")

## Flusso di riproduzione: WAV in loop; la battaglia a livelli sincronizzati (se la classe esiste).
func _render_stream(mood: String) -> AudioStream:
	var L := render_buffers(mood)
	if L.is_empty():
		return null
	if L.size() > 1 and ClassDB.class_exists("AudioStreamSynchronized"):
		var ss := AudioStreamSynchronized.new()
		ss.stream_count = L.size()
		var i := 0
		for k in L.keys():
			ss.set_sync_stream(i, _to_wav(L[k]))
			ss.set_sync_stream_volume(i, 0.0)
			i += 1
		return ss
	return _to_wav(_mix(L))

## Genera una traccia completa (mix di tutti i livelli). Usato dai test e dalla revisione audio.
func render(mood: String) -> AudioStreamWAV:
	mood = String(ALIAS.get(mood, mood))
	var L := render_buffers(mood)
	if L.is_empty():
		return null
	return _to_wav(_mix(L))

func render_layer(mood: String, layer: String) -> AudioStreamWAV:
	var L := render_buffers(mood)
	if not L.has(layer):
		return null
	return _to_wav(L[layer])

## Livelli float (già normalizzati insieme). Dizionario ordinato: livello -> PackedFloat32Array.
func render_buffers(mood: String) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	_rng.seed = hash(mood)
	var L: Dictionary
	match mood:
		"menu": L = _menu()
		"map": L = _map()
		"tension": L = _tension()
		"battle": L = _battle()
		"victory": L = _victory()
		"defeat": L = _defeat()
		_: return {}
	if _cancel:
		return {}
	_finish(L, float(TARGET_DB[mood]))
	gen_ms[mood] = (Time.get_ticks_usec() - t0) / 1000.0
	return L

func _mix(L: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in L.keys():
		var b: PackedFloat32Array = L[k]
		if out.is_empty():
			out = b.duplicate()
		else:
			for i in b.size():
				out[i] += b[i]
	return out

## Pulizia e livello: passa-alto a 28 Hz, niente NaN, RMS del mix al valore voluto con picco ≤ 0,89 (stesso guadagno
## per tutti i livelli, così l'equilibrio resta quello composto).
func _finish(L: Dictionary, target_db: float) -> void:
	for k in L.keys():
		var b: PackedFloat32Array = L[k]
		for i in b.size():
			if is_nan(b[i]) or is_inf(b[i]):
				b[i] = 0.0
		_hp(b, 28.0)
		L[k] = b
	var mix := _mix(L)
	var pk := 0.0
	var ss := 0.0
	for v in mix:
		pk = maxf(pk, absf(v))
		ss += v * v
	var rms := sqrt(ss / maxf(1.0, mix.size()))
	if rms < 1e-9:
		return
	var g := minf(0.89 / maxf(pk, 1e-9), db_to_linear(target_db) / rms)
	for k in L.keys():
		var b: PackedFloat32Array = L[k]
		for i in b.size():
			b[i] *= g
		L[k] = b

static func _to_wav(raw: PackedFloat32Array) -> AudioStreamWAV:
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
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

# ============================================================== sintesi: tabelle d'onda
static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

## Tono periodico di 1 s (SR+1 campioni, l'ultimo = il primo), limitato in armoniche per la banda d'intonazione.
## "saw" = tre denti di sega stonati (±14 cent), "warm" = dente di sega addolcito (violoncello / ottone basso),
## "sine" = sinusoide pura, "sub" = sinusoide con un filo di seconda armonica.
func _tone(inst: String, ratio: float) -> PackedFloat32Array:
	var band := 0 if ratio <= 0.85 else (1 if ratio <= 1.7 else 2)
	var key := "%s%d" % [inst, band]
	if _tones.has(key):
		return _tones[key]
	var hmax := [44, 22, 11][band] as int
	var amps: Array = []
	var voices: Array = [250]
	match inst:
		"saw":
			voices = [248, 250, 252]
			for n in range(1, 45):
				amps.append(1.0 / float(n))
		"warm":
			voices = [249, 251]
			for n in range(1, 45):
				amps.append(exp(-float(n) / 9.0) / pow(float(n), 0.8) * (1.0 if n % 2 == 1 else 0.8))
		"sub":
			amps = [1.0, 0.18, 0.04]
		_:
			amps = [1.0]
	var W := 1024
	var cyc := PackedFloat32Array()
	cyc.resize(W + 1)
	var nh := mini(amps.size(), hmax)
	var peak := 0.0
	for i in W:
		var x := TAU * float(i) / float(W)
		var v := 0.0
		for h in nh:
			v += float(amps[h]) * sin(x * float(h + 1) + float(h) * 0.37)
		cyc[i] = v
		peak = maxf(peak, absf(v))
	for i in W:
		cyc[i] /= maxf(peak, 0.0001)
	cyc[W] = cyc[0]
	var out := PackedFloat32Array()
	out.resize(SR + 1)
	var nv := voices.size()
	for vi in nv:
		var step := float(voices[vi]) * float(W) / float(SR)
		var ph := float(vi) * 337.0
		for i in SR:
			var i0 := int(ph)
			var a: float = cyc[i0]
			out[i] += (a + (cyc[i0 + 1] - a) * (ph - float(i0))) / float(nv)
			ph += step
			if ph >= float(W):
				ph -= float(W)
	out[SR] = out[0]
	_tones[key] = out
	return out

## Nota di pad (senza filtro proprio: il livello viene filtrato tutto insieme). Inviluppo morbido, avvolta sul loop.
func _pad(buf: PackedFloat32Array, t0: float, midi: float, dur: float, inst: String, vel: float, att: float, rel: float) -> void:
	var ratio := _hz(midi) / BASE
	var tone := _tone(inst, ratio)
	var n_on := maxi(1, int(dur * SR))
	var n_att := mini(n_on, maxi(1, int(att * SR)))
	var n_rel := maxi(1, int(rel * SR))
	var total := n_on + n_rel
	var N := buf.size()
	var idx := posmod(int(t0 * SR), N)
	var ph := float(_rng.randi() % SR)
	var fsr := float(SR)
	for j in total:
		var i0 := int(ph)
		var s0: float = tone[i0]
		var smp := s0 + (tone[i0 + 1] - s0) * (ph - float(i0))
		var env := 1.0
		if j < n_att:
			var x := float(j) / n_att
			env = x * x * (3.0 - 2.0 * x)
		elif j >= n_on:
			var x2 := 1.0 - float(j - n_on) / n_rel
			env = x2 * x2
		buf[idx] += smp * env * vel
		idx += 1
		if idx >= N:
			idx = 0
		ph += ratio
		if ph >= fsr:
			ph -= fsr

## Nota con passa-basso proprio a due poli: il taglio sale da fc_lo a fc_hi in f_att secondi e ricade con costante f_dec
## (ottoni bassi, violoncello, ostinato smorzato, braam). vib = profondità del vibrato (frazione), ritardato.
func _voice(buf: PackedFloat32Array, t0: float, midi: float, dur: float, inst: String, vel: float, att: float, rel: float,
		fc_lo: float, fc_hi: float, f_att: float, f_dec: float, vib: float = 0.0) -> void:
	var ratio := _hz(midi) / BASE
	var tone := _tone(inst, ratio)
	var n_on := maxi(1, int(dur * SR))
	var n_att := mini(n_on, maxi(1, int(att * SR)))
	var n_rel := maxi(1, int(rel * SR))
	var total := n_on + n_rel
	var N := buf.size()
	var idx := posmod(int(t0 * SR), N)
	var ph := float(_rng.randi() % SR)
	var fsr := float(SR)
	var y1 := 0.0
	var y2 := 0.0
	var a := 0.1
	var step := ratio
	var vph := _rng.randf() * TAU
	for j in total:
		if j % 16 == 0:
			var t := float(j) / fsr
			var k := t / f_att if t < f_att else exp(-(t - f_att) / f_dec)
			a = 1.0 - exp(-TAU * (fc_lo + (fc_hi - fc_lo) * k) / fsr)
			if vib > 0.0:
				step = ratio * (1.0 + vib * sin(vph + TAU * 4.8 * t) * minf(1.0, t / 0.7))
		var i0 := int(ph)
		var s0: float = tone[i0]
		var smp := s0 + (tone[i0 + 1] - s0) * (ph - float(i0))
		var env := 1.0
		if j < n_att:
			var x := float(j) / n_att
			env = x * x * (3.0 - 2.0 * x)
		elif j >= n_on:
			var x2 := 1.0 - float(j - n_on) / n_rel
			env = x2 * x2
		y1 += a * (smp - y1)
		y2 += a * (y1 - y2)
		buf[idx] += y2 * env * vel
		idx += 1
		if idx >= N:
			idx = 0
		ph += step
		if ph >= fsr:
			ph -= fsr

## Bordone lungo quanto tutto il loop: frequenza ritoccata (≤ 0,02 Hz) per un numero intero di periodi => nessuna giunta.
## Respiro d'ampiezza periodico (am_cycles respiri per loop, profondità depth).
func _drone(buf: PackedFloat32Array, midi: float, inst: String, amp: float, am_cycles: int = 1, depth: float = 0.3, am_phase: float = 0.0) -> void:
	var N := buf.size()
	var ratio := _hz(midi) / BASE
	var fsr := float(SR)
	ratio = maxf(1.0, roundf(ratio * float(N) / fsr)) * fsr / float(N)
	var tone := _tone(inst, ratio)
	var ph := 0.0
	var g := amp
	for j in N:
		if j % 64 == 0:
			g = amp * (1.0 - depth * (0.5 + 0.5 * sin(TAU * float(am_cycles) * float(j) / float(N) + am_phase)))
		var i0 := int(ph)
		var s0: float = tone[i0]
		buf[j] += (s0 + (tone[i0 + 1] - s0) * (ph - float(i0))) * g
		ph += ratio
		if ph >= fsr:
			ph -= fsr

# ============================================================== sintesi: filtri sul livello (consapevoli del loop)
## Passa-basso a due poli con taglio che respira: f = f_lo·(f_hi/f_lo)^m, m = 0,5 + 0,5·Σ w·sin(2π·c·t/L + φ)
## (c intero => periodico sul loop). Lo stato iniziale si scalda sulla coda: nessuna giunta.
func _lp_sweep(buf: PackedFloat32Array, f_lo: float, f_hi: float, lfo: Array) -> void:
	var N := buf.size()
	var fsr := float(SR)
	var y1 := 0.0
	var y2 := 0.0
	var a := 0.1
	var warm := mini(N, SR * 2)
	for ps in 2:
		var j0 := N - warm if ps == 0 else 0
		for j in range(j0, N):
			if j % 32 == 0:
				var m := 0.5
				for l in lfo:
					m += 0.5 * float(l[1]) * sin(TAU * float(l[0]) * float(j) / float(N) + float(l[2]))
				a = 1.0 - exp(-TAU * f_lo * pow(f_hi / f_lo, clampf(m, 0.0, 1.0)) / fsr)
			y1 += a * (buf[j] - y1)
			y2 += a * (y1 - y2)
			if ps == 1:
				buf[j] = y2

func _hp(buf: PackedFloat32Array, fc: float) -> void:
	var N := buf.size()
	var a := exp(-TAU * fc / float(SR))
	var y := 0.0
	var xp := 0.0
	for j in range(maxi(0, N - SR), N):
		y = a * (y + buf[j] - xp)
		xp = buf[j]
	for j in N:
		var x := buf[j]
		y = a * (y + x - xp)
		xp = x
		buf[j] = y

## Tessitura di rumore: passa-banda a variabili di stato con centro che vaga (f_lo..f_hi, f_cycles giri per loop),
## livello RMS = amp, respiro d'ampiezza periodico. Il rumore bianco è già "ciclico", il filtro si scalda sulla coda.
func _noise_bed(buf: PackedFloat32Array, amp: float, f_lo: float, f_hi: float, f_cycles: int, q: float, am_cycles: int, depth: float, seed: int) -> void:
	var N := buf.size()
	var tmp := PackedFloat32Array()
	tmp.resize(N)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for j in N:
		tmp[j] = r.randf() * 2.0 - 1.0
	var lo := 0.0
	var bd := 0.0
	var f := 0.1
	var fsr := float(SR)
	var damp := 1.0 / maxf(0.5, q)
	var warm := mini(N, SR)
	var ss := 0.0
	for ps in 2:
		var j0 := N - warm if ps == 0 else 0
		for j in range(j0, N):
			if j % 32 == 0:
				var m := 0.5 + 0.35 * sin(TAU * float(f_cycles) * float(j) / float(N)) + 0.15 * sin(TAU * float(f_cycles * 3 + 1) * float(j) / float(N) + 1.7)
				f = 2.0 * sin(PI * minf(f_lo * pow(f_hi / f_lo, m), 3500.0) / fsr)
			lo += f * bd
			var hi := tmp[j] - lo - damp * bd
			bd += f * hi
			if ps == 1:
				tmp[j] = bd
				ss += bd * bd
	var k := amp / maxf(1e-9, sqrt(ss / float(N)))
	var g := 1.0
	for j in N:
		if j % 64 == 0:
			g = k * (1.0 - depth * (0.5 + 0.5 * sin(TAU * float(am_cycles) * float(j) / float(N) + 0.9)))
		buf[j] += tmp[j] * g

## Saturazione morbida relativa al picco (dà corpo, accorcia i picchi delle percussioni).
func _soft(buf: PackedFloat32Array, drive: float) -> void:
	var pk := 0.0
	for v in buf:
		pk = maxf(pk, absf(v))
	if pk < 1e-9:
		return
	var k := drive / pk
	var nrm := pk / tanh(drive)
	for i in buf.size():
		buf[i] = tanh(buf[i] * k) * nrm

# ============================================================== sintesi: percussioni e colpi (campioni brevi in cache)
func _hit(name: String, variant: int = 0, pitch: float = 0.0) -> PackedFloat32Array:
	var key := "%s%d_%.1f" % [name, variant, pitch]
	if _hits.has(key):
		return _hits[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	var out := PackedFloat32Array()
	var fsr := float(SR)
	var dv := r.randf_range(0.96, 1.04)     # ogni variante leggermente diversa
	match name:
		"taiko":     # tamburo grande: pelle che cala, secondo modo, schiaffo di pelle filtrato
			var n := int(1.1 * SR)
			out.resize(n)
			var ph := 0.0
			var ph2 := 0.0
			var lp := 0.0
			for i in n:
				var t := float(i) / fsr
				var f := (60.0 + 55.0 * exp(-t * 32.0)) * dv
				ph += TAU * f / fsr
				ph2 += TAU * f * 1.59 / fsr
				lp += ((r.randf() * 2.0 - 1.0) - lp) * 0.22
				out[i] = sin(ph) * exp(-t * 5.0) + sin(ph2) * 0.25 * exp(-t * 13.0) + lp * 0.9 * exp(-t * 40.0)
		"odaiko":    # tamburo enorme, lontano
			var n := int(2.0 * SR)
			out.resize(n)
			var ph := 0.0
			var lp := 0.0
			for i in n:
				var t := float(i) / fsr
				var f := (42.0 + 38.0 * exp(-t * 22.0)) * dv
				ph += TAU * f / fsr
				lp += ((r.randf() * 2.0 - 1.0) - lp) * 0.08
				out[i] = sin(ph) * exp(-t * 2.6) + sin(ph * 1.5) * 0.18 * exp(-t * 7.0) + lp * 1.4 * exp(-t * 18.0)
		"tom":
			var n := int(0.7 * SR)
			out.resize(n)
			var ph := 0.0
			var lp := 0.0
			var f0 := (88.0 + pitch) * dv
			for i in n:
				var t := float(i) / fsr
				ph += TAU * (f0 + 45.0 * exp(-t * 30.0)) / fsr
				lp += ((r.randf() * 2.0 - 1.0) - lp) * 0.3
				out[i] = sin(ph) * exp(-t * 8.0) + sin(ph * 1.52) * 0.2 * exp(-t * 16.0) + lp * 0.6 * exp(-t * 60.0)
		"snare":     # rullante militare: corpo a 185/330 Hz, cordiera (rumore passa-banda) lunga, colpo di bacchetta
			var n := int(0.5 * SR)
			out.resize(n)
			var lo := 0.0
			var bd := 0.0
			var fb := 2.0 * sin(PI * 2900.0 * dv / fsr)
			var y := 0.0
			for i in n:
				var t := float(i) / fsr
				var w := r.randf() * 2.0 - 1.0
				lo += fb * bd
				var hi := w - lo - 1.1 * bd
				bd += fb * hi
				var v := sin(TAU * 182.0 * dv * t) * 0.55 * exp(-t * 32.0) + sin(TAU * 331.0 * dv * t) * 0.25 * exp(-t * 48.0)
				v += bd * 0.75 * exp(-t * 11.0) + w * 0.5 * exp(-t * 350.0)
				y += 0.55 * (v - y)            # passa-basso ~6 kHz: niente sfrigolio
				out[i] = y
		"rim":       # colpo sul cerchio, smorzato
			var n := int(0.07 * SR)
			out.resize(n)
			var y := 0.0
			for i in n:
				var t := float(i) / fsr
				var v := sin(TAU * 1650.0 * dv * t) * 0.5 * exp(-t * 170.0) + sin(TAU * 620.0 * dv * t) * 0.4 * exp(-t * 90.0)
				v += (r.randf() * 2.0 - 1.0) * 0.5 * exp(-t * 700.0)
				y += 0.5 * (v - y)
				out[i] = y
		"sub":       # pulsazione sub (battito)
			var n := int(0.9 * SR)
			out.resize(n)
			var ph := 0.0
			for i in n:
				var t := float(i) / fsr
				ph += TAU * (44.0 + 10.0 * exp(-t * 18.0)) / fsr
				out[i] = sin(ph) * minf(1.0, t / 0.008) * exp(-t * 4.5)
		"boom":      # colpo cinematografico sub-basso con rombo
			var n := int(3.6 * SR)
			out.resize(n)
			var ph := 0.0
			var lp := 0.0
			var lp2 := 0.0
			for i in n:
				var t := float(i) / fsr
				ph += TAU * (28.0 + 42.0 * exp(-t * 4.0)) / fsr
				lp += ((r.randf() * 2.0 - 1.0) - lp) * 0.04
				lp2 += (lp - lp2) * 0.04
				out[i] = sin(ph) * exp(-t * 1.3) * minf(1.0, t / 0.004) + lp2 * 9.0 * exp(-t * 1.8)
		"metal":     # colpo metallico grave e lontano (lamiera, ancora): parziali inarmoniche lunghe
			var fr := [97.0, 263.0, 431.0, 602.0, 911.0, 1287.0]
			var am := [0.5, 0.45, 0.32, 0.22, 0.14, 0.08]
			var ta := [2.4, 1.6, 1.1, 0.8, 0.5, 0.3]
			var n := int(3.0 * SR)
			out.resize(n)
			for k in fr.size():
				var w := TAU * float(fr[k]) * dv / fsr
				for i in n:
					out[i] += sin(w * float(i)) * float(am[k]) * exp(-float(i) / fsr / float(ta[k]))
			var y := 0.0
			for i in mini(n, int(0.4 * SR)):
				y += 0.1 * ((r.randf() * 2.0 - 1.0) - y)
				out[i] += y * 1.5 * exp(-float(i) / fsr * 9.0)
		"timp":      # timpano intonato (pitch = nota midi)
			var n := int(1.8 * SR)
			out.resize(n)
			var f0 := _hz(pitch)
			var lp := 0.0
			for i in n:
				var t := float(i) / fsr
				var x := TAU * f0 * t
				lp += ((r.randf() * 2.0 - 1.0) - lp) * 0.15
				out[i] = (sin(x) + 0.45 * sin(x * 1.504) * exp(-t * 3.0) + 0.25 * sin(x * 1.742) * exp(-t * 4.0)) * exp(-t * 2.0) * 0.7 + lp * exp(-t * 35.0) * 0.6
		"riser":     # rumore che sale (2,5 s) e si ferma di colpo: porta al colpo successivo
			var n := int(2.5 * SR)
			out.resize(n)
			var lo := 0.0
			var bd := 0.0
			for i in n:
				var x := float(i) / float(n)
				var f := 2.0 * sin(PI * (250.0 * pow(12.0, x)) / fsr)
				var w := r.randf() * 2.0 - 1.0
				lo += f * bd
				var hi := w - lo - 0.9 * bd
				bd += f * hi
				out[i] = bd * x * x * x * minf(1.0, float(n - i) / (0.03 * fsr))
		"braam":     # ottoni gravi a quinte vuote che si aprono: pitch = fondamentale midi
			var keep := _rng.state
			_rng.seed = hash(key)
			var n := int(5.0 * SR)
			out.resize(n)
			for iv in [[0.0, 0.7], [12.0, 0.8], [19.0, 0.55], [24.0, 0.45], [7.0, 0.4], [15.0, 0.18]]:
				_voice(out, 0.0, pitch + float(iv[0]), 2.4, "saw", float(iv[1]), 0.28, 2.2, 110.0, 2300.0, 0.55, 1.2)
			_voice(out, 0.0, pitch - 12.0, 2.8, "sub", 0.55, 0.15, 1.8, 400.0, 400.0, 0.1, 10.0)
			_soft(out, 2.2)
			_rng.state = keep
	_hits[key] = out
	return out

func _add(buf: PackedFloat32Array, t0: float, smp: PackedFloat32Array, gain: float) -> void:
	var N := buf.size()
	var idx := posmod(int(t0 * SR), N)
	for i in smp.size():
		buf[idx] += smp[i] * gain
		idx += 1
		if idx >= N:
			idx = 0

## Colpo umanizzato: variante a caso (0..2), ±5 ms, velocità ±12 %.
func _hum(buf: PackedFloat32Array, t: float, name: String, gain: float, pitch: float = 0.0) -> void:
	_add(buf, t + _rng.randf_range(-0.005, 0.005), _hit(name, _rng.randi() % 3, pitch), gain * _rng.randf_range(0.88, 1.06))

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * SR))
	return b

# ============================================================== composizioni
## menu — re eolio/frigio, libero (~60 BPM), 48 s in quattro sezioni: bordone sub, pad di denti di sega che respirano nel
## passa-basso, vento lontano, un braam grave in apertura, taiko distanti, violoncello grave e rado.
func _menu() -> Dictionary:
	var L := 48.0
	var pad := _buf(L)
	var low := _buf(L)
	var fx := _buf(L)
	_drone(low, 26.0, "sub", 0.072, 2, 0.35)                          # re1 sub
	_drone(pad, 38.0, "saw", 0.16, 3, 0.4, 1.0)                     # re2
	_drone(pad, 45.0, "saw", 0.09, 2, 0.6, 2.5)                     # la2 (quinta vuota)
	var ch := [[50.0, 53.0, 57.0], [46.0, 50.0, 53.0], [43.0, 46.0, 50.0], [51.0, 55.0, 50.0]]   # re-, sib, sol-/re, mib/re (frigio)
	for i in 4:
		for nt in ch[i]:
			_pad(pad, float(i) * 12.0 - 1.0, float(nt), 11.0, "saw", 0.126, 4.5, 5.0)
	_lp_sweep(pad, 336.0, 1540.0, [[1, 0.7, -1.2], [3, 0.3, 0.4]])
	_noise_bed(fx, 0.02, 220.0, 900.0, 2, 1.4, 3, 0.6, 11)       # vento / aria
	# violoncello grave, due frasi rade
	for m in [[5.0, 45.0, 3.0], [8.2, 46.0, 2.2], [10.6, 45.0, 2.0], [12.8, 43.0, 1.8], [14.8, 41.0, 4.0],
			[29.0, 50.0, 3.5], [32.6, 48.0, 1.8], [34.6, 46.0, 1.8], [36.6, 45.0, 5.0]]:
		_voice(fx, float(m[0]), float(m[1]), float(m[2]), "warm", 0.28, 0.6, 1.4, 220.0, 1100.0, 0.7, 2.0, 0.005)
		_voice(fx, float(m[0]), float(m[1]) - 12.0, float(m[2]), "warm", 0.1, 0.8, 1.4, 160.0, 600.0, 0.8, 2.0, 0.003)
	_add(low, 0.0, _hit("braam", 0, 38.0), 0.3)
	_add(low, 0.0, _hit("boom"), 0.175)
	_add(low, 24.0, _hit("boom", 1), 0.112)
	for t in [8.0, 9.5, 20.0, 32.0, 33.5, 44.0]:
		_hum(low, t, "odaiko", 0.098)
	_add(fx, 40.0, _hit("metal"), 0.05)
	return {"pad": pad, "low": low, "fx": fx}

## mappa / turni — mi frigio, 64 s in quattro sezioni da 16 s: tappeto grave e discreto che non stanca. Bordone, pad
## scuro che cambia colore (mi-, do/mi, la-/mi, fa/mi), statica radio lontana, rari tonfi, una frase di violoncello.
func _map() -> Dictionary:
	var L := 64.0
	var pad := _buf(L)
	var low := _buf(L)
	var fx := _buf(L)
	_drone(low, 28.0, "sub", 0.054, 4, 0.3)                          # mi1
	_drone(pad, 40.0, "saw", 0.14, 2, 0.45)                         # mi2
	_drone(pad, 47.0, "saw", 0.07, 3, 0.7, 1.3)                    # si2
	var ch := [[52.0, 55.0, 59.0], [52.0, 55.0, 60.0], [45.0, 52.0, 57.0], [41.0, 48.0, 53.0]]
	for i in 4:
		for nt in ch[i]:
			_pad(pad, float(i) * 16.0 - 1.5, float(nt), 14.5, "saw", 0.105, 5.5, 6.0)
	_lp_sweep(pad, 308.0, 1260.0, [[1, 0.6, 0.0], [4, 0.4, 1.1]])
	_noise_bed(fx, 0.012, 900.0, 1700.0, 3, 3.0, 5, 0.8, 21)       # statica radio lontana
	_noise_bed(fx, 0.014, 160.0, 520.0, 2, 1.2, 2, 0.5, 22)        # vento grave
	for m in [[38.0, 47.0, 3.5], [42.0, 48.0, 2.5], [44.8, 47.0, 2.5], [47.6, 45.0, 4.5]]:
		_voice(fx, float(m[0]), float(m[1]), float(m[2]), "warm", 0.2, 0.9, 1.8, 200.0, 900.0, 0.9, 2.0, 0.004)
	for t in [0.0, 16.0, 32.0, 48.0]:
		_hum(low, t, "odaiko", 0.070)
		_add(low, t + 8.0, _hit("sub", 0), 0.12)
	_add(fx, 26.0, _hit("metal", 1), 0.035)
	_add(fx, 58.0, _hit("metal", 2), 0.03)
	return {"pad": pad, "low": low, "fx": fx}

## tensione / turno dell'IA — mi frigio, 90 BPM, 16 battute (42,7 s): pulsazione grave e smorzata in crome sulla tonica
## (fa nelle battute di passaggio), ticchettio del cerchio, battito sub, cluster acuto lontano (mi-fa), salita finale.
func _tension() -> Dictionary:
	var bt := 60.0 / 90.0
	var L := 64.0 * bt
	var pad := _buf(L)
	var low := _buf(L)
	var fx := _buf(L)
	_drone(low, 28.0, "sub", 0.054, 4, 0.3)
	_drone(pad, 40.0, "saw", 0.16, 2, 0.4)
	for nt in [52.0, 59.0]:     # mi3-si3: quinta vuota che respira
		_pad(pad, -2.0, nt, 22.0, "saw", 0.06, 7.0, 7.0)
		_pad(pad, 19.0, nt, 22.0, "saw", 0.05, 7.0, 7.0)
	_pad(pad, 0.0, 76.0, 20.0, "saw", 0.028, 6.0, 6.0)               # mi5 + fa5 lontani: dissonanza ferma
	_pad(pad, 21.0, 77.0, 18.0, "saw", 0.024, 6.0, 6.0)
	_lp_sweep(pad, 420.0, 1540.0, [[1, 0.6, 0.0], [2, 0.4, 2.0]])
	_noise_bed(fx, 0.006, 500.0, 1400.0, 2, 2.0, 4, 0.7, 31)
	for bar in 16:
		var t := float(bar) * 4.0 * bt
		var root := 41.0 if (bar % 4 == 3 and bar != 15) else 40.0
		var sw := 0.7 + 0.3 * sin(TAU * float(bar) / 16.0)
		for k in 8:
			var acc := 1.0 if k % 4 == 0 else (0.75 if k == 3 or k == 6 else 0.55)
			var tk := t + float(k) * 0.5 * bt
			_voice(low, tk, root + (12.0 if k == 6 else 0.0), 0.16, "warm", 0.3 * acc * sw, 0.004, 0.1, 130.0, 450.0 + 600.0 * acc, 0.008, 0.06)
			if k % 2 == 1:
				_hum(fx, tk, "rim", 0.045 * sw)
		_add(low, t, _hit("sub", bar % 3), 0.2)
		if bar % 4 == 0:
			_hum(low, t, "odaiko", 0.140)
		if bar % 8 == 6:
			_hum(low, t + 2.0 * bt, "tom", 0.12)
			_hum(low, t + 2.5 * bt, "tom", 0.09)
	_add(fx, L - 2.5, _hit("riser"), 0.05)
	_add(fx, 10.0 * 4.0 * bt, _hit("metal"), 0.04)
	return {"pad": pad, "low": low, "fx": fx}

## battaglia — re frigio, 120 BPM, 24 battute (48 s) in sei frasi da 4 battute (re, re, sib, do, re, mib).
## base: bordoni, pad, ostinato grave smorzato in semicrome (3-3-2) sulla radice; perc: taiko, tom, rullante militare con
## note fantasma e rullate di fine frase; hi: braam a inizio frase, ottoni bassi in frigio, salite di rumore.
func _battle() -> Dictionary:
	var bt := 0.5
	var L := 96.0 * bt
	var base := _buf(L)
	var perc := _buf(L)
	var hi := _buf(L)
	var roots := [38.0, 38.0, 34.0, 36.0, 38.0, 39.0]
	_drone(base, 26.0, "sub", 0.054, 6, 0.25)
	_drone(base, 38.0, "saw", 0.1, 3, 0.5)
	var padb := _buf(L)
	for ph in 6:
		var r: float = roots[ph]
		var t0 := float(ph) * 16.0 * bt
		for nt in [r, r + 7.0, r + 12.0]:
			_pad(padb, t0 - 0.5, nt, 8.0, "saw", 0.112, 1.5, 2.5)
	_lp_sweep(padb, 420.0, 1960.0, [[3, 0.6, 0.0], [6, 0.4, 1.0]])
	for i in base.size():
		base[i] += padb[i]
	padb = PackedFloat32Array()
	var acc16 := [1.0, 0.45, 0.5, 0.9, 0.45, 0.5, 0.85, 0.5, 1.0, 0.45, 0.5, 0.9, 0.45, 0.5, 0.75, 0.6]
	for bar in 24:
		var ph2 := bar / 4
		var r2: float = roots[ph2]
		var t := float(bar) * 4.0 * bt
		for k in 16:
			var a: float = acc16[k]
			var nt2 := r2 + (12.0 if (k == 14 and bar % 2 == 1) else 0.0)
			_voice(base, t + float(k) * 0.25 * bt, nt2, 0.09, "warm", 0.28 * a, 0.003, 0.07, 140.0, 450.0 + 900.0 * a, 0.006, 0.05)
		# --- percussioni
		_hum(perc, t, "odaiko", 0.252)
		for b in [1.5, 2.0, 3.0, 3.75]:
			_hum(perc, t + b * bt, "taiko", 0.3 if b == 2.0 else 0.22)
		if bar % 2 == 1:
			_hum(perc, t + 3.5 * bt, "taiko", 0.2)
		# rullante militare: colpi su 2 e 4, note fantasma, rullata a fine frase
		for k in 16:
			var g := 0.0
			if k == 4 or k == 12:
				g = 0.6
			elif k in [2, 7, 10, 15]:
				g = 0.11
			elif k in [6, 14] and bar % 2 == 0:
				g = 0.17
			if g > 0.0:
				_hum(perc, t + float(k) * 0.25 * bt, "snare", g)
		if bar % 4 == 3:
			for k in 12:
				_hum(perc, t + 2.5 * bt + float(k) * 0.125 * bt, "snare", 0.07 + 0.03 * float(k))
			for k in 4:
				_hum(perc, t + 2.0 * bt + float(k) * 0.25 * bt, "tom", 0.22, 20.0 - 8.0 * float(k))
		for k in 8:
			if k % 2 == 1:
				_hum(perc, t + float(k) * 0.5 * bt, "rim", 0.05)
		# --- braam e ottoni
		if bar % 4 == 0:
			_add(hi, t, _hit("braam", bar / 4 % 3, r2), 0.42 if bar % 8 == 0 else 0.32)
			_add(perc, t, _hit("boom", bar / 4 % 2), 0.140)
		if bar % 8 == 7:
			_add(hi, t + 4.0 * bt - 2.5, _hit("riser", 0), 0.07)
	# ottoni bassi: due frasi frigie (frasi 3-4 e 5-6)
	for m in [[32.0, 50.0, 3.0], [35.0, 51.0, 1.0], [36.0, 50.0, 4.0], [40.0, 48.0, 3.0], [43.0, 46.0, 1.0], [44.0, 45.0, 4.0],
			[64.0, 50.0, 2.0], [66.0, 51.0, 2.0], [68.0, 53.0, 3.0], [71.0, 51.0, 1.0], [72.0, 50.0, 6.0], [80.0, 51.0, 4.0], [84.0, 50.0, 8.0]]:
		var t3 := float(m[0]) * bt
		var d3 := float(m[2]) * bt
		_voice(hi, t3, float(m[1]), d3, "warm", 0.28, 0.18, 0.6, 200.0, 1400.0, 0.35, 0.9, 0.003)
		_voice(hi, t3, float(m[1]) - 12.0, d3, "warm", 0.16, 0.2, 0.6, 160.0, 800.0, 0.4, 0.9, 0.002)
	_soft(perc, 1.6)
	return {"base": base, "perc": perc, "hi": hi}

## vittoria — re, ~60 BPM, 36 s: rullata di onore che cresce, colpo grave, corale di ottoni bassi a quinte vuote e accordi
## sospesi (re5, sib, fa/la, sol-, sib, do, re5): solenne e trattenuta, niente fanfara.
func _victory() -> Dictionary:
	var L := 36.0
	var pad := _buf(L)
	var low := _buf(L)
	var br := _buf(L)
	_drone(low, 26.0, "sub", 0.054, 2, 0.3)
	_drone(pad, 38.0, "saw", 0.1, 2, 0.4)
	for k in 40:     # rullata d'onore in crescendo, poi colpo
		var x := float(k) / 40.0
		_hum(low, 0.0 + x * 3.2, "snare", 0.02 + 0.09 * x * x)
	_add(low, 3.2, _hit("timp", 0, 38.0), 0.5)
	_add(low, 3.2, _hit("boom"), 0.175)
	var ch := [[3.2, [38.0, 45.0, 50.0, 52.0]], [8.0, [34.0, 41.0, 50.0, 53.0]], [12.8, [33.0, 41.0, 48.0, 53.0]],
		[17.6, [31.0, 43.0, 50.0, 55.0]], [22.4, [34.0, 46.0, 50.0, 53.0]], [27.2, [36.0, 43.0, 48.0, 52.0]], [32.0, [38.0, 45.0, 50.0, 57.0]]]
	for c in ch:
		var t: float = c[0]
		for nt in c[1]:
			_voice(br, t, float(nt), 4.6, "warm", 0.16, 0.9, 1.8, 220.0, 1200.0, 1.6, 2.5, 0.0025)
			_pad(pad, t, float(nt) + 12.0, 4.4, "saw", 0.056, 1.6, 2.2)
		_hum(low, t, "timp", 0.16, float(c[1][0]) + 12.0)
	_lp_sweep(pad, 420.0, 1680.0, [[1, 0.8, -1.4]])
	_noise_bed(br, 0.006, 300.0, 900.0, 1, 1.4, 2, 0.5, 41)
	return {"pad": pad, "low": low, "br": br}

## sconfitta — do frigio, 44 s: sub di do1, cluster grave do-reb nel passa-basso chiuso, lamento di violoncello che scende,
## tuono lontano, un solo tamburo, vento scuro.
func _defeat() -> Dictionary:
	var L := 44.0
	var pad := _buf(L)
	var low := _buf(L)
	var fx := _buf(L)
	_drone(low, 24.0, "sub", 0.066, 2, 0.35)
	_drone(pad, 36.0, "saw", 0.14, 2, 0.4)
	_drone(pad, 37.0, "saw", 0.05, 3, 0.8, 2.0)                     # reb2: seconda minore che stringe
	_drone(pad, 43.0, "saw", 0.06, 1, 0.6, 0.7)
	for i in 4:
		var ch2: Array = [[48.0, 51.0], [49.0, 53.0], [46.0, 51.0], [48.0, 51.0]][i]
		for nt in ch2:
			_pad(pad, float(i) * 11.0 - 1.0, float(nt), 10.0, "saw", 0.098, 4.5, 5.0)
	_lp_sweep(pad, 238.0, 910.0, [[1, 0.7, 0.0], [3, 0.3, 1.2]])
	_noise_bed(fx, 0.016, 120.0, 420.0, 2, 1.2, 2, 0.5, 51)
	for m in [[4.0, 43.0, 3.0], [7.4, 44.0, 2.2], [9.8, 43.0, 2.0], [12.0, 41.0, 2.2], [14.4, 39.0, 5.0],
			[26.0, 48.0, 3.5], [29.8, 46.0, 2.0], [32.0, 44.0, 2.0], [34.2, 43.0, 6.0]]:
		_voice(fx, float(m[0]), float(m[1]), float(m[2]), "warm", 0.26, 0.7, 1.8, 180.0, 800.0, 0.8, 2.2, 0.005)
	_add(low, 0.0, _hit("boom"), 0.196)
	_add(low, 22.0, _hit("boom", 1), 0.140)
	_hum(low, 11.0, "odaiko", 0.098)
	_hum(low, 33.0, "odaiko", 0.084)
	_add(fx, 18.0, _hit("metal"), 0.04)
	return {"pad": pad, "low": low, "fx": fx}
