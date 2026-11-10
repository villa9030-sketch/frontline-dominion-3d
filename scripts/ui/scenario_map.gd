extends Control
## Mappa in miniatura (disegnata in codice) per le schede degli scenari: territori colorati per proprietario
## alla partenza dello scenario, QG con la stella, territori chiave evidenziati con un anello.
## Dati: owners[i] (−1 neutrale), colors {player_idx: Color}, hqs [idx], focus [idx], human (player idx).

var owners: Array = []
var colors := {}
var hqs: Array = []
var focus: Array = []
var human := -1
var accent := Color("#f2b13c")
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func set_data(d: Dictionary) -> void:
	owners = d.get("owners", [])
	colors = d.get("colors", {})
	hqs = d.get("hqs", [])
	focus = d.get("focus", [])
	human = int(d.get("human", -1))
	accent = d.get("accent", accent)
	queue_redraw()

func _process(dt: float) -> void:
	if not focus.is_empty() and is_visible_in_tree():
		_t += dt
		queue_redraw()

func _xf() -> Array:
	# piano mappa 1600×900 → rettangolo del controllo (adatta mantenendo le proporzioni)
	var s := minf(size.x / 1600.0, size.y / 900.0)
	var off := (size - Vector2(1600, 900) * s) * 0.5
	return [s, off]

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.035, 0.07, 0.085))
	# reticolo da sala operativa
	var g := Color(0.35, 0.6, 0.65, 0.07)
	var step := size.x / 16.0
	for i in range(1, 16):
		draw_line(Vector2(i * step, 0), Vector2(i * step, size.y), g, 1.0)
	for j in range(1, int(size.y / step) + 1):
		draw_line(Vector2(0, j * step), Vector2(size.x, j * step), g, 1.0)
	var xf := _xf()
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	var neutral := Color(Data.NEUTRAL_COLOR)
	# costa (alone) poi riempimento
	for T in Data.TERRITORIES:
		for b in T["blobs_px"]:
			draw_circle(off + Vector2(b[0], b[1]) * s, (float(b[2]) + 14.0) * s, Color(0.3, 0.55, 0.6, 0.10))
	for T in Data.TERRITORIES:
		var i := int(T["idx"])
		var o := int(owners[i]) if i < owners.size() else -1
		var c: Color = colors.get(o, neutral) if o >= 0 else neutral
		var fill := Color(c.darkened(0.25), 0.92) if o >= 0 else Color(0.28, 0.31, 0.32, 0.85)
		for b in T["blobs_px"]:
			draw_circle(off + Vector2(b[0], b[1]) * s, float(b[2]) * s, fill)
	# rialzo per i territori del giocatore
	if human >= 0:
		for T in Data.TERRITORIES:
			var i := int(T["idx"])
			if i < owners.size() and int(owners[i]) == human:
				for b in T["blobs_px"]:
					draw_circle(off + Vector2(b[0], b[1]) * s, float(b[2]) * s * 0.55, Color(1, 1, 1, 0.10))
	# territori chiave
	for i in focus:
		if int(i) < 0 or int(i) >= Data.TERRITORIES.size():
			continue
		var T: Dictionary = Data.TERRITORIES[int(i)]
		var p := off + Vector2(T["x"], T["y"]) * s
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_arc(p, (26.0 + 6.0 * pulse) * s * 2.0, 0, TAU, 32, Color(accent, 0.55 + 0.35 * pulse), 2.0, true)
		draw_arc(p, 14.0 * s * 2.0, 0, TAU, 24, Color(accent, 0.9), 1.5, true)
	# QG
	for i in hqs:
		if int(i) < 0 or int(i) >= Data.TERRITORIES.size():
			continue
		var T: Dictionary = Data.TERRITORIES[int(i)]
		var p := off + Vector2(T["x"], T["y"]) * s
		_star(p, 7.0, 3.0, Color(0, 0, 0, 0.6), Vector2(1, 1))
		_star(p, 6.5, 2.7, Color("#ffd84a"), Vector2.ZERO)
	# vignetta e cornice
	draw_rect(r, Color(UIKit.LINE2, 0.9), false, 1.0)

func _star(c: Vector2, r1: float, r2: float, col: Color, shift: Vector2) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		var rr := r1 if k % 2 == 0 else r2
		pts.append(c + shift + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
