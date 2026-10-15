extends SceneTree
## 迷雾视觉柔化原型 · 五场景对比抓帧（2026-10-15）。
## 运行（-- 之后是用户参数）：
## Godot_console.exe --path <项目> --write-movie "<目录>/<名>.png" --resolution 1152x648
##   --quit-after 45 -s tools/shot_fog_visual.gd -- pos=800,700 aim=1,0 mode=1
## pos=玩家世界坐标  aim=视野方向向量  mode=绘制模式(0/1)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var pos := Vector2(800, 700)
	var aim := Vector2.RIGHT
	var mode := 0
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		var v := kv[1].split(",")
		if kv[0] == "pos" and v.size() == 2:
			pos = Vector2(float(v[0]), float(v[1]))
		elif kv[0] == "aim" and v.size() == 2:
			aim = Vector2(float(v[0]), float(v[1])).normalized()
		elif kv[0] == "mode":
			mode = int(v[0])
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: Node2D = main.get_node("Player")
	player.global_position = pos
	var fog: Node2D = main.get_node("FogOfWar")
	fog.visual_mode = mode
	fog.aim_override = aim
	for i in 32:  # 等迷雾自动刷新两轮以上
		await physics_frame
	await process_frame
	print("SHOT DONE pos=%s mode=%d" % [pos, mode])
	quit(0)
