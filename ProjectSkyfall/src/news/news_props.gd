class_name NewsProps
extends RefCounted
## Procedural props for news sets: police cars with light bars, cordon tape, portable light
## towers, tents, rescue boats and life rafts, evidence markers, plus press-room and memorial
## pieces (podium, flags, microphones, candles, flowers, photographs, railings).

static var _cache := {}


static func _mat() -> StandardMaterial3D:
	if not _cache.has("vc"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.5
		m.metallic = 0.25
		_cache.vc = m
	return _cache.vc


static func _glow(col: Color, e: float) -> StandardMaterial3D:
	var key := "g%s%.1f" % [col.to_html(), e]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = e
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


static func _mi(mb: MeshBuilder, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = m
	return mi


## Police car facing -Z with a roof light bar. Children "Red"/"Blue" are the bar halves and
## "LR"/"LB" OmniLights the stage flashes.
static func police_car() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var white := Color(0.93, 0.94, 0.95)
	var blue := Color(0.08, 0.17, 0.5)
	var yel := Color(0.98, 0.82, 0.08)
	mb.add_rounded_box(Vector3(0, 0.72, 0), Vector3(1.86, 0.78, 4.75), white, 0.22, 14, 8)
	mb.add_rounded_box(Vector3(0, 1.32, 0.25), Vector3(1.66, 0.62, 2.5), Color(0.08, 0.1, 0.13), 0.25, 14, 8)
	mb.add_box(Vector3(0, 1.64, 0.25), Vector3(1.5, 0.05, 2.2), white)
	# battenburg band
	for side in [-1.0, 1.0]:
		for i in 8:
			var z := -2.1 + i * 0.6
			var col := blue if i % 2 == 0 else yel
			mb.add_box(Vector3(side * 0.935, 0.78, z + 0.3), Vector3(0.02, 0.3, 0.6), col)
			mb.add_box(Vector3(side * 0.935, 0.48, z + 0.3), Vector3(0.02, 0.3, 0.6), yel if i % 2 == 0 else blue)
	for w in [[-0.85, -1.45], [0.85, -1.45], [-0.85, 1.5], [0.85, 1.5]]:
		mb.add_cylinder(Vector3(float(w[0]) - 0.12, 0.34, float(w[1])), Vector3(float(w[0]) + 0.12, 0.34, float(w[1])), 0.34, 0.34, 14, Color(0.05, 0.05, 0.05))
	mb.add_box(Vector3(0, 1.72, 0.25), Vector3(1.3, 0.12, 0.3), Color(0.12, 0.12, 0.13))
	root.add_child(_mi(mb, _mat()))
	var r := MeshBuilder.new()
	r.add_box(Vector3(-0.35, 1.8, 0.25), Vector3(0.55, 0.1, 0.24), Color.WHITE)
	var red := _mi(r, _glow(Color(1.0, 0.08, 0.06), 6.0))
	red.name = "Red"
	root.add_child(red)
	var b := MeshBuilder.new()
	b.add_box(Vector3(0.35, 1.8, 0.25), Vector3(0.55, 0.1, 0.24), Color.WHITE)
	var bl := _mi(b, _glow(Color(0.1, 0.3, 1.0), 6.0))
	bl.name = "Blue"
	root.add_child(bl)
	var hl := MeshBuilder.new()
	for x in [-0.62, 0.62]:
		hl.add_box(Vector3(x, 0.82, -2.37), Vector3(0.36, 0.14, 0.04), Color.WHITE)
	root.add_child(_mi(hl, _glow(Color(1.0, 0.97, 0.9), 3.0)))
	for k in [["LR", Color(1.0, 0.1, 0.08), -0.4], ["LB", Color(0.15, 0.35, 1.0), 0.4]]:
		var l := OmniLight3D.new()
		l.name = String(k[0])
		l.light_color = k[1]
		l.omni_range = 22.0
		l.light_energy = 0.0
		l.position = Vector3(float(k[2]), 2.2, 0.25)
		root.add_child(l)
	return root


## Flash a police car's bar (or any node with Red/Blue/LR/LB) at time t.
static func flash(car: Node3D, t: float, phase: float, night: float) -> void:
	var a := fmod(t * 2.6 + phase, 1.0) < 0.5
	var red := car.get_node_or_null("Red") as MeshInstance3D
	var blue := car.get_node_or_null("Blue") as MeshInstance3D
	if red:
		red.visible = a
	if blue:
		blue.visible = not a
	var lr := car.get_node_or_null("LR") as OmniLight3D
	var lb := car.get_node_or_null("LB") as OmniLight3D
	if lr:
		lr.light_energy = (2.5 * night + 0.3) if a else 0.0
	if lb:
		lb.light_energy = 0.0 if a else (2.5 * night + 0.3)


## Police tape along points (local, on the ground): posts and a striped tape.
static func cordon(points: Array, seed_v: int) -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var tape := MeshBuilder.new()
	for i in points.size():
		var p: Vector3 = points[i]
		mb.add_cylinder(p, p + Vector3(0, 1.05, 0), 0.035, 0.03, 6, Color(0.85, 0.85, 0.85) if i % 2 == 0 else Color(0.9, 0.35, 0.1))
		mb.add_cylinder(p, p + Vector3(0, 0.05, 0), 0.18, 0.18, 8, Color(0.15, 0.15, 0.15))
		if i + 1 < points.size():
			var q: Vector3 = points[i + 1]
			var seg := 6
			for s in seg:
				var f0 := float(s) / seg
				var f1 := float(s + 1) / seg
				var a := p.lerp(q, f0) + Vector3(0, 0.95 - sin(f0 * PI) * 0.12, 0)
				var b := p.lerp(q, f1) + Vector3(0, 0.95 - sin(f1 * PI) * 0.12, 0)
				var col := Color(0.98, 0.84, 0.05) if (s + i) % 2 == 0 else Color(0.06, 0.06, 0.06)
				tape.add_quad(a, b, b + Vector3(0, 0.075, 0), a + Vector3(0, 0.075, 0), col)
	root.add_child(_mi(mb, _mat()))
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.vertex_color_is_srgb = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.roughness = 0.4
	root.add_child(_mi(tape, tm))
	return root


## Portable light tower: trailer, mast and four lamps lighting `target` (local).
static func light_tower(pos: Vector3, target: Vector3, on: bool) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(0, 0.7, 0), Vector3(1.4, 1.0, 2.6), Color(0.95, 0.7, 0.1))
	mb.add_cylinder(Vector3(0, 1.2, 0), Vector3(0, 8.0, 0), 0.09, 0.07, 8, Color(0.6, 0.6, 0.62))
	mb.add_box(Vector3(0, 8.0, 0), Vector3(1.6, 0.1, 0.1), Color(0.4, 0.4, 0.42))
	for w in [-0.75, 0.75]:
		mb.add_cylinder(Vector3(w - 0.1, 0.35, 0.6), Vector3(w + 0.1, 0.35, 0.6), 0.35, 0.35, 12, Color(0.05, 0.05, 0.05))
	root.add_child(_mi(mb, _mat()))
	var lamps := MeshBuilder.new()
	for i in 4:
		lamps.add_box(Vector3(-0.6 + i * 0.4, 8.25, 0), Vector3(0.34, 0.3, 0.12), Color.WHITE)
	var lm := _mi(lamps, _glow(Color(1.0, 0.98, 0.9), 8.0 if on else 0.2))
	root.add_child(lm)
	var to_t := target - pos
	lm.rotation.y = atan2(-to_t.x, -to_t.z)
	if on:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.97, 0.9)
		s.light_energy = 9.0
		s.spot_range = 160.0
		s.spot_angle = 38.0
		s.spot_attenuation = 0.8
		s.position = Vector3(0, 8.3, 0)
		root.add_child(s)
		s.look_at_from_position(pos + Vector3(0, 8.3, 0), target, Vector3.UP)
		s.position = Vector3(0, 8.3, 0)
	return root


static func tent(size: Vector3, col: Color, cross: bool) -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var h := size.y
	mb.add_box(Vector3(0, h * 0.35, 0), Vector3(size.x, h * 0.7, size.z), col)
	var a := Vector3(-size.x * 0.5, h * 0.7, -size.z * 0.5)
	var b := Vector3(size.x * 0.5, h * 0.7, -size.z * 0.5)
	var c := Vector3(size.x * 0.5, h * 0.7, size.z * 0.5)
	var d := Vector3(-size.x * 0.5, h * 0.7, size.z * 0.5)
	var top := Vector3(0, h, 0)
	mb.add_quad(a, b, top + Vector3(0.01, 0, 0), top, col.darkened(0.05))
	mb.add_quad(b, c, top, top + Vector3(0, 0, 0.01), col.darkened(0.1))
	mb.add_quad(c, d, top + Vector3(-0.01, 0, 0), top, col.darkened(0.05))
	mb.add_quad(d, a, top, top + Vector3(0, 0, -0.01), col.darkened(0.1))
	if cross:
		mb.add_box(Vector3(0, h * 0.45, -size.z * 0.5 - 0.02), Vector3(1.2, 0.35, 0.02), Color(0.85, 0.06, 0.06))
		mb.add_box(Vector3(0, h * 0.45, -size.z * 0.5 - 0.02), Vector3(0.35, 1.2, 0.02), Color(0.85, 0.06, 0.06))
	var m := _mat().duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.0
	m.roughness = 0.85
	root.add_child(_mi(mb, m))
	return root


static func boat(col: Color) -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var rings := []
	for i in 7:
		var f := float(i) / 6.0
		var z := -4.5 + f * 9.0
		var w := 1.25 * (1.0 - pow(maxf(-z, 0.0) / 4.6, 2.0) * 0.85) if z < 0.0 else 1.25
		var ring := PackedVector3Array()
		for k in 9:
			var a := PI + float(k) / 8.0 * PI
			ring.append(Vector3(cos(a) * w, sin(a) * 0.8 + 0.8 + (0.4 if z < -3.5 else 0.0), z))
		rings.append(ring)
	mb.add_loft(rings, col, false, true)
	mb.add_box(Vector3(0, 1.35, 0.8), Vector3(1.5, 0.9, 2.2), Color(0.92, 0.93, 0.95))
	mb.add_box(Vector3(0, 1.85, 0.8), Vector3(0.4, 0.12, 0.3), Color(0.1, 0.3, 1.0))
	var m := _mat().duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(_mi(mb, m))
	return root


static func raft() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	mb.add_rounded_box(Vector3(0, 0.25, 0), Vector3(3.2, 0.5, 4.4), Color(1.0, 0.42, 0.05), 0.24, 16, 8)
	mb.add_box(Vector3(0, 0.42, 0), Vector3(2.4, 0.06, 3.5), Color(0.1, 0.1, 0.1))
	root.add_child(_mi(mb, _mat()))
	return root


static func marker(col: Color) -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3.ZERO, Vector3(0, 0.7, 0), 0.012, 0.012, 4, Color(0.7, 0.7, 0.7))
	mb.add_quad(Vector3(0, 0.7, 0), Vector3(0.22, 0.6, 0), Vector3(0.22, 0.6, 0.001), Vector3(0, 0.5, 0), col)
	return mb


# ================================================================== press room and memorial
static func podium(front_col: Color) -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	mb.add_rounded_box(Vector3(0, 0.55, 0), Vector3(0.9, 1.1, 0.55), front_col, 0.04, 10, 6)
	mb.add_box(Vector3(0, 1.13, 0.04), Vector3(1.0, 0.05, 0.62), Color(0.18, 0.12, 0.08))
	for i in 5:
		var x := -0.24 + i * 0.12
		var top := Vector3(x * 0.6, 1.42 + (i % 2) * 0.04, -0.12)
		mb.add_cylinder(Vector3(x * 0.3, 1.15, 0.05), top, 0.008, 0.008, 5, Color(0.1, 0.1, 0.1))
		var cols := [Color(0.85, 0.1, 0.12), Color(0.1, 0.2, 0.55), Color(0.95, 0.75, 0.1), Color(0.12, 0.5, 0.3), Color(0.5, 0.2, 0.6)]
		mb.add_sphere(top, Vector3(0.035, 0.05, 0.035), 8, 5, cols[i])
		mb.add_box(top + Vector3(0, -0.07, 0), Vector3(0.05, 0.05, 0.05), cols[i])
	root.add_child(_mi(mb, _mat()))
	return root


static func flag(stripes: Array, size: Vector2, seed_v: float) -> Node3D:
	## A flag on a pole, gently folded (static folds, horizontal stripes top to bottom).
	var root := Node3D.new()
	var pole := MeshBuilder.new()
	pole.add_cylinder(Vector3.ZERO, Vector3(0, 2.6, 0), 0.025, 0.02, 8, Color(0.8, 0.72, 0.4))
	pole.add_sphere(Vector3(0, 2.63, 0), Vector3(0.05, 0.05, 0.05), 8, 6, Color(0.85, 0.75, 0.35))
	pole.add_cylinder(Vector3(0, 0, 0), Vector3(0, 0.08, 0), 0.22, 0.22, 12, Color(0.15, 0.15, 0.17))
	root.add_child(_mi(pole, _mat()))
	var cloth := MeshBuilder.new()
	var nx := 12
	var ns := stripes.size()
	for i in nx:
		var u0 := float(i) / nx
		var u1 := float(i + 1) / nx
		for s in ns:
			var v0 := float(s) / ns
			var v1 := float(s + 1) / ns
			var p := func(u: float, v: float) -> Vector3:
				var hang := u * u * 0.45
				return Vector3(0.03 + u * size.x * 0.82, 2.55 - v * size.y - hang * size.y, sin(u * 9.0 + seed_v) * 0.07 * u + sin(v * 3.0) * 0.02)
			cloth.add_quad(p.call(u0, v0), p.call(u1, v0), p.call(u1, v1), p.call(u0, v1), stripes[s])
	var cm := _mat().duplicate() as StandardMaterial3D
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.metallic = 0.0
	cm.roughness = 0.75
	root.add_child(_mi(cloth, cm))
	return root


## Candle with a flame (flame child named "Flame" for flicker).
static func candle(h: float, col: Color) -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.add_cylinder(Vector3.ZERO, Vector3(0, h, 0), 0.03, 0.03, 8, col)
	return mb


static func flowers(mb: MeshBuilder, center: Vector3, r: RandomNumberGenerator, n: int) -> void:
	var cols := [Color(0.95, 0.95, 0.92), Color(0.9, 0.2, 0.25), Color(0.98, 0.8, 0.2), Color(0.85, 0.5, 0.75), Color(0.95, 0.55, 0.15), Color(0.6, 0.3, 0.75)]
	for i in n:
		var p := center + Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.3, 0.3))
		var wrap_col: Color = [Color(0.92, 0.9, 0.85), Color(0.75, 0.85, 0.95), Color(0.25, 0.25, 0.28)][r.randi() % 3]
		mb.add_cone(p + Vector3(0, 0.02, 0), p + Vector3(r.randf_range(-0.05, 0.05), 0.45, r.randf_range(-0.05, 0.05)), 0.12, 6, wrap_col)
		for k in 5:
			var fp := p + Vector3(r.randf_range(-0.09, 0.09), 0.42 + r.randf_range(0.0, 0.08), r.randf_range(-0.09, 0.09))
			mb.add_sphere(fp, Vector3(0.045, 0.04, 0.045), 6, 4, cols[r.randi() % cols.size()])
