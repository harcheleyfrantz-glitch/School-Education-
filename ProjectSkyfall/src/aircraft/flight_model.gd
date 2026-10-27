class_name FlightModel
extends RefCounted
## Six-degree-of-freedom rigid-body flight dynamics with a coefficient-based aerodynamic model,
## engines applied at their mounting points, and spring-damper landing gear with tyre friction.
## Body axes follow Godot: +X right wing, +Y up, -Z nose. All units SI.

const AIR_RHO0 := 1.225

var spec: Dictionary
var S := 120.0
var b := 35.0
var c := 4.0
var AR := 10.0

# ---------------------------------------------------------------- state
var pos := Vector3.ZERO            # WorldView-local position
var vel := Vector3.ZERO            # world velocity (m/s)
var basis := Basis.IDENTITY
var omega := Vector3.ZERO          # body angular velocity (rad/s)
var mass := 60000.0
var inertia := Vector3.ONE         # (pitch about X, yaw about Y, roll about Z)
var cg_aft := 0.0                  # metres aft of the reference point (pitch trim effect)

# ---------------------------------------------------------------- inputs
var elevator := 0.0                # -1..1, + nose up
var aileron := 0.0                 # + roll right
var rudder := 0.0                  # + nose right
var flap_frac := 0.0               # fractional flap detent index
var gear := [1.0, 1.0, 1.0]        # extension 0..1 (nose, left main, right main)
var gear_ok := [true, true, true]  # leg structurally intact
var spoilers := 0.0
var thrust := []                   # N per engine (negative = reverse)
var engine_pos := []               # Vector3 body positions
var brake_l := 0.0
var brake_r := 0.0
var steer := 0.0                   # nose-wheel steering -1..1
var wind := Vector3.ZERO
var gust := Vector3.ZERO
var isa_dev := 0.0
var ice := 0.0
var damage_drag := 0.0
var damage_lift := 0.0
var damage_roll := 0.0
var damage_yaw := 0.0
var surface_mu := 1.0              # 1 dry, ~0.5 wet, ~0.25 ice
var ground_plane := Plane(Vector3.UP, 0.0)   # local ground under the aircraft
var ground_is_water := false
var ground_rough := 0.0            # 0 paved, 1 rough terrain (extra rolling drag)

# ---------------------------------------------------------------- outputs
var tas := 0.0
var ias := 0.0
var mach := 0.0
var alpha := 0.0
var beta := 0.0
var qbar := 0.0
var nz := 1.0
var cl_now := 0.0
var alpha_stall := 0.25
var stall := 0.0                   # 0..1 depth into the stall
var buffet := 0.0
var on_ground := false
var wow := [false, false, false]
var gear_load := [0.0, 0.0, 0.0]
var agl := 1000.0
var accel_world := Vector3.ZERO
var contacts: Array = []           # {name, p (body), kind, k, c, mu, gear}
var impacts: Array = []            # collected per step: {part, speed, vs, force}
var wheel_speed := 0.0
var _wing_drop := 0.0
var _last_stall := false
var rng := RandomNumberGenerator.new()


func setup(type_spec: Dictionary, total_mass: float) -> void:
	spec = type_spec
	S = float(spec.wing_area)
	b = float(spec.span)
	c = float(spec.mac)
	AR = b * b / S
	set_mass(total_mass)
	rng.seed = 4242
	_build_contacts()
	var n: int = int(spec.engine_count)
	thrust.resize(n)
	thrust.fill(0.0)
	engine_pos = engine_positions(spec)


func set_mass(m: float) -> void:
	mass = maxf(m, 300.0)
	var k: Array = spec.inertia_k
	var L := float(spec.length)
	var rx := float(k[0]) * b * 0.5
	var ry := float(k[1]) * L * 0.5
	var rz := float(k[2]) * (b + L) * 0.25
	inertia = Vector3(mass * ry * ry, mass * rz * rz, mass * rx * rx)


static func engine_positions(t: Dictionary) -> Array:
	var out := []
	var n: int = int(t.engine_count)
	var span: float = t.span
	var fw: float = t.fuse_w
	match String(t.engine_mount):
		"nose":
			out.append(Vector3(0, 0, -float(t.length) * float(t.cg_frac) + 0.2))
		"rear":
			for i in n:
				var sx := -1.0 if i == 0 else 1.0
				out.append(Vector3(sx * (fw * 0.5 + 1.0), 0.6, float(t.length) * 0.32))
		"wing_prop":
			for i in n:
				var sx2 := -1.0 if i % 2 == 0 else 1.0
				out.append(Vector3(sx2 * span * 0.17, 0.9, -2.2))
		_:
			if n == 4:
				var offs := [-0.42, -0.24, 0.24, 0.42]
				for i in 4:
					out.append(Vector3(offs[i] * span, -1.6, -3.0 - absf(offs[i]) * 6.0 + 4.0))
			else:
				for i in n:
					var sx3 := -1.0 if i == 0 else 1.0
					out.append(Vector3(sx3 * span * 0.17, -fw * 0.42 - 0.3, -2.5))
	return out


func _build_contacts() -> void:
	contacts.clear()
	var gh: float = spec.gear_height
	var gx_n: float = spec.nose_gear_x
	var gx_m: float = spec.main_gear_x
	var track: float = spec.gear_track
	var share_main := absf(gx_n) / (absf(gx_n) + absf(gx_m))
	var w := mass * U.G0
	var stroke := 0.32 if spec.category != "trainer" else 0.12
	# gear legs: stiffness sized so the static load compresses ~a third of the stroke
	var kn := w * (1.0 - share_main) / (stroke * 0.35)
	var km := w * share_main * 0.5 / (stroke * 0.35)
	contacts.append({"name": "nose", "p": Vector3(0, -gh, gx_n), "kind": "gear", "k": kn, "c": 2.0 * 0.55 * sqrt(kn * mass * (1.0 - share_main)), "gear": 0, "stroke": stroke})
	contacts.append({"name": "main_l", "p": Vector3(-track * 0.5, -gh, gx_m), "kind": "gear", "k": km, "c": 2.0 * 0.55 * sqrt(km * mass * share_main * 0.5), "gear": 1, "stroke": stroke})
	contacts.append({"name": "main_r", "p": Vector3(track * 0.5, -gh, gx_m), "kind": "gear", "k": km, "c": 2.0 * 0.55 * sqrt(km * mass * share_main * 0.5), "gear": 2, "stroke": stroke})
	# structure points (belly, tail, wingtips, nose, engines)
	var L: float = spec.length
	var cgf: float = spec.cg_frac
	var fh: float = spec.fuse_h
	var ks := w / 0.25
	var cs := 2.0 * 0.5 * sqrt(ks * mass)
	var belly_y := -fh * 0.5
	contacts.append({"name": "belly_f", "p": Vector3(0, belly_y, -L * cgf * 0.6), "kind": "body", "k": ks, "c": cs, "gear": -1})
	contacts.append({"name": "belly_c", "p": Vector3(0, belly_y, 0.0), "kind": "body", "k": ks, "c": cs, "gear": -1})
	contacts.append({"name": "belly_a", "p": Vector3(0, belly_y + fh * 0.12, L * (1.0 - cgf) * 0.55), "kind": "body", "k": ks, "c": cs, "gear": -1})
	# tail contact placed so that rotating about the main gear touches it at the type's tailstrike attitude
	var tz := L * (1.0 - cgf) * 0.72
	var ty := -gh + 0.15 + tan(deg_to_rad(float(spec.get("tailstrike", 11.0)))) * (tz - gx_m)
	contacts.append({"name": "tail", "p": Vector3(0, ty, tz), "kind": "body", "k": ks, "c": cs, "gear": -1})
	contacts.append({"name": "nose_cone", "p": Vector3(0, 0.0, -L * cgf), "kind": "body", "k": ks, "c": cs, "gear": -1})
	var wing_y := (fh * 0.42) if spec.wing_pos == "high" else (-fh * 0.3)
	var dih := deg_to_rad(float(spec.dihedral))
	var sweep := deg_to_rad(float(spec.sweep))
	for sx in [-1.0, 1.0]:
		var tip := Vector3(sx * b * 0.5, wing_y + b * 0.5 * sin(dih), b * 0.5 * tan(sweep) * 0.9)
		contacts.append({"name": "wing_l" if sx < 0 else "wing_r", "p": tip, "kind": "body", "k": ks * 0.3, "c": cs * 0.3, "gear": -1})
	for i in engine_pos.size():
		var ep: Vector3 = engine_pos[i]
		var ef: float = spec.get("fan_diam", 1.0)
		contacts.append({"name": "engine_%d" % i, "p": ep - Vector3(0, ef * 0.55, 0), "kind": "body", "k": ks * 0.5, "c": cs * 0.5, "gear": -1})


# ---------------------------------------------------------------- aerodynamics
func _flap_coeffs() -> Dictionary:
	var flaps: Array = spec.flaps
	var fi := clampf(flap_frac, 0.0, flaps.size() - 1.0)
	var i0 := int(floor(fi))
	var i1 := mini(i0 + 1, flaps.size() - 1)
	var t := fi - i0
	var f0: Dictionary = flaps[i0]
	var f1: Dictionary = flaps[i1]
	return {"dcl": lerpf(f0.dcl, f1.dcl, t), "dclmax": lerpf(f0.dclmax, f1.dclmax, t),
		"dcd": lerpf(f0.dcd, f1.dcd, t), "dcm": lerpf(f0.dcm, f1.dcm, t)}


static func lift_curve(a: float, cl0: float, cla: float, clmax: float) -> Dictionary:
	var a_s := (clmax - cl0) / cla
	var a_ns := (-clmax * 0.75 - cl0) / cla
	var cl := 0.0
	var stall_depth := 0.0
	var knee := 0.04
	if a >= a_ns and a <= a_s - knee:
		cl = cl0 + cla * a
	elif a > a_s - knee and a <= a_s:
		var t := (a - (a_s - knee)) / knee
		cl = lerpf(cl0 + cla * (a_s - knee), clmax, t * (2.0 - t))
	elif a > a_s:
		var dt := clampf((a - a_s) / 0.12, 0.0, 1.0)
		var post := lerpf(clmax, clmax * 0.62, dt)
		var t2 := clampf((a - a_s - 0.12) / 0.45, 0.0, 1.0)
		cl = lerpf(post, 1.15 * sin(2.0 * a), t2)
		stall_depth = clampf((a - a_s) / 0.1, 0.0, 1.0)
	else:
		var dt2 := clampf((a_ns - a) / 0.12, 0.0, 1.0)
		var post2 := lerpf(-clmax * 0.75, -clmax * 0.5, dt2)
		var t3 := clampf((a_ns - a - 0.12) / 0.45, 0.0, 1.0)
		cl = lerpf(post2, 1.15 * sin(2.0 * a), t3)
		stall_depth = clampf((a_ns - a) / 0.1, 0.0, 1.0)
	return {"cl": cl, "a_s": a_s, "stall": stall_depth}


func _aero(alt: float) -> Array:
	var rho := Atmo.density(maxf(alt, -100.0), isa_dev)
	var v_air := vel - wind - gust
	var inv := basis.transposed()
	var vb := inv * v_air
	var V := vb.length()
	tas = V
	ias = V * sqrt(rho / AIR_RHO0)
	mach = V / Atmo.speed_of_sound(maxf(alt, 0.0), isa_dev)
	if V < 0.8:
		alpha = 0.0
		beta = 0.0
		qbar = 0.0
		return [Vector3.ZERO, Vector3.ZERO]
	var u := -vb.z
	var w_up := vb.y
	alpha = atan2(-w_up, u)
	beta = asin(clampf(vb.x / V, -1.0, 1.0))
	qbar = 0.5 * rho * V * V
	# body rates (p roll right, q pitch up, r yaw right)
	var p := -omega.z
	var q := omega.x
	var r := -omega.y
	var ph := p * b / (2.0 * V)
	var qh := q * c / (2.0 * V)
	var rh := r * b / (2.0 * V)
	# control blow-down: hinge moments and lockouts limit throws at high dynamic pressure
	var vref := float(spec.vref) * U.KT * 1.3
	var q_ref := 0.5 * AIR_RHO0 * vref * vref
	var blow := clampf(q_ref / maxf(qbar, 1.0), 0.28, 1.0)
	var de := elevator * deg_to_rad(float(spec.max_elev)) * lerpf(1.0, blow, 0.45)
	var da := aileron * deg_to_rad(float(spec.max_ail)) * blow
	var dr := rudder * deg_to_rad(float(spec.max_rud)) * lerpf(1.0, blow, 0.8)
	var fc := _flap_coeffs()
	var cl0: float = float(spec.cl0) + fc.dcl
	var clmax: float = (float(spec.clmax) + fc.dclmax) * (1.0 - 0.28 * ice) * (1.0 - damage_lift)
	var lc := lift_curve(alpha, cl0, float(spec.cla), clmax)
	alpha_stall = lc.a_s
	var cl: float = lc.cl
	stall = lc.stall
	cl += 3.5 * qh + 0.32 * de
	cl *= 1.0 - 0.45 * spoilers
	cl *= 1.0 - damage_lift * 0.5
	# ground effect
	var hb := clampf(agl / b, 0.0, 2.0)
	var k_ge := 1.0
	if hb < 1.0:
		var x16 := 16.0 * hb
		k_ge = (x16 * x16) / (1.0 + x16 * x16)
		cl *= 1.0 + 0.09 * (1.0 - hb)
	cl_now = cl
	var e: float = spec.oswald
	var gear_avg: float = (float(gear[0]) + float(gear[1]) + float(gear[2])) / 3.0
	var cd: float = float(spec.cd0) + fc.dcd + float(spec.gear_cd) * gear_avg + float(spec.spoiler_cd) * spoilers
	cd += cl * cl / (PI * e * AR) * k_ge + damage_drag + ice * 0.012
	var mcrit: float = (float(spec.mmo) - 0.05) if float(spec.mmo) > 0.0 else 0.55
	if mach > mcrit:
		cd += 20.0 * pow(mach - mcrit, 4.0)
	if stall > 0.0:
		cd = maxf(cd, float(spec.cd0) + 1.25 * sin(alpha) * sin(alpha))
	var cy: float = float(spec.cyb) * beta - float(spec.cydr) * dr
	# moments
	var cm: float = float(spec.cm0) + float(spec.cma) * alpha + float(spec.cmq) * qh + float(spec.cmde) * de + fc.dcm
	cm += cl * cg_aft / c * 0.6
	cm -= 0.18 * stall
	# stall wing-drop: a random wing lets go first
	var is_stalled := stall > 0.25
	if is_stalled and not _last_stall:
		_wing_drop = rng.randf_range(-1.0, 1.0)
	_last_stall = is_stalled
	var croll: float = float(spec.clb) * beta + float(spec.clp) * ph + float(spec.clr) * rh * clampf(cl, 0.0, 1.5) + float(spec.clda) * da - 0.012 * dr
	croll += _wing_drop * 0.05 * stall + damage_roll
	var cn: float = float(spec.cnb) * beta + float(spec.cnr) * rh + float(spec.cnp) * ph + float(spec.cndr) * dr + float(spec.cnda) * da + damage_yaw
	buffet = clampf((alpha - (alpha_stall - 0.035)) / 0.06, 0.0, 1.0) + clampf((mach - mcrit - 0.02) * 10.0, 0.0, 1.0)
	# forces (world)
	var vdir := v_air / V
	var right_w := basis.x
	var lift_dir := right_w.cross(vdir)
	if lift_dir.length_squared() < 1e-6:
		lift_dir = basis.y
	lift_dir = lift_dir.normalized()
	var F := (lift_dir * cl - vdir * cd + right_w * cy) * qbar * S
	var tau := Vector3(cm * c, -cn * b, -croll * b) * qbar * S
	return [F, tau]


# ---------------------------------------------------------------- ground
func _ground_forces(dt: float) -> Array:
	var F := Vector3.ZERO
	var tau := Vector3.ZERO
	on_ground = false
	wow = [false, false, false]
	gear_load = [0.0, 0.0, 0.0]
	var n := ground_plane.normal
	var inv := basis.transposed()
	for ct in contacts:
		var g: int = ct.gear
		var pb: Vector3 = ct.p
		if g >= 0:
			if float(gear[g]) < 0.98 or not gear_ok[g]:
				continue
		var rw: Vector3 = basis * pb
		var pw := pos + rw
		var depth := -ground_plane.distance_to(pw)
		if depth <= 0.0:
			continue
		var vp := vel + basis * omega.cross(pb)
		var vn := vp.dot(n)
		if ground_is_water:
			# water: strong drag, weak buoyancy (ditching)
			var fw := n * clampf(depth * mass * 4.0, 0.0, mass * 30.0) - vp * mass * 0.35 * (1.0 if g < 0 else 0.2)
			F += fw
			tau += inv * rw.cross(fw)
			if absf(vn) > 2.0:
				impacts.append({"part": ct.name, "speed": vp.length(), "vs": -vn, "kind": ct.kind, "water": true})
			continue
		var k: float = ct.k
		var cdamp: float = ct.c
		var fn := k * depth - cdamp * vn
		if ct.kind == "gear":
			var stroke: float = ct.stroke
			if depth > stroke:
				# bottomed out: very stiff
				fn += (depth - stroke) * k * 25.0
		fn = maxf(fn, 0.0)
		if fn <= 0.0:
			continue
		if ct.kind == "body":
			impacts.append({"part": ct.name, "speed": vp.length(), "vs": -vn, "kind": "body", "force": fn})
		elif -vn > 2.6:
			impacts.append({"part": ct.name, "speed": vp.length(), "vs": -vn, "kind": "gear", "force": fn})
		var force := n * fn
		# tyre / skid friction in the ground plane
		var fwd := -basis.z
		if g == 0:
			var steer_ang := steer * deg_to_rad(70.0 if ias < 15.0 else 8.0)
			fwd = Basis(basis.y, -steer_ang) * fwd
		fwd = (fwd - n * fwd.dot(n)).normalized()
		var side := n.cross(fwd).normalized()
		var v_long := vp.dot(fwd)
		var v_lat := vp.dot(side)
		if ct.kind == "gear":
			wow[g] = true
			gear_load[g] = fn
			on_ground = true
			var mu_roll := 0.012 + ground_rough * 0.06
			var brake := 0.0
			if g == 1:
				brake = brake_l
			elif g == 2:
				brake = brake_r
			var mu_b := brake * 0.62 * surface_mu
			var mu_long := mu_roll + mu_b
			var long_f := -v_long / (absf(v_long) + 0.25) * mu_long * fn
			if brake > 0.5 and absf(v_long) < 0.5:
				long_f = clampf(-v_long * fn * 6.0, -mu_long * fn, mu_long * fn)
			var lat_cap := 0.75 * surface_mu * fn
			var lat_f := clampf(-v_lat * mass * 3.0, -lat_cap, lat_cap)
			force += fwd * long_f + side * lat_f
			if g == 1:
				wheel_speed = v_long
		else:
			on_ground = true
			var mu_s := 0.45 * (1.0 if not ground_is_water else 0.2)
			var vh := vp - n * vn
			var sp := vh.length()
			if sp > 0.01:
				force += -vh / (sp + 0.3) * mu_s * fn
		F += force
		tau += inv * rw.cross(force)
	return [F, tau]


# ---------------------------------------------------------------- integration
func step(dt: float, alt: float) -> void:
	agl = ground_plane.distance_to(pos)
	var aero := _aero(alt)
	var F: Vector3 = aero[0]
	var tau: Vector3 = aero[1]
	# engines
	for i in thrust.size():
		var t: float = thrust[i]
		if t == 0.0:
			continue
		var tb := Vector3(0, 0, -t)
		F += basis * tb
		tau += (engine_pos[i] as Vector3).cross(tb)
	F += Vector3(0, -mass * U.G0, 0)
	var gr := _ground_forces(dt)
	F += gr[0]
	tau += gr[1]
	var acc := F / mass
	accel_world = acc
	vel += acc * dt
	pos += vel * dt
	# rigid body rotation (diagonal inertia, gyroscopic coupling)
	var Iw := Vector3(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z)
	var wdot := (tau - omega.cross(Iw)) / inertia
	omega += wdot * dt
	if on_ground:
		omega *= 1.0 - minf(dt * 0.8, 0.1)
	var ang := omega.length() * dt
	if ang > 1e-7:
		basis = (basis * Basis(omega.normalized(), ang)).orthonormalized()
	# load factor along body up axis (what the pilot feels)
	nz = (acc + Vector3(0, U.G0, 0)).dot(basis.y) / U.G0


# ---------------------------------------------------------------- convenience
func heading_deg() -> float:
	return U.dir_to_heading(-basis.z)


func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-basis.z.y, -1.0, 1.0)))


func bank_deg() -> float:
	# positive = right wing down
	var fwd := -basis.z
	var right := basis.x
	var level_right := fwd.cross(Vector3.UP)
	if level_right.length_squared() < 1e-6:
		return 0.0
	level_right = level_right.normalized()
	var s := -right.dot(Vector3.UP)
	return rad_to_deg(atan2(s, right.dot(level_right)))


func vs_mps() -> float:
	return vel.y


func ground_speed() -> float:
	return Vector2(vel.x, vel.z).length()


func track_deg() -> float:
	return U.dir_to_heading(Vector3(vel.x, 0, vel.z))


func set_attitude(heading: float, pitch: float, bank: float) -> void:
	var b0 := Basis(Vector3.UP, -deg_to_rad(heading))
	b0 = b0 * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	b0 = b0 * Basis(Vector3.FORWARD, deg_to_rad(bank))
	basis = b0.orthonormalized()
