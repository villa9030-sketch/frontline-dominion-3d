extends Control
## Banco di prova dei suoni sintetizzati (Sfx): un pulsante per ogni suono, loop dei motori con velocità regolabile,
## riproduzione in sequenza, musica di ogni stato (con dissolvenze reali e intensità della battaglia). Avvio:  node tools/godot_run.js --timeout=900 -- --path . res://scenes/sound_test.tscn

const GROUPS := [
	["Interfaccia (tabellone)", ["click", "select", "order", "build", "recruit", "research", "card", "capture", "battle", "alert", "radio", "victory", "defeat"]],
	["Fanteria e armi leggere", ["rifle", "mg", "hmg", "rocket", "smoke_pop"]],
	["Carri e cannoni", ["cannon", "cannon_far", "hit_armor", "explosion", "explosion_far", "expl_small", "cookoff"]],
	["Artiglieria e contraerea", ["whistle", "arty_impact", "aa", "flak"]],
	["Aerei", ["jet_flyby"]],
	["Loop: motori e rotori", ["engine_heavy", "tracks", "engine_light", "tires", "heli", "drone", "jet_loop"]],
	["Loop: ambiente", ["amb_wind", "amb_battle", "amb_crackle"]],
]
const MUSIC := [["menu", "Menu"], ["map", "Mappa / turni"], ["tension", "Tensione / turno IA"], ["battle", "Battaglia"],
	["victory", "Vittoria"], ["defeat", "Sconfitta"]]
const LABEL := {
	"click": "Clic", "select": "Selezione", "order": "Ordine (radio)", "build": "Costruzione", "recruit": "Reclutamento",
	"research": "Ricerca", "card": "Carta", "capture": "Conquista", "battle": "Battaglia", "alert": "Allarme",
	"radio": "Radio", "victory": "Vittoria", "defeat": "Sconfitta",
	"rifle": "Fucili (raffica di squadra)", "mg": "Mitragliatrice", "hmg": "Mitragliatrice pesante (bunker)",
	"rocket": "Razzo controcarro", "smoke_pop": "Lanciafumogeni",
	"cannon": "Cannone del carro (vicino)", "cannon_far": "Cannone (lontano)", "hit_armor": "Colpo su corazza",
	"explosion": "Esplosione (vicina)", "explosion_far": "Esplosione (lontana)", "expl_small": "Esplosione piccola",
	"cookoff": "Munizioni che esplodono",
	"whistle": "Fischio del proiettile", "arty_impact": "Impatto d'artiglieria", "aa": "Cannone contraereo", "flak": "Scoppi in quota",
	"jet_flyby": "Passaggio del caccia",
	"engine_heavy": "Motore diesel del carro", "tracks": "Cingoli", "engine_light": "Motore mezzo ruotato", "tires": "Gomme",
	"heli": "Elicottero", "drone": "Drone", "jet_loop": "Reattore",
	"amb_wind": "Vento", "amb_battle": "Battaglia lontana", "amb_crackle": "Fucileria lontana",
}

var _one: Array[AudioStreamPlayer] = []
var _loops := {}            # nome -> AudioStreamPlayer
var _speed := 0.5
var _status: Label
var _seq: Array = []
var _seq_t := 0.0
var _cur := ""
var _rng := RandomNumberGenerator.new()
var _mstatus: Label

func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 20; sc.offset_top = 16; sc.offset_right = -20; sc.offset_bottom = -16
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	var title := Label.new()
	title.text = "FRONTLINE DOMINION — prova dei suoni (tutti sintetizzati in codice)"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	_btn(bar, "▶ Tutti in sequenza", _play_all)
	_btn(bar, "■ Ferma tutto", _stop_all)
	var lb := Label.new()
	lb.text = "   Velocità del mezzo (loop):"
	bar.add_child(lb)
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.01; sl.value = _speed
	sl.custom_minimum_size = Vector2(220, 0)
	sl.value_changed.connect(func(v: float) -> void: _speed = v)
	bar.add_child(sl)
	_status = Label.new()
	vb.add_child(_status)
	# --- musica (autoload Music: generata in sottofondo all'avvio)
	var mh := Label.new()
	mh.text = "Musica (stati di gioco)"
	mh.add_theme_font_size_override("font_size", 17)
	mh.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	vb.add_child(mh)
	var mg := GridContainer.new()
	mg.columns = 4
	vb.add_child(mg)
	for e in MUSIC:
		var mood := String(e[0])
		_btn(mg, "♪ " + String(e[1]), func() -> void: _music(mood))
	_btn(mg, "■ Ferma musica", func() -> void: Music.stop(2.0))
	var ib := HBoxContainer.new()
	vb.add_child(ib)
	var il := Label.new()
	il.text = "Intensità della battaglia:"
	ib.add_child(il)
	var isl := HSlider.new()
	isl.min_value = 0.0; isl.max_value = 1.0; isl.step = 0.01; isl.value = 0.45
	isl.custom_minimum_size = Vector2(260, 0)
	isl.value_changed.connect(func(v: float) -> void: Music.set_intensity(v))
	ib.add_child(isl)
	_mstatus = Label.new()
	vb.add_child(_mstatus)
	for g in GROUPS:
		var h := Label.new()
		h.text = String(g[0])
		h.add_theme_font_size_override("font_size", 17)
		h.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
		vb.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 4
		vb.add_child(grid)
		for nm in g[1]:
			var n := String(nm)
			var cap := String(LABEL.get(n, n))
			if Sfx.is_loop(n):
				_btn(grid, "⟳ " + cap, func() -> void: _toggle_loop(n))
			else:
				_btn(grid, cap, func() -> void: _play(n))
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_one.append(p)

func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 34)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _play(n: String) -> float:
	var st: AudioStreamWAV = Sfx.stream_sync(n)
	if st == null:
		return 0.0
	var p: AudioStreamPlayer = _one[0]
	for q in _one:
		if not q.playing:
			p = q
			break
	p.stream = st
	p.pitch_scale = _rng.randf_range(0.94, 1.06)
	p.volume_db = linear_to_db(maxf(0.0001, Sfx.volume))
	p.play()
	return st.get_length() / p.pitch_scale

func _music(mood: String) -> void:
	Music.play(mood)
	if mood == "battle":
		Music.set_intensity(0.45)

func _toggle_loop(n: String) -> void:
	if _loops.has(n):
		(_loops[n] as AudioStreamPlayer).queue_free()
		_loops.erase(n)
		return
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.stream_sync(n)
	add_child(p)
	p.play()
	_loops[n] = p

func _stop_all() -> void:
	_seq.clear()
	_cur = ""
	for p in _one:
		p.stop()
	for k in _loops.keys():
		(_loops[k] as AudioStreamPlayer).queue_free()
	_loops.clear()

func _play_all() -> void:
	_stop_all()
	for g in GROUPS:
		for nm in g[1]:
			_seq.append(String(nm))
	_seq_t = 0.0

func _process(dt: float) -> void:
	var ready := 0
	for k in Sfx.names():
		if Sfx.is_ready(k):
			ready += 1
	if not _seq.is_empty() or _seq_t > 0.0:
		_seq_t -= dt
		if _seq_t <= 0.0:
			for k in _loops.keys():
				(_loops[k] as AudioStreamPlayer).queue_free()
			_loops.clear()
			if not _seq.is_empty():
				var n: String = _seq.pop_front()
				_cur = n
				if Sfx.is_loop(n):
					_toggle_loop(n)
					_seq_t = 3.5
				else:
					_seq_t = minf(_play(n), 6.0) + 0.5
			else:
				_cur = ""
	_status.text = "Suoni generati: %d / %d%s" % [ready, Sfx.names().size(), ("   ▶ " + String(LABEL.get(_cur, _cur))) if _cur != "" else ""]
	var rd: Array = []
	for e in MUSIC:
		if Music.is_ready(String(e[0])):
			rd.append(String(e[0]))
	_mstatus.text = "Musica pronta: %s   ▶ %s" % [", ".join(PackedStringArray(rd)) if not rd.is_empty() else "(generazione in corso…)", Music.current if Music.current != "" else "—"]
	# loop dei mezzi: intonazione e volume come in battaglia
	for k in _loops.keys():
		var p: AudioStreamPlayer = _loops[k]
		var v := linear_to_db(maxf(0.0001, Sfx.volume))
		match String(k):
			"engine_heavy", "engine_light":
				p.pitch_scale = 0.8 + 0.42 * _speed
				p.volume_db = v - 6.0 + 6.0 * _speed
			"tracks", "tires":
				p.pitch_scale = 0.7 + 0.5 * _speed
				p.volume_db = v - 30.0 + 30.0 * pow(_speed, 0.6)
			"heli", "drone", "jet_loop":
				p.pitch_scale = 0.95 + 0.1 * _speed
				p.volume_db = v
			_:
				p.volume_db = v
