extends RefCounted
## SEGNAPOSTO del nucleo di gioco (usato SOLO se res://scripts/core/game.gd non esiste ancora).
## Implementa in modo semplificato l'interfaccia pubblica di Game (SPEC3D) per collaudare l'interfaccia.

signal event(name: String, data: Dictionary)

var opts := {}
var time := 0.0
var speed := 1.0
var paused := false
var over = null
var human_idx := -1
var players := []
var terr := []
var divisions := []
var events := []
var effects := []
var pending_battle = null
var ais := []
var rng := RandomNumberGenerator.new()
var _next_div := 1
var _manual = null
var market := {"oil": 1.0, "steel": 1.0, "manpower": 1.0}

func _init(o: Dictionary = {}) -> void:
	opts = o
	rng.seed = int(o.get("seed", 1))
	var pl: Array = o.get("players", [{"faction": 0, "human": true, "difficulty": "veterano"}])
	for i in pl.size():
		var F: Dictionary = Data.FACTIONS[int(pl[i]["faction"])]
		var P := {"idx": i, "faction": int(pl[i]["faction"]), "fac": F, "name": F["name"], "color": Color(F["color"]),
			"human": bool(pl[i].get("human", false)), "difficulty": pl[i].get("difficulty", "veterano"),
			"res": Data.ECON["startRes"].duplicate(), "rates": {"money": 0, "oil": 0, "steel": 0, "manpower": 0},
			"tech": 1, "research": null, "hq": -1, "alive": true, "cards": [], "card_cd": 0, "sets_traded": 0,
			"pool": Data.empty_forces(), "next_reinforce": Data.ECON["reinforceEvery"], "objective": null, "low_oil": false,
			"stats": {"conquered": 0, "lost": 0, "battlesWon": 0, "battlesLost": 0, "killed": 0, "unitsLost": 0}}
		if P["human"] and human_idx < 0:
			human_idx = i
		players.append(P)
	for T in Data.TERRITORIES:
		var f := Data.empty_forces()
		f["inf"] = 2 + rng.randi() % 4
		terr.append({"idx": T["idx"], "owner": -1, "forces": f, "buildings": [], "building": null, "queue": [],
			"sabotage": 0.0, "unrest": 0.0, "regroup": 0.0, "supplied": true})
	var hqs := [15, 34, 5, 25]
	for P in players:
		var hq: int = hqs[P["idx"] % hqs.size()]
		P["hq"] = hq
		var mine := [hq]
		for j in Data.TERRITORIES[hq]["adj"]:
			if terr[j]["owner"] < 0 and mine.size() < 5:
				mine.append(j)
		for t in mine:
			terr[t]["owner"] = P["idx"]
			terr[t]["forces"] = {"inf": 6, "tank": 2, "art": 1, "aa": 0, "heli": 0, "jet": 0, "drone": 0}
		terr[hq]["forces"] = {"inf": 12, "tank": 4, "art": 3, "aa": 1, "heli": 0, "jet": 0, "drone": 0}
		terr[hq]["buildings"] = ["caserma"]
		if o.get("mode", "") == "obiettivo":
			P["objective"] = {"type": "count", "count": 24, "text": "Conquista 24 territori"}
	if human_idx >= 0:
		var H: Dictionary = players[human_idx]
		H["cards"] = [{"type": "inf"}, {"type": "tank"}, {"type": "air"}, {"type": "inf"}]
		H["pool"]["inf"] = 4
		terr[H["hq"]]["building"] = {"key": "fabbrica", "t": 9.0, "total": 25.0}
		terr[H["hq"]]["queue"] = [{"unit": "inf", "t": 1.2, "total": 3.0}, {"unit": "inf", "t": 0, "total": 3.0}, {"unit": "tank", "t": 0, "total": 6.0}]
		H["research"] = {"level": 2, "t": 18.0, "total": 45.0}
	_log("Partita iniziata (segnaposto: nucleo di gioco non ancora disponibile)", "info", null)
	_rates()

func _log(text: String, type: String, player) -> void:
	events.append({"time": time, "text": text, "type": type, "player": player})

func _rates() -> void:
	for P in players:
		var n := territories_of(P["idx"]).size()
		P["rates"] = {"money": 0.7 * n * 0.6, "oil": 0.1 * n - 0.05, "steel": 0.15 * n, "manpower": 0.35 * n * 0.6}

# ------------------------------------------------------------------ interrogazioni
func territories_of(p: int) -> Array:
	var o := []
	for t in terr:
		if t["owner"] == p:
			o.append(t["idx"])
	return o
func owns_continent(p: int, c: String) -> bool:
	for i in Data.CONT_TERR[c]:
		if terr[i]["owner"] != p:
			return false
	return p >= 0
func continent_owner(c: String) -> int:
	for P in players:
		if owns_continent(P["idx"], c):
			return P["idx"]
	return -1
func cost_for(p: int, u: String) -> Dictionary:
	return Data.UNITS[u]["cost"].duplicate()
func can_afford(p: int, cost: Dictionary) -> bool:
	for k in cost:
		if float(players[p]["res"].get(k, 0)) < float(cost[k]):
			return false
	return true
func unit_available(p: int, u: String) -> bool:
	return players[p]["tech"] >= int(Data.UNITS[u]["tech"])
func can_recruit(p: int, t: int, u: String) -> Dictionary:
	if not unit_available(p, u):
		return {"ok": false, "reason": "Richiede Tech %d" % Data.UNITS[u]["tech"]}
	var b: String = Data.UNITS[u]["build"]
	var tr: Dictionary = terr[t]
	if not (tr["buildings"].has(b) or (players[p]["hq"] == t and b != "aeroporto")):
		return {"ok": false, "reason": "Serve: " + Data.BUILDINGS[b]["name"]}
	if not can_afford(p, cost_for(p, u)):
		return {"ok": false, "reason": "Risorse insufficienti"}
	return {"ok": true, "reason": ""}
func can_build(p: int, t: int, k: String) -> Dictionary:
	var tr: Dictionary = terr[t]
	var mx := Data.HQ_SLOTS if players[p]["hq"] == t else Data.SLOTS
	if tr["building"] != null:
		return {"ok": false, "reason": "Costruzione già in corso"}
	if tr["buildings"].size() >= mx:
		return {"ok": false, "reason": "Nessuno slot libero"}
	if not can_afford(p, Data.BUILDINGS[k]["cost"]):
		return {"ok": false, "reason": "Risorse insufficienti"}
	return {"ok": true, "reason": ""}
func research_cost(p: int):
	var P: Dictionary = players[p]
	if P["tech"] >= 4:
		return null
	var L: Dictionary = Data.TECH_LEVELS[P["tech"] + 1]
	return {"cost": L["cost"], "time": L["time"], "level": P["tech"] + 1}
func valid_targets(p: int, from: int) -> Array:
	if terr[from]["owner"] != p:
		return []
	var out := []
	for j in Data.TERRITORIES[from]["adj"]:
		out.append({"idx": j, "sea": Data.is_sea_link(from, j), "airlift": false})
	return out
func travel_time(p: int, from: int, to: int, f = null) -> float:
	var a: Dictionary = Data.TERRITORIES[from]
	var b: Dictionary = Data.TERRITORIES[to]
	return Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"])) / 22.0
func visible_forces(viewer: int, t: int):
	return terr[t]["forces"]
func income_of(p: int) -> Dictionary:
	return players[p]["rates"]
func reinforce_amount(p: int) -> int:
	return maxi(4, territories_of(p).size() / 3)
func is_valid_set(cards: Array) -> bool:
	if cards.size() != 3:
		return false
	var types := {}
	for c in cards:
		if c == null:
			return false
		if c["type"] == "jolly":
			return true
		types[c["type"]] = true
	return types.size() == 1 or types.size() == 3
func find_set(p: int):
	var c: Array = players[p]["cards"]
	for i in c.size():
		for j in range(i + 1, c.size()):
			for k in range(j + 1, c.size()):
				if is_valid_set([c[i], c[j], c[k]]):
					return [i, j, k]
	return null
func set_value(p: int) -> int:
	return Data.SET_VALUES[mini(players[p]["sets_traded"], Data.SET_VALUES.size() - 1)]
func market_price(p: int, r: String, dir: String) -> int:
	return int(round(Data.MARKET["lot"] * float(market[r]) * (Data.MARKET["sell"] if dir == "sell" else Data.MARKET["buy"])))

# ------------------------------------------------------------------ comandi
func send_division(p: int, from: int, to: int, q) -> Dictionary:
	var tr: Dictionary = terr[from]
	var f := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		f[k] = tr["forces"][k] if float(q) >= 1.0 else int(floor(tr["forces"][k] * float(q)))
	if Data.total_units(f) == 0:
		return {"ok": false, "reason": "Nessuna unità da inviare"}
	for k in Data.UNIT_KEYS:
		tr["forces"][k] -= f[k]
	var T: Dictionary = Data.TERRITORIES[from]
	divisions.append({"id": _next_div, "owner": p, "from": from, "to": to, "forces": f, "t": 0.0, "total": travel_time(p, from, to),
		"sea": Data.is_sea_link(from, to), "airlift": false, "retreat": false, "x": T["x"], "y": T["y"]})
	_next_div += 1
	return {"ok": true, "reason": ""}
func recruit(p: int, t: int, u: String, n: int = 1) -> Dictionary:
	var c := can_recruit(p, t, u)
	if not c["ok"]:
		return c
	for i in n:
		if not can_afford(p, cost_for(p, u)):
			break
		for k in cost_for(p, u):
			players[p]["res"][k] -= cost_for(p, u)[k]
		terr[t]["queue"].append({"unit": u, "t": 0.0, "total": float(Data.UNITS[u]["time"])})
	return {"ok": true, "reason": ""}
func build(p: int, t: int, k: String) -> Dictionary:
	var c := can_build(p, t, k)
	if not c["ok"]:
		return c
	terr[t]["building"] = {"key": k, "t": 0.0, "total": float(Data.BUILDINGS[k]["time"])}
	return {"ok": true, "reason": ""}
func research(p: int) -> Dictionary:
	var rc = research_cost(p)
	if rc == null or players[p]["research"] != null:
		return {"ok": false, "reason": "Ricerca non disponibile"}
	players[p]["research"] = {"level": rc["level"], "t": 0.0, "total": float(rc["time"])}
	return {"ok": true, "reason": ""}
func place_pool(p: int, t: int) -> Dictionary:
	Data.add_forces(terr[t]["forces"], players[p]["pool"])
	players[p]["pool"] = Data.empty_forces()
	return {"ok": true, "reason": ""}
func hire_mercs(p: int, t: int) -> Dictionary:
	terr[t]["forces"]["inf"] += 5
	return {"ok": true, "reason": ""}
func play_cards(p: int, idxs: Array, op: String, target: int) -> Dictionary:
	var c: Array = players[p]["cards"]
	var keep := []
	for i in c.size():
		if not idxs.has(i):
			keep.append(c[i])
	players[p]["cards"] = keep
	players[p]["sets_traded"] += 1
	event.emit("card", {"player": p})
	return {"ok": true, "reason": ""}
func trade(p: int, r: String, dir: String) -> Dictionary:
	var price := market_price(p, r, dir)
	if dir == "sell":
		players[p]["res"][r] -= 100
		players[p]["res"]["money"] += price
	else:
		players[p]["res"][r] += 100
		players[p]["res"]["money"] -= price
	return {"ok": true, "reason": ""}

# ------------------------------------------------------------------ battaglie
func resolve_pending_auto() -> Dictionary:
	var info = pending_battle
	if info == null:
		return {"ok": false, "reason": ""}
	pending_battle = null
	_apply(info, Data.total_units(info["forces"]) > Data.total_units(terr[info["terr"]]["forces"]), info["forces"])
	return {"ok": true, "reason": ""}
func start_manual_battle():
	var info = pending_battle
	if info == null:
		return null
	var tr: Dictionary = terr[info["terr"]]
	var T: Dictionary = Data.TERRITORIES[info["terr"]]
	var A: Dictionary = players[info["attacker"]]
	var o: int = tr["owner"]
	_manual = info
	return {"terrIdx": info["terr"], "terrain": T["ter"], "terrName": T["name"], "sea": info["sea"], "seed": rng.randi(),
		"att": {"player": info["attacker"], "name": A["name"], "color": A["color"], "forces": info["forces"].duplicate(), "mods": {"atk": 1.1, "def": 1.0}, "human": A["human"]},
		"def": {"player": o, "name": players[o]["name"] if o >= 0 else "Neutrali", "color": players[o]["color"] if o >= 0 else Color("#d6d9de"),
			"forces": tr["forces"].duplicate(), "mods": {"atk": 1.0, "def": 1.0}, "human": false, "bunkers": 0}, "support": {"att": 0, "def": 0}}
func finish_manual_battle(result: Dictionary) -> Dictionary:
	var info = pending_battle if pending_battle != null else _manual
	pending_battle = null
	_manual = null
	if info == null:
		return {"ok": false, "reason": ""}
	_apply(info, result.get("winner", "def") == "att", result.get("att", Data.empty_forces()))
	return {"ok": true, "reason": ""}
func _apply(info: Dictionary, att_wins: bool, left: Dictionary) -> void:
	var tr: Dictionary = terr[info["terr"]]
	var T: Dictionary = Data.TERRITORIES[info["terr"]]
	event.emit("battle", {"terr": info["terr"], "winner": "att" if att_wins else "def", "attacker": info["attacker"], "defender": tr["owner"]})
	_log("Battaglia per " + T["name"] + ": " + ("vince l'attaccante" if att_wins else "resiste il difensore"), "battle", null)
	if att_wins:
		var prev: int = tr["owner"]
		tr["owner"] = info["attacker"]
		tr["forces"] = Data.clone_forces(left)
		event.emit("capture", {"terr": info["terr"], "by": info["attacker"], "prev": prev})
		_log("Conquistato " + T["name"], "good", info["attacker"])

# ------------------------------------------------------------------ ciclo
func update(real_dt: float) -> void:
	if paused or over != null or pending_battle != null:
		return
	step(minf(0.5, real_dt * speed))

func step(dt: float) -> void:
	time += dt
	for P in players:
		for k in Data.RES_KEYS:
			P["res"][k] = maxf(0.0, float(P["res"][k]) + float(P["rates"][k]) * dt)
		P["next_reinforce"] -= dt
		if P["next_reinforce"] <= 0:
			P["next_reinforce"] = Data.ECON["reinforceEvery"]
			P["pool"]["inf"] += reinforce_amount(P["idx"])
			event.emit("reinforce", {"player": P["idx"], "count": reinforce_amount(P["idx"])})
		if P["research"] != null:
			P["research"]["t"] += dt
			if P["research"]["t"] >= P["research"]["total"]:
				P["tech"] = P["research"]["level"]
				P["research"] = null
				event.emit("researched", {"player": P["idx"], "level": P["tech"]})
	for tr in terr:
		if tr["building"] != null:
			tr["building"]["t"] += dt
			if tr["building"]["t"] >= tr["building"]["total"]:
				tr["buildings"].append(tr["building"]["key"])
				event.emit("built", {"player": tr["owner"], "terr": tr["idx"], "key": tr["building"]["key"]})
				tr["building"] = null
		if tr["queue"].size():
			var q: Dictionary = tr["queue"][0]
			q["t"] += dt
			if q["t"] >= q["total"]:
				tr["forces"][q["unit"]] += 1
				tr["queue"].pop_front()
	var keep := []
	for d in divisions:
		d["t"] += dt
		var a: Dictionary = Data.TERRITORIES[d["from"]]
		var b: Dictionary = Data.TERRITORIES[d["to"]]
		var k: float = clampf(d["t"] / maxf(0.01, d["total"]), 0, 1)
		d["x"] = lerpf(a["x"], b["x"], k)
		d["y"] = lerpf(a["y"], b["y"], k)
		if k >= 1.0:
			var tr: Dictionary = terr[d["to"]]
			if tr["owner"] == d["owner"]:
				Data.add_forces(tr["forces"], d["forces"])
			elif pending_battle == null and players[d["owner"]]["human"]:
				pending_battle = {"id": d["id"], "attacker": d["owner"], "defender": tr["owner"], "terr": d["to"], "from": d["from"], "forces": d["forces"], "sea": d["sea"]}
				event.emit("pending", {"battle": pending_battle})
			else:
				_apply({"attacker": d["owner"], "terr": d["to"], "forces": d["forces"]}, Data.total_units(d["forces"]) > Data.total_units(tr["forces"]), d["forces"])
			continue
		keep.append(d)
	divisions = keep
	_rates()
