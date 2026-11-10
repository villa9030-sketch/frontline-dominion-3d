extends SceneTree
## Collaudo headless di salvataggi, cronologia, riepilogo, eventi di contesto e casi limite del nucleo (FASE 6: a turni).
## Uso: node tools/godot_run.js --timeout=600 -- --headless --path . --script tests/test_save.gd

var D            # autoload Data
var GameS: Script
var CombatS: Script
var fails := 0
var checks := 0


class ErrCount extends Logger:
	var errors := 0
	var first: Array = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors += 1
		if first.size() < 8:
			first.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		mutex.unlock()
	func _log_message(_m: String, _e: bool) -> void:
		pass


var logger := ErrCount.new()


func _initialize() -> void:
	OS.add_logger(logger)
	D = root.get_node("Data")
	GameS = load("res://scripts/core/game.gd")
	CombatS = load("res://scripts/core/combat.gd")
	CombatS.set("tactical", false)   # formula: test veloce e deterministico
	test_roundtrip_ai_match()
	test_roundtrip_plain_json()
	test_mid_turn_save()
	test_mid_ai_turn_save()
	test_pending_save()
	test_history_and_summary()
	test_eliminated_with_pending()
	test_hq_captured_in_manual()
	test_incoherent_finish()
	test_card_targets()
	test_two_player_random()
	test_headlines()
	test_bad_saves()
	CombatS.set("tactical", true)
	ok(logger.errors == 0, "nessun errore del motore (%d)" % logger.errors)
	for e in logger.first:
		print("    ", e)
	print("\n== test_save: ", checks, " verifiche, ", fails, " fallite ==")
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


## stato confrontabile: chiavi ordinate, senza i tempi di calcolo delle IA
func canon(g) -> String:
	var s: Dictionary = g.serialize()
	for a in s["ais"]:
		if a is Dictionary:
			a["stats"].erase("ms")
			a["stats"].erase("maxMs")
	return JSON.stringify(s, "", true, true)


func strip(s: Dictionary) -> Dictionary:
	for a in s["ais"]:
		if a is Dictionary:
			a["stats"].erase("ms")
			a["stats"].erase("maxMs")
	return s


## "" se uguali (float con tolleranza relativa 1e-9, int e float distinti), altrimenti il primo percorso diverso
func deep_diff(a, b, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: tipo %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		if a.size() != b.size():
			return "%s: chiavi %s vs %s" % [path, a.keys(), b.keys()]
		for k in a:
			if not b.has(k):
				return "%s: manca %s" % [path, k]
			var r := deep_diff(a[k], b[k], path + "." + str(k))
			if r != "":
				return r
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: lunghezza %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var r := deep_diff(a[i], b[i], path + "[" + str(i) + "]")
			if r != "":
				return r
		return ""
	if a is float:
		return "" if absf(a - b) <= 1e-9 * maxf(1.0, absf(a)) else "%s: %s vs %s" % [path, a, b]
	return "" if a == b else "%s: %s vs %s" % [path, a, b]


func first_diff(a: String, b: String) -> String:
	var n := mini(a.length(), b.length())
	for i in n:
		if a[i] != b[i]:
			return "@%d: ...%s... vs ...%s..." % [i, a.substr(maxi(0, i - 80), 160), b.substr(maxi(0, i - 80), 160)]
	return "lunghezze %d vs %d" % [a.length(), b.length()]




func ai_game(n: int, mode: String, dist: String, seed_v: int):
	var pl := []
	for i in n:
		pl.append({"faction": i % 4, "human": false, "difficulty": ["veterano", "generale", "recluta", "veterano"][i]})
	return GameS.new({"players": pl, "mode": mode, "distribution": dist, "seed": seed_v, "auto_battles": true, "ai_step_delay": 0.0})


## gioca rounds round (IA istantanee; l'umano passa il turno; battaglie risolte in automatico)
func run(g, rounds: int) -> void:
	var stop: int = g.round + rounds
	var guard := 0
	while g.over == null and g.round < stop and guard < 100000:
		guard += 1
		if g.pending_battle != null:
			g.resolve_pending_auto()
		elif g.is_human_turn():
			g.end_turn()
		else:
			g.update(0.1)


# ---------------------------------------------------------------- salvataggio a metà partita
func test_roundtrip_ai_match() -> void:
	print("- salvataggio/ricarica a metà partita (4 IA, obiettivo)")
	var g = ai_game(4, "obiettivo", "regionale", 31)
	run(g, 12)
	ok(g.over == null, "partita ancora in corso al round 13")
	var txt: String = g.to_json()
	var g2 = GameS.from_json(txt)
	ok(g2 != null, "from_json")
	if g2 == null:
		return
	var diff := deep_diff(strip(g.serialize()), strip(g2.serialize()), "")
	ok(diff == "", "stato ricaricato da JSON coincide " + diff)
	ok(g2.ais[1] != null and g2.ais[1].seen.size() == g.ais[1].seen.size(), "memoria IA ricaricata")
	ok(g2.players[0]["color"] is Color and g2.players[0]["fac"] is Dictionary, "colore/fazione ricostruiti")
	ok(g2.round == g.round and g2.current == g.current and g2.phase == g.phase, "stato dei turni ricaricato")
	var g3 = GameS.deserialize(g.serialize())
	var a := canon(g)
	var b := canon(g3)
	ok(a == b, "stato ricaricato identico " + ("" if a == b else first_diff(a, b)))
	run(g, 5)
	run(g3, 5)
	a = canon(g)
	b = canon(g3)
	ok(a == b, "dopo 5 round la partita ricaricata è identica all'originale " + ("" if a == b else first_diff(a, b)))
	g3.dispose()
	var e0 := logger.errors
	run(g2, 200)
	ok(g2.over != null and int(g2.over["winner"]) >= 0, "la partita ricaricata arriva a un vincitore")
	ok(logger.errors == e0, "nessun errore dopo la ricarica")
	print("  vincitore %s al round %d" % ["-" if g2.over == null else g2.players[g2.over["winner"]]["fac"]["short"], g2.round])
	g.dispose()
	g2.dispose()


func test_roundtrip_plain_json() -> void:
	print("- round-trip con JSON.stringify/parse_string standard")
	var g = ai_game(3, "conquista", "casuale", 32)
	run(g, 8)
	var d = JSON.parse_string(JSON.stringify(g.serialize()))
	ok(d is Dictionary, "JSON valido")
	var g2 = GameS.deserialize(d)
	ok(g2 != null, "deserialize da JSON standard")
	if g2 == null:
		return
	ok(g2.round == g.round and g2.players.size() == 3 and typeof(g2.round) == TYPE_INT, "round/giocatori")
	var same := true
	for i in g.terr.size():
		if g.terr[i]["owner"] != g2.terr[i]["owner"] or str(g.terr[i]["forces"]) != str(g2.terr[i]["forces"]) or str(g.terr[i]["fort"]) != str(g2.terr[i]["fort"]):
			same = false
	ok(same, "territori (forze, fortificazioni) identici")
	ok(typeof(g2.terr[0]["owner"]) == TYPE_INT and typeof(g2.terr[0]["forces"]["inf"]) == TYPE_INT and typeof(g2.terr[0]["fort"]["trench"]) == TYPE_INT, "interi restano interi")
	ok(typeof(g2.players[0]["tech"]) == TYPE_INT and typeof(g2.players[0]["hq"]) == TYPE_INT and typeof(g2.terr[0]["unrest"]) == TYPE_INT, "tech/hq/occupazione interi")
	ok(g2.deck.size() + g2.discard.size() + _cards_in_hand(g2) == D.TERRITORIES.size() + 2, "mazzo completo")
	var e0 := logger.errors
	run(g2, 20)
	ok(logger.errors == e0, "prosegue senza errori")
	g.dispose()
	g2.dispose()


func _cards_in_hand(g) -> int:
	var n := 0
	for P in g.players:
		n += P["cards"].size()
	return n


## Salvataggio a metà del turno dell'umano: fase, attacco/spostamento usati, code e pool
func test_mid_turn_save() -> void:
	print("- salvataggio a metà turno (umano)")
	var g = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}, {"faction": 3, "human": false}], "seed": 33, "ai_step_delay": 0.0, "auto_battles": true})
	var hq: int = g.players[0]["hq"]
	g.recruit(0, hq, "tank", 1)
	g.build(0, hq, "impianto")
	g.fortify(0, hq, "trench")
	g.place_pool(0, hq, {"inf": 1})
	var nb := -1
	var from := -1
	for t in g.territories_of(0):
		for j in D.TERRITORIES[t]["adj"]:
			if g.terr[j]["owner"] == -1 and nb < 0:
				nb = j
				from = t
	g.terr[from]["forces"] = F({"inf": 30, "tank": 5})
	g.terr[nb]["forces"] = F({"inf": 1})
	ok(g.attack(from, nb, F({"inf": 20, "tank": 5}))["ok"], "attacco prima del salvataggio")
	var g2 = GameS.from_json(g.to_json())
	ok(g2 != null and g2.phase == "attacco" and g2.attack_used and not g2.move_used and g2.current == 0, "fase e attacco usato ricaricati")
	ok(g2.terr[hq]["queue"].size() == 1 and g2.terr[hq]["queue"][0]["total"] == 2 and g2.terr[hq]["building"]["key"] == "impianto", "code ricaricate")
	ok(g2.terr[hq]["fort"]["trench"] == 1 and g2.players[0]["pool"]["inf"] == g.players[0]["pool"]["inf"], "fortificazioni e pool")
	ok(g2.terr[nb]["regroup"] == 1 and g2.terr[nb]["unrest"] == 2, "riorganizzazione/occupazione")
	ok(not g2.attack(from, nb, F({"inf": 1}))["ok"], "dopo la ricarica: niente secondo attacco")
	ok(g2.is_human_turn() and g2.end_turn()["ok"] and g2.current == 1, "il turno prosegue")
	g.dispose()
	g2.dispose()


## Salvataggio a metà del turno di un'IA (ritmo con ritardo): la partita ricaricata prosegue identica
func test_mid_ai_turn_save() -> void:
	print("- salvataggio a metà turno IA")
	var g = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}, {"faction": 2, "human": false}], "seed": 34,
		"ai_step_delay": 0.5, "auto_battles": true})
	for i in 4:   # alcuni round per avere un'economia avviata
		g.end_turn()
		g.skip_ai_turn()
		g.skip_ai_turn()
	ok(g.is_human_turn(), "di nuovo l'umano")
	g.end_turn()
	g.update(0.6)
	ok(g.current == 1 and g.ais[1].stage > 0 and g.ais[1].stage < 5, "IA a metà turno (fase %d)" % g.ais[1].stage)
	var g2 = GameS.from_json(g.to_json())
	ok(g2 != null and g2.current == 1 and g2.ais[1].stage == g.ais[1].stage, "fase del turno IA ricaricata")
	var df := deep_diff(strip(g.serialize()), strip(g2.serialize()), "")
	ok(df == "", "stato a metà turno IA identico (a meno dell'ultima cifra dei float JSON) " + df)
	for x in [g, g2]:
		for i in 12:
			x.update(0.5)
	ok(g.current == 0 and g2.current == 0, "turni IA completati")
	df = deep_diff(strip(g.serialize()), strip(g2.serialize()), "")
	ok(df == "", "dopo i turni IA lo stato coincide " + df)
	g.dispose()
	g2.dispose()


# ---------------------------------------------------------------- battaglia in attesa
func _human_game(seed_v: int, n: int = 2):
	var pl := [{"faction": 0, "human": true, "difficulty": "veterano"}]
	for i in range(1, n):
		pl.append({"faction": i, "human": false, "difficulty": "veterano"})
	var g = GameS.new({"players": pl, "seed": seed_v, "ai_step_delay": 0.0})
	for i in range(1, n):
		g.ais[i] = null   # stato controllato
	g.round = 3           # dopo la tregua
	return g


## crea una battaglia in attesa del giocatore 0 contro un territorio di target_owner
func _pending(g, target_owner: int, att: Dictionary, def: Dictionary, to_hq: bool = false) -> Dictionary:
	var from := -1
	var to := -1
	for t in g.territories_of(0):
		for j in D.TERRITORIES[t]["adj"]:
			if g.terr[j]["owner"] == target_owner and (not to_hq or g.players[target_owner]["hq"] == j):
				from = t
				to = j
				break
		if from >= 0:
			break
	if from < 0:
		to = g.players[target_owner]["hq"] if to_hq and target_owner >= 0 else g.territories_of(target_owner)[0]
		from = D.TERRITORIES[to]["adj"][0]
		g.terr[from]["owner"] = 0
	g.current = 0
	g.phase = "rifornimento"
	g.attack_used = false
	g.move_used = false
	g.terr[from]["forces"] = F(att)
	g.terr[from]["forces"]["inf"] += 1
	g.terr[from]["regroup"] = 0
	g.terr[to]["forces"] = F(def)
	g.players[0]["res"]["oil"] = 1000.0
	var r: Dictionary = g.attack(from, to, F(att))
	ok(r["ok"] and r["pending"], "attacco: " + r["reason"])
	return {"from": from, "to": to}


func test_pending_save() -> void:
	print("- salvataggio con battaglia in attesa / manuale")
	var g = _human_game(41)
	var s := _pending(g, -1, {"inf": 12, "tank": 4}, {"inf": 5})
	ok(g.pending_battle != null, "battaglia in attesa")
	var g2 = GameS.from_json(g.to_json())
	ok(g2 != null and g2.pending_battle != null and g2.pending_battle["terr"] == s["to"], "attesa salvata")
	ok(g2.pending_battle["forces"]["inf"] == 12 and g2.pending_battle["human_side"] == "att", "forze e lato umano salvati")
	var r: Dictionary = g2.resolve_pending_auto()
	ok(r["ok"] and g2.pending_battle == null, "risolta dopo la ricarica")
	g.start_manual_battle()
	var g3 = GameS.from_json(g.to_json())
	ok(g3.pending_battle != null and not g3.pending_battle.has("manual"), "manuale -> torna in attesa")
	var setup: Dictionary = g3.start_manual_battle()
	ok(setup.has("att") and setup["att"]["color"] is Color, "setup manuale dopo la ricarica")
	r = g3.finish_manual_battle({"att": {"inf": 10, "tank": 4}, "def": {}, "winner": "att"})
	ok(r["ok"] and g3.terr[s["to"]]["owner"] == 0, "battaglia manuale conclusa dopo la ricarica")
	# difesa umana in attesa durante il turno IA
	var gd = GameS.new({"players": [{"faction": 0, "human": true}, {"faction": 1, "human": false}], "seed": 42, "ai_step_delay": 0.0})
	gd.round = 3
	gd.end_turn()
	var tgt := -1
	var src := -1
	for t in gd.territories_of(1):
		for j in D.TERRITORIES[t]["adj"]:
			if gd.terr[j]["owner"] == 0 and tgt < 0:
				tgt = j
				src = t
	if tgt < 0:
		src = gd.territories_of(1)[0]
		tgt = D.TERRITORIES[src]["adj"][0]
		gd.terr[tgt]["owner"] = 0
	gd.terr[src]["forces"] = F({"inf": 20})
	gd.terr[tgt]["forces"] = F({"inf": 5})
	ok(gd.attack(src, tgt, F({"inf": 15}))["pending"], "difesa umana in attesa")
	var gd2 = GameS.from_json(gd.to_json())
	ok(gd2.pending_battle != null and gd2.pending_battle["human_side"] == "def" and gd2.current == 1, "difesa in attesa salvata (turno IA)")
	gd2.resolve_pending_auto()
	gd2.update(0.1)
	ok(gd2.pending_battle == null and gd2.current == 0, "dopo la difesa l'IA finisce il turno")
	for x in [g, g2, g3, gd, gd2]:
		x.dispose()


# ---------------------------------------------------------------- cronologia e riepilogo
func test_history_and_summary() -> void:
	print("- cronologia e riepilogo finale")
	var g = ai_game(4, "conquista", "regionale", 11)
	var heads := {"n": 0, "txt": []}
	g.event.connect(func(n, d):
		if n == "headline":
			heads["n"] += 1
			if heads["txt"].size() < 6:
				heads["txt"].append(d["text"]))
	run(g, 130)
	ok(g.over != null, "partita finita")
	var h: Array = g.history
	ok(h.size() == g.round or h.size() == g.round - 1 or h.size() == g.round + 1, "un'istantanea per round (%d per %d round)" % [h.size(), g.round])
	var spaced := true
	for i in range(1, h.size()):
		if int(h[i]["round"]) != int(h[i - 1]["round"]) + 1:
			spaced = false
	ok(spaced, "round consecutivi")
	var last: Dictionary = h[h.size() - 1]
	ok(last["terr"].size() == 4 and last["power"].size() == 4 and last["units"].size() == 4 and last["income"].size() == 4, "campi per giocatore")
	ok(last["terr"][g.over["winner"]] == g.territories_of(g.over["winner"]).size(), "ultima istantanea = fine partita")
	var ss: Dictionary = g.stats_summary()
	ok(ss["winner"] == g.over["winner"] and ss["players"].size() == 4 and ss["round"] == g.round, "riepilogo: vincitore e round")
	var w: Dictionary = ss["players"][g.over["winner"]]
	ok(w["max_territories"] >= w["territories"] and w["battles_won"] > 0 and w["buildings"] > 0 and w["research"] > 0, "riepilogo: statistiche del vincitore")
	ok(w["color"] is String and JSON.stringify(ss) != "", "riepilogo serializzabile")
	for p in ss["players"]:
		if not p["alive"]:
			ok(p["eliminated_at"] > 0, "round di eliminazione")
	var cards := 0
	for p in ss["players"]:
		cards += p["cards_played"]
	ok(cards > 0, "carte giocate contate")
	ok(heads["n"] > 0, "eventi di contesto (headline) emessi: %d" % heads["n"])
	print("  %d istantanee, %d headline, es.: %s" % [h.size(), heads["n"], heads["txt"]])
	g.dispose()


# ---------------------------------------------------------------- casi limite
func test_eliminated_with_pending() -> void:
	print("- attaccante eliminato con battaglia in attesa")
	var g = _human_game(51)
	_pending(g, 1, {"inf": 10}, {"inf": 6})
	ok(g.pending_battle != null, "attesa")
	for t in g.territories_of(0):
		g._capture(t, 1, F({"inf": 1}))
	ok(not g.players[0]["alive"], "umano eliminato")
	ok(g.pending_battle == null, "battaglia in attesa annullata")
	ok(not g.finish_manual_battle({"att": {"inf": 3}, "winner": "att"})["ok"], "finish rifiutato")
	ok(not g.resolve_pending_auto()["ok"], "resolve rifiutato")
	g._check_victory()
	ok(g.over != null and g.over["winner"] == 1, "vittoria dell'altro")
	g.dispose()
	var g2 = _human_game(52)
	_pending(g2, 1, {"inf": 10}, {"inf": 6})
	g2.start_manual_battle()
	g2._eliminate(0, 1)
	ok(g2.finish_manual_battle({"att": {"inf": 3}, "winner": "att"})["ok"] and g2.pending_battle == null, "battaglia manuale chiusa senza effetti")
	g2.dispose()


func test_hq_captured_in_manual() -> void:
	print("- QG catturato in una battaglia manuale")
	var g = _human_game(61, 3)
	var lost := {"n": 0}
	g.event.connect(func(n, _d): if n == "hqLost": lost["n"] += 1)
	var hq1: int = g.players[1]["hq"]
	var s := _pending(g, 1, {"inf": 20, "tank": 6}, {"inf": 4}, true)
	ok(s["to"] == hq1 and g.pending_battle != null, "attesa sul QG nemico")
	g.start_manual_battle()
	var money0: float = g.players[1]["res"]["money"]
	g.finish_manual_battle({"att": {"inf": 15, "tank": 6}, "def": {}, "winner": "att"})
	ok(g.terr[hq1]["owner"] == 0 and lost["n"] == 1, "QG catturato + hqLost")
	ok(g.players[1]["hq"] != hq1 and (g.players[1]["hq"] < 0 or g.terr[g.players[1]["hq"]]["owner"] == 1), "nuovo QG valido")
	ok(g.players[1]["res"]["money"] <= money0, "denaro sottratto")
	var g2 = _human_game(62)
	for t in g2.territories_of(1):
		if t != g2.players[1]["hq"]:
			g2.terr[t]["owner"] = -1
	var s2 := _pending(g2, 1, {"inf": 20, "tank": 6}, {"inf": 4}, true)
	ok(g2.pending_battle != null, "attesa sull'ultimo territorio")
	g2.start_manual_battle()
	g2.finish_manual_battle({"att": {"inf": 15}, "def": {}, "winner": "att"})
	ok(not g2.players[1]["alive"] and g2.players[1]["hq"] == -1, "difensore eliminato")
	ok(g2.over != null and g2.over["winner"] == 0, "vittoria dopo la battaglia manuale")
	ok(g2.terr[s2["to"]]["owner"] == 0, "territorio conquistato")
	g.dispose()
	g2.dispose()


func test_incoherent_finish() -> void:
	print("- finish_manual_battle con forze incoerenti")
	var g = _human_game(71)
	var s := _pending(g, -1, {"inf": 8, "tank": 2}, {"inf": 5})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": NAN, "tank": -4, "art": "x", "jet": INF}, "def": [1, 2], "winner": "att"})
	ok(g.terr[s["to"]]["owner"] == -1, "vittoria con zero superstiti -> vince il difensore")
	ok(g.terr[s["to"]]["forces"]["inf"] == 0, "difensore senza forze valide = 0")
	var bad := false
	for k in g.terr[s["to"]]["forces"]:
		var v = g.terr[s["to"]]["forces"][k]
		if typeof(v) != TYPE_INT or v < 0:
			bad = true
	ok(not bad, "forze sanificate")
	s = _pending(g, -1, {"inf": 8, "tank": 2}, {"inf": 5})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": "6", "tank": 9.7}, "def": {"inf": 99}, "winner": "att"})
	ok(g.terr[s["to"]]["owner"] == 0 and g.terr[s["to"]]["forces"]["inf"] == 6 and g.terr[s["to"]]["forces"]["tank"] == 2, "superstiti numerici limitati")
	s = _pending(g, -1, {"inf": 8}, {"inf": 5})
	g.start_manual_battle()
	ok(g.finish_manual_battle("boh")["ok"], "risultato non valido accettato come sconfitta")
	ok(g.terr[s["to"]]["owner"] == -1 and g.pending_battle == null, "sconfitta: territorio resta neutrale")
	s = _pending(g, -1, {"inf": 8}, {"inf": 5})
	g.terr[s["to"]]["owner"] = 0
	var r: Dictionary = g.resolve_pending_auto()
	ok(r["ok"] and g.terr[s["to"]]["forces"]["inf"] == 13, "battaglia inutile: forze unite (%s)" % str(g.terr[s["to"]]["forces"]))
	s = _pending(g, -1, {"inf": 8}, {"inf": 5})
	g.terr[s["to"]]["forces"] = F({})
	g.start_manual_battle()
	g.finish_manual_battle({"att": {"inf": 8}, "def": {}, "winner": "att"})
	ok(g.terr[s["to"]]["owner"] == 0 and g.terr[s["to"]]["forces"]["inf"] == 8, "conquista senza difensori")
	g.dispose()


func test_card_targets() -> void:
	print("- carte con bersaglio non valido")
	var g = _human_game(81)
	var P: Dictionary = g.players[0]
	var mine: int = g.territories_of(0)[0]
	var enemy: int = g.territories_of(1)[0]
	var hq1: int = g.players[1]["hq"]
	var give := func():
		P["cards"] = [{"type": "inf"}, {"type": "inf"}, {"type": "inf"}]
	var cases := [["missile", mine, "proprio"], ["missile", -1, "-1"], ["missile", 999, "fuori"], ["missile", "abc", "stringa"],
		["missile", null, "null"], ["sabotaggio", 42, "42"], ["golpe", hq1, "QG"], ["nessuna", enemy, "op sconosciuta"]]
	for c in cases:
		give.call()
		var r: Dictionary = g.play_cards(0, [0, 1, 2], c[0], c[1])
		ok(not r["ok"] and P["cards"].size() == 3, "rifiutata (%s %s): %s" % [c[0], c[2], r["reason"]])
	give.call()
	g.terr[enemy]["forces"] = F({"inf": D.GOLPE_MAX + 1})
	if enemy != hq1:
		ok(not g.play_cards(0, [0, 1, 2], "golpe", enemy)["ok"], "golpe con troppe truppe")
	give.call()
	ok(not g.play_cards(0, [0, 0, 1], "rinforzi")["ok"], "indici ripetuti")
	ok(not g.play_cards(0, [0, 1, 7], "rinforzi")["ok"], "indice fuori mano")
	ok(not g.play_cards(0, "012", "rinforzi")["ok"], "indici non array")
	ok(not g.play_cards(5, [0, 1, 2], "rinforzi")["ok"], "giocatore inesistente")
	give.call()
	g.terr[enemy]["forces"] = F({"inf": 4})
	var r2: Dictionary = g.play_cards(0, [0, 1, 2], "missile", float(enemy))
	ok(r2["ok"] and P["cards"].is_empty(), "missile con indice float")
	ok(P["stats"]["cardsPlayed"] == 1, "carte giocate contate")
	g.dispose()


func test_two_player_random() -> void:
	print("- partita a 2 con distribuzione casuale")
	for seed_v in [91, 92, 93]:
		for mode in ["conquista", "obiettivo"]:
			var g = ai_game(2, mode, "casuale", seed_v)
			var c := [0, 0, 0]
			for tr in g.terr:
				c[tr["owner"] + 1] += 1
			ok(c[1] == 14 and c[2] == 14 and c[0] == 14, "14/14/14 territori (%s)" % str(c))
			for P in g.players:
				ok(P["hq"] >= 0 and g.terr[P["hq"]]["owner"] == P["idx"], "QG proprio")
				if mode == "obiettivo":
					var ob = P["objective"]
					ok(ob != null and (ob["type"] != "eliminate" or ob["target"] == 1 - P["idx"]), "obiettivo valido")
			var e0 := logger.errors
			run(g, 130)
			ok(g.over != null and logger.errors == e0, "2p casuale %s seed %d: fine senza errori (round %d)" % [mode, seed_v, g.round])
			g.dispose()


func test_headlines() -> void:
	print("- eventi di contesto")
	var g = _human_game(101, 3)
	var got: Array = []
	g.event.connect(func(n, d): if n == "headline": got.append(d["text"]))
	for t in D.CONT_TERR["AF"]:
		if g.terr[t]["owner"] != 2:
			g._capture(t, 2, F({"inf": 3}))
	g._after_action()
	var found := false
	for x in got:
		if "controlla ora l'Africa" in x:
			found = true
	ok(found, "\"controlla ora l'Africa\" " + str(got))
	got.clear()
	for i in 4:
		g._battle_times.append([g.round, "EU"])
	g._ctx_dirty = true
	g._after_action()
	ok(got.size() == 1 and "Fronte caldo in Europa" in got[0], "fronte caldo " + str(got))
	got.clear()
	g._battle_times.append([g.round, "EU"])
	g._ctx_dirty = true
	g._after_action()
	ok(got.is_empty(), "niente ripetizioni ravvicinate")
	g._capture(D.CONT_TERR["AF"][0], 0, F({"inf": 3}))
	g._after_action()
	var lost := false
	for x in got:
		if "strappa" in x or "perde il controllo" in x:
			lost = true
	ok(lost, "perdita del continente " + str(got))
	got.clear()
	var g2 = GameS.from_json(g.to_json())
	var got2: Array = []
	g2.event.connect(func(n, d): if n == "headline": got2.append(d["text"]))
	g2._after_action()
	ok(got2.is_empty(), "nessun annuncio ripetuto dopo la ricarica " + str(got2))
	g.dispose()
	g2.dispose()


func test_bad_saves() -> void:
	print("- salvataggi non validi e versioni vecchie")
	ok(GameS.deserialize(null) == null, "null")
	ok(GameS.deserialize({}) == null, "vuoto")
	ok(GameS.deserialize({"players": [], "terr": [], "opts": {}}) == null, "senza giocatori")
	ok(GameS.from_json("{rotto") == null and GameS.last_load_error != "", "JSON rotto")
	var g = ai_game(2, "conquista", "regionale", 5)
	var d: Dictionary = g.serialize()
	ok(int(d["version"]) == int(GameS.SAVE_VERSION) and int(d["version"]) >= 3 and d.has("turn"), "SAVE_VERSION %d con stato dei turni" % int(d["version"]))
	# migrazione: un salvataggio v2 (senza worn/decoy/silence/fog_mode) si carica, con nebbia totale dal vecchio bool
	var d2: Dictionary = JSON.parse_string(JSON.stringify(d))
	d2["version"] = 2
	d2["opts"].erase("fog_mode")
	d2["opts"]["fog"] = true
	d2.erase("intel")
	for tr in d2["terr"]:
		tr.erase("worn"); tr.erase("decoy"); tr.erase("silence")
	var gm = GameS.deserialize(d2)
	ok(gm != null and gm.fog_mode == "full" and gm.fog and int(gm.terr[0].get("worn", -1)) == 0 and gm.intel.is_empty(), "salvataggio v2 migrato (nebbia totale, logoramento 0)")
	if gm != null:
		gm.dispose()
	var old: Dictionary = g.serialize()
	old["version"] = 1
	old.erase("turn")
	ok(GameS.deserialize(old) == null and "versione precedente" in GameS.last_load_error, "salvataggio in tempo reale rifiutato: " + GameS.last_load_error)
	d["terr"].pop_back()
	ok(GameS.deserialize(d) == null, "territori mancanti")
	d = g.serialize()
	d["players"][0]["res"]["money"] = "molto"
	d["pending_battle"] = {"terr": -5}
	d["turn"]["phase"] = "boh"
	d["turn"]["current"] = 99
	d["terr"][3]["fort"] = {"trench": 9, "mines": "x"}
	var g2 = GameS.deserialize(d)
	ok(g2 != null and g2.pending_battle == null and g2.players[0]["res"]["money"] == 0.0, "campi errati ripuliti")
	ok(g2.phase == "rifornimento" and g2.current < g2.players.size() and g2.terr[3]["fort"] == {"trench": 3, "mines": 0, "bunker": 0}, "turno e fortificazioni ripuliti")
	ok(GameS.last_load_error == "", "nessun errore di caricamento")
	var e0 := logger.errors
	run(g2, 3)
	ok(logger.errors == e0, "prosegue senza errori")
	g.dispose()
	g2.dispose()
