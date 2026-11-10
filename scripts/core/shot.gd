extends Node
## Autoload "Shot": screenshot automatici per il collaudo.
## Argomenti utente (dopo "--" sulla riga di comando di Godot):
##   --shot=percorso.png   salva uno screenshot della finestra e chiude
##   --frames=N            frame da attendere prima dello scatto (default 90)
##   --quit-after=S        chiude dopo S secondi anche senza scatto
## Le scene possono leggere i propri argomenti con Shot.arg("nome", "default").
var _args := {}
var _frames := 0
var _target := -1
var _path := ""
var _quit_after := -1.0
var _t := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_path = String(_args.get("shot", ""))
	if _path != "":
		_target = int(_args.get("frames", "90"))
	_quit_after = float(_args.get("quit-after", "-1"))
	process_mode = Node.PROCESS_MODE_ALWAYS

func arg(name: String, default_value: String = "") -> String:
	return String(_args.get(name, default_value))

func has_arg(name: String) -> bool:
	return _args.has(name)

func _process(delta: float) -> void:
	_t += delta
	if _target >= 0:
		_frames += 1
		if _frames >= _target:
			_target = -1
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var p := _path
			if not p.is_absolute_path() and not p.begins_with("res://") and not p.begins_with("user://"):
				p = ProjectSettings.globalize_path("res://").path_join(p)
			DirAccess.make_dir_recursive_absolute(p.get_base_dir())
			var err := img.save_png(p)
			print("[Shot] salvato ", p, " ", img.get_size(), " err=", err)
			get_tree().quit()
	if _quit_after > 0 and _t >= _quit_after:
		get_tree().quit()
