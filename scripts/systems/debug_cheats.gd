class_name DebugCheats
extends Node
## 测试专用调试键：只在调试运行（编辑器 F5 / Debug 构建）中挂载，
## 导出 Release 版后在 _ready 里自毁——玩家拿到的版本不含任何作弊。
##
## 按键（游戏进行中直接按）：
##   F1  击杀全场丧尸（含 Boss；走正常受击流程，掉落物照常生成）
##   F2  无敌开关（免伤，食物/水照常消耗）
##   F3  清空背包并发放标准测试包（撤离清单物资 + 弹药 + 手雷）
##   F4  白天 / 黑夜切换
##   F5  回满状态（生命 / 食物 / 水 + 备弹各 120）

## 标准测试包：撤离清单所需（食物 2 / 水 2 / 汽油 1 / 医疗 1）+ 战斗补给。
const KIT_ITEMS: Array[String] = [
	"res://data/items/food_canned.tres",
	"res://data/items/food_canned.tres",
	"res://data/items/water_bottle.tres",
	"res://data/items/water_bottle.tres",
	"res://data/items/fuel.tres",
	"res://data/items/med_firstaid.tres",
	"res://data/items/med_bandage.tres",
	"res://data/items/med_bandage.tres",
	"res://data/items/ammo_pistol_box.tres",
	"res://data/items/ammo_rifle_box.tres",
	"res://data/items/weapon_grenade.tres",
	"res://data/items/weapon_grenade.tres",
]
const AMMO_PER_BOX := 60  # 与弹药盒 stack 对齐的备弹补充量


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()  # Release 导出：本节点自毁，作弊不可达
		return


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_kill_all_zombies()
		KEY_F2:
			_toggle_god_mode()
		KEY_F3:
			_give_test_kit()
		KEY_F4:
			_toggle_day_night()
		KEY_F5:
			_refill_status()


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _hud() -> Hud:
	return get_parent().get_node("HUD") as Hud


func _notify(text: String) -> void:
	var hud := _hud()
	if hud != null:
		hud.show_message("【调试】" + text, 2.0)


## F1：全场丧尸走正常受击流程扣 99999 血（复用死亡/掉落/击杀计数逻辑）。
func _kill_all_zombies() -> void:
	var killed := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie != null and zombie.health > 0.0:
			zombie.take_damage(99999)
			killed += 1
	_notify("已击杀 %d 只丧尸" % killed)


## F2：无敌开关。食物 / 水照常消耗，只免伤害。
func _toggle_god_mode() -> void:
	var player := _player()
	if player == null:
		return
	player.god_mode = not player.god_mode
	_notify("无敌模式：%s" % ("开" if player.god_mode else "关"))


## F3：清空背包 + 发标准测试包 + 备弹，保证撤离清单随时可交付。
func _give_test_kit() -> void:
	var player := _player()
	if player == null:
		return
	player.inventory.clear()
	for path in KIT_ITEMS:
		player.inventory.add_item(load(path) as ItemData)
	player.ammo_pistol += AMMO_PER_BOX
	player.ammo_rifle += AMMO_PER_BOX
	_notify("已发放标准测试包（背包已清空重发）")


## F4：白天 / 黑夜直接切换（测试夜晚视野强化、夜间丧尸行为）。
func _toggle_day_night() -> void:
	var day_night: DayNight = get_parent().get_node("DayNight")
	if day_night == null:
		return
	var to_night := not day_night.is_night
	day_night.force_night(to_night)
	_notify("切换到%s" % ("黑夜" if to_night else "白天"))


## F5：状态全满 + 备弹补充（不清背包）。
func _refill_status() -> void:
	var player := _player()
	if player == null:
		return
	player.health = float(player.max_health)
	player.food = player.max_food
	player.water = player.max_water
	player.ammo_pistol = maxi(player.ammo_pistol, AMMO_PER_BOX)
	player.ammo_rifle = maxi(player.ammo_rifle, AMMO_PER_BOX)
	_notify("状态已回满（生命/食物/水/备弹）")
