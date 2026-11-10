extends VBoxContainer
## Schermata Salvataggi: elenco degli slot con miniatura, nome, fazione, minuto e data.
## mode "save": campo nome + nuovo slot, sovrascrivi; mode "load": carica. In entrambe: elimina (con conferma).

const SaveStore := preload("res://scripts/ui/save_store.gd")

var main = null
var mode := "load"
var on_back: Callable = Callable()
var _list: VBoxContainer
var _name: LineEdit
var _confirm := ""

func setup(m, md: String, back: Callable) -> VBoxContainer:
	main = m
	mode = md
	on_back = back
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	return self

func _build() -> void:
	UIKit.clear(self)
	var th := UIKit.hbox(12)
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_child(UIKit.icon("save" if mode == "save" else "load", 26, UIKit.AMBER2))
	th.add_child(UIKit.label("SALVA LA PARTITA" if mode == "save" else "CARICA PARTITA", 28, UIKit.AMBER2, "cond", 700))
	add_child(th)
	if mode == "save":
		var ok: bool = main.save_available()
		var nh := UIKit.hbox(10)
		_name = LineEdit.new()
		_name.placeholder_text = "Nome del salvataggio"
		_name.text = main.default_save_name()
		_name.custom_minimum_size = Vector2(420, 40)
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.max_length = 40
		_name.add_theme_font_size_override("font_size", 16)
		_name.add_theme_stylebox_override("normal", UIKit.box(Color(0, 0, 0, 0.4), UIKit.LINE2, 1, 3, Vector4(12, 6, 12, 6)))
		_name.add_theme_stylebox_override("focus", UIKit.box(Color(0, 0, 0, 0.5), UIKit.AMBER, 1, 3, Vector4(12, 6, 12, 6)))
		_name.add_theme_color_override("font_color", UIKit.WHITE)
		_name.add_theme_color_override("caret_color", UIKit.AMBER2)
		_name.text_submitted.connect(func(_t): _save_new())
		nh.add_child(_name)
		var sb := UIKit.button("Nuovo salvataggio", "primary", "big", _save_new)
		sb.disabled = not ok
		nh.add_child(sb)
		add_child(nh)
		if not ok:
			add_child(_note("Il nucleo di gioco non supporta ancora i salvataggi (serialize mancante)."))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(900, 430)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	add_child(sc)
	_fill()
	var bh := UIKit.hbox(14)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UIKit.button("◀  Indietro", "normal", "big", func():
		if on_back.is_valid():
			on_back.call())
	back.custom_minimum_size.x = 220
	bh.add_child(back)
	var hint := UIKit.label("F5 salvataggio rapido · F9 caricamento rapido", 12, UIKit.DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(hint)
	add_child(bh)

func _note(t: String) -> Label:
	var l := UIKit.label(t, 13, UIKit.ORANGE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _fill() -> void:
	UIKit.clear(_list)
	var items := SaveStore.list()
	if items.is_empty():
		var e := UIKit.vbox(6)
		e.custom_minimum_size.y = 200
		e.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := UIKit.icon("folder", 46, Color(UIKit.DIM, 0.5))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		e.add_child(ic)
		var l := UIKit.label("Nessun salvataggio", 18, UIKit.DIM, "sans", 600)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_child(l)
		var l2 := UIKit.label("Durante la partita: Esc → Salva partita, oppure F5.", 13, UIKit.DIM)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_child(l2)
		_list.add_child(e)
		return
	for m in items:
		_list.add_child(_row(m))

func _row(m: Dictionary) -> Control:
	var slot := String(m["slot"])
	var p := PanelContainer.new()
	var col := Color(m.get("color", "#8b9a8d"))
	var sb := UIKit.box(Color(0.06, 0.095, 0.09, 0.92), UIKit.LINE, 1, 4, Vector4(8, 8, 14, 8))
	sb.border_width_left = 4
	sb.border_color = col
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(14)
	# miniatura
	var th := PanelContainer.new()
	th.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.5), UIKit.LINE2, 1, 2, Vector4(1, 1, 1, 1)))
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(176, 99)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = SaveStore.thumb_texture(String(m.get("thumb_path", "")))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tr.texture == null:
		var ph := UIKit.icon("globe", 40, Color(UIKit.DIM, 0.35))
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.add_child(ph)
	th.add_child(tr)
	h.add_child(th)
	# testi
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var nh := UIKit.hbox(8)
	var nl := UIKit.label(String(m.get("name", slot)), 18, UIKit.WHITE, "sans", 700)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(nl)
	if slot == "auto":
		nh.add_child(UIKit.tag("AUTOMATICO", Color(0.45, 0.62, 0.75), Color(0.03, 0.05, 0.08)))
	elif slot == "quick":
		nh.add_child(UIKit.tag("RAPIDO  F9", Color(0.55, 0.75, 0.5), Color(0.03, 0.06, 0.03)))
	v.add_child(nh)
	var fh := UIKit.hbox(7)
	fh.add_child(UIKit.swatch(col, 11))
	fh.add_child(UIKit.label(String(m.get("faction_name", "Spettatore")), 14, col.lightened(0.3), "sans", 600))
	v.add_child(fh)
	var when := ("Turno %d" % int(m["round"])) if int(m.get("round", 0)) > 0 else ("Minuto %d" % int(m.get("minute", 0)))
	var info := "%s  ·  %s  ·  %d territori" % [when, String(m.get("mode_name", "")), int(m.get("territories", 0))]
	v.add_child(UIKit.label(info, 13, UIKit.TEXT, "mono"))
	v.add_child(UIKit.label(SaveStore.fmt_date(float(m.get("date", 0))), 12, UIKit.DIM, "mono"))
	h.add_child(v)
	# pulsanti
	var bv := UIKit.vbox(6)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	if mode == "save":
		var ow := UIKit.button("Sovrascrivi", "primary", "md", func(): _save_over(slot, String(m.get("name", ""))))
		ow.disabled = not main.save_available()
		ow.custom_minimum_size = Vector2(150, 34)
		bv.add_child(ow)
	else:
		var lb := UIKit.button("▶  Carica", "primary", "md", func(): main.load_slot(slot))
		lb.disabled = not main.load_available()
		lb.custom_minimum_size = Vector2(150, 34)
		if not main.load_available():
			lb.tooltip_text = "Il nucleo di gioco non supporta ancora il caricamento"
		bv.add_child(lb)
	var del := UIKit.button("Conferma eliminazione" if _confirm == slot else "Elimina", "danger" if _confirm == slot else "ghost", "sm", func():
		if _confirm == slot:
			SaveStore.remove(slot)
			_confirm = ""
		else:
			_confirm = slot
		_fill())
	del.custom_minimum_size = Vector2(150, 28)
	bv.add_child(del)
	h.add_child(bv)
	p.add_child(h)
	return p

func _save_new() -> void:
	if not main.save_available():
		return
	var n := _name.text.strip_edges() if _name != null else ""
	if main.save_to_slot(SaveStore.new_slot_id(), n if n != "" else main.default_save_name()):
		_fill()

func _save_over(slot: String, old_name: String) -> void:
	var n := _name.text.strip_edges() if _name != null else ""
	if main.save_to_slot(slot, n if n != "" else old_name):
		_fill()
