class_name CrashDebris
extends RefCounted
## Wreckage pieces shared by the live crash and the news crash site: torn skin panels, cabin
## seats (single and in rows), suitcases and bags (some burst open), overhead bins, insulation,
## wing and tail fragments, engine nacelles, fan discs and wheels. With the optional "graphic
## crash scenes" setting it also adds stylised, bloodless mannequin-like human remains and
## sheet-covered victims. Every piece is built in its own frame so it can be placed loose on the
## ground or flung through the air as a separate body.

const SEAT_COLORS := [Color(0.12, 0.16, 0.34), Color(0.3, 0.32, 0.36), Color(0.45, 0.12, 0.14), Color(0.1, 0.28, 0.3), Color(0.2, 0.2, 0.22)]
const BAG_COLORS := [Color(0.1, 0.12, 0.3), Color(0.5, 0.1, 0.1), Color(0.15, 0.15, 0.15), Color(0.6, 0.45, 0.2), Color(0.2, 0.45, 0.3),
	Color(0.75, 0.75, 0.78), Color(0.85, 0.35, 0.55), Color(0.9, 0.6, 0.1)]
const CLOTH := [Color(0.12, 0.14, 0.25), Color(0.6, 0.6, 0.62), Color(0.5, 0.15, 0.12), Color(0.2, 0.35, 0.22), Color(0.85, 0.82, 0.75),
	Color(0.08, 0.08, 0.09), Color(0.3, 0.45, 0.7), Color(0.55, 0.4, 0.3)]
const SKIN := [Color(0.93, 0.78, 0.66), Color(0.8, 0.6, 0.45), Color(0.62, 0.43, 0.3), Color(0.42, 0.28, 0.2), Color(0.98, 0.85, 0.74)]

static var _wreck_shader: Shader


static func graphic_enabled() -> bool:
	return bool(Game.settings.get("graphic_crashes", false))


static func wreck_shader() -> Shader:
	## The airframe paint shader clipped to a part of the aircraft (a fuselage section between
	## keep_z, and/or a span range keep_x for a torn-off wing), open at the cut (dark inside),
	## charred and glowing along the break. Derived at runtime so it tracks the paint shader.
	if _wreck_shader != null:
		return _wreck_shader
	var src: String = (load("res://shaders/aircraft_paint.gdshader") as Shader).code
	src = src.replace("render_mode cull_back,", "render_mode cull_disabled,")
	src = src.replace("render_mode cull_back;", "render_mode cull_disabled;")
	src = src.replace("uniform float scorch = 0.0;", "uniform float scorch = 0.0;\nuniform vec2 keep_z = vec2(-1000.0, 1000.0);\nuniform vec2 keep_x = vec2(-1000.0, 1000.0);\nuniform float char_w = 1.8;\nuniform float embers = 0.0;")
	src = src.replace("void fragment() {", "void fragment() {\n\tif (lpos.z < keep_z.x || lpos.z > keep_z.y || lpos.x < keep_x.x || lpos.x > keep_x.y) { discard; }\n\tfloat cut_d = min(min(lpos.z - keep_z.x, keep_z.y - lpos.z), min(lpos.x - keep_x.x, keep_x.y - lpos.x));\n\tfloat char_k = 1.0 - smoothstep(0.0, char_w, cut_d);\n\tbool inside = !FRONT_FACING;")
	src = src.replace("\tALBEDO = col;", "\tcol = mix(col, vec3(0.035, 0.03, 0.025), char_k * 0.95);\n\tALBEDO = inside ? vec3(0.03, 0.026, 0.022) : col;")
	src = src.replace("\tROUGHNESS = rough;", "\tROUGHNESS = inside ? 0.95 : rough;")
	src = src.replace("\tMETALLIC = metal;", "\tMETALLIC = inside ? 0.0 : metal;")
	src = src.replace("\tEMISSION = emit;", "\tEMISSION = (inside ? vec3(0.0) : emit) + vec3(1.0, 0.3, 0.05) * embers * (1.0 - smoothstep(0.0, inside ? 0.6 : 0.35, cut_d)) * 3.0;")
	var sh := Shader.new()
	sh.code = src
	_wreck_shader = sh
	return sh


static func section(type_id: String, airline: String, reg: String, keep_z: Vector2, keep_x: Vector2, scorch: float, embers: float, detail: float = 1.0) -> AircraftModel:
	## A broken-off part of an airframe: a full model whose paint shader discards everything
	## outside the kept range. Gear, lights and prop discs are hidden.
	var m := AircraftModel.new()
	m.build(type_id, airline, reg, detail)
	var src: ShaderMaterial = m.mat
	var wm := ShaderMaterial.new()
	wm.shader = wreck_shader()
	for u in src.shader.get_shader_uniform_list():
		var nm := String(u.name)
		wm.set_shader_parameter(nm, src.get_shader_parameter(nm))
	wm.set_shader_parameter("keep_z", keep_z)
	wm.set_shader_parameter("keep_x", keep_x)
	wm.set_shader_parameter("scorch", scorch)
	wm.set_shader_parameter("dirt", 0.6)
	wm.set_shader_parameter("embers", embers)
	wm.set_shader_parameter("cabin_lights", 0.0)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == src:
			(mi as MeshInstance3D).material_override = wm
	for g in m.gear:
		(g.pivot as Node3D).visible = false
	for ln in m.label_nodes:
		var lp := (ln as Node3D).position
		(ln as Node3D).visible = lp.z > keep_z.x + 0.5 and lp.z < keep_z.y - 0.5 and lp.x > keep_x.x and lp.x < keep_x.y
		if scorch > 0.5 and ln is Label3D:
			(ln as Label3D).modulate = Color(0.25, 0.22, 0.2)
	for k in m.lights.keys():
		(m.lights[k] as Node3D).visible = false
	for sl in m.landing_lights:
		(sl as Node3D).visible = false
	for pd in m.prop_discs:
		if pd != null:
			(pd as Node3D).visible = false
	for i in m.fans.size():
		var fp := (m.fans[i] as Node3D).position
		(m.fans[i] as Node3D).visible = fp.z > keep_z.x and fp.z < keep_z.y and fp.x > keep_x.x and fp.x < keep_x.y
	return m


# ================================================================== single pieces
static func _rand_basis(r: RandomNumberGenerator, tilt: float = 0.6) -> Basis:
	return Basis.from_euler(Vector3(r.randf_range(-tilt, tilt), r.randf() * TAU, r.randf_range(-tilt, tilt)))


static func _cyl(mb: MeshBuilder, xf: Transform3D, a: Vector3, b: Vector3, ra: float, rb: float, segs: int, c: Color) -> void:
	mb.add_cylinder(xf * a, xf * b, ra, rb, segs, c)


static func panel(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator, col: Color, scale: float) -> void:
	## A torn piece of skin: a thin curved plate, sometimes with a stringer showing inside.
	var sz := Vector3(r.randf_range(0.4, 2.4), r.randf_range(0.04, 0.12), r.randf_range(0.4, 3.0)) * scale
	mb.add_rounded_box(xf.origin, sz, col, 0.15, 8, 4, xf.basis)
	if r.randf() < 0.5:
		var off := xf.basis * Vector3(0, -sz.y * 0.8, 0)
		mb.add_box_xf(Transform3D(xf.basis, xf.origin + off), Vector3(0.06, 0.08, sz.z * 0.9), Color(0.55, 0.58, 0.55))


static func seat(mb: MeshBuilder, xf: Transform3D, fabric: Color, scorch: float) -> void:
	## One passenger seat: cushion, backrest with headrest cover, armrests and the leg frame.
	var f := fabric.darkened(scorch * 0.7)
	var frame := Color(0.55, 0.56, 0.58).darkened(scorch * 0.5)
	mb.add_rounded_box(xf * Vector3(0, 0.44, 0), Vector3(0.46, 0.12, 0.47), f, 0.05, 6, 4, xf.basis)
	var back := xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	mb.add_rounded_box(xf * Vector3(0, 0.8, 0.24), Vector3(0.46, 0.62, 0.11), f, 0.05, 6, 4, back)
	mb.add_box_xf(Transform3D(back, xf * Vector3(0, 1.04, 0.2)), Vector3(0.4, 0.16, 0.12), Color(0.9, 0.9, 0.88).darkened(scorch * 0.8))
	for sx in [-0.25, 0.25]:
		mb.add_box_xf(Transform3D(xf.basis, xf * Vector3(sx, 0.6, 0.02)), Vector3(0.05, 0.06, 0.42), Color(0.25, 0.25, 0.27))
		_cyl(mb, xf, Vector3(sx * 0.8, 0.38, -0.15), Vector3(sx * 0.8, 0.0, -0.2), 0.025, 0.025, 6, frame)
		_cyl(mb, xf, Vector3(sx * 0.8, 0.38, 0.18), Vector3(sx * 0.8, 0.0, 0.22), 0.025, 0.025, 6, frame)


static func seat_row(mb: MeshBuilder, xf: Transform3D, fabric: Color, scorch: float, n: int) -> void:
	## Two or three seats still bolted to their track, torn out of the floor together.
	for i in n:
		seat(mb, xf * Transform3D(Basis(), Vector3((float(i) - (n - 1) * 0.5) * 0.48, 0, 0)), fabric, scorch)
	mb.add_box_xf(xf * Transform3D(Basis(), Vector3(0, 0.02, 0.0)), Vector3(0.5 * n, 0.04, 0.06), Color(0.5, 0.5, 0.52).darkened(scorch * 0.5))


static func suitcase(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator, col: Color, burst: bool) -> void:
	var sz := Vector3(r.randf_range(0.38, 0.55), r.randf_range(0.22, 0.3), r.randf_range(0.55, 0.78))
	if burst:
		# the shell split open: two halves and clothes thrown around it
		mb.add_rounded_box(xf * Vector3(0, sz.y * 0.25, 0), Vector3(sz.x, sz.y * 0.5, sz.z), col, 0.04, 6, 4, xf.basis)
		var lid := xf.basis * Basis(Vector3(0, 0, 1), deg_to_rad(r.randf_range(100.0, 170.0)))
		mb.add_rounded_box(xf * Vector3(sz.x * 0.9, sz.y * 0.2, 0), Vector3(sz.x, sz.y * 0.5, sz.z), col.darkened(0.1), 0.04, 6, 4, lid)
		for k in r.randi_range(3, 6):
			var p := Vector3(r.randf_range(-1.2, 1.6), 0.03, r.randf_range(-1.0, 1.0))
			mb.add_box_xf(Transform3D(xf.basis * Basis(Vector3.UP, r.randf() * TAU), xf * p), Vector3(r.randf_range(0.25, 0.6), 0.03, r.randf_range(0.2, 0.5)), CLOTH[r.randi() % CLOTH.size()])
	else:
		mb.add_rounded_box(xf * Vector3(0, sz.y * 0.5, 0), sz, col, 0.05, 6, 4, xf.basis)
		mb.add_box_xf(Transform3D(xf.basis, xf * Vector3(0, sz.y * 0.5, -sz.z * 0.5 - 0.03)), Vector3(0.16, 0.03, 0.05), Color(0.1, 0.1, 0.1))
		for wx in [-sz.x * 0.4, sz.x * 0.4]:
			_cyl(mb, xf, Vector3(wx - 0.02, 0.03, sz.z * 0.45), Vector3(wx + 0.02, 0.03, sz.z * 0.45), 0.03, 0.03, 6, Color(0.08, 0.08, 0.08))


static func bag(mb: MeshBuilder, xf: Transform3D, col: Color) -> void:
	mb.add_rounded_box(xf * Vector3(0, 0.16, 0), Vector3(0.34, 0.32, 0.22), col, 0.12, 8, 5, xf.basis)
	_cyl(mb, xf, Vector3(-0.1, 0.32, 0), Vector3(0.1, 0.32, 0), 0.02, 0.02, 5, col.darkened(0.4))


static func bin_door(mb: MeshBuilder, xf: Transform3D, scorch: float) -> void:
	## An overhead locker lid with its curved face.
	mb.add_rounded_box(xf.origin, Vector3(1.4, 0.06, 0.55), Color(0.92, 0.92, 0.9).darkened(scorch * 0.8), 0.1, 8, 4, xf.basis)
	mb.add_box_xf(Transform3D(xf.basis, xf * Vector3(0, 0.04, 0.2)), Vector3(0.18, 0.03, 0.05), Color(0.35, 0.35, 0.37))


static func wing_piece(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator, chord: float, len: float, col: Color, scorch: float) -> void:
	## A section of wing: tapered slab with a hanging flap and a jagged root.
	var c := col.darkened(scorch * 0.6)
	var t := chord * 0.11
	for k in 4:
		var f := float(k) / 4.0
		var cw := lerpf(chord, chord * 0.7, f)
		mb.add_rounded_box(xf * Vector3(f * len - len * 0.5 + len * 0.125, 0, 0), Vector3(len * 0.26, t * (1.0 - f * 0.3), cw), c, 0.2, 6, 4, xf.basis)
	var flap := xf.basis * Basis(Vector3.RIGHT, deg_to_rad(r.randf_range(15.0, 50.0)))
	mb.add_box_xf(Transform3D(flap, xf * Vector3(0, -t * 0.3, chord * 0.55)), Vector3(len * 0.6, t * 0.5, chord * 0.25), c.darkened(0.15))
	mb.add_box_xf(Transform3D(xf.basis, xf * Vector3(-len * 0.5, 0, 0)), Vector3(0.12, t * 1.4, chord * 0.8), Color(0.08, 0.07, 0.06))


static func fin_piece(mb: MeshBuilder, xf: Transform3D, chord: float, h: float, col: Color, scorch: float) -> void:
	var c := col.darkened(scorch * 0.5)
	for k in 3:
		var f := float(k) / 3.0
		mb.add_rounded_box(xf * Vector3(0, f * h + h / 6.0, f * chord * 0.35), Vector3(chord * 0.08, h / 3.0, chord * lerpf(1.0, 0.55, f)), c, 0.25, 6, 4, xf.basis)


static func engine(mb: MeshBuilder, xf: Transform3D, d: float, col: Color, scorch: float) -> void:
	## A separated nacelle with the fan face showing, or the bare core with its exhaust cone.
	var nc := col.darkened(scorch * 0.6)
	_cyl(mb, xf, Vector3(0, 0, -d * 1.0), Vector3(0, 0, d * 0.9), d * 0.5, d * 0.42, 18, nc)
	_cyl(mb, xf, Vector3(0, 0, -d * 0.95), Vector3(0, 0, -d * 0.85), d * 0.44, d * 0.44, 18, Color(0.12, 0.12, 0.13))
	_cyl(mb, xf, Vector3(0, 0, d * 0.9), Vector3(0, 0, d * 1.4), d * 0.25, d * 0.06, 12, Color(0.3, 0.28, 0.26).darkened(scorch * 0.6))


static func fan_disc(mb: MeshBuilder, xf: Transform3D, d: float, scorch: float) -> void:
	_cyl(mb, xf, Vector3(0, 0, -0.08), Vector3(0, 0, 0.08), d * 0.45, d * 0.45, 20, Color(0.32, 0.33, 0.35).darkened(scorch * 0.5))
	mb.add_sphere(xf * Vector3(0, 0, -0.12), Vector3(d * 0.12, d * 0.12, d * 0.12), 8, 5, Color(0.15, 0.15, 0.16))


static func wheel(mb: MeshBuilder, xf: Transform3D, rad: float) -> void:
	_cyl(mb, xf, Vector3(-rad * 0.32, 0, 0), Vector3(rad * 0.32, 0, 0), rad, rad, 16, Color(0.06, 0.06, 0.06))
	_cyl(mb, xf, Vector3(-rad * 0.34, 0, 0), Vector3(rad * 0.34, 0, 0), rad * 0.55, rad * 0.55, 12, Color(0.62, 0.63, 0.65))


static func insulation(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator) -> void:
	mb.add_rounded_box(xf.origin, Vector3(r.randf_range(0.3, 1.0), 0.06, r.randf_range(0.3, 0.8)), [Color(0.85, 0.75, 0.35), Color(0.75, 0.72, 0.65), Color(0.2, 0.2, 0.2)][r.randi() % 3], 0.4, 6, 4, xf.basis)


static func oxygen_masks(mb: MeshBuilder, xf: Transform3D) -> void:
	for k in 3:
		var p := Vector3(float(k) * 0.18 - 0.18, 0.04, 0)
		mb.add_cylinder(xf * p, xf * (p + Vector3(0, 0.06, 0)), 0.06, 0.05, 8, Color(0.95, 0.8, 0.1))
		_cyl(mb, xf, p + Vector3(0, 0.05, 0), p + Vector3(0.0, 0.02, 0.4), 0.008, 0.008, 4, Color(0.85, 0.85, 0.85))


# ================================================================== remains (optional, 18+)
static func remains(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator, kind: int) -> void:
	## Stylised, bloodless mannequin-like body parts: only built when the player has switched
	## on graphic crash scenes. 0 head, 1 arm, 2 leg, 3 torso.
	var skin: Color = SKIN[r.randi() % SKIN.size()]
	var cloth: Color = CLOTH[r.randi() % CLOTH.size()]
	match kind:
		0:
			mb.add_sphere(xf * Vector3(0, 0.11, 0), Vector3(0.09, 0.115, 0.1), 10, 7, skin)
			mb.add_sphere(xf * Vector3(0, 0.15, 0.015), Vector3(0.095, 0.085, 0.1), 10, 6, [Color(0.08, 0.06, 0.05), Color(0.35, 0.22, 0.12), Color(0.75, 0.62, 0.38), Color(0.5, 0.5, 0.5)][r.randi() % 4])
			mb.add_sphere(xf * Vector3(0, 0.1, -0.095), Vector3(0.018, 0.022, 0.02), 5, 4, skin.darkened(0.08))
			_cyl(mb, xf, Vector3(0, 0.0, 0.0), Vector3(0, 0.03, 0.0), 0.045, 0.045, 8, skin.darkened(0.15))
		1:
			_cyl(mb, xf, Vector3(0, 0.04, 0), Vector3(0, 0.04, 0.3), 0.045, 0.04, 8, cloth)
			_cyl(mb, xf, Vector3(0, 0.04, 0.3), Vector3(0, 0.04, 0.55), 0.035, 0.03, 8, skin)
			mb.add_rounded_box(xf * Vector3(0, 0.035, 0.62), Vector3(0.07, 0.03, 0.1), skin, 0.4, 6, 4, xf.basis)
		2:
			_cyl(mb, xf, Vector3(0, 0.06, 0), Vector3(0, 0.06, 0.45), 0.07, 0.055, 8, cloth)
			_cyl(mb, xf, Vector3(0, 0.06, 0.45), Vector3(0, 0.06, 0.85), 0.05, 0.04, 8, cloth.darkened(0.1))
			mb.add_rounded_box(xf * Vector3(0, 0.05, 0.92), Vector3(0.1, 0.09, 0.26), Color(0.1, 0.08, 0.07), 0.3, 6, 4, xf.basis * Basis(Vector3.RIGHT, PI * 0.5))
		_:
			mb.add_rounded_box(xf * Vector3(0, 0.12, 0), Vector3(0.38, 0.22, 0.55), cloth, 0.35, 8, 5, xf.basis)
			_cyl(mb, xf, Vector3(0, 0.12, -0.28), Vector3(0, 0.12, -0.34), 0.05, 0.05, 8, skin)


static func covered_body(mb: MeshBuilder, xf: Transform3D, r: RandomNumberGenerator) -> void:
	## A victim covered by responders: a white or grey sheet over a body-shaped mound.
	var sheet := Color(0.9, 0.9, 0.88) if r.randf() < 0.7 else Color(0.45, 0.47, 0.5)
	mb.add_rounded_box(xf * Vector3(0, 0.11, 0), Vector3(0.62, 0.22, 1.85), sheet, 0.5, 10, 6, xf.basis)
	mb.add_sphere(xf * Vector3(0, 0.15, -0.8), Vector3(0.16, 0.12, 0.15), 8, 5, sheet.darkened(0.03))
	if r.randf() < 0.5:
		mb.add_rounded_box(xf * Vector3(0.18, 0.05, 0.98), Vector3(0.1, 0.09, 0.2), Color(0.1, 0.08, 0.07), 0.3, 6, 4, xf.basis)


# ================================================================== a whole field
static func scatter(mb: MeshBuilder, r: RandomNumberGenerator, place: Callable, n: int, opts: Dictionary) -> void:
	## Lay n pieces out on the ground. place(i, r) returns the piece's ground position in the
	## mesh's frame. opts: body, accent, wing (colours), scorch, sev, chord, span, eng_d,
	## wheel_r, graphic, victims (how many fatalities to show), tail (bool: a fin piece).
	var body_c: Color = opts.get("body", Color(0.92, 0.92, 0.94))
	var acc_c: Color = opts.get("accent", Color(0.2, 0.3, 0.6))
	var wing_c: Color = opts.get("wing", Color(0.72, 0.74, 0.76))
	var scorch := float(opts.get("scorch", 0.4))
	var sev := float(opts.get("sev", 0.6))
	var fabric: Color = SEAT_COLORS[r.randi() % SEAT_COLORS.size()]
	var scale := 0.6 + sev * 0.6
	for i in n:
		var p: Vector3 = place.call(i, r)
		var roll := r.randf()
		var xf := Transform3D(_rand_basis(r, 0.5), p)
		if roll < 0.36:
			var col := body_c if r.randf() < 0.7 else (acc_c if r.randf() < 0.6 else Color(0.25, 0.25, 0.27))
			panel(mb, xf, r, col.darkened(r.randf_range(0.0, 0.6) * scorch), scale)
		elif roll < 0.52:
			# seats land upright, on their backs or on their side
			var b := Basis(Vector3.UP, r.randf() * TAU)
			var pick := r.randf()
			if pick < 0.3:
				b = b * Basis(Vector3.RIGHT, deg_to_rad(-80.0))
			elif pick < 0.5:
				b = b * Basis(Vector3(0, 0, 1), deg_to_rad(85.0))
			var sxf := Transform3D(b, p + Vector3(0, 0.25 if pick < 0.5 else 0.0, 0))
			if r.randf() < 0.35:
				seat_row(mb, sxf, fabric, scorch * r.randf(), r.randi_range(2, 3))
			else:
				seat(mb, sxf, fabric, scorch * r.randf())
		elif roll < 0.66:
			suitcase(mb, Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(0, 0, 1), deg_to_rad(90.0) if r.randf() < 0.3 else 0.0), p),
				r, BAG_COLORS[r.randi() % BAG_COLORS.size()], r.randf() < 0.35)
		elif roll < 0.72:
			bag(mb, Transform3D(_rand_basis(r, 1.2), p), BAG_COLORS[r.randi() % BAG_COLORS.size()])
		elif roll < 0.77:
			bin_door(mb, xf, scorch * r.randf())
		elif roll < 0.85:
			insulation(mb, xf, r)
		elif roll < 0.87:
			oxygen_masks(mb, xf)
		elif roll < 0.91:
			var ch := float(opts.get("chord", 3.0)) * r.randf_range(0.4, 0.8)
			wing_piece(mb, Transform3D(_rand_basis(r, 0.25), p + Vector3(0, 0.3, 0)), r, ch, ch * r.randf_range(1.5, 3.0), wing_c, scorch * r.randf())
		elif roll < 0.95:
			var d := float(opts.get("eng_d", 1.8))
			var eb := Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(0, 0, 1), r.randf_range(-0.4, 0.4))
			if r.randf() < 0.6:
				engine(mb, Transform3D(eb, p + Vector3(0, d * 0.45, 0)), d, acc_c if r.randf() < 0.5 else body_c, scorch)
			else:
				fan_disc(mb, Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + r.randf_range(-0.3, 0.3)), p + Vector3(0, 0.12, 0)), d, scorch)
		else:
			var wr := float(opts.get("wheel_r", 0.6))
			var wb := Basis(Vector3.UP, r.randf() * TAU) * (Basis(Vector3(0, 0, 1), PI * 0.5) if r.randf() < 0.6 else Basis())
			wheel(mb, Transform3D(wb, p + Vector3(0, wr * 0.35, 0)), wr)
	if bool(opts.get("tail", false)):
		var tp: Vector3 = place.call(n, r)
		fin_piece(mb, Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis(Vector3(0, 0, 1), deg_to_rad(r.randf_range(60.0, 100.0))), tp + Vector3(0, 0.4, 0)),
			float(opts.get("chord", 3.0)) * 1.3, float(opts.get("chord", 3.0)) * 1.6, acc_c, scorch)
	# victims: only with graphic crash scenes on, never with blood
	if bool(opts.get("graphic", false)):
		var victims := int(opts.get("victims", 0))
		var parts := mini(int(victims * 0.6 * sev), 80)
		for k in parts:
			var rp: Vector3 = place.call(n + 1 + k, r)
			remains(mb, Transform3D(Basis(Vector3.UP, r.randf() * TAU), rp + Vector3(0, 0.01, 0)), r, r.randi() % 4)
		var covered := mini(int(victims * 0.25), 40)
		for k2 in covered:
			var cp: Vector3 = place.call(n + 100 + k2, r)
			covered_body(mb, Transform3D(Basis(Vector3.UP, r.randf() * TAU), cp), r)


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.6
	m.metallic = 0.25
	return m


static func opts_for(spec: Dictionary, airline: String, scorch: float, sev: float) -> Dictionary:
	var lc := Airlines.livery_colors(airline)
	var d := 1.8
	if spec.has("fan_diam"):
		d = float(spec.fan_diam) * 1.15
	elif spec.has("prop_diam"):
		d = float(spec.prop_diam) * 0.45
	return {"body": lc.get("body", Color(0.92, 0.92, 0.94)), "accent": lc.get("tail", Color(0.2, 0.3, 0.6)), "wing": Color(0.72, 0.74, 0.76),
		"scorch": scorch, "sev": sev, "chord": float(spec.span) * 0.1, "span": float(spec.span), "eng_d": d, "wheel_r": clampf(float(spec.gear_height) * 0.28, 0.3, 0.7),
		"graphic": graphic_enabled()}
