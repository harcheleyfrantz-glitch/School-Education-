extends Node3D
## Aerial views of places in the world: landmarks by id (RealWorld.LANDMARKS) or airports by
## ICAO, framed from a few kilometres away. Usage: -- out_dir id1,id2,... [hour] [dist_m] [alt_m]

var view: WorldView
var cam: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp"
	var ids := (a[1] if a.size() > 1 else "esb").split(",")
	var hour := float(a[2]) if a.size() > 2 else 15.0
	var dist := float(a[3]) if a.size() > 3 else 3200.0
	var alt := float(a[4]) if a.size() > 4 else 650.0
	Game.settings.quality = OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "medium"
	Game.apply_settings()
	WeatherModel.override_preset = "few"
	for id in ids:
		var target := Vector3.ZERO
		var hdg := 210.0
		var found := false
		for lm in RealWorld.LANDMARKS:
			if String(lm.id) == id:
				target = Vector3(float(lm.x), 0.0, float(lm.z))
				hdg = float(lm.yaw) + 160.0
				found = true
		if not found and Airports.DATA.has(id):
			var ap: Dictionary = Airports.get_ap(id)
			target = Vector3(float(ap.x), 0.0, float(ap.z))
			found = true
		if not found:
			print("unknown ", id)
			continue
		target.y = Geo.ground_height(target.x, target.z)
		var back := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
		var from := Vector3(target.x - back.x * dist, target.y + alt, target.z - back.y * dist)
		if view:
			view.queue_free()
			await get_tree().process_frame
		view = WorldView.new()
		add_child(view)
		view.setup(from.x, from.z, U.date_to_clock(2027, 6, 14, hour), true)
		if cam == null:
			cam = Camera3D.new()
			add_child(cam)
			cam.far = 120000.0
			cam.current = true
		view.camera = cam
		cam.position = view.world_to_local(from.x, from.y, from.z)
		cam.look_at(view.world_to_local(target.x, target.y + alt * 0.08, target.z), Vector3.UP)
		cam.fov = 50.0
		for i in 8:
			await get_tree().process_frame
		await view.warm_up(40.0)
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("place_%s.png" % id))
		print("shot ", id, " ", Geo.place_name(target.x, target.z), " landmarks built: ", view.landmarks.built.keys())
		for k in view.landmarks.built:
			var rt: Node3D = view.landmarks.built[k].root
			print("   ", k, " local ", rt.position, " cam ", cam.position, " children ", rt.get_child_count(), " visible ", rt.is_visible_in_tree())
	get_tree().quit()
