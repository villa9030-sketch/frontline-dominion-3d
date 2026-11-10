class_name SceneFade
extends CanvasLayer
## Velo nero sopra tutto per le transizioni tabellone ↔ battaglia (dissolvenze in chiusura e in apertura).
## Un solo nodo per albero: `SceneFade.of(nodo)` lo crea sotto la radice la prima volta.
##   await SceneFade.of(self).fade_to(1.0, 0.5)   # a nero in mezzo secondo
##   SceneFade.of(self).fade_to(0.0, 0.8)         # riapre (senza aspettare)

var rect: ColorRect
var _a := 0.0
var _goal := 0.0
var _speed := 2.0

static func of(n: Node) -> SceneFade:
	var r := n.get_tree().root
	var f := r.get_node_or_null("SceneFade")
	if f == null:
		f = SceneFade.new()
		f.name = "SceneFade"
		r.add_child(f)
	return f as SceneFade

func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	add_child(rect)

## Porta il velo all'opacità `a` in `dur` secondi; si può attendere con await.
func fade_to(a: float, dur: float) -> void:
	_goal = clampf(a, 0.0, 1.0)
	_speed = 1.0 / maxf(dur, 0.01)
	while absf(_a - _goal) > 0.0005 and is_inside_tree():
		await get_tree().process_frame

## Velo subito a `a` (es. nero prima di cambiare scena).
func set_now(a: float) -> void:
	_a = clampf(a, 0.0, 1.0)
	_goal = _a
	_apply()

func opacity() -> float:
	return _a

func _process(dt: float) -> void:
	if absf(_a - _goal) < 0.0005:
		return
	_a = move_toward(_a, _goal, dt * _speed)
	_apply()

func _apply() -> void:
	rect.color = Color(0, 0, 0, _a)
	rect.visible = _a > 0.001
