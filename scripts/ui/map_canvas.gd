class_name MapCanvas
extends Control
## M 键全屏地图的画布：把迷雾网格缩放绘制成底图，
## 已发现/已探索的地点画标记与名称，玩家位置画白点。
## 数据由 main.gd 注入（fog / buildings / markers 引用，markers 是同一字典的引用）。

@export var map_size := Vector2(4800, 3200)

var fog: FogOfWar
var buildings: Array = []
var markers := {}
var player: Node2D

var _view_size := Vector2(720, 480)


func _ready() -> void:
	custom_minimum_size = _view_size
	if size.x > 1.0:
		_view_size = size
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _scale() -> float:
	return minf(_view_size.x / map_size.x, _view_size.y / map_size.y)


func _draw() -> void:
	var s := _scale()
	draw_rect(Rect2(Vector2.ZERO, _view_size), Color(0.05, 0.06, 0.05))
	# —— 迷雾底图：未知 = 背景色；已探索 = 暗绿；当前可见 = 亮绿 ——
	if fog != null:
		var cell := fog.cell_size * s
		for gy in fog.row_count():
			for gx in fog.col_count():
				var state := fog.cell_state(gx, gy)
				if state == FogOfWar.STATE_UNKNOWN:
					continue
				var color := Color(0.30, 0.34, 0.28) if state == FogOfWar.STATE_EXPLORED \
						else Color(0.46, 0.52, 0.42)
				draw_rect(Rect2(gx * cell, gy * cell, cell + 0.5, cell + 0.5), color)
	# —— 地点标记：未知不画；已发现 = 圆点 + 名称；已探索 = 名称 + ✓ ——
	var font := ThemeDB.fallback_font
	for b in buildings:
		var state := int(markers.get(str(b.id), 0))
		if state == 0:
			continue
		var rect: Rect2 = b.rect
		var pos := rect.get_center() * s
		draw_circle(pos, 5.0, b.color)
		draw_arc(pos, 5.0, 0.0, TAU, 16, Color(0.1, 0.1, 0.1), 1.5)
		var label: String = str(b.name) + (" ✓" if state == 2 else "")
		draw_string(font, pos + Vector2(9, 4), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.92, 0.85))
	# —— 玩家位置 ——
	if player != null:
		var pos := player.global_position * s
		draw_circle(pos, 4.0, Color(1, 1, 1))
		draw_string(font, pos + Vector2(8, 4), "你",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
