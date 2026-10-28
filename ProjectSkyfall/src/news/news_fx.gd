class_name NewsFX
extends RefCounted
## Effects for news footage: towering smoke columns that drift with the wind, fuel fires with
## flickering light, fire-tender water and foam jets, the impact fireball, and procedural decal
## textures for scorch marks, ground scars and foam.

static var _tex := {}


static func soft_tex() -> Texture2D:
	return TexGen.smoke_tex(64)


static func _billboard_mat(add: bool, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if add else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = tex
	m.roughness = 1.0
	m.disable_receive_shadows = true
	return m


## A rising, wind-drifting smoke column. scale ~1 for a big airliner fire.
static func smoke_column(scale: float, wind: Vector3, dark: float = 1.0, amount: int = 160) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.local_coords = false
	p.fixed_fps = 20
	p.visibility_aabb = AABB(Vector3(-800, -50, -800), Vector3(1600, 900, 1600))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 7.0 * scale
	pm.initial_velocity_max = 12.0 * scale
	pm.gravity = Vector3(wind.x, 0.6, wind.z) * 0.9
	pm.damping_min = 0.15
	pm.damping_max = 0.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 9.0 * scale
	pm.scale_min = 7.0 * scale
	pm.scale_max = 12.0 * scale
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.3, 1.2))
	curve.add_point(Vector2(1, 4.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	var c0 := Color(0.06, 0.055, 0.05).lerp(Color(0.45, 0.44, 0.42), 1.0 - dark)
	grad.set_color(0, Color(c0, 0.0))
	grad.add_point(0.04, Color(c0, 0.9))
	grad.add_point(0.5, Color(c0.lerp(Color(0.3, 0.3, 0.3), 0.4), 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.42, 0.42, 0.42, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	q.material = _billboard_mat(false, soft_tex())
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func flames(scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 3.0 * scale
	pm.initial_velocity_max = 7.0 * scale
	pm.gravity = Vector3(0, 4.0 * scale, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.5 * scale
	pm.scale_min = 2.2 * scale
	pm.scale_max = 4.2 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.65, 1.0))
	grad.add_point(0.3, Color(1.0, 0.55, 0.12, 0.95))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.07, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.9)
	q.material = _billboard_mat(true, GroundOps._soft_dot())
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Water or foam jet from a fire tender's monitor toward a target (local direction).
static func jet(dir: Vector3, speed: float, foam: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 4.0
	pm.initial_velocity_min = speed * 0.9
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color = Color(0.95, 0.97, 1.0, 0.55) if foam else Color(0.85, 0.92, 1.0, 0.45)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _billboard_mat(false, GroundOps._soft_dot())
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Fireball as a deterministic function of time since impact (seekable): an expanding,
## cooling ball and a dust ring. Returns the node; call fireball_pose() each frame.
static func fireball() -> Node3D:
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.6, 0.15, 1.0)
	m.albedo_texture = soft_tex()
	ball.material_override = m
	ball.name = "Ball"
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.45, 0.38, 0.3, 0.6)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.name = "Ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 400.0
	light.name = "Light"
	root.add_child(light)
	return root


static func fireball_pose(fb: Node3D, since: float, size: float) -> void:
	var ball := fb.get_node("Ball") as MeshInstance3D
	var ring := fb.get_node("Ring") as MeshInstance3D
	var light := fb.get_node("Light") as OmniLight3D
	var vis := since >= 0.0 and since < 7.0
	fb.visible = vis
	if not vis:
		return
	var grow := 1.0 - exp(-since * 2.2)
	var r := size * (0.25 + grow)
	ball.scale = Vector3(r, r * 0.8, r)
	ball.position.y = r * 0.5 + since * size * 0.25
	var heat := clampf(1.0 - since / 4.5, 0.0, 1.0)
	var bm := ball.material_override as StandardMaterial3D
	bm.albedo_color = Color(1.0, 0.45 + 0.4 * heat, 0.1 + 0.3 * heat, heat * heat)
	ring.scale = Vector3.ONE * size * (0.4 + since * 1.6)
	(ring.material_override as StandardMaterial3D).albedo_color = Color(0.45, 0.38, 0.3, 0.6 * clampf(1.0 - since / 5.0, 0.0, 1.0))
	light.light_energy = 16.0 * heat * heat


static func decal_tex(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = U.hash_str(kind)
	n.frequency = 0.05
	n.fractal_octaves = 4
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) / size * 2.0 - Vector2.ONE
			var nn := n.get_noise_2d(x, y) * 0.5 + 0.5
			var d := p.length()
			var a := 0.0
			var c := Color(0.03, 0.025, 0.02)
			match kind:
				"scar":
					var w := 0.55 + 0.35 * nn
					a = clampf((w - absf(p.x)) * 5.0, 0.0, 1.0) * clampf((1.0 - absf(p.y)) * 6.0, 0.0, 1.0)
					c = Color(0.16, 0.11, 0.07).lerp(Color(0.04, 0.03, 0.025), nn)
				"foam":
					a = clampf((0.85 - d - (nn - 0.5) * 0.5) * 4.0, 0.0, 1.0) * (0.6 + 0.4 * nn)
					c = Color(0.95, 0.96, 0.95)
				_:
					a = clampf((1.0 - d - (nn - 0.5) * 0.6) * 2.5, 0.0, 1.0)
					c = Color(0.02, 0.018, 0.015).lerp(Color(0.12, 0.09, 0.06), nn * (1.0 - a))
			img.set_pixel(x, y, Color(c, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex[kind] = tex
	return tex


static func decal(kind: String, size: Vector3) -> Decal:
	var d := Decal.new()
	d.size = size
	d.texture_albedo = decal_tex(kind)
	d.cull_mask = 0xFFFFF
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	return d
