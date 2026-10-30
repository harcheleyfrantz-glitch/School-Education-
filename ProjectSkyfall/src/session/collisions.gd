class_name Collisions
extends Node
## Solid objects around the player's aircraft: other aircraft (parked at gates, taxiing,
## landing, departing) and airport structures (terminals, the control tower, hangars and
## other buildings, jet bridges). Sample points on the player's airframe (nose, tail,
## wingtips, engines, fuselage) are tested against simple boxes each physics frame. A firm
## hit is an accident; a slow bump damages the aircraft and stops it.

const CRASH_SPEED := 6.0      # m/s closing speed above which an impact is an accident

var session: Node
var ac: Aircraft
var view: WorldView
var _cooldown := 0.0
var _probe: Array = []


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView) -> void:
	session = sess
	ac = aircraft
	view = world_view
	var spec: Dictionary = ac.spec
	var L := float(spec.length)
	var nose := -L * float(spec.cg_frac)
	var b := float(spec.span) * 0.5
	var fh := float(spec.fuse_h) * 0.5
	_probe = [["nose", Vector3(0, 0, nose + 0.3)], ["tail", Vector3(0, fh * 1.6, nose + L - 0.5)], ["left wingtip", Vector3(-b + 0.2, 0.4, 2.0)],
		["right wingtip", Vector3(b - 0.2, 0.4, 2.0)], ["fuselage", Vector3(0, 0, nose + L * 0.35)], ["fuselage", Vector3(0, 0, nose + L * 0.7)],
		["fin", Vector3(0, fh * 2.6, nose + L * 0.92)]]
	for e in FlightModel.engine_positions(spec):
		_probe.append(["engine", e])


func _physics_process(delta: float) -> void:
	if ac == null or ac.crashed_state:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var alt_agl := float(ac.ra)
	if alt_agl > 80.0:
		return
	var xf := ac.global_transform
	var pts := []
	for p in _probe:
		pts.append([p[0], xf * (p[1] as Vector3)])
	var hit := _hit_aircraft(pts)
	if hit.is_empty():
		hit = _hit_buildings(pts)
	if hit.is_empty():
		return
	var speed := ac.fdm.vel.length()
	if speed >= CRASH_SPEED:
		ac.set_meta("breakup", "collision")
		ac.call("_crash", {"cause_hint": "collided with %s" % String(hit.what), "collision": hit.what, "slide": speed < 25.0})
	else:
		# solid: the aircraft cannot push through, it stops against the obstacle
		ac.fdm.vel = -ac.fdm.vel.normalized() * 0.3 if speed > 0.05 else Vector3.ZERO
		ac.sys.brake_input = 1.0
		if _cooldown > 0.0:
			return
		_cooldown = 4.0
		ac.throttle_lever = 0.0
		var dmg: Dictionary = ac.damage
		dmg[String(hit.part).replace(" ", "_")] = true
		ac.set_meta("ground_collision", hit.what)
		if session and session.has_signal("toast"):
			session.toast.emit("Your %s struck %s. The aircraft is damaged - it needs an inspection before it can fly." % [hit.part, hit.what], "warning")


func _hit_aircraft(pts: Array) -> Dictionary:
	var tm = session.get("traffic") if session else null
	if tm == null:
		return {}
	for list in [tm.parked, tm.moving]:
		for item in list:
			var m = item.get("model")
			if m == null or not is_instance_valid(m) or not (m as Node3D).is_visible_in_tree():
				continue
			var mx: Transform3D = (m as Node3D).global_transform
			if mx.origin.distance_to(ac.global_position) > 90.0:
				continue
			var spec := AircraftTypes.get_type(String(item.get("type", "s320")))
			var inv := mx.affine_inverse()
			var L := float(spec.length)
			var nose := -L * float(spec.cg_frac)
			var fw := float(spec.fuse_w) * 0.5 + 0.3
			var fh := float(spec.fuse_h) * 0.5 + 0.3
			var b := float(spec.span) * 0.5
			for p in pts:
				var q: Vector3 = inv * (p[1] as Vector3)
				var in_body := absf(q.x) < fw and q.z > nose and q.z < nose + L and absf(q.y) < fh * 1.2 + (fh * 1.4 if q.z > nose + L * 0.85 else 0.0)
				var in_wing := absf(q.x) < b and absf(q.z - 1.5) < 3.0 and absf(q.y + fh * 0.3) < 1.2
				if in_body or in_wing:
					var who := "a parked %s" % String(spec.short) if String(item.get("phase", "")) == "parked" else "another aircraft (%s)" % String(item.get("callsign", spec.short))
					return {"what": who, "part": String(p[0])}
	return {}


func _hit_buildings(pts: Array) -> Dictionary:
	var icao := Airports.nearest(ac.world_x(), ac.world_z())
	if icao == "":
		return {}
	var av: AirportView = view.airports.get_view(icao)
	if av == null:
		return {}
	var L: Dictionary = av.layout
	var inv := av.global_transform.affine_inverse()
	for p in pts:
		var q: Vector3 = inv * (p[1] as Vector3)
		for bld in L.get("buildings", []):
			var c: Vector2 = bld.center
			var ax: Vector2 = (bld.axis as Vector2).normalized()
			var rel := Vector2(q.x, q.z) - c
			var along := rel.dot(ax)
			var across := rel.dot(Vector2(-ax.y, ax.x))
			if absf(along) < float(bld.len) * 0.5 and absf(across) < float(bld.depth) * 0.5 and q.y < float(bld.h):
				return {"what": {"terminal": "the terminal building", "fbo": "the general aviation terminal"}.get(String(bld.kind), "a %s building" % String(bld.kind)), "part": String(p[0])}
		var t: Vector2 = L.get("tower", Vector2(1e9, 1e9))
		if Vector2(q.x, q.z).distance_to(t) < 4.5 and q.y < float(L.get("tower_h", 30.0)) + 4.0:
			return {"what": "the control tower", "part": String(p[0])}
		for br in av.bridges:
			var cab: Node3D = br.cab
			var cl: Vector3 = cab.global_transform.affine_inverse() * (p[1] as Vector3)
			# a docked bridge's canopy rests against the door: only parked / swinging bridges are obstacles
			if not bool(br.docked) and absf(cl.x) < 1.8 and cl.z > -float(br.length) and cl.z < 3.2 and cl.y > -0.6 and cl.y < 3.0:
				return {"what": "a jet bridge", "part": String(p[0])}
	return {}
