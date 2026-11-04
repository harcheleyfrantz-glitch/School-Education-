extends Node
## Triangle counts and build times of hero aircraft per quality preset.
## Usage: -- [types comma list] [presets comma list]

func _tris(n: Node) -> int:
	var c := 0
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	for ch in list:
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				c += (idx as PackedInt32Array).size() / 3
			else:
				c += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return c


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var types := (a[0] if a.size() > 0 else "t172,s320,w350,q740").split(",")
	var presets := (a[1] if a.size() > 1 else "potato,medium,high,ultra").split(",")
	for pr in presets:
		Game.settings.quality = pr
		for t in types:
			var m := AircraftModel.new()
			add_child(m)
			var t0 := Time.get_ticks_msec()
			m.build(t, "SKF", "CR-TRI", 1.0)
			print("TRI %-7s %-5s %8d tris %6d ms" % [pr, t, _tris(m), Time.get_ticks_msec() - t0])
			remove_child(m)
			m.free()
	get_tree().quit()
