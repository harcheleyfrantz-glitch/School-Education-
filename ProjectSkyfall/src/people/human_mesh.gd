class_name HumanMesh
extends RefCounted
## Procedural human used for every person in the game (passengers, crew, crowds, news footage).
## One shared mesh built from smooth parametric surfaces; the human shader poses and dresses it
## per instance. UV2.x = body part, UV2.y = colour slot, UV.x = variant (hair style etc.).
## Rest pose: standing, facing -Z, feet at y = 0, about 1.75 m tall.

enum Part { TORSO, HEAD, HAIR, UARM_L, FARM_L, UARM_R, FARM_R, THIGH_L, SHIN_L, THIGH_R, SHIN_R, BAG, PHONE,
	FACE, MOUTH, HAT, HELMET, SKIRT, TIE, BACKPACK, GLASSES, EYES }
enum Slot { SKIN, TOP, BOTTOM, SHOES, HAIR, BAG, DARK, PHONE, HAT, TRIM, SLEEVE, LEG, SOLE, LIPS, EYE_WHITE,
	IRIS, COLLAR, TIE, FRAME }

const POSES := {
	"stand": 0, "walk": 1, "sit": 2, "brace": 3, "run": 4, "lie": 5, "demo": 6, "talk": 7, "sit_panic": 8,
	"sit_sleep": 9, "stow": 10, "wave": 11, "kneel": 12, "sit_film": 13, "film": 14, "sit_talk": 15,
	"sit_read": 16, "sit_clap": 17, "grief": 18, "sit_mask": 19, "push": 20,
}
const HAIR_STYLES := 8   # 0 crop, 1 side part, 2 long, 3 bun, 4 ponytail, 5 curly, 6 bob, 7 receding

# skeleton (must match shaders/human.gdshader)
const HIP := Vector3(0.092, 0.93, 0.0)
const KNEE := Vector3(0.095, 0.50, -0.01)
const ANKLE := Vector3(0.095, 0.085, 0.01)
const SHOULDER := Vector3(0.192, 1.415, 0.0)
const ELBOW := Vector3(0.205, 1.145, 0.01)
const WRIST := Vector3(0.21, 0.895, -0.005)
const HEAD_C := Vector3(0.0, 1.665, 0.004)
const HEAD_R := Vector3(0.08, 0.111, 0.098)

static var _cache := {}

var mb: MeshBuilder
var q := 1.0          # resolution scale
var _part := 0
var _slot := 0
var _var := 0.0


static func get_mesh(lod: int = 0) -> ArrayMesh:
	if _cache.has(lod):
		return _cache[lod]
	var h := HumanMesh.new()
	var m := h._build(lod)
	_cache[lod] = m
	return m


# ---------------------------------------------------------------------------- surface helpers
func _tag(part: int, slot: int, variant: float = 0.0) -> void:
	_part = part
	_slot = slot
	_var = variant


func _vertex(p: Vector3, n: Vector3) -> int:
	return mb.add_vertex(p, n, Color.WHITE, Vector2(_var, 0.0), Vector2(_part, _slot))


## Parametric surface P(u, v) with u in [0,1] (wrapped when closed_u) and v in [0,1].
## ref(p) returns a point "inside" the surface so normals and winding face outward.
func _surface(P: Callable, nu: int, nv: int, closed_u: bool, ref: Callable) -> void:
	var cols := nu + 1
	var base := mb.vcount()
	var pts := []
	for j in nv + 1:
		var row := []
		for i in cols:
			var u := float(i) / nu
			if closed_u and i == nu:
				u = 0.0
			row.append(P.call(u, float(j) / nv))
		pts.append(row)
	for j in nv + 1:
		for i in cols:
			var p: Vector3 = pts[j][i]
			var i0 := i - 1 if i > 0 else (nu - 1 if closed_u else 0)
			var i1 := i + 1 if i < nu else (1 if closed_u else nu)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, nv)
			var du: Vector3 = pts[j][i1] - pts[j][i0]
			var dv: Vector3 = pts[j1][i] - pts[j0][i]
			var n := du.cross(dv)
			var outward: Vector3 = p - ref.call(p)
			if n.length_squared() < 1e-14:
				n = outward
			if n.dot(outward) < 0.0:
				n = -n
			_vertex(p, n.normalized())
	# winding from a representative quad
	for j in nv:
		for i in nu:
			var a := base + j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			var pa: Vector3 = mb.verts[a]
			var pb: Vector3 = mb.verts[b]
			var pc: Vector3 = mb.verts[c]
			var fn := (pb - pa).cross(pc - pa)
			var outward2: Vector3 = mb.normals[a] + mb.normals[d]
			if fn.dot(outward2) > 0.0:
				mb.add_tri_idx(a, c, b)
				mb.add_tri_idx(b, c, d)
			else:
				mb.add_tri_idx(a, b, c)
				mb.add_tri_idx(b, d, c)


static func _sgnpow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


static func _lerp_rows(rows: Array, v: float) -> Array:
	## Smoothly interpolate a table of numeric rows by parameter v in [0,1].
	var f := v * (rows.size() - 1)
	var i := clampi(int(floor(f)), 0, rows.size() - 2)
	var t := f - i
	t = t * t * (3.0 - 2.0 * t)
	var a: Array = rows[i]
	var b: Array = rows[i + 1]
	var out := []
	for k in a.size():
		out.append(lerpf(float(a[k]), float(b[k]), t))
	return out


## Tapered limb between joints a and b. prof(v) -> [r_side, r_front, bulge_front, bulge_back].
func _limb(a: Vector3, b: Vector3, prof: Callable, nu: int, nv: int, cap_a: bool, cap_b: bool) -> void:
	var d := (b - a).normalized()
	var side := Vector3.RIGHT - d * d.dot(Vector3.RIGHT)
	if side.length() < 0.1:
		side = Vector3.BACK - d * d.dot(Vector3.BACK)
	side = side.normalized()
	var front := d.cross(side).normalized()
	if front.z > 0.0:
		front = -front
	var L := a.distance_to(b)
	var P := func(u: float, v: float) -> Vector3:
		var ang := u * TAU
		var pr: Array = prof.call(v)
		var cs := cos(ang)
		var sn := sin(ang)
		var rf := float(pr[1]) + (float(pr[2]) if sn > 0.0 else float(pr[3])) * absf(sn)
		var r_s := float(pr[0])
		# rounded ends
		var endk := 1.0
		if cap_a and v < 0.08:
			endk = sqrt(maxf(1.0 - pow((0.08 - v) / 0.08, 2.0), 0.0))
		if cap_b and v > 0.92:
			endk = sqrt(maxf(1.0 - pow((v - 0.92) / 0.08, 2.0), 0.0))
		return a + d * (v * L) + side * cs * r_s * endk + front * sn * rf * endk
	var ref := func(p: Vector3) -> Vector3:
		var t := clampf((p - a).dot(d), 0.0, L)
		return a + d * t
	_surface(P, nu, nv, true, ref)


# ---------------------------------------------------------------------------- build
func _build(lod: int) -> ArrayMesh:
	mb = MeshBuilder.new()
	mb.use_uv2 = true
	# lod -1 is the high-resolution mesh for skinned hero characters (SkinnedHuman)
	q = 1.55 if lod < 0 else [1.0, 0.6, 0.38][clampi(lod, 0, 2)]
	var dl := maxi(lod, 0)
	var su := func(n: float) -> int: return maxi(int(round(n * q)), 4)
	_torso(su)
	_neck_head(su, dl)
	_arms(su, dl)
	_legs(su, dl)
	_hair(su, dl)
	_clothing_extras(su, dl)
	_props(su, dl)
	var mesh := mb.commit()
	mesh.custom_aabb = AABB(Vector3(-1.1, -0.3, -1.1), Vector3(2.2, 2.5, 2.2))
	return mesh


func _torso(su: Callable) -> void:
	# y, half width, front depth, back depth, z shift, squareness
	var rows := [
		[0.835, 0.105, 0.075, 0.085, 0.0, 1.0],
		[0.88, 0.150, 0.088, 0.112, 0.0, 0.86],
		[0.95, 0.168, 0.090, 0.118, 0.0, 0.84],
		[1.02, 0.155, 0.088, 0.098, 0.0, 0.9],
		[1.08, 0.150, 0.092, 0.090, 0.0, 0.92],
		[1.16, 0.160, 0.104, 0.092, -0.004, 0.88],
		[1.24, 0.172, 0.114, 0.098, -0.006, 0.86],
		[1.30, 0.180, 0.110, 0.102, -0.004, 0.88],
		[1.355, 0.184, 0.096, 0.098, 0.0, 0.92],
		[1.405, 0.162, 0.076, 0.086, 0.004, 0.95],
		[1.445, 0.105, 0.062, 0.07, 0.006, 0.98],
		[1.472, 0.058, 0.05, 0.054, 0.006, 1.0],
	]
	_tag(Part.TORSO, Slot.TOP)
	var P := func(u: float, v: float) -> Vector3:
		var r := _lerp_rows(rows, v)
		var ang := u * TAU
		var e: float = r[5]
		var cx := _sgnpow(cos(ang), e)
		var sz := sin(ang)
		var depth: float = r[3] if sz > 0.0 else r[2]
		var z := _sgnpow(sz, e) * depth + float(r[4])
		# shoulder blades and chest have slightly flatter faces
		return Vector3(cx * float(r[1]), float(r[0]), z)
	var ref := func(p: Vector3) -> Vector3: return Vector3(0.0, p.y, 0.0)
	_surface(P, su.call(28), su.call(22), true, ref)
	# crotch cap
	_tag(Part.TORSO, Slot.TOP)
	var c := _vertex(Vector3(0, 0.82, 0.004), Vector3.DOWN)
	var st := mb.vcount()
	var n := 16
	for i in n:
		var a := TAU * float(i) / n
		_vertex(Vector3(cos(a) * 0.105, 0.836, sin(a) * (0.085 if sin(a) > 0.0 else 0.075)), Vector3.DOWN)
	for i in n:
		mb.add_tri_idx(c, st + i, st + (i + 1) % n)


func _head_point(u: float, v: float, inflate: float = 0.0) -> Vector3:
	## Sculpted head: u = azimuth (0 at +x, 0.25 at back +z), v = polar (0 top .. 1 bottom).
	var ang := u * TAU
	var pol := v * PI
	var dx := sin(pol) * cos(ang)
	var dz := sin(pol) * sin(ang)
	var dy := cos(pol)
	var r := HEAD_R + Vector3(inflate, inflate, inflate)
	var x := dx * r.x
	var y := dy * r.y
	var z := dz * r.z
	# jaw narrows toward the chin, chin juts forward slightly
	var low := clampf((-dy - 0.15) / 0.85, 0.0, 1.0)
	x *= lerpf(1.0, 0.86, pow(low, 1.7))
	if dz < 0.0:
		var fr := smoothstep(0.0, -0.6, dz)
		z *= lerpf(1.0, 0.9, low)
		z -= 0.014 * pow(low, 1.5) * fr
		# longer lower face: chin and jaw line sit lower at the front
		y -= 0.016 * smoothstep(0.25, 0.9, -dy) * fr
	# fuller cranium at the back, flatter face and temples
	if dz > 0.0 and dy > -0.3:
		z *= 1.06
	if dz < -0.5:
		z *= 0.96
	x *= 1.0 - 0.06 * smoothstep(0.2, 0.7, dy) * absf(dx)
	# cheekbones
	var cheek := exp(-pow((dy + 0.12) / 0.18, 2.0)) * smoothstep(-0.2, -0.75, dz) * smoothstep(0.25, 0.6, absf(dx))
	x += signf(dx) * 0.006 * cheek
	z -= 0.004 * cheek
	# eye sockets
	for sx in [-1.0, 1.0]:
		var e := exp(-(pow((dx - sx * 0.38) / 0.16, 2.0) + pow((dy - 0.08) / 0.12, 2.0))) * smoothstep(-0.4, -0.8, dz)
		z += 0.007 * e
	return HEAD_C + Vector3(x, y, z)


func _neck_head(su: Callable, lod: int) -> void:
	# neck
	_tag(Part.HEAD, Slot.SKIN)
	_limb(Vector3(0, 1.43, 0.008), Vector3(0, 1.6, 0.0), func(v: float) -> Array:
		return [0.058 - 0.008 * v, 0.054 - 0.006 * v, 0.006 * (1.0 - v), 0.0], su.call(14), su.call(5), false, false)
	# head
	_tag(Part.HEAD, Slot.SKIN)
	var P := func(u: float, v: float) -> Vector3: return _head_point(u, v)
	var ref := func(p: Vector3) -> Vector3: return HEAD_C
	_surface(P, su.call(30), su.call(22), true, ref)
	# ears
	for sx in [-1.0, 1.0]:
		var ec := Vector3(sx * 0.077, 1.66, 0.014)
		_tag(Part.HEAD, Slot.SKIN)
		var Pe := func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var pol := v * PI
			var p := Vector3(sin(pol) * cos(a) * 0.008, cos(pol) * 0.026, sin(pol) * sin(a) * 0.016)
			p.x += sx * 0.004 * sin(pol)
			return ec + p.rotated(Vector3.UP, sx * 0.18)
		_surface(Pe, su.call(10), su.call(7), true, func(p: Vector3) -> Vector3: return ec)
	# nose: ridge, rounded tip and nostril underside
	_tag(Part.HEAD, Slot.SKIN)
	var nose_rows := [
		[1.694, -0.0895, 0.0075, -0.0835],
		[1.676, -0.0955, 0.0088, -0.0855],
		[1.656, -0.1025, 0.0108, -0.0875],
		[1.640, -0.1075, 0.0138, -0.0885],
		[1.630, -0.1065, 0.0162, -0.0888],
		[1.6215, -0.0995, 0.0158, -0.0888],
	]
	var Pn := func(u: float, v: float) -> Vector3:
		var r := _lerp_rows(nose_rows, v)
		var a := u * PI
		var sa := sin(a)
		return Vector3(-cos(a) * float(r[2]) * (0.75 + 0.25 * sa), float(r[0]), float(r[3]) + (float(r[1]) - float(r[3])) * sa)
	_surface(Pn, su.call(10), su.call(7), false, func(p: Vector3) -> Vector3: return Vector3(0, p.y, -0.07))
	var lastr: Array = nose_rows[nose_rows.size() - 1]
	var nb := Vector3(0, float(lastr[0]), (float(lastr[1]) + float(lastr[3])) * 0.5)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * PI
		var sa := sin(a)
		var edge := Vector3(-cos(a) * float(lastr[2]) * (0.75 + 0.25 * sa), float(lastr[0]), float(lastr[3]) + (float(lastr[1]) - float(lastr[3])) * sa)
		return nb.lerp(edge, v), su.call(10), 2, false, func(p: Vector3) -> Vector3: return nb + Vector3(0, 0.03, 0))
	if lod >= 2:
		return
	# eyes (whites + irises), brows, lips
	for sx2 in [-1.0, 1.0]:
		var c := Vector3(sx2 * 0.03, 1.677, -0.0745)
		_tag(Part.EYES, Slot.EYE_WHITE)
		_surface(func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var pol := v * PI
			return c + Vector3(sin(pol) * cos(a) * 0.0115, cos(pol) * 0.0092, sin(pol) * sin(a) * 0.0108), su.call(10), su.call(7), true, func(p: Vector3) -> Vector3: return c)
		var ic := c + Vector3(0, 0, -0.0097)
		_tag(Part.EYES, Slot.IRIS)
		_surface(func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var rr := v * 0.0063
			return ic + Vector3(cos(a) * rr, sin(a) * rr, -0.0019 * (1.0 - v * v)), su.call(12), 2, true, func(p: Vector3) -> Vector3: return ic + Vector3(0, 0, 0.01))
		# upper and lower lids (skin) frame the eye for a calm, natural look
		_tag(Part.EYES, Slot.SKIN)
		var lc := c + Vector3(0, 0.0022, 0.0005)
		_surface(func(u: float, v: float) -> Vector3:
			var a := u * PI
			var pol := v * PI * 0.5
			return lc + Vector3(-cos(a) * 0.0128 * sin(pol + 0.35), cos(pol) * 0.0088, -sin(a) * 0.0122 * sin(pol + 0.35)), su.call(10), 3, false, func(p: Vector3) -> Vector3: return lc + Vector3(0, -0.004, 0.0))
		var lc2 := c + Vector3(0, -0.0035, 0.0012)
		_surface(func(u: float, v: float) -> Vector3:
			var a := u * PI
			var pol := PI - v * PI * 0.32
			return lc2 + Vector3(-cos(a) * 0.0122 * sin(pol), cos(pol) * 0.0068, -sin(a) * 0.0113 * sin(pol)), su.call(10), 2, false, func(p: Vector3) -> Vector3: return lc2 + Vector3(0, 0.004, 0.0))
		# eyebrow following the brow ridge
		_tag(Part.FACE, Slot.HAIR)
		var b0 := Vector3(sx2 * 0.011, 1.6935, -0.0875)
		var bm := Vector3(sx2 * 0.032, 1.6975, -0.0845)
		var b1 := Vector3(sx2 * 0.051, 1.6945, -0.0765)
		_limb(b0, bm, func(v: float) -> Array: return [0.0022, 0.0013 + 0.0004 * v, 0.0, 0.0], 5, 3, true, false)
		_limb(bm, b1, func(v: float) -> Array: return [0.0022, 0.0017 - 0.0009 * v, 0.0, 0.0], 5, 3, false, true)
	# lips
	_tag(Part.HEAD, Slot.LIPS)
	var ul := Vector3(0, 1.6105, -0.0885)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI
		var w := 0.0185 * (1.0 - 0.15 * absf(cos(a)))
		return ul + Vector3(sin(pol) * cos(a) * w, cos(pol) * 0.0033 * (1.0 + 0.3 * (1.0 - absf(cos(a)))), sin(pol) * sin(a) * 0.0058), su.call(12), su.call(5), true, func(p: Vector3) -> Vector3: return ul)
	_tag(Part.MOUTH, Slot.LIPS)
	var ll := Vector3(0, 1.6035, -0.0875)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI
		return ll + Vector3(sin(pol) * cos(a) * 0.0165, cos(pol) * 0.0038, sin(pol) * sin(a) * 0.006), su.call(12), su.call(5), true, func(p: Vector3) -> Vector3: return ll)


func _arms(su: Callable, lod: int) -> void:
	for side in [-1.0, 1.0]:
		var sh := Vector3(side * SHOULDER.x, SHOULDER.y, SHOULDER.z)
		var el := Vector3(side * ELBOW.x, ELBOW.y, ELBOW.z)
		var wr := Vector3(side * WRIST.x, WRIST.y, WRIST.z)
		var up := Part.UARM_L if side < 0.0 else Part.UARM_R
		var fa := Part.FARM_L if side < 0.0 else Part.FARM_R
		# deltoid cap blends the arm into the shoulder
		_tag(up, Slot.TOP)
		var dc := sh + Vector3(side * -0.012, -0.008, 0.0)
		_surface(func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var pol := v * PI * 0.62
			return dc + Vector3(side * cos(pol) * 0.05, sin(pol) * cos(a) * 0.047 + 0.004, sin(pol) * sin(a) * 0.048), su.call(14), su.call(6), true, func(p: Vector3) -> Vector3: return dc)
		_limb(sh + Vector3(0, 0.02, 0), el, func(v: float) -> Array:
			var bicep := exp(-pow((v - 0.45) / 0.3, 2.0))
			return [0.047 - 0.01 * v + 0.004 * bicep, 0.045 - 0.008 * v, 0.006 * bicep, 0.003 * bicep], su.call(14), su.call(8), false, false)
		_tag(fa, Slot.SLEEVE)
		_limb(el + Vector3(0, 0.02, 0), wr, func(v: float) -> Array:
			var bulge := exp(-pow((v - 0.25) / 0.25, 2.0))
			return [0.037 + 0.006 * bulge - 0.01 * v, 0.036 + 0.004 * bulge - 0.014 * v, 0.002, 0.003 * bulge], su.call(14), su.call(8), false, false)
		# hand: palm and fingers as one lofted mitten, plus a thumb
		_tag(fa, Slot.SKIN)
		var h0 := wr + Vector3(0, 0.012, 0)
		var h1 := wr + Vector3(side * -0.006, -0.175, -0.012)
		_limb(h0, h1, func(v: float) -> Array:
			var w := 0.031 + 0.012 * sin(minf(v * 1.6, 1.0) * PI * 0.5) - 0.02 * smoothstep(0.62, 1.0, v)
			var t := 0.017 - 0.006 * smoothstep(0.5, 1.0, v)
			return [t, w, 0.0, 0.0], su.call(12), su.call(9), false, true)
		var tb0 := wr + Vector3(side * -0.008, -0.03, -0.028)
		var tb1 := wr + Vector3(side * -0.02, -0.09, -0.04)
		_limb(tb0, tb1, func(v: float) -> Array: return [0.011 - 0.003 * v, 0.012 - 0.003 * v, 0.0, 0.0], su.call(8), su.call(5), true, true)
		if lod == 0:
			# knuckle ridge hints at fingers
			for k in 3:
				var kz := -0.012 + float(k) * 0.012
				var kp := wr + Vector3(side * -0.002, -0.118, kz - 0.006)
				_limb(kp, kp + Vector3(0, -0.05, -0.004), func(v: float) -> Array: return [0.009, 0.0075, 0.0, 0.0], 6, 4, true, true)


func _legs(su: Callable, lod: int) -> void:
	for side in [-1.0, 1.0]:
		var hp := Vector3(side * HIP.x, HIP.y, HIP.z)
		var kn := Vector3(side * KNEE.x, KNEE.y, KNEE.z)
		var an := Vector3(side * ANKLE.x, ANKLE.y, ANKLE.z)
		var th := Part.THIGH_L if side < 0.0 else Part.THIGH_R
		var sh := Part.SHIN_L if side < 0.0 else Part.SHIN_R
		_tag(th, Slot.BOTTOM)
		_limb(hp + Vector3(side * 0.006, 0.05, 0.004), kn + Vector3(0, -0.01, 0), func(v: float) -> Array:
			var quad := exp(-pow((v - 0.35) / 0.35, 2.0))
			return [0.088 - 0.032 * v, 0.084 - 0.028 * v, 0.008 * quad, 0.004], su.call(16), su.call(9), false, false)
		_tag(sh, Slot.LEG)
		_limb(kn + Vector3(0, 0.02, 0), an + Vector3(0, 0.02, 0), func(v: float) -> Array:
			var calf := exp(-pow((v - 0.28) / 0.22, 2.0))
			var knee := exp(-pow(v / 0.08, 2.0))
			return [0.054 - 0.022 * v + 0.004 * calf, 0.05 - 0.022 * v, 0.006 * knee, 0.016 * calf], su.call(16), su.call(10), false, false)
		# shoe upper and sole
		_tag(sh, Slot.SHOES)
		var heel := Vector3(side * 0.095, 0.0, 0.055)
		var toe := Vector3(side * 0.1, 0.0, -0.2)
		var shoe_rows := [
			[0.0, 0.032, 0.085, 0.0],
			[0.2, 0.040, 0.10, 0.0],
			[0.45, 0.046, 0.085, 0.0],
			[0.75, 0.048, 0.06, 0.0],
			[0.92, 0.044, 0.046, 0.0],
			[1.0, 0.02, 0.03, 0.0],
		]
		var Ps := func(u: float, v: float) -> Vector3:
			var r := _lerp_rows(shoe_rows, v)
			var a := u * TAU
			var p := heel.lerp(toe, v)
			var hgt: float = r[2]
			var y := 0.015 + (sin(a) * 0.5 + 0.5) * hgt
			if sin(a) < 0.0:
				y = 0.015 + (sin(a) * 0.15 + 0.15) * hgt * 0.2
			return Vector3(p.x + cos(a) * float(r[1]), y, p.z)
		var shoe_ref := func(p: Vector3) -> Vector3:
			var t := clampf((p.z - heel.z) / (toe.z - heel.z), 0.0, 1.0)
			return Vector3(heel.lerp(toe, t).x, 0.04, p.z)
		_surface(Ps, su.call(14), su.call(9), true, shoe_ref)
		_tag(sh, Slot.SOLE)
		var Pso := func(u: float, v: float) -> Vector3:
			var r := _lerp_rows(shoe_rows, v)
			var a := u * TAU
			var p := heel.lerp(toe, v) + Vector3(0, 0, -0.006 if v > 0.5 else 0.006)
			return Vector3(p.x + cos(a) * (float(r[1]) + 0.004), 0.008 + sin(a) * 0.008, p.z)
		_surface(Pso, su.call(12), su.call(7), true, func(p: Vector3) -> Vector3: return Vector3(p.x - (cos(0.0) * 0.0), 0.008, p.z))


func _hair(su: Callable, lod: int) -> void:
	var styles := [0, 1, 2, 3, 4, 5, 6, 7] if lod < 2 else [0, 2, 5]
	for style in styles:
		_tag(Part.HAIR, Slot.HAIR, float(style))
		var thick = [0.006, 0.016, 0.014, 0.008, 0.008, 0.032, 0.02, 0.006][style]
		var line_front = [0.30, 0.34, 0.30, 0.26, 0.26, 0.32, 0.36, 0.28][style]
		var line_back = [0.6, 0.62, 0.66, 0.62, 0.62, 0.66, 0.7, 0.62][style]
		var top_scale = [1.0, 1.25, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][style]
		var Ph := func(u: float, v: float) -> Vector3:
			var a := u * TAU
			# azimuth: sin(a) > 0 at the back
			var back := (sin(a) + 1.0) * 0.5
			var side := absf(cos(a))
			var limit: float = lerpf(line_front, line_back, smoothstep(0.15, 0.85, back)) + 0.03 * side * (1.0 - back)
			if style == 6:
				limit = lerpf(0.5, 0.64, back) + 0.08 * side
			if style == 7:
				limit = lerpf(0.4, line_back, back)
			var pol := v * limit
			var edge := smoothstep(1.0, 0.75, v)
			var t: float = thick * edge
			if style == 1:
				t *= 1.0 + (top_scale - 1.0) * smoothstep(0.5, 0.0, v)
			if style == 5:
				t += 0.006 * sin(a * 9.0) * sin(pol * 14.0) * edge
			var p := _head_point(u, pol, t + 0.0025)
			if style == 7:
				# receding: no hair on the crown front
				var front := (1.0 - back)
				if v < 0.55 and front > 0.4:
					p = _head_point(u, pol, -0.004)
			return p
		_surface(Ph, su.call(26), su.call(10), true, func(p: Vector3) -> Vector3: return HEAD_C)
		match style:
			2:
				# long hair falling down the back and framing the face
				var Pl := func(u: float, v: float) -> Vector3:
					var a := lerpf(0.05, 0.95, u) * PI
					var y := lerpf(1.63, 1.36, v)
					var rr := lerpf(0.095, 0.115, v)
					var p := Vector3(-cos(a) * rr * lerpf(1.0, 1.25, v), y, sin(a) * rr * 0.85 + 0.02 + 0.03 * v)
					return p
				_surface(Pl, su.call(16), su.call(8), false, func(p: Vector3) -> Vector3: return Vector3(0, p.y, 0.0))
			3:
				var bc := Vector3(0, 1.735, 0.085)
				_surface(func(u: float, v: float) -> Vector3:
					var a := u * TAU
					var pol := v * PI
					return bc + Vector3(sin(pol) * cos(a) * 0.042, cos(pol) * 0.036, sin(pol) * sin(a) * 0.04), su.call(12), su.call(8), true, func(p: Vector3) -> Vector3: return bc)
			4:
				_limb(Vector3(0, 1.71, 0.1), Vector3(0, 1.5, 0.125), func(v: float) -> Array:
					var r := 0.024 * (1.0 - v * 0.6) + 0.006 * sin(v * PI)
					return [r, r, 0.0, 0.0], su.call(10), su.call(8), true, true)
			6:
				# bob: rounded volume ending at the jaw
				var Pb := func(u: float, v: float) -> Vector3:
					var a := lerpf(-0.1, 1.1, u) * PI
					var y := lerpf(1.66, 1.585, v)
					var rr := 0.099 + 0.008 * sin(v * PI)
					return Vector3(-cos(a) * rr, y, sin(a) * rr * 0.95 + 0.012)
				_surface(Pb, su.call(16), su.call(5), false, func(p: Vector3) -> Vector3: return Vector3(0, p.y, 0.005))


func _clothing_extras(su: Callable, lod: int) -> void:
	# shirt collar
	_tag(Part.TORSO, Slot.COLLAR)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var open := smoothstep(0.55, 0.0, absf(fmod(u - 0.75 + 1.5, 1.0) - 0.5))
		var y := lerpf(1.448, 1.488, v) - open * 0.012 * v
		var r := lerpf(0.062, 0.054, v) + 0.004
		return Vector3(cos(a) * r, y, sin(a) * r + 0.004), su.call(18), 2, true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, 0.004))
	# necktie (shown for suits and flight crew)
	_tag(Part.TIE, Slot.TIE)
	var tie_rows := [[1.44, 0.012], [1.42, 0.016], [1.30, 0.022], [1.17, 0.03], [1.135, 0.0]]
	var Pt := func(u: float, v: float) -> Vector3:
		var r := _lerp_rows(tie_rows, v)
		var y: float = r[0]
		var zf := -0.116
		if y > 1.38:
			zf = lerpf(-0.105, -0.07, (y - 1.38) / 0.06)
		elif y < 1.2:
			zf = lerpf(-0.112, -0.104, (1.2 - y) / 0.07)
		var a := u * TAU
		return Vector3(cos(a) * float(r[1]), y, zf + sin(a) * 0.004)
	_surface(Pt, 6, 6, true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, -0.1))
	# skirt (flagged), knee length
	_tag(Part.SKIRT, Slot.BOTTOM)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var y := lerpf(1.02, 0.56, v)
		var rx := lerpf(0.158, 0.205, v)
		var rz := lerpf(0.1, 0.13, v)
		var z := sin(a) * rz + (0.012 if sin(a) > 0.0 else 0.0)
		return Vector3(cos(a) * rx, y, z), su.call(24), su.call(6), true, func(p: Vector3) -> Vector3: return Vector3(0, p.y, 0.0))
	# glasses (seed dependent)
	if lod < 2:
		_tag(Part.GLASSES, Slot.FRAME)
		for sx in [-1.0, 1.0]:
			var gc := Vector3(sx * 0.031, 1.676, -0.1)
			for k in 8:
				var a0 := TAU * float(k) / 8.0
				var a1 := TAU * float(k + 1) / 8.0
				var p0 := gc + Vector3(cos(a0) * 0.019, sin(a0) * 0.014, 0)
				var p1 := gc + Vector3(cos(a1) * 0.019, sin(a1) * 0.014, 0)
				_limb(p0, p1, func(v: float) -> Array: return [0.0016, 0.0016, 0.0, 0.0], 4, 1, false, false)
			_limb(gc + Vector3(sx * 0.019, 0.002, 0), Vector3(sx * 0.079, 1.68, -0.01), func(v: float) -> Array: return [0.0015, 0.0015, 0.0, 0.0], 4, 2, false, false)
		_limb(Vector3(-0.012, 1.68, -0.101), Vector3(0.012, 1.68, -0.101), func(v: float) -> Array: return [0.0016, 0.0016, 0.0, 0.0], 4, 2, false, false)
	# backpack (flagged)
	_tag(Part.BACKPACK, Slot.BAG)
	var bp := Vector3(0, 1.2, 0.165)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI
		var x := _sgnpow(sin(pol) * cos(a), 0.6) * 0.14
		var y := _sgnpow(cos(pol), 0.6) * 0.2
		var z := _sgnpow(sin(pol) * sin(a), 0.7) * 0.075
		return bp + Vector3(x, y, z), su.call(14), su.call(10), true, func(p: Vector3) -> Vector3: return bp)
	for sx2 in [-1.0, 1.0]:
		_limb(Vector3(sx2 * 0.08, 1.42, 0.09), Vector3(sx2 * 0.1, 1.24, -0.11), func(v: float) -> Array: return [0.012, 0.004, 0.0, 0.0], 5, 4, false, false)


func _props(su: Callable, lod: int) -> void:
	# rolling suitcase beside the right hand
	_tag(Part.BAG, Slot.BAG)
	var bc := Vector3(0.34, 0.33, 0.26)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI
		var x := _sgnpow(sin(pol) * cos(a), 0.25) * 0.11
		var y := _sgnpow(cos(pol), 0.25) * 0.26
		var z := _sgnpow(sin(pol) * sin(a), 0.25) * 0.17
		return bc + Vector3(x, y, z), su.call(16), su.call(10), true, func(p: Vector3) -> Vector3: return bc)
	_tag(Part.BAG, Slot.DARK)
	_limb(Vector3(0.34, 0.58, 0.16), Vector3(0.3, 0.87, 0.06), func(v: float) -> Array: return [0.01, 0.01, 0.0, 0.0], 6, 2, false, true)
	for wz in [0.13, 0.39]:
		_limb(Vector3(0.24, 0.035, wz), Vector3(0.44, 0.035, wz), func(v: float) -> Array: return [0.033, 0.033, 0.0, 0.0], 8, 2, true, true)
	# phone in the right hand
	_tag(Part.PHONE, Slot.PHONE)
	var pc := Vector3(0.205, 0.79, -0.035)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI
		return pc + Vector3(_sgnpow(sin(pol) * cos(a), 0.3) * 0.0055, _sgnpow(cos(pol), 0.3) * 0.075, _sgnpow(sin(pol) * sin(a), 0.3) * 0.036), 8, 6, true, func(p: Vector3) -> Vector3: return pc)
	# cap with visor (flight crew, police)
	_tag(Part.HAT, Slot.HAT)
	var hc := Vector3(0, 1.735, 0.008)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var y := lerpf(1.72, 1.81, v)
		var r := lerpf(0.098, 0.104 + 0.01 * (1.0 - absf(sin(a))), v)
		var top := smoothstep(0.85, 1.0, v)
		return Vector3(cos(a) * r * (1.0 - top * 0.6), y - top * 0.01 + (0.012 * maxf(-sin(a), 0.0) * v), sin(a) * r * 1.08 * (1.0 - top * 0.6) + 0.004), su.call(20), 5, true, func(p: Vector3) -> Vector3: return Vector3(0, 1.74, 0.008))
	_tag(Part.HAT, Slot.DARK)
	_surface(func(u: float, v: float) -> Vector3:
		var a := lerpf(0.15, 0.85, u) * PI
		var r := lerpf(0.098, 0.16, v)
		return Vector3(-cos(a) * r * 0.92, 1.722 - v * 0.012, -sin(a) * r), su.call(12), 2, false, func(p: Vector3) -> Vector3: return Vector3(0, 1.75, 0.0))
	# firefighter helmet
	_tag(Part.HELMET, Slot.HAT)
	var he := Vector3(0, 1.69, 0.01)
	_surface(func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var pol := v * PI * 0.56
		var brim := smoothstep(0.85, 1.0, v)
		var r := 1.0 + brim * (0.35 + 0.25 * maxf(sin(a), 0.0))
		return he + Vector3(sin(pol) * cos(a) * 0.112 * r, cos(pol) * 0.13 - brim * 0.01, sin(pol) * sin(a) * 0.125 * r), su.call(20), su.call(8), true, func(p: Vector3) -> Vector3: return he)


# ---------------------------------------------------------------------------- appearance
static func hair_style_for(gender: String, age: int, seed_v: float) -> int:
	var r := fposmod(seed_v * 7.31, 1.0)
	if gender == "f":
		if r < 0.28: return 2
		if r < 0.45: return 4
		if r < 0.6: return 6
		if r < 0.72: return 3
		if r < 0.85: return 1
		return 5
	if age > 55 and r < 0.45:
		return 7
	if r < 0.45: return 0
	if r < 0.75: return 1
	if r < 0.88: return 5
	return 4 if r < 0.92 else 0
