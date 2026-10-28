class_name PressStage
extends NewsStage
## Press conference room: a step-and-repeat backdrop with the safety board's (or the airline's)
## emblem, a podium bristling with microphones, flags, a screen with the flight path, rows of
## journalists, TV cameras on tripods at the back and camera flashes going off.

var speaker := ["Ingrid Solberg", "f", "Investigator-in-charge"]
var board := true
var _flashes: Array = []
var _flash_meshes: Array = []
var screen_vp: SubViewport
const PODIUM := Vector3(0.0, 0.0, 2.3)


func build(prog: Dictionary) -> void:
	super.build(prog)
	for s in prog.get("segments", []):
		if String(s.kind) == "presser":
			speaker = s.get("speaker", speaker)
			board = bool(s.get("board", true))
	var airline := String(prog.get("world", {}).get("airline", "SKF"))
	var main_col := Color(0.11, 0.26, 0.48) if board else Color.html(String(Airlines.get_al(airline).livery.tail))
	var text_col := Color(1.0, 0.75, 0.15) if board else Color.html(String(Airlines.get_al(airline).livery.logo))
	_environment()
	_room(main_col)
	_backdrop(main_col, text_col, airline)
	var pod := NewsProps.podium(main_col.darkened(0.25))
	pod.position = PODIUM
	pod.rotation.y = PI
	add_child(pod)
	var emb := label3d("CTSB" if board else String(Airlines.get_al(airline).name).to_upper(), 64, 0.0024, text_col, NewsStyle.font("sans", 900))
	emb.position = PODIUM + Vector3(0, 0.72, -0.29)
	emb.rotation.y = PI
	add_child(emb)
	if board:
		var sub := label3d("TRANSPORT SAFETY BOARD", 32, 0.0018, Color(1, 1, 1, 0.9), NewsStyle.font("sans", 700))
		sub.position = PODIUM + Vector3(0, 0.56, -0.29)
		sub.rotation.y = PI
		add_child(sub)
	# flags either side
	var national := [Color(0.06, 0.18, 0.42), Color(0.95, 0.95, 0.95), Color(0.95, 0.55, 0.12)]
	var bflag := [Color(0.11, 0.3, 0.54), Color(1.0, 0.72, 0.1), Color(0.11, 0.3, 0.54)] if board else [main_col, text_col, main_col]
	for f in [[Vector3(-1.6, 0, 3.0), national, 0.3], [Vector3(1.65, 0, 3.0), bflag, 1.7], [Vector3(-2.3, 0, 3.1), bflag, 2.6]]:
		var fl := NewsProps.flag(f[1], Vector2(1.2, 0.8), float(f[2]))
		fl.position = f[0]
		fl.rotation.y = PI + 0.35
		add_child(fl)
	_screen(prog)
	people = Crowd.new()
	add_child(people)
	people.setup(48, 0, "", true)
	var sid := 2000 + U.hash_str(String(speaker[0])) % 9000
	_person(0, PODIUM + Vector3(0, 0, 0.42), 0.0, "talk", Crowd.Outfit.SUIT, sid, 0, Color(-1, 0, 0), 0.55, String(speaker[1]))
	_person(1, PODIUM + Vector3(1.0, 0, 0.75), 0.15, "stand", Crowd.Outfit.SUIT, sid + 13, 0)
	_person(2, PODIUM + Vector3(-1.05, 0, 0.8), -0.2, "stand", Crowd.Outfit.OFFICIAL if board else Crowd.Outfit.SUIT, sid + 29, 0)
	var r := U.rng(sid)
	var idx := 3
	for row in 4:
		for k in 8:
			if r.randf() < 0.12:
				continue
			var x := -3.15 + k * 0.9 + (0.3 if row % 2 else 0.0)
			var z := -1.0 - row * 1.15
			var pose: String = ["sit_film", "sit_read", "sit", "sit_film", "sit_talk"][r.randi() % 5]
			_person(idx, Vector3(x, 0, z), PI + r.randf_range(-0.12, 0.12), pose, Crowd.Outfit.CIVIL if r.randf() < 0.7 else Crowd.Outfit.SUIT,
				150000 + idx * 31, Crowd.FLAG_PHONE if pose == "sit_film" else 0)
			idx += 1
			if r.randf() < 0.18 and _flashes.size() < 10:
				_flashes.append(Vector3(x, 1.3, z - 0.3))
	# camera operators on the riser at the back
	for k2 in 3:
		_person(idx, Vector3(-2.2 + k2 * 2.2, 0.4, -6.3), PI, "stand", Crowd.Outfit.CIVIL, 160000 + k2, 0, Color(0.08, 0.08, 0.1))
		idx += 1
	people.flush()
	_chairs_and_cameras()
	_lights()
	_make_camera()
	cam.near = 0.05
	cam.far = 120.0


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	if Game.renderer == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _room(col: Color) -> void:
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, -0.05, -1.5), Vector3(16, 0.1, 14), Color(0.16, 0.18, 0.24))
	mb.add_box(Vector3(0, 4.3, -1.5), Vector3(16, 0.1, 14), Color(0.85, 0.85, 0.83))
	mb.add_box(Vector3(0, 2.15, 3.9), Vector3(16, 4.3, 0.1), Color(0.6, 0.6, 0.62))
	mb.add_box(Vector3(-7.5, 2.15, -1.5), Vector3(0.1, 4.3, 14), Color(0.72, 0.7, 0.66))
	mb.add_box(Vector3(7.5, 2.15, -1.5), Vector3(0.1, 4.3, 14), Color(0.72, 0.7, 0.66))
	mb.add_box(Vector3(0, 2.15, -8.4), Vector3(16, 4.3, 0.1), Color(0.6, 0.6, 0.62))
	mb.add_box(Vector3(0, 0.2, -6.3), Vector3(7.5, 0.4, 1.8), Color(0.1, 0.1, 0.11))
	var m := vcolor_mat(0.85, 0.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh_node(mb, m))
	var panels := MeshBuilder.new()
	for i in 3:
		for k in 2:
			panels.add_box(Vector3(-4.0 + i * 4.0, 4.24, -4.0 + k * 4.5), Vector3(2.2, 0.02, 1.2), Color.WHITE)
	add_child(mesh_node(panels, unshaded(Color(1, 0.98, 0.94), 1.6), false))


func _backdrop(col: Color, text_col: Color, airline: String) -> void:
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, 1.75, 3.75), Vector3(6.6, 3.1, 0.06), col)
	add_child(mesh_node(mb, vcolor_mat(0.7, 0.0)))
	var word := "CTSB" if board else String(Airlines.get_al(airline).iata) + " " + String(Airlines.get_al(airline).name).to_upper()
	var f := NewsStyle.font("sans", 900)
	for row in 4:
		for k in 5:
			var l := label3d(word, 40, 0.0042, Color(text_col, 0.85) if (row + k) % 2 == 0 else Color(1, 1, 1, 0.75), f)
			l.position = Vector3(-2.6 + k * 1.3 + (0.65 if row % 2 else 0.0), 0.6 + row * 0.72, 3.71)
			l.rotation.y = PI
			add_child(l)


func _screen(prog: Dictionary) -> void:
	screen_vp = SubViewport.new()
	screen_vp.size = Vector2i(800, 450)
	screen_vp.disable_3d = true
	screen_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(screen_vp)
	var g := StoryGraphic.new()
	g.size = Vector2(800, 450)
	g.setup(prog)
	screen_vp.add_child(g)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.07)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission_texture = screen_vp.get_texture()
	m.emission_energy_multiplier = 1.1
	mi.material_override = m
	mi.position = Vector3(3.1, 1.75, 3.2)
	mi.rotation.y = PI + 0.4
	add_child(mi)
	var st := MeshBuilder.new()
	st.add_box(Vector3(3.1, 1.75, 3.24), Vector3(2.0, 1.16, 0.06), Color(0.05, 0.05, 0.05))
	st.add_cylinder(Vector3(3.1, 0.0, 3.3), Vector3(3.1, 1.2, 3.3), 0.04, 0.04, 8, Color(0.2, 0.2, 0.2))
	var sm := mesh_node(st, vcolor_mat(0.5, 0.3))
	add_child(sm)


func _chairs_and_cameras() -> void:
	var mb := MeshBuilder.new()
	for row in 4:
		for k in 8:
			var x := -3.15 + k * 0.9 + (0.3 if row % 2 else 0.0)
			var z := -1.0 - row * 1.15
			mb.add_box(Vector3(x, 0.44, z + 0.08), Vector3(0.5, 0.06, 0.48), Color(0.2, 0.22, 0.3))
			mb.add_box(Vector3(x, 0.72, z + 0.32), Vector3(0.5, 0.52, 0.05), Color(0.2, 0.22, 0.3))
			mb.add_cylinder(Vector3(x, 0.0, z + 0.08), Vector3(x, 0.44, z + 0.08), 0.02, 0.02, 6, Color(0.6, 0.6, 0.6))
	# TV cameras on tripods on the riser
	for k2 in 3:
		var p := Vector3(-2.2 + k2 * 2.2, 0.4, -5.7)
		for a in 3:
			var ang := float(a) / 3.0 * TAU
			mb.add_cylinder(p + Vector3(0, 1.2, 0), p + Vector3(sin(ang) * 0.4, 0, cos(ang) * 0.4), 0.018, 0.018, 5, Color(0.1, 0.1, 0.1))
		mb.add_box(p + Vector3(0, 1.38, 0.1), Vector3(0.22, 0.26, 0.55), Color(0.08, 0.08, 0.09))
		mb.add_cylinder(p + Vector3(0, 1.38, 0.38), p + Vector3(0, 1.38, 0.62), 0.07, 0.08, 12, Color(0.03, 0.03, 0.03))
	add_child(mesh_node(mb, vcolor_mat(0.6, 0.2)))
	for i in _flashes.size():
		var l := OmniLight3D.new()
		l.light_color = Color(0.95, 0.97, 1.0)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.position = _flashes[i]
		add_child(l)
		_flash_meshes.append(l)


func _lights() -> void:
	var key := SpotLight3D.new()
	key.light_energy = 3.0
	key.spot_range = 14.0
	key.spot_angle = 26.0
	key.light_color = Color(1.0, 0.96, 0.9)
	key.shadow_enabled = true
	key.position = Vector3(-1.5, 3.9, -2.0)
	add_child(key)
	key.look_at(PODIUM + Vector3(0, 1.4, 0.4), Vector3.UP)
	var fill := SpotLight3D.new()
	fill.light_energy = 1.6
	fill.spot_range = 14.0
	fill.spot_angle = 32.0
	fill.position = Vector3(2.0, 3.6, -1.8)
	add_child(fill)
	fill.look_at(PODIUM + Vector3(0, 1.4, 0.4), Vector3.UP)
	var room := OmniLight3D.new()
	room.light_energy = 1.2
	room.omni_range = 14.0
	room.position = Vector3(0, 3.8, -3.0)
	add_child(room)


func apply(seg: Dictionary, shot: Dictionary, lt: float, st: float, delta: float) -> void:
	var c := String(shot.get("cam", "presser_wide"))
	var f := ease01(st / maxf(float(shot.get("dur", 5.0)), 0.1))
	var head := PODIUM + Vector3(0, 1.62, 0.42)
	var sway := handheld(st, 0.05, 2.0)
	match c:
		"presser_close":
			var p := Vector3(0.35, 1.55, -5.2).lerp(Vector3(0.3, 1.55, -5.0), f)
			_look(p + Vector3(sway.x, sway.y, 0) * 0.01, head + Vector3(-0.22, -0.18, 0), 13.0)
			_dof(true, p.distance_to(head), 0.06)
		"presser_press":
			var p2 := Vector3(-3.2, 1.6, 2.0).lerp(Vector3(-3.0, 1.55, 1.6), f)
			_look(p2, Vector3(0.5, 0.9, -3.0), 50.0)
			_dof(false)
		_:
			var p3 := Vector3(-1.4, 1.9, -7.4).lerp(Vector3(-0.8, 1.85, -6.6), f)
			_look(p3 + Vector3(sway.x, sway.y, 0) * 0.02, PODIUM + Vector3(0, 1.3, 0), 36.0)
			_dof(false)
	# camera flashes: short pops at pseudo-random moments
	for i in _flash_meshes.size():
		var bucket := int((lt + i * 0.37) * 7.0)
		var on := U.hash_ints(bucket, i, 77) % 9 == 0 and fmod((lt + i * 0.37) * 7.0, 1.0) < 0.45
		(_flash_meshes[i] as OmniLight3D).light_energy = 6.0 if on else 0.0
