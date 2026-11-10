class_name BattleSim
extends RefCounted
## FRONTLINE DOMINION 3D — battaglia RTS in tempo reale, sola logica (headless).
## Fase 5 (battaglia tattica, scala R.U.S.E.): piano 4800×2700 px, visibilità per lato con occultamento in copertura,
## imboscate, corazza frontale/laterale/posteriore, artiglieria a lunghissima gittata ma imprecisa. Regole in BattleRules,
## IA in BattleAI. La vista (Battle3D) legge `units`, `shells`, `obs`, `roads`, `blocks`… e consuma `fx` (eventi grafici).

const K := 0.3              # scala del danno per colpo (Fase 5: ×2.9 rispetto al JS, battaglie più letali e brevi)
const MAX_SPRITES := 36     # oltre questo numero di unità per lato: sprite di gruppo
const RETARGET := 0.4
const LEASH := 300.0
const BARRAGE_CD := 20.0
const BARRAGE_SALVOS := 3
const BARRAGE_R := 160.0
const BARRAGE_MUL := 2.0
const END_MSG := 2.0
const STALL := 5.0
const STALL_ATT := 1.1      # stallo/tempo: vince l'attaccante se la sua potenza supera questo multiplo di quella "trincerata" del difensore
const STALL_COVER := 1.5    # ... in cui le unità del difensore in copertura contano ×1.5
const NO_DMG_AI := 90.0
const NO_DMG_HUMAN := 180.0
const MAX_TIME := 300.0        # = BattleRules.BATTLE_T: allo scadere decidono gli obiettivi (docs/omogeneita.md)
const AUTO_MAX_TIME := 300.0   # tetto della risoluzione automatica (s di battaglia)
const AUTO_DT := 1.0           # passo della risoluzione automatica
const SEP_GROUND := 1.0

const IDLE := 0
const MOVE := 1
const ATTACK := 2
const AMOVE := 3
const FIRE := 4             # artiglieria: fuoco d'area su (ox, oy)
const TAU_ := TAU
## ordine delle righe nelle formazioni (carri in testa ... artiglieria in coda)
const BACK := {"tank": 0, "inf": 42, "aa": 105, "drone": 125, "heli": 150, "art": 195, "jet": 265}
## distanza dal fronte di schieramento iniziale (px)
const SPAWN_BACK := {"inf": 0, "tank": 140, "aa": 320, "drone": 380, "heli": 460, "art": 950, "jet": 1050}
# abilità tattiche (solo battaglia manuale)
const SMOKE_T := 10.0       # durata della cortina fumogena
const SMOKE_CD := 40.0      # ricarica
const SMOKE_MUL := 0.7      # −30% danni dal fuoco diretto (non da artiglieria/sbarramenti/bombe)
const SMOKE_R := 40.0       # raggio (px) della nube attorno a ogni unità (solo vista)
const AIR_DELAY := 3.0      # secondi tra la chiamata e lo sgancio
const AIR_BOMBS := 6
const AIR_STEP := 55.0      # distanza (px) tra le bombe lungo la rotta
const AIR_SPLASH := 80.0
const AIR_MUL := 3.0        # danno di una bomba = atk×cd×K del caccia × AIR_MUL (× matrice "jet")
const AIR_R := 150.0        # raggio indicativo dell'area bombardata (cursore)
const CG := 30.0            # cella della griglia di copertura

class Unit extends RefCounted:
	var id: int
	var side: int
	var type: String
	var air: bool
	var stat: bool
	var x: float
	var y: float
	var vx := 0.0
	var vy := 0.0
	var ang := 0.0
	var tur := 0.0
	var hp: float
	var hp_max: float
	var hp_unit: float
	var g: int
	var r: float
	var speed: float
	var range_: float
	var min_range: float
	var splash: float
	var cd: float
	var cd_t: float
	var mul: float
	var M: Dictionary
	var st: Dictionary       # BattleRules.STATS[type]
	var tgt: Unit = null
	var order := 0
	var ox: float
	var oy: float
	var otgt: Unit = null
	var ax: float
	var ay: float
	var ret_t: float
	var nav_t := 0.0
	var direct := true
	var stuck_t := 0.0
	var prev_d := 1e9
	var chk_t := 0.0
	var pass_t := 0.0
	var cap := 0.0
	var sel := false
	var dead := false
	var hit_t := 0.0
	var fire_t := 0.0
	var bob := 0.0
	var smoke_t := 0.0      # > 0: dentro la cortina fumogena
	var hold := false       # mantieni posizione: non insegue i bersagli
	var last_hit := -100.0  # ultimo istante in cui ha subito danni
	# --- Fase 5: visibilità, copertura, imboscate
	var spotted := [false, false]   # visibile al lato 0 / lato 1
	var seen_once := false          # già avvistata dal lato umano (per fx "spotted".first)
	var concealed := false          # nascosta dalla copertura (o dal fumo)
	var conc_r := 0.0               # distanza massima di scoperta quando nascosta
	var view := 0.0                 # raggio di vista attuale
	var view0 := 0.0                # raggio di vista in aperto
	var cover := 0                  # 0 aperto, 1 leggera, 2 pesante
	var zone := 0                   # 0 aperto, 1 bosco, 2 città
	var reveal_t := 0.0             # > 0: rivelata (ha sparato)
	var ambush_t := 0.0             # > 0: bonus d'imboscata
	var hidden_t := 0.0             # s trascorsi nascosta e non avvistata (imboscata pronta oltre AMBUSH_REARM)
	var deploy_t := 0.0             # artiglieria: > 0 si sta piazzando
	var trench := false             # in trincea
	var reverse := false            # in retromarcia (scafo opposto al moto: la vista può farlo arretrare)
	var role := ""                  # IA: "post", "flank", "scout"...
	var rx := 0.0                   # IA: punto assegnato
	var ry := 0.0
	var rt := 0.0                   # IA: istante dell'assegnazione
	var reinf := false              # rinforzo arrivato da un territorio vicino (torna a casa a fine battaglia)
	var escaped := false            # in ritirata ha raggiunto il proprio bordo: salvo (conta tra i superstiti)

class Shell extends RefCounted:
	var on := false
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0
	var t := 0.0
	var T := 1.0
	var dmg := 0.0
	var side := 0
	var splash := 0.0
	var h := 40.0
	var barrage := false
	var scatter := 0.0

var W := 4800.0
var H := 2700.0
var TOP := 138.0
var BOTTOM := 2544.0
var NAV := 40.0

var setup: Dictionary
var seed_: int
var tkey: String
var T: Dictionary
var sea: bool
var coast_ph: float
var time := 0.0
var paused := false
var done := false
var result = null           # null | Dictionary
var ending = null           # null | {winner, t, why}
var hs := -1                # lato umano (0 att, 1 dif, -1 nessuno)
var sides: Array = []
var units: Array = []       # Array[Unit]
var obs: Array = []         # ostacoli {rect, kind, x, y, w, h | R, r, trees | pts, shade, ...}
var forests: Array = []     # i boschi (sottoinsieme di obs, attraversabili)
var roads: Array = []       # Array di Array di Vector2
var blocks: Array = []      # urbano: {x,y,w,h,park}
var streets_x: Array = []
var streets_y: Array = []
var patches: Array = []
var shells: Array = []      # Array[Shell]
var salvos: Array = []
var strikes: Array = []     # bombe del supporto aereo {t, si, x, y}
var sel: Array = []
var groups := {}
var marker = null
var last_dmg := 0.0
var stall_t := 0.0
var check_t := 0.0
var flow_budget := 8
var cnt := [0, 0]
var init := [0, 0]
var bunker_pos: Array = []
var ghosts := [[], []]      # per lato: ultime posizioni note dei nemici non più avvistati {id, type, x, y, t, g}
var cover_spots: Array = [] # punti di copertura percorribili (Vector2) per l'IA
var spot_road := PackedByteArray()  # 1 se il punto di copertura è vicino a una strada (vie d'accesso)
## Fortificazioni del difensore (setup.def.fort): trincee e campi minati.
var fort := {"bunker": 0, "trench": 0, "mines": 0}
var trenches: Array = []    # segmenti {x0, y0, x1, y1} (copertura pesante, meno danni d'artiglieria alla fanteria)
var mines: Array = []       # campi minati {x, y, r, charges, spotted:[bool, bool]} (colpiscono i mezzi dell'attaccante)
var _mine_t := 0.0
var city := Rect2()         # urbano: estensione della città
var relief: BattleRelief    # Fase 7: rilievo condiviso con la vista (quote, linee di vista)
## Eventi grafici per la vista (svuotati da chi li consuma). Disattivabili per i test.
var emit_fx := true
var fx: Array = []
## Il lato i è guidato dall'IA interna anche se umano (demo, risoluzione automatica).
var ai_assist := [false, false]
## Fase 8 — meteo (vedi SPEC3D "Fase 8"): `setup.weather` assente/"" = sereno fisso (test, formula strategica);
## "auto" = piano dal seed (BattleRules.weather_plan); altrimenti il nome di una condizione. La vista legge `weather`,
## `weather_view_mul` e `flares`; consuma gli eventi fx {"e":"weather","kind"} e {"e":"flare","x","y","side","t"}.
var weather := "sereno"
var weather_view_mul := 1.0
var weather_sched: Array = []     # [[t_s, kind], ...] cambiamenti futuri (ordinati)
var flares: Array = []            # razzi illuminanti in volo {x, y, r, until, side}: dentro, la vista torna piena
var _flare_cd := [0.0, 0.0]
var rubble: Array = []            # macerie {x, y, r} (copertura pesante aggiunta dalla vista alla caduta di un edificio)
## Omogeneità (docs/omogeneita.md): obiettivi del campo, luoghi (edifici del territorio), rinforzi, ritirata ordinata.
## objectives[i] = {kind: "hq"|"building"|"bridge"|"ford"|"hill"|"bunker", key, name, x, y, r, owner: -1|0|1, home, hold: [s, s]}
var objectives: Array = []
var landmarks: Array = []         # {key, name, x, y, w, h}: edifici del territorio sul campo (copertura pesante; la vista può disegnarli)
var reinf: Array = [null, null]   # per lato: {forces, t, dir (-1 nord / +1 sud), arrived: bool}
var retreating := [false, false]  # il lato sta ripiegando verso il proprio bordo
var escaped: Array = [{"main": {}, "reinf": {}}, {"main": {}, "reinf": {}}]   # unità salve (ritirata al bordo)
var _obj_t := 0.0
## Modalità veloce (risoluzione automatica): passo interno fino a AUTO_DT, meno calcoli di percorso.
var fast := false
## Profilazione (solo test): microsecondi per sezione.
var prof_on := false
var prof := {}

var _uid := 1
var _mrng := RandomNumberGenerator.new()
var _rng := RandomNumberGenerator.new()
var _cg_w := 0
var _cg_h := 0
var _cgrid: Array = []
var nw := 0
var nh := 0
var nav_block := PackedByteArray()
var _cov := PackedByteArray()   # copertura per cella CG
var _zon := PackedByteArray()   # zona per cella CG
var _cw := 0
var _ch := 0
var _flow_cache := {}
var _flow_full := {}
var _adj := PackedInt32Array()
var _adj_start := PackedInt32Array()
var _flow_order: Array = []
var _nd := Vector2.ZERO
var _vis_t := 0.0
var _sep: Array = []
var _elist := [[], []]   # unità vive per lato (aggiornato a ogni passo)

func _init(s: Dictionary) -> void:
	setup = s
	seed_ = int(s.get("seed", 12345)) & 0x7fffffff
	if seed_ == 0:
		seed_ = 12345
	_mrng.seed = seed_ ^ 0x5A3C9E1
	_rng.seed = seed_ * 31 + 7
	tkey = String(s.get("terrain", "pianura"))
	if not Data.TERRAINS.has(tkey):
		tkey = "pianura"
	T = Data.TERRAINS[tkey]
	NAV = 30.0 if tkey == "urbano" else 40.0
	sea = bool(s.get("sea", false))
	coast_ph = _mrng.randf() * 6.0
	var att: Dictionary = s.get("att", {})
	var def: Dictionary = s.get("def", {})
	hs = 0 if bool(att.get("human", false)) else (1 if bool(def.get("human", false)) else -1)
	var sup: Dictionary = s.get("support", {})
	sides = [_mk_side(0, att, int(sup.get("att", 0))), _mk_side(1, def, int(sup.get("def", 0)))]
	# "condizioni del giorno" (morale, meteo locale, fortuna): ±LUCK sul danno inflitto da ciascun lato
	for S in sides:
		S["luck"] = clampf(1.0 + _mrng.randfn(0.0, BattleRules.LUCK), 0.75, 1.25)
	sides[0]["luck"] = float(sides[0]["luck"]) * BattleRules.ATT_INITIATIVE
	for i in 64:
		shells.append(Shell.new())
	var fo = def.get("fort", {})
	if fo is Dictionary:
		for k in fort:
			fort[k] = clampi(int(fo.get(k, 0)), 0, 3)
	var nb := maxi(maxi(0, int(def.get("bunkers", 0))), [0, 2, 3, 5][fort["bunker"]])
	bunker_pos = _bunker_spots(nb)
	_gen_map()
	_gen_landmarks()
	_build_grids()
	_spawn()
	init = [_count_mobile(0), _count_mobile(1)]
	cnt = init.duplicate()
	for si in 2:
		escaped[si] = {"main": Data.empty_forces(), "reinf": Data.empty_forces()}
		var rs = (att if si == 0 else def).get("reinf")
		if rs is Dictionary and Data.total_units(Data.clone_forces(rs.get("forces", {}))) > 0:
			reinf[si] = {"forces": Data.clone_forces(rs["forces"]), "t": float(rs.get("t", BattleRules.REINF_T[si])),
				"dir": -1 if int(rs.get("dir", -1)) < 0 else 1, "arrived": false}
	_gen_objectives()
	# Fase 8: meteo dal setup (vedi `weather`)
	var wk := String(s.get("weather", ""))
	if wk == "auto":
		var plan := BattleRules.weather_plan(seed_, tkey)
		weather_sched = (plan["changes"] as Array).duplicate()
		set_weather(String(plan["start"]), false)
	elif wk != "" and BattleRules.WEATHER_VIEW.has(wk):
		set_weather(wk, false)
	_flare_cd = [8.0 + _mrng.randf() * 6.0, 14.0 + _mrng.randf() * 8.0]
	_upd_vis(true)

# ---------------------------------------------------------------------------- Fase 8: meteo
## Cambia la condizione meteo (vista × BattleRules.WEATHER_VIEW[kind]); `announce` = evento fx per la vista.
func set_weather(kind: String, announce := true) -> void:
	if not BattleRules.WEATHER_VIEW.has(kind):
		return
	weather = kind
	weather_view_mul = float(BattleRules.WEATHER_VIEW[kind])
	if announce and emit_fx:
		fx.append({"e": "weather", "kind": kind})
	if not units.is_empty():
		_upd_vis(true)

## true se il punto è illuminato da un razzo illuminante (di notte: la vista torna piena).
func lit_at(x: float, y: float) -> bool:
	for f in flares:
		var dx: float = x - f["x"]
		var dy: float = y - f["y"]
		var r: float = f["r"]
		if dx * dx + dy * dy < r * r:
			return true
	return false

## Razzo illuminante sul punto (px sim): per FLARE_T secondi la vista nell'area è piena anche di notte.
func add_flare(x: float, y: float, side: int, r := BattleRules.FLARE_R, dur := BattleRules.FLARE_T) -> void:
	flares.append({"x": x, "y": y, "r": r, "until": time + dur, "side": side})
	if emit_fx:
		fx.append({"e": "flare", "x": x, "y": y, "side": side, "t": dur})

## Di notte ogni lato spara un razzo illuminante ogni FLARE_CD s sopra il nemico più vicino al proprio fronte
## (o sui fantasmi); deterministico (RNG della mappa).
func _upd_weather(dt: float) -> void:
	if not weather_sched.is_empty() and time >= float(weather_sched[0][0]):
		var ch: Array = weather_sched.pop_front()
		set_weather(String(ch[1]))
	if not flares.is_empty():
		flares = flares.filter(func(f): return float(f["until"]) > time)
	if weather != "notte":
		return
	for si in 2:
		_flare_cd[si] -= dt
		if _flare_cd[si] > 0.0:
			continue
		_flare_cd[si] = BattleRules.FLARE_CD[0] + _mrng.randf() * (BattleRules.FLARE_CD[1] - BattleRules.FLARE_CD[0])
		# punto: nemico avvistato più vicino alle proprie unità, altrimenti fantasma, altrimenti davanti al fronte
		var best := Vector2.INF
		var bd := 1e18
		for e in _elist[1 - si]:
			if not e.spotted[si] or e.air:
				continue
			for a in _elist[si]:
				var d: float = (a.x - e.x) * (a.x - e.x) + (a.y - e.y) * (a.y - e.y)
				if d < bd:
					bd = d; best = Vector2(e.x, e.y)
		if best.x == INF:
			var gl: Array = ghosts[si]
			if not gl.is_empty():
				var g: Dictionary = gl[_mrng.randi() % gl.size()]
				best = Vector2(float(g["x"]), float(g["y"]))
		if best.x == INF:
			var c := Vector2.ZERO
			var n := 0
			for a in _elist[si]:
				if not a.air:
					c += Vector2(a.x, a.y); n += 1
			if n == 0:
				continue
			c /= n
			best = c + Vector2(520.0 if si == 0 else -520.0, 0.0)
		best += Vector2(_mrng.randf_range(-120, 120), _mrng.randf_range(-120, 120))
		add_flare(clampf(best.x, 60.0, W - 60.0), clampf(best.y, TOP, BOTTOM), si)

## Macerie di un edificio crollato (coordinate sim, raggio px): copertura pesante per chi ci sta dentro. Economico:
## aggiorna solo le celle toccate della griglia di copertura.
func add_rubble(x: float, y: float, r: float) -> void:
	rubble.append({"x": x, "y": y, "r": r})
	var i0 := clampi(int((x - r) / CG), 0, _cw - 1)
	var i1 := clampi(int((x + r) / CG), 0, _cw - 1)
	var j0 := clampi(int((y - r) / CG), 0, _ch - 1)
	var j1 := clampi(int((y + r) / CG), 0, _ch - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * _cw + i
			if _cov[k] < BattleRules.RUBBLE_COVER:
				_cov[k] = BattleRules.RUBBLE_COVER

## Rompe i riferimenti circolari (bersagli) a fine uso.
func dispose() -> void:
	for u in units:
		u.tgt = null
		u.otgt = null
	units.clear()
	sel.clear()
	groups.clear()
	_sep.clear()

# ---------------------------------------------------------------------------- setup
static func _to_color(c, fallback: Color) -> Color:
	if c is Color:
		return c
	if c is String and String(c) != "":
		return Color(String(c))
	return fallback

func _mk_side(i: int, s: Dictionary, support: int) -> Dictionary:
	var mods: Dictionary = s.get("mods", {})
	var atk_mul := float(mods.get("atk", 1.0))
	# con il contesto tattico (Combat.combat_mods) la difesa del terreno è già data dalla copertura: si toglie il bonus forfettario
	var ctx = mods.get("ctx")
	if i == 1 and ctx is Dictionary and Data.TERRAINS.has(String(ctx.get("ter", ""))):
		atk_mul /= maxf(0.5, float(Data.TERRAINS[String(ctx["ter"])]["def"]))
	var color := _to_color(s.get("color", null), Color("#ef4444") if i else Color("#3b82f6"))
	var human := bool(s.get("human", false))
	var fo: Dictionary = s.get("forces", {})
	# supporto aereo (J): dalla campagna solo con un aeroporto proprio nel territorio o accanto (setup.X.air);
	# senza l'indicazione (test, demo) vale la vecchia regola: caccia/elicotteri nell'esercito o supporto d'artiglieria
	var air: bool
	if s.has("air"):
		air = bool(s["air"])
	else:
		air = int(fo.get("jet", 0)) > 0 or int(fo.get("heli", 0)) > 0 or support > 0
	var naval := maxi(0, int(s.get("naval", 0)))   # batterie navali (porto/flotta): si sommano al supporto d'artiglieria
	return {
		"smoke_cd": 0.0, "air_uses": 1 if air else 0, "air_t": -1.0, "hurt": 0.0,
		"i": i, "name": String(s.get("name", "Difensore" if i else "Attaccante")), "color": color, "human": human,
		"forces": Data.clone_forces(s.get("forces", {})),
		"mods": {"atk": atk_mul, "unit": mods.get("unit", {}), "hp": mods.get("hp", {})},
		"support": maxi(0, support) + naval, "naval": naval, "manual": bool(s.get("manual", false)),
		"barrage_cd": 0.0 if human else (9.0 if i else 6.0),
		"ai": {"phase": "start", "t": 0.5 if i else 0.0, "t0": 0.0, "re": 0.0}, "g": 1,
	}

func _bunker_spots(n: int) -> Array:
	var out := []
	if n <= 0:
		return out
	var cy := (TOP + BOTTOM) / 2.0
	var sp := minf(560.0, (BOTTOM - TOP - 360.0) / maxf(1.0, n - 1))
	for i in n:
		out.append(Vector2(3450 + (i % 2) * 36, cy + (i - (n - 1) / 2.0) * sp))
	return out

func coast(y: float) -> float:
	return 354.0 + 48.0 * sin(y * 0.004 + coast_ph) + 24.0 * sin(y * 0.0123 + 1.3)

func _near_bunker(x: float, y: float, d: float) -> bool:
	for b in bunker_pos:
		if (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) < d * d:
			return true
	return false

func _gen_map() -> void:
	var rng := _mrng
	for i in 70:
		patches.append({"x": rng.randf() * W, "y": rng.randf() * H, "r": 90 + rng.randf() * 330, "a": 0.35 + rng.randf() * 0.45})
	if tkey == "urbano":
		var st := 60.0
		var bw := 244.0
		var bh := 192.0
		var x0 := 954.0
		var x1 := 3885.0
		var bx := x0
		while bx + bw <= x1:
			streets_x.append(bx - st / 2)
			bx += bw + st
		var by := TOP + 48
		while by + bh <= BOTTOM - 18:
			streets_y.append(by - st / 2)
			by += bh + st
		var cx1 := x0
		var cy1 := TOP
		bx = x0
		while bx + bw <= x1:
			by = TOP + 48
			while by + bh <= BOTTOM - 18:
				var blk := {"x": bx, "y": by, "w": bw, "h": bh, "park": false}
				blocks.append(blk)
				cx1 = maxf(cx1, bx + bw); cy1 = maxf(cy1, by + bh)
				if _near_bunker(bx + bw / 2, by + bh / 2, 260) or rng.randf() > 0.82 * float(T["density"]) + 0.05:
					blk["park"] = true
				else:
					var n := 1 + int(rng.randf() * 3)
					var horiz := rng.randf() < 0.5
					var acc := 0.0
					var parts := []
					for k in n:
						var p := 0.6 + rng.randf()
						parts.append(p)
						acc += p
					var off := 0.0
					var L := (bw - 24) if horiz else (bh - 24)
					var gap := 16.0
					var usable := L - gap * (n - 1)
					for k in n:
						var len_: float = usable * parts[k] / acc
						var o: Dictionary
						if horiz:
							o = {"rect": true, "x": bx + 12 + off, "y": by + 12, "w": len_, "h": bh - 24}
						else:
							o = {"rect": true, "x": bx + 12, "y": by + 12 + off, "w": bw - 24, "h": len_}
						o["kind"] = "edificio"
						o["shade"] = 0.75 + rng.randf() * 0.5
						o["ac"] = rng.randf() < 0.7
						o["acx"] = 0.2 + rng.randf() * 0.5
						o["acy"] = 0.2 + rng.randf() * 0.5
						obs.append(o)
						off += len_ + gap
				by += bh + st
			bx += bw + st
		city = Rect2(x0 - st, TOP, cx1 - x0 + 2 * st, cy1 - TOP + st)
		relief = BattleRelief.new(tkey, seed_, W, H, TOP, BOTTOM, sea, coast_ph, bool(setup.get("clear", false)), roads)
	else:
		var y := 900 + rng.randf() * 900
		var road := []
		var x := -60.0
		while x <= W + 240:
			road.append(Vector2(x, y))
			y += (rng.randf() - 0.5) * 150
			y = clampf(y, 600, 2100)
			x += 240
		roads.append(road)
		if rng.randf() < 0.65:
			var r2 := []
			var xx := 1560 + rng.randf() * 1680
			var yy := TOP - 60
			while yy <= BOTTOM + 180:
				r2.append(Vector2(xx, yy))
				xx += (rng.randf() - 0.5) * 180
				yy += 240
			roads.append(r2)
		relief = BattleRelief.new(tkey, seed_, W, H, TOP, BOTTOM, sea, coast_ph, bool(setup.get("clear", false)), roads)
		var kind: String = T["obstacle"]
		if bool(setup.get("clear", false)):
			return   # solo test: campo aperto senza ostacoli
		# boschi attraversabili e più grandi in ogni terreno (copertura); rocce/ghiaccio bloccanti come prima
		var groves := 0
		if kind == "bosco":
			groves = roundi(float(T["density"]) * 60)
		else:
			groves = {"deserto": 4, "montagna": 9, "artico": 5}.get(tkey, 6)
		var rocks := 0 if kind == "bosco" else roundi(float(T["density"]) * 40)
		var tries := 0
		var placed_g := 0
		var placed_r := 0
		while (placed_g < groves or placed_r < rocks) and tries < 900:
			tries += 1
			var forest := placed_g < groves and (placed_r >= rocks or rng.randf() < 0.5)
			var k2 := "bosco" if forest else kind
			var R: float
			if k2 == "bosco":
				R = 70 + rng.randf() * 100
			elif k2 == "roccia":
				R = 32 + rng.randf() * 58
			else:
				R = 40 + rng.randf() * 60
			var ox: float
			if k2 == "bosco":
				ox = 520 + rng.randf() * (W - 1040)
			else:
				ox = 950 + rng.randf() * (W - 1900)
			var oy := TOP + R + 30 + rng.randf() * (BOTTOM - TOP - 2 * R - 60)
			if _near_bunker(ox, oy, R + 150):
				continue
			if near_road(ox, oy, R + 50):
				continue
			if sea and ox < coast(oy) + R + 120:
				continue
			var bad := false
			for o in obs:
				var m: float = o["R"] + R + 50
				if (o["x"] - ox) * (o["x"] - ox) + (o["y"] - oy) * (o["y"] - oy) < m * m:
					bad = true
					break
			if bad:
				continue
			var ob := {"rect": false, "kind": k2, "x": ox, "y": oy, "R": R, "r": R * (0.92 if k2 == "bosco" else 0.9)}
			if k2 == "bosco":
				var trees := []
				var nt := roundi(R * R / 200.0)
				for k in nt:
					var a := rng.randf() * TAU
					var rr := sqrt(rng.randf()) * R * 0.88
					trees.append([ox + cos(a) * rr, oy + sin(a) * rr, 6 + rng.randf() * 5, rng.randf()])
				ob["trees"] = trees
				forests.append(ob)
				placed_g += 1
			else:
				var pts := []
				var kk := 7 + int(rng.randf() * 4)
				for j in kk:
					var a := float(j) / kk * TAU + rng.randf() * 0.3
					var rr := R * (0.75 + rng.randf() * 0.35)
					pts.append(Vector2(ox + cos(a) * rr, oy + sin(a) * rr))
				ob["pts"] = pts
				placed_r += 1
			obs.append(ob)

# ---------------------------------------------------------------------------- omogeneità: luoghi e obiettivi
## Edifici del territorio (setup.buildings) come luoghi nella metà del difensore: copertura pesante per la fanteria,
## obiettivi di battaglia. Non bloccano il movimento (sono "siti": cortili, capannoni, piazzali).
func _gen_landmarks() -> void:
	landmarks.clear()
	var bl = setup.get("buildings", [])
	if not (bl is Array) or bool(setup.get("clear", false)):
		return
	var keys: Array = []
	for k in bl:
		if BattleRules.BUILDING_SITES.has(String(k)) and not keys.has(String(k)):
			keys.append(String(k))
	if keys.is_empty():
		return
	# ordine di importanza: QG a parte; fabbrica/aeroporto/porto/raffineria prima della caserma
	var prio := ["fabbrica", "aeroporto", "porto", "impianto", "caserma", "bunker"]
	keys.sort_custom(func(a, b): return prio.find(a) < prio.find(b))
	var cy := (TOP + BOTTOM) / 2.0
	var spots := [Vector2(W - 1250.0, cy - 520.0), Vector2(W - 1250.0, cy + 520.0), Vector2(W - 800.0, cy), Vector2(W - 1500.0, cy)]
	var n := 0
	for k in keys:
		if n >= spots.size():
			break
		var w := 200.0
		var h := 150.0
		var p: Vector2 = spots[n]
		n += 1
		if sea and p.x < coast(p.y) + 400.0:
			p.x = coast(p.y) + 400.0
		# evita ostacoli bloccanti: sposta verso il bordo del campo se serve
		var tries := 0
		while tries < 12 and _obs_blocked_rect(p.x - w / 2, p.y - h / 2, w, h):
			p.y += 120.0 if (tries % 2 == 0) else -240.0 * ((tries + 1) / 2)
			p.y = clampf(p.y, TOP + 200.0, BOTTOM - 200.0)
			tries += 1
		landmarks.append({"key": k, "name": String(BattleRules.BUILDING_SITES[k]), "x": p.x - w / 2, "y": p.y - h / 2, "w": w, "h": h})

func _obs_blocked_rect(x: float, y: float, w: float, h: float) -> bool:
	for o in obs:
		if o["kind"] == "bosco":
			continue
		if o["rect"]:
			if x < o["x"] + o["w"] and x + w > o["x"] and y < o["y"] + o["h"] and y + h > o["y"]:
				return true
		else:
			var cx := clampf(o["x"], x, x + w)
			var cy := clampf(o["y"], y, y + h)
			if (cx - o["x"]) * (cx - o["x"]) + (cy - o["y"]) * (cy - o["y"]) < o["r"] * o["r"]:
				return true
	return false

## Obiettivi dal contesto (docs/omogeneita.md §1): QG, edifici, ponti/guadi, altura, linea dei bunker. Al massimo OBJ_MAX.
func _gen_objectives() -> void:
	objectives.clear()
	if bool(setup.get("clear", false)) and not bool(setup.get("hq", false)) and landmarks.is_empty():
		return
	var cy := (TOP + BOTTOM) / 2.0
	if bool(setup.get("hq", false)):
		var hx := W - 620.0
		if sea:
			hx = maxf(hx, coast(cy) + 500.0)
		_add_obj("hq", "hq", "Quartier generale", hx, cy, 1)
	var nb := 0
	for lm in landmarks:
		if nb >= 2 or objectives.size() >= BattleRules.OBJ_MAX:
			break
		_add_obj("building", String(lm["key"]), String(lm["name"]), float(lm["x"]) + float(lm["w"]) / 2.0, float(lm["y"]) + float(lm["h"]) / 2.0, 1)
		nb += 1
	if relief != null:
		var xs: Array = []
		for rv in relief.rivers:
			for xg in rv.get("xings", []):
				xs.append(xg)
		# i più vicini al centro del campo
		xs.sort_custom(func(a, b): return absf(float(a["y"]) - cy) < absf(float(b["y"]) - cy))
		var nx := 0
		for xg in xs:
			if nx >= 2 or objectives.size() >= BattleRules.OBJ_MAX:
				break
			var kind := "bridge" if String(xg["k"]) == "bridge" else "ford"
			var x := float(xg["x"])
			_add_obj(kind, kind, "Ponte" if kind == "bridge" else "Guado", x, float(xg["y"]), _home_of(x))
			nx += 1
		if relief.has_relief() and objectives.size() < BattleRules.OBJ_MAX:
			var best := Vector3(-1e9, 0, 0)
			for j in range(2, 14):
				for i in range(3, 29):
					var x: float = W * i / 32.0
					var y: float = TOP + (BOTTOM - TOP) * j / 16.0
					if sea and x < coast(y) + 200.0:
						continue
					var h := relief.height(x, y)
					if h > best.x:
						var far := true
						for o in objectives:
							if Vector2(o["x"], o["y"]).distance_to(Vector2(x, y)) < W * 0.18:
								far = false
						if far:
							best = Vector3(h, x, y)
			if best.x > -1e8 and best.x >= relief.hmin + BattleRules.OBJ_HILL_MIN:
				_add_obj("hill", "hill", "Quota %d" % int(round(best.x + 100.0)), best.y, best.z, _home_of(best.y))
	if not bunker_pos.is_empty() and objectives.size() < BattleRules.OBJ_MAX:
		var bx := 0.0
		var by := 0.0
		for b in bunker_pos:
			bx += b.x; by += b.y
		_add_obj("bunker", "bunker", "Linea dei bunker", bx / bunker_pos.size(), by / bunker_pos.size(), 1)

## Chi "possiede" all'inizio un punto: nella metà del difensore il difensore, altrimenti neutro.
func _home_of(x: float) -> int:
	return 1 if x > W * 0.62 else -1

func _add_obj(kind: String, key: String, name: String, x: float, y: float, home: int) -> void:
	objectives.append({"kind": kind, "key": key, "name": name, "x": x, "y": y, "r": BattleRules.OBJ_R, "owner": home, "home": home,
		"hold": [0.0, 0.0], "contested": false})

## Controllo degli obiettivi: presenza esclusiva di unità di terra nel raggio per OBJ_HOLD s continuativi.
func _upd_objectives(dt: float) -> void:
	for o in objectives:
		var ox: float = o["x"]
		var oy: float = o["y"]
		var r: float = o["r"]
		var near := [0, 0]
		for si in 2:
			for u in _elist[si]:
				if u.air:
					continue
				var dx: float = u.x - ox
				var dy: float = u.y - oy
				if dx * dx + dy * dy < r * r:
					near[si] += 1
					break
		var hold: Array = o["hold"]
		o["contested"] = near[0] > 0 and near[1] > 0
		if o["contested"]:
			hold[0] = 0.0; hold[1] = 0.0
			continue
		for si in 2:
			if near[si] > 0:
				hold[1 - si] = 0.0
				if int(o["owner"]) == si:
					hold[si] = 0.0
				else:
					hold[si] += dt
					if hold[si] >= BattleRules.OBJ_HOLD:
						o["owner"] = si
						hold[si] = 0.0
						if emit_fx:
							fx.append({"e": "objective", "name": o["name"], "side": si, "x": ox, "y": oy, "kind": o["kind"]})

## Obiettivi tenuti per lato: [attaccante, difensore].
func objectives_held() -> Array:
	var h := [0, 0]
	for o in objectives:
		var w: int = int(o["owner"])
		if w >= 0:
			h[w] += 1
	return h

## Esito allo scadere del tempo (o di uno stallo): con obiettivi decide chi ne tiene di più (parità → difensore);
## senza obiettivi (campo pulito) vale la vecchia regola di forza (_stall_winner).
func _time_winner() -> String:
	if objectives.is_empty():
		return _stall_winner()
	var h := objectives_held()
	if h[0] == 0 and h[1] == 0:
		return _stall_winner()   # nessuno ha preso nulla: decide la forza rimasta (difensori in copertura ×1.5)
	return "att" if h[0] > h[1] else "def"

# ---------------------------------------------------------------------------- omogeneità: rinforzi
## I rinforzi dai territori vicini entrano dal proprio bordo (terzo nord o sud del campo) al tempo stabilito.
func _upd_reinf() -> void:
	for si in 2:
		var r = reinf[si]
		if r == null or bool(r["arrived"]) or time < float(r["t"]):
			continue
		r["arrived"] = true
		var f: Dictionary = r["forces"]
		var dir := 1 if si == 0 else -1
		var x0 := 90.0 if si == 0 else W - 90.0
		var yc: float = (TOP + 420.0) if int(r["dir"]) < 0 else (BOTTOM - 420.0)
		var S: Dictionary = sides[si]
		var g: int = int(S["g"])
		var k_i := 0
		var added: Array = []
		for k in Data.UNIT_KEYS:
			var n := int(f.get(k, 0))
			if n <= 0:
				continue
			var count := int(ceil(float(n) / g))
			for j in count:
				var x := x0 + dir * (float(k_i % 3) * 70.0 + (j / 6) * 70.0)
				var y := yc + ((j % 6) - 2.5) * 70.0 + (_mrng.randf() - 0.5) * 20.0
				var u := _add_unit(si, k, clampf(x, 60.0, W - 60.0), clampf(y, TOP + 40.0, BOTTOM - 40.0), mini(g, n - j * g))
				u.reinf = true
				added.append(u)
			k_i += 1
		for u in added:
			if not u.air:
				_push_out(u)
			u.ax = u.x; u.ay = u.y
			_elist[si].append(u)
			# verso il fronte: il difensore raggiunge la propria linea, l'attaccante avanza sul campo
			var fx_ := (W - 1150.0 - 300.0) if si == 1 else 1900.0
			if si == 1:
				u.role = "post"; u.rx = fx_; u.ry = u.y
			order_unit(u, AMOVE, fx_, u.y, null)
		if emit_fx:
			fx.append({"e": "reinf", "side": si, "x": x0, "y": yc, "n": Data.total_units(f)})
		_upd_vis(true)

## Rinforzi non ancora arrivati del lato: secondi mancanti (-1 se nessuno).
func reinf_eta(si: int) -> float:
	var r = reinf[si]
	if r == null or bool(r["arrived"]):
		return -1.0
	return maxf(0.0, float(r["t"]) - time)

# ---------------------------------------------------------------------------- omogeneità: ritirata ordinata
## Ordina a tutto il lato di ripiegare verso il proprio bordo; chi lo raggiunge è salvo (escaped), chi resta combatte.
func _order_retreat(si: int) -> void:
	if retreating[si]:
		return
	retreating[si] = true
	for u in units:
		if u.dead or u.side != si or u.stat:
			continue
		u.hold = false
		u.role = "retreat"
		if u.air:
			_escape(u)
		else:
			order_unit(u, MOVE, _edge_x(si), u.y, null)
	if emit_fx:
		fx.append({"e": "retreat", "side": si})

func _edge_x(si: int) -> float:
	return BattleRules.RETREAT_EDGE * 0.5 if si == 0 else W - BattleRules.RETREAT_EDGE * 0.5

func _upd_retreat(si: int) -> void:
	var ex := _edge_x(si)
	for u in _elist[si]:
		if u.stat or u.dead:
			continue
		var at_edge: bool = (u.x <= BattleRules.RETREAT_EDGE) if si == 0 else (u.x >= W - BattleRules.RETREAT_EDGE)
		if at_edge or u.air:
			_escape(u)
		elif u.order != MOVE or absf(u.ox - ex) > 1.0:
			u.hold = false
			order_unit(u, MOVE, ex, u.y, null)

## Il reparto lascia il campo sano e salvo.
func _escape(u: Unit) -> void:
	if u.dead:
		return
	var n := alive(u)
	var bag: Dictionary = escaped[u.side]["reinf" if u.reinf else "main"]
	bag[u.type] = int(bag.get(u.type, 0)) + n
	u.escaped = true
	u.dead = true; u.hp = 0; u.tgt = null; u.otgt = null
	if u.sel:
		u.sel = false
	for si in 2:
		_drop_ghost(si, u.id)
	if emit_fx:
		fx.append({"e": "escape", "u": u, "x": u.x, "y": u.y, "type": u.type, "side": u.side, "n": n})

## Distanza minima da una strada sterrata (solo terreni non urbani).
func road_dist(x: float, y: float) -> float:
	var best := 1e9
	for road in roads:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var v := b - a
			var l2 := v.length_squared()
			var t := 0.0
			if l2 > 0:
				t = clampf(((x - a.x) * v.x + (y - a.y) * v.y) / l2, 0, 1)
			var d := Vector2(a.x + v.x * t - x, a.y + v.y * t - y).length()
			if d < best:
				best = d
	return best

func near_road(x: float, y: float, d: float) -> bool:
	return road_dist(x, y) < d

func _obs_hit(x: float, y: float, infl: float) -> bool:
	if sea and x < coast(y) + infl:
		return true
	var list = _cgrid[_cgi(x, y)]
	if list == null:
		return false
	for o in list:
		if o["rect"]:
			if x > o["x"] - infl and x < o["x"] + o["w"] + infl and y > o["y"] - infl and y < o["y"] + o["h"] + infl:
				return true
		else:
			var dx: float = x - o["x"]
			var dy: float = y - o["y"]
			var R: float = o["r"] + infl
			if dx * dx + dy * dy < R * R:
				return true
	return false

func _cgi(x: float, y: float) -> int:
	var cx := clampi(int(floor(x / 50.0)), 0, _cg_w - 1)
	var cy := clampi(int(floor(y / 50.0)), 0, _cg_h - 1)
	return cy * _cg_w + cx

func _build_grids() -> void:
	_cg_w = int(ceil(W / 50.0))
	_cg_h = int(ceil(H / 50.0))
	_cgrid = []
	_cgrid.resize(_cg_w * _cg_h)
	var pad := 18.0
	for o in obs:
		if o["kind"] == "bosco":
			continue   # i boschi non bloccano
		var x0: float = o["x"] if o["rect"] else o["x"] - o["r"]
		var y0: float = o["y"] if o["rect"] else o["y"] - o["r"]
		var x1: float = o["x"] + o["w"] if o["rect"] else o["x"] + o["r"]
		var y1: float = o["y"] + o["h"] if o["rect"] else o["y"] + o["r"]
		var cx0 := maxi(0, int(floor((x0 - pad) / 50))); var cx1 := mini(_cg_w - 1, int(floor((x1 + pad) / 50)))
		var cy0 := maxi(0, int(floor((y0 - pad) / 50))); var cy1 := mini(_cg_h - 1, int(floor((y1 + pad) / 50)))
		for cy in range(cy0, cy1 + 1):
			for cx in range(cx0, cx1 + 1):
				var i := cy * _cg_w + cx
				if _cgrid[i] == null:
					_cgrid[i] = []
				_cgrid[i].append(o)
	nw = int(ceil(W / NAV))
	nh = int(ceil(H / NAV))
	nav_block.resize(nw * nh)
	for y in nh:
		for x in nw:
			var px := (x + 0.5) * NAV
			var py := (y + 0.5) * NAV
			nav_block[y * nw + x] = 1 if (py < TOP or py > BOTTOM or _obs_hit(px, py, 7)) else 0
	_build_adj()
	_gen_fort()
	_build_cover()

## Griglia di copertura e zone (bosco/città), punti di copertura per l'IA.
func _build_cover() -> void:
	_cw = int(ceil(W / CG))
	_ch = int(ceil(H / CG))
	_cov = PackedByteArray()
	_cov.resize(_cw * _ch)
	_zon = PackedByteArray()
	_zon.resize(_cw * _ch)
	var put := func(cx0: float, cy0: float, cx1: float, cy1: float, test: Callable, cov: int, zon: int) -> void:
		var i0 := maxi(0, int(floor(cx0 / CG))); var i1 := mini(_cw - 1, int(floor(cx1 / CG)))
		var j0 := maxi(0, int(floor(cy0 / CG))); var j1 := mini(_ch - 1, int(floor(cy1 / CG)))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var px := (i + 0.5) * CG
				var py := (j + 0.5) * CG
				if test.call(px, py):
					var k := j * _cw + i
					if cov > _cov[k]: _cov[k] = cov
					if zon > 0: _zon[k] = zon
	if tkey == "urbano":
		var c := city
		put.call(c.position.x, c.position.y, c.end.x, c.end.y, func(_px, _py): return true, 1, 2)
		for o in obs:
			if not o["rect"]:
				continue
			var ox: float = o["x"]; var oy: float = o["y"]; var ow: float = o["w"]; var oh: float = o["h"]
			put.call(ox - 45, oy - 45, ox + ow + 45, oy + oh + 45, func(px, py):
				var dx := maxf(0.0, maxf(ox - px, px - ox - ow))
				var dy := maxf(0.0, maxf(oy - py, py - oy - oh))
				return dx * dx + dy * dy < 45.0 * 45.0, 2, 2)
	for o in obs:
		if o["rect"]:
			continue
		var ox: float = o["x"]; var oy: float = o["y"]
		if o["kind"] == "bosco":
			var R: float = o["r"]
			put.call(ox - R, oy - R, ox + R, oy + R, func(px, py): return (px - ox) * (px - ox) + (py - oy) * (py - oy) < R * R, 1, 1)
		else:
			var R2: float = o["r"] + 40.0
			put.call(ox - R2, oy - R2, ox + R2, oy + R2, func(px, py): return (px - ox) * (px - ox) + (py - oy) * (py - oy) < R2 * R2, 1, 0)
	for t in trenches:
		var a := Vector2(t["x0"], t["y0"])
		var b2 := Vector2(t["x1"], t["y1"])
		put.call(minf(a.x, b2.x) - 34, minf(a.y, b2.y) - 34, maxf(a.x, b2.x) + 34, maxf(a.y, b2.y) + 34, func(px, py):
			return Geometry2D.get_closest_point_to_segment(Vector2(px, py), a, b2).distance_to(Vector2(px, py)) < 34.0, 3, 0)
	for b in bunker_pos:
		var bx: float = b.x; var by: float = b.y
		put.call(bx - 90, by - 90, bx + 90, by + 90, func(px, py): return (px - bx) * (px - bx) + (py - by) * (py - by) < 90.0 * 90.0, 2, 0)
	# luoghi (edifici del territorio): copertura pesante come un isolato
	for lm in landmarks:
		var lx: float = lm["x"]; var ly: float = lm["y"]; var lw: float = lm["w"]; var lh: float = lm["h"]
		put.call(lx - 30, ly - 30, lx + lw + 30, ly + lh + 30, func(_px, _py): return true, 2, 2)
	# punti di copertura percorribili per l'IA (griglia di 90 px)
	cover_spots.clear()
	var yy := TOP + 60.0
	while yy < BOTTOM - 60:
		var xx := 150.0
		while xx < W - 150:
			if cover_at(xx, yy) > 0 and not _obs_hit(xx, yy, 14.0):
				cover_spots.append(Vector2(xx, yy))
			xx += 90.0
		yy += 90.0
	for t in trenches:
		var a := Vector2(t["x0"], t["y0"])
		var b2 := Vector2(t["x1"], t["y1"])
		var n := maxi(1, int(a.distance_to(b2) / 70.0))
		for k in n + 1:
			var p := a.lerp(b2, float(k) / n)
			if not _obs_hit(p.x, p.y, 14.0):
				cover_spots.append(p)
	spot_road.resize(cover_spots.size())
	for i in cover_spots.size():
		var p: Vector2 = cover_spots[i]
		spot_road[i] = 1 if (not roads.is_empty() and road_dist(p.x, p.y) < 260.0) else 0

## Aggiunge un bosco (attraversabile) e ricalcola copertura e punti di copertura (test, scenari).
func add_forest(x: float, y: float, R: float) -> void:
	var ob := {"rect": false, "kind": "bosco", "x": x, "y": y, "R": R, "r": R * 0.92, "trees": []}
	obs.append(ob)
	forests.append(ob)
	_build_cover()
	_upd_vis(true)

## Copertura del punto: 0 aperto, 1 leggera (bosco, rocce), 2 pesante (città vicino agli edifici, bunker, trincea).
func cover_at(x: float, y: float) -> int:
	var i := clampi(int(x / CG), 0, _cw - 1)
	var j := clampi(int(y / CG), 0, _ch - 1)
	return mini(2, _cov[j * _cw + i])

## true se il punto è in una trincea.
## Fase 7 — quota del suolo (m) nel punto (griglia del rilievo, la stessa usata per le linee di vista).
func height_at(x: float, y: float) -> float:
	return relief.height(x, y) if relief != null else 0.0

## Fase 7 — acqua nel punto (0 asciutto/ponte/guado, >0 nell'alveo di un fiume: le unità a terra rallentano).
func water_at(x: float, y: float) -> float:
	return relief.water_at(x, y) if relief != null else 0.0

## Fase 7 — linea di vista libera tra due punti a terra (il rilievo può nasconderla; velivoli: sempre libera).
func has_los(x0: float, y0: float, x1: float, y1: float) -> bool:
	return relief == null or not relief.has_relief() or relief.los(x0, y0, x1, y1)

## Linea di vista tra due unità (velivoli sempre in vista).
func los_units(a: Unit, b: Unit) -> bool:
	if a.air or b.air or relief == null or not relief.has_relief():
		return true
	return relief.los(a.x, a.y, b.x, b.y)

func in_trench(x: float, y: float) -> bool:
	var i := clampi(int(x / CG), 0, _cw - 1)
	var j := clampi(int(y / CG), 0, _ch - 1)
	return _cov[j * _cw + i] == 3

## Trincee e campi minati del difensore (livelli 0..3 di setup.def.fort), nella sua metà del campo.
func _gen_fort() -> void:
	var rng := _mrng
	var F := W - 1150.0
	for i in int(fort["trench"]):
		var x := F - 220.0 - i * 330.0 + (rng.randf() - 0.5) * 60.0
		var y := TOP + 180.0
		while y < BOTTOM - 260.0:
			var L := 380.0 + rng.randf() * 120.0
			var y1 := minf(y + L, BOTTOM - 180.0)
			var x0 := x + (rng.randf() - 0.5) * 70.0
			var x1 := x + (rng.randf() - 0.5) * 70.0
			var bad := false
			for k in 5:
				var t := k / 4.0
				if _obs_hit(lerpf(x0, x1, t), lerpf(y, y1, t), 20.0):
					bad = true
					break
			if not bad:
				trenches.append({"x0": x0, "y0": y, "x1": x1, "y1": y1})
			y = y1 + 120.0 + rng.randf() * 80.0
	for i in int(fort["mines"]) * 2:
		var best := Vector2.ZERO
		var bs := 1e18
		for c in 8:
			var px := F - 450.0 - rng.randf() * 1100.0
			var py := TOP + 200.0 + rng.randf() * (BOTTOM - TOP - 400.0)
			if _obs_hit(px, py, 40.0):
				continue
			var ok := true
			for m in mines:
				if Vector2(m["x"], m["y"]).distance_to(Vector2(px, py)) < 300.0:
					ok = false
			if not ok:
				continue
			var sc := (road_dist(px, py) if not roads.is_empty() else 0.0) + rng.randf() * 200.0
			if sc < bs:
				bs = sc; best = Vector2(px, py)
		if bs < 1e17:
			mines.append({"x": best.x, "y": best.y, "r": BattleRules.MINE_R, "charges": BattleRules.MINE_CHARGES, "spotted": [false, true]})

## Mezzi dell'attaccante nei campi minati.
func _upd_mines(dt: float) -> void:
	_mine_t -= dt
	if _mine_t > 0:
		return
	_mine_t = 0.5
	for m in mines:
		if int(m["charges"]) <= 0:
			continue
		var R: float = m["r"]
		for u in units:
			if u.dead or u.side != 0 or u.air or not BattleRules.ARMORED.has(u.type):
				continue
			var dx: float = u.x - m["x"]
			var dy: float = u.y - m["y"]
			if dx * dx + dy * dy > R * R:
				continue
			if _rng.randf() < BattleRules.MINE_P:
				m["charges"] = int(m["charges"]) - 1
				m["spotted"][0] = true
				_damage(u, BattleRules.MINE_DMG * minf(2.0, float(alive(u))))
				if emit_fx:
					fx.append({"e": "mine", "x": u.x, "y": u.y, "id": u.id})
				if int(m["charges"]) <= 0:
					break

## true se il punto è in un campo minato noto al lato si.
func known_mine_at(si: int, x: float, y: float, pad := 60.0) -> bool:
	for m in mines:
		if int(m["charges"]) > 0 and m["spotted"][si]:
			var R: float = float(m["r"]) + pad
			if (x - m["x"]) * (x - m["x"]) + (y - m["y"]) * (y - m["y"]) < R * R:
				return true
	return false

## Zona del punto: 0 aperto, 1 bosco, 2 città.
func zone_at(x: float, y: float) -> int:
	var i := clampi(int(x / CG), 0, _cw - 1)
	var j := clampi(int(y / CG), 0, _ch - 1)
	return _zon[j * _cw + i]

func _spawn() -> void:
	var cy := (TOP + BOTTOM) / 2.0
	for si in 2:
		var S: Dictionary = sides[si]
		var f: Dictionary = S["forces"]
		var tot := Data.total_units(f)
		var g := int(ceil(float(tot) / MAX_SPRITES)) if tot > MAX_SPRITES else 1
		S["g"] = g
		var dir := 1 if si == 0 else -1
		var front := 1150.0 if si == 0 else W - 1150.0
		for k in Data.UNIT_KEYS:
			var n := int(f.get(k, 0))
			if n <= 0:
				continue
			var count := int(ceil(float(n) / g))
			var size: float = float(Data.UNITS[k]["rts"]["size"]) * minf(1.4, 1 + 0.1 * (g - 1))
			var sp := maxf(60.0, size * 2 + 40)
			var rows_max := maxi(1, int(floor(1500.0 / sp)))
			for j in count:
				var col := j / rows_max
				var row := j % rows_max
				var rows_in_col := mini(rows_max, count - col * rows_max)
				var y := cy + (row - (rows_in_col - 1) / 2.0) * sp + (_mrng.randf() - 0.5) * 10
				var x := front - dir * (float(SPAWN_BACK[k]) + col * sp * 0.8) + (_mrng.randf() - 0.5) * 10
				x = clampf(x, 60, W - 60)
				_add_unit(si, k, x, y, mini(g, n - j * g))
	for b in bunker_pos:
		_add_unit(1, "bunker", b.x, b.y, 1)
	for u in units:
		if not u.air and not u.stat:
			_push_out(u)
			u.ax = u.x; u.ay = u.y; u.ox = u.x; u.oy = u.y

func _add_unit(si: int, type: String, x: float, y: float, count: int) -> Unit:
	var S: Dictionary = sides[si]
	var bunker := type == "bunker"
	var U: Dictionary = {} if bunker else Data.UNITS[type]
	var R: Dictionary = Data.BUNKER_STATS if bunker else U["rts"]
	var B: Dictionary = BattleRules.stat(type)
	var hpu: float = (float(Data.BUNKER_STATS["hp"]) if bunker else float(U["hp"])) * float(S["mods"]["hp"].get(type, 1.0))
	var atk: float = float(Data.BUNKER_STATS["atk"]) if bunker else float(U["atk"])
	var u := Unit.new()
	u.id = _uid; _uid += 1
	u.side = si; u.type = type; u.air = (not bunker) and bool(U["air"]); u.stat = bunker
	u.x = x; u.y = y
	u.ang = PI if si else 0.0
	u.tur = u.ang
	u.st = B
	u.hp = hpu * count; u.hp_max = u.hp; u.hp_unit = hpu; u.g = count
	u.r = float(R["size"]) * 1.2 if bunker else float(R["size"]) * 1.55 * minf(1.4, 1 + 0.1 * (count - 1))
	u.speed = 0.0 if bunker else float(B["speed"])
	u.range_ = float(B["range"]); u.min_range = float(B.get("min_range", 0)); u.splash = float(B.get("splash", 0))
	u.view0 = float(B["view"]); u.view = u.view0
	u.cd = float(R["cd"]); u.cd_t = _rng.randf() * u.cd
	u.mul = atk * u.cd * K * float(S["mods"]["atk"]) * float(S["mods"]["unit"].get(type, 1.0)) * float(S.get("luck", 1.0))
	u.M = BattleRules.matrix(type)
	u.ox = x; u.oy = y; u.ax = x; u.ay = y
	u.ret_t = _rng.randf() * RETARGET
	u.bob = _rng.randf() * TAU
	u.hidden_t = BattleRules.AMBUSH_REARM
	units.append(u)
	return u

func alive(u: Unit) -> int:
	if u.dead:
		return 0
	var n := int(ceil(u.hp / u.hp_unit - 0.02))
	return 1 if n < 1 else n

func _count_mobile(si: int) -> int:
	var n := 0
	for u in units:
		if not u.dead and not u.stat and u.side == si:
			n += alive(u)
	return n

## Superstiti del lato: forza principale (sul campo + salvi in ritirata), entro le forze iniziali.
func _survivors(si: int, reinforcements := false) -> Dictionary:
	var f := Data.empty_forces()
	var orig: Dictionary
	if reinforcements:
		orig = reinf[si]["forces"] if reinf[si] != null else Data.empty_forces()
	else:
		orig = sides[si]["forces"]
	for u in units:
		if not u.dead and not u.stat and u.side == si and u.reinf == reinforcements:
			f[u.type] += alive(u)
	var esc: Dictionary = escaped[si]["reinf" if reinforcements else "main"]
	for k in Data.UNIT_KEYS:
		f[k] = maxi(0, mini(int(orig.get(k, 0)), f[k] + int(esc.get(k, 0))))
	return f

func power(si: int) -> float:
	var a := 0.0
	var h := 0.0
	for u in units:
		if u.dead or u.side != si:
			continue
		var w := 0.5 if u.stat else 1.0
		a += u.mul / u.cd * alive(u) * w
		h += u.hp * w
	return sqrt(a * h)

# ---------------------------------------------------------------------------- visibilità
## Le proprie unità sono sempre visibili; quelle nemiche solo se avvistate dal lato si.
func visible_to(si: int, u) -> bool:
	if si < 0 or u.side == si:
		return true
	return u.spotted[si]

func _upd_vis(force := false) -> void:
	for u in units:
		if u.dead:
			continue
		if u.air:
			u.cover = 0; u.zone = 0; u.view = u.view0 * weather_view_mul; u.concealed = false; u.conc_r = 0.0
			continue
		var ci := clampi(int(u.x / CG), 0, _cw - 1) + clampi(int(u.y / CG), 0, _ch - 1) * _cw
		u.zone = _zon[ci]
		u.trench = _cov[ci] == 3
		u.cover = 2 if u.stat else mini(2, _cov[ci])
		var vm := weather_view_mul   # Fase 8: pioggia/nebbia/neve/notte riducono la vista di tutti
		if u.zone == 1:
			vm *= u.st["forest_view"]
		elif u.zone == 2:
			vm *= u.st["city_view"]
		u.view = u.view0 * vm
		var conc := 0.0
		if u.reveal_t <= 0:
			if u.smoke_t > 0:
				conc = BattleRules.CONCEAL_SMOKE
			var kind: String = u.st["conceal"]
			if u.cover > 0 and kind != "":
				var lim: float = u.speed * BattleRules.SLOW_FRAC
				if u.vx * u.vx + u.vy * u.vy <= lim * lim:
					var c: float = BattleRules.CONCEAL_INF[u.cover] if kind == "inf" else BattleRules.CONCEAL_VEH[u.cover]
					conc = c if conc <= 0 else minf(conc, c)
		u.conc_r = conc
		u.concealed = conc > 0
	var hv := hs if hs >= 0 else 0
	var rel: bool = relief != null and relief.has_relief()
	for si in 2:
		var vx := PackedFloat32Array()
		var vy := PackedFloat32Array()
		var vr := PackedFloat32Array()
		var va := PackedFloat32Array()
		var rc := PackedByteArray()
		var vh := PackedFloat32Array()   # Fase 7: quota del suolo di chi guarda (−1e9 = velivolo: niente rilievo)
		for v in units:
			if v.dead or v.side != si:
				continue
			vx.append(v.x); vy.append(v.y); vr.append(v.view)
			va.append(BattleRules.AA_AIR_VIEW if v.type == "aa" else v.view * BattleRules.AIR_SEEN)
			rc.append(1 if v.st["recon"] else 0)
			vh.append(-1e9 if (v.air or not rel) else relief.height(v.x, v.y))
		var nv := vx.size()
		for e in units:
			if e.dead or e.side == si:
				continue
			var vis := false
			var he := 0.0
			var ground: bool = rel and not e.air
			if ground:
				he = relief.height(e.x, e.y)
			# Fase 8: sotto un razzo illuminante la vista torna piena (l'effetto del meteo si annulla)
			var lit_k := 1.0
			if weather_view_mul < 0.999 and not flares.is_empty() and lit_at(e.x, e.y):
				lit_k = 1.0 / weather_view_mul
			for k in nv:
				var dx: float = e.x - vx[k]
				var dy: float = e.y - vy[k]
				var r: float
				var gg: bool = ground and vh[k] > -1e8
				if e.air:
					r = va[k] * lit_k
				else:
					r = vr[k] * lit_k
					if gg and vh[k] > he:
						r *= BattleRelief.view_mul(vh[k] - he)   # posizione dominante: si vede più lontano verso il basso
					if e.reveal_t > 0:
						# la fanteria che spara da copertura si vede solo da vicino; i cannoni dei mezzi si vedono da lontano
						if e.type == "inf":
							r = minf(r * BattleRules.REVEAL_OPEN, BattleRules.REVEAL_COVER[e.cover]) if e.cover > 0 else r * BattleRules.REVEAL_OPEN
						else:
							r = maxf(r * BattleRules.REVEAL_OPEN, BattleRules.REVEAL_GUN)
					elif e.conc_r > 0:
						r = minf(r, e.conc_r * (BattleRules.RECON_CONCEAL if rc[k] else 1.0))
				if dx * dx + dy * dy <= r * r:
					# linea di vista: una cresta tra i due nasconde il bersaglio (velivoli esclusi)
					if gg and not relief.los(vx[k], vy[k], e.x, e.y):
						continue
					vis = true
					break
			var was: bool = e.spotted[si]
			if vis != was or force:
				e.spotted[si] = vis
				if vis:
					_drop_ghost(si, e.id)
					if si == hv and not was and emit_fx and not force:
						fx.append({"e": "spotted", "u": e, "id": e.id, "side": e.side, "x": e.x, "y": e.y, "first": not e.seen_once})
					if si == hv:
						e.seen_once = true
				elif was:
					ghosts[si].append({"id": e.id, "type": e.type, "x": e.x, "y": e.y, "t": time, "g": e.g})
	# campi minati: l'attaccante li scopre da vicino (ricognizione da più lontano)
	for i in mines.size():
		var m: Dictionary = mines[i]
		if m["spotted"][0] or int(m["charges"]) <= 0:
			continue
		for v in units:
			if v.dead or v.side != 0:
				continue
			var R: float = float(m["r"]) + (BattleRules.MINE_SPOT_RECON if v.st["recon"] else BattleRules.MINE_SPOT)
			if (v.x - m["x"]) * (v.x - m["x"]) + (v.y - m["y"]) * (v.y - m["y"]) < R * R:
				m["spotted"][0] = true
				if emit_fx and not force:
					fx.append({"e": "mines_spotted", "i": i, "x": m["x"], "y": m["y"], "r": m["r"]})
				break
	# tempo trascorso nascosta (imboscata pronta)
	for u in units:
		if u.dead:
			continue
		if u.concealed and not u.spotted[1 - u.side]:
			u.hidden_t += 1.5 if fast else BattleRules.SPOT_DT
	for si in 2:
		var gl: Array = ghosts[si]
		if not gl.is_empty():
			ghosts[si] = gl.filter(func(g): return time - float(g["t"]) < BattleRules.GHOST_T)

func _drop_ghost(si: int, id: int) -> void:
	var gl: Array = ghosts[si]
	for i in range(gl.size() - 1, -1, -1):
		if int(gl[i]["id"]) == id:
			gl.remove_at(i)

# ---------------------------------------------------------------------------- ciclo
func step(dt: float) -> void:
	if done or not (dt > 0):
		return
	var hmax := AUTO_DT if fast else 0.1
	if dt > hmax + 1e-6:
		var n := int(ceil(dt / hmax))
		var h := dt / n
		for i in n:
			if done:
				break
			step(h)
		return
	if ending != null:
		ending["t"] -= dt
		if ending["t"] <= 0:
			done = true
		return
	if paused:
		return
	time += dt
	flow_budget = 2 if fast else 8
	var t0 := Time.get_ticks_usec() if prof_on else 0
	if weather != "sereno" or not weather_sched.is_empty() or not flares.is_empty():
		_upd_weather(dt)
	_vis_t -= dt
	if _vis_t <= 0:
		_vis_t = 1.5 if fast else BattleRules.SPOT_DT
		_upd_vis()
	if prof_on: t0 = _pf("vis", t0)
	for si in 2:
		var S: Dictionary = sides[si]
		if S["barrage_cd"] > 0:
			S["barrage_cd"] -= dt
		if S["smoke_cd"] > 0:
			S["smoke_cd"] -= dt
		if S["hurt"] > 0:
			S["hurt"] *= maxf(0.0, 1.0 - dt * 0.35)
		if (not S["human"] or ai_assist[si]) and not retreating[si]:
			S["ai"]["t"] -= dt
			if S["ai"]["t"] <= 0:
				S["ai"]["t"] = 2.0 if fast else 1.0
				BattleAI.think(self, si)
	if prof_on: t0 = _pf("ai", t0)
	if not salvos.is_empty():
		_upd_salvos()
	if not strikes.is_empty():
		_upd_strikes()
	if not mines.is_empty():
		_upd_mines(dt)
	_elist[0].clear()
	_elist[1].clear()
	for u in units:
		if not u.dead:
			_elist[u.side].append(u)
	if reinf[0] != null or reinf[1] != null:
		_upd_reinf()
	if not objectives.is_empty():
		_upd_objectives(dt)
	_obj_t -= dt
	if _obj_t <= 0.0:
		_obj_t = 1.0
		for si in 2:
			if retreating[si]:
				_upd_retreat(si)
		# l'IA attaccante ormai battuta ripiega per salvare i reparti (docs/omogeneita.md §1)
		if not retreating[0] and (ai_assist[0] or not sides[0]["human"]) and time > BattleRules.AI_RETREAT_T and ending == null:
			var p1 := power(1)
			if p1 > 0.0 and power(0) < p1 * BattleRules.AI_RETREAT_K and _count_mobile(0) > 0:
				_order_retreat(0)
	for i in units.size():
		var u: Unit = units[i]
		if not u.dead:
			_upd_unit(u, dt)
	if prof_on: t0 = _pf("units", t0)
	_separate()
	if prof_on: t0 = _pf("sep", t0)
	_upd_shells(dt)
	if marker != null:
		marker["t"] -= dt
		if marker["t"] <= 0:
			marker = null
	check_t -= dt
	if check_t <= 0:
		check_t = 0.25
		_check()

func _pf(k: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	prof[k] = int(prof.get(k, 0)) + t - t0
	return t

func _ang_diff(a: float, b: float) -> float:
	var d := b - a
	while d > PI:
		d -= TAU
	while d < -PI:
		d += TAU
	return d

func _turn(a: float, target: float, max_step: float) -> float:
	var d := _ang_diff(a, target)
	return a + clampf(d, -max_step, max_step)

func _upd_unit(u: Unit, dt: float) -> void:
	if u.hit_t > 0: u.hit_t -= dt
	if u.fire_t > 0: u.fire_t -= dt
	u.cd_t -= dt
	if u.smoke_t > 0: u.smoke_t -= dt
	if u.reveal_t > 0: u.reveal_t -= dt
	if u.ambush_t > 0: u.ambush_t -= dt
	u.ret_t -= dt * (0.3 if fast else 1.0)
	var si := u.side
	if u.tgt != null and (u.tgt.dead or not u.tgt.spotted[si]):
		u.tgt = null
		if u.ret_t > 0.05:
			u.ret_t = 0.05
	if u.order == ATTACK:
		if u.otgt == null or u.otgt.dead:
			u.order = IDLE; u.otgt = null; u.ax = u.x; u.ay = u.y
		elif not u.otgt.spotted[si]:
			# bersaglio perso di vista: attacco in movimento verso l'ultima posizione nota
			var lx: float = u.otgt.x
			var ly: float = u.otgt.y
			order_unit(u, AMOVE, lx, ly, null)
	if u.ret_t <= 0:
		u.ret_t = RETARGET * (0.85 + 0.3 * _rng.randf())
		if u.order == ATTACK:
			u.tgt = u.otgt
		else:
			var rad: float
			if u.stat or u.order == MOVE or u.order == FIRE or (u.hold and u.order == IDLE) or u.type == "art":
				rad = u.range_
			elif u.order == AMOVE:
				rad = u.range_ + (500.0 if u.air else 200.0)
			else:
				rad = u.range_ + (450.0 if u.air else LEASH)
			u.tgt = _find_target(u, rad)
	var t: Unit = u.tgt
	var d := 0.0
	var dx := 0.0
	var dy := 0.0
	var tr: float = u.st["turret"]
	var aim := 0.0
	if t != null:
		dx = t.x - u.x; dy = t.y - u.y; d = sqrt(dx * dx + dy * dy)
		aim = atan2(dy, dx)
		u.tur = _turn(u.tur, aim, tr * dt)
	elif u.order == FIRE:
		aim = atan2(u.oy - u.y, u.ox - u.x)
		u.tur = _turn(u.tur, aim, tr * dt)
	elif not u.stat:
		u.tur = _turn(u.tur, u.ang, minf(2.0, tr) * dt)
	# artiglieria: si piazza dopo ogni spostamento
	if u.type == "art":
		if u.vx * u.vx + u.vy * u.vy > 36:
			u.deploy_t = float(u.st["deploy"])
		elif u.deploy_t > 0:
			u.deploy_t -= dt
	# Fase 7: senza linea di vista il fuoco diretto non parte (e chi attacca si avvicina per scavalcare la cresta)
	var blind: bool = t != null and not u.air and not t.air and u.type != "art" and relief != null and relief.has_relief() 		and d <= u.range_ + t.r * 0.5 and not relief.los(u.x, u.y, t.x, t.y)
	if u.cd_t <= 0:
		if t != null and d <= u.range_ + t.r * 0.5 and (u.min_range == 0 or d >= u.min_range) and not blind:
			if _can_fire(u, aim):
				_fire(u, t, d)
		elif u.order == FIRE and u.type == "art":
			var fd := Vector2(u.ox - u.x, u.oy - u.y).length()
			if fd <= u.range_ and fd >= u.min_range and _can_fire(u, aim):
				_fire_area(u, u.ox, u.oy, fd)
		if u.cd_t < -dt:
			u.cd_t = -dt
	if u.stat:
		return
	var gx := NAN
	var gy := 0.0
	if u.order == MOVE:
		gx = u.ox; gy = u.oy
	elif u.order == FIRE:
		var fd2 := Vector2(u.ox - u.x, u.oy - u.y).length()
		if fd2 > u.range_ * 0.97:
			gx = u.ox; gy = u.oy
		elif fd2 < u.min_range + 20 and fd2 > 0.1:
			gx = u.x - (u.ox - u.x) / fd2 * 200; gy = u.y - (u.oy - u.y) / fd2 * 200
	elif u.hold and u.order == IDLE:
		# mantieni posizione: spara solo a ciò che è a tiro e torna al proprio punto se spinto via
		var hx := u.x - u.ax
		var hy := u.y - u.ay
		if hx * hx + hy * hy > (3600.0 if u.type == "jet" else 64.0):
			gx = u.ax; gy = u.ay
	elif t != null and (u.order != IDLE or _in_leash(u, t)):
		if u.min_range > 0 and d < u.min_range + 40 and d > 0.1:
			gx = u.x - dx / d * 250; gy = u.y - dy / d * 250
		elif (d > u.range_ * 0.9 or blind) and u.type != "art":
			gx = t.x; gy = t.y
	elif u.order == AMOVE:
		gx = u.ox; gy = u.oy
	else:
		var ax := u.x - u.ax
		var ay := u.y - u.ay
		if ax * ax + ay * ay > (3600.0 if u.type == "jet" else 64.0):
			gx = u.ax; gy = u.ay
	if (u.order == MOVE or u.order == AMOVE) and gx == u.ox and gy == u.oy:
		var ex := u.ox - u.x
		var ey := u.oy - u.y
		var dd := sqrt(ex * ex + ey * ey)
		var arr := 150.0 if u.type == "jet" else (20.0 if u.air else 7 + u.r * 0.6)
		if dd < arr:
			_arrive(u); gx = NAN
		else:
			u.chk_t -= dt
			if u.chk_t <= 0:
				u.chk_t = 0.5
				if dd > u.prev_d - u.speed * 0.125:
					u.stuck_t += 0.5
				else:
					u.stuck_t = 0
				u.prev_d = dd
				if (u.stuck_t >= 1.5 and dd < 100) or u.stuck_t >= 4:
					_arrive(u); gx = NAN
	if u.type == "jet":
		_jet_move(u, dt, gx, gy, t, d)
	else:
		_move_to(u, dt, gx, gy)

func _can_fire(u: Unit, aim: float) -> bool:
	if u.type == "art":
		if u.deploy_t > 0 or u.vx * u.vx + u.vy * u.vy > 36:
			return false
		return absf(_ang_diff(u.tur, aim)) < 0.3
	if u.type == "jet":
		return absf(_ang_diff(u.ang, aim)) < 0.55
	if u.type == "tank" or u.type == "aa" or u.type == "bunker":
		return absf(_ang_diff(u.tur, aim)) < 0.25
	return true

func _arrive(u: Unit) -> void:
	u.order = IDLE; u.ax = u.x; u.ay = u.y; u.stuck_t = 0; u.prev_d = 1e9

func _in_leash(u: Unit, t: Unit) -> bool:
	var dx := t.x - u.ax
	var dy := t.y - u.ay
	var L := u.range_ + (450.0 if u.air else LEASH)
	return dx * dx + dy * dy <= L * L

func _find_target(u: Unit, rad: float) -> Unit:
	var M := u.M
	var r2 := rad * rad
	var best: Unit = null
	var bs := 0.0
	var si := u.side
	var los_chk: bool = not u.air and u.type != "art" and relief != null and relief.has_relief()
	for e in _elist[1 - si]:
		if e.dead or not e.spotted[si]:
			continue
		var m: float = M.get(e.type, 0.0)
		if m <= 0:
			continue
		var dx: float = e.x - u.x
		var dy: float = e.y - u.y
		var d2 := dx * dx + dy * dy
		if d2 > r2:
			continue
		var d := sqrt(d2)
		if u.min_range > 0 and d < u.min_range:
			continue
		# danno atteso (copertura del bersaglio) × minaccia che il bersaglio rappresenta per chi spara
		var me := m
		if not e.air and e.cover > 0 and u.type != "art":
			if e.type == "inf":
				me *= BattleRules.COVER_INF[e.cover] * (BattleRules.VEH_VS_COVER_INF if (u.type == "tank" or u.type == "aa") else 1.0)
			else:
				me *= BattleRules.COVER_VEH[e.cover]
		var thr: float = e.M.get(u.type, 0.0)
		if e.type == "inf" and BattleRules.ARMORED.has(u.type) and d < BattleRules.AT_RANGE + u.r + 60.0:
			thr *= BattleRules.AT_COVER_MUL   # fanteria anticarro vicina: minaccia mortale
		var s: float = me * (1.0 + 2.0 * thr) * (1.3 - 0.3 * e.hp / e.hp_max) / (1 + d / (u.range_ * 1.5))
		if e.stat: s *= 0.55
		if e == u.tgt: s *= 1.15
		# preferisce i bersagli già a tiro: evita di attraversare lo schieramento nemico per un bersaglio lontano
		if d <= u.range_ + e.r * 0.5: s *= 2.5
		if s > bs:
			# fuoco diretto: serve la linea di vista propria (l'artiglieria spara in curva sopra le creste);
			# controllata solo per il candidato migliore finora (poche chiamate, in cache)
			if los_chk and not e.air and not relief.los(u.x, u.y, e.x, e.y):
				continue
			bs = s; best = e
	return best

func _move_to(u: Unit, dt: float, gx: float, gy: float) -> void:
	var dvx := 0.0
	var dvy := 0.0
	if not is_nan(gx) and not u.air and u.type != "inf" and relief != null and relief.has_water:
		# Fase 7: i mezzi passano i fiumi da ponti e guadi (la fanteria guada dove si trova)
		var ct := relief.crossing_target(u.x, u.y, gx, gy)
		if not is_nan(ct.x):
			gx = ct.x
			gy = ct.y
	if not is_nan(gx):
		var dx := gx - u.x
		var dy := gy - u.y
		var d := sqrt(dx * dx + dy * dy)
		if d > 2:
			var ux := dx / d
			var uy := dy / d
			if not u.air and _nav_dir(u, gx, gy, d):
				ux = _nd.x; uy = _nd.y
			var sp := u.speed
			if not u.air:
				if u.zone == 1:
					sp *= float(u.st["forest_speed"])
				elif u.zone == 2:
					sp *= float(u.st["city_speed"])
				# Fase 7: fiumi guadabili ma lenti (ponti e guadi: a piena velocità)
				if relief != null and relief.has_water and relief.water_at(u.x, u.y) > 0.0:
					sp *= BattleRules.WADE_INF if u.type == "inf" else BattleRules.WADE_VEH
			if u.cap > 0 and u.order == AMOVE and u.tgt == null and sp > u.cap:
				sp = u.cap
			if d < 24:
				sp *= maxf(0.25, d / 24)
			# retromarcia: un mezzo corazzato che si allontana di poco dal proprio bersaglio gli resta col muso rivolto
			u.reverse = false
			if not u.air and u.tgt != null and d < 700.0 and u.st["armor"].size() > 0:
				var ta := atan2(u.tgt.y - u.y, u.tgt.x - u.x)
				if absf(_ang_diff(atan2(uy, ux), ta)) > 2.0:
					u.reverse = true
					sp *= 0.5
			dvx = ux * sp; dvy = uy * sp
	else:
		u.reverse = false
	var k := minf(1.0, dt * (2.5 if u.air else 6.0))
	u.vx += (dvx - u.vx) * k; u.vy += (dvy - u.vy) * k
	u.x += u.vx * dt; u.y += u.vy * dt
	var hull: float = u.st["hull"]
	if u.reverse and u.vx * u.vx + u.vy * u.vy > 4:
		u.ang = _turn(u.ang, atan2(-u.vy, -u.vx), hull * 2.7 * dt)
	elif u.vx * u.vx + u.vy * u.vy > 4:
		u.ang = _turn(u.ang, atan2(u.vy, u.vx), hull * 2.7 * dt)
	elif u.tgt != null and (u.air or u.st["armor"].size() > 0):
		# fermo: lo scafo si gira lentamente verso il bersaglio (la corazza frontale verso la minaccia)
		u.ang = _turn(u.ang, u.tur, (3.0 if u.air else hull * 0.25) * dt)

func _jet_move(u: Unit, dt: float, gx: float, gy: float, t: Unit, d: float) -> void:
	var hx := NAN
	var hy := 0.0
	var orbit := false
	if t != null and u.order != MOVE:
		if u.pass_t > 0:
			u.pass_t -= dt
		elif d < 160:
			u.pass_t = 1.0
		else:
			hx = t.x; hy = t.y
	elif not is_nan(gx):
		hx = gx; hy = gy; orbit = true
	else:
		hx = u.ax; hy = u.ay; orbit = true
	var desired := u.ang
	if not is_nan(hx):
		var dx := hx - u.x
		var dy := hy - u.y
		desired = atan2(dy, dx)
		if orbit and dx * dx + dy * dy < 250.0 * 250.0:
			desired += 1.3
	if u.x < 100 or u.x > W - 100 or u.y < TOP + 80 or u.y > BOTTOM - 80:
		desired = atan2(H / 2 - u.y, W / 2 - u.x)
	u.ang = _turn(u.ang, desired, float(u.st["hull"]) * dt)
	u.vx = cos(u.ang) * u.speed; u.vy = sin(u.ang) * u.speed
	u.x += u.vx * dt; u.y += u.vy * dt

func _nav_dir(u: Unit, gx: float, gy: float, d: float) -> bool:
	if time >= u.nav_t:
		u.nav_t = time + (0.7 if fast else 0.35)
		u.direct = d < 60 or _clear_line(u.x, u.y, gx, gy)
	if u.direct:
		return false
	if fast and tkey != "urbano":
		return false   # risoluzione automatica: fuori città basta scivolare attorno agli ostacoli
	var f = _flow(gx, gy, u.x, u.y)
	if f == null:
		return false
	var fl: PackedInt32Array = f
	var cx := clampi(int(floor(u.x / NAV)), 0, nw - 1)
	var cy := clampi(int(floor(u.y / NAV)), 0, nh - 1)
	for st in 2:
		var best := -1
		var bd := 1000000000
		var own := fl[cy * nw + cx]
		if own == 0:
			break
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := cx + ox
				var ny := cy + oy
				if nx < 0 or ny < 0 or nx >= nw or ny >= nh:
					continue
				var v := fl[ny * nw + nx]
				if v < 0 or v >= bd:
					continue
				if ox != 0 and oy != 0 and (nav_block[cy * nw + nx] != 0 or nav_block[ny * nw + cx] != 0):
					continue
				bd = v; best = ny * nw + nx
		if best < 0 or (own >= 0 and bd >= own):
			if st == 0:
				return false
			break
		cx = best % nw; cy = best / nw
	var tx := (cx + 0.5) * NAV - u.x
	var ty := (cy + 0.5) * NAV - u.y
	var l := sqrt(tx * tx + ty * ty)
	if l < 0.5:
		return false
	_nd = Vector2(tx / l, ty / l)
	return true

func _clear_line(x0: float, y0: float, x1: float, y1: float) -> bool:
	var dx := x1 - x0
	var dy := y1 - y0
	var d := sqrt(dx * dx + dy * dy)
	var n := int(ceil(d / (NAV * 0.75)))
	for i in range(1, n):
		var t := float(i) / n
		if t * d < 12:
			continue
		var cx := int(floor((x0 + dx * t) / NAV))
		var cy := int(floor((y0 + dy * t) / NAV))
		if cx < 0 or cy < 0 or cx >= nw or cy >= nh:
			continue
		if nav_block[cy * nw + cx] != 0:
			return false
	return true

## Campo di flusso verso (gx, gy). Con (ux, uy) la ricerca si ferma poco oltre la cella dell'unità che lo chiede
## (campo parziale); se un'altra unità fuori dal campo parziale lo richiede, viene ricalcolato per intero.
func _flow(gx: float, gy: float, ux := -1.0, uy := -1.0):
	# obiettivi raggruppati a blocchi di 3×3 celle: molte meno ricerche in ampiezza (l'ultimo tratto è in linea retta)
	var gs := 5 if fast else 3
	var cx := clampi(int(floor(gx / NAV)) / gs * gs + gs / 2, 0, nw - 1)
	var cy := clampi(int(floor(gy / NAV)) / gs * gs + gs / 2, 0, nh - 1)
	var ci := cy * nw + cx
	if nav_block[ci] != 0:
		ci = -1
		for r in range(1, 8):
			if ci >= 0:
				break
			for oy in range(-r, r + 1):
				if ci >= 0:
					break
				for ox in range(-r, r + 1):
					var nx := cx + ox
					var ny := cy + oy
					if nx < 0 or ny < 0 or nx >= nw or ny >= nh:
						continue
					if nav_block[ny * nw + nx] == 0:
						ci = ny * nw + nx
						break
		if ci < 0:
			return null
	var ucell := -1
	if ux >= 0:
		ucell = clampi(int(ux / NAV), 0, nw - 1) + clampi(int(uy / NAV), 0, nh - 1) * nw
		if nav_block[ucell] != 0:
			ucell = -1
	if _flow_cache.has(ci):
		var f0: PackedInt32Array = _flow_cache[ci]
		if ucell < 0 or f0[ucell] >= 0 or _flow_full.has(ci):
			return f0
	if flow_budget <= 0:
		return null
	flow_budget -= 1
	prof["bfs"] = int(prof.get("bfs", 0)) + 1
	var N := nw * nh
	if _adj_start.size() != N + 1:
		_build_adj()
	var f := PackedInt32Array()
	f.resize(N)
	f.fill(-1)
	var q := PackedInt32Array()
	q.resize(N)
	var h := 0
	var tl := 0
	f[ci] = 0; q[tl] = ci; tl += 1
	var adj := _adj
	var st := _adj_start
	var stop := 1 << 30
	var full := true
	while h < tl:
		var c := q[h]; h += 1
		if c == ucell:
			stop = f[c] + 14
		var v := f[c] + 1
		if v > stop:
			full = false
			break
		for k in range(st[c], st[c + 1]):
			var ni := adj[k]
			if f[ni] < 0:
				f[ni] = v; q[tl] = ni; tl += 1
	if not _flow_cache.has(ci):
		_flow_order.append(ci)
	_flow_cache[ci] = f
	if full:
		_flow_full[ci] = true
	else:
		_flow_full.erase(ci)
	if _flow_order.size() > 64:
		var old = _flow_order.pop_front()
		_flow_cache.erase(old)
		_flow_full.erase(old)
	return f

## Vicini percorribili di ogni cella della griglia di navigazione (8 direzioni, diagonali solo se i due lati sono liberi).
func _build_adj() -> void:
	var N := nw * nh
	_adj_start.resize(N + 1)
	_adj = PackedInt32Array()
	_adj.resize(N * 8)
	var cnt_ := 0
	for c in N:
		_adj_start[c] = cnt_
		if nav_block[c] != 0:
			continue
		var x := c % nw
		var y := c / nw
		for oy in range(-1, 2):
			var ny := y + oy
			if ny < 0 or ny >= nh:
				continue
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := x + ox
				if nx < 0 or nx >= nw:
					continue
				var ni := ny * nw + nx
				if nav_block[ni] != 0:
					continue
				if ox != 0 and oy != 0 and (nav_block[y * nw + nx] != 0 or nav_block[ny * nw + x] != 0):
					continue
				_adj[cnt_] = ni
				cnt_ += 1
	_adj_start[N] = cnt_
	_adj.resize(cnt_)

func _push_out(u: Unit) -> void:
	var r := u.r * 0.85
	var list = _cgrid[_cgi(u.x, u.y)]
	if list != null:
		for o in list:
			if o["rect"]:
				var ox: float = o["x"]; var oy: float = o["y"]; var ow: float = o["w"]; var oh: float = o["h"]
				var cx := clampf(u.x, ox, ox + ow)
				var cy := clampf(u.y, oy, oy + oh)
				var dx := u.x - cx
				var dy := u.y - cy
				var d2 := dx * dx + dy * dy
				if d2 >= r * r:
					continue
				if d2 > 1e-6:
					var d := sqrt(d2)
					var p := (r - d) / d
					u.x += dx * p; u.y += dy * p
				else:
					var l := u.x - ox
					var rr := ox + ow - u.x
					var t := u.y - oy
					var b := oy + oh - u.y
					var m := minf(minf(l, rr), minf(t, b))
					if m == l: u.x = ox - r
					elif m == rr: u.x = ox + ow + r
					elif m == t: u.y = oy - r
					else: u.y = oy + oh + r
			else:
				var dx: float = u.x - o["x"]
				var dy: float = u.y - o["y"]
				var R: float = o["r"] + r
				var d2 := dx * dx + dy * dy
				if d2 >= R * R:
					continue
				var d := sqrt(d2)
				if d == 0: d = 0.01
				u.x = o["x"] + dx / d * R; u.y = o["y"] + dy / d * R
	if sea:
		var cx := coast(u.y) + u.r
		if u.x < cx:
			u.x = cx

## Separazione tra unità vicine (spazzata ordinata per x: costo quasi lineare).
func _separate() -> void:
	_sep.clear()
	var rmax := 0.0
	for u in units:
		if not u.dead and u.type != "jet":
			_sep.append(u)
			if u.r > rmax: rmax = u.r
	_sep.sort_custom(func(a, b): return a.x < b.x)
	var n := _sep.size()
	for i in n:
		var a: Unit = _sep[i]
		var lim := a.r + rmax
		for j in range(i + 1, n):
			var b: Unit = _sep[j]
			var dx := b.x - a.x
			if dx > lim:
				break
			if b.air != a.air:
				continue
			# separazione: un po' più ampia del JS (0.9) per non compenetrare i modelli 3D a terra
			var R := (a.r + b.r) * (0.8 if a.air else SEP_GROUND)
			if dx > R or dx < -R:
				continue
			var dy := b.y - a.y
			if dy > R or dy < -R:
				continue
			var d2 := dx * dx + dy * dy
			if d2 >= R * R:
				continue
			if d2 < 1e-4:
				dx = 0.1 * (1.0 if (a.id & 1) else -1.0); dy = 0.07; d2 = dx * dx + dy * dy
			var d := sqrt(d2)
			var p := (R - d) * (0.35 if a.air else 0.45) / d
			if a.stat:
				b.x += dx * p * 2; b.y += dy * p * 2
			elif b.stat:
				a.x -= dx * p * 2; a.y -= dy * p * 2
			else:
				a.x -= dx * p; a.y -= dy * p; b.x += dx * p; b.y += dy * p
	for u in units:
		if u.dead or u.stat:
			continue
		if not u.air:
			_push_out(u)
		var m: float = u.r
		u.x = clampf(u.x, m, W - m)
		u.y = clampf(u.y, TOP + m, BOTTOM - m)

# ---------------------------------------------------------------------------- combattimento
func _start_shot(u: Unit) -> bool:
	u.cd_t += u.cd * (0.92 + 0.16 * _rng.randf())
	if u.cd_t < 0.05:
		u.cd_t = 0.05
	u.fire_t = 0.09
	# imboscata: primi colpi da posizione nascosta
	var amb := false
	if u.concealed and u.hidden_t >= BattleRules.AMBUSH_REARM and u.type != "art":
		u.ambush_t = BattleRules.AMBUSH_T
		u.hidden_t = 0.0
		amb = true
	u.reveal_t = BattleRules.REVEAL_T
	u.concealed = false
	u.conc_r = 0.0
	if amb and emit_fx:
		fx.append({"e": "ambush", "u": u, "id": u.id, "side": u.side, "x": u.x, "y": u.y})
	return amb

func _fire(u: Unit, t: Unit, d: float) -> void:
	_start_shot(u)
	var base := u.mul * alive(u)
	if u.type == "art":
		var sc := BattleRules.scatter(d)
		# mira dove il bersaglio È (nessun anticipo): con 2–5 s di volo l'artiglieria punisce chi sta fermo, non chi manovra
		_art_shell(u, t.x, t.y, d, sc, base * BattleRules.ART_DMG)
		return
	var dmg := base * float(u.M.get(t.type, 0.0))
	# precisione: cala con la distanza e sparando in movimento
	var fr := d / maxf(1.0, u.range_)
	dmg *= lerpf(1.0, float(u.st["acc_far"]), clampf(fr * fr, 0.0, 1.0))
	var lim := u.speed * 0.25
	if not u.air and u.vx * u.vx + u.vy * u.vy > lim * lim:
		dmg *= float(u.st["move_fire"])
	# copertura del bersaglio (fuoco diretto)
	var cov: int = 0 if t.air else t.cover
	if cov > 0:
		if t.type == "inf":
			dmg *= BattleRules.COVER_INF[cov]
			if u.type == "tank" or u.type == "aa":
				dmg *= BattleRules.VEH_VS_COVER_INF
		else:
			dmg *= BattleRules.COVER_VEH[cov]
	# corazza: fronte / fianco / retro
	var fl := BattleRules.flank(t.type, t.ang, u.x - t.x, u.y - t.y)
	dmg *= float(fl[0])
	if u.type == "tank" and BattleRules.ARMORED.has(t.type):
		dmg *= BattleRules.TANK_GUN_VS_ARMOR
	# fanteria anticarro da vicino
	var rocket := false
	if u.type == "inf" and BattleRules.ARMORED.has(t.type) and d < BattleRules.AT_RANGE + t.r:
		dmg *= BattleRules.AT_COVER_MUL if u.cover > 0 else BattleRules.AT_OPEN_MUL
		rocket = true
	var amb := u.ambush_t > 0
	if amb:
		dmg *= BattleRules.AMBUSH_MUL
	if t.smoke_t > 0:
		dmg *= SMOKE_MUL
	if prof_on:
		var fk := "%d:n_%s_%s_c%d%s%s" % [u.side, u.type, fl[1], cov, "_amb" if u.ambush_t > 0 else "", "_mv" if u.vx * u.vx + u.vy * u.vy > lim * lim else ""]
		prof[fk] = float(prof.get(fk, 0.0)) + 1.0
		var pk := "%d:%s>%s" % [u.side, u.type, t.type]
		prof[pk] = float(prof.get(pk, 0.0)) + minf(dmg, t.hp)
	_damage(t, dmg)
	if emit_fx:
		fx.append({"e": "fire", "u": u, "t": t, "tx": t.x, "ty": t.y, "tair": t.air, "flank": fl[1], "ambush": amb, "cover": cov, "rocket": rocket})

## Fuoco d'area dell'artiglieria su un punto (ordine FIRE o fantasma): dispersione larga.
func _fire_area(u: Unit, x: float, y: float, d: float) -> void:
	_start_shot(u)
	_art_shell(u, x, y, d, BattleRules.scatter(d) * BattleRules.AREA_SCATTER, u.mul * alive(u) * BattleRules.ART_DMG)

func _art_shell(u: Unit, x: float, y: float, d: float, sc: float, base: float) -> void:
	var a := _rng.randf() * TAU
	var rr := sqrt(_rng.randf()) * sc
	var ca := cos(u.tur)
	var sa := sin(u.tur)
	var TT := BattleRules.SHELL_T0 + d * BattleRules.SHELL_TK
	var s := _shell(u.side, u.x + ca * u.r * 1.4, u.y + sa * u.r * 1.4, x + cos(a) * rr, y + sin(a) * rr, base, u.splash, TT, 30 + d * 0.12, false)
	s.scatter = sc
	if emit_fx:
		fx.append({"e": "fire", "u": u, "art": true})

func _damage(t: Unit, dmg: float) -> void:
	if t.dead or not (dmg > 0):
		return
	t.hp -= dmg; t.hit_t = 0.25; last_dmg = time
	t.last_hit = time
	sides[t.side]["hurt"] += dmg
	if t.hp <= t.hp_unit * 0.02:
		_kill(t)

func _kill(t: Unit) -> void:
	t.dead = true; t.hp = 0; t.tgt = null; t.otgt = null
	if t.sel:
		t.sel = false
	for si in 2:
		_drop_ghost(si, t.id)
	if emit_fx:
		fx.append({"e": "kill", "u": t, "x": t.x, "y": t.y, "type": t.type, "air": t.air, "ang": t.ang})

func _shell(side: int, x0: float, y0: float, x1: float, y1: float, dmg: float, splash: float, TT: float, h: float, barr: bool) -> Shell:
	var s: Shell = null
	for sh in shells:
		if not sh.on:
			s = sh
			break
	if s == null:
		s = Shell.new()
		shells.append(s)
	s.on = true; s.side = side; s.x0 = x0; s.y0 = y0; s.x1 = x1; s.y1 = y1; s.t = 0; s.T = TT
	s.dmg = dmg; s.splash = splash; s.h = h; s.barrage = barr; s.scatter = 0.0
	return s

func _upd_shells(dt: float) -> void:
	for s in shells:
		if not s.on:
			continue
		s.t += dt
		if s.t >= s.T:
			s.on = false
			_impact(s)

func _impact(s: Shell) -> void:
	var M: Dictionary = Data.MATRIX["art"]
	for e in units:
		if e.dead or e.side == s.side or e.air:
			continue
		var dx: float = e.x - s.x1
		var dy: float = e.y - s.y1
		var R: float = s.splash + e.r * 0.5
		var d2 := dx * dx + dy * dy
		if d2 >= R * R:
			continue
		var f := 1 - 0.5 * sqrt(d2) / R
		if e.type == "inf" and e.cover > 0:
			f *= BattleRules.TRENCH_ART if e.trench else BattleRules.COVER_ART_INF[e.cover]
		if prof_on:
			var pk := "%d:shell>%s" % [s.side, e.type]
			prof[pk] = float(prof.get(pk, 0.0)) + minf(s.dmg * float(M[e.type]) * f, e.hp)
		_damage(e, s.dmg * float(M[e.type]) * f)
	if emit_fx:
		fx.append({"e": "impact", "x": s.x1, "y": s.y1, "big": s.barrage, "scatter": s.scatter})

func barrage(si: int, x: float, y: float) -> bool:
	var S: Dictionary = sides[si]
	if int(S["support"]) <= 0 or S["barrage_cd"] > 0 or ending != null:
		return false
	S["barrage_cd"] = BARRAGE_CD
	for k in BARRAGE_SALVOS:
		salvos.append({"t": time + k * 0.7, "si": si, "x": x, "y": y})
	if emit_fx:
		fx.append({"e": "barrage", "side": si, "x": x, "y": y})
	return true

func _upd_salvos() -> void:
	var A: Dictionary = Data.UNITS["art"]
	for i in range(salvos.size() - 1, -1, -1):
		var sv: Dictionary = salvos[i]
		if sv["t"] > time:
			continue
		salvos.remove_at(i)
		var S: Dictionary = sides[sv["si"]]
		var sup := int(S["support"])
		var n := mini(8, sup)
		var per: float = float(A["atk"]) * float(A["rts"]["cd"]) * K * float(S["mods"]["atk"]) * float(S["mods"]["unit"].get("art", 1.0)) * BARRAGE_MUL * sup / n
		for j in n:
			var a := _rng.randf() * TAU
			var rr := sqrt(_rng.randf()) * BARRAGE_R
			var x0 := W + 60 if sv["si"] else -60.0
			var s := _shell(sv["si"], x0, sv["y"] - 400, sv["x"] + cos(a) * rr, sv["y"] + sin(a) * rr, per, 70, 1.6 + _rng.randf() * 0.4, 300, true)
			s.scatter = BARRAGE_R

# ---------------------------------------------------------------------------- abilità tattiche
## Cortina fumogena: le unità di terra di `list` (lato si) subiscono −30% dal fuoco diretto per SMOKE_T secondi
## (e restano nascoste alla vista da lontano).
func smoke(si: int, list: Array) -> bool:
	var S: Dictionary = sides[si]
	if S["smoke_cd"] > 0 or ending != null or done:
		return false
	var who := []
	for u in list:
		if not u.dead and not u.stat and not u.air and u.side == si:
			who.append(u)
	if who.is_empty():
		return false
	S["smoke_cd"] = SMOKE_CD
	for u in who:
		u.smoke_t = SMOKE_T
		if emit_fx:
			fx.append({"e": "smoke", "u": u, "x": u.x, "y": u.y, "side": si})
	return true

func can_smoke(si: int) -> bool:
	return si >= 0 and sides[si]["smoke_cd"] <= 0 and ending == null and not done

## Supporto aereo: un caccia sgancia AIR_BOMBS bombe in linea su x,y dopo AIR_DELAY secondi. Un uso per battaglia.
func air_strike(si: int, x: float, y: float) -> bool:
	var S: Dictionary = sides[si]
	if int(S["air_uses"]) <= 0 or ending != null or done:
		return false
	S["air_uses"] = int(S["air_uses"]) - 1
	S["air_t"] = time + AIR_DELAY
	x = clampf(x, 10, W - 10)
	y = clampf(y, TOP + 10, BOTTOM - 10)
	var dir := 1.0 if si == 0 else -1.0
	for k in AIR_BOMBS:
		var o := (k - (AIR_BOMBS - 1) / 2.0) * AIR_STEP
		strikes.append({"t": time + AIR_DELAY + k * 0.09, "si": si, "x": x + dir * o, "y": y + (16.0 if k % 2 else -16.0)})
	if emit_fx:
		fx.append({"e": "airstrike", "side": si, "x": x, "y": y, "dir": dir, "delay": AIR_DELAY})
	return true

func _upd_strikes() -> void:
	var J: Dictionary = Data.UNITS["jet"]
	var M: Dictionary = Data.MATRIX["jet"]
	for i in range(strikes.size() - 1, -1, -1):
		var b: Dictionary = strikes[i]
		if b["t"] > time:
			continue
		strikes.remove_at(i)
		var S: Dictionary = sides[b["si"]]
		var per: float = float(J["atk"]) * float(J["rts"]["cd"]) * K * float(S["mods"]["atk"]) * AIR_MUL
		for e in units:
			if e.dead or e.side == b["si"] or e.air:
				continue
			var dx: float = e.x - b["x"]
			var dy: float = e.y - b["y"]
			var R: float = AIR_SPLASH + e.r * 0.5
			var d2 := dx * dx + dy * dy
			if d2 >= R * R:
				continue
			var f := 1 - 0.5 * sqrt(d2) / R
			if e.type == "inf" and e.cover > 0:
				f *= BattleRules.TRENCH_ART if e.trench else BattleRules.COVER_ART_INF[e.cover]
			_damage(e, per * float(M.get(e.type, 1.0)) * f)
		if emit_fx:
			fx.append({"e": "bomb", "x": b["x"], "y": b["y"], "side": b["si"]})

## IA del lato avversario (solo con un lato umano): fumo quando è sotto forte fuoco diretto.
func _ai_smoke(si: int) -> void:
	if hs < 0 or si == hs or sides[si]["smoke_cd"] > 0:
		return
	var hp := 0.0
	var hit := []
	for u in units:
		if u.dead or u.side != si or u.stat:
			continue
		hp += u.hp
		if not u.air and time - u.last_hit < 2.0:
			hit.append(u)
	if (hit.size() >= 2 and float(sides[si]["hurt"]) > hp * 0.05) or (hit.size() >= 1 and float(sides[si]["hurt"]) > hp * 0.1):
		smoke(si, hit)

func _check() -> void:
	if not sel.is_empty():
		sel = sel.filter(func(u): return not u.dead)
	var dead := 0
	for u in units:
		if u.dead:
			dead += 1
	if dead > 20:
		_compact()
	var pa := {}
	var pd := {}
	var pd_all := {}
	var am := 0
	var dm := 0
	for u in units:
		if u.dead:
			continue
		if u.side == 0:
			am += alive(u); pa[u.type] = 1
		else:
			pd_all[u.type] = 1
			if not u.stat:
				dm += alive(u); pd[u.type] = 1
	cnt[0] = am; cnt[1] = dm
	if dm == 0:
		_end("att", ""); return
	if am == 0:
		_end("def", "ritirata" if retreating[0] else ""); return
	var can_a := false
	var can_d := false
	for a in pa:
		var Ma := BattleRules.matrix(a)
		for d in pd:
			if float(Ma.get(d, 0)) > 0: can_a = true
	for d in pd_all:
		var Md := BattleRules.matrix(d)
		for a in pa:
			if float(Md.get(a, 0)) > 0: can_d = true
	if not can_a and not can_d:
		stall_t += 0.25
	else:
		stall_t = 0
	if stall_t >= STALL:
		_end("def", "stallo"); return
	var lim := NO_DMG_HUMAN if (hs >= 0 and not ai_assist[hs]) else NO_DMG_AI
	if time >= BattleRules.BATTLE_T:
		_end(_time_winner(), "tempo")
	elif time - last_dmg > lim:
		# stallo: decidono gli obiettivi; senza obiettivi, se l'attaccante è nettamente più forte i resti del difensore ripiegano
		_end(_time_winner(), "stallo")

## Esito di uno stallo (nessun danno per molto tempo) o del tempo scaduto: tiene il difensore salvo netta superiorità
## dell'attaccante rispetto a ciò che resta, con i difensori in copertura più difficili da stanare.
func _stall_winner() -> String:
	var att_inf := false
	for u in units:
		if not u.dead and u.side == 0 and u.type == "inf":
			att_inf = true
			break
	if not att_inf:
		# senza fanteria non si stanano i fanti nascosti in boschi, città e trincee: il terreno resta al difensore
		for u in units:
			if not u.dead and u.side == 1 and u.type == "inf" and u.cover > 0:
				return "def"
	var a := [0.0, 0.0]
	var h := [0.0, 0.0]
	for u in units:
		if u.dead:
			continue
		var w := 0.5 if u.stat else 1.0
		if u.side == 1 and not u.air and u.cover > 0:
			w *= STALL_COVER
		a[u.side] += u.mul / u.cd * alive(u) * w
		h[u.side] += u.hp * w
	var pa := sqrt(a[0] * h[0])
	var pd := sqrt(a[1] * h[1])
	return "att" if pa > pd * STALL_ATT else "def"

func _compact() -> void:
	var keep := []
	for u in units:
		if not u.dead:
			keep.append(u)
		else:
			u.tgt = null; u.otgt = null
	units = keep
	for k in groups:
		groups[k] = groups[k].filter(func(u): return not u.dead)

func _end(winner: String, why: String) -> void:
	if ending != null or done:
		return
	ending = {"winner": winner, "t": END_MSG, "why": why}
	result = _make_result(winner, retreating[0] and winner == "def")

## Risultato: superstiti della forza principale (att/def), dei rinforzi (attReinf/defReinf), obiettivi tenuti.
func _make_result(winner: String, retreated: bool) -> Dictionary:
	return {"att": _survivors(0), "def": _survivors(1), "winner": winner, "retreated": retreated, "autoRest": false,
		"attReinf": _survivors(0, true), "defReinf": _survivors(1, true), "objectives": objectives_held(), "time": time,
		"why": String(ending["why"]) if ending != null else ""}

## Ritirata ordinata (solo attaccante umano): i reparti ripiegano al proprio bordo; chi lo raggiunge è salvo, chi resta
## combatte. La battaglia finisce quando l'attaccante non ha più unità sul campo (vince il difensore, `retreated: true`).
func retreat() -> bool:
	if done or ending != null or hs != 0 or retreating[0]:
		return false
	_order_retreat(0)
	return true

## Risolve il resto della battaglia simulandolo davvero (entrambi i lati IA, senza fx, passo grosso).
## Il risultato è definitivo (`autoRest: false`).
func auto_resolve() -> bool:
	if done or ending != null:
		return false
	run_headless(BattleRules.BATTLE_T + 1.0)
	return true

## Simula fino alla fine (o fino a `max_time` s di battaglia) senza vista. Restituisce il risultato.
func run_headless(max_time: float = AUTO_MAX_TIME, dt: float = AUTO_DT) -> Dictionary:
	emit_fx = false
	fx.clear()
	ai_assist = [true, true]
	paused = false
	fast = true
	for u in sel:
		u.sel = false
	sel.clear()
	var guard := 0
	while not done and time < max_time and guard < 20000:
		step(dt)
		guard += 1
	if not done:
		if ending == null:
			# tempo scaduto: decidono gli obiettivi (senza obiettivi: vince l'attaccante solo se nettamente più forte)
			_end(_time_winner(), "tempo")
		done = true
	return result

# ---------------------------------------------------------------------------- IA (vedi BattleAI)
## Gruppo di nemici avvistati più denso (bersaglio dello sbarramento).
func _cluster(si: int):
	var E := 1 - si
	var best: Unit = null
	var bc := 2.0
	var k := 0
	for e in units:
		if e.dead or e.side != E or e.air or not e.spotted[si]:
			continue
		k += 1
		if ((k - 1) % 2) == 1 and units.size() > 80:
			continue
		var c := 0.0
		var own := false
		for o in units:
			if o.dead or o.air:
				continue
			var dx: float = o.x - e.x
			var dy: float = o.y - e.y
			var d2 := dx * dx + dy * dy
			if o.side == E:
				if d2 < 32400: c += 0.5 if o.stat else 1.0
			elif d2 < 300 * 300:
				own = true
				break
		if not own and c > bc:
			bc = c; best = e
	return Vector2(best.x, best.y) if best != null else null

func order_unit(u: Unit, order: int, x: float, y: float, tgt: Unit) -> void:
	u.order = order
	u.ox = clampf(x, 10, W - 10); u.oy = clampf(y, TOP + 10, BOTTOM - 10)
	u.otgt = tgt; u.cap = 0; u.stuck_t = 0; u.prev_d = 1e9; u.chk_t = 0; u.nav_t = 0; u.pass_t = 0
	if order != IDLE:
		u.hold = false
	if order == ATTACK:
		u.tgt = tgt
	elif order == MOVE:
		u.tgt = null; u.ret_t = 0.1
	if order == IDLE:
		u.ax = u.x; u.ay = u.y; u.tgt = null

func formation(list: Array, x: float, y: float, order: int) -> void:
	var n := list.size()
	if n == 0:
		return
	var cx := 0.0
	var cy := 0.0
	var max_r := 0.0
	for u in list:
		cx += u.x; cy += u.y
		if u.r > max_r: max_r = u.r
	cx /= n; cy /= n
	var fx_ := x - cx
	var fy := y - cy
	var fl := sqrt(fx_ * fx_ + fy * fy)
	if fl < 1:
		fx_ = 1; fy = 0
	else:
		fx_ /= fl; fy /= fl
	var lx := -fy
	var ly := fx_
	var sp := maxf(26.0, max_r * 2 + 12)
	var cols := maxi(1, mini(n, int(ceil(sqrt(n * 2.5)))))
	var rows := int(ceil(float(n) / cols))
	var arr := list.duplicate()
	# righe ordinate per ruolo (carri in testa, fanteria, contraerea, artiglieria in coda), poi per posizione
	arr.sort_custom(func(a, b):
		var ba := int(BACK.get(a.type, 0))
		var bb := int(BACK.get(b.type, 0))
		if ba != bb:
			return ba < bb
		return (a.x * fx_ + a.y * fy) > (b.x * fx_ + b.y * fy))
	for r in rows:
		var chunk := arr.slice(r * cols, r * cols + cols)
		chunk.sort_custom(func(a, b): return (a.x * lx + a.y * ly) < (b.x * lx + b.y * ly))
		var m := chunk.size()
		for k in m:
			var ol := (k - (m - 1) / 2.0) * sp
			var of := -(r - (rows - 1) / 2.0) * sp
			order_unit(chunk[k], order, x + lx * ol + fx_ * of, y + ly * ol + fy * of, null)

# ---------------------------------------------------------------------------- comandi (lato umano)
func human_side():
	return sides[hs] if hs >= 0 else null

func own_units() -> Array:
	var out := []
	for u in units:
		if not u.dead and not u.stat and u.side == hs:
			out.append(u)
	return out

func set_selection(list: Array, add: bool) -> void:
	if not add:
		for u in sel:
			u.sel = false
		sel = []
	for u in list:
		if not u.sel and not u.dead:
			u.sel = true
			sel.append(u)

func select_all() -> void:
	if hs < 0 or ending != null:
		return
	set_selection(own_units(), false)

func select_type(type: String) -> void:
	if hs < 0 or ending != null:
		return
	set_selection(own_units().filter(func(u): return u.type == type), false)

func select_units(list: Array, add: bool) -> void:
	if hs < 0 or ending != null:
		return
	set_selection(list.filter(func(u): return not u.dead and not u.stat and u.side == hs), add)

func toggle_unit(u: Unit) -> void:
	if u.sel:
		u.sel = false
		sel.erase(u)
	else:
		select_units([u], true)

func sel_alive() -> Array:
	return sel.filter(func(u): return not u.dead)

## Unità sotto x,y; le unità nemiche non visibili al lato umano vengono ignorate.
func unit_at(x: float, y: float, side: int = -1) -> Unit:
	var best: Unit = null
	var bd := 1e9
	for u in units:
		if u.dead or (side >= 0 and u.side != side):
			continue
		if hs >= 0 and u.side != hs and not u.spotted[hs]:
			continue
		var d: float = Vector2(u.x - x, u.y - y).length() - u.r - (2.0 if u.air else 0.0)
		if d < 6 and d < bd:
			bd = d; best = u
	return best

## Tasto destro: se `enemy` (o un nemico sotto x,y) → attacco, altrimenti movimento in formazione.
func order_move(x: float, y: float, enemy: Unit = null) -> void:
	var own := sel_alive()
	if own.is_empty() or ending != null:
		return
	var e: Unit = enemy if enemy != null else unit_at(x, y, 1 - hs)
	if e != null:
		order_attack(e)
		return
	formation(own, x, y, MOVE)
	marker = {"x": x, "y": y, "t": 0.6, "kind": "move"}

func order_attack(e: Unit) -> void:
	var own := sel_alive()
	if own.is_empty() or e == null or e.dead:
		return
	if hs >= 0 and e.side != hs and not e.spotted[hs]:
		# nemico non visibile: attacco in movimento verso il punto
		formation(own, e.x, e.y, AMOVE)
		marker = {"x": e.x, "y": e.y, "t": 0.6, "kind": "amove"}
		return
	var other := []
	for u in own:
		if float(u.M.get(e.type, 0)) > 0:
			order_unit(u, ATTACK, e.x, e.y, e)
		else:
			other.append(u)
	if not other.is_empty():
		formation(other, e.x, e.y, AMOVE)
	marker = {"x": e.x, "y": e.y, "t": 0.6, "kind": "attack", "tgt": e}

func order_attack_move(x: float, y: float, enemy: Unit = null) -> void:
	var own := sel_alive()
	if own.is_empty() or ending != null:
		return
	var e: Unit = enemy if enemy != null else unit_at(x, y, 1 - hs)
	if e != null and (hs < 0 or e.spotted[hs]):
		var other := []
		for u in own:
			if float(u.M.get(e.type, 0)) > 0:
				order_unit(u, ATTACK, e.x, e.y, e)
			else:
				other.append(u)
		if not other.is_empty():
			formation(other, x, y, AMOVE)
	else:
		formation(own, x, y, AMOVE)
	marker = {"x": x, "y": y, "t": 0.6, "kind": "amove"}

## Artiglieria selezionata: fuoco d'area su x,y (dispersione larga) finché non riceve un altro ordine.
func order_fire_area(x: float, y: float) -> bool:
	var any := false
	for u in sel_alive():
		if u.type == "art":
			order_unit(u, FIRE, x, y, null)
			any = true
	if any:
		marker = {"x": x, "y": y, "t": 0.8, "kind": "barrage", "r": BattleRules.scatter(1500.0) * BattleRules.AREA_SCATTER}
	return any

func stop() -> void:
	for u in sel_alive():
		order_unit(u, IDLE, u.x, u.y, null)
		u.hold = false

## Mantieni posizione (alterna): i selezionati si fermano e sparano solo a ciò che è a tiro, senza inseguire.
## Restituisce il nuovo stato (true = in posizione).
func hold_position() -> bool:
	var own := sel_alive()
	if own.is_empty() or ending != null:
		return false
	var all_hold := true
	for u in own:
		if not u.hold:
			all_hold = false
			break
	for u in own:
		order_unit(u, IDLE, u.x, u.y, null)
		u.hold = not all_hold
	return not all_hold

func human_smoke() -> bool:
	if hs < 0:
		return false
	return smoke(hs, sel_alive())

func human_air_strike(x: float, y: float) -> bool:
	if hs < 0:
		return false
	if air_strike(hs, x, y):
		marker = {"x": x, "y": y, "t": 0.8, "kind": "air", "r": AIR_R}
		return true
	return false

func human_barrage(x: float, y: float) -> bool:
	if hs < 0:
		return false
	if barrage(hs, x, y):
		marker = {"x": x, "y": y, "t": 0.8, "kind": "barrage", "r": BARRAGE_R}
		return true
	return false

## Zona di schieramento iniziale del lato `si` (piano sim).
func deploy_zone(si: int) -> Rect2:
	if si == 0:
		return Rect2(120, TOP + 42, 1680, BOTTOM - TOP - 84)
	# il difensore si prepara in tutta la propria metà del campo (boschi, città, trincee)
	return Rect2(W * 0.5 + 150, TOP + 42, W * 0.5 - 270, BOTTOM - TOP - 84)

## Fase di schieramento (a battaglia in pausa): colloca subito le unità `list` del lato umano in formazione
## attorno a x,y dentro la propria zona (carri davanti, artiglieria dietro), rivolte verso il nemico.
func deploy_place(list: Array, x: float, y: float) -> void:
	if hs < 0 or ending != null or done:
		return
	var own := list.filter(func(u): return not u.dead and not u.stat and u.side == hs)
	var n := own.size()
	if n == 0:
		return
	var Z := deploy_zone(hs)
	var dir := 1.0 if hs == 0 else -1.0
	var max_r := 0.0
	for u in own:
		max_r = maxf(max_r, u.r)
	var sp := maxf(26.0, max_r * 2 + 12)
	var cols := maxi(1, mini(n, int(ceil(sqrt(n * 2.5)))))
	var rows := int(ceil(float(n) / cols))
	var arr := own.duplicate()
	arr.sort_custom(func(a, b):
		var ba := int(BACK.get(a.type, 0))
		var bb := int(BACK.get(b.type, 0))
		return ba < bb if ba != bb else a.y < b.y)
	var hd := (rows - 1) * sp * 0.5 + max_r
	var hw := (cols - 1) * sp * 0.5 + max_r
	x = clampf(x, Z.position.x + hd, Z.end.x - hd) if hd * 2 < Z.size.x else Z.get_center().x
	y = clampf(y, Z.position.y + hw, Z.end.y - hw) if hw * 2 < Z.size.y else Z.get_center().y
	for r in rows:
		var chunk := arr.slice(r * cols, r * cols + cols)
		chunk.sort_custom(func(a, b): return a.y < b.y)
		var m := chunk.size()
		for k in m:
			var u: Unit = chunk[k]
			u.x = x - dir * (r - (rows - 1) / 2.0) * sp
			u.y = y + (k - (m - 1) / 2.0) * sp
			u.vx = 0; u.vy = 0
			u.ang = 0.0 if hs == 0 else PI
			u.tur = u.ang
	for it in 4:
		_separate()
		for u in own:
			u.x = clampf(u.x, Z.position.x + u.r, Z.end.x - u.r)
			u.y = clampf(u.y, Z.position.y + u.r, Z.end.y - u.r)
	for u in own:
		if not u.air:
			_push_out(u)
		order_unit(u, IDLE, u.x, u.y, null)
	_upd_vis(true)

func store_group(k: int) -> void:
	groups[k] = sel_alive()

func recall_group(k: int) -> void:
	if groups.has(k):
		set_selection(groups[k].filter(func(u): return not u.dead), false)

func toggle_pause() -> void:
	if not done:
		paused = not paused

## Forze mobili rimaste per tipo (per l'HUD).
func live_forces(si: int) -> Dictionary:
	return _survivors(si)

func bunkers_alive() -> int:
	var n := 0
	for u in units:
		if not u.dead and u.stat:
			n += 1
	return n
