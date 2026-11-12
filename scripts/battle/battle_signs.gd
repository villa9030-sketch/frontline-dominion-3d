class_name BattleSigns
extends Node3D
## NOTTE 3 (agente GRAFICA) — segni 3D dello scontro "senza nascondino". Solo vista: legge la sim, non la tocca.
## Lo crea BattleMarks.setup (nessuna modifica a battle3d): si aggiorna da solo in _process.
##  - contatti «?»: sagoma generica traslucida (telo/ingombro del colore del nemico) dove la sim dà `u.known[hs]` senza
##    `u.spotted[hs]` (Battle3D.is_contact_unit): posizione nota, tipo ignoto. Il «?» 2D resta dell'HUD.
##  - rivelazione: chi spara è identificato per BattleRules.REVEAL_T secondi → lampo e anello tratteggiato che si stringe e
##    si spegne (rosso sui nemici rivelati, ambra sulle proprie unità che il nemico ora vede).
##  - eventi annunciati (`sim.pending`): attacco aereo = cerchio rosso che pulsa sempre più in fretta + fumogeno rosso;
##    rinforzi = frecce che entrano dal bordo nel colore del lato + polvere della colonna in arrivo.
##  - obiettivo minacciato: anello che si riempie (tempo di conquista) nel colore di chi lo sta prendendo.

const MAX_CONTACTS := 96
const MAX_REVEALS := 96

var b                      # Battle3D
var sim
var terrain
var enabled := true
var _c_mm: MultiMesh
var _r_mm: MultiMesh
var _pend := {}            # chiave -> {node, mat, kind, t_fx}
var _objs := {}            # indice obiettivo -> {node, mat}
var _t := 0.0
var _dbg_done := false
var stats := {"contacts": 0, "reveals": 0, "pending": 0, "threats": 0}

const CONTACT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.4);
	// righe di scansione che salgono: è un'ipotesi, non un oggetto vero
	float scan = smoothstep(0.55, 0.9, fract(wp.y * 1.6 - TIME * 0.7));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2 + wp.x * 0.05);
	ALBEDO = mix(COLOR.rgb * 0.75, COLOR.rgb * 1.5 + vec3(0.15), clamp(fres + scan * 0.6, 0.0, 1.0)) * pulse;
	ALPHA = clamp(0.34 + 0.4 * fres + 0.22 * scan, 0.0, 0.9) * COLOR.a;   // due strati (fronte e retro): insieme ~0,55
}
"""
const REVEAL_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float f = COLOR.a;   // 1 = appena rivelata, 0 = sta tornando nascosta
	float ring = smoothstep(0.84, 0.88, d) * (1.0 - smoothstep(0.95, 1.0, d));
	float dash = step(0.45, fract(atan(q.y, q.x) / 6.2832 * 12.0 + TIME * 0.35));
	float flash = smoothstep(0.86, 1.0, f) * pow(max(0.0, 1.0 - d), 1.5);
	float a = ring * dash * (0.25 + 0.75 * f) + flash * 0.85;
	ALBEDO = COLOR.rgb * (1.0 + flash * 1.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
const AIR_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float left = 7.0;
void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float ring = smoothstep(0.86, 0.9, d) * (1.0 - smoothstep(0.96, 1.0, d));
	float pulse = 0.5 + 0.5 * sin(TIME * mix(13.0, 4.0, clamp(left / 7.0, 0.0, 1.0)));
	// onde che si chiudono sul bersaglio e croce di mira
	float sw = fract(d * 2.5 + TIME * 0.9);
	float waves = smoothstep(0.0, 0.12, sw) * (1.0 - smoothstep(0.12, 0.35, sw)) * (1.0 - smoothstep(0.8, 0.9, d));
	float cr = (1.0 - smoothstep(0.012, 0.02, min(abs(q.x), abs(q.y)))) * smoothstep(0.1, 0.16, d) * (1.0 - smoothstep(0.3, 0.34, d));
	float a = ring * (0.55 + 0.45 * pulse) + waves * 0.3 * (0.4 + 0.6 * pulse) + cr * 0.8 + (1.0 - smoothstep(0.0, 0.9, d)) * 0.1 * pulse;
	ALBEDO = col.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * col.a;
}
"""
const REINF_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.3, 0.6, 1.0, 1.0);
void fragment() {
	// frecce a spina che scorrono lungo +V (verso l'interno del campo)
	float x = abs(UV.x - 0.5) * 2.0;
	float v = fract(UV.y * 3.0 - TIME * 0.8 + x * 0.42);
	float band = smoothstep(0.0, 0.05, v) * (1.0 - smoothstep(0.26, 0.32, v)) * (1.0 - smoothstep(0.82, 0.95, x));
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	ALBEDO = col.rgb * 1.15;
	ALPHA = band * ends * col.a * 0.85;
}
"""
const OBJ_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform float prog = 0.0;
void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q) * 2.0;
	float ring = smoothstep(0.84, 0.88, d) * (1.0 - smoothstep(0.96, 1.0, d));
	float ang = atan(q.x, -q.y) / 6.2832 + 0.5;
	float done = step(ang, prog);
	float blink = 0.6 + 0.4 * sin(TIME * 6.0);
	float a = ring * mix(0.22, 0.95 * blink, done);
	ALBEDO = col.rgb * (1.0 + done * 0.4);
	ALPHA = a * col.a;
}
"""

func setup(battle) -> void:
	b = battle
	sim = b.sim
	if "--segni=0" in OS.get_cmdline_user_args():   # confronto / misure
		enabled = false
	terrain = b.terrain
	name = "Signs"
	# sagoma dei contatti
	_c_mm = _mk_mm(_contact_mesh(), CONTACT_SHADER, MAX_CONTACTS, "Contacts", 2)
	# anelli di rivelazione
	var q := PlaneMesh.new()
	q.size = Vector2(2.0, 2.0)
	_r_mm = _mk_mm(q, REVEAL_SHADER, MAX_REVEALS, "Reveals", 3)

func _mk_mm(mesh: Mesh, code: String, n: int, nm: String, prio: int) -> MultiMesh:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = prio
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4000, -200, -4000), Vector3(8000, 800, 8000))
	add_child(mi)
	return mm

## Ingombro generico: un telo teso su "qualcosa" (cupola bassa sfaccettata, allungata): non dice che cosa c'è sotto.
static func _contact_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	var rings := [[1.0, 0.0], [0.9, 0.55], [0.55, 0.95], [0.0, 1.0]]   # [raggio, quota] normalizzati
	var pts: Array = []
	for r in rings.size():
		var row: Array = []
		for i in seg:
			var a := TAU * float(i) / seg + (0.31 if r % 2 == 1 else 0.0)
			var wob := 1.0 + 0.1 * sin(a * 3.0 + r)
			row.append(Vector3(cos(a) * 1.75 * float(rings[r][0]) * wob, 1.9 * float(rings[r][1]), sin(a) * 2.9 * float(rings[r][0]) * wob))
		pts.append(row)
	for r in rings.size() - 1:
		for i in seg:
			var a0: Vector3 = pts[r][i]
			var a1: Vector3 = pts[r][(i + 1) % seg]
			var b0: Vector3 = pts[r + 1][i]
			var b1: Vector3 = pts[r + 1][(i + 1) % seg]
			for tri in [[a0, b0, a1], [a1, b0, b1]]:
				var n := ((tri[2] as Vector3) - (tri[0] as Vector3)).cross((tri[1] as Vector3) - (tri[0] as Vector3))
				if n.length_squared() < 1e-8:
					continue
				n = n.normalized()
				for p in tri:
					st.set_normal(n)
					st.add_vertex(p)
	return st.commit()

## Pezza di suolo (griglia che segue il rilievo) centrata in `c`, semiassi `half`, ruotata di `yaw`: UV 0..1.
func _patch(c: Vector2, half: Vector2, yaw: float, n := 10, lift := 0.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ax := Vector2(cos(yaw), sin(yaw))
	var ay := Vector2(-sin(yaw), cos(yaw))
	var V: Array = []
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / n
			var v := float(j) / n
			var o := ax * ((u - 0.5) * 2.0 * half.x) + ay * ((v - 0.5) * 2.0 * half.y)
			var h: float = terrain.height(c.x + o.x, c.y + o.y)
			if sim.sea:
				h = maxf(h, 0.0)
			V.append([Vector3(o.x, h + lift, o.y), Vector2(u, v)])
	for j in n:
		for i in n:
			var k := j * (n + 1) + i
			for idx in [k, k + 1, k + n + 1, k + 1, k + n + 2, k + n + 1]:
				st.set_uv(V[idx][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(V[idx][0])
	return st.commit()

func _patch_node(c: Vector2, half: Vector2, yaw: float, code: String, col: Color) -> Dictionary:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 2
	mat.set_shader_parameter("col", col)
	var mi := MeshInstance3D.new()
	mi.mesh = _patch(c, half, yaw)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, 0.0, c.y)
	add_child(mi)
	return {"node": mi, "mat": mat}

func _process(dt: float) -> void:
	if b == null or sim == null or not enabled:
		return
	_t += dt
	var live: bool = not sim.done and not bool(b.get("photo"))
	visible = live
	if not live:
		return
	_upd_units()
	_upd_pending(dt)
	_upd_objectives()

func _ground_basis(x: float, z: float, s: float) -> Basis:
	var n: Vector3 = terrain.normal(x, z)
	var t := Vector3.RIGHT.slide(n).normalized()
	return Basis(t, n, t.cross(n)).scaled(Vector3(s, 1.0, s))

func _upd_units() -> void:
	var hs: int = sim.hs
	var nc := 0
	var nr := 0
	var rt: float = BattleRules.REVEAL_T
	for u in sim.units:
		if u.dead:
			continue
		if hs >= 0 and u.side != hs and nc < MAX_CONTACTS and b.is_contact_unit(u):
			var p: Vector3 = b._unit_pos(u)
			var sc := clampf(float(u.r) * BattleTerrain.S * 0.55, 0.95, 1.8)
			var bs := Basis(Vector3.UP, float(u.id) * 1.7).scaled(Vector3(sc, sc * (0.75 if u.type == "inf" else 1.0), sc))
			_c_mm.set_instance_transform(nc, Transform3D(bs, p - Vector3(0, 0.15, 0)))
			var col: Color = b.side_color(u.side)
			_c_mm.set_instance_color(nc, Color(col.r * 0.8 + 0.12, col.g * 0.8 + 0.12, col.b * 0.8 + 0.12, 1.0))
			nc += 1
		var rv: float = u.reveal_t
		if rv > 0.0 and nr < MAX_REVEALS and (hs < 0 or u.side == hs or b.is_visible_unit(u)):
			var f := clampf(rv / rt, 0.0, 1.0)
			var p2: Vector3 = b._unit_pos(u)
			var rad := (float(u.r) * BattleTerrain.S + 1.8) * (1.0 + 0.45 * f * f)
			var own: bool = hs >= 0 and u.side == hs
			var c2 := Color(1.0, 0.72, 0.25) if own else Color(1.0, 0.22, 0.14)
			if hs < 0:
				c2 = (b.side_color(u.side) as Color).lightened(0.25)
			var k := 1.0
			if own:
				f *= 0.6
			if u.air:
				_r_mm.set_instance_transform(nr, Transform3D(Basis.IDENTITY.scaled(Vector3(rad, 1.0, rad)), p2 - Vector3(0, 0.4, 0)))
			else:
				_r_mm.set_instance_transform(nr, Transform3D(_ground_basis(p2.x, p2.z, rad), p2 + Vector3(0, 0.45, 0)))
			_r_mm.set_instance_color(nr, Color(c2.r * k, c2.g * k, c2.b * k, f))
			nr += 1
	if nc > 0 and not _dbg_done and "--segni=1" in OS.get_cmdline_user_args():
		# collaudo: dove sono i contatti (per inquadrarli con --cam=x,z)
		_dbg_done = true
		for i in mini(nc, 6):
			var o := _c_mm.get_instance_transform(i).origin
			print("[segni] contatto a %.0f,%.0f" % [o.x, o.z])
	_c_mm.visible_instance_count = nc
	_r_mm.visible_instance_count = nr
	stats["contacts"] = nc
	stats["reveals"] = nr

func _upd_pending(dt: float) -> void:
	var seen := {}
	var list = sim.get("pending")
	if list != null:
		for e in list:
			var kind := String(e.get("kind", ""))
			if kind != "air" and kind != "reinf":
				continue
			var key := "%s|%d|%d|%d|%d" % [kind, int(e.get("side", 0)), int(e.get("x", 0)), int(e.get("y", 0)), int(float(e.get("t", 0.0)) * 10.0)]
			seen[key] = true
			var w := BattleTerrain.sim_to_world(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
			if not _pend.has(key):
				var d: Dictionary
				if kind == "air":
					var r: float = BattleSim.AIR_R * BattleTerrain.S
					d = _patch_node(w, Vector2(r, r), 0.0, AIR_SHADER, Color(1.0, 0.2, 0.14, 1.0))
				else:
					# le frecce entrano dal bordo verso il centro del campo
					var inw := (-w).normalized() if w.length() > 1.0 else Vector2.RIGHT
					var yaw := atan2(inw.y, inw.x) - PI * 0.5
					var c := w + inw * 26.0
					d = _patch_node(c, Vector2(11.0, 30.0), yaw, REINF_SHADER, (b.side_color(int(e.get("side", 0))) as Color).lightened(0.2))
				d["kind"] = kind
				d["t_fx"] = 0.0
				d["w"] = w
				_pend[key] = d
			var pd: Dictionary = _pend[key]
			var left := maxf(0.0, float(e.get("t", 0.0)) - float(sim.time))
			pd["t_fx"] = float(pd["t_fx"]) - dt
			if kind == "air":
				(pd["mat"] as ShaderMaterial).set_shader_parameter("left", left)
			if float(pd["t_fx"]) <= 0.0 and b.fx != null:
				var gy: float = terrain.height(w.x, w.y)
				if kind == "air":
					# fumogeno rosso di segnalazione sul bersaglio
					pd["t_fx"] = 0.22
					var wd: Vector3 = b.fx.wind
					b.fx._smoke(Vector3(w.x, gy + 0.6, w.y), Vector3(wd.x * 0.5, 3.2, wd.z * 0.5), 3.4, 1.3, 2.0, 0, Color(0.95, 0.16, 0.12, 0.75), 0.5)
				else:
					# polvere della colonna che arriva
					pd["t_fx"] = 0.7
					b.fx.dust(Vector3(w.x + randf_range(-6.0, 6.0), gy + 0.3, w.y + randf_range(-6.0, 6.0)), 1.6)
	for key in _pend.keys():
		if not seen.has(key):
			(_pend[key]["node"] as Node).queue_free()
			_pend.erase(key)
	stats["pending"] = _pend.size()

func _upd_objectives() -> void:
	var objs = sim.get("objectives")
	if objs == null:
		return
	var nt := 0
	for i in (objs as Array).size():
		var o: Dictionary = objs[i]
		var hold = o.get("hold")
		var si := -1
		if hold != null and not bool(o.get("contested", false)):
			for k in 2:
				if float(hold[k]) > 0.0 and int(o.get("owner", -1)) != k:
					si = k
		if si < 0:
			if _objs.has(i):
				(_objs[i]["node"] as Node3D).visible = false
			continue
		if not _objs.has(i):
			var w := BattleTerrain.sim_to_world(float(o["x"]), float(o["y"]))
			var r := float(o.get("r", 200.0)) * BattleTerrain.S
			_objs[i] = _patch_node(w, Vector2(r, r), 0.0, OBJ_SHADER, Color.WHITE)
		var d: Dictionary = _objs[i]
		(d["node"] as Node3D).visible = true
		var m := d["mat"] as ShaderMaterial
		m.set_shader_parameter("col", (b.side_color(si) as Color).lightened(0.15))
		m.set_shader_parameter("prog", clampf(float(hold[si]) / BattleRules.OBJ_HOLD, 0.0, 1.0))
		nt += 1
	stats["threats"] = nt
