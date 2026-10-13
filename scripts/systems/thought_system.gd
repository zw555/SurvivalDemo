class_name ThoughtSystem
extends Node
## 主角内心独白引导系统：按玩家状态触发"自言自语"，代替按键式教程。
## 每条想法有触发条件、优先级、冷却与次数上限；同一时刻只说一句，
## 说完有最短间隔，避免主角变成话痨。括号里的提示只在前几天出现，
## 之后只留独白，让玩家根据状态自行判断行动。

signal thought_shown(id: String, text: String)

## 评估间隔（秒）。
const TICK_INTERVAL := 1.0
## 一句独白停留时间（秒）。
const DISPLAY_SECONDS := 5.0
## 说完一句到下一句的最短间隔（秒）。
const REFRACTORY := 2.0
## 括号提示保留到第几天（之后撤掉手把手引导）。
const HINT_UNTIL_DAY := 3
## "首次发现建筑"的判定半径（像素）。
const DISCOVER_RADIUS := 420.0
## 时间比较容差：固定帧率下累加的 elapsed 会有浮点误差（如 2.99999999999999）。
const TICK_EPS := 0.01

## 开局多少秒后说第一句（给玩家一点环顾四周的时间）。
@export var start_delay := 3.0

var _player: Player
var _camp: CampStorage
var _day_night: DayNight
var _hud: Hud
## 特殊建筑：{id, name, pos}，供"首次发现"想法判定。
var _buildings: Array[Dictionary] = []

var _defs: Array[Dictionary] = []
var _counts := {}
var _cooldowns := {}
var _was_inside := true
var _just_left := false
var _elapsed := 0.0
var _accum := TICK_INTERVAL
var _display_left := 0.0
var _refractory := 0.0


func _ready() -> void:
	_build_defs()


## 由 main.gd 注入依赖；buildings 为 [{id, name, pos}]。
func setup(player: Player, camp: CampStorage, day_night: DayNight, hud: Hud,
		buildings: Array) -> void:
	_player = player
	_camp = camp
	_day_night = day_night
	_hud = hud
	for b in buildings:
		_buildings.append(b)
	_was_inside = _inside_camp()


func _process(delta: float) -> void:
	_elapsed += delta
	_display_left = maxf(0.0, _display_left - delta)
	_refractory = maxf(0.0, _refractory - delta)
	for id in _cooldowns:
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)
	_accum -= delta
	if _accum <= 0.0:
		_accum = TICK_INTERVAL
		evaluate()


## 评估一轮：找到当前满足条件且优先级最高的想法并说出（至多一句）。
## 供内部节流与测试直接调用。
func evaluate() -> void:
	if _player == null or _player.dead or _day_night == null:
		return
	_update_room_state()
	if _display_left > 0.0 or _refractory > 0.0:
		return
	var best: Dictionary = {}
	for def in _defs:
		if int(def.max_count) >= 0 and int(_counts[def.id]) >= int(def.max_count):
			continue
		if float(_cooldowns[def.id]) > 0.0:
			continue
		if def.cond.call() and (best.is_empty() or int(def.priority) > int(best.priority)):
			best = def
	if not best.is_empty():
		_speak(best)


## —— 测试辅助 ——————————————————————————————

## 跳过"说完一句"的显示与间隔冷却（测试用，正常游戏请勿调用）。
func skip_display_wait() -> void:
	_display_left = 0.0
	_refractory = 0.0


func trigger_count(id: String) -> int:
	return int(_counts.get(id, 0))


func definition_count() -> int:
	return _defs.size()


## —— 存档 ——————————————————————————————————

func get_save_data() -> Dictionary:
	var arr: Array = []
	for def in _defs:
		arr.append(int(_counts[def.id]))
	return {"counts": arr}


func load_save_data(data: Dictionary) -> void:
	var arr: Array = data.get("counts", [])
	for i in mini(arr.size(), _defs.size()):
		_counts[_defs[i].id] = int(arr[i])


## —— 内部 ——————————————————————————————————

func _add(id: String, text: String, hint: String, priority: int,
		max_count: int, cooldown: float, cond: Callable) -> void:
	_defs.append({
		"id": id, "text": text, "hint": hint, "priority": priority,
		"max_count": max_count, "cooldown": cooldown, "cond": cond,
	})
	_counts[id] = 0
	_cooldowns[id] = 0.0


func _build_defs() -> void:
	# —— 教程场景（一次性）——
	_add("wake", "肚子有点饿了……得先找点吃的。",
			"屋里的冰箱、营地仓库都有吃的：按 E 打开，点背包格子吃掉。",
			12, 1, 0.0, _cond_wake)
	_add("go_out", "外面可不是闹着玩的，至少得带点像样的装备。",
			"点背包里的武器、衣服穿上；按 Tab 检查装备、食物和水。",
			2, 1, 0.0, _cond_go_out)
	_add("first_hurt", "该死，受伤了……得找些药品。",
			"血条掉了就要用药：点背包里的绷带；没有药就先撤回营地。",
			3, 1, 0.0, _cond_first_hurt)
	_add("explore", "光靠这根破棍子可不行。警察局里说不定有枪。",
			"市公安局在营地东北方向，守卫很强——带上食物和水，打不过就跑。",
			4, 1, 0.0, _cond_explore)
	# —— 首次发现特殊建筑（每栋一次）——
	_add("discover_market", "那里可能有我需要的东西。",
			"发现：惠民超市——吃的是这里的主题，货架不少，守卫也是。",
			7, 1, 0.0, _cond_discover_market)
	_add("discover_police", "那里可能有我需要的东西。",
			"发现：市公安局——枪在那里，但守卫很强。",
			7, 1, 0.0, _cond_discover_police)
	_add("discover_hospital", "那里可能有我需要的东西。",
			"发现：仁爱医院——药品的来源。",
			7, 1, 0.0, _cond_discover_hospital)
	_add("discover_hardware", "那里可能有我需要的东西。",
			"发现：五金店——制作材料的来源。",
			7, 1, 0.0, _cond_discover_hardware)
	_add("discover_military", "那里可能有我需要的东西。",
			"发现：城北军营——直升机停在这里，也有重兵把守。",
			7, 1, 0.0, _cond_discover_military)
	# —— 状态想法（可重复，有冷却）——
	_add("hunger", "得找点吃的了。",
			"食物见底了：翻容器或出门搜刮，别等到饿到掉血。",
			8, -1, 150.0, _cond_hunger)
	_add("thirst", "比起食物，我现在更需要水。",
			"水比食物耗得快，看到瓶装水先囤起来。",
			9, -1, 150.0, _cond_thirst)
	_add("hp_low", "不能再硬撑了，得找药。",
			"点击药品回复；没有药就脱离战斗，回营地休息恢复。",
			10, -1, 90.0, _cond_hp_low)
	_add("poor_gear", "这身装备恐怕撑不了多久。",
			"出门前看看 Tab 面板：武器太差就先去超市、五金店转转。",
			6, -1, 300.0, _cond_poor_gear)
	# —— 里程碑反馈 ——
	_add("gun_got", "有了这家伙，底气足多了。……但子弹是有限的。",
			"子弹打完就没了：省着用，落单的僵尸交给近战更划算。",
			5, 1, 0.0, _cond_gun_got)


func _speak(def: Dictionary) -> void:
	var id: String = def.id
	_counts[id] = int(_counts.get(id, 0)) + 1
	var cd := float(def.cooldown)
	if cd > 0.0:
		_cooldowns[id] = cd
	_display_left = DISPLAY_SECONDS
	_refractory = REFRACTORY
	var hint: String = ""
	if _day_night.day_number <= HINT_UNTIL_DAY:
		hint = def.hint
	if _hud != null:
		_hud.show_thought(def.text, hint)
	thought_shown.emit(id, def.text)


func _update_room_state() -> void:
	var inside := _inside_camp()
	_just_left = _was_inside and not inside
	_was_inside = inside


func _inside_camp() -> bool:
	return _camp != null and _player != null \
			and _camp.has_point(_player.global_position)


func _near_building(id: String) -> bool:
	for b in _buildings:
		if b.id == id and _player.global_position.distance_to(b.pos) <= DISCOVER_RADIUS:
			return true
	return false


func _has_gun() -> bool:
	for slot in [ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R]:
		var item: ItemData = _player.equipped.get(slot)
		if item != null and item.kind == ItemData.KIND_GUN:
			return true
	for item in _player.inventory.slots:
		if item != null and item.kind == ItemData.KIND_GUN:
			return true
	return false


## —— 触发条件 ——————————————————————————————

func _cond_wake() -> bool:
	return _day_night.day_number == 1 \
			and _elapsed >= start_delay - TICK_EPS and _inside_camp()


func _cond_go_out() -> bool:
	return not _inside_camp()


func _cond_first_hurt() -> bool:
	return _player.health < float(_player.max_health)


func _cond_explore() -> bool:
	return (_day_night.day_number >= 2 or _near_building("police")) and not _has_gun()


func _cond_discover_market() -> bool:
	return _near_building("market")


func _cond_discover_police() -> bool:
	return _near_building("police")


func _cond_discover_hospital() -> bool:
	return _near_building("hospital")


func _cond_discover_hardware() -> bool:
	return _near_building("hardware")


func _cond_discover_military() -> bool:
	return _near_building("military")


func _cond_hunger() -> bool:
	return _player.food < 30.0


func _cond_thirst() -> bool:
	return _player.water < 30.0


func _cond_hp_low() -> bool:
	return _player.health < 40.0


func _cond_poor_gear() -> bool:
	return _just_left and _player.current_damage() <= 7


func _cond_gun_got() -> bool:
	return _has_gun()
