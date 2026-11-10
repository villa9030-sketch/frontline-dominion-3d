extends SceneTree
## Strumento di revisione audio: genera musica (tutti i mood) e suoni (interfaccia + armi principali) in WAV
## dentro docs/audio_review/wav/<tag>/ per l'analisi spettrale (docs/audio_review/analyze.py).
##   node tools/godot_run.js --timeout=400 -- --headless --path . --script docs/audio_review/render_audio.gd -- --tag=after
## Opzioni: --tag=nome (sottocartella), --music=0 (salta la musica), --sfx=0 (salta i suoni), --only=menu,click

const UI := ["click", "select", "order", "build", "recruit", "research", "card", "capture", "battle", "alert", "radio", "victory", "defeat"]
const BATTLE := ["rifle", "mg", "cannon", "cannon_far", "explosion", "arty_impact", "hit_armor", "rocket", "engine_heavy", "tracks"]

func _initialize() -> void:
	var tag := "after"
	var do_music := true
	var do_sfx := true
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--music=0":
			do_music = false
		elif a == "--sfx=0":
			do_sfx = false
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	var dir := ProjectSettings.globalize_path("res://docs/audio_review/wav/" + tag)
	DirAccess.make_dir_recursive_absolute(dir)
	if do_music:
		var M: GDScript = load("res://scripts/core/music.gd")
		var m: Node = M.new()
		for mood in M.MOODS:
			if not only.is_empty() and not (mood in only):
				continue
			var t0 := Time.get_ticks_msec()
			var w: AudioStreamWAV = m.render(mood)
			var ms := Time.get_ticks_msec() - t0
			if w == null:
				print("[review] musica %s: NULL" % mood)
				continue
			w.save_to_wav(dir + "/music_" + mood + ".wav")
			print("[review] musica %-8s %5.1f s  %d ms  %.2f MB" % [mood, w.get_length(), ms, w.data.size() / 1048576.0])
			if m.has_method("render_layer"):
				# livelli separati (battaglia: base + percussioni)
				for ly in m.call("layers", mood):
					var wl: AudioStreamWAV = m.call("render_layer", mood, ly)
					if wl != null:
						wl.save_to_wav(dir + "/music_" + mood + "_" + String(ly) + ".wav")
		m.free()
	if do_sfx:
		var S: GDScript = load("res://scripts/core/sfx.gd")
		var s: Node = S.new()
		for nm in UI + BATTLE:
			if not only.is_empty() and not (nm in only):
				continue
			var d: Array = S.DEFS[nm]
			var raws: Array = s.render_raw(nm)
			var w2: AudioStreamWAV = S._to_wav(raws[0], int(d[1]), false)
			w2.save_to_wav(dir + "/sfx_" + nm + ".wav")
		print("[review] suoni salvati")
		s.free()
	print("[review] cartella ", dir)
	quit(0)
