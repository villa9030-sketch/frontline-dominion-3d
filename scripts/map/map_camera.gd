class_name MapCamera
extends Camera3D
## Telecamera RTS del tabellone: pan (WASD/frecce, bordi dello schermo, tasto centrale), zoom con la rotella
## (l'inclinazione cambia con lo zoom), rotazione Q/E (o Maiusc + tasto centrale), volo morbido verso un punto (fly_to).
## Legge da /root/Settings (se esiste) camera_speed ed edge_scroll.

const MIN_DIST := 9.0
const MAX_DIST := 140.0
const PITCH_NEAR := 36.0
const PITCH_FAR := 72.0

var target := Vector3(0, 0, 3)
var dist := 110.0
var yaw := 0.0
var bounds := Rect2(-80, -45, 160, 90)
var edge_pan := true
var speed_mul := 1.0
var _goal_target := Vector3(0, 0, 3)
var _goal_dist := 110.0
var _goal_yaw := 0.0
var _mmb := false
# volo
var _fly := false
var _fly_t := 0.0
var _fly_dur := 1.0
var _fly_a := Vector3.ZERO
var _fly_b := Vector3.ZERO
var _fly_da := 0.0
var _fly_db := 0.0
var _fly_arc := 0.0

func _ready() -> void:
	fov = 38.0
	near = 0.1
	far = 900.0
	_goal_target = target
	_goal_dist = dist
	_goal_yaw = yaw
	var st = get_node_or_null("/root/Settings")
	if st != null:
		_read_settings(st)
		if st.has_signal("changed"):
			st.changed.connect(func(_k): _read_settings(st))
	_apply()

func _read_settings(st) -> void:
	if not st.has_method("get_value"):
		return
	var cs = st.get_value("camera_speed")
	if cs != null:
		speed_mul = clampf(float(cs), 0.3, 3.0)
	var es = st.get_value("edge_scroll")
	if es != null:
		edge_pan = bool(es)

func zoom_t() -> float:
	return clampf((dist - MIN_DIST) / (MAX_DIST - MIN_DIST), 0.0, 1.0)

func is_flying() -> bool:
	return _fly

func set_view(t: Vector3, d: float, y: float = 0.0, instant: bool = false) -> void:
	_fly = false
	_goal_target = Vector3(t.x, 0.0, t.z)
	_goal_dist = clampf(d, MIN_DIST, MAX_DIST)
	_goal_yaw = y
	if instant:
		target = _goal_target
		dist = _goal_dist
		yaw = _goal_yaw
		_apply()

func focus_point(p: Vector3, d: float = -1.0) -> void:
	fly_to(p, d if d > 0 else _goal_dist)

## Volo cinematografico: curva morbida (inizio e fine lenti); se il salto è lungo la telecamera si alza a metà strada.
func fly_to(p: Vector3, d: float) -> void:
	var b := Vector3(clampf(p.x, bounds.position.x, bounds.end.x), 0.0, clampf(p.z, bounds.position.y, bounds.end.y))
	var db := clampf(d, MIN_DIST, MAX_DIST)
	var L := Vector2(b.x - target.x, b.z - target.z).length()
	if L < 0.3 and absf(db - dist) < 0.5:
		return
	_fly = true
	_fly_t = 0.0
	_fly_a = target
	_fly_b = b
	_fly_da = dist
	_fly_db = db
	_fly_dur = clampf(0.55 + L / 90.0 + absf(db - dist) / 160.0, 0.55, 1.6)
	_fly_arc = clampf(L * 0.45 - minf(dist, db) * 0.15, 0.0, 55.0)
	_goal_target = b
	_goal_dist = db

func _cancel_fly() -> void:
	if _fly:
		_fly = false
		_goal_target = target
		_goal_dist = dist

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cancel_fly()
			_goal_dist = clampf(_goal_dist * 0.86, MIN_DIST, MAX_DIST)
			_zoom_toward(mb.position, 0.16)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cancel_fly()
			_goal_dist = clampf(_goal_dist / 0.86, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb = mb.pressed
			if mb.pressed:
				_cancel_fly()
	elif ev is InputEventMouseMotion and _mmb:
		var mm := ev as InputEventMouseMotion
		if mm.shift_pressed or mm.alt_pressed:
			_goal_yaw -= mm.relative.x * 0.006
		else:
			var k := dist * 0.0018
			var r := mm.relative.rotated(-yaw)
			_goal_target -= Vector3(r.x, 0, r.y) * k
			target -= Vector3(r.x, 0, r.y) * k

func _zoom_toward(screen_pos: Vector2, amount: float) -> void:
	var o := project_ray_origin(screen_pos)
	var d := project_ray_normal(screen_pos)
	if absf(d.y) < 0.001:
		return
	var t := -o.y / d.y
	if t <= 0:
		return
	var p := o + d * t
	_goal_target = _goal_target.lerp(Vector3(p.x, 0, p.z), amount)

func _process(delta: float) -> void:
	var mv := Vector2.ZERO
	var focused := DisplayServer.window_is_focused()
	if focused and not _text_focus():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
		if Input.is_key_pressed(KEY_Q): _goal_yaw += delta * 1.6
		if Input.is_key_pressed(KEY_E): _goal_yaw -= delta * 1.6
		if edge_pan and not _mmb:
			var vp := get_viewport()
			var m := vp.get_mouse_position()
			var sz := vp.get_visible_rect().size
			var inside := m.x >= 0 and m.y >= 0 and m.x < sz.x and m.y < sz.y
			if inside:
				if m.x < 4: mv.x -= 1
				elif m.x > sz.x - 5: mv.x += 1
				if m.y < 4: mv.y -= 1
				elif m.y > sz.y - 5: mv.y += 1
	if mv != Vector2.ZERO:
		_cancel_fly()
		var r := mv.normalized().rotated(-yaw) * (12.0 + dist * 0.9) * speed_mul * delta
		_goal_target += Vector3(r.x, 0, r.y)
	_goal_target.x = clampf(_goal_target.x, bounds.position.x, bounds.end.x)
	_goal_target.z = clampf(_goal_target.z, bounds.position.y, bounds.end.y)
	if _fly:
		_fly_t += delta / _fly_dur
		var u := clampf(_fly_t, 0.0, 1.0)
		var e := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)   # smootherstep
		target = _fly_a.lerp(_fly_b, e)
		dist = lerpf(_fly_da, _fly_db, e) + sin(PI * u) * _fly_arc
		if u >= 1.0:
			_fly = false
	else:
		var k := 1.0 - exp(-delta * 9.0)
		target = target.lerp(_goal_target, k)
		dist = lerpf(dist, _goal_dist, k)
	var ky := 1.0 - exp(-delta * 9.0)
	yaw = lerp_angle(yaw, _goal_yaw, ky)
	_apply()

func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f is LineEdit or f is TextEdit)

func _apply() -> void:
	var pitch := deg_to_rad(lerpf(PITCH_NEAR, PITCH_FAR, pow(zoom_t(), 0.7)))
	var off := Vector3(0, sin(pitch), cos(pitch)) * dist
	off = off.rotated(Vector3.UP, yaw)
	global_position = target + off
	look_at(target, Vector3.UP)
