class_name FogOfWar
extends Node2D
## 地图探索迷雾：网格化的"未探索 / 已探索 / 当前可见"三层状态。
## 玩家周围一定半径逐步揭开，已探索区域永久保留（半透明遮罩）；
## 未探索区域近乎全黑，连同其中的僵尸、物资一起隐藏。
## 绘制在世界之上（z_index 高）、HUD 之下（HUD 是 CanvasLayer，天然在其上）。

const STATE_UNKNOWN := 0
const STATE_EXPLORED := 1
const STATE_VISIBLE := 2

## 迷雾刷新间隔（秒）：不用每帧重算，0.15s 足够平滑。
const TICK_INTERVAL := 0.15

@export var cell_size := 64.0
@export var visible_radius := 280.0
@export var map_size := Vector2(2400, 1600)

var _cols := 0
var _rows := 0
var _cells := PackedByteArray()
var _dirty := true
var _accum := 0.0
var _player: Node2D


func _ready() -> void:
	z_index = 90  # 世界之上、CanvasLayer 之下
	_cols = maxi(1, ceili(map_size.x / cell_size))
	_rows = maxi(1, ceili(map_size.y / cell_size))
	_cells.resize(_cols * _rows)
	_dirty = true


## 由 main.gd 注入玩家；注入后立刻揭开出生点周围。
func setup(player: Node2D) -> void:
	_player = player
	if _player != null:
		reveal_now()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_accum -= delta
	if _accum <= 0.0:
		_accum = TICK_INTERVAL
		reveal_now()


## 当前可见 → 已探索（保留地图），再揭开玩家周围一圈为当前可见。
func reveal_now() -> void:
	if _player == null:
		return
	for i in _cells.size():
		if _cells[i] == STATE_VISIBLE:
			_cells[i] = STATE_EXPLORED
	_reveal_around(_player.global_position, visible_radius, STATE_VISIBLE)
	_dirty = true


## 情报解锁：把一片区域直接标为"已探索"（地图上可见，但不当作当前视野）。
func reveal_area(pos: Vector2, radius: float) -> void:
	_reveal_around(pos, radius, STATE_EXPLORED)
	_dirty = true


func _reveal_around(pos: Vector2, radius: float, state: int) -> void:
	var cx := int(pos.x / cell_size)
	var cy := int(pos.y / cell_size)
	var span := int(ceil(radius / cell_size)) + 1
	for gy in range(maxi(0, cy - span), mini(_rows, cy + span + 1)):
		for gx in range(maxi(0, cx - span), mini(_cols, cx + span + 1)):
			var center := Vector2((gx + 0.5) * cell_size, (gy + 0.5) * cell_size)
			if center.distance_to(pos) <= radius:
				var idx := gy * _cols + gx
				if _cells[idx] < state:
					_cells[idx] = state


func is_explored(pos: Vector2) -> bool:
	var gx := clampi(int(pos.x / cell_size), 0, _cols - 1)
	var gy := clampi(int(pos.y / cell_size), 0, _rows - 1)
	return _cells[gy * _cols + gx] >= STATE_EXPLORED


## —— 地图画布用的只读访问器 ——

func col_count() -> int:
	return _cols


func row_count() -> int:
	return _rows


func cell_state(gx: int, gy: int) -> int:
	if gx < 0 or gy < 0 or gx >= _cols or gy >= _rows:
		return STATE_UNKNOWN
	return _cells[gy * _cols + gx]


func _draw() -> void:
	for gy in _rows:
		for gx in _cols:
			match _cells[gy * _cols + gx]:
				STATE_UNKNOWN:
					draw_rect(Rect2(gx * cell_size, gy * cell_size, cell_size, cell_size),
							Color(0.02, 0.03, 0.04, 0.97))
				STATE_EXPLORED:
					draw_rect(Rect2(gx * cell_size, gy * cell_size, cell_size, cell_size),
							Color(0.0, 0.0, 0.0, 0.45))
				_:
					pass  # 当前可见：不画


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		queue_redraw()


## 存档：只保存"是否探索过"（当前可见是临时状态）。
func get_save_data() -> String:
	var bits := ""
	for i in _cells.size():
		bits += "1" if _cells[i] >= STATE_EXPLORED else "0"
	return bits


func load_save_data(data: String) -> void:
	if data.is_empty() or data.length() != _cells.size():
		return
	for i in _cells.size():
		_cells[i] = STATE_EXPLORED if data[i] == "1" else STATE_UNKNOWN
	_dirty = true
