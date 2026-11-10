class_name MapOverlay
extends Control
## Sovrimpressione 2D del tabellone (sala operativa): distintivi delle pedine a dimensione costante sullo schermo,
## nomi, etichette dei continenti, segnali (QG, battaglia, attacco in arrivo, sabotaggio...), cartiglio al passaggio.
## I dati li prepara WorldMap a ogni fotogramma (posizioni già proiettate e sfoltite); qui si disegna soltanto.

var badges: Array = []      # vedi WorldMap._layout_overlay
var divs: Array = []
var conts: Array = []
var rings: Array = []       # {pos, r, col, w}
var plate: Dictionary = {}  # cartiglio del territorio sotto il cursore
var promos: Array = []      # {pos, u, n, r} promozioni dei veterani
var t := 0.0

static var _fonts := {}

static func font(weight: int) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial Narrow", "Arial", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_fonts[weight] = f
	return f

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var fb := font(700)
	var fm := font(500)
	for c in conts:
		_draw_continent(c, fb, fm)
	for r in rings:
		var col: Color = r["col"]
		draw_arc(r["pos"], r["r"], 0.0, TAU, 48, col, r.get("w", 2.0), true)
	# leader: linee dalla posizione reale al distintivo spostato
	for b in badges:
		if b["alpha"] <= 0.01:
			continue
		var d: Vector2 = b["pos"] - b["anchor"]
		if d.length() > b["r"] * 0.6:
			var a: float = b["alpha"]
			draw_line(b["anchor"], b["pos"] - d.normalized() * b["r"], Color(0.02, 0.03, 0.04, 0.55 * a), 3.0, true)
			draw_line(b["anchor"], b["pos"] - d.normalized() * b["r"], Color(0.85, 0.9, 0.9, 0.7 * a), 1.2, true)
			draw_circle(b["anchor"], 2.6, Color(0.02, 0.03, 0.04, 0.7 * a))
			draw_circle(b["anchor"], 1.7, Color(b["col"], a))
	for d in divs:
		_draw_div(d, fb)
	for b in badges:
		if b["name_alpha"] > 0.01:
			_draw_name(b, fm)
	for b in badges:
		if b["alpha"] > 0.01:
			_draw_badge(b, fb)
	for pr in promos:
		_draw_promo(pr, fb)
	if not plate.is_empty():
		_draw_plate(plate, fb, fm)

# ---------------------------------------------------------------- elementi
func _text(f: Font, pos: Vector2, s: String, size: int, col: Color, outline: int, ocol: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var base := Vector2(x, pos.y + size * 0.36)
	if outline > 0:
		draw_string_outline(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ocol)
	draw_string(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func spaced(s: String) -> String:
	var out := ""
	for k in s.length():
		out += s[k]
		if k < s.length() - 1:
			out += " " if s[k] != " " else "  "
	return out

func _draw_continent(c: Dictionary, fb: Font, fm: Font) -> void:
	var a: float = c["alpha"]
	if a <= 0.01:
		return
	var p: Vector2 = c["pos"]
	var owned: bool = c["owned"]
	var col := Color(0.80, 0.90, 0.95, 0.30 * a)
	if owned:
		col = Color(c["col"].lightened(0.35), 0.80 * a)
	_text(fb, p, c["text"], 22, col, 6, Color(0.01, 0.03, 0.05, 0.45 * a))
	var sub: String = c["sub"]
	if sub != "":
		var sc := Color(0.75, 0.85, 0.9, 0.42 * a)
		if owned:
			sc = Color(c["col"].lightened(0.5), 0.85 * a)
		_text(fm, p + Vector2(0, 20), sub, 12, sc, 4, Color(0.01, 0.03, 0.05, 0.5 * a))

func _draw_badge(b: Dictionary, f: Font) -> void:
	var p: Vector2 = b["pos"]
	var r: float = b["r"] * (1.0 + 0.22 * b["pop"])
	var a: float = b["alpha"]
	var col: Color = b["col"]
	var pul := 0.5 + 0.5 * sin(t * 5.0)
	# allarme: attacco nemico in arrivo
	if b["warn"]:
		var rr := r + 5.0 + 7.0 * fmod(t * 1.2, 1.0)
		draw_arc(p, rr, 0, TAU, 40, Color(1.0, 0.25, 0.18, (1.0 - fmod(t * 1.2, 1.0)) * 0.9 * a), 2.5, true)
	if b["battle"]:
		draw_circle(p, r + 7.0 + pul * 3.0, Color(1.0, 0.25, 0.1, 0.22 * a))
	var fog: bool = b.get("fog", false)
	if fog:
		# territorio nella nebbia: distintivo attenuato (colore del proprietario noto ma spento, bordo tratteggiato)
		var lm := col.get_luminance()
		var fc := col.lerp(Color(lm, lm, lm), 0.3).darkened(0.12)
		draw_circle(p + Vector2(0, 2.0), r + 1.5, Color(0, 0, 0, 0.25 * a))
		draw_circle(p, r + 1.4, Color(0.03, 0.04, 0.05, 0.75 * a))
		draw_circle(p, r, Color(fc.darkened(0.25), 0.82 * a))
		var nd := 12
		for k in nd:
			var a0 := k * TAU / nd
			draw_arc(p, r, a0, a0 + TAU / nd * 0.55, 4, Color(fc.lightened(0.45), 0.8 * a), 1.3, true)
		if b["hq"]:
			draw_arc(p, r + 0.5, 0, TAU, 36, Color(1.0, 0.84, 0.36, 0.6 * a), 1.4, true)
	else:
		# ombra, corpo, bordo
		draw_circle(p + Vector2(0, 2.0), r + 1.5, Color(0, 0, 0, 0.35 * a))
		draw_circle(p, r + 1.6, Color(0.03, 0.04, 0.05, 0.92 * a))
		draw_circle(p, r, Color(col.darkened(0.28), a))
		draw_circle(p - Vector2(0, r * 0.18), r * 0.78, Color(col.darkened(0.08), a * 0.9))
		var rim := Color(1.0, 0.84, 0.36, a) if b["hq"] else Color(col.lightened(0.45), 0.95 * a)
		draw_arc(p, r, 0, TAU, 36, rim, 1.6 if not b["hq"] else 2.2, true)
	if b["sel"]:
		var n := 10
		for k in n:
			var a0 := t * 1.6 + k * TAU / n
			draw_arc(p, r + 5.0, a0, a0 + TAU / n * 0.55, 6, Color(1.0, 0.95, 0.7, a), 2.2, true)
	elif b["hov"]:
		draw_arc(p, r + 4.0, 0, TAU, 36, Color(1, 1, 1, 0.75 * a), 1.5, true)
	# numero
	var txt: String = b["text"]
	var fs := int(round(r * (1.05 if txt.length() < 3 else (0.86 if txt.length() < 4 else 0.72))))
	if fog:
		_text(f, p + Vector2(0, -0.5), txt, fs, Color(0.80, 0.84, 0.86, 0.85 * a), 3, Color(0.02, 0.02, 0.03, 0.6 * a))
	else:
		_text(f, p + Vector2(0, -0.5), txt, fs, Color(1, 1, 1, a), 4, Color(0.02, 0.02, 0.03, 0.8 * a))
	# veterani: 1-3 stelline dorate sul bordo inferiore
	var vet: int = b.get("vet", 0)
	if vet > 0:
		for k in vet:
			var ang := PI * 0.5 + (k - (vet - 1) * 0.5) * 0.42
			_star(p + Vector2(cos(ang), sin(ang)) * (r + 1.0), 4.6, Color(1.0, 0.82, 0.32, a))
	# patto di non aggressione: stretta di mano
	if b.get("pact", false):
		var hs: float = b.get("pact_s", 9.5)
		_handshake(p + Vector2(-r - hs - 1.0, r * 0.3), hs, Color(0.72, 0.92, 1.0, a))
	# QG
	if b["hq"]:
		_star(p + Vector2(0, -r - 5.0), 7.0, Color(1.0, 0.84, 0.3, a))
	# battaglia in corso
	if b["battle"]:
		_swords(p + Vector2(r + 11.0, -r * 0.5), 9.0 + pul * 1.5, Color(1.0, 0.42, 0.25, a))
	# attacco in arrivo
	if b["warn"]:
		var wp := p + Vector2(-r - 11.0, -r * 0.45)
		_warn(wp, 9.0, Color(1.0, 0.3, 0.2, a * (0.75 + 0.25 * pul)))
		if b["eta"] != "":
			_text(f, wp + Vector2(0, 15), b["eta"], 11, Color(1.0, 0.75, 0.7, a), 3, Color(0.1, 0.0, 0.0, 0.85 * a))
	# edifici (lettere) e segnali
	var chips: Array = b["chips"]
	if chips.size() > 0 and b["chip_alpha"] > 0.01:
		var ca: float = b["chip_alpha"] * a
		var w := 13.0
		var x0 := p.x - (chips.size() * (w + 2.0) - 2.0) * 0.5
		var y0 := p.y + r + 4.0 + (5.0 if vet > 0 else 0.0)
		for k in chips.size():
			var c: Array = chips[k]
			var rc := Rect2(x0 + k * (w + 2.0), y0, w, 12.0)
			draw_rect(rc, Color(0.03, 0.04, 0.05, 0.85 * ca))
			draw_rect(rc, Color(c[1], 0.8 * ca), false, 1.0)
			_text(f, rc.get_center() + Vector2(0, -0.5), c[0], 10, Color(c[1], ca), 0, Color.BLACK)
	var dots: Array = b["dots"]
	for k in dots.size():
		var dp := p + Vector2(r * 0.78, r * 0.78) + Vector2(k * 7.0, 0)
		draw_circle(dp, 3.6, Color(0.02, 0.02, 0.02, 0.9 * a))
		draw_circle(dp, 2.6, Color(dots[k], a))

func _draw_name(b: Dictionary, f: Font) -> void:
	var a: float = b["name_alpha"]
	var hi: bool = b["sel"] or b["hov"]
	var col := Color(1.0, 0.95, 0.78, a) if hi else Color(0.90, 0.94, 0.92, 0.9 * a)
	var fs: int = b["name_size"]
	_text(f, b["name_pos"], b["name"], fs, col, 5, Color(0.02, 0.03, 0.04, 0.75 * a))
	var tags: String = b["tags"]
	if tags != "":
		_text(f, b["name_pos"] + Vector2(0, fs + 2), tags, fs - 2, Color(1.0, 0.55, 0.42, a), 4, Color(0.05, 0.0, 0.0, 0.8 * a))

func _draw_div(d: Dictionary, f: Font) -> void:
	var a: float = d["alpha"]
	if a <= 0.01:
		return
	var p: Vector2 = d["pos"]
	var col: Color = d["col"]
	var dir: Vector2 = d["dir"]
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var k: float = d.get("big", 1.0)   # piu' grande nella vista d'insieme
	# punta di freccia (direzione di marcia)
	var tip := p + dir * 15.0 * k
	var pts := PackedVector2Array([tip, p + dir * 6.0 * k + side * 7.0 * k, p + dir * 6.0 * k - side * 7.0 * k])
	draw_colored_polygon(pts, Color(0.02, 0.03, 0.04, 0.8 * a))
	var pts2 := PackedVector2Array([tip - dir * 2.0, p + dir * 7.0 * k + side * 5.0 * k, p + dir * 7.0 * k - side * 5.0 * k])
	var hc := Color(1.0, 0.3, 0.2, a) if d["hostile"] else Color(col.lightened(0.3), a)
	draw_colored_polygon(pts2, hc)
	var txt: String = d["text"]
	var fs := int(round(12.0 * k))
	var w := maxf(22.0 * k, f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0 * k)
	var h := 16.0 * k
	var rc := Rect2(p - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(Rect2(rc.position + Vector2(0, 1.5), rc.size), Color(0, 0, 0, 0.35 * a))
	draw_rect(rc, Color(0.03, 0.04, 0.05, 0.9 * a))
	draw_rect(Rect2(rc.position + Vector2(1, 1), rc.size - Vector2(2, 2)), Color(col.darkened(0.3), a))
	draw_rect(rc, Color(1.0, 0.35, 0.25, a) if d["hostile"] else Color(col.lightened(0.4), 0.9 * a), false, 1.2 * k)
	_text(f, rc.get_center(), txt, fs, Color(1, 1, 1, a), 3, Color(0.02, 0.02, 0.03, 0.7 * a))
	if d["naval"]:
		_anchor_icon(rc.position + Vector2(-7, h * 0.5), Color(0.75, 0.9, 1.0, a))
	var vet: int = d.get("vet", 0)
	for q in vet:
		_star(Vector2(rc.get_center().x + (q - (vet - 1) * 0.5) * 7.5, rc.end.y + 1.0), 3.6, Color(1.0, 0.82, 0.32, a))

func _draw_plate(pl: Dictionary, fb: Font, fm: Font) -> void:
	var p: Vector2 = pl["pos"]
	var title: String = pl["title"]
	var sub: String = pl["sub"]
	var col: Color = pl["col"]
	var w := maxf(fb.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, fm.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 24.0
	var rc := Rect2(p, Vector2(w, 40))
	draw_rect(Rect2(rc.position + Vector2(0, 2), rc.size), Color(0, 0, 0, 0.35))
	draw_rect(rc, Color(0.035, 0.05, 0.06, 0.88))
	draw_rect(Rect2(rc.position, Vector2(4, rc.size.y)), col)
	draw_rect(rc, Color(0.55, 0.7, 0.72, 0.45), false, 1.0)
	# angoli da mirino
	for cx in [0, 1]:
		for cy in [0, 1]:
			var c := rc.position + Vector2(rc.size.x * cx, rc.size.y * cy)
			var sx := 1.0 if cx == 0 else -1.0
			var sy := 1.0 if cy == 0 else -1.0
			draw_line(c, c + Vector2(7 * sx, 0), Color(0.85, 0.95, 0.95, 0.8), 1.5)
			draw_line(c, c + Vector2(0, 7 * sy), Color(0.85, 0.95, 0.95, 0.8), 1.5)
	_text(fb, Vector2(rc.position.x + 12, rc.position.y + 13), title, 15, Color(0.95, 0.97, 0.95), 0, Color.BLACK, HORIZONTAL_ALIGNMENT_LEFT)
	_text(fm, Vector2(rc.position.x + 12, rc.position.y + 29), sub, 12, Color(0.68, 0.78, 0.8), 0, Color.BLACK, HORIZONTAL_ALIGNMENT_LEFT)

# ---------------------------------------------------------------- pittogrammi
func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(ang), sin(ang)) * (r if k % 2 == 0 else r * 0.45))
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(c + (q - c) * 1.3)
	draw_colored_polygon(sh, Color(0.05, 0.04, 0.0, col.a * 0.85))
	draw_colored_polygon(pts, col)

func _swords(c: Vector2, r: float, col: Color) -> void:
	var dark := Color(0.08, 0.02, 0.0, col.a * 0.9)
	draw_circle(c, r + 3.0, dark)
	for s in [-1.0, 1.0]:
		var d := Vector2(s, -1).normalized()
		var a := c - d * r * 0.85
		var b := c + d * r * 0.85
		draw_line(a, b, col, 2.4, true)
		var g := c - d * r * 0.35
		var sd := Vector2(-d.y, d.x)
		draw_line(g - sd * r * 0.32, g + sd * r * 0.32, col, 2.0, true)

func _warn(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.7), c + Vector2(-r * 0.95, r * 0.7)])
	var big := PackedVector2Array()
	for q in pts:
		big.append(c + (q - c) * 1.35)
	draw_colored_polygon(big, Color(0.08, 0.0, 0.0, col.a * 0.9))
	draw_colored_polygon(pts, col)
	draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, r * 0.2), Color(0.1, 0, 0, col.a), 2.0)
	draw_circle(c + Vector2(0, r * 0.45), 1.2, Color(0.1, 0, 0, col.a))

## Stretta di mano stilizzata (patto): due avambracci che si incontrano su un dischetto scuro.
func _handshake(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 2.5, Color(0.02, 0.04, 0.06, col.a * 0.92))
	draw_arc(c, r + 2.5, 0, TAU, 28, Color(col, col.a * 0.7), 1.2, true)
	var w := 2.6
	# polsini
	draw_line(c + Vector2(-r * 0.95, r * 0.05), c + Vector2(-r * 0.55, -r * 0.05), col, w + 1.2)
	draw_line(c + Vector2(r * 0.95, r * 0.05), c + Vector2(r * 0.55, -r * 0.05), col, w + 1.2)
	# mani intrecciate
	draw_line(c + Vector2(-r * 0.55, -r * 0.05), c + Vector2(r * 0.15, r * 0.35), col, w, true)
	draw_line(c + Vector2(r * 0.55, -r * 0.05), c + Vector2(-r * 0.15, r * 0.35), col, w, true)
	draw_line(c + Vector2(-r * 0.25, r * 0.12), c + Vector2(r * 0.3, r * 0.42), Color(col, col.a * 0.8), 1.4, true)
	draw_circle(c + Vector2(0, r * 0.2), r * 0.22, col)

## Promozione dei veterani: stelle dorate che salgono e svaniscono sopra il distintivo.
func _draw_promo(pr: Dictionary, f: Font) -> void:
	var u: float = pr["u"]
	var p: Vector2 = pr["pos"]
	var r: float = pr["r"]
	var a := clampf((1.0 - u) * 1.6, 0.0, 1.0) * clampf(u * 8.0, 0.0, 1.0)
	var y := p.y - r - 14.0 - u * 26.0
	var n: int = pr["n"]
	var sc := 1.0 + 0.5 * sin(clampf(u * 3.0, 0.0, 1.0) * PI)
	for k in n:
		_star(Vector2(p.x + (k - (n - 1) * 0.5) * 13.0, y), 6.0 * sc, Color(1.0, 0.84, 0.35, a))
	_text(f, Vector2(p.x, y - 13.0), "VETERANI", 11, Color(1.0, 0.9, 0.6, a), 3, Color(0.1, 0.06, 0.0, 0.8 * a))

func _anchor_icon(c: Vector2, col: Color) -> void:
	draw_circle(c, 6.5, Color(0.02, 0.04, 0.06, col.a * 0.9))
	draw_line(c + Vector2(0, -4), c + Vector2(0, 4), col, 1.4)
	draw_line(c + Vector2(-3, -2), c + Vector2(3, -2), col, 1.2)
	draw_arc(c + Vector2(0, 0.5), 3.5, 0.3, PI - 0.3, 8, col, 1.2)
