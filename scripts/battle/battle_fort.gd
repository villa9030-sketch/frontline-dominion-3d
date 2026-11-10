extends Node3D
## Fortificazioni del difensore (solo vista): trincee (terra scavata con sacchetti di sabbia) e campi minati (cartelli di
## pericolo e paletti). Legge i dati della sim in modo difensivo: `sim.trenches` e `sim.mines` se esistono.
## Formati accettati: trincea = Array di Vector2 | {pts:[Vector2|[x,y]]} | {x0,y0,x1,y1} | {x,y,w|len,ang};
## campo minato = {x, y, r|R, side?, spotted?:[bool,bool], known?:[bool,bool], visible?:[bool,bool]}.
## I campi minati si vedono solo dal loro proprietario o quando sono stati scoperti dal lato del giocatore.

var battle
var _fields: Array = []     # {node: Node3D, d: Dictionary}
var _t := 0.0

const EARTH := Color(0.16, 0.12, 0.085)
const SAND := Color(0.66, 0.58, 0.42)

func setup(b) -> void:
	battle = b
	var sim = b.sim
	if "trenches" in sim and sim.trenches is Array:
		var segs := []
		for tr in sim.trenches:
			var pts := _trench_pts(tr)
			for i in pts.size() - 1:
				segs.append([pts[i], pts[i + 1]])
		if not segs.is_empty():
			_build_trenches(segs)
	if "mines" in sim and sim.mines is Array:
		for m in sim.mines:
			if m is Dictionary and m.has("x") and m.has("y"):
				var n := _build_minefield(m)
				add_child(n)
				_fields.append({"node": n, "d": m})
	update(1.0)
	if b._demo:
		var tn: int = sim.trenches.size() if "trenches" in sim else 0
		var mn: int = sim.mines.size() if "mines" in sim else 0
		var at := ""
		if mn > 0:
			var w := BattleTerrain.sim_to_world(float(sim.mines[0]["x"]), float(sim.mines[0]["y"]))
			at = " prima mina a %d,%d" % [w.x, w.y]
		if tn > 0:
			var t0: Dictionary = sim.trenches[0]
			var w2 := BattleTerrain.sim_to_world(float(t0.get("x0", 0)), float(t0.get("y0", 0)))
			at += " prima trincea a %d,%d" % [w2.x, w2.y]
		print("[fort] trincee %d, campi minati %d%s" % [tn, mn, at])

static func _v(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.ZERO

func _trench_pts(tr) -> Array:
	var out := []
	if tr is Array or tr is PackedVector2Array:
		for p in tr:
			out.append(_v(p))
	elif tr is Dictionary:
		if tr.has("pts"):
			for p in tr["pts"]:
				out.append(_v(p))
		elif tr.has("x0"):
			out = [Vector2(float(tr["x0"]), float(tr["y0"])), Vector2(float(tr["x1"]), float(tr["y1"]))]
		elif tr.has("x"):
			var c := Vector2(float(tr["x"]), float(tr["y"]))
			var L := float(tr.get("len", tr.get("w", 120.0)))
			var d := Vector2.from_angle(float(tr.get("ang", PI * 0.5)))
			out = [c - d * L * 0.5, c + d * L * 0.5]
	return out

func _ground(sx: float, sy: float) -> Vector3:
	var w := BattleTerrain.sim_to_world(sx, sy)
	return Vector3(w.x, battle.terrain.height(w.x, w.y), w.y)

## Trincee: nastro di terra scura a filo del suolo e due file di sacchetti di sabbia sui bordi (MultiMesh).
func _build_trenches(segs: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bags := []
	var half := 3.0     # la trincea della sim è larga ~60 px (15 m): fossato centrale con parapetti
	for sg in segs:
		var a := _ground(sg[0].x, sg[0].y)
		var b := _ground(sg[1].x, sg[1].y)
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		var L := d.length()
		if L < 0.5:
			continue
		d /= L
		var n := Vector3(-d.z, 0, d.x)
		var steps := maxi(1, int(ceil(L / 2.0)))
		for k in steps:
			var p0 := a.lerp(b, float(k) / steps)
			var p1 := a.lerp(b, float(k + 1) / steps)
			var q := []
			for p in [p0 - n * half, p0 + n * half, p1 + n * half, p1 - n * half]:
				var h: float = battle.terrain.height(p.x, p.z) + 0.06
				q.append(Vector3(p.x, h, p.z))
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_color(EARTH)
				st.set_normal(Vector3.UP)
				st.add_vertex(q[i])
		var nb := int(L / 0.62)
		for k in nb:
			var p := a.lerp(b, (k + 0.5) / nb)
			for sd in [-1.0, 1.0]:
				var e: Vector3 = p + n * sd * (half + 0.35)
				e.y = battle.terrain.height(e.x, e.z) + 0.16
				bags.append(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z) + randf_range(-0.12, 0.12)).scaled(Vector3(0.55, 0.32, 0.36)), e))
				if k % 2 == 0:
					var e2 := e + Vector3(0, 0.28, 0)
					bags.append(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z) + randf_range(-0.12, 0.12)).scaled(Vector3(0.55, 0.3, 0.36)), e2))
	var mi := MeshInstance3D.new()
	mi.name = "Trenches"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if bags.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var bm := StandardMaterial3D.new()
	bm.albedo_color = SAND
	bm.roughness = 0.95
	box.material = bm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = bags.size()
	for i in bags.size():
		mm.set_instance_transform(i, bags[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sandbags"
	mmi.multimesh = mm
	add_child(mmi)

## Campo minato: paletti con nastro e cartelli triangolari rossi lungo il bordo, più qualche cartello all'interno.
func _build_minefield(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Minefield"
	var c := Vector2(float(d["x"]), float(d["y"]))
	var R := float(d.get("r", d.get("R", 80.0)))
	var Rw := R * BattleTerrain.S
	var n := clampi(int(TAU * Rw / 7.0), 8, 64)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.9, 0.12)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.28, 0.2)
	post.material = pm
	var sign := PrismMesh.new()
	sign.size = Vector3(1.3, 1.1, 0.06)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.12, 0.08)
	sm.emission_enabled = true
	sm.emission = Color(0.5, 0.05, 0.03)
	sign.material = sm
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post
	posts.instance_count = n
	var signs := MultiMesh.new()
	signs.transform_format = MultiMesh.TRANSFORM_3D
	signs.mesh = sign
	signs.instance_count = n
	for i in n:
		var a := TAU * i / n
		var p := _ground(c.x + cos(a) * R, c.y + sin(a) * R)
		posts.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0.95, 0)))
		var b := Basis(Vector3.UP, -a + PI * 0.5)
		signs.set_instance_transform(i, Transform3D(b, p + Vector3(0, 1.75, 0) + Vector3(cos(a), 0, sin(a)) * 0.09))
	for mmx in [posts, signs]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mmx
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# nastro di delimitazione: anello sottile rosso/bianco sul terreno
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := n * 3
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var col := Color(0.9, 0.15, 0.1) if i % 2 == 0 else Color(0.92, 0.9, 0.85)
		var q := []
		for v in [[a0, R - 1.3], [a0, R + 1.3], [a1, R + 1.3], [a1, R - 1.3]]:
			var g := _ground(c.x + cos(v[0]) * v[1], c.y + sin(v[0]) * v[1])
			q.append(g + Vector3(0, 0.08, 0))
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(q[k])
	var tape := MeshInstance3D.new()
	tape.mesh = st.commit()
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tape.material_override = tm
	tape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tape)
	var lb := Label3D.new()
	lb.text = "CAMPO MINATO"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1.0, 0.35, 0.25)
	lb.outline_modulate = Color(0, 0, 0, 0.8)
	lb.font_size = 40
	lb.pixel_size = 0.07
	lb.no_depth_test = true
	lb.position = _ground(c.x, c.y) + Vector3(0, 4.0, 0)
	root.add_child(lb)
	return root

## Visibilità dei campi minati: proprietario, oppure scoperti dal lato del giocatore (o spettatore).
func _mine_visible(d: Dictionary) -> bool:
	var sim = battle.sim
	var hs: int = sim.hs
	if hs < 0:
		return true
	if int(d.get("side", 1)) == hs:
		return true
	for k in ["spotted", "known", "visible"]:
		var v = d.get(k)
		if v is Array and v.size() > hs and bool(v[hs]):
			return true
		if v is bool and v:
			return true
	return false

func update(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.4
	for f in _fields:
		var d: Dictionary = f["d"]
		var vis := _mine_visible(d) and not bool(d.get("dead", false)) and not bool(d.get("cleared", false))
		(f["node"] as Node3D).visible = vis
