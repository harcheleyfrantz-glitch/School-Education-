class_name AirportView
extends Node3D
## A loaded, visible airport. Positioned at the airport reference point (y = field elevation);
## children use airport-local coordinates.

var icao := ""
var layout: Dictionary = {}
var manager: AirportManager = null
var light_mat: ShaderMaterial
var pave_mats: Array = []
var facility_mats: Array = []
var bridges := []           # [{root: Node3D, tunnel: Node3D, cab: Node3D, rest_yaw, stand, docked}]
var windsocks := []         # [Node3D sock pivots]
var stand_occupied := {}    # stand name -> owner id


func build_from(product: Dictionary, mgr: AirportManager) -> void:
	manager = mgr
	icao = product.icao
	layout = AirportLayout.get_layout(icao)
	name = "Airport_" + icao
	for m in product.meshes:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mgr.material_for(m.key, m.params, self)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if m.key in ["paint", "vcolor"]:
			mi.visibility_range_end = 9000.0
		add_child(mi)
	for lb in product.labels:
		var l := Label3D.new()
		l.text = lb.text
		l.font_size = 64
		l.pixel_size = float(lb.size) / 46.0
		l.modulate = lb.color
		l.outline_size = int(lb.outline)
		l.outline_modulate = Color(0, 0, 0, 0.55)
		l.double_sided = false
		l.shaded = true
		l.transform = Transform3D(lb.basis, lb.pos)
		l.visibility_range_end = 900.0 if float(lb.size) < 4.0 else 4000.0
		add_child(l)
	# lights
	var lb_count: int = (product.lights as PackedFloat32Array).size() / 16
	if lb_count > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = lb_count
		mm.buffer = product.lights
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		light_mat = mgr.light_material
		mmi.material_override = light_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 400.0
		add_child(mmi)
	# parked cars
	var cc: int = (product.cars as PackedFloat32Array).size() / 16
	if cc > 0:
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_custom_data = true
		mm2.mesh = mgr.car_mesh
		mm2.instance_count = cc
		mm2.buffer = product.cars
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.multimesh = mm2
		mmi2.material_override = mgr.instanced_material
		mmi2.visibility_range_end = 2500.0
		add_child(mmi2)
	for b in product.bridges:
		_make_bridge(b)
	for w in product.windsocks:
		_make_windsock(w)


# ------------------------------------------------------------------ jet bridges
func _make_bridge(b: Dictionary) -> void:
	var root := Node3D.new()
	var rp: Vector2 = b.root
	var nrm: Vector2 = b.normal
	root.position = Vector3(rp.x, 0, rp.y)
	add_child(root)
	var mat: Material = manager.material_for("vcolor", {}, self)
	# fixed stub from the terminal to the rotunda
	var stub := MeshBuilder.new()
	var rot := rp + nrm * 9.0
	var stub_len := 9.0
	stub.xf = Transform3D(Basis(Vector3.UP, atan2(nrm.x, nrm.y)), Vector3.ZERO)
	stub.add_box(Vector3(0, 5.2, stub_len * 0.5), Vector3(3.2, 3.0, stub_len), Color(0.72, 0.74, 0.76))
	stub.xf = Transform3D.IDENTITY
	var rl := Vector3(rot.x - rp.x, 0, rot.y - rp.y)
	stub.add_cylinder(rl, rl + Vector3(0, 6.8, 0), 0.6, 0.6, 8, Color(0.5, 0.5, 0.52))
	stub.add_cylinder(rl + Vector3(0, 3.6, 0), rl + Vector3(0, 6.8, 0), 2.4, 2.4, 10, Color(0.75, 0.76, 0.78))
	var smi := MeshInstance3D.new()
	smi.mesh = stub.commit()
	smi.material_override = mat
	root.add_child(smi)
	# rotating, telescoping tunnel
	var pivot := Node3D.new()
	pivot.position = rl + Vector3(0, 5.2, 0)
	root.add_child(pivot)
	var tunnel := MeshInstance3D.new()
	var tb := MeshBuilder.new()
	tb.add_box(Vector3(0, 0, 0.5), Vector3(3.0, 2.9, 1.0), Color(0.78, 0.8, 0.82))
	tb.add_box(Vector3(1.52, -0.2, 0.5), Vector3(0.04, 1.1, 1.0), Color(0.2, 0.3, 0.38))
	tb.add_box(Vector3(-1.52, -0.2, 0.5), Vector3(0.04, 1.1, 1.0), Color(0.2, 0.3, 0.38))
	tunnel.mesh = tb.commit()
	tunnel.material_override = mat
	pivot.add_child(tunnel)
	var cab := Node3D.new()
	pivot.add_child(cab)
	var cb := MeshBuilder.new()
	cb.add_box(Vector3(0, 0, 1.6), Vector3(3.6, 3.2, 3.2), Color(0.7, 0.72, 0.74))
	cb.add_box(Vector3(0, -0.2, 3.25), Vector3(3.0, 2.6, 0.15), Color(0.15, 0.15, 0.15))
	cb.add_box(Vector3(0, -4.3, 0.0), Vector3(2.8, 0.7, 1.4), Color(0.25, 0.25, 0.25))
	cb.add_box(Vector3(0, -2.4, 0.0), Vector3(0.35, 3.6, 0.35), Color(0.4, 0.4, 0.42))
	var cmi := MeshInstance3D.new()
	cmi.mesh = cb.commit()
	cmi.material_override = mat
	cab.add_child(cmi)
	# parked: swung along the facade toward the aircraft's side
	var left: Vector2 = b.left
	var park_dir := (nrm * 0.55 - left * 0.6).normalized()
	var rest_yaw := atan2(park_dir.x, park_dir.y)
	var br := {"root": root, "pivot": pivot, "tunnel": tunnel, "cab": cab, "rest_yaw": rest_yaw, "stand": b.stand,
		"docked": false, "length": 12.0, "yaw": rest_yaw, "target_len": 12.0, "target_yaw": rest_yaw, "height": 5.2, "target_h": 5.2}
	bridges.append(br)
	_apply_bridge(br)


func _apply_bridge(br: Dictionary) -> void:
	br.pivot.rotation = Vector3(0, br.yaw, 0)
	br.pivot.position.y = br.height
	br.tunnel.scale = Vector3(1, 1, br.length)
	br.cab.position = Vector3(0, 0, br.length)


func dock_bridge(stand_name: String, door_local: Vector3) -> bool:
	## Extends the stand's jet bridge to a door position given in airport-local coordinates.
	for br in bridges:
		var s: Dictionary = layout.stands[br.stand]
		if s.name != stand_name:
			continue
		var piv: Vector3 = br.root.position + br.pivot.position
		var to := door_local - piv
		to.y = 0.0
		var length := to.length() - 3.4
		br.target_yaw = atan2(to.x, to.z)
		br.target_len = clampf(length, 6.0, 38.0)
		br.target_h = clampf(door_local.y - 1.0, 2.5, 7.0)
		br.docked = true
		return true
	return false


func undock_bridge(stand_name: String) -> void:
	for br in bridges:
		var s: Dictionary = layout.stands[br.stand]
		if s.name == stand_name:
			br.target_yaw = br.rest_yaw
			br.target_len = 12.0
			br.target_h = 5.2
			br.docked = false


func bridge_state(stand_name: String) -> String:
	for br in bridges:
		if layout.stands[br.stand].name == stand_name:
			if br.docked and absf(br.length - br.target_len) < 0.05 and absf(angle_difference(br.yaw, br.target_yaw)) < 0.01:
				return "docked"
			return "moving" if br.docked else "retracted"
	return "none"


# ------------------------------------------------------------------ windsocks
func _make_windsock(p: Vector3) -> void:
	var mat: Material = manager.material_for("vcolor", {}, self)
	var pole := MeshBuilder.new()
	pole.add_cylinder(p, p + Vector3(0, 6.5, 0), 0.09, 0.07, 6, Color(0.85, 0.85, 0.85))
	var pmi := MeshInstance3D.new()
	pmi.mesh = pole.commit()
	pmi.material_override = mat
	add_child(pmi)
	var pivot := Node3D.new()
	pivot.position = p + Vector3(0, 6.4, 0)
	add_child(pivot)
	var sock := MeshBuilder.new()
	for k in 5:
		var z0 := k * 0.75
		var r0 := lerpf(0.45, 0.22, k / 5.0)
		var r1 := lerpf(0.45, 0.22, (k + 1) / 5.0)
		var col := Color(0.95, 0.35, 0.05) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
		sock.add_cylinder(Vector3(0, 0, z0), Vector3(0, 0, z0 + 0.75), r0, r1, 10, col, false)
	var smi := MeshInstance3D.new()
	smi.mesh = sock.commit()
	smi.material_override = manager.material_for("vcolor_2s", {}, self)
	pivot.add_child(smi)
	windsocks.append(pivot)


func update_wind(dir_from_deg: float, speed_kt: float) -> void:
	# the sock points downwind and droops in light wind
	var to := deg_to_rad(dir_from_deg + 180.0)
	var droop := lerpf(1.2, 0.05, clampf(speed_kt / 15.0, 0.0, 1.0))
	for pv in windsocks:
		pv.rotation = Vector3(0, 0, 0)
		pv.basis = Basis(Vector3.UP, atan2(sin(to), -cos(to))) * Basis(Vector3.RIGHT, droop)


func _process(delta: float) -> void:
	for br in bridges:
		var changed := false
		var ny := rotate_toward(br.yaw, br.target_yaw, 0.25 * delta)
		var nl := move_toward(br.length, br.target_len, 1.6 * delta)
		var nh := move_toward(br.height, br.target_h, 0.4 * delta)
		if ny != br.yaw or nl != br.length or nh != br.height:
			changed = true
		br.yaw = ny
		br.length = nl
		br.height = nh
		if changed:
			_apply_bridge(br)


# ------------------------------------------------------------------ queries (airport-local)
func stand_local(stand_name: String) -> Dictionary:
	return AirportLayout.stand_by_name(layout, stand_name)
