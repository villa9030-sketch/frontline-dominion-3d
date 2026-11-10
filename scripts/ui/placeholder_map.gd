extends Control
## SEGNAPOSTO 2D del tabellone (usato SOLO finché scenes/world_map.tscn non esiste).
## Stessa interfaccia di WorldMap (bind, set_selection, set_targets, set_marks, set_drag, clear_drag, focus, segnali).

signal territory_clicked(idx: int, button: int, shift: bool)
signal territory_hovered(idx: int)
signal drag_released(from_idx: int, to_idx: int)

var game = null
var sel := -1
var targets := []
var marks := []
var mark_color := Color.WHITE
var drag_from := -1
var drag_to := Vector3.ZERO
var hover := -1
var _press_t := -1
var _press_pos := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func bind(g) -> void:
	game = g
	queue_redraw()

func map_to_world(x: float, y: float) -> Vector3:
	return Vector3((x - 800.0) * 0.1, 0, (y - 450.0) * 0.1)

func screen_to_world(p: Vector2) -> Vector3:
	var m := _to_map(p)
	return map_to_world(m.x, m.y)

func set_selection(i: int) -> void: sel = i; queue_redraw()
func set_targets(l: Array) -> void: targets = l; queue_redraw()
func set_marks(l: Array, c: Color) -> void: marks = l; mark_color = c; queue_redraw()
func set_drag(f: int, w: Vector3) -> void: drag_from = f; drag_to = w; queue_redraw()
func clear_drag() -> void: drag_from = -1; queue_redraw()
func focus(_i: int) -> void: pass

func _scale() -> float:
	return minf(size.x / 1600.0, size.y / 900.0)
func _off() -> Vector2:
	return (size - Vector2(1600, 900) * _scale()) * 0.5
func _to_map(p: Vector2) -> Vector2:
	return (p - _off()) / _scale()
func _to_scr(x: float, y: float) -> Vector2:
	return _off() + Vector2(x, y) * _scale()

func terr_at(p: Vector2) -> int:
	var m := _to_map(p)
	var best := -1
	var bd := 1e9
	for T in Data.TERRITORIES:
		for b in T["blobs_px"]:
			var d := m.distance_to(Vector2(b[0], b[1])) - float(b[2]) * 1.15
			if d < bd:
				bd = d
				best = T["idx"]
	return best if bd < 6 else -1

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var t := terr_at(e.position)
		if t != hover:
			hover = t
			territory_hovered.emit(t)
			queue_redraw()
	elif e is InputEventMouseButton:
		var t := terr_at(e.position)
		if e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
			territory_clicked.emit(t, e.button_index, e.shift_pressed)
			if e.button_index == MOUSE_BUTTON_LEFT:
				_press_t = t
				_press_pos = e.position
		elif not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if _press_t >= 0 and t >= 0 and t != _press_t and e.position.distance_to(_press_pos) > 9:
				drag_released.emit(_press_t, t)
			_press_t = -1

func _process(_dt: float) -> void:
	if game != null:
		queue_redraw()

func _draw() -> void:
	var s := _scale()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.09, 0.12))
	for gx in range(0, 1601, 100):
		draw_line(_to_scr(gx, 0), _to_scr(gx, 900), Color(0.3, 0.5, 0.6, 0.08), 1)
	for gy in range(0, 901, 100):
		draw_line(_to_scr(0, gy), _to_scr(1600, gy), Color(0.3, 0.5, 0.6, 0.08), 1)
	for a in Data.LAND_LINKS + Data.SEA_LINKS:
		var A: Dictionary = Data.TERRITORIES[Data.TERR_INDEX[a[0]]]
		var B: Dictionary = Data.TERRITORIES[Data.TERR_INDEX[a[1]]]
		if absf(A["x"] - B["x"]) < 800:
			draw_line(_to_scr(A["x"], A["y"]), _to_scr(B["x"], B["y"]), Color(0.6, 0.7, 0.7, 0.10), 1)
	var tset := {}
	for t in targets:
		tset[int(t["idx"])] = true
	for T in Data.TERRITORIES:
		var o: int = game.terr[T["idx"]]["owner"] if game != null else -1
		var col := Data.faction_color(game.players[o]["faction"]) if (game != null and o >= 0) else Color(0.42, 0.45, 0.48)
		col = col.darkened(0.25)
		if T["idx"] == hover:
			col = col.lightened(0.15)
		for b in T["blobs_px"]:
			draw_circle(_to_scr(b[0], b[1]), float(b[2]) * s * 1.1, col)
	for T in Data.TERRITORIES:
		var p := _to_scr(T["x"], T["y"])
		if marks.has(T["idx"]):
			draw_arc(p, 26 * s, 0, TAU, 32, mark_color, 2)
		if tset.has(T["idx"]):
			draw_arc(p, 22 * s, 0, TAU, 32, Color(1, 0.85, 0.4, 0.9), 2)
		if T["idx"] == sel:
			draw_arc(p, 30 * s, 0, TAU, 40, Color.WHITE, 2.5)
		if game != null:
			var n := Data.total_units(game.terr[T["idx"]]["forces"])
			var f := UIKit.font("mono", 700)
			var fs := maxi(8, int(15 * s))
			draw_circle(p, 12 * s, Color(0, 0, 0, 0.55))
			var w := f.get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, p + Vector2(-w / 2, fs * 0.36), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var fn := UIKit.font("sans", 600)
		var fs2 := maxi(7, int(11 * s))
		var w2 := fn.get_string_size(T["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(fn, p + Vector2(-w2 / 2, 26 * s), T["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, 0.6))
	if game != null:
		for d in game.divisions:
			draw_circle(_to_scr(d["x"], d["y"]), 6 * s, Data.faction_color(game.players[d["owner"]]["faction"]))
	if drag_from >= 0:
		var A: Dictionary = Data.TERRITORIES[drag_from]
		var to := _to_scr(drag_to.x * 10 + 800, drag_to.z * 10 + 450)
		draw_line(_to_scr(A["x"], A["y"]), to, Color(1, 0.85, 0.4), 3)
