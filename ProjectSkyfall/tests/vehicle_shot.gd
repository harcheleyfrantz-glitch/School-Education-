extends Node3D
## Renders every ground vehicle on the Port Calder apron for visual checks.
var out_dir := "/tmp"
var view: WorldView
var cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	WeatherModel.override_preset = "few"
	view = WorldView.new()
	add_child(view)
	var ap: Dictionary = Airports.get_ap("SKPC")
	view.setup(ap.x, ap.z - 300.0, U.date_to_clock(2027, 6, 14, 10.5), true)
	view.airports.ensure_loaded("SKPC")
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.near = 0.1
	cam.fov = 50.0
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	var kinds := VehicleBuilder.KINDS
	var lay := AirportLayout.get_layout("SKPC")
	var sd: Dictionary = lay.stands[2]
	var st: Vector2 = sd.stop
	var ax: Vector2 = sd.axis
	var nrm: Vector2 = sd.normal
	var p0 := st + nrm * 30.0
	var base := view.world_to_local(float(ap.x) + p0.x, float(ap.elev), float(ap.z) + p0.y)
	var axis3 := Vector3(ax.x, 0, ax.y)
	var vs := []
	var i := 0
	for k in kinds:
		var liv := {"main": VehicleBuilder.YELLOW, "text": "SKF"}
		if k in ["catering", "bus", "cart", "uld_dolly"]:
			liv = {"main": Color(0.95, 0.95, 0.96), "accent": Color(0.75, 0.1, 0.12), "text": "SKYFALL"}
		var v := VehicleBuilder.build(k, liv)
		view.dynamic_root.add_child(v)
		v.position = base + axis3 * (i * 16.0)
		v.position.y = Geo.ground_height(view.wx(v.position), view.wz(v.position)) + 0.02
		v.rotation.y = deg_to_rad(-35.0)
		VehicleBuilder.set_lamps(v, true, true)
		if k == "catering":
			VehicleBuilder.set_lift(v, 2.2)
		if k == "belt_loader":
			VehicleBuilder.part(v, "boom").rotation.x = deg_to_rad(14.0)
		if k == "arff":
			VehicleBuilder.part(v, "turret").rotation.y = deg_to_rad(20.0)
			VehicleBuilder.part(v, "turret_barrel").rotation.x = deg_to_rad(12.0)
		vs.append(v)
		i += 1
	await view.warm_up(15.0)
	for f in 10:
		await get_tree().process_frame
	var mid := base + axis3 * (kinds.size() * 8.0)
	cam.position = mid + Vector3(nrm.x, 0, nrm.y) * 90.0 + Vector3(0, 40.0, 0)
	cam.look_at(mid)
	for f in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("veh_row.png"))
	for v in vs:
		var L: float = v.get_meta("length", 6.0)
		var p: Vector3 = v.position
		# three-quarter front view from the left, then rear right
		var fwd: Vector3 = -v.global_transform.basis.z
		var right: Vector3 = v.global_transform.basis.x
		cam.position = p + fwd * L * 0.85 - right * L * 0.75 + Vector3(0, L * 0.32 + 1.0, 0)
		cam.look_at(p + Vector3(0, 1.2, 0))
		for f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("veh_%s_a.png" % v.name))
		cam.position = p - fwd * L * 0.9 + right * L * 0.7 + Vector3(0, L * 0.25 + 1.0, 0)
		cam.look_at(p + Vector3(0, 1.2, 0))
		for f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("veh_%s_b.png" % v.name))
	print("vehicle shots done")
	get_tree().quit()
