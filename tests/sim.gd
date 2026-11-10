extends SceneTree
## Collaudo headless: partite tutte IA in varie modalità (porting di frontline/tests/sim.js).
## FASE 6 (turni): le IA giocano a turni senza ritardo (ai_step_delay 0); la durata è in round.
## Uso: node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/sim.gd [-- --case=N --seed=S --passive=0|1 --rounds=R --fog=0|1]
##   --bal=conquista --seeds=1-24: bilanciamento con 4 IA (fazioni ruotate), tabella delle vittorie per fazione.
##   senza argomenti: tutti i casi × seed 11,12 + prova "umano passivo".
## Stampa vincitore, motivo, round, scambi/golpe/missili/sabotaggi, NaN ed errori (contati con un Logger).

const CASES := [
	{"n": 4, "mode": "conquista", "dist": "regionale", "d": ["recluta", "veterano", "generale", "veterano"]},
	{"n": 4, "mode": "obiettivo", "dist": "regionale", "d": ["veterano", "veterano", "veterano", "veterano"]},
	{"n": 2, "mode": "conquista", "dist": "casuale", "d": ["generale", "generale"]},
	{"n": 3, "mode": "obiettivo", "dist": "casuale", "d": ["recluta", "generale", "veterano"]},
	{"n": 2, "mode": "conquista", "dist": "regionale", "d": ["veterano", "veterano"]},
]


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


var logger := ErrCount.new()
var started := false
var verbose := false
var fog := false
var wins := {}          # sigla fazione -> vittorie
var games := 0
var finished := 0
var total_err := 0
var minutes: Array = []  # durata (round) delle partite IA finite
var by_cap := 0          # partite decise dal limite di round
var fstat := {}          # sigla -> {elim, elim_round, terr20}
var ai_turn_max := 0.0   # ms del turno IA più lento
var ai_ms_tot := 0.0
var ai_turns_tot := 0


func _initialize() -> void:
	OS.add_logger(logger)


func _process(_delta: float) -> bool:
	if started:
		return true
	started = true
	_run()
	quit(0)
	return true


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/core/game.gd"):
		print("sim: game.gd assente")
		return
	var only_case := int(_arg("case", "-1"))
	var only_seed := int(_arg("seed", "0"))
	var seeds: Array = []
	for x in _arg("seeds", "11,12").split(","):
		if x.contains("-"):   # intervallo, es. 1-24
			var ab := x.split("-")
			for s in range(int(ab[0]), int(ab[1]) + 1):
				seeds.append(s)
		else:
			seeds.append(int(x))
	verbose = _arg("verbose", "0") == "1"
	fog = _arg("fog", "0") == "1"
	print("sim: nebbia di guerra ", "SI" if fog else "no")
	var passive := _arg("passive", "1") == "1"
	var max_min := float(_arg("rounds", "130"))   # round massimi (oltre il limite della partita: protezione)
	var CombatS: Script = load("res://scripts/core/combat.gd")
	if _arg("tactical", "1") == "0" and "tactical" in CombatS:
		CombatS.tactical = false   # risoluzione con la formula (più veloce, per i confronti)
	var GameScript: Script = load(_arg("game", "res://scripts/core/game.gd"))   # --game=: nucleo alternativo (confronti)
	if GameScript == null or not GameScript.can_instantiate():
		print("sim: game.gd non si carica")
		return
	# bilanciamento: --bal=conquista|obiettivo|casuale -> 4 IA veterano, fazioni ruotate tra i posti a ogni seed
	# scenario: --scenario=id (fazioni/giocatori decisi dallo scenario; i posti ruotano come sopra)
	var bal := _arg("bal", "")
	var scen := _arg("scenario", "")
	if bal != "" or scen != "":
		for seed_v in seeds:
			var pls3: Array = []
			var np := int(_arg("players", "4"))
			for i in np:
				pls3.append({"faction": (i + seed_v) % 4, "human": false, "difficulty": _arg("diff", "veterano")})
			var md := "obiettivo" if bal == "obiettivo" else "conquista"
			var opts3 := {"players": pls3, "mode": md, "distribution": "casuale" if bal == "casuale" else "regionale",
				"seed": seed_v, "auto_battles": true, "ask_defense": false, "fog": fog, "ai_step_delay": 0.0}
			if scen != "":
				opts3["scenario"] = scen
			if _arg("ai", "") != "":   # IA alternativa (confronti di bilanciamento)
				opts3["ai_script"] = load(_arg("ai", ""))
			_play(GameScript, opts3, "%s seed %d" % [scen if scen != "" else bal, seed_v], max_min, -1)
		_summary()
		return
	for ci in CASES.size():
		if only_case >= 0 and ci != only_case:
			continue
		for seed_v in seeds:
			if only_seed != 0 and seed_v != only_seed:
				continue
			var c: Dictionary = CASES[ci]
			var pls: Array = []
			for i in c["d"].size():
				pls.append({"faction": (i + ci) % 4, "human": false, "difficulty": c["d"][i]})
			var opts := {"players": pls, "mode": c["mode"], "distribution": c["dist"], "seed": seed_v,
				"auto_battles": true, "ask_defense": false, "fog": fog, "ai_step_delay": 0.0}
			_play(GameScript, opts, "%d %dp %s %s seed %d" % [ci, c["n"], c["mode"], c["dist"], seed_v], max_min, -1)
	if passive and only_case < 0:
		# umano passivo: il giocatore 0 è umano e non fa nulla, battaglie automatiche
		for seed_v in [11, 12]:
			if only_seed != 0 and seed_v != only_seed:
				continue
			var pls2: Array = [{"faction": 0, "human": true, "difficulty": "veterano"},
				{"faction": 1, "human": false, "difficulty": "veterano"},
				{"faction": 2, "human": false, "difficulty": "veterano"},
				{"faction": 3, "human": false, "difficulty": "veterano"}]
			var opts2 := {"players": pls2, "mode": "conquista", "distribution": "regionale", "seed": seed_v,
				"auto_battles": true, "ask_defense": false, "fog": fog, "ai_step_delay": 0.0}
			_play(GameScript, opts2, "P umano passivo 4p conquista regionale seed %d" % seed_v, max_min, 0)
	_summary()


func _summary() -> void:
	print("sim: partite tutte IA %d, finite con vincitore %d, vittorie per fazione %s, errori totali %d" % [games, finished, str(wins), total_err])
	if minutes.size() > 0:
		var mn: float = minutes.min()
		var mx: float = minutes.max()
		var sum := 0.0
		for m in minutes:
			sum += m
		var srt := minutes.duplicate()
		srt.sort()
		print("sim: durata media %.1f round (min %d, mediana %d, max %d), decise dal limite di round %d, turno IA medio %.1f ms (più lento %.1f ms)" % [
			sum / minutes.size(), int(mn), int(srt[srt.size() / 2]), int(mx), by_cap, ai_ms_tot / maxf(1.0, ai_turns_tot), ai_turn_max])
	var fp: PackedStringArray = []
	for sh in fstat:
		var f: Dictionary = fstat[sh]
		fp.append("%s eliminata %d volte (round medio %.0f), territori al round 20 %.1f" % [sh, f["elim"], f["er"] / maxf(1.0, f["elim"]), f["t20"] / maxf(1.0, f["n"])])
	print("sim: ", " | ".join(fp))
	var parts: PackedStringArray = []
	for sh in ["AAN", "FO", "CP", "UL"]:
		parts.append("%s %d%%" % [sh, roundi(100.0 * wins.get(sh, 0) / maxi(1, games))])
	print("sim: quota vittorie ", " | ".join(parts))


func _play(GameScript: Script, opts: Dictionary, label: String, max_min: float, watch: int) -> void:
	var err0 := logger.errors
	var t_real := Time.get_ticks_msec()
	var g = GameScript.new(opts)
	var sig := {}
	var elim := {}
	var on_event := func(n: String, data: Dictionary) -> void:
		sig[n] = sig.get(n, 0) + 1
		if n == "eliminated":
			elim[int(data.get("player", -1))] = g.round
			if verbose:
				var by := int(data.get("by", -1))
				print("    %s eliminata da %s al round %d" % [g.players[int(data["player"])]["fac"]["short"], g.players[by]["fac"]["short"] if by >= 0 else "-", g.round])
	g.event.connect(on_event)
	var bad := 0
	var guard := 0
	var t20 := {}
	while g.over == null and g.round <= max_min:
		if g.round == 20 and t20.is_empty():
			for P in g.players:
				t20[P["fac"]["short"]] = g.territories_of(P["idx"]).size()
		if g.is_human_turn():
			g.end_turn()   # umano passivo
		g.update(0.1)
		if g.pending_battle != null:
			g.resolve_pending_auto()
			guard += 1
			if guard > 100000:
				print("  pending_battle bloccata")
				break
		for p in g.players:
			for k in p["res"]:
				var v = p["res"][k]
				if is_nan(v) or is_inf(v):
					bad += 1
		if watch >= 0 and elim.has(watch):
			break
	var trades := 0
	var ai_ms := 0.0
	var ai_max := 0.0
	var ai_err := 0
	for a in g.ais:
		if a != null:
			trades += int(a.stats.get("trades", 0))
			ai_ms += float(a.stats["ms"])
			ai_max = maxf(ai_max, float(a.stats["maxMs"]))
			ai_err += int(a.stats["errors"])
			ai_ms_tot += float(a.stats["ms"])
			ai_turns_tot += int(a.stats.get("turns", 0))
	ai_turn_max = maxf(ai_turn_max, ai_max)
	var res: String
	if watch >= 0:
		if elim.has(watch):
			res = "umano eliminato al round %d" % int(elim[watch])
		elif g.over != null:
			res = "fine prima dell'eliminazione: %s \"%s\" round %d" % [g.players[g.over["winner"]]["fac"]["short"], g.over["reason"], g.round]
		else:
			res = "umano vivo al round %d (terr %d)" % [g.round, g.territories_of(watch).size()]
	elif g.over != null:
		res = "%s \"%s\" round %d" % [g.players[g.over["winner"]]["fac"]["short"] if int(g.over["winner"]) >= 0 else "-", g.over["reason"], g.round]
	else:
		res = "nessun vincitore in %d round" % int(max_min)
	total_err += logger.errors - err0
	if watch < 0:
		games += 1
		if g.over != null and int(g.over["winner"]) >= 0:
			finished += 1
			var sh: String = g.players[g.over["winner"]]["fac"]["short"]
			wins[sh] = wins.get(sh, 0) + 1
			minutes.append(float(mini(g.round, g.round_limit)))
			if str(g.over["reason"]).begins_with("Limite"):
				by_cap += 1
	if watch < 0:
		for P in g.players:
			var sh: String = P["fac"]["short"]
			if not fstat.has(sh):
				fstat[sh] = {"elim": 0, "er": 0.0, "t20": 0.0, "n": 0}
			if elim.has(P["idx"]):
				fstat[sh]["elim"] += 1
				fstat[sh]["er"] += float(elim[P["idx"]])
			fstat[sh]["t20"] += float(t20.get(sh, g.territories_of(P["idx"]).size()))
			fstat[sh]["n"] += 1
	var vets := [0, 0, 0, 0]
	for tr in g.terr:
		vets[clampi(int(tr.get("vet", 0)), 0, 3)] += 1
	print("%s -> %s | NaN %d | errori %d (ia %d) | scambi %d | golpe %d missili %d sabot %d | stelle %d (terr. vet1/2/3 %d/%d/%d) offerte patto %d | IA %.0f ms (max %.1f) | reale %.1f s" % [
		label, res, bad, logger.errors - err0, ai_err, trades, sig.get("golpe", 0), sig.get("missile", 0), sig.get("sabotage", 0),
		sig.get("veteran", 0), vets[1], vets[2], vets[3], sig.get("pact_offer", 0),
		ai_ms, ai_max, (Time.get_ticks_msec() - t_real) / 1000.0])
	g.event.disconnect(on_event)
	if verbose:
		for p in g.players:
			var ob = p["objective"]
			if g.ais[p["idx"]] != null and "prof" in g.ais[p["idx"]]:
				print("    prof ", g.ais[p["idx"]].prof)
			print("    %s %s terr %d tech %d stats %s obiettivo %s" % [p["fac"]["short"], p["difficulty"], g.territories_of(p["idx"]).size(),
				p["tech"], "-" if g.ais[p["idx"]] == null else str(g.ais[p["idx"]].stats), "-" if ob == null else ob["text"]])
	if g.has_method("dispose"):
		g.dispose()
	if logger.errors > err0:
		for e in logger.first:
			print("    ", e)
