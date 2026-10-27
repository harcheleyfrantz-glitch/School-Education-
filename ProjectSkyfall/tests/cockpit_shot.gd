extends Node3D
## Renders flight decks for visual checks. Usage: -- <out_dir> [type]
var out_dir := "/tmp"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var types := ["s320", "w350", "tp72", "bj6", "t172"]
	if args.size() > 1:
		types = [args[1]]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.36, 0.3)
	ground.material_override = gm
	add_child(ground)
	var strip := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(45, 3000)
	strip.mesh = sm
	var stm := StandardMaterial3D.new()
	stm.albedo_color = Color(0.2, 0.2, 0.21)
	strip.material_override = stm
	strip.position = Vector3(0, 0.02, -1400)
	add_child(strip)
	var cam := Camera3D.new()
	cam.fov = 75
	cam.near = 0.02
	add_child(cam)
	cam.current = true
	for t in types:
		var ac := Aircraft.new()
		add_child(ac)
		ac.setup(t, "CR-TST", "SKF", null, true)
		ac.player_controlled = false
		ac.set_physics_process(false)
		ac.place_at(Vector3(0, float(ac.spec.gear_height) + float(ac.spec.fuse_h) * 0.5, 0), 0.0, true)
		ac.model.show_exterior_fuselage(false)
		if OS.get_environment("HIDE_EXT") != "":
			ac.model.exterior.visible = false
		ac.sys.lights.landing = true
		ac.sys.lights.seatbelt = true
		ac.ap.engaged = true
		ac.ap.hdg_sel = 15.0
		ac.ap.alt_sel = 3000.0
		ac.ap.plan = [{"name": "DEP", "x": 0.0, "z": 0.0}, {"name": "ORENA", "x": 9000.0, "z": -30000.0}, {"name": "SKRV", "x": 20000.0, "z": -90000.0}]
		ac.ap.leg = 1
		ac.sys.master_caution = true
		var ckp := CockpitInterior.new()
		ac.add_child(ckp)
		ckp.build(t, "SKF", "high")
		ckp.attach(ac)
		var Ey: Vector3 = ckp.E
		var shots := [
			["eye", Ey, Ey + Vector3(0.05, -0.12, -1.0)],
			["wide", Ey + Vector3(0.52, 0.18, 0.95), Ey + Vector3(0.52, -0.25, -1.0)],
			["overhead", Ey + Vector3(0.3, -0.05, 0.2), Ey + Vector3(0.45, 0.75, -0.3)],
			["pedestal", Ey + Vector3(0.52, 0.1, 0.25), Ey + Vector3(0.52, -0.6, -0.55)],
		]
		for s in shots:
			cam.global_position = ac.global_transform * (s[1] as Vector3)
			cam.look_at(ac.global_transform * (s[2] as Vector3))
			for f in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("ck_%s_%s.png" % [t, s[0]]))
		ac.queue_free()
		await get_tree().process_frame
	print("cockpit shots done")
	get_tree().quit()
