class_name AircraftModel
extends Node3D
## Procedural exterior model generated from the aircraft type data. The static airframe is a
## single mesh (one draw call) painted by one shader; control surfaces, gear, fans, propellers,
## doors and lights are separate animated nodes. Body axes: +X right, +Y up, -Z forward.

const P_BODY := 0.0
const P_WING := 0.1
const P_TAIL := 0.2
const P_NACELLE := 0.3
const P_METAL := 0.4
const P_DARK := 0.5
const P_GLASS := 0.6
const P_WHITE := 0.7
const P_INLET := 0.8
const P_EXHAUST := 0.9

static var _mat_cache := {}

var spec: Dictionary
var detail := 1.0
var mat: ShaderMaterial
var exterior: Node3D            # fuselage-only node (hidden from inside the cabin)
var airframe: MeshInstance3D
var fuselage_mi: MeshInstance3D
var surfaces := {}              # name -> {pivot, sign, max}
var gear := []                  # [{pivot, axis, angle, wheels:[Node3D], radius, doors:[]}]
var fans := []                  # Node3D spinning per engine
var prop_discs := []
var prop_blades := []
var doors := {}                 # name -> {pivot, axis, angle, open}
var lights := {}                # name -> MeshInstance3D sprite
var landing_lights := []
var label_nodes := []
var wheel_angle := 0.0
var fan_angle := []
var body_len := 37.0
var cg_z := 0.0
var _flash_t := 0.0
var door_l1_local := Vector3.ZERO


func build(type_id: String, airline_code: String, reg: String, detail_level: float = 1.0) -> void:
	spec = AircraftTypes.get_type(type_id)
	detail = detail_level
	body_len = float(spec.length)
	cg_z = -body_len * float(spec.cg_frac)
	mat = _material(airline_code, type_id)
	exterior = Node3D.new()
	exterior.name = "Exterior"
	add_child(exterior)
	var static_mb := MeshBuilder.new()
	var fuse_mb := MeshBuilder.new()
	_build_fuselage(fuse_mb)
	_build_wings(static_mb)
	_build_tail(static_mb)
	_build_engines(static_mb)
	_build_gear()
	_build_doors()
	_build_lights()
	fuselage_mi = MeshInstance3D.new()
	fuselage_mi.name = "Fuselage"
	fuselage_mi.mesh = fuse_mb.commit()
	fuselage_mi.material_override = mat
	exterior.add_child(fuselage_mi)
	airframe = MeshInstance3D.new()
	airframe.name = "Airframe"
	airframe.mesh = static_mb.commit()
	airframe.material_override = mat
	add_child(airframe)
	if detail > 0.5:
		_build_labels(airline_code, reg)


static func _material(airline_code: String, type_id: String) -> ShaderMaterial:
	var key := airline_code + ":" + type_id
	if _mat_cache.has(key):
		return _mat_cache[key]
	var t := AircraftTypes.get_type(type_id)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/aircraft_paint.gdshader")
	var l := Airlines.livery_colors(airline_code)
	m.set_shader_parameter("body_col", l.body)
	m.set_shader_parameter("belly_col", l.belly)
	m.set_shader_parameter("stripe_col", l.stripe)
	m.set_shader_parameter("tail_col", l.tail)
	m.set_shader_parameter("logo_col", l.logo)
	m.set_shader_parameter("engine_col", l.engine)
	m.set_shader_parameter("logo_shape", int(l.logo_shape))
	m.set_shader_parameter("fuse_len", float(t.length))
	m.set_shader_parameter("fuse_r", float(t.fuse_h) * 0.5)
	var nose_t := _nose_frac(t)
	var dl: Array = t.doors
	var win_start: float = float(dl[0]) + 0.6 / float(t.length)
	var win_end: float = float(dl[dl.size() - 1]) - 0.6 / float(t.length)
	if dl.size() == 1:
		win_end = 1.0 - _tail_frac(t) + 0.02
	if t.category == "trainer":
		win_start = 0.3
		win_end = 0.52
	m.set_shader_parameter("win_start", win_start)
	m.set_shader_parameter("win_end", win_end)
	m.set_shader_parameter("win_pitch", 0.53 if t.category != "bizjet" else 1.1)
	m.set_shader_parameter("cockpit_v", (pilot_eye_station(t) - 0.85) / float(t.length))
	var d: Array = t.doors
	var dv := Vector4(-1, -1, -1, -1)
	for i in mini(d.size(), 4):
		dv[i] = d[i]
	m.set_shader_parameter("doors", dv)
	var ow: Array = t.get("overwing", [])
	var dv2 := Vector4(-1, -1, -1, -1)
	for i in mini(ow.size(), 4):
		dv2[i] = ow[i]
	m.set_shader_parameter("doors2", dv2)
	if t.category == "cargo":
		m.set_shader_parameter("win_end", nose_t + 0.06)
	_mat_cache[key] = m
	return m


static func _nose_frac(t: Dictionary) -> float:
	var D: float = t.fuse_h
	var L: float = t.length
	match String(t.nose):
		"pointy":
			return clampf(2.4 * D / L, 0.08, 0.2)
		"ga":
			return 0.16
		"regional":
			return clampf(1.5 * D / L, 0.07, 0.16)
	return clampf(1.35 * D / L, 0.06, 0.15)


## Station (metres from the nose) of the pilots' eyes; the windscreen sits ~0.8 m ahead of it.
static func pilot_eye_station(t: Dictionary) -> float:
	match String(t.category):
		"trainer": return 2.25
		"turboprop": return 2.6
		"regional": return 2.6
		"bizjet": return 3.3
		"widebody": return 3.7
		"cargo": return 5.4
	return 3.0


static var _crown_cache := {}


## Exponent of the upper nose profile, chosen so the crown passes ~0.55 m above the pilots'
## eyes at the flight deck station.
static func _crown_exp(t: Dictionary) -> float:
	var key := String(t.name)
	if _crown_cache.has(key):
		return _crown_cache[key]
	var rh := float(t.fuse_h) * 0.5
	var nose_len := _nose_frac(t) * float(t.length)
	var ke := clampf(pilot_eye_station(t) / maxf(nose_len, 0.1), 0.2, 0.95)
	var floor_k: float = CabinLayout.FLOOR_K.get(String(t.category), -0.33)
	var eye_y := rh * floor_k + 1.12
	if bool(t.hump):
		eye_y = rh * 0.3 + 1.12
	var target := clampf((eye_y + 0.55) / rh, 0.2, 0.95)
	if bool(t.hump):
		target /= 1.35
	var base := 1.0 - pow(1.0 - ke, 1.2)
	var b := clampf(log(target) / log(base), 0.45, 2.2)
	_crown_cache[key] = b
	return b


static func _tail_frac(t: Dictionary) -> float:
	var D: float = t.fuse_h
	var L: float = t.length
	if t.category == "trainer":
		return 0.5
	return clampf(2.2 * D / L, 0.16, 0.3)


# ------------------------------------------------------------------ fuselage
func _ring(t: float, segs: int) -> PackedVector3Array:
	var rw: float = float(spec.fuse_w) * 0.5
	var rh: float = float(spec.fuse_h) * 0.5
	var sp := section(spec, t)
	var sx := sp.x
	var s_top := sp.y
	var s_bot := sp.z
	var cy := sp.w
	var z := cg_z + t * body_len
	var pts := PackedVector3Array()
	for i in segs:
		var th := TAU * float(i) / segs
		var sy := s_top if cos(th) >= 0.0 else s_bot
		pts.append(Vector3(sin(th) * rw * sx, cos(th) * rh * sy + cy, z))
	return pts


## Cross-section scale at body station t (0 nose .. 1 tail): x = width scale, y = upper height
## scale, z = lower height scale, w = vertical centre offset (metres).
static func section(spec: Dictionary, t: float) -> Vector4:
	var rh: float = float(spec.fuse_h) * 0.5
	var tn := _nose_frac(spec)
	var tt := 1.0 - _tail_frac(spec)
	var sx := 1.0
	var s_top := 1.0
	var s_bot := 1.0
	var cy := 0.0
	var nose_kind: String = spec.nose
	if t < tn:
		var k := t / tn
		var pw := 2.0
		var ex := 0.5
		if nose_kind == "pointy":
			pw = 1.55
			ex = 0.62
		elif nose_kind == "ga":
			pw = 3.0
			ex = 0.35
		var s := pow(1.0 - pow(1.0 - k, pw), ex)
		sx = s
		s_top = s
		s_bot = s
		if nose_kind == "ga":
			s = maxf(s, 0.35)
			sx = s
			s_top = s * 0.9
			s_bot = s
		else:
			# airliner nose: full lower radome, low sloping crown carrying the windscreen
			s_bot = pow(1.0 - pow(1.0 - k, 2.4), 0.5)
			s_top = pow(1.0 - pow(1.0 - k, 1.2), _crown_exp(spec))
	elif t > tt:
		var k2 := (t - tt) / (1.0 - tt)
		if spec.category == "trainer":
			sx = 1.0 - 0.85 * k2
			s_top = 1.0 - 0.75 * k2
			s_bot = 1.0 - 0.6 * k2
			cy = rh * 0.35 * k2
		else:
			sx = 1.0 - 0.86 * pow(k2, 1.55)
			s_top = 1.0 - 0.7 * pow(k2, 1.6)
			s_bot = 1.0 - 0.92 * pow(k2, 1.05)
			cy = rh * 0.55 * pow(k2, 1.25)
	if bool(spec.hump) and t > 0.03 and t < 0.36:
		var hk := clampf((t - 0.03) / 0.08, 0.0, 1.0) * clampf((0.36 - t) / 0.1, 0.0, 1.0)
		s_top *= 1.0 + 0.42 * U.smooth01(hk)
	return Vector4(sx, s_top, s_bot, cy)


func _build_fuselage(mb: MeshBuilder) -> void:
	var segs := 28 if detail > 0.5 else 14
	var ts := []
	var tn := _nose_frac(spec)
	var tt := 1.0 - _tail_frac(spec)
	var n_nose := 12 if detail > 0.5 else 6
	for i in n_nose:
		var k := float(i) / n_nose
		ts.append(tn * (1.0 - cos(k * PI * 0.5)))
	var n_body := 6
	for i in n_body:
		ts.append(lerpf(tn, tt, float(i) / n_body))
	var n_tail := 9 if detail > 0.5 else 5
	for i in n_tail + 1:
		ts.append(lerpf(tt, 0.995, float(i) / n_tail))
	if bool(spec.hump):
		for extra in [0.05, 0.1, 0.2, 0.3, 0.34, 0.38]:
			ts.append(extra)
		ts.sort()
	var rings := []
	var vs := []
	for t in ts:
		rings.append(_ring(t, segs))
		vs.append(t)
	mb.add_loft(rings, Color(P_BODY, 0, 0), false, true, vs)
	# wing-to-body fairing (belly) for low-wing aircraft
	if spec.wing_pos == "low" and spec.category != "trainer":
		var rh: float = float(spec.fuse_h) * 0.5
		var rw: float = float(spec.fuse_w) * 0.5
		var mac: float = spec.mac
		mb.add_sphere(Vector3(0, -rh * 0.62, 0.15 * mac), Vector3(rw * 0.9, rh * 0.45, mac * 1.25), 14, 6, Color(P_BODY, 0, 0, 1))
	# trainer: engine cowling front, spinner handled by the propeller
	if spec.category == "trainer":
		var zf := cg_z
		mb.add_cylinder(Vector3(0, 0, zf + 0.05), Vector3(0, 0, zf + 1.4), 0.48, 0.62, 16, Color(P_BODY, 0, 0), true)
		# windows of the cabin as dark glass panels
		var rw2: float = float(spec.fuse_w) * 0.5
		var rh2: float = float(spec.fuse_h) * 0.5
		for sx in [-1.0, 1.0]:
			mb.add_box(Vector3(sx * rw2 * 0.97, rh2 * 0.35, zf + 2.9), Vector3(0.04, 0.55, 1.6), Color(P_GLASS, 0, 0))
		mb.add_box(Vector3(0, rh2 * 0.62, zf + 2.05), Vector3(rw2 * 1.7, 0.05, 0.6), Color(P_GLASS, 0, 0))


# ------------------------------------------------------------------ lifting surfaces
static func _airfoil_y(x: float, tc: float) -> float:
	return 5.0 * tc * (0.2969 * sqrt(maxf(x, 0.0)) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1015 * x * x * x * x)


## Point on a lifting surface. span_dir/thick_dir define the surface plane.
func _surf_point(root: Vector3, span_dir: Vector3, thick_dir: Vector3, s: float, x: float, upper: bool,
		c_r: float, c_t: float, semi: float, le_slope: float, dih_slope: float, tc: float) -> Vector3:
	var eta := s / semi
	var c := lerpf(c_r, c_t, eta)
	var le := root + span_dir * s + Vector3(0, 0, s * le_slope) + thick_dir * (s * dih_slope)
	var yt := _airfoil_y(x, tc) * c
	var camber := 0.018 * c * sin(PI * x) if tc > 0.07 else 0.0
	var off := (yt if upper else -yt) + camber
	return le + Vector3(0, 0, x * c) + thick_dir * off


func _surface_ring(root: Vector3, span_dir: Vector3, thick_dir: Vector3, s: float, x0: float, x1: float,
		c_r: float, c_t: float, semi: float, le_slope: float, dih_slope: float, tc: float, n: int) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for i in n:
		var k := float(i) / (n - 1)
		var x := lerpf(x0, x1, 1.0 - cos(k * PI * 0.5)) if x0 == 0.0 else lerpf(x0, x1, k)
		ring.append(_surf_point(root, span_dir, thick_dir, s, x, true, c_r, c_t, semi, le_slope, dih_slope, tc))
	for i in n:
		var k := float(n - 1 - i) / (n - 1)
		var x := lerpf(x0, x1, 1.0 - cos(k * PI * 0.5)) if x0 == 0.0 else lerpf(x0, x1, k)
		ring.append(_surf_point(root, span_dir, thick_dir, s, x, false, c_r, c_t, semi, le_slope, dih_slope, tc))
	return ring


func _loft_surface(mb: MeshBuilder, params: Dictionary, s0: float, s1: float, x0: float, x1: float, part: float, steps: int = 2) -> void:
	var rings := []
	var n := 7 if detail > 0.5 else 4
	for i in steps + 1:
		var s := lerpf(s0, s1, float(i) / steps)
		rings.append(_surface_ring(params.root, params.span_dir, params.thick_dir, s, x0, x1, params.c_r, params.c_t,
			params.semi, params.le_slope, params.dih_slope, params.tc, n))
	mb.add_loft(rings, Color(part, 0, 0), true, true)


func _hinged(name: String, params: Dictionary, s0: float, s1: float, x0: float, x1: float, part: float, down_is_te_down: bool, max_deg: float) -> void:
	## Builds a control surface as its own node, pivoting about its leading edge line.
	var a := _surf_point(params.root, params.span_dir, params.thick_dir, s0, x0, true, params.c_r, params.c_t, params.semi, params.le_slope, params.dih_slope, params.tc)
	var a2 := _surf_point(params.root, params.span_dir, params.thick_dir, s0, x0, false, params.c_r, params.c_t, params.semi, params.le_slope, params.dih_slope, params.tc)
	var b := _surf_point(params.root, params.span_dir, params.thick_dir, s1, x0, true, params.c_r, params.c_t, params.semi, params.le_slope, params.dih_slope, params.tc)
	var b2 := _surf_point(params.root, params.span_dir, params.thick_dir, s1, x0, false, params.c_r, params.c_t, params.semi, params.le_slope, params.dih_slope, params.tc)
	var A := (a + a2) * 0.5
	var B := (b + b2) * 0.5
	var xa := (B - A).normalized()
	var up: Vector3 = params.thick_dir
	var za := xa.cross(up).normalized()
	var ya := za.cross(xa).normalized()
	var basis := Basis(xa, ya, za)
	var pivot := Node3D.new()
	pivot.name = name
	pivot.transform = Transform3D(basis, A)
	pivot.set_meta("b0", basis)
	var mb := MeshBuilder.new()
	mb.xf = Transform3D(basis, A).affine_inverse()
	_loft_surface(mb, params, s0, s1, x0, x1, part, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	pivot.add_child(mi)
	add_child(pivot)
	# decide which rotation sign moves the trailing edge toward +thick_dir (or -)
	var te := _surf_point(params.root, params.span_dir, params.thick_dir, (s0 + s1) * 0.5, 1.0, true, params.c_r, params.c_t, params.semi, params.le_slope, params.dih_slope, params.tc)
	var te_local := basis.inverse() * (te - A)
	var rotated := Basis(Vector3.RIGHT, 0.2) * te_local
	var moved := basis * rotated - basis * te_local
	var sign := 1.0 if moved.dot(up) < 0.0 else -1.0
	if not down_is_te_down:
		sign = -sign
	surfaces[name] = {"pivot": pivot, "sign": sign, "max": deg_to_rad(max_deg), "angle": 0.0}


func _wing_params(side: float) -> Dictionary:
	var b: float = spec.span
	var S: float = spec.wing_area
	var lam: float = spec.taper
	var semi := b * 0.5
	var c_r := 2.0 * S / (b * (1.0 + lam))
	var c_t := c_r * lam
	var sweep := deg_to_rad(float(spec.sweep))
	var mac := 2.0 / 3.0 * c_r * (1.0 + lam + lam * lam) / (1.0 + lam)
	var eta_mac := (1.0 + 2.0 * lam) / (3.0 * (1.0 + lam))
	var le_slope := tan(sweep) + (c_r - c_t) * 0.25 / semi * 0.0
	var z_le_root := -0.22 * mac - eta_mac * semi * le_slope
	var rh: float = float(spec.fuse_h) * 0.5
	var wy := -rh * 0.48 if spec.wing_pos == "low" else rh * 0.78
	return {"root": Vector3(0, wy, z_le_root), "span_dir": Vector3(side, 0, 0), "thick_dir": Vector3.UP,
		"c_r": c_r, "c_t": c_t, "semi": semi, "le_slope": le_slope, "dih_slope": tan(deg_to_rad(float(spec.dihedral))),
		"tc": 0.13 if spec.category in ["trainer", "turboprop"] else 0.115}


func _build_wings(mb: MeshBuilder) -> void:
	for side in [-1.0, 1.0]:
		var p := _wing_params(side)
		var semi: float = p.semi
		var x_split := 0.74
		var flap_end := 0.62 if spec.category != "trainer" else 0.55
		var ail_end := 0.94
		# main box (leading edge to rear spar) over the whole span
		_loft_surface(mb, p, 0.0, semi, 0.0, x_split, P_WING, 3)
		var sname := "R" if side > 0 else "L"
		_hinged("flap_" + sname, p, semi * 0.08, semi * flap_end, x_split, 1.0, P_WING, true, 40.0)
		_hinged("aileron_" + sname, p, semi * flap_end, semi * ail_end, x_split, 1.0, P_WING, true, 25.0)
		# fixed trailing edge pieces at root and tip
		_loft_surface(mb, p, 0.0, semi * 0.08, x_split, 1.0, P_WING, 1)
		_loft_surface(mb, p, semi * ail_end, semi, x_split, 1.0, P_WING, 1)
		if bool(spec.spoilers):
			_hinged("spoiler_" + sname, p, semi * 0.2, semi * flap_end * 0.98, 0.56, x_split, P_WING, false, 50.0)
		# winglet
		var wl: String = spec.winglet
		if wl != "none":
			var tip := _surf_point(p.root, p.span_dir, p.thick_dir, semi, 0.0, true, p.c_r, p.c_t, semi, p.le_slope, p.dih_slope, p.tc)
			var c_tip: float = p.c_t
			var h := c_tip * (1.3 if wl == "sharklet" else (0.9 if wl == "blended" else 0.0))
			if wl == "raked":
				var rp := {"root": tip, "span_dir": Vector3(side, 0, 0), "thick_dir": Vector3.UP, "c_r": c_tip, "c_t": c_tip * 0.25,
					"semi": c_tip * 1.6, "le_slope": 1.1, "dih_slope": 0.04, "tc": 0.09}
				_loft_surface(mb, rp, 0.0, c_tip * 1.6, 0.0, 1.0, P_WING, 2)
			else:
				var cant := Vector3(side * 0.25, 1.0, 0).normalized()
				var wp := {"root": tip + Vector3(0, 0, c_tip * 0.15), "span_dir": cant, "thick_dir": Vector3(side, -0.25, 0).normalized() * -1.0,
					"c_r": c_tip * 0.8, "c_t": c_tip * 0.35, "semi": h, "le_slope": 0.6, "dih_slope": 0.0, "tc": 0.08}
				_loft_surface(mb, wp, 0.0, h, 0.0, 1.0, P_TAIL if wl == "sharklet" else P_WING, 2)
		# trainer wing strut
		if spec.category == "trainer":
			var rh: float = float(spec.fuse_h) * 0.5
			var a := Vector3(side * float(spec.fuse_w) * 0.45, -rh * 0.6, 0.2)
			var bpt := _surf_point(p.root, p.span_dir, p.thick_dir, semi * 0.55, 0.3, false, p.c_r, p.c_t, semi, p.le_slope, p.dih_slope, p.tc)
			mb.add_cylinder(a, bpt, 0.06, 0.05, 6, Color(P_WING, 0, 0), false)


func _build_tail(mb: MeshBuilder) -> void:
	var b: float = spec.span
	var rh: float = float(spec.fuse_h) * 0.5
	var t_tail: bool = spec.tail == "t_tail"
	var L := body_len
	var tail_z := cg_z + L * 0.86
	if spec.category == "trainer":
		tail_z = cg_z + L * 0.82
	# vertical fin
	var fin_h := b * (0.19 if not t_tail else 0.2)
	if spec.category == "trainer":
		fin_h = 1.5
	elif spec.category in ["widebody", "cargo"]:
		fin_h = b * 0.17
	var fin_cr := fin_h * (1.15 if not t_tail else 1.0)
	var fin_ct := fin_cr * (0.42 if not t_tail else 0.7)
	var fin_sweep := deg_to_rad(38.0 if spec.category != "trainer" else 30.0)
	var fin_root := Vector3(0, rh * 0.55, tail_z - fin_cr * 0.62)
	var fp := {"root": fin_root, "span_dir": Vector3.UP, "thick_dir": Vector3.RIGHT, "c_r": fin_cr, "c_t": fin_ct,
		"semi": fin_h, "le_slope": tan(fin_sweep), "dih_slope": 0.0, "tc": 0.1}
	# fin with fin-chord UVs for the logo: build manually to set UV
	var fin_mb := MeshBuilder.new()
	_loft_surface(fin_mb, fp, 0.0, fin_h, 0.0, 0.72, P_TAIL, 3)
	_fin_uv(fin_mb, fp)
	mb.add_mesh_builder(fin_mb)
	_hinged("rudder", fp, fin_h * 0.06, fin_h * 0.96, 0.72, 1.0, P_TAIL, true, 25.0)
	# horizontal stabiliser
	var hs_semi := b * (0.17 if spec.category != "trainer" else 0.3)
	var hs_cr := hs_semi * (0.75 if spec.category != "trainer" else 0.55)
	var hs_root: Vector3
	if t_tail:
		var top := _surf_point(fp.root, fp.span_dir, fp.thick_dir, fin_h * 0.98, 0.0, true, fin_cr, fin_ct, fin_h, fp.le_slope, 0.0, 0.1)
		hs_root = Vector3(0, top.y - 0.1, top.z - hs_cr * 0.1)
	else:
		hs_root = Vector3(0, rh * 0.1, tail_z - hs_cr * 0.35)
	for side in [-1.0, 1.0]:
		var hp := {"root": hs_root, "span_dir": Vector3(side, 0, 0), "thick_dir": Vector3.UP, "c_r": hs_cr, "c_t": hs_cr * 0.42,
			"semi": hs_semi, "le_slope": tan(deg_to_rad(float(spec.sweep) + 6.0)), "dih_slope": tan(deg_to_rad(4.0 if not t_tail else -2.0)), "tc": 0.1}
		_loft_surface(mb, hp, 0.0, hs_semi, 0.0, 0.7, P_WING, 2)
		_hinged("elevator_" + ("R" if side > 0 else "L"), hp, hs_semi * 0.08, hs_semi * 0.97, 0.7, 1.0, P_WING, true, 25.0)
		_loft_surface(mb, hp, 0.0, hs_semi * 0.08, 0.7, 1.0, P_WING, 1)


func _fin_uv(fmb: MeshBuilder, fp: Dictionary) -> void:
	for i in fmb.verts.size():
		var v := fmb.verts[i]
		var span_t := clampf((v.y - fp.root.y) / fp.semi, 0.0, 1.0)
		var c: float = lerpf(fp.c_r, fp.c_t, span_t)
		var le_z: float = fp.root.z + (v.y - fp.root.y) * fp.le_slope
		fmb.uvs[i] = Vector2(clampf((v.z - le_z) / c, 0.0, 1.0), span_t)


# ------------------------------------------------------------------ engines
func _build_engines(mb: MeshBuilder) -> void:
	var positions := FlightModel.engine_positions(spec)
	var et: String = spec.engine_type
	for i in positions.size():
		var p: Vector3 = positions[i]
		fan_angle.append(0.0)
		if et == "turbofan":
			_turbofan(mb, p, i)
		elif et == "turboprop":
			_turboprop(mb, p, i)
		else:
			_nose_prop(p, i)


func _turbofan(mb: MeshBuilder, p: Vector3, idx: int) -> void:
	var D: float = spec.get("fan_diam", 1.8)
	var R := D * 0.58
	var length := D * (2.1 if spec.engine_mount != "rear" else 2.4)
	var z0 := p.z - length * 0.5
	var rings := []
	var prof := [[0.0, 0.92], [0.04, 1.0], [0.18, 1.04], [0.45, 1.0], [0.75, 0.84], [1.0, 0.62]]
	var segs := 20 if detail > 0.5 else 10
	for pr in prof:
		var ring := PackedVector3Array()
		for k in segs:
			var a := TAU * k / segs
			ring.append(p + Vector3(sin(a) * R * pr[1], cos(a) * R * pr[1], z0 + pr[0] * length - p.z))
		rings.append(ring)
	mb.add_loft(rings, Color(P_NACELLE, 0, 0), false, false)
	# inlet lip interior and fan face
	mb.add_cylinder(Vector3(p.x, p.y, z0 + 0.02), Vector3(p.x, p.y, z0 + D * 0.35), R * 0.9, R * 0.86, segs, Color(P_INLET, 0, 0), false)
	# exhaust: core nozzle and plug
	var ze := z0 + length
	mb.add_cylinder(Vector3(p.x, p.y, ze - 0.05), Vector3(p.x, p.y, ze + D * 0.35), R * 0.55, R * 0.38, segs, Color(P_EXHAUST, 0, 0), false)
	mb.add_cone(Vector3(p.x, p.y, ze + D * 0.3), Vector3(p.x, p.y, ze + D * 0.75), R * 0.3, 10, Color(P_EXHAUST, 0, 0))
	# pylon
	if spec.engine_mount == "rear":
		var side := signf(p.x)
		var root := Vector3(side * float(spec.fuse_w) * 0.42, p.y, p.z)
		mb.add_box(Vector3((root.x + p.x) * 0.5, p.y, p.z), Vector3(absf(p.x - root.x), 0.25, length * 0.55), Color(P_NACELLE, 0, 0))
	else:
		var wp := _wing_params(signf(p.x))
		var s := absf(p.x)
		var wing_low := _surf_point(wp.root, wp.span_dir, wp.thick_dir, s, 0.25, false, wp.c_r, wp.c_t, wp.semi, wp.le_slope, wp.dih_slope, wp.tc)
		var top := p.y + R * 0.85
		mb.add_box(Vector3(p.x, (top + wing_low.y) * 0.5 + 0.1, (z0 + wing_low.z) * 0.5 + 0.6), Vector3(0.35, maxf(wing_low.y - top + 0.4, 0.4), maxf(wing_low.z - z0 + 1.2, length * 0.8)), Color(P_NACELLE, 0, 0))
	# spinning fan (separate node)
	var fan := Node3D.new()
	fan.position = Vector3(p.x, p.y, z0 + D * 0.3)
	add_child(fan)
	var fmb := MeshBuilder.new()
	fmb.add_cone(Vector3(0, 0, 0.05), Vector3(0, 0, -D * 0.28), D * 0.13, 12, Color(P_WHITE, 0, 0))
	var blades := 18 if detail > 0.5 else 8
	for k in blades:
		var a := TAU * k / blades
		var dir := Vector3(sin(a), cos(a), 0)
		var bt := Transform3D(Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.5), dir * R * 0.5)
		fmb.add_box_xf(bt, Vector3(R * 0.13, R * 0.78, 0.04), Color(P_METAL, 0, 0))
	var fmi := MeshInstance3D.new()
	fmi.mesh = fmb.commit()
	fmi.material_override = mat
	fan.add_child(fmi)
	fans.append(fan)
	prop_discs.append(null)
	prop_blades.append(null)


func _turboprop(mb: MeshBuilder, p: Vector3, idx: int) -> void:
	var D: float = spec.get("prop_diam", 3.9)
	var nac_len := D * 1.45
	var r := D * 0.17
	var z0 := p.z - nac_len * 0.45
	var segs := 16 if detail > 0.5 else 8
	var rings := []
	var prof := [[0.0, 0.55], [0.06, 0.9], [0.25, 1.0], [0.7, 0.95], [1.0, 0.3]]
	for pr in prof:
		var ring := PackedVector3Array()
		for k in segs:
			var a := TAU * k / segs
			ring.append(Vector3(p.x + sin(a) * r * pr[1], p.y - 0.25 + cos(a) * r * pr[1] * 1.25, z0 + pr[0] * nac_len))
		rings.append(ring)
	mb.add_loft(rings, Color(P_NACELLE, 0, 0), true, true)
	var hub := Node3D.new()
	hub.position = Vector3(p.x, p.y - 0.25, z0 - 0.1)
	add_child(hub)
	var hmb := MeshBuilder.new()
	hmb.add_cone(Vector3(0, 0, 0.1), Vector3(0, 0, -0.75), r * 0.55, 12, Color(P_WHITE, 0, 0))
	var nb := 6
	var bmb := MeshBuilder.new()
	for k in nb:
		var a := TAU * k / nb
		var dir := Vector3(sin(a), cos(a), 0)
		bmb.add_box_xf(Transform3D(Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.35), dir * D * 0.26), Vector3(0.22, D * 0.44, 0.05), Color(P_DARK, 0, 0))
	var hmi := MeshInstance3D.new()
	hmi.mesh = hmb.commit()
	hmi.material_override = mat
	hub.add_child(hmi)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bmb.commit()
	bmi.material_override = mat
	hub.add_child(bmi)
	var disc := _prop_disc(D, nb)
	hub.add_child(disc)
	fans.append(hub)
	prop_discs.append(disc)
	prop_blades.append(bmi)


func _nose_prop(p: Vector3, idx: int) -> void:
	var D: float = spec.get("prop_diam", 1.9)
	var hub := Node3D.new()
	hub.position = Vector3(0, 0, cg_z - 0.05)
	add_child(hub)
	var hmb := MeshBuilder.new()
	hmb.add_cone(Vector3(0, 0, 0.1), Vector3(0, 0, -0.45), 0.22, 12, Color(P_WHITE, 0, 0))
	var bmb := MeshBuilder.new()
	for k in 2:
		var a := PI * k
		bmb.add_box_xf(Transform3D(Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.3), Vector3(sin(a), cos(a), 0) * D * 0.25), Vector3(0.12, D * 0.46, 0.03), Color(P_DARK, 0, 0))
	var hmi := MeshInstance3D.new()
	hmi.mesh = hmb.commit()
	hmi.material_override = mat
	hub.add_child(hmi)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bmb.commit()
	bmi.material_override = mat
	hub.add_child(bmi)
	var disc := _prop_disc(D, 2)
	hub.add_child(disc)
	fans.append(hub)
	prop_discs.append(disc)
	prop_blades.append(bmi)


func _prop_disc(D: float, blades: int) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(D, D)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/prop_disc.gdshader")
	m.set_shader_parameter("blades", float(blades))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


# ------------------------------------------------------------------ landing gear
func _build_gear() -> void:
	var gh: float = spec.gear_height
	var rh: float = float(spec.fuse_h) * 0.5
	var wr := 0.3 if spec.category == "trainer" else clampf(gh * 0.2, 0.35, 0.68)
	var retract: bool = spec.gear_retract
	var configs := [
		{"z": float(spec.nose_gear_x), "x": 0.0, "wheels": 2 if spec.category != "trainer" else 1, "bogie": false, "nose": true},
		{"z": float(spec.main_gear_x), "x": -float(spec.gear_track) * 0.5, "wheels": 2, "bogie": spec.category in ["widebody", "cargo"], "nose": false},
		{"z": float(spec.main_gear_x), "x": float(spec.gear_track) * 0.5, "wheels": 2, "bogie": spec.category in ["widebody", "cargo"], "nose": false},
	]
	for gi in 3:
		var c: Dictionary = configs[gi]
		var top_y := -rh * 0.55 if c.nose else (-rh * 0.4 if spec.wing_pos == "low" else -rh * 0.85)
		var pivot := Node3D.new()
		pivot.position = Vector3(c.x, top_y, c.z)
		add_child(pivot)
		var leg_len := gh + top_y - wr
		var mb := MeshBuilder.new()
		var leg_col := Color(P_WHITE, 0, 0) if spec.category != "trainer" else Color(P_BODY, 0, 0)
		mb.add_cylinder(Vector3(0, 0, 0), Vector3(0, -leg_len, 0), 0.09 * (gh / 2.5) + 0.05, 0.08 * (gh / 2.5) + 0.04, 8, leg_col, true)
		var wheels := []
		var axle_y := -leg_len
		var wheel_nodes := Node3D.new()
		wheel_nodes.position = Vector3(0, axle_y, 0)
		pivot.add_child(wheel_nodes)
		var offs := []
		if c.bogie:
			offs = [Vector3(-0.55, 0, -0.75), Vector3(0.55, 0, -0.75), Vector3(-0.55, 0, 0.75), Vector3(0.55, 0, 0.75)]
			mb.add_box(Vector3(0, axle_y, 0), Vector3(0.18, 0.18, 1.8), Color(P_METAL, 0, 0))
		elif c.wheels == 2:
			offs = [Vector3(-0.32 - wr * 0.3, 0, 0), Vector3(0.32 + wr * 0.3, 0, 0)]
		else:
			offs = [Vector3(0, 0, 0)]
		for o in offs:
			var w := Node3D.new()
			w.position = o
			wheel_nodes.add_child(w)
			var wmb := MeshBuilder.new()
			wmb.add_cylinder(Vector3(-0.14, 0, 0), Vector3(0.14, 0, 0), wr, wr, 14, Color(P_DARK, 0, 0), true)
			wmb.add_cylinder(Vector3(-0.15, 0, 0), Vector3(0.15, 0, 0), wr * 0.55, wr * 0.55, 10, Color(P_METAL, 0, 0), true)
			wmb.add_box(Vector3(0, wr * 0.3, 0), Vector3(0.31, 0.06, wr * 0.15), Color(P_WHITE, 0, 0))
			var wmi := MeshInstance3D.new()
			wmi.mesh = wmb.commit()
			wmi.material_override = mat
			w.add_child(wmi)
			wheels.append(w)
		if spec.category == "trainer":
			# wheel fairings
			mb.add_sphere(Vector3(0, axle_y + 0.05, 0), Vector3(0.18, 0.32, 0.55), 10, 6, Color(P_BODY, 0, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = mat
		pivot.add_child(mi)
		# retraction: nose folds forward, mains fold inward
		var axis := Vector3.RIGHT if c.nose else Vector3(0, 0, -signf(c.x))
		var ang := -PI * 0.5 if c.nose else PI * 0.5
		gear.append({"pivot": pivot, "axis": axis, "angle": ang, "wheels": wheels, "radius": wr, "wheel_root": wheel_nodes, "leg": leg_len, "retract": retract})


# ------------------------------------------------------------------ doors
func _build_doors() -> void:
	var d: Array = spec.doors
	if d.is_empty() or spec.category == "trainer":
		return
	var tn := _nose_frac(spec)
	var dz := cg_z + float(d[0]) * body_len
	var rw: float = float(spec.fuse_w) * 0.5
	var rh: float = float(spec.fuse_h) * 0.5
	door_l1_local = Vector3(-rw, rh * 0.05, dz)
	var pivot := Node3D.new()
	pivot.position = Vector3(-rw * 0.98, rh * 0.05, dz - 0.55)
	add_child(pivot)
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(-0.04, 0, 0.55), Vector3(0.08, 1.9, 1.05), Color(P_BODY, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	pivot.add_child(mi)
	pivot.visible = false
	doors["L1"] = {"pivot": pivot, "axis": Vector3.UP, "angle": -1.9, "open": 0.0}
	if bool(spec.hump) and bool(spec.cargo_door):
		# freighter nose door hinges upward
		var np := Node3D.new()
		np.position = Vector3(0, rh * 0.9, cg_z + body_len * tn * 0.95)
		add_child(np)
		doors["NOSE"] = {"pivot": np, "axis": Vector3.RIGHT, "angle": 1.2, "open": 0.0}


func set_door(name: String, open_frac: float) -> void:
	if doors.has(name):
		doors[name].open = clampf(open_frac, 0.0, 1.0)


# ------------------------------------------------------------------ lights
func _sprite(color: Color, pattern: int, phase: float, size: float, pos: Vector3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/nav_light.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("size", size)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.extra_cull_margin = 8.0
	add_child(mi)
	return mi


func _build_lights() -> void:
	var p := _wing_params(1.0)
	var semi: float = p.semi
	var tip_r := _surf_point(p.root, Vector3.RIGHT, Vector3.UP, semi, 0.1, true, p.c_r, p.c_t, semi, p.le_slope, p.dih_slope, p.tc)
	var tip_l := Vector3(-tip_r.x, tip_r.y, tip_r.z)
	var rh: float = float(spec.fuse_h) * 0.5
	var tail := Vector3(0, rh * 0.5, cg_z + body_len * 0.995)
	lights["nav_r"] = _sprite(Color(0.1, 1.0, 0.25), 0, 0.0, 0.25, tip_r + Vector3(0.2, 0, 0))
	lights["nav_l"] = _sprite(Color(1.0, 0.08, 0.05), 0, 0.0, 0.25, tip_l - Vector3(0.2, 0, 0))
	lights["nav_tail"] = _sprite(Color(1, 1, 1), 0, 0.0, 0.2, tail)
	lights["strobe_r"] = _sprite(Color(1, 1, 1), 1, 0.0, 0.35, tip_r + Vector3(0.25, 0.05, 0.3))
	lights["strobe_l"] = _sprite(Color(1, 1, 1), 1, 0.0, 0.35, tip_l + Vector3(-0.25, 0.05, 0.3))
	lights["strobe_tail"] = _sprite(Color(1, 1, 1), 1, 0.5, 0.3, tail + Vector3(0, 0.1, 0.1))
	lights["beacon_top"] = _sprite(Color(1, 0.1, 0.05), 2, 0.0, 0.3, Vector3(0, rh * 1.02, cg_z + body_len * 0.45))
	lights["beacon_bot"] = _sprite(Color(1, 0.1, 0.05), 2, 0.5, 0.3, Vector3(0, -rh * 1.02, cg_z + body_len * 0.5))
	if detail > 0.5 and bool(Game.q("lights")):
		var count := 2 if not Game.is_mobile else 1
		for i in count:
			var sl := SpotLight3D.new()
			sl.spot_range = 900.0 if spec.category != "trainer" else 400.0
			sl.spot_angle = 14.0
			sl.spot_attenuation = 0.6
			sl.light_energy = 0.0
			sl.light_color = Color(1.0, 0.95, 0.85)
			sl.shadow_enabled = false
			var x := 0.0 if count == 1 else (-1.0 if i == 0 else 1.0) * float(spec.fuse_w) * 0.9
			sl.position = Vector3(x, -rh * 0.6, cg_z + body_len * 0.2)
			sl.rotation = Vector3(deg_to_rad(-4.0), 0, 0)
			add_child(sl)
			landing_lights.append(sl)
	for k in lights.keys():
		lights[k].visible = false


func _build_labels(airline_code: String, reg: String) -> void:
	var al := Airlines.get_al(airline_code)
	var colors := Airlines.livery_colors(airline_code)
	var rw: float = float(spec.fuse_w) * 0.5
	var rh: float = float(spec.fuse_h) * 0.5
	var tn := _nose_frac(spec)
	var name_z := cg_z + body_len * (tn + 0.12)
	var text: String = String(al.name).to_upper()
	var size := clampf(float(spec.fuse_h) * 0.12, 0.22, 0.75)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 64
		l.pixel_size = size / 46.0
		l.modulate = colors.text
		l.double_sided = false
		l.shaded = true
		l.outline_size = 0
		var face := Vector3(side, 0, 0)
		var zv := face
		var yv := Vector3.UP
		var xv := yv.cross(zv)
		var lz := name_z + float(text.length()) * size * 0.3
		l.transform = Transform3D(Basis(xv, yv, zv), Vector3(side * rw * 0.86, rh * 0.62, lz))
		l.visibility_range_end = 2500.0
		add_child(l)
		label_nodes.append(l)
		var r := Label3D.new()
		r.text = reg
		r.font_size = 48
		r.pixel_size = size * 0.55 / 34.0
		r.modulate = Color(0.2, 0.2, 0.22)
		r.double_sided = false
		r.transform = Transform3D(Basis(xv, yv, zv), Vector3(side * rw * 0.75, rh * 0.3, cg_z + body_len * 0.82))
		r.visibility_range_end = 800.0
		add_child(r)
		label_nodes.append(r)


# ------------------------------------------------------------------ animation
func animate(ac: Node, dt: float) -> void:
	if ac == null:
		return
	var a: Aircraft = ac
	var fdm := a.fdm
	var sys := a.sys
	# control surfaces
	_set_surface("aileron_R", -fdm.aileron)
	_set_surface("aileron_L", fdm.aileron)
	_set_surface("elevator_R", -fdm.elevator * 0.9)
	_set_surface("elevator_L", -fdm.elevator * 0.9)
	_set_surface("rudder", -fdm.rudder)
	var flap_deg: float = 0.0
	var flaps: Array = spec.flaps
	var fi := clampf(sys.flap_pos, 0.0, flaps.size() - 1.0)
	var i0 := int(floor(fi))
	var i1 := mini(i0 + 1, flaps.size() - 1)
	flap_deg = lerpf(float(flaps[i0].deg), float(flaps[i1].deg), fi - i0)
	_set_surface_deg("flap_R", flap_deg)
	_set_surface_deg("flap_L", flap_deg)
	_set_surface("spoiler_R", sys.spoilers + maxf(fdm.aileron, 0.0) * 0.4 * float(not fdm.on_ground))
	_set_surface("spoiler_L", sys.spoilers + maxf(-fdm.aileron, 0.0) * 0.4 * float(not fdm.on_ground))
	# gear: retraction and compression
	for gi in gear.size():
		var g: Dictionary = gear[gi]
		var ext: float = sys.gear_pos[gi] if gi < sys.gear_pos.size() else 1.0
		if not g.retract:
			ext = 1.0
		var ang: float = (1.0 - ext) * g.angle
		g.pivot.basis = Basis(g.axis, ang)
		g.pivot.visible = ext > 0.02 or detail < 0.5
		if a.damage.gear[gi]:
			g.pivot.basis = Basis(g.axis, g.angle * 0.55)
		var load: float = fdm.gear_load[gi] if gi < fdm.gear_load.size() else 0.0
		var comp := clampf(load / maxf(fdm.mass * U.G0, 1.0) * 0.5, 0.0, 0.3)
		g.wheel_root.position.y = -g.leg + comp
		var ws := fdm.wheel_speed if fdm.on_ground else lerpf(0.0, 0.0, 0.0)
		for w in g.wheels:
			w.rotation.x -= ws / g.radius * dt
	# engines
	for i in fans.size():
		if i >= sys.eng.size():
			break
		var e: Dictionary = sys.eng[i]
		var rate := 0.0
		if spec.engine_type == "turbofan":
			rate = float(e.n1) / 100.0 * 55.0
		else:
			rate = float(e.rpm) / 60.0 * TAU * 0.12 if e.running else float(e.n1) * 0.3
		fan_angle[i] = fmod(fan_angle[i] + rate * dt, TAU)
		fans[i].rotation.z = fan_angle[i]
		if prop_discs[i] != null:
			var fast := rate > 8.0
			prop_discs[i].visible = fast
			prop_blades[i].visible = not fast or detail < 0.5
			prop_discs[i].material_override.set_shader_parameter("rpm_k", clampf(rate / 30.0, 0.0, 1.0))
	# doors
	for dn in doors.keys():
		var d: Dictionary = doors[dn]
		var cur: float = d.get("cur", 0.0)
		cur = move_toward(cur, d.open, dt * 0.35)
		d.cur = cur
		d.pivot.visible = cur > 0.01 or dn == "NOSE"
		d.pivot.basis = Basis(d.axis, d.angle * cur)
	# lights
	var L: Dictionary = sys.lights
	var powered := sys.dc_power
	var night: float = a.world.night if a.world else 0.0
	for k in ["nav_r", "nav_l", "nav_tail"]:
		lights[k].visible = L.nav and powered
	for k in ["strobe_r", "strobe_l", "strobe_tail"]:
		lights[k].visible = L.strobe and powered
	for k in ["beacon_top", "beacon_bot"]:
		lights[k].visible = L.beacon and powered
	for k in lights.keys():
		lights[k].material_override.set_shader_parameter("night", night)
	for sl in landing_lights:
		sl.light_energy = (6.0 if L.landing and powered else 0.0) * clampf(night * 1.4, 0.0, 1.0)
		sl.visible = sl.light_energy > 0.01
	mat.set_shader_parameter("cabin_lights", night * (1.0 if L.cabin and powered else 0.0))


func _set_surface(name: String, frac: float) -> void:
	if not surfaces.has(name):
		return
	var s: Dictionary = surfaces[name]
	var ang := clampf(frac, -1.0, 1.0) * float(s.max)
	s.pivot.basis = Basis(Vector3.RIGHT, ang * float(s.sign)) if s.pivot.get_meta("b0", null) == null else s.pivot.get_meta("b0") * Basis(Vector3.RIGHT, ang * float(s.sign))


func _set_surface_deg(name: String, deg: float) -> void:
	if not surfaces.has(name):
		return
	var s: Dictionary = surfaces[name]
	_set_surface(name, deg_to_rad(deg) / maxf(float(s.max), 0.001))


func show_exterior_fuselage(show: bool) -> void:
	## From inside, the exterior skin stays visible (seen through the windows, its inner faces
	## are culled) but stops casting shadows: the interior shells shadow the sun instead, so
	## light enters only through real window openings.
	exterior.visible = true
	fuselage_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if show else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in label_nodes:
		l.visible = show
	for d in doors.values():
		(d.pivot as Node3D).visible = show and float(d.open) > 0.01


func door_world_local() -> Vector3:
	return door_l1_local
