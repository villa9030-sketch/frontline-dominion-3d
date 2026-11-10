class_name BattleOrderMarks
extends Node3D
## Indicatori d'ordine animati a terra (in pool, nessun nodo creato per ordine): anello che si stringe sul punto,
## quattro frecce che convergono, colore per tipo d'ordine; per l'attacco segue il bersaglio con un mirino rotante.

const POOL := 10
const DUR := 0.95
const COLS := {
	"move": Color(0.45, 1.0, 0.55),
	"deploy": Color(0.45, 1.0, 0.55),
	"amove": Color(1.0, 0.7, 0.3),
	"attack": Color(1.0, 0.3, 0.25),
	"barrage": Color(1.0, 0.3, 0.25),
}

var battle            # Battle3D
var _items: Array = []   # {root, ring, ring2, chev:[MeshInstance3D], mat, t, T, r, kind, u, p}
var _next := 0

static func _chevron_mesh() -> ArrayMesh:
	# freccia a V piatta, punta verso -Z, larga ~1.2 (scalata col raggio dell'indicatore)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.22
	var tip := Vector3(0, 0, -0.45)
	for s in [-1.0, 1.0]:
		var e := Vector3(0.62 * s, 0, 0.35)
		var a := tip
		var b := e
		var n := Vector3(0, 0, w)
		var q := [a, b, b + n, a + n]
		var order := [[0, 1, 2], [0, 2, 3]] if s > 0 else [[0, 2, 1], [0, 3, 2]]
		for tri in order:
			for k in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(q[k])
	return st.commit()

func setup(b, ring_mesh: Mesh) -> void:
	battle = b
	var chev := _chevron_mesh()
	var inner := TorusMesh.new()
	inner.inner_radius = 0.82
	inner.outer_radius = 1.0
	inner.rings = 24
	inner.ring_segments = 3
	for i in POOL:
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 4
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var ring2 := MeshInstance3D.new()
		ring2.mesh = inner
		ring2.material_override = m
		ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring2)
		var chs := []
		for k in 4:
			var c := MeshInstance3D.new()
			c.mesh = chev
			c.material_override = m
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(c)
			chs.append(c)
		_items.append({"root": root, "ring": ring, "ring2": ring2, "chev": chs, "mat": m, "t": 0.0, "T": DUR, "r": 3.0, "kind": "move", "u": null, "p": Vector3.ZERO})

## Nuovo indicatore: p = punto a terra (mondo), r = raggio finale (m), u = unità bersaglio da seguire (o null).
func spawn(p: Vector3, kind: String, r: float, u = null, dur := DUR) -> void:
	var it: Dictionary = _items[_next]
	_next = (_next + 1) % _items.size()
	it["t"] = 0.0
	it["T"] = dur
	it["r"] = maxf(1.5, r)
	it["kind"] = kind
	it["u"] = u
	it["p"] = p
	(it["root"] as Node3D).visible = true
	(it["root"] as Node3D).position = p + Vector3(0, 0.35, 0)
	_apply(it)

func update(dt: float) -> void:
	for it in _items:
		var root: Node3D = it["root"]
		if not root.visible:
			continue
		it["t"] += dt
		if it["t"] >= it["T"]:
			root.visible = false
			it["u"] = null
			continue
		var u = it["u"]
		if u != null and not u.dead and battle != null and battle.views.has(u.id):
			var vp: Vector3 = battle.views[u.id]["pos"]
			var gy: float = battle.terrain.height(vp.x, vp.z)
			if battle.sim.sea:
				gy = maxf(gy, 0.0)
			root.position = Vector3(vp.x, gy + 0.35, vp.z)
		_apply(it)

func _apply(it: Dictionary) -> void:
	var f: float = it["t"] / it["T"]
	var r: float = it["r"]
	var kind: String = it["kind"]
	var col: Color = COLS.get(kind, Color(0.45, 1.0, 0.55))
	var a := 1.0 - smoothstep(0.55, 1.0, f)
	(it["mat"] as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.95 * a)
	# anello esterno: parte largo e si stringe sul punto (rimbalzo leggero)
	var e := 1.0 - pow(1.0 - minf(1.0, f / 0.3), 3.0)
	var rr := lerpf(r * 1.9, r, e)
	var ring: MeshInstance3D = it["ring"]
	ring.scale = Vector3(rr, 0.6, rr)
	# anello interno: pulsa una volta e si espande mentre svanisce
	var ring2: MeshInstance3D = it["ring2"]
	var r2 := r * (0.35 + 0.5 * smoothstep(0.25, 1.0, f))
	ring2.scale = Vector3(r2, 0.5, r2)
	ring2.visible = kind != "barrage"
	# frecce: convergono verso il centro; per l'attacco ruotano come un mirino
	var spin := f * 1.4 if kind == "attack" else 0.0
	var d := lerpf(r * 2.6, r * 1.25, e)
	var cs := r * 0.55 if kind != "barrage" else r * 0.12
	var chs: Array = it["chev"]
	for k in chs.size():
		var c: MeshInstance3D = chs[k]
		var ang := k * PI * 0.5 + (PI * 0.25 if kind == "attack" or kind == "amove" else 0.0) + spin
		var dir := Vector3(cos(ang), 0, sin(ang))
		c.position = dir * d + Vector3(0, 0.05, 0)
		c.basis = Basis.looking_at(-dir, Vector3.UP).scaled(Vector3.ONE * cs)
		c.visible = kind != "barrage" or k % 2 == 0
