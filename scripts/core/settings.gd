extends Node
## Autoload "Settings": impostazioni persistenti in user://settings.cfg.
## API: Settings.get_value(key), Settings.set_value(key, v), signal changed(key).
## Chiavi (SPEC3D FASE 2): quality ("basso"|"medio"|"alto"), fullscreen, vol_master, vol_sfx, vol_music,
## camera_speed, edge_scroll, show_names, autosave (0 = disattivato, altrimenti ogni turno del giocatore), daynight (FASE 4),
## ai_follow (bool) e ai_speed (FASE 6, turni IA; ai_step_delay() → secondi per mossa).
## Chiavi dell'interfaccia: tips (suggerimenti guida), tips_seen (Dictionary), tutorial_done (bool), ui_scale.
## Applica da sé ciò che riguarda finestra, viewport (MSAA, scala 3D, FXAA) e volumi (bus Master, Sfx, Music).

signal changed(key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"quality": "medio",
	"fullscreen": false,   # primo avvio in finestra massimizzata (più prudente); Alt+Invio / impostazioni per lo schermo intero
	"vol_master": 0.8,
	"vol_sfx": 0.75,
	"vol_music": 0.55,
	"camera_speed": 1.0,
	"edge_scroll": true,
	"show_names": true,
	"autosave": 5,
	"tips": true,
	"tips_seen": {},
	"tutorial_done": false, # tutorial guidato del primo turno già completato o saltato
	"ui_scale": 1.0,
	"daynight": true,      # ciclo giorno/notte sul tabellone (lo legge la mappa)
	"ai_follow": true,     # FASE 6: la telecamera segue gli attacchi e gli spostamenti delle IA
	"ai_speed": "normale", # FASE 6: velocità dei turni IA (lenta|normale|veloce|istantanea → opts.ai_step_delay)
}
const AI_SPEED_KEYS := ["lenta", "normale", "veloce", "istantanea"]
const AI_SPEED_NAMES := {"lenta": "Lenta", "normale": "Normale", "veloce": "Veloce", "istantanea": "Istantanea"}
## Secondi di animazione per ogni mossa dell'IA (opts.ai_step_delay del nucleo).
const AI_STEP_DELAY := {"lenta": 1.6, "normale": 0.9, "veloce": 0.4, "istantanea": 0.0}
const QUALITY_KEYS := ["basso", "medio", "alto"]
const QUALITY_NAMES := {"basso": "Bassa", "medio": "Media", "alto": "Alta"}

var _v := {}
var _save_pending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_v = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if not _windowed_env() and cf.load(PATH) == OK:
		for k in DEFAULTS.keys():
			if cf.has_section_key("settings", k):
				_v[k] = _coerce(k, cf.get_value("settings", k))
	call_deferred("apply_all")

func _coerce(k: String, v):
	var d = DEFAULTS[k]
	match typeof(d):
		TYPE_BOOL: return bool(v)
		TYPE_FLOAT: return float(v)
		TYPE_INT: return int(v)
		TYPE_STRING:
			if k == "quality" and not QUALITY_KEYS.has(String(v)):
				return d
			if k == "ai_speed" and not AI_SPEED_KEYS.has(String(v)):
				return d
			return String(v)
		TYPE_DICTIONARY: return v if v is Dictionary else {}
	return v

func get_value(key: String, def = null):
	if _v.has(key):
		return _v[key]
	return DEFAULTS.get(key, def)

func set_value(key: String, v) -> void:
	if DEFAULTS.has(key):
		v = _coerce(key, v)
	if _v.has(key) and typeof(_v[key]) == typeof(v) and _v[key] == v and not (v is Dictionary):
		return
	_v[key] = v
	_apply(key)
	changed.emit(key)
	_queue_save()

func reset_defaults() -> void:
	var seen = _v.get("tips_seen", {})
	_v = DEFAULTS.duplicate(true)
	_v["tips_seen"] = seen
	apply_all()
	for k in DEFAULTS.keys():
		changed.emit(k)
	_queue_save()

## Suggerimenti della guida già mostrati.
func tip_seen(id: String) -> bool:
	return bool((_v.get("tips_seen", {}) as Dictionary).get(id, false))

func mark_tip(id: String) -> void:
	var d: Dictionary = (_v.get("tips_seen", {}) as Dictionary).duplicate()
	d[id] = true
	_v["tips_seen"] = d
	_queue_save()

func reset_tips() -> void:
	_v["tips_seen"] = {}
	changed.emit("tips_seen")
	_queue_save()

func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	call_deferred("save")

func save() -> void:
	_save_pending = false
	if _windowed_env():
		return   # test automatici: non modificano le impostazioni dell'utente
	var cf := ConfigFile.new()
	for k in _v.keys():
		cf.set_value("settings", k, _v[k])
	cf.save(PATH)

# ------------------------------------------------------------------ applicazione
func apply_all() -> void:
	for k in ["fullscreen", "quality", "vol_master", "vol_sfx", "vol_music"]:
		_apply(k)

func _apply(key: String) -> void:
	match key:
		"fullscreen":
			_apply_window()
		"quality":
			_apply_quality(get_viewport())
		"vol_master":
			var bus := AudioServer.get_bus_index("Master")
			var v := float(_v["vol_master"])
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(bus, v <= 0.001)
		"vol_sfx":
			var sfx := get_node_or_null("/root/Sfx")
			if sfx != null and sfx.has_method("set_volume"):
				sfx.set_volume(float(_v["vol_sfx"]))
		"vol_music":
			var mu := get_node_or_null("/root/Music")
			if mu != null and mu.has_method("set_volume"):
				mu.set_volume(float(_v["vol_music"]))

func _windowed_env() -> bool:
	# niente schermo intero per i test automatici e in modalità headless
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_args().has("--script"):
		return true   # anche i test con --script (es. tests/test_flow.gd) non toccano le impostazioni dell'utente
	var shot := get_node_or_null("/root/Shot")
	return shot != null and shot.has_method("has_arg") and (shot.has_arg("shot") or shot.has_arg("quit-after"))

func _apply_window() -> void:
	if _windowed_env():
		return
	var w := get_window()
	if bool(_v["fullscreen"]):
		w.mode = Window.MODE_FULLSCREEN
	elif w.mode != Window.MODE_MAXIMIZED:
		# finestra: prima dimensione ragionevole centrata (per quando l'utente la ripristina), poi massimizzata
		if w.mode != Window.MODE_WINDOWED:
			w.mode = Window.MODE_WINDOWED
		var scr := DisplayServer.screen_get_usable_rect(w.current_screen)
		var sz := Vector2i(mini(1600, int(scr.size.x * 0.9)), mini(900, int(scr.size.y * 0.9)))
		w.size = sz
		w.position = scr.position + (scr.size - sz) / 2
		w.mode = Window.MODE_MAXIMIZED

## Parametri del viewport secondo la qualità (MSAA, scala di rendering 3D, FXAA, LOD delle mesh).
## Ombre, SSAO, vegetazione e terreno li regolano tabellone e battaglia leggendo "quality".
func _apply_quality(vp: Viewport) -> void:
	if vp == null:
		return
	match String(_v["quality"]):
		"basso":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.75
			vp.mesh_lod_threshold = 4.0
		"alto":
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.mesh_lod_threshold = 0.5
		_:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.mesh_lod_threshold = 1.0

## Ritardo tra le mosse dell'IA (s) secondo l'impostazione «Velocità turni IA».
func ai_step_delay() -> float:
	return float(AI_STEP_DELAY.get(String(get_value("ai_speed")), 0.9))

## Livello numerico della qualità (0 basso, 1 medio, 2 alto) per chi preferisce un intero.
func quality_level() -> int:
	return maxi(0, QUALITY_KEYS.find(String(_v["quality"])))
