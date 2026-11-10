extends SceneTree
func _init():
	var D = load("res://scripts/core/data.gd").new()
	print("territori ", D.TERRITORIES.size(), " unita ", D.UNIT_KEYS.size(), " tank cost ", D.UNITS["tank"]["cost"], " adj0 ", D.TERRITORIES[0]["adj"], " sea0 ", D.TERRITORIES[0]["sea"])
	print("forze ", D.total_units({"inf": 3, "tank": 2}))
	D.free()
	quit()
