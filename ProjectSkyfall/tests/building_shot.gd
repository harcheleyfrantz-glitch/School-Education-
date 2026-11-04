extends Node3D
## Close-ups of city buildings with the building shader: see-through rooms behind the glass,
## facade variety and night lighting. Usage: -- out_dir
const CityMeshes := preload("res://src/world/models/city/city_meshes.gd")
const CarMeshes := preload("res://src/world/models/city/car_meshes.gd")
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var mat: ShaderMaterial
var car_mat: ShaderMaterial


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.25, 0.26)
	ground.material_override = gm
	add_child(ground)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	car_mat = ShaderMaterial.new()
	car_mat.shader = load("res://shaders/traffic.gdshader")
	var meshes := CityMeshes.build_all()
	var rows := [["tower_glass", Vector3(-60, 0, 0), Vector3(36, 160, 36), Color(0.42, 0.52, 0.62), 0.13],
		["tower_glass", Vector3(0, 0, 0), Vector3(34, 140, 34), Color(0.35, 0.45, 0.5), 0.61],
		["box_office", Vector3(60, 0, 0), Vector3(44, 60, 40), Color(0.78, 0.74, 0.68), 0.37],
		["tower_res", Vector3(120, 0, 0), Vector3(34, 110, 34), Color(0.86, 0.85, 0.82), 0.71],
		["tower_glass", Vector3(-120, 0, 0), Vector3(38, 170, 38), Color(0.5, 0.56, 0.52), 0.88]]
	for r in rows:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[r[0]]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis().scaled(r[2]), r[1]))
		mm.set_instance_custom_data(0, Color(r[3].r, r[3].g, r[3].b, (5.0 + 0.05 + 0.9 * float(r[4])) / 8.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		add_child(mi)
	# a street of traffic in front
	var cars := CarMeshes.build_all()
	var k := 0
	for kind in ["sedan", "suv", "hatch", "van", "bus", "truck"]:
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_custom_data = true
		mm2.mesh = cars[kind]
		mm2.instance_count = 3
		for i in 3:
			mm2.set_instance_transform(i, Transform3D(Basis(), Vector3(-20 + i * 2.0, 0.03, 40.0 + (k % 2) * 4.0)))
			mm2.set_instance_custom_data(i, Color(120.0, 0.0, (float(k) * 3.0 + i) / 18.0, float(i) + 0.37 * k))
		var mi2 := MultiMeshInstance3D.new()
		mi2.multimesh = mm2
		mi2.material_override = car_mat
		add_child(mi2)
		k += 1
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 55.0
	var views := [[Vector3(-30, 22, 32), Vector3(-2, 26, 0), "glass_close"], [Vector3(30, 14, 50), Vector3(60, 18, 0), "office_close"],
		[Vector3(-90, 70, 110), Vector3(0, 70, 0), "towers"], [Vector3(-14, 4, 58), Vector3(-10, 1.0, 40), "cars"]]
	for night in [0.0, 1.0]:
		mat.set_shader_parameter("night", night)
		car_mat.set_shader_parameter("night", night)
		sun.light_energy = 1.0 - night * 0.97
		psm.sky_top_color = Color(0.35, 0.5, 0.75).lerp(Color(0.01, 0.015, 0.04), night)
		psm.sky_horizon_color = Color(0.7, 0.75, 0.8).lerp(Color(0.03, 0.03, 0.06), night)
		psm.ground_horizon_color = psm.sky_horizon_color
		env.ambient_light_energy = 1.0 - night * 0.9
		for v in views:
			cam.position = v[0]
			cam.look_at(v[1], Vector3.UP)
			for i in 6:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("bld_%s_%s.png" % [v[2], "night" if night > 0.5 else "day"]))
	print("BUILDING SHOT DONE")
	get_tree().quit()
