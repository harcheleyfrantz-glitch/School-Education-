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
	match m:
		"cockpit":
			look_yaw = 0.0
			look_pitch = -8.0
			cam.near = 0.02
		"cabin":
			look_yaw = 0.0
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
			cam.fov = clampf(rad_to_deg(2.0 * atan(float(ac.spec.span) * 2.5 / maxf(d, 1.0))), 2.0, 60.0)
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
