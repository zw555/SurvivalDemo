class_name Bed
extends Interactable
## 营地里的床：按 E 睡觉，按最大生命值的百分比恢复，带冷却防止连续睡觉瞬间回满。
## 夜晚睡觉会直接跳到第二天清晨（白天睡觉只回血，不跳时间）。

@export var heal_percent := 20.0  ## 恢复最大生命值的百分比
@export var cooldown_seconds := 30.0  ## 两次睡觉的最短间隔

## 由 main.gd 注入；为空或白天时睡觉不推进时间。
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
	if player.health >= float(player.max_health):
		player.notify.emit("生命值已满，不需要休息")
		return
	var heal_amount := int(round(player.max_health * heal_percent / 100.0))
	player.heal(heal_amount)
	_cooldown_left = cooldown_seconds
	if day_night != null and day_night.is_night:
		day_night.skip_to_morning()
		player.notify.emit("一觉睡到天亮，恢复了 %d 点生命值" % heal_amount)
	else:
		player.notify.emit("睡了一觉，恢复了 %d 点生命值" % heal_amount)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
