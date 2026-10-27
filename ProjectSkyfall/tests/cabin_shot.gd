extends Node3D
## Renders cabin interiors with seated passengers for visual checks.
## Usage: -- <out_dir> [type]
var out_dir := "/tmp"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var types := ["s320", "w350", "rj90", "tp72", "bj6"]
	if args.size() > 1:
		types = [args[1]]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.68, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 60, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	for t in types:
		var model := AircraftModel.new()
		add_child(model)
		model.build(t, "SKF", "CR-TST", 1.0)
		model.show_exterior_fuselage(false)
		var cab := CabinInterior.new()
		model.add_child(cab)
		cab.build(t, "SKF")
		cab.set_signs(true)
		var lay := cab.lay
		var crowd := Crowd.new()
		model.add_child(crowd)
		crowd.setup(lay.seats.size() + 4, 0, "SKF")
		var i := 0
		var r := RandomNumberGenerator.new()
		r.seed = 7
		for s in lay.seats:
			if r.randf() < 0.82:
				var ap := Crowd.appearance_for({"id": i * 31 + 5, "gender": "f" if r.randf() < 0.5 else "m", "age": r.randi_range(8, 80)})
				var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(ap.scale)), s.pos)
				if float(s.facing) > 0.0:
					xf.basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * float(ap.scale))
				var pose := HumanMesh.POSES["sit"]
				var roll := r.randf()
				if roll < 0.1:
					pose = HumanMesh.POSES["sit_read"]
				elif roll < 0.18:
					pose = HumanMesh.POSES["sit_sleep"]
				elif roll < 0.25:
					pose = HumanMesh.POSES["sit_talk"]
				crowd.set_person(i, xf, pose, r.randf(), 0.3, ap.top, ap.outfit, ap.seed, ap.flags, ap.build)
			i += 1
		# cabin crew in the aisle
		var ax: float = lay.aisles[0]
		var r0: Dictionary = lay.rows[mini(4, lay.rows.size() - 1)]
		crowd.set_person(lay.seats.size(), Transform3D(Basis(Vector3.UP, PI), Vector3(ax, lay.floor_y, r0.z0 - 0.3)), HumanMesh.POSES["demo"], 0.8, 0.2, Color.WHITE, Crowd.Outfit.CABIN, 0.3, Crowd.FLAG_SKIRT, 0.85)
		crowd.flush()
		var back: float = lay.cabin_back
		var front: float = lay.cabin_front
		# 1) from the rear looking forward along the aisle
		cam.position = Vector3(ax, lay.floor_y + 1.6, minf(back - 2.5, float(lay.rows[lay.rows.size() - 1].z1) + 0.6))
		cam.look_at(Vector3(ax, lay.floor_y + 1.1, front))
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("cabin_%s_aisle.png" % t))
		# 2) window seat view
		var ws: Dictionary = lay.seats[min(40, lay.seats.size() - 1)]
		for s2 in lay.seats:
			if s2.window and s2.side < 0 and s2.row > 6:
				ws = s2
				break
		cam.position = ws.pos + Vector3(0.05, 1.2, -0.12)
		cam.look_at(ws.pos + Vector3(-1.5, 1.0, -0.35))
		crowd.hide_person(lay.seats.find(ws))
		crowd.flush()
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("cabin_%s_window.png" % t))
		# 3) door area looking aft
		var d0: Dictionary = lay.doors[0]
		cam.position = Vector3(0.3, lay.floor_y + 1.65, d0.z - 0.2)
		cam.look_at(Vector3(-1.0, lay.floor_y + 1.0, d0.z + 1.0))
		cab.open_door("L1", true)
		for f in 90:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("cabin_%s_door.png" % t))
		model.queue_free()
		await get_tree().process_frame
	print("cabin shots done")
	get_tree().quit()
