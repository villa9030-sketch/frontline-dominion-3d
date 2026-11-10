class_name UIIcon
extends Control
## Icone vettoriali semplici disegnate in codice (risorse, unità, edifici, carte, varie).

@export var kind := "money":
	set(v):
		kind = v
		queue_redraw()
@export var tint := Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()

const C_MONEY := Color("#e9c45a")
const C_OIL := Color("#3a3f46")
const C_OIL_HI := Color("#9aa7b5")
const C_STEEL := Color("#9fb4c4")
const C_MAN := Color("#8fd08f")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _col(def: Color) -> Color:
	return tint if tint.a > 0 else def

func _draw() -> void:
	_paint(kind)

func _paint(k: String) -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	var u := s / 16.0   # unità di disegno: icona progettata su 16×16
	match k:
		"money":
			draw_circle(c, 7 * u, _col(C_MONEY))
			draw_arc(c, 5.4 * u, 0, TAU, 20, Color(0.45, 0.33, 0.05, 0.9), 1.2 * u)
			_text("$", c, 9 * u, Color(0.35, 0.24, 0.02))
		"oil":
			var pts := PackedVector2Array()
			pts.append(c + Vector2(0, -7.5) * u)
			for i in 13:
				var a := PI * float(i) / 12.0
				pts.append(c + Vector2(cos(a) * 5.2, 2.2 + sin(a) * 5.0) * u)
			draw_colored_polygon(pts, _col(Color("#2b2f35")) if tint.a == 0 else tint)
			draw_polyline(pts + PackedVector2Array([pts[0]]), C_OIL_HI if tint.a == 0 else tint.lightened(0.3), 1.0 * u, true)
			draw_circle(c + Vector2(-2.0, 2.0) * u, 1.2 * u, Color(1, 1, 1, 0.55))
		"steel":
			_gear(c, 7 * u, 5.2 * u, 8, _col(C_STEEL))
			draw_circle(c, 2.2 * u, Color(0.08, 0.1, 0.12))
		"manpower":
			var col := _col(C_MAN)
			draw_circle(c + Vector2(0, -3.6) * u, 2.8 * u, col)
			draw_arc(c + Vector2(0, 6.5) * u, 6.2 * u, PI + 0.25, TAU - 0.25, 16, col, 3.6 * u)
		"inf":
			var col := _col(Color("#cfe0c8"))
			draw_circle(c + Vector2(-1, -5) * u, 2.2 * u, col)
			draw_line(c + Vector2(-1, -2.5) * u, c + Vector2(-1, 3) * u, col, 2.6 * u)
			draw_line(c + Vector2(-1, 3) * u, c + Vector2(-4, 7.5) * u, col, 2.0 * u)
			draw_line(c + Vector2(-1, 3) * u, c + Vector2(2, 7.5) * u, col, 2.0 * u)
			draw_line(c + Vector2(-5, -1) * u, c + Vector2(6.5, -3.5) * u, col, 1.4 * u)
		"tank":
			var col := _col(Color("#d7c9a6"))
			draw_rect(Rect2(c + Vector2(-7.5, 0) * u, Vector2(15, 4.5) * u), col)
			draw_rect(Rect2(c + Vector2(-4, -3.5) * u, Vector2(7, 3.5) * u), col)
			draw_line(c + Vector2(2.5, -2.2) * u, c + Vector2(8, -3.5) * u, col, 1.4 * u)
			for i in 4:
				draw_circle(c + Vector2(-5.2 + i * 3.5, 5.4) * u, 1.4 * u, col.darkened(0.35))
		"art":
			var col := _col(Color("#d7c9a6"))
			draw_line(c + Vector2(-6, 3) * u, c + Vector2(7, -6) * u, col, 1.8 * u)
			draw_rect(Rect2(c + Vector2(-5, 1) * u, Vector2(8, 3) * u), col)
			draw_circle(c + Vector2(-3.5, 5) * u, 2.4 * u, col.darkened(0.3))
			draw_circle(c + Vector2(2.5, 5) * u, 2.4 * u, col.darkened(0.3))
		"aa":
			var col := _col(Color("#c9d6e6"))
			draw_rect(Rect2(c + Vector2(-7, 2) * u, Vector2(14, 4) * u), col)
			draw_rect(Rect2(c + Vector2(-3, -1) * u, Vector2(6, 3) * u), col)
			draw_line(c + Vector2(-1, -1) * u, c + Vector2(3, -8) * u, col, 1.2 * u)
			draw_line(c + Vector2(1.5, -1) * u, c + Vector2(5.5, -8) * u, col, 1.2 * u)
		"heli":
			var col := _col(Color("#c9d6e6"))
			draw_line(c + Vector2(-8, -5) * u, c + Vector2(8, -5) * u, col, 1.2 * u)
			draw_line(c + Vector2(0, -5) * u, c + Vector2(0, -2) * u, col, 1.2 * u)
			draw_circle(c + Vector2(-1.5, 1) * u, 3.6 * u, col)
			draw_line(c + Vector2(1, 0) * u, c + Vector2(8, -1.5) * u, col, 1.6 * u)
			draw_line(c + Vector2(-5, 6) * u, c + Vector2(3, 6) * u, col, 1.0 * u)
		"jet":
			var col := _col(Color("#c9d6e6"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * u, c + Vector2(1.6, -2) * u, c + Vector2(8, 3) * u,
				c + Vector2(1.6, 2) * u, c + Vector2(1.2, 5.5) * u, c + Vector2(3.5, 8) * u, c + Vector2(-3.5, 8) * u,
				c + Vector2(-1.2, 5.5) * u, c + Vector2(-1.6, 2) * u, c + Vector2(-8, 3) * u, c + Vector2(-1.6, -2) * u]), col)
		"drone":
			var col := _col(Color("#c9d6e6"))
			draw_line(c + Vector2(-5, -5) * u, c + Vector2(5, 5) * u, col, 1.4 * u)
			draw_line(c + Vector2(5, -5) * u, c + Vector2(-5, 5) * u, col, 1.4 * u)
			for d in [Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
				draw_arc(c + d * u, 2.6 * u, 0, TAU, 14, col, 1.0 * u)
			draw_rect(Rect2(c - Vector2(1.8, 1.8) * u, Vector2(3.6, 3.6) * u), col)
		"air":
			_paint("jet")
		"jolly", "star", "hq":
			var col := _col(Color("#ffd84a"))
			_star(c, 7.5 * u, 3.2 * u, col)
		"caserma":
			var col := _col(AMBERC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 6) * u, c + Vector2(0, -6) * u, c + Vector2(7, 6) * u]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 6) * u, c + Vector2(0, 1) * u, c + Vector2(2, 6) * u]), Color(0.1, 0.1, 0.08))
		"fabbrica":
			var col := _col(AMBERC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 7) * u, c + Vector2(-7, -1) * u, c + Vector2(-3, 2) * u,
				c + Vector2(-3, -1) * u, c + Vector2(1, 2) * u, c + Vector2(1, -1) * u, c + Vector2(4, 1) * u,
				c + Vector2(4, -7) * u, c + Vector2(7, -7) * u, c + Vector2(7, 7) * u]), col)
		"aeroporto":
			var col := _col(AMBERC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7) * u, c + Vector2(1.3, -2) * u, c + Vector2(7, 2) * u,
				c + Vector2(1.3, 1.5) * u, c + Vector2(1, 5) * u, c + Vector2(3, 7) * u, c + Vector2(-3, 7) * u,
				c + Vector2(-1, 5) * u, c + Vector2(-1.3, 1.5) * u, c + Vector2(-7, 2) * u, c + Vector2(-1.3, -2) * u]), col)
		"porto", "anchor":
			var col := _col(AMBERC)
			draw_arc(c + Vector2(0, -5) * u, 1.8 * u, 0, TAU, 12, col, 1.3 * u)
			draw_line(c + Vector2(0, -3) * u, c + Vector2(0, 6.5) * u, col, 1.5 * u)
			draw_line(c + Vector2(-3.5, -1) * u, c + Vector2(3.5, -1) * u, col, 1.3 * u)
			draw_arc(c + Vector2(0, 1) * u, 5.5 * u, 0.3, PI - 0.3, 14, col, 1.5 * u)
		"bunker":
			var col := _col(AMBERC)
			draw_colored_polygon(_arc_poly(c + Vector2(0, 5) * u, 7 * u, PI, TAU), col)
			draw_rect(Rect2(c + Vector2(-3, 0.5) * u, Vector2(6, 1.5) * u), Color(0.1, 0.1, 0.08))
			draw_line(c + Vector2(-8, 5.5) * u, c + Vector2(8, 5.5) * u, col, 1.4 * u)
		"impianto":
			var col := _col(AMBERC)
			draw_line(c + Vector2(-5, 7) * u, c + Vector2(0, -7) * u, col, 1.5 * u)
			draw_line(c + Vector2(5, 7) * u, c + Vector2(0, -7) * u, col, 1.5 * u)
			draw_line(c + Vector2(-3.2, 2) * u, c + Vector2(3.2, 2) * u, col, 1.2 * u)
			draw_line(c + Vector2(-1.8, -2.5) * u, c + Vector2(1.8, -2.5) * u, col, 1.2 * u)
			draw_line(c + Vector2(-7, 7) * u, c + Vector2(7, 7) * u, col, 1.5 * u)
		"clock":
			var col := _col(AMBER2C)
			draw_arc(c, 6.5 * u, 0, TAU, 24, col, 1.4 * u)
			draw_line(c, c + Vector2(0, -4.5) * u, col, 1.4 * u)
			draw_line(c, c + Vector2(3.2, 1.5) * u, col, 1.4 * u)
		"terr":
			var col := _col(Color("#cfe0c8"))
			draw_rect(Rect2(c - Vector2(5, 5) * u, Vector2(10, 10) * u), col, false, 1.4 * u)
			draw_rect(Rect2(c - Vector2(2, 2) * u, Vector2(4, 4) * u), col)
		"power":
			var col := _col(Color("#ff9a7a"))
			draw_line(c + Vector2(-6, 6) * u, c + Vector2(6, -6) * u, col, 1.6 * u)
			draw_line(c + Vector2(6, 6) * u, c + Vector2(-6, -6) * u, col, 1.6 * u)
			draw_line(c + Vector2(-6, 2) * u, c + Vector2(-2, 6) * u, col, 1.6 * u)
			draw_line(c + Vector2(6, 2) * u, c + Vector2(2, 6) * u, col, 1.6 * u)
		"card":
			var col := _col(Color("#8ac8ff"))
			draw_rect(Rect2(c + Vector2(-4.5, -6.5) * u, Vector2(9, 13) * u), col, false, 1.3 * u)
			draw_rect(Rect2(c + Vector2(-2, -3) * u, Vector2(4, 6) * u), col)
		"pause":
			var col := _col(TEXTC)
			draw_rect(Rect2(c + Vector2(-5, -6) * u, Vector2(3.4, 12) * u), col)
			draw_rect(Rect2(c + Vector2(1.6, -6) * u, Vector2(3.4, 12) * u), col)
		"play":
			var col := _col(TEXTC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4.5, -6.5) * u, c + Vector2(6.5, 0) * u, c + Vector2(-4.5, 6.5) * u]), col)
		"sound", "mute":
			var col := _col(TEXTC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -2.5) * u, c + Vector2(-3.5, -2.5) * u, c + Vector2(1, -6.5) * u,
				c + Vector2(1, 6.5) * u, c + Vector2(-3.5, 2.5) * u, c + Vector2(-7, 2.5) * u]), col)
			if k == "sound":
				draw_arc(c + Vector2(1, 0) * u, 3.5 * u, -0.9, 0.9, 10, col, 1.2 * u)
				draw_arc(c + Vector2(1, 0) * u, 6.0 * u, -0.9, 0.9, 12, col, 1.2 * u)
			else:
				draw_line(c + Vector2(3, -3) * u, c + Vector2(8, 3) * u, RED_C, 1.5 * u)
				draw_line(c + Vector2(8, -3) * u, c + Vector2(3, 3) * u, RED_C, 1.5 * u)
		"menu":
			var col := _col(TEXTC)
			for i in 3:
				draw_rect(Rect2(c + Vector2(-6, -5 + i * 4.2) * u, Vector2(12, 1.8) * u), col)
		"supply":
			draw_circle(c, 4 * u, _col(Color("#7fe08f")))
		"nosupply":
			draw_arc(c, 5 * u, 0, TAU, 16, _col(Color("#ffa14a")), 1.6 * u)
		"sabotage":
			var col := _col(RED_C)
			draw_colored_polygon(PackedVector2Array([c + Vector2(1.5, -8) * u, c + Vector2(-4.5, 1) * u, c + Vector2(-0.5, 1) * u,
				c + Vector2(-2, 8) * u, c + Vector2(4.5, -1.5) * u, c + Vector2(0.5, -1.5) * u]), col)
		"truce":
			var col := _col(Color("#bfe8c8"))
			draw_rect(Rect2(c + Vector2(-5, -7) * u, Vector2(1.4, 14) * u), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3.6, -7) * u, c + Vector2(6, -4.5) * u, c + Vector2(-3.6, -1.5) * u]), col)
		"alert":
			var col := _col(RED_C)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7) * u, c + Vector2(7.5, 6.5) * u, c + Vector2(-7.5, 6.5) * u]), col)
			draw_rect(Rect2(c + Vector2(-0.8, -2.5) * u, Vector2(1.6, 5) * u), Color(0.1, 0.05, 0.03))
			draw_rect(Rect2(c + Vector2(-0.8, 3.6) * u, Vector2(1.6, 1.6) * u), Color(0.1, 0.05, 0.03))
		"reinforce":
			var col := _col(Color("#7fe08f"))
			draw_rect(Rect2(c + Vector2(-1.5, -6.5) * u, Vector2(3, 13) * u), col)
			draw_rect(Rect2(c + Vector2(-6.5, -1.5) * u, Vector2(13, 3) * u), col)
		"tech":
			var col := _col(Color("#8ac8ff"))
			draw_arc(c, 6.5 * u, 0, TAU, 6, col, 1.4 * u)
			draw_circle(c, 2.2 * u, col)
		"target":
			var col := _col(RED_C)
			draw_arc(c, 6 * u, 0, TAU, 20, col, 1.3 * u)
			draw_arc(c, 2.5 * u, 0, TAU, 12, col, 1.3 * u)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * 4.5 * u, c + d * 8 * u, col, 1.3 * u)
		"gear":
			var col := _col(TEXTC)
			_gear(c, 7.2 * u, 5.4 * u, 8, col)
			draw_circle(c, 2.4 * u, Color(0.05, 0.08, 0.08))
		"save":
			var col := _col(TEXTC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6.5, -6.5) * u, c + Vector2(4, -6.5) * u, c + Vector2(6.5, -4) * u,
				c + Vector2(6.5, 6.5) * u, c + Vector2(-6.5, 6.5) * u]), col)
			draw_rect(Rect2(c + Vector2(-4, -6.5) * u, Vector2(7, 4) * u), Color(0.05, 0.08, 0.08))
			draw_rect(Rect2(c + Vector2(-4, 1) * u, Vector2(8, 5.5) * u), Color(0.05, 0.08, 0.08))
		"load", "folder":
			var col := _col(TEXTC)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -5.5) * u, c + Vector2(-2, -5.5) * u, c + Vector2(0, -3.5) * u,
				c + Vector2(7, -3.5) * u, c + Vector2(7, 6) * u, c + Vector2(-7, 6) * u]), col)
			draw_line(c + Vector2(-7, -1.5) * u, c + Vector2(7, -1.5) * u, Color(0.05, 0.08, 0.08), 1.0 * u)
		"exit":
			var col := _col(TEXTC)
			draw_rect(Rect2(c + Vector2(-6.5, -6.5) * u, Vector2(8, 13) * u), col, false, 1.4 * u)
			draw_line(c + Vector2(-1, 0) * u, c + Vector2(7, 0) * u, col, 1.6 * u)
			draw_line(c + Vector2(4, -3) * u, c + Vector2(7, 0) * u, col, 1.6 * u)
			draw_line(c + Vector2(4, 3) * u, c + Vector2(7, 0) * u, col, 1.6 * u)
		"chart":
			var col := _col(TEXTC)
			draw_line(c + Vector2(-7, 7) * u, c + Vector2(7, 7) * u, col, 1.2 * u)
			draw_line(c + Vector2(-7, 7) * u, c + Vector2(-7, -7) * u, col, 1.2 * u)
			draw_polyline(PackedVector2Array([c + Vector2(-5, 4) * u, c + Vector2(-1, -1) * u, c + Vector2(2, 2) * u, c + Vector2(6.5, -5) * u]), _col(AMBERC), 1.6 * u, true)
		"info", "bulb":
			var col := _col(AMBER2C)
			draw_circle(c + Vector2(0, -1.5) * u, 5 * u, col)
			draw_rect(Rect2(c + Vector2(-2.5, 3) * u, Vector2(5, 2) * u), col)
			draw_rect(Rect2(c + Vector2(-1.8, 5.6) * u, Vector2(3.6, 1.4) * u), col)
			draw_line(c + Vector2(-1.4, -2) * u, c + Vector2(0, 1.5) * u, Color(0.1, 0.08, 0.02), 1.0 * u)
			draw_line(c + Vector2(1.4, -2) * u, c + Vector2(0, 1.5) * u, Color(0.1, 0.08, 0.02), 1.0 * u)
		"trophy":
			var col := _col(AMBER2C)
			draw_colored_polygon(_arc_poly(c + Vector2(0, -4) * u, 5.5 * u, 0, PI), col)
			draw_rect(Rect2(c + Vector2(-5.5, -6.5) * u, Vector2(11, 2.6) * u), col)
			draw_rect(Rect2(c + Vector2(-1, 1) * u, Vector2(2, 3.5) * u), col)
			draw_rect(Rect2(c + Vector2(-4, 4.5) * u, Vector2(8, 2.2) * u), col)
			draw_arc(c + Vector2(-5.5, -3) * u, 2.2 * u, PI * 0.5, PI * 1.5, 8, col, 1.2 * u)
			draw_arc(c + Vector2(5.5, -3) * u, 2.2 * u, -PI * 0.5, PI * 0.5, 8, col, 1.2 * u)
		"skull":
			var col := _col(RED_C)
			draw_circle(c + Vector2(0, -1.5) * u, 6 * u, col)
			draw_rect(Rect2(c + Vector2(-3.5, 2) * u, Vector2(7, 5) * u), col)
			draw_circle(c + Vector2(-2.3, -1.5) * u, 1.7 * u, Color(0.08, 0.04, 0.03))
			draw_circle(c + Vector2(2.3, -1.5) * u, 1.7 * u, Color(0.08, 0.04, 0.03))
			for i in 3:
				draw_line(c + Vector2(-2 + i * 2, 4.5) * u, c + Vector2(-2 + i * 2, 7) * u, Color(0.08, 0.04, 0.03), 0.8 * u)
		"news":
			var col := _col(AMBER2C)
			draw_rect(Rect2(c + Vector2(-7, -5.5) * u, Vector2(14, 11) * u), col, false, 1.3 * u)
			draw_rect(Rect2(c + Vector2(-5, -3.5) * u, Vector2(4.5, 4) * u), col)
			for i in 3:
				draw_line(c + Vector2(1, -3 + i * 2) * u, c + Vector2(5, -3 + i * 2) * u, col, 1.0 * u)
			draw_line(c + Vector2(-5, 3) * u, c + Vector2(5, 3) * u, col, 1.0 * u)
		"globe":
			var col := _col(TEXTC)
			draw_arc(c, 6.5 * u, 0, TAU, 24, col, 1.3 * u)
			draw_arc(c, 6.5 * u, -PI / 2, PI / 2, 16, col, 1.0 * u)
			draw_line(c + Vector2(0, -6.5) * u, c + Vector2(0, 6.5) * u, col, 1.0 * u)
			draw_line(c + Vector2(-6.5, 0) * u, c + Vector2(6.5, 0) * u, col, 1.0 * u)
			draw_line(c + Vector2(-5.5, -3.3) * u, c + Vector2(5.5, -3.3) * u, col, 0.8 * u)
			draw_line(c + Vector2(-5.5, 3.3) * u, c + Vector2(5.5, 3.3) * u, col, 0.8 * u)
		"eye":
			var col := _col(TEXTC)
			draw_arc(c + Vector2(0, 5) * u, 8 * u, -PI * 0.8, -PI * 0.2, 14, col, 1.3 * u)
			draw_arc(c + Vector2(0, -5) * u, 8 * u, PI * 0.2, PI * 0.8, 14, col, 1.3 * u)
			draw_circle(c, 2.6 * u, col)
		"pact":
			# due anelli intrecciati (alleanza / patto)
			var col := _col(Color("#8fe0b0"))
			draw_arc(c + Vector2(-2.6, 0) * u, 4.6 * u, 0, TAU, 22, col, 1.5 * u)
			draw_arc(c + Vector2(2.6, 0) * u, 4.6 * u, 0, TAU, 22, col, 1.5 * u)
			draw_circle(c, 1.1 * u, col)
		"fog":
			# nuvola con righe di foschia
			var col := _col(Color("#a9b8c4"))
			draw_circle(c + Vector2(-3, -0.5) * u, 3.2 * u, col)
			draw_circle(c + Vector2(1, -2.5) * u, 4 * u, col)
			draw_circle(c + Vector2(4.5, 0) * u, 2.8 * u, col)
			draw_rect(Rect2(c + Vector2(-6, 0) * u, Vector2(13, 2.6) * u), col)
			draw_line(c + Vector2(-6.5, 4.6) * u, c + Vector2(4, 4.6) * u, col, 1.1 * u)
			draw_line(c + Vector2(-3.5, 6.8) * u, c + Vector2(6.5, 6.8) * u, col, 1.1 * u)
		"vet":
			# gallone da veterano
			var col := _col(Color("#ffd84a"))
			for i in 2:
				var y := (-3.0 + i * 4.5)
				draw_polyline(PackedVector2Array([c + Vector2(-6, y) * u, c + Vector2(0, y + 4) * u, c + Vector2(6, y) * u]), col, 1.8 * u, true)
		"flag":
			# bandierina su asta (scenari / obiettivi)
			var col := _col(TEXTC)
			draw_line(c + Vector2(-5, -7) * u, c + Vector2(-5, 7.5) * u, col, 1.5 * u)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4.4, -6.8) * u, c + Vector2(6.5, -4.6) * u, c + Vector2(2.5, -2.2) * u,
				c + Vector2(6.5, 0.2) * u, c + Vector2(-4.4, 1.2) * u]), col)
		"help":
			var col := _col(TEXTC)
			draw_arc(c, 6.8 * u, 0, TAU, 24, col, 1.3 * u)
			_text("?", c, 11 * u, col)
		"trench":
			# trincea: profilo a zig-zag con sacchetti di sabbia
			var col := _col(AMBERC)
			draw_polyline(PackedVector2Array([c + Vector2(-7.5, 1) * u, c + Vector2(-4, 1) * u, c + Vector2(-2.5, 5) * u, c + Vector2(2.5, 5) * u,
				c + Vector2(4, 1) * u, c + Vector2(7.5, 1) * u]), col, 1.6 * u, true)
			for i in 4:
				draw_circle(c + Vector2(-5.2 + i * 3.5, -1.6) * u, 1.6 * u, col)
			draw_line(c + Vector2(-7.5, 7) * u, c + Vector2(7.5, 7) * u, Color(col, 0.6), 1.0 * u)
		"mines":
			# mina anticarro: disco con spoletta e punte
			var col := _col(AMBERC)
			draw_circle(c + Vector2(0, 1.5) * u, 5.4 * u, col)
			draw_circle(c + Vector2(0, 1.5) * u, 2.2 * u, Color(0.12, 0.1, 0.05))
			for i in 6:
				var a := TAU * i / 6.0
				draw_line(c + Vector2(0, 1.5) * u + Vector2(cos(a), sin(a)) * 5.4 * u, c + Vector2(0, 1.5) * u + Vector2(cos(a), sin(a)) * 7.2 * u, col, 1.3 * u)
		"move":
			# freccia di spostamento (doppia punta)
			var col := _col(Color("#8ad6ff"))
			draw_line(c + Vector2(-7, 2) * u, c + Vector2(4, 2) * u, col, 2.0 * u)
			draw_colored_polygon(PackedVector2Array([c + Vector2(7.5, 2) * u, c + Vector2(2.5, -2.5) * u, c + Vector2(2.5, 6.5) * u]), col)
			draw_line(c + Vector2(-7, -4) * u, c + Vector2(0, -4) * u, Color(col, 0.55), 1.4 * u)
		"attack":
			# freccia d'attacco (punta piena, rossa)
			var col := _col(Color("#ff8a6a"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -1.6) * u, c + Vector2(1.5, -1.6) * u, c + Vector2(1.5, -5.5) * u,
				c + Vector2(7.5, 0) * u, c + Vector2(1.5, 5.5) * u, c + Vector2(1.5, 1.6) * u, c + Vector2(-7, 1.6) * u]), col)
		"turn":
			# clessidra (turno)
			var col := _col(AMBER2C)
			draw_line(c + Vector2(-5, -7) * u, c + Vector2(5, -7) * u, col, 1.5 * u)
			draw_line(c + Vector2(-5, 7) * u, c + Vector2(5, 7) * u, col, 1.5 * u)
			draw_polyline(PackedVector2Array([c + Vector2(-4, -7) * u, c + Vector2(0, 0) * u, c + Vector2(-4, 7) * u]), col, 1.3 * u, true)
			draw_polyline(PackedVector2Array([c + Vector2(4, -7) * u, c + Vector2(0, 0) * u, c + Vector2(4, 7) * u]), col, 1.3 * u, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-2.6, 7) * u, c + Vector2(0, 3) * u, c + Vector2(2.6, 7) * u]), col)
		"check":
			var col := _col(Color("#7fe08f"))
			draw_polyline(PackedVector2Array([c + Vector2(-6, 0) * u, c + Vector2(-2, 4.5) * u, c + Vector2(6.5, -5) * u]), col, 2.2 * u, true)
		_:
			draw_circle(c, 4 * u, _col(TEXTC))

const AMBERC := Color("#f2b13c")
const AMBER2C := Color("#ffd57a")
const TEXTC := Color("#dbe5d6")
const RED_C := Color("#ff6a5a")

func _text(t: String, c: Vector2, fs: float, col: Color) -> void:
	var f := UIKit.font("sans", 800)
	var fsz := maxi(6, int(fs))
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	draw_string(f, Vector2(c.x - w * 0.5, c.y + fsz * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)

func _star(c: Vector2, r1: float, r2: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var r := r1 if i % 2 == 0 else r2
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)

func _gear(c: Vector2, ro: float, ri: float, teeth: int, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := teeth * 4
	for i in n:
		var a := TAU * float(i) / n
		var r := ro if (i % 4 == 1 or i % 4 == 2) else ri
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)

func _arc_poly(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var a := lerpf(a0, a1, float(i) / 16.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
