class_name ModelKit
extends RefCounted
## Costruttore di mesh procedurali (Agente F).
## Accumula triangoli per materiale con normali corrette (piatte per le superfici dure, lisce per cilindri/sfere/loft),
## colori per vertice (camuffamento, sporco, bruciato) e materiali PBR condivisi da tutti i modelli.
## Convenzione Godot: facce frontali in senso orario; ogni primitiva si orienta da sola verso l'esterno.

static var _mats := {}
## false = materiali StandardMaterial3D semplici al posto degli shader (vernice/cingoli/fogliame): confronto prestazioni
## o qualità minima. Va impostato prima di costruire i modelli (le mesh in cache tengono il materiale con cui sono nate).
static var use_shaders := true
static var _noise: FastNoiseLite = null

const MUD := Color(0.27, 0.22, 0.15)
const SAND := Color(0.55, 0.48, 0.34)

var t := Transform3D.IDENTITY   ## trasformazione corrente applicata a tutti i punti
var fac := Color.WHITE          ## colore fazione (materiale "faction")
var camo := 1.0                 ## 0 = vernice liscia, 1 = mimetica a macchie (mezzi), 2 = mimetica fine (uniformi)
var dirt_h := 0.0               ## altezza (m) sotto la quale la vernice si sporca di fango
var burnt := false              ## relitto: tutto carbonizzato
var style := -1                 ## stile di fazione della vernice: -1 generico, 0 AAN pixel, 1 FO verde/sabbia, 2 CP navale, 3 UL ruggine
var _s := {}                    ## chiave materiale -> [verts, normals, colors] (+ [uv, uv2] per i soldati animati)
## Soldati animati (soldier.gdshader): ogni vertice porta in UV (x, z) la posizione del soldato nel modello e in UV2
## (imbardata, osso + 16 * indice del soldato). Le superfici usano i materiali "<chiave>#rig". Solo con use_shaders.
var rig := false
var rig_bone := 1               ## 1 busto, 2 testa, 3/4 coscia/stinco sx, 5/6 coscia/stinco dx, 7 braccia+fucile, 8 braccia+lanciarazzi
var _rig_uv := Vector2.ZERO
var _rig_n := 0
## Ruote animate (wheel.gdshader): tra wheel_begin() e wheel_end() le primitive con chiave "wheel_rubber" / "wheel_paint" /
## "wheel_metal" portano in UV il centro dell'asse (y, z) e in UV2.x il raggio: il vertex shader le fa girare attorno all'asse X
## del modello secondo il parametro per istanza `roll` (metri percorsi), lo stesso che fa scorrere le maglie dei cingoli.
var _wheel := false
var _wuv := Vector2.ZERO
var _wuv2 := Vector2.ZERO
const WHEEL_KEYS := ["wheel_rubber", "wheel_paint", "wheel_metal"]
## Posti per numero tattico + stemma (marks.gdshader): [centro, normale, larghezza, altezza]; finiscono nel meta "marks"
## della mesh e UnitModels vi appoggia un MeshInstance "Marks" con il numero per istanza.
var marks: Array = []

## Registra un posto per numero tattico e stemma: centro `p`, normale `n` (verso l'esterno), larghezza `w` e altezza `h` in metri.
func mark(p: Vector3, n: Vector3, w: float = 0.9, h: float = 0.42) -> void:
	if burnt:
		return
	marks.append([t * p, (t.basis * n).normalized(), w, h])

## Coppia di posti speculari sui fianchi (normali ±X, `tilt` = inclinazione verso l'alto della parete, es. torrette rastremate).
func marks_x(x: float, y: float, z: float, w: float = 0.9, h: float = 0.42, tilt: float = 0.0) -> void:
	mark(Vector3(x, y, z), Vector3(1.0, tilt, 0.0), w, h)
	mark(Vector3(-x, y, z), Vector3(-1.0, tilt, 0.0), w, h)

func _init(faction_color: Color = Color.WHITE, is_burnt: bool = false) -> void:
	fac = faction_color
	burnt = is_burnt

## Inizia un soldato animato: legge posizione e imbardata dalla trasformazione corrente `t`.
func rig_begin() -> void:
	_rig_uv = Vector2(t.origin.x, t.origin.z)
	_rig_yaw = t.basis.get_euler().y
	_rig_idx = _rig_n
	_rig_n += 1

var _rig_yaw := 0.0
var _rig_idx := 0

## Inizia una ruota: centro dell'asse `p` (coordinate locali, asse di rotazione = X del modello) e raggio `r`.
func wheel_begin(p: Vector3, r: float) -> void:
	var c := t * p
	_wheel = true
	_wuv = Vector2(c.y, c.z)
	_wuv2 = Vector2(r, 0.0)

func wheel_end() -> void:
	_wheel = false

## Ruota completa che gira: pneumatico/cerchione in gomma, mozzo dipinto (hub_r = frazione del raggio) e coprimozzo in metallo
## (lod 0). Asse lungo X, centrata in `p`, larghezza `w`.
func wheel(p: Vector3, r: float, w: float, seg: int, hub: Color, lod: int, hub_r: float = 0.6, tyre: Color = Color(0.11, 0.11, 0.1)) -> void:
	var rx := Basis(Vector3.BACK, PI * 0.5)
	wheel_begin(p, r)
	cyl("wheel_rubber", r, r, w, seg, Transform3D(rx, p), tyre)
	cyl("wheel_paint", r * hub_r, r * hub_r, w + 0.02, seg if lod < 2 else 6, Transform3D(rx, p), hub)
	if lod == 0:
		cyl("wheel_metal", r * 0.2, r * 0.17, w + 0.07, 6, Transform3D(rx, p), Color(0.2, 0.2, 0.21))
	wheel_end()

# ---------------------------------------------------------------- materiali condivisi
static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	if key.ends_with("#rig"):
		var rm := _rig_mat(key.trim_suffix("#rig"))
		_mats[key] = rm
		return rm
	if key.begins_with("wheel_"):
		if not use_shaders:
			return mat(key.trim_prefix("wheel_"))
		var wm := _wheel_mat(key.trim_prefix("wheel_"))
		_mats[key] = wm
		return wm
	if key.begins_with("paint") and use_shaders:
		var sm := _paint_mat(key)
		_mats[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.85
	if key.begins_with("faction:"):
		# insegne e bande della fazione: vernice opaca leggermente luminosa (leggibile da lontano senza effetto "neon")
		var c := Color(key.substr(8))
		m.roughness = 0.62
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.14
	elif key.begins_with("paint"):
		m.roughness = 0.8
		m.metallic = 0.1
		var tx: Texture2D = null
		match key:
			"paint": tx = camo_tex()
			"paint_fine": tx = camo_tex()
			"paint_pixel", "paint_pixel_fine": tx = pixel_tex()
			"paint_fo", "paint_cp", "paint_rust": tx = style_tex(key)
		if tx != null:
			m.albedo_texture = tx
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * (1.6 if key.ends_with("_fine") else 0.14)
	elif not use_shaders and key in ["track", "foliage"]:
		m.roughness = 0.9
		if key == "foliage":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		match key:
			"metal":
				m.roughness = 0.46
				m.metallic = 0.75
				m.metallic_specular = 0.5
			"rubber":
				m.roughness = 0.96
				m.metallic_specular = 0.2
			"glass":
				m.roughness = 0.06
				m.metallic = 0.65
				m.metallic_specular = 1.0
			"stained":
				m.roughness = 0.95
				m.metallic_specular = 0.3
				m.albedo_texture = stain_tex()
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 0.12
			"matte":
				m.roughness = 0.92
				m.metallic_specular = 0.3
			"track":
				var tm := ShaderMaterial.new()
				tm.shader = load("res://scripts/models/track.gdshader")
				_mats[key] = tm
				return tm
			"foliage":
				var fm := ShaderMaterial.new()
				fm.shader = load("res://scripts/models/foliage.gdshader")
				fm.set_shader_parameter("grime_tex", grime_tex())
				_mats[key] = fm
				return fm
			"light":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.emission_enabled = true
				m.emission = Color(1, 0.85, 0.6)
			"burnt":
				m.roughness = 1.0
				m.metallic = 0.15
	_mats[key] = m
	return m

## Vernice dei mezzi: ShaderMaterial (paint.gdshader) con mimetica triplanare e invecchiamento procedurale.
## Chiavi: paint, paint_fine (uniformi), paint_pixel(_fine) (AAN), paint_fo, paint_cp, paint_rust, paint_plain (senza mimetica).
static func _paint_mat(key: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var pixel := key.begins_with("paint_pixel")
	sm.shader = _paint_shader(pixel)
	sm.set_shader_parameter("grime_tex", grime_tex())
	var rough := 0.8
	var metal := 0.1
	var scale := 0.16
	var sharp := 4.0
	var wear := 1.0
	var tex: Texture2D = null
	match key:
		"paint":
			tex = camo_tex()
		"paint_fine":
			tex = camo_tex()
			scale = 1.6
			wear = 0.3
			rough = 0.88
			metal = 0.0
		"paint_pixel", "paint_pixel_fine":
			tex = pixel_tex()
			rough = 0.78
			metal = 0.08
			sharp = 6.0
			scale = 0.11 if key == "paint_pixel" else 1.3
			if key == "paint_pixel_fine":
				wear = 0.3
				metal = 0.0
				rough = 0.88
		"paint_fo", "paint_cp", "paint_rust":
			tex = style_tex(key)
			rough = 0.82 if key != "paint_cp" else 0.62
			metal = 0.1 if key != "paint_rust" else 0.25
			scale = 0.11 if key == "paint_fo" else (0.2 if key == "paint_cp" else 0.32)
			wear = 0.75 if key == "paint_cp" else (1.4 if key == "paint_rust" else 1.0)
		_:
			rough = 0.6
			metal = 0.2
			wear = 0.5
	sm.set_shader_parameter("use_camo", tex != null)
	if tex != null:
		sm.set_shader_parameter("camo_tex", tex)
	sm.set_shader_parameter("camo_scale", scale)
	sm.set_shader_parameter("sharp", sharp)
	sm.set_shader_parameter("base_rough", rough)
	sm.set_shader_parameter("base_metal", metal)
	sm.set_shader_parameter("wear", wear)
	return sm

## Materiale delle ruote animate (wheel.gdshader): sub = rubber | paint | metal.
static func _wheel_mat(sub: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/models/wheel.gdshader")
	sm.set_shader_parameter("grime_tex", grime_tex())
	match sub:
		"rubber":
			sm.set_shader_parameter("base_rough", 0.95)
			sm.set_shader_parameter("base_metal", 0.0)
			sm.set_shader_parameter("spec", 0.25)
			sm.set_shader_parameter("tyre", true)
		"metal":
			sm.set_shader_parameter("base_rough", 0.46)
			sm.set_shader_parameter("base_metal", 0.75)
			sm.set_shader_parameter("spec", 0.5)
			sm.set_shader_parameter("tyre", false)
		_:
			sm.set_shader_parameter("base_rough", 0.8)
			sm.set_shader_parameter("base_metal", 0.1)
			sm.set_shader_parameter("spec", 0.45)
			sm.set_shader_parameter("tyre", false)
	return sm

static func _paint_shader(pixel: bool) -> Shader:
	var k := "_shader_pixel" if pixel else "_shader_paint"
	if _mats.has(k):
		return _mats[k]
	var sh: Shader = load("res://scripts/models/paint.gdshader")
	if pixel:
		var s2 := Shader.new()
		s2.code = sh.code.replace("source_color, filter_linear_mipmap_anisotropic, repeat_enable", "source_color, filter_nearest_mipmap, repeat_enable")
		sh = s2
	_mats[k] = sh
	return sh

## Rumore in scala di grigi ripetibile per sporco/usura (condiviso da vernice e fogliame).
static func grime_tex() -> Texture2D:
	if _mats.has("_grime_tex"):
		return _mats["_grime_tex"]
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = 2718
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz.frequency = 0.03
	nz.fractal_octaves = 4
	nt.noise = nz
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.normalize = true
	_mats["_grime_tex"] = nt
	return nt

## Texture di camuffamento a macchie (moltiplicata per il colore di vertice), proiezione triplanare in spazio oggetto.
static func camo_tex() -> Texture2D:
	if _mats.has("_camo_tex"):
		return _mats["_camo_tex"]
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = 4242
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.012
	nz.fractal_octaves = 3
	nz.fractal_gain = 0.6
	nz.domain_warp_enabled = true
	nz.domain_warp_amplitude = 40.0
	nt.noise = nz
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.36, 0.55, 0.72])
	g.colors = PackedColorArray([Color(0.66, 0.68, 0.58), Color(0.95, 0.96, 0.93), Color(1.0, 0.94, 0.8), Color(0.52, 0.52, 0.48)])
	nt.color_ramp = g
	_mats["_camo_tex"] = nt
	return nt

## Mimetica digitale "a pixel" (AAN): celle quadrate su 4 toni, da moltiplicare per una base grigio-verde chiara.
static func pixel_tex() -> Texture2D:
	if _mats.has("_pixel_tex"):
		return _mats["_pixel_tex"]
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz.frequency = 0.06
	nz.fractal_octaves = 2
	var n2 := FastNoiseLite.new()
	n2.seed = 78
	n2.frequency = 0.4
	var cols := [Color(0.42, 0.47, 0.42), Color(0.7, 0.8, 0.64), Color(1.0, 1.0, 0.97), Color(0.9, 0.8, 0.62)]
	var N := 64
	var img := Image.create(N * 2, N * 2, false, Image.FORMAT_RGB8)
	for y in N:
		for x in N:
			# rumore periodico (toro) per una texture ripetibile
			var ax := TAU * float(x) / float(N)
			var ay := TAU * float(y) / float(N)
			var v := nz.get_noise_3d(cos(ax) * 9.0, sin(ax) * 9.0, cos(ay) * 9.0 + sin(ay) * 4.0)
			v += 0.16 * n2.get_noise_2d(float(x), float(y))
			var i := 0 if v < -0.2 else (1 if v < 0.04 else (2 if v < 0.22 else 3))
			img.fill_rect(Rect2i(x * 2, y * 2, 2, 2), cols[i])
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats["_pixel_tex"] = tex
	return tex

## Texture di fazione: "paint_fo" grandi macchie verde scuro/marrone su sabbia, "paint_cp" grigio navale a bassissimo contrasto,
## "paint_rust" vernice sabbia consumata con chiazze di ruggine e di primer (UL).
static func style_tex(key: String) -> Texture2D:
	var tk := "_tex_" + key
	if _mats.has(tk):
		return _mats[tk]
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var g := Gradient.new()
	match key:
		"paint_fo":
			nz.seed = 515
			nz.frequency = 0.01
			nz.fractal_octaves = 2
			nz.domain_warp_enabled = true
			nz.domain_warp_amplitude = 55.0
			g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.62, 0.8])
			g.colors = PackedColorArray([Color(0.5, 0.45, 0.4), Color(0.56, 0.7, 0.5), Color(1.0, 0.98, 0.92), Color(0.56, 0.7, 0.5)])
		"paint_cp":
			nz.seed = 616
			nz.frequency = 0.02
			nz.fractal_octaves = 2
			g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			g.offsets = PackedFloat32Array([0.0, 0.4, 0.7])
			g.colors = PackedColorArray([Color(0.86, 0.88, 0.9), Color(1, 1, 1), Color(0.92, 0.94, 0.97)])
		_:
			nz.seed = 717
			nz.frequency = 0.035
			nz.fractal_octaves = 4
			nz.fractal_gain = 0.65
			g.offsets = PackedFloat32Array([0.0, 0.22, 0.3, 0.5, 0.72, 0.8, 1.0])
			g.colors = PackedColorArray([Color(0.62, 0.36, 0.2), Color(0.72, 0.45, 0.28), Color(0.95, 0.9, 0.8), Color(1, 0.97, 0.9),
				Color(0.93, 0.88, 0.78), Color(0.6, 0.62, 0.58), Color(0.55, 0.57, 0.53)])
	nt.noise = nz
	nt.color_ramp = g
	_mats[tk] = nt
	return nt

## Macchie di umidità/sporco per cemento e intonaco (scala di grigi, triplanare).
static func stain_tex() -> Texture2D:
	if _mats.has("_stain_tex"):
		return _mats["_stain_tex"]
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = 99
	nz.frequency = 0.02
	nz.fractal_octaves = 5
	nt.noise = nz
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0.8, 0.78, 0.75), Color(0.93, 0.92, 0.9), Color(1, 1, 1)])
	nt.color_ramp = g
	_mats["_stain_tex"] = nt
	return nt

static func noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1337
		_noise.frequency = 0.35
		_noise.fractal_octaves = 2
	return _noise

# ---------------------------------------------------------------- colori per vertice
func _key(k: String) -> String:
	if burnt and k != "glass" and k != "light":
		return "burnt"
	if k == "faction":
		return "faction:" + fac.to_html(false)
	if k == "paint":
		match style:
			0:
				if camo > 0.0:
					return "paint_pixel_fine" if camo >= 2.0 else "paint_pixel"
			1:
				if camo > 0.0 and camo < 2.0:
					return "paint_fo"
			2:
				if camo > 0.0 and camo < 2.0:
					return "paint_cp"
			3:
				if camo < 2.0:
					return "paint_rust"
		if camo <= 0.0:
			return "paint_plain"
		if camo >= 2.0:
			return "paint_fine"
	return k

func _vcol(k: String, c: Color, p: Vector3) -> Color:
	if burnt:
		var n := noise().get_noise_3d(p.x * 2.1, p.y * 2.1, p.z * 2.1)
		var g := 0.07 + 0.05 * n
		var rust := clampf(n * 2.0 - 0.3, 0.0, 1.0)
		var base := Color(g, g * 0.95, g * 0.9).lerp(Color(0.24, 0.12, 0.06), rust * 0.6)
		if k == "glass":
			return Color(0.02, 0.02, 0.02)
		return base
	var out := c
	if k == "paint":
		out = out * (0.93 + 0.14 * noise().get_noise_3d(p.x * 3.0, p.y * 3.0, p.z * 3.0))
	if dirt_h > 0.0 and (k == "paint" or k == "rubber" or k == "metal" or k == "track"):
		var d := clampf(1.0 - p.y / dirt_h, 0.0, 1.0)
		out = out.lerp(MUD, d * 0.55)
	out.a = 1.0
	return out

func _arr(k: String) -> Array:
	var kk := _key(k)
	if rig and not burnt:
		kk += "#rig"
	if not _s.has(kk):
		_s[kk] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		if (rig and not burnt) or kk.begins_with("wheel_"):
			_s[kk].append(PackedVector2Array())
			_s[kk].append(PackedVector2Array())
	return _s[kk]

## UV/UV2 dei vertici animati: soldati (posizione + imbardata/osso) o ruote (centro dell'asse + raggio).
func _rig3(A: Array) -> void:
	if A.size() < 5:
		return
	var u1 := _rig_uv
	var u2 := Vector2(_rig_yaw, float(rig_bone + 16 * _rig_idx))
	if not rig:
		u1 = _wuv
		u2 = _wuv2
	for i in 3:
		A[3].append(u1)
		A[4].append(u2)

# ---------------------------------------------------------------- triangoli di base (coordinate già nel modello)
func _emit(k: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	var A := _arr(k)
	var fn := (c - a).cross(b - a)
	if fn.dot(na + nb + nc) < 0.0:
		var tmp := b; b = c; c = tmp
		var tn := nb; nb = nc; nc = tn
	A[0].append(a); A[0].append(b); A[0].append(c)
	A[1].append(na); A[1].append(nb); A[1].append(nc)
	A[2].append(_vcol(k, col, a)); A[2].append(_vcol(k, col, b)); A[2].append(_vcol(k, col, c))
	_rig3(A)

## Poligono convesso piatto (punti locali, in ordine lungo il bordo); `inside` = un punto interno al solido.
func face(k: String, pts: Array, col: Color, inside: Vector3) -> void:
	if pts.size() < 3:
		return
	var w: Array = []
	for p in pts:
		w.append(t * (p as Vector3))
	var ins: Vector3 = t * inside
	var n := Vector3.ZERO
	for i in range(1, w.size() - 1):
		n += ((w[i + 1] as Vector3) - (w[0] as Vector3)).cross((w[i] as Vector3) - (w[0] as Vector3))
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((w[0] as Vector3) - ins) < 0.0:
		n = -n
	for i in range(1, w.size() - 1):
		_emit(k, w[0], w[i], w[i + 1], n, n, n, col)

func tri_s(k: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	var bs := t.basis
	_emit(k, t * a, t * b, t * c, (bs * na).normalized(), (bs * nb).normalized(), (bs * nc).normalized(), col)

## Triangolo con normali e colori per vertice (sfumature morbide, es. chiome degli alberi).
func tri_c(k: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var A := _arr(k)
	var bs := t.basis
	var pa := t * a
	var pb := t * b
	var pc := t * c
	na = (bs * na).normalized()
	nb = (bs * nb).normalized()
	nc = (bs * nc).normalized()
	var fn := (pc - pa).cross(pb - pa)
	if fn.dot(na + nb + nc) < 0.0:
		var tp := pb; pb = pc; pc = tp
		var tn := nb; nb = nc; nc = tn
		var tc := cb; cb = cc; cc = tc
	A[0].append(pa); A[0].append(pb); A[0].append(pc)
	A[1].append(na); A[1].append(nb); A[1].append(nc)
	A[2].append(_vcol(k, ca, pa)); A[2].append(_vcol(k, cb, pb)); A[2].append(_vcol(k, cc, pc))
	_rig3(A)

# ---------------------------------------------------------------- solidi
## Esaedro da 8 vertici: 0..3 base (-x-z, +x-z, +x+z, -x+z), 4..7 sopra nello stesso ordine.
func hexa(k: String, v: Array, col: Color) -> void:
	var c := Vector3.ZERO
	for p in v:
		c += p
	c /= 8.0
	var F := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for f in F:
		face(k, [v[f[0]], v[f[1]], v[f[2]], v[f[3]]], col, c)

## Scatola centrata in `pos`, con smusso `bev` sugli spigoli (0 = spigoli vivi) e rotazione `rot`.
func box(k: String, size: Vector3, pos: Vector3, col: Color, bev: float = 0.0, rot: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var tr := Transform3D(rot, pos)
	if bev <= 0.0:
		var v: Array = []
		for p in [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
				Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]:
			v.append(tr * p)
		hexa(k, v, col)
		return
	var c := minf(bev, minf(h.x, minf(h.y, h.z)) * 0.45)
	var P := {}
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				P[Vector3i(sx, sy, sz) * 1] = [
					tr * Vector3(sx * h.x, sy * (h.y - c), sz * (h.z - c)),
					tr * Vector3(sx * (h.x - c), sy * h.y, sz * (h.z - c)),
					tr * Vector3(sx * (h.x - c), sy * (h.y - c), sz * h.z)]
	var ctr := tr * Vector3.ZERO
	for s in [-1, 1]:
		face(k, [P[Vector3i(s, -1, -1)][0], P[Vector3i(s, 1, -1)][0], P[Vector3i(s, 1, 1)][0], P[Vector3i(s, -1, 1)][0]], col, ctr)
		face(k, [P[Vector3i(-1, s, -1)][1], P[Vector3i(1, s, -1)][1], P[Vector3i(1, s, 1)][1], P[Vector3i(-1, s, 1)][1]], col, ctr)
		face(k, [P[Vector3i(-1, -1, s)][2], P[Vector3i(1, -1, s)][2], P[Vector3i(1, 1, s)][2], P[Vector3i(-1, 1, s)][2]], col, ctr)
	for a in [-1, 1]:
		for b in [-1, 1]:
			# spigoli lungo X (tra facce Y e Z), lungo Y (tra X e Z), lungo Z (tra X e Y)
			face(k, [P[Vector3i(-1, a, b)][1], P[Vector3i(1, a, b)][1], P[Vector3i(1, a, b)][2], P[Vector3i(-1, a, b)][2]], col, ctr)
			face(k, [P[Vector3i(a, -1, b)][0], P[Vector3i(a, 1, b)][0], P[Vector3i(a, 1, b)][2], P[Vector3i(a, -1, b)][2]], col, ctr)
			face(k, [P[Vector3i(a, b, -1)][0], P[Vector3i(a, b, 1)][0], P[Vector3i(a, b, 1)][1], P[Vector3i(a, b, -1)][1]], col, ctr)
	for key in P.keys():
		face(k, P[key], col, ctr)

## Profilo laterale convesso (z, y) estruso lungo X da x0 a x1.
func prism_x(k: String, prof: Array, x0: float, x1: float, col: Color) -> void:
	var c2 := Vector2.ZERO
	for p in prof:
		c2 += p
	c2 /= float(prof.size())
	var ins := Vector3((x0 + x1) * 0.5, c2.y, c2.x)
	var a0: Array = []
	var a1: Array = []
	for p in prof:
		a0.append(Vector3(x0, p.y, p.x))
		a1.append(Vector3(x1, p.y, p.x))
	face(k, a0, col, ins)
	face(k, a1, col, ins)
	for i in prof.size():
		var j := (i + 1) % prof.size()
		face(k, [a0[i], a1[i], a1[j], a0[j]], col, ins)

## Pianta convessa (x, z) estrusa lungo Y da y0 a y1; la sommità è scalata di `ts` e spostata di `toff` (x,z).
func prism_y(k: String, prof: Array, y0: float, y1: float, col: Color, ts: float = 1.0, toff: Vector2 = Vector2.ZERO) -> void:
	var c2 := Vector2.ZERO
	for p in prof:
		c2 += p
	c2 /= float(prof.size())
	var ins := Vector3(c2.x + toff.x * 0.5, (y0 + y1) * 0.5, c2.y + toff.y * 0.5)
	var a0: Array = []
	var a1: Array = []
	for p in prof:
		a0.append(Vector3(p.x, y0, p.y))
		var q: Vector2 = c2 + (p - c2) * ts + toff
		a1.append(Vector3(q.x, y1, q.y))
	face(k, a0, col, ins)
	face(k, a1, col, ins)
	for i in prof.size():
		var j := (i + 1) % prof.size()
		face(k, [a0[i], a0[j], a1[j], a1[i]], col, ins)

## Cilindro/tronco di cono lungo Y locale (centrato), trasformato da `tr`.
func cyl(k: String, r0: float, r1: float, h: float, seg: int, tr: Transform3D, col: Color, caps: bool = true, smooth: bool = true) -> void:
	var y0 := -h * 0.5
	var y1 := h * 0.5
	var slope := (r0 - r1) / maxf(h, 0.0001)
	var top: Array = []
	var bot: Array = []
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var d := Vector3(cos(a), 0, sin(a))
		bot.append(d * r0 + Vector3(0, y0, 0))
		top.append(d * r1 + Vector3(0, y1, 0))
	var bs := tr.basis
	for i in seg:
		var j := (i + 1) % seg
		if smooth:
			var a := TAU * float(i) / float(seg)
			var b := TAU * float(j) / float(seg)
			var ni := (bs * Vector3(cos(a), slope, sin(a))).normalized()
			var nj := (bs * Vector3(cos(b), slope, sin(b))).normalized()
			var p0: Vector3 = t * (tr * (bot[i] as Vector3))
			var p1: Vector3 = t * (tr * (bot[j] as Vector3))
			var p2: Vector3 = t * (tr * (top[j] as Vector3))
			var p3: Vector3 = t * (tr * (top[i] as Vector3))
			var tb := t.basis
			ni = (tb * ni).normalized()
			nj = (tb * nj).normalized()
			if r0 > 0.0001 or r1 > 0.0001:
				_emit(k, p0, p1, p2, ni, nj, nj, col)
				_emit(k, p0, p2, p3, ni, nj, ni, col)
		else:
			face(k, [tr * (bot[i] as Vector3), tr * (bot[j] as Vector3), tr * (top[j] as Vector3), tr * (top[i] as Vector3)], col, tr * Vector3.ZERO)
	if caps:
		var inside := tr * Vector3.ZERO
		var bw: Array = []
		var tw: Array = []
		for p in bot:
			bw.append(tr * (p as Vector3))
		for p in top:
			tw.append(tr * (p as Vector3))
		if r0 > 0.001:
			face(k, bw, col, inside)
		if r1 > 0.001:
			face(k, tw, col, inside)

static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

## Cilindro da `a` a `b`.
func cyl_ab(k: String, a: Vector3, b: Vector3, r0: float, r1: float, seg: int, col: Color, caps: bool = true) -> void:
	var d := b - a
	if d.length() < 0.0001:
		return
	cyl(k, r0, r1, d.length(), seg, Transform3D(basis_y(d), (a + b) * 0.5), col, caps)

## Ellissoide (o semi-ellissoide superiore con `hemi`) con normali lisce.
func sphere(k: String, pos: Vector3, rad: Vector3, seg: int, rings: int, col: Color, hemi: bool = false, rot: Basis = Basis.IDENTITY) -> void:
	var lat0 := 0.0 if hemi else -PI * 0.5
	var grid: Array = []
	var nrm: Array = []
	for r in rings + 1:
		var lat := lerpf(lat0, PI * 0.5, float(r) / float(rings))
		var row: Array = []
		var nrow: Array = []
		for s in seg:
			var lo := TAU * float(s) / float(seg)
			var u := Vector3(cos(lat) * cos(lo), sin(lat), cos(lat) * sin(lo))
			row.append(rot * (u * rad) + pos)
			nrow.append(rot * Vector3(u.x / rad.x, u.y / rad.y, u.z / rad.z))
		grid.append(row)
		nrm.append(nrow)
	for r in rings:
		for s in seg:
			var s2 := (s + 1) % seg
			tri_s(k, grid[r][s], grid[r][s2], grid[r + 1][s2], nrm[r][s], nrm[r][s2], nrm[r + 1][s2], col)
			tri_s(k, grid[r][s], grid[r + 1][s2], grid[r + 1][s], nrm[r][s], nrm[r + 1][s2], nrm[r + 1][s], col)
	if hemi:
		face(k, grid[0], col, pos + rot * Vector3(0, rad.y * 0.5, 0))

## Loft lungo Z di sezioni super-ellittiche: ogni sezione [z, cy, semi-larghezza, semi-altezza, esponente(2=ellisse, >2 squadrata)].
func loft(k: String, secs: Array, seg: int, col: Color, caps: bool = true) -> void:
	var G: Array = []
	for s in secs:
		var n: float = s[4] if s.size() > 4 else 2.0
		var row: Array = []
		for i in seg:
			var a := TAU * float(i) / float(seg)
			var ca := cos(a)
			var sa := sin(a)
			var x := signf(ca) * pow(absf(ca), 2.0 / n) * float(s[2])
			var y := signf(sa) * pow(absf(sa), 2.0 / n) * float(s[3])
			row.append(Vector3(x, float(s[1]) + y, float(s[0])))
		G.append(row)
	var N: Array = []
	var ns := secs.size()
	for r in ns:
		var nrow: Array = []
		for i in seg:
			var pa: Vector3 = G[maxi(r - 1, 0)][i]
			var pb: Vector3 = G[mini(r + 1, ns - 1)][i]
			var qa: Vector3 = G[r][(i - 1 + seg) % seg]
			var qb: Vector3 = G[r][(i + 1) % seg]
			var nn := (pb - pa).cross(qb - qa)
			var axis := Vector3(0, float(secs[r][1]), float(secs[r][0]))
			if nn.dot((G[r][i] as Vector3) - axis) < 0.0:
				nn = -nn
			if nn.length_squared() < 1e-10:
				nn = (G[r][i] as Vector3) - axis
			nrow.append(nn.normalized())
		N.append(nrow)
	for r in ns - 1:
		for i in seg:
			var j := (i + 1) % seg
			tri_s(k, G[r][i], G[r][j], G[r + 1][j], N[r][i], N[r][j], N[r + 1][j], col)
			tri_s(k, G[r][i], G[r + 1][j], G[r + 1][i], N[r][i], N[r + 1][j], N[r + 1][i], col)
	if caps:
		if float(secs[0][2]) > 0.01:
			face(k, G[0], col, Vector3(0, float(secs[0][1]), float(secs[0][0]) + signf(float(secs[1][0]) - float(secs[0][0])) * 0.01))
		var l := ns - 1
		if float(secs[l][2]) > 0.01:
			face(k, G[l], col, Vector3(0, float(secs[l][1]), float(secs[l][0]) + signf(float(secs[l - 1][0]) - float(secs[l][0])) * 0.01))

## Lastra sottile: poligono convesso nel piano XZ (ali, derive) con spessore `th` lungo Y.
func plate(k: String, prof: Array, th: float, col: Color, tr: Transform3D = Transform3D.IDENTITY) -> void:
	var old := t
	t = t * tr
	prism_y(k, prof, -th * 0.5, th * 0.5, col)
	t = old

# ---------------------------------------------------------------- uscita
func tri_count() -> int:
	var n := 0
	for k in _s:
		n += (_s[k][0] as PackedVector3Array).size() / 3
	return n

func commit() -> ArrayMesh:
	var m := ArrayMesh.new()
	var keys := _s.keys()
	keys.sort()
	for k in keys:
		var A: Array = _s[k]
		if (A[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = A[0]
		arrays[Mesh.ARRAY_NORMAL] = A[1]
		arrays[Mesh.ARRAY_COLOR] = A[2]
		if A.size() >= 5:
			arrays[Mesh.ARRAY_TEX_UV] = A[3]
			arrays[Mesh.ARRAY_TEX_UV2] = A[4]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(m.get_surface_count() - 1, mat(k))
	if rig and not burnt and m.get_surface_count() > 0:
		# le pose animate (in ginocchio, a terra, caduta) escono dalla sagoma a riposo
		m.custom_aabb = m.get_aabb().grow(1.8)
		m.set_meta("rig", true)
	if not marks.is_empty():
		m.set_meta("marks", marks.duplicate())
	return m

## Atlante dei numeri tattici e degli stemmi (240×64): riga alta = cifre 0..9 (bianche con bordo nero), riga bassa = stemmi
## (0 AAN stella in cerchio, 1 FO triangolo, 2 CP cerchio a onde, 3 UL rombo con barra, 4 generico quadrato), bianchi: li tinge lo shader.
static func marks_tex() -> Texture2D:
	if _mats.has("_marks_tex"):
		return _mats["_marks_tex"]
	const FONT := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
		"111100111101111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]
	var W := 240
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var on := []
	on.resize(W * H)
	on.fill(false)
	for d in 10:
		var f: String = FONT[d]
		for r in 5:
			for c in 3:
				if f[r * 3 + c] == "1":
					for yy in 6:
						for xx in 6:
							on[(3 + r * 5 + yy) * W + d * 24 + 3 + c * 5 + xx] = true
	# bordo nero di 1 px attorno alle cifre
	for y in 32:
		for x in W:
			if on[y * W + x]:
				img.set_pixel(x, y, Color(0.95, 0.95, 0.9, 1))
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and xx < W and yy >= 0 and yy < 32 and on[yy * W + xx]:
						near = true
			if near:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.02, 1))
	for e in 5:
		for y in 32:
			for x in 24:
				var px := float(x) - 11.5
				var py := float(y) - 15.5
				var ax := absf(px)
				var ay := absf(py)
				var rr := sqrt(px * px + py * py)
				var inside := false
				match e:
					0: inside = (rr >= 8.5 and rr <= 10.5) or (ax + ay <= 7.5 and ax * ay <= 9.0)
					1: inside = py <= 8.0 and py >= -9.0 and ax <= (py + 9.0) * 0.62 and not (py <= 4.0 and py >= -3.0 and ax <= (py + 3.0) * 0.45)
					2: inside = rr <= 10.5 and not (absf(py - 3.0) < 1.4 or absf(py + 3.0) < 1.4) and not (rr <= 10.5 and ay < 1.2 and rr > 4.0)
					3: inside = (ax + ay <= 11.0 and ax + ay >= 8.5) or (ax <= 1.6 and ay <= 7.0)
					_: inside = ax <= 9.5 and ay <= 9.5 and not (ax <= 7.0 and ay <= 7.0)
				if inside:
					img.set_pixel(e * 24 + x, 32 + y, Color(1, 1, 1, 1))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats["_marks_tex"] = tex
	return tex

## Materiale dei numeri tattici per stemma (0..3 fazioni, 4 generico).
static func marks_mat(emblem: int) -> ShaderMaterial:
	var k := "_marks_mat%d" % emblem
	if _mats.has(k):
		return _mats[k]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/models/marks.gdshader")
	sm.set_shader_parameter("atlas", marks_tex())
	sm.set_shader_parameter("emblem", float(clampi(emblem, 0, 4)))
	_mats[k] = sm
	return sm

## Materiale dei soldati animati: stessi parametri della vernice/del materiale di base, con lo shader dello scheletro.
static func _rig_mat(base: String) -> ShaderMaterial:
	var sm: ShaderMaterial
	if base.begins_with("paint"):
		sm = _paint_mat(base)
	else:
		sm = ShaderMaterial.new()
		sm.set_shader_parameter("use_camo", false)
		sm.set_shader_parameter("wear", 0.0)
		var rough := 0.85
		var metal := 0.0
		var spec := 0.5
		if base.begins_with("faction:"):
			var c := Color(base.substr(8))
			rough = 0.62
			sm.set_shader_parameter("emit", c)
			sm.set_shader_parameter("emit_k", 0.14)
		else:
			match base:
				"metal":
					rough = 0.46; metal = 0.75; spec = 0.5
				"rubber":
					rough = 0.96; spec = 0.2
				"matte":
					rough = 0.92; spec = 0.3
		sm.set_shader_parameter("base_rough", rough)
		sm.set_shader_parameter("base_metal", metal)
		sm.set_shader_parameter("spec", spec)
	sm.shader = _soldier_shader(base.begins_with("paint_pixel"))
	return sm

static func _soldier_shader(pixel: bool) -> Shader:
	var k := "_shader_soldier_px" if pixel else "_shader_soldier"
	if _mats.has(k):
		return _mats[k]
	var sh: Shader = load("res://scripts/models/soldier.gdshader")
	if pixel:
		var s2 := Shader.new()
		s2.code = sh.code.replace("source_color, filter_linear_mipmap_anisotropic, repeat_enable", "source_color, filter_nearest_mipmap, repeat_enable")
		sh = s2
	_mats[k] = sh
	return sh
