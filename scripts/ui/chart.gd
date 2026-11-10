extends Control
## Grafico a linee (andamento nel tempo) disegnato in codice: griglia, assi, serie colorate con area sfumata,
## valore finale etichettato. series = [{name, color, points: PackedVector2Array (x = secondi, y = valore)}].

var series: Array = []
var title := ""
var y_fmt := "%d"
var x_turns := false   # FASE 6: asse x in turni (round) invece che in secondi
var _anim := 1.0

func set_data(s: Array, t: String = "", fmt: String = "%d") -> void:
	series = s
	title = t
	y_fmt = fmt
	_anim = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_anim", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(queue_redraw)
	queue_redraw()

func _process(_dt: float) -> void:
	if _anim < 1.0:
		queue_redraw()

func _nice_step(span: float, n: int) -> float:
	if span <= 0:
		return 1.0
	var raw := span / n
	var mag := pow(10.0, floor(log(raw) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * mag:
			return m * mag
	return 10.0 * mag

func _fmt_axis(v: float) -> String:
	if v >= 10000:
		return "%dk" % int(round(v / 1000.0))
	if absf(v - round(v)) < 0.01:
		return str(int(round(v)))
	return "%.1f" % v

func _draw() -> void:
	var font := UIKit.font("mono", 400)
	var fs := 12
	var r := Rect2(Vector2(46, 10), size - Vector2(46 + 64, 10 + 24))
	if r.size.x < 20 or r.size.y < 20:
		return
	draw_rect(r, Color(0, 0, 0, 0.22))
	var x_max := 1.0
	var y_max := 1.0
	var any := false
	for s in series:
		for p in s["points"]:
			x_max = maxf(x_max, p.x)
			y_max = maxf(y_max, p.y)
			any = true
	if not any:
		draw_string(font, r.get_center() - Vector2(110, 0), "Nessun dato registrato", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.DIM)
		return
	var ys := _nice_step(y_max, 4)
	y_max = ceil(y_max / ys) * ys
	var xs := _nice_step(x_max / 60.0, 6) * 60.0
	if x_turns:
		xs = maxf(1.0, _nice_step(x_max, 6))
	# griglia orizzontale
	var v := 0.0
	while v <= y_max + 0.001:
		var y := r.end.y - r.size.y * v / y_max
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(UIKit.LINE, 0.5 if v > 0 else 1.0), 1.0)
		draw_string(font, Vector2(r.position.x - 6 - 40, y + 4), _fmt_axis(v), HORIZONTAL_ALIGNMENT_RIGHT, 40, fs, UIKit.DIM)
		v += ys
	# griglia verticale (minuti)
	var t := 0.0
	while t <= x_max + 0.001:
		var x := r.position.x + r.size.x * t / x_max
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(UIKit.LINE, 0.25), 1.0)
		draw_string(font, Vector2(x - 20, r.end.y + 16), ("T%d" % int(round(t))) if x_turns else ("%d'" % int(round(t / 60.0))), HORIZONTAL_ALIGNMENT_CENTER, 40, fs, UIKit.DIM)
		t += xs
	# serie
	var cut := x_max * _anim
	var labels := []
	for s in series:
		var col: Color = s["color"]
		var pts := PackedVector2Array()
		for p in s["points"]:
			if p.x > cut:
				break
			pts.append(Vector2(r.position.x + r.size.x * p.x / x_max, r.end.y - r.size.y * p.y / y_max))
		if pts.size() == 0:
			continue
		if pts.size() >= 2:
			var poly := PackedVector2Array(pts)
			poly.append(Vector2(pts[pts.size() - 1].x, r.end.y))
			poly.append(Vector2(pts[0].x, r.end.y))
			var cols := PackedColorArray()
			cols.resize(poly.size())
			cols.fill(Color(col, 0.07))
			if Geometry2D.triangulate_polygon(poly).size() > 0:
				draw_polygon(poly, cols)
			draw_polyline(pts, Color(0, 0, 0, 0.5), 4.0, true)
			draw_polyline(pts, col, 2.2, true)
		var last := pts[pts.size() - 1]
		draw_circle(last, 4.0, col)
		draw_circle(last, 2.0, Color(0.02, 0.03, 0.03))
		var lv: float = (s["points"][mini(s["points"].size() - 1, maxi(0, pts.size() - 1))] as Vector2).y
		labels.append({"y": last.y, "x": last.x, "text": "%d" % int(round(lv)), "col": col})
	# etichette finali senza sovrapposizioni
	labels.sort_custom(func(a, b): return a["y"] < b["y"])
	var prev := -1000.0
	for l in labels:
		var y: float = maxf(l["y"], prev + 14)
		prev = y
		draw_string(UIKit.font("mono", 700), Vector2(r.end.x + 8, y + 4), l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, l["col"].lightened(0.2))
	draw_rect(r, UIKit.LINE2, false, 1.0)
