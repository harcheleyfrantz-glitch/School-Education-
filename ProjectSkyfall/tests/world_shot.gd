extends Node3D
## Dev harness: renders the world from a few vantage points and saves screenshots.
## Usage: godot --path . res://tests/world_shot.tscn -- out_dir

var shots := [
	{"name": "coast_pc", "x": -72000.0, "z": 14000.0, "alt": 700.0, "yaw": 75.0, "pitch": -7.0, "hour": 10.5, "wx": "few"},
	{"name": "mountains", "x": 214000.0, "z": -182000.0, "alt": 2600.0, "yaw": 45.0, "pitch": -5.0, "hour": 15.0, "wx": "scattered"},
	{"name": "cruise", "x": 60000.0, "z": -40000.0, "alt": 10500.0, "yaw": 80.0, "pitch": -14.0, "hour": 12.0, "wx": ""},
	{"name": "sunset", "x": -30000.0, "z": 30000.0, "alt": 900.0, "yaw": 285.0, "pitch": -3.0, "hour": 19.6, "wx": "few"},
	{"name": "night_city", "x": -38000.0, "z": 26000.0, "alt": 2500.0, "yaw": 300.0, "pitch": -18.0, "hour": 23.0, "wx": "clear"},
	{"name": "overcast_rain", "x": 20000.0, "z": 20000.0, "alt": 260.0, "yaw": 120.0, "pitch": -2.0, "hour": 14.0, "wx": "rain"},
	{"name": "pc_final", "x": -36300.0, "z": -700.0, "alt": 105.0, "yaw": 270.0, "pitch": -3.5, "hour": 11.0, "wx": "few", "ap": "SKPC"},
	{"name": "pc_terminal", "x": -39700.0, "z": -360.0, "alt": 30.0, "yaw": 215.0, "pitch": -8.0, "hour": 15.0, "wx": "scattered", "ap": "SKPC"},
	{"name": "pc_night", "x": -33000.0, "z": 1500.0, "alt": 420.0, "yaw": 280.0, "pitch": -6.0, "hour": 22.5, "wx": "clear", "ap": "SKPC"},
	{"name": "highpass_app", "x": 221830.0, "z": -165660.0, "alt": 1600.0, "yaw": 62.0, "pitch": -4.0, "hour": 9.0, "wx": "few", "ap": "SKHP"},
	{"name": "above_overcast", "x": 20000.0, "z": 20000.0, "alt": 3600.0, "yaw": 200.0, "pitch": -8.0, "hour": 17.5, "wx": "overcast"},
]
var out_dir := "/tmp"
var view: WorldView
var cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		var only := args[1]
		shots = shots.filter(func(s): return s.name == only)
	_run()

func _run() -> void:
	for s in shots:
		if view:
			view.queue_free()
			await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		view = WorldView.new()
		add_child(view)
		var clock := U.date_to_clock(2027, 6, 14, s.hour)
		WeatherModel.override_preset = s.get("wx", "")
		view.setup(s.x, s.z, clock, true)
		var dis := OS.get_environment("SKYFALL_DISABLE").split(",")
		if "clouds" in dis:
			view.cloud_low.queue_free()
			view.cloud_high.queue_free()
			view.cloud_low = MeshInstance3D.new()
			view.cloud_high = MeshInstance3D.new()
			view.add_child(view.cloud_low)
			view.add_child(view.cloud_high)
		if "water" in dis:
			view.ocean.visible = false
			view.static_root.visible = false
		if "shadow" in dis:
			view.sun.shadow_enabled = false
		if "softshadow" in dis:
			view.sun.light_angular_distance = 0.0
		if "glow" in dis:
			view.env.glow_enabled = false
		if "ssao" in dis:
			view.env.ssao_enabled = false
		if "fog" in dis:
			view.env.fog_enabled = false
		if "terrain" in dis:
			view.terrain.visible = false
		var skyv := OS.get_environment("SKYFALL_SKY")
		if skyv != "":
			var sh := Shader.new()
			sh.code = FileAccess.get_file_as_string(skyv)
			view.sky_mat.shader = sh
		if "sky" in dis:
			view.env.sky.sky_material = ProceduralSkyMaterial.new()
		if "precip" in dis:
			view.precip.queue_free()
			view.precip = MeshInstance3D.new()
			view.add_child(view.precip)
		if "storm" in dis:
			view.storm_root.visible = false
		if "adjust" in dis:
			view.env.adjustment_enabled = false
		if "msaa" in dis:
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		cam = Camera3D.new()
		cam.far = 160000.0
		cam.near = 0.5
		cam.fov = 62.0
		view.dynamic_root.add_child(cam)
		cam.current = true
		view.camera = cam
		var lp := view.world_to_local(s.x, s.alt, s.z)
		cam.position = lp
		cam.rotation_degrees = Vector3(s.pitch, -s.yaw, 0.0)
		if s.has("ap"):
			view.airports.ensure_loaded(s.ap)
		await view.warm_up(25.0)
		for i in 30:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(s.name + ".png"))
		print("  weather: ", WeatherModel.describe(view.weather), " base_ft=", int(view.weather.base_ft), " vis=", int(view.weather.vis), " ground=", int(Geo.height(s.x, s.z)), " city=", Geo.place_name(s.x, s.z))
		print("shot ", s.name, " in ", Time.get_ticks_msec() - t0, " ms, chunks=", view.terrain.chunks.size(), " displayed=", view.terrain.displayed.size())
	get_tree().quit()
