class_name UnitModels
extends RefCounted
## Modelli 3D dei mezzi generati in codice (Agente F). Tutte le funzioni sono statiche.
## Dimensioni reali in metri, avanti = -Z, origine a terra (per gli aerei: sotto la fusoliera).
## Nodi con nome: "Body" (scafo), "Turret" (imbardata, asse Y), "Barrel" (elevazione, asse X), "Muzzle"/"Muzzle2" (Marker3D),
## "Rotor" (rotore principale, gira su Y), "TailRotor" (gira su X), "Prop" (elica spingente del drone, gira su Z), "Radar" (gira su Y).
## Metadati sul nodo radice: "kind", "length" (m), "height" (m), "air" (bool), "tris" (triangoli).
## Le mesh sono in cache per (tipo, colore, lod, fazione): istanziare 100 carri costa solo i nodi.
## FASE 4 — mezzi per fazione: `faction` 0 AAN, 1 FO, 2 CP, 3 UL, -1 generico (neutrali). Ogni fazione ha sagome proprie
## (FactionModels) e vernice propria (ModelKit.style); i nodi con nome e le dimensioni restano gli stessi.

const KINDS := ["inf", "tank", "art", "aa", "heli", "jet", "drone", "bunker", "truck"]
const NAVAL := ["ship", "transport"]   ## navi (NavalModels): origine sulla linea di galleggiamento
const OLIVE := Color(0.27, 0.29, 0.19)
const HELI_GREEN := Color(0.22, 0.25, 0.21)
const AIR_GRAY := Color(0.46, 0.49, 0.52)
const DRONE_GRAY := Color(0.56, 0.58, 0.6)
const DARK := Color(0.11, 0.11, 0.1)
const TRACK := Color(0.15, 0.14, 0.12)
const GUNMETAL := Color(0.2, 0.2, 0.21)
const GLASS := Color(0.1, 0.16, 0.2)
const CLOTH := Color(0.33, 0.31, 0.22)
const SKIN := Color(0.62, 0.46, 0.36)
const CONCRETE := Color(0.5, 0.49, 0.45)
const EARTH := Color(0.33, 0.27, 0.19)
const SANDBAG := Color(0.52, 0.46, 0.33)
const UNIFORM := Color(0.31, 0.32, 0.23)

## Stili di fazione (indice = fazione). base: vernice dei mezzi terrestri, heli/air/drone: velivoli, uniform: fanteria,
## camo: tipo di mimetica, wheeled: tipi che la fazione costruisce su ruote, desc: descrizione per la galleria/UI.
const FACTION_STYLES := [
	{"id": "aan", "camo": "pixel", "base": Color(0.5, 0.53, 0.47), "heli": Color(0.33, 0.35, 0.33), "air": Color(0.5, 0.53, 0.56),
		"drone": Color(0.55, 0.57, 0.59), "uniform": Color(0.5, 0.51, 0.44), "wheeled": ["truck"],
		"desc": "Mezzi squadrati e tecnologici, torrette angolari, sensori; mimetica grigio-verde a pixel"},
	{"id": "fo", "camo": "verde/sabbia", "base": Color(0.46, 0.42, 0.3), "heli": Color(0.25, 0.28, 0.2), "air": Color(0.44, 0.48, 0.52),
		"drone": Color(0.4, 0.43, 0.36), "uniform": Color(0.43, 0.42, 0.3), "wheeled": ["truck"],
		"desc": "Corazzati pesanti: torrette basse arrotondate, corazza reattiva a mattonelle, canne lunghe, cingoli larghi"},
	{"id": "cp", "camo": "navale", "base": Color(0.4, 0.45, 0.5), "heli": Color(0.38, 0.43, 0.48), "air": Color(0.52, 0.56, 0.6),
		"drone": Color(0.36, 0.39, 0.43), "uniform": Color(0.3, 0.34, 0.39), "wheeled": ["tank", "art", "aa", "truck"],
		"desc": "Mezzi leggeri e moderni su ruote 8x8, antenne di guerra elettronica, droni evoluti; grigio-blu navale"},
	{"id": "ul", "camo": "ruggine", "base": Color(0.58, 0.5, 0.36), "heli": Color(0.42, 0.42, 0.33), "air": Color(0.5, 0.49, 0.42),
		"drone": Color(0.62, 0.6, 0.55), "uniform": Color(0.4, 0.37, 0.3), "wheeled": ["truck", "art", "aa"],
		"desc": "Mezzi improvvisati: tecniche su pick-up, vecchi carri con gabbie e sacchetti, artiglieria su camion; sabbia/ruggine"},
]

static var _cache := {}
static var _fac := -1   ## fazione del modello in costruzione (usata da _cached e _paint)
static var _no_marks := false   ## true mentre si costruiscono le pedine: niente numeri tattici

# ============================================================== API
static func build(kind: String, color: Color, lod: int = 0, faction: int = -1) -> Node3D:
	return _make(kind, color, clampi(lod, 0, 2), false, 0.15, faction)

static func miniature(kind: String, color: Color, faction: int = -1) -> Node3D:
	if kind in NAVAL:
		return _naval_miniature(kind, color)
	var root := Node3D.new()
	root.name = "Miniature"
	_no_marks = true
	var model := _make(kind, color, 1, false, 0.35, faction)
	_no_marks = false
	var L: float = model.get_meta("length", 7.0)
	var air: bool = model.get_meta("air", false)
	var s := 1.6 / maxf(L, 1.0)
	if kind == "inf":
		s = 1.6 / 4.0
	model.scale = Vector3.ONE * s
	model.position = Vector3(0, 0.16 + (0.75 if air else 0.0), 0)
	root.add_child(model)
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = _cached("mini_base", color, 0, false, 0.0, func(b: ModelKit) -> void:
		b.cyl("metal", 1.0, 0.94, 0.12, 28, Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)), Color(0.16, 0.16, 0.15))
		b.cyl("faction", 1.03, 1.03, 0.08, 28, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), color, false)
		b.cyl("matte", 0.9, 0.9, 0.012, 24, Transform3D(Basis.IDENTITY, Vector3(0, 0.126, 0)), Color(0.24, 0.26, 0.2).lerp(color, 0.25))
		if air:
			b.cyl_ab("metal", Vector3(0, 0.12, 0), Vector3(0, 0.12 + 0.8, 0), 0.035, 0.03, 8, Color(0.25, 0.25, 0.25)))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(base)
	root.set_meta("kind", kind)
	root.set_meta("air", air)
	root.set_meta("faction", faction)
	return root

## Pedina navale: nave lunga ~3 unità su una basetta ovale "a onde" con bordo della fazione (galleggiamento = piano della basetta).
static func _naval_miniature(kind: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Miniature"
	var model := _make(kind, color, 1, false, 0.3)
	var L: float = model.get_meta("length", 120.0)
	var s := 3.0 / L
	model.scale = Vector3.ONE * s
	model.position = Vector3(0, 0.15, 0)
	root.add_child(model)
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = _cached("mini_base_naval", color, 0, false, 0.0, func(b: ModelKit) -> void:
		var ov: Array = []
		var ov2: Array = []
		var ov3: Array = []
		for i in 32:
			var a := TAU * float(i) / 32.0
			ov.append(Vector2(cos(a) * 0.82, sin(a) * 1.85))
			ov2.append(Vector2(cos(a) * 0.86, sin(a) * 1.89))
			ov3.append(Vector2(cos(a) * 0.74, sin(a) * 1.77))
		b.prism_y("metal", ov, 0.0, 0.13, Color(0.16, 0.16, 0.15), 0.96)
		b.prism_y("faction", ov2, 0.02, 0.09, color)
		b.prism_y("matte", ov3, 0.13, 0.142, Color(0.1, 0.17, 0.22).lerp(color, 0.12))
		# scia di schiuma sulla basetta
		b.face("matte", [Vector3(0, 0.145, 1.3), Vector3(0.22, 0.145, 1.75), Vector3(-0.22, 0.145, 1.75)], Color(0.62, 0.68, 0.7), Vector3(0, 0.0, 1.5))
		b.face("matte", [Vector3(0, 0.145, -1.45), Vector3(0.12, 0.145, -1.2), Vector3(-0.12, 0.145, -1.2)], Color(0.55, 0.62, 0.65), Vector3(0, 0.0, -1.3))
		)
	root.add_child(base)
	root.set_meta("kind", kind)
	root.set_meta("air", false)
	root.set_meta("naval", true)
	return root

## FANTERIA ANIMATA (soldier.gdshader): la mesh "Body" della squadra ha meta "rig" = true quando i soldati sono animati
## dallo shader. Per ogni MeshInstance3D "Body": set_instance_shader_parameter("anim", inf_anim_vec(...)) ogni frame
## (una chiamata per squadra) e una volta "seed" (float casuale, sfasa respiro/sguardi/passo tra le squadre).
static func inf_rigged(model: Node3D) -> bool:
	var bd := model.get_node_or_null("Body") as MeshInstance3D
	return bd != null and bd.mesh != null and bd.mesh.has_meta("rig")

## Radianti di fase del passo per metro percorso (alla velocità `speed` m/s nella scala del modello): fase += v·dt·rate.
## Lunghezza del passo coerente con l'ampiezza delle gambe nello shader, così i piedi non scivolano.
static func inf_step_rate(speed: float) -> float:
	var A := clampf(0.16 + 0.085 * speed, 0.2, 0.62) * clampf(speed * 1.2, 0.3, 1.0)
	return 1.0 / (0.88 * A)

## Parametro per istanza dello shader: `phase` fase del passo, `speed` m/s (scala del modello), `crouch` 0..1 (in ginocchio,
## il quinto soldato a terra), `aim` 0..1 (fucile in spalla), `firing` rinculo, `dead_t` >= 0: secondi dalla morte (caduta,
## dopo 4 s sprofonda: nascondere il modello dopo ~6 s).
static func inf_anim_vec(phase: float, speed: float, crouch: float, aim: float, firing: bool, dead_t: float = -1.0) -> Vector4:
	return Vector4(wrapf(phase, 0.0, TAU * 64.0), -1.0 - dead_t if dead_t >= 0.0 else speed, crouch, aim + (1.0 if firing else 0.0))

static func wreck(kind: String, faction: int = -1) -> Node3D:
	var root := _make(kind, Color(0.1, 0.1, 0.1), 0, true, 0.0, faction)
	root.name = "Wreck"
	for n in ["Muzzle", "Muzzle2"]:
		var m := root.find_child(n, true, false)
		if m:
			m.get_parent().remove_child(m)
			m.free()
	var tur := root.find_child("Turret", true, false) as Node3D
	if tur and kind in ["tank", "art", "aa"]:
		tur.rotation = Vector3(0.06, 0.55, -0.1)
		tur.position += Vector3(0.25, -0.05, 0.3)
	var bar := root.find_child("Barrel", true, false) as Node3D
	if bar:
		bar.rotation.x = -0.12
	var rot := root.find_child("Rotor", true, false) as Node3D
	if rot:
		rot.rotation = Vector3(0.12, 0.4, 0.18)
	var body := root.find_child("Body", true, false) as Node3D
	if body:
		body.position.y -= 0.12
		body.rotation.z = 0.04
	if kind in ["heli", "jet", "drone"]:
		root.rotation = Vector3(0.05, 0, 0.12)
	if kind in NAVAL:
		# nave affondata a metà: sbandata e appoppata
		root.rotation = Vector3(-0.04, 0, 0.16)
		root.position.y = -2.5
	return root

## Stato di danno visivo di un modello (frac 0 = intatto, 1 = distrutto ma ancora in gioco).
## 0.15+: annerimento leggero e filo di fumo grigio; 0.45+: fuliggine marcata e fumo scuro; 0.75+: fiamme, fumo nero e braci.
## Idempotente ed economico: ricrea gli effetti solo quando cambia la fascia. Gli effetti stanno nel figlio "Damage".
static func set_damage(node: Node3D, frac: float) -> void:
	if node == null:
		return
	var f := clampf(frac, 0.0, 1.0)
	var lvl := 0 if f < 0.15 else (1 if f < 0.45 else (2 if f < 0.75 else 3))
	if node.has_meta("dmg_lvl") and int(node.get_meta("dmg_lvl")) == lvl:
		return
	node.set_meta("dmg_lvl", lvl)
	var old := node.get_node_or_null("Damage")
	if old != null:
		old.name = "DamageOld"
		old.queue_free()
	var ov: Material = null if lvl == 0 else _soot_mat(lvl)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).begins_with("Base") and String(mi.name) != "Blur":
			(mi as MeshInstance3D).material_overlay = ov
	# sospensioni cedute / cingolo rotto: dal livello 2 il mezzo terrestre si abbassa e pende da un lato
	var body := node.get_node_or_null("Body") as Node3D
	if body != null and not bool(node.get_meta("air", false)) and not bool(node.get_meta("naval", false)) and String(node.get_meta("kind", "")) not in ["inf", "bunker"]:
		var sag := 0.0 if lvl < 2 else (0.07 if lvl == 2 else 0.12)
		var tilt := 0.0 if lvl < 2 else (0.035 if lvl == 2 else 0.06)
		var sgn := 1.0 if (node.get_instance_id() % 2) == 0 else -1.0
		for ch in node.get_children():
			if ch is Node3D and ch.name != "Damage" and ch.name != "DamageOld":
				var n3 := ch as Node3D
				var base: Vector3 = n3.get_meta("dmg_base", n3.position)
				n3.set_meta("dmg_base", base)
				n3.position = base + Vector3(0, -sag, 0)
				n3.rotation.z = tilt * sgn
	if lvl == 0 or not node.is_inside_tree():
		return
	var holder := Node3D.new()
	holder.name = "Damage"
	node.add_child(holder)
	var h: float = node.get_meta("height", 2.5)
	var L: float = node.get_meta("length", 7.0)
	var size := clampf(L / 7.0, 0.5, 6.0)
	var pos := Vector3(0, h * 0.75, L * 0.12)
	if bool(node.get_meta("naval", false)):
		pos = Vector3(0, h * 0.35, L * 0.05)
	match lvl:
		1: Vfx.fire(holder, pos, size * 0.8, 0.0, false)
		2: Vfx.fire(holder, pos, size * 1.2, 0.0, false)
		3: Vfx.fire(holder, pos, size * 1.0, 0.0, true)

## Numeri tattici e stemmi: per ogni mesh con meta "marks" (posti registrati dal costruttore con ModelKit.mark) aggiunge un
## figlio "Marks" con i quad (mesh in cache sulla mesh stessa) e il materiale della fazione. Il numero si imposta con set_number.
static func _attach_marks(root: Node3D, c: Color, faction: int) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.mesh.has_meta("marks"):
			continue
		var mm: ArrayMesh
		if mi.mesh.has_meta("marks_mesh"):
			mm = mi.mesh.get_meta("marks_mesh")
		else:
			mm = _marks_mesh(mi.mesh.get_meta("marks"), c)
			mi.mesh.set_meta("marks_mesh", mm)
		var q := MeshInstance3D.new()
		q.name = "Marks"
		q.mesh = mm
		q.material_override = ModelKit.marks_mat(faction if faction >= 0 and faction < 4 else 4)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(q)

static func _marks_mesh(marks: Array, c: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mk in marks:
		var p: Vector3 = mk[0]
		var n: Vector3 = mk[1]
		var w: float = mk[2] * 1.1
		var h: float = mk[3] * 1.2
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
		var right := up.cross(n).normalized()   # "destra" guardando il fianco dall'esterno
		up = n.cross(right).normalized()
		p += n * 0.012
		var corners := [p - right * w * 0.5 + up * h * 0.5, p + right * w * 0.5 + up * h * 0.5, p + right * w * 0.5 - up * h * 0.5, p - right * w * 0.5 - up * h * 0.5]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_color(c)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	var m := st.commit()
	m.set_meta("tris", marks.size() * 2)
	return m

## Numero tattico (0..999) di un modello: lo mostrano i quad "Marks" (vedi _attach_marks). Niente da fare se il modello non ne ha.
static func set_number(model: Node3D, num: int) -> void:
	for q in model.find_children("Marks", "MeshInstance3D", true, false):
		(q as GeometryInstance3D).set_instance_shader_parameter(&"num", float(posmod(num, 1000)))

## Movimento di un mezzo: `roll` metri percorsi (ruote che girano e cingoli che scorrono), `mud` 0..1 fango accumulato.
## Una chiamata per mezzo e per frame quando si muove: aggiorna i parametri per istanza dello scafo ("Body").
static func set_motion(model: Node3D, roll: float, mud: float) -> void:
	var bd := model.get_node_or_null("Body") as GeometryInstance3D
	if bd == null:
		return
	bd.set_instance_shader_parameter(&"roll", roll)
	bd.set_instance_shader_parameter(&"mud", mud)

## Dischi di sfocatura sotto i nodi "Rotor"/"TailRotor" (figli "Blur": girano con il rotore, nessuna ombra).
static func _rotor_blur(root: Node3D) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if not (nm.begins_with("Rotor") or nm.begins_with("TailRotor")):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := mi.mesh.get_aabb()
		var tail := nm.begins_with("TailRotor")
		var r := (maxf(bb.size.y, bb.size.z) if tail else maxf(bb.size.x, bb.size.z)) * 0.5
		if r < 0.3:
			continue
		var d := MeshInstance3D.new()
		d.name = "Blur"
		d.mesh = _blur_mesh()
		d.scale = Vector3.ONE * r
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.material_override = _blur_mat()
		var cpos := bb.get_center()
		if tail:
			d.position = Vector3(cpos.x, 0, 0)
			d.rotation.z = PI * 0.5
		else:
			d.position = Vector3(0, cpos.y, 0)
		mi.add_child(d)

static func _blur_mesh() -> Mesh:
	if _cache.has("_blur_mesh"):
		return _cache["_blur_mesh"]
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	_cache["_blur_mesh"] = pm
	return pm

static func _blur_mat() -> Material:
	if _cache.has("_blur_mat"):
		return _cache["_blur_mat"]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/models/rotor_blur.gdshader")
	_cache["_blur_mat"] = m
	return m

static func _soot_mat(lvl: int) -> Material:
	var key := "soot%d" % lvl
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.03, 0.025, 0.02, [0.0, 0.45, 0.7, 0.88][lvl])
	m.roughness = 1.0
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 0.03
	nz.fractal_octaves = 3
	nt.noise = nz
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.9), Color(1, 1, 1, 1)])
	nt.color_ramp = g
	m.albedo_texture = nt
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.35
	_cache[key] = m
	return m

# ============================================================== infrastruttura
static func _cached(key: String, c: Color, lod: int, burnt: bool, tint: float, fn: Callable) -> ArrayMesh:
	var k := "%s|%s|%d|%s|%.2f|f%d" % [key, c.to_html(false), lod, burnt, tint, _fac]
	if _cache.has(k):
		return _cache[k]
	var b := ModelKit.new(c, burnt)
	b.style = _fac
	fn.call(b)
	var m := b.commit()
	m.set_meta("tris", b.tri_count())
	_cache[k] = m
	return m

static func _mi(n: String, mesh: ArrayMesh, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	return mi

static func _marker(n: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	return m

## Vernice militare con una tinta della fazione, mantenendo la luminosità cupa della vernice di base.
static func _paint(base: Color, c: Color, tint: float) -> Color:
	base = _base(base)
	if _fac >= 0:
		tint *= 0.45   # la fazione si riconosce già da sagoma, vernice e insegne

	var mix := base.lerp(c, tint)
	var lb := base.get_luminance()
	var lm := maxf(mix.get_luminance(), 0.001)
	var out := mix * (lb * (1.0 + tint * 0.4) / lm)
	out.a = 1.0
	return out

## Vernice di base della fazione corrente al posto di quella generica (OLIVE, HELI_GREEN, AIR_GRAY, DRONE_GRAY, UNIFORM).
static func _base(base: Color) -> Color:
	if _fac < 0 or _fac >= FACTION_STYLES.size():
		return base
	var st: Dictionary = FACTION_STYLES[_fac]
	if base == OLIVE:
		return st["base"]
	if base == HELI_GREEN:
		return st["heli"]
	if base == AIR_GRAY:
		return st["air"]
	if base == DRONE_GRAY:
		return st["drone"]
	if base == UNIFORM:
		return st["uniform"]
	return base

static func _make(kind: String, c: Color, lod: int, burnt: bool, tint: float, faction: int = -1) -> Node3D:
	var root := Node3D.new()
	root.name = "Unit_" + kind
	var prev := _fac
	_fac = faction if faction >= 0 and faction < FACTION_STYLES.size() and not (kind in NAVAL) else -1
	if _fac >= 0 and FactionModels.build_into(root, kind, c, lod, burnt, tint, _fac):
		pass
	else:
		_make_generic(root, kind, c, lod, burnt, tint)
	_fac = prev
	if not burnt and lod < 2 and kind in ["heli", "drone"]:
		_rotor_blur(root)
	if not burnt and lod < 2 and not _no_marks:
		_attach_marks(root, c, faction)
	var tris := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mm := (n as MeshInstance3D).mesh
		if mm and mm.has_meta("tris"):
			tris += int(mm.get_meta("tris"))
	root.set_meta("kind", kind)
	root.set_meta("tris", tris)
	root.set_meta("faction", faction)
	return root

static func _make_generic(root: Node3D, kind: String, c: Color, lod: int, burnt: bool, tint: float) -> void:
	match kind:
		"tank": _tank(root, c, lod, burnt, tint)
		"art": _art(root, c, lod, burnt, tint)
		"aa": _aa(root, c, lod, burnt, tint)
		"heli": _heli(root, c, lod, burnt, tint)
		"jet": _jet(root, c, lod, burnt, tint)
		"drone": _drone(root, c, lod, burnt, tint)
		"bunker": _bunker(root, c, lod, burnt, tint)
		"truck": _truck(root, c, lod, burnt, tint)
		"ship": NavalModels.destroyer(root, c, lod, burnt, tint)
		"transport": NavalModels.transport(root, c, lod, burnt, tint)
		_: _inf(root, c, lod, burnt, tint)

static func _rx() -> Basis:
	return Basis(Vector3.BACK, PI * 0.5)   # asse Y del cilindro -> asse X

# ============================================================== cingolato comune
static func _chassis(b: ModelKit, pc: Color, hl: float, hw: float, lod: int, nwheels: int) -> void:
	b.camo = 1.0
	b.dirt_h = 1.15
	var c := b.fac
	# scafo inferiore (tra i cingoli) e superiore (sopra i cingoli, piastra frontale inclinata)
	b.prism_x("paint", [Vector2(-hl - 0.05, 1.0), Vector2(-hl + 0.55, 0.42), Vector2(hl - 0.35, 0.42), Vector2(hl - 0.05, 1.0)], -(hw - 0.6), hw - 0.6, pc * 0.9)
	b.prism_x("paint", [Vector2(-hl - 0.05, 1.0), Vector2(-hl - 0.14, 1.14), Vector2(-hl + 1.35, 1.58), Vector2(hl - 0.25, 1.62),
		Vector2(hl - 0.04, 1.5), Vector2(hl - 0.04, 1.0)], -hw, hw, pc)
	var segw := 14 if lod == 0 else (10 if lod == 1 else 6)
	for s in [-1.0, 1.0]:
		var xo: float = s * (hw - 0.02)
		var xi: float = s * (hw - 0.64)
		# cingolo
		b.prism_x("track", [Vector2(-hl + 0.8, 0.0), Vector2(hl - 0.8, 0.0), Vector2(hl + 0.02, 0.55), Vector2(hl + 0.02, 0.86),
			Vector2(hl - 0.3, 0.99), Vector2(-hl + 0.2, 0.99), Vector2(-hl - 0.12, 0.86), Vector2(-hl - 0.12, 0.55)], minf(xo, xi), maxf(xo, xi), TRACK)
		# ruote portanti (girano: wheel.gdshader) e rulli di ritorno
		for i in nwheels:
			var z := lerpf(-hl + 0.9, hl - 0.95, float(i) / float(nwheels - 1))
			b.wheel(Vector3(s * (hw - 0.07), 0.43, z), 0.4, 0.13, segw, pc * 0.85, lod, 0.72)
		if lod == 0:
			for i in 3:
				var z := lerpf(-hl + 1.6, hl - 1.6, float(i) / 2.0)
				b.wheel(Vector3(s * (hw - 0.1), 0.86, z), 0.11, 0.1, 8, pc * 0.7, 2, 0.5)
		# ruota motrice (dentata) dietro e tenditrice davanti
		b.wheel_begin(Vector3(s * (hw - 0.12), 0.72, hl - 0.28), 0.37)
		b.cyl("wheel_metal", 0.37, 0.37, 0.2, 12 if lod < 2 else 6, Transform3D(_rx(), Vector3(s * (hw - 0.12), 0.72, hl - 0.28)), GUNMETAL, true, false)
		if lod == 0:
			for k in 6:
				var a := TAU * float(k) / 6.0
				b.box("wheel_metal", Vector3(0.22, 0.1, 0.1), Vector3(s * (hw - 0.12), 0.72 + cos(a) * 0.4, hl - 0.28 + sin(a) * 0.4), GUNMETAL * 1.1, 0.0, Basis(Vector3.RIGHT, -a))
		b.wheel_end()
		b.wheel(Vector3(s * (hw - 0.12), 0.68, -hl + 0.12), 0.31, 0.18, segw, pc * 0.8, lod, 0.7, pc * 0.6)
		# minigonne laterali (coprono la parte alta delle ruote)
		b.box("paint", Vector3(0.07, 0.52, hl * 2.0 - 0.7), Vector3(s * (hw + 0.03), 0.8, 0.05), pc, 0.02)
		b.box("paint", Vector3(0.07, 0.32, 0.5), Vector3(s * (hw + 0.03), 0.9, -hl + 0.16), pc, 0.02, Basis(Vector3.RIGHT, -0.5))
		# banda della fazione sulle minigonne
		b.box("faction", Vector3(0.02, 0.2, 1.3), Vector3(s * (hw + 0.075), 0.86, -hl + 1.3), c)
		if lod < 2:
			# parafanghi anteriori e cassette portaoggetti posteriori
			b.box("paint", Vector3(0.62, 0.04, 0.45), Vector3(s * (hw - 0.31), 1.02, -hl - 0.15), pc, 0.0, Basis(Vector3.RIGHT, -0.25))
			b.box("paint", Vector3(0.5, 0.32, 1.3), Vector3(s * (hw - 0.3), 1.79, hl - 0.95), pc * 0.95, 0.04)
			# fari
			b.box("glass", Vector3(0.16, 0.12, 0.06), Vector3(s * (hw - 0.45), 1.2, -hl - 0.12), GLASS)
			b.box("metal", Vector3(0.24, 0.04, 0.16), Vector3(s * (hw - 0.45), 1.29, -hl - 0.12), GUNMETAL)
	if lod < 2:
		# griglie motore, scarichi, portello del pilota, pannello di riconoscimento aereo
		for i in 4:
			b.box("metal", Vector3(0.48, 0.03, 0.85), Vector3(-0.99 + i * 0.66, 1.635, hl - 1.25), DARK)
		b.box("metal", Vector3(0.9, 0.18, 0.08), Vector3(-0.8, 1.25, hl - 0.0), DARK)
		b.box("metal", Vector3(0.9, 0.18, 0.08), Vector3(0.8, 1.25, hl - 0.0), DARK)
		b.cyl("paint", 0.32, 0.32, 0.06, 14, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 1.5, -hl + 1.05)), pc * 0.9)
		for i in 3:
			b.box("glass", Vector3(0.16, 0.06, 0.05), Vector3(-0.2 + i * 0.2, 1.57, -hl + 1.33), GLASS)
		b.box("faction", Vector3(1.1, 0.02, 0.6), Vector3(0.0, 1.645, hl - 0.45), c)
		b.box("metal", Vector3(0.3, 0.12, 0.12), Vector3(-0.9, 0.55, -hl + 0.4), GUNMETAL)
		b.box("metal", Vector3(0.3, 0.12, 0.12), Vector3(0.9, 0.55, -hl + 0.4), GUNMETAL)
	if lod == 0:
		# taniche sul retro e cavo di traino
		b.box("paint", Vector3(0.18, 0.46, 0.34), Vector3(-0.35, 1.2, hl + 0.14), pc * 0.75, 0.03)
		b.box("paint", Vector3(0.18, 0.46, 0.34), Vector3(-0.1, 1.2, hl + 0.14), pc * 0.75, 0.03)
		b.cyl_ab("metal", Vector3(hw - 0.05, 1.66, -1.0), Vector3(hw - 0.05, 1.66, 1.6), 0.03, 0.03, 5, GUNMETAL)

## Banda colorata attorno a una torretta prism_y (stessa pianta e rastremazione).
static func _band(b: ModelKit, prof: Array, h: float, ts: float, toff: Vector2, y0: float, y1: float, col: Color) -> void:
	var c2 := Vector2.ZERO
	for p in prof:
		c2 += p
	c2 /= float(prof.size())
	var f0 := y0 / h
	var f1 := y1 / h
	var s0 := lerpf(1.0, ts, f0) * 1.012
	var s1 := lerpf(1.0, ts, f1) * 1.012
	var pr: Array = []
	for p in prof:
		pr.append(c2 + (p - c2) * s0 + toff * f0)
	b.prism_y("faction", pr, y0, y1, col, s1 / s0, toff * (f1 - f0))

# ============================================================== carro armato
static func _tank(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(OLIVE, c, tint)
	var hl := 3.55
	var hw := 1.78
	root.add_child(_mi("Body", _cached("tank_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_chassis(b, pc, hl, hw, lod, 7))))
	var prof := [Vector2(-0.5, -2.05), Vector2(0.5, -2.05), Vector2(1.55, -1.2), Vector2(1.66, 0.9), Vector2(1.38, 1.75),
		Vector2(-1.38, 1.75), Vector2(-1.66, 0.9), Vector2(-1.55, -1.2)]
	var tur := _mi("Turret", _cached("tank_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 0.82, pc, 0.9, Vector2(0, 0.08))
		_band(b, prof, 0.82, 0.9, Vector2(0, 0.08), 0.34, 0.56, b.fac)
		b.marks_x(1.6, 0.18, 0.1, 0.9, 0.26, 0.2)
		b.box("paint", Vector3(0.95, 0.62, 0.45), Vector3(0, 0.42, -2.1), pc * 0.92, 0.05)
		# pannello di riconoscimento sul tetto
		b.box("faction", Vector3(1.0, 0.025, 0.9), Vector3(-0.35, 0.835, 0.75), b.fac)
		if lod < 2:
			# cupola del capocarro con mitragliatrice
			b.cyl("paint", 0.38, 0.34, 0.26, 14, Transform3D(Basis.IDENTITY, Vector3(0.7, 0.94, 0.45)), pc)
			b.cyl("paint", 0.3, 0.3, 0.06, 12, Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0.7, 1.2, 0.75)), pc * 0.9)
			b.cyl_ab("metal", Vector3(0.7, 1.07, 0.2), Vector3(0.7, 1.32, 0.15), 0.03, 0.03, 6, GUNMETAL)
			b.box("metal", Vector3(0.13, 0.15, 0.55), Vector3(0.7, 1.38, -0.05), DARK, 0.02)
			b.cyl_ab("metal", Vector3(0.7, 1.39, -0.32), Vector3(0.7, 1.39, -1.25), 0.025, 0.025, 6, DARK)
			b.box("paint", Vector3(0.12, 0.14, 0.22), Vector3(0.82, 1.32, 0.0), pc * 0.7)
			# mirino del cannoniere
			b.box("paint", Vector3(0.38, 0.36, 0.5), Vector3(-0.85, 0.98, -0.95), pc, 0.04)
			b.box("glass", Vector3(0.28, 0.22, 0.04), Vector3(-0.85, 1.0, -1.21), GLASS)
			# portello del servente
			b.cyl("paint", 0.3, 0.3, 0.07, 12, Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.85, 0.35)), pc * 0.9)
			# lanciafumogeni
			for s in [-1.0, 1.0]:
				for i in 4:
					b.cyl_ab("metal", Vector3(s * (1.35 + i * 0.06), 0.62 + (i % 2) * 0.12, -1.25 + i * 0.12),
						Vector3(s * (1.62 + i * 0.06), 0.8 + (i % 2) * 0.12, -1.45 + i * 0.12), 0.055, 0.055, 7, DARK)
		if lod == 0:
			# cesto portaoggetti posteriore
			b.box("metal", Vector3(2.5, 0.04, 0.72), Vector3(0, 0.28, 2.1), GUNMETAL)
			for s in [-1.0, 1.0]:
				b.box("metal", Vector3(0.04, 0.5, 0.72), Vector3(s * 1.25, 0.52, 2.1), GUNMETAL)
				b.cyl_ab("metal", Vector3(s * 1.25, 0.78, 1.74), Vector3(s * 1.25, 0.78, 2.46), 0.02, 0.02, 4, GUNMETAL)
			b.cyl_ab("metal", Vector3(-1.25, 0.78, 2.46), Vector3(1.25, 0.78, 2.46), 0.02, 0.02, 4, GUNMETAL)
			for i in 6:
				b.cyl_ab("metal", Vector3(-1.25 + i * 0.5, 0.3, 2.46), Vector3(-1.25 + i * 0.5, 0.78, 2.46), 0.015, 0.015, 4, GUNMETAL)
			b.cyl("matte", 0.2, 0.2, 2.1, 10, Transform3D(_rx(), Vector3(0, 0.52, 2.25)), CLOTH)
			b.box("paint", Vector3(0.7, 0.36, 0.45), Vector3(-0.7, 0.5, 1.95), pc * 0.7, 0.03)
			b.box("matte", Vector3(0.6, 0.3, 0.42), Vector3(0.65, 0.48, 1.95), CLOTH * 0.85, 0.06)
			# antenna con fiamma della fazione
			b.cyl_ab("metal", Vector3(-1.05, 0.82, 1.45), Vector3(-1.05, 3.3, 1.5), 0.02, 0.008, 4, DARK)
			b.face("faction", [Vector3(-1.05, 3.25, 1.5), Vector3(-1.05, 3.0, 1.5), Vector3(-1.05, 3.12, 2.05)], b.fac, Vector3(-1.2, 3.1, 1.6))
			b.face("faction", [Vector3(-1.05, 3.25, 1.5), Vector3(-1.05, 3.0, 1.5), Vector3(-1.05, 3.12, 2.05)], b.fac, Vector3(-0.9, 3.1, 1.6))
		), Vector3(0, 1.62, 0.25))
	root.add_child(tur)
	var bar := _mi("Barrel", _cached("tank_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.1), Vector3(0, 0, -5.2), 0.12, 0.1, sg, pc * 0.95)
		b.cyl_ab("paint", Vector3(0, 0, -2.4), Vector3(0, 0, -3.1), 0.17, 0.17, sg, pc * 0.88)
		b.cyl_ab("metal", Vector3(0, 0, -5.15), Vector3(0, 0, -5.4), 0.12, 0.12, sg, GUNMETAL)
		b.cyl_ab("metal", Vector3(0, 0, -5.39), Vector3(0, 0, -5.4), 0.06, 0.06, sg, Color(0.02, 0.02, 0.02))
		), Vector3(0, 0.42, -2.25))
	tur.add_child(bar)
	bar.add_child(_marker("Muzzle", Vector3(0, 0, -5.45)))
	root.set_meta("length", 7.3)
	root.set_meta("height", 2.5)
	root.set_meta("air", false)

# ============================================================== artiglieria semovente
static func _art(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(OLIVE, c, tint)
	var hl := 3.7
	var hw := 1.72
	root.add_child(_mi("Body", _cached("art_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_chassis(b, pc, hl, hw, lod, 7)
		if lod < 2:
			# blocco di marcia della canna sul glacis
			b.box("paint", Vector3(0.12, 0.6, 0.12), Vector3(-0.15, 1.75, -hl + 0.8), pc * 0.8)
			b.box("paint", Vector3(0.12, 0.6, 0.12), Vector3(0.15, 1.75, -hl + 0.8), pc * 0.8)
			b.box("paint", Vector3(0.5, 0.1, 0.2), Vector3(0, 2.05, -hl + 0.8), pc * 0.8)
		)))
	var prof := [Vector2(-1.45, -1.55), Vector2(1.45, -1.55), Vector2(1.62, -0.95), Vector2(1.62, 2.35), Vector2(-1.62, 2.35), Vector2(-1.62, -0.95)]
	var tur := _mi("Turret", _cached("art_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 1.3, pc, 0.94, Vector2(0, 0.05))
		_band(b, prof, 1.3, 0.94, Vector2(0, 0.05), 0.55, 0.8, b.fac)
		b.marks_x(1.595, 0.3, -0.2, 1.0, 0.4, 0.075)
		b.box("faction", Vector3(1.4, 0.025, 1.2), Vector3(0.0, 1.315, 1.2), b.fac)
		b.box("paint", Vector3(1.0, 0.85, 0.35), Vector3(0, 0.7, -1.6), pc * 0.9, 0.06)
		if lod < 2:
			b.cyl("paint", 0.34, 0.3, 0.25, 12, Transform3D(Basis.IDENTITY, Vector3(0.85, 1.42, 0.2)), pc)
			b.cyl_ab("metal", Vector3(0.85, 1.55, 0.0), Vector3(0.85, 1.6, -0.9), 0.025, 0.025, 6, DARK)
			b.box("paint", Vector3(0.4, 0.35, 0.45), Vector3(-0.95, 1.45, -0.9), pc, 0.04)
			b.box("glass", Vector3(0.3, 0.2, 0.04), Vector3(-0.95, 1.48, -1.14), GLASS)
			for s in [-1.0, 1.0]:
				b.box("paint", Vector3(0.05, 0.9, 1.2), Vector3(s * 1.63, 0.6, 1.2), pc * 0.85)   # portelli munizioni
		if lod == 0:
			b.cyl_ab("metal", Vector3(-1.2, 1.3, 2.1), Vector3(-1.2, 3.6, 2.15), 0.02, 0.008, 4, DARK)
			b.face("faction", [Vector3(-1.2, 3.55, 2.15), Vector3(-1.2, 3.3, 2.15), Vector3(-1.2, 3.42, 2.7)], b.fac, Vector3(-1.3, 3.4, 2.2))
			b.face("faction", [Vector3(-1.2, 3.55, 2.15), Vector3(-1.2, 3.3, 2.15), Vector3(-1.2, 3.42, 2.7)], b.fac, Vector3(-1.1, 3.4, 2.2))
			b.box("matte", Vector3(2.2, 0.25, 0.3), Vector3(0, 1.45, 2.1), CLOTH * 0.9, 0.08)
		), Vector3(0, 1.62, 0.95))
	root.add_child(tur)
	var bar := _mi("Barrel", _cached("art_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var sg := 12 if lod == 0 else 8
		b.cyl_ab("paint", Vector3(0, 0, 0.3), Vector3(0, 0, -7.2), 0.13, 0.1, sg, pc * 0.95)
		b.cyl_ab("paint", Vector3(0, 0, -3.0), Vector3(0, 0, -3.9), 0.17, 0.17, sg, pc * 0.85)
		b.box("metal", Vector3(0.42, 0.3, 0.7), Vector3(0, 0, -7.4), GUNMETAL, 0.04)
		b.box("metal", Vector3(0.44, 0.14, 0.12), Vector3(0, 0, -7.6), DARK)
		b.cyl_ab("paint", Vector3(0, 0.22, 0.2), Vector3(0, 0.22, -1.2), 0.08, 0.08, 8, pc * 0.8)
		), Vector3(0, 0.75, -1.65))
	tur.add_child(bar)
	bar.add_child(_marker("Muzzle", Vector3(0, 0, -7.8)))
	root.add_child(spades(c, lod, burnt, tint, pc, Vector3(0, 1.0, hl + 0.1), 2.6))
	root.set_meta("length", 7.5)
	root.set_meta("height", 3.0)
	root.set_meta("air", false)

## Vomeri posteriori dell'artiglieria (nodo "Spades", cerniera nell'origine): due pale che pendono verso -Y; in marcia il nodo
## sta a rotation.x ≈ -1.3 (pale alzate all'indietro), piazzata a ≈ +0.35 (pale a terra). `w` = larghezza totale.
static func spades(c: Color, lod: int, burnt: bool, tint: float, pc: Color, pos: Vector3, w: float) -> MeshInstance3D:
	var mi := _mi("Spades", _cached("art_spades_%.1f" % w, c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.07, 0.07, w, 8, Transform3D(_rx(), Vector3.ZERO), GUNMETAL)
		for s: float in [-1.0, 1.0]:
			var x := s * w * 0.27
			b.box("paint", Vector3(0.12, 0.75, 0.12), Vector3(x, -0.4, 0.0), pc * 0.8)
			b.box("paint", Vector3(w * 0.42, 0.45, 0.06), Vector3(x, -0.95, 0.0), pc * 0.85, 0.02, Basis(Vector3.RIGHT, 0.12))
			b.box("metal", Vector3(w * 0.42, 0.08, 0.1), Vector3(x, -1.17, -0.03), GUNMETAL)
		), pos)
	mi.rotation.x = -1.3
	return mi

# ============================================================== contraerea semovente
static func _aa(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(OLIVE, c, tint)
	var hl := 3.45
	var hw := 1.65
	root.add_child(_mi("Body", _cached("aa_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		_chassis(b, pc, hl, hw, lod, 6))))
	var prof := [Vector2(-1.0, -1.3), Vector2(1.0, -1.3), Vector2(1.25, -0.7), Vector2(1.25, 1.45), Vector2(-1.25, 1.45), Vector2(-1.25, -0.7)]
	var tur := _mi("Turret", _cached("aa_turret", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		b.prism_y("paint", prof, 0.0, 1.05, pc, 0.9, Vector2(0, 0.08))
		_band(b, prof, 1.05, 0.9, Vector2(0, 0.08), 0.45, 0.66, b.fac)
		b.marks_x(1.222, 0.24, 0.4, 0.8, 0.3, 0.12)
		b.box("faction", Vector3(0.9, 0.025, 0.7), Vector3(0.0, 1.065, 0.35), b.fac)
		# radar di tiro anteriore
		b.cyl("metal", 0.42, 0.42, 0.3, 14, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.62, -1.42)), Color(0.3, 0.31, 0.3))
		b.sphere("paint", Vector3(0, 0.62, -1.6), Vector3(0.42, 0.42, 0.18), 14, 6, pc * 1.1, false)
		if lod < 2:
			b.cyl_ab("paint", Vector3(0, 1.05, 1.0), Vector3(0, 1.5, 1.0), 0.12, 0.1, 8, pc * 0.9)
			b.cyl("paint", 0.3, 0.3, 0.2, 10, Transform3D(Basis.IDENTITY, Vector3(-0.6, 1.15, 0.0)), pc)
			b.box("paint", Vector3(2.0, 0.5, 0.5), Vector3(0, 0.5, 1.6), pc * 0.9, 0.05)
		), Vector3(0, 1.62, 0.35))
	root.add_child(tur)
	var radar := _mi("Radar", _cached("aa_radar", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.3, 0.15, 0.3), Vector3(0, 0.07, 0), GUNMETAL)
		b.box("paint", Vector3(2.1, 0.55, 0.14), Vector3(0, 0.5, 0.05), pc * 1.05, 0.05, Basis(Vector3.RIGHT, 0.25))
		b.box("metal", Vector3(2.0, 0.08, 0.1), Vector3(0, 0.22, -0.02), GUNMETAL)
		b.box("metal", Vector3(0.08, 0.3, 0.5), Vector3(0, 0.3, -0.25), GUNMETAL)
		), Vector3(0, 1.5, 1.0))
	tur.add_child(radar)
	var bar := _mi("Barrel", _cached("aa_barrel", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 1.0
		for s in [-1.0, 1.0]:
			b.box("paint", Vector3(0.45, 0.6, 1.9), Vector3(s * 1.5, 0, -0.2), pc * 0.95, 0.06)
			b.box("faction", Vector3(0.46, 0.15, 0.4), Vector3(s * 1.5, 0.15, 0.55), b.fac)
			b.cyl_ab("metal", Vector3(s * 1.5, 0.05, -1.1), Vector3(s * 1.5, 0.05, -4.3), 0.055, 0.045, 8, GUNMETAL)
			b.cyl_ab("metal", Vector3(s * 1.5, 0.05, -1.1), Vector3(s * 1.5, 0.05, -1.7), 0.1, 0.1, 8, GUNMETAL)
			b.cyl_ab("metal", Vector3(s * 1.5, 0.05, -4.05), Vector3(s * 1.5, 0.05, -4.4), 0.085, 0.085, 8, DARK)
			b.cyl_ab("paint", Vector3(s * 1.25, 0, 0), Vector3(s * 1.0, 0, 0), 0.2, 0.2, 10, pc * 0.8)
		), Vector3(0, 0.62, -0.1))
	tur.add_child(bar)
	bar.add_child(_marker("Muzzle", Vector3(-1.5, 0.05, -4.45)))
	bar.add_child(_marker("Muzzle2", Vector3(1.5, 0.05, -4.45)))
	root.set_meta("length", 7.0)
	root.set_meta("height", 3.5)
	root.set_meta("air", false)

# ============================================================== camion 6x6
static func _truck(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(OLIVE, c, tint)
	root.add_child(_mi("Body", _cached("truck_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.8
		b.dirt_h = 1.0
		var sg := 14 if lod == 0 else 8
		# telaio
		b.box("metal", Vector3(1.1, 0.25, 7.6), Vector3(0, 0.85, 0.1), DARK)
		# ruote: 1 asse anteriore, 2 posteriori
		for z in [-2.6, 1.3, 2.75]:
			for s in [-1.0, 1.0]:
				b.wheel(Vector3(s * 1.0, 0.56, z), 0.56, 0.42, sg, pc * 0.8, lod, 0.54)
		# cofano e cabina
		b.box("paint", Vector3(2.1, 0.75, 1.3), Vector3(0, 1.38, -3.15), pc, 0.08)
		b.box("metal", Vector3(1.4, 0.45, 0.06), Vector3(0, 1.3, -3.82), DARK)
		b.box("paint", Vector3(2.4, 1.25, 1.7), Vector3(0, 1.95, -1.75), pc, 0.08)
		b.box("paint", Vector3(2.42, 0.04, 1.6), Vector3(0, 2.6, -1.75), pc * 0.9, 0.02)
		b.box("glass", Vector3(2.1, 0.55, 0.04), Vector3(0, 2.22, -2.61), GLASS, 0.0, Basis(Vector3.RIGHT, 0.12))
		for s in [-1.0, 1.0]:
			b.box("glass", Vector3(0.04, 0.45, 0.8), Vector3(s * 1.21, 2.22, -1.9), GLASS)
			b.box("faction", Vector3(0.02, 0.4, 0.4), Vector3(s * 1.215, 1.7, -1.6), b.fac)
			b.box("paint", Vector3(0.5, 0.06, 0.9), Vector3(s * 1.0, 1.15, -2.7), pc * 0.85)   # parafanghi
			b.box("light", Vector3(0.2, 0.14, 0.05), Vector3(s * 0.8, 1.45, -3.82), Color(1, 0.95, 0.8))
			b.box("paint", Vector3(0.32, 0.36, 0.9), Vector3(s * 0.85, 1.05, -0.6), pc * 0.7, 0.05)  # serbatoi
		b.marks_x(1.205, 1.62, -1.1, 0.5, 0.26)
		b.box("metal", Vector3(2.3, 0.18, 0.15), Vector3(0, 0.95, -3.9), GUNMETAL)
		# cassone con telone
		b.box("paint", Vector3(2.45, 0.55, 4.4), Vector3(0, 1.3, 1.5), pc * 0.92, 0.03)
		b.camo = 0.0
		var top: Array = []
		for i in 9:
			var a := PI * float(i) / 8.0
			top.append(Vector2(cos(a) * 1.22, 1.58 + sin(a) * 1.25))
		# telone: prisma lungo Z costruito come prisma_x ruotato
		var old := b.t
		b.t = b.t * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, 1.5))
		var pr: Array = []
		for p in top:
			pr.append(Vector2(p.x, p.y))
		b.prism_x("matte", pr, -2.15, 2.15, Color(0.3, 0.31, 0.22))
		b.t = old
		b.box("faction", Vector3(1.4, 0.02, 1.2), Vector3(0, 2.84, 1.5), b.fac)
		if lod == 0:
			b.cyl("rubber", 0.5, 0.5, 0.3, 12, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.75, -0.78)), DARK)
			for i in 4:
				b.box("metal", Vector3(2.48, 0.04, 0.05), Vector3(0, 2.0 + 0.0, -0.5 + i * 1.33), GUNMETAL)
		)))
	root.add_child(_marker("Muzzle", Vector3(0, 2.0, -3.9)))
	root.set_meta("length", 7.9)
	root.set_meta("height", 2.9)
	root.set_meta("air", false)

# ============================================================== bunker in cemento
static func _bunker(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	root.add_child(_mi("Body", _cached("bunker_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		var oct: Array = []
		for i in 8:
			var a := TAU * (float(i) + 0.5) / 8.0
			oct.append(Vector2(cos(a) * 3.4, sin(a) * 3.4))
		# terrapieno
		var ring: Array = []
		for i in 12:
			var a := TAU * float(i) / 12.0
			ring.append(Vector2(cos(a) * 5.0, sin(a) * 5.0))
		b.prism_y("matte", ring, -0.05, 0.6, EARTH, 0.78)
		b.prism_y("stained", oct, 0.0, 2.0, CONCRETE, 0.86)
		b.prism_y("stained", oct.map(func(p: Vector2) -> Vector2: return p * 0.96), 2.0, 2.45, CONCRETE * 0.92, 0.9)
		# feritoia frontale
		b.box("rubber", Vector3(2.4, 0.32, 0.3), Vector3(0, 1.45, -2.78), Color(0.03, 0.03, 0.03))
		b.box("matte", Vector3(2.8, 0.12, 0.7), Vector3(0, 1.68, -3.05), CONCRETE * 0.85)
		b.box("rubber", Vector3(1.6, 0.26, 0.3), Vector3(-1.97, 1.45, -1.97), Color(0.03, 0.03, 0.03), 0.0, Basis(Vector3.UP, -PI / 4))
		b.box("rubber", Vector3(1.6, 0.26, 0.3), Vector3(1.97, 1.45, -1.97), Color(0.03, 0.03, 0.03), 0.0, Basis(Vector3.UP, PI / 4))
		b.box("metal", Vector3(0.12, 0.12, 0.9), Vector3(0.3, 1.43, -3.1), DARK)
		# fascia della fazione e bandiera
		_band(b, oct, 2.0, 0.86, Vector2.ZERO, 1.95, 2.02, b.fac)
		b.box("faction", Vector3(1.6, 0.03, 1.6), Vector3(0, 2.465, 0), b.fac)
		b.cyl_ab("metal", Vector3(2.0, 2.4, 1.4), Vector3(2.0, 6.0, 1.4), 0.05, 0.04, 6, GUNMETAL)
		b.box("faction", Vector3(0.03, 0.9, 1.4), Vector3(2.0, 5.5, 2.1), b.fac)
		# ingresso posteriore
		b.box("rubber", Vector3(1.0, 1.6, 0.4), Vector3(0, 0.8, 3.0), Color(0.04, 0.04, 0.04))
		if lod < 2:
			# sacchetti di sabbia
			for i in 16:
				var a := lerpf(-1.1, 1.1, float(i) / 15.0) - PI * 0.5
				for r in 2:
					var rr := 4.3 - r * 0.05
					var p := Vector3(cos(a) * rr, 0.62 + r * 0.24, sin(a) * rr)
					b.box("matte", Vector3(0.62, 0.24, 0.38), p, SANDBAG * (0.9 + 0.15 * ((i + r) % 3) / 2.0), 0.08, Basis(Vector3.UP, -a + PI * 0.5 + (0.12 if r == 1 else 0.0)))
			# sacchetti sul tetto
			for i in 5:
				b.box("matte", Vector3(0.6, 0.22, 0.36), Vector3(-1.5 + i * 0.62, 2.56, 1.3), SANDBAG * 0.95, 0.08, Basis(Vector3.UP, 0.1 * (i % 2)))
		)))
	root.add_child(_marker("Muzzle", Vector3(0.3, 1.43, -3.6)))
	root.set_meta("length", 9.0)
	root.set_meta("height", 2.5)
	root.set_meta("air", false)

# ============================================================== elicottero d'attacco
static func _heli(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(HELI_GREEN, c, tint)
	var sg := 12 if lod == 0 else (8 if lod == 1 else 6)
	root.add_child(_mi("Body", _cached("heli_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		# fusoliera stretta a sezione quasi rettangolare (esponente alto = spigoli vivi), muso sensori basso
		b.loft("paint", [[-6.25, 1.2, 0.05, 0.05], [-6.05, 1.22, 0.3, 0.3, 4.0], [-5.5, 1.3, 0.44, 0.5, 6.0], [-4.2, 1.5, 0.5, 0.72, 8.0],
			[-2.0, 1.72, 0.58, 0.95, 8.0], [0.0, 1.85, 0.64, 1.02, 8.0], [1.5, 1.92, 0.58, 0.92, 7.0], [2.7, 2.1, 0.3, 0.46, 4.0],
			[5.6, 2.22, 0.17, 0.23, 4.0], [6.45, 2.26, 0.12, 0.18, 3.0]], sg, pc)
		# cabina biposto in tandem a gradini, vetri piani
		b.hexa("glass", [Vector3(-0.42, 1.93, -5.2), Vector3(0.42, 1.93, -5.2), Vector3(0.5, 2.28, -3.35), Vector3(-0.5, 2.28, -3.35),
			Vector3(-0.24, 2.5, -4.55), Vector3(0.24, 2.5, -4.55), Vector3(0.32, 2.72, -3.35), Vector3(-0.32, 2.72, -3.35)], GLASS)
		b.hexa("glass", [Vector3(-0.5, 2.28, -3.45), Vector3(0.5, 2.28, -3.45), Vector3(0.56, 2.65, -1.45), Vector3(-0.56, 2.65, -1.45),
			Vector3(-0.3, 3.02, -2.95), Vector3(0.3, 3.02, -2.95), Vector3(0.34, 3.06, -1.45), Vector3(-0.34, 3.06, -1.45)], GLASS)
		# montanti del tettuccio
		b.box("paint", Vector3(0.7, 0.07, 0.08), Vector3(0, 2.73, -3.36), pc * 0.75)
		b.box("paint", Vector3(0.72, 0.07, 0.08), Vector3(0, 3.07, -1.47), pc * 0.75)
		b.cyl_ab("paint", Vector3(0, 2.5, -4.55), Vector3(0, 2.73, -3.36), 0.035, 0.035, 4, pc * 0.7)
		b.cyl_ab("paint", Vector3(0, 3.02, -2.95), Vector3(0, 3.06, -1.47), 0.035, 0.035, 4, pc * 0.7)
		# dorso: carenatura della trasmissione squadrata
		b.hexa("paint", [Vector3(-0.5, 2.6, -1.5), Vector3(0.5, 2.6, -1.5), Vector3(0.55, 2.7, 2.2), Vector3(-0.55, 2.7, 2.2),
			Vector3(-0.3, 3.1, -1.1), Vector3(0.3, 3.1, -1.1), Vector3(0.3, 3.05, 1.6), Vector3(-0.3, 3.05, 1.6)], pc * 0.95)
		for s: float in [-1.0, 1.0]:
			# gondole motori angolari con scarichi soppressi rivolti verso l'esterno
			b.box("paint", Vector3(0.62, 0.62, 2.6), Vector3(s * 0.88, 2.55, 0.5), pc * 0.92, 0.12)
			b.box("rubber", Vector3(0.5, 0.5, 0.06), Vector3(s * 0.88, 2.55, -0.82), DARK)
			b.box("paint", Vector3(0.5, 0.4, 0.8), Vector3(s * 1.05, 2.5, 2.1), pc * 0.8, 0.06, Basis(Vector3.UP, s * 0.35))
			b.box("rubber", Vector3(0.36, 0.28, 0.05), Vector3(s * 1.2, 2.5, 2.48), Color(0.03, 0.03, 0.03), 0.0, Basis(Vector3.UP, s * 0.35))
			# alette con leggero anedro
			var wt := Transform3D(Basis(Vector3.BACK, s * 0.1), Vector3(s * 0.55, 1.95, 0)).scaled_local(Vector3(s, 1, 1))
			b.plate("paint", [Vector2(0, -0.9), Vector2(2.05, -0.62), Vector2(2.05, 0.2), Vector2(0, 0.45)], 0.12, pc, wt)
			b.box("paint", Vector3(0.14, 0.22, 0.3), Vector3(s * 2.62, 2.02, -0.25), pc * 0.8)
			for pyl: float in [1.25, 2.15]:
				b.box("paint", Vector3(0.1, 0.3, 0.7), Vector3(s * pyl, 1.75, -0.25), pc * 0.7)
			# lanciarazzi (interno) e rastrelliera di 4 missili controcarro (esterno)
			b.cyl_ab("paint", Vector3(s * 1.25, 1.4, -1.25), Vector3(s * 1.25, 1.4, 0.55), 0.24, 0.24, sg, pc * 0.72)
			b.cyl_ab("metal", Vector3(s * 1.25, 1.4, -1.27), Vector3(s * 1.25, 1.4, -1.28), 0.2, 0.2, sg, DARK)
			b.box("paint", Vector3(0.5, 0.06, 1.5), Vector3(s * 2.15, 1.6, -0.25), GUNMETAL)
			if lod < 2:
				for k in 2:
					for j in 2:
						var mp := Vector3(s * (2.03 + k * 0.24), 1.48 - j * 0.24, 0)
						b.cyl_ab("paint", mp + Vector3(0, 0, 0.45), mp + Vector3(0, 0, -0.95), 0.085, 0.085, 6, Color(0.3, 0.32, 0.28))
						b.cyl_ab("paint", mp + Vector3(0, 0, -0.95), mp + Vector3(0, 0, -1.15), 0.085, 0.02, 6, Color(0.3, 0.32, 0.28))
			# carrello: ruote principali con gambe
			b.cyl("rubber", 0.34, 0.34, 0.2, 10, Transform3D(_rx(), Vector3(s * 1.05, 0.34, -2.5)), DARK)
			b.cyl_ab("metal", Vector3(s * 1.05, 0.38, -2.5), Vector3(s * 0.48, 1.25, -2.2), 0.06, 0.06, 6, GUNMETAL)
			b.cyl_ab("metal", Vector3(s * 1.05, 0.5, -2.5), Vector3(s * 0.62, 1.3, -2.85), 0.05, 0.05, 6, GUNMETAL)
			# insegna della fazione sui fianchi e listello
			b.box("faction", Vector3(0.02, 0.5, 0.9), Vector3(s * 0.645, 1.9, 0.6), b.fac)
			b.box("paint", Vector3(0.03, 0.04, 2.2), Vector3(s * 0.58, 2.3, -0.4), pc * 0.6)
		# sensori del muso (torretta di puntamento)
		b.box("paint", Vector3(0.58, 0.5, 0.55), Vector3(0, 1.1, -6.05), pc * 0.85, 0.08)
		b.cyl("paint", 0.3, 0.3, 0.62, 12, Transform3D(_rx(), Vector3(0, 0.82, -6.05)), pc * 0.8)
		for s: float in [-1.0, 1.0]:
			b.box("glass", Vector3(0.04, 0.24, 0.24), Vector3(s * 0.32, 0.82, -6.05), Color(0.18, 0.12, 0.05))
		# trave di coda: deriva a freccia, piano orizzontale, ruotino
		b.plate("paint", [Vector2(0, -0.9), Vector2(1.7, 0.55), Vector2(1.75, 1.05), Vector2(0, 0.55)], 0.12, pc,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 2.2, 5.85)))
		b.plate("faction", [Vector2(1.1, 0.05), Vector2(1.7, 0.55), Vector2(1.75, 1.05), Vector2(1.15, 0.84)], 0.14, b.fac,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 2.2, 5.85)))
		b.plate("paint", [Vector2(-1.5, -0.2), Vector2(1.5, -0.2), Vector2(1.3, 0.35), Vector2(-1.3, 0.35)], 0.08, pc, Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 6.3)))
		b.plate("paint", [Vector2(-0.25, -0.6), Vector2(0.25, -0.6), Vector2(1.05, 0.25), Vector2(1.05, 0.7)], 0.1, pc * 0.9,
			Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0, 2.05, 5.9)))
		b.cyl_ab("metal", Vector3(0, 1.1, 5.8), Vector3(0, 0.25, 5.8), 0.05, 0.05, 6, GUNMETAL)
		b.cyl("rubber", 0.2, 0.2, 0.12, 8, Transform3D(_rx(), Vector3(0, 0.2, 5.8)), DARK)
		# albero rotore
		b.cyl_ab("metal", Vector3(0, 3.05, -0.3), Vector3(0, 3.48, -0.3), 0.16, 0.12, 10, GUNMETAL)
		)))
	var gun := _mi("Turret", _cached("heli_gun", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.box("metal", Vector3(0.4, 0.28, 0.42), Vector3.ZERO, GUNMETAL, 0.06)
		b.cyl_ab("metal", Vector3(0, 0.12, 0), Vector3(0, 0.38, 0), 0.08, 0.08, 6, GUNMETAL)
		), Vector3(0, 0.82, -4.7))
	root.add_child(gun)
	var gb := _mi("Barrel", _cached("heli_gunb", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl_ab("metal", Vector3(0, 0, 0), Vector3(0, 0, -1.55), 0.05, 0.045, 6, DARK)
		b.box("metal", Vector3(0.22, 0.2, 0.55), Vector3(0, 0, -0.2), GUNMETAL, 0.03)
		b.cyl_ab("metal", Vector3(0, 0, -1.3), Vector3(0, 0, -1.5), 0.075, 0.075, 6, DARK)
		), Vector3(0, -0.04, -0.15))
	gun.add_child(gb)
	gb.add_child(_marker("Muzzle", Vector3(0, 0, -1.6)))
	var rotor := _mi("Rotor", _cached("heli_rotor", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.32, 0.28, 0.24, 10, Transform3D(Basis.IDENTITY, Vector3.ZERO), GUNMETAL)
		# radar a cupola in testa d'albero
		b.cyl("paint", 0.2, 0.2, 0.5, 8, Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0)), GUNMETAL)
		b.loft("paint", [[-0.62, 0.95, 0.02, 0.02], [-0.5, 0.95, 0.42, 0.22, 3.0], [0.0, 0.95, 0.55, 0.3, 3.0], [0.5, 0.95, 0.42, 0.22, 3.0], [0.62, 0.95, 0.02, 0.02]], 10, pc * 0.9)
		for i in 4:
			var r := Basis(Vector3.UP, PI * 0.5 * i + 0.3)
			b.box("paint", Vector3(0.52, 0.05, 6.0), r * Vector3(0, 0.02, -3.2), Color(0.14, 0.15, 0.14), 0.0, r * Basis(Vector3.FORWARD, 0.06))
			b.box("faction", Vector3(0.53, 0.06, 0.3), r * Vector3(0, 0.02, -6.05), b.fac, 0.0, r)
		), Vector3(0, 3.5, -0.3))
	root.add_child(rotor)
	var tr := _mi("TailRotor", _cached("heli_tail", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.cyl("metal", 0.1, 0.1, 0.2, 8, Transform3D(_rx(), Vector3.ZERO), GUNMETAL)
		# rotore di coda a X
		b.box("paint", Vector3(0.04, 2.3, 0.22), Vector3(0.06, 0, 0), Color(0.14, 0.15, 0.14), 0.0, Basis(Vector3.RIGHT, 0.95))
		b.box("paint", Vector3(0.04, 2.3, 0.22), Vector3(0.1, 0, 0), Color(0.14, 0.15, 0.14), 0.0, Basis(Vector3.RIGHT, -0.95))
		), Vector3(-0.2, 3.15, 6.75))
	root.add_child(tr)
	root.set_meta("length", 14.0)
	root.set_meta("height", 4.1)
	root.set_meta("air", true)

# ============================================================== caccia-bombardiere
static func _jet(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(AIR_GRAY, c, tint * 0.9)
	var sg := 16 if lod == 0 else (10 if lod == 1 else 6)
	root.add_child(_mi("Body", _cached("jet_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-9.6, 1.05, 0.02, 0.02], [-9.1, 1.05, 0.26, 0.28], [-7.6, 1.1, 0.5, 0.52], [-5.6, 1.18, 0.66, 0.68],
			[-4.0, 1.15, 0.85, 0.72, 2.4], [-2.0, 1.02, 1.55, 0.7, 3.2], [2.0, 1.0, 1.7, 0.66, 3.4], [6.5, 1.02, 1.5, 0.6, 3.2],
			[8.3, 1.02, 1.3, 0.55, 2.8], [8.7, 1.02, 1.2, 0.5, 2.6]], sg, pc)
		b.cyl_ab("rubber", Vector3(0, 1.05, -9.62), Vector3(0, 1.05, -9.55), 0.03, 0.03, 4, DARK)
		# tettuccio
		b.sphere("glass", Vector3(0, 1.62, -5.2), Vector3(0.48, 0.55, 1.75), sg, 6, GLASS, true)
		b.loft("paint", [[-3.6, 1.6, 0.4, 0.38], [-1.5, 1.45, 0.42, 0.32], [1.5, 1.4, 0.3, 0.2]], sg, pc * 0.97, false)
		for s in [-1.0, 1.0]:
			# prese d'aria
			b.prism_x("paint", [Vector2(-4.2, 0.35), Vector2(-4.2, 1.15), Vector2(-1.0, 1.25), Vector2(-1.0, 0.25)], s * 0.95, s * 1.75, pc * 0.92)
			b.box("rubber", Vector3(0.7, 0.72, 0.04), Vector3(s * 1.35, 0.75, -4.22), Color(0.02, 0.02, 0.02))
			# ugelli
			b.cyl_ab("metal", Vector3(s * 0.62, 1.0, 8.5), Vector3(s * 0.62, 1.0, 9.4), 0.55, 0.47, sg, Color(0.24, 0.23, 0.22))
			b.cyl_ab("rubber", Vector3(s * 0.62, 1.0, 9.38), Vector3(s * 0.62, 1.0, 9.41), 0.4, 0.4, sg, Color(0.05, 0.04, 0.04))
			# ali a freccia
			var wing := [Vector2(1.4, -3.4), Vector2(6.6, 2.6), Vector2(6.6, 3.7), Vector2(1.4, 4.8)]
			b.plate("paint", wing, 0.18, pc, Transform3D(Basis.IDENTITY, Vector3(0, 1.08, 0)).scaled_local(Vector3(s, 1, 1)))
			# coccarda della fazione sull'ala
			b.cyl("faction", 0.75, 0.75, 0.02, 20, Transform3D(Basis.IDENTITY, Vector3(s * 4.6, 1.19, 2.4)), b.fac, true, false)
			b.cyl("paint", 0.32, 0.32, 0.022, 16, Transform3D(Basis.IDENTITY, Vector3(s * 4.6, 1.195, 2.4)), Color(0.9, 0.9, 0.88), true, false)
			# piani di coda
			b.plate("paint", [Vector2(1.2, 6.4), Vector2(3.9, 8.5), Vector2(3.9, 9.3), Vector2(1.2, 9.4)], 0.12, pc,
				Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)).scaled_local(Vector3(s, 1, 1)))
			# derive gemelle inclinate
			var fin := Transform3D(Basis(Vector3.BACK, s * -0.26) * Basis(Vector3.BACK, PI * 0.5), Vector3(s * 1.2, 1.5, 0))
			b.plate("paint", [Vector2(0, 4.6), Vector2(3.2, 7.4), Vector2(3.2, 8.4), Vector2(0, 8.7)], 0.12, pc, fin)
			b.plate("faction", [Vector2(2.0, 6.33), Vector2(3.2, 7.4), Vector2(3.2, 8.4), Vector2(2.0, 8.52)], 0.14, b.fac, fin)
			# armamento: bomba e missile
			if lod < 2:
				b.box("paint", Vector3(0.12, 0.3, 1.0), Vector3(s * 3.2, 0.85, 1.2), pc * 0.8)
				var ob := b.t
				b.t = b.t * Transform3D(Basis.IDENTITY, Vector3(s * 3.2, 0, 0))
				b.loft("paint", [[0.0, 0.48, 0.02, 0.02], [0.3, 0.48, 0.22, 0.22], [2.0, 0.48, 0.22, 0.22], [2.5, 0.48, 0.08, 0.08]], 10, Color(0.3, 0.32, 0.28))
				b.t = ob
				b.cyl_ab("paint", Vector3(s * 6.6, 1.05, 1.6), Vector3(s * 6.6, 1.05, 4.2), 0.08, 0.08, 6, Color(0.85, 0.85, 0.82))
				b.cyl_ab("paint", Vector3(s * 6.6, 1.05, 1.6), Vector3(s * 6.6, 1.05, 1.3), 0.08, 0.0, 6, Color(0.85, 0.85, 0.82))
		)))
	root.add_child(_marker("Muzzle", Vector3(-0.9, 1.4, -6.2)))
	root.set_meta("length", 19.0)
	root.set_meta("height", 4.4)
	root.set_meta("air", true)

# ============================================================== drone (UAV MALE)
static func _drone(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(DRONE_GRAY, c, tint * 0.8)
	var sg := 12 if lod == 0 else 8
	root.add_child(_mi("Body", _cached("drone_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.camo = 0.0
		b.loft("paint", [[-3.2, 0.55, 0.05, 0.05], [-2.9, 0.58, 0.3, 0.3], [-2.0, 0.65, 0.4, 0.42], [0.5, 0.62, 0.36, 0.38], [2.6, 0.62, 0.16, 0.16], [3.0, 0.62, 0.1, 0.1]], sg, pc)
		b.sphere("glass", Vector3(0, 0.3, -2.5), Vector3(0.2, 0.2, 0.2), 10, 6, Color(0.05, 0.05, 0.06))
		for s in [-1.0, 1.0]:
			b.plate("paint", [Vector2(0, -0.75), Vector2(5.6, -0.25), Vector2(5.6, 0.18), Vector2(0, 0.25)], 0.08, pc,
				Transform3D(Basis.IDENTITY, Vector3(0, 0.95, -0.4)).scaled_local(Vector3(s, 1, 1)))
			b.plate("faction", [Vector2(4.6, -0.33), Vector2(5.62, -0.25), Vector2(5.62, 0.19), Vector2(4.6, 0.2)], 0.1, b.fac,
				Transform3D(Basis.IDENTITY, Vector3(0, 0.95, -0.4)).scaled_local(Vector3(s, 1, 1)))
			b.plate("paint", [Vector2(0, 2.0), Vector2(1.5, 2.6), Vector2(1.5, 2.95), Vector2(0, 2.95)], 0.06, pc,
				Transform3D(Basis(Vector3.BACK, s * 0.7), Vector3(0, 0.7, 0)).scaled_local(Vector3(s, 1, 1)))
			b.cyl_ab("rubber", Vector3(s * 2.0, 0.85, -0.5), Vector3(s * 2.0, 0.85, -0.3), 0.06, 0.06, 6, DARK)
		b.box("faction", Vector3(0.3, 0.02, 1.4), Vector3(0, 1.01, 0.3), b.fac)
		)))
	var prop := _mi("Prop", _cached("drone_prop", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.sphere("metal", Vector3.ZERO, Vector3(0.1, 0.1, 0.14), 8, 4, GUNMETAL)
		b.box("paint", Vector3(1.5, 0.12, 0.03), Vector3.ZERO, Color(0.12, 0.12, 0.12), 0.0, Basis(Vector3.RIGHT, 0.0))
		), Vector3(0, 0.62, 3.1))
	root.add_child(prop)
	root.add_child(_marker("Muzzle", Vector3(0, 0.3, -2.6)))
	root.set_meta("length", 6.3)
	root.set_meta("height", 1.2)
	root.set_meta("air", true)

# ============================================================== squadra di fanteria
static func _inf(root: Node3D, c: Color, lod: int, burnt: bool, tint: float) -> void:
	var pc := _paint(UNIFORM, c, tint)
	var squad := [
		["aim", Vector3(0.0, 0, -1.4), 0.0],
		["kneel", Vector3(-1.7, 0, -0.2), 0.25],
		["walk", Vector3(1.6, 0, 0.1), -0.15],
		["rpg", Vector3(-0.8, 0, 1.6), 0.1],
		["prone", Vector3(1.0, 0, 1.9), -0.05]]
	root.add_child(_mi("Body", _cached("inf_body", c, lod, burnt, tint, func(b: ModelKit) -> void:
		b.rig = ModelKit.use_shaders and not burnt
		for i in squad.size():
			var s: Array = squad[i]
			var old := b.t
			b.t = b.t * Transform3D(Basis(Vector3.UP, float(s[2])), s[1] as Vector3)
			_soldier(b, String(s[0]), pc, lod, "helmet", Color(0, 0, 0, 0), "paint", Color(0.3, 0.28, 0.22), SQUAD_ROLES[i])
			b.t = old
		)))
	root.add_child(_marker("Muzzle", Vector3(0.05, 1.45, -2.4)))
	root.set_meta("length", 4.5)
	root.set_meta("height", 1.8)
	root.set_meta("air", false)

static func _limb(b: ModelKit, a: Vector3, e: Vector3, r0: float, r1: float, col: Color, sg: int, k: String = "paint") -> void:
	b.cyl_ab(k, a, e, r0, r1, sg, col)

## Ruoli della squadra (in ordine di soldato): capo, mitragliere con bipiede, radiofonista con antenna, anticarro, fuciliere.
const SQUAD_ROLES := ["leader", "mg", "radio", "at", "rifle"]

## Soldato. `hat`: "helmet", "helmet_nvg", "cap", "shemagh", "beanie", "boonie"; `legs`: colore dei pantaloni (alfa 0 = come pc);
## `ck`: materiale degli abiti ("paint" = mimetica, "matte" = tinta unita); `hc`: colore del copricapo morbido;
## `role`: "rifle" | "leader" (binocolo, ottica) | "mg" (mitragliatrice con bipiede e scatola) | "radio" (zaino radio e antenna) | "at" (lanciarazzi).
static func _soldier(b: ModelKit, pose: String, pc: Color, lod: int, hat: String = "helmet", legs: Color = Color(0, 0, 0, 0),
		ck: String = "paint", hc: Color = Color(0.3, 0.28, 0.22), role: String = "rifle") -> void:
	var sg := 6 if lod == 0 else (4 if lod == 1 else 3)
	var lc := pc if legs.a <= 0.0 else legs
	b.camo = 2.0
	if pose == "rpg":
		role = "at"
	elif role == "at":
		pose = "rpg"
	if b.rig:
		# soldato animato (soldier.gdshader): posa a riposo in piedi in mira, le altre pose le fa lo shader
		b.rig_begin()
		pose = "rpg" if pose == "rpg" else "aim"
	var arm_bone := 8 if pose == "rpg" else 7
	var J := {}
	# scheletro di base in piedi (avanti = -Z)
	J = {"hipL": Vector3(-0.1, 0.95, 0), "hipR": Vector3(0.1, 0.95, 0), "kneeL": Vector3(-0.11, 0.52, -0.03), "kneeR": Vector3(0.11, 0.52, -0.03),
		"footL": Vector3(-0.12, 0.07, 0.0), "footR": Vector3(0.12, 0.07, 0.0), "pelvis": Vector3(0, 0.98, 0), "chest": Vector3(0, 1.42, 0),
		"head": Vector3(0, 1.64, -0.02), "shL": Vector3(-0.2, 1.4, 0), "shR": Vector3(0.2, 1.4, 0),
		"elL": Vector3(-0.15, 1.18, -0.3), "elR": Vector3(0.3, 1.18, 0.0), "haL": Vector3(-0.03, 1.36, -0.5), "haR": Vector3(0.13, 1.34, -0.2),
		"gunA": Vector3(0.13, 1.42, 0.05), "gunB": Vector3(0.05, 1.45, -0.95)}
	var tube := false
	match pose:
		"kneel":
			var dy := Vector3(0, -0.42, 0)
			for k in ["pelvis", "chest", "head", "shL", "shR", "elL", "elR", "haL", "haR", "gunA", "gunB"]:
				J[k] = J[k] + dy
			J["hipL"] = Vector3(-0.1, 0.55, 0.0); J["hipR"] = Vector3(0.1, 0.55, 0.0)
			J["kneeL"] = Vector3(-0.13, 0.5, -0.42); J["footL"] = Vector3(-0.13, 0.07, -0.42)
			J["kneeR"] = Vector3(0.13, 0.07, -0.05); J["footR"] = Vector3(0.13, 0.1, 0.42)
			J["elL"] = Vector3(-0.12, 0.72, -0.32)
		"walk":
			J["kneeL"] = Vector3(-0.11, 0.53, -0.2); J["footL"] = Vector3(-0.12, 0.07, -0.3)
			J["kneeR"] = Vector3(0.11, 0.5, 0.12); J["footR"] = Vector3(0.12, 0.12, 0.35)
			J["chest"] = Vector3(0, 1.41, -0.06); J["head"] = Vector3(0, 1.63, -0.1)
			J["elL"] = Vector3(-0.22, 1.12, -0.18); J["haL"] = Vector3(-0.08, 1.25, -0.32)
			J["elR"] = Vector3(0.26, 1.08, 0.0); J["haR"] = Vector3(0.12, 1.02, -0.18)
			J["gunA"] = Vector3(0.2, 0.92, -0.05); J["gunB"] = Vector3(-0.22, 1.42, -0.55)
		"rpg":
			tube = true
			J["footL"] = Vector3(-0.15, 0.07, -0.18); J["kneeL"] = Vector3(-0.13, 0.52, -0.12)
			J["footR"] = Vector3(0.16, 0.07, 0.2)
			J["elL"] = Vector3(-0.12, 1.2, -0.3); J["haL"] = Vector3(0.12, 1.42, -0.35)
			J["elR"] = Vector3(0.3, 1.2, -0.1); J["haR"] = Vector3(0.18, 1.38, -0.12)
		"prone":
			J = {"hipL": Vector3(-0.1, 0.16, 0.25), "hipR": Vector3(0.1, 0.16, 0.25), "kneeL": Vector3(-0.2, 0.1, 0.68), "kneeR": Vector3(0.18, 0.1, 0.7),
				"footL": Vector3(-0.28, 0.1, 1.1), "footR": Vector3(0.26, 0.1, 1.12), "pelvis": Vector3(0, 0.17, 0.22), "chest": Vector3(0, 0.26, -0.3),
				"head": Vector3(0, 0.4, -0.52), "shL": Vector3(-0.2, 0.24, -0.3), "shR": Vector3(0.2, 0.24, -0.3),
				"elL": Vector3(-0.25, 0.08, -0.6), "elR": Vector3(0.24, 0.08, -0.5), "haL": Vector3(-0.06, 0.22, -0.8), "haR": Vector3(0.09, 0.24, -0.55),
				"gunA": Vector3(0.08, 0.3, -0.4), "gunB": Vector3(0.0, 0.26, -1.55)}
	# gambe e stivali
	for sd in ["L", "R"]:
		b.rig_bone = 3 if sd == "L" else 5
		_limb(b, J["hip" + sd], J["knee" + sd], 0.1, 0.077, lc, sg, ck)
		b.rig_bone += 1
		if b.rig:
			b.sphere(ck, J["knee" + sd], Vector3(0.078, 0.078, 0.078), sg, 3, lc)   # ginocchio: niente fessura quando si piega
		_limb(b, J["knee" + sd], J["foot" + sd], 0.074, 0.06, lc, sg, ck)
		if lod == 0:
			# ginocchiera e tasca laterale dei pantaloni
			var kn: Vector3 = J["knee" + sd]
			b.box("matte", Vector3(0.12, 0.11, 0.07), kn + Vector3(0, 0.0, -0.06) * (0.0 if pose == "prone" else 1.0) + Vector3(0, -0.06, 0) * (1.0 if pose == "prone" else 0.0), Color(0.16, 0.16, 0.14), 0.02)
		var f: Vector3 = J["foot" + sd]
		var dirf: Vector3 = (f - (J["knee" + sd] as Vector3)).normalized()
		var fwd := Vector3(0, 0, -1) if pose != "prone" else Vector3(0, -1, 0)
		b.box("rubber", Vector3(0.11, 0.1, 0.27), f + dirf * 0.02 + fwd * 0.06 - Vector3(0, 0.02, 0), Color(0.12, 0.1, 0.08), 0.02,
			Basis(Vector3.RIGHT, PI * 0.5) if pose == "prone" else Basis.IDENTITY)
	# busto con giubbotto, zaino
	b.rig_bone = 1
	var pel: Vector3 = J["pelvis"]
	var ch: Vector3 = J["chest"]
	var spine := ch - pel
	var up := spine.normalized()
	var side: Vector3 = ((J["shR"] as Vector3) - (J["shL"] as Vector3)).normalized()
	var fw := up.cross(side).normalized()   # verso -Z per una figura in piedi
	var bs := Basis(side, up, -fw)
	b.box(ck, Vector3(0.34, spine.length() + 0.1, 0.2), pel + spine * 0.5, pc, 0.05, bs)
	b.box("matte", Vector3(0.37, spine.length() * 0.62, 0.25), pel + spine * 0.62, pc * 0.75, 0.04, bs)
	if lod == 0:
		b.box("matte", Vector3(0.3, 0.1, 0.06), pel + spine * 0.45 + fw * 0.14, pc * 0.6, 0.02, bs)
		# tasche portacaricatori sulla piastra e spallacci
		for i in 3:
			b.box("matte", Vector3(0.085, 0.11, 0.06), pel + spine * 0.7 + fw * 0.15 + side * (-0.1 + i * 0.1), pc * 0.68, 0.015, bs)
		for sx in [-1.0, 1.0]:
			b.box("matte", Vector3(0.07, 0.04, 0.26), ch + side * (sx * 0.13) + up * 0.02, pc * 0.7, 0.01, bs)
	var back := -fw
	if role == "radio":
		# zaino radio: scatola grande, maniglie, antenna a frusta piegata all'indietro
		b.box("matte", Vector3(0.32, spine.length() * 0.85, 0.22), pel + spine * 0.62 + back * 0.22, Color(0.2, 0.22, 0.18), 0.03, bs)
		b.box("metal", Vector3(0.26, 0.05, 0.03), pel + spine * 0.62 + back * 0.34 + up * (spine.length() * 0.3), DARK, 0.0, bs)
		b.box("metal", Vector3(0.26, 0.05, 0.03), pel + spine * 0.62 + back * 0.34 - up * (spine.length() * 0.3), DARK, 0.0, bs)
		var ab: Vector3 = pel + spine * 0.62 + back * 0.26 + side * 0.11 + up * (spine.length() * 0.45)
		b.cyl_ab("metal", ab, ab + up * 0.95 + back * 0.3, 0.012, 0.005, 4, DARK)
		b.box("faction", Vector3(0.1, 0.1, 0.03), pel + spine * 0.62 + back * 0.34, b.fac, 0.0, bs)
	else:
		b.box("matte", Vector3(0.3, spine.length() * 0.7, 0.18), pel + spine * 0.6 + back * 0.2, pc * 0.82, 0.05, bs)
		b.box("faction", Vector3(0.22, 0.04, 0.12), pel + spine * 0.6 + back * 0.2 + up * (spine.length() * 0.35 + 0.02), b.fac, 0.0, bs)
	if role == "at" and lod < 2:
		# razzo di scorta nella custodia sullo zaino
		b.cyl_ab("matte", pel + spine * 0.3 + back * 0.33 - side * 0.1, pel + spine * 1.05 + back * 0.33 - side * 0.1, 0.045, 0.045, 6, Color(0.25, 0.27, 0.2))
	if role == "leader" and lod < 2:
		# binocolo sul petto
		b.box("metal", Vector3(0.12, 0.05, 0.06), pel + spine * 0.8 + fw * 0.16, DARK, 0.01, bs)
	# collo
	b.box("matte", Vector3(0.09, 0.1, 0.09), pel + spine * 1.02, SKIN * 0.95, 0.02, bs)
	# testa, elmetto con banda della fazione
	var hd: Vector3 = J["head"]
	b.rig_bone = 2
	b.sphere("matte", hd, Vector3(0.095, 0.11, 0.1), sg + 2, 4, SKIN)
	match hat:
		"cap":
			b.sphere("matte", hd + up * 0.04, Vector3(0.105, 0.075, 0.11), sg + 2, 3, hc, true, bs)
			b.box("matte", Vector3(0.15, 0.015, 0.1), hd + up * 0.05 + fw * 0.12, hc * 0.9, 0.0, bs)
		"shemagh":
			b.sphere("matte", hd + up * 0.01, Vector3(0.118, 0.125, 0.118), sg + 2, 4, hc, false, bs)
			b.box("matte", Vector3(0.2, 0.2, 0.05), hd - up * 0.12 + back * 0.08, hc * 0.9, 0.03, bs)
		"beanie":
			b.sphere("matte", hd + up * 0.035, Vector3(0.108, 0.1, 0.11), sg + 2, 3, hc, true, bs)
		"boonie":
			b.sphere(ck, hd + up * 0.035, Vector3(0.11, 0.1, 0.115), sg + 2, 3, pc * 0.9, true, bs)
			b.cyl(ck, 0.19, 0.17, 0.02, sg + 4, Transform3D(bs, hd + up * 0.04), pc * 0.85)
		_:
			b.sphere("paint", hd + up * 0.03, Vector3(0.14, 0.13, 0.15), sg + 2, 3, pc * 0.9, true, bs)
			b.cyl("faction", 0.142, 0.142, 0.022, sg + 2, Transform3D(bs, hd + up * 0.045), b.fac, false)
			if hat == "helmet_nvg":
				b.box("metal", Vector3(0.07, 0.06, 0.05), hd + up * 0.09 + fw * 0.14, DARK, 0.0, bs)
				b.box("metal", Vector3(0.22, 0.03, 0.03), hd + up * 0.06 + fw * 0.02, DARK, 0.0, bs)
				b.box("matte", Vector3(0.1, 0.06, 0.07), hd + up * 0.08 - fw * 0.15, DARK * 1.5, 0.0, bs)
	# braccia, mani, bracciale
	b.rig_bone = arm_bone
	for sd in ["L", "R"]:
		_limb(b, J["sh" + sd], J["el" + sd], 0.068, 0.056, pc, sg, ck)
		_limb(b, J["el" + sd], J["ha" + sd], 0.054, 0.044, pc, sg, ck)
		var sh: Vector3 = J["sh" + sd]
		var el: Vector3 = J["el" + sd]
		b.cyl_ab("faction", sh.lerp(el, 0.35), sh.lerp(el, 0.55), 0.064, 0.06, sg, b.fac, false)
		b.sphere("matte", J["ha" + sd], Vector3(0.045, 0.045, 0.05), 6, 3, SKIN * 0.9)
	# arma
	var ga: Vector3 = J["gunA"]
	var gb: Vector3 = J["gunB"]
	if tube:
		var a2 := Vector3(0.17, 1.55, 0.55)
		var b2 := Vector3(0.17, 1.52, -0.65)
		b.cyl_ab("paint", a2, b2, 0.05, 0.05, 8, Color(0.25, 0.27, 0.2))
		b.cyl_ab("paint", b2, b2 + Vector3(0, 0, -0.12), 0.09, 0.09, 8, Color(0.22, 0.24, 0.18))
		b.cyl_ab("paint", b2 + Vector3(0, 0, -0.12), b2 + Vector3(0, 0, -0.38), 0.09, 0.0, 8, Color(0.22, 0.24, 0.18))
	elif role == "mg":
		# mitragliatrice: canna lunga e pesante con bipiede aperto, scatola di munizioni al posto del caricatore
		var gd := (gb - ga).normalized()
		var gbs := Basis.looking_at(gd, Vector3.UP)
		var L := ga.distance_to(gb) + 0.28
		var gb2 := ga + gd * L
		b.box("metal", Vector3(0.06, 0.12, L * 0.55), ga + gd * L * 0.3, DARK, 0.0, gbs)
		b.cyl_ab("metal", ga + gd * L * 0.55, gb2, 0.02, 0.016, 5, DARK)
		b.box("metal", Vector3(0.05, 0.08, 0.3), ga + gd * L * 0.62 - gbs.y * 0.02, DARK * 1.3, 0.0, gbs)
		b.box("matte", Vector3(0.09, 0.11, 0.14), ga + gd * L * 0.4 - gbs.y * 0.1, Color(0.22, 0.26, 0.2), 0.01, gbs)
		if lod < 2:
			var bp := ga + gd * L * 0.78
			for sx in [-1.0, 1.0]:
				b.cyl_ab("metal", bp, bp - gbs.y * 0.26 + gbs.x * (sx * 0.11) + gd * 0.04, 0.009, 0.009, 4, DARK)
	else:
		var gd := (gb - ga).normalized()
		var gbs := Basis.looking_at(gd, Vector3.UP)
		var L := ga.distance_to(gb)
		b.box("metal", Vector3(0.05, 0.1, L * 0.62), ga + gd * L * 0.32, DARK, 0.0, gbs)
		b.cyl_ab("metal", ga + gd * L * 0.6, gb, 0.014, 0.014, 4, DARK)
		b.box("metal", Vector3(0.035, 0.14, 0.06), ga + gd * L * 0.42 - gbs.y * 0.1, DARK, 0.0, gbs)
		if lod < 2 and role == "leader":
			b.box("metal", Vector3(0.03, 0.05, 0.1), ga + gd * L * 0.45 + gbs.y * 0.07, DARK, 0.0, gbs)
	b.camo = 0.0
	b.rig_bone = 1
