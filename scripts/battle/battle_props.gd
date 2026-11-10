class_name BattleProps
extends RefCounted
## Mesh procedurali di riserva per la battaglia (alberi, rocce) e modelli segnaposto delle unità.
## Se esistono le classi dell'Agente F (UnitModels / Props / Vfx) la battaglia usa quelle: vedi `ext()`.

static var _mats := {}
static var _ext_cache := {}

## Script di una classe globale (class_name) se registrata, altrimenti null. Evita dipendenze a compilazione.
static func ext(cls: String):
	if _ext_cache.has(cls):
		return _ext_cache[cls]
	var res = null
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == cls:
			var path := String(c["path"])
			if ResourceLoader.exists(path):
				res = load(path)
				# classe esterna in lavorazione (errore di sintassi): si usano i segnaposto, niente crash
				if res is Script and not (res as Script).can_instantiate():
					push_warning("BattleProps: %s non compila, uso i segnaposto" % cls)
					res = null
			break
	_ext_cache[cls] = res
	return res

static func vc_mat(key: String, rough := 0.9, cull_off := false, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

# ---------------------------------------------------------------------------- primitive su SurfaceTool
static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, seg: int, col0: Color, col1: Color) -> void:
	var ax := (b - a).normalized()
	var up := Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT
	var u := ax.cross(up).normalized()
	var v := ax.cross(u).normalized()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var p00 := a + d0 * r0
		var p01 := a + d1 * r0
		var p10 := b + d0 * r1
		var p11 := b + d1 * r1
		st.set_color(col0); st.set_normal(d0); st.add_vertex(p00)
		st.set_color(col1); st.set_normal(d0); st.add_vertex(p10)
		st.set_color(col0); st.set_normal(d1); st.add_vertex(p01)
		st.set_color(col1); st.set_normal(d0); st.add_vertex(p10)
		st.set_color(col1); st.set_normal(d1); st.add_vertex(p11)
		st.set_color(col0); st.set_normal(d1); st.add_vertex(p01)

static func _cone(st: SurfaceTool, base: Vector3, h: float, r: float, seg: int, col_b: Color, col_t: Color, rng: RandomNumberGenerator, droop := 0.0) -> void:
	var top := base + Vector3(0, h, 0)
	var pts := []
	for i in seg:
		var a := TAU * i / seg + rng.randf() * 0.3
		var rr := r * (0.8 + rng.randf() * 0.4)
		pts.append(base + Vector3(cos(a) * rr, -droop * rng.randf(), sin(a) * rr))
	for i in seg:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % seg]
		var n := (p1 - top).cross(p0 - top).normalized()
		var nm := (n + Vector3.UP * 0.35).normalized()
		st.set_color(col_t); st.set_normal(Vector3.UP); st.add_vertex(top)
		st.set_color(col_b); st.set_normal(nm); st.add_vertex(p1)
		st.set_color(col_b); st.set_normal(nm); st.add_vertex(p0)
		# fondo
		st.set_color(col_b.darkened(0.5)); st.set_normal(Vector3.DOWN); st.add_vertex(base)
		st.set_color(col_b.darkened(0.5)); st.set_normal(Vector3.DOWN); st.add_vertex(p0)
		st.set_color(col_b.darkened(0.5)); st.set_normal(Vector3.DOWN); st.add_vertex(p1)

static func _blob(st: SurfaceTool, c: Vector3, rad: Vector3, col: Color, rng: RandomNumberGenerator, jitter := 0.25) -> void:
	var sm := SphereMesh.new()
	sm.radial_segments = 8
	sm.rings = 5
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var disp := {}
	for i in idx.size():
		var vi := idx[i]
		var p: Vector3 = verts[vi]
		var key := Vector3i(roundi(p.x * 100), roundi(p.y * 100), roundi(p.z * 100))
		if not disp.has(key):
			disp[key] = 1.0 + (rng.randf() - 0.5) * 2.0 * jitter
		var k: float = disp[key]
		var pp := Vector3(p.x * 2 * rad.x, p.y * rad.y, p.z * 2 * rad.z) * k
		var shade := 0.72 + 0.28 * clampf(p.y + 0.5, 0, 1)
		st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
		st.set_normal((norms[vi] + Vector3(0, 0.2, 0)).normalized())
		st.add_vertex(c + pp)

static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b: Basis = Basis.IDENTITY) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var cc := c + b * (n * h)
		var uu := b * (u * h)
		var vv := b * (v * h)
		var nn := (b * n).normalized()
		var shade := 1.0 if n.y > 0.5 else (0.6 if n.y < -0.5 else 0.85)
		var colf := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
		var p := [cc - uu - vv, cc + uu - vv, cc + uu + vv, cc - uu + vv]
		for tri in [[0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.set_color(colf); st.set_normal(nn); st.add_vertex(p[k])

# ---------------------------------------------------------------------------- vegetazione
static func tree_mesh(kind: String, variant := 0) -> Mesh:
	var P = ext("Props")
	if P != null and P.has_method("tree_mesh") and kind in ["pine", "broadleaf", "palm", "dead", "snowpine", "bush", "birch"]:
		var m = P.tree_mesh("pine", "snow") if kind == "snowpine" else P.tree_mesh(kind)
		if m is Mesh:
			return m
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 977
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.28, 0.2, 0.13)
	match kind:
		"pine", "snowpine":
			var H := 11.0
			_cyl(st, Vector3.ZERO, Vector3(0, H * 0.4, 0), 0.28, 0.18, 6, bark, bark)
			var g0 := Color(0.11, 0.2, 0.1)
			var g1 := Color(0.2, 0.32, 0.16)
			var layers := 4
			for i in layers:
				var f := float(i) / layers
				var y := H * (0.18 + f * 0.6)
				var r := 2.6 * (1.0 - f * 0.68)
				var cb := g0.lerp(g1, f * 0.6)
				var ct := g1
				if kind == "snowpine":
					ct = Color(0.86, 0.9, 0.94)
					cb = cb.lerp(Color(0.75, 0.8, 0.85), 0.35)
				_cone(st, Vector3(0, y, 0), H * 0.36 * (1.0 - f * 0.25), r, 9, cb, ct, rng, 0.6)
		"broadleaf":
			_cyl(st, Vector3.ZERO, Vector3(0, 4.2, 0), 0.32, 0.22, 6, bark, bark)
			_cyl(st, Vector3(0, 3.2, 0), Vector3(1.3, 5.0, 0.4), 0.16, 0.1, 5, bark, bark)
			var gc := Color(0.2, 0.32, 0.13)
			_blob(st, Vector3(0, 6.2, 0), Vector3(2.7, 4.4, 2.7), gc, rng)
			for i in 4:
				var a := TAU * i / 4 + rng.randf()
				_blob(st, Vector3(cos(a) * 1.7, 5.4 + rng.randf() * 1.6, sin(a) * 1.7), Vector3(1.6, 2.8, 1.6), gc.lerp(Color(0.3, 0.4, 0.15), rng.randf() * 0.5), rng)
		"bush":
			var gc := Color(0.2, 0.3, 0.12)
			for i in 3:
				var a := TAU * i / 3 + rng.randf()
				_blob(st, Vector3(cos(a) * 0.6, 0.6, sin(a) * 0.6), Vector3(0.9, 1.4, 0.9), gc.lerp(Color(0.32, 0.38, 0.16), rng.randf() * 0.6), rng, 0.3)
		"palm":
			var p := Vector3.ZERO
			var dir := Vector3(0.12, 1, 0.05).normalized()
			for i in 6:
				var q := p + dir * 1.6
				_cyl(st, p, q, 0.3 - i * 0.025, 0.28 - i * 0.025, 6, bark.lightened(0.15), bark.lightened(0.2))
				p = q
				dir = (dir + Vector3(0.05, 0, 0)).normalized()
			var leaf := Color(0.25, 0.38, 0.14)
			for i in 9:
				var a := TAU * i / 9 + rng.randf() * 0.3
				var d := Vector3(cos(a), 0, sin(a))
				var side := d.cross(Vector3.UP).normalized() * 0.5
				var tip := p + d * 4.2 + Vector3(0, -1.6, 0)
				var mid := p + d * 2.2 + Vector3(0, 0.4, 0)
				for tri in [[p, mid + side, mid - side], [mid + side, tip, mid - side]]:
					var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
					if n.y < 0: n = -n
					for v in tri:
						st.set_color(leaf); st.set_normal(n); st.add_vertex(v)
		_:  # dead
			_cyl(st, Vector3.ZERO, Vector3(0, 6.5, 0), 0.3, 0.12, 6, bark.darkened(0.2), bark)
			for i in 5:
				var a := TAU * i / 5 + rng.randf()
				var y := 2.5 + rng.randf() * 3.5
				_cyl(st, Vector3(0, y, 0), Vector3(cos(a) * 2.2, y + 1.6, sin(a) * 2.2), 0.12, 0.04, 4, bark.darkened(0.2), bark)
	var mesh := st.commit()
	mesh.surface_set_material(0, vc_mat("foliage", 0.92, true))
	return mesh

## Ciuffo d'erba (9 fili) per MultiMesh; `dry` = sterpaglia.
static func grass_mesh(dry := false) -> Mesh:
	var key := "grass_dry" if dry else "grass"
	if _mats.has(key + "_mesh"):
		return _mats[key + "_mesh"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if not dry else 99
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var side := d.cross(Vector3.UP).normalized() * (0.035 + rng.randf() * 0.02)
		var r0 := rng.randf() * 0.12
		var base := d * r0
		var hgt := 0.32 + rng.randf() * 0.38
		var tip := base + d * (0.12 + rng.randf() * 0.22) + Vector3(0, hgt, 0)
		var mid := base.lerp(tip, 0.5) + d * 0.03
		var cb := Color(0.5, 0.5, 0.5)
		var cm := Color(0.85, 0.85, 0.85)
		var ct := Color(1.15, 1.12, 1.0)
		var nrm := Vector3(d.x * 0.3, 1.0, d.z * 0.3).normalized()
		for tri in [[base - side, mid - side * 0.6, base + side, cb, cm, cb], [base + side, mid - side * 0.6, mid + side * 0.6, cb, cm, cm], [mid - side * 0.6, tip, mid + side * 0.6, cm, ct, cm]]:
			for k in 3:
				st.set_color(tri[3 + k]); st.set_normal(nrm); st.add_vertex(tri[k])
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.surface_set_material(0, m)
	_mats[key + "_mesh"] = mesh
	return mesh

## Masso: sfera deformata da rumore a più scale, normali morbide (niente facce piatte), colore per vertice
## (stratificazioni nel deserto, licheni in cima, ghiaccio in artico) e dettaglio triplanare nel materiale.
static func rock_mesh(seed_: int, ice := false, tint := Color(0.42, 0.4, 0.37), style := "") -> Mesh:
	# rocce dell'Agente F (Props.rock_mesh, stili rock/desert/mountain/arctic) se disponibili:
	# normalizzate a raggio orizzontale 1, base a y = -0.2 come le nostre (stesse trasformazioni in MultiMesh)
	var P = ext("Props")
	if P != null and P.has_method("rock_mesh") and style != "":
		var r := RandomNumberGenerator.new()
		r.seed = seed_
		var fm = P.rock_mesh(r, style, 3)
		if fm is ArrayMesh and (fm as ArrayMesh).get_surface_count() > 0:
			var norm := _normalize_rock(fm)
			if norm != null:
				return norm
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var sm := SphereMesh.new()
	sm.radial_segments = 28
	sm.rings = 16
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var cell := FastNoiseLite.new()
	cell.seed = seed_ + 3
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.frequency = 1.3
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var sc := Vector3(1.0 + rng.randf() * 0.5, 0.55 + rng.randf() * 0.3, 0.9 + rng.randf() * 0.4)
	var sandstone := tint.r > tint.b + 0.15 and not ice
	var pos := PackedVector3Array()
	pos.resize(verts.size())
	for i in verts.size():
		var p: Vector3 = verts[i] * 2.0
		var k := 1.0 + noise.get_noise_3dv(p * 1.1) * 0.32 + cell.get_noise_3dv(p * 1.4) * 0.16
		var q := Vector3(p.x * sc.x, p.y * sc.y, p.z * sc.z) * k
		if sandstone:
			# gradoni orizzontali (arenaria erosa)
			var band := floorf(q.y * 5.0) / 5.0
			q.y = lerpf(q.y, band, 0.45)
			q.x *= 1.0 + 0.06 * sin(q.y * 20.0)
			q.z *= 1.0 + 0.06 * sin(q.y * 20.0)
		if q.y < -0.2:
			q.y = -0.2
		pos[i] = q
	# normali morbide: somma delle normali di faccia per posizione (salda anche la cucitura della sfera)
	var acc := {}
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var fn := (c - a).cross(b - a)
		for vi in [idx[t], idx[t + 1], idx[t + 2]]:
			var key := Vector3i(roundi(pos[vi].x * 1000), roundi(pos[vi].y * 1000), roundi(pos[vi].z * 1000))
			acc[key] = acc.get(key, Vector3.ZERO) + fn
	var base := tint if not ice else Color(0.78, 0.86, 0.93)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pos.size():
		var q := pos[i]
		var key := Vector3i(roundi(q.x * 1000), roundi(q.y * 1000), roundi(q.z * 1000))
		var n: Vector3 = acc.get(key, Vector3.UP)
		if n.length_squared() < 1e-8:
			n = Vector3.UP
		n = n.normalized()
		var v := noise.get_noise_3dv(q * 3.0) * 0.5 + 0.5
		var col := base * (0.82 + 0.3 * v)
		if sandstone:
			col = col.lerp(Color(0.78, 0.62, 0.45), 0.35 * (0.5 + 0.5 * sin(q.y * 14.0)))
		elif ice:
			col = col.lerp(Color(0.95, 0.97, 1.0), smoothstep(0.55, 0.9, n.y))
		else:
			col = col.lerp(Color(0.34, 0.37, 0.24), smoothstep(0.7, 0.95, n.y) * 0.45 * v)
		# base più scura (terra e ombra di contatto)
		col = col.darkened(0.25 * (1.0 - smoothstep(-0.2, 0.25, q.y)))
		st.set_color(Color(col.r, col.g, col.b))
		st.set_normal(n)
		st.add_vertex(q)
	for t in idx:
		st.add_index(t)
	var mesh := st.commit()
	mesh.surface_set_material(0, _rock_mat(ice))
	return mesh

static func _normalize_rock(m: ArrayMesh) -> ArrayMesh:
	var bb := m.get_aabb()
	var half := maxf(bb.size.x, bb.size.z) * 0.5
	if half < 0.01:
		return null
	var k := 1.0 / half
	var c := bb.get_center()
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			var q := v[i]
			v[i] = Vector3((q.x - c.x) * k, (q.y - bb.position.y) * k - 0.2, (q.z - c.z) * k)
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, m.surface_get_material(si))
	return out

static func _rock_mat(ice: bool) -> StandardMaterial3D:
	var key := "rockmat_ice" if ice else "rockmat"
	if _mats.has(key):
		return _mats[key]
	var nz := FastNoiseLite.new()
	nz.seed = 31
	nz.frequency = 0.03
	nz.fractal_octaves = 5
	var img := nz.get_seamless_image(256, 256)
	var nimg := img.duplicate() as Image
	# albedo: rumore schiarito (moltiplica il colore per vertice tra 0.75 e 1.05)
	for y in img.get_height():
		for x in img.get_width():
			var g := img.get_pixel(x, y).r
			var v := 0.72 + 0.36 * g
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	nimg.bump_map_to_normal_map(5.0)
	nimg.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(nimg)
	m.normal_scale = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.22, 0.22, 0.22)
	m.roughness = 0.35 if ice else 0.92
	if ice:
		m.metallic_specular = 0.7
	_mats[key] = m
	return m

# ---------------------------------------------------------------------------- unità segnaposto
static func _pmat(col: Color, key: String, rough := 0.75, metal := 0.15) -> StandardMaterial3D:
	var k := key + col.to_html()
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[k] = m
	return m

static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, name := "", rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi

static func _bx(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _cy(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c

## Modello 3D di un'unità: UnitModels dell'Agente F se c'è, altrimenti segnaposto.
## `faction` (0 AAN, 1 FO, 2 CP, 3 UL, -1 generico): passata solo se UnitModels.build la accetta (fase 4, Agente F4).
static func unit_model(kind: String, color: Color, faction := -1) -> Node3D:
	var U = ext("UnitModels")
	if U != null and U.has_method("build"):
		var n = U.build(kind, color, 0, faction) if (faction >= 0 and build_args() >= 4) else U.build(kind, color)
		if n is Node3D:
			return n
	return placeholder(kind, color, false)

static var _build_args := -1

## Numero di argomenti di UnitModels.build (3 = senza fazione, 4 = con fazione).
static func build_args() -> int:
	if _build_args >= 0:
		return _build_args
	_build_args = 0
	var U = ext("UnitModels")
	if U != null:
		for m in (U as Script).get_script_method_list():
			if String(m["name"]) == "build":
				_build_args = (m["args"] as Array).size()
				break
	return _build_args

static func wreck_model(kind: String, color: Color) -> Node3D:
	var U = ext("UnitModels")
	if U != null and U.has_method("wreck"):
		var n = U.wreck(kind)
		if n is Node3D:
			return n
	return placeholder(kind, color, true)

static func placeholder(kind: String, color: Color, burnt: bool) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var olive := Color(0.3, 0.32, 0.22).lerp(color, 0.22)
	var fac := color
	var dark := Color(0.1, 0.1, 0.09)
	if burnt:
		olive = Color(0.11, 0.1, 0.09)
		fac = Color(0.16, 0.12, 0.1)
	var mb := _pmat(olive, "b")
	var mf := _pmat(fac, "f", 0.6)
	var md := _pmat(dark, "d", 0.9)
	match kind:
		"tank":
			var body := Node3D.new(); body.name = "Body"; root.add_child(body)
			_mi(body, _bx(3.5, 1.0, 7.0), mb, Vector3(0, 1.0, 0))
			_mi(body, _bx(0.7, 1.0, 7.2), md, Vector3(-1.55, 0.6, 0))
			_mi(body, _bx(0.7, 1.0, 7.2), md, Vector3(1.55, 0.6, 0))
			var tur := Node3D.new(); tur.name = "Turret"; tur.position = Vector3(0, 1.5, 0.4); root.add_child(tur)
			_mi(tur, _bx(2.5, 0.85, 3.0), mb, Vector3(0, 0.42, 0))
			_mi(tur, _bx(2.52, 0.2, 1.2), mf, Vector3(0, 0.88, 0.6))
			var bar := Node3D.new(); bar.name = "Barrel"; bar.position = Vector3(0, 0.45, -1.4); tur.add_child(bar)
			_mi(bar, _cy(0.12, 4.2), md, Vector3(0, 0, -2.1), "", Vector3(PI / 2, 0, 0))
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, 0, -4.3); bar.add_child(mz)
		"inf":
			var offs := [Vector3(0, 0, -1.2), Vector3(-1.1, 0, 0.1), Vector3(1.1, 0, 0.2), Vector3(-0.5, 0, 1.3), Vector3(0.7, 0, 1.4)]
			var cap := CapsuleMesh.new(); cap.radius = 0.24; cap.height = 1.45
			var head := SphereMesh.new(); head.radius = 0.15; head.height = 0.3
			for o in offs:
				_mi(root, cap, mb, o + Vector3(0, 0.75, 0))
				_mi(root, head, mf, o + Vector3(0, 1.6, 0))
				_mi(root, _bx(0.08, 0.08, 0.9), md, o + Vector3(0.25, 1.1, -0.3))
		"art":
			var body := Node3D.new(); body.name = "Body"; root.add_child(body)
			_mi(body, _bx(3.0, 1.2, 6.5), mb, Vector3(0, 1.1, 0.5))
			_mi(body, _bx(0.6, 1.0, 6.6), md, Vector3(-1.35, 0.6, 0.5))
			_mi(body, _bx(0.6, 1.0, 6.6), md, Vector3(1.35, 0.6, 0.5))
			var tur := Node3D.new(); tur.name = "Turret"; tur.position = Vector3(0, 1.7, 1.0); root.add_child(tur)
			_mi(tur, _bx(2.6, 1.3, 3.2), mb, Vector3(0, 0.6, 0))
			_mi(tur, _bx(2.62, 0.2, 1.0), mf, Vector3(0, 1.26, 0.8))
			var bar := Node3D.new(); bar.name = "Barrel"; bar.position = Vector3(0, 0.7, -1.5); tur.add_child(bar)
			_mi(bar, _cy(0.14, 6.5), md, Vector3(0, 0, -3.2), "", Vector3(PI / 2, 0, 0))
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, 0, -6.5); bar.add_child(mz)
		"aa":
			var body := Node3D.new(); body.name = "Body"; root.add_child(body)
			_mi(body, _bx(2.8, 1.1, 6.0), mb, Vector3(0, 1.0, 0))
			for sx in [-1.2, 1.2]:
				for z in [-2.0, 0.0, 2.0]:
					_mi(body, _cy(0.5, 0.35), md, Vector3(sx, 0.5, z), "", Vector3(0, 0, PI / 2))
			var tur := Node3D.new(); tur.name = "Turret"; tur.position = Vector3(0, 1.6, 0.6); root.add_child(tur)
			_mi(tur, _bx(2.2, 1.0, 2.2), mb, Vector3(0, 0.5, 0))
			_mi(tur, _bx(1.6, 1.0, 0.1), mf, Vector3(0, 1.5, 0.9))
			var bar := Node3D.new(); bar.name = "Barrel"; bar.position = Vector3(0, 0.6, -0.8); tur.add_child(bar)
			for sx in [-0.9, 0.9]:
				_mi(bar, _cy(0.07, 2.6), md, Vector3(sx, 0, -1.3), "", Vector3(PI / 2, 0, 0))
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, 0, -2.6); bar.add_child(mz)
		"heli":
			var body := Node3D.new(); body.name = "Body"; root.add_child(body)
			var cap := CapsuleMesh.new(); cap.radius = 0.9; cap.height = 6.0
			_mi(body, cap, mb, Vector3(0, 0, -0.5), "", Vector3(PI / 2, 0, 0))
			_mi(body, _cy(0.3, 6.0, 0.15), mb, Vector3(0, 0.25, 4.6), "", Vector3(PI / 2, 0, 0))
			_mi(body, _bx(0.1, 1.4, 1.0), mf, Vector3(0, 0.8, 7.3))
			_mi(body, _bx(3.0, 0.15, 0.8), mb, Vector3(0, -0.2, 0))
			var rot := Node3D.new(); rot.name = "Rotor"; rot.position = Vector3(0, 1.15, -0.5); root.add_child(rot)
			for a in 4:
				_mi(rot, _bx(0.35, 0.05, 6.2), md, Vector3(sin(a * PI / 2) * 3.1, 0, cos(a * PI / 2) * 3.1), "", Vector3(0, a * PI / 2, 0))
			var tr := Node3D.new(); tr.name = "TailRotor"; tr.position = Vector3(0.25, 0.8, 7.4); root.add_child(tr)
			_mi(tr, _bx(0.04, 1.6, 0.2), md, Vector3.ZERO)
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, -0.6, -3.5); root.add_child(mz)
		"jet":
			var body := Node3D.new(); body.name = "Body"; root.add_child(body)
			_mi(body, _cy(0.6, 14.0, 0.25), mb, Vector3(0, 0, 0), "", Vector3(-PI / 2, 0, 0))
			var wing := PrismMesh.new(); wing.size = Vector3(11.0, 6.0, 0.25)
			_mi(body, wing, mb, Vector3(0, 0, 1.2), "", Vector3(PI / 2, 0, 0))
			_mi(body, _bx(0.12, 2.4, 2.0), mf, Vector3(0, 1.1, 5.6))
			_mi(body, _bx(4.5, 0.12, 1.6), mb, Vector3(0, 0, 6.0))
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, 0, -7.0); root.add_child(mz)
		"drone":
			for i in 5:
				var a := TAU * i / 5.0
				var d := Node3D.new(); d.position = Vector3(cos(a) * 2.2, sin(i * 1.7) * 0.6, sin(a) * 2.2); root.add_child(d)
				_mi(d, _bx(0.9, 0.18, 0.9), mb, Vector3.ZERO)
				_mi(d, _bx(1.4, 0.05, 0.12), mf, Vector3(0, 0.08, 0), "", Vector3(0, PI / 4, 0))
				_mi(d, _bx(1.4, 0.05, 0.12), md, Vector3(0, 0.08, 0), "", Vector3(0, -PI / 4, 0))
		"bunker":
			var cm := _pmat(Color(0.55, 0.54, 0.5) if not burnt else Color(0.2, 0.19, 0.18), "c", 0.95, 0.0)
			_mi(root, _cy(4.2, 2.2, 3.6), cm, Vector3(0, 1.1, 0))
			_mi(root, _cy(3.7, 0.4, 3.3), cm, Vector3(0, 2.4, 0))
			_mi(root, _bx(5.5, 0.35, 0.5), md, Vector3(0, 1.6, -3.7))
			var sand := _pmat(Color(0.5, 0.45, 0.32), "s", 1.0, 0.0)
			for i in 10:
				var a := TAU * i / 10.0
				_mi(root, _bx(1.6, 0.7, 0.9), sand, Vector3(cos(a) * 5.2, 0.35, sin(a) * 5.2), "", Vector3(0, -a + PI / 2, 0))
			_mi(root, _bx(1.4, 0.15, 1.4), mf, Vector3(0, 2.7, 0))
			var tur := Node3D.new(); tur.name = "Turret"; tur.position = Vector3(0, 1.6, 0); root.add_child(tur)
			var bar := Node3D.new(); bar.name = "Barrel"; bar.position = Vector3(0, 0, -3.6); tur.add_child(bar)
			_mi(bar, _cy(0.06, 1.2), md, Vector3(0, 0, -0.6), "", Vector3(PI / 2, 0, 0))
			var mz := Marker3D.new(); mz.name = "Muzzle"; mz.position = Vector3(0, 0, -1.2); bar.add_child(mz)
		_:
			_mi(root, _bx(2.5, 2.0, 5.0), mb, Vector3(0, 1.0, 0))
	if burnt:
		for c in root.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).rotation += Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08))
	return root

# ---------------------------------------------------------------------------- fanteria: pose alternative (solo vista)
static var _inf_cache := {}
static var _inf_ok := -1

# ---------------------------------------------------------------------------- punti di riferimento (Fase 7)
## Prisma triangolare (tetto a due falde): colmo lungo X, base `w` (X) × `d` (Z), altezza `h`, base a `c`.
static func _gable(st: SurfaceTool, c: Vector3, w: float, d: float, h: float, col: Color, eave := 0.4) -> void:
	var x0 := c.x - w * 0.5 - eave
	var x1 := c.x + w * 0.5 + eave
	var z0 := c.z - d * 0.5 - eave
	var z1 := c.z + d * 0.5 + eave
	var y0 := c.y
	var y1 := c.y + h
	var a := Vector3(x0, y0, z0); var b := Vector3(x1, y0, z0); var r0 := Vector3(x0, y1, c.z); var r1 := Vector3(x1, y1, c.z)
	var e := Vector3(x0, y0, z1); var f := Vector3(x1, y0, z1)
	var n1 := (r0 - a).cross(b - a).normalized()
	if n1.y < 0: n1 = -n1
	var n2 := Vector3(n1.x, n1.y, -n1.z)
	for tri in [[a, r0, b, n1, 1.0], [b, r0, r1, n1, 1.0], [e, f, r0, n2, 0.82], [f, r1, r0, n2, 0.82]]:
		var cc := Color(col.r * tri[4], col.g * tri[4], col.b * tri[4])
		for k in 3:
			st.set_color(cc); st.set_normal(tri[3]); st.add_vertex(tri[k])
	# timpani
	var wall := col.darkened(0.15)
	for side in [[a, e, r0, Vector3.LEFT], [b, r1, f, Vector3.RIGHT]]:
		for k in 3:
			st.set_color(wall); st.set_normal(side[3]); st.add_vertex(side[k])

## Mesh dei punti di riferimento del paesaggio (MultiMesh, colore d'istanza moltiplicato):
## "house" casa colonica, "barn" fienile, "silo", "hut" casa in mattoni crudi a tetto piano, "chalet" baita,
## "pole" palo della linea elettrica (11 m), "wire" campata di filo (lunga 1 lungo +Z), "bridge" impalcato (lungo 1 lungo +Z),
## "ruin" muri diroccati, "fence" staccionata (lunga 1 lungo +Z).
static func landmark_mesh(kind: String) -> Mesh:
	var key := "lm_" + kind
	if _mats.has(key):
		return _mats[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"house":
			_box(st, Vector3(0, 2.6, 0), Vector3(11.0, 5.2, 7.5), Color(0.78, 0.72, 0.6))
			_gable(st, Vector3(0, 5.2, 0), 11.0, 7.5, 2.8, Color(0.55, 0.27, 0.2))
			_box(st, Vector3(3.2, 7.2, 1.2), Vector3(0.8, 2.2, 0.8), Color(0.5, 0.45, 0.4))
			for i in 3:
				_box(st, Vector3(-3.6 + i * 3.6, 3.4, 3.78), Vector3(1.0, 1.2, 0.08), Color(0.12, 0.13, 0.15))
		"barn":
			_box(st, Vector3(0, 3.4, 0), Vector3(16.0, 6.8, 9.0), Color(0.5, 0.33, 0.24))
			_gable(st, Vector3(0, 6.8, 0), 16.0, 9.0, 3.6, Color(0.42, 0.42, 0.42))
			_box(st, Vector3(0, 2.2, 4.55), Vector3(4.5, 4.4, 0.1), Color(0.28, 0.2, 0.15))
		"silo":
			_cyl(st, Vector3.ZERO, Vector3(0, 12.0, 0), 2.6, 2.6, 10, Color(0.68, 0.68, 0.66), Color(0.75, 0.75, 0.73))
			_cyl(st, Vector3(0, 12.0, 0), Vector3(0, 14.2, 0), 2.6, 0.3, 10, Color(0.55, 0.55, 0.55), Color(0.6, 0.6, 0.6))
		"hut":
			_box(st, Vector3(0, 1.9, 0), Vector3(8.0, 3.8, 6.5), Color(0.74, 0.6, 0.44))
			_box(st, Vector3(0, 3.95, 0), Vector3(8.4, 0.3, 6.9), Color(0.66, 0.53, 0.39))
			_box(st, Vector3(2.0, 1.2, 3.27), Vector3(1.1, 2.2, 0.06), Color(0.2, 0.15, 0.1))
		"chalet":
			_box(st, Vector3(0, 1.2, 0), Vector3(9.0, 2.4, 7.0), Color(0.62, 0.6, 0.56))
			_box(st, Vector3(0, 3.6, 0), Vector3(9.0, 2.4, 7.0), Color(0.45, 0.3, 0.18))
			_gable(st, Vector3(0, 4.8, 0), 9.0, 7.0, 2.2, Color(0.3, 0.3, 0.32), 1.0)
		"pole":
			_cyl(st, Vector3.ZERO, Vector3(0, 11.0, 0), 0.17, 0.12, 6, Color(0.36, 0.28, 0.2), Color(0.4, 0.32, 0.22))
			_box(st, Vector3(0, 10.4, 0), Vector3(3.2, 0.16, 0.16), Color(0.36, 0.28, 0.2))
			for x in [-1.4, 0.0, 1.4]:
				_box(st, Vector3(x, 10.62, 0), Vector3(0.1, 0.3, 0.1), Color(0.75, 0.75, 0.7))
		"wire":
			_box(st, Vector3(0, 0, 0.5), Vector3(0.04, 0.04, 1.0), Color(0.12, 0.12, 0.12))
		"bridge":
			# impalcato 7 m con parapetti, lungo 1 (scala Z), spessore 0.7
			_box(st, Vector3(0, -0.35, 0.5), Vector3(7.0, 0.7, 1.0), Color(0.55, 0.53, 0.5))
			_box(st, Vector3(-3.35, 0.45, 0.5), Vector3(0.3, 0.9, 1.0), Color(0.62, 0.6, 0.57))
			_box(st, Vector3(3.35, 0.45, 0.5), Vector3(0.3, 0.9, 1.0), Color(0.62, 0.6, 0.57))
		"pier":
			_box(st, Vector3(0, -2.5, 0), Vector3(5.0, 5.0, 1.4), Color(0.5, 0.48, 0.45))
		"ruin":
			var c := Color(0.62, 0.58, 0.52)
			_box(st, Vector3(0, 1.4, -3.0), Vector3(8.0, 2.8, 0.5), c)
			_box(st, Vector3(-3.8, 0.9, 0), Vector3(0.5, 1.8, 6.0), c.darkened(0.08))
			_box(st, Vector3(1.5, 0.5, 2.8), Vector3(3.5, 1.0, 0.5), c)
			for i in 6:
				_box(st, Vector3(rng.randf_range(-3, 3), 0.2, rng.randf_range(-2.5, 2.5)), Vector3(0.6, 0.4, 0.5) * (0.6 + rng.randf()), c.darkened(0.2), Basis(Vector3.UP, rng.randf() * TAU))
		"fence":
			_box(st, Vector3(0, 0.55, 0), Vector3(0.12, 1.1, 0.12), Color(0.4, 0.32, 0.24))
			_box(st, Vector3(0, 0.85, 0.5), Vector3(0.06, 0.1, 1.0), Color(0.45, 0.36, 0.27))
			_box(st, Vector3(0, 0.45, 0.5), Vector3(0.06, 0.1, 1.0), Color(0.45, 0.36, 0.27))
	var mesh := st.commit()
	mesh.surface_set_material(0, vc_mat("landmark", 0.88, true))
	_mats[key] = mesh
	return mesh

## Squadra di fanteria in posa alternativa: "run" (tutti in corsa, più distanziati) o "cover" (accovacciati/a terra,
## sparpagliati). Usa il costruttore dei soldati dell'Agente F se c'è; altrimenti null (la vista tiene la mesh originale).
static func inf_squad_mesh(color: Color, variant: String) -> Mesh:
	var key := "%s|%s" % [variant, color.to_html(false)]
	if _inf_cache.has(key):
		return _inf_cache[key]
	var UM = ext("UnitModels")
	var MK = ext("ModelKit")
	if _inf_ok < 0:
		_inf_ok = 0
		if UM != null and MK != null:
			var names := {}
			for m in (UM as Script).get_script_method_list():
				names[String(m["name"])] = true
			if names.has("_soldier") and names.has("_paint"):
				_inf_ok = 1
	if _inf_ok == 0:
		return null
	var pc: Color = UM._paint(Color(0.31, 0.32, 0.23), color, 0.15)
	var squad: Array
	if variant == "run":
		squad = [["walk", Vector3(0.2, 0, -2.1), 0.05], ["walk", Vector3(-1.9, 0, -0.6), -0.1], ["walk", Vector3(1.8, 0, 0.1), 0.12],
			["walk", Vector3(-0.9, 0, 1.7), -0.05], ["walk", Vector3(1.1, 0, 2.4), 0.08]]
	else:
		squad = [["kneel", Vector3(0.3, 0, -1.9), 0.15], ["prone", Vector3(-2.2, 0, -0.4), -0.3], ["kneel", Vector3(2.1, 0, 0.0), -0.35],
			["prone", Vector3(-0.6, 0, 1.6), 0.2], ["kneel", Vector3(1.4, 0, 2.3), 0.4]]
	var b = MK.new(color, false)
	for s in squad:
		var old: Transform3D = b.t
		b.t = b.t * Transform3D(Basis(Vector3.UP, float(s[2])), s[1] as Vector3)
		UM._soldier(b, String(s[0]), pc, 0)
		b.t = old
	var mesh: Mesh = b.commit()
	_inf_cache[key] = mesh
	return mesh

# ---------------------------------------------------------------------------- mezzo da sbarco (decorativo, costa)
static var _lc_cache := {}

## Mezzo da sbarco tipo LCM (~22 m): scafo piatto, rampa di prua abbassata verso -Z, plancia a poppa, fascia della fazione.
static func landing_craft(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "LandingCraft"
	var key := color.to_html(false)
	var mesh: ArrayMesh = _lc_cache.get(key)
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var grey := Color(0.36, 0.38, 0.39)
		var dark := Color(0.2, 0.21, 0.22)
		var deck := Color(0.28, 0.27, 0.25)
		# scafo (fondo) e fiancate
		_box(st, Vector3(0, 0.55, 1.0), Vector3(6.4, 1.1, 18.0), dark)
		_box(st, Vector3(-3.0, 1.75, 1.0), Vector3(0.4, 1.5, 18.0), grey)
		_box(st, Vector3(3.0, 1.75, 1.0), Vector3(0.4, 1.5, 18.0), grey)
		_box(st, Vector3(0, 1.15, 1.0), Vector3(5.6, 0.1, 18.0), deck)
		# fascia della fazione lungo le fiancate
		_box(st, Vector3(-3.22, 2.2, 1.0), Vector3(0.05, 0.35, 15.0), color)
		_box(st, Vector3(3.22, 2.2, 1.0), Vector3(0.05, 0.35, 15.0), color)
		# poppa con plancia
		_box(st, Vector3(0, 2.0, 9.6), Vector3(6.4, 1.8, 1.2), grey)
		_box(st, Vector3(1.6, 3.3, 9.0), Vector3(2.4, 1.6, 2.0), grey)
		_box(st, Vector3(1.6, 3.65, 7.98), Vector3(2.0, 0.45, 0.05), Color(0.1, 0.14, 0.18))
		_box(st, Vector3(1.6, 4.4, 9.2), Vector3(0.15, 0.6, 0.15), dark)
		# rampa abbassata (inclinata verso la riva, davanti = -Z)
		var rb := Basis(Vector3.RIGHT, -0.32)
		_box(st, Vector3(0, 0.75, -9.4), Vector3(5.8, 0.25, 4.2), grey, rb)
		_box(st, Vector3(-2.75, 1.05, -9.3), Vector3(0.3, 0.6, 4.0), grey, rb)
		_box(st, Vector3(2.75, 1.05, -9.3), Vector3(0.3, 0.6, 4.0), grey, rb)
		mesh = st.commit()
		_lc_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.material_override = vc_mat("lc", 0.75, false, 0.25)
	root.add_child(mi)
	return root
