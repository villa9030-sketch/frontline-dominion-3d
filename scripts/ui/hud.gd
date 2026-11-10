extends Control
## HUD della partita (riorganizzata per chiarezza, vedi docs/ux_plan.md):
## - barra in alto: risorse, tecnologia/ricerca, guida, audio, menu;
## - barra dei turni: turno, di chi è il turno, fasi ①②③, tregua;
## - riquadro ORDINI in basso al centro: cosa fare adesso, esito dell'ultima azione, pulsante principale contestuale;
## - barra a icone a sinistra che apre un cassetto (obiettivo, potenze, carte, mercato, continenti, registro), chiuso di default;
## - pannello del territorio a destra: riassunto + schede Recluta / Edifici / Fortifica (solo rifornimento, solo propri).
## Vista pura: legge lo stato da main (controller) e chiama main.act(...).

const TOP_H := 50.0
const BOT_H := 0.0          # niente più barra inferiore (carte e registro sono nel cassetto)
const M := 8.0
const LEFT_W := 340.0       # larghezza del cassetto
const RIGHT_W := 360.0
const RAIL_W := 66.0
const GUIDE_W := 720.0
# scala tipografica unica
const FS_TITLE := 18
const FS_BODY := 14
const FS_SMALL := 12
## Schede della barra a sinistra: [chiave, icona, nome, tooltip]
const TABS := [
	["obj", "flag", "Obiettivo", "Obiettivo della partita, rinforzi a ogni turno e tregua"],
	["players", "power", "Potenze", "Le potenze in campo: territori, forza stimata, carte e patti di non aggressione"],
	["cards", "card", "Carte", "Carte comando: un tris di carte dà rinforzi o un'operazione speciale (missile, sabotaggio, golpe)"],
	["market", "money", "Mercato", "Mercato internazionale: compra e vendi petrolio, acciaio e manodopera (solo nel rifornimento)"],
	["conts", "globe", "Continenti", "Continenti: chi ne controlla uno intero riceve rinforzi extra a ogni turno"],
	["log", "news", "Registro", "Registro operazioni: tutto ciò che è successo, turno per turno"],
]
const TAB_SECS := {"obj": ["scn", "obj", "rein"], "players": ["players"], "cards": ["cards"], "market": ["market"], "conts": ["conts"], "log": ["log"]}

var rail: PanelContainer
var rail_btns := {}          # tab -> {b, badge, bl}
var drawer_tab := ""
var drawer_title: Label
var _log_seen := 0           # eventi del registro già visti (badge)
var _rail_key := ""
var rtab := "recruit"        # scheda del pannello territorio: recruit | build | fort
# riquadro ORDINI
var guide: PanelContainer
var g_phase: Label
var g_fb: Label
var g_text: RichTextLabel
var g_sub: Label
var g_main: Button
var g_alt: Button
var _g_state := {}
var _g_key := ""
var _fb_text := ""
var _fb_kind := "good"
var _fb_t := -100.0
var _fb_secs := 8.0
const CARD_ICON := {"inf": "inf", "tank": "tank", "air": "jet", "jolly": "star"}
const CARD_COL := {"inf": Color("#cfe0c8"), "tank": Color("#ff9a7a"), "air": Color("#8ac8ff"), "jolly": Color("#ffd84a")}

var main = null
var game = null

var top: PanelContainer
var res_box: HBoxContainer
var res_val := {}
var res_rate := {}
var res_chip := {}
var tech_box: HBoxContainer
var clock_lbl: Label
var speed_btns := {}
var pause_btn: Button
var audio_btn: Button
var audio_icon: UIIcon
var pause_icon: UIIcon
var pause_lbl: Label

var left: PanelContainer
var left_scroll: ScrollContainer
var left_v: VBoxContainer
var lp := {}
var right: PanelContainer
var right_scroll: ScrollContainer
var right_v: VBoxContainer
var rp := {}

var bottom: HBoxContainer
var cards_panel: PanelContainer
var cards_v: VBoxContainer
var pool_panel: PanelContainer
var pool_v: VBoxContainer
var log_panel: PanelContainer
var log_text: RichTextLabel
var _log_key := ""

var banner: PanelContainer
var banner_lbl: Label
var pause_tag: Control
var tip: PanelContainer
var tip_text: RichTextLabel
var _tip_key := ""
var alert_frame: Panel
var threat_btn: Button
var threat_lbl: Label
var _threat_tw: Tween
var _alert_tw: Tween
var speed_seg: Control
var clock_box: Control

# barra dei turni (FASE 6)
var turn_bar: PanelContainer
var tb_stripe: ColorRect
var tb_title: Label
var tb_sub: Label
var tb_chips := {}
var tb_truce: PanelContainer
var tb_truce_lbl: Label
var tb_phase_btn: Button
var tb_end_btn: Button
var tb_fast: Label
var tb_hint: Label
var tb_hint_p: PanelContainer
var _tb_key := ""
var _tbanner: PanelContainer
var _tbanner_tw: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_left()
	_build_rail()
	_build_right()
	_build_bottom()
	_build_turn_bar()
	_build_guide()
	_build_overlays()

# ================================================================== costruzione statica
func _panel(accent: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UIKit.panel_box()
	if accent.a > 0:
		sb.border_width_top = 2
		sb.border_color = Color(accent, 0.6)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

func _build_top() -> void:
	top = PanelContainer.new()
	var sb := UIKit.box(Color(0.03, 0.055, 0.058, 0.94), UIKit.LINE2, 0, 0, Vector4(12, 6, 10, 6))
	sb.border_width_bottom = 1
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	top.add_theme_stylebox_override("panel", sb)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var hb := UIKit.hbox(10)
	top.add_child(hb)
	var brand := UIKit.hbox(5)
	brand.add_child(UIKit.label("FRONTLINE", 15, UIKit.DIM, "mono", 700))
	brand.add_child(UIKit.label("DOMINION", 15, UIKit.AMBER, "mono", 700))
	hb.add_child(brand)
	hb.add_child(_vsep())
	res_box = UIKit.hbox(6)
	hb.add_child(res_box)
	for k in Data.RES_KEYS:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.32), UIKit.LINE, 1, 3, Vector4(7, 1, 8, 1)))
		chip.tooltip_text = "%s: quantità disponibile e variazione netta a ogni turno (entrate meno mantenimento)" % Data.RES_NAMES[k]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var c := UIKit.hbox(7)
		c.add_child(UIKit.icon(k, 22))
		var cv := UIKit.vbox(-3)
		var v := UIKit.label("0", 17, UIKit.WHITE, "mono", 700)
		v.custom_minimum_size.x = 64
		cv.add_child(v)
		var r := UIKit.label("+0/min", 11, UIKit.GREEN, "mono", 400)
		cv.add_child(r)
		c.add_child(cv)
		chip.add_child(c)
		res_box.add_child(chip)
		res_val[k] = v
		res_rate[k] = r
		res_chip[k] = chip
	hb.add_child(_vsep())
	tech_box = UIKit.hbox(8)
	hb.add_child(tech_box)
	hb.add_child(UIKit.spacer())
	threat_btn = UIKit.button("", "danger", "sm", main_act.bind("threat", {}), "Attacchi nemici in arrivo sui tuoi territori: clic per inquadrarli")
	threat_btn.custom_minimum_size = Vector2(170, 30)
	var tbh := UIKit.hbox(6)
	tbh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tbh.alignment = BoxContainer.ALIGNMENT_CENTER
	tbh.add_child(UIKit.icon("alert", 15, Color("#ffd0c0")))
	threat_lbl = UIKit.label("", 12, Color("#ffe2dc"), "sans", 700)
	tbh.add_child(threat_lbl)
	threat_btn.add_child(tbh)
	threat_btn.visible = false
	hb.add_child(threat_btn)
	var clk := UIKit.hbox(5)
	clock_box = clk
	clk.add_child(UIKit.icon("clock", 18))
	clock_lbl = UIKit.label("00:00", 20, UIKit.AMBER2, "mono", 700)
	clk.add_child(clock_lbl)
	hb.add_child(clk)
	hb.add_child(_vsep())
	var seg := UIKit.hbox(2)
	speed_seg = seg
	for s in [0.5, 1.0, 2.0, 3.0]:
		var txt := "½×" if s == 0.5 else "%d×" % int(s)
		var b := UIKit.button(txt, "normal", "sm", main_act.bind("speed", {"v": s}), "Velocità %s (tasto %s)" % [txt, "0" if s == 0.5 else str(int(s))])
		b.toggle_mode = true
		b.custom_minimum_size.x = 38
		seg.add_child(b)
		speed_btns[s] = b
	hb.add_child(seg)
	pause_btn = UIKit.button("", "normal", "sm", main_act.bind("pause", {}), "Pausa (Spazio)")
	pause_btn.toggle_mode = true
	pause_btn.custom_minimum_size = Vector2(98, 30)
	var pb := UIKit.hbox(6)
	pb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_icon = UIKit.icon("pause", 14)
	pb.add_child(pause_icon)
	pause_lbl = UIKit.label("Pausa", 12, UIKit.TEXT, "sans", 600)
	pb.add_child(pause_lbl)
	pause_btn.add_child(pb)
	hb.add_child(pause_btn)
	var hb_help := UIKit.button("", "normal", "sm", main_act.bind("help", {}), "Guida completa (F1)")
	hb_help.custom_minimum_size = Vector2(34, 30)
	var hic := UIKit.icon("help", 16)
	hic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb_help.add_child(hic)
	hb.add_child(hb_help)
	audio_btn = UIKit.button("", "normal", "sm", main_act.bind("audio", {}), "Audio attivo / muto")
	audio_btn.custom_minimum_size = Vector2(34, 30)
	audio_icon = UIKit.icon("sound", 16)
	audio_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio_btn.add_child(audio_icon)
	hb.add_child(audio_btn)
	var mb := UIKit.button("", "normal", "sm", main_act.bind("menu", {}), "Menu di pausa (Esc)")
	mb.custom_minimum_size = Vector2(84, 30)
	var mh := UIKit.hbox(6)
	mh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mh.alignment = BoxContainer.ALIGNMENT_CENTER
	mh.add_child(UIKit.icon("menu", 14))
	mh.add_child(UIKit.label("Menu", 12, UIKit.TEXT, "sans", 600))
	mb.add_child(mh)
	hb.add_child(mb)

## Durata in turni (FASE 6) o secondi (tempo reale).
func _dur(turns: int, secs: float) -> String:
	if main != null and main.turn_mode():
		return "%d turn%s" % [turns, "o" if turns == 1 else "i"]
	return "%d s" % int(round(secs))

func _unit_turns(k: String) -> int:
	return int(Data.TURNS["units"].get(k, 1)) if "TURNS" in Data else 1

func _bld_turns(k: String) -> int:
	return int(Data.TURNS["buildings"].get(k, 1)) if "TURNS" in Data else 1

func main_act(a: String, ds: Dictionary) -> void:
	if main:
		main.act(a, ds)

func _vsep() -> Control:
	var r := ColorRect.new()
	r.color = UIKit.LINE
	r.custom_minimum_size = Vector2(1, 28)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _side_panel(is_left: bool) -> Array:
	var p := _panel()
	p.position = Vector2(M, TOP_H + M) if is_left else Vector2(0, TOP_H + M)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2((LEFT_W if is_left else RIGHT_W) - 24, 100)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(sc)
	var v := UIKit.vbox(9)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	add_child(p)
	return [p, sc, v]

## Cassetto a sinistra (chiuso di default): una scheda alla volta, aperta dalla barra a icone.
func _build_left() -> void:
	var a := _side_panel(true)
	left = a[0]; left_scroll = a[1]; left_v = a[2]
	left.position = Vector2(M + RAIL_W + 6, TOP_H + M)
	left.visible = false
	var hh := UIKit.hbox(8)
	drawer_title = UIKit.label("", FS_TITLE, UIKit.AMBER2, "cond", 700)
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(drawer_title)
	var xb := UIKit.button("✕", "ghost", "xs", func(): toggle_tab(""), "Chiudi il pannello")
	xb.custom_minimum_size = Vector2(28, 26)
	hh.add_child(xb)
	left_v.add_child(hh)
	for k in ["scn", "obj", "rein", "players", "market", "conts", "cards", "log"]:
		var c := UIKit.vbox(5)
		left_v.add_child(c)
		lp[k] = c

## Barra a icone verticale (sempre visibile in partita): apre/chiude le schede del cassetto. Badge = novità.
func _build_rail() -> void:
	rail = PanelContainer.new()
	var sb := UIKit.box(Color(0.03, 0.05, 0.052, 0.90), UIKit.LINE, 1, 6, Vector4(5, 6, 5, 6))
	rail.add_theme_stylebox_override("panel", sb)
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.position = Vector2(M, TOP_H + M)
	var v := UIKit.vbox(4)
	for T in TABS:
		var k: String = T[0]
		var b := UIKit.button("", "ghost", "xs", toggle_tab.bind(k), "%s — %s" % [T[2], T[3]])
		b.custom_minimum_size = Vector2(RAIL_W - 10, 54)
		b.toggle_mode = true
		var bv := UIKit.vbox(1)
		bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := UIKit.icon(T[1], 22)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bv.add_child(ic)
		var nl := UIKit.label(T[2], 11, UIKit.TEXT, "sans", 600)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(nl)
		b.add_child(bv)
		var bp := PanelContainer.new()
		bp.add_theme_stylebox_override("panel", UIKit.box(UIKit.AMBER, Color(0, 0, 0, 0), 0, 8, Vector4(5, 0, 5, 0)))
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bp.position = Vector2(RAIL_W - 30, 1)
		var bl := UIKit.label("", 11, Color("#1a1205"), "mono", 700)
		bp.add_child(bl)
		bp.visible = false
		b.add_child(bp)
		v.add_child(b)
		rail_btns[k] = {"b": b, "badge": bp, "bl": bl}
	rail.add_child(v)
	add_child(rail)

## Apre una scheda del cassetto ("" = chiude; la stessa scheda di nuovo = chiude).
func toggle_tab(k: String) -> void:
	drawer_tab = "" if (k == drawer_tab or not TAB_SECS.has(k)) else k
	if drawer_tab == "log" and game != null:
		_log_seen = _player_events()
	_rail_key = ""
	_apply_drawer()
	if game != null:
		_refresh_rail()
		_fit_panels()
		_place_turn_bar()

func _apply_drawer() -> void:
	for k in rail_btns:
		(rail_btns[k]["b"] as Button).set_pressed_no_signal(k == drawer_tab)
	left.visible = drawer_tab != "" and rail.visible
	var shown: Array = TAB_SECS.get(drawer_tab, [])
	for k in lp:
		(lp[k] as Control).visible = shown.has(k)
	for T in TABS:
		if T[0] == drawer_tab:
			drawer_title.text = String(T[2]).to_upper() if drawer_tab != "obj" else "OBIETTIVO"
	if left.visible:
		left.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(left, "modulate:a", 1.0, 0.14)

## Numero di eventi del registro che riguardano il giocatore (per il badge «Registro»).
func _player_events() -> int:
	var hh: int = main.h()
	var n := 0
	for e in game.events:
		if hh < 0 or e.get("player") == null or int(e["player"]) == hh:
			n += 1
	return n

## Badge della barra a icone: carte in mano (ambra se c'è un tris), notizie non lette nel registro, turni rimasti.
func _refresh_rail() -> void:
	var hh: int = main.h()
	var cards := 0
	var set_ok := false
	if hh >= 0:
		cards = (game.players[hh]["cards"] as Array).size()
		set_ok = main.gcall("find_set", [hh]) != null
	var unread := maxi(0, _player_events() - _log_seen) if drawer_tab != "log" else 0
	if drawer_tab == "log":
		_log_seen = _player_events()
	var st: Dictionary = main.scenario_status() if main.current_scenario() != null else {}
	var rl := int(st.get("rounds_left", -1))
	var key := "%d|%s|%d|%d|%s" % [cards, str(set_ok), unread, rl, drawer_tab]
	if key == _rail_key:
		return
	_rail_key = key
	_badge("cards", str(cards) if cards > 0 else "", set_ok, "Hai un tris di carte da giocare nel rifornimento" if set_ok else "")
	_badge("log", ("9+" if unread > 9 else str(unread)) if unread > 0 else "", false, "")
	_badge("obj", ("%dT" % rl) if rl >= 0 and rl <= 5 else "", rl >= 0 and rl <= 3, "Turni rimasti allo scenario")
	(rail_btns["cards"]["b"] as Button).visible = hh >= 0
	(rail_btns["market"]["b"] as Button).visible = hh >= 0

func _badge(k: String, text: String, hot: bool, extra_tip: String) -> void:
	var d: Dictionary = rail_btns[k]
	var bp: PanelContainer = d["badge"]
	bp.visible = text != ""
	(d["bl"] as Label).text = text
	var col: Color = Color("#ff8a50") if hot else (UIKit.AMBER if k == "cards" else Color("#9fb6a6"))
	bp.add_theme_stylebox_override("panel", UIKit.box(col, Color(0, 0, 0, 0), 0, 8, Vector4(5, 0, 5, 0)))
	bp.reset_size()
	bp.position = Vector2(RAIL_W - 10 - bp.size.x - 2, 2)
	var b: Button = d["b"]
	var base := ""
	for T in TABS:
		if T[0] == k:
			base = "%s — %s" % [T[2], T[3]]
	b.tooltip_text = base + (("\n" + extra_tip) if extra_tip != "" and text != "" else "")
	if hot and not b.has_meta("pulse"):
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "modulate", Color(1.35, 1.2, 0.9), 0.5)
		tw.tween_property(b, "modulate", Color(1, 1, 1), 0.5)
		b.set_meta("pulse", tw)
	elif not hot and b.has_meta("pulse"):
		(b.get_meta("pulse") as Tween).kill()
		b.remove_meta("pulse")
		b.modulate = Color(1, 1, 1)

func _build_right() -> void:
	var a := _side_panel(false)
	right = a[0]; right_scroll = a[1]; right_v = a[2]
	right.visible = false
	for k in ["head", "forces", "deploy", "orders", "tabs", "recruit", "queue", "blist", "bbtns", "fort", "send"]:
		var c := UIKit.vbox(5)
		right_v.add_child(c)
		rp[k] = c

## Carte e registro vivono nel cassetto; i rinforzi nel riquadro ORDINI e nel pannello del territorio.
func _build_bottom() -> void:
	cards_v = lp["cards"]
	pool_v = UIKit.vbox(3)   # non più mostrato (compatibilità)
	var lv: VBoxContainer = lp["log"]
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_active = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_override("normal_font", UIKit.font("sans", 400))
	log_text.add_theme_font_override("mono_font", UIKit.font("mono", 400))
	log_text.add_theme_font_size_override("normal_font_size", 13)
	log_text.add_theme_font_size_override("mono_font_size", 12)
	log_text.add_theme_constant_override("line_separation", 2)
	log_text.add_theme_color_override("default_color", UIKit.TEXT)
	log_text.mouse_filter = Control.MOUSE_FILTER_PASS
	log_text.custom_minimum_size = Vector2(LEFT_W - 30, 440)
	lv.add_child(log_text)

# ================================================================== riquadro ORDINI (cosa fare adesso)
func _build_guide() -> void:
	guide = PanelContainer.new()
	guide.mouse_filter = Control.MOUSE_FILTER_STOP
	guide.custom_minimum_size.x = GUIDE_W
	guide.visible = false
	var h := UIKit.hbox(16)
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g_phase = UIKit.label("", FS_SMALL, UIKit.AMBER, "mono", 700)
	v.add_child(g_phase)
	g_fb = UIKit.label("", 13, UIKit.GREEN, "sans", 600)
	g_fb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g_fb.visible = false
	v.add_child(g_fb)
	g_text = UIKit.rich("", 16, UIKit.WHITE)
	g_text.custom_minimum_size.x = GUIDE_W - 310
	v.add_child(g_text)
	g_sub = UIKit.label("", FS_SMALL, UIKit.DIM)
	g_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(g_sub)
	h.add_child(v)
	var bv := UIKit.vbox(6)
	bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g_main = UIKit.button("", "primary", "big", func(): _guide_act("main"))
	g_main.custom_minimum_size = Vector2(250, 48)
	g_main.add_theme_font_override("font", UIKit.font("sans", 700))
	bv.add_child(g_main)
	g_alt = UIKit.button("", "ghost", "sm", func(): _guide_act("alt"))
	g_alt.custom_minimum_size = Vector2(250, 28)
	bv.add_child(g_alt)
	h.add_child(bv)
	guide.add_child(h)
	add_child(guide)

func _guide_act(which: String) -> void:
	var a = _g_state.get(which)
	if a is Dictionary and main != null:
		main.act(String(a.get("act", "")), a.get("ds", {}))

## Esito dell'ultima azione nel riquadro ORDINI (riga «✓ …» per qualche secondo).
func feedback(text: String, kind: String = "good", secs: float = 8.0) -> void:
	_fb_text = text
	_fb_kind = kind
	_fb_secs = secs
	_fb_t = Time.get_ticks_msec() / 1000.0
	_g_key = ""
	if game != null:
		_refresh_guide()

func _refresh_guide() -> void:
	var tm: bool = main.turn_mode() and main.h() >= 0
	guide.visible = tm and main.modal_kind == ""
	if not guide.visible:
		return
	var st: Dictionary = main.guide_state()
	var now := Time.get_ticks_msec() / 1000.0
	var fb := _fb_text if now - _fb_t < _fb_secs else ""
	var key := str(st) + "|" + fb
	if key != _g_key:
		_g_key = key
		_g_state = st
		var col: Color = st.get("col", UIKit.AMBER)
		var sb := UIKit.box(Color(0.03, 0.05, 0.05, 0.95), Color(col, 0.45), 1, 6, Vector4(16, 12, 14, 12))
		sb.border_width_left = 5
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 12
		guide.add_theme_stylebox_override("panel", sb)
		g_phase.text = String(st.get("phase", ""))
		g_phase.add_theme_color_override("font_color", col.lightened(0.2))
		g_fb.visible = fb != ""
		g_fb.text = ("✓ " if _fb_kind == "good" else "• ") + fb
		g_fb.add_theme_color_override("font_color", UIKit.GREEN if _fb_kind == "good" else (Color("#ffb59a") if _fb_kind == "bad" else Color("#cfe0c8")))
		g_text.text = String(st.get("text", ""))
		var sub := String(st.get("sub", ""))
		g_sub.text = sub
		g_sub.visible = sub != ""
		for pair in [[g_main, st.get("main")], [g_alt, st.get("alt")]]:
			var b: Button = pair[0]
			var d = pair[1]
			b.visible = d is Dictionary
			if d is Dictionary:
				b.text = String(d.get("text", ""))
				b.tooltip_text = String(d.get("tip", ""))
				b.disabled = bool(d.get("disabled", false))
		var mk := String((st.get("main") as Dictionary).get("kind", "primary")) if st.get("main") is Dictionary else "primary"
		var bs := UIKit._btn_styles(mk)
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var x: StyleBoxFlat = (bs[s] as StyleBoxFlat).duplicate()
			x.content_margin_left = 20; x.content_margin_right = 20
			x.content_margin_top = 10; x.content_margin_bottom = 10
			g_main.add_theme_stylebox_override(s, x)
	# il testo a capo (RichTextLabel fit_content) conosce la propria altezza solo dopo un passaggio di layout:
	# ricalcolo sempre la dimensione (costa poco)
	g_text.size.x = g_text.custom_minimum_size.x
	guide.size = Vector2.ZERO
	guide.reset_size()
	var vs := get_viewport_rect().size
	guide.position = Vector2(round((vs.x - guide.size.x) / 2), vs.y - guide.size.y - 14)

## Rettangolo del riquadro ORDINI (per toast e tutorial).
func guide_top() -> float:
	return guide.position.y if guide.visible else get_viewport_rect().size.y - 14

# ================================================================== barra dei turni (FASE 6)
const TB_Y := TOP_H - 1.0
const UNDER_TB := TOP_H + 76.0    # sotto barra dei turni + suggerimento: banner, notizie, toast

func _build_turn_bar() -> void:
	turn_bar = PanelContainer.new()
	var sb := UIKit.box(Color(0.03, 0.05, 0.052, 0.96), UIKit.LINE2, 1, 0, Vector4(0, 5, 10, 6))
	sb.border_width_top = 0
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	turn_bar.add_theme_stylebox_override("panel", sb)
	turn_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	turn_bar.visible = false
	var hb := UIKit.hbox(10)
	tb_stripe = ColorRect.new()
	tb_stripe.custom_minimum_size = Vector2(5, 36)
	tb_stripe.color = UIKit.AMBER
	tb_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tb_stripe)
	var tv := UIKit.vbox(-2)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var th := UIKit.hbox(6)
	th.add_child(UIKit.icon("turn", 15))
	tb_title = UIKit.label("TURNO 1", 16, UIKit.AMBER2, "mono", 700)
	th.add_child(tb_title)
	tv.add_child(th)
	tb_sub = UIKit.label("Tocca a te", 13, UIKit.WHITE, "sans", 600)
	tb_sub.custom_minimum_size.x = 190
	tb_sub.clip_text = true
	tb_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(tb_sub)
	hb.add_child(tv)
	hb.add_child(_vsep())
	var chips := UIKit.hbox(3)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icons := {"supply": "reinforce", "attack": "attack", "move": "move"}
	var names := {"supply": "1 RIFORNIMENTO", "attack": "2 ATTACCO", "move": "3 SPOSTAMENTO"}
	var tips := {"supply": "Fase 1 · Rifornimento: schiera i rinforzi, recluta, costruisci, fortifica, ricerca, commercia, gioca le carte",
		"attack": "Fase 2 · Attacco: al massimo un attacco per turno, da un tuo territorio con almeno 2 unità a un nemico confinante (o via mare con un porto). Facoltativo",
		"move": "Fase 3 · Spostamento: un trasferimento di truppe tra tuoi territori collegati. Facoltativo. Poi «Fine turno»"}
	var i := 0
	for k in ["supply", "attack", "move"]:
		if i > 0:
			var ar := UIKit.label("›", 18, UIKit.DIM, "mono", 700)
			ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chips.add_child(ar)
		var cp := PanelContainer.new()
		cp.mouse_filter = Control.MOUSE_FILTER_PASS
		cp.tooltip_text = tips[k]
		var ch := UIKit.hbox(5)
		var ic := UIKit.icon(icons[k], 15)
		ch.add_child(ic)
		var cl := UIKit.label(names[k], 12, UIKit.DIM, "mono", 700)
		ch.add_child(cl)
		cp.add_child(ch)
		chips.add_child(cp)
		tb_chips[k] = {"p": cp, "l": cl, "i": ic}
		i += 1
	hb.add_child(chips)
	tb_truce = PanelContainer.new()
	tb_truce.add_theme_stylebox_override("panel", UIKit.box(Color(0.3, 0.6, 0.4, 0.14), Color(0.5, 0.85, 0.6, 0.45), 1, 3, Vector4(7, 3, 8, 3)))
	tb_truce.mouse_filter = Control.MOUSE_FILTER_PASS
	tb_truce.tooltip_text = "Durante la tregua si possono attaccare solo i territori neutrali"
	tb_truce.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var trh := UIKit.hbox(5)
	trh.add_child(UIKit.icon("truce", 14))
	tb_truce_lbl = UIKit.label("", 12, Color("#dff8e4"), "sans", 600)
	trh.add_child(tb_truce_lbl)
	tb_truce.add_child(trh)
	hb.add_child(tb_truce)
	tb_fast = UIKit.label("Spazio: accelera", 12, UIKit.DIM, "mono", 600)
	tb_fast.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tb_fast)
	turn_bar.add_child(hb)
	add_child(turn_bar)
	# (i pulsanti di fase e il suggerimento ora sono nel riquadro ORDINI in basso)
	tb_hint_p = PanelContainer.new()
	tb_hint = UIKit.label("", 12)
	tb_hint_p.add_child(tb_hint)
	tb_hint_p.visible = false

func _chip_style(state: String, col: Color) -> StyleBoxFlat:
	match state:
		"cur":
			var sb := UIKit.box(Color(col, 0.22), Color(col, 0.9), 1, 3, Vector4(8, 3, 9, 3))
			sb.shadow_color = Color(col, 0.30)
			sb.shadow_size = 6
			return sb
		"done":
			return UIKit.box(Color(1, 1, 1, 0.03), Color(UIKit.LINE, 0.25), 1, 3, Vector4(8, 3, 9, 3))
	return UIKit.box(Color(0, 0, 0, 0.25), UIKit.LINE, 1, 3, Vector4(8, 3, 9, 3))

## Aggiorna la barra dei turni (chiamata dal refresh a ~5 Hz).
func _refresh_turn_bar() -> void:
	var tm: bool = main.turn_mode()
	turn_bar.visible = tm
	if not tm:
		tb_hint_p.visible = false
		return
	var cp: int = main.cur_player()
	var mine: bool = main.my_turn()
	var ph: String = main.phase_key()
	var tt: int = main.truce_turns()
	var key := "%d|%d|%s|%s|%d|%s" % [main.round_n(), cp, str(mine), ph, tt, str(main._ai_fast)]
	if key == _tb_key:
		_place_turn_bar()
		return
	_tb_key = key
	var P = game.players[cp] if cp >= 0 and cp < game.players.size() else null
	var col: Color = UIKit.AMBER if (mine or P == null) else (P["color"] as Color)
	tb_stripe.color = col
	tb_title.text = "TURNO %d" % main.round_n()
	if mine:
		tb_sub.text = "Tocca a te"
		tb_sub.add_theme_color_override("font_color", UIKit.WHITE)
	elif P != null:
		tb_sub.text = "Turno %s…" % _di(String(P["name"]))
		tb_sub.add_theme_color_override("font_color", (P["color"] as Color).lightened(0.35))
	else:
		tb_sub.text = "—"
	var order := ["supply", "attack", "move"]
	var pi := order.find(ph)
	for k in order:
		var c: Dictionary = tb_chips[k]
		var ki := order.find(k)
		var st := "cur" if ki == pi else ("done" if pi >= 0 and ki < pi else "next")
		(c["p"] as PanelContainer).add_theme_stylebox_override("panel", _chip_style(st, col))
		(c["l"] as Label).add_theme_color_override("font_color", UIKit.WHITE if st == "cur" else (Color(UIKit.DIM, 0.6) if st == "done" else UIKit.DIM))
		(c["i"] as Control).modulate.a = 1.0 if st == "cur" else 0.45
	tb_truce.visible = tt > 0
	tb_truce_lbl.text = "Tregua: ancora %d turn%s" % [tt, "o" if tt == 1 else "i"]
	tb_fast.visible = not mine and main.h() >= 0
	tb_fast.text = "Animazioni accelerate" if main._ai_fast else "Spazio: accelera"
	tb_truce.tooltip_text = "Tregua: per altri %d turn%s nessuno può attaccare gli altri giocatori, solo i territori neutrali" % [tt, "o" if tt == 1 else "i"]
	turn_bar.tooltip_text = "Turno %d: ogni turno ha tre fasi, poi giocano le IA una dopo l'altra" % main.round_n()
	_place_turn_bar()

## "Federazione Orientale" → "della Federazione Orientale" (preposizione articolata).
static func _di(name: String) -> String:
	var l := name.to_lower()
	if l.begins_with("unione") or l.begins_with("alleanza"):
		return "dell'" + name
	if l.begins_with("stati") or l.begins_with("neutrali"):
		return "degli " + name
	return "della " + name

func _place_turn_bar() -> void:
	var vw := get_viewport_rect().size.x
	turn_bar.reset_size()
	var x: float = roundf((vw - turn_bar.size.x) / 2)
	if left.visible:
		x = maxf(x, left.position.x + left.size.x + 10)   # non sotto il cassetto aperto
	turn_bar.position = Vector2(x, TB_Y)

## Grande striscia d'inizio turno: colore della fazione per le IA, ambra per il giocatore. Svanisce da sola.
func turn_banner(p: int, mine: bool) -> void:
	if game == null or p < 0 or p >= game.players.size():
		return
	var P: Dictionary = game.players[p]
	var col: Color = UIKit.AMBER if mine else (P["color"] as Color)
	if _tbanner == null:
		_tbanner = PanelContainer.new()
		_tbanner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(14)
		var sw := ColorRect.new()
		sw.name = "Sw"
		sw.custom_minimum_size = Vector2(8, 46)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sw)
		var v := UIKit.vbox(-2)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var t := UIKit.label("", 22, UIKit.WHITE, "cond", 700)
		t.name = "T"
		t.add_theme_constant_override("outline_size", 3)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		v.add_child(t)
		var sub := UIKit.label("", 13, UIKit.TEXT, "mono", 600)
		sub.name = "S"
		v.add_child(sub)
		h.add_child(v)
		_tbanner.add_child(h)
		add_child(_tbanner)
	var sb := UIKit.box(Color(col.darkened(0.78), 0.94), Color(col, 0.75), 1, 4, Vector4(0, 8, 26, 8))
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	_tbanner.add_theme_stylebox_override("panel", sb)
	(_tbanner.find_child("Sw", true, false) as ColorRect).color = col
	var tl: Label = _tbanner.find_child("T", true, false)
	var sl: Label = _tbanner.find_child("S", true, false)
	if mine:
		tl.text = "TOCCA A TE · TURNO %d" % main.round_n()
		tl.add_theme_color_override("font_color", UIKit.AMBER2)
		sl.text = "Segui il riquadro ORDINI in basso"
	else:
		tl.text = ("Turno " + _di(String(P["name"]))).to_upper()
		tl.add_theme_color_override("font_color", col.lightened(0.45))
		sl.text = "L'IA muove  ·  Spazio accelera"
	_tbanner.visible = true
	_tbanner.reset_size()
	var vw := get_viewport_rect().size.x
	_tbanner.position = Vector2(round((vw - _tbanner.size.x) / 2), round(get_viewport_rect().size.y * 0.24))
	if _tbanner_tw:
		_tbanner_tw.kill()
	_tbanner.modulate.a = 0.0
	_tbanner_tw = create_tween()
	_tbanner_tw.tween_property(_tbanner, "modulate:a", 1.0, 0.22)
	_tbanner_tw.tween_interval(float(Shot.arg("banner_hold", "1.2")) if mine else float(Shot.arg("banner_hold", "0.9")))
	_tbanner_tw.tween_property(_tbanner, "modulate:a", 0.0, 0.45)
	_tbanner_tw.tween_callback(func(): _tbanner.visible = false)

func turn_banner_visible() -> bool:
	return _tbanner != null and _tbanner.visible

func _build_overlays() -> void:
	banner = PanelContainer.new()
	var bs := UIKit.box(Color(0.24, 0.07, 0.04, 0.94), Color("#ff8a50"), 1, 3, Vector4(16, 7, 10, 7))
	bs.shadow_color = Color(0, 0, 0, 0.5)
	bs.shadow_size = 6
	banner.add_theme_stylebox_override("panel", bs)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = UNDER_TB + 4
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.visible = false
	set_threats([])
	var bh := UIKit.hbox(12)
	bh.add_child(UIKit.icon("target", 18, Color("#ffb080")))
	banner_lbl = UIKit.label("", 14, Color("#ffd8b8"), "mono", 700)
	bh.add_child(banner_lbl)
	bh.add_child(UIKit.button("Annulla (Esc)", "normal", "xs", main_act.bind("cancel-mode", {})))
	banner.add_child(bh)
	add_child(banner)

	pause_tag = UIKit.hbox(14)
	pause_tag.set_anchors_preset(Control.PRESET_CENTER)
	pause_tag.offset_top = -120
	pause_tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_tag.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_tag.add_child(UIKit.icon("pause", 36, Color(1, 0.84, 0.48, 0.85)))
	var pl := UIKit.label("PAUSA", 40, Color(1, 0.84, 0.48, 0.85), "mono", 700)
	pl.add_theme_constant_override("outline_size", 8)
	pl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	pause_tag.add_child(pl)
	pause_tag.visible = false
	add_child(pause_tag)

	alert_frame = Panel.new()
	var af := StyleBoxFlat.new()
	af.bg_color = Color(0, 0, 0, 0)
	af.set_border_width_all(5)
	af.border_color = Color(1, 0.2, 0.15, 0.85)
	af.shadow_color = Color(1, 0.1, 0.05, 0.35)
	af.shadow_size = 0
	alert_frame.add_theme_stylebox_override("panel", af)
	alert_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	alert_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_frame.modulate.a = 0
	add_child(alert_frame)

	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UIKit.box(Color(0.025, 0.045, 0.045, 0.95), UIKit.LINE2, 1, 3, Vector4(10, 7, 10, 7)))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_text = UIKit.rich("", 13)
	tip_text.custom_minimum_size.x = 260
	tip.add_child(tip_text)
	add_child(tip)

# ================================================================== avvio partita
func start(g) -> void:
	game = g
	_log_key = ""
	_tip_key = ""
	for c in lp.values() + rp.values() + [tech_box, cards_v, pool_v]:
		c.set_meta("key", "")
	var spect: bool = main.h() < 0
	res_box.visible = not spect
	banner.visible = false
	set_threats([])
	_log_seen = _player_events()
	_rail_key = ""
	_g_key = ""
	_fb_text = ""
	rtab = "recruit"
	rail.visible = true
	drawer_tab = ""
	# negli scenari l'obiettivo è la prima cosa da sapere: la scheda parte aperta
	if main.current_scenario() != null:
		drawer_tab = "obj"
	_apply_drawer()

func flash_alert() -> void:
	if _alert_tw:
		_alert_tw.kill()
	alert_frame.modulate.a = 0
	_alert_tw = create_tween()
	for i in 2:
		_alert_tw.tween_property(alert_frame, "modulate:a", 1.0, 0.18)
		_alert_tw.tween_property(alert_frame, "modulate:a", 0.0, 0.45)

func set_mode_banner(m) -> void:
	_g_key = ""
	if m == null or (main != null and main.turn_mode()):
		banner.visible = false   # a turni la modalità (schieramento, carta) è spiegata nel riquadro ORDINI
		return
	banner.visible = true
	if m["type"] == "deploy":
		banner_lbl.text = "SCHIERAMENTO RINFORZI — clic su un tuo territorio"
	else:
		banner_lbl.text = String(Data.OPS[m["op"]]["name"]).to_upper() + " — scegli il bersaglio sulla mappa"
	banner.reset_size()
	banner.offset_left = -banner.size.x / 2
	banner.offset_right = banner.size.x / 2

## Ricostruisce il contenuto di una sezione solo se la chiave di stato cambia (come setHTML del JS).
func _sec(c: Control, key: String, fn: Callable) -> void:
	if c.get_meta("key", null) == key:
		return
	c.set_meta("key", key)
	UIKit.clear(c)
	fn.call(c)

# ================================================================== refresh (~5 Hz)
func refresh(_force: bool = false) -> void:
	if game == null or main == null:
		return
	var hh: int = main.h()
	var P = game.players[hh] if hh >= 0 else null
	if P != null:
		for k in Data.RES_KEYS:
			res_val[k].text = str(int(floor(float(P["res"][k]))))
			var tmode: bool = main.turn_mode()
			var r := float(P["rates"].get(k, 0)) * (1.0 if tmode else 60.0)
			res_rate[k].text = ("+" if r >= 0 else "") + (str(int(round(r))) if absf(r) >= 100 or tmode else "%.1f" % r) + ("/turno" if tmode else "/min")
			var bad: bool = r < 0 or (k == "oil" and bool(main.pget(P, ["low_oil", "lowOil"], false)))
			res_rate[k].add_theme_color_override("font_color", UIKit.RED if bad else UIKit.GREEN)
			res_chip[k].add_theme_stylebox_override("panel", UIKit.box(Color(0.25, 0.03, 0.02, 0.4) if bad else Color(0, 0, 0, 0.32), Color(1, 0.35, 0.3, 0.55) if bad else UIKit.LINE, 1, 3, Vector4(7, 1, 8, 1)))
	_refresh_tech(P)
	var tmode2: bool = main.turn_mode()
	clock_lbl.text = UIKit.fmt_time(game.time)
	clock_box.visible = not tmode2
	speed_seg.visible = not tmode2
	pause_btn.visible = not tmode2
	_refresh_turn_bar()
	for s in speed_btns:
		speed_btns[s].set_pressed_no_signal(absf(float(game.speed) - s) < 0.01)
	pause_btn.set_pressed_no_signal(game.paused)
	pause_icon.kind = "play" if game.paused else "pause"
	pause_lbl.text = "Riprendi" if game.paused else "Pausa"
	audio_icon.kind = "mute" if Sfx.muted else "sound"
	pause_tag.visible = game.paused and main.modal_kind == "" and not tmode2
	_refresh_left()
	_refresh_right()
	_refresh_bottom()
	_refresh_log()
	_refresh_rail()
	_refresh_guide()
	_fit_panels()

func _fit_panels() -> void:
	var vh := get_viewport_rect().size.y
	var maxh := vh - TOP_H - 2 * M
	var was_vis := right.visible
	right.visible = main.sel >= 0
	if right.visible and not was_vis:
		right.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(right, "modulate:a", 1.0, 0.16)
	var vw := get_viewport_rect().size.x
	for pair in [[left, left_scroll, left_v], [right, right_scroll, right_v]]:
		var p: PanelContainer = pair[0]
		var sc: ScrollContainer = pair[1]
		var v: VBoxContainer = pair[2]
		var need := v.get_combined_minimum_size().y
		sc.custom_minimum_size.y = minf(need, maxh - 26)
		p.size = Vector2(0, 0)
		p.reset_size()
	right.position = Vector2(vw - right.size.x - M, TOP_H + M)
	left.position = Vector2(M + RAIL_W + 6, TOP_H + M)

func _refresh_tech(P) -> void:
	var hh: int = main.h()
	var key := "spect"
	if P != null:
		var rs = P["research"]
		if rs != null:
			key = "r|%d|%d" % [int(rs["level"]), int(100.0 * float(rs["t"]) / maxf(0.001, float(rs["total"])))]
		elif int(P["tech"]) < 4:
			var rc = main.gcall("research_cost", [hh])
			var ok: bool = rc != null and main.gcall("can_afford", [hh, rc["cost"]], false) and P["alive"] and int(P["hq"]) >= 0
			key = "b|%d|%s|%s|%s" % [int(P["tech"]), str(ok), str(rc), main.supply_block()]
		else:
			key = "max"
		key = str(P["tech"]) + key
	_sec(tech_box, key, func(c: Control):
		if P == null:
			c.add_child(UIKit.label("SPETTATORE", 14, UIKit.AMBER2, "mono", 700))
			return
		var lv: int = int(P["tech"])
		var tl := UIKit.hbox(5)
		tl.add_child(UIKit.icon("tech", 16))
		var tv := UIKit.vbox(-3)
		tv.add_child(UIKit.label("TECH %d" % lv, 14, UIKit.AMBER2, "mono", 700))
		tv.add_child(UIKit.label(Data.TECH_LEVELS[lv]["name"], 11, UIKit.DIM, "sans", 600))
		tl.add_child(tv)
		tl.tooltip_text = "Livello attuale %s: %s.
La tecnologia vale per tutti i tuoi territori." % [UIKit.tech_name(lv), Data.TECH_LEVELS[lv]["desc"]]
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		c.add_child(tl)
		var rs = P["research"]
		if rs != null:
			var pc := int(100.0 * float(rs["t"]) / maxf(0.001, float(rs["total"])))
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(230, 24)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pbar := UIKit.progress(pc, Color(0.24, 0.52, 0.70), 24)
			pbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bar.add_child(pbar)
			var bl := UIKit.label("Ricerca %s  %d%%" % [UIKit.tech_name(int(rs["level"])), pc], 12, UIKit.WHITE, "mono", 700)
			bl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bar.add_child(bl)
			bar.tooltip_text = "Ricerca in corso — " + tech_tip(int(rs["level"]), hh)
			c.add_child(bar)
		elif lv < 4:
			var rc = main.gcall("research_cost", [hh])
			if rc == null:
				rc = {"cost": Data.TECH_LEVELS[lv + 1]["cost"], "time": Data.TECH_LEVELS[lv + 1]["time"]}
			var L: Dictionary = Data.TECH_LEVELS[lv + 1]
			var afford: bool = main.gcall("can_afford", [hh, rc["cost"]], false)
			var ok: bool = afford and P["alive"] and int(P["hq"]) >= 0
			var why := "" if ok else ("Eliminato" if not P["alive"] else ("Serve un QG" if int(P["hq"]) < 0 else "Risorse insufficienti"))
			if ok and main.supply_block() != "":
				ok = false
				why = main.supply_block()
			var rturns := int(rc.get("turns", Data.TURNS["tech"][mini(lv + 1, 4)] if "TURNS" in Data else 1))
			var b := UIKit.button("", "normal", "sm", main_act.bind("research", {}), "%s — pronta in %s%s" % [tech_tip(lv + 1, hh), _dur(rturns, float(rc.get("time", 0))), ("
" + why) if why != "" else ""])
			var bh := UIKit.vbox(-2)
			bh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bh.offset_left = 8
			bh.alignment = BoxContainer.ALIGNMENT_CENTER
			bh.add_child(UIKit.label("Ricerca → " + UIKit.tech_name(lv + 1), 12, UIKit.TEXT if ok else UIKit.DIM, "sans", 600))
			var cr := UIKit.cost_row(rc["cost"], 1.0, 10, P["res"])
			bh.add_child(cr)
			b.add_child(bh)
			b.custom_minimum_size = Vector2(bh.get_combined_minimum_size().x + 16, 38)
			b.disabled = not ok
			c.add_child(b)
		else:
			c.add_child(UIKit.label("Tecnologia massima", 12, UIKit.DIM))
	)

## Testo d'aiuto di un livello tecnologico: cosa sblocca, bonus d'attacco e che vale ovunque.
func tech_tip(lv: int, hh: int) -> String:
	if lv < 1 or lv >= Data.TECH_LEVELS.size():
		return ""
	var units := []
	for k in Data.UNIT_KEYS:
		var need := int(Data.UNITS[k]["tech"])
		if k == "drone" and hh >= 0 and game.players[hh]["fac"]["mods"].has("droneTech"):
			need = int(game.players[hh]["fac"]["mods"]["droneTech"])
		if need == lv:
			units.append(String(Data.UNITS[k]["name"]).to_lower())
	var t := "%s sblocca: %s" % [UIKit.tech_name(lv), UIKit.terms(String(Data.TECH_LEVELS[lv]["desc"]))]
	if units.size():
		t += "
Nuove unità da reclutare: " + ", ".join(units)
	t += "
Attacco di tutte le tue unità +%d%% (rispetto a Tech 1)" % int(round(Data.TECH_COMBAT_BONUS * 100 * (lv - 1)))
	t += "
Vale per tutti i tuoi territori: basta ricercarla una volta."
	return t

# ------------------------------------------------------------------ pannello sinistro
func _refresh_left() -> void:
	var hh: int = main.h()
	var n_terr := {}
	var power := {}
	for P in game.players:
		n_terr[P["idx"]] = 0
		power[P["idx"]] = 0.0
	var cs = main._combat_script
	# con la nebbia la potenza degli avversari è stimata solo da ciò che si vede (niente forze esatte nascoste)
	var fog: bool = main.fog_on()
	for tr in game.terr:
		var o := int(tr["owner"])
		if o >= 0:
			n_terr[o] += 1
			if fog and o != hh and not main.is_vis(int(tr["idx"])):
				var e: int = main.estimate(int(tr["idx"]))
				if e > 0:
					power[o] += _power(cs, {"inf": e})
			else:
				power[o] += _power(cs, tr["forces"])
	for d in game.divisions:
		var o := int(d["owner"])
		if power.has(o):
			if fog and o != hh and not main.is_vis(int(d["from"])) and not main.is_vis(int(d["to"])):
				continue
			power[o] += _power(cs, d["forces"])
	if fog:
		for k in power:
			if int(k) != hh:
				power[k] = round(float(power[k]) / 5.0) * 5.0
	_refresh_scenario()
	var key := ""
	for P in game.players:
		key += "%d,%s,%d,%d,%d,%d,%d,%s;" % [P["idx"], str(P["alive"]), n_terr[P["idx"]], int(power[P["idx"]]), P["cards"].size(), int(P["hq"]), int(P["tech"]), _pact_key(int(P["idx"]), hh)]
	_sec(lp["players"], key, func(c: Control):
		var ph := UIKit.label("Territori, forza stimata e carte di ogni potenza. «Patto?» propone una tregua di alcuni turni.", FS_SMALL, UIKit.DIM)
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(ph)
		for P in game.players:
			c.add_child(_player_row(P, hh, n_terr[P["idx"]], power[P["idx"]]))
	)
	# rinforzi e tregua
	var rk := ""
	if hh >= 0 and game.players[hh]["alive"]:
		var P: Dictionary = game.players[hh]
		rk = "%d|%d|%d" % [int(ceil(float(main.pget(P, ["next_reinforce", "nextReinforce"], 0)))), int(main.gcall("reinforce_amount", [hh], 0)), int(Data.ECON["truce"] - game.time) if game.time < Data.ECON["truce"] else -1]
		if main.turn_mode():
			rk = "T%d|%d" % [int(main.gcall("reinforce_amount", [hh], 0)), main.truce_turns()]
	_sec(lp["rein"], rk, func(c: Control):
		if rk == "":
			return
		if main.turn_mode():
			var rr := UIKit.hbox(7)
			rr.add_child(UIKit.icon("reinforce", 15))
			rr.add_child(UIKit.label("Rinforzi a ogni turno", 13, UIKit.TEXT))
			rr.add_child(UIKit.spacer())
			rr.add_child(UIKit.label("+%d unità" % int(main.gcall("reinforce_amount", [hh], 0)), 14, UIKit.AMBER2, "mono", 700))
			rr.tooltip_text = "Unità nuove a ogni tuo turno: circa metà dei tuoi territori (minimo 4) più il bonus dei continenti completi"
			rr.mouse_filter = Control.MOUSE_FILTER_PASS
			c.add_child(rr)
			var tt: int = main.truce_turns()
			if tt > 0:
				var tq := PanelContainer.new()
				tq.add_theme_stylebox_override("panel", UIKit.box(Color(0.3, 0.6, 0.4, 0.10), Color(0.5, 0.85, 0.6, 0.35), 1, 3, Vector4(8, 4, 8, 4)))
				tq.tooltip_text = "Fino ad allora si possono attaccare solo i territori neutrali"
				tq.mouse_filter = Control.MOUSE_FILTER_PASS
				var tqh := UIKit.hbox(7)
				tqh.add_child(UIKit.icon("truce", 15))
				tqh.add_child(UIKit.label("Tregua tra giocatori", 13, Color("#bfe8c8")))
				tqh.add_child(UIKit.spacer())
				tqh.add_child(UIKit.label("ancora %d turn%s" % [tt, "o" if tt == 1 else "i"], 13, Color("#dff8e4"), "mono", 700))
				tq.add_child(tqh)
				c.add_child(tq)
			return
		var P: Dictionary = game.players[hh]
		var r := UIKit.hbox(7)
		r.add_child(UIKit.icon("reinforce", 15))
		r.add_child(UIKit.label("Prossimo rinforzo", 13, UIKit.TEXT))
		r.add_child(UIKit.label("%d s" % int(ceil(float(main.pget(P, ["next_reinforce", "nextReinforce"], 0)))), 14, UIKit.AMBER2, "mono", 700))
		r.add_child(UIKit.spacer())
		r.add_child(UIKit.label("+%d unità" % int(main.gcall("reinforce_amount", [hh], 0)), 12, UIKit.DIM))
		c.add_child(r)
		if game.time < Data.ECON["truce"]:
			var tp := PanelContainer.new()
			tp.add_theme_stylebox_override("panel", UIKit.box(Color(0.3, 0.6, 0.4, 0.10), Color(0.5, 0.85, 0.6, 0.35), 1, 3, Vector4(8, 4, 8, 4)))
			tp.tooltip_text = "Fino ad allora si possono attaccare solo i territori neutrali"
			tp.mouse_filter = Control.MOUSE_FILTER_PASS
			var th := UIKit.hbox(7)
			th.add_child(UIKit.icon("truce", 15))
			th.add_child(UIKit.label("Tregua tra giocatori", 13, Color("#bfe8c8")))
			th.add_child(UIKit.spacer())
			th.add_child(UIKit.label(UIKit.fmt_time(Data.ECON["truce"] - game.time), 14, Color("#dff8e4"), "mono", 700))
			tp.add_child(th)
			c.add_child(tp)
	)
	# mercato
	var mk := ""
	if hh >= 0 and game.players[hh]["alive"]:
		var P: Dictionary = game.players[hh]
		for r in Data.MARKET["goods"]:
			mk += main.supply_block() + "%s%d%d%s%s" % [r, int(main.gcall("market_price", [hh, r, "sell"], 0)), int(main.gcall("market_price", [hh, r, "buy"], 0)), str(float(P["res"][r]) >= Data.MARKET["lot"]), str(float(P["res"]["money"]) >= float(main.gcall("market_price", [hh, r, "buy"], 0)))]
	_sec(lp["market"], mk, func(c: Control):
		if mk == "":
			return
		var P: Dictionary = game.players[hh]
		var mh := UIKit.label("Compra o vendi lotti da %d unità. Solo nella fase di rifornimento." % Data.MARKET["lot"], FS_SMALL, UIKit.DIM)
		mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(mh)
		for r in Data.MARKET["goods"]:
			var sp := int(main.gcall("market_price", [hh, r, "sell"], 0))
			var bp := int(main.gcall("market_price", [hh, r, "buy"], 0))
			var row := UIKit.hbox(5)
			row.add_child(UIKit.icon(r, 15))
			var nl := UIKit.label(Data.RES_NAMES[r], 13)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nl)
			var bs := UIKit.button("Vendi +$%d" % sp, "normal", "xs", main_act.bind("trade", {"r": r, "d": "sell"}), "Vendi %d %s" % [Data.MARKET["lot"], Data.RES_NAMES[r]])
			bs.custom_minimum_size.x = 92
			bs.disabled = float(P["res"][r]) < Data.MARKET["lot"] or not main.can_supply()
			if not main.can_supply():
				bs.tooltip_text = main.supply_block()
			row.add_child(bs)
			var bb := UIKit.button("Compra −$%d" % bp, "normal", "xs", main_act.bind("trade", {"r": r, "d": "buy"}), "Compra %d %s" % [Data.MARKET["lot"], Data.RES_NAMES[r]])
			bb.custom_minimum_size.x = 98
			bb.disabled = float(P["res"]["money"]) < bp or not main.can_supply()
			if not main.can_supply():
				bb.tooltip_text = main.supply_block()
			row.add_child(bb)
			c.add_child(row)
	)
	# continenti
	var ck := ""
	for k in Data.CONT_KEYS:
		var mine := 0
		for i in Data.CONT_TERR[k]:
			if int(game.terr[i]["owner"]) == hh:
				mine += 1
		ck += "%s%d%d;" % [k, int(main.gcall("continent_owner", [k], -1)), mine]
	_sec(lp["conts"], ck, func(c: Control):
		var ch := UIKit.label("Chi controlla tutto un continente riceve rinforzi extra a ogni turno e un vantaggio speciale.", FS_SMALL, UIKit.DIM)
		ch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(ch)
		for k in Data.CONT_KEYS:
			var C: Dictionary = Data.CONTINENTS[k]
			var o := int(main.gcall("continent_owner", [k], -1))
			var mine := 0
			for i in Data.CONT_TERR[k]:
				if int(game.terr[i]["owner"]) == hh:
					mine += 1
			var row := UIKit.hbox(6)
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			row.tooltip_text = C["name"] + ": +" + str(C["bonus"]) + " rinforzi — " + C["perkText"]
			if o >= 0:
				row.add_child(UIKit.swatch(game.players[o]["color"], 11))
			else:
				var e := Panel.new()
				e.custom_minimum_size = Vector2(11, 11)
				e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				e.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0), UIKit.LINE2, 1, 2, Vector4.ZERO))
				e.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(e)
			var nl := UIKit.label(C["name"], 13, UIKit.WHITE if o >= 0 else UIKit.TEXT, "sans", 600 if o >= 0 else 400)
			nl.custom_minimum_size.x = 92
			row.add_child(nl)
			var cc := UIKit.label(("%d/%d" % [mine, Data.CONT_TERR[k].size()]) if hh >= 0 else str(Data.CONT_TERR[k].size()), 12, UIKit.DIM, "mono")
			cc.custom_minimum_size.x = 30
			row.add_child(cc)
			var cb := UIKit.label("+%d" % C["bonus"], 12, UIKit.AMBER2, "mono", 700)
			cb.custom_minimum_size.x = 22
			row.add_child(cb)
			var pk := UIKit.label(C["perkText"], 11, UIKit.DIM)
			pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pk.clip_text = true
			pk.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			pk.custom_minimum_size.x = 40
			row.add_child(pk)
			c.add_child(row)
	)
	# obiettivo segreto
	var ok_ := ""
	if hh >= 0 and game.players[hh]["objective"] != null and not bool(game.players[hh]["objective"].get("scenario", false)):
		ok_ = String(game.players[hh]["objective"].get("text", ""))
	var conq := ""
	if ok_ == "" and main.current_scenario() == null:
		var share := float(game.victory_share) if "victory_share" in game else float(Data.ECON.get("victoryShare", 0.7))
		var need := int(ceil(share * game.terr.size()))
		conq = "%d|%d|%d" % [need, n_terr.get(hh, 0) if hh >= 0 else -1, int(round(share * 100))]
	_sec(lp["obj"], ok_ + conq, func(c: Control):
		if ok_ == "" and conq != "":
			var a := conq.split("|")
			c.add_child(UIKit.header("Conquista mondiale"))
			var l := UIKit.label("Controlla il %s%% del mondo: %s territori su %d." % [a[2], a[0], game.terr.size()], FS_BODY, Color("#f3e6bd"), "sans", 600)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(l)
			if int(a[1]) >= 0:
				c.add_child(UIKit.label("Ne controlli %s." % a[1], FS_SMALL, UIKit.TEXT))
				c.add_child(UIKit.progress(100.0 * float(a[1]) / maxf(1.0, float(a[0])), UIKit.AMBER, 6))
			return
		if ok_ == "":
			return
		c.add_child(UIKit.header("Obiettivo segreto"))
		var p := PanelContainer.new()
		var sb := UIKit.box(Color(0.95, 0.69, 0.24, 0.07), Color(0, 0, 0, 0), 0, 0, Vector4(9, 5, 8, 5))
		sb.border_width_left = 3
		sb.border_color = UIKit.AMBER
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIKit.label(ok_, 13, Color("#f3e6bd"), "sans", 600)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_child(l)
		c.add_child(p)
	)

## Pannello dell'operazione (scenari, FASE 4): nome, obiettivo, eventuale avanzamento e tempo rimasto.
func _refresh_scenario() -> void:
	var S = main.current_scenario()
	var st: Dictionary = main.scenario_status() if S != null else {}
	var left := float(st["time_left"]) if st.has("time_left") else -1.0
	var key := "" if S == null else "%s|%s|%s|%d|%d" % [S.get("id", ""), str(st.get("text", "")), str(st.get("progress", "")), int(ceil(left)), int(ceil(float(st.get("hold_left", -1.0))))]
	_sec(lp["scn"], key, func(c: Control):
		if S == null:
			return
		var p := PanelContainer.new()
		var sb := UIKit.box(Color(0.95, 0.69, 0.24, 0.08), Color(UIKit.AMBER, 0.35), 1, 3, Vector4(10, 6, 10, 7))
		sb.border_width_left = 3
		sb.border_color = UIKit.AMBER
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.tooltip_text = String(main.menu.sf(S, ["desc", "description"], ""))
		var v := UIKit.vbox(3)
		var hh := UIKit.hbox(6)
		hh.add_child(UIKit.icon("flag", 15, UIKit.AMBER2))
		var nl := UIKit.label(String(S.get("name", "")).to_upper(), 13, UIKit.AMBER2, "mono", 700)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hh.add_child(nl)
		if main.turn_mode() and st.has("rounds_left") and int(st["rounds_left"]) >= 0:
			var rl := int(st["rounds_left"])
			hh.add_child(UIKit.icon("turn", 13))
			hh.add_child(UIKit.label("%d turn%s" % [rl, "o" if rl == 1 else "i"], 14, UIKit.RED if rl <= 3 else UIKit.WHITE, "mono", 700))
		elif left >= 0 and not main.turn_mode():
			hh.add_child(UIKit.icon("clock", 13))
			hh.add_child(UIKit.label(UIKit.fmt_time(left), 14, UIKit.RED if left < 60 else UIKit.WHITE, "mono", 700))
		v.add_child(hh)
		# obiettivo (quello del giocatore, se il nucleo lo distingue: assedianti / assediato)
		var obj := String(st.get("text", ""))
		if obj == "":
			obj = String(main.menu.scn_objective(S))
		if obj != "":
			var ol := UIKit.label(obj, 12, Color("#f3e6bd"), "sans", 600)
			ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ol.custom_minimum_size.x = 240
			v.add_child(ol)
		# avanzamento: testo (nucleo) e/o barra
		var pr = st.get("progress", "")
		if pr is String and pr != "":
			var sl := UIKit.label(pr, 11, UIKit.TEXT, "mono")
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size.x = 240
			v.add_child(sl)
		var bar := -1.0
		if pr is float or pr is int:
			bar = clampf(float(pr), 0.0, 1.0)
		elif int(st.get("hold_owner", -1)) >= 0 and "hold_secs" in game and float(game.hold_secs) > 0:
			bar = clampf(1.0 - float(st.get("hold_left", 0.0)) / float(game.hold_secs), 0.0, 1.0)
		elif int(st.get("hold_owner", -1)) >= 0 and "hold_rounds" in game and int(game.hold_rounds) > 0:
			bar = clampf(1.0 - float(st.get("hold_left", 0.0)) / float(game.hold_rounds), 0.0, 1.0)
		if bar >= 0:
			var ho := int(st.get("hold_owner", -1))
			var bc: Color = game.players[ho]["color"] if ho >= 0 else UIKit.AMBER
			v.add_child(UIKit.progress(bar * 100.0, bc, 6))
		p.add_child(v)
		c.add_child(p)
	)

func _power(cs, f) -> float:
	if cs != null:
		return float(cs.force_power(f))
	return float(Data.total_units(f))

## Stato diplomatico di una riga (per ricostruire il pannello solo quando cambia).
func _pact_key(i: int, hh: int) -> String:
	if not main.diplomacy_available():
		return ""
	var k := ""
	if hh >= 0:
		var pc = main.pact_between(hh, i)
		k = ("P" + main.pact_left_text(pc)) if pc != null else "-"
		k += str(main.human_alive()) + str(int(ceil(float(main.gcall("pact_cooldown", [hh, i], 0.0)))))
	else:
		for q in game.players:
			if int(q["idx"]) != i and main.pact_between(i, int(q["idx"])) != null:
				k += str(q["idx"])
	return k

## Patto / pulsante di proposta accanto a una potenza.
func _pact_widget(P: Dictionary, hh: int) -> Control:
	var i := int(P["idx"])
	if not main.diplomacy_available() or not P["alive"] or i == hh:
		return null
	if hh < 0:
		var partners := []
		for q in game.players:
			if int(q["idx"]) != i and main.pact_between(i, int(q["idx"])) != null:
				partners.append(String(q["fac"]["short"]))
		if partners.is_empty():
			return null
		var sp := UIKit.hbox(3)
		sp.mouse_filter = Control.MOUSE_FILTER_PASS
		sp.tooltip_text = "Patto di non aggressione con " + ", ".join(partners)
		sp.add_child(UIKit.icon("pact", 14))
		sp.add_child(UIKit.label(", ".join(partners), 11, Color("#bff0d0"), "mono", 700))
		return sp
	var pc = main.pact_between(hh, i)
	if pc != null:
		var left_t: String = main.pact_left_text(pc)
		var tp := PanelContainer.new()
		tp.add_theme_stylebox_override("panel", UIKit.box(Color(0.3, 0.7, 0.45, 0.16), Color(0.55, 0.9, 0.65, 0.5), 1, 3, Vector4(5, 1, 6, 1)))
		tp.mouse_filter = Control.MOUSE_FILTER_PASS
		tp.tooltip_text = "Patto di non aggressione con %s %s:\nnessuno dei due può attaccare l'altro né colpirlo con le carte." % [P["fac"]["short"], main.until_text(float(pc["until"]))]
		var th := UIKit.hbox(4)
		th.add_child(UIKit.icon("pact", 13))
		th.add_child(UIKit.label("PATTO " + left_t, 11, Color("#dff8e4"), "mono", 700))
		tp.add_child(th)
		return tp
	if not main.human_alive():
		return null
	var cd := float(main.gcall("pact_cooldown", [hh, i], 0.0))
	if cd > 0:
		var cl := UIKit.hbox(3)
		cl.mouse_filter = Control.MOUSE_FILTER_PASS
		cl.tooltip_text = "Diplomazia con %s: nuova proposta possibile tra %s" % [P["fac"]["short"], _dur(int(ceil(cd)), cd)]
		var ic := UIKit.icon("pact", 12)
		ic.modulate.a = 0.4
		cl.add_child(ic)
		cl.add_child(UIKit.label(("%dT" % int(ceil(cd))) if main.turn_mode() else UIKit.fmt_time(cd), 11, UIKit.DIM, "mono"))
		return cl
	var b := UIKit.button("", "normal", "xs", main_act.bind("pact", {"p": i}), "Proponi a %s un patto di non aggressione%s.\nL'IA accetta se non sei in testa e ha minacce più gravi altrove." % [P["fac"]["short"], " per alcuni turni" if main.turn_mode() else " di 5 minuti"])
	b.custom_minimum_size = Vector2(74, 20)
	var bh := UIKit.hbox(4)
	bh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_child(UIKit.icon("pact", 12))
	bh.add_child(UIKit.label("Patto?", 11, UIKit.TEXT, "sans", 600))
	b.add_child(bh)
	return b

func _player_row(P: Dictionary, hh: int, nt: int, pw: float) -> Control:
	var p := PanelContainer.new()
	var me: bool = int(P["idx"]) == hh
	var sb := UIKit.box(Color(0.95, 0.69, 0.24, 0.08) if me else Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0, 2, Vector4(8, 4, 8, 4))
	sb.border_width_left = 3
	sb.border_color = P["color"]
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = P["name"] + " — " + P["fac"]["doctrine"]
	if not P["alive"]:
		p.modulate.a = 0.45
	var v := UIKit.vbox(1)
	var l := UIKit.hbox(5)
	l.add_child(UIKit.label(P["fac"]["short"], 14, P["color"].lightened(0.25), "mono", 700))
	l.add_child(UIKit.tag("TU") if me else UIKit.tag("IA", Color(0.59, 0.75, 0.63, 0.25), UIKit.TEXT))
	l.add_child(UIKit.spacer())
	if not P["alive"]:
		l.add_child(UIKit.tag("ELIMINATO", Color("#5a2020"), Color("#ffb0a0")))
	else:
		for it in [["terr", str(nt), "Territori"], ["power", str(int(round(pw))), "Potenza stimata" + (" (nebbia: solo forze visibili e stime)" if main.fog_on() and not me else "")], ["card", str(P["cards"].size()), "Carte comando"]]:
			var s := UIKit.hbox(3)
			s.tooltip_text = it[2]
			s.mouse_filter = Control.MOUSE_FILTER_PASS
			s.add_child(UIKit.icon(it[0], 13))
			var vl := UIKit.label(it[1], 13, UIKit.WHITE, "mono", 600)
			vl.custom_minimum_size.x = 26 if it[0] != "card" else 12
			s.add_child(vl)
			l.add_child(s)
	v.add_child(l)
	if P["alive"]:
		var l2 := UIKit.hbox(4)
		var ql := UIKit.label("QG: %s · Tech %d" % [Data.TERRITORIES[P["hq"]]["name"] if int(P["hq"]) >= 0 else "—", int(P["tech"])], 11, UIKit.DIM)
		ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ql.clip_text = true
		ql.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l2.add_child(ql)
		var pw_ := _pact_widget(P, hh)
		if pw_ != null:
			l2.add_child(pw_)
		v.add_child(l2)
	p.add_child(v)
	return p

# ------------------------------------------------------------------ pannello territorio
func _refresh_right() -> void:
	var t: int = main.sel
	if t < 0:
		return
	var hh: int = main.h()
	var T: Dictionary = Data.TERRITORIES[t]
	var st: Dictionary = game.terr[t]
	var o := int(st["owner"])
	var O = game.players[o] if o >= 0 else null
	var own: bool = main.sel_own()
	var is_hq: bool = O != null and int(O["hq"]) == t
	var TR: Dictionary = Data.TERRAINS[T["ter"]]
	var ocol: Color = O["color"] if O != null else Color(Data.NEUTRAL_COLOR)

	var vis: bool = main.is_vis(t)
	var vet: int = main.vet_of(t) if vis else 0
	var pact = main.pact_between(hh, o) if (o >= 0 and hh >= 0 and o != hh) else null
	var hk := "%d|%d|%s|%s|%d|%s|%d|%s|%s" % [t, o, str(is_hq), str(st.get("supplied", true)), int(ceil(float(st.get("sabotage", 0)))), str(own), vet, str(vis), str(pact)]
	_sec(rp["head"], hk, func(c: Control):
		var p := PanelContainer.new()
		var sb := UIKit.box(Color(ocol, 0.10), Color(0, 0, 0, 0), 0, 3, Vector4(10, 6, 6, 7))
		sb.border_width_left = 4
		sb.border_color = ocol
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UIKit.vbox(3)
		var r1 := UIKit.hbox(6)
		if is_hq:
			r1.add_child(UIKit.icon("hq", 20))
		var nm := UIKit.label(T["name"], 20, UIKit.WHITE, "sans", 700)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r1.add_child(nm)
		if vet > 0:
			r1.add_child(_stars_box(vet, 15))
		var xb := UIKit.button("✕", "ghost", "xs", main_act.bind("close-panel", {}), "Chiudi (Esc)")
		xb.custom_minimum_size = Vector2(26, 24)
		r1.add_child(xb)
		v.add_child(r1)
		var r2 := UIKit.hbox(4)
		r2.add_child(UIKit.label(Data.CONTINENTS[T["c"]]["name"] + " · " + TR["name"], 13, UIKit.TEXT))
		r2.add_child(UIKit.label("(difesa ×%.2f)" % float(TR["def"]), 12, UIKit.DIM))
		v.add_child(r2)
		var r3 := UIKit.hbox(6)
		r3.add_child(UIKit.swatch(ocol, 12))
		r3.add_child(UIKit.label(O["name"] if O != null else "Neutrale", 13, UIKit.WHITE, "sans", 600))
		if o == hh and hh >= 0:
			r3.add_child(UIKit.tag("TU"))
		v.add_child(r3)
		var r4 := HFlowContainer.new()
		r4.add_theme_constant_override("h_separation", 12)
		r4.add_theme_constant_override("v_separation", 2)
		r4.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r4.add_child(_chip(T["spec"], "%s ×%.1f" % [Data.RES_NAMES[T["spec"]], float(T["amt"])], UIKit.TEXT))
		if T["coastal"]:
			r4.add_child(_chip("anchor", "Costiero", UIKit.BLUE))
		if o >= 0 and vis:
			if st.get("supplied", true):
				r4.add_child(_chip("supply", "Rifornito", UIKit.GREEN))
			else:
				r4.add_child(_chip("nosupply", "Senza rifornimenti", UIKit.ORANGE))
		if float(st.get("sabotage", 0)) > 0:
			r4.add_child(_chip("sabotage", "Sabotato " + _dur(int(ceil(float(st["sabotage"]))), float(st["sabotage"])), UIKit.RED))
		if main.turn_mode() and int(st.get("regroup", 0)) > 0 and o == hh:
			r4.add_child(_chip("clock", "Riorganizzazione %s" % _dur(int(st["regroup"]), 0), UIKit.ORANGE))
		if not vis:
			r4.add_child(_chip("fog", "Nella nebbia", Color("#b8c6d0")))
		if pact != null:
			r4.add_child(_chip("pact", "Patto " + main.until_text(float(pact["until"])), Color("#bff0d0")))
		v.add_child(r4)
		p.add_child(v)
		c.add_child(p)
	)
	# forze
	var f = st["forces"] if hh < 0 else main.gcall("visible_forces", [hh, t], st["forces"])
	var fog_t: String = "" if vis else main.fog_text(t)
	_sec(rp["forces"], str(t) + str(f) + fog_t + str(vet), func(c: Control):
		var note := ""
		if f != null and vis:
			note = "%d unità" % Data.total_units(f)
			if vet > 0:
				note += " · veterani +%d%%" % (6 * vet)
		c.add_child(UIKit.header("Forze", note))
		if not vis:
			c.add_child(_fog_box(t))
			return
		if f == null:
			c.add_child(UIKit.label("Forze nascoste (guerriglia urbana)", 13, UIKit.DIM))
			return
		var g := GridContainer.new()
		g.columns = 7
		g.add_theme_constant_override("h_separation", 4)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in Data.UNIT_KEYS:
			var n := int(f.get(k, 0))
			var cell := PanelContainer.new()
			cell.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.28) if n else Color(0, 0, 0, 0.12), UIKit.LINE if n else Color(UIKit.LINE, 0.08), 1, 3, Vector4(2, 3, 2, 2)))
			cell.custom_minimum_size.x = 44
			cell.tooltip_text = Data.UNITS[k]["name"]
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
			var cv := UIKit.vbox(0)
			cv.alignment = BoxContainer.ALIGNMENT_CENTER
			var ic := UIKit.icon(k, 18)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			if not n:
				ic.modulate.a = 0.3
			cv.add_child(ic)
			var nl := UIKit.label(str(n), 16, UIKit.WHITE if n else Color("#4d5953"), "mono", 700)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(nl)
			var sl := UIKit.label(Data.UNITS[k]["short"], 9, UIKit.DIM, "mono")
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(sl)
			cell.add_child(cv)
			g.add_child(cell)
		c.add_child(g)
	)
	# edifici
	var slots := Data.HQ_SLOTS if is_hq else Data.SLOTS
	var bld = st["building"]
	var bpc := int(100.0 * float(bld["t"]) / maxf(0.001, float(bld["total"]))) if bld != null else -1
	var bk := "%d|%s|%s|%d|%s|%s" % [t, str(st["buildings"]), str(bld["key"]) if bld != null else "", bpc, str(is_hq), str(vis)]
	_sec(rp["blist"], bk, func(c: Control):
		if not vis:
			c.add_child(UIKit.header("Edifici", "%d slot" % slots))
			var fh := UIKit.hbox(6)
			if is_hq:
				fh.add_child(_bchip("hq", "Quartier generale", "Il QG vale come caserma e fabbrica", Color(1, 0.85, 0.3, 0.6)))
			fh.add_child(UIKit.label("Altri edifici sconosciuti (nebbia)", 13, UIKit.DIM))
			c.add_child(fh)
			return
		c.add_child(UIKit.header("Edifici", "%d/%d slot" % [st["buildings"].size() + (1 if bld != null else 0), slots]))
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 4)
		fl.add_theme_constant_override("v_separation", 4)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_hq:
			fl.add_child(_bchip("hq", "Quartier generale", "Il QG vale come caserma e fabbrica", Color(1, 0.85, 0.3, 0.6)))
		for k in st["buildings"]:
			fl.add_child(_bchip(k, Data.BUILDINGS[k]["name"], Data.BUILDINGS[k]["desc"], UIKit.LINE2))
		if bld != null:
			var chip := _bchip(bld["key"], "%s %d%%" % [Data.BUILDINGS[bld["key"]]["name"], bpc], "In costruzione", UIKit.AMBER)
			fl.add_child(chip)
		if st["buildings"].is_empty() and bld == null and not is_hq:
			fl.add_child(UIKit.label("Nessuno", 13, UIKit.DIM))
		c.add_child(fl)
		if bld != null:
			c.add_child(UIKit.progress(bpc, UIKit.AMBER, 4))
	)
	var bbk := ""
	if own:
		bbk = str(t)
		for k in Data.BUILDING_KEYS:
			var cb = main.gcall("can_build", [hh, t, k], {"ok": false, "reason": ""})
			bbk += "%s%s%s" % [k, str(cb["ok"]), cb.get("reason", "")]
		bbk += str(st["buildings"]) + (str(bld["key"]) if bld != null else "") + main.supply_block()
	_sec(rp["bbtns"], bbk, func(c: Control):
		if bbk == "":
			return
		var bl := UIKit.vbox(4)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := 0
		var hint := UIKit.label("Gli edifici valgono solo in questo territorio. Pronti in 1–3 turni.", 13, Color("#d2dcd3"))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.add_child(hint)
		for k in Data.BUILDING_KEYS:
			if st["buildings"].has(k) or (bld != null and bld["key"] == k):
				continue
			if Data.BUILDINGS[k].get("coastal", false) and not T["coastal"]:
				continue
			if is_hq and (k == "caserma" or k == "fabbrica"):
				continue   # il QG vale già come caserma e fabbrica
			var cb = main.gcall("can_build", [hh, t, k], {"ok": false, "reason": ""})
			var B: Dictionary = Data.BUILDINGS[k]
			var bok: bool = cb["ok"] and main.can_supply()
			var why: String = String(cb.get("reason", "")) if not cb["ok"] else main.supply_block()
			var role := String(Data.BUILDING_ROLE.get(k, B["desc"])) if "BUILDING_ROLE" in Data else String(B["desc"])
			var tipt: String = "%s: %s — %s%s" % [B["name"], role, _dur(_bld_turns(k), float(B["time"])), "" if bok else " — " + why]
			bl.add_child(_build_row(k, B, role, bok, why, tipt))
			n += 1
		if n:
			c.add_child(bl)
	)
	# reclutamento
	var rk := ""
	if own:
		rk = str(t)
		for k in Data.UNIT_KEYS:
			var cr = main.gcall("can_recruit", [hh, t, k], {"ok": false, "reason": ""})
			rk += "%s%s%s%s%s" % [k, str(cr["ok"]), cr.get("reason", ""), str(main.gcall("cost_for", [hh, k], {})), str(main.gcall("unit_available", [hh, k], false))]
		var P: Dictionary = game.players[hh]
		if P["fac"]["mods"].get("mercs", false):
			rk += "M" + str(main.gcall("can_afford", [hh, Data.MERC_OFFER["cost"]], false) and float(st.get("sabotage", 0)) <= 0)
		rk += main.supply_block()
	_sec(rp["recruit"], rk, func(c: Control):
		if rk == "":
			return
		c.add_child(UIKit.header("Reclutamento", "" if main.can_supply() else main.supply_block().to_lower()))
		var info := UIKit.rich("La [b]tecnologia[/b] vale in tutti i tuoi territori. Gli [b]edifici[/b] valgono solo qui. Le unità [b]nascono in questo territorio[/b].", 13, Color("#d2dcd3"))
		info.tooltip_text = "I rinforzi gratuiti di ogni turno sono fanteria (ottima per difendere). Per attaccare servono carri e artiglieria: si reclutano dove hai una Fabbrica (il QG vale come caserma e fabbrica). Un esercito misto batte un esercito numeroso di un solo tipo."
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		var ip := PanelContainer.new()
		ip.add_theme_stylebox_override("panel", UIKit.box(Color(0.35, 0.6, 0.8, 0.08), Color(0.55, 0.8, 1.0, 0.35), 1, 3, Vector4(8, 4, 8, 5)))
		ip.mouse_filter = Control.MOUSE_FILTER_PASS
		ip.tooltip_text = info.tooltip_text
		ip.add_child(info)
		c.add_child(ip)
		for k in Data.UNIT_KEYS:
			c.add_child(_recruit_row(hh, t, k))
		var P: Dictionary = game.players[hh]
		if P["fac"]["mods"].get("mercs", false):
			var ok: bool = main.gcall("can_afford", [hh, Data.MERC_OFFER["cost"]], false) and float(st.get("sabotage", 0)) <= 0 and main.can_supply()
			var b := _rich_button("inf", "Assolda mercenari: +%d FAN" % Data.MERC_OFFER["count"], Data.MERC_OFFER["cost"], ok, "Fanteria istantanea pagando denaro" + ("" if main.can_supply() else " — " + main.supply_block()), main_act.bind("mercs", {}), Vector2(RIGHT_W - 26, 30), true)
			c.add_child(b)
	)
	# coda
	var q: Array = st["queue"]
	var qk := ""
	if (own or (hh < 0 and q.size())) and q.size():
		var q0: Dictionary = q[0]
		qk = "%d|%d|%s|%d" % [t, q.size(), q0["unit"], int(100.0 * float(q0["t"]) / maxf(0.001, float(q0["total"])))]
	_sec(rp["queue"], qk, func(c: Control):
		if qk == "":
			return
		var q0: Dictionary = q[0]
		var pc := int(100.0 * float(q0["t"]) / maxf(0.001, float(q0["total"])))
		c.add_child(UIKit.header("Coda di reclutamento", ("%d in coda" % q.size()) + ((" · pronto tra " + _dur(maxi(1, int(q0["total"]) - int(q0["t"])), 0)) if main.turn_mode() else "")))
		var r := UIKit.hbox(8)
		r.add_child(UIKit.icon(q0["unit"], 18))
		r.add_child(UIKit.label(Data.UNITS[q0["unit"]]["short"], 12, UIKit.AMBER2, "mono", 700))
		var pb := UIKit.progress(pc, Color(0.36, 0.72, 0.42), 9)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(pb)
		r.add_child(UIKit.label("%d%%" % pc, 12, UIKit.TEXT, "mono"))
		c.add_child(r)
		var counts := {}
		var order := []
		for it in q:
			if not counts.has(it["unit"]):
				order.append(it["unit"])
				counts[it["unit"]] = 0
			counts[it["unit"]] += 1
		var parts := []
		for u in order:
			parts.append("%s×%d" % [Data.UNITS[u]["short"], counts[u]])
		c.add_child(UIKit.label(" · ".join(parts), 12, UIKit.DIM, "mono"))
	)
	# ordini del turno e fortificazioni (FASE 6)
	if main.turn_mode():
		_refresh_turn_orders(t, own, vis)
		_refresh_rtabs(t, own)
	# invio e rinforzi
	var sk := "%d|%s|%s|%d|%d" % [t, str(own), str(main.quota), main.send_forces(t).values().reduce(func(a, b): return a + b, 0) if own else 0, Data.total_units(game.players[hh]["pool"]) if hh >= 0 else 0]
	if not own:
		sk += str(o != hh and main.human_alive()) + str(pact != null)
	if main.turn_mode():
		sk = "T|%d|%s|%s|%d" % [t, str(own), main.supply_block(), Data.total_units(game.players[hh]["pool"]) if hh >= 0 else 0]
		if not own:
			sk += str(o != hh and main.human_alive()) + str(pact != null)
	_sec(rp["send"], sk, func(c: Control):
		if main.turn_mode():
			_turn_send(c, t, own, o, O, pact)
			return
		if own:
			var n := Data.total_units(st["forces"])
			c.add_child(UIKit.header("Invio divisione", "quota"))
			var seg := UIKit.hbox(2)
			for qv in [0.25, 0.5, 0.75, 1.0]:
				var b := UIKit.button("%d%%" % int(qv * 100), "normal", "sm", main_act.bind("quota", {"v": qv}))
				b.toggle_mode = true
				b.set_pressed_no_signal(absf(main.quota - qv) < 0.01)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				seg.add_child(b)
			c.add_child(seg)
			var hint := UIKit.label(("Clic destro su un bersaglio o trascina dal territorio · %d unità" % Data.total_units(main.send_forces(t))) if n else "Nessuna unità da inviare", 12, UIKit.DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(hint)
			var pool := Data.total_units(game.players[hh]["pool"])
			if pool > 0:
				var b := UIKit.button("Schiera qui i rinforzi (%d)" % pool, "primary", "md", main_act.bind("deploy-here", {}))
				c.add_child(b)
		elif o != hh and main.human_alive() and pact != null:
			var hint := UIKit.label("Patto di non aggressione con %s %s: niente attacchi né carte OPS su questo territorio." % [O["fac"]["short"], main.until_text(float(pact["until"]))], 12, Color("#bff0d0"))
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(hint)
		elif o != hh and main.human_alive():
			var hint := UIKit.label("Seleziona un tuo territorio adiacente e fai clic destro qui per attaccare.", 12, UIKit.DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(hint)
	)
	if main.turn_mode():
		_apply_rtab_visibility(own)

## Rifornimento sul proprio territorio: pulsante «Schiera qui» e schede Recluta / Edifici / Fortifica.
func _refresh_rtabs(t: int, own: bool) -> void:
	var hh: int = main.h()
	var pool := Data.total_units(game.players[hh]["pool"]) if hh >= 0 else 0
	var sup: bool = own and main.can_supply() and main.my_turn()
	var dk := "%d|%s|%d" % [t, str(sup), pool]
	_sec(rp["deploy"], dk, func(c: Control):
		if not sup or pool <= 0:
			return
		var b := UIKit.button("Schiera qui i %d rinforzi" % pool, "primary", "md", main_act.bind("deploy-here", {}), "Mette qui tutti i rinforzi in attesa: %s" % UIKit.forces_text(game.players[hh]["pool"]))
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 15)
		c.add_child(b)
	)
	var tk := "%d|%s|%s" % [t, str(sup), rtab]
	_sec(rp["tabs"], tk, func(c: Control):
		if not sup:
			return
		var seg := UIKit.hbox(3)
		for it in [["recruit", "inf", "Recluta", "Recluta nuove unità (pronte in 1–3 turni)"], ["build", "fabbrica", "Edifici", "Costruisci edifici: caserma, fabbrica, aeroporto, porto, impianto, fortificazioni"], ["fort", "trench", "Fortifica", "Trincee, campi minati e bunker: rafforzano subito la difesa di questo territorio"]]:
			var b := UIKit.button("", "normal", "sm", func(): rtab = it[0]; _refresh_right(); _fit_panels(), it[3])
			b.toggle_mode = true
			b.set_pressed_no_signal(rtab == it[0])
			b.custom_minimum_size = Vector2(0, 34)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var bh := UIKit.hbox(5)
			bh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bh.alignment = BoxContainer.ALIGNMENT_CENTER
			bh.add_child(UIKit.icon(it[1], 16))
			bh.add_child(UIKit.label(it[2], 13, UIKit.WHITE if rtab == it[0] else UIKit.TEXT, "sans", 600))
			b.add_child(bh)
			b.set_meta("tab", it[0])
			seg.add_child(b)
		c.add_child(seg)
	)

## Mostra solo le sezioni utili adesso: riassunto sempre; schede solo nel rifornimento sui propri territori.
func _apply_rtab_visibility(own: bool) -> void:
	var sup: bool = own and main.can_supply() and main.my_turn()
	var ph: String = main.phase_key()
	var show := {"head": true, "forces": true, "deploy": sup, "orders": own and main.my_turn() and ph != "supply",
		"tabs": sup, "send": not own}
	if sup:
		show["recruit"] = rtab == "recruit"
		show["queue"] = rtab == "recruit"
		show["blist"] = rtab == "build"
		show["bbtns"] = rtab == "build"
		show["fort"] = rtab == "fort"
	else:
		# riassunto: coda e fortificazioni come informazione, edifici in breve
		show["recruit"] = false
		show["bbtns"] = false
		show["queue"] = true
		show["blist"] = true
		show["fort"] = true
	for k in rp:
		(rp[k] as Control).visible = bool(show.get(k, true))

## Pannello territorio a turni: ordini (attacco/spostamento) in alto e fortificazioni.
func _refresh_turn_orders(t: int, own: bool, vis: bool) -> void:
	var hh: int = main.h()
	var ph: String = main.phase_key()
	var ok_k := "%d|%s|%s|%s|%s|%s|%d" % [t, str(own), ph, str(main.my_turn()), str(main.attack_used()), str(main.move_used()), main.targets.size()]
	_sec(rp["orders"], ok_k, func(c: Control):
		if not own or not main.my_turn() or ph == "supply":
			return
		var n := Data.total_units(game.terr[t]["forces"])
		var p := PanelContainer.new()
		var atk_ph: bool = ph == "attack" or ph == "supply"
		var col: Color = Color("#ff8a6a") if atk_ph else Color("#8ad6ff")
		var sb := UIKit.box(Color(col, 0.07), Color(col, 0.35), 1, 3, Vector4(10, 6, 10, 6))
		sb.border_width_left = 3
		sb.border_color = col
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(8)
		h.add_child(UIKit.icon("attack" if atk_ph else "move", 18))
		var txt := ""
		if n <= 1:
			txt = "Presidio minimo: serve almeno 2 unità per attaccare o spostare."
		elif ph == "move" and not main.move_used() and int(game.terr[t].get("regroup", 0)) > 0:
			txt = "Truppe in riorganizzazione dopo la conquista: non possono ripartire in questo turno."
		elif ph == "move":
			txt = "Spostamento già eseguito in questo turno." if main.move_used() else ("Spostamento: clic su uno dei %d tuoi territori evidenziati." % main.targets.size() if main.targets.size() else "Nessun tuo territorio collegato raggiungibile.")
		elif main.move_used():
			txt = "Dopo lo spostamento non si attacca più in questo turno."
		elif main.attack_used():
			txt = "Attacco del turno già eseguito. Passa allo spostamento."
		elif main.targets.size():
			txt = "Attacco: clic su uno dei %d bersagli evidenziati (fino a %d unità)." % [main.targets.size(), Data.total_units(main.movable_forces(t))]
		elif main.truce_turns() > 0:
			txt = "Tregua: nessun neutrale confinante da attaccare da qui."
		else:
			txt = "Nessun bersaglio attaccabile da questo territorio."
		var l := UIKit.label(txt, 12, UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		p.add_child(h)
		c.add_child(p)
	)
	var fk := ""
	if vis and int(game.terr[t]["owner"]) >= 0:
		fk = "%d|%s|%s|%s" % [t, str(own), str(main.fort_levels(t)), main.supply_block()]
		if own:
			for k in main.FORT_KINDS:
				fk += str(main.can_fortify(t, k)) + str(main.fort_cost(t, k))
	_sec(rp["fort"], fk, func(c: Control):
		if fk == "":
			return
		var lv: Dictionary = main.fort_levels(t)
		var any := false
		for k in lv:
			any = any or int(lv[k]) > 0
		if not own or not (main.can_supply() and main.my_turn()):
			if any:
				c.add_child(UIKit.header("Fortificazioni"))
				c.add_child(main.modal.fort_row(t, true, 12))
			return
		var fh := UIKit.label("Ogni livello rafforza subito la difesa del territorio (livelli 0–3).", FS_SMALL, UIKit.DIM)
		fh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(fh)
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 4)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in main.FORT_KINDS:
			var L := int(lv[k])
			var cf: Dictionary = main.can_fortify(t, k)
			var cost = main.fort_cost(t, k)
			var desc := String(Data.FORT[k]["desc"]) if "FORT" in Data and Data.FORT.has(k) else String(main.FORT_INFO[k]["desc"])
			var tipt := "%s (livello %d/3): %s%s" % [main.fort_name(k), L, desc, "" if cf.get("ok", false) else " — " + String(cf.get("reason", ""))]
			var b := UIKit.button("", "normal", "sm", main_act.bind("fortify", {"k": k}), tipt)
			b.custom_minimum_size = Vector2(108, 52)
			b.disabled = not cf.get("ok", false)
			var m := MarginContainer.new()
			m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			m.add_theme_constant_override("margin_left", 6)
			m.add_theme_constant_override("margin_top", 3)
			m.add_theme_constant_override("margin_right", 4)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var v := UIKit.vbox(0)
			var hh2 := UIKit.hbox(4)
			hh2.add_child(UIKit.icon(k, 15))
			var nl := UIKit.label(main.fort_name(k), 12, UIKit.TEXT if cf.get("ok", false) else UIKit.DIM, "sans", 600)
			nl.clip_text = true
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hh2.add_child(nl)
			v.add_child(hh2)
			v.add_child(UIKit.label(_pips_txt(L), 12, UIKit.AMBER2 if L > 0 else UIKit.DIM, "mono", 700))
			if cost != null:
				var cr := UIKit.cost_row(cost, 1.0, 10, game.players[hh]["res"])
				cr.add_theme_constant_override("separation", 3)
				v.add_child(cr)
			else:
				v.add_child(UIKit.label("massimo", 10, UIKit.DIM, "mono"))
			m.add_child(v)
			b.add_child(m)
			g.add_child(b)
		c.add_child(g)
	)

static func _pips_txt(n: int) -> String:
	return "■".repeat(clampi(n, 0, 3)) + "□".repeat(3 - clampi(n, 0, 3)) + "  Lv %d" % n

## Sezione in fondo al pannello territorio durante i turni: rinforzi e suggerimenti.
func _turn_send(c: Control, t: int, own: bool, o: int, O, pact) -> void:
	var hh: int = main.h()
	if own:
		return   # «Schiera qui» è in cima al pannello (sezione deploy)
	elif o != hh and main.human_alive() and pact != null:
		var hint := UIKit.label("Patto di non aggressione con %s %s: niente attacchi né carte OPS su questo territorio." % [O["fac"]["short"], main.until_text(float(pact["until"]))], 12, Color("#bff0d0"))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(hint)
	elif o != hh and main.human_alive():
		var hint := UIKit.label("Per attaccarlo: nella fase di attacco seleziona un tuo territorio confinante con almeno 2 unità, poi clicca qui.", FS_SMALL, UIKit.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(hint)

## Riquadro "nella nebbia": stima delle forze o sconosciute.
func _fog_box(t: int) -> Control:
	var e: int = main.estimate(t)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0.55, 0.65, 0.72, 0.08), Color(0.6, 0.7, 0.78, 0.3), 1, 3, Vector4(10, 7, 10, 7)))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = "Territorio fuori dalla tua vista: lo vedi solo se confina con un tuo territorio."
	var h := UIKit.hbox(10)
	h.add_child(UIKit.icon("fog", 30))
	var v := UIKit.vbox(0)
	if e >= 0:
		var r := UIKit.hbox(6)
		r.add_child(UIKit.label("≈%d" % e, 26, UIKit.WHITE, "mono", 700))
		var u := UIKit.label("forze stimate", 13, UIKit.TEXT)
		u.size_flags_vertical = Control.SIZE_SHRINK_END
		r.add_child(u)
		v.add_child(r)
		v.add_child(UIKit.label("Ricognizione incerta: composizione ignota", 12, UIKit.DIM))
	else:
		v.add_child(UIKit.label("Forze sconosciute", 18, UIKit.WHITE, "sans", 700))
		v.add_child(UIKit.label("Nessuna informazione sul presidio", 12, UIKit.DIM))
	h.add_child(v)
	p.add_child(h)
	return p

## Stelle di veterania (1..3).
func _stars_box(n: int, sz: float = 13) -> Control:
	var h := UIKit.hbox(0)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.tooltip_text = "Veterani: %d stell%s (+%d%% in combattimento)" % [n, "a" if n == 1 else "e", 6 * n]
	for i in n:
		h.add_child(UIKit.icon("star", sz))
	return h

func _chip(ic: String, text: String, col: Color) -> Control:
	var h := UIKit.hbox(4)
	h.add_child(UIKit.icon(ic, 13))
	h.add_child(UIKit.label(text, 12, col))
	return h

func _bchip(ic: String, text: String, tipt: String, border: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.3), border, 1, 3, Vector4(6, 3, 8, 3)))
	p.tooltip_text = tipt
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(5)
	h.add_child(UIKit.icon(ic, 14))
	h.add_child(UIKit.label(text, 12, UIKit.AMBER2 if border == UIKit.AMBER else UIKit.TEXT))
	p.add_child(h)
	return p

## Pulsante con icona, titolo e riga di costo (edifici, mercenari).
func _rich_button(ic: String, title: String, cost, ok: bool, tipt: String, cb: Callable, sz: Vector2, one_line: bool = false) -> Button:
	var b := UIKit.button("", "normal", "sm", cb, tipt)
	b.custom_minimum_size = sz
	b.disabled = not ok
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 4)
	m.add_theme_constant_override("margin_top", 3)
	m.add_theme_constant_override("margin_bottom", 3)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var res = game.players[main.h()]["res"] if main.h() >= 0 else null
	if one_line:
		var h := UIKit.hbox(6)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(UIKit.icon(ic, 15))
		h.add_child(UIKit.label(title, 12, UIKit.TEXT if ok else UIKit.DIM, "sans", 600))
		h.add_child(UIKit.cost_row(cost, 1.0, 11, res))
		m.add_child(h)
	else:
		var v := UIKit.vbox(1)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var h := UIKit.hbox(4)
		h.add_child(UIKit.icon(ic, 14, Color(0, 0, 0, 0) if ok else Color(0.5, 0.5, 0.45)))
		var l := UIKit.label(title, 12, UIKit.TEXT if ok else UIKit.DIM, "sans", 600)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		v.add_child(h)
		var cr := UIKit.cost_row(cost, 1.0, 10, res)
		cr.add_theme_constant_override("separation", 3)
		v.add_child(cr)
		m.add_child(v)
	b.add_child(m)
	return b

## Riga di un edificio nella scheda Edifici: nome, costo, turni, a cosa serve e perché non si può costruire.
func _build_row(k: String, B: Dictionary, role: String, ok: bool, why: String, tipt: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.22), UIKit.LINE if ok else Color(UIKit.LINE, 0.4), 1, 3, Vector4(8, 4, 6, 5)))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = tipt
	var v := UIKit.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(UIKit.icon(k, 16, Color(0, 0, 0, 0) if ok else Color(0.5, 0.5, 0.45)))
	h.add_child(UIKit.label(B["name"], 13, UIKit.WHITE if ok else UIKit.TEXT, "sans", 600))
	h.add_child(UIKit.spacer())
	var res = game.players[main.h()]["res"] if main.h() >= 0 else null
	h.add_child(UIKit.cost_row(B["cost"], 1.0, 11, res))
	var b := UIKit.button("Costruisci", "normal", "xs", main_act.bind("build", {"k": k}), tipt)
	b.custom_minimum_size = Vector2(78, 22)
	b.disabled = not ok
	h.add_child(b)
	v.add_child(h)
	var rl := UIKit.label("%s · %s" % [role, _dur(_bld_turns(k), float(B["time"]))], 13, Color("#d2dcd3"))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.custom_minimum_size.x = RIGHT_W - 50
	v.add_child(rl)
	if not ok and why != "":
		var wl := UIKit.label(why, 13, Color("#ffb4a0"), "sans", 600)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.custom_minimum_size.x = RIGHT_W - 50
		v.add_child(wl)
	p.add_child(v)
	return p

func _recruit_row(hh: int, t: int, k: String) -> Control:
	var U: Dictionary = Data.UNITS[k]
	var cr = main.gcall("can_recruit", [hh, t, k], {"ok": false, "reason": ""})
	var cost = main.gcall("cost_for", [hh, k], U["cost"])
	var avail: bool = main.gcall("unit_available", [hh, k], false)
	var bname: String = Data.BUILDINGS[U["build"]]["name"] if Data.BUILDINGS.has(U["build"]) else String(U["build"])
	if cr["ok"] and not main.can_supply():
		cr = {"ok": false, "reason": main.supply_block()}
	var lock: bool = String(cr.get("lock", "")) != "" or not avail
	var why := String(cr.get("reason", ""))
	var role := String(Data.UNIT_ROLE.get(k, "")) if "UNIT_ROLE" in Data else ""
	var nt := _unit_turns(k)
	var tipt: String = "%s — %s
Pronta in %s · si recluta con: %s%s" % [U["name"], role, _dur(nt, float(U["time"])), bname + (" (o QG)" if U["build"] in ["caserma", "fabbrica"] else ""), "" if cr["ok"] else "
" + why]
	var box := UIKit.vbox(0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = tipt
	var row := UIKit.hbox(5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size.y = 24
	row.add_child(UIKit.icon(k, 18))
	var nl := UIKit.label(U["name"], 13, UIKit.WHITE if cr["ok"] else UIKit.TEXT, "sans", 600 if cr["ok"] else 400)
	nl.custom_minimum_size.x = 104
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(nl)
	var info: Control
	if not avail:
		var need := int(U["tech"])
		if k == "drone" and game.players[hh]["fac"]["mods"].has("droneTech"):
			need = int(game.players[hh]["fac"]["mods"]["droneTech"])
		info = UIKit.label("🔒 Tech %d" % need, 11, UIKit.DIM, "mono", 700)
	else:
		info = UIKit.cost_row(cost, 1.0, 11, game.players[hh]["res"])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 60
	row.add_child(info)
	for n in [1, 5]:
		var b := UIKit.button("+%d" % n, "normal", "xs", main_act.bind("recruit", {"u": k, "n": n}), tipt)
		b.custom_minimum_size = Vector2(36, 22)
		b.disabled = not cr["ok"]
		row.add_child(b)
	box.add_child(row)
	# riga 2: il ruolo se si può reclutare, altrimenti il motivo esatto (il ruolo resta nel tooltip)
	var l2: Label
	if cr["ok"] or why == "":
		l2 = UIKit.label(role + " · pronta in %d turn%s" % [nt, "o" if nt == 1 else "i"], 13, Color("#d2dcd3"))
	else:
		l2 = UIKit.label(("🔒 " if lock else "") + why, 13, Color("#ffd28a") if lock else Color("#ffb4a0"), "sans", 600)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size.x = RIGHT_W - 60
	l2.mouse_filter = Control.MOUSE_FILTER_PASS
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 23)
	rm.mouse_filter = Control.MOUSE_FILTER_PASS
	rm.add_child(l2)
	box.add_child(rm)
	if lock:
		row.modulate.a = 0.6
	box.add_child(UIKit.spacer(0, 3, false))
	return box

# ------------------------------------------------------------------ barra inferiore
func _refresh_bottom() -> void:
	var hh: int = main.h()
	if hh < 0:
		return
	var P: Dictionary = game.players[hh]
	if P["cards"].size() != main._card_count:
		main._card_count = P["cards"].size()
		main.sel_cards = []
	var selected := []
	for i in main.sel_cards:
		if i < P["cards"].size():
			selected.append(P["cards"][i])
	var valid: bool = main.sel_cards.size() == 3 and main.gcall("is_valid_set", [selected], false)
	var mode_op: String = main.mode["op"] if (main.mode != null and main.mode["type"] == "card") else ""
	var ck: String = main.supply_block() + "%s|%s|%s|%s|%d|%s" % [str(P["cards"]), str(main.sel_cards), str(valid), mode_op, int(main.gcall("set_value", [hh], 0)), str(main.gcall("find_set", [hh]) != null)]
	_sec(cards_v, ck, func(c: Control):
		c.add_child(UIKit.header("Carte comando", "%d/%d · prossimo tris: %d unità" % [P["cards"].size(), Data.HAND_MAX, int(main.gcall("set_value", [hh], 0))]))
		var help := UIKit.label("Seleziona 3 carte (tre uguali, tre diverse o con il jolly) e scegli l'operazione. Si giocano nel rifornimento.", FS_SMALL, UIKit.DIM)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(help)
		var row := UIKit.vbox(8)
		var hand := UIKit.hbox(3)
		hand.custom_minimum_size = Vector2(5 * 58 + 4 * 3, 86)
		if P["cards"].is_empty():
			var l := UIKit.label(("Conquista territori per ottenere carte (una per turno al massimo)." if main.turn_mode() else "Conquista territori per ottenere carte (una ogni %d s al massimo)." % Data.CARD_COOLDOWN), 13, UIKit.DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 290
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hand.add_child(l)
		for i in P["cards"].size():
			hand.add_child(_card(P["cards"][i]["type"], i, main.sel_cards.has(i)))
		row.add_child(hand)
		var ops := GridContainer.new()
		ops.columns = 2
		ops.add_theme_constant_override("h_separation", 4)
		ops.add_theme_constant_override("v_separation", 4)
		ops.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ops.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var why := "Seleziona tre carte" if main.sel_cards.size() != 3 else ("" if valid else "Tris non valido (tre uguali, tre diverse o con jolly)")
		for op in Data.OPS.keys():
			var b := UIKit.button(Data.OPS[op]["name"].replace("Attacco missilistico", "Missile"), "op", "xs", main_act.bind("op", {"op": op}), Data.OPS[op]["name"] + ": " + Data.OPS[op]["desc"] + ((" — " + why) if why != "" else ""))
			b.disabled = not valid or not main.can_supply()
			if valid and not main.can_supply():
				b.tooltip_text = main.supply_block()
			b.custom_minimum_size = Vector2(88, 26)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if mode_op == op:
				b.toggle_mode = true
				b.set_pressed_no_signal(true)
			ops.add_child(b)
		var ab := UIKit.button("Tris automatico", "normal", "xs", main_act.bind("autoset", {}), "Seleziona automaticamente un tris valido")
		ab.disabled = main.gcall("find_set", [hh]) == null
		ab.custom_minimum_size.y = 26
		var opsv := UIKit.vbox(4)
		opsv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opsv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		opsv.add_child(ab)
		opsv.add_child(ops)
		row.add_child(opsv)
		c.add_child(row)
	)
	var pool := Data.total_units(P["pool"])
	var deploying: bool = main.mode != null and main.mode["type"] == "deploy"
	var pk: String = main.supply_block() + "%d|%s|%s|%d|%s" % [pool, str(P["pool"]), str(deploying), int(ceil(float(main.pget(P, ["next_reinforce", "nextReinforce"], 0)))), str(P["alive"])]
	_sec(pool_v, pk, func(c: Control):
		c.add_child(UIKit.header("Rinforzi"))
		var nh := UIKit.hbox(8)
		nh.alignment = BoxContainer.ALIGNMENT_CENTER
		nh.add_child(UIKit.icon("reinforce", 18))
		nh.add_child(UIKit.label(str(pool), 30, UIKit.AMBER2 if pool else UIKit.DIM, "mono", 700))
		c.add_child(nh)
		var fl := UIKit.label(UIKit.forces_text(P["pool"]) if pool else "nessuno in attesa", 11, UIKit.DIM)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.clip_text = true
		c.add_child(fl)
		var b := UIKit.button("Schiera (%d)" % pool, "primary" if pool else "normal", "sm", main_act.bind("deploy", {}), "Schiera i rinforzi (N), poi clic su un tuo territorio")
		b.disabled = not (pool > 0 and P["alive"] and main.can_supply())
		if pool > 0 and not main.can_supply():
			b.tooltip_text = main.supply_block()
		b.toggle_mode = true
		b.set_pressed_no_signal(deploying)
		c.add_child(b)
		var nl := UIKit.label(("Nuovi a ogni tuo turno" if main.turn_mode() else "Prossimi tra %d s" % int(ceil(float(main.pget(P, ["next_reinforce", "nextReinforce"], 0))))), 11, UIKit.DIM)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(nl)
	)

func _card(type: String, i: int, on: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(58, 86)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = Data.CARD_TYPES.get(type, type)
	var col: Color = CARD_COL.get(type, UIKit.TEXT)
	var n := UIKit.box(Color(0.10, 0.15, 0.14), UIKit.LINE2, 1, 5, Vector4(2, 2, 2, 2))
	var hv := UIKit.box(Color(0.14, 0.20, 0.18), Color(0.8, 0.9, 0.78), 1, 5, Vector4(2, 2, 2, 2))
	var sel := UIKit.box(Color(0.24, 0.20, 0.08), UIKit.AMBER, 2, 5, Vector4(2, 2, 2, 2))
	sel.shadow_color = Color(UIKit.AMBER, 0.45)
	sel.shadow_size = 8
	b.add_theme_stylebox_override("normal", sel if on else n)
	b.add_theme_stylebox_override("hover", sel if on else hv)
	b.add_theme_stylebox_override("pressed", sel)
	b.position = Vector2(0, 0 if on else 7)
	b.size = Vector2(58, 79)
	b.pressed.connect(func(): Sfx.play("click"); main_act("card", {"i": i}))
	var v := UIKit.vbox(3)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UIKit.icon(CARD_ICON.get(type, "star"), 30, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UIKit.label(String(Data.CARD_TYPES.get(type, type)).to_upper(), 9, UIKit.DIM if not on else UIKit.AMBER2, "mono", 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	holder.add_child(b)
	return holder

# ------------------------------------------------------------------ registro
func _refresh_log() -> void:
	var hh: int = main.h()
	var ev: Array = game.events
	var last = ev[ev.size() - 1] if ev.size() else null
	var key := "%d|%s" % [ev.size(), str(last.get("time", 0)) + String(last.get("text", "")) if last != null else ""]
	if key == _log_key:
		return
	# toast per i nuovi eventi importanti del giocatore
	if _log_key != "" and last != null:
		var prev_n := int(_log_key.split("|")[0])
		var from := maxi(prev_n, ev.size() - 6)
		for i in range(from, ev.size()):
			var e: Dictionary = ev[i]
			if hh >= 0 and e.get("player") != null and int(e["player"]) == hh and (e.get("type") == "bad" or (e.get("type") == "good" and not _covered(String(e["text"])))) and not main.toasted_recently(e["text"]):
				main.toast(e["text"], e["type"])
	_log_key = key
	var lines := PackedStringArray()
	var n := 0
	var i := ev.size() - 1
	while i >= 0 and n < 60:
		var e: Dictionary = ev[i]
		i -= 1
		if hh >= 0 and e.get("player") != null and int(e["player"]) != hh:
			continue
		var col := "#dbe5d6"
		match String(e.get("type", "info")):
			"good": col = "#a8f0a8"
			"bad": col = "#ff9a8a"
			"battle": col = "#ffd08a"
			"headline": col = "#ffd57a"
		var txt := _fog_log_text(String(e.get("text", ""))).replace("[", "[lb]")
		var stamp := ("T%-3d" % int(e["round"])) if e.has("round") and main.turn_mode() else UIKit.fmt_time(float(e.get("time", 0)))
		lines.append("[color=#7d8c80][code]%s[/code][/color]  [color=%s]%s[/color]" % [stamp, col, txt])
		n += 1
	log_text.text = "\n".join(lines)
	log_text.scroll_to_line(0)

## A turni alcune notizie positive sono già mostrate altrove (riquadro ORDINI, badge delle carte): niente toast doppi.
func _covered(txt: String) -> bool:
	if not main.turn_mode():
		return false
	for p in ["Rinforzi disponibili", "Hai ottenuto una carta", "Conquistat", "Rinforzi schierati", "Costruzione avviata", "Ricerca avviata"]:
		if txt.begins_with(p):
			return true
	return false

var _terr_by_name := {}

## Nebbia: le battaglie lontane restano nel registro, ma senza il conteggio delle perdite.
func _fog_log_text(txt: String) -> String:
	if not main.fog_on() or not txt.begins_with("Battaglia per "):
		return txt
	var k := txt.find(" (")
	var cut := txt.find(". Perdite:")
	if k < 0 or cut < 0:
		return txt
	if _terr_by_name.is_empty():
		for T in Data.TERRITORIES:
			_terr_by_name[String(T["name"])] = int(T["idx"])
	var t := int(_terr_by_name.get(txt.substr(14, k - 14), -1))
	if t < 0 or main.is_vis(t):
		return txt
	return txt.substr(0, cut) + "."

# ------------------------------------------------------------------ tooltip del tabellone
func update_tip(force: bool = false) -> void:
	if game == null or main == null or main.battle != null or main.hover < 0 or main.modal_kind != "" or _mouse_on_gui():
		hide_tip()
		return
	var t: int = main.hover
	var hh: int = main.h()
	var T: Dictionary = Data.TERRITORIES[t]
	var st: Dictionary = game.terr[t]
	var o := int(st["owner"])
	var O = game.players[o] if o >= 0 else null
	var f = st["forces"] if hh < 0 else main.gcall("visible_forces", [hh, t], st["forces"])
	var vis: bool = main.is_vis(t)
	var vet: int = main.vet_of(t) if vis else 0
	var s := "[font_size=15][b][color=#ffffff]%s%s[/color][/b][/font_size]%s\n" % ["★ " if (O != null and int(O["hq"]) == t) else "", T["name"], ("  [color=#ffd84a]%s[/color]" % main.stars(vet)) if vet > 0 else ""]
	s += "[color=#8b9a8d]%s · %s[/color]\n" % [Data.CONTINENTS[T["c"]]["name"], Data.TERRAINS[T["ter"]]["name"]]
	var oc := UIKit.hexc(O["color"] if O != null else Color(Data.NEUTRAL_COLOR))
	s += "[color=%s]■[/color] %s\n" % [oc, (O["fac"]["short"] + (" (tu)" if o == hh else "")) if O != null else "Neutrale"]
	if not vis:
		var e: int = main.estimate(t)
		s += "[color=#b8c6d0]Nella nebbia: %s[/color]" % (("forze stimate [b]≈%d[/b]" % e) if e >= 0 else "forze [b]sconosciute[/b]")
	else:
		s += "Forze: [b]%s[/b] [color=#8b9a8d]%s[/color]" % [str(Data.total_units(f)) if f != null else "?", UIKit.forces_text(f) if f != null else "nascoste"]
		if vet > 0:
			s += "\n[color=#ffd84a]Veterani %s[/color] [color=#8b9a8d](+%d%%)[/color]" % [main.stars(vet), 6 * vet]
	if o >= 0 and hh >= 0 and o != hh and main.pact_between(hh, o) != null:
		s += "\n[color=#bff0d0]Patto di non aggressione %s[/color]" % main.until_text(float(main.pact_between(hh, o)["until"]))
	var mode = main.mode
	if mode != null and mode["type"] == "card":
		s += "\n[color=#ffd57a][b]Clic: %s[/b][/color]" % Data.OPS[mode["op"]]["name"]
	elif mode != null and mode["type"] == "deploy":
		if o == hh:
			s += "\n[color=#ffd57a][b]Clic: schiera i rinforzi[/b][/color]"
	elif main.sel_own() and main.target_set.has(t):
		var tg = null
		for x in main.targets:
			if int(x["idx"]) == t:
				tg = x
		var sf: Dictionary = main.send_forces(main.sel)
		var tt := float(main.gcall("travel_time", [hh, main.sel, t, sf], 0.0)) if not main.turn_mode() else 0.0
		var how := ""
		if tg != null and tg.get("airlift", false):
			how = " · ponte aereo"
		elif tg != null and tg.get("sea", false):
			how = " · via mare"
		if main.turn_mode():
			s += "\n[color=#ffd57a][b]Clic: %s · fino a %d unità%s[/b][/color]" % ["prepara lo spostamento" if o == hh else "prepara l'attacco", Data.total_units(main.movable_forces(main.sel)), " · via mare" if (tg != null and tg.get("sea", false)) else ""]
		else:
			s += "\n[color=#ffd57a][b]%s: %d unità · viaggio %.1f s%s[/b][/color]\n[color=#8b9a8d]Clic destro o trascina per inviare[/color]" % ["Sposta" if o == hh else "Attacca", Data.total_units(sf), tt, how]
	if st["buildings"].size() and vis:
		var bn := []
		for k in st["buildings"]:
			bn.append(Data.BUILDINGS[k]["name"])
		s += "\n[color=#8b9a8d]Edifici: %s[/color]" % ", ".join(bn)
	if force or s != _tip_key:
		_tip_key = s
		tip_text.text = s
		tip.reset_size()
	tip.visible = true
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	var p := mp + Vector2(18, 16)
	if p.x + tip.size.x > vs.x - 4:
		p.x = mp.x - tip.size.x - 14
	if p.y + tip.size.y > vs.y - 4:
		p.y = mp.y - tip.size.y - 12
	tip.position = p

func _mouse_on_gui() -> bool:
	var c: Control = get_viewport().gui_get_hovered_control()
	return c != null and not (c.get_script() == load("res://scripts/ui/placeholder_map.gd"))

func hide_tip() -> void:
	if tip:
		tip.visible = false

# ------------------------------------------------------------------ notizie "headline" e conferme
var _headline_q: Array = []
var _headline_busy := false
var _headline: PanelContainer
var _saved: PanelContainer

## Notizia di prima pagina (segnale di gioco "headline"): striscia in alto al centro, una alla volta.
func headline(text: String) -> void:
	if _headline_q.size() < 2:
		_headline_q.append(text)
	if not _headline_busy:
		_next_headline()

func _next_headline() -> void:
	if _headline_q.is_empty():
		_headline_busy = false
		return
	_headline_busy = true
	var text: String = _headline_q.pop_front()
	if _headline == null:
		_headline = PanelContainer.new()
		var sb := UIKit.box(Color(0.06, 0.05, 0.03, 0.96), Color(UIKit.AMBER, 0.6), 1, 3, Vector4(0, 0, 18, 0))
		sb.border_width_bottom = 2
		sb.border_color = UIKit.AMBER
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 12
		_headline.add_theme_stylebox_override("panel", sb)
		_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(14)
		var tagp := PanelContainer.new()
		tagp.add_theme_stylebox_override("panel", UIKit.box(Color("#c8462e"), Color(0, 0, 0, 0), 0, 0, Vector4(12, 8, 12, 8)))
		tagp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var th := UIKit.hbox(6)
		th.add_child(UIKit.icon("news", 16, Color("#fff1d8")))
		th.add_child(UIKit.label("ULTIM'ORA", 13, Color("#fff1d8"), "mono", 700))
		tagp.add_child(th)
		h.add_child(tagp)
		var l := UIKit.label("", 17, UIKit.WHITE, "sans", 700)
		l.name = "Text"
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		_headline.add_child(h)
		add_child(_headline)
	var lbl: Label = _headline.find_child("Text", true, false)
	lbl.text = text
	_headline.visible = true
	_headline.reset_size()
	var vw := get_viewport_rect().size.x
	_headline.position = Vector2((vw - _headline.size.x) / 2, (UNDER_TB + 4) if (game != null and main.turn_mode()) else TOP_H + 8)
	_headline.modulate.a = 0.0
	var y0 := _headline.position.y
	_headline.position.y = y0 - 16
	Sfx.play("card")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_headline, "modulate:a", 1.0, 0.25)
	tw.tween_property(_headline, "position:y", y0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(3.0)
	tw.tween_property(_headline, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_headline.visible = false
		_next_headline())

## Piccola conferma in basso a destra (es. salvataggio automatico).
func saved_hint(text: String) -> void:
	if _saved == null:
		_saved = PanelContainer.new()
		_saved.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.06, 0.06, 0.92), UIKit.LINE2, 1, 3, Vector4(10, 5, 12, 5)))
		_saved.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(7)
		h.add_child(UIKit.icon("save", 14, UIKit.GREEN))
		var l := UIKit.label("", 13, UIKit.TEXT, "sans", 600)
		l.name = "Text"
		h.add_child(l)
		_saved.add_child(h)
		add_child(_saved)
	(_saved.find_child("Text", true, false) as Label).text = text
	_saved.reset_size()
	var vs := get_viewport_rect().size
	_saved.position = Vector2(M + RAIL_W + 10, vs.y - _saved.size.y - 16)
	_saved.visible = true
	_saved.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(_saved, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(_saved, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _saved.visible = false)

## Indicatore delle minacce nella barra in alto (lampeggia finché ci sono divisioni nemiche in arrivo).
func set_threats(list: Array) -> void:
	if threat_btn == null:
		return
	var n := list.size()
	var was := threat_btn.visible
	threat_btn.visible = n > 0
	if n == 0:
		if _threat_tw:
			_threat_tw.kill()
			_threat_tw = null
		return
	var first: Dictionary = list[0]
	threat_lbl.text = ("%d ATTACCHI" % n if n > 1 else "ATTACCO") + " · %d s" % int(ceil(maxf(0.0, float(first["left"]))))
	if not was or _threat_tw == null:
		if _threat_tw:
			_threat_tw.kill()
		_threat_tw = create_tween().set_loops()
		_threat_tw.tween_property(threat_btn, "modulate", Color(1.25, 1.1, 1.1), 0.45)
		_threat_tw.tween_property(threat_btn, "modulate", Color(1, 1, 1), 0.45)
