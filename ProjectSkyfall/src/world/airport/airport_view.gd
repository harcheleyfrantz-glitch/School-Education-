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
	# kerbside streetscape and stand equipment (decor only; nothing else depends on them)
	AirportLandside.build(self, layout, icao, mgr)
	JetBridge.dress_stands(self, layout, icao, mgr.material_for("vcolor", {}, self))


# ------------------------------------------------------------------ terminal interior
func build_terminal_interior() -> TerminalInterior:
	## The walkable departures level (built on demand: only where the player is).
	if terminal != null:
		return terminal
	# the walkable hall is the first terminal (or, failing that, concourse) with gates on its faces
	var pick: Dictionary = {}
	for kind in ["terminal", "concourse"]:
		for b in layout.buildings:
			if b.kind == kind and pick.is_empty() and _has_gates(b):
				pick = b
	if pick.is_empty():
		for b in layout.buildings:
			if b.kind == "terminal" and pick.is_empty():
				pick = b
	for b in [pick]:
		if b.is_empty():
			continue
		terminal = TerminalInterior.new()
		add_child(terminal)
		terminal.build(self, b, layout, String(Airports.get_ap(icao).get("name", icao)))
		# daylight comes in through the curtain walls; the roof still shades the hall
		if glass_mi:
			glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		break
	return terminal


func _has_gates(b: Dictionary) -> bool:
	var ax: Vector2 = (b.axis as Vector2).normalized()
	var nn := Vector2(-ax.y, ax.x)
	for fc in layout.facades:
		var rel: Vector2 = (fc.origin as Vector2) - (b.center as Vector2)
		if absf(absf(rel.dot(nn)) - float(b.depth) * 0.5) < 10.0 and absf(rel.dot(ax)) < float(b.len) * 0.5 + 10.0:
			return true
	return false


# ------------------------------------------------------------------ jet bridges
## Jet bridges are walkable: a fixed corridor level with the departures floor runs out to a
## glazed rotunda, and the telescopic tunnel pitches up or down to the aircraft's door sill.
## The meshes and posing live in JetBridge (src/world/models/airports/jetbridge.gd).
const JetBridge := preload("res://src/world/models/airports/jetbridge.gd")
const AirportLandside := preload("res://src/world/models/airports/landside.gd")
const BRIDGE_FLOOR := 4.5        # TerminalInterior.FLOOR (= JetBridge.FLOOR)
const BRIDGE_W := 2.6
const BRIDGE_H := 2.45
const CAB_D := 3.0               # = JetBridge.CAB_D
const ROT_R := 2.3


func _make_bridge(b: Dictionary) -> void:
	var mat: Material = manager.material_for("vcolor_2s", {}, self)
	var br := JetBridge.make(self, b, mat, JetBridge.finish_for(icao))
	bridges.append(br)
	_apply_bridge(br)


func _apply_bridge(br: Dictionary) -> void:
	JetBridge.apply(br)


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
