extends VBoxContainer
## Notifiche a comparsa sopra il riquadro ORDINI (max 2, brevi: svaniscono dopo ~3 s).

const MAX := 2

func _ready() -> void:
	# in basso al centro, sopra la barra inferiore: lontano da barra dei turni, banner e notizie; le nuove si impilano verso l'alto
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -340
	offset_right = 340
	offset_top = -168
	offset_bottom = -168
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow_horizontal = Control.GROW_DIRECTION_BOTH

func clear_all() -> void:
	for c in get_children():
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.15)
		tw.tween_callback(c.queue_free)

func push(text: String, type: String = "info") -> void:
	var col := Color("#8fb0a0")
	var ic := ""
	match type:
		"good": col = UIKit.GREEN; ic = "supply"
		"bad": col = UIKit.RED; ic = "alert"
		"alert": col = UIKit.RED; ic = "alert"
		_: col = Color("#8ab8c8"); ic = ""
	var p := PanelContainer.new()
	var sb := UIKit.box(Color(0.035, 0.065, 0.065, 0.95), Color(col, 0.55), 1, 3, Vector4(12, 7, 14, 7))
	sb.border_width_left = 4
	sb.border_color = col
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	if type == "alert":
		sb.bg_color = Color(0.20, 0.05, 0.04, 0.95)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := UIKit.hbox(8)
	if ic != "":
		hb.add_child(UIKit.icon(ic, 16))
	var l := UIKit.label(text, 14, Color("#ffe2dc") if type in ["bad", "alert"] else UIKit.TEXT, "sans", 600 if type == "alert" else 400)
	hb.add_child(l)
	p.add_child(hb)
	add_child(p)
	while get_child_count() > MAX:
		var c := get_child(0)
		remove_child(c)
		c.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(2.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
