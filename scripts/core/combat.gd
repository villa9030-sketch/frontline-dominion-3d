class_name Combat
extends RefCounted
## FRONTLINE DOMINION 3D — risoluzione automatica delle battaglie e modificatori.
## Porting di frontline/js/combat.js. Nessun accesso a nodi/scene.
## Mods: {"atk": float, "unit": {unitKey: mult}, "hp": {unitKey: mult}, "ctx": {...}}
##
## Fase 5 — risoluzione automatica TATTICA: se i mods portano il contesto `ctx` (lo aggiunge combat_mods: terreno, bunker,
## fortificazioni, supporto d'artiglieria) resolve_battle simula davvero la battaglia con BattleSim (entrambi i lati IA, senza
## grafica, passo 0.7 s), così composizione, terreno e posizione contano come in una battaglia comandata.
## La vecchia formula (_simulate) resta: per predict_battle (stime dell'IA strategica, migliaia di chiamate), per mods senza
## contesto (test, chiamate esterne), con ctx.engine == "formula", con `Combat.tactical = false`, o per battaglie oltre
## TACTICAL_MAX_UNITS unità (dove la simulazione costerebbe troppo).

const COMBAT_K := 0.12          # danno per round (frazione di atk·count)
const COMBAT_NOISE := 0.15      # rumore ±15% per round e per tipo
const COMBAT_MAX_ROUNDS := 80
const COMBAT_END_UNITS := 0.5   # un lato con meno di mezza unità è annientato
const VET_BONUS := 0.06         # attacco per stella di veterano
const TACTICAL_MAX_UNITS := 240  # oltre (att + dif) si usa la formula
## Interruttore globale della risoluzione tattica (true = BattleSim headless quando c'è il contesto).
static var tactical := true
## Statistiche (per i test): battaglie risolte e millisecondi totali per motore.
static var stats := {"tactical": 0, "formula": 0, "tactical_ms": 0, "tactical_max_ms": 0}


static func default_mods() -> Dictionary:
	return {"atk": 1.0, "unit": {}, "hp": {}}


## game: istanza Game (o null); role: "att" | "def"; opts: {fromIdx, sea, manual, vet (stelle 0..3)}
static func combat_mods(game, player_idx: int, role: String, terr_idx: int, opts: Dictionary = {}) -> Dictionary:
	var mods := {"atk": 1.0, "unit": {}, "hp": {}}
	var T = Data.TERRITORIES[terr_idx] if terr_idx >= 0 and terr_idx < Data.TERRITORIES.size() else null
	var ter = Data.TERRAINS[T["ter"]] if T != null else null
	if ter != null:
		for k in ter["mul"]:
			mods["unit"][k] = float(ter["mul"][k])
		if role == "def":
			mods["atk"] *= float(ter["def"])
	var p = game.players[player_idx] if (game != null and player_idx >= 0) else null
	if p != null:
		var tech: int = int(p.get("tech", 1)) if p.get("tech", 1) else 1
		mods["atk"] *= 1.0 + Data.TECH_COMBAT_BONUS * (tech - 1)
		var fm: Dictionary = p["fac"]["mods"] if p.get("fac") != null else {}
		if fm.get("tankHp"):
			mods["hp"]["tank"] = float(mods["hp"].get("tank", 1.0)) * float(fm["tankHp"])
		if fm.get("artAtk"):
			mods["unit"]["art"] = float(mods["unit"].get("art", 1.0)) * float(fm["artAtk"])
		if fm.get("guerrilla") and role == "def" and T != null and (T["ter"] == "urbano" or T["ter"] == "foresta"):
			mods["atk"] *= float(fm["guerrilla"])
		if p.get("low_oil", false):
			mods["atk"] *= Data.ECON["lowOilCombat"]
		if opts.get("manual", false) and p.get("human", false):
			mods["atk"] *= 1.10
	# veterani: +6% per stella (opts.vet del lato, 0..3)
	var vet := clampi(int(opts.get("vet", 0)) if opts.get("vet") != null else 0, 0, 3)
	if vet > 0:
		mods["atk"] *= 1.0 + VET_BONUS * vet
	# logoramento (docs/omogeneita.md §4): truppe reduci da una battaglia recente combattono al −15%
	if bool(opts.get("worn", false)):
		mods["atk"] *= float(Data.WORN_MUL)
	if game != null and game.terr != null and not game.terr.is_empty():
		if role == "def":
			var t = game.terr[terr_idx]
			if t != null and t["buildings"].has("bunker") and not (float(t["sabotage"]) > 0):
				mods["atk"] *= Data.ECON["bunkerDef"]
			if p != null and int(p["hq"]) == terr_idx:
				mods["atk"] *= Data.ECON["hqDef"]
			if p != null and game.owns_continent(player_idx, "OC"):
				mods["atk"] *= 1.15
		elif role == "att" and opts.get("fromIdx") != null and int(opts["fromIdx"]) >= 0:
			var f = game.terr[int(opts["fromIdx"])]
			var naval: bool = p != null and p.get("fac") != null and bool(p["fac"]["mods"].get("naval", false))
			if opts.get("sea", false) and not naval and not (f != null and f["buildings"].has("porto")):
				mods["atk"] *= Data.ECON["seaLandingPenalty"]
			if p != null and f != null and int(f["owner"]) == player_idx and f["supplied"] == false:
				mods["atk"] *= Data.ECON["unsuppliedCombat"]
	# contesto tattico per la risoluzione con BattleSim (solo tipi JSON)
	var ctx := {"ter": String(T["ter"]) if T != null else "pianura", "role": role, "terr": terr_idx, "sea": bool(opts.get("sea", false)),
		"human": p != null and bool(p.get("human", false)), "faction": int(p["faction"]) if p != null and p.get("faction") != null else -1,
		"bunkers": 0, "support": 0, "fort": {}, "buildings": [], "hq": false, "air": false, "naval": 0,
		"manual": bool(opts.get("manual", false)) and p != null and bool(p.get("human", false)), "worn": bool(opts.get("worn", false))}
	if opts.get("reinf") is Dictionary:
		ctx["reinf"] = opts["reinf"]
	if game != null and game.terr != null and not game.terr.is_empty() and terr_idx >= 0 and terr_idx < game.terr.size():
		var tt = game.terr[terr_idx]
		if role == "def" and tt != null:
			if tt["buildings"].has("bunker") and not (float(tt["sabotage"]) > 0):
				ctx["bunkers"] = 3
			var fo = tt.get("fort")
			if fo is Dictionary:
				ctx["fort"] = fo.duplicate()
			# omogeneità §2: edifici del territorio sul campo, QG della capitale, porto = tiro navale del difensore
			for b in tt["buildings"]:
				ctx["buildings"].append(String(b))
			ctx["hq"] = p != null and int(p["hq"]) == terr_idx
			if tt["buildings"].has("porto") and T != null and bool(T.get("coastal", false)) and not (float(tt["sabotage"]) > 0):
				ctx["naval"] = int(BattleRules.NAVAL_SUPPORT[1])
		if p != null and T != null:
			if int(p.get("tech", 1)) >= 3:
				var n := 0
				for j in T["adj"]:
					if game.terr[j]["owner"] == player_idx:
						n += int(game.terr[j]["forces"].get("art", 0))
				ctx["support"] = n
			# supporto aereo (J) solo con un aeroporto proprio nel territorio o in un confinante
			var air: bool = role == "def" and tt["owner"] == player_idx and tt["buildings"].has("aeroporto") and not (float(tt["sabotage"]) > 0)
			for j in T["adj"]:
				var tj = game.terr[j]
				if tj["owner"] == player_idx and tj["buildings"].has("aeroporto") and not (float(tj["sabotage"]) > 0):
					air = true
			ctx["air"] = air
			# tiro navale dell'attaccante: sbarco dal mare con porto nel territorio di partenza (o fazione navale)
			if role == "att" and bool(opts.get("sea", false)) and opts.get("fromIdx") != null and int(opts["fromIdx"]) >= 0:
				var f2 = game.terr[int(opts["fromIdx"])]
				var naval_fac: bool = p.get("fac") != null and bool(p["fac"]["mods"].get("naval", false))
				if naval_fac or (f2 != null and f2["buildings"].has("porto")):
					ctx["naval"] = int(BattleRules.NAVAL_SUPPORT[0])
	mods["ctx"] = ctx
	return mods


static func _mget(o, k: String) -> float:
	if o != null and o is Dictionary and o.get(k) != null:
		return float(o[k])
	return 1.0


static func _hp_of(k: String, mods: Dictionary) -> float:
	return Data.UNITS[k]["hp"] * maxf(0.01, _mget(mods.get("hp"), k))


static func _atk_of(k: String, mods: Dictionary) -> float:
	var a = mods.get("atk")
	return Data.UNITS[k]["atk"] * (float(a) if a != null else 1.0) * _mget(mods.get("unit"), k)


static func _units(c: Dictionary) -> float:
	var s := 0.0
	for k in Data.UNIT_KEYS:
		s += float(c[k])
	return s


static func _hp_total(c: Dictionary, mods: Dictionary) -> float:
	var s := 0.0
	for k in Data.UNIT_KEYS:
		s += float(c[k]) * _hp_of(k, mods)
	return s


## copia in virgola mobile (le forze nella simulazione sono frazionarie)
static func _fclone(f) -> Dictionary:
	var o := {}
	for k in Data.UNIT_KEYS:
		o[k] = float(f.get(k, 0)) if f != null and f.get(k) != null else 0.0
	return o


static func _rand(rng) -> float:
	return rng.randf()


## Danno inflitto dal lato S (mods mS) al lato T (mods mT): perdite frazionarie per tipo (o null).
static func _volley(S: Dictionary, Tg: Dictionary, mS: Dictionary, mT: Dictionary, rng, noise: bool):
	var loss := {"inf": 0.0, "tank": 0.0, "art": 0.0, "aa": 0.0, "heli": 0.0, "jet": 0.0, "drone": 0.0}
	var any := false
	for a in Data.UNIT_KEYS:
		var ca: float = S[a]
		if ca <= 1e-9:
			continue
		var row: Dictionary = Data.MATRIX[a]
		var W := 0.0
		for t in Data.UNIT_KEYS:
			if Tg[t] > 1e-9:
				W += Tg[t] * _hp_of(t, mT) * row[t]
		if W <= 0:
			continue
		var base: float = ca * _atk_of(a, mS) * COMBAT_K
		for t in Data.UNIT_KEYS:
			if Tg[t] <= 1e-9 or row[t] <= 0:
				continue
			var w: float = Tg[t] * _hp_of(t, mT) * row[t] / W
			var dmg: float = base * row[t] * w
			if noise and rng != null:
				dmg *= 1.0 + (_rand(rng) * 2.0 - 1.0) * COMBAT_NOISE
			if dmg > 0:
				loss[t] += dmg / _hp_of(t, mT)
				any = true
	return loss if any else null


static func _simulate(att_forces: Dictionary, def_forces: Dictionary, mods_a, mods_d, rng, noise: bool) -> Dictionary:
	var A := _fclone(att_forces)
	var D := _fclone(def_forces)
	var mA: Dictionary = mods_a if mods_a != null else default_mods()
	var mD: Dictionary = mods_d if mods_d != null else default_mods()
	var rounds := 0
	var winner := "def"
	while true:
		var aU := _units(A)
		var dU := _units(D)
		if aU < COMBAT_END_UNITS:
			winner = "def"
			break
		if dU < COMBAT_END_UNITS:
			winner = "att"
			break
		if rounds >= COMBAT_MAX_ROUNDS:
			winner = "def"
			break
		var lD = _volley(A, D, mA, mD, rng, noise)
		var lA = _volley(D, A, mD, mA, rng, noise)
		if lD == null and lA == null:
			winner = "def"   # stallo
			break
		rounds += 1
		for k in Data.UNIT_KEYS:
			if lD != null:
				D[k] = maxf(0.0, D[k] - lD[k])
			if lA != null:
				A[k] = maxf(0.0, A[k] - lA[k])
	return {"A": A, "D": D, "winner": winner, "rounds": rounds}


static func _round_forces(F: Dictionary, rng) -> Dictionary:
	var o := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		var x: float = F[k]
		var fl := int(floor(x + 1e-9))
		var r: float = _rand(rng) if rng != null else 0.5
		o[k] = fl + (1 if r < (x - fl) else 0)
	return o


static func _fix_winner(rounded: Dictionary, frac: Dictionary) -> void:
	if Data.total_units(rounded) > 0 or _units(frac) <= 1e-6:
		return
	var best := ""
	for k in Data.UNIT_KEYS:
		if best == "" or frac[k] > frac[best]:
			best = k
	rounded[best] = 1


## rng: RandomNumberGenerator (se null ne crea uno casuale)
static func resolve_battle(att_forces: Dictionary, def_forces: Dictionary, mods_a, mods_d, rng = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var ctx_d = mods_d.get("ctx") if mods_d is Dictionary else null
	var ctx_a = mods_a.get("ctx") if mods_a is Dictionary else null
	var ctx = ctx_d if ctx_d is Dictionary else ctx_a
	if tactical and ctx is Dictionary and String(ctx.get("engine", "")) != "formula" 			and Data.total_units(_iforces(att_forces)) > 0 and Data.total_units(_iforces(def_forces)) > 0 			and Data.total_units(_iforces(att_forces)) + Data.total_units(_iforces(def_forces)) <= TACTICAL_MAX_UNITS:
		return _resolve_tactical(att_forces, def_forces, mods_a, mods_d, ctx_a if ctx_a is Dictionary else {}, ctx_d if ctx_d is Dictionary else {}, rng)
	stats["formula"] += 1
	var s := _simulate(att_forces, def_forces, mods_a, mods_d, rng, true)
	var att := _round_forces(s["A"], rng)
	var def := _round_forces(s["D"], rng)
	if s["winner"] == "att":
		_fix_winner(att, s["A"])
		def = Data.empty_forces()
	else:
		_fix_winner(def, s["D"])
	# Mai più superstiti delle forze iniziali
	for k in Data.UNIT_KEYS:
		att[k] = mini(att[k], int(att_forces.get(k, 0)))
		def[k] = mini(def[k], int(def_forces.get(k, 0)))
	var att_losses := Data.empty_forces()
	var def_losses := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		att_losses[k] = maxi(0, int(att_forces.get(k, 0)) - att[k])
		def_losses[k] = maxi(0, int(def_forces.get(k, 0)) - def[k])
	return {"att": att, "def": def, "winner": s["winner"], "rounds": s["rounds"], "attLosses": att_losses, "defLosses": def_losses, "engine": "formula"}


static func _iforces(f) -> Dictionary:
	var o := Data.empty_forces()
	if f == null:
		return o
	for k in Data.UNIT_KEYS:
		o[k] = maxi(0, int(f.get(k, 0)) if f.get(k) != null else 0)
	return o


## Battaglia vera (BattleSim headless, IA contro IA): stesse regole della battaglia comandata.
static func _resolve_tactical(att_forces: Dictionary, def_forces: Dictionary, mods_a, mods_d, ca: Dictionary, cd: Dictionary, rng) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var A := _iforces(att_forces)
	var Df := _iforces(def_forces)
	var ter := String(cd.get("ter", ca.get("ter", "pianura")))
	var setup := {
		"terrIdx": int(cd.get("terr", -1)), "terrain": ter, "terrName": "", "sea": bool(ca.get("sea", false)),
		"seed": int(rng.randi() & 0x3fffffff) + 1,
		"att": {"player": -1, "name": "Attaccante", "forces": A, "mods": mods_a if mods_a != null else default_mods(), "human": false,
			"faction": int(ca.get("faction", -1)), "air": bool(ca.get("air", false)), "naval": int(ca.get("naval", 0))},
		"def": {"player": -1, "name": "Difensore", "forces": Df, "mods": mods_d if mods_d != null else default_mods(), "human": false,
			"bunkers": int(cd.get("bunkers", 0)), "fort": cd.get("fort", {}), "faction": int(cd.get("faction", -1)),
			"air": bool(cd.get("air", false)), "naval": int(cd.get("naval", 0))},
		"support": {"att": int(ca.get("support", 0)), "def": int(cd.get("support", 0))},
		"buildings": cd.get("buildings", []), "hq": bool(cd.get("hq", false)),
	}
	# omogeneità §2: rinforzi dai territori vicini (ctx.reinf = {forces, dir, t})
	for sk in ["att", "def"]:
		var c: Dictionary = ca if sk == "att" else cd
		if c.get("reinf") is Dictionary and Data.total_units(_iforces(c["reinf"].get("forces"))) > 0:
			setup[sk]["reinf"] = c["reinf"]
	var b := BattleSim.new(setup)
	var r: Dictionary = b.run_headless()
	var secs := b.time
	b.dispose()
	var att: Dictionary = _iforces(r.get("att"))
	var def: Dictionary = _iforces(r.get("def"))
	var winner := "att" if r.get("winner") == "att" and Data.total_units(att) > 0 else "def"
	if winner == "att":
		def = Data.empty_forces()
	elif Data.total_units(def) == 0:
		# il difensore "vince" per stallo ma senza superstiti mobili: resta almeno un'unità (come _fix_winner)
		for k in Data.UNIT_KEYS:
			if Df[k] > 0:
				def[k] = 1
				break
	var att_losses := Data.empty_forces()
	var def_losses := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		att[k] = mini(att[k], A[k])
		def[k] = mini(def[k], Df[k])
		att_losses[k] = A[k] - att[k]
		def_losses[k] = Df[k] - def[k]
	var ms := int((Time.get_ticks_usec() - t0) / 1000)
	stats["tactical"] += 1
	stats["tactical_ms"] += ms
	stats["tactical_max_ms"] = maxi(int(stats["tactical_max_ms"]), ms)
	return {"att": att, "def": def, "winner": winner, "rounds": maxi(1, int(secs)), "attLosses": att_losses, "defLosses": def_losses,
		"engine": "tactical", "ms": ms, "time": secs, "attReinf": _iforces(r.get("attReinf")), "defReinf": _iforces(r.get("defReinf")),
		"objectives": r.get("objectives", [0, 0]), "why": String(r.get("why", "")), "retreated": bool(r.get("retreated", false))}


static func predict_battle(att_forces: Dictionary, def_forces: Dictionary, mods_a = null, mods_d = null) -> Dictionary:
	var mA: Dictionary = mods_a if mods_a != null else default_mods()
	var mD: Dictionary = mods_d if mods_d != null else default_mods()
	var s := _simulate(att_forces, def_forces, mA, mD, null, false)
	var a0 := _hp_total(_fclone(att_forces), mA)
	var d0 := _hp_total(_fclone(def_forces), mD)
	var att_left: float = _hp_total(s["A"], mA) / a0 if a0 > 0 else 0.0
	var def_left := 0.0
	if d0 > 0:
		def_left = 0.0 if s["winner"] == "att" else _hp_total(s["D"], mD) / d0
	return {"winner": s["winner"], "attLeft": att_left, "defLeft": def_left}


## Stima rapida: fanteria = 1
static func force_power(forces) -> float:
	if forces == null:
		return 0.0
	var s := 0.0
	for k in Data.UNIT_KEYS:
		var c: float = float(forces.get(k, 0)) if forces.get(k) != null else 0.0
		if c != 0:
			s += c * sqrt(Data.UNITS[k]["hp"] * Data.UNITS[k]["atk"] / 20.0)
	return s
