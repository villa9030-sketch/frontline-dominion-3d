extends SceneTree
## Test headless degli effetti sonori sintetizzati: genera ogni banco (tutte le varianti), controlla NaN/Inf,
## picco ≤ 1,0, livello non nullo, giunta dei loop e conversione 16 bit; misura tempo di sintesi e memoria.
##   node tools/godot_run.js --timeout=300 -- --headless --path . --script tests/test_sfx.gd
## Opzioni: -- --only=cannon,rifle   (solo alcuni banchi)   --audio=1 (prova anche BattleAudio con una BattleSim)

var _audio := false
var _errors := 0
var _sfx: Node = null
var _ran := false

func _initialize() -> void:
	var S: GDScript = load("res://scripts/core/sfx.gd")
	var sfx: Node = S.new()
	_sfx = sfx
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		if a == "--audio=1":
			_audio = true
			only = "-"   # solo la prova di BattleAudio
	var errors := 0
	var total_ms := 0.0
	var total_bytes := 0
	var total_samples := 0
	var names: Array = sfx.names()
	for nm in names:
		if only != "" and not (nm in only.split(",")):
			continue
		var d: Array = sfx.DEFS[nm]
		var t0 := Time.get_ticks_usec()
		var raws: Array = sfx.render_raw(nm)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		var line := "[sfx] %-14s %d var %5d Hz %4.1f s  sintesi %7.1f ms" % [nm, raws.size(), d[1], d[2], ms]
		var worst_peak := 0.0
		var min_rms := 1.0
		var seam := 0.0
		for raw in raws:
			var b: PackedFloat32Array = raw
			var pk := 0.0
			var rms := 0.0
			var bad := false
			for i in b.size():
				var v := b[i]
				if is_nan(v) or is_inf(v):
					bad = true
					break
				pk = maxf(pk, absf(v))
				rms += v * v
			rms = sqrt(rms / maxf(1.0, b.size()))
			if bad:
				errors += 1
				line += "  NaN/Inf!"
			worst_peak = maxf(worst_peak, pk)
			min_rms = minf(min_rms, rms)
			total_samples += b.size()
			if bool(d[3]):
				# salto alla giunta rispetto al salto medio interno
				var avg := 0.0
				for i in range(1, b.size(), 5):
					avg += absf(b[i] - b[i - 1])
				avg /= float(b.size() / 5)
				seam = maxf(seam, absf(b[0] - b[b.size() - 1]) / maxf(1e-6, avg))
			var w: AudioStreamWAV = S._to_wav(b, int(d[1]), bool(d[3]))
			total_bytes += w.data.size()
			# verifica la conversione 16 bit su qualche campione
			for i in [0, b.size() / 3, b.size() - 1]:
				var q := w.data.decode_s16(i * 2) / 32767.0
				if absf(q - clampf(b[i], -1, 1)) > 0.002:
					errors += 1
					line += "  PCM errato @%d" % i
					break
		line += "  picco %.3f  rms min %.3f" % [worst_peak, min_rms]
		if bool(d[3]):
			line += "  giunta %.1fx" % seam
			if seam > 6.0:
				errors += 1
				line += " GIUNTA!"
		if worst_peak > 1.0:
			errors += 1
			line += "  CLIP!"
		if min_rms < 0.003:
			errors += 1
			line += "  MUTO!"
		print(line)
	if only != "-":
		print("[sfx] totale sintesi %.0f ms, %d campioni, memoria PCM %.2f MB, errori %d" % [total_ms, total_samples, total_bytes / 1048576.0, errors])
	_errors = errors
	if not _audio:
		sfx.free()
		quit(1 if errors > 0 else 0)

func _process(_dt: float) -> bool:
	if not _audio or _ran:
		return false
	_ran = true
	var t0 := Time.get_ticks_msec()
	for nm in _sfx.names():
		_sfx.stream_sync(nm)
	print("[audio] banchi generati in %d ms" % (Time.get_ticks_msec() - t0))
	_errors += _test_audio(_sfx)
	_sfx.free()
	quit(1 if _errors > 0 else 0)
	return false

## BattleAudio con una vera BattleSim (senza vista 3D): eventi fx, loop dei mezzi, voci massime.
func _test_audio(sfx: Node) -> int:
	var D = root.get_node_or_null("Data")
	if D == null:
		print("[audio] autoload Data assente: salto")
		return 0
	var BS: GDScript = load("res://scripts/battle/battle_sim.gd")
	var BA: GDScript = load("res://scripts/battle/battle_audio.gd")
	var f0: Dictionary = D.empty_forces()
	var f1: Dictionary = D.empty_forces()
	for k in {"inf": 30, "tank": 12, "art": 4, "aa": 3, "heli": 3, "drone": 2}:
		f0[k] = {"inf": 30, "tank": 12, "art": 4, "aa": 3, "heli": 3, "drone": 2}[k]
		f1[k] = f0[k]
	var s := {"terrIdx": 0, "terrain": "pianura", "terrName": "Prova", "sea": false, "seed": 3,
		"att": {"player": 0, "name": "A", "color": Color.BLUE, "forces": f0, "mods": {"atk": 1, "unit": D.TERRAINS["pianura"]["mul"], "hp": {}}, "human": false},
		"def": {"player": 1, "name": "B", "color": Color.RED, "forces": f1, "mods": {"atk": 1, "unit": D.TERRAINS["pianura"]["mul"], "hp": {}}, "human": false, "bunkers": 1},
		"support": {"att": 0, "def": 0}}
	var sim = BS.new(s)
	var bt := Node3D.new()
	root.add_child(bt)
	var cam := Camera3D.new()
	bt.add_child(cam)
	cam.position = Vector3(0, 80, 60)
	cam.look_at(Vector3.ZERO)
	var ba: Node = BA.new()
	bt.add_child(ba)
	# il test usa il banco del suo Sfx locale (l'autoload non genera in headless)
	ba.sfx = sfx
	ba.setup(bt, sim, cam)
	var t0 := Time.get_ticks_usec()
	var ev := 0
	var maxv := 0
	var steps := 0
	while steps < 1200 and not sim.done:
		sim.step(0.05)
		ev += sim.fx.size()
		ba.on_fx(sim.fx)
		sim.fx = []
		ba.update(0.05)
		maxv = maxi(maxv, ba.active_voices())
		steps += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("[audio] %d passi (%.0f s di battaglia), %d eventi fx, voci max %d, avviati %d, scartati %d, costo audio %.2f ms/passo (sim inclusa %.0f ms)" % [
		steps, steps * 0.05, ev, maxv, ba.stats["played"], ba.stats["dropped"], ba.cost_us / 1000.0 / steps, ms])
	var bad := 0
	# intensità della musica di battaglia (Music.set_intensity) pilotata da BattleAudio
	var mu := root.get_node_or_null("Music")
	if mu != null and mu.has_method("set_intensity"):
		print("[audio] intensità musica: BattleAudio %.2f, Music target %.2f" % [ba._inten, mu._inten_target])
		if absf(float(mu._inten_target) - float(ba._inten)) > 0.001 or float(ba._inten) <= 0.2:
			print("[audio] l'intensità della musica non segue la battaglia")
			bad += 1
	if maxv > ba.MAX_VOICES + ba.LOOP_VOICES + 3:
		print("[audio] troppe voci")
		bad += 1
	if ba.stats["played"] < 20:
		print("[audio] troppo pochi suoni avviati")
		bad += 1
	bt.queue_free()
	return bad
