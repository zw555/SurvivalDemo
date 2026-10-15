class_name Player
extends CharacterBody2D
## 玩家：WASD 移动、鼠标方向近战攻击、实时消耗的生存数值与格子背包。
## 打击感反馈：挥砍弧线、击退、受击闪红、飘字、音效、顿帧与震屏。

signal stats_changed
signal inventory_changed
signal equipped_changed
signal died
signal notify(text: String)
## 阅读情报纸条后发出，参数为纸条要解锁的地点 id；由 main.gd 裁决。
signal intel_found(reveals: String)

const SFX_SWING := preload("res://assets/audio/swing.wav")
const SFX_HIT := preload("res://assets/audio/hit.wav")
const SFX_PICKUP := preload("res://assets/audio/pickup.wav")
const SFX_HURT := preload("res://assets/audio/hurt.wav")
const PICKUP_SCENE := preload("res://scenes/items/ItemPickup.tscn")

## 手雷最大投掷距离（像素）。
const GRENADE_THROW_RANGE := 220.0
## 枪械 hitscan 的瞄准容差：目标到射线的垂直距离小于该值视为在射线上。
const GUN_AIM_TOLERANCE := 18.0

## 装备部位顺序（HUD 装备面板按此排列）。
const EQUIP_SLOTS: Array[String] = [
	ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R, ItemData.SLOT_HEAD,
	ItemData.SLOT_CHEST, ItemData.SLOT_LEGS, ItemData.SLOT_FEET, ItemData.SLOT_BACKPACK,
]

@export var move_speed := 160.0
@export var max_health := 100
@export var unarmed_damage := 5
@export var attack_range := 48.0
@export var attack_half_arc_deg := 50.0
@export var attack_cooldown := 0.45
@export var max_food := 100.0
@export var max_water := 100.0
## 消耗速率按"一天 600 秒（现实 10 分钟）"折算：食物 180/天、水 300/天（×3 压力档）。
## 满状态 100 只够撑 333 秒 ≈ 一次出门时长：出门前必须算"带几个罐头"。
## 缺水比缺粮更急（现实里人不喝水死得更快），水是每天的主要补给压力。
@export var food_drain_per_sec := 0.3
@export var water_drain_per_sec := 0.5
@export var starvation_damage_per_sec := 2.0
@export var thirst_damage_per_sec := 3.0
@export var base_slot_count := 8
@export var regen_interval := 10.0  ## 每隔多少秒自然恢复 1 点生命值（饥饿/口渴归零时暂停）
@export var knockback_force := 200.0
@export var knockback_decay := 900.0

var health := 65.0  ## 带伤开局（_ready 应用）：一睁眼就要面对"先包扎还是先找吃的"
var food := 54.0  ## 开局 3 分钟量（0.3/秒 × 180 秒）：必须立刻决定去哪
var water := 50.0  ## 开局约 1.6 分钟量：比食物更紧，出门第一目标
var dead := false
var god_mode := false  ## 仅调试键（DebugCheats）切换；Release 版无入口，恒为 false
## 枪械弹药储备：弹盒物品按 E 装填进来，射击时逐发消耗。
var ammo_pistol := 0
var ammo_rifle := 0
## 装备栏：部位名 -> ItemData（见 ItemData.SLOT_*；空位不存在键）。
var equipped: Dictionary = {}
var inventory: Inventory

var _attack_timer := 0.0
var _knockback := Vector2.ZERO
var _regen_accum := 0.0
var _interactables: Array[Interactable] = []
var _swing: Polygon2D
var _sfx: AudioStreamPlayer
var _sprinting := false  # 本帧是否在奔跑（物理帧判定，_process 里用于精力结算）
var _sprint_denied_accum := 0.0  # 精力不足提示的节流计时

## 精力/疲劳系统（参数与修正集中在该模块）；由 _ready 创建。
var stamina: StaminaSystem
## 伤势/疾病系统（出血、骨折、感染、发热、肠胃；修正统一由它提供）；由 _ready 创建。
var medical: HealthSystem
## 安全屋区域引用（由 main.gd 注入），用于"安全屋内恢复更快"的判定。
var camp_area: Area2D

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	# 新开局初始状态（带伤 + 低饱食 + 更紧的水）：读档时被存档值覆盖，不会重复发放
	health = float(max_health) - 35.0
	food = 54.0
	water = 50.0
	inventory = Inventory.new(base_slot_count)
	inventory.changed.connect(_on_inventory_changed)
	stamina = StaminaSystem.new()
	stamina.name = "StaminaSystem"
	add_child(stamina)
	# 精力/疲劳变化统一并入 stats_changed，HUD 一条刷新路径
	stamina.fatigue_stage_changed.connect(func(_label: String) -> void: stats_changed.emit())
	medical = HealthSystem.new()
	medical.name = "HealthSystem"
	add_child(medical)
	# 持续扣血（出血/重度感染）交回玩家结算（死亡判定集中一处）
	medical.continuous_damage.connect(_apply_continuous_damage)
	medical.condition_alert.connect(func(text: String, danger: int) -> void:
		notify.emit(text)
		if danger > 0:
			_hurt_flash())
	# 疾病压低精力上限：同步给 StaminaSystem 并收紧当前值
	medical.condition_changed.connect(func() -> void:
		stamina.cap_penalty = medical.stamina_cap_penalty()
		stamina.stamina = minf(stamina.stamina, stamina.max_stamina())
		stats_changed.emit())
	_build_swing_arc()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Master"
	add_child(_sfx)


func _on_inventory_changed() -> void:
	inventory_changed.emit()


func _physics_process(delta: float) -> void:
	if dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 奔跑：按住 Shift 且有移动输入且精力足够；精力耗尽自动降为步行（不剥夺控制权）
	_sprinting = input_vec != Vector2.ZERO and Input.is_action_pressed("sprint") \
			and stamina.can_sprint()
	velocity = input_vec * current_move_speed()
	if _sprinting:
		velocity *= StaminaSystem.SPRINT_SPEED_MULT
	velocity += _knockback
	move_and_slide()


## 当前移速：基础移速 + 装备（鞋子等）的百分比加成，再乘伤势/疾病修正
## （骨折影响最明显；状态解除后修正自动消失，基础值从不被改写）。
func current_move_speed() -> float:
	return move_speed * (1.0 + speed_bonus_pct() / 100.0) * medical.move_speed_mult()


func in_camp() -> bool:
	return camp_area != null and camp_area.has_point(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event.is_action_pressed("attack") and _attack_timer <= 0.0:
		_attack()
	if event.is_action_pressed("interact"):
		var target := nearest_interactable()
		if target != null:
			target.interact(self)


## 可交互物注册表：进入/离开范围时由 Interactable 调用。
func register_interactable(interactable: Interactable) -> void:
	if not _interactables.has(interactable):
		_interactables.append(interactable)


func unregister_interactable(interactable: Interactable) -> void:
	_interactables.erase(interactable)


## 当前可以交互的最近对象；没有时返回 null（HUD 用它显示提示）。
func nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_dist := INF
	for interactable in _interactables:
		if not is_instance_valid(interactable) or not interactable.can_interact(self):
			continue
		var dist := global_position.distance_squared_to(interactable.global_position)
		if dist < best_dist:
			best_dist = dist
			best = interactable
	return best


func _process(delta: float) -> void:
	if dead:
		return
	_drain_survival_stats(delta)
	_natural_regen(delta)
	# 精力/疲劳结算（暂停时 _process 不跑 → 暂停期间不消耗不累计）
	if _sprint_denied_accum > 0.0:
		_sprint_denied_accum = maxf(0.0, _sprint_denied_accum - delta)
	if Input.is_action_pressed("sprint") and not _sprinting \
			and Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO \
			and _sprint_denied_accum <= 0.0 and not stamina.can_sprint():
		notify.emit("太累了，跑不动了……先缓一缓")
		_sprint_denied_accum = 2.0
	# 伤势/疾病修正：精力恢复 × 疾病倍率、奔跑消耗 × 骨折倍率、疲劳 × 疾病倍率
	medical.tick(delta, _sprinting, water <= 0.0)
	stamina.tick(delta, _sprinting, in_camp(),
			medical.stamina_regen_mult(), medical.run_cost_mult(),
			medical.fatigue_rate_mult())


## 当前使用的武器：左右手中伤害更高的一件；空手返回 null。
## 伤害与攻击距离都由它决定（同时拿矛和刀时，以伤害高者为准）。
func current_weapon() -> ItemData:
	var best: ItemData = null
	for slot in [ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R]:
		var item: ItemData = equipped.get(slot)
		if item != null and (best == null or item.damage > best.damage):
			best = item
	return best


## 当前攻击力：左右手武器中伤害最高的一件，否则空手；重度感染按统一修正降低。
func current_damage() -> int:
	var weapon := current_weapon()
	var base := maxi(unarmed_damage, weapon.damage) if weapon != null else unarmed_damage
	return maxi(1, roundi(base * medical.attack_damage_mult()))


## 当前攻击冷却：武器的 attack_cooldown（0 = 玩家默认）。匕首类更快。
## 极度疲劳与发热按统一修正变长，基础值不被改写。
func current_attack_cooldown() -> float:
	var weapon := current_weapon()
	var base := attack_cooldown
	if weapon != null and weapon.attack_cooldown > 0.0:
		base = weapon.attack_cooldown
	return base * stamina.attack_cooldown_mult() * medical.attack_cooldown_mult()


## 当前攻击距离：武器的 attack_range（0 = 默认一格）。
func current_attack_range() -> float:
	var weapon := current_weapon()
	if weapon != null and weapon.attack_range > 0.0:
		return weapon.attack_range
	return attack_range


## 当前挥击扇形半角：长柄武器（矛）角度更小，体现"直刺"而不是横扫。
func current_attack_arc_deg() -> float:
	var weapon := current_weapon()
	if weapon != null and weapon.attack_arc_deg > 0.0:
		return weapon.attack_arc_deg
	return attack_half_arc_deg


## 总护甲：所有已装备部位的 defense 之和。
func total_defense() -> int:
	var total := 0
	for item in equipped.values():
		if item != null:
			total += item.defense
	return total


## 总移速加成百分比：所有已装备部位的 speed_bonus 之和。
func speed_bonus_pct() -> float:
	var total := 0.0
	for item in equipped.values():
		if item != null:
			total += item.speed_bonus
	return total


## 拾取点调用；返回 false 表示背包已满。
func try_pickup(item: ItemData) -> bool:
	if not inventory.add_item(item):
		notify.emit("背包满了！")
		return false
	notify.emit("拾取了 %s" % item.display_name)
	_play_sfx(SFX_PICKUP)
	return true


## 点击背包格子时的行为：吃 / 喝 / 用药 / 装填 / 投雷 / 装备（武器→手、背包→背包部位、服装→对应部位）。
## aim 参数供测试与脚本调用显式指定方向；默认取鼠标方向。
func use_item(index: int, aim: Vector2 = Vector2.ZERO) -> void:
	var item := inventory.peek(index)
	if item == null:
		return
	match item.kind:
		ItemData.KIND_FOOD:
			food = minf(max_food, food + item.food_value)
			inventory.remove_item(index)
			notify.emit("吃掉了 %s" % item.display_name)
			_play_sfx(SFX_PICKUP)
			stats_changed.emit()
		ItemData.KIND_WATER:
			water = minf(max_water, water + item.water_value)
			inventory.remove_item(index)
			notify.emit("喝掉了 %s" % item.display_name)
			_play_sfx(SFX_PICKUP)
			stats_changed.emit()
		ItemData.KIND_MEDICINE:
			_use_medicine(index, item)
		ItemData.KIND_AMMO:
			if item.ammo_type == "pistol":
				ammo_pistol += item.ammo_amount
			else:
				ammo_rifle += item.ammo_amount
			inventory.remove_item(index)
			notify.emit("装填了 %s ×%d" % [item.ammo_display_name(), item.ammo_amount])
			_play_sfx(SFX_PICKUP)
			stats_changed.emit()
		ItemData.KIND_GRENADE:
			var throw_aim := aim
			if throw_aim == Vector2.ZERO:
				throw_aim = get_global_mouse_position() - global_position
			if throw_aim.length() < 0.01:
				throw_aim = Vector2.RIGHT
			var target := global_position \
					+ throw_aim.normalized() * minf(throw_aim.length(), GRENADE_THROW_RANGE)
			inventory.remove_item(index)
			_spawn_grenade(item, target)
			notify.emit("投出了 %s" % item.display_name)
			stats_changed.emit()
		ItemData.KIND_MATERIAL:
			notify.emit("%s 是制作材料，拿到工作台去用" % item.display_name)
		ItemData.KIND_NOTE:
			inventory.remove_item(index)
			intel_found.emit(item.reveals)
			notify.emit("仔细读完了 %s，位置已经记在地图上（按 M 查看）" % item.display_name)
			_play_sfx(SFX_PICKUP)
		ItemData.KIND_WEAPON, ItemData.KIND_GUN, ItemData.KIND_BACKPACK, ItemData.KIND_CLOTHING:
			var slot := _target_slot(item)
			inventory.remove_item(index)
			if not equip_item(item, slot):
				inventory.add_item(item)  # 装备失败放回背包


## 装备一件武器会占用/腾出的手位：双手武器占左右手；单手武器（匕首）虽然只握一只手，
## 但同一时间仍然只能持一件武器——装备新武器时双手都要腾空。
func _affected_slots_for(item: ItemData, slot: String) -> Array[String]:
	if item.kind == ItemData.KIND_WEAPON or item.kind == ItemData.KIND_GUN:
		return [ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R]
	return [slot]


## 装备到指定部位；被替换的旧装备放回背包（放不下则整体失败）。
## 双手武器同时占用左右手。成功返回 true。
func equip_item(item: ItemData, slot: String) -> bool:
	if item == null or slot == "":
		return false
	var affected := _affected_slots_for(item, slot)
	var olds: Array[ItemData] = []  # 同一件双手武器在两个槽位只记一次
	for s in affected:
		var old: ItemData = equipped.get(s)
		if old != null and not olds.has(old):
			olds.append(old)
	var placed: Array[ItemData] = []
	for old in olds:
		if inventory.add_item(old):
			placed.append(old)
		else:
			for placed_item in placed:  # 放不下：撤回已入包的，装备栏原样不动
				inventory.remove_item(inventory.slots.find(placed_item))
			notify.emit("背包满了，无法更换装备")
			return false
	for s in affected:
		equipped.erase(s)
	if item.kind == ItemData.KIND_WEAPON and item.two_handed:
		equipped[ItemData.SLOT_HAND_L] = item
		equipped[ItemData.SLOT_HAND_R] = item
	else:
		equipped[slot] = item
	_after_equipment_changed()
	notify.emit("装备了 %s（%s）" % [item.display_name, ItemData.SLOT_NAMES.get(slot, slot)])
	_play_sfx(SFX_PICKUP)
	return true


## 脱下某部位的装备放回背包；双手武器从任意一只手脱下都整体卸下。
## 背包部位需要先确认缩容后放得下。
func unequip_slot(slot: String) -> bool:
	var item: ItemData = equipped.get(slot)
	if item == null:
		return false
	var affected: Array[String] = [slot]
	if item.kind == ItemData.KIND_WEAPON and item.two_handed:
		affected = [ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R]
	if slot == ItemData.SLOT_BACKPACK:
		if inventory.item_count() + 1 > base_slot_count:
			notify.emit("背包里东西太多，无法脱下")
			return false
		equipped.erase(slot)
		inventory.resize_capacity(base_slot_count)
	else:
		for s in affected:
			equipped.erase(s)
	if not inventory.add_item(item):
		for s in affected:
			equipped[s] = item
		_after_equipment_changed()
		notify.emit("背包满了，无法脱下")
		return false
	notify.emit("脱下了 %s" % item.display_name)
	_after_equipment_changed()
	return true


## 依据物品类型决定目标装备部位。
func _target_slot(item: ItemData) -> String:
	match item.kind:
		ItemData.KIND_WEAPON, ItemData.KIND_GUN:
			return ItemData.SLOT_HAND_R  # 所有武器同一时间只持一件，装到右手
		ItemData.KIND_BACKPACK:
			return ItemData.SLOT_BACKPACK
		ItemData.KIND_CLOTHING:
			return item.equip_slot
	return ""


## 容量 = 基础格数 + 已装备背包的扩容；装备变化后调用。
func _refresh_capacity() -> void:
	var bonus := 0
	var backpack: ItemData = equipped.get(ItemData.SLOT_BACKPACK)
	if backpack != null:
		bonus = backpack.slot_bonus
	inventory.resize_capacity(base_slot_count + bonus)


func _after_equipment_changed() -> void:
	_refresh_capacity()
	equipped_changed.emit()


## 药品使用：按物品 id 分发到 HealthSystem（规则集中在 MEDICINE_RULES/apply_medicine）。
## 没有可治疗的状态时提示原因且不消耗——不允许无意义浪费药品。
func _use_medicine(index: int, item: ItemData) -> void:
	# 补液盐特殊：先补水（普通饮水规则），再走疾病缓解
	if item.id == "med_rehydration":
		if water >= max_water - 0.5 and not medical.illnesses.has("gastro"):
			notify.emit("水分充足也没有肠胃问题，不需要补液")
			return
		water = minf(max_water, water + item.water_value)
		var extra := medical.apply_rehydration()
		inventory.remove_item(index)
		notify.emit("使用了 %s（饮水 +%d）%s" % [item.display_name, int(item.water_value),
				("· " + extra) if extra != "" else ""])
		_play_sfx(SFX_PICKUP)
		stats_changed.emit()
		return
	var result := medical.apply_medicine(item)
	# 急救包等同时带回复量的药：有治疗对象时顺带回血
	if result != "" and item.heal_amount > 0.0 and health < float(max_health):
		var healed := minf(item.heal_amount, max_health - health)
		health += healed
		result += "，生命 +%d" % int(healed)
	if result == "":
		notify.emit("%s现在用不上：%s" % [item.display_name, item.usage_desc])
		return
	inventory.remove_item(index)
	notify.emit("使用了 %s：%s" % [item.display_name, result])
	_play_sfx(SFX_PICKUP)
	stats_changed.emit()


## 持续扣血（出血 / 重度感染）；与受击伤害分开结算（无护甲、无击退）。
func _apply_continuous_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()
	else:
		stats_changed.emit()


## 恢复生命值（睡觉等来源）；上限为最大生命值。
func heal(amount: int) -> void:
	if dead or amount <= 0:
		return
	health = minf(float(max_health), health + float(amount))
	stats_changed.emit()


## 自然恢复：每隔 regen_interval 秒回 1 点；饥饿或口渴归零时暂停（身体没有余力愈合）。
func _natural_regen(delta: float) -> void:
	if regen_interval <= 0.0 or health >= float(max_health):
		return
	if food <= 0.0 or water <= 0.0:
		_regen_accum = 0.0
		return
	_regen_accum += delta
	if _regen_accum >= regen_interval:
		_regen_accum -= regen_interval
		health = minf(float(max_health), health + 1.0)
		stats_changed.emit()


## 丢弃背包中物品：掉在脚下附近，按 E 可再捡回（右键背包格触发）。
func drop_item(index: int) -> void:
	var item := inventory.peek(index)
	if item == null:
		return
	inventory.remove_item(index)
	_spawn_pickup_nearby(item, 16.0)
	notify.emit("丢弃了 %s" % item.display_name)


func _spawn_pickup_nearby(item: ItemData, spread: float) -> void:
	var pickup := PICKUP_SCENE.instantiate()
	pickup.item = item
	get_parent().add_child(pickup)
	pickup.global_position = global_position + Vector2(randf_range(-spread, spread), randf_range(-spread, spread))


func take_damage(amount: int, from_direction := Vector2.ZERO) -> void:
	if dead or god_mode:
		return
	# 护甲 = 百分比减伤（总防 ÷20），减完至少剩 1 点——防具降低风险但无法免疫伤害。
	var final_damage := maxi(1, roundi(amount * (1.0 - minf(float(total_defense()), 20.0) / 20.0)))
	health = maxf(0.0, health - final_damage)
	# 伤势结算：重击可能出血/骨折（概率与阈值在 HealthSystem，来源由伤害轻重区分）
	medical.on_damaged(final_damage, final_damage >= 25)
	_knockback = from_direction.normalized() * knockback_force
	_hurt_flash()
	_play_sfx(SFX_HURT)
	_shake(0.4)
	var host := get_tree().current_scene
	if host != null:
		FloatingText.spawn(host, global_position, "-%d" % final_damage, Color(1.0, 0.4, 0.35))
	stats_changed.emit()
	if health <= 0.0:
		_die()


## 死亡后由主场景把玩家送回营地并调用。
## 精力回满（死里逃生喘口气）；疲劳保留——长距离探索的负担不会因死亡消失。
## 伤势/疾病清空：死里逃生相当于重新来过，骨折/感染不再延续（否则无医疗时是死循环）。
func revive() -> void:
	dead = false
	health = float(max_health)
	_knockback = Vector2.ZERO
	stamina.refill(true)
	medical.injuries.clear()
	medical.illnesses.clear()
	medical.infection_risk = 0.0
	medical.painkiller_left = 0.0
	medical.fever_med_left = 0.0
	medical.condition_changed.emit()
	stats_changed.emit()


## 存档：玩家状态、背包与装备（物品按 .tres 资源路径序列化）。
func get_save_data() -> Dictionary:
	var inv_items := inventory.to_save_list()
	var equip_data := {}
	for slot in equipped:
		var item: ItemData = equipped[slot]
		if item != null and item.resource_path != "":
			equip_data[slot] = item.resource_path
	return {
		"health": health,
		"food": food,
		"water": water,
		"stamina": stamina.stamina,
		"fatigue": stamina.fatigue,
		"medical": medical.to_save_data(),
		"ammo_pistol": ammo_pistol,
		"ammo_rifle": ammo_rifle,
		"inventory": inv_items,
		"equipped": equip_data,
	}


## 读档：恢复状态、装备与背包。无背包装备时容量回落到基础格数。
func load_save_data(data: Dictionary) -> void:
	dead = false
	health = minf(float(max_health), float(data.get("health", max_health)))
	food = minf(max_food, float(data.get("food", max_food)))
	water = minf(max_water, float(data.get("water", max_water)))
	ammo_pistol = int(data.get("ammo_pistol", 0))
	ammo_rifle = int(data.get("ammo_rifle", 0))
	stamina.set_fatigue(float(data.get("fatigue", 0.0)))
	stamina.stamina = clampf(float(data.get("stamina", stamina.max_stamina())),
			0.0, stamina.max_stamina())
	medical.load_save_data(data.get("medical", {}))
	stamina.cap_penalty = medical.stamina_cap_penalty()
	equipped.clear()
	var equip_data: Dictionary = data.get("equipped", {})
	for slot in equip_data:
		var res := load(str(equip_data[slot]))
		if res is ItemData:
			equipped[slot] = res
	_refresh_capacity()
	inventory.load_save_list(data.get("inventory", []))
	inventory_changed.emit()
	stats_changed.emit()
	equipped_changed.emit()


func _attack() -> void:
	var aim := get_global_mouse_position() - global_position
	if aim.length() < 0.01:
		aim = Vector2.RIGHT
	_attack_toward(aim)


## 按指定方向攻击（普通调用由 _attack 传入鼠标方向；测试可直接传方向）。
func _attack_toward(aim: Vector2) -> void:
	var weapon := current_weapon()
	if weapon != null and weapon.kind == ItemData.KIND_GUN:
		_gun_attack(weapon, aim.normalized())
		return
	# 近战消耗精力：耗尽时挥不动（不进入冷却，喘口气就能再试；提示走 _process 节流）
	if not stamina.try_melee():
		notify.emit("太累了，挥不动……")
		return
	_attack_timer = current_attack_cooldown()
	var reach := current_attack_range()
	_play_sfx(SFX_SWING)
	_show_swing_arc(aim.angle(), reach)
	# 挥砍声会惊动范围内的丧尸（听觉系统）：隔墙偷袭不再无声无息
	NoiseEvent.emit(self, global_position, NoiseEvent.MELEE_LOUDNESS)
	var targets: Array[Zombie] = []
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null:
			continue
		var to_zombie := zombie.global_position - global_position
		if to_zombie.length() > reach:
			continue
		if absf(aim.angle_to(to_zombie)) > deg_to_rad(current_attack_arc_deg()):
			continue
		targets.append(zombie)
	if weapon != null and weapon.single_target and targets.size() > 1:
		var nearest: Zombie = targets[0]
		var nearest_dist := INF
		for z in targets:
			var d := global_position.distance_squared_to(z.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = z
		targets = [nearest]  # 矛只刺中最近的一个
	# 疲劳/重度感染使命中率下降：现有战斗是范围判定必中，映射为本次攻击整体落空（一次概率判定）
	if not targets.is_empty() and randf() < stamina.hit_miss_chance() + medical.hit_miss_chance():
		var host := get_tree().current_scene
		if host != null:
			FloatingText.spawn(host, global_position, "落空", Color(0.8, 0.8, 0.8))
		return
	for zombie in targets:
		zombie.take_damage(current_damage(), (zombie.global_position - global_position).normalized())
	if not targets.is_empty():
		_play_sfx(SFX_HIT)
		_shake(0.3)
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("hit_stop"):
			scene.call("hit_stop")


## 枪械射击：消耗 1 发对应弹药，沿射线命中最近的目标（hitscan）。
func _gun_attack(weapon: ItemData, dir: Vector2) -> void:
	var ammo := ammo_pistol if weapon.gun_ammo_type == "pistol" else ammo_rifle
	if ammo <= 0:
		notify.emit("没有%s了" % weapon.ammo_display_name())
		return
	if weapon.gun_ammo_type == "pistol":
		ammo_pistol -= 1
	else:
		ammo_rifle -= 1
	var reach := weapon.attack_range if weapon.attack_range > 0.0 else attack_range
	var best: Zombie = null
	var best_dist := reach
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null:
			continue
		var to_zombie := zombie.global_position - global_position
		var along := dir.dot(to_zombie)
		if along <= 0.0 or along > reach:
			continue
		if absf(dir.cross(to_zombie)) > GUN_AIM_TOLERANCE:
			continue
		if along < best_dist:
			best_dist = along
			best = zombie
	if best != null:
		best.take_damage(weapon.damage, dir)
	_tracer(dir * best_dist)
	# 枪声很响：惊动更大范围内的丧尸
	NoiseEvent.emit(self, global_position, NoiseEvent.GUNSHOT_LOUDNESS)
	stats_changed.emit()


## 枪口曳光：一条快速淡出的细线，标示弹道。
func _tracer(end: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(1.0, 0.9, 0.4, 0.9)
	line.points = PackedVector2Array([Vector2.ZERO, end])
	add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.08)
	tw.tween_callback(line.queue_free)


## 投掷手雷：生成手雷节点飞向目标点，落地后延迟爆炸。
func _spawn_grenade(item: ItemData, target: Vector2) -> void:
	var g := Grenade.new()
	g.blast_damage = float(item.damage)
	g.blast_radius = item.blast_radius if item.blast_radius > 0.0 else 90.0
	add_child(g)
	g.global_position = global_position + Vector2(0, -10)
	g.launch(target)


func _die() -> void:
	if dead:
		return
	dead = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_drop_everything()
	died.emit()


## 死亡惩罚：背包与身上装备全部掉落在死亡地点（DESIGN.md 用户决定）。
## 双手武器在左右手各存一份引用，去重后只掉一件。
func _drop_everything() -> void:
	for index in range(inventory.slots.size() - 1, -1, -1):
		var item := inventory.remove_item(index)
		if item != null:
			_spawn_pickup_nearby(item, 32.0)
	var dropped: Array[ItemData] = []
	for slot in equipped:
		var item: ItemData = equipped[slot]
		if item != null and not dropped.has(item):
			dropped.append(item)
			_spawn_pickup_nearby(item, 32.0)
	equipped.clear()
	_after_equipment_changed()
	inventory_changed.emit()


func _drain_survival_stats(delta: float) -> void:
	# 肠胃疾病加快水分/食物消耗（状态解除后倍率自动回到 1，基础速率不被改写）
	food = maxf(0.0, food - food_drain_per_sec * medical.food_drain_mult() * delta)
	water = maxf(0.0, water - water_drain_per_sec * medical.water_drain_mult() * delta)
	var drain_damage := 0.0
	if food <= 0.0:
		drain_damage += starvation_damage_per_sec * delta
	if water <= 0.0:
		drain_damage += thirst_damage_per_sec * delta
	if drain_damage > 0.0:
		health = maxf(0.0, health - drain_damage)
		if health <= 0.0:
			_die()
			return
	stats_changed.emit()


## 按秒数一次性结算生存消耗（睡眠推进时间时用，与实时规则完全一致）。
## 返回是否仍然存活（睡梦中饿死会返回 false）。
func drain_survival_seconds(seconds: float) -> bool:
	_drain_survival_stats(seconds)
	return not dead


func _build_swing_arc() -> void:
	_swing = Polygon2D.new()
	_swing.visible = false
	_swing.z_index = 1
	add_child(_swing)


## 每次攻击时按当前武器的距离/角度重建扇形（换武器后无需额外刷新）。
func _rebuild_swing_polygon(reach: float, half_arc_deg: float) -> void:
	var steps := 14
	var points := PackedVector2Array()
	for i in steps + 1:
		var ang := deg_to_rad(lerpf(-half_arc_deg, half_arc_deg, float(i) / steps))
		points.append(Vector2(cos(ang), sin(ang)) * reach * 0.95)
	for i in steps + 1:
		var ang := deg_to_rad(lerpf(half_arc_deg, -half_arc_deg, float(i) / steps))
		points.append(Vector2(cos(ang), sin(ang)) * 14.0)
	_swing.polygon = points


func _show_swing_arc(aim_angle: float, reach: float) -> void:
	_rebuild_swing_polygon(reach, current_attack_arc_deg())
	_swing.rotation = aim_angle
	_swing.scale = Vector2.ONE
	_swing.color = Color(1.0, 1.0, 1.0, 0.5)
	_swing.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_swing, "color:a", 0.0, 0.14)
	tween.tween_property(_swing, "scale", Vector2(1.15, 1.15), 0.14)
	tween.chain().tween_callback(_hide_swing)


func _hide_swing() -> void:
	_swing.visible = false


func _hurt_flash() -> void:
	_visual.modulate = Color(3.0, 0.5, 0.5)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0), 0.15)


func _shake(amount: float) -> void:
	var cam := get_node_or_null("Camera2D") as CameraShake
	if cam != null:
		cam.add_trauma(amount)


func _play_sfx(stream: AudioStream) -> void:
	_sfx.stream = stream
	_sfx.pitch_scale = randf_range(0.92, 1.08)
	_sfx.play()
