class_name CampStorage
extends ContainerBase
## 安全屋与仓库：仓库无限容量；僵尸用 has_point() 判断玩家是否在屋内
## （再结合门是否关闭决定是否放弃追击）。存取 / 开关逻辑在 ContainerBase。

@export var half_size := Vector2(350, 200)


func _init() -> void:
	display_name = "安全屋仓库"
	open_prompt = "打开安全屋仓库"
	close_prompt = "关闭安全屋仓库"


func _ready() -> void:
	super._ready()
	add_to_group("camp")


## 僵尸用它判断玩家是否在安全区内。
func has_point(point: Vector2) -> bool:
	return absf(point.x - global_position.x) <= half_size.x \
			and absf(point.y - global_position.y) <= half_size.y
