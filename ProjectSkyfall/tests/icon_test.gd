extends Control
## Draws every UIIcon at a few sizes, one at a time, to catch degenerate polygons.

func _ready() -> void:
	for k in ["plane", "trophy", "moon", "fog", "wind", "clock", "user", "pin", "globe", "star", "bell", "news", "play", "medal", "lock"]:
		for px in [34, 24, 12]:
			print("ICON ", k, " ", px)
			var ic := UIIcon.make(k, px, Color.WHITE, 1.6)
			add_child(ic)
			await get_tree().process_frame
			await get_tree().process_frame
			ic.queue_free()
	print("ICON TEST DONE")
	get_tree().quit()
