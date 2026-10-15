extends SceneTree
## 冒烟测试：headless 验证核心循环的关键行为。
## 运行：Godot_console.exe --headless --path <项目> -s tools/smoke_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	_test_inventory()

	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var player: Player = main.get_node("Player")
	var spawn: Marker2D = main.get_node("SpawnPoint")

	# 前半段大量断言按刷点位置统计丧尸（建筑守卫等）：先冻结自主游荡，
	# 防止游荡漂移造成随机失败；感知段之前的守卫断言结束后恢复。
	var wander_frozen: Array[Zombie] = []
	for node in get_nodes_in_group("zombies"):
		var fz := node as Zombie
		if fz.can_wander:
			wander_frozen.append(fz)
			fz.can_wander = false
	for node in get_nodes_in_group("zombies"):  # 测试定身语义：失明的不解冻
		if node.detect_radius <= 0:
			wander_frozen.erase(node)

	_check(player.inventory.capacity == 8, "玩家初始背包 8 格")
	_check(player.health == 65.0, "带伤开局（生命 65，不是满血）")
	_check(absf(player.food - 54.0) < 1.0, "初始饱食度 54（3 分钟量）")
	_check(absf(player.water - 50.0) < 5.0 and player.water < player.food,
			"初始饮水 50 比饱食更紧")
	_check(player.food_drain_per_sec == 0.3 and player.water_drain_per_sec == 0.5,
			"消耗速率 ×3（食物 0.3 / 水 0.5 每秒）")

	# —— 武器分级：tier 数据、伤害回归保护、初始木棒 ——
	var expected_tiers := {
		"weapon_wood_club": 1, "weapon_kitchen_knife": 1,
		"weapon_fruit_knife": 1, "weapon_wood_spear": 1,
		"weapon_pipe": 2, "weapon_shovel": 2,
		"weapon_baton": 2, "weapon_combat_dagger": 2,
		"weapon_machete": 3, "weapon_army_saber": 3, "weapon_metal_spear": 3,
		"weapon_fire_axe": 4, "weapon_mod_spear": 4,
		"weapon_pistol": 4, "weapon_rifle": 4,
	}
	var tiers_ok := true
	for wid in expected_tiers:
		var w: ItemData = load("res://data/items/%s.tres" % wid)
		if w.tier != int(expected_tiers[wid]):
			tiers_ok = false
	_check(tiers_ok, "全部武器 tier 与分级表一致（16 件）")
	var grenade_item: ItemData = load("res://data/items/weapon_grenade.tres")
	_check(grenade_item.tier == 0, "手雷不参与武器分级")
	_check((load("res://data/items/weapon_wood_club.tres") as ItemData).damage == 7
			and (load("res://data/items/weapon_army_saber.tres") as ItemData).damage == 25
			and (load("res://data/items/weapon_fire_axe.tres") as ItemData).damage == 26,
			"分级未改动任何伤害数值（木棒7/军刀25/消防斧26）")
	var melee_tier_max_ok := true  # 每级近战伤害上限不低于低级（改装矛23 vs 军刀25 允许，见表）
	var tier_max_damage := {}
	for wid in expected_tiers:
		var w3: ItemData = load("res://data/items/%s.tres" % wid)
		if w3.kind != ItemData.KIND_WEAPON:
			continue
		tier_max_damage[w3.tier] = maxi(int(tier_max_damage.get(w3.tier, 0)), w3.damage)
	var tier_keys := tier_max_damage.keys()
	tier_keys.sort()
	for i in range(1, tier_keys.size()):
		if int(tier_max_damage[tier_keys[i - 1]]) > int(tier_max_damage[tier_keys[i]]):
			melee_tier_max_ok = false
	_check(melee_tier_max_ok, "近战每级伤害上限随等级递增（8→14→25→26）")
	var starter_club: ItemData = load("res://data/items/weapon_wood_club.tres")
	_check(starter_club.display_name_tiered() == "木棒（破烂）", "显示名带分级后缀")
	var hand_item: ItemData = player.equipped.get(ItemData.SLOT_HAND_R)
	_check(hand_item != null and hand_item.id == "weapon_wood_club" and hand_item.tier == 1,
			"开局手持木棒（1 级破烂）")
	_check(get_nodes_in_group("zombies").size() > 0, "生成系统刷出了僵尸")
	_check(get_nodes_in_group("pickups").is_empty(), "室外无散落物资（搜刮只在建筑内）")
	_check(get_nodes_in_group("containers").size() > 0, "生成系统刷出了物资箱")

	var loot_table: LootTable = load("res://data/loot/rich_table.tres")
	var all_valid := true
	for i in 50:
		if loot_table.pick() == null:
			all_valid = false
	_check(all_valid, "掉落表 50 次抽取全部有效")

	var zscene := load("res://scenes/enemies/Zombie.tscn") as PackedScene
	var runner: Zombie = zscene.instantiate()
	runner.variant = load("res://data/variants/runner.tres")
	main.add_child(runner)
	runner.global_position = Vector2(-600, -600)
	_check(runner.health == 30 and runner.move_speed == 150.0, "迅捷丧尸变体参数正确应用")
	runner.take_damage(30)
	await physics_frame
	_check(not is_instance_valid(runner), "迅捷丧尸 30 血一击即死")

	var sp := SpawnPoint.new()
	sp.variants = [null, load("res://data/variants/runner.tres")]
	sp.variant_weights = [1.0, 0.0]
	var all_normal := true
	for i in 20:
		if sp._pick_variant() != null:
			all_normal = false
	_check(all_normal, "变体权重为 0 时不会被抽中")
	sp.free()

	var variant_stats_ok := true
	for node in get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z.variant != null and z.health != z.variant.max_health:
			variant_stats_ok = false
	_check(variant_stats_ok, "场上变体僵尸的参数与配置一致")

	# 室外已无散落物资：自建一个地上物品，专门测拾取交互本身
	var pickup_scene := load("res://scenes/items/ItemPickup.tscn") as PackedScene
	var food_pickup: Node2D = pickup_scene.instantiate()
	food_pickup.item = load("res://data/items/food_canned.tres") as ItemData
	main.add_child(food_pickup)
	food_pickup.global_position = player.global_position + Vector2(40, 0)
	var inv_before_pickup := player.inventory.item_count()
	player.global_position = food_pickup.global_position
	for i in 8:
		await physics_frame
	_check(player.inventory.item_count() == inv_before_pickup, "物资不再自动拾取")
	var near := player.nearest_interactable()
	_check(near != null and near.is_in_group("pickups"), "靠近物资出现拾取交互")
	near.interact(player)
	_check(player.inventory.item_count() == inv_before_pickup + 1, "E 拾取物资进背包")
	await physics_frame
	_check(not is_instance_valid(near), "拾取后地上物资消失")

	player.food = 0.0
	var health_before := player.health
	for i in 90:
		await physics_frame
	_check(player.health < health_before, "断粮后血量持续下降")

	var zombie: Zombie = get_first_node_in_group("zombies")
	health_before = player.health
	player.global_position = zombie.global_position + Vector2(34, 0)
	for i in 40:
		await physics_frame
	_check(player.health < health_before, "贴近僵尸会被攻击")

	zombie.take_damage(50)
	for i in 3:
		await physics_frame
	_check(not is_instance_valid(zombie), "僵尸血量归零后消失")

	player.food = 100.0
	player.water = 100.0
	player.inventory.clear()
	player.inventory.add_item(load("res://data/items/food_canned.tres") as ItemData)
	var pickups_before_death := get_nodes_in_group("pickups").size()
	player.take_damage(999)
	await physics_frame
	_check(not player.dead, "死亡后立即重生")
	_check(player.global_position.distance_to(spawn.global_position) < 2.0, "重生位置在营地")
	_check(player.health == 100.0, "重生后血量回满")
	for i in 5:
		await physics_frame
	var no_zombie_in_camp := true
	var camp_area: Area2D = main.get_node("CampArea")
	for node in get_nodes_in_group("zombies"):
		if camp_area.has_point((node as Node2D).global_position):
			no_zombie_in_camp = false
	_check(no_zombie_in_camp, "营地内没有僵尸停留（安全区）")
	_check(get_nodes_in_group("pickups").size() == pickups_before_death + 2,
			"死亡掉落随身物品（1 罐头 + 开局手持的木棒）")
	_check(player.inventory.item_count() == 0, "死亡后背包清空")

	var camp: CampStorage = main.get_node("CampArea")
	_check(camp.half_size == Vector2(350, 200), "安全区覆盖整个屋子（客厅/厨房/卧室/厕所）")
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == camp, "营地内探测到可交互的仓库")
	camp.interact(player)
	_check(camp.open, "E 交互打开仓库")
	camp.interact(player)
	_check(not camp.open, "再次交互关闭仓库")

	player.food = 100.0
	player.water = 100.0
	player.health = 60.0
	player.regen_interval = 0.5
	for i in 60:
		await physics_frame
	_check(player.health > 60.0, "生命值随时间自然恢复")
	player.regen_interval = 10.0

	var bed: Interactable = main.get_node("Bed")
	var hud_bed: Hud = main.get_node("HUD")
	var sleep_panel: PanelContainer = hud_bed.get_node("Root/SleepPanel")
	player.health = 50.0
	player.global_position = bed.global_position
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == bed, "靠近床可探测到睡觉交互")
	bed.interact(player)
	_check(sleep_panel.visible, "床交互弹出睡眠菜单（不再直接回血）")
	hud_bed.close_sleep_menu()

	# 昼夜循环与天数
	var day_night: DayNight = main.get_node("DayNight")
	_check(day_night.day_number == 1 and not day_night.is_night, "开局第 1 天白天")
	var z2 := get_first_node_in_group("zombies") as Zombie
	var detect_before := z2.detect_radius
	day_night.force_night(true)
	for i in 3:
		await physics_frame
	_check(day_night.is_night, "进入夜晚")
	_check(z2.detect_radius > detect_before, "夜晚僵尸视野被强化")
	day_night.skip_to_morning()
	_check(day_night.day_number == 2 and not day_night.is_night, "迎来第 2 天清晨")
	_check(z2.detect_radius == detect_before, "白天僵尸强化解除")

	# —— 睡眠结算：按游戏小时推进时间、降疲劳、回精力；保留 20% 回血 ——
	bed.cooldown_seconds = 30.0
	bed._cooldown_left = 0.0
	player.health = 50.0
	player.food = 100.0  # 消耗 ×3 后：睡眠期间水/粮耗尽会掉血，干扰回血断言，先回满
	player.water = 100.0
	day_night.skip_to_morning()  # 归位到白天清晨，方便断言时刻
	player.stamina.set_fatigue(60.0)
	var hour_before := day_night.hour_of_day()
	var day_before_sleep := day_night.day_number
	bed.interact(player)
	hud_bed._on_sleep_confirmed(4.0)
	_check(not sleep_panel.visible, "确认睡眠后菜单关闭")
	_check(player.health == 70.0, "睡眠结算恢复 20% 生命值（原床铺机制保留）")
	_check(absf(day_night.hour_of_day() - hour_before - 4.0) < 0.2
			and day_night.day_number == day_before_sleep,
			"睡眠推进游戏内时间 4 小时（白天内不跨天）")
	_check(absf(player.stamina.fatigue - 28.0) < 0.5, "4 小时睡眠降低疲劳 32（60→约 28）")
	_check(absf(player.stamina.stamina - player.stamina.max_stamina()) < 0.5,
			"睡醒精力回满（按动态上限）")
	bed.interact(player)
	_check(not sleep_panel.visible, "刚睡醒有冷却，不能连续睡")

	# 夜里睡觉按小时推进：8 小时从 20:00 睡到 04:00 仍是同一夜；再睡 2 小时跨到清晨
	bed._cooldown_left = 0.0
	player.health = 50.0
	player.food = 100.0
	player.water = 100.0
	day_night.force_night(true)
	var night_start_day := day_night.day_number
	bed.interact(player)
	hud_bed._on_sleep_confirmed(8.0)
	_check(day_night.is_night and day_night.day_number == night_start_day,
			"夜里睡 8 小时推进到凌晨（仍是同一夜）")
	_check(absf(player.health - 70.0) < 0.01, "夜里睡 8 小时恢复 20%% 生命值（50→70）")
	player.food = 100.0  # 8 小时睡眠又消耗了不少水，再回满防止下一段睡眠掉血
	player.water = 100.0
	bed.interact(player)
	hud_bed._on_sleep_confirmed(2.0)
	_check(not day_night.is_night and day_night.day_number == night_start_day + 1,
			"再睡 2 小时跨过清晨（天数 +1）")
	_check(absf(player.health - 90.0) < 0.01,
			"再睡 2 小时再次恢复 20%% 生命值（70→90）")

	# 门：E 开关 + 门控安全区
	var door: Door = main.get_node("Door")
	_check(door.closed and door.get_prompt() == "开门", "门初始关闭，提示开门")
	door.interact(player)
	_check(not door.closed and door.get_prompt() == "关门", "E 打开门")
	door.interact(player)
	_check(door.closed and door.get_prompt() == "开门", "再次 E 关上门")
	var door_watcher := get_first_node_in_group("zombies") as Zombie
	player.global_position = spawn.global_position  # 屋内
	door_watcher.global_position = door.global_position + Vector2(0, 100)  # 门外正对门洞，视野内
	for i in 5:
		await physics_frame
	var dist_sheltered := door_watcher.global_position.distance_to(player.global_position)
	for i in 40:
		await physics_frame
	_check(door_watcher.global_position.distance_to(player.global_position) >= dist_sheltered - 1.0,
			"门关着时僵尸不会追进安全屋")
	door.interact(player)  # 开门
	for i in 40:
		await physics_frame
	_check(door_watcher.global_position.distance_to(player.global_position) < dist_sheltered - 10.0,
			"门开后僵尸会追进屋")
	door.interact(player)  # 关门恢复

	# 本段玩家要多次传送到箱子/家具旁，而守卫刷点（军营/五金店）就在附近：
	# 丧尸随机刷在玩家传送点上时，物理推挤会把玩家挤出交互检测区，造成与本
	# 测试无关的随机失败。把丧尸失明并瞬移到图外（段末恢复原位与视野，不影
	# 响后面的建筑守卫位置断言——恢复与断言之间没有物理帧）。
	var zombie_sight: Dictionary = {}
	for node in get_nodes_in_group("zombies"):
		var z := node as Zombie
		zombie_sight[z] = [z.detect_radius, z.global_position]
		z.detect_radius = 0
		z.global_position = Vector2(5000, 5000)
	# 家具容器与超市货架都挂在固定节点下；测试用"物资箱"选军营南墙外的 Box1：
	# HardwareBox 刷点紧邻五金店货架（140×70 交互区，中心距刷点仅 80px），
	# 箱子偏东刷时玩家传送点与货架并列最近，货架会抢走 nearest 探测（随机失败源）；
	# Box1 周边 100px 内没有其他交互物，探测结果唯一。
	var box: StorageBox = null
	for node in get_nodes_in_group("containers"):
		var candidate := node as StorageBox
		if candidate != null and candidate.get_parent() is SpawnPoint \
				and (candidate.get_parent() as Node).name == "Box1":
			box = candidate
			break
	_check(box.storage.item_count() > 0, "箱子按掉落表携带物资")
	player.global_position = box.global_position + Vector2(30, 0)
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == box, "靠近箱子可探测到")
	box.interact(player)
	_check(box.open, "E 打开箱子")
	var inv_count := player.inventory.item_count()
	_check(box.withdraw(0, player.inventory) and player.inventory.item_count() == inv_count + 1,
			"从箱子取出物资进背包")
	box.interact(player)
	_check(not box.open, "再次交互关闭箱子")

	var pickups_before := get_nodes_in_group("pickups").size()
	var inv_before := player.inventory.item_count()
	player.drop_item(0)
	for i in 3:
		await physics_frame
	_check(player.inventory.item_count() == inv_before - 1, "丢弃后背包减少且不会被自动捡回")
	_check(get_nodes_in_group("pickups").size() == pickups_before + 1, "丢弃的物品出现在地上")

	# 屋内家具：衣柜 / 冰箱 / 厨房柜子（容器）、洗手台（装水）、沙发（休息 / 翻找）
	var wardrobe: ContainerBase = main.get_node("Wardrobe")
	var fridge: ContainerBase = main.get_node("Fridge")
	var cabinet: ContainerBase = main.get_node("KitchenCabinet")
	_check(wardrobe.storage.item_count() == 4, "衣柜里放着四件衣物")
	_check(fridge.storage.item_count() == 0, "安全屋冰箱不存粮（必须出门搜刮）")
	_check(cabinet.storage.item_count() == 0, "安全屋厨房柜不存粮（必须出门搜刮）")
	player.global_position = wardrobe.global_position + Vector2(0, 50)
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == wardrobe, "靠近衣柜可交互")
	var tshirt := load("res://data/items/cloth_tshirt.tres") as ItemData
	_check(tshirt.kind == ItemData.KIND_CLOTHING and tshirt.equip_slot == ItemData.SLOT_CHEST,
			"T恤是衣服部位的装备")

	var sink: Sink = main.get_node("Sink")
	var plastic := load("res://data/items/bottle_plastic.tres") as ItemData
	var bottled := load("res://data/items/water_bottle.tres") as ItemData
	player.inventory.clear()
	player.inventory.add_item(plastic)
	sink.interact(player)
	_check(player.inventory.slots.has(bottled) and not player.inventory.slots.has(plastic),
			"塑料瓶在洗手台装成瓶装水")
	sink.interact(player)
	_check(player.inventory.item_count() == 1, "没有塑料瓶时装不了水")
	player.inventory.clear()

	var sofa: Sofa = main.get_node("Sofa")
	player.global_position = sofa.global_position + Vector2(45, 0)
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == sofa, "靠近沙发可交互")
	sofa.interact(player)
	_check(main.get_node("HUD/Root/SofaPanel").visible, "按 E 弹出沙发选项面板")
	player.health = 50.0
	sofa.do_rest()
	_check(player.health == 55.0, "沙发休息恢复 5 点生命")
	sofa.do_search()
	_check(not sofa.can_search(), "沙发每天只能翻找一次")
	var hud_node: Hud = main.get_node("HUD")
	hud_node._on_sofa_menu_closed()
	_check(not main.get_node("HUD/Root/SofaPanel").visible, "离开沙发后选项面板自动关闭")

	# 家具/箱子段结束，恢复丧尸位置与视野
	for z in zombie_sight:
		z.detect_radius = zombie_sight[z][0]
		z.global_position = zombie_sight[z][1]

	# 超市：货架容器、守卫僵尸、南墙入口可通行
	var market: Node2D = main.get_node("Market")
	_check(market != null, "惠民超市存在于地图上")
	var shelf_count := 0
	var shelf_items := 0
	var some_shelf: StorageBox = null
	for node in get_nodes_in_group("containers"):
		var shelf := node as StorageBox
		if shelf != null and shelf.display_name == "货架" and shelf.get_parent() == market:
			shelf_count += 1
			shelf_items += shelf.storage.item_count()
			if some_shelf == null:
				some_shelf = shelf
	_check(shelf_count == 6 and shelf_items >= 18, "超市 6 排货架且初始铺满货")
	var market_guards := 0
	for node in get_nodes_in_group("zombies"):
		var guard := node as Zombie
		if guard.global_position.x > 1660.0 and guard.global_position.x < 2140.0 \
				and guard.global_position.y > 820.0 and guard.global_position.y < 1180.0:
			market_guards += 1
	_check(market_guards >= 2, "超市内有守卫僵尸")
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	var point_params := PhysicsPointQueryParameters2D.new()
	point_params.position = Vector2(1900, 1172)  # 南墙入口门洞中心
	var entrance_clear := true
	for hit in space.intersect_point(point_params):
		if hit.collider is StaticBody2D:
			entrance_clear = false
	_check(entrance_clear, "超市南墙入口可以通行")
	player.inventory.clear()
	player.global_position = some_shelf.global_position + Vector2(0, 30)
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == some_shelf, "靠近货架可搜刮")
	some_shelf.interact(player)
	_check(some_shelf.open, "E 打开货架")
	some_shelf.interact(player)
	_check(not some_shelf.open, "再次交互关闭货架")

	# 医院：药品回血、药房库存、守卫僵尸（含 1 只强壮）、入口通行
	var hospital: Node2D = main.get_node("Hospital")
	_check(hospital != null, "仁爱医院存在于地图上")
	var med_containers := 0
	var med_stock := 0
	for node in get_nodes_in_group("containers"):
		var med_box := node as StorageBox
		if med_box != null and (med_box.display_name == "药房货架"
				or med_box.display_name == "急救柜" or med_box.display_name == "床头柜"):
			med_containers += 1
			med_stock += med_box.storage.item_count()
	_check(med_containers == 4 and med_stock >= 8, "医院药房货架/急救柜/床头柜备有药品")
	var hosp_guards := 0
	for node in get_nodes_in_group("zombies"):
		var guard := node as Zombie
		if guard.global_position.x > 1560.0 and guard.global_position.x < 2000.0 \
				and guard.global_position.y > 140.0 and guard.global_position.y < 460.0:
			hosp_guards += 1
	_check(hosp_guards == 3, "医院内有 3 只守卫僵尸")
	var tank_in_pharmacy := false
	for node in get_nodes_in_group("zombies"):
		var tank := node as Zombie
		if tank.variant != null and tank.global_position.x > 1560.0 \
				and tank.global_position.x < 1780.0 and tank.global_position.y > 140.0 \
				and tank.global_position.y < 340.0:
			tank_in_pharmacy = true
	_check(tank_in_pharmacy, "药房由强壮丧尸看守")
	var hosp_params := PhysicsPointQueryParameters2D.new()
	hosp_params.position = Vector2(1780, 452)  # 南墙入口门洞中心
	var hosp_clear := true
	for hit in space.intersect_point(hosp_params):
		if hit.collider is StaticBody2D:
			hosp_clear = false
	_check(hosp_clear, "医院南墙入口可以通行")

	# 药品机制：绷带处理出血（附带少量回血）；没有可治疗的状态时不消耗
	var bandage := load("res://data/items/med_bandage.tres") as ItemData
	_check(bandage.kind == ItemData.KIND_MEDICINE and bandage.heal_amount == 15.0,
			"绷带是回复 15 点的药品")
	player.inventory.clear()
	player.inventory.add_item(bandage)
	player.health = 50.0
	player.use_item(player.inventory.slots.find(bandage))
	_check(player.inventory.slots.has(bandage),
			"没有出血时使用绷带不消耗（提示用途）")
	# 轻度出血：绷带止血 + 附带 15 点回血
	player.medical.injuries["bleed_minor"] = {"left": 600.0}
	player.use_item(player.inventory.slots.find(bandage))
	_check(not player.medical.injuries.has("bleed_minor"), "绷带止住轻度出血")
	_check(player.health == 65.0, "绷带止血时附带恢复 15 点生命")
	_check(not player.inventory.slots.has(bandage), "有效治疗后药品被消耗")
	# 严重出血：绷带只能降级为轻度（有限缓解）
	player.inventory.add_item(bandage)
	player.medical.injuries["bleed_severe"] = {}
	player.use_item(player.inventory.slots.find(bandage))
	_check(player.medical.injuries.has("bleed_minor")
			and not player.medical.injuries.has("bleed_severe"),
			"绷带对严重出血只降级为轻度（有限缓解）")
	player.inventory.clear()

	# 警察局：守卫、入口、枪柜物资
	var police: Node2D = main.get_node("PoliceStation")
	_check(police != null, "警察局存在于地图上")
	var police_guards := 0
	for node in get_nodes_in_group("zombies"):
		var pg := node as Zombie
		if pg.global_position.x > 1180.0 and pg.global_position.x < 1620.0 \
				and pg.global_position.y > 760.0 and pg.global_position.y < 1040.0:
			police_guards += 1
	_check(police_guards == 3, "警察局内有 3 只守卫僵尸")
	var police_params := PhysicsPointQueryParameters2D.new()
	police_params.position = Vector2(1400, 1040)  # 南墙入口门洞中心
	var police_clear := true
	for hit in space.intersect_point(police_params):
		if hit.collider is StaticBody2D:
			police_clear = false
	_check(police_clear, "警察局南墙入口可以通行")
	var gunlocker_stock := 0
	for node in get_nodes_in_group("containers"):
		if node.display_name == "枪柜":
			gunlocker_stock = node.storage.item_count()
	_check(gunlocker_stock == 5, "枪柜存有枪械、弹药与手雷")

	# 五金店：材料货架、守卫僵尸、入口、工具柜台与掉落表
	var hardware: Node2D = main.get_node("HardwareStore")
	_check(hardware != null, "五金店存在于地图上")
	var hw_shelves := 0
	var hw_stock := 0
	var hw_material_kinds := {}
	for node in get_nodes_in_group("containers"):
		var hw_shelf := node as StorageBox
		if hw_shelf != null and hw_shelf.get_parent() == hardware:
			hw_shelves += 1
			hw_stock += hw_shelf.storage.item_count()
			for item in hw_shelf.storage.slots:
				if item != null and item.kind == ItemData.KIND_MATERIAL:
					hw_material_kinds[item.id] = true
	_check(hw_shelves == 7, "五金店有 6 排货架 + 1 个工具柜台")
	_check(hw_stock >= 14, "五金店货架上备有物资")
	_check(hw_material_kinds.size() >= 6, "货架上有至少 6 种制作材料")
	var hw_guards := 0
	for node in get_nodes_in_group("zombies"):
		var hw_guard := node as Zombie
		if hw_guard.global_position.x > 1940.0 and hw_guard.global_position.x < 2380.0 \
				and hw_guard.global_position.y > 1200.0 and hw_guard.global_position.y < 1480.0:
			hw_guards += 1
	_check(hw_guards >= 2, "五金店内有守卫僵尸")
	var hw_params := PhysicsPointQueryParameters2D.new()
	hw_params.position = Vector2(2160, 1472)  # 南墙入口门洞中心
	var hw_clear := true
	for hit in space.intersect_point(hw_params):
		if hit.collider is StaticBody2D:
			hw_clear = false
	_check(hw_clear, "五金店南墙入口可以通行")
	var hw_table: LootTable = load("res://data/loot/hardware_table.tres")
	var hw_table_ok := true
	for i in 50:
		var rolled := hw_table.pick()
		if rolled == null:
			hw_table_ok = false
	_check(hw_table_ok, "五金掉落表 50 次抽取全部有效")

	# 枪械：装填、射击消耗弹药、直线命中、没弹药打不响
	var pistol := load("res://data/items/weapon_pistol.tres") as ItemData
	var ammo9 := load("res://data/items/ammo_pistol_box.tres") as ItemData
	var baton := load("res://data/items/weapon_baton.tres") as ItemData
	var fire_axe := load("res://data/items/weapon_fire_axe.tres") as ItemData
	_check(pistol.kind == ItemData.KIND_GUN and pistol.damage == 16
			and pistol.range_in_tiles() == 5 and pistol.two_handed,
			"手枪 16 伤害、5 格射程、双手")
	_check(baton.damage == 10 and baton.attack_cooldown == 0.3 and not baton.two_handed,
			"警棍 10 伤害、攻速 0.3、单手")
	_check(fire_axe.damage == 26 and fire_axe.two_handed
			and fire_axe.attack_cooldown == 0.7, "消防斧 26 伤害、双手、攻速 0.7")
	player.inventory.clear()
	player.inventory.add_item(pistol)
	player.use_item(player.inventory.slots.find(pistol))
	_check(player.current_weapon() == pistol, "手枪装备到手上")
	player.inventory.add_item(ammo9)
	player.use_item(player.inventory.slots.find(ammo9))
	_check(player.ammo_pistol == 15, "9mm 弹盒装填 15 发")
	# 挪到地图外空地，避免场上游荡僵尸干扰弹道
	player.global_position = Vector2(-800, -600)
	var gun_target: Zombie = zscene.instantiate()
	main.add_child(gun_target)
	gun_target.global_position = Vector2(-680, -600)
	await physics_frame
	var ammo_before := player.ammo_pistol
	player._attack_toward(Vector2.RIGHT)
	_check(player.ammo_pistol == ammo_before - 1, "射击消耗 1 发 9mm")
	_check(gun_target.health == 29, "手枪命中直线上的僵尸（45 → 29）")
	gun_target.queue_free()
	await physics_frame
	player.ammo_pistol = 0
	var dry: Zombie = zscene.instantiate()
	main.add_child(dry)
	dry.global_position = Vector2(-700, -600)
	await physics_frame
	player._attack_toward(Vector2.RIGHT)
	_check(dry.health == 45, "没有弹药时手枪无法射击")
	dry.queue_free()
	await physics_frame

	# 手雷：朝指定方向投掷，爆炸范围杀伤
	var grenade := load("res://data/items/weapon_grenade.tres") as ItemData
	player.inventory.add_item(grenade)
	var boom1: Zombie = zscene.instantiate()
	var boom2: Zombie = zscene.instantiate()
	main.add_child(boom1)
	main.add_child(boom2)
	boom1.global_position = Vector2(-600, -600)
	boom2.global_position = Vector2(-560, -600)
	boom1.detect_radius = 0  # 测试丧尸失明定身，排除感知/寻路对爆炸测试的干扰
	boom2.detect_radius = 0
	player.global_position = Vector2(-800, -600)
	for i in 3:
		await physics_frame
	player.use_item(player.inventory.slots.find(grenade), Vector2(210, 0))
	_check(not player.inventory.slots.has(grenade), "手雷投出后消耗")
	for i in 90:
		await physics_frame
	_check(not is_instance_valid(boom1) and not is_instance_valid(boom2),
			"手雷爆炸炸死范围内的僵尸")

	# 装备系统：双手武器占两手、匕首单手可双持、矛单体、护甲减伤、背包扩容、鞋子加速
	var machete := load("res://data/items/weapon_machete.tres") as ItemData
	var wood_spear := load("res://data/items/weapon_wood_spear.tres") as ItemData
	var saber := load("res://data/items/weapon_army_saber.tres") as ItemData
	var kitchen := load("res://data/items/weapon_kitchen_knife.tres") as ItemData
	var fruit := load("res://data/items/weapon_fruit_knife.tres") as ItemData
	_check(machete.damage == 17 and machete.two_handed, "砍刀 17 伤害、双手武器")
	_check(saber.damage == 25 and saber.two_handed, "军刀 25 伤害、双手武器")
	_check(wood_spear.damage == 5 and wood_spear.range_in_tiles() == 2 and wood_spear.single_target,
			"木矛 5 伤害、两格距离、只命中最近目标")
	_check(kitchen.damage == 5 and kitchen.attack_cooldown == 0.35 and not kitchen.two_handed,
			"菜刀 5 伤害、攻速 0.35 秒、单手")
	_check(fruit.damage == 8 and fruit.attack_cooldown == 0.35, "水果刀 8 伤害、攻速 0.35 秒")

	player.inventory.add_item(machete)
	player.use_item(player.inventory.slots.find(machete))
	_check(player.equipped.get(ItemData.SLOT_HAND_R) == machete
			and player.equipped.get(ItemData.SLOT_HAND_L) == machete, "双手武器占用左右手")
	_check(not player.inventory.slots.has(machete), "装备后武器离开背包")
	_check(player.current_damage() == 17 and player.current_attack_range() == 48.0,
			"砍刀攻击力 17、距离一格")

	player.inventory.add_item(wood_spear)
	player.use_item(player.inventory.slots.find(wood_spear))
	_check(player.equipped.get(ItemData.SLOT_HAND_R) == wood_spear
			and player.equipped.get(ItemData.SLOT_HAND_L) == wood_spear, "新双手武器替换旧武器")
	_check(player.inventory.slots.has(machete), "替换下的砍刀回到背包")
	_check(player.current_damage() == 5 and player.current_attack_range() == 96.0,
			"木矛攻击力 5、距离两格")

	player.inventory.add_item(saber)
	player.use_item(player.inventory.slots.find(saber))
	_check(player.current_damage() == 25 and player.current_attack_range() == 48.0,
			"军刀攻击力 25、距离一格")
	_check(player.current_attack_cooldown() == 0.45, "双手武器使用默认攻击冷却")

	player.inventory.add_item(kitchen)
	player.use_item(player.inventory.slots.find(kitchen))
	_check(player.equipped.get(ItemData.SLOT_HAND_R) == kitchen
			and player.equipped.get(ItemData.SLOT_HAND_L) == null, "匕首只占用一只手")
	_check(player.current_damage() == 5 and player.current_attack_cooldown() == 0.35,
			"菜刀攻击力 5、攻击冷却 0.35 秒")

	player.inventory.add_item(fruit)
	player.use_item(player.inventory.slots.find(fruit))
	_check(player.equipped.get(ItemData.SLOT_HAND_R) == fruit
			and player.equipped.get(ItemData.SLOT_HAND_L) == null, "新武器替换旧武器、不可双持")
	_check(player.inventory.slots.has(kitchen), "替换下的菜刀回到背包")
	_check(player.current_damage() == 8 and player.current_attack_cooldown() == 0.35,
			"水果刀攻击力 8、攻击冷却 0.35 秒")
	_check(player.unequip_slot(ItemData.SLOT_HAND_R), "可脱下单手武器")
	_check(player.equipped.get(ItemData.SLOT_HAND_R) == null, "脱下后右手为空")

	var jacket := load("res://data/items/cloth_jacket.tres") as ItemData
	player.inventory.add_item(jacket)
	player.use_item(player.inventory.slots.find(jacket))
	_check(player.equipped.get(ItemData.SLOT_CHEST) == jacket, "夹克装备到衣服部位")
	var hp_before := player.health
	player.take_damage(10)
	_check(player.health == hp_before - 9.0, "护甲 2 点按 10% 减伤（10 → 9）")

	var bp := load("res://data/items/backpack_small.tres") as ItemData
	player.inventory.add_item(bp)
	player.use_item(player.inventory.slots.find(bp))
	_check(player.inventory.capacity == player.base_slot_count + 4, "装备背包扩容 +4")

	var shoes := load("res://data/items/sport_shoes.tres") as ItemData
	player.inventory.add_item(shoes)
	player.use_item(player.inventory.slots.find(shoes))
	_check(player.equipped.get(ItemData.SLOT_FEET) == shoes, "鞋子装备到脚部")
	_check(player.current_move_speed() > player.move_speed, "鞋子提升移速")

	var filler := load("res://data/items/food_canned.tres") as ItemData
	while player.inventory.add_item(filler):
		pass
	_check(not player.unequip_slot(ItemData.SLOT_BACKPACK), "物品装满时无法脱下背包")
	_check(player.equipped.get(ItemData.SLOT_BACKPACK) == bp, "背包仍在装备栏")
	_check(not player.unequip_slot(ItemData.SLOT_FEET), "背包满时无法脱下其他装备")
	player.inventory.remove_item(0)
	_check(player.unequip_slot(ItemData.SLOT_FEET), "腾出空位后可脱下鞋子放回背包")

	# 材料与叠放
	var nails := load("res://data/items/mat_nails.tres") as ItemData
	var board := load("res://data/items/mat_wood_board.tres") as ItemData
	_check(nails.kind == ItemData.KIND_MATERIAL and nails.stack_size == 10,
			"钉子是可叠放 10 个的材料")
	player.inventory.clear()
	player.inventory.add_item(nails)
	player.inventory.add_item(nails)
	player.inventory.add_item(nails)
	_check(player.inventory.item_count() == 1 and player.inventory.count_at(0) == 3,
			"同 id 材料叠进同一格并计数")
	camp.storage.clear()
	camp.storage.add_item(nails)
	camp.storage.add_item(nails)
	_check(camp.storage.item_count() == 1 and camp.storage.count_at(0) == 2, "材料存入营地仓库同样叠放")
	var stack_snapshot := camp.storage.to_save_list()
	var stack_restored := Inventory.new(4)
	stack_restored.load_save_list(stack_snapshot)
	_check(stack_restored.item_count() == 1 and stack_restored.count_at(0) == 2, "叠放数量随存档保留")
	camp.storage.clear()

	# 制作系统：配方加载、材料检查、制作消耗与产物
	var recipes := Crafting.load_recipes()
	_check(recipes.size() == 6, "加载全部 6 条制作配方")
	player.inventory.clear()
	var club_recipe: RecipeData = null
	var armor_recipe: RecipeData = null
	for r in recipes:
		if r.id == "recipe_wood_club":
			club_recipe = r
		if r.id == "recipe_scrap_armor":
			armor_recipe = r
	_check(club_recipe != null and club_recipe.product != null
			and club_recipe.product.display_name == "木棒", "木棒配方存在")
	if club_recipe == null or club_recipe.product == null:
		print("SMOKE TEST: 配方加载失败，中止制作测试")
		quit(1)
		return
	_check(not Crafting.can_craft(player.inventory, club_recipe), "材料不足时不能制作")
	_check(not Crafting.craft(player.inventory, club_recipe), "材料不足时制作被拒绝")
	_check(Crafting.missing_text(player.inventory, club_recipe) != "", "缺料时给出缺料摘要")
	player.inventory.add_item(board)
	_check(not Crafting.can_craft(player.inventory, club_recipe), "只有木板时还不能制作")
	player.inventory.add_item(nails)
	_check(not Crafting.can_craft(player.inventory, club_recipe), "钉子只有 1 根（需 2 根）时不能制作")
	player.inventory.add_item(nails)
	_check(Crafting.can_craft(player.inventory, club_recipe), "补齐木板与钉子后可以制作")
	_check(Crafting.craft(player.inventory, club_recipe), "制作成功")
	_check(player.inventory.slots.has(club_recipe.product), "产物木棒进入背包")
	_check(player.inventory.count_of(nails) == 0 and player.inventory.count_of(board) == 0,
			"制作消耗了木板与钉子")

	# 自制护甲：制作产物可装备并计入护甲值
	player.inventory.clear()
	var scrap := load("res://data/items/mat_scrap_metal.tres") as ItemData
	var cloth := load("res://data/items/mat_cloth.tres") as ItemData
	var tape := load("res://data/items/mat_duct_tape.tres") as ItemData
	player.inventory.add_item(scrap)
	player.inventory.add_item(scrap)
	player.inventory.add_item(cloth)
	player.inventory.add_item(cloth)
	player.inventory.add_item(tape)
	_check(Crafting.craft(player.inventory, armor_recipe), "废金属+布料+胶带做出自制护甲")
	var scrap_armor := load("res://data/items/armor_scrap.tres") as ItemData
	_check(player.inventory.slots.has(scrap_armor), "自制护甲进入背包")
	player.use_item(player.inventory.slots.find(scrap_armor))
	_check(player.equipped.get(ItemData.SLOT_CHEST) == scrap_armor, "自制护甲装备到衣服部位")
	var hp_before_armor := player.health
	player.take_damage(10)
	_check(player.health == hp_before_armor - 9.0, "护甲 3 点按 15% 减伤（10 → 9）")
	player.inventory.clear()

	# 工作台：交互弹出制作面板
	var workbench: Interactable = main.get_node("Workbench")
	_check(workbench != null, "安全屋里放着工作台")
	player.global_position = workbench.global_position + Vector2(0, -50)
	for i in 3:
		await physics_frame
	_check(player.nearest_interactable() == workbench, "靠近工作台可交互")
	workbench.interact(player)
	_check(main.get_node("HUD/Root/CraftPanel").visible, "按 E 弹出制作面板")
	hud_node._on_craft_menu_closed()
	_check(not main.get_node("HUD/Root/CraftPanel").visible, "离开工作台后面板关闭")

	# 引导系统：状态触发、一次性、冷却与发现建筑
	var thoughts: ThoughtSystem = main.get_node("ThoughtSystem")
	_check(thoughts != null and thoughts.definition_count() == 14, "ThoughtSystem 挂载且 14 条想法齐全")
	thoughts.start_delay = 0.0
	main.get_node("DayNight").day_number = 1  # 开场独白只在第 1 天（床铺测试已推进天数）
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("wake") == 1, "开局独白「肚子饿了」触发")
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("wake") == 1, "一次性想法不会重复触发")
	player.food = 20.0
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("hunger") == 1, "饥饿阈值触发「找吃的」")
	player.food = 100.0
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("hunger") == 1, "饥饿想法受冷却保护不立即重复")
	var thought_pos := player.global_position
	player.global_position = Vector2(1900, 1172)
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("discover_market") == 1, "首次靠近超市触发「发现建筑」")
	player.global_position = Vector2(1400, 700)
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("discover_police") == 1, "首次靠近警局触发「发现建筑」")
	_check(thoughts.trigger_count("discover_hospital") == 0, "没靠近医院就不触发对应想法")
	player.global_position = thought_pos
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("discover_market") == 1 \
			and thoughts.trigger_count("discover_police") == 1, "同一栋建筑的发现想法只触发一次")
	var health_backup := player.health
	player.health = 30.0
	thoughts.skip_display_wait()
	thoughts.evaluate()
	_check(thoughts.trigger_count("hp_low") == 1, "生命值低触发「得找药」")
	player.health = health_backup

	# —— 物资分布：室外无散落、安全屋无粮、超市有食物、弹药只在警局 ——
	var sp_root: Node2D = main.get_node("SpawnPoints")
	var outdoor_has_loot := false
	for spawn_node in sp_root.get_children():
		if spawn_node is SpawnPoint and spawn_node.pickup_rolls != 0:
			outdoor_has_loot = true
	_check(not outdoor_has_loot, "所有生成点无室外散落物资（搜刮只在建筑内）")
	var fridge_camp := main.get_node("Fridge") as ContainerBase
	var cabinet_camp := main.get_node("KitchenCabinet") as ContainerBase
	_check(fridge_camp != null and fridge_camp.storage.item_count() == 0, "安全屋冰箱已清空")
	_check(cabinet_camp != null and cabinet_camp.storage.item_count() == 0, "安全屋厨房柜已清空")
	var market_food := 0
	var market_node: Node2D = main.get_node("Market")
	for node in get_nodes_in_group("containers"):
		var shelf := node as ContainerBase
		if shelf != null and shelf.get_parent() == market_node:
			for item in shelf.storage.slots:
				if item != null and (item.kind == ItemData.KIND_FOOD \
						or item.kind == ItemData.KIND_WATER):
					market_food += 1
	_check(market_food >= 5, "超市货架仍有充足食物与水")
	var ammo_outside_police := 0
	for node in get_nodes_in_group("containers"):
		var loot_box := node as ContainerBase
		if loot_box == null or loot_box.get_parent() == null:
			continue
		var in_police := false
		var ancestor: Node = loot_box.get_parent()
		while ancestor != null:
			if ancestor.name == "PoliceStation":
				in_police = true
				break
			ancestor = ancestor.get_parent()
		if not in_police:
			for item in loot_box.storage.slots:
				if item != null and item.kind == ItemData.KIND_AMMO:
					ammo_outside_police += 1
	_check(ammo_outside_police == 0, "弹药只从警局获得（其他建筑与掉落表不产弹药）")
	var fixed_backpacks := 0
	for node in get_nodes_in_group("containers"):
		var bp_box := node as ContainerBase
		if bp_box == null:
			continue
		for item in bp_box.storage.slots:
			if item != null and item.kind == ItemData.KIND_BACKPACK:
				fixed_backpacks += 1
	_check(fixed_backpacks >= 2,
			"固定背包 ≥2（清单 12 格 > 初始 8 格：必须找到背包扩容才装得下清单）")

	# 军事基地与撤离任务：汽油、建筑物资、守卫、任务链四阶段与结局
	var military: Node2D = main.get_node("MilitaryBase")
	_check(military != null, "军事基地存在于地图上")
	var mil_stock := 0
	var mil_fuel := 0
	for node in get_nodes_in_group("containers"):
		var mil_box := node as StorageBox
		if mil_box != null and mil_box.get_parent() == military:
			mil_stock += mil_box.storage.item_count()
			for item in mil_box.storage.slots:
				if item != null and item.kind == ItemData.KIND_FUEL:
					mil_fuel += 1
	_check(mil_stock >= 6, "军需柜与油桶备有物资")
	_check(mil_fuel >= 2, "油桶里有汽油")
	var fuel := load("res://data/items/fuel.tres") as ItemData
	_check(fuel.kind == ItemData.KIND_FUEL and fuel.stack_size == 2, "汽油是可叠 2 个的燃料")
	var mil_guards := 0
	for node in get_nodes_in_group("zombies"):
		var mg := node as Zombie
		if mg.global_position.x > 1040.0 and mg.global_position.x < 1520.0 \
				and mg.global_position.y > 150.0 and mg.global_position.y < 510.0:
			mil_guards += 1
	_check(mil_guards >= 4, "军事基地内有守卫僵尸")
	# 最后一个按位置统计的守卫断言已过：恢复自主游荡，供后续行为测试使用
	for fz in wander_frozen:
		if is_instance_valid(fz):
			fz.can_wander = true
	var radio: Interactable = main.get_node("Radio")
	var pilot: SurvivorNpc = main.get_node("Pilot")
	_check(radio != null and pilot != null, "收音机与飞行员 NPC 都在场景里")
	_check(main.quest_stage == "none", "撤离任务初始未开始")
	radio.interact(player)
	_check(main.quest_stage == "radio_heard", "收听广播后撤离任务开启")
	pilot.interact(player)
	_check(main.quest_stage == "pilot_met", "与飞行员交谈接到物资清单")
	pilot.interact(player)
	_check(main.quest_stage == "pilot_met", "没备齐物资时交谈不会推进任务")
	# —— 新撤离清单：配比 4/4/2/2/1、总量大于背包、缺项不可交付 ——
	var req: Dictionary = main.SUPPLY_REQUIREMENTS
	_check(int(req[ItemData.KIND_FOOD]) == 4 and int(req[ItemData.KIND_WATER]) == 4 \
			and int(req[ItemData.KIND_FUEL]) == 2 and int(req[ItemData.KIND_MEDICINE]) == 2 \
			and int(req[ItemData.KIND_AMMO]) == 1, "撤离清单为新配比：食物4 水4 汽油2 医疗2 弹药1")
	var total_required := 0
	for kind in req:
		total_required += int(req[kind])
	_check(total_required > player.base_slot_count,
			"清单总量大于初始背包 8 格（刻意设计：强制分多趟）")
	var supply_load := [
		[load("res://data/items/food_canned.tres") as ItemData, 4],
		[load("res://data/items/water_bottle.tres") as ItemData, 4],
		[fuel, 2],
		[load("res://data/items/med_bandage.tres") as ItemData, 2],
		[load("res://data/items/ammo_pistol_box.tres") as ItemData, 1],
	]
	for i in supply_load.size():  # 缺任一类物资都不应可交付
		player.inventory.clear()
		player.inventory.resize_capacity(24)  # 测试用临时扩容，真实游戏靠分趟
		for j in supply_load.size():
			if j == i:
				continue
			for k in int(supply_load[j][1]):
				player.inventory.add_item(supply_load[j][0])
		_check(not main._has_all_supplies(), "缺一类物资时不可交付（第 %d 类缺席）" % i)
	player.inventory.clear()
	player.inventory.resize_capacity(24)
	for entry in supply_load:  # 全部备齐
		for k in int(entry[1]):
			player.inventory.add_item(entry[0])
	_check(main._has_all_supplies(), "物资清单备齐（食物水汽油药品弹药）")
	main._on_deliver_pressed()
	_check(main.quest_stage == "supplied", "交付物资后任务进入汇合阶段")
	_check(pilot.global_position.distance_to(main.PILOT_PAD_POSITION) < 2.0,
			"交付后飞行员瞬移到停机坪等候")
	# 重型 Boss：交付物资后刷出；数值、蓄力重击节奏与狂暴
	var boss: Brute = null
	for node in get_nodes_in_group("zombies"):
		if node is Brute:
			boss = node
	_check(boss != null, "交付物资后停机坪刷出重型变异体")
	var brute_variant: ZombieVariant = load("res://data/variants/brute.tres")
	_check(brute_variant.max_health == 450 and brute_variant.damage == 20
			and brute_variant.move_speed == 55.0, "重型变异体数值 450 HP / 20 伤 / 移速 55")
	_check(boss.health == 450 and boss.attack_cooldown > 1.0,
			"Boss 初始 450 血、普攻间隔 1.2 秒")
	await physics_frame
	await physics_frame  # 让 Boss 的 _target 在物理帧里完成初始化
	boss._perform_attack()
	boss._perform_attack()
	_check(boss._state == Brute.State.NORMAL, "前两次普攻为普通攻击")
	boss._perform_attack()
	_check(boss._state == Brute.State.SLAM_WINDUP, "第三次普攻进入蓄力重击前摇")
	var brute_hp_before := boss.health
	boss.take_damage(300)
	_check(brute_hp_before - boss.health == 300, "Boss 受击正常扣血（复用受击系统）")
	_check(boss._enraged and boss.move_speed > brute_variant.move_speed,
			"血量低于 45% 进入狂暴（移速提升）")
	_check(player.inventory.count_of(fuel) == 0, "交付扣除了汽油")
	pilot.interact(player)
	_check(main.quest_stage == "escaped", "停机坪与飞行员汇合触发结局")
	_check(main.get_node("HUD/Root/EndingPanel").visible, "结局面板弹出")
	hud_node._on_ending_continue()
	_check(not main.get_node("HUD/Root/EndingPanel").visible, "选择继续生存后世界恢复运行")

	# —— 任务追踪：接取/追踪分离、槽位上限、完成释放、HUD 刷新 ——
	var quests: QuestManager = main._quests
	_check(quests != null and quests.is_accepted("evacuate"),
			"撤离任务处于已接取状态（随任务链路自动接取）")
	_check(quests.is_completed("evacuate") and not quests.is_tracked("evacuate"),
			"任务完成自动释放追踪槽位")
	var hud_q: Hud = main.get_node("HUD")
	var tracker_panel: PanelContainer = hud_q.get_node("Root/QuestTrackerPanel")
	_check(tracker_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"追踪 HUD 不拦截鼠标（不挡游戏世界点击）")
	quests.define_quest("t_a", "测试甲", [{"id": "o", "text": "目标一"}])
	quests.define_quest("t_b", "测试乙", [{"id": "o", "text": "目标一"}])
	quests.define_quest("t_c", "测试丙", [{"id": "o", "text": "目标一"}])
	quests.define_quest("t_d", "测试丁", [{"id": "o", "text": "目标一"}])
	quests.accept("t_a")
	_check(quests.is_accepted("t_a") and not quests.is_tracked("t_a"),
			"接取任务不会自动占用追踪槽位（接取≠追踪）")
	_check(quests.track("t_a") and quests.track("t_b") and quests.track("t_c"),
			"手动追踪至 3 个任务")
	var track_rejected_flag: Array = []  # lambda 按值捕获局部变量，用引用类型做标志
	quests.track_rejected.connect(func(_id: String) -> void: track_rejected_flag.append(true),
			CONNECT_ONE_SHOT)
	_check(not quests.track("t_d") and not track_rejected_flag.is_empty()
			and not quests.is_tracked("t_d"), "槽位满时第 4 个追踪被拒绝（不静默覆盖）")
	_check(hud_q.get_node("Root/QuestTrackerPanel/QuestTrackerBox/QuestList")
			.get_child_count() == 3, "追踪 HUD 显示 3 个任务卡")
	_check(not hud_q.get_node("Root/QuestTrackerPanel/QuestTrackerBox/TrackerEmpty").visible,
			"有追踪任务时不显示空状态")
	var quest_changed_flag: Array = []
	quests.quest_changed.connect(func(_id: String) -> void: quest_changed_flag.append(true),
			CONNECT_ONE_SHOT)
	quests.set_objective_text("t_a", "o", "目标一（进度 1/2）")
	_check(not quest_changed_flag.is_empty(),
			"目标进度变化发出 quest_changed（HUD 自动刷新依据）")
	var a_entry := {}
	for e in quests.tracked_snapshot():
		if e.id == "t_a":
			a_entry = e
	_check(not a_entry.is_empty() and str(a_entry.current_text) == "目标一（进度 1/2）",
			"追踪快照返回最新目标文本（进度实时）")
	quests.untrack("t_a")
	_check(quests.is_accepted("t_a") and not quests.is_tracked("t_a"),
			"取消追踪不影响任务接取状态")
	quests.untrack("t_b")
	quests.untrack("t_c")
	_check(hud_q.get_node("Root/QuestTrackerPanel/QuestTrackerBox/TrackerEmpty").visible,
			"无追踪任务时显示简洁空状态")
	quests.track("t_d")
	_check(quests.is_tracked("t_d"), "槽位释放后可再次追踪")
	quests.complete_quest("t_d")
	_check(not quests.is_tracked("t_d"), "追踪中的任务完成后自动从 HUD 移除")

	# 地图迷雾与标记：揭开、保留、三态地点与情报解锁
	var fog: FogOfWar = main.get_node("FogOfWar")
	_check(fog != null and fog.col_count() > 0, "迷雾系统挂载且网格已生成")
	_check(fog.is_explored(player.global_position), "玩家所在区域已被揭开")
	_check(not fog.is_explored(Vector2(2300, 200)), "地图东北角仍是未知区域")
	fog.reveal_area(Vector2(2300, 200), 220.0)
	_check(fog.is_explored(Vector2(2300, 200)), "情报照亮能揭开远处区域")
	_check(int(main.map_markers["military"]) >= 1, "收音机广播解锁军营地图标记")
	_check(int(main.map_markers["camp"]) == 2, "安全屋开局即为已探索")
	main.map_markers["police"] = 0
	player.global_position = Vector2(1400, 700)
	main._update_map_markers()
	_check(int(main.map_markers["police"]) == 1, "路过警局被自动发现")
	main.map_markers["market"] = 0
	main.map_markers["hospital"] = 0
	player.global_position = Vector2(1900, 1172)
	main._update_map_markers()
	_check(int(main.map_markers["market"]) == 1, "靠近后超市标记为已发现")
	hud_node.toggle_map(true)
	_check(main.get_node("HUD/Root/MapPanel").visible, "M 键打开地图面板")
	hud_node.toggle_map(false)
	_check(not main.get_node("HUD/Root/MapPanel").visible, "再按 M 关闭地图面板")
	player.global_position = Vector2(1900, 1000)
	main._update_map_markers()
	_check(int(main.map_markers["market"]) == 2, "走进建筑标记为已探索")
	var note := load("res://data/items/note_hospital.tres") as ItemData
	player.inventory.add_item(note)
	var note_index := player.inventory.slots.find(note)
	player.use_item(note_index)
	_check(int(main.map_markers["hospital"]) == 1, "阅读纸条解锁医院地图标记")
	_check(player.inventory.count_of(note) == 0, "纸条阅读后消耗")

	# —— 丧尸感知系统：视线遮挡 / 听觉 / 导航寻路 ——
	var zscene_per := load("res://scenes/enemies/Zombie.tscn") as PackedScene
	# 1) 导航网格已烘焙，路径会绕过超市墙体（直线穿墙 vs 绕行门口）
	var nav_probe_z: Zombie = get_nodes_in_group("zombies")[0]
	_check(nav_probe_z._nav_ready(), "主场景启动后导航网格已烘焙")
	var nav_map: RID = nav_probe_z._nav.get_navigation_map()
	var nav_path := NavigationServer2D.map_get_path(
			nav_map, Vector2(1500, 1000), Vector2(1900, 1060), true)
	var path_len := 0.0
	for i in range(1, nav_path.size()):
		path_len += nav_path[i - 1].distance_to(nav_path[i])
	var straight := Vector2(1500, 1000).distance_to(Vector2(1900, 1060))
	_check(nav_path.size() >= 2 and path_len > straight * 1.15,
			"导航路径绕过超市墙体（经门口绕行而非直线穿墙）")
	# 2) 隔墙失明：丧尸在超市墙外 184px（视野 260 内），但视线被墙体挡住
	# 先清掉场上守卫：玩家就站在 MarketGuard 刷点内，贴脸守卫会被挥砍命中
	# 触发惨叫（声源=丧尸位置≠玩家位置），覆盖挥砍声源记忆造成随机失败。
	# 守卫位置断言已在前面测过；Boss（Brute）保留——后面的读档测试需要它。
	for node in get_nodes_in_group("zombies"):
		if node is Brute:
			continue
		node.queue_free()
	var wall_blind: Zombie = zscene_per.instantiate()
	main.add_child(wall_blind)
	wall_blind.global_position = Vector2(1780, 1200)
	player.global_position = Vector2(1900, 1060)
	for i in 8:
		await physics_frame
	_check(not wall_blind._sees_player, "隔着超市墙体丧尸看不见玩家")
	_check(wall_blind._memory_left == 0.0, "没看见也没听到时丧尸不会凭空追踪")
	# 3) 听觉：隔墙挥砍声让丧尸记住声源位置并前来调查
	player._attack_toward(Vector2.RIGHT)
	await physics_frame
	await physics_frame
	_check(wall_blind._memory_left > 0.0 \
			and wall_blind._last_seen.distance_to(player.global_position) < 2.0,
			"隔墙挥砍声引来丧尸调查（记住声源位置）")
	# 3b) 声音半径外：挥砍声 240px 传不到远处丧尸
	wall_blind.global_position = Vector2(1500, 1200)  # 距玩家约 424px
	wall_blind._memory_left = 0.0
	player._attack_toward(Vector2.RIGHT)
	await physics_frame
	await physics_frame
	_check(wall_blind._memory_left == 0.0, "声音半径之外的丧尸不会收到挥砍声")
	# 3c) 调查记忆按时限衰减，超时后丧尸放弃调查
	#（headless 的 delta 是墙钟且极短，取极小初值保证任意正 delta 一帧衰减到零）
	wall_blind._memory_left = 0.000001
	await physics_frame
	await physics_frame
	_check(wall_blind._memory_left == 0.0, "调查记忆超时归零（丧尸会放弃调查）")
	wall_blind.queue_free()
	# 4) 关门挡视线、开门能看见（营地安全屋）
	var gate_door := main.get_node("Door") as Door
	var gate_watcher: Zombie = zscene_per.instantiate()
	main.add_child(gate_watcher)
	gate_watcher.global_position = Vector2(200, 1540)
	player.global_position = Vector2(200, 1420)
	gate_door.set_closed(true)
	for i in 8:
		await physics_frame
	_check(not gate_watcher._sees_player, "关着的门挡住丧尸视线")
	gate_door.set_closed(false)
	for i in 8:
		await physics_frame
	_check(gate_watcher._sees_player, "门打开后丧尸能看见屋内玩家")
	gate_door.set_closed(true)
	gate_watcher.queue_free()
	# 5) 开阔地：视线通畅时正常追击移动
	player.global_position = Vector2(760, 700)
	var field_chaser: Zombie = zscene_per.instantiate()
	main.add_child(field_chaser)
	field_chaser.global_position = Vector2(600, 700)
	for i in 4:
		await physics_frame
	_check(field_chaser._sees_player, "开阔地丧尸能看见玩家")
	var chaser_start_x := field_chaser.global_position.x
	for i in 30:
		await physics_frame
	_check(field_chaser.global_position.x > chaser_start_x + 20.0, "视线通畅时丧尸朝玩家移动")
	field_chaser.queue_free()

	# 6) Boss 冲撞视线门槛：隔墙不冲撞，获得视线后才起跑（不隔墙撞墙）
	var boss_probe: Brute = (load("res://scenes/enemies/Brute.tscn") as PackedScene).instantiate()
	main.add_child(boss_probe)
	boss_probe.global_position = Vector2(1780, 1200)  # 超市墙外
	player.global_position = Vector2(1900, 1060)      # 墙内（距探针约 184px，在冲撞距离区间内）
	for i in 8:
		await physics_frame
	boss_probe._charge_cd = 0.0
	boss_probe._try_start_charge()
	_check(boss_probe._state != Brute.State.CHARGE_WINDUP, "隔墙时 Boss 不发动冲撞")
	boss_probe._sees_player = true  # 模拟获得视线
	boss_probe._try_start_charge()
	_check(boss_probe._state == Brute.State.CHARGE_WINDUP, "有视线时 Boss 正常进入冲撞前摇")
	boss_probe.queue_free()

	# —— 自主行为：游荡 / 搜索 / 调查切换 ——
	# （headless 下帧率与墙钟不对应，行为断言一律事件驱动 + 帧数上限兜底）
	# 1) 无目标自主游荡：看不见玩家也无记忆时，丧尸在附近游荡而非罚站
	# 玩家放东北角空地（距丧尸 1300px+，超视野）：不能用"躲安全屋"制造不可见——
	# 安全屋关门会触发 target_sheltered 屏蔽调查分支，游荡断言过但调查断言必挂
	var wb_a: Zombie = zscene_per.instantiate()
	main.add_child(wb_a)
	wb_a.global_position = Vector2(560, 700)
	player.global_position = Vector2(1900, 300)
	var wa_start := wb_a.global_position
	var wandered := false
	for i in 1500:
		await physics_frame
		if wb_a.global_position.distance_to(wa_start) > 25.0:
			wandered = true
			break
	_check(wandered, "无目标丧尸自主游荡（实际发生位移）")
	_check(wb_a.global_position.distance_to(wa_start) < 400.0,
			"游荡位移受导航约束（不会瞬移/狂奔出区域）")
	# 2) 游荡节奏不同步：同点放出的两只丧尸停顿/目标互不相同
	var wb_b: Zombie = zscene_per.instantiate()
	main.add_child(wb_b)
	wb_b.global_position = Vector2(580, 720)
	var desynced := false
	for i in 240:
		await physics_frame
		if wb_a._wander_wait != wb_b._wander_wait \
				or wb_a._wander_point != wb_b._wander_point:
			desynced = true
			break
	_check(desynced, "两只丧尸游荡节奏不同步")
	wb_b.queue_free()  # 断言 2 完成，移除 wb_b：后续 wb_a 要瞬移到附近测试，
	# 两只丧尸碰撞体叠在一起会物理互挤，卡住移动造成随机失败
	# 3) 声音打断游荡：记住声源并前往调查（距离明显缩短）
	# 确定性部分：hear_noise 后立即进入调查状态（记忆 > 0 且未到达声源）
	wb_a.global_position = Vector2(560, 700)  # 瞬移到固定点，排除游荡漂移干扰
	wb_a.hear_noise(Vector2(950, 700))
	_check(wb_a._ai_state() == "INVESTIGATE", "声音打断游荡（立即进入调查状态）")
	# 位移部分：事件驱动等待接近声源（headless 帧率随机器波动，上限放宽）
	var d0 := wb_a.global_position.distance_to(Vector2(950, 700))
	var approached := false
	for i in 3000:
		await physics_frame
		if wb_a.global_position.distance_to(Vector2(950, 700)) < d0 - 50.0:
			approached = true
			break
	_check(approached, "调查状态下丧尸实际向声源移动")
	# 4) 搜索/调查结束（记忆耗尽）后恢复游荡：状态最终回到 WANDER/IDLE
	wb_a._memory_left = 0.0001
	var resumed := false
	for i in 2500:
		await physics_frame
		if wb_a._ai_state() == "WANDER" or wb_a._ai_state() == "IDLE":
			resumed = true
			break
	_check(resumed, "搜索结束后恢复自主游荡")
	# 5) 游荡中重新看见玩家 → 立即恢复追击
	# 玩家动态传到丧尸旁 100px 的空地上（不赌固定坐标；感知周期 0.15s，留足余量）
	player.global_position = wb_a.global_position + Vector2(100, 0)
	var saw_again := false
	for i in 600:
		await physics_frame
		if wb_a._sees_player and wb_a._ai_state() == "CHASE":
			saw_again = true
			break
	_check(saw_again, "游荡中重新看见玩家立即转为追击")
	# 6) Boss 不参与游荡：无目标时保持驻守
	var boss_guard: Brute = (load("res://scenes/enemies/Brute.tscn") as PackedScene).instantiate()
	main.add_child(boss_guard)
	boss_guard.global_position = Vector2(700, 560)
	player.global_position = Vector2(1900, 1060)  # 远离且隔超市墙
	var bg_start := boss_guard.global_position
	for i in 150:
		await physics_frame
	_check(boss_guard.global_position.distance_to(bg_start) < 5.0,
			"Boss 无目标时不游荡（保持驻守）")
	boss_guard.queue_free()
	wb_a.queue_free()

	# —— 玩家视野：全向 + 视野锥 + 墙体遮挡 / 窗户透视 ——
	# headless 无鼠标：关掉 fog 自动刷新，用 aim_override 固定方向手动驱动。
	fog.set_physics_process(false)
	fog.aim_override = Vector2.RIGHT
	# 1) 开阔地：锥内远处格可见，锥外同距格不可见（方向性）
	player.global_position = Vector2(800, 700)
	await physics_frame
	await physics_frame
	fog.reveal_now()
	_check(fog.cell_state(16, 11) == FogOfWar.STATE_VISIBLE,
			"视野锥内远距格子可见（aim=右，(1056,736) 距 258px）")
	_check(fog.cell_state(8, 11) != FogOfWar.STATE_VISIBLE,
			"视野锥外同距格子不可见（玩家左侧 243px）")
	# 2) 方向切换：aim 转向左后，原锥内格熄灭、新方向格点亮
	fog.aim_override = Vector2.LEFT
	fog.reveal_now()
	_check(fog.cell_state(8, 11) == FogOfWar.STATE_VISIBLE,
			"转向后视野锥随鼠标方向更新（左侧格点亮）")
	_check(fog.cell_state(16, 11) != FogOfWar.STATE_VISIBLE,
			"转向后原右侧远格不再当前可见")
	# 3) 全向圈隔墙遮挡：玩家在超市室内贴东墙上段墙（y 820~950），
	#    墙外贴脸格子不因距离近而可见（64px 网格下墙带内无格中心，
	#    用"室内贴墙→室外格"方向验证遮挡）
	player.global_position = Vector2(2120, 930)
	fog.aim_override = Vector2.RIGHT
	await physics_frame
	await physics_frame
	fog.reveal_now()
	_check(fog.cell_state(33, 14) != FogOfWar.STATE_VISIBLE,
			"全向圈内隔墙格子不可见（墙体截断近距视线）")
	# 4) 窗户透视：玩家在室内贴东墙窗洞（y 950~1050 @ x=2132），
	#    透过窗看见室外；窗旁下段墙（y 1050~1180）仍遮挡
	player.global_position = Vector2(2120, 1010)
	await physics_frame
	await physics_frame
	fog.reveal_now()
	_check(fog.cell_state(33, 15) == FogOfWar.STATE_VISIBLE,
			"透过窗户可见室外近格（视线穿窗、窗后无墙）")
	_check(fog.cell_state(33, 17) != FogOfWar.STATE_VISIBLE,
			"窗户旁的墙体仍遮挡视线（不会整面墙透视）")
	var zwin: Zombie = zscene_per.instantiate()
	main.add_child(zwin)
	zwin.global_position = Vector2(2090, 1000)
	await physics_frame
	await physics_frame
	_check(zwin._has_line_of_sight(), "丧尸隔窗能看见窗外玩家（窗户允许视觉检测）")
	zwin.global_position = Vector2(2090, 880)
	await physics_frame
	await physics_frame
	_check(not zwin._has_line_of_sight(), "丧尸隔窗旁墙体看不见玩家（墙仍遮挡）")
	zwin.queue_free()
	# 5) 窗户挡移动：朝窗冲刺被实体碰撞拦下，不能穿窗
	player.global_position = Vector2(2200, 1000)
	player.velocity = Vector2(-400, 0)
	for i in 40:
		player.move_and_slide()
		await physics_frame
	_check(player.global_position.x > 2152.0, "窗户阻挡角色移动（不能穿窗）")
	player.velocity = Vector2.ZERO
	# 6) 家具不挡玩家视野：玩家视线只查墙/门层（值 4），贴身家具不再把格子挡黑
	#    （回归：此前沙发所在格中心落在沙发碰撞体内 → 格子永久黑，"沙发只亮一半"）
	player.global_position = Vector2(150, 1380)
	fog.aim_override = Vector2.RIGHT
	await physics_frame
	await physics_frame
	fog.reveal_now()
	_check(fog.cell_state(1, 21) == FogOfWar.STATE_VISIBLE,
			"贴身家具不挡玩家视野（沙发所在格可见）")
	# 7) 家具夹缝不再"完全无视野"：沙发/桌子/西墙窄缝里，身边多数格子仍点亮
	player.global_position = Vector2(118, 1330)
	await physics_frame
	await physics_frame
	fog.reveal_now()
	var lit := 0
	for gy in range(19, 24):
		for gx in range(0, 5):
			if fog.cell_state(gx, gy) == FogOfWar.STATE_VISIBLE:
				lit += 1
	_check(lit >= 5, "家具夹缝处视野正常（5x5 内点亮 %d 格，修复前仅 1）" % lit)
	fog.set_physics_process(true)
	fog.aim_override = Vector2.ZERO

	# —— 精力与疲劳系统：初始值/消耗/恢复/阶段惩罚/上限/钳制/暂停 ——
	var st: StaminaSystem = player.stamina
	_check(st != null, "玩家挂载了精力/疲劳系统")
	st.set_fatigue(0.0)
	st.refill()
	_check(st.stamina == 100.0 and st.fatigue == 0.0, "初始精力 100、疲劳 0")
	# 奔跑：消耗精力 + 累积疲劳（容差含"上限收缩钳制"的 0.6×Δ疲劳，非额外扣减）
	var fatigue_before_run := st.fatigue
	st.tick(1.0, true, false)
	_check(absf(st.stamina - 92.0) < 0.1, "奔跑 1 秒消耗 8 点精力")
	_check(st.fatigue > fatigue_before_run, "奔跑累积疲劳（随游戏时间+额外档）")
	# 精力耗尽不能继续奔跑（但步行不受限——步行本身不消耗）
	st.stamina = 0.0
	_check(not st.can_sprint(), "精力耗尽后不能继续奔跑")
	# 近战：精力不足不能挥击（不部分消耗）；足够时消耗 8 点
	st.refill()
	st.stamina = 4.0
	_check(not st.try_melee() and st.stamina == 4.0, "精力不足时不能近战")
	st.refill()
	var stamina_before_attack := st.stamina
	player._attack_toward(Vector2.RIGHT)
	_check(absf(st.stamina - (stamina_before_attack - 8.0)) < 0.01, "近战攻击消耗 8 点精力")
	# 休息恢复：普通 10/s、安全屋 15/s；普通休息不降疲劳
	st.stamina = 50.0
	st.tick(1.0, false, false)
	_check(absf(st.stamina - 60.0) < 0.5, "普通休息恢复 10 点/秒（正常阶段）")
	st.stamina = 50.0
	st.tick(1.0, false, true)
	_check(absf(st.stamina - 65.0) < 0.5, "安全屋内休息恢复 15 点/秒")
	var fatigue_before_rest := st.fatigue
	st.tick(1.0, false, false)
	_check(st.fatigue < fatigue_before_rest + 0.5,
			"普通休息不显著降低疲劳（仅自然增长）")
	# 疲劳阶段惩罚切换与回落解除（统一修正机制，基础属性不被改写）
	st.set_fatigue(24.0)
	_check(st.recovery_mult() == 1.0 and st.hit_miss_chance() == 0.0,
			"阶段 A 正常：无惩罚")
	st.set_fatigue(25.0)
	_check(absf(st.recovery_mult() - 0.9) < 0.001, "阶段 B 轻度疲劳：精力恢复 -10%")
	st.set_fatigue(50.0)
	_check(absf(st.recovery_mult() - 0.75) < 0.001
			and absf(st.hit_miss_chance() - 0.10) < 0.001,
			"阶段 C 严重疲劳：恢复 -25%、落空率 10%")
	st.set_fatigue(75.0)
	_check(absf(st.recovery_mult() - 0.5) < 0.001
			and absf(st.hit_miss_chance() - 0.25) < 0.001
			and absf(st.attack_cooldown_mult() - 1.3333) < 0.001,
			"阶段 D 极度疲劳：恢复 -50%、落空率 25%、攻速 -25%")
	_check(absf(player.current_attack_cooldown()
			- player.attack_cooldown * 1.3333) < 0.01,
			"极度疲劳攻击冷却变长（读修正值，基础冷却未被改写）")
	st.set_fatigue(20.0)
	_check(st.recovery_mult() == 1.0 and st.hit_miss_chance() == 0.0,
			"疲劳回落到正常后惩罚解除")
	# 精力上限 = max(40, 100 - 0.6×疲劳)，当前精力被钳制不超上限
	st.refill()
	st.set_fatigue(50.0)
	_check(absf(st.max_stamina() - 70.0) < 0.01 and st.stamina <= 70.0,
			"疲劳 50 → 精力上限 70，当前精力不超过上限")
	st.set_fatigue(100.0)
	_check(absf(st.max_stamina() - 40.0) < 0.01, "疲劳 100 → 精力上限下限 40")
	# 极值钳制：长时间/大数值运行不出现负数或越界
	st.add_fatigue(500.0)
	_check(st.fatigue == 100.0, "疲劳钳制不超过 100")
	st.set_fatigue(-50.0)
	_check(st.fatigue == 0.0, "疲劳钳制不为负")
	st.stamina = 80.0
	st.set_fatigue(0.0)
	st.tick(9999.0, true, false)
	_check(st.stamina == 0.0 and st.fatigue == 100.0,
			"极端时长结算：精力钳制不为负、疲劳不越界")
	# 暂停期间不累计疲劳、不推进时间（节点 _process 停跑）
	st.set_fatigue(10.0)
	var fatigue_when_paused := st.fatigue
	paused = true
	for i in 5:
		await process_frame
	paused = false
	_check(st.fatigue == fatigue_when_paused, "暂停期间不累计疲劳")
	_check(st.stamina >= 0.0 and st.stamina <= st.max_stamina(),
			"暂停后精力仍在合法范围")
	st.refill()

	# —— 伤势与疾病系统 ————————————————————————————————
	var med: HealthSystem = player.medical

	# 骨折：移速降低、奔跑耗精提高；夹板固定后惩罚减轻但不立即痊愈
	med.injuries["fracture"] = {"splinted": false, "recover_left": 24.0}
	var speed_normal := player.move_speed
	_check(player.current_move_speed() < speed_normal * 0.6,
			"未固定骨折显著降低移速（%.0f → %.0f）"
					% [speed_normal, player.current_move_speed()])
	_check(med.run_cost_mult() > 1.5, "未固定骨折提高奔跑精力消耗")
	med.injuries.fracture.splinted = true
	_check(player.current_move_speed() > speed_normal * 0.75
			and player.current_move_speed() < speed_normal * 0.85,
			"夹板固定后移速惩罚减轻（%.0f）" % player.current_move_speed())
	_check(not med.injuries.is_empty() and med.injuries.has("fracture"),
			"夹板固定不等于立即痊愈")
	# 固定 24 游戏小时后痊愈（直接推进恢复计时）
	med.injuries.fracture.recover_left = 0.0
	med.tick(0.05, false, false)
	_check(not med.injuries.has("fracture"), "固定满 24 游戏小时后骨折解除")
	_check(absf(player.current_move_speed() - speed_normal) < 0.01,
			"骨折解除后移速修正完全恢复")

	# 严重出血：持续扣血；急救包止住
	var bleed_health_before := player.health
	player.medical.injuries.clear()  # 清掉绷带测试段遗留的降级出血
	player.medical.injuries["bleed_severe"] = {}
	med.tick(1.0, false, false)
	var lost := bleed_health_before - player.health
	_check(lost > 0.4 and lost < 0.8, "严重出血每秒持续损失生命（实际 %.2f）" % lost)
	var firstaid := load("res://data/items/med_firstaid.tres") as ItemData
	player.inventory.clear()
	player.inventory.add_item(firstaid)
	player.use_item(player.inventory.slots.find(firstaid))
	_check(not player.medical.injuries.has("bleed_severe"), "急救包止住严重出血")
	_check(player.health > bleed_health_before - lost, "急救包同时恢复生命")
	med.tick(1.0, false, false)
	var after_heal := player.health
	med.tick(1.0, false, false)
	_check(absf(player.health - after_heal) < 0.01,
			"出血止住后不再持续扣血（自然恢复另计）")

	# 伤口感染：风险累积→触发→分级→抗生素逐步治疗
	med.infection_risk = 0.999
	med.injuries["bleed_minor"] = {"left": 600.0}
	med.tick(1.0, false, false)
	_check(med.illnesses.has("infection") and med.infection_label() == "轻度",
			"感染风险满值触发轻度伤口感染")
	var regen_before := med.stamina_regen_mult()
	_check(regen_before < 1.0, "轻度感染降低精力恢复（×%.2f）" % regen_before)
	med.illnesses.infection.treat_progress = 7.9  # 差一点到 8 小时恶化线
	med.tick(10.0, false, false)
	_check(med.infection_label() == "中度", "未治疗感染随游戏时间恶化到中度")
	_check(med.stamina_cap_penalty() > 0.0, "中度感染降低精力上限")
	var antibiotic := load("res://data/items/med_antibiotic.tres") as ItemData
	player.inventory.clear()
	player.inventory.add_item(antibiotic)
	player.use_item(player.inventory.slots.find(antibiotic))
	_check(bool(med.illnesses.infection.get("treating", false)), "抗生素开始治疗感染")
	med.illnesses.infection.treat_progress = 2.95
	med.tick(10.0, false, false)
	_check(med.infection_label() == "轻度", "抗生素约 3 游戏小时降低一级感染")
	med.illnesses.infection.treat_progress = 2.95
	med.tick(10.0, false, false)
	_check(not med.illnesses.has("infection"), "感染完全痊愈")
	med.illnesses.erase("fever")  # 根因已愈；发热消退期惩罚属正常（发热段单独验证）
	_check(med.stamina_regen_mult() == 1.0 and med.stamina_cap_penalty() == 0.0,
			"感染痊愈后精力恢复与上限修正全部解除")
	player.medical.injuries.erase("bleed_minor")
	player.medical.infection_risk = 0.0

	# 发热：随中/重度感染出现；退热药只缓解不清根因
	med.illnesses["infection"] = {"stage": 2, "treat_progress": 0.0}
	med.tick(0.05, false, false)
	_check(med.illnesses.has("fever"), "中度感染引发发热")
	var cd_with_fever := med.attack_cooldown_mult()
	_check(cd_with_fever > 1.0, "发热降低攻击速度（冷却×%.2f）" % cd_with_fever)
	var fever_med := load("res://data/items/med_fever.tres") as ItemData
	player.inventory.clear()
	player.inventory.add_item(fever_med)
	player.use_item(player.inventory.slots.find(fever_med))
	_check(med.fever_med_left > 0.0 and med.attack_cooldown_mult() == 1.0,
			"退热药缓解发热惩罚（药效期内）")
	_check(med.illnesses.has("fever") and med.illnesses.has("infection"),
			"退热药不清除发热状态与根源感染")
	med.illnesses.infection.stage = 1  # 根因降到轻度
	med.tick(0.05, false, false)
	_check(med.illnesses.has("fever"), "根因降级后发热进入消退期（尚未消失）")
	med.tick(200.0, false, false)  # 3+ 游戏小时
	_check(not med.illnesses.has("fever"), "根因感染减轻后发热逐步消退")
	med.illnesses.erase("infection")

	# 肠胃疾病：脱水触发；水分消耗加快；补水后恢复
	player.water = 0.0
	med.tick(70.0, false, true)  # 脱水 70 游戏秒
	_check(med.illnesses.has("gastro"), "长时间脱水触发肠胃疾病")
	_check(med.water_drain_mult() > 1.0, "肠胃疾病加快水分消耗")
	_check(med.stamina_regen_mult() < 1.0, "肠胃疾病降低精力恢复")
	player.water = 80.0  # 补水：停止恶化进入恢复
	var gastro_regen := med.stamina_regen_mult()
	_check(gastro_regen < 1.0, "肠胃疾病恢复期仍有轻度惩罚（×%.2f）" % gastro_regen)
	med._gastro_recover_left = 0.01
	med.tick(5.0, false, false)
	_check(not med.illnesses.has("gastro"), "水分充足一段时间后肠胃疾病痊愈")
	_check(med.water_drain_mult() == 1.0, "痊愈后水分消耗倍率恢复")
	# 补液盐：补水 + 加速恢复
	var rehy := load("res://data/items/med_rehydration.tres") as ItemData
	med.illnesses["gastro"] = {"stage": 1}
	med._gastro_recover_left = 0.0
	player.inventory.clear()
	player.inventory.add_item(rehy)
	var water_before_rehy := player.water
	player.use_item(player.inventory.slots.find(rehy))
	_check(player.water > water_before_rehy, "补液盐恢复水分")
	_check(med._gastro_recover_left > 0.0, "补液盐加速肠胃疾病恢复")
	med.illnesses.clear()

	# 止痛药：药效期内骨折惩罚减半，到期恢复
	med.injuries["fracture"] = {"splinted": false, "recover_left": 24.0}
	var speed_fracture := player.current_move_speed()
	var painkiller := load("res://data/items/med_painkiller.tres") as ItemData
	player.inventory.clear()
	player.inventory.add_item(painkiller)
	player.use_item(player.inventory.slots.find(painkiller))
	_check(player.current_move_speed() > speed_fracture,
			"止痛药缓解骨折移速惩罚")
	_check(not med.injuries.is_empty() and med.injuries.has("fracture"),
			"止痛药不治疗骨折本身")
	med.painkiller_left = 0.0
	_check(absf(player.current_move_speed() - speed_fracture) < 0.01,
			"止痛药药效到期后惩罚重新生效")
	med.injuries.clear()

	# 修正叠加与死亡：多状态扣血叠加但各来源只算一次；死亡后不再扣血
	med.injuries["bleed_severe"] = {}
	med.illnesses["infection"] = {"stage": 3, "treat_progress": 0.0}
	var health_before_combo := player.health
	med.tick(1.0, false, false)
	var combo_lost := health_before_combo - player.health
	_check(absf(combo_lost - 0.9) < 0.05,
			"严重出血+重度感染叠加扣血各算一次（预期 0.9，实际 %.2f）" % combo_lost)
	player.dead = true
	var health_at_death := player.health
	med.tick(2.0, false, false)
	_check(player.health == health_at_death, "死亡后不再继续扣血")
	_check(med.attack_damage_mult() < 1.0 and med.move_speed_mult() < 1.0,
			"重度感染同时降低攻击伤害与移速（无重复叠加）")
	player.dead = false
	player.medical.injuries.clear()
	player.medical.illnesses.clear()
	player.medical.infection_risk = 0.0
	player.health = 100.0

	# 存档 / 读档
	var saved_day: int = main.get_node("DayNight").day_number
	var saved_pos := player.global_position + Vector2(120.0, 80.0)
	player.global_position = saved_pos
	player.health = 66.0
	player.inventory.clear()
	player.inventory.add_item(load("res://data/items/food_canned.tres") as ItemData)
	var zombies_before_save: int = get_nodes_in_group("zombies").size()
	var pickups_before_save: int = get_nodes_in_group("pickups").size()
	var fog_bits_before: String = fog.get_save_data()
	main.map_markers["hardware"] = 2
	main._quests.track("t_a")  # 任务追踪状态随存档保留的验证样本
	player.stamina.set_fatigue(42.0)
	player.stamina.stamina = 30.0  # 精力/疲劳随存档保留的验证样本
	main.save_game()
	player.health = 10.0
	player.inventory.clear()
	player.global_position = Vector2(100.0, 100.0)
	# 杀掉一只僵尸、捡走一件地上物资，模拟存档后世界发生变化
	var victim: Zombie = get_nodes_in_group("zombies")[0]
	victim.take_damage(999)
	main.load_game()
	_check(player.health == 66.0, "读档恢复生命值")
	_check(player.inventory.item_count() == 1, "读档恢复背包物品")
	_check(main.get_node("DayNight").day_number == saved_day, "读档恢复天数")
	_check(player.global_position.distance_to(saved_pos) < 2.0, "读档恢复玩家位置")
	_check(get_nodes_in_group("zombies").size() == zombies_before_save, "读档还原全部僵尸（含被杀的）")
	_check(get_nodes_in_group("pickups").size() == pickups_before_save, "读档还原全部地上物资")
	_check(thoughts.trigger_count("wake") == 1, "想法触发记录随存档保留")
	_check(main.quest_stage == "escaped", "读档保留撤离任务的结局状态")
	_check(fog.get_save_data() == fog_bits_before, "读档保留迷雾探索进度")
	_check(int(main.map_markers["hardware"]) == 2, "读档保留地图标记状态")
	_check(main._quests.is_tracked("t_a"), "读档保留任务追踪状态")
	_check(absf(player.stamina.fatigue - 42.0) < 0.01
			and absf(player.stamina.stamina - 30.0) < 0.01, "读档保留精力与疲劳")
	var boss_after_load := 0
	for node in get_nodes_in_group("zombies"):
		if node is Brute:
			boss_after_load += 1
	_check(boss_after_load == 1, "读档后重型变异体仍以 Boss 形态存在")
	var restored_variant_count := 0
	for node in get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z.health > 0 and z.health <= z.max_health:
			restored_variant_count += 1
	_check(restored_variant_count == zombies_before_save, "还原僵尸的血量与变体有效")

	# ESC 暂停菜单
	var hud: Hud = main.get_node("HUD")
	_check(not paused and not hud._menu_open, "初始未暂停、菜单关闭")
	hud.toggle_pause_menu()
	_check(paused and hud._menu_open, "ESC 菜单打开时游戏暂停")
	_check(hud.get_node("Root/PauseMenu").visible, "暂停菜单面板可见")
	hud.toggle_pause_menu()
	_check(not paused and not hud._menu_open, "关闭菜单后恢复运行")

	# —— 调试键（DebugCheats）：只在调试构建存在；逐个调方法验证效果 ——
	var cheats: DebugCheats = null
	for child in main.get_children():
		if child is DebugCheats:
			cheats = child
			break
	_check(cheats != null, "调试构建挂载了调试键节点")
	if cheats != null:
		# F1 全场击杀（读档测试已结束，此时杀 Boss 不影响后续断言）
		var alive_before := 0
		for node in get_nodes_in_group("zombies"):
			var z := node as Zombie
			if z.health > 0.0:
				alive_before += 1
		cheats._kill_all_zombies()
		var alive_after := 0
		for node in get_nodes_in_group("zombies"):
			var z := node as Zombie
			if z.health > 0.0:
				alive_after += 1
		_check(alive_before > 0 and alive_after == 0,
				"调试键 F1 击杀全场丧尸（%d -> 0 存活）" % alive_before)
		# F2 无敌：开启后伤害无效，关闭后恢复
		player.god_mode = false
		cheats._toggle_god_mode()
		var cheat_hp := player.health
		player.take_damage(30)
		_check(player.health == cheat_hp, "调试键 F2 开启无敌后受到伤害无效")
		cheats._toggle_god_mode()
		player.take_damage(30)
		_check(player.health < cheat_hp, "调试键 F2 关闭无敌后恢复受伤")
		player.god_mode = false  # 复位，避免影响后续测试
		# F3 测试物资包：清背包重发，含撤离清单四项
		player.inventory.clear()
		cheats._give_test_kit()
		_check(player.inventory.count_of(load("res://data/items/fuel.tres") as ItemData) >= 1
				and player.inventory.count_of(load("res://data/items/med_firstaid.tres") as ItemData) >= 1
				and player.inventory.count_of(load("res://data/items/food_canned.tres") as ItemData) >= 2
				and player.inventory.count_of(load("res://data/items/water_bottle.tres") as ItemData) >= 2,
				"调试键 F3 发放含撤离清单的标准测试包")
		_check(player.ammo_pistol >= 60 and player.ammo_rifle >= 60, "调试键 F3 同步补充备弹")
		# F4 昼夜切换
		var was_night: bool = main.get_node("DayNight").is_night
		cheats._toggle_day_night()
		_check(main.get_node("DayNight").is_night != was_night, "调试键 F4 切换昼夜")
		cheats._toggle_day_night()  # 切回，保持现场一致
		# F5 状态回满
		player.health = 10.0
		player.food = 5.0
		player.water = 5.0
		cheats._refill_status()
		_check(player.health == float(player.max_health) and player.food == player.max_food
				and player.water == player.max_water, "调试键 F5 回满生命/食物/水")
		# 按键路径：真实派发 F5 按键事件，确认 _unhandled_input 能接住
		player.health = 10.0
		var f5 := InputEventKey.new()
		f5.keycode = KEY_F5
		f5.pressed = true
		Input.parse_input_event(f5)
		for i in 4:
			await physics_frame
		_check(player.health == float(player.max_health), "调试键 F5 实际按键可触发")

	print("----------------------------------------")
	root.remove_child(main)
	main.free()
	if _failures == 0:
		print("SMOKE TEST: ALL PASSED")
		quit(0)
	else:
		print("SMOKE TEST: %d FAILED" % _failures)
		quit(1)


func _test_inventory() -> void:
	var inv := Inventory.new(2)
	var a := ItemData.new()
	var b := ItemData.new()
	var c := ItemData.new()
	_check(inv.add_item(a), "有限容量：第 1 件可放入")
	_check(inv.add_item(b), "有限容量：第 2 件可放入")
	_check(not inv.add_item(c), "有限容量：第 3 件放不下")
	inv.remove_item(0)
	_check(inv.add_item(c), "腾出空位后可放入")
	inv.resize_capacity(inv.capacity + 2)
	_check(inv.capacity == 4 and inv.add_item(a), "扩容后容量与放置正确")

	var storage := Inventory.new(-1)
	for i in 20:
		if not storage.add_item(a):
			_check(false, "无限容量可一直放入")
			break
	_check(storage.item_count() == 20, "无限容量：20 件全部放入")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		_failures += 1
		print("FAIL  " + label)
