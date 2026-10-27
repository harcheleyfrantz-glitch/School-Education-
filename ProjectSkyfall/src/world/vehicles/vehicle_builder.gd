class_name VehicleBuilder
extends RefCounted
## Procedural airport ground vehicles built to the same standard as the aircraft: rounded
## bodies, glazed cabs with frames, lathed tyres with tread and rims, grilles, mirrors,
## handrails, chevrons and working lamps. One body mesh per vehicle (material classes packed in
## vertex alpha), a lamp mesh, separately spinning/steering wheels and animated parts
## (tug cradle, belt boom, catering lift, stairs, fire monitors).
## Vehicle frame: +X right, +Y up, -Z forward, origin on the ground at the footprint centre.

const PAINT := 1.0
const RUBBER := 0.8
const METAL := 0.55
const MATTE := 0.3
const GLASS := 0.05
# lamp modes (vertex alpha); the fractional part of a band carries the blink phase
const LAMP_STEADY := 0.95
const LAMP_HEAD := 0.2

const YELLOW := Color(0.95, 0.71, 0.07)
const DARK := Color(0.12, 0.125, 0.135)
const BLACK := Color(0.035, 0.035, 0.04)
const STEEL := Color(0.6, 0.62, 0.64)
const CHROME := Color(0.84, 0.85, 0.87)
const GLASS_C := Color(0.12, 0.17, 0.22)
const WHITE := Color(0.93, 0.94, 0.95)
const RED := Color(0.78, 0.06, 0.05)
const LIME := Color(0.76, 0.86, 0.1)
const AMBER := Color(1.0, 0.5, 0.04)
const KINDS := ["tug", "tractor", "cart", "uld_dolly", "belt_loader", "fuel_truck", "catering", "stairs", "gpu", "arff", "ambulance", "follow_me", "bus"]

static var _mat_body: ShaderMaterial
static var _mat_lamp: ShaderMaterial
static var _cache := {}
static var _wheel_meshes := {}


static func body_material() -> ShaderMaterial:
	if _mat_body == null:
		_mat_body = ShaderMaterial.new()
		_mat_body.shader = load("res://shaders/vehicle.gdshader")
	return _mat_body


static func lamp_material() -> ShaderMaterial:
	if _mat_lamp == null:
		_mat_lamp = ShaderMaterial.new()
		_mat_lamp.shader = load("res://shaders/vehicle_lamp.gdshader")
	return _mat_lamp


## Builds (or instances from the cache) a vehicle. livery: {main, accent, text}.
static func build(kind: String, livery: Dictionary = {}) -> Node3D:
	var main: Color = livery.get("main", YELLOW)
	var accent: Color = livery.get("accent", DARK)
	var key := "%s|%s|%s|%s" % [kind, main.to_html(false), accent.to_html(false), String(livery.get("text", ""))]
	if not _cache.has(key):
		_cache[key] = _make(kind, main, accent, String(livery.get("text", "")))
	return _instance(_cache[key], kind)


static func _make(kind: String, main: Color, accent: Color, text: String) -> Dictionary:
	var c := {"mb": MeshBuilder.new(), "lb": MeshBuilder.new(), "wheels": [], "parts": {}, "labels": [],
		"meta": {}, "main": main, "accent": accent, "text": text, "stack": []}
	c.body_mb = c.mb
	c.body_lb = c.lb
	match kind:
		"tug":
			_tug(c)
		"tractor":
			_tractor(c)
		"cart":
			_cart(c)
		"uld_dolly":
			_uld_dolly(c)
		"belt_loader":
			_belt_loader(c)
		"fuel_truck":
			_fuel_truck(c)
		"catering":
			_catering(c)
		"stairs":
			_stairs(c)
		"gpu":
			_gpu(c)
		"arff":
			_arff(c)
		"ambulance":
			_ambulance(c)
		"follow_me":
			_follow_me(c)
		"bus":
			_bus(c)
	var out := {"body": c.body_mb.commit(), "lamps": c.body_lb.commit(), "wheels": c.wheels, "labels": c.labels,
		"meta": c.meta, "parts": {}}
	for pn in c.parts.keys():
		var pd: Dictionary = c.parts[pn]
		out.parts[pn] = {"body": pd.mb.commit(), "lamps": pd.lb.commit(), "pivot": pd.pivot, "parent": pd.parent,
			"labels": pd.labels}
	return out


static func _instance(d: Dictionary, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	root.set_meta("kind", kind)
	for k in d.meta.keys():
		root.set_meta(k, d.meta[k])
	_add_meshes(root, d.body, d.lamps)
	for l in d.labels:
		_add_label(root, l)
	var part_nodes := {}
	# parts may be nested (a turret on a boom): create parents first
	var pending: Array = d.parts.keys()
	var guard := 0
	while not pending.is_empty() and guard < 20:
		guard += 1
		for pn in pending.duplicate():
			var pd: Dictionary = d.parts[pn]
			var parent_name := String(pd.parent)
			if parent_name != "" and not part_nodes.has(parent_name):
				continue
			var pivot := Node3D.new()
			pivot.name = pn
			var parent_node: Node3D = root if parent_name == "" else part_nodes[parent_name]
			var parent_pivot: Vector3 = Vector3.ZERO if parent_name == "" else d.parts[parent_name].pivot
			pivot.position = pd.pivot - parent_pivot
			parent_node.add_child(pivot)
			_add_meshes(pivot, pd.body, pd.lamps)
			for l2 in pd.labels:
				_add_label(pivot, l2)
			part_nodes[pn] = pivot
			pending.erase(pn)
	var wheels := []
	for w in d.wheels:
		var steer := Node3D.new()
		steer.name = "wheel_%d" % wheels.size()
		steer.position = w.pos
		root.add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		var mi := MeshInstance3D.new()
		mi.mesh = _wheel_mesh(float(w.r), float(w.w), bool(w.dual))
		mi.material_override = body_material()
		if float(w.pos.x) < 0.0:
			mi.rotation.y = PI
		spin.add_child(mi)
		wheels.append({"steer": steer, "spin": spin, "r": w.r, "front": w.steer})
	root.set_meta("wheels", wheels)
	root.set_meta("parts", part_nodes)
	return root


static func _add_meshes(parent: Node3D, body: ArrayMesh, lamps: ArrayMesh) -> void:
	if body.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Body"
		mi.mesh = body
		mi.material_override = body_material()
		parent.add_child(mi)
	if lamps.get_surface_count() > 0:
		var li := MeshInstance3D.new()
		li.name = "Lamps"
		li.mesh = lamps
		li.material_override = lamp_material()
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(li)


static func _add_label(parent: Node3D, l: Dictionary) -> void:
	var lb := Label3D.new()
	lb.text = l.text
	lb.transform = l.xf
	lb.pixel_size = float(l.size) / 64.0
	lb.font_size = 64
	lb.outline_size = 0
	lb.modulate = l.col
	lb.double_sided = false
	lb.shaded = true
	lb.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	lb.font = _font()
	parent.add_child(lb)


static var _font_res: SystemFont


static func _font() -> SystemFont:
	if _font_res == null:
		_font_res = SystemFont.new()
		_font_res.font_names = PackedStringArray(["DejaVu Sans", "Arial", "Helvetica", "sans-serif"])
		_font_res.font_weight = 800
		_font_res.multichannel_signed_distance_field = true
	return _font_res


# ================================================================== animation helpers
## Rolls the wheels for a distance travelled (m) and steers the front wheels (degrees).
static func roll(v: Node3D, dist: float, steer_deg: float = 0.0) -> void:
	var wheels: Array = v.get_meta("wheels", [])
	for w in wheels:
		var spin: Node3D = w.spin
		spin.rotation.x -= dist / maxf(float(w.r), 0.05)
		if w.front:
			var st: Node3D = w.steer
			st.rotation.y = deg_to_rad(-steer_deg)


## Raises a catering truck body (metres above its travel position) and works the scissors.
static func set_lift(v: Node3D, h: float) -> void:
	var lift := part(v, "lift")
	if lift == null:
		return
	var low := float(v.get_meta("lift_low", 1.3))
	lift.position.y = low + h
	var top_y := low + h - 0.02
	var half := 2.3
	for side in ["l", "r"]:
		for k in 2:
			var arm := part(v, "scissor_%s%d" % [side, k])
			if arm == null:
				continue
			var x := arm.position.x
			var z_from := 1.4 + (half if k == 0 else -half)
			var z_to := 1.4 - (half if k == 0 else -half)
			var a := Vector3(x, 1.16, z_from)
			var b := Vector3(x, top_y, z_to)
			arm.position = a
			arm.basis = Basis.looking_at(b - a, Vector3.UP)
			arm.scale = Vector3(1, 1, (b - a).length())


static func part(v: Node3D, part_name: String) -> Node3D:
	var parts: Dictionary = v.get_meta("parts", {})
	return parts.get(part_name, null)


static func set_lamps(v: Node3D, beacons: bool, lights: bool) -> void:
	for mi in v.find_children("Lamps", "MeshInstance3D", true, false):
		mi.set_instance_shader_parameter("active", 1.0 if beacons else 0.0)
		mi.set_instance_shader_parameter("lights_on", 1.0 if lights else 0.0)


# ================================================================== primitives
static func _col(col: Color, cls: float) -> Color:
	return Color(col.r, col.g, col.b, cls)


static func _rb(c: Dictionary, center: Vector3, size: Vector3, col: Color, cls: float = PAINT, e: float = 0.2,
		b: Basis = Basis(), nu: int = 12, nv: int = 8) -> void:
	var mb: MeshBuilder = c.mb
	mb.add_rounded_box(center, size, _col(col, cls), e, nu, nv, b)


static func _bx(c: Dictionary, center: Vector3, size: Vector3, col: Color, cls: float = PAINT) -> void:
	var mb: MeshBuilder = c.mb
	mb.add_box(center, size, _col(col, cls))


static func _cy(c: Dictionary, a: Vector3, b: Vector3, r: float, col: Color, cls: float = METAL, segs: int = 10, r2: float = -1.0) -> void:
	var mb: MeshBuilder = c.mb
	mb.add_cylinder(a, b, r, r if r2 < 0.0 else r2, segs, _col(col, cls), true)


static func _glass(c: Dictionary, center: Vector3, size: Vector3, b: Basis = Basis()) -> void:
	var mb: MeshBuilder = c.mb
	mb.add_rounded_box(center, size, _col(GLASS_C, GLASS), 0.12, 8, 6, b)


static func _lamp(c: Dictionary, center: Vector3, size: Vector3, col: Color, mode: String = "steady", phase: float = 0.0) -> void:
	var a := LAMP_STEADY
	match mode:
		"beacon":
			a = 0.6 + 0.29 * fposmod(phase, 1.0)
		"strobe":
			a = 0.4 + 0.19 * fposmod(phase, 1.0)
		"head":
			a = LAMP_HEAD
	var lb: MeshBuilder = c.lb
	lb.add_rounded_box(center, size, Color(col.r, col.g, col.b, a), 0.35, 8, 6)


static func _rail(c: Dictionary, pts: Array, r: float, col: Color = STEEL) -> void:
	for i in pts.size() - 1:
		_cy(c, pts[i], pts[i + 1], r, col, METAL, 8)
	for p in pts:
		var mb: MeshBuilder = c.mb
		mb.add_sphere(p, Vector3.ONE * r * 1.15, 6, 4, _col(col, METAL))


static func _label(c: Dictionary, text: String, pos: Vector3, facing: Vector3, size: float, col: Color = Color.WHITE) -> void:
	## Painted lettering: a Label3D lying on a body face (facing = outward normal of the face).
	var f := facing.normalized()
	var up := Vector3.UP if absf(f.y) < 0.9 else Vector3(0, 0, -1)
	var x := up.cross(f).normalized()
	var y := f.cross(x).normalized()
	var labels: Array = c.labels
	var off: Vector3 = c.get("label_off", Vector3.ZERO)
	labels.append({"text": text, "xf": Transform3D(Basis(x, y, f), pos + f * 0.006 - off), "size": size, "col": col})


static func _stripes(c: Dictionary, origin: Vector3, u: Vector3, v: Vector3, n: int, ca: Color, cb: Color, slant: float = 0.5, cls: float = PAINT) -> void:
	## Diagonal hazard stripes painted on a face spanned by u (width) and v (height) from origin.
	var mb: MeshBuilder = c.mb
	var nrm := u.cross(v).normalized()
	var o := origin + nrm * 0.004
	var step := u / float(n)
	var sh := u.normalized() * v.length() * slant
	for i in n + 1:
		var a0 := o + step * float(i) - sh * 0.5
		var a1 := a0 + step
		var p0 := _clip_face(a0, origin, u)
		var p1 := _clip_face(a1, origin, u)
		var p2 := _clip_face(a1 + v + sh, origin + v, u)
		var p3 := _clip_face(a0 + v + sh, origin + v, u)
		if (p1 - p0).length() < 0.001 and (p2 - p3).length() < 0.001:
			continue
		mb.add_quad(p0 + nrm * 0.004, p1 + nrm * 0.004, p2 + nrm * 0.004, p3 + nrm * 0.004, _col(ca if i % 2 == 0 else cb, cls))


static func _clip_face(p: Vector3, edge_origin: Vector3, u: Vector3) -> Vector3:
	## Clamps a point along u to the face span [edge_origin, edge_origin + u].
	var ud := u.normalized()
	var t := clampf((p - edge_origin).dot(ud), 0.0, u.length())
	var perp := (p - edge_origin) - ud * (p - edge_origin).dot(ud)
	return edge_origin + ud * t + perp


static func _checker(c: Dictionary, origin: Vector3, u: Vector3, v: Vector3, nu: int, nv: int, ca: Color, cb: Color) -> void:
	var mb: MeshBuilder = c.mb
	var nrm := u.cross(v).normalized() * 0.005
	for j in nv:
		for i in nu:
			var p0 := origin + u * (float(i) / nu) + v * (float(j) / nv) + nrm
			var p1 := p0 + u / float(nu)
			var p2 := p1 + v / float(nv)
			var p3 := p0 + v / float(nv)
			mb.add_quad(p0, p1, p2, p3, _col(ca if (i + j) % 2 == 0 else cb, PAINT))


static func _grille(c: Dictionary, center: Vector3, w: float, h: float, slats: int, facing: Vector3) -> void:
	## Recessed dark grille with chrome slats on a face pointing along facing (±Z).
	var f := signf(facing.z)
	_bx(c, center, Vector3(w, h, 0.04), BLACK, RUBBER)
	for i in slats:
		var y := center.y - h * 0.5 + h * (float(i) + 0.5) / slats
		_bx(c, Vector3(center.x, y, center.z + f * 0.025), Vector3(w * 0.96, h / slats * 0.32, 0.02), CHROME, METAL)


static func _mirror(c: Dictionary, base: Vector3, side: float, reach: float = 0.35, h: float = 0.32) -> void:
	var tip := base + Vector3(side * reach, 0.05, -0.05)
	_cy(c, base, tip, 0.018, DARK, METAL, 6)
	_rb(c, tip + Vector3(side * 0.02, 0.0, 0.0), Vector3(0.08, h, 0.2), BLACK, RUBBER, 0.25, Basis(), 8, 6)
	_glass(c, tip + Vector3(side * 0.02, 0.0, 0.055), Vector3(0.06, h * 0.86, 0.02))


static func _seat(c: Dictionary, pos: Vector3, col: Color = DARK) -> void:
	_rb(c, pos + Vector3(0, 0.05, 0), Vector3(0.52, 0.12, 0.5), col, MATTE, 0.35, Basis(), 8, 6)
	_rb(c, pos + Vector3(0, 0.38, 0.22), Vector3(0.5, 0.62, 0.11), col, MATTE, 0.35, Basis(), 8, 6)


static func _steering_wheel(c: Dictionary, center: Vector3, tilt_deg: float, r: float = 0.19) -> void:
	var b := Basis(Vector3.RIGHT, deg_to_rad(tilt_deg))
	var mb: MeshBuilder = c.mb
	var n := 14
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var p0 := center + b * Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := center + b * Vector3(cos(a1) * r, sin(a1) * r, 0)
		mb.add_cylinder(p0, p1, 0.016, 0.016, 6, _col(BLACK, RUBBER), false)
	_cy(c, center, center + b * Vector3(0, 0, 0.45), 0.025, DARK, METAL, 8)


static func _ladder(c: Dictionary, bottom: Vector3, top: Vector3, width: float, rungs: int) -> void:
	var side := Vector3(width * 0.5, 0, 0)
	_cy(c, bottom - side, top - side, 0.022, STEEL)
	_cy(c, bottom + side, top + side, 0.022, STEEL)
	for i in rungs:
		var p := bottom.lerp(top, (float(i) + 0.5) / rungs)
		_cy(c, p - side, p + side, 0.016, STEEL, METAL, 6)


static func _wheel(c: Dictionary, pos: Vector3, r: float, w: float, steer: bool = false, dual: bool = false) -> void:
	var wheels: Array = c.wheels
	wheels.append({"pos": pos, "r": r, "w": w, "steer": steer, "dual": dual})


static func _wheel_arch(c: Dictionary, pos: Vector3, r: float, w: float, col: Color, side: float) -> void:
	## Fender over a wheel: a thin rounded shell following the tyre.
	var n := 7
	for i in n:
		var a0 := lerpf(PI * 0.12, PI * 0.88, float(i) / n)
		var a1 := lerpf(PI * 0.12, PI * 0.88, float(i + 1) / n)
		var p0 := pos + Vector3(0, sin(a0), -cos(a0)) * (r + 0.08)
		var p1 := pos + Vector3(0, sin(a1), -cos(a1)) * (r + 0.08)
		var mid := (p0 + p1) * 0.5
		var tang := (p1 - p0)
		var b := Basis.looking_at(tang.normalized(), (mid - pos).normalized())
		_rb(c, mid + Vector3(side * 0.01, 0, 0), Vector3(w + 0.1, 0.04, tang.length() + 0.04), col, PAINT, 0.2, b, 6, 4)


static func _begin_part(c: Dictionary, part_name: String, pivot: Vector3, parent: String = "") -> void:
	var pd := {"mb": MeshBuilder.new(), "lb": MeshBuilder.new(), "pivot": pivot, "parent": parent, "labels": []}
	pd.mb.xf = Transform3D(Basis(), -pivot)
	pd.lb.xf = Transform3D(Basis(), -pivot)
	var stack: Array = c.stack
	stack.append([c.mb, c.lb, c.labels, c.get("label_off", Vector3.ZERO)])
	c.mb = pd.mb
	c.lb = pd.lb
	c.labels = pd.labels
	c.label_off = pivot
	c.parts[part_name] = pd


static func _end_part(c: Dictionary) -> void:
	var stack: Array = c.stack
	var prev: Array = stack.pop_back()
	c.mb = prev[0]
	c.lb = prev[1]
	c.labels = prev[2]
	c.label_off = prev[3]


# ================================================================== wheels
static func _wheel_mesh(r: float, w: float, dual: bool) -> ArrayMesh:
	var key := "%.3f|%.3f|%s" % [r, w, dual]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var mb := MeshBuilder.new()
	var segs := 28 if r > 0.3 else 20
	var tyres: Array = [[0.0, w]] if not dual else [[-w * 0.26, w * 0.47], [w * 0.26, w * 0.47]]
	for t in tyres:
		var x0: float = t[0]
		var tw: float = t[1]
		var hw := tw * 0.5
		var prof := [
			Vector2(x0 - hw * 0.98, r * 0.6), Vector2(x0 - hw, r * 0.7), Vector2(x0 - hw * 1.03, r * 0.83),
			Vector2(x0 - hw * 0.96, r * 0.94), Vector2(x0 - hw * 0.78, r * 0.99), Vector2(x0 - hw * 0.5, r),
			Vector2(x0 + hw * 0.5, r), Vector2(x0 + hw * 0.78, r * 0.99), Vector2(x0 + hw * 0.96, r * 0.94),
			Vector2(x0 + hw * 1.03, r * 0.83), Vector2(x0 + hw, r * 0.7), Vector2(x0 + hw * 0.98, r * 0.6),
		]
		_lathe(mb, prof, segs, _col(Color(0.045, 0.045, 0.05), RUBBER), r, 0.022)
	# rim on the outer (+X) face: lip, dish, hub and cap
	var xo := w * 0.5 * (1.0 if not dual else 1.0)
	var rim := [
		Vector2(xo - 0.01, r * 0.62), Vector2(xo + 0.004, r * 0.6), Vector2(xo - w * 0.08, r * 0.52),
		Vector2(xo - w * 0.12, r * 0.38), Vector2(xo - w * 0.1, r * 0.24), Vector2(xo - w * 0.02, r * 0.2),
		Vector2(xo, r * 0.12), Vector2(xo + 0.006, 0.0),
	]
	_lathe(mb, rim, segs, _col(Color(0.7, 0.71, 0.73), METAL), r, 0.0)
	# inner face: brake disc / axle cover
	var inner := [Vector2(-w * 0.48, 0.0), Vector2(-w * 0.5, r * 0.3), Vector2(-w * 0.47, r * 0.6)]
	_lathe(mb, inner, segs, _col(Color(0.18, 0.18, 0.19), METAL), r, 0.0)
	# spokes and lug nuts
	var nuts := 6 if r > 0.4 else 5
	for i in nuts:
		var a := TAU * float(i) / nuts
		var dir := Vector3(0, cos(a), sin(a))
		var p0 := Vector3(xo - w * 0.1, 0, 0) + dir * r * 0.26
		var p1 := Vector3(xo - w * 0.06, 0, 0) + dir * r * 0.5
		var b := Basis(Vector3(1, 0, 0), dir, Vector3(1, 0, 0).cross(dir))
		mb.add_rounded_box((p0 + p1) * 0.5, Vector3(0.025, (p1 - p0).length(), r * 0.09), _col(Color(0.66, 0.67, 0.7), METAL), 0.3, 6, 4, b)
		var np := Vector3(xo - w * 0.015, 0, 0) + Vector3(0, cos(a + PI / nuts), sin(a + PI / nuts)) * r * 0.15
		mb.add_cylinder(np, np + Vector3(0.025, 0, 0), r * 0.025, r * 0.022, 6, _col(Color(0.8, 0.8, 0.82), METAL), true)
	var m := mb.commit()
	_wheel_meshes[key] = m
	return m


static func _lathe(mb: MeshBuilder, prof: Array, segs: int, col: Color, r_max: float, tread: float) -> void:
	## Revolves a profile of Vector2(x along the axle, radius) about the X axis.
	var n := prof.size()
	var base := mb.verts.size()
	for j in segs + 1:
		var th := TAU * float(j) / segs
		var cs := cos(th)
		var sn := sin(th)
		for i in n:
			var p: Vector2 = prof[i]
			var pa: Vector2 = prof[maxi(i - 1, 0)]
			var pb: Vector2 = prof[mini(i + 1, n - 1)]
			var t := pb - pa
			var nn := Vector2(-t.y, t.x).normalized()
			var rr := p.y
			if tread > 0.0 and rr > r_max * 0.985 and j % 3 == 0:
				rr *= 1.0 - tread
			mb.add_vertex(Vector3(p.x, rr * cs, rr * sn), Vector3(nn.x, nn.y * cs, nn.y * sn), col,
				Vector2(float(j) / segs, float(i) / maxf(n - 1, 1)))
	for j in segs:
		for i in n - 1:
			var a := base + j * n + i
			var b := a + n
			mb.add_tri_idx(a, a + 1, b)
			mb.add_tri_idx(a + 1, b + 1, b)


# ================================================================== vehicles
static func _tug(c: Dictionary) -> void:
	## Towbarless narrow/wide-body tug: low chassis, open fork at the back that cradles the
	## nose wheel, offset cab at the front left.
	var m: Color = c.main
	var meta: Dictionary = c.meta
	meta.length = 8.2
	meta.width = 3.3
	meta.cradle = Vector3(0, 0.3, 2.65)       # where the nose wheel sits
	# chassis and fork arms
	_rb(c, Vector3(0, 0.78, -1.45), Vector3(3.2, 0.72, 4.9), m, PAINT, 0.12, Basis(), 14, 8)
	_rb(c, Vector3(-1.12, 0.86, 2.15), Vector3(0.95, 0.62, 3.6), m, PAINT, 0.14)
	_rb(c, Vector3(1.12, 0.86, 2.15), Vector3(0.95, 0.62, 3.6), m, PAINT, 0.14)
	# black lower skirt with rubbing strips
	_rb(c, Vector3(0, 0.45, -1.45), Vector3(3.24, 0.12, 4.94), BLACK, RUBBER, 0.2)
	for s in [-1.0, 1.0]:
		_rb(c, Vector3(s * 1.12, 0.52, 2.15), Vector3(0.99, 0.1, 3.64), BLACK, RUBBER, 0.2)
		# hydraulic rams along the arms
		_cy(c, Vector3(s * 0.72, 1.12, 0.8), Vector3(s * 0.72, 0.82, 3.3), 0.07, CHROME)
		_cy(c, Vector3(s * 0.72, 1.12, 0.8), Vector3(s * 0.72, 1.06, 1.6), 0.1, DARK, PAINT)
	# engine deck with louvres
	_rb(c, Vector3(0.72, 1.32, -1.2), Vector3(1.55, 0.42, 2.8), m, PAINT, 0.18)
	for i in 9:
		_bx(c, Vector3(0.72, 1.535, -2.3 + i * 0.27), Vector3(1.3, 0.02, 0.1), DARK, MATTE)
	_cy(c, Vector3(1.32, 1.4, -0.1), Vector3(1.32, 2.35, -0.1), 0.06, DARK, METAL, 10)
	_cy(c, Vector3(1.32, 2.35, -0.1), Vector3(1.32, 2.42, -0.02), 0.065, BLACK, METAL, 10)
	# front bumper with hazard chevrons
	_rb(c, Vector3(0, 0.72, -3.98), Vector3(3.3, 0.5, 0.32), BLACK, RUBBER, 0.25)
	_stripes(c, Vector3(1.5, 0.53, -4.15), Vector3(-3.0, 0, 0), Vector3(0, 0.38, 0), 12, YELLOW, BLACK, 0.6)
	# cradle: floor plate, clamp jaws and the push plate
	_begin_part(c, "cradle", Vector3(0, 0.3, 2.65))
	_rb(c, Vector3(0, 0.22, 2.65), Vector3(1.24, 0.1, 2.0), DARK, METAL, 0.15)
	for s2 in [-1.0, 1.0]:
		_rb(c, Vector3(s2 * 0.6, 0.48, 2.45), Vector3(0.14, 0.42, 1.0), Color(0.85, 0.85, 0.2), PAINT, 0.2)
		_cy(c, Vector3(s2 * 0.52, 0.45, 2.0), Vector3(s2 * 0.52, 0.45, 2.9), 0.05, CHROME)
	_rb(c, Vector3(0, 0.5, 3.62), Vector3(1.2, 0.5, 0.14), DARK, METAL, 0.2)
	_end_part(c)
	# cab: offset to the front-left, glazed on all sides
	var cab := Vector3(-0.78, 1.72, -2.35)
	_rb(c, cab + Vector3(0, -0.28, 0), Vector3(1.5, 0.62, 1.95), m, PAINT, 0.16)
	for x in [-0.7, 0.7]:
		for z in [-0.92, 0.92]:
			_rb(c, cab + Vector3(x, 0.38, z), Vector3(0.09, 0.82, 0.09), DARK, PAINT, 0.3, Basis(), 6, 4)
	_rb(c, cab + Vector3(0, 0.84, 0), Vector3(1.6, 0.13, 2.05), m, PAINT, 0.25)
	_glass(c, cab + Vector3(0, 0.38, -0.97), Vector3(1.32, 0.74, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-8.0)))
	_glass(c, cab + Vector3(0, 0.38, 0.97), Vector3(1.32, 0.74, 0.03))
	for s3 in [-1.0, 1.0]:
		_glass(c, cab + Vector3(s3 * 0.75, 0.38, 0), Vector3(0.03, 0.74, 1.76))
	_seat(c, cab + Vector3(0, -0.2, 0.3))
	_steering_wheel(c, cab + Vector3(0, 0.25, -0.45), 35.0)
	_mirror(c, cab + Vector3(-0.78, 0.55, -0.9), -1.0)
	# steps to the cab
	for i in 2:
		_bx(c, cab + Vector3(-0.82, -0.75 - i * 0.28, 0.3), Vector3(0.22, 0.04, 0.55), STEEL, METAL)
	# lamps
	_lamp(c, cab + Vector3(0, 0.98, 0), Vector3(0.2, 0.18, 0.2), AMBER, "beacon", 0.0)
	for s4 in [-1.0, 1.0]:
		_lamp(c, Vector3(s4 * 1.3, 0.95, -4.15), Vector3(0.26, 0.14, 0.05), Color(1, 0.97, 0.88), "head")
		_lamp(c, Vector3(s4 * 1.45, 1.1, 3.92), Vector3(0.12, 0.1, 0.05), Color(1, 0.12, 0.08), "head")
	_lamp(c, Vector3(1.4, 1.6, 0.15), Vector3(0.16, 0.14, 0.16), AMBER, "beacon", 0.5)
	_label(c, String(c.text) if String(c.text) != "" else "TUG", cab + Vector3(-0.8, -0.3, 0.2), Vector3(-1, 0, 0), 0.22, DARK)
	# wheels: steering pair at the front, a fixed pair inside the fork arms
	for s5 in [-1.0, 1.0]:
		_wheel(c, Vector3(s5 * 1.3, 0.56, -2.85), 0.56, 0.5, true)
		_wheel(c, Vector3(s5 * 1.12, 0.5, 2.9), 0.5, 0.46, false)
		_wheel_arch(c, Vector3(s5 * 1.3, 0.56, -2.85), 0.56, 0.5, m, s5)


static func _tractor(c: Dictionary) -> void:
	## Baggage tractor with a canopy cab.
	var m: Color = c.main
	c.meta.length = 3.1
	c.meta.width = 1.5
	c.meta.hitch = Vector3(0, 0.45, 1.62)
	_rb(c, Vector3(0, 0.62, 0.05), Vector3(1.42, 0.5, 2.95), DARK, PAINT, 0.15)
	_rb(c, Vector3(0, 1.0, -0.98), Vector3(1.38, 0.5, 0.95), m, PAINT, 0.28)
	_grille(c, Vector3(0, 0.92, -1.46), 0.9, 0.32, 5, Vector3(0, 0, -1))
	_rb(c, Vector3(0, 0.52, -1.52), Vector3(1.5, 0.22, 0.14), BLACK, RUBBER, 0.3)
	_rb(c, Vector3(0, 0.88, 0.45), Vector3(1.4, 0.18, 1.7), m, PAINT, 0.2)
	_seat(c, Vector3(0, 1.0, 0.45))
	_steering_wheel(c, Vector3(0, 1.45, -0.18), 40.0, 0.17)
	# canopy: posts, roof and windscreen
	for x in [-0.64, 0.64]:
		_cy(c, Vector3(x, 1.2, -0.42), Vector3(x, 2.02, -0.38), 0.035, DARK, PAINT, 8)
		_cy(c, Vector3(x, 0.95, 1.2), Vector3(x, 2.02, 1.12), 0.035, DARK, PAINT, 8)
	_rb(c, Vector3(0, 2.06, 0.38), Vector3(1.48, 0.08, 1.75), m, PAINT, 0.3)
	_glass(c, Vector3(0, 1.62, -0.4), Vector3(1.22, 0.78, 0.025), Basis(Vector3.RIGHT, deg_to_rad(-4.0)))
	_rb(c, Vector3(0, 0.5, 1.6), Vector3(0.36, 0.16, 0.22), STEEL, METAL, 0.25)
	_lamp(c, Vector3(0, 2.16, 0.38), Vector3(0.16, 0.14, 0.16), AMBER, "beacon", 0.2)
	for s in [-1.0, 1.0]:
		_lamp(c, Vector3(s * 0.52, 1.1, -1.47), Vector3(0.16, 0.1, 0.04), Color(1, 0.96, 0.85), "head")
		_lamp(c, Vector3(s * 0.62, 0.75, 1.53), Vector3(0.1, 0.07, 0.03), Color(1, 0.1, 0.06), "head")
		_wheel(c, Vector3(s * 0.66, 0.33, -0.95), 0.33, 0.24, true)
		_wheel(c, Vector3(s * 0.66, 0.36, 0.95), 0.36, 0.28)
		_wheel_arch(c, Vector3(s * 0.66, 0.36, 0.95), 0.36, 0.28, m, s)


static func _cart(c: Dictionary) -> void:
	## Covered baggage cart with curtains (one side rolled up) and suitcases.
	var m: Color = c.main
	c.meta.length = 3.3
	c.meta.width = 1.55
	c.meta.hitch = Vector3(0, 0.45, 1.55)
	c.meta.tow = Vector3(0, 0.45, -1.9)
	_rb(c, Vector3(0, 0.5, 0), Vector3(1.5, 0.12, 2.7), STEEL, METAL, 0.1)
	for x in [-0.72, 0.72]:
		for z in [-1.3, 1.3]:
			_cy(c, Vector3(x, 0.55, z), Vector3(x, 1.85, z), 0.03, STEEL)
	_rb(c, Vector3(0, 1.9, 0), Vector3(1.6, 0.08, 2.8), m, PAINT, 0.35)
	# curtain down on the left, rolled up on the right
	_rb(c, Vector3(-0.75, 1.22, 0), Vector3(0.025, 1.18, 2.58), m.darkened(0.15), MATTE, 0.12)
	_bx(c, Vector3(-0.765, 1.22, 0), Vector3(0.006, 0.12, 2.58), WHITE, MATTE)
	_cy(c, Vector3(0.75, 1.78, -1.28), Vector3(0.75, 1.78, 1.28), 0.07, m.darkened(0.15), MATTE, 10)
	# luggage
	var r := U.rng(U.hash_str(String(c.text) + "bags"))
	var cols := [Color(0.1, 0.12, 0.3), Color(0.5, 0.05, 0.08), BLACK, Color(0.3, 0.32, 0.34), Color(0.05, 0.3, 0.3), Color(0.55, 0.42, 0.25)]
	var z0 := -1.15
	while z0 < 1.15:
		var bw := r.randf_range(0.4, 0.75)
		var x0 := -0.6
		while x0 < 0.55:
			var bh := r.randf_range(0.25, 0.6)
			var bd := r.randf_range(0.3, 0.55)
			var y := 0.56
			for k in r.randi_range(1, 2):
				_rb(c, Vector3(x0 + bd * 0.5, y + bh * 0.5, z0 + bw * 0.5), Vector3(bd, bh, bw * 0.95), cols[r.randi() % cols.size()], MATTE, 0.3, Basis(), 8, 6)
				y += bh
			x0 += bd + 0.03
		z0 += bw + 0.03
	# drawbar
	_cy(c, Vector3(0, 0.45, -1.35), Vector3(0, 0.45, -1.9), 0.04, DARK, PAINT)
	_cy(c, Vector3(0, 0.45, -1.9), Vector3(0, 0.45, -1.95), 0.08, STEEL)
	for s in [-1.0, 1.0]:
		_wheel(c, Vector3(s * 0.62, 0.22, -0.95), 0.22, 0.15, true)
		_wheel(c, Vector3(s * 0.62, 0.22, 0.95), 0.22, 0.15)


static func _uld_dolly(c: Dictionary) -> void:
	## Container dolly carrying an LD3 unit load device.
	var m: Color = c.main
	c.meta.length = 2.6
	c.meta.width = 1.8
	c.meta.hitch = Vector3(0, 0.45, 1.3)
	c.meta.tow = Vector3(0, 0.45, -1.7)
	_rb(c, Vector3(0, 0.45, 0), Vector3(1.75, 0.1, 2.0), STEEL, METAL, 0.1)
	for i in 6:
		_cy(c, Vector3(-0.8, 0.52, -0.8 + i * 0.32), Vector3(0.8, 0.52, -0.8 + i * 0.32), 0.03, DARK, METAL, 6)
	# LD3: angled lower contour on one side, aluminium with a door curtain
	var ld := Vector3(0, 0.55, 0)
	var alu := Color(0.7, 0.72, 0.75)
	_rb(c, ld + Vector3(0.18, 0.82, 0), Vector3(1.3, 1.62, 1.5), alu, METAL, 0.06)
	# the sloped side that follows the lower fuselage contour
	_rb(c, ld + Vector3(-0.56, 1.06, 0), Vector3(0.42, 1.12, 1.5), alu, METAL, 0.06)
	_rb(c, ld + Vector3(-0.5, 0.42, 0), Vector3(0.36, 0.5, 1.5), alu, METAL, 0.06, Basis(Vector3(0, 0, 1), deg_to_rad(-38.0)))
	for k in 5:
		_bx(c, ld + Vector3(0.18, 0.2 + k * 0.35, -0.752), Vector3(1.24, 0.03, 0.01), Color(0.5, 0.52, 0.55), METAL)
	_rb(c, ld + Vector3(0.18, 0.86, -0.765), Vector3(1.12, 1.3, 0.02), m.darkened(0.25), MATTE, 0.1)
	_label(c, "AKE %05d" % (U.hash_str(String(c.text)) % 99999), ld + Vector3(0.12, 1.3, -0.785), Vector3(0, 0, -1), 0.12, WHITE)
	_cy(c, Vector3(0, 0.45, -1.0), Vector3(0, 0.45, -1.7), 0.04, DARK, PAINT)
	for s in [-1.0, 1.0]:
		_wheel(c, Vector3(s * 0.75, 0.2, -0.75), 0.2, 0.14, true)
		_wheel(c, Vector3(s * 0.75, 0.2, 0.75), 0.2, 0.14)


static func _belt_loader(c: Dictionary) -> void:
	## Self-propelled belt loader; the conveyor boom is a part pivoting at its rear end.
	var m: Color = c.main
	c.meta.length = 7.6
	c.meta.width = 2.1
	_rb(c, Vector3(0, 0.62, 0.2), Vector3(1.85, 0.48, 6.2), DARK, PAINT, 0.12)
	_rb(c, Vector3(0, 0.95, 2.3), Vector3(1.6, 0.45, 1.8), m, PAINT, 0.2)
	for i in 6:
		_bx(c, Vector3(0.81, 0.95, 1.7 + i * 0.22), Vector3(0.02, 0.28, 0.08), DARK, MATTE)
	# side driver station
	var st := Vector3(-0.55, 1.0, -0.6)
	_rb(c, st + Vector3(0, 0.0, 0), Vector3(0.9, 0.4, 1.4), m, PAINT, 0.2)
	_seat(c, st + Vector3(0, 0.22, 0.2))
	_steering_wheel(c, st + Vector3(0, 0.65, -0.35), 40.0, 0.17)
	_glass(c, st + Vector3(0, 0.95, -0.62), Vector3(0.82, 0.65, 0.025), Basis(Vector3.RIGHT, deg_to_rad(-10.0)))
	_rb(c, st + Vector3(0, 1.45, 0.05), Vector3(0.95, 0.06, 1.4), m, PAINT, 0.3)
	for z in [-0.6, 0.65]:
		_cy(c, st + Vector3(-0.42, 0.2, z), st + Vector3(-0.42, 1.43, z), 0.03, DARK, PAINT, 6)
	_lamp(c, st + Vector3(0, 1.53, 0.05), Vector3(0.14, 0.12, 0.14), AMBER, "beacon", 0.3)
	# conveyor boom (pivot near the back, raised by the rams)
	var piv := Vector3(0.35, 0.95, 3.1)
	c.meta.boom_pivot = piv
	c.meta.boom_len = 7.0
	_begin_part(c, "boom", piv)
	var L := 7.0
	for s in [-1.0, 1.0]:
		_rb(c, piv + Vector3(s * 0.42, 0.0, -L * 0.5), Vector3(0.1, 0.24, L), m, PAINT, 0.15)
		var rail := []
		for k in 6:
			var zz := -0.4 - (L - 0.8) * float(k) / 5.0
			_cy(c, piv + Vector3(s * 0.42, 0.1, zz), piv + Vector3(s * 0.42, 0.62, zz), 0.022, STEEL, METAL, 6)
			rail.append(piv + Vector3(s * 0.42, 0.62, zz))
		_rail(c, rail, 0.024)
	_rb(c, piv + Vector3(0, 0.08, -L * 0.5), Vector3(0.76, 0.05, L - 0.1), Color(0.07, 0.07, 0.075), RUBBER, 0.08)
	for k2 in int(L / 0.42):
		_bx(c, piv + Vector3(0, 0.12, -0.25 - k2 * 0.42), Vector3(0.72, 0.03, 0.04), Color(0.1, 0.1, 0.1), RUBBER)
	_cy(c, piv + Vector3(-0.4, 0.06, -0.08), piv + Vector3(0.4, 0.06, -0.08), 0.09, STEEL)
	_cy(c, piv + Vector3(-0.4, 0.06, -L + 0.08), piv + Vector3(0.4, 0.06, -L + 0.08), 0.09, STEEL)
	_rb(c, piv + Vector3(0, -0.02, -L - 0.05), Vector3(0.95, 0.12, 0.16), BLACK, RUBBER, 0.3)
	_end_part(c)
	_cy(c, Vector3(0.35, 0.85, -1.0), Vector3(0.35, 1.35, -1.4), 0.08, CHROME)
	for s2 in [-1.0, 1.0]:
		_lamp(c, Vector3(s2 * 0.75, 0.75, -2.9), Vector3(0.14, 0.09, 0.04), Color(1, 0.96, 0.85), "head")
		_wheel(c, Vector3(s2 * 0.82, 0.38, -2.2), 0.38, 0.26, true)
		_wheel(c, Vector3(s2 * 0.82, 0.38, 2.1), 0.38, 0.26)


static func _cab_over(c: Dictionary, z_front: float, w: float, h: float, l: float, col: Color, roof_lamps: bool = true) -> Vector3:
	## Cab-over truck cab with a wrap windscreen, grille, bumper, mirrors and lamps.
	## Returns the cab centre.
	var cc := Vector3(0, 0.75 + h * 0.5 + 0.25, z_front + l * 0.5)
	_rb(c, cc, Vector3(w, h, l), col, PAINT, 0.18, Basis(), 14, 10)
	# windscreen and side windows
	_glass(c, cc + Vector3(0, h * 0.18, -l * 0.5 - 0.005), Vector3(w * 0.88, h * 0.42, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-6.0)))
	for s in [-1.0, 1.0]:
		_glass(c, cc + Vector3(s * (w * 0.5 + 0.004), h * 0.18, -l * 0.12), Vector3(0.03, h * 0.4, l * 0.52))
		_mirror(c, cc + Vector3(s * w * 0.5, h * 0.22, -l * 0.42), s, 0.28, 0.45)
		_lamp(c, cc + Vector3(s * w * 0.36, -h * 0.36, -l * 0.5 - 0.02), Vector3(0.3, 0.13, 0.05), Color(1, 0.96, 0.86), "head")
		_lamp(c, cc + Vector3(s * w * 0.47, -h * 0.36, -l * 0.5 - 0.01), Vector3(0.08, 0.1, 0.05), AMBER, "head")
		# entry steps
		for i in 2:
			_bx(c, cc + Vector3(s * (w * 0.5 - 0.12), -h * 0.5 - 0.15 - i * 0.3, l * 0.1), Vector3(0.26, 0.04, 0.5), STEEL, METAL)
	_grille(c, cc + Vector3(0, -h * 0.26, -l * 0.5 - 0.01), w * 0.5, h * 0.24, 6, Vector3(0, 0, -1))
	_rb(c, cc + Vector3(0, -h * 0.5 - 0.06, -l * 0.5 - 0.05), Vector3(w + 0.04, 0.3, 0.22), BLACK, RUBBER, 0.25)
	_rb(c, cc + Vector3(0, h * 0.5 + 0.03, -l * 0.4), Vector3(w * 0.9, 0.06, 0.3), col.darkened(0.2), PAINT, 0.3)
	if roof_lamps:
		_lamp(c, cc + Vector3(-w * 0.32, h * 0.5 + 0.1, -l * 0.15), Vector3(0.18, 0.16, 0.18), AMBER, "beacon", 0.0)
		_lamp(c, cc + Vector3(w * 0.32, h * 0.5 + 0.1, -l * 0.15), Vector3(0.18, 0.16, 0.18), AMBER, "beacon", 0.5)
	return cc


static func _fuel_truck(c: Dictionary) -> void:
	## Aviation refueller: cab-over tractor, elliptical tank, top walkway, ladder and hose reels.
	c.meta.length = 10.2
	c.meta.width = 2.55
	var m: Color = c.main if c.main != YELLOW else WHITE
	_cab_over(c, -5.1, 2.5, 2.0, 2.1, m)
	_rb(c, Vector3(0, 0.82, 0.4), Vector3(1.0, 0.3, 9.4), DARK, PAINT, 0.1)
	# tank: lofted ellipse with dished ends
	var rings := []
	var z0 := -2.75
	var z1 := 3.55
	var n := 24
	var profile := [[z0, 0.0], [z0 + 0.06, 0.6], [z0 + 0.2, 0.92], [z0 + 0.45, 1.0], [z1 - 0.45, 1.0], [z1 - 0.2, 0.92], [z1 - 0.06, 0.6], [z1, 0.0]]
	for pr in profile:
		var ring := PackedVector3Array()
		var sc: float = maxf(float(pr[1]), 0.02)
		for k in n:
			var a := TAU * float(k) / n
			ring.append(Vector3(cos(a) * 1.22 * sc, 2.08 + sin(a) * 0.98 * sc, float(pr[0])))
		rings.append(ring)
	var mb: MeshBuilder = c.mb
	mb.add_loft(rings, _col(m, PAINT))
	# red band and lettering
	for zb in [-2.1, 2.75]:
		var band := []
		for zz in [zb, zb + 0.35]:
			var ring2 := PackedVector3Array()
			for k2 in n:
				var a2 := TAU * float(k2) / n
				ring2.append(Vector3(cos(a2) * 1.235, 2.08 + sin(a2) * 0.995, zz))
			band.append(ring2)
		mb.add_loft(band, _col(RED, PAINT))
	for s in [-1.0, 1.0]:
		_label(c, "JET A-1", Vector3(s * 1.2, 2.1, 0.45), Vector3(s, 0, 0), 0.42, RED)
		_bx(c, Vector3(s * 1.15, 1.55, 3.0), Vector3(0.02, 0.3, 0.3), Color(0.95, 0.6, 0.1), PAINT)
	# walkway with fold-down rails
	_bx(c, Vector3(0, 3.1, 0.4), Vector3(0.75, 0.04, 5.6), STEEL, METAL)
	for s2 in [-1.0, 1.0]:
		var pts := []
		for k3 in 5:
			var zz2 := -2.2 + k3 * 1.3
			_cy(c, Vector3(s2 * 0.38, 3.1, zz2), Vector3(s2 * 0.38, 3.65, zz2), 0.02, YELLOW, PAINT, 6)
			pts.append(Vector3(s2 * 0.38, 3.65, zz2))
		_rail(c, pts, 0.022, YELLOW)
	for zm in [-1.6, 0.4, 2.4]:
		_cy(c, Vector3(0, 3.0, zm), Vector3(0, 3.16, zm), 0.28, STEEL, METAL, 14)
	_ladder(c, Vector3(-1.32, 0.6, 3.72), Vector3(-1.32, 3.1, 3.72), 0.42, 8)
	# rear cabinet with hose reels and a lift deck
	_rb(c, Vector3(0, 1.45, 4.42), Vector3(2.4, 1.5, 0.9), m, PAINT, 0.12)
	for s3 in [-1.0, 1.0]:
		_cy(c, Vector3(s3 * 0.9, 1.55, 4.9), Vector3(s3 * 0.25, 1.55, 4.9), 0.55, DARK, PAINT, 16)
		_cy(c, Vector3(s3 * 0.85, 1.55, 4.9), Vector3(s3 * 0.3, 1.55, 4.9), 0.5, BLACK, RUBBER, 16)
	_bx(c, Vector3(0, 0.72, 5.0), Vector3(2.3, 0.08, 0.6), STEEL, METAL)
	_stripes(c, Vector3(-1.2, 0.55, 5.05), Vector3(2.4, 0, 0), Vector3(0, 0.25, 0), 10, RED, WHITE, 0.7)
	for s4 in [-1.0, 1.0]:
		_lamp(c, Vector3(s4 * 1.05, 1.0, 5.1), Vector3(0.18, 0.12, 0.04), Color(1, 0.08, 0.05), "head")
		_wheel(c, Vector3(s4 * 1.03, 0.52, -3.55), 0.52, 0.34, true)
		_wheel(c, Vector3(s4 * 0.98, 0.52, 1.75), 0.52, 0.62, false, true)
		_wheel(c, Vector3(s4 * 0.98, 0.52, 3.05), 0.52, 0.62, false, true)
		_wheel_arch(c, Vector3(s4 * 1.03, 0.52, -3.55), 0.52, 0.34, m, s4)


static func _catering(c: Dictionary) -> void:
	## Catering high-loader: the body rides on a scissor lift with a front platform.
	c.meta.length = 9.2
	c.meta.width = 2.5
	var m: Color = c.main if c.main != YELLOW else WHITE
	_cab_over(c, -4.6, 2.45, 1.9, 1.9, m)
	_rb(c, Vector3(0, 0.82, 0.6), Vector3(1.0, 0.3, 8.0), DARK, PAINT, 0.1)
	_bx(c, Vector3(0, 1.02, 1.4), Vector3(2.3, 0.1, 5.6), DARK, METAL)
	c.meta.lift_low = 1.3
	_begin_part(c, "lift", Vector3(0, 1.3, 1.4))
	var b0 := Vector3(0, 1.3, 1.4)
	_rb(c, b0 + Vector3(0, 1.35, 0), Vector3(2.48, 2.6, 5.5), m, PAINT, 0.1, Basis(), 14, 8)
	_rb(c, b0 + Vector3(0, 0.05, 0), Vector3(2.52, 0.14, 5.56), DARK, PAINT, 0.2)
	for s in [-1.0, 1.0]:
		_bx(c, b0 + Vector3(s * 1.245, 1.0, 0), Vector3(0.012, 0.28, 5.4), c.accent if c.accent != DARK else RED, PAINT)
		_label(c, String(c.text) if String(c.text) != "" else "CATERING", b0 + Vector3(s * 1.245, 1.65, 0.4), Vector3(s, 0, 0), 0.38, Color(0.15, 0.17, 0.25))
	# roller door facing the aircraft
	for i in 10:
		_bx(c, b0 + Vector3(0, 0.35 + i * 0.2, -2.76), Vector3(1.6, 0.17, 0.03), Color(0.82, 0.84, 0.86), METAL)
	# front platform and rails
	_bx(c, b0 + Vector3(0, 0.08, -3.35), Vector3(2.3, 0.08, 1.2), STEEL, METAL)
	for s2 in [-1.0, 1.0]:
		_rail(c, [b0 + Vector3(s2 * 1.12, 0.12, -2.75), b0 + Vector3(s2 * 1.12, 1.1, -2.75), b0 + Vector3(s2 * 1.12, 1.1, -3.9), b0 + Vector3(s2 * 1.12, 0.12, -3.9)], 0.025, YELLOW)
	_bx(c, b0 + Vector3(0, 0.12, -4.0), Vector3(1.4, 0.04, 0.3), BLACK, RUBBER)
	_lamp(c, b0 + Vector3(-1.1, 2.7, -2.6), Vector3(0.16, 0.14, 0.16), AMBER, "beacon", 0.7)
	_end_part(c)
	# scissor arms: unit-length beams (pointing -Z) placed and stretched by set_lift()
	for s3 in [-1.0, 1.0]:
		for k in 2:
			var nm := "scissor_%s%d" % ["l" if s3 < 0.0 else "r", k]
			_begin_part(c, nm, Vector3(s3 * (0.82 + k * 0.14), 1.16, 1.4))
			var pv := Vector3(s3 * (0.82 + k * 0.14), 1.16, 1.4)
			_bx(c, pv + Vector3(0, 0, -0.5), Vector3(0.1, 0.14, 1.0), STEEL, METAL)
			_end_part(c)
		_rb(c, Vector3(s3 * 0.9, 1.1, 1.4), Vector3(0.3, 0.08, 5.2), DARK, METAL, 0.2)
	for s4 in [-1.0, 1.0]:
		_wheel(c, Vector3(s4 * 1.03, 0.5, -3.25), 0.5, 0.34, true)
		_wheel(c, Vector3(s4 * 0.98, 0.5, 2.6), 0.5, 0.6, false, true)
		_wheel_arch(c, Vector3(s4 * 1.03, 0.5, -3.25), 0.5, 0.34, m, s4)
		_lamp(c, Vector3(s4 * 1.05, 0.9, 4.95), Vector3(0.18, 0.12, 0.04), Color(1, 0.08, 0.05), "head")


static func _stairs(c: Dictionary) -> void:
	## Passenger stairs truck: small cab, stair flight with handrails and a canopy at the top.
	c.meta.length = 8.0
	c.meta.width = 2.4
	var m: Color = c.main
	_rb(c, Vector3(0, 0.7, 0.3), Vector3(2.2, 0.4, 7.4), DARK, PAINT, 0.12)
	var cab := Vector3(-0.55, 1.45, -2.9)
	_rb(c, cab, Vector3(1.1, 1.3, 1.5), m, PAINT, 0.18)
	_glass(c, cab + Vector3(0, 0.25, -0.76), Vector3(0.95, 0.6, 0.025), Basis(Vector3.RIGHT, deg_to_rad(-6.0)))
	_glass(c, cab + Vector3(-0.56, 0.25, 0.0), Vector3(0.025, 0.6, 1.2))
	_mirror(c, cab + Vector3(-0.56, 0.3, -0.7), -1.0)
	_lamp(c, cab + Vector3(0, 0.75, 0), Vector3(0.16, 0.14, 0.16), AMBER, "beacon", 0.1)
	c.meta.stairs_pivot = Vector3(0.35, 1.0, 3.6)
	_begin_part(c, "stairs", Vector3(0.35, 1.0, 3.6))
	var piv := Vector3(0.35, 1.0, 3.6)
	var steps := 16
	var run := 5.6
	var rise := 3.0
	for i in steps:
		var f := (float(i) + 0.5) / steps
		_bx(c, piv + Vector3(0, rise * f, -run * f), Vector3(1.25, 0.05, 0.3), STEEL, METAL)
	for s in [-1.0, 1.0]:
		_rb(c, piv + Vector3(s * 0.66, rise * 0.5 - 0.15, -run * 0.5), Vector3(0.08, 0.3, 6.3), m, PAINT, 0.15,
			Basis(Vector3.RIGHT, atan2(rise, run)))
		var pts := []
		for k in 6:
			var f2 := float(k) / 5.0
			var base := piv + Vector3(s * 0.66, rise * f2, -run * f2)
			_cy(c, base, base + Vector3(0, 0.95, 0), 0.022, STEEL, METAL, 6)
			pts.append(base + Vector3(0, 0.95, 0))
		_rail(c, pts, 0.025)
	var top := piv + Vector3(0, rise, -run - 0.55)
	_bx(c, top, Vector3(1.4, 0.06, 1.1), STEEL, METAL)
	for x in [-0.66, 0.66]:
		_cy(c, top + Vector3(x, 0, 0.5), top + Vector3(x, 2.15, 0.5), 0.03, m, PAINT, 6)
	_rb(c, top + Vector3(0, 2.2, 0.1), Vector3(1.55, 0.06, 1.4), m, PAINT, 0.3)
	_rb(c, top + Vector3(0, 0.0, -0.58), Vector3(1.35, 0.14, 0.1), BLACK, RUBBER, 0.3)
	_end_part(c)
	for s2 in [-1.0, 1.0]:
		_wheel(c, Vector3(s2 * 1.02, 0.42, -2.5), 0.42, 0.28, true)
		_wheel(c, Vector3(s2 * 1.02, 0.42, 2.7), 0.42, 0.28)


static func _gpu(c: Dictionary) -> void:
	## Towed ground power unit with louvres, control panel and a cable reel.
	c.meta.length = 2.9
	c.meta.width = 1.35
	var m: Color = c.main
	_rb(c, Vector3(0, 0.9, 0.1), Vector3(1.25, 1.05, 2.1), m, PAINT, 0.12)
	for s in [-1.0, 1.0]:
		for i in 7:
			_bx(c, Vector3(s * 0.63, 0.7 + i * 0.07, 0.4), Vector3(0.02, 0.025, 0.9), DARK, MATTE)
	_bx(c, Vector3(0, 1.0, -0.96), Vector3(0.8, 0.5, 0.03), BLACK, MATTE)
	_lamp(c, Vector3(-0.2, 1.1, -0.985), Vector3(0.05, 0.05, 0.02), Color(0.2, 1.0, 0.3), "steady")
	_lamp(c, Vector3(0.0, 1.1, -0.985), Vector3(0.05, 0.05, 0.02), Color(1.0, 0.6, 0.1), "steady")
	_cy(c, Vector3(-0.5, 1.55, 0.6), Vector3(0.5, 1.55, 0.6), 0.22, DARK, PAINT, 14)
	_cy(c, Vector3(-0.45, 1.55, 0.6), Vector3(0.45, 1.55, 0.6), 0.25, BLACK, RUBBER, 14)
	_cy(c, Vector3(0, 0.45, -1.0), Vector3(0, 0.45, -1.6), 0.035, DARK, PAINT)
	_lamp(c, Vector3(0, 1.48, -0.6), Vector3(0.12, 0.1, 0.12), AMBER, "beacon", 0.4)
	for s2 in [-1.0, 1.0]:
		_wheel(c, Vector3(s2 * 0.6, 0.25, -0.6), 0.25, 0.16, true)
		_wheel(c, Vector3(s2 * 0.6, 0.25, 0.75), 0.25, 0.16)


static func _arff(c: Dictionary) -> void:
	## 6x6 airport crash tender: big glazed cab, compartment roller doors, roof and bumper
	## monitors (parts "turret" and "bumper_turret"), light bars and chevrons.
	c.meta.length = 12.2
	c.meta.width = 3.0
	var m: Color = c.main if c.main != YELLOW else LIME
	var cab := Vector3(0, 2.15, -4.55)
	_rb(c, cab, Vector3(2.98, 2.0, 2.4), m, PAINT, 0.22, Basis(), 16, 10)
	_rb(c, cab + Vector3(0, -1.0, -0.05), Vector3(3.0, 0.4, 2.42), Color(0.85, 0.85, 0.86), PAINT, 0.2)
	# wrap-around windscreen in three panes and big side windows
	_glass(c, cab + Vector3(0, 0.35, -1.21), Vector3(2.2, 1.0, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-5.0)))
	for s in [-1.0, 1.0]:
		_glass(c, cab + Vector3(s * 1.31, 0.35, -1.08), Vector3(0.4, 1.0, 0.03), Basis(Vector3.UP, deg_to_rad(s * 38.0)))
		_glass(c, cab + Vector3(s * 1.5, 0.35, 0.15), Vector3(0.03, 0.95, 1.4))
		_glass(c, cab + Vector3(s * 1.5, -0.55, -0.2), Vector3(0.03, 0.55, 0.5))
		_mirror(c, cab + Vector3(s * 1.49, 0.6, -1.0), s, 0.35, 0.55)
	_rb(c, cab + Vector3(0, -1.35, -1.28), Vector3(3.05, 0.45, 0.32), BLACK, RUBBER, 0.25)
	_stripes(c, Vector3(1.45, 0.64, -6.0), Vector3(-2.9, 0, 0), Vector3(0, 0.3, 0), 14, RED, WHITE, 0.7)
	# light bar
	_rb(c, cab + Vector3(0, 1.08, -0.6), Vector3(2.2, 0.14, 0.3), BLACK, RUBBER, 0.3)
	for i in 6:
		var x := -0.92 + i * 0.368
		_lamp(c, cab + Vector3(x, 1.12, -0.74), Vector3(0.3, 0.1, 0.05), RED if i % 2 == 0 else Color(0.2, 0.4, 1.0), "strobe", float(i) * 0.17)
	for s2 in [-1.0, 1.0]:
		_lamp(c, cab + Vector3(s2 * 1.1, -0.95, -1.22), Vector3(0.36, 0.14, 0.05), Color(1, 0.97, 0.88), "head")
		_lamp(c, cab + Vector3(s2 * 1.46, -0.6, -1.0), Vector3(0.04, 0.2, 0.2), RED, "strobe", 0.5 + s2 * 0.2)
	# body with compartments and roller doors
	var body := Vector3(0, 2.0, 1.15)
	_rb(c, body, Vector3(2.98, 2.7, 6.9), m, PAINT, 0.1, Basis(), 14, 10)
	for s3 in [-1.0, 1.0]:
		for comp in 3:
			var zc := -1.15 + comp * 2.25 + body.z - 1.15
			for k in 12:
				_bx(c, Vector3(s3 * 1.495, 1.0 + k * 0.13, zc), Vector3(0.012, 0.1, 1.9), Color(0.75, 0.77, 0.79), METAL)
			_cy(c, Vector3(s3 * 1.51, 0.92, zc - 0.7), Vector3(s3 * 1.51, 0.92, zc + 0.7), 0.025, CHROME)
		_bx(c, Vector3(s3 * 1.5, 2.85, body.z), Vector3(0.012, 0.22, 6.7), RED, PAINT)
		_label(c, "AIRPORT FIRE & RESCUE", Vector3(s3 * 1.5, 3.12, body.z), Vector3(s3, 0, 0), 0.3, RED)
	# rear: chevrons, ladder, lights
	_stripes(c, Vector3(-1.48, 0.9, 4.61), Vector3(2.96, 0, 0), Vector3(0, 1.8, 0), 9, RED, YELLOW, 0.55)
	_ladder(c, Vector3(1.1, 0.9, 4.66), Vector3(1.1, 3.35, 4.66), 0.45, 8)
	for s4 in [-1.0, 1.0]:
		_lamp(c, Vector3(s4 * 1.3, 0.85, 4.62), Vector3(0.2, 0.16, 0.04), Color(1, 0.08, 0.05), "head")
		_lamp(c, Vector3(s4 * 1.3, 3.25, 4.62), Vector3(0.12, 0.12, 0.05), RED, "strobe", 0.3 + s4 * 0.2)
	# roof walkway and the main monitor
	_bx(c, Vector3(0, 3.37, 1.15), Vector3(2.4, 0.04, 6.4), STEEL, METAL)
	c.meta.turret_pos = Vector3(0, 3.55, -3.7)
	_begin_part(c, "turret", Vector3(0, 3.55, -3.7))
	var tp := Vector3(0, 3.55, -3.7)
	_cy(c, tp + Vector3(0, -0.25, 0), tp + Vector3(0, 0.1, 0), 0.32, DARK, PAINT, 14)
	_cy(c, tp + Vector3(0, 0.1, 0), tp + Vector3(0, 0.38, 0), 0.18, m, PAINT, 12)
	_end_part(c)
	_begin_part(c, "turret_barrel", Vector3(0, 3.95, -3.7), "turret")
	var bp := Vector3(0, 3.95, -3.7)
	_cy(c, bp, bp + Vector3(0, 0, -1.5), 0.11, CHROME, METAL, 12)
	_cy(c, bp + Vector3(0, 0, -1.5), bp + Vector3(0, 0, -1.85), 0.16, Color(0.75, 0.6, 0.2), METAL, 12, 0.09)
	_end_part(c)
	_begin_part(c, "bumper_turret", Vector3(0, 0.95, -6.0))
	var bt := Vector3(0, 0.95, -6.0)
	_cy(c, bt + Vector3(0, -0.15, 0), bt + Vector3(0, 0.1, 0), 0.16, DARK, PAINT, 12)
	_cy(c, bt + Vector3(0, 0.05, 0), bt + Vector3(0, 0.05, -0.75), 0.07, CHROME, METAL, 10)
	_end_part(c)
	for s5 in [-1.0, 1.0]:
		_wheel(c, Vector3(s5 * 1.2, 0.72, -3.7), 0.72, 0.58, true)
		_wheel(c, Vector3(s5 * 1.2, 0.72, 1.0), 0.72, 0.58)
		_wheel(c, Vector3(s5 * 1.2, 0.72, 2.75), 0.72, 0.58)
		_wheel_arch(c, Vector3(s5 * 1.2, 0.72, -3.7), 0.72, 0.58, Color(0.85, 0.85, 0.86), s5)


static func _ambulance(c: Dictionary) -> void:
	## Box ambulance with high-visibility chequers and a light bar.
	c.meta.length = 6.6
	c.meta.width = 2.25
	_rb(c, Vector3(0, 0.95, -2.75), Vector3(2.05, 0.75, 1.15), WHITE, PAINT, 0.35)
	_rb(c, Vector3(0, 1.55, -1.95), Vector3(2.08, 1.3, 1.25), WHITE, PAINT, 0.25)
	_glass(c, Vector3(0, 1.75, -2.6), Vector3(1.8, 0.62, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-28.0)))
	for s in [-1.0, 1.0]:
		_glass(c, Vector3(s * 1.045, 1.72, -1.95), Vector3(0.03, 0.5, 1.0))
		_mirror(c, Vector3(s * 1.04, 1.62, -2.35), s, 0.22, 0.3)
		_lamp(c, Vector3(s * 0.72, 1.0, -3.33), Vector3(0.28, 0.13, 0.04), Color(1, 0.97, 0.88), "head")
	_grille(c, Vector3(0, 0.85, -3.33), 0.9, 0.22, 4, Vector3(0, 0, -1))
	_rb(c, Vector3(0, 0.55, -3.35), Vector3(2.12, 0.24, 0.14), Color(0.2, 0.2, 0.22), RUBBER, 0.3)
	var box := Vector3(0, 1.72, 0.85)
	_rb(c, box, Vector3(2.25, 2.3, 4.2), WHITE, PAINT, 0.1)
	for s2 in [-1.0, 1.0]:
		_checker(c, Vector3(s2 * 1.126, 0.95, box.z + 2.05 * s2), Vector3(0, 0, -4.1 * s2), Vector3(0, 0.44, 0), 10, 2, Color(0.95, 0.85, 0.05), Color(0.1, 0.55, 0.25))
		_label(c, "AMBULANCE", Vector3(s2 * 1.128, 2.15, box.z), Vector3(s2, 0, 0), 0.34, Color(0.1, 0.45, 0.2))
		_lamp(c, Vector3(s2 * 1.0, 2.84, box.z + 2.05), Vector3(0.14, 0.12, 0.06), Color(0.2, 0.4, 1.0), "strobe", 0.25 + s2 * 0.2)
		_lamp(c, Vector3(s2 * 0.8, 1.0, box.z + 2.11), Vector3(0.16, 0.2, 0.04), Color(1, 0.08, 0.05), "head")
	_rb(c, Vector3(0, 2.33, -1.85), Vector3(1.6, 0.12, 0.28), BLACK, RUBBER, 0.3)
	for i in 4:
		_lamp(c, Vector3(-0.6 + i * 0.4, 2.4, -1.95), Vector3(0.3, 0.09, 0.06), Color(0.2, 0.4, 1.0), "strobe", i * 0.23)
	for s3 in [-1.0, 1.0]:
		_wheel(c, Vector3(s3 * 0.95, 0.38, -2.3), 0.38, 0.24, true)
		_wheel(c, Vector3(s3 * 0.95, 0.38, 1.9), 0.38, 0.24)


static func _follow_me(c: Dictionary) -> void:
	## Compact SUV with chequers and an illuminated FOLLOW ME roof sign.
	c.meta.length = 4.5
	c.meta.width = 1.85
	_rb(c, Vector3(0, 0.72, 0), Vector3(1.85, 0.78, 4.45), YELLOW, PAINT, 0.32, Basis(), 16, 10)
	_rb(c, Vector3(0, 1.33, 0.25), Vector3(1.62, 0.62, 2.45), YELLOW, PAINT, 0.35, Basis(), 14, 8)
	_glass(c, Vector3(0, 1.36, -0.92), Vector3(1.42, 0.5, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-32.0)))
	_glass(c, Vector3(0, 1.38, 1.46), Vector3(1.32, 0.42, 0.03), Basis(Vector3.RIGHT, deg_to_rad(18.0)))
	for s in [-1.0, 1.0]:
		_glass(c, Vector3(s * 0.81, 1.37, 0.25), Vector3(0.03, 0.4, 2.0))
		_checker(c, Vector3(s * 0.93, 0.48, 2.0 * s), Vector3(0, 0, -4.0 * s), Vector3(0, 0.36, 0), 12, 2, YELLOW, BLACK)
		_mirror(c, Vector3(s * 0.85, 1.15, -0.7), s, 0.15, 0.16)
		_lamp(c, Vector3(s * 0.62, 0.86, -2.23), Vector3(0.32, 0.11, 0.04), Color(1, 0.97, 0.88), "head")
		_lamp(c, Vector3(s * 0.7, 0.92, 2.23), Vector3(0.26, 0.12, 0.04), Color(1, 0.08, 0.05), "head")
	_rb(c, Vector3(0, 0.42, -2.25), Vector3(1.9, 0.26, 0.14), BLACK, RUBBER, 0.3)
	_rb(c, Vector3(0, 0.42, 2.25), Vector3(1.9, 0.26, 0.14), BLACK, RUBBER, 0.3)
	_grille(c, Vector3(0, 0.75, -2.22), 0.9, 0.2, 4, Vector3(0, 0, -1))
	# roof sign
	_bx(c, Vector3(0, 1.72, 0.2), Vector3(1.0, 0.06, 0.08), DARK, METAL)
	var lbm: MeshBuilder = c.lb
	lbm.add_rounded_box(Vector3(0, 1.97, 0.2), Vector3(1.3, 0.4, 0.2), Color(0.95, 0.9, 0.75, LAMP_STEADY), 0.2, 10, 6)
	for s2 in [-1.0, 1.0]:
		_label(c, "FOLLOW ME", Vector3(0, 1.97, 0.2 + s2 * 0.105), Vector3(0, 0, s2), 0.22, Color(0.05, 0.05, 0.05))
		_lamp(c, Vector3(s2 * 0.75, 2.0, 0.2), Vector3(0.14, 0.24, 0.14), AMBER, "beacon", 0.5 + s2 * 0.25)
	for s3 in [-1.0, 1.0]:
		_wheel(c, Vector3(s3 * 0.8, 0.36, -1.4), 0.36, 0.25, true)
		_wheel(c, Vector3(s3 * 0.8, 0.36, 1.4), 0.36, 0.25)


static func _bus(c: Dictionary) -> void:
	## Low-floor apron bus with a full glasshouse and double doors on the right side.
	c.meta.length = 13.0
	c.meta.width = 3.0
	var m: Color = c.main if c.main != YELLOW else WHITE
	_rb(c, Vector3(0, 0.75, 0), Vector3(2.98, 0.85, 12.9), m, PAINT, 0.12, Basis(), 14, 8)
	_rb(c, Vector3(0, 2.25, 0), Vector3(2.98, 0.4, 12.9), m, PAINT, 0.15, Basis(), 14, 8)
	for s in [-1.0, 1.0]:
		_glass(c, Vector3(s * 1.49, 1.6, 0), Vector3(0.03, 1.15, 12.4))
		for i in 9:
			_bx(c, Vector3(s * 1.5, 1.6, -5.6 + i * 1.4), Vector3(0.02, 1.15, 0.07), DARK, PAINT)
		_bx(c, Vector3(s * 1.5, 0.9, 0), Vector3(0.012, 0.12, 12.6), c.accent if c.accent != DARK else Color(0.1, 0.3, 0.6), PAINT)
	_glass(c, Vector3(0, 1.65, -6.45), Vector3(2.7, 1.25, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-4.0)))
	_glass(c, Vector3(0, 1.75, 6.45), Vector3(2.5, 0.9, 0.03))
	_rb(c, Vector3(0, 0.45, -6.45), Vector3(3.0, 0.28, 0.16), BLACK, RUBBER, 0.3)
	_rb(c, Vector3(0, 2.6, 0), Vector3(2.6, 0.12, 11.0), Color(0.75, 0.77, 0.8), MATTE, 0.3)
	for s2 in [-1.0, 1.0]:
		_lamp(c, Vector3(s2 * 1.15, 0.8, -6.48), Vector3(0.3, 0.13, 0.04), Color(1, 0.97, 0.88), "head")
		_lamp(c, Vector3(s2 * 1.2, 0.9, 6.47), Vector3(0.2, 0.2, 0.04), Color(1, 0.08, 0.05), "head")
		_wheel(c, Vector3(s2 * 1.2, 0.45, -4.6), 0.45, 0.3, true)
		_wheel(c, Vector3(s2 * 1.2, 0.45, 4.2), 0.45, 0.3)
	_lamp(c, Vector3(0, 2.72, -4.0), Vector3(0.16, 0.14, 0.16), AMBER, "beacon", 0.3)
	_label(c, String(c.text) if String(c.text) != "" else "APRON", Vector3(0, 2.25, -6.47), Vector3(0, 0, -1), 0.3, Color(0.1, 0.12, 0.2))
