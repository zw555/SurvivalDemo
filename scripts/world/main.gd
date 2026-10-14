extends Node2D
## 游戏主场景：把玩家、营地与 HUD 连起来，并处理死亡重生。
## 同时承载全局打击感效果：命中顿帧（hit-stop）。

@export var map_size := Vector2i(2400, 1600)
@export var zombie_density := 1.0
@export var loot_density := 1.0
@export var hit_stop_duration := 0.07
@export var hit_stop_time_scale := 0.05

const SAVE_PATH := "user://savegame.json"
const ZOMBIE_SCENE := preload("res://scenes/enemies/Zombie.tscn")
const BRUTE_SCENE := preload("res://scenes/enemies/Brute.tscn")
const PICKUP_SCENE := preload("res://scenes/items/ItemPickup.tscn")

## —— 撤离任务（主线）——
## 任务阶段：none（没听说过撤离）→ radio_heard（收到广播）→
## pilot_met（见到飞行员、接到清单）→ supplied（物资已交付、NPC 在停机坪等）
## → escaped（结局已触发）。
const STAGE_NONE := "none"
const STAGE_RADIO := "radio_heard"
const STAGE_MET := "pilot_met"
const STAGE_SUPPLIED := "supplied"
const STAGE_ESCAPED := "escaped"
## 物资清单：{kind: 数量}——食物×2、水×2、汽油×1、医疗物资×1。
const SUPPLY_REQUIREMENTS := {
	ItemData.KIND_FOOD: 2,
	ItemData.KIND_WATER: 2,
	ItemData.KIND_FUEL: 1,
	ItemData.KIND_MEDICINE: 1,
}
## NPC 交付物资后瞬移到停机坪等候的位置（直升机旁）。
const PILOT_PAD_POSITION := Vector2(1420, 380)
## 重型变异体（Boss）在交付物资后出现的位置（停机坪东南角）。
const BOSS_SPAWN_POSITION := Vector2(1490, 450)
const BRUTE_VARIANT_PATH := "res://data/variants/brute.tres"

## —— 地图标记（配合迷雾）——
## 三态：未知（地图上不显示）→ 已发现（靠近/情报解锁，地图画名称）→ 已探索（进过建筑，加 ✓）。
const MARKER_UNKNOWN := 0
const MARKER_FOUND := 1
const MARKER_EXPLORED := 2
## "路过即发现"的半径（像素）。
const MARKER_DISCOVER_RADIUS := 420.0
## 可标注的建筑清单（id 与 ThoughtSystem 的建筑 id 保持一致）。
const MAP_BUILDINGS: Array = [
	{"id": "camp", "name": "安全屋", "color": Color(0.55, 0.85, 0.55),
			"rect": Rect2(60, 1080, 700, 400), "start_found": true},
	{"id": "market", "name": "惠民超市", "color": Color(0.95, 0.8, 0.4),
			"rect": Rect2(1660, 820, 480, 360), "start_found": false},
	{"id": "police", "name": "市公安局", "color": Color(0.5, 0.7, 0.95),
			"rect": Rect2(1180, 760, 440, 280), "start_found": false},
	{"id": "hospital", "name": "仁爱医院", "color": Color(0.95, 0.95, 0.95),
			"rect": Rect2(1560, 140, 440, 320), "start_found": false},
	{"id": "hardware", "name": "废铁五金店", "color": Color(0.9, 0.6, 0.3),
			"rect": Rect2(1940, 1200, 440, 280), "start_found": false},
	{"id": "military", "name": "城北军营", "color": Color(0.85, 0.35, 0.35),
			"rect": Rect2(1040, 150, 480, 360), "start_found": false},
]
## 标记发现检查间隔（秒）。
const MARKER_CHECK_INTERVAL := 0.4

var quest_stage := STAGE_NONE
## 任务管理模块：接取/目标进度/追踪状态的唯一数据源（HUD 只是展示）。
var _quests: QuestManager
## 地点标记状态：id -> MARKER_*（随存档保留）。
var map_markers := {}

var _hit_stopping := false
var _marker_accum := 0.0

@onready var _player: Player = $Player
@onready var _camp: CampStorage = $CampArea
@onready var _door: Door = $Door
@onready var _hud: Hud = $HUD
@onready var _spawn_point: Marker2D = $SpawnPoint
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _day_night: DayNight = $DayNight
@onready var _bed: Bed = $Bed
@onready var _sofa: Sofa = $Sofa
@onready var _workbench: Workbench = $Workbench
@onready var _thoughts: ThoughtSystem = $ThoughtSystem
@onready var _radio: Radio = $Radio
@onready var _pilot: SurvivorNpc = $Pilot
@onready var _fog: FogOfWar = $FogOfWar


func _ready() -> void:
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera != null:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = map_size.x
		camera.limit_bottom = map_size.y
	_hud.bind(_player, _camp)
	_hud.menu_backend = self
	for node in _spawn_points.get_children():
		if node is SpawnPoint:
			node.spawn(zombie_density, loot_density)
	# 家具容器（衣柜/冰箱/厨房柜子）与生成点刷出的箱子统一注册到 HUD；
	# 营地仓库已在 bind() 时单独接入。
	for node in get_tree().get_nodes_in_group("containers"):
		if node is ContainerBase:
			_hud.attach_container(node)
	_sofa.day_night = _day_night
	_hud.attach_sofa(_sofa)
	_hud.attach_workbench(_workbench)
	# 撤离任务：收音机播广播、飞行员 NPC 对话、HUD"交付物资"按钮
	_radio.broadcast_heard.connect(_on_radio_broadcast)
	_pilot.talk_requested.connect(_on_pilot_talk)
	_hud.npc_deliver_pressed.connect(_on_deliver_pressed)
	# 任务管理：撤离主线。目标文本里的物资进度随背包变化实时刷新。
	_quests = QuestManager.new()
	_quests.name = "QuestManager"
	add_child(_quests)
	_quests.define_quest("evacuate", "撤离计划", [
		{"id": "radio", "text": "收听收音机广播，找到撤离线索"},
		{"id": "pilot", "text": "见到飞行员老周，接到物资清单"},
		{"id": "supplies", "text": "收集物资：食物×2 · 水×2 · 汽油×1 · 医疗物资×1"},
	])
	_hud.attach_quests(_quests)
	_player.inventory_changed.connect(_refresh_supply_objective)
	_day_night.setup($DayNightModulate)
	_day_night.day_started.connect(_on_day_started)
	_day_night.night_started.connect(_on_night_started)
	_hud.attach_day_night(_day_night)
	_bed.day_night = _day_night
	_player.died.connect(_on_player_died)
	_player.notify.connect(_hud.show_message)
	# 内心独白引导系统：传入特殊建筑位置（画面中心，与墙体节点无关）
	var thought_buildings: Array = [
		{"id": "market", "name": "惠民超市", "pos": Vector2(1900, 1000)},
		{"id": "police", "name": "市公安局", "pos": Vector2(1400, 900)},
		{"id": "hospital", "name": "仁爱医院", "pos": Vector2(1780, 300)},
		{"id": "hardware", "name": "五金店", "pos": Vector2(2160, 1340)},
		{"id": "military", "name": "城北军营", "pos": Vector2(1280, 330)},
	]
	_thoughts.setup(_player, _camp, _day_night, _hud, thought_buildings)
	# 地图迷雾与地点标记：安全屋开局已知，其余靠探索/情报解锁
	for b in MAP_BUILDINGS:
		map_markers[b.id] = MARKER_FOUND if b.start_found else MARKER_UNKNOWN
	_fog.setup(_player)
	_player.intel_found.connect(_on_intel_found)
	_hud.attach_map(_fog, MAP_BUILDINGS, map_markers, _player)
	_setup_navigation()
	if OS.is_debug_build():  # 测试专用调试键（F1-F5），Release 导出自动移除
		add_child(preload("res://scripts/systems/debug_cheats.gd").new())


## 烘焙丧尸寻路用的导航网格：用地图边界做可通行外轮廓，解析主场景下所有
## 静态障碍（墙体/家具；门体临时禁用——门洞要在网格里保持可通行，关门时
## 由物理碰撞直接挡住丧尸），一次性同步烘焙。之后丧尸追击/调查沿导航路径
## 移动，会绕过墙体从门口进来，不再贴墙打转。
func _setup_navigation() -> void:
	var gates: Array = get_tree().get_nodes_in_group("gate")
	for gate in gates:  # 烘焙期间临时禁用门体，让门洞保持可通行
		(gate as Door).set_nav_parse_mode(true)
	var polygon := NavigationPolygon.new()
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.agent_radius = 10.0
	var data := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(polygon, data, self)
	# 注意：解析会先清空数据，可通行外轮廓必须在解析之后补加
	data.add_traversable_outline(PackedVector2Array([
		Vector2(0, 0), Vector2(map_size.x, 0),
		Vector2(map_size.x, map_size.y), Vector2(0, map_size.y),
	]))
	NavigationServer2D.bake_from_source_geometry_data(polygon, data)
	for gate in gates:  # 按各自的开关状态恢复门体
		(gate as Door).set_nav_parse_mode(false)
	var region := NavigationRegion2D.new()
	region.navigation_polygon = polygon
	add_child(region)


func _process(delta: float) -> void:
	_marker_accum -= delta
	if _marker_accum <= 0.0:
		_marker_accum = MARKER_CHECK_INTERVAL
		_update_map_markers()


## 地点标记推进：路过即发现；进入建筑算已探索。
func _update_map_markers() -> void:
	if _player == null:
		return
	for b in MAP_BUILDINGS:
		var rect: Rect2 = b.rect
		var state := int(map_markers.get(b.id, MARKER_UNKNOWN))
		if state == MARKER_UNKNOWN \
				and _player.global_position.distance_to(rect.get_center()) \
						<= MARKER_DISCOVER_RADIUS:
			map_markers[b.id] = MARKER_FOUND
			_hud.show_message("发现了「%s」——按 M 查看地图" % b.name)
		elif state == MARKER_FOUND and rect.has_point(_player.global_position):
			map_markers[b.id] = MARKER_EXPLORED
			_hud.show_message("探索了「%s」" % b.name)


## 情报解锁（收音机/纸条）：把未知地点标为已发现，并在迷雾上照亮一小片。
func discover_marker(id: String) -> void:
	if int(map_markers.get(id, MARKER_UNKNOWN)) != MARKER_UNKNOWN:
		return
	map_markers[id] = MARKER_FOUND
	for b in MAP_BUILDINGS:
		if b.id == id:
			_fog.reveal_area((b.rect as Rect2).get_center(), 320.0)
			_hud.show_message("地图上标记了「%s」——按 M 查看" % b.name)
			return


## 纸条阅读：解锁纸条指向的地点。
func _on_intel_found(reveals: String) -> void:
	if reveals == "":
		return
	var was_unknown := int(map_markers.get(reveals, MARKER_UNKNOWN)) == MARKER_UNKNOWN
	discover_marker(reveals)
	if was_unknown:
		_hud.show_thought("纸条上写着地址……多一条线索就多一条活路。",
				"按 M 打开地图查看新标记的地点。")


func _on_night_started(day: int) -> void:
	_hud.show_message("第 %d 天的夜晚降临了……僵尸在黑暗中更危险" % day, 3.0)
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Zombie:
			node.set_night_buffed(true)


func _on_day_started(day: int) -> void:
	_hud.show_message("你迎来了第 %d 天的清晨" % day, 3.0)
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Zombie:
			node.set_night_buffed(false)


## —— 撤离任务 ——————————————————————————————————————

## 收音机：第一次收听开启任务，之后只重播内容。
func _on_radio_broadcast() -> void:
	_hud.show_message("收音机：%s" % _radio.broadcast_text, 6.0)
	# 广播本身就是情报：解锁军营的地图标记
	discover_marker("military")
	if quest_stage == STAGE_NONE:
		quest_stage = STAGE_RADIO
		# 任务接取与追踪是两个独立状态：教学主线默认追踪（只占 1 个槽位）
		_quests.accept("evacuate", true)
		_quests.set_objective_done("evacuate", "radio")
		_hud.show_thought("广播是真的……城北有个军营，还有个会开飞机的活人。",
				"军营在地图北边。带上武器去找那个幸存者。")


## 飞行员 NPC：按任务阶段说话；在停机坪（已交付）触发结局。
func _on_pilot_talk() -> void:
	match quest_stage:
		STAGE_NONE:
			_hud.show_npc_dialogue("飞行员 老周",
					"……你是活人？别靠太近，我还剩半格子弹。\n\n"
					+ "我不跟陌生人走。除非你能证明外面还有秩序——"
					+ "[color=#c8b06a]军方的频道在循环播报[/color]，找到台能响的收音机再说。",
					false)
		STAGE_RADIO:
			quest_stage = STAGE_MET
			_quests.set_objective_done("evacuate", "pilot")
			_refresh_supply_objective()
			_hud.show_npc_dialogue("飞行员 老周",
					"你听到广播了？好。我就是那个开飞机的。\n\n"
					+ "油料见底、人也饿垮了。想让我带你飞出这座城，把清单备齐——\n\n"
					+ _supplies_bbcode() + "\n\n[color=#9fd89f]备齐了再来找我。[/color]",
					_has_all_supplies())
		STAGE_MET:
			if _has_all_supplies():
				_hud.show_npc_dialogue("飞行员 老周",
						"都齐了？验货。\n\n" + _supplies_bbcode()
						+ "\n\n[color=#9fd89f]点「交付物资」，我立刻去停机坪热车。[/color]",
						true)
			else:
				_hud.show_npc_dialogue("飞行员 老周",
						"还差着呢。\n\n" + _supplies_bbcode()
						+ "\n\n超市有吃的，军营油料区有油，医院有药。全城都是死人，慢慢找。",
						false)
		STAGE_SUPPLIED:
			_trigger_ending()
		STAGE_ESCAPED:
			_hud.show_npc_dialogue("飞行员 老周",
					"（直升机早已远去。这个世界的结局，已经写完了。）", false)


## HUD「交付物资」按钮：验收、扣料、把老周挪到停机坪。
func _on_deliver_pressed() -> void:
	if quest_stage != STAGE_MET or not _has_all_supplies():
		return
	for kind in SUPPLY_REQUIREMENTS:
		_consume_kind(kind, int(SUPPLY_REQUIREMENTS[kind]))
	quest_stage = STAGE_SUPPLIED
	_quests.set_objective_done("evacuate", "supplies")
	_pilot.global_position = PILOT_PAD_POSITION
	_spawn_boss()
	_hud.show_npc_dialogue("飞行员 老周",
			"好东西，全齐了！\n\n我去停机坪热车。[color=#c8b06a]最后一程你自己杀出去"
			+ "——院子里那群东西会闻着动静过来。[/color]\n\n到飞机旁边找我。", false)
	_hud.show_thought("最后一程了。把武器备好，从院子里杀出去。", "")


## 交付后刷新 Boss：停机坪与老周之间的重型变异体，撤离前的最后一战。
## 场上已有或已刷过（存档恢复）就不重复刷。
func _spawn_boss() -> void:
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Brute:
			return
	var boss := BRUTE_SCENE.instantiate() as Brute
	boss.variant = load(BRUTE_VARIANT_PATH) as ZombieVariant
	add_child(boss)
	boss.global_position = BOSS_SPAWN_POSITION
	_hud.show_message("警告：一只重型变异体堵住了停机坪！", 4.0)
	_hud.show_thought("那家伙挡在飞机前面……看准它的前摇再走位。",
			"重击和冲撞都有前摇，侧移躲开；实在不行用手雷。")


## 触发结局：记录阶段并弹出结局面板。
func _trigger_ending() -> void:
	if quest_stage == STAGE_ESCAPED:
		return
	quest_stage = STAGE_ESCAPED
	_quests.complete_quest("evacuate")  # 完成即释放追踪槽位
	_hud.show_ending(_day_night.day_number)


## 背包内某类物品的总数量（跨具体物品，如任意医疗物资）。
func _count_kind(kind: String) -> int:
	var total := 0
	for i in _player.inventory.slots.size():
		var item := _player.inventory.slots[i]
		if item != null and item.kind == kind:
			total += _player.inventory.count_at(i)
	return total


## 扣除某类物品 amount 个（跨具体物品）；不足时不动背包并返回 false。
func _consume_kind(kind: String, amount: int) -> bool:
	if _count_kind(kind) < amount:
		return false
	var remaining := amount
	var inv := _player.inventory
	for i in range(inv.slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var item := inv.slots[i]
		if item == null or item.kind != kind:
			continue
		var take := mini(inv.count_at(i), remaining)
		for j in take:
			inv.remove_item(i)
		remaining -= take
	return true


func _has_all_supplies() -> bool:
	for kind in SUPPLY_REQUIREMENTS:
		if _count_kind(kind) < int(SUPPLY_REQUIREMENTS[kind]):
			return false
	return true


## 物资清单 bbcode：够的绿色、缺的红色。
func _supplies_bbcode() -> String:
	var names := {
		ItemData.KIND_FOOD: "食物", ItemData.KIND_WATER: "水",
		ItemData.KIND_FUEL: "汽油", ItemData.KIND_MEDICINE: "医疗物资",
	}
	var lines: Array[String] = []
	for kind in SUPPLY_REQUIREMENTS:
		var need := int(SUPPLY_REQUIREMENTS[kind])
		var have := _count_kind(kind)
		var color := "#9fd89f" if have >= need else "#e08a8a"
		lines.append("[color=%s]%s ×%d（已有 %d）[/color]" % [color, names[kind], need, have])
	return "\n".join(lines)


## 物资目标进度文本（纯文本，供任务追踪 HUD/列表显示）；背包变化时自动刷新。
func _refresh_supply_objective() -> void:
	if not _quests.is_accepted("evacuate") or _quests.is_completed("evacuate"):
		return
	var names := {
		ItemData.KIND_FOOD: "食物", ItemData.KIND_WATER: "水",
		ItemData.KIND_FUEL: "汽油", ItemData.KIND_MEDICINE: "医疗物资",
	}
	var parts: Array[String] = []
	for kind in SUPPLY_REQUIREMENTS:
		var need := int(SUPPLY_REQUIREMENTS[kind])
		parts.append("%s %d/%d" % [names[kind], mini(_count_kind(kind), need), need])
	_quests.set_objective_text("evacuate", "supplies",
			"收集物资：" + " · ".join(parts))


## 命中顿帧：命中瞬间全局时间短暂减速，随后恢复。
## 使用 ignore_time_scale 的计时器恢复，保证不会被自己卡住。
func hit_stop() -> void:
	if _hit_stopping:
		return
	_hit_stopping = true
	Engine.time_scale = hit_stop_time_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stopping = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game()
	elif event.is_action_pressed("load_game"):
		load_game()


## 存档：天数/昼夜、玩家（状态+背包+装备+位置）、营地仓库、
## 以及整个可见世界——僵尸（变体/血量/位置）、地上物资、箱子内容。
## 这样读档后世界与存档时一致，而不是"只恢复了状态条"。
func save_game() -> void:
	var zombies: Array = []
	for node in get_tree().get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z == null:
			continue
		zombies.append({
			"v": z.variant.resource_path if z.variant != null else "",
			"x": z.global_position.x,
			"y": z.global_position.y,
			"hp": z.health,
		})
	var pickups: Array = []
	for node in get_tree().get_nodes_in_group("pickups"):
		var item := node.get("item") as ItemData
		if item == null or item.resource_path == "":
			continue
		pickups.append({
			"item": item.resource_path,
			"x": node.global_position.x,
			"y": node.global_position.y,
		})
	var boxes: Array = []
	for node in get_tree().get_nodes_in_group("containers"):
		var box := node as ContainerBase
		if box == null:
			continue
		boxes.append(box.storage.to_save_list())
	var data := {
		"day_number": _day_night.day_number,
		"is_night": _day_night.is_night,
		"phase_left": _day_night._phase_left,
		"gate_closed": _door.closed,
		"player": _player.get_save_data(),
		"player_pos": [_player.global_position.x, _player.global_position.y],
		"camp": _camp.storage.to_save_list(),
		"zombies": zombies,
		"pickups": pickups,
		"boxes": boxes,
		"thoughts": _thoughts.get_save_data(),
		"quest_stage": quest_stage,
		"quest_tracked": _quests.get_save_data(),
		"map_markers": map_markers,
		"fog": _fog.get_save_data(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_hud.show_message("存档失败", 2.0)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	_hud.show_message("游戏已保存", 2.0)


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_hud.show_message("没有找到存档", 2.0)
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_hud.show_message("读档失败", 2.0)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_hud.show_message("存档已损坏", 2.0)
		return
	var data: Dictionary = parsed
	_player.load_save_data(data.get("player", {}))
	var pos: Array = data.get("player_pos", [])
	if pos.size() == 2:
		_player.global_position = Vector2(float(pos[0]), float(pos[1]))
	_camp.storage.load_save_list(data.get("camp", []))
	_day_night.restore(int(data.get("day_number", 1)), bool(data.get("is_night", false)),
			float(data.get("phase_left", 1.0)))
	_door.set_closed(bool(data.get("gate_closed", true)))
	_thoughts.load_save_data(data.get("thoughts", {}))
	quest_stage = str(data.get("quest_stage", STAGE_NONE))
	# 任务目标状态以 quest_stage 为唯一事实来源重建；追踪集合随存档恢复
	_sync_quest_from_stage()
	_quests.load_save_data(data.get("quest_tracked", {}))
	# 迷雾探索进度与地点标记随存档恢复
	var markers_data: Dictionary = data.get("map_markers", {})
	for id in markers_data:
		map_markers[id] = int(markers_data[id])
	_fog.load_save_data(str(data.get("fog", "")))
	# 已交付物资的档：老周应站在停机坪（他瞬移过的位置不随普通存档保存），
	# 且 Boss 需要守在撤离路线上（场景随存档保存，读档后补刷兜底）
	if quest_stage == STAGE_SUPPLIED or quest_stage == STAGE_ESCAPED:
		_pilot.global_position = PILOT_PAD_POSITION
	if quest_stage == STAGE_SUPPLIED:
		_spawn_boss()
	_restore_world(data)
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Zombie:
			node.set_night_buffed(_day_night.is_night)
	_hud.refresh_day_label(_day_night.day_number)
	_hud.show_message("已读取存档", 2.0)


## 读档后按 quest_stage 重建任务接取/目标状态（quest_stage 是任务进度的
## 唯一事实来源，QuestManager 的目标只是它的展示投影）。
func _sync_quest_from_stage() -> void:
	if quest_stage == STAGE_NONE:
		return
	if not _quests.is_accepted("evacuate"):
		_quests.accept("evacuate", false)  # 追踪集合随后由存档数据恢复
	if quest_stage != STAGE_NONE:
		_quests.set_objective_done("evacuate", "radio")
	if quest_stage != STAGE_NONE and quest_stage != STAGE_RADIO:
		_quests.set_objective_done("evacuate", "pilot")
	if quest_stage == STAGE_SUPPLIED or quest_stage == STAGE_ESCAPED:
		_quests.set_objective_done("evacuate", "supplies")
	if quest_stage == STAGE_ESCAPED:
		_quests.complete_quest("evacuate")
	_refresh_supply_objective()


## 读档还原世界：清掉现存僵尸与地上物资，按存档重建；箱子内容按顺序覆盖。
## 分组顺序由场景树决定（生成点固定顺序），原型阶段视为稳定。
func _restore_world(data: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("zombies"):
		node.get_parent().remove_child(node)
		node.queue_free()
	for entry in data.get("zombies", []):
		var variant_path := str(entry.get("v", ""))
		# Boss 用自己的场景重建（脚本行为不同：蓄力/冲撞），普通僵尸照旧
		var is_brute := "brute" in variant_path
		var zombie := (BRUTE_SCENE if is_brute else ZOMBIE_SCENE).instantiate() as Zombie
		if variant_path != "":
			zombie.variant = load(variant_path) as ZombieVariant
		add_child(zombie)
		zombie.global_position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		zombie.health = mini(int(entry.get("hp", zombie.max_health)), zombie.max_health)
	for node in get_tree().get_nodes_in_group("pickups"):
		node.get_parent().remove_child(node)
		node.queue_free()
	for entry in data.get("pickups", []):
		var item_path := str(entry.get("item", ""))
		if item_path == "":
			continue
		var item: Variant = load(item_path)
		if not (item is ItemData):
			continue
		var pickup := PICKUP_SCENE.instantiate()
		pickup.item = item
		add_child(pickup)
		pickup.global_position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
	var box_nodes := get_tree().get_nodes_in_group("containers")
	var box_data: Array = data.get("boxes", [])
	for i in mini(box_nodes.size(), box_data.size()):
		var box := box_nodes[i] as ContainerBase
		if box == null:
			continue
		box.storage.load_save_list(box_data[i])


## 死亡 = 重生回营地：血量回满，背包物资保留（DESIGN.md 已确定）。
func _on_player_died() -> void:
	_player.global_position = _spawn_point.global_position
	_player.revive()
	_evict_zombies_from_camp()
	_hud.show_message("你倒下了，已在营地醒来", 2.5)


## 安全区重生清理：把屋内残留的僵尸清到屋外，保证玩家重生点周围干净。
## 依次尝试四个朝向（优先远离屋子的方向），取第一个落在地图内
## 且不在屋子里的落点——避免把僵尸传送到地图边界外卡死。
func _evict_zombies_from_camp() -> void:
	var escape := 500.0
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not _camp.has_point(zombie.global_position):
			continue
		var out_dir: Vector2 = zombie.global_position - _camp.global_position
		out_dir = out_dir.normalized() if out_dir.length() > 0.01 else Vector2.RIGHT
		var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
		dirs.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.dot(out_dir) > b.dot(out_dir))
		for dir in dirs:
			var target := _camp.global_position + dir * escape
			if target.x > 60.0 and target.x < map_size.x - 60.0 \
					and target.y > 60.0 and target.y < map_size.y - 60.0 \
					and not _camp.has_point(target):
				zombie.global_position = target
				break
