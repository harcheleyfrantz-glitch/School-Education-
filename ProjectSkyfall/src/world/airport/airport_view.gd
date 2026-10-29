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
var glass_mi: MeshInstance3D = null
var terminal: TerminalInterior = null


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
		if m.key == "glass":
			glass_mi = mi
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


# ------------------------------------------------------------------ terminal interior
func build_terminal_interior() -> TerminalInterior:
	## The walkable departures level (built on demand: only where the player is).
	if terminal != null:
		return terminal
	for b in layout.buildings:
		if b.kind != "terminal":
			continue
		terminal = TerminalInterior.new()
		add_child(terminal)
		terminal.build(self, b, layout, String(Airports.get_ap(icao).get("name", icao)))
		# daylight comes in through the curtain walls; the roof still shades the hall
		if glass_mi:
			glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		break
	return terminal


# ------------------------------------------------------------------ jet bridges
## Jet bridges are walkable: a fixed corridor level with the departures floor runs out to a
## glazed rotunda, and the telescopic tunnel pitches up or down to the aircraft's door sill.
const BRIDGE_FLOOR := 4.5        # TerminalInterior.FLOOR
const BRIDGE_W := 2.6            # inside width
const BRIDGE_H := 2.45           # inside height
const CAB_D := 3.0
const ROT_R := 2.3

static func _corridor(mb: MeshBuilder, z0: float, z1: float, shell: Color, inner: Color, floor_c: Color, glass: Color) -> void:
	## Hollow corridor along +z with its floor at y = 0 (double-sided material: walls read from
	## both sides), a window band down each side and a light trough in the ceiling.
	var hw := BRIDGE_W * 0.5
	var L := z1 - z0
	var zc := (z0 + z1) * 0.5
	mb.add_box(Vector3(0, -0.12, zc), Vector3(BRIDGE_W + 0.3, 0.24, L), floor_c)
	mb.add_box(Vector3(0, BRIDGE_H + 0.14, zc), Vector3(BRIDGE_W + 0.3, 0.28, L), shell)
	mb.add_box(Vector3(0, BRIDGE_H - 0.01, zc), Vector3(BRIDGE_W - 0.2, 0.02, L), inner)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.07)
		mb.add_box(Vector3(x, 0.45, zc), Vector3(0.14, 0.9, L), shell)
		mb.add_box(Vector3(x, 0.9 + 0.55, zc), Vector3(0.05, 1.1, L), glass)
		mb.add_box(Vector3(x, 2.0 + (BRIDGE_H - 2.0) * 0.5 + 0.0, zc), Vector3(0.14, BRIDGE_H - 2.0 + 0.0, L), shell)
		mb.add_box(Vector3(sx * (hw - 0.02), 0.06, zc), Vector3(0.04, 0.12, L), Color(0.18, 0.19, 0.2))


func _make_bridge(b: Dictionary) -> void:
	var root := Node3D.new()
	var rp: Vector2 = b.root
	var nrm: Vector2 = b.normal
	root.position = Vector3(rp.x, 0, rp.y)
	add_child(root)
	var mat: Material = manager.material_for("vcolor_2s", {}, self)
	var shell := Color(0.74, 0.76, 0.78)
	var inner := Color(0.86, 0.85, 0.82)
	var carpet := Color(0.16, 0.19, 0.26)
	var glass := Color(0.16, 0.24, 0.3)
	var yaw_n := atan2(nrm.x, nrm.y)
	var rot := rp + nrm * 9.0
	var rl := Vector3(rot.x - rp.x, 0, rot.y - rp.y)
	# fixed corridor from the terminal glass to the rotunda, floor level with departures
	var stub := MeshBuilder.new()
	stub.xf = Transform3D(Basis(Vector3.UP, yaw_n), Vector3(0, BRIDGE_FLOOR, 0))
	_corridor(stub, 0.0, 9.0 - ROT_R + 0.3, shell, inner, carpet, glass)
	# rotunda: round floor and roof on a column, glazed all round
	stub.xf = Transform3D(Basis(), rl + Vector3(0, BRIDGE_FLOOR, 0))
	stub.add_cylinder(Vector3(0, -0.24, 0), Vector3(0, 0.0, 0), ROT_R, ROT_R, 16, carpet)
	stub.add_cylinder(Vector3(0, BRIDGE_H, 0), Vector3(0, BRIDGE_H + 0.3, 0), ROT_R + 0.1, ROT_R + 0.1, 16, shell)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		stub.add_box(Vector3(cos(a) * ROT_R, BRIDGE_H * 0.5, sin(a) * ROT_R), Vector3(0.12, BRIDGE_H, 0.12), shell)
	stub.xf = Transform3D.IDENTITY
	stub.add_cylinder(rl, rl + Vector3(0, BRIDGE_FLOOR - 0.24, 0), 0.55, 0.55, 10, Color(0.5, 0.5, 0.52))
	var smi := MeshInstance3D.new()
	smi.mesh = stub.commit()
	smi.material_override = mat
	root.add_child(smi)
	# light troughs (emissive)
	var lights := MeshBuilder.new()
	lights.xf = Transform3D(Basis(Vector3.UP, yaw_n), Vector3(0, BRIDGE_FLOOR, 0))
	lights.add_box(Vector3(0, BRIDGE_H - 0.03, (9.0 - ROT_R) * 0.5), Vector3(0.3, 0.03, 9.0 - ROT_R - 0.8), Color(1.0, 0.96, 0.88))
	var lmi := MeshInstance3D.new()
	lmi.mesh = lights.commit()
	lmi.material_override = TerminalInterior.material("emit")
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lmi)
	# telescopic tunnel (unit length, scaled along z), pitched at the rotunda
	var pivot := Node3D.new()
	pivot.position = rl + Vector3(0, BRIDGE_FLOOR, 0)
	root.add_child(pivot)
	var tunnel := Node3D.new()
	pivot.add_child(tunnel)
	var tb := MeshBuilder.new()
	_corridor(tb, 0.0, 1.0, shell, inner, carpet, glass)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tb.commit()
	tmi.material_override = mat
	tunnel.add_child(tmi)
	var tl := MeshBuilder.new()
	tl.add_box(Vector3(0, BRIDGE_H - 0.03, 0.5), Vector3(0.3, 0.03, 0.9), Color(1.0, 0.96, 0.88))
	var tlmi := MeshInstance3D.new()
	tlmi.mesh = tl.commit()
	tlmi.material_override = TerminalInterior.material("emit")
	tlmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tunnel.add_child(tlmi)
	# cab: stays level, opens onto the aircraft door through a dark canopy frame
	var cab := Node3D.new()
	pivot.add_child(cab)
	var cb := MeshBuilder.new()
	_corridor(cb, 0.0, CAB_D - 0.4, shell, inner, carpet, glass)
	cb.add_box(Vector3(0, BRIDGE_H * 0.5, CAB_D - 0.2), Vector3(BRIDGE_W + 0.5, 0.25, 0.4), Color(0.08, 0.08, 0.08))
	for sx in [-1.0, 1.0]:
		cb.add_box(Vector3(sx * (BRIDGE_W * 0.5 + 0.12), BRIDGE_H * 0.5, CAB_D - 0.2), Vector3(0.25, BRIDGE_H + 0.3, 0.45), Color(0.08, 0.08, 0.08))
	cb.add_box(Vector3(0, BRIDGE_H + 0.12, CAB_D - 0.2), Vector3(BRIDGE_W + 0.5, 0.25, 0.45), Color(0.08, 0.08, 0.08))
	cb.add_box(Vector3(0, -0.05, CAB_D - 0.2), Vector3(BRIDGE_W, 0.1, 0.4), Color(0.85, 0.7, 0.1))
	var cmi := MeshInstance3D.new()
	cmi.mesh = cb.commit()
	cmi.material_override = mat
	cab.add_child(cmi)
	# drive column with its wheel bogie, scaled to the cab height each update
	var col := Node3D.new()
	cab.add_child(col)
	col.position = Vector3(0, -0.24, 0.9)
	var colb := MeshBuilder.new()
	colb.add_cylinder(Vector3(0, -1.0, 0), Vector3(0, 0, 0), 0.2, 0.2, 8, Color(0.42, 0.42, 0.44))
	var cbm := MeshInstance3D.new()
	cbm.mesh = colb.commit()
	cbm.material_override = mat
	col.add_child(cbm)
	var bogie := MeshBuilder.new()
	bogie.add_box(Vector3(0, 0.45, 0), Vector3(2.6, 0.5, 1.2), Color(0.3, 0.3, 0.32))
	for sx2 in [-1.0, 1.0]:
		bogie.add_cylinder(Vector3(sx2 * 1.0 - 0.18, 0.35, 0), Vector3(sx2 * 1.0 + 0.18, 0.35, 0), 0.35, 0.35, 12, Color(0.06, 0.06, 0.06))
	var bmi := MeshInstance3D.new()
	bmi.mesh = bogie.commit()
	bmi.material_override = mat
	cab.add_child(bmi)
	# parked: swung along the facade toward the aircraft's side
	var left: Vector2 = b.left
	var park_dir := (nrm * 0.55 - left * 0.6).normalized()
	var rest_yaw := atan2(park_dir.x, park_dir.y)
	var br := {"root": root, "pivot": pivot, "tunnel": tunnel, "cab": cab, "column": col, "bogie": bmi, "rest_yaw": rest_yaw, "stand": b.stand,
		"docked": false, "length": 12.0, "yaw": rest_yaw, "target_len": 12.0, "target_yaw": rest_yaw, "pitch": 0.0, "target_pitch": 0.0}
	bridges.append(br)
	_apply_bridge(br)


func _apply_bridge(br: Dictionary) -> void:
	var pitch := float(br.pitch)
	br.pivot.basis = Basis(Vector3.UP, float(br.yaw)) * Basis(Vector3.RIGHT, -pitch)
	br.tunnel.scale = Vector3(1, 1, float(br.length))
	br.cab.position = Vector3(0, 0, float(br.length))
	br.cab.basis = Basis(Vector3.RIGHT, pitch)
	var cab_h := BRIDGE_FLOOR + float(br.length) * sin(pitch) - 0.24
	br.column.scale = Vector3(1, maxf(cab_h - 0.9, 0.1), 1)
	br.bogie.position = Vector3(0, -cab_h - 0.24, 0.9)


func dock_bridge(stand_name: String, sill_local: Vector3) -> bool:
	## Extends the stand's jet bridge to an aircraft door sill (airport-local coordinates).
	for br in bridges:
		var s: Dictionary = layout.stands[br.stand]
		if s.name != stand_name:
			continue
		var piv: Vector3 = br.root.position + br.pivot.position
		var to := sill_local - piv
		var horiz := Vector2(to.x, to.z).length() - CAB_D + 0.15
		var pitch := clampf(atan2(to.y, maxf(horiz, 1.0)), -0.2, 0.2)
		br.target_yaw = atan2(to.x, to.z)
		br.target_len = clampf(horiz / cos(pitch), 6.0, 38.0)
		br.target_pitch = pitch
		br.docked = true
		return true
	return false


func undock_bridge(stand_name: String) -> void:
	for br in bridges:
		var s: Dictionary = layout.stands[br.stand]
		if s.name == stand_name:
			br.target_yaw = br.rest_yaw
			br.target_len = 12.0
			br.target_pitch = 0.0
			br.docked = false


func bridge_state(stand_name: String) -> String:
	for br in bridges:
		if layout.stands[br.stand].name == stand_name:
			if br.docked and absf(br.length - br.target_len) < 0.05 and absf(angle_difference(br.yaw, br.target_yaw)) < 0.01:
				return "docked"
			return "moving" if br.docked else "retracted"
	return "none"


## The walk through a stand's bridge, airport-local floor points: terminal door, rotunda,
## tunnel end, cab threshold (the aircraft door sill when docked).
func bridge_path(stand_name: String) -> Array:
	for br in bridges:
		if layout.stands[br.stand].name != stand_name:
			continue
		var root: Vector3 = br.root.position
		var piv: Vector3 = root + br.pivot.position
		var b := Basis(Vector3.UP, float(br.yaw))
		var dir := b * Basis(Vector3.RIGHT, -float(br.pitch)) * Vector3(0, 0, 1)
		var p2 := piv + dir * float(br.length)
		var p3 := p2 + b * Vector3(0, 0, CAB_D - 0.25)
		var rot2 := Vector2(piv.x - root.x, piv.z - root.z).normalized()
		var p0 := root + Vector3(0, BRIDGE_FLOOR, 0) - Vector3(rot2.x, 0, rot2.y) * 0.2
		return [p0, piv, p2, p3]
	return []


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
		var np := move_toward(br.pitch, br.target_pitch, 0.05 * delta)
		if ny != br.yaw or nl != br.length or np != br.pitch:
			changed = true
		br.yaw = ny
		br.length = nl
		br.pitch = np
		if changed:
			_apply_bridge(br)


# ------------------------------------------------------------------ queries (airport-local)
func stand_local(stand_name: String) -> Dictionary:
	return AirportLayout.stand_by_name(layout, stand_name)
