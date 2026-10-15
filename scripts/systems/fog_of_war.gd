class_name FogOfWar
extends Node2D
## 地图探索迷雾：网格化的"未探索 / 已探索 / 当前可见"三层状态。
## 玩家视野 = 近距离全向 + 中远距离方向视野锥，射线遮挡截断（隔墙看不见）；
## 已探索区域永久保留（半透明遮罩），未探索区域近乎全黑，连同其中的僵尸、
## 物资一起隐藏。绘制在世界之上（z_index 高）、HUD 之下（HUD 是 CanvasLayer）。

const STATE_UNKNOWN := 0
const STATE_EXPLORED := 1
const STATE_VISIBLE := 2

## —— 玩家视野参数（集中配置） ——
## 近距离全向视野半径：身边一圈 360° 可见（同样遵守墙体遮挡）。
## 180（2026-10-15 第三批）：原 100 小于丧尸 detect_radius 260，存在"死亡盲区"——
## 玩家看不见丧尸但它已锁定你；180 覆盖贴身威胁圈。
@export var omni_radius := 180.0
## 中远距离视野锥最大距离：460 明显超过丧尸 260（夜 364），玩家看得比它远才有"绕开"的空间。
@export var cone_radius := 460.0
## 视野锥半角（度）：总夹角 = 2 × 半角，150°——横向逃跑时视野跟随更跟手。
@export var cone_half_angle_deg := 75.0
## 视线检测碰撞层：**玩家视线遮挡层（值 4）**——只有墙/地图边界/建筑墙/关着的门
## 在此层；家具只占丧尸视线层（值 2），不挡玩家视野（贴身家具不会把周围格子挡黑）。
const SIGHT_MASK := 4

## 迷雾刷新间隔（秒）：不用每帧重算，0.15s 足够平滑。
const TICK_INTERVAL := 0.15

@export var cell_size := 64.0
@export var map_size := Vector2(2400, 1600)
## 测试/脚本用视野方向覆盖：非 ZERO 时替代鼠标方向（headless 无鼠标）。
var aim_override := Vector2.ZERO

var _cols := 0
var _rows := 0
var _cells := PackedByteArray()
var _dirty := true
var _accum := 0.0
var _player: Node2D
var _last_aim := Vector2.RIGHT  ## 上一有效视野方向（鼠标无效时保持）


func _ready() -> void:
	add_to_group("fog_of_war")  # 供 FogLabel 等查询探索状态
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


## 当前可见 → 已探索（保留地图），再按视野规则揭开玩家周围：
## 近距离全向 + 中远距离视野锥，每个候选格子做射线遮挡检查。
func reveal_now() -> void:
	if _player == null:
		return
	for i in _cells.size():
		if _cells[i] == STATE_VISIBLE:
			_cells[i] = STATE_EXPLORED
	var ppos := _player.global_position
	var aim := _aim_dir(ppos)
	var cos_half := cos(deg_to_rad(cone_half_angle_deg))
	var cx := int(ppos.x / cell_size)
	var cy := int(ppos.y / cell_size)
	var span := int(ceil(cone_radius / cell_size)) + 1
	for gy in range(maxi(0, cy - span), mini(_rows, cy + span + 1)):
		for gx in range(maxi(0, cx - span), mini(_cols, cx + span + 1)):
			var center := Vector2((gx + 0.5) * cell_size, (gy + 0.5) * cell_size)
			if not _in_view(center, ppos, aim, cos_half):
				continue
			if not _line_clear(ppos, center) \
					and not _point_in_occluder(center) \
					and not _sub_points_clear(ppos, center):
				continue
			var idx := gy * _cols + gx
			if _cells[idx] < STATE_VISIBLE:
				_cells[idx] = STATE_VISIBLE
	_dirty = true


## 视野方向：玩家指向鼠标；鼠标贴身/无效时保留上一有效方向（初始向右）。
## aim_override 非 ZERO 时直接采用（headless 测试无鼠标）。
func _aim_dir(ppos: Vector2) -> Vector2:
	if aim_override != Vector2.ZERO:
		return aim_override.normalized()
	var aim := get_global_mouse_position() - ppos
	if aim.length() >= 8.0:
		_last_aim = aim.normalized()
	return _last_aim


## 距离与方向判定：全向圈内恒真；锥环内要求与视野方向夹角 ≤ 半角。
func _in_view(point: Vector2, ppos: Vector2, aim: Vector2, cos_half: float) -> bool:
	var offset := point - ppos
	var d := offset.length()
	if d <= omni_radius:
		return true
	if d > cone_radius:
		return false
	if d < 0.01:
		return true
	return offset.normalized().dot(aim) >= cos_half


## 视线无遮挡：从玩家到目标点做射线检测（查视线层 2，排除玩家自身）。
## 窗户不占视线层 → 射线自然穿透；墙/家具/关着的门 → 截断。
func _line_clear(from: Vector2, to: Vector2) -> bool:
	var space := _player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK, [_player.get_rid()])
	return space.intersect_ray(query).is_empty()


## 格心是否落在视线遮挡物内部（2026-10-15 第五批：遮挡物自身所在的格应点亮）。
## 大件遮挡物（120×60 废弃车）覆盖整格：格心在车体内、射线在车的近侧表面
## 就被截断，旧模型把车身涂成整块黑——美术资源上线后会盖掉车轮车漆细节。
## 正确模型：物体本身可见（点亮它覆盖的格），只有它**后面**的格看不到——
## 后方格子的格心在物体外，射线照样被挡，不会"看穿"。
func _point_in_occluder(point: Vector2) -> bool:
	var space := _player.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = SIGHT_MASK
	return not space.intersect_point(query).is_empty()


## 格内子点采样：格心被挡时，在格内四角（±20px）补测，任意一点通视即算可见。
## 解决"格中心恰好在沙发等窄家具/墙体内 → 格子永久黑"的粒度缺陷：
## 窄家具能正常亮起，而贯穿整格的墙体子点仍全被挡，不会破坏隔墙遮挡。
const SUB_SAMPLE_OFFSETS: Array[Vector2] = [
	Vector2(-20, -20), Vector2(20, -20), Vector2(-20, 20), Vector2(20, 20),
]

func _sub_points_clear(from: Vector2, cell_center: Vector2) -> bool:
	for off in SUB_SAMPLE_OFFSETS:
		if _line_clear(from, cell_center + off):
			return true
	return false


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
