class_name DeathEffect
extends Node2D
## 死亡特效：红色方块缩小旋转消失，并播放死亡音效。
## 独立于尸体本体存在，本体可以立即释放（冒烟测试依赖这一点）。

const SFX_DIE := preload("res://assets/audio/zombie_die.wav")

@export var square_size := 24.0
@export var color := Color(0.62, 0.18, 0.16)

var _lifetime := 0.0


func _ready() -> void:
	var visual := Polygon2D.new()
	visual.color = color
	var h := square_size * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
	])
	add_child(visual)

	var sfx := AudioStreamPlayer.new()
	sfx.stream = SFX_DIE
	sfx.pitch_scale = randf_range(0.9, 1.1)
	add_child(sfx)
	sfx.play()

	_lifetime = maxf(0.4, sfx.stream.get_length())
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.35) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "rotation", randf_range(-0.7, 0.7), 0.35)
	tween.tween_property(visual, "color", Color(color.r, color.g, color.b, 0.0), 0.4)
	tween.chain().tween_interval(_lifetime - 0.4)
	tween.chain().tween_callback(queue_free)
