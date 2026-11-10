extends VBoxContainer
## Schermata Impostazioni (dal menu iniziale e dal menu di pausa): grafica, audio, controlli, interfaccia.
## Ogni modifica va subito in Settings (che la applica e la salva).

var on_back: Callable = Callable()
var _vals := {}

func setup(back: Callable) -> VBoxContainer:
	on_back = back
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	return self

func _st():
	return get_node_or_null("/root/Settings") if is_inside_tree() else Engine.get_main_loop().root.get_node_or_null("Settings")

func _gv(key: String):
	var s = _st()
	return s.get_value(key) if s != null else null

func _sv(key: String, v) -> void:
	var s = _st()
	if s != null:
		s.set_value(key, v)

func _build() -> void:
	UIKit.clear(self)
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("gear", 26, UIKit.AMBER2))
	var t := UIKit.label("IMPOSTAZIONI", 28, UIKit.AMBER2, "cond", 700)
	th.add_child(t)
	add_child(th)
	var cols := UIKit.hbox(34)
	var c1 := UIKit.vbox(10)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c2 := UIKit.vbox(10)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	cols.add_child(c2)
	add_child(cols)

	c1.add_child(UIKit.header("Grafica"))
	var q := []
	for k in ["basso", "medio", "alto"]:
		q.append([k, {"basso": "Bassa", "medio": "Media", "alto": "Alta"}[k]])
	c1.add_child(_row("Qualità grafica", _seg("quality", q), "Bassa: senza antialias multiplo, risoluzione 3D al 75%, ombre e vegetazione ridotte. Alta: MSAA 4×, ombre e dettagli massimi."))
	c1.add_child(_row("Schermo intero", _toggle("fullscreen"), "Spento: finestra massimizzata. Alt+Invio per alternare in qualsiasi momento"))
	c1.add_child(_row("Ciclo giorno/notte", _toggle("daynight"), "Il tabellone alterna giorno e notte col passare del tempo di gioco. Spento: luce diurna fissa"))
	c1.add_child(UIKit.spacer(0, 4, false))
	c1.add_child(UIKit.header("Audio"))
	c1.add_child(_row("Volume generale", _slider("vol_master", 0.0, 1.0, 0.05, true)))
	c1.add_child(_row("Effetti sonori", _slider("vol_sfx", 0.0, 1.0, 0.05, true)))
	c1.add_child(_row("Musica", _slider("vol_music", 0.0, 1.0, 0.05, true)))

	c2.add_child(UIKit.header("Controlli"))
	c2.add_child(_row("Velocità telecamera", _slider("camera_speed", 0.4, 2.5, 0.1, false)))
	c2.add_child(_row("Scorrimento ai bordi", _toggle("edge_scroll"), "Sposta la telecamera portando il mouse al bordo dello schermo"))
	c2.add_child(UIKit.spacer(0, 4, false))
	c2.add_child(UIKit.header("Interfaccia e partita"))
	c2.add_child(_row("Nomi dei territori", _toggle("show_names")))
	c2.add_child(_row("Salvataggio automatico", _seg("autosave", [[0, "No"], [5, "A ogni tuo turno"]]), "All'inizio di ogni tuo turno, nello slot «Automatico»"))
	c2.add_child(UIKit.spacer(0, 4, false))
	c2.add_child(UIKit.header("Turni delle IA"))
	c2.add_child(_row("Velocità turni IA", _seg("ai_speed", [["lenta", "Lenta"], ["normale", "Normale"], ["veloce", "Veloce"], ["istantanea", "Istantanea"]]), "Durata delle animazioni delle mosse avversarie sul tabellone. Durante un turno IA, Spazio accelera e poi salta"))
	c2.add_child(_row("Segui le mosse dell'IA", _toggle("ai_follow"), "La telecamera vola sugli attacchi e sugli spostamenti visibili delle IA"))
	var tips := UIKit.hbox(6)
	tips.add_child(UIKit.spacer())
	var rb := UIKit.button("Rivedi da capo", "ghost", "sm", func():
		var s = _st()
		if s != null:
			s.reset_tips()
			s.set_value("tips", true)
		_build(), "Mostra di nuovo tutti i suggerimenti della prima partita")
	tips.add_child(rb)
	tips.add_child(_toggle("tips"))
	c2.add_child(_row("Suggerimenti guida", tips, "Brevi consigli contestuali nella prima partita"))

	add_child(UIKit.spacer(0, 2, false))
	var bh := UIKit.hbox(14)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_child(UIKit.button("Ripristina predefinite", "ghost", "big", func():
		var s = _st()
		if s != null:
			s.reset_defaults()
		_build()))
	var back := UIKit.button("◀  Indietro", "primary", "big", func():
		if on_back.is_valid():
			on_back.call())
	back.custom_minimum_size.x = 220
	bh.add_child(back)
	add_child(bh)

func _row(title: String, ctl: Control, hint: String = "") -> Control:
	var v := UIKit.vbox(2)
	var h := UIKit.hbox(10)
	var l := UIKit.label(title, 15, UIKit.WHITE, "sans", 600)
	l.custom_minimum_size.x = 190
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if ctl is Button:
		h.add_child(UIKit.spacer())
	else:
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	v.add_child(h)
	if hint != "":
		var hl := UIKit.label(hint, 12, UIKit.DIM)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size.x = 300
		v.add_child(hl)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0, 4, Vector4(12, 8, 12, 8)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return p

func _seg(key: String, items: Array) -> Control:
	var h := UIKit.hbox(2)
	var btns := []
	for it in items:
		var b := UIKit.button(String(it[1]), "normal", "md", Callable())
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(str(_gv(key)) == str(it[0]))
		btns.append(b)
		h.add_child(b)
	for i in btns.size():
		var val = items[i][0]
		btns[i].pressed.connect(func():
			Sfx.play("click")
			_sv(key, val)
			for j in btns.size():
				btns[j].set_pressed_no_signal(j == i))
	return h

func _toggle(key: String) -> Button:
	var on := bool(_gv(key))
	var b := UIKit.button("", "normal", "md", Callable())
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(130, 30)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var paint := func(v: bool):
		b.text = ("●  Attivo" if v else "○  Disattivo")
		b.set_pressed_no_signal(v)
	paint.call(on)
	b.pressed.connect(func():
		Sfx.play("click")
		var nv := not bool(_gv(key))
		_sv(key, nv)
		paint.call(nv))
	return b

func _slider(key: String, lo: float, hi: float, step: float, pct: bool) -> Control:
	var h := UIKit.hbox(10)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(_gv(key))
	sl.custom_minimum_size = Vector2(170, 22)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var vl := UIKit.label("", 14, UIKit.AMBER2, "mono", 700)
	vl.custom_minimum_size.x = 52
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(x: float) -> String:
		return ("%d%%" % int(round(x * 100))) if pct else ("×%.1f" % x)
	vl.text = fmt.call(sl.value)
	sl.value_changed.connect(func(x: float):
		vl.text = fmt.call(x)
		_sv(key, x)
		if key == "vol_sfx" or key == "vol_master":
			Sfx.play("click"))
	h.add_child(sl)
	h.add_child(vl)
	return h
