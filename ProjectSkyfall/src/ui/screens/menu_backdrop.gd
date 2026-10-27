extends Node3D
## Live 3D scene behind the menus: an airliner being turned around at a Port Calder gate in the
## late-afternoon light, service vehicles and crews working around it, a slow camera drifting
## around the scene. Different screens frame it differently.

var view: WorldView
var ac: Aircraft
var ops: GroundOps
var cam: Camera3D
var _t := 0.0
var _yaw := 210.0
var _dist := 62.0
var _height := 9.0
var _target_dist := 62.0
var _target_height := 9.0
var _look_off := Vector3.ZERO


func _ready() -> void:
	var icao := "SKPC"
	var ap: Dictionary = Airports.get_ap(icao)
	var clock := WorldSim.clock if WorldSim.clock > 0.0 else WorldSim.START_CLOCK
	# always golden hour on the menu, on the current day
	var day := floorf(clock / 86400.0) * 86400.0
	WeatherModel.override_preset = "few"
	view = WorldView.new()
	view.name = "World"
	add_child(view)
	view.setup(float(ap.x), float(ap.z), day + 18.4 * 3600.0, true)
	view.airports.ensure_loaded(icao)
	var L := AirportLayout.get_layout(icao)
	var sd: Dictionary = L.stands[mini(3, L.stands.size() - 1)]
	ac = Aircraft.new()
	ac.name = "Display"
	view.dynamic_root.add_child(ac)
	ac.setup("s320", "CR-SFA", "SKF", view, true)
	ac.player_controlled = false
	var n: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	var pos := face + n * (7.0 + float(ac.spec.length) * float(ac.spec.cg_frac))
	ac.place_at(view.world_to_local(float(ap.x) + pos.x, float(ap.elev), float(ap.z) + pos.y), float(sd.hdg), true)
	ac.sys.setup(ac.spec, 8000.0, true)
	ac.sys.lights.beacon = false
	ac.sys.lights.nav = true
	ac.sys.lights.logo = true
	ac.sys.parking_brake = true
	ac.set_physics_process(false)
	ac.model.set_door("L1", 1.0)
	for i in 30:
		ac.model.animate(ac, 0.1)
	var av := view.airports.get_view(icao)
	if av:
		var door := ac.global_transform * ac.model.door_world_local()
		av.dock_bridge(String(sd.name), Vector3(view.wx(door) - float(ap.x), door.y - float(ap.elev), view.wz(door) - float(ap.z)))
	ops = GroundOps.new()
	ops.name = "Ops"
	view.dynamic_root.add_child(ops)
	ops.setup(null, ac, view)
	ops.begin_turnaround(icao, true)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.3
	cam.far = 60000.0
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam


func focus(screen_name: String) -> void:
	## Each screen frames the scene a little differently.
	match screen_name:
		"menu":
			_target_dist = 62.0
			_target_height = 9.0
			_look_off = Vector3.ZERO
		"create":
			_target_dist = 30.0
			_target_height = 3.0
			_look_off = Vector3(0, 1.5, 0)
		"hub", "jobs", "logbook":
			_target_dist = 48.0
			_target_height = 14.0
			_look_off = Vector3(0, 2.0, 0)
		_:
			_target_dist = 75.0
			_target_height = 22.0
			_look_off = Vector3.ZERO


func _process(delta: float) -> void:
	if ac == null:
		return
	_t += delta
	_yaw = fmod(_yaw + delta * 1.6, 360.0)
	_dist = lerpf(_dist, _target_dist, clampf(delta * 0.8, 0.0, 1.0))
	_height = lerpf(_height, _target_height, clampf(delta * 0.8, 0.0, 1.0))
	var c := ac.global_position + _look_off
	var dir := Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	var p := c + dir * _dist + Vector3(0, _height + sin(_t * 0.15) * 1.5, 0)
	var g := Geo.ground_height(view.wx(p), view.wz(p)) + 1.8
	p.y = maxf(p.y, g)
	cam.global_position = p
	cam.look_at(c + Vector3(0, 2.0, 0), Vector3.UP)
	# keep the scene alive: the light moves slowly through the evening
	view.set_time(view.time + delta * 2.0)
	ac.model.animate(ac, delta)


func _exit_tree() -> void:
	WeatherModel.override_preset = ""
