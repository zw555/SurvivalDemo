extends SceneTree
## 第五批视觉验证：玩家站到废弃车正下方，抓帧确认
## 「车身格点亮（能看清车全貌）、车后区域仍暗」的渲染模型修正效果。
## 运行：Godot_console.exe --path <项目> --write-movie "<输出目录>/shot.png" --resolution 1152x648 --quit-after 45 -s tools/shot_fog_occluder.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: Node2D = main.get_node("Player")
	player.global_position = Vector2(300, 810)  # Car1 (300,700) 正下方
	var fog: Node2D = main.get_node("FogOfWar")
	fog.aim_override = Vector2.UP
	for i in 32:  # 等 fog 自动刷新两轮以上（TICK_INTERVAL 0.15s）
		await physics_frame
	await process_frame
