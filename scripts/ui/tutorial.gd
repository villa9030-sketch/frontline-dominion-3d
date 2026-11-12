extends Control
## Prima partita guidata: suggerimenti contestuali brevi, mostrati una volta sola (Settings.tips_seen) e disattivabili.
## main chiama update() ~4 volte al secondo (anche durante la battaglia comandata).

var main = null
var panel: PanelContainer
var title_lbl: Label
var text_lbl: RichTextLabel
var step_lbl: Label
var cur := ""
var _shown_t := 0.0
var _tw: Tween

const ORDER := ["welcome", "deploy", "attack", "endturn", "truce", "build", "battle", "battle_cmd", "cards", "research"]
const TITLES := {
	"welcome": "Benvenuto, comandante",
	"attack": "Espanditi tra i neutrali",
	"deploy": "Schiera i rinforzi",
	"truce": "La tregua iniziale",
	"build": "Costruisci l'industria",
	"battle": "Battaglia in arrivo",
	"battle_cmd": "Battaglia comandata",
	"cards": "Carte comando",
	"research": "Ricerca tecnologica",
	"endturn": "Fine del turno",
}

func _tm() -> bool:
	return main != null and main.turn_mode()

func _rnd() -> int:
	return main.round_n() if _tm() else 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var sb := UIKit.box(Color(0.045, 0.07, 0.065, 0.97), Color(UIKit.AMBER, 0.55), 1, 5, Vector4(16, 12, 16, 12))
	sb.border_width_left = 4
	sb.border_color = UIKit.AMBER
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size.x = 430
	panel.visible = false
	add_child(panel)
	var v := UIKit.vbox(6)
	var h := UIKit.hbox(9)
	h.add_child(UIKit.icon("bulb", 22))
	title_lbl = UIKit.label("", 17, UIKit.AMBER2, "sans", 700)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title_lbl)
	step_lbl = UIKit.label("", 11, UIKit.DIM, "mono", 700)
	h.add_child(step_lbl)
	v.add_child(h)
	text_lbl = UIKit.rich("", 14)
	text_lbl.custom_minimum_size.x = 398
	v.add_child(text_lbl)
	var bh := UIKit.hbox(8)
	bh.add_child(UIKit.spacer())
	bh.add_child(UIKit.button("Disattiva suggerimenti", "ghost", "sm", func(): disable()))
	var ok := UIKit.button("Ho capito", "primary", "sm", func(): dismiss())
	ok.custom_minimum_size.x = 110
	bh.add_child(ok)
	v.add_child(bh)
	panel.add_child(v)

func _enabled() -> bool:
	return bool(Settings.get_value("tips")) and main != null and main.game != null and main.h() >= 0

func reset() -> void:
	cur = ""
	panel.visible = false

func disable() -> void:
	Settings.set_value("tips", false)
	_hide()
	main.toast("Suggerimenti disattivati (riattivabili nelle Impostazioni)", "info")

func dismiss() -> void:
	_hide()

func _hide() -> void:
	if cur == "":
		return
	cur = ""
	_hidden_at = Time.get_ticks_msec() / 1000.0
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(panel, "modulate:a", 0.0, 0.18)
	_tw.tween_callback(func(): panel.visible = false)

func _show(id: String) -> void:
	cur = id
	_shown_t = Time.get_ticks_msec() / 1000.0
	Settings.mark_tip(id)
	title_lbl.text = TITLES.get(id, "Suggerimento")
	var seen := 0
	for k in ORDER:
		if Settings.tip_seen(k):
			seen += 1
	step_lbl.text = "%d/%d" % [seen, ORDER.size()]
	text_lbl.text = _text(id)
	panel.visible = true
	panel.reset_size()
	_place()
	if _tw:
		_tw.kill()
	panel.modulate.a = 0.0
	var y0 := panel.position.y
	panel.position.y = y0 + 14
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	_tw.tween_property(panel, "position:y", y0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Sfx.play("select")

func _place() -> void:
	var vs := get_viewport_rect().size
	panel.reset_size()
	var sz := panel.size
	if cur == "battle":
		panel.position = Vector2(16, 120)
	elif cur == "battle_cmd":
		panel.position = Vector2(16, vs.y * 0.30)
	else:
		# in alto a sinistra, accanto alla barra a icone (lontano dal riquadro ORDINI e dal pannello territorio)
		var x0 := 90.0
		if main.hud != null and main.hud.left.visible:
			x0 = main.hud.left.position.x + main.hud.left.size.x + 10
		panel.position = Vector2(x0, 140)

func _text(id: String) -> String:
	var E: Dictionary = Data.ECON
	if _tm():
		var tr := int(main.game.truce_rounds) if "truce_rounds" in main.game else 2
		match id:
			"welcome":
				return "Si gioca [b]a turni[/b]: la barra in alto mostra il turno e le fasi [b]Rifornimento › Attacco › Spostamento[/b]. Il tuo [b]QG ★[/b] è selezionato: a destra forze, edifici, reclutamento e fortificazioni. [b]WASD[/b] o bordi per la vista, [b]rotella[/b] per lo zoom."
			"deploy":
				return "Fase di [b]rifornimento[/b]: hai rinforzi da schierare. Premi [b]Schiera[/b] (N) nella barra in basso e fai clic su un tuo territorio, oppure [b]Schiera qui[/b] nel pannello del territorio."
			"attack":
				return "Un [b]attacco per turno[/b]: seleziona un tuo territorio con almeno 2 unità e fai clic su un [b]neutrale evidenziato[/b]. Nel pannello scegli le forze con i cursori, guarda la previsione e premi [b]Attacca[/b]."
			"endturn":
				return "Puoi ancora fare [b]uno spostamento[/b] tra tuoi territori collegati (fase Spostamento). Quando hai finito premi [b]Fine turno[/b] o [b]Invio[/b]: giocano le IA, le loro mosse appaiono sul tabellone (Spazio accelera)."
			"truce":
				return "Per i primi [b]%d turni[/b] nessuno può attaccare gli altri giocatori: si conquistano solo i neutrali. La barra in alto mostra «Tregua: ancora N turni»." % tr
			"build":
				return "Nella fase di rifornimento scegli un [b]edificio[/b] nel pannello del territorio (1–3 turni): la [b]Fabbrica[/b] sblocca carri e artiglieria, l'[b]Impianto[/b] aumenta la produzione. Le [b]fortificazioni[/b] (trincee, mine, bunker) rafforzano subito la difesa."
			"battle":
				return "[b]Risoluzione automatica[/b] calcola subito l'esito. Il [b]comando diretto (3D)[/b] ti porta sul campo con +10% alle tue truppe; se sei tu a difenderti, schieri per primo."
			"cards":
				return "Hai almeno tre [b]carte comando[/b]: apri la scheda [b]Carte[/b] nella barra a sinistra e, nella fase di rifornimento, seleziona un tris valido (o [b]Tris automatico[/b]) e scegli l'operazione: rinforzi, missile, sabotaggio o golpe."
			"research":
				return "Il pulsante [b]Ricerca[/b] in alto porta la tua fazione al livello tecnologico successivo in alcuni turni: nuove unità e +%d%% di attacco per livello." % int(round(Data.TECH_COMBAT_BONUS * 100))
	match id:
		"welcome":
			return "Il tuo [b]QG ★[/b] è selezionato: a destra vedi forze, edifici e reclutamento. [b]Clic sinistro[/b] su un territorio per selezionarlo; [b]WASD[/b] o bordi per spostare la vista, [b]rotella[/b] per lo zoom, [b]Spazio[/b] per la pausa."
		"attack":
			return "Seleziona un tuo territorio con truppe e fai [b]clic destro[/b] su un territorio [b]neutrale[/b] evidenziato (oppure [b]trascina[/b] fin lì). Parte una divisione con la quota scelta nel pannello (25–100%)."
		"deploy":
			return "Hai rinforzi in attesa: premi [b]Schiera[/b] nella barra in basso e poi fai clic su un tuo territorio, oppure usa [b]Schiera qui[/b] nel pannello del territorio selezionato."
		"truce":
			return "Per i primi [b]%d minuti[/b] nessuno può attaccare gli altri giocatori: si conquistano solo i neutrali. Sfrutta la tregua per espanderti e costruire. Il conto alla rovescia è nel pannello a sinistra." % int(round(E["truce"] / 60.0))
		"build":
			return "Nel pannello del territorio scegli un [b]edificio[/b]: la [b]Fabbrica[/b] sblocca carri e artiglieria, l'[b]Impianto[/b] aumenta la produzione, le [b]Fortificazioni[/b] rafforzano la difesa. Il QG vale già come caserma e fabbrica."
		"battle":
			return "[b]Risoluzione automatica[/b] calcola subito l'esito (vedi la previsione). [b]Comanda la battaglia[/b] ti porta sul campo 3D con +10% alle tue truppe."
		"battle_cmd":
			return "Durante lo [b]schieramento[/b] disponi i reparti nella tua zona, poi premi [b]Inizia[/b]. In battaglia: [b]trascina[/b] col sinistro per selezionare, [b]clic destro[/b] per muovere o attaccare; rotella per lo zoom, [b]Q/E[/b] per ruotare. Abilità: [b]F[/b] fumo, [b]J[/b] supporto aereo, [b]T[/b] mantieni posizione. Per chiudere subito: [b]Risolvi in automatico[/b]."
		"cards":
			return "Hai almeno tre [b]carte comando[/b]: selezionane un tris valido (tre uguali, tre diverse o con jolly) oppure premi [b]Tris automatico[/b], poi scegli l'operazione: rinforzi, missile, sabotaggio o golpe."
		"research":
			return "Il pulsante [b]Ricerca[/b] in alto porta la tua fazione al livello tecnologico successivo: nuove unità e +%d%% di attacco per livello." % int(round(Data.TECH_COMBAT_BONUS * 100))
	return ""

## Condizione per mostrare un suggerimento.
func _want(id: String) -> bool:
	var g = main.game
	var hh: int = main.h()
	var P: Dictionary = g.players[hh]
	if not P["alive"]:
		return false
	if _tm():
		var free: bool = main.modal_kind == "" and main.battle == null
		# a turni il riquadro ORDINI e il tutorial guidato spiegano già i passi base
		if id in ["welcome", "deploy", "attack", "endturn", "truce", "build"]:
			return false
		match id:
			"welcome":
				return free and main.my_turn()
			"deploy":
				return free and main.my_phase("supply") and Data.total_units(P["pool"]) > 0 and Settings.tip_seen("welcome") and _since_hidden() > 1.0
			"attack":
				return free and main.my_turn() and not main.attacked_any() and main.phase_key() != "move" and Settings.tip_seen("welcome") and Data.total_units(P["pool"]) == 0 and _since_hidden() > 1.0
			"endturn":
				return free and main.my_turn() and (main.attacked_any() or main.phase_key() == "move")
			"truce":
				return free and main.my_turn() and _rnd() >= 2 and main.truce_turns() > 0
			"build":
				return free and main.my_phase("supply") and _rnd() >= 2 and main.sel_own() and _no_building(hh)
			"research":
				if not free or not main.my_phase("supply") or _rnd() < 3 or P["research"] != null or int(P["tech"]) >= 4:
					return false
				var rc2 = main.gcall("research_cost", [hh])
				return rc2 != null and main.gcall("can_afford", [hh, rc2["cost"]], false)
			"cards":
				return free and main.my_phase("supply") and P["cards"].size() >= 3
	match id:
		"welcome":
			return main.modal_kind == "" and main.battle == null
		"attack":
			if main.modal_kind != "" or main.battle != null or float(g.time) > float(Data.ECON["truce"]):
				return false
			return Settings.tip_seen("welcome") and _since_hidden() > 1.5
		"deploy":
			return main.modal_kind == "" and main.battle == null and Data.total_units(P["pool"]) > 0
		"truce":
			return main.modal_kind == "" and main.battle == null and float(g.time) > 50.0 and float(g.time) < float(Data.ECON["truce"]) - 20
		"build":
			return main.modal_kind == "" and main.battle == null and float(g.time) > 75.0 and main.sel_own() and _no_building(hh)
		"battle":
			return main.modal_kind == "battle"
		"battle_cmd":
			return main.battle != null
		"cards":
			return main.modal_kind == "" and main.battle == null and P["cards"].size() >= 3
		"research":
			if main.modal_kind != "" or main.battle != null or float(g.time) < 160.0 or P["research"] != null or int(P["tech"]) >= 4:
				return false
			var rc = main.gcall("research_cost", [hh])
			return rc != null and main.gcall("can_afford", [hh, rc["cost"]], false)
	return false

## Condizione per cui il suggerimento corrente è stato eseguito (si chiude da solo).
func _done(id: String) -> bool:
	var g = main.game
	var hh: int = main.h()
	var P: Dictionary = g.players[hh]
	if _tm():
		match id:
			"welcome":
				return (main.sel >= 0 and main.sel != int(P["hq"])) or main.phase_key() != "supply"
			"attack":
				return main.attacked_any() or not main.my_turn()
			"endturn":
				return not main.my_turn()
	match id:
		"welcome":
			return main.sel >= 0 and main.sel != int(P["hq"])
		"attack":
			for d in g.divisions:
				if int(d["owner"]) == hh:
					return true
			return false
		"deploy":
			return Data.total_units(P["pool"]) == 0
		"build":
			return not _no_building(hh)
		"battle":
			return main.modal_kind != "battle"
		"battle_cmd":
			return main.battle == null
		"cards":
			return P["cards"].size() < 3
		"research":
			return P["research"] != null
	return false

func _no_building(hh: int) -> bool:
	for tr in main.game.terr:
		if int(tr["owner"]) == hh and (tr["building"] != null or tr["buildings"].size() > 0):
			return false
	return true

var _hidden_at := 0.0
func _since_hidden() -> float:
	return Time.get_ticks_msec() / 1000.0 - _hidden_at

func update() -> void:
	if not _enabled() or (main.coach != null and main.coach.active):
		if cur != "":
			_hide()
		return
	var now := Time.get_ticks_msec() / 1000.0
	if cur != "":
		var timeout := 16.0 if cur == "truce" else 40.0
		var bad_ctx: bool = (cur != "battle" and cur != "battle_cmd" and (main.modal_kind != "" or main.battle != null))
		if bad_ctx:
			panel.visible = false
			_shown_t += 0.25
			return
		if _done(cur) or now - _shown_t > timeout:
			_hide()
		else:
			if not panel.visible:
				panel.visible = true
				panel.modulate.a = 1.0
			_place()
		return
	if now - _hidden_at < 1.2:
		return
	for id in ORDER:
		if Settings.tip_seen(id):
			continue
		if _want(id):
			_show(id)
			return
