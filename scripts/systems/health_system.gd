class_name HealthSystem
extends Node
## 伤势（Injury）与疾病（Illness）系统：出血 ×2、骨折 + 伤口感染、发热、肠胃疾病。
## 与 StaminaSystem 同一设计模式：
## - 所有惩罚通过「读取时计算的修正值」提供（move_speed_mult / stamina_regen_mult / ...），
##   从不改写玩家基础属性；状态解除即移除修正来源，无残留、无重复叠加。
## - 时间全部走游戏内时间：tick 的 delta 由 _process 传入（暂停自动停），
##   「游戏小时」用 day_night.seconds_per_hour() 折算（睡眠推进时间时疾病/恢复同步推进）。
## - 持续扣血通过 continuous_damage 信号交由玩家结算（死亡判定集中一处）。
## 所有平衡参数集中在常量区；医疗物品规则见 MEDICINE_RULES。

## 持续性扣血（出血 / 重度感染），参数为本次扣血量；由玩家接住并做死亡判定。
signal continuous_damage(amount: float)
## 状态出现 / 恶化 / 缓解 / 治愈提示（text, danger 等级 0 提示 1 警告）。
signal condition_alert(text: String, danger: int)
## 任何状态变化（健康面板刷新依据）。
signal condition_changed

# —— 平衡参数（集中配置）—————————————————————————————
const BLEED_MINOR_DPS := 0.15        # 轻度出血每游戏秒扣血
const BLEED_MINOR_HEAL_HOURS := 6.0  # 轻度出血未处理的自愈时长（结痂）
const BLEED_SEVERE_DPS := 0.6        # 严重出血每游戏秒扣血（不处理可致死）
const BLEED_MINOR_RISK_PER_HOUR := 0.04   # 出血未处理的感染风险累积（每小时）
const BLEED_SEVERE_RISK_PER_HOUR := 0.08
const FRACTURE_DAMAGE_MIN := 18      # 单次伤害 ≥ 该值才可能骨折
const FRACTURE_CHANCE := 0.3         # 重击骨折概率（同一击独立于出血判定）
const FRACTURE_MOVE_MULT := 0.55     # 未固定骨折移速
const FRACTURE_MOVE_SPLINTED := 0.80 # 已固定骨折移速
const FRACTURE_MOVE_PAINKILLER := 0.80  # 止痛药期间未固定骨折的移速（惩罚减半）
const FRACTURE_RUN_COST_MULT := 1.6  # 未固定骨折奔跑精力消耗
const FRACTURE_SPLINTED_RUN_COST := 1.2
const FRACTURE_FATIGUE_MULT := 1.3
const FRACTURE_RECOVER_HOURS := 24.0 # 夹板固定后需要的恢复时长（游戏小时）
const BLEED_CHANCE_NORMAL := 0.3     # 普通受击的轻度出血概率
const BLEED_CHANCE_HEAVY := 0.4      # 重击（伤害 ≥ 25）的严重出血概率
const INFECTION_STAGE_HOURS := 8.0   # 感染每级进展所需游戏小时（无抗生素时恶化）
const ANTIBIOTIC_HOURS_PER_STAGE := 3.0  # 抗生素治疗：每降一级所需游戏小时
const INFECTION_SEVERE_DPS := 0.3    # 重度感染持续扣血
const INFECTION_CAP_PENALTY := [0.0, 0.0, 10.0, 15.0]  # 按阶段：精力上限扣减
const INFECTION_REGEN_MULT := [1.0, 0.85, 0.75, 0.65]  # 按阶段：精力恢复
const INFECTION_FATIGUE_MULT := [1.0, 1.0, 1.4, 1.6]
const INFECTION_MOVE_MULT := [1.0, 1.0, 1.0, 0.85]
const INFECTION_DAMAGE_MULT := [1.0, 1.0, 1.0, 0.85]
const INFECTION_MISS := [0.0, 0.0, 0.0, 0.10]
const FEVER_REGEN_MULT := 0.8
const FEVER_FATIGUE_MULT := 1.25
const FEVER_COOLDOWN_MULT := 1.15
const FEVER_FADE_HOURS := 3.0        # 根因（感染）降至轻度后发热消退时长
const GASTRO_TRIGGER_WATER_ZERO_SEC := 60.0  # 脱水持续该游戏秒数触发肠胃疾病
const GASTRO_STAGE_HOURS := 6.0      # 脱水持续时 stage1→2 的时长
const GASTRO_RECOVER_HOURS := 5.0    # 水分充足（或补液后）的恢复时长
const GASTRO_WATER_DRAIN_MULT := 1.5
const GASTRO_FOOD_DRAIN_MULT := 1.2
const GASTRO_REGEN_MULT := [1.0, 0.85, 0.7]
const GASTRO_MOVE_MULT := [1.0, 1.0, 0.85]
const GASTRO_FATIGUE_MULT := [1.0, 1.0, 1.4]
const PAINKILLER_HOURS := 1.0        # 止痛药效时长（游戏小时）
const FEVER_MED_HOURS := 2.0         # 退热药效时长
const ANTISEPTIC_GUARD_HOURS := 6.0  # 消毒后防感染累积时长

## 医疗物品规则（id -> 用途）；效果实现见 apply_medicine()。
## 集中于此，禁止把药物逻辑散落到物品脚本。
const MEDICINE_RULES := {
	"med_bandage": "止血：轻度出血直接处理；严重出血仅降级为轻度（有限缓解）",
	"med_splint": "骨折固定：移动惩罚减轻，固定 24 游戏小时后痊愈",
	"med_firstaid": "急救：生命 +70，可止住严重出血",
	"med_antiseptic": "伤口消毒：清除感染风险累积，6 游戏小时内伤口不会积累感染风险",
	"med_antibiotic": "抗感染：治疗伤口感染，约 9 游戏小时逐步痊愈；对骨折/出血/发热无效",
	"med_painkiller": "止痛：1 游戏小时内骨折等行动惩罚减半（不治疗伤势本身）",
	"med_fever": "退热：2 游戏小时内缓解发热惩罚（不治愈根源感染）",
	"med_rehydration": "补液：饮水 +40，加速肠胃疾病的恢复",
}

var day_night: DayNight  ## 由 main.gd 注入；折算游戏小时用
## 伤势：bleed_minor / bleed_severe（存在即生效）；fracture = {splinted, recover_left}
var injuries := {}
## 疾病：infection = {stage, treat_progress}；fever = {}；gastro = {stage}
var illnesses := {}
## 药效剩余（游戏秒）。
var painkiller_left := 0.0
var fever_med_left := 0.0
var antiseptic_guard_left := 0.0
## 感染风险累积 0..1（出血未处理时上升，消毒清零）。
var infection_risk := 0.0

var _water_zero_accum := 0.0   # 脱水累积计时（肠胃疾病触发条件）
var _fever_fade_left := 0.0    # 发热消退倒计时（游戏小时）
var _gastro_recover_left := 0.0
var _prev_stages := {}         # 提示用：上一帧各状态快照


func _ready() -> void:
	name = "HealthSystem"


func _hour_seconds() -> float:
	return day_night.seconds_per_hour() if day_night != null else 25.0


## —— 每帧结算（delta 为游戏时间；暂停时本函数不被调用）————————————————

func tick(delta: float, sprinting: bool, water_empty: bool) -> void:
	var changed := false
	# 脱水累积（肠胃疾病触发/恶化的依据；补水即清零）
	_water_zero_accum = _water_zero_accum + delta if water_empty else 0.0
	# 药效倒计时
	for key in ["painkiller_left", "fever_med_left", "antiseptic_guard_left"]:
		if get(key) > 0.0:
			set(key, maxf(0.0, get(key) - delta))
			changed = true
	# 出血：持续扣血 + 感染风险累积 + 轻度自愈
	var bleeding := false
	if injuries.has("bleed_minor"):
		bleeding = true
		var left: float = _hour_seconds() * BLEED_MINOR_HEAL_HOURS
		injuries.bleed_minor.left = maxf(0.0, float(injuries.bleed_minor.get("left", left)) - delta)
		if injuries.bleed_minor.left <= 0.0:
			injuries.erase("bleed_minor")
			condition_alert.emit("伤口结痂了，轻度出血已停止。", 0)
	if injuries.has("bleed_minor"):
		continuous_damage.emit(BLEED_MINOR_DPS * delta)
	if injuries.has("bleed_severe"):
		bleeding = true
		continuous_damage.emit(BLEED_SEVERE_DPS * delta)
	if bleeding and antiseptic_guard_left <= 0.0:
		var rate := (BLEED_SEVERE_RISK_PER_HOUR if injuries.has("bleed_severe")
				else BLEED_MINOR_RISK_PER_HOUR) * delta / _hour_seconds()
		if not illnesses.has("infection"):
			infection_risk = minf(1.0, infection_risk + rate)
			if infection_risk >= 1.0:
				_start_infection()
				changed = true
	# 重度感染持续扣血
	if illnesses.has("infection") and int(illnesses.infection.stage) >= 3:
		continuous_damage.emit(INFECTION_SEVERE_DPS * delta)
	# 感染进展 / 抗生素治疗
	if illnesses.has("infection"):
		changed = _tick_infection(delta) or changed
	# 发热出现 / 消退
	changed = _tick_fever(delta) or changed
	# 肠胃疾病：脱水触发 / 恢复
	changed = _tick_gastro(delta, sprinting) or changed
	# 骨折恢复推进（固定后）
	if injuries.has("fracture") and bool(injuries.fracture.splinted):
		injuries.fracture.recover_left = maxf(0.0,
				float(injuries.fracture.recover_left) - delta / _hour_seconds())
		if injuries.fracture.recover_left <= 0.0:
			injuries.erase("fracture")
			condition_alert.emit("骨折已经恢复，行动轻松多了。", 0)
			changed = true
	# 恶化警告（严重出血持续存在时提醒一次）
	if injuries.has("bleed_severe") and not _prev_stages.get("warned_severe", false):
		_prev_stages.warned_severe = true
		condition_alert.emit("严重出血！生命持续流失，需要急救包！", 1)
	elif not injuries.has("bleed_severe"):
		_prev_stages.warned_severe = false
	if changed:
		condition_changed.emit()


func _tick_infection(delta: float) -> bool:
	var inf: Dictionary = illnesses.infection
	var changed := false
	if bool(inf.get("treating", false)):
		inf.treat_progress = float(inf.treat_progress) + delta / _hour_seconds()
		if inf.treat_progress >= ANTIBIOTIC_HOURS_PER_STAGE:
			inf.treat_progress = 0.0
			inf.stage = int(inf.stage) - 1
			changed = true
			if int(inf.stage) <= 0:
				illnesses.erase("infection")
				infection_risk = 0.0
				condition_alert.emit("感染已经痊愈。", 0)
			else:
				condition_alert.emit("抗生素起效了，感染减轻（%s）。" % infection_label(), 0)
	else:
		inf.treat_progress = float(inf.treat_progress) + delta / _hour_seconds()
		if inf.treat_progress >= INFECTION_STAGE_HOURS:
			inf.treat_progress = 0.0
			if int(inf.stage) < 3:
				inf.stage = int(inf.stage) + 1
				condition_alert.emit("伤口感染恶化了！（%s）尽快用抗生素。"
						% infection_label(), 1)
				changed = true
			# 重度后不再升级，但持续扣血
	return changed


func _tick_fever(delta: float) -> bool:
	var changed := false
	var infected := illnesses.has("infection") and int(illnesses.infection.stage) >= 2
	if infected and not illnesses.has("fever"):
		illnesses["fever"] = {}
		condition_alert.emit("你发起了低烧，浑身没劲。", 1)
		changed = true
	elif not infected and illnesses.has("fever"):
		# 根因感染降到轻度后退热倒计时
		_fever_fade_left = _fever_fade_left if _fever_fade_left > 0.0 \
				else FEVER_FADE_HOURS
		_fever_fade_left -= delta / _hour_seconds()
		if _fever_fade_left <= 0.0:
			illnesses.erase("fever")
			_fever_fade_left = 0.0
			condition_alert.emit("烧退了。", 0)
			changed = true
	return changed


func _tick_gastro(delta: float, _sprinting: bool) -> bool:
	var changed := false
	if not illnesses.has("gastro"):
		# 脱水（饮水归零）累积触发——现有系统里真实存在的游戏事件
		if _water_zero_accum >= GASTRO_TRIGGER_WATER_ZERO_SEC:
			illnesses["gastro"] = {"stage": 1}
			_water_zero_accum = 0.0
			_gastro_recover_left = 0.0
			condition_alert.emit("长时间缺水，你开始上吐下泻……（肠胃疾病）", 1)
			return true
		return false
	var gastro: Dictionary = illnesses.gastro
	var stage := int(gastro.stage)
	if _water_zero_accum >= GASTRO_STAGE_HOURS * _hour_seconds() and stage < 2:
		gastro.stage = 2
		condition_alert.emit("肠胃疾病加重了！尽快补水并休息。", 1)
		changed = true
	elif _water_zero_accum <= 0.0:
		# 水分充足：恢复推进（补液用品直接给大半进度）
		_gastro_recover_left = _gastro_recover_left if _gastro_recover_left > 0.0 \
				else GASTRO_RECOVER_HOURS
		_gastro_recover_left -= delta / _hour_seconds()
		if _gastro_recover_left <= 0.0:
			illnesses.erase("gastro")
			_gastro_recover_left = 0.0
			condition_alert.emit("肠胃舒服多了，肠胃疾病已痊愈。", 0)
			changed = true
	return changed


func _start_infection() -> void:
	illnesses["infection"] = {"stage": 1, "treat_progress": 0.0}
	infection_risk = 0.0
	condition_alert.emit("伤口感染了！（轻度）用消毒剂可预防，抗生素可治疗。", 1)


## —— 受击结算（由 player.take_damage 调用；final_damage 为护甲后的实际伤害）——

func on_damaged(final_damage: int, heavy: bool) -> void:
	# 出血：普通攻击轻度出血；重击（伤害 ≥25）更高概率严重出血
	if heavy and randf() < BLEED_CHANCE_HEAVY:
		if not injuries.has("bleed_severe"):
			injuries["bleed_severe"] = {}
			condition_alert.emit("伤口很深，严重出血！需要急救包！", 1)
			condition_changed.emit()
	elif randf() < BLEED_CHANCE_NORMAL and not injuries.has("bleed_minor") \
			and not injuries.has("bleed_severe"):
		injuries["bleed_minor"] = {"left": _hour_seconds() * BLEED_MINOR_HEAL_HOURS}
		condition_alert.emit("你在流血……用绷带止血。", 0)
		condition_changed.emit()
	# 骨折：重击（伤害 ≥18）概率触发
	if final_damage >= FRACTURE_DAMAGE_MIN and randf() < FRACTURE_CHANCE \
			and not injuries.has("fracture"):
		injuries["fracture"] = {"splinted": false,
				"recover_left": FRACTURE_RECOVER_HOURS}
		condition_alert.emit("剧痛！你感觉骨头裂了……（骨折）用夹板固定！", 1)
		condition_changed.emit()


## —— 医疗物品（返回消耗提示文本；"" = 不适用未消耗）——————————————————

func apply_medicine(item: ItemData) -> String:
	match item.id:
		"med_bandage":
			if injuries.has("bleed_minor"):
				injuries.erase("bleed_minor")
				return "绷带扎紧了伤口，轻度出血已止住。"
			if injuries.has("bleed_severe"):
				injuries.erase("bleed_severe")
				injuries["bleed_minor"] = {"left": _hour_seconds() * BLEED_MINOR_HEAL_HOURS}
				return "绷带只能暂时压住严重的出血——伤口还在渗血（降为轻度），尽快找急救包！"
			return ""
		"med_firstaid":
			var stopped := ""
			if injuries.has("bleed_severe"):
				injuries.erase("bleed_severe")
				stopped = "严重出血已止住；"
			elif injuries.has("bleed_minor"):
				injuries.erase("bleed_minor")
				stopped = "出血已止住；"
			return ("%s生命恢复了不少。" % stopped) if stopped != "" else ""
		"med_splint":
			if injuries.has("fracture") and not bool(injuries.fracture.splinted):
				injuries.fracture.splinted = true
				return ("夹板固定好了：行动方便了些，还需要约 %d 游戏小时静养。"
						% int(FRACTURE_RECOVER_HOURS))
			return ""
		"med_antiseptic":
			if infection_risk > 0.0 or antiseptic_guard_left > 0.0 \
					or injuries.has("bleed_minor") or injuries.has("bleed_severe"):
				infection_risk = 0.0
				antiseptic_guard_left = _hour_seconds() * ANTISEPTIC_GUARD_HOURS
				return "伤口消毒完毕：感染风险已清除，短期内伤口不会积累感染。"
			return ""
		"med_antibiotic":
			if illnesses.has("infection") \
					and not bool(illnesses.infection.get("treating", false)):
				illnesses.infection.treating = true
				return "开始服用抗生素：感染会逐步减轻（无需再次服用）。"
			return ""
		"med_painkiller":
			if painkiller_left > 0.0:
				return ""
			if injuries.has("fracture"):
				painkiller_left = _hour_seconds() * PAINKILLER_HOURS
				return "疼痛缓解了（%d 游戏小时内行动惩罚减半）——伤还没好，别硬撑。" % int(PAINKILLER_HOURS)
			return ""
		"med_fever":
			if fever_med_left > 0.0:
				return ""
			if illnesses.has("fever"):
				fever_med_left = _hour_seconds() * FEVER_MED_HOURS
				return "退烧药起效了（%d 游戏小时内症状缓解）——根子上的感染还得靠抗生素。" % int(FEVER_MED_HOURS)
			return ""
		"med_rehydration":
			return "rehydration"  # 特殊：需要同时补水，由 player.use_item 处理
	return ""


## 补液用品的疾病部分（由 player 在补水后调用）。
func apply_rehydration() -> String:
	if illnesses.has("gastro"):
		_gastro_recover_left = maxf(_gastro_recover_left,
				GASTRO_RECOVER_HOURS * 0.6)
		return "补液缓解了脱水症状，恢复快了一些。"
	return ""


## 睡眠每游戏小时结算：出血/感染扣血、疾病进展、药效消耗与实时规则一致。
## 返回该小时的持续扣血量（由调用方一次性应用，避免重复结算）。
func sleep_hour() -> float:
	var bleed := 0.0
	if injuries.has("bleed_minor"):
		bleed += BLEED_MINOR_DPS * _hour_seconds()
		injuries.bleed_minor.left = float(injuries.bleed_minor.get("left", 0.0)) - _hour_seconds()
		if injuries.bleed_minor.left <= 0.0:
			injuries.erase("bleed_minor")
			condition_alert.emit("睡梦中伤口结痂了，轻度出血已停止。", 0)
	if injuries.has("bleed_severe"):
		bleed += BLEED_SEVERE_DPS * _hour_seconds()
	if illnesses.has("infection") and int(illnesses.infection.stage) >= 3:
		bleed += INFECTION_SEVERE_DPS * _hour_seconds()
	# 疾病进展 / 恢复 / 药效按 1 小时推进
	if illnesses.has("infection"):
		_tick_infection(_hour_seconds())
	_tick_fever(_hour_seconds())
	_tick_gastro(_hour_seconds(), false)
	for key in ["painkiller_left", "fever_med_left", "antiseptic_guard_left"]:
		if get(key) > 0.0:
			set(key, maxf(0.0, get(key) - _hour_seconds()))
	if injuries.has("fracture") and bool(injuries.fracture.splinted):
		injuries.fracture.recover_left = maxf(0.0,
				float(injuries.fracture.recover_left) - 1.0)
		if injuries.fracture.recover_left <= 0.0:
			injuries.erase("fracture")
			condition_alert.emit("静养之后，骨折已经恢复。", 0)
	condition_changed.emit()
	return bleed


## —— 统一修正接口（乘法组合各状态自身声明，绝不改写基础属性）——————————

## 移速倍率：骨折（最明显）> 重度感染 / 重度肠胃；止痛药缓解骨折惩罚。
func move_speed_mult() -> float:
	var mult := 1.0
	if injuries.has("fracture"):
		if bool(injuries.fracture.splinted):
			mult *= FRACTURE_MOVE_SPLINTED
		else:
			mult *= FRACTURE_MOVE_PAINKILLER if painkiller_left > 0.0 \
					else FRACTURE_MOVE_MULT
	if illnesses.has("infection") and int(illnesses.infection.stage) >= 3:
		mult *= INFECTION_MOVE_MULT[3]
	if illnesses.has("gastro"):
		mult *= GASTRO_MOVE_MULT[int(illnesses.gastro.stage)]
	if illnesses.has("fever") and fever_med_left <= 0.0 \
			and illnesses.has("infection") and int(illnesses.infection.stage) >= 3:
		mult *= 0.9  # 高烧+重度感染：行动迟缓
	return mult


## 精力恢复倍率（与疲劳的 recovery_mult 相乘）。
func stamina_regen_mult() -> float:
	var mult := 1.0
	if illnesses.has("infection"):
		mult *= INFECTION_REGEN_MULT[int(illnesses.infection.stage)]
	if illnesses.has("fever"):
		mult *= FEVER_REGEN_MULT if fever_med_left <= 0.0 \
				else lerpf(1.0, FEVER_REGEN_MULT, 0.5)
	if illnesses.has("gastro"):
		mult *= GASTRO_REGEN_MULT[int(illnesses.gastro.stage)]
	return mult


## 精力上限扣减值（重度感染/疾病压上限；StaminaSystem 每次计算时读取）。
func stamina_cap_penalty() -> float:
	if illnesses.has("infection"):
		return INFECTION_CAP_PENALTY[int(illnesses.infection.stage)]
	return 0.0


## 奔跑精力消耗倍率（骨折显著提高；止痛药缓解）。
func run_cost_mult() -> float:
	if injuries.has("fracture"):
		if bool(injuries.fracture.splinted):
			return FRACTURE_SPLINTED_RUN_COST
		if painkiller_left > 0.0:
			return lerpf(1.0, FRACTURE_RUN_COST_MULT, 0.5)
		return FRACTURE_RUN_COST_MULT
	return 1.0


## 疲劳增长倍率（严重疾病加快累积）。
func fatigue_rate_mult() -> float:
	var mult := 1.0
	if injuries.has("fracture") and not bool(injuries.fracture.splinted):
		mult *= FRACTURE_FATIGUE_MULT
	if illnesses.has("infection"):
		mult *= INFECTION_FATIGUE_MULT[int(illnesses.infection.stage)]
	if illnesses.has("fever") and fever_med_left <= 0.0:
		mult *= FEVER_FATIGUE_MULT
	if illnesses.has("gastro"):
		mult *= GASTRO_FATIGUE_MULT[int(illnesses.gastro.stage)]
	return mult


## 攻击伤害倍率（只有重度感染降低；轻度伤势不惩罚）。
func attack_damage_mult() -> float:
	if illnesses.has("infection") and int(illnesses.infection.stage) >= 3:
		return INFECTION_DAMAGE_MULT[3]
	return 1.0


## 攻击冷却倍率（发热降低攻速；止痛药不缓解发热）。
func attack_cooldown_mult() -> float:
	var mult := 1.0
	if illnesses.has("fever") and fever_med_left <= 0.0:
		mult *= FEVER_COOLDOWN_MULT
	return mult


## 攻击落空概率（与疲劳的落空相加；重度感染才影响）。
func hit_miss_chance() -> float:
	if illnesses.has("infection"):
		return INFECTION_MISS[int(illnesses.infection.stage)]
	return 0.0


func water_drain_mult() -> float:
	return GASTRO_WATER_DRAIN_MULT if illnesses.has("gastro") else 1.0


func food_drain_mult() -> float:
	return GASTRO_FOOD_DRAIN_MULT if illnesses.has("gastro") else 1.0


## 睡眠恢复效率（疾病降低睡眠带来的疲劳恢复；已累积的疲劳不因痊愈瞬间消失）。
func sleep_efficiency() -> float:
	var mult := 1.0
	if illnesses.has("infection"):
		mult *= [1.0, 0.9, 0.75, 0.6][int(illnesses.infection.stage)]
	if illnesses.has("fever") and fever_med_left <= 0.0:
		mult *= 0.8
	return mult


## —— 查询 / 展示 ——————————————————————————————————————

func infection_label() -> String:
	if not illnesses.has("infection"):
		return ""
	return ["", "轻度", "中度", "重度"][int(illnesses.infection.stage)]


func gastro_label() -> String:
	if not illnesses.has("gastro"):
		return ""
	return ["", "轻度", "重度"][int(illnesses.gastro.stage)]


## 状态摘要（健康面板 / HUD 提示用）：每行一个状态。
func summary_lines() -> Array[String]:
	var lines: Array[String] = []
	if injuries.has("bleed_minor"):
		lines.append("轻度出血 · 持续失血（绷带可止血，会自愈）")
	if injuries.has("bleed_severe"):
		lines.append("严重出血 · 危险！持续大量失血（需要急救包）")
	if injuries.has("fracture"):
		var f: Dictionary = injuries.fracture
		if bool(f.splinted):
			lines.append("骨折（已固定）· 移动不便，静养 %d 小时后恢复"
					% ceili(float(f.recover_left)))
		else:
			lines.append("骨折 · 移动严重受限（用夹板固定）")
	if illnesses.has("infection"):
		var t := " · 抗生素治疗中" \
				if bool(illnesses.infection.get("treating", false)) else ""
		lines.append("伤口感染（%s）%s · %s" % [infection_label(), t, _infection_hint()])
	if illnesses.has("fever"):
		lines.append("发热 · 精力恢复下降、疲劳加快（退热药缓解；根源是感染）")
	if illnesses.has("gastro"):
		lines.append("肠胃疾病（%s）· 水分消耗加快（补水 + 补液用品）"
				% gastro_label())
	if infection_risk > 0.3:
		lines.append("伤口有感染风险（%.0f%%）· 用消毒剂处理" % (infection_risk * 100))
	for pair in [["止痛药", painkiller_left], ["退热药", fever_med_left]]:
		if pair[1] > 0.0:
			lines.append("%s药效中 · 剩余 %d 分钟（游戏时间）"
					% [pair[0], int(pair[1] / _hour_seconds() * 60.0)])
	return lines


func _infection_hint() -> String:
	match int(illnesses.infection.stage):
		1: return "精力恢复下降（抗生素可治疗）"
		2: return "疲劳加快、精力上限下降"
		_: return "持续损伤生命、行动与战斗能力下降！"


func has_any_condition() -> bool:
	return not injuries.is_empty() or not illnesses.is_empty() or infection_risk > 0.3


## —— 存档 ——————————————————————————————————————

func to_save_data() -> Dictionary:
	return {
		"injuries": injuries,
		"illnesses": illnesses,
		"painkiller_left": painkiller_left,
		"fever_med_left": fever_med_left,
		"antiseptic_guard_left": antiseptic_guard_left,
		"infection_risk": infection_risk,
		"water_zero_accum": _water_zero_accum,
		"gastro_recover_left": _gastro_recover_left,
	}


func load_save_data(data: Dictionary) -> void:
	injuries = data.get("injuries", {})
	illnesses = data.get("illnesses", {})
	painkiller_left = float(data.get("painkiller_left", 0.0))
	fever_med_left = float(data.get("fever_med_left", 0.0))
	antiseptic_guard_left = float(data.get("antiseptic_guard_left", 0.0))
	infection_risk = float(data.get("infection_risk", 0.0))
	_water_zero_accum = float(data.get("water_zero_accum", 0.0))
	_gastro_recover_left = float(data.get("gastro_recover_left", 0.0))
	condition_changed.emit()
