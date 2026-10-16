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

## —— 迷雾绘制模式（2026-10-15 视觉柔化原型，F6 切换） ——
## 0 = 现状纯色矩形（对照基线）；1 = 边界柔化原型。
## 柔化只作用于「因距离/角度不可见」的视野边界格：绘制时把格子切成 16px
## 子格，用 _in_view()（纯几何：全向圆 + 视野锥）对子格中心做真实采样，
## 让视野边缘从 64px 方块阶梯变成贴合真实圆弧/扇形的过渡——不是继承
## 格状态的假细分。「因遮挡不可见」的格（格心在视野几何内却被墙挡）
## 保持整格硬边：墙后不该被柔化看穿。判定逻辑 / 存档格式 / _cells 不变。
@export var visual_mode := 1  ## 0=纯色基线（调试对照） 1=边界柔化（2026-10-16 起默认，F6 切换）

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
## —— 绘制层缓存：reveal_now 时记录的视野几何参数，_draw 柔化采样用。
## 不在 _draw 里调 _aim_dir（它会读鼠标并改写 _last_aim，绘制必须无副作用）。
var _last_ppos := Vector2.ZERO
var _last_cos_half := 0.0
var _has_view_cache := false
## 调试测量：最近一次 _draw 耗时（微秒）。基准脚本 tools/bench_fog.gd 读取。
var last_draw_usec := 0
## 柔化绘制复用缓冲（_ready 预分配，避免每次 _draw 分配 Packed 数组）。
var _soft_pts := PackedVector2Array()
var _soft_cols := PackedColorArray()
var _soft_uvs := PackedVector2Array()
## 视野边界格标记（派生缓存，_update_border 维护，语义完全由 _cells 决定，
## 不参与判定/存档）。**不要在 _draw 里现算 8 邻**：首版对每个非可见格
## 调 8 次 cell_state（~6400 次 GDScript 调用）实测把 _draw 拖到 3.3ms。
var _border := PackedByteArray()


func _ready() -> void:
	add_to_group("fog_of_war")  # 供 FogLabel 等查询探索状态
	z_index = 90  # 世界之上、CanvasLayer 之下
	_cols = maxi(1, ceili(map_size.x / cell_size))
	_rows = maxi(1, ceili(map_size.y / cell_size))
	_cells.resize(_cols * _rows)
	_border.resize(_cols * _rows)
	_soft_pts.resize(4)
	_soft_cols.resize(4)
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
	_last_ppos = ppos
	_last_aim = aim
	_last_cos_half = cos_half
	_has_view_cache = true
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
	if visual_mode == 1:
		_update_border()
	_dirty = true


## 视野边界格标记：从每个可见格向 8 邻扩散标记非可见邻居。
## 只遍历可见格（~200 个）向外的 8 邻，比"每个非可见格查 8 邻"便宜一个量级。
func _update_border() -> void:
	for i in _border.size():
		_border[i] = 0
	for gy in _rows:
		for gx in _cols:
			if _cells[gy * _cols + gx] != STATE_VISIBLE:
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := gx + ox
					var ny := gy + oy
					if nx < 0 or ny < 0 or nx >= _cols or ny >= _rows:
						continue
					var ni := ny * _cols + nx
					if _cells[ni] != STATE_VISIBLE:
						_border[ni] = 1


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
	var t0 := Time.get_ticks_usec()
	if visual_mode == 1 and _has_view_cache:
		_draw_soft()
	else:
		_draw_solid()
	last_draw_usec = int(Time.get_ticks_usec() - t0)


## 模式 0（对照基线）：纯色矩形，与柔化原型之前完全一致。
func _draw_solid() -> void:
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


## 模式 1（边界柔化原型）：只有「视野边界格」改变画法，其余与基线一致。
func _draw_soft() -> void:
	for gy in _rows:
		for gx in _cols:
			var st := _cells[gy * _cols + gx]
			if st == STATE_VISIBLE:
				continue
			var solid_alpha := 0.97 if st == STATE_UNKNOWN else 0.45
			if _border[gy * _cols + gx] == 1 \
					and not _in_view(_cell_center(gx, gy), _last_ppos, _last_aim, _last_cos_half):
				# 不可见原因是距离/角度（格心在视野几何外）→ 子格真实采样柔化。
				# 若格心在视野几何内，说明是遮挡造成的不可见 → 保持整格硬边，
				# 绝不柔化墙后（否则子采样会把墙后的格"点"出一半亮来）。
				_draw_cell_soft(gx, gy, st, solid_alpha)
			else:
				var col := Color(0.02, 0.03, 0.04, solid_alpha) if st == STATE_UNKNOWN \
						else Color(0.0, 0.0, 0.0, solid_alpha)
				draw_rect(Rect2(gx * cell_size, gy * cell_size, cell_size, cell_size), col)


func _cell_center(gx: int, gy: int) -> Vector2:
	return Vector2((gx + 0.5) * cell_size, (gy + 0.5) * cell_size)


## 边界格柔化：把格切成上下两个半格条带，各画一个四边形（draw_primitive），
## 四个角点的 alpha 由视野几何（全向圆 + 视野锥）真实采样：
##   角点在视野几何内 → 过渡 alpha（UNKNOWN 过渡到 0.45、EXPLORED 到 0.2）
##   角点在视野几何外 → 该状态原有的整格 alpha
## GPU 在三角形内对 alpha 插值 → 边界是连续渐变，不是方块阶梯；
## 相邻格共享位置角点的采样值一致 → 跨格颜色连续。
## 性能要点（首版实测教训）：① 视野判定数学**内联**在采样循环里——
## GDScript 每次函数调用 ~1-3µs，560 次采样走函数就是 1.5ms+；
## ② 顶点/颜色缓冲用成员数组复用（写索引原地改，不触发分配）；
## ③ draw_primitive 画四边形不三角化、不开新命令，比 draw_polygon 便宜。
func _draw_cell_soft(gx: int, gy: int, st: int, solid_alpha: float) -> void:
	var soft_alpha := 0.2 if st == STATE_EXPLORED else 0.45
	var cr := 0.02 if st == STATE_UNKNOWN else 0.0
	var cg := 0.03 if st == STATE_UNKNOWN else 0.0
	var cb := 0.04 if st == STATE_UNKNOWN else 0.0
	var omni2 := omni_radius * omni_radius
	var cone2 := cone_radius * cone_radius
	var x0 := gx * cell_size
	var x1 := x0 + cell_size
	for band in 2:
		var ya := gy * cell_size if band == 0 else gy * cell_size + cell_size * 0.5
		var yb := gy * cell_size + cell_size * 0.5 if band == 0 else gy * cell_size + cell_size
		_soft_pts[0] = Vector2(x0, ya)
		_soft_pts[1] = Vector2(x1, ya)
		_soft_pts[2] = Vector2(x1, yb)
		_soft_pts[3] = Vector2(x0, yb)
		for vi in 4:
			var off: Vector2 = _soft_pts[vi] - _last_ppos
			var d2 := off.length_squared()
			var a := soft_alpha
			if d2 > omni2:
				# 全向圈外：锥外实雾；锥内再比角度（等价 _in_view，内联省调用）
				if d2 > cone2 or off.dot(_last_aim) < _last_cos_half * sqrt(d2):
					a = solid_alpha
			_soft_cols[vi] = Color(cr, cg, cb, a)
		draw_primitive(_soft_pts, _soft_cols, _soft_uvs)


## F6：在「纯色基线 ↔ 柔化原型」之间切换（调试模式，原型验证用）。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F6:
		visual_mode = 1 - visual_mode
		if visual_mode == 1:
			_update_border()  # 切换时立即补算边界标记（上次 reveal 可能在模式 0）
		queue_redraw()


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
