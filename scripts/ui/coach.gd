extends Control
## Tutorial guidato del primo turno (FASE 6, a turni): dice esattamente cosa cliccare, indica con una freccia
## l'elemento vero (territorio sul tabellone o pulsante dell'interfaccia) e aspetta che il giocatore lo faccia.
## Parte da solo alla prima campagna (Settings.tutorial_done = false) o dal menu «Tutorial». Saltabile in ogni momento.
## main chiama update() ~4 volte al secondo; il disegno della freccia avviene a ogni fotogramma.

var main = null
var active := false
var step := ""
var panel: PanelContainer
var title_lbl: Label
var step_lbl: Label
var text_lbl: RichTextLabel
var btn_next: Button
var btn_skip: Button
var _src := -1
var _tgt := -1
var _q0 := 0
var _t := 0.0
var _rect = null            # Rect2 dell'elemento indicato (o null)
var _entered := 0.0

const ORDER := ["intro", "deploy", "army", "recruit", "endphase", "source", "target", "panel", "result", "move", "endturn", "ai", "done"]
const TITLES := {
	"intro": "Benvenuto, comandante",
	"deploy": "1 · Schiera i rinforzi",
	"army": "2 · Come formare l'esercito",
	"recruit": "3 · Recluta nuove truppe",
	"endphase": "4 · Passa all'attacco",
	"source": "5 · Scegli da dove attaccare",
	"skipatk": "5 · Niente attacchi utili",
	"target": "6 · Scegli il bersaglio",
	"panel": "7 · Il pannello d'attacco",
	"result": "8 · Esito della battaglia",
	"move": "9 · Spostamento (facoltativo)",
	"endturn": "10 · Fine del turno",
	"ai": "11 · Il turno delle IA",
	"defense": "Ti attaccano!",
	"done": "Pronto al comando",
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var sb := UIKit.box(Color(0.05, 0.075, 0.07, 0.98), Color(UIKit.AMBER, 0.7), 1, 6, Vector4(16, 12, 16, 12))
	sb.border_width_left = 5
	sb.border_color = UIKit.AMBER
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size.x = 400
	panel.visible = false
	add_child(panel)
	var v := UIKit.vbox(8)
	var h := UIKit.hbox(9)
	h.add_child(UIKit.icon("bulb", 22))
	title_lbl = UIKit.label("", 18, UIKit.AMBER2, "sans", 700)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title_lbl)
	step_lbl = UIKit.label("", 11, UIKit.DIM, "mono", 700)
	step_lbl.tooltip_text = "Tutorial guidato del primo turno"
	step_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(step_lbl)
	v.add_child(h)
	text_lbl = UIKit.rich("", 15, UIKit.TEXT)
	text_lbl.custom_minimum_size.x = 368
	v.add_child(text_lbl)
	var bh := UIKit.hbox(8)
	btn_skip = UIKit.button("Salta tutorial", "ghost", "sm", func(): skip(), "Chiudi il tutorial: lo ritrovi nel menu principale")
	bh.add_child(btn_skip)
	bh.add_child(UIKit.spacer())
	btn_next = UIKit.button("Avanti  ›", "primary", "sm", func(): _on_next())
	btn_next.custom_minimum_size = Vector2(120, 32)
	bh.add_child(btn_next)
	v.add_child(bh)
	panel.add_child(v)

# ------------------------------------------------------------------ ciclo di vita
func start() -> void:
	active = true
	_src = -1
	_tgt = -1
	_go("intro")

func stop(mark_done: bool = true) -> void:
	if mark_done:
		Settings.set_value("tutorial_done", true)
	active = false
	step = ""
	_rect = null
	if panel:
		panel.visible = false
	queue_redraw()

func skip() -> void:
	stop(true)
	if main != null:
		main.toast("Tutorial chiuso: lo ritrovi nel menu principale", "info")

func _on_next() -> void:
	match step:
		"intro": _go("deploy" if _pool() > 0 else "army")
		"army": _go("recruit")
		"recruit": _go("endphase")
		"move": _go("endturn")
		"done": stop(true)
		_: pass

func _go(id: String) -> void:
	step = id
	_entered = Time.get_ticks_msec() / 1000.0
	var g = main.game
	match id:
		"deploy":
			if _pool() <= 0:
				_go("recruit")
				return
			_focus(_hq())
		"army", "recruit":
			if not main.my_phase("supply"):
				_go("source")
				return
			if not main.sel_own():
				main.select(_hq())
			main.hud.rtab = "recruit"
			_q0 = _queued()
			main.refresh(true)
		"source":
			var pair: Array = main.demo_attack_pair()
			if pair.is_empty():
				_go("skipatk")
				return
			_src = int(pair[0])
			_tgt = int(pair[1])
			if main.sel_own() and not main.targets.is_empty():
				_src = main.sel
			_focus(_src)
		"target":
			_src = main.sel
			_tgt = _best_target()
			_focus(_tgt)
	if g == null:
		return
	title_lbl.text = TITLES.get(id, "")
	var i := ORDER.find(id)
	step_lbl.text = ("PASSO %d/%d" % [i, ORDER.size() - 2]) if i >= 1 and i <= ORDER.size() - 2 else ""
	text_lbl.text = _text(id)
	btn_next.visible = id in ["intro", "army", "recruit", "move", "done"]
	btn_next.text = {"intro": "Inizia  ›", "army": "Ho capito  ›", "recruit": "Salta questo passo  ›", "move": "Non spostare  ›", "done": "Fine  ✓"}.get(id, "Avanti  ›")
	btn_skip.visible = id != "done"
	# sotto le finestre (pannello d'attacco, difesa) il riquadro è largo e basso per stare nello spazio libero
	var wide := id in ["panel", "defense"]
	panel.custom_minimum_size.x = 600 if wide else 400
	text_lbl.custom_minimum_size.x = 568 if wide else 368
	text_lbl.size = Vector2(text_lbl.custom_minimum_size.x, 0)
	panel.size = Vector2.ZERO
	panel.visible = true
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	Sfx.play("select")
	panel.reset_size()

# ------------------------------------------------------------------ testi
func _text(id: String) -> String:
	match id:
		"intro":
			return "Ti guido nel [b]primo turno[/b]. Ogni turno ha [b]tre fasi[/b]: [color=#7fe08f]Rifornimento[/color] › [color=#ff8a6a]Attacco[/color] › [color=#8ad6ff]Spostamento[/color]. Poi giocano le IA.\nIl riquadro [b]ORDINI[/b] in basso ti dice sempre cosa fare."
		"deploy":
			return "Hai [b]%d rinforzi[/b]. I tuoi territori [color=#7fe08f]pulsano in verde[/color]: [b]clicca il tuo QG ★ %s[/b] (indicato dalla freccia) per schierarli lì." % [_pool(), Data.TERRITORIES[_hq()]["name"]]
		"army":
			return "I [b]rinforzi gratis[/b] di ogni turno sono [b]fanteria[/b]: ottima per [b]difendere[/b] boschi e città.
Per [b]attaccare[/b] recluta [b]carri[/b] e [b]artiglieria[/b] dove hai una [b]Fabbrica[/b] (il QG ★ vale come caserma e fabbrica): nascono in quel territorio. Un [b]esercito misto[/b] batte uno numeroso di un solo tipo.
La [b]ricerca[/b] (pulsante in alto) vale per [b]tutti[/b] i tuoi territori; gli edifici solo dove li costruisci."
		"recruit":
			return "A destra c'è il pannello del territorio. Nella scheda [b]Recluta[/b] premi [b]+1[/b] accanto a [b]Fanteria[/b]: la nuova unità arriverà al prossimo turno.\nNelle altre schede costruisci edifici e fortificazioni."
		"endphase":
			return "Fatto il rifornimento, premi [b]Fase successiva: Attacco[/b] nel riquadro ORDINI."
		"source":
			return "Fase di [color=#ff8a6a]attacco[/color]: [b]uno solo per turno[/b], facoltativo. I territori che possono attaccare [color=#ffc060]pulsano in ambra[/color]: [b]clicca %s[/b]." % Data.TERRITORIES[_src]["name"]
		"skipatk":
			return "Ora nessun tuo territorio può attaccare con profitto. Premi [b]Salta attacco[/b] nel riquadro ORDINI."
		"target":
			return "I bersagli possibili sono [color=#ff8a6a]evidenziati in rosso[/color]. Durante la [b]tregua[/b] dei primi turni si attaccano solo i neutrali. [b]Clicca %s[/b]." % Data.TERRITORIES[maxi(0, _tgt)]["name"]
		"panel":
			return "Con i [b]cursori[/b] scegli quante unità inviare (una resta a casa) e guarda la [b]previsione[/b]. [b]Comando diretto (3D)[/b] = combatti tu in tempo reale: hai [b]+10%[/b] di attacco ed esperienza doppia, la battaglia dura al massimo [b]5 minuti[/b] e allo scadere decidono gli [b]obiettivi[/b] del campo. [b]Risoluzione automatica[/b] = esito immediato. Dopo ogni battaglia le truppe restano [b]logorate[/b] (−15%) per un turno. Per ora premi [b]risoluzione automatica[/b]."
		"result":
			return "L'esito è nel riquadro ORDINI. Se conquisti, le truppe entrano e ottieni una [b]carta[/b] (scheda Carte a sinistra).\nOra premi [b]Fase successiva: Spostamento[/b]."
		"move":
			return "Puoi fare [b]uno spostamento[/b]: clicca un tuo territorio ([color=#8ad6ff]pulsano in azzurro[/color]), poi un tuo territorio collegato. Nel pannello scegli quante unità e premi [b]Sposta[/b].\nÈ facoltativo."
		"endturn":
			return "Premi [b]Fine turno[/b] (o [b]Invio[/b]). Le unità reclutate avanzano di un turno e giocano le IA."
		"ai":
			return "Ora muovono le IA: attacchi e spostamenti appaiono come [b]frecce[/b] sul tabellone. [b]Spazio[/b] accelera.\nSe qualcuno ti attacca sceglierai: [b]difesa in 3D[/b] o [b]risoluzione automatica[/b]."
		"defense":
			return "Un nemico attacca un tuo territorio. [b]Difendi in prima persona (3D)[/b]: schieri tu le truppe e comandi la battaglia (+10% e esperienza doppia). [b]Risoluzione automatica[/b]: esito immediato.
Le [b]fortificazioni[/b] costruite nel rifornimento aiutano qui; in difesa basta [b]tenere gli obiettivi[/b] fino allo scadere dei 5 minuti, e i territori vicini mandano [b]rinforzi[/b] a metà battaglia."
		"done":
			return "Ottimo, comandante! Ora conosci il turno completo.\nLe icone a [b]sinistra[/b] aprono obiettivo, potenze, carte, mercato, continenti e registro. [b]F1[/b] apre la guida completa. Buona campagna!"
	return ""

# ------------------------------------------------------------------ avanzamento (4 Hz)
func update() -> void:
	if not active or main == null:
		return
	var g = main.game
	if g == null or not main.human_alive() or g.over != null:
		stop(false)
		return
	var ph: String = main.phase_key()
	var mine: bool = main.my_turn()
	match step:
		"deploy":
			if _pool() <= 0:
				_go("army")
			elif not mine or ph != "supply":
				_go("source" if mine else "ai")
		"army":
			if not mine or ph != "supply":
				_go("source" if mine else "ai")
		"recruit":
			if _queued() > _q0:
				_go("endphase")
			elif ph != "supply":
				_go("source" if mine else "ai")
		"endphase":
			if not mine:
				_go("ai")
			elif ph != "supply":
				_go("source")
		"source":
			if not mine:
				_go("ai")
			elif main.attack_used() or main.move_used() or ph == "move":
				_go("result" if ph != "move" else "move")
			elif main.modal_kind == "attack":
				_go("panel")
			elif main.sel_own() and not main.targets.is_empty():
				_go("target")
		"target":
			if main.modal_kind == "attack":
				_go("panel")
			elif main.attack_used():
				_go("result")
			elif not (main.sel_own() and not main.targets.is_empty()):
				_go("source")
			elif main.sel != _src:
				_go("target")
		"panel":
			if main.attack_used():
				if main.modal_kind == "" or main.modal_kind == "summary":
					_go("result")
			elif main.modal_kind == "" and main.battle == null:
				_go("source")
		"result", "skipatk":
			if not mine:
				_go("ai")
			elif ph == "move":
				_go("move")
		"move":
			if not mine:
				_go("ai")
			elif main.move_used():
				_go("endturn")
		"endturn":
			if not mine:
				_go("ai")
		"ai":
			if main.modal_kind == "battle" and g.pending_battle != null and String(g.pending_battle.get("human_side", "")) == "def":
				_go("defense")
			elif mine and main.modal_kind == "":
				_go("done")
		"defense":
			if main.modal_kind != "battle":
				_go("ai")

func _process(dt: float) -> void:
	if not active or main == null or main.game == null:
		if _rect != null:
			_rect = null
			queue_redraw()
		return
	_t += dt
	# nascosto in battaglia 3D e sotto le finestre che non c'entrano (menu, guida, riepiloghi)
	var allowed := ["", "attack", "move", "battle"]
	var hid: bool = main.battle != null or not (main.modal_kind in allowed) or (main.modal_kind == "battle" and step != "defense")
	if step in ["panel"] and main.modal_kind != "attack":
		hid = true
	panel.visible = not hid and step != ""
	_rect = null if hid else _target_rect()
	if panel.visible:
		_place()
	queue_redraw()

# ------------------------------------------------------------------ bersagli della freccia
func _target_rect():
	match step:
		"deploy":
			return _terr_rect(_hq())
		"recruit":
			var b := _find_button(main.hud.rp.get("recruit"), "+1")
			return b.get_global_rect() if b != null else null
		"army":
			var rc: Control = main.hud.rp.get("recruit")
			return rc.get_global_rect() if rc != null and rc.is_visible_in_tree() else null
		"endphase", "result", "skipatk", "endturn":
			var gm: Button = main.hud.g_main
			return gm.get_global_rect() if gm != null and gm.is_visible_in_tree() else null
		"source":
			return _terr_rect(_src)
		"target":
			return _terr_rect(_tgt)
		"panel":
			var b := _find_button(main.modal, "risoluzione automatica")
			return b.get_global_rect() if b != null else null
		"defense":
			var b := _find_button(main.modal, "Difendi")
			return b.get_global_rect() if b != null else null
		"done":
			var r: Control = main.hud.rail
			return r.get_global_rect() if r != null and r.is_visible_in_tree() else null
	return null

func _terr_rect(t: int):
	var m = main.map
	if t < 0 or m == null or not ("_badge_pos" in m):
		return null
	var bp: Array = m._badge_pos
	if t >= bp.size() or not (bp[t] is Vector2):
		return null
	var p: Vector2 = bp[t]
	var vs := get_viewport_rect().size
	if p.x < -40 or p.y < -40 or p.x > vs.x + 40 or p.y > vs.y + 40:
		return null
	return Rect2(p - Vector2(36, 36), Vector2(72, 72))

func _find_button(n, needle: String) -> Button:
	if n == null or not (n is Node):
		return null
	if n is Button and (n as Button).is_visible_in_tree() and String((n as Button).text).find(needle) >= 0:
		return n
	for c in (n as Node).get_children():
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null

# ------------------------------------------------------------------ posizione del riquadro e freccia
func _place() -> void:
	var vs := get_viewport_rect().size
	panel.reset_size()
	var S := panel.size
	var cands: Array = []
	if _rect is Rect2:
		var R: Rect2 = _rect
		var cx := R.get_center().x - S.x / 2
		var cy := R.get_center().y - S.y / 2
		var above := Vector2(cx, R.position.y - S.y - 70)
		var below := Vector2(cx, R.end.y + 70)
		var left := Vector2(R.position.x - S.x - 80, cy)
		var right := Vector2(R.end.x + 80, cy)
		if step in ["panel", "defense"] and main.modal.panel != null and main.modal.panel.visible:
			# fuori dalla finestra: non deve coprire cursori e pulsanti
			var MR: Rect2 = main.modal.panel.get_global_rect()
			var mx := MR.get_center().x - S.x / 2
			cands = [Vector2(mx, MR.end.y + 12), Vector2(mx, MR.position.y - S.y - 12),
				Vector2(MR.position.x - S.x - 24, R.position.y - S.y * 0.5), Vector2(MR.end.x + 24, R.position.y - S.y * 0.5), left]
		elif step in ["panel", "defense", "recruit", "army"]:
			cands = [left, right, above, below]
		elif step == "done":
			cands = [right]
		else:
			cands = [above, below, left, right]
	cands.append(Vector2(90, 120))
	var guide_r: Rect2 = main.hud.guide.get_global_rect() if main.hud.guide.visible else Rect2()
	var best: Vector2 = cands[cands.size() - 1]
	for c in cands:
		var r := Rect2(c, S)
		if r.position.x < 8 or r.position.y < 60 or r.end.x > vs.x - 8 or r.end.y > vs.y - 8:
			continue
		if _rect is Rect2 and r.grow(10).intersects(_rect):
			continue
		if guide_r.size.x > 0 and r.intersects(guide_r) and not step in ["endphase", "result", "skipatk", "endturn"]:
			continue
		best = c
		break
	panel.position = best.round()

func _draw() -> void:
	if not (_rect is Rect2) or not panel.visible:
		return
	var R: Rect2 = _rect
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var col := Color(UIKit.AMBER2, 0.75 + 0.25 * pulse)
	var g := R.grow(4.0 + 5.0 * pulse)
	draw_rect(g, Color(UIKit.AMBER, 0.10 * pulse), true)
	draw_rect(g, col, false, 3.0)
	# freccia dal riquadro del tutorial al bersaglio
	var P := Rect2(panel.position, panel.size)
	var tc := R.get_center()
	var a := Vector2(clampf(tc.x, P.position.x + 20, P.end.x - 20), clampf(tc.y, P.position.y + 14, P.end.y - 14))
	if tc.y < P.position.y:
		a.y = P.position.y
	elif tc.y > P.end.y:
		a.y = P.end.y
	elif tc.x < P.position.x:
		a.x = P.position.x
	else:
		a.x = P.end.x
	var dir := (tc - a)
	if dir.length() < 30:
		return
	dir = dir.normalized()
	# punta sul bordo del rettangolo evidenziato
	var b := tc
	for i in 60:
		if not g.has_point(b):
			break
		b -= dir * 4.0
	b -= dir * (6.0 + 6.0 * pulse)
	draw_line(a, b, Color(0, 0, 0, 0.45), 8.0, true)
	draw_line(a, b, col, 4.0, true)
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([b + dir * 14.0, b - dir * 6.0 + n * 11.0, b - dir * 6.0 - n * 11.0]), col)

# ------------------------------------------------------------------ helper di stato
func _pool() -> int:
	return Data.total_units(main.game.players[main.h()]["pool"])

func _hq() -> int:
	return int(main.game.players[main.h()]["hq"])

func _queued() -> int:
	var n := 0
	for tr in main.game.terr:
		if int(tr["owner"]) == main.h():
			n += (tr["queue"] as Array).size()
	return n

func _focus(t: int) -> void:
	if t >= 0 and main.map != null and main.map.has_method("focus"):
		main.map.focus(t)

## Bersaglio consigliato: quello con meno difensori visibili tra quelli evidenziati.
func _best_target() -> int:
	var best := -1
	var bv := 1e9
	for x in main.targets:
		var j := int(x["idx"])
		var f = main.gcall("visible_forces", [main.h(), j], main.game.terr[j]["forces"])
		var n := float(Data.total_units(f)) if f is Dictionary else float(maxi(0, main.estimate(j))) + 0.5
		if n < bv:
			bv = n
			best = j
	return best
