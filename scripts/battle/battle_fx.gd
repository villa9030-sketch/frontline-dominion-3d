class_name BattleFx
extends Node3D
## Effetti della battaglia: particelle CPU su MultiMesh (fuoco additivo + fumo/polvere sfumati, particelle morbide),
## traccianti/razzi su ImmediateMesh orientata alla camera, lampi di luce in pool. Nessun nodo creato per colpo.

const ST := 14      # px,py,pz, vx,vy,vz, life,max, size,grow, kind, seed, drag, grav
const GLOW_N := 1100
const SMOKE_N := 1700

var camera: Camera3D
var _g := PackedFloat32Array()
var _gc := PackedColorArray()
var _gn := 0
var _s := PackedFloat32Array()
var _sc := PackedColorArray()
var _sn := 0
var _gbuf := PackedFloat32Array()
var _sbuf := PackedFloat32Array()
var _gmm: MultiMesh
var _smm: MultiMesh
var _tr: Array = []      # traccianti {a, b, t, T, w, len, col}
var _mis: Array = []     # razzi {a, b, t, T, side}
var _im: ImmediateMesh
var _imi: MeshInstance3D
var _lights: Array = []
var _smm_inst: MultiMeshInstance3D
var _smolders: Array = []    # crateri/relitti che fumano a lungo: [pos, tempo rimasto, intervallo, prossimo sbuffo, forza]
const SMOLDER_MAX := 28
var detail := 1.0            # qualità degli effetti nuovi (alto 1, medio 0.7, basso 0.45): numero di sbuffi e fumo persistente
var _li := 0
var wind := Vector3(1.2, 0, 0.4)
var dust_color := Color(0.5, 0.45, 0.35)
var night_k := 1.0            # Fase 8: di notte le luci degli spari/esplosioni rischiarano di più il suolo
var wet := 0.0                # 0..1 pioggia: la polvere diventa fango (schizzi scuri)
var snowy := 0.0              # 0..1 neve a terra: la polvere diventa neve sollevata

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
varying vec4 cus;
varying vec4 col;
varying float size;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	size = s;
	vec3 c = MODEL_MATRIX[3].xyz;
	float r = INSTANCE_CUSTOM.z * 6.2831;
	vec2 v = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r))) * VERTEX.xy;
	vec3 wp = c + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	cus = INSTANCE_CUSTOM;
	col = COLOR;
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
	float age = cus.x;
	vec3 c = col.rgb;
	if (cus.y > 0.5 && cus.y < 1.5) {
		c = mix(c, vec3(0.9, 0.25, 0.05), smoothstep(0.1, 0.7, age));
		a *= 1.0 - smoothstep(0.4, 1.0, age);
	} else {
		a *= 1.0 - age;
	}
	// sfumatura contro la scena (alberi, tetti, terreno): niente tagli netti dei quad grandi
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vv.xyz /= vv.w;
	float soft = clamp((VERTEX.z - vv.z) / max(0.4, size * 0.45), 0.0, 1.0);
	ALBEDO = c * 3.0;
	ALPHA = clamp(a * col.a * soft, 0.0, 1.0);
}
"""

const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3);
uniform vec3 light_col = vec3(1.0, 0.97, 0.9);
uniform vec3 amb_col = vec3(0.55, 0.6, 0.68);
varying vec4 cus;
varying vec4 col;
varying float size;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	size = s;
	vec3 c = MODEL_MATRIX[3].xyz;
	float r = INSTANCE_CUSTOM.z * 6.2831 + INSTANCE_CUSTOM.x * 0.8;
	vec2 v = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r))) * VERTEX.xy;
	vec3 wp = c + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	cus = INSTANCE_CUSTOM;
	col = COLOR;
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float age = cus.x;
	float kind = cus.y;
	// rumore animato: due strati che scorrono e si deformano con l'età (effetto "ribollire" senza flipbook)
	vec2 flow = vec2(age * 0.22, -age * 0.35);
	vec2 warp = (texture(noise_tex, UV * 0.6 + vec2(cus.z * 3.0, age * 0.15)).rg - 0.5) * 0.25;
	float n = texture(noise_tex, UV * 0.45 + warp + vec2(cus.z * 7.0, cus.z * 3.0) + flow).r;
	float n2 = texture(noise_tex, UV * 1.3 - warp + vec2(cus.z * 5.0, 0.3) - flow * 1.6).r;
	float a = 1.0 - smoothstep(0.3, 1.0, r + (n - 0.5) * 0.8 + (n2 - 0.5) * 0.35);
	// bordi più "a ciuffi" con l'età: il fumo si sfilaccia
	a *= mix(1.0, smoothstep(0.25, 0.65, n2 + 0.2), smoothstep(0.3, 1.0, age) * 0.6);
	if (kind > 2.5) {
		a = step(r, 0.55 + (n - 0.5) * 0.4);
	} else {
		a *= smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.45, 1.0, age));
	}
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vv = INV_PROJECTION_MATRIX * ndc;
	vv.xyz /= vv.w;
	float soft = clamp((VERTEX.z - vv.z) / max(0.6, size * 0.6), 0.0, 1.0);
	soft *= soft * (3.0 - 2.0 * soft);
	// vicino alla telecamera: dissolvenza (niente quad che riempiono lo schermo)
	soft *= smoothstep(size * 0.4, size * 1.4 + 1.0, -VERTEX.z);
	// illuminazione finta: lato superiore verso il sole più chiaro
	vec3 nv = normalize(vec3(uv.x, -uv.y, 0.6));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	float lit = clamp(dot(nw, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	// luce della scena (sole e ambiente dell'ora del giorno), controluce leggero sui bordi sottili
	vec3 c = col.rgb * (amb_col * 0.8 + light_col * lit * 0.65) * (0.82 + 0.36 * n2);
	c += light_col * col.rgb * (1.0 - a) * 0.25 * lit;
	if (kind > 1.5 && kind < 2.5) {
		// fumo nero con base infuocata nei primi istanti
		c = mix(c + vec3(0.9, 0.35, 0.05) * (1.0 - smoothstep(0.0, 0.18, age)), c, smoothstep(0.0, 0.18, age));
	}
	ALBEDO = c;
	ALPHA = clamp(a * col.a * soft, 0.0, 1.0);
}
"""

const TRACER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	float e = 1.0 - abs(UV.y * 2.0 - 1.0);
	float t = UV.x;
	ALBEDO = COLOR.rgb * 4.0;
	ALPHA = clamp(pow(e, 1.5) * t * COLOR.a, 0.0, 1.0);
}
"""

var _dbg_off := false

func setup(cam: Camera3D, noise_tex: Texture2D, sun_dir: Vector3) -> void:
	camera = cam
	_dbg_off = "--fxoff=1" in OS.get_cmdline_user_args()
	_g.resize(GLOW_N * ST); _gc.resize(GLOW_N)
	_s.resize(SMOKE_N * ST); _sc.resize(SMOKE_N)
	_gbuf.resize(GLOW_N * 20)
	_sbuf.resize(SMOKE_N * 20)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var gs := Shader.new(); gs.code = GLOW_SHADER
	var gm := ShaderMaterial.new(); gm.shader = gs
	var ss := Shader.new(); ss.code = SMOKE_SHADER
	var sm := ShaderMaterial.new(); sm.shader = ss
	sm.set_shader_parameter("noise_tex", noise_tex)
	sm.set_shader_parameter("sun_dir", sun_dir)
	sm.render_priority = 0
	gm.render_priority = 1
	_smm = _mk_mm(quad, sm, SMOKE_N, "Smoke")
	_smm_inst = get_node("Smoke") as MultiMeshInstance3D
	_gmm = _mk_mm(quad, gm, GLOW_N, "Glow")
	_im = ImmediateMesh.new()
	_imi = MeshInstance3D.new()
	_imi.name = "Tracers"
	_imi.mesh = _im
	var ts := Shader.new(); ts.code = TRACER_SHADER
	var tm := ShaderMaterial.new(); tm.shader = ts
	tm.render_priority = 2
	_imi.material_override = tm
	_imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imi.extra_cull_margin = 16384
	add_child(_imi)
	for i in 8:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 20.0
		l.shadow_enabled = false
		l.light_color = Color(1.0, 0.65, 0.3)
		l.visible = false
		add_child(l)
		_lights.append([l, 0.0, 0.0, 0.0])

## Luce del fumo coerente con l'ora del giorno: colore/energia del sole e luce ambiente della scena.
func set_lighting(sun_col: Color, sun_e: float, amb: Color) -> void:
	if _smm_inst == null:
		return
	var m := _smm_inst.material_override as ShaderMaterial
	m.set_shader_parameter("light_col", Vector3(sun_col.r, sun_col.g, sun_col.b) * clampf(sun_e, 0.2, 1.4))
	m.set_shader_parameter("amb_col", Vector3(amb.r, amb.g, amb.b))

func _mk_mm(mesh: Mesh, mat: Material, n: int, nm: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384
	add_child(mi)
	return mm

# ---------------------------------------------------------------------------- emissione
func _glow(p: Vector3, v: Vector3, life: float, size: float, grow: float, kind: int, c: Color, drag := 3.0, grav := 0.0) -> void:
	if _gn >= GLOW_N:
		return
	var o := _gn * ST
	_g[o] = p.x; _g[o + 1] = p.y; _g[o + 2] = p.z
	_g[o + 3] = v.x; _g[o + 4] = v.y; _g[o + 5] = v.z
	_g[o + 6] = life; _g[o + 7] = life; _g[o + 8] = size; _g[o + 9] = grow
	_g[o + 10] = kind; _g[o + 11] = randf(); _g[o + 12] = drag; _g[o + 13] = grav
	_gc[_gn] = c
	_gn += 1

func _smoke(p: Vector3, v: Vector3, life: float, size: float, grow: float, kind: int, c: Color, drag := 1.2, grav := 0.0) -> void:
	if _sn >= SMOKE_N:
		# ricicla la più vecchia approssimata: sovrascrivi una a caso
		var k := randi() % SMOKE_N
		var oo := k * ST
		_s[oo + 6] = 0.0
		return
	var o := _sn * ST
	_s[o] = p.x; _s[o + 1] = p.y; _s[o + 2] = p.z
	_s[o + 3] = v.x; _s[o + 4] = v.y; _s[o + 5] = v.z
	_s[o + 6] = life; _s[o + 7] = life; _s[o + 8] = size; _s[o + 9] = grow
	_s[o + 10] = kind; _s[o + 11] = randf(); _s[o + 12] = drag; _s[o + 13] = grav
	_sc[_sn] = c
	_sn += 1

static func _rv(m: float) -> Vector3:
	return Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * m

func muzzle(p: Vector3, dir: Vector3, s: float) -> void:
	_glow(p, dir * 2.0, 0.07 + randf() * 0.03, 1.4 * s, 1.0, 0, Color(1.0, 0.85, 0.5))
	for i in 2:
		_glow(p + dir * (0.4 + i * 0.5) * s, dir * (8.0 + randf() * 6.0), 0.06 + randf() * 0.04, 0.8 * s, 0.5, 0, Color(1.0, 0.7, 0.3))
	if s > 0.8:
		_smoke(p + dir * 0.6, dir * 3.0 + Vector3(0, 0.6, 0), 1.0 + randf() * 0.8, 1.2 * s, 2.2, 0, Color(0.72, 0.7, 0.66, 0.55))
		_smoke(p - Vector3(0, p.y * 0.0, 0), dir * 1.0 + _rv(1.5) + Vector3(0, 0.3, 0), 1.4 + randf(), 1.6 * s, 2.0, 1, Color(_ground_dust(), 0.4))

func hit(p: Vector3, s: float, ground: bool) -> void:
	_glow(p, Vector3.ZERO, 0.12, 1.6 * s, 1.5, 0, Color(1.0, 0.8, 0.45))
	for i in int(3 + 3 * s):
		_glow(p, _rv(9.0 * s) + Vector3(0, 6.0 * s, 0), 0.25 + randf() * 0.25, 0.22, 0.0, 2, Color(1.0, 0.75, 0.35), 0.5, 18.0)
	if ground:
		_smoke(p, _rv(1.0) + Vector3(0, 1.5, 0), 1.2 + randf() * 0.8, 1.2 * s + 0.6, 2.2, 1, Color(_ground_dust(), 0.6))
	else:
		_smoke(p, _rv(1.0), 0.9, 1.0 * s, 2.0, 0, Color(0.25, 0.24, 0.23, 0.6))

func flak(p: Vector3) -> void:
	_glow(p, Vector3.ZERO, 0.1, 1.6, 1.2, 0, Color(1.0, 0.75, 0.4))
	_smoke(p, _rv(0.6), 1.6 + randf(), 1.4, 1.6, 0, Color(0.16, 0.15, 0.15, 0.75))

func explosion(p: Vector3, s: float, ground: bool) -> void:
	# lampo centrale ampio e palla di fuoco che si gonfia (Fase 8: più grande e più luminosa)
	_glow(p + Vector3(0, 0.6 * s, 0), Vector3.ZERO, 0.14, 6.0 * s, 1.5, 0, Color(1.0, 0.92, 0.75))
	_glow(p + Vector3(0, 1.2 * s, 0), Vector3(0, 3.0 * s, 0), 0.5, 3.2 * s, 2.0, 1, Color(1.0, 0.7, 0.3), 1.5)
	for i in int(5 + 6 * s):
		_glow(p + _rv(1.3 * s) + Vector3(0, s, 0), _rv(5.5 * s) + Vector3(0, 4.5 * s, 0), 0.35 + randf() * 0.4, (1.8 + randf() * 1.8) * s, 1.5, 1, Color(1.0, 0.62, 0.22), 2.5)
	for i in int(8 + 10 * s):
		_glow(p + Vector3(0, 0.4, 0), _rv(18.0 * s) + Vector3(0, 11.0 * s, 0), 0.4 + randf() * 0.7, 0.25, 0.0, 2, Color(1.0, 0.7, 0.3), 0.6, 16.0)
	# fungo: molti sbuffi più piccoli invece di pochi piani grandi (si leggono come volume)
	for i in int((7 + 8 * s) * lerpf(0.6, 1.0, detail)):
		_smoke(p + _rv(1.2 * s) + Vector3(0, (0.6 + randf() * 1.2) * s, 0), _rv(2.6 * s) + Vector3(0, 2.5 + randf() * 4.5 * s, 0), 2.6 + randf() * 3.2, (1.3 + randf() * 1.3) * s, 2.8, 2, Color(0.16, 0.14, 0.13, 0.8), 1.0)
	if ground:
		var dc := _ground_dust()
		for i in int(5 + 6 * s):
			var a := randf() * TAU
			var v := Vector3(cos(a), 0.15 + randf() * 0.3, sin(a)) * (6.0 + randf() * 8.0) * s
			_smoke(p + Vector3(0, 0.4, 0), v, 1.8 + randf() * 1.5, (1.8 + randf()) * s, 2.0, 1, Color(dc, 0.7), 2.2)
		for i in int(5 + 7 * s):
			_smoke(p + Vector3(0, 0.3, 0), _rv(8.0 * s) + Vector3(0, 10.0 * s + randf() * 7.0, 0), 1.0 + randf() * 0.7, 0.25 + randf() * 0.3, 0.0, 3, Color(0.12, 0.1, 0.08, 1.0) if wet < 0.5 else Color(0.2, 0.17, 0.12, 1.0), 0.3, 18.0)
		# zolle e sassi più grossi, lenti a ricadere: danno peso al colpo
		for i in int((2 + 3 * s) * detail):
			_smoke(p + Vector3(0, 0.4, 0), _rv(5.0 * s) + Vector3(0, 7.0 * s + randf() * 5.0, 0), 1.3 + randf() * 0.6, 0.5 + randf() * 0.45, 0.0, 3, Color(0.17, 0.14, 0.1, 1.0), 0.15, 15.0)
		# foschia bassa che resta sul campo e scivola col vento
		for i in (2 if detail > 0.6 else 1):
			_smoke(p + _rv(2.0 * s) + Vector3(0, 1.0, 0), wind * 0.3 + Vector3(0, 0.15, 0), 14.0 + randf() * 8.0, (3.5 + randf() * 2.0) * s, 1.6, 0, Color(dc.lerp(Color(0.5, 0.5, 0.5), 0.5), 0.22), 0.6)
		if s >= 0.9:
			smolder(p, 22.0 + randf() * 14.0, clampf(s * 0.6, 0.4, 1.0))
	light(p + Vector3(0, 2.0 + s, 0), 9.0 * s, 16.0 + 12.0 * s, 0.34)

## Colore della polvere sollevata secondo il suolo del momento: fango con la pioggia, neve nell'artico/nevicata.
func _ground_dust() -> Color:
	var c := dust_color
	if snowy > 0.3:
		c = c.lerp(Color(0.88, 0.9, 0.94), snowy)
	if wet > 0.3:
		c = c.lerp(Color(0.22, 0.18, 0.13), wet * 0.8)
	return c

## Goccia di pioggia che tocca terra: minuscolo sbuffo chiaro (molte al secondo, vita brevissima).
func splash_drop(p: Vector3) -> void:
	_smoke(p, Vector3(0, 0.7, 0), 0.22 + randf() * 0.1, 0.25, 1.6, 0, Color(0.85, 0.88, 0.92, 0.4), 2.0)

## Schizzo di fango dietro un mezzo (pioggia): gocce scure che ricadono e sbuffo marrone basso.
func mud_splash(p: Vector3, s := 1.0) -> void:
	for i in int(2 + 3 * s):
		_smoke(p + Vector3(0, 0.3, 0), _rv(2.5 * s) + Vector3(0, 3.5 * s + randf() * 2.0, 0), 0.5 + randf() * 0.3, 0.18 + randf() * 0.12, 0.0, 3, Color(0.2, 0.16, 0.11, 1.0), 0.4, 14.0)
	_smoke(p, _rv(0.5) + Vector3(0, 0.6, 0), 0.9 + randf() * 0.5, 0.9 * s, 1.6, 1, Color(0.26, 0.21, 0.15, 0.45), 1.8)

## Neve sollevata dai cingoli: nuvola bianca che si disperde in fretta.
func snow_spray(p: Vector3, s := 1.0) -> void:
	_smoke(p, _rv(1.2) + Vector3(0, 1.2, 0), 1.0 + randf() * 0.6, 1.0 * s, 2.0, 1, Color(0.9, 0.92, 0.96, 0.5), 1.6)
	for i in 2:
		_smoke(p + Vector3(0, 0.3, 0), _rv(2.0 * s) + Vector3(0, 2.5 * s, 0), 0.5, 0.2, 0.0, 3, Color(0.95, 0.96, 1.0, 1.0), 0.5, 10.0)

## Crollo di un edificio: nube di polvere di calcinacci che rotola bassa, detriti che ricadono, sbuffo alto.
func collapse(p: Vector3, size: Vector3, col: Color) -> void:
	var s := clampf((size.x + size.z) * 0.08, 0.8, 3.5)
	var dc := col.lerp(Color(0.6, 0.57, 0.52), 0.6)
	for i in int(8 + 8 * s):
		var a := randf() * TAU
		var v := Vector3(cos(a), 0.05 + randf() * 0.2, sin(a)) * (4.0 + randf() * 6.0) * s
		_smoke(p + Vector3(cos(a), 0.3, sin(a)) * size.x * 0.3, v, 3.0 + randf() * 2.5, (2.2 + randf() * 1.4) * s, 2.2, 1, Color(dc, 0.8), 1.6)
	for i in int(5 + 4 * s):
		_smoke(p + _rv(size.x * 0.25) + Vector3(0, size.y * 0.5, 0), _rv(1.5) + Vector3(0, 3.0 + randf() * 3.0, 0), 4.0 + randf() * 3.0, (2.5 + randf()) * s, 2.0, 0, Color(dc * 0.9, 0.7), 0.9)
	for i in int(10 + 10 * s):
		_smoke(p + Vector3(0, size.y * 0.4, 0), _rv(7.0 * s) + Vector3(0, 6.0 + randf() * 6.0, 0), 0.9 + randf() * 0.8, 0.3 + randf() * 0.4, 0.0, 3, Color(col * 0.7, 1.0), 0.3, 16.0)

## Chioma che si abbatte: foglie/aghi e polvere alla base.
func tree_fall(p: Vector3, s := 1.0) -> void:
	_smoke(p, _rv(0.8) + Vector3(0, 0.8, 0), 1.4 + randf() * 0.6, 1.2 * s, 1.8, 1, Color(_ground_dust(), 0.45), 1.5)
	for i in 5:
		_smoke(p + Vector3(0, 1.5 + randf() * 3.0, 0), _rv(2.5) + Vector3(0, 1.0, 0), 1.0 + randf() * 0.8, 0.16, 0.0, 3, Color(0.25, 0.36, 0.14, 1.0), 0.8, 4.0)

## Cratere o relitto che continua a fumare: un filo di fumo grigio che sale e si piega col vento (max SMOLDER_MAX attivi).
func smolder(p: Vector3, dur: float, k := 0.6) -> void:
	if _smolders.size() >= int(SMOLDER_MAX * detail):
		_smolders.pop_front()
	_smolders.append([p, dur, lerpf(1.6, 0.7, k), randf() * 0.5, k])

func _update_smolders(dt: float) -> void:
	var i := 0
	while i < _smolders.size():
		var S: Array = _smolders[i]
		S[1] -= dt
		if S[1] <= 0.0:
			_smolders.remove_at(i)
			continue
		S[3] -= dt
		if S[3] <= 0.0:
			var fade: float = clampf(S[1] / 8.0, 0.0, 1.0)
			S[3] = S[2] * (0.8 + randf() * 0.4) / maxf(0.4, detail)
			var k: float = S[4]
			_smoke(S[0] + _rv(0.8) + Vector3(0, 0.4, 0), Vector3(0, 1.4 + randf() * 0.8, 0) + wind * 0.35, 6.0 + randf() * 3.0,
				(0.9 + randf() * 0.6) * (0.7 + k), 3.2, 0, Color(0.3, 0.29, 0.28, (0.35 + 0.2 * k) * fade), 0.5)
		i += 1

func burn(p: Vector3, strength: float) -> void:
	# fumo da relitto: denso e scuro all'inizio, poi più leggero
	var c := Color(0.13, 0.12, 0.11, 0.8).lerp(Color(0.32, 0.31, 0.3, 0.55), 1.0 - strength)
	_smoke(p + _rv(0.6), Vector3(0, 2.2 + randf() * 1.5, 0) + wind * 0.4, 3.5 + randf() * 2.5, 1.5 + randf() * 1.0, 1.9, 2 if strength > 0.7 else 0, c, 0.4)
	if strength > 0.6 and randf() < 0.6:
		_glow(p + _rv(0.5) + Vector3(0, 0.6, 0), Vector3(0, 2.0, 0), 0.35 + randf() * 0.3, 1.0 + randf() * 0.8, 0.6, 1, Color(1.0, 0.55, 0.15), 1.5)

## Colonna d'acqua (colpo in mare).
func splash(p: Vector3, s := 1.0) -> void:
	for i in int(5 + 4 * s):
		_smoke(p + _rv(1.2 * s), _rv(2.5 * s) + Vector3(0, 9.0 * s + randf() * 7.0 * s, 0), 1.4 + randf() * 0.9, (1.4 + randf()) * s, 1.6, 0, Color(0.86, 0.9, 0.92, 0.75), 1.4, 9.0)
	for i in int(4 + 3 * s):
		var a := randf() * TAU
		_smoke(p + Vector3(0, 0.3, 0), Vector3(cos(a), 0.1, sin(a)) * (4.0 + randf() * 3.0) * s, 1.8 + randf(), (1.8 + randf()) * s, 1.8, 0, Color(0.8, 0.85, 0.88, 0.55), 2.0)

## Cortina fumogena: nubi bianche basse e lente (abilità "Fumo").
func smoke_screen(p: Vector3, s := 1.0, n := 2) -> void:
	for i in n:
		var o := Vector3((randf() - 0.5) * 6.0, 0.4 + randf() * 1.2, (randf() - 0.5) * 6.0) * s
		_smoke(p + o, _rv(0.7) + Vector3(0, 0.3 + randf() * 0.3, 0) + wind * 0.25, 4.5 + randf() * 2.0, (3.2 + randf() * 1.6) * s, 1.7, 0, Color(0.88, 0.89, 0.88, 0.72), 0.8)

func trail(p: Vector3, s := 0.6, c := Color(0.85, 0.85, 0.85, 0.5)) -> void:
	_smoke(p, _rv(0.3), 1.2 + randf() * 0.8, s, 2.4, 0, c, 1.0)

func dust(p: Vector3, s := 1.0) -> void:
	if wet > 0.5:
		mud_splash(p, s * 0.8)
		return
	if snowy > 0.5:
		snow_spray(p, s)
		return
	_smoke(p, _rv(0.6) + Vector3(0, 0.5, 0), 1.2 + randf() * 0.8, s, 1.8, 1, Color(_ground_dust(), 0.35), 1.5)

## Vampa a terra del cannone: anello di polvere schiacciata davanti alla bocca (dà "peso" allo sparo).
func blast_dust(g: Vector3, dir: Vector3, s := 1.0) -> void:
	if wet > 0.5 or snowy > 0.5:
		dust(g, s)
		return
	var dc := _ground_dust()
	for i in int(4 + 2 * s):
		var a := randf() * TAU
		var v := (Vector3(cos(a), 0.0, sin(a)) * 0.6 + dir * 0.8).normalized() * (5.0 + randf() * 5.0) * s
		v.y = 0.4 + randf() * 0.6
		_smoke(g + Vector3(0, 0.3, 0), v, 1.2 + randf() * 0.8, (1.0 + randf() * 0.6) * s, 2.4, 1, Color(dc, 0.5), 2.6)

## Polvere sotto i cingoli: due sbuffi bassi ai lati, che restano un po' e scivolano col vento.
func track_dust(l: Vector3, r: Vector3, s := 1.0) -> void:
	if wet > 0.5:
		mud_splash(l, s * 0.7)
		return
	if snowy > 0.5:
		snow_spray(l, s * 0.8)
		snow_spray(r, s * 0.8)
		return
	var dc := _ground_dust()
	for q in ([l, r] if detail > 0.5 else [l.lerp(r, 0.5)]):
		_smoke(q + Vector3(0, 0.25, 0), _rv(0.5) + Vector3(0, 0.35, 0) + wind * 0.2, 1.6 + randf() * 1.2, (0.9 + randf() * 0.4) * s, 2.2, 1, Color(dc, 0.32), 1.4)

func light(p: Vector3, energy: float, rng: float, dur: float) -> void:
	var L: Array = _lights[_li]
	_li = (_li + 1) % _lights.size()
	var l: OmniLight3D = L[0]
	energy *= night_k
	l.position = p
	l.omni_range = rng * (1.0 + 0.35 * (night_k - 1.0))
	l.light_energy = energy
	l.visible = true
	L[1] = dur; L[2] = dur; L[3] = energy

func tracer(a: Vector3, b: Vector3, T: float, w: float, len_: float, col: Color) -> void:
	if _tr.size() > 260:
		return
	if night_k > 1.0:
		w *= 1.35
		col.a = minf(1.0, col.a * 1.25)
	_tr.append([a, b, 0.0, T, w, len_, col])

func missile(a: Vector3, b: Vector3, T: float) -> void:
	_mis.append([a, b, 0.0, T, 0.0])

# ---------------------------------------------------------------------------- aggiornamento
func update(dt: float, paused: bool) -> void:
	if not paused:
		_sim(_g, _gc, dt, true)
		_sim(_s, _sc, dt, false)
		_update_smolders(dt)
		for L in _lights:
			if L[1] > 0:
				L[1] -= dt
				var l: OmniLight3D = L[0]
				if L[1] <= 0:
					l.visible = false
				else:
					l.light_energy = L[3] * (L[1] / L[2])
	_fill(_g, _gc, _gn, _gbuf, _gmm)
	_fill(_s, _sc, _sn, _sbuf, _smm)
	_draw_tracers(dt if not paused else 0.0)

func _sim(A: PackedFloat32Array, C: PackedColorArray, dt: float, glow: bool) -> void:
	var n := _gn if glow else _sn
	var i := 0
	while i < n:
		var o := i * ST
		var life := A[o + 6] - dt
		if life <= 0:
			n -= 1
			var last := n * ST
			for k in ST:
				A[o + k] = A[last + k]
			C[i] = C[n]
			continue
		A[o + 6] = life
		var dr := 1.0 - minf(1.0, A[o + 12] * dt)
		A[o + 3] *= dr; A[o + 4] *= dr; A[o + 5] *= dr
		A[o + 4] -= A[o + 13] * dt
		if not glow and int(A[o + 10]) != 3:
			A[o + 3] += wind.x * dt * 0.8
			A[o + 5] += wind.z * dt * 0.8
			A[o + 4] += 0.25 * dt
		A[o] += A[o + 3] * dt; A[o + 1] += A[o + 4] * dt; A[o + 2] += A[o + 5] * dt
		if int(A[o + 10]) == 3 and A[o + 1] < -50:
			A[o + 6] = 0.0
		i += 1
	if glow:
		_gn = n
	else:
		_sn = n

func _fill(A: PackedFloat32Array, C: PackedColorArray, n: int, buf: PackedFloat32Array, mm: MultiMesh) -> void:
	for i in n:
		var o := i * ST
		var b := i * 20
		var age := 1.0 - A[o + 6] / A[o + 7]
		var s := A[o + 8] * (1.0 + A[o + 9] * age)
		buf[b] = s; buf[b + 1] = 0; buf[b + 2] = 0; buf[b + 3] = A[o]
		buf[b + 4] = 0; buf[b + 5] = s; buf[b + 6] = 0; buf[b + 7] = A[o + 1]
		buf[b + 8] = 0; buf[b + 9] = 0; buf[b + 10] = s; buf[b + 11] = A[o + 2]
		var c := C[i]
		buf[b + 12] = c.r; buf[b + 13] = c.g; buf[b + 14] = c.b; buf[b + 15] = c.a
		buf[b + 16] = age; buf[b + 17] = A[o + 10]; buf[b + 18] = A[o + 11]; buf[b + 19] = 0.0
	mm.buffer = buf
	mm.visible_instance_count = 0 if _dbg_off else n   # --fxoff=1: misura del costo di fumo e bagliori

func _draw_tracers(dt: float) -> void:
	_im.clear_surfaces()
	if camera == null:
		return
	var cam := camera.global_position
	var any := false
	var i := 0
	while i < _tr.size():
		var t: Array = _tr[i]
		t[2] += dt
		if t[2] >= t[3]:
			_tr.remove_at(i)
			continue
		i += 1
	i = 0
	while i < _mis.size():
		var m: Array = _mis[i]
		m[2] += dt
		var f: float = m[2] / m[3]
		var a: Vector3 = m[0]
		var b: Vector3 = m[1]
		var p := a.lerp(b, minf(f, 1.0)) + Vector3(0, sin(minf(f, 1.0) * PI) * a.distance_to(b) * 0.04, 0)
		if f >= 1.0:
			_mis.remove_at(i)
			continue
		m[4] -= dt
		if m[4] <= 0 and dt > 0:
			m[4] = 0.015
			trail(p, 0.5, Color(0.8, 0.8, 0.78, 0.55))
		_glow(p, Vector3.ZERO, 0.03, 0.9, 0.0, 0, Color(1.0, 0.8, 0.5))
		i += 1
	if _tr.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in _tr:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var f: float = t[2] / t[3]
		var dir := b - a
		var L := dir.length()
		if L < 0.01:
			continue
		var d := dir / L
		var head := a + d * (L * f)
		var tl: float = minf(t[5], L * f + 0.5)
		var tail := head - d * tl
		var side := d.cross(cam - head).normalized() * float(t[4])
		var col: Color = t[6]
		_quad(tail, head, side, col)
		any = true
	_im.surface_end()
	if not any:
		_im.clear_surfaces()

func _quad(tail: Vector3, head: Vector3, side: Vector3, col: Color) -> void:
	_im.surface_set_color(col)
	_im.surface_set_uv(Vector2(0, 0)); _im.surface_add_vertex(tail - side)
	_im.surface_set_uv(Vector2(1, 0)); _im.surface_add_vertex(head - side)
	_im.surface_set_uv(Vector2(1, 1)); _im.surface_add_vertex(head + side)
	_im.surface_set_uv(Vector2(0, 0)); _im.surface_add_vertex(tail - side)
	_im.surface_set_uv(Vector2(1, 1)); _im.surface_add_vertex(head + side)
	_im.surface_set_uv(Vector2(0, 1)); _im.surface_add_vertex(tail + side)

## Proiettile d'artiglieria in volo (chiamato dalla vista per ogni proiettile attivo).
func shell_draw(p: Vector3, v: Vector3, emit_trail: bool) -> void:
	_glow(p, Vector3.ZERO, 0.025, 0.7, 0.0, 0, Color(1.0, 0.75, 0.45))
	if emit_trail:
		_smoke(p, _rv(0.2), 0.9 + randf() * 0.5, 0.45, 2.0, 0, Color(0.75, 0.74, 0.72, 0.35), 1.0)
	if v.length() > 0.1:
		tracer(p - v.normalized() * 3.0, p, 0.03, 0.12, 3.0, Color(1.0, 0.7, 0.4, 0.7))

func counts() -> Vector2i:
	return Vector2i(_gn, _sn)
