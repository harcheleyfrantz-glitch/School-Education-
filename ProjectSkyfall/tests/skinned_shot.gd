extends Node3D
## Renders SkinnedHuman characters: a lineup in different clips, portraits and a walking pilot.
## Usage: -- <out_dir>

var out_dir := "/tmp"
var people: Array = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.45, 0.72)
	sm.sky_horizon_color = Color(0.95, 0.72, 0.52)
	sm.ground_horizon_color = Color(0.6, 0.5, 0.42)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(-140.0), 0.0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.37, 0.38)
	gm.roughness = 0.9
	ground.material_override = gm
	add_child(ground)
	if OS.get_environment("WALL") != "":
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(20, 4, 0.1)
		wall.mesh = bm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.9, 0.1)
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wall.material_override = wm
		wall.position = Vector3(0, 2, 3)
		add_child(wall)
	Game.player = {"name": "Maya Okafor", "gender": "f", "airline": "SKF", "appearance": {"skin": 4, "hair_color": 0, "hair": 4, "build": 0.82}}
	var looks := [
		[SkinnedHuman.player_look(), "idle"],
		[Crowd.staff_appearance(Crowd.Outfit.CABIN, 11, "f"), "talk"],
		[Crowd.staff_appearance(Crowd.Outfit.FLIGHT, 5, "m"), "salute"],
		[Crowd.appearance_for({"id": 9001, "gender": "m", "age": 44, "job": "banker"}), "point"],
		[Crowd.appearance_for({"id": 9002, "gender": "f", "age": 27}), "wave"],
		[Crowd.appearance_for({"id": 9003, "gender": "m", "age": 71}), "idle"],
		[Crowd.staff_appearance(Crowd.Outfit.GROUND, 21, "m"), "walk"],
		[Crowd.appearance_for({"id": 9004, "gender": "f", "age": 35}), "run"],
	]
	for i in looks.size():
		var h := SkinnedHuman.new()
		add_child(h)
		var lk: Dictionary = looks[i][0]
		if i == 1:
			lk["airline"] = "SKF"
		h.setup(lk)
		h.play(String(looks[i][1]), 0.0)
		if OS.get_environment("MAT") == "std":
			var sm2 := StandardMaterial3D.new()
			sm2.albedo_color = Color(0.8, 0.5, 0.4)
			h.body.material_override = sm2
		h.position = Vector3((float(i) - 3.5) * 0.95, 0.0, 0.0)
		people.append(h)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await _settle(30)
	_cam(cam, Vector3(0, 1.15, -6.2), Vector3(0, 0.95, 0), 45.0)
	await _settle(4)
	_shot("skin_lineup")
	# portraits
	for i in [0, 1, 3, 5]:
		var hp: Vector3 = (people[i] as SkinnedHuman).bone_global(SkinnedHuman.B.HEAD).origin
		_cam(cam, hp + Vector3(0.25, 0.05, -0.75), hp + Vector3(0, 0.03, 0), 30.0)
		await _settle(3)
		_shot("skin_face_%d" % i)
	# motion: freeze walk and run at several phases
	var w: SkinnedHuman = people[6]
	var r: SkinnedHuman = people[7]
	for k in 3:
		w.anim.seek(0.18 + float(k) * 0.3, true)
		r.anim.seek(0.1 + float(k) * 0.2, true)
		_cam(cam, Vector3(5.4, 1.0, -1.6), Vector3(2.4, 0.9, 0), 40.0)
		await _settle(2)
		_shot("skin_motion_%d" % k)
	# a seated passenger
	var s: SkinnedHuman = people[5]
	s.play("sit", 0.0)
	_cam(cam, s.position + Vector3(1.6, 1.0, -1.6), s.position + Vector3(0, 0.6, 0), 40.0)
	await _settle(10)
	_shot("skin_sit")
	get_tree().quit()


func _cam(cam: Camera3D, from: Vector3, to: Vector3, fov: float) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.fov = fov


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
