class_name Landmarks
extends Node3D
## Famous buildings and skylines of the real-world region (RealWorld.LANDMARKS): the Statue of
## Liberty, the Empire State Building, Big Ben, the Eiffel Tower, the Golden Gate Bridge and the
## rest. Each is a procedural model streamed in when the camera comes within range, merged into
## one mesh (plus a short-range mesh for fine detail) on the landmark material: its vertex alpha
## picks stonework, metal, curtain walls, ribbon or punched windows and lamps, so towers show
## window grids by day and lit offices after dark while monuments are floodlit. Skylines are
## clusters of varied tower archetypes (setbacks, crowns, spires, slanted and round tops) on
## the city building shader. Every model also reports simple collision boxes so aircraft can
## hit them.

const K := preload("res://src/world/models/model_kit.gd")
const BUILD_RANGE := 48000.0
const DROP_RANGE := 62000.0
const FINE_RANGE := 7000.0

var view: WorldView
var built := {}            # id -> {root, boxes}
var _timer := 0.0
var _mat: ShaderMaterial
var _glow := -1.0
var _fine: MeshBuilder     # small detail of the landmark being built (shorter draw distance)
var _id := ""              # id of the landmark being built (per-landmark variants)

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
	_mat = K.landmark_material()


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
	# window lights and floodlights come on after dark
	var g := clampf(view.night * 1.4 - 0.2, 0.0, 1.0)
	if absf(g - _glow) > 0.01:
		_glow = g
		_mat.set_shader_parameter("night", g)


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
	var mb := MeshBuilder.new()
	_fine = MeshBuilder.new()
	_id = String(lm.id)
	var boxes := []         # local collision boxes [center, half]
	if _glow < 0.0:
		_glow = clampf(view.night * 1.4 - 0.2, 0.0, 1.0)
		_mat.set_shader_parameter("night", _glow)
	if SKYLINES.has(kind):
		_skyline(root, lm, SKYLINES[kind], yaw, boxes)
	else:
		match kind:
			"liberty":
				_liberty(mb, boxes)
			"empire":
				_empire(mb, boxes)
			"one_wtc":
				_one_wtc(mb, boxes)
			"willis":
				_willis(mb, boxes)
			"shard":
				_shard(mb, boxes)
			"cn_tower":
				_cn_tower(mb, boxes)
			"bridge_brooklyn":
				_suspension(mb, boxes, 480.0, 84.0, 38.0, 940.0, 34.0, Color(0.66, 0.58, 0.48), Color(0.3, 0.3, 0.32), true)
			"bridge_golden":
				_suspension(mb, boxes, 1280.0, 227.0, 67.0, 2300.0, 27.0, Color(0.78, 0.24, 0.1), Color(0.75, 0.22, 0.1), false)
			"bridge_tower":
				_tower_bridge(mb, boxes)
			"big_ben":
				_big_ben(mb, boxes)
			"london_eye":
				_london_eye(mb, boxes)
			"eiffel":
				_eiffel(mb, boxes)
			"arc":
				_arc(mb, boxes)
			"hollywood":
				_hollywood(root)
			"capitol":
				_capitol(mb, boxes)
			"obelisk":
				_obelisk(mb, boxes)
			"colosseum":
				_colosseum(mb, boxes)
			"dome_church":
				_dome_church(mb, boxes)
			"windmills":
				_windmills(mb, boxes)
			"church_tower":
				_church_tower(mb, boxes)
			"space_needle":
				_space_needle(mb, boxes)
			"tv_tower":
				_tv_tower(mb, boxes)
			"reunion":
				_reunion(mb, boxes)
			"brandenburg":
				_brandenburg(mb, boxes)
			"sagrada":
				_sagrada(mb, boxes)
			"atomium":
				_atomium(mb, boxes)
			"castle":
				_castle(mb, boxes)
			"twin_towers_church":
				_twin_church(mb, boxes)
			"burj":
				_burj(mb, boxes)
			"petronas":
				_petronas(mb, boxes)
			"mbs":
				_mbs(mb, boxes)
			"taipei101":
				_taipei101(mb, boxes)
			"pyramids":
				_pyramids(mb, boxes)
			"parthenon":
				_parthenon(mb, boxes)
			"pagoda":
				_pagoda(mb, boxes)
			"onion_domes":
				_onion_domes(mb, boxes)
	_add_mesh(root, mb, 42000.0, true)
	_add_mesh(root, _fine, FINE_RANGE, false)
	_fine = null
	var wb := []
	var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
	for bx in boxes:
		var c: Vector3 = basis * (bx[0] as Vector3)
		var hh: Vector3 = bx[1]
		# axis-aligned bound of the rotated box
		var ext := (basis * Vector3(hh.x, 0, 0)).abs() + (basis * Vector3(0, 0, hh.z)).abs()
		wb.append({"c": Vector3(x + c.x, ground + c.y, z + c.z), "h": Vector3(ext.x, hh.y, ext.z), "name": String(lm.name)})
	built[String(lm.id)] = {"root": root, "boxes": wb}


func _add_mesh(root: Node3D, mb: MeshBuilder, range_end: float, shadow: bool) -> void:
	if mb == null or mb.vcount() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _mat
	mi.visibility_range_end = range_end
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _c(col: Color, surface: float) -> Color:
	return Color(col.r, col.g, col.b, surface)


func _aviation_light(p: Vector3, r: float = 0.9) -> void:
	_fine.add_sphere(p, Vector3.ONE * r, 6, 4, _c(Color(1.0, 0.12, 0.08), K.LAMP))


# ================================================================== skylines
func _skyline(root: Node3D, lm: Dictionary, p: Array, yaw: float, boxes: Array) -> void:
	## A cluster of downtown towers on the city building shader, kept off the water. Each tower
	## is one of the ModelKit archetypes (setbacks, crown, pyramid, slant, round, octagon, twin
	## slab, taper, deco spire, rounded slab), the tallest favouring crowns and spires.
	var r := RandomNumberGenerator.new()
	r.seed = int(p[6]) * 7919
	var w: float = p[0]
	var d: float = p[1]
	var n: int = p[2]
	var hmax: float = p[4]
	var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
	var bufs := {}           # "archetype|glass" -> PackedFloat32Array of instances
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
		var h := lerpf(float(p[3]), hmax, pow(r.randf(), 1.6) * 0.55 + core * 0.45)
		var gh := Geo.ground_height(wx, wz) - g0
		placed.append({"x": lp.x, "z": lp.z, "w": tw})
		var is_glass := r.randf() < float(p[5])
		var col: Color = U.pick(r, [Color(0.42, 0.52, 0.62), Color(0.35, 0.45, 0.52), Color(0.55, 0.6, 0.66), Color(0.3, 0.38, 0.48), Color(0.6, 0.62, 0.62), Color(0.48, 0.56, 0.5)]) if is_glass \
			else U.pick(r, [Color(0.72, 0.68, 0.6), Color(0.62, 0.58, 0.54), Color(0.78, 0.74, 0.68), Color(0.55, 0.45, 0.38), Color(0.66, 0.66, 0.64), Color(0.5, 0.52, 0.55)])
		var td := tw * r.randf_range(0.8, 1.25)
		var arch := _pick_archetype(r, h / hmax)
		if arch == 4 or arch == 2 or arch == 5:
			td = tw          # round and pyramid tops want a square footprint
		var rot := float(r.randi() % 4) * PI * 0.5
		var key := "%d|%d" % [arch, 1 if is_glass else 0]
		var buf: PackedFloat32Array = bufs.get(key, PackedFloat32Array())
		TerrainManager._push_instance(buf, Vector3(lp.x, gh - 2.0, lp.z), rot, Vector3(tw, h + 2.0, td), col, r.randf())
		bufs[key] = buf
		boxes.append([Vector3(lp.x, gh + h * 0.5, lp.z), Vector3(maxf(tw, td) * 0.5, h * 0.5, maxf(tw, td) * 0.5)])
	for key2 in bufs.keys():
		var buf2: PackedFloat32Array = bufs[key2]
		if buf2.is_empty():
			continue
		var parts := String(key2).split("|")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = K.archetype_mesh(int(parts[0]), parts[1] == "1")
		mm.instance_count = buf2.size() / 16
		mm.buffer = buf2
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = view.terrain.building_material
		mmi.visibility_range_end = 45000.0
		root.add_child(mmi)


static func _pick_archetype(r: RandomNumberGenerator, t: float) -> int:
	var tall: Array[int] = [1, 2, 3, 5, 8, 4, 7, 0]
	var mid: Array[int] = [0, 1, 3, 4, 5, 6, 9, 7, 0]
	var low: Array[int] = [0, 6, 9, 4, 0, 6, 1]
	if t > 0.72:
		return tall[r.randi() % tall.size()]
	if t > 0.45:
		return mid[r.randi() % mid.size()]
	return low[r.randi() % low.size()]


# ================================================================== New York
func _liberty(mb: MeshBuilder, boxes: Array) -> void:
	## Liberty Island: the star fort, the granite pedestal and the copper statue (93 m to the torch).
	var grass := _c(Color(0.33, 0.45, 0.25), K.STONE)
	var paving := _c(Color(0.6, 0.58, 0.54), K.STONE)
	var stone := _c(Color(0.66, 0.63, 0.57), K.STONE)
	var granite := _c(Color(0.78, 0.74, 0.66), K.STONE)
	var copper := _c(Color(0.42, 0.68, 0.58), K.STONE)
	var gold := _c(Color(1.0, 0.8, 0.35), K.LAMP)
	var dark := _c(Color(0.1, 0.1, 0.1), K.DARK_GLASS)
	# the island stands well clear of the harbour swell; everything else sits on its top
	mb.add_cylinder(Vector3(0, -24, 0), Vector3(0, 6.0, 0), 158.0, 136.0, 40, grass)
	mb.add_cylinder(Vector3(0, 6.0, 0), Vector3(0, 6.2, 0), 72.0, 72.0, 32, paving)
	mb.xf = Transform3D(Basis(), Vector3(0, 3.5, 0))
	# Fort Wood: an eleven-pointed star of granite walls
	K.prism(mb, K.star(11, 62.0, 45.0, PI * 0.5), 2.5, 9.0, stone)
	# pedestal: stepped base, shaft with a loggia on each face, cornice and the balcony
	K.prism(mb, K.rect(21.0, 21.0), 9.0, 13.0, granite)
	K.prism(mb, K.rect(18.0, 18.0), 13.0, 27.0, granite, 0.9)
	K.prism(mb, K.rect(14.5, 14.5), 27.0, 41.0, granite)
	K.prism(mb, K.rect(15.6, 15.6), 41.0, 43.0, granite)
	K.prism(mb, K.rect(13.4, 13.4), 43.0, 46.0, granite)
	K.prism(mb, K.rect(10.5, 10.5), 46.0, 47.0, granite)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k in 3:
			mb.add_box_xf(Transform3D(b, b * Vector3((k - 1) * 5.6, 35.5, 14.5)), Vector3(2.2, 6.5, 0.4), dark)
		for k2 in 4:
			mb.add_box_xf(Transform3D(b, b * Vector3(-8.4 + k2 * 5.6, 34.0, 14.7)), Vector3(1.1, 13.0, 0.5), granite)
		mb.add_box_xf(Transform3D(b, b * Vector3(0, 21.0, 16.4)), Vector3(4.0, 3.0, 0.4), dark)
	var P := 47.0
	# robe: lofted rings with folds, slightly forward-leaning stance
	var rings := []
	var prof := [[0.0, 5.4], [2.5, 5.1], [8.0, 4.6], [14.0, 4.2], [19.0, 3.9], [23.0, 3.7], [25.5, 3.4], [27.2, 2.2]]
	for pr in prof:
		var y: float = P + float(pr[0])
		var rr: float = pr[1]
		var ring := PackedVector3Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			var fold := 1.0 + 0.07 * sin(a * 7.0 + y * 0.35)
			ring.append(Vector3(cos(a) * rr * fold * 1.12, y, sin(a) * rr * fold * 0.84 - 0.3))
		rings.append(ring)
	mb.add_loft(rings, copper, true, true)
	# neck, head and the crown with seven rays
	mb.add_cylinder(Vector3(0, P + 27.0, -0.4), Vector3(0, P + 29.0, -0.5), 1.4, 1.2, 10, copper)
	mb.add_sphere(Vector3(0, P + 30.7, -0.6), Vector3(2.2, 2.7, 2.4), 12, 8, copper)
	mb.add_cylinder(Vector3(0, P + 31.9, -0.6), Vector3(0, P + 33.0, -0.6), 2.5, 2.2, 14, copper)
	for k3 in 7:
		var a3 := deg_to_rad(-78.0 + k3 * 26.0)
		var dirv := Vector3(sin(a3), 0.42, -cos(a3)).normalized()
		var root_p := Vector3(0, P + 32.6, -0.6) + Vector3(sin(a3), 0, -cos(a3)) * 2.2
		mb.add_cone(root_p, root_p + dirv * 4.0, 0.45, 4, copper)
	# raised right arm, torch and the gilded flame (lit at night)
	mb.add_sphere(Vector3(3.0, P + 25.6, -0.3), Vector3(1.6, 1.6, 1.6), 8, 6, copper)
	mb.add_cylinder(Vector3(3.1, P + 25.8, -0.3), Vector3(4.2, P + 37.8, -0.9), 1.3, 0.95, 8, copper)
	mb.add_sphere(Vector3(4.25, P + 38.2, -0.9), Vector3(1.05, 1.1, 1.05), 8, 6, copper)
	mb.add_cylinder(Vector3(4.25, P + 38.5, -0.9), Vector3(4.3, P + 41.3, -0.95), 0.75, 0.9, 8, copper)
	mb.add_cylinder(Vector3(4.3, P + 41.3, -0.95), Vector3(4.3, P + 42.5, -0.95), 1.3, 1.9, 12, copper)
	mb.add_cylinder(Vector3(4.3, P + 42.2, -0.95), Vector3(4.3, P + 42.6, -0.95), 2.1, 2.1, 12, copper)
	mb.add_cone(Vector3(4.3, P + 42.5, -0.95), Vector3(4.4, P + 46.2, -1.0), 1.5, 10, gold)
	# left arm cradling the tablet
	mb.add_cylinder(Vector3(-3.1, P + 24.5, -0.4), Vector3(-3.9, P + 17.8, -1.6), 1.15, 0.9, 8, copper)
	mb.add_box_xf(Transform3D(Basis(Vector3.FORWARD, 0.22) * Basis(Vector3.RIGHT, -0.18), Vector3(-4.6, P + 19.5, -1.9)), Vector3(1.0, 7.2, 4.2), copper)
	mb.xf = Transform3D.IDENTITY
	boxes.append([Vector3(0, 27, 0), Vector3(21, 27, 21)])
	boxes.append([Vector3(0, 73, 0), Vector3(7, 23, 7)])


func _empire(mb: MeshBuilder, boxes: Array) -> void:
	## Limestone setbacks with aluminium piers, the 86th-floor deck, the mooring-mast crown that
	## glows at night and the antenna (443 m).
	var lime := _c(Color(0.76, 0.72, 0.64), K.PUNCHED)
	var trim := _c(Color(0.7, 0.67, 0.6), K.STONE)
	var pier := _c(Color(0.8, 0.77, 0.7), K.STONE)
	var alu := _c(Color(0.8, 0.82, 0.84), K.METAL)
	var lamp := _c(Color(0.98, 0.95, 0.85), K.LAMP)
	var roof := _c(Color(0.3, 0.3, 0.31), K.STONE)
	var tiers := [[0.0, 25.0, 64.0, 28.5], [25.0, 82.0, 54.0, 26.0], [82.0, 124.0, 42.0, 24.0], [124.0, 268.0, 31.0, 21.5],
		[268.0, 300.0, 26.0, 18.5], [300.0, 320.0, 21.0, 15.0], [320.0, 330.0, 18.0, 13.0]]
	for t in tiers:
		var y0: float = t[0]
		var y1: float = t[1]
		var hx: float = t[2]
		var hz: float = t[3]
		K.prism(mb, K.rect(hx, hz), y0, y1, lime, 1.0, true, roof)
		K.prism(mb, K.rect(hx + 0.4, hz + 0.4), y1 - 1.0, y1 + 0.6, trim, 1.0, true, roof)
		# vertical piers between the window bays (every 6 m)
		if y1 - y0 > 15.0:
			var nx := int(hx * 2.0 / 6.0)
			for k in nx + 1:
				var px := -hx + (hx * 2.0) * float(k) / nx
				for sz in [-1.0, 1.0]:
					mb.add_box(Vector3(px, (y0 + y1) * 0.5, sz * (hz + 0.2)), Vector3(0.9, y1 - y0, 0.5), pier)
			var nz := int(hz * 2.0 / 6.0)
			for k2 in nz + 1:
				var pz := -hz + (hz * 2.0) * float(k2) / nz
				for sx in [-1.0, 1.0]:
					mb.add_box(Vector3(sx * (hx + 0.2), (y0 + y1) * 0.5, pz), Vector3(0.5, y1 - y0, 0.9), pier)
	# floodlit crown: lamp bands on the upper setbacks
	for yb in [299.5, 319.5, 329.5]:
		var s := 26.6 if yb < 300.0 else (21.6 if yb < 320.0 else 18.6)
		K.prism(mb, K.rect(s, s * 0.71), yb - 0.4, yb + 0.5, lamp)
	# the mooring mast
	K.prism(mb, K.ngon(8, 11.5, PI / 8.0), 330.0, 352.0, alu, 0.86, true, alu)
	for k3 in 8:
		var a := TAU * float(k3) / 8.0 + PI / 8.0
		mb.add_box_xf(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 10.6, 341.0, sin(a) * 10.6)), Vector3(1.4, 22.0, 0.9), lamp)
	K.prism(mb, K.ngon(8, 8.0, PI / 8.0), 352.0, 366.0, alu, 0.8, true, alu)
	K.prism(mb, K.ngon(8, 5.6, PI / 8.0), 366.0, 373.0, lamp, 0.7, true, alu)
	mb.add_sphere(Vector3(0, 374.5, 0), Vector3(3.6, 3.0, 3.6), 10, 5, alu)
	mb.add_cylinder(Vector3(0, 376, 0), Vector3(0, 405, 0), 1.6, 1.0, 8, alu)
	mb.add_cylinder(Vector3(0, 405, 0), Vector3(0, 443, 0), 0.8, 0.25, 6, _c(Color(0.9, 0.9, 0.9), K.METAL))
	_aviation_light(Vector3(0, 443.5, 0))
	_aviation_light(Vector3(0, 405.5, 0), 0.7)
	boxes.append([Vector3(0, 41, 0), Vector3(64, 41, 28)])
	boxes.append([Vector3(0, 200, 0), Vector3(31, 165, 22)])
	boxes.append([Vector3(0, 400, 0), Vector3(6, 45, 6)])


func _one_wtc(mb: MeshBuilder, boxes: Array) -> void:
	## A 61 m square that twists into a 45-degree-rotated square at the roof (eight tall
	## triangular facets), on a podium of glass fins, with the 124 m spire (541 m).
	var glass := _c(Color(0.62, 0.72, 0.82), K.CURTAIN)
	var podium := _c(Color(0.8, 0.82, 0.84), K.RIBBON)
	var steel := _c(Color(0.82, 0.84, 0.86), K.METAL)
	K.prism(mb, K.rect(30.5, 30.5), 0.0, 56.0, podium, 1.0, false)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k in 15:
			mb.add_box_xf(Transform3D(b, b * Vector3(-28.0 + k * 4.0, 28.0, 30.8)), Vector3(0.5, 56.0, 0.7), steel)
	var y0 := 56.0
	var y1 := 417.0
	var rb := 30.5 * sqrt(2.0)
	var rt := 23.5 * sqrt(2.0)
	for k2 in 4:
		var ab0 := PI * 0.25 + k2 * PI * 0.5
		var ab1 := ab0 + PI * 0.5
		var at := ab0 + PI * 0.25
		var b0 := Vector3(cos(ab0) * rb, y0, sin(ab0) * rb)
		var b1 := Vector3(cos(ab1) * rb, y0, sin(ab1) * rb)
		var t1 := Vector3(cos(at) * rt, y1, sin(at) * rt)
		var t0 := Vector3(cos(at - PI * 0.5) * rt, y1, sin(at - PI * 0.5) * rt)
		K.tri(mb, b0, b1, t1, Vector3(cos(at), 0, sin(at)), glass)
		K.tri(mb, t0, b0, t1, Vector3(cos(ab0), 0, sin(ab0)), glass)
	# parapet, spire base and the spire with its maintenance rings
	K.prism(mb, K.ngon(4, rt, 0.0), y1, y1 + 8.0, steel)
	mb.add_cylinder(Vector3(0, 425, 0), Vector3(0, 434, 0), 7.0, 5.0, 12, steel)
	mb.add_cylinder(Vector3(0, 434, 0), Vector3(0, 541, 0), 2.0, 0.45, 8, steel)
	for ry in [446.0, 470.0, 494.0, 518.0]:
		mb.add_cylinder(Vector3(0, ry, 0), Vector3(0, ry + 1.2, 0), 3.4, 3.4, 10, steel)
	_fine.add_sphere(Vector3(0, 541.5, 0), Vector3.ONE * 1.2, 8, 5, _c(Color(1, 1, 1), K.LAMP))
	boxes.append([Vector3(0, 210, 0), Vector3(32, 210, 32)])
	boxes.append([Vector3(0, 480, 0), Vector3(4, 60, 4)])


func _willis(mb: MeshBuilder, boxes: Array) -> void:
	## Nine bundled black tubes stepping back at floors 50, 66 and 90, with the twin masts.
	var glass := _c(Color(0.17, 0.16, 0.16), K.CURTAIN)
	var band := _c(Color(0.07, 0.07, 0.08), K.STONE)
	var roof := _c(Color(0.22, 0.22, 0.23), K.STONE)
	var heights := [[270.0, 368.0, 205.0], [442.0, 442.0, 270.0], [205.0, 368.0, 270.0]]
	for i in 3:
		for j in 3:
			var h: float = heights[i][j]
			var cx := (i - 1) * 23.0
			var cz := (j - 1) * 23.0
			K.prism(mb, K.rect(11.5, 11.5, cx, cz), 0.0, h, glass, 1.0, true, roof)
			# black louvre bands at the mechanical floors
			for yb in [104.0, 200.0, 262.0, 360.0, 434.0]:
				if yb < h - 3.0:
					K.prism(mb, K.rect(11.65, 11.65, cx, cz), yb, yb + 6.0, band, 1.0, false)
			if h > 300.0:
				K.prism(mb, K.rect(6.0, 5.0, cx, cz), h, h + 4.0, roof)
	for p in [Vector3(-12, 442, -6), Vector3(12, 442, -6)]:
		mb.add_cylinder(p, p + Vector3(0, 85, 0), 1.6, 0.4, 8, _c(Color(0.9, 0.9, 0.9), K.METAL))
		_aviation_light(p + Vector3(0, 85.5, 0))
	boxes.append([Vector3(0, 221, 0), Vector3(35, 221, 35)])


# ================================================================== London
func _shard(mb: MeshBuilder, boxes: Array) -> void:
	## Eight leaning glass shards around a tapering core; they overshoot the top at different
	## heights and leave the spire open (310 m).
	var glass := _c(Color(0.72, 0.8, 0.88), K.CURTAIN)
	var core := _c(Color(0.55, 0.62, 0.7), K.CURTAIN)
	K.loft2(mb, K.rect(27.0, 27.0), 0.0, K.rect(2.0, 2.0), 296.0, core)
	var tops := [306.0, 288.0, 300.0, 292.0, 310.0, 284.0, 298.0, 291.0]
	var apex := 330.0
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for half in 2:
			var off := 1.0 if (side + half) % 2 == 0 else 0.0
			var ty: float = tops[side * 2 + half]
			var s0 := 29.0 + off
			var s1 := s0 * (1.0 - ty / apex)
			var x0 := -1.0 if half == 0 else 0.0
			var x1 := 0.0 if half == 0 else 1.0
			var p0 := b * Vector3(x0 * s0, 0.0, s0)
			var p1 := b * Vector3(x1 * s0, 0.0, s0)
			var p2 := b * Vector3(x1 * s1, ty, s1)
			var p3 := b * Vector3(x0 * s1, ty, s1)
			K.quad(mb, p0, p1, p2, p3, b * Vector3(0, 0.1, 1), glass)
	# plaza and the London Bridge station canopy
	K.prism(mb, K.rect(55.0, 40.0), 0.0, 0.6, _c(Color(0.66, 0.64, 0.6), K.STONE))
	_aviation_light(Vector3(0, 311.0, 0))
	boxes.append([Vector3(0, 130, 0), Vector3(30, 130, 30)])


func _big_ben(mb: MeshBuilder, boxes: Array) -> void:
	## Elizabeth Tower (96 m) with lit clock faces, the Palace of Westminster along the river,
	## the Central Tower and Victoria Tower.
	var sand := _c(Color(0.82, 0.72, 0.52), K.STONE)
	var sandw := _c(Color(0.82, 0.72, 0.52), K.PUNCHED)
	var slate := _c(Color(0.24, 0.27, 0.3), K.METAL)
	var gold := _c(Color(0.86, 0.7, 0.32), K.METAL)
	var face := _c(Color(0.98, 0.95, 0.82), K.LAMP)
	var dark := _c(Color(0.08, 0.08, 0.1), K.DARK_GLASS)
	# palace: river front, slate roof, pinnacles and the Central Tower
	K.prism(mb, K.rect(128.0, 35.0, 132.0, 0.0), 0.0, 28.0, sandw, 1.0, false)
	K.loft2(mb, K.rect(128.0, 33.0, 132.0, 0.0), 28.0, K.rect(126.0, 5.0, 132.0, 0.0), 37.0, slate)
	for k in 29:
		var px := 12.0 + k * 8.9
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(px, 16.0, sz * 35.6), Vector3(1.4, 32.0, 1.2), sand)
			mb.add_cone(Vector3(px, 32.0, sz * 35.6), Vector3(px, 39.0, sz * 35.6), 1.0, 4, sand)
	K.prism(mb, K.ngon(8, 9.0, PI / 8.0, 128.0, 0.0), 28.0, 66.0, sandw)
	K.loft2(mb, K.ngon(8, 9.0, PI / 8.0, 128.0, 0.0), 66.0, K.ngon(8, 0.5, PI / 8.0, 128.0, 0.0), 91.0, slate)
	# Victoria Tower with corner turrets and the flag
	K.prism(mb, K.rect(11.5, 11.5, 262.0, 0.0), 0.0, 92.0, sandw)
	for cx in [-10.5, 10.5]:
		for cz in [-10.5, 10.5]:
			K.prism(mb, K.ngon(8, 2.2, PI / 8.0, 262.0 + cx, cz), 0.0, 98.0, sand)
			mb.add_cone(Vector3(262.0 + cx, 98.0, cz), Vector3(262.0 + cx, 104.0, cz), 2.0, 8, gold)
	K.loft2(mb, K.rect(10.0, 10.0, 262.0, 0.0), 92.0, K.rect(5.0, 5.0, 262.0, 0.0), 96.0, slate)
	_fine.add_cylinder(Vector3(262, 96, 0), Vector3(262, 112, 0), 0.25, 0.15, 6, _c(Color(0.9, 0.9, 0.9), K.METAL))
	_fine.add_box(Vector3(262, 109.5, 3.0), Vector3(0.1, 4.0, 6.0), _c(Color(0.75, 0.1, 0.12), K.STONE))
	# Elizabeth Tower: shaft, clock stage, belfry, slate spire and gilded finial
	K.prism(mb, K.rect(6.0, 6.0), 0.0, 54.0, sandw)
	for cx2 in [-6.0, 6.0]:
		for cz2 in [-6.0, 6.0]:
			mb.add_box(Vector3(cx2, 27.0, cz2), Vector3(1.4, 54.0, 1.4), sand)
	K.prism(mb, K.rect(7.3, 7.3), 54.0, 70.0, sand)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		mb.add_cylinder(b * Vector3(0, 62.0, 7.3), b * Vector3(0, 62.0, 7.75), 3.55, 3.55, 20, face)
		mb.add_cylinder(b * Vector3(0, 62.0, 7.25), b * Vector3(0, 62.0, 7.55), 4.2, 4.2, 20, gold)
		_fine.add_box_xf(Transform3D(b * Basis(Vector3.BACK, 0.7), b * Vector3(0, 62.0, 7.85)), Vector3(0.3, 4.6, 0.1), dark)
		_fine.add_box_xf(Transform3D(b * Basis(Vector3.BACK, -1.9), b * Vector3(0, 62.0, 7.9)), Vector3(0.35, 3.2, 0.1), dark)
		for k2 in 3:
			mb.add_box_xf(Transform3D(b, b * Vector3((k2 - 1) * 3.4, 74.5, 6.15)), Vector3(1.6, 5.0, 0.4), dark)
	K.prism(mb, K.rect(6.4, 6.4), 70.0, 78.5, sand)
	K.loft2(mb, K.rect(6.9, 6.9), 78.5, K.rect(0.7, 0.7), 92.0, slate)
	for cx3 in [-6.2, 6.2]:
		for cz3 in [-6.2, 6.2]:
			mb.add_cone(Vector3(cx3, 78.5, cz3), Vector3(cx3, 86.0, cz3), 1.0, 6, gold)
	K.prism(mb, K.rect(1.6, 1.6), 86.0, 89.0, gold)
	mb.add_cone(Vector3(0, 91.5, 0), Vector3(0, 96.0, 0), 0.7, 6, gold)
	boxes.append([Vector3(0, 48, 0), Vector3(8, 48, 8)])
	boxes.append([Vector3(130, 20, 0), Vector3(135, 20, 35)])
	boxes.append([Vector3(262, 54, 0), Vector3(12, 54, 12)])


func _london_eye(mb: MeshBuilder, boxes: Array) -> void:
	var white := _c(Color(0.92, 0.93, 0.95), K.METAL)
	var pod := _c(Color(0.72, 0.84, 0.95), K.LAMP)
	var cy := 75.0
	var rr := 66.0
	var n := 64
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		for zz in [-1.6, 1.6]:
			var p0 := Vector3(cos(a0) * rr, cy + sin(a0) * rr, zz)
			var p1 := Vector3(cos(a1) * rr, cy + sin(a1) * rr, zz)
			mb.add_cylinder(p0, p1, 0.6, 0.6, 4, white, false)
		if k % 2 == 0:
			_fine.add_cylinder(Vector3(cos(a0) * rr, cy + sin(a0) * rr, -1.6), Vector3(cos(a1) * rr, cy + sin(a1) * rr, 1.6), 0.2, 0.2, 3, white, false)
	for k in 32:
		var a := TAU * k / 32.0
		mb.add_cylinder(Vector3(0, cy, (k % 2) * 6.0 - 3.0), Vector3(cos(a) * rr, cy + sin(a) * rr, 0), 0.18, 0.18, 3, white, false)
	for k in 32:
		var a2 := TAU * k / 32.0
		mb.add_sphere(Vector3(cos(a2) * (rr + 2.8), cy + sin(a2) * (rr + 2.8), 0), Vector3(2.4, 2.0, 4.0), 8, 5, pod)
	mb.add_cylinder(Vector3(0, cy, -5), Vector3(0, cy, 5), 3.0, 3.0, 12, white)
	mb.add_cylinder(Vector3(-30, 0, 35), Vector3(0, cy, 2), 1.6, 1.2, 8, white)
	mb.add_cylinder(Vector3(30, 0, 35), Vector3(0, cy, 2), 1.6, 1.2, 8, white)
	_fine.add_cylinder(Vector3(-30, 40, 35), Vector3(30, 40, 35), 0.4, 0.4, 4, white, false)
	K.prism(mb, K.rect(40.0, 10.0, 0.0, 38.0), 0.0, 1.0, _c(Color(0.5, 0.5, 0.52), K.STONE))
	boxes.append([Vector3(0, cy, 0), Vector3(68, 68, 4)])


func _tower_bridge(mb: MeshBuilder, boxes: Array) -> void:
	var stone := _c(Color(0.8, 0.76, 0.68), K.PUNCHED)
	var stone_p := _c(Color(0.8, 0.76, 0.68), K.STONE)
	var blue := _c(Color(0.38, 0.6, 0.8), K.METAL)
	var white := _c(Color(0.9, 0.9, 0.9), K.METAL)
	var slate := _c(Color(0.3, 0.32, 0.36), K.METAL)
	var gold := _c(Color(0.86, 0.7, 0.32), K.METAL)
	var deck := _c(Color(0.22, 0.22, 0.24), K.STONE)
	for tz in [-38.0, 38.0]:
		mb.add_box(Vector3(0, -6, tz), Vector3(28, 16, 32), stone_p)
		K.prism(mb, K.rect(9.0, 9.0, 0.0, tz), 2.0, 58.0, stone)
		for cx in [-8.5, 8.5]:
			for cz in [-8.5, 8.5]:
				K.prism(mb, K.ngon(8, 2.4, PI / 8.0, cx, tz + cz), 2.0, 60.0, stone_p)
				mb.add_cone(Vector3(cx, 60, tz + cz), Vector3(cx, 68, tz + cz), 2.3, 8, slate)
				_fine.add_cone(Vector3(cx, 67.5, tz + cz), Vector3(cx, 70.5, tz + cz), 0.4, 4, gold)
		K.loft2(mb, K.rect(8.5, 8.5, 0.0, tz), 58.0, K.rect(1.0, 1.0, 0.0, tz), 72.0, slate)
		mb.add_cone(Vector3(0, 71.5, tz), Vector3(0, 76.0, tz), 0.6, 6, gold)
	# high-level walkways (blue lattice girders) and the bascule road deck
	for wy in [44.0, 49.0]:
		for wx in [-4.0, 4.0]:
			mb.add_box(Vector3(wx, wy, 0), Vector3(3, 3.4, 58), blue)
	for k in 10:
		var zz := -26.0 + k * 5.8
		_fine.add_cylinder(Vector3(-5.5, 42.5, zz), Vector3(-5.5, 50.5, zz + 5.8), 0.25, 0.25, 3, white, false)
		_fine.add_cylinder(Vector3(5.5, 42.5, zz), Vector3(5.5, 50.5, zz + 5.8), 0.25, 0.25, 3, white, false)
	mb.add_box(Vector3(0, 9, 0), Vector3(16, 2.5, 330), deck)
	for sx in [-8.2, 8.2]:
		mb.add_box(Vector3(sx, 10.8, 0), Vector3(0.6, 1.2, 330), blue)
	for sgn in [-1.0, 1.0]:
		for sx in [-8.0, 8.0]:
			var a := Vector3(sx, 40, 38.0 * sgn)
			var b := Vector3(sx, 12, 165.0 * sgn)
			for k in 10:
				var t0 := float(k) / 10.0
				var t1 := float(k + 1) / 10.0
				var p0 := a.lerp(b, t0) + Vector3(0, -sin(t0 * PI) * 8.0, 0)
				var p1 := a.lerp(b, t1) + Vector3(0, -sin(t1 * PI) * 8.0, 0)
				mb.add_cylinder(p0, p1, 0.9, 0.9, 4, blue, false)
				if k > 0:
					mb.add_cylinder(p0, Vector3(p0.x, 10.5, p0.z), 0.25, 0.25, 3, blue, false)
	boxes.append([Vector3(0, 30, -38), Vector3(11, 36, 11)])
	boxes.append([Vector3(0, 30, 38), Vector3(11, 36, 11)])
	boxes.append([Vector3(0, 46, 0), Vector3(8, 4, 30)])


func _suspension(mb: MeshBuilder, boxes: Array, span: float, tower_h: float, deck_h: float, length: float, width: float, tower_col: Color, cable_col: Color, stone: bool) -> void:
	## A suspension bridge along local Z: two towers, the deck, main cables and hangers.
	var half_s := span * 0.5
	var half_l := length * 0.5
	var tcol := _c(tower_col, K.STONE)
	var tdark := _c(tower_col.darkened(0.2), K.STONE)
	var ccol := _c(cable_col, K.METAL)
	var deck := _c(Color(0.24, 0.24, 0.26), K.STONE)
	var pier := _c(Color(0.6, 0.58, 0.55), K.STONE)
	mb.add_box(Vector3(0, deck_h, 0), Vector3(width, 3.5, length), deck)
	mb.add_box(Vector3(0, deck_h + 2.2, 0), Vector3(width + 1.0, 1.0, length), _c(tower_col.darkened(0.15), K.STONE))
	# stiffening truss under the deck
	mb.add_box(Vector3(0, deck_h - 5.0, 0), Vector3(width - 2.0, 7.0, length), _c(tower_col.darkened(0.35), K.METAL))
	for tz in [-half_s, half_s]:
		if stone:
			# masonry towers with twin Gothic arches
			mb.add_box(Vector3(0, deck_h * 0.5 - 10.0, tz), Vector3(width + 18.0, deck_h + 20.0, 34.0), tcol)
			for sx in [-1.0, 0.0, 1.0]:
				var pw := 12.0 if sx != 0.0 else 8.0
				mb.add_box(Vector3(sx * (width * 0.5 + 2.0), (deck_h + tower_h) * 0.5, tz), Vector3(pw, tower_h - deck_h, 30.0), tcol)
			for sx2 in [-1.0, 1.0]:
				mb.add_arch(Vector3(sx2 * (width * 0.25 + 1.0), tower_h - 30.0, tz), width * 0.5 - 6.0, 8.0, 30.0, 8, tcol)
			mb.add_box(Vector3(0, tower_h - 9.0, tz), Vector3(width + 16.0, 18.0, 30.0), tcol)
			mb.add_box(Vector3(0, tower_h + 0.8, tz), Vector3(width + 18.0, 1.6, 32.0), tdark)
		else:
			# art deco steel towers: legs stepping in at each portal strut, recessed panels
			for sx3 in [-1.0, 1.0]:
				var segs := [[-20.0, deck_h + 30.0, 10.0, 14.0], [deck_h + 30.0, tower_h * 0.62, 9.0, 12.0], [tower_h * 0.62, tower_h * 0.86, 8.0, 10.5], [tower_h * 0.86, tower_h, 7.0, 9.0]]
				for sg in segs:
					var y0: float = sg[0]
					var y1: float = sg[1]
					var lw: float = sg[2]
					var ld: float = sg[3]
					mb.add_box(Vector3(sx3 * width * 0.5, (y0 + y1) * 0.5, tz), Vector3(lw, y1 - y0, ld), tcol)
					_fine.add_box(Vector3(sx3 * width * 0.5, (y0 + y1) * 0.5, tz + ld * 0.5 + 0.1), Vector3(lw * 0.5, (y1 - y0) * 0.8, 0.3), tdark)
					_fine.add_box(Vector3(sx3 * width * 0.5, (y0 + y1) * 0.5, tz - ld * 0.5 - 0.1), Vector3(lw * 0.5, (y1 - y0) * 0.8, 0.3), tdark)
			for by in [deck_h + 30.0, tower_h * 0.62, tower_h * 0.86, tower_h - 4.0]:
				mb.add_box(Vector3(0, by, tz), Vector3(width, 7.0, 8.0), tcol)
			mb.add_box(Vector3(0, -12.0, tz), Vector3(width + 22.0, 24.0, 40.0), pier)
			_aviation_light(Vector3(-width * 0.5, tower_h + 1.0, tz))
			_aviation_light(Vector3(width * 0.5, tower_h + 1.0, tz))
		boxes.append([Vector3(0, tower_h * 0.5, tz), Vector3(width * 0.5 + 8.0, tower_h * 0.5, 16.0)])
	boxes.append([Vector3(0, deck_h, 0), Vector3(width * 0.5, 3.0, half_l)])
	for sx4 in [-1.0, 1.0]:
		var px: float = sx4 * width * 0.5
		var pts := []
		# main span: parabola from tower top down to just above the deck
		for k in 41:
			var t := float(k) / 40.0
			var zz := lerpf(-half_s, half_s, t)
			var yy := deck_h + 4.0 + (tower_h - deck_h - 6.0) * pow((zz / half_s), 2.0)
			pts.append(Vector3(px, yy, zz))
		for k2 in pts.size() - 1:
			mb.add_cylinder(pts[k2], pts[k2 + 1], 0.9, 0.9, 5, ccol, false)
			var hp: Vector3 = pts[k2]
			if k2 > 0:
				var hanger_mb: MeshBuilder = mb if k2 % 2 == 0 else _fine
				hanger_mb.add_cylinder(hp, Vector3(px, deck_h + 1.5, hp.z), 0.2, 0.2, 3, ccol, false)
		# side spans down to the anchorages
		for sgn in [-1.0, 1.0]:
			var a := Vector3(px, tower_h - 2.0, half_s * sgn)
			var b := Vector3(px, deck_h + 2.0, half_l * sgn)
			for k3 in 10:
				var t0 := float(k3) / 10.0
				var t1 := float(k3 + 1) / 10.0
				var q0 := a.lerp(b, t0) - Vector3(0, sin(t0 * PI) * 10.0, 0)
				var q1 := a.lerp(b, t1) - Vector3(0, sin(t1 * PI) * 10.0, 0)
				mb.add_cylinder(q0, q1, 0.9, 0.9, 5, ccol, false)
				if k3 > 0:
					_fine.add_cylinder(q0, Vector3(px, deck_h + 1.5, q0.z), 0.2, 0.2, 3, ccol, false)
	for sgn2 in [-1.0, 1.0]:
		mb.add_box(Vector3(0, deck_h * 0.5, half_l * sgn2), Vector3(width + 10.0, deck_h + 6.0, 40.0), pier)


# ================================================================== Paris
func _eiffel(mb: MeshBuilder, boxes: Array) -> void:
	## Wrought-iron lattice: four curved legs braced in X panels, the decorative arches, three
	## platforms and the lattice shaft to the antenna (330 m). Tokyo Tower uses the same frame
	## in international orange and white.
	var tokyo := _id == "ttower"
	var iron := _c(Color(0.47, 0.38, 0.29), K.STONE)
	var orange := _c(Color(0.92, 0.36, 0.1), K.STONE)
	var white := _c(Color(0.94, 0.94, 0.92), K.STONE)
	var deck := _c(Color(0.36, 0.3, 0.24), K.STONE)
	var lamp := _c(Color(1.0, 0.85, 0.55), K.LAMP)
	# half-width of the silhouette, legs merge at the second platform
	var lv := [0.0, 14.0, 28.0, 43.0, 57.0, 72.0, 86.0, 100.0, 115.0]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rings := []
			for yv in lv:
				var y: float = yv
				var w := 62.5 * exp(-y / 101.0)
				var ls := lerpf(26.0, 12.0, y / 115.0)
				var wi := w - ls
				rings.append([Vector3(sx * w, y, sz * w), Vector3(sx * wi, y, sz * w), Vector3(sx * wi, y, sz * wi), Vector3(sx * w, y, sz * wi)])
			var col := iron if not tokyo else orange
			K.lattice(mb, rings, 1.5, 0.55, col)
			# solid web on the outer faces keeps the legs readable from afar
			for i in rings.size() - 1:
				var r0: Array = rings[i]
				var r1: Array = rings[i + 1]
				var mid0: Vector3 = (r0[0] + r0[1] + r0[2] + r0[3]) * 0.25
				var mid1: Vector3 = (r1[0] + r1[1] + r1[2] + r1[3]) * 0.25
				mb.add_cylinder(mid0, mid1, (r0[0] as Vector3).distance_to(r0[2]) * 0.18, (r1[0] as Vector3).distance_to(r1[2]) * 0.18, 4, col, false)
	# arches between the legs under the first platform
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k in 12:
			var t0 := float(k) / 12.0
			var t1 := float(k + 1) / 12.0
			var p0 := b * Vector3(lerpf(-30.0, 30.0, t0), 17.0 + sin(t0 * PI) * 22.0, -42.0)
			var p1 := b * Vector3(lerpf(-30.0, 30.0, t1), 17.0 + sin(t1 * PI) * 22.0, -42.0)
			mb.add_cylinder(p0, p1, 1.3, 1.3, 4, iron if not tokyo else orange, false)
	# first platform: a square ring with its gallery, second platform, top cabin
	var pc := deck if not tokyo else white
	for side2 in 4:
		var b2 := Basis(Vector3.UP, side2 * PI * 0.5)
		mb.add_box_xf(Transform3D(b2, b2 * Vector3(0, 60.0, -29.0)), Vector3(70.0, 6.0, 12.0), pc)
		_fine.add_box_xf(Transform3D(b2, b2 * Vector3(0, 64.2, -35.0)), Vector3(70.0, 2.4, 0.3), _c(Color(0.3, 0.26, 0.2), K.STONE))
		mb.add_box_xf(Transform3D(b2, b2 * Vector3(0, 59.0, -34.9)), Vector3(70.4, 1.2, 0.4), lamp)
	mb.add_box(Vector3(0, 117.0, 0), Vector3(40.0, 5.0, 40.0), pc)
	for side3 in 4:
		var b3 := Basis(Vector3.UP, side3 * PI * 0.5)
		mb.add_box_xf(Transform3D(b3, b3 * Vector3(0, 116.0, -20.0)), Vector3(40.4, 1.0, 0.4), lamp)
	# upper shaft: lattice of four chords with an elevator core
	var up_lv := [119.0, 136.0, 153.0, 170.0, 188.0, 206.0, 224.0, 242.0, 259.0, 276.0]
	var up_rings := []
	for yv2 in up_lv:
		var y2: float = yv2
		var w2 := 62.5 * exp(-y2 / 101.0) + 0.8
		up_rings.append([Vector3(w2, y2, w2), Vector3(-w2, y2, w2), Vector3(-w2, y2, -w2), Vector3(w2, y2, -w2)])
	if not tokyo:
		K.lattice(mb, up_rings, 1.2, 0.45, iron)
		K.loft2(mb, K.rect(9.0, 9.0), 119.0, K.rect(2.6, 2.6), 276.0, iron)
	else:
		for i2 in up_rings.size() - 1:
			K.lattice(mb, [up_rings[i2], up_rings[i2 + 1]], 1.2, 0.45, orange if i2 % 2 == 0 else white)
		K.loft2(mb, K.rect(9.0, 9.0), 119.0, K.rect(2.6, 2.6), 276.0, orange)
		K.prism(mb, K.rect(14.0, 14.0), 150.0, 160.0, _c(Color(0.75, 0.8, 0.85), K.RIBBON))
	K.prism(mb, K.rect(8.5, 8.5), 276.0, 283.0, _c(Color(0.5, 0.45, 0.38), K.PUNCHED))
	K.prism(mb, K.rect(5.0, 5.0), 283.0, 288.0, pc)
	mb.add_cylinder(Vector3(0, 288, 0), Vector3(0, 300, 0), 2.2, 1.6, 8, pc)
	mb.add_cylinder(Vector3(0, 300, 0), Vector3(0, 330, 0), 1.1, 0.35, 6, _c(Color(0.75, 0.75, 0.75), K.METAL))
	_fine.add_sphere(Vector3(0, 301.0, 0), Vector3(2.0, 1.2, 2.0), 8, 4, lamp)
	_aviation_light(Vector3(0, 330.5, 0))
	K.prism(mb, K.rect(90.0, 90.0), 0.0, 0.4, _c(Color(0.72, 0.68, 0.6), K.STONE))
	boxes.append([Vector3(0, 60, 0), Vector3(62, 60, 62)])
	boxes.append([Vector3(0, 220, 0), Vector3(10, 110, 10)])


func _arc(mb: MeshBuilder, boxes: Array) -> void:
	## Arc de Triomphe (India Gate shares it): four piers pierced both ways, the vaults, cornice
	## and attic, on its round plaza.
	var st := _c(Color(0.87, 0.83, 0.73), K.STONE)
	var relief := _c(Color(0.74, 0.7, 0.6), K.STONE)
	var plaza := _c(Color(0.62, 0.6, 0.57), K.STONE)
	mb.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 0.3, 0), 120.0, 120.0, 40, plaza)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(sx * 15.4, 15.0, sz * 7.3), Vector3(14.2, 30.0, 7.4), st)
			_fine.add_box(Vector3(sx * 15.4, 12.0, sz * 11.1), Vector3(9.0, 11.0, 0.4), relief)
		mb.add_arch(Vector3(sx * 15.4, 18.7, 0), 8.4, 4.2, 7.2, 8, st)
	mb.add_box(Vector3(0, 33.0, 0), Vector3(45.0, 6.0, 22.0), st)
	mb.add_box(Vector3(0, 36.5, 0), Vector3(46.4, 1.4, 23.4), relief)
	mb.add_box(Vector3(0, 42.5, 0), Vector3(44.6, 11.0, 21.6), st)
	mb.add_box(Vector3(0, 48.4, 0), Vector3(45.6, 1.2, 22.6), relief)
	mb.add_arch(Vector3(0, 22.6, 0), 14.6, 7.3, 22.0, 12, st)
	mb.add_box(Vector3(0, 26.5, 0), Vector3(14.6, 7.0, 22.0), st)
	boxes.append([Vector3(0, 25, 0), Vector3(23, 25, 11)])


# ================================================================== North America
func _cn_tower(mb: MeshBuilder, boxes: Array) -> void:
	## Toronto: hexagonal shaft braced by three tapering buttress legs, the SkyPod (lit window
	## ring), the SkyPod deck and the antenna mast (553 m).
	var conc := _c(Color(0.82, 0.81, 0.78), K.STONE)
	var pod := _c(Color(0.86, 0.85, 0.82), K.STONE)
	var win := _c(Color(0.35, 0.4, 0.46), K.RIBBON)
	var red := _c(Color(0.88, 0.2, 0.15), K.METAL)
	var white := _c(Color(0.92, 0.92, 0.92), K.METAL)
	K.prism(mb, K.ngon(6, 10.0), 0.0, 335.0, conc, 0.62)
	var tiers := [[0.0, 60.0, 30.0], [60.0, 130.0, 24.0], [130.0, 200.0, 18.0], [200.0, 260.0, 13.0], [260.0, 310.0, 9.0], [310.0, 335.0, 6.5]]
	for t in tiers:
		var y0: float = t[0]
		var y1: float = t[1]
		var ln: float = t[2]
		var ln1 := ln * 0.82
		for k in 3:
			var a := TAU * k / 3.0 + PI * 0.5
			K.loft2(mb, K.wing_plan(a, ln, 7.0, 2), y0, K.wing_plan(a, ln1, 6.0, 2), y1, conc)
	mb.add_cylinder(Vector3(0, 335, 0), Vector3(0, 342, 0), 15.0, 21.0, 24, pod)
	mb.add_cylinder(Vector3(0, 342, 0), Vector3(0, 351, 0), 21.0, 23.5, 24, win)
	mb.add_cylinder(Vector3(0, 351, 0), Vector3(0, 360, 0), 23.5, 22.5, 24, pod)
	mb.add_cylinder(Vector3(0, 360, 0), Vector3(0, 368, 0), 22.5, 14.0, 24, win)
	mb.add_cylinder(Vector3(0, 368, 0), Vector3(0, 372, 0), 14.0, 8.0, 18, pod)
	mb.add_cylinder(Vector3(0, 372, 0), Vector3(0, 447, 0), 6.0, 4.8, 8, conc)
	mb.add_cylinder(Vector3(0, 447, 0), Vector3(0, 457, 0), 8.5, 8.5, 14, win)
	mb.add_cylinder(Vector3(0, 457, 0), Vector3(0, 460, 0), 8.5, 4.5, 14, pod)
	for k2 in 6:
		var y2 := 460.0 + k2 * 15.5
		mb.add_cylinder(Vector3(0, y2, 0), Vector3(0, y2 + 15.5, 0), 3.0 - k2 * 0.4, 2.8 - k2 * 0.4, 8, red if k2 % 2 == 0 else white)
	_aviation_light(Vector3(0, 553.5, 0), 1.0)
	_aviation_light(Vector3(0, 447.0, 6.2), 0.8)
	boxes.append([Vector3(0, 170, 0), Vector3(20, 170, 20)])
	boxes.append([Vector3(0, 352, 0), Vector3(24, 18, 24)])
	boxes.append([Vector3(0, 460, 0), Vector3(8, 93, 8)])


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
	## US Capitol: wings with windows, the portico, the cast-iron dome on its colonnaded drum,
	## the lantern and the Statue of Freedom.
	var w := _c(Color(0.93, 0.92, 0.89), K.STONE)
	var ww := _c(Color(0.93, 0.92, 0.89), K.PUNCHED)
	var roof := _c(Color(0.62, 0.64, 0.62), K.STONE)
	K.prism(mb, K.rect(115.0, 36.0), 0.0, 32.0, ww, 1.0, true, roof)
	K.prism(mb, K.rect(111.0, 32.0), 32.0, 36.0, w, 1.0, true, roof)
	mb.add_box(Vector3(0, 20, 42), Vector3(60, 36, 14), w)
	K.loft2(mb, K.rect(30.0, 8.0, 0.0, 42.0), 36.0, K.rect(28.0, 0.5, 0.0, 42.0), 44.0, w)
	for k in 12:
		mb.add_cylinder(Vector3(-27 + k * 4.9, 4, 50), Vector3(-27 + k * 4.9, 34, 50), 1.2, 1.05, 10, w)
	mb.add_box(Vector3(0, 2, 56), Vector3(54, 4, 16), w)
	mb.add_cylinder(Vector3(0, 32, 0), Vector3(0, 40, 0), 33.0, 32.0, 32, w)
	mb.add_cylinder(Vector3(0, 40, 0), Vector3(0, 62, 0), 28.0, 27.0, 32, ww)
	for k2 in 36:
		var a := TAU * k2 / 36.0
		mb.add_cylinder(Vector3(cos(a) * 31.0, 40, sin(a) * 31.0), Vector3(cos(a) * 31.0, 58, sin(a) * 31.0), 0.9, 0.8, 8, w)
	mb.add_cylinder(Vector3(0, 58, 0), Vector3(0, 63, 0), 32.0, 30.0, 32, w)
	mb.add_cylinder(Vector3(0, 63, 0), Vector3(0, 70, 0), 26.0, 25.0, 32, ww)
	mb.add_sphere(Vector3(0, 70, 0), Vector3(25, 22, 25), 32, 10, w)
	for k3 in 16:
		var a3 := TAU * k3 / 16.0
		var rib := []
		for j in 6:
			var ph := float(j) / 5.0 * PI * 0.47
			rib.append(Vector3(cos(a3) * 25.3 * cos(ph), 70.0 + 22.3 * sin(ph), sin(a3) * 25.3 * cos(ph)))
		for j2 in 5:
			_fine.add_cylinder(rib[j2], rib[j2 + 1], 0.45, 0.45, 4, w, false)
	mb.add_cylinder(Vector3(0, 91, 0), Vector3(0, 100, 0), 4.5, 3.8, 14, w)
	mb.add_sphere(Vector3(0, 100, 0), Vector3(3.8, 3.0, 3.8), 12, 5, w)
	mb.add_cylinder(Vector3(0, 102, 0), Vector3(0, 107, 0), 1.0, 0.6, 8, _c(Color(0.35, 0.33, 0.28), K.METAL))
	boxes.append([Vector3(0, 18, 0), Vector3(115, 18, 36)])
	boxes.append([Vector3(0, 60, 0), Vector3(30, 40, 30)])


func _obelisk(mb: MeshBuilder, boxes: Array) -> void:
	var w := _c(Color(0.93, 0.92, 0.88), K.STONE)
	var w2 := _c(Color(0.86, 0.84, 0.8), K.STONE)
	var dark := _c(Color(0.1, 0.1, 0.1), K.DARK_GLASS)
	K.prism(mb, K.rect(8.4, 8.4), 0.0, 46.0, w2, 0.96)
	K.prism(mb, K.rect(8.1, 8.1), 46.0, 152.0, w, 0.65)
	K.loft2(mb, K.rect(5.27, 5.27), 152.0, K.rect(0.05, 0.05), 169.0, w)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k in 2:
			mb.add_box_xf(Transform3D(b, b * Vector3((k - 0.5) * 2.6, 150.0, 5.35)), Vector3(0.8, 1.6, 0.2), dark)
	_aviation_light(Vector3(0, 160.0, 3.6), 0.5)
	# the ring of flags
	for k2 in 50:
		var a := TAU * k2 / 50.0
		var p := Vector3(cos(a) * 32.0, 0, sin(a) * 32.0)
		_fine.add_cylinder(p, p + Vector3(0, 15, 0), 0.12, 0.08, 4, _c(Color(0.85, 0.85, 0.85), K.METAL), false)
		_fine.add_box(p + Vector3(0, 14, 0.9), Vector3(0.05, 1.2, 1.8), _c(Color(0.75, 0.1, 0.15) if k2 % 2 == 0 else Color(0.15, 0.2, 0.5), K.STONE))
	mb.add_cylinder(Vector3(0, -0.5, 0), Vector3(0, 0.3, 0), 36.0, 36.0, 32, _c(Color(0.7, 0.68, 0.64), K.STONE))
	boxes.append([Vector3(0, 84, 0), Vector3(9, 84, 9)])


# ================================================================== Rome
func _colosseum(mb: MeshBuilder, boxes: Array) -> void:
	## Travertine ellipse with three tiers of arcades and the attic (partly fallen on the south
	## side), the stepped cavea inside and the exposed hypogeum.
	var tr := _c(Color(0.82, 0.73, 0.58), K.STONE)
	var band := _c(Color(0.62, 0.54, 0.43), K.STONE)
	var dark := _c(Color(0.12, 0.1, 0.08), K.DARK_GLASS)
	var n := 64
	for k in n:
		var a := TAU * (k + 0.5) / n
		var c := Vector3(cos(a) * 78.0, 0, sin(a) * 62.0)
		var tangent := Vector3(-sin(a) * 78.0, 0, cos(a) * 62.0).normalized()
		var b := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP))
		var seg := 2.0 * PI * 70.0 / n + 0.8
		var h := 48.0 if k < 44 else 34.0
		mb.add_box_xf(Transform3D(b, c + Vector3(0, h * 0.5, 0)), Vector3(seg, h, 14.0), tr)
		var outer := b.z * -7.05
		for by in [11.0, 23.0, 35.0]:
			if by < h - 2.0:
				mb.add_box_xf(Transform3D(b, c + Vector3(0, by + 0.8, 0)), Vector3(seg + 0.2, 1.4, 14.6), band)
		var tiers := [[5.6, 8.4], [17.4, 7.4], [29.2, 7.0]]
		for t in tiers:
			var ty: float = t[0]
			var th: float = t[1]
			if ty + th * 0.5 < h:
				mb.add_box_xf(Transform3D(b, c + outer + Vector3(0, ty, 0)), Vector3(seg * 0.56, th, 0.3), dark)
		if h > 40.0:
			_fine.add_box_xf(Transform3D(b, c + outer + Vector3(0, 42.0, 0)), Vector3(seg * 0.25, 2.2, 0.3), dark)
	# cavea: stepped seating sloping down to the arena
	var steps := 6
	for s in steps:
		var t0 := float(s) / steps
		var t1 := float(s + 1) / steps
		var rx0 := lerpf(70.0, 44.0, t0)
		var rz0 := lerpf(54.0, 28.0, t0)
		var rx1 := lerpf(70.0, 44.0, t1)
		var rz1 := lerpf(54.0, 28.0, t1)
		var y0 := lerpf(32.0, 5.0, t0)
		var y1 := lerpf(32.0, 5.0, t1)
		for k2 in 48:
			var a0 := TAU * k2 / 48.0
			var a1 := TAU * (k2 + 1) / 48.0
			var p0 := Vector3(cos(a0) * rx0, y0, sin(a0) * rz0)
			var p1 := Vector3(cos(a1) * rx0, y0, sin(a1) * rz0)
			var p2 := Vector3(cos(a1) * rx1, y1, sin(a1) * rz1)
			var p3 := Vector3(cos(a0) * rx1, y1, sin(a0) * rz1)
			var inward := -Vector3(p0.x, 0, p0.z).normalized() + Vector3(0, 1.2, 0)
			K.quad(mb, p0, p1, p2, p3, inward, tr if s % 2 == 0 else band)
	mb.add_box(Vector3(0, 1.5, 0), Vector3(84, 2, 52), _c(Color(0.55, 0.46, 0.36), K.STONE))
	for k3 in 7:
		_fine.add_box(Vector3(-36 + k3 * 12.0, 2.8, 0), Vector3(1.5, 1.2, 46.0), band)
	mb.add_box(Vector3(0, 3.2, 10), Vector3(84, 0.6, 30), _c(Color(0.78, 0.68, 0.5), K.STONE))
	boxes.append([Vector3(0, 24, 0), Vector3(94, 24, 78)])


func _dome_church(mb: MeshBuilder, boxes: Array) -> void:
	## St Peter's (Hagia Sophia shares it): nave and facade, the drum with paired columns and
	## windows, the ribbed lead dome and its lantern.
	var hagia := _id == "hagia"
	var st := _c(Color(0.86, 0.81, 0.7) if not hagia else Color(0.82, 0.62, 0.52), K.STONE)
	var stw := _c(Color(0.86, 0.81, 0.7) if not hagia else Color(0.82, 0.62, 0.52), K.PUNCHED)
	var lead := _c(Color(0.55, 0.6, 0.63) if not hagia else Color(0.5, 0.55, 0.58), K.METAL)
	var dark := _c(Color(0.1, 0.1, 0.12), K.DARK_GLASS)
	K.prism(mb, K.rect(30.0, 75.0, 0.0, 70.0), 0.0, 44.0, stw)
	K.loft2(mb, K.rect(30.0, 75.0, 0.0, 70.0), 44.0, K.rect(1.0, 75.0, 0.0, 70.0), 56.0, lead)
	K.prism(mb, K.rect(57.5, 6.0, 0.0, 140.0), 0.0, 50.0, stw)
	for k in 8:
		mb.add_cylinder(Vector3(-26.0 + k * 7.4, 0, 147.0), Vector3(-26.0 + k * 7.4, 42.0, 147.0), 1.4, 1.2, 10, st)
	K.loft2(mb, K.rect(28.0, 3.0, 0.0, 146.0), 42.0, K.rect(27.0, 0.5, 0.0, 146.0), 52.0, st)
	K.prism(mb, K.rect(70.0, 30.0, 0.0, -20.0), 0.0, 44.0, stw)
	mb.add_cylinder(Vector3(0, 44, -20), Vector3(0, 48, -20), 28.0, 27.0, 32, st)
	mb.add_cylinder(Vector3(0, 48, -20), Vector3(0, 76, -20), 25.0, 24.0, 32, st)
	for k2 in 16:
		var a := TAU * k2 / 16.0
		var cp := Vector3(cos(a) * 25.6, 0, -20.0 + sin(a) * 25.6)
		mb.add_cylinder(cp + Vector3(0, 48, 0), cp + Vector3(0, 74, 0), 1.0, 0.9, 6, st)
		var wa := a + TAU / 32.0
		mb.add_box_xf(Transform3D(Basis(Vector3.UP, -wa + PI * 0.5), Vector3(cos(wa) * 24.6, 62.0, -20.0 + sin(wa) * 24.6)), Vector3(3.2, 8.0, 0.4), dark)
	mb.add_cylinder(Vector3(0, 76, -20), Vector3(0, 79, -20), 26.0, 24.0, 32, st)
	mb.add_sphere(Vector3(0, 79, -20), Vector3(23, 34 if not hagia else 18, 23), 32, 10, lead)
	for k3 in 16:
		var a3 := TAU * k3 / 16.0
		var prev := Vector3.ZERO
		for j in 7:
			var ph := float(j) / 6.0 * PI * 0.46
			var p := Vector3(cos(a3) * 23.3 * cos(ph), 79.0 + (34.3 if not hagia else 18.3) * sin(ph), -20.0 + sin(a3) * 23.3 * cos(ph))
			if j > 0:
				_fine.add_cylinder(prev, p, 0.5, 0.5, 4, st, false)
			prev = p
	if not hagia:
		mb.add_cylinder(Vector3(0, 111, -20), Vector3(0, 126, -20), 5.0, 4.2, 12, st)
		mb.add_sphere(Vector3(0, 126, -20), Vector3(4.2, 3.0, 4.2), 10, 5, lead)
		mb.add_cone(Vector3(0, 128, -20), Vector3(0, 134, -20), 1.4, 8, lead)
		mb.add_sphere(Vector3(0, 134.5, -20), Vector3(1.0, 1.0, 1.0), 8, 5, _c(Color(0.9, 0.75, 0.35), K.METAL))
		for sx in [-1.0, 1.0]:
			mb.add_cylinder(Vector3(sx * 42.0, 44, -20), Vector3(sx * 42.0, 60, -20), 7.0, 6.5, 12, st)
			mb.add_sphere(Vector3(sx * 42.0, 60, -20), Vector3(6.5, 9.0, 6.5), 12, 6, lead)
	else:
		mb.add_cylinder(Vector3(0, 96, -20), Vector3(0, 100, -20), 0.6, 0.3, 6, _c(Color(0.9, 0.75, 0.35), K.METAL))
		for mx in [-1.0, 1.0]:
			for mz in [-1.0, 1.0]:
				var mp := Vector3(mx * 62.0, 0, -20.0 + mz * 50.0)
				mb.add_cylinder(mp, mp + Vector3(0, 55, 0), 2.4, 2.0, 10, st)
				mb.add_cylinder(mp + Vector3(0, 40, 0), mp + Vector3(0, 41.5, 0), 3.2, 3.2, 10, st)
				mb.add_cone(mp + Vector3(0, 55, 0), mp + Vector3(0, 66, 0), 2.1, 10, lead)
	boxes.append([Vector3(0, 25, 50), Vector3(60, 25, 95)])
	boxes.append([Vector3(0, 80, -20), Vector3(25, 56, 25)])


# ================================================================== Amsterdam, Reykjavik
func _windmills(mb: MeshBuilder, boxes: Array) -> void:
	for k in 5:
		var o := Vector3((k - 2) * 230.0, 0, sin(k * 1.7) * 120.0)
		var body := _c(Color(0.25, 0.32, 0.26) if k % 2 == 0 else Color(0.45, 0.33, 0.24), K.STONE)
		K.prism(mb, K.ngon(8, 7.8, 0.0, o.x, o.z), 0.0, 6.0, _c(Color(0.55, 0.3, 0.22), K.PUNCHED))
		K.prism(mb, K.ngon(8, 7.0, 0.0, o.x, o.z), 6.0, 22.0, body, 0.62)
		_fine.add_cylinder(o + Vector3(0, 6.5, 0), o + Vector3(0, 7.0, 0), 9.0, 9.0, 12, _c(Color(0.35, 0.25, 0.18), K.STONE))
		mb.add_cone(o + Vector3(0, 22, 0), o + Vector3(0, 28, 0), 5.2, 8, _c(Color(0.2, 0.2, 0.22), K.STONE))
		var hub := o + Vector3(0, 23, -5.5)
		mb.add_cylinder(o + Vector3(0, 23, -3.0), hub, 0.6, 0.5, 6, _c(Color(0.3, 0.22, 0.16), K.STONE))
		for s in 4:
			var a := s * PI * 0.5 + PI * 0.25 + k * 0.4
			var tip := hub + Vector3(cos(a), sin(a), 0) * 13.0
			mb.add_cylinder(hub, tip, 0.35, 0.3, 4, _c(Color(0.35, 0.25, 0.18), K.STONE), false)
			mb.add_box_xf(Transform3D(Basis(Vector3.FORWARD, a), hub.lerp(tip, 0.6) + Vector3(0, 0, -0.4)), Vector3(8.0, 2.2, 0.3), _c(Color(0.92, 0.9, 0.84), K.STONE))
		boxes.append([o + Vector3(0, 14, 0), Vector3(8, 14, 8)])


func _church_tower(mb: MeshBuilder, boxes: Array) -> void:
	## Hallgrimskirkja: the stepped basalt-column wings rising to the central tower.
	var c := _c(Color(0.86, 0.86, 0.84), K.STONE)
	var dark := _c(Color(0.1, 0.1, 0.12), K.DARK_GLASS)
	K.prism(mb, K.rect(5.0, 7.0), 0.0, 68.0, c)
	K.loft2(mb, K.rect(5.0, 7.0), 68.0, K.rect(0.4, 0.4), 76.0, c)
	_fine.add_cylinder(Vector3(0, 76, 0), Vector3(0, 78.5, 0), 0.15, 0.1, 4, c)
	for side in [-1.0, 1.0]:
		mb.add_box(Vector3(side * 5.05, 58.0, 0), Vector3(0.2, 5.0, 3.0), dark)
	mb.add_box(Vector3(0, 58.0, -7.05), Vector3(3.0, 5.0, 0.2), dark)
	for k in 9:
		var h := 54.0 - k * 5.4
		for sx in [-1.0, 1.0]:
			K.prism(mb, K.rect(1.25, 5.0, sx * (6.2 + k * 2.5), 2.0), 0.0, h, c, 1.0, true)
			_fine.add_box(Vector3(sx * (6.2 + k * 2.5), h * 0.5, -3.05), Vector3(0.5, h * 0.95, 0.15), _c(Color(0.75, 0.75, 0.73), K.STONE))
	mb.add_box(Vector3(0, 12, 30), Vector3(26, 24, 46), _c(Color(0.86, 0.86, 0.84), K.PUNCHED))
	K.loft2(mb, K.rect(13.0, 23.0, 0.0, 30.0), 24.0, K.rect(1.0, 23.0, 0.0, 30.0), 34.0, _c(Color(0.3, 0.32, 0.34), K.METAL))
	boxes.append([Vector3(0, 36, 6), Vector3(26, 36, 30)])


# ================================================================== second-wave landmarks
func _space_needle(mb: MeshBuilder, boxes: Array) -> void:
	## Seattle: three pairs of curved legs pinched at the waist, the halo top house with its
	## glass restaurant ring, the spire.
	var white := _c(Color(0.92, 0.92, 0.9), K.METAL)
	var orange := _c(Color(0.9, 0.55, 0.18), K.METAL)
	var glass := _c(Color(0.36, 0.44, 0.52), K.RIBBON)
	for k in 3:
		var a := TAU * k / 3.0
		for off in [-0.16, 0.16]:
			var aa: float = a + off
			var pts := []
			for j in 9:
				var t := float(j) / 8.0
				var rad := lerpf(19.0, 4.0, sin(t * PI * 0.5)) if t < 0.72 else lerpf(5.0, 9.5, (t - 0.72) / 0.28)
				pts.append(Vector3(cos(aa) * rad, t * 158.0, sin(aa) * rad))
			for j2 in 8:
				mb.add_cylinder(pts[j2], pts[j2 + 1], 1.1, 1.0, 6, white, false)
		for j3 in 5:
			var y := 25.0 + j3 * 26.0
			var rad2 := lerpf(19.0, 4.0, sin(y / 158.0 * PI * 0.5))
			_fine.add_cylinder(Vector3(cos(a - 0.16) * rad2, y, sin(a - 0.16) * rad2), Vector3(cos(a + 0.16) * rad2, y, sin(a + 0.16) * rad2), 0.4, 0.4, 4, white, false)
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 160, 0), 3.0, 3.0, 10, _c(Color(0.78, 0.78, 0.76), K.STONE))
	mb.add_cylinder(Vector3(0, 100, 0), Vector3(0, 102, 0), 8.5, 8.5, 16, white)
	mb.add_cylinder(Vector3(0, 152, 0), Vector3(0, 156, 0), 5.0, 14.0, 24, white)
	mb.add_cylinder(Vector3(0, 156, 0), Vector3(0, 163, 0), 14.0, 17.0, 32, glass)
	mb.add_cylinder(Vector3(0, 163, 0), Vector3(0, 165, 0), 21.0, 21.0, 32, orange)
	mb.add_cylinder(Vector3(0, 165, 0), Vector3(0, 169, 0), 17.0, 15.0, 32, glass)
	mb.add_cylinder(Vector3(0, 169, 0), Vector3(0, 173, 0), 15.0, 6.0, 24, white)
	mb.add_cylinder(Vector3(0, 173, 0), Vector3(0, 184, 0), 1.2, 0.3, 6, white)
	_aviation_light(Vector3(0, 184.5, 0), 0.6)
	boxes.append([Vector3(0, 80, 0), Vector3(12, 80, 12)])
	boxes.append([Vector3(0, 165, 0), Vector3(21, 10, 21)])


func _tv_tower(mb: MeshBuilder, boxes: Array) -> void:
	## Broadcast towers: Berlin's Fernsehturm by default, with variants for the Tokyo Skytree,
	## Shanghai's Oriental Pearl, N Seoul Tower and the Strat in Las Vegas.
	var conc := _c(Color(0.84, 0.83, 0.8), K.STONE)
	var steel := _c(Color(0.62, 0.66, 0.72), K.METAL)
	var glass := _c(Color(0.32, 0.38, 0.46), K.RIBBON)
	var red := _c(Color(0.88, 0.15, 0.12), K.METAL)
	var white := _c(Color(0.95, 0.95, 0.95), K.METAL)
	match _id:
		"skytree":
			# triangular lattice base morphing to round, two observation decks, 634 m
			var lat := _c(Color(0.86, 0.9, 0.95), K.METAL)
			var lv := [0.0, 40.0, 80.0, 125.0, 170.0, 215.0, 260.0, 305.0, 340.0]
			var prev := []
			for yv in lv:
				var y: float = yv
				var rr := lerpf(34.0, 13.0, y / 340.0)
				var ring := []
				for k in 6:
					var a := TAU * k / 6.0 + (0.0 if k % 2 == 0 else -0.25 * (1.0 - y / 340.0))
					ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
				if not prev.is_empty():
					for k2 in 6:
						K.bar(mb, prev[k2], ring[k2], 1.4, lat)
						K.bar(mb, prev[k2], ring[(k2 + 1) % 6], 0.6, lat, 3)
						K.bar(mb, prev[(k2 + 1) % 6], ring[k2], 0.6, lat, 3)
				prev = ring
			mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 495, 0), 8.0, 5.0, 12, _c(Color(0.8, 0.82, 0.85), K.STONE))
			mb.add_cylinder(Vector3(0, 340, 0), Vector3(0, 345, 0), 13.0, 19.0, 24, steel)
			mb.add_cylinder(Vector3(0, 345, 0), Vector3(0, 358, 0), 19.0, 18.0, 24, glass)
			mb.add_cylinder(Vector3(0, 358, 0), Vector3(0, 362, 0), 18.0, 10.0, 24, steel)
			mb.add_cylinder(Vector3(0, 362, 0), Vector3(0, 440, 0), 10.0, 9.0, 12, _c(Color(0.86, 0.9, 0.95), K.METAL))
			mb.add_cylinder(Vector3(0, 440, 0), Vector3(0, 452, 0), 13.5, 13.0, 24, glass)
			mb.add_cylinder(Vector3(0, 452, 0), Vector3(0, 456, 0), 13.0, 7.0, 24, steel)
			mb.add_cylinder(Vector3(0, 456, 0), Vector3(0, 634, 0), 5.0, 1.2, 10, white)
			_aviation_light(Vector3(0, 634.5, 0), 1.2)
			boxes.append([Vector3(0, 170, 0), Vector3(30, 170, 30)])
			boxes.append([Vector3(0, 490, 0), Vector3(19, 145, 19)])
		"pearl":
			# three columns through the big lower sphere, the upper sphere and the space module
			var pink := _c(Color(0.86, 0.32, 0.48), K.METAL)
			for k in 3:
				var a := TAU * k / 3.0
				mb.add_cylinder(Vector3(cos(a) * 22.0, 0, sin(a) * 22.0), Vector3(cos(a) * 6.0, 95.0, sin(a) * 6.0), 4.0, 3.0, 8, conc)
				mb.add_cylinder(Vector3(cos(a) * 6.0, 0, sin(a) * 6.0), Vector3(cos(a) * 6.0, 330.0, sin(a) * 6.0), 4.5, 3.5, 10, conc)
			mb.add_sphere(Vector3(0, 95, 0), Vector3(25, 25, 25), 24, 14, pink)
			mb.add_sphere(Vector3(0, 263, 0), Vector3(22.5, 22.5, 22.5), 24, 14, pink)
			mb.add_cylinder(Vector3(0, 93, 0), Vector3(0, 97, 0), 25.5, 25.5, 24, glass)
			mb.add_cylinder(Vector3(0, 261, 0), Vector3(0, 265, 0), 23.0, 23.0, 24, glass)
			for k2 in 5:
				var y2 := 140.0 + k2 * 22.0
				mb.add_sphere(Vector3(0, y2, 0), Vector3(7.5, 7.5, 7.5), 12, 8, pink)
			mb.add_cylinder(Vector3(0, 330, 0), Vector3(0, 345, 0), 4.0, 4.0, 10, conc)
			mb.add_sphere(Vector3(0, 350, 0), Vector3(8, 8, 8), 14, 10, pink)
			mb.add_cylinder(Vector3(0, 358, 0), Vector3(0, 468, 0), 2.6, 0.6, 8, white)
			_aviation_light(Vector3(0, 468.5, 0))
			boxes.append([Vector3(0, 150, 0), Vector3(25, 150, 25)])
			boxes.append([Vector3(0, 400, 0), Vector3(8, 70, 8)])
		"strat":
			# three-legged concrete shaft and the multi-level pod with the ride mast
			K.prism(mb, K.ngon(6, 8.0), 0.0, 260.0, conc, 0.7)
			for k in 3:
				var a := TAU * k / 3.0 + PI * 0.5
				K.loft2(mb, K.wing_plan(a, 24.0, 6.0, 2), 0.0, K.wing_plan(a, 6.0, 4.0, 2), 250.0, conc)
			mb.add_cylinder(Vector3(0, 255, 0), Vector3(0, 262, 0), 8.0, 20.0, 24, conc)
			for k2 in 4:
				var y3 := 262.0 + k2 * 6.5
				mb.add_cylinder(Vector3(0, y3, 0), Vector3(0, y3 + 4.5, 0), 20.0 - k2 * 1.5, 20.5 - k2 * 1.5, 24, glass)
				mb.add_cylinder(Vector3(0, y3 + 4.5, 0), Vector3(0, y3 + 6.5, 0), 21.0 - k2 * 1.5, 19.5 - k2 * 1.5, 24, conc)
			mb.add_cylinder(Vector3(0, 288, 0), Vector3(0, 350, 0), 3.5, 1.2, 8, white)
			_aviation_light(Vector3(0, 350.5, 0))
			boxes.append([Vector3(0, 140, 0), Vector3(20, 140, 20)])
			boxes.append([Vector3(0, 300, 0), Vector3(20, 50, 20)])
		"ntower":
			K.prism(mb, K.ngon(8, 8.0), 0.0, 140.0, conc, 0.8)
			mb.add_cylinder(Vector3(0, 140, 0), Vector3(0, 146, 0), 6.4, 15.0, 24, conc)
			mb.add_cylinder(Vector3(0, 146, 0), Vector3(0, 160, 0), 15.0, 15.5, 24, glass)
			mb.add_cylinder(Vector3(0, 160, 0), Vector3(0, 164, 0), 15.5, 8.0, 24, conc)
			mb.add_cylinder(Vector3(0, 164, 0), Vector3(0, 236, 0), 3.0, 0.8, 8, white)
			for k in 3:
				mb.add_cylinder(Vector3(0, 180 + k * 18.0, 0), Vector3(0, 188 + k * 18.0, 0), 2.6 - k * 0.5, 2.4 - k * 0.5, 8, red)
			_aviation_light(Vector3(0, 236.5, 0))
			boxes.append([Vector3(0, 80, 0), Vector3(8, 80, 8)])
			boxes.append([Vector3(0, 190, 0), Vector3(15, 46, 15)])
		_:
			# Berlin: tapering shaft, the steel sphere with its window band, red-and-white mast
			K.prism(mb, K.ngon(12, 9.0), 0.0, 200.0, conc, 0.6)
			mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 6, 0), 26.0, 24.0, 12, _c(Color(0.7, 0.7, 0.68), K.PUNCHED))
			mb.add_sphere(Vector3(0, 212, 0), Vector3(16, 16, 16), 24, 14, steel)
			mb.add_cylinder(Vector3(0, 205, 0), Vector3(0, 211, 0), 15.6, 16.2, 24, glass)
			mb.add_cylinder(Vector3(0, 211, 0), Vector3(0, 213, 0), 16.2, 16.2, 24, _c(Color(0.5, 0.52, 0.56), K.METAL))
			mb.add_cylinder(Vector3(0, 226, 0), Vector3(0, 300, 0), 3.0, 2.0, 10, white)
			for k in 4:
				mb.add_cylinder(Vector3(0, 300 + k * 16.0, 0), Vector3(0, 308 + k * 16.0, 0), 1.9 - k * 0.3, 1.8 - k * 0.3, 8, red)
				mb.add_cylinder(Vector3(0, 308 + k * 16.0, 0), Vector3(0, 316 + k * 16.0, 0), 1.8 - k * 0.3, 1.6 - k * 0.3, 8, white)
			_aviation_light(Vector3(0, 365, 0))
			_aviation_light(Vector3(0, 228, 3.2), 0.6)
			boxes.append([Vector3(0, 110, 0), Vector3(9, 110, 9)])
			boxes.append([Vector3(0, 212, 0), Vector3(16, 16, 16)])
			boxes.append([Vector3(0, 300, 0), Vector3(3, 70, 3)])


func _reunion(mb: MeshBuilder, boxes: Array) -> void:
	## Dallas: four concrete shafts carrying the geodesic ball of lights.
	var conc := _c(Color(0.8, 0.79, 0.76), K.STONE)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var p := Vector3(cos(a) * 4.5, 0, sin(a) * 4.5)
		mb.add_cylinder(p, p + Vector3(0, 150, 0), 2.6, 2.6, 10, conc)
	mb.add_cylinder(Vector3(0, 146, 0), Vector3(0, 150, 0), 12.0, 14.0, 20, conc)
	mb.add_cylinder(Vector3(0, 150, 0), Vector3(0, 156, 0), 14.0, 15.5, 24, _c(Color(0.3, 0.36, 0.42), K.RIBBON))
	mb.add_sphere(Vector3(0, 162, 0), Vector3(18, 16, 18), 24, 12, _c(Color(0.88, 0.88, 0.84), K.METAL))
	# the ball's lights
	for i in 6:
		var ph := -0.2 + i * 0.28
		for j in 16:
			var th := TAU * j / 16.0 + i * 0.2
			var d := Vector3(cos(ph) * cos(th), sin(ph), cos(ph) * sin(th))
			_fine.add_sphere(Vector3(0, 162, 0) + d * Vector3(18.2, 16.2, 18.2), Vector3.ONE * 0.6, 4, 3, _c(Color(1.0, 0.95, 0.85), K.LAMP))
	boxes.append([Vector3(0, 85, 0), Vector3(18, 85, 18)])


func _brandenburg(mb: MeshBuilder, boxes: Array) -> void:
	## Berlin: twelve Doric columns, the attic and the quadriga on top.
	var sand := _c(Color(0.84, 0.78, 0.64), K.STONE)
	var bronze := _c(Color(0.3, 0.44, 0.36), K.METAL)
	K.prism(mb, K.rect(33.0, 7.5), 0.0, 1.2, sand)
	for k in 6:
		var x := -26.0 + k * 10.4
		for zz in [-4.5, 4.5]:
			mb.add_cylinder(Vector3(x, 1.2, zz), Vector3(x, 15, zz), 0.95, 0.85, 12, sand)
			mb.add_box(Vector3(x, 15.2, zz), Vector3(2.2, 0.4, 2.2), sand)
		if k < 5:
			mb.add_box(Vector3(x + 5.2, 7.5, 0), Vector3(1.6, 13.0, 7.6), sand)
	mb.add_box(Vector3(0, 17.5, 0), Vector3(62, 4.4, 12), sand)
	mb.add_box(Vector3(0, 19.9, 0), Vector3(63, 0.6, 12.6), sand)
	mb.add_box(Vector3(0, 21.5, 0), Vector3(40, 3, 10), sand)
	K.loft2(mb, K.rect(20.0, 5.0), 23.0, K.rect(14.0, 3.5), 24.5, sand)
	# quadriga: chariot, goddess and four horses
	mb.add_box(Vector3(0, 26.0, 0), Vector3(2.4, 3.0, 2.0), bronze)
	mb.add_cylinder(Vector3(0, 27.5, 0), Vector3(0, 30.5, 0), 0.6, 0.4, 6, bronze)
	for hk in 4:
		var hx := -2.7 + hk * 1.8
		mb.add_box(Vector3(hx, 26.3, -2.6), Vector3(0.9, 1.5, 3.0), bronze)
		mb.add_box(Vector3(hx, 27.4, -4.1), Vector3(0.6, 1.5, 0.8), bronze)
	for sx in [-1.0, 1.0]:
		mb.add_box(Vector3(sx * 40.0, 7.0, 0), Vector3(14, 14, 10), _c(Color(0.84, 0.78, 0.64), K.PUNCHED))
		for k2 in 4:
			mb.add_cylinder(Vector3(sx * (34.5 + k2 * 3.6), 0, 5.5), Vector3(sx * (34.5 + k2 * 3.6), 12, 5.5), 0.6, 0.55, 8, sand)
	boxes.append([Vector3(0, 12, 0), Vector3(48, 13, 7)])


func _sagrada(mb: MeshBuilder, boxes: Array) -> void:
	## Barcelona: the forest of tapering, perforated spires over the nave.
	var stone := _c(Color(0.72, 0.66, 0.55), K.STONE)
	var stonew := _c(Color(0.72, 0.66, 0.55), K.PUNCHED)
	var gold := _c(Color(0.92, 0.76, 0.3), K.METAL)
	var dark := _c(Color(0.1, 0.09, 0.08), K.DARK_GLASS)
	K.prism(mb, K.rect(30.0, 45.0), 0.0, 44.0, stonew)
	K.loft2(mb, K.rect(30.0, 45.0), 44.0, K.rect(3.0, 45.0), 58.0, stone)
	var spires := [[Vector3(-14, 0, -45), 98.0], [Vector3(-5, 0, -45), 107.0], [Vector3(5, 0, -45), 107.0], [Vector3(14, 0, -45), 98.0],
		[Vector3(-14, 0, 45), 100.0], [Vector3(-5, 0, 45), 112.0], [Vector3(5, 0, 45), 112.0], [Vector3(14, 0, 45), 100.0],
		[Vector3(0, 0, 0), 172.0], [Vector3(-16, 0, -5), 135.0], [Vector3(16, 0, -5), 135.0], [Vector3(0, 0, 18), 138.0], [Vector3(0, 0, -22), 138.0]]
	for sp in spires:
		var b: Vector3 = sp[0]
		var h: float = sp[1]
		var r0 := 4.8 if h > 150.0 else 3.4
		mb.add_cylinder(b, b + Vector3(0, h * 0.55, 0), r0, r0 * 0.85, 12, stone)
		mb.add_cylinder(b + Vector3(0, h * 0.55, 0), b + Vector3(0, h * 0.82, 0), r0 * 0.85, r0 * 0.5, 12, stone)
		for k in 4:
			var y := h * (0.3 + k * 0.13)
			_fine.add_cylinder(b + Vector3(0, y, 0), b + Vector3(0, y + 2.0, 0), r0 * (0.93 - k * 0.1), r0 * (0.93 - k * 0.1), 12, dark, false)
		mb.add_cone(b + Vector3(0, h * 0.82, 0), b + Vector3(0, h * 0.97, 0), r0 * 0.5, 8, stone.lightened(0.08))
		mb.add_sphere(b + Vector3(0, h * 0.98, 0), Vector3(1.6, 1.8, 1.6), 8, 5, gold)
	mb.add_sphere(Vector3(0, 172.0 * 0.98 + 3.0, 0), Vector3(2.6, 2.6, 2.6), 10, 6, _c(Color(1, 0.95, 0.8), K.LAMP))
	boxes.append([Vector3(0, 60, 0), Vector3(32, 60, 48)])
	boxes.append([Vector3(0, 140, 0), Vector3(6, 32, 6)])


func _atomium(mb: MeshBuilder, boxes: Array) -> void:
	## Brussels: nine steel spheres on the corners and centre of a giant iron crystal.
	var steel := _c(Color(0.86, 0.88, 0.91), K.METAL)
	var win := _c(Color(0.95, 0.95, 1.0), K.LAMP)
	var c := Vector3(0, 52, 0)
	var corners := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(c + Basis.from_euler(Vector3(0.62, 0, 0.78)) * Vector3(sx, sy, sz) * 24.0)
	for i in corners.size():
		var p: Vector3 = corners[i]
		mb.add_cylinder(c, p, 1.6, 1.6, 10, steel)
		for j in range(i + 1, corners.size()):
			var q: Vector3 = corners[j]
			if absf(p.distance_to(q) - 48.0) < 1.0:
				mb.add_cylinder(p, q, 1.5, 1.5, 10, steel)
		mb.add_sphere(p, Vector3(9, 9, 9), 18, 12, steel)
		mb.add_cylinder(p + Vector3(0, -0.6, 0), p + Vector3(0, 0.6, 0), 9.05, 9.05, 18, win, false)
	mb.add_sphere(c, Vector3(9, 9, 9), 18, 12, steel)
	mb.add_cylinder(Vector3(0, 0, 0), c, 2.2, 2.2, 10, steel)
	for k in 3:
		var a := TAU * k / 3.0
		mb.add_cylinder(Vector3(cos(a) * 14.0, 0, sin(a) * 14.0), corners[k * 2] as Vector3, 1.2, 1.2, 8, steel)
	boxes.append([c, Vector3(34, 46, 34)])


func _castle(mb: MeshBuilder, boxes: Array) -> void:
	## A castle on its rock (Edinburgh), or the fairytale castle at the theme parks.
	var fairy := _id == "castle"
	var rock := _c(Color(0.38, 0.36, 0.33), K.STONE)
	var wall := _c(Color(0.62, 0.6, 0.56) if not fairy else Color(0.9, 0.88, 0.84), K.PUNCHED)
	var wall_p := _c(Color(0.62, 0.6, 0.56) if not fairy else Color(0.9, 0.88, 0.84), K.STONE)
	var roof := _c(Color(0.25, 0.32, 0.5) if fairy else Color(0.28, 0.3, 0.33), K.METAL)
	var gold := _c(Color(0.9, 0.75, 0.35), K.METAL)
	mb.add_rounded_box(Vector3(0, 20, 0), Vector3(180, 40, 110), rock, 0.5, 14, 8)
	K.prism(mb, K.rect(60.0, 30.0), 38.0, 64.0, wall)
	for k in 30:
		var t := float(k) / 30.0
		var px := lerpf(-60.0, 60.0, t)
		_fine.add_box(Vector3(px, 65.0, 30.0), Vector3(2.0, 2.0, 1.0), wall_p)
		_fine.add_box(Vector3(px, 65.0, -30.0), Vector3(2.0, 2.0, 1.0), wall_p)
	for k2 in 4:
		var p := Vector3((k2 % 2) * 120.0 - 60.0, 38, (k2 / 2) * 60.0 - 30.0)
		K.prism(mb, K.ngon(12, 7.0, 0.0, p.x, p.z), 38.0, 84.0, wall)
		mb.add_cone(p + Vector3(0, 46, 0), p + Vector3(0, 64, 0), 8.0, 12, roof)
		mb.add_cone(p + Vector3(0, 63, 0), p + Vector3(0, 67, 0), 0.6, 6, gold)
	K.prism(mb, K.ngon(12, 9.0), 60.0, 100.0, wall)
	mb.add_cone(Vector3(0, 100, 0), Vector3(0, 126, 0), 10.5, 12, roof)
	mb.add_cone(Vector3(0, 125, 0), Vector3(0, 130, 0), 0.8, 6, gold)
	if fairy:
		for k3 in 6:
			var a := TAU * k3 / 6.0
			var tp := Vector3(cos(a) * 22.0, 0, sin(a) * 14.0)
			K.prism(mb, K.ngon(10, 4.0, 0.0, tp.x, tp.z), 50.0, 82.0 + (k3 % 3) * 6.0, wall)
			mb.add_cone(tp + Vector3(0, 82.0 + (k3 % 3) * 6.0, 0), tp + Vector3(0, 96.0 + (k3 % 3) * 6.0, 0), 4.8, 10, roof)
	boxes.append([Vector3(0, 45, 0), Vector3(90, 45, 55)])
	boxes.append([Vector3(0, 90, 0), Vector3(10, 32, 10)])


func _twin_church(mb: MeshBuilder, boxes: Array) -> void:
	## Munich's Frauenkirche: a brick hall with twin towers under green onion domes.
	var brick := _c(Color(0.6, 0.36, 0.28), K.STONE)
	var brickw := _c(Color(0.6, 0.36, 0.28), K.PUNCHED)
	var copper := _c(Color(0.3, 0.55, 0.42), K.METAL)
	K.prism(mb, K.rect(20.0, 45.0, 0.0, 25.0), 0.0, 38.0, brickw)
	K.loft2(mb, K.rect(20.0, 45.0, 0.0, 25.0), 38.0, K.rect(1.0, 45.0, 0.0, 25.0), 62.0, _c(Color(0.45, 0.25, 0.2), K.STONE))
	for sx in [-1.0, 1.0]:
		var b := Vector3(sx * 11.0, 0, -28)
		K.prism(mb, K.rect(8.0, 8.0, b.x, b.z), 0.0, 72.0, brick)
		K.prism(mb, K.chamfer_rect(7.6, 7.6, 2.4), 72.0, 99.0, brickw)
		mb.add_sphere(b + Vector3(0, 106, 0), Vector3(8.0, 9.0, 8.0), 16, 10, copper)
		mb.add_cylinder(b + Vector3(0, 99, 0), b + Vector3(0, 102, 0), 7.2, 7.8, 16, copper)
		mb.add_cylinder(b + Vector3(0, 114, 0), b + Vector3(0, 116, 0), 2.4, 1.6, 10, copper)
		mb.add_cone(b + Vector3(0, 116, 0), b + Vector3(0, 120, 0), 1.2, 8, _c(Color(0.85, 0.7, 0.3), K.METAL))
	boxes.append([Vector3(0, 55, -28), Vector3(20, 60, 9)])
	boxes.append([Vector3(0, 20, 25), Vector3(20, 20, 45)])


# ================================================================== Asia and the Middle East
func _burj(mb: MeshBuilder, boxes: Array) -> void:
	## The Burj Khalifa: a Y-plan of three wings around a hexagonal core, stepping back in a
	## spiral through 27 terraces, then the pinnacle and the spire (828 m).
	var glass := _c(Color(0.74, 0.8, 0.86), K.CURTAIN)
	var steel := _c(Color(0.84, 0.86, 0.9), K.METAL)
	var plaza := _c(Color(0.78, 0.74, 0.66), K.STONE)
	var water := _c(Color(0.18, 0.32, 0.4), K.METAL)
	mb.add_cylinder(Vector3(0, -1, 0), Vector3(0, 0.4, 0), 120.0, 120.0, 40, plaza)
	K.prism(mb, K.xform_poly(K.stadium(150.0, 55.0, 10), 0.0, Vector2(0.0, 175.0)), -0.6, 0.6, water)
	var tiers := 27
	var top := 585.0
	for i in tiers:
		var y0 := top * float(i) / tiers
		var y1 := top * float(i + 1) / tiers
		var t := float(i) / tiers
		var rc := lerpf(23.0, 9.0, t)
		K.prism(mb, K.ngon(6, rc, PI / 6.0), y0, y1, glass)
		var wid := lerpf(32.0, 17.0, t)
		for k in 3:
			var a := PI * 0.5 + TAU * k / 3.0
			var steps := (i + (2 - k)) / 3
			var ln := 64.0 - 5.6 * float(steps)
			if ln > rc + 2.0:
				K.prism(mb, K.wing_plan(a, ln, wid, 6), y0, y1, glass)
				# silver fin running up the wing tip
				var tipd := Vector2(cos(a), sin(a)) * (ln - 0.3)
				mb.add_box_xf(Transform3D(Basis(Vector3.UP, -a), Vector3(tipd.x, (y0 + y1) * 0.5, tipd.y)), Vector3(2.2, y1 - y0, 1.2), steel)
	K.prism(mb, K.ngon(6, 9.0, PI / 6.0), top, 640.0, steel, 0.65)
	for k2 in 6:
		var a2 := TAU * k2 / 6.0
		_fine.add_cylinder(Vector3(cos(a2) * 8.5, top, sin(a2) * 8.5), Vector3(cos(a2) * 5.0, 640.0, sin(a2) * 5.0), 0.5, 0.4, 4, steel, false)
	mb.add_cylinder(Vector3(0, 640, 0), Vector3(0, 828, 0), 4.2, 0.5, 8, steel)
	for ry in [660.0, 700.0, 740.0]:
		mb.add_cylinder(Vector3(0, ry, 0), Vector3(0, ry + 1.5, 0), 4.4 - (ry - 640.0) * 0.019, 4.4 - (ry - 640.0) * 0.019, 8, steel)
	_aviation_light(Vector3(0, 828.5, 0), 1.2)
	_aviation_light(Vector3(0, 641.0, 6.2), 0.8)
	boxes.append([Vector3(0, 240, 0), Vector3(40, 240, 40)])
	boxes.append([Vector3(0, 700, 0), Vector3(10, 130, 10)])


func _petronas(mb: MeshBuilder, boxes: Array) -> void:
	## Twin stainless-steel towers on the eight-pointed star plan, setting back to round tiers
	## and pinnacles (452 m), each with its round annex, joined by the double-deck skybridge.
	var steel := _c(Color(0.8, 0.82, 0.86), K.RIBBON)
	var metal := _c(Color(0.86, 0.88, 0.9), K.METAL)
	var mall := _c(Color(0.55, 0.6, 0.66), K.CURTAIN)
	K.prism(mb, K.rect(110.0, 55.0, 0.0, 20.0), 0.0, 22.0, mall)
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 52.0
		var tiers := [[0.0, 240.0, 23.5], [240.0, 290.0, 21.0], [290.0, 322.0, 18.5], [322.0, 345.0, 15.5]]
		for t in tiers:
			var y0: float = t[0]
			var y1: float = t[1]
			var r: float = t[2]
			K.prism(mb, K.xform_poly(K.petronas_plan(r, 64), 0.0, Vector2(cx, 0.0)), y0, y1, steel)
		mb.add_cylinder(Vector3(cx, 345, 0), Vector3(cx, 362, 0), 12.0, 10.5, 24, steel)
		mb.add_cylinder(Vector3(cx, 362, 0), Vector3(cx, 375, 0), 10.0, 7.5, 24, steel)
		for k in 4:
			var y2 := 375.0 + k * 4.0
			mb.add_cylinder(Vector3(cx, y2, 0), Vector3(cx, y2 + 2.6, 0), 6.5 - k * 1.2, 5.8 - k * 1.2, 16, metal)
			mb.add_cylinder(Vector3(cx, y2 + 2.6, 0), Vector3(cx, y2 + 4.0, 0), 5.8 - k * 1.2, 5.6 - k * 1.2, 16, metal)
		mb.add_cylinder(Vector3(cx, 391, 0), Vector3(cx, 452, 0), 2.2, 0.35, 10, metal)
		for k2 in 5:
			mb.add_sphere(Vector3(cx, 398.0 + k2 * 9.0, 0), Vector3.ONE * (1.9 - k2 * 0.25), 8, 6, metal)
		_aviation_light(Vector3(cx, 452.5, 0), 0.8)
		# round annex ("bustle") on the outer side
		mb.add_cylinder(Vector3(cx + sx * 26.0, 0, 18.0), Vector3(cx + sx * 26.0, 188.0, 18.0), 12.0, 12.0, 20, steel)
		mb.add_cylinder(Vector3(cx + sx * 26.0, 188.0, 18.0), Vector3(cx + sx * 26.0, 194.0, 18.0), 12.0, 9.0, 20, metal)
		boxes.append([Vector3(cx, 200, 0), Vector3(24, 200, 24)])
	# skybridge at floors 41-42 with its inverted-V support legs
	mb.add_box(Vector3(0, 172, 0), Vector3(62, 9, 6), _c(Color(0.5, 0.55, 0.6), K.RIBBON))
	mb.add_box(Vector3(0, 177, 0), Vector3(62, 1.0, 6.6), metal)
	for sx2 in [-1.0, 1.0]:
		mb.add_cylinder(Vector3(0, 167.5, 0), Vector3(sx2 * 30.0, 120.0, 0), 1.2, 1.2, 8, metal)
	boxes.append([Vector3(0, 172, 0), Vector3(31, 5, 4)])


func _mbs(mb: MeshBuilder, boxes: Array) -> void:
	## Marina Bay Sands: three 55-storey towers, each two leaning legs, carrying the ship-shaped
	## SkyPark with its pool and gardens; the podium and the lotus-shaped museum.
	var c := _c(Color(0.86, 0.87, 0.86), K.RIBBON)
	var cw := _c(Color(0.88, 0.88, 0.86), K.STONE)
	var green := _c(Color(0.3, 0.48, 0.3), K.STONE)
	var pool := _c(Color(0.25, 0.6, 0.75), K.METAL)
	K.prism(mb, K.rect(165.0, 55.0, 0.0, 75.0), 0.0, 18.0, _c(Color(0.6, 0.64, 0.68), K.CURTAIN))
	for k in 3:
		var x := (k - 1) * 72.0
		# west leg straight, east leg leaning in, joined near the top
		K.prism(mb, K.rect(9.0, 19.0, x - 10.0, 0.0), 0.0, 194.0, c)
		K.loft2(mb, K.rect(9.0, 19.0, x + 18.0, 0.0), 0.0, K.rect(9.0, 19.0, x + 8.0, 0.0), 194.0, c)
		mb.add_box(Vector3(x - 1.0, 120.0, 0), Vector3(1.0, 150.0, 30.0), _c(Color(0.5, 0.58, 0.66), K.CURTAIN))
		boxes.append([Vector3(x, 97, 0), Vector3(20, 97, 19)])
	# SkyPark: a 340 m hull cantilevered past the north tower
	var hull := K.stadium(170.0, 20.0, 8)
	K.prism(mb, K.xform_poly(hull, 0.0, Vector2(30.0, 0.0)), 194.0, 199.0, cw)
	K.loft2(mb, K.xform_poly(K.scale_poly(hull, 0.94), 0.0, Vector2(30.0, 0.0)), 189.0, K.xform_poly(hull, 0.0, Vector2(30.0, 0.0)), 194.0, cw, false, true)
	K.prism(mb, K.xform_poly(K.stadium(160.0, 17.0, 8), 0.0, Vector2(30.0, 0.0)), 199.0, 200.0, green)
	K.prism(mb, K.rect(70.0, 4.0, 120.0, -9.0), 200.0, 200.3, pool)
	for k2 in 24:
		_fine.add_sphere(Vector3(-110.0 + k2 * 9.0, 202.0, 9.0), Vector3(2.4, 2.6, 2.4), 6, 4, _c(Color(0.2, 0.42, 0.2), K.STONE))
	# ArtScience Museum (lotus)
	for k3 in 8:
		var a := -PI * 0.5 + (k3 - 3.5) * 0.3
		var base := Vector3(-120.0, 6.0, 120.0)
		mb.add_cone(base, base + Vector3(cos(a) * 30.0, 30.0 - absf(k3 - 3.5) * 3.0, sin(a) * 30.0), 6.0, 6, cw)
	boxes.append([Vector3(30, 197, 0), Vector3(172, 5, 20)])


func _taipei101(mb: MeshBuilder, boxes: Array) -> void:
	## Taipei 101: the tapering podium, eight flared eight-storey modules like bamboo segments,
	## the ruyi emblems, the top tower and the pinnacle (508 m).
	var g := _c(Color(0.42, 0.62, 0.58), K.CURTAIN)
	var trim := _c(Color(0.7, 0.76, 0.74), K.METAL)
	var gold := _c(Color(0.9, 0.75, 0.35), K.METAL)
	K.prism(mb, K.rect(95.0, 60.0, 0.0, 70.0), 0.0, 30.0, _c(Color(0.62, 0.68, 0.7), K.CURTAIN))
	K.loft2(mb, K.notch_rect(35.0, 5.0), 0.0, K.notch_rect(28.0, 4.5), 100.0, g)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		mb.add_cylinder(b * Vector3(0, 96.0, 28.5), b * Vector3(0, 96.0, 29.8), 7.0, 7.0, 16, gold)
		mb.add_cylinder(b * Vector3(0, 96.0, 29.0), b * Vector3(0, 96.0, 30.3), 4.0, 4.0, 12, trim)
	for k in 8:
		var y0 := 100.0 + k * 34.0
		K.loft2(mb, K.notch_rect(22.0, 3.5), y0, K.notch_rect(27.5, 4.5), y0 + 34.0, g, true, false, trim)
		K.prism(mb, K.notch_rect(27.9, 4.6), y0 + 32.6, y0 + 34.0, trim)
	K.prism(mb, K.notch_rect(19.0, 3.0), 372.0, 400.0, g, 1.0, true, trim)
	K.loft2(mb, K.notch_rect(14.0, 2.5), 400.0, K.notch_rect(11.0, 2.0), 438.0, g, true, false, trim)
	K.prism(mb, K.rect(7.0, 7.0), 438.0, 448.0, trim)
	mb.add_cylinder(Vector3(0, 448, 0), Vector3(0, 508, 0), 3.2, 0.5, 8, _c(Color(0.86, 0.86, 0.86), K.METAL))
	for ry in [462.0, 478.0, 492.0]:
		mb.add_cylinder(Vector3(0, ry, 0), Vector3(0, ry + 1.4, 0), 3.4 - (ry - 448.0) * 0.045, 3.4 - (ry - 448.0) * 0.045, 8, trim)
	_aviation_light(Vector3(0, 508.5, 0))
	boxes.append([Vector3(0, 230, 0), Vector3(32, 230, 32)])


func _pyramids(mb: MeshBuilder, boxes: Array) -> void:
	## Giza: Khufu, Khafre (with its casing cap) and Menkaure, the queens' pyramids and the
	## Sphinx.
	var sand := _c(Color(0.85, 0.74, 0.52), K.STONE)
	var casing := _c(Color(0.93, 0.86, 0.7), K.STONE)
	var course := _c(Color(0.76, 0.65, 0.45), K.STONE)
	for p in [[Vector3(0, 0, 0), 230.0, 139.0, false], [Vector3(-350, 0, 300), 215.0, 136.0, true], [Vector3(-600, 0, 560), 105.0, 62.0, false]]:
		var b: Vector3 = p[0]
		var w: float = p[1]
		var h: float = p[2]
		var hw := w * 0.5
		var top_h := h if not bool(p[3]) else h * 0.82
		K.loft2(mb, K.rect(hw, hw, b.x, b.z), b.y, K.rect(hw * (1.0 - top_h / h) + 0.01, hw * (1.0 - top_h / h) + 0.01, b.x, b.z), b.y + top_h, sand, true)
		if bool(p[3]):
			var hw2 := hw * (1.0 - top_h / h)
			K.loft2(mb, K.rect(hw2, hw2, b.x, b.z), b.y + top_h, K.rect(0.05, 0.05, b.x, b.z), b.y + h, casing)
		# weathered courses: a few darker bands give the stepped texture its scale
		for k in 7:
			var y := h * (0.08 + k * 0.1)
			if y > top_h - 2.0:
				break
			var s := hw * (1.0 - y / h) + 0.3
			_fine.add_box(Vector3(b.x, y, b.z), Vector3(s * 2.0, 0.8, s * 2.0), course)
		boxes.append([b + Vector3(0, h * 0.4, 0), Vector3(w * 0.45, h * 0.4, w * 0.45)])
	for k2 in 3:
		var qb := Vector3(150.0, 0, -80.0 + k2 * 55.0)
		K.loft2(mb, K.rect(22.0, 22.0, qb.x, qb.z), 0.0, K.rect(0.05, 0.05, qb.x, qb.z), 28.0, sand)
	# the Sphinx
	var sp := Vector3(350.0, 0, 120.0)
	mb.add_box(sp + Vector3(0, 6, 0), Vector3(12, 12, 50), sand)
	mb.add_box(sp + Vector3(0, 15, -20), Vector3(9, 10, 9), sand)
	mb.add_box(sp + Vector3(0, 2.5, -32), Vector3(10, 5, 16), sand)


func _parthenon(mb: MeshBuilder, boxes: Array) -> void:
	## The Acropolis rock with the Parthenon: stylobate, peristyle of 8 x 17 Doric columns,
	## entablature and pediments, and the Erechtheion beside it.
	var rock := _c(Color(0.6, 0.55, 0.47), K.STONE)
	var marble := _c(Color(0.92, 0.88, 0.8), K.STONE)
	var marble2 := _c(Color(0.84, 0.8, 0.72), K.STONE)
	mb.add_rounded_box(Vector3(0, 35, 0), Vector3(300, 70, 150), rock, 0.5, 14, 8)
	K.prism(mb, K.rect(130.0, 62.0), 66.0, 70.0, _c(Color(0.7, 0.66, 0.58), K.STONE))
	var y0 := 70.0
	K.prism(mb, K.rect(36.0, 17.0), y0, y0 + 1.6, marble)
	var cols := []
	for i in 17:
		cols.append(Vector2(-33.0 + i * 4.125, -14.6))
		cols.append(Vector2(-33.0 + i * 4.125, 14.6))
	for j in range(1, 7):
		cols.append(Vector2(-33.0, -14.6 + j * 4.17))
		cols.append(Vector2(33.0, -14.6 + j * 4.17))
	for cp in cols:
		mb.add_cylinder(Vector3(cp.x, y0 + 1.6, cp.y), Vector3(cp.x, y0 + 12.0, cp.y), 0.95, 0.78, 10, marble, false)
		_fine.add_box(Vector3(cp.x, y0 + 12.2, cp.y), Vector3(2.0, 0.45, 2.0), marble)
	K.prism(mb, K.rect(30.0, 12.0), y0 + 1.6, y0 + 10.0, marble2)
	K.prism(mb, K.rect(35.0, 16.0), y0 + 12.4, y0 + 16.0, marble)
	for sx in [-1.0, 1.0]:
		var gx: float = sx * 35.0
		K.tri(mb, Vector3(gx, y0 + 16.0, -16.0), Vector3(gx, y0 + 16.0, 16.0), Vector3(gx, y0 + 20.5, 0.0), Vector3(sx, 0, 0), marble)
	# partly fallen roof: a central strip only
	K.loft2(mb, K.rect(20.0, 16.0), y0 + 16.0, K.rect(20.0, 0.5), y0 + 20.4, marble2)
	# Erechtheion and the Propylaea
	K.prism(mb, K.rect(12.0, 6.0, 55.0, 35.0), y0, y0 + 9.0, marble)
	K.prism(mb, K.rect(18.0, 10.0, -105.0, 0.0), y0 - 4.0, y0 + 9.0, marble)
	boxes.append([Vector3(0, 42, 0), Vector3(150, 42, 75)])


func _pagoda(mb: MeshBuilder, boxes: Array) -> void:
	## East Asian towers: Osaka Castle's keep by default, the Forbidden City's Hall of Supreme
	## Harmony and Bangkok's Wat Arun prang.
	match _id:
		"forbidden":
			var red := _c(Color(0.66, 0.14, 0.1), K.STONE)
			var yellow := _c(Color(0.9, 0.68, 0.18), K.METAL)
			var marble := _c(Color(0.88, 0.86, 0.82), K.STONE)
			for k in 3:
				K.prism(mb, K.rect(70.0 - k * 6.0, 40.0 - k * 5.0), k * 2.6, k * 2.6 + 2.6, marble)
			K.prism(mb, K.rect(32.0, 18.0), 7.8, 22.0, red)
			for i in 12:
				mb.add_cylinder(Vector3(-30.0 + i * 5.45, 7.8, 18.5), Vector3(-30.0 + i * 5.45, 21.0, 18.5), 0.6, 0.6, 8, red)
			_hip_roof(mb, 22.0, 38.0, 24.0, 4.0, 26.0, 0.0, yellow)
			K.prism(mb, K.rect(28.0, 14.0), 26.5, 30.0, red)
			_hip_roof(mb, 30.0, 34.0, 20.0, 9.0, 18.0, 6.0, yellow)
			# the palace walls around
			for s in [-1.0, 1.0]:
				mb.add_box(Vector3(0, 5, s * 150.0), Vector3(300, 10, 6), red)
				mb.add_box(Vector3(s * 150.0, 5, 0), Vector3(6, 10, 300), red)
			boxes.append([Vector3(0, 20, 0), Vector3(40, 20, 24)])
		"wat":
			# Wat Arun: the central prang and four corner prangs
			var porcelain := _c(Color(0.88, 0.85, 0.78), K.STONE)
			var accent := _c(Color(0.62, 0.66, 0.72), K.STONE)
			K.prism(mb, K.rect(40.0, 40.0), 0.0, 4.0, porcelain)
			_prang(mb, Vector3.ZERO, 70.0, 16.0, porcelain, accent)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_prang(mb, Vector3(sx * 30.0, 4.0, sz * 30.0), 30.0, 6.0, porcelain, accent)
			boxes.append([Vector3(0, 35, 0), Vector3(20, 35, 20)])
		_:
			# Osaka Castle: battered stone base, white walls, green flared roofs, gold trim
			var stone := _c(Color(0.55, 0.53, 0.5), K.STONE)
			var wall := _c(Color(0.94, 0.94, 0.92), K.PUNCHED)
			var green := _c(Color(0.32, 0.55, 0.5), K.METAL)
			var gold := _c(Color(0.92, 0.75, 0.3), K.METAL)
			K.loft2(mb, K.rect(30.0, 26.0), 0.0, K.rect(24.0, 20.0), 14.0, stone)
			var y := 14.0
			for k in 5:
				var hx := 21.0 - k * 3.2
				var hz := 17.0 - k * 2.7
				K.prism(mb, K.rect(hx, hz), y, y + 6.5, wall)
				_hip_roof(mb, y + 6.5, hx + 3.5, hz + 3.5, 2.2, hx * 0.82, hz * 0.82, green)
				_fine.add_box(Vector3(0, y + 4.0, hz + 0.3), Vector3(hx * 0.6, 1.4, 0.3), gold)
				y += 8.7
			_hip_roof(mb, y, 9.0, 7.0, 6.0, 0.3, 0.3, green)
			for sx2 in [-1.0, 1.0]:
				mb.add_box(Vector3(sx2 * 6.5, y + 1.5, 0), Vector3(1.2, 2.5, 0.8), gold)
			boxes.append([Vector3(0, 35, 0), Vector3(26, 35, 26)])


func _hip_roof(mb: MeshBuilder, y: float, ex: float, ez: float, rise: float, tx: float, tz: float, col: Color) -> void:
	## Flared hip roof: wide eaves curving up to a ridge (tx, tz are the top half extents).
	var mid_y := y + rise * 0.35
	K.loft2(mb, K.rect(ex, ez), y - 0.4, K.rect(ex, ez), y, col, false)
	K.loft2(mb, K.rect(ex, ez), y, K.rect(lerpf(ex, tx, 0.55), lerpf(ez, tz, 0.55)), mid_y, col, false)
	K.loft2(mb, K.rect(lerpf(ex, tx, 0.55), lerpf(ez, tz, 0.55)), mid_y, K.rect(maxf(tx, 0.05), maxf(tz, 0.05)), y + rise, col, true)
	# upturned corners
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_cone(Vector3(sx * ex, y - 0.2, sz * ez), Vector3(sx * (ex + 1.2), y + 1.4, sz * (ez + 1.2)), 0.5, 4, col)


func _prang(mb: MeshBuilder, base: Vector3, h: float, r: float, col: Color, accent: Color) -> void:
	## A Khmer-style prang: stacked, narrowing tiers rounding to a spike.
	var y := base.y
	var n := 9
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var r0 := r * (1.0 - t0 * 0.82)
		var r1 := r * (1.0 - t1 * 0.82)
		var hh := h * 0.85 / n
		var off := Vector2(base.x, base.z)
		K.loft2(mb, K.xform_poly(K.chamfer_rect(r0, r0, r0 * 0.35), 0.0, off), y, K.xform_poly(K.chamfer_rect(r1 * 1.05, r1 * 1.05, r1 * 0.37), 0.0, off), y + hh, col if k % 2 == 0 else accent)
		y += hh
	mb.add_cone(Vector3(base.x, y, base.z), Vector3(base.x, base.y + h, base.z), r * 0.16, 8, col)


func _onion_domes(mb: MeshBuilder, boxes: Array) -> void:
	## St Basil's: nine chapels whose onion domes carry twisting stripes, around the tent-roofed
	## central spire, on a brick terrace.
	var brick := _c(Color(0.68, 0.27, 0.2), K.PUNCHED)
	var brick_p := _c(Color(0.68, 0.27, 0.2), K.STONE)
	var white := _c(Color(0.92, 0.9, 0.85), K.STONE)
	var gold := _c(Color(0.92, 0.75, 0.3), K.METAL)
	K.prism(mb, K.rect(34.0, 34.0), 0.0, 12.0, brick)
	K.prism(mb, K.rect(35.0, 35.0), 12.0, 13.0, white)
	# central tent spire
	K.prism(mb, K.ngon(8, 8.0, PI / 8.0), 12.0, 38.0, brick_p)
	K.loft2(mb, K.ngon(8, 7.4, PI / 8.0), 38.0, K.ngon(8, 0.5, PI / 8.0), 56.0, _c(Color(0.86, 0.6, 0.3), K.STONE))
	mb.add_sphere(Vector3(0, 57.5, 0), Vector3(2.2, 2.6, 2.2), 12, 8, gold)
	mb.add_cone(Vector3(0, 59.5, 0), Vector3(0, 63.0, 0), 0.5, 6, gold)
	var schemes := [[Color(0.85, 0.2, 0.2), Color(0.95, 0.9, 0.8)], [Color(0.2, 0.6, 0.35), Color(0.95, 0.8, 0.25)],
		[Color(0.95, 0.75, 0.2), Color(0.2, 0.55, 0.35)], [Color(0.2, 0.4, 0.8), Color(0.95, 0.95, 0.9)],
		[Color(0.2, 0.62, 0.4), Color(0.85, 0.25, 0.2)], [Color(0.9, 0.55, 0.15), Color(0.2, 0.5, 0.3)],
		[Color(0.25, 0.55, 0.75), Color(0.95, 0.85, 0.3)], [Color(0.8, 0.2, 0.25), Color(0.25, 0.6, 0.4)]]
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var big := i % 2 == 0
		var rad := 21.0 if big else 15.0
		var b := Vector3(cos(a) * rad, 12.0, sin(a) * rad)
		var dh := 26.0 if big else 18.0
		var dr := 5.6 if big else 4.2
		K.prism(mb, K.ngon(8, dr * 1.15, PI / 8.0, b.x, b.z), 12.0, 12.0 + dh, brick_p)
		mb.add_cylinder(b + Vector3(0, dh, 0), b + Vector3(0, dh + 3.0, 0), dr * 0.8, dr * 0.75, 12, white)
		var sch: Array = schemes[i]
		_onion(mb, b + Vector3(0, dh + 3.0, 0), dr, dr * 2.4, sch[0], sch[1])
		mb.add_cone(b + Vector3(0, dh + 3.0 + dr * 2.4, 0), b + Vector3(0, dh + 6.0 + dr * 2.4, 0), 0.35, 6, gold)
	boxes.append([Vector3(0, 30, 0), Vector3(34, 30, 34)])


func _onion(mb: MeshBuilder, base: Vector3, r: float, h: float, ca: Color, cb: Color) -> void:
	## Onion dome lofted from a profile, in twisting coloured gores.
	var prof := [[0.0, 0.8], [0.12, 0.97], [0.26, 1.0], [0.4, 0.93], [0.55, 0.74], [0.7, 0.48], [0.82, 0.26], [0.92, 0.1], [1.0, 0.0]]
	var gores := 12
	var twist := 1.4
	for g in gores:
		var col := _c(ca if g % 2 == 0 else cb, K.METAL)
		for j in prof.size() - 1:
			var t0: float = prof[j][0]
			var t1: float = prof[j + 1][0]
			var r0: float = float(prof[j][1]) * r
			var r1: float = float(prof[j + 1][1]) * r
			var a0 := TAU * g / gores + twist * t0
			var a1 := TAU * (g + 1) / gores + twist * t0
			var a2 := TAU * (g + 1) / gores + twist * t1
			var a3 := TAU * g / gores + twist * t1
			var p0 := base + Vector3(cos(a0) * r0, t0 * h, sin(a0) * r0)
			var p1 := base + Vector3(cos(a1) * r0, t0 * h, sin(a1) * r0)
			var p2 := base + Vector3(cos(a2) * r1, t1 * h, sin(a2) * r1)
			var p3 := base + Vector3(cos(a3) * r1, t1 * h, sin(a3) * r1)
			var outward := (p0 + p1 + p2 + p3) * 0.25 - (base + Vector3(0, h * 0.3, 0))
			if r1 < 0.001:
				K.tri(mb, p0, p1, p2, outward, col)
			else:
				K.quad(mb, p0, p1, p2, p3, outward, col)
