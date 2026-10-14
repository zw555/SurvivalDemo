class_name QuestManager
extends Node
## 任务管理模块：任务数据（接取/目标进度）与追踪状态统一在这里维护。
## 右上角追踪 HUD 与任务列表面板只读快照、监听信号刷新，各自不保存任务数据。
##
## 两个独立概念：
## - 接取（accepted）：任务进入玩家任务列表。
## - 追踪（tracked）：玩家选择把任务显示在右上角 HUD，最多 3 个。
## 接取不自动占用追踪槽位（除非调用方明确 auto_track，用于教学引导）。

## 任一任务的目标或状态变化（含完成）。
signal quest_changed(id: String)
## 追踪集合变化（增/删）。
signal tracked_changed()
## 追踪请求被拒：槽位已满，未静默覆盖。UI 据此提示玩家先取消一个。
signal track_rejected(id: String)

const MAX_TRACKED := 3

## 任务表：id -> {title, accepted, completed, objectives: [{id, text, done}]}
var _quests := {}
## 追踪中的任务 id，最多 MAX_TRACKED 个，保持追踪顺序。
var _tracked: Array[String] = []


func define_quest(id: String, title: String, objectives: Array) -> void:
	var objs: Array[Dictionary] = []
	for o in objectives:
		objs.append({"id": str(o.id), "text": str(o.text), "done": false})
	_quests[id] = {"title": title, "accepted": false, "completed": false,
			"objectives": objs}


## —— 接取 ————————————————————————————————————————

## 接取任务；auto_track 仅用于教学主线这类"应默认出现在 HUD"的场景，
## 且至多占用 1 个槽位（槽位满时只接取不追踪，不报错）。
func accept(id: String, auto_track := false) -> void:
	var q: Dictionary = _quests.get(id, {})
	if q.is_empty() or bool(q.accepted):
		return
	q.accepted = true
	if auto_track and _tracked.size() < MAX_TRACKED:
		_tracked.append(id)
		tracked_changed.emit()
	quest_changed.emit(id)


func is_accepted(id: String) -> bool:
	var q: Dictionary = _quests.get(id, {})
	return not q.is_empty() and bool(q.accepted)


func is_completed(id: String) -> bool:
	var q: Dictionary = _quests.get(id, {})
	return not q.is_empty() and bool(q.completed)


## —— 目标进度 ——————————————————————————————————————

func set_objective_done(quest_id: String, obj_id: String, done := true) -> void:
	var obj := _find_objective(quest_id, obj_id)
	if obj.is_empty() or bool(obj.done) == done:
		return
	obj.done = done
	quest_changed.emit(quest_id)


## 更新目标进度文本（如"食物 1/2 · 水 0/2"），HUD 收到信号自动刷新。
func set_objective_text(quest_id: String, obj_id: String, text: String) -> void:
	var obj := _find_objective(quest_id, obj_id)
	if obj.is_empty() or str(obj.text) == text:
		return
	obj.text = text
	quest_changed.emit(quest_id)


## 任务整体完成：自动从追踪中移除，释放槽位。
func complete_quest(id: String) -> void:
	var q: Dictionary = _quests.get(id, {})
	if q.is_empty() or bool(q.completed):
		return
	q.completed = true
	if untrack(id) and _tracked.size() >= 0:
		pass  # untrack 内部已发 tracked_changed
	quest_changed.emit(id)


## —— 追踪 ————————————————————————————————————————

func is_tracked(id: String) -> bool:
	return _tracked.has(id)


## 追踪：槽位满返回 false 并发 track_rejected（不覆盖已有追踪）。
func track(id: String) -> bool:
	if not _quests.has(id) or is_tracked(id):
		return is_tracked(id)
	if _tracked.size() >= MAX_TRACKED:
		track_rejected.emit(id)
		return false
	_tracked.append(id)
	tracked_changed.emit()
	return true


## 取消追踪：不影响任务本身的进度与状态。返回是否确实移除了。
func untrack(id: String) -> bool:
	if not _tracked.has(id):
		return false
	_tracked.erase(id)
	tracked_changed.emit()
	return true


func toggle_track(id: String) -> bool:
	if is_tracked(id):
		untrack(id)
		return true
	return track(id)


## —— UI 快照（只读）——————————————————————————————

## 右上角追踪 HUD 用：[{id, title, done, total, current_text}]
## current_text 为第一个未完成目标的文本；全部完成时为完成提示。
func tracked_snapshot() -> Array:
	var out: Array = []
	for id in _tracked:
		var q: Dictionary = _quests.get(id, {})
		if q.is_empty():
			continue
		var done_count := 0
		var current_text := ""
		for obj in q.objectives:
			if bool(obj.done):
				done_count += 1
			elif current_text == "":
				current_text = str(obj.text)
		if current_text == "":
			current_text = "全部目标已完成"
		out.append({"id": id, "title": str(q.title), "done": done_count,
				"total": q.objectives.size(), "current_text": current_text})
	return out


## 任务列表 UI 用：接取中的全部任务（含目标明细，供 ✓/· 标记）。
func quests_snapshot() -> Array:
	var out: Array = []
	for id in _quests:
		var q: Dictionary = _quests[id]
		if not bool(q.accepted):
			continue
		var objs: Array = []
		for obj in q.objectives:
			objs.append({"id": str(obj.id), "text": str(obj.text),
					"done": bool(obj.done)})
		out.append({"id": id, "title": str(q.title),
				"completed": bool(q.completed), "tracked": is_tracked(id),
				"objectives": objs})
	return out


## —— 存档（只存追踪状态；任务进度由 main 的 quest_stage 恢复）——

func get_save_data() -> Dictionary:
	return {"tracked": Array(_tracked)}


func load_save_data(data: Dictionary) -> void:
	_tracked.clear()
	for id in data.get("tracked", []):
		var sid := str(id)
		if _quests.has(sid) and not _tracked.has(sid):
			_tracked.append(sid)
	tracked_changed.emit()


## —— 内部 ————————————————————————————————————————

func _find_objective(quest_id: String, obj_id: String) -> Dictionary:
	var q: Dictionary = _quests.get(quest_id, {})
	if q.is_empty():
		return {}
	for obj in q.objectives:
		if str(obj.id) == obj_id:
			return obj
	return {}
