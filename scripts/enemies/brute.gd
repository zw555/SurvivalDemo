class_name Brute
extends Zombie
## 重型变异体（撤离路线的最终威胁）。复用 Zombie 的追击/受击/死亡/飘字，
## 只在攻击方式上扩展，全部攻击都有明显前摇、可以走位躲开：
## - 蓄力重击：每第 3 次普攻改为重击——0.8 秒前摇（原地发抖 + 闪橙），
##   之后砸向锁定方向 100px 扇形，伤害 30。看到前摇走开即可。
## - 冲撞：玩家在 160~420px 且冷却好时触发——0.9 秒前摇后沿锁定方向
##   直线冲刺，命中 30 伤 + 大击退，撞墙提前停下。侧移躲避。
## - 狂暴：生命低于 45% 时移速/攻速提升、身体变暗红（一次性，给玩家反应时间）。

enum State { NORMAL, SLAM_WINDUP, CHARGE_WINDUP, CHARGING }

const SLAM_WINDUP_TIME := 0.8
const SLAM_RANGE := 100.0
const SLAM_DAMAGE := 30
const SLAM_EVERY_N_ATTACKS := 3
const CHARGE_WINDUP_TIME := 0.9
const CHARGE_SPEED := 320.0
const CHARGE_TIME := 0.55
const CHARGE_DAMAGE := 30
const CHARGE_MIN_DIST := 160.0
const CHARGE_MAX_DIST := 420.0
const CHARGE_COOLDOWN := 10.0
const ENRAGE_HEALTH_RATIO := 0.45
const ENRAGE_SPEED_MULT := 1.35
const ENRAGE_COOLDOWN := 0.7

var _state := State.NORMAL
var _melee_count := 0
var _windup_left := 0.0
var _charge_left := 0.0
var _aim_dir := Vector2.RIGHT  # 前摇开始时锁定的方向
var _charge_cd := 3.0  # 开局短冷却，避免玩家刚接近就被撞
var _charge_hit := false
var _enraged := false
var _wobble_accum := 0.0


func _ready() -> void:
	super()
	attack_cooldown = 1.2  # 普攻比小怪慢：绕背/走位的机会


func _physics_process(delta: float) -> void:
	_charge_cd = maxf(0.0, _charge_cd - delta)
	match _state:
		State.SLAM_WINDUP, State.CHARGE_WINDUP:
			_tick_windup(delta)
		State.CHARGING:
			_tick_charge(delta)
		_:
			_try_start_charge()
			super._physics_process(delta)


## 前摇阶段：原地发抖（视觉预警），倒计时结束执行对应攻击。
func _tick_windup(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_knockback = _knockback.move_toward(Vector2.ZERO, knockback_decay * delta)
	velocity = _knockback
	if velocity != Vector2.ZERO:
		move_and_slide()
	_wobble_accum += delta
	_visual.offset = Vector2(randf_range(-2, 2), randf_range(-2, 2)) * 3.0
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_visual.offset = Vector2.ZERO
	if _state == State.SLAM_WINDUP:
		_release_slam()
	else:
		_state = State.CHARGING
		_charge_left = CHARGE_TIME
		_charge_hit = false


## 冲刺阶段：直线冲，命中玩家或撞墙/超时结束。
func _tick_charge(delta: float) -> void:
	_charge_left -= delta
	velocity = _aim_dir * CHARGE_SPEED
	move_and_slide()
	if not _charge_hit and _target != null and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		if to_target.length() <= 34.0:
			_charge_hit = true
			_target.call("take_damage", CHARGE_DAMAGE, _aim_dir)
			_knockback = Vector2.ZERO  # 命中后立即停，不让玩家被连续判定
			_end_charge()
			return
	if get_slide_collision_count() > 0 or _charge_left <= 0.0:
		_end_charge()


func _end_charge() -> void:
	_state = State.NORMAL
	_charge_cd = CHARGE_COOLDOWN


## 中距离冲撞触发：目标有效、看得见（有视线）、没躲在关门的屋里、
## 冷却好了、距离合适——隔墙时它不知道玩家在哪，不会隔空撞墙。
func _try_start_charge() -> void:
	if _charge_cd > 0.0 or _target == null or not is_instance_valid(_target):
		return
	if _target.get("dead") or not _sees_player:
		return
	var camp: Node = get_tree().get_first_node_in_group("camp")
	var gate: Node = get_tree().get_first_node_in_group("gate")
	if camp != null and camp.has_point(_target.global_position) \
			and gate != null and gate.closed:
		return
	var to_target := _target.global_position - global_position
	if to_target.length() < CHARGE_MIN_DIST or to_target.length() > CHARGE_MAX_DIST:
		return
	_aim_dir = to_target.normalized()
	_state = State.CHARGE_WINDUP
	_windup_left = CHARGE_WINDUP_TIME
	_visual.modulate = Color(2.2, 2.2, 2.2)  # 闪白预警
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0), CHARGE_WINDUP_TIME)


## 普攻计数：每第 3 次改为蓄力重击（其余沿用父类普攻）。
func _perform_attack() -> void:
	if _state != State.NORMAL:
		return
	_melee_count += 1
	if _melee_count % SLAM_EVERY_N_ATTACKS == 0 \
			and _target != null and is_instance_valid(_target):
		_aim_dir = (_target.global_position - global_position).normalized()
		_state = State.SLAM_WINDUP
		_windup_left = SLAM_WINDUP_TIME
		_visual.modulate = Color(2.5, 1.4, 0.3)  # 闪橙预警
		var tween := create_tween()
		tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0), SLAM_WINDUP_TIME)
	else:
		super._perform_attack()


## 蓄力重击释放：砸向锁定方向的扇形（前摇期间玩家走开就打空）。
func _release_slam() -> void:
	_state = State.NORMAL
	_attack_timer = attack_cooldown
	var host := get_tree().current_scene
	if host != null:  # 砸地震屏（无论是否命中，给玩家反馈）
		if host.has_method("hit_stop"):
			host.call("hit_stop")
	if _target == null or not is_instance_valid(_target):
		return
	var to_target := _target.global_position - global_position
	if to_target.length() <= SLAM_RANGE \
			and absf(_aim_dir.angle_to(to_target)) <= deg_to_rad(70.0):
		_target.call("take_damage", SLAM_DAMAGE, to_target.normalized())


## 低血狂暴：加移速加攻速、变暗红。改 _base_speed 保证夜晚加成仍然成立。
func take_damage(amount: int, from_direction := Vector2.ZERO) -> void:
	super.take_damage(amount, from_direction)
	if not _enraged and health > 0 \
			and health <= float(max_health) * ENRAGE_HEALTH_RATIO:
		_enraged = true
		_base_speed *= ENRAGE_SPEED_MULT
		# 不能走 set_night_buffed：同值会被 early-return 挡住，直接按昼夜状态重算
		move_speed = _base_speed * (night_speed_mult if _night_buffed else 1.0)
		attack_cooldown = ENRAGE_COOLDOWN
		_visual.color = Color(0.7, 0.08, 0.08)
