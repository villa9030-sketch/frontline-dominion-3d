extends SceneTree
## Test headless delle regole tattiche (Fase 5): imboscate, copertura, visibilità, corazze, artiglieria, ricognizione,
## fortificazioni, equilibrio (numeri contro armi combinate) e tempi della risoluzione automatica.
## Uso: node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/test_tactics.gd [-- --quick=1]

var _fail := 0
var D = null
var BS = null
var BR = null
var CB = null
var _ran := false
var quick := false

func _f(d: Dictionary) -> Dictionary:
	var o: Dictionary = D.empty_forces()
	for k in d:
		o[k] = d[k]
	return o

func _setup(terrain: String, a: Dictionary, d: Dictionary, seed := 1, extra := {}) -> Dictionary:
	return {
		"terrIdx": 0, "terrain": terrain, "terrName": "Prova", "sea": false, "seed": seed, "clear": bool(extra.get("clear", false)),
		"att": {"player": 0, "name": "A", "color": Color("#3b82f6"), "forces": _f(a), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": bool(extra.get("ah", false))},
		"def": {"player": 1, "name": "D", "color": Color("#ef4444"), "forces": _f(d), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": bool(extra.get("dh", false)),
			"bunkers": 0, "fort": extra.get("fort", {})},
		"support": {"att": 0, "def": 0},
	}

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  FALLITO: ", msg)
	else:
		print("  ok: ", msg)

func _side(b, si: int, type := "") -> Array:
	return b.units.filter(func(u): return not u.dead and u.side == si and (type == "" or u.type == type))

func _hp(b, si: int) -> float:
	var h := 0.0
	for u in b.units:
		if not u.dead and u.side == si and not u.stat:
			h += u.hp
	return h

func _hp0(b, si: int) -> float:
	var h := 0.0
	for u in b.units:
		if u.side == si and not u.stat:
			h += u.hp_max
	return h

func _run(b, secs: float, dt := 0.1) -> void:
	var n := int(secs / dt)
	for i in n:
		if b.done:
			break
		b.step(dt)
		b.fx.clear()

## Battaglia senza IA (entrambi i lati "umani"): le unità eseguono solo gli ordini del test.
func _manual(a: Dictionary, d: Dictionary, seed := 1) -> Object:
	var b = BS.new(_setup("pianura", a, d, seed, {"clear": true, "ah": true, "dh": true}))
	b.emit_fx = false
	return b

func _place(b, list: Array, x: float, y: float, dy := 40.0, ang := 0.0) -> void:
	for i in list.size():
		var u = list[i]
		u.x = x; u.y = y + (i - (list.size() - 1) / 2.0) * dy
		u.vx = 0; u.vy = 0; u.ang = ang; u.tur = ang
		b.order_unit(u, 0, u.x, u.y, null)
	b._upd_vis(true)

# ---------------------------------------------------------------------------- scenari
func t_ambush() -> void:
	print("- imboscata: 6 fanterie in un bosco contro 3 carri che passano accanto")
	var res := []
	for forest in [true, false]:
		var tl := 0.0
		var il := 0.0
		for sd in 3:
			var b = _manual({"tank": 3}, {"inf": 6}, 10 + sd)
			if forest:
				b.add_forest(2400.0, 1350.0, 170.0)
			var inf := _side(b, 1, "inf")
			_place(b, inf, 2400.0 + 60.0, 1350.0, 45.0, PI)
			for u in inf:
				u.hold = true
			var tk := _side(b, 0, "tank")
			_place(b, tk, 1300.0, 1350.0 + 230.0, 45.0, 0.0)
			for u in tk:
				b.order_unit(u, 1, 3800.0, u.y, null)
			_run(b, 70.0)
			tl += 1.0 - _hp(b, 0) / _hp0(b, 0)
			il += 1.0 - _hp(b, 1) / _hp0(b, 1)
			b.dispose()
		res.append([tl / 3.0, il / 3.0])
		print("    %s: carri persi %.0f%%, fanteria persa %.0f%%" % ["bosco" if forest else "aperto", tl / 3.0 * 100, il / 3.0 * 100])
	_check(res[0][0] >= 0.6, "imboscata nel bosco: i carri perdono almeno il 60%% (%.0f%%)" % (res[0][0] * 100))
	_check(res[0][0] > res[0][1], "imboscata nel bosco: la fanteria vince lo scambio")
	_check(res[1][1] >= 0.7 and res[1][0] < res[0][0] * 0.6, "allo scoperto la stessa fanteria perde (fan %.0f%%, carri %.0f%%)" % [res[1][1] * 100, res[1][0] * 100])

func t_flank() -> void:
	print("- corazza frontale/laterale/posteriore")
	var dm := []
	for dirn in ["front", "side", "rear"]:
		var b = _manual({"tank": 1}, {"tank": 1})
		var me = _side(b, 0)[0]
		var en = _side(b, 1)[0]
		en.x = 2400; en.y = 1350; en.ang = PI   # guarda verso ovest
		var off: Vector2 = {"front": Vector2(-500, 0), "side": Vector2(0, -500), "rear": Vector2(500, 0)}[dirn]
		me.x = en.x + off.x; me.y = en.y + off.y
		b._upd_vis(true)
		var h0: float = en.hp
		b._fire(me, en, 500.0)
		dm.append(h0 - en.hp)
		b.dispose()
	print("    danno fronte %.2f, fianco %.2f, retro %.2f" % dm)
	_check(absf(dm[1] / dm[0] - 1.6) < 0.01 and absf(dm[2] / dm[0] - 2.5) < 0.01, "moltiplicatori 1 / 1.6 / 2.5")
	# dinamico: 3 carri attaccano 3 carri in posizione, di fronte oppure alle spalle
	var won := {"front": 0.0, "rear": 0.0}
	for dirn in ["front", "rear"]:
		for sd in 3:
			var b = _manual({"tank": 3}, {"tank": 3}, 30 + sd)
			var dfn := _side(b, 1)
			_place(b, dfn, 2600.0, 1350.0, 60.0, PI)
			for u in dfn:
				u.hold = true
			var at := _side(b, 0)
			var x0 := 1700.0 if dirn == "front" else 3500.0
			_place(b, at, x0, 1350.0, 60.0, 0.0 if dirn == "front" else PI)
			b.select_units(at, false)
			b.order_attack_move(2600.0, 1350.0)
			_run(b, 40.0)
			won[dirn] += (1.0 - _hp(b, 1) / _hp0(b, 1)) - (1.0 - _hp(b, 0) / _hp0(b, 0))
			b.dispose()
	print("    vantaggio dell'attaccante (perdite nemiche − proprie): fronte %.2f, alle spalle %.2f" % [won["front"] / 3, won["rear"] / 3])
	_check(won["rear"] > won["front"] + 0.6, "attaccare alle spalle rende molto di più")

func t_artillery() -> void:
	print("- artiglieria: gittata lunghissima, dispersione crescente, minima")
	var b = _manual({"art": 1}, {"inf": 1, "tank": 1})
	var a = _side(b, 0, "art")[0]
	var t = _side(b, 1, "tank")[0]
	a.x = 500; a.y = 1350
	var errs := {}
	for dist in [900.0, 3000.0]:
		t.x = a.x + dist; t.y = 1350
		var tot := 0.0
		for i in 40:
			for s in b.shells:
				s.on = false
			b._fire(a, t, dist)
			for s in b.shells:
				if s.on:
					tot += Vector2(s.x1 - t.x, s.y1 - t.y).length()
		errs[dist] = tot / 40.0
	print("    errore medio a 900 px: %.0f, a 3000 px: %.0f (gittata %d, minima %d)" % [errs[900.0], errs[3000.0], a.range_, a.min_range])
	_check(a.range_ >= 3500 and a.min_range >= 400, "gittata quasi tutto il campo, gittata minima")
	_check(errs[3000.0] > 100.0 and errs[3000.0] > errs[900.0] * 1.8, "la dispersione cresce con la distanza")
	b.dispose()

func t_spotting() -> void:
	print("- visibilità: niente fuoco diretto su ciò che non si vede")
	var b = _manual({"tank": 1}, {"inf": 1})
	b.add_forest(2400, 1350, 160)
	var tk = _side(b, 0)[0]
	var inf = _side(b, 1)[0]
	_place(b, [inf], 2400, 1350, 0, PI)
	inf.hold = true
	_place(b, [tk], 2400 - 700, 1350, 0, 0.0)
	tk.hold = true
	_run(b, 3.0)
	_check(not b.visible_to(0, inf) and inf.concealed, "fanteria ferma nel bosco nascosta a 700 px")
	_check(b._find_target(tk, 2000.0) == null, "il carro non trova bersagli non avvistati")
	var h0: float = inf.hp
	_run(b, 20.0)
	_check(inf.hp == h0, "nessun danno all'unità nascosta in 20 s")
	tk.x = 2400 - 480
	b._upd_vis(true)
	_check(b.visible_to(1, tk) and not b.visible_to(0, inf), "a 480 px la fanteria nascosta vede il carro, il carro non vede lei")
	b.select_units([tk], false)
	b.hs = 0
	b.order_attack(inf)
	_check(tk.order == 3, "attacco su nemico invisibile → attacco in movimento")
	b.dispose()
	# una fanteria allo scoperto si vede da lontano
	var b2 = _manual({"tank": 1}, {"inf": 1})
	var t2 = _side(b2, 0)[0]
	var i2 = _side(b2, 1)[0]
	_place(b2, [t2], 1700, 1350, 0, 0.0)
	_place(b2, [i2], 2400, 1350, 0, PI)
	_check(b2.visible_to(0, i2), "fanteria allo scoperto avvistata a 700 px")
	b2.dispose()

func t_contact() -> void:
	print("- contatti (notte 3): posizione nota, tipo ignoto; chi spara si rivela; l'artiglieria batte i contatti")
	var b = _manual({"tank": 1, "art": 1}, {"inf": 2, "tank": 1})
	b.add_forest(3400, 1350, 160)
	var tk = _side(b, 0, "tank")[0]
	var ar = _side(b, 0, "art")[0]
	var infs := _side(b, 1, "inf")
	var etk = _side(b, 1, "tank")[0]
	_place(b, [tk], 1200, 1350, 0, 0.0)
	_place(b, [ar], 600, 1350, 0, 0.0)
	_place(b, [infs[0]], 3400, 1350, 0, PI)       # nel bosco, ferma: nascosta
	_place(b, [infs[1]], 3400, 500, 0, PI)        # allo scoperto
	_place(b, [etk], 3900, 2000, 0, PI)           # allo scoperto, lontanissimo
	for u in b.units:
		u.hold = true
	b._upd_vis(true)
	_check(etk.known[0] and not etk.spotted[0] and infs[1].known[0] and not infs[1].spotted[0], "nemici allo scoperto lontani: contatti noti (posizione) ma non identificati")
	_check(not infs[0].known[0] and infs[0].concealed, "fanteria ferma nel bosco a 2200 px: nemmeno il contatto")
	_check(b.visible_to(0, etk) == false and b._find_target(tk, 5000.0) == null, "niente fuoco diretto su un contatto non identificato")
	b._elist[0] = _side(b, 0); b._elist[1] = _side(b, 1)
	_check(b._find_target(ar, ar.range_) != null, "l'artiglieria può battere un contatto «?»")
	_place(b, [tk], 3400 - BR.CONTACT_R + 100.0, 1350, 0, 0.0)
	_check(infs[0].known[0] and not infs[0].spotted[0], "entro %d px la fanteria nascosta diventa un contatto, non identificata" % int(BR.CONTACT_R))
	_place(b, [tk], 3400 - 200.0, 1350, 0, 0.0)
	_check(infs[0].spotted[0] and infs[0].known[0] and infs[0].id_once[0], "da vicino (200 px) è identificata")
	# chi spara si rivela: la fanteria nel bosco che fa fuoco è identificata entro REVEAL_MIN, e nota ovunque
	_place(b, [tk], 3400 - 400.0, 1350, 0, 0.0)
	_check(not infs[0].spotted[0], "a 400 px, ferma e zitta: solo contatto")
	b._start_shot(infs[0])
	b._upd_vis(true)
	_check(infs[0].spotted[0] and infs[0].reveal_t > BR.REVEAL_T - 0.5, "ha sparato dal bosco: identificata per %d s entro %d px" % [int(BR.REVEAL_T), int(BR.REVEAL_COVER[1])])
	# un carro che spara è identificato da lontano (REVEAL_K × gittata), anche oltre la vista
	_place(b, [etk], 3900, 2000, 0, PI)
	var far_before: bool = etk.spotted[0]
	b._start_shot(etk)
	b._upd_vis(true)
	_check(not far_before and etk.spotted[0], "un carro che spara è identificato fino a %d px" % int(etk.range_ * BR.REVEAL_K))
	etk.reveal_t = 0.0
	_place(b, [tk], 1200, 1350, 0, 0.0)
	_check(infs[0].known[0] and not infs[0].spotted[0], "da 2200 px chi ha sparato è un contatto noto, ma non identificato")
	_run(b, BR.REVEAL_T + 1.0)
	b._upd_vis(true)
	_check(not infs[0].known[0], "dopo %d s senza sparare torna nascosta" % int(BR.REVEAL_T))
	# imboscata: solo il primo colpo, ×AMBUSH_MUL
	_check(absf(BR.AMBUSH_MUL - 1.25) < 0.01, "imboscata ridotta a ×1.25")
	infs[0].hidden_t = BR.AMBUSH_REARM
	infs[0].concealed = true
	var a1: bool = b._start_shot(infs[0])
	var a2: bool = b._start_shot(infs[0])
	_check(a1 and not a2, "bonus d'imboscata solo sul primo colpo")
	# ordine umano su un contatto: l'artiglieria lo prende di mira, gli altri vanno in movimento d'attacco
	b.hs = 0
	b._upd_vis(true)
	b.select_units([tk, ar], false)
	b.order_attack(etk)
	_check(ar.order == 2 and ar.otgt == etk and tk.order == 3, "ordine d'attacco su un «?»: artiglieria = fuoco sul contatto, carro = movimento d'attacco")
	_check(b.unit_at(etk.x + 30.0, etk.y, 1) == etk, "il gettone «?» si può indicare con il clic")
	# lato allo sbando: tutti noti
	b.rout[1] = true
	b._upd_vis(true)
	_check(infs[0].known[0], "lato allo sbando: anche chi è nascosto è un contatto noto")
	b.dispose()

func t_recon() -> void:
	print("- ricognizione: l'artiglieria è precisa solo su ciò che la ricognizione identifica")
	var res := []
	for scout in [false, true]:
		var b = _manual({"art": 3, "heli": 1 if scout else 0}, {"tank": 3})
		var ar := _side(b, 0, "art")
		_place(b, ar, 800, 1350, 60, 0.0)
		var tk := _side(b, 1, "tank")
		_place(b, tk, 3700, 1350, 70, PI)
		for u in tk:
			u.hold = true
		if scout:
			var h = _side(b, 0, "heli")[0]
			_place(b, [h], 3700 - 1460, 1350, 0, 0.0)
			h.hold = true
		_run(b, 90.0)
		res.append(1.0 - _hp(b, 1) / _hp0(b, 1))
		b.dispose()
	print("    danni ai carri a 2900 px: senza ricognizione (contatti «?») %.0f%%, con elicottero (identificati) %.0f%%" % [res[0] * 100, res[1] * 100])
	_check(res[1] > 0.03 and res[1] > res[0] * 1.3, "la ricognizione rende molto più efficace il tiro d'artiglieria")

func t_fort() -> void:
	print("- fortificazioni: trincee e campi minati")
	var b = BS.new(_setup("pianura", {"tank": 4}, {"inf": 4}, 3, {"fort": {"trench": 2, "mines": 2, "bunker": 1}}))
	b.emit_fx = true
	_check(b.trenches.size() >= 4 and b.mines.size() == 4 and b.bunker_pos.size() == 2, "trincee %d, campi minati %d, bunker %d" % [b.trenches.size(), b.mines.size(), b.bunker_pos.size()])
	var t0: Dictionary = b.trenches[0]
	var mx := (float(t0["x0"]) + float(t0["x1"])) / 2.0
	var my := (float(t0["y0"]) + float(t0["y1"])) / 2.0
	_check(b.cover_at(mx, my) == 2 and b.in_trench(mx, my), "trincea = copertura pesante")
	_check(not b.mines[0]["spotted"][0] and b.mines[0]["spotted"][1], "campi minati nascosti all'attaccante")
	# un carro dentro un campo minato
	var m: Dictionary = b.mines[0]
	var tk = _side(b, 0, "tank")[0]
	tk.x = m["x"]; tk.y = m["y"]
	var h0: float = tk.hp
	b.sides[0]["human"] = true
	b.sides[1]["human"] = true
	b.order_unit(tk, 0, tk.x, tk.y, null)
	tk.hold = true
	for i in 60:
		b.step(0.1)
		tk.x = m["x"]; tk.y = m["y"]
	var mfx: int = b.fx.filter(func(e): return e["e"] == "mine").size()
	_check(tk.hp < h0 and mfx > 0 and b.mines[0]["spotted"][0], "il campo minato danneggia il carro e si rivela (%.1f → %.1f)" % [h0, tk.hp])
	# artiglieria su fanteria in trincea vs allo scoperto
	var inf = _side(b, 1, "inf")[0]
	var dmg := []
	for where in ["trench", "open"]:
		inf.x = mx if where == "trench" else 2400.0
		inf.y = my if where == "trench" else 300.0
		b._upd_vis(true)
		var s = BS.Shell.new()
		s.side = 0; s.x1 = inf.x; s.y1 = inf.y; s.dmg = 2.0; s.splash = 60.0
		var hb: float = inf.hp
		b._impact(s)
		dmg.append(hb - inf.hp)
	_check(dmg[0] < dmg[1] * 0.5, "la trincea riduce l'artiglieria sulla fanteria (%.2f vs %.2f)" % dmg)
	b.dispose()
	# schieramento del difensore umano nella propria metà, anche dentro un bosco
	var bd = BS.new(_setup("foresta", {"inf": 6}, {"inf": 6, "tank": 2}, 4, {"dh": true}))
	bd.emit_fx = false
	var z: Rect2 = bd.deploy_zone(1)
	_check(z.position.x >= bd.W * 0.5 and z.end.x <= bd.W, "zona del difensore nella sua metà")
	var fo = null
	for o in bd.forests:
		if z.has_point(Vector2(o["x"], o["y"])) and float(o["R"]) > 110:
			fo = o
			break
	if fo != null:
		var li := _side(bd, 1, "inf").slice(0, 2)
		bd.deploy_place(li, fo["x"], fo["y"])
		_check(li[0].cover >= 1, "fanteria schierata nel bosco in copertura")
	bd.dispose()
	# il difensore IA parte in posizione: fanteria in copertura
	var ba = BS.new(_setup("foresta", {"inf": 8, "tank": 3}, {"inf": 8, "tank": 3, "art": 1}, 5))
	ba.emit_fx = false
	ba.step(1.2)
	var inc := 0
	for u in _side(ba, 1, "inf"):
		if u.cover > 0: inc += 1
	_check(inc >= 6, "IA difensore: fanteria in copertura all'inizio (%d/8)" % inc)
	ba.dispose()

func t_relief() -> void:
	print("- rilievo (Fase 7): linee di vista dietro le creste, vista dall'alto, fuoco diretto")
	# cresta nord-sud alta 20 m in x = 2400 (semilarghezza 300 px = 75 m) tra due carri a 700 px
	var b = _manual({"tank": 1, "heli": 1}, {"tank": 1})
	b.relief.add_ridge(2400.0, 300.0, 20.0)
	var a = _side(b, 0, "tank")[0]
	var e = _side(b, 1, "tank")[0]
	var h = _side(b, 0, "heli")[0]
	_place(b, [a], 2050, 1350, 0, 0.0)
	_place(b, [e], 2750, 1350, 0, PI)
	_place(b, [h], 300, 400, 0, 0.0)
	a.hold = true; e.hold = true
	b._upd_vis(true)
	b._elist[0] = _side(b, 0); b._elist[1] = _side(b, 1)
	print("    quote: carro A %.1f m, cresta %.1f m, carro B %.1f m" % [b.height_at(a.x, a.y), b.height_at(2400, 1350), b.height_at(e.x, e.y)])
	_check(not b.visible_to(0, e) and not b.visible_to(1, a), "carri ai due lati di una cresta: nessuno vede l'altro (700 px < vista 850)")
	_check(b._find_target(a, 2000.0) == null, "nessun bersaglio oltre la cresta")
	_check(not b.has_los(a.x, a.y, e.x, e.y) and b.has_los(a.x, a.y, a.x, a.y + 600), "has_los: bloccata dalla cresta, libera lungo il versante")
	# un elicottero vede oltre la cresta
	_place(b, [h], 2050, 1300, 0, 0.0)
	_check(b.visible_to(0, e), "l'elicottero vede il carro dietro la cresta")
	_place(b, [h], 300, 400, 0, 0.0)
	# A sale sulla cresta: vede e si fa vedere, e può sparare
	_place(b, [a], 2400, 1350, 0, 0.0)
	_check(b.visible_to(0, e) and b.visible_to(1, a), "dalla cresta il carro vede (ed è visto)")
	_check(b._find_target(a, 2000.0) == e, "dalla cresta il carro ingaggia il bersaglio")
	b.dispose()
	# fuoco diretto bloccato: B in vista grazie all'elicottero, ma A (dietro la cresta) non può sparargli
	var bf = _manual({"tank": 1, "heli": 1}, {"tank": 1})
	bf.relief.add_ridge(2400.0, 300.0, 20.0)
	var fa = _side(bf, 0, "tank")[0]
	var fe = _side(bf, 1, "tank")[0]
	var fh = _side(bf, 0, "heli")[0]
	_place(bf, [fa], 2050, 1350, 0, 0.0)
	_place(bf, [fe], 2750, 1350, 0, PI)
	_place(bf, [fh], 2400, 900, 0, 0.0)
	fa.hold = true; fe.hold = true; fh.hold = true
	fh.M = {}   # l'elicottero osserva soltanto
	fe.M = {}
	var h0: float = fe.hp
	_run(bf, 8.0)
	_check(bf.visible_to(0, fe) and fe.hp == h0, "bersaglio avvistato da altri ma dietro la cresta: niente fuoco diretto (%.1f → %.1f)" % [h0, fe.hp])
	bf.dispose()
	# posizione dominante: da 20 m più in alto si vede ~30% più lontano
	var res := []
	for hill in [true, false]:
		var bh = _manual({"tank": 1}, {"tank": 1})
		if hill:
			bh.relief.add_hill(1500.0, 1350.0, 500.0, 20.0)
		var v = _side(bh, 0)[0]
		var t = _side(bh, 1)[0]
		_place(bh, [v], 1650, 1350, 0, 0.0)
		_place(bh, [t], 2600, 1350, 0, PI)
		v.hold = true; t.hold = true
		bh._upd_vis(true)
		res.append([bh.visible_to(0, t), bh.visible_to(1, v)])
		bh.dispose()
	_check(res[0][0] and not res[1][0], "dalla collina (+19 m) il carro vede a 950 px (vista 850), in piano no")
	_check(not res[0][1], "dal basso il bersaglio non vede chi sta in alto alla stessa distanza")
	# i terreni veri hanno rilievo
	for tk in ["pianura", "montagna", "deserto", "artico"]:
		var bt = BS.new(_setup(tk, {"inf": 2}, {"inf": 2}, 9))
		var r = bt.relief
		print("    %-9s quote %.1f … %.1f m" % [tk, r.hmin, r.hmax])
		_check(r.hmax - r.hmin > (25.0 if tk == "montagna" else 10.0), "%s: rilievo di almeno %d m" % [tk, 25 if tk == "montagna" else 10])
		bt.dispose()
	# fiume (pianura): ponte dove passa la strada e un guado; nell'alveo si guada (lenti), sugli attraversamenti no
	var RL = load("res://scripts/battle/battle_relief.gd")
	var bp = BS.new(_setup("pianura", {"tank": 1}, {"inf": 1}, 11))
	var rvs: Array = bp.relief.rivers
	_check(rvs.size() == 1 and bool(rvs[0]["water"]) and bp.relief.has_water, "pianura: un fiume con acqua")
	if rvs.size() == 1:
		var rv: Dictionary = rvs[0]
		var xg: Array = rv["xings"]
		var nb := 0
		var nf := 0
		for c in xg:
			if String(c["k"]) == "bridge":
				nb += 1
			else:
				nf += 1
		print("    fiume x≈%.0f: %d ponti, %d guadi" % [float(rv["x"]), nb, nf])
		_check(nb >= 1 and nf >= 1, "fiume: almeno un ponte (sulla strada) e un guado")
		var yy := float(bp.TOP) + 100.0
		var mid_y := -1.0
		while yy < float(bp.BOTTOM) - 100.0:
			var far := true
			for c in xg:
				if absf(float(c["y"]) - yy) < 200.0:
					far = false
			if far:
				mid_y = yy
				break
			yy += 50.0
		var rx: float = RL.river_x(rv, mid_y)
		_check(bp.water_at(rx, mid_y) > 0.5, "in mezzo al fiume c'è acqua (water_at %.2f)" % bp.water_at(rx, mid_y))
		_check(bp.water_at(float(xg[0]["x"]), float(xg[0]["y"])) == 0.0, "sull'attraversamento (%s) niente acqua" % String(xg[0]["k"]))
		_check(bp.water_at(rx + float(rv["vw"]), mid_y) == 0.0, "fuori dall'alveo asciutto")
		_check(bp.height_at(rx, mid_y) < bp.height_at(rx + float(rv["vw"]), mid_y) - 1.0, "l'alveo è più basso delle sponde")
	bp.dispose()

# ---------------------------------------------------------------------------- equilibrio (IA contro IA, come la risoluzione automatica)
func _auto(terrain: String, a: Dictionary, d: Dictionary, seed: int, clear := false) -> Dictionary:
	var b = BS.new(_setup(terrain, a, d, seed, {"clear": clear}))
	var r: Dictionary = b.run_headless()
	r["t"] = b.time
	b.dispose()
	return r

func _series(name: String, terrain: String, a: Dictionary, d: Dictionary, n: int, clear := false) -> float:
	var w := 0
	var tt := 0.0
	var why := {}
	for sd in n:
		var r := _auto(terrain, a, d, 500 + sd * 13, clear)
		if r["winner"] == "att":
			w += 1
		tt += float(r["t"])
		var wk: String = "%s:%s" % [r["winner"], String(r.get("why", "")) if String(r.get("why", "")) != "" else "annientato"]
		why[wk] = int(why.get(wk, 0)) + 1
	print("    %-44s attaccante vince %d/%d (durata media %.0f s) %s" % [name, w, n, tt / n, str(why)])
	return float(w) / n

func t_balance() -> void:
	print("- equilibrio (IA contro IA come nella risoluzione automatica, %d seed per caso)" % (8 if quick else 16))
	var n := 8 if quick else 16
	var small := {"inf": 6, "tank": 3, "art": 1}
	var big := {"inf": 12, "tank": 6, "art": 2}
	var w2 := _series("2x in campo aperto", "pianura", big, small, n, true)
	_check(w2 >= 0.85, "un esercito doppio vince quasi sempre in campo aperto")
	# specchio a forze pari su terreno misto (boschi), senza fortificazioni: il difensore deve vincere più spesso, ma non sempre
	var m1 := _series("specchio 6f3c1a (pianura con boschi)", "pianura", small, small, n)
	var mid := {"inf": 10, "tank": 5, "art": 2}
	var m2 := _series("specchio 10f5c2a (pianura con boschi)", "pianura", mid, mid, n)
	var m3 := _series("specchio 10f5c (foresta)", "foresta", {"inf": 10, "tank": 5}, {"inf": 10, "tank": 5}, n)
	var mm := (m1 + m2 + m3) / 3.0
	print("    specchio: il difensore vince il %.0f%% (obiettivo 60–65%%)" % ((1.0 - mm) * 100))
	# notte 3: la composizione pesa (eserciti piccoli e senza artiglieria favoriscono chi attacca); il controllo per mappa è in t_maps
	_check(mm >= 0.2 and mm <= 0.6, "specchio: nessuno dei due lati domina (difensore %.0f%%, accettato 40–80%%)" % ((1.0 - mm) * 100))
	var w15 := _series("1.5x misto contro misto (pianura)", "pianura", {"inf": 9, "tank": 5, "art": 2}, small, n)
	_check(w15 >= 0.75, "con 1.5x l'attaccante vince chiaramente")
	var comb := {"inf": 8, "tank": 3, "art": 2, "aa": 1, "heli": 1}
	var pc: float = CB.force_power(_f(comb))
	var nt := roundi(pc * 1.3 / 3.0)
	var tanks := {"tank": nt}
	print("    armi combinate %.1f contro %d carri (%.1f, ×%.2f)" % [pc, nt, CB.force_power(_f(tanks)), CB.force_power(_f(tanks)) / pc])
	# notte 3: con i contatti «?» e gli obiettivi allo scoperto al centro, una massa di soli carri 1.3× sfonda anche nel bosco
	# (prima vinceva ≤ 50%: il difensore la logorava con le imboscate). Resta il controllo a potenza pari.
	var wt := _series("informativo: solo carri 1.3x → armi combinate (foresta)", "foresta", tanks, comb, n)
	var nt1 := roundi(pc / 3.0)
	var wt1 := _series("informativo: solo carri 1.0x → armi combinate (foresta)", "foresta", {"tank": nt1}, comb, n)
	print("    (soli carri contro armi combinate nel bosco: l'attaccante vince il %.0f%% a potenza pari, il %.0f%% a 1.3x)" % [wt1 * 100, wt * 100])
	var wa := _series("informativo: specchio con contraerea ed elicotteri", "pianura", {"inf": 10, "tank": 5, "art": 2, "aa": 2, "heli": 1}, {"inf": 10, "tank": 5, "art": 2, "aa": 2, "heli": 1}, n)
	print("    (con contraerea ed elicotteri il difensore è più forte: vince il %.0f%%)" % ((1.0 - wa) * 100))

## Fazioni (omogeneità §6): stesso esercito, modificatori di fazione in battaglia (FO carri +20% hp e artiglieria +25%;
## UL guerriglia +10% in difesa in bosco/città; AAN e CP neutri sul campo). Informativo + controllo di sbilanciamento.
func t_factions() -> void:
	var n := 6 if quick else 12
	print("- fazioni: specchio 8f4c2a in foresta, %d seed per caso (attacco e difesa)" % n)
	var army := {"inf": 8, "tank": 4, "art": 2}
	var res := {}
	for fi in Data.FACTIONS.size():
		var fm: Dictionary = Data.FACTIONS[fi]["mods"]
		var wa := 0
		var wd := 0
		for sd in n:
			for role in ["att", "def"]:
				var s := _setup("foresta", army, army, 700 + sd * 7)
				var side: Dictionary = s[role]
				var mods: Dictionary = side["mods"]
				if fm.get("tankHp"):
					mods["hp"] = {"tank": float(fm["tankHp"])}
				if fm.get("artAtk"):
					mods["unit"] = {"art": float(fm["artAtk"])}
				if fm.get("guerrilla") and role == "def":
					mods["atk"] = float(mods["atk"]) * float(fm["guerrilla"])
				side["faction"] = fi
				var b = BS.new(s)
				var r: Dictionary = b.run_headless()
				b.dispose()
				if r["winner"] == role:
					if role == "att":
						wa += 1
					else:
						wd += 1
		res[fi] = [wa, wd]
		print("    %-4s attacca e vince %d/%d · difende e vince %d/%d" % [Data.FACTIONS[fi]["short"], wa, n, wd, n])
	var lo := 1e9
	var hi := -1e9
	for fi in res:
		var tot: float = float(res[fi][0] + res[fi][1]) / (2.0 * n)
		lo = minf(lo, tot); hi = maxf(hi, tot)
	print("    forbice tra le fazioni (vittorie complessive): %.0f%% … %.0f%%" % [lo * 100, hi * 100])
	_check(hi - lo <= 0.3, "nessuna fazione sbilanciata oltre 30 punti (forbice %.0f)" % ((hi - lo) * 100))

## Metrica del divertimento (notte 3): battaglie tipiche IA contro IA a passo reale (0.1 s), viste dal lato `pv`.
##  - primo contatto: primo nemico noto (gettone "?" o identificato) · primo colpo (anche d'artiglieria alla cieca)
##  - primo scontro: primo colpo di FUOCO DIRETTO (le due parti si vedono e si sparano)
##  - scontro in corso: % dei secondi con almeno un colpo MIRATO a un nemico noto negli ultimi 4 s (fuoco diretto, o
##    artiglieria su un'unità nota; il fuoco d'area alla cieca non conta); tra parentesi il solo fuoco diretto
##  - senza nemici noti: secondi (e finestra più lunga) in cui il lato non conosce la posizione di nessun nemico
##  - cambi di possesso degli obiettivi
func _fun_one(terrain: String, forces: Dictionary, seed: int, buildings: Array) -> Dictionary:
	var s := _setup(terrain, forces, forces, seed)
	s["buildings"] = buildings
	var b = BS.new(s)
	b.emit_fx = true
	var has_known: bool = "known" in b.units[0]
	var first_known := [-1.0, -1.0]
	var first_fire := -1.0
	var first_direct := -1.0
	var last_fire := -100.0
	var last_direct := -100.0
	var fight_d := 0.0
	var fight := 0.0
	var blind := [0.0, 0.0]
	var win := [0.0, 0.0]
	var win_max := [0.0, 0.0]
	var flips := 0
	var owners := []
	for o in b.objectives:
		owners.append(int(o["owner"]))
	var dt := 0.1
	while not b.done and b.ending == null and b.time < 300.0:
		b.step(dt)
		for e in b.fx:
			if e["e"] == "fire":
				if first_fire < 0.0:
					first_fire = b.time
				if e.has("t"):
					last_direct = b.time
					if first_direct < 0.0:
						first_direct = b.time
				if e.has("t") or bool(e.get("aimed", false)):
					last_fire = b.time
		b.fx.clear()
		if b.time - last_fire <= 4.0:
			fight += dt
		if b.time - last_direct <= 4.0:
			fight_d += dt
		for si in 2:
			var any := false
			for u in b.units:
				if u.dead or u.side == si or u.stat:
					continue
				if u.spotted[si] or (has_known and u.known[si]):
					any = true
					break
			if any:
				if first_known[si] < 0.0:
					first_known[si] = b.time
				win[si] = 0.0
			else:
				blind[si] += dt
				win[si] += dt
				win_max[si] = maxf(win_max[si], win[si])
		for i in b.objectives.size():
			var w := int(b.objectives[i]["owner"])
			if w != owners[i]:
				owners[i] = w
				flips += 1
	var T: float = maxf(1.0, b.time)
	var r := {"t": T, "first_known": first_known[0], "first_fire": first_fire, "first_direct": first_direct, "fight": fight / T, "fight_d": fight_d / T, "blind": blind[0], "blind_max": win_max[0],
		"blind_d": blind[1], "blind_max_d": win_max[1], "flips": flips, "objs": b.objectives.size(),
		"winner": String(b.ending["winner"]) if b.ending != null else "?"}
	b.dispose()
	return r

func t_fun() -> void:
	print("- metrica del divertimento (IA contro IA, passo 0.1 s, specchio 10f5c2a; lato attaccante)")
	var army := {"inf": 10, "tank": 5, "art": 2}
	var tf := 0.0
	var tk := 0.0
	var fg := 0.0
	var fgd := 0.0
	var bl := 0.0
	var bm := 0.0
	var bmd := 0.0
	var fl := 0.0
	var n := 0
	var worst_fire := 0.0
	for terrain in ["pianura", "foresta", "montagna", "deserto", "artico", "urbano"]:
		for k in (1 if quick else 2):
			var r := _fun_one(terrain, army, 900 + k * 17, ["fabbrica", "caserma"] if k == 1 else [])
			print("    %-9s seed %d: noto a %5.1f s · primo colpo %5.1f s · scontro diretto da %5.1f s · scontro in corso %3.0f%% (diretto %3.0f%%) · senza nemici noti %5.1f s (max %5.1f; dif. max %5.1f) · cambi %d/%d ob. · %3.0f s vince %s" % [
				terrain, k, r["first_known"], r["first_fire"], r["first_direct"], r["fight"] * 100, r["fight_d"] * 100, r["blind"], r["blind_max"], r["blind_max_d"], r["flips"], r["objs"], r["t"], r["winner"]])
			var ff: float = r["first_direct"] if r["first_direct"] >= 0.0 else 300.0
			tf += ff; tk += (r["first_known"] if r["first_known"] >= 0.0 else 300.0)
			worst_fire = maxf(worst_fire, ff)
			fg += r["fight"]; fgd += r["fight_d"]; bl += r["blind"]; bm = maxf(bm, r["blind_max"]); bmd = maxf(bmd, r["blind_max_d"]); fl += r["flips"]; n += 1
	print("    MEDIA: nemico noto a %.1f s · primo scontro diretto a %.1f s (peggiore %.1f) · scontro in corso %.0f%% (solo fuoco diretto %.0f%%) · senza nemici noti %.1f s · finestra peggiore %.1f s (dif. %.1f) · cambi di possesso %.1f" % [
		tk / n, tf / n, worst_fire, fg / n * 100, fgd / n * 100, bl / n, bm, bmd, fl / n])
	if "known" in BS.Unit.new():
		_check(tf / n < 30.0, "primo scontro in media entro 30 s (%.1f)" % (tf / n))
		_check(fg / n > 0.6, "scontro in corso per più del 60%% del tempo (%.0f%%)" % (fg / n * 100))
		_check(bm <= 40.0 and bmd <= 40.0, "nessuna finestra oltre 40 s senza nemici noti (att. %.1f, dif. %.1f)" % [bm, bmd])

## Difensore a forze pari su tutte le mappe (obiettivo 60–70%).
func t_maps() -> void:
	var n := 8 if quick else 16
	print("- difensore a forze pari per mappa (specchio 10f5c2a, %d seed)" % n)
	var army := {"inf": 10, "tank": 5, "art": 2}
	var tot := 0.0
	var lo := 1.0
	var hi := 0.0
	var terrs := ["pianura", "foresta", "montagna", "deserto", "artico", "urbano"]
	for terrain in terrs:
		var d := 1.0 - _series("specchio su " + terrain, terrain, army, army, n)
		tot += d; lo = minf(lo, d); hi = maxf(hi, d)
	print("    difensore: media %.0f%%, da %.0f%% a %.0f%%" % [tot / terrs.size() * 100, lo * 100, hi * 100])
	_check(tot / terrs.size() >= 0.55 and tot / terrs.size() <= 0.75, "difensore in media tra 55 e 75%% (%.0f%%)" % (tot / terrs.size() * 100))
	_check(lo >= 0.4 and hi <= 0.88, "nessuna mappa fuori scala (%.0f%%…%.0f%%)" % [lo * 100, hi * 100])

func t_timing() -> void:
	print("- tempi della risoluzione automatica (Combat.resolve_battle con contesto tattico)")
	var cases := [
		["tipica 15 vs 10 (pianura)", "pianura", {"inf": 8, "tank": 4, "art": 2, "aa": 1}, {"inf": 6, "tank": 3, "art": 1}],
		["piccola 6 vs 4 (foresta)", "foresta", {"inf": 4, "tank": 2}, {"inf": 3, "tank": 1}],
		["urbana 20 vs 14", "urbano", {"inf": 12, "tank": 5, "art": 3}, {"inf": 10, "tank": 4}],
		["60 vs 60 (deserto)", "deserto", {"inf": 24, "tank": 12, "art": 6, "aa": 6, "heli": 6, "jet": 4, "drone": 2}, {"inf": 24, "tank": 12, "art": 6, "aa": 6, "heli": 6, "jet": 4, "drone": 2}],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for c in cases:
		var ma := {"atk": 1.0, "unit": {}, "hp": {}, "ctx": {"ter": c[1], "role": "att"}}
		var md := {"atk": 1.0, "unit": {}, "hp": {}, "ctx": {"ter": c[1], "role": "def", "bunkers": 0}}
		var worst := 0
		var tot := 0
		for k in 3:
			var t0 := Time.get_ticks_msec()
			var r: Dictionary = CB.resolve_battle(_f(c[2]), _f(c[3]), ma, md, rng)
			var ms := Time.get_ticks_msec() - t0
			tot += ms
			worst = maxi(worst, ms)
			if k == 0:
				print("    %-28s %4d ms  vince %s  (motore: %s)" % [c[0], ms, r["winner"], r.get("engine", "?")])
		print("    %-28s media %d ms, peggiore %d ms" % ["", tot / 3, worst])

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	D = root.get_node_or_null("/root/Data")
	BS = load("res://scripts/battle/battle_sim.gd")
	BR = load("res://scripts/battle/battle_rules.gd")
	CB = load("res://scripts/core/combat.gd")
	for a in OS.get_cmdline_user_args():
		if a == "--quick=1":
			quick = true
		if a == "--flat=1":
			# confronto: tutti i campi piani (rilievo della Fase 7 spento)
			load("res://scripts/battle/battle_relief.gd").disabled = true
			print("(rilievo spento: --flat=1)")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	print("== test_tactics ==")
	for t in ["ambush", "flank", "artillery", "spotting", "contact", "recon", "fort", "relief", "fun", "maps", "balance", "factions", "timing"]:
		if only == "" or only.split(",").has(t):
			call("t_" + t)
	print("== test_tactics: ", "OK" if _fail == 0 else "%d FALLIMENTI" % _fail, " ==")
	quit(0 if _fail == 0 else 1)
	return true
