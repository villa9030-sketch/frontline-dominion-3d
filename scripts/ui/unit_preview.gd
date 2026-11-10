extends SubViewportContainer
## Anteprima 3D di un mezzo (UnitModels) in un SubViewport con mondo proprio: sfondo trasparente, luce da studio,
## rotazione lenta se `spin` (altrimenti viene disegnata una volta sola e resta ferma: costa zero).
## Usa la firma per fazione di UnitModels.build(kind, color, lod, faction) se presente (FASE 4, Agente F4).

var vp: SubViewport
var pivot: Node3D
var cam: Camera3D
var spin := false
var _yaw := 0.0
var _speed := 0.45

static func faction_kind(f: int) -> String:
	# mezzo tipico di ogni dottrina: AAN aviazione, FO corazzati, CP marina, UL tecniche/guerriglia
	return ["jet", "tank", "ship", "truck"][f] if f >= 0 and f < 4 else "tank"

static var _fac_args := -1

static func supports_faction() -> bool:
	if _fac_args < 0:
		_fac_args = 0
		var sc: Script = load("res://scripts/models/unit_models.gd")
		for m in sc.get_script_method_list():
			if String(m["name"]) == "build":
				_fac_args = (m["args"] as Array).size()
	return _fac_args >= 4

static func make_model(kind: String, color: Color, faction: int) -> Node3D:
	if supports_faction():
		var sc: Script = load("res://scripts/models/unit_models.gd")
		return sc.callv("build", [kind, color, 0, faction])
	return UnitModels.build(kind, color, 0)

func setup(kind: String, color: Color, faction: int, sz: Vector2, spinning: bool = false, yaw0: float = -0.65) -> SubViewportContainer:
	custom_minimum_size = sz
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(sz)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.94, 0.84)
	key.rotation_degrees = Vector3(-38, -35, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.55
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-20, 150, 0)
	vp.add_child(rim)
	pivot = Node3D.new()
	vp.add_child(pivot)
	var m := make_model(kind, color, faction)
	var L: float = float(m.get_meta("length", 7.0))
	var H: float = float(m.get_meta("height", 2.5))
	var air: bool = bool(m.get_meta("air", false))
	if kind == "inf":
		L = 4.0
	m.position.y = -H * 0.45 - (0.0 if not air else 0.2)
	pivot.add_child(m)
	# basetta luminosa nel colore della fazione
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = L * 0.56
	cm.bottom_radius = L * 0.58
	cm.height = L * 0.012
	cm.radial_segments = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.darkened(0.7), 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color.darkened(0.35)
	mat.emission_energy_multiplier = 0.18
	cm.material = mat
	disc.mesh = cm
	disc.position.y = m.position.y - (H * 0.6 if air else 0.0) - L * 0.006
	pivot.add_child(disc)
	cam = Camera3D.new()
	cam.fov = 32
	var d := L * 1.12 + H * 0.6
	var eye := Vector3(0, d * 0.42, d)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, -H * 0.1, 0) - eye, Vector3.UP), eye)
	vp.add_child(cam)
	_yaw = yaw0
	pivot.rotation.y = _yaw
	set_spin(spinning)
	return self

func set_spin(on: bool) -> void:
	spin = on
	if vp == null:
		return
	if on:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(dt: float) -> void:
	if spin and pivot != null and is_visible_in_tree():
		_yaw += dt * _speed
		pivot.rotation.y = _yaw
