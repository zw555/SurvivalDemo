class_name Zombie
extends CharacterBody2D
## 僵尸感知模型（视线 + 听觉 + 记忆）：
## - 视线：玩家在视野内且中间没有墙体/家具/关着的门遮挡时才能"看见"（射线检测）。
##   隔墙时丧尸是瞎的，不会无端追踪。
## - 听觉：玩家攻击、开枪、爆炸与同伴惨叫会发出声响（NoiseEvent.emit），范围内的丧尸
##   会记住声源位置并前往调查——声音可穿墙，但没有透视。
## - 记忆：失去视线后走向最后目击点（沿导航路径绕过障碍），到达或超时后放弃。
## 移动：主场景启动时烘焙导航网格，追击/调查沿导航路径走，会绕过墙体从门口进来。
## 玩家身处营地范围内且门关着时放弃追击（营地是安全区）。
## 打击感反馈：受击击退与闪白、伤害飘字、死亡特效（独立节点，本体立即释放）。

## 感知检测间隔（秒）：视线射线不必每帧打。
const PERCEPTION_INTERVAL := 0.15
## 失去视线后还记得玩家位置多久（秒）。
const MEMORY_TIME := 5.0
## 调查目标点走到多近算"到了"（像素）。
const INVESTIGATE_ARRIVE_DIST := 24.0
## 视线检测用的碰撞层位：所有静态障碍（墙/家具/关门）都在 layer 2 上。
const SIGHT_MASK := 2

## —— 自主行为：无目标游荡 / 丢失目标后就地搜索 ——
const WANDER_RADIUS_MIN := 50.0  ## 游荡目标距中心的最小半径（像素）
const WANDER_RADIUS_MAX := 140.0  ## 自主游荡的最大半径
const WANDER_ARRIVE_DIST := 16.0  ## 游荡目标走到多近算到达
const WANDER_WAIT_MIN := 1.2  ## 到达后的停顿区间（秒），随机取值防同步
const WANDER_WAIT_MAX := 3.2
const WANDER_STUCK_TIME := 6.0  ## 一个游荡点走这么久还没到就放弃重选（卡死保护）
const WANDER_SPEED_RATIO := 0.45  ## 游荡速度 = 移速 × 该系数（漫游感，不巡逻冲刺）
const SEARCH_RADIUS := 90.0  ## 丢失目标后围绕最后目击点搜索的半径
const SEARCH_MIN_TIME := 2.5  ## 到达目击点后至少搜索这么久（防止走路耗光记忆后没得搜）

@export var variant: ZombieVariant  ## 非空时覆盖以下默认参数（_ready 时应用）
@export var max_health := 45
@export var damage := 8
@export var move_speed := 90.0
@export var detect_radius := 260.0
@export var attack_range := 40.0
@export var attack_cooldown := 1.0
@export var knockback_force := 180.0
@export var knockback_decay := 800.0
@export var night_detect_mult := 1.4  ## 夜晚视野倍率（DayNight 系统调用 set_night_buffed）
@export var night_speed_mult := 1.15  ## 夜晚移速倍率

var health := 50

var _attack_timer := 0.0
var _knockback := Vector2.ZERO
var _target: Node2D
var _camp: Node = null
var _gate: Node = null
var _base_detect := 0.0
var _base_speed := 0.0
var _night_buffed := false
## —— 感知状态 ——
var _perception_timer := 0.0
var _sees_player := false  ## 当前是否真的看得见玩家（距离 + 无遮挡）
var _last_seen := Vector2.ZERO  ## 最后一次目击（或听到）的位置
var _memory_left := 0.0  ## 记忆剩余时间；> 0 时前往最后目击点调查
var _searching := false  ## 已到达目击点、正在就地小范围搜索（区分调查行进阶段）
## —— 自主行为状态 ——
@export var can_wander := true  ## 无目标时是否自主游荡（Boss 覆写 false 保持驻守）
var _wander_point := Vector2.ZERO  ## 当前游荡/搜索目标点；ZERO = 无（到点或停顿中）
var _wander_wait := 0.0  ## 停顿剩余时间（秒）
var _wander_walked := 0.0  ## 当前游荡点已走的时间（卡死保护计时）
## —— 寻路 ——
var _nav: NavigationAgent2D

## 轻量调试开关：置 true 后状态切换各打一行日志（不刷屏）。
static var debug_ai := false
var _logged_state := ""

@onready var _visual: Polygon2D = $Visual
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	if variant != null:
		max_health = variant.max_health
		damage = variant.damage
		move_speed = variant.move_speed
		detect_radius = variant.detect_radius
	health = max_health
	if variant != null:
		_visual.color = variant.color
	_name_label.text = variant.display_name if variant != null else "普通丧尸"
	_base_detect = detect_radius
	_base_speed = move_speed
	_nav = NavigationAgent2D.new()
	_nav.radius = 10.0
	_nav.path_desired_distance = 12.0
	_nav.target_desired_distance = 12.0
	add_child(_nav)
	# 随机初始停顿相位：避免同帧刷出的丧尸游荡节奏完全同步
	_wander_wait = randf_range(0.0, WANDER_WAIT_MAX)


## 昼夜系统调用：夜晚视野与移速提升，白天恢复基准值。
func set_night_buffed(buffed: bool) -> void:
	if _night_buffed == buffed:
		return
	_night_buffed = buffed
	if buffed:
		detect_radius = _base_detect * night_detect_mult
		move_speed = _base_speed * night_speed_mult
	else:
		detect_radius = _base_detect
		move_speed = _base_speed


## 听觉：NoiseEvent.emit 调用。记住声源位置并开始调查（不区分是否看得见——
## 正在看玩家时视线检测会持续刷新 _last_seen，听到声源位置等价）。
## 新线索会打断当前的游荡/搜索目标。
func hear_noise(pos: Vector2) -> void:
	if health <= 0:
		return
	_last_seen = pos
	_memory_left = MEMORY_TIME
	_wander_point = Vector2.ZERO


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	_memory_left = maxf(0.0, _memory_left - delta)
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node2D
	# 感知节拍要在拿到目标之后：否则首拍永远空跑，要多等一个周期才能看见玩家
	_tick_perception(delta)
	var desired := Vector2.ZERO
	if _target == null:
		velocity = _knockback
		if velocity != Vector2.ZERO:
			move_and_slide()
		return
	if _target.get("dead"):
		velocity = _knockback
		if velocity != Vector2.ZERO:
			move_and_slide()
		return
	if _camp == null:
		_camp = get_tree().get_first_node_in_group("camp")
	if _gate == null:
		_gate = get_tree().get_first_node_in_group("gate")
	var to_target := _target.global_position - global_position
	# 安全区 = 玩家身处屋内且门关着：僵尸放弃追击与攻击（门体同时挡住它）。
	# 门开着僵尸可以追进屋——出门记得关门。
	var target_sheltered: bool = _camp != null and _camp.has_point(_target.global_position) \
			and _gate != null and _gate.closed
	if not target_sheltered and _sees_player:
		_searching = false
		if to_target.length() > attack_range:
			desired = _nav_dir_to(_target.global_position, to_target.normalized()) * move_speed
		elif _attack_timer <= 0.0:
			_perform_attack()
	elif not target_sheltered and _memory_left > 0.0:
		# 失去视线 / 听到声音：先走到最后目击点；到了就地小范围搜索，
		# 记忆耗尽后落入下面的游荡分支恢复自主活动。
		var to_memory := _last_seen - global_position
		if to_memory.length() > INVESTIGATE_ARRIVE_DIST:
			_searching = false
			_wander_point = Vector2.ZERO  # 直奔目击点，不继续走旧的游荡点
			desired = _nav_dir_to(_last_seen, to_memory.normalized()) * move_speed
		else:
			if not _searching:  # 刚到达目击点：保证最短搜索时长
				_searching = true
				_memory_left = maxf(_memory_left, SEARCH_MIN_TIME)
			desired = _wander_step(delta, _last_seen, SEARCH_RADIUS)
	elif can_wander and detect_radius > 0.0:
		_searching = false
		# 无目标无线索：在附近自主游荡（慢速、随机停顿、导航约束不穿墙；
		# detect_radius <= 0 视为"瘫痪"，测试用它定身丧尸）
		desired = _wander_step(delta, global_position, WANDER_RADIUS_MAX)
	_log_ai_state()
	velocity = desired + _knockback
	if velocity != Vector2.ZERO:
		move_and_slide()


## 感知节拍：定期做一次"距离 + 视线遮挡"检测，刷新看得见/记忆状态。
func _tick_perception(delta: float) -> void:
	_perception_timer -= delta
	if _perception_timer > 0.0:
		return
	_perception_timer = PERCEPTION_INTERVAL
	if _target == null or not is_instance_valid(_target) or _target.get("dead"):
		_sees_player = false
		return
	var to_target := _target.global_position - global_position
	if to_target.length() > detect_radius or not _has_line_of_sight():
		if _sees_player:
			# 刚失去视线：丢弃旧游荡点，改以最后目击点为基准搜索
			_wander_point = Vector2.ZERO
		_sees_player = false
		return
	_sees_player = true
	_last_seen = _target.global_position
	_memory_left = MEMORY_TIME


## 视线射线：从自身到目标，只检测静态障碍层（玩家/同类不挡视线）。
func _has_line_of_sight() -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			global_position, _target.global_position, SIGHT_MASK, [get_rid()])
	return space.intersect_ray(query).is_empty()


## 沿导航路径走向 point 的方向；导航不可用（无烘焙地图/路径未就绪）时
## 退化为直线方向 fallback_dir——保证任何场景下都不会原地卡死。
## 目标与上次相同则不重设，避免每帧触发无谓的路径重算。
func _nav_dir_to(point: Vector2, fallback_dir: Vector2) -> Vector2:
	if _nav_ready():
		if _nav.target_position != point:
			_nav.target_position = point
		var next := _nav.get_next_path_position()
		var step := next - global_position
		if step.length_squared() > 1.0:
			return step.normalized()
	return fallback_dir


## 游荡/搜索共用的步进逻辑，返回本帧期望速度：
## 无目标点时围绕 center 随机选一个导航可达的点 → 走过去 →
## 到达后随机停顿 → 再选下一个。center 传最后目击点 = 就地搜索，
## 传自身位置 = 自主游荡（目标点随移动漂移，行为更自然）。
func _wander_step(delta: float, center: Vector2, radius: float) -> Vector2:
	if _wander_wait > 0.0:  # 停顿中：原地发呆
		_wander_wait -= delta
		return Vector2.ZERO
	if _wander_point == Vector2.ZERO:  # 选一个新目标点
		_wander_point = _pick_wander_point(center, radius)
		_wander_walked = 0.0
		if _wander_point == Vector2.ZERO:  # 周围都不可达：歇一拍再选
			_wander_wait = randf_range(WANDER_WAIT_MIN, WANDER_WAIT_MAX)
			return Vector2.ZERO
	var to_point := _wander_point - global_position
	if to_point.length() <= WANDER_ARRIVE_DIST:  # 到达：停顿，随后换新点
		_wander_point = Vector2.ZERO
		_wander_wait = randf_range(WANDER_WAIT_MIN, WANDER_WAIT_MAX)
		return Vector2.ZERO
	_wander_walked += delta
	if _wander_walked > WANDER_STUCK_TIME:  # 走了太久（被卡/不可达）：放弃重选
		_wander_point = Vector2.ZERO
		return Vector2.ZERO
	return _nav_dir_to(_wander_point, to_point.normalized()) * move_speed * WANDER_SPEED_RATIO


## 围绕 center 随机挑一个导航可达的游荡点（最多试 6 次）；挑不到返回 ZERO。
## 可达性由导航网格把关——墙外、关着的门后、地图外的点都不可达，自然被排除。
func _pick_wander_point(center: Vector2, radius: float) -> Vector2:
	if not _nav_ready():
		return Vector2.ZERO
	for i in 6:
		var candidate := center \
				+ Vector2.RIGHT.rotated(randf() * TAU) * randf_range(WANDER_RADIUS_MIN, radius)
		_nav.target_position = candidate
		_nav.get_next_path_position()  # 触发一次路径计算
		if _nav.is_target_reachable():
			return candidate
	return Vector2.ZERO


## 当前行为状态名（调试与测试用）。
func _ai_state() -> String:
	if _sees_player:
		return "CHASE"
	if _memory_left > 0.0:
		return "SEARCH" if _searching else "INVESTIGATE"
	if _wander_point != Vector2.ZERO or _wander_wait > 0.0:
		return "WANDER"
	return "IDLE"


## 状态切换时打一行日志；debug_ai 不开时零开销。
func _log_ai_state() -> void:
	if not debug_ai:
		return
	var state := _ai_state()
	if state != _logged_state:
		_logged_state = state
		print("[AI] %s -> %s @ %v" % [name, state, global_position])


## 导航地图是否已烘焙并同步（裸测试场景里没有导航区域，返回 false）。
func _nav_ready() -> bool:
	return _nav != null \
			and NavigationServer2D.map_get_iteration_id(_nav.get_navigation_map()) > 0


## 执行一次近战攻击（子类可 override 换成蓄力/连击等变体攻击）。
func _perform_attack() -> void:
	_attack_timer = attack_cooldown
	if _target != null and _target.has_method("take_damage"):
		_target.call("take_damage", damage, (_target.global_position - global_position).normalized())


func take_damage(amount: int, from_direction := Vector2.ZERO) -> void:
	if health <= 0:
		return
	health -= amount
	_knockback = from_direction.normalized() * knockback_force
	_flash()
	var host := get_tree().current_scene
	if host != null:
		FloatingText.spawn(host, global_position, "-%d" % amount, Color(1.0, 0.92, 0.55))
	# 受击惨叫：惊动周围的同类（它们不知道玩家在哪，只知道同伴出事的位置）
	NoiseEvent.emit(self, global_position, NoiseEvent.SCREAM_LOUDNESS)
	if health <= 0:
		_die()


func _die() -> void:
	var host := get_tree().current_scene
	if host != null:
		var effect := DeathEffect.new()
		if variant != null:
			effect.color = variant.color
		host.add_child(effect)
		effect.global_position = global_position
	queue_free()


func _flash() -> void:
	_visual.modulate = Color(4.0, 1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0), 0.15)
