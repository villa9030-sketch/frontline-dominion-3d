class_name AIController
extends RefCounted
## FRONTLINE DOMINION 3D — Intelligenza artificiale dei giocatori non umani (FASE 6: a turni).
## Usa solo le interrogazioni/comandi pubblici di Game e le funzioni statiche di Combat (predict_battle, combat_mods,
## force_power). Nessun nodo. Game chiama begin_turn() all'inizio del turno e poi turn_step() a ritmo (una azione
## "visibile" per passo); turn_step() restituisce false quando il turno è finito (Game chiama end_turn()).
## Fasi del turno IA: 0 economia (carte, mercato, ricerca, edifici, reclutamento, mercenari, diplomazia) → 1 schieramento
## del pool → 2 fortificazioni → 3 attacco (al più uno: miglior valore atteso, composizione mista) → 4 spostamento → fine.

## Pesi base del reclutamento per fazione (per id)
const MIX := {
	"aan": {"inf": 3.0, "tank": 2.5, "art": 1.5, "aa": 1.0, "heli": 2.5, "jet": 3.0, "drone": 2.0},
	"fo": {"inf": 3.0, "tank": 3.5, "art": 2.5, "aa": 1.0, "heli": 1.0, "jet": 1.0, "drone": 1.0},
	"cp": {"inf": 3.0, "tank": 2.5, "art": 1.5, "aa": 1.0, "heli": 2.5, "jet": 2.0, "drone": 3.0},
	"ul": {"inf": 3.0, "tank": 2.5, "art": 2.0, "aa": 1.0, "heli": 1.5, "jet": 1.0, "drone": 1.0},
}
## Ordine in cui si lasciano unità a presidio (le prime restano a casa)
const KEEP_ORDER := ["inf", "aa", "art", "drone", "tank", "heli", "jet"]

static var _combat: Script = null

var _game_ref: WeakRef     # riferimento debole: Game possiede le IA (niente cicli di RefCounted)
var game:
	get:
		return _game_ref.get_ref() if _game_ref != null else null
var idx: int
var diff: Dictionary
var rng := RandomNumberGenerator.new()
var stage := 5             # fase del turno IA (5 = turno finito / non iniziato)
var plan = null            # attacco pianificato {from, to, score}
var seen := {}             # memoria della potenza nemica vista: t -> potenza
var idle := 0              # turni consecutivi senza attacchi a giocatori (abbassa la prudenza)
var last_pact := -99       # round dell'ultima proposta di patto
var stats := {"turns": 0, "ms": 0.0, "maxMs": 0.0, "attacks": 0, "wins": 0, "builds": 0, "research": 0, "cards": 0,
	"recruits": 0, "moves": 0, "forts": 0, "trades": 0, "mercs": 0, "errors": 0}

# analisi (ricalcolata a ogni passo, non salvata)
var p: Dictionary
var own: Array = []
var own_pow := PackedFloat32Array()
var threat := PackedFloat32Array()     # potenza nemica (giocatori, niente patti) confinante con il mio territorio
var enemy_pow := PackedFloat32Array()  # potenza stimata dei territori non miei
var frontier := PackedByteArray()
var enemy_air := 0.0
var _vcache := {}
var _leader := -1
var _turn_ms := 0.0
var prof := {}             # ms massimi per fase (diagnostica, non salvato)
var _ext_us := 0           # µs spesi fuori dall'IA (risoluzione delle battaglie) nel passo corrente


func _init(g, player_idx: int) -> void:
	_game_ref = weakref(g)
	idx = player_idx
	if _combat == null:
		_combat = load("res://scripts/core/combat.gd")
	var pl = g.players[player_idx] if player_idx < g.players.size() else null
	var dk = pl["difficulty"] if pl != null else "veterano"
	diff = Data.DIFFICULTY.get(dk, Data.DIFFICULTY["veterano"])
	var seed_v: int = ((player_idx + 1) * 2654435761) & 0xFFFFFFFF
	var grng = g.get("rng")
	if grng is RandomNumberGenerator:
		seed_v = seed_v ^ (grng.randi() & 0xFFFFFFFF)
	rng.seed = seed_v


# ---------------------------------------------------------------------------- salvataggio
func save_state() -> Dictionary:
	var sn := {}
	for t in seen:
		sn[str(t)] = float(seen[t])
	var st := {}
	for k in stats:
		st[str(k)] = stats[k]
	var pl = null
	if plan is Dictionary:
		pl = {"from": int(plan["from"]), "to": int(plan["to"]), "score": float(plan.get("score", 0.0))}
	return {"idx": idx, "rng_seed": str(rng.seed), "rng_state": str(rng.state), "stage": stage, "plan": pl, "seen": sn,
		"idle": idle, "last_pact": last_pact, "stats": st}


func load_state(d: Dictionary) -> void:
	rng.seed = str(d.get("rng_seed", "0")).to_int()
	rng.state = str(d.get("rng_state", "0")).to_int()
	stage = clampi(int(d.get("stage", 5)), 0, 5)
	var pl = d.get("plan")
	plan = {"from": int(pl.get("from", -1)), "to": int(pl.get("to", -1)), "score": float(pl.get("score", 0.0))} if pl is Dictionary else null
	seen = {}
	var sn = d.get("seen", {})
	if sn is Dictionary:
		for k in sn:
			seen[int(str(k))] = float(sn[k])
	idle = int(d.get("idle", 0))
	last_pact = int(d.get("last_pact", -99))
	var st = d.get("stats", {})
	if st is Dictionary:
		for k in st:
			var key := str(k)
			stats[key] = float(st[k]) if (key == "ms" or key == "maxMs") else int(st[k])


# ---------------------------------------------------------------------------- ciclo del turno
func begin_turn() -> void:
	stage = 0
	plan = null
	_turn_ms = 0.0
	stats["turns"] += 1


## Un passo del turno (almeno un'azione visibile, se c'è). false = turno finito.
func turn_step() -> bool:
	var g = game
	if g == null or g.over != null or not g.players[idx]["alive"]:
		return false
	if g.current != idx:
		return false
	var t0 := Time.get_ticks_usec()
	_ext_us = 0
	var acted := false
	while stage < 5 and not acted:
		var s := stage
		stage += 1
		var ts := Time.get_ticks_usec()
		_analyze()
		if own.is_empty():
			stage = 5
			break
		match s:
			0:
				_do_economy()   # invisibile: si prosegue con lo schieramento nello stesso passo
			1:
				acted = _do_deploy()
			2:
				acted = _do_fortify()
			3:
				acted = _do_attack()
				if not acted and g.phase == "rifornimento":
					g.end_phase()
					acted = true
			4:
				acted = _do_move()
		var sms := (Time.get_ticks_usec() - ts) / 1000.0
		var key := "st%d" % s
		if sms > float(prof.get(key, 0.0)):
			prof[key] = sms
		if g.pending_battle != null or g.over != null:
			break
	var ms := (Time.get_ticks_usec() - t0 - _ext_us) / 1000.0   # senza la risoluzione della battaglia (Combat)
	stats["ms"] += ms
	_turn_ms += ms
	if _turn_ms > stats["maxMs"]:
		stats["maxMs"] = _turn_ms
	return stage < 5


# ---------------------------------------------------------------------------- analisi
func _pow(f) -> float:
	return float(_combat.force_power(f)) if f != null else 0.0


func _analyze() -> void:
	var g = game
	var N: int = g.terr.size()
	p = g.players[idx]
	own = g.territories_of(idx)
	own_pow.resize(N)
	threat.resize(N)
	enemy_pow.resize(N)
	frontier.resize(N)
	enemy_air = 0.0
	_vcache.clear()
	_leader = -1
	for q in g.players:
		if q["alive"] and q["idx"] != idx and g.is_leader(q["idx"]):
			_leader = q["idx"]
	var truce: bool = g.in_truce()
	for t in N:
		var tr: Dictionary = g.terr[t]
		own_pow[t] = 0.0
		threat[t] = 0.0
		frontier[t] = 0
		if tr["owner"] == idx:
			own_pow[t] = _pow(tr["forces"])
			enemy_pow[t] = 0.0
		else:
			enemy_pow[t] = _est_pow(t)
			if tr["owner"] >= 0:
				var vf = g.visible_forces(idx, t)
				if vf != null:
					enemy_air += float(vf["heli"] + vf["jet"] + vf["drone"])
	for t in own:
		for j in Data.TERRITORIES[t]["adj"]:
			var o: int = g.terr[j]["owner"]
			if o == idx:
				continue
			frontier[t] = 1
			if o >= 0 and not g.has_pact(idx, o):
				threat[t] += enemy_pow[j] * (0.5 if truce else 1.0)


## Potenza stimata di un territorio non mio (nebbia: memoria o stima)
func _est_pow(t: int) -> float:
	var g = game
	var vf = g.visible_forces(idx, t)
	if vf != null:
		var pw := _pow(vf)
		seen[t] = pw
		return pw
	if seen.has(t):
		return float(seen[t]) * 1.15
	var n: int = g.estimate_forces(idx, t)
	if n >= 0:
		return float(n) * 1.3
	return 14.0


## Forze del difensore usate nelle previsioni (visibili, altrimenti fanteria equivalente alla stima)
func _def_forces(t: int) -> Dictionary:
	var g = game
	var vf = g.visible_forces(idx, t)
	if vf != null:
		return vf
	var f := Data.empty_forces()
	f["inf"] = maxi(1, roundi(_est_pow(t)))
	return f


# ---------------------------------------------------------------------------- economia
func _reserve() -> Dictionary:
	# riserva per la ricerca imminente
	var g = game
	var o := {"money": 0.0, "oil": 0.0, "steel": 0.0, "manpower": 0.0}
	if p["research"] == null:
		var rc = g.research_cost(idx)
		if rc != null and int(p["tech"]) < 4 and g.round >= 3:
			for k in rc["cost"]:
				o[k] = float(rc["cost"][k]) * 0.6
	return o


func _do_economy() -> void:
	var g = game
	_do_diplomacy()
	_do_cards()
	_do_market()
	# ricerca
	if p["research"] == null:
		var rc = g.research_cost(idx)
		if rc != null and g.can_afford(idx, rc["cost"]) and (int(p["tech"]) < 3 or g.round >= 8):
			if _ok(g.research(idx)):
				stats["research"] += 1
	_do_build()
	_do_recruit()
	_do_mercs()


func _do_market() -> void:
	var g = game
	var R: Dictionary = p["res"]
	# scorte da tenere: acciaio e manodopera per i mezzi, petrolio per mantenimento e spostamenti
	var keep := {"oil": 90.0 + maxf(0.0, -float(p["rates"]["oil"])) * 3.0, "steel": 140.0, "manpower": 80.0}
	for _k in 5:
		if R["money"] < 260:
			var best := ""
			var amt := 0.0
			for r in Data.MARKET["goods"]:
				var spare: float = R[r] - keep[r]
				if spare >= float(Data.MARKET["lot"]) and spare > amt:
					best = r
					amt = spare
			if best == "" or not _ok(g.trade(idx, best, "sell")):
				break
			stats["trades"] += 1
		elif R["money"] > 600 and R["steel"] < 80:
			if float(g.market_price(idx, "steel", "buy")) < R["money"] - 350 and _ok(g.trade(idx, "steel", "buy")):
				stats["trades"] += 1
			else:
				break
		else:
			break


func _do_cards() -> void:
	var g = game
	var fs = g.find_set(idx)
	if fs == null:
		return
	# golpe su un territorio nemico debole e prezioso
	if not g.in_truce():
		var best := -1
		var bs := 0.0
		for t in own:
			for j in Data.TERRITORIES[t]["adj"]:
				var tr: Dictionary = g.terr[j]
				if tr["owner"] < 0 or tr["owner"] == idx or g.has_pact(idx, tr["owner"]):
					continue
				if Data.total_units(tr["forces"]) > Data.GOLPE_MAX or g.players[tr["owner"]]["hq"] == j:
					continue
				var v := _value(j)
				if v > bs:
					bs = v
					best = j
		if best >= 0 and bs >= 10.0 and _ok(g.play_cards(idx, fs, "golpe", best)):
			stats["cards"] += 1
			return
	# carte inganno (docs/omogeneita.md §5): solo con la nebbia, e non sempre (i rinforzi restano la scelta principale)
	if bool(g.get("fog")) and rng.randf() < 0.5 and _do_deceit(fs):
		stats["cards"] += 1
		return
	if _ok(g.play_cards(idx, fs, "rinforzi", -1)):
		stats["cards"] += 1


## Ricognizione sul bersaglio di maggior valore che non vedo; silenzio radio sulla frontiera più minacciata se debole;
## divisione falsa su una frontiera debole accanto a un nemico forte. true se ha giocato.
func _do_deceit(fs) -> bool:
	var g = game
	var best := -1
	var bs := 0.0
	for t in own:
		for j in Data.TERRITORIES[t]["adj"]:
			var tr: Dictionary = g.terr[j]
			if tr["owner"] < 0 or tr["owner"] == idx or g.has_pact(idx, tr["owner"]):
				continue
			if g.visible_forces(idx, j) != null or g.has_intel(idx, j):
				continue
			var v := _value(j)
			if v > bs:
				bs = v; best = j
	if best >= 0 and bs >= 9.0 and _ok(g.play_cards(idx, fs, "ricognizione", best)):
		return true
	var weak := -1
	var wr := 0.0
	for t in own:
		if frontier[t] == 0 or int(g.terr[t].get("silence", 0)) > 0 or int(g.terr[t].get("decoy", 0)) > 0:
			continue
		var r: float = threat[t] / maxf(1.0, own_pow[t])
		if r > wr:
			wr = r; weak = t
	if weak >= 0 and wr > 1.2:
		var op := "silenzio" if wr > 2.0 else "finta"
		if _ok(g.play_cards(idx, fs, op, weak)):
			return true
	return false


func _do_diplomacy() -> void:
	var g = game
	var h: int = g.human_idx
	if h < 0 or h == idx or not g.players[h]["alive"] or g.has_pact(idx, h) or g.round - last_pact < 4 or g.in_truce():
		return
	var borders := false
	for t in own:
		for j in Data.TERRITORIES[t]["adj"]:
			if g.terr[j]["owner"] == h:
				borders = true
				break
		if borders:
			break
	if not borders:
		return
	# sotto pressione su un altro fronte: propone al giocatore un patto per spostare le forze
	if bool(g.pact_evaluation(idx, h)["accept"]):
		last_pact = g.round
		g.propose_pact(idx, h)


func _has(t: int, k: String) -> bool:
	return game.has_building(t, k)


## Base di produzione: il territorio di frontiera più minacciato/da cui si attacca con caserma+fabbrica, altrimenti il QG
func _prod_sites() -> Array:
	var g = game
	var o: Array = []
	for t in own:
		if _has(t, "caserma") or _has(t, "fabbrica") or _has(t, "aeroporto"):
			if int(g.terr[t]["sabotage"]) <= 0:
				o.append(t)
	return o


func _do_build() -> void:
	var g = game
	var money: float = p["res"]["money"]
	if money < 200 or g.round < 2:
		return
	var hq: int = p["hq"]
	var fid: String = p["fac"]["id"]
	var wants: Array = []
	# fabbrica + caserma su un territorio di frontiera forte (base avanzata), aeroporto al QG dal Tech 2, impianti sui ricchi
	var front := _best_front()
	if front >= 0 and front != hq and not _has(front, "caserma"):
		wants.append([front, "caserma"])
	if front >= 0 and front != hq and not _has(front, "fabbrica") and own.size() >= 6:
		wants.append([front, "fabbrica"])
	if int(p["tech"]) >= 2 and hq >= 0 and not _has(hq, "aeroporto") and (fid == "aan" or fid == "cp" or own.size() >= 9):
		wants.append([hq, "aeroporto"])
	if fid == "cp" and hq >= 0 and not _has(hq, "porto"):
		wants.append([hq, "porto"])
	var rich := -1
	var ra := 0.0
	for t in own:
		if frontier[t] == 0 and not _has(t, "impianto") and g.terr[t]["supplied"]:
			var a: float = float(Data.TERRITORIES[t]["amt"]) + (1.0 if t == hq else 0.0)
			if a > ra:
				ra = a
				rich = t
	if rich >= 0 and own.size() >= 5:
		wants.append([rich, "impianto"])
	var n := 0
	for w in wants:
		if n >= 2 or p["res"]["money"] < 260:
			break
		if _ok(g.can_build(idx, w[0], w[1])) and _ok(g.build(idx, w[0], w[1])):
			stats["builds"] += 1
			n += 1


## Territorio di frontiera con più potenza propria (da cui si attacca)
func _best_front() -> int:
	var best := -1
	var bp := -1.0
	for t in own:
		if frontier[t] == 1 and own_pow[t] + threat[t] * 0.3 > bp:
			bp = own_pow[t] + threat[t] * 0.3
			best = t
	return best


func _uses_oil(u: String) -> bool:
	return float(Data.UNITS[u]["upkeep"]) > 0.0


func _do_recruit() -> void:
	var g = game
	var sites := _prod_sites()
	if sites.is_empty():
		return
	# il sito più vicino al fronte (frontiera o minacciato) prima
	sites.sort_custom(func(a, b): return threat[a] + float(frontier[a]) * 5.0 > threat[b] + float(frontier[b]) * 5.0)
	var res: Dictionary = p["res"]
	var rsv := _reserve()
	var mix: Dictionary = MIX.get(str(p["fac"]["id"]), MIX["aan"]).duplicate()
	if enemy_air > 4.0:
		mix["aa"] = float(mix["aa"]) + enemy_air / 4.0
	var oil_ok: bool = res["oil"] > 60.0 or float(p["rates"]["oil"]) > 5.0
	# tipi reclutabili: sito e costo calcolati una volta sola
	var types: Array = []
	for u in Data.UNIT_KEYS:
		if not g.unit_available(idx, u):
			continue
		if _uses_oil(u) and not oil_ok and u != "inf":
			continue
		var bk: String = Data.UNITS[u]["build"]
		var site := -1
		for s2 in sites:
			if _has(s2, bk) and g.terr[s2]["queue"].size() < g.QUEUE_MAX:
				site = s2
				break
		if site >= 0:
			types.append([u, site, float(mix.get(u, 1.0)), g.cost_for(idx, u)])
	var guard := 0
	while guard < 30 and not types.is_empty():
		guard += 1
		var cands: Array = []
		var wsum := 0.0
		for c in types:
			var afford := true
			for k in c[3]:
				if res[k] - float(c[3][k]) < rsv[k]:
					afford = false
					break
			if afford:
				cands.append(c)
				wsum += c[2]
		if cands.is_empty():
			break
		var r := rng.randf() * wsum
		var pick: Array = cands[0]
		for c in cands:
			r -= c[2]
			if r <= 0.0:
				pick = c
				break
		if not _ok(g.recruit(idx, pick[1], pick[0], 1)):
			types.erase(pick)
			continue
		stats["recruits"] += 1


func _do_mercs() -> void:
	var g = game
	if not p["fac"]["mods"].get("mercs", false) or p["res"]["money"] < 420:
		return
	var t := _most_threatened()
	if t >= 0 and _ok(g.hire_mercs(idx, t)):
		stats["mercs"] += 1


func _most_threatened() -> int:
	var best := -1
	var bs := 0.0
	for t in own:
		var s := threat[t] - own_pow[t] * 0.8
		if t == int(p["hq"]):
			s += threat[t] * 0.3
		if s > bs:
			bs = s
			best = t
	return best


# ---------------------------------------------------------------------------- schieramento e fortificazioni
func _do_deploy() -> bool:
	var g = game
	var pool: Dictionary = p["pool"]
	if Data.total_units(pool) == 0:
		return false
	# piano d'attacco con il pool ipoteticamente schierato; altrimenti la base da cui preparare il prossimo attacco
	plan = _choose_attack(true)
	var danger := _most_threatened()
	var target := -1
	var stg := _staging() if plan == null else -1
	var hq := int(p["hq"])
	if hq >= 0 and threat[hq] > 0.0 and own_pow[hq] < threat[hq] * 0.9:
		target = hq   # QG scoperto: prima di tutto lo si difende
	elif danger >= 0 and threat[danger] > own_pow[danger] * 1.2 and (plan == null or danger == hq or rng.randf() < 0.4):
		target = danger
	elif plan != null:
		target = int(plan["from"])
	elif stg >= 0:
		target = stg
	elif danger >= 0:
		target = danger
	else:
		target = _best_front()
	if target < 0:
		target = int(p["hq"]) if int(p["hq"]) >= 0 else own[0]
	return _ok(g.place_pool(idx, target))


func _do_fortify() -> bool:
	var g = game
	if g.round < 2 or str(p["difficulty"]) == "recluta":
		return false
	var money: float = p["res"]["money"]
	if money < 250:
		return false
	var done := 0
	var maxn := 2 if str(p["difficulty"]) == "generale" else 1
	var cands: Array = []
	for t in own:
		if threat[t] <= 0.0:
			continue
		var s: float = threat[t] / maxf(1.0, own_pow[t])
		if t == int(p["hq"]):
			s *= 1.5
		if s > 0.5:
			cands.append([t, s])
	cands.sort_custom(func(a, b): return a[1] > b[1])
	for c in cands:
		if done >= maxn or p["res"]["money"] < 250:
			break
		var t: int = c[0]
		for kind in ["trench", "bunker", "mines"]:
			if kind == "bunker" and t != int(p["hq"]) and g.fort_level(t, "trench") < 2:
				continue
			if _ok(g.fortify(idx, t, kind)):
				stats["forts"] += 1
				done += 1
				break
	return done > 0


# ---------------------------------------------------------------------------- attacco
## Valore strategico di conquistare j (in cache per passo)
func _value(j: int) -> float:
	if _vcache.has(j):
		return _vcache[j]
	var v := _value_raw(j)
	_vcache[j] = v
	return v


func _value_raw(j: int) -> float:
	var g = game
	var T: Dictionary = Data.TERRITORIES[j]
	var tr: Dictionary = g.terr[j]
	var o: int = tr["owner"]
	var v := 6.0 + float(T["amt"]) * 2.0
	var c: String = T["c"]
	# completamento del continente
	var have := 0
	var tot: int = Data.CONT_TERR[c].size()
	for t in Data.CONT_TERR[c]:
		if g.terr[t]["owner"] == idx:
			have += 1
	if have + 1 == tot:
		v += float(Data.CONTINENTS[c]["bonus"]) * 6.0
	else:
		v += float(Data.CONTINENTS[c]["bonus"]) * 2.0 * float(have) / tot
	if o >= 0:
		v += 3.0
		if g.owns_continent(o, c):
			v += float(Data.CONTINENTS[c]["bonus"]) * 3.0
		if int(g.players[o]["hq"]) == j:
			v += 10.0
		if o == _leader:
			v += 4.0
	# obiettivi
	var ob = p["objective"]
	if ob is Dictionary:
		if ob.get("type") == "continents" and ob.get("conts", []).has(c):
			v += 8.0
		elif ob.get("type") == "eliminate" and int(ob.get("target", -1)) == o and o >= 0:
			v += 8.0
		elif ob.get("type") == "hold" and ob.get("terrs", []).has(j):
			v += 25.0
	if g.siege_idx >= 0 and g.siege_idx != idx and o == g.siege_idx:
		v += 8.0
	if g.hold_terrs.has(j):
		v += 12.0
	return v


## Forze da inviare da t (tutto tranne il presidio necessario contro le altre minacce)
func _send_forces(t: int, to: int, extra: Dictionary = {}) -> Dictionary:
	var g = game
	var have := Data.clone_forces(g.terr[t]["forces"])
	Data.add_forces(have, extra)
	var other := 0.0
	for j in Data.TERRITORIES[t]["adj"]:
		var o: int = g.terr[j]["owner"]
		if j != to and o >= 0 and o != idx and not g.has_pact(idx, o):
			other += enemy_pow[j]
	var total := _pow(have)
	var keep_pow := minf(total * 0.35, other * 0.6)
	if t == int(p["hq"]):
		# il QG non resta sguarnito: anche i nemici a due passi possono schierare i rinforzi accanto e attaccare
		keep_pow = minf(total * 0.6, maxf(other * 0.9, _hq_need(to)))
	var keep := Data.empty_forces()
	var kp := 0.0
	keep["inf"] = 0
	# almeno 1 unità
	for u in KEEP_ORDER:
		if have[u] > 0:
			keep[u] = 1
			kp += _pow({u: 1})
			break
	for u in KEEP_ORDER:
		while kp < keep_pow and keep[u] < have[u]:
			keep[u] += 1
			kp += _pow({u: 1})
	var send := Data.empty_forces()
	for u in Data.UNIT_KEYS:
		send[u] = have[u] - keep[u]
	# petrolio per i mezzi
	var oil: float = p["res"]["oil"]
	var need := 0.0
	for u in Data.UNIT_KEYS:
		need += send[u] * float(Data.UNITS[u]["moveOil"])
	if need > oil:
		for u in ["jet", "heli", "tank", "art", "aa", "drone"]:
			while send[u] > 0 and need > oil:
				send[u] -= 1
				need -= float(Data.UNITS[u]["moveOil"])
	return send


## Potenza da tenere nel QG: minaccia confinante (escluso il bersaglio `skip`) + parte di quella a due passi + presidio minimo.
func _hq_need(skip: int = -1) -> float:
	var g = game
	var hq := int(p["hq"])
	if hq < 0:
		return 0.0
	var adj: Array = Data.TERRITORIES[hq]["adj"]
	var near := 0.0
	var far := 0.0
	var seen2 := {}
	for j in adj:
		var o: int = g.terr[j]["owner"]
		if j != skip and o >= 0 and o != idx and not g.has_pact(idx, o):
			near += enemy_pow[j]
		for k in Data.TERRITORIES[j]["adj"]:
			if k == hq or adj.has(k) or seen2.has(k):
				continue
			seen2[k] = true
			var o2: int = g.terr[k]["owner"]
			if o2 >= 0 and o2 != idx and not g.has_pact(idx, o2):
				far += enemy_pow[k]
	return near * 0.9 + far * 0.3 + 3.0


## Miglior attacco possibile ora: {from, to, score, forces} o null. with_pool: aggiunge il pool al territorio di partenza.
func _choose_attack(with_pool: bool) -> Variant:
	var g = game
	var thr: float = (float(diff["margin"]) - 1.0) * 0.65
	thr = maxf(0.05, thr - 0.04 * mini(idle, 6))
	if bool(_combat.tactical):
		thr += 0.1   # la risoluzione tattica premia il difensore più della formula di previsione: margine in più
	var noise: float = float(diff["noise"])
	var pool: Dictionary = p["pool"] if with_pool else {}
	var best = null
	var bs := 0.0
	var quick: Array = []
	for t in own:
		if int(g.terr[t]["regroup"]) > 0:
			continue
		var tot := Data.total_units(g.terr[t]["forces"])
		if tot < 2 and not with_pool:
			continue
		for tg in g.attack_targets(idx, t):
			var j: int = tg["idx"]
			var ap: float = own_pow[t] + (_pow(pool) if with_pool else 0.0)
			var dp: float = enemy_pow[j] * Data.TERRAINS[Data.TERRITORIES[j]["ter"]]["def"]
			if ap < dp * 0.9:
				continue
			quick.append([t, j, _value(j) * (ap / maxf(1.0, dp + ap))])
	quick.sort_custom(func(a, b): return a[2] > b[2])
	var n := 0
	for q in quick:
		if n >= 4:
			break
		n += 1
		var t: int = q[0]
		var j: int = q[1]
		var send := _send_forces(t, j, pool)
		if Data.total_units(send) == 0:
			continue
		var info := {"attacker": idx, "terr": j, "from": t, "sea": Data.TERRITORIES[t]["sea"].has(j), "vet": int(g.terr[t].get("vet", 0))}
		var dfz := _def_forces(j)
		var sp := _pow(send)
		var dpw := _pow(dfz) * float(Data.TERRAINS[Data.TERRITORIES[j]["ter"]]["def"])
		var left := 0.0
		if sp > dpw * 3.0:
			left = 1.0 - 0.7 * dpw / sp   # vittoria certa: niente simulazione
		else:
			var m: Dictionary = g.battle_mods(info, false)
			var pr: Dictionary = _combat.predict_battle(send, dfz, m["modsA"], m["modsD"])
			if pr["winner"] != "att":
				continue
			left = float(pr["attLeft"])
		if left < thr:
			continue
		var v := _value(j)
		# esposizione dopo la conquista
		var expo := 0.0
		for k in Data.TERRITORIES[j]["adj"]:
			var o: int = g.terr[k]["owner"]
			if o >= 0 and o != idx and not g.has_pact(idx, o):
				expo += enemy_pow[k]
		var hold_pow := _pow(send) * left
		if expo > hold_pow * 1.6:
			v *= 0.6
		var s := v * (0.4 + left) * (1.0 + (rng.randf() * 2.0 - 1.0) * noise)
		if s > bs:
			bs = s
			best = {"from": t, "to": j, "score": s, "forces": send}
	return best


## Base da cui preparare il prossimo attacco: il territorio di frontiera con il miglior rapporto valore/forze mancanti
func _staging() -> int:
	var g = game
	var best := -1
	var bs := 0.0
	var margin: float = float(diff["margin"]) + 0.2
	for t in own:
		if frontier[t] == 0:
			continue
		for tg in g.attack_targets(idx, t):
			var j: int = tg["idx"]
			var dp: float = enemy_pow[j] * float(Data.TERRAINS[Data.TERRITORIES[j]["ter"]]["def"])
			var need: float = dp * margin - own_pow[t]
			var s: float = _value(j) / maxf(4.0, need)
			if g.terr[j]["owner"] < 0:
				s *= 1.3   # i neutrali non contrattaccano
			if s > bs:
				bs = s
				best = t
	return best


func _do_attack() -> bool:
	var g = game
	if g.attack_used or g.move_used:
		return false
	var a = _choose_attack(false)
	if a == null:
		idle += 1
		return false
	var tb := Time.get_ticks_usec()
	var r: Dictionary = g.attack(a["from"], a["to"], a["forces"])
	_ext_us += Time.get_ticks_usec() - tb
	if not _ok(r):
		stats["errors"] += 1
		return false
	stats["attacks"] += 1
	idle = 0
	if r.get("result") is Dictionary and r["result"].get("winner") == "att":
		stats["wins"] += 1
	return true


# ---------------------------------------------------------------------------- spostamento
func _do_move() -> bool:
	var g = game
	if g.move_used:
		return false
	_analyze()
	# destinazione: prima il buco più pericoloso del fronte (minaccia scoperta, valore del territorio), altrimenti la base
	# d'attacco migliore per il prossimo turno
	var dest := -1
	var ds := 4.0
	for t in own:
		if frontier[t] == 0 or threat[t] <= 0.0:
			continue
		var need := threat[t] * 1.15 - own_pow[t]
		if t == int(p["hq"]):
			need += threat[t] * 0.3
		need *= 0.6 + 0.08 * float(Data.TERRITORIES[t]["amt"]) * 5.0
		if need > ds:
			ds = need
			dest = t
	if dest < 0:
		dest = _staging()
	if dest < 0:
		ds = 0.0
		for t in own:
			if frontier[t] == 0:
				continue
			var s2 := threat[t] * 1.2 - own_pow[t]
			if s2 > ds:
				ds = s2
				dest = t
	if dest < 0:
		return false
	# sorgente: il territorio con più eccedenza collegato alla destinazione
	var src := -1
	var surplus := 0.0
	for t in own:
		if t == dest or int(g.terr[t]["regroup"]) > 0 or Data.total_units(g.terr[t]["forces"]) < 2:
			continue
		var spare: float = own_pow[t] - (threat[t] * 1.1 if frontier[t] == 1 else 0.0)
		if t == int(p["hq"]):
			spare = own_pow[t] - maxf(threat[t] * 1.1, _hq_need())
		if spare <= surplus + 2.0:
			continue
		if not g.move_targets(idx, t).has(dest):
			continue
		surplus = spare
		src = t
	if src < 0 or surplus < 3.0:
		return false
	var have: Dictionary = g.terr[src]["forces"]
	var send := Data.clone_forces(have)
	if frontier[src] == 1 or src == int(p["hq"]):
		# lascia un presidio contro la minaccia locale (e nel QG anche contro quella a due passi)
		var keep_pow := threat[src] * 1.1
		if src == int(p["hq"]):
			keep_pow = maxf(keep_pow, _hq_need())
		var kp := 0.0
		for u in KEEP_ORDER:
			while kp < keep_pow and send[u] > 0:
				send[u] -= 1
				kp += _pow({u: 1})
	# almeno un'unità resta
	if Data.total_units(have) - Data.total_units(send) < 1:
		for u in KEEP_ORDER:
			if send[u] > 0:
				send[u] -= 1
				break
	if Data.total_units(send) <= 0:
		return false
	var r: Dictionary = g.move(src, dest, send)
	if not _ok(r):
		# petrolio insufficiente: solo la fanteria
		var inf := Data.empty_forces()
		inf["inf"] = mini(send["inf"], have["inf"] - (1 if Data.total_units(have) - send["inf"] < 1 else 0))
		if inf["inf"] <= 0 or not _ok(g.move(src, dest, inf)):
			return false
	stats["moves"] += 1
	return true


static func _ok(r) -> bool:
	return r is Dictionary and bool(r.get("ok", false))
