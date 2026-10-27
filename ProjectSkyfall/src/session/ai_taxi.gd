class_name AITaxi
extends RefCounted
## Taxis the aircraft through the real ground model: pure-pursuit nose-wheel steering along the
## taxi graph, speed held with thrust and brakes, slowing for turns, holding short, lining up and
## parking on the stand. Used for passenger flights (the crew taxis) and the player's auto-taxi.

var session: Node
var ac: Aircraft
var active := false
var pts: Array = []              # world (x, z) Vector2 points
var max_speed := 8.5             # m/s (~16 kt)
var stage := ""                  # "" | out | lineup | lined_up | in | parked
var hold_wait := 0.0
var _hold_index := -1
var _end_heading := -1.0


func setup(sess: Node, aircraft: Aircraft) -> void:
	session = sess
	ac = aircraft


func _icao_dep() -> String:
	return String(session.get("dep_icao"))


func _icao_arr() -> String:
	return String(session.get("arr_icao"))


func _to_world(icao: String, p: Vector2) -> Vector2:
	var ap: Dictionary = Airports.get_ap(icao)
	return Vector2(float(ap.x) + p.x, float(ap.z) + p.y)


func _here_local(icao: String) -> Vector2:
	var ap: Dictionary = Airports.get_ap(icao)
	return Vector2(ac.world_x() - float(ap.x), ac.world_z() - float(ap.z))


# ================================================================== routes
func plan_out() -> bool:
	## Stand/pushback point -> holding point -> line up on the departure runway.
	var icao := _icao_dep()
	var end: Dictionary = session.get("dep_end")
	var L := AirportLayout.get_layout(icao)
	var from := AirportLayout.nearest_node(L, _here_local(icao), ["apron", "taxi"])
	var hold := AirportLayout.hold_node_for(L, String(end.name))
	if from < 0 or hold < 0:
		return false
	var path := AirportLayout.find_path(L, from, hold)
	if path.is_empty():
		return false
	pts.clear()
	for step in path:
		pts.append(_to_world(icao, L.taxi_nodes[int(step.node)].pos))
	_hold_index = pts.size() - 1
	_hold_index -= _trim_start()
	var dir := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
	var thr := Vector2(float(end.thr_x), float(end.thr_z))
	pts.append(thr + dir * 60.0)
	pts.append(thr + dir * 130.0)
	pts.append(thr + dir * 230.0)
	_end_heading = float(end.hdg)
	stage = "out"
	active = true
	max_speed = 8.5 if ac.spec.category != "trainer" else 6.0
	session.set("taxi_path", path)
	return true


func plan_in() -> bool:
	## Runway exit -> arrival stand, stopping with the nose at the stop line.
	var icao := _icao_arr()
	var L := AirportLayout.get_layout(icao)
	var sd := AirportLayout.stand_by_name(L, String(session.get("arr_stand")))
	if sd.is_empty():
		return false
	var from := AirportLayout.nearest_node(L, _here_local(icao), ["rwy", "taxi", "hold"])
	var path := AirportLayout.find_path(L, from, int(sd.lane_node), true)
	if path.is_empty():
		return false
	pts.clear()
	for step in path:
		pts.append(_to_world(icao, L.taxi_nodes[int(step.node)].pos))
	var n: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	var cg_from_nose := float(ac.spec.length) * float(ac.spec.cg_frac)
	var park := face + n * (7.0 + (2.0 if ac.spec.category == "widebody" else 0.0) + cg_from_nose)
	pts.append(_to_world(icao, park + n * 25.0))
	pts.append(_to_world(icao, park))
	_trim_start()
	_hold_index = -1
	_end_heading = float(sd.hdg)
	stage = "in"
	active = true
	max_speed = 8.0 if ac.spec.category != "trainer" else 5.5
	session.set("taxi_path", path)
	return true


func _trim_start() -> int:
	## Joins the route at the segment nearest to the aircraft instead of driving back to a node
	## behind it (after a pushback the aircraft already sits on the lane). Returns points removed.
	var p := Vector2(ac.world_x(), ac.world_z())
	var best := 0
	var bd := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < bd - 0.5:
			bd = d
			best = i
	# never start on a point behind the nose
	var hdg := deg_to_rad(ac.fdm.heading_deg())
	var fwd := Vector2(sin(hdg), -cos(hdg))
	var removed := 0
	for k in best + 1:
		if pts.size() > 1:
			pts.pop_front()
			removed += 1
	while pts.size() > 1 and fwd.dot((pts[0] as Vector2) - p) < 5.0:
		pts.pop_front()
		removed += 1
	return removed


# ================================================================== driving
func update(dt: float) -> bool:
	## Drives the current route. Returns true once stopped at its end.
	if not active:
		return true
	ac.player_controlled = false
	var p := Vector2(ac.world_x(), ac.world_z())
	var gs := ac.fdm.ground_speed()
	# drop points we have passed
	while pts.size() > 1 and p.distance_to(pts[0]) < 9.0:
		pts.pop_front()
		if _hold_index >= 0:
			_hold_index -= 1
	var end_dist := _remaining(p)
	var hold_dist := _dist_to_index(p, _hold_index) if _hold_index >= 0 else INF
	# hold short until cleared (ATC) or the runway is free
	var must_hold := _hold_index >= 0 and stage == "out" and not _cleared_onto_runway()
	var look := clampf(gs * 2.6, 14.0, 34.0)
	var target := _lookahead(p, look)
	var hdg := deg_to_rad(ac.fdm.heading_deg())
	var fwd := Vector2(sin(hdg), -cos(hdg))
	var to := target - p
	var alpha := fwd.angle_to(to) if to.length() > 0.5 else 0.0
	var wheelbase := absf(float(ac.spec.nose_gear_x) - float(ac.spec.main_gear_x))
	var delta := atan(2.0 * wheelbase * sin(alpha) / maxf(look, 1.0))
	ac.in_tiller = clampf(delta / deg_to_rad(70.0), -1.0, 1.0)
	ac.in_yaw = 0.0
	# target speed: slow for turns ahead, for the hold line and for the end of the route
	var turn := _turn_ahead(p, 45.0)
	var v_t := lerpf(max_speed, 3.2, clampf(turn / 80.0, 0.0, 1.0))
	# braking profile: arrive at the end of the route (or the hold line) at walking pace
	v_t = minf(v_t, sqrt(2.0 * 0.55 * maxf(end_dist - 1.5, 0.0)) + 0.2)
	if must_hold:
		v_t = minf(v_t, sqrt(2.0 * 0.55 * maxf(hold_dist - 6.0, 0.0)))
	# at (or past) the last point: stop straight ahead, firmly
	if _stopping or end_dist < 3.0 or (pts.size() == 1 and fwd.dot((pts[0] as Vector2) - p) < 1.0 and end_dist < 60.0):
		_stopping = true
		ac.in_tiller = 0.0
		ac.throttle_lever = 0.0
		ac.sys.brake_input = 0.7
		if gs > 0.25:
			return false
		end_dist = 0.0
	else:
		_drive_speed(gs, v_t, dt)
	if must_hold and hold_dist < 8.0 and gs < 0.3:
		ac.sys.brake_input = 0.6
		return false
	if end_dist < 3.0 and gs < 0.5:
		_stopping = false
		ac.throttle_lever = 0.0
		ac.sys.brake_input = 0.0
		ac.sys.parking_brake = true
		ac.in_tiller = 0.0
		active = false
		stage = "lined_up" if stage == "out" else "parked"
		return true
	return false


var _thr_i := 0.0
var _stopping := false


func _drive_speed(gs: float, v_t: float, dt: float) -> void:
	ac.sys.parking_brake = false
	var err := v_t - gs
	var jets: bool = ac.spec.category != "trainer"
	_thr_i = clampf(_thr_i + err * dt * 0.015, -0.1, 0.3)
	if err > 0.4:
		var breakaway := 0.32 if gs < 0.6 else 0.1
		ac.throttle_lever = move_toward(ac.throttle_lever, clampf(breakaway + err * 0.08 + _thr_i, 0.0, 0.5 if jets else 0.6), dt * 0.5)
		ac.sys.brake_input = 0.0
	elif err < -0.6:
		ac.throttle_lever = move_toward(ac.throttle_lever, 0.0, dt)
		ac.sys.brake_input = clampf(-err * 0.3, 0.1, 1.0)
		_thr_i = minf(_thr_i, 0.0)
	else:
		ac.throttle_lever = move_toward(ac.throttle_lever, 0.06 if jets else 0.1, dt * 0.3)
		ac.sys.brake_input = 0.0


func _cleared_onto_runway() -> bool:
	var atc: AtcController = session.get("atc")
	if atc and (bool(atc.clearance.get("lineup", false)) or bool(atc.clearance.get("takeoff", false))):
		return true
	if atc and atc.auto_atc:
		return false
	return atc == null


func _lookahead(p: Vector2, dist: float) -> Vector2:
	var acc := 0.0
	var prev := p
	for q in pts:
		var seg: float = prev.distance_to(q)
		if acc + seg >= dist:
			return prev.lerp(q, (dist - acc) / maxf(seg, 0.001))
		acc += seg
		prev = q
	return pts[pts.size() - 1] if not pts.is_empty() else p


func _remaining(p: Vector2) -> float:
	var d := 0.0
	var prev := p
	for q in pts:
		d += prev.distance_to(q)
		prev = q
	return d


func _dist_to_index(p: Vector2, idx: int) -> float:
	if idx < 0 or idx >= pts.size():
		return INF
	var d := 0.0
	var prev := p
	for i in idx + 1:
		d += prev.distance_to(pts[i])
		prev = pts[i]
	return d


func _turn_ahead(p: Vector2, within: float) -> float:
	## Largest heading change (deg) at the route vertices within the given distance.
	var best := 0.0
	var acc := 0.0
	var prev := p
	var hdg := deg_to_rad(ac.fdm.heading_deg())
	var prev_dir := Vector2(sin(hdg), -cos(hdg))
	for i in pts.size():
		var q: Vector2 = pts[i]
		var seg := q - prev
		if seg.length() > 0.5:
			best = maxf(best, absf(rad_to_deg(prev_dir.angle_to(seg))))
			prev_dir = seg.normalized()
		acc += seg.length()
		prev = q
		if acc > within:
			break
	return best


# ================================================================== session helpers
func update_out(dt: float) -> bool:
	## Called each frame after the pushback in passenger mode: taxi out, hold, line up.
	## Returns true once lined up and stopped (the crew then starts the takeoff).
	if stage == "":
		if not plan_out():
			return true
	if stage == "lined_up":
		# make sure we really are on the centreline and pointing down the runway
		var end: Dictionary = session.get("dep_end")
		var dh := absf(U.angle_diff_deg(float(end.hdg), ac.fdm.heading_deg()))
		var dir := Vector2(sin(deg_to_rad(float(end.hdg))), -cos(deg_to_rad(float(end.hdg))))
		var rel := Vector2(ac.world_x() - float(end.thr_x), ac.world_z() - float(end.thr_z))
		var lat := absf(rel.dot(Vector2(-dir.y, dir.x)))
		if dh < 8.0 and lat < 6.0:
			return true
		var along := rel.dot(dir)
		pts = [Vector2(end.thr_x, end.thr_z) + dir * (along + 120.0), Vector2(end.thr_x, end.thr_z) + dir * (along + 260.0)]
		_hold_index = -1
		stage = "out"
		active = true
	return update(dt)


func update_in(dt: float) -> void:
	if stage in ["", "lined_up"]:
		if not plan_in():
			stage = "parked"
			return
	if stage == "parked":
		ac.sys.parking_brake = true
		for e in ac.sys.eng:
			e.cutoff = true
		return
	update(dt)
