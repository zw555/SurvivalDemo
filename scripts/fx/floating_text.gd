class_name FloatingText
extends Label
## 世界空间飘字（伤害数字等）：向上漂浮并淡出后自行销毁。
## 用法：FloatingText.spawn(host_node, global_pos, "-25", Color.YELLOW)


static func spawn(host: Node, global_pos: Vector2, text: String, color: Color, font_size := 15) -> void:
	if host == null:
		return
	var label := FloatingText.new()
	label.text = text
	label.z_index = 100
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	host.add_child(label)
	label.global_position = global_pos + Vector2(randf_range(-8.0, 8.0), -20.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position",
			label.global_position + Vector2(0.0, -28.0), 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
