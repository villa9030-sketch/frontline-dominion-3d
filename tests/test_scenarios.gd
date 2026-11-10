extends SceneTree
## Collaudo headless degli scenari (FASE 4, a turni dalla FASE 6): dati di Scenarios.LIST, regole applicate da Game,
## vittorie speciali (in round), serializzazione e partite tutte IA che arrivano a una conclusione senza errori.
## Uso: node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_scenarios.gd [-- --seeds=1,2 --quick=1]

var D            # autoload Data
var GameS: Script
var ScS: Script
var fails := 0
var checks := 0
var logger


class ErrCount extends Logger:
	var errors := 0
	var first: Array = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors += 1
		if first.size() < 5:
			first.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		mutex.unlock()
	func _log_message(_m: String, _e: bool) -> void:
		pass


## IA che non fa nulla (prove controllate): passa il turno
class NullAI:
	extends RefCounted
	var stats := {"ms": 0.0, "maxMs": 0.0, "errors": 0}
	func _init(_g, _i: int) -> void:
		pass
	func turn_step() -> bool:
		return false


func _initialize() -> void:
	logger = ErrCount.new()
	OS.add_logger(logger)
	D = root.get_node("Data")
	GameS = load("res://scripts/core/game.gd")
	ScS = load("res://scripts/core/scenarios.gd")
	load("res://scripts/core/combat.gd").set("tactical", false)
	if GameS == null or ScS == null:
		print("FALLITO: script non caricati")
		quit(1)
		return
	test_list()
	test_normal_game()
	test_setup()
	test_round_limit()
	test_siege()
	test_hold()
	test_serialization()
	if _arg("quick", "0") != "1":
		test_ai_games()
	ok(logger.errors == 0, "nessun errore di script (%d: %s)" % [logger.errors, str(logger.first)])
	print("\n== test_scenarios: ", checks, " verifiche, ", fails, " fallite ==")
	quit(1 if fails > 0 else 0)


func _process(_d: float) -> bool:
	return true


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FALLITO: ", what)


func new_game(id: String, human := -1, extra := {}):
	var o := {"players": ScS.make_players(id, human, "veterano"), "seed": 7, "auto_battles": true, "scenario": id, "ai_script": NullAI, "ai_step_delay": 0.0}
	var S: Dictionary = ScS.find(id)
	o["distribution"] = S.get("distribution", "regionale")
	o["fog"] = S.get("fog", false)
	o.merge(extra, true)
	return GameS.new(o)


## uguaglianza profonda con tolleranza sui numeri
func same(x, y) -> bool:
	if (x is int or x is float) and (y is int or y is float):
		return absf(float(x) - float(y)) <= 1e-6 * maxf(1.0, absf(float(x)))
	if x is Dictionary and y is Dictionary:
		if x.size() != y.size():
			return false
		for k in x:
			if not y.has(k) or not same(x[k], y[k]):
				return false
		return true
	if x is Array and y is Array:
		if x.size() != y.size():
			return false
		for i in x.size():
			if not same(x[i], y[i]):
				return false
		return true
	return x == y


## Avanza fino al round r (tutti passano il turno)
func to_round(g, r: int) -> void:
	var guard := 0
	while g.over == null and g.round < r and guard < 2000:
		guard += 1
		if g.pending_battle != null:
			g.resolve_pending_auto()
		elif g.is_human_turn():
			g.end_turn()
		else:
			g.update(0.1)


func fac_idx(g, f: int) -> int:
	for P in g.players:
		if P["faction"] == f:
			return P["idx"]
	return -1


# ------------------------------------------------------------------ dati
func test_list() -> void:
	print("- Scenarios.LIST")
	var L: Array = ScS.LIST
	ok(L.size() >= 4, "almeno 4 scenari (%d)" % L.size())
	var seen := {}
	for S in L:
		var id := str(S.get("id", ""))
		ok(id != "" and not seen.has(id), "id valido e unico: " + id)
		seen[id] = true
		for k in ["name", "desc", "objective"]:
			ok(str(S.get(k, "")).length() > 3, id + ": campo " + k)
		ok(int(S.get("faction", -1)) >= 0 and int(S.get("faction", -1)) < 4, id + ": fazione consigliata")
		ok(int(S.get("opp", 0)) >= 1 and int(S.get("opp", 0)) <= 3, id + ": avversari 1..3")
		ok(int(S.get("round_limit", 0)) >= 10 and int(S.get("round_limit", 0)) <= 120, id + ": limite di round (ogni scenario finisce)")
		ok(not S.has("time_limit"), id + ": niente più limite in secondi")
		ok(S.get("mode") == "conquista" and S.get("distribution") in ["regionale", "casuale"], id + ": modalità/distribuzione")
		for t in S.get("focus", []):
			ok(int(t) >= 0 and int(t) < D.TERRITORIES.size(), id + ": territorio chiave valido")
		var R: Dictionary = S.get("rules", {})
		for fid in R.get("fac", {}):
			var F: Dictionary = R["fac"][fid]
			for t in F.get("start", []):
				ok(D.TERR_INDEX.has(t), id + ": partenza " + str(t))
			ok(F.get("hq") == null or F.get("start", []).has(F["hq"]), id + ": QG tra le partenze")
		if R.has("hold"):
			for t in R["hold"]["terrs"]:
				ok(D.TERR_INDEX.has(t), id + ": territorio chiave " + str(t))
			var fo: Array = S.get("focus", [])
			ok(fo.size() == R["hold"]["terrs"].size(), id + ": focus = territori chiave")
			ok(int(R["hold"].get("rounds", 0)) >= 1 and not R["hold"].has("secs"), id + ": hold in round")
		ok(ScS.find(id) == S, id + ": find()")
	ok(ScS.find("inesistente").is_empty(), "find() di un id sconosciuto -> {}")
	var mp: Array = ScS.make_players("mondo_diviso", 3, "generale")
	ok(mp.size() == 2 and mp[0]["faction"] == 3 and mp[0]["human"] and not mp[1]["human"] and mp[1]["difficulty"] == "generale", "make_players 2 giocatori")
	mp = ScS.make_players("blocco_acciaio", -1)
	ok(mp.size() == 4 and not mp[0]["human"] and mp[0]["faction"] == 1, "make_players spettatore: fazione consigliata in testa")


func test_normal_game() -> void:
	print("- partita normale invariata")
	var g = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1}], "seed": 3, "ai_script": NullAI})
	ok(g.scenario == null and g.opts["scenario"] == "", "nessuno scenario")
	ok(g.scenario_status(0).is_empty(), "scenario_status vuoto")
	ok(g.truce_rounds == 2 and g.victory_share == float(D.ECON["victoryShare"]) and g.round_limit == 120 and g.time_limit == 0.0, "regole di base (tregua 2 round, limite 120)")
	var g2 = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1}], "seed": 3, "ai_script": NullAI, "scenario": "boh"})
	ok(g2.scenario == null and g2.opts["scenario"] == "", "id sconosciuto: partita normale")
	g.dispose()
	g2.dispose()


# ------------------------------------------------------------------ regole
func test_setup() -> void:
	print("- regole di partenza")
	var g = new_game("guerra_lampo", 1)
	ok(g.scenario is Dictionary and g.scenario["id"] == "guerra_lampo" and g.opts["scenario"] == "guerra_lampo", "scenario attivo")
	ok(g.truce_rounds == 1 and g.victory_share == 0.6 and g.round_limit == 25, "tregua, quota e limite dello scenario")
	ok(absf(float(g.players[0]["res"]["money"]) - float(g.players[0]["rates"]["money"]) - 2.0 * float(D.ECON["startRes"]["money"])) < 1e-3, "risorse iniziali raddoppiate (+ reddito del primo turno)")
	var hq: int = g.players[0]["hq"]
	ok(int(g.terr[hq]["forces"]["inf"]) == 14 and int(g.terr[hq]["forces"]["tank"]) == 7, "forze iniziali ×1.75 (%s)" % str(g.terr[hq]["forces"]))
	ok(g.players[0]["human"] and g.human_idx == 0, "giocatore umano")
	var neu := 0
	for P in g.players:
		var a: int = P["idx"]
		for P2 in g.players:
			if P2["idx"] != a and P["alive"]:
				pass
	for tr in g.terr:
		if tr["owner"] < 0:
			neu += 1
	ok(neu > 10, "restano territori neutrali")
	g.round = 2
	var me: int = 0
	var tgt := -1
	var src := -1
	for t in g.territories_of(me):
		for j in D.TERRITORIES[t]["adj"]:
			if g.terr[j]["owner"] >= 0 and g.terr[j]["owner"] != me:
				tgt = j
				src = t
	if tgt >= 0:
		g.terr[src]["forces"]["inf"] += 5
		ok(g.attack(src, tgt, {"inf": 3})["ok"], "attacco possibile dopo 1 round di tregua")
	g.dispose()

	g = new_game("assedio_pacifico", 0)
	var cp := fac_idx(g, 2)
	ok(cp >= 0 and g.siege_idx == cp, "assediato: CP")
	var cps: Array = g.territories_of(cp)
	cps.sort()
	ok(cps == [38, 39, 40, 41], "CP parte con l'Oceania (%s)" % str(cps))
	ok(g.players[cp]["hq"] == D.TERR_INDEX["ausest"], "QG di CP in Australia orientale")
	ok(g.owns_continent(cp, "OC"), "CP possiede l'Oceania")
	ok(g.pacts.is_empty(), "assedio senza alleanze: nessun patto")
	ok(float(g.players[cp]["res"]["money"]) > float(D.ECON["startRes"]["money"]) * 1.15, "CP ricca")
	var inc_cp: Dictionary = g.income_of(cp)
	g._scen_income[cp] = 1.0
	var inc_1: Dictionary = g.income_of(cp)
	ok(absf(inc_cp["money"] - 1.1 * inc_1["money"]) < 1e-6, "reddito di CP ×1.1")
	g._scen_income[cp] = 1.1
	for P in g.players:
		if P["idx"] != cp:
			ok(P["objective"] != null and P["objective"]["type"] == "eliminate" and P["objective"]["target"] == cp, "obiettivo: eliminare CP")
		else:
			ok(P["objective"] != null and P["objective"]["type"] == "survive", "obiettivo di CP: resistere")
	for P in g.players:
		ok(g.territories_of(P["idx"]).size() >= 4, "%s ha i suoi territori" % P["fac"]["short"])
	var st: Dictionary = g.scenario_status(0)
	ok(st.get("text", "") != "" and st.get("progress", "").begins_with("CP: 4") and int(st["rounds_left"]) == 30 and int(st["time_left"]) == 30, "scenario_status (%s)" % str(st))
	g.dispose()

	g = new_game("blocco_acciaio", 0)
	var fo := fac_idx(g, 1)
	ok(g.siege_idx == fo and g.territories_of(fo).size() == 13 and g.owns_continent(fo, "EU"), "FO parte con Europa e Asia settentrionale")
	ok(g.players[fo]["hq"] == D.TERR_INDEX["russia"], "QG di FO in Russia")
	ok(g.scenario_targets == [D.TERR_INDEX["russia"]], "scenario_targets = QG dell'assediata")
	var allies: Array = []
	for P in g.players:
		if P["idx"] != fo:
			allies.append(P["idx"])
	ok(g.pacts.size() == 3, "patti tra i tre alleati (%d)" % g.pacts.size())
	for a in allies:
		ok(not g.has_pact(a, fo), "nessun patto con FO")
		for b in allies:
			if a < b:
				ok(g.has_pact(a, b) and g.pact_until(a, b) > g.round_limit, "alleanza fino alla fine")
	ok(g.players[0]["objective"]["text"].contains("3 territori"), "obiettivo dell'alleanza")
	g.dispose()

	g = new_game("corsa_petrolio", 3)
	ok(g.hold_terrs.size() == 5 and g.hold_need == 3 and g.hold_rounds == 2, "territori chiave (2 round)")
	ok(g.scenario_targets == g.hold_terrs, "scenario_targets = territori chiave")
	for P in g.players:
		ok(P["objective"]["type"] == "hold" and P["objective"]["terrs"] == g.hold_terrs, "obiettivo hold per tutti")
	g.dispose()

	g = new_game("mondo_diviso", 2, {"players": [{"faction": 2, "human": true}, {"faction": 0}, {"faction": 1}, {"faction": 3}]})
	ok(g.players.size() == 2 and g.players[0]["human"] and g.opts["distribution"] == "casuale" and g.fog, "2 giocatori (anche se ne arrivano 4), casuale, nebbia")
	g.dispose()


func test_round_limit() -> void:
	print("- limite di round")
	var g = new_game("blocco_acciaio", 0)
	var fo := fac_idx(g, 1)
	to_round(g, g.round_limit)
	ok(g.over == null and g.round == g.round_limit, "ultimo round in corso")
	to_round(g, g.round_limit + 1)
	ok(g.over != null and g.over["winner"] == fo and str(g.over["reason"]).contains("resistito"), "FO resiste fino all'ultimo round: vince (%s)" % str(g.over))
	g.dispose()
	g = new_game("guerra_lampo", -1)
	var t_free := -1
	for tr in g.terr:
		if tr["owner"] < 0:
			t_free = tr["idx"]
			break
	g.terr[t_free]["owner"] = 2
	g.round = g.round_limit
	to_round(g, g.round_limit + 1)
	ok(g.over != null and g.over["winner"] == 2 and str(g.over["reason"]).contains("Round esauriti"), "allo scadere vince chi ha più territori (%s)" % str(g.over))
	g.dispose()


func test_siege() -> void:
	print("- assedio")
	# alleanza: FO ridotta a 3 territori -> vince l'alleanza (umano incluso)
	var g = new_game("blocco_acciaio", 0)
	var fo := fac_idx(g, 1)
	g.round = 4
	var mine: Array = g.territories_of(fo)
	var k := 0
	for t in mine:
		if t != g.players[fo]["hq"] and k < mine.size() - 3:
			g.terr[t]["owner"] = 2 if fo != 2 else 3
			k += 1
	g._supply_dirty = true
	g._check_victory()
	ok(g.over != null and g.over["winner"] == 0 and g.over.get("team", []).size() == 3, "l'alleanza vince insieme (%s)" % str(g.over))
	ok(g.over != null and not g.over.get("team", []).has(fo), "FO fuori dalla squadra")
	g.dispose()
	# senza alleanza: chi elimina CP vince
	g = new_game("assedio_pacifico", -1)
	var cp := fac_idx(g, 2)
	g.round = 4
	var killer: int = (cp + 1) % g.players.size()
	var cps: Array = g.territories_of(cp)
	for i in cps.size():
		var t: int = cps[i]
		if i < cps.size() - 1:
			g.terr[t]["owner"] = (cp + 2) % g.players.size()
	var last: int = g.territories_of(cp)[0]
	g.terr[last]["forces"] = D.empty_forces()
	g._capture(last, killer, {"inf": 3, "tank": 0, "art": 0, "aa": 0, "heli": 0, "jet": 0, "drone": 0})
	ok(not g.players[cp]["alive"], "CP eliminata")
	g._check_victory()
	ok(g.over != null and g.over["winner"] == killer and not g.over.has("team"), "vince chi ha eliminato CP (%s)" % str(g.over))
	ok(g.players[(cp + 2) % g.players.size()]["objective"]["type"] == "eliminate", "obiettivi di scenario non convertiti")
	g.dispose()


func test_hold() -> void:
	print("- territori chiave (in round)")
	var g = new_game("corsa_petrolio", 0)
	to_round(g, 3)
	for i in 3:
		g.terr[g.hold_terrs[i]]["owner"] = 0
	g.terr[g.hold_terrs[3]]["owner"] = 1
	g._check_victory()
	ok(g.over == null and g._hold_owner == 0 and g._hold_since == 3, "conto alla rovescia avviato al round 3")
	var st: Dictionary = g.scenario_status(0)
	ok(st.get("hold_owner", -1) == 0 and int(st.get("hold_left", -1)) == 2, "scenario_status mostra i round mancanti (%s)" % str(st))
	to_round(g, 4)
	ok(g.over == null and g.hold_left() == 1, "dopo 1 round non è finita")
	g.terr[g.hold_terrs[2]]["owner"] = 1
	g._check_victory()
	ok(g._hold_owner == -1, "perso un territorio: conto azzerato")
	g.terr[g.hold_terrs[2]]["owner"] = 0
	g._check_victory()
	ok(g._hold_since == 4, "il conto riparte da capo")
	to_round(g, 5)
	ok(g.over == null, "1 round dopo la ripartenza non è finita")
	to_round(g, 6)
	ok(g.over != null and g.over["winner"] == 0 and str(g.over["reason"]).contains("territori chiave"), "vittoria dopo 2 round (%s)" % str(g.over))
	g.dispose()
	g = new_game("corsa_petrolio", 0)
	g.terr[g.hold_terrs[0]]["owner"] = 3
	g.terr[g.hold_terrs[1]]["owner"] = 3
	g.round = g.round_limit
	to_round(g, g.round_limit + 1)
	ok(g.over != null and g.over["winner"] == 3, "allo scadere: più territori chiave (%s)" % str(g.over))
	g.dispose()


func test_serialization() -> void:
	print("- serializzazione")
	for id in ["corsa_petrolio", "blocco_acciaio", "guerra_lampo"]:
		var g = GameS.new({"players": ScS.make_players(id, -1), "seed": 21, "auto_battles": true, "scenario": id, "ai_step_delay": 0.0})
		to_round(g, 8)
		if id == "corsa_petrolio":
			g._hold_owner = 1
			g._hold_since = g.round - 1
		var h = GameS.from_json(g.to_json())
		ok(h != null and h.scenario is Dictionary and h.scenario["id"] == id, id + ": scenario ricaricato")
		if h == null:
			g.dispose()
			continue
		ok(h.truce_rounds == g.truce_rounds and h.victory_share == g.victory_share and h.round_limit == g.round_limit and h.siege_idx == g.siege_idx, id + ": regole")
		ok(h.scenario_targets == g.scenario_targets, id + ": territori obiettivo")
		ok(h.hold_terrs == g.hold_terrs and h._hold_owner == g._hold_owner and h._hold_since == g._hold_since and h.hold_rounds == g.hold_rounds, id + ": stato dei territori chiave")
		ok(h.pacts.size() == g.pacts.size(), id + ": alleanze")
		var a: Dictionary = g.serialize()
		var b: Dictionary = h.serialize()
		a.erase("ais")
		b.erase("ais")
		# (il JSON dei float perde al più l'ultima cifra: confronto con tolleranza)
		ok(same(a, b), id + ": serialize() uguale dopo la ricarica")
		var e0: int = logger.errors
		var r0: int = h.round
		to_round(h, r0 + 3)
		ok(logger.errors == e0 and (h.round > r0 or h.over != null), id + ": la partita ricaricata prosegue")
		g.dispose()
		h.dispose()


# ------------------------------------------------------------------ partite tutte IA
func test_ai_games() -> void:
	print("- partite tutte IA")
	var seeds: Array = []
	for x in _arg("seeds", "1,2").split(","):
		seeds.append(int(x))
	for S in ScS.LIST:
		var id: String = S["id"]
		for sd in seeds:
			var e0: int = logger.errors
			var pl: Array = ScS.make_players(id, -1)
			# fazioni ruotate tra i posti
			for i in pl.size():
				pl[i]["faction"] = (int(pl[i]["faction"]) + sd) % 4 if S.get("opp", 3) == 3 else pl[i]["faction"]
			var g = GameS.new({"players": pl, "seed": sd, "auto_battles": true, "scenario": id, "fog": S.get("fog", false),
				"distribution": S.get("distribution", "regionale"), "ai_step_delay": 0.0})
			to_round(g, g.round_limit + 2)
			var aerr := 0
			for a in g.ais:
				if a != null:
					aerr += int(a.stats.get("errors", 0))
			var w = "-" if g.over == null or int(g.over["winner"]) < 0 else g.players[g.over["winner"]]["fac"]["short"]
			print("    %s seed %d -> %s \"%s\" round %d" % [id, sd, w, "" if g.over == null else g.over["reason"], g.round])
			ok(g.over != null and int(g.over["winner"]) >= 0, id + " seed " + str(sd) + ": conclusa con un vincitore")
			ok(g.round <= g.round_limit + 1, id + ": entro il limite di round")
			ok(logger.errors == e0 and aerr == 0, id + ": nessun errore")
			g.dispose()
