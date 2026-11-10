extends RefCounted
## Stato finto per provare il tabellone quando `Game` non esiste ancora (stessa forma dei campi pubblici di Game).

const D = preload("res://scripts/core/data.gd")

var time := 0.0
var human_idx := -1
var over = null
var players: Array = []
var terr: Array = []
var divisions: Array = []
var effects: Array = []
var _rng := RandomNumberGenerator.new()
var _next_div := 1
var _next_ev := 0.0

func _init(seed_v: int = 7) -> void:
	_rng.seed = seed_v
	for f in 4:
		players.append({"idx": f, "faction": f, "fac": D.FACTIONS[f], "name": D.FACTIONS[f]["short"],
			"color": Color(D.FACTIONS[f]["color"]), "human": false, "hq": -1, "alive": true})
	var conts := {"NA": 0, "EU": 1, "AS": 2, "SA": 3, "AF": 3, "OC": 2}
	for t in D.TERRITORIES:
		var o: int = conts[t["c"]]
		if _rng.randf() < 0.25:
			o = -1
		var f: Dictionary = Data.empty_forces()
		f["inf"] = _rng.randi_range(1, 8)
		if _rng.randf() < 0.5: f["tank"] = _rng.randi_range(1, 5)
		if _rng.randf() < 0.3: f["art"] = _rng.randi_range(1, 3)
		if _rng.randf() < 0.2: f["heli"] = _rng.randi_range(1, 3)
		if _rng.randf() < 0.1: f["jet"] = _rng.randi_range(1, 2)
		var bl: Array = []
		for k in D.BUILDING_KEYS:
			if _rng.randf() < 0.18 and bl.size() < 3:
				bl.append(k)
		terr.append({"idx": t["idx"], "owner": o, "forces": f, "buildings": bl,
			"building": {"key": "fabbrica", "t": 5.0, "total": 25.0} if _rng.randf() < 0.15 else null,
			"queue": [{"unit": "inf", "t": 1.0, "total": 3.0}] if _rng.randf() < 0.2 else [],
			"sabotage": 30.0 if _rng.randf() < 0.06 else 0.0, "unrest": 40.0 if _rng.randf() < 0.06 else 0.0,
			"regroup": 0.0, "supplied": _rng.randf() > 0.08})
	players[0]["hq"] = 6
	players[1]["hq"] = 17
	players[2]["hq"] = 34
	players[3]["hq"] = 11
	for p in players:
		terr[p["hq"]]["owner"] = p["idx"]

func visible_forces(viewer: int, t: int):
	var tr: Dictionary = terr[t]
	if viewer < 0 or tr["owner"] == viewer or tr["owner"] < 0:
		return Data.clone_forces(tr["forces"])
	if players[tr["owner"]]["faction"] == 3 and D.TERRITORIES[t]["ter"] == "urbano":
		return null
	return Data.clone_forces(tr["forces"])

func update(dt: float) -> void:
	step(dt)

func step(dt: float) -> void:
	time += dt
	_next_ev -= dt
	if _next_ev <= 0.0:
		_next_ev = _rng.randf_range(1.0, 3.0)
		var a := _rng.randi_range(0, terr.size() - 1)
		var T: Dictionary = D.TERRITORIES[a]
		var adj: Array = T["adj"]
		if adj.size() > 0 and terr[a]["owner"] >= 0:
			var b: int = adj[_rng.randi_range(0, adj.size() - 1)]
			var f: Dictionary = Data.empty_forces()
			f["inf"] = _rng.randi_range(1, 4)
			if _rng.randf() < 0.5: f["tank"] = _rng.randi_range(1, 3)
			if _rng.randf() < 0.2: f["jet"] = 2
			var sea := Data.is_sea_link(a, b)
			divisions.append({"id": _next_div, "owner": terr[a]["owner"], "from": a, "to": b, "forces": f, "t": 0.0,
				"total": _rng.randf_range(8.0, 16.0) * (2.0 if sea else 1.0), "sea": sea, "airlift": false, "retreat": false,
				"x": T["x"], "y": T["y"]})
			_next_div += 1
		if _rng.randf() < 0.3:
			var tt: Dictionary = D.TERRITORIES[_rng.randi_range(0, terr.size() - 1)]
			var src: Dictionary = D.TERRITORIES[_rng.randi_range(0, terr.size() - 1)]
			effects.append({"type": "missile", "x": src["x"], "y": src["y"], "x2": tt["x"], "y2": tt["y"], "born": time, "dur": 2.2})
			effects.append({"type": "explosion", "x": tt["x"], "y": tt["y"], "born": time + 1.9, "dur": 1.6})
	var done: Array = []
	for d in divisions:
		d["t"] = minf(d["total"], d["t"] + dt)
		var A: Dictionary = D.TERRITORIES[d["from"]]
		var B: Dictionary = D.TERRITORIES[d["to"]]
		var f: float = d["t"] / d["total"]
		d["x"] = lerpf(A["x"], B["x"], f)
		d["y"] = lerpf(A["y"], B["y"], f)
		if d["t"] >= d["total"]:
			done.append(d)
	for d in done:
		divisions.erase(d)
		var tr: Dictionary = terr[d["to"]]
		var B: Dictionary = D.TERRITORIES[d["to"]]
		if tr["owner"] == d["owner"]:
			Data.add_forces(tr["forces"], d["forces"])
		elif Data.total_units(d["forces"]) > Data.total_units(tr["forces"]) or _rng.randf() < 0.4:
			tr["owner"] = d["owner"]
			tr["forces"] = Data.clone_forces(d["forces"])
			effects.append({"type": "capture", "x": B["x"], "y": B["y"], "born": time, "dur": 1.6})
		else:
			effects.append({"type": "battle", "x": B["x"], "y": B["y"], "born": time, "dur": 2.0})
			effects.append({"type": "explosion", "x": B["x"] + 4, "y": B["y"] - 3, "born": time, "dur": 1.6})
	var keep: Array = []
	for e in effects:
		if time - e["born"] < e["dur"] + 0.5:
			keep.append(e)
	effects = keep
