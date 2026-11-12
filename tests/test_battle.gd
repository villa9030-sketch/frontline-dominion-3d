extends SceneTree
## Test headless della battaglia (BattleSim). Uso:
##   node tools/godot_run.js -- --headless --path . --script tests/test_battle.gd

var _fail := 0
var D = null
var BS = null
var _ran := false

func _f(d: Dictionary) -> Dictionary:
	var o: Dictionary = D.empty_forces()
	for k in d:
		o[k] = d[k]
	return o

func _setup(terrain: String, a: Dictionary, d: Dictionary, bunkers := 0, seed := 1, extra := {}) -> Dictionary:
	var s := {
		"terrIdx": 0, "terrain": terrain, "terrName": "Prova", "sea": bool(extra.get("sea", false)), "seed": seed, "clear": bool(extra.get("clear", false)),
		"att": {"player": 0, "name": "Attaccante", "color": Color("#3b82f6"), "forces": _f(a), "mods": {"atk": 1, "unit": D.TERRAINS[terrain]["mul"], "hp": {}}, "human": bool(extra.get("ah", false))},
		"def": {"player": 1, "name": "Difensore", "color": Color("#ef4444"), "forces": _f(d), "mods": {"atk": float(D.TERRAINS[terrain]["def"]), "unit": D.TERRAINS[terrain]["mul"], "hp": {}}, "human": false, "bunkers": bunkers},
		"support": {"att": int(extra.get("sa", 0)), "def": int(extra.get("sd", 0))},
	}
	return s

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  FALLITO: ", msg)

func _run(name: String, s: Dictionary, fx := false) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var b = BS.new(s)
	b.emit_fx = fx
	var nan := false
	var steps := 0
	while not b.done and b.time < 1000 and steps < 40000:
		b.step(0.05)
		steps += 1
		if fx:
			b.fx.clear()
		if steps % 20 == 0:
			for u in b.units:
				if is_nan(u.x) or is_nan(u.y) or is_nan(u.hp) or is_inf(u.x) or is_inf(u.y):
					nan = true
	var ms := Time.get_ticks_msec() - t0
	var r = b.result
	_check(b.done, name + ": non terminata")
	_check(not nan, name + ": NaN nelle posizioni")
	_check(r != null, name + ": risultato nullo")
	if r != null:
		print("%-34s %6.1f s sim  vince %-3s  att %-34s def %-34s  [%d ms, g=%d/%d, bunker vivi %d]" % [
			name, b.time, r["winner"], _fs(r["att"]), _fs(r["def"]), ms, b.sides[0]["g"], b.sides[1]["g"], b.bunkers_alive()])
		for k in D.UNIT_KEYS:
			_check(int(r["att"][k]) <= int(s["att"]["forces"][k]) and int(r["att"][k]) >= 0, name + ": superstiti att fuori limite")
			_check(int(r["def"][k]) <= int(s["def"]["forces"][k]) and int(r["def"][k]) >= 0, name + ": superstiti def fuori limite")
	b.dispose()
	return r if r != null else {}

## Riga y senza ostacoli tra x0 e x1 (per collocare unità di prova allo scoperto).
func _clear_y(b, x0: float, x1: float) -> float:
	for yy in range(300, 2400, 20):
		var ok := true
		var x := x0
		while x <= x1:
			if b._obs_hit(x, float(yy), 22.0) or b.cover_at(x, float(yy)) > 0:
				ok = false
				break
			x += 8.0
		if ok:
			return float(yy)
	return 1350.0

## Abilità tattiche: fumo (−30% dal fuoco diretto, non dall'artiglieria, ricarica), supporto aereo (1 uso, danno d'area
## ritardato), mantieni posizione (niente inseguimento).
func _test_abilities() -> void:
	# --- fumo: stesso colpo diretto su due simulazioni identiche, con e senza fumo
	var dmg := []
	var art := []
	for smoked in [false, true]:
		var b = BS.new(_setup("pianura", {"tank": 2, "art": 1}, {"inf": 4, "tank": 2}, 0, 3, {"ah": true}))
		b.emit_fx = false
		var shooter = null
		var victim = null
		for u in b.units:
			if u.side == 0 and u.type == "tank" and shooter == null: shooter = u
			if u.side == 1 and u.type == "tank" and victim == null: victim = u
		if smoked:
			_check(b.smoke(1, [victim]), "fumo rifiutato")
			_check(victim.smoke_t > 0, "fumo: unità non coperta")
			_check(not b.smoke(1, [victim]), "fumo: ricarica ignorata")
		var h0: float = victim.hp
		b._fire(shooter, victim, 100.0)
		dmg.append(h0 - victim.hp)
		var h1: float = victim.hp
		var s = BS.Shell.new()
		s.side = 0; s.x1 = victim.x; s.y1 = victim.y; s.dmg = 3.0; s.splash = 30.0
		b._impact(s)
		art.append(h1 - victim.hp)
		if smoked:
			for i in 220:
				b.step(0.05)
			_check(victim.dead or victim.smoke_t <= 0, "fumo: non si dissolve dopo 10 s")
			for i in 620:
				b.step(0.05)
			_check(b.done or b.can_smoke(1), "fumo: ricarica oltre 40 s")
		b.dispose()
	_check(dmg[0] > 0 and absf(dmg[1] / dmg[0] - BS.SMOKE_MUL) < 0.001, "fumo: danno diretto non ridotto del 30%% (%.3f → %.3f)" % [dmg[0], dmg[1]])
	_check(art[0] > 0 and absf(art[1] - art[0]) < 0.0001, "fumo: l'artiglieria non deve essere ridotta")
	print("  fumo: colpo diretto %.2f → %.2f, artiglieria %.2f → %.2f" % [dmg[0], dmg[1], art[0], art[1]])
	# --- supporto aereo
	var b = BS.new(_setup("pianura", {"inf": 6, "jet": 1}, {"inf": 8, "tank": 3}, 0, 4, {"ah": true}))
	b.emit_fx = true
	var tgt = null
	b.paused = false
	for i in 30:
		b.step(0.05)   # il difensore IA prende posizione (notte 3: i carri manovrano, la fanteria tiene i posti)
	for u in b.units:
		if u.side == 1 and u.type == "inf" and not u.dead and u.hold:
			tgt = u
			break
	var hp0 := 0.0
	for u in b.units:
		if u.side == 1: hp0 += u.hp
	_check(b.human_air_strike(tgt.x, tgt.y), "supporto aereo rifiutato")
	_check(not b.human_air_strike(tgt.x, tgt.y), "supporto aereo: più di un uso")
	b.paused = false
	for i in 80:
		b.step(0.05)
	var hp1 := 0.0
	for u in b.units:
		if u.side == 1: hp1 += u.hp
	var bombs := 0
	for e in b.fx:
		if e["e"] == "bomb": bombs += 1
	_check(bombs == BS.AIR_BOMBS, "supporto aereo: bombe %d" % bombs)
	_check(hp1 < hp0 - 5.0, "supporto aereo: nessun danno (%.1f → %.1f)" % [hp0, hp1])
	print("  supporto aereo: integrità difensore %.0f → %.0f" % [hp0, hp1])
	b.dispose()
	var bn = BS.new(_setup("pianura", {"inf": 6, "tank": 2}, {"inf": 8}, 0, 4, {"ah": true}))
	bn.emit_fx = false
	_check(not bn.human_air_strike(3000, 1350), "supporto aereo senza velivoli né supporto")
	bn.dispose()
	# --- mantieni posizione: con un nemico appena fuori tiro l'unità non insegue
	# (campo piano e sgombro: con il rilievo della Fase 7 una collina o il fiume tra i due cambierebbero l'esito)
	var moved := []
	for hold in [false, true]:
		var bh = BS.new(_setup("pianura", {"inf": 1}, {"inf": 1}, 0, 12, {"ah": true, "clear": true}))
		bh.emit_fx = false
		bh.sides[1]["human"] = true   # niente IA sul bersaglio (non deve schierarsi altrove)
		var me = null
		var en = null
		for u in bh.units:
			if u.side == 0: me = u
			else: en = u
		var y := _clear_y(bh, 1900, 2500)
		me.x = 1960; me.y = y; en.x = 1960 + me.range_ + 60; en.y = y
		en.hold = true
		bh._upd_vis(true)
		bh.select_units([me], false)
		bh.stop()
		if hold:
			_check(bh.hold_position(), "mantieni posizione rifiutato")
			_check(me.hold, "mantieni posizione non applicato")
		var x0: float = me.x
		for i in 40:
			bh.step(0.05)
		moved.append(absf(me.x - x0))
		if hold:
			bh.order_move(1500, y)
			_check(not me.hold, "un nuovo ordine deve annullare 'mantieni posizione'")
		bh.dispose()
	_check(moved[0] > 15.0 and moved[1] < 3.0, "mantieni posizione: spostamento %.1f (libero) / %.1f (fermo)" % [moved[0], moved[1]])
	# --- IA avversaria: usa il fumo sotto forte fuoco (solo con un lato umano)
	var ba = BS.new(_setup("pianura", {"tank": 10}, {"inf": 10}, 0, 5, {"ah": true}))
	ba.emit_fx = false
	ba.select_all()
	var dcx := 0.0
	var dcy := 0.0
	var dn := 0
	ba.step(1.2)   # il difensore IA si schiera
	for u in ba.units:
		if u.side == 1 and not u.dead:
			dcx += u.x; dcy += u.y; dn += 1
	ba.order_attack_move(dcx / dn, dcy / dn)
	var used := false
	for i in 4000:
		ba.step(0.05)
		if ba.sides[1]["smoke_cd"] > 0:
			used = true
			break
		if ba.done:
			break
	_check(used, "IA: il difensore non usa mai il fumo sotto il fuoco")
	ba.dispose()

func _fs(f: Dictionary) -> String:
	var parts := []
	for k in D.UNIT_KEYS:
		if int(f.get(k, 0)) > 0:
			parts.append("%d%s" % [f[k], k])
	return "{" + " ".join(parts) + "}"

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	D = root.get_node_or_null("/root/Data")
	if D == null:
		print("autoload Data assente")
		quit(2)
		return true
	BS = load("res://scripts/battle/battle_sim.gd")
	print("== test_battle ==")
	var r: Dictionary
	# Fase 5: in città la fanteria in copertura e i bunker rendono il difensore molto forte (nel JS 1.45x bastava):
	# 20i8c4a contro 15i6c+3 bunker ora è incerto; il doppio deve vincere.
	r = _run("urbano 20i8c4a vs 15i6c+3bunker", _setup("urbano", {"inf": 20, "tank": 8, "art": 4}, {"inf": 15, "tank": 6}, 3, 7))
	r = _run("urbano 2x: 30i12c6a vs 15i6c+3bunker", _setup("urbano", {"inf": 30, "tank": 12, "art": 6}, {"inf": 15, "tank": 6}, 3, 2))
	# informativo: città + bunker = la posizione più forte del gioco (l'equilibrio statistico è in tests/test_tactics.gd)
	print("  urbano 2x contro bunker: vince ", r.get("winner", "?"))
	r = _run("pianura 10 carri vs 10 eli", _setup("pianura", {"tank": 10}, {"heli": 10}, 0, 3))
	_check(r.get("winner", "") == "def", "10 carri vs 10 eli: gli elicotteri dovrebbero vincere")
	r = _run("pianura 6 aa vs 10 eli", _setup("pianura", {"aa": 6}, {"heli": 10}, 0, 4))
	# come nel JS: gli elicotteri vincono quasi sempre, ma la contraerea ne abbatte più della metà (statistica su 8 seed)
	var hw := 0
	var hs_ := 0
	for sd in 8:
		var rr: Dictionary = _run("  6 aa vs 10 eli seed %d" % (20 + sd), _setup("pianura", {"aa": 6}, {"heli": 10}, 0, 20 + sd))
		if rr.get("winner", "") == "def":
			hw += 1
		hs_ += int(rr.get("def", {}).get("heli", 0))
	print("  aa vs eli: eli vincono %d/8, superstiti medi %.1f" % [hw, hs_ / 8.0])
	# Fase 5: la contraerea (gittata 1100 contro 750) è il vero contrappeso degli elicotteri: ne abbatte più della metà
	_check(hs_ / 8.0 <= 5.0, "6 aa vs 10 eli: la contraerea deve abbattere più della metà degli elicotteri")
	var big := {"inf": 24, "tank": 12, "art": 6, "aa": 6, "heli": 6, "jet": 4, "drone": 2}
	r = _run("foresta 60 vs 60 misti", _setup("foresta", big, big, 0, 5))
	r = _run("deserto 60 vs 60 misti", _setup("deserto", big, big, 0, 11))
	var mix := {"inf": 10, "tank": 5, "art": 2, "aa": 2, "heli": 1}
	var wins := {"att": 0, "def": 0}
	for sd in 6:
		var rr: Dictionary = _run("pianura specchio 20v20 seed %d" % sd, _setup("pianura", mix, mix, 0, 100 + sd))
		if rr.has("winner"):
			wins[rr["winner"]] += 1
	print("  specchio: vittorie ", wins)
	r = _run("montagna 12i4c vs 12i4c + mare", _setup("montagna", {"inf": 12, "tank": 4}, {"inf": 12, "tank": 4}, 0, 9, {"sea": true}))
	r = _run("artico 8i vs 4 jet (stallo?)", _setup("artico", {"inf": 8}, {"jet": 4}, 0, 6))
	r = _run("pianura con sbarramenti e fx", _setup("pianura", {"inf": 14, "tank": 6, "art": 3}, {"inf": 14, "tank": 4}, 0, 8, {"sa": 6, "sd": 4}), true)
	# comandi lato umano
	var b = BS.new(_setup("pianura", {"inf": 8, "tank": 4}, {"inf": 8}, 0, 3, {"ah": true, "sa": 4}))
	b.emit_fx = false
	b.select_all()
	_check(b.sel.size() > 0, "select_all vuoto")
	b.order_move(2400, 1350)
	_check(b.sel[0].order == BS.MOVE, "order_move non applicato")
	b.order_attack_move(3300, 1350)
	_check(b.sel[0].order == BS.AMOVE, "order_attack_move non applicato")
	b.store_group(1)
	b.stop()
	_check(b.sel[0].order == BS.IDLE, "stop non applicato")
	_check(b.human_barrage(3600, 1350), "sbarramento rifiutato")
	_check(not b.human_barrage(3600, 1350), "sbarramento senza ricarica")
	for i in 100:
		b.step(0.05)
	b.recall_group(1)
	_check(b.sel.size() > 0, "gruppo 1 vuoto")
	_check(b.retreat(), "ritirata rifiutata")
	_check(not b.retreat(), "ritirata già in corso rifiutata")
	# ritirata ordinata (omogeneità §1): i reparti ripiegano al bordo e si salvano; la battaglia finisce senza l'attaccante sul campo
	var guard := 0
	while not b.done and guard < 4000:
		b.step(0.1)
		guard += 1
	_check(b.done and b.result["retreated"] and b.result["winner"] == "def", "ritirata: fine con retreated e vittoria del difensore")
	var saved: int = D.total_units(b.escaped[0]["main"])
	_check(saved > 0 and D.total_units(b.result["att"]) >= saved, "ritirata: %d unità salve al bordo (superstiti %d)" % [saved, D.total_units(b.result["att"])])
	print("  ritirata ordinata: salve %d, superstiti %d, durata %.0f s" % [saved, D.total_units(b.result["att"]), b.time])
	b.dispose()
	# schieramento iniziale: le unità finiscono nella zona del proprio lato, senza sovrapporsi
	var bd = BS.new(_setup("foresta", {"inf": 18, "tank": 7, "art": 3}, {"inf": 8}, 0, 5, {"ah": true}))
	bd.emit_fx = false
	bd.select_all()
	bd.order_move(0, 0)
	bd.deploy_place(bd.sel_alive(), 900, 900)
	var z: Rect2 = bd.deploy_zone(0)
	var inside := true
	var overl := 0
	for u in bd.units:
		if u.side == 0 and not u.dead:
			if not z.grow(1.0).has_point(Vector2(u.x, u.y)):
				inside = false
			for o in bd.units:
				if o != u and o.side == 0 and not o.air and not u.air and Vector2(o.x - u.x, o.y - u.y).length() < (o.r + u.r) * 0.6:
					overl += 1
	_check(inside, "schieramento: unità fuori dalla zona")
	_check(overl == 0, "schieramento: unità sovrapposte (%d)" % overl)
	_check(bd.sel[0].order == BS.IDLE, "schieramento: ordine residuo")
	bd.dispose()
	_test_abilities()
	var b2 = BS.new(_setup("urbano", {"inf": 8, "tank": 4}, {"inf": 8}, 2, 3))
	b2.emit_fx = false
	for i in 200:
		b2.step(0.05)
	var ta := Time.get_ticks_msec()
	_check(b2.auto_resolve() and b2.done and b2.result != null and not b2.result["autoRest"], "risoluzione automatica (simulata fino alla fine)")
	print("  auto_resolve a battaglia iniziata: %d ms, esito %s a %.0f s" % [Time.get_ticks_msec() - ta, b2.result["winner"], b2.time])
	b2.dispose()
	# difensore umano: schieramento nella propria metà
	var bdd = BS.new(_setup("foresta", {"inf": 8}, {"inf": 6, "tank": 2}, 0, 6))
	bdd.setup["def"]["human"] = true
	bdd.hs = 1
	bdd.sides[1]["human"] = true
	bdd.emit_fx = false
	var z1: Rect2 = bdd.deploy_zone(1)
	var own1: Array = bdd.own_units()
	bdd.deploy_place(own1, z1.get_center().x, z1.get_center().y)
	var ok1 := true
	for u in own1:
		if not z1.grow(1.0).has_point(Vector2(u.x, u.y)):
			ok1 = false
	_check(own1.size() > 0 and ok1, "schieramento del difensore umano nella sua zona")
	bdd.dispose()
	print("== test_battle: ", "OK" if _fail == 0 else "%d FALLIMENTI" % _fail, " ==")
	quit(0 if _fail == 0 else 1)
	return true
