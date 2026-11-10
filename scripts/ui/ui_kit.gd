class_name UIKit
extends RefCounted
## Tema "comando militare" e helper per costruire i widget dell'interfaccia (tutto in codice).

const BG := Color(0.035, 0.06, 0.062, 0.90)
const BG2 := Color(0.07, 0.11, 0.105, 0.94)
const LINE := Color(0.59, 0.75, 0.63, 0.20)
const LINE2 := Color(0.59, 0.75, 0.63, 0.42)
const TEXT := Color("#dbe5d6")
const DIM := Color("#8b9a8d")
const AMBER := Color("#f2b13c")
const AMBER2 := Color("#ffd57a")
const GREEN := Color("#7fe08f")
const RED := Color("#ff6a5a")
const ORANGE := Color("#ffa14a")
const BLUE := Color("#6fb6e8")
const WHITE := Color("#f4f8f0")

static var _theme: Theme
static var _fonts := {}
static var _sb := {}

# ------------------------------------------------------------------ font
static func font(kind: String = "sans", weight: int = 400) -> Font:
	var key := kind + str(weight)
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	if kind == "mono":
		f.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Courier New", "monospace"])
	elif kind == "cond":
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial Narrow", "Arial", "sans-serif"])
	else:
		f.font_names = PackedStringArray(["Segoe UI", "Tahoma", "Arial", "DejaVu Sans", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	var sym := SystemFont.new()
	sym.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI Emoji", "DejaVu Sans", "Arial Unicode MS"])
	f.fallbacks = [sym]
	_fonts[key] = f
	return f

# ------------------------------------------------------------------ stylebox
static func box(bg: Color, border: Color = LINE, bw: int = 1, radius: int = 3, pad: Vector4 = Vector4(10, 8, 10, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s

static func panel_box(accent: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := box(BG, LINE, 1, 4, Vector4(12, 10, 12, 10))
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	if accent.a > 0:
		s.border_width_top = 2
		s.border_color = LINE
		s.border_blend = false
	return s

static func _btn_styles(kind: String) -> Dictionary:
	if _sb.has(kind):
		return _sb[kind]
	var base: Color
	var border: Color
	match kind:
		"primary":
			base = Color(0.17, 0.30, 0.16); border = Color(0.50, 0.75, 0.44)
		"danger":
			base = Color(0.32, 0.12, 0.11); border = Color(0.75, 0.38, 0.35)
		"op":
			base = Color(0.20, 0.10, 0.08); border = Color(0.75, 0.40, 0.30, 0.8)
		"ghost":
			base = Color(0.0, 0.0, 0.0, 0.25); border = LINE
		_:
			base = Color(0.11, 0.165, 0.15); border = LINE2
	var d := {}
	d["normal"] = box(base, border, 1, 3, Vector4(10, 5, 10, 5))
	d["hover"] = box(base.lightened(0.16), border.lightened(0.3), 1, 3, Vector4(10, 5, 10, 5))
	d["pressed"] = box(Color(0.33, 0.25, 0.07), AMBER, 1, 3, Vector4(10, 5, 10, 5))
	d["hover_pressed"] = box(Color(0.40, 0.31, 0.09), AMBER2, 1, 3, Vector4(10, 5, 10, 5))
	d["disabled"] = box(Color(0.08, 0.10, 0.10, 0.85), Color(LINE, 0.15), 1, 3, Vector4(10, 5, 10, 5))
	d["focus"] = StyleBoxEmpty.new()
	_sb[kind] = d
	return d

# ------------------------------------------------------------------ tema
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("sans", 400)
	t.default_font_size = 14
	var bs := _btn_styles("normal")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "Button", bs[st])
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", AMBER2)
	t.set_color("font_hover_pressed_color", "Button", AMBER2)
	t.set_color("font_disabled_color", "Button", Color(DIM, 0.55))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_font("font", "Button", font("sans", 600))
	t.set_font_size("font_size", "Button", 13)
	t.set_constant("h_separation", "Button", 6)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	# barre di scorrimento sottili
	var grab := box(Color(0.59, 0.75, 0.63, 0.30), Color(0, 0, 0, 0), 0, 3, Vector4(0, 0, 0, 0))
	var grab_h := box(Color(0.59, 0.75, 0.63, 0.55), Color(0, 0, 0, 0), 0, 3, Vector4(0, 0, 0, 0))
	var track := box(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0), 0, 3, Vector4(3, 0, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	# tooltip
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.05, 0.05, 0.96), LINE2, 1, 3, Vector4(8, 6, 8, 6)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	# barra di avanzamento
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.45), LINE, 1, 2, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", box(Color(0.30, 0.62, 0.36), Color(0, 0, 0, 0), 0, 2, Vector4(0, 0, 0, 0)))
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_stylebox("separator", "HSeparator", box(LINE, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_constant("separation", "HSeparator", 6)
	_theme = t
	return t

# ------------------------------------------------------------------ widget
static func label(text: String, size: int = 14, color: Color = TEXT, kind: String = "sans", weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func rich(bbcode: String, size: int = 13, color: Color = TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_override("normal_font", font("sans", 400))
	r.add_theme_font_override("bold_font", font("sans", 700))
	r.add_theme_font_override("mono_font", font("mono", 400))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size - 1)
	r.add_theme_color_override("default_color", color)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bbcode
	return r

## Intestazione di sezione: testo ambra maiuscolo + linea sottile, con nota a destra.
static func header(text: String, note: String = "") -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text.to_upper(), 12, AMBER, "mono", 700)
	h.add_child(l)
	if note != "":
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sp)
		h.add_child(label(note, 12, DIM))
	v.add_child(h)
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	return v

static func button(text: String, kind: String = "normal", size: String = "md", cb: Callable = Callable(), tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if kind != "normal":
		var st := _btn_styles(kind)
		for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(k, st[k])
	var fs := 13
	var pad := Vector2(10, 5)
	match size:
		"xs": fs = 12; pad = Vector2(6, 2)
		"sm": fs = 12; pad = Vector2(8, 3)
		"big": fs = 16; pad = Vector2(20, 10)
	b.add_theme_font_size_override("font_size", fs)
	if size != "md":
		var st2 := _btn_styles(kind)
		for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var s: StyleBoxFlat = (st2[k] as StyleBoxFlat).duplicate()
			s.content_margin_left = pad.x; s.content_margin_right = pad.x
			s.content_margin_top = pad.y; s.content_margin_bottom = pad.y
			b.add_theme_stylebox_override(k, s)
	if kind == "primary":
		b.add_theme_color_override("font_color", Color("#eaffdf"))
	if tip != "":
		b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(func(): Sfx.play("click"); cb.call())
	return b

## Pulsante "disattivato ma informativo": cliccabile per il tooltip, aspetto spento.
static func set_enabled(b: Button, ok: bool) -> void:
	b.disabled = not ok
	b.mouse_filter = Control.MOUSE_FILTER_STOP

static func spacer(w: float = 0, h: float = 0, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func vbox(sep: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

static func swatch(c: Color, sz: float = 11) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(sz, sz)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func tag(text: String, bg: Color = AMBER, fg: Color = Color("#1a1205")) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, Color(0, 0, 0, 0), 0, 2, Vector4(4, 0, 4, 0)))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, 10, fg, "mono", 700))
	return p

static func progress(pc: float, color: Color = Color(0.36, 0.72, 0.42), h: float = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = 100
	p.value = pc
	p.show_percentage = false
	p.custom_minimum_size = Vector2(40, h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 0, 2, Vector4(0, 0, 0, 0)))
	return p

static func icon(kind: String, sz: float = 16, col: Color = Color(0, 0, 0, 0)) -> Control:
	var i := UIIcon.new()
	i.kind = kind
	i.custom_minimum_size = Vector2(sz, sz)
	if col.a > 0:
		i.tint = col
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

## Riga di costo con icone; se res è dato, le voci non coperte diventano rosse.
static func cost_row(cost, mul: float = 1.0, fs: int = 12, res = null) -> HBoxContainer:
	var h := hbox(5)
	if cost == null or not (cost is Dictionary):
		return h
	for k in Data.RES_KEYS:
		var v := float(cost.get(k, 0))
		if v <= 0:
			continue
		var n := int(round(v * mul))
		var pair := hbox(2)
		pair.add_child(icon(k, fs + 1))
		var col := Color("#d8d2a8")
		if res is Dictionary and float(res.get(k, 0)) < n:
			col = RED
		pair.add_child(label(str(n), fs, col, "mono", 400))
		h.add_child(pair)
	return h

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

# ------------------------------------------------------------------ testo
static func fmt_time(s: float) -> String:
	var t := maxi(0, int(floor(s)))
	return "%02d:%02d" % [t / 60, t % 60]

static func cost_str(cost, mul: float = 1.0) -> String:
	if cost == null or not (cost is Dictionary):
		return ""
	var parts := []
	for k in Data.RES_KEYS:
		if cost.get(k, 0):
			parts.append(res_short(k) + str(int(round(float(cost[k]) * mul))))
	return "  ".join(parts)

static func res_short(k: String) -> String:
	match k:
		"money": return "$"
		"oil": return "P "
		"steel": return "A "
		"manpower": return "M "
	return k

static func forces_text(f, sep: String = " · ") -> String:
	if f == null or not (f is Dictionary):
		return "sconosciute"
	var parts := []
	for k in Data.UNIT_KEYS:
		if int(f.get(k, 0)) > 0:
			parts.append(Data.UNITS[k]["short"] + " " + str(int(f[k])))
	return sep.join(parts) if parts.size() else "nessuna"

static func hexc(c: Color) -> String:
	return "#" + c.to_html(false)

## Nome di un livello tecnologico nella forma unica usata ovunque: "Tech N · Nome".
static func tech_name(lv: int) -> String:
	if lv >= 1 and lv < Data.TECH_LEVELS.size() and Data.TECH_LEVELS[lv] != null:
		return "Tech %d · %s" % [lv, Data.TECH_LEVELS[lv]["name"]]
	return "Tech %d" % lv

## Uniforma i termini dei testi di dati (es. "dal livello 2" → "da Tech 2 · Moderna").
static func terms(s: String) -> String:
	for lv in range(1, Data.TECH_LEVELS.size()):
		s = s.replace("dal livello %d" % lv, "da " + tech_name(lv)).replace("dal Liv. %d" % lv, "da " + tech_name(lv))
	return s
