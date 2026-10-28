class_name AircraftModel
extends Node3D
## Procedural exterior model generated from the aircraft type data. The static airframe is two
## meshes (the fuselage skin, and wings/tail/engines/details) painted by one shader; control
## surfaces, slats, flaps, spoilers, reversers, gear, fans, propellers, doors and lights are separate
## animated nodes. Meshes depend only on the type and detail level, so they are generated once and
## shared by every instance; the livery lives in the material. Body axes: +X right, +Y up,
## -Z forward, origin at the CG.

# part ids, written to vertex COLOR.r as id / 64 (see shaders/aircraft_paint.gdshader)
const P_BODY := 0
const P_WING := 1
const P_TAIL := 2
const P_NACELLE := 3
const P_METAL := 4
const P_DARK := 5
const P_GLASS := 6
const P_GEAR := 7
const P_INLET := 8
const P_EXHAUST := 9
const P_LIP := 10
const P_FAN := 11
const P_SPINNER := 12
const P_PLUG := 13
const P_TYRE := 14
const P_HUB := 15
const P_CHROME := 16
const P_BELLY := 17
const P_FLAT := 18
const P_WINGLET := 19
const P_LENS := 20
const P_WELL := 21
const P_PROP := 22
const P_BOOT := 23
const P_PYLON := 24
const P_STAB := 25
const P_WHITE := P_GEAR

static var _mat_cache := {}
static var _kit_cache := {}
static var _crown_cache := {}
static var _fonts := {}
static var _light_mat: ShaderMaterial = null
static var _quad: QuadMesh = null

var spec: Dictionary
var detail := 1.0
var hi := true
var mat: ShaderMaterial
var exterior: Node3D            # fuselage-only node (stays visible from inside the cabin)
var airframe: MeshInstance3D
var fuselage_mi: MeshInstance3D
var surfaces := {}              # name -> {pivot, sign, max, angle, b0, o0, travel}
var gear := []                  # [{pivot, axis, angle, wheels, radius, wheel_root, leg, retract, src, steer}]
var fans := []                  # Node3D spinning per engine
var prop_discs := []
var prop_blades := []
var doors := {}                 # name -> {pivot, axis, angle, open, cur, ...}
var lights := {}                # name -> MeshInstance3D glow sprite
var landing_lights := []
var label_nodes := []
var wheel_angle := 0.0
var fan_angle := []
var body_len := 37.0
var cg_z := 0.0
var door_l1_local := Vector3.ZERO
var anchors := {}               # named body-frame points (engines, gear, wingtips, tail) for cameras
var livery := ""
var reversers := []             # per engine: {node, base, travel} or null
var gear_doors := []            # [{pivot, b0, axis, angle, src}]
var _mis := []                  # painted mesh instances (per-aircraft shader parameters)
var _inst := {}
var _type_id := "s320"
var _k := {}                    # kit under construction
var _rw := 1.0
var _rh := 1.0
var _boxy := 0.0
var _bulges := []
var _W := {}


func build(type_id: String, airline_code: String, reg: String, detail_level: float = 1.0) -> void:
	spec = AircraftTypes.get_type(type_id)
	_type_id = type_id if AircraftTypes.TYPES.has(type_id) else "s320"
	detail = detail_level
	hi = detail_level > 0.5
	body_len = float(spec.length)
	cg_z = -body_len * float(spec.cg_frac)
	_setup_geometry()
	var key := _type_id + (":hi" if hi else ":lo")
	if not _kit_cache.has(key):
		_kit_cache[key] = _make_kit()
	var kit: Dictionary = _kit_cache[key]
	livery = Airlines.livery_for(airline_code, reg, _type_id)
	mat = _material(livery, _type_id, kit.shader)
	_instantiate(kit)
	_build_labels(livery, reg)


func _make_kit() -> Dictionary:
	_k = {"parts": [], "gear": [], "engines": [], "lights": [], "doors": [], "anchors": {}, "shader": {},
		"door_l1": Vector3.ZERO, "gear_doors": [], "landing": [], "wheels": {}}
	var fmb := _new_mb()
	var amb := _new_mb()
	_build_fuselage(fmb)
	_build_wings(amb)
	_build_tail(amb)
	_build_engines(amb)
	_build_gear(amb)
	_build_doors()
	var panes := _cockpit_panes()
	_build_details(fmb, amb, panes)
	_build_light_defs(fmb, amb)
	_shader_geometry(panes)
	_k.fuselage = fmb.commit()
	_k.airframe = amb.commit()
	_k.erase("wheels")
	return _k


func _instantiate(kit: Dictionary) -> void:
	exterior = Node3D.new()
	exterior.name = "Exterior"
	add_child(exterior)
	fuselage_mi = _mesh_node(kit.fuselage, "Fuselage", exterior)
	airframe = _mesh_node(kit.airframe, "Airframe", self)
	anchors = kit.anchors
	door_l1_local = kit.door_l1
	for p in kit.parts:
		var pivot := Node3D.new()
		pivot.name = String(p.name)
		pivot.transform = p.xf
		add_child(pivot)
		_mesh_node(p.mesh, "Mesh", pivot)
		if String(p.kind) == "reverser":
			while reversers.size() <= int(p.engine):
				reversers.append(null)
			reversers[int(p.engine)] = {"node": pivot, "base": (p.xf as Transform3D).origin, "travel": p.travel}
		else:
			surfaces[String(p.name)] = {"pivot": pivot, "sign": p.sign, "max": p.max, "angle": 0.0,
				"b0": (p.xf as Transform3D).basis, "o0": (p.xf as Transform3D).origin, "travel": p.travel}
	for gd in kit.gear:
		var pivot := Node3D.new()
		pivot.name = "Gear%d" % gear.size()
		pivot.position = gd.pos
		add_child(pivot)
		_mesh_node(gd.leg_mesh, "Leg", pivot)
		var root := Node3D.new()
		root.name = "Slider"
		root.position = Vector3(0, -float(gd.leg), 0)
		pivot.add_child(root)
		var steer := Node3D.new()
		steer.name = "Steer"
		root.add_child(steer)
		if gd.slider_mesh != null:
			_mesh_node(gd.slider_mesh, "Piston", steer)
		var wheels := []
		for w in gd.wheels:
			var wn := Node3D.new()
			wn.position = w.pos
			steer.add_child(wn)
			_mesh_node(w.mesh, "Wheel", wn)
			wheels.append(wn)
		gear.append({"pivot": pivot, "axis": gd.axis, "angle": gd.angle, "wheels": wheels, "radius": gd.radius,
			"wheel_root": root, "leg": gd.leg, "retract": gd.retract, "src": gd.src, "steer": steer if bool(gd.nose) else null})
	for gdd in kit.gear_doors:
		var dp := Node3D.new()
		dp.transform = gdd.xf
		add_child(dp)
		_mesh_node(gdd.mesh, "Door", dp)
		gear_doors.append({"pivot": dp, "b0": (gdd.xf as Transform3D).basis, "axis": gdd.axis, "angle": gdd.angle, "src": gdd.src})
	for e in kit.engines:
		var fan := Node3D.new()
		fan.name = "Engine%d" % fans.size()
		fan.position = e.pos
		add_child(fan)
		_mesh_node(e.mesh, "Rotor", fan).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var blades: MeshInstance3D = null
		var disc: MeshInstance3D = null
		if e.blades != null:
			blades = _mesh_node(e.blades, "Blades", fan)
			disc = _prop_disc(float(e.disc), int(e.nb))
			fan.add_child(disc)
		fans.append(fan)
		prop_discs.append(disc)
		prop_blades.append(blades)
		fan_angle.append(0.0)
	while reversers.size() < fans.size():
		reversers.append(null)
	for d in kit.doors:
		var pivot := Node3D.new()
		pivot.name = "Door" + String(d.name)
		pivot.transform = d.xf
		add_child(pivot)
		if d.mesh != null:
			_mesh_node(d.mesh, "Panel", pivot)
		pivot.visible = String(d.name) == "NOSE"
		doors[String(d.name)] = {"pivot": pivot, "axis": d.axis, "angle": d.angle, "open": 0.0, "cur": 0.0,
			"kind": d.kind, "x0": d.xf, "w": d.w}
	for ld in kit.lights:
		var parent: Node3D = self
		var gi: int = ld.get("gear", -1)
		if gi >= 0 and gi < gear.size():
			parent = gear[gi].pivot
		_sprite(String(ld.name), ld.color, int(ld.pattern), float(ld.phase), float(ld.size), ld.pos, ld.aim, parent)
	if hi and bool(Game.q("lights")):
		var count := 2 if not Game.is_mobile else 1
		var lp: Array = kit.landing
		for i in mini(count, lp.size()):
			var sl := SpotLight3D.new()
			sl.spot_range = 900.0 if spec.category != "trainer" else 400.0
			sl.spot_angle = 14.0
			sl.spot_attenuation = 0.6
			sl.light_energy = 0.0
			sl.light_color = Color(1.0, 0.95, 0.85)
			sl.shadow_enabled = false
			var pos: Vector3 = lp[i] if count == 2 else (lp[0] + lp[1]) * 0.5 * Vector3(0, 1, 1)
			sl.position = pos
			sl.rotation = Vector3(deg_to_rad(-4.0), 0, 0)
			add_child(sl)
			landing_lights.append(sl)


func _mesh_node(m: Mesh, nm: String, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	_mis.append(mi)
	return mi


# ------------------------------------------------------------------ material / livery
static func _material(lv: String, type_id: String, geo: Dictionary) -> ShaderMaterial:
	var key := lv + ":" + type_id
	if _mat_cache.has(key):
		return _mat_cache[key]
	var t := AircraftTypes.get_type(type_id)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/aircraft_paint.gdshader")
	var l := Airlines.livery_colors(lv)
	for k in ["body", "belly", "stripe", "stripe2", "stripe3", "tail", "tail2", "logo", "engine", "engine2", "wing", "tip", "gear", "art"]:
		if l.has(k):
			m.set_shader_parameter(k + "_col", l[k])
	m.set_shader_parameter("logo_shape", int(l.get("logo_shape", 0)))
	m.set_shader_parameter("engine_style", int(l.get("engine_style", 0)))
	for k in ["belly_h", "nose_dip", "rise_t", "rise_h", "flow_t", "flow_h", "tail_band", "metal_belly", "nose_paint", "event_art"]:
		if l.has(k):
			m.set_shader_parameter(k, float(l[k]))
	var st: Array = l.get("stripes", [0.0, 0.0, 0.0, 0.0])
	m.set_shader_parameter("stripes", Vector4(st[0], st[1], st[2], st[3]))
	var s3: Array = l.get("stripe3_at", [0.0, 0.0])
	m.set_shader_parameter("stripe3", Vector2(s3[0], s3[1]))
	var stt: Array = l.get("stripe_t", [0.06, 0.985])
	m.set_shader_parameter("stripe_t", Vector2(stt[0], stt[1]))
	var mk: float = l.get("mask", -1.0)
	if mk < 0.0:
		mk = 1.0 if t.category == "widebody" else 0.0
	m.set_shader_parameter("mask", mk)
	for k in geo.keys():
		m.set_shader_parameter(k, geo[k])
	_mat_cache[key] = m
	return m


# ------------------------------------------------------------------ shared geometry API
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


static func _airfoil_y(x: float, tc: float) -> float:
	return 5.0 * tc * (0.2969 * sqrt(maxf(x, 0.0)) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1015 * x * x * x * x)


# ------------------------------------------------------------------ mesh helpers
static func _c(part: int, g: float = 0.0, b: float = 0.0, a: float = 1.0) -> Color:
	return Color(float(part) / 64.0, g, b, a)


func _new_mb() -> MeshBuilder:
	var m := MeshBuilder.new()
	m.use_uv2 = true
	return m


## Emits a rows x cols vertex grid; each quad is wound so that its front faces the vertex normals.
func _emit_grid(mb: MeshBuilder, rows: int, cols: int, pos: PackedVector3Array, nrm: PackedVector3Array,
		col: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array) -> void:
	var base := mb.verts.size()
	for i in pos.size():
		mb.add_vertex(pos[i], nrm[i], col[i], uv[i], uv2[i])
	for r in rows - 1:
		for c in cols - 1:
			var i00 := r * cols + c
			var i01 := i00 + 1
			var i10 := i00 + cols
			var i11 := i10 + 1
			var gn := (pos[i10] - pos[i00]).cross(pos[i01] - pos[i00])
			if gn.length_squared() < 1e-18:
				gn = (pos[i11] - pos[i10]).cross(pos[i01] - pos[i10])
			if gn.length_squared() < 1e-18:
				continue
			var vn := nrm[i00] + nrm[i01] + nrm[i10] + nrm[i11]
			if gn.dot(vn) <= 0.0:
				mb.add_tri_idx(base + i00, base + i10, base + i01)
				mb.add_tri_idx(base + i10, base + i11, base + i01)
			else:
				mb.add_tri_idx(base + i00, base + i01, base + i10)
				mb.add_tri_idx(base + i10, base + i01, base + i11)


## Smooth grid normals by central differences, oriented along per-vertex hint vectors. With
## wrap_c the last column repeats the first (closed rings).
func _grid_normals(rows: int, cols: int, pos: PackedVector3Array, hint: PackedVector3Array, wrap_c: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pos.size())
	for r in rows:
		var ra := maxi(r - 1, 0)
		var rb := mini(r + 1, rows - 1)
		for c in cols:
			var ca := c - 1
			var cb := c + 1
			if wrap_c:
				if ca < 0:
					ca = cols - 2
				if cb > cols - 1:
					cb = 1
			else:
				ca = maxi(ca, 0)
				cb = mini(cb, cols - 1)
			var dr := pos[rb * cols + c] - pos[ra * cols + c]
			var dc := pos[r * cols + cb] - pos[r * cols + ca]
			var n := dr.cross(dc)
			var h := hint[r * cols + c]
			if n.length_squared() < 1e-16:
				n = h
			elif n.dot(h) < 0.0:
				n = -n
			out[r * cols + c] = n.normalized() if n.length_squared() > 1e-20 else Vector3.UP
	return out


## Triangle fan closing a ring, facing n.
func _fan(mb: MeshBuilder, ctr: Vector3, ring: PackedVector3Array, n: Vector3, c: Color) -> void:
	var ci := mb.add_vertex(ctr, n, c, Vector2(0.5, 0.5), Vector2(ctr.z, ctr.y))
	var st := mb.verts.size()
	var m := ring.size()
	for p in ring:
		mb.add_vertex(p, n, c, Vector2(0.5, 0.5), Vector2(p.z, p.y))
	for i in m:
		var j := (i + 1) % m
		var gn := (ring[i] - ctr).cross(ring[j] - ctr)
		if gn.dot(n) > 0.0:
			mb.add_tri_idx(ci, st + j, st + i)
		else:
			mb.add_tri_idx(ci, st + i, st + j)


## Lofts closed rings (equal point counts) into a tube with smooth normals pointing away from
## the ring centres.
func _loft_rings(mb: MeshBuilder, rings: Array, centers: Array, part: int, vs: Array = [], cap0: bool = false,
		cap1: bool = false, g: float = 0.0, b: float = 0.0) -> void:
	var rows := rings.size()
	var n: int = (rings[0] as PackedVector3Array).size()
	var cols := n + 1
	var pos := PackedVector3Array()
	var hint := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cc := _c(part, g, b)
	for r in rows:
		var ring: PackedVector3Array = rings[r]
		var ctr: Vector3 = centers[r]
		var v: float = vs[r] if vs.size() == rows else float(r) / float(rows - 1)
		var axis_out: Vector3 = (ctr - (centers[1] as Vector3)) if r == 0 else (ctr - (centers[r - 1] as Vector3))
		for j in cols:
			var p := ring[j % n]
			pos.append(p)
			var h := p - ctr
			if h.length_squared() < 1e-10:
				h = axis_out
			hint.append(h)
			col.append(cc)
			uv.append(Vector2(float(j) / n, v))
			uv2.append(Vector2(p.z, p.y))
	var nrm := _grid_normals(rows, cols, pos, hint, true)
	_emit_grid(mb, rows, cols, pos, nrm, col, uv, uv2)
	if cap0:
		_fan(mb, centers[0], rings[0], ((centers[0] as Vector3) - (centers[1] as Vector3)).normalized(), cc)
	if cap1:
		_fan(mb, centers[rows - 1], rings[rows - 1], ((centers[rows - 1] as Vector3) - (centers[rows - 2] as Vector3)).normalized(), cc)


## Surface of revolution about the axis through o along ax. prof: Vector2(distance along the axis,
## radius) points; parts: part id of each profile segment; vs: UV.y of each profile point.
func _revolve(mb: MeshBuilder, o: Vector3, ax: Vector3, prof: Array, parts: Array, vs: Array, segs: int, g: float = 0.0) -> void:
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := ax.cross(u).normalized()
	var np := prof.size()
	var n2 := []
	for i in np:
		var pa: Vector2 = prof[maxi(i - 1, 0)]
		var pb: Vector2 = prof[mini(i + 1, np - 1)]
		var tg := pb - pa
		if tg.length_squared() < 1e-14:
			tg = Vector2(1, 0)
		tg = tg.normalized()
		n2.append(Vector2(-tg.y, tg.x))
	var cols := segs + 1
	var dirs := []
	for j in cols:
		var a := TAU * float(j) / segs
		dirs.append(u * cos(a) + v * sin(a))
	var i0 := 0
	while i0 < np - 1:
		var part: int = parts[mini(i0, parts.size() - 1)]
		var i1 := i0 + 1
		while i1 < np - 1 and int(parts[mini(i1, parts.size() - 1)]) == part:
			i1 += 1
		var rows := i1 - i0 + 1
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var cc := _c(part, g)
		for r in rows:
			var pi := i0 + r
			var pp: Vector2 = prof[pi]
			var nn: Vector2 = n2[pi]
			var vv: float = vs[pi] if pi < vs.size() else 0.0
			for j in cols:
				var rad: Vector3 = dirs[j]
				var p := o + ax * pp.x + rad * pp.y
				pos.append(p)
				nrm.append((ax * nn.x + rad * nn.y).normalized())
				col.append(cc)
				uv.append(Vector2(float(j) / segs, vv))
				uv2.append(Vector2(p.z, p.y))
		_emit_grid(mb, rows, cols, pos, nrm, col, uv, uv2)
		i0 = i1


## Lifting-surface section: leading edge, chord / thickness directions, chord, t/c, span fraction.
func _sec(le: Vector3, cd: Vector3, td: Vector3, c: float, tc: float, v: float, cam: float = 0.0) -> Dictionary:
	return {"le": le, "cd": cd, "td": td, "c": c, "tc": tc, "v": v, "cam": cam}


func _spt(s: Dictionary, x: float, upper: bool) -> Vector3:
	var c: float = s.c
	var yt := _airfoil_y(x, float(s.tc)) * c
	var cm: float = float(s.cam) * c * x * (1.0 - x) * (1.0 + 0.8 * x) * 2.2
	var le: Vector3 = s.le
	var cd: Vector3 = s.cd
	var td: Vector3 = s.td
	return le + cd * (x * c) + td * ((yt if upper else -yt) + cm)


func _smid(s: Dictionary, x: float) -> Vector3:
	var c: float = s.c
	var cm: float = float(s.cam) * c * x * (1.0 - x) * (1.0 + 0.8 * x) * 2.2
	return (s.le as Vector3) + (s.cd as Vector3) * (x * c) + (s.td as Vector3) * cm


## Closed lifting surface between chord fractions x0..x1: skins (wrapping the leading edge when
## x0 is 0), front / rear faces and optional end caps. opts: side (COLOR.b), g (COLOR.g override),
## uv2 "xz" (planform) or "zy" (fin), cap0, cap1, side_from_upper.
func _surf(mb: MeshBuilder, secs: Array, x0: float, x1: float, part: int, nx: int, opts: Dictionary = {}) -> void:
	var xs := PackedFloat32Array()
	for k in nx:
		var f := float(k) / float(nx - 1)
		if x0 <= 0.0001:
			xs.append(x1 * (0.55 * (1.0 - cos(f * PI * 0.5)) + 0.45 * f * f))
		else:
			xs.append(lerpf(x0, x1, f))
	var cols := []
	if x0 <= 0.0001:
		for k in range(nx - 1, 0, -1):
			cols.append([xs[k], false])
		cols.append([0.0, true])
		for k in range(1, nx):
			cols.append([xs[k], true])
		_skin(mb, secs, cols, part, opts)
	else:
		var up := []
		var dn := []
		for k in nx:
			up.append([xs[k], true])
			dn.append([xs[k], false])
		_skin(mb, secs, up, part, opts)
		_skin(mb, secs, dn, part, opts)
		_face(mb, secs, x0, part, -1.0, opts)
	_face(mb, secs, x1, part, 1.0, opts)
	if bool(opts.get("cap0", false)) or bool(opts.get("cap1", false)):
		for which in [0, 1]:
			if not bool(opts.get("cap%d" % which, false)):
				continue
			var si := 0 if which == 0 else secs.size() - 1
			var sj := 1 if which == 0 else secs.size() - 2
			var s: Dictionary = secs[si]
			var ring := PackedVector3Array()
			for k in nx:
				ring.append(_spt(s, xs[k], true))
			for k in range(nx - 1, -1, -1):
				ring.append(_spt(s, xs[k], false))
			var n := ((s.le as Vector3) - ((secs[sj] as Dictionary).le as Vector3)).normalized()
			_fan(mb, _smid(s, (x0 + x1) * 0.5), ring, n, _c(part, 0.5, float(opts.get("side", 0.0))))


func _skin(mb: MeshBuilder, secs: Array, cols: Array, part: int, opts: Dictionary) -> void:
	var rows := secs.size()
	var nc := cols.size()
	var pos := PackedVector3Array()
	var hint := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var g_over: float = opts.get("g", -1.0)
	var side: float = opts.get("side", 0.0)
	var zy := String(opts.get("uv2", "xz")) == "zy"
	var sfu := bool(opts.get("side_from_upper", false))
	for r in rows:
		var s: Dictionary = secs[r]
		for cdef in cols:
			var x: float = cdef[0]
			var upper: bool = cdef[1]
			var p := _spt(s, x, upper)
			pos.append(p)
			var ref := _smid(s, clampf(x, 0.025, 0.975))
			hint.append(p - ref)
			var gg := g_over if g_over >= 0.0 else (1.0 if upper else 0.0)
			var bb := (1.0 if upper else 0.0) if sfu else side
			col.append(_c(part, gg, bb))
			uv.append(Vector2(x, float(s.v)))
			uv2.append(Vector2(p.z, p.y) if zy else Vector2(p.x, p.z))
	var nrm := _grid_normals(rows, nc, pos, hint, false)
	_emit_grid(mb, rows, nc, pos, nrm, col, uv, uv2)


## Flat chordwise face at fraction x (dirn -1 faces forward, +1 aft).
func _face(mb: MeshBuilder, secs: Array, x: float, part: int, dirn: float, opts: Dictionary) -> void:
	var rows := secs.size()
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var side: float = opts.get("side", 0.0)
	var zy := String(opts.get("uv2", "xz")) == "zy"
	for r in rows:
		var s: Dictionary = secs[r]
		var n: Vector3 = (s.cd as Vector3) * dirn
		for upper in [true, false]:
			var p := _spt(s, x, upper)
			pos.append(p)
			nrm.append(n)
			col.append(_c(part, 0.5, side))
			uv.append(Vector2(x, float(s.v)))
			uv2.append(Vector2(p.z, p.y) if zy else Vector2(p.x, p.z))
	_emit_grid(mb, rows, 2, pos, nrm, col, uv, uv2)


## Registers an animated part from geometry built in the body frame. The pivot sits on the hinge
## line A-B; `ref` is a point that should move towards -up (true) or +up (false) for positive input.
func _add_part(kind: String, name: String, A: Vector3, B: Vector3, up: Vector3, body_mb: MeshBuilder, max_rad: float,
		ref: Vector3, ref_down: bool, travel: Vector3, extra := {}) -> void:
	var xa := (B - A).normalized()
	var za := xa.cross(up).normalized()
	var ya := za.cross(xa).normalized()
	var basis := Basis(xa, ya, za)
	var xf := Transform3D(basis, A)
	var local := _new_mb()
	local.xf = xf.affine_inverse()
	local.add_mesh_builder(body_mb)
	var rl := xf.affine_inverse() * ref
	var moved := basis * (Basis(Vector3.RIGHT, 0.2) * rl) - basis * rl
	var sgn := 1.0 if moved.dot(up) < 0.0 else -1.0
	if not ref_down:
		sgn = -sgn
	var d := {"kind": kind, "name": name, "xf": xf, "mesh": local.commit(), "sign": sgn, "max": max_rad, "travel": travel}
	d.merge(extra)
	_k.parts.append(d)


## Hinged control surface between chord fractions x0..x1 of the given sections. In the light
## model only flaps stay movable; everything else is merged into the static mesh `sm`.
func _hinged(name: String, secs: Array, x0: float, x1: float, part: int, max_deg: float, te_down: bool,
		travel: Vector3, sm: MeshBuilder, opts: Dictionary = {}, extra: MeshBuilder = null) -> void:
	var tmp := _new_mb()
	var o := opts.duplicate()
	o["cap0"] = true
	o["cap1"] = true
	_surf(tmp, secs, x0, x1, part, 5 if hi else 3, o)
	if extra != null:
		tmp.add_mesh_builder(extra)
	if not hi and not name.begins_with("flap"):
		sm.add_mesh_builder(tmp)
		return
	var s0: Dictionary = secs[0]
	var s1: Dictionary = secs[secs.size() - 1]
	var A := (_spt(s0, x0, true) + _spt(s0, x0, false)) * 0.5
	var B := (_spt(s1, x0, true) + _spt(s1, x0, false)) * 0.5
	var up := ((s0.td as Vector3) + (s1.td as Vector3)).normalized()
	var mid: Dictionary = secs[secs.size() / 2]
	_add_part("surface", name, A, B, up, tmp, deg_to_rad(max_deg), _spt(mid, x1, true), te_down, travel)


# ------------------------------------------------------------------ geometry setup
func _setup_geometry() -> void:
	_rw = float(spec.fuse_w) * 0.5
	_rh = float(spec.fuse_h) * 0.5
	_boxy = 2.6 if spec.category == "trainer" else 0.0
	_W = _wing_setup()
	_bulges = []
	var cat: String = spec.category
	if spec.wing_pos == "low" and cat != "trainer":
		var zle := _w_le_z(_rw)
		var c := _w_chord(_rw)
		_bulges.append({"z": [zle - 0.25 * c, zle + 0.3 * c, zle + 1.0 * c, zle + 1.85 * c], "a": _rw * 1.07,
			"b": _rh * 1.055, "n": 3.0, "c0": 0.2, "c1": -0.3, "keel": true, "top": false})
	elif cat == "turboprop":
		var mz: float = spec.main_gear_x
		_bulges.append({"z": [mz - 3.6, mz - 1.8, mz + 1.4, mz + 3.6], "a": _rw * 1.36, "b": _rh * 0.99,
			"n": 4.0, "c0": 0.0, "c1": -0.45, "keel": false, "top": false})
		var zl := _w_le_z(0.0)
		var cr := _w_chord(0.0)
		_bulges.append({"z": [zl - 0.6 * cr, zl + 0.15 * cr, zl + 0.9 * cr, zl + 2.2 * cr], "a": _rw * 0.62,
			"b": _rh * 1.16, "n": 2.4, "top": true, "keel": false, "c0": 0.0, "c1": 0.0})


func _wing_setup() -> Dictionary:
	var b: float = spec.span
	var semi := b * 0.5
	var S: float = spec.wing_area
	var lam: float = spec.taper
	var c_r := 2.0 * S / (b * (1.0 + lam))
	var c_t := c_r * lam
	var mac := 2.0 / 3.0 * c_r * (1.0 + lam + lam * lam) / (1.0 + lam)
	var eta_mac := (1.0 + 2.0 * lam) / (3.0 * (1.0 + lam))
	var le_slope := tan(deg_to_rad(float(spec.sweep)))
	var cat: String = spec.category
	var props := cat in ["trainer", "turboprop"]
	var w := {"semi": semi, "c_r": c_r, "c_t": c_t, "le_slope": le_slope,
		"z0": -0.22 * mac - eta_mac * semi * le_slope,
		"y0": -_rh * 0.48 if spec.wing_pos == "low" else _rh * 0.78,
		"dih": tan(deg_to_rad(float(spec.dihedral))),
		"kink": semi * (0.34 if cat in ["narrowbody", "widebody", "cargo"] else (0.3 if cat == "regional" else 0.0)),
		"tc_r": 0.16 if props else 0.145, "tc_t": 0.13 if props else 0.105,
		"twist": deg_to_rad(-2.0 if props else -3.0),
		"rake": semi * 0.9 if spec.winglet == "raked" else semi + 10.0,
		"cam": 0.03 if props else 0.034}
	var kink: float = w.kink
	w["te_in"] = float(w.z0) + kink * le_slope + lerpf(c_r, c_t, kink / semi)
	return w


func _w_le_z(s: float) -> float:
	var z: float = float(_W.z0) + s * float(_W.le_slope)
	var rk: float = _W.rake
	if s > rk:
		z += pow((s - rk) / (float(_W.semi) - rk), 1.8) * float(_W.c_t) * 0.78
	return z


func _w_chord(s: float) -> float:
	var semi: float = _W.semi
	var c := lerpf(float(_W.c_r), float(_W.c_t), clampf(s / semi, 0.0, 1.0))
	if s < float(_W.kink):
		c = float(_W.te_in) - (float(_W.z0) + s * float(_W.le_slope))
	var rk: float = _W.rake
	if s > rk:
		c -= pow((s - rk) / (semi - rk), 1.8) * float(_W.c_t) * 0.74
	return c


func _w_twist(s: float) -> float:
	var k: float = _W.kink
	var semi: float = _W.semi
	if s <= k:
		return 0.0
	return float(_W.twist) * clampf((s - k) / maxf(semi - k, 0.1), 0.0, 1.0)


func _wsec(side: float, s: float) -> Dictionary:
	var c := _w_chord(s)
	var tw := _w_twist(s)
	var gam := atan(float(_W.dih))
	var le := Vector3(side * s, float(_W.y0) + s * float(_W.dih), _w_le_z(s))
	var cd := Vector3(0.0, -sin(tw), cos(tw))
	var td := Vector3(-side * sin(gam), cos(gam), 0.0)
	td = (td - cd * td.dot(cd)).normalized()
	le += (Vector3(0, 0, 1) - cd) * 0.25 * c
	var semi: float = _W.semi
	var tc := lerpf(float(_W.tc_r), float(_W.tc_t), clampf(s / semi, 0.0, 1.0))
	return _sec(le, cd, td, c, tc, s / semi, float(_W.cam))


func _wsecs(side: float, ss: Array) -> Array:
	var out := []
	for s in ss:
		out.append(_wsec(side, float(s)))
	return out


## Stations from a to b no further apart than step, including breakpoints inside the range.
func _stations(a: float, b: float, step: float, extra: Array = []) -> Array:
	var n := maxi(int(ceil((b - a) / step)), 1)
	var out := []
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / n))
	for e in extra:
		var ef: float = e
		if ef > a + 0.05 and ef < b - 0.05:
			out.append(ef)
	out.sort()
	return out


## Half width of the outer skin at body z and height y (0 outside the section; bulges ignored).
func _hw(z: float, y: float) -> float:
	var t := clampf((z - cg_z) / body_len, 0.0, 1.0)
	var sp := section(spec, t)
	var sy := sp.y if y >= sp.w else sp.z
	var k := absf(y - sp.w) / maxf(_rh * sy, 0.001)
	if k >= 1.0:
		return 0.0
	if _boxy > 0.0:
		return _rw * sp.x * pow(1.0 - pow(k, _boxy), 1.0 / _boxy)
	return _rw * sp.x * sqrt(1.0 - k * k)


## Point on the nose skin at half width x and height y (searching aft from z_lo to z_hi).
func _skin_at_x(x: float, y: float, z_lo: float, z_hi: float) -> Vector3:
	if _hw(z_hi, y) <= x:
		return Vector3(_hw(z_hi, y), y, z_hi)
	var a := z_lo
	var b := z_hi
	for i in 28:
		var m := (a + b) * 0.5
		if _hw(m, y) < x:
			a = m
		else:
			b = m
	return Vector3(x, y, (a + b) * 0.5)


func _skin_at_z(z: float, y: float) -> Vector3:
	return Vector3(_hw(z, y), y, z)


# ------------------------------------------------------------------ fuselage
func _bulge(x: float, y: float, z: float, c: float) -> Vector2:
	for bg in _bulges:
		var zz: Array = bg.z
		if z <= float(zz[0]) or z >= float(zz[3]):
			continue
		var k := U.smooth01((z - float(zz[0])) / (float(zz[1]) - float(zz[0]))) * U.smooth01((float(zz[3]) - z) / (float(zz[3]) - float(zz[2])))
		var w: float
		if bool(bg.top):
			w = U.smooth01((c - 0.45) / 0.4)
		else:
			w = U.smooth01((float(bg.c0) - c) / (float(bg.c0) - float(bg.c1)))
			if not bool(bg.keel):
				w *= U.smooth01((c + 1.0) / 0.3)
		if k * w <= 0.0:
			continue
		var r0 := sqrt(x * x + y * y)
		if r0 < 1e-4:
			continue
		var dx := absf(x) / r0
		var dy := absf(y) / r0
		var n: float = bg.n
		var rf := 1.0 / pow(pow(dx / float(bg.a), n) + pow(dy / float(bg.b), n), 1.0 / n)
		var r := maxf(r0, lerpf(r0, rf, k * w))
		x *= r / r0
		y *= r / r0
	return Vector2(x, y)


func _fpt(sp: Vector4, t: float, th: float) -> Vector3:
	var s := sin(th)
	var c := cos(th)
	var sy := sp.y if c >= 0.0 else sp.z
	var x: float
	var y: float
	if _boxy > 0.0:
		var e := 2.0 / _boxy
		x = signf(s) * pow(absf(s), e) * _rw * sp.x
		y = signf(c) * pow(absf(c), e) * _rh * sy
	else:
		x = s * _rw * sp.x
		y = c * _rh * sy
	var z := cg_z + t * body_len
	if not _bulges.is_empty():
		var q := _bulge(x, y, z, c)
		x = q.x
		y = q.y
	return Vector3(x, y + sp.w, z)


func _fuse_stations() -> Array:
	var tn := _nose_frac(spec)
	var tt := 1.0 - _tail_frac(spec)
	var out := []
	var n_nose := 34 if hi else 10
	for i in n_nose:
		out.append(tn * (1.0 - cos(float(i) / n_nose * PI * 0.5)))
	var step := (1.25 if hi else 4.0) / body_len
	var n_body := maxi(int(ceil((tt - tn) / step)), 2)
	for i in n_body:
		out.append(lerpf(tn, tt, float(i) / n_body))
	var n_tail := 24 if hi else 8
	for i in n_tail + 1:
		out.append(lerpf(tt, 1.0, float(i) / n_tail))
	for bg in _bulges:
		var zz: Array = bg.z
		var n_b := 14 if hi else 6
		for i in n_b + 1:
			var z := lerpf(float(zz[0]), float(zz[3]), float(i) / n_b)
			out.append(clampf((z - cg_z) / body_len, 0.0, 1.0))
	if bool(spec.hump):
		for e in [0.05, 0.08, 0.11, 0.14, 0.26, 0.29, 0.32, 0.35, 0.38]:
			out.append(e)
	out.sort()
	var dd := []
	for t in out:
		if dd.is_empty() or float(t) - float(dd[dd.size() - 1]) > 0.0008:
			dd.append(t)
	return dd


func _build_fuselage(mb: MeshBuilder) -> void:
	var segs := 64 if hi else 22
	var ts := _fuse_stations()
	var rows := ts.size()
	var cols := segs + 1
	var pos := PackedVector3Array()
	var hint := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cc := _c(P_BODY)
	for t in ts:
		var tf: float = t
		var sp := section(spec, tf)
		for j in cols:
			var th := TAU * float(j) / segs
			var p := _fpt(sp, tf, th)
			pos.append(p)
			var h := p - Vector3(0, sp.w, p.z)
			if tf < 0.0005:
				h = Vector3(0, 0, -1)
			hint.append(h)
			col.append(cc)
			uv.append(Vector2(float(j) / segs, tf))
			uv2.append(Vector2(p.z, p.y))
	var nrm := _grid_normals(rows, cols, pos, hint, true)
	_emit_grid(mb, rows, cols, pos, nrm, col, uv, uv2)
	# tail closure and the APU exhaust
	var spe := section(spec, 1.0)
	var ring := PackedVector3Array()
	var ctr := Vector3.ZERO
	for j in segs:
		var p := _fpt(spe, 1.0, TAU * float(j) / segs)
		ring.append(p)
		ctr += p
	ctr /= segs
	_fan(mb, ctr, ring, Vector3(0, 0, 1), _c(P_BODY))
	if spec.category != "trainer":
		var r_apu := clampf(minf(_rw * spe.x, _rh * (spe.y + spe.z) * 0.5) * 0.7, 0.06, 0.32)
		var prof := [Vector2(-0.1, r_apu * 1.02), Vector2(0.1, r_apu), Vector2(0.11, r_apu * 0.86), Vector2(-0.12, r_apu * 0.84), Vector2(-0.12, 0.0)]
		_revolve(mb, ctr, Vector3(0, 0, 1), prof, [P_EXHAUST, P_EXHAUST, P_DARK, P_DARK], [0.0, 0.5, 1.0, 1.0, 1.0], 18 if hi else 8)
		_k.anchors["tail"] = ctr


# ------------------------------------------------------------------ wings
func _build_wings(mb: MeshBuilder) -> void:
	var cat: String = spec.category
	var semi: float = _W.semi
	var kink: float = _W.kink
	var jets := cat in ["narrowbody", "widebody", "cargo", "regional", "bizjet"]
	var slats := hi and cat in ["narrowbody", "widebody", "cargo", "regional"]
	var spoil := hi and bool(spec.spoilers)
	var xh := 0.72
	var xsl := 0.11
	var s_fus := _rw * (1.0 if spec.wing_pos == "low" else 0.75)
	var flap_end := semi * (0.74 if jets else 0.62)
	var ail_end := semi * (0.95 if jets else 0.93)
	if cat == "trainer":
		flap_end = semi * 0.56
	var rk: float = _W.rake
	var sl0 := s_fus + 0.35
	var sl1 := minf(semi * 0.965, rk)
	var nx := 15 if hi else 6
	var step := 1.2 if hi else 4.5
	var brk := [kink, rk, flap_end, ail_end]
	var wl: String = spec.winglet
	var tip_cap := wl == "none" or wl == "raked"
	var canoes := []
	if jets and cat != "bizjet":
		var fs := [0.15, 0.5, 0.85] if cat != "regional" else [0.2, 0.75]
		var a0 := kink if kink > 0.0 else s_fus
		for f in fs:
			canoes.append(lerpf(a0, flap_end, float(f)))
		if cat in ["widebody", "cargo"]:
			canoes.append(lerpf(s_fus, kink, 0.55))
	var eng_s := []
	if spec.engine_mount == "wing" or spec.engine_mount == "wing_prop":
		for p in FlightModel.engine_positions(spec):
			eng_s.append(absf((p as Vector3).x))
	for i in canoes.size():
		for es in eng_s:
			if absf(float(canoes[i]) - float(es)) < 1.1:
				canoes[i] = float(es) + 1.3
	for side in [-1.0, 1.0]:
		var sn := "R" if side > 0.0 else "L"
		var sflag := 1.0 if side > 0.0 else 0.0
		var o := {"side": sflag}
		# fixed wing box
		if slats:
			_surf(mb, _wsecs(side, _stations(0.0, sl0, step, brk)), 0.0, xh, P_WING, nx, {"side": sflag, "cap1": true})
			_surf(mb, _wsecs(side, _stations(sl0, sl1, step, brk)), xsl, xh, P_WING, nx, o)
			_surf(mb, _wsecs(side, _stations(sl1, semi, step * 0.5, brk)), 0.0, xh, P_WING, nx, {"side": sflag, "cap0": true, "cap1": tip_cap})
			_slat("slat_" + sn, side, sl0, sl1, xsl)
		else:
			_surf(mb, _wsecs(side, _stations(0.0, semi, step, brk)), 0.0, xh, P_WING, nx, {"side": sflag, "cap1": tip_cap})
		# trailing edge: root, flaps, aileron, tip
		_surf(mb, _wsecs(side, [0.0, s_fus]), xh, 1.0, P_WING, 4, {"side": sflag, "cap1": true})
		var fl_stations := []
		if kink > s_fus + 0.5:
			fl_stations = [[s_fus, kink, "flap_in_"], [kink, flap_end, "flap_"]]
		else:
			fl_stations = [[s_fus, flap_end, "flap_"]]
		for fr in fl_stations:
			var a: float = fr[0]
			var b: float = fr[1]
			var extra := _new_mb()
			for cs in canoes:
				var csf: float = cs
				if csf > a + 0.3 and csf < b - 0.3:
					_canoe(mb, extra, side, csf, xh)
			var mid := _wsec(side, (a + b) * 0.5)
			var travel := ((mid.cd as Vector3) * 0.11 - (mid.td as Vector3) * 0.035) * float(mid.c)
			_hinged(String(fr[2]) + sn, _wsecs(side, _stations(a, b, step * 1.5, brk)), xh, 1.0, P_WING, 40.0, true, travel, mb, o, extra)
		var wicks := _new_mb()
		if hi:
			for f in [0.35, 0.7, 0.95]:
				var ws := _wsec(side, lerpf(flap_end, ail_end, f))
				var te := _spt(ws, 1.0, true)
				wicks.add_cylinder(te - (ws.cd as Vector3) * 0.02, te + (ws.cd as Vector3) * 0.22, 0.008, 0.004, 4, _c(P_DARK), false)
		_hinged("aileron_" + sn, _wsecs(side, _stations(flap_end, ail_end, step * 2.0, brk)), xh, 1.0, P_WING, 25.0, true, Vector3.ZERO, mb, o, wicks)
		_surf(mb, _wsecs(side, _stations(ail_end, semi, step * 0.5, brk)), xh, 1.0, P_WING, 4, {"side": sflag, "cap0": true, "cap1": tip_cap})
		if spoil:
			if kink > s_fus + 0.8:
				_spoilers("spoiler_in_" + sn, side, s_fus + 0.25, kink - 0.05, 1)
				_spoilers("spoiler_" + sn, side, kink + 0.05, flap_end * 0.985, 4 if cat != "regional" else 3)
			else:
				_spoilers("spoiler_" + sn, side, s_fus + 0.35, flap_end * 0.985, 3 if cat != "bizjet" else 2)
		# wingtip
		if wl == "sharklet" or wl == "blended":
			_winglet(mb, side, wl)
		elif wl == "none":
			_round_tip(mb, side)
		_k.anchors["wingtip_" + sn] = _spt(_wsec(side, semi), 0.3, true)
		# trainer: lift strut and vortex generators
		if cat == "trainer":
			var a2 := Vector3(side * _rw * 0.9, -_rh * 0.55, _w_le_z(0.0) + _w_chord(0.0) * 0.3)
			var b2 := _spt(_wsec(side, semi * 0.56), 0.3, false)
			_strut(mb, a2, b2, 0.075, 0.03, P_FLAT)
			if hi:
				for k in 12:
					var vs := _wsec(side, lerpf(semi * 0.5, semi * 0.95, float(k) / 11.0))
					var vp := _spt(vs, 0.1, true)
					var bt := Transform3D(Basis(Vector3.UP, 0.25 * side * (1.0 if k % 2 == 0 else -1.0)), vp + (vs.td as Vector3) * 0.012)
					mb.add_box_xf(bt, Vector3(0.004, 0.025, 0.045), _c(P_FLAT))
	# landing light lenses in the wing roots
	var land := []
	for side2 in [-1.0, 1.0]:
		var s_l := s_fus + (0.8 if spec.wing_pos == "low" else 1.6)
		var ls := _wsec(side2, s_l)
		var lp := _spt(ls, 0.06, false) + (ls.td as Vector3) * -0.01
		land.append(lp)
		if hi:
			mb.add_sphere(lp, Vector3(0.14, 0.05, 0.12), 10, 4, _c(P_LENS))
	_k.landing = land


## Leading-edge slat panels (one animated node per side).
func _slat(name: String, side: float, a: float, b: float, xsl: float) -> void:
	var tmp := _new_mb()
	var n_pan := clampi(int((b - a) / 3.2), 3, 6)
	for k in n_pan:
		var sa := lerpf(a, b, float(k) / n_pan) + (0.02 if k > 0 else 0.0)
		var sb := lerpf(a, b, float(k + 1) / n_pan) - (0.02 if k < n_pan - 1 else 0.0)
		_surf(tmp, _wsecs(side, _stations(sa, sb, 1.4, [_W.kink])), 0.0, xsl, P_WING, 8, {"side": 1.0 if side > 0.0 else 0.0, "cap0": true, "cap1": true})
	var s0 := _wsec(side, a)
	var s1 := _wsec(side, b)
	var A := (_spt(s0, xsl, true) + _spt(s0, xsl, false)) * 0.5
	var B := (_spt(s1, xsl, true) + _spt(s1, xsl, false)) * 0.5
	var mid := _wsec(side, (a + b) * 0.5)
	var travel := (-(mid.cd as Vector3) * 0.085 - (mid.td as Vector3) * 0.04) * float(mid.c)
	_add_part("surface", name, A, B, ((s0.td as Vector3) + (s1.td as Vector3)).normalized(), tmp, deg_to_rad(18.0), _spt(mid, 0.0, true), true, travel)


## Spoiler panels: thin plates on the upper skin hinged at 56 % chord.
func _spoilers(name: String, side: float, a: float, b: float, n_pan: int) -> void:
	var tmp := _new_mb()
	var x0 := 0.56
	var x1 := 0.715
	var nx := 5
	for k in n_pan:
		var sa := lerpf(a, b, float(k) / n_pan) + 0.025
		var sb := lerpf(a, b, float(k + 1) / n_pan) - 0.025
		var secs := _wsecs(side, [sa, sb])
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for layer in [0.016, 0.004]:
			pos.clear()
			nrm.clear()
			col.clear()
			uv.clear()
			uv2.clear()
			for s in secs:
				for i in nx:
					var x := lerpf(x0, x1, float(i) / (nx - 1))
					var p := _spt(s, x, true) + (s.td as Vector3) * float(layer)
					pos.append(p)
					nrm.append((s.td as Vector3) * (1.0 if layer > 0.01 else -1.0))
					col.append(_c(P_WING, 1.0, 1.0 if side > 0.0 else 0.0))
					uv.append(Vector2(x, float(s.v)))
					uv2.append(Vector2(p.x, p.z))
			_emit_grid(tmp, 2, nx, pos, nrm, col, uv, uv2)
		# edges
		for s2 in secs:
			var e0 := _spt(s2, x0, true)
			var e1 := _spt(s2, x1, true)
			var td: Vector3 = s2.td
			tmp.add_quad(e0 + td * 0.004, e1 + td * 0.004, e1 + td * 0.016, e0 + td * 0.016, _c(P_WING, 1.0))
	var s0 := _wsec(side, a)
	var s1 := _wsec(side, b)
	var A := _spt(s0, x0, true)
	var B := _spt(s1, x0, true)
	var mid := _wsec(side, (a + b) * 0.5)
	_add_part("surface", name, A, B, ((s0.td as Vector3) + (s1.td as Vector3)).normalized(), tmp, deg_to_rad(50.0), _spt(mid, x1, true), false, Vector3.ZERO)


## Flap track fairing: fixed front half on the wing, rear half (in `rear`) rides on the flap.
func _canoe(front: MeshBuilder, rear: MeshBuilder, side: float, s: float, xh: float) -> void:
	var sec := _wsec(side, s)
	var c: float = sec.c
	var cd: Vector3 = sec.cd
	var td: Vector3 = sec.td
	var sd := td.cross(cd).normalized()
	var prof := [[0.38, 0.005, 0.006], [0.44, 0.026, 0.035], [0.54, 0.037, 0.065], [0.65, 0.042, 0.088], [xh, 0.043, 0.098],
		[0.86, 0.042, 0.104], [1.0, 0.037, 0.092], [1.12, 0.028, 0.066], [1.24, 0.015, 0.037], [1.32, 0.004, 0.012]]
	var n := 12 if hi else 6
	var rings_f := []
	var cen_f := []
	var rings_r := []
	var cen_r := []
	var te := _spt(sec, 1.0, false)
	for pr in prof:
		var x: float = pr[0]
		var w: float = float(pr[1]) * c
		var d: float = float(pr[2]) * c
		var base := _spt(sec, minf(x, 1.0), false)
		if x > 1.0:
			base = te + cd * ((x - 1.0) * c) + td * ((x - 1.0) * c * 0.12)
		var ctr := base - td * (d * 0.45)
		var ring := PackedVector3Array()
		for k in n:
			var a := TAU * float(k) / n
			ring.append(ctr + sd * (w * sin(a)) + td * (cos(a) * (d * 0.55 if cos(a) < 0.0 else d * 0.75)))
		if x <= xh + 0.001:
			rings_f.append(ring)
			cen_f.append(ctr)
		if x >= xh - 0.001:
			rings_r.append(ring)
			cen_r.append(ctr)
	var target := rear if hi else front
	_loft_rings(front, rings_f, cen_f, P_WING, [], false, false, 0.0, 1.0 if side > 0.0 else 0.0)
	_loft_rings(target, rings_r, cen_r, P_WING, [], false, true, 0.0, 1.0 if side > 0.0 else 0.0)


func _winglet(mb: MeshBuilder, side: float, kind: String) -> void:
	var semi: float = _W.semi
	var tip := _wsec(side, semi)
	var ct: float = tip.c
	var shark := kind == "sharklet"
	var h := ct * (1.45 if shark else 0.95)
	var rb := ct * (0.32 if shark else 0.55)
	var cant := deg_to_rad(8.0 if shark else 16.0)
	var phi_max := PI * 0.5 - cant
	var arc_len := rb * phi_max
	var total := arc_len + maxf(h - rb, 0.2)
	var n := 12 if hi else 4
	var secs := []
	var le0: Vector3 = tip.le
	for i in n + 1:
		var u := float(i) / n
		var a := u * total
		var lat: float
		var vert: float
		var phi: float
		if a <= arc_len:
			phi = a / rb
			lat = rb * sin(phi)
			vert = rb * (1.0 - cos(phi))
		else:
			phi = phi_max
			var d := a - arc_len
			lat = rb * sin(phi_max) + d * cos(phi_max)
			vert = rb * (1.0 - cos(phi_max)) + d * sin(phi_max)
		var c := ct * lerpf(1.0, 0.36 if shark else 0.42, pow(u, 0.85))
		var sweep_z := vert * (1.05 if shark else 0.8) + (ct - c) * 0.35
		var le := le0 + Vector3(side * lat, vert, sweep_z)
		var T := Vector3(side * cos(phi), sin(phi), 0.0)
		var cd := Vector3(0, 0, 1)
		var td := cd.cross(T).normalized() * side
		secs.append(_sec(le, cd, td, c, lerpf(float(tip.tc), 0.08, u), u, 0.0))
	var sf := 1.0 if side > 0.0 else 0.0
	_surf(mb, secs, 0.0, 1.0, P_WINGLET, 10 if hi else 5, {"side": sf, "cap1": true, "uv2": "zy"})
	if hi:
		var top: Dictionary = secs[n - 1]
		var te := _spt(top, 1.0, true)
		mb.add_cylinder(te - Vector3(0, 0, 0.02), te + Vector3(0, -0.05, 0.22), 0.008, 0.004, 4, _c(P_DARK), false)


## Rounded wingtip closing a plain wing.
func _round_tip(mb: MeshBuilder, side: float) -> void:
	var semi: float = _W.semi
	var base := _wsec(side, semi)
	var secs := [base]
	var ct: float = base.c
	for f in [0.35, 0.7, 0.92]:
		var s := base.duplicate()
		var off := ct * 0.05 * float(f)
		s["le"] = (base.le as Vector3) + Vector3(side * off, -off * 0.25, ct * 0.04 * float(f) * float(f))
		s["tc"] = float(base.tc) * sqrt(1.0 - float(f) * float(f))
		s["c"] = ct * (1.0 - 0.08 * float(f) * float(f))
		secs.append(s)
	_surf(mb, secs, 0.0, 1.0, P_WING, 10 if hi else 5, {"side": 1.0 if side > 0.0 else 0.0, "cap1": true})


## Streamlined strut between two points.
func _strut(mb: MeshBuilder, a: Vector3, b: Vector3, chord: float, thick: float, part: int) -> void:
	var ax := (b - a).normalized()
	var fwd := Vector3(0, 0, -1)
	fwd = (fwd - ax * fwd.dot(ax)).normalized()
	var lat := ax.cross(fwd).normalized()
	var rings := []
	var cens := []
	var n := 10 if hi else 6
	for e in [a, b]:
		var ring := PackedVector3Array()
		for k in n:
			var t := TAU * float(k) / n
			ring.append((e as Vector3) + fwd * (cos(t) * chord * 0.5) + lat * (sin(t) * thick * 0.5 * (1.0 if cos(t) > 0.0 else 0.8)))
		rings.append(ring)
		cens.append(e)
	_loft_rings(mb, rings, cens, part, [], true, true)


# ------------------------------------------------------------------ tail
func _build_tail(mb: MeshBuilder) -> void:
	var b: float = spec.span
	var cat: String = spec.category
	var t_tail: bool = spec.tail == "t_tail"
	var L := body_len
	var tail_z := cg_z + L * (0.86 if cat != "trainer" else 0.82)
	var fin_h := b * (0.19 if not t_tail else 0.2)
	if cat == "trainer":
		fin_h = 1.5
	elif cat in ["widebody", "cargo"]:
		fin_h = b * 0.17
	var fin_cr := fin_h * (1.15 if not t_tail else 1.0)
	var fin_ct := fin_cr * (0.42 if not t_tail else 0.7)
	var slope := tan(deg_to_rad(38.0 if cat != "trainer" else 30.0))
	var fz := tail_z - fin_cr * 0.62
	var y_root := INF
	for f in [0.0, 0.35, 0.7, 1.0]:
		var t := clampf((fz + fin_cr * float(f) - cg_z) / L, 0.0, 1.0)
		var sp := section(spec, t)
		y_root = minf(y_root, sp.w + _rh * sp.y)
	var fy := y_root - 0.03
	var nf := 8 if hi else 3
	var fin_secs := func(h0: float, h1: float, n: int) -> Array:
		var out := []
		for i in n + 1:
			var s := lerpf(h0, h1, float(i) / n)
			var c := lerpf(fin_cr, fin_ct, clampf(s / fin_h, 0.0, 1.0))
			out.append(_sec(Vector3(0, fy + s, fz + s * slope), Vector3(0, 0, 1), Vector3(1, 0, 0), c,
				lerpf(0.115, 0.09, clampf(s / fin_h, 0.0, 1.0)), clampf(s / fin_h, 0.0, 1.0), 0.0))
		return out
	var fo := {"uv2": "zy", "side_from_upper": true}
	var sub := -0.25 * _rh
	_surf(mb, fin_secs.call(sub, fin_h, nf), 0.0, 0.72, P_TAIL, 12 if hi else 5, {"uv2": "zy", "side_from_upper": true, "cap1": true})
	_surf(mb, fin_secs.call(sub, fin_h * 0.05, 1), 0.72, 1.0, P_TAIL, 4, {"uv2": "zy", "side_from_upper": true, "cap1": true})
	_surf(mb, fin_secs.call(fin_h * 0.97, fin_h, 1), 0.72, 1.0, P_TAIL, 4, {"uv2": "zy", "side_from_upper": true, "cap0": true, "cap1": true})
	var rwick := _new_mb()
	if hi:
		for f in [0.45, 0.8]:
			var rs: Dictionary = (fin_secs.call(fin_h * float(f), fin_h, 1) as Array)[0]
			var te := _spt(rs, 1.0, true)
			rwick.add_cylinder(te - Vector3(0, 0, 0.02), te + Vector3(0, -0.06, 0.25), 0.008, 0.004, 4, _c(P_DARK), false)
	_hinged("rudder", fin_secs.call(fin_h * 0.05, fin_h * 0.97, 3 if hi else 1), 0.72, 1.0, P_TAIL, 25.0, true, Vector3.ZERO, mb, fo, rwick)
	# dorsal fillet
	if cat != "trainer" and cat != "cargo":
		var dl := fin_cr * (0.55 if cat == "turboprop" else 0.32)
		var dh := fin_h * (0.24 if cat == "turboprop" else 0.16)
		var ds := []
		for i in 4:
			var f := float(i) / 3.0
			var s := lerpf(sub, dh, f)
			var le_z := lerpf(fz - dl, fz + dh * slope, pow(f, 0.7))
			var c := lerpf(dl + fin_cr * 0.3, fin_cr * 0.2, f)
			ds.append(_sec(Vector3(0, fy + s, le_z), Vector3(0, 0, 1), Vector3(1, 0, 0), c, lerpf(0.06, 0.12, f), clampf(s / fin_h, 0.0, 1.0), 0.0))
		_surf(mb, ds, 0.0, 1.0, P_TAIL, 8 if hi else 4, {"uv2": "zy", "side_from_upper": true})
	# fin art placement for the shader
	var mid_c := lerpf(fin_cr, fin_ct, 0.5)
	_k.shader["logo_xf"] = Vector4(fz + fin_h * 0.5 * slope + mid_c * 0.47, fy + fin_h * 0.52, 0.42 * minf(fin_h, mid_c * 1.15), 0.0)
	_k.shader["fin_geo"] = Vector4(fz, fy, fin_h, slope)
	_k.shader["fin_chord"] = Vector2(fin_cr, fin_ct)
	_k.anchors["fin_top"] = Vector3(0, fy + fin_h, fz + fin_h * slope + fin_ct * 0.5)
	# horizontal stabiliser
	var hs_semi := b * (0.17 if cat != "trainer" else 0.3)
	var hs_cr := hs_semi * (0.75 if cat != "trainer" else 0.55)
	var hs_ct := hs_cr * 0.42
	var hs_root: Vector3
	if t_tail:
		hs_root = Vector3(0, fy + fin_h - 0.04, fz + fin_h * slope + fin_ct * 0.12)
		var bl := fin_ct * 1.25
		var br := fin_ct * 0.1
		var prof := [Vector2(0.0, 0.0), Vector2(0.06 * bl, br * 0.55), Vector2(0.22 * bl, br * 0.92), Vector2(0.45 * bl, br),
			Vector2(0.78 * bl, br * 0.8), Vector2(bl, br * 0.15), Vector2(bl * 1.01, 0.0)]
		_revolve(mb, hs_root + Vector3(0, 0.02, -bl * 0.18), Vector3(0, 0, 1), prof, [P_TAIL], [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.0], 16 if hi else 8, 1.0)
	else:
		hs_root = Vector3(0, _rh * 0.12, tail_z - hs_cr * 0.35)
	var hsweep := tan(deg_to_rad(float(spec.sweep) + 6.0))
	var hdih := deg_to_rad(4.5 if not t_tail else -2.0)
	for side in [-1.0, 1.0]:
		var sn := "R" if side > 0.0 else "L"
		var sf := 1.0 if side > 0.0 else 0.0
		var hs := func(a: float, bb: float, n: int) -> Array:
			var out := []
			for i in n + 1:
				var s := lerpf(a, bb, float(i) / n)
				var td := Vector3(-side * sin(hdih), cos(hdih), 0.0)
				out.append(_sec(hs_root + Vector3(side * s, s * tan(hdih), s * hsweep), Vector3(0, 0, 1), td,
					lerpf(hs_cr, hs_ct, s / hs_semi), lerpf(0.11, 0.09, s / hs_semi), s / hs_semi, 0.0))
			return out
		var so := {"side": sf}
		_surf(mb, hs.call(0.0, hs_semi, 5 if hi else 2), 0.0, 0.7, P_STAB, 11 if hi else 5, {"side": sf, "cap1": true})
		_surf(mb, hs.call(0.0, hs_semi * 0.08, 1), 0.7, 1.0, P_STAB, 4, {"side": sf, "cap1": true})
		_surf(mb, hs.call(hs_semi * 0.97, hs_semi, 1), 0.7, 1.0, P_STAB, 4, {"side": sf, "cap0": true, "cap1": true})
		var ew := _new_mb()
		if hi:
			for f in [0.6, 0.9]:
				var es: Dictionary = (hs.call(hs_semi * float(f), hs_semi, 1) as Array)[0]
				var te := _spt(es, 1.0, true)
				ew.add_cylinder(te - Vector3(0, 0, 0.02), te + Vector3(0, 0, 0.22), 0.007, 0.004, 4, _c(P_DARK), false)
		_hinged("elevator_" + sn, hs.call(hs_semi * 0.08, hs_semi * 0.97, 2 if hi else 1), 0.7, 1.0, P_STAB, 25.0, true, Vector3.ZERO, mb, so, ew)
		_k.anchors["stab_tip_" + sn] = hs_root + Vector3(side * hs_semi, hs_semi * tan(hdih), hs_semi * hsweep)


# ------------------------------------------------------------------ engines
func _build_engines(mb: MeshBuilder) -> void:
	var positions := FlightModel.engine_positions(spec)
	var et: String = spec.engine_type
	for i in positions.size():
		var p: Vector3 = positions[i]
		if et == "turbofan":
			_turbofan(mb, p, i)
		elif et == "turboprop":
			_turboprop(mb, p, i)
		else:
			_piston(mb, p, i)


func _turbofan(mb: MeshBuilder, p: Vector3, idx: int) -> void:
	var D: float = spec.get("fan_diam", 1.8)
	var rear: bool = spec.engine_mount == "rear"
	var cat: String = spec.category
	var segs := 40 if hi else 14
	var Ln := D * (1.95 if rear else 1.55)
	var Rm := D * (0.56 if rear else 0.57)
	var Rh := D * 0.53
	var Rf := D * 0.5
	var xf := D * 0.3
	var ax := Vector3(0, 0, 1)
	var o: Vector3
	var side := signf(p.x)
	var wsec := {}
	if rear:
		o = Vector3(p.x, p.y, p.z - Ln * 0.5)
	else:
		wsec = _wsec(side, absf(p.x))
		var le: Vector3 = wsec.le
		var y_low := _spt(wsec, 0.08, false).y
		var y_ax := y_low - 0.11 * D - Rm
		y_ax = maxf(y_ax, -float(spec.gear_height) + 0.42 + Rm)
		o = Vector3(p.x, y_ax, le.z - Ln - 0.04 * D)
	_k.anchors["engine_%d" % idx] = o
	_k.anchors["engine_d_%d" % idx] = D
	# nacelle: inlet duct, polished lip, cowl (split for the reverser sleeve on the full model)
	var x_tr := Ln * 0.56
	var outer := [
		Vector2(xf - 0.01 * D, Rf * 1.004), Vector2(xf * 0.45, Rf * 1.012), Vector2(0.06 * D, 0.497 * D),
		Vector2(0.02 * D, 0.506 * D), Vector2(0.0, Rh), Vector2(0.012 * D, Rh + 0.018 * D),
		Vector2(0.05 * D, Rh + 0.03 * D), Vector2(0.13 * D, Rm * 0.985), Vector2(0.32 * D, Rm),
		Vector2(x_tr, Rm * 0.99)]
	var parts := [P_INLET, P_INLET, P_LIP, P_LIP, P_LIP, P_LIP, P_NACELLE, P_NACELLE, P_NACELLE]
	var vs := [1.0, 0.6, 0.15, 0.0, 0.0, 0.01, 0.03, 0.08, 0.2, 0.56]
	var aft := [Vector2(x_tr, Rm * 0.99), Vector2(0.8 * Ln, Rm * 0.94), Vector2(Ln, 0.48 * D),
		Vector2(Ln - 0.008 * D, 0.466 * D), Vector2(Ln - 0.4 * D, 0.47 * D)]
	var aft_parts := [P_NACELLE, P_NACELLE, P_DARK, P_DARK]
	var aft_vs := [0.56, 0.8, 1.0, 1.0, 1.0]
	if rear:
		aft = [Vector2(x_tr, Rm * 0.99), Vector2(0.82 * Ln, Rm * 0.9), Vector2(Ln, 0.42 * D),
			Vector2(Ln - 0.008 * D, 0.405 * D), Vector2(Ln - 0.5 * D, 0.42 * D)]
	if hi and bool(spec.reverser):
		_revolve(mb, o, ax, outer + [Vector2(x_tr, Rm * 0.955), Vector2(x_tr + 0.32 * D, Rm * 0.955)],
			parts + [P_DARK, P_DARK], vs + [0.56, 0.6], segs)
		var sleeve := _new_mb()
		_revolve(sleeve, o, ax, [Vector2(x_tr + 0.004 * D, Rm * 0.955)] + aft, [P_NACELLE] + aft_parts, [0.56] + aft_vs, segs)
		_k.parts.append({"kind": "reverser", "name": "Reverser%d" % idx, "engine": idx, "xf": Transform3D.IDENTITY,
			"mesh": sleeve.commit(), "sign": 1.0, "max": 0.0, "travel": ax * (0.3 * D)})
	else:
		aft.remove_at(0)
		_revolve(mb, o, ax, outer + aft, parts + aft_parts, vs + aft_vs.slice(1), segs)
	# fan exit (dark) and core cowl, nozzle and plug
	_revolve(mb, o, ax, [Vector2(xf + 0.16 * D, 0.0), Vector2(xf + 0.16 * D, Rf)], [P_DARK], [0.0, 1.0], segs)
	if rear:
		_revolve(mb, o, ax, [Vector2(Ln - 0.45 * D, 0.26 * D), Vector2(Ln - 0.1 * D, 0.25 * D), Vector2(Ln + 0.12 * D, 0.17 * D),
			Vector2(Ln + 0.3 * D, 0.06 * D), Vector2(Ln + 0.33 * D, 0.0)], [P_PLUG], [0.0, 0.3, 0.6, 0.9, 1.0], segs / 2 + 4)
	else:
		_revolve(mb, o, ax, [Vector2(Ln - 0.45 * D, 0.385 * D), Vector2(Ln, 0.368 * D), Vector2(Ln + 0.2 * D, 0.33 * D),
			Vector2(Ln + 0.42 * D, 0.255 * D), Vector2(Ln + 0.41 * D, 0.238 * D), Vector2(Ln + 0.2 * D, 0.232 * D)],
			[P_EXHAUST, P_EXHAUST, P_EXHAUST, P_DARK, P_DARK], [0.0, 0.3, 0.6, 1.0, 1.0, 1.0], segs)
		_revolve(mb, o, ax, [Vector2(Ln + 0.25 * D, 0.21 * D), Vector2(Ln + 0.42 * D, 0.2 * D), Vector2(Ln + 0.62 * D, 0.13 * D),
			Vector2(Ln + 0.8 * D, 0.04 * D), Vector2(Ln + 0.84 * D, 0.0)], [P_PLUG], [0.0, 0.3, 0.6, 0.9, 1.0], segs / 2 + 4)
	# pylon
	if rear:
		var fz_c := o.z + Ln * 0.42
		var root_x := side * _hw(fz_c, p.y) * 0.85
		var tip_x := o.x - side * Rm * 0.7
		var secs := []
		for f in [0.0, 1.0]:
			var x := lerpf(root_x, tip_x, f)
			var c := Ln * lerpf(0.62, 0.48, f)
			secs.append(_sec(Vector3(x, p.y, fz_c - c * 0.35 + f * c * 0.08), Vector3(0, 0, 1), Vector3(0, 1, 0), c, 0.14, f, 0.0))
		_surf(mb, secs, 0.0, 1.0, P_PYLON, 8 if hi else 4, {"uv2": "xz"})
	else:
		_pylon(mb, o, D, Ln, Rm, wsec)
	# rotor: spinner and fan blades
	var rmb := _new_mb()
	var sp := [Vector2(-0.27 * D, 0.0), Vector2(-0.25 * D, 0.03 * D), Vector2(-0.19 * D, 0.08 * D), Vector2(-0.11 * D, 0.125 * D),
		Vector2(-0.03 * D, 0.158 * D), Vector2(0.03 * D, 0.172 * D), Vector2(0.07 * D, 0.172 * D)]
	_revolve(rmb, Vector3.ZERO, ax, sp, [P_SPINNER], [0.0, 0.1, 0.3, 0.55, 0.8, 0.94, 1.0], 28 if hi else 10)
	var nb := 18
	if cat in ["widebody", "cargo"]:
		nb = 22
	elif cat in ["regional", "bizjet"]:
		nb = 24
	if not hi:
		nb = 10
	_fan_blades(rmb, D, nb)
	_k.engines.append({"pos": o + ax * xf, "mesh": rmb.commit(), "blades": null, "disc": 0.0, "nb": nb})


## Wide-chord twisted fan blades in the rotor frame (fan plane at z = 0).
func _fan_blades(mb: MeshBuilder, D: float, nb: int) -> void:
	var r0 := 0.16 * D
	var r1 := 0.495 * D
	var ns := 5 if hi else 2
	var nc := 4 if hi else 2
	for k in nb:
		var a := TAU * float(k) / nb
		var rad := Vector3(sin(a), cos(a), 0.0)
		var tang := Vector3(cos(a), -sin(a), 0.0)
		var pos := PackedVector3Array()
		var hint := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var cols := nc * 2 + 1
		for i in ns + 1:
			var f := float(i) / ns
			var r := lerpf(r0, r1, f)
			var chord := D * lerpf(0.13, 0.19, f)
			var phi := deg_to_rad(lerpf(58.0, 30.0, pow(f, 0.8)))
			var cdir := (tang * cos(phi) + Vector3(0, 0, 1) * sin(phi)).normalized()
			var ndir := cdir.cross(rad).normalized()
			var th := D * lerpf(0.012, 0.004, f)
			var ctr := rad * r + Vector3(0, 0, 0.02 * D) - tang * (0.03 * D * f * f)
			for j in cols:
				var u := float(j) / (cols - 1)
				var x: float
				var s: float
				if j <= nc:
					x = float(j) / nc
					s = 1.0
				else:
					x = 1.0 - float(j - nc) / nc
					s = -1.0
				var t := th * sin(PI * clampf(x, 0.0, 1.0)) * 0.5 + 0.0005
				var pp := ctr + cdir * ((x - 0.5) * chord) + ndir * (s * t + 0.012 * D * sin(PI * x))
				pos.append(pp)
				hint.append(ndir * s)
				col.append(_c(P_FAN))
				uv.append(Vector2(x, f))
				uv2.append(Vector2(u, f))
		var nrm := _grid_normals(ns + 1, cols, pos, hint, false)
		_emit_grid(mb, ns + 1, cols, pos, nrm, col, uv, uv2)


func _pylon(mb: MeshBuilder, o: Vector3, D: float, Ln: float, Rm: float, wsec: Dictionary) -> void:
	var le: Vector3 = wsec.le
	var c: float = wsec.c
	var z_a := o.z + 0.2 * Ln
	var z_end := le.z + c * 1.02
	var n := 14 if hi else 6
	var rings := []
	var cens := []
	var vs := []
	var m := 12 if hi else 6
	var hw0 := 0.11 * D
	for i in n + 1:
		var f := float(i) / n
		var z := lerpf(z_a, z_end, f)
		var xw := clampf((z - le.z) / c, 0.0, 1.0)
		var y_wing := _spt(wsec, xw, false).y + 0.12
		if z < le.z:
			y_wing = lerpf(o.y + Rm + 0.25 * D, _spt(wsec, 0.0, false).y + 0.1, U.smooth01((z - z_a) / maxf(le.z - z_a, 0.1)))
		var xa := z - o.z
		var y_bot: float
		if xa < Ln:
			y_bot = o.y + Rm * lerpf(0.97, 0.9, clampf(xa / Ln, 0.0, 1.0)) - 0.04 * D
		elif xa < Ln + 0.42 * D:
			y_bot = o.y + lerpf(0.37, 0.27, (xa - Ln) / (0.42 * D)) * D
		else:
			y_bot = lerpf(o.y + 0.27 * D, y_wing - 0.05 * D, U.smooth01((xa - Ln - 0.42 * D) / maxf(z_end - o.z - Ln - 0.42 * D, 0.1)))
		var y_top := maxf(y_wing, y_bot + 0.06)
		var hw := hw0 * U.smooth01(f / 0.12 + 0.15) * lerpf(1.0, 0.25, U.smooth01((f - 0.7) / 0.3))
		var ctr := Vector3(o.x, (y_top + y_bot) * 0.5, z)
		var hh := (y_top - y_bot) * 0.5
		var ring := PackedVector3Array()
		for k in m:
			var a := TAU * float(k) / m
			var sx := signf(sin(a)) * pow(absf(sin(a)), 0.5)
			var sy := signf(cos(a)) * pow(absf(cos(a)), 0.5)
			ring.append(ctr + Vector3(sx * hw, sy * hh, 0.0))
		rings.append(ring)
		cens.append(ctr)
		vs.append(f)
	_loft_rings(mb, rings, cens, P_PYLON, vs, true, true)


func _turboprop(mb: MeshBuilder, p: Vector3, idx: int) -> void:
	var D: float = spec.get("prop_diam", 3.9)
	var side := signf(p.x)
	var wsec := _wsec(side, absf(p.x))
	var le: Vector3 = wsec.le
	var c: float = wsec.c
	var y_ax := le.y - 0.62
	var z_prop := le.z - D * 0.5
	var stations := [
		[z_prop + 0.08, 0.27, 0.27, 0.29], [z_prop + 0.35, 0.38, 0.38, 0.47], [z_prop + 0.9, 0.46, 0.5, 0.62],
		[le.z - 0.2, 0.5, 0.75, 0.68], [le.z + c * 0.4, 0.5, 0.9, 0.64], [le.z + c * 0.85, 0.42, 0.9, 0.48],
		[le.z + c * 1.15, 0.26, 0.85, 0.28], [le.z + c * 1.38, 0.04, 0.8, 0.05]]
	var m := 18 if hi else 8
	var rings := []
	var cens := []
	var vs := []
	for i in stations.size():
		var st: Array = stations[i]
		var z: float = st[0]
		var w: float = st[1]
		var up: float = st[2]
		var dn: float = st[3]
		var ring := PackedVector3Array()
		var ctr := Vector3(p.x, y_ax, z)
		for k in m:
			var a := TAU * float(k) / m
			var sx := signf(sin(a)) * pow(absf(sin(a)), 0.8)
			var cy := cos(a)
			var sy := signf(cy) * pow(absf(cy), 0.8)
			ring.append(ctr + Vector3(sx * w, sy * (up if cy > 0.0 else dn), 0.0))
		rings.append(ring)
		cens.append(ctr + Vector3(0, (up - dn) * 0.25, 0))
		vs.append(float(i) / (stations.size() - 1))
	_loft_rings(mb, rings, cens, P_NACELLE, vs, true, true)
	# chin intake and exhaust
	mb.add_rounded_box(Vector3(p.x, y_ax - 0.5, z_prop + 0.62), Vector3(0.36, 0.14, 0.42), _c(P_DARK), 0.4, 10, 6)
	var ex0 := Vector3(p.x + side * 0.44, y_ax + 0.02, le.z + c * 0.2)
	mb.add_cylinder(ex0 - Vector3(side * 0.12, 0, 0.1), ex0 + Vector3(side * 0.08, -0.02, 0.32), 0.13, 0.12, 10 if hi else 6, _c(P_EXHAUST), false)
	mb.add_cylinder(ex0 + Vector3(side * 0.08, -0.02, 0.32), ex0 + Vector3(side * 0.02, -0.02, 0.1), 0.115, 0.115, 10 if hi else 6, _c(P_DARK), true)
	_k.anchors["engine_%d" % idx] = Vector3(p.x, y_ax, z_prop)
	_k.anchors["engine_d_%d" % idx] = D * 0.3
	# propeller: spinner (rotor) and blades
	var rmb := _new_mb()
	var spn := [Vector2(-0.62, 0.0), Vector2(-0.58, 0.06), Vector2(-0.46, 0.15), Vector2(-0.28, 0.23), Vector2(-0.08, 0.27), Vector2(0.06, 0.275), Vector2(0.08, 0.0)]
	_revolve(rmb, Vector3.ZERO, Vector3(0, 0, 1), spn, [P_GEAR], [0.0, 0.1, 0.3, 0.6, 0.85, 1.0, 1.0], 24 if hi else 10)
	var bmb := _new_mb()
	_prop_blades(bmb, D, 6, 0.24, -0.15)
	_k.engines.append({"pos": Vector3(p.x, y_ax, z_prop), "mesh": rmb.commit(), "blades": bmb.commit(), "disc": D, "nb": 6})


## Propeller blades in the hub frame (disc at z = z0): twisted, tapered and swept-back tips.
func _prop_blades(mb: MeshBuilder, D: float, nb: int, r_hub: float, z0: float) -> void:
	var R := D * 0.5
	var ns := 7 if hi else 3
	var nc := 5 if hi else 2
	for k in nb:
		var a := TAU * float(k) / nb
		var rad := Vector3(sin(a), cos(a), 0.0)
		var tang := Vector3(cos(a), -sin(a), 0.0)
		var pos := PackedVector3Array()
		var hint := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var cols := nc * 2 + 1
		for i in ns + 1:
			var f := float(i) / ns
			var r := lerpf(r_hub, R, f)
			var chord := R * (0.07 + 0.09 * sin(PI * minf(f * 1.25, 1.0)) * (1.0 - 0.75 * pow(f, 6.0))) + 0.012
			var pitch := deg_to_rad(lerpf(48.0, 14.0, f))
			var cdir := (tang * cos(pitch) + Vector3(0, 0, 1) * sin(pitch)).normalized()
			var ndir := cdir.cross(rad).normalized()
			var th := chord * lerpf(0.16, 0.06, f)
			var ctr := rad * r + Vector3(0, 0, z0) - tang * (R * 0.08 * f * f)
			for j in cols:
				var x: float
				var s: float
				if j <= nc:
					x = float(j) / nc
					s = 1.0
				else:
					x = 1.0 - float(j - nc) / nc
					s = -1.0
				var t := th * sin(PI * clampf(x * 0.85 + 0.15 * x * x, 0.0, 1.0)) * 0.5 + 0.0008
				var pp := ctr + cdir * ((x - 0.35) * chord) + ndir * (s * t)
				pos.append(pp)
				hint.append(ndir * s)
				col.append(_c(P_PROP))
				uv.append(Vector2(x, f))
				uv2.append(Vector2(x, f))
		var nrm := _grid_normals(ns + 1, cols, pos, hint, false)
		_emit_grid(mb, ns + 1, cols, pos, nrm, col, uv, uv2)


func _piston(mb: MeshBuilder, p: Vector3, idx: int) -> void:
	var D: float = spec.get("prop_diam", 1.9)
	var hub := Vector3(0, -0.04, cg_z - 0.06)
	# cowling intakes either side of the spinner and the exhaust stub
	for sx in [-1.0, 1.0]:
		mb.add_rounded_box(Vector3(sx * 0.17, -0.06, cg_z + 0.06), Vector3(0.16, 0.12, 0.08), _c(P_DARK), 0.4, 8, 6)
	mb.add_cylinder(Vector3(0.12, -_rh * 0.62, cg_z + 0.75), Vector3(0.14, -_rh * 0.7, cg_z + 1.05), 0.035, 0.03, 8, _c(P_EXHAUST), true)
	_k.anchors["engine_%d" % idx] = hub
	_k.anchors["engine_d_%d" % idx] = 0.6
	var rmb := _new_mb()
	var spn := [Vector2(-0.36, 0.0), Vector2(-0.33, 0.05), Vector2(-0.24, 0.11), Vector2(-0.12, 0.155), Vector2(0.0, 0.17), Vector2(0.03, 0.17), Vector2(0.04, 0.0)]
	_revolve(rmb, Vector3.ZERO, Vector3(0, 0, 1), spn, [P_FLAT], [0.0, 0.15, 0.4, 0.7, 0.95, 1.0, 1.0], 22 if hi else 10)
	var bmb := _new_mb()
	_prop_blades(bmb, D, 2, 0.12, -0.08)
	_k.engines.append({"pos": hub, "mesh": rmb.commit(), "blades": bmb.commit(), "disc": D, "nb": 2})


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
func _build_gear(mb: MeshBuilder) -> void:
	var gh: float = spec.gear_height
	var cat: String = spec.category
	var wr := 0.3 if cat == "trainer" else clampf(gh * 0.2, 0.35, 0.68)
	var retract: bool = spec.gear_retract
	var bogie := cat in ["widebody", "cargo"]
	var mz: float = spec.main_gear_x
	var tr: float = spec.gear_track
	var nz: float = spec.nose_gear_x
	var tn := clampf((nz - cg_z) / body_len, 0.0, 1.0)
	var spn := section(spec, tn)
	var y_nose := spn.w - _rh * spn.z + 0.3
	_gear_leg(mb, {"nose": true, "x": 0.0, "z": nz, "y": y_nose, "src": 0, "wr": wr * (0.62 if cat != "trainer" else 0.85),
		"twin": cat != "trainer", "bogie": false, "axis": Vector3.RIGHT, "angle": PI * 0.5, "retract": retract})
	for side in [-1.0, 1.0]:
		var x: float = float(side) * tr * 0.5
		var y: float
		if spec.wing_pos == "low":
			var ws := _wsec(side, absf(x))
			y = (ws.le as Vector3).y + 0.02
		elif cat == "turboprop":
			y = -_rh * 0.5
		else:
			y = -_rh * 0.62
		_gear_leg(mb, {"nose": false, "x": x, "z": mz, "y": y, "src": 1 if side < 0.0 else 2, "wr": wr, "twin": cat != "trainer",
			"bogie": bogie, "axis": Vector3(0, 0, -side), "angle": PI * 0.5, "retract": retract})
	if cat == "cargo":
		for side in [-1.0, 1.0]:
			_gear_leg(mb, {"nose": false, "x": side * 1.95, "z": mz + 3.4, "y": -_rh * 0.82, "src": 1 if side < 0.0 else 2, "wr": wr,
				"twin": true, "bogie": true, "axis": Vector3.RIGHT, "angle": -PI * 0.5, "retract": retract, "body": true})


func _wheel_mesh(wr: float, tw: float) -> ArrayMesh:
	var key := "%.3f:%.3f" % [wr, tw]
	if _k.wheels.has(key):
		return _k.wheels[key]
	var wmb := _new_mb()
	_wheel_into(wmb, Vector3.ZERO, wr, tw)
	var m := wmb.commit()
	_k.wheels[key] = m
	return m


## Tyre (rounded shoulders, tread) and a wheel with a dished hub on each face; axle along X.
func _wheel_into(mb: MeshBuilder, c: Vector3, wr: float, tw: float) -> void:
	var segs := 30 if hi else 12
	var h := tw * 0.5
	var rr := wr * 0.56
	var prof := [Vector2(-h * 0.86, rr), Vector2(-h * 0.98, rr + (wr - rr) * 0.25), Vector2(-h, rr + (wr - rr) * 0.55),
		Vector2(-h * 0.93, wr * 0.95), Vector2(-h * 0.7, wr * 0.995), Vector2(0.0, wr), Vector2(h * 0.7, wr * 0.995),
		Vector2(h * 0.93, wr * 0.95), Vector2(h, rr + (wr - rr) * 0.55), Vector2(h * 0.98, rr + (wr - rr) * 0.25), Vector2(h * 0.86, rr)]
	_revolve(mb, c, Vector3.RIGHT, prof, [P_TYRE], [0.0, 0.08, 0.16, 0.28, 0.36, 0.5, 0.64, 0.72, 0.84, 0.92, 1.0], segs)
	for s in [-1.0, 1.0]:
		var hp := [Vector2(h * 0.86, rr), Vector2(h * 0.8, rr * 0.93), Vector2(h * 0.55, rr * 0.82), Vector2(h * 0.5, rr * 0.4),
			Vector2(h * 0.62, rr * 0.3), Vector2(h * 0.64, 0.0)]
		var hpp := []
		for q in hp:
			hpp.append(Vector2((q as Vector2).x * s, (q as Vector2).y))
		_revolve(mb, c, Vector3.RIGHT, hpp, [P_HUB, P_HUB, P_HUB, P_DARK if s < 0.0 else P_HUB, P_HUB], [0.0, 0.2, 0.4, 0.6, 0.8, 1.0], segs / 2 + 2)
		if hi:
			for k in 8:
				var a := TAU * float(k) / 8.0
				var bp := c + Vector3(s * h * 0.5, cos(a) * rr * 0.62, sin(a) * rr * 0.62)
				mb.add_cylinder(bp, bp + Vector3(s * 0.025, 0, 0), 0.018, 0.018, 6, _c(P_METAL), true)


func _gear_leg(mb: MeshBuilder, g: Dictionary) -> void:
	var gh: float = spec.gear_height
	var cat: String = spec.category
	var nose: bool = g.nose
	var wr: float = g.wr
	var tw := wr * (0.7 if not nose else 0.6)
	if cat == "trainer":
		tw = wr * 0.55
	var top_y: float = g.y
	var leg := top_y + gh - wr
	var piv := Vector3(g.x, top_y, g.z)
	var side := signf(float(g.x))
	var rc := clampf(0.045 * gh, 0.05, 0.24) * (0.78 if nose else 1.0)
	var stroke := clampf(0.12 * gh, 0.15, 0.55) * (0.8 if nose else 1.0)
	var lmb := _new_mb()
	var smb := _new_mb()
	var seg := 14 if hi else 7
	var bogie: bool = g.bogie
	var twin: bool = g.twin
	var off := rc * 0.85 + tw * 0.5 + 0.05
	if bogie:
		off = rc * 0.9 + tw * 0.5 + 0.08
	var wheels := []
	var wb := wr * 2.25
	if cat == "trainer":
		# spring steel legs (mains) or a short oleo (nose); spats over the wheels
		if not nose:
			var foot := Vector3(-side * 0.0, -leg, 0.0)
			var root := Vector3(-side * (absf(float(g.x)) - _rw * 0.8), 0.0, 0.0)
			lmb.add_cylinder(root, foot + Vector3(-side * 0.04, 0.05, 0), 0.045, 0.03, 6, _c(P_FLAT), true)
		else:
			lmb.add_cylinder(Vector3(0, 0.05, 0), Vector3(0, -leg + stroke, 0), rc, rc, seg, _c(P_GEAR), true)
			smb.add_cylinder(Vector3(0, stroke + 0.2, 0), Vector3(0, 0.05, 0), rc * 0.7, rc * 0.7, seg, _c(P_CHROME), false)
		smb.add_sphere(Vector3(0, 0.03, 0.04), Vector3(tw * 0.75, wr * 0.88, wr * 1.75), 14 if hi else 8, 7 if hi else 4, _c(P_FLAT))
		wheels.append(Vector3.ZERO)
	else:
		# oleo: painted cylinder with gland nut, chrome piston on the sliding part
		lmb.add_cylinder(Vector3(0, 0.12, 0), Vector3(0, -leg + stroke, 0), rc, rc, seg, _c(P_GEAR), true)
		lmb.add_cylinder(Vector3(0, -leg + stroke + 0.04, 0), Vector3(0, -leg + stroke - 0.02, 0), rc * 1.1, rc * 1.1, seg, _c(P_METAL), true)
		smb.add_cylinder(Vector3(0, stroke + 0.25, 0), Vector3(0, 0.12, 0), rc * 0.72, rc * 0.72, seg, _c(P_CHROME), false)
		# trunnion at the top
		if nose:
			lmb.add_cylinder(Vector3(-rc * 2.2, 0.02, 0), Vector3(rc * 2.2, 0.02, 0), rc * 0.55, rc * 0.55, 8, _c(P_GEAR), true)
		else:
			lmb.add_cylinder(Vector3(0, 0.02, -rc * 2.5), Vector3(0, 0.02, rc * 2.5), rc * 0.6, rc * 0.6, 8, _c(P_GEAR), true)
		# bracing: drag brace forward (nose) or folding side brace inboard (mains)
		if nose:
			var k0 := Vector3(0, -leg * 0.42, -rc)
			var k1 := Vector3(0, -leg * 0.05, -leg * 0.62)
			lmb.add_cylinder(k0, k0.lerp(k1, 0.5) + Vector3(0, -0.06, 0), rc * 0.36, rc * 0.36, 6, _c(P_GEAR), true)
			lmb.add_cylinder(k0.lerp(k1, 0.5) + Vector3(0, -0.06, 0), k1, rc * 0.36, rc * 0.36, 6, _c(P_GEAR), true)
		else:
			var inb := -side
			var k0 := Vector3(inb * rc, -leg * 0.38, 0.0)
			var k1 := Vector3(inb * leg * 0.62, -0.05, 0.12)
			var knee := k0.lerp(k1, 0.5) + Vector3(0, -0.12, 0.05)
			lmb.add_cylinder(k0, knee, rc * 0.38, rc * 0.38, 6, _c(P_GEAR), true)
			lmb.add_cylinder(knee, k1, rc * 0.38, rc * 0.38, 6, _c(P_GEAR), true)
			if hi:
				lmb.add_sphere(knee, Vector3.ONE * rc * 0.5, 8, 4, _c(P_METAL))
			# leg door on the outboard side
			if bool(g.retract) and not bool(g.get("body", false)):
				var dh := leg * 0.66
				lmb.add_box(Vector3(side * (rc + 0.06), -dh * 0.5 + 0.05, 0.0), Vector3(0.035, dh, rc * 5.0), _c(P_BELLY))
		# torque links (scissors) on the front of the oleo
		var lz := -rc - 0.02
		var tl0 := Vector3(0, -leg + stroke + 0.02, lz)
		var tl1 := Vector3(0, -leg + stroke * 0.5 + 0.04, lz - 0.16 - rc)
		lmb.add_cylinder(tl0, tl1, 0.03 + rc * 0.12, 0.03 + rc * 0.12, 5, _c(P_GEAR), true)
		smb.add_cylinder(Vector3(0, stroke * 0.5 + 0.04, lz - 0.16 - rc), Vector3(0, 0.15, lz), 0.03 + rc * 0.12, 0.03 + rc * 0.12, 5, _c(P_GEAR), true)
		if hi:
			# hydraulic lines down the leg
			lmb.add_cylinder(Vector3(rc * 0.9, 0.0, rc * 0.5), Vector3(rc * 0.95, -leg + stroke + 0.1, rc * 0.5), 0.012, 0.012, 4, _c(P_DARK), false)
			lmb.add_cylinder(Vector3(rc * 0.9, 0.0, rc * 0.2), Vector3(rc * 0.95, -leg + stroke + 0.1, rc * 0.2), 0.01, 0.01, 4, _c(P_DARK), false)
		# axle, bogie
		if bogie:
			smb.add_cylinder(Vector3(0, 0.0, -wb * 0.62), Vector3(0, 0.0, wb * 0.62), rc * 0.55, rc * 0.55, 8, _c(P_GEAR), true)
			smb.add_box(Vector3(0, 0.08, 0), Vector3(rc * 1.4, rc * 1.2, rc * 2.0), _c(P_GEAR))
			for az in [-wb * 0.5, wb * 0.5]:
				smb.add_cylinder(Vector3(-off - tw * 0.3, 0, az), Vector3(off + tw * 0.3, 0, az), rc * 0.3, rc * 0.3, 8, _c(P_METAL), false)
				for sx in [-1.0, 1.0]:
					wheels.append(Vector3(sx * off, 0.0, az))
			if hi:
				smb.add_cylinder(Vector3(0, 0.35, -rc), Vector3(0, 0.06, -wb * 0.45), rc * 0.22, rc * 0.18, 6, _c(P_GEAR), true)
		elif twin:
			smb.add_box(Vector3(0, 0.0, 0), Vector3(rc * 1.6, rc * 1.3, rc * 1.5), _c(P_GEAR))
			smb.add_cylinder(Vector3(-off - tw * 0.3, 0, 0), Vector3(off + tw * 0.3, 0, 0), rc * 0.32, rc * 0.32, 8, _c(P_METAL), false)
			wheels.append(Vector3(-off, 0, 0))
			wheels.append(Vector3(off, 0, 0))
		else:
			wheels.append(Vector3.ZERO)
		if nose and hi:
			# steering actuators and the taxi / turn-off light bar
			smb.add_cylinder(Vector3(-rc * 1.3, stroke + 0.1, -rc * 0.4), Vector3(rc * 1.3, stroke + 0.1, -rc * 0.4), rc * 0.25, rc * 0.25, 6, _c(P_METAL), true)
			lmb.add_box(Vector3(0, -leg * 0.55, -rc - 0.08), Vector3(rc * 2.6, 0.1, 0.12), _c(P_GEAR))
			for lx in [-rc * 0.8, 0.0, rc * 0.8]:
				lmb.add_cylinder(Vector3(lx, -leg * 0.55, -rc - 0.14), Vector3(lx, -leg * 0.55, -rc - 0.16), 0.06, 0.06, 10, _c(P_LENS), true)
	# brakes inside each wheel
	var wl := []
	if hi:
		var wmesh := _wheel_mesh(wr, tw)
		for wp in wheels:
			wl.append({"pos": wp, "mesh": wmesh})
			if cat != "trainer" and not nose:
				var inn := -signf((wp as Vector3).x) if absf((wp as Vector3).x) > 0.01 else -1.0
				smb.add_cylinder((wp as Vector3) + Vector3(inn * tw * 0.12, 0, 0), (wp as Vector3) + Vector3(inn * tw * 0.42, 0, 0), wr * 0.42, wr * 0.42, 12, _c(P_DARK), true)
	else:
		for wp in wheels:
			_wheel_into(smb, wp, wr, tw)
	var ext_axis: Vector3 = g.axis
	_k.gear.append({"pos": piv, "axis": ext_axis, "angle": float(g.angle), "leg": leg, "radius": wr, "retract": bool(g.retract),
		"src": int(g.src), "nose": nose, "leg_mesh": lmb.commit(), "slider_mesh": smb.commit(), "wheels": wl})
	var gname := "nose_gear" if nose else ("main_gear_%s" % ("R" if side > 0.0 else "L"))
	if g.get("body", false):
		gname = "body_gear_%s" % ("R" if side > 0.0 else "L")
	_k.anchors[gname] = piv + Vector3(0, -leg, 0)
	# nose bay doors (open while the gear is down)
	if nose and bool(g.retract):
		var bay_w := (off + tw * 0.5 + 0.1 if twin else rc + tw + 0.1) * 0.62
		var dl := (leg + wr * 1.1) * 0.45
		for sx in [-1.0, 1.0]:
			var hinge := Vector3(sx * bay_w, top_y - 0.28, float(g.z) + dl * 0.5 - 0.1)
			var dmb := _new_mb()
			dmb.add_box(Vector3(-sx * bay_w * 0.5, 0.0, 0.0), Vector3(bay_w, 0.04, dl), _c(P_BELLY))
			_k.gear_doors.append({"xf": Transform3D(Basis.IDENTITY, hinge), "mesh": dmb.commit(), "axis": Vector3(0, 0, 1),
				"angle": sx * PI * 0.5, "src": 0})


# ------------------------------------------------------------------ doors
func _build_doors() -> void:
	var d: Array = spec.doors
	var lay := CabinLayout.get_layout(_type_id)
	var floor_y: float = lay.floor_y
	var dz := cg_z + float(d[0]) * body_len
	_k.door_l1 = Vector3(-_rw, _rh * 0.05, dz)
	if d.is_empty() or spec.category == "trainer":
		return
	var w := 0.95 if spec.category != "bizjet" else 0.85
	var h := 1.88
	var y0 := floor_y + 0.03
	# curved plug door panel in the hinge frame (hinge at the forward edge, outside the skin)
	var hz := dz - w * 0.5 - 0.03
	var hx := -_hw(dz, y0 + h * 0.5) - 0.03
	var hinge := Vector3(hx, y0 + h * 0.5, hz)
	var dmb := _new_mb()
	var nz := 6
	var ny := 8
	for layer in [0.0, -0.09]:
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for i in ny + 1:
			var y := y0 + h * float(i) / ny
			for j in nz + 1:
				var z := dz - w * 0.5 - 0.02 + (w + 0.04) * float(j) / nz
				var x := -_hw(z, y) - 0.012
				var n := Vector3(x / (_rw * _rw), (y - 0.0) / (_rh * _rh), 0.0).normalized()
				var p := Vector3(x, y, z) + n * (-float(layer))
				pos.append(p - hinge)
				nrm.append(n if layer == 0.0 else -n)
				col.append(_c(P_FLAT if layer == 0.0 else P_GEAR))
				uv.append(Vector2(float(j) / nz, float(i) / ny))
				uv2.append(Vector2(z, y))
		_emit_grid(dmb, ny + 1, nz + 1, pos, nrm, col, uv, uv2)
	_k.doors.append({"name": "L1", "xf": Transform3D(Basis.IDENTITY, hinge), "mesh": dmb.commit(), "axis": Vector3.UP,
		"angle": -1.9, "kind": "plug", "w": w})
	if bool(spec.hump) and bool(spec.cargo_door):
		var tn := _nose_frac(spec)
		_k.doors.append({"name": "NOSE", "xf": Transform3D(Basis.IDENTITY, Vector3(0, _rh * 0.9, cg_z + body_len * tn * 0.95)),
			"mesh": null, "axis": Vector3.RIGHT, "angle": 1.2, "kind": "hinge", "w": 0.0})


func set_door(name: String, open_frac: float) -> void:
	if doors.has(name):
		doors[name].open = clampf(open_frac, 0.0, 1.0)


# ------------------------------------------------------------------ details
func _build_details(fmb: MeshBuilder, amb: MeshBuilder, panes: Array) -> void:
	if not hi:
		return
	var cat: String = spec.category
	var lay := CabinLayout.get_layout(_type_id)
	var ck: Dictionary = lay.cockpit
	var ez: float = ck.eye_z
	var ey: float = ck.eye_y
	# windscreen wipers resting along the bottom of the front panes
	if cat != "trainer" and panes.size() > 0:
		var fp: Array = panes[0]
		for sx in [-1.0, 1.0]:
			var c0: Vector3 = fp[0]
			var c1: Vector3 = fp[1]
			var c3: Vector3 = fp[3]
			c0.x *= sx
			c1.x *= sx
			c3.x *= sx
			var upv := (c3 - c0).normalized()
			var n := (c1 - c0).cross(c3 - c0).normalized()
			if n.dot(Vector3(c0.x, c0.y, 0.0)) < 0.0 and n.z > 0.0:
				n = -n
			if n.z > 0.0:
				n = -n
			var a := c0.lerp(c1, 0.14) + upv * 0.05 + n * 0.02
			var b := c0.lerp(c1, 0.8) + upv * 0.09 + n * 0.02
			var dirv := (b - a).normalized()
			var bas := Basis(dirv, n.cross(dirv).normalized(), n)
			fmb.add_box_xf(Transform3D(bas, (a + b) * 0.5), Vector3((b - a).length(), 0.025, 0.018), _c(P_DARK))
			fmb.add_cylinder(a - n * 0.015, a + n * 0.03, 0.025, 0.02, 8, _c(P_DARK), true)
	# pitot probes, AoA vanes and the TAT probe on the nose
	if cat != "trainer":
		for sx in [-1.0, 1.0]:
			for k in 2:
				var pz := ez - 1.0 + k * 0.32
				var py := ey - 0.62 - k * 0.12
				var base := _skin_at_z(pz, py)
				base.x *= sx
				var outv := Vector3(sx, 0.15, 0.0).normalized()
				var tip := base + outv * 0.1
				fmb.add_cylinder(base - outv * 0.02, tip, 0.03, 0.018, 6, _c(P_METAL), true)
				fmb.add_cylinder(tip, tip + Vector3(0, 0, -0.2), 0.012, 0.01, 6, _c(P_METAL), true)
			var vb := _skin_at_z(ez - 1.55, ey - 0.9)
			vb.x *= sx
			var vdir := Vector3(sx, 0, 0)
			var vbas := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
			fmb.add_box_xf(Transform3D(vbas, vb + vdir * 0.06 + Vector3(0, 0, 0.03)), Vector3(0.12, 0.08, 0.012), _c(P_METAL))
			fmb.add_cylinder(vb - vdir * 0.01, vb + vdir * 0.015, 0.05, 0.05, 10, _c(P_METAL), true)
	# antennas: blades on the crown and belly, a satcom fairing on long-haul types
	if cat != "trainer":
		var ants := [[0.28, 1.0, 0.36], [0.47, 1.0, 0.26], [0.22, -1.0, 0.3], [0.62, -1.0, 0.24]]
		for a in ants:
			var t: float = a[0]
			var dirn: float = a[1]
			var hgt: float = float(a[2]) * clampf(_rh / 2.0, 0.6, 1.3)
			var sp := section(spec, t)
			var y := sp.w + (_rh * sp.y if dirn > 0.0 else -_rh * sp.z)
			var z := cg_z + t * body_len
			if dirn < 0.0 and not _bulges.is_empty():
				y = _fpt(sp, t, PI).y
			var secs := []
			for i in 2:
				var f := float(i)
				secs.append(_sec(Vector3(0, y + dirn * (f * hgt - 0.03), z + f * hgt * 0.9), Vector3(0, 0, 1), Vector3(1, 0, 0),
					lerpf(hgt * 1.1, hgt * 0.45, f), 0.12, f, 0.0))
			_surf(fmb, secs, 0.0, 1.0, P_FLAT if dirn > 0.0 else P_BELLY, 6, {"cap1": true, "uv2": "zy"})
		if cat in ["widebody", "cargo"]:
			var t2 := 0.42
			var sp2 := section(spec, t2)
			fmb.add_sphere(Vector3(0, sp2.w + _rh * sp2.y - 0.05, cg_z + t2 * body_len), Vector3(0.55, 0.2, 1.4), 16, 6, _c(P_FLAT))
	# trainer: door handles, step and the GA wing root fairing
	if cat == "trainer":
		for sx in [-1.0, 1.0]:
			var st := Vector3(sx * (_rw + 0.08), -_rh * 0.78, ez + 0.25)
			fmb.add_cylinder(st - Vector3(sx * 0.1, -0.05, 0), st, 0.015, 0.015, 6, _c(P_METAL), true)
			fmb.add_box(st + Vector3(sx * 0.02, 0, 0), Vector3(0.12, 0.012, 0.09), _c(P_METAL))


func _build_light_defs(fmb: MeshBuilder, amb: MeshBuilder) -> void:
	var semi: float = _W.semi
	var cat: String = spec.category
	var tips := {}
	for side in [-1.0, 1.0]:
		var ts := _wsec(side, semi * (0.985 if spec.winglet != "raked" else 0.96))
		var p_front := _spt(ts, 0.06, false) + Vector3(side * 0.05, -0.02, 0.0)
		var p_back := _spt(ts, 0.92, true) + Vector3(side * 0.05, 0.0, 0.0)
		tips[side] = [p_front, p_back]
		if hi:
			amb.add_sphere(p_front, Vector3(0.09, 0.05, 0.13), 10, 5, _c(P_LENS, 0.3 if side < 0.0 else 0.55))
			amb.add_sphere(p_back, Vector3(0.05, 0.04, 0.08), 8, 4, _c(P_LENS))
	var L: Array = _k.lights
	L.append({"name": "nav_r", "color": Color(0.1, 1.0, 0.25), "pattern": 0, "phase": 0.0, "size": 0.25, "pos": tips[1.0][0] + Vector3(0.05, 0, 0), "aim": Vector3.FORWARD})
	L.append({"name": "nav_l", "color": Color(1.0, 0.08, 0.05), "pattern": 0, "phase": 0.0, "size": 0.25, "pos": tips[-1.0][0] - Vector3(0.05, 0, 0), "aim": Vector3.FORWARD})
	L.append({"name": "strobe_r", "color": Color(1, 1, 1), "pattern": 1, "phase": 0.0, "size": 0.35, "pos": tips[1.0][1], "aim": Vector3.FORWARD})
	L.append({"name": "strobe_l", "color": Color(1, 1, 1), "pattern": 1, "phase": 0.0, "size": 0.35, "pos": tips[-1.0][1], "aim": Vector3.FORWARD})
	var tail: Vector3 = _k.anchors.get("tail", Vector3(0, _rh * 0.5, cg_z + body_len * 0.995))
	if cat == "trainer":
		tail = _k.anchors.get("fin_top", tail) + Vector3(0, -0.15, 0.1)
	L.append({"name": "nav_tail", "color": Color(1, 1, 1), "pattern": 0, "phase": 0.0, "size": 0.2, "pos": tail + Vector3(0, 0.12, 0.06), "aim": Vector3.BACK})
	L.append({"name": "strobe_tail", "color": Color(1, 1, 1), "pattern": 1, "phase": 0.5, "size": 0.3, "pos": tail + Vector3(0, 0.22, 0.1), "aim": Vector3.BACK})
	# beacons on the crown and belly
	var tb := clampf((_w_le_z(0.0) + _w_chord(0.0) * 0.4 - cg_z) / body_len, 0.2, 0.7)
	var sp := section(spec, tb)
	var zb := cg_z + tb * body_len
	var top := Vector3(0, sp.w + _rh * sp.y, zb)
	var bot := _fpt(sp, tb, PI) if not _bulges.is_empty() else Vector3(0, sp.w - _rh * sp.z, zb)
	if cat == "trainer":
		top = _k.anchors.get("fin_top", top) + Vector3(0, 0.05, -0.05)
	if hi:
		fmb.add_sphere(top, Vector3(0.1, 0.07, 0.16), 10, 5, _c(P_LENS, 0.3))
		if cat != "trainer":
			fmb.add_sphere(bot, Vector3(0.1, 0.07, 0.16), 10, 5, _c(P_LENS, 0.3))
	L.append({"name": "beacon_top", "color": Color(1, 0.1, 0.05), "pattern": 2, "phase": 0.0, "size": 0.3, "pos": top + Vector3(0, 0.08, 0), "aim": Vector3.UP})
	L.append({"name": "beacon_bot", "color": Color(1, 0.1, 0.05), "pattern": 2, "phase": 0.5, "size": 0.3, "pos": bot - Vector3(0, 0.08, 0), "aim": Vector3.DOWN})
	# landing lights (wing roots), taxi light (nose gear), wing scan lights (fuselage sides)
	var land: Array = _k.landing
	for i in land.size():
		L.append({"name": "landing_%s" % ("l" if i == 0 else "r"), "color": Color(1.0, 0.96, 0.88), "pattern": 3, "phase": 0.0,
			"size": 0.45, "pos": land[i] + Vector3(0, -0.05, -0.1), "aim": Vector3.FORWARD})
	if not _k.gear.is_empty():
		var ng: Dictionary = _k.gear[0]
		var leg: float = ng.leg
		var rc := clampf(0.045 * float(spec.gear_height), 0.05, 0.24) * 0.78
		L.append({"name": "taxi", "color": Color(1.0, 0.96, 0.88), "pattern": 3, "phase": 0.0, "size": 0.35,
			"pos": Vector3(0, -leg * 0.55, -rc - 0.22), "aim": Vector3.FORWARD, "gear": 0})
	if cat != "trainer" and cat != "turboprop":
		for side in [-1.0, 1.0]:
			var wz := _w_le_z(_rw) - 1.2
			var wy := float(_W.y0) + 1.0
			var wp := _skin_at_z(wz, wy)
			wp.x *= side
			L.append({"name": "wing_%s" % ("l" if side < 0.0 else "r"), "color": Color(1.0, 0.95, 0.85), "pattern": 3, "phase": 0.0,
				"size": 0.18, "pos": wp + Vector3(side * 0.05, 0, 0), "aim": Vector3(side, -0.2, 0.3).normalized()})
			if hi:
				fmb.add_sphere(wp, Vector3(0.04, 0.06, 0.08), 8, 4, _c(P_LENS))


# ------------------------------------------------------------------ flight deck glazing and paint geometry
## Flight deck window outlines on the right side (the shader mirrors them): [c0, c1, c2, c3, radius].
func _cockpit_panes() -> Array:
	var cat: String = spec.category
	var lay := CabinLayout.get_layout(_type_id)
	var ck: Dictionary = lay.cockpit
	var ez: float = ck.eye_z
	var ey: float = ck.eye_y
	var z_lo := cg_z + 0.02
	var z_hi := ez + 2.0
	var out := []
	if cat == "trainer":
		var yb := ey - 0.3
		var yt := ey + 0.24
		var w0 := _skin_at_x(-0.03, yb, z_lo, z_hi)
		var w1 := _skin_at_x(0.43, yb, z_lo, z_hi)
		var w2 := _skin_at_x(0.4, yt, z_lo, z_hi)
		var w3 := _skin_at_x(-0.03, yt, z_lo, z_hi)
		out.append([w0, w1, w2, w3, 0.08])
		var za := maxf(w1.z, w2.z) + 0.1
		out.append([_skin_at_z(za, ey - 0.26), _skin_at_z(ez + 0.5, ey - 0.26), _skin_at_z(ez + 0.5, ey + 0.2), _skin_at_z(za + 0.12, ey + 0.2), 0.08])
		out.append([_skin_at_z(ez + 0.6, ey - 0.22), _skin_at_z(ez + 1.25, ey - 0.12), _skin_at_z(ez + 1.25, ey + 0.08), _skin_at_z(ez + 0.6, ey + 0.17), 0.1])
		return out
	var s := clampf(_rw / 1.98, 0.75, 1.25)
	var fb := ey - 0.24
	var ft := ey + 0.3
	var xi := 0.055
	var xob := 0.76 * s
	var xot := 0.62 * s
	if cat == "bizjet":
		fb = ey - 0.2
		xob = 0.64
		xot = 0.5
	elif cat in ["turboprop", "regional"]:
		xob = 0.7 * s
		xot = 0.56 * s
	var c0 := _skin_at_x(xi, fb, z_lo, z_hi)
	var c1 := _skin_at_x(xob, fb, z_lo, z_hi)
	var c2 := _skin_at_x(xot, ft, z_lo, z_hi)
	var c3 := _skin_at_x(xi, ft, z_lo, z_hi)
	out.append([c0, c1, c2, c3, 0.05])
	var post := 0.1
	var sb := fb + 0.01
	var stp := ft - 0.03
	var z_a_b := c1.z + post
	var z_a_t := c2.z + post
	var z_b := ez + (0.12 if cat != "bizjet" else 0.3)
	var stp2 := minf(stp, _crown_y(z_b) - 0.14)
	out.append([_skin_at_z(z_a_b, sb), _skin_at_z(z_b, sb), _skin_at_z(z_b, stp2), _skin_at_z(z_a_t, minf(stp, _crown_y(z_a_t) - 0.12)), 0.06])
	var z_c := z_b + post
	var z_d := z_c + (0.52 if cat != "bizjet" else 0.7)
	var b2 := sb + (0.03 if cat != "bizjet" else 0.0)
	var t2 := minf(stp2 - 0.02, _crown_y(z_c) - 0.16)
	var t3 := minf(stp2 - (0.16 if cat != "bizjet" else 0.06), _crown_y(z_d) - 0.18)
	out.append([_skin_at_z(z_c, b2), _skin_at_z(z_d, b2 + 0.04), _skin_at_z(z_d, t3), _skin_at_z(z_c, t2), 0.08 if cat != "bizjet" else 0.14])
	return out


func _crown_y(z: float) -> float:
	var t := clampf((z - cg_z) / body_len, 0.0, 1.0)
	var sp := section(spec, t)
	return sp.w + _rh * sp.y


static func _line_x(p: Vector2, d: Vector2, q: Vector2, e: Vector2) -> Vector2:
	var den := d.cross(e)
	if absf(den) < 1e-9:
		return p
	return p + d * ((q - p).cross(e) / den)


static func _inset_quad(q: Array, r: float) -> Array:
	var area := 0.0
	for i in 4:
		area += (q[i] as Vector2).cross(q[(i + 1) % 4])
	var sgn := 1.0 if area > 0.0 else -1.0
	var lines := []
	for i in 4:
		var a: Vector2 = q[i]
		var b: Vector2 = q[(i + 1) % 4]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * sgn
		lines.append([a + n * r, d])
	var out := []
	for i in 4:
		var l0: Array = lines[(i + 3) % 4]
		var l1: Array = lines[i]
		out.append(_line_x(l0[0], l0[1], l1[0], l1[1]))
	return out


func _shader_geometry(panes: Array) -> void:
	var sh: Dictionary = _k.shader
	var cat: String = spec.category
	var lay := CabinLayout.get_layout(_type_id)
	var floor_y: float = lay.floor_y
	var ck: Dictionary = lay.cockpit
	var ez: float = ck.eye_z
	var ey: float = ck.eye_y
	sh["fuse_rw"] = _rw
	sh["fuse_rh"] = _rh
	sh["nose_z"] = cg_z
	sh["fuse_len"] = body_len
	sh["floor_y"] = floor_y
	# passenger windows: same stations and size as the cabin's window cut-outs
	var wins: Array = lay.windows
	var win_h := 0.34 if cat != "widebody" else 0.42
	var win_w := 0.23 if cat != "widebody" else 0.27
	if cat == "bizjet":
		win_h = 0.42
		win_w = 0.34
	var pitch := 0.53 if cat != "bizjet" else 1.1
	var wy := floor_y + 1.02
	var wr := Vector2(1e4, -1e4)
	if wins.size() > 0:
		wr = Vector2(float(wins[0]), float(wins[wins.size() - 1]))
	elif cat == "cargo":
		wr = Vector2(ez + 2.4, ez + 2.4 + pitch * 3.0)
	if cat == "trainer":
		pitch = 0.0
	sh["win"] = Vector4(wy, win_h * 0.5 + 0.012, win_w * 0.5 + 0.01, pitch)
	sh["win_range"] = wr
	sh["win_shape"] = 2.0 if cat == "bizjet" else 2.7
	sh["win_hn"] = wy / _rh
	if cat == "cargo":
		sh["win_hn"] = 0.1
	elif cat == "trainer":
		sh["win_hn"] = 0.0
	var dz := Vector4(-1e4, -1e4, -1e4, -1e4)
	var dw := Vector4(0.5, 0.5, 0.5, 0.5)
	var ez4 := Vector4(-1e4, -1e4, -1e4, -1e4)
	var nd := 0
	var ne := 0
	if cat != "trainer":
		for d in lay.doors:
			if int(d.side) > 0:
				continue
			if String(d.kind) == "door" and nd < 4:
				dz[nd] = float(d.z)
				dw[nd] = float(d.width) * 0.5
				nd += 1
			elif String(d.kind) == "overwing" and ne < 4:
				ez4[ne] = float(d.z)
				ne += 1
	sh["door_z"] = dz
	sh["door_w"] = dw
	sh["door_h"] = 1.88
	sh["exit_z"] = ez4
	var cz := Vector4(-1e4, -1e4, -1e4, -1e4)
	var cw := Vector4(0.9, 0.9, 0.9, 0.9)
	var chh := 1.25
	var nzz := cg_z
	match cat:
		"narrowbody":
			cz = Vector4(nzz + body_len * 0.27, nzz + body_len * 0.66, -1e4, -1e4)
		"widebody":
			cz = Vector4(nzz + body_len * 0.235, nzz + body_len * 0.7, -1e4, -1e4)
			cw = Vector4(1.35, 1.35, 0.5, 0.5)
			chh = 1.7
		"cargo":
			cz = Vector4(nzz + body_len * 0.25, nzz + body_len * 0.67, -1e4, -1e4)
			cw = Vector4(1.35, 1.35, 0.5, 0.5)
			chh = 1.7
		"regional":
			cz = Vector4(nzz + body_len * 0.25, nzz + body_len * 0.68, -1e4, -1e4)
			cw = Vector4(0.55, 0.55, 0.5, 0.5)
			chh = 0.9
	sh["cargo_z"] = cz
	sh["cargo_w"] = cw
	sh["cargo_h"] = chh
	sh["main_door"] = Vector4(nzz + body_len * 0.79, 1.7, 1.55, -_rh * 0.12) if cat == "cargo" else Vector4(-1e4, 1.7, 1.6, 0.0)
	sh["nose_door"] = (nzz + body_len * 0.115) if (cat == "cargo" and bool(spec.cargo_door)) else -1e4
	sh["static_port"] = Vector2(ez + 1.45, ey - 0.7) if cat != "trainer" else Vector2(-1e4, 0.0)
	sh["boots"] = 1.0 if cat == "turboprop" else 0.0
	sh["wing_body"] = 1.0 if cat == "trainer" else 0.0
	# flight deck panes
	var po := PackedVector3Array()
	var pu := PackedVector3Array()
	var pv := PackedVector3Array()
	var pa := []
	var pb := []
	var pr := PackedFloat32Array()
	var zmax := -1e4
	for pane in panes:
		var cs := [pane[0], pane[1], pane[2], pane[3]]
		var o := Vector3.ZERO
		for c in cs:
			o += c as Vector3
			zmax = maxf(zmax, (c as Vector3).z)
		o /= 4.0
		var n := ((cs[2] as Vector3) - (cs[0] as Vector3)).cross((cs[3] as Vector3) - (cs[1] as Vector3)).normalized()
		var sp := section(spec, clampf((o.z - cg_z) / body_len, 0.0, 1.0))
		if n.dot(o - Vector3(0, sp.w, o.z)) < 0.0:
			n = -n
		var u := (cs[1] as Vector3) - (cs[0] as Vector3)
		u = (u - n * u.dot(n)).normalized()
		var v := n.cross(u).normalized()
		var q2 := []
		for c in cs:
			var d := (c as Vector3) - o
			q2.append(Vector2(d.dot(u), d.dot(v)))
		var r: float = pane[4]
		var ins := _inset_quad(q2, r)
		po.append(o)
		pu.append(u)
		pv.append(v)
		pa.append(Vector4((ins[0] as Vector2).x, (ins[0] as Vector2).y, (ins[1] as Vector2).x, (ins[1] as Vector2).y))
		pb.append(Vector4((ins[2] as Vector2).x, (ins[2] as Vector2).y, (ins[3] as Vector2).x, (ins[3] as Vector2).y))
		pr.append(r)
	sh["pane_count"] = po.size()
	while po.size() < 5:
		po.append(Vector3.ZERO)
		pu.append(Vector3.RIGHT)
		pv.append(Vector3.UP)
		pa.append(Vector4.ZERO)
		pb.append(Vector4.ZERO)
		pr.append(0.0)
	sh["pane_o"] = po
	sh["pane_u"] = pu
	sh["pane_v"] = pv
	sh["pane_a"] = pa
	sh["pane_b"] = pb
	sh["pane_r"] = pr
	sh["cockpit_z1"] = zmax + 0.4


# ------------------------------------------------------------------ lights
func _sprite(name: String, color: Color, pattern: int, phase: float, size: float, pos: Vector3, aim: Vector3, parent: Node3D) -> MeshInstance3D:
	if _light_mat == null:
		_light_mat = ShaderMaterial.new()
		_light_mat.shader = load("res://shaders/nav_light.gdshader")
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _quad
	mi.material_override = _light_mat
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("pattern", pattern)
	mi.set_instance_shader_parameter("phase", phase)
	mi.set_instance_shader_parameter("size", size)
	mi.set_instance_shader_parameter("aim", aim)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.extra_cull_margin = 8.0
	mi.visible = false
	parent.add_child(mi)
	lights[name] = mi
	return mi


# ------------------------------------------------------------------ titles and registration
static func _title_font(style: String) -> Font:
	if _fonts.has(style):
		return _fonts[style]
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	match style:
		"italic":
			fv.variation_embolden = 0.9
			fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
		"wide":
			fv.variation_embolden = 0.75
			fv.spacing_glyph = 10
		"light":
			fv.variation_embolden = 0.15
			fv.spacing_glyph = 18
		"retro":
			fv.variation_embolden = 1.3
			fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.3, 1), Vector2.ZERO)
			fv.spacing_glyph = 4
		_:
			fv.variation_embolden = 1.0
	_fonts[style] = fv
	return fv


func _label(text: String, font: Font, h: float, color: Color, side: float, z: float, y: float, range_end: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 96
	l.pixel_size = h / (96.0 * 0.72)
	l.modulate = color
	l.shaded = true
	l.double_sided = false
	l.outline_size = 0
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var t := clampf((z - cg_z) / body_len, 0.0, 1.0)
	var sp := section(spec, t)
	var x := _hw(z, y)
	var sy := sp.y if y >= sp.w else sp.z
	var nrm := Vector3(side * x / maxf(_rw * _rw * sp.x * sp.x, 0.01), (y - sp.w) / maxf(_rh * _rh * sy * sy, 0.01), 0.0).normalized()
	var yv := (Vector3.UP - nrm * nrm.y).normalized()
	var xv := yv.cross(nrm)
	l.transform = Transform3D(Basis(xv, yv, nrm), Vector3(side * x, y, z) + nrm * 0.012)
	l.visibility_range_end = range_end
	add_child(l)
	label_nodes.append(l)


func _build_labels(lv: String, reg: String) -> void:
	var colors := Airlines.livery_colors(lv)
	var al := Airlines.get_al(Airlines.base_code(lv))
	var cat: String = spec.category
	var title: String = colors.get("title", "")
	if title == "":
		title = String(al.name).to_upper()
	var style: String = colors.get("title_style", "bold")
	var tsize: float = colors.get("title_size", 1.0)
	var tpos: float = colors.get("title_pos", 0.0)
	var txt: Color = colors.get("text", Color(0.1, 0.2, 0.4))
	var font := _title_font(style)
	var lay := CabinLayout.get_layout(_type_id)
	var floor_y: float = lay.floor_y
	var wy := floor_y + 1.02
	var h := clampf(_rh * 0.27, 0.22, 0.95) * tsize
	var rng := 2500.0 if hi else 900.0
	if cat == "trainer":
		var rz := cg_z + body_len * 0.66
		for side in [-1.0, 1.0]:
			_label(reg, _title_font("bold"), 0.32, txt, side, rz, -0.02, rng)
		return
	var y := wy + 0.19 + 0.12 + h * 0.5
	y = minf(y, _rh * 0.78)
	var zc := cg_z + body_len * (_nose_frac(spec) + 0.2 + tpos)
	if cat in ["widebody", "cargo"]:
		zc = cg_z + body_len * (_nose_frac(spec) + 0.16 + tpos)
	for side in [-1.0, 1.0]:
		_label(title, font, h, txt, side, zc, y, rng)
	if hi and reg != "":
		var rc: Color = colors.get("reg_col", Color(0.16, 0.17, 0.19))
		var rz := cg_z + body_len * (1.0 - _tail_frac(spec) * 0.9)
		var ry := wy + 0.05
		for side in [-1.0, 1.0]:
			_label(reg, _title_font("bold"), clampf(h * 0.42, 0.16, 0.42), rc, side, rz, ry, 800.0)


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
	var flap_deg := _flap_deg(sys.flap_pos)
	for n in ["flap_R", "flap_L", "flap_in_R", "flap_in_L"]:
		_set_surface_deg(n, flap_deg)
	var slat := clampf(sys.flap_pos, 0.0, 1.0)
	_set_surface("slat_R", slat)
	_set_surface("slat_L", slat)
	var air := 0.0 if fdm.on_ground else 1.0
	var spl := sys.spoilers + maxf(fdm.aileron, 0.0) * 0.4 * air
	var spr := sys.spoilers + maxf(-fdm.aileron, 0.0) * 0.4 * air
	_set_surface("spoiler_R", spl)
	_set_surface("spoiler_L", spr)
	_set_surface("spoiler_in_R", sys.spoilers)
	_set_surface("spoiler_in_L", sys.spoilers)
	# gear: retraction, doors, oleo compression, wheel spin and nose wheel steering
	var ws := fdm.wheel_speed if fdm.on_ground else 0.0
	for g in gear:
		var src: int = g.src
		var ext: float = sys.gear_pos[src] if src < sys.gear_pos.size() else 1.0
		if not g.retract:
			ext = 1.0
		var broken: bool = a.damage.gear[src] if src < a.damage.gear.size() else false
		var ang: float = (1.0 - ext) * float(g.angle)
		if broken:
			ang = float(g.angle) * 0.55
		(g.pivot as Node3D).basis = Basis(g.axis, ang)
		(g.pivot as Node3D).visible = ext > 0.02 or broken
		var load: float = fdm.gear_load[src] if src < fdm.gear_load.size() else 0.0
		var comp := clampf(load / maxf(fdm.mass * U.G0, 1.0) * 0.5, 0.0, 0.3)
		(g.wheel_root as Node3D).position.y = -float(g.leg) + comp
		for w in g.wheels:
			(w as Node3D).rotation.x -= ws / float(g.radius) * dt
		if g.steer != null:
			var lim := deg_to_rad(70.0 if fdm.wheel_speed < 8.0 else 8.0)
			(g.steer as Node3D).rotation.y = -fdm.steer * lim * ext
	for gd in gear_doors:
		var src2: int = gd.src
		var ext2: float = sys.gear_pos[src2] if src2 < sys.gear_pos.size() else 1.0
		(gd.pivot as Node3D).basis = (gd.b0 as Basis) * Basis(gd.axis, float(gd.angle) * U.smooth01(ext2 / 0.15))
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
			prop_blades[i].visible = not fast
			prop_discs[i].material_override.set_shader_parameter("rpm_k", clampf(rate / 30.0, 0.0, 1.0))
		if i < reversers.size() and reversers[i] != null:
			var rv: Dictionary = reversers[i]
			(rv.node as Node3D).position = (rv.base as Vector3) + (rv.travel as Vector3) * float(e.get("rev", 0.0))
	_animate_doors(dt)
	# lights
	var L: Dictionary = sys.lights
	var powered := sys.dc_power
	var night: float = a.world.night if a.world else 0.0
	_apply_lights(bool(L.nav) and powered, bool(L.strobe) and powered, bool(L.beacon) and powered,
		bool(L.landing) and powered, bool(L.get("taxi", false)) and powered, bool(L.get("wing", false)) and powered, night)
	_set_inst("cabin_lights", night * (1.0 if L.cabin and powered else 0.0))
	_set_inst("logo_light", night * (1.0 if (bool(L.get("logo", false)) or bool(L.nav)) and powered else 0.0))
	_set_inst("deck_glow", night * (1.0 if powered else 0.0))


## Lightweight animation for AI traffic and replays (no flight model behind the model).
func animate_simple(gear_ext: float, flap_frac: float, fan_rate: float, lit: Dictionary, night: float, dt: float, roll_speed: float = 0.0) -> void:
	var fdeg := _flap_deg(flap_frac)
	for n in ["flap_R", "flap_L", "flap_in_R", "flap_in_L"]:
		_set_surface_deg(n, fdeg)
	_set_surface("slat_R", clampf(flap_frac, 0.0, 1.0))
	_set_surface("slat_L", clampf(flap_frac, 0.0, 1.0))
	for g in gear:
		var ext := gear_ext if g.retract else 1.0
		(g.pivot as Node3D).basis = Basis(g.axis, (1.0 - ext) * float(g.angle))
		(g.pivot as Node3D).visible = ext > 0.02
		for w in g.wheels:
			(w as Node3D).rotation.x -= roll_speed / float(g.radius) * dt
	for gd in gear_doors:
		(gd.pivot as Node3D).basis = (gd.b0 as Basis) * Basis(gd.axis, float(gd.angle) * U.smooth01(gear_ext / 0.15))
	for i in fans.size():
		fan_angle[i] = fmod(fan_angle[i] + fan_rate * dt, TAU)
		fans[i].rotation.z = fan_angle[i]
		if prop_discs[i] != null:
			prop_discs[i].visible = fan_rate > 8.0
			prop_blades[i].visible = fan_rate <= 8.0
	_animate_doors(dt)
	_apply_lights(bool(lit.get("nav", false)), bool(lit.get("strobe", false)), bool(lit.get("beacon", false)),
		bool(lit.get("landing", false)), bool(lit.get("taxi", false)), bool(lit.get("wing", false)), night)
	_set_inst("cabin_lights", night * (1.0 if bool(lit.get("cabin", true)) else 0.0))
	_set_inst("logo_light", night * (1.0 if bool(lit.get("logo", lit.get("nav", false))) else 0.0))
	_set_inst("deck_glow", night)


func _flap_deg(pos: float) -> float:
	var flaps: Array = spec.flaps
	var fi := clampf(pos, 0.0, flaps.size() - 1.0)
	var i0 := int(floor(fi))
	var i1 := mini(i0 + 1, flaps.size() - 1)
	return lerpf(float(flaps[i0].deg), float(flaps[i1].deg), fi - i0)


func _animate_doors(dt: float) -> void:
	for dn in doors.keys():
		var d: Dictionary = doors[dn]
		var cur: float = d.get("cur", 0.0)
		cur = move_toward(cur, float(d.open), dt * 0.35)
		d.cur = cur
		var pv: Node3D = d.pivot
		if String(d.get("kind", "hinge")) == "plug":
			# out of the frame, then swung forward to rest flat against the fuselage
			var t1 := U.smooth01(cur / 0.25)
			var t2 := U.smooth01((cur - 0.2) / 0.8)
			var x0: Transform3D = d.x0
			var w: float = d.w
			var ang := -PI * 0.5 * sin(PI * t2) * 0.35
			pv.transform = Transform3D(Basis(Vector3.UP, ang), x0.origin + Vector3(-0.12 * t1 - 0.32 * sin(PI * t2) * 0.6 - 0.18 * t2, 0, -(w + 0.12) * t2))
			pv.visible = cur > 0.01
		else:
			pv.visible = cur > 0.01 or dn == "NOSE"
			pv.basis = Basis(d.axis, float(d.angle) * cur)
	if doors.has("L1"):
		_set_inst("door_open", U.smooth01(float(doors.L1.cur) / 0.2))


func _apply_lights(nav: bool, strobe: bool, beacon: bool, landing: bool, taxi: bool, wing: bool, night: float) -> void:
	var want := {"nav_r": nav, "nav_l": nav, "nav_tail": nav, "strobe_r": strobe, "strobe_l": strobe, "strobe_tail": strobe,
		"beacon_top": beacon, "beacon_bot": beacon, "landing_l": landing, "landing_r": landing, "taxi": taxi,
		"wing_l": wing, "wing_r": wing}
	var nq := snappedf(night, 0.02)
	var night_changed := float(_inst.get("_night", -1.0)) != nq
	_inst["_night"] = nq
	for k in lights.keys():
		var mi: MeshInstance3D = lights[k]
		var on: bool = want.get(k, false)
		if k == "taxi" and gear.size() > 0:
			on = on and (gear[0].pivot as Node3D).visible
		mi.visible = on
		if night_changed:
			mi.set_instance_shader_parameter("night", nq)
	for sl in landing_lights:
		sl.light_energy = (6.0 if landing else 0.0) * clampf(night * 1.4, 0.0, 1.0)
		sl.visible = sl.light_energy > 0.01


func _set_inst(param: String, v: float) -> void:
	var q := snappedf(v, 0.01)
	if float(_inst.get(param, -1.0)) == q:
		return
	_inst[param] = q
	for mi in _mis:
		(mi as MeshInstance3D).set_instance_shader_parameter(param, q)


func _set_surface(name: String, frac: float) -> void:
	if not surfaces.has(name):
		return
	var s: Dictionary = surfaces[name]
	var f := clampf(frac, -1.0, 1.0)
	var ang := f * float(s.max)
	if absf(ang - float(s.angle)) < 1e-5 and s.has("set"):
		return
	s.angle = ang
	s["set"] = true
	var pv: Node3D = s.pivot
	pv.basis = (s.b0 as Basis) * Basis(Vector3.RIGHT, ang * float(s.sign))
	var tr: Vector3 = s.travel
	if tr != Vector3.ZERO:
		pv.position = (s.o0 as Vector3) + tr * absf(f)


func _set_surface_deg(name: String, deg: float) -> void:
	if not surfaces.has(name):
		return
	var s: Dictionary = surfaces[name]
	_set_surface(name, deg_to_rad(deg) / maxf(float(s.max), 0.001))


func show_exterior_fuselage(show: bool) -> void:
	## From inside, the exterior skin stays visible (seen through the windows, its inner faces
	## are culled) and keeps casting its shadow: the closed skin is what keeps direct sun out of
	## the cabin (the thinner interior shells alone let it leak through). Interiors are lit by
	## their own lights and an interior ambient probe.
	exterior.visible = true
	fuselage_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for l in label_nodes:
		l.visible = show
	for d in doors.values():
		(d.pivot as Node3D).visible = show and float(d.get("cur", d.open)) > 0.01


func door_world_local() -> Vector3:
	return door_l1_local
