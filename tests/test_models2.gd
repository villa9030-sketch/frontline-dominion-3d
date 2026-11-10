extends SceneTree
## Test headless dei modelli della fase 2 (Agente F2): navi, elicottero, rocce, alberi stagionali, edifici, danno, effetti.
## node tools/godot_run.js -- --headless --path . --script tests/test_models2.gd
func _init() -> void:
	var err := 0
	var t0 := Time.get_ticks_msec()
	var c := Color(0.2, 0.5, 1.0)
	for k in UnitModels.KINDS + UnitModels.NAVAL:
		for lod in 3:
			var m := UnitModels.build(k, c, lod)
			if m == null or int(m.get_meta("tris", 0)) <= 0:
				print("[models2] ERRORE build ", k, " lod ", lod)
				err += 1
			elif lod == 0:
				print("[models2] %-9s tris %5d  len %.0f m" % [k, int(m.get_meta("tris")), float(m.get_meta("length", 0))])
			m.free()
		var mn := UnitModels.miniature(k, c)
		mn.free()
		var w := UnitModels.wreck(k)
		w.free()
	# FASE 4: mezzi per fazione (stessi nodi con nome, triangoli comparabili, cache per fazione)
	if UnitModels.FACTION_STYLES.size() != 4:
		print("[models2] ERRORE FACTION_STYLES")
		err += 1
	var need := {"tank": ["Body", "Turret", "Barrel", "Muzzle"], "art": ["Turret", "Barrel", "Muzzle"], "aa": ["Turret", "Barrel", "Muzzle", "Muzzle2"],
		"heli": ["Body", "Rotor", "Muzzle"], "jet": ["Body", "Muzzle"], "drone": ["Body", "Muzzle"], "inf": ["Body", "Muzzle"],
		"truck": ["Body", "Muzzle"], "bunker": ["Body", "Muzzle"]}
	for f in 4:
		var fc: Color = [Color("#3b82f6"), Color("#ef4444"), Color("#14b8a6"), Color("#f59e0b")][f]
		var line := "[models2] fazione %d:" % f
		for k in UnitModels.KINDS:
			for lod in 3:
				var m := UnitModels.build(k, fc, lod, f)
				var tr := int(m.get_meta("tris", 0))
				if tr <= 0 or tr > 9000:
					print("[models2] ERRORE fazione ", f, " ", k, " lod ", lod, " tris ", tr)
					err += 1
				if lod == 0:
					line += " %s %d" % [k, tr]
					for n in need[k]:
						if m.find_child(n, true, false) == null:
							print("[models2] ERRORE fazione ", f, " ", k, " senza ", n)
							err += 1
					var g := UnitModels.build(k, fc, 0, -1)
					if int(g.get_meta("tris")) == tr and k != "inf":
						print("[models2] AVVISO fazione ", f, " ", k, " uguale al generico")
					g.free()
				m.free()
			UnitModels.miniature(k, fc, f).free()
			UnitModels.wreck(k, f).free()
		print(line)
	var ship := UnitModels.build("ship", c)
	for n in ["Turret", "Barrel", "Muzzle", "Radar", "Body"]:
		if ship.find_child(n, true, false) == null:
			print("[models2] ERRORE nave senza ", n)
			err += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for st in Props.ROCK_STYLES:
		var r := Props.rock_mesh(rng, st)
		if r.get_surface_count() != 1:
			err += 1
	for k in Props.TREE_KINDS:
		for s in Props.SEASONS:
			if Props.tree_mesh(k, s).get_surface_count() < 1:
				print("[models2] ERRORE albero ", k, s)
				err += 1
	for st in Props.BUILDING_STYLES:
		var b := Props.building(Vector3(16, 12, 14), st, rng)
		print("[models2] edificio %-10s tris %5d" % [st, int(b.get_meta("tris"))])
		b.free()
	# danno e effetti in un albero reale
	var root3 := Node3D.new()
	root.add_child(root3)
	var tank := UnitModels.build("tank", c)
	root3.add_child(tank)
	for f in [0.3, 0.6, 0.9, 0.0]:
		UnitModels.set_damage(tank, f)
	Vfx.explosion(root3, Vector3.ZERO, 2.0)
	Vfx.fire(root3, Vector3.ZERO, 1.0, 3.0)
	Vfx.rocket_trail(root3, Vector3.ZERO, Vector3(50, 0, 0), 0.5)
	Vfx.night_flash(root3, Vector3.ZERO)
	Vfx.wake(ship, Vector3(0, 0.1, 60), Vector3(0, 0, -1))
	print("[models2] particelle attive %d, luci %d" % [Vfx.live_particles, Vfx.live_lights])
	ship.free()
	print("[models2] tempo %d ms, errori %d" % [Time.get_ticks_msec() - t0, err])
	quit(1 if err > 0 else 0)
