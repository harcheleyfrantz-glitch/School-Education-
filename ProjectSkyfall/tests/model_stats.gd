extends Node
## Headless: builds every aircraft type at full and traffic detail and prints build time, mesh
## instance count and vertex / triangle totals, then exercises animate_simple on each.
## Usage: godot --headless --path . res://tests/model_stats.tscn


func _ready() -> void:
	for lod in [1.0, 0.45]:
		print("--- detail %.2f" % lod)
		for t in AircraftTypes.ORDER:
			for pass_i in 2:
				var m := AircraftModel.new()
				var t0 := Time.get_ticks_usec()
				m.build(t, "SKF", "CR-ABC", lod)
				var ms := float(Time.get_ticks_usec() - t0) / 1000.0
				add_child(m)
				m.animate_simple(0.5, 1.0, 12.0, {"nav": true, "strobe": true, "beacon": true, "landing": true}, 1.0, 0.016, 3.0)
				m.animate_simple(1.0, 0.0, 0.0, {}, 0.0, 0.016)
				if pass_i == 1:
					var st := _count(m)
					print("%-5s %s build %6.1f ms  mesh nodes %3d  verts %7d  tris %7d  lights %d" % [t, "cached" if pass_i == 1 else "first ", ms, st.x, st.y, st.z, m.lights.size()])
				else:
					print("%-5s first  build %6.1f ms" % [t, ms])
				m.queue_free()
	get_tree().quit()


func _count(n: Node) -> Vector3i:
	var out := Vector3i.ZERO
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh:
			var am: ArrayMesh = (c as MeshInstance3D).mesh
			out.x += 1
			for s in am.get_surface_count():
				var arr := am.surface_get_arrays(s)
				out.y += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				out.z += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		out += _count(c)
	return out
