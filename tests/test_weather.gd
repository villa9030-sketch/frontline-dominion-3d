extends SceneTree
## Test headless del meteo di battaglia (Fase 8): piano deterministico dal seed, moltiplicatore unico della vista
## applicato a tutte le unità, cambiamenti programmati, razzi illuminanti che ripristinano la vista, macerie = copertura.
##   node tools/godot_run.js -- --headless --path . --script tests/test_weather.gd

var _fail := 0
var D = null
var BS = null
var BR = null

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("  FALLITO: ", msg)
	else:
		print("  ok: ", msg)

func _f(d: Dictionary) -> Dictionary:
	var o: Dictionary = D.empty_forces()
	for k in d:
		o[k] = d[k]
	return o

func _setup(terrain: String, seed: int, weather = null) -> Dictionary:
	var s := {
		"terrIdx": 0, "terrain": terrain, "terrName": "Prova", "sea": false, "seed": seed,
		"att": {"player": 0, "name": "A", "color": Color("#3b82f6"), "forces": _f({"inf": 6, "tank": 4, "heli": 1}), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": false},
		"def": {"player": 1, "name": "D", "color": Color("#ef4444"), "forces": _f({"inf": 6, "tank": 3}), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": false, "bunkers": 0},
		"support": {"att": 0, "def": 0},
	}
	if weather != null:
		s["weather"] = weather
	return s

func _initialize() -> void:
	D = root.get_node_or_null("Data")
	BS = load("res://scripts/battle/battle_sim.gd")
	BR = load("res://scripts/battle/battle_rules.gd")
	if D == null:
		print("autoload Data assente")
		quit(1)
		return
	print("[meteo] piano deterministico dal seed")
	var p1: Dictionary = BR.weather_plan(42, "pianura")
	var p2: Dictionary = BR.weather_plan(42, "pianura")
	_check(p1["start"] == p2["start"] and str(p1["changes"]) == str(p2["changes"]), "stesso seed → stesso piano (%s %s)" % [p1["start"], str(p1["changes"])])
	var kinds := {}
	var changes := 0
	for sd in 200:
		var pl: Dictionary = BR.weather_plan(sd, "pianura")
		kinds[pl["start"]] = int(kinds.get(pl["start"], 0)) + 1
		changes += (pl["changes"] as Array).size()
		_check(BR.WEATHER_VIEW.has(pl["start"]), "condizione valida") if not BR.WEATHER_VIEW.has(pl["start"]) else null
		for ch in pl["changes"]:
			if float(ch[0]) < 70.0 or float(ch[0]) > 200.0 or not BR.WEATHER_VIEW.has(ch[1]):
				_check(false, "cambiamento fuori regola %s" % str(ch))
	print("  distribuzione su 200 seed (pianura): ", kinds, "  cambiamenti ", changes)
	_check(kinds.size() >= 4 and changes > 20, "varietà di condizioni e qualche cambiamento")
	var pa: Dictionary = BR.weather_plan(7, "artico")
	_check(pa["start"] != "pioggia" and pa["start"] != "temporale", "artico: niente pioggia (%s)" % pa["start"])
	var snow_any := false
	for sd in 60:
		if BR.weather_plan(sd, "artico")["start"] == "neve":
			snow_any = true
	_check(snow_any, "artico: la neve esiste")

	print("[meteo] senza chiave weather la sim resta serena (test e formula strategica)")
	var b0 = BS.new(_setup("pianura", 5))
	_check(b0.weather == "sereno" and absf(b0.weather_view_mul - 1.0) < 1e-6, "sereno, moltiplicatore 1")
	var v0 := {}
	for u in b0.units:
		v0[u.id] = u.view
	b0.dispose()

	print("[meteo] moltiplicatore della vista applicato a tutte le unità")
	var bn = BS.new(_setup("pianura", 5, "nebbia"))
	var mul: float = BR.WEATHER_VIEW["nebbia"]
	_check(bn.weather == "nebbia" and absf(bn.weather_view_mul - mul) < 1e-6, "nebbia impostata (×%.2f)" % mul)
	var okv := true
	for u in bn.units:
		if not v0.has(u.id):
			continue
		if absf(u.view - float(v0[u.id]) * mul) > 0.01:
			okv = false
			print("    unità %s vista %.1f attesa %.1f" % [u.type, u.view, float(v0[u.id]) * mul])
	_check(okv, "vista di ogni unità (terra e aria) = vista serena × moltiplicatore")
	# cambio in corsa: set_weather aggiorna subito e annuncia
	bn.emit_fx = true
	bn.set_weather("sereno")
	var ann := false
	for e in bn.fx:
		if e["e"] == "weather" and e["kind"] == "sereno":
			ann = true
	_check(ann and absf(bn.weather_view_mul - 1.0) < 1e-6, "set_weather annuncia l'evento fx e ripristina la vista")
	bn.dispose()

	print("[meteo] piano automatico e cambiamenti programmati")
	var found_change := false
	for sd in range(1, 40):   # seed 0 → la sim usa 12345
		var plan: Dictionary = BR.weather_plan(sd, "foresta")
		if (plan["changes"] as Array).is_empty():
			continue
		var ba = BS.new(_setup("foresta", sd, "auto"))
		_check(ba.weather == plan["start"], "avvio col piano (%s)" % plan["start"])
		var tch: float = plan["changes"][0][0]
		var kch: String = plan["changes"][0][1]
		var steps := int((tch + 2.0) / 0.5)
		for i in steps:
			if ba.done:
				break
			ba.step(0.5)
			ba.fx.clear()
		if not ba.done:
			_check(ba.weather == kch, "a t=%.0f s il meteo è passato a %s" % [ba.time, kch])
			_check(absf(ba.weather_view_mul - float(BR.WEATHER_VIEW[kch])) < 1e-6, "moltiplicatore aggiornato")
		found_change = true
		ba.dispose()
		break
	_check(found_change, "trovato un piano con cambiamento")

	print("[meteo] notte: razzi illuminanti e vista ripristinata nell'area")
	var bt = BS.new(_setup("pianura", 9, "notte"))
	bt.emit_fx = true
	var flares := 0
	var t := 0.0
	while t < 60.0 and not bt.done:
		bt.step(0.25)
		t += 0.25
		for e in bt.fx:
			if e["e"] == "flare":
				flares += 1
		bt.fx.clear()
	_check(flares >= 2, "in 60 s di notte partono razzi illuminanti (%d)" % flares)
	# unità nemica appena oltre la vista notturna ma dentro quella piena: visibile solo sotto il razzo
	var bl = BS.new(_setup("pianura", 11, "notte"))
	bl.emit_fx = false
	var a = null
	var e2 = null
	for u in bl.units:
		if u.side == 0 and u.type == "tank" and a == null: a = u
		if u.side == 1 and u.type == "tank" and e2 == null: e2 = u
	# campo libero: li mettiamo su una riga lontana dagli ostacoli (la notte dimezza la vista: 850 → ~467 px)
	var BRd = bl.relief
	if BRd != null:
		BRd.disabled = true
	var y := 1350.0
	a.x = 1200.0; a.y = y; a.vx = 0; a.vy = 0
	e2.x = a.x + 700.0; e2.y = y; e2.vx = 0; e2.vy = 0
	for u in bl.units:
		if u != a and u != e2:
			u.x = 100.0 if u.side == 0 else 4700.0
			u.y = 200.0
	bl.flares.clear()
	bl._upd_vis(true)
	var seen_dark: bool = e2.spotted[0]
	bl.add_flare(e2.x, e2.y, 0)
	bl._upd_vis(true)
	var seen_lit: bool = e2.spotted[0]
	_check(not seen_dark and seen_lit, "carro a 700 px: invisibile di notte (%s), visibile sotto il razzo (%s)" % [str(seen_dark), str(seen_lit)])
	bl.dispose()
	bt.dispose()

	print("[meteo] macerie = copertura pesante")
	var bm = BS.new(_setup("pianura", 3))
	var cx := 2400.0
	var cy := 1350.0
	var c0: int = bm.cover_at(cx, cy)
	bm.add_rubble(cx, cy, 40.0)
	_check(bm.cover_at(cx, cy) == 2, "copertura nel punto delle macerie: %d → %d" % [c0, bm.cover_at(cx, cy)])
	_check(bm.cover_at(cx + 200.0, cy + 200.0) <= 2, "fuori dalle macerie invariata")
	bm.dispose()

	print("[meteo] esito: %s" % ("OK" if _fail == 0 else "%d errori" % _fail))
	quit(1 if _fail > 0 else 0)
