class_name DayNight
extends Node
## 昼夜循环：白天 / 夜晚实时交替，夜晚画面变暗、僵尸被强化（由 main.gd 监听信号处理）。
## 天数从 1 开始计数；每次迎来清晨 day_number + 1 并发出 day_started。

signal day_started(day: int)
signal night_started(day: int)

@export var day_seconds := 400.0  ## 一个白天的现实时长（秒）；一天共 600s ≈ 现实 10 分钟
@export var night_seconds := 200.0  ## 一个夜晚的现实时长（秒）
@export var transition_seconds := 3.0  ## 画面明暗过渡时长
@export var day_color := Color(1.0, 1.0, 1.0)
@export var night_color := Color(0.32, 0.36, 0.55)

var day_number := 1
var is_night := false

var _phase_left := 0.0
var _canvas_modulate: CanvasModulate
var _tween: Tween


## 由 main.gd 在就绪时调用，绑定画面变暗用的 CanvasModulate 并开始计时。
func setup(modulate_node: CanvasModulate) -> void:
	_canvas_modulate = modulate_node
	_phase_left = day_seconds
	_canvas_modulate.color = day_color


func _process(delta: float) -> void:
	if _canvas_modulate == null:
		return
	_phase_left -= delta
	if _phase_left <= 0.0:
		_toggle_phase()


## 夜里在床上睡觉时调用：立刻跳到第二天清晨。
func skip_to_morning() -> void:
	if not is_night:
		return
	is_night = false
	_phase_left = day_seconds
	day_number += 1
	_transition_color(day_color)
	day_started.emit(day_number)


## 测试 / 调试用：直接切换昼夜状态。
func force_night(night: bool) -> void:
	if is_night == night:
		return
	if night:
		is_night = true
		_phase_left = night_seconds
		_transition_color(night_color)
		night_started.emit(day_number)
	else:
		skip_to_morning()


## 读档恢复：天数、昼夜与阶段剩余时间直接生效（画面颜色不做过场）。
func restore(day: int, night: bool, phase_left: float) -> void:
	day_number = maxi(1, day)
	is_night = night
	_phase_left = maxf(1.0, phase_left)
	if _canvas_modulate != null:
		_canvas_modulate.color = night_color if is_night else day_color


func _toggle_phase() -> void:
	if is_night:
		skip_to_morning()
	else:
		is_night = true
		_phase_left = night_seconds
		_transition_color(night_color)
		night_started.emit(day_number)


func _transition_color(target: Color) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_canvas_modulate, "color", target, transition_seconds)
