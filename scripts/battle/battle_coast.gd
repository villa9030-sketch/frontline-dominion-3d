class_name BattleCoast
extends Node3D
## Battaglie costiere (setup.sea), solo scena: mezzi da sbarco arenati sulla riva da cui sbarcano i mezzi a terra
## dell'attaccante (scostamento visivo che si annulla in pochi secondi) e navi al largo che sparano salve decorative.

const LAND_SPEED := 13.0     # m/s apparenti dei mezzi che lasciano la rampa

var battle            # Battle3D
var crafts: Array = []        # {n: Node3D, ramp: Vector3, ph: float}
var landing := {}             # id unità -> {from: Vector3, delay: float, dur: float}
var land_t := 0.0
var ships: Array = []         # [Node3D, fase, lato]
var _salvo_t := 4.0
var _shells: Array = []       # {a, b, t, T, peak, land}
var _rng := RandomNumberGenerator.new()

func setup(b, ship_list: Array) -> void:
	battle = b
	ships = ship_list
	_rng.seed = b.sim.seed_ * 31 + 5
	_salvo_t = 2.5 + _rng.randf() * 2.0
	_place_crafts()

func _place_crafts() -> void:
	var sim: BattleSim = battle.sim
	var ground: Array = []
	for u in sim.units:
		if u.side == 0 and not u.air and not u.stat and not u.dead:
			ground.append(u)
	if ground.is_empty():
		return
	ground.sort_custom(func(a, b): return a.y < b.y)
	var k := clampi(int(ceil(ground.size() / 6.0)), 2, 5)
	var per := int(ceil(float(ground.size()) / k))
	var col: Color = battle.side_color(0)
	for c in k:
		var grp := ground.slice(c * per, mini(ground.size(), (c + 1) * per))
		if grp.is_empty():
			continue
		var zs := 0.0
		for u in grp:
			zs += BattleTerrain.sim_to_world(u.x, u.y).y
		var Z := zs / grp.size() + _rng.randf_range(-4.0, 4.0)
		var cx: float = battle.terrain.coast_x(Z)
		var n := BattleProps.landing_craft(col)
		add_child(n)
		var X := cx - 9.0
		n.position = Vector3(X, -0.55, Z)
		var yaw := -PI * 0.5 + _rng.randf_range(-0.12, 0.12)
		n.rotation.y = yaw
		var ramp := n.position + Basis(Vector3.UP, yaw) * Vector3(0, 0, -11.0)
		ramp.y = maxf(battle.terrain.height(ramp.x, ramp.z), -0.3)
		crafts.append({"n": n, "ramp": ramp, "ph": _rng.randf() * TAU})
		# ordine di sbarco: prima i più vicini alla riva
		grp.sort_custom(func(a, b): return a.x < b.x)
		for i in grp.size():
			var u: BattleSim.Unit = grp[i]
			var w := BattleTerrain.sim_to_world(u.x, u.y)
			var d := Vector2(ramp.x, ramp.z).distance_to(w)
			landing[u.id] = {"from": ramp + Vector3(0, 0, _rng.randf_range(-1.0, 1.0)), "delay": i * 0.32, "dur": clampf(d / LAND_SPEED, 1.0, 4.5)}

## Scostamento visivo dell'unità durante lo sbarco (Vector3.ZERO se arrivata). real = posizione vera della vista.
func land_offset(u: BattleSim.Unit, real: Vector3) -> Vector3:
	if not landing.has(u.id):
		return Vector3.ZERO
	var L: Dictionary = landing[u.id]
	var f := clampf((land_t - float(L["delay"])) / float(L["dur"]), 0.0, 1.0)
	if f >= 1.0:
		landing.erase(u.id)
		return Vector3.ZERO
	var e := f * f * (3.0 - 2.0 * f)
	var from: Vector3 = L["from"]
	var o := (from - real) * (1.0 - e)
	o.y = 0.0
	return o

func finish_landing() -> void:
	land_t = 1e6

func update(dt: float, frozen: bool) -> void:
	var t: float = battle._wall_time
	for c in crafts:
		var n: Node3D = c["n"]
		n.position.y = -0.55 + sin(t * 0.8 + float(c["ph"])) * 0.08
		n.rotation.z = sin(t * 0.6 + float(c["ph"])) * 0.012
	if frozen:
		return
	land_t += dt
	# salve decorative
	_salvo_t -= dt
	if _salvo_t <= 0 and not ships.is_empty() and battle.sim.ending == null:
		_salvo_t = 5.0 + _rng.randf() * 7.0
		_fire_salvo()
	var i := 0
	while i < _shells.size():
		var s: Dictionary = _shells[i]
		s["t"] += dt
		if float(s["t"]) < 0.0:
			i += 1
			continue
		var f: float = s["t"] / s["T"]
		if f >= 1.0:
			_impact(s)
			_shells.remove_at(i)
			continue
		var a: Vector3 = s["a"]
		var b: Vector3 = s["b"]
		var p := a.lerp(b, f) + Vector3(0, 4.0 * float(s["peak"]) * f * (1.0 - f), 0)
		var f2 := minf(1.0, f + 0.02)
		var p2 := a.lerp(b, f2) + Vector3(0, 4.0 * float(s["peak"]) * f2 * (1.0 - f2), 0)
		battle.fx.shell_draw(p, p2 - p, true)
		i += 1

func _fire_salvo() -> void:
	var sh: Array = ships[_rng.randi() % ships.size()]
	var n: Node3D = sh[0]
	if not is_instance_valid(n):
		return
	var side: int = sh[2]
	var L: float = float(n.get_meta("length", 90.0))
	var gun := n.global_transform * Vector3(0, 7.0, -L * 0.3)
	var shots := 2 + _rng.randi() % 2
	for k in shots:
		var tgt: Vector3
		var land := true
		if side == 0:
			# l'attaccante batte le retrovie nemiche oltre il campo (colline lontane)
			var Z := _rng.randf_range(-BattleTerrain.FIELD_HZ * 0.8, BattleTerrain.FIELD_HZ * 0.8)
			var X := BattleTerrain.FIELD_HX + _rng.randf_range(25.0, 90.0)
			tgt = Vector3(X, battle.terrain.height(X, Z), Z)
		else:
			# il difensore spara contro le navi avversarie: colonne d'acqua al largo
			var other = _enemy_ship(side)
			var c: Vector3 = (other as Node3D).global_position if other != null else gun + Vector3(-60, 0, 0)
			tgt = Vector3(c.x + _rng.randf_range(-35.0, 35.0), 0.0, c.z + _rng.randf_range(-35.0, 35.0))
			if battle.terrain.height(tgt.x, tgt.z) > 0.0:
				tgt.x -= 40.0
			tgt.y = 0.0
			land = false
		var d := gun.distance_to(tgt)
		_shells.append({"a": gun, "b": tgt, "t": -k * 0.22, "T": clampf(d / 160.0, 1.4, 3.2), "peak": maxf(25.0, d * 0.22), "land": land})
	battle.fx.muzzle(gun, (Vector3(0, 0.4, 0) + (n.global_transform.basis * Vector3(0, 0, -1))).normalized(), 2.6)
	battle.fx.light(gun, 2.5, 30.0, 0.1)
	if battle.audio != null:
		battle.audio.play_at("cannon", gun, "arty", 3.0, 0.8)

func _enemy_ship(side: int):
	for s in ships:
		if int(s[2]) != side and is_instance_valid(s[0]):
			return s[0]
	return null

func _impact(s: Dictionary) -> void:
	var p: Vector3 = s["b"]
	if s["land"]:
		battle.fx.explosion(p, 1.1, true)
	else:
		battle.fx.splash(p, 1.2)
	if battle.audio != null:
		battle.audio.play_at("arty_impact" if s["land"] else "expl_small", p, "big" if s["land"] else "small")
