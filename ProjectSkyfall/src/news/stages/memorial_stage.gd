class_name MemorialStage
extends NewsStage
## A roadside vigil near the crash site at dusk: a railing hung with ribbons and a banner,
## hundreds of bouquets, framed photographs of the victims, flickering candles, mourners
## kneeling and standing in silence, street lamps and the last light in the sky.

var _flames: Array = []
var _candle_lights: Array = []
var _photos: Array = []


func build(prog: Dictionary) -> void:
	super.build(prog)
	var inc := News.incident(String(prog.get("incident", "")))
	var victims: Array = inc.get("victims", prog.get("victims", []))
	var num := String(inc.get("num", ""))
	var r := U.rng(U.hash_str(String(prog.get("incident", "x")) + "vigil"))
	_environment()
	# ground, a footpath and a low wall
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, -0.05, 0), Vector3(60, 0.1, 40), Color(0.16, 0.2, 0.12))
	mb.add_box(Vector3(0, 0.005, -1.6), Vector3(60, 0.02, 2.6), Color(0.32, 0.31, 0.3))
	mb.add_box(Vector3(0, 0.25, 0.9), Vector3(16, 0.5, 0.35), Color(0.45, 0.43, 0.4))
	add_child(mesh_node(mb, vcolor_mat(0.9, 0.0)))
	# railing with ribbons
	var rail := MeshBuilder.new()
	for i in 17:
		var x := -8.0 + i
		rail.add_cylinder(Vector3(x, 0.5, 0.9), Vector3(x, 1.6, 0.9), 0.03, 0.03, 6, Color(0.15, 0.15, 0.16))
	for y in [1.0, 1.55]:
		rail.add_cylinder(Vector3(-8.0, y, 0.9), Vector3(8.0, y, 0.9), 0.025, 0.025, 6, Color(0.15, 0.15, 0.16))
	var ribbons := MeshBuilder.new()
	for i2 in 26:
		var x2 := r.randf_range(-7.8, 7.8)
		var col: Color = [Color(0.95, 0.95, 0.95), Color(0.2, 0.35, 0.8), Color(0.95, 0.75, 0.15), Color(0.85, 0.15, 0.2)][r.randi() % 4]
		ribbons.add_quad(Vector3(x2, 1.55, 0.88), Vector3(x2 + 0.05, 1.55, 0.88), Vector3(x2 + 0.07, 1.05, 0.86), Vector3(x2 + 0.02, 1.05, 0.86), col)
	add_child(mesh_node(rail, vcolor_mat(0.4, 0.6)))
	var rm := vcolor_mat(0.7, 0.0)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh_node(ribbons, rm))
	# the banner
	var ban := MeshBuilder.new()
	ban.add_quad(Vector3(-3.0, 1.0, 0.84), Vector3(3.0, 1.0, 0.84), Vector3(3.0, 1.58, 0.84), Vector3(-3.0, 1.58, 0.84), Color(0.96, 0.95, 0.92))
	var bm := vcolor_mat(0.9, 0.0)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh_node(ban, bm))
	var bl := label3d("FLIGHT %s  ·  FOREVER IN OUR HEARTS" % num if num != "" else "FOREVER IN OUR HEARTS", 72, 0.0042, Color(0.08, 0.1, 0.25), NewsStyle.font("serif", 700))
	bl.position = Vector3(0, 1.29, 0.83)
	bl.rotation.y = PI
	add_child(bl)
	# bouquets, cards and toys along the wall
	var fl := MeshBuilder.new()
	for k in 46:
		NewsProps.flowers(fl, Vector3(r.randf_range(-7.5, 7.5), 0.0, r.randf_range(0.2, 0.65)), r, 2)
	for k2 in 18:
		var cp := Vector3(r.randf_range(-7, 7), 0.02, r.randf_range(0.05, 0.6))
		fl.add_box(cp + Vector3(0, 0.08, 0), Vector3(0.14, 0.16, 0.01).rotated(Vector3.UP, 0.0), Color(0.97, 0.96, 0.92))
	for k3 in 6:
		var tp := Vector3(r.randf_range(-6, 6), 0.0, r.randf_range(0.3, 0.6))
		fl.add_sphere(tp + Vector3(0, 0.12, 0), Vector3(0.13, 0.12, 0.11), 10, 6, Color(0.55, 0.38, 0.22))
		fl.add_sphere(tp + Vector3(0, 0.3, 0), Vector3(0.09, 0.09, 0.08), 10, 6, Color(0.6, 0.42, 0.25))
	var fm := vcolor_mat(0.8, 0.0)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh_node(fl, fm))
	# framed photographs of the victims, propped against the wall
	var n_ph := clampi(victims.size(), 6, 14)
	for i3 in n_ph:
		var v: Dictionary = victims[i3] if i3 < victims.size() else {"name": "", "id": i3}
		var tex := _portrait(v, i3)
		var q := QuadMesh.new()
		q.size = Vector2(0.32, 0.4)
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = tex
		pm.roughness = 0.3
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = pm
		var x3 := -6.2 + i3 * (12.4 / maxf(n_ph - 1, 1)) + r.randf_range(-0.2, 0.2)
		mi.position = Vector3(x3, 0.72, 0.68)
		mi.rotation = Vector3(deg_to_rad(-12.0), PI + r.randf_range(-0.15, 0.15), 0)
		add_child(mi)
		var fr := MeshBuilder.new()
		fr.add_box(Vector3(0, 0, 0.012), Vector3(0.38, 0.46, 0.02), Color(0.12, 0.08, 0.05))
		var fmi := mesh_node(fr, vcolor_mat(0.5, 0.2))
		mi.add_child(fmi)
	# candles in clusters on the ground and the wall
	var cmb := MeshBuilder.new()
	var flames := MeshBuilder.new()
	for k4 in 70:
		var on_wall := k4 % 3 == 0
		var cp2 := Vector3(r.randf_range(-7.5, 7.5), 0.5 if on_wall else 0.0, 0.9 + r.randf_range(-0.12, 0.12) if on_wall else r.randf_range(-0.35, 0.3))
		var h := r.randf_range(0.06, 0.16)
		cmb.add_cylinder(cp2, cp2 + Vector3(0, h, 0), 0.035, 0.035, 8, [Color(0.95, 0.93, 0.86), Color(0.85, 0.15, 0.12), Color(0.95, 0.9, 0.6)][r.randi() % 3])
		var tip := cp2 + Vector3(0, h + 0.035, 0)
		flames.add_sphere(tip, Vector3(0.012, 0.03, 0.012), 6, 4, Color.WHITE)
		if k4 % 9 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.62, 0.25)
			l.omni_range = 2.6
			l.light_energy = 1.2
			l.position = tip + Vector3(0, 0.05, 0)
			add_child(l)
			_candle_lights.append(l)
	add_child(mesh_node(cmb, vcolor_mat(0.6, 0.0)))
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.albedo_color = Color(1.0, 0.75, 0.35)
	flm.emission_enabled = true
	flm.emission = Color(1.0, 0.6, 0.2)
	flm.emission_energy_multiplier = 6.0
	var flame_mi := mesh_node(flames, flm, false)
	add_child(flame_mi)
	_flames.append(flame_mi)
	# street lamps and trees behind
	var bg := MeshBuilder.new()
	for x4 in [-12.0, 0.5, 13.0]:
		bg.add_cylinder(Vector3(x4, 0, 6.0), Vector3(x4, 5.5, 6.0), 0.08, 0.06, 8, Color(0.1, 0.1, 0.1))
		bg.add_box(Vector3(x4, 5.55, 5.6), Vector3(0.3, 0.12, 0.8), Color(0.1, 0.1, 0.1))
		var sl := OmniLight3D.new()
		sl.light_color = Color(1.0, 0.75, 0.45)
		sl.light_energy = 2.2
		sl.omni_range = 16.0
		sl.position = Vector3(x4, 5.3, 5.4)
		add_child(sl)
	for k5 in 14:
		var tp2 := Vector3(r.randf_range(-25, 25), 0, r.randf_range(9, 22))
		bg.add_cylinder(tp2, tp2 + Vector3(0, 2.0, 0), 0.15, 0.12, 6, Color(0.12, 0.09, 0.07))
		bg.add_sphere(tp2 + Vector3(0, 4.0, 0), Vector3(2.2, 2.6, 2.2) * r.randf_range(0.7, 1.3), 10, 7, Color(0.08, 0.12, 0.08))
	add_child(mesh_node(bg, vcolor_mat(0.9, 0.0)))
	var glow := MeshBuilder.new()
	for x5 in [-12.0, 0.5, 13.0]:
		glow.add_box(Vector3(x5, 5.47, 5.6), Vector3(0.24, 0.03, 0.6), Color.WHITE)
	add_child(mesh_node(glow, unshaded(Color(1.0, 0.85, 0.6), 5.0), false))
	# mourners
	people = Crowd.new()
	add_child(people)
	people.setup(40, 0, "", true)
	var idx := 0
	for k6 in 30:
		var p := Vector3(r.randf_range(-7.5, 7.5), 0, r.randf_range(-3.6, -0.4))
		var pose: String = ["grief", "stand", "stand", "kneel", "grief", "film", "stand"][r.randi() % 7]
		if pose == "kneel":
			p.z = r.randf_range(-0.7, -0.4)
		_person(idx, p, PI + r.randf_range(-0.5, 0.5), pose, Crowd.Outfit.CIVIL, 170000 + k6 * 17, Crowd.FLAG_PHONE if pose == "film" else 0,
			[Color(0.08, 0.08, 0.1), Color(0.15, 0.15, 0.18), Color(0.25, 0.2, 0.18), Color(0.12, 0.14, 0.22)][r.randi() % 4])
		idx += 1
	people.flush()
	_make_camera()
	cam.near = 0.05
	cam.far = 200.0


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.03, 0.05, 0.14)
	psm.sky_horizon_color = Color(0.42, 0.28, 0.32)
	psm.ground_horizon_color = Color(0.1, 0.08, 0.08)
	psm.ground_bottom_color = Color(0.02, 0.02, 0.02)
	psm.sun_angle_max = 0.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.4)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.18, 0.25)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.9)
	moon.light_energy = 0.25
	moon.rotation_degrees = Vector3(-35, 160, 0)
	add_child(moon)


static func _portrait(v: Dictionary, i: int) -> ImageTexture:
	## A simple photograph: soft background, head and shoulders in the person's colours.
	var r := U.rng(U.hash_ints(int(v.get("id", i)), 31))
	var w := 64
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var bg := Color.from_hsv(r.randf(), 0.25, 0.75)
	var skin: Color = [Color(0.86, 0.68, 0.57), Color(0.71, 0.51, 0.37), Color(0.47, 0.32, 0.21), Color(0.3, 0.2, 0.14)][r.randi() % 4]
	var hair: Color = [Color(0.08, 0.06, 0.05), Color(0.35, 0.22, 0.12), Color(0.7, 0.56, 0.34), Color(0.6, 0.6, 0.6)][r.randi() % 4]
	var top := Color.from_hsv(r.randf(), 0.5, 0.55)
	for y in h:
		for x in w:
			var c := bg.lerp(bg.darkened(0.3), float(y) / h)
			var hx := (x - w * 0.5) / 13.0
			var hy := (y - h * 0.38) / 16.0
			if hx * hx + hy * hy < 1.0:
				c = skin
				if hy < -0.35 or (absf(hx) > 0.8 and hy < 0.3):
					c = hair
			var sy := y - h * 0.72
			if sy > 0.0 and absf(x - w * 0.5) < 14.0 + sy * 1.3:
				c = top
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func apply(seg: Dictionary, shot: Dictionary, lt: float, st: float, delta: float) -> void:
	var c := String(shot.get("cam", "memorial_wide"))
	var f := ease01(st / maxf(float(shot.get("dur", 5.0)), 0.1))
	match c:
		"memorial_candles":
			var p := Vector3(-1.2, 0.35, -0.9).lerp(Vector3(0.6, 0.38, -0.95), f)
			_look(p, Vector3(p.x + 0.6, 0.45, 0.8), 40.0)
			_dof(true, 1.6, 0.12)
		"memorial_mourners":
			var p2 := Vector3(2.5, 1.5, 0.3).lerp(Vector3(1.8, 1.45, 0.3), f)
			_look(p2, Vector3(-1.0, 1.25, -2.0), 38.0)
			_dof(true, 3.6, 0.06)
		_:
			var p3 := Vector3(-3.5, 2.6, -9.0).lerp(Vector3(-2.0, 2.2, -8.0), f)
			_look(p3, Vector3(0, 0.9, 0.5), 40.0)
			_dof(false)
	for i in _candle_lights.size():
		(_candle_lights[i] as OmniLight3D).light_energy = 1.0 + 0.35 * sin(lt * 11.0 + i * 1.7) * sin(lt * 6.3 + i)
