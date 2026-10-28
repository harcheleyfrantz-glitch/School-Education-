class_name CabinInterior
extends Node3D
## Walk-in passenger cabin generated from CabinLayout: sidewalls with real window cut-outs and
## glazing, overhead bins, ceiling, floor, bulkheads, class dividers, galleys, lavatories, doors
## (that open, with escape slides), exit signs, seats, oxygen masks and cabin lighting modes.
## Meshes are split into ~8 m chunks so mobile renderers keep few lights per object.

const CHUNK := 8.0
const INSET := 0.13

const BIN := {
	"turboprop": {"bottom": 1.50, "top": 1.76, "depth": 0.38},
	"regional": {"bottom": 1.55, "top": 1.86, "depth": 0.42},
	"narrowbody": {"bottom": 1.62, "top": 2.0, "depth": 0.52},
	"widebody": {"bottom": 1.68, "top": 2.12, "depth": 0.60},
	"bizjet": {"bottom": 1.45, "top": 1.62, "depth": 0.0},
	"cargo": {"bottom": 1.7, "top": 1.95, "depth": 0.0},
}

var lay: Dictionary
var spec: Dictionary
var airline := "SKF"
var cat := ""
var floor_y := 0.0
var ceil_y := 0.0
var bin: Dictionary
var _builders := {}     # "kind:chunk" -> MeshBuilder
var mat_shell: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_emit: ShaderMaterial
var lights: Array[OmniLight3D] = []
var light_mode := "boarding"
var door_nodes := {}    # name -> {pivot: Node3D, open: float, target: float, side, z}
var slides := {}        # name -> MeshInstance3D
var mask_root: Node3D
var masks_deployed := 0.0
var masks_target := 0.0
var seat_mmis: Array[MultiMeshInstance3D] = []
var smoke := 0.0
var _t := 0.0


func build(type_id: String, airline_code: String) -> void:
	spec = AircraftTypes.get_type(type_id)
	lay = CabinLayout.get_layout(type_id)
	airline = airline_code
	cat = spec.category
	floor_y = lay.floor_y
	ceil_y = lay.ceil_y
	bin = BIN.get(cat, BIN.narrowbody)
	name = "CabinInterior"
	mat_shell = StandardMaterial3D.new()
	mat_shell.vertex_color_use_as_albedo = true
	mat_shell.vertex_color_is_srgb = true
	mat_shell.roughness = 0.82
	mat_glass = StandardMaterial3D.new()
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.albedo_color = Color(0.62, 0.72, 0.82, 0.16)
	mat_glass.roughness = 0.04
	mat_glass.metallic_specular = 0.9
	mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_emit = ShaderMaterial.new()
	mat_emit.shader = load("res://shaders/cabin_emit.gdshader")
	if cat == "trainer":
		return
	_build_walls()
	_build_ceiling_and_bins()
	_build_floor()
	_build_bulkheads()
	_build_galleys_lavs()
	_build_signs()
	_commit()
	_build_doors()
	_build_seats()
	_build_masks()
	_build_lights()
	_build_interior_probe()
	set_light_mode("boarding")


func _build_interior_probe() -> void:
	## Without global illumination the open sky would light the inside of the tube as brightly
	## as the outside. Interior geometry sits on its own render layer, and an interior probe
	## covering the whole section gives just that layer a dimmer, warm cabin ambient; the
	## exterior skin keeps the sky's light.
	var z0 := float(lay.cabin_front)
	var z1 := float(lay.cabin_back)
	add_child(make_interior_probe("InteriorProbe", Vector3(0, (floor_y + ceil_y) * 0.5, (z0 + z1) * 0.5),
		Vector3(float(spec.fuse_w) + 0.4, float(spec.fuse_h) + 0.4, maxf(z1 - z0, 1.0)), Color(0.9, 0.92, 0.95), 0.34))
	tag_interior(self)


const INTERIOR_LAYER := 1 << 10     # render layer 11: geometry lit by the interior probes


static func make_interior_probe(probe_name: String, center: Vector3, size: Vector3, ambient: Color, energy: float) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = probe_name
	probe.size = size
	probe.position = center
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = ambient
	probe.ambient_color_energy = energy
	probe.intensity = 0.25
	probe.blend_distance = 0.05
	probe.reflection_mask = INTERIOR_LAYER     # only interior geometry takes this ambient
	probe.cull_mask = INTERIOR_LAYER           # and only interior geometry shows in its reflections
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = maxf(size.z, 6.0)
	return probe


static func tag_interior(root: Node) -> void:
	## Puts every visual under root on the interior layer (cameras still draw it: they see all layers).
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers |= INTERIOR_LAYER
	for c in root.get_children():
		tag_interior(c)


# ---------------------------------------------------------------- helpers
func _chunk(z: float) -> int:
	return int(floorf((z - float(lay.cabin_front)) / CHUNK))


func _mb(kind: String, z: float) -> MeshBuilder:
	var key := "%s:%d" % [kind, _chunk(z)]
	if not _builders.has(key):
		_builders[key] = MeshBuilder.new()
	return _builders[key]


func _wall_x(z: float, y: float) -> float:
	return maxf(CabinLayout.half_width(spec, z, y) - INSET, 0.05)


func _quad(mb: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, facing: Vector3, c: Color) -> void:
	var n := (p1 - p0).cross(p3 - p0)
	if n.dot(facing) < 0.0:
		mb.add_quad(p0, p3, p2, p1, c)
	else:
		mb.add_quad(p0, p1, p2, p3, c)


func _box(mb: MeshBuilder, c: Vector3, size: Vector3, col: Color) -> void:
	mb.add_box(c, size, col)


func _commit() -> void:
	for key in _builders.keys():
		var mb: MeshBuilder = _builders[key]
		if mb.verts.is_empty():
			continue
		var kind: String = key.split(":")[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.name = key
		match kind:
			"glass":
				mi.material_override = mat_glass
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"emit":
				mi.material_override = mat_emit
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mi.material_override = mat_shell
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		add_child(mi)
	_builders.clear()


# ---------------------------------------------------------------- sidewalls with windows and door cut-outs
func _openings(side: int) -> Array:
	var out := []
	for d in lay.doors:
		if d.side != side:
			continue
		if d.kind == "door":
			out.append({"z0": d.z - d.width * 0.5, "z1": d.z + d.width * 0.5, "y0": floor_y - 0.01, "y1": floor_y + d.height})
		else:
			out.append({"z0": d.z - 0.26, "z1": d.z + 0.26, "y0": floor_y + 0.36, "y1": floor_y + 1.3})
	return out


func _build_walls() -> void:
	var z0: float = lay.cabin_front
	var z1: float = lay.cabin_back
	var win_h := 0.34 if cat != "widebody" else 0.42
	var win_w := 0.23 if cat != "widebody" else 0.27
	if cat == "bizjet":
		win_h = 0.36
		win_w = 0.3
	var yc := floor_y + 1.02
	var yb := yc - win_h * 0.5 - 0.06
	var yt := yc + win_h * 0.5 + 0.06
	var y_top := floor_y + float(bin.top)
	var pitch := 0.53 if cat != "bizjet" else 1.1
	var y_levels := [floor_y, floor_y + 0.36, yb, yt, floor_y + 1.3, floor_y + 1.86, y_top]
	y_levels.sort()
	# z breakpoints: regular slices + window cells + opening edges
	var zs := []
	var z := z0
	while z < z1:
		zs.append(z)
		z += 0.5
	zs.append(z1)
	for side in [-1, 1]:
		var ops := _openings(side)
		var zb := []
		var cells := []
		for wz in lay.windows:
			zb.append(wz - pitch * 0.5)
			zb.append(wz + pitch * 0.5)
			cells.append(wz)
		for zr in zs:
			var inside := false
			for wz3 in cells:
				if absf(float(zr) - float(wz3)) < pitch * 0.5 - 0.005:
					inside = true
			if not inside:
				zb.append(zr)
		for o in ops:
			zb.append(o.z0)
			zb.append(o.z1)
		zb.sort()
		var zu := []
		for v in zb:
			if v < z0 - 0.001 or v > z1 + 0.001:
				continue
			if zu.is_empty() or v - float(zu[zu.size() - 1]) > 0.02:
				zu.append(v)
		var facing := Vector3(-side, 0, 0)
		var wall_col := Color(0.76, 0.76, 0.74)
		var lower_col := Color(0.78, 0.79, 0.8)
		for i in zu.size() - 1:
			var za: float = zu[i]
			var zc2: float = zu[i + 1]
			var zm := (za + zc2) * 0.5
			var mb := _mb("shell", zm)
			# is this a window cell?
			var win_z := -1e9
			for wz2 in cells:
				if absf(zm - wz2) < pitch * 0.5 - 0.01:
					win_z = wz2
			for j in y_levels.size() - 1:
				var ya: float = y_levels[j]
				var yb2: float = y_levels[j + 1]
				if yb2 - ya < 0.005:
					continue
				var ym := (ya + yb2) * 0.5
				var cut := false
				for o2 in ops:
					if zm > o2.z0 and zm < o2.z1 and ym > o2.y0 and ym < o2.y1:
						cut = true
				if cut:
					continue
				var col := lower_col if ym < floor_y + 0.36 else wall_col
				if win_z > -1e8 and absf(ya - yb) < 0.001 and absf(yb2 - yt) < 0.001:
					_window_cell(side, za, zc2, ya, yb2, win_z, yc, win_w * 0.5, win_h * 0.5, col)
					continue
				var p0 := Vector3(side * _wall_x(za, ya), ya, za)
				var p1 := Vector3(side * _wall_x(zc2, ya), ya, zc2)
				var p2 := Vector3(side * _wall_x(zc2, yb2), yb2, zc2)
				var p3 := Vector3(side * _wall_x(za, yb2), yb2, za)
				_quad(mb, p0, p1, p2, p3, facing, col)
		# door/hatch reveals (frame around each opening)
		for o3 in ops:
			_opening_frame(side, o3)


func _window_cell(side: int, za: float, zb: float, ya: float, yb: float, wz: float, yc: float, hw: float, hh: float, col: Color) -> void:
	## One wall cell with a window: a rounded-rectangle opening (superellipse) joined to the cell
	## edges by a ring of quads, a reveal down to the glazing, and the pane.
	var mb := _mb("shell", wz)
	var gmb := _mb("glass", wz)
	# sample angles so that four of them point exactly at the cell corners (watertight ring)
	var ca := [atan2(yb - yc, zb - wz), atan2(yb - yc, za - wz), atan2(ya - yc, za - wz) + TAU, atan2(ya - yc, zb - wz) + TAU]
	var per := 6
	var angles := []
	for c in 4:
		var a0: float = ca[c]
		var a1: float = ca[(c + 1) % 4] + (TAU if c == 3 else 0.0)
		for k in per:
			angles.append(lerpf(a0, a1, float(k) / per))
	var n := angles.size()
	var hole := []
	var bnd := []
	for a in angles:
		var d := Vector2(cos(a), sin(a))
		var r := 1.0 / pow(pow(absf(d.x) / hw, 4.0) + pow(absf(d.y) / hh, 4.0), 0.25)
		hole.append(Vector2(wz, yc) + d * r)
		var tz := INF
		var ty := INF
		if absf(d.x) > 1e-6:
			tz = ((zb if d.x > 0.0 else za) - wz) / d.x
		if absf(d.y) > 1e-6:
			ty = ((yb if d.y > 0.0 else ya) - yc) / d.y
		bnd.append(Vector2(wz, yc) + d * minf(tz, ty))
	var facing := Vector3(-side, 0, 0)
	var reveal_col := Color(0.8, 0.8, 0.79)
	var inner := []
	var outer := []
	for k in n:
		var h: Vector2 = hole[k]
		inner.append(Vector3(side * _wall_x(h.x, h.y), h.y, h.x))
		outer.append(Vector3(side * (_wall_x(h.x, h.y) + INSET - 0.03), h.y, h.x))
	for k in n:
		var k2 := (k + 1) % n
		var b0: Vector2 = bnd[k]
		var b1: Vector2 = bnd[k2]
		var pb0 := Vector3(side * _wall_x(b0.x, b0.y), b0.y, b0.x)
		var pb1 := Vector3(side * _wall_x(b1.x, b1.y), b1.y, b1.x)
		_quad(mb, inner[k], inner[k2], pb1, pb0, facing, col)
		# reveal facing the window axis, smooth-shaded around the opening
		var mid: Vector3 = (inner[k] + inner[k2]) * 0.5
		var axis_pt := Vector3(mid.x, yc, wz)
		var pts := [inner[k], inner[k2], outer[k2], outer[k]]
		var nrm := []
		for q in pts:
			var to_axis := Vector3(0.0, yc - (q as Vector3).y, wz - (q as Vector3).z)
			nrm.append(to_axis.normalized() if to_axis.length() > 1e-5 else facing)
		var fn = ((pts[1] as Vector3) - pts[0]).cross((pts[3] as Vector3) - pts[0])
		var base := mb.vcount()
		for qi in 4:
			mb.add_vertex(pts[qi], nrm[qi], reveal_col)
		if fn.dot(axis_pt - mid) >= 0.0:
			mb.add_tri_idx(base, base + 2, base + 1)
			mb.add_tri_idx(base, base + 3, base + 2)
		else:
			mb.add_tri_idx(base, base + 1, base + 2)
			mb.add_tri_idx(base, base + 2, base + 3)
	# glazing
	var gc := Vector3(side * (_wall_x(wz, yc) + INSET - 0.035), yc, wz)
	var ci := gmb.add_vertex(gc, facing, Color.WHITE)
	var st := gmb.vcount()
	for k in n:
		var o: Vector3 = outer[k]
		gmb.add_vertex(Vector3(o.x - side * 0.005, o.y, o.z), facing, Color.WHITE)
	for k in n:
		gmb.add_tri_idx(ci, st + k, st + (k + 1) % n)


func _opening_frame(side: int, o: Dictionary) -> void:
	var mb := _mb("shell", (o.z0 + o.z1) * 0.5)
	var frame_col := Color(0.7, 0.71, 0.72)
	var d := INSET - 0.02
	var corners := [Vector2(o.z0, o.y0), Vector2(o.z1, o.y0), Vector2(o.z1, o.y1), Vector2(o.z0, o.y1)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		if k == 0:
			continue   # sill handled by the floor
		var pa := Vector3(side * _wall_x(a.x, a.y), a.y, a.x)
		var pb := Vector3(side * _wall_x(b.x, b.y), b.y, b.x)
		var mid := (pa + pb) * 0.5
		var c := Vector3(mid.x, (o.y0 + o.y1) * 0.5, (o.z0 + o.z1) * 0.5)
		_quad(mb, pa, pb, pb + Vector3(side * d, 0, 0), pa + Vector3(side * d, 0, 0), c - mid, frame_col)


# ---------------------------------------------------------------- ceiling, bins, passenger service units
func _bin_zone(z: float) -> bool:
	if float(bin.depth) <= 0.0:
		return false
	for r in lay.rows:
		if z >= r.z0 - 0.05 and z <= r.z1 + 0.05:
			return true
	return false


func _build_ceiling_and_bins() -> void:
	var z0: float = lay.cabin_front
	var z1: float = lay.cabin_back
	var y_top := floor_y + float(bin.top)
	var segs := 6
	var z := z0
	var step := 0.5
	var ceil_col := Color(0.84, 0.84, 0.82)
	while z < z1 - 0.001:
		var za := z
		var zb := minf(z + step, z1)
		var mb := _mb("shell", (za + zb) * 0.5)
		for side in [-1, 1]:
			var xa := _wall_x(za, y_top)
			var xb := _wall_x(zb, y_top)
			for k in segs:
				var f0 := float(k) / segs
				var f1 := float(k + 1) / segs
				var p0 := Vector3(side * xa * (1.0 - f0), lerpf(y_top, ceil_y, 1.0 - pow(1.0 - f0, 2.0)), za)
				var p1 := Vector3(side * xb * (1.0 - f0), lerpf(y_top, ceil_y, 1.0 - pow(1.0 - f0, 2.0)), zb)
				var p2 := Vector3(side * xb * (1.0 - f1), lerpf(y_top, ceil_y, 1.0 - pow(1.0 - f1, 2.0)), zb)
				var p3 := Vector3(side * xa * (1.0 - f1), lerpf(y_top, ceil_y, 1.0 - pow(1.0 - f1, 2.0)), za)
				_quad(mb, p0, p1, p2, p3, Vector3(0, -1, 0), ceil_col)
		z = zb
	if float(bin.depth) <= 0.0:
		return
	# side bins as continuous runs over the seat rows
	var runs := _runs()
	var bin_col := Color(0.8, 0.81, 0.82)
	var seam_col := Color(0.55, 0.57, 0.6)
	for run in runs:
		for side2 in [-1, 1]:
			_bin_run(side2, run[0], run[1], bin_col, seam_col)
		if cat == "widebody":
			_center_bin(run[0], run[1], bin_col, seam_col)


func _runs() -> Array:
	var runs := []
	var cur := []
	for r in lay.rows:
		if cur.is_empty():
			cur = [r.z0, r.z1]
		elif r.z0 - cur[1] < 0.3:
			cur[1] = r.z1
		else:
			runs.append(cur)
			cur = [r.z0, r.z1]
	if not cur.is_empty():
		runs.append(cur)
	return runs


func _bin_run(side: int, za: float, zb: float, col: Color, seam: Color) -> void:
	var yb := floor_y + float(bin.bottom)
	var yt := floor_y + float(bin.top)
	var depth: float = bin.depth
	var z := za
	while z < zb - 0.001:
		var z2 := minf(z + 0.5, zb)
		var mb := _mb("shell", (z + z2) * 0.5)
		var pts_a := _bin_profile(side, z, yb, yt, depth)
		var pts_b := _bin_profile(side, z2, yb, yt, depth)
		for k in pts_a.size() - 1:
			var c := col
			_quad(mb, pts_a[k], pts_b[k], pts_b[k + 1], pts_a[k + 1], Vector3(-side, -0.6, 0), c)
		z = z2
	# end caps
	for zc in [za, zb]:
		var mb2 := _mb("shell", zc)
		var pts := _bin_profile(side, zc, yb, yt, depth)
		var back := Vector3(side * _wall_x(zc, (yb + yt) * 0.5), (yb + yt) * 0.5, zc)
		for k in pts.size() - 1:
			var fz := -1.0 if zc == za else 1.0
			var n = (pts[k + 1] - back).cross(pts[k] - back)
			if n.z * fz < 0.0:
				mb2.add_vertex(back, Vector3(0, 0, fz), col)
				mb2.add_vertex(pts[k], Vector3(0, 0, fz), col)
				mb2.add_vertex(pts[k + 1], Vector3(0, 0, fz), col)
			else:
				mb2.add_vertex(back, Vector3(0, 0, fz), col)
				mb2.add_vertex(pts[k + 1], Vector3(0, 0, fz), col)
				mb2.add_vertex(pts[k], Vector3(0, 0, fz), col)
			var b := mb2.vcount() - 3
			mb2.add_tri_idx(b, b + 1, b + 2)
	# door seams and latches every ~1.5 m
	var nseg := maxi(int((zb - za) / 1.5), 1)
	var segl := (zb - za) / nseg
	for i in nseg + 1:
		var sz := za + i * segl
		var mb3 := _mb("shell", sz)
		var x_front := side * (_wall_x(sz, yb) - depth)
		mb3.add_box(Vector3(x_front - side * 0.012, yb + 0.16, sz), Vector3(0.012, 0.3, 0.012), seam)
		if i < nseg:
			mb3.add_box(Vector3(x_front - side * 0.016, yb + 0.05, sz + segl * 0.5), Vector3(0.012, 0.03, 0.14), seam)
	# passenger service unit strip under the bin with reading lights and signs
	var emb := _mb("emit", (za + zb) * 0.5)
	for r in lay.rows:
		if r.z0 < za - 0.01 or r.z1 > zb + 0.01:
			continue
		var x_in := side * (_wall_x(r.z0, yb) - depth + 0.08)
		var mb4 := _mb("shell", r.z0)
		mb4.add_box(Vector3(x_in + side * 0.14, yb - 0.012, (r.z0 + r.z1) * 0.5), Vector3(0.34, 0.02, r.z1 - r.z0 - 0.04), Color(0.8, 0.81, 0.82))
		emb.add_box(Vector3(x_in + side * 0.06, yb - 0.025, r.z0 + r.pitch * 0.55), Vector3(0.05, 0.006, 0.05), Color(1.0, 0.95, 0.8, 0.12))
		emb.add_box(Vector3(x_in + side * 0.2, yb - 0.025, r.z0 + r.pitch * 0.3), Vector3(0.09, 0.006, 0.05), Color(0.9, 0.9, 0.95, 0.5))
	# cove light along the top of the bin
	var x_c := side * (_wall_x((za + zb) * 0.5, yt) - depth * 0.6)
	emb.add_box(Vector3(x_c, yt + 0.01, (za + zb) * 0.5), Vector3(0.05, 0.01, zb - za), Color(0.95, 0.92, 0.85, 0.75))


func _bin_profile(side: int, z: float, yb: float, yt: float, depth: float) -> Array:
	var xw := _wall_x(z, yb)
	var xt := _wall_x(z, yt)
	var xf := xw - depth
	return [
		Vector3(side * xw, yb, z),
		Vector3(side * xf, yb, z),
		Vector3(side * (xf - 0.03), yb + 0.14, z),
		Vector3(side * (xf - 0.0), yb + (yt - yb) * 0.75, z),
		Vector3(side * minf(xf + 0.12, xt), yt, z),
	]


func _center_bin(za: float, zb: float, col: Color, seam: Color) -> void:
	var yb := floor_y + 1.78
	var hw := 0.62
	var z := za
	while z < zb - 0.001:
		var z2 := minf(z + 0.5, zb)
		var mb := _mb("shell", (z + z2) * 0.5)
		var top := ceil_y - 0.02
		mb.add_box(Vector3(0, (yb + top) * 0.5, (z + z2) * 0.5), Vector3(hw * 2.0, top - yb, z2 - z), col)
		mb.add_box(Vector3(0, yb - 0.012, (z + z2) * 0.5), Vector3(hw * 2.0 - 0.1, 0.02, z2 - z - 0.02), Color(0.8, 0.81, 0.82))
		for sx in [-1.0, 1.0]:
			mb.add_box(Vector3(sx * (hw + 0.004), yb + 0.18, z), Vector3(0.008, 0.32, 0.012), seam)
		z = z2


# ---------------------------------------------------------------- floor
func _build_floor() -> void:
	var z0: float = lay.cabin_front
	var z1: float = lay.cabin_back
	var carpet := Color(0.2, 0.23, 0.32)
	var lc := Airlines.livery_colors(airline)
	var aisle_col: Color = (lc.get("tail", Color(0.2, 0.25, 0.4)) as Color).darkened(0.45)
	var z := z0
	while z < z1 - 0.001:
		var z2 := minf(z + 0.5, z1)
		var mb := _mb("shell", (z + z2) * 0.5)
		var xa := _wall_x(z, floor_y + 0.02)
		var xb := _wall_x(z2, floor_y + 0.02)
		_quad(mb, Vector3(-xa, floor_y, z), Vector3(xa, floor_y, z), Vector3(xb, floor_y, z2), Vector3(-xb, floor_y, z2), Vector3.UP, carpet)
		z = z2
	# aisle runners and floor path lighting along each aisle
	for r in lay.rows:
		for ax in r.aisles:
			var mb2 := _mb("shell", r.z0)
			mb2.add_box(Vector3(float(ax), floor_y + 0.003, (r.z0 + r.z1) * 0.5), Vector3(0.44, 0.004, r.z1 - r.z0), aisle_col)
			var emb := _mb("emit", r.z0)
			for sx in [-1.0, 1.0]:
				emb.add_box(Vector3(float(ax) + sx * 0.24, floor_y + 0.012, (r.z0 + r.z1) * 0.5), Vector3(0.025, 0.012, r.z1 - r.z0 - 0.08), Color(0.95, 0.85, 0.55, 0.3))


# ---------------------------------------------------------------- bulkheads, dividers
func _section_wall(mb: MeshBuilder, z: float, facing: float, door_hw: float, door_h: float, col: Color) -> void:
	## Wall across the cabin at z from the floor to the ceiling, optional centred doorway.
	var levels := 10
	var y0 := floor_y
	var y1 := ceil_y
	for k in levels:
		var ya := lerpf(y0, y1, float(k) / levels)
		var yb := lerpf(y0, y1, float(k + 1) / levels)
		var xa := _wall_x(z, ya) + 0.02
		var xb := _wall_x(z, yb) + 0.02
		if yb < floor_y + 0.0:
			continue
		var ym := (ya + yb) * 0.5
		if door_hw > 0.0 and ym < floor_y + door_h:
			for sx in [-1.0, 1.0]:
				_quad(mb, Vector3(sx * door_hw, ya, z), Vector3(sx * xa, ya, z), Vector3(sx * xb, yb, z), Vector3(sx * door_hw, yb, z), Vector3(0, 0, facing), col)
		else:
			_quad(mb, Vector3(-xa, ya, z), Vector3(xa, ya, z), Vector3(xb, yb, z), Vector3(-xb, yb, z), Vector3(0, 0, facing), col)


func _build_bulkheads() -> void:
	var front: float = lay.cabin_front
	var back: float = lay.cabin_back
	var col := Color(0.74, 0.74, 0.72)
	_section_wall(_mb("shell", front), front, 1.0, 0.42, 1.95, col)
	_section_wall(_mb("shell", back), back, -1.0, 0.0, 0.0, col)
	# class dividers: half-height panels from the wall to the aisle edge, curtains tied back
	var lc := Airlines.livery_colors(airline)
	for dv in lay.dividers:
		var z: float = dv.z
		var mb := _mb("shell", z)
		var r := _row_at(z + 0.3)
		var aisles: Array = r.aisles if not r.is_empty() else [0.0]
		var edges := []
		var xw := _wall_x(z, floor_y + 1.0)
		edges.append(-xw)
		for ax in aisles:
			edges.append(float(ax) - 0.28)
			edges.append(float(ax) + 0.28)
		edges.append(xw)
		for k in range(0, edges.size(), 2):
			var xa: float = edges[k]
			var xb: float = edges[k + 1]
			mb.add_box(Vector3((xa + xb) * 0.5, floor_y + 0.92, z), Vector3(absf(xb - xa), 1.84, 0.06), Color(0.82, 0.82, 0.8))
			# airline accent band
			mb.add_box(Vector3((xa + xb) * 0.5, floor_y + 1.6, z - 0.035), Vector3(absf(xb - xa) * 0.9, 0.05, 0.01), lc.stripe)
		for ax2 in aisles:
			for sx in [-1.0, 1.0]:
				mb.add_box(Vector3(float(ax2) + sx * 0.25, floor_y + 1.25, z), Vector3(0.08, 1.0, 0.1), (lc.tail as Color).darkened(0.3))


func _row_at(z: float) -> Dictionary:
	for r in lay.rows:
		if z >= r.z0 and z <= r.z1:
			return r
	return {}


# ---------------------------------------------------------------- galleys, lavatories, jump seats
func _build_galleys_lavs() -> void:
	var steel := Color(0.72, 0.74, 0.76)
	var dark := Color(0.3, 0.32, 0.35)
	var counter := Color(0.55, 0.57, 0.6)
	for g in lay.galleys:
		var z0: float = g.z0
		var z1: float = g.z1
		var zc := (z0 + z1) * 0.5
		var mb := _mb("shell", zc)
		var sides := [g.side] if int(g.side) != 0 else [0]
		for side in sides:
			var depth: float = g.depth
			var cx := 0.0
			var w := 0.0
			var at_back := absf(z1 - float(lay.cabin_back)) < 0.2
			if int(side) == 0:
				w = minf(depth, _wall_x(zc, floor_y + 1.0) * 2.0 - 1.2)
				cx = 0.0
				if at_back:
					# aft galley spans the rear wall, facing forward
					w = _wall_x(z1, floor_y + 1.0) * 2.0 - 0.1
			else:
				var xw := _wall_x(zc, floor_y + 1.0)
				w = depth
				cx = float(side) * (xw - depth * 0.5)
			var dz := z1 - z0
			if int(side) == 0 and at_back:
				# against the aft bulkhead: depth along z
				var gd := minf(dz, 0.8)
				var gz := z1 - gd * 0.5
				mb.add_box(Vector3(0, floor_y + 0.5, gz), Vector3(w, 1.0, gd), steel)
				mb.add_box(Vector3(0, floor_y + 1.02, gz - 0.02), Vector3(w, 0.04, gd + 0.04), counter)
				mb.add_box(Vector3(0, floor_y + 1.62, gz + 0.1), Vector3(w, 0.8, gd - 0.2), steel)
				var ncart := maxi(int(w / 0.32), 1)
				for i in ncart:
					var cxx := -w * 0.5 + (i + 0.5) * (w / ncart)
					mb.add_box(Vector3(cxx, floor_y + 0.46, gz - gd * 0.5 - 0.004), Vector3(w / ncart - 0.03, 0.86, 0.01), Color(0.62, 0.64, 0.66))
					mb.add_box(Vector3(cxx, floor_y + 0.85, gz - gd * 0.5 - 0.012), Vector3(0.12, 0.025, 0.02), dark)
				continue
			mb.add_box(Vector3(cx, floor_y + 0.5, zc), Vector3(w, 1.0, dz), steel)
			mb.add_box(Vector3(cx, floor_y + 1.02, zc), Vector3(w + 0.04, 0.04, dz), counter)
			var top := minf(floor_y + 2.0, ceil_y - 0.02)
			mb.add_box(Vector3(cx + (float(side) * 0.1 if int(side) != 0 else 0.0), (floor_y + 1.4 + top) * 0.5, zc), Vector3(maxf(w - 0.2, 0.2), top - floor_y - 1.4, dz), steel)
			# oven doors and cart faces on the aisle-facing side
			var face_x := cx - float(side) * w * 0.5 - (0.006 if int(side) != 0 else 0.0)
			if int(side) != 0:
				var nc := maxi(int(dz / 0.33), 1)
				for i2 in nc:
					var cz := z0 + (i2 + 0.5) * (dz / nc)
					mb.add_box(Vector3(face_x, floor_y + 0.46, cz), Vector3(0.01, 0.86, dz / nc - 0.03), Color(0.62, 0.64, 0.66))
					mb.add_box(Vector3(face_x - float(side) * 0.01, floor_y + 0.86, cz), Vector3(0.02, 0.025, 0.12), dark)
					mb.add_box(Vector3(face_x + float(side) * 0.1, floor_y + 1.62, cz), Vector3(0.01, 0.28, dz / nc - 0.08), Color(0.2, 0.22, 0.24))
	for lv in lay.lavs:
		var z0b: float = lv.z0
		var z1b: float = lv.z1
		var zcb := (z0b + z1b) * 0.5
		var side3 := int(lv.side)
		var xw2 := _wall_x(zcb, floor_y + 1.0)
		var depth2: float = minf(float(lv.depth), xw2 - 0.3)
		var cx2 := float(side3) * (xw2 - depth2 * 0.5 + 0.05)
		var top2 := minf(floor_y + 2.0, ceil_y - 0.02)
		var mb5 := _mb("shell", zcb)
		mb5.add_box(Vector3(cx2, (floor_y + top2) * 0.5, zcb), Vector3(depth2, top2 - floor_y, z1b - z0b), Color(0.78, 0.78, 0.76))
		# door on the aisle side with a sign
		var dx := cx2 - float(side3) * (depth2 * 0.5 + 0.005)
		mb5.add_box(Vector3(dx, floor_y + 0.95, zcb), Vector3(0.012, 1.8, (z1b - z0b) - 0.18), Color(0.82, 0.83, 0.82))
		mb5.add_box(Vector3(dx - float(side3) * 0.012, floor_y + 1.0, zcb + (z1b - z0b) * 0.3), Vector3(0.02, 0.1, 0.03), Color(0.4, 0.42, 0.45))
		var emb := _mb("emit", zcb)
		emb.add_box(Vector3(dx - float(side3) * 0.01, floor_y + 1.85, zcb), Vector3(0.01, 0.07, 0.16), Color(0.2, 0.9, 0.3, 0.1))


# ---------------------------------------------------------------- exit signs
func _build_signs() -> void:
	for d in lay.doors:
		var emb := _mb("emit", d.z)
		var side: int = d.side
		var top: float = floor_y + (d.height if d.kind == "door" else 1.3) + 0.12
		var x := side * (_wall_x(d.z, top) - 0.03)
		emb.add_box(Vector3(x, top, d.z), Vector3(0.02, 0.1, 0.32), Color(0.1, 1.0, 0.35, 1.0))
		emb.add_box(Vector3(x - side * 0.004, top, d.z), Vector3(0.02, 0.06, 0.22), Color(0.95, 1.0, 0.95, 1.0))
	# ceiling-hung exit signs over the aisles at each exit row/door zone
	var y := ceil_y - 0.12
	for d2 in lay.doors:
		if d2.side > 0:
			continue
		for ax in lay.aisles:
			var emb2 := _mb("emit", d2.z)
			emb2.add_box(Vector3(float(ax), y, d2.z + (0.7 if d2.kind == "door" else 0.0)), Vector3(0.3, 0.1, 0.02), Color(0.1, 1.0, 0.35, 1.0))
	# seat belt / no smoking signs near the front of each cabin zone
	var r0 = lay.rows[0] if not lay.rows.is_empty() else {}
	if not r0.is_empty():
		var emb3 := _mb("emit", r0.z0)
		emb3.add_box(Vector3(0, ceil_y - 0.1, r0.z0 - 0.3), Vector3(0.36, 0.1, 0.02), Color(0.95, 0.95, 0.9, 0.5))


# ---------------------------------------------------------------- doors and escape slides
func _build_doors() -> void:
	var panel_col := Color(0.74, 0.74, 0.72)
	for d in lay.doors:
		var side: int = d.side
		var pivot := Node3D.new()
		pivot.name = "Door_" + d.name
		var w: float = d.width
		var h: float = d.height if d.kind == "door" else 0.94
		var y0: float = floor_y if d.kind == "door" else floor_y + 0.36
		var xw := _wall_x(d.z, y0 + h * 0.5)
		pivot.position = Vector3(side * (xw + INSET * 0.4), y0, d.z - w * 0.5)
		add_child(pivot)
		var mb := MeshBuilder.new()
		mb.add_box(Vector3(0, h * 0.5, w * 0.5), Vector3(INSET * 0.6, h, w), panel_col)
		# porthole, handle and arming panel on the inside face
		var inner_x := -side * INSET * 0.3
		mb.add_box(Vector3(inner_x - side * 0.005, h * 0.72, w * 0.5), Vector3(0.01, 0.2, 0.16), Color(0.08, 0.1, 0.13))
		if d.kind == "door":
			mb.add_box(Vector3(inner_x - side * 0.03, h * 0.55, w * 0.78), Vector3(0.05, 0.05, 0.3), Color(0.3, 0.32, 0.36))
			mb.add_box(Vector3(inner_x - side * 0.008, h * 0.38, w * 0.3), Vector3(0.012, 0.12, 0.18), Color(0.85, 0.2, 0.15))
		else:
			mb.add_box(Vector3(inner_x - side * 0.02, h * 0.9, w * 0.5), Vector3(0.03, 0.04, 0.24), Color(0.85, 0.2, 0.15))
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = mat_shell
		pivot.add_child(mi)
		door_nodes[d.name] = {"pivot": pivot, "open": 0.0, "target": 0.0, "side": side, "z": d.z, "kind": d.kind, "mesh": mi}


func open_door(door_name: String, open: bool = true) -> void:
	if door_nodes.has(door_name):
		door_nodes[door_name].target = 1.0 if open else 0.0


## Deploy an escape slide at a door. ground_y: ground height in body coordinates.
func deploy_slide(door_name: String, ground_y: float, water: bool = false) -> void:
	if slides.has(door_name) or not door_nodes.has(door_name):
		return
	var dn: Dictionary = door_nodes[door_name]
	var side: int = dn.side
	var sill := Vector3(side * (_wall_x(dn.z, floor_y + 0.5) + INSET + 0.05), floor_y, dn.z)
	var drop := maxf(sill.y - ground_y, 0.3)
	var mb := MeshBuilder.new()
	var yellow := Color(1.0, 0.82, 0.12)
	var rings := []
	var n := 8
	var length := drop / 0.55 if not water else 4.0
	for i in n + 1:
		var f := float(i) / n
		var out := f * length * 0.84
		var y := 0.05
		if not water:
			y = -drop * (f * f * 0.35 + f * 0.65)
		var c := Vector3(side * out, y, 0.0)
		var ring := PackedVector3Array()
		for k in 8:
			var a := TAU * float(k) / 8.0
			ring.append(c + Vector3(0, cos(a) * 0.18 + 0.1, sin(a) * 0.7 * (1.0 if absf(sin(a)) > 0.3 else 0.9)))
		rings.append(ring)
	mb.add_loft(rings, yellow, true, true)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.5
	mi.material_override = m
	var piv := Node3D.new()
	piv.position = sill
	piv.scale = Vector3(0.05, 0.05, 1)
	add_child(piv)
	piv.add_child(mi)
	piv.set_meta("grow", 0.0)
	slides[door_name] = piv


# ---------------------------------------------------------------- seats
static func seat_mesh(cls: String, width: float, airline_code: String) -> ArrayMesh:
	var lc := Airlines.livery_colors(airline_code)
	var fabric: Color = (lc.get("tail", Color(0.15, 0.2, 0.4)) as Color).darkened(0.25)
	if fabric.get_luminance() > 0.55:
		fabric = (lc.get("stripe", Color(0.3, 0.3, 0.6)) as Color).darkened(0.35)
	var frame := Color(0.3, 0.31, 0.33)
	var plastic := Color(0.78, 0.78, 0.76)
	var head := Color(0.86, 0.86, 0.84)
	var mb := MeshBuilder.new()
	var w := width - 0.05
	match cls:
		"business", "premium", "vip", "crew_rest":
			var leather := Color(0.22, 0.23, 0.26) if cls != "vip" else Color(0.86, 0.8, 0.68)
			if cls == "premium":
				leather = fabric.lightened(0.1)
			if cls == "crew_rest":
				leather = Color(0.32, 0.34, 0.38)
			mb.add_box(Vector3(0, 0.44, -0.22), Vector3(w - 0.08, 0.14, 0.55), leather)
			var back := Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0, 0.86, 0.1))
			mb.add_box_xf(back, Vector3(w - 0.06, 0.82, 0.14), leather)
			mb.add_box_xf(back * Transform3D(Basis(), Vector3(0, 0.44, 0.0)), Vector3(w - 0.16, 0.16, 0.12), head if cls != "vip" else leather)
			for sx in [-1.0, 1.0]:
				mb.add_box(Vector3(sx * (w * 0.5 - 0.05), 0.6, -0.15), Vector3(0.1, 0.08, 0.58), plastic)
				mb.add_box(Vector3(sx * (w * 0.5 - 0.05), 0.42, -0.15), Vector3(0.08, 0.3, 0.5), frame)
			mb.add_box(Vector3(0, 0.28, -0.52), Vector3(w - 0.2, 0.08, 0.2), leather)
			if cls == "business" and width > 0.6:
				# shell privacy screen for wide business seats
				mb.add_box(Vector3(-w * 0.5, 0.6, -0.1), Vector3(0.04, 1.0, 0.95), plastic)
		"ga":
			mb.add_box(Vector3(0, 0.36, -0.2), Vector3(w - 0.06, 0.12, 0.46), Color(0.5, 0.42, 0.32))
			var back2 := Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.72, 0.06))
			mb.add_box_xf(back2, Vector3(w - 0.06, 0.62, 0.1), Color(0.5, 0.42, 0.32))
		_:
			mb.add_box(Vector3(0, 0.43, -0.2), Vector3(w - 0.04, 0.11, 0.46), fabric)
			var back3 := Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.8, 0.08))
			mb.add_box_xf(back3, Vector3(w - 0.03, 0.72, 0.09), fabric)
			mb.add_box_xf(back3 * Transform3D(Basis(), Vector3(0, 0.3, 0.0)), Vector3(w - 0.12, 0.16, 0.1), head)
			# seat-back tray table and pocket
			mb.add_box_xf(back3 * Transform3D(Basis(), Vector3(0, 0.08, 0.05)), Vector3(w - 0.12, 0.3, 0.012), plastic)
			mb.add_box_xf(back3 * Transform3D(Basis(), Vector3(0, -0.22, 0.06)), Vector3(w - 0.14, 0.18, 0.02), fabric.darkened(0.3))
			for sx2 in [-1.0, 1.0]:
				mb.add_box(Vector3(sx2 * (w * 0.5), 0.6, -0.13), Vector3(0.05, 0.05, 0.42), plastic)
			mb.add_box(Vector3(0, 0.28, -0.12), Vector3(w - 0.1, 0.05, 0.36), frame)
	# legs
	for sx3 in [-1.0, 1.0]:
		mb.add_box(Vector3(sx3 * (w * 0.5 - 0.08), 0.18, -0.12), Vector3(0.035, 0.36, 0.035), frame)
		mb.add_box(Vector3(sx3 * (w * 0.5 - 0.08), 0.02, -0.12), Vector3(0.035, 0.03, 0.5), frame)
	return mb.commit()


func _build_seats() -> void:
	var groups := {}   # "cls:width:chunk" -> Array of transforms
	for s in lay.seats:
		var key := "%s:%.2f:%d" % [s.cls, s.width, _chunk(s.pos.z)]
		if not groups.has(key):
			groups[key] = []
		var b := Basis.IDENTITY
		if float(s.get("facing", -1.0)) > 0.0:
			b = Basis(Vector3.UP, PI)
		groups[key].append(Transform3D(b, s.pos))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.75
	for key2 in groups.keys():
		var parts: PackedStringArray = key2.split(":")
		var mesh := seat_mesh(parts[0], float(parts[1]), airline)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var arr: Array = groups[key2]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
		seat_mmis.append(mmi)


# ---------------------------------------------------------------- oxygen masks
func _build_masks() -> void:
	if float(bin.depth) <= 0.0 and cat != "bizjet":
		return
	mask_root = Node3D.new()
	mask_root.name = "OxygenMasks"
	add_child(mask_root)
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, 0.0, 0), Vector3(0, -0.06, 0), 0.04, 0.05, 8, Color(0.98, 0.85, 0.1), true)
	mb.add_cylinder(Vector3(0, 0.0, 0), Vector3(0, 0.55, 0), 0.006, 0.006, 4, Color(0.9, 0.9, 0.9), false)
	var mesh := mb.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = lay.seats.size()
	var yb := floor_y + float(bin.bottom) - 0.62
	for i in lay.seats.size():
		var s: Dictionary = lay.seats[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(s.pos.x, yb, s.pos.z - 0.45)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mmi.material_override = m
	mask_root.add_child(mmi)
	mask_root.visible = false


func deploy_masks() -> void:
	masks_target = 1.0
	if mask_root:
		mask_root.visible = true


# ---------------------------------------------------------------- lighting
func _build_lights() -> void:
	var z0: float = lay.cabin_front
	var z1: float = lay.cabin_back
	var n := maxi(int((z1 - z0) / 5.5), 1)
	for i in n:
		var l := OmniLight3D.new()
		l.position = Vector3(0, ceil_y - 0.2, z0 + (i + 0.5) * (z1 - z0) / n)
		l.omni_range = 5.5 if cat != "widebody" else 7.0
		l.omni_attenuation = 1.2
		l.light_energy = 0.8
		l.shadow_enabled = false
		l.light_specular = 0.2
		add_child(l)
		lights.append(l)


## Lighting scenes: boarding, cruise, night (dimmed blue), takeoff (dim), emergency, off.
func set_light_mode(mode: String) -> void:
	light_mode = mode
	var energy := 0.5
	var col := Color(1.0, 0.97, 0.92)
	var wash := 1.0
	var tint := Color(1.0, 0.95, 0.86)
	var path := 0.0
	match mode:
		"cruise":
			energy = 0.42
		"night":
			energy = 0.12
			col = Color(0.55, 0.62, 1.0)
			wash = 0.35
			tint = Color(0.45, 0.55, 1.0)
		"takeoff":
			energy = 0.22
			wash = 0.4
		"emergency":
			energy = 0.06
			col = Color(1.0, 0.95, 0.85)
			wash = 0.0
			path = 1.6
		"off":
			energy = 0.0
			wash = 0.0
	for l in lights:
		l.light_energy = energy
		l.light_color = col
	mat_emit.set_shader_parameter("wash_e", wash)
	mat_emit.set_shader_parameter("wash_tint", tint)
	mat_emit.set_shader_parameter("path_e", path)
	mat_emit.set_shader_parameter("exit_e", 1.6 if mode == "emergency" else 1.0)


func set_signs(seatbelt: bool) -> void:
	mat_emit.set_shader_parameter("belt_e", 1.4 if seatbelt else 0.0)


func set_flicker(amount: float) -> void:
	mat_emit.set_shader_parameter("flicker", amount)


func _process(delta: float) -> void:
	_t += delta
	for k in door_nodes.keys():
		var dn: Dictionary = door_nodes[k]
		if absf(dn.open - dn.target) > 0.001:
			dn.open = move_toward(dn.open, dn.target, delta * 0.6)
			var piv: Node3D = dn.pivot
			if dn.kind == "door":
				# plug door: swings outward and forward around its leading edge
				piv.rotation.y = -float(dn.side) * dn.open * 1.75
			else:
				piv.visible = dn.open < 0.5
	for k2 in slides.keys():
		var sl: Node3D = slides[k2]
		var g := minf(float(sl.get_meta("grow")) + delta * 0.18, 1.0)
		sl.set_meta("grow", g)
		var e := U.smooth01(g)
		sl.scale = Vector3(maxf(e, 0.05), maxf(e, 0.05), 1)
	if mask_root and masks_deployed < masks_target:
		masks_deployed = minf(masks_deployed + delta * 1.4, 1.0)
		mask_root.position.y = (1.0 - masks_deployed) * 0.55
		mask_root.rotation.z = sin(_t * 3.0) * 0.01
