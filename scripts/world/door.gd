class_name Door
extends Interactable
## 安全屋的门：E 键开关。关门后门体物理阻挡通行，且屋内成为安全区
## （僵尸放弃追击屋内的玩家）；门开着时僵尸可以追进来——出门记得关门。

signal toggled(closed: bool)

@export var closed := true

@onready var _gate_shape: CollisionShape2D = $GateBody/GateShape
@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	super._ready()
	add_to_group("gate")
	_apply_state()


func get_prompt() -> String:
	return "开门" if closed else "关门"


func interact(_player: Player) -> void:
	closed = not closed
	_apply_state()
	toggled.emit(closed)


## 存档恢复用：直接设置门状态。
func set_closed(value: bool) -> void:
	closed = value
	_apply_state()


## 导航烘焙专用：烘焙期间临时禁用门体（门洞必须在导航网格里可通行），
## 结束后按当前开关状态恢复。
func set_nav_parse_mode(parse_mode: bool) -> void:
	if parse_mode:
		_gate_shape.disabled = true
	else:
		_apply_state()


func _apply_state() -> void:
	# 门关：门板横在门洞上并启用碰撞；门开：门板旋到屋内侧、关闭碰撞。
	_gate_shape.set_deferred("disabled", not closed)
	_visual.rotation_degrees = 0.0 if closed else 90.0
	_visual.position = Vector2.ZERO if closed else Vector2(-26, -26)
	_visual.modulate = Color(1, 1, 1, 1) if closed else Color(1, 1, 1, 0.55)
