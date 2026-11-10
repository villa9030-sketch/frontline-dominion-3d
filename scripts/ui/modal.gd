extends Control
## Finestre modali: battaglia (previsione + Automatica/Comanda), riepilogo, vittoria/sconfitta, eliminato,
## menu di pausa, guida. main.show_modal(kind, content, closable, wide) mostra il contenuto costruito qui.

var main = null
var dim: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var holder: VBoxContainer
var is_wide := false
var _current: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	dim = ColorRect.new()
	dim.color = Color(0, 0.01, 0.01, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	panel = PanelContainer.new()
	var sb := UIKit.box(Color(0.035, 0.06, 0.06, 0.97), UIKit.LINE2, 1, 6, Vector4(30, 24, 30, 24))
	sb.border_width_top = 3
	sb.border_color = Color(UIKit.AMBER, 0.75)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 30
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	holder = UIKit.vbox(0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)

func show_content(c: Control, wide: bool) -> void:
	if _current != null and is_instance_valid(_current) and _current.get_parent() == holder:
		holder.remove_child(_current)
		_current.queue_free()
	_current = c
	is_wide = wide
	holder.add_child(c)
	if not visible:
		panel.modulate.a = 0.0
		dim.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.16)
		tw.tween_property(dim, "modulate:a", 1.0, 0.22)
	visible = true
	var w := 1180.0 if wide else 680.0
	if c.has_meta("modal_width"):
		w = float(c.get_meta("modal_width"))
	panel.custom_minimum_size.x = w
	scroll.custom_minimum_size.x = w - 60
	call_deferred("_fit")
	_fit()

func _fit() -> void:
	if _current == null or not is_instance_valid(_current):
		return
	var vh := get_viewport_rect().size.y
	scroll.custom_minimum_size.y = minf(_current.get_combined_minimum_size().y, vh - 120)
	panel.reset_size()

## Stacca il contenuto attuale senza liberarlo (per tornarci dopo la guida).
func take_content() -> Control:
	var c := _current
	if c != null and c.get_parent() == holder:
		holder.remove_child(c)
	_current = null
	return c

func hide_content() -> void:
	if _current != null and is_instance_valid(_current):
		if _current.get_parent() == holder:
			holder.remove_child(_current)
		_current.queue_free()
	_current = null
	visible = false

# ------------------------------------------------------------------ mattoni
func _title(text: String, col: Color = UIKit.AMBER2, size: int = 28) -> Label:
	var l := UIKit.label(text, size, col, "cond", 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l

func _center_text(text: String, size: int = 15, col: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _buttons(items: Array) -> HBoxContainer:
	var h := UIKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for it in items:
		var b := UIKit.button(it[0], it[1], "big", func(): main.act(it[2]), it[3] if it.size() > 3 else "")
		if it.size() > 4 and it[4] == false:
			b.disabled = true
		h.add_child(b)
	return h

# ------------------------------------------------------------------ menu di pausa
func build_game_menu() -> Control:
	var g = main.game
	var v := UIKit.vbox(10)
	v.add_child(_title("PARTITA IN PAUSA"))
	var info := ("Turno %d" % main.round_n()) if main.turn_mode() else ("Minuto " + UIKit.fmt_time(g.time))
	if main.h() >= 0:
		info += "  ·  " + String(g.players[main.h()]["name"])
	else:
		info += "  ·  Spettatore"
	v.add_child(_center_text(info, 14, UIKit.DIM))
	v.add_child(UIKit.spacer(0, 6, false))
	var can_save: bool = main.save_available()
	var items := [
		["play", "Riprendi", "primary", "resume", true, ""],
		["save", "Salva partita", "normal", "save-menu", can_save, "" if can_save else "Salvataggi non ancora supportati dal nucleo"],
		["load", "Carica partita", "normal", "load-menu", true, ""],
		["gear", "Impostazioni", "normal", "settings", true, ""],
		["help", "Come si gioca", "normal", "help", true, ""],
	]
	for it in items:
		v.add_child(_menu_row(it[0], it[1], it[2], func(): main.act(it[3]), it[4], it[5]))
	v.add_child(UIKit.spacer(0, 4, false))
	var quit_b: Button = _menu_row("exit", "Abbandona e torna al menu", "danger", Callable(), true, "")
	var armed := [false]
	quit_b.pressed.connect(func():
		Sfx.play("click")
		if armed[0] or main.recently_saved():
			main.act("quit")
			return
		armed[0] = true
		var l: Label = quit_b.get_meta("label")
		l.text = "Conferma: i progressi non salvati andranno persi"
		l.add_theme_color_override("font_color", Color("#ffd0c8")))
	v.add_child(quit_b)
	var foot := _center_text("Esc riprende · F5 salvataggio rapido · F9 caricamento rapido", 12, UIKit.DIM)
	v.add_child(UIKit.spacer(0, 2, false))
	v.add_child(foot)
	return v

func _menu_row(ic: String, text: String, kind: String, cb: Callable, enabled: bool, tip: String) -> Button:
	var b := UIKit.button("", kind, "big", cb, tip)
	b.custom_minimum_size = Vector2(420, 46)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	var h := UIKit.hbox(12)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	h.add_child(UIKit.icon(ic, 18, Color(UIKit.TEXT, 1.0 if enabled else 0.4)))
	var l := UIKit.label(text, 16, (Color("#eaffdf") if kind == "primary" else UIKit.TEXT) if enabled else Color(UIKit.DIM, 0.6), "sans", 600)
	h.add_child(l)
	b.set_meta("label", l)
	b.add_child(h)
	return b

# ------------------------------------------------------------------ guida
func build_help() -> Control:
	var E: Dictionary = Data.ECON
	var v := UIKit.vbox(12)
	v.add_child(_title("COME SI GIOCA"))
	var cols := UIKit.hbox(30)
	var c1 := UIKit.vbox(4)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c2 := UIKit.vbox(4)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hsec(c1, "La schermata", "Il riquadro [b]ORDINI[/b] in basso dice sempre cosa fare adesso e mostra l'esito dell'ultima azione. Sul tabellone [b]pulsa[/b] ciò che puoi cliccare: [color=#7fe08f]verde[/color] dove schierare, [color=#ffc060]ambra[/color] da dove attaccare, [color=#ff8a6a]rosso[/color] i bersagli, [color=#8ad6ff]azzurro[/color] gli spostamenti. La barra a icone a [b]sinistra[/b] apre obiettivo, potenze, carte, mercato, continenti e registro; il pannello a [b]destra[/b] mostra il territorio selezionato con le schede Recluta / Edifici / Fortifica. Il [b]Tutorial[/b] del menu guida il primo turno.")
	_hsec(c1, "Obiettivo", "[b]Conquista mondiale[/b]: controlla il %d%% dei territori o elimina tutti gli avversari. [b]Obiettivo segreto[/b]: in più puoi vincere completando la tua missione (continenti, numero di territori o eliminare un rivale)." % int(round(E["victoryShare"] * 100)))
	var tr := int(main.game.truce_rounds) if (main.game != null and "truce_rounds" in main.game) else 2
	_hsec(c1, "Turni", "Il tabellone strategico si gioca [b]a turni[/b], come a Risiko: prima tu, poi ogni IA. Ogni turno ha tre fasi, indicate dalla barra in alto al centro:\n[b]1. Rifornimento[/b] — entrate e rinforzi del turno; recluti, costruisci, ricerchi, commerci, giochi le carte, assoldi mercenari, [b]schieri[/b] i rinforzi e [b]fortifichi[/b] (trincee, mine, bunker).\n[b]2. Attacco[/b] — al massimo [b]un attacco[/b] per turno da un tuo territorio a un nemico confinante (o via mare se hai un porto): scegli quante unità inviare (almeno una resta a casa) e se comandare la battaglia in 3D o risolverla in automatico.\n[b]3. Spostamento[/b] — [b]uno[/b] spostamento di truppe tra tuoi territori collegati, a qualunque distanza.\nIl [b]pulsante principale del riquadro ORDINI[/b] (in basso) passa alla fase successiva o chiude il turno ([b]Invio[/b] = fine turno). Nei turni delle IA le loro mosse sono animate sul tabellone; [b]Spazio[/b] accelera e, premuto di nuovo, salta l'animazione. Se un'IA ti attacca scegli se [b]difenderti in prima persona[/b] (3D) o con la risoluzione automatica.")
	_hsec(c1, "Il tabellone", "42 territori in 6 continenti. Ogni pedina mostra le unità presenti ([b]?[/b] = forze nascoste dell'Unione Libera in città). ★ = Quartier Generale. Le icone accanto alla pedina sono gli edifici. Anello ambra = costruzione, verde = reclutamento, cerchio arancio = territorio [b]senza rifornimenti[/b] (non collegato via terra al QG: produce e combatte peggio).")
	_hsec(c1, "Economia", "Ogni territorio produce denaro e manodopera più la sua risorsa specializzata (valori [b]per turno[/b] nella barra in alto); il QG produce al 100%, gli altri al 60%. I mezzi consumano petrolio: a petrolio zero le tue forze combattono peggio. A ogni tuo turno ricevi [b]rinforzi[/b] (circa metà dei tuoi territori, minimo 4, + bonus dei continenti posseduti) da schierare. Reclutare richiede [b]1–3 turni[/b] (fanteria 1, carri 2, caccia 3), gli edifici 1–3 turni. Il [b]Mercato internazionale[/b] (scheda Mercato nella barra a sinistra) vende o compra lotti di petrolio, acciaio e manodopera: il prezzo cala se vendi spesso e sale se compri.")
	_hsec(c1, "Regole del fronte", "[b]Tregua iniziale[/b]: nei primi %d turni si possono attaccare solo i territori neutrali (la barra mostra «Tregua: ancora N turni»). Ogni territorio rifornito arruola una [b]milizia[/b]; il QG è una roccaforte (difesa ×%s). Dopo una conquista le truppe si [b]riorganizzano[/b] per un turno (non possono ripartire) e il territorio resta [b]in occupazione[/b] per due turni. [b]Fortificazioni[/b] (pannello del territorio, fase di rifornimento): trincee (fanteria più resistente), campi minati (danni ai mezzi attaccanti), bunker (postazioni che sparano), ciascuna fino al livello 3; alla conquista trincee e mine si azzerano." % [tr, str(E["hqDef"])])
	_hsec(c1, "Edifici e tecnologia", "Caserma (fanteria), Fabbrica (carri, artiglieria, contraerea), Aeroporto (mezzi aerei e ponte aereo da %s), Porto (attacchi via mare), Fortificazioni (difesa +30%%), Impianto (produzione +60%%). Il QG vale come caserma e fabbrica. La ricerca (pulsante in alto) porta da [b]Tech 1 · Guerra Fredda[/b] a [b]%s[/b] in 2–4 turni: sblocca nuove unità e dà +%d%% di attacco per livello." % [UIKit.tech_name(2), UIKit.tech_name(4), int(round(Data.TECH_COMBAT_BONUS * 100))])
	_hsec(c1, "Come formare l'esercito", "• [b]Rinforzi gratis[/b] = [b]fanteria[/b] a ogni turno: ottima per [b]difendere[/b] (tiene boschi e città, letale contro i carri da vicino).
• Per [b]attaccare[/b] recluta [b]carri[/b] (sfondano in campo aperto) e [b]artiglieria[/b] (colpisce da lontano, ottima contro bunker) dove hai una [b]Fabbrica[/b] o nel [b]QG[/b]; elicotteri, caccia e droni dove hai un [b]Aeroporto[/b]. Le unità reclutate [b]nascono in quel territorio[/b].
• Un [b]esercito misto[/b] batte un esercito numeroso di un solo tipo: la fanteria tiene il terreno, i carri sfondano, l'artiglieria indebolisce, la contraerea protegge dagli aerei.
• La [b]ricerca[/b] è [b]globale[/b]: vale in tutti i tuoi territori, sblocca nuove unità e dà più attacco. Gli [b]edifici[/b] valgono solo dove li costruisci.
• Lo [b]spostamento[/b] non ha limiti di distanza: porta le truppe dove servono attraverso i tuoi territori collegati (uno per turno; con due aeroporti da Tech 2 anche per ponte aereo).")
	_hsec(c2, "Comandi", "• [b]Clic sinistro[/b]: seleziona un territorio\n• [b]Attacco[/b]: seleziona un tuo territorio (almeno 2 unità), poi clic su un bersaglio evidenziato: si apre il pannello d'attacco con i cursori per ogni tipo di unità e la previsione\n• [b]Spostamento[/b]: nella terza fase, tuo territorio → clic su un tuo territorio evidenziato → [b]Sposta[/b]\n• [b]Rinforzi[/b]: nel rifornimento lo schieramento è già attivo, clic su un tuo territorio verde (N attiva/disattiva)\n• [b]Carte[/b] (scheda nella barra a sinistra): seleziona un tris (tre uguali, tre diverse o con jolly) e scegli l'operazione: rinforzi, missile, sabotaggio o golpe\n• [b]Fase successiva[/b] / [b]Fine turno[/b] (Invio): pulsante principale del riquadro ORDINI\n• [b]Telecamera[/b]: WASD o bordi per spostarti, rotella per lo zoom, Q/E per ruotare\n• [b]Spazio[/b] nei turni IA: accelera, di nuovo per saltare · [b]Esc[/b] annulla / menu · [b]F1/H[/b] questo aiuto · [b]F5/F9[/b] salvataggio/caricamento rapido")
	_hsec(c2, "Battaglie", "Quando attacchi, o un'IA attacca te, puoi scegliere la [b]risoluzione automatica[/b] oppure [b]comandare la battaglia[/b] in tempo reale sul campo 3D, sia in attacco sia in [b]difesa[/b]. Terreno, fortificazioni, QG, tecnologia, rifornimenti, petrolio e [b]veterani[/b] influenzano lo scontro.\n[b]Il campo è grande[/b]: i carri colpiscono da centinaia di metri, l'artiglieria da un capo all'altro della mappa. Con la [b]rotella[/b] allontani la vista fino alla [b]vista d'insieme[/b]: i mezzi diventano [b]pedine[/b] con il simbolo del tipo e il numero di unità (le tue rettangolari, le nemiche con gli angoli smussati).\n[b]Vedere prima di sparare[/b]: vedi i nemici solo entro il raggio di vista delle tue unità; le zone non osservate sono più scure. Un nemico perso di vista lascia un [b]fantasma[/b] con «?» e da quanti secondi non lo vedi. «AVVISTATO» segnala un nemico appena scoperto (anche sulla minimappa).\n[b]Copertura[/b]: boschi e terreno accidentato danno copertura leggera, città e bunker pesante (passa il mouse sul terreno per saperlo). La [b]fanteria ferma al riparo resta nascosta[/b] finché non spara (icona a foglia sulle tue unità nascoste) ed è letale contro i carri da vicino. Il primo fuoco da posizione nascosta è un'[b]IMBOSCATA[/b]: danni ×2 per 4 s.\n[b]Corazza[/b]: i carri reggono di fronte ma subiscono ×1,6 sul [b]FIANCO[/b] e ×2,5 sul [b]RETRO[/b] (mezzi leggeri ×1,25 / ×1,5). Passando il mouse su un mezzo nemico vedi da che lato lo colpirebbero le tue unità selezionate: aggiralo.\n[b]Artiglieria[/b]: spara solo su nemici avvistati da qualcuno (o con il [b]fuoco d'area[/b], tasto [b]X[/b]); i colpi si disperdono di più a grande distanza; dopo ogni spostamento deve piazzarsi per qualche secondo e ha una gittata minima.\nSelezionando le unità vedi a terra la [b]gittata[/b] (linea piena), la [b]vista[/b] (tratteggio) e per l'artiglieria la [b]gittata minima[/b] (rosso).\nSul campo: prima lo [b]schieramento[/b] (clic destro nella tua zona, [b]Invio[/b] per iniziare; in difesa: fanteria nei boschi e in città, carri dietro i rilievi), poi [b]clic destro[/b] muovi/attacca · [b]G[/b] attacco in movimento · [b]H[/b] alt · [b]X[/b] fuoco d'area · [b]B[/b] sbarramento d'artiglieria · [b]Ctrl+A[/b] tutte le unità · [b]Ctrl+1..9[/b] gruppi · [b]C[/b] centra la selezione · [b]V[/b] vai all'allarme · [b]Home[/b] torna all'esercito · [b]WASD[/b]/[b]Q/E[/b] telecamera · [b]P/Spazio[/b] pausa · [b]Invio[/b] continua a fine battaglia.\n[b]Abilità[/b] (pulsanti in basso): [b]F[/b] cortina fumogena (meno danni dal fuoco diretto per alcuni secondi e più difficili da avvistare; poi ricarica) · [b]J[/b] supporto aereo (un caccia bombarda l'area indicata poco dopo la chiamata; una volta per battaglia) · [b]T[/b] mantieni posizione (i reparti restano fermi e sparano solo ai nemici a tiro; di nuovo T per sbloccarli).")
	var fz := ""
	for F in Data.FACTIONS:
		fz += "• [b][color=%s]%s[/color][/b] — %s: %s\n" % [F["color"], F["short"], F["doctrine"], UIKit.terms("; ".join(F["perks"]))]
	_hsec(c2, "Fazioni", fz.strip_edges())
	_hsec(c2, "Nebbia, veterani e diplomazia", "[b]Nebbia di guerra[/b] (si sceglie nella nuova campagna): vedi le forze solo nei tuoi territori e in quelli confinanti (l'AAN un anello in più col radar); altrove solo una stima [b]≈N[/b] o nulla, e la previsione d'attacco usa la stima. [b]Veterani[/b]: ogni vittoria dà esperienza al presidio vincitore, fino a ★★★ (+6%% per stella); le truppe portano le stelle con sé. [b]Diplomazia[/b]: nella scheda Potenze (barra a sinistra) proponi a un'IA un [b]patto di non aggressione[/b] per alcuni turni (accetta se non sei in testa e ha nemici più pericolosi); anche le IA in difficoltà possono proportelo. Durante il patto nessuno dei due può attaccare l'altro né colpirlo con le carte.")
	cols.add_child(c1)
	cols.add_child(c2)
	v.add_child(cols)
	v.add_child(_buttons([["Chiudi", "primary", "help-back"]]))
	return v

func _hsec(c: Control, title: String, text: String) -> void:
	c.add_child(UIKit.spacer(0, 4, false))
	c.add_child(UIKit.header(title))
	c.add_child(UIKit.rich(text, 14))

# ------------------------------------------------------------------ battaglia
func _side(P, f, label_t: String, idx: int, hh: int, vet: int = 0, fog_est: int = -2) -> Control:
	var col: Color = P["color"] if P != null else Color(Data.NEUTRAL_COLOR)
	var p := PanelContainer.new()
	var sb := UIKit.box(Color(col, 0.08), UIKit.LINE2, 1, 4, Vector4(14, 10, 14, 12))
	sb.border_width_top = 4
	sb.border_color = col
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(4)
	v.add_child(UIKit.label(label_t, 11, UIKit.DIM, "mono", 700))
	var nh := UIKit.hbox(6)
	nh.add_child(UIKit.swatch(col, 12))
	var nl := UIKit.label(P["name"] if P != null else "Neutrali", 15, UIKit.WHITE, "sans", 700)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(nl)
	if idx == hh and hh >= 0:
		nh.add_child(UIKit.tag("TU"))
	v.add_child(nh)
	var fh := UIKit.hbox(8)
	var fog := fog_est > -2
	var num := "?"
	if f != null and not fog:
		num = str(Data.total_units(f))
	elif fog and fog_est >= 0:
		num = "≈%d" % fog_est
	fh.add_child(UIKit.label(num, 34, UIKit.WHITE, "mono", 700))
	fh.add_child(UIKit.label("unità", 14, UIKit.DIM))
	if vet > 0 and not fog:
		fh.add_child(UIKit.spacer())
		fh.add_child(_vet_badge(vet))
	v.add_child(fh)
	if fog:
		var fl := UIKit.hbox(5)
		fl.add_child(UIKit.icon("fog", 15))
		fl.add_child(UIKit.label("stima nella nebbia" if fog_est >= 0 else "forze sconosciute (nebbia)", 12, Color("#b8c6d0")))
		v.add_child(fl)
	elif f == null:
		v.add_child(UIKit.label("forze nascoste", 12, UIKit.DIM))
	else:
		var g := HFlowContainer.new()
		g.add_theme_constant_override("h_separation", 10)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in Data.UNIT_KEYS:
			if int(f.get(k, 0)) > 0:
				var u := UIKit.hbox(3)
				u.add_child(UIKit.icon(k, 16))
				u.add_child(UIKit.label("%s %d" % [Data.UNITS[k]["short"], int(f[k])], 12, UIKit.TEXT, "mono", 600))
				g.add_child(u)
		v.add_child(g)
	p.add_child(v)
	return p

## Distintivo veterani: stelle + bonus.
func _vet_badge(n: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(1, 0.85, 0.3, 0.10), Color(1, 0.85, 0.3, 0.45), 1, 3, Vector4(6, 2, 7, 2)))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = "Veterani: +%d%% in combattimento" % (6 * n)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := UIKit.hbox(1)
	for i in n:
		h.add_child(UIKit.icon("star", 15))
	h.add_child(UIKit.spacer(4, 0, false))
	h.add_child(UIKit.label("+%d%%" % (6 * n), 12, Color("#ffe08a"), "mono", 700))
	p.add_child(h)
	return p

func build_battle_prompt(pb: Dictionary) -> Control:
	var g = main.game
	var hh: int = main.h()
	var t := int(pb["terr"])
	var T: Dictionary = Data.TERRITORIES[t]
	var st: Dictionary = g.terr[t]
	var att := int(pb["attacker"])
	var A: Dictionary = g.players[att]
	var di := int(st["owner"])
	var D = g.players[di] if di >= 0 else null
	var human_att := att == hh
	if pb.has("human_side"):
		human_att = String(pb["human_side"]) == "att"
	var tm: bool = main.turn_mode()
	var def_f = main.gcall("visible_forces", [hh, t], st["forces"]) if human_att else st["forces"]
	var def_vis: bool = (not human_att) or main.is_vis(t)
	var att_vet := clampi(int(pb.get("vet", 0)), 0, 3)
	var def_vet: int = main.vet_of(t)
	var v := UIKit.vbox(12)
	var th := UIKit.hbox(10)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("power" if human_att else "alert", 26))
	th.add_child(_title(("BATTAGLIA PER " if human_att else "ATTACCO NEMICO SU ") + String(T["name"]).to_upper(), UIKit.AMBER2 if human_att else Color("#ff9a7a"), 26))
	v.add_child(th)
	if not human_att and tm:
		var sub := _center_text("%s attacca da %s nel suo turno: scegli come difenderti." % [String(A["name"]), Data.TERRITORIES[int(pb.get("from", t))]["name"] if int(pb.get("from", -1)) >= 0 else "?"], 14, UIKit.TEXT)
		v.add_child(sub)
	var sides := UIKit.hbox(12)
	var att_est := -2
	var fr := int(pb.get("from", -1))
	if not human_att and main.fog_on() and fr >= 0 and not main.is_vis(fr):
		att_est = int(round(Data.total_units(pb["forces"]) / 5.0)) * 5
	sides.add_child(_side(A, pb["forces"], "ATTACCANTE" + (" (stima)" if att_est > -2 else ""), att, hh, att_vet, att_est))
	var vs := UIKit.label("VS", 24, UIKit.RED, "cond", 700)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sides.add_child(vs)
	sides.add_child(_side(D, def_f, "DIFENSORE", di, hh, def_vet, -2 if def_vis else main.estimate(t)))
	v.add_child(sides)
	var notes := [Data.TERRAINS[T["ter"]]["name"] + " (difesa ×%.2f)" % float(Data.TERRAINS[T["ter"]]["def"])]
	if st["buildings"].has("bunker"):
		notes.append("Fortificazioni sabotate" if float(st.get("sabotage", 0)) > 0 else "Fortificazioni")
	if D != null and int(D["hq"]) == t:
		notes.append("Quartier generale")
	if pb.get("sea", false):
		notes.append("Sbarco dal mare")
	v.add_child(_center_text(" · ".join(notes), 14, UIKit.DIM))
	if tm:
		var fh := CenterContainer.new()
		fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fh.add_child(fort_row(t, def_vis))
		v.add_child(fh)
	# previsione (Combat.predict_battle + combat_mods)
	var pred: Control = null
	if not def_vis:
		pred = _intel_box(main.estimate(t))
	elif def_f != null and main._combat_script != null:
		var ma = main.combat_mods(att, "att", t, {"fromIdx": pb.get("from", -1), "from_idx": pb.get("from", -1), "sea": pb.get("sea", false), "manual": false, "vet": att_vet})
		var md = main.combat_mods(di, "def", t, {"manual": false, "vet": def_vet})
		var pr = main.predict(pb["forces"], def_f, ma, md)
		if pr != null:
			var att_wins: bool = pr.get("winner", "def") == "att"
			var human_wins: bool = att_wins == human_att
			var left_k: float = float(pr.get("attLeft", pr.get("att_left", 0))) if att_wins else float(pr.get("defLeft", pr.get("def_left", 0)))
			var col := UIKit.GREEN if human_wins else UIKit.RED
			var pp := PanelContainer.new()
			pp.add_theme_stylebox_override("panel", UIKit.box(Color(col, 0.08), Color(col, 0.45), 1, 4, Vector4(12, 8, 12, 8)))
			pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pv := UIKit.vbox(3)
			var l1 := UIKit.label("Previsione: " + ("VITTORIA PROBABILE" if human_wins else "SCONFITTA PROBABILE"), 17, col, "mono", 700)
			l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pv.add_child(l1)
			pv.add_child(_center_text("al vincitore resterebbe ≈%d%% delle forze" % int(round(100.0 * left_k)), 13, UIKit.DIM))
			var ma_atk := float(ma.get("atk", 1.0)) if ma is Dictionary else 1.0
			var md_atk := float(md.get("atk", 1.0)) if md is Dictionary else 1.0
			pv.add_child(_center_text("Modificatori att. ×%.2f · dif. ×%.2f" % [ma_atk, md_atk], 12, UIKit.DIM))
			pp.add_child(pv)
			pred = pp
	elif def_f == null:
		pred = _center_text("Forze nemiche sconosciute: nessuna previsione disponibile.", 14, UIKit.DIM)
	if pred != null:
		v.add_child(pred)
	var can_manual: bool = main.can_manual_battle()
	var no3d := "Modulo battaglia 3D non ancora disponibile"
	if human_att:
		v.add_child(_buttons([
			["⚙  Attacca: risoluzione automatica", "normal", "bp-auto", "Esito calcolato immediatamente"],
			["⚔  Attacca: comando diretto (3D)", "primary", "bp-manual", "Comanda le truppe in tempo reale sul campo 3D (+10%)" if can_manual else no3d, can_manual]]))
	else:
		v.add_child(_buttons([
			["⚙  Risoluzione automatica", "normal", "bp-auto", "Esito calcolato immediatamente"],
			["⚔  Difendi in prima persona (3D)", "primary", "bp-manual", "Schieri per primo i difensori sul campo 3D e comandi la difesa (+10%)" if can_manual else no3d, can_manual]]))
	return v

func _intel_box(est: int) -> Control:
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", UIKit.box(Color(0.55, 0.65, 0.72, 0.08), Color(0.6, 0.7, 0.78, 0.4), 1, 4, Vector4(12, 8, 12, 8)))
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv := UIKit.vbox(3)
	var th := UIKit.hbox(8)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("fog", 20))
	th.add_child(UIKit.label("INTELLIGENCE INSUFFICIENTE", 17, Color("#d0dce4"), "mono", 700))
	pv.add_child(th)
	pv.add_child(_center_text("Il difensore è nella nebbia di guerra: nessuna previsione disponibile" + ((" (forze stimate ≈%d)." % est) if est >= 0 else "."), 13, UIKit.DIM))
	pp.add_child(pv)
	return pp

# ------------------------------------------------------------------ pannello attacco / spostamento (FASE 6)
var _fp := {}   # stato del pannello forze: sliders, etichette, previsione

## Livelli di fortificazione come piccoli distintivi (icona + tacche 0..3).
func fort_row(t: int, known: bool = true, sz: int = 13) -> Control:
	var h := UIKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv: Dictionary = main.fort_levels(t)
	for k in main.FORT_KINDS:
		var n := int(lv[k])
		var b := UIKit.hbox(4)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.tooltip_text = "%s: livello %s — %s" % [main.fort_name(k), str(n) if known else "?", main.FORT_INFO[k]["desc"]]
		var ic := UIKit.icon(k, sz + 3)
		if known and n == 0:
			ic.modulate.a = 0.35
		b.add_child(ic)
		b.add_child(UIKit.label(main.fort_name(k), sz - 1, UIKit.TEXT if (n > 0 or not known) else UIKit.DIM))
		b.add_child(UIKit.label(_pips(n) if known else "?", sz, UIKit.AMBER2 if n > 0 else UIKit.DIM, "mono", 700))
		h.add_child(b)
	return h

static func _pips(n: int) -> String:
	return "■".repeat(clampi(n, 0, 3)) + "□".repeat(3 - clampi(n, 0, 3))

func build_force_panel(kind: String, from: int, to: int) -> Control:
	var g = main.game
	var hh: int = main.h()
	var atk := kind == "attack"
	var TF: Dictionary = Data.TERRITORIES[from]
	var TT: Dictionary = Data.TERRITORIES[to]
	var src: Dictionary = g.terr[from]["forces"]
	var tot := Data.total_units(src)
	_fp = {"kind": kind, "from": from, "to": to, "tot": tot, "sliders": {}, "vals": {}}
	var v := UIKit.vbox(12)
	v.set_meta("modal_width", 900)
	var k0 := UIKit.label(("ORDINE D'ATTACCO · TURNO %d" if atk else "ORDINE DI SPOSTAMENTO · TURNO %d") % main.round_n(), 12, UIKit.AMBER, "mono", 700)
	k0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k0)
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.label(String(TF["name"]).to_upper(), 26, UIKit.WHITE, "cond", 700))
	th.add_child(UIKit.icon("attack" if atk else "move", 26))
	th.add_child(UIKit.label(String(TT["name"]).to_upper(), 26, UIKit.AMBER2 if atk else Color("#8ad6ff"), "cond", 700))
	v.add_child(th)
	var cols := UIKit.hbox(18)
	# --- colonna sinistra: forze da inviare
	var lc := UIKit.vbox(6)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.custom_minimum_size.x = 430
	lc.add_child(UIKit.header("Forze da inviare", "ne resta almeno 1 a presidio"))
	var sel: Dictionary = main._force_sel
	for k in Data.UNIT_KEYS:
		var n := int(src.get(k, 0))
		if n <= 0:
			continue
		var row := UIKit.hbox(8)
		row.add_child(UIKit.icon(k, 20))
		var nl := UIKit.label(Data.UNITS[k]["name"], 14, UIKit.WHITE, "sans", 600)
		nl.custom_minimum_size.x = 120
		row.add_child(nl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = n
		sl.step = 1
		sl.value = int(sel.get(k, 0))
		sl.custom_minimum_size = Vector2(170, 22)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sl.name = "S_" + k
		row.add_child(sl)
		var vl := UIKit.label("", 15, UIKit.AMBER2, "mono", 700)
		vl.custom_minimum_size.x = 64
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		_fp["sliders"][k] = sl
		_fp["vals"][k] = vl
		sl.value_changed.connect(func(x: float): _fp_changed(k, int(x)))
		lc.add_child(row)
	var qh := UIKit.hbox(6)
	qh.add_child(UIKit.label("Rapidi:", 12, UIKit.DIM))
	for it in [["Tutto", 1.0], ["Metà", 0.5], ["Un quarto", 0.25]]:
		var frac: float = it[1]
		qh.add_child(UIKit.button(it[0], "normal", "xs", func(): _fp_fill(frac)))
	lc.add_child(qh)
	var tl := UIKit.label("", 14, UIKit.TEXT, "mono", 600)
	_fp["total"] = tl
	lc.add_child(tl)
	cols.add_child(lc)
	# --- colonna destra: bersaglio
	var rc := UIKit.vbox(8)
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.custom_minimum_size.x = 360
	var o := int(g.terr[to]["owner"])
	var O = g.players[o] if o >= 0 else null
	var vis: bool = main.is_vis(to)
	if atk:
		var df = main.gcall("visible_forces", [hh, to], g.terr[to]["forces"])
		rc.add_child(_side(O, df, "DIFENSORE", o, hh, main.vet_of(to) if vis else 0, -2 if vis else main.estimate(to)))
		var notes := [String(Data.TERRAINS[TT["ter"]]["name"]) + " (difesa ×%.2f)" % float(Data.TERRAINS[TT["ter"]]["def"])]
		if O != null and int(O["hq"]) == to:
			notes.append("Quartier generale")
		if vis and g.terr[to]["buildings"].has("bunker"):
			notes.append("edificio Fortificazioni")
		var sea := false
		for x in main.targets:
			if int(x["idx"]) == to and bool(x.get("sea", false)):
				sea = true
		if sea:
			notes.append("sbarco dal mare")
		var nl2 := UIKit.label(" · ".join(notes), 13, UIKit.DIM)
		nl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rc.add_child(nl2)
		rc.add_child(UIKit.header("Fortificazioni del difensore", "" if vis else "nella nebbia"))
		rc.add_child(fort_row(to, vis))
		var pp := PanelContainer.new()
		_fp["pred_p"] = pp
		var pv := UIKit.vbox(2)
		var p1 := UIKit.label("", 16, UIKit.WHITE, "mono", 700)
		p1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var p2 := UIKit.label("", 12, UIKit.DIM)
		p2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(p1)
		pv.add_child(p2)
		pp.add_child(pv)
		_fp["pred1"] = p1
		_fp["pred2"] = p2
		rc.add_child(pp)
		var ch := UIKit.rich("", 14, Color("#e2e9e3"))
		ch.custom_minimum_size.x = 340
		_fp["comp"] = ch
		rc.add_child(ch)
	else:
		var P: Dictionary = g.players[hh]
		rc.add_child(_side(P, g.terr[to]["forces"], "DESTINAZIONE", hh, hh, main.vet_of(to)))
		var hint := UIKit.label("Le truppe arrivano subito. Dopo lo spostamento non si può più attaccare in questo turno.", 13, UIKit.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rc.add_child(hint)
		if main.vet_of(from) != main.vet_of(to):
			var vh := UIKit.label("Veterani: le stelle si fondono in media pesata per unità.", 12, Color("#ffe08a"))
			vh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rc.add_child(vh)
	cols.add_child(rc)
	v.add_child(cols)
	var bh := UIKit.hbox(12)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	if atk:
		var can3d: bool = main.can_manual_battle()
		var bm := UIKit.button("⚔  Attacca: comando diretto (3D)", "primary", "big", func(): main.act("atk-manual"), "Comanda le truppe sul campo 3D in tempo reale (+10%)" if can3d else "Modulo battaglia 3D non disponibile")
		bm.disabled = not can3d
		bh.add_child(bm)
		bh.add_child(UIKit.button("⚙  Attacca: risoluzione automatica", "normal", "big", func(): main.act("atk-auto"), "Esito calcolato subito con la simulazione"))
		_fp["go"] = [bm, bh.get_child(1)]
	else:
		var bs := UIKit.button("➜  Sposta", "primary", "big", func(): main.act("mv-go"), "Trasferisci le unità scelte")
		bs.custom_minimum_size.x = 200
		bh.add_child(bs)
		_fp["go"] = [bs]
	bh.add_child(UIKit.button("Annulla", "ghost", "big", func(): main.act("force-cancel"), "Esc"))
	v.add_child(bh)
	_fp_refresh()
	return v

func _fp_changed(k: String, n: int) -> void:
	var tot := int(_fp["tot"])
	var sum := 0
	for kk in _fp["sliders"]:
		sum += n if kk == k else int(main._force_sel.get(kk, 0))
	if sum > tot - 1:
		n -= sum - (tot - 1)
		(_fp["sliders"][k] as HSlider).set_value_no_signal(n)
	main.set_force(k, n)
	_fp_refresh()

func _fp_fill(frac: float) -> void:
	var g = main.game
	var src: Dictionary = g.terr[int(_fp["from"])]["forces"]
	var mv: Dictionary = main.movable_forces(int(_fp["from"]))
	for k in _fp["sliders"]:
		var n := int(mv.get(k, 0)) if frac >= 1.0 else int(floor(int(src.get(k, 0)) * frac))
		n = mini(n, int(mv.get(k, 0)))
		main.set_force(k, n)
		(_fp["sliders"][k] as HSlider).set_value_no_signal(n)
	if Data.total_units(main._force_sel) == 0:
		for k in _fp["sliders"]:
			if int(mv.get(k, 0)) > 0:
				main.set_force(k, 1)
				(_fp["sliders"][k] as HSlider).set_value_no_signal(1)
				break
	_fp_refresh()

func _fp_refresh() -> void:
	var g = main.game
	var src: Dictionary = g.terr[int(_fp["from"])]["forces"]
	var f: Dictionary = main._force_sel
	for k in _fp["vals"]:
		(_fp["vals"][k] as Label).text = "%d/%d" % [int(f.get(k, 0)), int(src.get(k, 0))]
	var n := Data.total_units(f)
	(_fp["total"] as Label).text = "Invii %d unità · restano %d a %s" % [n, int(_fp["tot"]) - n, Data.TERRITORIES[int(_fp["from"])]["name"]]
	for b in _fp["go"]:
		if b is Button and n <= 0:
			b.disabled = true
		elif b is Button and not (b.text.find("3D") >= 0 and not main.can_manual_battle()):
			b.disabled = false
	if _fp["kind"] != "attack":
		return
	var pr = main.predict_attack(int(_fp["from"]), int(_fp["to"]), f)
	var p1: Label = _fp["pred1"]
	var p2: Label = _fp["pred2"]
	var pp: PanelContainer = _fp["pred_p"]
	var fog: bool = not main.is_vis(int(_fp["to"]))
	if n <= 0:
		pr = null
	if pr == null:
		p1.text = "Previsione non disponibile"
		p1.add_theme_color_override("font_color", Color("#d0dce4"))
		p2.text = "Scegli le forze da inviare" if n <= 0 else "Forze del difensore sconosciute (nebbia di guerra)"
		pp.add_theme_stylebox_override("panel", UIKit.box(Color(0.55, 0.65, 0.72, 0.08), Color(0.6, 0.7, 0.78, 0.4), 1, 4, Vector4(12, 8, 12, 8)))
		if _fp.has("comp"):
			(_fp["comp"] as RichTextLabel).visible = false
		return
	var win: bool = String(pr.get("winner", "def")) == "att"
	var left := float(pr.get("attLeft", pr.get("att_left", 0.0))) if win else float(pr.get("defLeft", pr.get("def_left", 0.0)))
	var pct := left * 100.0 if left <= 1.0 else 100.0 * left / maxf(1.0, n)
	var col := UIKit.GREEN if win else UIKit.RED
	var close := pct < 25.0
	if win and close:
		col = UIKit.AMBER2
	p1.text = ("VITTORIA PROBABILE" if not close else "VITTORIA DI MISURA") if win else "SCONFITTA PROBABILE"
	if fog:
		p1.text += " (stima)"
	p1.add_theme_color_override("font_color", col)
	if win:
		p2.text = "ti resterebbe ≈%d%% delle forze inviate (≈%d unità)" % [int(round(pct)), int(round(n * pct / 100.0))]
	else:
		p2.text = "al difensore resterebbe ≈%d%% delle forze; i tuoi superstiti tornano a %s" % [int(round(pct)), Data.TERRITORIES[int(_fp["from"])]["name"]]
	if fog:
		p2.text += " · difensore nella nebbia: previsione sulle forze stimate"
	pp.add_theme_stylebox_override("panel", UIKit.box(Color(col, 0.08), Color(col, 0.45), 1, 4, Vector4(12, 8, 12, 8)))
	# consigli sulla composizione (ruoli delle unità + previsione con tutte le forze disponibili)
	var hints := comp_hints(int(_fp["from"]), int(_fp["to"]), f)
	if not win:
		var mv: Dictionary = main.movable_forces(int(_fp["from"]))
		if Data.total_units(mv) > n:
			var pa = main.predict_attack(int(_fp["from"]), int(_fp["to"]), mv)
			if pa is Dictionary and String(pa.get("winner", "def")) == "att":
				hints.push_front("[color=#7fe08f]Con tutte le unità disponibili (pulsante «Tutto») la previsione diventa favorevole.[/color]")
			else:
				hints.push_front("[color=#ffb59a]Anche con tutte le unità disponibili la previsione resta sfavorevole: rinforza prima questo territorio.[/color]")
	if _fp.has("comp"):
		var lines := []
		for x in hints:
			lines.append("• " + String(x))
		(_fp["comp"] as RichTextLabel).text = "
".join(lines)
		(_fp["comp"] as RichTextLabel).visible = not lines.is_empty()

## Consigli sulla composizione dell'attacco (ruoli delle unità contro terreno, difese e forze visibili del difensore).
func comp_hints(from: int, to: int, f: Dictionary) -> Array:
	var g = main.game
	var out := []
	var n := Data.total_units(f)
	if n <= 0 or g == null:
		return out
	var ter := String(Data.TERRITORIES[to]["ter"])
	var tname := String(Data.TERRAINS[ter]["name"]).to_lower()
	var vis: bool = main.is_vis(to)
	var df = main.gcall("visible_forces", [main.h(), to], null) if vis else null
	var types := []
	for k in Data.UNIT_KEYS:
		if int(f.get(k, 0)) > 0:
			types.append(k)
	var fort := 0
	if vis:
		var lv: Dictionary = main.fort_levels(to)
		for k in lv:
			fort += int(lv[k])
	var o := int(g.terr[to]["owner"])
	var hq: bool = o >= 0 and int(g.players[o]["hq"]) == to
	var bunker: bool = vis and g.terr[to]["buildings"].has("bunker")
	var closed := ter in ["urbano", "foresta", "montagna"]
	var where := {"urbano": "in città", "foresta": "nei boschi", "montagna": "in montagna"}
	var warn := "[color=#ffc060]%s[/color]"
	if types == ["inf"]:
		if closed or fort > 0 or hq or bunker:
			out.append(warn % ("Solo fanteria contro un nemico %s: rischioso. Carri e artiglieria aiutano a sfondare." % (where.get(ter, "fortificato") if closed else ("nel QG" if hq else "fortificato"))))
		elif df is Dictionary and int(df.get("tank", 0)) > 0:
			out.append(warn % "Solo fanteria contro carri in campo aperto: rischioso.")
	if int(f.get("tank", 0)) > 0 and int(f.get("inf", 0)) == 0 and closed:
		out.append(warn % ("Carri senza fanteria %s: vulnerabili da vicino. Aggiungi fanteria." % where.get(ter, "")))
	if (fort > 0 or bunker or hq) and int(f.get("art", 0)) == 0 and int(f.get("jet", 0)) == 0:
		out.append(("QG fortificato" if hq and fort == 0 and not bunker else "Difese fortificate") + ": l'[b]artiglieria[/b] (o i caccia) è la più efficace contro trincee e bunker.")
	if df is Dictionary and int(df.get("heli", 0)) + int(df.get("jet", 0)) + int(df.get("drone", 0)) > 0 and int(f.get("aa", 0)) + int(f.get("jet", 0)) == 0:
		out.append(warn % "Il difensore ha mezzi aerei: porta contraerea o caccia.")
	if types == ["art"]:
		out.append(warn % "Artiglieria da sola: serve qualcuno che avvisti e tenga il terreno.")
	if types.size() == 1 and n >= 4 and out.is_empty():
		out.append("Esercito di un solo tipo: un mix (fanteria + carri + artiglieria) rende di più.")
	if types.size() >= 3:
		out.append("[color=#7fe08f]Esercito misto: ogni tipo copre i punti deboli degli altri.[/color]")
	elif not closed and int(f.get("tank", 0)) > 0 and fort == 0 and out.is_empty():
		out.append("Campo aperto (%s): terreno ideale per i carri." % tname)
	return out

# ------------------------------------------------------------------ offerta di patto da un'IA
var _pact_cd: Label = null
var _pact_bar: ProgressBar = null
var _pact_total := 30.0

func build_pact_offer(from: int, secs: float) -> Control:
	var g = main.game
	var P: Dictionary = g.players[from]
	var col: Color = P["color"]
	_pact_total = secs
	var v := UIKit.vbox(12)
	var th := UIKit.hbox(10)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("pact", 28))
	th.add_child(_title("PROPOSTA DI PATTO", UIKit.AMBER2, 26))
	v.add_child(th)
	var card := PanelContainer.new()
	var sb := UIKit.box(Color(col, 0.08), UIKit.LINE2, 1, 4, Vector4(16, 12, 16, 12))
	sb.border_width_left = 5
	sb.border_color = col
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := UIKit.vbox(6)
	var nh := UIKit.hbox(8)
	nh.add_child(UIKit.swatch(col, 14))
	nh.add_child(UIKit.label(String(P["name"]), 19, UIKit.WHITE, "sans", 700))
	nh.add_child(UIKit.tag("IA", Color(0.59, 0.75, 0.63, 0.25), UIKit.TEXT))
	cv.add_child(nh)
	var msg := UIKit.label("«Proponiamo un patto di non aggressione" + (" per alcuni turni." if main.turn_mode() else " di 5 minuti.") + " Le nostre forze non varcheranno i vostri confini, se voi non varcherete i nostri.»", 15, Color("#f0ead8"))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(msg)
	var n_terr: int = (main.gcall("territories_of", [from], []) as Array).size()
	var mine: int = (main.gcall("territories_of", [main.h()], []) as Array).size()
	cv.add_child(UIKit.label("%s controlla %d territori (tu %d) · QG: %s · Tech %d" % [P["fac"]["short"], n_terr, mine, Data.TERRITORIES[P["hq"]]["name"] if int(P["hq"]) >= 0 else "—", int(P["tech"])], 12, UIKit.DIM))
	card.add_child(cv)
	v.add_child(card)
	v.add_child(_center_text(("Se accetti, per alcuni turni" if main.turn_mode() else "Se accetti, per 5 minuti") + " nessuno dei due potrà attaccare l'altro né colpirlo con le carte comando.", 13, UIKit.DIM))
	var cd := UIKit.hbox(8)
	cd.alignment = BoxContainer.ALIGNMENT_CENTER
	cd.add_child(UIKit.icon("clock", 15))
	_pact_cd = UIKit.label("", 13, UIKit.AMBER2, "mono", 700)
	cd.add_child(_pact_cd)
	v.add_child(cd)
	_pact_bar = UIKit.progress(100, UIKit.AMBER, 4)
	v.add_child(_pact_bar)
	update_pact_countdown(secs)
	v.add_child(_buttons([["✕  Rifiuta", "normal", "pact-no", "Nessun patto: la guerra continua"], ["✓  Accetta il patto", "primary", "pact-yes", "Patto di non aggressione"]]))
	return v

func update_pact_countdown(left: float) -> void:
	if _pact_cd == null or not is_instance_valid(_pact_cd):
		return
	_pact_cd.text = "L'offerta scade tra %d s (partita in pausa)" % int(ceil(maxf(0.0, left)))
	if _pact_bar != null and is_instance_valid(_pact_bar):
		_pact_bar.value = 100.0 * clampf(left / maxf(0.1, _pact_total), 0.0, 1.0)

# ------------------------------------------------------------------ riepilogo battaglia
func build_summary(setup: Dictionary, res: Dictionary) -> Control:
	var g = main.game
	var hh: int = main.h()
	var t := int(setup["terrIdx"])
	var owner := int(g.terr[t]["owner"])
	var att_won: bool = owner == int(setup["att"]["player"])
	var human_att: bool = int(setup["att"]["player"]) == hh
	var human_won: bool = att_won == human_att
	var a0 := Data.total_units(setup["att"]["forces"])
	var d0 := Data.total_units(setup["def"]["forces"])
	var surv := Data.total_units(g.terr[t]["forces"])
	var v := UIKit.vbox(12)
	v.add_child(_title(("VITTORIA" if human_won else "SCONFITTA") + " — " + String(setup["terrName"]), UIKit.GREEN if human_won else UIKit.RED))
	var msg := ""
	if res.get("retreated", false):
		msg = "L'attaccante si è ritirato: i superstiti tornano alla base."
	elif att_won:
		msg = String(setup["att"]["name"]) + " conquista il territorio."
	else:
		msg = String(setup["def"]["name"]) + " mantiene il territorio."
	v.add_child(_center_text(msg, 16))
	var stats := UIKit.hbox(24)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	for it in [["Attaccante", a0], ["Difensore", d0], ["Presidio attuale", surv]]:
		var sv := UIKit.vbox(0)
		var n := UIKit.label(str(it[1]), 30, UIKit.WHITE, "mono", 700)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(n)
		var l := UIKit.label(String(it[0]).to_upper(), 11, UIKit.DIM, "mono", 700)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(l)
		stats.add_child(sv)
	v.add_child(stats)
	var av := clampi(int(setup["att"].get("vet", 0)), 0, 3)
	var dv := clampi(int(setup["def"].get("vet", 0)), 0, 3)
	var nv: int = main.vet_of(t)
	var vets := []
	if av > 0:
		vets.append("attaccante %s" % main.stars(av))
	if dv > 0:
		vets.append("difensore %s" % main.stars(dv))
	if vets.size() or nv > 0:
		var vh := UIKit.hbox(8)
		vh.alignment = BoxContainer.ALIGNMENT_CENTER
		vh.add_child(UIKit.icon("vet", 16))
		var txt := ("Veterani in campo: " + ", ".join(vets)) if vets.size() else "Nessun veterano in campo"
		vh.add_child(UIKit.label(txt, 13, Color("#ffe08a"), "sans", 600))
		if nv > 0:
			vh.add_child(UIKit.label("·  presidio ora", 13, UIKit.DIM))
			vh.add_child(_vet_badge(nv))
		v.add_child(vh)
	v.add_child(_buttons([["Torna alla mappa", "primary", "modal-close"]]))
	return v

# ------------------------------------------------------------------ fine partita
const STAT_NAMES := {"conquered": "Conquiste", "lost": "Terr. persi", "battlesWon": "Battaglie vinte", "battlesLost": "Battaglie perse",
	"killed": "Unità distrutte", "unitsLost": "Unità perse", "recruited": "Reclutate", "built": "Edifici", "spent": "Spesa",
	"cards": "Carte", "missiles": "Missili", "peak_terr": "Picco terr.", "peakTerr": "Picco terr.", "income": "Reddito",
	"research": "Ricerche", "manual": "Battaglie comandate", "trades": "Scambi", "damage": "Danni"}
const STAT_SKIP := ["idx", "player", "faction", "conquered", "lost", "battlesWon", "battlesLost", "battles_won", "battles_lost",
	"killed", "unitsLost", "units_lost", "terr", "territories", "alive"]

func _summary_players() -> Array:
	var sm = main.gcall("stats_summary", [], null)
	if sm is Dictionary and sm.get("players") is Array:
		return sm["players"]
	return []

func _stats_table() -> Control:
	var g = main.game
	var sp := _summary_players()
	var rich: bool = sp.size() == g.players.size()
	var grid := GridContainer.new()
	var heads := ["FAZIONE", "TERRITORI", "CONQUISTE", "PERSI", "BATTAGLIE V/S", "DISTRUTTE", "PERSE"]
	if rich:
		heads = ["FAZIONE", "TERRITORI", "PICCO", "CONQUISTE", "PERSI", "BATTAGLIE V/S", "DISTRUTTE", "PERSE", "EDIFICI", "TECH", "CARTE"]
	grid.columns = heads.size()
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 7)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for hd in heads:
		grid.add_child(UIKit.label(hd, 11, UIKit.AMBER, "mono", 700))
	for P in g.players:
		var me: bool = int(P["idx"]) == main.h()
		var col := UIKit.AMBER2 if me else UIKit.TEXT
		var s: Dictionary = P.get("stats", {})
		var fh := UIKit.hbox(6)
		fh.add_child(UIKit.swatch(P["color"], 11))
		fh.add_child(UIKit.label(String(P["fac"]["short"]) + ("" if P["alive"] else " ✝"), 14, col, "mono", 700))
		if me:
			fh.add_child(UIKit.tag("TU"))
		grid.add_child(fh)
		var vals := []
		if rich:
			var e: Dictionary = sp[int(P["idx"])]
			vals = [e.get("territories", 0), e.get("max_territories", 0), e.get("conquered", 0), e.get("lost", 0),
				"%d/%d" % [int(e.get("battles_won", 0)), int(e.get("battles_lost", 0))], e.get("units_killed", 0), e.get("units_lost", 0),
				e.get("buildings", 0), e.get("tech", 0), e.get("cards_played", 0)]
		else:
			var cnt: int = (main.gcall("territories_of", [P["idx"]], []) as Array).size()
			vals = [cnt, s.get("conquered", 0), s.get("lost", 0),
				"%d/%d" % [int(s.get("battlesWon", s.get("battles_won", 0))), int(s.get("battlesLost", s.get("battles_lost", 0)))],
				s.get("killed", 0), s.get("unitsLost", s.get("units_lost", 0))]
		for x in vals:
			grid.add_child(UIKit.label(str(int(x)) if (x is float) else str(x), 14, col, "mono"))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.25), UIKit.LINE, 1, 4, Vector4(18, 12, 18, 12)))
	p.add_child(grid)
	cc.add_child(p)
	return cc

## Grafici dell'andamento (territori, potenza, unità, reddito) dalla cronologia della partita.
func _charts() -> Control:
	var g = main.game
	var hist: Array = main.get_history()
	var v := UIKit.vbox(6)
	var top := UIKit.hbox(4)
	top.add_child(UIKit.icon("chart", 18))
	top.add_child(UIKit.label("ANDAMENTO DELLA GUERRA", 13, UIKit.AMBER, "mono", 700))
	top.add_child(UIKit.spacer())
	var chart = load("res://scripts/ui/chart.gd").new()
	chart.custom_minimum_size = Vector2(0, 270)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm: bool = main.turn_mode()
	chart.x_turns = tm
	var metrics := [["terr", "Territori"], ["power", "Potenza"], ["units", "Unità"], ["income", "Reddito $/turno" if tm else "Reddito $/min"]]
	var btns := []
	var show := func(key: String):
		var series := []
		for P in g.players:
			var pts := PackedVector2Array()
			for snap in hist:
				var arr = snap.get(key, [])
				if arr is Array and int(P["idx"]) < arr.size():
					var xx := float(snap.get("round", snap.get("t", 0))) if tm else float(snap.get("t", 0))
					pts.append(Vector2(xx, float(arr[int(P["idx"])]) * (60.0 if key == "income" and not tm else 1.0)))
			series.append({"name": P["fac"]["short"], "color": P["color"], "points": pts})
		chart.set_data(series)
		for b in btns:
			b.set_pressed_no_signal(b.get_meta("k") == key)
	for m in metrics:
		var b := UIKit.button(m[1], "normal", "sm", Callable())
		b.toggle_mode = true
		b.custom_minimum_size.x = 84
		b.set_meta("k", m[0])
		b.pressed.connect(func(): Sfx.play("click"); show.call(m[0]))
		btns.append(b)
		top.add_child(b)
	v.add_child(top)
	v.add_child(chart)
	var leg := UIKit.hbox(18)
	leg.alignment = BoxContainer.ALIGNMENT_CENTER
	for P in g.players:
		var lh := UIKit.hbox(6)
		var sw := ColorRect.new()
		sw.color = P["color"]
		sw.custom_minimum_size = Vector2(18, 3)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lh.add_child(sw)
		lh.add_child(UIKit.label(String(P["name"]), 12, UIKit.TEXT if P["alive"] else UIKit.DIM))
		leg.add_child(lh)
	v.add_child(leg)
	show.call("terr")
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.22), UIKit.LINE, 1, 4, Vector4(14, 10, 14, 10)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return p

## Riquadri con i numeri chiave del giocatore (o del vincitore in modalità spettatore).
func _highlights(P: Dictionary) -> Control:
	var s: Dictionary = P.get("stats", {})
	var hist: Array = main.get_history()
	var peak := 0
	for snap in hist:
		var arr = snap.get("terr", [])
		if arr is Array and int(P["idx"]) < arr.size():
			peak = maxi(peak, int(arr[int(P["idx"])]))
	var cnt := (main.gcall("territories_of", [P["idx"]], []) as Array).size()
	peak = maxi(peak, cnt)
	var h := UIKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var items := [
		["terr", str(cnt), "territori finali"],
		["globe", str(peak), "picco territori"],
		["power", str(int(s.get("battlesWon", s.get("battles_won", 0)))), "battaglie vinte"],
		["target", str(int(s.get("killed", 0))), "nemici distrutti"],
		["skull", str(int(s.get("unitsLost", s.get("units_lost", 0)))), "unità perse"],
		["turn", "%d" % main.round_n(), "turni"] if main.turn_mode() else ["clock", UIKit.fmt_time(main.game.time), "durata"],
	]
	for it in items:
		var p := PanelContainer.new()
		var sb := UIKit.box(Color(1, 1, 1, 0.03), UIKit.LINE, 1, 4, Vector4(12, 8, 12, 8))
		sb.border_width_top = 2
		sb.border_color = Color(P["color"], 0.8)
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size.x = 160
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UIKit.vbox(0)
		var r := UIKit.hbox(8)
		r.add_child(UIKit.icon(it[0], 18))
		r.add_child(UIKit.label(it[1], 26, UIKit.WHITE, "mono", 700))
		v.add_child(r)
		v.add_child(UIKit.label(it[2], 12, UIKit.DIM))
		p.add_child(v)
		h.add_child(p)
	return h

# ------------------------------------------------------------------ scenari
## Briefing d'avvio di uno scenario: nome, situazione, obiettivo, fazione, durata.
func build_briefing(S: Dictionary) -> Control:
	var M = main.menu
	var v := UIKit.vbox(10)
	v.set_meta("modal_width", 760)
	var k := UIKit.label("BRIEFING DELL'OPERAZIONE", 12, UIKit.AMBER, "mono", 700)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("flag", 30, UIKit.AMBER2))
	th.add_child(_title(String(S.get("name", "Scenario")).to_upper(), UIKit.AMBER2, 38))
	v.add_child(th)
	var hh: int = main.h()
	if hh >= 0:
		var P: Dictionary = main.game.players[hh]
		var ph := UIKit.hbox(8)
		ph.alignment = BoxContainer.ALIGNMENT_CENTER
		ph.add_child(UIKit.swatch(P["color"], 12))
		ph.add_child(UIKit.label("Comandi: " + String(P["name"]), 15, UIKit.WHITE, "sans", 700))
		v.add_child(ph)
	var d := UIKit.rich(String(M.sf(S, ["desc", "description"], "")), 15)
	d.custom_minimum_size.x = 680
	v.add_child(d)
	var obj: String = M.scn_objective(S)
	if obj != "":
		var op := PanelContainer.new()
		var sb := UIKit.box(Color(0.95, 0.69, 0.24, 0.09), Color(0, 0, 0, 0), 0, 0, Vector4(14, 9, 12, 9))
		sb.border_width_left = 3
		sb.border_color = UIKit.AMBER
		op.add_theme_stylebox_override("panel", sb)
		var oh := UIKit.hbox(10)
		oh.add_child(UIKit.icon("target", 20, UIKit.AMBER2))
		var ol := UIKit.rich("[b]Obiettivo:[/b] " + obj, 15, Color("#f3e6bd"))
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oh.add_child(ol)
		op.add_child(oh)
		v.add_child(op)
	var bits := []
	if M.scn_difficulty(S) != "":
		bits.append("Difficoltà " + M.scn_difficulty(S))
	if M.scn_duration(S) != "":
		bits.append("Durata " + M.scn_duration(S))
	if not bits.is_empty():
		v.add_child(_center_text("  ·  ".join(bits), 13, UIKit.DIM))
	v.add_child(UIKit.spacer(0, 4, false))
	v.add_child(_buttons([["▶  Inizia l'operazione", "primary", "resume"]]))
	v.add_child(_center_text(("Si gioca a turni: tocca a te per primo · F1 guida · l'obiettivo e i turni rimasti restano nel pannello a sinistra") if main.turn_mode() else "La partita è in pausa · F1 guida · l'obiettivo resta visibile nel pannello a sinistra", 12, UIKit.DIM))
	return v

func build_end() -> Control:
	var g = main.game
	var hh: int = main.h()
	var w := int(g.over.get("winner", -1)) if g.over is Dictionary else -1
	var W = g.players[w] if w >= 0 else null
	var won := hh >= 0 and w == hh
	var v := UIKit.vbox(12)
	var title := "FINE DELLA GUERRA" if hh < 0 else ("VITTORIA!" if won else "SCONFITTA")
	var tcol := UIKit.AMBER2 if hh < 0 else (UIKit.GREEN if won else UIKit.RED)
	var th := UIKit.hbox(14)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("trophy" if (won or hh < 0) else "skull", 38, tcol))
	th.add_child(_title(title, tcol, 46))
	v.add_child(th)
	if W != null:
		var wh := UIKit.hbox(8)
		wh.alignment = BoxContainer.ALIGNMENT_CENTER
		wh.add_child(UIKit.swatch(W["color"], 14))
		wh.add_child(UIKit.label(String(W["name"]) + (" vince l'operazione." if main.current_scenario() != null else " domina il mondo."), 18, UIKit.WHITE, "sans", 700))
		v.add_child(wh)
	var reason := String(g.over.get("reason", "")) if g.over is Dictionary else ""
	var scn = main.current_scenario()
	if scn != null:
		var sh := UIKit.hbox(8)
		sh.alignment = BoxContainer.ALIGNMENT_CENTER
		sh.add_child(UIKit.icon("flag", 16, UIKit.AMBER2))
		sh.add_child(UIKit.label("Scenario: " + String(scn.get("name", "")), 14, UIKit.AMBER2, "mono", 700))
		v.add_child(sh)
	if reason != "":
		v.add_child(_center_text(reason, 15 if scn != null else 14, UIKit.TEXT if scn != null else UIKit.DIM))
	var focus_p = g.players[hh] if hh >= 0 else W
	if focus_p != null:
		v.add_child(_highlights(focus_p))
	v.add_child(_charts())
	v.add_child(_stats_table())
	v.add_child(_buttons([["↻  Nuova partita", "primary", "new-game"], ["Menu principale", "normal", "quit"], ["Guarda la mappa", "normal", "watch"]]))
	return v

func build_eliminated() -> Control:
	var v := UIKit.vbox(12)
	var th := UIKit.hbox(14)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("skull", 38, UIKit.RED))
	th.add_child(_title("SCONFITTA", UIKit.RED, 46))
	v.add_child(th)
	v.add_child(_center_text("Le tue forze sono state annientate. Puoi continuare a guardare la guerra o iniziare una nuova partita.", 15))
	v.add_child(_charts())
	v.add_child(_stats_table())
	v.add_child(_buttons([["Continua a guardare", "normal", "watch"], ["↻  Nuova partita", "primary", "new-game"], ["Menu principale", "normal", "quit"]]))
	return v
