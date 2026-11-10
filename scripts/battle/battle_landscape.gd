class_name BattleLandscape
extends RefCounted
## Paesaggio esteso attorno al campo di battaglia (solo vista: la simulazione non ne sa nulla).
## Il campo è un pezzo di una regione più grande: montagne lontane (rilievo in BattleTerrain._far_term), rete di strade
## che parte da quelle del campo, decine di paesi con chiesa, nuvole basse che lasciano libero il campo.
## Campi coltivati e grandi boschi lontani sono dipinti nello shader del terreno (stessa maschera dei boschi: forest_at).

const FOREST_AMT := {"pianura": 0.3, "foresta": 0.6, "montagna": 0.45, "artico": 0.22, "deserto": 0.03, "urbano": 0.2}   # deserto: rare oasi
const FAR_SNOW := {"pianura": 380.0, "foresta": 380.0, "montagna": 560.0, "artico": -999.0, "deserto": 9999.0, "urbano": 380.0}
const ROAD_W := 8.0
const MOSAIC := {"pianura": 1.0, "foresta": 0.55, "montagna": 0.7, "artico": 0.0, "deserto": 0.0, "urbano": 1.0}   # quota di campi coltivati lontani

var T: BattleTerrain
var rng := RandomNumberGenerator.new()
var _noise_img: Image
var villages: Array = []     # [{c: Vector2, n: int}]
var roads: Array = []        # polilinee (Vector2) fuori dal campo

func build(t: BattleTerrain) -> void:
	T = t
	rng.seed = int(t.sim.seed_) * 53 + 17
	var nt: Texture2D = T.terrain_mat.get_shader_parameter("noise_tex")
	if nt != null:
		_noise_img = nt.get_image()
	var m := T.terrain_mat
	m.set_shader_parameter("far_on", 1.0)
	m.set_shader_parameter("far_snow", float(FAR_SNOW.get(T.tkey, 360.0)))
	m.set_shader_parameter("forest_amt", float(FOREST_AMT.get(T.tkey, 0.25)))
	m.set_shader_parameter("mosaic_on", MOSAIC.get(T.tkey, 1.0))
	m.set_shader_parameter("cloud_k", 1.0)
	var wl := []
	for w in T.woods:
		if wl.size() >= 64:
			break
		var c: Vector2 = w["c"]
		wl.append(Vector4(c.x, c.y, float(w["r"]) * 1.15, 0.0))
	m.set_shader_parameter("woods", wl)
	m.set_shader_parameter("wood_n", wl.size())
	_villages()
	_roads()
	_build_road_mesh()
	_build_villages()
	if T.tkey == "urbano":
		_suburbs()
	_build_lakes()
	_build_clouds()
	T._flush_landmarks()

# ---------------------------------------------------------------------------- servizi
## Stessa formula dello shader (forest_mask): 0 aperto .. 1 bosco (calcolata da BattleTerrain, che la usa anche per gli alberi 3D).
func forest_at(p: Vector2) -> float:
	return T.forest_at(p)

func _nz(uv: Vector2) -> float:
	var w := _noise_img.get_width()
	var h := _noise_img.get_height()
	var x := posmod(int(floor(uv.x * w)), w)
	var y := posmod(int(floor(uv.y * h)), h)
	return _noise_img.get_pixel(x, y).r

func far_d(p: Vector2) -> float:
	var dx := maxf(0.0, absf(p.x) - T.FIELD_HX)
	var dz := maxf(0.0, absf(p.y) - T.FIELD_HZ)
	return sqrt(dx * dx + dz * dz)

func _slope_ok(p: Vector2, lim := 0.94) -> bool:
	return T.normal(p.x, p.y).y > lim

func _land_ok(p: Vector2) -> bool:
	if absf(p.x) > T.OUTER * 0.85 or absf(p.y) > T.OUTER * 0.68:
		return false
	if T.sim.sea and (p.x < T.coast_x(p.y) + 120.0 or T.height(p.x, p.y) < 2.0):
		return false
	if T.in_far_lake(p, 30.0):
		return false
	return T.height(p.x, p.y) < float(FAR_SNOW.get(T.tkey, 360.0)) * 0.6 or T.tkey == "artico"

# ---------------------------------------------------------------------------- paesi
func _villages() -> void:
	var want: int = {"pianura": 34, "foresta": 22, "montagna": 18, "artico": 10, "deserto": 12, "urbano": 26}.get(T.tkey, 20)
	var tries := 0
	while villages.size() < want and tries < want * 40:
		tries += 1
		var a := rng.randf() * TAU
		var r := lerpf(650.0, T.OUTER * 0.72, pow(rng.randf(), 0.8))
		var p := Vector2(cos(a) * r, sin(a) * r * 0.85)
		if far_d(p) < 520.0 or not _land_ok(p) or not _slope_ok(p, 0.97) or forest_at(p) > 0.2:
			continue
		var close := false
		for v in villages:
			if (v["c"] as Vector2).distance_to(p) < 900.0:
				close = true
				break
		if close:
			continue
		var big := rng.randf() < 0.2
		villages.append({"c": p, "n": (90 + rng.randi() % 70) if big else (14 + rng.randi() % 22), "big": big})

func _build_villages() -> void:
	var trees := []
	for v in villages:
		var c: Vector2 = v["c"]
		var n: int = v["n"]
		var big: bool = v["big"]
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		# direzione della strada più vicina, se c'è: le case si allineano
		var best := 1e9
		for rd in roads:
			for i in rd.size() - 1:
				var a: Vector2 = rd[i]
				var b: Vector2 = rd[i + 1]
				var d := Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c)
				if d < best:
					best = d
					dir = (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var yaw := atan2(dir.x, dir.y)
		# chiesa al centro (piazza), luci della piazza e dei lampioni lungo la via principale
		T._lm_add("church", _g(c), yaw, Vector3.ONE * (1.25 if big else 1.0), Color(1, 1, 1))
		T.add_glow(c, 34.0 if big else 22.0, 1.3, Color(1.0, 0.85, 0.6))
		var placed := 0
		var spread := 75.0 if not big else 190.0
		var nl := int(spread * 2.0 / 26.0)
		for k in nl:
			var lp := c + dir * (-spread + 26.0 * k + 8.0) + side * (6.0 if k % 2 == 0 else -6.0)
			if _land_ok(lp):
				T.add_glow(lp, 14.0, 0.9, Color(1.0, 0.82, 0.55))
		for k in n * 3:
			if placed >= n:
				break
			var along := rng.randf_range(-1.0, 1.0) * spread * (1.4 if not big else 1.0)
			var off := rng.randf_range(14.0, spread * (0.55 if not big else 1.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			if big:
				# griglia di isolati
				along = roundf(along / 22.0) * 22.0 + rng.randf_range(-3.0, 3.0)
				off = roundf(off / 20.0) * 20.0 + rng.randf_range(-3.0, 3.0)
			var p := c + dir * along + side * off
			if p.distance_to(c) < 13.0 or not _slope_ok(p, 0.95) or not _land_ok(p):
				continue
			var s := rng.randf_range(0.75, 1.15)
			var tint := Color(rng.randf_range(0.85, 1.12), rng.randf_range(0.85, 1.08), rng.randf_range(0.8, 1.05))
			T._lm_add("fhouse", _g(p), yaw + (0.0 if rng.randf() < 0.7 else PI * 0.5) + rng.randf_range(-0.12, 0.12), Vector3(s, s * rng.randf_range(0.85, 1.25), s), tint)
			if rng.randf() < 0.6:
				T.add_glow(p, 9.0, 0.6, Color(1.0, 0.75, 0.45))
			placed += 1
			if rng.randf() < 0.35:
				var tp := p + side * rng.randf_range(-12.0, 12.0) + dir * rng.randf_range(-10.0, 10.0)
				trees.append([_g(tp, 0.2), rng.randf_range(0.6, 1.0), rng.randf() * TAU, T._tint()])
		# orti e frutteti attorno al paese: filari di alberelli bassi su 2-4 appezzamenti ai margini
		if T.tkey != "artico" and T.tkey != "deserto":
			for o in 2 + rng.randi() % 3:
				var oc := c + Vector2.RIGHT.rotated(rng.randf() * TAU) * (spread * rng.randf_range(1.15, 1.6))
				if not _land_ok(oc) or not _slope_ok(oc, 0.95) or forest_at(oc) > 0.3:
					continue
				var oy := rng.randf() * TAU
				var od := Vector2.RIGHT.rotated(oy)
				var os := Vector2(-od.y, od.x)
				var rows := 4 + rng.randi() % 4
				var cols := 6 + rng.randi() % 6
				for r in rows:
					for q in cols:
						var tp := oc + od * ((q - cols * 0.5) * 6.0) + os * ((r - rows * 0.5) * 7.0)
						orchard.append([_g(tp, 0.15), rng.randf_range(0.3, 0.42), oy, T._tint()])
	if not trees.is_empty():
		T.set_tree_range(T._add_instances("broadleaf", trees, false), 3200.0)
	if not orchard.is_empty():
		T.set_tree_range(T._add_instances("broadleaf", orchard, false), 2600.0)

var orchard := []

## Periferie della città oltre la griglia degli isolati: case basse su una maglia allentata, sempre più rade allontanandosi.
func _suburbs() -> void:
	var G := T.city_grid()
	var px: float = G["bw"] + G["st"]
	var pz: float = G["bh"] + G["st"]
	var lim := T.FIELD_HX + 500.0   # fine della griglia di isolati (BattleTerrain._build_city)
	var reach := 1500.0
	var gx0: float = G["gx0"]
	var gz0: float = G["gz0"]
	for i in range(int(floor((-lim - reach - gx0) / px)), int(ceil((lim + reach - gx0) / px)) + 1):
		for j in range(int(floor((-lim * 0.8 - reach - gz0) / pz)), int(ceil((lim * 0.8 + reach - gz0) / pz)) + 1):
			var x0: float = gx0 + i * px
			var z0: float = gz0 + j * pz
			var bw: float = G["bw"]
			var bh: float = G["bh"]
			var cx: float = x0 + bw * 0.5
			var cz: float = z0 + bh * 0.5
			if absf(cx) < lim and absf(cz) < lim * 0.8:
				continue
			var d := maxf(absf(cx) - lim, absf(cz) - lim * 0.8)
			var dens := 1.0 - smoothstep(0.0, reach, d)
			dens *= 0.4 + 0.6 * _nz(Vector2(cx, cz) / 900.0 + Vector2(0.3, 0.6))
			if rng.randf() > dens * 1.3:
				continue
			var n := int(dens * 9.0 * rng.randf_range(0.6, 1.3)) + 1
			for k in n:
				# lungo i quattro lati dell'isolato (le vie), fronte verso la via
				var sd := rng.randi() % 4
				var t := rng.randf_range(0.08, 0.92)
				var p: Vector2
				var yaw: float
				match sd:
					0: p = Vector2(x0 + bw * t, z0 + 7.0); yaw = PI
					1: p = Vector2(x0 + bw * t, z0 + bh - 7.0); yaw = 0.0
					2: p = Vector2(x0 + 7.0, z0 + bh * t); yaw = PI * 0.5
					_: p = Vector2(x0 + bw - 7.0, z0 + bh * t); yaw = -PI * 0.5
				if not _land_ok(p) or not _slope_ok(p, 0.95) or forest_at(p) > 0.5:
					continue
				var s := rng.randf_range(0.8, 1.2)
				var tint := Color(rng.randf_range(0.8, 1.05), rng.randf_range(0.8, 1.02), rng.randf_range(0.78, 1.0))
				T._lm_add("fhouse", _g(p), yaw + rng.randf_range(-0.06, 0.06), Vector3(s, s * rng.randf_range(0.9, 1.3), s), tint)
				if rng.randf() < 0.5:
					T.add_glow(p, 9.0, 0.6, Color(1.0, 0.78, 0.5))
			if rng.randf() < 0.35 * dens:
				T.add_glow(Vector2(cx, cz), 20.0, 0.9, Color(1.0, 0.85, 0.6))

## Specchi d'acqua dei laghi lontani (le conche sono già nel rilievo): disco d'acqua con lo shader del fiume.
func _build_lakes() -> void:
	if T.far_lakes.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for L in T.far_lakes:
		var c := Vector3(L[0], float(L[3]) - 1.0, L[1])
		var R := float(L[2]) * 1.02
		var n := 28
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var r0 := R * (0.92 + 0.08 * _nz(Vector2(cos(a0), sin(a0)) * 0.21 + Vector2(L[0], L[1]) * 0.001))
			var r1 := R * (0.92 + 0.08 * _nz(Vector2(cos(a1), sin(a1)) * 0.21 + Vector2(L[0], L[1]) * 0.001))
			for v in [c, c + Vector3(cos(a1) * r1, 0, sin(a1) * r1), c + Vector3(cos(a0) * r0, 0, sin(a0) * r0)]:
				st.set_uv(Vector2(v.x, v.z) * 0.02)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mesh := st.commit()
	var sh := Shader.new()
	sh.code = T.RIVER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var river: Node = T.get_node_or_null("River")
	if river != null and river is MeshInstance3D and (river as MeshInstance3D).material_override != null:
		m = (river as MeshInstance3D).material_override
	else:
		var nz := FastNoiseLite.new()
		nz.seed = 3
		nz.frequency = 0.05
		var img := nz.get_seamless_image(256, 256)
		img.bump_map_to_normal_map(2.5)
		img.generate_mipmaps()
		m.set_shader_parameter("nrm", ImageTexture.create_from_image(img))
	var mi := MeshInstance3D.new()
	mi.name = "FarLakes"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	T.add_child(mi)

func _g(p: Vector2, sink := 0.3) -> Vector3:
	return Vector3(p.x, T.height(p.x, p.y) - sink, p.y)

# ---------------------------------------------------------------------------- strade
## Rete stradale: prolunga le strade del campo fino all'orizzonte e collega ogni paese al nodo più vicino già collegato.
func _roads() -> void:
	var nodes: Array = []   # punti già sulla rete
	for rd in T.outer_roads:
		var pts: Array = rd
		if pts.size() < 2:
			continue
		# parte esterna già esistente (oltre la maschera delle strade del campo non era disegnata)
		var outer_part := []
		for q in pts:
			outer_part.append(q)
		roads.append(outer_part)
		for end in [[pts[0], pts[1]], [pts[pts.size() - 1], pts[pts.size() - 2]]]:
			var p: Vector2 = end[0]
			var d: Vector2 = (end[0] - end[1]).normalized()
			var path := [p]
			for i in 160:
				d = _steer(p, d)
				p += d * 45.0
				path.append(p)
				if absf(p.x) > T.OUTER * 0.9 or absf(p.y) > T.OUTER * 0.72 or (T.sim.sea and p.x < T.coast_x(p.y) + 60.0):
					break
			roads.append(path)
			for q in path:
				nodes.append(q)
	if nodes.is_empty():
		nodes.append(Vector2(T.FIELD_HX + 300.0, 0.0))
	# paesi in ordine di distanza dal campo: ognuno si collega al nodo più vicino
	var order := villages.duplicate()
	order.sort_custom(func(a, b): return far_d(a["c"]) < far_d(b["c"]))
	for v in order:
		var c: Vector2 = v["c"]
		var best: Vector2 = nodes[0]
		var bd := 1e12
		for q in nodes:
			var dd := (q as Vector2).distance_squared_to(c)
			if dd < bd:
				bd = dd
				best = q
		var path := [best]
		var p: Vector2 = best
		var steps := int(sqrt(bd) / 45.0) + 1
		for i in steps:
			var to := (c - p)
			if to.length() < 45.0:
				break
			var d := _steer(p, to.normalized(), 0.45)
			d = (d + to.normalized() * 1.2).normalized()
			p += d * 45.0
			path.append(p)
		path.append(c)
		roads.append(path)
		for q in path:
			nodes.append(q)
		# un ramo che prosegue oltre il paese
		if rng.randf() < 0.6:
			var d2 := (c - best).normalized().rotated(rng.randf_range(-0.6, 0.6))
			var q2 := c
			var br := [c]
			for i in 18 + rng.randi() % 25:
				d2 = _steer(q2, d2)
				q2 += d2 * 45.0
				if not _land_ok(q2):
					break
				br.append(q2)
			if br.size() > 3:
				roads.append(br)
				for q in br:
					nodes.append(q)

## Direzione successiva: tra cinque varianti sceglie quella con meno pendenza (le strade seguono valli e pianure).
func _steer(p: Vector2, d: Vector2, spread := 0.35) -> Vector2:
	var best := d
	var bs := 1e9
	for k in 5:
		var dd := d.rotated((k - 2) * spread * 0.5 + rng.randf_range(-0.08, 0.08))
		var q := p + dd * 45.0
		var s := absf(T.height(q.x, q.y) - T.height(p.x, p.y)) + forest_at(q) * 6.0
		if s < bs:
			bs = s
			best = dd
	return best

func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.74, 0.7, 0.6)
	if T.tkey == "artico":
		col = Color(0.62, 0.6, 0.58)
	elif T.tkey == "deserto":
		col = Color(0.78, 0.7, 0.58)
	var mask := Rect2(-T.MASK_HX + 30.0, -T.MASK_HZ + 30.0, T.MASK_HX * 2.0 - 60.0, T.MASK_HZ * 2.0 - 60.0)
	for rd in roads:
		var pts: Array = rd
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if mask.has_point(a) and mask.has_point(b):
				continue   # dentro la maschera la strada è già dipinta dallo shader del terreno
			if T.sim.sea and (T.height(a.x, a.y) < 0.8 or T.height(b.x, b.y) < 0.8):
				continue
			var L := a.distance_to(b)
			var n := maxi(1, int(L / 15.0))
			var dir := (b - a) / maxf(L, 0.001)
			var nrm := Vector2(-dir.y, dir.x) * ROAD_W * 0.5
			for k in n:
				var p0 := a.lerp(b, float(k) / n)
				var p1 := a.lerp(b, float(k + 1) / n)
				var v := [p0 + nrm, p0 - nrm, p1 - nrm, p1 + nrm]
				var y := []
				for q in v:
					y.append(T.height(q.x, q.y) + 0.35)
				var c := col * rng.randf_range(0.94, 1.04)
				for idx in [0, 1, 2, 0, 2, 3]:
					var q: Vector2 = v[idx]
					st.set_color(c)
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(q.x, y[idx], q.y))
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "FarRoads"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	T.add_child(mi)

# ---------------------------------------------------------------------------- nuvole
const CLOUD_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 field_half = vec2(600.0, 340.0);
uniform vec3 lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade : source_color = vec3(0.62, 0.66, 0.72);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	// stessa forma delle ombre nello shader del terreno
	float cn = texture(noise_tex, p / 1500.0 + vec2(TIME * 0.0016, TIME * 0.0007)).r * 0.7 + texture(noise_tex, p / 520.0 + vec2(TIME * 0.0021, 0.3)).r * 0.3;
	float fine = texture(noise_tex, p / 120.0 + vec2(TIME * 0.004, 0.0)).r;
	vec2 o = max(abs(p) - field_half, vec2(0.0));
	float fd = length(o);
	float a = smoothstep(0.56, 0.72, cn + (fine - 0.5) * 0.12) * smoothstep(350.0, 1100.0, fd);
	// lontano dalla telecamera le nuvole sfumano nella foschia; vicinissime non coprono la vista
	float dc = length(wp - CAMERA_POSITION_WORLD);
	a *= smoothstep(120.0, 600.0, dc) * (1.0 - smoothstep(7000.0, 11000.0, dc));
	vec3 c = mix(shade, lit, smoothstep(0.5, 0.85, cn + fine * 0.2));
	ALBEDO = c;
	ALPHA = a * 0.92;
}
"""

func _build_clouds() -> void:
	if T.tkey == "deserto":
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(T.OUTER * 2.2, T.OUTER * 2.0)
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", T.terrain_mat.get_shader_parameter("noise_tex"))
	m.set_shader_parameter("field_half", Vector2(T.FIELD_HX, T.FIELD_HZ))
	var mi := MeshInstance3D.new()
	mi.name = "Clouds"
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, 620.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	T.add_child(mi)
