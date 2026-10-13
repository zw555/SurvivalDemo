class_name SpawnPoint
extends Marker2D
## 刷怪/刷物资点：由 main.gd 在开局统一调用 spawn()，按配置生成内容。
## 数量 = 基础数量 × main.gd 传入的密度系数，调密度不用改场景。
## 生成的节点挂在本点下面，位置在本点周围 spawn_radius 内随机。

const ZOMBIE_SCENE := preload("res://scenes/enemies/Zombie.tscn")
const PICKUP_SCENE := preload("res://scenes/items/ItemPickup.tscn")
const BOX_SCENE := preload("res://scenes/world/StorageBox.tscn")

@export_group("僵尸")
@export var zombie_count := 0
## 变体池：null = 普通僵尸；与 variant_weights 一一对应，权重缺省按 1.0。
@export var variants: Array[ZombieVariant] = []
@export var variant_weights: Array[float] = []
@export_group("散落物资")
@export var pickup_rolls := 0
@export var pickup_table: LootTable
@export_group("物资箱")
@export var box_count := 0
@export var box_rolls := 3
@export var box_table: LootTable

@export var spawn_radius := 60.0


func spawn(zombie_scale := 1.0, loot_scale := 1.0) -> void:
	var zombies := roundi(zombie_count * zombie_scale)
	for i in zombies:
		_spawn_zombie()
	var rolls := roundi(pickup_rolls * loot_scale)
	for i in rolls:
		_spawn_pickup()
	for i in box_count:
		_spawn_box()


func _random_offset() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spawn_radius


func _spawn_zombie() -> void:
	var zombie := ZOMBIE_SCENE.instantiate() as Zombie
	zombie.variant = _pick_variant()
	add_child(zombie)
	zombie.global_position = global_position + _random_offset()


func _pick_variant() -> ZombieVariant:
	if variants.is_empty():
		return null
	var total := 0.0
	for i in variants.size():
		total += _weight_at(i)
	var roll := randf() * total
	for i in variants.size():
		roll -= _weight_at(i)
		if roll <= 0.0:
			return variants[i]
	return variants.back()


func _weight_at(index: int) -> float:
	if index < variant_weights.size():
		return maxf(0.0, variant_weights[index])
	return 1.0


func _spawn_pickup() -> void:
	if pickup_table == null:
		return
	var item := pickup_table.pick()
	if item == null:
		return
	var pickup := PICKUP_SCENE.instantiate()
	pickup.item = item
	add_child(pickup)
	pickup.global_position = global_position + _random_offset()


func _spawn_box() -> void:
	var box := BOX_SCENE.instantiate() as StorageBox
	box.starting_items = []
	if box_table != null:
		box.starting_items = box_table.pick_many(box_rolls)
	add_child(box)
	box.global_position = global_position + _random_offset() * 0.4
