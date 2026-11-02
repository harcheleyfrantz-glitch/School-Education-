extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.size = Vector2(400, 140)
	add_child(bg)
	var x := 10.0
	for k in ["moon", "sun", "star", "lock", "medal"]:
		var ic := UIIcon.make(k, 64, Color(1, 0.85, 0.4), 1.6)
		ic.position = Vector2(x, 30)
		add_child(ic)
		x += 76.0
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().get_region(Rect2i(0, 0, 400, 140)).save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
