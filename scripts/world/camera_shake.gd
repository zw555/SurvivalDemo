class_name CameraShake
extends Camera2D
## 受创震屏：trauma 值随时间衰减，抖动幅度 = trauma 的平方（大冲击更猛）。

@export var shake_decay := 5.0
@export var max_offset := 14.0

var _trauma := 0.0


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		return
	_trauma = maxf(0.0, _trauma - shake_decay * delta)
	var strength := _trauma * _trauma
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_offset * strength
