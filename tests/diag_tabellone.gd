extends SceneTree
## Diagnosi del ritmo del tabellone (notte 3): partite tutte IA, misurate dal punto di vista del posto 0
## (sostituto del giocatore). Non è un test: stampa numeri per docs/notte3_tabellone.md.
## Uso: node tools/godot_run.js --timeout=900 -- --headless --path . --script tests/diag_tabellone.gd [-- --seeds=1-4 --mode=conquista --rounds=130 --tactical=0|1]

var started := false


func _process(_d: float) -> bool:
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
	var D = root.get_node("Data")
	var GameS: Script = load("res://scripts/core/game.gd")
	var CombatS: Script = load("res://scripts/core/combat.gd")
	if _arg("tactical", "1") == "0":
		CombatS.tactical = false
	var seeds: Array = []
	var sa := _arg("seeds", "1-4")
	if sa.contains("-"):
		for s in range(int(sa.split("-")[0]), int(sa.split("-")[1]) + 1):
			seeds.append(s)
	else:
		for x in sa.split(","):
			seeds.append(int(x))
	var max_r := int(_arg("rounds", "130"))
	var tot := {}
	for sd in seeds:
		var pls: Array = []
		for i in 4:
			pls.append({"faction": (i + sd) % 4, "human": false, "difficulty": "veterano"})
		var o := {"players": pls, "mode": _arg("mode", "conquista"), "distribution": "regionale", "seed": sd,
			"auto_battles": true, "ask_defense": false, "ai_step_delay": 0.0}
		if _arg("classic", "0") == "1":   # regole di prima della notte 3 (confronto)
			o["missions"] = false
			o["events"] = false
			o["attacks_per_turn"] = 1
		if _arg("apt", "0") != "0":
			o["attacks_per_turn"] = int(_arg("apt", "0"))
		if _arg("fog_mode", "") != "":
			o["fog_mode"] = _arg("fog_mode", "")
		var g = GameS.new(o)
		var m := {"turns0": 0, "att0": 0, "att0_neutral": 0, "att0_win": 0, "move0": 0, "v0": 0, "v1": 0, "v2": 0, "vsum": 0,
			"hit0": 0, "lost0": 0, "battles": 0, "captures": 0, "pvp_first": -1, "elim": [], "headlines": 0, "ops": 0, "deceit": 0,
			"lead_changes": 0, "ai_steps": 0, "ai_turns": 0, "fog_enemy": 0, "fog_hidden": 0, "fog_all": 0, "fog_all_hidden": 0,
			"stag_max": 0, "first_pvp0": -1, "cards0": 0, "newthing_rounds": 0, "obj_done": 0, "obj_new": 0, "wevents": 0, "threat0": 0,
			"neutral_start": 0, "thr": 0, "thr_kept": 0, "hit0_ann": 0, "att0_r5": 0, "terr0_r5": 0, "terr0_r10": 0}
		for tr in g.terr:
			if int(tr["owner"]) < 0:
				m["neutral_start"] += 1
		var st := {"leader": -1, "stag": 0, "last_n": -1, "round_new": false}
		var ann := {}
		var nxt := {}
		var cb := func(n: String, d: Dictionary) -> void:
			match n:
				"turn_start":
					var tp := int(d["player"])
					ann.erase(tp)
					if nxt.has(tp):
						ann[tp] = nxt[tp]
						nxt.erase(tp)
						m["thr"] += 1
					if tp == 0 and g.round == 6:
						m["terr0_r5"] = g.territories_of(0).size()
					if tp == 0 and g.round == 11:
						m["terr0_r10"] = g.territories_of(0).size()
					if int(d["player"]) == 0 and g.players[0]["alive"]:
						m["turns0"] += 1
						# opzioni d'attacco "vincibili" (previsione) contando i rinforzi del turno
						var pool: int = int(g.players[0]["pool"]["inf"])
						var viable := 0
						for t in g.territories_of(0):
							var tr: Dictionary = g.terr[t]
							tr["forces"]["inf"] += pool
							if D.total_units(tr["forces"]) >= 2:
								var f: Dictionary = D.clone_forces(tr["forces"])
								f["inf"] = maxi(0, int(f["inf"]) - 1)
								for tg in g.attack_targets(0, t):
									var pr: Dictionary = g.predict_attack(t, int(tg["idx"]), f)
									if str(pr.get("winner", "def")) == "att":
										viable += 1
							tr["forces"]["inf"] -= pool
						m["vsum"] += viable
						m["v0" if viable == 0 else ("v1" if viable == 1 else "v2")] += 1
						var n0: int = g.territories_of(0).size()
						if n0 == int(st["last_n"]):
							st["stag"] = int(st["stag"]) + 1
							m["stag_max"] = maxi(int(m["stag_max"]), int(st["stag"]))
						else:
							st["stag"] = 0
						st["last_n"] = n0
						# cosa nasconderebbe la nebbia leggera al posto 0
						var fm: String = g.fog_mode
						var fg: bool = g.fog
						g.fog_mode = "light"; g.fog = true; g._vis_cache.clear()
						for tr2 in g.terr:
							var ow: int = int(tr2["owner"])
							if ow == 0:
								continue
							m["fog_all"] += 1
							var ex: bool = bool(g.forces_view(0, int(tr2["idx"]))["exact"])
							if not ex:
								m["fog_all_hidden"] += 1
							if ow > 0:
								m["fog_enemy"] += 1
								if not ex:
									m["fog_hidden"] += 1
						g.fog_mode = fm; g.fog = fg; g._vis_cache.clear()
				"turn_end":
					if int(d["player"]) != 0:
						m["ai_steps"] += int(g._turn_steps)
						m["ai_turns"] += 1
				"attack":
					var p := int(d["player"])
					var df := int(d["defender"])
					if ann.has(p) and int(ann[p]) == int(d["to"]):
						m["thr_kept"] += 1
						if df == 0:
							m["hit0_ann"] += 1
						ann.erase(p)
					if p == 0 and g.round <= 5:
						m["att0_r5"] += 1
					if p == 0:
						m["att0"] += 1
						if df < 0:
							m["att0_neutral"] += 1
						elif int(m["first_pvp0"]) < 0:
							m["first_pvp0"] = g.round
					if df == 0:
						m["hit0"] += 1
					if df >= 0 and int(m["pvp_first"]) < 0:
						m["pvp_first"] = g.round
				"battle":
					m["battles"] += 1
					if int(d["attacker"]) == 0 and str(d["winner"]) == "att":
						m["att0_win"] += 1
				"capture":
					m["captures"] += 1
					if int(d["prev"]) == 0:
						m["lost0"] += 1
				"move":
					if int(d["player"]) == 0:
						m["move0"] += 1
				"eliminated":
					m["elim"].append(g.round)
				"headline":
					m["headlines"] += 1
					st["round_new"] = true
				"missile", "sabotage", "golpe":
					m["ops"] += 1
					st["round_new"] = true
				"deceit":
					m["deceit"] += 1
				"card":
					if int(d["player"]) == 0:
						m["cards0"] += 1
				"objective_done":
					m["obj_done"] += 1
				"objective_new":
					m["obj_new"] += 1
				"world_event":
					m["wevents"] += 1
					st["round_new"] = true
				"threat":
					nxt[int(d["player"])] = int(d["to"])
					if int(d.get("target_owner", -1)) == 0:
						m["threat0"] += 1
				"round":
					if st["round_new"]:
						m["newthing_rounds"] += 1
					st["round_new"] = false
					var best := -1
					var bn := -1
					for P in g.players:
						var c: int = g.territories_of(P["idx"]).size()
						if c > bn:
							bn = c; best = P["idx"]
					if best != int(st["leader"]):
						if int(st["leader"]) >= 0:
							m["lead_changes"] += 1
						st["leader"] = best
		g.event.connect(cb)
		var t0 := Time.get_ticks_msec()
		while g.over == null and g.round <= max_r:
			g.update(0.1)
			if g.pending_battle != null:
				g.resolve_pending_auto()
		var R: int = mini(g.round, g.round_limit)
		var T0: float = maxf(1.0, float(m["turns0"]))
		print("seed %d: %s round %d (%s) | neutrali all'inizio %d | posto0: turni %d, attacchi %d (neutrali %d, vinti %d), spostamenti %d, opzioni vincibili 0/1/2+ = %d/%d/%d (media %.1f), primo attacco a un giocatore round %d, stallo massimo %d turni, subiti %d attacchi, persi %d terr., carte %d | mondo: battaglie/round %.2f, conquiste/round %.2f, primo scontro tra giocatori round %d, eliminazioni %s, titoli %d, operazioni %d, inganni %d, cambi di testa %d, round con una novità %d%% | obiettivi brevi fatti %d/%d, eventi mondiali %d, minacce annunciate a posto0 %d (in tutto %d, mantenute %d%%; attacchi subiti da posto0 preannunciati %d su %d) | primi 5 round: attacchi posto0 %d, territori al round 6 = %d, al round 11 = %d | azioni IA per turno %.1f | nebbia leggera: nemici non esatti %d%%, non propri non esatti %d%% | %.0f s" % [
			sd, g.players[g.over["winner"]]["fac"]["short"] if g.over != null and int(g.over["winner"]) >= 0 else "-", R,
			str(g.over["reason"]).substr(0, 28) if g.over != null else "non finita", m["neutral_start"],
			m["turns0"], m["att0"], m["att0_neutral"], m["att0_win"], m["move0"], m["v0"], m["v1"], m["v2"], m["vsum"] / T0, m["first_pvp0"], m["stag_max"],
			m["hit0"], m["lost0"], m["cards0"], m["battles"] / float(R), m["captures"] / float(R), m["pvp_first"], str(m["elim"]), m["headlines"], m["ops"], m["deceit"],
			m["lead_changes"], roundi(100.0 * m["newthing_rounds"] / float(R)), m["obj_done"], m["obj_new"], m["wevents"], m["threat0"], m["thr"], roundi(100.0 * m["thr_kept"] / maxf(1.0, float(m["thr"]))), m["hit0_ann"], m["hit0"],
			m["att0_r5"], m["terr0_r5"], m["terr0_r10"],
			m["ai_steps"] / maxf(1.0, float(m["ai_turns"])),
			roundi(100.0 * m["fog_hidden"] / maxf(1.0, float(m["fog_enemy"]))), roundi(100.0 * m["fog_all_hidden"] / maxf(1.0, float(m["fog_all"]))),
			(Time.get_ticks_msec() - t0) / 1000.0])
		for k in m:
			if m[k] is int or m[k] is float:
				tot[k] = float(tot.get(k, 0.0)) + float(m[k])
		tot["rounds"] = float(tot.get("rounds", 0.0)) + R
		tot["games"] = float(tot.get("games", 0.0)) + 1
		g.event.disconnect(cb)
		if g.has_method("dispose"):
			g.dispose()
	var G: float = maxf(1.0, tot.get("games", 1.0))
	var TT: float = maxf(1.0, tot.get("turns0", 1.0))
	print("MEDIA su %d partite: %.0f round | posto0: attacca nel %d%% dei turni (vince %d%%), sposta nel %d%%, turni con 0/1/2+ opzioni vincibili %d%%/%d%%/%d%%, subisce %.2f attacchi/turno, stallo massimo medio %.0f turni | battaglie/round %.2f conquiste/round %.2f | round con una novità %d%% | obiettivi brevi %.1f fatti su %.1f, eventi mondiali %.1f, minacce %.1f a partita (mantenute %d%%, attacchi subiti preannunciati %d%%) | primi 5 round: %.1f attacchi, %.1f territori al round 6, %.1f al round 11 | azioni IA/turno %.1f | nebbia leggera: nemici non esatti %d%%" % [
		int(G), tot["rounds"] / G, roundi(100 * tot["att0"] / TT), roundi(100 * tot["att0_win"] / maxf(1.0, tot["att0"])), roundi(100 * tot["move0"] / TT),
		roundi(100 * tot["v0"] / TT), roundi(100 * tot["v1"] / TT), roundi(100 * tot["v2"] / TT), tot["hit0"] / TT, tot["stag_max"] / G,
		tot["battles"] / tot["rounds"], tot["captures"] / tot["rounds"], roundi(100 * tot["newthing_rounds"] / tot["rounds"]),
		tot["obj_done"] / G, tot["obj_new"] / G, tot["wevents"] / G, tot["threat0"] / G, roundi(100 * tot["thr_kept"] / maxf(1.0, tot["thr"])), roundi(100 * tot["hit0_ann"] / maxf(1.0, tot["hit0"])),
		tot["att0_r5"] / G, tot["terr0_r5"] / G, tot["terr0_r10"] / G,
		tot["ai_steps"] / maxf(1.0, tot["ai_turns"]), roundi(100 * tot["fog_hidden"] / maxf(1.0, tot["fog_enemy"]))])
