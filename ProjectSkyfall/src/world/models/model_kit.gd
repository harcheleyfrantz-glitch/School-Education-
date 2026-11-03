class_name ModelKit
extends RefCounted
## Shared helpers for the procedural world models (landmarks, skylines, airport buildings):
## extruded and tapered footprints, lattice trusses, and the landmark material. The landmark
## material reads a surface class from the vertex alpha (stone, metal, ribbon windows, curtain
## wall, punched windows, lamps, dark glass), so one merged mesh per landmark carries window
## patterns by day, lit windows after dark and warm floodlighting on the stonework.
## Skyline towers come from a small library of unit "archetype" meshes (setbacks, crowns,
## spires, slanted and round tops) instanced with the city building shader.

# surface classes (vertex alpha) for landmark_material()
const STONE := 1.0        # stone, concrete, paint: floodlit after dark
const METAL := 0.85       # steel, copper, lead, gilding
const RIBBON := 0.7       # horizontal ribbon windows between spandrels (lit at night)
const CURTAIN := 0.55     # glass curtain wall with a mullion grid (lit at night)
const PUNCHED := 0.4      # masonry with punched windows (lit at night)
const LAMP := 0.22        # self-lit: clock faces, crowns, aviation lights
const DARK_GLASS := 0.05  # unlit dark glazing and openings

const _LM_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform float night = 0.0;

varying vec3 lpos;
varying vec3 onrm;
varying vec4 vcol;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lpos = VERTEX;
	onrm = NORMAL;
	vcol = COLOR;
}

void fragment() {
	vec3 base = pow(clamp(vcol.rgb, 0.0, 1.0), vec3(2.2));
	float cls = vcol.a;
	vec3 col = base;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float wall = 1.0 - step(0.6, abs(onrm.y));
	float u = abs(onrm.x) > abs(onrm.z) ? lpos.z : lpos.x;
	float v = lpos.y;
	vec3 warm = vec3(1.0, 0.78, 0.5);
	// floodlights wash the facades from below after dark
	float flood = night * (0.45 + 0.55 * exp(-max(v, 0.0) / 140.0));
	if (cls > 0.93) {
		col *= 0.94 + 0.06 * hash12(floor(lpos.xz * 0.25 + lpos.y * 0.5));
		emit = base * warm * flood * 0.75;
	} else if (cls > 0.78) {
		rough = 0.36;
		metal = 0.65;
		emit = base * warm * flood * 0.55;
	} else if (cls > 0.62) {
		// ribbon windows: glazed band and spandrel every 4 m storey
		float f = fract(v / 4.0);
		float g = step(0.34, f) * step(f, 0.94) * wall;
		vec2 cell = floor(vec2(u / 7.5, v / 4.0));
		float lit = step(0.55, hash12(cell + 17.0));
		col = mix(base, vec3(0.04, 0.06, 0.08) + base * 0.12, g);
		rough = mix(0.4, 0.06, g);
		metal = mix(0.6, 0.4, g);
		emit = g * lit * night * vec3(1.0, 0.86, 0.62) * 0.85 + (1.0 - g) * base * warm * flood * 0.35;
	} else if (cls > 0.48) {
		// curtain wall: 1.6 x 3.8 m mullion grid, pane tint and lit offices after dark
		float mx = abs(fract(u / 1.6) - 0.5);
		float my = fract(v / 3.8);
		float mull = clamp(step(0.45, mx) + step(my, 0.09), 0.0, 1.0) * wall;
		vec2 cell = floor(vec2(u / 1.6, v / 3.8));
		vec3 glass = base * vec3(0.42, 0.52, 0.62) + vec3(0.025) * hash12(cell);
		col = mix(glass, base * 0.85 + 0.08, mull);
		rough = mix(0.05, 0.45, mull);
		metal = mix(0.75, 0.35, mull);
		float lit = step(0.58, hash12(floor(vec2(u / 6.4, v / 3.8)) + 5.0));
		emit = (1.0 - mull) * wall * lit * night * vec3(1.0, 0.9, 0.74) * 0.7;
	} else if (cls > 0.3) {
		// masonry with punched windows in 3 x 3.6 m bays
		float wx = fract(u / 3.0);
		float wy = fract(v / 3.6);
		float win = step(0.22, wx) * step(wx, 0.78) * step(0.24, wy) * step(wy, 0.86) * wall;
		vec2 cell = floor(vec2(u / 3.0, v / 3.6));
		float lit = step(0.56, hash12(cell + 3.0));
		col = mix(base, vec3(0.05, 0.06, 0.08), win);
		rough = mix(0.85, 0.12, win);
		emit = win * lit * night * vec3(1.0, 0.76, 0.48) * 1.0 + (1.0 - win) * base * warm * flood * 0.6;
	} else if (cls > 0.12) {
		rough = 0.3;
		emit = base * (0.12 + night * 2.6);
	} else {
		col = vec3(0.02, 0.03, 0.04) + base * 0.15;
		rough = 0.08;
		metal = 0.4;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
"""

static var _lm_shader: Shader
static var _arch_cache := {}


static func landmark_material() -> ShaderMaterial:
	if _lm_shader == null:
		_lm_shader = Shader.new()
		_lm_shader.code = _LM_SHADER
	var m := ShaderMaterial.new()
	m.shader = _lm_shader
	return m


static func cls(c: Color, surface: float) -> Color:
	return Color(c.r, c.g, c.b, surface)


# ------------------------------------------------------------------ primitives
static func tri(mb: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, outward: Vector3, c: Color) -> void:
	## One flat triangle facing along outward (front faces are clockwise in Godot).
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	var flip := n.dot(outward) < 0.0
	if flip:
		n = -n
	var i0 := mb.add_vertex(p0, n, c)
	var i1 := mb.add_vertex(p1, n, c)
	var i2 := mb.add_vertex(p2, n, c)
	if flip:
		mb.add_tri_idx(i0, i1, i2)
	else:
		mb.add_tri_idx(i0, i2, i1)


static func quad(mb: MeshBuilder, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, outward: Vector3, c: Color) -> void:
	## Flat quad (p0..p3 around the edge in either order) facing along outward.
	var n := (p1 - p0).cross(p3 - p0)
	if n.length_squared() < 1e-10:
		n = (p2 - p1).cross(p0 - p1)
	n = n.normalized()
	var flip := n.dot(outward) < 0.0
	if flip:
		n = -n
	var i0 := mb.add_vertex(p0, n, c, Vector2(0, 0))
	var i1 := mb.add_vertex(p1, n, c, Vector2(1, 0))
	var i2 := mb.add_vertex(p2, n, c, Vector2(1, 1))
	var i3 := mb.add_vertex(p3, n, c, Vector2(0, 1))
	if flip:
		mb.add_tri_idx(i0, i1, i2)
		mb.add_tri_idx(i0, i2, i3)
	else:
		mb.add_tri_idx(i0, i2, i1)
		mb.add_tri_idx(i0, i3, i2)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


static func loft2(mb: MeshBuilder, poly0: PackedVector2Array, y0: float, poly1: PackedVector2Array, y1: float, c: Color,
		cap_top: bool = true, cap_bottom: bool = false, top_c: Color = Color(-1, 0, 0)) -> void:
	## Flat-shaded walls between two footprints with matching point counts (x, z), plus caps.
	var n := poly0.size()
	if n < 3 or poly1.size() != n:
		return
	var c0 := _centroid(poly0)
	var c1 := _centroid(poly1)
	var mid := Vector3((c0.x + c1.x) * 0.5, (y0 + y1) * 0.5, (c0.y + c1.y) * 0.5)
	for i in n:
		var j := (i + 1) % n
		var a0 := Vector3(poly0[i].x, y0, poly0[i].y)
		var b0 := Vector3(poly0[j].x, y0, poly0[j].y)
		var a1 := Vector3(poly1[i].x, y1, poly1[i].y)
		var b1 := Vector3(poly1[j].x, y1, poly1[j].y)
		var face_mid := (a0 + b0 + a1 + b1) * 0.25
		var outward := face_mid - mid
		outward.y = 0.0
		if (a1 - b1).length_squared() < 1e-8:
			tri(mb, a0, b0, a1, outward, c)
		elif (a0 - b0).length_squared() < 1e-8:
			tri(mb, a0, b1, a1, outward, c)
		else:
			quad(mb, a0, b0, b1, a1, outward, c)
	if cap_top:
		_cap(mb, poly1, y1, Vector3.UP, c if top_c.r < 0.0 else top_c)
	if cap_bottom:
		_cap(mb, poly0, y0, Vector3.DOWN, c)


static func _cap(mb: MeshBuilder, poly: PackedVector2Array, y: float, nrm: Vector3, c: Color) -> void:
	var ce := _centroid(poly)
	var cv := Vector3(ce.x, y, ce.y)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		tri(mb, cv, Vector3(poly[i].x, y, poly[i].y), Vector3(poly[j].x, y, poly[j].y), nrm, c)


static func prism(mb: MeshBuilder, poly: PackedVector2Array, y0: float, y1: float, c: Color, top_scale: float = 1.0,
		cap_top: bool = true, top_c: Color = Color(-1, 0, 0)) -> void:
	## Extrudes a footprint from y0 to y1; top_scale shrinks the top about the centroid.
	var top := poly
	if absf(top_scale - 1.0) > 0.0001:
		top = scale_poly(poly, top_scale)
	loft2(mb, poly, y0, top, y1, c, cap_top, false, top_c)


static func scale_poly(poly: PackedVector2Array, s: float, about: Vector2 = Vector2(INF, 0)) -> PackedVector2Array:
	var ce := _centroid(poly) if about.x == INF else about
	var out := PackedVector2Array()
	for p in poly:
		out.append(ce + (p - ce) * s)
	return out


static func xform_poly(poly: PackedVector2Array, rot: float, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p.rotated(rot) + offset)
	return out


# ------------------------------------------------------------------ footprints
static func rect(hx: float, hz: float, cx: float = 0.0, cz: float = 0.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz), Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz)])


static func chamfer_rect(hx: float, hz: float, ch: float) -> PackedVector2Array:
	## Rectangle with its four corners cut at 45 degrees (an octagon when ch is large).
	return PackedVector2Array([Vector2(-hx + ch, -hz), Vector2(hx - ch, -hz), Vector2(hx, -hz + ch), Vector2(hx, hz - ch),
		Vector2(hx - ch, hz), Vector2(-hx + ch, hz), Vector2(-hx, hz - ch), Vector2(-hx, -hz + ch)])


static func notch_rect(h: float, notch: float) -> PackedVector2Array:
	## Square with stepped (re-entrant) corners, like Taipei 101's sawtooth corners.
	var a := h - notch
	return PackedVector2Array([Vector2(-a, -h), Vector2(a, -h), Vector2(a, -a), Vector2(h, -a), Vector2(h, a), Vector2(a, a),
		Vector2(a, h), Vector2(-a, h), Vector2(-a, a), Vector2(-h, a), Vector2(-h, -a), Vector2(-a, -a)])


static func ngon(n: int, r: float, rot: float = 0.0, cx: float = 0.0, cz: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := rot + TAU * float(i) / n
		out.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	return out


static func star(points: int, r_out: float, r_in: float, rot: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * float(i) / points
		var rr := r_out if i % 2 == 0 else r_in
		out.append(Vector2(cos(a), sin(a)) * rr)
	return out


static func stadium(hx: float, hz: float, segs: int = 6) -> PackedVector2Array:
	## Slab with semicircular ends along x (hz is the half depth and end radius).
	var out := PackedVector2Array()
	var cx := maxf(hx - hz, 0.0)
	for i in segs + 1:
		var a := -PI * 0.5 + PI * float(i) / segs
		out.append(Vector2(cx + cos(a) * hz, sin(a) * hz))
	for i in segs + 1:
		var a2 := PI * 0.5 + PI * float(i) / segs
		out.append(Vector2(-cx + cos(a2) * hz, sin(a2) * hz))
	return out


static func petronas_plan(r: float, n: int = 64) -> PackedVector2Array:
	## Rub el Hizb: two overlapping squares (an 8-pointed star) with the inner corners filled
	## by circular lobes.
	var out := PackedVector2Array()
	var k := cos(PI * 0.25)
	for i in n:
		var a := TAU * float(i) / n
		var s1 := r * k / cos(fposmod(a, PI * 0.5) - PI * 0.25)
		var s2 := r * k / cos(fposmod(a + PI * 0.25, PI * 0.5) - PI * 0.25)
		var rr := maxf(maxf(s1, s2), r * 0.82)
		out.append(Vector2(cos(a), sin(a)) * rr)
	return out


static func wing_plan(angle: float, length: float, width: float, segs: int = 6) -> PackedVector2Array:
	## A wing from the origin out to a rounded tip at distance length (Burj Khalifa's Y plan).
	var out := PackedVector2Array()
	var hw := width * 0.5
	var tip := maxf(length - hw, 0.0)
	out.append(Vector2(0, -hw))
	for i in segs + 1:
		var a := -PI * 0.5 + PI * float(i) / segs
		out.append(Vector2(tip + cos(a) * hw, sin(a) * hw))
	out.append(Vector2(0, hw))
	return xform_poly(out, angle, Vector2.ZERO)


# ------------------------------------------------------------------ structures
static func bar(mb: MeshBuilder, a: Vector3, b: Vector3, r: float, c: Color, segs: int = 4) -> void:
	mb.add_cylinder(a, b, r, r, segs, c, false)


static func lattice(mb: MeshBuilder, rings: Array, chord_r: float, brace_r: float, c: Color, faces: Array = [0, 1, 2, 3]) -> void:
	## Square lattice truss: rings are [Vector3 x4] corner sets from bottom to top; chords run up
	## the corners and X braces cross the chosen faces.
	for i in rings.size() - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for k in 4:
			bar(mb, r0[k], r1[k], chord_r, c)
		for f in faces:
			var k0: int = f
			var k1: int = (f + 1) % 4
			bar(mb, r0[k0], r1[k1], brace_r, c, 3)
			bar(mb, r0[k1], r1[k0], brace_r, c, 3)


static func ring_rail(mb: MeshBuilder, y: float, r: float, posts: int, h: float, c: Color, center: Vector3 = Vector3.ZERO) -> void:
	## A round balcony railing: posts and a top rail.
	for i in posts:
		var a0 := TAU * float(i) / posts
		var a1 := TAU * float(i + 1) / posts
		var p0 := center + Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := center + Vector3(cos(a1) * r, y, sin(a1) * r)
		bar(mb, p0, p0 + Vector3(0, h, 0), 0.06, c, 3)
		bar(mb, p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), 0.05, c, 3)


# ------------------------------------------------------------------ skyline archetypes
## Unit tower meshes (footprint about 1 x 1, height 0..1, scaled per instance) for the city
## building shader: vertex colour r = facade kind (1 offices, 0.5 glass), a = surface (1 wall,
## 0.25 rooftop plant / metal crown, 0 flat roof).
const ARCHETYPES := 10


static func archetype_mesh(idx: int, glass: bool) -> ArrayMesh:
	var key := "%d|%s" % [idx, glass]
	if _arch_cache.has(key):
		return _arch_cache[key]
	var mb := MeshBuilder.new()
	var kr := 0.5 if glass else 1.0
	var w := Color(kr, 1, 1, 1.0)
	var roof := Color(kr, 1, 1, 0.0)
	var plant := Color(kr, 1, 1, 0.25)
	match idx:
		0:
			# wedding-cake setbacks with a plant room and a mast
			prism(mb, rect(0.5, 0.5), 0.0, 0.56, w, 1.0, true, roof)
			prism(mb, rect(0.41, 0.41), 0.56, 0.8, w, 1.0, true, roof)
			prism(mb, rect(0.31, 0.31), 0.8, 0.94, w, 1.0, true, roof)
			prism(mb, rect(0.18, 0.2), 0.94, 0.975, plant)
			mb.add_cylinder(Vector3(0.08, 0.975, 0.05), Vector3(0.08, 1.07, 0.05), 0.012, 0.004, 4, plant, false)
		1:
			# straight shaft under an open crown frame
			prism(mb, rect(0.5, 0.5), 0.0, 0.9, w, 1.0, true, roof)
			for s in [-1.0, 1.0]:
				prism(mb, rect(0.5, 0.025, 0.0, s * 0.475), 0.9, 1.0, plant)
				prism(mb, rect(0.025, 0.45, s * 0.475, 0.0), 0.9, 1.0, plant)
			prism(mb, rect(0.2, 0.15), 0.9, 0.95, plant)
		2:
			# pyramid cap and needle
			prism(mb, chamfer_rect(0.5, 0.5, 0.08), 0.0, 0.84, w, 1.0, false)
			loft2(mb, chamfer_rect(0.5, 0.5, 0.08), 0.84, chamfer_rect(0.06, 0.06, 0.01), 0.98, plant)
			mb.add_cylinder(Vector3(0, 0.98, 0), Vector3(0, 1.1, 0), 0.02, 0.003, 6, plant, false)
		3:
			# slanted glass top
			prism(mb, rect(0.5, 0.5), 0.0, 0.8, w, 1.0, false)
			var y_lo := 0.8
			var y_hi := 1.0
			var a := Vector3(-0.5, y_lo, -0.5)
			var b := Vector3(0.5, y_hi, -0.5)
			var cc := Vector3(0.5, y_hi, 0.5)
			var d := Vector3(-0.5, y_lo, 0.5)
			quad(mb, a, b, cc, d, Vector3(-0.2, 1, 0), plant)
			# side walls of the wedge
			tri(mb, Vector3(-0.5, y_lo, -0.5), Vector3(0.5, y_lo, -0.5), Vector3(0.5, y_hi, -0.5), Vector3(0, 0, -1), w)
			tri(mb, Vector3(-0.5, y_lo, 0.5), Vector3(0.5, y_lo, 0.5), Vector3(0.5, y_hi, 0.5), Vector3(0, 0, 1), w)
			quad(mb, Vector3(0.5, y_lo, -0.5), Vector3(0.5, y_lo, 0.5), Vector3(0.5, y_hi, 0.5), Vector3(0.5, y_hi, -0.5), Vector3(1, 0, 0), w)
		4:
			# round tower with a stepped top ring
			prism(mb, ngon(18, 0.5), 0.0, 0.9, w, 1.0, true, roof)
			prism(mb, ngon(18, 0.43), 0.9, 0.95, plant, 1.0, true, roof)
			prism(mb, ngon(10, 0.16), 0.95, 0.985, plant)
		5:
			# chamfered octagon with a lantern and a needle
			prism(mb, chamfer_rect(0.5, 0.5, 0.15), 0.0, 0.7, w, 1.0, true, roof)
			prism(mb, chamfer_rect(0.4, 0.4, 0.12), 0.7, 0.88, w, 1.0, true, roof)
			prism(mb, chamfer_rect(0.25, 0.25, 0.08), 0.88, 0.95, plant, 0.8)
			mb.add_cylinder(Vector3(0, 0.95, 0), Vector3(0, 1.06, 0), 0.015, 0.003, 6, plant, false)
		6:
			# two slabs of different heights
			prism(mb, rect(0.32, 0.5, -0.18, 0.0), 0.0, 1.0, w, 1.0, true, roof)
			prism(mb, rect(0.2, 0.42, 0.3, 0.04), 0.0, 0.7, w, 1.0, true, roof)
			prism(mb, rect(0.14, 0.2, -0.2, 0.1), 1.0, 1.03, plant)
			prism(mb, rect(0.1, 0.16, 0.3, -0.1), 0.7, 0.73, plant)
		7:
			# tapering tube with twin antennas
			prism(mb, rect(0.5, 0.5), 0.0, 0.97, w, 0.72, true, roof)
			prism(mb, rect(0.22, 0.22), 0.97, 0.99, plant)
			for s2 in [-1.0, 1.0]:
				mb.add_cylinder(Vector3(s2 * 0.12, 0.97, 0.0), Vector3(s2 * 0.12, 1.16, 0.0), 0.012, 0.004, 4, plant, false)
		8:
			# art deco spire: stepped tiers and a metal needle
			prism(mb, rect(0.5, 0.5), 0.0, 0.62, w, 1.0, true, roof)
			prism(mb, chamfer_rect(0.4, 0.4, 0.08), 0.62, 0.76, w, 1.0, true, roof)
			prism(mb, chamfer_rect(0.3, 0.3, 0.07), 0.76, 0.86, w, 1.0, true, roof)
			loft2(mb, chamfer_rect(0.22, 0.22, 0.06), 0.86, chamfer_rect(0.08, 0.08, 0.02), 0.95, plant)
			mb.add_cylinder(Vector3(0, 0.95, 0), Vector3(0, 1.12, 0), 0.025, 0.003, 6, plant, false)
		_:
			# rounded slab
			prism(mb, stadium(0.5, 0.36), 0.0, 0.95, w, 1.0, true, roof)
			prism(mb, rect(0.22, 0.16), 0.95, 0.985, plant)
	var m := mb.commit()
	_arch_cache[key] = m
	return m
