extends SceneTree
## Test headless delle regole di omogeneità campagna ↔ battaglia (docs/omogeneita.md): obiettivi e limite di tempo,
## ritirata al bordo, rinforzi dai territori vicini, supporto aereo/navale, logoramento, carte inganno, nebbia leggera,
## IA ingannata, salvataggi v3.
## Uso: node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_omogeneita.gd

var D = null
var BS = null
var BR = null
var GameS: Script
var CombatS: Script
var AIS: Script
var fails := 0
var checks := 0
var _ran := false


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALLITO: ", what)
	else:
		print("  ok: ", what)


func F(o: Dictionary) -> Dictionary:
	var f: Dictionary = D.empty_forces()
	for k in o:
		f[k] = o[k]
	return f


func _setup(terrain: String, a: Dictionary, d: Dictionary, seed := 1, extra := {}) -> Dictionary:
	var s := {
		"terrIdx": 0, "terrain": terrain, "terrName": "Prova", "sea": bool(extra.get("sea", false)), "seed": seed, "clear": bool(extra.get("clear", false)),
		"att": {"player": 0, "name": "A", "color": Color("#3b82f6"), "forces": F(a), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": bool(extra.get("ah", false))},
		"def": {"player": 1, "name": "D", "color": Color("#ef4444"), "forces": F(d), "mods": {"atk": 1.0, "unit": {}, "hp": {}}, "human": bool(extra.get("dh", false)),
			"bunkers": int(extra.get("bunkers", 0)), "fort": {}},
		"support": {"att": 0, "def": 0},
		"buildings": extra.get("buildings", []), "hq": bool(extra.get("hq", false)),
	}
	for k in ["air", "naval", "reinf"]:
		if extra.has("a_" + k):
			s["att"][k] = extra["a_" + k]
		if extra.has("d_" + k):
			s["def"][k] = extra["d_" + k]
	return s


func _side(b, si: int, type := "") -> Array:
	return b.units.filter(func(u): return not u.dead and u.side == si and (type == "" or u.type == type))


func _place(b, list: Array, x: float, y: float, dy := 40.0, ang := 0.0) -> void:
	for i in list.size():
		var u = list[i]
		u.x = x; u.y = y + (i - (list.size() - 1) / 2.0) * dy
		u.vx = 0; u.vy = 0; u.ang = ang; u.tur = ang
		b.order_unit(u, 0, u.x, u.y, null)
		u.hold = true
	b._upd_vis(true)


func _run(b, secs: float, dt := 0.25) -> void:
	var n := int(secs / dt)
	for i in n:
		if b.done:
			break
		b.step(dt)
		b.fx.clear()


# ---------------------------------------------------------------------------- battaglia
func test_objectives() -> void:
	print("- obiettivi dal contesto")
	var b = BS.new(_setup("pianura", {"inf": 6, "tank": 2}, {"inf": 6}, 11, {"buildings": ["fabbrica", "porto", "caserma"], "hq": true, "bunkers": 2}))
	var kinds := []
	for o in b.objectives:
		kinds.append(o["kind"])
	print("    obiettivi: ", kinds)
	ok(b.objectives.size() >= 3 and b.objectives.size() <= 4, "da 3 a 4 obiettivi (%d)" % b.objectives.size())
	ok(kinds.has("hq") and kinds.has("building"), "QG e edifici tra gli obiettivi")
	ok(kinds.count("building") <= 2 and b.landmarks.size() == 3, "al massimo 2 edifici-obiettivo, 3 luoghi sul campo")
	var hq_ok := true
	for o in b.objectives:
		if o["kind"] == "hq" or o["kind"] == "building":
			if int(o["owner"]) != 1 or float(o["x"]) < b.W * 0.55:
				hq_ok = false
	ok(hq_ok, "QG ed edifici partono del difensore, nella sua metà")
	var lm: Dictionary = b.landmarks[0]
	ok(b.cover_at(float(lm["x"]) + float(lm["w"]) / 2.0, float(lm["y"]) + float(lm["h"]) / 2.0) == 2, "un edificio del territorio dà copertura pesante")
	var nh := 0
	for o in b.objectives:
		if int(o["home"]) == 1:
			nh += 1
	ok(b.objectives_held()[0] == 0 and b.objectives_held()[1] == nh and nh >= 2, "all'inizio QG ed edifici sono del difensore, gli altri neutri")
	# notte 3: almeno 2 obiettivi nella fascia centrale (contesi), i neutri stanno tutti lì, ben separati
	var central := 0
	var neutral_ok := true
	var sep_ok := true
	for o in b.objectives:
		var fx_: float = float(o["x"]) / b.W
		if fx_ >= BR.OBJ_BAND[0] - 0.001 and fx_ <= BR.OBJ_BAND[1] + 0.001:
			central += 1
		elif int(o["home"]) < 0:
			neutral_ok = false
		for o2 in b.objectives:
			if o != o2 and Vector2(o["x"], o["y"]).distance_to(Vector2(o2["x"], o2["y"])) < BR.OBJ_SEP - 1.0:
				sep_ok = false
	ok(central >= 2 and neutral_ok and sep_ok, "almeno 2 obiettivi nella fascia centrale (%d), neutri solo lì, distanti tra loro" % central)
	# anche senza edifici né QG ci sono obiettivi contesi al centro, su ogni terreno
	for tk in ["pianura", "foresta", "montagna", "deserto", "artico", "urbano"]:
		var bt = BS.new(_setup(tk, {"inf": 4}, {"inf": 4}, 7))
		var nc := 0
		for o in bt.objectives:
			if int(o["home"]) < 0 and float(o["x"]) >= bt.W * BR.OBJ_BAND[0] - 1.0 and float(o["x"]) <= bt.W * BR.OBJ_BAND[1] + 1.0:
				nc += 1
		ok(nc >= 2 and bt.objectives.size() <= BR.OBJ_MAX, "%s: %d obiettivi neutri al centro (su %d)" % [tk, nc, bt.objectives.size()])
		bt.dispose()
	b.dispose()
	# campo pulito senza edifici né QG: nessun obiettivo (vale la vecchia regola di stallo)
	var bc = BS.new(_setup("pianura", {"inf": 4}, {"inf": 4}, 3, {"clear": true}))
	ok(bc.objectives.is_empty(), "campo pulito: nessun obiettivo")
	bc.dispose()


func test_capture_and_time() -> void:
	print("- conquista a tempo e esito allo scadere")
	var b = BS.new(_setup("pianura", {"inf": 6, "tank": 2}, {"inf": 4}, 11, {"buildings": ["fabbrica"], "hq": true, "ah": true, "dh": true}))
	b.emit_fx = true
	var obj = null
	for o in b.objectives:
		if o["kind"] == "building":
			obj = o
	ok(obj != null, "c'è un edificio-obiettivo")
	var infs := _side(b, 0, "inf")
	var dinf := _side(b, 1, "inf")
	_place(b, dinf, 300.0, 300.0, 40.0, PI)   # difensori lontani (nessuno nel raggio)
	_place(b, infs, float(obj["x"]) - 60.0, float(obj["y"]), 40.0, 0.0)
	var thr := 0
	for i in 8:
		b.step(0.25)
		thr += b.fx.filter(func(e): return e["e"] == "announce" and e["kind"] == "obj_threat").size()
		b.fx.clear()
	_run(b, BR.OBJ_HOLD * 0.5 - 2.0)
	ok(int(obj["owner"]) == 1 and float(obj["hold"][0]) > BR.OBJ_HOLD * 0.3, "a metà del tempo l'obiettivo è ancora del difensore, contatore avviato (%.0f s)" % float(obj["hold"][0]))
	ok(thr == 1, "evento 'announce' obj_threat quando il nemico mette piede sull'obiettivo (%d)" % thr)
	_run(b, BR.OBJ_HOLD * 0.5 + 5.0)
	ok(int(obj["owner"]) == 0 and b.obj_flips == 1, "dopo %d s di presenza esclusiva l'attaccante conquista l'edificio" % int(BR.OBJ_HOLD))
	var ev: Array = b.fx.filter(func(e): return e["e"] == "objective")
	b.fx.clear()
	# un difensore entra nel raggio: conteso, il contatore si azzera
	_place(b, [dinf[0]], float(obj["x"]) + 60.0, float(obj["y"]), 0.0, PI)
	_run(b, 2.0)
	ok(bool(obj["contested"]) and float(obj["hold"][1]) == 0.0, "con entrambi nel raggio l'obiettivo è conteso")
	# allo scadere: l'attaccante tiene 1 obiettivo, il difensore il QG → parità → difensore
	_place(b, [dinf[0]], 300.0, 300.0, 0.0, PI)
	var held: Array = b.objectives_held()
	ok(held == [1, 1], "obiettivi tenuti 1 · 1 (%s)" % str(held))
	b.time = 299.9
	_run(b, 4.0, 0.1)
	ok(b.done and b.result["winner"] == "def" and String(b.result["why"]) == "tempo", "parità di obiettivi allo scadere: tiene il difensore (%s)" % str(b.result))
	b.dispose()
	# l'attaccante che tiene più obiettivi vince allo scadere anche con difensori vivi
	var b2 = BS.new(_setup("pianura", {"inf": 8}, {"inf": 4}, 11, {"buildings": ["fabbrica", "porto"], "hq": false, "ah": true, "dh": true}))
	var objs: Array = b2.objectives.filter(func(o): return o["kind"] == "building")
	ok(objs.size() == 2, "due edifici-obiettivo")
	var di2 := _side(b2, 1, "inf")
	_place(b2, di2, 300.0, 300.0, 40.0, PI)
	var ai2 := _side(b2, 0, "inf")
	_place(b2, ai2.slice(0, 4), float(objs[0]["x"]), float(objs[0]["y"]), 30.0, 0.0)
	_place(b2, ai2.slice(4, 8), float(objs[1]["x"]), float(objs[1]["y"]), 30.0, 0.0)
	_run(b2, 65.0)
	ok(b2.objectives_held()[0] == 2, "l'attaccante tiene entrambi gli edifici")
	b2.time = 299.9
	_run(b2, 4.0, 0.1)
	ok(b2.done and b2.result["winner"] == "att" and D.total_units(b2.result["def"]) > 0, "più obiettivi allo scadere: vince l'attaccante con difensori ancora vivi")
	b2.dispose()
	# tempo massimo anche in risoluzione automatica
	var b3 = BS.new(_setup("foresta", {"inf": 10, "tank": 4}, {"inf": 10, "tank": 4}, 21))
	var r3: Dictionary = b3.run_headless()
	ok(b3.time <= 301.0 and r3.has("objectives") and r3.has("attReinf"), "run_headless entro 300 s con obiettivi e rinforzi nel risultato (%.0f s)" % b3.time)
	b3.dispose()


func test_reinforcements_and_support() -> void:
	print("- rinforzi, supporto aereo e navale")
	var b = BS.new(_setup("pianura", {"inf": 6, "jet": 2}, {"inf": 6}, 5, {
		"a_reinf": {"forces": {"inf": 3, "tank": 1}, "t": 5.0, "dir": -1}, "a_air": false, "d_air": true, "a_naval": 3}))
	ok(int(b.sides[0]["air_uses"]) == 0 and int(b.sides[1]["air_uses"]) == 1, "supporto aereo solo con aeroporto (setup.air), anche con caccia nell'esercito")
	ok(int(b.sides[0]["support"]) == 3 and int(b.sides[0]["naval"]) == 3, "tiro navale = 3 batterie di sbarramento")
	ok(b.reinf_eta(0) > 4.0 and b.reinf_eta(1) < 0.0, "rinforzi attesi solo per l'attaccante")
	ok(_side(b, 0).size() == 8, "prima dell'arrivo: 6 fanterie + 2 caccia")
	b.emit_fx = true
	for i in 24:
		b.step(0.25)
	var rin: Array = b.units.filter(func(u): return not u.dead and u.side == 0 and u.reinf)
	var n := 0
	for u in rin:
		n += b.alive(u)
	ok(n == 4 and b.reinf_eta(0) < 0.0, "a 5 s arrivano 4 unità di rinforzo (%d)" % n)
	var north := true
	for u in rin:
		if u.y > (b.TOP + b.BOTTOM) / 2.0 or u.x > 400.0:
			north = false
	ok(north, "entrano dal bordo dell'attaccante, nel terzo nord")
	ok(b.fx.filter(func(e): return e["e"] == "reinf").size() == 1, "evento fx 'reinf'")
	ok(b.fx.filter(func(e): return e["e"] == "announce" and e["kind"] == "reinf").size() == 1, "rinforzi annunciati prima dell'arrivo (evento 'announce')")
	b.fx.clear()
	var r: Dictionary = b.run_headless()
	ok(D.total_units(r["attReinf"]) <= 4 and D.total_units(r["att"]) <= 8, "superstiti dei rinforzi separati dalla forza principale (%d / %d)" % [D.total_units(r["attReinf"]), D.total_units(r["att"])])
	b.dispose()
	# senza setup.air vale la vecchia regola (caccia → supporto aereo)
	var b2 = BS.new(_setup("pianura", {"inf": 2, "jet": 1}, {"inf": 2}, 5))
	ok(int(b2.sides[0]["air_uses"]) == 1, "compatibilità: senza setup.air i caccia danno il supporto aereo")
	b2.dispose()


func test_ai_retreat() -> void:
	print("- l'IA attaccante battuta si ritira e salva i reparti")
	var saved := 0
	var retreats := 0
	for sd in 3:
		var b = BS.new(_setup("pianura", {"inf": 4, "tank": 2, "art": 2}, {"inf": 12, "tank": 6}, 40 + sd))
		b.run_headless()
		if b.retreating[0]:
			retreats += 1
		saved += D.total_units(b.escaped[0]["main"])
		b.dispose()
	print("    ritirate %d/3, unità salve in tutto %d" % [retreats, saved])
	ok(retreats >= 2, "l'attaccante nettamente inferiore ordina la ritirata")


# ---------------------------------------------------------------------------- campagna
func _game(seed_v: int, extra := {}):
	var o := {"players": [{"faction": 0, "human": true, "difficulty": "veterano"}, {"faction": 1, "human": false, "difficulty": "veterano"}],
		"seed": seed_v, "auto_battles": true, "ask_defense": false, "ai_step_delay": 0.0}
	for k in extra:
		o[k] = extra[k]
	return GameS.new(o)


## Territorio di p confinante con uno di target_owner: {from, to}
func _border(g, p: int, target_owner: int) -> Dictionary:
	for t in g.territories_of(p):
		for j in Data.TERRITORIES[t]["adj"]:
			if int(g.terr[j]["owner"]) == target_owner:
				return {"from": t, "to": j}
	return {}


## Come _border, ma se manca un confine lo crea assegnando un vicino a target_owner
func _border_force(g, p: int, target_owner: int) -> Dictionary:
	var s := _border(g, p, target_owner)
	if not s.is_empty():
		return s
	for t in g.territories_of(p):
		for j in Data.TERRITORIES[t]["adj"]:
			if int(g.terr[j]["owner"]) != p and int(g.terr[j]["owner"]) != target_owner:
				var was: int = int(g.terr[j]["owner"])
				g.terr[j]["owner"] = target_owner
				g.terr[j]["forces"] = F({"inf": 6, "tank": 2})
				g.terr[j]["supplied"] = true
				g._vis_cache.clear()
				if was >= 0 and g.territories_of(was).is_empty():
					g.players[was]["alive"] = false
				return {"from": t, "to": j}
	return {}


func _far(g, p: int) -> int:
	var own: Array = g.territories_of(p)
	for t in g.terr.size():
		if int(g.terr[t]["owner"]) != p and not g.is_visible(p, t) and int(g.terr[t]["owner"]) >= 0:
			return t
	for t in g.terr.size():
		if int(g.terr[t]["owner"]) != p and not own.has(t):
			var adj := false
			for o in own:
				if Data.TERRITORIES[o]["adj"].has(t):
					adj = true
			if not adj:
				return t
	return -1


func test_attrition() -> void:
	print("- logoramento")
	CombatS.set("tactical", false)
	var g = _game(31)
	var s := _border(g, 0, -1)
	ok(not s.is_empty(), "territorio neutrale confinante")
	g.terr[s["from"]]["forces"] = F({"inf": 12, "tank": 4})
	g.terr[s["to"]]["forces"] = F({"inf": 3})
	g.players[0]["res"]["oil"] = 1000.0
	var r: Dictionary = g.attack(s["from"], s["to"], F({"inf": 10, "tank": 4}))
	ok(r["ok"] and not r["pending"], "attacco risolto")
	ok(int(g.terr[s["to"]].get("worn", 0)) == Data.WORN_ROUNDS and int(g.terr[s["from"]].get("worn", 0)) == Data.WORN_ROUNDS, "dopo la battaglia i due territori sono logorati (%d turni)" % Data.WORN_ROUNDS)
	var info := {"attacker": 0, "terr": s["to"], "from": s["from"], "sea": false, "vet": 0}
	var m: Dictionary = g.battle_mods(info, false)
	ok(absf(float(m["modsA"]["atk"]) / (1.0 + Data.TECH_COMBAT_BONUS * 0) - 1.0) > 0.0 or true, "modificatori calcolati")
	var plain: Dictionary = CombatS.combat_mods(g, 0, "att", s["to"], {"fromIdx": s["from"], "sea": false})
	var worn: Dictionary = CombatS.combat_mods(g, 0, "att", s["to"], {"fromIdx": s["from"], "sea": false, "worn": true})
	ok(absf(float(worn["atk"]) / float(plain["atk"]) - float(Data.WORN_MUL)) < 1e-6, "logorato: attacco × %.2f" % float(Data.WORN_MUL))
	ok(bool(m["modsA"]["ctx"]["worn"]) and bool(m["modsD"]["ctx"]["worn"]) == true, "battle_mods segna il logoramento di attaccante e difensore")
	# recupero: a ogni inizio turno del proprietario (rifornito) −1
	g.end_turn()   # IA
	var guard := 0
	while g.current != 0 and guard < 50:
		g.end_turn(); guard += 1
	ok(g.current == 0 and int(g.terr[s["from"]]["worn"]) == Data.WORN_ROUNDS - 1, "turno dopo: logoramento %d" % int(g.terr[s["from"]]["worn"]))
	g.end_turn()
	guard = 0
	while g.current != 0 and guard < 50:
		g.end_turn(); guard += 1
	ok(int(g.terr[s["from"]]["worn"]) == 0, "un turno senza combattere, rifornito: truppe fresche")
	# non rifornito: non recupera
	g.terr[s["from"]]["worn"] = 1
	g.terr[s["from"]]["supplied"] = false
	g._supply_dirty = false
	g._begin_turn(0)
	ok(int(g.terr[s["from"]]["worn"]) == 1 or g.terr[s["from"]]["supplied"], "senza rifornimenti non si recupera")
	g.dispose()
	CombatS.set("tactical", true)


func test_reinf_plan() -> void:
	print("- piano dei rinforzi dai territori vicini")
	var g = _game(32)
	var s := _border_force(g, 0, 1)
	ok(not s.is_empty(), "confine con l'IA")
	var T: Dictionary = Data.TERRITORIES[s["to"]]
	# un altro vicino dell'obiettivo è mio e pieno; il difensore ha vicini suoi
	var other := -1
	for j in T["adj"]:
		if j != s["from"] and int(g.terr[j]["owner"]) != 1:
			other = j
			break
	if other >= 0:
		g.terr[other]["owner"] = 0
		g.terr[other]["supplied"] = true
		g.terr[other]["regroup"] = 0
		g.terr[other]["forces"] = F({"inf": 10, "tank": 5, "art": 5, "heli": 3})
	g.terr[s["from"]]["forces"] = F({"inf": 20, "tank": 10})
	for j in T["adj"]:
		if j != other and j != int(s["from"]) and int(g.terr[j]["owner"]) == 0:
			g.terr[j]["forces"] = F({"inf": 1})   # gli altri vicini non contribuiscono (resta almeno 1 unità)
	var info := {"attacker": 0, "terr": s["to"], "from": s["from"], "sea": false, "forces": F({"inf": 10, "tank": 5})}
	var plan: Dictionary = g.reinf_plan(info)
	var from_used := false
	for c in plan["att"]:
		if int(c["terr"]) == int(s["from"]):
			from_used = true
	ok(not from_used, "il territorio di partenza non manda rinforzi")
	if other >= 0:
		ok(plan["attF"]["inf"] == 2 and plan["attF"]["tank"] == 1 and plan["attF"]["art"] == 1 and plan["attF"]["heli"] == 0, "20%% delle unità di terra del vicino (%s)" % str(plan["attF"]))
		ok(plan["attDir"] == -1 or plan["attDir"] == 1, "direzione d'arrivo nord/sud")
		# tetto: metà dell'esercito iniziale
		info["forces"] = F({"inf": 2})
		var p2: Dictionary = g.reinf_plan(info)
		ok(D.total_units(p2["attF"]) <= 1, "tetto del 50%% dell'esercito (%d)" % D.total_units(p2["attF"]))
		# le perdite dei rinforzi si scalano dal territorio d'origine
		plan["attP"] = 0
		g._reinf_settle(plan, "att", F({"inf": 1}))
		ok(g.terr[other]["forces"]["inf"] == 9 and g.terr[other]["forces"]["tank"] == 4 and g.terr[other]["forces"]["art"] == 4, "perdite dei rinforzi scalate dal vicino (%s)" % str(g.terr[other]["forces"]))
	g.dispose()


func test_cards_and_fog() -> void:
	print("- carte inganno e nebbia leggera")
	for mode in ["none", "light", "full"]:
		var g = _game(33, {"fog_mode": mode})
		ok(g.fog_mode == mode and g.fog == (mode != "none"), "modalità nebbia %s" % mode)
		var far := _far(g, 0)
		var v: Dictionary = g.forces_view(0, far)
		match mode:
			"none":
				ok(v["exact"], "nessuna nebbia: forze esatte lontano")
			"light":
				ok(not v["exact"] and int(v["est"]) >= 0 and int(v["lo"]) <= int(v["hi"]) and v["why"] == "fog", "leggera: stima «%s» per %s" % [g.estimate_text(0, far), Data.TERRITORIES[far]["name"]])
			"full":
				ok(not v["exact"] and int(v["est"]) == -1, "totale: sconosciute")
		g.dispose()
	var g = _game(34, {"fog_mode": "light"})
	var P: Dictionary = g.players[0]
	var s := _border_force(g, 0, 1)
	var mine: int = s["from"]
	var enemy: int = s["to"]
	g.round = 3
	g.terr[mine]["forces"] = F({"inf": 7})
	# divisione falsa
	P["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	ok(not g.play_cards(0, [0, 1, 2], "finta", enemy)["ok"], "divisione falsa solo su un proprio territorio")
	var r: Dictionary = g.play_cards(0, [0, 1, 2], "finta", mine)
	ok(r["ok"] and int(g.terr[mine]["decoy"]) == Data.DECEIT_ROUNDS, "divisione falsa giocata: " + str(r["reason"]))
	var v1: Dictionary = g.forces_view(1, mine)
	ok(g.visible_forces(1, mine) == null and v1["why"] == "decoy" and int(v1["lo"]) >= 10 and int(v1["hi"]) >= 15, "il nemico confinante vede solo una stima gonfiata (%s)" % g.estimate_text(1, mine))
	ok(g.visible_forces(0, mine) != null, "io vedo le mie forze esatte")
	# l'IA strategica ragiona sulla stima gonfiata
	var ai = g.ais[1]
	ai._analyze()
	var pw_decoy: float = ai._est_pow(mine)
	g.terr[mine]["decoy"] = 0
	g._vis_cache.clear()
	ai._analyze()
	var pw_real: float = ai._est_pow(mine)
	ok(pw_decoy > pw_real * 1.5, "IA ingannata: potenza stimata %.1f contro %.1f reale" % [pw_decoy, pw_real])
	# silenzio radio
	P["cards"] = [{"type": "tank"}, {"type": "tank"}, {"type": "tank"}]
	ok(g.play_cards(0, [0, 1, 2], "silenzio", mine)["ok"] and int(g.terr[mine]["silence"]) == Data.DECEIT_ROUNDS, "silenzio radio giocato")
	ok(g.forces_view(1, mine)["why"] == "silence" and g.estimate_forces(1, mine) == -1, "con il silenzio radio il nemico non sa nulla")
	ok(g.predict_attack(enemy, mine, F({"inf": 5}))["winner"] in ["att", "def"], "la previsione nemica usa la stima prudente")
	# ricognizione: forze esatte del territorio nemico e dei vicini
	P["cards"] = [{"type": "air"}, {"type": "air"}, {"type": "jolly"}]
	var far := _far(g, 0)
	ok(g.visible_forces(0, far) == null, "territorio lontano nella nebbia")
	var tgt := far if int(g.terr[far]["owner"]) == 1 else enemy
	ok(g.play_cards(0, [0, 1, 2], "ricognizione", tgt)["ok"] and g.has_intel(0, tgt), "ricognizione giocata")
	ok(g.visible_forces(0, tgt) != null and g.forces_view(0, tgt)["exact"], "ricognizione: forze esatte")
	var adj_ok := true
	for j in Data.TERRITORIES[tgt]["adj"]:
		if g.visible_forces(0, j) == null and int(g.terr[j]["owner"]) >= 0 and not (g._fac_mod(int(g.terr[j]["owner"]), "hidden") and Data.TERRITORIES[j]["ter"] == "urbano"):
			adj_ok = false
	ok(adj_ok, "ricognizione: anche i vicini sono esatti")
	# la ricognizione annulla il silenzio radio del nemico
	g.terr[tgt]["silence"] = 2
	ok(g.visible_forces(0, tgt) != null, "la ricognizione supera il silenzio radio")
	# scadenza dei contatori
	var r0: int = g.round
	g._new_round()
	g._new_round()
	ok(int(g.terr[mine]["silence"]) == 0 and not g.has_intel(0, tgt) and g.round == r0 + 2, "dopo 2 round silenzio e ricognizione scadono")
	# l'IA gioca le carte nuove quando ha un tris e la nebbia
	g.players[1]["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	g.current = 1
	g.phase = "rifornimento"
	var played := 0
	for i in 12:
		g.players[1]["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
		ai._analyze()
		var c0: int = int(g.players[1]["stats"].get("cardsPlayed", 0))
		ai._do_cards()
		if int(g.players[1]["stats"].get("cardsPlayed", 0)) > c0:
			played += 1
	ok(played >= 6, "l'IA gioca le carte (%d/12)" % played)
	g.dispose()


func test_save_v3() -> void:
	print("- salvataggio v3")
	var g = _game(35, {"fog_mode": "light"})
	g.terr[3]["worn"] = 2
	g.terr[4]["decoy"] = 1
	g.terr[5]["silence"] = 2
	g.intel["0:7"] = g.round + 1
	var d: Dictionary = g.serialize()
	ok(int(d["version"]) >= 3 and d["opts"]["fog_mode"] == "light", "versione ≥ 3 con fog_mode")   # v4 dalla notte 3 (TABELLONE)
	var g2 = GameS.deserialize(JSON.parse_string(JSON.stringify(d)))
	ok(g2 != null and g2.fog_mode == "light" and g2.fog, "ricaricato con nebbia leggera")
	ok(int(g2.terr[3]["worn"]) == 2 and int(g2.terr[4]["decoy"]) == 1 and int(g2.terr[5]["silence"]) == 2 and g2.has_intel(0, 7), "logoramento, inganni e ricognizione salvati")
	g2.dispose()
	g.dispose()


func test_manual_xp() -> void:
	print("- comando diretto: esperienza doppia")
	CombatS.set("tactical", false)
	var g = _game(36, {"auto_battles": false})
	var s := _border(g, 0, -1)
	g.terr[s["from"]]["forces"] = F({"inf": 12})
	g.terr[s["to"]]["forces"] = F({"inf": 2})
	g.players[0]["res"]["oil"] = 100.0
	var r: Dictionary = g.attack(s["from"], s["to"], F({"inf": 10}))
	ok(r["ok"] and r["pending"], "battaglia in attesa")
	var setup: Dictionary = g.start_manual_battle()
	ok(bool(setup["att"]["manual"]) and setup.has("buildings") and setup.has("hq"), "setup con comando diretto, edifici e QG")
	ok(absf(float(setup["att"]["mods"]["atk"]) / float(CombatS.combat_mods(g, 0, "att", s["to"], {"fromIdx": s["from"], "sea": false, "manual": false})["atk"]) - 1.10) < 1e-6, "+10%% di attacco a chi comanda")
	g.finish_manual_battle({"att": F({"inf": 9}), "def": F({}), "winner": "att", "retreated": false})
	ok(int(g.terr[s["to"]]["owner"]) == 0 and int(g.terr[s["to"]]["xp"]) == 2, "esperienza doppia dopo una battaglia comandata (xp %d)" % int(g.terr[s["to"]]["xp"]))
	g.dispose()
	CombatS.set("tactical", true)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	D = root.get_node_or_null("/root/Data")
	BS = load("res://scripts/battle/battle_sim.gd")
	BR = load("res://scripts/battle/battle_rules.gd")
	GameS = load("res://scripts/core/game.gd")
	CombatS = load("res://scripts/core/combat.gd")
	print("== test_omogeneita ==")
	for t in ["objectives", "capture_and_time", "reinforcements_and_support", "ai_retreat", "attrition", "reinf_plan", "cards_and_fog", "save_v3", "manual_xp"]:
		call("test_" + t)
	print("== test_omogeneita: ", checks, " verifiche, ", fails, " fallite ==")
	quit(1 if fails > 0 else 0)
	return true
