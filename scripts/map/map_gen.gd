class_name MapGen
extends RefCounted
## Generazione del mondo del tabellone (porting di frontline/js/mapgen.js + rilievo 3D).
## Funzione pura e deterministica; il risultato è memorizzato in cache (memoria + user://).
## Raster: W×H = 800×450 (S = 2 px mappa per cella). Coordinate mappa 0..1600 × 0..900.

const D = preload("res://scripts/core/data.gd")
const VERSION := 10
const S := 2
const W := 800
const H := 450
const WARP := 13.0
const PAD := 26.0
const TER_KEYS := ["pianura", "deserto", "urbano", "montagna", "foresta", "artico"]

static var _cache: Dictionary = {}

## -> {w, h, s, tid: PackedInt32Array (-1 mare), height: PackedFloat32Array (unità mondo, 0 = livello del mare),
##     border: PackedByteArray (distanza dal confine fra territori, 16 = 1 cella), cont: PackedByteArray (idem continenti),
##     coast: PackedByteArray (distanza dalla costa, terra e mare), ter1/ter2: Image pesi terreno a bassa risoluzione,
##     count: PackedInt32Array, ms}
static func build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var t0 := Time.get_ticks_msec()
	var path := "user://worldmap_v%d.bin" % VERSION
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var d = f.get_var(false)
			f.close()
			if d is Dictionary and d.get("version", 0) == VERSION:
				_cache = _finish(d)
				_cache["ms"] = Time.get_ticks_msec() - t0
				_cache["cached"] = true
				return _cache
	var data := _generate()
	data["version"] = VERSION
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_var(data, false)
		fw.close()
	_cache = _finish(data)
	_cache["ms"] = Time.get_ticks_msec() - t0
	_cache["cached"] = false
	return _cache

static func _finish(d: Dictionary) -> Dictionary:
	d["ter1"] = Image.create_from_data(d["tw"], d["th"], false, Image.FORMAT_RGBA8, d["ter1_data"])
	d["ter2"] = Image.create_from_data(d["tw"], d["th"], false, Image.FORMAT_RGBA8, d["ter2_data"])
	return d

static func _noise(seed: int, freq: float, octaves: int, kind: int = FastNoiseLite.TYPE_VALUE_CUBIC, fractal: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = kind
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n

static func _noise_img(n: FastNoiseLite, w: int, h: int) -> PackedFloat32Array:
	var img := n.get_image(w, h, false, false, true)
	img.convert(Image.FORMAT_RF)
	return img.get_data().to_float32_array()

static func _generate() -> Dictionary:
	var N := W * H
	var T: Array = D.TERRITORIES
	var NT := T.size()
	# ---------------------------------------------------------------- deformazione del dominio
	var G := 3
	var GW := int(ceil(float(W) / G)) + 2
	var GH := int(ceil(float(H) / G)) + 2
	var na := _noise(11, 1.0 / 62.0, 3)
	var nb := _noise(23, 1.0 / 62.0, 3)
	var nc := _noise(5, 1.0 / 17.0, 1, FastNoiseLite.TYPE_VALUE)
	var nd := _noise(6, 1.0 / 17.0, 1, FastNoiseLite.TYPE_VALUE)
	var gdx := PackedFloat32Array(); gdx.resize(GW * GH)
	var gdy := PackedFloat32Array(); gdy.resize(GW * GH)
	var k := 0
	for gy in GH:
		var Y := float(gy * G * S)
		for gx in GW:
			var X := float(gx * G * S)
			var dx := na.get_noise_2d(X, Y) * 1.45 * WARP + nc.get_noise_2d(X, Y) * 2.5
			var dy := nb.get_noise_2d(X, Y) * 1.45 * WARP + nd.get_noise_2d(X, Y) * 2.5
			gdx[k] = clampf(dx, -PAD, PAD)
			gdy[k] = clampf(dy, -PAD, PAD)
			k += 1
	var wx := PackedFloat32Array(); wx.resize(N)
	var wy := PackedFloat32Array(); wy.resize(N)
	var i := 0
	for y in H:
		var fy := float(y) / G
		var gy := int(fy)
		var ty := fy - gy
		var Yc := (y + 0.5) * S
		for x in W:
			var fx := float(x) / G
			var gx := int(fx)
			var tx := fx - gx
			k = gy * GW + gx
			var a := gdx[k] + (gdx[k + 1] - gdx[k]) * tx
			var b := gdx[k + GW] + (gdx[k + GW + 1] - gdx[k + GW]) * tx
			var c := gdy[k] + (gdy[k + 1] - gdy[k]) * tx
			var dd := gdy[k + GW] + (gdy[k + GW + 1] - gdy[k + GW]) * tx
			wx[i] = (x + 0.5) * S + a + (b - a) * ty
			wy[i] = Yc + c + (dd - c) * ty
			i += 1
	# ---------------------------------------------------------------- distanza normalizzata dai blob
	var best := PackedFloat32Array(); best.resize(N); best.fill(1.0)
	var tid := PackedInt32Array(); tid.resize(N); tid.fill(-1)
	for t in T:
		var ti: int = t["idx"]
		for bl in t["blobs_px"]:
			var cx: float = bl[0]
			var cy: float = bl[1]
			var r: float = bl[2]
			var r2 := r * r
			var inv := 1.0 / r
			var x0 := maxi(0, int(floor((cx - r - PAD) / S)))
			var x1 := mini(W - 1, int(ceil((cx + r + PAD) / S)))
			var y0 := maxi(0, int(floor((cy - r - PAD) / S)))
			var y1 := mini(H - 1, int(ceil((cy + r + PAD) / S)))
			for y in range(y0, y1 + 1):
				i = y * W + x0
				for x in range(x0, x1 + 1):
					var ddx := wx[i] - cx
					var ddy := wy[i] - cy
					var d2 := ddx * ddx + ddy * ddy
					if d2 < r2:
						var dn := sqrt(d2) * inv
						if dn < best[i]:
							best[i] = dn
							tid[i] = ti
					i += 1
	# ---------------------------------------------------------------- coesione (capsule tra blob dello stesso territorio)
	for t in T:
		var ti: int = t["idx"]
		var bls: Array = t["blobs_px"]
		for m in range(1, bls.size()):
			var bj := 0
			var bd := INF
			for n in m:
				var dg: float = Vector2(bls[m][0] - bls[n][0], bls[m][1] - bls[n][1]).length() - bls[m][2] - bls[n][2]
				if dg < bd:
					bd = dg
					bj = n
			var A: Array = bls[m]
			var B: Array = bls[bj]
			var wdt := maxf(7.0, 0.45 * minf(A[2], B[2]))
			_capsule(tid, best, wx, wy, A[0], A[1], B[0], B[1], wdt, ti, -1, false, A[2], B[2])
	# ---------------------------------------------------------------- istmi tra territori collegati via terra
	for l in D.LAND_LINKS:
		var TA: Dictionary = T[D.TERR_INDEX[l[0]]]
		var TB: Dictionary = T[D.TERR_INDEX[l[1]]]
		var ba: Array = []
		var bb: Array = []
		var bg := INF
		for a in TA["blobs_px"]:
			for b in TB["blobs_px"]:
				var g: float = Vector2(a[0] - b[0], a[1] - b[1]).length() - a[2] - b[2]
				if g < bg:
					bg = g; ba = a; bb = b
		if bg < -4.0:
			continue
		var wdt := maxf(9.0, 0.55 * minf(ba[2], bb[2]))
		_capsule(tid, best, wx, wy, ba[0], ba[1], bb[0], bb[1], wdt, TA["idx"], TB["idx"], true, ba[2], bb[2])
	# ---------------------------------------------------------------- laghi chiusi -> terra
	var comp := PackedInt32Array(); comp.resize(N); comp.fill(-1)
	var stack := PackedInt32Array(); stack.resize(N)
	var ncomp := 0
	var smalls: Array = []
	for s0 in N:
		if tid[s0] >= 0 or comp[s0] >= 0:
			continue
		var sp := 0
		var size := 0
		var edge_touch := false
		stack[sp] = s0; sp += 1
		comp[s0] = ncomp
		var pix := PackedInt32Array()
		while sp > 0:
			sp -= 1
			var p := stack[sp]
			size += 1
			if size <= 600:
				pix.append(p)
			var x := p % W
			var y := p / W
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				edge_touch = true
			if x > 0 and tid[p - 1] < 0 and comp[p - 1] < 0:
				comp[p - 1] = ncomp; stack[sp] = p - 1; sp += 1
			if x < W - 1 and tid[p + 1] < 0 and comp[p + 1] < 0:
				comp[p + 1] = ncomp; stack[sp] = p + 1; sp += 1
			if y > 0 and tid[p - W] < 0 and comp[p - W] < 0:
				comp[p - W] = ncomp; stack[sp] = p - W; sp += 1
			if y < H - 1 and tid[p + W] < 0 and comp[p + W] < 0:
				comp[p + W] = ncomp; stack[sp] = p + W; sp += 1
		if not edge_touch and size <= 600:
			smalls.append(pix)
		ncomp += 1
	for pix in smalls:
		var left: PackedInt32Array = pix
		var guard := 0
		while left.size() > 0 and guard < 60:
			guard += 1
			var nxt := PackedInt32Array()
			var setv := PackedInt32Array()
			for p in left:
				var x := p % W
				var v := -1
				if x > 0 and tid[p - 1] >= 0: v = tid[p - 1]
				elif x < W - 1 and tid[p + 1] >= 0: v = tid[p + 1]
				elif p - W >= 0 and tid[p - W] >= 0: v = tid[p - W]
				elif p + W < N and tid[p + W] >= 0: v = tid[p + W]
				if v >= 0:
					setv.append(p); setv.append(v)
				else:
					nxt.append(p)
			var q := 0
			while q < setv.size():
				tid[setv[q]] = setv[q + 1]
				q += 2
			left = nxt
	# ---------------------------------------------------------------- enclavi
	comp.fill(-1)
	ncomp = 0
	for s0 in N:
		var a := tid[s0]
		if a < 0 or comp[s0] >= 0:
			continue
		var sp := 0
		var pix := PackedInt32Array()
		var nbc := {}
		var has_center := false
		var ci := int(floor(T[a]["y"] / S)) * W + int(floor(T[a]["x"] / S))
		stack[sp] = s0; sp += 1
		comp[s0] = ncomp
		while sp > 0:
			sp -= 1
			var p := stack[sp]
			pix.append(p)
			if p == ci:
				has_center = true
			var x := p % W
			for j in [p - 1 if x > 0 else -1, p + 1 if x < W - 1 else -1, p - W, p + W]:
				if j < 0 or j >= N:
					continue
				var b := tid[j]
				if b == a:
					if comp[j] < 0:
						comp[j] = ncomp; stack[sp] = j; sp += 1
				elif b >= 0:
					nbc[b] = nbc.get(b, 0) + 1
		ncomp += 1
		if has_center or pix.size() > 160:
			continue
		var bestb := -1
		var bestc := 0
		for kk in nbc:
			if nbc[kk] > bestc:
				bestc = nbc[kk]; bestb = kk
		if bestb >= 0:
			for p in pix:
				tid[p] = bestb
	# ---------------------------------------------------------------- centro di ogni territorio garantito
	for t in T:
		var cx := int(floor(t["x"] / S))
		var cy := int(floor(t["y"] / S))
		for y in range(cy - 2, cy + 3):
			for x in range(cx - 2, cx + 3):
				if x < 0 or y < 0 or x >= W or y >= H:
					continue
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= 5:
					tid[y * W + x] = t["idx"]
	# ---------------------------------------------------------------- campi di distanza (chamfer 2/3)
	var cont_of := PackedInt32Array()
	for t in T:
		cont_of.append(D.CONT_KEYS.find(t["c"]))
	var bdist := PackedInt32Array(); bdist.resize(N); bdist.fill(9999)
	var nlab := PackedInt32Array(); nlab.resize(N); nlab.fill(-1)   # territorio confinante più vicino
	var cdist := PackedInt32Array(); cdist.resize(N); cdist.fill(9999)
	var ldist := PackedInt32Array(); ldist.resize(N)   # terra: distanza dal mare
	var sdist := PackedInt32Array(); sdist.resize(N)   # mare: distanza dalla terra
	i = 0
	for y in H:
		for x in W:
			var a := tid[i]
			if a < 0:
				ldist[i] = 0
				sdist[i] = 9999
			else:
				ldist[i] = 9999
				sdist[i] = 0
				var e := false
				var ec := false
				var cst := false
				for j in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if y > 0 else -1, i + W if y < H - 1 else -1]:
					if j < 0:
						continue
					var b := tid[j]
					if b < 0:
						cst = true
					elif b != a:
						e = true
						nlab[i] = b
						if cont_of[b] != cont_of[a]:
							ec = true
				if e: bdist[i] = 0
				if ec: cdist[i] = 0
				if cst: ldist[i] = 1
			i += 1
	_chamfer(bdist, nlab)
	_chamfer(cdist)
	_chamfer(ldist)
	_chamfer(sdist)
	# ---------------------------------------------------------------- pesi del terreno (bassa risoluzione, sfumati)
	var TS := 4
	var tw := W / TS
	var th := int(ceil(float(H) / TS))
	var nch := TER_KEYS.size()
	var tw_arr: Array = []
	for c in nch:
		var arr := PackedFloat32Array(); arr.resize(tw * th)
		tw_arr.append(arr)
	var ter_of := PackedInt32Array()
	for t in T:
		ter_of.append(TER_KEYS.find(t["ter"]))
	for y in th:
		for x in tw:
			var p := mini(H - 1, y * TS + TS / 2) * W + x * TS + TS / 2
			var a := tid[p]
			if a >= 0:
				tw_arr[ter_of[a]][y * tw + x] = 1.0
	for c in nch:
		tw_arr[c] = _blur(tw_arr[c], tw, th, 2)
		tw_arr[c] = _blur(tw_arr[c], tw, th, 1)
	# normalizzazione: i pesi sommano a 1 dove c'è almeno qualcosa
	for p in tw * th:
		var sm := 0.0
		for c in nch:
			sm += tw_arr[c][p]
		if sm > 0.0001:
			for c in nch:
				tw_arr[c][p] = tw_arr[c][p] / sm
		else:
			tw_arr[0][p] = 1.0
	# ---------------------------------------------------------------- altezze
	var n_ridge := _noise_img(_noise(101, 1.0 / 26.0, 5, FastNoiseLite.TYPE_PERLIN, FastNoiseLite.FRACTAL_RIDGED), W, H)
	var n_hill := _noise_img(_noise(202, 1.0 / 30.0, 4, FastNoiseLite.TYPE_PERLIN), W, H)
	var n_det := _noise_img(_noise(303, 1.0 / 7.0, 3, FastNoiseLite.TYPE_PERLIN), W, H)
	var n_big := _noise_img(_noise(404, 1.0 / 90.0, 3, FastNoiseLite.TYPE_PERLIN), W, H)
	var n_warp := _noise_img(_noise(505, 1.0 / 40.0, 2, FastNoiseLite.TYPE_PERLIN), W, H)
	var height := PackedFloat32Array(); height.resize(N)
	var wts := PackedFloat32Array(); wts.resize(nch)
	i = 0
	for y in H:
		var fy := (y + 0.5) / TS - 0.5
		var y0 := clampi(int(floor(fy)), 0, th - 1)
		var y1 := mini(y0 + 1, th - 1)
		var ty := clampf(fy - y0, 0.0, 1.0)
		for x in W:
			if tid[i] < 0:
				var sd := sdist[i] * 0.5
				var shelf := smoothstep(0.0, 9.0, sd)
				var deep := smoothstep(6.0, 55.0, sd)
				height[i] = -0.04 - 0.22 * shelf - 1.1 * deep + (n_big[i] - 0.5) * 0.35 * deep + (n_hill[i] - 0.5) * 0.08
				i += 1
				continue
			var fx := (x + 0.5) / TS - 0.5
			var x0 := clampi(int(floor(fx)), 0, tw - 1)
			var x1 := mini(x0 + 1, tw - 1)
			var tx := clampf(fx - x0, 0.0, 1.0)
			for c in nch:
				var arr: PackedFloat32Array = tw_arr[c]
				var top := arr[y0 * tw + x0] + (arr[y0 * tw + x1] - arr[y0 * tw + x0]) * tx
				var bot := arr[y1 * tw + x0] + (arr[y1 * tw + x1] - arr[y1 * tw + x0]) * tx
				wts[c] = top + (bot - top) * ty
			var ld := ldist[i] * 0.5
			var coast := smoothstep(0.0, 4.0, ld)
			var inland := smoothstep(1.0, 18.0, ld)
			var hill := n_hill[i]
			var det := n_det[i]
			var rid := n_ridge[i]
			# pianura / urbano: quasi piatti, ondulazione lieve
			var h_flat := 0.06 + 0.13 * hill + 0.025 * det
			# foresta: colline
			var h_for := 0.08 + 0.50 * pow(hill, 1.6) * (0.5 + 0.5 * inland) + 0.05 * det
			# montagna: catene (rumore ridged) che crescono verso l'interno
			var r2 := pow(rid, 2.2)
			var h_mtn := 0.22 + 0.35 * n_big[i] + 1.7 * r2 * (0.6 + 0.4 * inland) + 0.08 * det
			# deserto: dune ondulate deformate + altopiani
			var ph := (x * 0.52 + y * 0.30) * 0.55 + n_warp[i] * 9.0
			var dune := 0.5 + 0.5 * sin(ph)
			dune = dune * dune
			var h_des := 0.07 + 0.16 * dune * (0.4 + hill) + 0.22 * smoothstep(0.5, 0.8, n_big[i]) + 0.02 * det
			# artico: calotta di ghiaccio a cupola, creste dolci
			var h_arc := 0.12 + 0.60 * smoothstep(0.0, 22.0, ld) + 0.22 * hill + 0.35 * r2 * inland
			var hh := wts[0] * h_flat + wts[2] * (h_flat * 0.7) + wts[3] * h_mtn + wts[4] * h_for + wts[1] * h_des + wts[5] * h_arc
			height[i] = 0.015 + coast * hh + (1.0 - coast) * 0.01 * det
			i += 1
	# ---------------------------------------------------------------- ammorbidimento (coste e confini senza scalini)
	height = _blur(height, W, H, 1)
	height = _blur(height, W, H, 1)
	var bf := PackedFloat32Array(); bf.resize(N)
	for p in N:
		bf[p] = minf(bdist[p], 40.0)
	bf = _blur(_blur(bf, W, H, 1), W, H, 1)
	var cf := PackedFloat32Array(); cf.resize(N)
	for p in N:
		cf[p] = minf(cdist[p], 40.0)
	cf = _blur(cf, W, H, 1)
	# ---------------------------------------------------------------- impacchettamento
	var border := PackedByteArray(); border.resize(N)
	var contb := PackedByteArray(); contb.resize(N)
	var coastb := PackedByteArray(); coastb.resize(N)
	var count := PackedInt32Array(); count.resize(NT)
	var nbr := PackedByteArray(); nbr.resize(N)
	for p in N:
		nbr[p] = nlab[p] + 1
		border[p] = mini(255, int(bf[p] * 8.0))
		contb[p] = mini(255, int(cf[p] * 8.0))
		var cd := ldist[p] if tid[p] >= 0 else sdist[p]
		coastb[p] = mini(255, cd * 2)
		if tid[p] >= 0:
			count[tid[p]] += 1
	var ter1 := PackedByteArray(); ter1.resize(tw * th * 4)
	var ter2 := PackedByteArray(); ter2.resize(tw * th * 4)
	for p in tw * th:
		# ter1: montagna, deserto, artico, foresta ; ter2: urbano, pianura
		ter1[p * 4] = int(tw_arr[3][p] * 255.0)
		ter1[p * 4 + 1] = int(tw_arr[1][p] * 255.0)
		ter1[p * 4 + 2] = int(tw_arr[5][p] * 255.0)
		ter1[p * 4 + 3] = int(tw_arr[4][p] * 255.0)
		ter2[p * 4] = int(tw_arr[2][p] * 255.0)
		ter2[p * 4 + 1] = int(tw_arr[0][p] * 255.0)
		ter2[p * 4 + 2] = 0
		ter2[p * 4 + 3] = 255
	return {"w": W, "h": H, "s": S, "tid": tid, "height": height, "border": border, "nbr": nbr, "cont": contb, "coast": coastb,
		"count": count, "tw": tw, "th": th, "ter1_data": ter1, "ter2_data": ter2}

static func _capsule(tid: PackedInt32Array, best: PackedFloat32Array, wx: PackedFloat32Array, wy: PackedFloat32Array,
		ax: float, ay: float, bx: float, by: float, wdt: float, ia: int, ib: int, isthmus: bool, ra: float, rb: float) -> void:
	var vx := bx - ax
	var vy := by - ay
	var L2 := vx * vx + vy * vy
	if L2 == 0.0:
		L2 = 1.0
	var w2 := wdt * wdt
	var x0 := maxi(0, int(floor((minf(ax, bx) - wdt - PAD) / S)))
	var x1 := mini(W - 1, int(ceil((maxf(ax, bx) + wdt + PAD) / S)))
	var y0 := maxi(0, int(floor((minf(ay, by) - wdt - PAD) / S)))
	var y1 := mini(H - 1, int(ceil((maxf(ay, by) + wdt + PAD) / S)))
	for y in range(y0, y1 + 1):
		var i := y * W + x0
		for x in range(x0, x1 + 1):
			var cur := tid[i]
			var skip := false
			if isthmus:
				skip = cur >= 0
			else:
				skip = cur == ia or (cur >= 0 and best[i] < 0.75)
			if not skip:
				var px := wx[i]
				var py := wy[i]
				var u := clampf(((px - ax) * vx + (py - ay) * vy) / L2, 0.0, 1.0)
				var qx := ax + vx * u - px
				var qy := ay + vy * u - py
				var ww := w2
				if isthmus:
					ww = w2 * (0.75 + 0.25 * absf(2.0 * u - 1.0))
				if qx * qx + qy * qy < ww:
					if isthmus:
						var da := Vector2(px - ax, py - ay).length() / ra
						var db := Vector2(px - bx, py - by).length() / rb
						tid[i] = ia if da <= db else ib
					else:
						tid[i] = ia
						best[i] = 0.75
			i += 1

## Distanza chamfer 2/3 in loco (valori 0 = sorgente; 2 = una cella).
static func _chamfer(d: PackedInt32Array, lab: PackedInt32Array = PackedInt32Array()) -> void:
	var L := lab.size() > 0
	for y in H:
		var i := y * W
		for x in W:
			var v := d[i]
			if v != 0:
				var src := -1
				if x > 0 and d[i - 1] + 2 < v: v = d[i - 1] + 2; src = i - 1
				if y > 0:
					if d[i - W] + 2 < v: v = d[i - W] + 2; src = i - W
					if x > 0 and d[i - W - 1] + 3 < v: v = d[i - W - 1] + 3; src = i - W - 1
					if x < W - 1 and d[i - W + 1] + 3 < v: v = d[i - W + 1] + 3; src = i - W + 1
				if src >= 0:
					d[i] = v
					if L: lab[i] = lab[src]
			i += 1
	for y in range(H - 1, -1, -1):
		var i := y * W + W - 1
		for x in range(W - 1, -1, -1):
			var v := d[i]
			if v != 0:
				var src := -1
				if x < W - 1 and d[i + 1] + 2 < v: v = d[i + 1] + 2; src = i + 1
				if y < H - 1:
					if d[i + W] + 2 < v: v = d[i + W] + 2; src = i + W
					if x < W - 1 and d[i + W + 1] + 3 < v: v = d[i + W + 1] + 3; src = i + W + 1
					if x > 0 and d[i + W - 1] + 3 < v: v = d[i + W - 1] + 3; src = i + W - 1
				if src >= 0:
					d[i] = v
					if L: lab[i] = lab[src]
			i -= 1

static func _blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array(); tmp.resize(w * h)
	var out := PackedFloat32Array(); out.resize(w * h)
	var inv := 1.0 / (2 * r + 1)
	for y in h:
		for x in w:
			var s := 0.0
			for k in range(-r, r + 1):
				s += src[y * w + clampi(x + k, 0, w - 1)]
			tmp[y * w + x] = s * inv
	for y in h:
		for x in w:
			var s := 0.0
			for k in range(-r, r + 1):
				s += tmp[clampi(y + k, 0, h - 1) * w + x]
			out[y * w + x] = s * inv
	return out

# ---------------------------------------------------------------- interrogazioni (CPU)
static func cell_of(map_x: float, map_y: float) -> int:
	var x := clampi(int(map_x / S), 0, W - 1)
	var y := clampi(int(map_y / S), 0, H - 1)
	return y * W + x

static func territory_at(data: Dictionary, map_x: float, map_y: float) -> int:
	if map_x < 0 or map_y < 0 or map_x >= D.MAP_W or map_y >= D.MAP_H:
		return -1
	return data["tid"][cell_of(map_x, map_y)]

## Altezza (unità mondo) interpolata nel punto mappa.
static func height_at(data: Dictionary, map_x: float, map_y: float) -> float:
	var hh: PackedFloat32Array = data["height"]
	var fx := clampf(map_x / S - 0.5, 0.0, W - 1.001)
	var fy := clampf(map_y / S - 0.5, 0.0, H - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var i := y0 * W + x0
	var a := hh[i] + (hh[i + 1] - hh[i]) * tx
	var b := hh[i + W] + (hh[i + W + 1] - hh[i + W]) * tx
	return a + (b - a) * ty
