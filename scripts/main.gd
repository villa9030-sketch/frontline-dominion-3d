extends Node
## FRONTLINE DOMINION 3D — flusso di gioco e controller dell'interfaccia (porting di frontline/js/ui.js + main.js).
## menu → Game.new(opts) → WorldMap (scenes/world_map.tscn) + HUD → battaglia (scenes/battle.tscn) → ritorno.
## Integra i moduli degli altri agenti solo se esistono (caricamento dinamico, nessun riferimento a class_name esterni).

const GAME_PATH := "res://scripts/core/game.gd"
const COMBAT_PATH := "res://scripts/core/combat.gd"
const MAP_SCENE := "res://scenes/world_map.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const MOCK_GAME := "res://scripts/ui/mock_game.gd"
const PLACEHOLDER_MAP := "res://scripts/ui/placeholder_map.gd"
const SaveStore := preload("res://scripts/ui/save_store.gd")
const HIST_EVERY := 10.0
const MODE_NAMES := {"conquista": "Conquista mondiale", "obiettivo": "Obiettivo segreto"}

const DEPLOY_COLOR := Color(0.47, 1.0, 0.63, 0.9)
const CARD_COLOR := Color(1.0, 0.35, 0.27, 0.95)

var game = null
var map: Node = null
var map_is_3d := false
var map_layer: CanvasLayer   # contiene il tabellone segnaposto 2D
var ui_layer: CanvasLayer
var ui_root: Control
var hud: Control
var menu: Control
var modal: Control
var toasts: Control
var battle: Node = null
var battle_setup = null
var battle_info = null
var _battle_holder: Node = null
var _transition := false   # transizione cinematica tabellone ↔ battaglia in corso (input del tabellone bloccato)
var using_mock := false

# stato dell'interfaccia (come UI nel JS)
var sel := -1
var hover := -1
var quota := 0.5
var mode = null            # null | {type:"deploy"} | {type:"card", op, cards}
var sel_cards: Array = []
var targets: Array = []
var target_set := {}
var drag = null            # {from, pos0, active}
var menu_opts := {"faction": 0, "opp": 3, "diff": "veterano", "mode": "conquista", "dist": "regionale", "ask_defense": true, "auto_battles": false, "fog": false, "fog_mode": "none"}
var modal_kind := ""
var modal_closable := true
var _paused_before := false
var _help_paused := false
var _help_return: Callable = Callable()
var _refresh_t := 0.0
var _seen_div := {}
var _alert_t := -100.0
var _card_count := -1
var _end_shown := false
var _elim_shown := false
var _elim_pending := false
var _recent_toasts := []
var _menu_bg_t := 0.0
var _menu_bg_i := 0
var _combat_script = null
var _sent_marks := ""
var _bound_game = null
var tutorial: Control
var coach: Control             # tutorial guidato del primo turno (scripts/ui/coach.gd)
var _hist: Array = []          # cronologia di riserva se il nucleo non fornisce game.history
var _hist_next := 0.0
var _autosave_next := 0.0
var _last_save_real := -1000.0
var _thumb: Image = null
var _tension_until := 0.0
var _mood := ""
var _cursor_mode := ""
var _tut_t := 0.0
var threats: Array = []
var _threat_key := ""
var _demo_threats: Array = []   # solo per gli screenshot dimostrativi
var _threat_i := -1
var _vet_seen := {}             # territorio -> [owner, vet] per l'annuncio delle stelle
var _pact_offers: Array = []    # offerte di patto delle IA in attesa di essere mostrate
var _pact_offer = null          # offerta mostrata ora {from, to, t_end}
const PACT_OFFER_SECS := 30.0   # tempo reale per rispondere (poi si intende rifiutata)

# ================================================================== avvio
func _ready() -> void:
	get_window().min_size = Vector2i(800, 450)
	map_layer = CanvasLayer.new()
	map_layer.layer = -1
	add_child(map_layer)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UIKit.theme()
	ui_layer.add_child(ui_root)
	hud = load("res://scripts/ui/hud.gd").new()
	hud.main = self
	hud.visible = false
	ui_root.add_child(hud)
	menu = load("res://scripts/ui/menu.gd").new()
	menu.main = self
	ui_root.add_child(menu)
	toasts = load("res://scripts/ui/toasts.gd").new()
	ui_root.add_child(toasts)   # sotto le finestre modali
	modal = load("res://scripts/ui/modal.gd").new()
	modal.main = self
	ui_root.add_child(modal)
	if Shot.has_arg("shot") or Shot.has_arg("quit-after") or OS.get_cmdline_args().has("--script"):
		SaveStore.DIR = "user://saves_test"   # i test automatici non toccano i salvataggi veri
	tutorial = load("res://scripts/ui/tutorial.gd").new()
	tutorial.main = self
	ui_root.add_child(tutorial)
	coach = load("res://scripts/ui/coach.gd").new()
	coach.main = self
	ui_root.add_child(coach)
	_setup_cursors()
	if Settings.has_signal("changed"):
		Settings.changed.connect(_on_setting)
	if ResourceLoader.exists(COMBAT_PATH):
		_combat_script = load(COMBAT_PATH)
	# l'argomento --demo è dell'interfaccia: lo tolgo prima di istanziare tabellone/battaglia (che hanno demo proprie)
	var demo := Shot.arg("demo")
	if Shot.has_arg("demo") and "_args" in Shot:
		Shot._args.erase("demo")
	_show_menu()
	if demo != "":
		call_deferred("_run_demo", demo)

func _show_menu(page: String = "home") -> void:
	menu.visible = true
	menu.page = page
	menu.refresh()
	_setup_menu_background()
	music("menu")

## Sfondo del menu: tabellone 3D (se esiste) con una partita IA ferma e la camera che scorre tra i territori.
func _setup_menu_background() -> void:
	var g = null
	if ResourceLoader.exists(MAP_SCENE) and _game_script() != null:
		var players := []
		for i in Data.FACTIONS.size():
			players.append({"faction": i, "human": false, "difficulty": "veterano"})
		g = _new_game({"players": players, "mode": "conquista", "distribution": "regionale", "seed": 7, "ask_defense": false, "auto_battles": false, "fog": false})
	_create_map(g)
	_menu_bg_t = 0.0

func _game_script():
	if ResourceLoader.exists(GAME_PATH):
		var s = load(GAME_PATH)
		if s != null and s is Script and s.can_instantiate():
			return s
	return null

func _new_game(opts: Dictionary):
	var s = _game_script()
	using_mock = false
	if s == null:
		using_mock = true
		s = load(MOCK_GAME)
	if not opts.has("ai_step_delay") and Settings.has_method("ai_step_delay"):
		opts["ai_step_delay"] = Settings.ai_step_delay()
	var g = s.new(opts)
	return g

## Un solo tabellone per tutta la sessione (la generazione del rilievo costa): si ricollega con bind() a ogni partita.
func _create_map(g) -> void:
	if _bound_game != null and _bound_game != g and _bound_game.has_method("dispose"):
		_bound_game.dispose()   # spezza i riferimenti circolari IA ↔ partita
	_bound_game = g
	if map != null and is_instance_valid(map):
		if map.has_method("bind"):
			map.bind(g)
		_sent_marks = ""
		_reset_map_view()
		return
	map_is_3d = false
	if ResourceLoader.exists(MAP_SCENE):
		var ps = load(MAP_SCENE)
		if ps is PackedScene:
			map = ps.instantiate()
			map_is_3d = true
			add_child(map)
			move_child(map, 0)
	if map == null:
		map = load(PLACEHOLDER_MAP).new()
		map_layer.add_child(map)
	if map.has_method("bind") and (g != null or not map_is_3d):
		map.bind(g)
	if map.has_signal("territory_clicked"):
		map.territory_clicked.connect(_on_map_clicked)
	if map.has_signal("territory_hovered"):
		map.territory_hovered.connect(_on_map_hovered)
	if map.has_signal("drag_released"):
		map.drag_released.connect(_on_map_drag_released)
	_sent_marks = ""

func _reset_map_view() -> void:
	if map == null:
		return
	if map.has_method("set_selection"):
		map.set_selection(-1)
	if map.has_method("set_targets"):
		map.set_targets([])
	if map.has_method("set_marks"):
		map.set_marks([], Color.WHITE)
	if map.has_method("clear_drag"):
		map.clear_drag()

func _free_map() -> void:
	if map != null and is_instance_valid(map):
		if map.get_parent():
			map.get_parent().remove_child(map)
		map.queue_free()
	map = null

# ================================================================== partita
func start_game(spectator: bool) -> void:
	var o := menu_opts
	var players := []
	if spectator:
		for i in Data.FACTIONS.size():
			players.append({"faction": i, "human": false, "difficulty": o["diff"]})
	else:
		players.append({"faction": o["faction"], "human": true, "difficulty": o["diff"]})
		var n := 0
		for i in Data.FACTIONS.size():
			if i != o["faction"] and n < int(o["opp"]):
				players.append({"faction": i, "human": false, "difficulty": o["diff"]})
				n += 1
	var opts := {"players": players, "mode": o["mode"], "distribution": o["dist"], "seed": int(Time.get_unix_time_from_system()) & 0x7fffffff,
		"ask_defense": o["ask_defense"], "auto_battles": o["auto_battles"], "fog": bool(o.get("fog", false)) and not spectator,
		"fog_mode": "none" if spectator else String(o.get("fog_mode", "none"))}
	var g = _new_game(opts)
	if g == null:
		toast("Errore nell'avvio della partita", "bad")
		return
	_begin_game(g, false)

# ------------------------------------------------------------------ scenari (FASE 4)
## Opzioni di Game.new per uno scenario: giocatori dallo scenario se li fissa, altrimenti fazione consigliata + avversari.
func scenario_opts(S: Dictionary, fac: int = -1) -> Dictionary:
	var o := menu_opts
	if fac < 0:
		fac = menu.scn_faction(S)
	if fac < 0 or fac >= Data.FACTIONS.size():
		fac = int(o["faction"])
	var dk := String(menu.sf(S, ["difficulty", "diff"], ""))
	var diff: String = dk if Data.DIFFICULTY.has(dk) else String(o["diff"])
	var players := []
	var sp = S.get("players", null)
	if sp is Array and not sp.is_empty():
		for P in sp:
			if P is Dictionary:
				players.append(P.duplicate(true))
			else:
				players.append({"faction": int(P), "human": int(P) == fac, "difficulty": diff})
	else:
		players.append({"faction": fac, "human": true, "difficulty": diff})
		var n := 0
		var opp := int(menu.sf(S, ["opp", "opponents"], 3))
		for i in Data.FACTIONS.size():
			if i != fac and n < opp:
				players.append({"faction": i, "human": false, "difficulty": diff})
				n += 1
	return {"players": players, "mode": String(menu.sf(S, ["mode"], o["mode"])), "distribution": String(menu.sf(S, ["distribution", "dist"], "regionale")),
		"seed": int(menu.sf(S, ["seed"], int(Time.get_unix_time_from_system()) & 0x7fffffff)),
		"ask_defense": o["ask_defense"], "auto_battles": o["auto_battles"], "fog": bool(menu.sf(S, ["fog"], o.get("fog", true))),
		"fog_mode": String(menu.sf(S, ["fog_mode"], "full" if bool(menu.sf(S, ["fog"], false)) else "none")),
		"scenario": String(S.get("id", ""))}

func make_scenario_game(S: Dictionary, _preview: bool = false, fac: int = -1):
	if _game_script() == null:
		return null
	var opts := scenario_opts(S, fac)
	if _preview:
		opts["seed"] = 12345
	return _game_script().new(opts)

func start_scenario(id: String, fac: int = -1) -> void:
	var S = menu.scenario_by_id(id)
	if S == null:
		toast("Scenario non trovato: " + id, "bad")
		return
	var g = _new_game(scenario_opts(S, fac))
	if g == null:
		toast("Errore nell'avvio dello scenario", "bad")
		return
	_begin_game(g, false)
	show_briefing()

## Dati dello scenario della partita in corso (null in una partita normale).
func current_scenario():
	if game == null:
		return null
	var id := ""
	if "scenario" in game and game.scenario != null:
		id = String(game.scenario.get("id", "")) if game.scenario is Dictionary else String(game.scenario)
	elif "opts" in game and game.opts is Dictionary:
		id = String(game.opts.get("scenario", ""))
	if id == "":
		return null
	var S = menu.scenario_by_id(id)
	if S == null and "scenario" in game and game.scenario is Dictionary:
		return game.scenario
	return S

## Stato dell'operazione per il pannello: {text, progress (0..1, opzionale), time_left (s, opzionale)}.
## Usa game.scenario_status(h) se il nucleo lo fornisce, altrimenti lo ricava dalle regole pubbliche dello scenario.
func scenario_status() -> Dictionary:
	if current_scenario() == null:
		return {}
	if game.has_method("scenario_status"):
		var r = game.scenario_status(h())
		if r is Dictionary:
			return r
	var st := {}
	var tl := float(game.time_limit) if "time_limit" in game else 0.0
	if tl > 0:
		st["time_left"] = maxf(0.0, tl - float(game.time))
	var hh := h()
	var nt := Data.TERRITORIES.size()
	var siege := int(game.siege_idx) if "siege_idx" in game else -1
	var hold: Array = game.hold_terrs if "hold_terrs" in game else []
	if not hold.is_empty():
		var need := int(game.hold_need) if "hold_need" in game else hold.size()
		var secs := float(game.hold_secs) if "hold_secs" in game else 0.0
		var mine := 0
		for t in hold:
			if hh >= 0 and int(game.terr[int(t)]["owner"]) == hh:
				mine += 1
		var ho := int(game.get("_hold_owner")) if "_hold_owner" in game else -1
		var txt := "Territori chiave: tuoi %d/%d (ne servono %d)" % [mine, hold.size(), need]
		if ho >= 0 and secs > 0:
			var held := float(game.time) - float(game.get("_hold_since"))
			txt += " · %s li tiene da %d s su %d" % [game.players[ho]["fac"]["short"], int(held), int(secs)]
			st["progress"] = clampf(held / secs, 0.0, 1.0)
		st["text"] = txt
	elif siege >= 0:
		var n := 0
		for tr in game.terr:
			if int(tr["owner"]) == siege:
				n += 1
		var sn: String = game.players[siege]["fac"]["short"]
		if hh == siege:
			st["text"] = "Resisti fino allo scadere: controlli %d territori" % n
		else:
			st["text"] = "%s assediata: le restano %d territori" % [sn, n]
	elif hh >= 0:
		var mine2: int = gcall("territories_of", [hh], []).size()
		var share := float(game.victory_share) if "victory_share" in game else float(Data.ECON["victoryShare"])
		var need2 := int(ceil(share * nt))
		st["text"] = "Territori: %d su %d necessari" % [mine2, need2]
		st["progress"] = clampf(float(mine2) / maxf(1.0, need2), 0.0, 1.0)
	return st

## Briefing all'avvio di uno scenario (partita in pausa finché non si chiude).
func show_briefing() -> void:
	var S = current_scenario()
	if S == null or game == null:
		return
	_paused_before = false
	game.paused = true
	show_modal("briefing", modal.build_briefing(S), true)

## Collega una partita (nuova o caricata) a tabellone, HUD e controller.
func _begin_game(g, loaded: bool) -> void:
	if battle != null:
		_end_battle_scene()
	if game != null and game != g and game.has_signal("event") and game.event.is_connected(_on_signal):
		game.event.disconnect(_on_signal)
	game = g
	battle = null
	sel = -1; hover = -1; mode = null; sel_cards = []; drag = null
	targets = []; target_set = {}
	_seen_div = {}; _end_shown = game.over != null; _elim_shown = false; _elim_pending = false; _card_count = -1
	_recent_toasts = []
	_vet_seen = {}
	_pact_offers = []
	_pact_offer = null
	_turn_seen = ""
	_recap_key = ""
	_recap = []
	_news_q = []
	_ai_fast = false
	_force_ctx = null
	_argc_cache = {}
	if not loaded:
		_hist = []
	_hist_next = 0.0
	_autosave_next = float(game.time) + _autosave_every()
	_tension_until = 0.0
	if game.has_signal("event"):
		game.event.connect(_on_signal)
	menu.visible = false
	close_modal(true)
	set_mode(null)
	_create_map(game)
	hud.visible = true
	hud.start(game)
	tutorial.reset()
	coach.stop(false)
	if h() >= 0:
		var P: Dictionary = game.players[h()]
		if int(P["hq"]) >= 0:
			select(int(P["hq"]))
			if map.has_method("focus"):
				map.focus(int(P["hq"]))
		if loaded:
			if turn_mode():
				toast("Partita caricata: turno %d · %s" % [round_n(), P["name"]], "good")
			else:
				toast("Partita caricata: minuto %s · %s" % [UIKit.fmt_time(game.time), P["name"]], "good")
		else:
			toast("Sei " + P["name"] + ". Il tuo QG è in " + (Data.TERRITORIES[P["hq"]]["name"] if int(P["hq"]) >= 0 else "—") + ".", "info")
	else:
		toast(("Partita caricata. " if loaded else "") + "Modalità spettatore: %d IA si contendono il mondo." % game.players.size(), "info")
	if using_mock:
		toast("Nucleo di gioco non ancora disponibile: partita segnaposto", "bad")
	Sfx.play("order")
	music("map")
	_record_history(true)
	_apply_ai_delay()
	refresh(true)
	if turn_mode():
		call_deferred("_on_turn_start", cur_player())
	# primo turno guidato: alla prima campagna (o dal menu «Tutorial»)
	var tut := _force_tutorial or (not loaded and current_scenario() == null and _auto_tutorial_ok())
	_force_tutorial = false
	if tut and turn_mode() and human_alive() and my_turn():
		coach.start()

func back_to_menu(page: String = "home") -> void:
	if battle != null:
		_end_battle_scene()
	if game != null and game.has_signal("event") and game.event.is_connected(_on_signal):
		game.event.disconnect(_on_signal)
	game = null
	mode = null
	hud.set_mode_banner(null)
	_apply_cursor("")
	close_modal(true)
	hud.visible = false
	hud.hide_tip()
	tutorial.reset()
	coach.stop(false)
	toasts.clear_all()
	_show_menu(page)

# ================================================================== helper di stato
func h() -> int:
	return int(game.human_idx) if game != null else -1

func human_alive() -> bool:
	return game != null and h() >= 0 and bool(game.players[h()]["alive"])

func sel_own() -> bool:
	return game != null and sel >= 0 and human_alive() and int(game.terr[sel]["owner"]) == h()

func gcall(method: String, args: Array = [], def = null):
	if game != null and game.has_method(method):
		return game.callv(method, args)
	return def

func pget(P: Dictionary, keys: Array, def = 0):
	for k in keys:
		if P.has(k):
			return P[k]
	return def

## Nebbia di guerra attiva nella partita?
func fog_on() -> bool:
	return game != null and h() >= 0 and "fog" in game and bool(game.fog)

## Il giocatore umano vede il territorio t? (sempre vero senza nebbia o da spettatore)
func is_vis(t: int) -> bool:
	if not fog_on() or t < 0:
		return true
	return bool(gcall("is_visible", [h(), t], true))

## Stima delle forze di un territorio nella nebbia (-1 = sconosciute).
func estimate(t: int) -> int:
	var e = gcall("estimate_forces", [h(), t], -1)
	return int(e) if e != null else -1

## Testo delle forze per un territorio non visibile ("forze stimate circa 10–15" / "forze sconosciute").
func fog_text(t: int) -> String:
	var e := estimate(t)
	if e < 0:
		return "forze sconosciute"
	var txt = gcall("estimate_text", [h(), t], "circa %d" % e)
	return "forze stimate " + String(txt)

## Stima leggibile delle forze di un territorio non visibile ("circa 10–15", "sconosciute").
func estimate_text(t: int) -> String:
	return String(gcall("estimate_text", [h(), t], "sconosciute"))

## Logoramento di un territorio (turni al recupero, 0 = fresco).
func worn_of(t: int) -> int:
	if game == null or t < 0:
		return 0
	return int(game.terr[t].get("worn", 0))

## Stelle di veterania di un territorio (0..3).
func vet_of(t: int) -> int:
	if game == null or t < 0:
		return 0
	return clampi(int(game.terr[t].get("vet", 0)), 0, 3)

static func stars(n: int) -> String:
	return "★".repeat(clampi(n, 0, 3))

## Patto attivo tra a e b: {a, b, until} oppure null.
func pact_between(a: int, b: int):
	if game == null or not ("pacts" in game) or not (game.pacts is Array):
		return null
	for pc in game.pacts:
		if (int(pc["a"]) == a and int(pc["b"]) == b) or (int(pc["a"]) == b and int(pc["b"]) == a):
			if turn_mode():
				if int(pc.get("until", 0)) >= round_n():
					return pc
			elif float(pc.get("until", 0)) > float(game.time):
				return pc
	return null

## «fino al turno N» (turni) oppure «fino a mm:ss» (tempo reale).
func until_text(u: float) -> String:
	if turn_mode():
		return "fino al turno %d" % int(u)
	return "fino a " + UIKit.fmt_time(u)

## Tempo o turni rimanenti di un patto (testo breve).
func pact_left_text(pc) -> String:
	if pc == null:
		return ""
	if turn_mode():
		var n := maxi(0, int(pc["until"]) - round_n() + 1)
		return "%d turn%s" % [n, "o" if n == 1 else "i"]
	return UIKit.fmt_time(maxf(0.0, float(pc["until"]) - float(game.time)))

func diplomacy_available() -> bool:
	return game != null and game.has_method("propose_pact")

func propose_pact(to: int) -> void:
	if not human_alive() or not diplomacy_available():
		return
	var r = gcall("propose_pact", [h(), to])
	if not (r is Dictionary):
		return
	var nm: String = String(game.players[to]["fac"]["short"])
	var reason := String(r.get("reason", ""))
	if r.get("ok", false) and r.get("accepted", false):
		Sfx.play("research")   # il segnale "pact" mostra il patto con la scadenza
		if not ("pacts" in game):
			toast(nm + " accetta il patto di non aggressione", "good")
	elif r.get("ok", false):
		Sfx.play("click")
		toast(reason if reason.begins_with(nm) else ("%s rifiuta il patto%s" % [nm, (": " + reason) if reason != "" else ""]), "bad")
	else:
		toast(reason if reason != "" else "Proposta non possibile", "bad")
	refresh(true)

func card_targets(op: String) -> Array:
	var out := []
	if String(Data.OPS.get(op, {}).get("target", "")) == "self":
		return gcall("territories_of", [h()], [])   # divisione falsa / silenzio radio: un proprio territorio
	for tr in game.terr:
		if int(tr["owner"]) == h():
			continue
		if int(tr["owner"]) >= 0 and pact_between(h(), int(tr["owner"])) != null:
			continue   # partner di un patto: le OPS sono vietate
		if op == "golpe":
			var f = gcall("visible_forces", [h(), tr["idx"]], tr["forces"])
			if f != null and Data.total_units(f) > Data.GOLPE_MAX:
				continue
			var is_hq := false
			for q in game.players:
				if q["alive"] and int(q["hq"]) == int(tr["idx"]):
					is_hq = true
			if is_hq:
				continue
		out.append(tr["idx"])
	return out

func send_forces(t: int) -> Dictionary:
	var f: Dictionary = game.terr[t]["forces"]
	var o := Data.empty_forces()
	for k in Data.UNIT_KEYS:
		o[k] = int(f.get(k, 0)) if quota >= 1.0 else int(floor(int(f.get(k, 0)) * quota + 1e-9))
	if Data.total_units(o) == 0 and Data.total_units(f) > 0:
		var b := ""
		for k in Data.UNIT_KEYS:
			if int(f.get(k, 0)) > 0 and (b == "" or f[k] > f[b]):
				b = k
		o[b] = 1
	return o

func combat_mods(p: int, role: String, t: int, opts: Dictionary):
	if _combat_script == null:
		return null
	return _combat_script.combat_mods(game, p, role, t, opts)

func predict(att: Dictionary, def: Dictionary, ma, md):
	if _combat_script == null:
		return null
	return _combat_script.predict_battle(att, def, ma, md)

## Previsione per il pannello d'attacco: nucleo (predict_attack, nebbia compresa) o Combat.predict_battle.
func predict_attack(from: int, to: int, forces: Dictionary):
	if Data.total_units(forces) <= 0:
		return null
	if game.has_method("predict_attack"):
		var r = tcall("predict_attack", [from, to, forces], null)
		if r is Dictionary and not r.is_empty():
			return r
		return null
	var df = gcall("visible_forces", [h(), to], game.terr[to]["forces"])
	if df == null:
		return null
	var ma = combat_mods(h(), "att", to, {"fromIdx": from, "from_idx": from, "manual": false, "vet": vet_of(from)})
	var md = combat_mods(int(game.terr[to]["owner"]), "def", to, {"manual": false, "vet": vet_of(to)})
	return predict(forces, df, ma, md)

# ================================================================== ciclo
func _process(dt: float) -> void:
	_tut_t -= dt
	if _tut_t <= 0:
		_tut_t = 0.25
		tutorial.update()
		coach.update()
	if battle != null:
		return
	if game == null:
		_menu_bg_t += dt
		if map_is_3d and map != null and map.has_method("focus") and _menu_bg_t > 7.0:
			_menu_bg_t = 0.0
			var order := [15, 34, 5, 25, 11, 37, 20, 41, 28, 2]
			_menu_bg_i = (_menu_bg_i + 1) % order.size()
			map.focus(order[_menu_bg_i])
		return
	game.update(_ai_dt(dt))
	_record_history(false)
	if turn_mode():
		var cp := cur_player()
		if "%d|%d" % [cp, round_n()] != _turn_seen and game.pending_battle == null:
			_on_turn_start(cp)
	else:
		_check_autosave()
	_update_music()
	_update_drag()
	if game.pending_battle != null and battle == null and modal_kind != "battle" and modal_kind != "help" and not _transition:
		if modal_kind == "pact":
			_defer_pact_offer()
		show_battle_prompt()
	_update_pact_offer()
	if game.over != null and not _end_shown and battle == null:
		show_end()
	_refresh_t -= dt
	if _refresh_t <= 0:
		_refresh_t = 0.2
		refresh(false)
	hud.update_tip()

func refresh(force: bool) -> void:
	if game == null or battle != null:
		return
	if force:
		_refresh_t = 0.2
	if sel_own() and turn_mode():
		targets = []
		if my_phase("attack") or (my_phase("supply") and not move_used()):
			if not attack_used() and not move_used():
				targets = attack_targets(sel)
		elif my_phase("move") and not move_used() and int(game.terr[sel].get("regroup", 0)) <= 0:
			targets = move_targets(sel)
		target_set = {}
		for t in targets:
			target_set[int(t["idx"])] = true
	elif sel_own():
		targets = gcall("valid_targets", [h(), sel], [])
		target_set = {}
		for t in targets:
			target_set[int(t["idx"])] = true
	else:
		targets = []
		target_set = {}
	if mode != null and mode["type"] == "deploy" and (h() < 0 or Data.total_units(game.players[h()]["pool"]) == 0 or (turn_mode() and not my_phase("supply"))):
		mode = null
		hud.set_mode_banner(null)
		_apply_cursor("")
	# rinforzi da schierare: lo schieramento è già attivo (un clic su un tuo territorio), salvo «Annulla»
	if turn_mode() and mode == null and not _deploy_off and modal_kind == "" and my_phase("supply") and _pool_n() > 0:
		mode = {"type": "deploy"}
		hud.set_mode_banner(mode)
		_apply_cursor("deploy")
	_push_map_view()
	hud.refresh(force)
	_check_threats()
	_check_vet()

## Aggiorna selezione, bersagli e marcature sul tabellone.
func _push_map_view() -> void:
	if map == null:
		return
	var tg := targets if (sel_own() and mode == null) else []
	var marks := []
	var mc := Color.WHITE
	if mode != null and mode["type"] == "deploy":
		marks = gcall("territories_of", [h()], [])
		mc = DEPLOY_COLOR
	elif mode != null and mode["type"] == "card":
		marks = card_targets(mode["op"])
		mc = CARD_COLOR
	elif turn_mode() and not (sel_own() and not targets.is_empty()):
		# cosa si può cliccare adesso: origini d'attacco (ambra) o di spostamento (azzurro)
		marks = click_marks()
		mc = MARK_ATTACK if phase_key() == "attack" else MARK_MOVE
	var key := str(sel) + "|" + str(tg) + "|" + str(marks) + "|" + str(mc)
	if key == _sent_marks:
		return
	_sent_marks = key
	if map.has_method("set_selection"):
		map.set_selection(sel)
	if map.has_method("set_targets"):
		map.set_targets(tg)
	if map.has_method("set_marks"):
		map.set_marks(marks, mc)

func _check_threats() -> void:
	if h() < 0:
		return
	if turn_mode():
		# notte 3: attacchi che le IA stanno preparando contro i miei territori (annunciati a fine turno)
		threats = []
		if game.has_method("threats_for") and human_alive():
			for th in game.threats_for(h()):
				threats.append({"to": int(th["to"]), "from": int(th["from"]), "owner": int(th["player"]), "n": int(th["att"]), "def": int(th["def"]), "left": 0.0, "turn": true})
		hud.set_threats(threats)
		var tk := str(threats)
		if tk != _threat_key:
			_threat_key = tk
			if map != null and map.has_method("set_threats"):
				map.set_threats(threats)   # disegno a carico della mappa (richiesta a GRAFICA in docs/notte3_richieste.md)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var alive := {}
	threats = []
	for d in game.divisions:
		alive[d["id"]] = true
		var tt := int(d["to"])
		if int(d["owner"]) != h() and not d.get("retreat", false) and tt >= 0 and int(game.terr[tt]["owner"]) == h():
			threats.append({"to": tt, "owner": int(d["owner"]), "n": Data.total_units(d["forces"]), "left": float(d.get("total", 0)) - float(d.get("t", 0))})
		if _seen_div.has(d["id"]):
			continue
		_seen_div[d["id"]] = true
		var to := int(d["to"])
		if int(d["owner"]) != h() and not d.get("retreat", false) and to >= 0 and int(game.terr[to]["owner"]) == h():
			_tension_until = float(game.time) + 35.0
			if now - _alert_t > 2.5:
				_alert_t = now
				Sfx.play("alert")
				hud.flash_alert()
				toast("%s: %d unità in arrivo su %s" % [game.players[d["owner"]]["fac"]["short"], Data.total_units(d["forces"]), Data.TERRITORIES[to]["name"]], "alert")
	for id in _seen_div.keys():
		if not alive.has(id):
			_seen_div.erase(id)
	if threats.is_empty() and not _demo_threats.is_empty():
		threats = _demo_threats.duplicate(true)
	threats.sort_custom(func(a, b): return a["left"] < b["left"])
	hud.set_threats(threats)

## Clic sull'indicatore di minaccia: inquadra il prossimo territorio sotto attacco.
func focus_threat() -> void:
	if threats.is_empty():
		return
	_threat_i = (_threat_i + 1) % threats.size()
	var t := int(threats[_threat_i]["to"])
	select(t)
	if map != null and map.has_method("focus"):
		map.focus(t)

# ================================================================== turni (FASE 6)
## La mappa strategica è a turni (Risiko): il nucleo espone end_turn/end_phase/attack/move/fortify.
## Tutto è letto con controlli has_method/"in" così l'interfaccia funziona anche con un nucleo più vecchio.
const PHASES := ["supply", "attack", "move"]
const PHASE_NAMES := {"supply": "Rifornimento", "attack": "Attacco", "move": "Spostamento"}
const ONLY_SUPPLY := "Solo nella fase di rifornimento"
var _argc_cache := {}
var _ai_fast := false           # Spazio durante il turno IA: animazioni accelerate fino al prossimo turno umano
var _force_sel := {}            # forze scelte nel pannello attacco/spostamento
var _force_ctx = null           # {kind:"attack"|"move", from, to}
var _turn_seen := ""            # ultimo "giocatore|turno" annunciato
var _autosave_turn := -1

func turn_mode() -> bool:
	return game != null and game.has_method("end_turn")

## Numero di argomenti di un metodo del nucleo (per chiamare sia f(p, ...) sia f(...)).
func _argc(method: String) -> int:
	if _argc_cache.has(method):
		return _argc_cache[method]
	var n := -1
	if game != null and game.get_script() != null:
		for m in game.get_script().get_script_method_list():
			if String(m.get("name", "")) == method:
				var al: Array = m.get("args", [])
				n = al.size()
				if n > 0:
					_argc_cache[method + ":0"] = String(al[0].get("name", ""))
				break
	_argc_cache[method] = n
	return n

## Chiama un comando di turno: se il metodo vuole anche il giocatore come primo argomento, lo aggiunge.
func tcall(method: String, args: Array = [], def = null):
	if game == null or not game.has_method(method):
		return def
	var n := _argc(method)
	if n == args.size() + 1 or (n > args.size() and String(_argc_cache.get(method + ":0", "")) in ["p", "player"]):
		args = [h()] + args
	elif n >= 0 and n < args.size():
		args = args.slice(0, n)
	return game.callv(method, args)

func round_n() -> int:
	if game == null:
		return 0
	if "round" in game:
		return maxi(1, int(game.round))
	return 1

func cur_player() -> int:
	if game == null:
		return -1
	if "current" in game and game.current != null:
		return int(game.current)
	return h()

## Fase attuale normalizzata: "supply" | "attack" | "move" | "" (fuori turno).
func phase_key() -> String:
	if game == null or not ("phase" in game):
		return ""
	var p = game.phase
	if p is int or p is float:
		return PHASES[clampi(int(p), 0, 2)]
	var s := String(p).to_lower()
	if s.begins_with("rif") or s.begins_with("sup") or s.begins_with("dep") or s.begins_with("rei"):
		return "supply"
	if s.begins_with("att"):
		return "attack"
	if s.begins_with("spo") or s.begins_with("mov") or s.begins_with("for"):
		return "move"
	return ""

func turn_status() -> Dictionary:
	var r = gcall("turn_status", [], null)
	return r if r is Dictionary else {}

## Tocca al giocatore umano?
func my_turn() -> bool:
	if not turn_mode():
		return true
	if not human_alive() or game.over != null:
		return false
	if game.has_method("is_human_turn"):
		return bool(game.is_human_turn()) and cur_player() == h()
	return cur_player() == h()

func my_phase(k: String) -> bool:
	return my_turn() and (not turn_mode() or phase_key() == k)

## Azioni economiche (reclutare, costruire, ricerca, mercato, carte, mercenari, schierare, fortificare).
func can_supply() -> bool:
	return not turn_mode() or my_phase("supply")

## Motivo per cui un'azione di rifornimento non è possibile ora ("" = possibile).
func supply_block() -> String:
	if can_supply():
		return ""
	if turn_mode() and not my_turn():
		return "Non è il tuo turno"
	return ONLY_SUPPLY

## Turni di tregua rimasti (0 = nessuna tregua).
func truce_turns() -> int:
	if not turn_mode():
		return 0
	var st := turn_status()
	for k in ["truce_rounds_left", "truce_left", "truce_turns"]:
		if st.has(k) and (st[k] is int or st[k] is float):
			return maxi(0, int(st[k]))
	if game.has_method("truce_left"):
		return maxi(0, int(tcall("truce_left", [], 0)))
	if "truce_rounds" in game:
		return maxi(0, int(game.truce_rounds) - round_n() + 1)
	return 0

## Attacchi consentiti in questo turno (1 di regola; 2 nella tregua iniziale; +1 con «Finestra di bel tempo»).
func attacks_max() -> int:
	return int(game.attacks_max()) if game != null and game.has_method("attacks_max") else 1

func attacks_left() -> int:
	if game != null and game.has_method("attacks_left"):
		return int(game.attacks_left())
	return 0 if attack_used() else 1

## Almeno un attacco fatto in questo turno (per il tutorial: attack_used() è «attacchi finiti»).
func attacked_any() -> bool:
	if game != null and "attacks_done" in game:
		return int(game.attacks_done) > 0
	return attack_used()

func attack_used() -> bool:
	if "attack_used" in game:
		return bool(game.attack_used)
	var st := turn_status()
	for k in ["attacked", "attack_done", "attacks_done"]:
		if st.has(k):
			return bool(st[k]) if not (st[k] is int) else int(st[k]) > 0
	if st.has("attacks_left"):
		return int(st["attacks_left"]) <= 0
	return false

func move_used() -> bool:
	if "move_used" in game:
		return bool(game.move_used)
	var st := turn_status()
	for k in ["moved", "move_done", "moves_done"]:
		if st.has(k):
			return bool(st[k]) if not (st[k] is int) else int(st[k]) > 0
	if st.has("moves_left"):
		return int(st["moves_left"]) <= 0
	return false

## Bersagli d'attacco validi da `from` (nemici o neutrali confinanti, collegamenti marittimi con porto).
func attack_targets(from: int) -> Array:
	if from < 0 or int(game.terr[from]["owner"]) != h():
		return []
	if game.has_method("attack_targets"):
		var r = tcall("attack_targets", [from], [])
		return _norm_targets(r)
	var out := []
	for tg in gcall("valid_targets", [h(), from], []):
		var j := int(tg["idx"])
		var o := int(game.terr[j]["owner"])
		if o == h() or bool(tg.get("airlift", false)):
			continue
		if o >= 0 and pact_between(h(), o) != null:
			continue
		if o >= 0 and truce_turns() > 0:
			continue
		out.append({"idx": j, "sea": bool(tg.get("sea", false)), "airlift": false})
	return out

## Territori propri raggiungibili da `from` passando solo per territori propri.
func move_targets(from: int) -> Array:
	if from < 0 or int(game.terr[from]["owner"]) != h():
		return []
	if game.has_method("move_targets"):
		return _norm_targets(tcall("move_targets", [from], []))
	var seen := {from: true}
	var q := [from]
	var out := []
	while not q.is_empty():
		var a: int = q.pop_front()
		for j in Data.TERRITORIES[a]["adj"]:
			j = int(j)
			if seen.has(j) or int(game.terr[j]["owner"]) != h():
				continue
			seen[j] = true
			q.append(j)
			out.append({"idx": j, "sea": false, "airlift": false})
	return out

func _norm_targets(r) -> Array:
	var out := []
	if not (r is Array):
		return out
	for x in r:
		if x is Dictionary:
			out.append({"idx": int(x.get("idx", -1)), "sea": bool(x.get("sea", false)), "airlift": bool(x.get("airlift", false))})
		else:
			out.append({"idx": int(x), "sea": false, "airlift": false})
	return out

## Unità che possono lasciare `from` (ne resta almeno 1).
func movable_forces(from: int) -> Dictionary:
	var f: Dictionary = game.terr[from]["forces"]
	var o := Data.clone_forces(f)
	var tot := Data.total_units(f)
	if tot <= 1:
		return Data.empty_forces()
	# lascio indietro un'unità del tipo più debole (preferibilmente fanteria)
	for k in ["inf", "aa", "art", "drone", "tank", "heli", "jet"]:
		if int(o.get(k, 0)) > 0:
			o[k] = int(o[k]) - 1
			break
	return o

## Apre il pannello forze (attacco o spostamento) da `from` verso `to`.
func open_force_panel(kind: String, from: int, to: int) -> void:
	if from < 0 or to < 0:
		return
	var tot := Data.total_units(game.terr[from]["forces"])
	if tot <= 1:
		toast("Servono almeno 2 unità: una deve restare a presidio", "bad")
		return
	_force_ctx = {"kind": kind, "from": from, "to": to}
	_force_sel = movable_forces(from)
	Sfx.play("select")
	show_modal(kind, modal.build_force_panel(kind, from, to), true)

func force_ctx():
	return _force_ctx

## Il pannello aggiorna le forze scelte dai cursori.
func set_force(k: String, n: int) -> void:
	_force_sel[k] = maxi(0, n)

## Esegue l'attacco scelto nel pannello: manual = comando diretto 3D.
func do_attack(manual: bool) -> void:
	if _force_ctx == null or game == null:
		return
	var from := int(_force_ctx["from"])
	var to := int(_force_ctx["to"])
	var forces := _force_sel.duplicate()
	close_modal(true)
	_force_ctx = null
	if Data.total_units(forces) <= 0:
		toast("Scegli almeno un'unità da inviare", "bad")
		return
	var prev_owner := int(game.terr[to]["owner"])
	var r = tcall("attack", [from, to, forces], {"ok": false, "reason": "Attacco non disponibile"})
	if not (r is Dictionary) or not r.get("ok", false):
		toast(String(r.get("reason", "Attacco non valido")) if r is Dictionary else "Attacco non valido", "bad")
		refresh(true)
		return
	Sfx.play("order")
	if map != null and map.has_method("turn_arrow"):
		map.turn_arrow(from, to, h(), "attack", 0.9)
	if game.pending_battle != null:
		var pb = game.pending_battle
		battle_info = {"attacker": h(), "defender": prev_owner, "terr": int(pb.get("terr", to))}
		if manual and can_manual_battle():
			modal_kind = ""
			battle_manual()
		else:
			battle_auto()
	else:
		# il nucleo ha già risolto lo scontro
		battle_info = {"attacker": h(), "defender": prev_owner, "terr": to}
		_battle_outcome_toast(battle_info)
	refresh(true)

func do_move() -> void:
	if _force_ctx == null or game == null:
		return
	var from := int(_force_ctx["from"])
	var to := int(_force_ctx["to"])
	var forces := _force_sel.duplicate()
	close_modal(true)
	_force_ctx = null
	if Data.total_units(forces) <= 0:
		toast("Scegli almeno un'unità da spostare", "bad")
		return
	var r = tcall("move", [from, to, forces], {"ok": false, "reason": "Spostamento non disponibile"})
	if r is Dictionary and r.get("ok", false):
		Sfx.play("order")
		if map != null and map.has_method("turn_arrow"):
			map.turn_arrow(from, to, h(), "move", 0.8)
		feedback("Spostate %d unità: %s → %s" % [Data.total_units(forces), _tn(from), _tn(to)])
		select(to)
	else:
		toast(String(r.get("reason", "Spostamento non valido")) if r is Dictionary else "Spostamento non valido", "bad")
	refresh(true)

func do_fortify(kind: String) -> void:
	if not sel_own():
		return
	if not can_supply():
		toast(supply_block(), "bad")
		return
	var r = tcall("fortify", [sel, kind], {"ok": false, "reason": "Fortificazioni non disponibili"})
	if r is Dictionary and r.get("ok", false):
		Sfx.play("build")
	result(r, "%s rafforzate in %s" % [fort_name(kind), _tn(sel)])

const FORT_KINDS := ["trench", "mines", "bunker"]
const FORT_INFO := {
	"trench": {"name": "Trincee", "desc": "La fanteria in difesa si ripara: meno perdite dal fuoco diretto"},
	"mines": {"name": "Campi minati", "desc": "I mezzi attaccanti subiscono danni entrando nel territorio"},
	"bunker": {"name": "Bunker", "desc": "Postazioni fisse armate che sparano sugli attaccanti"},
}

static func fort_name(kind: String) -> String:
	if "FORT" in Data and Data.FORT is Dictionary and Data.FORT.has(kind):
		return String(Data.FORT[kind].get("name", kind))
	return String(FORT_INFO.get(kind, {}).get("name", kind))

## Livelli di fortificazione di un territorio {trench, mines, bunker} (0..3).
func fort_levels(t: int) -> Dictionary:
	var out := {"trench": 0, "mines": 0, "bunker": 0}
	if game == null or t < 0:
		return out
	var tr: Dictionary = game.terr[t]
	var f = tr.get("fort", tr.get("forts", null))
	if f is Dictionary:
		for k in FORT_KINDS:
			out[k] = clampi(int(f.get(k, 0)), 0, 3)
	return out

## Costo del prossimo livello di fortificazione (null = massimo o non disponibile).
func fort_cost(t: int, kind: String):
	if game == null:
		return null
	for m in ["fort_cost", "fortify_cost"]:
		if game.has_method(m):
			return tcall(m, [t, kind], null)
	var lv := int(fort_levels(t)[kind])
	if lv >= 3:
		return null
	if "FORT" in Data and Data.FORT is Dictionary and Data.FORT.has(kind):
		var F: Dictionary = Data.FORT[kind]
		var c = F.get("cost", null)
		if c is Array:
			return c[mini(lv, c.size() - 1)]
		if c is Dictionary:
			var o := {}
			for r in c:
				o[r] = int(round(float(c[r]) * (lv + 1)))
			return o
	return null

func can_fortify(t: int, kind: String) -> Dictionary:
	if game != null and game.has_method("can_fortify"):
		var r = tcall("can_fortify", [t, kind], null)
		if r is Dictionary:
			return r
	if not can_supply():
		return {"ok": false, "reason": supply_block()}
	if int(fort_levels(t)[kind]) >= 3:
		return {"ok": false, "reason": "Livello massimo"}
	var c = fort_cost(t, kind)
	if c == null:
		return {"ok": game != null and game.has_method("fortify"), "reason": "" if game != null and game.has_method("fortify") else "Non disponibile"}
	if not gcall("can_afford", [h(), c], false):
		return {"ok": false, "reason": "Risorse insufficienti"}
	return {"ok": true, "reason": ""}

## ================================================================== riquadro ORDINI (cosa fare adesso)
const PHASE_COL := {"supply": Color("#7fe08f"), "attack": Color("#ff8a6a"), "move": Color("#8ad6ff")}
const MARK_ATTACK := Color(1.0, 0.72, 0.25, 0.95)
const MARK_MOVE := Color(0.45, 0.80, 1.0, 0.95)
var _deploy_off := false        # il giocatore ha annullato lo schieramento automatico in questo turno
var _pool_warn_t := -100.0      # «Fase successiva» con rinforzi non schierati: secondo clic per confermare
var _click_cache := ""
var _click_list: Array = []

func _phase_label(ph: String) -> String:
	var n := {"supply": 1, "attack": 2, "move": 3}
	return "TURNO %d  ·  FASE %d DI 3  ·  %s" % [round_n(), int(n.get(ph, 1)), String(PHASE_NAMES.get(ph, "")).to_upper()]

func _pool_n() -> int:
	return Data.total_units(game.players[h()]["pool"]) if game != null and h() >= 0 else 0

## Stato del riquadro ORDINI: {phase, col, text (bbcode), sub, main: {text, act, tip, kind}, alt}.
func guide_state() -> Dictionary:
	if game == null or h() < 0:
		return {}
	var st := {"phase": "", "col": UIKit.AMBER, "text": "", "sub": "", "main": null, "alt": null}
	if game.over != null:
		st["text"] = "La partita è finita."
		return st
	if not human_alive():
		st["text"] = "Sei stato eliminato: puoi continuare a guardare la partita."
		return st
	if not my_turn():
		var cp := cur_player()
		var P = game.players[cp] if cp >= 0 and cp < game.players.size() else null
		st["phase"] = "TURNO %d  ·  TOCCA ALL'AVVERSARIO" % round_n()
		st["col"] = (P["color"] as Color) if P != null else UIKit.DIM
		st["text"] = "[b]Turno %s[/b]: guarda attacchi e spostamenti sul tabellone." % (hud._di(String(P["name"])) if P != null else "dell'IA")
		st["sub"] = "Se ti attaccano potrai difenderti in 3D o con la risoluzione automatica."
		st["main"] = {"text": "Salta animazioni  »»" if _ai_fast else "Accelera  »", "act": "ai-fast", "kind": "normal",
			"tip": "Spazio: la prima volta accelera, la seconda salta le animazioni del turno IA"}
		return st
	var ph := phase_key()
	var pool := _pool_n()
	st["phase"] = _phase_label(ph)
	st["col"] = PHASE_COL.get(ph, UIKit.AMBER)
	var end_alt := {"text": "Fine turno  ⏎", "act": "end-turn", "tip": "Termina subito il turno (Invio): salta le fasi rimaste e giocano le IA"}
	if mode != null and mode["type"] == "card":
		var op: Dictionary = Data.OPS[mode["op"]]
		st["text"] = ("[b]%s[/b]: clicca un tuo territorio [color=#ff8a6a]evidenziato[/color]." if String(op.get("target", "")) == "self" else "[b]%s[/b]: clicca un territorio nemico [color=#ff8a6a]evidenziato in rosso[/color].") % op["name"]
		st["sub"] = String(op.get("desc", ""))
		st["main"] = {"text": "Annulla", "act": "cancel-mode", "kind": "normal", "tip": "Annulla la carta (Esc)"}
		return st
	match ph:
		"supply":
			var nxt := {"text": "Fase successiva: Attacco  ›", "act": "end-phase", "tip": "Passa alla fase 2 · Attacco"}
			if pool > 0 and mode != null and mode["type"] == "deploy":
				st["text"] = "Hai [b][color=#ffd57a]%d rinforzi[/color][/b]: clicca un tuo territorio [color=#7fe08f]evidenziato in verde[/color] per schierarli." % pool
				st["sub"] = "Sono fanteria: mettili dove confini con i nemici o da dove vuoi attaccare. Esc = prima guarda il tabellone."
				nxt["kind"] = "normal"
				st["main"] = nxt
				st["alt"] = {"text": "Annulla schieramento", "act": "cancel-mode", "tip": "Esci dallo schieramento per esplorare il tabellone (Esc)"}
			elif pool > 0:
				st["text"] = "Hai ancora [b][color=#ffd57a]%d rinforzi[/color][/b] da schierare." % pool
				st["sub"] = "Premi «Schiera» e clicca un tuo territorio, oppure «Schiera qui» nel pannello del territorio."
				st["main"] = {"text": "Schiera %d rinforzi" % pool, "act": "deploy", "tip": "Scegli dove schierare i rinforzi (N)"}
				st["alt"] = {"text": "Fase successiva: Attacco  ›", "act": "end-phase", "tip": "I rinforzi non schierati restano per il prossimo turno"}
			else:
				st["text"] = "Puoi [b]reclutare[/b], [b]costruire[/b] o [b]fortificare[/b]: clicca un tuo territorio e usa le schede del pannello a destra."
				st["sub"] = "Per attaccare servono carri e artiglieria: si reclutano nel QG o dove hai una Fabbrica. Poi passa all'attacco."
				st["main"] = nxt
				st["alt"] = end_alt
			if Time.get_ticks_msec() / 1000.0 - _pool_warn_t < 6.0 and pool > 0:
				st["text"] = "[color=#ffb59a]Hai ancora %d rinforzi non schierati.[/color] Premi di nuovo per passare all'attacco senza schierarli (restano per il prossimo turno)." % pool
				st["main"] = {"text": "Sì, passa all'attacco  ›", "act": "end-phase", "kind": "danger", "tip": "I rinforzi restano in attesa"}
		"attack":
			var skip := {"text": "Salta attacco  ›", "act": "end-phase", "kind": "normal", "tip": "Nessun attacco in questo turno: passa allo spostamento"}
			if attacked_any():   # più attacchi nel turno (tregua, bel tempo): il secondo è facoltativo
				skip = {"text": "Basta attacchi: Spostamento  ›", "act": "end-phase", "kind": "normal", "tip": "Rinuncia agli attacchi rimasti e passa alla fase 3 · Spostamento"}
			if attack_used() or move_used():
				st["text"] = "Attacco del turno eseguito. Ora puoi [b]spostare[/b] truppe tra i tuoi territori."
				st["main"] = {"text": "Fase successiva: Spostamento  ›", "act": "end-phase", "tip": "Passa alla fase 3 · Spostamento"}
				st["alt"] = end_alt
			elif sel_own() and not targets.is_empty():
				st["text"] = "Clicca un bersaglio [color=#ff8a6a]evidenziato in rosso[/color] (%d possibil%s): si apre il pannello d'attacco." % [targets.size(), "e" if targets.size() == 1 else "i"]
				st["sub"] = _attacks_note() + " Nel pannello scegli quante unità inviare e vedi la previsione."
				st["main"] = skip
				st["alt"] = end_alt
			else:
				var n := click_marks().size()
				if n > 0:
					st["text"] = "Scegli un tuo territorio con almeno 2 unità ([color=#ffc060]pulsano in ambra[/color]), poi un nemico confinante [color=#ff8a6a]in rosso[/color]."
					st["sub"] = ("Da qui non puoi attaccare: scegline un altro. " if sel_own() else "") + "Oppure salta l'attacco." + (" Tregua: solo territori neutrali." if truce_turns() > 0 else "")
					if attacks_max() > 1:
						st["sub"] = _attacks_note() + " " + String(st["sub"])
				else:
					st["text"] = "Nessun attacco possibile in questo turno."
					st["sub"] = "Ti servono almeno 2 unità vicino a un nemico o neutrale."
				st["main"] = skip
				st["alt"] = end_alt
		"move":
			var fin := {"text": "Fine turno  ✓", "act": "end-turn", "tip": "Termina il turno (Invio): giocano le IA"}
			st["main"] = fin
			if move_used():
				st["text"] = "Spostamento eseguito. Premi [b]Fine turno[/b]: giocheranno le IA."
			elif sel_own() and not targets.is_empty():
				st["text"] = "Clicca un tuo territorio [color=#8ad6ff]evidenziato in azzurro[/color] per spostarci le truppe."
				st["sub"] = "Facoltativo: uno spostamento per turno, almeno 1 unità resta."
			elif sel_own() and int(game.terr[sel].get("regroup", 0)) > 0:
				st["text"] = "Queste truppe hanno appena conquistato: non possono ripartire. Scegli un altro territorio o termina il turno."
			else:
				st["text"] = "Facoltativo: clicca un tuo territorio ([color=#8ad6ff]pulsano in azzurro[/color]), poi un tuo territorio collegato per spostare truppe."
				st["sub"] = "Altrimenti premi Fine turno."
	st["goal"] = goal_text()
	return st

func _attacks_note() -> String:
	var am := attacks_max()
	if am <= 1:
		return "Un solo attacco per turno."
	return "Attacchi rimasti in questo turno: %d su %d%s." % [attacks_left(), am, " (tregua iniziale: due attacchi, solo contro i neutrali)" if truce_turns() > 0 else ""]

## Riga degli obiettivi a breve termine nel riquadro ORDINI: ordine del comando ed evento mondiale in corso.
func goal_text() -> String:
	if game == null or h() < 0:
		return ""
	var parts := []
	if game.has_method("mission_text"):
		var mt := String(game.mission_text(h()))
		if mt != "":
			parts.append("[color=#ffd57a]★ ORDINE DEL COMANDO[/color]  " + mt)
	if game.has_method("world_event_text"):
		var wt := String(game.world_event_text())
		if wt != "":
			parts.append("[color=#8ad6ff]◆ EVENTO[/color]  " + wt)
	return "\n".join(parts)

# ================================================================== rapporto del round (notte 3)
## Cosa è successo mentre giocavano le IA: raccolto dai segnali, mostrato all'inizio del turno del giocatore
## (prima le minacce annunciate, poi ciò che lo riguarda, poi il resto). Un clic su una riga inquadra il territorio.
var _recap: Array = []        # {text, kind: "threat"|"bad"|"good"|"news"|"info", terr, w}
var _last_cap := {}

func _recap_add(text: String, kind: String, terr: int, w: int) -> void:
	if game == null or not turn_mode() or h() < 0 or my_turn():
		return
	_recap.append({"text": text, "kind": kind, "terr": terr, "w": w})

func _sh(i: int) -> String:
	return String(game.players[i]["fac"]["short"]) if i >= 0 and i < game.players.size() else "Neutrali"

func recap_lines() -> Array:
	var lines := []
	if game != null and game.has_method("threats_for") and human_alive():
		for th in game.threats_for(h()):
			lines.append({"text": "%s ammassa %d unità in %s contro %s (%d in difesa)" % [_sh(int(th["player"])), int(th["att"]), _tn(th["from"]), _tn(th["to"]), int(th["def"])],
				"kind": "threat", "terr": int(th["to"]), "w": 5})
	var rest := _recap.duplicate()
	rest.sort_custom(func(a, b): return int(a["w"]) > int(b["w"]))
	lines.append_array(rest)
	return lines

var _recap_key := ""

func _show_recap() -> void:
	var rk := "%d|%d" % [h(), round_n()]
	if rk == _recap_key:
		return   # già mostrato per questo turno
	_recap_key = rk
	var lines := recap_lines()
	_recap = []
	if round_n() <= 1 or not hud.has_method("show_recap"):
		return
	var keep := lines.slice(0, 6)
	hud.show_recap(keep, lines.size() - keep.size())
	# le minacce lampeggiano sul tabellone come frecce
	if map != null and map.has_method("turn_arrow") and not map.has_method("set_threats") and game.has_method("threats_for"):
		for th in game.threats_for(h()):
			map.turn_arrow(int(th["from"]), int(th["to"]), int(th["player"]), "attack", 2.6)

func focus_terr(t: int) -> void:
	if t < 0 or game == null:
		return
	select(t)
	if map != null and map.has_method("focus"):
		map.focus(t)

## Territori del giocatore da cui si può agire ADESSO (pulsano sul tabellone quando non c'è selezione utile).
func click_marks() -> Array:
	if game == null or not turn_mode() or not my_turn() or mode != null:
		return []
	var ph := phase_key()
	if not (ph == "attack" and not attack_used() and not move_used()) and not (ph == "move" and not move_used()):
		return []
	var mine: Array = gcall("territories_of", [h()], [])
	var key := "%d|%s|%s|%s" % [round_n(), ph, str(attack_used()), str(move_used())]
	for t in mine:
		key += ",%d:%d" % [int(t), Data.total_units(game.terr[int(t)]["forces"])]
	if key == _click_cache:
		return _click_list
	_click_cache = key
	_click_list = []
	for t in mine:
		var ti := int(t)
		if Data.total_units(game.terr[ti]["forces"]) < 2:
			continue
		if ph == "attack":
			if not attack_targets(ti).is_empty():
				_click_list.append(ti)
		elif int(game.terr[ti].get("regroup", 0)) <= 0 and not move_targets(ti).is_empty():
			_click_list.append(ti)
	return _click_list

## Esito di un'azione nel riquadro ORDINI.
func feedback(text: String, kind: String = "good") -> void:
	if hud != null and hud.has_method("feedback"):
		hud.feedback(text, kind)

## Il tutorial guidato parte da solo alla prima campagna (non nei test e negli screenshot).
func _auto_tutorial_ok() -> bool:
	if OS.get_cmdline_args().has("--script") or Shot.has_arg("shot") or Shot.has_arg("quit-after"):
		return Shot.has_arg("tutorial")
	return not bool(Settings.get_value("tutorial_done", false))

## Menu «Tutorial»: nuova campagna con impostazioni semplici e il primo turno guidato.
func start_tutorial() -> void:
	menu_opts["opp"] = 3
	menu_opts["mode"] = "conquista"
	menu_opts["fog"] = true
	if Data.DIFFICULTY.has("recluta"):
		menu_opts["diff"] = "recluta"
	_force_tutorial = true
	start_game(false)

var _force_tutorial := false

## Suggerimento sotto la barra dei turni (compatibilità: ora il testo è nel riquadro ORDINI).
func turn_hint() -> String:
	if not my_turn() or game == null:
		return ""
	if mode != null and mode["type"] == "deploy":
		return "Clic su un tuo territorio per schierare i rinforzi"
	var ph := phase_key()
	var pool := Data.total_units(game.players[h()]["pool"])
	match ph:
		"supply":
			if pool > 0:
				return "Rinforzi da schierare: %d · Schiera (N) e clic su un tuo territorio · recluta, costruisci, fortifica" % pool
			return "Recluta, costruisci, fortifica, commercia · poi seleziona un tuo territorio e un bersaglio per attaccare"
		"attack":
			if attack_used():
				return "Attacco del turno già eseguito · Fine fase per lo spostamento"
			if sel_own() and not targets.is_empty():
				return "Clic su un bersaglio evidenziato per preparare l'attacco (%d possibili)" % targets.size()
			if sel_own():
				return "Nessun bersaglio attaccabile da qui: scegli un altro territorio con almeno 2 unità"
			return "Seleziona un tuo territorio con almeno 2 unità, poi un nemico confinante"
		"move":
			if move_used():
				return "Spostamento eseguito · Invio per terminare il turno"
			if sel_own() and not targets.is_empty():
				return "Clic su un tuo territorio evidenziato per spostare le truppe"
			return "Seleziona un tuo territorio da cui spostare truppe verso un altro collegato"
	return ""

func end_phase() -> void:
	if not turn_mode() or not my_turn() or modal_kind != "":
		return
	var before := phase_key()
	var now := Time.get_ticks_msec() / 1000.0
	if before == "supply" and _pool_n() > 0 and now - _pool_warn_t > 6.0:
		# primo clic con rinforzi non schierati: chiedo conferma nel riquadro ORDINI
		_pool_warn_t = now
		Sfx.play("alert")
		refresh(true)
		return
	_pool_warn_t = -100.0
	_deploy_off = true
	set_mode(null)
	tcall("end_phase")
	Sfx.play("click")
	if my_turn() and phase_key() != before and phase_key() != "":
		var am := attacks_max()
		var msg := {"attack": "Fase 2 · Attacco: un attacco facoltativo" if am <= 1 else "Fase 2 · Attacco: fino a %d attacchi in questo turno" % am,
			"move": "Fase 3 · Spostamento: uno spostamento facoltativo"}
		feedback(String(msg.get(phase_key(), "")), "info")
	refresh(true)

func end_turn() -> void:
	if not turn_mode() or not my_turn() or modal_kind != "":
		return
	set_mode(null)
	_ai_fast = false
	_pool_warn_t = -100.0
	_recap = []
	if hud.has_method("hide_recap"):
		hud.hide_recap()
	tcall("end_turn")
	Sfx.play("order")
	refresh(true)

## Pulsante del riquadro ORDINI durante il turno IA (come Spazio).
func ai_fast() -> void:
	if game == null or my_turn() or game.over != null:
		return
	if _ai_fast and game.has_method("skip_ai_turn"):
		game.skip_ai_turn()
		if map != null and map.has_method("clear_turn_anims"):
			map.clear_turn_anims()
	_ai_fast = true
	refresh(true)

## Passo del ciclo durante i turni: accelera le animazioni dell'IA se richiesto e aggiorna il ritardo.
func _ai_dt(dt: float) -> float:
	if not turn_mode() or my_turn():
		return dt
	return dt * (6.0 if _ai_fast else 1.0)

## Applica l'impostazione «Velocità turni IA» alla partita in corso.
func _apply_ai_delay() -> void:
	if game == null:
		return
	var dly: float = Settings.ai_step_delay() if Settings.has_method("ai_step_delay") else 0.9
	if "opts" in game and game.opts is Dictionary:
		game.opts["ai_step_delay"] = dly
	if "ai_step_delay" in game:
		game.ai_step_delay = dly

func _on_setting(key: String) -> void:
	if key == "ai_speed":
		_apply_ai_delay()

## Inizio di un turno (segnale turn_start o cambio rilevato): banner, autosalvataggio, selezione.
func _on_turn_start(p: int) -> void:
	if game == null:
		return
	var key := "%d|%d" % [p, round_n()]
	if key == _turn_seen:
		return
	_turn_seen = key
	if p == h() and h() >= 0:
		_ai_fast = false
		_deploy_off = false
		_pool_warn_t = -100.0
		_tension_until = 0.0   # torna la musica del tabellone all'inizio del turno del giocatore
		hud.turn_banner(p, true)
		_turn_report()
		_show_recap()
		Sfx.play("research")
		if is_inside_tree():
			get_tree().create_timer(2.4).timeout.connect(_flush_news)
		_autosave_turn = round_n()
		call_deferred("_turn_autosave")
	elif p >= 0 and p < game.players.size():
		hud.turn_banner(p, false)
		if sel >= 0 and not sel_own():
			pass
	refresh(true)

## Riepilogo d'inizio turno del giocatore: entrate, rinforzi, edifici e unità completati, ricerca, territori persi.
var _rep := {}

func _rep_add(k: String, text: String) -> void:
	if not _rep.has(k):
		_rep[k] = []
	(_rep[k] as Array).append(text)

func turn_report_text() -> String:
	if game == null or h() < 0:
		return ""
	var P: Dictionary = game.players[h()]
	var parts := []
	var inc := []
	var rates: Dictionary = P.get("rates", {})
	for k in ["money", "oil", "steel", "manpower"]:
		var v := int(round(float(rates.get(k, 0.0))))
		if v != 0 and (k == "money" or absf(float(rates.get(k, 0.0))) >= 1.0):
			inc.append("%s%d %s" % ["+" if v > 0 else "", v, Data.RES_ICONS.get(k, k)])
	if inc.size():
		parts.append(" ".join(inc))
	var pool := Data.total_units(P["pool"])
	if pool > 0:
		parts.append("%d rinforzi (fanteria) da schierare" % pool)
	for b in _rep.get("built", []):
		parts.append(String(b))
	var units: Dictionary = _rep.get("units", {})
	for tn in units:
		var u: Dictionary = units[tn]
		var lst := []
		for k in Data.UNIT_KEYS:
			if int(u.get(k, 0)) > 0:
				lst.append("%d %s" % [int(u[k]), Data.UNITS[k]["short"]])
		parts.append("pronte a %s: %s" % [tn, ", ".join(lst)])
	for r in _rep.get("research", []):
		parts.append(String(r))
	var lost: Array = _rep.get("lost", [])
	if lost.size():
		parts.append("perduto: " + ", ".join(lost))
	if parts.is_empty():
		return ""
	return "Questo turno: " + " · ".join(parts)

func _turn_report() -> void:
	var tx := turn_report_text()
	_rep = {}
	if tx == "" or round_n() <= 1:
		return
	if hud != null and hud.has_method("feedback"):
		hud.feedback(tx, "info", 16.0)

## Notizie sulle altre potenze: in tempo reale subito come toast; a turni raccolte durante i turni IA e riassunte
## in pochi toast all'inizio del turno del giocatore (il dettaglio resta nel registro).
var _news_q: Array = []

func _news(kind: String, text: String, extra: Dictionary = {}) -> void:
	if not turn_mode() or my_turn():
		toast(text, "info")
		return
	var e := extra.duplicate()
	e["kind"] = kind
	e["text"] = text
	_news_q.append(e)

func _flush_news() -> void:
	if game == null or _news_q.is_empty():
		return
	var tech := {}   # livello -> [sigle]
	var lines := []
	for e in _news_q:
		if e["kind"] == "tech":
			var lv := int(e["lv"])
			if not tech.has(lv):
				tech[lv] = []
			if not (tech[lv] as Array).has(e["who"]):
				tech[lv].append(e["who"])
		else:
			lines.append(String(e["text"]))
	_news_q = []
	for lv in tech:
		var w: Array = tech[lv]
		lines.push_front(("%s raggiunge Tech %d" % [w[0], lv]) if w.size() == 1 else ("%s raggiungono Tech %d" % [", ".join(w), lv]))
	# una sola notizia a comparsa: il resto è nel Registro (badge sulla barra a sinistra)
	if not lines.is_empty():
		toast(String(lines[0]) + ((" · altre %d nel Registro" % (lines.size() - 1)) if lines.size() > 1 else ""), "info")

func _turn_autosave() -> void:
	if game == null or float(Settings.get_value("autosave")) <= 0 or game.over != null or battle != null:
		return
	if round_n() <= 1 or not save_available():
		return
	if modal_kind != "" and modal_kind != "summary":
		return
	_grab_thumb()
	if save_to_slot("auto", "Automatico · " + default_save_name(), true):
		hud.saved_hint("Salvataggio automatico · turno %d" % round_n())

## Mossa o attacco (segnali "move"/"attack"): freccia animata e telecamera che segue l'IA.
func _on_turn_action(kind: String, d: Dictionary) -> void:
	var p := int(d.get("player", d.get("attacker", d.get("by", -1))))
	var from := int(d.get("from", -1))
	var to := int(d.get("to", d.get("terr", -1)))
	if from < 0 or to < 0 or p == h() and h() >= 0:
		return
	if map != null and map.has_method("turn_arrow"):
		var vis := is_vis(from) or is_vis(to)
		if vis:
			map.turn_arrow(from, to, p, kind, maxf(0.5, Settings.ai_step_delay() * (0.4 if _ai_fast else 1.0)))
	if bool(Settings.get_value("ai_follow")) and map != null and map.has_method("focus") and (is_vis(to) or h() < 0):
		if not _ai_fast or kind == "attack":
			map.focus(to)

# ================================================================== selezione e modalità
func select(t: int) -> void:
	sel = t
	if t >= 0:
		Sfx.play("select")
	refresh(true)

func set_mode(m) -> void:
	mode = m
	hud.set_mode_banner(m)
	_apply_cursor("" if m == null else ("target" if m["type"] == "card" else "deploy"))
	if game != null:
		refresh(true)

func send_to(to: int) -> void:
	if not sel_own():
		return
	var r = gcall("send_division", [h(), sel, to, quota], {"ok": false, "reason": "Comando non disponibile"})
	if r["ok"]:
		Sfx.play("order")
		if String(r.get("reason", "")) != "":
			toast(r["reason"], "info")
	else:
		toast(r.get("reason", "Ordine non valido") if String(r.get("reason", "")) != "" else "Ordine non valido", "bad")
	refresh(true)

func result(r, ok_msg: String = "") -> void:
	if r == null:
		return
	var reason := String(r.get("reason", ""))
	if r.get("ok", false):
		# a turni l'esito va nel riquadro ORDINI (niente toast in più)
		if turn_mode() and h() >= 0:
			if ok_msg != "" or reason != "":
				feedback(ok_msg if ok_msg != "" else reason, "good")
		elif reason != "":
			toast(reason, "info")
		elif ok_msg != "":
			toast(ok_msg, "good")
	else:
		toast(reason if reason != "" else "Impossibile", "bad")
	refresh(true)

func toast(text: String, type: String = "info") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_recent_toasts.append({"text": text, "t": now})
	toasts.push(text, type)

func toasted_recently(text: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var keep := []
	var found := false
	for r in _recent_toasts:
		if now - float(r["t"]) < 3.0:
			keep.append(r)
			if r["text"] == text:
				found = true
	_recent_toasts = keep
	return found

# ================================================================== azioni (dai pulsanti)
const SUPPLY_ACTS := ["research", "build", "recruit", "trade", "mercs", "deploy-here", "deploy", "op", "fortify"]

func act(a: String, ds: Dictionary = {}) -> void:
	var o := menu_opts
	if game != null and turn_mode() and a in SUPPLY_ACTS and not can_supply():
		if a == "deploy" and mode != null:
			set_mode(null)
		else:
			toast(supply_block(), "bad")
		return
	match a:
		"end-phase": end_phase()
		"end-turn": end_turn()
		"focus-terr": focus_terr(int(ds.get("t", -1)))
		"recap-close":
			if hud.has_method("hide_recap"):
				hud.hide_recap()
		"ai-fast": ai_fast()
		"tutorial": start_tutorial()
		"fortify": do_fortify(String(ds.get("k", "")))
		"atk-auto": do_attack(false)
		"atk-manual": do_attack(true)
		"mv-go": do_move()
		"force-cancel":
			_force_ctx = null
			close_modal(true)
		"m-fac": o["faction"] = int(ds["v"]); menu.refresh()
		"m-opp": o["opp"] = int(ds["v"]); menu.refresh()
		"m-diff": o["diff"] = ds["v"]; menu.refresh()
		"m-mode": o["mode"] = ds["v"]; menu.refresh()
		"m-dist": o["dist"] = ds["v"]; menu.refresh()
		"m-ask": o["ask_defense"] = not o["ask_defense"]; menu.refresh()
		"m-auto": o["auto_battles"] = not o["auto_battles"]; menu.refresh()
		"m-fog":
			o["fog_mode"] = String(ds.get("v", "none"))
			o["fog"] = o["fog_mode"] != "none"
			menu.refresh()
		"pact": propose_pact(int(ds["p"]))
		"pact-yes": answer_pact_offer(true)
		"pact-no": answer_pact_offer(false)
		"start": start_game(false)
		"scn-start": start_scenario(String(ds["id"]), int(ds.get("faction", -1)))
		"spectate": start_game(true)
		"continue": continue_latest()
		"exit": get_tree().quit()
		"save-menu": show_saves_modal("save")
		"load-menu": show_saves_modal("load")
		"settings":
			if game != null:
				show_settings_modal()
			else:
				menu.show_page("settings")
		"pause-back": _show_pause_content()
		"new-game": back_to_menu("new")
		"threat": focus_threat()
		"help": show_help()
		"speed":
			if game != null and not turn_mode():
				game.speed = float(ds["v"]); refresh(true)
		"pause": toggle_pause()
		"audio":
			Sfx.toggle_muted()
			AudioServer.set_bus_mute(0, Sfx.muted or float(Settings.get_value("vol_master")) <= 0.001)
			refresh(true)
		"menu": show_game_menu()
		"research":
			if game != null and h() >= 0:
				var r = gcall("research", [h()])
				if r != null and r.get("ok", false):
					Sfx.play("research")
				result(r, "Ricerca avviata")
		"build":
			if sel_own():
				var r = gcall("build", [h(), sel, ds["k"]])
				if r != null and r.get("ok", false):
					Sfx.play("build")
				result(r, "Costruzione avviata: " + Data.BUILDINGS[ds["k"]]["name"])
		"recruit":
			if sel_own():
				var r = gcall("recruit", [h(), sel, ds["u"], int(ds["n"])])
				if r != null and r.get("ok", false):
					Sfx.play("recruit")
				result(r)
		"quota": quota = float(ds["v"]); refresh(true)
		"trade":
			if game != null and h() >= 0:
				result(gcall("trade", [h(), ds["r"], ds["d"]]))
		"mercs":
			if sel_own():
				var r = gcall("hire_mercs", [h(), sel])
				if r != null and r.get("ok", false):
					Sfx.play("recruit")
				result(r)
		"deploy-here":
			if sel_own():
				var r = gcall("place_pool", [h(), sel])
				if r != null and r.get("ok", false):
					Sfx.play("order")
				result(r, "Rinforzi schierati in " + Data.TERRITORIES[sel]["name"])
				set_mode(null)
		"deploy":
			if game != null and h() >= 0:
				if mode != null and mode["type"] == "deploy":
					_deploy_off = true
					set_mode(null)
				else:
					_deploy_off = false
					set_mode({"type": "deploy"})
		"card":
			var i := int(ds["i"])
			var k := sel_cards.find(i)
			if k >= 0:
				sel_cards.remove_at(k)
			else:
				if sel_cards.size() >= 3:
					sel_cards.pop_front()
				sel_cards.append(i)
			if mode != null and mode["type"] == "card":
				set_mode(null)
			refresh(true)
		"autoset":
			if game != null and h() >= 0:
				var s = gcall("find_set", [h()])
				if s != null:
					sel_cards = Array(s).duplicate()
				refresh(true)
		"op": play_op(ds["op"])
		"cancel-mode":
			if mode != null and mode["type"] == "deploy":
				_deploy_off = true
			set_mode(null)
		"close-panel": select(-1)
		"bp-auto": battle_auto()
		"bp-manual": battle_manual()
		"modal-close", "resume": close_modal()
		"quit": back_to_menu()
		"watch": close_modal(true)
		"help-back": _help_back()

func play_op(op: String) -> void:
	if game == null or h() < 0:
		return
	var P: Dictionary = game.players[h()]
	var cards := []
	for i in sel_cards:
		if i < P["cards"].size():
			cards.append(P["cards"][i])
	if sel_cards.size() != 3 or not gcall("is_valid_set", [cards], false):
		toast("Seleziona un tris valido di carte", "bad")
		return
	if Data.OPS[op]["target"] == "enemy" or Data.OPS[op]["target"] == "self":
		set_mode({"type": "card", "op": op, "cards": sel_cards.duplicate()})
		return
	var r = gcall("play_cards", [h(), sel_cards.duplicate(), op, sel])
	if r != null and r.get("ok", false):
		Sfx.play("card")
		sel_cards = []
		_card_count = P["cards"].size()
	# i rinforzi da carte hanno già il loro messaggio nel registro del nucleo
	result(r, "" if Data.OPS[op].get("target", "") != "enemy" else Data.OPS[op]["name"] + ": carte giocate")

func toggle_pause() -> void:
	if game == null or game.over != null:
		return
	game.paused = not game.paused
	refresh(true)

# ================================================================== input del tabellone
func _input_blocked() -> bool:
	return game == null or battle != null or modal_kind != "" or _transition

func _on_map_clicked(t: int, button: int, _shift: bool) -> void:
	if _input_blocked():
		return
	if button == MOUSE_BUTTON_RIGHT:
		if mode != null:
			set_mode(null)
			return
		if t >= 0 and sel_own() and target_set.has(t):
			if turn_mode():
				_turn_target(t)
			else:
				send_to(t)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if mode != null and mode["type"] == "deploy":
		if t >= 0 and int(game.terr[t]["owner"]) == h():
			var r = gcall("place_pool", [h(), t])
			if r != null and r.get("ok", false):
				Sfx.play("order")
				set_mode(null)
				select(t)
			result(r, "Rinforzi schierati in " + Data.TERRITORIES[t]["name"])
		else:
			toast("Scegli un tuo territorio", "bad")
		return
	if mode != null and mode["type"] == "card":
		if t < 0:
			return
		var op_name: String = Data.OPS[mode["op"]]["name"]
		var r = gcall("play_cards", [h(), mode["cards"], mode["op"], t])
		if r != null and r.get("ok", false):
			Sfx.play("card")
			sel_cards = []
			_card_count = game.players[h()]["cards"].size()
			set_mode(null)
		result(r, op_name + ": " + Data.TERRITORIES[t]["name"])
		return
	if turn_mode() and t >= 0 and t != sel and sel_own() and target_set.has(t):
		_turn_target(t)
		return
	if t != sel:
		select(t)
	if t >= 0 and sel_own() and (not turn_mode() or not targets.is_empty()):
		drag = {"from": t, "pos0": _mouse(), "active": false}

## Clic su un bersaglio evidenziato durante il proprio turno: pannello attacco o spostamento.
func _turn_target(t: int) -> void:
	if not sel_own() or not target_set.has(t):
		return
	if int(game.terr[t]["owner"]) == h():
		open_force_panel("move", sel, t)
	else:
		open_force_panel("attack", sel, t)

func _on_map_hovered(t: int) -> void:
	if hover != t:
		hover = t
		hud.update_tip(true)

func _on_map_drag_released(from_idx: int, to_idx: int) -> void:
	if _input_blocked():
		return
	_clear_drag()
	if mode != null or from_idx < 0 or int(game.terr[from_idx]["owner"]) != h():
		return
	# il tabellone gestisce da sé il trascinamento: seleziono l'origine se non lo era
	if sel != from_idx:
		select(from_idx)
	if to_idx >= 0 and to_idx != from_idx and target_set.has(to_idx):
		if turn_mode():
			_turn_target(to_idx)
		else:
			send_to(to_idx)

func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()

func _update_drag() -> void:
	if drag == null:
		return
	if modal_kind != "":
		_clear_drag()
		return
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held:
		if not drag["active"] and _mouse().distance_to(drag["pos0"]) > 9:
			drag["active"] = true
		if drag["active"] and map != null and map.has_method("set_drag"):
			map.set_drag(drag["from"], _mouse_world())
	else:
		# rilascio senza segnale drag_released dal tabellone: usa il territorio sotto il cursore
		var d = drag
		_clear_drag()
		if d["active"] and hover >= 0 and hover != d["from"] and sel == d["from"] and target_set.has(hover):
			if turn_mode():
				_turn_target(hover)
			else:
				send_to(hover)

func _clear_drag() -> void:
	if drag != null and drag["active"] and map != null and map.has_method("clear_drag"):
		map.clear_drag()
	drag = null

func _mouse_world() -> Vector3:
	if hover >= 0 and target_set.has(hover) and map.has_method("map_to_world"):
		var T: Dictionary = Data.TERRITORIES[hover]
		return map.map_to_world(T["x"], T["y"])
	if map.has_method("screen_to_world"):
		return map.screen_to_world(_mouse())
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var o := cam.project_ray_origin(_mouse())
		var d := cam.project_ray_normal(_mouse())
		if absf(d.y) > 1e-4:
			var k := -o.y / d.y
			if k > 0:
				return o + d * k
	return Vector3.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if battle != null:
		return
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	if k == KEY_F1 or k == KEY_H:
		if modal_kind == "help":
			_help_back()
		else:
			show_help()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_ENTER and e.alt_pressed:
		Settings.set_value("fullscreen", not bool(Settings.get_value("fullscreen")))
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F5 and game != null and battle == null:
		quick_save()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F9:
		quick_load()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if modal_kind != "":
			if modal_closable:
				if modal_kind == "help":
					_help_back()
				elif modal_kind in ["settings", "saves"] and game != null:
					_show_pause_content()
				else:
					close_modal()
			return
		if game == null:
			menu.back()
			return
		if mode != null:
			if mode["type"] == "deploy":
				_deploy_off = true
			set_mode(null); return
		if drag != null:
			_clear_drag(); return
		if sel >= 0:
			select(-1)
		else:
			show_game_menu()
		return
	if game == null or modal_kind != "":
		return
	if turn_mode():
		match k:
			KEY_SPACE:
				get_viewport().set_input_as_handled()
				ai_fast()
			KEY_ENTER, KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				if my_turn():
					end_turn()
			KEY_N:
				act("deploy")
		return
	match k:
		KEY_SPACE:
			toggle_pause(); get_viewport().set_input_as_handled()
		KEY_1, KEY_KP_1:
			game.speed = 1.0; refresh(true)
		KEY_2, KEY_KP_2:
			game.speed = 2.0; refresh(true)
		KEY_3, KEY_KP_3:
			game.speed = 3.0; refresh(true)
		KEY_0, KEY_KP_0:
			game.speed = 0.5; refresh(true)
		KEY_N:
			act("deploy")

# ================================================================== segnali di gioco
func _tn(i) -> String:
	var j := int(i) if i != null else -1
	return Data.TERRITORIES[j]["name"] if j >= 0 and j < Data.TERRITORIES.size() else "?"

func _on_signal(name: String, d: Dictionary) -> void:
	if game == null:
		return
	var hh := h()
	match name:
		"capture":
			if int(d.get("by", -2)) == hh:
				Sfx.play("capture")
				if not turn_mode():
					toast("Conquistato: " + _tn(d.get("terr")), "good")   # a turni l'esito è nel riquadro ORDINI
			elif hh >= 0 and int(d.get("prev", -2)) == hh:
				Sfx.play("alert"); toast("Perduto: " + _tn(d.get("terr")), "bad")
				if turn_mode():
					_rep_add("lost", _tn(d.get("terr")))
			elif hh < 0:
				Sfx.play("capture")
			_last_cap = d
			if sel == int(d.get("terr", -1)):
				refresh(true)
		"battle":
			if hh < 0 or int(d.get("attacker", -2)) == hh or int(d.get("defender", -2)) == hh:
				Sfx.play("battle")
			var ba := int(d.get("attacker", -1))
			var bd := int(d.get("defender", -1))
			var bt := int(d.get("terr", -1))
			if hh >= 0 and ba != hh and ba >= 0 and bt >= 0:
				var won: bool = String(d.get("winner", "")) == "att"
				if bd == hh:
					_recap_add(("%s ti ha strappato %s" if won else "Hai respinto %s a %s") % [_sh(ba), _tn(bt)], "bad" if won else "good", bt, 4)
				elif won:
					_recap_add("%s conquista %s%s" % [_sh(ba), _tn(bt), (" (a %s)" % _sh(bd)) if bd >= 0 else ""], "info", bt, 2 if bd >= 0 else 1)
				elif bd >= 0:
					_recap_add("%s respinge %s a %s" % [_sh(bd), _sh(ba), _tn(bt)], "info", bt, 1)
		"built":
			if int(d.get("player", -2)) == hh:
				Sfx.play("build")
				var bk = d.get("key", "")
				var btxt: String = (Data.BUILDINGS[bk]["name"] if Data.BUILDINGS.has(bk) else "Edificio") + " completat" + ("o" if String(bk) in ["aeroporto", "porto", "impianto"] else "a") + " a " + _tn(d.get("terr"))
				if turn_mode():
					_rep_add("built", btxt)   # nel riepilogo d'inizio turno
				else:
					toast(btxt, "good")
		"recruited":
			if int(d.get("player", -2)) == hh and turn_mode():
				var tn := _tn(d.get("terr"))
				if not _rep.has("units"):
					_rep["units"] = {}
				if not _rep["units"].has(tn):
					_rep["units"][tn] = {}
				var uk := String(d.get("unit", "inf"))
				_rep["units"][tn][uk] = int(_rep["units"][tn].get(uk, 0)) + 1
		"researched":
			var lv := int(d.get("level", 1))
			if int(d.get("player", -2)) == hh:
				Sfx.play("research"); toast("Ricerca completata: " + UIKit.tech_name(lv) + " (vale in tutti i tuoi territori)", "good")
				if turn_mode():
					_rep_add("research", "ricerca completata: " + UIKit.tech_name(lv))
			elif hh >= 0:
				_news("tech", "%s raggiunge Tech %d" % [game.players[int(d["player"])]["fac"]["short"], lv], {"who": String(game.players[int(d["player"])]["fac"]["short"]), "lv": lv})
		"card":
			if int(d.get("player", -2)) == hh:
				Sfx.play("card")   # il registro del nucleo mostra già "Hai ottenuto una carta Comando"
		"missile":
			Sfx.play("missile")
			var t := int(d.get("terr", -1))
			if hh >= 0 and t >= 0 and int(game.terr[t]["owner"]) == hh and int(d.get("by", -2)) != hh:
				toast("Attacco missilistico su " + _tn(t) + "!", "bad")
				_recap_add("Missili di %s su %s" % [_sh(int(d.get("by", -1))), _tn(t)], "bad", t, 4)
			elif t >= 0 and int(d.get("by", -2)) != hh:
				_recap_add("Missili di %s su %s (%s)" % [_sh(int(d.get("by", -1))), _tn(t), _sh(int(game.terr[t]["owner"]))], "info", t, 1)
		"sabotage":
			var t := int(d.get("terr", -1))
			if hh >= 0 and t >= 0 and int(game.terr[t]["owner"]) == hh and int(d.get("by", -2)) != hh:
				Sfx.play("alert"); toast("Sabotaggio in " + _tn(t) + "!", "bad")
				_recap_add("Sabotaggio di %s in %s: produzione ferma" % [_sh(int(d.get("by", -1))), _tn(t)], "bad", t, 4)
		"golpe":
			if int(d.get("by", -2)) == hh:
				Sfx.play("capture")
			else:
				var gt := int(d.get("terr", -1))
				var mine: bool = int(_last_cap.get("terr", -2)) == gt and int(_last_cap.get("prev", -2)) == hh and hh >= 0
				_recap_add("Golpe di %s a %s%s" % [_sh(int(d.get("by", -1))), _tn(gt), ": territorio perduto" if mine else ""], "bad" if mine else "info", gt, 4 if mine else 2)
		"hqLost":
			if int(d.get("player", -2)) == hh:
				if (gcall("territories_of", [hh], []) as Array).is_empty():
					pass   # ultimo territorio: segue la schermata di sconfitta
				else:
					Sfx.play("alert"); toast("QG PERDUTO in " + _tn(d.get("terr")) + "! Il comando si sposta.", "bad")
			else:
				_news("hq", "QG %s catturato in %s" % [game.players[int(d["player"])]["fac"]["short"], _tn(d.get("terr"))])
		"reinforce":
			if int(d.get("player", -2)) == hh:
				Sfx.play("select")   # il toast arriva dal registro del nucleo ("Rinforzi disponibili: N fanteria...")
		"eliminated":
			if int(d.get("player", -2)) == hh:
				Sfx.play("defeat"); music("defeat"); _elim_pending = true
			else:
				toast(game.players[int(d["player"])]["name"] + " è stata eliminata", "info")
				_recap_add("%s è stata eliminata" % _sh(int(d["player"])), "news", -1, 3)
		"victory":
			if hh < 0 or int(d.get("winner", -2)) == hh:
				Sfx.play("victory")
				music("victory")
			else:
				Sfx.play("defeat")
				music("defeat")
		"pact_offer":
			if int(d.get("to", -2)) == hh and hh >= 0:
				_pact_offers.append(int(d.get("from", -1)))
		"pact":
			var a := int(d.get("a", -1))
			var b := int(d.get("b", -1))
			if hh >= 0 and (a == hh or b == hh):
				var other := b if a == hh else a
				if other >= 0:
					Sfx.play("research")
					toast("Patto di non aggressione con %s %s" % [game.players[other]["fac"]["short"], until_text(float(d.get("until", 0)))], "good")
			elif a >= 0 and b >= 0:
				_news("pact", "%s e %s firmano un patto di non aggressione" % [game.players[a]["fac"]["short"], game.players[b]["fac"]["short"]])
			refresh(true)
		"pact_end":
			var a := int(d.get("a", -1))
			var b := int(d.get("b", -1))
			if hh >= 0 and (a == hh or b == hh) and human_alive():
				var other := b if a == hh else a
				if other >= 0 and bool(game.players[other]["alive"]):
					Sfx.play("alert")
					toast("Il patto con %s è scaduto: i confini sono di nuovo aperti" % game.players[other]["fac"]["short"], "alert")
			refresh(true)
		"vet", "veteran", "vet_up":
			var t := int(d.get("terr", -1))
			if hh >= 0 and t >= 0 and int(game.terr[t]["owner"]) == hh:
				# il nucleo scrive l'annuncio nel registro (diventa un toast): qui solo il suono
				Sfx.play("research")
				_vet_seen[t] = [hh, vet_of(t)]
		"pact_offer_end":
			if _pact_offer != null and int(d.get("from", -1)) == int(_pact_offer["from"]):
				_pact_offer = null
				close_modal(true)
				game.paused = _paused_before
			_pact_offers.erase(int(d.get("from", -1)))
		"headline":
			var tx := String(d.get("text", ""))
			if tx != "":
				hud.headline(tx)
				var ht := -1   # il titolo di un evento mondiale inquadra il suo territorio
				if "world_event" in game and game.world_event is Dictionary and tx.begins_with(String(Data.WORLD_EVENTS[game.world_event["id"]]["name"])):
					ht = int(game.world_event["terr"])
				_recap_add(tx, "news", ht, 3)
		"objective_done":
			if int(d.get("player", -2)) == hh:
				Sfx.play("research")
		"world_event", "objective_new", "objective_failed":
			refresh(true)
		"turn_start":
			_on_turn_start(int(d.get("player", cur_player())))
		"move", "attack":
			_on_turn_action(name, d)
			if name == "attack" and hh >= 0 and int(d.get("defender", -2)) == hh and int(d.get("player", -2)) != hh:
				Sfx.play("alert")
				hud.flash_alert()
				_tension_until = float(game.time) + 20.0
		"phase":
			refresh(true)
		"fortify":
			if int(d.get("player", -2)) == hh:
				refresh(true)
	if _elim_pending and game.over == null and battle == null:
		_elim_pending = false
		call_deferred("show_eliminated")

# ================================================================== veterani
## Annuncia le stelle guadagnate dai presidi del giocatore (confronto con lo stato precedente, stesso proprietario).
func _check_vet() -> void:
	if game == null or h() < 0 or game.has_method("vet_next"):   # il nucleo annuncia da sé (segnale "veteran" + registro)
		return
	var hh := h()
	for tr in game.terr:
		var t := int(tr["idx"])
		var o := int(tr["owner"])
		var v := clampi(int(tr.get("vet", 0)), 0, 3)
		var prev = _vet_seen.get(t)
		_vet_seen[t] = [o, v]
		if prev != null and o == hh and int(prev[0]) == o and v > int(prev[1]):
			_vet_toast(t, v)

func _vet_toast(t: int, v: int) -> void:
	var tx := "Il presidio di %s diventa veterano %s" % [_tn(t), stars(v)]
	if toasted_recently(tx):
		return
	Sfx.play("research")
	toast(tx, "good")

# ================================================================== diplomazia: offerte delle IA
func _defer_pact_offer() -> void:
	if _pact_offer != null:
		_pact_offers.push_front(int(_pact_offer["from"]))
		_pact_offer = null
	if modal_kind == "pact":
		close_modal(true)
		if game != null:
			game.paused = _paused_before

func _update_pact_offer() -> void:
	if game == null:
		return
	if _pact_offer != null:
		if modal_kind == "help":
			_pact_offer["t_end"] = float(_pact_offer["t_end"]) + get_process_delta_time()   # la guida ferma il conto alla rovescia
			return
		if modal_kind != "pact":
			_pact_offer = null
			return
		var left := float(_pact_offer["t_end"]) - Time.get_ticks_msec() / 1000.0
		modal.update_pact_countdown(left)
		if left <= 0:
			answer_pact_offer(false, true)
		return
	if _pact_offers.is_empty() or modal_kind != "" or game.pending_battle != null or game.over != null or not human_alive():
		return
	var from := int(_pact_offers.pop_front())
	if from < 0 or from >= game.players.size() or not bool(game.players[from]["alive"]) or pact_between(h(), from) != null:
		return
	_pact_offer = {"from": from, "to": h(), "t_end": Time.get_ticks_msec() / 1000.0 + PACT_OFFER_SECS}
	_paused_before = game.paused
	game.paused = true
	Sfx.play("card")
	show_modal("pact", modal.build_pact_offer(from, PACT_OFFER_SECS), false)

func answer_pact_offer(accept: bool, expired: bool = false) -> void:
	if _pact_offer == null:
		return
	var from := int(_pact_offer["from"])
	_pact_offer = null
	close_modal(true)
	if game == null:
		return
	game.paused = _paused_before
	var r = gcall("answer_pact", [from, h(), accept])
	var nm: String = String(game.players[from]["fac"]["short"])
	if r is Dictionary and not r.get("ok", true):
		toast(String(r.get("reason", "Offerta non più valida")), "bad")
	elif not accept:
		toast(("Offerta di %s scaduta: nessun patto" if expired else "Hai respinto l'offerta di %s") % nm, "info")
	refresh(true)

# ================================================================== modali
func show_modal(kind: String, content: Control, closable: bool = true, wide: bool = false) -> void:
	modal_kind = kind
	modal_closable = closable
	if kind != "battle" and toasts.has_method("clear_all"):
		toasts.clear_all()
	modal.show_content(content, wide)
	hud.hide_tip()

func close_modal(force: bool = false) -> void:
	if not force and not modal_closable:
		return
	var was_menu := modal_kind in ["gamemenu", "settings", "saves", "briefing"]
	modal_kind = ""
	modal.hide_content()
	if was_menu and game != null:
		game.paused = _paused_before
		refresh(true)

func show_game_menu() -> void:
	if game == null:
		return
	_grab_thumb()
	_paused_before = game.paused
	game.paused = true
	_show_pause_content()

func _show_pause_content() -> void:
	if game == null:
		return
	game.paused = true
	show_modal("gamemenu", modal.build_game_menu(), true)

func show_settings_modal() -> void:
	var c: Control = load("res://scripts/ui/settings_panel.gd").new().setup(func(): _show_pause_content())
	c.set_meta("modal_width", 1060)
	show_modal("settings", c, true)

func show_saves_modal(md: String) -> void:
	var c: Control = load("res://scripts/ui/saves_panel.gd").new().setup(self, md, func(): _show_pause_content())
	c.set_meta("modal_width", 1000)
	show_modal("saves", c, true)

func show_help() -> void:
	var prev_kind := modal_kind
	if prev_kind != "" and prev_kind != "help":
		var prev_closable := modal_closable
		var prev_content: Control = modal.take_content()
		var prev_wide: bool = modal.is_wide
		_help_return = func(): show_modal(prev_kind, prev_content, prev_closable, prev_wide)
	else:
		_help_return = Callable()
	if game != null and prev_kind == "":
		_paused_before = game.paused
		game.paused = true
		_help_paused = true
	else:
		_help_paused = false
	show_modal("help", modal.build_help(), true, true)

func _help_back() -> void:
	if modal_kind != "help":
		close_modal()
		return
	if _help_return.is_valid():
		var f := _help_return
		_help_return = Callable()
		f.call()
		return
	close_modal(true)
	if _help_paused and game != null:
		game.paused = _paused_before
		_help_paused = false
		refresh(true)

func show_battle_prompt() -> void:
	var pb = game.pending_battle
	if pb == null:
		return
	battle_info = {"attacker": int(pb["attacker"]), "defender": int(game.terr[pb["terr"]]["owner"]), "terr": int(pb["terr"])}
	show_modal("battle", modal.build_battle_prompt(pb), false, false)
	Sfx.play("alert")

func can_manual_battle() -> bool:
	return ResourceLoader.exists(BATTLE_SCENE) and game != null and game.has_method("start_manual_battle")

func battle_auto() -> void:
	close_modal(true)
	if game == null or game.pending_battle == null:
		return
	var info = battle_info
	gcall("resolve_pending_auto")
	if info != null:
		_battle_outcome_toast(info)
	refresh(true)

func _battle_outcome_toast(info: Dictionary) -> void:
	var owner := int(game.terr[info["terr"]]["owner"])
	var att_won: bool = owner == int(info["attacker"])
	var human_won: bool = att_won == (int(info["attacker"]) == h())
	var tn := _tn(info["terr"])
	var txt := ""
	if int(info["attacker"]) == h():
		txt = ("Vittoria a %s: territorio conquistato" % tn) if human_won else ("Sconfitta a %s: i superstiti sono tornati indietro" % tn)
	else:
		txt = ("Difesa riuscita a %s" % tn) if human_won else ("Sconfitta: hai perso %s" % tn)
	toast(txt, "good" if human_won else "bad")
	feedback(txt, "good" if human_won else "bad")

func battle_manual() -> void:
	if not can_manual_battle():
		battle_auto()
		return
	close_modal(true)
	# transizione continua: la telecamera del tabellone scende sul territorio, dissolvenza a nero, poi la battaglia
	# parte dall'alto sullo stesso paesaggio (introduzione) e scende sul campo
	var terr_t := int(battle_info["terr"]) if battle_info is Dictionary and battle_info.has("terr") else -1
	if _cinematic_ok() and terr_t >= 0:
		_transition = true
		var dur: float = map.dive_to(terr_t)
		if dur > 0.45:
			await get_tree().create_timer(dur - 0.45).timeout
		await SceneFade.of(self).fade_to(1.0, 0.45)
		_transition = false
		if game == null or game.pending_battle == null:
			SceneFade.of(self).fade_to(0.0, 0.5)
			return
	var setup = game.start_manual_battle()
	if setup == null or (setup is Dictionary and setup.is_empty()):
		SceneFade.of(self).fade_to(0.0, 0.5)
		return
	var ps = load(BATTLE_SCENE)
	var inst: Node = ps.instantiate() if ps is PackedScene else null
	if inst == null or not inst.has_method("start"):
		if inst:
			inst.free()
		toast("Errore nella battaglia 3D: risoluzione automatica", "bad")
		game.finish_manual_battle({"att": setup["att"]["forces"], "def": setup["def"]["forces"], "winner": "def", "retreated": false, "autoRest": true})
		refresh(true)
		return
	battle_setup = setup
	battle = inst
	hud.visible = false
	hud.hide_tip()
	toasts.clear_all()   # le notifiche del tabellone non devono coprire la HUD della battaglia
	_clear_drag()
	# il tabellone esce dall'albero (niente camera/ambiente/elaborazione in conflitto) e rientra a fine battaglia
	if map != null and map.get_parent() != null:
		_battle_holder = map.get_parent()
		_battle_holder.remove_child(map)
	add_child(battle)
	move_child(battle, 0)
	if battle.has_signal("finished"):
		battle.finished.connect(_on_battle_finished, CONNECT_ONE_SHOT)
	battle.start(setup)
	var cam := _find_camera(battle)
	if cam != null:
		cam.make_current()
	if SceneFade.of(self).opacity() > 0.0:
		SceneFade.of(self).fade_to(0.0, 1.1)
	Sfx.play("battle")
	music("battle")

func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var r := _find_camera(c)
		if r != null:
			return r
	return null

func _on_battle_finished(res: Dictionary) -> void:
	call_deferred("_after_battle", res)

func _after_battle(res) -> void:
	var setup = battle_setup
	var terr_t := int(battle_info["terr"]) if battle_info is Dictionary and battle_info.has("terr") else -1
	var cine := _cinematic_ok() and terr_t >= 0
	if cine:
		# la battaglia ha già alzato la telecamera: dissolvenza a nero, poi il tabellone riparte basso sul territorio e risale
		await SceneFade.of(self).fade_to(1.0, 0.4)
	_end_battle_scene()
	if cine and map != null and map.has_method("rise_from"):
		map.rise_from(terr_t)
		SceneFade.of(self).fade_to(0.0, 0.9)
	if game == null or setup == null:
		return
	if res == null or not (res is Dictionary):
		res = {"att": Data.empty_forces(), "def": setup["def"]["forces"], "winner": "def", "retreated": false, "autoRest": false}
	game.finish_manual_battle(res)
	show_modal("summary", modal.build_summary(setup, res), true)
	refresh(true)
	if _elim_pending and game.over == null:
		_elim_pending = false
		show_eliminated()

## Transizioni cinematiche tabellone ↔ battaglia: solo con il tabellone 3D e fuori dai test automatici (--script).
func _cinematic_ok() -> bool:
	return map_is_3d and map != null and map.has_method("dive_to") and not OS.get_cmdline_args().has("--script")

func _end_battle_scene() -> void:
	if battle != null and is_instance_valid(battle):
		remove_child(battle)
		battle.queue_free()
	battle = null
	battle_setup = null
	if map != null and map.get_parent() == null and _battle_holder != null:
		_battle_holder.add_child(map)
		if map_is_3d:
			move_child(map, 0)
			var cam := _find_camera(map)
			if cam != null:
				cam.make_current()
	_battle_holder = null
	if game != null:
		hud.visible = true
		music("map")
	_sent_marks = ""

func show_end() -> void:
	_end_shown = true
	_record_history(true)
	if h() >= 0 and game.over is Dictionary:
		music("victory" if int(game.over.get("winner", -1)) == h() else "defeat")
	else:
		music("victory")
	show_modal("end", modal.build_end(), true, true)

func show_eliminated() -> void:
	if game == null or _elim_shown or game.over != null:
		return
	_elim_shown = true
	_record_history(true)
	show_modal("elim", modal.build_eliminated(), true, true)

# ================================================================== salvataggi
## Il nucleo sa serializzare la partita?
func save_available() -> bool:
	return game != null and not using_mock and game.has_method("serialize")

## Il nucleo sa ricostruire una partita (static Game.deserialize)?
func load_available() -> bool:
	var s = _game_script()
	if s == null:
		return false
	for m in s.get_script_method_list():
		if String(m.get("name", "")) == "deserialize":
			return true
	return false

func recently_saved() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_save_real < 90.0

func default_save_name() -> String:
	if game == null:
		return "Partita"
	var who: String = String(game.players[h()]["fac"]["short"]) if h() >= 0 else "Spettatore"
	if turn_mode():
		return "%s · turno %d" % [who, round_n()]
	return "%s · minuto %d" % [who, int(float(game.time) / 60.0)]

func _grab_thumb() -> void:
	if DisplayServer.get_name() == "headless":
		_thumb = null
		return
	var tex := get_viewport().get_texture()
	_thumb = tex.get_image() if tex != null else null

func _save_meta(name: String) -> Dictionary:
	var hh := h()
	var P = game.players[hh] if hh >= 0 else null
	var m := {
		"name": name,
		"minute": int(float(game.time) / 60.0),
		"round": round_n() if turn_mode() else 0,
		"time": float(game.time),
		"mode": String(game.get("mode") if "mode" in game else menu_opts["mode"]),
		"faction_name": String(P["name"]) if P != null else "Spettatore",
		"faction_short": String(P["fac"]["short"]) if P != null else "IA",
		"color": "#" + (P["color"] as Color).to_html(false) if P != null else "#8b9a8d",
		"territories": (gcall("territories_of", [hh], []) as Array).size() if hh >= 0 else 0,
		"players": game.players.size(),
	}
	m["mode_name"] = MODE_NAMES.get(m["mode"], m["mode"])
	return m

## Salva la partita corrente nello slot dato. Restituisce true se riuscito.
func save_to_slot(slot: String, name: String, silent: bool = false) -> bool:
	if not save_available():
		if not silent:
			toast("Salvataggio non disponibile", "bad")
		return false
	if battle != null:
		if not silent:
			toast("Non si può salvare durante una battaglia", "bad")
		return false
	# formato consigliato dal nucleo: testo JSON (to_json/from_json); altrimenti il dizionario di serialize()
	var data = game.to_json() if game.has_method("to_json") else game.serialize()
	if not (data is Dictionary or data is String):
		toast("Errore nel salvataggio", "bad")
		return false
	var ui := {"hist": _hist if not ("history" in game) else [], "quota": quota}
	var img := _thumb
	if img == null or modal_kind == "":
		_grab_thumb()
		img = _thumb
	var ok := SaveStore.save(slot, {"game": data, "ui": ui, "opts": menu_opts.duplicate()}, _save_meta(name), img)
	if ok:
		_last_save_real = Time.get_ticks_msec() / 1000.0
		if not silent:
			Sfx.play("build")
			toast("Partita salvata: " + name, "good")
	elif not silent:
		toast("Impossibile scrivere il salvataggio", "bad")
	return ok

func quick_save() -> void:
	if modal_kind != "" and modal_kind != "gamemenu":
		return
	if save_to_slot("quick", "Salvataggio rapido · " + default_save_name()):
		pass

func quick_load() -> void:
	if battle != null:
		toast("Non si può caricare durante una battaglia", "bad")
		return
	if not FileAccess.file_exists(SaveStore.path("quick", "sav")):
		toast("Nessun salvataggio rapido (F5 per crearlo)", "bad")
		return
	load_slot("quick")

func continue_latest() -> void:
	var m = SaveStore.latest()
	if m == null:
		menu.show_page("new")
		return
	load_slot(String(m["slot"]))

## Carica uno slot: ricostruisce la partita con Game.deserialize e la collega all'interfaccia.
func load_slot(slot: String) -> void:
	if not load_available():
		toast("Caricamento non disponibile: il nucleo non supporta ancora i salvataggi", "bad")
		return
	var d = SaveStore.load_data(slot)
	if not (d is Dictionary) or not (d.get("game") is Dictionary or d.get("game") is String):
		toast("Salvataggio danneggiato o incompatibile", "bad")
		return
	var g = null
	if d["game"] is String:
		g = _game_script().from_json(d["game"])
	else:
		g = _game_script().deserialize(d["game"])
	if g == null:
		var why := ""
		var gs = _game_script()
		if gs != null and "last_load_error" in gs:
			why = String(gs.last_load_error)
		toast(why if why != "" else "Impossibile ricostruire la partita", "bad")
		return
	using_mock = false
	var ui: Dictionary = d.get("ui", {})
	_hist = Array(ui.get("hist", []))
	quota = float(ui.get("quota", 0.5))
	if d.get("opts") is Dictionary:
		for k in d["opts"]:
			menu_opts[k] = d["opts"][k]
	_begin_game(g, true)
	_last_save_real = Time.get_ticks_msec() / 1000.0

func _autosave_every() -> float:
	return float(Settings.get_value("autosave")) * 60.0

func _check_autosave() -> void:
	var every := _autosave_every()
	if every <= 0 or game.over != null or battle != null or game.pending_battle != null or modal_kind != "":
		return
	if float(game.time) >= _autosave_next:
		_autosave_next = float(game.time) + every
		if save_available() and float(game.time) > 30.0:
			_grab_thumb()
			if save_to_slot("auto", "Automatico · " + default_save_name(), true):
				hud.saved_hint("Salvataggio automatico")

# ================================================================== cronologia per i grafici
func get_history() -> Array:
	if game != null and "history" in game and game.history is Array and game.history.size() > 0:
		# la cronologia del nucleo è ogni 10 s: aggiungo lo stato attuale perché i grafici finiscano sul valore vero
		var hs: Array = game.history
		if turn_mode():
			if int(hs[-1].get("round", hs[-1].get("t", 0))) < round_n():
				return hs + [_snapshot()]
			return hs.slice(0, hs.size() - 1) + [_snapshot()]
		if float(game.time) - float(hs[-1].get("t", 0)) > 0.5:
			return hs + [_snapshot()]
		return hs.slice(0, hs.size() - 1) + [_snapshot()]   # stesso istante: vale lo stato attuale (es. eliminazione)
	return _hist

## Istantanea ogni 10 s di gioco (solo se il nucleo non ne tiene una propria).
func _record_history(force: bool) -> void:
	if game == null or ("history" in game and game.history is Array and game.history.size() > 0):
		return
	var now_t := float(round_n()) if turn_mode() else float(game.time)
	if not force and now_t < _hist_next:
		return
	_hist_next = now_t + (1.0 if turn_mode() else HIST_EVERY)
	var snap := _snapshot()
	if _hist.size() and absf(float(_hist[-1]["t"]) - snap["t"]) < 0.5:
		_hist[-1] = snap
	else:
		_hist.append(snap)

## Istantanea dello stato attuale {t, terr, power, units, income} (stesso formato di game.history).
func _snapshot() -> Dictionary:
	var n: int = game.players.size()
	var terr := []; var power := []; var units := []; var income := []
	terr.resize(n); power.resize(n); units.resize(n); income.resize(n)
	for i in n:
		terr[i] = 0; power[i] = 0.0; units[i] = 0; income[i] = 0.0
	for tr in game.terr:
		var o := int(tr["owner"])
		if o >= 0 and o < n:
			terr[o] += 1
			units[o] += Data.total_units(tr["forces"])
			power[o] += float(_combat_script.force_power(tr["forces"])) if _combat_script != null else float(Data.total_units(tr["forces"]))
	for d in game.divisions:
		var o := int(d["owner"])
		if o >= 0 and o < n:
			units[o] += Data.total_units(d["forces"])
			power[o] += float(_combat_script.force_power(d["forces"])) if _combat_script != null else float(Data.total_units(d["forces"]))
	for i in n:
		var P: Dictionary = game.players[i]
		# come game._snapshot(): reddito = rates.money al secondo, unità comprese quelle da schierare
		income[i] = float(P["rates"].get("money", 0.0)) if P["alive"] else 0.0
		units[i] += Data.total_units(P.get("pool", {}))
		power[i] = round(power[i])
	if turn_mode():
		return {"t": float(round_n()), "round": round_n(), "terr": terr, "power": power, "units": units, "income": income}
	return {"t": float(game.time), "terr": terr, "power": power, "units": units, "income": income}

# ================================================================== musica
func music(mood: String) -> void:
	var mu := get_node_or_null("/root/Music")
	if mu == null or not mu.has_method("play"):
		return
	if mood == _mood:
		return
	_mood = mood
	mu.play(mood)

func _update_music() -> void:
	if game.over != null or _mood == "victory" or _mood == "defeat":
		return
	# tensione durante i turni delle IA (e dopo un attacco contro il giocatore); "map" quando torna il suo turno
	if (float(game.time) < _tension_until and h() >= 0) or (turn_mode() and h() >= 0 and human_alive() and not my_turn()):
		music("tension")
	else:
		music("map")

# ================================================================== cursori
func _cursor_tex(kind: String) -> Texture2D:
	var N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var amber := Color("#ffd57a")
	var dark := Color(0.03, 0.05, 0.05, 1)
	if kind == "arrow":
		# freccia: riempimento scuro, bordo ambra
		var poly := PackedVector2Array([Vector2(2, 2), Vector2(2, 24), Vector2(8, 18.5), Vector2(12.5, 28), Vector2(16.5, 26.2), Vector2(12, 17), Vector2(20, 16.5)])
		for y in N:
			for x in N:
				var p := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.is_point_in_polygon(p, poly):
					var dmin := 99.0
					for i in poly.size():
						var a: Vector2 = poly[i]
						var b: Vector2 = poly[(i + 1) % poly.size()]
						dmin = minf(dmin, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
					img.set_pixel(x, y, amber if dmin < 1.6 else dark)
	else:
		var col := Color("#ff6a5a") if kind == "target" else Color("#7fe08f")
		var c := Vector2(16, 16)
		for y in N:
			for x in N:
				var p := Vector2(x + 0.5, y + 0.5)
				var r := p.distance_to(c)
				var on := absf(r - 9.0) < 1.3
				if (absf(p.x - c.x) < 1.1 and (r > 4 and r < 15)) or (absf(p.y - c.y) < 1.1 and (r > 4 and r < 15)):
					on = true
				if r < 1.6:
					on = true
				if on:
					img.set_pixel(x, y, col)
				elif absf(r - 9.0) < 2.4 or ((absf(p.x - c.x) < 2.2 or absf(p.y - c.y) < 2.2) and r > 3 and r < 16):
					img.set_pixel(x, y, Color(0, 0, 0, 0.55))
	return ImageTexture.create_from_image(img)

func _setup_cursors() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.set_custom_mouse_cursor(_cursor_tex("arrow"), Input.CURSOR_ARROW, Vector2(2, 2))

func _apply_cursor(kind: String) -> void:
	if kind == _cursor_mode or DisplayServer.get_name() == "headless":
		return
	_cursor_mode = kind
	if kind == "":
		Input.set_custom_mouse_cursor(null, Input.CURSOR_CROSS)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	else:
		Input.set_custom_mouse_cursor(_cursor_tex(kind), Input.CURSOR_CROSS, Vector2(16, 16))
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)

# ================================================================== demo per screenshot
func _run_demo(demo: String) -> void:
	if demo == "play":
		# partita "vera" con le impostazioni predefinite del menu (collaudo lungo con --quit-after)
		act("start")
		_play_autopilot()
		return
	if demo != "tip" and demo != "battle-tip":
		Settings.set_value("tips", false)
	else:
		Settings.set_value("tips", true)
		Settings.reset_tips()
	match demo:
		"menu":
			pass
		"new", "settings", "load", "scenari":
			menu.show_page(demo)
			if demo == "scenari" and Shot.arg("scn") != "":
				menu.select_scenario(int(Shot.arg("scn")))
		"help":
			show_help()
		"scn-brief", "scn-game", "scn-end":
			# scenario per gli screenshot: --scn-id=<id> [--scn-fac=N]
			start_scenario(Shot.arg("scn-id", "corsa_petrolio"), int(Shot.arg("scn-fac", "-1")))
			if game == null or demo == "scn-brief":
				return
			close_modal(true)
			game.paused = false
			for i in 900:
				game.step(0.1)
				if game.pending_battle != null:
					gcall("resolve_pending_auto")
			if demo == "scn-end":
				game.over = {"winner": h(), "reason": "Ha tenuto 3 territori chiave per 60 s"}
			refresh(true)
		"fog", "pact", "offer", "vet", "vet-battle":
			_run_demo3(demo)
		"turn", "attack-panel", "move-panel", "ai-turn", "defense", "fortify", "supply", "supply2", "move", "tut":
			_run_demo_turns(demo)
		"game", "prompt", "pause", "summary", "end", "battle", "deploy", "card", "pause-settings", "save", "tip", "battle-tip", "headline", "elim":
			menu_opts["faction"] = 0
			start_game(false)
			if game == null:
				return
			var hq := int(game.players[h()]["hq"])
			if demo == "prompt" or demo == "battle" or demo == "battle-tip":
				_demo_make_battle(hq)
				if demo == "battle-tip" and game.pending_battle != null:
					show_battle_prompt()
				if demo == "battle" and game.pending_battle != null:
					show_battle_prompt()
					battle_manual()
				return
			# un po' di partita per avere eventi, divisioni e produzione
			var steps := 450
			if demo == "end" or demo == "elim":
				steps = int(Shot.arg("steps", "4000"))
				game.speed = 1.0
			for i in steps:
				game.step(0.1)
				_record_history(false)
				if game.pending_battle != null:
					gcall("resolve_pending_auto")
				if game.over != null:
					break
			var P: Dictionary = game.players[h()]
			if P["cards"].size() < 4:
				P["cards"].append_array([{"type": "inf"}, {"type": "tank"}, {"type": "air"}, {"type": "jolly"}].slice(0, 4 - P["cards"].size()))
			_card_count = -1
			hq = int(P["hq"])
			select(hq)
			if demo == "game":
				sel_cards = [0, 1]
				var my: Array = gcall("territories_of", [h()], [])
				for t in my:
					if t != hq and Data.total_units(game.terr[t]["forces"]) > 0:
						var tg: Array = gcall("valid_targets", [h(), t], [])
						if tg.size():
							gcall("send_division", [h(), t, tg[0]["idx"], 0.5])
							break
				game.step(0.5)
				game.speed = 1.0
				toast("Rinforzi disponibili: 6 fanteria da schierare", "good")
				toast("Conquistato: Iberia", "good")
				hud.flash_alert()
				toast("FO: 9 unità in arrivo su Germania", "alert")
				_demo_threats = [{"to": hq, "owner": 1, "n": 9, "left": 14.0}, {"to": hq, "owner": 3, "n": 4, "left": 30.0}]
			elif demo == "pause":
				show_game_menu()
			elif demo == "pause-settings":
				show_game_menu()
				show_settings_modal()
			elif demo == "save":
				await get_tree().create_timer(0.6).timeout
				_grab_thumb()
				save_to_slot("auto", "Automatico · AAN · minuto 3", true)
				show_game_menu()
				show_saves_modal("save")
			elif demo == "tip":
				select(hq)
			elif demo == "headline":
				hud.headline("La Federazione Orientale invade l'Europa: cade Berlino")
			elif demo == "elim":
				_elim_shown = false
				show_eliminated()
			elif demo == "deploy":
				P["pool"]["inf"] = maxi(4, int(P["pool"]["inf"]))
				set_mode({"type": "deploy"})
			elif demo == "card":
				sel_cards = [0, 1, 2]
				refresh(true)
				play_op("missile")
			elif demo == "summary":
				var tgt := int(Data.TERRITORIES[hq]["adj"][0])
				var setup := {"terrIdx": tgt, "terrain": Data.TERRITORIES[tgt]["ter"], "terrName": Data.TERRITORIES[tgt]["name"],
					"att": {"player": h(), "name": P["name"], "forces": {"inf": 8, "tank": 3}}, "def": {"player": -1, "name": "Neutrali", "forces": {"inf": 5}}}
				show_modal("summary", modal.build_summary(setup, {"winner": "att", "retreated": false}), true)
			elif demo == "end":
				_end_shown = true
				if game.over == null:
					game.over = {"winner": h(), "reason": "Controlla il 70% dei territori."}
				show_end()
		_:
			pass

## Demo della fase 6 (turni) per gli screenshot: --demo=turn|attack-panel|move-panel|ai-turn|defense|fortify
func _run_demo_turns(demo: String) -> void:
	menu_opts["faction"] = int(Shot.arg("faction", "0"))
	menu_opts["fog"] = Shot.arg("fog", "0") == "1"
	start_game(false)
	if game == null or not turn_mode():
		return
	var hq := int(game.players[h()]["hq"])
	# alcuni turni giocati in automatico per avere una situazione interessante
	var rounds := int(Shot.arg("rounds", "0"))
	if rounds > 0:
		demo_play_rounds(rounds)
		hq = int(game.players[h()]["hq"])
	call_deferred("_demo_ui_args")
	match demo:
		"supply":
			# inizio turno: rinforzi da schierare (schieramento attivo), QG selezionato
			select(hq)
			if Shot.arg("threat") == "1":
				_demo_threat()
		"supply2":
			# dopo lo schieramento: pannello del territorio con le schede, esito nel riquadro ORDINI
			select(hq)
			act("deploy-here")
			if Shot.arg("rtab") != "":
				hud.rtab = Shot.arg("rtab")
			for k in Data.RES_KEYS:
				game.players[h()]["res"][k] = maxf(float(game.players[h()]["res"][k]), 300.0)
			refresh(true)
		"move":
			if Data.total_units(game.players[h()]["pool"]) > 0:
				tcall("place_pool", [hq])
			tcall("end_phase")
			tcall("end_phase")
			select(-1)
		"tut":
			# tutorial guidato: --tstep=intro|deploy|recruit|source|target|panel
			coach.start()
			var ts := Shot.arg("tstep", "intro")
			if ts != "intro":
				coach._on_next()
			if ts in ["recruit", "source", "target", "panel"]:
				_on_map_clicked(hq, MOUSE_BUTTON_LEFT, false)
				coach.update()
			if ts in ["source", "target", "panel"]:
				end_phase()
				select(-1)
				coach.update()
			if ts in ["target", "panel"]:
				var pr := demo_attack_pair()
				if pr.size():
					select(pr[0])
					coach.update()
					if ts == "panel":
						_turn_target(pr[1])
						coach.update()
		"turn":
			# fase d'attacco con un bersaglio evidenziato
			var pair := demo_attack_pair()
			if Data.total_units(game.players[h()]["pool"]) > 0:
				tcall("place_pool", [hq])
			tcall("end_phase")
			if pair.size():
				select(pair[0])
				if map != null:
					map.focus(pair[0])
			else:
				select(hq)
		"attack-panel", "move-panel":
			var pair := demo_attack_pair() if demo == "attack-panel" else demo_move_pair()
			if pair.is_empty():
				select(hq)
				return
			if Data.total_units(game.players[h()]["pool"]) > 0:
				tcall("place_pool", [pair[0]])
			if demo == "move-panel":
				tcall("end_phase")
				tcall("end_phase")
			select(pair[0])
			if map != null:
				map.focus(pair[0])
			_turn_target(pair[1])
		"fortify":
			tcall("place_pool", [hq])
			if "fort" in game.terr[hq] or game.terr[hq].has("fort"):
				game.terr[hq]["fort"] = {"trench": 2, "mines": 1, "bunker": 0}
			for k in Data.RES_KEYS:
				game.players[h()]["res"][k] = maxf(float(game.players[h()]["res"][k]), 400.0)
			select(hq)
			if map != null:
				map.focus(hq)
		"ai-turn":
			Settings.set_value("ai_speed", "lenta")
			_apply_ai_delay()
			if "truce_rounds" in game:
				game.truce_rounds = 0
			select(-1)
			end_turn()
		"defense":
			if "truce_rounds" in game:
				game.truce_rounds = 0
			select(-1)
			var hh := h()
			end_turn()
			var ai := cur_player()
			var pair := []
			for guard in game.players.size():
				ai = cur_player()
				if ai == hh or game.pending_battle != null:
					break
				for t in gcall("territories_of", [ai], []):
					for j in Data.TERRITORIES[int(t)]["adj"]:
						if int(game.terr[int(j)]["owner"]) == hh and Data.total_units(game.terr[int(t)]["forces"]) >= 2:
							pair = [int(t), int(j)]
							break
					if pair.size():
						break
				if pair.size():
					break
				game.skip_ai_turn()   # quest'IA non confina col giocatore: passa alla successiva
			if pair.is_empty():
				return
			Data.add_forces(game.terr[pair[0]]["forces"], {"inf": 6, "tank": 4, "art": 2})
			var f := movable_forces(pair[0])
			var ar = game.attack(pair[0], pair[1], f)
			print("[demo] difesa ", pair, " cur=", cur_player(), " -> ", ar, " pending=", game.pending_battle != null)
			if map != null:
				map.turn_arrow(pair[0], pair[1], ai, "attack", 0.6, f)
				map.focus(pair[1])

## Argomenti comuni delle demo: --drawer=<scheda> apre il cassetto a sinistra.
func _demo_ui_args() -> void:
	if Shot.arg("drawer") != "":
		hud.toggle_tab(Shot.arg("drawer"))
	refresh(true)

## Gioca N round con risoluzioni automatiche (umano: schiera, attacca il bersaglio più debole, passa).
func demo_play_rounds(n: int) -> void:
	var r0 := round_n()
	var guard := 0
	while round_n() < r0 + n and game.over == null and guard < 20000:
		guard += 1
		if game.pending_battle != null:
			gcall("resolve_pending_auto")
			continue
		if my_turn():
			var hq := int(game.players[h()]["hq"])
			if Data.total_units(game.players[h()]["pool"]) > 0:
				tcall("place_pool", [hq])
			var pair := demo_attack_pair()
			if pair.size():
				tcall("attack", [pair[0], pair[1], movable_forces(pair[0])])
				if game.pending_battle != null:
					gcall("resolve_pending_auto")
			tcall("end_turn")
			continue
		if game.has_method("skip_ai_turn"):
			game.skip_ai_turn()
		else:
			game.update(0.5)
	_turn_seen = ""
	refresh(true)

## Screenshot (--threat=1): una minaccia annunciata contro un territorio del giocatore, con il rapporto del round.
func _demo_threat() -> void:
	if game == null or not game.has_method("set_intent"):
		return
	var best := []
	var bn := -1
	for t in gcall("territories_of", [h()], []):
		for j in Data.TERRITORIES[int(t)]["adj"]:
			var o := int(game.terr[j]["owner"])
			var n := Data.total_units(game.terr[j]["forces"])
			if o >= 0 and o != h() and n > bn:
				bn = n
				best = [o, j, int(t)]
	if best.is_empty():
		return
	game.set_intent(best[0], best[1], best[2])
	_recap.append({"text": "%s conquista %s" % [_sh(best[0]), _tn(best[1])], "kind": "info", "terr": best[1], "w": 1})
	_recap_key = ""
	_show_recap()
	_pact_offers.clear()   # niente proposte di patto sopra lo screenshot
	focus_terr(best[2])
	refresh(true)

## Coppia [mio territorio, bersaglio] per un attacco dimostrativo (bersaglio più debole).
func demo_attack_pair() -> Array:
	var best := []
	var best_v := 1e9
	for t in gcall("territories_of", [h()], []):
		if Data.total_units(game.terr[int(t)]["forces"]) < 3:
			continue
		for tg in attack_targets(int(t)):
			var j := int(tg["idx"])
			var v := float(Data.total_units(game.terr[j]["forces"])) - Data.total_units(game.terr[int(t)]["forces"]) * 0.5
			if v < best_v:
				best_v = v
				best = [int(t), j]
	return best

func demo_move_pair() -> Array:
	var best := []
	var bn := 0
	for t in gcall("territories_of", [h()], []):
		var n := Data.total_units(game.terr[int(t)]["forces"])
		if n < 3 or n <= bn or int(game.terr[int(t)].get("regroup", 0)) > 0:
			continue
		var mt := move_targets(int(t))
		if mt.size():
			bn = n
			best = [int(t), int(mt[0]["idx"])]
	return best

## Demo "play": ogni pochi secondi risponde alle finestre come farebbe un giocatore distratto
## (battaglie automatiche, chiude riepiloghi) e con --snap=S salva uno screenshot dopo S secondi senza chiudere.
func _play_autopilot() -> void:
	var t0 := Time.get_ticks_msec() / 1000.0
	var snap := float(Shot.arg("snap", "-1"))
	var snapped := false
	while is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if game == null:
			continue
		if modal_kind == "battle":
			battle_auto()
		elif modal_kind == "summary" or modal_kind == "elim":
			close_modal(true)
		elif modal_kind == "pact":
			answer_pact_offer(true)
		var el := Time.get_ticks_msec() / 1000.0 - t0
		if snap > 0 and not snapped and el >= snap:
			snapped = true
			var img := get_viewport().get_texture().get_image()
			var p := ProjectSettings.globalize_path("res://").path_join(Shot.arg("snap_path", "docs/screens/ui3_partita_vera.png"))
			print("[play] screenshot minuto ", UIKit.fmt_time(game.time), " err=", img.save_png(p))
		if int(el) % 20 == 0:
			print("[play] t=%s reale=%d s terr=%d modal=%s" % [UIKit.fmt_time(game.time), int(el), (gcall("territories_of", [h()], []) as Array).size(), modal_kind])

## Demo della fase 3 (nebbia, patti, offerte, veterani) per gli screenshot.
func _run_demo3(demo: String) -> void:
	menu_opts["faction"] = int(Shot.arg("faction", "1"))
	menu_opts["fog"] = true
	start_game(false)
	if game == null:
		return
	var hq := int(game.players[h()]["hq"])
	if demo == "vet-battle":
		for t in gcall("territories_of", [h()], []):
			game.terr[t]["vet"] = 2
		_demo_make_battle(hq)
		if game.pending_battle != null:
			show_battle_prompt()
		return
	for i in 900:
		game.step(0.1)
		_record_history(false)
		if game.pending_battle != null:
			gcall("resolve_pending_auto")
		if game.over != null:
			break
	game.speed = 1.0
	hq = int(game.players[h()]["hq"])
	var ai := -1
	for P in game.players:
		if int(P["idx"]) != h() and P["alive"]:
			ai = int(P["idx"])
			break
	match demo:
		"fog":
			var best := -1
			for t in Data.TERRITORIES.size():
				if not is_vis(t) and (best < 0 or estimate(t) >= 0):
					best = t
					if estimate(t) >= 0 and Shot.arg("fogpick", "est") == "est":
						break
			select(best if best >= 0 else hq)
			if best >= 0 and map != null and map.has_method("focus"):
				map.focus(best)
		"pact":
			propose_pact(ai)
			if pact_between(h(), ai) == null and "pacts" in game:
				game.pacts.append({"a": h(), "b": ai, "until": float(game.time) + 300.0})   # solo per la foto
				refresh(true)
			var pt := -1
			for t in gcall("territories_of", [ai], []):
				pt = t
				if is_vis(t):
					break
			select(pt if pt >= 0 else hq)
			if pt >= 0 and map != null and map.has_method("focus"):
				map.focus(pt)
		"offer":
			select(-1)
			var other := -1
			for P in game.players:
				if int(P["idx"]) != h() and P["alive"]:
					other = int(P["idx"])
			_on_signal("pact_offer", {"from": other, "to": h()})
		"vet":
			if game.has_method("_gain_xp"):
				var v0 := vet_of(hq)
				for i in 30:
					game._gain_xp(hq)
					if vet_of(hq) >= mini(3, v0 + 2):
						break
			else:
				game.terr[hq]["vet"] = 2
			_check_vet()
			select(hq)

func _demo_make_battle(hq: int) -> void:
	var tgt := -1
	var src := hq
	var mine: Array = [hq] + Array(gcall("territories_of", [h()], []))
	for a in mine:
		for j in Data.TERRITORIES[a]["adj"]:
			if int(game.terr[j]["owner"]) != h() and Data.total_units(game.terr[j]["forces"]) > 0:
				tgt = j
				src = a
				break
		if tgt >= 0:
			break
	if tgt < 0:
		return
	# rinforzo la sorgente con le forze del QG per avere uno scontro interessante
	if src != hq:
		Data.add_forces(game.terr[src]["forces"], game.terr[hq]["forces"])
		game.terr[hq]["forces"] = Data.empty_forces()
		game.terr[hq]["forces"]["inf"] = 2
	quota = 1.0
	sel = src
	refresh(true)
	gcall("send_division", [h(), src, tgt, 1.0])
	for i in 2000:
		game.step(0.1)
		if game.pending_battle != null:
			break
	quota = 0.5
	refresh(true)
