class_name CameraRig
extends Node3D
## All in-flight camera modes. Cockpit and cabin views ride in the aircraft frame with head
## look, g-force head motion and touchdown shake; external views follow smoothly.

signal mode_changed(mode: String)

const MODES := ["cockpit", "chase", "orbit", "tower", "flyby", "wing", "cabin"]

var cam: Camera3D
var ac: Aircraft
var view: WorldView
var mode := "cockpit"
var look_yaw := 0.0          # degrees, + = left
var look_pitch := -8.0       # degrees, + = up
var fov_base := 72.0
var zoom := 1.0
var head_local := Vector3.ZERO        # cockpit / seat eye point (body frame)
var seat_local := Vector3.ZERO
var walker: Node3D = null             # set when walking
var orbit_yaw := 160.0
var orbit_pitch := 12.0
var orbit_dist := 40.0
var shake := 0.0
var _head_off := Vector3.ZERO
var _head_vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _chase_pos := Vector3.ZERO
var _flyby_pos := Vector3.ZERO
var _flyby_t := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
## Walking in third person: the player's skinned avatar is shown and the camera follows it
## over the shoulder (V toggles).
var third_person := false
var avatar: SkinnedHuman = null
var avatar_look := {}
var _tp_pos := Vector3.ZERO
var _tp_valid := false
var _av_last := Vector3.ZERO
var _av_seated := false


func setup(aircraft: Aircraft, world_view: WorldView, cockpit_eye: Vector3) -> void:
	ac = aircraft
	view = world_view
	head_local = cockpit_eye
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.02
	cam.far = float(Game.q("view")) * 1.2
	cam.fov = fov_base
	add_child(cam)
	cam.current = true
	view.camera = cam
	_chase_pos = ac.global_position + Vector3(0, 10, 30)


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	if ac:
		ac.input_enabled = m != "walk"
	if avatar:
		avatar.visible = m == "walk" and third_person
	_tp_valid = false
	match m:
		"cockpit":
			look_yaw = 0.0
			look_pitch = -8.0
			cam.near = 0.02
		"cabin":
			# a window seat looks half out of the window to start with
			look_yaw = 35.0 if seat_local.x < -0.4 else (-35.0 if seat_local.x > 0.4 else 0.0)
			look_pitch = -4.0
			cam.near = 0.02
		"chase", "orbit":
			cam.near = 0.3
			_chase_pos = cam.global_position
			orbit_dist = maxf(float(ac.spec.length) * 1.3, 18.0)
		"tower", "flyby":
			cam.near = 0.5
			_flyby_t = 0.0
		"wing":
			cam.near = 0.05
	mode_changed.emit(m)


func cycle(dir: int = 1) -> void:
	var i := MODES.find(mode)
	set_mode(MODES[posmod(i + dir, MODES.size())])


func is_inside() -> bool:
	return mode in ["cockpit", "cabin", "walk"]


func look(dx: float, dy: float) -> void:
	## Mouse / touch look in degrees.
	match mode:
		"orbit", "chase":
			orbit_yaw = fmod(orbit_yaw - dx, 360.0)
			orbit_pitch = clampf(orbit_pitch + dy, -10.0, 80.0)
		_:
			look_yaw = clampf(look_yaw - dx, -165.0, 165.0)
			look_pitch = clampf(look_pitch + dy, -75.0, 70.0)


func zoom_by(f: float) -> void:
	if mode in ["orbit", "chase"]:
		orbit_dist = clampf(orbit_dist * f, 6.0, 900.0)
	else:
		zoom = clampf(zoom * f, 0.35, 1.25)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func _process(delta: float) -> void:
	if ac == null or cam == null:
		return
	_t += delta
	shake = move_toward(shake, 0.0, delta * 1.5)
	var body := ac.global_transform
	match mode:
		"cockpit", "cabin":
			_inside_cam(delta, body, head_local if mode == "cockpit" else seat_local)
		"walk":
			if walker:
				if third_person:
					_third_person_cam(delta)
				else:
					var head: Transform3D = walker.get("head_transform") if walker.get("head_transform") != null else walker.global_transform
					cam.global_transform = head
					cam.fov = fov_base * zoom
		"chase":
			var back := body.basis.z.normalized()
			var flat_back := Vector3(back.x, 0, back.z).normalized()
			if flat_back.length() < 0.1:
				flat_back = Vector3.BACK
			var want := ac.global_position + flat_back.rotated(Vector3.UP, deg_to_rad(orbit_yaw - 180.0)) * orbit_dist + Vector3(0, orbit_dist * sin(deg_to_rad(orbit_pitch)) + float(ac.spec.height) * 0.4, 0)
			_chase_pos = _chase_pos.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
			cam.global_position = _chase_pos
			cam.look_at(ac.global_position + Vector3(0, float(ac.spec.height) * 0.3, 0), Vector3.UP)
			cam.fov = 60.0 * zoom
		"orbit":
			var dir := Vector3(sin(deg_to_rad(orbit_yaw)) * cos(deg_to_rad(orbit_pitch)), sin(deg_to_rad(orbit_pitch)), cos(deg_to_rad(orbit_yaw)) * cos(deg_to_rad(orbit_pitch)))
			cam.global_position = ac.global_position + dir * orbit_dist
			_keep_above_ground()
			cam.look_at(ac.global_position, Vector3.UP)
			cam.fov = 60.0
		"tower":
			var tp := _tower_point()
			cam.global_position = tp
			cam.look_at(ac.global_position, Vector3.UP)
			var d := tp.distance_to(ac.global_position)
			cam.fov = clampf(rad_to_deg(2.0 * atan(float(ac.spec.span) * 1.4 / maxf(d, 1.0))), 2.0, 50.0)
		"flyby":
			_flyby_t -= delta
			var to_ac := ac.global_position - _flyby_pos
			if _flyby_t <= 0.0 or (to_ac.length() > 1600.0 and to_ac.dot(ac.fdm.vel) > 0.0):
				var ahead := ac.fdm.vel.normalized() if ac.fdm.vel.length() > 5.0 else -body.basis.z
				_flyby_pos = ac.global_position + ahead * clampf(ac.fdm.vel.length() * 8.0, 60.0, 1200.0) + ahead.cross(Vector3.UP).normalized() * float(ac.spec.span) * 1.6 + Vector3(0, 6, 0)
				_flyby_t = 14.0
			cam.global_position = _flyby_pos
			_keep_above_ground()
			cam.look_at(ac.global_position, Vector3.UP)
			cam.fov = clampf(rad_to_deg(2.0 * atan(float(ac.spec.length) * 1.6 / maxf(cam.global_position.distance_to(ac.global_position), 1.0))), 4.0, 70.0)
		"wing":
			var tip := Vector3(float(ac.spec.span) * 0.08 + float(ac.spec.fuse_w) * 0.55, float(ac.spec.fuse_h) * 0.18, -float(ac.spec.length) * 0.02)
			var xf := body * Transform3D(Basis(), tip)
			cam.global_transform = xf * Transform3D(Basis.from_euler(Vector3(deg_to_rad(look_pitch * 0.5 - 6.0), deg_to_rad(look_yaw - 95.0), 0)), Vector3.ZERO)
			cam.fov = 70.0
	if shake > 0.001:
		cam.global_position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake * 0.02


func _inside_cam(delta: float, body: Transform3D, eye: Vector3) -> void:
	# head motion from accelerations felt in the body frame (springy, lags behind the airframe)
	var vel := ac.fdm.vel
	var acc := (vel - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = vel
	var acc_body := body.basis.inverse() * (acc + Vector3(0, 9.81, 0))
	var target := Vector3(-acc_body.x * 0.0035, -(acc_body.y - 9.81) * 0.004, -acc_body.z * 0.003)
	target = target.limit_length(0.06)
	var k := 60.0
	var c := 11.0
	_head_vel += ((target - _head_off) * k - _head_vel * c) * delta
	_head_off += _head_vel * delta
	var turb := float(ac.turbulence)
	var buffet := Vector3.ZERO
	if turb > 0.05 or shake > 0.0:
		var amp := turb * 0.012 + shake * 0.01
		buffet = Vector3(sin(_t * 23.0) * 0.4, sin(_t * 31.0 + 1.0), sin(_t * 17.0 + 2.0) * 0.3) * amp
	var local := Transform3D(Basis.from_euler(Vector3(deg_to_rad(look_pitch), deg_to_rad(look_yaw), 0), EULER_ORDER_YXZ), eye + _head_off + buffet)
	cam.global_transform = body * local
	cam.fov = fov_base * zoom


func _unhandled_key_input(event: InputEvent) -> void:
	if mode == "walk" and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_V:
		toggle_third_person()
		get_viewport().set_input_as_handled()


func toggle_third_person() -> void:
	third_person = not third_person
	_tp_valid = false
	if third_person and avatar == null:
		avatar = SkinnedHuman.new()
		avatar.name = "Avatar"
		avatar.setup(avatar_look if not avatar_look.is_empty() else SkinnedHuman.player_look())
	if avatar:
		avatar.visible = third_person and mode == "walk"


## Places the avatar where the walker is and follows it with a smooth over-the-shoulder camera
## that stays inside the cabin walls (or above the apron).
func _third_person_cam(delta: float) -> void:
	var in_cabin := String(walker.get("where")) == "cabin"
	var host: Node = ac if in_cabin else walker.get_parent()
	if avatar.get_parent() != host:
		if avatar.get_parent():
			avatar.get_parent().remove_child(avatar)
		host.add_child(avatar)
		_tp_valid = false
	var wpos: Vector3 = walker.get("pos")
	var wyaw: float = walker.get("yaw")
	var seated := bool(walker.get("seated"))
	var lay: Dictionary = walker.get("lay") if in_cabin else {}
	if seated and in_cabin:
		var seat: Dictionary = walker.get("seat")
		avatar.transform = Transform3D(Basis(), Vector3(float(seat.pos.x), float(lay.floor_y) + 0.02, float(seat.pos.z) + 0.12))
		avatar.play("sit", 0.3)
	else:
		avatar.transform = Transform3D(Basis(Vector3.UP, wyaw), wpos)
		var spd := (wpos - _av_last).length() / maxf(delta, 0.001) if _tp_valid else 0.0
		if _av_seated:
			avatar.play("idle", 0.3)
		avatar.set_motion(spd, delta)
	_av_seated = seated
	_av_last = wpos
	avatar.head_pitch = -float(walker.get("pitch")) * 0.4
	# camera: behind and above the shoulder, shorter in the cabin
	var pitch_r := clampf(float(walker.get("pitch")), deg_to_rad(-60.0), deg_to_rad(45.0))
	var basis := Basis.from_euler(Vector3(pitch_r - 0.18, wyaw, 0.0), EULER_ORDER_YXZ)
	var head_local := avatar.transform.origin + Vector3(0, 1.12 if seated else 1.58, 0)
	var where := String(walker.get("where"))
	var dist := 1.3 if in_cabin else (1.7 if where == "bridge" else (2.7 if where == "terminal" else 3.2))
	var side := basis.x * (0.32 if in_cabin else (0.12 if where == "bridge" else 0.55))
	var want_local := head_local + basis.z * dist + side
	if where == "terminal":
		var ti: TerminalInterior = walker.get("ti")
		want_local.x = clampf(want_local.x, -ti.depth * 0.5 + 0.6, ti.depth * 0.5 - 0.6)
		want_local.z = clampf(want_local.z, -ti.length * 0.5 + 0.6, ti.length * 0.5 - 0.6)
		want_local.y = clampf(want_local.y, TerminalInterior.FLOOR + 0.6, ti.ceil_h - 0.6)
	elif where == "bridge":
		want_local.y = minf(want_local.y, avatar.transform.origin.y + 2.15)
	if in_cabin:
		var half_w := maxf(CabinLayout.half_width(ac.spec, want_local.z, float(lay.floor_y) + 1.3) - 0.28, 0.3)
		want_local.x = clampf(want_local.x, -half_w, half_w)
		want_local.y = clampf(want_local.y, float(lay.floor_y) + 0.6, float(lay.floor_y) + 2.0)
	var host3 := host as Node3D
	var want: Vector3 = host3.global_transform * want_local
	var look_at_p: Vector3 = host3.global_transform * (head_local + basis.x * 0.12)
	if not in_cabin:
		var g := Geo.ground_height(view.wx(want), view.wz(want)) + 0.4
		want.y = maxf(want.y, g)
	if not _tp_valid:
		_tp_pos = want
		_tp_valid = true
	else:
		_tp_pos = _tp_pos.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	cam.global_position = _tp_pos
	cam.look_at(look_at_p, host3.global_transform.basis.y)
	cam.fov = 68.0 * zoom


func _tower_point() -> Vector3:
	var icao := Airports.nearest(ac.world_x(), ac.world_z())
	if icao == "":
		return ac.global_position + Vector3(200, 60, 200)
	var L := AirportLayout.get_layout(icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var t: Vector2 = L.tower
	return view.world_to_local(float(ap.x) + t.x, float(ap.elev) + float(L.tower_h) + 4.0, float(ap.z) + t.y)


func _keep_above_ground() -> void:
	var wxv := view.wx(cam.global_position)
	var wzv := view.wz(cam.global_position)
	var g := Geo.ground_height(wxv, wzv) + 1.5
	if cam.global_position.y < g:
		cam.global_position.y = g
