extends Node3D
## Renders every aircraft type on the Port Calder apron for visual checks.
var out_dir := "/tmp"
var view: WorldView
var cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var which := args[1] if args.size() > 1 else "all"
	WeatherModel.override_preset = "few"
	view = WorldView.new()
	add_child(view)
	var ap: Dictionary = Airports.get_ap("SKPC")
	view.setup(ap.x, ap.z - 300.0, U.date_to_clock(2027, 6, 14, 10.5), true)
	view.airports.ensure_loaded("SKPC")
	cam = Camera3D.new()
	cam.far = 120000.0
	cam.near = 0.2
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	var types := AircraftTypes.ORDER if which == "all" else [which]
	var x0: float = ap.x - 250.0
	var models := []
	var i := 0
	for t in types:
		var ac := Aircraft.new()
		view.dynamic_root.add_child(ac)
		ac.setup(t, "CR-T%d" % i, ["SKF", "CLK", "LMN", "NWC", "APX", "HFA", "WMA"][i % 7] if t != "t172" else "HFA", view, true)
		if t == "f4":
			ac.airline = "NWC"
		var spec := AircraftTypes.get_type(t)
		var lp := view.world_to_local(x0 + i * 75.0, float(ap.elev), float(ap.z) - 330.0)
		ac.place_at(lp, 160.0, true)
		ac.sys.lights.nav = true
		ac.sys.lights.beacon = true
		ac.player_controlled = false
		ac.set_physics_process(false)
		ac.model.animate(ac, 0.016)
		models.append(ac)
		i += 1
	cam.position = view.world_to_local(x0 + 120.0, float(ap.elev) + 22.0, float(ap.z) - 230.0)
	cam.look_at(view.world_to_local(x0 + 200.0, float(ap.elev) + 3.0, float(ap.z) - 330.0))
	await view.warm_up(20.0)
	for k in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("models_row.png"))
	# close-ups
	var idx := 0
	for ac in models:
		var t2: String = ac.type_id
		var L: float = ac.spec.length
		var p: Vector3 = ac.position
		cam.position = p + Vector3(L * 0.75, L * 0.18 + 2.0, L * 0.55)
		cam.look_at(p + Vector3(0, 1.0, 0))
		for k in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("model_%s.png" % t2))
		idx += 1
	print("model shots done")
	get_tree().quit()
