class_name BattleRelief
extends RefCounted
## FRONTLINE DOMINION 3D — rilievo del campo di battaglia (Fase 7).
## Funzione d'altezza deterministica (tipo di terreno + seed della battaglia) CONDIVISA da sim e vista:
##  - `h(x, y)`: quota esatta in metri nel punto (px sim, anche fuori dal campo); la vista la campiona per la mesh.
##  - `height(x, y)`: bilineare sulla griglia `G` (10 m), veloce: è quella che usa la sim.
##  - `los(x0, y0, x1, y1)`: linea di vista libera tra due unità a terra (occhi a BattleRules.LOS_EYE m), cache per celle.
## Rilievi per tipo: pianura (colline dolci, un fiume), foresta (ondulata, un torrente), montagna (due creste con valichi),
## deserto (dune, mesas, uadi asciutto), artico (cumuli di neve, lago ghiacciato), urbano (quasi piano, un terrapieno),
## costa (`sea`: spiaggia, poi falesie con varchi dove passano le strade).
## Con `flat` (setup.clear dei test) il campo è piano; `add_hill` / `add_ridge` aggiungono rilievi a mano (test).

const G := 60.0             # passo della griglia della sim (px) = 15 m
const NU := 40.0            # unità di coordinata del rumore (px): indipendente dal passo della griglia
const LOS_CELL := 60.0      # celle della cache delle linee di vista (px)
const S := 0.25             # metri per px
static var disabled := false   # interruttore globale (misure di confronto): tutti i campi piani

var tkey := "pianura"
var flat := false
var W := 4800.0
var H := 2700.0
var TOP := 138.0
var BOTTOM := 2544.0
var sea := false
var coast_ph := 0.0
var base := 3.2
var a1 := 8.0               # ampiezza delle colline (m)
var a2 := 2.0               # ampiezza del dettaglio (m)
var ad := 0.0               # dune / cumuli di neve (m)
var nb := FastNoiseLite.new()
var nd := FastNoiseLite.new()
var nx := FastNoiseLite.new()
var feats: Array = []       # {k: "hill"|"mesa"|"ridge"|"river"|"lake"|"bank", bx0, by0, bx1, by1, ...}
var rivers: Array = []      # fiumi e uadi (sottoinsieme di feats), per la vista: acqua, ponti, sabbia
var lake = null             # {x, y, rx, ry, lvl}
var bluffs := false
var road_ys: Array = []     # quota y delle strade sulla costa (varchi nelle falesie)
var has_water := false      # almeno un fiume con acqua (guadabile: rallenta; ponti e guadi no)
var gw := 0
var gh := 0
var hg := PackedFloat32Array()
var hmin := 0.0
var hmax := 0.0
var _rng := RandomNumberGenerator.new()
var _fb := PackedFloat64Array()   # riquadri dei rilievi (x0, y0, x1, y1)
var _fk := PackedInt32Array()
var _los := {}
var _lw := 0
var _lh := 0
var _ln := 0
var los_rays := 0           # statistiche: linee calcolate (non in cache)
var eye := 2.2
var tol := 0.25

func _init(tk: String, seed_: int, w: float, h: float, top: float, bottom: float, is_sea: bool, cph: float, is_flat: bool, roads: Array) -> void:
	tkey = tk
	W = w; H = h; TOP = top; BOTTOM = bottom
	sea = is_sea
	coast_ph = cph
	flat = is_flat or disabled
	eye = BattleRules.LOS_EYE
	tol = BattleRules.LOS_TOL
	_rng.seed = seed_ * 977 + 13
	for n in [nb, nd, nx]:
		(n as FastNoiseLite).noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.seed = seed_ + 11
	nb.fractal_type = FastNoiseLite.FRACTAL_FBM
	nb.fractal_octaves = 3
	nd.seed = seed_ + 23
	nd.fractal_type = FastNoiseLite.FRACTAL_FBM
	nd.fractal_octaves = 3
	nx.seed = seed_ + 37
	nx.fractal_type = FastNoiseLite.FRACTAL_FBM
	nx.fractal_octaves = 2
	if sea and not roads.is_empty():
		for r in roads:
			var pts: Array = r
			if pts.size() >= 2 and absf(pts[1].x - pts[0].x) > absf(pts[1].y - pts[0].y):
				road_ys.append(_poly_y_at(pts, 420.0))
	if not flat:
		_generate(roads)
	else:
		base = 0.0; a1 = 0.0; a2 = 0.0; ad = 0.0
	_build_grid()

static func _poly_y_at(pts: Array, x: float) -> float:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 0.001:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return pts[0].y

func coast(y: float) -> float:
	# identica a BattleSim.coast
	return 354.0 + 48.0 * sin(y * 0.004 + coast_ph) + 24.0 * sin(y * 0.0123 + 1.3)

# ---------------------------------------------------------------------------- generazione
func _freq(n: FastNoiseLite, wavelength_px: float) -> void:
	n.frequency = NU / wavelength_px

func _generate(roads: Array) -> void:
	var r := _rng
	var cy := (TOP + BOTTOM) * 0.5
	match tkey:
		"pianura":
			a1 = 13.0; _freq(nb, 2000.0); a2 = 2.2; _freq(nd, 620.0)
			_hill(W * (0.16 + r.randf() * 0.2), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 600 + r.randf() * 260, 12.0 + r.randf() * 7.0)
			_hill(W * (0.62 + r.randf() * 0.22), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 600 + r.randf() * 260, 12.0 + r.randf() * 7.0)
			_river(W * (0.4 + r.randf() * 0.2), 260.0, 34.0, 470.0, 1.6, true)
		"foresta":
			a1 = 15.0; _freq(nb, 1900.0); a2 = 3.0; _freq(nd, 560.0)
			_hill(W * (0.14 + r.randf() * 0.22), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 650 + r.randf() * 260, 13.0 + r.randf() * 7.0)
			_hill(W * (0.62 + r.randf() * 0.24), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 650 + r.randf() * 260, 13.0 + r.randf() * 7.0)
			_river(W * (0.42 + r.randf() * 0.16), 200.0, 24.0, 320.0, 1.3, true)
		"montagna":
			a1 = 14.0; _freq(nb, 2000.0); a2 = 8.0; _freq(nd, 760.0)
			nd.fractal_type = FastNoiseLite.FRACTAL_RIDGED
			# due creste trasversali all'asse d'attacco, una davanti a ciascun esercito, con valichi sulle strade
			for k in 2:
				var xc := W * (0.31 if k == 0 else 0.69) + (r.randf() - 0.5) * 240.0
				var passes := []
				for rd in roads:
					passes.append([_road_y_at(rd, xc), 0.72, 300.0])
				passes.append([TOP + 250 + r.randf() * (BOTTOM - TOP - 500), 0.55 + r.randf() * 0.2, 240.0])
				_ridge(xc, 160.0 + r.randf() * 120.0, 460.0 + r.randf() * 100.0, 42.0 + r.randf() * 14.0, passes)
			_hill(W * 0.5 + (r.randf() - 0.5) * 600.0, TOP + r.randf() * (BOTTOM - TOP), 700.0, 10.0 + r.randf() * 8.0)
		"deserto":
			a1 = 8.0; _freq(nb, 2400.0); a2 = 1.4; _freq(nd, 520.0)
			ad = 7.0; _freq(nx, 1800.0)
			var n_mesa := 3 + r.randi() % 2
			var placed := 0
			var tries := 0
			while placed < n_mesa and tries < 60:
				tries += 1
				var mx := 900.0 + r.randf() * (W - 1800.0)
				var my := TOP + 250 + r.randf() * (BOTTOM - TOP - 500)
				if placed == 0:
					mx = W * 0.5 + (r.randf() - 0.5) * 900.0
				var ok := true
				for f in feats:
					if f["k"] == "mesa" and Vector2(f["x"], f["y"]).distance_to(Vector2(mx, my)) < 900.0:
						ok = false
				for rd in roads:
					if absf(_road_y_at(rd, mx) - my) < 330.0 and absf(rd[0].y - rd[rd.size() - 1].y) < 1200.0:
						ok = false
				if ok:
					_mesa(mx, my, 150.0 + r.randf() * 120.0, 16.0 + r.randf() * 9.0)
					placed += 1
			# alcune mesas fuori dal campo (orizzonte)
			for k in 6:
				var a := r.randf() * TAU
				_mesa(W * 0.5 + cos(a) * (W * 0.62 + r.randf() * 1400.0), cy + sin(a) * (H * 0.62 + r.randf() * 900.0), 220.0 + r.randf() * 260.0, 18.0 + r.randf() * 16.0)
			_river(W * (0.38 + r.randf() * 0.24), 300.0, 46.0, 230.0, 2.2, false)
		"artico":
			a1 = 16.0; _freq(nb, 1900.0); a2 = 3.2; _freq(nd, 640.0)
			ad = 2.2; _freq(nx, 260.0)
			_hill(W * (0.15 + r.randf() * 0.2), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 620.0, 14.0 + r.randf() * 8.0)
			_hill(W * (0.65 + r.randf() * 0.2), TOP + 300 + r.randf() * (BOTTOM - TOP - 600), 620.0, 14.0 + r.randf() * 8.0)
			var lx := W * (0.42 + r.randf() * 0.16)
			var ly := cy + (r.randf() - 0.5) * 700.0
			for rd in roads:
				if absf(rd[0].y - rd[rd.size() - 1].y) < 1200.0 and absf(_road_y_at(rd, lx) - ly) < 520.0:
					ly = _road_y_at(rd, lx) + (560.0 if ly > _road_y_at(rd, lx) else -560.0)
			ly = clampf(ly, TOP + 380.0, BOTTOM - 380.0)
			_lake(lx, ly, 420.0 + r.randf() * 160.0, 250.0 + r.randf() * 90.0)
		"urbano":
			a1 = 2.5; _freq(nb, 3600.0); a2 = 0.35; _freq(nd, 900.0)
			# terrapieno ferroviario nord-sud nella zona dell'attaccante, davanti alla città
			feats.append({"k": "bank", "x": 690.0 + r.randf() * 80.0, "top": 22.0, "side": 70.0, "hgt": 3.4,
				"bx0": 500.0, "by0": -1e9, "bx1": 960.0, "by1": 1e9})
	base = 2.0 + a1 * 0.8 + ad * 0.5
	if sea:
		bluffs = true
	for rv in rivers:
		_crossings(rv, roads)
		if bool(rv["water"]):
			has_water = true

func _road_y_at(rd: Array, x: float) -> float:
	return _poly_y_at(rd, x) if absf(rd[0].y - rd[rd.size() - 1].y) < 1200.0 else 1e9

func _hill(x: float, y: float, R: float, hm: float) -> void:
	feats.append({"k": "hill", "x": x, "y": y, "R": R, "hm": hm, "bx0": x - R, "by0": y - R, "bx1": x + R, "by1": y + R})

func _mesa(x: float, y: float, R: float, hm: float) -> void:
	var T := 70.0 + hm * 3.0
	var top := _pre(x, y) + hm
	feats.append({"k": "mesa", "x": x, "y": y, "R": R, "T": T, "top": top, "p1": _rng.randf() * TAU, "p2": _rng.randf() * TAU,
		"bx0": x - R * 1.3 - T, "by0": y - R * 1.3 - T, "bx1": x + R * 1.3 + T, "by1": y + R * 1.3 + T})

func _ridge(xc: float, amp: float, w: float, hgt: float, passes: Array) -> void:
	feats.append({"k": "ridge", "x": xc, "a": amp, "f": TAU / (2600.0 + _rng.randf() * 900.0), "p": _rng.randf() * TAU,
		"w": w, "hgt": hgt, "passes": passes, "bx0": xc - amp - w, "by0": -1e9, "bx1": xc + amp + w, "by1": 1e9})

func _lake(x: float, y: float, rx: float, ry: float) -> void:
	var lo := 1e9
	for k in 12:
		var a := k / 12.0 * TAU
		lo = minf(lo, _pre(x + cos(a) * rx, y + sin(a) * ry))
	lo = minf(lo, _pre(x, y))
	lake = {"k": "lake", "x": x, "y": y, "rx": rx, "ry": ry, "lvl": lo - 0.8, "bx0": x - rx * 1.7, "by0": y - ry * 1.7, "bx1": x + rx * 1.7, "by1": y + ry * 1.7}
	feats.append(lake)

## Fiume (water) o uadi asciutto: tracciato nord-sud a meandri, alveo `cw` (semilarghezza px), valle `vw`, profondità `depth` m.
func _river(x0: float, amp: float, cw: float, vw: float, depth: float, water: bool) -> void:
	var rv := {"k": "river", "x": x0, "a1": amp, "f1": TAU / (2400.0 + _rng.randf() * 800.0), "p1": _rng.randf() * TAU,
		"a2": amp * 0.35, "f2": TAU / (760.0 + _rng.randf() * 300.0), "p2": _rng.randf() * TAU,
		"cw": cw, "vw": vw, "depth": depth, "water": water, "by": -1800.0, "bs": 40.0, "fords": [], "xings": []}
	rv["bx0"] = x0 - amp * 1.4 - vw
	rv["bx1"] = x0 + amp * 1.4 + vw
	rv["by0"] = -1e9
	rv["by1"] = 1e9
	# profilo dell'alveo: quota del terreno lungo il tracciato, in discesa verso sud, mai più di 7 m sotto il terreno
	var n := int((H + 3600.0) / 40.0) + 1
	var bed := PackedFloat32Array()
	bed.resize(n)
	var prev := 1e9
	for i in n:
		var y := -1800.0 + i * 40.0
		var s := _pre(river_x(rv, y), y)
		var b := minf(prev - 0.015, s)
		b = maxf(b, s - 7.0)
		bed[i] = b
		prev = b
	for pass_ in 3:
		var sm := bed.duplicate()
		for i in range(1, n - 1):
			sm[i] = (bed[i - 1] + 2.0 * bed[i] + bed[i + 1]) * 0.25
		bed = sm
	if sea:
		for i in n:
			bed[i] = maxf(bed[i], 1.2)
	rv["bed"] = bed
	feats.append(rv)
	rivers.append(rv)

## Attraversamenti del fiume: un ponte dove passa ogni strada (al più 2 per strada), più un guado lontano dai ponti.
## `rv.xings` = [{k: "bridge"|"ford", x, y (px), dir: Vector2 (direzione dell'attraversamento), half (px lungo il fiume)}].
## I guadi alzano il fondo (`fords`, usato in `_apply`): acqua bassa, visibile anche nella vista.
func _crossings(rv: Dictionary, roads: Array) -> void:
	var xs := []
	for rd in roads:
		var found := 0
		for i in rd.size() - 1:
			var a: Vector2 = rd[i]
			var b: Vector2 = rd[i + 1]
			var fa := a.x - river_x(rv, a.y)
			var fb := b.x - river_x(rv, b.y)
			if fa * fb > 0.0:
				continue
			var lo := 0.0
			var hi := 1.0
			for k in 24:
				var m := (lo + hi) * 0.5
				var q := a.lerp(b, m)
				if (q.x - river_x(rv, q.y)) * fa > 0.0:
					lo = m
				else:
					hi = m
			var p := a.lerp(b, (lo + hi) * 0.5)
			if p.y < TOP - 400.0 or p.y > BOTTOM + 400.0:
				continue
			var near := false
			for c in xs:
				if absf(float(c["y"]) - p.y) < 300.0:
					near = true
			if near or found >= 2:
				continue
			xs.append({"k": "bridge", "x": p.x, "y": p.y, "dir": (b - a).normalized(), "half": 44.0})
			found += 1
	if bool(rv["water"]):
		for tries in 14:
			var fy := TOP + 220.0 + _rng.randf() * (BOTTOM - TOP - 440.0)
			var ok := true
			for c in xs:
				if absf(float(c["y"]) - fy) < 420.0:
					ok = false
			if ok:
				var sl := river_slope(rv, fy)
				xs.append({"k": "ford", "x": river_x(rv, fy), "y": fy, "dir": Vector2(1.0, -sl).normalized(), "half": 80.0})
				rv["fords"].append(fy)
				break
	rv["xings"] = xs

## Acqua nel punto (0 = asciutto, ponte o guado; altrimenti 0..1 ~ profondità relativa nell'alveo).
## La sim rallenta chi guada (BattleRules.WADE_INF / WADE_VEH); i velivoli non ne risentono.
func water_at(x: float, y: float) -> float:
	if not has_water:
		return 0.0
	for rv in rivers:
		if not bool(rv["water"]) or x < float(rv["bx0"]) or x > float(rv["bx1"]):
			continue
		var cw: float = rv["cw"]
		var dp := river_dist(rv, x, y)
		if dp >= cw * 0.85:
			continue
		for c in rv["xings"]:
			if absf(y - float(c["y"])) < float(c["half"]):
				return 0.0
		return 1.0 - (dp / cw) * (dp / cw)
	return 0.0

## Punto intermedio verso cui dirigere un mezzo che deve passare un fiume per andare da (x0,y0) a (x1,y1): l'imbocco
## dell'attraversamento (ponte/guado) più comodo, poi l'uscita sulla sponda opposta; Vector2(NAN, NAN) se non serve.
func crossing_target(x0: float, y0: float, x1: float, y1: float) -> Vector2:
	if not has_water:
		return Vector2(NAN, NAN)
	for rv in rivers:
		if not bool(rv["water"]):
			continue
		var s0 := x0 - river_x(rv, y0)
		var s1 := x1 - river_x(rv, y1)
		if s0 * s1 > 0.0:
			continue
		var xg: Array = rv["xings"]
		if xg.is_empty():
			continue
		var best: Dictionary = xg[0]
		var bd := 1e18
		for c in xg:
			var cx := float(c["x"])
			var cy := float(c["y"])
			var d := sqrt((cx - x0) * (cx - x0) + (cy - y0) * (cy - y0)) + sqrt((x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy))
			if d < bd:
				bd = d
				best = c
		var cx := float(best["x"])
		var cy := float(best["y"])
		var cw: float = rv["cw"]
		var side := 1.0 if s1 > 0.0 else -1.0
		if absf(y0 - cy) < float(best["half"]) * 0.9 and absf(x0 - cx) < cw * 2.5:
			return Vector2(cx + side * cw * 2.2, cy)     # sull'attraversamento: oltre la sponda opposta
		return Vector2(cx - side * cw * 1.6, cy)         # imbocco sulla propria sponda
	return Vector2(NAN, NAN)

## Ascissa del tracciato del fiume alla quota y.
static func river_x(rv: Dictionary, y: float) -> float:
	return float(rv["x"]) + float(rv["a1"]) * sin(y * float(rv["f1"]) + float(rv["p1"])) + float(rv["a2"]) * sin(y * float(rv["f2"]) + float(rv["p2"]))

static func river_slope(rv: Dictionary, y: float) -> float:
	return float(rv["a1"]) * float(rv["f1"]) * cos(y * float(rv["f1"]) + float(rv["p1"])) + float(rv["a2"]) * float(rv["f2"]) * cos(y * float(rv["f2"]) + float(rv["p2"]))

## Quota del fondovalle (sponde) del fiume alla quota y; l'acqua sta 0.5 m sotto.
static func river_floor(rv: Dictionary, y: float) -> float:
	var bed: PackedFloat32Array = rv["bed"]
	var f := (y - float(rv["by"])) / float(rv["bs"])
	var i := clampi(int(f), 0, bed.size() - 2)
	return lerpf(bed[i], bed[i + 1], clampf(f - i, 0.0, 1.0))

## Distanza (px, perpendicolare approssimata) dal tracciato.
static func river_dist(rv: Dictionary, x: float, y: float) -> float:
	var sl := river_slope(rv, y)
	return absf(x - river_x(rv, y)) / sqrt(1.0 + sl * sl)

# ---------------------------------------------------------------------------- funzione d'altezza
## Quota senza la costa (base + rilievi). La vista ci somma i rilievi fuori campo e poi applica `shore`.
func _pre(x: float, y: float) -> float:
	var v := base
	if a1 > 0.0:
		v += a1 * nb.get_noise_2d(x / NU, y / NU) + a2 * nd.get_noise_2d(x / NU, y / NU)
	if ad > 0.0:
		if tkey == "deserto":
			# dune asimmetriche (sopravento dolce, sottovento ripido) dove la maschera lo permette
			var m := smoothstep(-0.12, 0.25, nx.get_noise_2d(x / NU, y / NU))
			if m > 0.0:
				var w := nd.get_noise_2d(x / NU * 0.7 + 40.0, y / NU * 0.7) * 160.0
				var s := fposmod((x * 0.82 + y * 0.35 + w) / 300.0, 1.0)
				var prof := smoothstep(0.0, 0.78, s) if s < 0.78 else 1.0 - smoothstep(0.78, 1.0, s)
				v += prof * ad * m
		else:
			# cumuli di neve allungati nella direzione del vento
			v += ad * absf(nx.get_noise_2d(x / NU * 0.35, y / NU * 1.4))
	if _fb.size() != feats.size() * 4:
		_index_feats()
	var o := 0
	for f in feats:
		if x >= _fb[o] and x <= _fb[o + 2] and y >= _fb[o + 1] and y <= _fb[o + 3]:
			v = _apply(f, v, x, y)
		o += 4
	return v

## Riquadri dei rilievi in un array compatto (il test dei limiti è la parte più frequente di `_pre`).
func _index_feats() -> void:
	_fb.resize(feats.size() * 4)
	_fk.resize(feats.size())
	for i in feats.size():
		var f: Dictionary = feats[i]
		_fb[i * 4] = f["bx0"]; _fb[i * 4 + 1] = f["by0"]; _fb[i * 4 + 2] = f["bx1"]; _fb[i * 4 + 3] = f["by1"]
		f["ki"] = ["hill", "mesa", "ridge", "river", "lake", "bank"].find(String(f["k"]))

func _apply(f: Dictionary, v: float, x: float, y: float) -> float:
	match int(f["ki"]):
		0:
			var dx: float = x - f["x"]
			var dy: float = y - f["y"]
			var R: float = f["R"]
			var d2 := dx * dx + dy * dy
			if d2 < R * R:
				var t := 1.0 - d2 / (R * R)
				v += float(f["hm"]) * t * t * (3.0 - 2.0 * t)
		1:
			var dx: float = x - f["x"]
			var dy: float = y - f["y"]
			var d := sqrt(dx * dx + dy * dy)
			var an := atan2(dy, dx)
			var Rr: float = float(f["R"]) * (1.0 + 0.17 * sin(an * 3.0 + float(f["p1"])) + 0.08 * sin(an * 5.0 + float(f["p2"])))
			var T: float = f["T"]
			if d < Rr + T:
				var s := clampf((d - Rr) / T, 0.0, 1.0)
				var prof := 1.0 - sqrt(s)
				prof = prof * prof * (3.0 - 2.0 * prof) * 0.35 + prof * 0.65
				var top: float = f["top"]
				v = maxf(v, lerpf(v, top, prof))
		2:
			var a: float = f["a"]
			var fr: float = f["f"]
			var ph: float = f["p"]
			var cx: float = float(f["x"]) + a * sin(y * fr + ph)
			var sl := a * fr * cos(y * fr + ph)
			var dp := absf(x - cx) / sqrt(1.0 + sl * sl)
			var w: float = f["w"]
			if dp < w:
				var hy: float = float(f["hgt"]) * (1.0 + 0.22 * sin(y * fr * 2.3 + ph * 1.7))
				for p in f["passes"]:
					var py: float = p[0]
					var pw: float = p[2]
					var e := (y - py) / pw
					if e * e < 9.0:
						hy *= 1.0 - float(p[1]) * exp(-e * e)
				var q := 1.0 - dp / w
				v += hy * pow(q, 1.35)
		3:
			var dp := river_dist(f, x, y)
			var vw: float = f["vw"]
			if dp < vw:
				var cw: float = f["cw"]
				var fl := river_floor(f, y)
				var t := smoothstep(cw * 1.3, vw, dp)
				v = minf(v, lerpf(fl, v, t))
				if dp < cw:
					var k := dp / cw
					v = minf(v, fl - float(f["depth"]) * (1.0 - k * k))
		4:
			var ex := (x - float(f["x"])) / float(f["rx"])
			var ey := (y - float(f["y"])) / float(f["ry"])
			var e := sqrt(ex * ex + ey * ey)
			if e < 1.7:
				var lvl: float = f["lvl"]
				v = lerpf(lvl, maxf(v, lvl), smoothstep(1.0, 1.7, e))
		5:
			var dp := absf(x - float(f["x"]))
			var top: float = f["top"]
			v += float(f["hgt"]) * (1.0 - smoothstep(top, top + float(f["side"]), dp))
	return v

## Profilo costiero: fondale, spiaggia, poi (a tratti) falesie con varchi sulle strade. `v` = quota dell'entroterra.
func shore(v: float, x: float, y: float) -> float:
	if not sea:
		return v
	var dm := (x - coast(y)) * S
	if dm > 90.0:
		return maxf(v, 0.6)
	if dm < 0.0:
		return maxf(-9.0, 0.3 + dm * 0.28)
	var inland := v
	if bluffs:
		var m := smoothstep(0.15, 0.55, 0.5 + 0.5 * sin(y * 0.0019 + coast_ph * 2.1)) * (0.75 + 0.25 * sin(y * 0.0071 + 0.4))
		for ry in road_ys:
			m *= smoothstep(140.0, 320.0, absf(y - float(ry)))
		if m > 0.0:
			inland = maxf(inland, 1.6) + (9.0 + 4.0 * sin(y * 0.0033 + coast_ph)) * m * smoothstep(34.0, 52.0, dm)
	var beach := 0.3 + dm * 0.045
	return maxf(lerpf(beach, maxf(inland, beach), smoothstep(4.0, 30.0, dm)), 0.6 if dm > 40.0 else -9.0)

## Quota esatta (m) nel punto (px sim).
func h(x: float, y: float) -> float:
	return shore(_pre(x, y), x, y)

# ---------------------------------------------------------------------------- griglia per la sim
func _build_grid() -> void:
	_lw = int(ceil(W / LOS_CELL))
	_lh = int(ceil(H / LOS_CELL))
	_ln = _lw * _lh
	_los.clear()
	if feats.is_empty() and a1 == 0.0 and ad == 0.0 and base == 0.0 and not sea:
		# campo piano: griglia minima
		gw = 2; gh = 2
		hg = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		hmin = 0.0; hmax = 0.0
		return
	gw = int(ceil(W / G)) + 1
	gh = int(ceil(H / G)) + 1
	hg.resize(gw * gh)
	hmin = 1e9
	hmax = -1e9
	for j in gh:
		var y := j * G
		for i in gw:
			var v := h(i * G, y)
			hg[j * gw + i] = v
			hmin = minf(hmin, v)
			hmax = maxf(hmax, v)
	_lw = int(ceil(W / LOS_CELL))
	_lh = int(ceil(H / LOS_CELL))
	_ln = _lw * _lh
	_los.clear()

## Quota (m) bilineare sulla griglia della sim.
func height(x: float, y: float) -> float:
	var fx := clampf(x / G, 0.0, gw - 1.001)
	var fy := clampf(y / G, 0.0, gh - 1.001)
	var i := int(fx)
	var j := int(fy)
	var tx := fx - i
	var ty := fy - j
	var a := j * gw + i
	var h0 := hg[a] + (hg[a + 1] - hg[a]) * tx
	var h1 := hg[a + gw] + (hg[a + gw + 1] - hg[a + gw]) * tx
	return h0 + (h1 - h0) * ty

## Rilievi aggiunti a mano (test, scenari): ricostruisce griglia e cache.
func add_hill(x: float, y: float, R: float, hm: float) -> void:
	_hill(x, y, R, hm)
	_build_grid()

## Cresta rettilinea nord-sud in x, semilarghezza w px, altezza hgt m.
func add_ridge(x: float, w: float, hgt: float) -> void:
	feats.append({"k": "ridge", "x": x, "a": 0.0, "f": 0.0, "p": 0.0, "w": w, "hgt": hgt, "passes": [], "bx0": x - w, "by0": -1e9, "bx1": x + w, "by1": 1e9})
	_build_grid()

## true se il rilievo esiste (altrimenti le linee di vista sono sempre libere).
func has_relief() -> bool:
	return hmax - hmin > 0.5

# ---------------------------------------------------------------------------- linee di vista
## Linea di vista tra due unità a terra (px sim). Simmetrica; calcolata tra i centri delle celle LOS_CELL e messa in cache.
func los(x0: float, y0: float, x1: float, y1: float) -> bool:
	var i0 := clampi(int(x0 / LOS_CELL), 0, _lw - 1)
	var j0 := clampi(int(y0 / LOS_CELL), 0, _lh - 1)
	var i1 := clampi(int(x1 / LOS_CELL), 0, _lw - 1)
	var j1 := clampi(int(y1 / LOS_CELL), 0, _lh - 1)
	var a := j0 * _lw + i0
	var b := j1 * _lw + i1
	if a == b or (absi(i0 - i1) <= 1 and absi(j0 - j1) <= 1):
		return true
	var key := a * _ln + b if a < b else b * _ln + a
	var c = _los.get(key)
	if c != null:
		return c
	var r := ray((i0 + 0.5) * LOS_CELL, (j0 + 0.5) * LOS_CELL, (i1 + 0.5) * LOS_CELL, (j1 + 0.5) * LOS_CELL)
	_los[key] = r
	return r

## Raggio esatto (senza cache) tra due punti a terra con gli occhi a `eye` m.
func ray(ax: float, ay: float, bx: float, by: float) -> bool:
	los_rays += 1
	var ha := height(ax, ay) + eye
	var hb := height(bx, by) + eye
	if hmax <= minf(ha, hb) + tol:
		return true
	var dx := bx - ax
	var dy := by - ay
	var L := sqrt(dx * dx + dy * dy)
	var n := int(ceil(L / (G * 0.75)))
	for k in range(1, n):
		var t := float(k) / n
		var x := ax + dx * t
		var y := ay + dy * t
		# griglia bilineare (in linea per velocità)
		var fx := clampf(x / G, 0.0, gw - 1.001)
		var fy := clampf(y / G, 0.0, gh - 1.001)
		var i := int(fx)
		var j := int(fy)
		var tx := fx - i
		var ty := fy - j
		var p := j * gw + i
		var h0 := hg[p] + (hg[p + 1] - hg[p]) * tx
		var h1 := hg[p + gw] + (hg[p + gw + 1] - hg[p + gw]) * tx
		if h0 + (h1 - h0) * ty > ha + (hb - ha) * t + tol:
			return false
	return true

## Moltiplicatore della vista di chi guarda da `dh` metri più in alto del bersaglio.
static func view_mul(dh: float) -> float:
	if dh <= 0.0:
		return 1.0
	return 1.0 + minf(BattleRules.HIGH_VIEW_MAX, dh * BattleRules.HIGH_VIEW_K)
