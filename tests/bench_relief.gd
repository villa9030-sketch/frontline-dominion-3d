extends SceneTree
## Misura: costruzione del rilievo (griglia della sim), auto-risoluzione con e senza rilievo, linee di vista calcolate.
var BS
var BR
var _ran := false
func _process(_dt: float) -> bool:
	if _ran:
		return true
	_ran = true
	BS = load("res://scripts/battle/battle_sim.gd")
	BR = load("res://scripts/battle/battle_relief.gd")
	for tk in ["pianura", "montagna", "deserto", "artico", "foresta", "urbano"]:
		var t0 := Time.get_ticks_usec()
		var r = BR.new(tk, 7, 4800.0, 2700.0, 138.0, 2544.0, false, 0.0, false, [[Vector2(-60, 1200), Vector2(4900, 1300)]])
		var t1 := Time.get_ticks_usec()
		print("%-9s rilievo %5.1f ms  griglia %dx%d  quote %.1f..%.1f  fiumi %d  xings %s" % [tk, (t1 - t0) / 1000.0, r.gw, r.gh, r.hmin, r.hmax, r.rivers.size(), str(r.rivers[0]["xings"].size()) if r.rivers.size() > 0 else "-"])
	for flat in [false, true]:
		BR.disabled = flat
		var tot := 0.0
		var rays := 0
		for sd in 4:
			var setup := {"terrIdx": 0, "terrain": "pianura", "terrName": "Prova", "sea": false, "seed": 100 + sd,
				"att": {"player": 0, "name": "A", "color": Color.BLUE, "forces": _f({"inf": 8, "tank": 4, "art": 2, "aa": 1}), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": false},
				"def": {"player": 1, "name": "D", "color": Color.RED, "forces": _f({"inf": 6, "tank": 3, "art": 1}), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": false, "bunkers": 0, "fort": {}},
				"support": {"att": 0, "def": 0}}
			var t0 := Time.get_ticks_usec()
			var b = BS.new(setup)
			var tg := Time.get_ticks_usec()
			b.run_headless()
			var t1 := Time.get_ticks_usec()
			tot += (t1 - t0) / 1000.0
			if b.relief != null:
				rays += b.relief.los_rays
			if sd == 0:
				print("  %s: setup %.1f ms, run %.1f ms, t=%.0f s" % ["piano" if flat else "rilievo", (tg - t0) / 1000.0, (t1 - tg) / 1000.0, b.time])
			b.dispose()
		print("%s: media %.1f ms per battaglia 15v10, raggi LOS %d" % ["piano  " if flat else "rilievo", tot / 4, rays / 4])
	quit(0)
	return true

func _f(d: Dictionary) -> Dictionary:
	var D = root.get_node_or_null("/root/Data")
	var f: Dictionary = D.empty_forces()
	for k in d:
		f[k] = d[k]
	return f
