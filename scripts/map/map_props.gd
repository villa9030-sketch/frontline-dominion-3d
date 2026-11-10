class_name MapProps
extends RefCounted
## Oggetti del tabellone: miniature (da UnitModels se disponibile, altrimenti segnaposto), navi, edifici in miniatura,
## stella del QG, texture generate per distintivi.

static var _um = null           # script UnitModels (caricato dinamicamente: lo scrive un altro agente)
static var _um_checked := false
static var _mats := {}
static var _tex := {}
static var _mesh := {}

static func global_class_script(cname: String):
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == cname:
			var p := String(c["path"])
			if ResourceLoader.exists(p):
				var sc = load(p)
				if sc is GDScript and (sc as GDScript).can_instantiate():
					return sc
				return null
	return null

static func unit_models():
	if not _um_checked:
		_um_checked = true
		_um = global_class_script("UnitModels")
	return _um

## true se UnitModels accetta la fazione (FASE 4: costante FACTION_STYLES).
static func um_factions() -> bool:
	var um = unit_models()
	return um != null and um.get_script_constant_map().has("FACTION_STYLES")

## true se UnitModels sa costruire davvero quel tipo (le navi arrivano dall'Agente F2: finché mancano si usa il segnaposto).
static func um_has(kind: String) -> bool:
	var um = unit_models()
	if um == null:
		return false
	var cm: Dictionary = um.get_script_constant_map()
	if cm.has("KINDS") and kind in cm["KINDS"]:
		return true
	if cm.has("NAVAL") and kind in cm["NAVAL"]:
		return true
	return false

static func mat(c: Color, rough := 0.7, emis := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), rough, emis]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	_mats[key] = m
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, seg := 16, r2 := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if r2 < 0 else r2
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

## Miniatura "pedina" normalizzata: larghezza massima ~ `size` unità, origine a terra, avanti = -Z.
## faction: 0..3 fazione del proprietario, -1 neutrale/generico (sagome per fazione se UnitModels le offre, FASE 4).
static func miniature(kind: String, color: Color, size: float = 1.6, faction: int = -1) -> Node3D:
	var um = unit_models()
	var n: Node3D = null
	if um != null and (kind != "ship" or um_has("ship")):
		if um_factions():
			n = um.miniature(kind, color, faction)
		else:
			n = um.miniature(kind, color)
	if n == null:
		n = _placeholder(kind, color)
	var holder := Node3D.new()
	holder.add_child(n)
	var aabb := _aabb(n, Transform3D.IDENTITY)
	var w := maxf(aabb.size.x, aabb.size.z)
	if w > 0.0001:
		var s := size / w
		n.scale = Vector3.ONE * s
		n.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * s, -aabb.position.y * s, -(aabb.position.z + aabb.size.z * 0.5) * s)
	return holder

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is VisualInstance3D and not (n is Light3D):
		var a: AABB = x * (n as VisualInstance3D).get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var b := _aabb(c, x)
		if b.size == Vector3.ZERO:
			continue
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

static func _placeholder(kind: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var paint := mat(color.darkened(0.25), 0.55, 0.15)
	var dark := mat(Color(0.12, 0.13, 0.12), 0.8)
	var olive := mat(Color(0.30, 0.33, 0.22), 0.8)
	_cyl(root, 1.0, 0.18, Vector3(0, 0.09, 0), mat(Color(0.08, 0.09, 0.09), 0.5), Vector3.ZERO, 24)
	_cyl(root, 1.02, 0.05, Vector3(0, 0.17, 0), paint, Vector3.ZERO, 24)
	match kind:
		"tank":
			_box(root, Vector3(0.9, 0.28, 1.5), Vector3(0, 0.36, 0), olive)
			_box(root, Vector3(1.05, 0.2, 1.6), Vector3(0, 0.3, 0), dark)
			_cyl(root, 0.32, 0.22, Vector3(0, 0.6, 0.1), paint)
			_cyl(root, 0.05, 0.9, Vector3(0, 0.62, -0.45), dark, Vector3(PI / 2, 0, 0), 8)
		"art":
			_box(root, Vector3(0.8, 0.22, 1.1), Vector3(0, 0.33, 0.2), olive)
			_box(root, Vector3(0.5, 0.25, 0.5), Vector3(0, 0.55, 0.15), paint)
			_cyl(root, 0.06, 1.3, Vector3(0, 0.85, -0.35), dark, Vector3(PI / 2 - 0.6, 0, 0), 8)
		"aa":
			_box(root, Vector3(0.85, 0.25, 1.3), Vector3(0, 0.34, 0), olive)
			_box(root, Vector3(0.5, 0.35, 0.5), Vector3(0, 0.62, 0), paint)
			for sx in [-0.12, 0.12]:
				_cyl(root, 0.04, 0.7, Vector3(sx, 0.95, -0.15), dark, Vector3(PI / 2 - 1.0, 0, 0), 6)
		"heli":
			_box(root, Vector3(0.36, 0.36, 1.0), Vector3(0, 0.7, 0), paint)
			_box(root, Vector3(0.1, 0.1, 0.9), Vector3(0, 0.75, 0.85), olive)
			_box(root, Vector3(1.7, 0.02, 0.08), Vector3(0, 0.95, 0), dark)
			_box(root, Vector3(0.08, 0.02, 1.7), Vector3(0, 0.95, 0), dark)
			_cyl(root, 0.03, 0.5, Vector3(0, 0.45, 0), dark, Vector3.ZERO, 6)
		"jet", "drone":
			var s := 0.6 if kind == "drone" else 1.0
			_box(root, Vector3(0.22, 0.2, 1.5) * s, Vector3(0, 0.9, 0), paint)
			_box(root, Vector3(1.5, 0.05, 0.45) * s, Vector3(0, 0.88, 0.15 * s), olive)
			_box(root, Vector3(0.05, 0.35, 0.3) * s, Vector3(0, 1.05, 0.6 * s), olive)
			_cyl(root, 0.03, 0.75, Vector3(0, 0.45, 0), dark, Vector3.ZERO, 6)
		"ship":
			_box(root, Vector3(0.55, 0.25, 1.8), Vector3(0, 0.3, 0), mat(Color(0.35, 0.38, 0.40), 0.6))
			_box(root, Vector3(0.4, 0.3, 0.6), Vector3(0, 0.55, 0.2), paint)
			_cyl(root, 0.05, 0.4, Vector3(0, 0.85, 0.2), dark, Vector3.ZERO, 6)
		"truck":
			_box(root, Vector3(0.6, 0.35, 1.2), Vector3(0, 0.42, 0.15), olive)
			_box(root, Vector3(0.6, 0.3, 0.35), Vector3(0, 0.4, -0.6), paint)
		_:
			for k in 3:
				var p := Vector3((k - 1) * 0.42, 0, (k % 2) * 0.25)
				_cyl(root, 0.12, 0.45, p + Vector3(0, 0.42, 0), olive, Vector3.ZERO, 8)
				var hm := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.13; sm.height = 0.24
				hm.mesh = sm
				hm.material_override = paint
				hm.position = p + Vector3(0, 0.75, 0)
				root.add_child(hm)
	return root

## Nave per le traversate, lunga ~3 unità, avanti = -Z: UnitModels.build("ship"|"transport") se disponibile, altrimenti segnaposto.
static func ship(color: Color, kind: String = "transport") -> Node3D:
	if um_has(kind):
		var n: Node3D = unit_models().build(kind, color, 1)
		if n != null:
			var holder := Node3D.new()
			holder.add_child(n)
			var aabb := _aabb(n, Transform3D.IDENTITY)
			var L := maxf(aabb.size.z, aabb.size.x)
			if L > 0.0001:
				var s := (2.6 if kind == "ship" else 2.2) / L
				n.scale = Vector3.ONE * s
				n.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * s, 0.0, -(aabb.position.z + aabb.size.z * 0.5) * s)
			return holder
	return _ship_placeholder(color)

static func _ship_placeholder(color: Color) -> Node3D:
	var root := Node3D.new()
	var hull := mat(Color(0.32, 0.35, 0.37), 0.55)
	var deck := mat(Color(0.22, 0.24, 0.25), 0.7)
	var paint := mat(color.darkened(0.15), 0.5, 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# scafo a punta (avanti = -Z), lungo 3, largo 0.7
	var pts := [Vector3(0, 0.35, -1.6), Vector3(0.35, 0.35, -0.8), Vector3(0.38, 0.35, 1.2), Vector3(0.0, 0.35, 1.35), Vector3(-0.38, 0.35, 1.2), Vector3(-0.35, 0.35, -0.8)]
	for k in pts.size():
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % pts.size()]
		var a2 := Vector3(a.x * 0.7, -0.05, a.z * 0.95)
		var b2 := Vector3(b.x * 0.7, -0.05, b.z * 0.95)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(b2)
		st.add_vertex(a); st.add_vertex(b2); st.add_vertex(a2)
	for k in range(1, pts.size() - 1):
		st.add_vertex(pts[0]); st.add_vertex(pts[k + 1]); st.add_vertex(pts[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = hull
	root.add_child(mi)
	_box(root, Vector3(0.45, 0.35, 0.9), Vector3(0, 0.52, 0.25), deck)
	_box(root, Vector3(0.3, 0.3, 0.4), Vector3(0, 0.85, 0.35), paint)
	_cyl(root, 0.03, 0.6, Vector3(0, 1.25, 0.35), deck, Vector3.ZERO, 6)
	_cyl(root, 0.12, 0.25, Vector3(0, 0.5, -0.75), paint, Vector3.ZERO, 10)
	_cyl(root, 0.025, 0.5, Vector3(0, 0.58, -1.05), deck, Vector3(PI / 2, 0, 0), 6)
	return root

## Edificio in miniatura per il tabellone (circa 0.5 unità).
static func building(key: String) -> Node3D:
	var root := Node3D.new()
	var conc := mat(Color(0.55, 0.55, 0.52), 0.85)
	var roof := mat(Color(0.30, 0.32, 0.30), 0.8)
	var rust := mat(Color(0.45, 0.30, 0.20), 0.8)
	var green := mat(Color(0.28, 0.33, 0.22), 0.85)
	match key:
		"caserma":
			_box(root, Vector3(0.55, 0.16, 0.22), Vector3(0, 0.08, -0.12), green)
			_box(root, Vector3(0.55, 0.16, 0.22), Vector3(0, 0.08, 0.16), green)
			_cyl(root, 0.012, 0.45, Vector3(0.32, 0.22, 0), roof, Vector3.ZERO, 4)
		"fabbrica":
			_box(root, Vector3(0.5, 0.2, 0.36), Vector3(0, 0.1, 0), rust)
			_box(root, Vector3(0.5, 0.06, 0.36), Vector3(0, 0.23, 0), roof)
			_cyl(root, 0.045, 0.5, Vector3(0.17, 0.3, -0.1), conc, Vector3.ZERO, 8)
			_cyl(root, 0.045, 0.42, Vector3(0.05, 0.26, -0.1), conc, Vector3.ZERO, 8)
		"aeroporto":
			_box(root, Vector3(0.14, 0.012, 0.75), Vector3(0, 0.006, 0), mat(Color(0.16, 0.16, 0.16), 0.9))
			var hm := _cyl(root, 0.14, 0.4, Vector3(0.24, 0.0, 0.1), conc, Vector3(PI / 2, 0, 0), 12)
			hm.scale = Vector3(1, 1, 0.9)
			_cyl(root, 0.03, 0.22, Vector3(-0.18, 0.11, -0.2), roof, Vector3.ZERO, 6)
		"porto":
			_box(root, Vector3(0.6, 0.06, 0.18), Vector3(0, 0.03, 0), conc)
			_box(root, Vector3(0.04, 0.4, 0.04), Vector3(0.15, 0.2, 0), mat(Color(0.85, 0.65, 0.15), 0.6))
			_box(root, Vector3(0.36, 0.04, 0.04), Vector3(0.05, 0.4, 0), mat(Color(0.85, 0.65, 0.15), 0.6))
			_box(root, Vector3(0.16, 0.12, 0.1), Vector3(-0.18, 0.12, 0.0), mat(Color(0.25, 0.4, 0.6), 0.6))
		"bunker":
			var dm := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22; sm.height = 0.22; sm.is_hemisphere = true
			dm.mesh = sm
			dm.material_override = conc
			root.add_child(dm)
			_box(root, Vector3(0.18, 0.03, 0.04), Vector3(0, 0.1, -0.2), roof)
		"impianto":
			_box(root, Vector3(0.05, 0.5, 0.05), Vector3(0, 0.25, 0), roof)
			_box(root, Vector3(0.05, 0.5, 0.05), Vector3(0, 0.25, 0), roof, Vector3(0, 0, 0.35))
			_box(root, Vector3(0.05, 0.5, 0.05), Vector3(0, 0.25, 0), roof, Vector3(0, 0, -0.35))
			_cyl(root, 0.1, 0.16, Vector3(0.2, 0.08, 0.12), mat(Color(0.7, 0.7, 0.68), 0.6), Vector3.ZERO, 10)
	return root

## Stella a 5 punte estrusa (raggio 1).
static func star_mesh() -> Mesh:
	if _mesh.has("star"):
		return _mesh["star"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		var r := 1.0 if k % 2 == 0 else 0.42
		pts.append(Vector2(cos(a), sin(a)) * r)
	var th := 0.25
	for k in 10:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 10]
		# fronte (+Z verso la telecamera nel billboard) con centro rialzato
		st.add_vertex(Vector3(0, 0, th)); st.add_vertex(Vector3(b.x, -b.y, 0)); st.add_vertex(Vector3(a.x, -a.y, 0))
		st.add_vertex(Vector3(0, 0, -th)); st.add_vertex(Vector3(a.x, -a.y, 0)); st.add_vertex(Vector3(b.x, -b.y, 0))
	st.generate_normals()
	var m := st.commit()
	_mesh["star"] = m
	return m

## Scia bianca di una nave (sfuma verso poppa e ai lati).
static func wake_texture() -> Texture2D:
	if _tex.has("wake"):
		return _tex["wake"]
	var W := 32
	var H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var v := float(y) / H
			var u := absf(x + 0.5 - W * 0.5) / (W * 0.5)
			var spread := 0.25 + 0.75 * v
			var a := (1.0 - smoothstep(spread * 0.6, spread, u)) * (1.0 - v) * (0.6 + 0.4 * smoothstep(0.0, 0.08, v))
			var edge := smoothstep(spread * 0.35, spread * 0.6, u) * 0.4
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * (0.55 + edge), 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex["wake"] = t
	return t

## Texture di un disco con bordo (per i distintivi): bianco, tintabile con modulate.
static func disc_texture() -> Texture2D:
	if _tex.has("disc"):
		return _tex["disc"]
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x + 0.5 - S * 0.5, y + 0.5 - S * 0.5).length() / (S * 0.5)
			var a := clampf((1.0 - d) * S * 0.5, 0.0, 1.0)
			var rim := smoothstep(0.80, 0.86, d)
			var shade := 0.62 - 0.22 * d
			var v := lerpf(shade, 1.0, rim)
			img.set_pixel(x, y, Color(v, v, v, a))
	var t := ImageTexture.create_from_image(img)
	_tex["disc"] = t
	return t

## Texture di una stella a 5 punte (dorata, con contorno scuro).
static func star_texture() -> Texture2D:
	if _tex.has("star"):
		return _tex["star"]
	var S := 64
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		var r := 1.0 if k % 2 == 0 else 0.45
		outer.append(Vector2(cos(a), sin(a)) * r * S * 0.48 + Vector2(S, S) * 0.5)
		inner.append(Vector2(cos(a), sin(a)) * r * S * 0.36 + Vector2(S, S) * 0.5)
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var cin := 0
			var cout := 0
			for sy in 2:
				for sx in 2:
					var p := Vector2(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5)
					if Geometry2D.is_point_in_polygon(p, inner): cin += 1
					if Geometry2D.is_point_in_polygon(p, outer): cout += 1
			var a := cout / 4.0
			var v := lerpf(0.15, 1.0, cin / 4.0)
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.9, a))
	var t := ImageTexture.create_from_image(img)
	_tex["star"] = t
	return t

# ====================================================================== strutture del tabellone (notte "tabellone più ricco")
## Costruttore minimo di mesh colorate per vertice (scatole e cilindri) in una sola superficie, più una superficie "luci"
## (shader map_lights: tenue di giorno, accesa di notte). Indipendente da ModelKit: il tabellone compila comunque.
class Kit:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var lc := PackedColorArray()

	## Triangolo a, b, cc con normale nn (Godot: facce frontali in senso ORARIO, quindi l'ordine è a, cc, b).
	func _tri(a: Vector3, b: Vector3, cc: Vector3, nn: Vector3, col: Color, lights: bool) -> void:
		if lights:
			lv.append(a); lv.append(cc); lv.append(b)
			ln.append(nn); ln.append(nn); ln.append(nn)
			lc.append(col); lc.append(col); lc.append(col)
		else:
			v.append(a); v.append(cc); v.append(b)
			n.append(nn); n.append(nn); n.append(nn)
			c.append(col); c.append(col); c.append(col)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, lights := false) -> void:
		var nn := (b - a).cross(d - a).normalized()
		_tri(a, b, cc, nn, col, lights)
		_tri(a, cc, d, nn, col, lights)

	## Scatola centrata in `pos` (y = centro), ruotata con `rot`; `shade` scurisce i fianchi rispetto al tetto.
	func box(size: Vector3, pos: Vector3, col: Color, rot := Basis.IDENTITY, lights := false, shade := 0.78) -> void:
		var h := size * 0.5
		var P: Array = []
		for k in 8:
			var s := Vector3(-h.x if (k & 1) == 0 else h.x, -h.y if (k & 2) == 0 else h.y, -h.z if (k & 4) == 0 else h.z)
			P.append(rot * s + pos)
		var side := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		var side2 := Color(side.r * 0.92, side.g * 0.92, side.b * 0.92, 1.0)
		var bottom := Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 1.0)
		quad(P[2], P[6], P[7], P[3], col, lights)            # sopra (+y)
		quad(P[0], P[1], P[5], P[4], bottom, lights)         # sotto
		quad(P[0], P[4], P[6], P[2], side, lights)           # -x
		quad(P[5], P[1], P[3], P[7], side, lights)           # +x
		quad(P[1], P[0], P[2], P[3], side2, lights)          # -z
		quad(P[4], P[5], P[7], P[6], side2, lights)          # +z

	## Cilindro con asse y (centro in pos), raggi base/cima, segmenti.
	func cyl(r0: float, r1: float, h: float, pos: Vector3, col: Color, seg := 10, rot := Basis.IDENTITY, lights := false, caps := true) -> void:
		var side := Color(col.r * 0.85, col.g * 0.85, col.b * 0.85, 1.0)
		var bot := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 1.0)
		for k in seg:
			var a0 := TAU * float(k) / seg
			var a1 := TAU * float(k + 1) / seg
			var b0 := Vector3(cos(a0) * r0, -h * 0.5, sin(a0) * r0)
			var b1 := Vector3(cos(a1) * r0, -h * 0.5, sin(a1) * r0)
			var t0 := Vector3(cos(a0) * r1, h * 0.5, sin(a0) * r1)
			var t1 := Vector3(cos(a1) * r1, h * 0.5, sin(a1) * r1)
			var nn := rot * Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			_tri(rot * b0 + pos, rot * t0 + pos, rot * t1 + pos, nn, side, lights)
			_tri(rot * b0 + pos, rot * t1 + pos, rot * b1 + pos, nn, side, lights)
			if caps:
				_tri(rot * Vector3(0, h * 0.5, 0) + pos, rot * t1 + pos, rot * t0 + pos, rot * Vector3.UP, col, lights)
				_tri(rot * Vector3(0, -h * 0.5, 0) + pos, rot * b0 + pos, rot * b1 + pos, rot * Vector3.DOWN, bot, lights)

	## Asta tra due punti (cilindro sottile).
	func bar(a: Vector3, b: Vector3, r: float, col: Color, seg := 5, lights := false) -> void:
		var d := b - a
		var L := d.length()
		if L < 0.0001:
			return
		var up := d / L
		var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var xa := up.cross(ref).normalized()
		var za := xa.cross(up).normalized()
		var rot := Basis(xa, up, za)
		cyl(r, r, L, (a + b) * 0.5, col, seg, rot, lights, true)

	func tri_count() -> int:
		return (v.size() + lv.size()) / 3

	## Crea le MeshInstance3D sotto `parent` (una per superficie) con raggio di visibilità `vis` (0 = sempre).
	func commit(parent: Node3D, vis := 0.0, shadows := true) -> Array:
		var out: Array = []
		for pair in [[v, n, c, false], [lv, ln, lc, true]]:
			var vv: PackedVector3Array = pair[0]
			if vv.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vv
			arrays[Mesh.ARRAY_NORMAL] = pair[1]
			arrays[Mesh.ARRAY_COLOR] = pair[2]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = MapProps.lights_mat() if pair[3] else MapProps.struct_mat()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and not pair[3]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if vis > 0.0:
				mi.visibility_range_end = vis
				mi.visibility_range_end_margin = vis * 0.15
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)
			out.append(mi)
		return out

static var _struct_mat: ShaderMaterial = null
static var _lights_mat: ShaderMaterial = null

## Materiale condiviso delle strutture (map_struct.gdshader: colore di vertice, buio sul lato notturno).
static func struct_mat() -> ShaderMaterial:
	if _struct_mat == null:
		_struct_mat = ShaderMaterial.new()
		_struct_mat.shader = load("res://scripts/map/map_struct.gdshader")
	return _struct_mat

static func lights_mat() -> ShaderMaterial:
	if _lights_mat == null:
		_lights_mat = ShaderMaterial.new()
		_lights_mat.shader = load("res://scripts/map/map_lights.gdshader")
		_lights_mat.render_priority = 1
	return _lights_mat

# colori comuni delle strutture
const C_CONC := Color(0.62, 0.61, 0.57)
const C_CONC_D := Color(0.45, 0.45, 0.43)
const C_ASPH := Color(0.19, 0.19, 0.20)
const C_ROOF := Color(0.33, 0.34, 0.33)
const C_STEEL := Color(0.55, 0.57, 0.60)
const C_RUST := Color(0.48, 0.30, 0.20)
const C_OLIVE := Color(0.33, 0.37, 0.25)
const C_YELLOW := Color(0.92, 0.70, 0.12)
const C_WHITE := Color(0.92, 0.92, 0.90)
const C_WOOD := Color(0.42, 0.30, 0.18)
const C_SAND := Color(0.66, 0.58, 0.40)
const C_LIGHT_W := Color(1.0, 0.85, 0.6)
const C_LIGHT_R := Color(1.0, 0.2, 0.12)
const C_LIGHT_O := Color(1.0, 0.55, 0.15)

## Struttura 3D per il tabellone (origine a terra, avanti = -Z; ~1–1.6 unità). key: chiave edificio di Data.BUILDINGS,
## "hq" (compound del quartier generale, con `col` = colore della fazione) o "scaffold" (cantiere).
static func structure(key: String, col := Color.WHITE, rng: RandomNumberGenerator = null, vis := 60.0) -> Node3D:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(key)
	var root := Node3D.new()
	root.name = "S_" + key
	var k := Kit.new()
	match key:
		"porto": _s_port(k, rng)
		"aeroporto": _s_airport(k, rng)
		"fabbrica": _s_factory(k, rng)
		"caserma": _s_barracks(k, rng, col)
		"bunker": _s_fort(k, rng)
		"impianto": _s_plant(k, rng)
		"hq": _s_hq(k, rng, col)
		"scaffold": _s_scaffold(k, rng)
		_: k.box(Vector3(0.4, 0.2, 0.4), Vector3(0, 0.1, 0), C_CONC)
	k.commit(root, vis)
	root.set_meta("tris", k.tri_count())
	return root

## Posizioni (locali) delle ciminiere di una struttura, per il fumo.
static func structure_smoke(key: String) -> Array:
	match key:
		"fabbrica": return [Vector3(0.38, 0.56, -0.25), Vector3(0.38, 0.56, 0.05)]
		"impianto": return [Vector3(0.4, 0.5, -0.3)]
		"porto": return [Vector3(0.36, 0.28, -0.22)]
	return []

## Porto: banchina che entra in mare (-Z), gru a portale, magazzino, container, nave ormeggiata.
static func _s_port(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(0.34, 0.05, 1.5), Vector3(0.0, 0.03, -0.55), C_CONC)          # molo
	k.box(Vector3(0.9, 0.04, 0.5), Vector3(0.0, 0.025, 0.35), C_CONC_D)          # piazzale
	for z in [-1.1, -0.6, -0.1]:
		k.bar(Vector3(0.16, -0.1, z), Vector3(0.16, 0.05, z), 0.012, C_WOOD, 4)   # pali
		k.bar(Vector3(-0.16, -0.1, z), Vector3(-0.16, 0.05, z), 0.012, C_WOOD, 4)
	# gru a portale
	for sx in [-0.14, 0.14]:
		k.box(Vector3(0.03, 0.42, 0.03), Vector3(sx, 0.26, -0.5), C_YELLOW)
		k.box(Vector3(0.03, 0.42, 0.03), Vector3(sx, 0.26, -0.32), C_YELLOW)
	k.box(Vector3(0.34, 0.04, 0.24), Vector3(0, 0.48, -0.41), C_YELLOW)
	k.box(Vector3(0.05, 0.05, 0.9), Vector3(0, 0.52, -0.52), C_YELLOW)            # braccio
	k.box(Vector3(0.1, 0.09, 0.1), Vector3(0, 0.455, -0.3), C_STEEL)              # cabina
	k.bar(Vector3(0, 0.5, -0.9), Vector3(0, 0.22, -0.9), 0.006, Color(0.2, 0.2, 0.2), 4)   # cavo
	k.box(Vector3(0.08, 0.06, 0.08), Vector3(0, 0.19, -0.9), Color(0.75, 0.25, 0.18))  # container sospeso
	k.box(Vector3(0.03, 0.03, 0.03), Vector3(0, 0.56, -0.52), C_LIGHT_R, Basis.IDENTITY, true)
	# magazzino con tetto ad arco e container impilati
	k.box(Vector3(0.5, 0.2, 0.3), Vector3(-0.15, 0.12, 0.45), Color(0.55, 0.58, 0.62))
	k.cyl(0.15, 0.15, 0.5, Vector3(-0.15, 0.22, 0.45), C_ROOF, 10, Basis(Vector3.FORWARD, PI / 2), false, false)
	var cc := [Color(0.75, 0.25, 0.18), Color(0.2, 0.45, 0.7), Color(0.25, 0.55, 0.3), Color(0.85, 0.6, 0.15)]
	for i in 6:
		@warning_ignore("integer_division")
		var p := Vector3(0.25 + (i % 3) * 0.1, 0.045 + (i / 3) * 0.07, 0.28 + (i % 2) * 0.09)
		k.box(Vector3(0.09, 0.065, 0.075), p, cc[rng.randi() % cc.size()])
	# nave ormeggiata (scafo grigio, sovrastruttura, fumaiolo)
	var sx := 0.36
	k.box(Vector3(0.2, 0.09, 0.95), Vector3(sx, 0.02, -0.55), Color(0.36, 0.38, 0.41))
	k.box(Vector3(0.14, 0.05, 0.2), Vector3(sx, 0.07, -0.85), Color(0.36, 0.38, 0.41))
	k.box(Vector3(0.16, 0.12, 0.22), Vector3(sx, 0.12, -0.25), C_WHITE)
	k.cyl(0.025, 0.02, 0.1, Vector3(sx, 0.23, -0.22), Color(0.8, 0.25, 0.2), 6)
	k.box(Vector3(0.02, 0.02, 0.02), Vector3(sx, 0.2, -0.36), C_LIGHT_W, Basis.IDENTITY, true)
	for i in 4:
		k.box(Vector3(0.09, 0.06, 0.07), Vector3(sx, 0.095, -0.45 - i * 0.09), cc[(i * 7) % cc.size()])
	# lampioni della banchina
	for z in [-1.0, -0.3]:
		k.bar(Vector3(-0.15, 0.05, z), Vector3(-0.15, 0.2, z), 0.006, C_STEEL, 4)
		k.box(Vector3(0.025, 0.02, 0.025), Vector3(-0.15, 0.21, z), C_LIGHT_W, Basis.IDENTITY, true)

## Aeroporto: pista con segnaletica, raccordo, due hangar ad arco, torre di controllo, jet parcheggiato, faro.
static func _s_airport(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(2.3, 0.016, 0.3), Vector3(0, 0.008, 0), C_ASPH)
	for i in 9:
		k.box(Vector3(0.12, 0.004, 0.02), Vector3(-1.0 + i * 0.25, 0.019, 0), C_WHITE)
	for e in [-1.08, 1.08]:
		for j in 5:
			k.box(Vector3(0.09, 0.004, 0.03), Vector3(e, 0.019, -0.1 + j * 0.05), C_WHITE)
	k.box(Vector3(0.9, 0.014, 0.16), Vector3(-0.2, 0.007, 0.3), Color(0.24, 0.24, 0.25))       # raccordo
	k.box(Vector3(0.7, 0.014, 0.45), Vector3(-0.2, 0.007, 0.56), Color(0.28, 0.28, 0.29))      # piazzale
	for hx in [-0.5, -0.05]:
		k.box(Vector3(0.34, 0.11, 0.3), Vector3(hx, 0.06, 0.7), C_CONC)
		k.cyl(0.15, 0.15, 0.34, Vector3(hx, 0.11, 0.7), C_ROOF, 10, Basis(Vector3.FORWARD, PI / 2), false, false)
		k.box(Vector3(0.3, 0.09, 0.01), Vector3(hx, 0.05, 0.55), Color(0.3, 0.32, 0.36))       # portone
	# torre di controllo
	k.cyl(0.035, 0.03, 0.3, Vector3(0.45, 0.15, 0.62), C_CONC, 8)
	k.box(Vector3(0.16, 0.07, 0.16), Vector3(0.45, 0.33, 0.62), Color(0.2, 0.3, 0.4))
	k.box(Vector3(0.18, 0.02, 0.18), Vector3(0.45, 0.375, 0.62), C_WHITE)
	k.box(Vector3(0.03, 0.03, 0.03), Vector3(0.45, 0.4, 0.62), C_LIGHT_R, Basis.IDENTITY, true)
	# terminal basso
	k.box(Vector3(0.5, 0.07, 0.18), Vector3(0.55, 0.04, 0.42), Color(0.58, 0.6, 0.62))
	# jet parcheggiato
	var jp := Vector3(-0.2, 0.03, 0.5)
	k.box(Vector3(0.05, 0.05, 0.3), jp + Vector3(0, 0.02, 0), Color(0.55, 0.58, 0.6))
	k.box(Vector3(0.3, 0.01, 0.1), jp + Vector3(0, 0.0, 0.03), Color(0.5, 0.53, 0.56))
	k.box(Vector3(0.02, 0.09, 0.07), jp + Vector3(0, 0.05, 0.13), Color(0.5, 0.53, 0.56))
	# luci di bordo pista
	for i in 6:
		for sz in [-0.17, 0.17]:
			k.box(Vector3(0.02, 0.012, 0.02), Vector3(-1.0 + i * 0.4, 0.02, sz), C_LIGHT_W if i % 2 == 0 else Color(0.4, 0.5, 1.0), Basis.IDENTITY, true)
	# manica a vento
	k.bar(Vector3(0.9, 0.0, -0.25), Vector3(0.9, 0.16, -0.25), 0.005, C_STEEL, 4)
	k.cyl(0.02, 0.012, 0.09, Vector3(0.94, 0.16, -0.25), Color(0.95, 0.4, 0.1), 6, Basis(Vector3.FORWARD, -PI / 2))

## Fabbrica: capannoni con tetto a denti di sega, ciminiere a bande, serbatoi, tubazioni, piazzale.
static func _s_factory(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(1.1, 0.012, 0.9), Vector3(0, 0.006, 0), Color(0.36, 0.36, 0.35))
	for i in 3:
		var z := -0.28 + i * 0.26
		k.box(Vector3(0.7, 0.16, 0.22), Vector3(-0.1, 0.08, z), Color(0.62, 0.52, 0.42))
		# dente di sega: tetto inclinato + vetrata verticale
		k.box(Vector3(0.7, 0.012, 0.2), Vector3(-0.1, 0.19, z - 0.01), C_ROOF, Basis(Vector3.RIGHT, 0.5))
		k.box(Vector3(0.68, 0.06, 0.008), Vector3(-0.1, 0.19, z + 0.1), Color(0.3, 0.45, 0.6))
	for i in 2:
		var p := Vector3(0.38, 0.0, -0.25 + i * 0.3)
		k.cyl(0.035, 0.028, 0.55, p + Vector3(0, 0.275, 0), Color(0.72, 0.3, 0.25), 8)
		k.cyl(0.0365, 0.034, 0.05, p + Vector3(0, 0.45, 0), C_WHITE, 8)
		k.cyl(0.0365, 0.034, 0.05, p + Vector3(0, 0.33, 0), C_WHITE, 8)
		k.box(Vector3(0.02, 0.02, 0.02), p + Vector3(0, 0.56, 0), C_LIGHT_R, Basis.IDENTITY, true)
	# serbatoi e tubi
	for i in 2:
		k.cyl(0.07, 0.07, 0.12, Vector3(0.38, 0.06, 0.18 + i * 0.16), C_STEEL, 10)
	k.bar(Vector3(0.38, 0.13, 0.18), Vector3(0.38, 0.13, 0.34), 0.012, C_RUST, 5)
	k.bar(Vector3(0.3, 0.1, 0.2), Vector3(0.25, 0.1, -0.1), 0.01, C_RUST, 5)
	# magazzino e uffici
	k.box(Vector3(0.3, 0.12, 0.2), Vector3(-0.3, 0.06, 0.36), Color(0.5, 0.52, 0.55))
	k.box(Vector3(0.18, 0.2, 0.14), Vector3(0.05, 0.1, 0.38), Color(0.64, 0.63, 0.6))
	k.box(Vector3(0.19, 0.03, 0.15), Vector3(0.05, 0.15, 0.38), Color(0.95, 0.8, 0.4), Basis.IDENTITY, true)   # finestre uffici
	# camion nel piazzale
	for i in 2:
		var p := Vector3(-0.45 + i * 0.16, 0.03, 0.1)
		k.box(Vector3(0.07, 0.05, 0.16), p, Color(0.3, 0.35, 0.4))
		k.box(Vector3(0.07, 0.04, 0.05), p + Vector3(0, 0.0, -0.1), Color(0.8, 0.8, 0.78))

## Caserma: blocchi alloggi in fila, piazza d'armi, pennone, recinzione, camion, torretta di guardia.
static func _s_barracks(k: Kit, rng: RandomNumberGenerator, col: Color) -> void:
	k.box(Vector3(1.0, 0.012, 0.8), Vector3(0, 0.006, 0), C_SAND)
	for i in 3:
		var z := -0.26 + i * 0.22
		k.box(Vector3(0.6, 0.1, 0.14), Vector3(-0.15, 0.05, z), C_OLIVE)
		k.box(Vector3(0.62, 0.02, 0.16), Vector3(-0.15, 0.105, z), Color(0.22, 0.24, 0.2))
		for w in 7:
			k.box(Vector3(0.03, 0.03, 0.006), Vector3(-0.42 + w * 0.09, 0.055, z + 0.073), Color(0.95, 0.85, 0.55), Basis.IDENTITY, true)
	k.box(Vector3(0.3, 0.01, 0.3), Vector3(0.28, 0.012, -0.1), C_CONC_D)   # piazza d'armi
	k.bar(Vector3(0.28, 0.0, -0.1), Vector3(0.28, 0.32, -0.1), 0.006, C_WHITE, 4)
	var fl := Color(col.r, col.g, col.b, 1.0)
	k.box(Vector3(0.12, 0.07, 0.008), Vector3(0.34, 0.285, -0.1), fl, Basis.IDENTITY, false, 1.0)
	# palazzina comando
	k.box(Vector3(0.26, 0.16, 0.18), Vector3(0.3, 0.08, 0.25), Color(0.6, 0.58, 0.52))
	k.box(Vector3(0.28, 0.02, 0.2), Vector3(0.3, 0.17, 0.25), Color(0.3, 0.2, 0.15))
	# recinzione e torretta
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a) * 0.52, 0.0, sin(a) * 0.42)
		k.bar(p, p + Vector3(0, 0.06, 0), 0.004, C_STEEL, 4)
	k.bar(Vector3(0.48, 0.0, -0.36), Vector3(0.48, 0.14, -0.36), 0.008, C_WOOD, 4)
	k.box(Vector3(0.08, 0.06, 0.08), Vector3(0.48, 0.17, -0.36), C_OLIVE)
	k.box(Vector3(0.1, 0.015, 0.1), Vector3(0.48, 0.205, -0.36), Color(0.22, 0.24, 0.2))
	k.box(Vector3(0.03, 0.03, 0.03), Vector3(0.48, 0.235, -0.36), C_LIGHT_W, Basis.IDENTITY, true)
	for i in 3:
		var p := Vector3(-0.4 + i * 0.12, 0.03, 0.3)
		k.box(Vector3(0.07, 0.05, 0.14), p, C_OLIVE)
		k.box(Vector3(0.07, 0.04, 0.05), p + Vector3(0, 0, -0.09), Color(0.28, 0.3, 0.22))

## Fortificazioni (edificio): bunker di comando in cemento con feritoie, sacchetti di sabbia, antenna, cannone.
static func _s_fort(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(0.6, 0.14, 0.42), Vector3(0, 0.07, 0), C_CONC_D)
	k.box(Vector3(0.5, 0.08, 0.34), Vector3(0, 0.17, 0.02), C_CONC)
	k.box(Vector3(0.52, 0.03, 0.3), Vector3(0, 0.22, 0.02), Color(0.4, 0.42, 0.36))
	for sx in [-0.16, 0.0, 0.16]:
		k.box(Vector3(0.1, 0.03, 0.02), Vector3(sx, 0.16, -0.16), Color(0.05, 0.05, 0.05))
	k.cyl(0.03, 0.03, 0.4, Vector3(0.0, 0.22, -0.22), Color(0.2, 0.22, 0.2), 6, Basis(Vector3.RIGHT, PI / 2 - 0.25))
	for i in 18:
		var a := TAU * float(i) / 18.0
		k.box(Vector3(0.07, 0.04, 0.05), Vector3(cos(a) * 0.4, 0.02, sin(a) * 0.3), C_SAND, Basis(Vector3.UP, -a))
	k.bar(Vector3(0.22, 0.24, 0.1), Vector3(0.22, 0.46, 0.1), 0.005, C_STEEL, 4)
	k.box(Vector3(0.02, 0.02, 0.02), Vector3(0.22, 0.47, 0.1), C_LIGHT_R, Basis.IDENTITY, true)
	k.box(Vector3(0.18, 0.06, 0.14), Vector3(-0.42, 0.03, 0.14), C_CONC_D)   # postazione laterale

## Impianto estrattivo: torre di trivellazione, pompa a bilanciere, serbatoi, torcia.
static func _s_plant(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(0.9, 0.012, 0.7), Vector3(0, 0.006, 0), Color(0.42, 0.38, 0.32))
	var top := Vector3(-0.2, 0.62, 0)
	for sx in [-0.14, 0.14]:
		for sz in [-0.14, 0.14]:
			k.bar(Vector3(-0.2 + sx, 0.0, sz), top + Vector3(sx * 0.25, 0, sz * 0.25), 0.008, C_RUST, 4)
	for y in [0.15, 0.3, 0.45]:
		var f: float = 1.0 - float(y) / 0.7
		for sx in [-1, 1]:
			k.bar(Vector3(-0.2 + sx * 0.14 * f, y, -0.14 * f), Vector3(-0.2 + sx * 0.14 * f, y, 0.14 * f), 0.005, C_RUST, 4)
		for sz in [-1, 1]:
			k.bar(Vector3(-0.2 - 0.14 * f, y, sz * 0.14 * f), Vector3(-0.2 + 0.14 * f, y, sz * 0.14 * f), 0.005, C_RUST, 4)
	k.box(Vector3(0.1, 0.03, 0.1), top, C_RUST)
	k.box(Vector3(0.025, 0.025, 0.025), top + Vector3(0, 0.03, 0), C_LIGHT_R, Basis.IDENTITY, true)
	# pompa a bilanciere
	k.box(Vector3(0.1, 0.03, 0.2), Vector3(0.2, 0.015, 0.15), C_CONC_D)
	k.bar(Vector3(0.2, 0.0, 0.15), Vector3(0.2, 0.18, 0.15), 0.012, C_STEEL, 5)
	k.box(Vector3(0.04, 0.03, 0.3), Vector3(0.2, 0.19, 0.12), Color(0.7, 0.2, 0.15), Basis(Vector3.RIGHT, 0.18))
	k.box(Vector3(0.06, 0.06, 0.04), Vector3(0.2, 0.19, 0.26), Color(0.3, 0.3, 0.3))
	# serbatoi, tubazioni, torcia
	k.cyl(0.08, 0.08, 0.1, Vector3(0.25, 0.05, -0.2), C_STEEL, 12)
	k.cyl(0.06, 0.06, 0.14, Vector3(0.05, 0.07, -0.25), Color(0.85, 0.85, 0.82), 10)
	k.bar(Vector3(0.25, 0.1, -0.2), Vector3(0.05, 0.1, -0.25), 0.01, C_RUST, 5)
	k.bar(Vector3(0.4, 0.0, -0.3), Vector3(0.4, 0.4, -0.3), 0.007, C_STEEL, 5)
	k.cyl(0.02, 0.035, 0.08, Vector3(0.4, 0.44, -0.3), C_LIGHT_O, 6, Basis.IDENTITY, true)
	k.box(Vector3(0.14, 0.08, 0.1), Vector3(-0.3, 0.04, 0.25), Color(0.55, 0.55, 0.5))   # baracca

## Quartier generale: compound recintato con torri d'angolo, palazzina di comando, radar, bunker, pennone con la bandiera.
static func _s_hq(k: Kit, rng: RandomNumberGenerator, col: Color) -> void:
	var fc := Color(col.r, col.g, col.b, 1.0)
	var W := 0.8
	k.box(Vector3(W * 2 + 0.1, 0.014, W * 2 + 0.1), Vector3(0, 0.007, 0), Color(0.5, 0.49, 0.45))
	# mura
	for s in 4:
		var rot := Basis(Vector3.UP, s * PI / 2)
		k.box(Vector3(W * 2, 0.1, 0.05), rot * Vector3(0, 0.05, W), C_CONC_D, rot)
		var cp := rot * Vector3(W, 0, W)
		k.box(Vector3(0.12, 0.2, 0.12), cp + Vector3(0, 0.1, 0), C_CONC)
		k.box(Vector3(0.14, 0.02, 0.14), cp + Vector3(0, 0.21, 0), Color(0.3, 0.32, 0.3))
		k.box(Vector3(0.03, 0.03, 0.03), cp + Vector3(0, 0.235, 0), C_LIGHT_W, Basis.IDENTITY, true)
	# ingresso (varco sul lato -Z con sbarra)
	k.box(Vector3(0.3, 0.12, 0.06), Vector3(0, 0.06, -W), Color(0.5, 0.49, 0.45))
	k.box(Vector3(0.28, 0.02, 0.02), Vector3(0, 0.1, -W - 0.04), fc, Basis.IDENTITY, false, 1.0)
	# palazzina di comando (a L) con fascia nel colore della fazione
	k.box(Vector3(0.7, 0.26, 0.3), Vector3(0, 0.13, 0.25), Color(0.63, 0.62, 0.58))
	k.box(Vector3(0.3, 0.36, 0.3), Vector3(-0.2, 0.18, 0.25), Color(0.58, 0.58, 0.55))
	k.box(Vector3(0.72, 0.03, 0.32), Vector3(0, 0.245, 0.25), fc, Basis.IDENTITY, false, 1.0)
	k.box(Vector3(0.32, 0.03, 0.32), Vector3(-0.2, 0.345, 0.25), fc, Basis.IDENTITY, false, 1.0)
	for w in 6:
		k.box(Vector3(0.05, 0.05, 0.006), Vector3(-0.3 + w * 0.12, 0.13, 0.095), Color(1.0, 0.9, 0.6), Basis.IDENTITY, true)
	# radar: traliccio + disco inclinato
	k.bar(Vector3(0.45, 0.0, 0.35), Vector3(0.45, 0.3, 0.35), 0.012, C_STEEL, 5)
	k.cyl(0.12, 0.02, 0.05, Vector3(0.45, 0.36, 0.35), C_WHITE, 12, Basis(Vector3.RIGHT, -1.1))
	k.box(Vector3(0.02, 0.02, 0.02), Vector3(0.45, 0.42, 0.35), C_LIGHT_R, Basis.IDENTITY, true)
	# bunker e mezzi
	k.box(Vector3(0.28, 0.08, 0.22), Vector3(0.45, 0.04, -0.4), C_CONC_D)
	k.box(Vector3(0.2, 0.04, 0.16), Vector3(0.45, 0.1, -0.4), C_CONC)
	for i in 3:
		var p := Vector3(-0.55, 0.035, -0.45 + i * 0.16)
		k.box(Vector3(0.14, 0.06, 0.08), p, C_OLIVE)
		k.box(Vector3(0.05, 0.04, 0.08), p + Vector3(-0.08, -0.005, 0), Color(0.28, 0.3, 0.22))
	# pennone con bandiera
	var fp := Vector3(0.0, 0.0, -0.45)
	k.cyl(0.05, 0.04, 0.03, fp + Vector3(0, 0.015, 0), C_WHITE, 10)
	k.bar(fp + Vector3(0, 0.03, 0), fp + Vector3(0, 0.95, 0), 0.008, C_WHITE, 5)
	k.cyl(0.0, 0.02, 0.03, fp + Vector3(0, 0.965, 0), C_YELLOW, 6)
	# drappo (tre lamelle leggermente sfalsate: effetto ondulato)
	for i in 3:
		var x0 := 0.01 + i * 0.1
		var dy := sin(i * 1.4) * 0.012
		k.box(Vector3(0.1, 0.18, 0.006), fp + Vector3(x0 + 0.05, 0.85 + dy, 0), fc, Basis.IDENTITY, false, 1.0)
	k.box(Vector3(0.012, 0.012, 0.012), fp + Vector3(0, 0.93, 0), C_LIGHT_W, Basis.IDENTITY, true)

## Cantiere (edificio in costruzione): impalcatura, gru, materiali.
static func _s_scaffold(k: Kit, rng: RandomNumberGenerator) -> void:
	k.box(Vector3(0.6, 0.01, 0.5), Vector3(0, 0.005, 0), Color(0.5, 0.45, 0.38))
	k.box(Vector3(0.42, 0.06, 0.32), Vector3(0, 0.03, 0), C_CONC)   # fondazioni
	var P := [Vector3(-0.22, 0, -0.17), Vector3(0.22, 0, -0.17), Vector3(0.22, 0, 0.17), Vector3(-0.22, 0, 0.17)]
	for i in 4:
		k.bar(P[i], P[i] + Vector3(0, 0.3, 0), 0.005, C_STEEL, 4)
		for y in [0.12, 0.24]:
			k.bar(P[i] + Vector3(0, y, 0), P[(i + 1) % 4] + Vector3(0, y, 0), 0.004, C_STEEL, 4)
	# gru
	k.bar(Vector3(0.35, 0, 0.3), Vector3(0.35, 0.55, 0.3), 0.01, C_YELLOW, 4)
	k.box(Vector3(0.7, 0.03, 0.03), Vector3(0.15, 0.55, 0.3), C_YELLOW)
	k.bar(Vector3(-0.15, 0.55, 0.3), Vector3(-0.15, 0.25, 0.3), 0.004, Color(0.2, 0.2, 0.2), 4)
	k.box(Vector3(0.06, 0.05, 0.06), Vector3(-0.15, 0.22, 0.3), C_CONC)
	k.box(Vector3(0.1, 0.04, 0.1), Vector3(0.5, 0.55, 0.3), C_CONC_D)   # contrappeso
	k.box(Vector3(0.025, 0.025, 0.025), Vector3(0.35, 0.58, 0.3), C_LIGHT_R, Basis.IDENTITY, true)
	# materiali
	var mc := [C_RUST, C_CONC, C_WOOD]
	for i in 3:
		k.box(Vector3(0.1, 0.05, 0.08), Vector3(-0.35, 0.025, -0.15 + i * 0.12), mc[i])
	k.box(Vector3(0.12, 0.08, 0.1), Vector3(0.0, 0.04, -0.33), C_YELLOW)   # betoniera/baracca

## Fortificazioni a livelli attorno al distintivo: trincee (anello tratteggiato scuro con parapetto), campi minati
## (dischetti con fascia gialla), bunker (cupole in cemento con feritoia). `r` = raggio dell'anello.
static func fort_rings(trench: int, mines: int, bunker: int, r: float, rng: RandomNumberGenerator, vis := 60.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Fort"
	var k := Kit.new()
	if trench > 0:
		var seg := 8 + trench * 6
		var frac := 0.55 + 0.1 * trench
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * (float(i) + frac) / seg
			var steps := 3
			for s in steps:
				var b0 := lerpf(a0, a1, float(s) / steps)
				var b1 := lerpf(a0, a1, float(s + 1) / steps)
				var am := (b0 + b1) * 0.5
				var L := r * (b1 - b0) * 1.05
				var pos := Vector3(cos(am) * r, 0.0, sin(am) * r)
				var rot := Basis(Vector3.UP, -am)
				k.box(Vector3(0.05, 0.02, L), pos + Vector3(0, 0.005, 0), Color(0.16, 0.13, 0.1), rot)      # scavo
				k.box(Vector3(0.025, 0.03, L), pos + rot * Vector3(0.035, 0.015, 0), Color(0.5, 0.42, 0.3), rot)  # parapetto esterno
				if trench >= 2:
					k.box(Vector3(0.02, 0.025, L), pos + rot * Vector3(-0.035, 0.012, 0), C_SAND, rot)           # sacchetti interni
			if trench >= 3 and i % 3 == 0:
				var a := (a0 + a1) * 0.5
				k.box(Vector3(0.08, 0.05, 0.08), Vector3(cos(a) * (r + 0.07), 0.025, sin(a) * (r + 0.07)), C_CONC_D, Basis(Vector3.UP, -a))
	if mines > 0:
		var nmin := 5 * mines
		for i in nmin:
			var a := TAU * (float(i) + 0.5 + rng.randf() * 0.4) / nmin
			var rr := r + 0.32 + rng.randf() * 0.25
			var p := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			k.cyl(0.035, 0.03, 0.015, p + Vector3(0, 0.008, 0), Color(0.22, 0.22, 0.2), 8)
			k.box(Vector3(0.05, 0.006, 0.012), p + Vector3(0, 0.017, 0), C_YELLOW, Basis(Vector3.UP, rng.randf() * TAU))
		# cartelli
		for i in mines:
			var a := TAU * (float(i) + 0.3) / mines
			var p := Vector3(cos(a) * (r + 0.62), 0.0, sin(a) * (r + 0.62))
			k.bar(p, p + Vector3(0, 0.07, 0), 0.004, C_STEEL, 4)
			k.box(Vector3(0.05, 0.035, 0.005), p + Vector3(0, 0.085, 0), Color(0.9, 0.15, 0.1), Basis(Vector3.UP, -a + PI / 2))
	if bunker > 0:
		var nb := 2 + bunker
		for i in nb:
			var a := TAU * (float(i) + 0.25) / nb
			var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			var rot := Basis(Vector3.UP, -a + PI / 2)
			k.cyl(0.11, 0.08, 0.06, p + Vector3(0, 0.03, 0), C_CONC_D, 12)
			k.cyl(0.08, 0.0, 0.05, p + Vector3(0, 0.085, 0), C_CONC, 12)
			k.box(Vector3(0.07, 0.016, 0.02), p + rot * Vector3(0, 0.05, -0.1), Color(0.05, 0.05, 0.05), rot)
			if bunker >= 2:
				k.cyl(0.008, 0.008, 0.12, p + rot * Vector3(0, 0.06, -0.14), Color(0.2, 0.22, 0.2), 5, rot * Basis(Vector3.RIGHT, PI / 2 - 0.2))
			if bunker >= 3:
				k.box(Vector3(0.05, 0.05, 0.05), p + Vector3(0, 0.025, 0) + rot * Vector3(0.14, 0, 0.02), C_CONC_D)
	k.commit(root, vis, false)
	root.set_meta("tris", k.tri_count())
	return root
