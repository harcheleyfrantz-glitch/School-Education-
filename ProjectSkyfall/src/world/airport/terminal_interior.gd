class_name TerminalInterior
extends Node3D
## The departures level of a passenger terminal: the landside check-in hall, the security
## checkpoint, shops and cafés, the concourse, gate lounges with their seating, podiums and
## signs, departure boards, and the doors through to the jet bridges.
##
## Built in the terminal's own frame - x across the building (positive towards the first apron
## facade), z along it, y up from the apron - and placed as a child of the AirportView. Besides
## the geometry it records what the walker and the terminal crowd need: obstacles, seats and
## points of interest.

const FLOOR := 4.5                 # departures level, level with the jet bridge stubs
const DOOR_W := 2.4
const BRANDS := [
	["Calder Coffee Co.", "cafe", Color(0.42, 0.25, 0.14)], ["SkyNews & Books", "shop", Color(0.75, 0.12, 0.12)],
	["Duty Free", "shop", Color(0.1, 0.1, 0.12)], ["Harbor Bistro", "cafe", Color(0.12, 0.32, 0.36)],
	["Aero Pharmacy", "shop", Color(0.1, 0.5, 0.3)], ["Westmark Wines", "shop", Color(0.42, 0.08, 0.16)],
	["Travel Essentials", "shop", Color(0.16, 0.3, 0.6)], ["Gate Burger", "cafe", Color(0.85, 0.45, 0.08)],
	["Book & Brew", "cafe", Color(0.3, 0.22, 0.4)], ["Toilets", "wc", Color(0.25, 0.3, 0.36)],
]

var icao := ""
var bld: Dictionary = {}
var depth := 0.0
var length := 0.0
var ceil_h := 0.0
var hub := false
var sides: Array = []              # airside faces: [{s: +1/-1, fc: facade record}]
var land_s := 0.0                  # side of the landside wall (0 when both long sides are airside)
var sec: Dictionary = {}           # security line: {axis: "x"/"z", at, gap0, gap1, lanes: [centre...]}
var obstacles: Array = []          # {c: Vector2(x, z), h: Vector2 half-size} or {c, r}
var spots: Array = []              # points of interest {kind, p: Vector3, text, ...}
var gates: Array = []              # {name, stand, door: Vector3, podium: Vector3, s, z}
var seats: Array = []              # {xf: Transform3D, gate: String, taken: bool}
var entrance := Vector3.ZERO       # where a passenger walks in from the kerb
var _fids: Array = []              # boards: [{lines: [Label3D], title: Label3D}]
var _fids_t := 0.0
var _mbs := {}
var _yaw := 0.0
var _center := Vector2.ZERO

static var _mats := {}
static var _seat_mesh: ArrayMesh
static var _plant_mesh: ArrayMesh
static var _table_mesh: ArrayMesh
static var _chair_mesh: ArrayMesh


# ================================================================== build
func build(view_ap: Node, terminal: Dictionary, layout: Dictionary, airport_name: String) -> void:
	icao = String(layout.icao)
	bld = terminal
	name = "TerminalInterior"
	hub = String(layout.get("size", "")) == "hub"
	depth = float(terminal.depth)
	length = float(terminal.len)
	ceil_h = float(terminal.h) - (2.0 if hub else 1.2)
	_center = terminal.center
	var ax: Vector2 = terminal.axis
	_yaw = atan2(ax.x, ax.y)
	transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(_center.x, 0.0, _center.y))
	# which long faces open onto aprons
	for fc in layout.facades:
		var n := _dir_local(fc.normal)
		sides.append({"s": signf(n.x) if absf(n.x) > 0.5 else 1.0, "fc": fc})
	if sides.size() == 1:
		land_s = -float(sides[0].s)
	_shell()
	for sd in sides:
		_airside(sd, layout, view_ap)
	_security_and_landside(layout)
	_retail()
	_boards()
	_wayfinding()
	_commit()
	add_child(CabinInterior.make_interior_probe("TerminalProbe", Vector3(0, (FLOOR + ceil_h) * 0.5, 0),
		Vector3(depth + 1.0, ceil_h - FLOOR + 2.0, length + 1.0), Color(0.95, 0.96, 0.98), 0.62))
	CabinInterior.tag_interior(self)
	refresh_boards()


func _dir_local(d: Vector2) -> Vector3:
	return Basis(Vector3.UP, _yaw).inverse() * Vector3(d.x, 0.0, d.y)


func point_local(p: Vector2) -> Vector3:
	## Airport-local 2D point -> this terminal's frame (at departures level).
	var v := Basis(Vector3.UP, _yaw).inverse() * Vector3(p.x - _center.x, 0.0, p.y - _center.y)
	return Vector3(v.x, FLOOR, v.z)


func to_airport(p: Vector3) -> Vector3:
	return transform * p


func _b(key: String) -> MeshBuilder:
	if not _mbs.has(key):
		_mbs[key] = MeshBuilder.new()
	return _mbs[key]


static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if key == "glass":
		var g := StandardMaterial3D.new()
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.albedo_color = Color(0.75, 0.85, 0.9, 0.12)
		g.roughness = 0.03
		g.metallic_specular = 0.9
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = g
	elif key == "frosted":
		var f := StandardMaterial3D.new()
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.albedo_color = Color(0.9, 0.93, 0.95, 0.55)
		f.roughness = 0.35
		f.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = f
	else:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/terminal.gdshader")
		match key:
			"floor":
				sm.set_shader_parameter("kind", 0)
				sm.set_shader_parameter("base_color", Color(0.8, 0.79, 0.76))
			"carpet":
				sm.set_shader_parameter("kind", 1)
				sm.set_shader_parameter("base_color", Color(0.2, 0.23, 0.29))
				sm.set_shader_parameter("accent", Color(0.33, 0.38, 0.46))
			"ceiling":
				sm.set_shader_parameter("kind", 2)
				sm.set_shader_parameter("base_color", Color(0.9, 0.9, 0.89))
			"wall":
				sm.set_shader_parameter("kind", 3)
				sm.set_shader_parameter("base_color", Color(0.86, 0.86, 0.84))
			"emit":
				sm.set_shader_parameter("kind", 5)
			_:
				sm.set_shader_parameter("kind", 4)
		m = sm
	_mats[key] = m
	return m


func _commit() -> void:
	for key in _mbs.keys():
		var mb: MeshBuilder = _mbs[key]
		if mb.verts.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "T_" + key
		mi.mesh = mb.commit()
		mi.material_override = material(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key in ["emit", "glass", "frosted", "floor", "carpet"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 2500.0
		add_child(mi)
	_mbs.clear()


func _rect(c: Vector2, h: Vector2) -> void:
	obstacles.append({"c": c, "h": h})


func _circle(c: Vector2, r: float) -> void:
	obstacles.append({"c": c, "r": r})


func _spot(kind: String, p: Vector3, text: String, extra: Dictionary = {}) -> void:
	var d := {"kind": kind, "p": p, "text": text}
	d.merge(extra, true)
	spots.append(d)


func _label(text: String, p: Vector3, facing: Vector3, height_m: float, col: Color, font_px: int = 64, mono: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_px
	l.pixel_size = height_m / float(font_px) * 1.4
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if mono:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
		l.font = f
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = p
	l.basis = Basis.looking_at(-facing.normalized(), Vector3.UP)
	l.visibility_range_end = 220.0
	add_child(l)
	return l


# ================================================================== shell
func _shell() -> void:
	var hx := depth * 0.5
	var hz := length * 0.5
	var f := _b("floor")
	f.add_quad(Vector3(-hx, FLOOR + 0.01, -hz), Vector3(-hx, FLOOR + 0.01, hz), Vector3(hx, FLOOR + 0.01, hz), Vector3(hx, FLOOR + 0.01, -hz), Color.WHITE)
	var c := _b("ceiling")
	c.add_quad(Vector3(-hx, ceil_h, -hz), Vector3(hx, ceil_h, -hz), Vector3(hx, ceil_h, hz), Vector3(-hx, ceil_h, hz), Color.WHITE)
	# long light lines in the ceiling: they give the hall its depth
	var em := _b("emit")
	var step_x := 7.0 if hub else 6.0
	var x := -hx + step_x * 0.5
	while x < hx:
		em.add_box(Vector3(x, ceil_h - 0.03, 0), Vector3(0.22, 0.04, length - 4.0), Color(0.98, 0.96, 0.9))
		x += step_x
	# glazing from inside: mullions on the exterior's 3.2 m x 4.2 m grid, a sill and the glass
	var v := _b("vcol")
	var gl := _b("glass")
	var mull := Color(0.32, 0.34, 0.37, 0.3)
	for sx in [-1.0, 1.0]:
		var xw: float = sx * (hx - 0.12)
		var z := -hz
		while z <= hz:
			v.add_box(Vector3(xw, (FLOOR + ceil_h) * 0.5, z), Vector3(0.1, ceil_h - FLOOR, 0.12), mull)
			z += 3.2
		var y := FLOOR + 4.2
		while y < ceil_h:
			v.add_box(Vector3(xw, y, 0), Vector3(0.08, 0.1, length), mull)
			y += 4.2
		v.add_box(Vector3(sx * (hx - 0.3), FLOOR + 0.2, 0), Vector3(0.4, 0.4, length), Color(0.55, 0.56, 0.58, 0.75))
		gl.add_quad(Vector3(sx * (hx - 0.05), FLOOR, -hz), Vector3(sx * (hx - 0.05), FLOOR, hz), Vector3(sx * (hx - 0.05), ceil_h, hz), Vector3(sx * (hx - 0.05), ceil_h, -hz), Color.WHITE)
		_rect(Vector2(sx * (hx - 0.3), 0), Vector2(0.55, hz))
	for sz in [-1.0, 1.0]:
		var zw: float = sz * (hz - 0.12)
		var xx := -hx
		while xx <= hx:
			v.add_box(Vector3(xx, (FLOOR + ceil_h) * 0.5, zw), Vector3(0.12, ceil_h - FLOOR, 0.1), mull)
			xx += 3.2
		gl.add_quad(Vector3(-hx, FLOOR, sz * (hz - 0.05)), Vector3(hx, FLOOR, sz * (hz - 0.05)), Vector3(hx, ceil_h, sz * (hz - 0.05)), Vector3(-hx, ceil_h, sz * (hz - 0.05)), Color.WHITE)
		_rect(Vector2(0, sz * (hz - 0.3)), Vector2(hx, 0.55))
	# structural columns: tall white drums with chrome collars
	var col_x := []
	for sd in sides:
		col_x.append(float(sd.s) * (hx - (24.0 if hub else 18.0)))
	if land_s != 0.0:
		col_x.append(land_s * (hx - 14.0))
	var zc := -hz + 9.0
	while zc < hz - 4.0:
		for cx in col_x:
			v.add_cylinder(Vector3(cx, FLOOR, zc), Vector3(cx, ceil_h, zc), 0.42, 0.42, 14, Color(0.93, 0.93, 0.92, 0.75), false)
			v.add_cylinder(Vector3(cx, FLOOR, zc), Vector3(cx, FLOOR + 0.12, zc), 0.5, 0.5, 14, Color(0.8, 0.8, 0.82, 0.3), true)
			_circle(Vector2(cx, zc), 0.55)
		zc += 18.0


# ================================================================== airside: gates
func _band(s: float) -> Dictionary:
	## Widths of the bands from an apron facade inwards.
	var gw := 24.0 if hub else 18.0
	var cw := 13.0 if hub else 9.0
	var rw := 16.0 if hub else 9.0
	var edge := s * depth * 0.5
	return {"edge": edge, "gate_in": edge - s * gw, "conc_in": edge - s * (gw + cw), "retail_in": edge - s * (gw + cw + rw), "gw": gw, "cw": cw, "rw": rw}


func _airside(sd: Dictionary, layout: Dictionary, view_ap: Node) -> void:
	var s: float = sd.s
	var bnd := _band(s)
	var fc: Dictionary = sd.fc
	var fn: Vector2 = fc.normal
	for si in layout.stands.size():
		var st: Dictionary = layout.stands[si]
		if not bool(st.get("bridge", false)) or (st.normal as Vector2).dot(fn) < 0.9:
			continue
		var gate_c := point_local(st.facade_origin)
		# the bridge root sits 9 m along the facade from the stand centre
		var nn: Vector2 = st.normal
		var left := Vector2(-nn.y, nn.x)
		var door_l := point_local((st.facade_origin as Vector2) + left * 9.0)
		var zg := gate_c.z
		var zd := door_l.z
		var gname := String(st.name)
		var xw := s * (depth * 0.5 - 0.2)
		_gate_door(s, zd, gname)
		var pod := Vector3(s * (depth * 0.5 - 4.5), FLOOR, zd - signf(zd - zg) * 4.0 if absf(zd - zg) > 0.5 else zd + 4.0)
		_podium(pod, s, gname)
		_gate_sign(Vector3(s * (depth * 0.5 - float(bnd.gw) * 0.55), FLOOR + 4.4, zg), gname)
		_gate_seating(s, bnd, zg, zd, pod, gname)
		gates.append({"name": gname, "stand": si, "door": Vector3(xw, FLOOR, zd), "podium": pod, "s": s, "z": zg})
		_spot("gate_podium", pod + Vector3(-s * 1.4, 0, 0), "Gate %s desk" % gname, {"gate": gname})
		_spot("gate_door", Vector3(s * (depth * 0.5 - 1.2), FLOOR, zd), "Gate %s - to the aircraft" % gname, {"gate": gname})


func _gate_door(s: float, zd: float, gname: String) -> void:
	var v := _b("vcol")
	var xw := s * (depth * 0.5 - 0.25)
	var frame := Color(0.22, 0.24, 0.27, 0.3)
	for dz in [-DOOR_W * 0.5 - 0.1, DOOR_W * 0.5 + 0.1]:
		v.add_box(Vector3(xw, FLOOR + 1.35, zd + dz), Vector3(0.3, 2.7, 0.18), frame)
	v.add_box(Vector3(xw, FLOOR + 2.8, zd), Vector3(0.3, 0.2, DOOR_W + 0.4), frame)
	# gate number over the door, lit
	var em := _b("emit")
	em.add_box(Vector3(xw - s * 0.16, FLOOR + 3.25, zd), Vector3(0.04, 0.6, 1.3), Color(0.06, 0.1, 0.2))
	_label(gname, Vector3(xw - s * 0.2, FLOOR + 3.25, zd), Vector3(-s, 0, 0), 0.42, Color(1.0, 0.85, 0.3))
	# keep the glazing out of the doorway
	obstacles.append({"c": Vector2(s * (depth * 0.5 - 0.3), zd), "h": Vector2(0.0, 0.0), "door": true})


func _podium(p: Vector3, s: float, gname: String) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	# a curved-front desk: wood-look front, white solid-surface top, two agent screens
	v.add_rounded_box(p + Vector3(0, 0.52, 0), Vector3(1.0, 1.04, 2.6), Color(0.62, 0.46, 0.3, 0.75), 0.18, 8, 4)
	v.add_box(p + Vector3(0, 1.07, 0), Vector3(1.15, 0.05, 2.8), Color(0.95, 0.95, 0.93, 0.55))
	for dz in [-0.6, 0.6]:
		v.add_box(p + Vector3(s * 0.25, 1.32, dz), Vector3(0.04, 0.38, 0.55), Color(0.08, 0.08, 0.09, 0.55))
		em.add_box(p + Vector3(s * 0.22, 1.32, dz), Vector3(0.01, 0.32, 0.5), Color(0.2, 0.35, 0.6))
	# customer-facing screen on a post
	v.add_box(p + Vector3(-s * 0.7, 1.0, 1.7), Vector3(0.08, 2.0, 0.08), Color(0.7, 0.72, 0.75, 0.3))
	v.add_box(p + Vector3(-s * 0.7, 2.25, 1.7), Vector3(0.1, 0.7, 1.15), Color(0.06, 0.06, 0.07, 0.55))
	em.add_box(p + Vector3(-s * 0.76, 2.25, 1.7), Vector3(0.01, 0.62, 1.05), Color(0.05, 0.12, 0.3))
	var l := _label("%s\n—" % gname, p + Vector3(-s * 0.77, 2.25, 1.7), Vector3(-s, 0, 0), 0.11, Color(1, 1, 1), 48)
	l.set_meta("gate_screen", gname)
	_rect(Vector2(p.x, p.z), Vector2(0.65, 1.5))


func _gate_sign(p: Vector3, gname: String) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	v.add_box(p + Vector3(0, 1.4, 0), Vector3(0.05, 2.0, 0.05), Color(0.6, 0.62, 0.65, 0.3))
	v.add_box(p, Vector3(0.2, 1.3, 3.4), Color(0.05, 0.08, 0.16, 0.55))
	em.add_box(p + Vector3(0, -0.45, 0), Vector3(0.21, 0.08, 3.3), Color(0.95, 0.75, 0.2))
	for sx in [-1.0, 1.0]:
		_label(gname, p + Vector3(sx * 0.11, 0.1, -0.95), Vector3(sx, 0, 0), 0.75, Color(1, 1, 1))
		var info := _label("", p + Vector3(sx * 0.11, 0.05, 0.6), Vector3(sx, 0, 0), 0.2, Color(0.85, 0.9, 1.0), 48)
		info.set_meta("gate_sign", gname)


func _gate_seating(s: float, bnd: Dictionary, zg: float, zd: float, pod: Vector3, gname: String) -> void:
	## Rows of beam seating parallel to the windows, back to back, in a carpeted lounge.
	var x_out := s * (depth * 0.5 - 7.0)
	var x_in := float(bnd.gate_in) + s * 2.5
	var half := (82.0 if hub else 68.0) * 0.36
	var z0 := zg - half
	var z1 := zg + half
	_floor_quad(_b("carpet"), x_out + s * 1.0, x_in - s * 1.0, z0 - 1.0, z1 + 1.0, FLOOR + 0.015)
	var xfs: Array[Transform3D] = []
	var row := 0
	var x := x_out
	while (x - x_in) * s > 0.0:
		var facing := s if row % 2 == 0 else -s          # alternate rows face the windows / away
		var seg_seats := 7
		var seg_len := seg_seats * 0.56
		var z := z0
		while z + seg_len <= z1:
			# leave the podium and the door approach clear
			var zc := z + seg_len * 0.5
			var near_pod := absf(zc - pod.z) < seg_len * 0.5 + 2.2 and absf(x - pod.x) < 4.0
			var near_door := absf(zc - zd) < seg_len * 0.5 + 2.0 and absf(x - s * depth * 0.5) < 9.0
			if not near_pod and not near_door:
				for k in seg_seats:
					var sp := Vector3(x, FLOOR, z + 0.28 + k * 0.56)
					var dir := Vector3(facing, 0, 0)
					var xf := Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), sp)
					xfs.append(xf)
					seats.append({"xf": xf, "gate": gname, "taken": false})
				_rect(Vector2(x, zc), Vector2(0.42, seg_len * 0.5))
			z += seg_len + 1.6
		x -= s * (0.95 if row % 2 == 0 else 2.6)      # back-to-back pair, then an aisle
		row += 1
	_mm(_seat_unit(), xfs, "vcol")
	# planters at the lounge corners
	var plants: Array[Transform3D] = []
	for pz in [z0 - 1.5, z1 + 1.5]:
		var pp := Vector3(x_out - s * 1.5, FLOOR, pz)
		plants.append(Transform3D(Basis(Vector3.UP, pz * 0.37), pp))
		_circle(Vector2(pp.x, pp.z), 0.6)
	_mm(_plant(), plants, "vcol")


static func _floor_quad(mb: MeshBuilder, xa: float, xb: float, za: float, zb: float, y: float) -> void:
	var x0 := minf(xa, xb)
	var x1 := maxf(xa, xb)
	var z0 := minf(za, zb)
	var z1 := maxf(za, zb)
	mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Color.WHITE)


func _mm(mesh: Mesh, xfs: Array[Transform3D], key: String) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material(key)
	mmi.visibility_range_end = 260.0
	add_child(mmi)


# ================================================================== furniture meshes
static func _seat_unit() -> ArrayMesh:
	## One seat of a beam row (faces -Z, origin on the floor under the seat): leather cushions,
	## a chrome beam, leg and armrest shared with the neighbour.
	if _seat_mesh:
		return _seat_mesh
	var mb := MeshBuilder.new()
	var leather := Color(0.1, 0.1, 0.11, 0.75)
	var chrome := Color(0.75, 0.76, 0.78, 0.3)
	mb.add_box(Vector3(0, 0.3, 0.12), Vector3(0.56, 0.06, 0.07), chrome)
	mb.add_box(Vector3(0.28, 0.15, 0.12), Vector3(0.05, 0.3, 0.05), chrome)
	mb.add_box(Vector3(0.28, 0.01, 0.12), Vector3(0.09, 0.02, 0.5), chrome)
	mb.add_rounded_box(Vector3(0, 0.43, -0.03), Vector3(0.5, 0.08, 0.48), leather, 0.35, 6, 4)
	mb.add_rounded_box(Vector3(0, 0.75, 0.22), Vector3(0.5, 0.56, 0.07), leather, 0.35, 6, 4, Basis(Vector3.RIGHT, deg_to_rad(-9.0)))
	mb.add_box(Vector3(0, 0.36, 0.0), Vector3(0.46, 0.04, 0.42), chrome)
	mb.add_box(Vector3(0.28, 0.62, -0.02), Vector3(0.05, 0.03, 0.42), chrome)
	mb.add_box(Vector3(0.28, 0.48, 0.12), Vector3(0.03, 0.28, 0.03), chrome)
	_seat_mesh = mb.commit()
	return _seat_mesh


static func _plant() -> ArrayMesh:
	if _plant_mesh:
		return _plant_mesh
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0.75, 0), 0.42, 0.5, 14, Color(0.2, 0.21, 0.23, 0.75))
	mb.add_cylinder(Vector3(0, 0.74, 0), Vector3(0, 0.76, 0), 0.46, 0.46, 14, Color(0.25, 0.18, 0.12))
	mb.add_cylinder(Vector3(0, 0.75, 0), Vector3(0, 1.7, 0), 0.05, 0.04, 6, Color(0.35, 0.26, 0.18))
	var greens := [Color(0.18, 0.36, 0.16), Color(0.22, 0.42, 0.18), Color(0.15, 0.3, 0.14)]
	for k in 5:
		var a := float(k) * TAU / 5.0
		var p := Vector3(cos(a) * 0.32, 1.7 + 0.18 * float(k % 2), sin(a) * 0.32)
		mb.add_sphere(p, Vector3(0.42, 0.3, 0.42), 8, 5, greens[k % 3])
	mb.add_sphere(Vector3(0, 2.05, 0), Vector3(0.45, 0.35, 0.45), 8, 5, greens[1])
	_plant_mesh = mb.commit()
	return _plant_mesh


static func _table() -> ArrayMesh:
	if _table_mesh:
		return _table_mesh
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, 0.72, 0), Vector3(0, 0.75, 0), 0.4, 0.4, 16, Color(0.92, 0.91, 0.88, 0.55))
	mb.add_cylinder(Vector3(0, 0.02, 0), Vector3(0, 0.72, 0), 0.04, 0.04, 8, Color(0.2, 0.2, 0.22, 0.3))
	mb.add_cylinder(Vector3(0, 0.0, 0), Vector3(0, 0.03, 0), 0.25, 0.25, 12, Color(0.2, 0.2, 0.22, 0.3))
	_table_mesh = mb.commit()
	return _table_mesh


static func _chair() -> ArrayMesh:
	if _chair_mesh:
		return _chair_mesh
	var mb := MeshBuilder.new()
	var wood := Color(0.55, 0.38, 0.24, 0.75)
	var steel := Color(0.15, 0.15, 0.16, 0.3)
	mb.add_box(Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42), wood)
	mb.add_box(Vector3(0, 0.72, 0.19), Vector3(0.42, 0.34, 0.03), wood)
	for lx in [-0.18, 0.18]:
		for lz in [-0.18, 0.18]:
			mb.add_box(Vector3(lx, 0.22, lz), Vector3(0.025, 0.45, 0.025), steel)
	_chair_mesh = mb.commit()
	return _chair_mesh


# ================================================================== retail band
func _retail() -> void:
	## Shops, cafés, a lounge and toilets along the inner side of each concourse.
	var r := U.rng(U.hash_str(icao + "retail"))
	var bi := r.randi() % BRANDS.size()
	for sd in sides:
		var s: float = sd.s
		var bnd := _band(s)
		var x_front: float = float(bnd.conc_in)                  # storefront line
		var x_back: float = x_front - s * (float(bnd.rw) - 1.0)
		if sides.size() == 2:
			x_back = x_front - s * minf(float(bnd.rw) - 1.0, depth * 0.5 - 1.0 - absf(x_front))
		var z := -length * 0.5 + 14.0
		var lounge_done := false
		var cafe_tables: Array[Transform3D] = []
		var cafe_chairs: Array[Transform3D] = []
		while z < length * 0.5 - 30.0:
			var w := r.randf_range(14.0, 22.0)
			# leave the security exit clear on the landside
			if not sec.is_empty() and String(sec.axis) == "x" and z + w > float(sec.gap0) - 6.0 and z < float(sec.gap1) + 6.0:
				z = float(sec.gap1) + 8.0
				continue
			# end-on security: keep the lanes and the space either side of them clear
			if not sec.is_empty() and String(sec.axis) == "z" and z + w > float(sec.at) - 9.0 and z < float(sec.at) + 9.0:
				z = float(sec.at) + 11.0
				continue
			var brand: Array = BRANDS[bi % BRANDS.size()]
			bi += 1
			var kind := String(brand[1])
			if not lounge_done and hub and r.randf() < 0.25:
				brand = ["Skyfall Lounge", "lounge", Color(0.1, 0.2, 0.42)]
				kind = "lounge"
				lounge_done = true
			_shop_unit(s, x_front, x_back, z, z + w, String(brand[0]), kind, brand[2])
			if kind == "cafe":
				# tables spill out into the concourse edge
				for k in int(w / 3.2):
					var tp := Vector3(x_front + s * 2.4, FLOOR, z + 1.6 + k * 3.2)
					cafe_tables.append(Transform3D(Basis.IDENTITY, tp))
					_circle(Vector2(tp.x, tp.z), 0.75)
					for cs in [-1.0, 1.0]:
						var cp := tp + Vector3(0, 0, cs * 0.62)
						var dir := Vector3(0, 0, -cs)
						cafe_chairs.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), cp))
						seats.append({"xf": Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), cp), "gate": "", "taken": false, "cafe": true})
			z += w + r.randf_range(6.0, 12.0)
		_mm(_table(), cafe_tables, "vcol")
		_mm(_chair(), cafe_chairs, "vcol")


func _shop_unit(s: float, x_front: float, x_back: float, z0: float, z1: float, title: String, kind: String, brand_col: Color) -> void:
	var v := _b("vcol")
	var wall := _b("wall")
	var em := _b("emit")
	var h := 4.2
	var xm := (x_front + x_back) * 0.5
	var dx := absf(x_front - x_back)
	var zm := (z0 + z1) * 0.5
	var w := z1 - z0
	# back and side walls (panelled), a soffit over the front carrying the fascia
	wall.add_box(Vector3(x_back, FLOOR + h * 0.5, zm), Vector3(0.2, h, w), Color.WHITE, true)
	for zz in [z0, z1]:
		wall.add_box(Vector3(xm, FLOOR + h * 0.5, zz), Vector3(dx, h, 0.2), Color.WHITE, true)
	v.add_box(Vector3(xm, FLOOR + h, zm), Vector3(dx, 0.1, w), Color(0.85, 0.85, 0.84))
	v.add_box(Vector3(x_front, FLOOR + h - 0.45, zm), Vector3(0.25, 0.9, w), Color(0.12, 0.12, 0.13, 0.55))
	var fascia_col := brand_col.lightened(0.15)
	em.add_box(Vector3(x_front + s * 0.13, FLOOR + h - 0.45, zm), Vector3(0.02, 0.06, w - 0.6), fascia_col)
	_label(title, Vector3(x_front + s * 0.14, FLOOR + h - 0.42, zm), Vector3(s, 0, 0), 0.42, Color(1, 1, 1))
	# lit interior: ceiling panel and coloured accent wall
	em.add_box(Vector3(xm, FLOOR + h - 0.06, zm), Vector3(dx - 1.0, 0.03, w - 1.0), Color(0.95, 0.93, 0.88))
	v.add_box(Vector3(x_back + s * 0.12, FLOOR + 2.0, zm), Vector3(0.04, 2.6, w - 1.2), Color(brand_col, 0.75))
	var glass := _b("frosted" if kind == "lounge" else "glass")
	var door0 := zm - 1.2
	var door1 := zm + 1.2
	match kind:
		"cafe":
			# open front: counter, espresso machine, pastry case, menu boards
			v.add_rounded_box(Vector3(xm + s * dx * 0.15, FLOOR + 0.55, zm), Vector3(0.9, 1.1, w * 0.6), Color(0.28, 0.2, 0.14, 0.75), 0.15, 8, 4)
			v.add_box(Vector3(xm + s * dx * 0.15, FLOOR + 1.12, zm), Vector3(1.0, 0.05, w * 0.62), Color(0.9, 0.9, 0.88, 0.55))
			v.add_box(Vector3(xm + s * dx * 0.15, FLOOR + 1.38, zm - w * 0.15), Vector3(0.55, 0.45, 0.8), Color(0.75, 0.76, 0.78, 0.3))
			em.add_box(Vector3(xm + s * dx * 0.15, FLOOR + 1.3, zm + w * 0.18), Vector3(0.6, 0.35, 1.4), Color(0.95, 0.85, 0.6))
			for k in 3:
				em.add_box(Vector3(x_back + s * 0.16, FLOOR + 2.9, zm + (k - 1) * 1.6), Vector3(0.02, 0.8, 1.4), Color(0.12, 0.1, 0.08))
			_rect(Vector2(xm, zm), Vector2(dx * 0.5, w * 0.5))
			_spot("cafe", Vector3(x_front + s * 0.8, FLOOR, zm), "Buy a coffee at %s" % title, {"title": title})
		"wc":
			wall.add_box(Vector3(x_front, FLOOR + 1.6, zm), Vector3(0.2, 3.2, w), Color.WHITE, true)
			for dz in [-w * 0.25, w * 0.25]:
				v.add_box(Vector3(x_front + s * 0.12, FLOOR + 1.1, zm + dz), Vector3(0.05, 2.2, 1.2), Color(0.3, 0.33, 0.38, 0.75))
			_label("WC", Vector3(x_front + s * 0.14, FLOOR + 2.7, zm), Vector3(s, 0, 0), 0.4, Color(1, 1, 1))
			_rect(Vector2(xm, zm), Vector2(dx * 0.5, w * 0.5))
			_spot("toilet", Vector3(x_front + s * 0.8, FLOOR, zm + w * 0.25), "Use the toilets")
		_:
			# glazed storefront with a door, shelving and a till
			for seg in [[z0, door0], [door1, z1]]:
				var a: float = seg[0]
				var b2: float = seg[1]
				glass.add_quad(Vector3(x_front, FLOOR, a), Vector3(x_front, FLOOR, b2), Vector3(x_front, FLOOR + h - 0.9, b2), Vector3(x_front, FLOOR + h - 0.9, a), Color.WHITE)
				v.add_box(Vector3(x_front, FLOOR + 0.04, (a + b2) * 0.5), Vector3(0.08, 0.08, b2 - a), Color(0.3, 0.3, 0.32, 0.3))
			var r := U.rng(U.hash_str(title))
			var n_sh := maxi(int(w / 3.0), 2)
			for k in n_sh:
				var zz := z0 + 1.2 + (float(k) + 0.5) * (w - 2.4) / n_sh
				var sx := x_back + s * 0.6
				v.add_box(Vector3(sx, FLOOR + 1.0, zz), Vector3(0.5, 2.0, 2.2), Color(0.86, 0.85, 0.82, 0.75))
				for shelf in 4:
					var prod := Color.from_hsv(r.randf(), r.randf_range(0.35, 0.8), r.randf_range(0.5, 0.95))
					v.add_box(Vector3(sx + s * 0.05, FLOOR + 0.35 + shelf * 0.45, zz), Vector3(0.4, 0.26, 2.0), prod)
			for k2 in int(dx / 3.5):
				var gp := Vector3(x_front - s * (2.5 + k2 * 3.0), FLOOR, zm + (k2 % 2) * 2.0 - 1.0)
				v.add_box(gp + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 1.8), Color(0.88, 0.87, 0.84, 0.75))
			v.add_box(Vector3(x_front - s * 1.6, FLOOR + 0.5, zm + w * 0.3), Vector3(0.7, 1.0, 1.6), Color(0.15, 0.15, 0.16, 0.55))
			_rect(Vector2(xm, zm), Vector2(dx * 0.5, w * 0.5))
			if kind == "lounge":
				_spot("lounge", Vector3(x_front + s * 0.8, FLOOR, zm), "%s - members and premium passengers" % title)
			else:
				_spot("shop", Vector3(x_front + s * 0.8, FLOOR, zm), "Browse %s" % title, {"title": title})


# ================================================================== security, check-in, kerb
func _security_and_landside(layout: Dictionary) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	var lanes := 6 if hub else 3
	var lane_w := 4.0
	if land_s != 0.0:
		# a line along the building between the landside hall and the shops
		var bnd := _band(-land_s)
		var x_line: float = float(bnd.retail_in) + land_s * 1.0
		var gap := lanes * lane_w
		sec = {"axis": "x", "at": x_line, "gap0": -gap * 0.5, "gap1": gap * 0.5, "lanes": []}
		_partition_x(x_line, -length * 0.5, -gap * 0.5)
		_partition_x(x_line, gap * 0.5, length * 0.5)
		for k in lanes:
			var zc := -gap * 0.5 + (k + 0.5) * lane_w
			sec.lanes.append(zc)
			_lane(Vector3(x_line, FLOOR, zc), Vector3(-land_s, 0, 0), Vector3(0, 0, 1), k)
		_hanging_sign(Vector3(x_line + land_s * 6.0, FLOOR + 4.6, 0), Vector3(land_s, 0, 0), "SECURITY  •  ALL GATES", 7.0)
		# check-in islands in the hall, entrances in the landside glass
		var x_wall := land_s * depth * 0.5
		var hall_w := absf(x_wall - x_line)
		var isl_x := x_wall - land_s * minf(hall_w * 0.45, 14.0)
		_checkin_islands(isl_x, land_s)
		for ez in [-length * 0.3, 0.0, length * 0.3]:
			_entrance(Vector3(x_wall - land_s * 0.3, FLOOR, ez), land_s)
		entrance = Vector3(x_wall - land_s * 3.0, FLOOR, 0.0)
	else:
		# midfield building: entry and security across one end
		var z_line := -length * 0.5 + 48.0
		var gap2 := lanes * lane_w
		sec = {"axis": "z", "at": z_line, "gap0": -gap2 * 0.5, "gap1": gap2 * 0.5, "lanes": []}
		_partition_z(z_line, -depth * 0.5, -gap2 * 0.5)
		_partition_z(z_line, gap2 * 0.5, depth * 0.5)
		for k in lanes:
			var xc := -gap2 * 0.5 + (k + 0.5) * lane_w
			sec.lanes.append(xc)
			_lane(Vector3(xc, FLOOR, z_line), Vector3(0, 0, 1), Vector3(1, 0, 0), k)
		_hanging_sign(Vector3(0, FLOOR + 4.6, z_line - 6.0), Vector3(0, 0, -1), "SECURITY  •  ALL GATES", 7.0)
		_checkin_islands_z(-length * 0.5 + 20.0)
		entrance = Vector3(0, FLOOR, -length * 0.5 + 4.0)
		_entrance(Vector3(0, FLOOR, -length * 0.5 + 0.3), 0.0)


func _partition_x(x: float, z0: float, z1: float) -> void:
	if z1 - z0 < 0.5:
		return
	_b("frosted").add_quad(Vector3(x, FLOOR, z0), Vector3(x, FLOOR, z1), Vector3(x, FLOOR + 2.6, z1), Vector3(x, FLOOR + 2.6, z0), Color.WHITE)
	_b("vcol").add_box(Vector3(x, FLOOR + 2.65, (z0 + z1) * 0.5), Vector3(0.08, 0.1, z1 - z0), Color(0.6, 0.62, 0.65, 0.3))
	_rect(Vector2(x, (z0 + z1) * 0.5), Vector2(0.15, (z1 - z0) * 0.5))


func _partition_z(z: float, x0: float, x1: float) -> void:
	if x1 - x0 < 0.5:
		return
	_b("frosted").add_quad(Vector3(x0, FLOOR, z), Vector3(x1, FLOOR, z), Vector3(x1, FLOOR + 2.6, z), Vector3(x0, FLOOR + 2.6, z), Color.WHITE)
	_b("vcol").add_box(Vector3((x0 + x1) * 0.5, FLOOR + 2.65, z), Vector3(x1 - x0, 0.1, 0.08), Color(0.6, 0.62, 0.65, 0.3))
	_rect(Vector2((x0 + x1) * 0.5, z), Vector2((x1 - x0) * 0.5, 0.15))


func _lane(c: Vector3, through: Vector3, across: Vector3, k: int) -> void:
	## One screening lane: divesting table, X-ray tunnel, reclaim belt, walk-through arch, barriers.
	var v := _b("vcol")
	var em := _b("emit")
	var basis := Basis(Vector3.UP.cross(through).normalized(), Vector3.UP, through)   # x across the lane, z the way people walk
	var xf := Transform3D(basis, c)
	var off := -1.05                                      # belts run on one side of the lane
	v.xf = xf
	v.add_box(Vector3(off, 0.45, -4.6), Vector3(0.8, 0.9, 3.0), Color(0.55, 0.57, 0.6, 0.3))     # divest table
	v.add_box(Vector3(off, 0.75, -1.6), Vector3(1.05, 1.5, 3.0), Color(0.82, 0.83, 0.84, 0.55))  # X-ray body
	v.add_box(Vector3(off, 0.8, -3.12), Vector3(0.7, 0.45, 0.04), Color(0.1, 0.1, 0.1, 0.75))    # curtain
	v.add_box(Vector3(off, 0.45, 1.6), Vector3(0.8, 0.9, 3.4), Color(0.55, 0.57, 0.6, 0.3))      # reclaim
	for side in [-1.0, 1.0]:
		v.add_box(Vector3(0.55 + side * 0.48, 1.05, 0.0), Vector3(0.12, 2.1, 0.5), Color(0.75, 0.76, 0.78, 0.55))
	v.add_box(Vector3(0.55, 2.15, 0.0), Vector3(1.1, 0.14, 0.5), Color(0.75, 0.76, 0.78, 0.55))
	v.add_box(Vector3(1.95, 0.5, 0.0), Vector3(0.06, 1.0, 9.0), Color(0.3, 0.32, 0.36, 0.55))      # lane divider
	for i in 4:
		v.add_box(Vector3(off, 0.95, -5.6 + i * 0.12), Vector3(0.55, 0.1, 0.4), Color(0.2, 0.22, 0.26, 0.75))   # tray stack
	v.xf = Transform3D.IDENTITY
	em.xf = xf
	em.add_box(Vector3(off - 0.5, 1.4, -1.6), Vector3(0.02, 0.3, 0.5), Color(0.2, 0.9, 0.4))
	em.add_box(Vector3(0.55, 2.3, 0.0), Vector3(0.6, 0.12, 0.02), Color(0.3, 0.95, 0.4))
	em.xf = Transform3D.IDENTITY
	var ctr := xf * Vector3(off, 0, -1.6)
	_rect(Vector2(ctr.x, ctr.z), Vector2(absf((basis * Vector3(0.6, 0, 4.6)).x), absf((basis * Vector3(0.6, 0, 4.6)).z)))
	var div := xf * Vector3(1.95, 0, 0)
	_rect(Vector2(div.x, div.z), Vector2(absf((basis * Vector3(0.05, 0, 4.5)).x), absf((basis * Vector3(0.05, 0, 4.5)).z)))
	_spot("security", xf * Vector3(0.55, 0, -2.5), "Go through security (lane %d)" % (k + 1), {"lane": k, "exit": xf * Vector3(0.55, 0, 2.5)})


func _checkin_islands(x: float, ls: float) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	var codes := _airlines_here()
	var n := maxi(codes.size(), 1)
	var span := minf(length * 0.8, n * 34.0)
	for i in n:
		var code: String = codes[i % codes.size()] if not codes.is_empty() else "SKF"
		var al := Airlines.get_al(code)
		var cols := Airlines.livery_colors(code)
		var zc := -span * 0.5 + (i + 0.5) * span / n
		var w := minf(span / n - 6.0, 26.0)
		# backdrop wall with the airline name, a row of desks with screens, a baggage belt
		v.add_box(Vector3(x, FLOOR + 1.8, zc), Vector3(0.4, 3.6, w), Color(cols.main, 0.75) if cols.has("main") else Color(0.2, 0.3, 0.5, 0.75))
		_label(String(al.get("name", code)).to_upper(), Vector3(x - ls * 0.22, FLOOR + 3.1, zc), Vector3(-ls, 0, 0), 0.55, Color(1, 1, 1))
		v.add_box(Vector3(x - ls * 0.9, FLOOR + 0.25, zc), Vector3(0.9, 0.5, w - 1.0), Color(0.25, 0.26, 0.28, 0.55))
		var desks := int(w / 2.2)
		for k in desks:
			var dz := zc - w * 0.5 + (k + 0.5) * w / desks
			v.add_box(Vector3(x - ls * 1.9, FLOOR + 0.55, dz), Vector3(0.7, 1.1, 1.6), Color(0.88, 0.88, 0.86, 0.55))
			em.add_box(Vector3(x - ls * 2.27, FLOOR + 1.45, dz), Vector3(0.02, 0.3, 0.5), Color(0.15, 0.3, 0.6))
		_rect(Vector2(x - ls * 1.2, zc), Vector2(1.3, w * 0.5))
		_spot("checkin", Vector3(x - ls * 3.2, FLOOR, zc), "Check in with %s" % al.get("name", code), {"airline": code})
		# queue lanes in front
		_queue_posts(Vector3(x - ls * 5.5, FLOOR, zc), Vector3(-ls, 0, 0), w * 0.6)


func _checkin_islands_z(z: float) -> void:
	var codes := _airlines_here()
	var n := maxi(codes.size(), 1)
	for i in n:
		var code: String = codes[i % codes.size()] if not codes.is_empty() else "SKF"
		var al := Airlines.get_al(code)
		var xc := -depth * 0.35 + (i + 0.5) * depth * 0.7 / n
		var w := minf(depth * 0.7 / n - 6.0, 22.0)
		var v := _b("vcol")
		v.add_box(Vector3(xc, FLOOR + 1.8, z), Vector3(w, 3.6, 0.4), Color(0.18, 0.28, 0.5, 0.75))
		_label(String(al.get("name", code)).to_upper(), Vector3(xc, FLOOR + 3.1, z + 0.22), Vector3(0, 0, 1), 0.55, Color(1, 1, 1))
		_rect(Vector2(xc, z + 1.0), Vector2(w * 0.5, 1.4))
		_spot("checkin", Vector3(xc, FLOOR, z + 3.2), "Check in with %s" % al.get("name", code), {"airline": code})


func _airlines_here() -> Array:
	var out := []
	for f in WorldSim.schedule_for_day(WorldSim.day_index()):
		if String(f.from) == icao and not bool(f.get("cargo", false)) and not String(f.airline) in out:
			out.append(String(f.airline))
	return out.slice(0, 4 if hub else 2)


func _queue_posts(c: Vector3, toward: Vector3, w: float) -> void:
	## Stanchions with belts: a short serpentine in front of a desk row.
	var v := _b("vcol")
	var across := Vector3(-toward.z, 0, toward.x)
	var rows := 3
	for rr in rows:
		var base := c + toward * (rr * 1.3)
		var n := int(w / 1.6)
		for k in n + 1:
			var p := base + across * (-w * 0.5 + k * w / n)
			v.add_cylinder(p, p + Vector3(0, 0.95, 0), 0.03, 0.03, 6, Color(0.75, 0.76, 0.78, 0.3), true)
			v.add_cylinder(p, p + Vector3(0, 0.02, 0), 0.16, 0.16, 10, Color(0.2, 0.2, 0.22, 0.3), true)
			if k < n and not (rr % 2 == 0 and k == n - 1) and not (rr % 2 == 1 and k == 0):
				var q := base + across * (-w * 0.5 + (k + 0.5) * w / n)
				var seg := across * (w / n)
				v.add_box(q + Vector3(0, 0.9, 0), Vector3(absf(seg.x) + 0.02, 0.05, absf(seg.z) + 0.02), Color(0.1, 0.15, 0.35, 0.75))


func _entrance(p: Vector3, ls: float) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	var along := Vector3(0, 0, 1) if ls != 0.0 else Vector3(1, 0, 0)
	for k in [-1.0, 1.0]:
		v.add_box(p + along * k * 1.8 + Vector3(0, 1.4, 0), Vector3(0.25, 2.8, 0.25) if ls != 0.0 else Vector3(0.25, 2.8, 0.25), Color(0.25, 0.27, 0.3, 0.3))
	v.add_box(p + Vector3(0, 2.9, 0), Vector3(0.3, 0.25, 3.9) if ls != 0.0 else Vector3(3.9, 0.25, 0.3), Color(0.25, 0.27, 0.3, 0.3))
	em.add_box(p + Vector3(0, 3.35, 0) - (Vector3(ls * 0.2, 0, 0) if ls != 0.0 else Vector3(0, 0, -0.2)), Vector3(0.02, 0.45, 3.0) if ls != 0.0 else Vector3(3.0, 0.45, 0.02), Color(0.1, 0.2, 0.45))
	_label("DEPARTURES", p + Vector3(0, 3.35, 0) - (Vector3(ls * 0.23, 0, 0) if ls != 0.0 else Vector3(0, 0, -0.23)), Vector3(-ls, 0, 0) if ls != 0.0 else Vector3(0, 0, 1), 0.3, Color(1, 1, 1))


func _hanging_sign(p: Vector3, facing: Vector3, text: String, w: float) -> void:
	var v := _b("vcol")
	var em := _b("emit")
	var across := Vector3(-facing.z, 0, facing.x)
	var size := Vector3(absf(across.x) * w + absf(facing.x) * 0.2, 0.9, absf(across.z) * w + absf(facing.z) * 0.2)
	v.add_box(p, size, Color(0.05, 0.08, 0.16, 0.55))
	for k in [-0.4, 0.4]:
		var rod = p + across * w * k
		v.add_box(Vector3(rod.x, (p.y + ceil_h) * 0.5 + 0.2, rod.z), Vector3(0.04, ceil_h - p.y - 0.4, 0.04), Color(0.6, 0.62, 0.65, 0.3))
	em.add_box(p + Vector3(0, -0.36, 0), Vector3(size.x * 0.98 + 0.01, 0.06, size.z * 0.98 + 0.01), Color(0.95, 0.75, 0.2))
	_label(text, p + facing.normalized() * 0.11 + Vector3(0, 0.05, 0), facing, 0.42, Color(1, 1, 1))
	_label(text, p - facing.normalized() * 0.11 + Vector3(0, 0.05, 0), -facing, 0.42, Color(1, 1, 1))


func _wayfinding() -> void:
	## Overhead signs along each concourse pointing to the gate ranges either way.
	for sd in sides:
		var s: float = sd.s
		var bnd := _band(s)
		var names := []
		var zs := []
		for g in gates:
			if float(g.s) == s:
				names.append(String(g.name))
				zs.append(float(g.z))
		if names.is_empty():
			continue
		var x := (float(bnd.gate_in) + float(bnd.conc_in)) * 0.5
		var z := -length * 0.5 + 40.0
		while z < length * 0.5 - 20.0:
			var lo := []
			var hi := []
			for i in names.size():
				(lo if float(zs[i]) < z else hi).append(names[i])
			var txt := ""
			if not lo.is_empty():
				txt += "< %s-%s     " % [lo[0], lo[lo.size() - 1]] if lo.size() > 1 else "< %s     " % lo[0]
			if not hi.is_empty():
				txt += "%s-%s >" % [hi[0], hi[hi.size() - 1]] if hi.size() > 1 else "%s >" % hi[0]
			_hanging_sign(Vector3(x, FLOOR + 4.8, z), Vector3(0, 0, -1), txt, 6.0)
			z += 110.0 if hub else 80.0


# ================================================================== departure boards
func _boards() -> void:
	## Big departure screens where people stop to look: past security and in the hall.
	var places := []
	if not sec.is_empty():
		if String(sec.axis) == "x":
			var x_after := float(sec.at) - land_s * 9.0
			places.append([Vector3(x_after, FLOOR, 9.0), Vector3(-land_s, 0, 0)])
			places.append([Vector3(float(sec.at) + land_s * 8.0, FLOOR, -9.0 - float(sec.gap1)), Vector3(land_s, 0, 0)])
		else:
			places.append([Vector3(9.0, FLOOR, float(sec.at) + 9.0), Vector3(0, 0, 1)])
	for pl in places:
		var p: Vector3 = pl[0]
		var f: Vector3 = pl[1]
		var across := Vector3(-f.z, 0, f.x)
		var v := _b("vcol")
		var em := _b("emit")
		var w := 5.6
		var h := 3.3
		var base := p + Vector3(0, 1.1, 0)
		v.add_box(base + Vector3(0, h * 0.5, 0) - f * 0.12, Vector3(absf(across.x) * (w + 0.3) + absf(f.x) * 0.2, h + 0.3, absf(across.z) * (w + 0.3) + absf(f.z) * 0.2), Color(0.12, 0.13, 0.15, 0.55))
		em.add_box(base + Vector3(0, h * 0.5, 0) - f * 0.01, Vector3(absf(across.x) * w + absf(f.x) * 0.02, h, absf(across.z) * w + absf(f.z) * 0.02), Color(0.015, 0.025, 0.06))
		for k in [-1.0, 1.0]:
			v.add_box(p + across * k * 2.2 + Vector3(0, 0.55, 0) - f * 0.12, Vector3(0.18, 1.1, 0.18), Color(0.2, 0.21, 0.23, 0.3))
		var vright := Vector3.UP.cross(f).normalized()     # the reader's right = the label's +X
		var top := base + Vector3(0, h - 0.25, 0) + f * 0.03 - vright * (w * 0.5 - 0.2)
		var title := _label("DEPARTURES                     %s" % Airports.get_ap(icao).get("short", icao), top, f, 0.16, Color(1.0, 0.82, 0.3), 48, true)
		var lines: Array[Label3D] = []
		for i in 11:
			var lp := top - Vector3(0, 0.36 + i * 0.255, 0)
			lines.append(_label("", lp, f, 0.12, Color(0.92, 0.95, 1.0), 48, true))
		_fids.append({"lines": lines, "title": title})
		_spot("fids", p + f * 2.2, "Read the departures board", {"board": base + Vector3(0, h * 0.5, 0)})
		_rect(Vector2(p.x, p.z), Vector2(absf(across.x) * w * 0.5 + 0.4, absf(across.z) * w * 0.5 + 0.4))


func departures(count: int = 11) -> Array:
	## The next departures from this airport, as the boards show them.
	var out := []
	var now := WorldSim.clock
	for d in [WorldSim.day_index(), WorldSim.day_index() + 1]:
		for f in WorldSim.schedule_for_day(d):
			if String(f.from) != icao or bool(f.get("cargo", false)) or bool(f.get("training", false)):
				continue
			var dep := float(f.dep) + float(f.get("delay", 0.0))
			if dep < now - 15.0 * 60.0:
				continue
			out.append(f)
	out.sort_custom(func(a, b): return float(a.dep) < float(b.dep))
	return out.slice(0, count)


static func status_for(f: Dictionary, now: float) -> String:
	var to_go := (float(f.dep) + float(f.get("delay", 0.0)) - now) / 60.0
	if to_go < -2.0:
		return "DEPARTED"
	if to_go < 12.0:
		return "GATE CLOSED"
	if to_go < 40.0:
		return "BOARDING"
	if float(f.get("delay", 0.0)) > 600.0:
		return "DELAYED %s" % U.fmt_clock(float(f.dep) + float(f.delay))
	if to_go < 75.0:
		return "GO TO GATE"
	return "ON TIME"


func refresh_boards(session_flight: Dictionary = {}) -> void:
	var now := WorldSim.clock
	var deps := departures(11)
	if not session_flight.is_empty():
		var found := false
		for f in deps:
			if String(f.get("number", "")) == String(session_flight.get("number", "")):
				found = true
		if not found:
			deps.push_front(session_flight)
			deps = deps.slice(0, 11)
	for bd in _fids:
		var lines: Array = bd.lines
		for i in lines.size():
			var l: Label3D = lines[i]
			if i >= deps.size():
				l.text = ""
				continue
			var f: Dictionary = deps[i]
			var dest := String(Airports.get_ap(String(f.to)).get("city", f.to)).to_upper()
			var st := status_for(f, now)
			l.text = "%s  %-7s %-14s %-4s %s" % [U.fmt_clock(float(f.dep)), String(f.number), dest.left(14), String(f.get("gate", "")), st]
			l.modulate = Color(1.0, 0.85, 0.3) if st == "BOARDING" else (Color(1.0, 0.45, 0.35) if st.begins_with("DELAY") or st == "GATE CLOSED" else Color(0.92, 0.95, 1.0))
	# gate screens and signs show the next flight from each gate
	var by_gate := {}
	for f2 in departures(40):
		var gname := String(f2.get("gate", ""))
		if gname != "" and not by_gate.has(gname):
			by_gate[gname] = f2
	if not session_flight.is_empty():
		by_gate[String(session_flight.get("gate", ""))] = session_flight
	for c in get_children():
		if c is Label3D and (c.has_meta("gate_screen") or c.has_meta("gate_sign")):
			var gn := String(c.get_meta("gate_screen", c.get_meta("gate_sign", "")))
			var f3: Dictionary = by_gate.get(gn, {})
			if f3.is_empty():
				c.text = gn if c.has_meta("gate_screen") else ""
				continue
			var city := String(Airports.get_ap(String(f3.to)).get("city", f3.to))
			if c.has_meta("gate_screen"):
				c.text = "%s\n%s  %s\n%s\n%s" % [gn, String(f3.number), city, U.fmt_clock(float(f3.dep)), status_for(f3, now)]
			else:
				c.text = "%s  %s  %s" % [String(f3.number), city.to_upper(), U.fmt_clock(float(f3.dep))]


func _process(delta: float) -> void:
	_fids_t -= delta
	if _fids_t <= 0.0:
		_fids_t = 20.0
		refresh_boards(get_meta("session_flight", {}))


# ================================================================== queries for walkers and crowds
func walkable(p: Vector2, radius: float = 0.3) -> bool:
	if absf(p.x) > depth * 0.5 - 0.6 or absf(p.y) > length * 0.5 - 0.6:
		return false
	for o in obstacles:
		if o.has("r"):
			if p.distance_to(o.c) < float(o.r) + radius:
				return false
		elif not o.has("door"):
			var d: Vector2 = (p - (o.c as Vector2)).abs() - (o.h as Vector2)
			if d.x < radius and d.y < radius:
				return false
	return true


func resolve(from: Vector2, to: Vector2, radius: float = 0.3) -> Vector2:
	## Slides a step along obstacles instead of stopping dead.
	if walkable(to, radius):
		return to
	var tx := Vector2(to.x, from.y)
	if walkable(tx, radius):
		return tx
	var tz := Vector2(from.x, to.y)
	if walkable(tz, radius):
		return tz
	return from


func gate(gname: String) -> Dictionary:
	for g in gates:
		if String(g.name) == gname:
			return g
	return {}


func nearest_spot(p: Vector3, max_d: float = 2.2) -> Dictionary:
	var best := {}
	var bd := max_d
	for s in spots:
		var d := Vector2(p.x - (s.p as Vector3).x, p.z - (s.p as Vector3).z).length()
		if d < bd:
			bd = d
			best = s
	return best
