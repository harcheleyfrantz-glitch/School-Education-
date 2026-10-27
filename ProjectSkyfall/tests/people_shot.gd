extends Node3D
## Renders every human pose and outfit for visual checks.
var out_dir := "/tmp"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.5, 0.52)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var crowd := Crowd.new()
	add_child(crowd)
	var poses := HumanMesh.POSES.keys()
	crowd.setup(poses.size() + 9, 0, "SKF")
	var i := 0
	for k in poses:
		var col := i % 7
		var row := i / 7
		var xf := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(200.0)), Vector3(col * 1.3 - 4.0, 0, row * 1.8 - 2.0))
		var flags := 0
		if k == "walk":
			flags |= Crowd.FLAG_BAG
		if k in ["film", "sit_film"]:
			flags |= Crowd.FLAG_PHONE
		var stage := 0.0
		if k == "demo":
			stage = 0.8
		crowd.set_person(i, xf, HumanMesh.POSES[k], stage, 0.8, Color(0.2, 0.4, 0.7), Crowd.Outfit.CIVIL, float(i) / 30.0, flags, 0.2 if i % 2 == 0 else 0.8)
		var lbl := Label3D.new()
		lbl.text = k
		lbl.pixel_size = 0.004
		lbl.position = xf.origin + Vector3(0, 2.05, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
		i += 1
	# outfits row
	for o in 9:
		var xf2 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(180.0)), Vector3(o * 1.0 - 4.0, 0, 4.0))
		var fl := Crowd.FLAG_HAT if o in [3, 4, 5, 7] else 0
		if o == 0:
			fl |= Crowd.FLAG_ELDERLY
		if o == 2:
			fl |= Crowd.FLAG_SKIRT
		crowd.set_person(i, xf2, 0, 0.1 * o, 0.3, Color(0.7, 0.2, 0.2), o, 0.11 * o + 0.05, fl, 0.8 if o % 2 == 0 else 0.1)
		i += 1
	crowd.flush()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3.2, 9.5)
	cam.look_at(Vector3(0, 0.8, 0.5))
	cam.fov = 60
	cam.current = true
	for f in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("people_all.png"))
	cam.position = Vector3(-2.0, 1.7, 2.2)
	cam.look_at(Vector3(-2.7, 1.0, -2.0))
	for f in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("people_close.png"))
	print("people shots done")
	get_tree().quit()
