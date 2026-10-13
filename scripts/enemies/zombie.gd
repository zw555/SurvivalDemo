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
## —— 寻路 ——
var _nav: NavigationAgent2D

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
func hear_noise(pos: Vector2) -> void:
	if health <= 0:
		return
	_last_seen = pos
	_memory_left = MEMORY_TIME


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
		if to_target.length() > attack_range:
			desired = _nav_dir_to(_target.global_position, to_target.normalized()) * move_speed
		elif _attack_timer <= 0.0:
			_perform_attack()
	elif not target_sheltered and _memory_left > 0.0:
		# 失去视线：前往最后目击/声源点调查，到了就原地放弃。
		var to_memory := _last_seen - global_position
		if to_memory.length() > INVESTIGATE_ARRIVE_DIST:
			desired = _nav_dir_to(_last_seen, to_memory.normalized()) * move_speed
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
func _nav_dir_to(point: Vector2, fallback_dir: Vector2) -> Vector2:
	if _nav_ready():
		_nav.target_position = point
		var next := _nav.get_next_path_position()
		var step := next - global_position
		if step.length_squared() > 1.0:
			return step.normalized()
	return fallback_dir


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
