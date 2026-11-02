class_name WreckPieces
extends Node
## Loose parts of a breaking aircraft: torn-off wings and tails, whole fuselage sections,
## engines, seats, luggage and skin panels. Each piece flies on its own ballistic path with
## air drag and tumble, trails smoke or fire if it is burning, bounces when it hits the ground
## and comes to rest there. Used for the player's crash, in-flight breakups after a mid-air
## collision, and AI aircraft hit by the player.

const MAX_SMALL := 90

var view: WorldView
var pieces: Array = []
var _small := 0
var _mat: StandardMaterial3D


func setup(world_view: WorldView) -> void:
	view = world_view
	_mat = CrashDebris.material()


func add_piece(node: Node3D, vel: Vector3, spin: Vector3, opts: Dictionary = {}) -> Dictionary:
	## node must already be placed (in dynamic_root coordinates). opts: drag, rest_h, bounce,
	## smoke (bool), fire (bool), big (bool).
	if node.get_parent() == null:
		view.dynamic_root.add_child(node)
	var p := {"node": node, "vel": vel, "spin": spin, "drag": float(opts.get("drag", 0.004)), "rest_h": float(opts.get("rest_h", 0.15)),
		"bounce": float(opts.get("bounce", 0.3)), "hops": 0, "landed": false, "big": bool(opts.get("big", false)), "trail": null, "fx": []}
	if bool(opts.get("smoke", false)):
		var tr := _trail(1.0 if p.big else 0.45, bool(opts.get("fire", false)))
		node.add_child(tr)
		p.trail = tr
	if bool(opts.get("fire", false)):
		var f := _flames(1.0 if p.big else 0.35)
		node.add_child(f)
		p.fx.append(f)
	pieces.append(p)
	return p


func falling_count() -> int:
	var n := 0
	for p in pieces:
		if not bool(p.landed):
			n += 1
	return n


# ================================================================== flying debris
func burst(at: Vector3, base_vel: Vector3, count: int, opts: Dictionary, rng: RandomNumberGenerator) -> void:
	## Throw count small pieces out of a breaking airframe: panels, seats, bags, insulation,
	## engine parts and (only with graphic crash scenes on) stylised remains.
	var graphic := bool(opts.get("graphic", false))
	var scorch := float(opts.get("scorch", 0.3))
	var body_c: Color = opts.get("body", Color(0.92, 0.92, 0.94))
	var acc_c: Color = opts.get("accent", Color(0.2, 0.3, 0.6))
	var fabric: Color = CrashDebris.SEAT_COLORS[rng.randi() % CrashDebris.SEAT_COLORS.size()]
	for i in count:
		if _small >= MAX_SMALL:
			return
		var mb := MeshBuilder.new()
		var roll := rng.randf()
		var drag := 0.02
		var rest := 0.05
		var kind := "panel"
		if graphic and roll < 0.1:
			CrashDebris.remains(mb, Transform3D.IDENTITY, rng, rng.randi() % 4)
			drag = 0.01
			kind = "remains"
		elif roll < 0.42:
			CrashDebris.panel(mb, Transform3D.IDENTITY, rng, (body_c if rng.randf() < 0.7 else acc_c).darkened(rng.randf() * scorch), 0.9)
			drag = 0.035
		elif roll < 0.6:
			CrashDebris.seat(mb, Transform3D(Basis(), Vector3(0, -0.5, 0)), fabric, scorch * rng.randf())
			drag = 0.012
			rest = 0.5
			kind = "seat"
		elif roll < 0.74:
			CrashDebris.suitcase(mb, Transform3D.IDENTITY, rng, CrashDebris.BAG_COLORS[rng.randi() % CrashDebris.BAG_COLORS.size()], false)
			drag = 0.01
			rest = 0.0
		elif roll < 0.82:
			CrashDebris.bag(mb, Transform3D.IDENTITY, CrashDebris.BAG_COLORS[rng.randi() % CrashDebris.BAG_COLORS.size()])
			drag = 0.015
		elif roll < 0.9:
			CrashDebris.insulation(mb, Transform3D.IDENTITY, rng)
			drag = 0.08
		elif roll < 0.95:
			CrashDebris.bin_door(mb, Transform3D.IDENTITY, scorch)
			drag = 0.05
		else:
			CrashDebris.wheel(mb, Transform3D.IDENTITY, float(opts.get("wheel_r", 0.5)))
			drag = 0.006
			rest = float(opts.get("wheel_r", 0.5)) * 0.35
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "panel" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = at + Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 2.5), rng.randf_range(-3, 3))
		mi.basis = CrashDebris._rand_basis(rng, PI)
		view.dynamic_root.add_child(mi)
		var kick := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.3), rng.randf_range(-1, 1)) * rng.randf_range(6.0, 22.0)
		var v := base_vel * rng.randf_range(0.35, 1.0) + kick
		var spin := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(2.0, 12.0)
		add_piece(mi, v, spin, {"drag": drag, "rest_h": rest, "bounce": 0.35, "smoke": rng.randf() < 0.08, "fire": rng.randf() < 0.05})
		_small += 1


func engine_piece(at: Vector3, base_vel: Vector3, d: float, col: Color, rng: RandomNumberGenerator, burning: bool) -> void:
	var mb := MeshBuilder.new()
	CrashDebris.engine(mb, Transform3D.IDENTITY, d, col, 0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _mat
	mi.position = at
	mi.basis = CrashDebris._rand_basis(rng, 0.4)
	view.dynamic_root.add_child(mi)
	var v := base_vel * rng.randf_range(0.6, 1.0) + Vector3(rng.randf_range(-6, 6), rng.randf_range(2, 9), rng.randf_range(-6, 6))
	add_piece(mi, v, Vector3(rng.randf_range(-1, 1), rng.randf_range(-3, 3), rng.randf_range(-1, 1)), {"drag": 0.003, "rest_h": d * 0.45, "bounce": 0.25, "smoke": true, "fire": burning, "big": true})


# ================================================================== simulation
func _physics_process(dt: float) -> void:
	if view == null:
		return
	for p in pieces:
		if bool(p.landed):
			continue
		var n: Node3D = p.node
		if not is_instance_valid(n):
			p.landed = true
			continue
		var v: Vector3 = p.vel
		v.y -= 9.81 * dt
		v -= v * minf(float(p.drag) * v.length() * dt, 0.9)
		n.position += v * dt
		var s: Vector3 = p.spin
		if s.length_squared() > 1e-6:
			n.basis = (Basis(s.normalized(), s.length() * dt) * n.basis).orthonormalized()
		var gx := view.wx(n.position)
		var gz := view.wz(n.position)
		var gy := Geo.ground_height(gx, gz)
		var water := Geo.is_water(gx, gz)
		if n.position.y <= gy + float(p.rest_h) and v.y < 0.0:
			var speed := v.length()
			if not water and speed > 9.0 and int(p.hops) < 2:
				p.hops = int(p.hops) + 1
				v = Vector3(v.x * 0.45, -v.y * float(p.bounce), v.z * 0.45)
				p.spin = s * 0.5
				n.position.y = gy + float(p.rest_h)
			else:
				_land(p, gy, water)
				v = Vector3.ZERO
		p.vel = v


func _land(p: Dictionary, gy: float, water: bool) -> void:
	p.landed = true
	var n: Node3D = p.node
	n.position.y = gy + float(p.rest_h) - (0.6 if water else 0.0)
	# settle: keep the heading, flatten most of the tumble so pieces lie on the ground
	var fwd := -n.basis.z
	fwd.y *= 0.25
	if fwd.length_squared() < 1e-4:
		fwd = Vector3.FORWARD
	var up := n.basis.y
	var flip := -1.0 if up.y < -0.2 and not bool(p.big) else 1.0
	var b := Basis.looking_at(fwd.normalized(), Vector3.UP * flip)
	n.basis = b
	if p.trail != null and is_instance_valid(p.trail):
		(p.trail as GPUParticles3D).emitting = bool(p.big) and not water
		(p.trail as GPUParticles3D).amount_ratio = 0.5
	if water:
		for f in p.fx:
			if is_instance_valid(f):
				(f as Node3D).queue_free()
		p.fx = []


# ================================================================== effects
func _trail(scale: float, fire: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(60 * scale) + 10
	p.lifetime = 9.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 2.0 * scale
	pm.scale_max = 4.5 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 3.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.15, 0.9) if fire else Color(0.12, 0.11, 0.1, 0.8))
	grad.add_point(0.12, Color(0.1, 0.09, 0.08, 0.85))
	grad.set_color(grad.get_point_count() - 1, Color(0.4, 0.39, 0.38, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.5, 2.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	p.emitting = true
	return p


func _flames(scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(50 * scale) + 8
	p.lifetime = 0.8
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 3.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2 * scale
	pm.scale_min = 1.2 * scale
	pm.scale_max = 2.6 * scale
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.add_point(0.4, Color(1.0, 0.5, 0.1, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.08, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.8)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	p.emitting = true
	return p


# ================================================================== airframe break-up
static func split_model(model: AircraftModel, keep_z: Vector2, keep_x: Vector2, scorch: float, embers: float) -> void:
	## Turn an aircraft's own model into a clipped wreck section (keeps its transform/parent).
	var src: ShaderMaterial = model.mat
	var wm := ShaderMaterial.new()
	wm.shader = CrashDebris.wreck_shader()
	for u in src.shader.get_shader_uniform_list():
		var nm := String(u.name)
		wm.set_shader_parameter(nm, src.get_shader_parameter(nm))
	wm.set_shader_parameter("keep_z", keep_z)
	wm.set_shader_parameter("keep_x", keep_x)
	wm.set_shader_parameter("scorch", scorch)
	wm.set_shader_parameter("embers", embers)
	wm.set_shader_parameter("cabin_lights", 0.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == src:
			(mi as MeshInstance3D).material_override = wm
	for i in model.fans.size():
		var fp := (model.fans[i] as Node3D).position
		if fp.z < keep_z.x or fp.z > keep_z.y or fp.x < keep_x.x or fp.x > keep_x.y:
			(model.fans[i] as Node3D).visible = false
	for ln in model.label_nodes:
		var lp := (ln as Node3D).position
		if lp.z < keep_z.x + 0.5 or lp.z > keep_z.y - 0.5 or lp.x < keep_x.x or lp.x > keep_x.y:
			(ln as Node3D).visible = false
	for g in model.gear:
		var gp := (g.pivot as Node3D).position
		if gp.z < keep_z.x or gp.z > keep_z.y or gp.x < keep_x.x or gp.x > keep_x.y:
			(g.pivot as Node3D).visible = false
	for pd in model.prop_discs:
		if pd != null:
			(pd as Node3D).visible = false


func break_up(model: AircraftModel, xf: Transform3D, vel: Vector3, type_id: String, airline: String, reg: String, plan: Dictionary,
		rng: RandomNumberGenerator, burning: bool) -> Dictionary:
	## Separate parts of an airframe: plan = {tail: bool, wing: -1/0/1 (side), nose: bool}.
	## The given model becomes the main remaining section; separated sections are new models that
	## fly off on their own. Returns the main section's kept ranges.
	var spec := AircraftTypes.get_type(type_id)
	var L := float(spec.length)
	var nose_z := -L * float(spec.cg_frac)
	var cut := float(spec.fuse_w) * 0.5 + float(spec.span) * 0.17
	var keep_z := Vector2(-1000.0, 1000.0)
	var keep_x := Vector2(-1000.0, 1000.0)
	var spin_k := 1.0
	if bool(plan.get("tail", false)):
		var tz := nose_z + L * rng.randf_range(0.7, 0.78)
		keep_z.y = tz
		var tail := CrashDebris.section(type_id, airline, reg, Vector2(tz, 1000.0), Vector2(-1000.0, 1000.0), 0.3, 1.0 if burning else 0.4, 0.6)
		tail.transform = xf
		view.dynamic_root.add_child(tail)
		add_piece(tail, vel * 0.92 + xf.basis.y * 3.0, xf.basis.x * rng.randf_range(0.6, 1.4) + xf.basis.y * rng.randf_range(-0.4, 0.4),
			{"drag": 0.0035, "rest_h": float(spec.fuse_h) * 0.45, "bounce": 0.15, "smoke": true, "fire": burning, "big": true})
	if bool(plan.get("nose", false)):
		var nz := nose_z + L * rng.randf_range(0.16, 0.24)
		keep_z.x = nz
		var nose := CrashDebris.section(type_id, airline, reg, Vector2(-1000.0, nz), Vector2(-1000.0, 1000.0), 0.4, 0.8, 0.6)
		nose.transform = xf
		view.dynamic_root.add_child(nose)
		add_piece(nose, vel * 1.02 - xf.basis.y * 2.0, -xf.basis.x * rng.randf_range(0.8, 1.6),
			{"drag": 0.003, "rest_h": float(spec.fuse_h) * 0.45, "bounce": 0.15, "smoke": true, "fire": false, "big": true})
	var side := int(plan.get("wing", 0))
	if side != 0:
		var wkx := Vector2(cut, 1000.0) if side > 0 else Vector2(-1000.0, -cut)
		if side > 0:
			keep_x.y = cut
		else:
			keep_x.x = -cut
		var wing := CrashDebris.section(type_id, airline, reg, Vector2(nose_z + L * 0.2, nose_z + L * 0.72), wkx, 0.25, 1.0 if burning else 0.5, 0.6)
		wing.transform = xf
		view.dynamic_root.add_child(wing)
		var away := xf.basis.x * float(side)
		add_piece(wing, vel * 0.85 + away * 6.0 + xf.basis.y * 4.0, -xf.basis.z * float(side) * rng.randf_range(1.5, 3.0) + xf.basis.y * rng.randf_range(-1.0, 1.0),
			{"drag": 0.012, "rest_h": 0.6, "bounce": 0.1, "smoke": true, "fire": burning, "big": true})
		spin_k = 2.0
	split_model(model, keep_z, keep_x, 0.2, 0.8 if burning else 0.3)
	return {"keep_z": keep_z, "keep_x": keep_x, "roll_rate": spin_k * float(side)}
