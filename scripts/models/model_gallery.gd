extends Node3D
## Galleria di collaudo dei modelli ed effetti (Agente F).
## Più scatti in un solo avvio: --multi=props,rocks,buildings --prefix=docs/screens/models2_ --each=45 (salva <prefix><demo>.png).
## Argomenti: --demo=units|props|trees|rocks|buildings|buildings2|vfx|night|damage|close|mini|wreck|ships|shipclose|shipstern|shipmini|transport|heli|one
##   (--kind=tank per "one", --yaw=gradi, --dist=m, --fac=N), --stats (stampa triangoli).
##   FASE 4: --demo=factions (tutti i tipi per le 4 fazioni + generico, in righe), --demo=faction --fac=N (una fazione da vicino,
##   --view=ground|air per metà della fila; --mini per le pedine).

const NAMES := {"inf": "Fanteria", "tank": "Carro armato", "art": "Artiglieria", "aa": "Contraerea", "heli": "Elicottero",
	"jet": "Caccia-bombardiere", "drone": "Drone", "bunker": "Bunker", "truck": "Camion"}
const ORDER := ["inf", "truck", "tank", "art", "aa", "bunker", "heli", "drone", "jet"]

var demo := "units"
var cam: Camera3D
var spinners: Array = []
var t := 0.0
var fx_t := 0.0
var fx_i := 0
var fx_origin := Vector3(0, 0, -70)
const SEA := Vector3(700, 0, 0)
var movers: Array = []   # [nodo, velocità m/s]
var multi: Array = []
var sun: DirectionalLight3D
var envr: Environment
var multi_i := -1
var multi_wait := 0

var perf_n := 0
var perf_cpu := 0.0
var perf_gpu := 0.0

func _ready() -> void:
	demo = Shot.arg("demo", "units")
	if Shot.has_arg("legacy"):
		ModelKit.use_shaders = false
	if Shot.has_arg("perf"):
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_env()
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 2000
	add_child(cam)
	if demo in ["factions", "faction"]:
		_factions()
		return
	if demo == "confronto":
		_confronto()
		return
	if demo == "crowd":
		_crowd()
		return
	if demo == "anim":
		_anim_demo()
		return
	if demo == "soldiers":
		_sol_next()
		return
	if demo in ["lineup", "blast"]:
		_lineup_demo()
		return
	var c0 := Data.faction_color(0)
	var c1 := Data.faction_color(1)
	var x := 0.0
	var xs := {}
	for k in ORDER:
		var w := 22.0 if k == "jet" else (16.0 if k == "heli" else 12.0)
		xs[k] = x + w * 0.5
		x += w
	var off := -x * 0.5
	for k in ORDER:
		var px: float = xs[k] + off
		for row in 2:
			var m := UnitModels.build(k, c0 if row == 0 else c1, 0)
			var air := bool(m.get_meta("air", false))
			m.position = Vector3(px, (2.5 if k in ["jet", "drone"] else 0.0), row * 24.0)
			m.rotation.y = deg_to_rad(-35.0)
			add_child(m)
			_collect(m)
			if k == "art":
				(m.find_child("Barrel", true, false) as Node3D).rotation.x = deg_to_rad(22)
			if k == "aa":
				(m.find_child("Barrel", true, false) as Node3D).rotation.x = deg_to_rad(30)
			if row == 0:
				var lb := Label3D.new()
				lb.text = NAMES[k]
				lb.font_size = 64
				lb.pixel_size = 0.02
				lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lb.position = Vector3(px, 0.3, -9.0)
				lb.modulate = Color(1, 1, 0.9)
				lb.outline_size = 12
				add_child(lb)
			if Shot.has_arg("stats") and row == 0:
				print("[gallery] %s tris lod0=%d lod1=%d lod2=%d" % [k, int(m.get_meta("tris")), int(UnitModels.build(k, c0, 1).get_meta("tris")), int(UnitModels.build(k, c0, 2).get_meta("tris"))])
	# props: alberi (tutti i tipi), stagioni, rocce per stile
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pz := 90.0
	var kinds: Array = Props.TREE_KINDS
	for i in kinds.size():
		var tr := Props.tree(kinds[i], rng)
		tr.position = Vector3(-70 + i * 9, 0, pz)
		add_child(tr)
	var seasons := ["autumn", "snow", "dry"]
	for j in seasons.size():
		for i in 3:
			var tr := Props.tree(["broadleaf", "pine", "birch"][i], rng, seasons[j])
			tr.position = Vector3(-70 + j * 27 + i * 8, 0, pz + 16)
			add_child(tr)
	var styles := ["rock", "desert", "mountain", "arctic"]
	for j in styles.size():
		for i in 2:
			var r := MeshInstance3D.new()
			r.mesh = Props.rock_mesh(rng, styles[j])
			r.position = Vector3(-70 + j * 12 + i * 5.5, 0, pz - 10)
			r.rotation.y = rng.randf() * TAU
			r.scale = Vector3.ONE * (1.4 if i == 0 else 1.0)
			add_child(r)
	# strada di edifici
	var bz := 170.0
	var bdefs := [["block", Vector3(18, 22, 14)], ["office", Vector3(16, 34, 16)], ["house", Vector3(9, 7, 11)], ["garden", Vector3(20, 7, 22)],
		["industrial", Vector3(26, 8, 20)], ["shed", Vector3(22, 9, 16)], ["station", Vector3(26, 6, 22)], ["ruin", Vector3(16, 10, 14)]]
	var bx := -110.0
	var b3: Node3D = null
	for d in bdefs:
		var sz: Vector3 = d[1]
		var bd := Props.building(sz, d[0], rng)
		bd.position = Vector3(bx + sz.x * 0.5, 0, bz)
		add_child(bd)
		if d[0] == "industrial":
			b3 = bd
		if Shot.has_arg("stats"):
			print("[gallery] building %s tris=%d" % [d[0], int(bd.get_meta("tris"))])
		bx += sz.x + 8.0
	var road := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(260, 10)
	road.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.17, 0.17, 0.17)
	rmat.roughness = 0.9
	road.material_override = rmat
	road.position = Vector3(0, 0.03, bz - 18)
	add_child(road)
	var cr := Props.crater()
	cr.position = Vector3(-30, 0.02, pz + 30)
	add_child(cr)
	for i in 3:
		var wk := UnitModels.wreck(["tank", "heli", "truck"][i])
		wk.position = Vector3(-15 + i * 13, 0, pz + 30)
		wk.rotation.y = 0.6 * i
		add_child(wk)
	if Shot.has_arg("stats"):
		for k in kinds:
			print("[gallery] tree %s tris=%d" % [k, int(Props.tree_mesh(k).get_meta("tris"))])
		print("[gallery] rock tris=%d" % int(Props.rock_mesh(rng).get_meta("tris")))
	# miniature
	for i in ORDER.size():
		var mn := UnitModels.miniature(ORDER[i], Data.faction_color(i % 4))
		mn.position = Vector3(-12 + i * 3.0, 0, 45)
		mn.rotation.y = -0.6
		add_child(mn)
		_collect(mn)
	# zona effetti: carri che sparano a un bersaglio
	for i in 3:
		var m := UnitModels.build("tank", c1, 1)
		m.position = fx_origin + Vector3(-20 + i * 9, 0, 25)
		m.rotation.y = PI
		add_child(m)
	var wr := UnitModels.wreck("tank")
	wr.position = fx_origin + Vector3(8, 0, -5)
	add_child(wr)
	for sm in [Vfx.fire(self, fx_origin + Vector3(8, 1.2, -5), 1.0), Vfx.smoke(self, b3.position + Vector3(-6, 8, 0), 600.0)]:
		for p in sm.find_children("*", "CPUParticles3D", true, false):
			(p as CPUParticles3D).preprocess = 6.0
	# stati di danno: 0, 0.3, 0.6, 0.9
	for i in 4:
		var m := UnitModels.build("tank", c0, 1)
		m.position = fx_origin + Vector3(26 + i * 9, 0, 10)
		m.rotation.y = 0.4
		add_child(m)
		UnitModels.set_damage(m, [0.0, 0.3, 0.6, 0.9][i])
		for p in m.find_children("*", "CPUParticles3D", true, false):
			(p as CPUParticles3D).preprocess = 5.0
	if demo == "vfx":
		# scena "congelata" a metà azione: esplosioni a diversi stadi
		for i in 4:
			var e := Vfx.explosion(self, fx_origin + Vector3(-12 + i * 8, 0, -4 + (i % 2) * 6), 0.8 + 0.4 * i)
			for p in e.find_children("*", "CPUParticles3D", true, false):
				(p as CPUParticles3D).preprocess = 0.06 + 0.12 * i
	_ships()
	_camera()

## Zona navale: mare, cacciatorpediniere e trasporto in navigazione con scia, miniature navali.
func _ships() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 900)
	w.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.05, 0.11, 0.14)
	wm.roughness = 0.12
	wm.metallic = 0.25
	wm.metallic_specular = 0.7
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.03
	nz.fractal_octaves = 4
	nt.noise = nz
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	wm.normal_enabled = true
	wm.normal_texture = nt
	wm.normal_scale = 0.6
	wm.uv1_scale = Vector3(40, 60, 1)
	w.material_override = wm
	w.position = SEA
	add_child(w)
	var c0 := Data.faction_color(0)
	var c2 := Data.faction_color(2)
	var ships := [["ship", c0, Vector3(0, 0, 0)], ["transport", c2, Vector3(-75, 0, 140)], ["ship", Data.faction_color(1), Vector3(70, 0, 200)]]
	for e in ships:
		var m := UnitModels.build(e[0], e[1], 0)
		m.position = SEA + (e[2] as Vector3)
		add_child(m)
		_collect(m)
		var L: float = m.get_meta("length", 100.0)
		Vfx.wake(m, Vector3(0, 0.15, L * 0.5), Vector3(0, 0, -1))
		movers.append([m, 9.0])
	for i in 2:
		var mn := UnitModels.miniature(["ship", "transport"][i], Data.faction_color(i * 2))
		mn.position = SEA + Vector3(-30 + i * 6, 0.3, -150)
		mn.rotation.y = -0.5
		add_child(mn)
	if Shot.has_arg("stats"):
		for k in ["ship", "transport"]:
			print("[gallery] %s tris lod0=%d lod1=%d lod2=%d" % [k, int(UnitModels.build(k, c0, 0).get_meta("tris")), int(UnitModels.build(k, c0, 1).get_meta("tris")), int(UnitModels.build(k, c0, 2).get_meta("tris"))])

## Notte 3 — confronto ravvicinato tra modello in codice (fila dietro) e modello esterno (fila davanti):
## --demo=confronto [--pairs=tank:0,tank:1,tank:3,heli:0,jet:1] [--dist=m] [--yaw=gradi] [--el=gradi]
func _confronto() -> void:
	var pairs := Shot.arg("pairs", "tank:0,tank:1,tank:3").split(",")
	var gap := float(Shot.arg("gap", "11"))
	var n := pairs.size()
	for i in n:
		var kv := String(pairs[i]).split(":")
		var k := String(kv[0])
		var f := int(kv[1]) if kv.size() > 1 else -1
		var col := Data.faction_color(f)
		for row in 2:
			UnitModels._ext_checked = true
			UnitModels.use_ext = row == 1
			var m := UnitModels.build(k, col, 0, f)
			m.position = Vector3(-(i - (n - 1) * 0.5) * gap, 0.0, 200.0 + (0.0 if row == 1 else gap * 0.95))
			m.rotation.y = deg_to_rad(float(Shot.arg("myaw", "-40")))
			add_child(m)
			_collect(m)
			if Shot.has_arg("stats"):
				print("[confronto] %s f%d %s tris %d L %.2f h %.2f" % [k, f, "esterno" if row == 1 else "codice", int(m.get_meta("tris", 0)), float(m.get_meta("length", 0.0)), float(m.get_meta("height", 0.0))])
	UnitModels.use_ext = true
	var d := float(Shot.arg("dist", str(n * gap * 0.62 + 8.0)))
	var el := deg_to_rad(float(Shot.arg("el", "30")))
	_look(Vector3(0, 0, 200.0 + gap * 0.4) + Vector3(0, sin(el), -cos(el)) * d, Vector3(0, 1.0, 200.0 + gap * 0.4))
	sun.directional_shadow_max_distance = 120

## Mezzi per fazione: righe = fazioni (AAN, FO, CP, UL, generico), colonne = tipi.
func _factions() -> void:
	var facs := [0, 1, 2, 3, -1]
	var one := demo == "faction"
	var fsel := int(Shot.arg("fac", "0"))
	if one:
		facs = [fsel]
	var order := ["inf", "truck", "tank", "art", "aa", "bunker", "heli", "drone", "jet"]
	var view := Shot.arg("view", "all")
	if view == "ground":
		order = ["inf", "truck", "tank", "art", "aa", "bunker"]
	elif view == "air":
		order = ["heli", "drone", "jet"]
	if Shot.has_arg("kinds"):
		order = Array(Shot.arg("kinds").split(","))
	var x := 0.0
	var xs := {}
	for k in order:
		var w := 21.0 if k == "jet" else (17.0 if k == "heli" else (11.0 if k == "bunker" else 9.5))
		xs[k] = x + w * 0.5
		x += w
	var off := -x * 0.5
	var mini := Shot.has_arg("mini")
	for r in facs.size():
		var f: int = facs[r]
		var col := Data.faction_color(f)
		for k in order:
			var m: Node3D
			if mini:
				m = UnitModels.miniature(k, col, f)
				m.scale = Vector3.ONE * 3.0
			else:
				m = UnitModels.build(k, col, int(Shot.arg("lod", "0")), f)
			m.position = Vector3(-(float(xs[k]) + off), (3.0 if k in ["jet", "drone", "heli"] and not mini else 0.0), r * 17.0)
			m.rotation.y = deg_to_rad(float(Shot.arg("yaw", "-35")))
			add_child(m)
			_collect(m)
			var bar := m.find_child("Barrel", true, false) as Node3D
			if bar and k in ["art", "aa"]:
				bar.rotation.x = deg_to_rad(25 if k == "art" else 35)
			if Shot.has_arg("stats"):
				print("[gallery] fac %d %-7s tris %5d" % [f, k, int(m.get_meta("tris", 0))])
		var lb := Label3D.new()
		lb.text = ["AAN", "FO", "CP", "UL"][f] if f >= 0 else "Generico"
		lb.font_size = 72
		lb.pixel_size = 0.03
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = Vector3(-off + 5.0, 1.5, r * 17.0)
		lb.modulate = col.lightened(0.3)
		lb.outline_size = 14
		add_child(lb)
	var span := x
	if one:
		var d := maxf(span * 0.62, 11.0)
		_look(Vector3(d * 0.1, d * 0.36, -d * 0.95), Vector3(0, 1.0, 0))
	else:
		var d := maxf(span, 100.0) * 0.62 + 14.0
		_look(Vector3(0, d * 0.75, -d * 0.55), Vector3(0, -2, 32))
	sun.directional_shadow_max_distance = 320

## Prova di carico: 120 mezzi LOD0 delle 4 fazioni (carri, fanteria, artiglieria, AA, camion, elicotteri) e 300 alberi.
func _crowd() -> void:
	var kinds := ["tank", "inf", "tank", "art", "aa", "truck", "inf", "heli"]
	var i := 0
	for r in 10:
		for cidx in 12:
			var f := (r + cidx) % 4
			var k: String = kinds[(r * 12 + cidx) % kinds.size()]
			var m := UnitModels.build(k, Data.faction_color(f), 0 if r < 5 else 1, f)
			m.position = Vector3(-66 + cidx * 12.0, 3.0 if k == "heli" else 0.0, -20 + r * 11.0)
			m.rotation.y = 0.3 * float(i % 7)
			add_child(m)
			_collect(m)
			i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for j in 300:
		var tr := Props.tree(Props.TREE_KINDS[j % Props.TREE_KINDS.size()], rng)
		tr.position = Vector3(rng.randf_range(-160, 160), 0, rng.randf_range(100, 260))
		add_child(tr)
	_look(Vector3(0, 70, -95), Vector3(0, 0, 40))
	sun.directional_shadow_max_distance = 260

func _collect(m: Node) -> void:
	for n in ["Rotor", "TailRotor", "Prop", "Radar"]:
		var s := m.find_child(n, true, false)
		if s:
			spinners.append([s, n])

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.33, 0.5, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sm.ground_bottom_color = Color(0.2, 0.19, 0.16)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.62)
	sm.sun_angle_max = 20
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_light_color = Color(0.7, 0.74, 0.8)
	env.fog_aerial_perspective = 0.5
	we.environment = env
	envr = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -40, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	pm.subdivide_width = 1
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.02
	nt.noise = nz
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var gr := Gradient.new()
	gr.set_color(0, Color(0.27, 0.29, 0.17))
	gr.set_color(1, Color(0.4, 0.37, 0.25))
	nt.color_ramp = gr
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(30, 30, 1)
	gm.roughness = 0.95
	g.material_override = gm
	add_child(g)

func _camera() -> void:
	var yaw := float(Shot.arg("yaw", "0"))
	match demo:
		"props":
			_look(Vector3(-40, 22, 140), Vector3(-40, 4, 92))
		"trees":
			_look(Vector3(-42, 9, 135), Vector3(-42, 6, 100))
		"rocks":
			_look(Vector3(-50, 7, 66), Vector3(-50, 0.5, 80))
		"buildings":
			_look(Vector3(-30, 45, 95), Vector3(-30, 4, 170))
		"buildings2":
			_look(Vector3(60, 35, 115), Vector3(60, 4, 170))
		"damage":
			_look(fx_origin + Vector3(40, 12, 34), fx_origin + Vector3(39, 2, 10))
		"vfx":
			_look(fx_origin + Vector3(-5, 18, 55), fx_origin + Vector3(-4, 6, 0))
			Engine.time_scale = 1.0
		"close":
			_look(Vector3(-2, 7, -21), Vector3(10, 1.0, 6))
		"mini":
			_look(Vector3(0, 6, 36), Vector3(0, 0.5, 45))
		"ships":
			_look(SEA + Vector3(-95, 48, 70), SEA + Vector3(0, 6, 40))
		"shipclose":
			_look(SEA + Vector3(-45, 22, -60), SEA + Vector3(0, 8, -5))
		"shipstern":
			_look(SEA + Vector3(-40, 30, 110), SEA + Vector3(0, 2, 70))
		"transport":
			_look(SEA + Vector3(-185, 50, 75), SEA + Vector3(-75, 6, 110))
		"night":
			_look(fx_origin + Vector3(-5, 18, 55), fx_origin + Vector3(-4, 6, 0))
			sun.light_energy = 0.03
			envr.background_mode = Environment.BG_COLOR
			envr.background_color = Color(0.01, 0.015, 0.03)
			envr.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			envr.ambient_light_color = Color(0.15, 0.18, 0.3)
			envr.ambient_light_energy = 0.25
			envr.fog_light_color = Color(0.02, 0.03, 0.05)
		"heli":
			var hm := UnitModels.build("heli", Data.faction_color(1), 0)
			hm.position = Vector3(0, 0, 260)
			hm.rotation.y = deg_to_rad(30)
			add_child(hm)
			_look(Vector3(-9, 6, 247), Vector3(0, 1.8, 260))
		"shipmini":
			_look(SEA + Vector3(-27, 4, -143), SEA + Vector3(-27, 0.5, -150))
		"wreck":
			_look(Vector3(-2, 14, 122), Vector3(-2, 0, 104))
		"one":
			var k := Shot.arg("kind", "tank")
			var m := UnitModels.build(k, Data.faction_color(int(Shot.arg("fac", "0"))), int(Shot.arg("lod", "0")), int(Shot.arg("faction", "-1")))
			m.position = Vector3(0, 0, 200)
			m.rotation.y = deg_to_rad(yaw)
			add_child(m)
			_collect(m)
			var L: float = m.get_meta("length", 7.0)
			var d := float(Shot.arg("dist", str(L * 1.35)))
			var el := deg_to_rad(float(Shot.arg("el", "22")))
			_look(Vector3(0, 0, 200) + Vector3(-sin(0.7) * cos(el), sin(el), -cos(0.7) * cos(el)) * d + Vector3(0, 1.0, 0), Vector3(0, L * 0.12, 200))
		_:
			_look(Vector3(0, 40, -50), Vector3(0, 0, 14))

func _multi_step() -> void:
	if multi_i < 0:
		multi = Shot.arg("multi").split(",")
		multi_i = 0
		demo = multi[0]
		_camera()
		multi_wait = int(Shot.arg("each", "60"))
		return
	multi_wait -= 1
	if multi_wait > 0:
		return
	if multi_wait == 0:
		multi_wait = -1
		_save_multi()
		return

func _save_multi() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 960:
		img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path("res://") .path_join(Shot.arg("prefix", "docs/screens/models2_") + demo + ".png")
	img.save_png(path)
	print("[gallery] salvato ", path)
	multi_i += 1
	if multi_i >= multi.size():
		get_tree().quit()
		return
	demo = multi[multi_i]
	_camera()
	multi_wait = int(Shot.arg("each", "60"))

func _look(from: Vector3, to: Vector3) -> void:
	cam.position = from
	cam.look_at(to, Vector3.UP)

## Collaudo dell'animazione della fanteria (soldier.gdshader): --demo=anim [--faction=N] [--state=walk,run,kneel,fire,cover,die,idle]
## [--spd=m/s] [--dist=m] [--yaw=gradi]. Le squadre in marcia avanzano davvero (verifica che i piedi non scivolino).
var anim_sq: Array = []
var die_at := -99.0
func _anim_demo() -> void:
	var states := Shot.arg("state", "walk,run,fire,cover,die").split(",")
	var fac := int(Shot.arg("faction", "1"))
	for i in states.size():
		var m := UnitModels.build("inf", Data.faction_color(fac), int(Shot.arg("lod", "0")), fac)
		m.position = Vector3((i - (states.size() - 1) * 0.5) * 6.5, 0, 200)
		m.rotation.y = deg_to_rad(float(Shot.arg("myaw", "0")))
		add_child(m)
		var bd := m.get_node("Body") as GeometryInstance3D
		bd.set_instance_shader_parameter(&"seed", float(i) * 3.7)
		anim_sq.append([m, String(states[i]), bd, 0.0, m.position])
	var d := float(Shot.arg("dist", "17"))
	var yw := deg_to_rad(float(Shot.arg("yaw", "35")))
	_look(Vector3(sin(yw) * d, d * 0.42, 200 - cos(yw) * d), Vector3(0, 0.8, 200))

func _anim_update(delta: float) -> void:
	for sq in anim_sq:
		var m: Node3D = sq[0]
		var st: String = sq[1]
		var spd := 0.0
		if st == "walk": spd = float(Shot.arg("spd", "1.6"))
		elif st == "run": spd = float(Shot.arg("rspd", "4.5"))
		var ph: float = sq[3] + spd * delta * UnitModels.inf_step_rate(spd)
		sq[3] = ph
		if spd > 0.0:
			var fw := -m.basis.z   # avanti del modello (con la scala): i piedi devono restare fermi a terra
			m.position = (sq[4] as Vector3) + fw * (fmod(t * spd, 6.0) - 3.0)
		var a := Vector4.ZERO
		match st:
			"walk", "run": a = UnitModels.inf_anim_vec(ph, spd, 0.0, 0.0, false)
			"idle": a = UnitModels.inf_anim_vec(ph, 0.0, 0.0, 0.0, false)
			"aim": a = UnitModels.inf_anim_vec(ph, 0.0, 0.0, 1.0, true)
			"fire", "kneel": a = UnitModels.inf_anim_vec(ph, 0.0, 1.0, 1.0, st == "fire")
			"cover": a = UnitModels.inf_anim_vec(ph, 0.0, 1.0, 0.0, false)
			"die": a = UnitModels.inf_anim_vec(ph, 0.0, 0.0, 0.0, false, maxf(0.0, t - (die_at if die_at > -9.0 else float(Shot.arg("die_at", "0.5")))))
		(sq[2] as GeometryInstance3D).set_instance_shader_parameter(&"anim", a)

## Collaudo dei soldati, più scatti in un avvio: --demo=soldiers [--shots=fac0,fac1,...] [--prefix=docs/screens/soldiers_after_]
## [--each=frames] [--lod=N] [--stats]. Scatti: fac0..fac3, generic (squadra da vicino), lineup (tutte le fazioni), roles (di lato),
## walk / walk120 (marcia e corsa da vicino e a 120 m, scala di battaglia 1.3), kneel (in ginocchio, fuoco, riparo, caduta).
const SOL_SHOTS := ["face", "fac0", "fac1", "fac2", "fac3", "generic", "lineup", "roles", "walk", "walk120", "kneel"]
var sol_list: Array = []
var sol_i := -1
var sol_wait := 0
var sol_root: Node3D

func _sol_squad(fac: int, st: String, pos: Vector3, sc: float = 1.0, yaw: float = 0.0) -> void:
	var m := UnitModels.build("inf", Data.faction_color(fac), int(Shot.arg("lod", "0")), fac)
	m.position = pos
	m.scale = Vector3.ONE * sc
	m.rotation.y = yaw
	sol_root.add_child(m)
	var bd := m.get_node("Body") as GeometryInstance3D
	bd.set_instance_shader_parameter(&"seed", float(anim_sq.size()) * 3.7 + 1.3)
	anim_sq.append([m, st, bd, float(anim_sq.size()) * 1.1, pos])
	if Shot.has_arg("stats") and st == "idle":
		print("[soldiers] fac %d tris/squad %d (lod %s)" % [fac, int(m.get_meta("tris", 0)), Shot.arg("lod", "0")])

func _sol_cam(target: Vector3, d: float, yaw_deg: float, el_deg: float, fov: float = 50.0) -> void:
	var yw := deg_to_rad(yaw_deg)   # 0 = davanti ai soldati (guardano verso -Z)
	var el := deg_to_rad(el_deg)
	cam.fov = fov
	_look(target + Vector3(sin(yw) * cos(el), sin(el), -cos(yw) * cos(el)) * d, target)

func _sol_next() -> void:
	if sol_i < 0:
		sol_list = Array(Shot.arg("shots", ",".join(SOL_SHOTS)).split(","))
	sol_i += 1
	if sol_i >= sol_list.size():
		get_tree().quit()
		return
	if sol_root != null:
		sol_root.queue_free()
	anim_sq.clear()
	t = 0.0
	sol_root = Node3D.new()
	add_child(sol_root)
	var z0 := 200.0
	var sh: String = sol_list[sol_i]
	sun.directional_shadow_max_distance = 60
	match sh:
		"fac0", "fac1", "fac2", "fac3", "generic":
			var f := -1 if sh == "generic" else int(sh.substr(3))
			_sol_squad(f, "idle", Vector3(0, 0, z0))
			_sol_cam(Vector3(0, 0.9, z0 + 0.2), 6.2, 32, 12, 45)
		"lineup":
			var facs := [0, 1, 2, 3, -1]
			for i in 5:
				_sol_squad(facs[i], "idle", Vector3((i - 2) * 5.5, 0, z0))
			_sol_cam(Vector3(0, 0.8, z0), 17, 8, 14, 50)
		"face":
			_sol_squad(int(Shot.arg("fac", "1")), "idle", Vector3(0, 0, z0))
			_sol_squad(int(Shot.arg("fac2", "3")), "idle", Vector3(3.2, 0, z0 + 1.0))
			_sol_cam(Vector3(0.3, 1.45, z0 - 1.4), 2.6, 25, 4, 45)
		"roles":
			_sol_squad(int(Shot.arg("fac", "0")), "idle", Vector3(0, 0, z0))
			_sol_cam(Vector3(0, 0.9, z0 + 0.2), 6.0, 80, 8, 45)
		"walk":
			_sol_squad(1, "walk", Vector3(-3.2, 0, z0))
			_sol_squad(0, "run", Vector3(3.2, 0, z0))
			_sol_cam(Vector3(0, 0.9, z0), 11, 70, 10, 50)
		"walk120":
			for i in 4:
				_sol_squad(i, "run" if i % 2 == 0 else "walk", Vector3((i - 1.5) * 9.0, 0, z0), 1.3, PI * 0.5)
			sun.directional_shadow_max_distance = 220
			# fov 30 a 960×540 ≈ dimensione in pixel della battaglia a 1600×900 con fov 48
			_sol_cam(Vector3(0, 1.0, z0), float(Shot.arg("far", "120")), 20, 22, 30)
		"kneel":
			die_at = -1.2
			var sts := ["kneel", "fire", "cover", "die"]
			for i in 4:
				_sol_squad(i, sts[i], Vector3((i - 1.5) * 5.0, 0, z0))
			_sol_cam(Vector3(0, 0.6, z0), 13, 25, 16, 50)
	sol_wait = int(Shot.arg("each", "50"))

func _sol_step() -> void:
	sol_wait -= 1
	if sol_wait == 0:
		_sol_save()

func _sol_save() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 960:
		img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path("res://").path_join(Shot.arg("prefix", "docs/screens/soldiers_after_") + String(sol_list[sol_i]) + ".png")
	img.save_png(path)
	print("[soldiers] salvato ", path)
	_sol_next()

## Primo piano di mezzi in marcia: --demo=lineup --faction=N --kinds=tank,art,aa [--mud=0.5] [--spd=m/s] [--yaw=gradi] [--el=gradi]
## [--dist=m] [--deploy=1]: ruote e cingoli girano (UnitModels.set_motion), fango accumulato, numeri tattici, artiglieria piazzata.
## --demo=blast: lo stesso schieramento con il carro che spara ogni 1.3 s (Vfx.gun_blast + rinculo) e la contraerea che espelle bossoli.
var lineup: Array = []     # [modello, lunghezza, tipo]
var blast_t := 0.4
func _lineup_demo() -> void:
	var kinds := Shot.arg("kinds", "tank,art,aa").split(",")
	var fac := int(Shot.arg("faction", "1"))
	var lod := int(Shot.arg("lod", "0"))
	var gap := 3.2
	var widths: Array = []
	var total := 0.0
	for k in kinds:
		var m := UnitModels.build(String(k), Data.faction_color(fac), lod, fac)
		var w := 4.6 if k != "inf" else 5.0
		widths.append(w)
		total += w + gap
		lineup.append([m, float(m.get_meta("length", 7.0)), String(k)])
		UnitModels.set_number(m, 100 + (lineup.size() * 113) % 800)
		var spades := m.find_child("Spades", true, false) as Node3D
		var bar := m.find_child("Barrel", true, false) as Node3D
		var dep_arg := Shot.arg("deploy", "1")
		if spades != null and (dep_arg == "1" or (dep_arg == "half" and lineup.size() % 2 == 1)):
			spades.rotation.x = 0.35
			if bar:
				bar.rotation.x = 0.55
		elif k == "aa" and bar:
			bar.rotation.x = 0.5
		add_child(m)
		_collect(m)
	total -= gap
	var x := -total * 0.5
	for i in lineup.size():
		var m: Node3D = lineup[i][0]
		var w: float = widths[i]
		m.position = Vector3(x + w * 0.5, (3.0 if bool(m.get_meta("air", false)) else 0.0), 200.0)
		m.rotation.y = deg_to_rad(float(Shot.arg("yaw", "-38")))
		x += w + gap
	var d := float(Shot.arg("dist", str(maxf(total * 1.05, 9.0))))
	var el := deg_to_rad(float(Shot.arg("el", "18")))
	var ay := deg_to_rad(float(Shot.arg("cam_yaw", "12")))
	_look(Vector3(0, 0, 200) + Vector3(sin(ay) * cos(el), sin(el), -cos(ay) * cos(el)) * d + Vector3(0, 1.0, 0), Vector3(0, 1.1, 200))
	sun.directional_shadow_max_distance = 120

func _lineup_update(delta: float) -> void:
	var spd := float(Shot.arg("spd", "5.0"))
	var mud := float(Shot.arg("mud", "0.45"))
	for e in lineup:
		var m: Node3D = e[0]
		UnitModels.set_motion(m, t * spd, mud)
	if demo != "blast":
		return
	blast_t -= delta
	if blast_t <= 0.0:
		blast_t = 1.3
		for e in lineup:
			var m: Node3D = e[0]
			var k: String = e[2]
			var mz := m.find_child("Muzzle", true, false) as Node3D
			var bar := m.find_child("Barrel", true, false) as Node3D
			if mz == null:
				continue
			var dir := -mz.global_transform.basis.z if k != "art" else (-mz.global_transform.basis.z + Vector3(0, 0.3, 0)).normalized()
			if k in ["tank", "art"]:
				Vfx.gun_blast(self, mz.global_position, dir, 1.0 if k == "tank" else 1.5, 0.0)
				if bar:
					var base := bar.position
					var tw := create_tween()
					tw.tween_property(bar, "position:z", base.z + 0.45, 0.07)
					tw.tween_property(bar, "position:z", base.z, 0.5)
			elif k == "aa":
				Vfx.muzzle_flash(self, mz.global_position, dir)
				Vfx.casings(self, mz.global_position + m.global_transform.basis * Vector3(0, 0.2, 3.0), m.global_transform.basis.x, 8, 1.6)
			elif k == "inf":
				Vfx.muzzle_flash(self, mz.global_position, dir)
				Vfx.casings(self, mz.global_position + m.global_transform.basis * Vector3(0.2, -0.1, 0.8), m.global_transform.basis.x, 5, 0.9)

func _process(delta: float) -> void:
	t += delta
	if not lineup.is_empty():
		_lineup_update(delta)
	if not anim_sq.is_empty():
		_anim_update(delta)
	if Shot.has_arg("perf"):
		var fr := Engine.get_process_frames()
		if fr > 60 and fr <= 360:
			perf_n += 1
			perf_cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
			perf_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if fr == 361:
			print("[perf] demo=%s legacy=%s frames=%d cpu_render=%.2f ms gpu=%.2f ms fps=%d" % [demo, str(not ModelKit.use_shaders), perf_n, perf_cpu / perf_n, perf_gpu / perf_n, Engine.get_frames_per_second()])
			get_tree().quit()
	if demo == "soldiers":
		_sol_step()
		return
	if Shot.has_arg("multi"):
		_multi_step()
	for mv in movers:
		var n: Node3D = mv[0]
		n.position.z -= float(mv[1]) * delta
	if demo in ["ships", "shipclose", "shipstern", "transport"] and not movers.is_empty():
		cam.position.z -= float(movers[0][1]) * delta
	for s in spinners:
		var n: Node3D = s[0]
		if not is_instance_valid(n):
			continue
		match String(s[1]):
			"Rotor": n.rotate_y(delta * 18.0)
			"TailRotor": n.rotate_x(delta * 40.0)
			"Prop": n.rotate_z(delta * 50.0)
			"Radar": n.rotate_y(delta * 2.0)
	if demo.begins_with("faction") or demo == "confronto":
		return
	if demo == "vfx" and t > 0.3 and t - delta <= 0.3:
		Vfx.explosion(self, fx_origin + Vector3(2, 0, 4), 1.5)
		Vfx.shell_trail(self, fx_origin + Vector3(-40, 2, 40), fx_origin + Vector3(14, 0, 0), 1.0)
	if demo == "vfx" and Engine.get_process_frames() % 3 == 0:
		var g := fx_origin + Vector3(-11, 2.4, 25)
		Vfx.tracer(self, g, fx_origin + Vector3(randf_range(-4, 4), 1, -2))
		if Engine.get_process_frames() % 9 == 0:
			Vfx.muzzle_flash(self, g + Vector3(0, 0, -6), Vector3(0, 0, -1))
	if demo == "night" and Engine.get_process_frames() % 20 == 0:
		Vfx.night_flash(self, fx_origin + Vector3(randf_range(-120, 120), 8, randf_range(-160, -90)), randf_range(0.8, 1.6))
	fx_t -= delta
	if fx_t <= 0.0:
		fx_t = 0.45
		fx_i += 1
		var base := fx_origin
		var tgt := base + Vector3(randf_range(-14, 14), 0, randf_range(-12, 4))
		match fx_i % 4:
			0:
				Vfx.explosion(self, tgt, randf_range(0.8, 1.8))
			1:
				var from := base + Vector3(-20 + (fx_i % 3) * 9, 2.3, 21)
				Vfx.muzzle_flash(self, from, (tgt - from).normalized())
				Vfx.tracer(self, from, tgt + Vector3(0, 1, 0))
				Vfx.dust(self, from + Vector3(0, -2.0, 1))
			2:
				Vfx.shell_trail(self, base + Vector3(-60, 2, 60), tgt, 1.2)
			3:
				Vfx.dust(self, tgt)
				Vfx.tracer(self, base + Vector3(-25, 1.5, 15), tgt + Vector3(0, 1, 0), Color(1, 0.3, 0.2))
