class_name Landmarks
extends Node3D
## Famous buildings and skylines of the real-world region (RealWorld.LANDMARKS): the Statue of
## Liberty, the Empire State Building, Big Ben, the Eiffel Tower, the Golden Gate Bridge and the
## rest. Each is a procedural model streamed in when the camera comes within range. Skyscrapers
## use the city building shader (windows by day, lights at night); monuments are floodlit after
## dark. Every model also reports simple collision boxes so aircraft can hit them.

const BUILD_RANGE := 48000.0
const DROP_RANGE := 62000.0

var view: WorldView
var built := {}            # id -> {root, boxes}
var _timer := 0.0
var _plain: StandardMaterial3D
var _glow := 0.0

## Skyline clusters: footprint (m), tower count, height range (m), share of glass towers, seed.
const SKYLINES := {
	"skyline_midtown": [2300.0, 1100.0, 74, 110.0, 330.0, 0.55, 11],
	"skyline_downtown": [1000.0, 850.0, 32, 90.0, 290.0, 0.6, 12],
	"skyline_city": [1100.0, 750.0, 26, 70.0, 260.0, 0.75, 13],
	"skyline_wharf": [650.0, 450.0, 14, 120.0, 235.0, 0.9, 14],
	"skyline_defense": [900.0, 550.0, 18, 80.0, 230.0, 0.85, 15],
	"skyline_sf": [1300.0, 850.0, 32, 80.0, 300.0, 0.6, 16],
	"skyline_la": [1100.0, 950.0, 26, 90.0, 310.0, 0.6, 17],
	"skyline_chicago": [1500.0, 1000.0, 50, 100.0, 340.0, 0.5, 18],
	"skyline_toronto": [1100.0, 750.0, 34, 90.0, 290.0, 0.7, 19],
	"skyline_miami": [1200.0, 650.0, 34, 80.0, 260.0, 0.75, 20],
	"skyline_boston": [850.0, 650.0, 18, 80.0, 240.0, 0.6, 21],
	"skyline_madrid": [500.0, 500.0, 9, 110.0, 250.0, 0.8, 22],
	"skyline_atlanta": [1100.0, 800.0, 30, 90.0, 300.0, 0.6, 23],
	"skyline_dallas": [1000.0, 800.0, 28, 90.0, 280.0, 0.6, 24],
	"skyline_denver": [800.0, 650.0, 20, 80.0, 220.0, 0.65, 25],
	"skyline_seattle": [900.0, 650.0, 24, 80.0, 280.0, 0.6, 26],
	"skyline_vegas": [600.0, 3200.0, 34, 90.0, 210.0, 0.8, 27],
	"skyline_frankfurt": [800.0, 600.0, 16, 110.0, 270.0, 0.7, 28],
	"skyline_tokyo": [2600.0, 1800.0, 90, 90.0, 260.0, 0.5, 29],
	"skyline_shanghai": [1300.0, 900.0, 36, 120.0, 420.0, 0.75, 30],
	"skyline_hongkong": [2000.0, 700.0, 70, 110.0, 380.0, 0.65, 31],
	"skyline_singapore": [1100.0, 800.0, 34, 100.0, 280.0, 0.7, 32],
	"skyline_kl": [1000.0, 800.0, 26, 90.0, 300.0, 0.65, 33],
	"skyline_dubai": [700.0, 3500.0, 44, 120.0, 350.0, 0.8, 34],
	"skyline_doha": [800.0, 700.0, 22, 100.0, 300.0, 0.8, 35],
	"skyline_seoul": [1600.0, 1200.0, 50, 80.0, 260.0, 0.55, 36],
	"skyline_beijing": [1000.0, 800.0, 30, 100.0, 330.0, 0.6, 37],
	"skyline_bangkok": [1200.0, 900.0, 34, 90.0, 300.0, 0.55, 38],
	"skyline_mumbai": [1200.0, 1500.0, 36, 80.0, 280.0, 0.55, 39],
}


func setup(world_view: WorldView) -> void:
	view = world_view
	_plain = StandardMaterial3D.new()
	_plain.vertex_color_use_as_albedo = true
	_plain.vertex_color_is_srgb = true
	_plain.roughness = 0.82
	_plain.emission_enabled = true
	_plain.emission = Color(1.0, 0.82, 0.58)
	_plain.emission_energy_multiplier = 0.0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or view == null:
		return
	_timer = 0.8
	var cam := view.camera if view.camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return
	var cx := view.wx(cam.global_position)
	var cz := view.wz(cam.global_position)
	if cz < Geo.MAP_HALF - DROP_RANGE:
		if not built.is_empty():
			for id in built.keys():
				_drop(id)
		return
	for lm in RealWorld.LANDMARKS:
		var d := Vector2(cx, cz).distance_to(Vector2(float(lm.x), float(lm.z)))
		var id := String(lm.id)
		if d < BUILD_RANGE and not built.has(id):
			_build(lm)
		elif d > DROP_RANGE and built.has(id):
			_drop(id)
	# floodlights come on after dark
	var g := clampf(view.night * 1.4 - 0.2, 0.0, 1.0) * 0.32
	if absf(g - _glow) > 0.01:
		_glow = g
		_plain.emission_energy_multiplier = g


func _drop(id: String) -> void:
	var b: Dictionary = built[id]
	if is_instance_valid(b.root):
		view.unregister_static(b.root)
		b.root.queue_free()
	built.erase(id)


## Collision boxes near a world position: [{c: Vector3 (world), h: Vector3 half extents, name}].
func boxes_near(x: float, z: float, r: float) -> Array:
	var out := []
	for id in built:
		for bx in built[id].boxes:
			var c: Vector3 = bx.c
			if absf(c.x - x) < r + bx.h.x and absf(c.z - z) < r + bx.h.z:
				out.append(bx)
	return out


func _build(lm: Dictionary) -> void:
	var x := float(lm.x)
	var z := float(lm.z)
	var kind := String(lm.kind)
	var ground := maxf(Geo.ground_height(x, z), 0.0) if not kind.begins_with("bridge") else 0.0
	var root := Node3D.new()
	root.name = "LM_" + String(lm.id)
	var yaw := float(lm.yaw)
	if kind == "hollywood":
		var cc := Airports.city_center(String(lm.icao))
		yaw = rad_to_deg(atan2(cc.x - x, -(cc.y - z)))
	root.rotation.y = -deg_to_rad(yaw)
	view.static_root.add_child(root)
	view.register_static(root, x, ground, z)
	var plain := MeshBuilder.new()
	var towers := []        # [MeshBuilder, facade color] drawn with the building shader
	var boxes := []         # local collision boxes [center, half]
	if SKYLINES.has(kind):
		_skyline(root, lm, SKYLINES[kind], yaw, boxes)
	else:
		match kind:
			"liberty":
				_liberty(plain, boxes)
			"empire":
				towers.append([_empire(boxes), Color(0.74, 0.7, 0.62)])
			"one_wtc":
				towers.append([_one_wtc(boxes), Color(0.55, 0.66, 0.78)])
			"willis":
				towers.append([_willis(boxes), Color(0.16, 0.16, 0.18)])
				_antennas(plain, Vector3(-12, 442, -6), Vector3(12, 442, -6), 85.0)
			"shard":
				towers.append([_shard(boxes), Color(0.62, 0.72, 0.82)])
			"cn_tower":
				_cn_tower(plain, boxes)
			"bridge_brooklyn":
				_suspension(plain, boxes, 480.0, 84.0, 38.0, 940.0, 34.0, Color(0.66, 0.58, 0.48), Color(0.3, 0.3, 0.32), true)
			"bridge_golden":
				_suspension(plain, boxes, 1280.0, 227.0, 67.0, 2300.0, 27.0, Color(0.78, 0.24, 0.1), Color(0.75, 0.22, 0.1), false)
			"bridge_tower":
				_tower_bridge(plain, boxes)
			"big_ben":
				_big_ben(plain, boxes)
			"london_eye":
				_london_eye(plain, boxes)
			"eiffel":
				_eiffel(plain, boxes)
			"arc":
				_arc(plain, boxes)
			"hollywood":
				_hollywood(root)
			"capitol":
				_capitol(plain, boxes)
			"obelisk":
				_obelisk(plain, boxes)
			"colosseum":
				_colosseum(plain, boxes)
			"dome_church":
				_dome_church(plain, boxes)
			"windmills":
				_windmills(plain, boxes)
			"church_tower":
				_church_tower(plain, boxes)
			"space_needle":
				_space_needle(plain, boxes)
			"tv_tower":
				_tv_tower(plain, boxes)
			"reunion":
				_reunion(plain, boxes)
			"brandenburg":
				_brandenburg(plain, boxes)
			"sagrada":
				_sagrada(plain, boxes)
			"atomium":
				_atomium(plain, boxes)
			"castle":
				_castle(plain, boxes)
			"twin_towers_church":
				_twin_church(plain, boxes)
			"burj":
				_burj(plain, boxes)
			"petronas":
				_petronas(plain, boxes)
			"mbs":
				_mbs(plain, boxes)
			"taipei101":
				_taipei101(plain, boxes)
			"pyramids":
				_pyramids(plain, boxes)
			"parthenon":
				_parthenon(plain, boxes)
			"pagoda":
				_pagoda(plain, boxes)
			"onion_domes":
				_onion_domes(plain, boxes)
	if plain.vcount() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = plain.commit()
		mi.material_override = _plain
		mi.visibility_range_end = 42000.0
		root.add_child(mi)
	for t in towers:
		_add_tower_mesh(root, t[0], t[1])
	var wb := []
	var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
	for bx in boxes:
		var c: Vector3 = basis * (bx[0] as Vector3)
		var hh: Vector3 = bx[1]
		# axis-aligned bound of the rotated box
		var ext := (basis * Vector3(hh.x, 0, 0)).abs() + (basis * Vector3(0, 0, hh.z)).abs()
		wb.append({"c": Vector3(x + c.x, ground + c.y, z + c.z), "h": Vector3(ext.x, hh.y, ext.z), "name": String(lm.name)})
	built[String(lm.id)] = {"root": root, "boxes": wb}


func _add_tower_mesh(root: Node3D, mb: MeshBuilder, facade: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mb.commit()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, Color(facade.r, facade.g, facade.b, 0.37))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = view.terrain.building_material
	mmi.visibility_range_end = 42000.0
	root.add_child(mmi)


# ================================================================== skylines
func _skyline(root: Node3D, lm: Dictionary, p: Array, yaw: float, boxes: Array) -> void:
	## A cluster of downtown towers on the city building shader, kept off the water.
	var r := RandomNumberGenerator.new()
	r.seed = int(p[6]) * 7919
	var w: float = p[0]
	var d: float = p[1]
	var n: int = p[2]
	var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
	var glass := PackedFloat32Array()
	var office := PackedFloat32Array()
	var x0 := float(lm.x)
	var z0 := float(lm.z)
	var g0 := maxf(Geo.ground_height(x0, z0), 0.0)
	var placed := []
	var tries := 0
	while placed.size() < n and tries < n * 6:
		tries += 1
		# taller towers cluster toward the middle
		var u := r.randf_range(-0.5, 0.5)
		var v := r.randf_range(-0.5, 0.5)
		var core := 1.0 - clampf(Vector2(u * 1.6, v * 1.6).length(), 0.0, 1.0)
		var lp := Vector3(u * w, 0.0, v * d)
		var wp: Vector3 = basis * lp
		var wx := x0 + wp.x
		var wz := z0 + wp.z
		if Geo.is_water(wx, wz):
			continue
		var tw := r.randf_range(24.0, 46.0)
		var clash := false
		for q in placed:
			if Vector2(q.x, q.z).distance_to(Vector2(lp.x, lp.z)) < (q.w + tw) * 0.62:
				clash = true
				break
		if clash:
			continue
		var h := lerpf(float(p[3]), float(p[4]), pow(r.randf(), 1.6) * 0.55 + core * 0.45)
		var gh := Geo.ground_height(wx, wz) - g0
		placed.append({"x": lp.x, "z": lp.z, "w": tw})
		var is_glass := r.randf() < float(p[5])
		var col: Color = U.pick(r, [Color(0.42, 0.52, 0.62), Color(0.35, 0.45, 0.52), Color(0.55, 0.6, 0.66), Color(0.3, 0.38, 0.48), Color(0.6, 0.62, 0.62)]) if is_glass \
			else U.pick(r, [Color(0.72, 0.68, 0.6), Color(0.62, 0.58, 0.54), Color(0.78, 0.74, 0.68), Color(0.55, 0.45, 0.38), Color(0.66, 0.66, 0.64)])
		var td := tw * r.randf_range(0.8, 1.25)
		var rot := float(r.randi() % 4) * PI * 0.5
		if is_glass:
			TerrainManager._push_instance(glass, Vector3(lp.x, gh - 2.0, lp.z), rot, Vector3(tw, h + 2.0, td), col, r.randf())
		else:
			TerrainManager._push_instance(office, Vector3(lp.x, gh - 2.0, lp.z), rot, Vector3(tw, h + 2.0, td), col, r.randf())
		boxes.append([Vector3(lp.x, gh + h * 0.5, lp.z), Vector3(maxf(tw, td) * 0.5, h * 0.5, maxf(tw, td) * 0.5)])
	TerrainManager._ensure_meshes()
	for pair in [[glass, TerrainManager._tower_mesh], [office, TerrainManager._building_mesh]]:
		var buf: PackedFloat32Array = pair[0]
		if buf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = pair[1]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = view.terrain.building_material
		mmi.visibility_range_end = 45000.0
		root.add_child(mmi)


# ================================================================== New York
func _liberty(mb: MeshBuilder, boxes: Array) -> void:
	var stone := Color(0.62, 0.6, 0.55)
	var granite := Color(0.74, 0.7, 0.62)
	var copper := Color(0.38, 0.64, 0.55)
	# Liberty Island with the star fort under the pedestal
	mb.add_cylinder(Vector3(0, -24, 0), Vector3(0, 2.5, 0), 150.0, 140.0, 24, Color(0.33, 0.45, 0.25))
	mb.add_cylinder(Vector3(0, 2.5, 0), Vector3(0, 10, 0), 62.0, 60.0, 11, stone)
	mb.add_cylinder(Vector3(0, 10, 0), Vector3(0, 57, 0), 21.0, 14.5, 4, granite)
	mb.add_cylinder(Vector3(0, 57, 0), Vector3(0, 59, 0), 16.0, 16.0, 4, granite)
	# robed figure, head, crown, torch arm and tablet
	mb.add_cylinder(Vector3(0, 59, 0), Vector3(0, 88, -0.5), 7.0, 4.2, 10, copper)
	mb.add_sphere(Vector3(0, 88.5, -0.5), Vector3(5.2, 3.2, 4.0), 10, 6, copper)
	mb.add_sphere(Vector3(0, 93.5, -0.8), Vector3(2.6, 3.0, 2.6), 10, 6, copper)
	for k in 7:
		var a := deg_to_rad(-75.0 + k * 25.0)
		var dirv := Vector3(sin(a), 0.35, -cos(a)).normalized()
		mb.add_cone(Vector3(0, 95, -0.8) + dirv * 2.2, Vector3(0, 95, -0.8) + dirv * 6.5, 0.55, 4, copper)
	mb.add_cylinder(Vector3(3.2, 89, -0.5), Vector3(5.4, 104, -1.2), 1.6, 1.2, 6, copper)
	mb.add_cylinder(Vector3(5.4, 104, -1.2), Vector3(5.6, 108, -1.3), 1.5, 1.9, 8, Color(0.75, 0.6, 0.3))
	mb.add_cone(Vector3(5.6, 108, -1.3), Vector3(5.8, 113, -1.3), 1.8, 8, Color(0.98, 0.78, 0.32))
	mb.add_box_xf(Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(-4.8, 79, -2.0)), Vector3(2.0, 6.5, 1.2), copper)
	boxes.append([Vector3(0, 30, 0), Vector3(21, 30, 21)])
	boxes.append([Vector3(0, 86, 0), Vector3(7, 27, 7)])


func _empire(boxes: Array) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var w := Color(1.0, 0, 0, 1.0)
	for tier in [[0.0, 25.0, 129.0, 57.0], [25.0, 86.0, 100.0, 50.0], [86.0, 320.0, 60.0, 42.0], [320.0, 342.0, 50.0, 32.0],
			[342.0, 362.0, 38.0, 25.0], [362.0, 373.0, 25.0, 19.0]]:
		var h := float(tier[1]) - float(tier[0])
		mb.add_box(Vector3(0, float(tier[0]) + h * 0.5, 0), Vector3(tier[2], h, tier[3]), w)
	var plinth := Color(1.0, 0, 0, 0.25)
	mb.add_cylinder(Vector3(0, 373, 0), Vector3(0, 405, 0), 7.0, 4.0, 8, plinth)
	mb.add_cylinder(Vector3(0, 405, 0), Vector3(0, 443, 0), 1.2, 0.4, 6, plinth)
	boxes.append([Vector3(0, 186, 0), Vector3(40, 186, 28)])
	return mb


func _one_wtc(boxes: Array) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var g := Color(0.5, 0, 0, 1.0)
	mb.add_box(Vector3(0, 28, 0), Vector3(62, 56, 62), Color(0.5, 0, 0, 1.0))
	mb.add_cylinder(Vector3(0, 56, 0), Vector3(0, 417, 0), 43.0, 22.0, 8, g)
	mb.add_cylinder(Vector3(0, 417, 0), Vector3(0, 425, 0), 22.0, 18.0, 8, Color(0.5, 0, 0, 0.25))
	mb.add_cylinder(Vector3(0, 425, 0), Vector3(0, 541, 0), 1.6, 0.5, 6, Color(0.5, 0, 0, 0.25))
	boxes.append([Vector3(0, 210, 0), Vector3(32, 210, 32)])
	return mb


func _willis(boxes: Array) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var g := Color(0.5, 0, 0, 1.0)
	var heights := [[270.0, 368.0, 205.0], [442.0, 442.0, 270.0], [205.0, 368.0, 270.0]]
	for i in 3:
		for j in 3:
			var h: float = heights[i][j]
			mb.add_box(Vector3((i - 1) * 23.0, h * 0.5, (j - 1) * 23.0), Vector3(23.0, h, 23.0), g)
	boxes.append([Vector3(0, 221, 0), Vector3(35, 221, 35)])
	return mb


func _antennas(mb: MeshBuilder, a: Vector3, b: Vector3, h: float) -> void:
	for p in [a, b]:
		mb.add_cylinder(p, p + Vector3(0, h, 0), 1.4, 0.4, 6, Color(0.85, 0.85, 0.85))


# ================================================================== London
func _shard(boxes: Array) -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.xf = Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 245, 0), 44.0, 12.0, 4, Color(0.5, 0, 0, 1.0), true)
	mb.add_cylinder(Vector3(0, 245, 0), Vector3(0, 310, 0), 12.0, 0.6, 4, Color(0.5, 0, 0, 0.25), false)
	mb.xf = Transform3D.IDENTITY
	boxes.append([Vector3(0, 130, 0), Vector3(30, 130, 30)])
	return mb


func _big_ben(mb: MeshBuilder, boxes: Array) -> void:
	var sand := Color(0.8, 0.7, 0.5)
	var slate := Color(0.25, 0.28, 0.3)
	var face := Color(0.96, 0.93, 0.8)
	# Palace of Westminster along the river, with Victoria Tower at the far end
	mb.add_box(Vector3(130, 14, 0), Vector3(270, 28, 70), sand)
	mb.add_box(Vector3(130, 30.5, 0), Vector3(262, 5, 40), slate)
	for k in 18:
		var px := 10.0 + k * 15.0
		mb.add_cone(Vector3(px, 28, 33), Vector3(px, 40, 33), 1.6, 4, sand)
		mb.add_cone(Vector3(px, 28, -33), Vector3(px, 40, -33), 1.6, 4, sand)
	mb.add_box(Vector3(262, 49, 0), Vector3(23, 98, 23), sand)
	mb.add_cylinder(Vector3(262, 98, 0), Vector3(262, 108, 0), 14.0, 9.0, 4, slate)
	mb.add_cylinder(Vector3(128, 28, 0), Vector3(128, 82, 0), 9.0, 2.0, 8, sand)
	# Elizabeth Tower
	mb.add_box(Vector3(0, 27.5, 0), Vector3(12, 55, 12), sand)
	mb.add_box(Vector3(0, 61.5, 0), Vector3(14.5, 13, 14.5), sand)
	for s in [Vector3(0, 0, -7.3), Vector3(0, 0, 7.3), Vector3(-7.3, 0, 0), Vector3(7.3, 0, 0)]:
		var sz := Vector3(9, 9, 0.4) if absf(s.z) > 0.0 else Vector3(0.4, 9, 9)
		mb.add_box(Vector3(s.x, 62, s.z), sz, face)
	mb.add_box(Vector3(0, 72, 0), Vector3(12, 8, 12), sand)
	mb.xf = Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	mb.add_cone(Vector3(0, 76, 0), Vector3(0, 96, 0), 8.6, 4, slate)
	mb.xf = Transform3D.IDENTITY
	boxes.append([Vector3(0, 48, 0), Vector3(8, 48, 8)])
	boxes.append([Vector3(130, 20, 0), Vector3(135, 20, 35)])
	boxes.append([Vector3(262, 54, 0), Vector3(12, 54, 12)])


func _london_eye(mb: MeshBuilder, boxes: Array) -> void:
	var white := Color(0.92, 0.93, 0.95)
	var cy := 75.0
	var rr := 66.0
	var n := 64
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := Vector3(cos(a0) * rr, cy + sin(a0) * rr, 0)
		var p1 := Vector3(cos(a1) * rr, cy + sin(a1) * rr, 0)
		mb.add_cylinder(p0, p1, 1.1, 1.1, 4, white, false)
	for k in 16:
		var a := TAU * k / 16.0
		mb.add_cylinder(Vector3(0, cy, 0), Vector3(cos(a) * rr, cy + sin(a) * rr, 0), 0.25, 0.25, 3, white, false)
	for k in 32:
		var a2 := TAU * k / 32.0
		mb.add_sphere(Vector3(cos(a2) * (rr + 2.5), cy + sin(a2) * (rr + 2.5), 0), Vector3(2.6, 2.0, 4.0), 8, 5, Color(0.8, 0.88, 0.92))
	mb.add_cylinder(Vector3(0, cy, -4), Vector3(0, cy, 4), 3.0, 3.0, 10, white)
	mb.add_cylinder(Vector3(-30, 0, 35), Vector3(0, cy, 2), 1.6, 1.2, 6, white)
	mb.add_cylinder(Vector3(30, 0, 35), Vector3(0, cy, 2), 1.6, 1.2, 6, white)
	boxes.append([Vector3(0, cy, 0), Vector3(68, 68, 4)])


func _tower_bridge(mb: MeshBuilder, boxes: Array) -> void:
	var stone := Color(0.78, 0.74, 0.66)
	var blue := Color(0.38, 0.6, 0.8)
	var deck := Color(0.22, 0.22, 0.24)
	for tz in [-38.0, 38.0]:
		mb.add_box(Vector3(0, -6, tz), Vector3(26, 16, 30), stone)
		mb.add_box(Vector3(0, 30, tz), Vector3(18, 58, 18), stone)
		for cx in [-9.0, 9.0]:
			for cz in [-9.0, 9.0]:
				mb.add_cone(Vector3(cx, 58, tz + cz), Vector3(cx, 66, tz + cz), 2.0, 4, Color(0.3, 0.32, 0.36))
		mb.xf = Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0, tz))
		mb.add_cone(Vector3(0, 59, 0), Vector3(0, 70, 0), 9.0, 4, Color(0.3, 0.32, 0.36))
		mb.xf = Transform3D.IDENTITY
	# high walkways and the road deck
	for wy in [44.0, 49.0]:
		mb.add_box(Vector3(-4, wy, 0), Vector3(3, 3, 58), blue)
		mb.add_box(Vector3(4, wy, 0), Vector3(3, 3, 58), blue)
	mb.add_box(Vector3(0, 9, 0), Vector3(16, 2.5, 330), deck)
	# side-span chains down to the banks
	for sgn in [-1.0, 1.0]:
		for sx in [-8.0, 8.0]:
			var a := Vector3(sx, 40, 38.0 * sgn)
			var b := Vector3(sx, 12, 165.0 * sgn)
			for k in 8:
				var t0 := float(k) / 8.0
				var t1 := float(k + 1) / 8.0
				var p0 := a.lerp(b, t0) + Vector3(0, -sin(t0 * PI) * 8.0, 0)
				var p1 := a.lerp(b, t1) + Vector3(0, -sin(t1 * PI) * 8.0, 0)
				mb.add_cylinder(p0, p1, 0.9, 0.9, 4, blue, false)
	boxes.append([Vector3(0, 30, -38), Vector3(11, 36, 11)])
	boxes.append([Vector3(0, 30, 38), Vector3(11, 36, 11)])
	boxes.append([Vector3(0, 46, 0), Vector3(8, 4, 30)])


func _suspension(mb: MeshBuilder, boxes: Array, span: float, tower_h: float, deck_h: float, length: float, width: float, tower_col: Color, cable_col: Color, stone: bool) -> void:
	## A suspension bridge along local Z: two towers, the deck, main cables and hangers.
	var half_s := span * 0.5
	var half_l := length * 0.5
	var deck := Color(0.24, 0.24, 0.26)
	mb.add_box(Vector3(0, deck_h, 0), Vector3(width, 3.5, length), deck)
	mb.add_box(Vector3(0, deck_h + 2.2, 0), Vector3(width + 1.0, 1.0, length), tower_col.darkened(0.15))
	for tz in [-half_s, half_s]:
		if stone:
			# masonry towers with twin Gothic arches
			mb.add_box(Vector3(0, deck_h * 0.5 - 10.0, tz), Vector3(width + 18.0, deck_h + 20.0, 34.0), tower_col)
			for sx in [-1.0, 1.0]:
				mb.add_box(Vector3(sx * (width * 0.5 + 2.0), (deck_h + tower_h) * 0.5, tz), Vector3(12.0, tower_h - deck_h, 30.0), tower_col)
			mb.add_box(Vector3(0, tower_h - 9.0, tz), Vector3(width + 16.0, 18.0, 30.0), tower_col)
		else:
			for sx2 in [-1.0, 1.0]:
				mb.add_box(Vector3(sx2 * width * 0.5, tower_h * 0.5 - 20.0, tz), Vector3(9.0, tower_h + 40.0, 12.0), tower_col)
			for by in [deck_h + 30.0, tower_h * 0.62, tower_h * 0.86, tower_h - 4.0]:
				mb.add_box(Vector3(0, by, tz), Vector3(width, 6.0, 8.0), tower_col)
			mb.add_box(Vector3(0, -12.0, tz), Vector3(width + 22.0, 24.0, 40.0), Color(0.6, 0.58, 0.55))
		boxes.append([Vector3(0, tower_h * 0.5, tz), Vector3(width * 0.5 + 8.0, tower_h * 0.5, 16.0)])
	boxes.append([Vector3(0, deck_h, 0), Vector3(width * 0.5, 3.0, half_l)])
	for sx3 in [-1.0, 1.0]:
		var px: float = sx3 * width * 0.5
		var pts := []
		# main span: parabola from tower top down to just above the deck
		for k in 25:
			var t := float(k) / 24.0
			var zz := lerpf(-half_s, half_s, t)
			var yy := deck_h + 4.0 + (tower_h - deck_h - 6.0) * pow((zz / half_s), 2.0)
			pts.append(Vector3(px, yy, zz))
		for k2 in pts.size() - 1:
			mb.add_cylinder(pts[k2], pts[k2 + 1], 0.9, 0.9, 4, cable_col, false)
			if k2 % 2 == 0:
				mb.add_cylinder(pts[k2], Vector3(px, deck_h + 1.5, (pts[k2] as Vector3).z), 0.18, 0.18, 3, cable_col, false)
		# side spans down to the anchorages
		for sgn in [-1.0, 1.0]:
			var a := Vector3(px, tower_h - 2.0, half_s * sgn)
			var b := Vector3(px, deck_h + 2.0, half_l * sgn)
			for k3 in 8:
				var t0 := float(k3) / 8.0
				var t1 := float(k3 + 1) / 8.0
				mb.add_cylinder(a.lerp(b, t0) - Vector3(0, sin(t0 * PI) * 10.0, 0), a.lerp(b, t1) - Vector3(0, sin(t1 * PI) * 10.0, 0), 0.9, 0.9, 4, cable_col, false)
	for sgn2 in [-1.0, 1.0]:
		mb.add_box(Vector3(0, deck_h * 0.5, half_l * sgn2), Vector3(width + 10.0, deck_h + 6.0, 40.0), Color(0.6, 0.57, 0.52))


# ================================================================== Paris
func _eiffel(mb: MeshBuilder, boxes: Array) -> void:
	var iron := Color(0.45, 0.37, 0.29)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_cylinder(Vector3(62 * sx, 0, 62 * sz), Vector3(27 * sx, 57, 27 * sz), 9.0, 6.5, 4, iron)
			mb.add_cylinder(Vector3(24 * sx, 60, 24 * sz), Vector3(12 * sx, 115, 12 * sz), 6.0, 4.0, 4, iron)
	# arches between the legs and the platforms
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k in 8:
			var t0 := float(k) / 8.0
			var t1 := float(k + 1) / 8.0
			var p0 := b * Vector3(lerpf(-48, 48, t0), 22.0 + sin(t0 * PI) * 16.0, -48)
			var p1 := b * Vector3(lerpf(-48, 48, t1), 22.0 + sin(t1 * PI) * 16.0, -48)
			mb.add_cylinder(p0, p1, 1.4, 1.4, 4, iron, false)
	mb.add_box(Vector3(0, 58, 0), Vector3(72, 6, 72), iron)
	mb.add_box(Vector3(0, 116, 0), Vector3(42, 5, 42), iron)
	mb.xf = Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	mb.add_cylinder(Vector3(0, 118, 0), Vector3(0, 276, 0), 15.0, 4.8, 4, iron)
	mb.xf = Transform3D.IDENTITY
	mb.add_box(Vector3(0, 278, 0), Vector3(11, 6, 11), iron)
	mb.add_cylinder(Vector3(0, 281, 0), Vector3(0, 330, 0), 1.4, 0.4, 6, Color(0.7, 0.7, 0.7))
	boxes.append([Vector3(0, 60, 0), Vector3(62, 60, 62)])
	boxes.append([Vector3(0, 220, 0), Vector3(10, 110, 10)])


func _arc(mb: MeshBuilder, boxes: Array) -> void:
	var st := Color(0.86, 0.82, 0.72)
	for sx in [-1.0, 1.0]:
		mb.add_box(Vector3(sx * 15.0, 15.0, 0), Vector3(15, 30, 22), st)
	mb.add_box(Vector3(0, 40, 0), Vector3(45, 20, 22), st)
	mb.add_arch(Vector3(0, 22, 0), 15.0, 8.0, 22.0, 10, st)
	boxes.append([Vector3(0, 25, 0), Vector3(23, 25, 11)])


# ================================================================== North America
func _cn_tower(mb: MeshBuilder, boxes: Array) -> void:
	var conc := Color(0.8, 0.79, 0.76)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 335, 0), 17.0, 7.0, 6, conc)
	for k in 3:
		var a := TAU * k / 3.0
		mb.add_cylinder(Vector3(cos(a) * 26, 0, sin(a) * 26), Vector3(cos(a) * 4, 300, sin(a) * 4), 6.0, 1.5, 4, conc)
	mb.add_cylinder(Vector3(0, 335, 0), Vector3(0, 352, 0), 19.0, 25.0, 16, Color(0.3, 0.33, 0.38))
	mb.add_cylinder(Vector3(0, 352, 0), Vector3(0, 368, 0), 25.0, 17.0, 16, conc)
	mb.add_cylinder(Vector3(0, 368, 0), Vector3(0, 447, 0), 6.0, 4.5, 6, conc)
	mb.add_cylinder(Vector3(0, 447, 0), Vector3(0, 456, 0), 8.0, 8.0, 10, Color(0.3, 0.33, 0.38))
	mb.add_cylinder(Vector3(0, 456, 0), Vector3(0, 553, 0), 3.0, 0.6, 6, Color(0.88, 0.2, 0.15))
	boxes.append([Vector3(0, 230, 0), Vector3(16, 230, 16)])
	boxes.append([Vector3(0, 352, 0), Vector3(25, 16, 25)])


func _hollywood(root: Node3D) -> void:
	var lb := Label3D.new()
	lb.text = "HOLLYWOOD"
	lb.font_size = 256
	lb.pixel_size = 0.14
	lb.modulate = Color(0.97, 0.97, 0.95)
	lb.outline_size = 0
	lb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lb.position = Vector3(0, 20, 0)
	lb.rotation = Vector3(-0.15, PI, 0)      # read from the city below
	lb.double_sided = true
	lb.visibility_range_end = 30000.0
	root.add_child(lb)


func _capitol(mb: MeshBuilder, boxes: Array) -> void:
	var w := Color(0.93, 0.92, 0.89)
	mb.add_box(Vector3(0, 16, 0), Vector3(230, 32, 72), w)
	mb.add_box(Vector3(0, 34, 0), Vector3(222, 4, 64), Color(0.82, 0.82, 0.8))
	mb.add_box(Vector3(0, 20, 42), Vector3(60, 36, 14), w)
	for k in 12:
		mb.add_cylinder(Vector3(-27 + k * 4.9, 0, 50), Vector3(-27 + k * 4.9, 32, 50), 1.2, 1.1, 8, w)
	mb.add_cylinder(Vector3(0, 32, 0), Vector3(0, 62, 0), 30.0, 28.0, 24, w)
	for k2 in 24:
		var a := TAU * k2 / 24.0
		mb.add_cylinder(Vector3(cos(a) * 31.5, 36, sin(a) * 31.5), Vector3(cos(a) * 31.5, 52, sin(a) * 31.5), 0.9, 0.8, 6, w)
	mb.add_sphere(Vector3(0, 62, 0), Vector3(27, 26, 27), 20, 8, w)
	mb.add_cylinder(Vector3(0, 86, 0), Vector3(0, 95, 0), 4.5, 3.5, 10, w)
	mb.add_cylinder(Vector3(0, 95, 0), Vector3(0, 101, 0), 1.0, 0.6, 6, Color(0.4, 0.38, 0.32))
	boxes.append([Vector3(0, 18, 0), Vector3(115, 18, 36)])
	boxes.append([Vector3(0, 60, 0), Vector3(30, 30, 30)])


func _obelisk(mb: MeshBuilder, boxes: Array) -> void:
	var w := Color(0.93, 0.92, 0.88)
	mb.xf = Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 152, 0), 12.0, 7.4, 4, w)
	mb.add_cone(Vector3(0, 152, 0), Vector3(0, 169, 0), 7.4, 4, w)
	mb.xf = Transform3D.IDENTITY
	boxes.append([Vector3(0, 84, 0), Vector3(9, 84, 9)])


# ================================================================== Rome
func _colosseum(mb: MeshBuilder, boxes: Array) -> void:
	var tr := Color(0.82, 0.73, 0.58)
	var band := Color(0.58, 0.5, 0.4)
	var n := 48
	for k in n:
		var a := TAU * (k + 0.5) / n
		var c := Vector3(cos(a) * 78.0, 0, sin(a) * 62.0)
		var tangent := Vector3(-sin(a) * 78.0, 0, cos(a) * 62.0).normalized()
		var b := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP))
		var seg := 2.0 * PI * 70.0 / n + 1.5
		var h := 48.0 if k % n < 32 else 36.0
		mb.add_box_xf(Transform3D(b, c + Vector3(0, h * 0.5, 0)), Vector3(seg, h, 28.0), tr)
		for by in [12.0, 24.0, 36.0]:
			if by < h:
				mb.add_box_xf(Transform3D(b, c + Vector3(0, by, 0)), Vector3(seg + 0.2, 1.6, 28.6), band)
	mb.add_box(Vector3(0, 1.0, 0), Vector3(100, 2, 70), Color(0.78, 0.68, 0.5))
	boxes.append([Vector3(0, 24, 0), Vector3(94, 24, 78)])


func _dome_church(mb: MeshBuilder, boxes: Array) -> void:
	var st := Color(0.86, 0.81, 0.7)
	var lead := Color(0.55, 0.6, 0.63)
	mb.add_box(Vector3(0, 22, 70), Vector3(60, 44, 150), st)
	mb.add_box(Vector3(0, 25, 140), Vector3(115, 50, 12), st)
	mb.add_box(Vector3(0, 22, -20), Vector3(140, 44, 60), st)
	mb.add_cylinder(Vector3(0, 44, -20), Vector3(0, 78, -20), 25.0, 24.0, 20, st)
	mb.add_sphere(Vector3(0, 78, -20), Vector3(22, 36, 22), 20, 8, lead)
	mb.add_cylinder(Vector3(0, 112, -20), Vector3(0, 128, -20), 4.5, 3.5, 10, st)
	mb.add_cone(Vector3(0, 128, -20), Vector3(0, 136, -20), 3.0, 8, lead)
	boxes.append([Vector3(0, 25, 50), Vector3(60, 25, 95)])
	boxes.append([Vector3(0, 80, -20), Vector3(25, 56, 25)])


# ================================================================== Amsterdam, Reykjavik
func _windmills(mb: MeshBuilder, boxes: Array) -> void:
	for k in 5:
		var o := Vector3((k - 2) * 230.0, 0, sin(k * 1.7) * 120.0)
		var body := Color(0.25, 0.32, 0.26) if k % 2 == 0 else Color(0.45, 0.33, 0.24)
		mb.add_cylinder(o, o + Vector3(0, 22, 0), 7.5, 4.5, 8, body)
		mb.add_cone(o + Vector3(0, 22, 0), o + Vector3(0, 28, 0), 5.2, 8, Color(0.2, 0.2, 0.22))
		var hub := o + Vector3(0, 23, -5.5)
		for s in 4:
			var a := s * PI * 0.5 + PI * 0.25 + k * 0.4
			var tip := hub + Vector3(cos(a), sin(a), 0) * 13.0
			mb.add_cylinder(hub, tip, 0.35, 0.3, 4, Color(0.35, 0.25, 0.18), false)
			mb.add_box_xf(Transform3D(Basis(Vector3.FORWARD, a), hub.lerp(tip, 0.6) + Vector3(0, 0, -0.4)), Vector3(8.0, 2.2, 0.3), Color(0.92, 0.9, 0.84))
		boxes.append([o + Vector3(0, 14, 0), Vector3(8, 14, 8)])


func _church_tower(mb: MeshBuilder, boxes: Array) -> void:
	var c := Color(0.84, 0.84, 0.82)
	mb.add_box(Vector3(0, 34, 0), Vector3(10, 68, 14), c)
	mb.add_cone(Vector3(0, 68, 0), Vector3(0, 76, 0), 4.0, 4, c)
	for k in 6:
		var h := 52.0 - k * 7.5
		for sx in [-1.0, 1.0]:
			mb.add_box(Vector3(sx * (7.0 + k * 3.2), h * 0.5, 2), Vector3(3.2, h, 10), c)
	mb.add_box(Vector3(0, 12, 30), Vector3(26, 24, 46), c)
	mb.add_box(Vector3(0, 25, 30), Vector3(26, 2, 46), Color(0.3, 0.32, 0.34))
	boxes.append([Vector3(0, 36, 6), Vector3(26, 36, 30)])


# ================================================================== second-wave landmarks
func _space_needle(mb: MeshBuilder, boxes: Array) -> void:
	## Seattle: three pairs of curved legs pinched at the waist, the flying-saucer top house, spire.
	var white := Color(0.9, 0.9, 0.88)
	for k in 3:
		var a := TAU * k / 3.0
		var foot := Vector3(cos(a), 0, sin(a)) * 18.0
		var waist := Vector3(cos(a), 0, sin(a)) * 4.0 + Vector3(0, 115, 0)
		var top := Vector3(cos(a), 0, sin(a)) * 9.0 + Vector3(0, 158, 0)
		mb.add_cylinder(foot, waist, 1.6, 1.2, 6, white)
		mb.add_cylinder(waist, top, 1.2, 1.1, 6, white)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 160, 0), 2.6, 2.6, 8, Color(0.75, 0.75, 0.73))
	mb.add_cylinder(Vector3(0, 155, 0), Vector3(0, 162, 0), 8.0, 21.0, 24, Color(0.85, 0.55, 0.2))
	mb.add_cylinder(Vector3(0, 162, 0), Vector3(0, 168, 0), 21.0, 16.0, 24, Color(0.3, 0.38, 0.45))
	mb.add_cylinder(Vector3(0, 168, 0), Vector3(0, 172, 0), 16.0, 6.0, 20, white)
	mb.add_cylinder(Vector3(0, 172, 0), Vector3(0, 184, 0), 1.2, 0.3, 6, white)
	boxes.append([Vector3(0, 80, 0), Vector3(12, 80, 12)])
	boxes.append([Vector3(0, 165, 0), Vector3(21, 10, 21)])


func _tv_tower(mb: MeshBuilder, boxes: Array) -> void:
	## A concrete shaft with a sphere and a red-and-white antenna (Berlin, Las Vegas).
	var conc := Color(0.82, 0.81, 0.78)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 200, 0), 9.0, 5.0, 12, conc)
	mb.add_sphere(Vector3(0, 212, 0), Vector3(16, 16, 16), 18, 12, Color(0.55, 0.6, 0.66))
	mb.add_cylinder(Vector3(0, 226, 0), Vector3(0, 300, 0), 3.0, 2.0, 8, Color(0.92, 0.92, 0.9))
	for k in 4:
		mb.add_cylinder(Vector3(0, 300 + k * 16.0, 0), Vector3(0, 308 + k * 16.0, 0), 1.9 - k * 0.3, 1.8 - k * 0.3, 6, Color(0.85, 0.15, 0.12))
		mb.add_cylinder(Vector3(0, 308 + k * 16.0, 0), Vector3(0, 316 + k * 16.0, 0), 1.8 - k * 0.3, 1.6 - k * 0.3, 6, Color(0.95, 0.95, 0.95))
	boxes.append([Vector3(0, 110, 0), Vector3(9, 110, 9)])
	boxes.append([Vector3(0, 212, 0), Vector3(16, 16, 16)])
	boxes.append([Vector3(0, 300, 0), Vector3(3, 70, 3)])


func _reunion(mb: MeshBuilder, boxes: Array) -> void:
	## Dallas: a tall shaft carrying a lattice ball that lights up at night.
	var conc := Color(0.78, 0.77, 0.74)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 150, 0), 7.0, 6.0, 10, conc)
	mb.add_sphere(Vector3(0, 158, 0), Vector3(18, 16, 18), 16, 10, Color(0.85, 0.85, 0.8))
	boxes.append([Vector3(0, 85, 0), Vector3(18, 85, 18)])


func _brandenburg(mb: MeshBuilder, boxes: Array) -> void:
	## Berlin: twelve Doric columns, the attic and the quadriga on top.
	var sand := Color(0.82, 0.76, 0.62)
	for k in 6:
		var x := -26.0 + k * 10.4
		for zz in [-4.5, 4.5]:
			mb.add_cylinder(Vector3(x, 0, zz), Vector3(x, 15, zz), 0.9, 0.85, 10, sand)
	mb.add_box(Vector3(0, 17.5, 0), Vector3(62, 5, 12), sand)
	mb.add_box(Vector3(0, 21.5, 0), Vector3(40, 3, 10), sand)
	mb.add_box(Vector3(0, 24.0, 0), Vector3(6, 3, 4), Color(0.3, 0.42, 0.34))
	for sx in [-1.0, 1.0]:
		mb.add_box(Vector3(sx * 40.0, 7.0, 0), Vector3(14, 14, 10), sand)
	boxes.append([Vector3(0, 12, 0), Vector3(48, 13, 7)])


func _sagrada(mb: MeshBuilder, boxes: Array) -> void:
	## Barcelona: the forest of tapering spires over the nave.
	var stone := Color(0.72, 0.66, 0.55)
	mb.add_box(Vector3(0, 22, 0), Vector3(60, 44, 90), stone)
	var spires := [[Vector3(-14, 0, -45), 98.0], [Vector3(-5, 0, -45), 107.0], [Vector3(5, 0, -45), 107.0], [Vector3(14, 0, -45), 98.0],
		[Vector3(-14, 0, 45), 100.0], [Vector3(-5, 0, 45), 112.0], [Vector3(5, 0, 45), 112.0], [Vector3(14, 0, 45), 100.0],
		[Vector3(0, 0, 0), 172.0], [Vector3(-16, 0, -5), 135.0], [Vector3(16, 0, -5), 135.0], [Vector3(0, 0, 18), 138.0]]
	for sp in spires:
		var b: Vector3 = sp[0]
		var h: float = sp[1]
		mb.add_cylinder(b, b + Vector3(0, h * 0.8, 0), 4.6 if h > 150.0 else 3.2, 2.2, 10, stone)
		mb.add_cone(b + Vector3(0, h * 0.8, 0), b + Vector3(0, h, 0), 2.4, 8, stone.lightened(0.08))
		mb.add_sphere(b + Vector3(0, h, 0), Vector3(1.4, 1.4, 1.4), 6, 4, Color(0.9, 0.75, 0.3))
	boxes.append([Vector3(0, 60, 0), Vector3(32, 60, 48)])
	boxes.append([Vector3(0, 140, 0), Vector3(6, 32, 6)])


func _atomium(mb: MeshBuilder, boxes: Array) -> void:
	## Brussels: nine steel spheres on the corners and centre of a giant iron crystal.
	var steel := Color(0.85, 0.87, 0.9)
	var c := Vector3(0, 52, 0)
	var corners := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(c + Basis.from_euler(Vector3(0.62, 0, 0.78)) * Vector3(sx, sy, sz) * 24.0)
	for p in corners:
		mb.add_cylinder(c, p, 1.6, 1.6, 8, steel)
		mb.add_sphere(p, Vector3(9, 9, 9), 14, 10, steel)
	mb.add_sphere(c, Vector3(9, 9, 9), 14, 10, steel)
	mb.add_cylinder(Vector3(0, 0, 0), c, 2.0, 2.0, 8, steel)
	boxes.append([c, Vector3(34, 46, 34)])


func _castle(mb: MeshBuilder, boxes: Array) -> void:
	## A castle on its rock (Edinburgh), or the fairytale castle at the theme parks.
	var rock := Color(0.38, 0.36, 0.33)
	var wall := Color(0.62, 0.6, 0.56)
	mb.add_rounded_box(Vector3(0, 20, 0), Vector3(180, 40, 110), rock, 0.5, 10, 6)
	mb.add_box(Vector3(0, 52, 0), Vector3(120, 24, 60), wall)
	for k in 4:
		var p := Vector3((k % 2) * 110.0 - 55.0, 40, (k / 2) * 52.0 - 26.0)
		mb.add_cylinder(p, p + Vector3(0, 46, 0), 7.0, 7.0, 10, wall)
		mb.add_cone(p + Vector3(0, 46, 0), p + Vector3(0, 62, 0), 8.0, 10, Color(0.25, 0.32, 0.5))
	mb.add_cylinder(Vector3(0, 60, 0), Vector3(0, 98, 0), 9.0, 8.0, 12, wall)
	mb.add_cone(Vector3(0, 98, 0), Vector3(0, 122, 0), 10.0, 12, Color(0.25, 0.32, 0.5))
	boxes.append([Vector3(0, 45, 0), Vector3(90, 45, 55)])
	boxes.append([Vector3(0, 90, 0), Vector3(10, 32, 10)])


func _twin_church(mb: MeshBuilder, boxes: Array) -> void:
	## Munich's Frauenkirche: a brick hall with twin towers under green onion domes.
	var brick := Color(0.6, 0.36, 0.28)
	mb.add_box(Vector3(0, 19, 25), Vector3(40, 38, 90), brick)
	mb.add_box(Vector3(0, 40, 25), Vector3(40, 4, 90), Color(0.45, 0.25, 0.2))
	for sx in [-1.0, 1.0]:
		var b := Vector3(sx * 11.0, 0, -28)
		mb.add_box(b + Vector3(0, 50, 0), Vector3(16, 100, 16), brick)
		mb.add_sphere(b + Vector3(0, 106, 0), Vector3(8.5, 9, 8.5), 12, 8, Color(0.3, 0.55, 0.42))
		mb.add_cone(b + Vector3(0, 112, 0), b + Vector3(0, 118, 0), 2.0, 6, Color(0.85, 0.7, 0.3))
	boxes.append([Vector3(0, 55, -28), Vector3(20, 60, 9)])
	boxes.append([Vector3(0, 20, 25), Vector3(20, 20, 45)])


# ================================================================== Asia and the Middle East
func _burj(mb: MeshBuilder, boxes: Array) -> void:
	## The Burj Khalifa: a Y-shaped stepped tower 828 m tall with a spire.
	var glass := Color(0.72, 0.78, 0.84)
	var h := 0.0
	var steps := [[0.0, 160.0, 34.0], [160.0, 330.0, 27.0], [330.0, 470.0, 20.0], [470.0, 580.0, 14.0], [580.0, 640.0, 9.0]]
	for st in steps:
		for k in 3:
			var a := TAU * k / 3.0
			var c := Vector3(cos(a), 0, sin(a)) * float(st[2]) * 0.55
			mb.add_cylinder(c + Vector3(0, float(st[0]), 0), c + Vector3(0, float(st[1]), 0), float(st[2]) * 0.55, float(st[2]) * 0.5, 8, glass)
		h = float(st[1])
	mb.add_cylinder(Vector3(0, h, 0), Vector3(0, 828, 0), 5.0, 0.6, 8, Color(0.85, 0.87, 0.9))
	boxes.append([Vector3(0, 240, 0), Vector3(36, 240, 36)])
	boxes.append([Vector3(0, 700, 0), Vector3(10, 130, 10)])


func _petronas(mb: MeshBuilder, boxes: Array) -> void:
	## Twin steel towers joined by a skybridge.
	var steel := Color(0.78, 0.8, 0.83)
	for sx in [-1.0, 1.0]:
		var b := Vector3(sx * 42.0, 0, 0)
		var tiers := [[0.0, 240.0, 24.0], [240.0, 330.0, 20.0], [330.0, 375.0, 15.0], [375.0, 400.0, 10.0]]
		for t in tiers:
			mb.add_cylinder(b + Vector3(0, float(t[0]), 0), b + Vector3(0, float(t[1]), 0), float(t[2]), float(t[2]) * 0.96, 16, steel)
		mb.add_cylinder(b + Vector3(0, 400, 0), b + Vector3(0, 452, 0), 3.0, 0.4, 8, steel)
		boxes.append([b + Vector3(0, 200, 0), Vector3(24, 200, 24)])
	mb.add_box(Vector3(0, 172, 0), Vector3(62, 6, 6), Color(0.5, 0.55, 0.6))


func _mbs(mb: MeshBuilder, boxes: Array) -> void:
	## Three hotel towers carrying a ship-shaped park across the top.
	var c := Color(0.86, 0.86, 0.84)
	for k in 3:
		var x := (k - 1) * 70.0
		mb.add_box(Vector3(x - 8, 97, 0), Vector3(14, 194, 38), c)
		mb.add_box(Vector3(x + 8, 97, 0), Vector3(14, 194, 38), c)
		boxes.append([Vector3(x, 97, 0), Vector3(16, 97, 19)])
	mb.add_box(Vector3(10, 199, 0), Vector3(340, 10, 40), Color(0.3, 0.45, 0.32))


func _taipei101(mb: MeshBuilder, boxes: Array) -> void:
	## Eight flared stacked sections like a bamboo stalk, 508 m with the spire.
	var g := Color(0.35, 0.55, 0.5)
	mb.add_box(Vector3(0, 45, 0), Vector3(60, 90, 60), g)
	for k in 8:
		var y0 := 90.0 + k * 40.0
		mb.add_cylinder(Vector3(0, y0, 0), Vector3(0, y0 + 40.0, 0), 22.0, 30.0, 4, g)
	mb.add_box(Vector3(0, 430, 0), Vector3(30, 30, 30), g)
	mb.add_cylinder(Vector3(0, 445, 0), Vector3(0, 508, 0), 3.0, 0.5, 6, Color(0.85, 0.85, 0.85))
	boxes.append([Vector3(0, 230, 0), Vector3(32, 230, 32)])


func _pyramids(mb: MeshBuilder, boxes: Array) -> void:
	var sand := Color(0.85, 0.74, 0.52)
	for p in [[Vector3(0, 0, 0), 230.0, 139.0], [Vector3(-350, 0, 300), 215.0, 136.0], [Vector3(-600, 0, 560), 105.0, 62.0]]:
		var b: Vector3 = p[0]
		mb.add_cone(b, b + Vector3(0, float(p[2]), 0), float(p[1]) * 0.7, 4, sand)
		boxes.append([b + Vector3(0, float(p[2]) * 0.4, 0), Vector3(float(p[1]) * 0.45, float(p[2]) * 0.4, float(p[1]) * 0.45)])


func _parthenon(mb: MeshBuilder, boxes: Array) -> void:
	## The Acropolis rock with the Parthenon on top.
	var rock := Color(0.6, 0.55, 0.47)
	var marble := Color(0.9, 0.87, 0.8)
	mb.add_rounded_box(Vector3(0, 35, 0), Vector3(300, 70, 150), rock, 0.5, 10, 6)
	for i in 8:
		for zz in [-14.0, 14.0]:
			mb.add_cylinder(Vector3(-31.0 + i * 8.8, 70, zz), Vector3(-31.0 + i * 8.8, 80, zz), 0.9, 0.85, 8, marble)
	mb.add_box(Vector3(0, 82, 0), Vector3(70, 4, 32), marble)
	mb.add_box(Vector3(0, 69, 0), Vector3(72, 2, 34), marble)
	boxes.append([Vector3(0, 42, 0), Vector3(150, 42, 75)])


func _pagoda(mb: MeshBuilder, boxes: Array) -> void:
	## A five-tiered pagoda or temple tower with upturned roofs.
	var wall := Color(0.75, 0.2, 0.15)
	var roof := Color(0.2, 0.22, 0.25)
	mb.add_box(Vector3(0, 3, 0), Vector3(40, 6, 40), Color(0.75, 0.72, 0.65))
	for k in 5:
		var y := 6.0 + k * 11.0
		var w := 22.0 - k * 3.0
		mb.add_box(Vector3(0, y + 4.0, 0), Vector3(w, 8.0, w), wall)
		mb.add_cone(Vector3(0, y + 8.0, 0), Vector3(0, y + 12.0, 0), w * 0.95, 4, roof)
	mb.add_cylinder(Vector3(0, 61, 0), Vector3(0, 74, 0), 0.6, 0.2, 6, Color(0.85, 0.7, 0.3))
	boxes.append([Vector3(0, 35, 0), Vector3(20, 35, 20)])


func _onion_domes(mb: MeshBuilder, boxes: Array) -> void:
	## St Basil's: a cluster of towers with bright striped onion domes.
	var cols := [Color(0.85, 0.2, 0.2), Color(0.2, 0.6, 0.35), Color(0.95, 0.75, 0.2), Color(0.2, 0.4, 0.8), Color(0.9, 0.9, 0.85)]
	mb.add_box(Vector3(0, 10, 0), Vector3(60, 20, 60), Color(0.65, 0.25, 0.2))
	var spots := [[Vector3(0, 0, 0), 47.0], [Vector3(-20, 0, -20), 32.0], [Vector3(20, 0, -20), 32.0], [Vector3(-20, 0, 20), 32.0], [Vector3(20, 0, 20), 32.0]]
	for i in spots.size():
		var b: Vector3 = spots[i][0]
		var h: float = spots[i][1]
		mb.add_cylinder(b, b + Vector3(0, h, 0), 6.0, 5.0, 10, Color(0.7, 0.28, 0.22))
		mb.add_sphere(b + Vector3(0, h + 5.0, 0), Vector3(7, 8, 7), 12, 8, cols[i % cols.size()])
		mb.add_cone(b + Vector3(0, h + 11.0, 0), b + Vector3(0, h + 17.0, 0), 2.5, 8, Color(0.9, 0.75, 0.3))
	boxes.append([Vector3(0, 30, 0), Vector3(30, 30, 30)])
