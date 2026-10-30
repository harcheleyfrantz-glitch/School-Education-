extends Node
func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Geo.ready = false
	Geo.init_world()
	print("Geo.init_world %d ms" % (Time.get_ticks_msec() - t0))
	var t1 := Time.get_ticks_msec()
	var main: Node = (load("res://src/main.gd") as GDScript).new()
	add_child(main)
	print("main ready (menu + backdrop) %d ms" % (Time.get_ticks_msec() - t1))
	get_tree().quit()
