class_name Escorts
extends Node3D
## Presidential transport: two fighter jets fly in formation off the player's wingtips. Every
## few minutes an unidentified aircraft (a hostile drone) closes in; an escort breaks away,
## intercepts it and shoots it down, then rejoins. The fighters are solid: hit one and it is a
## mid-air collision.

const OFFSETS := [Vector3(-70.0, 6.0, 55.0), Vector3(70.0, 6.0, 55.0)]

var session: Node
var ac: Aircraft
var view: WorldView
var jets: Array = []        # {node, vel, state: formation/intercept/return/destroyed, slot}
var threats: Array = []     # {node, vel, hunter}
var intercepts := 0
var _threat_t := 0.0
var _rng := RandomNumberGenerator.new()
var _joined := false


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView) -> void:
	session = sess
	ac = aircraft
	view = world_view
	_rng.randomize()
	_threat_t = _rng.randf_range(70.0, 120.0)
	for i in 2:
		var n := _fighter_mesh()
		view.dynamic_root.add_child(n)
		n.global_position = ac.global_position + ac.global_transform.basis * (OFFSETS[i] + Vector3(0, 300, 900))
		n.global_basis = ac.global_basis
		jets.append({"node": n, "vel": ac.fdm.vel, "state": "joining", "slot": i, "callsign": "Viper %d" % (i + 1)})


static func _fighter_mesh() -> Node3D:
	var mb := MeshBuilder.new()
	var grey := Color(0.5, 0.53, 0.56)
	var dark := Color(0.32, 0.34, 0.37)
	mb.add_cylinder(Vector3(0, 0, -8.5), Vector3(0, 0, -5.0), 0.05, 0.75, 12, grey)
	mb.add_cylinder(Vector3(0, 0, -5.0), Vector3(0, 0, 6.5), 0.75, 0.6, 14, grey)
	mb.add_cylinder(Vector3(0, 0, 6.5), Vector3(0, 0, 7.4), 0.6, 0.5, 12, Color(0.15, 0.15, 0.16))
	mb.add_sphere(Vector3(0, 0.6, -4.2), Vector3(0.45, 0.4, 1.4), 10, 6, Color(0.2, 0.3, 0.38))
	for sx in [-1.0, 1.0]:
		var wing := PackedVector3Array([Vector3(sx * 0.6, 0, -2.5), Vector3(sx * 5.2, 0, 3.0), Vector3(sx * 5.2, 0, 4.2), Vector3(sx * 0.6, 0, 4.5)])
		mb.add_quad(wing[0], wing[1], wing[2], wing[3], grey)
		mb.add_quad(wing[3], wing[2], wing[1], wing[0], dark)
		var st := PackedVector3Array([Vector3(sx * 0.5, 0, 5.4), Vector3(sx * 2.6, 0, 6.9), Vector3(sx * 2.6, 0, 7.5), Vector3(sx * 0.5, 0, 7.4)])
		mb.add_quad(st[0], st[1], st[2], st[3], grey)
		mb.add_quad(st[3], st[2], st[1], st[0], dark)
		var fin := PackedVector3Array([Vector3(sx * 0.5, 0.5, 4.2), Vector3(sx * 1.1, 3.0, 6.6), Vector3(sx * 1.1, 3.0, 7.3), Vector3(sx * 0.5, 0.5, 7.2)])
		mb.add_quad(fin[0], fin[1], fin[2], fin[3], grey)
		mb.add_quad(fin[3], fin[2], fin[1], fin[0], dark)
		mb.add_box(Vector3(sx * 0.9, -0.3, -1.5), Vector3(0.5, 0.6, 2.4), dark)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.4
	m.roughness = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	var root := Node3D.new()
	root.name = "Fighter"
	root.add_child(mi)
	# afterburner glow
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.25)
	glow.light_energy = 1.5
	glow.omni_range = 9.0
	glow.position = Vector3(0, 0, 8.0)
	root.add_child(glow)
	return root


func boxes() -> Array:
	## For collisions: each live fighter as a centre and radius.
	var out := []
	for j in jets:
		if String(j.state) != "destroyed":
			out.append(j)
	return out


func _steer(j: Dictionary, target: Vector3, target_vel: Vector3, max_speed: float, delta: float) -> void:
	var n: Node3D = j.node
	var to := target - n.global_position
	var want := target_vel + to * 0.6
	if want.length() > max_speed:
		want = want.normalized() * max_speed
	var v: Vector3 = (j.vel as Vector3).lerp(want, clampf(delta * 1.6, 0.0, 1.0))
	j.vel = v
	n.global_position += v * delta
	if v.length() > 5.0:
		var up := Vector3.UP + (want - v) * 0.02
		n.global_basis = n.global_basis.slerp(Basis.looking_at(v.normalized(), up.normalized()), clampf(delta * 3.0, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if ac == null:
		return
	var axf := ac.global_transform
	for j in jets:
		match String(j.state):
			"joining", "formation", "return":
				var slot := axf * (OFFSETS[int(j.slot)] as Vector3)
				_steer(j, slot, ac.fdm.vel, 320.0, delta)
				var d := (j.node as Node3D).global_position.distance_to(slot)
				if String(j.state) != "formation" and d < 25.0:
					if String(j.state) == "joining" and not _joined:
						_joined = true
						_say("Viper flight, joined up. We have you, %s." % _callsign())
					j.state = "formation"
			"intercept":
				var th: Dictionary = j.get("target", {})
				if th.is_empty() or not is_instance_valid(th.get("node")):
					j.state = "return"
					continue
				var tn: Node3D = th.node
				_steer(j, tn.global_position, th.vel, 420.0, delta)
				if (j.node as Node3D).global_position.distance_to(tn.global_position) < 700.0:
					_shoot_down(th, j)
					j.state = "return"
	if ac.crashed_state:
		return
	# hostile drones
	if _joined:
		_threat_t -= delta
		if _threat_t <= 0.0 and threats.is_empty():
			_threat_t = _rng.randf_range(110.0, 200.0)
			_spawn_threat()
	for th in threats.duplicate():
		var tn: Node3D = th.node
		if not is_instance_valid(tn):
			threats.erase(th)
			continue
		var to := ac.global_position - tn.global_position
		th.vel = (th.vel as Vector3).lerp(to.normalized() * 180.0, clampf(delta * 0.4, 0.0, 1.0))
		tn.global_position += (th.vel as Vector3) * delta
		tn.look_at(tn.global_position + (th.vel as Vector3), Vector3.UP)
		if to.length() < 60.0:
			# it got through: it strikes the aircraft
			threats.erase(th)
			_explode(tn.global_position, 1.0)
			tn.queue_free()
			ac.set_meta("breakup", "struck by a hostile drone")
			ac.call("_crash", {"cause_hint": "struck by a hostile drone", "attack": true, "midair": true, "collision": "a hostile drone"})


func _callsign() -> String:
	return String(session.get("callsign")) if session.get("callsign") != null else "Calderra One"


func _say(text: String) -> void:
	var atc: Node = session.get("atc")
	if atc and atc.has_method("traffic_advisory"):
		atc.call("traffic_advisory", text, text)
	if session.has_signal("toast"):
		session.toast.emit(text, "caution")


func _spawn_threat() -> void:
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3(0, 0, -2.0), Vector3(0, 0, 2.0), 0.35, 0.3, 10, Color(0.22, 0.23, 0.2))
	mb.add_box(Vector3(0, 0, 0.3), Vector3(5.0, 0.08, 0.9), Color(0.25, 0.26, 0.22))
	mb.add_box(Vector3(0, 0.4, 1.8), Vector3(0.08, 0.8, 0.6), Color(0.25, 0.26, 0.22))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	view.dynamic_root.add_child(mi)
	var fwd := -ac.global_transform.basis.z
	fwd.y = 0.0
	var side := Vector3(fwd.z, 0, -fwd.x)
	mi.global_position = ac.global_position + fwd.normalized() * 7000.0 + side.normalized() * _rng.randf_range(-3000.0, 3000.0) + Vector3(0, _rng.randf_range(-200.0, 300.0), 0)
	var th := {"node": mi, "vel": (ac.global_position - mi.global_position).normalized() * 180.0}
	threats.append(th)
	# the nearest free escort goes after it
	var best: Dictionary = {}
	for j in jets:
		if String(j.state) == "formation":
			best = j
			break
	if best.is_empty():
		return
	best.state = "intercept"
	best.target = th
	_say("%s: unidentified aircraft inbound, %d miles, not responding. %s breaking right to intercept." % [String(best.callsign), int(7000.0 / 1852.0), String(best.callsign)])


func _shoot_down(th: Dictionary, j: Dictionary) -> void:
	var tn: Node3D = th.node
	threats.erase(th)
	_explode(tn.global_position, 0.6)
	tn.queue_free()
	intercepts += 1
	_say("%s: Fox two... splash one. Threat destroyed. Rejoining." % String(j.callsign))


func _explode(at: Vector3, scale: float) -> void:
	var pieces: WreckPieces = session.call("wreck_pieces") if session.has_method("wreck_pieces") else null
	if pieces == null:
		return
	var f := pieces._flames(3.0 * scale)
	f.one_shot = true
	f.explosiveness = 0.9
	view.dynamic_root.add_child(f)
	f.global_position = at
	var sm := pieces._trail(2.0 * scale, true)
	view.dynamic_root.add_child(sm)
	sm.global_position = at
	sm.one_shot = true
	get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(f):
			f.queue_free()
		if is_instance_valid(sm):
			sm.queue_free())


func hit_jet(j: Dictionary) -> void:
	## The player flew into an escort: it is destroyed.
	j.state = "destroyed"
	var n: Node3D = j.node
	_explode(n.global_position, 1.0)
	var pieces: WreckPieces = session.call("wreck_pieces") if session.has_method("wreck_pieces") else null
	if pieces:
		pieces.add_piece(n, j.vel, Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2), _rng.randf_range(-3, 3)),
			{"drag": 0.003, "rest_h": 0.8, "bounce": 0.1, "smoke": true, "fire": true, "big": true})
