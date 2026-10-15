extends SceneTree
## 迷雾视觉柔化原型 · 性能基准（2026-10-15）。
## 真实窗口渲染（不是 headless），玩家放开阔主街，mode 0 / mode 1 各跑
## 300 帧，统计平均/最低 FPS 与 _draw 平均耗时。
## 运行：Godot_console.exe --path <项目> --resolution 1152x648 -s tools/bench_fog.gd

const FRAMES := 300

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
	var fog: Node2D = main.get_node("FogOfWar")
	player.global_position = Vector2(800, 700)  # 主街开阔段，视野边界最大化
	fog.aim_override = Vector2.RIGHT

	for mode in 2:
		fog.visual_mode = mode
		var frame_min_ms := 1000.0
		var frame_max_ms := 0.0
		var frame_total_ms := 0.0
		var draw_total_us := 0
		var draw_peak_us := 0
		for i in FRAMES:
			var t0 := Time.get_ticks_usec()
			await process_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			frame_total_ms += ms
			frame_min_ms = minf(frame_min_ms, ms)
			frame_max_ms = maxf(frame_max_ms, ms)
			draw_total_us += fog.last_draw_usec
			draw_peak_us = maxi(draw_peak_us, fog.last_draw_usec)
		var avg_frame := frame_total_ms / FRAMES
		var avg_fps := 1000.0 / avg_frame if avg_frame > 0.0 else 0.0
		var worst_fps := 1000.0 / frame_max_ms if frame_max_ms > 0.0 else 0.0
		print("MODE %d | 平均帧耗时 %.2fms (≈%.0f FPS) | 最差帧 %.2fms (≈%.0f FPS)"
				% [mode, avg_frame, avg_fps, frame_max_ms, worst_fps])
		print("MODE %d | _draw 平均 %.0fus (%.2fms) | 峰值 %dus (%.2fms)"
				% [mode, float(draw_total_us) / FRAMES, draw_total_us / 1000.0 / FRAMES,
				draw_peak_us, draw_peak_us / 1000.0])
	fog.visual_mode = 0
	print("BENCH DONE")
	quit(0)
