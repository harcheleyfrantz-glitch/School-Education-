extends RefCounted
## Unit meshes for street traffic: +x forward, y up, origin on the ground at the middle of the
## vehicle. Vertex colour r = part (1 paint, 0.72 second paint (bus livery, trailer),
## 0.6 glass, 0.3 tyres/bumpers/grille, 0.85 headlights, 0.95 tail lights). The traffic shader
## slides each instance along its lane and picks the paint from a per-country palette.

const PAINT := 1.0
const PAINT2 := 0.72
const GLASS := 0.6
const DARK := 0.3
const HEAD := 0.85
const TAIL := 0.95


static func build_all() -> Dictionary:
	return {
		"sedan": _car(4.7, 1.82, [[-2.35, 0.32], [-2.3, 0.78], [-1.55, 0.88], [1.35, 0.9], [2.32, 0.74], [2.35, 0.34]],
			[[-1.45, 0.86], [-0.95, 1.38], [0.55, 1.4], [1.25, 0.88]], 1.56, 0.68),
		"suv": _car(4.9, 1.94, [[-2.45, 0.42], [-2.42, 1.02], [2.2, 1.06], [2.45, 0.92], [2.47, 0.44]],
			[[-2.38, 1.0], [-2.25, 1.74], [1.0, 1.76], [1.65, 1.04]], 1.74, 0.72),
		"hatch": _car(4.0, 1.74, [[-2.0, 0.32], [-1.98, 0.86], [1.2, 0.9], [1.98, 0.74], [2.0, 0.34]],
			[[-1.92, 0.86], [-1.7, 1.46], [0.4, 1.48], [1.15, 0.9]], 1.5, 0.62),
		"van": _box_vehicle(5.3, 2.0, 2.25, false),
		"bus": _box_vehicle(12.0, 2.55, 3.15, true),
		"truck": _truck(),
	}


# ------------------------------------------------------------------ helpers
static func _tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
	var i0 := mb.add_vertex(a, nrm, col)
	var i1 := mb.add_vertex(b, nrm, col)
	var i2 := mb.add_vertex(c, nrm, col)
	if (b - a).cross(c - a).dot(nrm) >= 0.0:
		mb.add_tri_idx(i0, i2, i1)
	else:
		mb.add_tri_idx(i0, i1, i2)


static func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
	_tri(mb, a, b, c, nrm, col)
	_tri(mb, a, c, d, nrm, col)


static func _extrude(mb: MeshBuilder, prof: Array, hw: float, col: Color, side_col: Color = Color(-1, 0, 0)) -> void:
	## A convex side profile [[x, y], ...] (around the outline) extruded across z = -hw..hw.
	var sc := col if side_col.r < 0.0 else side_col
	var n := prof.size()
	var cx := 0.0
	var cy := 0.0
	for p in prof:
		cx += float(p[0])
		cy += float(p[1])
	cx /= n
	cy /= n
	for side in [-1.0, 1.0]:
		var z: float = side * hw
		for i in range(1, n - 1):
			_tri(mb, Vector3(prof[0][0], prof[0][1], z), Vector3(prof[i][0], prof[i][1], z), Vector3(prof[i + 1][0], prof[i + 1][1], z), Vector3(0, 0, side), sc)
	for i in n:
		var a: Array = prof[i]
		var b: Array = prof[(i + 1) % n]
		var mx := (float(a[0]) + float(b[0])) * 0.5 - cx
		var my := (float(a[1]) + float(b[1])) * 0.5 - cy
		var ex := float(b[0]) - float(a[0])
		var ey := float(b[1]) - float(a[1])
		var nrm := Vector3(ey, -ex, 0.0).normalized()
		if nrm.x * mx + nrm.y * my < 0.0:
			nrm = -nrm
		_quad(mb, Vector3(a[0], a[1], -hw), Vector3(b[0], b[1], -hw), Vector3(b[0], b[1], hw), Vector3(a[0], a[1], hw), nrm, col)


static func _box(mb: MeshBuilder, c: Vector3, s: Vector3, col: Color) -> void:
	mb.add_box(c, s, col)


static func _wheels(mb: MeshBuilder, xs: Array, half_track: float, r: float, w: float) -> void:
	## Tyres as one outward face each (all that shows from outside the body).
	for x in xs:
		for sz in [-1.0, 1.0]:
			var z: float = sz * (half_track + w * 0.5)
			var xf := float(x)
			_quad(mb, Vector3(xf - r, 0.02, z), Vector3(xf + r, 0.02, z), Vector3(xf + r, r * 2.0, z), Vector3(xf - r, r * 2.0, z), Vector3(0, 0, sz), Color(DARK, 1, 1, 1))


static func _lamp(mb: MeshBuilder, x: float, y: float, z: float, h: float, w: float, front: bool, part: float) -> void:
	var nx := 1.0 if front else -1.0
	_quad(mb, Vector3(x, y - h * 0.5, z - w * 0.5), Vector3(x, y - h * 0.5, z + w * 0.5), Vector3(x, y + h * 0.5, z + w * 0.5), Vector3(x, y + h * 0.5, z - w * 0.5),
		Vector3(nx, 0, 0), Color(part, 1, 1, 1))


# ------------------------------------------------------------------ vehicles
static func _car(length: float, width: float, body: Array, cabin: Array, cabin_w: float, wheel_r: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var hw := width * 0.5
	_extrude(mb, body, hw, Color(PAINT, 1, 1, 1))
	# cabin: glass all round under a painted roof
	_extrude(mb, cabin, cabin_w * 0.5, Color(GLASS, 1, 1, 1))
	var top_y := 0.0
	var x_lo := INF
	var x_hi := -INF
	for p in cabin:
		if float(p[1]) > top_y - 0.05:
			top_y = maxf(top_y, float(p[1]))
	for p in cabin:
		if float(p[1]) > top_y - 0.08:
			x_lo = minf(x_lo, float(p[0]))
			x_hi = maxf(x_hi, float(p[0]))
	# painted roof panel over the glasshouse
	var ry := top_y + 0.015
	var rz := cabin_w * 0.5 + 0.01
	_quad(mb, Vector3(x_lo - 0.02, ry, -rz), Vector3(x_hi + 0.02, ry, -rz), Vector3(x_hi + 0.02, ry, rz), Vector3(x_lo - 0.02, ry, rz), Vector3.UP, Color(PAINT, 1, 1, 1))
	# lamps
	var front := length * 0.5
	for sz in [-1.0, 1.0]:
		_lamp(mb, front + 0.01, 0.62, sz * (hw - 0.3), 0.13, 0.36, true, HEAD)
		_lamp(mb, -front - 0.01, 0.68, sz * (hw - 0.24), 0.13, 0.32, false, TAIL)
	_wheels(mb, [length * 0.31, -length * 0.3], hw - 0.12, wheel_r * 0.5, 0.26)
	return mb.commit()


static func _box_vehicle(length: float, width: float, height: float, bus: bool) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var hw := width * 0.5
	var front := length * 0.5
	var floor_y := 0.45 if bus else 0.4
	# body with a rounded nose
	_extrude(mb, [[-front, floor_y], [-front, height - 0.08], [-front + 0.1, height], [front - 0.45, height], [front - 0.05, height - 0.45],
		[front, floor_y + 0.25], [front - 0.02, floor_y]], hw, Color(PAINT if not bus else PAINT2, 1, 1, 1))
	# windows: a band along the sides and the windscreen
	var wy0 := floor_y + (0.95 if bus else 0.75)
	var wy1 := height - (0.3 if bus else 0.35)
	for sz in [-1.0, 1.0]:
		var zz: float = sz * (hw + 0.01)
		var x0 := -front + (0.5 if bus else 1.9)
		var x1 := front - (1.0 if bus else 1.2)
		_quad(mb, Vector3(x0, wy0, zz), Vector3(x1, wy0, zz), Vector3(x1, wy1, zz), Vector3(x0, wy1, zz), Vector3(0, 0, sz), Color(GLASS, 1, 1, 1))
	_quad(mb, Vector3(front - 0.04, wy0, -hw + 0.12), Vector3(front - 0.04, wy0, hw - 0.12), Vector3(front - 0.4, wy1, hw - 0.12), Vector3(front - 0.4, wy1, -hw + 0.12),
		Vector3(1, 0.5, 0).normalized(), Color(GLASS, 1, 1, 1))
	if bus:
		# livery stripe and roof units
		for sz in [-1.0, 1.0]:
			var zz2: float = sz * (hw + 0.012)
			_quad(mb, Vector3(-front + 0.2, floor_y + 0.25, zz2), Vector3(front - 0.3, floor_y + 0.25, zz2), Vector3(front - 0.3, floor_y + 0.75, zz2),
				Vector3(-front + 0.2, floor_y + 0.75, zz2), Vector3(0, 0, sz), Color(PAINT, 1, 1, 1))
		_box(mb, Vector3(-front * 0.4, height + 0.15, 0), Vector3(2.4, 0.3, width * 0.7), Color(PAINT2, 1, 1, 1))
	for sz in [-1.0, 1.0]:
		_lamp(mb, front + 0.01, floor_y + 0.3, sz * (hw - 0.3), 0.16, 0.34, true, HEAD)
		_lamp(mb, -front - 0.01, floor_y + 0.45, sz * (hw - 0.2), 0.22, 0.24, false, TAIL)
	var xs := [front - (2.4 if bus else 0.95), -front + (3.0 if bus else 1.0)]
	_wheels(mb, xs, hw - 0.18, 0.5 if bus else 0.36, 0.32)
	return mb.commit()


static func _truck() -> ArrayMesh:
	## Articulated lorry: cab with a sleeper roof and a box trailer.
	var mb := MeshBuilder.new()
	var hw := 1.27
	# cab
	_extrude(mb, [[5.6, 0.7], [5.6, 2.9], [6.0, 3.0], [8.2, 3.0], [8.25, 1.0], [8.2, 0.7]], hw, Color(PAINT, 1, 1, 1))
	_quad(mb, Vector3(8.23, 1.75, -hw + 0.15), Vector3(8.23, 1.75, hw - 0.15), Vector3(8.18, 2.65, hw - 0.15), Vector3(8.18, 2.65, -hw + 0.15), Vector3(1, 0, 0), Color(GLASS, 1, 1, 1))
	_extrude(mb, [[5.7, 3.0], [5.7, 3.7], [7.3, 3.7], [7.9, 3.0]], hw - 0.1, Color(PAINT, 1, 1, 1))
	# trailer
	_box(mb, Vector3(-1.9, 2.45, 0), Vector3(13.4, 2.9, 2.5), Color(PAINT2, 1, 1, 1))

	for sz in [-1.0, 1.0]:
		_lamp(mb, 8.26, 1.1, sz * (hw - 0.3), 0.2, 0.4, true, HEAD)
		_lamp(mb, -8.62, 1.0, sz * (hw - 0.2), 0.2, 0.3, false, TAIL)
	_wheels(mb, [7.4, 4.6, 3.3, -6.0, -7.3, -8.0], hw - 0.2, 0.5, 0.36)
	# centre the rig on its own length (cab front 8.25, trailer back -8.6)
	var mesh := mb.commit()
	return mesh
