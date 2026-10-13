class_name Grenade
extends Node2D
## 手雷：被投出后飞向目标点，短暂引信后爆炸，
## 对爆炸半径内的所有僵尸造成伤害（原型阶段不伤害玩家）。

var blast_damage := 60.0
var blast_radius := 90.0
var _visual: Polygon2D


func _ready() -> void:
	_visual = Polygon2D.new()
	_visual.color = Color(0.3, 0.42, 0.25, 1)
	var points := PackedVector2Array()
	for i in 12:
		var ang := TAU * i / 12.0
		points.append(Vector2(cos(ang), sin(ang)) * 6.0)
	_visual.polygon = points
	add_child(_visual)


## 飞行到目标点 → 引信闪烁 → 爆炸 → 视觉淡出后自毁。
func launch(target: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, 0.35)
	tw.tween_interval(0.45)
	tw.tween_callback(_explode)


func _explode() -> void:
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null:
			continue
		if global_position.distance_to(zombie.global_position) <= blast_radius:
			zombie.take_damage(int(blast_damage),
					(zombie.global_position - global_position).normalized())
	# 爆炸声惊动大范围内的丧尸（听觉系统）
	NoiseEvent.emit(self, global_position, NoiseEvent.EXPLOSION_LOUDNESS)
	# 爆炸视觉：橙色圆斑扩张淡出（挂在自身下面，跟随一起销毁）。
	var boom := Polygon2D.new()
	boom.color = Color(1.0, 0.6, 0.2, 0.85)
	var points := PackedVector2Array()
	for i in 20:
		var ang := TAU * i / 20.0
		points.append(Vector2(cos(ang), sin(ang)) * blast_radius * 0.5)
	boom.polygon = points
	add_child(boom)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(boom, "scale", Vector2(2.0, 2.0), 0.22)
	tw.tween_property(boom, "modulate:a", 0.0, 0.22)
	tw.chain().tween_callback(queue_free)
