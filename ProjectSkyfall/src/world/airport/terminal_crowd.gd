class_name TerminalCrowd
extends Node3D
## The people in a departures hall: travellers pulling roller bags between check-in, shops,
## cafés and gates, queues at the check-in desks and security lanes, passengers waiting
## (reading, on their phones, asleep) on the gate seating, and staff at the desks and lanes.
## One Crowd batch in the terminal's frame; walkers steer with TerminalInterior.resolve.

const SPEED := 1.25

var ti: TerminalInterior
var crowd: Crowd
var people: Array = []
var _r := RandomNumberGenerator.new()
var _goals: Array = []
var _t := 0.0


func setup(terminal: TerminalInterior, count: int, seed_v: int) -> void:
	ti = terminal
	_r.seed = seed_v
	name = "TerminalCrowd"
	var lod := 0 if String(Game.settings.get("quality", "high")) in ["high", "ultra"] else 1
	crowd = Crowd.new()
	add_child(crowd)
	crowd.setup(count, lod, "", lod == 0)
	CabinInterior.tag_interior(crowd)
	for sp in ti.spots:
		if String(sp.kind) in ["cafe", "shop", "checkin", "fids", "gate_podium", "toilet"]:
			_goals.append(Vector2((sp.p as Vector3).x, (sp.p as Vector3).z))
	var n_seated := int(count * 0.38)
	var n_queue := int(count * 0.17)
	var n_staff := mini(int(count * 0.08), 16)
	var free_seats := ti.seats.duplicate()
	for i in count:
		var p := {"i": i, "id": 300000 + seed_v % 10000 * 50 + i, "mode": "walk", "pos": Vector2.ZERO, "yaw": 0.0, "goal": Vector2.ZERO,
			"wait": 0.0, "pose": "walk", "phase": _r.randf()}
		var ap := Crowd.appearance_for({"id": int(p.id), "gender": "f" if _r.randf() < 0.5 else "m", "age": _r.randi_range(8, 80)})
		p.ap = ap
		p.flags = int(ap.flags)
		if i < n_seated and not free_seats.is_empty():
			var s: Dictionary = free_seats.pop_at(_r.randi() % free_seats.size())
			s.taken = true
			var xf: Transform3D = s.xf
			p.mode = "sit"
			p.pose = ["sit", "sit_read", "sit_sleep", "sit_film", "sit_talk"][_r.randi() % 5]
			if String(p.pose) == "sit_film":
				p.flags = int(p.flags) | Crowd.FLAG_PHONE
			p.xf = Transform3D(xf.basis, xf.origin + xf.basis.z * -0.02)
		elif i < n_seated + n_queue:
			var q := _queue_spot()
			p.mode = "stand"
			p.pose = "stand" if _r.randf() < 0.7 else "talk"
			p.pos = q[0]
			p.yaw = q[1]
			p.flags = int(p.flags) | (Crowd.FLAG_BAG if _r.randf() < 0.6 else 0)
		elif i < n_seated + n_queue + n_staff:
			var st := _staff_spot(i - n_seated - n_queue)
			p.mode = "stand"
			p.pose = "stand"
			p.pos = st[0]
			p.yaw = st[1]
			p.ap = Crowd.staff_appearance(int(st[2]), int(p.id))
			p.flags = int(p.ap.flags)
		else:
			p.pos = _random_floor()
			p.goal = _pick_goal()
			if _r.randf() < 0.55:
				p.flags = int(p.flags) | Crowd.FLAG_BAG
		people.append(p)
		_write(p)
	crowd.flush()


func _write(p: Dictionary) -> void:
	var ap: Dictionary = p.ap
	var xf: Transform3D
	if p.has("xf"):
		xf = p.xf
	else:
		xf = Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(p.pos.x, TerminalInterior.FLOOR, p.pos.y))
	xf = xf.scaled_local(Vector3.ONE * float(ap.get("scale", 1.0)))
	var pose := int(HumanMesh.POSES.get(String(p.pose), 0))
	var rate := 0.9 if String(p.pose) == "walk" else 0.25
	crowd.set_person(int(p.i), xf, pose, float(p.phase), rate, ap.top, int(ap.outfit), float(ap.seed), int(p.flags), float(ap.build))


func _process(delta: float) -> void:
	if ti == null or not is_visible_in_tree():
		return
	_t += delta
	for p in people:
		if String(p.mode) != "walk":
			continue
		if float(p.wait) > 0.0:
			p.wait = float(p.wait) - delta
			if float(p.wait) <= 0.0:
				p.pose = "walk"
				p.goal = _pick_goal()
			_write(p)
			continue
		var pos: Vector2 = p.pos
		var to: Vector2 = (p.goal as Vector2) - pos
		if to.length() < 1.2:
			p.wait = _r.randf_range(4.0, 25.0)
			p.pose = "stand" if _r.randf() < 0.75 else "film"
			_write(p)
			continue
		var step := to.normalized() * SPEED * delta
		var np := ti.resolve(pos, pos + step, 0.28)
		if np == pos:
			# blocked: sidestep, or give up on this goal
			np = ti.resolve(pos, pos + Vector2(-step.y, step.x) * 1.5, 0.28)
			if np == pos:
				p.goal = _pick_goal()
		p.pos = np
		var mv := np - pos
		if mv.length() > 0.0001:
			p.yaw = lerp_angle(float(p.yaw), atan2(-mv.x, -mv.y), clampf(delta * 6.0, 0.0, 1.0))
		_write(p)
	crowd.flush()


func _pick_goal() -> Vector2:
	if _goals.is_empty() or _r.randf() < 0.3:
		return _random_floor()
	var g: Vector2 = _goals[_r.randi() % _goals.size()]
	return g + Vector2(_r.randf_range(-2.0, 2.0), _r.randf_range(-2.0, 2.0))


func _random_floor() -> Vector2:
	for k in 20:
		var p := Vector2(_r.randf_range(-ti.depth * 0.45, ti.depth * 0.45), _r.randf_range(-ti.length * 0.45, ti.length * 0.45))
		if ti.walkable(p, 0.4):
			return p
	return Vector2(ti.entrance.x, ti.entrance.z)


func _queue_spot() -> Array:
	var qs := ti.spots.filter(func(s): return String(s.kind) in ["checkin", "security", "cafe"])
	if qs.is_empty():
		return [_random_floor(), 0.0]
	var s: Dictionary = qs[_r.randi() % qs.size()]
	var sp: Vector3 = s.p
	# a line stretching away from the desk, toward the middle of the hall
	var away := Vector2(-sp.x, -sp.z).normalized() if Vector2(sp.x, sp.z).length() > 1.0 else Vector2(0, 1)
	var k := _r.randi_range(1, 6)
	var p := Vector2(sp.x, sp.z) + away * (0.9 * k) + Vector2(-away.y, away.x) * _r.randf_range(-0.25, 0.25)
	return [p, atan2(away.x, away.y)]


func _staff_spot(k: int) -> Array:
	var podiums := ti.spots.filter(func(s): return String(s.kind) == "gate_podium")
	var lanes := ti.spots.filter(func(s): return String(s.kind) == "security")
	if k % 2 == 0 and not podiums.is_empty():
		var pd: Dictionary = podiums[(k / 2) % podiums.size()]
		var pp: Vector3 = pd.p
		return [Vector2(pp.x, pp.z) + Vector2(0.0, 0.6), PI * 0.5, Crowd.Outfit.CABIN]
	if not lanes.is_empty():
		var ln: Dictionary = lanes[(k / 2) % lanes.size()]
		var lp: Vector3 = ln.p
		return [Vector2(lp.x, lp.z) + Vector2(1.2, 0.0), -PI * 0.5, Crowd.Outfit.POLICE]
	return [_random_floor(), 0.0, Crowd.Outfit.OFFICIAL]
