class_name BattleCamera
extends Camera3D
## Telecamera RTS: pan (WASD/frecce/bordi/tasto centrale), rotella = zoom con inclinazione, Q/E rotazione, limiti.
## WASD muove SEMPRE la telecamera (i comandi delle unità sono su altri tasti).

var terrain: BattleTerrain
var target := Vector3.ZERO      # punto a terra osservato
var yaw := 0.0                  # rad: la camera sta in (sin yaw, cos yaw) rispetto al bersaglio
var dist := 90.0
var _t_target := Vector3.ZERO
var _t_yaw := 0.0
var _t_dist := 90.0
var min_dist := 16.0
var max_dist := 235.0
const NEAR_MAX := 235.0         # oltre questa distanza: vista d'insieme (pedine tattiche, inclinazione quasi zenitale)
var limit := Vector2(235, 150)
var edge_pan := true
var keys_enabled := true
var mouse_enabled := true       # falso nelle demo per screenshot (il mouse reale non deve muovere la vista)
var speed_mul := 1.0
var _mid_drag := false
var _rot_drag := false
var shake := 0.0
# Fase 8 — modalità foto: telecamera libera (WASD avanti/lati, Q/E quota, mouse col tasto destro o Maiusc = guarda,
# rotella = zoom ottico/FOV); al termine torna all'inquadratura RTS di prima.
var photo := false
var _ph_pos := Vector3.ZERO
var _ph_yaw := 0.0
var _ph_pitch := 0.0
var _ph_fov := 48.0
var _ph_look := false
var _ph_vel := Vector3.ZERO

func _ready() -> void:
	fov = 48.0
	near = 0.5
	far = 4000.0

## Entra/esce dalla modalità foto. Entrando parte dall'inquadratura attuale; uscendo ripristina FOV e vista RTS.
func set_photo(on: bool) -> void:
	if on == photo:
		return
	photo = on
	if on:
		_ph_pos = global_position
		var fwd := -global_transform.basis.z
		_ph_yaw = atan2(-fwd.x, -fwd.z)
		_ph_pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_ph_fov = fov
		_ph_vel = Vector3.ZERO
		_ph_look = false
	else:
		fov = 48.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_apply()

func _photo_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_ph_fov = clampf(_ph_fov * 0.9, 8.0, 95.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_ph_fov = clampf(_ph_fov / 0.9, 8.0, 95.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_ph_look = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and _ph_look:
		var mm := e as InputEventMouseMotion
		var k := 0.0028 * (_ph_fov / 48.0)
		_ph_yaw -= mm.relative.x * k
		_ph_pitch = clampf(_ph_pitch - mm.relative.y * k, -1.5, 1.5)

func _photo_process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var b := Basis.from_euler(Vector3(_ph_pitch, _ph_yaw, 0.0))
	var fwd := -b.z
	var rt := b.x
	var mv := Vector3.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv += fwd
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv -= fwd
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv -= rt
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv += rt
		if Input.is_physical_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEUP): mv += Vector3.UP
		if Input.is_physical_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEDOWN): mv -= Vector3.UP
	var spd := 22.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0) * speed_mul
	if mv.length_squared() > 0.001:
		mv = mv.normalized() * spd
	_ph_vel = _ph_vel.lerp(mv, 1.0 - exp(-dt * 8.0))
	_ph_pos += _ph_vel * dt
	_ph_pos.x = clampf(_ph_pos.x, -limit.x - 120.0, limit.x + 120.0)
	_ph_pos.z = clampf(_ph_pos.z, -limit.y - 120.0, limit.y + 120.0)
	if terrain != null:
		var h := terrain.height(_ph_pos.x, _ph_pos.z)
		if terrain.sim.sea:
			h = maxf(h, 0.0)
		_ph_pos.y = clampf(_ph_pos.y, h + 1.2, h + 600.0)
	fov = lerpf(fov, _ph_fov, 1.0 - exp(-dt * 10.0))
	global_transform = Transform3D(b, _ph_pos)

## Limiti e zoom massimo dal campo (metri, semiassi): a zoom massimo si vede tutto il campo di battaglia.
func configure_field(hx: float, hz: float) -> void:
	limit = Vector2(hx + 35.0, hz + 37.5)
	max_dist = maxf(NEAR_MAX, hx * 1.9)
	far = maxf(4000.0, max_dist * 4.0)

func place(tgt: Vector3, d: float, yw: float) -> void:
	_t_target = tgt; target = tgt
	_t_dist = clampf(d, min_dist, max_dist); dist = _t_dist
	_t_yaw = yw; yaw = yw
	_apply()

## Sposta dolcemente la vista su un punto (minimappa, F, allarmi).
func go_to(p: Vector3, d := -1.0) -> void:
	_t_target = Vector3(p.x, 0, p.z)
	if d > 0:
		_t_dist = clampf(d, min_dist, max_dist)

func pitch_for(d: float) -> float:
	if d > NEAR_MAX and max_dist > NEAR_MAX:
		return deg_to_rad(lerpf(60.0, 70.0, clampf((d - NEAR_MAX) / (max_dist - NEAR_MAX), 0.0, 1.0)))
	var f := inverse_lerp(min_dist, NEAR_MAX, d)
	return deg_to_rad(lerpf(32.0, 60.0, pow(clampf(f, 0.0, 1.0), 0.65)))

## 0 = vicino, 1 = vista d'insieme a zoom massimo.
func overview_k() -> float:
	if max_dist <= NEAR_MAX:
		return 0.0
	return clampf((dist - NEAR_MAX * 0.8) / (max_dist - NEAR_MAX * 0.8), 0.0, 1.0)

func zoom_by(steps: float, toward := Vector3.INF) -> void:
	var nd := clampf(_t_dist * pow(0.86, steps), min_dist, max_dist)
	if toward.x != INF and steps > 0:
		# zoom verso il cursore
		var k := 1.0 - nd / _t_dist
		_t_target += (Vector3(toward.x, 0, toward.z) - Vector3(_t_target.x, 0, _t_target.z)) * k * 0.6
	_t_dist = nd

func _unhandled_input(e: InputEvent) -> void:
	if photo:
		_photo_input(e)
		return
	if not mouse_enabled:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.0, _ground_under(mb.position))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(-1.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.alt_pressed or mb.ctrl_pressed or mb.shift_pressed:
				_rot_drag = mb.pressed
			else:
				_mid_drag = mb.pressed
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _mid_drag:
			var k := _t_dist * 0.0021
			var fw := Vector3(sin(yaw), 0, cos(yaw))
			var rt := Vector3(cos(yaw), 0, -sin(yaw))
			_t_target += (-rt * mm.relative.x - fw * mm.relative.y) * k
		elif _rot_drag:
			_t_yaw -= mm.relative.x * 0.006

func _ground_under(sp: Vector2) -> Vector3:
	if terrain == null:
		return Vector3.INF
	return terrain.raycast(project_ray_origin(sp), project_ray_normal(sp))

func _process(delta: float) -> void:
	if photo:
		_photo_process(delta)
		return
	var dt := minf(delta, 0.05)
	var pan := Vector2.ZERO
	if keys_enabled and not Input.is_key_pressed(KEY_CTRL):
		if Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A): pan.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D): pan.x += 1
		if Input.is_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W): pan.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S): pan.y += 1
		if Input.is_physical_key_pressed(KEY_Q): _t_yaw += 1.6 * dt
		if Input.is_physical_key_pressed(KEY_E): _t_yaw -= 1.6 * dt
		if Input.is_key_pressed(KEY_PAGEUP) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD): zoom_by(2.0 * dt)
		if Input.is_key_pressed(KEY_PAGEDOWN) or Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT): zoom_by(-2.0 * dt)
	if edge_pan and not _mid_drag and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var sz := vp.get_visible_rect().size
		var m := 6.0
		if mp.x >= 0 and mp.y >= 0 and mp.x <= sz.x and mp.y <= sz.y:
			if mp.x < m: pan.x -= 1
			elif mp.x > sz.x - m: pan.x += 1
			if mp.y < m: pan.y -= 1
			elif mp.y > sz.y - m: pan.y += 1
	if pan != Vector2.ZERO:
		var spd := (35.0 + _t_dist * (1.0 if _t_dist < NEAR_MAX else 0.85)) * dt * speed_mul
		var fw := Vector3(-sin(yaw), 0, -cos(yaw))
		var rt := Vector3(cos(yaw), 0, -sin(yaw))
		_t_target += (rt * pan.x - fw * pan.y) * spd
	_t_target.x = clampf(_t_target.x, -limit.x, limit.x)
	_t_target.z = clampf(_t_target.z, -limit.y, limit.y)
	var k := 1.0 - exp(-dt * 9.0)
	target = target.lerp(_t_target, k)
	dist = lerpf(dist, _t_dist, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	if shake > 0:
		shake = maxf(0.0, shake - dt * 2.5)
	_apply()

func _apply() -> void:
	var gy := 0.0
	if terrain != null:
		gy = terrain.height(target.x, target.z)
		gy = maxf(gy, 0.0) if terrain.sim.sea else gy
	var p := pitch_for(dist)
	var off := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	var look := Vector3(target.x, gy, target.z)
	var pos := look + off
	if terrain != null:
		var h := terrain.height(pos.x, pos.z) + 4.0
		if pos.y < h:
			pos.y = h
	if shake > 0:
		pos += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake * 0.6
	global_position = pos
	look_at(look, Vector3.UP)

## Quattro angoli dello schermo proiettati a terra (per la minimappa). Se un raggio non tocca il suolo usa il piano y=0.
func view_corners() -> Array:
	var sz := get_viewport().get_visible_rect().size
	var out := []
	for sp in [Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, sz.y), Vector2(0, sz.y)]:
		var o := project_ray_origin(sp)
		var d := project_ray_normal(sp)
		var hit := Vector3.INF
		if d.y < -0.02:
			var t := (target.y - o.y) / d.y
			hit = o + d * minf(t, far * 0.5)
		else:
			hit = o + Vector3(d.x, 0, d.z).normalized() * far * 0.5
		out.append(Vector2(hit.x, hit.z))
	return out
