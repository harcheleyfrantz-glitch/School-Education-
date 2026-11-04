extends RefCounted
## Unit meshes for instanced city buildings (footprint -0.5..0.5 in x and z, height 0..1, scaled
## per instance in metres). Vertex colour r = facade kind, a = surface; the building shader turns
## those into windows, brick, panels, roofs and night lights. Built once on the main thread.
##
## kinds: 0.05 ground plate, 0.12 wooden house, 0.2 house, 0.28 brick, 0.42 stone (Haussmann),
##   0.5 glass curtain wall, 0.6 residential tower, 0.68 concrete panel, 0.78 shed, 0.88 stucco,
##   1.0 office. surfaces: 0 flat roof, 0.12 water, 0.25 rooftop plant, 0.37 ground plate top,
##   0.5 pitched roof, 0.62 mansard, 0.8 trim and chimneys, 1 wall.

const K := preload("res://src/world/models/model_kit.gd")

const PLATE := 0.05
const WOOD := 0.12
const HOUSE := 0.2
const BRICK := 0.28
const STONE := 0.42
const GLASS := 0.5
const RES := 0.6
const PANEL := 0.68
const SHED := 0.78
const STUCCO := 0.88
const OFFICE := 1.0

const S_FLAT := 0.0
const S_WATER := 0.12
const S_PLANT := 0.25
const S_GROUND := 0.37
const S_PITCH := 0.5
const S_MANSARD := 0.62
const S_TRIM := 0.8
const S_WALL := 1.0


static func c(kind: float, surf: float) -> Color:
	return Color(kind, 1.0, 1.0, surf)


static func build_all() -> Dictionary:
	return {
		"plate": plate(), "box_office": box(OFFICE, false), "box_stucco": box(STUCCO, true), "box_panel": box(PANEL, true),
		"hip_block": hip_block(), "court_mansard": court_mansard(), "court_pitched": court_pitched(), "court_flat": court_flat(),
		"terrace": terrace(), "canal": canal(), "house": house(HOUSE, 0.62, 0.07), "wood_house": house(WOOD, 0.5, 0.05),
		"hip_house": hip_house(), "villa": villa(), "tower_glass": tower_glass(), "tower_res": tower_res(), "shed": shed(),
		"shop_row": shop_row(),
	}


# ------------------------------------------------------------------ helpers
static func _centroid(poly: PackedVector2Array) -> Vector2:
	var ce := Vector2.ZERO
	for p in poly:
		ce += p
	return ce / maxf(poly.size(), 1)


static func walls(mb: MeshBuilder, poly: PackedVector2Array, y0: float, y1: float, col: Color, inward: bool = false) -> void:
	var ce := _centroid(poly)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var mid := (a + b) * 0.5 - ce
		var out := Vector3(mid.x, 0.0, mid.y) * (-1.0 if inward else 1.0)
		K.quad(mb, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), out, col)


static func slope(mb: MeshBuilder, pa: PackedVector2Array, ya: float, pb: PackedVector2Array, yb: float, col: Color, inward: bool = false) -> void:
	## Roof band between two matching footprints (outer eaves to ridge, or courtyard eaves inward).
	var ce := _centroid(pa)
	var n := pa.size()
	for i in n:
		var j := (i + 1) % n
		var mid := (pa[i] + pa[j]) * 0.5 - ce
		var out := Vector3(mid.x, 0.0, mid.y).normalized() * (-1.0 if inward else 1.0) + Vector3(0, 0.6, 0)
		var a0 := Vector3(pa[i].x, ya, pa[i].y)
		var b0 := Vector3(pa[j].x, ya, pa[j].y)
		var a1 := Vector3(pb[i].x, yb, pb[i].y)
		var b1 := Vector3(pb[j].x, yb, pb[j].y)
		if (a1 - b1).length_squared() < 1e-8:
			K.tri(mb, a0, b0, a1, out, col)
		else:
			K.quad(mb, a0, b0, b1, a1, out, col)


static func ring_cap(mb: MeshBuilder, outer: PackedVector2Array, inner: PackedVector2Array, y: float, col: Color) -> void:
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		K.quad(mb, Vector3(outer[i].x, y, outer[i].y), Vector3(outer[j].x, y, outer[j].y), Vector3(inner[j].x, y, inner[j].y),
			Vector3(inner[i].x, y, inner[i].y), Vector3.UP, col)


static func gable_x(mb: MeshBuilder, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, e: float, roof: Color, wall: Color) -> void:
	## Pitched roof with its ridge along x (eaves overhang e on the long sides), gable walls at both ends.
	var zm := (z0 + z1) * 0.5
	var drop := (yr - ye) * e / maxf((z1 - z0) * 0.5, 0.001)
	K.quad(mb, Vector3(x0, ye - drop, z0 - e), Vector3(x1, ye - drop, z0 - e), Vector3(x1, yr, zm), Vector3(x0, yr, zm), Vector3(0, 1, -1), roof)
	K.quad(mb, Vector3(x0, ye - drop, z1 + e), Vector3(x1, ye - drop, z1 + e), Vector3(x1, yr, zm), Vector3(x0, yr, zm), Vector3(0, 1, 1), roof)
	K.tri(mb, Vector3(x0, ye, z0), Vector3(x0, ye, z1), Vector3(x0, yr, zm), Vector3(-1, 0, 0), wall)
	K.tri(mb, Vector3(x1, ye, z0), Vector3(x1, ye, z1), Vector3(x1, yr, zm), Vector3(1, 0, 0), wall)


static func gable_z(mb: MeshBuilder, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, e: float, roof: Color, wall: Color) -> void:
	var xm := (x0 + x1) * 0.5
	var drop := (yr - ye) * e / maxf((x1 - x0) * 0.5, 0.001)
	K.quad(mb, Vector3(x0 - e, ye - drop, z0), Vector3(x0 - e, ye - drop, z1), Vector3(xm, yr, z1), Vector3(xm, yr, z0), Vector3(-1, 1, 0), roof)
	K.quad(mb, Vector3(x1 + e, ye - drop, z0), Vector3(x1 + e, ye - drop, z1), Vector3(xm, yr, z1), Vector3(xm, yr, z0), Vector3(1, 1, 0), roof)
	K.tri(mb, Vector3(x0, ye, z0), Vector3(x1, ye, z0), Vector3(xm, yr, z0), Vector3(0, 0, -1), wall)
	K.tri(mb, Vector3(x0, ye, z1), Vector3(x1, ye, z1), Vector3(xm, yr, z1), Vector3(0, 0, 1), wall)


static func hip(mb: MeshBuilder, hx: float, hz: float, cx: float, cz: float, ye: float, yr: float, e: float, roof: Color) -> void:
	var ridge := maxf(hx - hz, 0.004) if hx >= hz else 0.004
	var ridge_z := 0.004 if hx >= hz else maxf(hz - hx, 0.004)
	slope(mb, K.rect(hx + e, hz + e, cx, cz), ye - 0.02, K.rect(ridge, ridge_z, cx, cz), yr, roof)


static func block(mb: MeshBuilder, center: Vector3, size: Vector3, col: Color) -> void:
	## Box without a bottom face.
	K.prism(mb, K.rect(size.x * 0.5, size.z * 0.5, center.x, center.z), center.y - size.y * 0.5, center.y + size.y * 0.5, col)


# ------------------------------------------------------------------ meshes
static func plate() -> ArrayMesh:
	var mb := MeshBuilder.new()
	K.prism(mb, K.rect(0.5, 0.5), 0.0, 1.0, c(PLATE, S_WALL), 1.0, true, c(PLATE, S_GROUND))
	return mb.commit()


static func box(kind: float, parapet: bool) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := c(kind, S_WALL)
	var roof := c(kind, S_FLAT)
	var plant := c(kind, S_PLANT)
	var trim := c(kind, S_TRIM)
	if parapet:
		K.prism(mb, K.rect(0.5, 0.5), 0.0, 1.0, w, 1.0, true, roof)
		for s in [-1.0, 1.0]:
			block(mb, Vector3(0, 1.012, s * 0.493), Vector3(1.0, 0.024, 0.014), trim)
			block(mb, Vector3(s * 0.493, 1.012, 0), Vector3(0.014, 0.024, 0.972), trim)
	else:
		walls(mb, K.rect(0.5, 0.5), 0.0, 0.975, w)
		K.prism(mb, K.rect(0.506, 0.506), 0.975, 1.0, trim, 1.0, true, roof)
	if kind == PANEL:
		block(mb, Vector3(0.28, 1.025, 0.0), Vector3(0.08, 0.05, 0.36), w)
		block(mb, Vector3(-0.28, 1.025, 0.0), Vector3(0.08, 0.05, 0.36), w)
	else:
		block(mb, Vector3(0.18, 1.025, -0.16), Vector3(0.26, 0.05, 0.2), plant)
		block(mb, Vector3(-0.24, 1.018, 0.18), Vector3(0.12, 0.036, 0.28), plant)
		K.cyl(mb, Vector3(0.3, 1.0, 0.3), Vector3(0.3, 1.06, 0.3), 0.04, 0.04, 6, plant)
		K.cone(mb, Vector3(0.3, 1.06, 0.3), Vector3(0.3, 1.085, 0.3), 0.044, 6, plant)
	if kind == STUCCO:
		block(mb, Vector3(-0.2, 1.04, -0.2), Vector3(0.14, 0.08, 0.12), w)
		K.cyl(mb, Vector3(-0.32, 1.0, 0.0), Vector3(-0.32, 1.04, 0.0), 0.035, 0.035, 6, trim)
	return mb.commit()


static func hip_block() -> ArrayMesh:
	var mb := MeshBuilder.new()
	walls(mb, K.rect(0.5, 0.5), 0.0, 0.8, c(STUCCO, S_WALL))
	hip(mb, 0.5, 0.5, 0, 0, 0.8, 1.0, 0.04, c(STUCCO, S_PITCH))
	block(mb, Vector3(0.2, 0.95, 0.15), Vector3(0.06, 0.14, 0.06), c(STUCCO, S_TRIM))
	return mb.commit()


static func court_mansard() -> ArrayMesh:
	## Haussmann perimeter block: stone walls round a courtyard, cornice, steep zinc mansard.
	var mb := MeshBuilder.new()
	var w := c(STONE, S_WALL)
	var m := c(STONE, S_MANSARD)
	var trim := c(STONE, S_TRIM)
	walls(mb, K.rect(0.5, 0.5), 0.0, 0.76, w)
	walls(mb, K.rect(0.34, 0.34), 0.0, 0.76, w, true)
	walls(mb, K.rect(0.506, 0.506), 0.735, 0.765, trim)
	ring_cap(mb, K.rect(0.506, 0.506), K.rect(0.5, 0.5), 0.765, trim)
	slope(mb, K.rect(0.5, 0.5), 0.765, K.rect(0.475, 0.475), 0.93, m)
	slope(mb, K.rect(0.34, 0.34), 0.76, K.rect(0.365, 0.365), 0.93, m, true)
	ring_cap(mb, K.rect(0.475, 0.475), K.rect(0.365, 0.365), 0.93, m)
	for p in [Vector2(-0.42, -0.2), Vector2(0.42, 0.15), Vector2(0.1, -0.42), Vector2(-0.25, 0.42), Vector2(0.42, -0.38), Vector2(-0.42, 0.3), Vector2(0.3, 0.42), Vector2(-0.1, -0.42)]:
		block(mb, Vector3(p.x, 0.96, p.y), Vector3(0.02, 0.07, 0.05) if absf(p.x) > 0.4 else Vector3(0.05, 0.07, 0.02), trim)
	return mb.commit()


static func court_pitched() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := c(STONE, S_WALL)
	var r := c(STONE, S_PITCH)
	walls(mb, K.rect(0.5, 0.5), 0.0, 0.78, w)
	walls(mb, K.rect(0.35, 0.35), 0.0, 0.78, w, true)
	slope(mb, K.rect(0.515, 0.515), 0.77, K.rect(0.425, 0.425), 1.0, r)
	slope(mb, K.rect(0.335, 0.335), 0.77, K.rect(0.425, 0.425), 1.0, r, true)
	for p in [Vector2(-0.425, -0.1), Vector2(0.425, 0.2), Vector2(0.15, -0.425), Vector2(-0.3, 0.425)]:
		block(mb, Vector3(p.x, 1.0, p.y), Vector3(0.03, 0.08, 0.03), c(STONE, S_TRIM))
	return mb.commit()


static func court_flat() -> ArrayMesh:
	## Chamfered perimeter block with a flat roof (Eixample, Cairo, Delhi, Moscow).
	var mb := MeshBuilder.new()
	var outer := K.chamfer_rect(0.5, 0.5, 0.1)
	var inner := K.chamfer_rect(0.32, 0.32, 0.06)
	var w := c(STUCCO, S_WALL)
	walls(mb, outer, 0.0, 0.97, w)
	walls(mb, outer, 0.97, 1.0, c(STUCCO, S_TRIM))
	walls(mb, inner, 0.0, 1.0, w, true)
	ring_cap(mb, outer, inner, 1.0, c(STUCCO, S_FLAT))
	block(mb, Vector3(0.41, 1.02, 0.0), Vector3(0.06, 0.04, 0.12), c(STUCCO, S_PLANT))
	block(mb, Vector3(-0.1, 1.02, -0.41), Vector3(0.14, 0.04, 0.05), c(STUCCO, S_PLANT))
	return mb.commit()


static func terrace() -> ArrayMesh:
	## Six terraced houses: one long gabled roof, chimney stacks on the party walls, bay windows.
	var mb := MeshBuilder.new()
	var w := c(BRICK, S_WALL)
	walls(mb, K.rect(0.5, 0.5), 0.0, 0.66, w)
	gable_x(mb, -0.5, 0.5, -0.5, 0.5, 0.66, 1.0, 0.05, c(BRICK, S_PITCH), w)
	for i in 7:
		var x := -0.5 + float(i) / 6.0
		block(mb, Vector3(clampf(x, -0.49, 0.49), 0.98, 0.0), Vector3(0.025, 0.16, 0.16), c(BRICK, S_TRIM))
	for i in 6:
		var xm := -0.5 + (float(i) + 0.5) / 6.0
		block(mb, Vector3(xm - 0.02, 0.2, 0.53), Vector3(0.07, 0.4, 0.06), w)
		block(mb, Vector3(xm - 0.02, 0.41, 0.53), Vector3(0.075, 0.02, 0.065), c(BRICK, S_TRIM))
	return mb.commit()


static func canal() -> ArrayMesh:
	## Five narrow canal houses with their gables to the street: plain, neck and stepped.
	var mb := MeshBuilder.new()
	var hf := [1.0, 0.86, 0.95, 0.8, 0.9]
	var w := c(BRICK, S_WALL)
	var trim := c(BRICK, S_TRIM)
	for i in 5:
		var x0 := -0.5 + float(i) * 0.2
		var x1 := x0 + 0.2
		var xm := x0 + 0.1
		var top: float = hf[i]
		var yw := top * 0.74
		walls(mb, K.rect(0.1, 0.5, xm, 0.0), 0.0, yw, w)
		gable_z(mb, x0, x1, -0.5, 0.5, yw, top, 0.0, c(BRICK, S_PITCH), w)
		var gh := top - yw
		for zs in [-0.5, 0.5]:
			if i % 3 == 1:
				block(mb, Vector3(xm, yw + gh * 0.55, zs), Vector3(0.1, gh * 1.1, 0.012), w)
				block(mb, Vector3(xm, top + gh * 0.12, zs), Vector3(0.11, 0.015, 0.016), trim)
			elif i % 3 == 2:
				block(mb, Vector3(xm, yw + gh * 0.3, zs), Vector3(0.15, gh * 0.6, 0.012), w)
				block(mb, Vector3(xm, yw + gh * 0.75, zs), Vector3(0.09, gh * 0.5, 0.012), w)
				block(mb, Vector3(xm, top + 0.01, zs), Vector3(0.04, gh * 0.3, 0.012), w)
		block(mb, Vector3(xm, yw * 0.04, 0.505), Vector3(0.2, yw * 0.08, 0.01), trim)
	return mb.commit()


static func house(kind: float, yw: float, e: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := c(kind, S_WALL)
	walls(mb, K.rect(0.5, 0.5), 0.0, yw, w)
	gable_z(mb, -0.5, 0.5, -0.5, 0.5, yw, 1.0, e, c(kind, S_PITCH), w)
	block(mb, Vector3(0.22, 0.92, 0.25), Vector3(0.08, 0.22, 0.08), c(kind, S_TRIM))
	if kind == WOOD:
		# porch roof over the front door
		block(mb, Vector3(0.0, yw * 0.62, 0.56), Vector3(0.4, 0.03, 0.12), c(kind, S_TRIM))
	return mb.commit()


static func hip_house() -> ArrayMesh:
	## Bungalow or Mediterranean house: hipped main roof and a hipped side wing.
	var mb := MeshBuilder.new()
	var w := c(HOUSE, S_WALL)
	var r := c(HOUSE, S_PITCH)
	walls(mb, K.rect(0.5, 0.32, 0.0, -0.18), 0.0, 0.58, w)
	hip(mb, 0.5, 0.32, 0.0, -0.18, 0.58, 0.95, 0.05, r)
	walls(mb, K.rect(0.2, 0.2, 0.28, 0.3), 0.0, 0.52, w)
	hip(mb, 0.2, 0.2, 0.28, 0.3, 0.52, 0.8, 0.04, r)
	return mb.commit()


static func villa() -> ArrayMesh:
	## Walled villa plot: two flat-roofed storeys with parapets, a roof terrace and a pool.
	var mb := MeshBuilder.new()
	var w := c(STUCCO, S_WALL)
	var roof := c(STUCCO, S_FLAT)
	var trim := c(STUCCO, S_TRIM)
	K.prism(mb, K.rect(0.3, 0.24, 0.04, -0.06), 0.0, 0.5, w, 1.0, true, roof)
	K.prism(mb, K.rect(0.17, 0.15, -0.04, -0.1), 0.5, 0.92, w, 1.0, true, roof)
	walls(mb, K.rect(0.3, 0.24, 0.04, -0.06), 0.5, 0.56, trim)
	block(mb, Vector3(0.12, 0.96, -0.12), Vector3(0.06, 0.08, 0.06), c(STUCCO, S_PLANT))
	for s in [-1.0, 1.0]:
		block(mb, Vector3(0, 0.1, s * 0.49), Vector3(1.0, 0.2, 0.02), trim)
		block(mb, Vector3(s * 0.49, 0.1, 0), Vector3(0.02, 0.2, 0.96), trim)
	block(mb, Vector3(0.05, 0.015, 0.34), Vector3(0.34, 0.03, 0.14), c(STUCCO, S_WATER))
	return mb.commit()


static func tower_glass() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var g := c(GLASS, S_WALL)
	var roof := c(OFFICE, S_FLAT)
	K.prism(mb, K.rect(0.5, 0.5), 0.0, 0.1, c(OFFICE, S_WALL), 1.0, true, roof)
	K.prism(mb, K.chamfer_rect(0.37, 0.37, 0.07), 0.1, 0.68, g, 1.0, true, roof)
	K.prism(mb, K.chamfer_rect(0.3, 0.3, 0.06), 0.68, 0.95, g, 1.0, true, roof)
	K.prism(mb, K.chamfer_rect(0.31, 0.31, 0.06), 0.95, 0.975, c(OFFICE, S_TRIM), 1.0, true, roof)
	block(mb, Vector3(0, 0.99, 0), Vector3(0.24, 0.03, 0.2), c(OFFICE, S_PLANT))
	K.cyl(mb, Vector3(0.08, 1.0, 0.06), Vector3(0.08, 1.1, 0.06), 0.01, 0.004, 4, c(OFFICE, S_PLANT))
	return mb.commit()


static func tower_res() -> ArrayMesh:
	## Cruciform residential tower on a podium (Hong Kong, Singapore, Shanghai).
	var mb := MeshBuilder.new()
	var a := 0.36
	var b := 0.13
	var cross := PackedVector2Array([Vector2(b, -a), Vector2(b, -b), Vector2(a, -b), Vector2(a, b), Vector2(b, b), Vector2(b, a),
		Vector2(-b, a), Vector2(-b, b), Vector2(-a, b), Vector2(-a, -b), Vector2(-b, -b), Vector2(-b, -a)])
	K.prism(mb, K.rect(0.5, 0.5), 0.0, 0.12, c(STUCCO, S_WALL), 1.0, true, c(STUCCO, S_FLAT))
	K.prism(mb, cross, 0.12, 0.97, c(RES, S_WALL), 1.0, true, c(RES, S_FLAT))
	block(mb, Vector3(0, 0.985, 0), Vector3(0.16, 0.03, 0.16), c(RES, S_PLANT))
	return mb.commit()


static func shed() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := c(SHED, S_WALL)
	walls(mb, K.rect(0.5, 0.5), 0.0, 0.72, w)
	gable_x(mb, -0.5, 0.5, -0.5, 0.5, 0.72, 1.0, 0.02, c(SHED, S_PITCH), w)
	K.prism(mb, K.rect(0.06, 0.25, 0.56, 0.15), 0.0, 0.48, c(OFFICE, S_WALL), 1.0, true, c(OFFICE, S_FLAT))
	return mb.commit()


static func shop_row() -> ArrayMesh:
	## Six narrow shophouses of different heights with flat roofs and water tanks.
	var mb := MeshBuilder.new()
	var hf := [1.0, 0.8, 0.92, 0.7, 0.95, 0.84]
	for i in 6:
		var xm := -0.5 + (float(i) + 0.5) / 6.0
		var top: float = hf[i]
		K.prism(mb, K.rect(1.0 / 12.0, 0.5, xm, 0.0), 0.0, top, c(STUCCO, S_WALL), 1.0, true, c(STUCCO, S_FLAT))
		if i % 2 == 0:
			K.cyl(mb, Vector3(xm, top, -0.25), Vector3(xm, top + 0.08, -0.25), 0.035, 0.035, 6, c(STUCCO, S_PLANT))
		block(mb, Vector3(xm, 0.2, 0.53), Vector3(1.0 / 6.0 - 0.01, 0.015, 0.06), c(STUCCO, S_TRIM))
	return mb.commit()
