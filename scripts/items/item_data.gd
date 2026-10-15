class_name ItemData
extends Resource
## 物品定义：占位原型使用的最小物品结构。
## 武器（kind=weapon）可装备到左右手；背包（kind=backpack）装备到背包部位；
## 服装（kind=clothing）按 equip_slot 装备到对应部位。

const KIND_FOOD := "food"
const KIND_WATER := "water"
const KIND_WEAPON := "weapon"
const KIND_BACKPACK := "backpack"
const KIND_CLOTHING := "clothing"
const KIND_MEDICINE := "medicine"
const KIND_GUN := "gun"
const KIND_AMMO := "ammo"
const KIND_GRENADE := "grenade"
const KIND_MATERIAL := "material"
const KIND_FUEL := "fuel"
const KIND_NOTE := "note"

const SLOT_HAND_L := "hand_l"
const SLOT_HAND_R := "hand_r"
const SLOT_HEAD := "head"
const SLOT_CHEST := "chest"
const SLOT_LEGS := "legs"
const SLOT_FEET := "feet"
const SLOT_BACKPACK := "backpack"

const SLOT_NAMES := {
	SLOT_HAND_L: "左手",
	SLOT_HAND_R: "右手",
	SLOT_HEAD: "帽子",
	SLOT_CHEST: "衣服",
	SLOT_LEGS: "裤子",
	SLOT_FEET: "鞋子",
	SLOT_BACKPACK: "背包",
}

## 一格距离对应的像素（玩家默认攻击距离）；两格武器 = 96。
const ONE_TILE_RANGE := 48.0

@export var id := ""
@export var display_name := ""
@export var kind := KIND_FOOD
## clothing 用的装备部位（SLOT_HEAD / SLOT_CHEST / SLOT_LEGS / SLOT_FEET）。
@export var equip_slot := ""
@export var food_value := 0.0
@export var water_value := 0.0
## medicine 使用的回复量：按 E 使用直接恢复生命（不超上限）。
@export var heal_amount := 0.0
## medicine 的用途说明（tooltip 与使用反馈用）；规则实现集中在 HealthSystem.MEDICINE_RULES。
@export var usage_desc := ""
@export var damage := 0
@export var slot_bonus := 0
@export var defense := 0
@export var speed_bonus := 0.0  ## 移速加成百分比
## 武器攻击距离（像素）；0 = 使用玩家默认（一格 48）。
@export var attack_range := 0.0
## 武器挥击扇形半角（度）；0 = 使用玩家默认（50°）。长柄武器用小角度体现"直刺"。
@export var attack_arc_deg := 0.0
## 武器攻击冷却（秒）；0 = 使用玩家默认（0.45）。匕首类更快。
@export var attack_cooldown := 0.0
## 双手武器：占用左右手两个部位（棒 / 刀 / 矛）；false 为单手（匕首，可双持）。
@export var two_handed := false
## 矛类：一次攻击只能命中最近的一个敌人。
@export var single_target := false
## gun 使用的弹药类型（"pistol" = 9mm / "rifle" = 步枪弹）。
@export var gun_ammo_type := ""
## ammo 物品：一盒装的子弹数。
@export var ammo_type := ""
@export var ammo_amount := 0
## grenade 的爆炸半径（像素）。
@export var blast_radius := 0.0
## 同 id 可叠放数量：1 = 一格一件（默认）；>1 时背包把相同物品叠进同一格。
@export var stack_size := 1
@export var color := Color.WHITE
## note（纸条）：阅读后在地图上解锁的地点 id（main.gd 的 map_markers 键）。
@export var reveals := ""


## 武器攻击距离折算成"格"数（用于说明文字）。
func range_in_tiles() -> int:
	return maxi(1, roundi(maxf(attack_range, ONE_TILE_RANGE) / ONE_TILE_RANGE))


## 弹药类型的显示名（枪械与弹盒共用）。
func ammo_display_name() -> String:
	return "9mm 弹药" if gun_ammo_type == "pistol" or ammo_type == "pistol" else "步枪弹药"


## 给 tooltip 用的物品说明。
func describe() -> String:
	match kind:
		KIND_FOOD:
			return "食物 +%d" % int(food_value)
		KIND_WATER:
			return "水 +%d" % int(water_value)
		KIND_MEDICINE:
			return usage_desc if usage_desc != "" \
					else "药品 · 生命 +%d（按 E 使用）" % int(heal_amount)
		KIND_GUN:
			return "枪械 · 伤害 %d · 射程 %d 格 · 需 %s" % [damage, range_in_tiles(), ammo_display_name()]
		KIND_AMMO:
			return "弹药 · %s ×%d（按 E 装填）" % [ammo_display_name(), ammo_amount]
		KIND_GRENADE:
			return "手雷 · 爆炸伤害 %d · 半径约 %d 格（按 E 朝鼠标方向投掷）" % [
				damage, maxi(1, roundi(blast_radius / ONE_TILE_RANGE))]
		KIND_MATERIAL:
			return "材料 · 用于制作（在工作台使用）%s" % (
				"· 可叠放 %d 个" % stack_size if stack_size > 1 else "")
		KIND_FUEL:
			return "燃料 · 任务物资（交给需要它的人）%s" % (
				"· 可叠放 %d 个" % stack_size if stack_size > 1 else "")
		KIND_NOTE:
			return "情报纸条 · 按 E 阅读，在地图上标记一个地点"
		KIND_WEAPON:
			var parts: Array[String] = ["武器 · 伤害 %d · 距离 %d 格" % [damage, range_in_tiles()]]
			parts.append("双手" if two_handed else "单手")
			if single_target:
				parts.append("只命中最近目标")
			if attack_cooldown > 0.0:
				parts.append("攻速快")
			return " · ".join(parts)
		KIND_BACKPACK:
			return "背包 · 扩容 +%d 格" % slot_bonus
		KIND_CLOTHING:
			var stats: Array[String] = []
			if defense > 0:
				stats.append("护甲 +%d" % defense)
			if speed_bonus > 0.0:
				stats.append("移速 +%.0f%%" % speed_bonus)
			var slot_name: String = SLOT_NAMES.get(equip_slot, equip_slot)
			if stats.is_empty():
				return "装备 · %s" % slot_name
			return "装备 · %s · %s" % [slot_name, "、".join(stats)]
	return display_name
