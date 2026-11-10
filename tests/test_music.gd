extends SceneTree
## Test headless della musica generata: genera tutti i mood (e i livelli della battaglia), controlla NaN/Inf, picco
## (nessun clipping), livello RMS, giunta del loop, lunghezze uguali dei livelli sincronizzati; misura tempo e memoria.
##   node tools/godot_run.js --timeout=300 -- --headless --path . --script tests/test_music.gd
## Opzioni: -- --only=menu,battle

func _initialize() -> void:
	var M: GDScript = load("res://scripts/core/music.gd")
	var m: Node = M.new()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var errors := 0
	var total_ms := 0.0
	var total_bytes := 0
	for mood in M.MOODS:
		if only != "" and not (mood in only.split(",")):
			continue
		var t0 := Time.get_ticks_usec()
		var L: Dictionary = m.render_buffers(mood)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		if L.is_empty():
			print("[music] ERRORE ", mood, ": nessun buffer")
			errors += 1
			continue
		var n := -1
		var mix := PackedFloat32Array()
		var bad := false
		for k in L.keys():
			var b: PackedFloat32Array = L[k]
			if n < 0:
				n = b.size()
				mix.resize(n)
			elif b.size() != n:
				print("[music] ERRORE ", mood, ": livello ", k, " di lunghezza diversa")
				errors += 1
			for i in mini(n, b.size()):
				var v := b[i]
				if is_nan(v) or is_inf(v):
					bad = true
				mix[i] += v
		# in riproduzione: la battaglia tiene i livelli separati, gli altri mood un solo WAV mixato
		var play_bytes := n * 2 * (L.size() if mood == "battle" else 1)
		total_bytes += play_bytes
		var pk := 0.0
		var ss := 0.0
		var maxstep := 0.0
		var avgstep := 0.0
		for i in n:
			pk = maxf(pk, absf(mix[i]))
			ss += mix[i] * mix[i]
			if i > 0:
				var d := absf(mix[i] - mix[i - 1])
				maxstep = maxf(maxstep, d)
				avgstep += d
		avgstep /= maxf(1.0, n - 1)
		var rms := sqrt(ss / maxf(1.0, n))
		var seam := absf(mix[0] - mix[n - 1])
		var line := "[music] %-8s %4.1f s  %d livelli  sintesi %6.0f ms  picco %.3f  rms %5.1f dBFS  giunta %.4f (passo medio %.4f, max %.4f)  %.2f MB" % [
			mood, float(n) / M.SR, L.size(), ms, pk, linear_to_db(rms), seam, avgstep, maxstep, play_bytes / 1048576.0]
		if bad:
			errors += 1
			line += "  NaN/Inf!"
		if pk > 0.95:
			errors += 1
			line += "  CLIP!"
		if rms < 0.02:
			errors += 1
			line += "  TROPPO PIANO!"
		if seam > maxf(avgstep * 8.0, 0.004):
			errors += 1
			line += "  GIUNTA!"
		print(line)
	# alias e flusso di riproduzione (battaglia a livelli sincronizzati)
	if only == "" or "battle" in only:
		var t1 := Time.get_ticks_usec()
		var st: AudioStream = m._render_stream("battle")
		print("[music] flusso battaglia: %s (%d ms)" % [st.get_class() if st != null else "null", (Time.get_ticks_usec() - t1) / 1000])
		if st == null:
			errors += 1
		elif ClassDB.class_exists("AudioStreamSynchronized") and not (st is AudioStreamSynchronized):
			errors += 1
	if m.ALIAS.get("ai", "") != "tension":
		errors += 1
	print("[music] totale sintesi %.0f ms, memoria PCM %.2f MB, errori %d" % [total_ms, total_bytes / 1048576.0, errors])
	m.free()
	quit(1 if errors > 0 else 0)
