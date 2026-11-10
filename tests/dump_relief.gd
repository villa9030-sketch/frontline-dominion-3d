extends SceneTree
## Profilo delle quote lungo l'asse del campo (controllo a occhio del rilievo, Fase 7).
func _initialize() -> void:
	var BR = load("res://scripts/battle/battle_relief.gd")
	for tk in ["pianura", "montagna", "deserto", "artico", "foresta"]:
		var r = BR.new(tk, 3, 4800.0, 2700.0, 138.0, 2544.0, false, 0.0, false, [[Vector2(-60, 1200), Vector2(4900, 1300)]])
		var line := "%-9s " % tk
		var x := 0.0
		while x <= 4800.0:
			line += "%4.0f" % r.h(x, 1350.0)
			x += 200.0
		print(line, "   (max pendenza: ", "%.1f gradi" % _max_slope(r), ")")
	quit(0)

func _max_slope(r) -> float:
	var m := 0.0
	for j in range(1, r.gh - 1):
		for i in range(1, r.gw - 1):
			var dx: float = (r.hg[j * r.gw + i + 1] - r.hg[j * r.gw + i - 1]) / (2.0 * r.G * r.S)
			var dy: float = (r.hg[(j + 1) * r.gw + i] - r.hg[(j - 1) * r.gw + i]) / (2.0 * r.G * r.S)
			m = maxf(m, sqrt(dx * dx + dy * dy))
	return rad_to_deg(atan(m))
