class_name BattleHud
extends CanvasLayer
## HUD della battaglia 3D: forze per lato, timer, territorio, pannello selezione, pulsanti, messaggi, sovrimpressione
## (riquadro di selezione, barre vita, simboli tattici a distanza, linee d'ordine).

signal pressed(id: String)

const BG := Color(0.045, 0.06, 0.065, 0.82)
const EDGE := Color(0.55, 0.6, 0.45, 0.35)
const TXT := Color(0.9, 0.92, 0.86)
const DIM := Color(0.62, 0.66, 0.6)
const SHORT := {"inf": "FAN", "tank": "CAR", "art": "ART", "aa": "AA", "heli": "ELI", "jet": "JET", "drone": "DRN", "bunker": "BNK"}

var battle            # Battle3D
var root: Control
var overlay: Overlay
var top: PanelContainer
var lbl_title: Label
var lbl_sub: Label
var lbl_time: Label
var side_box: Array = []    # [{name, bar, count, extra}]
var sel_panel: PanelContainer
var sel_title: Label
var sel_body: RichTextLabel
var btn_row: VBoxContainer
var cmd_row: HBoxContainer
var buttons := {}
var minimap: Minimap
var alert_btn: Button
var _alert_t := 0.0
var deploy_panel: PanelContainer
var deploy_title: Label
var msg_loss: RichTextLabel
var msg_panel: PanelContainer
var msg_title: Label
var msg_sub: Label
var pause_lbl: Label
var mode_lbl: Label
# Fase 8 — modalità foto
var photo_root: Control
var photo_panel: PanelContainer
var _vignette: ColorRect
var _photo_flash: ColorRect
var _flash_t := 0.0
var _dof_slider: HSlider
var _vig_slider: HSlider

const GOLD := Color(1.0, 0.82, 0.3)

## Stella a cinque punte (poligono: niente dipendenza dal glifo ★ nel font).
static func draw_star(ci: CanvasItem, c: Vector2, r: float, col: Color, outline := true) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if outline:
		var o := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var rr := (r + 1.6) if k % 2 == 0 else (r * 0.45 + 1.2)
			o.append(c + Vector2(cos(a), sin(a)) * rr)
		ci.draw_colored_polygon(o, Color(0, 0, 0, col.a * 0.75))
	ci.draw_colored_polygon(pts, col)

## Fila di stelle dei veterani (0..3) per pannelli e intro.
class Stars extends Control:
	var n := 0
	var r := 7.0
	func _init(count: int, radius := 7.0) -> void:
		n = count
		r = radius
		custom_minimum_size = Vector2(n * (r * 2.2) + 2, r * 2.2)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		for i in n:
			BattleHud.draw_star(self, Vector2(r * 1.1 + i * r * 2.2, size.y * 0.5), r, BattleHud.GOLD)

class Overlay extends Control:
	var hud
	func _draw() -> void:
		var b = hud.battle
		if b == null or b.sim == null:
			return
		var font := get_theme_default_font()
		var lines: bool = b.show_order_lines()
		var lk: float = b.order_lines_alpha()
		var hs: int = b.sim.hs
		var counters := []
		if b.strat != null and b.strat.k > 0.03:
			_draw_strategic(b, font, b.strat)
		for e in b.screen_list:
			var u = e[0]
			var sp: Vector2 = e[1]
			var rad: float = e[2]
			if u.dead:
				continue
			# dietro a edifici/rilievi: niente barre né simboli
			var occ: bool = e.size() > 5 and e[5]
			var ik: float = e[6] if e.size() > 6 else 0.0
			var conc: bool = e.size() > 7 and e[7]
			var frac: float = clampf(u.hp / u.hp_max, 0.0, 1.0)
			# pedina tattica a distanza (stile plancia): raccolta e disegnata dopo, raggruppando le vicine
			if ik > 0.02 and not occ:
				var tk: float = e[8] if e.size() > 8 else ik
				counters.append({"u": u, "p": sp + Vector2(0, -rad * (1.0 - tk) - 16.0), "a": ik, "z": lerpf(0.78, 1.0, tk), "n": b.sim.alive(u) if not u.stat else 1,
					"sel": u.sel, "hov": e[3], "hp": frac * float(u.hp_max), "hpm": float(u.hp_max), "conc": conc, "k": 1})
			var near_a := 1.0 - ik
			var show_bar: bool = (u.sel or frac < 0.985 or e[3]) and not occ and near_a > 0.15
			if show_bar:
				var w := clampf(rad * 1.6, 22.0, 46.0)
				var p2 := sp + Vector2(-w * 0.5, -rad - 6)
				BattleHud.draw_integrity(self, p2, w, 4.0, frac, near_a, u.side != hs and hs >= 0)
				# indicatore di colpo: lampo sulla barra e segno a croce sull'unità nemica
				if u.hit_t > 0.0:
					var ht: float = clampf(u.hit_t / 0.25, 0.0, 1.0)
					draw_rect(Rect2(p2 - Vector2(2, 2), Vector2(w + 4, 7)), Color(1, 1, 1, 0.55 * ht * near_a), false, 1.0)
					if u.side != hs:
						var hs2 := 4.0 + 3.0 * (1.0 - ht)
						var hcol := Color(1.0, 0.95, 0.8, 0.85 * ht)
						for dd in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
							draw_line(sp + dd * hs2, sp + dd * (hs2 + 4.0), hcol, 1.5)
				if u.g > 1:
					draw_string(font, p2 + Vector2(w + 3, 5), "×%d" % b.sim.alive(u), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85 * near_a))
			# notte 3 — chi spara si rivela: lampo accanto all'unità (propria in copertura: «sei stato visto»; nemica: «vista per il fuoco»)
			var rvt = u.get("reveal_t")
			if rvt != null and float(rvt) > 0.0 and not occ and hs >= 0 and not u.air and (u.side != hs or int(u.cover) > 0):
				var rp := sp + Vector2(maxf(rad, 11.0) + 9.0, -rad - 4.0)
				var ra: float = clampf(float(rvt) / 1.5, 0.25, 1.0) * maxf(near_a, 0.6)
				var rc := Color(1.0, 0.62, 0.2, ra) if u.side == hs else Color(1.0, 0.9, 0.5, ra)
				for k in 8:
					var an := k * TAU / 8.0
					var dv := Vector2(cos(an), sin(an))
					draw_line(rp + dv * 2.0, rp + dv * (6.5 if k % 2 == 0 else 4.5), rc, 1.6)
				draw_circle(rp, 2.0, rc)
			if not occ and near_a > 0.15 and u.side == hs:
				var gx := sp + Vector2(-maxf(rad, 11.0) - 9.0, -rad - 4.0)
				# mantieni posizione: piccolo scudo accanto all'unità
				if u.hold:
					BattleHud.draw_glyph(self, "hold", gx, 12.0, Color(BattleHud.AMBER, 0.95 * near_a))
					gx.y += 14.0
				# nascosta dalla copertura: foglia
				if conc:
					BattleHud.draw_glyph(self, "leaf", gx, 13.0, Color(0.6, 1.0, 0.55, 0.95 * near_a))
					gx.y += 14.0
				# artiglieria in piazzamento: orologio che si riempie
				var dpt = u.get("deploy_t")
				if dpt != null and float(dpt) > 0.0:
					var f := clampf(float(dpt) / 4.0, 0.0, 1.0)
					draw_arc(gx, 5.5, 0, TAU, 16, Color(0, 0, 0, 0.6 * near_a), 3.0)
					draw_arc(gx, 5.5, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - f), 16, Color(BattleHud.AMBER, near_a), 2.0)
			# veterani: stelle sopra le unità selezionate (o sotto il cursore)
			if (u.sel or e[3]) and not occ and near_a > 0.3:
				var nv: int = b.vet(u.side)
				if nv > 0:
					var yb: float = sp.y - rad - 15.0
					for k in nv:
						BattleHud.draw_star(self, Vector2(sp.x + (k - (nv - 1) * 0.5) * 10.0, yb), 4.2, Color(BattleHud.GOLD, near_a))
			# linea d'ordine dei selezionati (tenendo premuto Shift, o per un attimo dopo l'ordine)
			var fire_area: bool = u.order == 4
			if (lines or (fire_area and u.sel)) and u.sel and (u.order == BattleSim.MOVE or u.order == BattleSim.AMOVE or u.order == BattleSim.ATTACK or fire_area) and e.size() > 4 and e[4] != null:
				var dst: Vector2 = e[4]
				var oc := Color(0.45, 1.0, 0.55, 0.6) if u.order == BattleSim.MOVE else (Color(1.0, 0.7, 0.3, 0.65) if u.order == BattleSim.AMOVE else Color(1.0, 0.35, 0.3, 0.7))
				if fire_area:
					# fuoco d'area dell'artiglieria: bersaglio con punti d'impatto
					oc = Color(1.0, 0.55, 0.25, 0.75)
					BattleHud.draw_glyph(self, "area", dst, 26.0, oc)
					if not lines:
						continue
				oc.a *= lk
				draw_dashed_line(sp, dst, oc, 1.6, 7.0)
				draw_circle(dst, 3.0, oc)
				draw_arc(dst, 6.0, 0, TAU, 12, Color(oc, oc.a * 0.6), 1.0)
		_draw_ghosts(b, font)
		_draw_contacts(b, font)
		_draw_counters(b, font, counters)
		_draw_pings(b)
		_draw_floaters(b, font)
		_draw_alerts(b, font)
		if b.drag_active:
			var r := Rect2(b.drag_from, b.drag_to - b.drag_from).abs()
			draw_rect(r, Color(0.5, 1.0, 0.6, 0.12))
			draw_rect(r, Color(0.55, 1.0, 0.65, 0.85), false, 1.5)
		_draw_toasts(b, font)
		_draw_hover(b, font)

	## Pedine tattiche: le unità vicine dello stesso tipo e lato (sullo schermo) diventano una sola pedina con il totale.
	func _draw_counters(b, font: Font, list: Array) -> void:
		var merged := []
		for c in list:
			var hit = null
			if c["a"] > 0.8:
				for m in merged:
					if m["u"].side == c["u"].side and m["u"].type == c["u"].type and m["a"] > 0.8 and (m["p"] as Vector2).distance_to(c["p"]) < 24.0:
						hit = m
						break
			if hit == null:
				merged.append(c)
			else:
				var k: int = hit["k"]
				hit["p"] = ((hit["p"] as Vector2) * k + c["p"]) / (k + 1)
				hit["k"] = k + 1
				hit["n"] = int(hit["n"]) + int(c["n"])
				hit["hp"] = float(hit["hp"]) + float(c["hp"])
				hit["hpm"] = float(hit["hpm"]) + float(c["hpm"])
				hit["sel"] = hit["sel"] or c["sel"]
				hit["hov"] = hit["hov"] or c["hov"]
				hit["conc"] = hit["conc"] and c["conc"]
		var hs: int = b.sim.hs
		var view := Rect2(Vector2.ZERO, size).grow(60.0)
		# vista strategica: pedine più grandi (leggibili sulla plancia)
		var sc0: float = 1.0 + 0.45 * (b.strat.k if b.strat != null else 0.0)
		for m in merged:
			var u = m["u"]
			var mp: Vector2 = m["p"]
			if not mp.is_finite() or not view.has_point(mp):
				continue
			var own: bool = hs < 0 or u.side == hs
			var sc: float = sc0 * float(m.get("z", 1.0))
			if sc > 1.01:
				draw_set_transform(mp * (1.0 - sc), 0.0, Vector2(sc, sc))
			BattleHud.draw_counter(self, font, m["p"], b.side_color(u.side), u.type, int(m["n"]), own, m["sel"], m["hov"], float(m["a"]),
				clampf(float(m["hp"]) / maxf(1.0, float(m["hpm"])), 0.0, 1.0), m["conc"], u.air)
			if sc > 1.01:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Vista strategica: frecce di movimento dei gruppi (piene le proprie, tratteggiate le nemiche avvistate) e obiettivi.
	func _draw_strategic(b, font: Font, st) -> void:
		var cam: Camera3D = b.cam
		var a: float = st.k
		var aa: float = smoothstep(0.35, 0.9, a)   # le frecce compaiono più tardi: in vista operativa coprirebbero le unità
		for ar in st.arrows:
			var f: Vector3 = ar["from"]
			var t: Vector3 = ar["to"]
			if cam.is_position_behind(f) or cam.is_position_behind(t):
				continue
			var p0 := cam.unproject_position(f)
			var p1 := cam.unproject_position(t)
			var L := p0.distance_to(p1)
			if L < 28.0:
				continue
			if aa <= 0.01:
				break
			var col: Color = b.side_color(ar["side"])
			var wid := clampf(6.0 + float(ar["n"]) * 1.1, 8.0, 18.0)
			_arrow(p0, p1, wid, Color(col.lightened(0.15), (0.72 if ar["own"] else 0.45) * aa), Color(0, 0, 0, 0.55 * aa), not ar["own"], ar["atk"])
		for o in st.objectives:
			var pos: Vector3 = o["pos"]
			if cam.is_position_behind(pos):
				continue
			var sp := cam.unproject_position(pos)
			if not Rect2(Vector2.ZERO, size).grow(40.0).has_point(sp):
				continue
			var own: int = o["owner"]
			var fc: Color = Color(0.82, 0.8, 0.72) if own < 0 else b.side_color(own)
			_flag(sp, fc, a)
			var txt: String = o["name"]
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var bx := Rect2(sp + Vector2(-tw * 0.5 - 5.0, 6.0), Vector2(tw + 10.0, 17.0))
			draw_rect(bx, Color(0.07, 0.09, 0.07, 0.78 * a))
			draw_rect(Rect2(bx.position, Vector2(3.0, bx.size.y)), Color(fc, 0.95 * a))
			draw_string(font, bx.position + Vector2(5.0, 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.93, 0.85, a))

	## Freccia larga e leggermente curva da a a b (stile piano di battaglia); `dashed` = solo contorno tratteggiato.
	func _arrow(p0: Vector2, p1: Vector2, w: float, col: Color, edge: Color, dashed: bool, atk: bool) -> void:
		var d := (p1 - p0)
		var L := d.length()
		var dir := d / L
		var nrm := Vector2(-dir.y, dir.x)
		var head := minf(w * 2.4, L * 0.4)
		var ctrl := (p0 + p1) * 0.5 + nrm * L * 0.12
		var tip_base := p1 - dir * head
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var N := 12
		for i in N + 1:
			var t := float(i) / N
			var q := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * ctrl + t * t * tip_base
			var tg := (2.0 * (1.0 - t) * (ctrl - p0) + 2.0 * t * (tip_base - ctrl)).normalized()
			var nn := Vector2(-tg.y, tg.x)
			var hw := w * 0.5 * lerpf(0.55, 1.0, t)
			left.append(q + nn * hw)
			right.append(q - nn * hw)
		var tg_end := (tip_base - ctrl).normalized()
		var ne := Vector2(-tg_end.y, tg_end.x)
		var tip := tip_base + tg_end * head
		var poly := PackedVector2Array()
		poly.append_array(left)
		poly.append(tip_base + ne * w * 1.15)
		poly.append(tip)
		poly.append(tip_base - ne * w * 1.15)
		for i in range(right.size() - 1, -1, -1):
			poly.append(right[i])
		var outline := poly.duplicate()
		outline.append(poly[0])
		if dashed:
			draw_colored_polygon(poly, Color(col, col.a * 0.35))
			for i in range(0, outline.size() - 1, 2):
				draw_line(outline[i], outline[i + 1], Color(col, minf(1.0, col.a * 1.6)), 2.0)
		else:
			# ombra, corpo, contorno
			var sh := PackedVector2Array()
			for q in poly:
				sh.append(q + Vector2(2, 3))
			draw_colored_polygon(sh, Color(0, 0, 0, edge.a * 0.5))
			draw_colored_polygon(poly, col)
			draw_polyline(outline, edge, 1.5)
		if atk:
			# attacco: due tacche trasversali vicino alla punta
			for k in 2:
				var c := tip_base - tg_end * (6.0 + k * 7.0)
				draw_line(c + ne * w * 0.7, c - ne * w * 0.7, Color(1, 1, 1, col.a), 2.0)

	## Bandierina dell'obiettivo: asta, drappo nel colore di chi lo controlla, base a disco.
	func _flag(p: Vector2, col: Color, a: float) -> void:
		draw_circle(p, 5.0, Color(0, 0, 0, 0.5 * a))
		draw_circle(p, 3.2, Color(0.92, 0.9, 0.82, a))
		draw_line(p, p + Vector2(0, -30), Color(0.15, 0.13, 0.1, a), 2.0)
		var fl := PackedVector2Array([p + Vector2(1, -30), p + Vector2(20, -25), p + Vector2(1, -19)])
		var sh := PackedVector2Array([p + Vector2(2.5, -28.5), p + Vector2(21.5, -23.5), p + Vector2(2.5, -17.5)])
		draw_colored_polygon(sh, Color(0, 0, 0, 0.4 * a))
		draw_colored_polygon(fl, Color(col, a))
		draw_polyline(PackedVector2Array([fl[0], fl[1], fl[2], fl[0]]), Color(0, 0, 0, 0.6 * a), 1.0)

	## Notte 3 — contatti: nemici di cui si conosce la posizione ma non il tipo. Gettone "?" pieno nel colore nemico
	## (se l'unità era già stata identificata, il simbolo del tipo resta in piccolo).
	func _draw_contacts(b, font: Font) -> void:
		var sim = b.sim
		if sim.hs < 0 or not b.has_method("is_contact_unit"):
			return
		var col: Color = b.side_color(1 - sim.hs)
		var sc0: float = 1.0 + 0.45 * (b.strat.k if b.strat != null else 0.0)
		var pulse: float = 0.5 + 0.5 * sin(b._wall_time * 3.0)
		for u in sim.units:
			if not b.is_contact_unit(u):
				continue
			var w := BattleTerrain.sim_to_world(u.x, u.y)
			var p := Vector3(w.x, maxf(b.terrain.height(w.x, w.y), 0.0) + (14.0 if u.air else 2.0), w.y)
			if b.cam.is_position_behind(p):
				continue
			var sp: Vector2 = b.cam.unproject_position(p)
			if sp.x < -40 or sp.y < -40 or sp.x > size.x + 40 or sp.y > size.y + 40:
				continue
			var t := String(u.type) if bool(u.id_once[sim.hs]) else ""
			BattleHud.draw_contact(self, font, sp + Vector2(0, -14), col, t, sc0, pulse)

	## Ultime posizioni note dei nemici non più avvistati: pedina sbiadita con "?" e da quanto tempo.
	func _draw_ghosts(b, font: Font) -> void:
		var sim = b.sim
		if sim.hs < 0 or not ("ghosts" in sim):
			return
		var gl = sim.ghosts
		if not (gl is Array) or gl.size() <= sim.hs:
			return
		var col: Color = b.side_color(1 - sim.hs)
		for g in gl[sim.hs]:
			var w := BattleTerrain.sim_to_world(float(g["x"]), float(g["y"]))
			var p := Vector3(w.x, maxf(b.terrain.height(w.x, w.y), 0.0) + 2.0, w.y)
			if b.cam.is_position_behind(p):
				continue
			var sp: Vector2 = b.cam.unproject_position(p)
			if sp.x < -40 or sp.y < -40 or sp.x > size.x + 40 or sp.y > size.y + 40:
				continue
			var age: float = maxf(0.0, sim.time - float(g.get("t", sim.time)))
			var a := clampf(0.95 - age / 40.0, 0.5, 0.95)
			BattleHud.draw_ghost(self, font, sp + Vector2(0, -14), col, String(g.get("type", "")), int(g.get("g", 1)), a, age)

	func _draw_pings(b) -> void:
		for pg in b.pings:
			var t: float = pg["t"]
			if t > 1.2:
				continue
			var p: Vector3 = pg["p"]
			if b.cam.is_position_behind(p):
				continue
			var sp: Vector2 = b.cam.unproject_position(p)
			var c: Color = pg["col"]
			var f := t / 1.2
			draw_arc(sp, 10.0 + 34.0 * f, 0, TAU, 28, Color(c, (1.0 - f) * 0.9), 2.0)
			draw_arc(sp, 6.0 + 18.0 * f, 0, TAU, 20, Color(c, (1.0 - f) * 0.6), 1.2)

	func _draw_floaters(b, font: Font) -> void:
		for fl in b.floaters:
			var t: float = fl["t"]
			var T: float = fl["T"]
			var p: Vector3 = (fl["p"] as Vector3) + Vector3(0, t * 2.5, 0)
			if b.cam.is_position_behind(p):
				continue
			var sp: Vector2 = b.cam.unproject_position(p)
			var a := 1.0 - smoothstep(T * 0.6, T, t)
			var big: bool = fl["big"]
			var fs := 22 if big else 15
			var pop := 1.0 + 0.35 * (1.0 - smoothstep(0.0, 0.15, t))
			fs = int(fs * pop)
			var txt: String = fl["text"]
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var c: Color = fl["col"]
			var q := sp + Vector2(-tw * 0.5, 0)
			draw_string_outline(font, q, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.75 * a))
			draw_string(font, q, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c, a))

	func _draw_toasts(b, font: Font) -> void:
		var y := 100.0
		for t in b.toasts:
			var age: float = t["t"]
			var a := clampf(age / 0.2, 0.0, 1.0) * (1.0 - smoothstep(4.5, 6.0, age))
			var txt: String = t["text"]
			var fs := 15
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var r := Rect2(Vector2(size.x * 0.5 - tw * 0.5 - 12, y), Vector2(tw + 24, 24))
			draw_rect(r, Color(0.03, 0.04, 0.04, 0.78 * a))
			draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(t["col"], a))
			draw_string(font, r.position + Vector2(12, 17), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(t["col"], a))
			y += 28.0

	## Suggerimento sotto il cursore: copertura del terreno, fianco esposto del nemico.
	func _draw_hover(b, font: Font) -> void:
		var txt: String = b.hover_info
		if txt == "" or b.drag_active:
			return
		var ls := txt.split("\n")
		var fs := 13
		var w := 0.0
		for l in ls:
			w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var mp: Vector2 = b._mouse + Vector2(18, 20)
		var h := ls.size() * 17.0 + 6.0
		if mp.x + w + 16 > size.x:
			mp.x = size.x - w - 16
		if mp.y + h > size.y:
			mp.y -= h + 30
		var r := Rect2(mp, Vector2(w + 14, h))
		draw_rect(r, Color(0.03, 0.045, 0.04, 0.85))
		draw_rect(r, Color(0.55, 0.6, 0.45, 0.5), false, 1.0)
		for i in ls.size():
			var c := BattleHud.TXT if i == 0 else Color(1.0, 0.82, 0.45)
			draw_string(font, mp + Vector2(7, 15 + i * 17), ls[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

	## Frecce ai bordi dello schermo verso le proprie unità colpite fuori vista.
	func _draw_alerts(b, font: Font) -> void:
		if b.alerts.is_empty():
			return
		var sz := size
		var c := sz * 0.5
		var pulse := 0.6 + 0.4 * sin(b._wall_time * 8.0)
		var shown := 0
		for ai in range(b.alerts.size() - 1, -1, -1):
			if shown >= 3:
				break
			var a: Dictionary = b.alerts[ai]
			var p: Vector3 = a["p"]
			var dir: Vector2
			if b.cam.is_position_behind(p):
				var lp: Vector3 = b.cam.global_transform.affine_inverse() * p
				dir = Vector2(signf(lp.x) if absf(lp.x) > 0.01 else 0.0, 1.0).normalized()
			else:
				var sp: Vector2 = b.cam.unproject_position(p)
				if sp.x > 0 and sp.y > 0 and sp.x < sz.x and sp.y < sz.y:
					continue
				dir = sp - c
				if dir.length() < 1.0:
					continue
				dir = dir.normalized()
			var m := Vector2(sz.x * 0.5 - 70.0, sz.y * 0.5 - 120.0)
			var k := minf(m.x / maxf(0.001, absf(dir.x)), m.y / maxf(0.001, absf(dir.y)))
			var q := c + dir * k
			shown += 1
			var al: float = clampf(float(a["t"]), 0.0, 1.0) * pulse
			var col := Color(1.0, 0.3, 0.22, al)
			var n := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([q + dir * 16.0, q - dir * 6.0 + n * 11.0, q - dir * 6.0 - n * 11.0]), col)
			var o := q - dir * 24.0
			draw_circle(o, 13.0, Color(0.06, 0.02, 0.02, 0.7 * al))
			draw_arc(o, 13.0, 0, TAU, 20, col, 2.0)
			draw_string(font, o + Vector2(-3, 7), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 0.92, 0.88, al))

## Simbolo del tipo d'unità (stile NATO semplificato) centrato in p.
static func draw_type_glyph(ci: CanvasItem, t: String, p: Vector2, s: float, c: Color) -> void:
	match t:
		"inf":
			ci.draw_line(p + Vector2(-s * 1.2, -s * 0.7), p + Vector2(s * 1.2, s * 0.7), c, 1.6)
			ci.draw_line(p + Vector2(-s * 1.2, s * 0.7), p + Vector2(s * 1.2, -s * 0.7), c, 1.6)
		"tank":
			var pts := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				pts.append(p + Vector2(cos(a) * s * 1.05, sin(a) * s * 0.55))
			ci.draw_polyline(pts, c, 1.6, true)
		"art":
			ci.draw_circle(p, s * 0.38, c)
		"aa":
			ci.draw_arc(p + Vector2(0, s * 0.45), s * 0.85, PI, TAU, 12, c, 1.6)
			ci.draw_line(p + Vector2(0, s * 0.45), p + Vector2(0, -s * 0.5), c, 1.4)
		"heli":
			ci.draw_line(p + Vector2(-s, -s * 0.5), p + Vector2(s, s * 0.5), c, 1.5)
			ci.draw_line(p + Vector2(-s, s * 0.5), p + Vector2(s, -s * 0.5), c, 1.5)
			ci.draw_line(p + Vector2(-s, -s * 0.5), p + Vector2(-s, s * 0.5), c, 1.5)
			ci.draw_line(p + Vector2(s, -s * 0.5), p + Vector2(s, s * 0.5), c, 1.5)
		"jet":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.8), p + Vector2(s * 0.8, s * 0.6), p + Vector2(-s * 0.8, s * 0.6)]), c)
		"drone":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.6), p + Vector2(s * 0.6, 0), p + Vector2(0, s * 0.6), p + Vector2(-s * 0.6, 0)]), c)
		"bunker":
			ci.draw_rect(Rect2(p - Vector2(s * 0.7, s * 0.45), Vector2(s * 1.4, s * 0.9)), c, false, 1.6)
			ci.draw_line(p + Vector2(-s * 0.7, -s * 0.45), p + Vector2(0, -s * 0.85), c, 1.4)
			ci.draw_line(p + Vector2(s * 0.7, -s * 0.45), p + Vector2(0, -s * 0.85), c, 1.4)
		_:
			ci.draw_rect(Rect2(p - Vector2(s * 0.6, s * 0.6), Vector2(s * 1.2, s * 1.2)), c, false, 1.5)

## Cornice della pedina: rettangolo per le proprie unità, ottagono (angoli smussati) per le nemiche.
static func _counter_frame(own: bool, p: Vector2, hw: float, hh: float) -> PackedVector2Array:
	if own:
		return PackedVector2Array([p + Vector2(-hw, -hh), p + Vector2(hw, -hh), p + Vector2(hw, hh), p + Vector2(-hw, hh)])
	var k := hh * 0.55
	return PackedVector2Array([p + Vector2(-hw + k, -hh), p + Vector2(hw - k, -hh), p + Vector2(hw, -hh + k), p + Vector2(hw, hh - k),
		p + Vector2(hw - k, hh), p + Vector2(-hw + k, hh), p + Vector2(-hw, hh - k), p + Vector2(-hw, -hh + k)])

## Pedina tattica (vista d'insieme): colore della fazione, simbolo del tipo, numero di unità, integrità.
static func draw_counter(ci: CanvasItem, font: Font, p: Vector2, col: Color, t: String, n: int, own: bool, sel: bool, hov: bool, a: float, frac: float, conc: bool, air: bool) -> void:
	var hw := 15.0
	var hh := 10.0
	var fr := _counter_frame(own, p, hw, hh)
	var fill := Color(col.r * 0.42, col.g * 0.42, col.b * 0.42, 0.9 * a)
	if conc:
		fill.a *= 0.55
	# ombra
	var sh := PackedVector2Array()
	for q in fr:
		sh.append(q + Vector2(1.5, 2.0))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.45 * a))
	ci.draw_colored_polygon(fr, fill)
	# banda della fazione in alto
	ci.draw_rect(Rect2(p + Vector2(-hw + 3, -hh + 2), Vector2(hw * 2 - 6, 2.5)), Color(col.lightened(0.25), 0.95 * a))
	var edge := Color(col.lightened(0.45), a)
	var ew := 1.5
	if sel:
		edge = Color(0.55, 1.0, 0.6, a)
		ew = 2.5
	elif hov:
		edge = Color(1.0, 0.4, 0.32, a)
		ew = 2.5
	var lp := fr.duplicate()
	lp.append(fr[0])
	ci.draw_polyline(lp, edge, ew, true)
	if air:
		# velivoli: piccolo tratto di quota sopra la pedina
		ci.draw_line(p + Vector2(-5, -hh - 3), p + Vector2(5, -hh - 3), Color(edge, a * 0.8), 1.5)
	draw_type_glyph(ci, t, p + Vector2(0, 1.5), 6.0, Color(1, 1, 1, 0.95 * a))
	if n > 1:
		var txt := str(n)
		var fs := 12
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tr := Rect2(p + Vector2(hw - 3, hh - 9), Vector2(tw + 6, 13))
		ci.draw_rect(tr, Color(0.02, 0.03, 0.03, 0.88 * a))
		ci.draw_rect(tr, Color(edge, a * 0.8), false, 1.0)
		ci.draw_string(font, tr.position + Vector2(3, 10.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	# integrità
	draw_integrity(ci, p + Vector2(-hw, hh + 2), hw * 2.0, 4.0, frac, a, false)
	if conc:
		draw_glyph(ci, "leaf", p + Vector2(-hw - 7, -hh + 3), 12.0, Color(0.6, 1.0, 0.55, a))

## Barra d'integrità unica per tutta la battaglia: fondo scuro, riempimento verde/ambra/rosso, tacche ogni 25%
## (si legge la quantità anche da lontano), bordo sottile. `enemy` = tinta leggermente rossa.
static func draw_integrity(ci: CanvasItem, p: Vector2, w: float, h: float, frac: float, a: float, enemy: bool) -> void:
	ci.draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0.02, 0.03, 0.02, 0.8 * a))
	var hc := Color(0.42, 0.86, 0.38) if frac > 0.6 else (Color(0.96, 0.74, 0.22) if frac > 0.3 else Color(0.94, 0.28, 0.18))
	if enemy:
		hc = hc.lerp(Color(1, 0.35, 0.3), 0.3)
	ci.draw_rect(Rect2(p, Vector2(w * clampf(frac, 0.0, 1.0), h)), Color(hc, a))
	ci.draw_rect(Rect2(p, Vector2(w * clampf(frac, 0.0, 1.0), 1.0)), Color(1, 1, 1, 0.3 * a))
	for k in range(1, 4):
		var x := p.x + w * k / 4.0
		ci.draw_line(Vector2(x, p.y), Vector2(x, p.y + h), Color(0.02, 0.03, 0.02, 0.85 * a), 1.0)

## Cornice "da tavolo di comando": angoli a L color ambra attorno a un pannello (figlio del pannello, disegna fuori).
class Brackets extends Control:
	var pad := Vector2.ZERO
	var col := Color(0.95, 0.7, 0.24, 0.75)
	func _init(padding := Vector2.ZERO) -> void:
		pad = padding
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		var r := Rect2(-pad - Vector2(2, 2), size + pad * 2.0 + Vector2(4, 4))
		var L := 11.0
		var w := 2.0
		for c in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
			var o: Vector2 = c[0]
			var d: Vector2 = c[1]
			draw_line(o, o + Vector2(L * d.x, 0), col, w)
			draw_line(o, o + Vector2(0, L * d.y), col, w)
		# tacca centrale in alto (righello)
		draw_line(Vector2(r.get_center().x - 6, r.position.y), Vector2(r.get_center().x + 6, r.position.y), Color(col, col.a * 0.6), 1.0)

## Contatto (notte 3): gettone pieno con "?" — posizione nota, tipo ignoto (`t` = tipo ricordato, "" se mai identificata).
static func draw_contact(ci: CanvasItem, font: Font, p: Vector2, col: Color, t: String, sc: float, pulse: float) -> void:
	var hw := 13.0 * sc
	var hh := 10.0 * sc
	var fr := PackedVector2Array([p + Vector2(0, -hh - 3), p + Vector2(hw, 0), p + Vector2(0, hh + 3), p + Vector2(-hw, 0)])
	var sh := PackedVector2Array()
	for q in fr:
		sh.append(q + Vector2(1.5, 2.0))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	ci.draw_colored_polygon(fr, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.9))
	var ec := Color(col.lightened(0.45), 0.75 + 0.25 * pulse)
	for i in fr.size():
		ci.draw_line(fr[i], fr[(i + 1) % fr.size()], ec, 1.6)
	var fs := int(17 * sc)
	var tw := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(font, p + Vector2(-tw * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
	ci.draw_string(font, p + Vector2(-tw * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.93, 0.7))
	if t != "":
		draw_type_glyph(ci, t, p + Vector2(0, hh + 9.0 * sc), 4.0 * sc, Color(1, 1, 1, 0.75))

## Fantasma: ultima posizione nota di un nemico (cornice tratteggiata, "?" ed età).
static func draw_ghost(ci: CanvasItem, font: Font, p: Vector2, col: Color, t: String, n: int, a: float, age: float) -> void:
	var hw := 15.0
	var hh := 10.0
	var fr := _counter_frame(false, p, hw, hh)
	ci.draw_colored_polygon(fr, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.45 * a))
	var ec := Color(col.lightened(0.4), a)
	for i in fr.size():
		ci.draw_dashed_line(fr[i], fr[(i + 1) % fr.size()], ec, 1.3, 3.0)
	draw_type_glyph(ci, t, p + Vector2(-4, 1.5), 4.5, Color(1, 1, 1, 0.7 * a))
	ci.draw_string(font, p + Vector2(4, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.9, 0.6, a + 0.2))
	var txt := "%ds" % int(age)
	if n > 1:
		txt = "%d · %s" % [n, txt]
	var fs := 10
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(font, p + Vector2(-tw * 0.5, hh + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, a))
	ci.draw_string(font, p + Vector2(-tw * 0.5, hh + 12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.8, a + 0.15))

# ---------------------------------------------------------------------------- pulsanti con icona e ricarica
## Icone dell'interfaccia principale (UIIcon dell'Agente E) usate dove esistono; le altre sono disegnate qui con lo stesso
## stile (griglia 16×16, tratto chiaro).
const UI_KINDS := ["pause", "play", "target", "jet", "fog", "art", "alert"]
const TEXTC := Color("#dbe5d6")
const AMBER := Color("#f2b13c")

static func draw_glyph(ci: CanvasItem, k: String, c: Vector2, s: float, col: Color) -> void:
	var u := s / 16.0
	var w := 1.6 * u
	match k:
		"all":
			for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = c + d * 6.5 * u
				ci.draw_line(q, q - Vector2(d.x * 3.5 * u, 0), col, w)
				ci.draw_line(q, q - Vector2(0, d.y * 3.5 * u), col, w)
			for i in 3:
				ci.draw_circle(c + Vector2(-3.2 + i * 3.2, 0) * u, 1.3 * u, col)
		"stop":
			var pts := PackedVector2Array()
			for i in 8:
				var a := PI / 8.0 + i * TAU / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * 7.0 * u)
			ci.draw_colored_polygon(pts, Color(col, col.a * 0.25))
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w, true)
			ci.draw_line(c + Vector2(-3.5, 0) * u, c + Vector2(3.5, 0) * u, col, 2.0 * u)
		"hold":
			# scudo con barra: le unità restano sul posto
			var sh := PackedVector2Array([c + Vector2(-6, -6.5) * u, c + Vector2(6, -6.5) * u, c + Vector2(6, -0.5) * u,
				c + Vector2(0, 7.5) * u, c + Vector2(-6, -0.5) * u])
			ci.draw_colored_polygon(sh, Color(col, col.a * 0.25))
			sh.append(sh[0])
			ci.draw_polyline(sh, col, w, true)
			ci.draw_line(c + Vector2(-3.2, -1.5) * u, c + Vector2(3.2, -1.5) * u, col, 2.0 * u)
		"auto":
			for o in [-3.5, 2.5]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(o - 3.5, -5.5) * u, c + Vector2(o + 3.5, 0) * u, c + Vector2(o - 3.5, 5.5) * u]), col)
			ci.draw_rect(Rect2(c + Vector2(6.5, -5.5) * u, Vector2(1.6, 11) * u), col)
		"retreat":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7.5, -2) * u, c + Vector2(-2, -7.5) * u, c + Vector2(-2, 3.5) * u]), col)
			ci.draw_arc(c + Vector2(-2, 3) * u, 5.0 * u, -PI * 0.5, PI * 0.5, 12, col, 2.2 * u)
			ci.draw_line(c + Vector2(-2, 8) * u, c + Vector2(-6, 8) * u, col, 2.2 * u)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-5, -6) * u, Vector2(3.4, 12) * u), col)
			ci.draw_rect(Rect2(c + Vector2(1.6, -6) * u, Vector2(3.4, 12) * u), col)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.5, -6.5) * u, c + Vector2(6.5, 0) * u, c + Vector2(-4.5, 6.5) * u]), col)
		"target":
			ci.draw_arc(c, 6 * u, 0, TAU, 20, col, 1.3 * u)
			ci.draw_arc(c, 2.5 * u, 0, TAU, 12, col, 1.3 * u)
		"fog":
			ci.draw_circle(c + Vector2(-3, -0.5) * u, 3.2 * u, col)
			ci.draw_circle(c + Vector2(1, -2.5) * u, 4 * u, col)
			ci.draw_circle(c + Vector2(4.5, 0) * u, 2.8 * u, col)
		"jet":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * u, c + Vector2(8, 3) * u, c + Vector2(0, 5) * u, c + Vector2(-8, 3) * u]), col)
		"leaf":
			# foglia: unità nascosta dalla copertura
			var lf := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var y := lerpf(6.5, -6.5, t)
				lf.append(c + Vector2(sin(t * PI) * 4.6 - 0.5, y) * u)
			for i in range(11, 0, -1):
				var t := float(i) / 12.0
				var y := lerpf(6.5, -6.5, t)
				lf.append(c + Vector2(-sin(t * PI) * 3.2 - 0.5, y) * u)
			ci.draw_colored_polygon(lf, Color(col, col.a * 0.55))
			lf.append(lf[0])
			ci.draw_polyline(lf, Color(0, 0, 0, col.a * 0.6), 1.0, true)
			ci.draw_line(c + Vector2(-0.5, 7.5) * u, c + Vector2(-0.5, -5.5) * u, col, 1.2 * u)
		"area":
			# fuoco d'area: mirino con punti d'impatto sparsi
			ci.draw_arc(c, 6.5 * u, 0, TAU, 20, col, 1.3 * u)
			for d in [Vector2(-2.5, -2), Vector2(2.6, -1), Vector2(0.4, 2.8), Vector2(-3.2, 2.2), Vector2(3.4, 2.9)]:
				ci.draw_circle(c + d * u, 1.1 * u, col)
		_:
			ci.draw_circle(c, 4 * u, col)

class CmdButton extends Button:
	var kind := ""
	var key := ""
	var cd := 0.0          # 0..1: ricarica rimanente (settore scuro sull'icona)
	var active := false    # stato acceso (es. "mantieni posizione" sui selezionati)
	var _ic: Control = null
	var _over: Control
	const IS := 22.0

	func setup(k: String, hotkey: String) -> void:
		kind = k
		key = hotkey
		var IC = BattleProps.ext("UIIcon")
		if IC != null and k in BattleHud.UI_KINDS:
			_ic = IC.new()
			_ic.set("kind", k)
			_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_ic)
		_over = Control.new()
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_over)
		_over.draw.connect(_draw_over)
		resized.connect(_place)
		_place()

	func set_kind(k: String) -> void:
		if k == kind:
			return
		kind = k
		if _ic != null:
			_ic.set("kind", k)
		queue_redraw()

	func set_state(c: float, on: bool) -> void:
		if absf(c - cd) > 0.004 or on != active:
			cd = c
			active = on
			_over.queue_redraw()
			queue_redraw()

	func _icon_rect() -> Rect2:
		return Rect2(Vector2(9, (size.y - IS) * 0.5), Vector2(IS, IS))

	func _place() -> void:
		if _ic != null:
			_ic.position = _icon_rect().position
			_ic.size = Vector2(IS, IS)
		if _over != null:
			_over.queue_redraw()

	func _draw() -> void:
		var r := _icon_rect()
		if active:
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(BattleHud.AMBER, 0.14))
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(BattleHud.AMBER, 0.7), false, 1.5)
		if _ic != null:
			_ic.modulate = Color(1, 1, 1, 0.4 if disabled and cd <= 0.0 else 1.0)
		else:
			var col := BattleHud.AMBER if active else BattleHud.TEXTC
			BattleHud.draw_glyph(self, kind, r.get_center(), IS, Color(col, 0.4 if disabled and cd <= 0.0 else 1.0))

	func _draw_over() -> void:
		var r := _icon_rect()
		var c := r.get_center()
		var rad := IS * 0.62
		if cd > 0.0:
			# settore scuro = tempo rimanente, arco chiaro = avanzamento della ricarica
			var pts := PackedVector2Array([c])
			var n := maxi(3, int(28 * cd))
			for i in n + 1:
				var a := -PI * 0.5 + TAU * cd * float(i) / n
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			_over.draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
			_over.draw_arc(c, rad, -PI * 0.5 + TAU * cd, PI * 1.5, 32, Color(BattleHud.AMBER, 0.95), 2.0, true)
		if key != "":
			var font := get_theme_default_font()
			var fs := 10
			var tw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var br := Rect2(Vector2(size.x - tw - 9, 3), Vector2(tw + 6, 13))
			_over.draw_rect(br, Color(0, 0, 0, 0.45))
			_over.draw_rect(br, Color(0.75, 0.8, 0.65, 0.5), false, 1.0)
			_over.draw_string(font, br.position + Vector2(3, 10.5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.94, 0.88, 0.95 if not disabled else 0.5))

static func _sb(bg: Color, edge: Color, r := 5, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(mini(r, 3))   # Fase 5: angoli quasi vivi, stile strumentazione
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s

func _anchor(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b

func _label(text: String, size: int, col := TXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func build(b) -> void:
	battle = b
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = Overlay.new()
	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	_build_top()
	_build_bottom()
	_build_msg()

func _build_top() -> void:
	top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", _sb(BG, EDGE, 6, 12))
	_anchor(top, Control.PRESET_CENTER_TOP, -470, 8, 470, 90)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(top)
	top.add_child(Brackets.new(Vector2(12, 7.2)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	for i in 2:
		var S: Dictionary = battle.sim.sides[i]
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(300, 0)
		v.add_theme_constant_override("separation", 3)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_END if i == 1 else BoxContainer.ALIGNMENT_BEGIN
		var sw := ColorRect.new()
		sw.color = S["color"]
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var role := "ATTACCO" if i == 0 else "DIFESA"
		var nm := _label("%s · %s" % [role, S["name"]], 15, TXT)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 1 else HORIZONTAL_ALIGNMENT_LEFT
		var nv: int = battle.vet(i)
		var stars: Control = Stars.new(nv, 6.5) if nv > 0 else null
		if stars != null:
			stars.tooltip_text = "Veterani: %d stell%s (+%d%% attacco)" % [nv, "a" if nv == 1 else "e", nv * 6]
			nm.size_flags_horizontal = Control.SIZE_FILL
			nm.clip_text = false
		if i == 0:
			h.add_child(sw); h.add_child(nm)
			if stars != null: h.add_child(stars)
		else:
			if stars != null: h.add_child(stars)
			h.add_child(nm); h.add_child(sw)
		v.add_child(h)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(300, 9)
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = 1.0
		bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN if i == 1 else ProgressBar.FILL_BEGIN_TO_END
		var fill := StyleBoxFlat.new()
		fill.bg_color = S["color"]
		fill.set_corner_radius_all(3)
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color(0, 0, 0, 0.5)
		bgs.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bgs)
		v.add_child(bar)
		var cnt := _label("", 13, DIM)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 1 else HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(cnt)
		side_box.append({"bar": bar, "count": cnt})
		if i == 0:
			row.add_child(v)
			var mid := VBoxContainer.new()
			mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			mid.add_theme_constant_override("separation", 0)
			lbl_title = _label("", 19, Color(1, 0.95, 0.8))
			lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_sub = _label("", 13, DIM)
			lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_time = _label("00:00", 22, Color(0.95, 0.85, 0.45))
			lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(lbl_title)
			mid.add_child(lbl_sub)
			mid.add_child(lbl_time)
			row.add_child(mid)
		else:
			row.add_child(v)
	var st: Dictionary = battle.setup
	lbl_title.text = String(st.get("terrName", "Battaglia")).to_upper()
	var tname := String(Data.TERRAINS[battle.sim.tkey]["name"])
	lbl_sub.text = tname + (" · costa" if battle.sim.sea else "") + ((" · " + battle.mood_text) if battle.mood_text != "" else "")
	lbl_time.tooltip_text = "Tempo rimanente: allo scadere dei %d minuti decide chi tiene più obiettivi (parità: il difensore)." % int(BattleRules.BATTLE_T / 60.0)
	# bonus del comando diretto, scritto (docs/omogeneita.md §3)
	for i in 2:
		var S: Dictionary = battle.sim.sides[i]
		if bool(S.get("manual", false)) and battle.sim.hs == i:
			var extra := _label("Comando diretto: +10% attacco · esperienza doppia", 11, Color(0.75, 0.95, 0.7))
			extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 1 else HORIZONTAL_ALIGNMENT_LEFT
			side_box[i]["count"].get_parent().add_child(extra)
	_build_objectives()

## Riquadro degli obiettivi (sotto il pannello in alto): una riga per obiettivo con chi lo tiene e il contatore di conquista.
var obj_panel: PanelContainer
var obj_rows: Array = []   # [{dot: ColorRect, name: Label, bar: ProgressBar, state: Label}]
var obj_hint: Label

func _build_objectives() -> void:
	var objs: Array = battle.sim.objectives
	if objs.is_empty():
		return
	obj_panel = PanelContainer.new()
	obj_panel.add_theme_stylebox_override("panel", _sb(BG, EDGE, 6, 10))
	_anchor(obj_panel, Control.PRESET_CENTER_TOP, -250, 96, 250, 96 + 26 + objs.size() * 20)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	obj_panel.tooltip_text = "Obiettivi: tieni unità di terra nel raggio senza nemici per %d s per conquistarne uno.\nAllo scadere del tempo vince l'attaccante se ne tiene più del difensore." % int(BattleRules.OBJ_HOLD)
	root.add_child(obj_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	obj_panel.add_child(v)
	var hdr := HBoxContainer.new()
	var t := _label("OBIETTIVI", 12, Color(0.95, 0.85, 0.45), true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(t)
	obj_hint = _label("", 11, DIM)
	obj_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(obj_hint)
	v.add_child(hdr)
	for o in objs:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var nm := _label(String(o["name"]), 12, TXT)
		nm.custom_minimum_size.x = 150
		h.add_child(nm)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(140, 7)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.step = 0.01
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color(0, 0, 0, 0.5)
		bgs.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bgs)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.9, 0.8, 0.4)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		h.add_child(bar)
		var stt := _label("", 11, DIM)
		stt.custom_minimum_size.x = 120
		stt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(stt)
		v.add_child(h)
		obj_rows.append({"dot": dot, "name": nm, "bar": bar, "state": stt, "fill": fill})

func _refresh_objectives() -> void:
	if obj_panel == null:
		return
	var sim: BattleSim = battle.sim
	var objs: Array = sim.objectives
	var hs := sim.hs
	for i in mini(objs.size(), obj_rows.size()):
		var o: Dictionary = objs[i]
		var r: Dictionary = obj_rows[i]
		var own: int = int(o["owner"])
		(r["dot"] as ColorRect).color = Color(0.82, 0.8, 0.72) if own < 0 else battle.side_color(own)
		var hold: Array = o["hold"]
		var taking := 0 if float(hold[0]) > 0.0 else (1 if float(hold[1]) > 0.0 else -1)
		var bar: ProgressBar = r["bar"]
		var txt := ""
		if bool(o["contested"]):
			txt = "conteso"
			bar.value = 0.0
		elif taking >= 0:
			bar.value = clampf(float(hold[taking]) / BattleRules.OBJ_HOLD, 0.0, 1.0)
			(r["fill"] as StyleBoxFlat).bg_color = battle.side_color(taking).lightened(0.2)
			txt = ("conquista in %ds" % ceili(BattleRules.OBJ_HOLD - float(hold[taking])))
			if hs >= 0:
				txt = ("tuo tra %ds" if taking == hs else ("perso tra %ds" if own == hs else "al nemico tra %ds")) % ceili(BattleRules.OBJ_HOLD - float(hold[taking]))
		else:
			bar.value = 0.0
			if own < 0:
				txt = "neutro"
			elif hs >= 0:
				txt = "tenuto da te" if own == hs else "tenuto dal nemico"
			else:
				txt = "attaccante" if own == 0 else "difensore"
		(r["state"] as Label).text = txt
	var held := sim.objectives_held()
	var left := maxf(0.0, BattleRules.BATTLE_T - sim.time)
	var eta0 := sim.reinf_eta(0)
	var eta1 := sim.reinf_eta(1)
	var hint := "attaccante %d · difensore %d" % [held[0], held[1]]
	if hs >= 0:
		hint = "tu %d · nemico %d" % [held[hs], held[1 - hs]]
	# notte 3: eventi annunciati con conto alla rovescia (attacco aereo)
	if "pending" in sim:
		for pe in sim.pending:
			if String(pe["kind"]) == "air":
				var who := "attacco aereo" if (hs < 0 or int(pe["side"]) == hs) else "ATTACCO AEREO NEMICO"
				hint = "%s tra %ds · " % [who, ceili(maxf(0.0, float(pe["t"]) - sim.time))] + hint
	if hs >= 0:
		var mine_eta := eta0 if hs == 0 else eta1
		var en_eta := eta1 if hs == 0 else eta0
		if mine_eta >= 0.0:
			hint = "rinforzi tra %ds · " % ceili(mine_eta) + hint
		elif en_eta >= 0.0:
			hint = "rinforzi nemici tra %ds · " % ceili(en_eta) + hint
	if sim.ending == null and left < 60.0:
		hint = "allo scadere decidono gli obiettivi · " + hint
	obj_hint.text = hint
	pause_lbl = _label("PAUSA", 34, Color(1, 0.82, 0.25))
	_anchor(pause_lbl, Control.PRESET_CENTER_TOP, -200, 118, 200, 160)
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.visible = false
	root.add_child(pause_lbl)
	mode_lbl = _label("", 16, Color(1, 0.75, 0.4))
	_anchor(mode_lbl, Control.PRESET_CENTER_TOP, -400, 124, 400, 150)
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(mode_lbl)

func _build_bottom() -> void:
	var hs: int = battle.sim.hs
	# pannello selezione + comandi (in basso a sinistra)
	sel_panel = PanelContainer.new()
	sel_panel.add_theme_stylebox_override("panel", _sb(BG, EDGE, 6, 12))
	_anchor(sel_panel, Control.PRESET_BOTTOM_LEFT, 10, -206 if hs >= 0 else -118, 790, -10)
	sel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(sel_panel)
	sel_panel.add_child(Brackets.new(Vector2(12, 7.2)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	sel_panel.add_child(v)
	sel_title = _label("", 16, Color(1, 0.95, 0.8))
	v.add_child(sel_title)
	sel_body = RichTextLabel.new()
	sel_body.bbcode_enabled = true
	sel_body.fit_content = true
	sel_body.scroll_active = false
	sel_body.custom_minimum_size = Vector2(600, 62)
	sel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sel_body.add_theme_font_size_override("normal_font_size", 14)
	sel_body.add_theme_font_size_override("bold_font_size", 14)
	sel_body.add_theme_color_override("default_color", TXT)
	sel_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sel_body)
	if hs >= 0:
		cmd_row = HBoxContainer.new()
		cmd_row.add_theme_constant_override("separation", 5)
		v.add_child(cmd_row)
		_btn(cmd_row, "all", "Tutte", "Seleziona tutte le tue unità (Ctrl+A).\nDoppio clic su un'unità: tutte quelle dello stesso tipo.", "all", "^A")
		_btn(cmd_row, "amove", "Attacco", "Attacco in movimento (G): avanza verso il punto ingaggiando i nemici lungo il percorso.\nPremi G (o questo pulsante) e poi clic sinistro sul terreno.", "target", "G")
		_btn(cmd_row, "stop", "Alt", "Alt (H): ferma le unità selezionate sul posto.\nDa ferme ingaggiano comunque i nemici vicini.", "stop", "H")
		_btn(cmd_row, "hold", "Posizione", "Mantieni posizione (T): le unità selezionate restano dove sono e sparano solo\nai nemici a tiro, senza inseguirli. Premi di nuovo per sbloccarle.\nUn nuovo ordine di movimento annulla la consegna.", "hold", "T")
		_btn(cmd_row, "smoke", "Fumo", "Cortina fumogena (F): le unità di terra selezionate lanciano fumo.\nPer %d s subiscono il %d%% di danni in meno dal fuoco diretto\n(non dall'artiglieria né dalle bombe). Ricarica %d s." % [int(BattleSim.SMOKE_T), roundi((1.0 - BattleSim.SMOKE_MUL) * 100.0), int(BattleSim.SMOKE_CD)], "fog", "F")
		if battle.sim.has_method("order_fire_area"):
			_btn(cmd_row, "area", "Fuoco area", "Fuoco d'area (X): l'artiglieria selezionata bombarda un punto anche senza bersagli avvistati,\ncon dispersione larga, finché non riceve un altro ordine. Utile su boschi e città sospetti.", "area", "X")
		if int(battle.sim.sides[hs]["support"]) > 0:
			_btn(cmd_row, "barrage", "Sbarram.", "Sbarramento d'artiglieria di supporto (B): %d salve su un'area, poi clic sul bersaglio.\nRicarica %d s." % [BattleSim.BARRAGE_SALVOS, int(BattleSim.BARRAGE_CD)], "art", "B")
		if int(battle.sim.sides[hs]["air_uses"]) > 0:
			_btn(cmd_row, "air", "Aereo", "Supporto aereo (J): un caccia bombarda l'area indicata %d s dopo la chiamata\n(danno d'area moderato, solo unità di terra). Un solo uso per battaglia." % int(BattleSim.AIR_DELAY), "jet", "J")
	# pulsanti di battaglia (in alto a destra)
	btn_row = VBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	_anchor(btn_row, Control.PRESET_TOP_RIGHT, -236, 10, -10, 200)
	root.add_child(btn_row)
	_btn(btn_row, "pause", "Pausa", "Pausa / riprendi (P o Spazio).\nIn pausa puoi comunque selezionare e dare ordini.", "pause", "P")
	_btn(btn_row, "auto", "Risolvi in automatico", "Calcola il resto dello scontro in base alla forza rimasta\n(le perdite subite finora restano).", "auto")
	_btn(btn_row, "photo", "Foto  (F10)", "Modalità foto (F10): mette in pausa, nasconde l'interfaccia e libera la telecamera.\nWASD muove, Q/E quota, tasto destro + mouse guarda, rotella zoom.\nInvio scatta e salva un PNG nella cartella utente del gioco; Esc esce.", "")
	if hs == 0:
		_btn(btn_row, "retreat", "Ritirata", "Ritirata ordinata: i reparti ripiegano verso il tuo bordo del campo.\nChi lo raggiunge è salvo e torna a casa; chi resta combatte.\nIl territorio resta al difensore.", "retreat")
	# minimappa (in basso a destra)
	minimap = Minimap.new()
	minimap.hud = self
	_anchor(minimap, Control.PRESET_BOTTOM_RIGHT, -330, -196, -10, -16)
	root.add_child(minimap)
	minimap.setup()
	minimap.add_child(Brackets.new(Vector2(0, 0)))
	var mm_lbl := _label("Minimappa · clic: sposta la vista · destro: muovi", 11, DIM)
	_anchor(mm_lbl, Control.PRESET_BOTTOM_RIGHT, -330, -15, -10, 0)
	mm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(mm_lbl)
	# avviso "sotto attacco"
	alert_btn = _btn(null, "alert", "Unità sotto attacco!", "Sposta la vista sull'ultima unità colpita fuori schermo (V)", "alert", "V")
	alert_btn.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	_anchor(alert_btn, Control.PRESET_BOTTOM_RIGHT, -330, -240, -10, -204)
	root.add_child(alert_btn)
	alert_btn.visible = false

func _btn(parent: Control, id: String, text: String, tip := "", icon := "", key := "") -> Button:
	var b: Button = CmdButton.new() if icon != "" else Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 15)
	var hot := Color(0.62, 0.32, 0.18, 0.95) if id == "retreat" else Color(0.2, 0.27, 0.2, 0.95)
	var base := Color(0.08, 0.11, 0.09, 0.9)
	if id == "start":
		hot = Color(0.25, 0.45, 0.22, 0.98)
		base = Color(0.16, 0.3, 0.14, 0.95)
	elif id == "alert":
		hot = Color(0.5, 0.15, 0.1, 0.95)
		base = Color(0.25, 0.06, 0.05, 0.9)
	var sbs := [_sb(base, Color(0.55, 0.62, 0.45, 0.5), 5, 12), _sb(hot, Color(0.8, 0.85, 0.6, 0.7), 5, 12),
		_sb(hot.darkened(0.3), Color(0.9, 0.9, 0.7, 0.8), 5, 12), _sb(Color(0.06, 0.07, 0.07, 0.75), Color(0.3, 0.3, 0.3, 0.4), 5, 12)]
	if icon != "":
		for sb in sbs:
			(sb as StyleBoxFlat).content_margin_left = 37
			(sb as StyleBoxFlat).content_margin_right = 12 + (7 * key.length() if key != "" else 0)
		b.custom_minimum_size = Vector2(0, 42)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", sbs[0])
	b.add_theme_stylebox_override("hover", sbs[1])
	b.add_theme_stylebox_override("pressed", sbs[2])
	b.add_theme_stylebox_override("disabled", sbs[3])
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	b.pressed.connect(func(): pressed.emit(id))
	if parent != null:
		parent.add_child(b)
	if b is CmdButton:
		(b as CmdButton).setup(icon, key)
	buttons[id] = b
	return b

func _build_deploy() -> void:
	deploy_panel = PanelContainer.new()
	deploy_panel.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.07, 0.05, 0.88), Color(0.6, 0.85, 0.5, 0.55), 6, 16))
	_anchor(deploy_panel, Control.PRESET_CENTER_TOP, -380, 100, 380, 196)
	deploy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(deploy_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	deploy_panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	deploy_title = _label("SCHIERAMENTO", 20, Color(0.75, 1.0, 0.65))
	v.add_child(deploy_title)
	var txt := "Seleziona le unità e usa il tasto destro per collocarle nella zona evidenziata\n(carri davanti, artiglieria dietro). La battaglia è in pausa."
	if battle.sim.hs == 1:
		deploy_title.text = "SCHIERA LA DIFESA"
		txt = "Schiera la difesa: fanteria nei boschi e in città, carri dietro i rilievi, artiglieria in fondo.\nSeleziona e usa il tasto destro nella zona evidenziata. La battaglia è in pausa."
	var t := _label(txt, 13, TXT)
	v.add_child(t)
	var bt := _btn(h, "start", "Inizia ▶", "Inizia subito la battaglia (Invio)")
	bt.custom_minimum_size = Vector2(130, 52)
	bt.add_theme_font_size_override("font_size", 18)
	deploy_panel.visible = false

func _build_msg() -> void:
	msg_panel = PanelContainer.new()
	msg_panel.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.03, 0.03, 0.86), Color(0.7, 0.7, 0.55, 0.4), 8, 26))
	_anchor(msg_panel, Control.PRESET_CENTER, -400, -150, 400, 150)
	msg_panel.visible = false
	msg_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(msg_panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	msg_panel.add_child(v)
	msg_title = _label("", 50, Color.WHITE)
	msg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_sub = _label("", 17, TXT)
	msg_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg_title)
	v.add_child(msg_sub)
	msg_loss = RichTextLabel.new()
	msg_loss.bbcode_enabled = true
	msg_loss.fit_content = true
	msg_loss.scroll_active = false
	msg_loss.custom_minimum_size = Vector2(740, 0)
	msg_loss.add_theme_font_size_override("normal_font_size", 15)
	msg_loss.add_theme_font_size_override("bold_font_size", 15)
	msg_loss.add_theme_color_override("default_color", TXT)
	msg_loss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(msg_loss)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var b := _btn(row, "continue", "Continua (Invio)", "Torna al tabellone")
	b.custom_minimum_size = Vector2(200, 40)

func _loss_line(si: int, l: Dictionary) -> String:
	var S: Dictionary = battle.sim.sides[si]
	var col: Color = S["color"]
	var parts := []
	var tot := 0
	for k in Data.UNIT_KEYS:
		if l.has(k):
			parts.append("%d %s" % [l[k], String(Data.UNITS[k]["name"]).to_lower()])
			tot += int(l[k])
	var who := "%s · %s" % ["Attacco" if si == 0 else "Difesa", S["name"]]
	var body := ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "nessuna"
	return "[color=#%s]■[/color] [b]%s[/b] — perdite %d: [color=#c9cfc4]%s[/color]" % [col.to_html(false), who, tot, body]

func show_message(title: String, sub: String, col: Color, loss := []) -> void:
	msg_panel.visible = true
	msg_title.text = title
	msg_title.add_theme_color_override("font_color", col)
	msg_sub.text = sub
	var lines := []
	if loss.size() == 2:
		lines.append(_loss_line(0, loss[0]))
		lines.append(_loss_line(1, loss[1]))
		var tt := int(battle.sim.time)
		lines.append("[color=#9aa39a]Durata %02d:%02d[/color]" % [tt / 60, tt % 60])
	msg_loss.text = "[center]" + "\n".join(PackedStringArray(lines)) + "[/center]"
	if deploy_panel != null:
		deploy_panel.visible = false

# ---------------------------------------------------------------------------- introduzione cinematica
var intro_root: Control
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _intro_box: VBoxContainer
var _intro_skip: Label

## Sovrimpressione dell'introduzione: bande nere, nome del territorio, ora/meteo, schieramenti. L'HUD normale è nascosto.
func show_intro(title: String, line1: String, line2: String) -> void:
	root.visible = false
	intro_root = Control.new()
	intro_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(intro_root)
	_bar_top = ColorRect.new()
	_bar_top.color = Color(0, 0, 0, 0.92)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_bar_top, Control.PRESET_TOP_WIDE, 0, 0, 0, 0)
	intro_root.add_child(_bar_top)
	_bar_bot = ColorRect.new()
	_bar_bot.color = Color(0, 0, 0, 0.92)
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_bar_bot, Control.PRESET_BOTTOM_WIDE, 0, 0, 0, 0)
	intro_root.add_child(_bar_bot)
	_intro_box = VBoxContainer.new()
	_intro_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_intro_box.add_theme_constant_override("separation", 4)
	_intro_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_intro_box, Control.PRESET_CENTER_LEFT, 70, -60, 1100, 150)
	intro_root.add_child(_intro_box)
	var t1 := _label(line1.to_upper(), 16, Color(0.95, 0.85, 0.45))
	_intro_box.add_child(t1)
	var tt := _label(title.to_upper(), 46, Color(1, 0.97, 0.9))
	tt.add_theme_constant_override("shadow_offset_x", 2)
	tt.add_theme_constant_override("shadow_offset_y", 2)
	_intro_box.add_child(tt)
	var line := ColorRect.new()
	line.color = Color(0.95, 0.85, 0.45, 0.8)
	line.custom_minimum_size = Vector2(420, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_box.add_child(line)
	_intro_box.add_child(_label(line2, 17, TXT))
	for i in 2:
		var S: Dictionary = battle.sim.sides[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := ColorRect.new()
		sw.color = S["color"]
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		h.add_child(_label("%s · %s · %d unità" % ["Attacco" if i == 0 else "Difesa", S["name"], Data.total_units(S["forces"])], 15, TXT))
		var nv: int = battle.vet(i)
		if nv > 0:
			h.add_child(Stars.new(nv, 6.5))
			h.add_child(_label("veterani", 13, BattleHud.GOLD))
		_intro_box.add_child(h)
	_intro_skip = _label("Clic o Invio per saltare", 13, DIM)
	_anchor(_intro_skip, Control.PRESET_BOTTOM_RIGHT, -260, -34, -24, -12)
	_intro_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intro_root.add_child(_intro_skip)
	set_intro(0.0)

## f = avanzamento 0..1 dell'introduzione.
func set_intro(f: float) -> void:
	if intro_root == null:
		return
	var h := intro_root.size.y if intro_root.size.y > 0 else 900.0
	var bar := h * 0.11 * (smoothstep(0.0, 0.12, f) * (1.0 - smoothstep(0.88, 1.0, f)))
	_bar_top.offset_bottom = bar
	_bar_bot.offset_top = -bar
	var a := smoothstep(0.06, 0.2, f) * (1.0 - smoothstep(0.8, 0.97, f))
	_intro_box.modulate = Color(1, 1, 1, a)
	_intro_skip.modulate = Color(1, 1, 1, a * 0.8)

func hide_intro() -> void:
	if intro_root != null:
		intro_root.queue_free()
		intro_root = null
	root.visible = true

func flash_alert() -> void:
	_alert_t = 4.0

## Riga delle condizioni sotto il titolo ("Pianura · pomeriggio · pioggia").
func set_conditions(text: String) -> void:
	if lbl_sub == null:
		return
	var tname := String(Data.TERRAINS[battle.sim.tkey]["name"])
	lbl_sub.text = tname + (" · costa" if battle.sim.sea else "") + ((" · " + text) if text != "" else "")

# ---------------------------------------------------------------------------- Fase 8: modalità foto
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.25, 1.0)) * 1.6;
	float v = smoothstep(0.55, 1.35, r) * amount;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}
"""

func _build_photo() -> void:
	photo_root = Control.new()
	photo_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	photo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_root.visible = false
	add_child(photo_root)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("amount", 0.0)
	_vignette.material = sm
	photo_root.add_child(_vignette)
	_photo_flash = ColorRect.new()
	_photo_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo_flash.color = Color(1, 1, 1, 0)
	photo_root.add_child(_photo_flash)
	photo_panel = PanelContainer.new()
	photo_panel.add_theme_stylebox_override("panel", _sb(BG, EDGE, 6, 12))
	_anchor(photo_panel, Control.PRESET_CENTER_BOTTOM, -330, -118, 330, -12)
	photo_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	photo_root.add_child(photo_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	photo_panel.add_child(v)
	var title := _label("MODALITÀ FOTO", 15, Color(1, 0.9, 0.6), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var help := _label("WASD: muovi · Q/E: quota · tasto destro + mouse: guarda · Maiusc: veloce · rotella: zoom · H: nascondi il pannello", 12, DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_dof_slider = _slider(row, "Sfocatura", 0.0, func(x: float) -> void: battle.photo_dof(x))
	_vig_slider = _slider(row, "Vignetta", 0.25, func(x: float) -> void: (_vignette.material as ShaderMaterial).set_shader_parameter("amount", x))
	var b1 := _btn(row, "photo_shot", "Scatta  (Invio)", "Salva un PNG in user://screenshots", "")
	b1.custom_minimum_size = Vector2(150, 34)
	var b2 := _btn(row, "photo_exit", "Esci  (Esc)", "Torna alla battaglia", "")
	b2.custom_minimum_size = Vector2(110, 34)
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.25)

func _slider(parent: Control, name: String, v0: float, cb: Callable) -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := _label(name, 12, DIM)
	box.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = v0
	sl.custom_minimum_size = Vector2(150, 22)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(cb)
	box.add_child(sl)
	parent.add_child(box)
	return sl

## Entra/esce dalla modalità foto: nasconde tutta l'interfaccia, mostra vignetta e pannello.
func set_photo(on: bool) -> void:
	if photo_root == null:
		_build_photo()
	root.visible = not on
	if intro_root != null:
		intro_root.visible = not on
	photo_root.visible = on
	if on:
		photo_panel.visible = true
		battle.photo_dof(_dof_slider.value)

func set_photo_panel_visible(v: bool) -> void:
	if photo_panel != null:
		photo_panel.visible = v
		_vignette.visible = true

func toggle_photo_panel() -> void:
	if photo_panel != null:
		photo_panel.visible = not photo_panel.visible

## Lampo bianco dello scatto.
func flash_photo() -> void:
	_flash_t = 0.35

func refresh() -> void:
	var sim: BattleSim = battle.sim
	if _flash_t > 0.0 and _photo_flash != null:
		_flash_t = maxf(0.0, _flash_t - get_process_delta_time())
		_photo_flash.color = Color(1, 1, 1, clampf(_flash_t * 2.2, 0.0, 0.85))
	if battle.photo:
		return
	for i in 2:
		var sb: Dictionary = side_box[i]
		var init_n: int = maxi(1, sim.init[i])
		sb["bar"].value = float(sim.cnt[i]) / init_n
		var S: Dictionary = sim.sides[i]
		var t := "%d / %d unità" % [sim.cnt[i], sim.init[i]]
		if i == 1 and sim.bunker_pos.size() > 0:
			t += " · bunker %d" % sim.bunkers_alive()
		if int(S["support"]) > 0:
			t += " · supporto art. %d" % int(S["support"])
		sb["count"].text = t
	var tt := int(ceil(maxf(0.0, BattleRules.BATTLE_T - sim.time)))   # conto alla rovescia (docs/omogeneita.md §1)
	lbl_time.text = "%02d:%02d" % [tt / 60, tt % 60]
	lbl_time.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if (tt <= 60 and sim.ending == null) else Color(0.95, 0.85, 0.45))
	_refresh_objectives()
	pause_lbl.visible = sim.paused and sim.ending == null and not battle.deploying
	var hs := sim.hs
	var ended: bool = sim.ending != null or sim.done
	if buttons.has("pause"):
		var pz: bool = sim.paused and not battle.deploying
		buttons["pause"].text = "Riprendi" if pz else "Pausa"
		if buttons["pause"] is CmdButton:
			(buttons["pause"] as CmdButton).set_kind("play" if pz else "pause")
		buttons["pause"].disabled = ended or battle.deploying
	for id in ["auto", "retreat", "all"]:
		if buttons.has(id):
			buttons[id].disabled = ended
	if buttons.has("retreat") and sim.retreating[0]:
		buttons["retreat"].disabled = true
		buttons["retreat"].text = "In ritirata…"
	var sel_l: Array = sim.sel_alive() if hs >= 0 else []
	var nosel := sel_l.is_empty()
	for id in ["amove", "stop", "hold"]:
		if buttons.has(id):
			buttons[id].disabled = ended or battle.deploying or nosel
	if buttons.has("area"):
		buttons["area"].disabled = ended or battle.deploying or not battle.sel_has_art()
		_set_cmd("area", 0.0, battle.mode == "area")
	if buttons.has("amove"):
		_set_cmd("amove", 0.0, battle.mode == "amove")
	if buttons.has("hold"):
		var all_hold := not nosel
		for u in sel_l:
			if not u.hold:
				all_hold = false
				break
		_set_cmd("hold", 0.0, all_hold)
	if hs >= 0:
		var S: Dictionary = sim.sides[hs]
		if buttons.has("barrage"):
			var cd: float = S["barrage_cd"]
			buttons["barrage"].text = "Sbarram." + ((" %ds" % ceili(cd)) if cd > 0 else "")
			buttons["barrage"].disabled = ended or cd > 0 or battle.deploying
			_set_cmd("barrage", clampf(cd / BattleSim.BARRAGE_CD, 0.0, 1.0), battle.mode == "barrage")
		if buttons.has("smoke"):
			var sc: float = S["smoke_cd"]
			var ground := false
			for u in sel_l:
				if not u.air:
					ground = true
					break
			buttons["smoke"].text = "Fumo" + ((" %ds" % ceili(sc)) if sc > 0 else "")
			buttons["smoke"].disabled = ended or sc > 0 or battle.deploying or not ground
			_set_cmd("smoke", clampf(sc / BattleSim.SMOKE_CD, 0.0, 1.0), false)
		if buttons.has("air"):
			var left: float = float(S["air_t"]) - sim.time
			var uses := int(S["air_uses"])
			if uses > 0:
				buttons["air"].text = "Aereo"
				_set_cmd("air", 0.0, battle.mode == "air")
			elif left > 0.0:
				buttons["air"].text = "In arrivo"
				_set_cmd("air", clampf(left / BattleSim.AIR_DELAY, 0.0, 1.0), true)
			else:
				buttons["air"].text = "Usato"
				_set_cmd("air", 0.0, false)
			buttons["air"].disabled = ended or uses <= 0 or battle.deploying
	# schieramento
	if battle.deploying:
		if deploy_panel == null:
			_build_deploy()
		deploy_panel.visible = true
		deploy_title.text = ("SCHIERA LA DIFESA" if battle.sim.hs == 1 else "SCHIERAMENTO") + " — inizio tra %d s" % ceili(maxf(0.0, battle.deploy_left))
	elif deploy_panel != null:
		deploy_panel.visible = false
	# allarme
	_alert_t = maxf(0.0, _alert_t - get_process_delta_time())
	alert_btn.visible = not battle.alerts.is_empty() and not ended
	match battle.mode:
		"amove": mode_lbl.text = "ATTACCO IN MOVIMENTO — clic sinistro sul punto (tasto destro annulla)"
		"barrage": mode_lbl.text = "SBARRAMENTO — clic sinistro sul bersaglio (tasto destro annulla)"
		"air": mode_lbl.text = "SUPPORTO AEREO — clic sinistro sull'area da bombardare (tasto destro annulla)"
		"area": mode_lbl.text = "FUOCO D'AREA — clic sinistro sul punto da battere con l'artiglieria (tasto destro annulla)"
		_: mode_lbl.text = _stall_text(sim, ended)
	_refresh_selection()
	overlay.queue_redraw()
	minimap.redraw()

func _set_cmd(id: String, cd: float, on: bool) -> void:
	var b = buttons.get(id)
	if b is CmdButton:
		(b as CmdButton).set_state(cd, on)

## Avviso di stallo: senza danni per NO_DMG_HUMAN secondi l'attacco fallisce (regola del prototipo).
func _stall_text(sim: BattleSim, ended: bool) -> String:
	if ended or sim.hs < 0 or sim.paused or battle.deploying:
		return ""
	if sim.retreating[sim.hs]:
		return "RITIRATA IN CORSO — i reparti che raggiungono il tuo bordo si salvano"
	var left: float = BattleSim.NO_DMG_HUMAN - (sim.time - sim.last_dmg)
	if left > 45.0:
		return ""
	var objs: bool = not sim.objectives.is_empty()
	if sim.hs == 0:
		return "NESSUN CONTATTO — attacca entro %d s o l'offensiva fallisce (%s)" % [ceili(maxf(0.0, left)), "decidono gli obiettivi" if objs else "stallo"]
	return "Il nemico non attacca — tieni la posizione: %s tra %d s" % ["decidono gli obiettivi" if objs else "vittoria per stallo", ceili(maxf(0.0, left))]

const HELP_CAM :="WASD/frecce/bordi: sposta · Q/E: ruota · rotella: zoom (fino alla vista strategica) · Tab: vista strategica/tattica · Home: torna all'esercito · F10: modalità foto"

## Suggerimento tattico per tipo d'unità (pannello di selezione).
const HINTS := {
	"inf": "Fanteria: nascosta nei boschi e in città, letale contro i carri da vicino (×3 entro 60 m al riparo). Allo scoperto è vulnerabile.",
	"tank": "Carri: colpiscono da lontano; il fronte regge, fianchi (×1,6) e retro (×2,5) no. Aggira il nemico; nei boschi rallentano e vedono poco.",
	"art": "Artiglieria: tira oltre la vista, servono unità che avvistino (o il fuoco d'area, X). Dopo ogni spostamento si piazza per 4 s.",
	"aa": "Contraerea: protegge da elicotteri e caccia; corazza leggera, tienila dietro ai carri.",
	"heli": "Elicotteri: rapidi, vedono lontano e cacciano i carri; temono la contraerea.",
	"jet": "Caccia-bombardieri: colpi rapidi a lungo raggio sui mezzi; temono la contraerea.",
	"drone": "Droni: esploratori economici con vista ampia, scoprono i nemici nascosti per l'artiglieria.",
}

const ARMOR_TXT := {"tank": "corazza pesante", "art": "corazza leggera", "aa": "corazza leggera", "bunker": "fortificato",
	"inf": "nessuna corazza", "heli": "corazza leggera", "jet": "corazza leggera", "drone": "nessuna corazza"}

## Riga di statistiche reali dell'unità nella battaglia: gittata, vista, corazza, velocità.
func unit_stats(u) -> String:
	var S := BattleTerrain.S
	var out := []
	var rg := "gittata %d m" % roundi(u.range_ * S)
	if u.min_range > 1.0:
		rg += " (min %d)" % roundi(u.min_range * S)
	out.append(rg)
	var vw = u.get("view")
	if vw != null:
		out.append("vista %d m" % roundi(float(vw) * S))
	out.append(ARMOR_TXT.get(u.type, ""))
	out.append("%d km/h" % roundi(u.speed * S * 3.6))
	return " · ".join(PackedStringArray(out))

func _refresh_selection() -> void:
	var sim: BattleSim = battle.sim
	if sim.hs < 0:
		sel_title.text = "Battaglia tra forze automatiche"
		sel_body.text = "[color=#9aa39a]%s · P: pausa[/color]" % HELP_CAM
		return
	if battle.deploying:
		var n0 := sim.sel_alive().size()
		sel_title.text = "Schieramento: %d unità selezionate" % n0
		sel_body.text = "[color=#9aa39a]Clic/trascina: seleziona · doppio clic: stesso tipo · Ctrl+A: tutte\nTasto destro nella zona: colloca in formazione · Invio/Spazio: inizia\n%s[/color]" % HELP_CAM
		return
	var sel := sim.sel_alive()
	if sel.is_empty():
		sel_title.text = "Nessuna unità selezionata"
		sel_body.text = "[color=#9aa39a]Clic/trascina: seleziona · doppio clic: stesso tipo · Ctrl+A: tutte · Ctrl+1..9: gruppi\nTasto destro: muovi/attacca · G: attacco in mov. · H: alt · T: mantieni posizione · F: fumo · J: aereo · B: sbarramento\nC: centra sulla selezione · P: pausa · %s[/color]" % HELP_CAM
		return
	var by := {}
	var hp := 0.0
	var hpm := 0.0
	var n := 0
	for u in sel:
		var k: String = u.type
		by[k] = int(by.get(k, 0)) + sim.alive(u)
		hp += u.hp; hpm += u.hp_max
		n += sim.alive(u)
	sel_title.text = "Selezionate: %d unità  ·  integrità %d%%" % [n, roundi(100.0 * hp / maxf(1.0, hpm))]
	if battle.vet(sim.hs) > 0:
		sel_title.text += "  ·  veterani %d stell%s" % [battle.vet(sim.hs), "a" if battle.vet(sim.hs) == 1 else "e"]
	var parts := []
	var first := {}
	for u in sel:
		if not first.has(u.type):
			first[u.type] = u
	var main_k := ""
	for k in Data.UNIT_KEYS:
		if by.has(k):
			if main_k == "" or int(by[k]) > int(by[main_k]):
				main_k = k
			if parts.size() >= 3:
				parts[2] = parts[2] + " …"
				continue
			parts.append("[b]%s[/b] ×%d  [color=#aab3a6]%s[/color]" % [Data.UNITS[k]["name"], by[k], unit_stats(first[k])])
	var grp := []
	for g in sim.groups:
		if not sim.groups[g].is_empty():
			grp.append(str(g))
	var nh := 0
	var ns := 0
	for u in sel:
		if u.hold: nh += 1
		if u.smoke_t > 0: ns += 1
	var extra := "\n[color=#9aa39a]Tasto destro: muovi/attacca · G: attacco in mov. · H: alt · T: mantieni · F: fumo · C: centra[/color]"
	if nh > 0:
		extra += "  [color=#f2b13c]In posizione: %d[/color]" % nh
	if ns > 0:
		extra += "  [color=#cfd8d0]Nel fumo: %d[/color]" % ns
	if not grp.is_empty():
		extra += "[color=#9aa39a] · Gruppi: %s[/color]" % ", ".join(PackedStringArray(grp))
	var hint := ""
	if HINTS.has(main_k):
		hint = "\n[color=#e8c37a]%s[/color]" % HINTS[main_k]
	var nc := 0
	for u in sel:
		if u.get("concealed") == true:
			nc += 1
	if nc > 0:
		extra += "  [color=#9be38f]Nascoste: %d[/color]" % nc
	sel_body.text = "\n".join(PackedStringArray(parts)) + hint + extra

# ---------------------------------------------------------------------------- minimappa
class Minimap extends Control:
	var hud
	var tex: ImageTexture
	var _drag := false
	var HX := 230.0
	var HZ := 129.375
	var fog_rect: TextureRect
	var marks: Control

	func setup() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		var b = hud.battle
		# area mostrata: tutto il campo con un piccolo margine, proporzioni 16:9 come il riquadro
		HX = BattleTerrain.FIELD_HX + 30.0
		HZ = maxf(HX * 0.5625, BattleTerrain.FIELD_HZ + 16.0)
		HX = maxf(HX, HZ / 0.5625)
		var img: Image = b.terrain.minimap_image(256, 144, HX, HZ)
		tex = ImageTexture.create_from_image(img)
		var ft = b.fog_texture()
		if ft != null:
			# nebbia tattica: la texture dei cerchi di vista moltiplica la minimappa (zone non osservate più scure)
			fog_rect = TextureRect.new()
			fog_rect.texture = ft
			fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
			fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
			fog_rect.material = m
			add_child(fog_rect)
		marks = Control.new()
		marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marks.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(marks)
		marks.draw.connect(_draw_marks)
		resized.connect(_place_fog)
		_place_fog()

	func _place_fog() -> void:
		if fog_rect == null:
			return
		var a := w2m(-BattleTerrain.FIELD_HX, -BattleTerrain.FIELD_HZ)
		var c := w2m(BattleTerrain.FIELD_HX, BattleTerrain.FIELD_HZ)
		fog_rect.position = a
		fog_rect.size = c - a

	func redraw() -> void:
		queue_redraw()
		if marks != null:
			marks.queue_redraw()

	func w2m(X: float, Z: float) -> Vector2:
		return Vector2((X + HX) / (2.0 * HX) * size.x, (Z + HZ) / (2.0 * HZ) * size.y)

	func m2w(p: Vector2) -> Vector3:
		return Vector3(p.x / size.x * 2.0 * HX - HX, 0, p.y / size.y * 2.0 * HZ - HZ)

	func _gui_input(ev: InputEvent) -> void:
		var b = hud.battle
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
				if mb.pressed:
					b.cam.go_to(m2w(mb.position))
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var w: Vector3 = m2w(mb.position)
				var s := BattleTerrain.world_to_sim(w.x, w.z)
				if b.sim.hs >= 0 and not b.sim.sel_alive().is_empty() and b.sim.ending == null:
					if b.deploying:
						b.sim.deploy_place(b.sim.sel_alive(), s.x, s.y)
					else:
						b.sim.order_move(s.x, s.y)
					b._mark(s.x, s.y, "deploy" if b.deploying else "move", 3.0)
					b._sfx("order", 0.05)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				accept_event()
		elif ev is InputEventMouseMotion and _drag:
			b.cam.go_to(m2w((ev as InputEventMouseMotion).position))
			accept_event()

	func _draw() -> void:
		if tex == null:
			return
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)

	func _draw_marks() -> void:
		var b = hud.battle
		if tex == null or b == null or b.sim == null:
			return
		var c := marks
		var r := Rect2(Vector2.ZERO, size)
		# campo di battaglia
		var f0 := w2m(-BattleTerrain.FIELD_HX, -BattleTerrain.FIELD_HZ)
		var f1 := w2m(BattleTerrain.FIELD_HX, BattleTerrain.FIELD_HZ)
		c.draw_rect(Rect2(f0, f1 - f0), Color(0, 0, 0, 0.35), false, 1.0)
		var sim = b.sim
		if b.deploying:
			var z: Rect2 = sim.deploy_zone(sim.hs)
			var a := BattleTerrain.sim_to_world(z.position.x, z.position.y)
			var e := BattleTerrain.sim_to_world(z.end.x, z.end.y)
			var col: Color = b.side_color(sim.hs)
			var zr := Rect2(w2m(a.x, a.y), w2m(e.x, e.y) - w2m(a.x, a.y))
			c.draw_rect(zr, Color(col, 0.18))
			c.draw_rect(zr, Color(col.lightened(0.3), 0.8), false, 1.5)
		# fantasmi: ultime posizioni note dei nemici
		if sim.hs >= 0 and "ghosts" in sim and sim.ghosts is Array and sim.ghosts.size() > sim.hs:
			var gc: Color = b.side_color(1 - sim.hs).lightened(0.2)
			for g in sim.ghosts[sim.hs]:
				var w := BattleTerrain.sim_to_world(float(g["x"]), float(g["y"]))
				var p := w2m(w.x, w.y)
				var age: float = maxf(0.0, sim.time - float(g.get("t", sim.time)))
				var al := clampf(0.75 - age / 30.0, 0.25, 0.75)
				c.draw_arc(p, 3.2, 0, TAU, 8, Color(gc, al), 1.2)
		# unità (i nemici non avvistati non compaiono; i contatti "?" come rombo vuoto)
		for u in sim.units:
			if u.dead:
				continue
			if not b.is_visible_unit(u):
				if b.has_method("is_contact_unit") and b.is_contact_unit(u):
					var cw := BattleTerrain.sim_to_world(u.x, u.y)
					var cp := w2m(cw.x, cw.y)
					var cc: Color = b.side_color(u.side).lightened(0.3)
					c.draw_polyline(PackedVector2Array([cp + Vector2(0, -3), cp + Vector2(3, 0), cp + Vector2(0, 3), cp + Vector2(-3, 0), cp + Vector2(0, -3)]), cc, 1.2)
				continue
			var w := BattleTerrain.sim_to_world(u.x, u.y)
			var p := w2m(w.x, w.y)
			var col: Color = b.side_color(u.side).lightened(0.15)
			if u.side == sim.hs and u.get("concealed") == true:
				col = col.lerp(Color(0.55, 0.95, 0.5), 0.35)
				col.a = 0.75
			if u.stat:
				c.draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0, 0, 0, 0.8))
				c.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), col)
				continue
			var s := 2.0 if u.type == "inf" else 2.7
			if u.air:
				c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s - 1), p + Vector2(s + 1, 0), p + Vector2(0, s + 1), p + Vector2(-s - 1, 0)]), Color(0, 0, 0, 0.7))
				c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)
			else:
				c.draw_rect(Rect2(p - Vector2(s + 0.8, s + 0.8), Vector2(2 * s + 1.6, 2 * s + 1.6)), Color(0, 0, 0, 0.7))
				c.draw_rect(Rect2(p - Vector2(s, s), Vector2(2 * s, 2 * s)), col)
			if u.sel:
				c.draw_arc(p, s + 2.5, 0, TAU, 12, Color(0.5, 1.0, 0.6, 0.95), 1.2)
		# avvistamenti e imboscate
		for pg in b.pings:
			var pp: Vector3 = pg["p"]
			var q := w2m(pp.x, pp.z)
			var f: float = clampf(float(pg["t"]) / 3.0, 0.0, 1.0)
			var pc: Color = pg["col"]
			c.draw_arc(q, 4.0 + 14.0 * f, 0, TAU, 20, Color(pc, (1.0 - f) * 0.95), 1.6)
		# allarmi
		for al in b.alerts:
			var ap: Vector3 = al["p"]
			var q := w2m(ap.x, ap.z)
			var k := 0.5 + 0.5 * sin(b._wall_time * 8.0)
			c.draw_arc(q, 6.0 + 4.0 * k, 0, TAU, 16, Color(1, 0.3, 0.2, 0.9), 1.5)
		# vista della telecamera
		var cs: Array = b.cam.view_corners()
		var pts := PackedVector2Array()
		for cc in cs:
			pts.append(w2m(cc.x, cc.y))
		pts.append(pts[0])
		c.draw_polyline(pts, Color(1, 1, 1, 0.85), 1.4)
		c.draw_rect(r, Color(0.55, 0.6, 0.45, 0.6), false, 1.5)
