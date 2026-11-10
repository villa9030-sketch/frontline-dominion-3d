class_name Game
extends RefCounted
## FRONTLINE DOMINION 3D — stato, economia, turni, rifornimenti, carte, tecnologia, battaglie e vittoria.
## FASE 6: tabellone strategico A TURNI (stile Risiko): rifornimento → attacco (max 1) → spostamento (max 1) → fine turno.
## Le battaglie 3D restano in tempo reale. Nessun accesso a nodi/scene (gira headless). Contratto: SPEC3D.md «Fase 6 — turni».

signal event(name: String, data: Dictionary)

## QG di partenza per fazione. FASE 4: l'AAN parte dalle Grandi Pianure (non più dall'angolo atlantico, dietro un solo
## fronte): come FO e UL ha il QG in prima linea e può contendere subito il Messico neutrale.
const START_HQ_BY_FACTION = ["pianure", "russia", "ausest", "istmo"]
const QUEUE_MAX := 20           # unità massime in coda per territorio
const MIN_TRAVEL := 1.5         # s
const EFFECT_DUR = {"explosion": 1.6, "missile": 1.8, "capture": 1.8, "battle": 2.0}
const OBJECTIVE_POOL = [
	{"type": "continents", "conts": ["NA", "AF"]},
	{"type": "continents", "conts": ["AS", "SA"]},
	{"type": "continents", "conts": ["EU", "SA"]},
	{"type": "continents", "conts": ["AS", "OC"]},
	{"type": "continents", "conts": ["NA", "OC"]},
	{"type": "count", "count": 24},
	{"type": "eliminate"},
]
const AI_PATH := "res://scripts/core/ai.gd"

var opts: Dictionary
var mode: String
var rng := RandomNumberGenerator.new()
var time := 0.0                 # FASE 6: solo orologio di animazione (s reali)
var speed := 1.0                # moltiplica il ritmo delle azioni IA
var paused := false             # ferma il ritmo delle IA e le animazioni
## FASE 6 — stato dei turni
var round := 1
var current := 0
var phase := "rifornimento"     # "rifornimento" | "attacco" | "spostamento"
var attack_used := false
var move_used := false
var truce_rounds: int = int(Data.TURN_RULES["truce_rounds"])
var round_limit := 0            # 0 = nessuno (impostato a ROUND_CAP nelle partite normali)
var ai_step_delay := 0.8        # s reali tra due azioni IA (0 = istantaneo)
var turn_count := 0             # turni giocati in tutto
var _ai_timer := 0.0
var _turn_steps := 0            # azioni dell'IA nel turno corrente (protezione)
var _turn_started := false
var over = null                 # null | {winner, reason}
var events: Array = []          # {time, text, type, player}
var effects: Array = []         # {type, x, y, born, dur, [x2, y2]}
var divisions: Array = []       # FASE 6: solo record di animazione (move/attack), nessun effetto di gioco
var pending_battle = null       # null | {id, attacker, defender, terr, from, forces, sea, vet, xp, human_side, [manual]}
var ais: Array = []
var ai_errors := 0
var players: Array = []
var human_idx := -1
var terr: Array = []
var deck: Array = []
var discard: Array = []
var _next_div := 1
var _next_battle := 1
var _supply_dirty := true
var _setup_taken = null
var _manual = null
## Cronologia per i grafici: un'istantanea per round
## {t, terr:[n per giocatore], power:[...], units:[...], income:[...]}
var history: Array = []
# eventi di contesto ("headline")
var _cont_hold := {}            # continente -> proprietario annunciato (-1 nessuno)
var _milestones := {}           # "p:soglia" -> true
var _battle_times: Array = []   # [time, continente] delle battaglie recenti
var _hot_at := {}               # continente -> tempo dell'ultimo "fronte caldo"
var _ctx_dirty := false

const SAVE_VERSION := 3          # v3: logoramento (terr.worn), carte inganno (decoy/silence/intel), nebbia a tre modalità
const SAVE_MIN_VERSION := 2      # i salvataggi v2 (turni) si caricano con migrazione
const ROUND_CAP := 120          # partite normali: al limite vince chi controlla più territori
const REINFORCE_DIV := 2.0     # rinforzi per turno = territori / 2 (min 4) + bonus dei continenti
const ANIM_DUR := 1.2           # s reali di animazione di uno spostamento/attacco
const AI_MAX_STEPS := 40        # azioni massime di un turno IA (poi fine turno forzata)
const HOT_WINDOW := 2           # round: finestra per il "fronte caldo"
const HOT_BATTLES := 4          # battaglie nella finestra
const HOT_COOLDOWN := 5         # round tra due annunci per lo stesso continente
static var last_load_error := ""
## Fortificazioni nella risoluzione con la formula (per livello)
const FORT_TRENCH_HP := 0.06        # +hp di fanteria/artiglieria/contraerea del difensore
const FORT_MINES_ATK := 0.03        # −attacco dell'attaccante
const FORT_BUNKER_ATK := 0.04       # +attacco del difensore
const MILESTONES := [0.25, 0.4, 0.5]
# FASE 3 — veterani
const VET_XP := [0, 2, 4, 7]        # vittorie del presidio per 1, 2, 3 stelle
const VET_MAX := 3
const VET_BONUS := 0.06             # +6% attacco per stella (in Combat.combat_mods)
# FASE 3 — diplomazia
const PACT_DUR: int = Data.TURN_RULES["pact_rounds"]   # round
const PACT_CD: int = Data.TURN_RULES["pact_cd"]         # round di ricarica per coppia dopo una proposta (o la fine di un patto)
const PACT_OFFER_DUR := 1           # round di validità di un'offerta dell'IA al giocatore
const PACT_AGGR_WINDOW := 1         # round: niente patto se il proponente ha attaccato l'IA da poco
const RADAR_FACTION := "aan"        # fazione con il radar (+1 anello di visibilità)

## Nebbia di guerra (opts.fog)
var fog := false                # true con nebbia leggera o totale (compatibilità)
var fog_mode := "none"          # "none" | "light" | "full" (docs/omogeneita.md §5)
var intel := {}                 # "p:t" -> round fino al quale p vede esattamente t (ricognizione)
var _vis_cache := {}            # viewer -> PackedByteArray
## Patti di non aggressione: [{a, b, until}] e offerte delle IA al giocatore: [{from, to, until}]
var pacts: Array = []
var pact_offers: Array = []
var _pact_cd := {}              # "a:b" (a<b) -> round da cui si può riproporre
var _aggr := {}                 # "a>b" -> round dell'ultimo attacco di a contro b

## FASE 4 — scenari (opts.scenario = id di Scenarios.LIST). Regole effettive della partita:
var scenario = null             # null | voce di Scenarios.LIST (sola lettura)
var victory_share: float = float(Data.ECON["victoryShare"])   # quota del mondo per vincere
var time_limit := 0.0           # compatibilità: = round_limit dello scenario (in round)
var siege_idx := -1             # giocatore assediato (regola siege) o -1
var hold_terrs: Array = []      # territori chiave (regola hold)
var scenario_targets: Array = []  # indici dei territori obiettivo da segnalare sul tabellone (chiave o QG dell'assediato)
var hold_need := 0
var hold_rounds := 0            # round consecutivi da tenere
var hold_secs := 0.0            # compatibilità (= hold_rounds)
var _scen_income: Array = []    # moltiplicatore di reddito per giocatore
var _siege_by := -1             # chi ha eliminato l'assediato
var _hold_owner := -1           # chi tiene i territori chiave e da quale round
var _hold_since := 0
const SCENARIOS_PATH := "res://scripts/core/scenarios.gd"


func _init(o: Dictionary = {}) -> void:
	var pl = o.get("players")
	if pl == null or pl.is_empty():
		pl = [{"faction": 0, "human": true, "difficulty": "veterano"}, {"faction": 1, "human": false, "difficulty": "veterano"}]
	var seed_v: int
	if o.get("seed") != null:
		seed_v = int(o["seed"]) & 0xffffffff
	else:
		seed_v = int(Time.get_ticks_usec() + Time.get_unix_time_from_system() * 1000.0) & 0x7fffffff
	var pl_clean: Array = []
	for po in pl:
		var pd: Dictionary = po if po is Dictionary else {}
		pl_clean.append({"faction": int(_num(pd.get("faction", 0))), "human": bool(pd.get("human", false)),
			"difficulty": str(pd.get("difficulty", "veterano"))})
	pl = pl_clean
	# scenario
	var scen_id := str(o.get("scenario", "")) if o.get("scenario") != null else ""
	if scen_id != "" and ResourceLoader.exists(SCENARIOS_PATH):
		var S = load(SCENARIOS_PATH).find(scen_id)
		if S is Dictionary and not S.is_empty():
			scenario = S
	if scenario == null:
		scen_id = ""
	else:
		# numero di giocatori dello scenario: prima gli umani, poi le IA nell'ordine dato
		var want: int = int(scenario.get("opp", pl.size() - 1)) + 1
		if pl.size() > want:
			var keep: Array = pl.filter(func(x): return x["human"])
			for x in pl:
				if not x["human"] and keep.size() < want:
					keep.append(x)
			pl = keep.slice(0, want)
	opts = {
		"players": pl,
		"mode": "obiettivo" if o.get("mode") == "obiettivo" else "conquista",
		"distribution": "casuale" if o.get("distribution") == "casuale" else "regionale",
		"seed": seed_v,
		"ask_defense": bool(o.get("ask_defense", true)),
		"auto_battles": bool(o.get("auto_battles", false)),
		"fog": bool(o.get("fog", false)),
		"fog_mode": "",
		"scenario": scen_id,
		"ai_step_delay": maxf(0.0, _num(o.get("ai_step_delay", 0.8))),
	}
	# nebbia: opts.fog_mode ("none"/"light"/"full") ha la precedenza; il vecchio bool fog = totale/nessuna
	var fm := str(o.get("fog_mode", "")) if o.get("fog_mode") != null else ""
	if not Data.FOG_MODES.has(fm):
		fm = "full" if bool(o.get("fog", false)) else "none"
	opts["fog_mode"] = fm
	opts["fog"] = fm != "none"
	mode = opts["mode"]
	ai_step_delay = float(opts["ai_step_delay"])
	fog_mode = fm
	fog = fm != "none"
	rng.seed = seed_v

	for i in pl.size():
		var po: Dictionary = pl[i]
		var fi: int = int(po.get("faction", 0))
		var fac: Dictionary = Data.FACTIONS[fi]
		var diff: String = str(po.get("difficulty", "veterano"))
		if not Data.DIFFICULTY.has(diff):
			diff = "veterano"
		var res := {"money": 0.0, "oil": 0.0, "steel": 0.0, "manpower": 0.0}
		for k in Data.ECON["startRes"]:
			res[k] = float(Data.ECON["startRes"][k])
		players.append({
			"idx": i, "faction": fi, "fac": fac, "name": fac["name"], "color": Color(fac["color"]), "human": bool(po.get("human", false)),
			"difficulty": diff,
			"res": res,
			"rates": {"money": 0.0, "oil": 0.0, "steel": 0.0, "manpower": 0.0},
			"tech": 1, "research": null, "hq": -1, "alive": true,
			"cards": [], "card_cd": 0.0, "sets_traded": 0,
			"pool": Data.empty_forces(), "next_reinforce": 0.0,
			"objective": null, "low_oil": false,
			"stats": {"conquered": 0, "lost": 0, "battlesWon": 0, "battlesLost": 0, "killed": 0, "unitsLost": 0,
				"built": 0, "researched": 0, "cardsPlayed": 0, "maxTerr": 0, "eliminatedAt": -1.0},
			"market": {"oil": 1.0, "steel": 1.0, "manpower": 1.0},
			"militia_t": 0.0, "upkeep": 0.0,
		})
	for p in players:
		if p["human"]:
			human_idx = p["idx"]
			break

	for i in Data.TERRITORIES.size():
		terr.append({
			"idx": i, "owner": -1, "forces": Data.empty_forces(), "buildings": [], "building": null, "queue": [],
			"sabotage": 0.0, "unrest": 0.0, "regroup": 0.0, "supplied": true, "garrison_t": 0.0,
			"vet": 0, "xp": 0, "fresh": 0, "fort": {"trench": 0, "mines": 0, "bunker": 0},
			"worn": 0, "decoy": 0, "silence": 0,
		})

	var R: Dictionary = scenario.get("rules", {}) if scenario != null else {}
	truce_rounds = maxi(0, int(R.get("truce_rounds", o.get("truce_rounds", truce_rounds))))
	victory_share = float(R.get("victory_share", victory_share))
	round_limit = int(scenario.get("round_limit", 0)) if scenario != null else 0
	if round_limit <= 0:
		round_limit = int(Data.TURN_RULES["round_cap"])
	time_limit = float(round_limit) if scenario != null else 0.0
	_scen_income.resize(players.size())
	_scen_income.fill(1.0)
	if opts["distribution"] == "casuale":
		_setup_random()
	else:
		_setup_regional()
	if scenario != null:
		_apply_scenario(R)

	# Mazzo carte
	var types := ["inf", "tank", "air"]
	for i in Data.TERRITORIES.size():
		deck.append({"type": types[i % 3]})
	deck.append({"type": "jolly"})
	deck.append({"type": "jolly"})
	_shuffle(deck)
	discard = []

	if scenario != null and _scenario_objectives(R):
		pass   # obiettivi dello scenario (assedio, territori chiave)
	elif mode == "obiettivo":
		_assign_objectives()

	_recompute_supply()
	_compute_rates()
	_update_context(true)
	_snapshot()

	ais.resize(players.size())
	var ai_script = o.get("ai_script")   # facoltativo (test): Script con _init(game, idx)
	if ai_script == null and ResourceLoader.exists(AI_PATH):
		ai_script = load(AI_PATH)
	if ai_script != null and ai_script is Script and ai_script.can_instantiate():
		for i in players.size():
			if not players[i]["human"]:
				ais[i] = ai_script.new(self, i)
	if scenario != null:
		add_log("Scenario «" + str(scenario["name"]) + "»: " + str(scenario.get("objective", "")), "info", null)
	else:
		add_log("La guerra ha inizio. Conquista il " + str(roundi(victory_share * 100)) + "% del mondo!", "info", null)
	if human_idx >= 0:
		var hp: Dictionary = players[human_idx]
		if hp["objective"] != null and not hp["objective"].get("scenario", false):
			add_log("Obiettivo segreto: " + hp["objective"]["text"], "info", human_idx)
		elif hp["objective"] != null:
			add_log("Operazione «" + str(scenario["name"]) + "»: " + hp["objective"]["text"], "info", human_idx)
	# primo turno: il primo giocatore (di norma l'umano, posto 0)
	current = 0
	round = 1
	if bool(o.get("_no_start", false)):
		return   # deserialize: lo stato dei turni arriva dal salvataggio
	_begin_turn(current)


## Rompe il ciclo di riferimenti Game <-> IA (RefCounted): chiamare quando si abbandona la partita.
func dispose() -> void:
	ais.clear()
	_manual = null
	pending_battle = null


# ------------------------------------------------------------------ utilità
func _rand() -> float:
	return rng.randf()


func _shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(floor(_rand() * (i + 1)))
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr


static func _is_wrap(a: int, b: int) -> bool:
	var A: String = Data.TERRITORIES[a]["id"]
	var B: String = Data.TERRITORIES[b]["id"]
	for l in Data.WRAP_LINKS:
		if (l[0] == A and l[1] == B) or (l[0] == B and l[1] == A):
			return true
	return false


static func _num(v) -> float:
	if v == null:
		return 0.0
	if v is int or v is float:
		return float(v)
	if v is String and v.is_valid_float():
		return v.to_float()
	if v is bool:
		return 1.0 if v else 0.0
	return 0.0


static func _sanitize_forces(f, cap = null) -> Dictionary:
	var o := Data.empty_forces()
	if f == null or not (f is Dictionary):
		return o
	for k in Data.UNIT_KEYS:
		var x := _num(f.get(k))
		var v := 0 if is_nan(x) or is_inf(x) else int(floor(x))
		if v < 0:
			v = 0
		if cap != null:
			v = mini(v, int(cap.get(k, 0)))
		o[k] = v
	return o


static func forces_text(f: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in Data.UNIT_KEYS:
		if int(f.get(k, 0)) > 0:
			parts.append(str(f[k]) + " " + Data.UNITS[k]["short"])
	return ", ".join(parts) if parts.size() > 0 else "nessuna"


static func _ok(reason: String = "") -> Dictionary:
	return {"ok": true, "reason": reason}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _fac_mod(p: int, key: String):
	return players[p]["fac"]["mods"].get(key)


# ------------------------------------------------------------------ setup
func _setup_regional() -> void:
	var n := players.size()
	var taken: Array = []
	taken.resize(Data.TERRITORIES.size())
	taken.fill(false)
	var owned: Array = []
	for i in n:
		owned.append([])
	_setup_taken = taken
	# scenario: partenze fisse per fazione (gli altri scelgono attorno)
	var fixed := {}
	for i in n:
		var st := _scen_fac(players[i]["faction"])
		if st.get("start") is Array and not st["start"].is_empty():
			var list: Array = []
			for id in st["start"]:
				var t: int = int(Data.TERR_INDEX.get(str(id), -1))
				if t >= 0 and not taken[t]:
					taken[t] = true
					list.append(t)
			if list.is_empty():
				continue
			fixed[i] = true
			owned[i] = list
			var hq_id := str(st.get("hq", ""))
			players[i]["hq"] = int(Data.TERR_INDEX[hq_id]) if Data.TERR_INDEX.has(hq_id) and list.has(int(Data.TERR_INDEX[hq_id])) else list[0]
	for i in n:
		if fixed.has(i):
			continue
		var p: Dictionary = players[i]
		var hq: int = Data.TERR_INDEX[START_HQ_BY_FACTION[p["faction"]]]
		if taken[hq]:
			hq = _nearest_free(hq, taken)
		p["hq"] = hq
		taken[hq] = true
		owned[i].append(hq)
	for r in 4:
		for i in n:
			if fixed.has(i):
				continue
			# chi completa l'Oceania (troppo piccola per vietarla) ha già il bonus del continente: niente altri territori
			# (prima la CP saltava l'Indonesia neutrale e partiva anche in Indocina e Cina, isolate ma già in Asia)
			var full := false
			for ck in Data.CONT_KEYS:
				var all_in := true
				for t in Data.CONT_TERR[ck]:
					if not owned[i].has(t):
						all_in = false
						break
				if all_in:
					full = true
			if full:
				continue
			# nessuno parte con un continente completo: escludi il territorio che lo completerebbe
			var block: Array = taken.duplicate()
			for ck in Data.CONT_KEYS:
				var rest: Array = []
				for t in Data.CONT_TERR[ck]:
					if not owned[i].has(t):
						rest.append(t)
				if rest.size() == 1 and Data.CONT_TERR[ck].size() > 4:   # l'Oceania (4) è troppo piccola per vietarla
					block[rest[0]] = true
			# niente partenze nel continente del QG di un altro giocatore né confinanti con esso (bilanciamento FASE 4):
			# chi prendeva il Messico (UL o AAN, secondo l'ordine dei giocatori) schiacciava l'altro, e la partita era decisa
			# dal sorteggio dei posti. Il Messico resta neutrale, cuscinetto tra le due Americhe.
			var block2: Array = block.duplicate()
			for j in n:
				var hj: int = players[j]["hq"]
				if j != i and hj >= 0 and Data.TERRITORIES[hj]["c"] != Data.TERRITORIES[players[i]["hq"]]["c"]:
					for t in Data.CONT_TERR[Data.TERRITORIES[hj]["c"]]:
						block2[t] = true
				if j != i and hj >= 0:
					for t in Data.TERRITORIES[hj]["adj"]:   # né a ridosso del QG altrui: resta un cuscinetto neutrale
						block2[t] = true
			# prima via terra, poi oltremare (sempre a contatto con i propri territori)
			var c := _nearest_free(players[i]["hq"], block2, "", owned[i])
			if c < 0 and owned[i].size() < 4:
				c = _nearest_free(players[i]["hq"], block, "", owned[i])
				if c < 0:
					c = _nearest_free(players[i]["hq"], block, "", null)   # nessun vicino libero: anche staccato
			if c >= 0:
				taken[c] = true
				owned[i].append(c)
	for i in owned.size():
		for t in owned[i]:
			var tr: Dictionary = terr[t]
			tr["owner"] = i
			if t == players[i]["hq"]:
				tr["forces"]["inf"] = 8
				tr["forces"]["tank"] = 4
				tr["forces"]["art"] = 2
			else:
				tr["forces"]["inf"] = 3
				tr["forces"]["tank"] = 1
	for tr in terr:
		if tr["owner"] == -1:
			tr["forces"]["inf"] = 4 + int(floor(_rand() * 5))
			tr["forces"]["tank"] = int(floor(_rand() * 3))
			if _rand() < 0.35:
				tr["forces"]["art"] = 1 + int(floor(_rand() * 2))


## any_sea: "" (prima terra, poi mare), "land", "sea"
func _nearest_free(start: int, taken: Array, any_sea: String = "", mine = null) -> int:
	# prima solo via terra (niente teste di ponte oltremare all'inizio), poi anche via mare
	if any_sea == "":
		var l := _nearest_free(start, taken, "land", mine)
		if l >= 0:
			return l
		return _nearest_free(start, taken, "sea", mine)
	# BFS per distanza in salti; a parità, distanza euclidea
	var dist: Array = []
	dist.resize(Data.TERRITORIES.size())
	dist.fill(-1)
	dist[start] = 0
	var frontier: Array = [start]
	while frontier.size() > 0:
		var next: Array = []
		for a in frontier:
			if mine != null and a != start and not mine.has(a):
				continue   # partenze contigue: si allarga solo dai propri territori (FASE 4: la CP saltava l'Indonesia
				           # neutrale e partiva con Cina e Indocina isolate, senza rifornimenti, a ridosso della FO)
			for b in Data.TERRITORIES[a]["adj"]:
				if dist[b] < 0 and not (any_sea == "land" and Data.TERRITORIES[a]["sea"].has(b)):
					dist[b] = dist[a] + 1
					next.append(b)
		var free: Array = []
		for b in next:
			if not taken[b]:
				free.append(b)
		if free.size() > 0:
			var S: Dictionary = Data.TERRITORIES[start]
			var best: int = free[0]
			var bd := INF
			for x in free:   # come sort stabile + [0]: il primo con distanza minima
				var dd := Vector2(Data.TERRITORIES[x]["x"] - S["x"], Data.TERRITORIES[x]["y"] - S["y"]).length()
				if dd < bd:
					bd = dd
					best = x
			return best
		frontier = next
	return -1


func _setup_random() -> void:
	var n := players.size()
	var slots := 3 if n == 2 else n
	var order: Array = []
	for t in Data.TERRITORIES:
		order.append(t["idx"])
	_shuffle(order)
	for k in order.size():
		var t: int = order[k]
		var s := k % slots
		var tr: Dictionary = terr[t]
		tr["owner"] = s if s < n else -1
		tr["forces"]["inf"] = 3
	for i in n:
		var p: Dictionary = players[i]
		var mine: Array = []
		for t in terr:
			if t["owner"] == i:
				mine.append(t)
		var h: Dictionary = mine[int(floor(_rand() * mine.size()))]
		p["hq"] = h["idx"]
		h["forces"]["inf"] += 5
		h["forces"]["tank"] += 3


# ------------------------------------------------------------------ scenari (FASE 4)
## Regole dello scenario per una fazione (rules.fac[id]) o {}
func _scen_fac(fi: int) -> Dictionary:
	if scenario == null or fi < 0 or fi >= Data.FACTIONS.size():
		return {}
	var F = scenario.get("rules", {}).get("fac", {})
	var x = F.get(Data.FACTIONS[fi]["id"]) if F is Dictionary else null
	return x if x is Dictionary else {}


static func _mul_forces(f: Dictionary, m: float) -> void:
	if m == 1.0:
		return
	for k in Data.UNIT_KEYS:
		if int(f[k]) > 0:
			f[k] = maxi(1, roundi(f[k] * m))


## Risorse, forze, redditi, assedio e territori chiave dello scenario (dopo la distribuzione dei territori)
func _apply_scenario(R: Dictionary) -> void:
	for P in players:
		var F := _scen_fac(P["faction"])
		var rm: float = float(R.get("res_mul", 1.0)) * float(F.get("res_mul", 1.0))
		for k in Data.RES_KEYS:
			P["res"][k] = float(P["res"][k]) * rm
		_scen_income[P["idx"]] = float(F.get("income_mul", 1.0))
	for tr in terr:
		if tr["owner"] >= 0:
			_mul_forces(tr["forces"], float(R.get("forces_mul", 1.0)) * float(_scen_fac(players[tr["owner"]]["faction"]).get("forces_mul", 1.0)))
		else:
			_mul_forces(tr["forces"], float(R.get("neutral_mul", 1.0)))
	var sg = R.get("siege")
	if sg is Dictionary:
		for P in players:
			if P["faction"] == int(sg.get("faction", -1)):
				siege_idx = P["idx"]
				break
		if siege_idx >= 0 and bool(sg.get("pacts", false)):
			# gli assedianti sono alleati fino alla fine della partita
			var until: int = round_limit + 10
			for a in players:
				for b in players:
					if a["idx"] < b["idx"] and a["idx"] != siege_idx and b["idx"] != siege_idx:
						pacts.append({"a": a["idx"], "b": b["idx"], "until": until})
	var hd = R.get("hold")
	if hd is Dictionary:
		for id in hd.get("terrs", []):
			if Data.TERR_INDEX.has(str(id)):
				hold_terrs.append(int(Data.TERR_INDEX[str(id)]))
		hold_need = clampi(int(hd.get("need", hold_terrs.size())), 1, maxi(1, hold_terrs.size()))
		hold_rounds = maxi(1, int(hd.get("rounds", 2)))
		hold_secs = float(hold_rounds)
	_update_targets()


## Territori obiettivo per il tabellone: i territori chiave, oppure il QG attuale dell'assediato
func _update_targets() -> void:
	if not hold_terrs.is_empty():
		scenario_targets = hold_terrs.duplicate()
	elif siege_idx >= 0:
		var h: int = players[siege_idx]["hq"]
		scenario_targets = [h] if h >= 0 and players[siege_idx]["alive"] else []


## Obiettivi dello scenario (li usa anche l'IA). true se ne ha assegnati.
func _scenario_objectives(_R: Dictionary) -> bool:
	if siege_idx >= 0:
		var S: Dictionary = players[siege_idx]
		var col := _siege_collapse()
		for P in players:
			if P["idx"] == siege_idx:
				P["objective"] = {"type": "survive", "scenario": true,
					"text": ("Resisti fino alla fine del round " + str(round_limit)) if round_limit > 0 else "Resisti all'assedio"}
			else:
				P["objective"] = {"type": "eliminate", "target": siege_idx, "scenario": true,
					"text": ("Riduci " + S["fac"]["short"] + " a " + str(col) + " territori") if col > 0 else ("Elimina " + S["name"])}
		return true
	if not hold_terrs.is_empty():
		for P in players:
			P["objective"] = {"type": "hold", "terrs": hold_terrs.duplicate(), "need": hold_need, "scenario": true,
				"text": "Tieni " + str(hold_need) + " territori chiave su " + str(hold_terrs.size()) + " per " + str(hold_rounds) + " round"}
		return true
	return false


func _siege_rule() -> Dictionary:
	if scenario == null:
		return {}
	var sg = scenario.get("rules", {}).get("siege")
	return sg if sg is Dictionary else {}


func _siege_collapse() -> int:
	return int(_siege_rule().get("collapse", 0))


func _siege_pacts() -> bool:
	return bool(_siege_rule().get("pacts", false))


## Territori chiave posseduti da p
func hold_count(p: int) -> int:
	var n := 0
	for t in hold_terrs:
		if terr[t]["owner"] == p:
			n += 1
	return n


## Stato dello scenario per il pannello dell'operazione ({} in una partita normale):
## {text, progress, time_left (s, -1 senza limite), [hold_owner, hold_left]}
func scenario_status(viewer: int = -1) -> Dictionary:
	if scenario == null:
		return {}
	var rl := rounds_left()
	var o := {"text": str(scenario.get("objective", "")), "progress": "", "rounds_left": rl, "time_left": rl, "round": round, "round_limit": round_limit}
	var v := viewer if viewer >= 0 and viewer < players.size() else -1
	if siege_idx >= 0:
		var S: Dictionary = players[siege_idx]
		var n := territories_of(siege_idx).size()
		if v >= 0 and players[v]["objective"] != null:
			o["text"] = str(players[v]["objective"]["text"])
		o["progress"] = S["fac"]["short"] + ": " + str(n) + (" territorio" if n == 1 else " territori")
	elif not hold_terrs.is_empty():
		var parts: PackedStringArray = []
		for P in players:
			if P["alive"]:
				parts.append(P["fac"]["short"] + " " + str(hold_count(P["idx"])) + "/" + str(hold_terrs.size()))
		o["progress"] = " · ".join(parts)
		o["hold_owner"] = _hold_owner
		o["hold_left"] = hold_left() if _hold_owner >= 0 else -1
		if _hold_owner >= 0:
			o["progress"] += " — " + _pname(_hold_owner) + " vince tra " + str(o["hold_left"]) + " round"
	else:
		var need := int(ceil(victory_share * terr.size() - 1e-9))
		if v >= 0:
			o["progress"] = "Territori: " + str(territories_of(v).size()) + "/" + str(need)
	return o


## Vittorie dello scenario: [winner, reason] oppure [] se nessuna
func _scenario_victory(counts: Array) -> Array:
	if siege_idx >= 0:
		var S: Dictionary = players[siege_idx]
		var col := _siege_collapse()
		if not S["alive"] or (col > 0 and counts[siege_idx] <= col):
			var w := _siege_by
			if S["alive"] or w < 0 or not players[w]["alive"]:
				w = _best_of(counts, siege_idx)
			if _siege_pacts() and human_idx >= 0 and human_idx != siege_idx and players[human_idx]["alive"]:
				w = human_idx   # vittoria di squadra: l'alleanza vince insieme
			var why: String = (S["fac"]["short"] + " è stata eliminata") if not S["alive"] else (S["fac"]["short"] + " è crollata")
			return [w, ("L'alleanza ha vinto: " + why) if _siege_pacts() else why]
	if not hold_terrs.is_empty():
		var best := -1
		for P in players:
			if P["alive"] and hold_count(P["idx"]) >= hold_need:
				best = P["idx"]
				break
		if best != _hold_owner:
			_hold_owner = best
			_hold_since = round
			if best >= 0:
				_headline(_pname(best) + " controlla " + str(hold_count(best)) + " territori chiave: vince tra " + str(hold_rounds) + " round se li tiene!")
		if _hold_owner >= 0 and round - _hold_since >= hold_rounds:
			return [_hold_owner, "Ha tenuto " + str(hold_need) + " territori chiave per " + str(hold_rounds) + " round"]
	if round_limit > 0 and round > round_limit:
		var tw := str(scenario.get("rules", {}).get("time_win", "territories"))
		if tw == "siege" and siege_idx >= 0 and players[siege_idx]["alive"]:
			return [siege_idx, players[siege_idx]["fac"]["short"] + " ha resistito fino allo scadere"]
		if tw == "hold" and not hold_terrs.is_empty():
			var bw := -1
			var bn := -1
			for P in players:
				if not P["alive"]:
					continue
				var key: int = hold_count(P["idx"]) * 100 + int(counts[P["idx"]])
				if key > bn:
					bn = key
					bw = P["idx"]
			return [bw, "Round esauriti: controlla più territori chiave"]
		return [_best_of(counts, -1), "Round esauriti: controlla più territori"]
	return []


## Giocatore vivo con più territori (escluso skip); a parità la potenza militare
func _best_of(counts: Array, skip: int) -> int:
	var best := -1
	var bk := -1.0
	for P in players:
		var i: int = P["idx"]
		if i == skip or not P["alive"]:
			continue
		var pw := 0.0
		for tr in terr:
			if tr["owner"] == i:
				pw += Combat.force_power(tr["forces"])
		var k: float = float(counts[i]) * 100000.0 + pw
		if k > bk:
			bk = k
			best = i
	return best


func _assign_objectives() -> void:
	var pool: Array = _shuffle(OBJECTIVE_POOL.duplicate(true))
	for i in players.size():
		var p: Dictionary = players[i]
		var tpl: Dictionary = pool[i % pool.size()]
		var o := {"type": tpl["type"]}
		if tpl["type"] == "continents":
			o["conts"] = tpl["conts"].duplicate()
			var names: PackedStringArray = []
			for c in o["conts"]:
				names.append(CONT_ART[c][0] + Data.CONTINENTS[c]["name"])   # "il Nord America", "l'Africa"
			o["text"] = "Conquista " + " e ".join(names)
		elif tpl["type"] == "count":
			o["count"] = tpl["count"]
			o["text"] = "Conquista " + str(tpl["count"]) + " territori"
		else:
			var others: Array = []
			for q in players:
				if q["idx"] != i:
					others.append(q)
			var tgt: Dictionary = others[int(floor(_rand() * others.size()))]
			o["target"] = tgt["idx"]
			o["text"] = "Elimina " + tgt["name"]
		p["objective"] = o


# ------------------------------------------------------------------ segnali, log, effetti
func emit_event(name: String, data: Dictionary) -> void:
	event.emit(name, data)


func add_log(text: String, type = "info", player = null) -> void:
	events.append({"time": time, "round": round, "text": text, "type": type if type != null and type != "" else "info", "player": player})
	if events.size() > 200:
		events = events.slice(events.size() - 200)


func add_effect(type: String, x: float, y: float, extra: Dictionary = {}) -> void:
	var e := {"type": type, "x": x, "y": y, "born": time, "dur": EFFECT_DUR.get(type, 1.6)}
	e.merge(extra, true)
	effects.append(e)


func _involves_human(idxs: Array) -> bool:
	return human_idx >= 0 and idxs.has(human_idx)


func _pname(i: int) -> String:
	return players[i]["fac"]["short"] if i >= 0 else "Neutrali"


# ------------------------------------------------------------------ interrogazioni
func territories_of(p: int) -> Array:
	var o: Array = []
	for t in terr:
		if t["owner"] == p:
			o.append(t["idx"])
	return o


func owns_continent(p: int, c: String) -> bool:
	if p < 0:
		return false
	for i in Data.CONT_TERR[c]:
		if terr[i]["owner"] != p:
			return false
	return true


func continent_owner(c: String) -> int:
	var o: int = terr[Data.CONT_TERR[c][0]]["owner"]
	if o < 0:
		return -1
	return o if owns_continent(o, c) else -1


func has_building(t: int, key: String) -> bool:
	var tr: Dictionary = terr[t]
	if tr["buildings"].has(key):
		return true
	if (key == "caserma" or key == "fabbrica") and tr["owner"] >= 0 and players[tr["owner"]]["hq"] == t:
		return true
	return false


func cost_for(p: int, unit_key: String) -> Dictionary:
	var U: Dictionary = Data.UNITS[unit_key]
	var mul := 1.0
	if unit_key == "inf" and _fac_mod(p, "infCost"):
		mul *= float(_fac_mod(p, "infCost"))
	if U["air"] and _fac_mod(p, "airCost"):
		mul *= float(_fac_mod(p, "airCost"))
	if U["air"] and owns_continent(p, "NA"):
		mul *= 0.75
	var c := {}
	for k in U["cost"]:
		c[k] = roundi(U["cost"][k] * mul)
	return c


func can_afford(p: int, cost: Dictionary) -> bool:
	var r: Dictionary = players[p]["res"]
	for k in cost:
		if float(r.get(k, 0.0)) + 1e-9 < float(cost[k]):
			return false
	return true


func _pay(p: int, cost: Dictionary) -> void:
	var r: Dictionary = players[p]["res"]
	for k in cost:
		r[k] -= cost[k]


func unit_available(p: int, unit_key: String) -> bool:
	var P: Dictionary = players[p]
	if not Data.UNITS.has(unit_key):
		return false
	var need: int = Data.UNITS[unit_key]["tech"]
	if unit_key == "drone" and _fac_mod(p, "droneTech"):
		need = int(_fac_mod(p, "droneTech"))
	return P["tech"] >= need


func _valid_player(p: int) -> bool:
	return p >= 0 and p < players.size() and players[p]["alive"]


func _valid_terr(t) -> bool:
	return t != null and (t is int or t is float) and int(t) >= 0 and int(t) < terr.size()


func can_recruit(p: int, t: int, unit_key: String) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	if not Data.UNITS.has(unit_key):
		return _fail("Unità sconosciuta")
	if not _valid_terr(t) or terr[t]["owner"] != p:
		return _fail("Il territorio non è tuo")
	var tr: Dictionary = terr[t]
	if not unit_available(p, unit_key):
		var need: int = Data.UNITS[unit_key]["tech"]
		if unit_key == "drone" and _fac_mod(p, "droneTech"):
			need = int(_fac_mod(p, "droneTech"))
		return {"ok": false, "reason": "Serve Tech %d — ricerca dal pulsante in alto" % need, "lock": "tech"}
	var b: String = Data.UNITS[unit_key]["build"]
	if not has_building(t, b):
		return {"ok": false, "reason": "Serve %s %s in questo territorio" % ["un" if b == "aeroporto" else "una", Data.BUILDINGS[b]["name"]], "lock": "building"}
	if tr["sabotage"] > 0:
		return _fail("Territorio sabotato")
	if tr["queue"].size() >= QUEUE_MAX:
		return _fail("Coda piena")
	var cost := cost_for(p, unit_key)
	if not can_afford(p, cost):
		return _fail("Risorse insufficienti: " + missing_text(p, cost))
	return _ok()


## «mancano 20 acciaio, 5 petrolio» (risorse che mancano per pagare cost)
func missing_text(p: int, cost: Dictionary) -> String:
	var parts: Array = []
	var r: Dictionary = players[p]["res"]
	for k in Data.RES_KEYS:
		var miss := ceili(float(cost.get(k, 0)) - float(r.get(k, 0.0)) - 1e-9)
		if miss > 0:
			parts.append("%d %s" % [miss, String(Data.RES_NAMES[k]).to_lower()])
	return ("manca " if parts.size() == 1 else "mancano ") + ", ".join(parts) if parts.size() else "nessuna"


func slots_used(t: int) -> int:
	return terr[t]["buildings"].size() + (1 if terr[t]["building"] != null else 0)


func slots_max(t: int) -> int:
	var tr: Dictionary = terr[t]
	return Data.HQ_SLOTS if (tr["owner"] >= 0 and players[tr["owner"]]["hq"] == t) else Data.SLOTS


func can_build(p: int, t: int, key: String) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	if not Data.BUILDINGS.has(key):
		return _fail("Edificio sconosciuto")
	if not _valid_terr(t) or terr[t]["owner"] != p:
		return _fail("Il territorio non è tuo")
	var tr: Dictionary = terr[t]
	var B: Dictionary = Data.BUILDINGS[key]
	if has_building(t, key):
		return _fail("Già presente")
	if tr["building"] != null:
		return _fail("Costruzione già in corso")
	if B.get("coastal", false) and not Data.TERRITORIES[t]["coastal"]:
		return _fail("Serve un territorio costiero")
	if tr["sabotage"] > 0:
		return _fail("Territorio sabotato")
	if slots_used(t) >= slots_max(t):
		return _fail("Nessuno slot libero")
	if not can_afford(p, B["cost"]):
		return _fail("Risorse insufficienti: " + missing_text(p, B["cost"]))
	return _ok()


## null se la tecnologia è al massimo; altrimenti {cost, time, level}
func research_cost(p: int):
	var P: Dictionary = players[p]
	if P["tech"] + 1 >= Data.TECH_LEVELS.size():
		return null
	var L = Data.TECH_LEVELS[P["tech"] + 1]
	if L == null:
		return null
	var mr = _fac_mod(p, "research")
	var mul: float = float(mr) if mr else 1.0
	var cost := {}
	for k in L["cost"]:
		cost[k] = roundi(L["cost"][k] * mul)
	var turns: int = maxi(1, ceili(float(Data.TURNS["tech"][P["tech"] + 1]) * mul - 1e-6))
	return {"cost": cost, "time": turns, "turns": turns, "level": P["tech"] + 1}


func can_airlift(p: int, from: int, to: int) -> bool:
	var P: Dictionary = players[p]
	return P["tech"] >= 2 and from != to and terr[from]["owner"] == p and terr[to]["owner"] == p \
		and terr[from]["buildings"].has("aeroporto") and terr[to]["buildings"].has("aeroporto")


## [{idx, sea, airlift}]
func valid_targets(p: int, from: int) -> Array:
	if not _valid_terr(from) or terr[from]["owner"] != p:
		return []
	var tr: Dictionary = terr[from]
	var out: Array = []
	var T: Dictionary = Data.TERRITORIES[from]
	for j in T["adj"]:
		if can_airlift(p, from, j):
			out.append({"idx": j, "sea": false, "airlift": true})
		else:
			out.append({"idx": j, "sea": T["sea"].has(j), "airlift": false})
	if players[p]["tech"] >= 2 and tr["buildings"].has("aeroporto"):
		for t in terr:
			if t["idx"] == from or T["adj"].has(t["idx"]):
				continue
			if can_airlift(p, from, t["idx"]):
				out.append({"idx": t["idx"], "sea": false, "airlift": true})
	return out


func distance(a: int, b: int) -> float:
	var A: Dictionary = Data.TERRITORIES[a]
	var B: Dictionary = Data.TERRITORIES[b]
	var dx: float = absf(A["x"] - B["x"])
	if _is_wrap(a, b):
		dx = minf(dx, Data.MAP_W - dx)
	return Vector2(dx, A["y"] - B["y"]).length()


func travel_time(p: int, from: int, to: int, forces = null) -> float:
	var slow := INF
	var all_air := true
	var any := false
	for k in Data.UNIT_KEYS:
		if forces != null and int(forces.get(k, 0)) > 0:
			any = true
			slow = minf(slow, Data.UNITS[k]["speed"])
			if not Data.UNITS[k]["air"]:
				all_air = false
	if not any:
		slow = 1.0
		all_air = false
	var t: float = distance(from, to) / (Data.ECON["travelSpeed"] * slow)
	var airlift := p >= 0 and can_airlift(p, from, to)
	if airlift:
		t /= Data.ECON["airliftSpeed"]
	elif Data.TERRITORIES[from]["sea"].has(to) and not all_air:
		var fast: bool = terr[from]["buildings"].has("porto") or (p >= 0 and _fac_mod(p, "naval") == true) or (p >= 0 and owns_continent(p, "OC"))
		if not fast:
			t /= Data.ECON["seaSlow"]
	return maxf(MIN_TRAVEL, t)


## null se nascoste (UL in territorio urbano), fuori vista (nebbia di guerra), sotto divisione falsa o silenzio radio.
## La ricognizione (carta) mostra sempre le forze esatte.
func visible_forces(viewer: int, t: int):
	var tr: Dictionary = terr[t]
	if viewer < 0 or tr["owner"] == viewer:
		return Data.clone_forces(tr["forces"])
	if has_intel(viewer, t):
		return Data.clone_forces(tr["forces"])
	if tr["owner"] >= 0 and (int(tr.get("silence", 0)) > 0 or int(tr.get("decoy", 0)) > 0):
		return null
	if fog and not is_visible(viewer, t):
		return null
	if tr["owner"] < 0:
		return Data.clone_forces(tr["forces"])
	if _fac_mod(tr["owner"], "hidden") and Data.TERRITORIES[t]["ter"] == "urbano":
		return null
	return Data.clone_forces(tr["forces"])


## Ricognizione attiva di viewer su t (il territorio o un suo confinante è stato ricognito)
func has_intel(viewer: int, t: int) -> bool:
	if viewer < 0 or intel.is_empty():
		return false
	if int(intel.get("%d:%d" % [viewer, t], -1)) >= round:
		return true
	for j in Data.TERRITORIES[t]["adj"]:
		if int(intel.get("%d:%d" % [viewer, j], -1)) >= round:
			return true
	return false


## Che cosa vede viewer del territorio t: {exact, forces (o null), est (-1 ignoto), lo, hi, why}
## why: "" esatto · "fog" stima della nebbia leggera · "decoy" divisione falsa · "silence" silenzio radio ·
##      "hidden" guerriglia urbana · "unknown" nebbia totale
func forces_view(viewer: int, t: int) -> Dictionary:
	var f = visible_forces(viewer, t)
	var tr: Dictionary = terr[t]
	if f != null:
		var n := Data.total_units(f)
		return {"exact": true, "forces": f, "est": n, "lo": n, "hi": n, "why": ""}
	var out := {"exact": false, "forces": null, "est": -1, "lo": -1, "hi": -1, "why": "unknown"}
	if tr["owner"] >= 0 and int(tr.get("silence", 0)) > 0:
		out["why"] = "silence"
		return out
	var n := Data.total_units(tr["forces"])
	var hidden: bool = tr["owner"] >= 0 and _fac_mod(tr["owner"], "hidden") and Data.TERRITORIES[t]["ter"] == "urbano"
	if tr["owner"] >= 0 and int(tr.get("decoy", 0)) > 0:
		n += int(Data.DECOY_UNITS)
		out["why"] = "decoy"
	elif tr["owner"] < 0:
		out["why"] = "fog"
	elif hidden and (not fog or is_visible(viewer, t)):
		out["why"] = "hidden"   # guerriglia urbana: nulla
		return out
	elif fog_mode == "light":
		out["why"] = "fog"
	else:
		return out   # nebbia totale: ignoto
	# stima "circa lo–hi": ±25%, arrotondata a 5 (mai sotto 0)
	var lo := maxi(0, int(floor(n * 0.75 / 5.0)) * 5)
	var hi := maxi(lo + 5, int(ceil(n * 1.25 / 5.0)) * 5)
	if n == 0:
		lo = 0; hi = 0
	out["est"] = 0 if n == 0 else maxi(5, roundi(n / 5.0) * 5)
	out["lo"] = lo
	out["hi"] = hi
	return out


## Testo della stima per l'interfaccia ("circa 10–15", "sconosciute")
func estimate_text(viewer: int, t: int) -> String:
	var v := forces_view(viewer, t)
	if v["exact"]:
		return str(v["est"])
	if int(v["est"]) < 0:
		return "sconosciute"
	if int(v["lo"]) == int(v["hi"]):
		return "circa %d" % int(v["lo"])
	return "circa %d–%d" % [int(v["lo"]), int(v["hi"])]


# ------------------------------------------------------------------ nebbia di guerra
## true se viewer vede il territorio t: propri + adiacenti ai propri (AAN: +1 anello "radar").
## Senza nebbia (o viewer < 0, o viewer eliminato: spettatore) tutto è visibile.
func is_visible(viewer: int, t: int) -> bool:
	if not fog or viewer < 0 or viewer >= players.size() or not players[viewer]["alive"]:
		return true
	if not _valid_terr(t):
		return false
	var v = _vis_cache.get(viewer)
	if v == null:
		v = _compute_vis(viewer)
		_vis_cache[viewer] = v
	return v[int(t)] == 1


func _compute_vis(viewer: int) -> PackedByteArray:
	var N := terr.size()
	var vis := PackedByteArray()
	vis.resize(N)
	var front: Array = []
	for tr in terr:
		if tr["owner"] == viewer:
			vis[tr["idx"]] = 1
			front.append(tr["idx"])
	for r in vision_rings(viewer):
		var nxt: Array = []
		for a in front:
			for b in Data.TERRITORIES[a]["adj"]:
				if vis[b] == 0:
					vis[b] = 1
					nxt.append(b)
		front = nxt
	return vis


## Raggio di vista in anelli di adiacenza (1 = solo i confinanti; AAN 2 grazie al radar)
func vision_rings(viewer: int) -> int:
	if viewer < 0 or viewer >= players.size():
		return 1
	return 2 if str(players[viewer]["fac"].get("id", "")) == RADAR_FACTION else 1


## Una divisione è visibile se è propria, o se parte o arriva in un territorio visibile
func division_visible(viewer: int, d: Dictionary) -> bool:
	if not fog or viewer < 0 or int(d.get("owner", -1)) == viewer:
		return true
	return is_visible(viewer, int(d["from"])) or is_visible(viewer, int(d["to"]))


func visible_divisions(viewer: int) -> Array:
	if not fog or viewer < 0:
		return divisions
	return divisions.filter(func(d): return division_visible(viewer, d))


## Stima delle unità di t per viewer: esatta se le forze sono visibili; neutrali fuori vista arrotondati
## a multipli di 5 (sempre visibili come forza approssimativa); -1 se ignota (nemico nella nebbia o forze nascoste).
func estimate_forces(viewer: int, t: int) -> int:
	if not _valid_terr(t):
		return -1
	return int(forces_view(viewer, t)["est"])


# ------------------------------------------------------------------ veterani
static func vet_level(xp: int) -> int:
	for i in range(VET_MAX, 0, -1):
		if xp >= VET_XP[i]:
			return i
	return 0


## Vittorie mancanti alla prossima stella del presidio (0 se al massimo)
func vet_next(t: int) -> int:
	var tr: Dictionary = terr[t]
	var v: int = int(tr.get("vet", 0))
	if v >= VET_MAX:
		return 0
	return maxi(0, VET_XP[v + 1] - int(tr.get("xp", 0)))


## Media pesata (n0 unità a v0/x0, n1 a v1/x1) arrotondata al più vicino; xp coerente con la stella risultante
static func _blend_vet(n0: int, v0: int, x0: int, n1: int, v1: int, x1: int) -> Array:
	var n := float(n0 + n1)
	var nv := clampi(roundi((v0 * n0 + v1 * n1) / n), 0, VET_MAX)
	var nx := roundi((x0 * n0 + x1 * n1) / n)
	nx = clampi(nx, VET_XP[nv], (VET_XP[nv + 1] - 1) if nv < VET_MAX else VET_XP[VET_MAX])
	return [nv, nx]


## Fusione con una divisione/presidio: media pesata per unità arrotondata al più vicino
## (da chiamare PRIMA di sommare le forze). Le reclute fresche già presenti restano contate a parte.
func _merge_vet(tr: Dictionary, add: Dictionary, vet: int, xp: int) -> void:
	var n1 := Data.total_units(add)
	if n1 <= 0:
		return
	var n0 := Data.total_units(tr["forces"])
	if n0 <= 0:
		tr["vet"] = clampi(vet, 0, VET_MAX)
		tr["xp"] = maxi(0, xp)
		tr["fresh"] = 0
		return
	var v0: int = int(tr.get("vet", 0))
	var x0: int = int(tr.get("xp", 0))
	if v0 == vet and x0 == xp:
		return
	var b := _blend_vet(n0, v0, x0, n1, vet, xp)
	tr["vet"] = b[0]
	tr["xp"] = b[1]
	if b[0] == 0:
		tr["fresh"] = 0


## Reclute (milizia, reclutamento, pool/carte rinforzi, mercenari): non abbassano le stelle finché non superano
## il 50% del presidio veterano; oltre, si fondono (media pesata al più vicino) e il conteggio riparte.
## Da chiamare PRIMA di sommare le forze.
func _add_recruits(tr: Dictionary, n: int) -> void:
	if n <= 0 or int(tr.get("vet", 0)) <= 0:
		return
	var tot := Data.total_units(tr["forces"])
	var fresh: int = mini(int(tr.get("fresh", 0)), tot) + n
	var vets: int = tot + n - fresh
	if vets <= 0:
		tr["vet"] = 0
		tr["xp"] = 0
		tr["fresh"] = 0
		return
	if fresh * 2 <= vets:
		tr["fresh"] = fresh
		return
	var b := _blend_vet(vets, int(tr["vet"]), int(tr.get("xp", 0)), fresh, 0, 0)
	tr["vet"] = b[0]
	tr["xp"] = b[1]
	tr["fresh"] = 0


## Una vittoria (attacco o difesa) per il presidio di t
## Esperienza del presidio: 1 punto per battaglia, 2 se comandata di persona (docs/omogeneita.md §3)
func _gain_xp(t: int, pts: int = 1) -> void:
	var tr: Dictionary = terr[t]
	var o: int = tr["owner"]
	if o < 0 or Data.total_units(tr["forces"]) == 0:
		return
	tr["xp"] = mini(int(tr.get("xp", 0)) + maxi(1, pts), VET_XP[VET_MAX])
	var nv := vet_level(tr["xp"])
	if nv > int(tr.get("vet", 0)):
		tr["vet"] = nv
		var stars := "★".repeat(nv)
		var tname: String = Data.TERRITORIES[t]["name"]
		if o == human_idx:
			add_log("Il presidio di " + tname + " diventa veterano " + stars + " (+" + str(roundi(VET_BONUS * 100 * nv)) + "% attacco)", "good", o)
		elif nv >= VET_MAX:
			add_log(_pname(o) + ": truppe d'élite " + stars + " in " + tname, "info", null)
		emit_event("veteran", {"terr": t, "player": o, "vet": nv})


# ------------------------------------------------------------------ diplomazia
static func _pair_key(a: int, b: int) -> String:
	return str(mini(a, b)) + ":" + str(maxi(a, b))


## mm:ss di un tempo di gioco
static func clock_text(t: float) -> String:
	var s := maxi(0, int(floor(t)))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


func _find_pact(a: int, b: int) -> Variant:
	for pc in pacts:
		if (pc["a"] == a and pc["b"] == b) or (pc["a"] == b and pc["b"] == a):
			return pc
	return null


func has_pact(a: int, b: int) -> bool:
	return a != b and _find_pact(a, b) != null


## Ultimo round (incluso) in cui vale il patto tra a e b (-1 se non c'è)
func pact_until(a: int, b: int) -> int:
	var pc: Variant = _find_pact(a, b)
	return int(pc["until"]) if pc != null else -1


## Round mancanti prima di poter (ri)proporre un patto tra a e b
func pact_cooldown(a: int, b: int) -> int:
	return maxi(0, int(_pact_cd.get(_pair_key(a, b), -1000000)) - round)


func pact_partners(p: int) -> Array:
	var o: Array = []
	for pc in pacts:
		if pc["a"] == p:
			o.append(pc["b"])
		elif pc["b"] == p:
			o.append(pc["a"])
	return o


func _pact_block_text(p: int, o: int) -> String:
	return "Patto di non aggressione con " + _pname(o) + " fino al round " + str(pact_until(p, o))


func _note_aggression(a: int, b: int) -> void:
	if a >= 0 and b >= 0 and a != b:
		_aggr[str(a) + ">" + str(b)] = round


## true se a ha attaccato b (attacchi, carte OPS) negli ultimi window round (0 = in questo round)
func attacked_recently(a: int, b: int, window: int = PACT_AGGR_WINDOW) -> bool:
	var k := str(a) + ">" + str(b)
	return _aggr.has(k) and round - int(_aggr[k]) <= window


## Leader: più territori di ogni altro giocatore vivo, oppure oltre il 35% del mondo
func is_leader(p: int) -> bool:
	if not _valid_player(p):
		return false
	var n := territories_of(p).size()
	if n > 0.35 * terr.size():
		return true
	for q in players:
		if q["alive"] and q["idx"] != p and territories_of(q["idx"]).size() >= n:
			return false
	return true


## Pressione militare di q su me: potenza di q nei territori confinanti con i miei,
## aumentata se q mi ha attaccato negli ultimi 2 round.
func _pressure(me: int, q: int) -> float:
	var s := 0.0
	var counted := {}
	for tr in terr:
		if tr["owner"] != me:
			continue
		for j in Data.TERRITORIES[tr["idx"]]["adj"]:
			if terr[j]["owner"] == q and not counted.has(j):
				counted[j] = true
				s += Combat.force_power(terr[j]["forces"])
	if attacked_recently(q, me, 2):
		s *= 1.4
	return s


## Potenza di me nei miei territori confinanti con q
func _border_power(me: int, q: int) -> float:
	var s := 0.0
	for tr in terr:
		if tr["owner"] != me:
			continue
		for j in Data.TERRITORIES[tr["idx"]]["adj"]:
			if terr[j]["owner"] == q:
				s += Combat.force_power(tr["forces"])
				break
	return s


## Valutazione di un patto dal punto di vista dell'IA ai verso other:
## {accept: bool, reason: String, ratio (minacce altrove / minaccia di other), other_pressure, rest_pressure}
func pact_evaluation(ai: int, other: int) -> Dictionary:
	var out := {"accept": false, "reason": "", "ratio": 0.0, "other_pressure": 0.0, "rest_pressure": 0.0}
	if not _valid_player(ai) or not _valid_player(other) or ai == other:
		out["reason"] = "Giocatore non attivo"
		return out
	var an := _pname(ai)
	if is_leader(other):
		out["reason"] = an + " non firma patti con chi guida la corsa al dominio"
		return out
	if attacked_recently(other, ai):
		out["reason"] = an + " rifiuta: l'hai attaccata in questo round o nel precedente"
		return out
	var po := _pressure(ai, other)
	var rest := 0.0
	var hit_elsewhere := false
	for q in players:
		var qi: int = q["idx"]
		if qi == ai or qi == other or not q["alive"] or has_pact(ai, qi):
			continue
		rest += _pressure(ai, qi)
		if attacked_recently(qi, ai, 2):
			hit_elsewhere = true
	var ratio := rest / (po + 5.0)
	out["ratio"] = ratio
	out["other_pressure"] = po
	out["rest_pressure"] = rest
	if rest < 8.0:
		out["reason"] = an + " non ha altri fronti caldi: nessun interesse a un patto"
		return out
	var thr := 1.0 if hit_elsewhere else 1.5   # in difficoltà su un altro fronte: accetta più volentieri
	if ratio < thr:
		out["reason"] = an + " rifiuta: il fronte con te è il suo principale"
		return out
	if po > 0.0 and _border_power(ai, other) > 2.5 * po and ratio < 3.0:
		out["reason"] = an + " rifiuta: sul vostro confine è in netto vantaggio"
		return out
	out["accept"] = true
	out["reason"] = an + " accetta il patto di non aggressione"
	return out


func _pact_precheck(a: int, b: int) -> String:
	if over != null:
		return "Partita finita"
	if not _valid_player(a) or not _valid_player(b) or a == b:
		return "Giocatore non valido"
	if players[a]["human"] == players[b]["human"]:
		return "Patti possibili solo tra il giocatore e un'IA"
	if has_pact(a, b):
		return "Patto già in vigore con " + _pname(b if players[a]["human"] else a) + " fino al round " + str(pact_until(a, b))
	var h: int = a if players[a]["human"] else b
	var alive_others := 0
	for q in players:
		if q["alive"] and q["idx"] != h:
			alive_others += 1
	if pact_partners(h).size() >= alive_others - 1:
		return "Non puoi essere in pace con tutti gli avversari"
	return ""


## Proposta di patto (PACT_DUR round). Se to è un'IA decide subito ({ok, reason, accepted}); se to è il giocatore umano
## diventa un'offerta (segnale pact_offer {from, to}) a cui rispondere con answer_pact entro il round successivo.
## Ricarica PACT_CD round per coppia (anche dopo un rifiuto).
func propose_pact(from: int, to: int) -> Dictionary:
	var why := _pact_precheck(from, to)
	if why != "":
		return {"ok": false, "reason": why, "accepted": false}
	var cd := pact_cooldown(from, to)
	if cd > 0:
		return {"ok": false, "reason": "Diplomazia: riprova tra " + str(cd) + (" round" if cd != 1 else " round"), "accepted": false}
	if players[to]["human"]:
		for of in pact_offers:
			if of["from"] == from and of["to"] == to:
				return {"ok": false, "reason": "Offerta già in attesa", "accepted": false}
		_pact_cd[_pair_key(from, to)] = round + PACT_CD
		pact_offers.append({"from": from, "to": to, "until": round + PACT_OFFER_DUR})
		add_log(_pname(from) + " propone un patto di non aggressione di " + str(PACT_DUR) + " round", "info", to)
		emit_event("pact_offer", {"from": from, "to": to})
		return {"ok": true, "reason": "Proposta inviata", "accepted": false}
	_pact_cd[_pair_key(from, to)] = round + PACT_CD
	var ev := pact_evaluation(to, from)
	if ev["accept"]:
		_make_pact(from, to)
		return {"ok": true, "reason": ev["reason"], "accepted": true}
	if players[from]["human"]:
		add_log("Diplomazia: " + ev["reason"], "info", from)
	return {"ok": true, "reason": ev["reason"], "accepted": false}


## Risposta del giocatore umano a un'offerta dell'IA ai_idx: {ok, reason, accepted}
func answer_pact(ai_idx: int, human: int, accept: bool) -> Dictionary:
	var found := -1
	for i in pact_offers.size():
		if pact_offers[i]["from"] == ai_idx and pact_offers[i]["to"] == human:
			found = i
			break
	if found < 0:
		return {"ok": false, "reason": "Nessuna offerta in attesa (scaduta?)", "accepted": false}
	pact_offers.remove_at(found)
	_pact_cd[_pair_key(ai_idx, human)] = round + PACT_CD
	if not accept:
		add_log("Hai respinto l'offerta di patto di " + _pname(ai_idx), "info", human)
		emit_event("pact_refused", {"from": ai_idx, "to": human})
		return {"ok": true, "reason": "Offerta respinta", "accepted": false}
	var why := _pact_precheck(ai_idx, human)
	if why != "":
		return {"ok": false, "reason": why, "accepted": false}
	_make_pact(ai_idx, human)
	return {"ok": true, "reason": "Patto firmato", "accepted": true}


func _make_pact(a: int, b: int) -> void:
	var until := round + PACT_DUR
	pacts.append({"a": a, "b": b, "until": until})
	pact_offers = pact_offers.filter(func(of): return not ((of["from"] == a and of["to"] == b) or (of["from"] == b and of["to"] == a)))
	add_log("Patto di non aggressione tra " + _pname(a) + " e " + _pname(b) + " fino al round " + str(until),
		"good" if _involves_human([a, b]) else "info", null)
	emit_event("pact", {"a": a, "b": b, "until": until})


func _end_pact(i: int, expired: bool) -> void:
	var pc: Dictionary = pacts[i]
	pacts.remove_at(i)
	var key := _pair_key(pc["a"], pc["b"])
	_pact_cd[key] = maxi(int(_pact_cd.get(key, -1000000)), round + PACT_CD)
	if expired:
		add_log("Scaduto il patto di non aggressione tra " + _pname(pc["a"]) + " e " + _pname(pc["b"]),
			"bad" if _involves_human([pc["a"], pc["b"]]) else "info", null)
	emit_event("pact_end", {"a": pc["a"], "b": pc["b"]})


func _update_pacts() -> void:
	for i in range(pacts.size() - 1, -1, -1):
		var pc: Dictionary = pacts[i]
		if round > int(pc["until"]):
			_end_pact(i, true)
		elif not players[pc["a"]]["alive"] or not players[pc["b"]]["alive"]:
			_end_pact(i, false)
	for i in range(pact_offers.size() - 1, -1, -1):
		var of: Dictionary = pact_offers[i]
		if round > int(of["until"]) or not players[of["from"]]["alive"] or not players[of["to"]]["alive"]:
			pact_offers.remove_at(i)
			if players[of["to"]]["alive"] and players[of["from"]]["alive"]:
				add_log("L'offerta di patto di " + _pname(of["from"]) + " è scaduta", "info", of["to"])
			emit_event("pact_offer_end", {"from": of["from"], "to": of["to"]})


func terr_income(t: int) -> Dictionary:
	var tr: Dictionary = terr[t]
	var T: Dictionary = Data.TERRITORIES[t]
	var o := {"money": Data.ECON["baseMoney"], "oil": Data.ECON["baseOil"], "steel": Data.ECON["baseSteel"], "manpower": Data.ECON["baseManpower"]}
	o[T["spec"]] += Data.ECON["specRate"] * T["amt"]
	var mul: float = Data.ECON["passive"]
	if tr["sabotage"] > 0 or tr["unrest"] > 0:
		mul = 0.0
	if tr["owner"] >= 0 and players[tr["owner"]]["hq"] == t:
		mul *= Data.ECON["hqMul"]
	if tr["buildings"].has("impianto"):
		mul *= Data.ECON["impiantoMul"]
	if not tr["supplied"]:
		mul *= Data.ECON["unsupplied"]
	mul *= Data.TURN_SECS   # FASE 6: reddito per turno
	for k in Data.RES_KEYS:
		o[k] *= mul
	return o


func income_of(p: int) -> Dictionary:
	var inc := {"money": 0.0, "oil": 0.0, "steel": 0.0, "manpower": 0.0}
	if not _valid_player(p):
		return inc
	var P: Dictionary = players[p]
	for tr in terr:
		if tr["owner"] != p:
			continue
		var ti := terr_income(tr["idx"])
		for k in Data.RES_KEYS:
			inc[k] += ti[k]
	if owns_continent(p, "EU"):
		inc["money"] *= 1.25
	var mm = _fac_mod(p, "moneyMul")
	if mm:
		inc["money"] *= float(mm)   # FO: economia di guerra
	if owns_continent(p, "SA"):
		inc["steel"] *= 1.30
	if owns_continent(p, "AF"):
		inc["manpower"] *= 1.30
	if owns_continent(p, "AS"):
		inc["oil"] *= 1.30
	if p < _scen_income.size() and float(_scen_income[p]) != 1.0:
		for k in Data.RES_KEYS:
			inc[k] *= float(_scen_income[p])
	if not P["human"]:
		var m: float = Data.DIFFICULTY[P["difficulty"]]["income"]
		for k in Data.RES_KEYS:
			inc[k] *= m
	return inc


## Mantenimento in petrolio per turno
func upkeep_of(p: int) -> float:
	var u := 0.0
	for tr in terr:
		if tr["owner"] == p:
			for k in Data.UNIT_KEYS:
				u += tr["forces"][k] * Data.UNITS[k]["upkeep"]
	return u * Data.TURN_SECS


func reinforce_amount(p: int) -> int:
	var n: int = maxi(Data.ECON["reinforceMin"], int(floor(territories_of(p).size() / REINFORCE_DIV)))
	for c in Data.CONT_KEYS:
		if owns_continent(p, c):
			n += Data.CONTINENTS[c]["bonus"]
	var r = _fac_mod(p, "reinforce")
	n += int(r) if r else 0
	return n


func is_valid_set(cards) -> bool:
	if cards == null or cards.size() != 3:
		return false
	var types: Array = []
	for c in cards:
		if c == null:
			return false
		types.append(c["type"])
	if types.has("jolly"):
		return true
	var u := {}
	for x in types:
		u[x] = true
	return u.size() == 1 or u.size() == 3


## null o [i, j, k]
func find_set(p: int):
	var c: Array = players[p]["cards"]
	for i in c.size():
		for j in range(i + 1, c.size()):
			for k in range(j + 1, c.size()):
				if is_valid_set([c[i], c[j], c[k]]):
					return [i, j, k]
	return null


func set_value(p: int) -> int:
	var n: int = players[p]["sets_traded"]
	if n < Data.SET_VALUES.size():
		return Data.SET_VALUES[n]
	return Data.SET_VALUES[Data.SET_VALUES.size() - 1] + 5 * (n - Data.SET_VALUES.size() + 1)


# ------------------------------------------------------------------ comandi
## COMPATIBILITÀ (FASE 6): vecchio comando in tempo reale → move() se `to` è proprio, altrimenti attack().
## what: frazione 0..1 (float/int), null (= tutto meno 1) oppure Dictionary di forze
func send_division(p: int, from: int, to: int, what = null) -> Dictionary:
	if not _valid_terr(from) or not _valid_terr(to):
		return _fail("Destinazione non raggiungibile")
	if terr[from]["owner"] != p:
		return _fail("Il territorio di partenza non è tuo")
	var f: Dictionary
	if what is Dictionary:
		f = _sanitize_forces(what, terr[from]["forces"])
	else:
		var fr: float = clampf(1.0 if what == null else float(what), 0.0, 1.0)
		f = Data.empty_forces()
		for k in Data.UNIT_KEYS:
			f[k] = int(floor(terr[from]["forces"][k] * fr + 1e-9))
	f = _leave_one(terr[from]["forces"], f)
	if terr[to]["owner"] == p:
		return move(from, to, f)
	return attack(from, to, f)


func recruit(p: int, t: int, unit_key: String, count = 1) -> Dictionary:
	var cnt: int = maxi(1, int(floor(_num(count))) if _num(count) != 0 else 1)
	var turns: int = int(Data.TURNS["units"].get(unit_key, 1))
	var done := 0
	var last = null
	for i in cnt:
		var c := can_recruit(p, t, unit_key)
		if not c["ok"]:
			last = c
			break
		_pay(p, cost_for(p, unit_key))
		terr[t]["queue"].append({"unit": unit_key, "t": 0, "total": turns})
		done += 1
	if done == 0:
		return last if last != null else _fail("Impossibile reclutare")
	return {"ok": true, "reason": ("Accodate solo " + str(done) + " unità") if done < cnt else "", "count": done}


func build(p: int, t: int, key: String) -> Dictionary:
	var c := can_build(p, t, key)
	if not c["ok"]:
		return c
	_pay(p, Data.BUILDINGS[key]["cost"])
	terr[t]["building"] = {"key": key, "t": 0, "total": int(Data.TURNS["buildings"].get(key, 2))}
	return _ok()


func research(p: int) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	var P: Dictionary = players[p]
	if P["research"] != null:
		return _fail("Ricerca già in corso")
	if P["hq"] < 0:
		return _fail("Serve un QG")
	var rc = research_cost(p)
	if rc == null:
		return _fail("Tecnologia al massimo")
	if not can_afford(p, rc["cost"]):
		return _fail("Risorse insufficienti: " + missing_text(p, rc["cost"]))
	_pay(p, rc["cost"])
	P["research"] = {"level": rc["level"], "t": 0, "total": int(rc["turns"])}
	return _ok()


## forces: null = tutto il pool, oppure Dictionary di forze (limitato al pool)
func place_pool(p: int, t: int, forces = null) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	if not _valid_terr(t) or terr[t]["owner"] != p:
		return _fail("Il territorio non è tuo")
	var P: Dictionary = players[p]
	if Data.total_units(P["pool"]) == 0:
		return _fail("Nessun rinforzo da schierare")
	var f: Dictionary = Data.clone_forces(P["pool"]) if not (forces is Dictionary) else _sanitize_forces(forces, P["pool"])
	if Data.total_units(f) == 0:
		return _fail("Nessuna unità scelta")
	_add_recruits(terr[t], Data.total_units(f))
	Data.add_forces(terr[t]["forces"], f)
	for k in Data.UNIT_KEYS:
		P["pool"][k] = maxi(0, int(P["pool"][k]) - int(f[k]))
	emit_event("deploy", {"player": p, "terr": t, "forces": f})
	return _ok()


func hire_mercs(p: int, t: int) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	var P: Dictionary = players[p]
	if not _fac_mod(p, "mercs"):
		return _fail("Solo l'Unione Libera assolda mercenari")
	if not _valid_terr(t) or terr[t]["owner"] != p:
		return _fail("Il territorio non è tuo")
	if not can_afford(p, Data.MERC_OFFER["cost"]):
		return _fail("Denaro insufficiente")
	_pay(p, Data.MERC_OFFER["cost"])
	_add_recruits(terr[t], int(Data.MERC_OFFER["count"]))
	terr[t]["forces"]["inf"] += Data.MERC_OFFER["count"]
	if P["human"]:
		add_log("Mercenari assoldati in " + Data.TERRITORIES[t]["name"] + " (+" + str(Data.MERC_OFFER["count"]) + " FAN)", "good", p)
	return _ok()


## Mercato internazionale: vende o compra un lotto di risorsa in cambio di denaro.
## Il prezzo si muove con gli scambi (vendere lo abbassa, comprare lo alza) e torna lentamente a 1.
func market_price(p: int, res: String, dir: String) -> int:
	var P: Dictionary = players[p]
	var m: float = 1.0
	if P.get("market") != null and P["market"].get(res):
		m = float(P["market"][res])
	return roundi(Data.MARKET["lot"] * m * (Data.MARKET["sell"] if dir == "sell" else Data.MARKET["buy"]))


func trade(p: int, res: String, dir: String) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	var P: Dictionary = players[p]
	if not Data.MARKET["goods"].has(res):
		return _fail("Risorsa non scambiabile")
	if P.get("market") == null:
		P["market"] = {"oil": 1.0, "steel": 1.0, "manpower": 1.0}
	var price := market_price(p, res, dir)
	var lot: float = Data.MARKET["lot"]
	if dir == "sell":
		if P["res"][res] < lot:
			return _fail(Data.RES_NAMES[res] + " insufficiente (servono " + str(Data.MARKET["lot"]) + ")")
		P["res"][res] -= lot
		P["res"]["money"] += price
		P["market"][res] = maxf(Data.MARKET["min"], P["market"][res] * (1.0 - Data.MARKET["step"]))
	elif dir == "buy":
		if P["res"]["money"] < price:
			return _fail("Denaro insufficiente (servono " + str(price) + ")")
		P["res"]["money"] -= price
		P["res"][res] += lot
		P["market"][res] = minf(Data.MARKET["max"], P["market"][res] * (1.0 + Data.MARKET["step"]))
	else:
		return _fail("Operazione non valida")
	emit_event("trade", {"player": p, "res": res, "dir": dir, "price": price})
	return _ok()


func play_cards(p: int, idxs, op: String, target = -1) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	var P: Dictionary = players[p]
	if not (idxs is Array or idxs is PackedInt32Array) or idxs.size() != 3:
		return _fail("Seleziona tre carte")
	var uniq := {}
	for i in idxs:
		uniq[int(i)] = true
	if uniq.size() != 3:
		return _fail("Seleziona tre carte")
	var cards: Array = []
	for i in idxs:
		cards.append(P["cards"][int(i)] if int(i) >= 0 and int(i) < P["cards"].size() else null)
	if not is_valid_set(cards):
		return _fail("Tris non valido")
	if not Data.OPS.has(op):
		return _fail("Operazione sconosciuta")
	var tr = null
	if Data.OPS[op]["target"] == "self":
		if not _valid_terr(target):
			return _fail("Scegli un tuo territorio")
		tr = terr[int(target)]
		if tr["owner"] != p:
			return _fail("Il bersaglio deve essere un tuo territorio")
	elif Data.OPS[op]["target"] == "enemy":
		if not _valid_terr(target):
			return _fail("Scegli un bersaglio")
		tr = terr[int(target)]
		if tr["owner"] == p:
			return _fail("Il bersaglio deve essere nemico")
		if op == "ricognizione" and tr["owner"] < 0:
			return _fail("La ricognizione serve contro un giocatore")
		if tr["owner"] >= 0 and has_pact(p, tr["owner"]):
			return _fail(_pact_block_text(p, tr["owner"]))
		if tr["owner"] >= 0 and in_truce():
			# la tregua vale anche per le operazioni: niente golpe o missili sui giocatori nei primi round
			return _fail("Tregua iniziale: operazioni contro gli altri giocatori dal round " + str(truce_rounds + 1))
		if op == "golpe":
			if Data.total_units(tr["forces"]) > Data.GOLPE_MAX:
				return _fail("Troppe truppe (max " + str(Data.GOLPE_MAX) + ")")
			for q in players:
				if q["alive"] and q["hq"] == int(target):
					return _fail("Non si può fare un golpe su un QG")
	if tr != null and tr["owner"] >= 0 and tr["owner"] != p and op != "ricognizione":
		_note_aggression(p, tr["owner"])
	# consuma le carte
	var sorted_idx: Array = []
	for i in idxs:
		sorted_idx.append(int(i))
	sorted_idx.sort()
	sorted_idx.reverse()
	for i in sorted_idx:
		discard.append(P["cards"][i])
		P["cards"].remove_at(i)
	var T = Data.TERRITORIES[tr["idx"]] if tr != null else null
	if op == "rinforzi":
		var v := set_value(p)
		P["sets_traded"] += 1
		var non_j: Array = []
		for c in cards:
			if c["type"] != "jolly":
				non_j.append(c["type"])
		var kind = "inf"
		if non_j.size() > 0:
			var same := true
			for x in non_j:
				if x != non_j[0]:
					same = false
			if same:
				kind = non_j[0]
		var add := Data.empty_forces()
		if kind == "tank":
			add["tank"] = int(floor(v / 2.0))
			add["inf"] = v - add["tank"]
		elif kind == "air":
			if P["tech"] >= 2:
				add["heli"] = int(floor(v / 3.0))
				add["inf"] = v - add["heli"]
			else:
				add["tank"] = int(floor(v / 2.0))
				add["inf"] = v - add["tank"]
		else:
			add["inf"] = v
		Data.add_forces(P["pool"], add)
		if P["human"]:
			add_log("Carte giocate: rinforzi " + forces_text(add) + " da schierare", "good", p)
		emit_event("reinforce", {"player": p, "count": Data.total_units(add)})
	elif op == "missile":
		var pct := 0.5 if P["tech"] >= 4 else 0.35
		var killed := 0
		for k in Data.UNIT_KEYS:
			var x: float = tr["forces"][k] * pct
			var n: int = mini(tr["forces"][k], int(floor(x + _rand())))
			tr["forces"][k] -= n
			killed += n
		P["stats"]["killed"] += killed
		if tr["owner"] >= 0:
			players[tr["owner"]]["stats"]["unitsLost"] += killed
		var src: Dictionary = Data.TERRITORIES[P["hq"]] if P["hq"] >= 0 else T
		add_effect("missile", src["x"], src["y"], {"x2": T["x"], "y2": T["y"]})
		add_effect("explosion", T["x"], T["y"])
		add_log(P["fac"]["short"] + ": attacco missilistico su " + T["name"] + " (" + str(killed) + (" unità distrutta)" if killed == 1 else " unità distrutte)"),
			(("good" if p == human_idx else "bad") if _involves_human([p, tr["owner"]]) else "battle"), null)
		emit_event("missile", {"terr": tr["idx"], "by": p})
	elif op == "sabotaggio":
		tr["sabotage"] = int(Data.TURN_RULES["sabotage"])
		add_log(P["fac"]["short"] + ": sabotaggio in " + T["name"], (("good" if p == human_idx else "bad") if _involves_human([p, tr["owner"]]) else "info"), null)
		emit_event("sabotage", {"terr": tr["idx"], "by": p})
	elif op == "golpe":
		var half := Data.empty_forces()
		for k in Data.UNIT_KEYS:
			half[k] = int(floor(tr["forces"][k] / 2.0))
		if Data.total_units(half) == 0:
			half["inf"] = 1   # il golpe lascia sempre almeno un presidio
		var prev: int = tr["owner"]
		add_log(P["fac"]["short"] + ": golpe in " + T["name"] + "! Il territorio passa a " + P["fac"]["short"],
			(("good" if p == human_idx else "bad") if _involves_human([p, prev]) else "info"), null)
		_capture(tr["idx"], p, half, {"noCard": true, "silent": true})
		emit_event("golpe", {"terr": tr["idx"], "by": p})
	elif op == "finta":
		tr["decoy"] = int(Data.DECEIT_ROUNDS)
		tr["silence"] = 0
		if P["human"]:
			add_log("Divisione falsa in " + T["name"] + ": per " + str(Data.DECEIT_ROUNDS) + " round i nemici vedono circa " + str(Data.DECOY_UNITS) + " unità in più", "good", p)
		emit_event("deceit", {"terr": tr["idx"], "by": p, "op": op})
	elif op == "silenzio":
		tr["silence"] = int(Data.DECEIT_ROUNDS)
		tr["decoy"] = 0
		if P["human"]:
			add_log("Silenzio radio in " + T["name"] + ": per " + str(Data.DECEIT_ROUNDS) + " round i nemici non sanno quante truppe ci sono", "good", p)
		emit_event("deceit", {"terr": tr["idx"], "by": p, "op": op})
	elif op == "ricognizione":
		intel["%d:%d" % [p, int(tr["idx"])]] = round + int(Data.DECEIT_ROUNDS) - 1
		_vis_cache.clear()
		add_log(P["fac"]["short"] + ": ricognizione su " + T["name"] + " (forze esatte per " + str(Data.DECEIT_ROUNDS) + " round)",
			"good" if p == human_idx else ("bad" if tr["owner"] == human_idx else "info"), null)
		emit_event("deceit", {"terr": tr["idx"], "by": p, "op": op})
	P["stats"]["cardsPlayed"] = int(P["stats"].get("cardsPlayed", 0)) + 1
	_after_action()
	return _ok()


# ------------------------------------------------------------------ carte
func _draw_card(p: int):
	if deck.is_empty():
		if discard.is_empty():
			return null
		deck = _shuffle(discard)
		discard = []
	var c = deck.pop_back()
	var P: Dictionary = players[p]
	P["cards"].append(c)
	while P["cards"].size() > Data.HAND_MAX:
		discard.append(P["cards"].pop_front())
	return c


# ------------------------------------------------------------------ conquista, eliminazione
func _capture(t: int, by: int, forces: Dictionary, o: Dictionary = {}) -> void:
	var tr: Dictionary = terr[t]
	var T: Dictionary = Data.TERRITORIES[t]
	var prev: int = tr["owner"]
	tr["owner"] = by
	tr["forces"] = Data.clone_forces(forces)
	tr["queue"] = []
	tr["building"] = null
	tr["unrest"] = int(Data.TURN_RULES["occupation"])
	tr["regroup"] = int(Data.TURN_RULES["regroup"]) if by >= 0 else 0
	var F := _fort_of(t)
	F["trench"] = 0
	F["mines"] = 0
	F["bunker"] = maxi(0, int(F["bunker"]) - 1)
	tr["vet"] = clampi(int(o.get("vet", 0)), 0, VET_MAX)
	tr["xp"] = maxi(0, int(o.get("xp", 0)))
	tr["fresh"] = 0
	_vis_cache.clear()
	_supply_dirty = true
	_ctx_dirty = true
	if by >= 0:
		players[by]["stats"]["conquered"] += 1
		var nt := territories_of(by).size()
		if nt > int(players[by]["stats"].get("maxTerr", 0)):
			players[by]["stats"]["maxTerr"] = nt
	if prev >= 0:
		players[prev]["stats"]["lost"] += 1
	add_effect("capture", T["x"], T["y"])
	if not o.get("silent", false):
		var type := "info"
		if by == human_idx and by >= 0:
			type = "good"
		elif prev == human_idx and prev >= 0:
			type = "bad"
		add_log(_pname(by) + " conquista " + T["name"] + ((" (da " + _pname(prev) + ")") if prev >= 0 else ""), type, null)
	emit_event("capture", {"terr": t, "by": by, "prev": prev})
	# QG
	if prev >= 0 and players[prev]["hq"] == t:
		var PP: Dictionary = players[prev]
		var best := -1
		var best_n := -1
		for x in terr:
			if x["owner"] == prev:
				var n := Data.total_units(x["forces"])
				if n > best_n:
					best_n = n
					best = x["idx"]
		PP["hq"] = best
		PP["research"] = null
		var steal := int(floor(PP["res"]["money"] * Data.ECON["hqCaptureSteal"]))
		PP["res"]["money"] -= steal
		if by >= 0:
			players[by]["res"]["money"] += steal
		var ltype := "bad" if prev == human_idx else ("good" if by == human_idx else "battle")
		add_log("QG di " + PP["fac"]["short"] + " catturato in " + T["name"] + "!" + ((" Nuovo QG: " + Data.TERRITORIES[best]["name"]) if best >= 0 else "") +
			((" (" + str(steal) + "$ sottratti)") if steal > 0 and by >= 0 else ""), ltype, null)
		emit_event("hqLost", {"player": prev, "terr": t})
		if prev == siege_idx:
			_update_targets()
	# carta
	if by >= 0 and not o.get("noCard", false):
		var P: Dictionary = players[by]
		if _draw_card(by) != null:
			if P["human"]:
				add_log("Hai ottenuto una carta Comando", "good", by)
			emit_event("card", {"player": by})
	if prev >= 0 and players[prev]["alive"] and territories_of(prev).is_empty():
		_eliminate(prev, by)


func _eliminate(p: int, by: int) -> void:
	var P: Dictionary = players[p]
	P["alive"] = false
	P["hq"] = -1
	P["research"] = null
	P["pool"] = Data.empty_forces()
	# come in Risiko: chi elimina un giocatore ne prende le carte (oltre la mano massima vanno negli scarti)
	if by >= 0 and by < players.size() and players[by]["alive"]:
		for c in P["cards"]:
			players[by]["cards"].append(c)
		while players[by]["cards"].size() > Data.HAND_MAX:
			discard.append(players[by]["cards"].pop_front())
	else:
		discard.append_array(P["cards"])
	P["cards"] = []
	P["stats"]["eliminatedAt"] = float(round)
	_vis_cache.clear()
	for i in range(pacts.size() - 1, -1, -1):
		if pacts[i]["a"] == p or pacts[i]["b"] == p:
			_end_pact(i, false)
	pact_offers = pact_offers.filter(func(of): return of["from"] != p and of["to"] != p)
	divisions = divisions.filter(func(d): return d["owner"] != p)
	if pending_battle != null and pending_battle["attacker"] == p and _manual == null:
		pending_battle = null
	if p == siege_idx:
		_siege_by = by
		_update_targets()
	add_log(P["fac"]["short"] + " è stata eliminata" + ((" da " + _pname(by)) if by >= 0 else "") + "!", "bad" if p == human_idx else "battle", null)
	emit_event("eliminated", {"player": p, "by": by})
	# obiettivi "elimina"
	for Q in players:
		var ob = Q["objective"]
		if ob == null or ob["type"] != "eliminate" or ob.get("target") != p or not Q["alive"]:
			continue
		if by == Q["idx"]:
			ob["done"] = true
		elif ob.get("scenario", false):
			pass   # assedio: la vittoria la decide la regola dello scenario
		else:
			ob["type"] = "count"
			ob["count"] = 24
			ob["text"] = "Conquista 24 territori (bersaglio eliminato da altri)"
			if Q["human"]:
				add_log("Il tuo bersaglio è stato eliminato da altri: nuovo obiettivo, conquista 24 territori", "info", Q["idx"])


# ------------------------------------------------------------------ battaglie
## Modificatori di battaglia. Le fortificazioni (terr.fort) entrano nei modificatori solo se fort = true (previsioni con la
## formula e risoluzione automatica con la formula): BattleSim (battaglia 3D e risoluzione tattica) le legge da setup.def.fort.
func battle_mods(info: Dictionary, manual: bool = false, fort: bool = true, reinf: Dictionary = {}) -> Dictionary:
	var defender: int = terr[info["terr"]]["owner"]
	var from_i := int(info["from"]) if info.get("from") != null else -1
	var worn_a: bool = _valid_terr(from_i) and int(terr[from_i].get("worn", 0)) > 0
	var worn_d: bool = int(terr[info["terr"]].get("worn", 0)) > 0
	var mo := {"fromIdx": info["from"], "sea": info["sea"], "manual": manual, "vet": int(info.get("vet", 0)), "worn": worn_a}
	var md := {"manual": manual, "vet": int(terr[info["terr"]].get("vet", 0)), "worn": worn_d}
	if not reinf.is_empty():
		mo["reinf"] = {"forces": reinf["attF"], "dir": int(reinf["attDir"]), "t": float(BattleRules.REINF_T[0])}
		md["reinf"] = {"forces": reinf["defF"], "dir": int(reinf["defDir"]), "t": float(BattleRules.REINF_T[1])}
	var mA: Dictionary = Combat.combat_mods(self, info["attacker"], "att", info["terr"], mo)
	var mD: Dictionary = Combat.combat_mods(self, defender, "def", info["terr"], md)
	if fort and not manual:
		fort_mods(info["terr"], mA, mD)
	return {"modsA": mA, "modsD": mD}


## Logoramento del territorio (0 = fresco, altrimenti turni al recupero)
func worn_of(t: int) -> int:
	return int(terr[t].get("worn", 0)) if _valid_terr(t) else 0


## Rinforzi dai territori vicini (docs/omogeneita.md §2): per lato la lista dei contributi {terr, forces} e il totale.
## Non toglie nulla dai territori: le perdite si scalano a fine battaglia (_reinf_settle).
func reinf_plan(info: Dictionary) -> Dictionary:
	var t := int(info["terr"])
	var T: Dictionary = Data.TERRITORIES[t]
	var out := {"att": [], "def": [], "attF": Data.empty_forces(), "defF": Data.empty_forces(), "attDir": -1, "defDir": -1}
	var defender: int = terr[t]["owner"]
	var main_n := {"att": Data.total_units(info["forces"]), "def": Data.total_units(terr[t]["forces"])}
	for sk in ["att", "def"]:
		var p: int = int(info["attacker"]) if sk == "att" else defender
		if p < 0:
			continue
		var cap := int(floor(main_n[sk] * BattleRules.REINF_CAP))
		var tot := 0
		var best_n := 0
		var dir := -1
		for j in T["adj"]:
			var tj: Dictionary = terr[j]
			if tj["owner"] != p or not tj["supplied"] or int(tj["regroup"]) > 0:
				continue
			if sk == "att" and j == int(info["from"]):
				continue   # il territorio di partenza ha già mandato ciò che l'attaccante ha scelto
			var have := Data.total_units(tj["forces"])
			var f := Data.empty_forces()
			var n := 0
			for k in BattleRules.REINF_TYPES:
				var c := int(floor(int(tj["forces"].get(k, 0)) * BattleRules.REINF_SHARE))
				f[k] = c
				n += c
			# almeno un'unità resta; tetto complessivo
			while n > 0 and (have - n < 1 or tot + n > cap):
				for k in ["aa", "art", "tank", "inf"]:
					if f[k] > 0:
						f[k] -= 1; n -= 1
						break
			if n <= 0:
				continue
			out[sk].append({"terr": j, "forces": f})
			Data.add_forces(out[sk + "F"], f)
			tot += n
			if n > best_n:
				best_n = n
				dir = -1 if float(Data.TERRITORIES[j]["y"]) <= float(T["y"]) else 1
		out[sk + "Dir"] = dir
	return out


## A fine battaglia: le perdite dei rinforzi (inviati − superstiti) si scalano dai territori di origine, nell'ordine.
func _reinf_settle(plan: Dictionary, sk: String, left) -> void:
	var sent: Dictionary = plan.get(sk + "F", Data.empty_forces())
	if Data.total_units(sent) == 0:
		return
	var surv := _sanitize_forces(left, sent)
	var lost := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		lost[k] = maxi(0, int(sent.get(k, 0)) - int(surv.get(k, 0)))
	var n_lost := Data.total_units(lost)
	for c in plan[sk]:
		var tr: Dictionary = terr[int(c["terr"])]
		for k in Data.UNIT_KEYS:
			var x := mini(int(lost[k]), mini(int(c["forces"][k]), int(tr["forces"][k])))
			if x > 0:
				tr["forces"][k] -= x
				lost[k] -= x
		if Data.total_units(tr["forces"]) == 0:
			tr["forces"]["inf"] = 1   # il presidio non sparisce mai del tutto
	if n_lost > 0:
		var p: int = int(plan.get(sk + "P", -1))
		if p == human_idx and p >= 0:
			add_log("Rinforzi dai territori vicini: %d unità perdute in battaglia" % n_lost, "bad", p)


## true se Combat.resolve_battle userà BattleSim (che gestisce da sé le fortificazioni)
func _tactical_for(att: Dictionary, def: Dictionary) -> bool:
	if not Combat.tactical:
		return false
	return Data.total_units(att) + Data.total_units(def) <= Combat.TACTICAL_MAX_UNITS and Data.total_units(att) > 0 and Data.total_units(def) > 0


## Applica ai modificatori i livelli di fortificazione del territorio t (risoluzione automatica e previsioni)
func fort_mods(t: int, mA: Dictionary, mD: Dictionary) -> void:
	var F := _fort_of(t)
	if int(terr[t]["sabotage"]) > 0:
		return
	var tr_l: int = F["trench"]
	if tr_l > 0:
		if not mD.has("hp") or mD["hp"] == null:
			mD["hp"] = {}
		for k in ["inf", "art", "aa"]:
			mD["hp"][k] = float(mD["hp"].get(k, 1.0)) * (1.0 + FORT_TRENCH_HP * tr_l)
	if F["mines"] > 0:
		mA["atk"] = float(mA.get("atk", 1.0)) * (1.0 - FORT_MINES_ATK * F["mines"])
	if F["bunker"] > 0:
		mD["atk"] = float(mD.get("atk", 1.0)) * (1.0 + FORT_BUNKER_ATK * F["bunker"])


func _fort_of(t: int) -> Dictionary:
	var f = terr[t].get("fort")
	if not (f is Dictionary):
		f = {"trench": 0, "mines": 0, "bunker": 0}
		terr[t]["fort"] = f
	for k in Data.FORT_KEYS:
		f[k] = clampi(int(f.get(k, 0)), 0, Data.FORT_MAX)
	return f


func _auto_battle(info: Dictionary, forces_a = null, forces_d = null, manual: bool = false) -> Dictionary:
	var att: Dictionary = forces_a if forces_a != null else info["forces"]
	var def: Dictionary = forces_d if forces_d != null else terr[info["terr"]]["forces"]
	var tac := _tactical_for(att, def)
	var plan := reinf_plan(info) if tac else {}
	var m := battle_mods(info, manual, not tac, plan)
	var r := Combat.resolve_battle(att, def, m["modsA"], m["modsD"], rng)
	if tac:
		plan["attP"] = int(info["attacker"])
		plan["defP"] = int(terr[info["terr"]]["owner"])
		_reinf_settle(plan, "att", r.get("attReinf", {}))
		_reinf_settle(plan, "def", r.get("defReinf", {}))
	return r


## orig_a/orig_d: forze all'inizio della battaglia (per le perdite)
func _apply_battle(info: Dictionary, orig_a: Dictionary, orig_d: Dictionary, att_left: Dictionary, def_left: Dictionary, winner: String, retreated: bool) -> void:
	var tr: Dictionary = terr[info["terr"]]
	var T: Dictionary = Data.TERRITORIES[info["terr"]]
	var defender: int = tr["owner"]
	if winner == "att" and Data.total_units(att_left) == 0:
		winner = "def"
	var a_lost := Data.empty_forces()
	var d_lost := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		a_lost[k] = maxi(0, int(orig_a.get(k, 0)) - int(att_left.get(k, 0)))
		d_lost[k] = maxi(0, int(orig_d.get(k, 0)) - (0 if winner == "att" else int(def_left.get(k, 0))))
	var nA := Data.total_units(a_lost)
	var nD := Data.total_units(d_lost)
	var A: Dictionary = players[info["attacker"]]
	A["stats"]["killed"] += nD
	A["stats"]["unitsLost"] += nA
	if defender >= 0:
		var D: Dictionary = players[defender]
		D["stats"]["killed"] += nA
		D["stats"]["unitsLost"] += nD
	if winner == "att":
		A["stats"]["battlesWon"] += 1
		if defender >= 0:
			players[defender]["stats"]["battlesLost"] += 1
	else:
		A["stats"]["battlesLost"] += 1
		if defender >= 0:
			players[defender]["stats"]["battlesWon"] += 1
	_battle_times.append([round, T["c"]])
	_ctx_dirty = true
	add_effect("battle", T["x"], T["y"])
	add_effect("explosion", T["x"] + (_rand() - 0.5) * 16, T["y"] + (_rand() - 0.5) * 16)
	var hum := _involves_human([info["attacker"], defender])
	var type := "battle"
	if hum:
		type = "good" if ((winner == "att") == (info["attacker"] == human_idx)) else "bad"
	var res: String = ("ritirata di " + A["fac"]["short"]) if retreated else (("vince " + A["fac"]["short"]) if winner == "att" else ("resiste " + _pname(defender)))
	add_log("Battaglia per " + T["name"] + " (" + A["fac"]["short"] + " contro " + _pname(defender) + "): " + res +
		". Perdite: " + str(nA) + " att., " + str(nD) + " dif.", type, null)
	emit_event("battle", {"terr": info["terr"], "winner": winner, "attacker": info["attacker"], "defender": defender,
		"from": info["from"], "attLosses": a_lost, "defLosses": d_lost})
	var xp_pts := 2 if bool(info.get("manual", false)) else 1   # comando diretto: esperienza doppia
	if winner == "att":
		_capture(info["terr"], info["attacker"], att_left, {"vet": info.get("vet", 0), "xp": info.get("xp", 0)})
		if terr[info["terr"]]["owner"] == info["attacker"]:
			_gain_xp(info["terr"], xp_pts)
	else:
		tr["forces"] = Data.clone_forces(def_left)
		if not retreated or nA > 0:
			_gain_xp(info["terr"], xp_pts)
		if Data.total_units(att_left) > 0 and A["alive"]:
			_return_home(info, att_left)
	# logoramento (docs/omogeneita.md §4): chi ha combattuto resta logorato per WORN_ROUNDS turni
	tr["worn"] = int(Data.WORN_ROUNDS)
	var back := int(info["from"]) if info.get("from") != null else -1
	if _valid_terr(back) and terr[back]["owner"] == info["attacker"]:
		terr[back]["worn"] = int(Data.WORN_ROUNDS)


## I superstiti di un attacco respinto tornano subito nel territorio di partenza (se è ancora loro)
func _return_home(info: Dictionary, forces: Dictionary) -> void:
	var p: int = info["attacker"]
	var back: int = int(info["from"])
	if terr[back]["owner"] != p:
		back = -1
		for j in Data.TERRITORIES[info["terr"]]["adj"]:
			if terr[j]["owner"] == p:
				back = j
				break
	if back < 0:
		if p == human_idx:
			add_log("I superstiti senza via di ritorno si sono dispersi", "bad", p)
		return
	_merge_vet(terr[back], forces, int(info.get("vet", 0)), int(info.get("xp", 0)))
	Data.add_forces(terr[back]["forces"], Data.clone_forces(forces))
	_anim(p, info["terr"], back, forces, bool(info.get("sea", false)), true)


## Battaglia in attesa diventata inutile (attaccante eliminato, territorio già suo per un golpe...):
## la chiude senza combattere. true se l'ha chiusa.
func _pending_moot(info: Dictionary, att_left: Dictionary) -> bool:
	var a: int = int(info["attacker"])
	if a < 0 or a >= players.size() or not players[a]["alive"]:
		return true
	var tr: Dictionary = terr[info["terr"]]
	if tr["owner"] == a:
		_merge_vet(tr, att_left, int(info.get("vet", 0)), int(info.get("xp", 0)))
		Data.add_forces(tr["forces"], Data.clone_forces(att_left))
		return true
	if tr["owner"] >= 0 and has_pact(a, tr["owner"]):
		if Data.total_units(att_left) > 0:
			_return_home(info, att_left)
		return true
	if Data.total_units(tr["forces"]) == 0 and Data.total_units(att_left) > 0:
		_capture(info["terr"], a, att_left, {"vet": info.get("vet", 0), "xp": info.get("xp", 0)})
		return true
	return false


func resolve_pending_auto() -> Dictionary:
	var info = pending_battle
	if info == null:
		return _fail("Nessuna battaglia in attesa")
	pending_battle = null
	_manual = null
	if _pending_moot(info, info["forces"]):
		_after_action()
		return {"ok": true, "reason": "Battaglia non più necessaria", "result": null}
	var orig_d := Data.clone_forces(terr[info["terr"]]["forces"])
	var r := _auto_battle(info)
	_apply_battle(info, info["forces"], orig_d, r["att"], r["def"], r["winner"], false)
	_after_action()
	return {"ok": true, "reason": "", "result": r}


## BattleSetup (vedi SPEC3D); {} se non c'è una battaglia in attesa
func start_manual_battle() -> Dictionary:
	var info = pending_battle
	if info == null:
		return {}
	var tr: Dictionary = terr[info["terr"]]
	var T: Dictionary = Data.TERRITORIES[info["terr"]]
	var defender: int = tr["owner"]
	var plan := reinf_plan(info)
	var m := battle_mods(info, true, true, plan)
	var A: Dictionary = players[info["attacker"]]
	var D = players[defender] if defender >= 0 else null
	var F: Dictionary = _fort_of(info["terr"]).duplicate()
	var sab: bool = int(tr["sabotage"]) > 0
	if sab:
		F = {"trench": 0, "mines": 0, "bunker": 0}
	var bunkers: int = 3 if (tr["buildings"].has("bunker") and not sab) else 0
	var hs: String = str(info.get("human_side", "att"))
	var ca: Dictionary = m["modsA"].get("ctx", {})
	var cd: Dictionary = m["modsD"].get("ctx", {})
	var setup := {
		"terrIdx": info["terr"], "terrain": T["ter"], "terrName": T["name"], "sea": bool(info["sea"]), "seed": int(floor(_rand() * 1e9)),
		"att": {"player": info["attacker"], "name": A["name"], "color": A["color"], "forces": Data.clone_forces(info["forces"]), "mods": m["modsA"],
			"human": A["human"] and hs == "att", "vet": int(info.get("vet", 0)), "faction": int(A["faction"]),
			"air": bool(ca.get("air", false)), "naval": int(ca.get("naval", 0)), "manual": A["human"] and hs == "att",
			"worn": bool(ca.get("worn", false))},
		"def": {
			"player": defender, "name": D["name"] if D != null else "Neutrali", "color": D["color"] if D != null else Color("#d6d9de"),
			"forces": Data.clone_forces(tr["forces"]), "mods": m["modsD"],
			"human": (D["human"] and hs == "def") if D != null else false, "bunkers": bunkers, "fort": F,
			"vet": int(tr.get("vet", 0)), "faction": int(D["faction"]) if D != null else -1,
			"air": bool(cd.get("air", false)), "naval": int(cd.get("naval", 0)), "manual": (D["human"] and hs == "def") if D != null else false,
			"worn": bool(cd.get("worn", false)),
		},
		"support": {"att": _support(info["attacker"], T), "def": _support(defender, T)},
		"human_side": hs,
		"buildings": tr["buildings"].duplicate(), "hq": D != null and int(D["hq"]) == int(info["terr"]),
	}
	for sk in ["att", "def"]:
		if Data.total_units(plan[sk + "F"]) > 0:
			setup[sk]["reinf"] = {"forces": Data.clone_forces(plan[sk + "F"]), "dir": int(plan[sk + "Dir"]),
				"t": float(BattleRules.REINF_T[0 if sk == "att" else 1])}
	plan["attP"] = int(info["attacker"])
	plan["defP"] = defender
	_manual = {"info": info, "setup": setup, "origD": Data.clone_forces(tr["forces"]), "reinf": plan}
	info["manual"] = true
	return setup


func _support(p: int, T: Dictionary) -> int:
	if p < 0 or players[p]["tech"] < 3:
		return 0
	var n := 0
	for j in T["adj"]:
		if terr[j]["owner"] == p:
			n += int(terr[j]["forces"]["art"])
	return n


## result = {att, def, winner, retreated, autoRest}
func finish_manual_battle(result = null) -> Dictionary:
	var m = _manual
	var info = pending_battle if pending_battle != null else (m["info"] if m != null else null)
	if info == null:
		return _fail("Nessuna battaglia in corso")
	pending_battle = null
	_manual = null
	var orig_a: Dictionary = info["forces"]
	var orig_d: Dictionary = m["origD"] if m != null else Data.clone_forces(terr[info["terr"]]["forces"])
	if result == null or not (result is Dictionary):
		result = {}
	var att := _sanitize_forces(result.get("att"), orig_a)
	var def := _sanitize_forces(result.get("def"), orig_d)
	if m != null and m.get("reinf") is Dictionary:
		var plan: Dictionary = m["reinf"]
		# senza dati sui rinforzi (chiusura forzata della scena) si considerano tornati tutti a casa
		_reinf_settle(plan, "att", result.get("attReinf", plan["attF"]))
		_reinf_settle(plan, "def", result.get("defReinf", plan["defF"]))
	if _pending_moot(info, att):
		_after_action()
		return _ok("Battaglia non più necessaria")
	var winner := "att" if result.get("winner") == "att" else "def"
	var retreated: bool = result.get("retreated", false) == true
	if retreated:
		winner = "def"
	elif result.get("autoRest", false) == true:
		if Data.total_units(att) == 0:
			winner = "def"
		elif Data.total_units(def) == 0:
			winner = "att"
		else:
			var bm := battle_mods(info, false, not _tactical_for(att, def))
			var r := Combat.resolve_battle(att, def, bm["modsA"], bm["modsD"], rng)
			att = r["att"]
			def = r["def"]
			winner = r["winner"]
	else:
		if winner == "att" and Data.total_units(att) == 0:
			winner = "def"
	_apply_battle(info, orig_a, orig_d, att, def, winner, retreated)
	_after_action()
	return _ok()


# ------------------------------------------------------------------ rifornimenti
func _recompute_supply() -> void:
	_supply_dirty = false
	for tr in terr:
		tr["supplied"] = tr["owner"] < 0
	for P in players:
		if not P["alive"] or P["hq"] < 0 or terr[P["hq"]]["owner"] != P["idx"]:
			continue
		var q: Array = [P["hq"]]
		terr[P["hq"]]["supplied"] = true
		while q.size() > 0:
			var a: int = q.pop_front()
			for b in Data.TERRITORIES[a]["adj"]:
				var tb: Dictionary = terr[b]
				if tb["owner"] == P["idx"] and not tb["supplied"]:
					tb["supplied"] = true
					q.append(b)


## rates = reddito per turno (petrolio al netto del mantenimento)
func _compute_rates() -> void:
	for P in players:
		if not P["alive"]:
			P["rates"] = {"money": 0.0, "oil": 0.0, "steel": 0.0, "manpower": 0.0}
			continue
		var inc := income_of(P["idx"])
		P["upkeep"] = upkeep_of(P["idx"])
		P["rates"] = {"money": inc["money"], "oil": inc["oil"] - P["upkeep"], "steel": inc["steel"], "manpower": inc["manpower"]}


# ------------------------------------------------------------------ turni (FASE 6)
func is_human_turn() -> bool:
	return over == null and current >= 0 and current < players.size() and players[current]["human"] and players[current]["alive"]


func current_player() -> int:
	return current


func in_truce() -> bool:
	return round <= truce_rounds


## Round rimanenti prima del limite (-1 senza limite)
func rounds_left() -> int:
	return maxi(0, round_limit - round + 1) if round_limit > 0 else -1


## Round mancanti alla vittoria di chi tiene i territori chiave (-1 se nessuno)
func hold_left() -> int:
	return maxi(0, hold_rounds - (round - _hold_since)) if _hold_owner >= 0 else -1


func _next_alive(from: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var j := (from + k) % n
		if players[j]["alive"]:
			return j
	return -1


func turn_status() -> Dictionary:
	return {"round": round, "player": current, "phase": phase, "attack_used": attack_used, "move_used": move_used,
		"truce_rounds_left": maxi(0, truce_rounds - round + 1), "human_turn": is_human_turn(), "next_player": _next_alive(current),
		"round_limit": round_limit, "rounds_left": rounds_left(),
		"ai_turn": over == null and current >= 0 and not players[current]["human"],
		"waiting": "battle" if pending_battle != null else ""}


## "" se p può usare i comandi di rifornimento adesso, altrimenti il motivo
func _supply_check(p: int) -> String:
	if over != null:
		return "Partita finita"
	if not _valid_player(p):
		return "Giocatore non attivo"
	if p != current:
		return "Non è il tuo turno"
	if pending_battle != null:
		return "Battaglia in attesa"
	if phase != "rifornimento":
		return "Solo nella fase di rifornimento"
	return ""


func _turn_check(p: int) -> String:
	if over != null:
		return "Partita finita"
	if not _valid_player(p):
		return "Giocatore non attivo"
	if p != current:
		return "Non è il tuo turno"
	if pending_battle != null:
		return "Battaglia in attesa"
	return ""


func _set_phase(ph: String) -> void:
	if phase == ph:
		return
	phase = ph
	emit_event("phase", {"player": current, "phase": ph})


## Inizio del turno di p: reddito, mantenimento, rinforzi, milizia, occupazione
func _begin_turn(p: int) -> void:
	current = p
	phase = "rifornimento"
	attack_used = false
	move_used = false
	_turn_steps = 0
	_ai_timer = 0.0
	_turn_started = true
	var P: Dictionary = players[p]
	_vis_cache.clear()
	_recompute_supply()
	_compute_rates()
	# reddito del turno (petrolio al netto del mantenimento)
	for k in Data.RES_KEYS:
		P["res"][k] += P["rates"][k]
	if P["res"]["oil"] <= 0:
		P["res"]["oil"] = 0.0
		P["low_oil"] = P["rates"]["oil"] < 0
	else:
		P["low_oil"] = false
	P["card_cd"] = 0.0
	# rinforzi
	var n := reinforce_amount(p)
	P["pool"]["inf"] += n
	if P["human"]:
		add_log("Rinforzi disponibili: " + str(n) + " unità di fanteria da schierare", "good", p)
	emit_event("reinforce", {"player": p, "count": n})
	# mercato: i prezzi tornano verso 1
	if P.get("market") != null:
		for r in Data.MARKET["goods"]:
			P["market"][r] += (1.0 - P["market"][r]) * float(Data.TURN_RULES["market_recover"])
	# milizia del QG
	var hq_t = terr[P["hq"]] if P["hq"] >= 0 else null
	if hq_t != null and hq_t["owner"] == p:
		var have := Data.total_units(hq_t["forces"])
		var add: int = mini(int(Data.TURN_RULES["militia"]), int(Data.ECON["militiaCap"]) - have)
		if add > 0:
			_add_recruits(hq_t, add)
			hq_t["forces"]["inf"] += add
	# territori: milizia locale, occupazione, recupero dal logoramento (solo se riforniti)
	for tr in terr:
		if tr["owner"] != p:
			continue
		if tr["supplied"] and not (int(tr["unrest"]) > 0) and Data.total_units(tr["forces"]) < int(Data.ECON["garrisonCap"]):
			_add_recruits(tr, 1)
			tr["forces"]["inf"] += int(Data.TURN_RULES["garrison"])
		if int(tr["unrest"]) > 0:
			tr["unrest"] = int(tr["unrest"]) - 1
		if int(tr.get("worn", 0)) > 0 and tr["supplied"]:
			tr["worn"] = int(tr["worn"]) - 1
			if int(tr["worn"]) == 0 and P["human"]:
				add_log("Le truppe di " + Data.TERRITORIES[tr["idx"]]["name"] + " si sono riprese dal logoramento", "info", p)
	turn_count += 1
	add_log("Turno di " + P["fac"]["short"] + " (round " + str(round) + ")", "turn", null)
	emit_event("turn_start", {"player": p, "round": round})
	var ai = ais[p] if p < ais.size() else null
	if ai != null and ai.has_method("begin_turn"):
		ai.begin_turn()
	_check_victory()


## Fine del turno del giocatore di turno: la produzione avanza di un turno
func _finish_turn() -> void:
	var p := current
	var P: Dictionary = players[p]
	if P["alive"]:
		if P["research"] != null:
			P["research"]["t"] = int(P["research"]["t"]) + 1
			if int(P["research"]["t"]) >= int(P["research"]["total"]):
				P["tech"] = int(P["research"]["level"])
				P["research"] = null
				P["stats"]["researched"] = int(P["stats"].get("researched", 0)) + 1
				if int(P["tech"]) >= Data.TECH_LEVELS.size() - 1:
					_maybe_headline("tech:" + str(p), P["fac"]["short"] + " raggiunge il massimo livello tecnologico: Tech " + str(P["tech"]) + " · " + Data.TECH_LEVELS[P["tech"]]["name"])
				add_log(P["fac"]["short"] + " raggiunge Tech " + str(P["tech"]) + " · " + Data.TECH_LEVELS[P["tech"]]["name"],
					"good" if P["human"] else "info", null)
				emit_event("researched", {"player": p, "level": P["tech"]})
		for tr in terr:
			if tr["owner"] != p:
				continue
			tr["regroup"] = 0
			var sab: bool = int(tr["sabotage"]) > 0
			if tr["building"] != null and not sab:
				tr["building"]["t"] = int(tr["building"]["t"]) + 1
				if int(tr["building"]["t"]) >= int(tr["building"]["total"]):
					var key: String = tr["building"]["key"]
					tr["buildings"].append(key)
					tr["building"] = null
					P["stats"]["built"] = int(P["stats"].get("built", 0)) + 1
					if p == human_idx:
						add_log(Data.BUILDINGS[key]["name"] + " completato in " + Data.TERRITORIES[tr["idx"]]["name"], "good", p)
					emit_event("built", {"player": p, "terr": tr["idx"], "key": key})
			if tr["queue"].size() > 0 and not sab:
				var keep: Array = []
				var done := Data.empty_forces()
				for q in tr["queue"]:
					q["t"] = int(q["t"]) + 1
					if int(q["t"]) >= int(q["total"]):
						done[q["unit"]] += 1
					else:
						keep.append(q)
				tr["queue"] = keep
				var nd := Data.total_units(done)
				if nd > 0:
					_add_recruits(tr, nd)
					Data.add_forces(tr["forces"], done)
					for k in Data.UNIT_KEYS:
						for _i2 in int(done[k]):
							emit_event("recruited", {"player": p, "terr": tr["idx"], "unit": k})
			if sab:
				tr["sabotage"] = int(tr["sabotage"]) - 1
	_compute_rates()
	emit_event("turn_end", {"player": p, "round": round})


## Fine fase: rifornimento → attacco → spostamento → fine turno
func end_phase() -> Dictionary:
	if over != null:
		return _fail("Partita finita")
	if pending_battle != null:
		return _fail("Battaglia in attesa")
	if phase == "rifornimento":
		_set_phase("attacco")
	elif phase == "attacco":
		_set_phase("spostamento")
	else:
		return end_turn()
	return {"ok": true, "reason": "", "phase": phase}


func end_turn() -> Dictionary:
	if over != null:
		return _fail("Partita finita")
	if pending_battle != null:
		return _fail("Battaglia in attesa")
	_finish_turn()
	_check_victory()
	if over != null:
		return _ok()
	var nxt := _next_alive(current)
	if nxt < 0:
		return _ok()
	if nxt <= current:
		_new_round()
		if over != null:
			return _ok()
	_begin_turn(nxt)
	return _ok()


func _new_round() -> void:
	round += 1
	_vis_cache.clear()
	# carte inganno: i contatori scendono a ogni round; la ricognizione scade da sé (round di validità)
	for tr in terr:
		if int(tr.get("decoy", 0)) > 0:
			tr["decoy"] = int(tr["decoy"]) - 1
		if int(tr.get("silence", 0)) > 0:
			tr["silence"] = int(tr["silence"]) - 1
	for k in intel.keys():
		if int(intel[k]) < round:
			intel.erase(k)
	if not pacts.is_empty() or not pact_offers.is_empty():
		_update_pacts()
	_snapshot()
	emit_event("round", {"round": round})
	_update_context()
	_check_victory()


## Dopo ogni azione: rifornimenti, contesto, vittoria
func _after_action() -> void:
	_vis_cache.clear()
	if _supply_dirty:
		_recompute_supply()
	_compute_rates()
	_check_victory()
	if _ctx_dirty:
		_update_context()


# ------------------------------------------------------------------ attacco e spostamento
## Toglie dalla scelta quanto serve perché resti almeno 1 unità nel territorio
static func _leave_one(have: Dictionary, f: Dictionary) -> Dictionary:
	var o := Data.clone_forces(f)
	for k in Data.UNIT_KEYS:
		o[k] = clampi(int(o[k]), 0, int(have.get(k, 0)))
	if Data.total_units(have) - Data.total_units(o) >= 1:
		return o
	# lascia a casa un'unità del tipo meno prezioso tra quelli scelti
	for k in ["inf", "drone", "aa", "art", "tank", "heli", "jet"]:
		if int(o[k]) > 0:
			o[k] -= 1
			return o
	return o


static func _oil_for(f: Dictionary) -> float:
	var oil := 0.0
	for k in Data.UNIT_KEYS:
		oil += int(f.get(k, 0)) * float(Data.UNITS[k]["moveOil"])
	return oil


## Bersagli d'attacco da from: [{idx, sea}] (confinanti via terra o rotte marittime, non propri)
func attack_targets(p: int, from: int) -> Array:
	var out: Array = []
	if not _valid_terr(from) or terr[from]["owner"] != p:
		return out
	var T: Dictionary = Data.TERRITORIES[from]
	for j in T["adj"]:
		if terr[j]["owner"] == p:
			continue
		var o: int = terr[j]["owner"]
		if o >= 0 and (in_truce() or has_pact(p, o)):
			continue
		out.append({"idx": j, "sea": T["sea"].has(j)})
	return out


func can_attack(from, to, forces = null) -> Dictionary:
	if not _valid_terr(from) or not _valid_terr(to):
		return _fail("Territorio non valido")
	var p: int = terr[from]["owner"]
	var why := _turn_check(p)
	if why != "":
		return _fail(why)
	if phase == "spostamento" or move_used:
		return _fail("Fase di attacco già conclusa")
	if attack_used:
		return _fail("Hai già attaccato in questo turno")
	if int(terr[from]["regroup"]) > 0:
		return _fail("Truppe in riorganizzazione dopo la conquista")
	if not Data.TERRITORIES[from]["adj"].has(int(to)):
		return _fail("Il bersaglio non confina con il territorio di partenza")
	var o: int = terr[to]["owner"]
	if o == p:
		return _fail("Il bersaglio è già tuo")
	if o >= 0 and in_truce():
		return _fail("Tregua iniziale: puoi attaccare gli altri giocatori dal round " + str(truce_rounds + 1) + " (i neutrali sì)")
	if o >= 0 and has_pact(p, o):
		return _fail(_pact_block_text(p, o))
	if Data.total_units(terr[from]["forces"]) < 2:
		return _fail("Servono almeno 2 unità: una deve restare")
	if forces is Dictionary:
		var f := _sanitize_forces(forces, terr[from]["forces"])
		if Data.total_units(f) == 0:
			return _fail("Nessuna unità scelta")
		if Data.total_units(terr[from]["forces"]) - Data.total_units(f) < 1:
			return _fail("Almeno un'unità deve restare nel territorio")
		if _oil_for(f) > float(players[p]["res"]["oil"]) + 1e-9:
			return _fail("Petrolio insufficiente per muovere i mezzi")
	return _ok()


## Attacco del giocatore di turno: {ok, reason, pending, result}
func attack(from, to, forces = null) -> Dictionary:
	if not _valid_terr(from) or not _valid_terr(to):
		return _fail("Territorio non valido")
	var tr: Dictionary = terr[from]
	var f: Dictionary = _leave_one(tr["forces"], tr["forces"]) if not (forces is Dictionary) else _sanitize_forces(forces, tr["forces"])
	var c := can_attack(from, to, f)
	if not c["ok"]:
		return c
	var p: int = tr["owner"]
	var P: Dictionary = players[p]
	P["res"]["oil"] -= _oil_for(f)
	for k in Data.UNIT_KEYS:
		tr["forces"][k] -= f[k]
	var vet: int = int(tr.get("vet", 0))
	var xp: int = int(tr.get("xp", 0))
	tr["fresh"] = mini(int(tr.get("fresh", 0)), Data.total_units(tr["forces"]))
	_set_phase("attacco")
	attack_used = true
	var defender: int = terr[to]["owner"]
	if defender >= 0:
		_note_aggression(p, defender)
	var sea: bool = Data.TERRITORIES[from]["sea"].has(int(to))
	_anim(p, from, to, f, sea, false)
	emit_event("attack", {"type": "attack", "player": p, "from": from, "to": to, "forces": Data.clone_forces(f), "defender": defender})
	if Data.total_units(terr[to]["forces"]) == 0:
		_capture(to, p, f, {"vet": vet, "xp": xp})
		_after_action()
		return {"ok": true, "reason": "Territorio occupato senza combattere", "pending": false, "result": null}
	var info := {"id": _next_battle, "attacker": p, "defender": defender, "terr": int(to), "from": int(from),
		"forces": Data.clone_forces(f), "sea": sea, "vet": vet, "xp": xp, "human_side": "att"}
	_next_battle += 1
	var human_att: bool = P["human"]
	var human_def: bool = defender >= 0 and players[defender]["human"] and bool(opts.get("ask_defense", true))
	if (human_att or human_def) and not opts["auto_battles"]:
		info["human_side"] = "att" if human_att else "def"
		pending_battle = info
		emit_event("pending", {"battle": info})
		return {"ok": true, "reason": "", "pending": true, "result": null}
	var orig_d := Data.clone_forces(terr[to]["forces"])
	var r := _auto_battle(info)
	_apply_battle(info, info["forces"], orig_d, r["att"], r["def"], r["winner"], false)
	_after_action()
	return {"ok": true, "reason": "", "pending": false, "result": r}


## Previsione per il pannello d'attacco (forze del difensore visibili o stimate dal giocatore di from)
func predict_attack(from: int, to: int, forces: Dictionary) -> Dictionary:
	if not _valid_terr(from) or not _valid_terr(to):
		return {"winner": "def", "attLeft": 0.0, "defLeft": 1.0}
	var p: int = terr[from]["owner"]
	var d = visible_forces(p, to)
	if d == null:
		var n := estimate_forces(p, to)
		d = Data.empty_forces()
		d["inf"] = maxi(0, n if n >= 0 else 10)
	var info := {"attacker": p, "terr": to, "from": from, "sea": Data.TERRITORIES[from]["sea"].has(to), "vet": int(terr[from].get("vet", 0))}
	var m := battle_mods(info, false)
	return Combat.predict_battle(_sanitize_forces(forces, terr[from]["forces"]), d, m["modsA"], m["modsD"])


## Territori propri raggiungibili da from attraverso territori propri (rotte marittime incluse) + ponte aereo
func move_targets(p: int, from: int) -> Array:
	var out: Array = []
	if not _valid_terr(from) or terr[from]["owner"] != p:
		return out
	var seen := {from: true}
	var q: Array = [from]
	while not q.is_empty():
		var a: int = q.pop_front()
		for b in Data.TERRITORIES[a]["adj"]:
			if not seen.has(b) and terr[b]["owner"] == p:
				seen[b] = true
				out.append(b)
				q.append(b)
	if players[p]["tech"] >= 2 and terr[from]["buildings"].has("aeroporto"):
		for t in terr:
			if t["owner"] == p and not seen.has(t["idx"]) and can_airlift(p, from, t["idx"]):
				seen[t["idx"]] = true
				out.append(t["idx"])
	return out


func can_move(from, to, forces = null) -> Dictionary:
	if not _valid_terr(from) or not _valid_terr(to):
		return _fail("Territorio non valido")
	var p: int = terr[from]["owner"]
	var why := _turn_check(p)
	if why != "":
		return _fail(why)
	if move_used:
		return _fail("Hai già spostato truppe in questo turno")
	if from == to:
		return _fail("Scegli un altro territorio")
	if terr[to]["owner"] != p:
		return _fail("La destinazione non è tua")
	if int(terr[from]["regroup"]) > 0:
		return _fail("Truppe in riorganizzazione dopo la conquista")
	if not move_targets(p, from).has(int(to)):
		return _fail("Destinazione non collegata da territori tuoi")
	if Data.total_units(terr[from]["forces"]) < 2:
		return _fail("Servono almeno 2 unità: una deve restare")
	if forces is Dictionary:
		var f := _sanitize_forces(forces, terr[from]["forces"])
		if Data.total_units(f) == 0:
			return _fail("Nessuna unità scelta")
		if Data.total_units(terr[from]["forces"]) - Data.total_units(f) < 1:
			return _fail("Almeno un'unità deve restare nel territorio")
		if _oil_for(f) > float(players[p]["res"]["oil"]) + 1e-9:
			return _fail("Petrolio insufficiente per muovere i mezzi")
	return _ok()


## Spostamento del giocatore di turno (1 per turno): {ok, reason}
func move(from, to, forces) -> Dictionary:
	if not _valid_terr(from):
		return _fail("Territorio non valido")
	var f: Dictionary = _leave_one(terr[from]["forces"], terr[from]["forces"]) if not (forces is Dictionary) else _sanitize_forces(forces, terr[from]["forces"])
	var c := can_move(from, to, f)
	if not c["ok"]:
		return c
	var p: int = terr[from]["owner"]
	var tr: Dictionary = terr[from]
	var dst: Dictionary = terr[to]
	players[p]["res"]["oil"] -= _oil_for(f)
	_merge_vet(dst, f, int(tr.get("vet", 0)), int(tr.get("xp", 0)))
	for k in Data.UNIT_KEYS:
		tr["forces"][k] -= f[k]
	Data.add_forces(dst["forces"], f)
	tr["fresh"] = mini(int(tr.get("fresh", 0)), Data.total_units(tr["forces"]))
	move_used = true
	_set_phase("spostamento")
	var air: bool = can_airlift(p, from, to) and not Data.TERRITORIES[from]["adj"].has(int(to))
	_anim(p, from, to, f, Data.TERRITORIES[from]["sea"].has(int(to)), false, air)
	emit_event("move", {"type": "move", "player": p, "from": from, "to": to, "forces": Data.clone_forces(f)})
	_after_action()
	return _ok()


# ------------------------------------------------------------------ fortificazioni
func fort_level(t: int, kind: String) -> int:
	if not _valid_terr(t) or not Data.FORT.has(kind):
		return 0
	return int(_fort_of(t)[kind])


## Costo del prossimo livello (null se al massimo)
func fort_cost(t: int, kind: String):
	if not Data.FORT.has(kind):
		return null
	var L := fort_level(t, kind) + 1
	if L > Data.FORT_MAX:
		return null
	var c := {}
	for k in Data.FORT[kind]["cost"]:
		c[k] = int(Data.FORT[kind]["cost"][k]) * L
	return c


func can_fortify(p: int, t: int, kind: String) -> Dictionary:
	var why := _supply_check(p)
	if why != "":
		return _fail(why)
	if not Data.FORT.has(kind):
		return _fail("Fortificazione sconosciuta")
	if not _valid_terr(t) or terr[t]["owner"] != p:
		return _fail("Il territorio non è tuo")
	if int(terr[t]["sabotage"]) > 0:
		return _fail("Territorio sabotato")
	var c = fort_cost(t, kind)
	if c == null:
		return _fail("Livello massimo")
	if not can_afford(p, c):
		return _fail("Risorse insufficienti: " + missing_text(p, c))
	return _ok()


func fortify(p: int, t: int, kind: String) -> Dictionary:
	var c := can_fortify(p, t, kind)
	if not c["ok"]:
		return c
	_pay(p, fort_cost(t, kind))
	var F := _fort_of(t)
	F[kind] = int(F[kind]) + 1
	if p == human_idx:
		add_log(str(Data.FORT[kind]["name"]) + " livello " + str(F[kind]) + " in " + Data.TERRITORIES[t]["name"], "good", p)
	emit_event("fortify", {"player": p, "terr": t, "kind": kind, "level": F[kind]})
	_compute_rates()
	return _ok()


# ------------------------------------------------------------------ ciclo (ritmo dei turni IA e animazioni)
## Record di animazione (game.divisions): nessun effetto di gioco
func _anim(p: int, from: int, to: int, f: Dictionary, sea: bool, retreat: bool, airlift: bool = false) -> void:
	divisions.append({"id": _next_div, "owner": p, "from": int(from), "to": int(to), "forces": Data.clone_forces(f), "t": 0.0, "total": ANIM_DUR,
		"sea": sea, "airlift": airlift, "retreat": retreat, "anim": true,
		"x": float(Data.TERRITORIES[from]["x"]), "y": float(Data.TERRITORIES[from]["y"]),
		"vet": 0, "xp": 0})
	_next_div += 1
	if divisions.size() > 24:
		divisions = divisions.slice(divisions.size() - 24)


func _advance_anims(dt: float) -> void:
	if divisions.is_empty():
		return
	var keep: Array = []
	for d in divisions:
		d["t"] = minf(d["total"], d["t"] + dt)
		var A: Dictionary = Data.TERRITORIES[d["from"]]
		var B: Dictionary = Data.TERRITORIES[d["to"]]
		var f: float = d["t"] / d["total"] if d["total"] > 0 else 1.0
		var bx: float = B["x"]
		if _is_wrap(d["from"], d["to"]) and absf(B["x"] - A["x"]) > Data.MAP_W / 2.0:
			bx = B["x"] + (-Data.MAP_W if B["x"] > A["x"] else Data.MAP_W)
		d["x"] = fposmod(A["x"] + (bx - A["x"]) * f, Data.MAP_W)
		d["y"] = A["y"] + (B["y"] - A["y"]) * f
		if d["t"] < d["total"]:
			keep.append(d)
	divisions = keep


## real_dt: secondi reali. Avanza le animazioni e il ritmo delle azioni dell'IA di turno (l'umano gioca con i comandi).
func update(real_dt: float) -> void:
	if paused or over != null:
		return
	var dt := maxf(0.0, real_dt)
	time += dt
	_advance_anims(dt)
	if effects.size() > 0:
		effects = effects.filter(func(e): return time - e["born"] <= e["dur"])
	if pending_battle != null:
		return
	var delay: float = ai_step_delay / maxf(0.1, speed if speed > 0 else 1.0)
	if delay <= 0.0:
		_run_ai(4000)
		return
	if is_human_turn():
		return
	_ai_timer += dt
	var guard := 0
	while _ai_timer >= delay and guard < 8:
		_ai_timer -= delay
		guard += 1
		if not _ai_step():
			break


## Compatibilità: come update (dt in secondi reali)
func step(dt: float) -> void:
	update(dt)


## Completa subito il turno IA in corso (si ferma a una battaglia contro l'umano o al turno dell'umano)
func skip_ai_turn() -> void:
	if over != null or pending_battle != null or is_human_turn():
		return
	var who := current
	var guard := 0
	while over == null and pending_battle == null and current == who and not is_human_turn() and guard < AI_MAX_STEPS + 5:
		guard += 1
		if not _ai_step():
			break


## Senza ritardo: esegue il turno IA in corso fino alla fine (al più un turno per chiamata; si ferma al turno
## dell'umano, a una battaglia in attesa o alla fine della partita)
func _run_ai(max_steps: int) -> void:
	var n := 0
	var who := current
	while n < max_steps and over == null and pending_battle == null and not is_human_turn():
		n += 1
		if not _ai_step() or current != who:
			break


## Un'azione dell'IA di turno. false se non si può proseguire (umano di turno, battaglia, fine partita).
func _ai_step() -> bool:
	if over != null or pending_battle != null or is_human_turn():
		return false
	var p := current
	if not players[p]["alive"]:
		end_turn()
		return true
	var ai = ais[p] if p < ais.size() else null
	_turn_steps += 1
	if ai == null or _turn_steps > AI_MAX_STEPS:
		if ai != null:
			ai_errors += 0   # turno troppo lungo: chiuso d'ufficio
		end_turn()
		return true
	var more := true
	if ai.has_method("turn_step"):
		more = bool(ai.turn_step())
	else:
		# IA vecchio stile (update a tempo): un pensiero, poi fine turno
		if ai.has_method("update"):
			ai.update(100.0)
		more = false
	if over != null:
		return false
	if pending_battle != null:
		return false
	if not more and current == p:
		end_turn()
	return true


func _check_victory() -> void:
	if over != null:
		return
	var N := Data.TERRITORIES.size()
	var counts: Array = []
	counts.resize(players.size())
	counts.fill(0)
	for tr in terr:
		if tr["owner"] >= 0:
			counts[tr["owner"]] += 1
	var alive: Array = players.filter(func(P): return P["alive"])
	var winner := -1
	var reason := ""
	if alive.size() == 1:
		winner = alive[0]["idx"]
		reason = "Tutti gli avversari sono stati eliminati"
	if winner < 0 and scenario != null:
		var sv := _scenario_victory(counts)
		if not sv.is_empty() and int(sv[0]) >= 0:
			winner = int(sv[0])
			reason = str(sv[1])
	if winner < 0:
		for P in alive:
			if counts[P["idx"]] >= victory_share * N:
				winner = P["idx"]
				reason = "Controllo del " + str(roundi(victory_share * 100)) + "% dei territori del mondo"
				break
	if winner < 0 and mode == "obiettivo":
		for P in alive:
			var o = P["objective"]
			if o == null:
				continue
			var done := false
			if o["type"] == "continents":
				done = true
				for c in o["conts"]:
					if not owns_continent(P["idx"], c):
						done = false
						break
			elif o["type"] == "count":
				done = counts[P["idx"]] >= o["count"]
			elif o["type"] == "eliminate":
				done = bool(o.get("done", false))
			if done:
				winner = P["idx"]
				reason = "Obiettivo segreto completato: " + o["text"]
				break
	if winner < 0 and scenario == null and round_limit > 0 and round > round_limit and not alive.is_empty():
		winner = _best_of(counts, -1)
		reason = "Limite di " + str(round_limit) + " round: controlla più territori"
	if alive.is_empty():
		winner = -1
		reason = "Nessun sopravvissuto"
	if winner >= 0 or alive.is_empty():
		over = {"winner": winner, "reason": reason}
		if siege_idx >= 0 and _siege_pacts() and winner >= 0 and winner != siege_idx:
			var team: Array = []
			for P in players:
				if P["idx"] != siege_idx:
					team.append(P["idx"])
			over["team"] = team   # vittoria di squadra dell'alleanza
		_snapshot()
		add_log(((players[winner]["name"] + " vince! ") if winner >= 0 else "") + reason, "good" if (winner == human_idx and winner >= 0) else "info", null)
		emit_event("victory", {"winner": winner, "reason": reason})


# ------------------------------------------------------------------ cronologia e statistiche
func _snapshot() -> void:
	var n := players.size()
	var s := {"t": round, "round": round, "terr": [], "power": [], "units": [], "income": []}
	var cnt: Array = []
	cnt.resize(n)
	cnt.fill(0)
	var pw: Array = []
	pw.resize(n)
	pw.fill(0.0)
	var un: Array = []
	un.resize(n)
	un.fill(0)
	for tr in terr:
		var o: int = tr["owner"]
		if o < 0:
			continue
		cnt[o] += 1
		pw[o] += Combat.force_power(tr["forces"])
		un[o] += Data.total_units(tr["forces"])
	for i in n:
		var P: Dictionary = players[i]
		s["terr"].append(cnt[i])
		s["power"].append(snappedf(pw[i], 0.01))
		s["units"].append(un[i] + Data.total_units(P["pool"]))
		s["income"].append(snappedf(float(P["rates"]["money"]) if P["alive"] else 0.0, 0.001))
		if cnt[i] > int(P["stats"].get("maxTerr", 0)):
			P["stats"]["maxTerr"] = cnt[i]
	if not history.is_empty() and int(history[-1].get("round", -1)) == round:
		history[-1] = s   # una sola istantanea per round (l'ultima)
	else:
		history.append(s)


## Riepilogo per la schermata finale (anche a partita in corso).
## {time, minutes, over, winner, reason, players:[{idx, faction, name, short, color (html), human, alive, territories,
##   max_territories, conquered, lost, battles_won, battles_lost, units_lost, units_killed, buildings, research, tech,
##   cards_played, peak_power, eliminated_at (s, -1 se vivo)}]}
func stats_summary() -> Dictionary:
	var out := {"time": time, "minutes": time / 60.0, "round": round, "rounds": round, "over": over.duplicate() if over != null else null,
		"winner": int(over["winner"]) if over != null else -1, "reason": str(over["reason"]) if over != null else "", "players": []}
	for P in players:
		var st: Dictionary = P["stats"]
		var i: int = P["idx"]
		var mx: int = int(st.get("maxTerr", 0))
		var peak := 0.0
		for h in history:
			if i < h["terr"].size():
				mx = maxi(mx, int(h["terr"][i]))
				peak = maxf(peak, float(h["power"][i]))
		var cur := territories_of(i).size()
		out["players"].append({
			"idx": i, "faction": P["faction"], "name": P["name"], "short": P["fac"]["short"], "color": P["color"].to_html(false),
			"human": P["human"], "alive": P["alive"], "territories": cur, "max_territories": maxi(mx, cur),
			"conquered": int(st["conquered"]), "lost": int(st["lost"]),
			"battles_won": int(st["battlesWon"]), "battles_lost": int(st["battlesLost"]),
			"units_lost": int(st["unitsLost"]), "units_killed": int(st["killed"]),
			"buildings": int(st.get("built", 0)), "research": int(st.get("researched", 0)), "tech": int(P["tech"]),
			"cards_played": int(st.get("cardsPlayed", 0)), "peak_power": peak,
			"eliminated_at": float(st.get("eliminatedAt", -1.0)),
		})
	return out


# ------------------------------------------------------------------ eventi di contesto ("headline")
const CONT_ART := {"NA": ["il ", "del "], "SA": ["il ", "del "], "EU": ["l'", "dell'"], "AF": ["l'", "dell'"],
	"AS": ["l'", "dell'"], "OC": ["l'", "dell'"]}
const MILESTONE_TEXT := {0.25: "un quarto del mondo", 0.4: "il 40% del mondo", 0.5: "metà del mondo"}


func _headline(text: String) -> void:
	add_log(text, "headline", null)
	emit_event("headline", {"text": text})


func _maybe_headline(key: String, text: String) -> void:
	if _milestones.has(key):
		return
	_milestones[key] = true
	_headline(text)


## silent: registra lo stato senza annunci (inizio partita)
func _update_context(silent: bool = false) -> void:
	_ctx_dirty = false
	# continenti
	for c in Data.CONT_KEYS:
		var o := continent_owner(c)
		var prev: int = int(_cont_hold.get(c, -1))
		_cont_hold[c] = o
		if o == prev:
			continue
		if silent:
			continue
		var cname: String = Data.CONTINENTS[c]["name"]
		var art: Array = CONT_ART[c]
		if o >= 0 and prev >= 0:
			_headline(_pname(o) + " strappa " + art[0] + cname + " a " + _pname(prev) + " (" + Data.CONTINENTS[c]["perkText"] + ")")
		elif o >= 0:
			_headline(_pname(o) + " controlla ora " + art[0] + cname + " (+" + str(Data.CONTINENTS[c]["bonus"]) + " rinforzi, " + Data.CONTINENTS[c]["perkText"] + ")")
		elif prev >= 0 and prev < players.size() and players[prev]["alive"]:
			_headline(_pname(prev) + " perde il controllo " + art[1] + cname)
	# fronte caldo: molte battaglie nello stesso continente in poco tempo
	while _battle_times.size() > 0 and round - int(_battle_times[0][0]) >= HOT_WINDOW:
		_battle_times.pop_front()
	var per := {}
	for b in _battle_times:
		per[b[1]] = per.get(b[1], 0) + 1
	for c in per:
		if per[c] >= HOT_BATTLES and round - int(_hot_at.get(c, -1000)) >= HOT_COOLDOWN:
			_hot_at[c] = round
			if not silent:
				_headline("Fronte caldo in " + Data.CONTINENTS[c]["name"] + ": " + str(per[c]) + " battaglie negli ultimi round")
	# quote del mondo e vittoria vicina
	var N := Data.TERRITORIES.size()
	var need := int(ceil(victory_share * N - 1e-9))
	for P in players:
		if not P["alive"]:
			continue
		var n := territories_of(P["idx"]).size()
		for m in MILESTONES:
			var key := str(P["idx"]) + ":" + str(m)
			if n >= m * N and not _milestones.has(key):
				if silent:
					_milestones[key] = true
				else:
					_maybe_headline(key, _pname(P["idx"]) + " controlla ormai " + MILESTONE_TEXT[m])
		var left := need - n
		if left > 0 and left <= 3:
			var key2 := str(P["idx"]) + ":near"
			if silent:
				_milestones[key2] = true
			else:
				_maybe_headline(key2, _pname(P["idx"]) + " è a " + str(left) + (" territorio" if left == 1 else " territori") + " dalla vittoria!")


# ------------------------------------------------------------------ salvataggi
static func _i(v, def: int = 0) -> int:
	if v == null:
		return def
	var x := _num(v)
	if is_nan(x) or is_inf(x):
		return def
	return int(x)


static func _f(v, def: float = 0.0) -> float:
	if v == null:
		return def
	var x := _num(v)
	if is_nan(x) or is_inf(x):
		return def
	return x


static func _fdict(v, keys: Array) -> Dictionary:
	var o := {}
	var src: Dictionary = v if v is Dictionary else {}
	for k in keys:
		o[k] = _f(src.get(k, 0.0))
	return o


static func _ser_sub(v, int_keys: Array, float_keys: Array, str_keys: Array) -> Variant:
	if not (v is Dictionary):
		return null
	var o := {}
	for k in int_keys:
		o[k] = _i(v.get(k))
	for k in float_keys:
		o[k] = _f(v.get(k))
	for k in str_keys:
		o[k] = str(v.get(k, ""))
	return o


static func _ser_cards(arr) -> Array:
	var o: Array = []
	if arr is Array:
		for c in arr:
			if c is Dictionary:
				o.append({"type": str(c.get("type", "inf"))})
	return o


static func _ser_objective(ob) -> Variant:
	if not (ob is Dictionary):
		return null
	var o := {"type": str(ob.get("type", "count")), "text": str(ob.get("text", ""))}
	if ob.has("conts"):
		var cs: Array = []
		for c in ob["conts"]:
			cs.append(str(c))
		o["conts"] = cs
	if ob.has("count"):
		o["count"] = _i(ob["count"])
	if ob.has("target"):
		o["target"] = _i(ob["target"])
	if ob.has("done"):
		o["done"] = bool(ob["done"])
	if ob.has("terrs"):
		var ts: Array = []
		for t in ob["terrs"]:
			ts.append(_i(t))
		o["terrs"] = ts
	if ob.has("need"):
		o["need"] = _i(ob["need"])
	if ob.has("scenario"):
		o["scenario"] = bool(ob["scenario"])
	return o


static func _ser_stats(st) -> Dictionary:
	var o := {}
	if st is Dictionary:
		for k in st:
			o[str(k)] = _f(st[k]) if str(k) == "eliminatedAt" else _i(st[k])
	return o


static func _ser_pending(pb) -> Variant:
	if not (pb is Dictionary):
		return null
	return {"id": _i(pb.get("id")), "attacker": _i(pb.get("attacker"), -1), "defender": _i(pb.get("defender"), -1),
		"terr": _i(pb.get("terr")), "from": _i(pb.get("from")), "forces": _sanitize_forces(pb.get("forces")), "sea": bool(pb.get("sea", false)),
		"vet": clampi(_i(pb.get("vet")), 0, VET_MAX), "xp": maxi(0, _i(pb.get("xp"))),
		"human_side": "def" if str(pb.get("human_side", "att")) == "def" else "att"}


static func _ser_player(P: Dictionary) -> Dictionary:
	return {
		"res": _fdict(P["res"], Data.RES_KEYS), "rates": _fdict(P["rates"], Data.RES_KEYS),
		"tech": _i(P["tech"], 1),
		"research": _ser_sub(P["research"], ["level", "t", "total"], [], []),
		"hq": _i(P["hq"], -1), "alive": bool(P["alive"]),
		"cards": _ser_cards(P["cards"]), "card_cd": _f(P["card_cd"]), "sets_traded": _i(P["sets_traded"]),
		"pool": _sanitize_forces(P["pool"]), "next_reinforce": _f(P["next_reinforce"]),
		"objective": _ser_objective(P["objective"]), "low_oil": bool(P["low_oil"]),
		"stats": _ser_stats(P["stats"]),
		"market": _fdict(P["market"] if P.get("market") != null else {"oil": 1.0, "steel": 1.0, "manpower": 1.0}, Data.MARKET["goods"]),
		"militia_t": _f(P.get("militia_t", 0.0)), "upkeep": _f(P.get("upkeep", 0.0)),
	}


static func _ser_terr(tr: Dictionary) -> Dictionary:
	var bl: Array = []
	for b in tr["buildings"]:
		bl.append(str(b))
	var q: Array = []
	for it in tr["queue"]:
		if it is Dictionary:
			var u := str(it.get("unit", "inf"))
			if Data.UNITS.has(u):
				q.append({"unit": u, "t": maxi(0, _i(it.get("t"))), "total": maxi(1, _i(it.get("total"), 1))})
	return {"owner": _i(tr["owner"], -1), "forces": _sanitize_forces(tr["forces"]), "buildings": bl,
		"building": _ser_sub(tr["building"], ["t", "total"], [], ["key"]), "queue": q,
		"sabotage": maxi(0, _i(tr["sabotage"])), "unrest": maxi(0, _i(tr["unrest"])), "regroup": maxi(0, _i(tr["regroup"])),
		"fort": _ser_fort(tr.get("fort")),
		"supplied": bool(tr["supplied"]), "garrison_t": _f(tr.get("garrison_t", 0.0)),
		"vet": clampi(_i(tr.get("vet")), 0, VET_MAX), "xp": maxi(0, _i(tr.get("xp"))), "fresh": maxi(0, _i(tr.get("fresh"))),
		"worn": clampi(_i(tr.get("worn")), 0, 9), "decoy": clampi(_i(tr.get("decoy")), 0, 9), "silence": clampi(_i(tr.get("silence")), 0, 9)}


static func _ser_fort(f) -> Dictionary:
	var o := {"trench": 0, "mines": 0, "bunker": 0}
	if f is Dictionary:
		for k in Data.FORT_KEYS:
			o[k] = clampi(_i(f.get(k)), 0, Data.FORT_MAX)
	return o


static func _ser_division(d: Dictionary) -> Dictionary:
	return {"id": _i(d.get("id")), "owner": _i(d.get("owner"), -1), "from": _i(d.get("from")), "to": _i(d.get("to")),
		"forces": _sanitize_forces(d.get("forces")), "t": _f(d.get("t")), "total": _f(d.get("total"), MIN_TRAVEL),
		"sea": bool(d.get("sea", false)), "airlift": bool(d.get("airlift", false)), "retreat": bool(d.get("retreat", false)),
		"x": _f(d.get("x")), "y": _f(d.get("y")),
		"vet": clampi(_i(d.get("vet")), 0, VET_MAX), "xp": maxi(0, _i(d.get("xp")))}


static func _ser_event(e: Dictionary) -> Dictionary:
	var pl = e.get("player")
	return {"time": _f(e.get("time")), "round": _i(e.get("round"), 1), "text": str(e.get("text", "")), "type": str(e.get("type", "info")),
		"player": null if pl == null else _i(pl)}


static func _ser_snap(h: Dictionary) -> Dictionary:
	var o := {"t": _i(h.get("t")), "round": _i(h.get("round", h.get("t")))}
	for k in ["terr", "units"]:
		var a: Array = []
		for x in h.get(k, []):
			a.append(_i(x))
		o[k] = a
	for k in ["power", "income"]:
		var a: Array = []
		for x in h.get(k, []):
			a.append(_f(x))
		o[k] = a
	return o


## Stato completo della partita, solo tipi JSON (niente Color/oggetti). Gli effetti grafici non sono salvati.
## Per scriverlo su file usare to_json() (precisione piena dei float).
func serialize() -> Dictionary:
	var pls: Array = []
	for P in players:
		pls.append(_ser_player(P))
	var trs: Array = []
	for tr in terr:
		trs.append(_ser_terr(tr))
	var evs: Array = []
	for e in events:
		evs.append(_ser_event(e))
	var hist: Array = []
	for h in history:
		hist.append(_ser_snap(h))
	var ai_states: Array = []
	for a in ais:
		ai_states.append(a.save_state() if a != null and a.has_method("save_state") else null)
	var bt: Array = []
	for b in _battle_times:
		bt.append([_f(b[0]), str(b[1])])
	var opl: Array = []
	for po in opts["players"]:
		opl.append({"faction": _i(po["faction"]), "human": bool(po["human"]), "difficulty": str(po["difficulty"])})
	var ch := {}
	for c in _cont_hold:
		ch[str(c)] = _i(_cont_hold[c], -1)
	var ha := {}
	for c in _hot_at:
		ha[str(c)] = _f(_hot_at[c])
	return {
		"version": SAVE_VERSION, "game": "frontline_dominion_3d",
		"opts": {"players": opl, "mode": str(opts["mode"]), "distribution": str(opts["distribution"]), "seed": str(opts["seed"]),
			"ask_defense": bool(opts["ask_defense"]), "auto_battles": bool(opts["auto_battles"]), "fog": bool(opts.get("fog", false)),
			"fog_mode": str(fog_mode) if (fog_mode != "none" or not fog) else "full", "scenario": str(opts.get("scenario", ""))},
		"intel": _ser_times(intel),
		"scen": {"siege_by": _siege_by, "hold_owner": _hold_owner, "hold_since": _hold_since, "targets": scenario_targets.duplicate()},
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"time": time, "speed": speed, "paused": paused,
		"turn": {"round": round, "current": current, "phase": phase, "attack_used": attack_used, "move_used": move_used,
			"truce_rounds": truce_rounds, "round_limit": round_limit, "ai_step_delay": ai_step_delay, "turn_count": turn_count,
			"ai_timer": _ai_timer, "turn_steps": _turn_steps},
		"over": null if over == null else {"winner": _i(over["winner"], -1), "reason": str(over["reason"])},
		"human_idx": human_idx, "ai_errors": ai_errors,
		"players": pls, "terr": trs, "pending_battle": _ser_pending(pending_battle),
		"deck": _ser_cards(deck), "discard": _ser_cards(discard),
		"next_div": _next_div, "next_battle": _next_battle, "supply_dirty": _supply_dirty,
		"events": evs, "history": hist,
		"context": {"cont_hold": ch, "milestones": _milestones.keys(), "battle_times": bt, "hot_at": ha, "dirty": _ctx_dirty},
		"ais": ai_states,
		"pacts": _ser_pacts(pacts, "a", "b"), "pact_offers": _ser_pacts(pact_offers, "from", "to"),
		"pact_cd": _ser_times(_pact_cd), "aggr": _ser_times(_aggr),
	}


static func _ser_pacts(arr, ka: String, kb: String) -> Array:
	var o: Array = []
	if arr is Array:
		for pc in arr:
			if pc is Dictionary and pc.has(ka) and pc.has(kb):
				o.append({ka: _i(pc[ka], -1), kb: _i(pc[kb], -1), "until": _f(pc.get("until"))})
	return o


static func _ser_times(d) -> Dictionary:
	var o := {}
	if d is Dictionary:
		for k in d:
			o[str(k)] = _f(d[k])
	return o


## Testo JSON del salvataggio (float a precisione piena: la partita ricaricata prosegue identica).
func to_json() -> String:
	return JSON.stringify(serialize(), "", false, true)


## Ricrea la partita da serialize() (anche dopo JSON.parse_string). null se il salvataggio non è valido.
## I segnali vanno ricollegati dal chiamante; una battaglia manuale in corso torna "in attesa".
static func deserialize(d) -> Game:
	last_load_error = ""
	if not (d is Dictionary) or not (d.get("players") is Array) or not (d.get("terr") is Array) or not (d.get("opts") is Dictionary):
		last_load_error = "Salvataggio non valido o danneggiato"
		return null
	if _i(d.get("version"), 1) < SAVE_MIN_VERSION or not (d.get("turn") is Dictionary):
		last_load_error = "Salvataggio di una versione precedente (tempo reale): non compatibile con la modalità a turni"
		return null
	if _i(d.get("version"), 1) > SAVE_VERSION:
		last_load_error = "Salvataggio di una versione più recente del gioco"
		return null
	var so: Dictionary = d["opts"]
	if not (so.get("players") is Array) or so["players"].size() != d["players"].size() or so["players"].is_empty():
		return null
	if d["terr"].size() != Data.TERRITORIES.size():
		return null
	# migrazione v2 → v3: il vecchio bool fog diventa nebbia totale/nessuna; worn/decoy/silence/intel partono a zero
	var o := {"players": so["players"], "mode": str(so.get("mode", "conquista")), "distribution": str(so.get("distribution", "regionale")),
		"seed": str(so.get("seed", "1")).to_int(), "ask_defense": bool(so.get("ask_defense", false)),
		"auto_battles": bool(so.get("auto_battles", false)), "fog": bool(so.get("fog", false)),
		"fog_mode": str(so.get("fog_mode", "")), "scenario": str(so.get("scenario", "")), "_no_start": true}
	var g := Game.new(o)
	if g.players.size() != d["players"].size():
		last_load_error = "Salvataggio non valido o danneggiato"
		return null
	g._load_state(d)
	return g


static func from_json(text: String) -> Game:
	var j := JSON.new()
	if j.parse(text) != OK:
		last_load_error = "Salvataggio non valido o danneggiato"
		return null
	return deserialize(j.data)


func _load_state(d: Dictionary) -> void:
	rng.seed = str(d.get("rng_seed", "0")).to_int()
	rng.state = str(d.get("rng_state", "0")).to_int()
	time = _f(d.get("time"))
	speed = _f(d.get("speed"), 1.0)
	paused = bool(d.get("paused", false))
	var tn: Dictionary = d["turn"]
	round = maxi(1, _i(tn.get("round"), 1))
	current = clampi(_i(tn.get("current")), 0, players.size() - 1)
	var ph := str(tn.get("phase", "rifornimento"))
	phase = ph if ph in ["rifornimento", "attacco", "spostamento"] else "rifornimento"
	attack_used = bool(tn.get("attack_used", false))
	move_used = bool(tn.get("move_used", false))
	truce_rounds = maxi(0, _i(tn.get("truce_rounds"), truce_rounds))
	round_limit = maxi(0, _i(tn.get("round_limit"), round_limit))
	ai_step_delay = maxf(0.0, _f(tn.get("ai_step_delay"), ai_step_delay))
	turn_count = _i(tn.get("turn_count"))
	_ai_timer = _f(tn.get("ai_timer"))
	_turn_steps = _i(tn.get("turn_steps"))
	_turn_started = true
	var ov = d.get("over")
	over = null if not (ov is Dictionary) else {"winner": _i(ov.get("winner"), -1), "reason": str(ov.get("reason", ""))}
	ai_errors = _i(d.get("ai_errors"))
	for i in players.size():
		var P: Dictionary = players[i]
		var S = d["players"][i]
		if not (S is Dictionary):
			continue
		P["res"] = _fdict(S.get("res"), Data.RES_KEYS)
		P["rates"] = _fdict(S.get("rates"), Data.RES_KEYS)
		P["tech"] = clampi(_i(S.get("tech"), 1), 1, Data.TECH_LEVELS.size() - 1)
		P["research"] = _ser_sub(S.get("research"), ["level", "t", "total"], [], [])
		P["hq"] = _i(S.get("hq"), -1)
		if P["hq"] >= terr.size():
			P["hq"] = -1
		P["alive"] = bool(S.get("alive", true))
		P["cards"] = _ser_cards(S.get("cards"))
		P["card_cd"] = _f(S.get("card_cd"))
		P["sets_traded"] = _i(S.get("sets_traded"))
		P["pool"] = _sanitize_forces(S.get("pool"))
		P["next_reinforce"] = _f(S.get("next_reinforce"), 0.0)
		P["objective"] = _ser_objective(S.get("objective"))
		P["low_oil"] = bool(S.get("low_oil", false))
		var st: Dictionary = P["stats"]
		var ss := _ser_stats(S.get("stats"))
		for k in ss:
			st[k] = ss[k]
		P["market"] = _fdict(S.get("market", {"oil": 1.0, "steel": 1.0, "manpower": 1.0}), Data.MARKET["goods"])
		P["militia_t"] = _f(S.get("militia_t"))
		P["upkeep"] = _f(S.get("upkeep"))
	for i in terr.size():
		var S = d["terr"][i]
		if not (S is Dictionary):
			continue
		var tr: Dictionary = terr[i]
		var t2 := _ser_terr({"owner": S.get("owner", -1), "forces": S.get("forces"),
			"buildings": S.get("buildings") if S.get("buildings") is Array else [],
			"building": S.get("building"), "queue": S.get("queue") if S.get("queue") is Array else [],
			"sabotage": S.get("sabotage"), "unrest": S.get("unrest"), "regroup": S.get("regroup"), "fort": S.get("fort"),
			"supplied": S.get("supplied", true), "garrison_t": S.get("garrison_t"), "vet": S.get("vet"), "xp": S.get("xp"), "fresh": S.get("fresh"),
			"worn": S.get("worn", 0), "decoy": S.get("decoy", 0), "silence": S.get("silence", 0)})
		for k in t2:
			tr[k] = t2[k]
		if tr["owner"] >= players.size():
			tr["owner"] = -1
	divisions = []
	pending_battle = _ser_pending(d.get("pending_battle"))
	if pending_battle != null and (not _valid_terr(pending_battle["terr"]) or not _valid_terr(pending_battle["from"]) \
			or pending_battle["attacker"] < 0 or pending_battle["attacker"] >= players.size()):
		pending_battle = null
	_manual = null
	deck = _ser_cards(d.get("deck"))
	discard = _ser_cards(d.get("discard"))
	_next_div = _i(d.get("next_div"), 1)
	_next_battle = _i(d.get("next_battle"), 1)
	_supply_dirty = bool(d.get("supply_dirty", true))
	events = []
	var el = d.get("events", [])
	if el is Array:
		for e in el:
			if e is Dictionary:
				events.append(_ser_event(e))
	effects = []
	history = []
	var hl = d.get("history", [])
	if hl is Array:
		for h in hl:
			if h is Dictionary:
				history.append(_ser_snap(h))
	var cx = d.get("context")
	if cx is Dictionary:
		_cont_hold = {}
		var ch = cx.get("cont_hold")
		for c in Data.CONT_KEYS:
			_cont_hold[c] = _i(ch.get(c), -1) if ch is Dictionary else continent_owner(c)
		_milestones = {}
		var ml = cx.get("milestones", [])
		if ml is Array:
			for k in ml:
				_milestones[str(k)] = true
		_battle_times = []
		var bl = cx.get("battle_times", [])
		if bl is Array:
			for b in bl:
				if b is Array and b.size() >= 2:
					_battle_times.append([_f(b[0]), str(b[1])])
		_hot_at = {}
		var ha = cx.get("hot_at")
		if ha is Dictionary:
			for c in ha:
				_hot_at[str(c)] = _f(ha[c])
		_ctx_dirty = bool(cx.get("dirty", false))
	else:
		_update_context(true)
	# diplomazia
	var np := players.size()
	pacts = _ser_pacts(d.get("pacts", []), "a", "b").filter(func(pc): return pc["a"] >= 0 and pc["a"] < np and pc["b"] >= 0 and pc["b"] < np and pc["a"] != pc["b"])
	pact_offers = _ser_pacts(d.get("pact_offers", []), "from", "to").filter(func(of): return of["from"] >= 0 and of["from"] < np and of["to"] >= 0 and of["to"] < np)
	_pact_cd = _ser_times(d.get("pact_cd", {}))
	_aggr = _ser_times(d.get("aggr", {}))
	intel = {}
	var il = d.get("intel", {})
	if il is Dictionary:
		for k in il:
			intel[str(k)] = int(_f(il[k]))
	_vis_cache.clear()
	# scenario
	var sc = d.get("scen")
	if sc is Dictionary:
		_siege_by = _i(sc.get("siege_by"), -1)
		_hold_owner = _i(sc.get("hold_owner"), -1)
		_hold_since = _i(sc.get("hold_since"))
		if _siege_by >= players.size():
			_siege_by = -1
		if _hold_owner >= players.size():
			_hold_owner = -1
		var tl = sc.get("targets")
		if tl is Array:
			scenario_targets = []
			for t in tl:
				if _valid_terr(_i(t)):
					scenario_targets.append(_i(t))
	# IA
	var sa = d.get("ais", [])
	for i in ais.size():
		var a = ais[i]
		if a != null and a.has_method("load_state") and sa is Array and i < sa.size() and sa[i] is Dictionary:
			a.load_state(sa[i])
