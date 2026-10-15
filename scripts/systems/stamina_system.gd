class_name StaminaSystem
extends Node
## 精力（短期行动资源）与疲劳（长期负担）系统。
## - 精力：奔跑/近战等行动消耗，静止/安全屋休息恢复；耗尽后不能奔跑、不能近战。
## - 疲劳：随游戏时间积累，睡眠消除；疲劳抬高会压低精力上限并带来阶段惩罚。
## 惩罚通过修正值**读取时计算**（recovery_mult / cooldown_mult / hit_miss_chance），
## 从不直接改写玩家的基础移速、攻击冷却等属性；暂停期间 _process 不运行，自动不累计。
## 所有平衡参数集中在下方常量区，方便后续调平衡。

## 疲劳进入新阶段时发出（跨过 25/50/75 阈值或回落），参数为阶段名。
signal fatigue_stage_changed(label: String)

# —— 平衡参数（集中配置）—————————————————————————————
const STAMINA_MAX_BASE := 100.0
const STAMINA_CAP_MIN := 40.0      # 疲劳 100 时的精力上限下限
const FATIGUE_CAP_FACTOR := 0.6    # 精力上限 = max(40, 100 - 0.6×疲劳)
const FATIGUE_MAX := 100.0
const RUN_COST_PER_SEC := 8.0      # 奔跑每秒消耗精力
const MELEE_COST := 8.0            # 每次近战攻击消耗精力
# 扩展预留（当前无对应动作，不为它们开发行为）：
# 新动作实现时调用 try_spend(COST_CLIMB) 即可接入同一套结算。
const COST_CLIMB := 12.0           # 翻越障碍（预留）
const COST_DASH := 15.0            # 闪避/冲刺（预留）
const REST_REGEN_PER_SEC := 10.0   # 普通静止休息每秒恢复
const CAMP_REGEN_PER_SEC := 15.0   # 安全屋内每秒恢复
const SPRINT_SPEED_MULT := 1.5     # 奔跑移速倍率
const FATIGUE_PER_DAY := 20.0      # 每游戏日自然增长的疲劳（按游戏时间计）
const FATIGUE_RUN_BONUS_PER_SEC := 0.05   # 奔跑时的额外疲劳
const FATIGUE_PER_MELEE := 0.5     # 每次近战的额外疲劳
const SLEEP_RELIEF_PER_HOUR := 8.0 # 每睡 1 游戏小时降低的疲劳（8h=-64）

## 一个游戏日的现实秒数；由 main.gd 按 DayNight 配置注入，
## 改昼夜时长后疲劳速率自动跟随，禁止用现实时间累计疲劳。
var day_seconds := 600.0

var stamina := STAMINA_MAX_BASE
var fatigue := 0.0

var _stage := 0

## 疲劳阶段表：阈值起、阶段名、精力恢复倍率、攻击冷却倍率（>1=变慢）、攻击落空概率。
## 按任务书：轻度 -10% 恢复；严重 -25% 恢复 +10% 落空；极度 -50% 恢复 +25% 落空 +25% 攻速降。
const STAGES: Array[Dictionary] = [
	{"min": 0, "label": "正常", "recovery_mult": 1.0, "cooldown_mult": 1.0, "miss_chance": 0.0},
	{"min": 25, "label": "轻度疲劳", "recovery_mult": 0.9, "cooldown_mult": 1.0, "miss_chance": 0.0},
	{"min": 50, "label": "严重疲劳", "recovery_mult": 0.75, "cooldown_mult": 1.0, "miss_chance": 0.10},
	{"min": 75, "label": "极度疲劳", "recovery_mult": 0.5, "cooldown_mult": 1.3333, "miss_chance": 0.25},
]


## —— 查询（惩罚统一从这里读，基础属性不被改写）——————————

## 动态精力上限：max(40, 100 - 0.6×疲劳)。
func max_stamina() -> float:
	return maxf(STAMINA_CAP_MIN, STAMINA_MAX_BASE - FATIGUE_CAP_FACTOR * fatigue)


func stage() -> Dictionary:
	var current: Dictionary = STAGES[0]
	for s in STAGES:
		if fatigue >= float(s.min):
			current = s
	return current


func stage_label() -> String:
	return str(stage().label)


func recovery_mult() -> float:
	return float(stage().recovery_mult)


## 攻击冷却倍率：极度疲劳 1.3333 → 冷却变长 33% = 攻速 -25%。
func attack_cooldown_mult() -> float:
	return float(stage().cooldown_mult)


## 现有战斗为范围判定必中；疲劳的"命中率下降"映射为攻击落空概率（一次 randf 判定）。
func hit_miss_chance() -> float:
	return float(stage().miss_chance)


func can_sprint() -> bool:
	return stamina > 0.5  # 小阈值防止 0 附近反复横跳


## 睡眠预计恢复的疲劳量（UI 预览用）。
func sleep_relief_preview(hours: float) -> float:
	return minf(fatigue, hours * SLEEP_RELIEF_PER_HOUR)


## —— 状态变化 ——————————————————————————————————

func set_fatigue(value: float) -> void:
	fatigue = clampf(value, 0.0, FATIGUE_MAX)
	# 精力上限随疲劳变化；上限降低只 clamp 当前值，不额外产生消耗
	stamina = minf(stamina, max_stamina())
	var s := _stage_index()
	if s != _stage:
		_stage = s
		fatigue_stage_changed.emit(stage_label())


func add_fatigue(amount: float) -> void:
	set_fatigue(fatigue + amount)


## 每帧结算：疲劳随游戏时间增长 + 奔跑消耗 / 休息恢复。
## delta 是游戏时间（暂停时本函数不被调用），in_camp 用于安全屋恢复档位。
func tick(delta: float, sprinting: bool, in_camp: bool) -> void:
	var fatigue_rate := FATIGUE_PER_DAY / day_seconds
	if sprinting:
		fatigue_rate += FATIGUE_RUN_BONUS_PER_SEC
	set_fatigue(fatigue + fatigue_rate * delta)
	if sprinting:
		stamina = maxf(0.0, stamina - RUN_COST_PER_SEC * delta)
	else:
		var regen := CAMP_REGEN_PER_SEC if in_camp else REST_REGEN_PER_SEC
		stamina = minf(max_stamina(), stamina + regen * recovery_mult() * delta)


## 消耗精力；不足时返回 false（不部分消耗）。
func try_spend(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	return true


## 近战攻击：消耗精力并积累疲劳；精力不足返回 false（玩家不能挥击）。
func try_melee() -> bool:
	if not try_spend(MELEE_COST):
		return false
	add_fatigue(FATIGUE_PER_MELEE)
	return true


## 睡眠每游戏小时结算一次：疲劳降低、精力回满。返回实际降低量。
func sleep_settle() -> float:
	var relieved := minf(fatigue, SLEEP_RELIEF_PER_HOUR)
	set_fatigue(fatigue - SLEEP_RELIEF_PER_HOUR)
	stamina = max_stamina()
	return relieved


## 精力回满（复活/调试用）；keep_fatigue 为 true 时保留疲劳（复活场景）。
func refill(keep_fatigue := false) -> void:
	if not keep_fatigue:
		set_fatigue(0.0)
	stamina = max_stamina()


func _stage_index() -> int:
	for i in range(STAGES.size() - 1, -1, -1):
		if fatigue >= float(STAGES[i].min):
			return i
	return 0
