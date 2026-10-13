class_name ZombieVariant
extends Resource
## 僵尸变体数据：一组覆盖僵尸默认参数的数值 + 外观颜色。
## 新增变体 = 新建一个 .tres 配置，不改任何代码（DESIGN.md「内容生成」决定）。

@export var display_name := "普通丧尸"
@export var color := Color(0.42, 0.58, 0.32)
@export var max_health := 50
@export var damage := 5
@export var move_speed := 90.0
@export var detect_radius := 260.0
