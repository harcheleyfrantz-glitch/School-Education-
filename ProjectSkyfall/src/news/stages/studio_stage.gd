class_name StudioStage
extends NewsStage
## The news studio: a glossy floor with light inlays, a curved anchor desk with an LED fascia,
## a large video wall showing the story graphic, side LED columns, a night-city window, a
## lighting grid, pedestal cameras with prompters and the presenters at the desk. Shots: crane
## wide, two-shot, singles with shallow focus, an angle across the video wall.

var wall_vp: SubViewport
var graphic: StoryGraphic
var tint := Color(0.8, 0.1, 0.15)
var _two := true
const ANCHOR_A := Vector3(-0.62, 0.0, 0.98)
const ANCHOR_B := Vector3(0.62, 0.0, 0.98)
const DESK_C := Vector3(0.0, 0.0, 3.3)


func build(prog: Dictionary) -> void:
	super.build(prog)
	var outlet := String(prog.get("outlet", "skyline"))
	var st := NewsStyle.get_style(outlet)
	tint = Color.html(String(st.set_tint))
	_two = outlet != "skywatch"
	_environment()
	_floor()
	_desk(outlet)
	_video_wall(prog)
	_backdrop(outlet)
	_rig()
	_cameras()
	_lights()
	people = Crowd.new()
	add_child(people)
	people.setup(6, 0, "", true)
	var a := NewsStyle.anchor(outlet, U.hash_str(String(prog.get("incident", prog.get("title", "")))) % 2)
	var b := NewsStyle.anchor(outlet, U.hash_str(String(prog.get("incident", prog.get("title", "")))) % 2 + 1)
	var id_a := 1000 + U.hash_str(String(a[0])) % 9000
	var id_b := 1000 + U.hash_str(String(b[0])) % 9000
	_person(0, (ANCHOR_A if _two else Vector3(0, 0, 0.98)), deg_to_rad(-6.0) if _two else 0.0, "sit", Crowd.Outfit.SUIT, id_a, 0, Color(-1, 0, 0), 0.4, String(a[1]))
	if _two:
		_person(1, ANCHOR_B, deg_to_rad(8.0), "sit", Crowd.Outfit.SUIT, id_b, 0, Color(-1, 0, 0), 0.4, String(b[1]))
	# camera operators behind the pedestals
	_person(2, Vector3(-3.05, 0.0, -4.35), deg_to_rad(205.0), "stand", Crowd.Outfit.CIVIL, 77011, Crowd.FLAG_GLASSES, Color(0.08, 0.08, 0.09))
	_person(3, Vector3(3.15, 0.0, -4.4), deg_to_rad(158.0), "stand", Crowd.Outfit.CIVIL, 77023, 0, Color(0.1, 0.1, 0.12))
	# floor manager
	_person(4, Vector3(4.6, 0.0, -1.6), deg_to_rad(120.0), "stand", Crowd.Outfit.CIVIL, 77031, 0, Color(0.12, 0.12, 0.14))
	people.flush()
	_make_camera()


func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.4, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if Game.renderer == "forward_plus":
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 1.5
		env.ssao_enabled = true
		env.ssao_radius = 0.6
		env.ssao_intensity = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(34, 26)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.025, 0.03, 0.045)
	m.roughness = 0.14
	m.metallic = 0.35
	m.metallic_specular = 0.7
	mi.material_override = m
	mi.position = Vector3(0, 0, 2.0)
	add_child(mi)
	# light inlays: concentric rings around the desk and radial lines
	var mb := MeshBuilder.new()
	for ring in [[2.55, 0.035], [4.4, 0.05], [6.6, 0.03]]:
		_annulus(mb, Vector3(0, 0.004, 1.2), float(ring[0]), float(ring[0]) + float(ring[1]), 0.0, TAU, 96, Color.WHITE)
	for k in 12:
		var a := float(k) / 12.0 * TAU
		var d := Vector3(sin(a), 0, cos(a))
		var s := Vector3(d.z, 0, -d.x) * 0.012
		var p0 := Vector3(0, 0.005, 1.2) + d * 4.45
		var p1 := Vector3(0, 0.005, 1.2) + d * 6.55
		mb.add_quad(p0 - s, p0 + s, p1 + s, p1 - s, Color.WHITE)
	add_child(mesh_node(mb, unshaded(tint.lightened(0.15), 2.2), false))


func _annulus(mb: MeshBuilder, c: Vector3, r0: float, r1: float, a0: float, a1: float, n: int, col: Color, y_up: bool = true) -> void:
	for i in n:
		var u0 := a0 + (a1 - a0) * float(i) / n
		var u1 := a0 + (a1 - a0) * float(i + 1) / n
		var d0 := Vector3(sin(u0), 0, cos(u0))
		var d1 := Vector3(sin(u1), 0, cos(u1))
		if y_up:
			mb.add_quad(c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1, col)
		else:
			mb.add_quad(c + d0 * r1, c + d1 * r1, c + d1 * r0, c + d0 * r0, col)


func _desk(outlet: String) -> void:
	## A desk curved toward the cameras: glossy top, dark fascia with an LED band and logo.
	var top := MeshBuilder.new()
	var body := MeshBuilder.new()
	var led := MeshBuilder.new()
	var half := deg_to_rad(36.0) if _two else deg_to_rad(24.0)
	var n := 40
	var r_front := 3.3
	var r_back := 2.42
	for i in n:
		var u0 := PI - half + 2.0 * half * float(i) / n
		var u1 := PI - half + 2.0 * half * float(i + 1) / n
		var d0 := Vector3(sin(u0), 0, cos(u0))
		var d1 := Vector3(sin(u1), 0, cos(u1))
		var y_top := 0.745
		# top surface (with a lip over the fascia)
		top.add_quad(DESK_C + d0 * (r_front + 0.04) + Vector3(0, y_top, 0), DESK_C + d1 * (r_front + 0.04) + Vector3(0, y_top, 0),
			DESK_C + d1 * r_back + Vector3(0, y_top, 0), DESK_C + d0 * r_back + Vector3(0, y_top, 0), Color(0.93, 0.94, 0.96))
		top.add_quad(DESK_C + d1 * (r_front + 0.04) + Vector3(0, y_top - 0.045, 0), DESK_C + d0 * (r_front + 0.04) + Vector3(0, y_top - 0.045, 0),
			DESK_C + d0 * (r_front + 0.04) + Vector3(0, y_top, 0), DESK_C + d1 * (r_front + 0.04) + Vector3(0, y_top, 0), Color(0.75, 0.77, 0.8))
		# fascia, leaning slightly back toward the floor
		var f0 := DESK_C + d0 * r_front
		var f1 := DESK_C + d1 * r_front
		var b0 := DESK_C + d0 * (r_front - 0.14)
		var b1 := DESK_C + d1 * (r_front - 0.14)
		body.add_quad(b1 + Vector3(0, 0.06, 0), b0 + Vector3(0, 0.06, 0), f0 + Vector3(0, 0.37, 0), f1 + Vector3(0, 0.37, 0), Color(0.05, 0.055, 0.07))
		body.add_quad(f1 + Vector3(0, 0.45, 0), f0 + Vector3(0, 0.45, 0), f0 + Vector3(0, y_top - 0.045, 0), f1 + Vector3(0, y_top - 0.045, 0), Color(0.06, 0.065, 0.08))
		led.add_quad(f1 + Vector3(0, 0.37, 0), f0 + Vector3(0, 0.37, 0), f0 + Vector3(0, 0.45, 0), f1 + Vector3(0, 0.45, 0), Color.WHITE)
		# plinth glow on the floor
		led.add_quad(b1 + Vector3(0, 0.012, 0) + d1 * 0.03, b0 + Vector3(0, 0.012, 0) + d0 * 0.03, b0 + Vector3(0, 0.06, 0), b1 + Vector3(0, 0.06, 0), Color.WHITE)
		# back panel (anchor side) and a modesty board
		var k0 := DESK_C + d0 * r_back
		var k1 := DESK_C + d1 * r_back
		body.add_quad(k0 + Vector3(0, 0.55, 0), k1 + Vector3(0, 0.55, 0), k1 + Vector3(0, y_top, 0), k0 + Vector3(0, y_top, 0), Color(0.1, 0.1, 0.12))
	# end caps
	for side in [-1.0, 1.0]:
		var u: float = PI + half * float(side)
		var d := Vector3(sin(u), 0, cos(u))
		var pa := DESK_C + d * r_back
		var pb := DESK_C + d * (r_front + 0.04)
		var nrm: Vector3 = Vector3(cos(u), 0, -sin(u)) * float(side)
		var q := [pa, pb, pb + Vector3(0, 0.745, 0), pa + Vector3(0, 0.745, 0)]
		if nrm.x * side < 0.0:
			body.add_quad(q[1], q[0], q[3], q[2], Color(0.06, 0.065, 0.08))
		else:
			body.add_quad(q[0], q[1], q[2], q[3], Color(0.06, 0.065, 0.08))
	var tm := vcolor_mat(0.08, 0.0)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.clearcoat_enabled = true
	tm.clearcoat = 0.8
	add_child(mesh_node(top, tm))
	var bm := vcolor_mat(0.35, 0.4)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(mesh_node(body, bm))
	add_child(mesh_node(led, unshaded(tint, 3.0), false))
	# logo on the fascia
	var st := NewsStyle.get_style(outlet)
	var lbl := label3d(String(st.short), 96, 0.0032, Color(1, 1, 1), NewsStyle.head_font(outlet, 900))
	lbl.position = DESK_C + Vector3(0, 0.6, -r_front - 0.012)
	lbl.rotation.y = PI
	add_child(lbl)
	# props on the desk: papers, a laptop, mugs
	var pr := MeshBuilder.new()
	var xs := [ANCHOR_A.x, ANCHOR_B.x] if _two else [0.0]
	for x in xs:
		pr.add_box(Vector3(float(x) + 0.05, 0.752, 0.62), Vector3(0.3, 0.008, 0.22), Color(0.95, 0.95, 0.93))
		pr.add_box(Vector3(float(x) - 0.3, 0.76, 0.7), Vector3(0.34, 0.012, 0.24), Color(0.15, 0.16, 0.18))
		pr.add_box(Vector3(float(x) - 0.3, 0.86, 0.8), Vector3(0.34, 0.2, 0.012), Color(0.12, 0.13, 0.15))
		pr.add_cylinder(Vector3(float(x) + 0.35, 0.745, 0.55), Vector3(float(x) + 0.35, 0.85, 0.55), 0.04, 0.04, 12, tint.darkened(0.2))
	add_child(mesh_node(pr, vcolor_mat(0.4, 0.1)))
	# chairs
	var ch := MeshBuilder.new()
	for x2 in xs:
		var c := Vector3(float(x2), 0, 1.22)
		ch.add_cylinder(c, c + Vector3(0, 0.42, 0), 0.03, 0.03, 8, Color(0.3, 0.3, 0.32))
		ch.add_box(c + Vector3(0, 0.45, -0.05), Vector3(0.5, 0.07, 0.48), Color(0.08, 0.08, 0.09))
		ch.add_rounded_box(c + Vector3(0, 0.82, 0.2), Vector3(0.48, 0.62, 0.08), Color(0.07, 0.07, 0.08), 0.06, 10, 6)
		for k in 5:
			var a := float(k) / 5.0 * TAU
			ch.add_cylinder(c + Vector3(0, 0.04, 0), c + Vector3(sin(a) * 0.26, 0.03, cos(a) * 0.26), 0.02, 0.02, 6, Color(0.2, 0.2, 0.22))
	add_child(mesh_node(ch, vcolor_mat(0.5, 0.2)))


func _video_wall(prog: Dictionary) -> void:
	wall_vp = SubViewport.new()
	wall_vp.size = Vector2i(1024, 448)
	wall_vp.disable_3d = true
	wall_vp.transparent_bg = false
	wall_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(wall_vp)
	graphic = StoryGraphic.new()
	graphic.size = Vector2(1024, 448)
	graphic.setup(prog)
	wall_vp.add_child(graphic)
	var tex := wall_vp.get_texture()
	# main wall: slightly curved, made of panels
	var mb := MeshBuilder.new()
	var cols := 16
	var w := 9.6
	var h := 4.2
	var y0 := 0.55
	var z0 := 4.7
	for i in cols:
		var u0 := float(i) / cols
		var u1 := float(i + 1) / cols
		var x0 := w * 0.5 - w * u0
		var x1 := w * 0.5 - w * u1
		var zc0 := z0 - 0.35 * (1.0 - pow(x0 / (w * 0.5), 2.0))
		var zc1 := z0 - 0.35 * (1.0 - pow(x1 / (w * 0.5), 2.0))
		var p0 := Vector3(x0, y0, zc0)
		var p1 := Vector3(x1, y0, zc1)
		var p2 := Vector3(x1, y0 + h, zc1)
		var p3 := Vector3(x0, y0 + h, zc0)
		var vi := mb.vcount()
		var nrm := Vector3(0, 0, -1)
		# u flipped so the image reads correctly from the front
		mb.add_vertex(p0, nrm, Color.WHITE, Vector2(u0, 1))
		mb.add_vertex(p1, nrm, Color.WHITE, Vector2(u1, 1))
		mb.add_vertex(p2, nrm, Color.WHITE, Vector2(u1, 0))
		mb.add_vertex(p3, nrm, Color.WHITE, Vector2(u0, 0))
		mb.add_tri_idx(vi, vi + 1, vi + 2)
		mb.add_tri_idx(vi, vi + 2, vi + 3)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 1.35
	m.roughness = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall := mesh_node(mb, m, false)
	add_child(wall)
	# bezel and the wall's frame
	var fr := MeshBuilder.new()
	fr.add_box(Vector3(0, y0 - 0.12, z0 + 0.05), Vector3(w + 0.4, 0.24, 0.3), Color(0.04, 0.045, 0.06))
	fr.add_box(Vector3(0, y0 + h + 0.1, z0 + 0.05), Vector3(w + 0.4, 0.2, 0.3), Color(0.04, 0.045, 0.06))
	add_child(mesh_node(fr, vcolor_mat(0.4, 0.5)))
	# side LED columns with the outlet's colours
	var g := Gradient.new()
	g.set_color(0, tint.darkened(0.55))
	g.set_color(1, tint.lightened(0.1))
	g.add_point(0.5, tint)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	for side in [-1.0, 1.0]:
		var col_mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.3, 4.6)
		col_mi.mesh = qm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0, 0, 0)
		cm.emission_enabled = true
		cm.emission_texture = gt
		cm.emission_energy_multiplier = 1.6
		col_mi.material_override = cm
		col_mi.position = Vector3(side * 6.2, 2.75, 3.6)
		col_mi.rotation.y = PI + side * deg_to_rad(-32.0)
		col_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(col_mi)
	var spill := OmniLight3D.new()
	spill.light_color = tint.lerp(Color(0.6, 0.75, 1.0), 0.5)
	spill.light_energy = 0.9
	spill.omni_range = 7.0
	spill.position = Vector3(0, 2.4, 3.6)
	add_child(spill)


func _backdrop(outlet: String) -> void:
	## Studio walls with light slats, and a window onto the city at night.
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, 3.5, 6.6), Vector3(26, 7, 0.2), Color(0.07, 0.075, 0.095))
	mb.add_box(Vector3(-11.0, 3.5, 0), Vector3(0.2, 7, 18), Color(0.07, 0.075, 0.095))
	mb.add_box(Vector3(11.0, 3.5, 0), Vector3(0.2, 7, 18), Color(0.07, 0.075, 0.095))
	add_child(mesh_node(mb, vcolor_mat(0.7, 0.0), false))
	var slats := MeshBuilder.new()
	for i in 9:
		var x := -10.6 + i * 0.5
		slats.add_box(Vector3(x, 3.4, 6.45), Vector3(0.05, 5.8, 0.05), Color.WHITE)
		slats.add_box(Vector3(-x, 3.4, 6.45), Vector3(0.05, 5.8, 0.05), Color.WHITE)
	add_child(mesh_node(slats, unshaded(Color(0.55, 0.65, 0.9), 0.9), false))
	var city := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(8.0, 4.4)
	city.mesh = qm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0, 0, 0)
	cm.emission_enabled = true
	cm.emission_texture = _city_texture(U.hash_str(outlet))
	cm.emission_energy_multiplier = 1.1
	city.material_override = cm
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var c2 := city.duplicate() as MeshInstance3D
		c2.position = Vector3(side * 8.6, 2.9, 4.4)
		c2.rotation.y = PI + side * deg_to_rad(-48.0)
		add_child(c2)
	city.queue_free()


static func _city_texture(seed_v: int) -> ImageTexture:
	var r := U.rng(seed_v)
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var f := float(y) / h
		var sky := Color(0.02, 0.04, 0.1).lerp(Color(0.12, 0.08, 0.18), f * f)
		for x in w:
			img.set_pixel(x, y, sky)
	var x0 := 0
	while x0 < w:
		var bw := r.randi_range(14, 46)
		var bh := r.randi_range(50, 210)
		var base := Color(0.015, 0.02, 0.035)
		for yy in range(h - bh, h):
			for xx in range(x0, mini(x0 + bw, w)):
				var lit := false
				if (xx - x0) % 5 < 3 and (yy - (h - bh)) % 7 < 4 and xx - x0 > 1 and xx - x0 < bw - 2:
					lit = U.hash_ints(xx / 5, yy / 7, seed_v) % 100 < 38
				img.set_pixel(xx, yy, Color(1.0, 0.82, 0.5) * 0.85 if lit else base)
		x0 += bw + r.randi_range(0, 6)
	return ImageTexture.create_from_image(img)


func _rig() -> void:
	## Lighting grid: trusses with fresnel fixtures.
	var mb := MeshBuilder.new()
	var lens := MeshBuilder.new()
	for z in [-2.8, 0.2, 3.0]:
		mb.add_box(Vector3(0, 5.6, z), Vector3(16, 0.18, 0.18), Color(0.14, 0.14, 0.15))
		for i in 7:
			var x := -6.0 + i * 2.0
			mb.add_cylinder(Vector3(x, 5.5, z), Vector3(x, 5.0, z), 0.03, 0.03, 6, Color(0.1, 0.1, 0.1))
			mb.add_cylinder(Vector3(x, 5.0, z - 0.2), Vector3(x, 4.85, z + 0.22), 0.16, 0.16, 12, Color(0.06, 0.06, 0.07))
			lens.add_cylinder(Vector3(x, 4.84, z + 0.22), Vector3(x, 4.83, z + 0.235), 0.13, 0.13, 12, Color.WHITE)
	add_child(mesh_node(mb, vcolor_mat(0.5, 0.6), false))
	add_child(mesh_node(lens, unshaded(Color(1.0, 0.95, 0.85), 4.0), false))


func _cameras() -> void:
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	for c in [[Vector3(-2.75, 0, -3.75), 18.0], [Vector3(2.8, 0, -3.85), -16.0]]:
		var p: Vector3 = c[0]
		var b := Basis(Vector3.UP, deg_to_rad(float(c[1])))
		mb.xf = Transform3D(b, p)
		glow.xf = mb.xf
		for k in 3:
			var a := float(k) / 3.0 * TAU
			mb.add_cylinder(Vector3(0, 0.05, 0), Vector3(sin(a) * 0.45, 0.04, cos(a) * 0.45), 0.04, 0.04, 6, Color(0.15, 0.15, 0.16))
		mb.add_cylinder(Vector3(0, 0.05, 0), Vector3(0, 1.2, 0), 0.09, 0.07, 12, Color(0.18, 0.18, 0.2))
		mb.add_box(Vector3(0, 1.32, 0.05), Vector3(0.32, 0.26, 0.62), Color(0.1, 0.1, 0.11))
		mb.add_box(Vector3(0, 1.36, -0.42), Vector3(0.42, 0.36, 0.34), Color(0.05, 0.05, 0.055))
		mb.add_cylinder(Vector3(0, 1.3, -0.25), Vector3(0, 1.3, -0.62), 0.09, 0.1, 14, Color(0.03, 0.03, 0.03))
		mb.add_box(Vector3(0.0, 1.4, 0.45), Vector3(0.6, 0.06, 0.06), Color(0.2, 0.2, 0.22))
		glow.add_box(Vector3(0, 1.36, -0.25), Vector3(0.36, 0.28, 0.01), Color.WHITE)
		glow.add_box(Vector3(0.2, 1.52, -0.45), Vector3(0.03, 0.03, 0.03), Color(1, 0.1, 0.1))
	mb.xf = Transform3D.IDENTITY
	add_child(mesh_node(mb, vcolor_mat(0.45, 0.4)))
	add_child(mesh_node(glow, unshaded(Color(0.7, 0.85, 1.0), 1.4), false))


func _lights() -> void:
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.86)
	key.light_energy = 2.6
	key.spot_range = 12.0
	key.spot_angle = 28.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = true
	key.position = Vector3(-2.4, 3.6, -2.7)
	add_child(key)
	key.look_at(Vector3(-0.1, 1.15, 0.95), Vector3.UP)
	var fill := SpotLight3D.new()
	fill.light_color = Color(0.82, 0.9, 1.0)
	fill.light_energy = 1.4
	fill.spot_range = 12.0
	fill.spot_angle = 34.0
	fill.position = Vector3(2.7, 2.9, -2.5)
	add_child(fill)
	fill.look_at(Vector3(0.1, 1.15, 0.95), Vector3.UP)
	var back := SpotLight3D.new()
	back.light_color = Color(1.0, 0.97, 0.92)
	back.light_energy = 2.4
	back.spot_range = 8.0
	back.spot_angle = 38.0
	back.position = Vector3(0.0, 4.4, 3.0)
	add_child(back)
	back.look_at(Vector3(0, 1.0, 0.7), Vector3.UP)
	# coloured washes up the studio walls
	for wl in [[Vector3(-9.6, 0.3, -1.0), Vector3(-10.8, 4.0, 1.0)], [Vector3(9.6, 0.3, -1.0), Vector3(10.8, 4.0, 1.0)],
			[Vector3(-6.5, 0.3, 5.6), Vector3(-7.5, 4.5, 6.5)], [Vector3(6.5, 0.3, 5.6), Vector3(7.5, 4.5, 6.5)], [Vector3(0, 0.3, 5.9), Vector3(0, 5.0, 6.5)]]:
		var up := SpotLight3D.new()
		up.light_color = tint.lerp(Color(0.3, 0.45, 1.0), 0.35)
		up.light_energy = 4.0
		up.spot_range = 9.0
		up.spot_angle = 30.0
		up.position = wl[0]
		add_child(up)
		up.look_at(wl[1], Vector3.FORWARD)
	var accent := OmniLight3D.new()
	accent.light_color = tint
	accent.light_energy = 0.6
	accent.omni_range = 5.0
	accent.position = Vector3(0, 0.3, -0.6)
	add_child(accent)


# ================================================================== shots
func apply(seg: Dictionary, shot: Dictionary, lt: float, st: float, delta: float) -> void:
	var cam_name := String(shot.get("cam", "wide"))
	var sd := float(shot.get("dur", 6.0))
	var f := ease01(st / maxf(sd, 0.1))
	var a := ANCHOR_A if _two else Vector3(0, 0, 0.98)
	var b := ANCHOR_B
	var head_a := a + Vector3(0, 1.17, 0)
	var head_b := b + Vector3(0, 1.17, 0)
	var sway := handheld(st, 0.04, 1.0)
	match cam_name:
		"wide":
			var p := Vector3(-5.6, 3.9, -8.6).lerp(Vector3(-3.2, 2.1, -6.2), f)
			_look(p, Vector3(0, 1.25, 1.4), 46.0)
			_dof(false)
		"wide_out":
			var p2 := Vector3(-1.2, 1.5, -4.2).lerp(Vector3(4.8, 3.6, -8.4), f)
			_look(p2, Vector3(0, 1.3, 1.5), 48.0)
			_dof(false)
		"two":
			var mid := (head_a + head_b) * 0.5 if _two else head_a
			var p3 := Vector3(0, 1.32, -4.3).lerp(Vector3(0, 1.28, -3.7), f)
			_look(p3 + Vector3(sway.x, sway.y, 0) * 0.02, mid + Vector3(0, -0.12, 0), 30.0)
			_dof(true, p3.distance_to(mid), 0.04)
		"single_a", "single_b":
			var h := head_a if cam_name == "single_a" or not _two else head_b
			var off := Vector3(0.18 if cam_name == "single_a" else -0.18, 0.06, -2.5)
			var p4 := h + off + Vector3(0, 0, 0.12 * f)
			_look(p4 + Vector3(sway.x, sway.y, 0) * 0.01, h + Vector3(-0.34, -0.1, 0), 24.0)
			_dof(true, p4.distance_to(h), 0.09)
		"wall":
			var p5 := Vector3(3.3, 1.7, -2.6).lerp(Vector3(2.7, 1.6, -2.2), f)
			_look(p5, Vector3(-1.2, 1.55, 3.0), 44.0)
			_dof(false)
		_:
			_look(Vector3(0, 1.3, -4.0), Vector3(0, 1.2, 1.0), 32.0)
			_dof(false)
	if graphic:
		graphic.t = lt
