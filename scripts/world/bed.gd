class_name Bed
extends Interactable
## 营地里的床：按 E 打开睡眠菜单（4 小时 / 8 小时）。
## 睡眠推进游戏内时间、降低疲劳、恢复精力；原"回血"与冷却机制保留，
## 由 main.gd 的睡眠结算统一执行（本脚本只负责入口与节流）。

signal menu_requested

@export var cooldown_seconds := 30.0  ## 两次睡觉的最短间隔（防连睡白耗时间）

## 由 main.gd 注入；为空时直接拒绝睡觉（无法推进时间）。
var day_night: DayNight

var _cooldown_left := 0.0


func get_prompt() -> String:
	return "睡觉"


func can_interact(_player: Player) -> bool:
	return true


func interact(player: Player) -> void:
	if _cooldown_left > 0.0:
		player.notify.emit("刚休息过，还不困")
		return
	if day_night == null:
		player.notify.emit("现在没法睡觉")
		return
	menu_requested.emit()


## 睡眠结算完成后由 main.gd 调用，启动冷却。
func note_slept() -> void:
	_cooldown_left = cooldown_seconds


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
