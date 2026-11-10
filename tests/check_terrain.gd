extends SceneTree
## Controllo di compilazione dei file del terreno di battaglia (Fase 7) e prova di costruzione headless.
func _initialize() -> void:
	var ok := true
	for f in ["battle_rules", "battle_relief", "battle_sim", "battle_props", "battle_terrain", "battle_coast", "battle3d"]:
		var sc = load("res://scripts/battle/%s.gd" % f)
		if sc == null or not (sc as Script).can_instantiate():
			print("ERRORE: %s non compila" % f)
			ok = false
	print("check_terrain: ", "OK" if ok else "FALLITO")
	quit(0 if ok else 1)
