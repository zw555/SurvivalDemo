class_name Hud
extends CanvasLayer
## 生存 HUD：状态条、Tab 装备+背包面板、容器面板（营地仓库/箱子）与提示信息。

const SLOT_SIZE := Vector2(64, 64)

@onready var _health_bar: ProgressBar = $Root/Bars/HealthBar
@onready var _health_text: Label = $Root/Bars/HealthBar/HealthText
@onready var _food_bar: ProgressBar = $Root/Bars/FoodBar
@onready var _food_text: Label = $Root/Bars/FoodBar/FoodText
@onready var _water_bar: ProgressBar = $Root/Bars/WaterBar
@onready var _water_text: Label = $Root/Bars/WaterBar/WaterText
@onready var _stamina_bar: ProgressBar = $Root/Bars/StaminaBar
@onready var _stamina_text: Label = $Root/Bars/StaminaBar/StaminaText
@onready var _fatigue_bar: ProgressBar = $Root/Bars/FatigueBar
@onready var _fatigue_text: Label = $Root/Bars/FatigueBar/FatigueText
@onready var _sleep_panel: PanelContainer = $Root/SleepPanel
@onready var _sleep_info: Label = $Root/SleepPanel/SleepBox/SleepInfo
@onready var _sleep4_button: Button = $Root/SleepPanel/SleepBox/Sleep4Button
@onready var _sleep8_button: Button = $Root/SleepPanel/SleepBox/Sleep8Button
@onready var _sleep_close_button: Button = $Root/SleepPanel/SleepBox/SleepCloseButton
@onready var _equip_label: Label = $Root/EquipLabel
@onready var _message_label: Label = $Root/MessageLabel
@onready var _inventory_grid: GridContainer = $Root/GearPanel/GearBox/GearBody/InvBox/InventoryScroll/InventoryGrid
@onready var _storage_box: VBoxContainer = $Root/GearPanel/GearBox/GearBody/StorageBox
@onready var _storage_title: Label = $Root/GearPanel/GearBox/GearBody/StorageBox/StorageTitle
@onready var _storage_grid: GridContainer = $Root/GearPanel/GearBox/GearBody/StorageBox/StorageScroll/StorageGrid
@onready var _prompt_label: Label = $Root/PromptLabel
@onready var _day_label: Label = $Root/DayLabel
@onready var _gear_panel: PanelContainer = $Root/GearPanel
@onready var _gear_stats: Label = $Root/GearPanel/GearBox/GearStats
@onready var _body_layout: Control = $Root/GearPanel/GearBox/GearBody/BodyLayout
@onready var _pause_menu: ColorRect = $Root/PauseMenu
@onready var _continue_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/ContinueButton
@onready var _save_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/SaveButton
@onready var _load_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/LoadButton
@onready var _quit_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/QuitButton
@onready var _sofa_panel: PanelContainer = $Root/SofaPanel
@onready var _sofa_rest_button: Button = $Root/SofaPanel/SofaBox/RestButton
@onready var _sofa_search_button: Button = $Root/SofaPanel/SofaBox/SearchButton
@onready var _sofa_close_button: Button = $Root/SofaPanel/SofaBox/CloseButton
@onready var _craft_panel: PanelContainer = $Root/CraftPanel
@onready var _craft_list: VBoxContainer = $Root/CraftPanel/CraftBox/CraftList
@onready var _craft_close_button: Button = $Root/CraftPanel/CraftBox/CraftCloseButton
@onready var _thought_panel: PanelContainer = $Root/ThoughtPanel
@onready var _thought_text: Label = $Root/ThoughtPanel/ThoughtBox/ThoughtText
@onready var _thought_hint: Label = $Root/ThoughtPanel/ThoughtBox/ThoughtHint
@onready var _npc_panel: PanelContainer = $Root/NpcPanel
@onready var _npc_title: Label = $Root/NpcPanel/NpcBox/NpcTitle
@onready var _npc_text: RichTextLabel = $Root/NpcPanel/NpcBox/NpcText
@onready var _npc_deliver_button: Button = $Root/NpcPanel/NpcBox/NpcDeliverButton
@onready var _npc_close_button: Button = $Root/NpcPanel/NpcBox/NpcCloseButton
@onready var _ending_panel: ColorRect = $Root/EndingPanel
@onready var _ending_title: Label = $Root/EndingPanel/Center/Panel/EndingBox/EndingTitle
@onready var _ending_text: Label = $Root/EndingPanel/Center/Panel/EndingBox/EndingText
@onready var _ending_continue: Button = $Root/EndingPanel/Center/Panel/EndingBox/EndingContinueButton
@onready var _ending_restart: Button = $Root/EndingPanel/Center/Panel/EndingBox/EndingRestartButton
@onready var _map_panel: PanelContainer = $Root/MapPanel
@onready var _map_canvas: MapCanvas = $Root/MapPanel/MapBox/MapCanvas
@onready var _quest_tracker_panel: PanelContainer = $Root/QuestTrackerPanel
@onready var _quest_tracker_list: VBoxContainer = $Root/QuestTrackerPanel/QuestTrackerBox/QuestList
@onready var _quest_tracker_empty: Label = $Root/QuestTrackerPanel/QuestTrackerBox/TrackerEmpty
@onready var _quest_panel: PanelContainer = $Root/QuestPanel
@onready var _quest_panel_list: VBoxContainer = $Root/QuestPanel/QuestBox/QuestScroll/QuestList
@onready var _quest_close_button: Button = $Root/QuestPanel/QuestBox/QuestCloseButton
@onready var _quest_list_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/QuestListButton
@onready var _health_panel: PanelContainer = $Root/HealthPanel
@onready var _health_list: VBoxContainer = $Root/HealthPanel/HealthBox/HealthScroll/HealthList
@onready var _health_vitals: Label = $Root/HealthPanel/HealthBox/HealthVitals
@onready var _health_close_button: Button = $Root/HealthPanel/HealthBox/HealthCloseButton
@onready var _health_button: Button = $Root/PauseMenu/Center/Panel/MenuBox/HealthButton

## 提供 save_game()/load_game() 的后端（主场景），由 main.gd 注入。
var menu_backend: Node
## 任务管理模块（追踪状态与任务数据的唯一来源），由 main.gd 注入。
var _quests: QuestManager
var _player: Player
var _container: ContainerBase
var _sofa: Sofa
var _workbench: Workbench
var _recipes: Array[RecipeData] = []
var _day_night: DayNight
var _message_time := 0.0
var _thought_time := 0.0
var _equip_visible := false
## 容器模式标志：面板是开箱才出现的（关箱应整体关闭）还是 Tab 先开着。
var _gear_opened_by_container := false
var _menu_open := false
## 玩家点了"交付物资"；由 main.gd（任务状态机）裁决。
signal npc_deliver_pressed
## 玩家在睡眠菜单确认了时长（4/8 小时）；由 main.gd 执行睡眠结算。
signal sleep_confirmed(hours: float)

var _map_open := false


func _ready() -> void:
	_message_label.visible = false
	_thought_panel.visible = false
	_continue_button.pressed.connect(_on_pause_continue)
	_save_button.pressed.connect(_on_pause_save)
	_load_button.pressed.connect(_on_pause_load)
	_quit_button.pressed.connect(_on_pause_quit)
	_sofa_rest_button.pressed.connect(_on_sofa_rest)
	_sofa_search_button.pressed.connect(_on_sofa_search)
	_sofa_close_button.pressed.connect(_on_sofa_menu_closed)
	_craft_close_button.pressed.connect(_on_craft_menu_closed)
	_npc_close_button.pressed.connect(_on_npc_dialogue_closed)
	_npc_deliver_button.pressed.connect(func() -> void: npc_deliver_pressed.emit())
	_ending_continue.pressed.connect(_on_ending_continue)
	_ending_restart.pressed.connect(_on_ending_restart)
	_quest_list_button.pressed.connect(_on_quest_list_opened)
	_quest_close_button.pressed.connect(_on_quest_list_closed)
	_health_button.pressed.connect(_on_health_opened)
	_health_close_button.pressed.connect(_on_health_closed)
	_sleep4_button.pressed.connect(_on_sleep_confirmed.bind(4.0))
	_sleep8_button.pressed.connect(_on_sleep_confirmed.bind(8.0))
	_sleep_close_button.pressed.connect(close_sleep_menu)
	_recipes = Crafting.load_recipes()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message_label.visible = false
	if _thought_time > 0.0:
		_thought_time -= delta
		_thought_panel.modulate.a = clampf(_thought_time, 0.0, 1.0)  # 最后 1 秒淡出
		if _thought_time <= 0.0:
			_thought_panel.visible = false
	_update_interact_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu_open:
		return
	if event.is_action_pressed("toggle_map"):
		toggle_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_equipment"):
		_toggle_gear_panel()


## ESC 菜单：打开 = 暂停世界；HUD 因 PROCESS_MODE_ALWAYS 在暂停期间仍可点击。
func toggle_pause_menu() -> void:
	if _menu_open:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	_menu_open = true
	_pause_menu.visible = true
	get_tree().paused = true
	_continue_button.grab_focus()


func _close_menu() -> void:
	_menu_open = false
	_pause_menu.visible = false
	_quest_panel.visible = false
	_health_panel.visible = false
	get_tree().paused = false


func _on_pause_continue() -> void:
	_close_menu()


func _on_pause_save() -> void:
	if menu_backend != null and menu_backend.has_method("save_game"):
		menu_backend.save_game()
	_close_menu()


func _on_pause_load() -> void:
	if menu_backend != null and menu_backend.has_method("load_game"):
		menu_backend.load_game()
	_close_menu()

func _on_pause_quit() -> void:
	get_tree().paused = false
	get_tree().quit()


## 在主场景就绪后由 main.gd 调用，建立与玩家的联系并接上第一个容器（营地仓库）。
func bind(player: Player, camp: ContainerBase) -> void:
	_player = player
	attach_container(camp)
	player.stats_changed.connect(_refresh_bars)
	player.inventory_changed.connect(_refresh_inventory)
	player.equipped_changed.connect(_on_equipped_changed)
	_refresh_bars()
	_refresh_inventory()
	_on_equipped_changed()


## 注册一个容器（营地仓库、箱子……），其开/关驱动存储面板显示。
func attach_container(container: ContainerBase) -> void:
	container.open_changed.connect(_on_container_open_changed.bind(container))
	container.storage_changed.connect(_on_container_storage_changed.bind(container))


## 注册沙发：E 交互时弹出选项面板（休息 / 翻找物品）。
func attach_sofa(sofa: Sofa) -> void:
	_sofa = sofa
	sofa.menu_requested.connect(_on_sofa_menu)
	sofa.menu_closed.connect(_on_sofa_menu_closed)


## 注册工作台：E 交互时弹出制作面板。
func attach_workbench(workbench: Workbench) -> void:
	_workbench = workbench
	workbench.menu_requested.connect(_on_workbench_menu)
	workbench.menu_closed.connect(_on_craft_menu_closed)


## 注册地图数据：迷雾、建筑清单、标记字典（引用）、玩家——由 main.gd 注入。
func attach_map(fog: FogOfWar, buildings: Array, markers: Dictionary, player: Node2D) -> void:
	_map_canvas.fog = fog
	_map_canvas.buildings = buildings
	_map_canvas.markers = markers
	_map_canvas.player = player


## Tab 装备+背包面板：开关即互斥面板——打开时关掉地图，屏幕不留常驻背包。
## 容器打开时同面板切换为「左装备+背包 / 右箱子」容器模式（2026-10-15 第四批），
## 任务追踪面板在 GearPanel 显示期间隐藏避让。
func _toggle_gear_panel() -> void:
	_equip_visible = not _equip_visible
	_set_gear_panel_visible(_equip_visible)
	if _equip_visible:
		_close_map_if_open()
		_refresh_equipment()
		_refresh_inventory()
		_storage_box.visible = _container != null and _container.open
		_refresh_storage()
	elif _container != null and _container.open:
		_container.set_open(false)  # Tab 关掉 = 容器模式无处显示，随面板一起关


## GearPanel 显隐统一入口：同时处理任务追踪避让。
func _set_gear_panel_visible(shown: bool) -> void:
	_gear_panel.visible = shown
	_quest_tracker_panel.visible = not shown  # 面板居中放大，追踪卡避让不遮挡


## M 键地图：打开时刷新一帧绘制；与容器/沙发/制作/NPC 面板互斥。
func toggle_map(force: Variant = null) -> void:
	_map_open = (not _map_open) if force == null else bool(force)
	if _map_open:
		if _container != null and _container.open:
			_container.set_open(false)
		_sofa_panel.visible = false
		_craft_panel.visible = false
		_npc_panel.visible = false
		_map_canvas.refresh()
	_map_panel.visible = _map_open


func _close_map_if_open() -> void:
	if _map_open:
		toggle_map(false)


## 注册任务管理模块：追踪 HUD 与任务列表面板只读快照，状态全在 QuestManager。
## 任务/追踪变化 → 自动刷新右上角追踪面板；追踪槽满 → 顶部提示，不静默覆盖。
func attach_quests(quests: QuestManager) -> void:
	_quests = quests
	quests.quest_changed.connect(_refresh_quest_tracker)
	quests.tracked_changed.connect(_refresh_quest_tracker)
	quests.track_rejected.connect(func(_id: String) -> void:
		show_message("最多同时追踪 3 个任务，请先在任务列表里取消一个", 3.0))
	_refresh_quest_tracker()


## 右上角追踪面板：最多 3 个任务卡（标题 + 当前目标 + 完成计数），
## 无追踪任务时显示简洁空状态。整面板 mouse_filter=IGNORE，不挡游戏世界点击。
func _refresh_quest_tracker(_changed_id: String = "") -> void:
	if _quest_tracker_panel == null:
		return
	for child in _quest_tracker_list.get_children():
		_quest_tracker_list.remove_child(child)
		child.queue_free()
	var snapshot: Array = _quests.tracked_snapshot() if _quests != null else []
	_quest_tracker_empty.visible = snapshot.is_empty()
	# GearPanel 显示期间（装备/容器模式）追踪卡避让；面板关着时正常显示
	_quest_tracker_panel.visible = not _gear_panel.visible
	for entry in snapshot:
		var card := VBoxContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_constant_override("separation", 1)
		var title := Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.text = "◆ %s（%d/%d）" % [entry.title, entry.done, entry.total]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
		card.add_child(title)
		var obj := Label.new()
		obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
		obj.text = "  " + str(entry.current_text)
		obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		obj.custom_minimum_size = Vector2(240, 0)
		obj.max_lines_visible = 2
		obj.add_theme_font_size_override("font_size", 15)
		obj.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		card.add_child(obj)
		_quest_tracker_list.add_child(card)


## —— 任务列表面板（ESC 菜单 → 任务列表）—————————————————

func _on_quest_list_opened() -> void:
	_refresh_quest_panel()
	_quest_panel.visible = true


func _on_quest_list_closed() -> void:
	_quest_panel.visible = false


## 完整任务列表：每个已接取任务显示目标明细（✓/·）与追踪开关。
func _refresh_quest_panel() -> void:
	for child in _quest_panel_list.get_children():
		_quest_panel_list.remove_child(child)
		child.queue_free()
	if _quests == null:
		return
	var snapshot: Array = _quests.quests_snapshot()
	if snapshot.is_empty():
		var empty := Label.new()
		empty.text = "还没有任务。听听收音机的广播吧。"
		empty.add_theme_font_size_override("font_size", 14)
		_quest_panel_list.add_child(empty)
		return
	for entry in snapshot:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var head := HBoxContainer.new()
		var title := Label.new()
		title.text = str(entry.title) + ("（已完成）" if entry.completed else "")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color(0.9, 0.95, 0.85))
		head.add_child(title)
		var toggle := Button.new()
		toggle.custom_minimum_size = Vector2(72, 26)
		toggle.text = "取消追踪" if entry.tracked else "追踪"
		toggle.pressed.connect(_on_quest_track_toggled.bind(str(entry.id)))
		head.add_child(toggle)
		box.add_child(head)
		for obj in entry.objectives:
			var line := Label.new()
			line.text = ("  ✓ " if obj.done else "  · ") + str(obj.text)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_size_override("font_size", 14)
			line.add_theme_color_override("font_color",
					Color(0.6, 0.8, 0.6) if obj.done else Color(0.8, 0.8, 0.75))
			box.add_child(line)
		_quest_panel_list.add_child(box)


func _on_quest_track_toggled(quest_id: String) -> void:
	if _quests != null:
		_quests.toggle_track(quest_id)
	_refresh_quest_panel()


## —— 健康面板（ESC 菜单 → 健康状态）——————————————————————

func _on_health_opened() -> void:
	_quest_panel.visible = false  # 与任务列表互斥
	_refresh_health_panel()
	_health_panel.visible = true


func _on_health_closed() -> void:
	_health_panel.visible = false


## 生命/精力/疲劳总览 + 每个伤势/疾病一行（严重程度、属性影响、推荐治疗）。
func _refresh_health_panel() -> void:
	for child in _health_list.get_children():
		_health_list.remove_child(child)
		child.queue_free()
	if _player == null:
		return
	var stamina_sys := _player.stamina
	_health_vitals.text = "生命 %d/%d · 精力 %d/%d · 疲劳 %d（%s）" % [
		roundi(_player.health), _player.max_health,
		roundi(stamina_sys.stamina), roundi(stamina_sys.max_stamina()),
		roundi(stamina_sys.fatigue), stamina_sys.stage_label()]
	var lines := _player.medical.summary_lines()
	if lines.is_empty():
		var ok := Label.new()
		ok.text = "身体状态良好，没有伤势或疾病。"
		ok.add_theme_font_size_override("font_size", 14)
		ok.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		_health_list.add_child(ok)
		return
	for line_text in lines:
		var row := Label.new()
		row.text = "◆ " + str(line_text)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 14)
		var danger := str(line_text).contains("！") or str(line_text).contains("危险")
		row.add_theme_color_override("font_color",
				Color(0.95, 0.55, 0.45) if danger else Color(0.9, 0.85, 0.7))
		_health_list.add_child(row)


func _on_workbench_menu() -> void:
	if _container != null and _container.open:
		_container.set_open(false)  # 与容器面板互斥
	_sofa_panel.visible = false
	_npc_panel.visible = false  # 与对话面板互斥
	_close_map_if_open()
	_refresh_craft_list()
	_craft_panel.visible = true


func _on_craft_menu_closed() -> void:
	_craft_panel.visible = false


## 重建配方列表：每行一条配方，材料够绿色、缺的红色，"制作"按钮按需禁用。
func _refresh_craft_list() -> void:
	for child in _craft_list.get_children():
		_craft_list.remove_child(child)
		child.queue_free()
	if _player == null:
		return
	for recipe in _recipes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := RichTextLabel.new()
		info.bbcode_enabled = true
		info.fit_content = true
		info.custom_minimum_size = Vector2(240, 0)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.text = _recipe_bbcode(recipe)
		row.add_child(info)
		var button := Button.new()
		button.text = "制作"
		button.custom_minimum_size = Vector2(56, 30)
		button.pressed.connect(_on_craft_pressed.bind(recipe))
		button.disabled = not Crafting.can_craft(_player.inventory, recipe)
		row.add_child(button)
		_craft_list.add_child(row)


func _recipe_bbcode(recipe: RecipeData) -> String:
	var lines: Array[String] = [recipe.product.display_name]
	for i in recipe.ingredients.size():
		var mat := recipe.ingredients[i]
		var need := recipe.amounts[i] if i < recipe.amounts.size() else 1
		var have := _player.inventory.count_of(mat)
		var color := "#9fd89f" if have >= need else "#e08a8a"
		lines.append("[color=%s]%s %d/%d[/color]" % [color, mat.display_name, have, need])
	return "\n".join(lines)


func _on_craft_pressed(recipe: RecipeData) -> void:
	if _player == null or not Crafting.craft(_player.inventory, recipe):
		return
	_player.notify.emit("制作了 %s" % recipe.product.display_name)
	_refresh_craft_list()


func _on_sofa_menu() -> void:
	if _container != null and _container.open:
		_container.set_open(false)  # 与容器面板互斥
	_craft_panel.visible = false  # 与制作面板互斥
	_npc_panel.visible = false  # 与对话面板互斥
	_close_map_if_open()
	_refresh_sofa_buttons()
	_sofa_panel.visible = true


func _on_sofa_menu_closed() -> void:
	_sofa_panel.visible = false


func _refresh_sofa_buttons() -> void:
	_sofa_search_button.text = "翻找物品" if _sofa.can_search() else "翻找物品（今天翻过了）"


func _on_sofa_rest() -> void:
	if _sofa != null:
		_sofa.do_rest()
	_on_sofa_menu_closed()


func _on_sofa_search() -> void:
	if _sofa != null:
		_sofa.do_search()
	_on_sofa_menu_closed()


## 注册昼夜系统，左上角显示天数与时段。
func attach_day_night(day_night: DayNight) -> void:
	_day_night = day_night
	day_night.day_started.connect(refresh_day_label)
	day_night.night_started.connect(refresh_day_label)
	refresh_day_label(day_night.day_number)


## 天数标签刷新；读档后由 main.gd 直接调用。
func refresh_day_label(_day: int = -1) -> void:
	if _day_night.is_night:
		_day_label.text = "第 %d 天 · 夜晚" % _day_night.day_number
		_day_label.add_theme_color_override("font_color", Color(0.62, 0.68, 1.0))
	else:
		_day_label.text = "第 %d 天 · 白天" % _day_night.day_number
		_day_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))


func show_message(text: String, duration := 2.0) -> void:
	_message_label.text = text
	_message_label.visible = true
	_message_time = duration


## 主角内心独白：底部半透明气泡显示独白与（可选）引导提示，说完淡出。
func show_thought(text: String, hint: String = "") -> void:
	_thought_text.text = "「%s」" % text
	_thought_hint.text = hint
	_thought_hint.visible = hint != ""
	_thought_panel.visible = true
	_thought_panel.modulate.a = 1.0
	_thought_time = 5.0


## NPC 对话面板：显示台词（bbcode，任务清单用红绿标色）与"交付物资"按钮。
func show_npc_dialogue(npc_name: String, bbcode: String, can_deliver: bool) -> void:
	if _container != null and _container.open:
		_container.set_open(false)
	_sofa_panel.visible = false
	_craft_panel.visible = false
	_close_map_if_open()
	_npc_title.text = npc_name
	_npc_text.text = bbcode
	_npc_deliver_button.visible = can_deliver
	_npc_panel.visible = true


func _on_npc_dialogue_closed() -> void:
	_npc_panel.visible = false


## —— 睡眠菜单（床交互触发，main.gd 执行结算）—————————————————

## 打开睡眠菜单：与其它面板互斥；显示当前时刻/疲劳阶段与预计恢复效果。
func show_sleep_menu() -> void:
	if _container != null and _container.open:
		_container.set_open(false)
	_sofa_panel.visible = false
	_craft_panel.visible = false
	_npc_panel.visible = false
	_close_map_if_open()
	var st: StaminaSystem = _player.stamina
	var hour := 0.0
	var day_night := _day_night
	if day_night != null:
		hour = day_night.hour_of_day()
	_sleep_info.text = "当前时间 %02d:%02d · 疲劳 %d（%s）" % [
		int(hour), int(fmod(hour, 1.0) * 60.0), roundi(st.fatigue), st.stage_label()]
	_sleep4_button.text = "睡 4 小时（疲劳 -%d）" % roundi(st.sleep_relief_preview(4.0))
	_sleep8_button.text = "睡 8 小时（疲劳 -%d）" % roundi(st.sleep_relief_preview(8.0))
	_sleep_panel.visible = true


func close_sleep_menu() -> void:
	_sleep_panel.visible = false


func _on_sleep_confirmed(hours: float) -> void:
	_sleep_panel.visible = false
	sleep_confirmed.emit(hours)


## 结局面板：暂停世界，显示结局文字与统计；继续生存 / 重新开始。
func show_ending(days: int) -> void:
	_npc_panel.visible = false
	_set_gear_panel_visible(false)
	_equip_visible = false
	_storage_box.visible = false
	_sofa_panel.visible = false
	_craft_panel.visible = false
	_ending_title.text = "撤离成功"
	_ending_text.text = ("直升机轰鸣着爬升，整座城市在旋翼下渐渐缩小。\n\n"
			+ "你在废墟里撑过了 %d 个日夜——饥饿、干渴、撕咬都没有留下你。\n\n"
			+ "故事到这里结束了。但这个世界还在转动。") % days
	_ending_panel.visible = true
	get_tree().paused = true


func _on_ending_continue() -> void:
	_ending_panel.visible = false
	get_tree().paused = false


func _on_ending_restart() -> void:
	_ending_panel.visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _refresh_bars() -> void:
	_health_bar.max_value = _player.max_health
	_health_bar.value = _player.health
	_health_text.text = "生命 %d / %d" % [roundi(_player.health), _player.max_health]
	_food_bar.max_value = int(_player.max_food)
	_food_bar.value = _player.food
	_food_text.text = "饱食 %d / %d" % [roundi(_player.food), int(_player.max_food)]
	_water_bar.max_value = int(_player.max_water)
	_water_bar.value = _player.water
	_water_text.text = "饮水 %d / %d" % [roundi(_player.water), int(_player.max_water)]
	# 精力：当前值 / 动态上限（随疲劳压低）
	var st: StaminaSystem = _player.stamina
	_stamina_bar.max_value = st.max_stamina()
	_stamina_bar.value = st.stamina
	_stamina_text.text = "精力 %d / %d" % [roundi(st.stamina), roundi(st.max_stamina())]
	# 疲劳：0-100 + 阶段名
	_fatigue_bar.value = st.fatigue
	_fatigue_text.text = "疲劳 %d · %s" % [roundi(st.fatigue), st.stage_label()]


func _on_equipped_changed() -> void:
	_refresh_equip_label()
	_refresh_equipment()


func _refresh_equip_label() -> void:
	var hand: ItemData = _player.equipped.get(ItemData.SLOT_HAND_R)
	if hand == null:
		hand = _player.equipped.get(ItemData.SLOT_HAND_L)
	if hand == null:
		_equip_label.text = "武器：空手（伤害 %d）" % _player.unarmed_damage
	elif hand.kind == ItemData.KIND_GUN:
		var ammo := _player.ammo_pistol if hand.gun_ammo_type == "pistol" else _player.ammo_rifle
		_equip_label.text = "武器：%s（伤害 %d · %s 剩余 %d）" % [
			hand.display_name_tiered(), hand.damage, hand.ammo_display_name(), ammo]
	else:
		_equip_label.text = "武器：%s（伤害 %d）" % [hand.display_name_tiered(), hand.damage]


## —— Tab 装备面板：人体轮廓布局 ——————————————————————————————
## 7 个部位槽按人体位置摆放（形状+位置承担识别，文字降级为辅助）。
## 槽位尺寸本身就是信息：衣服最大、帽子最小。换美术时只改槽位贴图，布局不动。
## 2026-10-15 第四批 UI 放大：整体 ×1.25（槽 56→72 级别，容器 280×250→350×312）。
const BODY_SLOT_LAYOUT := {
	ItemData.SLOT_HEAD: {"pos": Vector2(140, 0), "size": Vector2(70, 45), "tag": "帽子"},
	ItemData.SLOT_HAND_L: {"pos": Vector2(8, 72), "size": Vector2(80, 80), "tag": "左手"},
	ItemData.SLOT_HAND_R: {"pos": Vector2(262, 72), "size": Vector2(80, 80), "tag": "右手"},
	ItemData.SLOT_BACKPACK: {"pos": Vector2(120, 72), "size": Vector2(110, 55), "tag": "背包"},
	ItemData.SLOT_CHEST: {"pos": Vector2(120, 135), "size": Vector2(110, 95), "tag": "衣服"},
	ItemData.SLOT_LEGS: {"pos": Vector2(120, 238), "size": Vector2(52, 62), "tag": "裤子"},
	ItemData.SLOT_FEET: {"pos": Vector2(178, 238), "size": Vector2(52, 62), "tag": "鞋子"},
}
## 槽位的显示顺序（从上到下：帽子 → 双手 → 背包 → 衣服 → 下肢）。
const BODY_SLOT_ORDER: Array[String] = [
	ItemData.SLOT_HEAD, ItemData.SLOT_HAND_L, ItemData.SLOT_HAND_R,
	ItemData.SLOT_BACKPACK, ItemData.SLOT_CHEST, ItemData.SLOT_LEGS, ItemData.SLOT_FEET,
]

var _body_slots: Dictionary = {}  # slot 名 -> Button（_refresh_equipment 首次构建）


## 装备面板：人体轮廓 7 槽 + 顶部属性条。点击已装备的部位脱下放回背包。
func _refresh_equipment() -> void:
	if _player == null or _body_layout == null:
		return
	if _body_slots.is_empty():
		for slot in BODY_SLOT_ORDER:
			var info: Dictionary = BODY_SLOT_LAYOUT[slot]
			var button := Button.new()
			button.position = info.pos
			button.size = info.size
			button.clip_text = true
			button.add_theme_font_size_override("font_size", 15)
			button.pressed.connect(_on_equip_slot_pressed.bind(slot))
			button.tooltip_text = "%s（点击脱下）" % info.tag
			_body_layout.add_child(button)
			_body_slots[slot] = button
	for slot in BODY_SLOT_ORDER:
		var info: Dictionary = BODY_SLOT_LAYOUT[slot]
		var button: Button = _body_slots[slot]
		var item: ItemData = _player.equipped.get(slot)
		if item != null:
			button.text = item.display_name_tiered()
			button.tooltip_text = "%s · %s（点击脱下）" % [info.tag, item.describe()]
			_style_slot_tier(button, item)
		else:
			button.text = info.tag
			button.tooltip_text = "%s（空）" % info.tag
			_style_slot_empty(button)
	_gear_stats.text = "攻击 %d · 护甲 %d · 移速 +%.0f%%" \
			% [_player.current_damage(), _player.total_defense(), _player.speed_bonus_pct()]


## 槽位分级边框：灰/绿/蓝/金（与背包格一致，余光可辨等级）。
## 底色比面板（0.14）稍亮 + 深色内衬描边，物品色块与面板背景分界清晰
## （2026-10-15 第三批：面板提亮后防止"物品融进面板"）。
func _style_slot_tier(button: Button, item: ItemData) -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.2, 0.21, 0.2)
	if item.tier >= 1 and ItemData.TIER_COLORS.has(item.tier):
		border.border_color = ItemData.TIER_COLORS[item.tier]
	else:
		border.border_color = Color(0.4, 0.43, 0.38)
	border.set_border_width_all(2)
	border.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", border)
	button.add_theme_stylebox_override("hover", border)


## 空槽底板：比面板稍亮的底色 + 暗描边，槽位轮廓一眼可辨。
func _style_slot_empty(button: Button) -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.18, 0.19, 0.18)
	border.border_color = Color(0.35, 0.38, 0.33)
	border.set_border_width_all(1)
	border.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", border)
	button.add_theme_stylebox_override("hover", border)


func _on_equip_slot_pressed(slot: String) -> void:
	_player.unequip_slot(slot)


func _refresh_inventory() -> void:
	_fill_grid(_inventory_grid, _player.inventory, false)


func _refresh_storage() -> void:
	if _container == null:
		return
	_fill_grid(_storage_grid, _container.storage, true)
	_storage_title.text = "%s（%d 件）· 点击存取" \
			% [_container.display_name, _container.storage.item_count()]


## 打开某个容器时切换面板归属；同时只显示一个容器。
## 容器与 Tab 共用 GearPanel：开箱即显示（记住是谁开的，关箱时按需还原）。
func _on_container_open_changed(open: bool, container: ContainerBase) -> void:
	if open:
		if _container != null and _container != container and _container.open:
			_container.set_open(false)
		_sofa_panel.visible = false  # 与沙发选项面板互斥
		_craft_panel.visible = false  # 与制作面板互斥
		_npc_panel.visible = false  # 与对话面板互斥
		_close_map_if_open()
		_container = container
		_gear_opened_by_container = not _equip_visible
		_equip_visible = true
		_set_gear_panel_visible(true)
		_storage_box.visible = true
		_refresh_storage()
		_refresh_equipment()
		_refresh_inventory()
	elif _container == container:
		_container = null
		_storage_box.visible = false
		if _gear_opened_by_container:
			# 面板是开箱才出现的：关箱即整体关闭，屏幕不留常驻面板
			_gear_opened_by_container = false
			_equip_visible = false
			_set_gear_panel_visible(false)
		# 否则面板本来就是 Tab 打开的：保持显示，切回纯装备布局


func _on_container_storage_changed(container: ContainerBase) -> void:
	if _container == container:
		_refresh_storage()


## 底部交互提示：显示最近可交互物的按键与名称。
func _update_interact_prompt() -> void:
	if _player == null:
		return
	var target := _player.nearest_interactable()
	if target == null:
		_prompt_label.visible = false
	else:
		_prompt_label.text = "[E] %s" % target.get_prompt()
		_prompt_label.visible = true


func _fill_grid(grid: GridContainer, inv: Inventory, is_storage: bool) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for index in inv.slots.size():
		var button := _make_slot_button(index, is_storage)
		grid.add_child(button)
		var item := inv.slots[index]
		if item == null:
			button.disabled = true
			continue
		var count := inv.count_at(index)
		button.text = item.display_name_tiered() + (" ×%d" % count if count > 1 else "")
		button.tooltip_text = item.display_name_tiered() + \
				(" ×%d" % count if count > 1 else "") + "\n" + item.describe()
		button.add_theme_font_size_override("font_size", 14)
		_add_color_chip(button, item.color)
		# 武器分级边框色：破烂灰 / 普通绿 / 精良蓝 / 稀有金
		if item.tier >= 1 and ItemData.TIER_COLORS.has(item.tier):
			var border := StyleBoxFlat.new()
			border.border_color = ItemData.TIER_COLORS[item.tier]
			border.set_border_width_all(2)
			button.add_theme_stylebox_override("normal", border)


func _make_slot_button(index: int, is_storage: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_text = true
	button.pressed.connect(_on_slot_pressed.bind(index, is_storage))
	button.gui_input.connect(_on_slot_gui_input.bind(index, is_storage))
	return button


## 右键背包格 = 丢弃到脚下。
func _on_slot_gui_input(event: InputEvent, index: int, is_storage: bool) -> void:
	if is_storage or _player == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_player.drop_item(index)


func _add_color_chip(button: Button, color: Color) -> void:
	var chip := ColorRect.new()
	chip.color = color
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	chip.offset_left = 4
	chip.offset_right = 10
	# 1px 深色描边：浅色面板上物品色块边界清晰（2026-10-15 第三批）。
	var outline := ReferenceRect.new()
	outline.border_color = Color(0.05, 0.06, 0.05, 0.9)
	outline.border_width = 1.0
	outline.editor_only = false
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(outline)
	button.add_child(chip)


## 背包格点击：容器打开时存入当前容器；否则 = 使用 / 装备。
## 容器格点击：取回到背包。
func _on_slot_pressed(index: int, is_storage: bool) -> void:
	if is_storage:
		if _container == null:
			return
		var item := _container.storage.peek(index)
		if item == null:
			return
		if _container.withdraw(index, _player.inventory):
			show_message("取回了 %s" % item.display_name_tiered())
		else:
			show_message("背包满了！")
	elif _container != null and _container.open:
		var item := _player.inventory.peek(index)
		if item == null:
			return
		_player.inventory.remove_item(index)
		_container.deposit(item)
		show_message("存入了 %s" % item.display_name)
	else:
		_player.use_item(index)
