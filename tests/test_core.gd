extends SceneTree
## Collaudo headless del nucleo (Combat + Game) — FASE 6: tabellone a turni. Uso:
##   node tools/godot_run.js -- --headless --path . --script tests/test_core.gd [-- --full]
## Gli script che usano l'autoload Data vanno caricati in _initialize (non in _init).

var D            # autoload Data
var GameS: Script
var CombatS: Script
var fails := 0
var checks := 0


## IA minimale a turni per i test: schiera il pool al QG, recluta fanteria e passa (attacca un neutrale debole se può)
class StubAI:
	extends RefCounted
	var g
	var me: int
	var stage := 3
	var stats := {"ms": 0.0, "maxMs": 0.0, "errors": 0}
	func _init(game, idx: int) -> void:
		g = game
		me = idx
	func begin_turn() -> void:
		stage = 0
	func turn_step() -> bool:
		var P: Dictionary = g.players[me]
		if stage == 0:
			if P["hq"] >= 0 and g.terr[P["hq"]]["owner"] == me:
				g.place_pool(me, P["hq"])
				g.recruit(me, P["hq"], "inf", 2)
			stage = 1
			return true
		if stage == 1:
			stage = 2
			for ti in g.territories_of(me):
				var n: int = 0
				for k in g.terr[ti]["forces"]:
					n += g.terr[ti]["forces"][k]
				if n < 8:
					continue
				for v in g.attack_targets(me, ti):
					var o: Dictionary = g.terr[v["idx"]]
					var m := 0
					for k in o["forces"]:
						m += o["forces"][k]
					if m * 2 < n:
						var f: Dictionary = g.terr[ti]["forces"].duplicate()
						f["inf"] = maxi(0, f["inf"] - 1)
						if g.attack(ti, v["idx"], f)["ok"]:
							return true
			return true
		stage = 3
		return false


func _initialize() -> void:
	D = root.get_node("Data")
	CombatS = load("res://scripts/core/combat.gd")
	GameS = load("res://scripts/core/game.gd")
	if GameS == null or CombatS == null:
		print("FALLITO: script non caricati")
		quit(1)
		return
	var full := OS.get_cmdline_user_args().has("--full")
	test_combat()
	test_game_basics()
	test_turn_flow()
	test_attack_rules()
	test_move_rules()
	test_fortify()
	test_market()
	test_cards()
	test_pending_flow()
	test_human_defender()
	test_ai_pacing()
	test_pace()
	test_hq_capture_and_victory()
	test_regional_setup()
	test_stub_match()
	if ResourceLoader.exists("res://scripts/core/ai.gd"):
		test_real_ai_matches(full)
	else:
		print("(ai.gd assente: salto le partite con l'IA vera)")
	print("\n== test_core: ", checks, " verifiche, ", fails, " fallite ==")
	quit(1 if fails > 0 else 0)


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


func new_game(o: Dictionary):
	if not o.has("ai_step_delay"):
		o["ai_step_delay"] = 0.0
	return GameS.new(o)


## Mette p di turno (inizio turno pulito: reddito, rinforzi...)
func turn_of(g, p: int, rnd: int = -1) -> void:
	if rnd > 0:
		g.round = rnd
	g._begin_turn(p)


## Un territorio di p confinante via terra con un territorio di target_owner (lo crea se serve): {from, to}
func border(g, p: int, target_owner: int) -> Dictionary:
	for t in g.territories_of(p):
		for j in D.TERRITORIES[t]["adj"]:
			if not D.TERRITORIES[t]["sea"].has(j) and g.terr[j]["owner"] == target_owner:
				return {"from": t, "to": j}
	var t0: int = g.territories_of(p)[0]
	var j2: int = D.TERRITORIES[t0]["adj"][0]
	g.terr[j2]["owner"] = target_owner
	return {"from": t0, "to": j2}


func test_combat() -> void:
	print("- combat")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var m0 := {"atk": 1.0, "unit": {}, "hp": {}}
	var wins := 0
	for i in 50:
		var r: Dictionary = CombatS.resolve_battle(F({"inf": 10}), F({"inf": 3}), m0, m0, rng)
		if r["winner"] == "att":
			wins += 1
		ok(D.total_units(r["def"]) == 0 or r["winner"] == "def", "difensore annientato se vince l'att")
		ok(r["att"]["inf"] <= 10 and r["att"]["inf"] >= 0, "superstiti <= iniziali")
		ok(r["attLosses"]["inf"] == 10 - r["att"]["inf"], "perdite coerenti")
	ok(wins >= 48, "10 FAN battono 3 FAN (%d/50)" % wins)
	var r2: Dictionary = CombatS.resolve_battle(F({"inf": 3}), F({"inf": 10, "tank": 2}), m0, m0, rng)
	ok(r2["winner"] == "def" and D.total_units(r2["att"]) == 0, "3 FAN perdono contro 10 FAN + 2 CAR")
	ok(D.total_units(r2["def"]) > 0, "il difensore vincente ha superstiti")
	var r3: Dictionary = CombatS.resolve_battle(F({"tank": 2}), F({}), m0, m0, rng)
	ok(r3["winner"] == "att" and r3["att"]["tank"] == 2, "attacco su territorio vuoto")
	var r4: Dictionary = CombatS.resolve_battle(F({"jet": 4}), F({"aa": 8}), m0, m0, rng)
	ok(r4["winner"] == "def", "la contraerea ferma i jet")
	var r5: Dictionary = CombatS.resolve_battle(F({"inf": 2}), F({"jet": 2}), m0, m0, rng)
	ok(r5["rounds"] >= 1, "battaglia FAN vs JET termina (%s)" % r5["winner"])
	var p: Dictionary = CombatS.predict_battle(F({"inf": 10, "tank": 3}), F({"inf": 5}), m0, m0)
	ok(p["winner"] == "att" and p["attLeft"] > 0.3 and p["defLeft"] == 0.0, "previsione 10F+3C vs 5F")
	var p2: Dictionary = CombatS.predict_battle(F({"inf": 5}), F({"inf": 5}), m0, {"atk": 1.5, "unit": {}, "hp": {}})
	ok(p2["winner"] == "def" and p2["defLeft"] > 0.0, "a parità vince il difensore fortificato")
	ok(absf(CombatS.force_power(F({"inf": 1})) - 1.0) < 1e-9, "force_power fanteria = 1")
	ok(CombatS.force_power(null) == 0.0, "force_power(null)")
	ok(absf(CombatS.force_power(F({"tank": 1})) - 3.0) < 1e-9, "force_power carro")
	# modificatori
	var g = new_game({"players": [{"faction": 1, "human": false}, {"faction": 3, "human": false}], "seed": 3, "ai_script": StubAI})
	var hq: int = g.players[0]["hq"]
	var md: Dictionary = CombatS.combat_mods(g, 0, "def", hq, {})
	var ter: Dictionary = D.TERRAINS[D.TERRITORIES[hq]["ter"]]
	ok(absf(md["atk"] - ter["def"] * D.ECON["hqDef"]) < 1e-6, "difesa QG × terreno (%.3f)" % md["atk"])
	ok(absf(md["hp"]["tank"] - 1.2) < 1e-9 and absf(md["unit"]["art"] - 1.25) < 1e-9, "dottrina FO (carri +20% hp, art +25%)")
	var ma: Dictionary = CombatS.combat_mods(g, 0, "att", hq, {"fromIdx": hq, "sea": true})
	ok(absf(ma["atk"] - D.ECON["seaLandingPenalty"]) < 1e-6, "penalità di sbarco")
	var ma2: Dictionary = CombatS.combat_mods(g, 0, "att", hq, {"manual": true})
	ok(absf(ma2["atk"] - 1.0) < 1e-9, "manuale +10% solo per gli umani")
	var hq_ul: int = g.players[1]["hq"]
	var mg: Dictionary = CombatS.combat_mods(g, 1, "def", hq_ul, {})
	ok(mg["atk"] > 1.0, "difesa UL")




# ---------------------------------------------------------------- base
func test_game_basics() -> void:
	print("- base e produzione a turni")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false, "difficulty": "generale"}], "seed": 42, "ai_script": StubAI})
	ok(g.human_idx == 0, "human_idx")
	ok(g.players[0]["color"] is Color, "colore come Color")
	ok(g.players[0]["hq"] == D.TERR_INDEX["pianure"] and g.players[1]["hq"] == D.TERR_INDEX["russia"], "QG regionali")
	ok(g.territories_of(0).size() == 5 and g.territories_of(1).size() == 5, "5 territori a testa")
	ok(g.deck.size() == 44, "mazzo 42+2")
	ok(g.ais[0] == null and g.ais[1] != null, "IA solo per i non umani")
	ok(g.round == 1 and g.current == 0 and g.phase == "rifornimento" and g.is_human_turn(), "si parte dal turno dell'umano, round 1")
	var ts: Dictionary = g.turn_status()
	for k in ["round", "player", "phase", "attack_used", "move_used", "truce_rounds_left", "human_turn", "next_player", "round_limit", "rounds_left", "ai_turn", "waiting"]:
		ok(ts.has(k), "turn_status." + k)
	ok(ts["truce_rounds_left"] == 2 and ts["next_player"] == 1 and g.round_limit == 120, "tregua 2 round, limite 120")
	ok(g.players[0]["pool"]["inf"] == g.reinforce_amount(0), "rinforzi del primo turno nel pool")
	var hq: int = g.players[0]["hq"]
	ok(g.has_building(hq, "caserma") and g.has_building(hq, "fabbrica"), "QG = caserma+fabbrica")
	ok(g.cost_for(0, "jet")["money"] == roundi(85 * 0.75), "AAN aerei -25%")
	ok(g.research_cost(0)["turns"] == 2, "AAN ricerca Tech 2 in 2 turni (2 × 0.75 per eccesso)")
	ok(g.research_cost(1)["turns"] == 2, "ricerca Tech 2 in 2 turni")
	var r: Dictionary = g.recruit(0, hq, "inf", 3)
	ok(r["ok"] and r["count"] == 3 and g.terr[hq]["queue"].size() == 3, "reclutamento ×3")
	ok(g.terr[hq]["queue"][0]["total"] == 1 and g.terr[hq]["queue"][0]["t"] == 0, "fanteria: 1 turno")
	ok(g.recruit(0, hq, "tank", 1)["ok"] and g.terr[hq]["queue"][3]["total"] == 2, "carri: 2 turni")
	ok(not g.can_recruit(0, hq, "heli")["ok"], "elicotteri richiedono Tech 2")
	ok(not g.recruit(1, g.players[1]["hq"], "inf", 1)["ok"], "fuori turno: niente reclutamento")
	ok(g.can_recruit(1, g.players[1]["hq"], "inf")["reason"] == "Non è il tuo turno", "motivo: non è il tuo turno")
	ok(not g.build(0, hq, "porto")["ok"], "porto solo sulla costa (le Pianure non lo sono)")
	var b: Dictionary = g.build(0, hq, "impianto")
	ok(b["ok"] and g.terr[hq]["building"]["total"] == 2, "costruisci impianto (2 turni): " + b["reason"])
	ok(not g.build(0, hq, "bunker")["ok"], "una costruzione alla volta")
	ok(g.research(0)["ok"], "ricerca avviata")
	# schieramento parziale del pool
	var pool0: int = g.players[0]["pool"]["inf"]
	var inf0: int = g.terr[hq]["forces"]["inf"]
	ok(g.place_pool(0, hq, {"inf": 2})["ok"] and g.players[0]["pool"]["inf"] == pool0 - 2 and g.terr[hq]["forces"]["inf"] == inf0 + 2, "schiera 2 unità del pool")
	ok(g.place_pool(0, hq)["ok"] and D.total_units(g.players[0]["pool"]) == 0, "schiera il resto del pool")
	var inf1: int = g.terr[hq]["forces"]["inf"]
	var built := {"n": 0, "rec": 0}
	g.event.connect(func(name, _data):
		if name == "built":
			built["n"] += 1
		elif name == "recruited":
			built["rec"] += 1)
	var m0: float = g.players[0]["res"]["money"]
	ok(g.end_turn()["ok"], "fine turno")
	ok(g.terr[hq]["forces"]["inf"] == inf1 + 3 and built["rec"] == 3, "fanteria pronta a fine turno")
	ok(g.terr[hq]["queue"].size() == 1 and g.terr[hq]["queue"][0]["t"] == 1, "carro a metà produzione")
	ok(g.current == 1 and g.round == 1, "tocca all'IA")
	g.update(0.1)   # IA istantanea (ai_step_delay 0)
	ok(g.current == 0 and g.round == 2, "di nuovo l'umano, round 2")
	ok(g.players[0]["res"]["money"] > m0, "reddito a inizio turno")
	ok(g.end_turn()["ok"], "fine turno 2")
	ok(g.terr[hq]["forces"]["tank"] >= 5 and g.terr[hq]["buildings"].has("impianto") and built["n"] >= 1, "carro e impianto completati dopo 2 turni")
	ok(g.players[0]["tech"] == 2, "Tech 2 dopo 2 turni")
	# reddito per turno = rates
	g.update(0.1)
	var P: Dictionary = g.players[0]
	var before: Dictionary = P["res"].duplicate()
	g.end_turn()
	g.update(0.1)
	ok(g.current == 0, "ciclo di turni")
	ok(absf(P["res"]["money"] - before["money"] - P["rates"]["money"]) < 1.0, "reddito del turno = rates (%.1f vs %.1f)" % [P["res"]["money"] - before["money"], P["rates"]["money"]])


# ---------------------------------------------------------------- ciclo dei turni
func test_turn_flow() -> void:
	print("- ciclo dei turni, fasi, eventi")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}, {"faction": 3, "human": false}], "seed": 7, "ai_script": StubAI})
	var ev := {}
	var order: Array = []
	g.event.connect(func(n, d):
		ev[n] = ev.get(n, 0) + 1
		if n == "turn_start":
			order.append(int(d["player"])))
	ok(g.end_phase()["phase"] == "attacco", "fine fase: attacco")
	ok(g.end_phase()["phase"] == "spostamento", "fine fase: spostamento")
	ok(not g.recruit(0, g.players[0]["hq"], "inf", 1)["ok"], "reclutamento solo in rifornimento")
	g.end_phase()   # = fine turno
	ok(g.current == 1 and ev.get("turn_end", 0) == 1 and ev.get("phase", 0) == 2, "fine turno dalla fase spostamento")
	for i in 3:
		g.update(0.1)
	ok(order == [1, 2, 0], "ordine dei turni: 1, 2, poi l'umano (%s)" % str(order))
	ok(g.round == 2 and ev.get("round", 0) == 1, "nuovo round")
	ok(g.history.size() >= 2 and g.history[-1]["round"] == 2, "un'istantanea per round")
	# eliminato: saltato
	for t in g.territories_of(1):
		g._capture(t, 2, F({"inf": 3}))
	ok(not g.players[1]["alive"], "giocatore 1 eliminato")
	order.clear()
	g.end_turn()
	g.update(0.1)
	ok(order[0] == 2 and g.current == 0, "il giocatore eliminato non gioca più")
	ok(g.events[-1].has("round"), "il registro riporta il round")


# ---------------------------------------------------------------- attacco
func test_attack_rules() -> void:
	print("- attacco: uno per turno, almeno 1 unità resta, tregua")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 21, "auto_battles": true, "ai_script": StubAI,
		"attacks_per_turn": 1})   # regola base (nella tregua iniziale delle partite libere sarebbero 2: vedi test_pace)
	var s := border(g, 0, -1)
	g.terr[s["from"]]["forces"] = F({"inf": 20, "tank": 6})
	g.terr[s["to"]]["forces"] = F({"inf": 2})
	g.players[0]["res"]["oil"] = 1000.0
	var all_f := F({"inf": 20, "tank": 6})
	var r: Dictionary = g.attack(s["from"], s["to"], all_f)
	ok(not r["ok"] and r["reason"].begins_with("Almeno un'unità"), "almeno un'unità resta: " + r["reason"])
	ok(not g.attack(s["from"], s["to"], F({}))["ok"], "nessuna unità scelta")
	var anim0: int = g.divisions.size()
	var evs := {}
	g.event.connect(func(n, d): evs[n] = d)
	r = g.attack(s["from"], s["to"], F({"inf": 15, "tank": 6}))
	ok(r["ok"] and not r["pending"] and r["result"] != null, "attacco risolto subito (auto_battles)")
	ok(g.terr[s["to"]]["owner"] == 0, "neutrale conquistato")
	ok(g.terr[s["from"]]["forces"]["inf"] == 5 and g.terr[s["from"]]["forces"]["tank"] == 0, "a casa restano le unità non inviate")
	ok(g.attack_used and g.phase == "attacco", "attacco usato, fase attacco")
	ok(evs.has("attack") and evs["attack"]["type"] == "attack" and evs["attack"]["from"] == s["from"], "evento attack")
	ok(g.divisions.size() == anim0 + 1 and g.divisions[-1]["anim"], "record di animazione")
	ok(int(g.terr[s["to"]]["regroup"]) == 1 and int(g.terr[s["to"]]["unrest"]) == 2, "riorganizzazione 1 turno, occupazione 2 turni")
	ok(g.players[0]["cards"].size() == 1, "carta alla conquista")
	# secondo attacco rifiutato
	var s2 := {}
	for t in g.territories_of(0):
		if t == s["to"]:
			continue
		for j in D.TERRITORIES[t]["adj"]:
			if g.terr[j]["owner"] == -1:
				s2 = {"from": t, "to": j}
	g.terr[s2["from"]]["forces"] = F({"inf": 30})
	r = g.attack(s2["from"], s2["to"], F({"inf": 10}))
	ok(not r["ok"] and r["reason"] == "Hai già attaccato in questo turno", "un solo attacco per turno")
	ok(not g.attack(s["to"], s2["to"], F({"inf": 1}))["ok"], "dal territorio appena conquistato non si parte")
	for i in 30:
		g.update(0.1)
	ok(g.divisions.size() == 0, "animazioni concluse")
	# tregua contro i giocatori (round 1-2), poi ammessa
	g.end_turn()
	g.update(0.1)
	var e := border(g, 0, 1)
	g.terr[e["from"]]["forces"] = F({"inf": 40, "tank": 10})
	g.terr[e["from"]]["regroup"] = 0
	g.terr[e["to"]]["forces"] = F({"inf": 1})
	ok(g.round == 2, "round 2")
	r = g.attack(e["from"], e["to"], F({"inf": 30}))
	ok(not r["ok"] and r["reason"].begins_with("Tregua"), "tregua nei primi 2 round: " + r["reason"])
	var found := false
	for v in g.attack_targets(0, e["from"]):
		if v["idx"] == e["to"]:
			found = true
	ok(not found, "durante la tregua i giocatori non sono bersagli")
	g.end_turn()
	g.update(0.1)
	ok(g.round == 3 and g.turn_status()["truce_rounds_left"] == 0, "tregua finita al round 3")
	g.terr[e["to"]]["owner"] = 1
	g.terr[e["to"]]["forces"] = F({"inf": 1})
	g.terr[e["from"]]["forces"] = F({"inf": 40, "tank": 10})
	r = g.attack(e["from"], e["to"], F({"inf": 30}))
	ok(r["ok"] and g.terr[e["to"]]["owner"] == 0, "dal round 3 si attaccano i giocatori")
	# sconfitta: i superstiti tornano subito a casa
	g.end_turn()
	g.update(0.1)
	var s3 := border(g, 0, -1)
	g.terr[s3["from"]]["forces"] = F({"inf": 12})
	g.terr[s3["from"]]["regroup"] = 0
	g.terr[s3["to"]]["forces"] = F({"inf": 30, "tank": 10})
	CombatS.set("tactical", false)
	r = g.attack(s3["from"], s3["to"], F({"inf": 11}))
	CombatS.set("tactical", true)
	ok(r["ok"] and r["result"]["winner"] == "def" and g.terr[s3["to"]]["owner"] == -1, "attacco respinto")
	ok(g.terr[s3["from"]]["forces"]["inf"] == 1 + r["result"]["att"]["inf"], "superstiti rientrati subito")


# ---------------------------------------------------------------- spostamento
func test_move_rules() -> void:
	print("- spostamento: uno per turno, solo attraverso territori propri")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 23, "ai_script": StubAI})
	var mine: Array = g.territories_of(0)
	var hq: int = g.players[0]["hq"]
	var dst := -1
	for t in mine:
		if t != hq and g.move_targets(0, hq).has(t):
			dst = t
			break
	ok(dst >= 0, "destinazione collegata")
	g.terr[hq]["forces"] = F({"inf": 10, "tank": 2})
	ok(not g.move(hq, dst, F({"inf": 10, "tank": 2}))["ok"], "almeno 1 unità resta")
	var far := -1
	for t in g.terr:
		if t["owner"] == 1:
			far = t["idx"]
	ok(not g.move(hq, far, F({"inf": 2}))["ok"], "solo verso territori propri")
	# territorio proprio isolato (non collegato)
	var iso := -1
	for t in g.terr:
		if t["owner"] == -1 and not g.move_targets(0, hq).has(t["idx"]):
			var adj_mine := false
			for j in D.TERRITORIES[t["idx"]]["adj"]:
				if g.terr[j]["owner"] == 0:
					adj_mine = true
			if not adj_mine:
				iso = t["idx"]
				break
	g.terr[iso]["owner"] = 0
	var cm: Dictionary = g.can_move(hq, iso, F({"inf": 1}))
	ok(not cm["ok"] and cm["reason"].begins_with("Destinazione non collegata"), "serve un collegamento di territori propri")
	var evs := {}
	g.event.connect(func(n, d): evs[n] = d)
	var d0: int = D.total_units(g.terr[dst]["forces"])
	ok(g.move(hq, dst, F({"inf": 6, "tank": 2}))["ok"], "spostamento")
	ok(D.total_units(g.terr[dst]["forces"]) == d0 + 8 and g.terr[hq]["forces"]["inf"] == 4, "forze spostate")
	ok(g.move_used and g.phase == "spostamento" and evs.has("move") and evs["move"]["type"] == "move", "fase spostamento + evento move")
	ok(not g.move(hq, dst, F({"inf": 1}))["ok"], "un solo spostamento per turno")
	var s := border(g, 0, -1)
	g.terr[s["from"]]["forces"] = F({"inf": 20})
	ok(not g.attack(s["from"], s["to"], F({"inf": 10}))["ok"], "dopo lo spostamento non si attacca")


# ---------------------------------------------------------------- fortificazioni
func test_fortify() -> void:
	print("- fortificazioni (livelli 0-3)")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 31, "ai_script": StubAI})
	var hq: int = g.players[0]["hq"]
	var P: Dictionary = g.players[0]
	P["res"]["money"] = 5000.0
	P["res"]["steel"] = 5000.0
	P["res"]["manpower"] = 5000.0
	ok(g.terr[hq]["fort"] == {"trench": 0, "mines": 0, "bunker": 0}, "terr.fort iniziale")
	ok(g.fort_cost(hq, "trench")["money"] == D.FORT["trench"]["cost"]["money"], "costo livello 1")
	var m0: float = P["res"]["money"]
	ok(g.fortify(0, hq, "trench")["ok"] and g.fort_level(hq, "trench") == 1, "trincee livello 1")
	ok(absf(m0 - P["res"]["money"] - D.FORT["trench"]["cost"]["money"]) < 1e-6, "pagato il livello 1")
	ok(g.fort_cost(hq, "trench")["money"] == 2 * D.FORT["trench"]["cost"]["money"], "costo livello 2 = 2×")
	g.fortify(0, hq, "trench")
	g.fortify(0, hq, "trench")
	ok(g.fort_level(hq, "trench") == 3 and g.fort_cost(hq, "trench") == null, "livello massimo 3")
	ok(not g.fortify(0, hq, "trench")["ok"], "oltre il 3 rifiutato")
	ok(not g.fortify(0, hq, "muro")["ok"], "tipo sconosciuto")
	ok(g.fortify(0, hq, "mines")["ok"] and g.fortify(0, hq, "bunker")["ok"] and g.fortify(0, hq, "bunker")["ok"], "mine 1, bunker 2")
	ok(not g.fortify(0, g.players[1]["hq"], "trench")["ok"], "solo sui propri territori")
	g.end_phase()
	ok(not g.fortify(0, hq, "mines")["ok"], "solo in rifornimento")
	# battaglia: setup.def.fort e modificatori dell'auto-risoluzione
	var att_from := -1
	for j in D.TERRITORIES[hq]["adj"]:
		att_from = j
		break
	g.terr[att_from]["owner"] = 1
	var info := {"attacker": 1, "terr": hq, "from": att_from, "sea": false, "vet": 0}
	var plain := {"attacker": 1, "terr": hq, "from": att_from, "sea": false, "vet": 0}
	var mf: Dictionary = g.battle_mods(info, false, true)
	var mn: Dictionary = g.battle_mods(plain, false, false)
	ok(mf["modsD"]["hp"]["inf"] > float(mn["modsD"]["hp"].get("inf", 1.0)) + 0.15, "trincee: fanteria del difensore più resistente")
	ok(mf["modsA"]["atk"] < mn["modsA"]["atk"] and mf["modsD"]["atk"] > mn["modsD"]["atk"], "mine e bunker nei modificatori")
	g.pending_battle = {"id": 99, "attacker": 1, "defender": 0, "terr": hq, "from": att_from, "forces": F({"inf": 10}), "sea": false, "vet": 0, "xp": 0, "human_side": "def"}
	var setup: Dictionary = g.start_manual_battle()
	ok(setup["def"]["fort"] == {"trench": 3, "mines": 1, "bunker": 2}, "setup.def.fort: " + str(setup["def"].get("fort")))
	ok(setup["def"]["mods"]["hp"].get("inf", 1.0) == mn["modsD"]["hp"].get("inf", 1.0), "battaglia 3D: niente doppio conteggio nei mods")
	ok(setup["def"]["human"] and not setup["att"]["human"], "difensore umano nel setup")
	g.pending_battle = null
	g._manual = null
	# conquista: trincee e mine azzerate, bunker -1
	g._capture(hq, 1, F({"inf": 3}))
	ok(g.terr[hq]["fort"] == {"trench": 0, "mines": 0, "bunker": 1}, "conquista: fortificazioni ridotte " + str(g.terr[hq]["fort"]))


# ---------------------------------------------------------------- mercato
func test_market() -> void:
	print("- mercato")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 5, "ai_script": StubAI})
	var P: Dictionary = g.players[0]
	var trades := {"n": 0}
	g.event.connect(func(name, _d): if name == "trade": trades["n"] += 1)
	var p_sell: int = g.market_price(0, "oil", "sell")
	var p_buy: int = g.market_price(0, "steel", "buy")
	ok(p_sell == 60 and p_buy == 160, "prezzi iniziali 60/160")
	var m0: float = P["res"]["money"]
	var o0: float = P["res"]["oil"]
	ok(g.trade(0, "oil", "sell")["ok"], "vendi petrolio")
	ok(absf(P["res"]["money"] - m0 - 60) < 1e-6 and absf(P["res"]["oil"] - o0 + 100) < 1e-6, "saldo vendita")
	ok(g.market_price(0, "oil", "sell") < p_sell, "vendere abbassa il prezzo")
	ok(g.trade(0, "steel", "buy")["ok"], "compra acciaio")
	ok(g.market_price(0, "steel", "buy") > p_buy, "comprare alza il prezzo")
	ok(not g.trade(0, "money", "buy")["ok"], "denaro non scambiabile")
	ok(not g.trade(0, "oil", "x")["ok"], "operazione non valida")
	P["res"]["manpower"] = 50.0
	ok(not g.trade(0, "manpower", "sell")["ok"], "lotto insufficiente")
	ok(trades["n"] == 2, "segnali trade")
	ok(not g.trade(1, "oil", "sell")["ok"], "mercato fuori turno rifiutato")
	var before: float = P["market"]["oil"]
	for i in 3:
		g.end_turn()
		g.update(0.1)
	ok(P["market"]["oil"] > before and P["market"]["oil"] < 1.0, "il prezzo torna verso 1 a ogni turno")


# ---------------------------------------------------------------- carte / OPS
func test_cards() -> void:
	print("- carte e OPS")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 9, "ai_script": StubAI})
	var P: Dictionary = g.players[0]
	ok(g.is_valid_set([{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]), "tris uguale")
	ok(g.is_valid_set([{"type": "inf"}, {"type": "tank"}, {"type": "air"}]), "tris diverso")
	ok(g.is_valid_set([{"type": "inf"}, {"type": "tank"}, {"type": "jolly"}]), "tris con jolly")
	ok(not g.is_valid_set([{"type": "inf"}, {"type": "inf"}, {"type": "tank"}]), "tris non valido")
	P["cards"] = [{"type": "tank"}, {"type": "inf"}, {"type": "tank"}, {"type": "tank"}]
	ok(g.find_set(0) == [0, 2, 3], "find_set")
	ok(not g.play_cards(0, [0, 0, 2], "rinforzi")["ok"], "carte duplicate")
	ok(not g.play_cards(0, [0, 1, 2], "rinforzi")["ok"], "tris non valido rifiutato")
	var pool0: Dictionary = P["pool"].duplicate()
	var r: Dictionary = g.play_cards(0, [0, 2, 3], "rinforzi")
	ok(r["ok"], "rinforzi")
	ok(P["pool"]["tank"] == pool0["tank"] + 2 and P["pool"]["inf"] == pool0["inf"] + 2 and P["sets_traded"] == 1 and P["cards"].size() == 1, "rinforzi corazzati 4 = 2C+2F")
	ok(g.set_value(0) == 6, "valore tris successivo")
	P["sets_traded"] = 8
	ok(g.set_value(0) == 15 + 5 * 3, "valore tris oltre la tabella")
	var tgt: int = g.players[1]["hq"]
	P["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "jolly"}]
	var rt: Dictionary = g.play_cards(0, [0, 1, 2], "missile", tgt)
	ok(not rt["ok"] and rt["reason"].begins_with("Tregua"), "tregua: niente operazioni sui giocatori")
	g.round = 3
	g.terr[tgt]["forces"] = F({"inf": 20, "tank": 10})
	ok(not g.play_cards(0, [0, 1, 2], "missile", g.players[0]["hq"])["ok"], "missile su sé stessi rifiutato")
	r = g.play_cards(0, [0, 1, 2], "missile", tgt)
	ok(r["ok"], "missile")
	var left: int = D.total_units(g.terr[tgt]["forces"])
	ok(left >= 18 and left <= 21, "missile 35%% (%d rimaste)" % left)
	ok(g.effects.size() >= 2, "effetti missile")
	P["cards"] = [{"type": "air"}, {"type": "air"}, {"type": "air"}]
	ok(g.play_cards(0, [0, 1, 2], "sabotaggio", tgt)["ok"], "sabotaggio")
	ok(g.terr[tgt]["sabotage"] == 2, "sabotaggio 2 turni")
	ok(g.terr_income(tgt)["money"] == 0.0, "sabotato: niente reddito")
	P["cards"] = [{"type": "inf"}, {"type": "tank"}, {"type": "air"}]
	ok(not g.play_cards(0, [0, 1, 2], "golpe", tgt)["ok"], "golpe vietato su QG/forze grandi")
	ok(P["cards"].size() == 3, "carte non consumate se rifiutato")
	var weak := -1
	for t in g.territories_of(1):
		if t != tgt:
			weak = t
			break
	g.terr[weak]["forces"] = F({"inf": 5, "tank": 1})
	r = g.play_cards(0, [0, 1, 2], "golpe", weak)
	ok(r["ok"] and g.terr[weak]["owner"] == 0, "golpe riuscito")
	ok(g.terr[weak]["forces"]["inf"] == 2 and g.terr[weak]["forces"]["tank"] == 0, "golpe: metà delle forze (per difetto)")
	ok(g.terr[weak]["unrest"] > 0 and g.terr[weak]["regroup"] > 0, "occupazione e riorganizzazione")
	ok(P["cards"].size() == 0, "golpe senza carta")
	# il sabotaggio dura 2 turni del proprietario
	g.end_turn()
	ok(g.current == 1 and g.terr[tgt]["sabotage"] == 2, "sabotaggio intatto fino al turno del proprietario")
	ok(not g.can_recruit(1, tgt, "inf")["ok"], "sabotato: niente reclutamento")
	g.end_turn()
	ok(g.terr[tgt]["sabotage"] == 1, "sabotaggio −1 a fine turno del proprietario")
	var neutral := -1
	for t in g.terr:
		if t["owner"] == -1:
			neutral = t["idx"]
			break
	P["cards"] = []
	g._capture(neutral, 0, F({"inf": 3}))
	ok(P["cards"].size() == 1, "carta comando alla conquista")
	P["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	g._draw_card(0)
	ok(P["cards"].size() == D.HAND_MAX, "mano massima")
	ok(not g.hire_mercs(0, g.players[0]["hq"])["ok"], "mercenari solo UL")


# ---------------------------------------------------------------- battaglia in attesa (attaccante umano)
func _make_pending(g, target_owner: int, att: Dictionary, def: Dictionary) -> Dictionary:
	var s := border(g, 0, target_owner)
	g.current = 0
	g.phase = "rifornimento"
	g.attack_used = false
	g.move_used = false
	g.terr[s["from"]]["forces"] = F(att)
	g.terr[s["from"]]["forces"]["inf"] += 1   # quella che resta
	g.terr[s["from"]]["regroup"] = 0
	g.terr[s["to"]]["forces"] = F(def)
	g.players[0]["res"]["oil"] = 1000.0
	var r: Dictionary = g.attack(s["from"], s["to"], F(att))
	ok(r["ok"] and r["pending"], "attacco con battaglia in attesa: " + r["reason"])
	return s


func test_pending_flow() -> void:
	print("- battaglia in attesa / manuale (attaccante umano)")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 21, "ai_script": StubAI})
	var pend := {"n": 0}
	g.event.connect(func(name, _d): if name == "pending": pend["n"] += 1)
	var s := _make_pending(g, -1, {"inf": 10, "tank": 4}, {"inf": 4})
	ok(g.pending_battle != null and pend["n"] == 1 and g.pending_battle["human_side"] == "att", "pending_battle (human_side att) + segnale")
	ok(not g.end_turn()["ok"] and g.turn_status()["waiting"] == "battle", "niente fine turno con una battaglia in attesa")
	var setup: Dictionary = g.start_manual_battle()
	ok(setup.has("terrIdx") and setup["terrIdx"] == s["to"] and setup["att"]["forces"]["inf"] == 10, "setup battaglia")
	ok(setup["att"]["color"] is Color and setup["def"]["color"] is Color, "colori Color nel setup")
	ok(setup["def"]["name"] == "Neutrali" and setup.has("support") and setup["def"].has("bunkers") and setup["def"].has("fort"), "setup difensore")
	ok(setup["att"]["human"] and setup["att"]["mods"]["atk"] > 1.05, "manuale umano +10%")
	var res: Dictionary = g.finish_manual_battle({"att": {"inf": 8, "tank": 4}, "def": {}, "winner": "att", "retreated": false})
	ok(res["ok"] and g.pending_battle == null, "fine battaglia manuale")
	ok(g.terr[s["to"]]["owner"] == 0 and g.terr[s["to"]]["forces"]["inf"] == 8, "conquista dopo vittoria manuale")
	# ritirata: i superstiti tornano subito
	s = _make_pending(g, -1, {"inf": 6}, {"inf": 6})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": 4}, "def": {"inf": 5}, "winner": "att", "retreated": true})
	ok(g.terr[s["to"]]["owner"] == -1 and g.terr[s["to"]]["forces"]["inf"] == 5, "ritirata: il difensore resta")
	ok(g.terr[s["from"]]["forces"]["inf"] == 5, "ritirata: 4 superstiti + 1 a casa")
	ok(g.divisions[-1]["retreat"], "animazione della ritirata")
	# autoRest
	s = _make_pending(g, -1, {"inf": 20, "tank": 6}, {"inf": 5})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": 15, "tank": 5}, "def": {"inf": 3}, "winner": "def", "retreated": false, "autoRest": true})
	ok(g.terr[s["to"]]["owner"] == 0, "autoRest: completata in automatico (vince l'att)")
	ok(g.terr[s["to"]]["forces"]["inf"] <= 15 and g.terr[s["to"]]["forces"]["tank"] <= 5, "autoRest: superstiti <= forze inviate")
	s = _make_pending(g, -1, {"inf": 5}, {"inf": 2})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": 99, "tank": 7}, "def": {}, "winner": "att"})
	ok(g.terr[s["to"]]["forces"]["inf"] == 5 and g.terr[s["to"]]["forces"]["tank"] == 0, "superstiti limitati alle forze iniziali")
	s = _make_pending(g, -1, {"inf": 25, "tank": 8}, {"inf": 3})
	var ra: Dictionary = g.resolve_pending_auto()
	ok(ra["ok"] and g.pending_battle == null and g.terr[s["to"]]["owner"] == 0, "resolve_pending_auto")
	ok(g.start_manual_battle().is_empty(), "start_manual_battle senza attesa = {}")
	ok(not g.finish_manual_battle({})["ok"], "finish senza battaglia rifiutato")
	ok(g.end_turn()["ok"], "fine turno dopo la battaglia")
	# compatibilità: send_division → attack/move
	var g2 = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 22, "auto_battles": true, "ai_script": StubAI})
	var s2 := border(g2, 0, -1)
	g2.terr[s2["from"]]["forces"] = F({"inf": 30, "tank": 8})
	g2.terr[s2["to"]]["forces"] = F({"inf": 2})
	var sd: Dictionary = g2.send_division(0, s2["from"], s2["to"], 1.0)
	ok(sd["ok"] and g2.pending_battle == null and g2.terr[s2["to"]]["owner"] == 0, "send_division (compatibilità) = attacco")
	ok(D.total_units(g2.terr[s2["from"]]["forces"]) == 1, "send_division lascia 1 unità")


# ---------------------------------------------------------------- difesa umana
func test_human_defender() -> void:
	print("- difensore umano: battaglia in attesa durante il turno IA")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 41, "ai_script": StubAI})
	g.round = 3
	g.end_turn()
	ok(g.current == 1 and not g.is_human_turn(), "turno IA")
	var s := border(g, 1, 0)
	g.terr[s["from"]]["forces"] = F({"inf": 20, "tank": 5})
	g.terr[s["to"]]["forces"] = F({"inf": 4})
	g.players[1]["res"]["oil"] = 500.0
	var r: Dictionary = g.attack(s["from"], s["to"], F({"inf": 18, "tank": 5}))
	ok(r["ok"] and r["pending"], "l'IA attacca l'umano: battaglia in attesa")
	ok(g.pending_battle["human_side"] == "def" and g.pending_battle["attacker"] == 1 and g.pending_battle["defender"] == 0, "human_side def")
	var cur: int = g.current
	for i in 20:
		g.update(0.5)
	ok(g.current == cur and g.pending_battle != null, "l'IA aspetta la risposta del difensore")
	var setup: Dictionary = g.start_manual_battle()
	ok(setup["def"]["human"] and not setup["att"]["human"] and setup["human_side"] == "def", "setup: il difensore è l'umano")
	ok(setup["def"]["mods"]["atk"] > 1.0, "difesa manuale umana +10%")
	g.finish_manual_battle({"att": {"inf": 2}, "def": {"inf": 3}, "winner": "def"})
	ok(g.terr[s["to"]]["owner"] == 0 and g.pending_battle == null, "difesa riuscita")
	ok(g.terr[s["from"]]["forces"]["inf"] == 4, "superstiti dell'IA rientrati (2 + 2 rimasti)")
	g.update(0.1)
	ok(g.current == 0, "l'IA conclude il turno dopo la battaglia")
	# ask_defense = false: difesa automatica
	var g2 = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 42, "ask_defense": false, "ai_script": StubAI})
	g2.round = 3
	g2.end_turn()
	var s2 := border(g2, 1, 0)
	g2.terr[s2["from"]]["forces"] = F({"inf": 20})
	g2.terr[s2["to"]]["forces"] = F({"inf": 2})
	r = g2.attack(s2["from"], s2["to"], F({"inf": 19}))
	ok(r["ok"] and not r["pending"] and g2.pending_battle == null, "ask_defense false: difesa automatica")


# ---------------------------------------------------------------- ritmo dei turni IA
class CountAI:
	extends RefCounted
	var g
	var me: int
	var steps := 0
	var left := 0
	var stats := {"ms": 0.0, "maxMs": 0.0, "errors": 0}
	func _init(game, idx: int) -> void:
		g = game
		me = idx
	func begin_turn() -> void:
		left = 4
	func turn_step() -> bool:
		steps += 1
		left -= 1
		return left > 0


# ---------------------------------------------------------------- notte 3: ritmo del tabellone
func test_pace() -> void:
	print("- notte 3: attacchi nella tregua, ordini del comando, eventi mondiali, minacce annunciate, inganni solo con la nebbia")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 71, "auto_battles": true, "ai_script": StubAI})
	ok(g.fog_mode == "none" and not g.fog, "nebbia predefinita: nessuna")
	ok(g.missions_on and g.events_on, "ordini ed eventi accesi nelle partite libere")
	# --- tregua iniziale: due attacchi per turno (solo neutrali attaccabili)
	ok(g.in_truce() and g.attacks_max() == 2 and g.attacks_left() == 2, "tregua: 2 attacchi per turno")
	var s := border(g, 0, -1)
	g.terr[s["from"]]["forces"] = F({"inf": 30})
	g.terr[s["to"]]["forces"] = F({"inf": 1})
	g.players[0]["mission"] = null
	ok(g.attack(s["from"], s["to"], F({"inf": 8}))["ok"] and not g.attack_used and g.attacks_left() == 1, "dopo il primo attacco ne resta uno")
	var s2 := {}
	for j in D.TERRITORIES[s["from"]]["adj"]:
		if g.terr[j]["owner"] != 0:
			s2 = {"from": s["from"], "to": j}
	if s2.is_empty():
		s2 = {"from": s["from"], "to": D.TERRITORIES[s["from"]]["adj"][0]}
	g.terr[s2["to"]]["owner"] = -1
	g.terr[s2["to"]]["forces"] = F({"inf": 1})
	ok(g.attack(s2["from"], s2["to"], F({"inf": 8}))["ok"] and g.attack_used and g.attacks_left() == 0, "secondo attacco: poi basta")
	ok(g.turn_status()["attacks_max"] == 2 and g.turn_status()["attacks_left"] == 0, "turn_status espone gli attacchi")
	turn_of(g, 0, 3)
	ok(not g.in_truce() and g.attacks_max() == 1, "dopo la tregua: 1 attacco per turno")
	g.dispose()
	var gs = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 71, "scenario": "corsa_petrolio", "ai_script": StubAI})
	ok(gs.scenario != null and not gs.missions_on and not gs.events_on and gs.players[0]["mission"] == null, "scenari: niente ordini né eventi")
	ok(gs.attacks_max() == 1, "scenari: un attacco per turno anche nella tregua")
	gs.dispose()
	# --- ordini del comando
	g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 72, "auto_battles": true, "ai_script": StubAI})
	var m = g.mission_of(0)
	ok(m is Dictionary and int(m["until"]) == D.MISSION_ROUNDS and D.MISSION_REWARDS.has(m["reward"]), "ordine del comando assegnato al primo turno (entro il round %d)" % D.MISSION_ROUNDS)
	var mt: int = int(m["terr"])
	var adj_ok := false
	for t in g.territories_of(0):
		if D.TERRITORIES[t]["adj"].has(mt):
			adj_ok = true
	ok(adj_ok and g.terr[mt]["owner"] == -1, "bersaglio confinante e neutrale durante la tregua")
	ok(g.mission_text(0).contains(D.TERRITORIES[mt]["name"]) and g.scenario_targets.has(mt), "testo e segnale sul tabellone")
	for rk in ["card", "reinf", "money"]:
		g.players[0]["mission"] = {"terr": mt, "until": g.round + 1, "reward": rk, "born": g.round}
		g.terr[mt]["owner"] = -1
		var c0: int = g.players[0]["cards"].size()
		var p0: int = int(g.players[0]["pool"]["inf"])
		var m0: float = g.players[0]["res"]["money"]
		g._capture(mt, 0, F({"inf": 2}), {"noCard": true})
		var got: bool = (g.players[0]["cards"].size() == c0 + 1) if rk == "card" else ((int(g.players[0]["pool"]["inf"]) == p0 + 4) if rk == "reinf" else is_equal_approx(g.players[0]["res"]["money"], m0 + 150.0))
		ok(got and g.mission_of(0) == null, "ordine eseguito: premio «%s»" % D.MISSION_REWARDS[rk]["name"])
	ok(int(g.players[0]["stats"].get("missions", 0)) == 3, "ordini eseguiti contati nelle statistiche")
	turn_of(g, 0, 2)
	var m2 = g.mission_of(0)
	ok(m2 is Dictionary and int(m2["terr"]) != mt and int(m2["until"]) == 2 + D.MISSION_ROUNDS - 1, "nuovo ordine al turno successivo")
	var evs := []
	g.event.connect(func(n, _d): evs.append(n))
	turn_of(g, 0, int(m2["until"]) + 1)
	ok(evs.has("objective_failed") and evs.has("objective_new") and g.mission_of(0) is Dictionary, "ordine scaduto e sostituito")
	# --- eventi mondiali
	g.round = 2
	g.world_event = null
	g._next_event = 3
	g._new_round()
	ok(g.round == 3 and g.world_event is Dictionary and evs.has("world_event") and g.world_event_text() != "", "evento mondiale al round 3: " + g.world_event_text())
	ok(g._next_event == 3 + D.WORLD_EVENT_EVERY, "prossimo evento dopo %d round" % D.WORLD_EVENT_EVERY)
	var pt: int = g.territories_of(0)[0]
	g.world_event = {"id": "convoglio", "terr": pt, "round": 5, "born": 3}
	g._update_goal_marks()
	ok(g.scenario_targets.has(pt), "territorio premio segnalato sul tabellone")
	var money0: float = g.players[0]["res"]["money"]
	g.round = 4
	g._new_round()
	ok(g.world_event == null and is_equal_approx(g.players[0]["res"]["money"], money0 + 250.0), "convoglio: chi controlla il territorio incassa 250 $")
	g.world_event = {"id": "offensiva", "terr": -1, "round": g.round + 1, "born": g.round}
	ok(g.attacks_max() == 2, "finestra di bel tempo: un attacco in più")
	g.world_event = null
	var nt := -1
	for tr in g.terr:
		if tr["owner"] == -1:
			for j in D.TERRITORIES[tr["idx"]]["adj"]:
				if g.terr[j]["owner"] >= 0:
					nt = tr["idx"]
	if nt >= 0:
		g.terr[nt]["forces"] = F({"inf": 8, "tank": 2})
		for tr in g.terr:
			if tr["owner"] == -1 and tr["idx"] != nt:
				tr["forces"] = F({"inf": 1})
		var tries := 0
		while tries < 60 and not (g.world_event is Dictionary and g.world_event["id"] == "diserzioni"):
			g.world_event = null
			g._last_event = ""
			g.terr[nt]["forces"] = F({"inf": 8, "tank": 2})
			g._spawn_world_event()
			tries += 1
		ok(g.world_event is Dictionary and g.world_event["id"] == "diserzioni" and int(g.world_event["terr"]) == nt and D.total_units(g.terr[nt]["forces"]) == 5, "diserzioni: presidio neutrale dimezzato")
	g.dispose()
	# --- minacce annunciate
	g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 73, "auto_battles": true, "ai_script": StubAI})
	var b := border(g, 1, 0)
	g.set_intent(1, b["from"], b["to"])
	var th: Array = g.threats_for(0)
	ok(th.size() == 1 and th[0]["player"] == 1 and th[0]["from"] == b["from"] and th[0]["to"] == b["to"] and th[0]["att"] == D.total_units(g.terr[b["from"]]["forces"]), "minaccia annunciata visibile al bersaglio")
	ok(g.threats_for(1).is_empty(), "chi minaccia non vede la propria come minaccia")
	g.fog = true; g.fog_mode = "full"; g._vis_cache.clear()
	ok(g.threats_for(0).size() == 1, "con la nebbia: visibile se il territorio di partenza confina")
	g.fog = false; g.fog_mode = "none"; g._vis_cache.clear()
	g.pacts.append({"a": 0, "b": 1, "until": g.round + 3})
	ok(g.threats_for(0).is_empty(), "con un patto la minaccia non vale")
	g.pacts.clear()
	g.set_intent(1, b["to"], b["from"])
	ok(g.intents[1] == null, "minaccia non valida scartata")
	g.set_intent(1, b["from"], b["to"])
	g.end_turn()
	ok(g.current == 1 and g.intents[1] == null, "la minaccia si toglie quando tocca a chi l'ha annunciata")
	g.dispose()
	# IA vera: annuncia e mantiene spesso
	if ResourceLoader.exists("res://scripts/core/ai.gd"):
		var tact: bool = CombatS.tactical
		CombatS.tactical = false
		var ga = new_game({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 74, "auto_battles": true})
		var cnt := {"threat": 0, "kept": 0, "obj": 0, "wev": 0}
		var ann := {}
		ga.event.connect(func(n, d):
			if n == "threat":
				cnt["threat"] += 1
				ann[int(d["player"])] = int(d["to"])
			elif n == "attack" and ann.get(int(d["player"]), -1) == int(d["to"]):
				cnt["kept"] += 1
				ann.erase(int(d["player"]))
			elif n == "objective_done":
				cnt["obj"] += 1
			elif n == "world_event":
				cnt["wev"] += 1)
		while ga.over == null and ga.round <= 25:
			ga.update(0.1)
		ok(cnt["threat"] >= 10 and cnt["kept"] * 3 >= cnt["threat"], "IA: minacce annunciate %d, mantenute %d" % [cnt["threat"], cnt["kept"]])
		ok(cnt["obj"] >= 5 and cnt["wev"] >= 6, "IA: ordini eseguiti %d, eventi mondiali (inizio+fine) %d" % [cnt["obj"], cnt["wev"]])
		ok(ga.ai_errors == 0, "nessun errore IA")
		ga.dispose()
		CombatS.tactical = tact
	# --- carte inganno solo con la nebbia
	g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 75, "ai_script": StubAI})
	g.players[0]["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	var own_t: int = g.territories_of(0)[0]
	var r: Dictionary = g.play_cards(0, [0, 1, 2], "finta", own_t)
	ok(not r["ok"] and r["reason"].contains("nebbia") and g.players[0]["cards"].size() == 3, "senza nebbia la divisione falsa non si gioca: " + r["reason"])
	ok(not g.op_available("silenzio") and not g.op_available("ricognizione") and g.op_available("missile") and g.op_available("rinforzi"), "op_available")
	g.terr[own_t]["silence"] = 2
	ok(g.visible_forces(1, own_t) != null, "senza nebbia un vecchio silenzio radio non nasconde nulla")
	g.dispose()
	var gf = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 75, "fog_mode": "light", "ai_script": StubAI})
	gf.players[0]["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	ok(gf.op_available("finta") and gf.play_cards(0, [0, 1, 2], "finta", gf.territories_of(0)[0])["ok"], "con la nebbia leggera la divisione falsa si gioca")
	gf.dispose()


func test_ai_pacing() -> void:
	print("- ritmo dei turni IA")
	var g = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 51, "ai_script": CountAI, "ai_step_delay": 0.5})
	ok(g.ai_step_delay == 0.5, "opts.ai_step_delay")
	g.end_turn()
	var ai = g.ais[1]
	# notte 3: attese pesate (0.5× all'inizio del turno, 0.3× dopo un'azione che non è un attacco né uno spostamento)
	g.update(0.2)
	ok(ai.steps == 0, "nessuna azione prima dell'attesa iniziale (metà ritardo)")
	g.update(0.1)
	ok(ai.steps == 1, "prima azione dopo 0.25 s")
	g.update(0.05)
	ok(ai.steps == 1, "attesa breve (0.3×) dopo un'azione senza nulla da guardare")
	g.update(0.1)
	ok(ai.steps == 2, "seconda azione dopo altri 0.15 s")
	g.paused = true
	g.update(5.0)
	ok(ai.steps == 2, "in pausa l'IA si ferma")
	g.paused = false
	g.skip_ai_turn()
	ok(ai.steps == 4 and g.current == 0, "skip_ai_turn completa il turno IA")
	g.update(10.0)
	ok(g.current == 0, "durante il turno umano l'IA non agisce")
	g.speed = 2.0
	g.end_turn()
	g.update(0.1)
	ok(ai.steps == 4, "speed 2: non ancora (attesa iniziale 0.125 s)")
	g.update(0.05)
	ok(ai.steps == 5, "speed 2 dimezza il ritardo")
	# spettatore: turni IA uno dopo l'altro
	var gs = GameS.new({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 52, "ai_script": CountAI, "ai_step_delay": 0.0})
	for i in 6:
		gs.update(0.1)
	ok(gs.round == 3, "spettatore: un turno per update senza ritardo (round %d)" % gs.round)
	# IA senza turn_step / assente: il turno passa comunque
	var gn = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 53, "ai_script": StubAI, "ai_step_delay": 0.0})
	gn.ais[1] = null
	gn.end_turn()
	gn.update(0.1)
	ok(gn.current == 0 and gn.round == 2, "IA assente: turno saltato")


# ---------------------------------------------------------------- QG e vittoria
func test_hq_capture_and_victory() -> void:
	print("- cattura QG, eliminazione, vittoria, limite di round")
	var g = new_game({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 33, "ai_script": StubAI})
	var got := {}
	g.event.connect(func(name, data): got[name] = data)
	var hq1: int = g.players[1]["hq"]
	g.players[1]["res"]["money"] = 1000.0
	var m0: float = g.players[0]["res"]["money"]
	g.players[1]["research"] = {"level": 2, "t": 0, "total": 2}
	g._capture(hq1, 0, F({"inf": 5}))
	ok(got.has("hqLost") and got["hqLost"]["player"] == 1, "segnale hqLost")
	ok(g.players[1]["hq"] != hq1 and g.players[1]["hq"] >= 0, "nuovo QG spostato")
	ok(g.players[1]["research"] == null, "ricerca persa")
	ok(absf(g.players[1]["res"]["money"] - 700.0) < 1e-6 and absf(g.players[0]["res"]["money"] - m0 - 300.0) < 1e-6, "30% del denaro sottratto")
	for t in g.territories_of(1):
		g._capture(t, 0, F({"inf": 2}))
	ok(not g.players[1]["alive"] and got.has("eliminated") and g.players[1]["stats"]["eliminatedAt"] == 1.0, "giocatore eliminato (round)")
	ok(g.over == null, "partita non finita con 2 vivi")
	for t in g.terr:
		if t["owner"] != 2 and t["owner"] != 0:
			t["owner"] = 0
	g._check_victory()
	ok(g.over != null and g.over["winner"] == 0 and got.has("victory"), "vittoria per quota")
	var g2 = new_game({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}], "seed": 34, "mode": "obiettivo", "ai_script": StubAI})
	ok(g2.players[0]["objective"] != null and g2.players[0]["objective"].has("text"), "obiettivo assegnato")
	for t in g2.territories_of(1):
		g2._capture(t, 0, F({"inf": 2}))
	g2._check_victory()
	ok(g2.over != null and g2.over["winner"] == 0, "vittoria per eliminazione: " + str(g2.over))
	var g3 = new_game({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 35, "mode": "obiettivo", "ai_script": StubAI})
	g3.players[1]["objective"] = {"type": "count", "count": 24, "text": "Conquista 24 territori"}
	g3.players[0]["objective"] = {"type": "continents", "conts": ["SA", "AF"], "text": "Conquista il Sud America e l'Africa"}
	g3.players[2]["objective"] = {"type": "eliminate", "target": 1, "text": "Elimina FO"}
	for t in D.CONT_TERR["SA"] + D.CONT_TERR["AF"]:
		if g3.terr[t]["owner"] != 0 and g3.terr[t]["owner"] >= 0 and g3.territories_of(g3.terr[t]["owner"]).size() <= 1:
			continue
		g3.terr[t]["owner"] = 0
	g3._check_victory()
	ok(g3.over != null and g3.over["winner"] == 0 and g3.over["reason"].begins_with("Obiettivo segreto"), "vittoria per obiettivo continenti: " + str(g3.over))
	var g5 = new_game({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 37, "mode": "obiettivo", "ai_script": StubAI})
	g5.players[2]["objective"] = {"type": "eliminate", "target": 1, "text": "Elimina FO"}
	g5.players[0]["objective"] = {"type": "count", "count": 40, "text": "x"}
	for t in g5.territories_of(1):
		g5._capture(t, 0, F({"inf": 2}))
	ok(g5.players[2]["objective"]["type"] == "count" and g5.players[2]["objective"]["count"] == 24, "obiettivo elimina convertito in 24 territori")
	# limite di round: vince chi ha più territori
	var g6 = new_game({"players": [{"faction": 0, "human": false}, {"faction": 1, "human": false}], "seed": 38, "ai_script": CountAI})
	g6.round = 120
	g6.terr[D.TERR_INDEX["messico"]]["owner"] = 1
	for i in 4:
		g6.update(0.1)
	ok(g6.over != null and g6.over["winner"] == 1 and str(g6.over["reason"]).begins_with("Limite"), "limite di round: vince chi ha più territori " + str(g6.over))


func test_regional_setup() -> void:
	print("- partenze regionali")
	for n in [2, 3, 4]:
		for seed in [1, 2, 3]:
			var pl := []
			for i in n:
				pl.append({"faction": i, "human": false})
			var g = new_game({"players": pl, "seed": seed, "ai_script": StubAI})
			for i in n:
				var mine: Array = g.territories_of(i)
				if i == 2:
					# CP: l'Oceania (4 territori, troppo piccola per vietarla) e nient'altro
					ok(mine.size() == 4 and g.owns_continent(i, "OC"), "%dp: CP con la sola Oceania" % n)
				else:
					ok(mine.size() == 5, "%dp: 5 territori" % n)
				for c in D.CONT_KEYS:
					if c != "OC":
						ok(not g.owns_continent(i, c), "%dp: nessun continente completo all'inizio (%s)" % [n, c])
				# partenze contigue: ogni territorio raggiunge il QG passando solo per territori propri
				var seen := {g.players[i]["hq"]: true}
				var q: Array = [g.players[i]["hq"]]
				while q.size() > 0:
					var a: int = q.pop_front()
					for bb in D.TERRITORIES[a]["adj"]:
						if g.terr[bb]["owner"] == i and not seen.has(bb):
							seen[bb] = true
							q.append(bb)
				ok(seen.size() == mine.size(), "%dp: partenze contigue (%d/%d)" % [n, seen.size(), mine.size()])
			if n == 4:
				ok(g.terr[D.TERR_INDEX["messico"]]["owner"] == -1, "Messico neutrale (cuscinetto tra AAN e UL)")
				# connessi via terra al QG? (BFS solo via terra, salvo isole)
			var gr = new_game({"players": pl, "seed": seed, "distribution": "casuale", "ai_script": StubAI})
			var tot := 0
			for i in n:
				tot += gr.territories_of(i).size()
				ok(gr.terr[gr.players[i]["hq"]]["owner"] == i, "casuale: QG proprio")
			ok(tot == (28 if n == 2 else 42), "casuale: distribuzione (%d)" % tot)


func _check_state(g, tag: String) -> bool:
	for p in g.players:
		for k in p["res"]:
			var v: float = p["res"][k]
			if is_nan(v) or is_inf(v):
				print("  NaN in ", tag, " ", k)
				return false
	for t in g.terr:
		for k in t["forces"]:
			if not (t["forces"][k] is int) or t["forces"][k] < 0:
				print("  forze non valide in ", tag, " ", t["idx"], " ", t["forces"])
				return false
	return true



func test_stub_match() -> void:
	print("- partita 4 giocatori con IA-stub (30 round)")
	var pl := []
	var diffs := ["recluta", "veterano", "generale", "veterano"]
	for i in 4:
		pl.append({"faction": i, "human": false, "difficulty": diffs[i]})
	var g = new_game({"players": pl, "seed": 11, "auto_battles": true, "ai_script": StubAI})
	var sig := {}
	g.event.connect(func(name, _d): sig[name] = sig.get(name, 0) + 1)
	var good := true
	var t0 := Time.get_ticks_msec()
	while g.over == null and g.round <= 30:
		g.update(0.1)
		if not _check_state(g, "stub"):
			good = false
			break
	ok(good and _check_state(g, "stub-fine"), "stato valido")
	ok(sig.get("battle", 0) > 0 and sig.get("capture", 0) > 0, "battaglie e conquiste avvenute")
	ok(sig.get("turn_start", 0) >= 4 * 29 and sig.get("round", 0) >= 29, "turni e round")
	var owners := []
	for i in 4:
		owners.append(g.territories_of(i).size())
	print("  round %d, territori %s, over %s, %d ms" % [g.round, owners, g.over, Time.get_ticks_msec() - t0])


func test_real_ai_matches(full: bool) -> void:
	print("- partite con l'IA vera (ai.gd)")
	var cases := [
		{"n": 4, "mode": "conquista", "dist": "regionale", "d": ["recluta", "veterano", "generale", "veterano"]},
		{"n": 4, "mode": "obiettivo", "dist": "regionale", "d": ["veterano", "veterano", "veterano", "veterano"]},
		{"n": 2, "mode": "conquista", "dist": "casuale", "d": ["generale", "generale"]},
		{"n": 3, "mode": "obiettivo", "dist": "casuale", "d": ["recluta", "generale", "veterano"]},
		{"n": 2, "mode": "conquista", "dist": "regionale", "d": ["veterano", "veterano"]},
	]
	var seeds := [11, 12] if full else [11]
	if not full:
		cases = cases.slice(0, 2)
	CombatS.set("tactical", false)   # risoluzione con la formula: test veloce
	for ci in cases.size():
		var c: Dictionary = cases[ci]
		for seed in seeds:
			var pl := []
			for i in c["n"]:
				pl.append({"faction": (i + ci) % 4, "human": false, "difficulty": c["d"][i]})
			var g = new_game({"players": pl, "mode": c["mode"], "distribution": c["dist"], "seed": seed, "auto_battles": true})
			var real := true
			for a in g.ais:
				if a == null or a is StubAI:
					real = false
			ok(real, "IA vera caricata")
			var t0 := Time.get_ticks_msec()
			while g.over == null and g.round <= 125:
				g.update(0.1)
			ok(_check_state(g, "ai"), "stato valido (IA vera)")
			ok(g.over != null and g.over["winner"] >= 0, "vincitore entro il limite di round (caso %d seed %d)" % [ci, seed])
			var mx := 0.0
			var tot := 0.0
			var turns := 0
			for a in g.ais:
				mx = maxf(mx, float(a.stats["maxMs"]))
				tot += float(a.stats["ms"])
				turns += int(a.stats.get("turns", 0))
			ok(tot / maxf(1.0, turns) < 50.0, "turno IA medio < 50 ms (%.1f ms, max %.1f)" % [tot / maxf(1.0, turns), mx])
			var w: String = g.players[g.over["winner"]]["fac"]["short"] if g.over != null and g.over["winner"] >= 0 else "-"
			print("  ", ci, " ", c["n"], "p ", c["mode"], " ", c["dist"], " seed ", seed, " -> ", w, " ",
				(g.over["reason"] if g.over != null else "nessun vincitore"), " round %d (%d ms)" % [g.round, Time.get_ticks_msec() - t0])
			g.dispose()
	CombatS.set("tactical", true)
