extends SceneTree
## Collaudo headless della FASE 3 (adattato ai turni, FASE 6): veterani, nebbia di guerra, diplomazia (patti in round),
## serializzazione. Uso: node tools/godot_run.js -- --headless --path . --script tests/test_fase3.gd

var D            # autoload Data
var GameS: Script
var CombatS: Script
var AIS: Script
var fails := 0
var checks := 0


## IA che non fa nulla (scenari controllati): passa il turno
class NullAI:
	extends RefCounted
	var stats := {"ms": 0.0, "maxMs": 0.0, "errors": 0}
	func _init(_g, _i: int) -> void:
		pass
	func turn_step() -> bool:
		return false


func _initialize() -> void:
	D = root.get_node("Data")
	CombatS = load("res://scripts/core/combat.gd")
	GameS = load("res://scripts/core/game.gd")
	AIS = load("res://scripts/core/ai.gd")
	if GameS == null or CombatS == null:
		print("FALLITO: script non caricati")
		quit(1)
		return
	CombatS.set("tactical", false)
	test_vet_basics()
	test_vet_flow()
	test_vet_recruits()
	test_vet_manual_setup()
	test_fog()
	test_pacts_rules()
	test_pact_offers()
	test_ai_respects_pact()
	test_ai_offers_pact()
	test_serialization()
	CombatS.set("tactical", true)
	print("\n== test_fase3: ", checks, " verifiche, ", fails, " fallite ==")
	quit(1 if fails > 0 else 0)


func _process(_d: float) -> bool:
	return true


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALLITO: ", what)


func F(o: Dictionary) -> Dictionary:
	var f: Dictionary = D.empty_forces()
	for k in o:
		f[k] = o[k]
	return f


## Partita "pulita": tutti i territori neutrali con 1 FAN, dopo la tregua (round 3)
func blank_game(pl: Array, extra: Dictionary = {}):
	var o := {"players": pl, "seed": 5, "auto_battles": true, "ai_script": NullAI, "ai_step_delay": 0.0}
	o.merge(extra, true)
	var g = GameS.new(o)
	for tr in g.terr:
		tr["owner"] = -1
		tr["forces"] = F({"inf": 1})
		tr["buildings"] = []
		tr["queue"] = []
		tr["vet"] = 0
		tr["xp"] = 0
	for p in g.players:
		p["hq"] = -1
	g.round = 3
	g._vis_cache.clear()
	g._supply_dirty = true
	return g


## p di turno, fase rifornimento, attacco e spostamento disponibili
func act(g, p: int) -> void:
	g.current = p
	g.phase = "rifornimento"
	g.attack_used = false
	g.move_used = false


## Avanza di un round intero (tutti passano il turno; le IA nulle passano subito)
func next_round(g) -> void:
	var r0: int = g.round
	var guard := 0
	while g.round == r0 and guard < 20:
		guard += 1
		if g.pending_battle != null:
			g.resolve_pending_auto()
		elif g.is_human_turn():
			g.end_turn()
		else:
			g.update(0.1)


func set_t(g, t: int, owner: int, f: Dictionary) -> void:
	g.terr[t]["owner"] = owner
	g.terr[t]["forces"] = F(f)
	g.terr[t]["regroup"] = 0
	g._vis_cache.clear()
	g._supply_dirty = true


func land_adj(t: int) -> Array:
	var o: Array = []
	for j in D.TERRITORIES[t]["adj"]:
		if not D.TERRITORIES[t]["sea"].has(j):
			o.append(j)
	return o


## distanze in salti (tutte le adiacenze, anche via mare)
func hops(from: int) -> Array:
	var dist: Array = []
	dist.resize(D.TERRITORIES.size())
	dist.fill(-1)
	dist[from] = 0
	var q: Array = [from]
	while q.size() > 0:
		var a: int = q.pop_front()
		for b in D.TERRITORIES[a]["adj"]:
			if dist[b] < 0:
				dist[b] = dist[a] + 1
				q.append(b)
	return dist


## territorio con almeno n vicini via terra
func pick_hub(n: int) -> int:
	for t in D.TERRITORIES:
		if land_adj(t["idx"]).size() >= n:
			return t["idx"]
	return 0


# ---------------------------------------------------------------- veterani
func test_vet_basics() -> void:
	print("- veterani: livelli e modificatori")
	ok(GameS.vet_level(0) == 0 and GameS.vet_level(1) == 0, "0-1 vittorie: nessuna stella")
	ok(GameS.vet_level(2) == 1 and GameS.vet_level(3) == 1, "2 vittorie: 1 stella")
	ok(GameS.vet_level(4) == 2 and GameS.vet_level(6) == 2, "4 vittorie: 2 stelle")
	ok(GameS.vet_level(7) == 3 and GameS.vet_level(99) == 3, "7 vittorie: 3 stelle")
	var g = blank_game([{"faction": 1, "human": false}, {"faction": 2, "human": false}])
	var t := pick_hub(2)
	set_t(g, t, 0, {"inf": 5})
	var m0: Dictionary = CombatS.combat_mods(g, 0, "att", t, {})
	var m3: Dictionary = CombatS.combat_mods(g, 0, "att", t, {"vet": 3})
	var m1: Dictionary = CombatS.combat_mods(g, 0, "def", t, {"vet": 1})
	var m1b: Dictionary = CombatS.combat_mods(g, 0, "def", t, {})
	ok(absf(m3["atk"] / m0["atk"] - 1.18) < 1e-6, "3 stelle = +18%% attacco (%.4f)" % (m3["atk"] / m0["atk"]))
	ok(absf(m1["atk"] / m1b["atk"] - 1.06) < 1e-6, "1 stella in difesa = +6%")
	ok(CombatS.combat_mods(g, 0, "att", t, {"vet": 9})["atk"] == m3["atk"], "stelle limitate a 3")
	ok(g.terr[t].has("vet") and g.terr[t].has("xp"), "terr[i] ha vet e xp")
	var g2 = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 2, "ai_script": NullAI})
	var all0 := true
	for tr in g2.terr:
		if int(tr["vet"]) != 0:
			all0 = false
	ok(all0, "a inizio partita nessun veterano")


func test_vet_flow() -> void:
	print("- veterani: vittorie in difesa, annuncio, spostamenti, fusioni, conquista")
	var g = blank_game([{"faction": 1, "human": true}, {"faction": 2, "human": false}])
	var evs: Array = []
	g.event.connect(func(n, d): evs.append([n, d]))
	var b := pick_hub(3)
	var la := land_adj(b)
	var a: int = la[0]
	var c: int = la[1]
	set_t(g, b, 0, {"inf": 40, "tank": 6})
	set_t(g, a, 1, {"inf": 60})
	set_t(g, c, 0, {})
	var stars_at := []
	for k in 8:
		act(g, 1)
		var r: Dictionary = g.attack(a, b, F({"inf": 1}))
		ok(r["ok"], "attacco di disturbo %d (%s)" % [k, r["reason"]])
		stars_at.append(int(g.terr[b]["vet"]))
	ok(g.terr[b]["owner"] == 0, "il presidio resiste")
	ok(stars_at[0] == 0 and stars_at[1] == 1 and stars_at[3] == 2 and stars_at[6] == 3, "stelle dopo 2/4/7 vittorie (%s)" % str(stars_at))
	ok(int(g.terr[b]["xp"]) == 7, "esperienza limitata a 7 (%d)" % g.terr[b]["xp"])
	var vev := evs.filter(func(e): return e[0] == "veteran")
	ok(vev.size() == 3, "3 eventi veteran (%d)" % vev.size())
	ok(vev.size() > 0 and vev[0][1]["terr"] == b and vev[0][1]["player"] == 0 and vev[0][1]["vet"] == 1, "dati evento veteran")
	var logged := false
	for e in g.events:
		if str(e["text"]).find("veterano") >= 0 and str(e["text"]).find("★") >= 0:
			logged = true
	ok(logged, "annuncio della stella nel registro")
	# lo spostamento porta la vet in un territorio vuoto
	act(g, 0)
	var r2: Dictionary = g.move(b, c, F({"inf": 10}))
	ok(r2["ok"] and int(g.terr[c]["vet"]) == 3, "territorio vuoto rinforzato: vet di chi arriva (%d)" % g.terr[c]["vet"])
	# fusione: 10 unità vet 3 + 10 vet 0 -> 2 (media 1.5 arrotondata al più vicino)
	g.terr[b]["vet"] = 0
	g.terr[b]["xp"] = 0
	act(g, 0)
	g.move(b, c, F({"inf": 10}))
	ok(int(g.terr[c]["vet"]) == 2, "fusione = media pesata al più vicino (%d)" % g.terr[c]["vet"])
	ok(int(g.terr[c]["xp"]) >= 4 and int(g.terr[c]["xp"]) <= 6, "xp coerente con la stella (%d)" % g.terr[c]["xp"])
	# conquista: la vet passa al territorio conquistato (+1 vittoria)
	g.terr[c]["vet"] = 2
	g.terr[c]["xp"] = 4
	var tgt := -1
	for j in land_adj(c):
		if g.terr[j]["owner"] < 0:
			tgt = j
			break
	if tgt >= 0:
		set_t(g, tgt, -1, {"inf": 2})
		act(g, 0)
		var r3: Dictionary = g.attack(c, tgt, F({"inf": 15}))
		ok(r3["ok"], "attacco su neutrale")
		ok(g.terr[tgt]["owner"] == 0, "neutrale conquistato")
		ok(int(g.terr[tgt]["vet"]) == 2 and int(g.terr[tgt]["xp"]) == 5, "conquista porta vet 2 e +1 xp (%d/%d)" % [g.terr[tgt]["vet"], g.terr[tgt]["xp"]])


func test_vet_recruits() -> void:
	print("- veterani: le reclute non abbassano le stelle fino al 50% del presidio")
	var g = blank_game([{"faction": 1, "human": true}, {"faction": 2, "human": false}])
	var t := pick_hub(2)
	set_t(g, t, 0, {"inf": 10})
	g.terr[t]["vet"] = 2
	g.terr[t]["xp"] = 4
	g.terr[t]["buildings"] = ["caserma"]
	act(g, 0)
	g.players[0]["pool"] = F({"inf": 5})
	ok(g.place_pool(0, t)["ok"], "pool schierato")
	ok(int(g.terr[t]["vet"]) == 2 and int(g.terr[t]["fresh"]) == 5, "50%% di reclute: ancora 2 stelle (%d, fresh %d)" % [g.terr[t]["vet"], g.terr[t]["fresh"]])
	g.players[0]["res"] = {"money": 9999.0, "oil": 9999.0, "steel": 9999.0, "manpower": 9999.0}
	ok(g.recruit(0, t, "inf", 1)["ok"], "recluta accodata")
	g._finish_turn()
	ok(g.terr[t]["queue"].is_empty(), "recluta pronta a fine turno")
	ok(int(g.terr[t]["vet"]) == 1 and int(g.terr[t]["fresh"]) == 0, "oltre il 50%%: fusione al più vicino (vet %d)" % g.terr[t]["vet"])
	var t2: int = land_adj(t)[0]
	set_t(g, t2, 0, {"inf": 3})
	g.terr[t2]["vet"] = 1
	g.terr[t2]["xp"] = 2
	g._add_recruits(g.terr[t2], 1)
	g.terr[t2]["forces"]["inf"] += 1
	ok(int(g.terr[t2]["vet"]) == 1, "una recluta su 3 veterani: stella intatta")
	g.terr[t2]["vet"] = 3
	g.terr[t2]["xp"] = 7
	g.terr[t2]["forces"] = F({"inf": 20})
	var n := -1
	for j in D.TERRITORIES[t2]["adj"]:
		if g.terr[j]["owner"] < 0 and not D.TERRITORIES[t2]["sea"].has(j):
			n = j
			break
	if n >= 0:
		set_t(g, n, -1, {"inf": 2})
		g.terr[n]["vet"] = 0
		act(g, 0)
		g.attack(t2, n, F({"inf": 12}))
		ok(g.terr[n]["owner"] == 0 and int(g.terr[n]["vet"]) == 3, "conquista: vet 3 dell'attaccante")


func test_vet_manual_setup() -> void:
	print("- veterani: battaglia manuale (setup.att.vet / setup.def.vet)")
	var g = blank_game([{"faction": 1, "human": true}, {"faction": 2, "human": false}], {"auto_battles": false})
	var b := pick_hub(2)
	var t: int = land_adj(b)[0]
	set_t(g, b, 0, {"inf": 30})
	g.terr[b]["vet"] = 3
	g.terr[b]["xp"] = 7
	set_t(g, t, 1, {"inf": 8})
	g.terr[t]["vet"] = 1
	g.terr[t]["xp"] = 2
	act(g, 0)
	var r: Dictionary = g.attack(b, t, F({"inf": 20}))
	ok(r["ok"] and r["pending"], "attacco manuale in attesa")
	ok(g.pending_battle != null and int(g.pending_battle.get("vet", -1)) == 3, "battaglia in attesa con vet dell'attaccante")
	var setup: Dictionary = g.start_manual_battle()
	ok(int(setup["att"].get("vet", -1)) == 3 and int(setup["def"].get("vet", -1)) == 1, "setup.att.vet=3, setup.def.vet=1")
	var base_a: Dictionary = CombatS.combat_mods(g, 0, "att", t, {"fromIdx": b, "sea": false, "manual": true})
	var base_d: Dictionary = CombatS.combat_mods(g, 1, "def", t, {"manual": true})
	ok(absf(setup["att"]["mods"]["atk"] / base_a["atk"] - 1.18) < 1e-6, "mods attaccante con +18%")
	ok(absf(setup["def"]["mods"]["atk"] / base_d["atk"] - 1.06) < 1e-6, "mods difensore con +6%")
	g.finish_manual_battle({"att": F({"inf": 15}), "def": F({}), "winner": "att", "retreated": false, "autoRest": false})
	ok(g.terr[t]["owner"] == 0 and int(g.terr[t]["vet"]) == 3, "conquista manuale porta la vet 3")


# ---------------------------------------------------------------- nebbia
func test_fog() -> void:
	print("- nebbia di guerra")
	var gn = blank_game([{"faction": 0, "human": true}, {"faction": 1, "human": false}])
	ok(gn.fog == false and gn.opts["fog"] == false, "senza opts.fog la nebbia è spenta")
	var far := 0
	var dist0 := hops(0)
	for i in dist0.size():
		if dist0[i] >= 4:
			far = i
			break
	set_t(gn, 0, 0, {"inf": 3})
	set_t(gn, far, 1, {"inf": 9})
	ok(gn.is_visible(0, far) and gn.visible_forces(0, far) != null and gn.estimate_forces(0, far) == 9, "senza nebbia tutto visibile")

	var g = blank_game([{"faction": 0, "human": true}, {"faction": 1, "human": false}], {"fog": true})
	ok(g.fog == true, "opts.fog = true")
	var s := pick_hub(3)
	var ds := hops(s)
	var r := -1
	for i in ds.size():
		if ds[i] >= 7:
			r = i
			break
	ok(r >= 0, "territori lontani trovati")
	set_t(g, s, 1, {"inf": 4})
	set_t(g, r, 0, {"inf": 4})
	var d1 := -1
	var d2 := -1
	for i in ds.size():
		if ds[i] == 1 and d1 < 0:
			d1 = i
		if ds[i] == 2 and d2 < 0:
			d2 = i
	ok(g.is_visible(1, s) and g.is_visible(1, d1), "FO vede i propri e i confinanti")
	ok(not g.is_visible(1, d2), "FO non vede a 2 salti")
	ok(g.vision_rings(0) == 2 and g.vision_rings(1) == 1, "AAN ha il radar (2 anelli)")
	var dr := hops(r)
	var r2 := -1
	var r3 := -1
	for i in dr.size():
		if dr[i] == 2 and r2 < 0 and ds[i] > 1:
			r2 = i
		if dr[i] == 3 and r3 < 0 and ds[i] > 1:
			r3 = i
	ok(r2 >= 0 and g.is_visible(0, r2), "AAN vede a 2 salti (radar)")
	ok(r3 >= 0 and not g.is_visible(0, r3), "AAN non vede a 3 salti")
	ok(g.visible_forces(0, s) == null and g.estimate_forces(0, s) == -1, "nemico nella nebbia: forze null, stima -1")
	g.terr[d2]["forces"] = F({"inf": 12})
	ok(g.visible_forces(1, d2) == null, "neutrale nella nebbia: visible_forces null")
	ok(g.estimate_forces(1, d2) == 10, "neutrale nella nebbia: stima a multipli di 5 (%d)" % g.estimate_forces(1, d2))
	g.terr[d2]["forces"] = F({"inf": 1})
	ok(g.estimate_forces(1, d2) == 5, "neutrale piccolo: stima minima 5")
	g.terr[d1]["forces"] = F({"inf": 7})
	ok(g.estimate_forces(1, d1) == 7 and g.visible_forces(1, d1) != null, "visibile: stima esatta")
	ok(g.estimate_forces(1, s) == 4, "proprio: esatto")
	ok(g.visible_forces(-1, s) != null, "viewer -1 vede tutto")
	# animazioni di spostamento: visibili solo se partono o arrivano in vista
	set_t(g, d1, 1, {"inf": 6})
	act(g, 1)
	var rr: Dictionary = g.move(d1, s, F({"inf": 2}))
	ok(rr["ok"], "spostamento FO")
	var dv: Dictionary = g.divisions[-1]
	ok(g.division_visible(1, dv), "propria animazione visibile")
	ok(not g.division_visible(0, dv), "animazione nemica lontana invisibile ad AAN")
	ok(g.visible_divisions(0).size() == 0 and g.visible_divisions(1).size() == 1, "visible_divisions")
	set_t(g, d2, 1, {"inf": 3})
	var d3 := -1
	for j in D.TERRITORIES[d2]["adj"]:
		if ds[j] == 3:
			d3 = j
			break
	if d3 >= 0:
		ok(g.is_visible(1, d3), "la vista segue i nuovi territori")
	g.players[1]["alive"] = false
	ok(g.is_visible(1, r), "giocatore eliminato vede tutto")


# ---------------------------------------------------------------- patti
func pact_scene(ai_for_1 = null):
	var g = blank_game([{"faction": 1, "human": true}, {"faction": 2, "human": false}, {"faction": 3, "human": false}])
	var x := pick_hub(3)
	var la := land_adj(x)
	var y: int = la[0]
	var z: int = la[1]
	set_t(g, x, 1, {"inf": 6})
	set_t(g, y, 0, {"inf": 3})
	set_t(g, z, 2, {"tank": 30})
	if ai_for_1 != null:
		g.ais[1] = ai_for_1.new(g, 1)
	return {"g": g, "x": x, "y": y, "z": z}


func test_pacts_rules() -> void:
	print("- diplomazia: regole dei patti (in round)")
	var S: Dictionary = pact_scene()
	var g = S["g"]
	var x: int = S["x"]
	var y: int = S["y"]
	var z: int = S["z"]
	var evs: Array = []
	g.event.connect(func(n, d): evs.append([n, d]))
	ok(not g.has_pact(0, 1) and g.pacts.is_empty(), "nessun patto iniziale")
	var ai_ai: Dictionary = g.propose_pact(1, 2)
	ok(not ai_ai["ok"] and not ai_ai["accepted"], "niente patti tra IA (%s)" % ai_ai["reason"])
	var ev: Dictionary = g.pact_evaluation(1, 0)
	ok(ev["accept"], "valutazione favorevole (%s, ratio %.1f)" % [ev["reason"], ev["ratio"]])
	var r: Dictionary = g.propose_pact(0, 1)
	ok(r["ok"] and r["accepted"], "patto accettato (%s)" % r["reason"])
	ok(g.has_pact(0, 1) and g.has_pact(1, 0) and g.pacts.size() == 1, "has_pact simmetrico")
	ok(g.pact_until(0, 1) == g.round + 5, "durata 5 round (fino al round %d)" % g.pact_until(0, 1))
	var pe := evs.filter(func(e): return e[0] == "pact")
	ok(pe.size() == 1 and pe[0][1].has("a") and pe[0][1].has("b") and pe[0][1].has("until"), "evento pact {a, b, until}")
	var logged := false
	for e in g.events:
		if str(e["text"]).find("Patto di non aggressione") >= 0:
			logged = true
	ok(logged, "patto nel registro")
	act(g, 0)
	var s1: Dictionary = g.attack(y, x, F({"inf": 1}))
	ok(not s1["ok"] and s1["reason"].find("Patto di non aggressione con") == 0 and s1["reason"].find("round") > 0, "attacco al partner rifiutato (%s)" % s1["reason"])
	act(g, 1)
	var s2: Dictionary = g.attack(x, y, F({"inf": 1}))
	ok(not s2["ok"] and s2["reason"].find("Patto") == 0, "l'IA non può attaccare il partner")
	var tg_ok := true
	for v in g.attack_targets(1, x):
		if v["idx"] == y:
			tg_ok = false
	ok(tg_ok, "il partner non è tra i bersagli")
	act(g, 0)
	g.players[0]["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	var c1: Dictionary = g.play_cards(0, [0, 1, 2], "sabotaggio", x)
	ok(not c1["ok"] and c1["reason"].find("Patto") == 0 and g.players[0]["cards"].size() == 3, "OPS sul partner rifiutate, carte non consumate")
	var again: Dictionary = g.propose_pact(0, 1)
	ok(not again["ok"] and again["reason"].find("già in vigore") >= 0, "un solo patto per IA col giocatore")
	var all: Dictionary = g.propose_pact(0, 2)
	ok(not all["ok"] and all["reason"].find("tutti") >= 0, "non si può essere in pace con tutti (%s)" % all["reason"])
	ok(g.pact_partners(0) == [1], "pact_partners")
	var until: int = g.pact_until(0, 1)
	var guard := 0
	while g.round <= until and guard < 20:
		guard += 1
		next_round(g)
		if g.round <= until:
			ok(g.has_pact(0, 1), "patto valido al round %d" % g.round)
	ok(not g.has_pact(0, 1) and g.pacts.is_empty(), "il patto scade dopo il round %d" % until)
	ok(evs.filter(func(e): return e[0] == "pact_end").size() == 1, "evento pact_end")
	ok(g.pact_cooldown(0, 1) >= 2, "ricarica in round dopo la fine del patto (%d)" % g.pact_cooldown(0, 1))
	var cd: Dictionary = g.propose_pact(0, 1)
	ok(not cd["ok"] and cd["reason"].find("riprova") >= 0, "ricarica rispettata (%s)" % cd["reason"])
	act(g, 0)
	g.terr[y]["forces"] = F({"inf": 3})
	ok(g.attack(y, x, F({"inf": 1}))["ok"], "dopo il patto si può attaccare")
	g._pact_cd = {}
	var ra: Dictionary = g.propose_pact(0, 1)
	ok(ra["ok"] and not ra["accepted"] and ra["reason"].find("attaccata") >= 0, "rifiuto dopo un attacco recente (%s)" % ra["reason"])
	ok(g.pact_cooldown(0, 1) > 0, "ricarica anche dopo un rifiuto")
	next_round(g)
	next_round(g)
	g._pact_cd = {}
	var extra := 0
	for tr in g.terr:
		if tr["owner"] < 0 and extra < 6 and tr["idx"] != x and tr["idx"] != z:
			tr["owner"] = 0
			extra += 1
	ok(g.is_leader(0), "il giocatore è il leader")
	var rl: Dictionary = g.propose_pact(0, 1)
	ok(rl["ok"] and not rl["accepted"] and rl["reason"].find("corsa al dominio") >= 0, "niente patto col leader (%s)" % rl["reason"])
	for tr in g.terr:
		if tr["owner"] == 0 and tr["idx"] != y:
			tr["owner"] = -1
	g._pact_cd = {}
	g.terr[z]["forces"] = F({"inf": 1})
	var rn: Dictionary = g.propose_pact(0, 1)
	ok(rn["ok"] and not rn["accepted"], "nessun altro fronte: rifiuto (%s)" % rn["reason"])
	g._pact_cd = {}
	g.terr[z]["forces"] = F({"tank": 4})
	g.terr[x]["forces"] = F({"tank": 30})
	var rv: Dictionary = g.propose_pact(0, 1)
	ok(rv["ok"] and not rv["accepted"], "IA in vantaggio sul confine: rifiuto (%s)" % rv["reason"])
	g._pact_cd = {}
	g.terr[x]["forces"] = F({"inf": 6})
	g.terr[z]["forces"] = F({"tank": 4})
	var ev_calm: Dictionary = g.pact_evaluation(1, 0)
	g._note_aggression(2, 1)
	var ev_hit: Dictionary = g.pact_evaluation(1, 0)
	ok(ev_hit["ratio"] > ev_calm["ratio"], "attacchi recenti altrove aumentano l'interesse (%.2f > %.2f)" % [ev_hit["ratio"], ev_calm["ratio"]])


func test_pact_offers() -> void:
	print("- diplomazia: offerte delle IA al giocatore")
	var S: Dictionary = pact_scene()
	var g = S["g"]
	var evs: Array = []
	g.event.connect(func(n, d): evs.append([n, d]))
	var r: Dictionary = g.propose_pact(1, 0)
	ok(r["ok"] and not r["accepted"] and g.pact_offers.size() == 1, "offerta registrata")
	var po := evs.filter(func(e): return e[0] == "pact_offer")
	ok(po.size() == 1 and po[0][1]["from"] == 1 and po[0][1]["to"] == 0, "evento pact_offer {from, to}")
	ok(int(g.pact_offers[0]["until"]) == g.round + 1, "offerta valida fino al round successivo")
	var a: Dictionary = g.answer_pact(1, 0, true)
	ok(a["ok"] and a["accepted"] and g.has_pact(0, 1) and g.pact_offers.is_empty(), "offerta accettata: patto")
	var a2: Dictionary = g.answer_pact(1, 0, true)
	ok(not a2["ok"], "nessuna seconda risposta")
	var S2: Dictionary = pact_scene()
	var g2 = S2["g"]
	var evs2: Array = []
	g2.event.connect(func(n, d): evs2.append([n, d]))
	g2.propose_pact(1, 0)
	var no: Dictionary = g2.answer_pact(1, 0, false)
	ok(no["ok"] and not no["accepted"] and not g2.has_pact(0, 1), "offerta respinta")
	ok(not g2.propose_pact(1, 0)["ok"], "dopo il rifiuto: ricarica")
	g2._pact_cd = {}
	g2.propose_pact(1, 0)
	next_round(g2)
	ok(g2.pact_offers.size() == 1, "offerta ancora valida nel round successivo")
	next_round(g2)
	ok(g2.pact_offers.is_empty() and not g2.has_pact(0, 1), "offerta scaduta dopo un round")
	ok(evs2.filter(func(e): return e[0] == "pact_offer_end").size() == 1, "evento pact_offer_end")
	ok(not g2.answer_pact(1, 0, true)["ok"], "risposta tardiva rifiutata")


func test_ai_respects_pact() -> void:
	print("- diplomazia: l'IA rispetta i patti")
	if AIS == null:
		print("  (ai.gd assente)")
		return
	var S0: Dictionary = pact_scene(AIS)
	var g0 = S0["g"]
	g0.terr[S0["x"]]["forces"] = F({"inf": 20, "tank": 12})
	g0.terr[S0["y"]]["forces"] = F({"inf": 1})
	g0.terr[S0["z"]]["forces"] = F({"inf": 2})
	for i in 3:
		next_round(g0)
	ok(g0.terr[S0["y"]]["owner"] == 1, "controllo: senza patto l'IA conquista il territorio debole")
	var S: Dictionary = pact_scene(AIS)
	var g = S["g"]
	var x: int = S["x"]
	var y: int = S["y"]
	g.terr[x]["forces"] = F({"inf": 20, "tank": 12})
	g.terr[y]["forces"] = F({"inf": 1})
	g.terr[S["z"]]["forces"] = F({"inf": 2})
	g.propose_pact(1, 0)
	ok(g.answer_pact(1, 0, true)["accepted"], "patto firmato")
	var atk := {"n": 0}
	g.event.connect(func(n, d):
		if n == "attack" and int(d["player"]) == 1 and int(d["defender"]) == 0:
			atk["n"] += 1)
	for i in 3:
		next_round(g)
	ok(g.terr[y]["owner"] == 0 and atk["n"] == 0, "con il patto l'IA non attacca il partner")


func test_ai_offers_pact() -> void:
	print("- diplomazia: l'IA propone un patto quando è sotto pressione altrove")
	if AIS == null:
		return
	var S: Dictionary = pact_scene(AIS)
	var g = S["g"]
	var offers: Array = []
	g.event.connect(func(n, d): if n == "pact_offer": offers.append(d))
	g.terr[S["x"]]["forces"] = F({"inf": 6})
	g.terr[S["y"]]["forces"] = F({"inf": 4})
	g.terr[S["z"]]["forces"] = F({"tank": 30})
	for i in 2:
		next_round(g)
		if offers.size() > 0:
			break
	ok(offers.size() == 1 and offers[0]["from"] == 1 and offers[0]["to"] == 0, "pact_offer dall'IA sotto pressione (%d)" % offers.size())
	var S2: Dictionary = pact_scene(AIS)
	var g2 = S2["g"]
	var off2: Array = []
	g2.event.connect(func(n, d): if n == "pact_offer": off2.append(d))
	g2.terr[S2["x"]]["forces"] = F({"inf": 20})
	g2.terr[S2["z"]]["forces"] = F({"inf": 1})
	for i in 2:
		next_round(g2)
	ok(off2.is_empty(), "nessuna offerta senza pressione")


# ---------------------------------------------------------------- serializzazione
func test_serialization() -> void:
	print("- serializzazione di vet, nebbia e patti")
	var S: Dictionary = pact_scene()
	var g = S["g"]
	g.fog = true
	g.opts["fog"] = true
	var x: int = S["x"]
	var y: int = S["y"]
	g.terr[y]["vet"] = 2
	g.terr[y]["xp"] = 5
	g.terr[y]["forces"] = F({"inf": 10})
	g.propose_pact(0, 1)
	ok(g.has_pact(0, 1), "patto in vigore")
	g._note_aggression(0, 2)
	g.pact_offers.append({"from": 2, "to": 0, "until": g.round + 1})
	var txt: String = g.to_json()
	var h = GameS.from_json(txt)
	ok(h != null, "ricarica riuscita")
	if h == null:
		return
	ok(h.fog == true and h.opts["fog"] == true, "fog salvata")
	ok(int(h.terr[y]["vet"]) == 2 and int(h.terr[y]["xp"]) == 5, "vet/xp dei territori")
	ok(h.has_pact(0, 1) and h.pact_until(0, 1) == g.pact_until(0, 1), "patti")
	ok(h.pact_offers.size() == 1 and h.pact_offers[0]["from"] == 2, "offerte")
	ok(h.pact_cooldown(0, 1) == g.pact_cooldown(0, 1), "ricariche")
	ok(h.attacked_recently(0, 2), "memoria degli attacchi")
	var sg: Dictionary = g.serialize()
	var sh: Dictionary = h.serialize()
	sg.erase("ais")
	sh.erase("ais")
	ok(JSON.stringify(sh) == JSON.stringify(sg), "serialize() identico dopo la ricarica")
	act(h, 0)
	ok(h.is_visible(0, x) and not h.attack(y, x, F({"inf": 1}))["ok"], "dopo la ricarica il patto blocca ancora")
	var old: Dictionary = g.serialize()
	old.erase("pacts")
	old.erase("pact_offers")
	old.erase("pact_cd")
	old.erase("aggr")
	old["opts"].erase("fog")
	for t in old["terr"]:
		t.erase("vet")
		t.erase("xp")
		t.erase("fresh")
		t.erase("fort")
	var h2 = GameS.deserialize(old)
	ok(h2 != null and h2.fog == false and h2.pacts.is_empty() and int(h2.terr[y]["vet"]) == 0 and h2.terr[y]["fort"]["bunker"] == 0, "chiavi mancanti: valori di default")
	for gg in [g, h, h2]:
		if gg != null:
			gg.dispose()
