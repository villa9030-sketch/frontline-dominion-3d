class_name Vfx
extends RefCounted
## Effetti visivi economici e auto-liberanti (Agente F). Tutte statiche; ogni funzione aggiunge un nodo a `parent`
## (posizioni nelle coordinate locali di `parent`) e lo restituisce. Il nodo si libera da solo (Timer interno).
## CPUParticles3D con pochi quad in billboard: niente compilazione shader a scatti, costo trascurabile.

static var _m := {}
static var _quad: QuadMesh = null
static var live_particles := 0      ## particelle attive di tutti gli effetti (budget globale)
static var live_lights := 0         ## luci dinamiche attive degli effetti
const PARTICLE_BUDGET := 2500
const LIGHT_BUDGET := 10
static var _qual := -1.0
static var _qual_frame := -100

## Fattore di qualità: impostazione "quality" di Settings (basso 0.5, medio 0.75, alto 1) × saturazione del budget.
static func _budget_k() -> float:
	var f := Engine.get_process_frames()
	if _qual < 0.0 or f - _qual_frame > 120:
		_qual_frame = f
		_qual = 1.0
		var ml := Engine.get_main_loop() as SceneTree
		if ml != null and ml.root != null:
			var st := ml.root.get_node_or_null("Settings")
			if st != null and st.has_method("get_value"):
				var q := String(st.call("get_value", "quality"))
				_qual = 0.5 if q == "basso" else (0.75 if q == "medio" else 1.0)
	var load_k := clampf(1.0 - float(live_particles - PARTICLE_BUDGET / 2) / float(PARTICLE_BUDGET), 0.2, 1.0)
	return _qual * load_k

# ============================================================== risorse condivise
static func _tex() -> Texture2D:
	if _m.has("tex"):
		return _m["tex"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_m["tex"] = t
	return t

static func _smoke_tex() -> Texture2D:
	if _m.has("stex"):
		return _m["stex"]
	# nuvola: rumore modulato da caduta radiale, generata una volta sola
	var n := FastNoiseLite.new()
	n.seed = 9
	n.frequency = 0.06
	n.fractal_octaves = 3
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 - 0.25 + (v - 0.5) * 0.9, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var sh := 0.78 + 0.22 * v
			img.set_pixel(x, y, Color(sh, sh, sh, a))
	var t := ImageTexture.create_from_image(img)
	_m["stex"] = t
	return t

static func _mat(key: String) -> StandardMaterial3D:
	if _m.has(key):
		return _m[key]
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	match key:
		"fire":
			m.albedo_texture = _smoke_tex()
			m.proximity_fade_enabled = true
			m.proximity_fade_distance = 2.5
		"smoke":
			m.albedo_texture = _smoke_tex()
			m.proximity_fade_enabled = true
			m.proximity_fade_distance = 4.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		"dust":
			m.albedo_texture = _smoke_tex()
			m.proximity_fade_enabled = true
			m.proximity_fade_distance = 3.0
		"debris":
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		"glowp":
			m.albedo_texture = _tex()
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			# lampi grandi: sfumano contro alberi e tetti invece di tagliarli con un bordo netto
			m.proximity_fade_enabled = true
			m.proximity_fade_distance = 3.0
		"glow":
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m[key] = m
	return m

static func _quad_mesh(key: String) -> Mesh:
	var k := "q_" + key
	if _m.has(k):
		return _m[k]
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _mat(key)
	_m[k] = q
	return q

static func _debris_mesh() -> Mesh:
	if _m.has("debris_mesh"):
		return _m["debris_mesh"]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.12, 0.18)
	var mat := _mat("debris").duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	bm.material = mat
	_m["debris_mesh"] = bm
	return bm

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	var mx := 1.0
	for p in points:
		mx = maxf(mx, (p as Vector2).y)
	c.max_value = mx
	for p in points:
		c.add_point(p)
	return c

static func _grad(cols: Array, offs: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	return g

static func _root(parent: Node, pos: Vector3, life: float, n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	parent.add_child(r)
	r.position = pos
	var t := Timer.new()
	t.one_shot = true
	t.autostart = true
	t.wait_time = life
	r.add_child(t)
	t.timeout.connect(r.queue_free)
	return r

static func _parts(r: Node3D, mesh: Mesh, amount: int, life: float, one_shot: bool = true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	var n := maxi(1, int(round(float(amount) * _budget_k())))
	p.amount = n
	live_particles += n
	p.tree_exiting.connect(func() -> void: live_particles -= n)
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.emitting = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(p)
	return p

static func _flash(r: Node3D, color: Color, energy: float, rng_m: float, dur: float) -> void:
	if live_lights >= LIGHT_BUDGET:
		return
	var l := OmniLight3D.new()
	live_lights += 1
	l.tree_exiting.connect(func() -> void: live_lights -= 1)
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	r.add_child(l)
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT)
		tw.tween_callback(l.queue_free)

# ============================================================== API
## Esplosione: lampo, palla di fuoco, anello d'urto, detriti balistici con rimbalzo (alcuni fumanti), fumo nero che sale e si
## disperde col vento, polvere a terra. size 1 ≈ granata da carro (fuoco ~5 m); 3 = bomba/missile pesante.
static func explosion(parent: Node, pos: Vector3, size: float = 1.0) -> Node3D:
	var s := maxf(size, 0.1)
	var r := _root(parent, pos, 10.0 + 2.0 * s, "Explosion")
	# nucleo incandescente brevissimo (additivo)
	var core := _parts(r, _quad_mesh("glowp"), 3, 0.18)
	core.position = Vector3(0, 0.8 * s, 0)
	core.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	core.emission_sphere_radius = 0.4 * s
	core.gravity = Vector3.ZERO
	core.initial_velocity_min = 0.0
	core.initial_velocity_max = 0.5
	core.scale_amount_min = 5.0 * s
	core.scale_amount_max = 7.0 * s
	core.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.2)])
	core.color_ramp = _grad([Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.2, 0.8), Color(1, 0.3, 0.05, 0)], [0.0, 0.5, 1.0])
	# palla di fuoco
	var fire := _parts(r, _quad_mesh("fire"), int(14 + 6 * s), 0.55 + 0.15 * s)
	fire.position = Vector3(0, 1.2 * s, 0)
	fire.angle_min = -180
	fire.angle_max = 180
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.6 * s
	fire.direction = Vector3.UP
	fire.spread = 70.0
	fire.initial_velocity_min = 2.0 * s
	fire.initial_velocity_max = 6.0 * s
	fire.gravity = Vector3(0, 1.5, 0)
	fire.damping_min = 4.0
	fire.damping_max = 7.0
	fire.scale_amount_min = 3.5 * s
	fire.scale_amount_max = 5.5 * s
	fire.scale_amount_curve = _curve([Vector2(0, 0.45), Vector2(0.25, 1.0), Vector2(1, 0.6)])
	fire.color_ramp = _grad([Color(1, 1, 0.9, 1), Color(1, 0.8, 0.35, 1), Color(0.95, 0.42, 0.08, 0.95), Color(0.18, 0.1, 0.06, 0.6), Color(0.08, 0.07, 0.06, 0)], [0.0, 0.18, 0.42, 0.72, 1.0])
	fire.sorting_offset = 3.0
	# anello d'urto: un disco che si allarga a terra in 0.35 s
	var ring := _parts(r, _ring_mesh(), 1, 0.35 + 0.05 * s)
	ring.position = Vector3(0, 0.25, 0)
	ring.gravity = Vector3.ZERO
	ring.initial_velocity_min = 0.0
	ring.initial_velocity_max = 0.0
	ring.scale_amount_min = 16.0 * s
	ring.scale_amount_max = 16.0 * s
	ring.scale_amount_curve = _curve([Vector2(0, 0.08), Vector2(1, 1.0)])
	ring.color_ramp = _grad([Color(1, 0.95, 0.85, 0.55), Color(0.85, 0.8, 0.7, 0.3), Color(0.7, 0.65, 0.55, 0)], [0.0, 0.4, 1.0])
	# fumo nero che sale e si disperde (vento verso +X)
	var smoke := _parts(r, _quad_mesh("smoke"), int(10 + 6 * s), 3.5 + 1.2 * s)
	smoke.position = Vector3(0, 1.5 * s, 0)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.9 * s
	smoke.explosiveness = 0.8
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.initial_velocity_min = 2.0 * s
	smoke.initial_velocity_max = 4.5 * s
	smoke.gravity = Vector3(0.9, 1.6, 0.2)
	smoke.damping_min = 1.2
	smoke.damping_max = 2.0
	smoke.angle_min = -180
	smoke.angle_max = 180
	smoke.angular_velocity_min = -25
	smoke.angular_velocity_max = 25
	smoke.scale_amount_min = 4.0 * s
	smoke.scale_amount_max = 6.5 * s
	smoke.scale_amount_curve = _curve([Vector2(0, 0.45), Vector2(1, 2.4)])
	smoke.color_ramp = _grad([Color(0.08, 0.07, 0.06, 0), Color(0.07, 0.06, 0.06, 0), Color(0.09, 0.08, 0.08, 0.9), Color(0.22, 0.21, 0.2, 0.5), Color(0.38, 0.37, 0.36, 0)], [0.0, 0.1, 0.22, 0.6, 1.0])
	# scintille
	var sp := _parts(r, _quad_mesh("glowp"), int(8 + 4 * s), 0.9)
	sp.position = Vector3(0, 0.8 * s, 0)
	sp.direction = Vector3.UP
	sp.spread = 75.0
	sp.initial_velocity_min = 8.0 * sqrt(s)
	sp.initial_velocity_max = 18.0 * sqrt(s)
	sp.gravity = Vector3(0, -9.8, 0)
	sp.scale_amount_min = 0.25
	sp.scale_amount_max = 0.45
	sp.color_ramp = _grad([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.1, 0)], [0.0, 1.0])
	# polvere a terra
	var dust := _parts(r, _quad_mesh("dust"), int(6 + 3 * s), 2.2)
	dust.position = Vector3(0, 0.6 * s, 0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 1.0 * s
	dust.emission_ring_inner_radius = 0.2 * s
	dust.emission_ring_height = 0.1
	dust.direction = Vector3(1, 0.15, 0)
	dust.spread = 180.0
	dust.flatness = 0.9
	dust.initial_velocity_min = 5.0 * s
	dust.initial_velocity_max = 9.0 * s
	dust.damping_min = 4.0
	dust.damping_max = 6.0
	dust.gravity = Vector3(0, 0.3, 0)
	dust.scale_amount_min = 3.0 * s
	dust.scale_amount_max = 5.0 * s
	dust.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	dust.color_ramp = _grad([Color(0.45, 0.38, 0.28, 0.7), Color(0.5, 0.44, 0.34, 0)], [0.0, 1.0])
	# detriti con fisica semplice (arco balistico + un rimbalzo), due lasciano una scia di fumo
	if r.is_inside_tree():
		var nd := mini(3 + int(2.0 * s), 9)
		nd = maxi(2, int(round(float(nd) * _budget_k())))
		for i in nd:
			_debris_chunk(r, s, i < 2 and s >= 0.8)
	# colonna di fumo che resta sospesa e si allarga lentamente dopo il fungo iniziale
	var lin := _parts(r, _quad_mesh("smoke"), int(5 + 3 * s), 7.0 + 1.5 * s)
	lin.position = Vector3(0, 0.8 * s, 0)
	lin.explosiveness = 0.0
	lin.one_shot = true
	lin.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	lin.emission_sphere_radius = 0.7 * s
	lin.direction = Vector3.UP
	lin.spread = 15.0
	lin.initial_velocity_min = 0.6 * s
	lin.initial_velocity_max = 1.4 * s
	lin.gravity = Vector3(0.45, 0.35, 0.1)
	lin.angle_min = -180
	lin.angle_max = 180
	lin.angular_velocity_min = -8
	lin.angular_velocity_max = 8
	lin.scale_amount_min = 3.0 * s
	lin.scale_amount_max = 4.5 * s
	lin.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.8)])
	lin.color_ramp = _grad([Color(0.2, 0.19, 0.18, 0), Color(0.16, 0.15, 0.14, 0.55), Color(0.36, 0.35, 0.33, 0.3), Color(0.5, 0.49, 0.47, 0)], [0.0, 0.15, 0.6, 1.0])
	_flash(r, Color(1, 0.62, 0.28), 8.0 * s, 12.0 + 10.0 * s, 0.45)
	if s >= 0.6:
		scorch(parent, pos, 2.2 * s)
	return r

static var live_scorch := 0
const SCORCH_BUDGET := 24

## Bruciatura a terra (Decal proiettato verso il basso) che sbiadisce in `life` secondi. Limite globale SCORCH_BUDGET.
static func scorch(parent: Node, pos: Vector3, radius: float = 2.0, life: float = 20.0) -> Node3D:
	if live_scorch >= SCORCH_BUDGET or parent == null or not parent.is_inside_tree():
		return null
	var d := Decal.new()
	d.name = "Scorch"
	d.texture_albedo = _scorch_tex()
	d.size = Vector3(radius * 2.0, 1.8, radius * 2.0)
	d.upper_fade = 0.2
	d.lower_fade = 0.6
	d.normal_fade = 0.4
	d.cull_mask = 1
	d.rotation.y = randf() * TAU
	d.modulate = Color(1, 1, 1, 0.92)
	parent.add_child(d)
	d.position = pos + Vector3(0, 0.3, 0)
	live_scorch += 1
	d.tree_exiting.connect(func() -> void: live_scorch -= 1)
	var tw := d.create_tween()
	tw.tween_interval(life * 0.6)
	tw.tween_property(d, "modulate:a", 0.0, life * 0.4)
	tw.tween_callback(d.queue_free)
	return d

static func _scorch_tex() -> Texture2D:
	if _m.has("scorch_tex"):
		return _m["scorch_tex"]
	var n := FastNoiseLite.new()
	n.seed = 31
	n.frequency = 0.09
	n.fractal_octaves = 3
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var dv := Vector2(x - N * 0.5 + 0.5, y - N * 0.5 + 0.5) / (N * 0.5)
			var ang := atan2(dv.y, dv.x)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			# bordo frastagliato a raggiera
			var edge := 0.78 + 0.16 * sin(ang * 7.0 + v * 3.0) + 0.12 * (v - 0.5)
			var d := dv.length() / edge
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 0.6) * (0.75 + 0.25 * v)
			var c := lerpf(0.03, 0.13, clampf(d * 0.9 + (v - 0.5) * 0.4, 0.0, 1.0))
			img.set_pixel(x, y, Color(c, c * 0.92, c * 0.85, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_m["scorch_tex"] = t
	return t

static func _debris_chunk(r: Node3D, s: float, trail: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _debris_mesh()
	mi.material_override = _chunk_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var k := randf_range(0.8, 2.2) * sqrt(s)
	mi.scale = Vector3(k, k * randf_range(0.6, 1.2), k)
	r.add_child(mi)
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var vh := randf_range(3.0, 9.0) * sqrt(s)
	var vy := randf_range(6.0, 14.0) * sqrt(s)
	var y0 := 0.6 * s
	var g := 9.8
	var t1 := (vy + sqrt(vy * vy + 2.0 * g * y0)) / g        # primo impatto
	var vy2 := vy * 0.3                                       # rimbalzo
	var t2 := 2.0 * vy2 / g
	var spin := Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	var p1 := dir * vh * t1
	var total := t1 + t2
	var fn := func(t: float) -> void:
		if t <= t1:
			mi.position = dir * vh * t + Vector3(0, y0 + vy * t - 0.5 * g * t * t, 0)
			mi.rotation = spin * t
		elif t <= total:
			var u := t - t1
			mi.position = p1 + dir * vh * 0.35 * u + Vector3(0, vy2 * u - 0.5 * g * u * u, 0)
			mi.rotation = spin * (t1 + u * 0.4)
	var tw := r.create_tween()
	tw.tween_method(fn, 0.0, total, total)
	tw.tween_interval(1.5)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.6)
	if trail:
		var tr := _parts(mi, _quad_mesh("smoke"), 14, 1.2, false)
		tr.direction = Vector3.UP
		tr.spread = 180.0
		tr.initial_velocity_min = 0.2
		tr.initial_velocity_max = 0.6
		tr.gravity = Vector3(0.5, 0.8, 0)
		tr.scale_amount_min = 0.6 * s
		tr.scale_amount_max = 1.0 * s
		tr.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.2)])
		tr.color_ramp = _grad([Color(0.1, 0.09, 0.08, 0.7), Color(0.3, 0.3, 0.3, 0)], [0.0, 1.0])
		var tw2 := r.create_tween()
		tw2.tween_interval(total)
		tw2.tween_callback(func() -> void: tr.emitting = false)

static func _chunk_mat() -> Material:
	if _m.has("chunk_mat"):
		return _m["chunk_mat"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.11, 0.09)
	m.roughness = 0.95
	_m["chunk_mat"] = m
	return m

static func _ring_mesh() -> Mesh:
	if _m.has("ring_mesh"):
		return _m["ring_mesh"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.86, 0.95, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = t
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	pm.material = mat
	_m["ring_mesh"] = pm
	return pm

## Incendio persistente (relitti, edifici): fiamme, fumo nero denso, braci e luce tremolante.
## size 1 ≈ carro in fiamme. duration <= 0: brucia finché il nodo esiste (liberarlo per spegnere).
## flames = false: solo fumo (danno leggero).
static func fire(parent: Node, pos: Vector3, size: float = 1.0, duration: float = 0.0, flames: bool = true) -> Node3D:
	var s := maxf(size, 0.1)
	var r: Node3D
	if duration > 0.0:
		r = _root(parent, pos, duration + 7.0, "Fire")
	else:
		r = Node3D.new()
		r.name = "Fire"
		parent.add_child(r)
		r.position = pos
	var parts: Array = []
	var sm := _parts(r, _quad_mesh("smoke"), int(18 * s + 6), 6.0, false)
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.6 * s
	sm.direction = Vector3.UP
	sm.spread = 10.0
	sm.initial_velocity_min = 2.0 * sqrt(s)
	sm.initial_velocity_max = 3.5 * sqrt(s)
	sm.gravity = Vector3(1.0, 0.7, 0.25)
	sm.damping_min = 0.2
	sm.damping_max = 0.4
	sm.angle_min = -180
	sm.angle_max = 180
	sm.angular_velocity_min = -15
	sm.angular_velocity_max = 15
	sm.scale_amount_min = 2.0 * s
	sm.scale_amount_max = 3.2 * s
	sm.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 3.6)])
	if flames:
		sm.color_ramp = _grad([Color(0.06, 0.05, 0.05, 0), Color(0.07, 0.06, 0.06, 0.85), Color(0.18, 0.17, 0.17, 0.5), Color(0.35, 0.35, 0.35, 0)], [0.0, 0.07, 0.5, 1.0])
	else:
		sm.amount = maxi(6, int(sm.amount * 0.7))
		sm.color_ramp = _grad([Color(0.2, 0.19, 0.18, 0), Color(0.2, 0.19, 0.18, 0.75), Color(0.4, 0.4, 0.4, 0.35), Color(0.5, 0.5, 0.5, 0)], [0.0, 0.08, 0.5, 1.0])
	parts.append(sm)
	if flames:
		var fl := _parts(r, _quad_mesh("glowp"), int(10 * s + 4), 0.7, false)
		fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fl.emission_sphere_radius = 0.55 * s
		fl.direction = Vector3.UP
		fl.spread = 15.0
		fl.initial_velocity_min = 1.0 * s
		fl.initial_velocity_max = 2.4 * s
		fl.gravity = Vector3(0.3, 2.0, 0)
		fl.angle_min = -180
		fl.angle_max = 180
		fl.scale_amount_min = 1.4 * s
		fl.scale_amount_max = 2.2 * s
		fl.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.3, 1.0), Vector2(1, 0.2)])
		fl.color_ramp = _grad([Color(1, 0.85, 0.5, 0.9), Color(1, 0.5, 0.12, 0.8), Color(0.6, 0.15, 0.03, 0)], [0.0, 0.4, 1.0])
		parts.append(fl)
		var em := _parts(r, _quad_mesh("glowp"), int(6 * s + 2), 1.8, false)
		em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		em.emission_sphere_radius = 0.6 * s
		em.direction = Vector3.UP
		em.spread = 30.0
		em.initial_velocity_min = 2.0
		em.initial_velocity_max = 4.0
		em.gravity = Vector3(0.8, 1.0, 0)
		em.scale_amount_min = 0.12
		em.scale_amount_max = 0.2
		em.color_ramp = _grad([Color(1, 0.7, 0.3, 1), Color(1, 0.3, 0.05, 0)], [0.0, 1.0])
		parts.append(em)
		if live_lights < LIGHT_BUDGET:
			var l := OmniLight3D.new()
			live_lights += 1
			l.tree_exiting.connect(func() -> void: live_lights -= 1)
			l.light_color = Color(1, 0.55, 0.22)
			l.light_energy = 2.5 * s
			l.omni_range = 7.0 + 4.0 * s
			l.shadow_enabled = false
			l.position = Vector3(0, 1.0 * s, 0)
			r.add_child(l)
			if r.is_inside_tree():
				var tw := l.create_tween().set_loops()
				for i in 4:
					tw.tween_property(l, "light_energy", randf_range(1.6, 3.2) * s, randf_range(0.07, 0.16))
	if duration > 0.0:
		var t := Timer.new()
		t.one_shot = true
		t.autostart = true
		t.wait_time = duration
		r.add_child(t)
		t.timeout.connect(func() -> void:
			for p in parts:
				(p as CPUParticles3D).emitting = false
			for l in r.find_children("*", "OmniLight3D", false, false):
				l.queue_free())
	return r

## Razzo/missile: corpo luminoso che vola da `from` a `to` in `time` s (arco leggero), scia di fumo chiaro che resta sospesa,
## luce del motore. Come shell_trail: l'esplosione all'arrivo la crea chi chiama.
static func rocket_trail(parent: Node, from: Vector3, to: Vector3, time: float = 0.8) -> Node3D:
	var dur := maxf(time, 0.05)
	var r := _root(parent, from, dur + 3.2, "RocketTrail")
	var body := MeshInstance3D.new()
	body.mesh = _flash_mesh()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(body)
	var trail := _parts(body, _quad_mesh("smoke"), 60, 2.8, false)
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0.4, 0.25, 0)
	trail.damping_min = 0.5
	trail.damping_max = 1.0
	trail.angle_min = -180
	trail.angle_max = 180
	trail.scale_amount_min = 0.7
	trail.scale_amount_max = 1.1
	trail.scale_amount_curve = _curve([Vector2(0, 0.35), Vector2(1, 2.6)])
	trail.color_ramp = _grad([Color(0.85, 0.82, 0.78, 0.0), Color(0.82, 0.8, 0.77, 0.6), Color(0.7, 0.7, 0.7, 0.25), Color(0.7, 0.7, 0.7, 0)], [0.0, 0.03, 0.4, 1.0])
	var ex := _parts(body, _quad_mesh("glowp"), 10, 0.12, false)
	ex.direction = Vector3.UP
	ex.spread = 180.0
	ex.initial_velocity_min = 0.0
	ex.initial_velocity_max = 0.3
	ex.gravity = Vector3.ZERO
	ex.scale_amount_min = 0.9
	ex.scale_amount_max = 1.4
	ex.color_ramp = _grad([Color(1, 0.9, 0.6, 1), Color(1, 0.5, 0.1, 0)], [0.0, 1.0])
	if live_lights < LIGHT_BUDGET:
		var l := OmniLight3D.new()
		live_lights += 1
		l.tree_exiting.connect(func() -> void: live_lights -= 1)
		l.light_color = Color(1, 0.7, 0.35)
		l.light_energy = 2.0
		l.omni_range = 8.0
		l.shadow_enabled = false
		body.add_child(l)
	var apex := from.distance_to(to) * 0.06
	var arc := func(f: float) -> void:
		var p := from.lerp(to, f) + Vector3(0, 4.0 * apex * f * (1.0 - f), 0)
		var nf := minf(f + 0.02, 1.0)
		var q := from.lerp(to, nf) + Vector3(0, 4.0 * apex * nf * (1.0 - nf), 0)
		body.position = p - from
		if q.distance_to(p) > 0.001:
			var up := Vector3.UP if absf((q - p).normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			body.basis = Basis.looking_at((q - p).normalized(), up).scaled(Vector3(0.6, 0.6, 1.2))
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_method(arc, 0.0, 1.0, dur)
		tw.tween_callback(func() -> void:
			trail.emitting = false
			ex.emitting = false
			for l in body.find_children("*", "OmniLight3D", false, false):
				l.queue_free()
			body.scale = Vector3(0.001, 0.001, 0.001))
	return r

## Lampo notturno lontano (artiglieria oltre l'orizzonte, bagliori sulle nuvole): luce ampia e un alone additivo, niente particelle.
static func night_flash(parent: Node, pos: Vector3, size: float = 1.0) -> Node3D:
	var s := maxf(size, 0.1)
	var r := _root(parent, pos, 1.2, "NightFlash")
	var halo := _parts(r, _quad_mesh("glowp"), 1, 0.5)
	halo.gravity = Vector3.ZERO
	halo.initial_velocity_max = 0.0
	halo.scale_amount_min = 30.0 * s
	halo.scale_amount_max = 30.0 * s
	halo.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(0.15, 0.7), Vector2(1, 0.3)])
	halo.color_ramp = _grad([Color(1, 0.75, 0.45, 0.5), Color(1, 0.5, 0.2, 0.18), Color(1, 0.4, 0.1, 0)], [0.0, 0.25, 1.0])
	_flash(r, Color(1, 0.7, 0.4), 14.0 * s, 60.0 * s, 0.5)
	return r

## Vampata di sparo in `pos` lungo la direzione `dir` (per esempio dal Marker "Muzzle").
static func muzzle_flash(parent: Node, pos: Vector3, dir: Vector3) -> Node3D:
	var r := _root(parent, pos, 0.9, "MuzzleFlash")
	var d := dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var star := MeshInstance3D.new()
	star.mesh = _flash_mesh()
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(star)
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	star.basis = Basis.looking_at(d, up)
	star.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_property(star, "scale", Vector3(0.3, 0.3, 1.4), 0.07)
		tw.tween_callback(star.queue_free)
	var puff := _parts(r, _quad_mesh("smoke"), 4, 0.8)
	puff.direction = d
	puff.spread = 20.0
	puff.initial_velocity_min = 2.0
	puff.initial_velocity_max = 5.0
	puff.damping_min = 5.0
	puff.damping_max = 8.0
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.4
	puff.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.5)])
	puff.color_ramp = _grad([Color(0.6, 0.58, 0.55, 0.5), Color(0.6, 0.6, 0.6, 0)], [0.0, 1.0])
	_flash(r, Color(1, 0.75, 0.4), 3.0, 7.0, 0.08)
	return r

## Colpo di cannone (carro, obice): vampa a stella, ANELLO di fumo che si allarga davanti alla bocca, getto di fumo lungo la
## canna, polvere sollevata a terra davanti al mezzo e luce breve. size 1 = cannone da carro, 1.6 = obice pesante.
## `ground_y` = quota del terreno sotto la bocca (per la polvere); se non data, 1.8 m sotto `pos`.
static func gun_blast(parent: Node, pos: Vector3, dir: Vector3, size: float = 1.0, ground_y: float = NAN) -> Node3D:
	var s := maxf(size, 0.2)
	var d := dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var r := _root(parent, pos, 2.6, "GunBlast")
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var star := MeshInstance3D.new()
	star.mesh = _flash_mesh()
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.basis = Basis.looking_at(d, up).scaled(Vector3(1.6 * s, 1.6 * s, 2.6 * s))
	star.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	r.add_child(star)
	# anello di fumo perpendicolare alla canna che avanza e si allarga
	var ring := _parts(r, _ring_mesh(), 1, 0.9)
	ring.position = d * 0.8 * s
	ring.direction = d
	ring.spread = 0.0
	ring.gravity = Vector3(0, 0.6, 0)
	ring.initial_velocity_min = 4.0 * s
	ring.initial_velocity_max = 4.0 * s
	ring.damping_min = 5.0
	ring.damping_max = 5.0
	ring.particle_flag_align_y = true
	ring.scale_amount_min = 2.2 * s
	ring.scale_amount_max = 2.2 * s
	ring.scale_amount_curve = _curve([Vector2(0, 0.25), Vector2(0.4, 0.8), Vector2(1, 1.3)])
	ring.color_ramp = _grad([Color(0.85, 0.82, 0.78, 0.7), Color(0.7, 0.68, 0.65, 0.35), Color(0.6, 0.6, 0.6, 0)], [0.0, 0.4, 1.0])
	# getto di fumo in avanti
	var jet := _parts(r, _quad_mesh("smoke"), int(6 + 4 * s), 1.4)
	jet.position = d * 0.5 * s
	jet.direction = d
	jet.spread = 14.0
	jet.initial_velocity_min = 9.0 * s
	jet.initial_velocity_max = 16.0 * s
	jet.damping_min = 9.0
	jet.damping_max = 14.0
	jet.gravity = Vector3(0, 0.8, 0)
	jet.angle_min = -180
	jet.angle_max = 180
	jet.scale_amount_min = 1.0 * s
	jet.scale_amount_max = 1.8 * s
	jet.scale_amount_curve = _curve([Vector2(0, 0.35), Vector2(1, 2.0)])
	jet.color_ramp = _grad([Color(0.95, 0.85, 0.7, 0.75), Color(0.75, 0.72, 0.68, 0.45), Color(0.65, 0.65, 0.65, 0)], [0.0, 0.3, 1.0])
	# polvere sollevata dal terreno davanti al mezzo
	var gy := ground_y if not is_nan(ground_y) else pos.y - 1.8
	var dust := _parts(r, _quad_mesh("dust"), int(5 + 3 * s), 1.8)
	dust.position = Vector3(0, gy - pos.y + 0.3, 0) + Vector3(d.x, 0, d.z).normalized() * 2.5 * s
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 1.2 * s
	dust.direction = Vector3(d.x, 0.5, d.z).normalized()
	dust.spread = 50.0
	dust.initial_velocity_min = 3.0 * s
	dust.initial_velocity_max = 7.0 * s
	dust.damping_min = 4.0
	dust.damping_max = 6.0
	dust.gravity = Vector3(0, 0.4, 0)
	dust.angle_min = -180
	dust.angle_max = 180
	dust.scale_amount_min = 2.0 * s
	dust.scale_amount_max = 3.2 * s
	dust.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.8)])
	dust.color_ramp = _grad([Color(0.5, 0.43, 0.32, 0.55), Color(0.52, 0.47, 0.38, 0)], [0.0, 1.0])
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_property(star, "scale", Vector3(0.4 * s, 0.4 * s, 3.2 * s), 0.06)
		tw.tween_property(star, "scale", Vector3(0.01, 0.01, 0.01), 0.05)
		tw.tween_callback(star.queue_free)
	_flash(r, Color(1, 0.72, 0.38), 5.0 * s, 9.0 + 6.0 * s, 0.1)
	return r

## Bossoli espulsi da una mitragliatrice/cannoncino: piccoli parallelepipedi d'ottone che volano verso `side` e rimbalzano a terra.
static func casings(parent: Node, pos: Vector3, side: Vector3, n: int = 6, size: float = 1.0) -> Node3D:
	var r := _root(parent, pos, 1.6, "Casings")
	var p := _parts(r, _casing_mesh(), n, 1.2)
	p.explosiveness = 0.4
	p.direction = (side.normalized() + Vector3(0, 1.2, 0)).normalized()
	p.spread = 25.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = 0.8 * size
	p.scale_amount_max = 1.2 * size
	p.color = Color(0.85, 0.65, 0.3)
	return r

static func _casing_mesh() -> Mesh:
	if _m.has("casing_mesh"):
		return _m["casing_mesh"]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 0.09)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.9, 0.7, 0.35)
	mat.metallic = 0.9
	mat.roughness = 0.35
	bm.material = mat
	_m["casing_mesh"] = bm
	return bm

## Ombra a terra di un velivolo: quad scuro con sfumatura radiale (unshaded), da posare all'altezza del terreno sotto il mezzo
## e scalare con la lunghezza del modello. Più economico di un Decal e leggibile da lontano.
static func shadow_blob(parent: Node, size: float = 10.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ShadowBlob"
	mi.mesh = _blob_mesh()
	mi.scale = Vector3(size, 1.0, size * 0.75)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _blob_mesh() -> Mesh:
	if _m.has("blob_mesh"):
		return _m["blob_mesh"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = t
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	mat.render_priority = -1
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	pm.material = mat
	_m["blob_mesh"] = pm
	return pm

static func _flash_mesh() -> Mesh:
	if _m.has("flash_mesh"):
		return _m["flash_mesh"]
	# tre lame incrociate a forma di stella, additive
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := PI * float(i) / 3.0
		var x := Vector3(cos(a), sin(a), 0) * 0.35
		var pts := [Vector3.ZERO - x, Vector3.ZERO + x, Vector3(0, 0, -1.3)]
		st.set_color(Color(1, 0.85, 0.5, 1)); st.add_vertex(pts[0])
		st.set_color(Color(1, 0.85, 0.5, 1)); st.add_vertex(pts[1])
		st.set_color(Color(1, 0.5, 0.1, 0)); st.add_vertex(pts[2])
		st.set_color(Color(1, 0.85, 0.5, 1)); st.add_vertex(pts[0])
		st.set_color(Color(1, 0.85, 0.5, 1)); st.add_vertex(pts[1])
		st.set_color(Color(1, 0.6, 0.2, 0)); st.add_vertex(Vector3(0, 0, 0.25))
	var m := st.commit()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	sm.radial_segments = 8
	sm.rings = 4
	var arr := sm.get_mesh_arrays()
	var cols := PackedColorArray()
	for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		cols.append(Color(1, 0.9, 0.6, 0.9))
	arr[Mesh.ARRAY_COLOR] = cols
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := _mat("glow")
	m.surface_set_material(0, mat)
	m.surface_set_material(1, mat)
	_m["flash_mesh"] = m
	return m

## Tracciante luminoso che vola da `from` a `to` (~500 m/s).
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color = Color(1, 0.75, 0.35)) -> Node3D:
	var dist := from.distance_to(to)
	var dur := clampf(dist / 500.0, 0.04, 1.0)
	var r := _root(parent, from, dur + 0.05, "Tracer")
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	var d := (to - from)
	if d.length() > 0.01:
		var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		mi.basis = Basis.looking_at(d.normalized(), up)
	var L := minf(6.0, dist * 0.5)
	mi.scale = Vector3(1, 1, L)
	var mk := "tr_" + color.to_html(false)
	if not _m.has(mk):
		var mat := _mat("glow").duplicate() as StandardMaterial3D
		mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1)
		_m[mk] = mat
	mi.material_override = _m[mk]
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_property(r, "position", to, dur)
	return r

static func _tracer_mesh() -> Mesh:
	if _m.has("tracer_mesh"):
		return _m["tracer_mesh"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.09
	for i in 2:
		var x := Vector3(w, 0, 0) if i == 0 else Vector3(0, w, 0)
		var head := Color(1, 1, 1, 1)
		var tail := Color(1, 1, 1, 0)
		st.set_color(head); st.add_vertex(-x)
		st.set_color(head); st.add_vertex(x)
		st.set_color(tail); st.add_vertex(Vector3(0, 0, 1) + x * 0.3)
		st.set_color(head); st.add_vertex(-x)
		st.set_color(tail); st.add_vertex(Vector3(0, 0, 1) + x * 0.3)
		st.set_color(tail); st.add_vertex(Vector3(0, 0, 1) - x * 0.3)
	var m := st.commit()
	_m["tracer_mesh"] = m
	return m

## Colonna di fumo persistente per `duration` secondi (mezzi distrutti, incendi), poi si dissolve e si libera.
static func smoke(parent: Node, pos: Vector3, duration: float = 12.0) -> Node3D:
	var life := 5.0
	var r := _root(parent, pos, duration + life + 0.5, "Smoke")
	var p := _parts(r, _quad_mesh("smoke"), 22, life, false)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0.8, 0.6, 0.2)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.angle_min = -180
	p.angle_max = 180
	p.angular_velocity_min = -20
	p.angular_velocity_max = 20
	p.scale_amount_min = 2.5
	p.scale_amount_max = 3.8
	p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 3.2)])
	p.color_ramp = _grad([Color(0.08, 0.07, 0.07, 0), Color(0.1, 0.09, 0.09, 0.8), Color(0.25, 0.24, 0.24, 0.45), Color(0.4, 0.4, 0.4, 0)], [0.0, 0.08, 0.5, 1.0])
	var f := _parts(r, _quad_mesh("fire"), 6, 0.6, false)
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.5
	f.direction = Vector3.UP
	f.initial_velocity_min = 0.8
	f.initial_velocity_max = 1.8
	f.scale_amount_min = 1.4
	f.scale_amount_max = 2.4
	f.color_ramp = _grad([Color(1, 0.6, 0.2, 0.8), Color(0.6, 0.2, 0.05, 0)], [0.0, 1.0])
	var t := Timer.new()
	t.one_shot = true
	t.autostart = true
	t.wait_time = maxf(duration, 0.1)
	r.add_child(t)
	t.timeout.connect(func() -> void:
		p.emitting = false
		f.emitting = false)
	return r

## Nuvoletta di polvere (cingoli, ruote, colpi a terra). Molto economica: chiamabile spesso.
static func dust(parent: Node, pos: Vector3) -> Node3D:
	var r := _root(parent, pos, 2.2, "Dust")
	var p := _parts(r, _quad_mesh("dust"), 3, 1.9)
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = -180
	p.angle_max = 180
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.4
	p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.8)])
	p.color_ramp = _grad([Color(0.52, 0.45, 0.34, 0), Color(0.52, 0.45, 0.34, 0.45), Color(0.55, 0.5, 0.42, 0)], [0.0, 0.15, 1.0])
	return r

## Proiettile d'artiglieria con scia di fumo lungo un arco balistico da `from` a `to` in `time` secondi.
## Non esplode da solo: chi lo chiama crea `explosion()` all'arrivo (stesso `time`).
static func shell_trail(parent: Node, from: Vector3, to: Vector3, time: float = 1.5) -> Node3D:
	var dur := maxf(time, 0.1)
	var r := _root(parent, from, dur + 1.6, "ShellTrail")
	var shell := MeshInstance3D.new()
	shell.mesh = _flash_mesh()
	shell.scale = Vector3(0.5, 0.5, 0.5)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(shell)
	var trail := _parts(shell, _quad_mesh("smoke"), 36, 1.4, false)
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3(0, 0.3, 0)
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 0.9
	trail.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.0)])
	trail.color_ramp = _grad([Color(0.75, 0.72, 0.68, 0.55), Color(0.7, 0.7, 0.7, 0)], [0.0, 1.0])
	var apex := maxf(8.0, from.distance_to(to) * 0.28)
	var arc := func(f: float) -> void:
		var p := from.lerp(to, f) + Vector3(0, 4.0 * apex * f * (1.0 - f), 0)
		var nf := minf(f + 0.02, 1.0)
		var q := from.lerp(to, nf) + Vector3(0, 4.0 * apex * nf * (1.0 - nf), 0)
		shell.position = p - from
		if q.distance_to(p) > 0.001:
			var up := Vector3.UP if absf((q - p).normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			shell.basis = Basis.looking_at((q - p).normalized(), up).scaled(Vector3(0.5, 0.5, 0.5))
	if r.is_inside_tree():
		var tw := r.create_tween()
		tw.tween_method(arc, 0.0, 1.0, dur)
		tw.tween_callback(func() -> void:
			trail.emitting = false
			shell.scale = Vector3(0.001, 0.001, 0.001))
	return r

## Scia d'acqua di una nave: schiuma piatta sull'acqua che si allarga e svanisce dietro `pos` (direzione di marcia `dir`).
## Mettere `parent` = la nave (le particelle restano nel mondo, quindi la scia segue la rotta). `size` scala tutto
## (1 = nave da ~120 m; sul tabellone usare ~0.03). `duration` <= 0: persistente finché il genitore esiste.
static func wake(parent: Node, pos: Vector3, dir: Vector3, size: float = 1.0, duration: float = 0.0) -> Node3D:
	var s := maxf(size, 0.005)
	var r: Node3D
	if duration > 0.0:
		r = _root(parent, pos, duration + 7.0, "Wake")
	else:
		r = Node3D.new()
		r.name = "Wake"
		parent.add_child(r)
		r.position = pos
	var d := dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var foam := _parts(r, _foam_mesh(), 70, 8.0, false)
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	foam.emission_sphere_radius = 3.0 * s
	foam.direction = -d
	foam.spread = 14.0
	foam.flatness = 1.0
	foam.gravity = Vector3.ZERO
	foam.initial_velocity_min = 1.0 * s
	foam.initial_velocity_max = 3.0 * s
	foam.damping_min = 0.3 * s
	foam.damping_max = 0.6 * s
	foam.scale_amount_min = 5.0 * s
	foam.scale_amount_max = 8.0 * s
	foam.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.6)])
	foam.angle_min = -180
	foam.angle_max = 180
	foam.particle_flag_rotate_y = true
	foam.color_ramp = _grad([Color(1, 1, 1, 0), Color(0.92, 0.96, 1.0, 0.32), Color(0.8, 0.88, 0.94, 0.1), Color(0.75, 0.85, 0.9, 0)], [0.0, 0.04, 0.4, 1.0])
	# getto di poppa più denso
	var churn := _parts(r, _foam_mesh(), 14, 1.6, false)
	churn.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	churn.emission_sphere_radius = 2.0 * s
	churn.direction = -d
	churn.spread = 10.0
	churn.gravity = Vector3.ZERO
	churn.initial_velocity_min = 3.0 * s
	churn.initial_velocity_max = 5.0 * s
	churn.scale_amount_min = 5.0 * s
	churn.scale_amount_max = 7.0 * s
	churn.color_ramp = _grad([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)], [0.0, 1.0])
	# onda di prua: due baffi di schiuma che si aprono ai lati (la prua è ~118 m avanti alla poppa per size 1)
	var bow := _parts(r, _foam_mesh(), 24, 3.0, false)
	bow.position = d * 112.0 * s
	bow.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bow.emission_sphere_radius = 2.5 * s
	bow.direction = -d
	bow.spread = 55.0
	bow.flatness = 1.0
	bow.gravity = Vector3.ZERO
	bow.initial_velocity_min = 3.5 * s
	bow.initial_velocity_max = 6.0 * s
	bow.damping_min = 0.8 * s
	bow.damping_max = 1.4 * s
	bow.scale_amount_min = 3.0 * s
	bow.scale_amount_max = 4.5 * s
	bow.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.8)])
	bow.particle_flag_rotate_y = true
	bow.color_ramp = _grad([Color(1, 1, 1, 0.75), Color(0.95, 0.97, 1.0, 0.35), Color(0.85, 0.9, 0.95, 0)], [0.0, 0.3, 1.0])
	if duration > 0.0:
		var t := Timer.new()
		t.one_shot = true
		t.autostart = true
		t.wait_time = duration
		r.add_child(t)
		t.timeout.connect(func() -> void:
			foam.emitting = false
			churn.emitting = false
			bow.emitting = false)
	return r

static func _foam_mesh() -> Mesh:
	if _m.has("foam_mesh"):
		return _m["foam_mesh"]
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	var mat := _mat("dust").duplicate() as StandardMaterial3D
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.proximity_fade_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	pm.material = mat
	_m["foam_mesh"] = pm
	return pm
