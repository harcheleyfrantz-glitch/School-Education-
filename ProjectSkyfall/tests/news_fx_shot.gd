extends Node3D
## Renders the news effects (smoke column, flames, fireball, decals) on a plain ground.
## godot --path . res://tests/news_fx_shot.tscn -- out_dir

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.22)
	g.material_override = gm
	add_child(g)
	var sm := NewsFX.smoke_column(1.6, Vector3(3, 0, 1), 1.0, 200)
	sm.position = Vector3(0, 6, 0)
	add_child(sm)
	var fl := NewsFX.flames(2.4)
	fl.position = Vector3(0, 1, 0)
	add_child(fl)
	var sc := NewsFX.decal("scorch", Vector3(60, 30, 60))
	add_child(sc)
	var fb := NewsFX.fireball()
	add_child(fb)
	NewsFX.fireball_pose(fb, 1.0, 30.0)
	fb.position = Vector3(120, 0, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-700, 300, 700)
	cam.look_at(Vector3(0, 150, 0))
	cam.fov = 40
	cam.current = true
	for i in 40:
		await get_tree().process_frame
	print("smoke emitting=", sm.emitting, " visible=", sm.is_visible_in_tree())
	get_viewport().get_texture().get_image().save_png(out.path_join("fx.png"))
	get_tree().quit()
