class_name SurvivorNpc
extends Interactable
## 飞行员 NPC（老周）：撤离任务的关键人物。第一版只做四件事——
## 固定位置、对话（对话内容与任务推进由 main.gd 的状态机决定）、
## 任务状态（交付物资后由 main.gd 把他挪到停机坪）、结局触发（在停机坪再按 E）。
## 不移动、不战斗、不被僵尸攻击（站在军营里，剧情上躲着）。

## 交谈时发出；main.gd 决定说什么、任务怎么推进。
signal talk_requested

@export var npc_name := "老周"


func get_prompt() -> String:
	return "飞行员 %s（按 E 交谈）" % npc_name


func interact(_player: Player) -> void:
	talk_requested.emit()
