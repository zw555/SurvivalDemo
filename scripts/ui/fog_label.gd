class_name FogLabel
extends Label
## 家具/门窗名称标签：跟随迷雾探索状态显隐，并绘制在迷雾之上。
## 未探索区域自动隐藏（不在黑暗中泄密）；已探索后完整清晰显示，
## 不再被迷雾的半透明黑罩盖住导致"文字显示不全"。

var _fog: FogOfWar

func _ready() -> void:
	z_index = 95  # 迷雾（z=90）之上、HUD（CanvasLayer）之下
	visible = false

func _process(_delta: float) -> void:
	if _fog == null:
		_fog = get_tree().get_first_node_in_group("fog_of_war") as FogOfWar
		if _fog == null:
			return
	var center := global_position + size * 0.5
	visible = _fog.is_explored(center)
