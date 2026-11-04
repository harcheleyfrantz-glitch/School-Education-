extends Node
## Runs the real main menu with the performance governor on (rendered, not headless) and
## reports what it did: frame rate, resolution scale, preset and whether the 3D backdrop stayed.

func _ready() -> void:
	Game.settings.quality = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "medium"
	Game.settings.menu_backdrop_off = false
	Game.settings.auto_perf = true
	Game.apply_settings()
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	for i in 2:
		await get_tree().create_timer(5.0).timeout
		print("PERF t=%ds fps=%.1f scale=%.2f quality=%s backdrop_off=%s live_backdrop=%s" % [(i + 1) * 5, Game.perf_fps, Game.dyn_scale,
			Game.settings.quality, Game.settings.menu_backdrop_off, is_instance_valid(main.get("backdrop"))])
		print("   draws=%d objects3d=%d prims=%d nodes=%d canvas=%d cams=%d vps=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), get_tree().root.find_children("*", "CanvasItem", true, false).size(),
			get_tree().root.find_children("*", "Camera3D", true, false).size(), get_tree().root.find_children("*", "SubViewport", true, false).size()])
	var roots := {}
	for n3 in get_tree().root.find_children("*", "Node3D", true, false):
		var path := str((n3 as Node).get_path()).split("/")
		var key := "/".join(path.slice(0, mini(5, path.size())))
		roots[key] = int(roots.get(key, 0)) + 1
	for k in roots:
		print("   3D under ", k, ": ", roots[k])
	print("   cam ", get_viewport().get_camera_3d())
	get_tree().quit()
