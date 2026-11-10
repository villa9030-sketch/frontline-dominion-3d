class_name BattleAI
extends RefCounted
## FRONTLINE DOMINION 3D — IA tattica della battaglia (Fase 5). Guida un lato della BattleSim: quello non umano,
## entrambi nella risoluzione automatica. Vede solo ciò che il proprio lato ha avvistato (più i fantasmi).
## Attaccante: ricognizione (elicotteri/droni davanti), fanteria che avanza a balzi da una copertura all'altra,
## carri dietro lo schermo della fanteria a distanza di tiro (fuori dai boschi) e aggiramento sui fianchi con metà dei carri,
## artiglieria lontana che spara su ciò che viene avvistato (o sui fantasmi recenti), contraerea al seguito.
## Difensore: fanteria nascosta in boschi/città davanti alla propria linea (imboscate), carri in posizione dietro di lei,
## artiglieria in fondo; contrattacca solo se nettamente più forte.

const REORDER := 5.0
const DEF_VEH_COVER := false   # true: l'IA difensiva mette carri e contraerea defilati nei boschi (difesa molto più forte)
const IDLE := 0
const MOVE := 1
const ATTACK := 2
const AMOVE := 3
const FIRE := 4


static func think(s, si: int) -> void:
	var S: Dictionary = s.sides[si]
	var A: Dictionary = S["ai"]
	var E := 1 - si
	var dirx := 1.0 if si == 0 else -1.0
	var mine: Array = []
	var kground: Array = []
	var kaa: Array = []
	var mx := 0.0
	var my := 0.0
	for u in s.units:
		if u.dead:
			continue
		if u.side == E:
			if u.spotted[si] and not u.air:
				kground.append(u)
				if u.type == "aa":
					kaa.append(u)
		elif not u.stat:
			mine.append(u); mx += u.x; my += u.y
	if mine.is_empty():
		return
	mx /= mine.size(); my /= mine.size()
	# stima della posizione nemica: avvistati + fantasmi (peso minore); altrimenti la sua zona di schieramento
	var kx := 0.0
	var ky := 0.0
	var kw := 0.0
	for e in kground:
		kx += e.x; ky += e.y; kw += 1.0
	for g in s.ghosts[si]:
		if g["type"] == "heli" or g["type"] == "jet" or g["type"] == "drone":
			continue
		kx += float(g["x"]) * 0.5; ky += float(g["y"]) * 0.5; kw += 0.5
	var ex: float
	var ey: float
	# obiettivo del campo (docs/omogeneita.md §1): il più vicino non ancora tenuto; l'attaccante vi punta quando non vede nemici
	var obj = _next_objective(s, si, mx, my)
	if kw > 0:
		ex = kx / kw; ey = ky / kw
	elif obj != null:
		ex = float(obj["x"]) - dirx * 120.0; ey = float(obj["y"])
	else:
		ex = s.deploy_zone(E).get_center().x; ey = my
	if obj != null and si == 0:
		A["fy"] = clampf(float(obj["y"]), s.TOP + 150.0, s.BOTTOM - 150.0)   # settore d'attacco = obiettivo
	if int(S["support"]) > 0 and S["barrage_cd"] <= 0:
		var p = s._cluster(si)
		if p != null:
			s.barrage(si, p.x, p.y)
	if s.hs >= 0:
		s._ai_smoke(si)
	if A["phase"] == "start":
		var meet: bool = si == 1 and String(s.setup.get("def", {}).get("ai_mode", "")) == "attack"
		A["phase"] = "defend" if (si == 1 and not meet) else "scout"
		A["t0"] = s.time
		A["re"] = 0.0
		A["flank"] = false
		var f := -1e9
		for u in mine:
			if not u.air and u.type != "art":
				f = maxf(f, u.x * dirx)
		A["front0"] = f * dirx if f > -1e8 else mx
	if A["phase"] != "defend" and not A.has("fy"):
		# settore d'attacco: un terzo del fronte, a caso (o dove si vedono meno nemici)
		var H3: float = (s.BOTTOM - s.TOP) / 3.0
		var opts := [s.TOP + H3 * 0.5, s.TOP + H3 * 1.5, s.TOP + H3 * 2.5]
		A["fy"] = opts[s._rng.randi() % 3]
	var reorder: bool = s.time >= float(A["re"])
	if reorder:
		A["re"] = s.time + REORDER
	var ph: String = A["phase"]
	if ph == "scout" and (s.time - float(A["t0"]) > 18.0 or not kground.is_empty()):
		ph = "advance"; A["phase"] = ph; reorder = true
	if ph == "defend" and s.time - float(A["t0"]) > 30.0 and s.power(si) > s.power(E) * 1.6:
		ph = "advance"; A["phase"] = ph; reorder = true
		for u in mine:
			u.role = ""; u.hold = false
	if ph == "defend":
		_defend(s, si, mine, kground, kaa, dirx, reorder, A, mx, my)
	else:
		_attack(s, si, mine, kground, kaa, ex, ey, mx, my, dirx, reorder, ph == "scout", A)


## Obiettivo più vicino (dal baricentro del lato) non tenuto dal lato; null se non ci sono obiettivi.
static func _next_objective(s, si: int, mx: float, my: float):
	var best = null
	var bd := 1e18
	for o in s.objectives:
		if int(o["owner"]) == si:
			continue
		var d: float = (float(o["x"]) - mx) * (float(o["x"]) - mx) + (float(o["y"]) - my) * (float(o["y"]) - my) * 0.5
		if o["kind"] == "hq":
			d *= 0.6   # il QG vale di più
		if d < bd:
			bd = d; best = o
	return best


# ---------------------------------------------------------------------------- difesa
static func _defend(s, si: int, mine: Array, kground: Array, kaa: Array, dirx: float, reorder: bool, A: Dictionary, mx: float, my: float) -> void:
	var front: float = A["front0"]
	if not A.get("posted", false):
		A["posted"] = true
		_assign_posts(s, si, mine, front, dirx)
		# il difensore guidato dall'IA ha avuto il tempo di prepararsi: parte già in posizione
		if s.time < 2.0 and not s.sides[si]["human"]:
			for u in mine:
				if u.role == "post" and not u.air:
					u.x = u.rx; u.y = u.ry
					s._push_out(u)
					u.rx = u.x; u.ry = u.y
					s.order_unit(u, IDLE, u.x, u.y, null)
					u.hold = true
					u.ang = PI if si == 1 else 0.0
					u.tur = u.ang
			s._upd_vis(true)
	var recon := mine.filter(func(u): return u.type == "heli" or u.type == "drone")
	for u in mine:
		if u.type == "heli" or u.type == "drone":
			_recon(s, u, recon.find(u), recon.size(), kaa, front + dirx * 900.0, dirx, reorder)
		elif u.type == "jet":
			_jet(s, u, kground, mx, my, dirx, reorder)
		else:
			if u.type == "art" and _art_ghost_fire(s, u):
				continue
			if u.role != "post":
				u.role = "post"; u.rx = u.x; u.ry = u.y
			var dx: float = u.x - u.rx
			var dy: float = u.y - u.ry
			if dx * dx + dy * dy > 45.0 * 45.0:
				if u.order == IDLE and (reorder or u.tgt == null):
					s.order_unit(u, MOVE, u.rx, u.ry, null)
			elif not u.hold and u.order == IDLE:
				s.order_unit(u, IDLE, u.x, u.y, null)
				u.hold = true


static func _assign_posts(s, si: int, mine: Array, front: float, dirx: float) -> void:
	var spots: Array = s.cover_spots
	var used := {}
	var infs := mine.filter(func(u): return u.type == "inf")
	infs.sort_custom(func(a, b): return a.y < b.y)
	for u in infs:
		var best := -1
		var bs := 1e18
		for i in spots.size():
			if used.has(i):
				continue
			var p: Vector2 = spots[i]
			var ahead: float = (p.x - front) * dirx
			if ahead < -700.0 or ahead > 900.0:
				continue
			var sc: float = absf(p.y - u.y) + absf(ahead - 250.0) * 0.6
			if s.cover_at(p.x, p.y) >= 2:
				sc -= 120.0
			if s.spot_road[i]:
				sc -= 160.0   # anticarro sulle vie d'accesso
			if sc < bs:
				bs = sc; best = i
		u.role = "post"
		if best >= 0 and bs < 1500.0:
			used[best] = true
			u.rx = spots[best].x; u.ry = spots[best].y
		else:
			u.rx = u.x + dirx * 150.0; u.ry = u.y
	for u in mine:
		if u.role == "post" or u.air:
			continue
		var tx: float = u.x
		match u.type:
			"tank": tx = front - dirx * 350.0
			"aa": tx = front - dirx * 600.0
			"art": tx = (s.W - 450.0) if si == 1 else 450.0
		var p := _open_point(s, tx, u.y)
		if DEF_VEH_COVER and (u.type == "tank" or u.type == "aa"):
			# carri e contraerea aspettano in posizione defilata (copertura) dietro la fanteria: imboscata anche per loro
			var best := -1
			var bs := 420.0 * 420.0
			for i in spots.size():
				if used.has(i):
					continue
				var q: Vector2 = spots[i]
				var d2: float = (q.x - tx) * (q.x - tx) + (q.y - u.y) * (q.y - u.y) * 0.5
				if d2 < bs:
					bs = d2; best = i
			if best >= 0:
				used[best] = true
				p = spots[best]
		u.role = "post"; u.rx = p.x; u.ry = p.y


# ---------------------------------------------------------------------------- attacco
static func _attack(s, si: int, mine: Array, kground: Array, kaa: Array, ex: float, ey: float, mx: float, my: float, dirx: float, reorder: bool, scout: bool, A: Dictionary) -> void:
	var inf_front := -1e9
	var has_inf := false
	var gx := 0.0
	var gy := 0.0
	var gn := 0
	var tanks: Array = []
	var recon: Array = []
	for u in mine:
		if u.type == "inf":
			has_inf = true
			inf_front = maxf(inf_front, u.x * dirx)
		if u.type == "tank":
			tanks.append(u)
		if u.type == "heli" or u.type == "drone":
			recon.append(u)
		if u.type == "inf" or u.type == "tank":
			gx += u.x; gy += u.y; gn += 1
	if gn > 0:
		gx /= gn; gy /= gn
	else:
		gx = mx; gy = my
	var tank_front := -1e9
	for u in tanks:
		tank_front = maxf(tank_front, u.x * dirx)
	A["tank_front"] = tank_front * dirx if tank_front > -1e8 else NAN
	var ground_front := inf_front
	for u in mine:
		if not u.air and u.type != "art":
			ground_front = maxf(ground_front, u.x * dirx)
	# aggiramento: metà dei carri (il lato più lontano dal centro nemico) va sul fianco
	if not A["flank"] and not scout and tanks.size() >= 4 and not kground.is_empty():
		A["flank"] = true
		tanks.sort_custom(func(a, b): return a.y < b.y)
		var half := tanks.size() / 2
		var top_side: Array = tanks.slice(0, half)
		var bot_side: Array = tanks.slice(tanks.size() - half, tanks.size())
		var ty := 0.0
		for u in top_side: ty += u.y
		var by := 0.0
		for u in bot_side: by += u.y
		var grp: Array = top_side if absf(ty / half - ey) > absf(by / half - ey) else bot_side
		var sg := -1.0 if grp == top_side else 1.0
		var fy := clampf(ey + sg * 950.0, s.TOP + 150.0, s.BOTTOM - 150.0)
		var p := _open_point(s, ex - dirx * 350.0, fy)
		for u in grp:
			u.role = "flank"; u.rx = p.x; u.ry = p.y + (u.y - by / half if sg > 0 else u.y - ty / half) * 0.5; u.rt = s.time
	A["ground_front"] = ground_front * dirx if ground_front > -1e8 else mx
	var taken := {}
	for u in mine:
		match u.type:
			"inf":
				_inf_attack(s, u, kground, ex, ey, my, dirx, scout, reorder, A, taken)
			"tank":
				_tank_attack(s, u, kground, ex, ey, my, dirx, scout, reorder, A, inf_front * dirx, has_inf)
			"art":
				_art_attack(s, u, kground, mx, dirx, reorder, A)
			"aa":
				if gn == 0:
					# niente carri né fanteria: la contraerea è la forza principale
					_tank_attack(s, u, kground, ex, ey, my, dirx, scout, reorder, A, inf_front * dirx, false)
				elif reorder or (u.order == IDLE and u.tgt == null):
					var tx := gx - dirx * 600.0   # ombrello antiaereo dietro l'assalto, fuori dal tiro dei carri
					if Vector2(tx - u.x, gy - u.y).length() > 260.0:
						var p := _open_point(s, tx, gy + (u.y - my) * 0.3)
						s.order_unit(u, AMOVE, p.x, p.y, null)
			"heli", "drone":
				var sx: float = ground_front * dirx + dirx * 700.0
				if not kground.is_empty() and not scout:
					sx = ex - dirx * 500.0
				_recon(s, u, recon.find(u), recon.size(), kaa, sx, dirx, reorder)
			"jet":
				_jet(s, u, kground, mx, my, dirx, reorder)


static func _inf_attack(s, u, kground: Array, ex: float, ey: float, my: float, dirx: float, scout: bool, reorder: bool, A: Dictionary, taken: Dictionary) -> void:
	if not reorder and not (u.order == IDLE and u.tgt == null):
		return
	# concentrazione: tutto l'attacco converge sul settore scelto (superiorità locale contro una difesa distribuita)
	var lane := clampf(float(A.get("fy", ey)) + clampf(u.y - my, -900.0, 900.0) * 0.6, s.TOP + 80.0, s.BOTTOM - 80.0)
	if scout:
		var sx: float = float(A["front0"]) + dirx * 350.0
		if (sx - u.x) * dirx > 60.0:
			s.order_unit(u, AMOVE, sx, u.y, null)
		return
	var nn := _nearest(kground, u.x, u.y)
	var ne = nn[0]
	var nd: float = nn[1]
	if ne != null and nd < 550.0 and (ne.type == "art" or ne.type == "aa" or (ne.type == "inf" and ne.cover == 0)):
		s.order_unit(u, AMOVE, ne.x, ne.y, null)   # assalto ravvicinato (mai allo scoperto contro carri)
		return
	if ne != null and nd <= u.range_ and u.cover > 0:
		if u.order != IDLE:
			s.order_unit(u, IDLE, u.x, u.y, null)  # resta in copertura e spara
		return
	# corazzati nemici noti a portata: niente balzi allo scoperto, la fanteria aspetta in copertura che i carri amici li ingaggino
	var kt := kground.filter(func(e): return e.type == "tank")
	var nt := _nearest(kt, u.x, u.y)
	if nt[0] != null and float(nt[1]) < 1550.0:
		if u.cover > 0:
			if u.order != IDLE:
				s.order_unit(u, IDLE, u.x, u.y, null)
			return
		var q = _near_cover(s, u.x, u.y, 520.0, taken)
		if q != null:
			s.order_unit(u, MOVE, q.x, q.y, null)
		else:
			s.order_unit(u, MOVE, u.x - dirx * 300.0, u.y, null)
		return
	var gx: float = u.x + dirx * 550.0
	if ne != null and (gx - ne.x) * dirx > -250.0:
		gx = ne.x - dirx * 250.0
	# i corazzati aprono la strada: la fanteria resta dietro la linea dei carri finché non c'è da stanare il nemico dalle coperture
	var tf = A.get("tank_front", NAN)
	if not is_nan(tf) and (ne == null or ne.cover == 0) and (gx - float(tf)) * dirx > -150.0:
		gx = float(tf) - dirx * 150.0
		if (gx - u.x) * dirx < 60.0:
			if u.order != IDLE:
				s.order_unit(u, IDLE, u.x, u.y, null)
			return
	var p = _pick_cover(s, u, gx, lane, dirx, taken)
	if p != null:
		s.order_unit(u, AMOVE, p.x, p.y, null)
	else:
		s.order_unit(u, AMOVE, gx, lerpf(u.y, lane, 0.3), null)


static func _tank_attack(s, u, kground: Array, ex: float, ey: float, my: float, dirx: float, scout: bool, reorder: bool, A: Dictionary, inf_front: float, has_inf: bool) -> void:
	if u.role == "flank":
		var d := Vector2(u.x - u.rx, u.y - u.ry).length()
		if s.time - u.rt < 50.0 and d > 80.0:
			if u.order != MOVE:
				s.order_unit(u, MOVE, u.rx, u.ry, null)
			return
		u.role = "flank2"
		s.order_unit(u, AMOVE, ex + dirx * 300.0, ey, null)
		return
	if u.role == "flank2":
		if u.order == IDLE and u.tgt == null:
			u.role = ""
		elif reorder and u.tgt == null:
			s.order_unit(u, AMOVE, ex + dirx * 300.0, ey, null)
			return
		else:
			return
	if not reorder and not (u.order == IDLE and u.tgt == null):
		return
	# concentrazione: tutto l'attacco converge sul settore scelto (superiorità locale contro una difesa distribuita)
	var lane := clampf(float(A.get("fy", ey)) + clampf(u.y - my, -900.0, 900.0) * 0.6, s.TOP + 80.0, s.BOTTOM - 80.0)
	if scout:
		var sx: float = float(A["front0"]) + dirx * 100.0
		if (sx - u.x) * dirx > 60.0:
			s.order_unit(u, AMOVE, sx, u.y, null)
		return
	var nn := _nearest(kground, u.x, u.y)
	var ne = nn[0]
	var nd: float = nn[1]
	# duello tra carri: con un carro nemico a tiro si resta fermi a sparare (muso avanti), niente riposizionamenti di fianco
	var ktk := kground.filter(func(e): return e.type == "tank")
	var nk := _nearest(ktk, u.x, u.y)
	if nk[0] != null and float(nk[1]) <= u.range_ * 0.95 and not (ne.type == "inf" and ne.cover > 0 and nd < 450.0):
		if u.order != IDLE:
			s.order_unit(u, IDLE, u.x, u.y, null)
		return
	if ne != null:
		if ne.type == "inf" and ne.cover > 0 and nd < 650.0:
			# fanteria in copertura da vicino = anticarro: si sgancia e la colpisce da lontano (fuori portata dei lanciarazzi)
			var bx: float = u.x - ne.x
			var by: float = u.y - ne.y
			var bl := maxf(1.0, sqrt(bx * bx + by * by))
			var q := _open_point(s, ne.x + bx / bl * 1000.0, ne.y + by / bl * 1000.0)
			s.order_unit(u, MOVE, q.x, q.y, null)
			return
		if nd <= u.range_ * 0.95:
			if u.zone == 1:
				# in un bosco il carro vede poco e rischia l'imboscata: esce allo scoperto
				var p := _open_point(s, u.x - dirx * 150.0, u.y)
				s.order_unit(u, MOVE, p.x, p.y, null)
			elif u.order != IDLE:
				s.order_unit(u, IDLE, u.x, u.y, null)
			return
		# distanza di tiro rispetto alla minaccia corazzata nota più vicina (se c'è), altrimenti al bersaglio più vicino
		var ref = ne
		var kt := kground.filter(func(e): return e.type == "tank")
		if not kt.is_empty():
			ref = _nearest(kt, u.x, u.y)[0]
		var vx: float = u.x - ref.x
		var vy: float = u.y - ref.y
		var vl := maxf(1.0, sqrt(vx * vx + vy * vy))
		var p := _open_point(s, ref.x + vx / vl * u.range_ * 0.85, ref.y + vy / vl * u.range_ * 0.85)
		s.order_unit(u, AMOVE, p.x, p.y, null)
		return
	# nessun nemico noto: dietro lo schermo della fanteria (che avvista e assorbe le imboscate)
	var tx: float = u.x + dirx * 500.0
	if (tx - u.x) * dirx > 80.0:
		var p := _open_point(s, tx, lane)
		s.order_unit(u, AMOVE, p.x, p.y, null)
	elif u.order != IDLE:
		s.order_unit(u, IDLE, u.x, u.y, null)


static func _art_attack(s, u, kground: Array, mx: float, dirx: float, reorder: bool, A: Dictionary = {}) -> void:
	if _art_ghost_fire(s, u):
		return
	if not reorder and u.order != IDLE:
		return
	if not kground.is_empty():
		var cx := 0.0
		var cy := 0.0
		for e in kground:
			cx += e.x; cy += e.y
		cx /= kground.size(); cy /= kground.size()
		var nn := _nearest(kground, u.x, u.y)
		var dc := Vector2(u.x - cx, u.y - cy).length()
		if float(nn[1]) < 1800.0 or dc > u.range_ * 0.9:
			var vl := maxf(1.0, dc)
			var px: float = clampf(cx + (u.x - cx) / vl * u.range_ * 0.6, 100.0, s.W - 100.0)
			var py: float = clampf(cy + (u.y - cy) / vl * u.range_ * 0.6, s.TOP + 100.0, s.BOTTOM - 100.0)
			if Vector2(px - u.x, py - u.y).length() > 200.0:
				s.order_unit(u, MOVE, px, py, null)
		return
	# fuoco di preparazione: nessun bersaglio noto, si battono le coperture davanti alla propria avanzata (dove può nascondersi il nemico)
	if u.order == IDLE and u.deploy_t <= 0 and not s.cover_spots.is_empty():
		var E: int = 1 - u.side
		var z: Rect2 = s.deploy_zone(E)
		var gfront: float = float(A.get("ground_front", mx))
		var best = null
		var bs := 1e18
		for i in range(0, s.cover_spots.size(), 2):
			var p: Vector2 = s.cover_spots[i]
			if not z.has_point(p):
				continue
			var ahead: float = (p.x - gfront) * dirx
			if ahead < 250.0 or ahead > 1400.0:
				continue
			var d := Vector2(p.x - u.x, p.y - u.y).length()
			if d > u.range_ or d < u.min_range:
				continue
			var sc: float = ahead + absf(p.y - float(A.get("fy", p.y))) * 0.5 + s._rng.randf() * 300.0
			if sc < bs:
				bs = sc; best = p
		if best != null:
			s.order_unit(u, FIRE, best.x, best.y, null)
			u.rt = s.time
			return
	# segue l'esercito ben fuori dalla gittata dei carri nemici (la sua gittata basta)
	var gf: float = float(A.get("ground_front", mx))
	var tx := gf - dirx * 2200.0
	if (tx - u.x) * dirx > 400.0 and u.order == IDLE:
		s.order_unit(u, MOVE, tx, u.y, null)


## Artiglieria senza bersagli avvistati: fuoco d'area sul fantasma più recente a tiro. true se ha dato/mantiene l'ordine.
static func _art_ghost_fire(s, u) -> bool:
	if u.order == FIRE:
		if u.tgt != null or s.time - u.rt > 12.0:
			s.order_unit(u, IDLE, u.x, u.y, null)
			return false
		return true
	if u.tgt != null or u.order != IDLE:
		return false
	var best = null
	var bt := -1e9
	for g in s.ghosts[u.side]:
		if s.time - float(g["t"]) > 10.0 or g["type"] == "heli" or g["type"] == "jet" or g["type"] == "drone":
			continue
		var d := Vector2(float(g["x"]) - u.x, float(g["y"]) - u.y).length()
		if d > u.range_ or d < u.min_range:
			continue
		if float(g["t"]) > bt:
			bt = float(g["t"]); best = g
	if best == null:
		return false
	var h: bool = u.hold
	s.order_unit(u, FIRE, float(best["x"]), float(best["y"]), null)
	u.rt = s.time
	u.hold = h
	return true


static func _recon(s, u, idx: int, n: int, kaa: Array, sx: float, dirx: float, reorder: bool) -> void:
	if not reorder and not (u.order == IDLE and u.tgt == null):
		return
	var py: float = s.TOP + (idx + 0.5) / maxf(1.0, n) * (s.BOTTOM - s.TOP)
	var px := clampf(sx, 150.0, s.W - 150.0)
	for a in kaa:
		var R: float = a.range_ + 250.0
		if Vector2(a.x - px, a.y - py).length() < R:
			px = a.x - dirx * (a.range_ + 450.0)
	s.order_unit(u, AMOVE, clampf(px, 150.0, s.W - 150.0), py, null)


static func _jet(s, u, kground: Array, mx: float, my: float, dirx: float, reorder: bool) -> void:
	if not reorder and not (u.order == IDLE and u.tgt == null):
		return
	var best = null
	var bd := 1e18
	for e in kground:
		if e.type == "aa" or e.stat:
			continue
		var d := Vector2(e.x - mx, e.y - my).length_squared()
		if d < bd:
			bd = d; best = e
	if best != null:
		s.order_unit(u, AMOVE, best.x, best.y, null)
	else:
		s.order_unit(u, MOVE, mx + dirx * 400.0, my, null)


# ---------------------------------------------------------------------------- utilità
static func _nearest(list: Array, x: float, y: float) -> Array:
	var best = null
	var bd := 1e18
	for e in list:
		var d: float = (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)
		if d < bd:
			bd = d; best = e
	return [best, sqrt(bd) if best != null else 1e9]


## Punto percorribile fuori dai boschi (e dai campi minati noti all'attaccante) vicino a (x, y) (per i mezzi).
static func _open_point(s, x: float, y: float) -> Vector2:
	x = clampf(x, 100.0, s.W - 100.0)
	y = clampf(y, s.TOP + 80.0, s.BOTTOM - 80.0)
	if _free(s, x, y):
		return Vector2(x, y)
	for ring in [120.0, 240.0, 360.0]:
		for k in 8:
			var a := k * TAU / 8.0
			var px := clampf(x + cos(a) * ring, 100.0, s.W - 100.0)
			var py := clampf(y + sin(a) * ring, s.TOP + 80.0, s.BOTTOM - 80.0)
			if _free(s, px, py):
				return Vector2(px, py)
	return Vector2(x, y)


static func _free(s, x: float, y: float) -> bool:
	return s.zone_at(x, y) != 1 and not s._obs_hit(x, y, 16.0) and not s.known_mine_at(0, x, y)


## Prossima copertura in avanti (balzo della fanteria) vicino al punto (gx, gy).
static func _pick_cover(s, u, gx: float, gy: float, dirx: float, taken: Dictionary):
	var spots: Array = s.cover_spots
	var best := -1
	var bs := 1e18
	for i in spots.size():
		if taken.has(i):
			continue
		var p: Vector2 = spots[i]
		var ahead: float = (p.x - u.x) * dirx
		if ahead < 60.0 or ahead > 900.0:
			continue
		var dx: float = p.x - gx
		var dy: float = p.y - gy
		var sc := dx * dx + dy * dy
		if sc < bs:
			bs = sc; best = i
	if best >= 0 and bs < 650.0 * 650.0:
		taken[best] = true
		return spots[best]
	return null


## Copertura libera più vicina entro r (in qualunque direzione).
static func _near_cover(s, x: float, y: float, r: float, taken: Dictionary):
	var spots: Array = s.cover_spots
	var best := -1
	var bs := r * r
	for i in spots.size():
		if taken.has(i):
			continue
		var p: Vector2 = spots[i]
		var d2: float = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
		if d2 < bs:
			bs = d2; best = i
	if best < 0:
		return null
	taken[best] = true
	return spots[best]
