class_name Tornado
extends Node3D
## A tornado on the player's route: a rotating funnel from the cloud base to the ground with a
## debris cloud at its foot. Near it the air spins and rises violently; flying into the core
## at low level tears the aircraft apart.

const INFLUENCE := 1400.0
const CORE := 140.0

var session: Node
var ac: Aircraft
var view: WorldView
var wx := 0.0
var wz := 0.0
var drift := Vector2(6.0, 3.0)
var top := 1600.0
var _funnel: MeshInstance3D
var _t := 0.0
var _warned := false


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView, at: Vector2) -> void:
	session = sess
	ac = aircraft
	view = world_view
	wx = at.x
	wz = at.y
	drift = Vector2.from_angle(randf() * TAU) * randf_range(5.0, 12.0)
	_build()


func _build() -> void:
	var mb := MeshBuilder.new()
	var rings := 14
	var prev_r := 0.0
	for i in rings:
		var f0 := float(i) / rings
		var f1 := float(i + 1) / rings
		var r0 := lerpf(28.0, 420.0, pow(f0, 2.2))
		var r1 := lerpf(28.0, 420.0, pow(f1, 2.2))
		var c := Color(0.36, 0.36, 0.38, 0.85).lerp(Color(0.25, 0.26, 0.28, 0.9), f0)
		mb.add_cylinder(Vector3(sin(f0 * 9.0) * 25.0, f0 * top, 0), Vector3(sin(f1 * 9.0) * 25.0, f1 * top, 0), r0, r1, 20, c, false)
		prev_r = r1
	_funnel = MeshInstance3D.new()
	_funnel.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	_funnel.material_override = m
	add_child(_funnel)
	# debris and dust whirling at the foot
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 6.0
	p.visibility_aabb = AABB(Vector3(-600, -50, -600), Vector3(1200, 900, 1200))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 90.0
	pm.emission_ring_inner_radius = 20.0
	pm.emission_ring_height = 10.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 60.0
	pm.orbit_velocity_min = 0.25
	pm.orbit_velocity_max = 0.5
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 8.0
	pm.scale_max = 22.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.32, 0.28, 0.22, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.35, 0.33, 0.3, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = GroundOps._soft_dot()
	q.material = qm
	p.draw_pass_1 = q
	add_child(p)


func _physics_process(delta: float) -> void:
	_t += delta
	wx += drift.x * delta
	wz += drift.y * delta
	var gy := Geo.ground_height(wx, wz)
	position = view.world_to_local(wx, gy - 5.0, wz)
	if _funnel:
		_funnel.rotation.y = fmod(_t * 1.8, TAU)
		_funnel.scale = Vector3(1.0 + sin(_t * 0.7) * 0.06, 1.0, 1.0 + cos(_t * 0.6) * 0.06)
	if ac == null or ac.crashed_state:
		return
	var rel := Vector2(ac.world_x() - wx, ac.world_z() - wz)
	var d := rel.length()
	var agl := ac.fdm.pos.y - gy
	if not _warned and d < 9000.0:
		_warned = true
		if session.has_signal("toast"):
			session.toast.emit("TORNADO WARNING: a tornado is on the ground %.0f km from you. Stay well clear!" % (d / 1000.0), "warning")
	if d > INFLUENCE or agl > top + 600.0:
		return
	# rotating, rising air: strongest near the core and near the ground
	var k := pow(1.0 - d / INFLUENCE, 2.0) * clampf(1.2 - agl / (top + 600.0), 0.2, 1.0)
	var tang := Vector3(-rel.y, 0.0, rel.x).normalized()
	var inward := Vector3(-rel.x, 0.0, -rel.y).normalized()
	ac.fdm.vel += (tang * 55.0 + inward * 12.0 + Vector3.UP * (30.0 + sin(_t * 3.1) * 25.0)) * k * delta
	var fwd := -ac.fdm.basis.z
	ac.fdm.basis = (Basis(fwd.normalized(), randf_range(-1.0, 1.0) * k * delta * 3.5) * ac.fdm.basis).orthonormalized()
	ac.turbulence = maxf(ac.turbulence, 2.0 * k)
	if d < CORE and agl < top:
		ac.call("_structural_failure", "flown into a tornado")
		ac.set_meta("breakup", "flown into a tornado")
		ac.call("_crash", {"cause_hint": "flew into a tornado", "tornado": true})
