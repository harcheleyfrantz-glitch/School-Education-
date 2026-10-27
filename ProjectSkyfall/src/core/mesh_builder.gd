class_name MeshBuilder
extends RefCounted
## Lightweight procedural mesh accumulator (faster than SurfaceTool for large meshes).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var indices := PackedInt32Array()
var use_uv2 := false
var xf := Transform3D.IDENTITY   # transform applied to everything added


func vcount() -> int:
	return verts.size()


func add_vertex(p: Vector3, n: Vector3, c: Color, uv: Vector2 = Vector2.ZERO, uv2: Vector2 = Vector2.ZERO) -> int:
	verts.append(xf * p)
	normals.append((xf.basis * n).normalized())
	colors.append(c)
	uvs.append(uv)
	uv2s.append(uv2)
	return verts.size() - 1


func add_tri_idx(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func add_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color, uv_scale: Vector2 = Vector2.ONE, uv2: Vector2 = Vector2.ZERO) -> void:
	## Quad with corners in counter-clockwise order when seen from the front.
	var n := (p1 - p0).cross(p3 - p0).normalized()
	if n == Vector3.ZERO:
		n = (p2 - p1).cross(p0 - p1).normalized()
	var i0 := add_vertex(p0, n, c, Vector2(0, 0), uv2)
	var i1 := add_vertex(p1, n, c, Vector2(uv_scale.x, 0), uv2)
	var i2 := add_vertex(p2, n, c, Vector2(uv_scale.x, uv_scale.y), uv2)
	var i3 := add_vertex(p3, n, c, Vector2(0, uv_scale.y), uv2)
	# Godot uses clockwise front faces
	add_tri_idx(i0, i2, i1)
	add_tri_idx(i0, i3, i2)


func add_box(center: Vector3, size: Vector3, c: Color, uv_world: bool = false) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var us := Vector2.ONE
	# front (+z)
	us = Vector2(size.x, size.y) if uv_world else Vector2.ONE
	add_quad(p[4], p[5], p[6], p[7], c, us)
	# back (-z)
	add_quad(p[1], p[0], p[3], p[2], c, us)
	us = Vector2(size.z, size.y) if uv_world else Vector2.ONE
	# right (+x)
	add_quad(p[5], p[1], p[2], p[6], c, us)
	# left (-x)
	add_quad(p[0], p[4], p[7], p[3], c, us)
	us = Vector2(size.x, size.z) if uv_world else Vector2.ONE
	# top
	add_quad(p[7], p[6], p[2], p[3], c, us)
	# bottom
	add_quad(p[0], p[1], p[5], p[4], c, us)


func add_box_xf(t: Transform3D, size: Vector3, c: Color) -> void:
	var saved := xf
	xf = xf * t
	add_box(Vector3.ZERO, size, c)
	xf = saved


func add_cylinder(a: Vector3, b: Vector3, r_a: float, r_b: float, segs: int, c: Color, caps: bool = true, c_cap: Color = Color(-1, 0, 0)) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var u := dir.cross(up).normalized()
	var v := dir.cross(u).normalized()
	var base := verts.size()
	var slope := (r_a - r_b) / length
	for i in segs + 1:
		var ang := TAU * float(i) / segs
		var off := u * cos(ang) + v * sin(ang)
		var n := (off + dir * slope).normalized()
		add_vertex(a + off * r_a, n, c, Vector2(float(i) / segs, 0))
		add_vertex(b + off * r_b, n, c, Vector2(float(i) / segs, 1))
	for i in segs:
		var i0 := base + i * 2
		add_tri_idx(i0, i0 + 1, i0 + 2)
		add_tri_idx(i0 + 1, i0 + 3, i0 + 2)
	if caps:
		var cc := c if c_cap.r < 0.0 else c_cap
		if r_a > 0.0001:
			var ca := add_vertex(a, -dir, cc)
			var start := verts.size()
			for i in segs + 1:
				var ang := TAU * float(i) / segs
				add_vertex(a + (u * cos(ang) + v * sin(ang)) * r_a, -dir, cc)
			for i in segs:
				add_tri_idx(ca, start + i + 1, start + i)
		if r_b > 0.0001:
			var cb := add_vertex(b, dir, cc)
			var start2 := verts.size()
			for i in segs + 1:
				var ang := TAU * float(i) / segs
				add_vertex(b + (u * cos(ang) + v * sin(ang)) * r_b, dir, cc)
			for i in segs:
				add_tri_idx(cb, start2 + i, start2 + i + 1)


func add_sphere(center: Vector3, radii: Vector3, segs: int, rings: int, c: Color) -> void:
	var base := verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / rings
		for s in segs + 1:
			var th := TAU * float(s) / segs
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			add_vertex(center + n * radii, (n / radii).normalized(), c, Vector2(float(s) / segs, float(r) / rings))
	for r in rings:
		for s in segs:
			var i0 := base + r * (segs + 1) + s
			var i1 := i0 + segs + 1
			add_tri_idx(i0, i1, i0 + 1)
			add_tri_idx(i0 + 1, i1, i1 + 1)


func add_arch(center: Vector3, width: float, rise: float, length: float, segs: int, c: Color) -> void:
	## Half-elliptic barrel roof spanning X (width) and running along Z (length), base at center.y.
	var rings := []
	for zi in 2:
		var z := (-0.5 + zi) * length
		var ring := PackedVector3Array()
		for i in segs + 1:
			var a := PI * float(i) / segs
			ring.append(center + Vector3(cos(a) * width * 0.5, sin(a) * rise, z))
		rings.append(ring)
	var base := verts.size()
	for zi in 2:
		var ring2: PackedVector3Array = rings[zi]
		for i in segs + 1:
			var a2 := PI * float(i) / segs
			var n := Vector3(cos(a2) / (width * 0.5), sin(a2) / maxf(rise, 0.01), 0.0).normalized()
			add_vertex(ring2[i], n, c, Vector2(a2 * width * 0.5, zi * length))
	for i in segs:
		var a0 := base + i
		var b0 := base + segs + 1 + i
		add_tri_idx(a0, a0 + 1, b0)
		add_tri_idx(a0 + 1, b0 + 1, b0)
	# gable ends
	for zi in 2:
		var ring3: PackedVector3Array = rings[zi]
		var n2 := Vector3(0, 0, -1 if zi == 0 else 1)
		var ci := add_vertex(center + Vector3(0, 0, (-0.5 + zi) * length), n2, c)
		var st := verts.size()
		for p in ring3:
			add_vertex(p, n2, c)
		for i in segs:
			if zi == 0:
				add_tri_idx(ci, st + i, st + i + 1)
			else:
				add_tri_idx(ci, st + i + 1, st + i)


func add_cone(base_center: Vector3, tip: Vector3, r: float, segs: int, c: Color) -> void:
	add_cylinder(base_center, tip, r, 0.0, segs, c, true)


## Lofts closed cross-sections (each a PackedVector3Array with equal point counts) into a tube.
func add_loft(rings: Array, c: Color, close_start: bool = false, close_end: bool = false, uv_v: Array = []) -> void:
	if rings.size() < 2:
		return
	var npts: int = rings[0].size()
	var base := verts.size()
	for ri in rings.size():
		var ring: PackedVector3Array = rings[ri]
		var center := Vector3.ZERO
		for p in ring:
			center += p
		center /= npts
		var prev: PackedVector3Array = rings[maxi(ri - 1, 0)]
		var nxt: PackedVector3Array = rings[mini(ri + 1, rings.size() - 1)]
		for pi in npts + 1:
			var k := pi % npts
			var p := ring[k]
			var tangent_ring := ring[(k + 1) % npts] - ring[(k - 1 + npts) % npts]
			var tangent_len := nxt[k] - prev[k]
			var n := tangent_len.cross(tangent_ring).normalized()
			if n.dot(p - center) < 0.0:
				n = -n
			if n == Vector3.ZERO:
				n = (p - center).normalized()
			var v_coord: float = uv_v[ri] if uv_v.size() == rings.size() else float(ri) / (rings.size() - 1)
			add_vertex(p, n, c, Vector2(float(pi) / npts, v_coord))
	# pick the winding that faces outward (Godot front faces are clockwise); test on the
	# widest ring so degenerate tips cannot fool us
	var mi := 0
	var best_r := -1.0
	for ri in rings.size() - 1:
		var rr: PackedVector3Array = rings[ri]
		var cc := Vector3.ZERO
		for p in rr:
			cc += p
		cc /= npts
		var spread := (rr[0] - cc).length() + (rr[npts / 2] - cc).length()
		if spread > best_r:
			best_r = spread
			mi = ri
	var r0: PackedVector3Array = rings[mi]
	var r1: PackedVector3Array = rings[mi + 1]
	var c0 := Vector3.ZERO
	for p in r0:
		c0 += p
	c0 /= npts
	var flip_votes := 0
	for k in [0, npts / 4, npts / 2, (3 * npts) / 4]:
		var outward := r0[k] - c0
		var nrm := (r0[(k + 1) % npts] - r0[k]).cross(r1[k] - r0[k])
		flip_votes += 1 if nrm.dot(outward) < 0.0 else -1
	var flip := flip_votes > 0
	for ri in rings.size() - 1:
		for pi in npts:
			var i0 := base + ri * (npts + 1) + pi
			var i1 := i0 + npts + 1
			if flip:
				add_tri_idx(i0, i0 + 1, i1)
				add_tri_idx(i0 + 1, i1 + 1, i1)
			else:
				add_tri_idx(i0, i1, i0 + 1)
				add_tri_idx(i0 + 1, i1, i1 + 1)
	if close_start:
		_cap_ring(rings[0], c, true)
	if close_end:
		_cap_ring(rings[rings.size() - 1], c, false)


func _cap_ring(ring: PackedVector3Array, c: Color, flip: bool) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= ring.size()
	var n := (ring[1] - ring[0]).cross(ring[2] - ring[0]).normalized()
	if flip:
		n = -n
	var ci := add_vertex(center, n, c)
	var start := verts.size()
	for p in ring:
		add_vertex(p, n, c)
	for i in ring.size():
		var a := start + i
		var b := start + (i + 1) % ring.size()
		if flip:
			add_tri_idx(ci, a, b)
		else:
			add_tri_idx(ci, b, a)


func add_mesh_builder(other: MeshBuilder, t: Transform3D = Transform3D.IDENTITY) -> void:
	var base := verts.size()
	var full := xf * t
	for i in other.verts.size():
		verts.append(full * other.verts[i])
		normals.append((full.basis * other.normals[i]).normalized())
		colors.append(other.colors[i])
		uvs.append(other.uvs[i])
		uv2s.append(other.uv2s[i])
	for idx in other.indices:
		indices.append(base + idx)


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if use_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func clear() -> void:
	verts.clear()
	normals.clear()
	colors.clear()
	uvs.clear()
	uv2s.clear()
	indices.clear()
	xf = Transform3D.IDENTITY
