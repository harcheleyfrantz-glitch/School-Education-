class_name HumanMesh
extends RefCounted
## Procedural low-poly human used for every person in the game (passengers, crew, crowds,
## news footage). One shared mesh; the human shader poses it per instance from UV2 tags:
## UV2.x = body part id, UV2.y = colour slot.

enum Part { TORSO, HEAD, HAIR, UARM_L, FARM_L, UARM_R, FARM_R, THIGH_L, SHIN_L, THIGH_R, SHIN_R, BAG, PHONE, FACE, MOUTH, HAT }
enum Slot { SKIN, TOP, BOTTOM, SHOES, HAIR, BAG, DARK, PHONE, HAT, TRIM, SLEEVE, LEG }

const POSES := {
	"stand": 0, "walk": 1, "sit": 2, "brace": 3, "run": 4, "lie": 5, "demo": 6, "talk": 7, "sit_panic": 8,
	"sit_sleep": 9, "stow": 10, "wave": 11, "kneel": 12, "sit_film": 13, "film": 14, "sit_talk": 15,
	"sit_read": 16, "sit_clap": 17, "grief": 18, "sit_mask": 19, "push": 20,
}

static var _cache := {}


static func get_mesh(lod: int = 0) -> ArrayMesh:
	if _cache.has(lod):
		return _cache[lod]
	var m := _build(lod)
	_cache[lod] = m
	return m


static func _tag(mb: MeshBuilder, start: int, part: int, slot: int) -> void:
	for i in range(start, mb.verts.size()):
		mb.uv2s[i] = Vector2(part, slot)


static func _build(lod: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.use_uv2 = true
	var w := Color.WHITE
	var seg := 8 if lod == 0 else 5
	var s := 0
	# ---- torso: lofted elliptical rings, crotch to neck base
	var rings := []
	var prof := [
		[0.84, 0.13, 0.085, 0.0], [0.92, 0.165, 0.10, 0.0], [1.00, 0.158, 0.098, 0.0], [1.07, 0.150, 0.094, 0.0],
		[1.18, 0.168, 0.105, -0.008], [1.29, 0.178, 0.108, -0.01], [1.38, 0.19, 0.098, 0.0], [1.44, 0.15, 0.085, 0.0],
		[1.475, 0.075, 0.062, 0.0],
	]
	var tseg := 12 if lod == 0 else 8
	for pr in prof:
		var ring := PackedVector3Array()
		for k in tseg:
			var a := TAU * float(k) / tseg
			# squarer shoulders/hips than a pure ellipse
			var cx := cos(a)
			var sz := sin(a)
			var sq := 0.82
			var ex := signf(cx) * pow(absf(cx), sq)
			var ez := signf(sz) * pow(absf(sz), sq)
			ring.append(Vector3(ex * pr[1], pr[0], ez * pr[2] + pr[3]))
		rings.append(ring)
	s = mb.vcount()
	mb.add_loft(rings, w, true, false)
	_tag(mb, s, Part.TORSO, Slot.TOP)
	# lower torso band (belt/trouser waist) recoloured by the shader using height
	# ---- neck
	s = mb.vcount()
	mb.add_cylinder(Vector3(0, 1.44, 0.0), Vector3(0, 1.57, 0.004), 0.048, 0.044, seg, w, false)
	_tag(mb, s, Part.HEAD, Slot.SKIN)
	# ---- head
	s = mb.vcount()
	mb.add_sphere(Vector3(0, 1.665, 0.004), Vector3(0.083, 0.112, 0.098), 12 if lod == 0 else 7, 9 if lod == 0 else 5, w)
	_tag(mb, s, Part.HEAD, Slot.SKIN)
	if lod == 0:
		# nose and ears
		s = mb.vcount()
		mb.add_box(Vector3(0, 1.645, -0.092), Vector3(0.02, 0.038, 0.02), w)
		mb.add_sphere(Vector3(-0.083, 1.66, 0.006), Vector3(0.014, 0.026, 0.02), 5, 3, w)
		mb.add_sphere(Vector3(0.083, 1.66, 0.006), Vector3(0.014, 0.026, 0.02), 5, 3, w)
		_tag(mb, s, Part.HEAD, Slot.SKIN)
		# eyes and brows
		s = mb.vcount()
		for sx in [-1.0, 1.0]:
			mb.add_box(Vector3(sx * 0.030, 1.674, -0.0855), Vector3(0.015, 0.0085, 0.006), w)
			mb.add_box(Vector3(sx * 0.031, 1.694, -0.0835), Vector3(0.024, 0.005, 0.006), w)
		_tag(mb, s, Part.FACE, Slot.DARK)
		s = mb.vcount()
		mb.add_box(Vector3(0, 1.612, -0.0835), Vector3(0.03, 0.006, 0.006), w)
		_tag(mb, s, Part.MOUTH, Slot.DARK)
	# ---- hair cap: sphere shell cut lower at the face than at the back
	s = mb.vcount()
	_hair_cap(mb, Vector3(0, 1.672, 0.01), Vector3(0.091, 0.122, 0.106), 12 if lod == 0 else 7, 7 if lod == 0 else 4)
	_tag(mb, s, Part.HAIR, Slot.HAIR)
	# ---- arms
	for side in [-1.0, 1.0]:
		var sh := Vector3(side * 0.192, 1.415, 0.0)
		var el := Vector3(side * 0.205, 1.145, 0.01)
		var wr := Vector3(side * 0.21, 0.895, -0.005)
		s = mb.vcount()
		mb.add_sphere(sh + Vector3(-side * 0.008, -0.004, 0.0), Vector3(0.049, 0.05, 0.049), seg, 4, w)
		mb.add_cylinder(sh, el, 0.05, 0.041, seg, w, false)
		_tag(mb, s, Part.UARM_L if side < 0.0 else Part.UARM_R, Slot.TOP)
		s = mb.vcount()
		mb.add_sphere(el, Vector3(0.041, 0.041, 0.041), seg, 3, w)
		mb.add_cylinder(el, wr, 0.040, 0.031, seg, w, false)
		_tag(mb, s, Part.FARM_L if side < 0.0 else Part.FARM_R, Slot.SLEEVE)
		s = mb.vcount()
		mb.add_sphere(wr + Vector3(side * 0.004, -0.05, -0.004), Vector3(0.028, 0.06, 0.042), 6, 4, w)
		_tag(mb, s, Part.FARM_L if side < 0.0 else Part.FARM_R, Slot.SKIN)
	# ---- legs
	for side2 in [-1.0, 1.0]:
		var hp := Vector3(side2 * 0.092, 0.93, 0.0)
		var kn := Vector3(side2 * 0.095, 0.50, -0.01)
		var an := Vector3(side2 * 0.095, 0.085, 0.01)
		s = mb.vcount()
		mb.add_cylinder(hp + Vector3(0, 0.03, 0), kn, 0.083, 0.058, seg, w, false)
		_tag(mb, s, Part.THIGH_L if side2 < 0.0 else Part.THIGH_R, Slot.BOTTOM)
		s = mb.vcount()
		mb.add_sphere(kn, Vector3(0.058, 0.058, 0.058), seg, 3, w)
		mb.add_cylinder(kn, an, 0.056, 0.038, seg, w, false)
		_tag(mb, s, Part.SHIN_L if side2 < 0.0 else Part.SHIN_R, Slot.LEG)
		s = mb.vcount()
		mb.add_box(Vector3(side2 * 0.095, 0.04, -0.045), Vector3(0.088, 0.08, 0.25), w)
		_tag(mb, s, Part.SHIN_L if side2 < 0.0 else Part.SHIN_R, Slot.SHOES)
	# ---- rolling bag (hidden unless flagged)
	s = mb.vcount()
	mb.add_box(Vector3(0.34, 0.33, 0.26), Vector3(0.22, 0.5, 0.34), w)
	if lod == 0:
		mb.add_cylinder(Vector3(0.34, 0.58, 0.18), Vector3(0.34, 0.86, 0.06), 0.012, 0.012, 4, w, false)
		mb.add_cylinder(Vector3(0.30, 0.09, 0.40), Vector3(0.38, 0.09, 0.40), 0.035, 0.035, 6, w)
	_tag(mb, s, Part.BAG, Slot.BAG)
	# ---- phone (hidden unless flagged), held in the right hand
	s = mb.vcount()
	mb.add_box(Vector3(0.21, 0.83, -0.02), Vector3(0.012, 0.14, 0.07), w)
	_tag(mb, s, Part.PHONE, Slot.PHONE)
	# ---- hat / cap / helmet (outfit dependent)
	s = mb.vcount()
	mb.add_cylinder(Vector3(0, 1.735, 0.008), Vector3(0, 1.80, 0.008), 0.098, 0.094, 10 if lod == 0 else 6, w, true)
	mb.add_cylinder(Vector3(0, 1.735, -0.03), Vector3(0, 1.745, -0.06), 0.1, 0.1, 10 if lod == 0 else 6, w, true)
	_tag(mb, s, Part.HAT, Slot.HAT)
	var mesh := mb.commit()
	mesh.custom_aabb = AABB(Vector3(-1.0, -0.2, -1.0), Vector3(2.0, 2.4, 2.0))
	return mesh


static func _hair_cap(mb: MeshBuilder, c: Vector3, r: Vector3, segs: int, rings: int) -> void:
	var base := mb.vcount()
	for ri in rings + 1:
		for si in segs + 1:
			var th := TAU * float(si) / segs
			# th = 0 points to the back (+z); the cap reaches lower at the back and sides
			var back := (cos(th) + 1.0) * 0.5
			var max_phi := lerpf(0.36, 0.62, back) * PI
			var phi := max_phi * float(ri) / rings
			var n := Vector3(sin(phi) * sin(th), cos(phi), sin(phi) * cos(th))
			mb.add_vertex(c + n * r, (n / r).normalized(), Color.WHITE)
	for ri in rings:
		for si in segs:
			var i0 := base + ri * (segs + 1) + si
			var i1 := i0 + segs + 1
			mb.add_tri_idx(i0, i0 + 1, i1)
			mb.add_tri_idx(i0 + 1, i1 + 1, i1)
