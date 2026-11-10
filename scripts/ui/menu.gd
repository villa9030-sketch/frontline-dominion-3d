extends Control
## Menu iniziale a pagine sopra il tabellone 3D:
##  home     → titolo, Continua / Nuova campagna / Carica / Impostazioni / Guida / Spettatore / Esci, ultimo salvataggio
##  new      → fazione, avversari, difficoltà, modalità, distribuzione, opzioni battaglia
##  scenari  → scenari storici/curati (Scenarios.LIST, FASE 4)
##  load     → elenco dei salvataggi
##  settings → impostazioni

const SaveStore := preload("res://scripts/ui/save_store.gd")
const UnitPreview := preload("res://scripts/ui/unit_preview.gd")
const VERSION := "v0.4"

var main = null
var page := "home"
var vignette: TextureRect
var side_shade: TextureRect
var home: Control
var center: CenterContainer
var box: PanelContainer
var content: VBoxContainer
var _anim_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# velature sopra lo sfondo 3D
	vignette = _grad_rect(true)
	add_child(vignette)
	side_shade = _grad_rect(false)
	add_child(side_shade)
	home = Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(home)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	box = PanelContainer.new()
	var sb := UIKit.box(Color(0.03, 0.055, 0.055, 0.92), UIKit.LINE2, 1, 6, Vector4(38, 28, 38, 24))
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	sb.border_width_top = 3
	sb.border_color = Color(UIKit.AMBER, 0.7)
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	content = UIKit.vbox(10)
	box.add_child(content)

func _grad_rect(radial: bool) -> TextureRect:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	if radial:
		gr.set_color(0, Color(0.02, 0.05, 0.05, 0.10))
		gr.set_color(1, Color(0.01, 0.03, 0.03, 0.85))
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.62, 0.45)
		gt.fill_to = Vector2(1.25, 1.1)
	else:
		gr.set_color(0, Color(0.01, 0.025, 0.025, 0.95))
		gr.add_point(0.45, Color(0.01, 0.03, 0.03, 0.72))
		gr.set_color(gr.get_point_count() - 1, Color(0.01, 0.03, 0.03, 0.0))
		gt.fill_from = Vector2(0, 0.5)
		gt.fill_to = Vector2(0.75, 0.5)
	gt.gradient = gr
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	return bg

func show_page(p: String) -> void:
	page = p
	refresh()

## Esc: dalle sotto-pagine torna alla home.
func back() -> bool:
	if page != "home":
		Sfx.play("click")
		show_page("home")
		return true
	return false

func refresh() -> void:
	if main == null:
		return
	var is_home := page == "home"
	home.visible = is_home
	center.visible = not is_home
	side_shade.visible = is_home
	UIKit.clear(home)
	UIKit.clear(content)
	match page:
		"home": _build_home()
		"new": _build_new()
		"scenari": _build_scenarios()
		"load":
			box.custom_minimum_size.x = 980
			content.add_child(load("res://scripts/ui/saves_panel.gd").new().setup(main, "load", func(): show_page("home")))
		"settings":
			box.custom_minimum_size.x = 1040
			content.add_child(load("res://scripts/ui/settings_panel.gd").new().setup(func(): show_page("home")))
	if not is_home:
		_pop(box)

func _pop(c: Control) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2
	c.scale = Vector2(0.97, 0.97)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ================================================================== home
func _build_home() -> void:
	var col := UIKit.vbox(0)
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 110
	col.offset_right = 110 + 520
	col.offset_top = 0
	col.offset_bottom = 0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	home.add_child(col)
	col.add_child(UIKit.label("TEATRO OPERATIVO GLOBALE", 14, Color(UIKit.AMBER, 0.85), "mono", 700))
	col.add_child(UIKit.spacer(0, 4, false))
	var t1 := UIKit.label("FRONTLINE", 86, Color("#e6eedf"), "cond", 700)
	var t2 := UIKit.label("DOMINION", 86, UIKit.AMBER, "cond", 700)
	var tv := UIKit.vbox(-30)
	for t in [t1, t2]:
		t.add_theme_constant_override("outline_size", 3)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		tv.add_child(t)
	col.add_child(tv)
	var bar := ColorRect.new()
	bar.color = UIKit.AMBER
	bar.custom_minimum_size = Vector2(140, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(UIKit.spacer(0, 6, false))
	col.add_child(bar)
	col.add_child(UIKit.spacer(0, 12, false))
	var sub := UIKit.label("Conquista globale a turni, come Risiko:\nindustria, diplomazia e battaglie 3D sul campo.", 17, UIKit.TEXT)
	col.add_child(sub)
	col.add_child(UIKit.spacer(0, 30, false))
	var last = SaveStore.latest()
	var can_load: bool = main.load_available()
	if last != null and can_load:
		col.add_child(_menu_btn("play", "Continua", "%s  ·  %s" % [String(last.get("name", "")), SaveStore.fmt_date(float(last.get("date", 0)))], func(): main.act("continue"), true))
	col.add_child(_menu_btn("globe", "Nuova campagna", "", func(): show_page("new"), last == null or not can_load))
	if not scenario_list().is_empty():
		col.add_child(_menu_btn("flag", "Scenari", "%d operazioni con obiettivi propri" % scenario_list().size(), func(): show_page("scenari")))
	var lb := _menu_btn("load", "Carica partita", "", func(): show_page("load"))
	col.add_child(lb)
	col.add_child(_menu_btn("gear", "Impostazioni", "", func(): show_page("settings")))
	col.add_child(_menu_btn("bulb", "Tutorial", "Prima partita guidata, passo per passo", func(): main.act("tutorial")))
	col.add_child(_menu_btn("help", "Come si gioca", "", func(): main.act("help")))
	col.add_child(_menu_btn("eye", "Modalità spettatore", "", func(): main.act("spectate")))
	col.add_child(_menu_btn("exit", "Esci", "", func(): main.act("exit")))
	# piede
	var foot := UIKit.vbox(2)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 110
	foot.offset_right = 900
	foot.offset_top = -64
	foot.offset_bottom = -24
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.add_child(UIKit.label("%s  ·  F1 guida  ·  F5/F9 salvataggio rapido  ·  Alt+Invio schermo intero" % VERSION, 12, Color(UIKit.DIM, 0.85), "mono"))
	foot.add_child(UIKit.label("Modelli, effetti, musica e suoni generati proceduralmente  ·  Godot %s" % Engine.get_version_info().get("string", "4"), 11, Color(UIKit.DIM, 0.6), "mono"))
	home.add_child(foot)
	home.add_child(_faction_strip())
	# scheda dell'ultimo salvataggio
	if last != null:
		home.add_child(_last_card(last, can_load))
	# comparsa
	col.modulate.a = 0
	col.position.x -= 24
	var tw := col.create_tween().set_parallel(true)
	tw.tween_property(col, "modulate:a", 1.0, 0.35)
	tw.tween_property(col, "position:x", col.position.x + 24, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _menu_btn(ic: String, text: String, sub: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(430, 58 if sub != "" else 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var n := UIKit.box(Color(UIKit.AMBER, 0.13) if primary else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4.ZERO)
	n.border_width_left = 3
	n.border_color = Color(UIKit.AMBER, 0.9) if primary else Color(1, 1, 1, 0.0)
	var hv := UIKit.box(Color(UIKit.AMBER, 0.20), Color(0, 0, 0, 0), 0, 2, Vector4.ZERO)
	hv.border_width_left = 3
	hv.border_color = UIKit.AMBER2
	var pr := hv.duplicate()
	pr.bg_color = Color(UIKit.AMBER, 0.30)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	var h := UIKit.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18
	var icon_c := UIKit.icon(ic, 22, UIKit.AMBER2 if primary else UIKit.TEXT)
	h.add_child(icon_c)
	var v := UIKit.vbox(-2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UIKit.label(text.to_upper(), 24, UIKit.WHITE if primary else Color("#dfe8d8"), "cond", 600)
	v.add_child(l)
	if sub != "":
		var sl := UIKit.label(sub, 13, UIKit.AMBER2 if primary else UIKit.DIM)
		sl.clip_text = true
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.custom_minimum_size.x = 340
		v.add_child(sl)
	h.add_child(v)
	b.add_child(h)
	b.mouse_entered.connect(func():
		l.add_theme_color_override("font_color", UIKit.AMBER2)
		icon_c.tint = UIKit.AMBER2
		Sfx.play("click", 0.25))
	b.mouse_exited.connect(func():
		l.add_theme_color_override("font_color", UIKit.WHITE if primary else Color("#dfe8d8"))
		icon_c.tint = UIKit.AMBER2 if primary else UIKit.TEXT)
	b.pressed.connect(func(): Sfx.play("click"); cb.call())
	return b

## Le quattro potenze con il loro mezzo tipico in 3D (fermo; ruota al passaggio del mouse). Clic = nuova campagna con quella fazione.
func _faction_strip() -> Control:
	var p := PanelContainer.new()
	var sb := UIKit.box(Color(0.03, 0.055, 0.055, 0.78), Color(UIKit.LINE2, 0.7), 1, 5, Vector4(14, 10, 14, 12))
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -60
	p.offset_left = -60
	p.offset_top = 52
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UIKit.vbox(8)
	var hh := UIKit.hbox(8)
	hh.add_child(UIKit.label("QUATTRO POTENZE IN GUERRA", 12, UIKit.AMBER, "mono", 700))
	hh.add_child(UIKit.spacer())
	hh.add_child(UIKit.label("scegli e combatti ▸", 11, UIKit.DIM, "mono"))
	v.add_child(hh)
	var row := UIKit.hbox(8)
	for i in Data.FACTIONS.size():
		row.add_child(_faction_tile(i))
	v.add_child(row)
	p.add_child(v)
	p.modulate.a = 0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.6).set_delay(0.25)
	return p

func _faction_tile(i: int) -> Control:
	var F: Dictionary = Data.FACTIONS[i]
	var fc := Color(F["color"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "%s — %s\n%s" % [F["name"], F["doctrine"], UIKit.terms("\n".join(F["perks"]))]
	var n := UIKit.box(Color(fc.darkened(0.8), 0.55), Color(fc, 0.35), 1, 4, Vector4.ZERO)
	n.border_width_bottom = 3
	n.border_color = Color(fc, 0.7)
	var hv := n.duplicate()
	hv.bg_color = Color(fc.darkened(0.6), 0.75)
	hv.border_color = fc
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var v := UIKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv: SubViewportContainer = UnitPreview.new().setup(UnitPreview.faction_kind(i), fc, i, Vector2(150, 84), false, -0.75 + i * 0.25)
	v.add_child(pv)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 8)
	m.add_theme_constant_override("margin_bottom", 7)
	var tv := UIKit.vbox(-2)
	var nh := UIKit.hbox(6)
	nh.add_child(UIKit.swatch(fc, 9))
	nh.add_child(UIKit.label(F["short"], 18, fc.lightened(0.25), "cond", 700))
	tv.add_child(nh)
	var dl := UIKit.label(F["doctrine"], 11, UIKit.TEXT)
	dl.clip_text = true
	dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dl.custom_minimum_size.x = 134
	tv.add_child(dl)
	m.add_child(tv)
	v.add_child(m)
	b.add_child(v)
	b.custom_minimum_size = Vector2(150, 132)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.mouse_entered.connect(func(): pv.set_spin(true); Sfx.play("click", 0.2))
	b.mouse_exited.connect(func(): pv.set_spin(false))
	b.pressed.connect(func():
		Sfx.play("select")
		main.act("m-fac", {"v": i})
		show_page("new"))
	return b

func _last_card(m: Dictionary, can_load: bool) -> Control:
	var p := PanelContainer.new()
	var col := Color(m.get("color", "#8b9a8d"))
	var sb := UIKit.box(Color(0.03, 0.055, 0.055, 0.88), UIKit.LINE2, 1, 5, Vector4(10, 10, 10, 12))
	sb.border_width_top = 3
	sb.border_color = col
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_left = -400
	p.offset_right = -60
	p.offset_top = -330
	p.offset_bottom = -60
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UIKit.vbox(6)
	v.add_child(UIKit.label("ULTIMO SALVATAGGIO", 12, UIKit.AMBER, "mono", 700))
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(320, 180)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = SaveStore.thumb_texture(String(m.get("thumb_path", "")))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tr.texture == null:
		var ph := UIKit.icon("globe", 60, Color(UIKit.DIM, 0.35))
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.add_child(ph)
	v.add_child(tr)
	var nh := UIKit.hbox(7)
	nh.add_child(UIKit.swatch(col, 11))
	var nl := UIKit.label(String(m.get("name", "")), 16, UIKit.WHITE, "sans", 700)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(nl)
	v.add_child(nh)
	var when := ("turno %d" % int(m["round"])) if int(m.get("round", 0)) > 0 else ("minuto %d" % int(m.get("minute", 0)))
	v.add_child(UIKit.label("%s · %s · %s" % [String(m.get("faction_short", "")), when, SaveStore.fmt_date(float(m.get("date", 0)))], 12, UIKit.DIM, "mono"))
	if can_load:
		var b := UIKit.button("▶  Riprendi", "primary", "md", func(): main.act("continue"))
		v.add_child(b)
	p.add_child(v)
	p.modulate.a = 0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.5).set_delay(0.15)
	return p

# ================================================================== nuova campagna
func _build_new() -> void:
	box.custom_minimum_size.x = 1180
	var o: Dictionary = main.menu_opts
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("globe", 26, UIKit.AMBER2))
	th.add_child(UIKit.label("NUOVA CAMPAGNA", 30, UIKit.AMBER2, "cond", 700))
	content.add_child(th)
	var sub := UIKit.label("Scegli la fazione e le regole del conflitto", 14, UIKit.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	content.add_child(UIKit.spacer(0, 4, false))
	content.add_child(UIKit.header("La tua fazione"))
	var fg := HBoxContainer.new()
	fg.add_theme_constant_override("separation", 12)
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Data.FACTIONS.size():
		fg.add_child(_faction_card(i, int(o["faction"]) == i))
	content.add_child(fg)
	content.add_child(UIKit.spacer(0, 4, false))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 36)
	g.add_theme_constant_override("v_separation", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(_opt("Avversari", _seg("m-opp", o["opp"], [[1, "1"], [2, "2"], [3, "3"]])))
	var diffs := []
	for k in Data.DIFFICULTY.keys():
		diffs.append([k, Data.DIFFICULTY[k]["name"]])
	g.add_child(_opt("Difficoltà IA", _seg("m-diff", o["diff"], diffs)))
	g.add_child(_opt("Modalità", _seg("m-mode", o["mode"], [["conquista", "Conquista mondiale"], ["obiettivo", "Obiettivo segreto"]])))
	g.add_child(_opt("Distribuzione iniziale", _seg("m-dist", o["dist"], [["regionale", "Regionale (consigliata)"], ["casuale", "Casuale (tabellone)"]])))
	var ob := UIKit.hbox(2)
	ob.add_child(_check("m-ask", o["ask_defense"], "Chiedi anche in difesa"))
	ob.add_child(_check("m-auto", o["auto_battles"], "Battaglie sempre automatiche"))
	g.add_child(_opt("Opzioni battaglia", ob))
	var tips_on := bool(Settings.get_value("tips"))
	var rb := UIKit.hbox(2)
	var fb := _check("m-fog", bool(o.get("fog", true)), "Nebbia di guerra")
	fb.tooltip_text = "Vedi solo i tuoi territori e quelli confinanti (l'AAN un anello in più col radar):\naltrove solo stime delle forze nemiche. Vale anche per l'IA."
	rb.add_child(fb)
	var tb := UIKit.button(("☑  " if tips_on else "☐  ") + "Suggerimenti", "normal", "md", func():
		Settings.set_value("tips", not bool(Settings.get_value("tips")))
		refresh(), "Consigli della guida durante la prima partita")
	tb.toggle_mode = true
	tb.set_pressed_no_signal(tips_on)
	rb.add_child(tb)
	g.add_child(_opt("Regole e guida", rb))
	content.add_child(g)
	content.add_child(UIKit.spacer(0, 8, false))
	var bh := UIKit.hbox(14)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UIKit.button("◀  Indietro", "normal", "big", func(): show_page("home"))
	back.custom_minimum_size.x = 180
	bh.add_child(back)
	var bs := UIKit.button("▶  INIZIA LA CAMPAGNA", "primary", "big", func(): main.act("start"))
	bs.custom_minimum_size.x = 320
	bh.add_child(bs)
	content.add_child(bh)
	var foot := UIKit.label("Le fazioni avversarie sono comandate dall'IA.  Spazio = pausa · 0/1/2/3 = velocità (½× consigliata per imparare) · F1 = aiuto", 13, UIKit.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(foot)

func _opt(title: String, ctl: Control) -> Control:
	var v := UIKit.vbox(6)
	v.add_child(UIKit.label(title.to_upper(), 12, UIKit.AMBER, "mono", 700))
	v.add_child(ctl)
	return v

func _seg(act: String, cur, items: Array) -> Control:
	var h := UIKit.hbox(2)
	for it in items:
		var b := UIKit.button(String(it[1]), "normal", "md", func(): main.act(act, {"v": it[0]}))
		b.toggle_mode = true
		b.set_pressed_no_signal(str(cur) == str(it[0]))
		if items.size() == 3 and String(it[1]).length() <= 2:
			b.custom_minimum_size.x = 46
		h.add_child(b)
	return h

func _check(act: String, on: bool, text: String) -> Button:
	var b := UIKit.button(("☑  " if on else "☐  ") + text, "normal", "md", func(): main.act(act))
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	return b

func _faction_card(i: int, on: bool) -> Control:
	var F: Dictionary = Data.FACTIONS[i]
	var fc := Color(F["color"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 244)
	var n := UIKit.box(Color(0.07, 0.11, 0.10, 0.9), UIKit.LINE2, 1, 5, Vector4.ZERO)
	n.border_width_left = 6
	n.border_color = Color(fc, 0.75)
	var hv := n.duplicate()
	hv.bg_color = Color(0.10, 0.15, 0.14, 0.95)
	hv.border_color = fc
	var sel := UIKit.box(Color(fc.darkened(0.75), 0.95), fc, 2, 5, Vector4.ZERO)
	sel.border_width_left = 6
	sel.shadow_color = Color(fc, 0.45)
	sel.shadow_size = 14
	b.add_theme_stylebox_override("normal", sel if on else n)
	b.add_theme_stylebox_override("hover", sel if on else hv)
	b.add_theme_stylebox_override("pressed", sel)
	b.pressed.connect(func(): Sfx.play("select"); main.act("m-fac", {"v": i}))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14 if side != "left" else 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(4)
	var hh := UIKit.hbox(8)
	var hv2 := UIKit.vbox(4)
	hv2.add_child(UIKit.label(F["short"], 22, fc.lightened(0.2), "cond", 700))
	if on:
		var tg := UIKit.tag("SCELTA", fc, Color(0.05, 0.05, 0.05))
		tg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		hv2.add_child(tg)
	hh.add_child(hv2)
	hh.add_child(UIKit.spacer())
	var pv: SubViewportContainer = UnitPreview.new().setup(UnitPreview.faction_kind(i), fc, i, Vector2(132, 64), on, -0.7)
	hh.add_child(pv)
	if not on:
		b.mouse_entered.connect(func(): pv.set_spin(true))
		b.mouse_exited.connect(func(): pv.set_spin(false))
	v.add_child(hh)
	var nm := UIKit.label(F["name"], 15, UIKit.WHITE, "sans", 700)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	v.add_child(UIKit.label(F["doctrine"], 13, UIKit.AMBER2, "sans", 600))
	for p in F["perks"]:
		var ph := UIKit.hbox(6)
		var dot := UIKit.swatch(Color(fc, 0.9), 5)
		ph.add_child(dot)
		var pl := UIKit.label(UIKit.terms(p), 12, UIKit.TEXT)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_child(pl)
		v.add_child(ph)
	m.add_child(v)
	b.add_child(m)
	return b

# ================================================================== scenari (FASE 4)
const SCENARIOS_PATH := "res://scripts/core/scenarios.gd"
var scn_sel := 0
var scn_fac := -1        # fazione scelta per lo scenario (-1 = quella consigliata)
var _scn_preview := {}   # id → dati della mappa in miniatura (calcolati una volta)

## Elenco degli scenari (Scenarios.LIST) caricato dinamicamente: vuoto se il file non c'è ancora.
static func scenario_list() -> Array:
	if not ResourceLoader.exists(SCENARIOS_PATH):
		return []
	var sc = load(SCENARIOS_PATH)
	if sc == null or not (sc is Script) or not sc.can_instantiate():
		return []
	var m: Dictionary = sc.get_script_constant_map()
	var l = m.get("LIST", [])
	return l if l is Array else []

static func scenario_by_id(id: String):
	for S in scenario_list():
		if String(S.get("id", "")) == id:
			return S
	return null

## Primo campo presente fra più nomi possibili (lo schema degli scenari è del nucleo).
static func sf(S: Dictionary, keys: Array, def = null):
	for k in keys:
		if S.has(k) and S[k] != null:
			return S[k]
	return def

static func scn_faction(S: Dictionary) -> int:
	return int(sf(S, ["faction", "recommended", "rec_faction", "suggested_faction", "human_faction"], -1))

static func scn_difficulty(S: Dictionary) -> String:
	var d = sf(S, ["difficulty", "diff", "level"], "")
	if d is String and Data.DIFFICULTY.has(d):
		return String(Data.DIFFICULTY[d]["name"])
	return str(d) if d != null else ""

static func scn_duration(S: Dictionary) -> String:
	var rl = sf(S, ["round_limit", "rounds"], null)
	if rl != null and int(rl) > 0:
		return "%d turni" % int(rl)
	var d = sf(S, ["duration", "length", "time_limit", "limit", "minutes"], null)
	if d == null:
		return ""
	if d is String:
		return d
	var x := float(d)
	if x <= 0:
		return ""
	return "%d min" % int(round(x / 60.0 if x > 90 else x))

static func scn_objective(S: Dictionary) -> String:
	return str(sf(S, ["objective", "goal", "victory_text", "win_text", "brief", "briefing"], ""))

func select_scenario(i: int) -> void:
	var ni := clampi(i, 0, maxi(0, scenario_list().size() - 1))
	if ni != scn_sel:
		scn_fac = -1
	scn_sel = ni
	if page == "scenari":
		refresh()

func _build_scenarios() -> void:
	box.custom_minimum_size.x = 1240
	var L := scenario_list()
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("flag", 26, UIKit.AMBER2))
	th.add_child(UIKit.label("SCENARI", 30, UIKit.AMBER2, "cond", 700))
	content.add_child(th)
	var sub := UIKit.label("Operazioni con forze di partenza, regole e obiettivi propri", 14, UIKit.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	content.add_child(UIKit.spacer(0, 4, false))
	if L.is_empty():
		var e := UIKit.label("Nessuno scenario disponibile.", 16, UIKit.DIM)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(e)
		var bb := UIKit.button("◀  Indietro", "normal", "big", func(): show_page("home"))
		bb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(bb)
		return
	scn_sel = clampi(scn_sel, 0, L.size() - 1)
	var body := UIKit.hbox(18)
	# elenco
	var lv := UIKit.vbox(6)
	lv.custom_minimum_size.x = 400
	for i in L.size():
		lv.add_child(_scn_item(i, L[i], i == scn_sel))
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.custom_minimum_size = Vector2(412, mini(560, L.size() * 82))
	lsc.add_child(lv)
	body.add_child(lsc)
	# dettaglio
	body.add_child(_scn_detail(L[scn_sel]))
	content.add_child(body)

func _scn_item(i: int, S: Dictionary, on: bool) -> Control:
	var f := scn_faction(S)
	var fc := Color(Data.FACTIONS[f]["color"]) if f >= 0 and f < Data.FACTIONS.size() else UIKit.AMBER
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(400, 76)
	var n := UIKit.box(Color(0.07, 0.11, 0.10, 0.85), UIKit.LINE, 1, 4, Vector4.ZERO)
	n.border_width_left = 4
	n.border_color = Color(fc, 0.55)
	var hv := n.duplicate()
	hv.bg_color = Color(0.10, 0.15, 0.14, 0.95)
	hv.border_color = fc
	var sel := UIKit.box(Color(UIKit.AMBER, 0.14), UIKit.AMBER, 1, 4, Vector4.ZERO)
	sel.border_width_left = 4
	sel.shadow_color = Color(UIKit.AMBER, 0.25)
	sel.shadow_size = 8
	b.add_theme_stylebox_override("normal", sel if on else n)
	b.add_theme_stylebox_override("hover", sel if on else hv)
	b.add_theme_stylebox_override("pressed", sel)
	b.pressed.connect(func():
		Sfx.play("select")
		select_scenario(i))
	var h := UIKit.hbox(12)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := UIKit.label("%02d" % (i + 1), 26, UIKit.AMBER2 if on else Color(UIKit.AMBER, 0.6), "mono", 700)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(num)
	var v := UIKit.vbox(1)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := UIKit.label(String(S.get("name", "?")).to_upper(), 20, UIKit.WHITE if on else Color("#dfe8d8"), "cond", 700)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size.x = 260
	v.add_child(nl)
	var meta := UIKit.hbox(6)
	if f >= 0 and f < Data.FACTIONS.size():
		meta.add_child(UIKit.swatch(fc, 9))
		meta.add_child(UIKit.label(Data.FACTIONS[f]["short"], 12, fc.lightened(0.25), "mono", 700))
	var bits := []
	if scn_difficulty(S) != "":
		bits.append(scn_difficulty(S))
	if scn_duration(S) != "":
		bits.append(scn_duration(S))
	if not bits.is_empty():
		meta.add_child(UIKit.label(("·  " if f >= 0 else "") + "  ·  ".join(bits), 12, UIKit.DIM, "mono"))
	v.add_child(meta)
	h.add_child(v)
	b.add_child(h)
	return b

func _scn_detail(S: Dictionary) -> Control:
	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var f := scn_faction(S)
	var fc := Color(Data.FACTIONS[f]["color"]) if f >= 0 and f < Data.FACTIONS.size() else UIKit.AMBER
	# mappa della situazione iniziale
	var mp := Control.new()
	mp.custom_minimum_size = Vector2(760, 300)
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm: Control = load("res://scripts/ui/scenario_map.gd").new()
	sm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mp.add_child(sm)
	var pd: Dictionary = _scn_preview_data(S)
	pd["accent"] = UIKit.AMBER2
	sm.set_data(pd)
	# didascalia sopra la mappa
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UIKit.box(Color(0.02, 0.04, 0.04, 0.85), Color(0, 0, 0, 0), 0, 3, Vector4(10, 4, 10, 4)))
	cap.position = Vector2(10, 10)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var casual := String(sf(S, ["distribution", "dist"], "regionale")) == "casuale"
	cap.add_child(UIKit.label("SITUAZIONE INIZIALE" + ("  ·  ESEMPIO (spartizione casuale)" if casual else ""), 11, UIKit.AMBER, "mono", 700))
	mp.add_child(cap)
	if pd.has("legend"):
		var lg := PanelContainer.new()
		lg.add_theme_stylebox_override("panel", UIKit.box(Color(0.02, 0.04, 0.04, 0.85), Color(0, 0, 0, 0), 0, 3, Vector4(10, 4, 10, 4)))
		lg.position = Vector2(10, 300 - 32)
		lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lh := UIKit.hbox(12)
		for it in pd["legend"]:
			var e := UIKit.hbox(4)
			e.add_child(UIKit.swatch(it[1], 9))
			e.add_child(UIKit.label(String(it[0]), 11, UIKit.TEXT, "mono", 700))
			lh.add_child(e)
		lg.add_child(lh)
		mp.add_child(lg)
	v.add_child(mp)
	# titolo e descrizione
	var tl := UIKit.label(String(S.get("name", "?")).to_upper(), 30, UIKit.WHITE, "cond", 700)
	v.add_child(tl)
	var desc := UIKit.rich(String(sf(S, ["desc", "description"], "")), 14)
	desc.custom_minimum_size.x = 740
	v.add_child(desc)
	# scheda: fazione consigliata, difficoltà, durata
	var chips := UIKit.hbox(8)
	if f >= 0 and f < Data.FACTIONS.size():
		chips.add_child(_scn_chip("FAZIONE CONSIGLIATA", "%s · %s" % [Data.FACTIONS[f]["short"], Data.FACTIONS[f]["name"]], fc))
	if scn_difficulty(S) != "":
		chips.add_child(_scn_chip("DIFFICOLTÀ", scn_difficulty(S), UIKit.AMBER))
	if scn_duration(S) != "":
		chips.add_child(_scn_chip("DURATA MASSIMA", scn_duration(S), UIKit.AMBER))
	if S.has("opp"):
		chips.add_child(_scn_chip("AVVERSARI", "%d IA" % int(S["opp"]), UIKit.AMBER))
	if S.has("fog"):
		chips.add_child(_scn_chip("NEBBIA DI GUERRA", "Sì" if bool(S["fog"]) else "No", UIKit.AMBER))
	if chips.get_child_count() > 0:
		v.add_child(chips)
	var obj := scn_objective(S)
	if obj != "":
		var op := PanelContainer.new()
		var sb := UIKit.box(Color(0.95, 0.69, 0.24, 0.08), Color(0, 0, 0, 0), 0, 0, Vector4(12, 7, 10, 7))
		sb.border_width_left = 3
		sb.border_color = UIKit.AMBER
		op.add_theme_stylebox_override("panel", sb)
		var oh := UIKit.hbox(10)
		oh.add_child(UIKit.icon("target", 18, UIKit.AMBER2))
		var ol := UIKit.rich("[b]Obiettivo:[/b] " + obj, 14, Color("#f3e6bd"))
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oh.add_child(ol)
		op.add_child(oh)
		v.add_child(op)
	var pick := UIKit.hbox(26)
	var fh := UIKit.hbox(2)
	var cur := scn_fac if scn_fac >= 0 else f
	for i in Data.FACTIONS.size():
		var F: Dictionary = Data.FACTIONS[i]
		var fb := UIKit.button(String(F["short"]) + ("  ★" if i == f else ""), "normal", "md", func():
			Sfx.play("select")
			scn_fac = i
			refresh(), F["name"] + (" (consigliata)" if i == f else ""))
		fb.toggle_mode = true
		fb.set_pressed_no_signal(i == cur)
		fb.custom_minimum_size.x = 62
		fb.add_theme_color_override("font_color", Color(F["color"]).lightened(0.3))
		fb.add_theme_color_override("font_pressed_color", Color(F["color"]).lightened(0.5))
		fh.add_child(fb)
	pick.add_child(_opt("Gioca come", fh))
	var diffs := []
	for k in Data.DIFFICULTY.keys():
		diffs.append([k, Data.DIFFICULTY[k]["name"]])
	pick.add_child(_opt("Difficoltà IA", _seg("m-diff", main.menu_opts["diff"], diffs)))
	v.add_child(pick)
	v.add_child(UIKit.spacer(0, 2, false))
	var bh := UIKit.hbox(14)
	var back := UIKit.button("◀  Indietro", "normal", "big", func(): show_page("home"))
	back.custom_minimum_size.x = 170
	bh.add_child(back)
	bh.add_child(UIKit.spacer())
	var id := String(S.get("id", ""))
	var bs := UIKit.button("▶  AVVIA LO SCENARIO", "primary", "big", func(): main.act("scn-start", {"id": id, "faction": cur}))
	bs.custom_minimum_size.x = 320
	bh.add_child(bs)
	v.add_child(bh)
	return v

func _scn_chip(title: String, text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := UIKit.box(Color(1, 1, 1, 0.03), UIKit.LINE, 1, 4, Vector4(10, 5, 12, 6))
	sb.border_width_top = 2
	sb.border_color = Color(col, 0.8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(0)
	v.add_child(UIKit.label(title, 10, UIKit.DIM, "mono", 700))
	v.add_child(UIKit.label(text, 15, UIKit.WHITE, "sans", 700))
	p.add_child(v)
	return p

## Situazione di partenza dello scenario: una partita creata e subito scartata (proprietari, QG, colori).
func _scn_preview_data(S: Dictionary) -> Dictionary:
	var fac := scn_fac if scn_fac >= 0 else scn_faction(S)
	var id := String(S.get("id", "")) + ":" + str(fac)
	if _scn_preview.has(id):
		return _scn_preview[id]
	var d := {"owners": [], "colors": {}, "hqs": [], "focus": [], "human": -1}
	var g = main.make_scenario_game(S, true, fac) if main != null and main.has_method("make_scenario_game") else null
	if g != null:
		var owners := []
		for tr in g.terr:
			owners.append(int(tr["owner"]))
		d["owners"] = owners
		var legend := []
		for P in g.players:
			d["colors"][int(P["idx"])] = P["color"]
			if int(P["hq"]) >= 0:
				d["hqs"].append(int(P["hq"]))
			legend.append([String(P["fac"]["short"]) + (" (tu)" if bool(P["human"]) else ""), P["color"]])
		d["legend"] = legend
		d["human"] = int(g.human_idx)
		if g.has_method("dispose"):
			g.dispose()
	var fo = sf(S, ["focus", "key_territories", "targets", "objectives_terr"], [])
	if fo is Array:
		for x in fo:
			if x is int or x is float:
				d["focus"].append(int(x))
	_scn_preview[id] = d
	return d
