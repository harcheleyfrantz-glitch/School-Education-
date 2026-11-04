extends Node
## Renders a story cutscene: screenshots every few seconds. Usage: -- out_dir chapter part
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp"
	var ch := int(a[1]) if a.size() > 1 else 0
	var part := a[2] if a.size() > 2 else "intro"
	Game.settings.quality = "high"
	if not Game.has_character():
		Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	Game.goto("cutscene", {"chapter": ch, "part": part})
	var t0 := Time.get_ticks_msec()
	var n := 0
	while n < 9 and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().create_timer(5.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("cut_%d_%s_%02d.png" % [ch, part, n]))
		n += 1
	get_tree().quit()
