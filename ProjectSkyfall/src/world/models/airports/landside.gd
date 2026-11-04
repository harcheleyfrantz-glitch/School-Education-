class_name AirportLandside
extends RefCounted
## The kerbside in front of a passenger terminal (0-80 m from its landside face): pavements and
## kerbs, the departures / arrivals roads with lane markings and zebra crossings, a raised
## median with a covered walkway, bollards, rows of national flags at international airports,
## palms in warm places (trees and planters elsewhere), lamp posts, road signs and taxis, buses
## and cars at the kerb. Hubs get an elevated departures roadway on piers with ramps at both
## ends and a canopy over the drop-off kerb.
##
## Built in a kerb frame per terminal: x = out from the facade, z = along it, y up.

const WARM := ["KMIA", "KLAX", "KLAS", "KMCO", "KMSY", "OMDB", "OTHH", "WSSS", "VTBS", "RPLL", "WIII", "WMKK", "VHHH",
	"VABB", "VIDP", "HECA", "LGAV", "LPPT", "LPMA", "LPPD", "TXKF", "LEBL", "LEMD", "LIRF", "RCTP", "SKPC", "SKSB", "SKIM", "SKNG"]
const DESERT := ["OMDB", "OTHH", "HECA", "KLAS", "VIDP"]
const FICTIONAL := ["Calderra", "Westmark"]

# flags: [type, colours...]; types: h / v stripes, nordic cross, disc, cross, canton (striped
# field + plain canton), hoist band, uk, canada, star, diamond
const RED := Color(0.78, 0.1, 0.14)
const WHITE := Color(0.96, 0.96, 0.95)
const BLUE := Color(0.08, 0.2, 0.52)
const NAVY := Color(0.05, 0.12, 0.33)
const GREEN := Color(0.0, 0.47, 0.25)
const YELLOW := Color(0.98, 0.8, 0.08)
const BLACK := Color(0.06, 0.06, 0.06)
const ORANGE := Color(1.0, 0.55, 0.15)
const SKY := Color(0.45, 0.68, 0.88)
const MAROON := Color(0.52, 0.08, 0.2)
const FLAGS := {
	"United States": ["canton", RED, WHITE, NAVY], "Canada": ["canada", RED, WHITE], "United Kingdom": ["uk", NAVY, WHITE, RED],
	"France": ["v", BLUE, WHITE, RED], "Netherlands": ["h", RED, WHITE, BLUE], "Ireland": ["v", GREEN, WHITE, ORANGE],
	"Spain": ["h", RED, YELLOW, YELLOW, RED], "Italy": ["v", GREEN, WHITE, RED], "Iceland": ["nordic", BLUE, WHITE, RED],
	"Bermuda": ["uk", RED, WHITE, NAVY], "Portugal": ["v", GREEN, RED, RED], "Faroe Islands": ["nordic", WHITE, BLUE, RED],
	"Greenland": ["disc", WHITE, RED], "Germany": ["h", BLACK, RED, YELLOW], "Switzerland": ["cross", RED, WHITE],
	"Austria": ["h", RED, WHITE, RED], "Denmark": ["nordic", RED, WHITE], "Norway": ["nordic", RED, WHITE, BLUE],
	"Sweden": ["nordic", BLUE, YELLOW], "Belgium": ["v", BLACK, YELLOW, RED], "Japan": ["disc", WHITE, RED],
	"South Korea": ["disc", WHITE, Color(0.8, 0.1, 0.2)], "China": ["star", RED, YELLOW], "Hong Kong": ["disc", RED, WHITE],
	"Taiwan": ["star", RED, NAVY], "Singapore": ["h", RED, WHITE], "Malaysia": ["canton", RED, WHITE, NAVY],
	"Thailand": ["h", RED, WHITE, NAVY, NAVY, WHITE, RED], "Philippines": ["hoist", WHITE, BLUE, RED], "Indonesia": ["h", RED, WHITE],
	"India": ["h", ORANGE, WHITE, GREEN], "United Arab Emirates": ["hoist", RED, GREEN, WHITE, BLACK], "Qatar": ["hoist", WHITE, MAROON],
	"Turkey": ["disc", RED, WHITE], "Egypt": ["h", RED, WHITE, BLACK], "Greece": ["canton", BLUE, WHITE, BLUE],
	"Russia": ["h", WHITE, BLUE, RED], "Mexico": ["v", GREEN, WHITE, RED], "Brazil": ["diamond", GREEN, YELLOW, BLUE],
	"Argentina": ["h", SKY, WHITE, SKY], "Colombia": ["h", YELLOW, YELLOW, BLUE, RED], "Peru": ["v", RED, WHITE, RED],
	"Chile": ["canton", WHITE, RED, BLUE], "Jamaica": ["cross", GREEN, YELLOW], "Australia": ["uk", NAVY, WHITE, RED],
	"Calderra": ["h", Color(0.0, 0.5, 0.55), WHITE, Color(0.9, 0.68, 0.15)], "Westmark": ["nordic", NAVY, Color(0.9, 0.68, 0.15)],
	"European Union": ["disc", BLUE, YELLOW],
}
const POOLS := {
	"americas": ["Mexico", "Brazil", "Argentina", "Colombia", "Peru", "Chile", "Jamaica", "Canada", "United Kingdom", "Spain", "France", "Germany"],
	"europe": ["European Union", "United Kingdom", "France", "Germany", "Italy", "Spain", "Netherlands", "Belgium", "Switzerland", "Austria",
		"Denmark", "Sweden", "Norway", "Ireland", "Portugal", "Greece", "Iceland", "United States"],
	"asia": ["Japan", "South Korea", "China", "Singapore", "Malaysia", "Thailand", "Indonesia", "India", "Philippines", "Taiwan",
		"Hong Kong", "United Arab Emirates", "Qatar", "Turkey", "Australia", "United Kingdom", "United States"],
	"global": ["United States", "United Kingdom", "France", "Germany", "Japan", "China", "Brazil", "India", "United Arab Emirates",
		"Canada", "Italy", "Spain", "Singapore", "Mexico", "Australia", "Netherlands"],
}
const ASIA := ["Japan", "South Korea", "China", "Hong Kong", "Taiwan", "Singapore", "Malaysia", "Thailand", "Philippines", "Indonesia",
	"India", "United Arab Emirates", "Qatar", "Turkey", "Egypt"]

static var _palm_mesh: ArrayMesh
static var _tree_mesh: ArrayMesh
static var _lamp_mesh: ArrayMesh
static var _bollard_mesh: ArrayMesh


static func build(view: Node3D, layout: Dictionary, icao: String, mgr: Node) -> void:
	var ap: Dictionary = Airports.get_ap(icao)
	if String(layout.get("size", "")) == "ga":
		return
	for b in layout.get("buildings", []):
		if String(b.kind) != "terminal":
			continue
		var fr := _kerb_frame(layout, b)
		_street(view, layout, icao, ap, b, fr, mgr)
		break


static func _kerb_frame(layout: Dictionary, b: Dictionary) -> Dictionary:
	## Where the kerb goes: the long face that is not an apron facade, else the -axis end (where
	## TerminalInterior puts the entrance of a midfield terminal).
	var ls: Dictionary = layout.get("landside", {})
	if ls.has("origin") and ls.has("normal"):
		# the layout names the kerbside facade (a head house for midfield complexes)
		var lo: Vector2 = ls.origin
		var ln: Vector2 = (ls.normal as Vector2).normalized()
		var lhw := minf(float(ls.get("len", 200.0)) * 0.45, 260.0)
		var head := false
		for hb in layout.get("buildings", []):
			if String(hb.kind) == "landside":
				head = true
		return {"origin": lo, "out": ln, "along": Vector2(-ln.y, ln.x), "hw": maxf(lhw, 60.0), "hw_near": maxf(lhw, 60.0), "end": head}
	var c: Vector2 = b.center
	var ax: Vector2 = (b.axis as Vector2).normalized()
	var n := Vector2(-ax.y, ax.x)
	var d: float = b.depth
	var L: float = b.len
	for sgn in [1.0, -1.0]:
		var wn: Vector2 = n * sgn
		var airside := false
		for f in layout.facades:
			var fn: Vector2 = f.normal
			if fn.dot(wn) > 0.9 and absf(((f.origin as Vector2) - c).dot(wn) - d * 0.5) < 8.0:
				airside = true
		if not airside:
			return {"origin": c + wn * d * 0.5, "out": wn, "along": Vector2(-wn.y, wn.x), "hw": minf(L * 0.36, 260.0), "hw_near": minf(L * 0.36, 260.0), "end": false}
	var out := -ax
	return {"origin": c + out * L * 0.5, "out": out, "along": Vector2(-out.y, out.x), "hw": maxf(d * 0.5 + 40.0, 100.0), "hw_near": d * 0.5 - 3.0, "end": true}


# ------------------------------------------------------------------ the street
static func _street(view: Node3D, layout: Dictionary, icao: String, ap: Dictionary, b: Dictionary, fr: Dictionary, mgr: Node) -> void:
	var hub := String(layout.get("size", "")) == "hub"
	var end_case: bool = fr.end
	var o: Vector2 = fr.origin
	var out: Vector2 = fr.out
	var yaw := atan2(out.x, out.y) - PI * 0.5
	# kerb frame: local +x = out, +z = along
	var basis := Basis(Vector3.UP, yaw)
	var bx := basis * Vector3(1, 0, 0)
	if Vector2(bx.x, bx.z).dot(out) < 0.0:
		basis = Basis(Vector3.UP, yaw + PI)
	var xf := Transform3D(basis, Vector3(o.x, 0.0, o.y))
	var hw: float = fr.hw
	var hw_near: float = fr.hw_near
	var warm := icao in WARM or String(Airports.DATA.get(icao, {}).get("terminal", {}).get("style", "")) in ["resort", "island"]
	var r := U.rng(U.hash_str(icao + "kerb"))
	# cross-section (m out from the facade)
	var walk1 := 26.0 if end_case else 15.0      # pavement / forecourt
	var r1 := walk1 + 14.0                        # kerb road: 2 drop-off + 2 through lanes
	var m1 := r1 + 7.0                            # median with covered walkway
	var r2 := m1 + 14.0                           # outer road
	var v1 := r2 + 10.0                           # verge
	var elevated := hub
	var deck_y := 4.5
	var mb := MeshBuilder.new()       # big, always-drawn surfaces
	var dt := MeshBuilder.new()       # small detail (markings, flags, signs, planters)
	var em := MeshBuilder.new()       # self-lit (sign faces, lamp heads)
	mb.xf = xf
	dt.xf = xf
	em.xf = xf
	var paving := Color(0.72, 0.7, 0.66) if not warm else Color(0.82, 0.78, 0.7)
	var paving2 := Color(0.62, 0.6, 0.57) if not warm else Color(0.74, 0.68, 0.6)
	var asphalt := Color(0.2, 0.2, 0.21)
	var kerb := Color(0.8, 0.8, 0.78)
	var concrete := Color(0.78, 0.77, 0.74)
	var paint_w := Color(0.92, 0.92, 0.9)
	var paint_y := Color(0.95, 0.75, 0.1)
	# pavement (raised), roads, median, outer pavement / verge
	var hw_walk := hw_near if end_case else hw
	mb.add_box(Vector3(walk1 * 0.5, 0.08, 0), Vector3(walk1, 0.16, hw_walk * 2.0), paving)
	if end_case:
		mb.add_box(Vector3(walk1 - 5.0, 0.08, 0), Vector3(10.0, 0.16, hw * 2.0), paving)
	mb.add_box(Vector3((walk1 + r1) * 0.5, 0.04, 0), Vector3(r1 - walk1, 0.08, hw * 2.0 + 60.0), asphalt)
	mb.add_box(Vector3((r1 + m1) * 0.5, 0.1, 0), Vector3(m1 - r1, 0.2, hw * 2.0), paving2)
	mb.add_box(Vector3((m1 + r2) * 0.5, 0.04, 0), Vector3(r2 - m1, 0.08, hw * 2.0 + 60.0), asphalt)
	mb.add_box(Vector3((r2 + v1) * 0.5, 0.08, 0), Vector3(v1 - r2, 0.16, hw * 2.0 + 60.0), Color(0.36, 0.5, 0.28) if not ("OMDB" == icao or "OTHH" == icao) else Color(0.78, 0.68, 0.52))
	mb.add_box(Vector3(r2 + 2.0, 0.09, 0), Vector3(4.0, 0.18, hw * 2.0 + 60.0), paving)
	# kerb stones with a yellow no-stopping line on the pavement edges
	for kx in [walk1, m1, r1, r2]:
		mb.add_box(Vector3(kx, 0.1, 0), Vector3(0.3, 0.2, hw * 2.0), kerb)
	for kx2 in [walk1 + 0.35, r1 - 0.35]:
		dt.add_box(Vector3(kx2, 0.085, 0), Vector3(0.15, 0.01, hw * 2.0), paint_y)
	# paving joints on the forecourt: darker bands every 6 m
	var zj := -hw_walk
	while zj < hw_walk:
		dt.add_box(Vector3(walk1 * 0.5, 0.165, zj), Vector3(walk1 - 0.6, 0.01, 0.6), paving2)
		zj += 6.0
	# lane markings: dashed lane lines, a solid line between drop-off and through lanes
	for road in [[walk1, r1], [m1, r2]]:
		var a: float = road[0]
		var bb: float = road[1]
		for li in 3:
			var lx: float = a + (bb - a) * float(li + 1) / 4.0
			var z := -hw - 25.0
			while z < hw + 25.0:
				dt.add_box(Vector3(lx, 0.085, z), Vector3(0.14, 0.01, 3.0 if li != 1 else 9.0), paint_w)
				z += 9.0
	# zebra crossings from the terminal doors across both roads, with bollards and a crossing
	# canopy; the drop-off lanes get "DEPARTURES" / taxi bays painted
	var bollards: Array[Transform3D] = []
	var cross_z := []
	var nc := maxi(2, int(hw * 2.0 / 70.0))
	for k in nc:
		cross_z.append(-hw * 0.82 + hw * 1.64 * (float(k) + 0.5) / nc)
	for cz in cross_z:
		var czf: float = cz
		for road in [[walk1, r1], [m1, r2]]:
			var a: float = road[0]
			var bb: float = road[1]
			var zz := -2.0
			while zz <= 2.01:
				dt.add_box(Vector3((a + bb) * 0.5, 0.085, czf + zz), Vector3(bb - a - 0.6, 0.01, 0.5), paint_w)
				zz += 1.0
		# bollards at each kerb either side of the crossing
		for kx3 in [walk1 - 0.6, r1 + 0.6, m1 - 0.6, r2 + 0.6]:
			for bz in [-3.4, -2.6, 2.6, 3.4]:
				bollards.append(xf * Transform3D(Basis(), Vector3(kx3, 0.16, czf + bz)))
	# bollards along the forecourt edge (anti-ram line)
	var zb := -hw_walk + 2.0
	while zb < hw_walk - 1.0:
		var near_cross := false
		for cz2 in cross_z:
			if absf(zb - float(cz2)) < 4.0:
				near_cross = true
		if not near_cross:
			bollards.append(xf * Transform3D(Basis(), Vector3(walk1 - 0.6, 0.16, zb)))
		zb += 1.8
	# median: covered walkway (white membrane on slim columns) and planters
	var cw_y := 3.6
	mb.add_box(Vector3((r1 + m1) * 0.5, cw_y, 0), Vector3(m1 - r1 - 0.6, 0.18, hw * 1.7), Color(0.95, 0.95, 0.94))
	dt.add_box(Vector3((r1 + m1) * 0.5, cw_y + 0.2, 0), Vector3(1.2, 0.25, hw * 1.7), Color(0.75, 0.77, 0.8))
	var zc := -hw * 0.85
	while zc <= hw * 0.85:
		for sx in [r1 + 0.9, m1 - 0.9]:
			ModelKit.cyl(dt, Vector3(sx, 0.2, zc), Vector3(sx, cw_y, zc), 0.1, 0.1, 6, Color(0.7, 0.72, 0.75), false)
		zc += 12.0
	# planters along the median and the forecourt (low concrete troughs with shrubs)
	var green := Color(0.2, 0.38, 0.17) if not icao in DESERT else Color(0.35, 0.42, 0.2)
	var zp := -hw * 0.85 + 6.0
	while zp < hw * 0.85:
		var near := false
		for cz3 in cross_z:
			if absf(zp - float(cz3)) < 6.0:
				near = true
		if not near:
			dt.add_box(Vector3((r1 + m1) * 0.5, 0.5, zp), Vector3(2.4, 0.6, 5.0), concrete)
			dt.add_box(Vector3((r1 + m1) * 0.5, 0.95, zp), Vector3(2.0, 0.5, 4.6), green)
		zp += 12.0
	# trees / palms on the median, verge and forecourt
	var plants: Array[Transform3D] = []
	var zt := -hw * 0.85
	while zt <= hw * 0.85:
		var near2 := false
		for cz4 in cross_z:
			if absf(zt - float(cz4)) < 5.0:
				near2 = true
		if not near2:
			var s := r.randf_range(0.85, 1.2)
			plants.append(xf * Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), Vector3((r1 + m1) * 0.5, 0.2, zt)))
		var s2 := r.randf_range(0.9, 1.3)
		plants.append(xf * Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s2, s2, s2)), Vector3((r2 + v1) * 0.5 + 2.0, 0.16, zt + 4.0)))
		zt += 12.0 if warm else 16.0
	if end_case and not elevated:
		var zf := -hw_near + 6.0
		while zf < hw_near - 4.0:
			plants.append(xf * Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(walk1 * 0.45, 0.16, zf)))
			zf += 14.0
	# lamp posts along the verge and the median
	var lamps: Array[Transform3D] = []
	var zl := -hw - 20.0
	while zl <= hw + 20.0:
		lamps.append(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(r2 + 3.5, 0.16, zl)))
		zl += 30.0
	# flags: rows of national flags on poles at international airports
	var country := String(ap.get("country", ""))
	var intl := hub or not country in FICTIONAL
	if intl:
		var names := _flag_list(icao, country, 28 if hub else 12)
		var row_x := (r2 + v1) * 0.5 - 1.5 if not end_case else walk1 * 0.35
		var span := minf(hw_walk * 1.6, names.size() * 5.5)
		for i in names.size():
			var fz := -span * 0.5 + span * (float(i) + 0.5) / names.size()
			var pat: Array = FLAGS.get(String(names[i]), FLAGS["United States"])
			_flag_pole(dt, Vector3(row_x, 0.16, fz), 11.0 if hub else 8.0, pat)
		if end_case:
			# a second row on the median, like Miami's kerbside
			var names2 := _flag_list(icao + "2", country, 16 if hub else 8)
			var span2 := minf(hw * 1.5, names2.size() * 5.5)
			for i2 in names2.size():
				var fz2 := -span2 * 0.5 + span2 * (float(i2) + 0.5) / names2.size()
				_flag_pole(dt, Vector3((r2 + v1) * 0.5 - 1.5, 0.16, fz2), 9.0, FLAGS.get(String(names2[i2]), FLAGS["United States"]))
	# road signs: an overhead gantry over each road, direction signs on posts
	var labels := []
	_gantry(mb, em, labels, xf, Vector3((walk1 + r1) * 0.5, 0.0, -hw * 0.95), r1 - walk1 + 2.0, "ARRIVALS  •  PICK-UP" if elevated else "DEPARTURES  •  ARRIVALS", Color(0.08, 0.2, 0.45))
	_gantry(mb, em, labels, xf, Vector3((m1 + r2) * 0.5, 0.0, -hw * 0.95 - 30.0), r2 - m1 + 2.0, "TAXI  •  BUS  •  PARKING", Color(0.05, 0.32, 0.16))
	for k3 in 3:
		var sp := Vector3(r2 + 1.2, 0.16, -hw * 0.6 + k3 * hw * 0.6)
		ModelKit.cyl(dt, sp, sp + Vector3(0, 2.6, 0), 0.05, 0.05, 6, Color(0.6, 0.6, 0.62), false)
		dt.add_box(sp + Vector3(0, 2.9, 0), Vector3(0.08, 0.8, 1.8), Color(0.1, 0.25, 0.55))
		em.add_box(sp + Vector3(-0.05, 2.9, 0), Vector3(0.01, 0.7, 1.7), [Color(0.1, 0.25, 0.55), Color(0.85, 0.65, 0.1), Color(0.1, 0.4, 0.2)][k3])
		labels.append([["P  Parking", "TAXI", "Car rental"][k3], xf * (sp + Vector3(-0.07, 2.9, 0)), (xf.basis * Vector3(-1, 0, 0)), 0.32])
	# taxis, cars and buses at the kerb
	var cars: Array = []
	var taxi := Color(0.95, 0.75, 0.1) if country in ["United States", "Canada", "Mexico", "Calderra"] else (Color(0.08, 0.08, 0.09) if country == "United Kingdom" else Color(0.92, 0.92, 0.9))
	var car_cols := [Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.12), Color(0.55, 0.57, 0.6), Color(0.6, 0.1, 0.1), Color(0.15, 0.25, 0.5), Color(0.75, 0.75, 0.78)]
	var zq := -hw * 0.8
	while zq < hw * 0.8:
		var near3 := false
		for cz5 in cross_z:
			if absf(zq - float(cz5)) < 7.0:
				near3 = true
		if not near3 and r.randf() < 0.65:
			var is_taxi := r.randf() < 0.45
			cars.append([xf * Transform3D(Basis(), Vector3(walk1 + 1.8, 0.08, zq)), taxi if is_taxi else car_cols[r.randi() % car_cols.size()], Vector3.ONE])
		if not near3 and r.randf() < 0.45:
			cars.append([xf * Transform3D(Basis(), Vector3(walk1 + 5.3 + r.randf_range(-0.3, 0.3), 0.08, zq + 2.0)), car_cols[r.randi() % car_cols.size()], Vector3.ONE])
		if not near3 and r.randf() < 0.3:
			cars.append([xf * Transform3D(Basis(Vector3.UP, PI), Vector3(m1 + 1.8, 0.08, zq)), taxi, Vector3.ONE])
		zq += 6.5
	# buses at the outer kerb
	for kb in 2:
		cars.append([xf * Transform3D(Basis(Vector3.UP, PI), Vector3(r2 - 1.9, 0.08, -hw * 0.3 + kb * hw * 0.45)), [Color(0.1, 0.3, 0.6), Color(0.85, 0.85, 0.85)][kb], Vector3(1.4, 1.9, 2.7)])
	# hub: elevated departures roadway level with the departures floor
	if elevated:
		_deck(mb, dt, em, labels, xf, walk1, r1, hw_near if end_case else hw, deck_y, end_case, lamps, warm)
	# ---------------------------------------------------------------- nodes
	var mat: Material = mgr.material_for("vcolor", {}, view)
	_mi(view, mb, mat, 0.0, true)
	_mi(view, dt, mat, 2200.0, false)
	_mi(view, em, TerminalInterior.material("emit"), 1800.0, false)
	_mm(view, _bollard(), bollards, mat, 700.0)
	_mm(view, _lamp(), lamps, mat, 2500.0)
	_mm(view, _palm() if warm else _tree(), plants, mat, 3500.0)
	if not cars.is_empty() and mgr.get("car_mesh") != null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mgr.car_mesh
		mm.instance_count = cars.size()
		for i3 in cars.size():
			var t: Transform3D = cars[i3][0]
			var sc: Vector3 = cars[i3][2]
			mm.set_instance_transform(i3, Transform3D(t.basis.scaled(sc), t.origin))
			var cc: Color = cars[i3][1]
			mm.set_instance_custom_data(i3, cc)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mgr.instanced_material
		mmi.visibility_range_end = 2000.0
		mmi.name = "KerbCars"
		view.add_child(mmi)
	for lb in labels:
		var l := Label3D.new()
		l.text = String(lb[0])
		l.font_size = 64
		l.pixel_size = float(lb[3]) / 64.0 * 1.4
		l.modulate = Color(1, 1, 1)
		l.double_sided = false
		l.position = lb[1]
		var f: Vector3 = lb[2]
		l.basis = Basis.looking_at(-f.normalized(), Vector3.UP)
		l.visibility_range_end = 500.0
		view.add_child(l)


static func _deck(mb: MeshBuilder, dt: MeshBuilder, em: MeshBuilder, labels: Array, xf: Transform3D, walk1: float, r1: float, hw: float, y: float,
		end_case: bool, lamps: Array[Transform3D], warm: bool) -> void:
	## Elevated departures level: pavement + two-lane roadway on piers, parapets, ramps down at
	## both ends, lamp posts and a canopy over the drop-off kerb.
	var deck_c := Color(0.8, 0.79, 0.76)
	var asphalt := Color(0.22, 0.22, 0.23)
	var x0 := 0.0 if end_case else walk1 - 2.0
	mb.add_box(Vector3((x0 + walk1) * 0.5, y - 0.3, 0), Vector3(walk1 - x0, 0.6, hw * 2.0), deck_c)
	mb.add_box(Vector3((walk1 + r1) * 0.5, y - 0.35, 0), Vector3(r1 - walk1, 0.7, hw * 2.0), asphalt)
	mb.add_box(Vector3((walk1 + r1) * 0.5, y - 0.55, 0), Vector3(r1 - walk1 + 0.2, 0.6, hw * 2.0), deck_c)
	mb.add_box(Vector3(walk1, y + 0.08, 0), Vector3(0.3, 0.16, hw * 2.0), Color(0.85, 0.85, 0.83))
	# parapet with a steel rail on the outer edge
	mb.add_box(Vector3(r1 + 0.2, y + 0.5, 0), Vector3(0.4, 1.0, hw * 2.0), deck_c)
	dt.add_box(Vector3(r1 + 0.2, y + 1.15, 0), Vector3(0.12, 0.08, hw * 2.0), Color(0.6, 0.62, 0.65))
	# piers (twin columns under a cross-head) every 18 m
	var z := -hw + 6.0
	while z < hw:
		for px in [walk1 + 1.2, r1 - 1.2]:
			ModelKit.cyl(mb, Vector3(px, 0.0, z), Vector3(px, y - 0.85, z), 0.6, 0.6, 10, deck_c, false)
		mb.add_box(Vector3((walk1 + r1) * 0.5, y - 1.05, z), Vector3(r1 - walk1 - 0.4, 0.6, 1.4), deck_c)
		if end_case:
			ModelKit.cyl(mb, Vector3(walk1 * 0.5, 0.0, z), Vector3(walk1 * 0.5, y - 0.6, z), 0.55, 0.55, 10, deck_c, false)
		z += 18.0
	# lane markings on the deck
	var zd := -hw + 2.0
	while zd < hw - 2.0:
		dt.add_box(Vector3((walk1 + r1) * 0.5, y + 0.005, zd), Vector3(0.14, 0.01, 3.0), Color(0.92, 0.92, 0.9))
		zd += 9.0
	dt.add_box(Vector3(walk1 + 0.4, y + 0.005, 0), Vector3(0.15, 0.01, hw * 2.0), Color(0.95, 0.75, 0.1))
	# ramps down to grade at both ends
	var ramp_l := 60.0
	for sz in [-1.0, 1.0]:
		var za: float = sz * hw
		var zb: float = sz * (hw + ramp_l)
		var top0 := Vector3(walk1, y, za)
		var top1 := Vector3(r1, y, za)
		var bot0 := Vector3(walk1, 0.1, zb)
		var bot1 := Vector3(r1, 0.1, zb)
		ModelKit.quad(mb, top0, top1, bot1, bot0, Vector3(0, 1, 0), asphalt)
		ModelKit.quad(mb, top0 - Vector3(0, 0.7, 0), top1 - Vector3(0, 0.7, 0), bot1 - Vector3(0, 0.1, 0), bot0 - Vector3(0, 0.1, 0), Vector3(0, -1, 0), deck_c)
		for ex in [walk1, r1]:
			var side := Vector3(-1 if ex == walk1 else 1, 0, 0)
			ModelKit.quad(mb, Vector3(ex, y + 1.0, za), Vector3(ex, 0.9, zb), Vector3(ex, 0.0, zb), Vector3(ex, y - 0.7, za), side, deck_c)
			ModelKit.quad(mb, Vector3(ex, y + 1.0, za), Vector3(ex, 0.9, zb), Vector3(ex, 0.0, zb), Vector3(ex, y - 0.7, za), -side, deck_c)
		# a pier at mid-ramp
		var zm := (za + zb) * 0.5
		ModelKit.cyl(mb, Vector3((walk1 + r1) * 0.5, 0.0, zm), Vector3((walk1 + r1) * 0.5, y * 0.5 - 0.5, zm), 0.6, 0.6, 10, deck_c, false)
	# lamp posts on the parapet
	var zl := -hw + 10.0
	while zl < hw:
		lamps.append(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(r1 + 0.2, y + 1.0, zl)))
		zl += 24.0
	# canopy over the drop-off kerb: a shallow white vault on a row of tree columns
	var cy := y + 7.5
	var cx0 := x0 + 1.0 if end_case else walk1 - 6.0
	var cx1 := walk1 + 4.0
	ModelKit.arch(mb, Vector3((cx0 + cx1) * 0.5, cy, 0), cx1 - cx0 + 2.0, 1.6, hw * 1.9, 10, Color(0.95, 0.95, 0.94))
	mb.add_box(Vector3((cx0 + cx1) * 0.5, cy - 0.1, 0), Vector3(cx1 - cx0 + 2.0, 0.2, hw * 1.9), Color(0.9, 0.9, 0.9))
	var zc := -hw * 0.95 + 4.0
	while zc < hw * 0.95:
		var base := Vector3(cx1 - 1.5, y, zc)
		ModelKit.cyl(mb, base, base + Vector3(0, 4.5, 0), 0.28, 0.22, 8, Color(0.85, 0.86, 0.88), false)
		for br in [Vector3(-2.2, 7.5, -1.6), Vector3(-2.2, 7.5, 1.6), Vector3(1.2, 7.5, 0.0)]:
			ModelKit.bar(dt, base + Vector3(0, 4.5, 0), base + (br as Vector3) - Vector3(0, 0.1, 0), 0.12, Color(0.85, 0.86, 0.88), 6)
		zc += 16.0
	# lit downlights under the canopy and a departures sign over the kerb
	var zk := -hw * 0.9
	while zk < hw * 0.9:
		em.add_box(Vector3((cx0 + cx1) * 0.5, cy - 0.21, zk), Vector3(cx1 - cx0 - 2.0, 0.02, 0.25), Color(1.0, 0.95, 0.85))
		zk += 8.0
	for sz2 in [-0.5, 0.5]:
		var sp := Vector3(walk1 + 0.5, y + 4.6, hw * sz2)
		mb.add_box(sp, Vector3(0.3, 1.0, 9.0), Color(0.06, 0.1, 0.2))
		em.add_box(sp + Vector3(0.16, 0, 0), Vector3(0.02, 0.85, 8.8), Color(0.08, 0.16, 0.36))
		labels.append(["DEPARTURES   ✈", xf * (sp + Vector3(0.18, 0.0, 0)), xf.basis * Vector3(1, 0, 0), 0.55])
		for k in 2:
			dt.add_box(sp + Vector3(0, 0.5 + 2.0 * 0.5, (k - 0.5) * 6.0), Vector3(0.06, 2.0, 0.06), Color(0.6, 0.62, 0.65))
	# palms or planters along the deck pavement
	if warm:
		var zp := -hw + 8.0
		while zp < hw - 4.0:
			dt.add_box(Vector3(walk1 - 1.6, y + 0.4, zp), Vector3(1.6, 0.8, 1.6), Color(0.78, 0.76, 0.72))
			dt.add_sphere(Vector3(walk1 - 1.6, y + 1.1, zp), Vector3(0.75, 0.5, 0.75), 8, 4, Color(0.22, 0.42, 0.18))
			zp += 20.0


static func _gantry(mb: MeshBuilder, em: MeshBuilder, labels: Array, xf: Transform3D, p: Vector3, span: float, text: String, col: Color) -> void:
	for sx in [-0.5, 0.5]:
		ModelKit.cyl(mb, p + Vector3(sx * span, 0, 0), p + Vector3(sx * span, 7.0, 0), 0.22, 0.2, 8, Color(0.62, 0.64, 0.66), false)
	mb.add_box(p + Vector3(0, 6.7, 0), Vector3(span, 0.4, 0.4), Color(0.62, 0.64, 0.66))
	mb.add_box(p + Vector3(0, 5.8, -0.3), Vector3(span * 0.8, 1.6, 0.15), col)
	em.add_box(p + Vector3(0, 5.8, -0.39), Vector3(span * 0.78, 1.45, 0.02), col.lightened(0.1))
	labels.append([text, xf * (p + Vector3(0, 5.8, -0.42)), xf.basis * Vector3(0, 0, -1), 0.55])


static func _flag_list(icao: String, country: String, n: int) -> Array:
	var pool_name := "global"
	if country in ["United States", "Canada", "Bermuda"]:
		pool_name = "americas"
	elif country in ASIA:
		pool_name = "asia"
	elif not country in FICTIONAL:
		pool_name = "europe"
	var pool: Array = (POOLS[pool_name] as Array).duplicate()
	var r := U.rng(U.hash_str(icao + "flags"))
	for i in range(pool.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out := []
	var host := country if FLAGS.has(country) else "United States"
	for i2 in n:
		if i2 == 0 or i2 == n - 1 or i2 == n / 2:
			out.append(host)
		else:
			var pick := String(pool[i2 % pool.size()])
			out.append(pick if pick != host else String(pool[(i2 + 3) % pool.size()]))
	return out


static func _flag_pole(mb: MeshBuilder, base: Vector3, h: float, pat: Array) -> void:
	ModelKit.cyl(mb, base, base + Vector3(0, h, 0), 0.07, 0.05, 6, Color(0.88, 0.88, 0.9), false)
	mb.add_sphere(base + Vector3(0, h + 0.06, 0), Vector3(0.09, 0.09, 0.09), 6, 3, Color(0.85, 0.7, 0.3))
	ModelKit.cyl(mb, base, base + Vector3(0, 0.25, 0), 0.18, 0.18, 8, Color(0.5, 0.5, 0.52), false)
	# flag flies along +z from the pole, slightly drooped
	var fw := 2.2 if h > 9.0 else 1.6
	var fh := fw * 0.62
	var top := base + Vector3(0, h - 0.15, 0.07)
	_flag(mb, top, fw, fh, pat)


static func _frect(mb: MeshBuilder, top: Vector3, u0: float, v0: float, u1: float, v1: float, c: Color, th: float = 0.03) -> void:
	## Flag-space rectangle: u along the fly (+z), v down from the top edge.
	mb.add_box(top + Vector3(0, -(v0 + v1) * 0.5, (u0 + u1) * 0.5), Vector3(th, v1 - v0, u1 - u0), c)


static func _flag(mb: MeshBuilder, top: Vector3, w: float, h: float, pat: Array) -> void:
	var kind := String(pat[0])
	var cols: Array = pat.slice(1)
	var c0: Color = cols[0]
	var c1: Color = cols[1] if cols.size() > 1 else c0
	var c2: Color = cols[2] if cols.size() > 2 else c1
	match kind:
		"h":
			var n := cols.size()
			for i in n:
				_frect(mb, top, 0, h * i / n, w, h * (i + 1) / n, cols[i])
		"v":
			var n2 := cols.size()
			for i in n2:
				_frect(mb, top, w * i / n2, 0, w * (i + 1) / n2, h, cols[i])
		"nordic":
			_frect(mb, top, 0, 0, w, h, c0)
			_frect(mb, top, w * 0.3, 0, w * 0.44, h, c1, 0.04)
			_frect(mb, top, 0, h * 0.4, w, h * 0.6, c1, 0.04)
			if cols.size() > 2:
				_frect(mb, top, w * 0.33, 0, w * 0.41, h, c2, 0.05)
				_frect(mb, top, 0, h * 0.45, w, h * 0.55, c2, 0.05)
		"disc":
			_frect(mb, top, 0, 0, w, h, c0)
			var cc := top + Vector3(0, -h * 0.5, w * 0.5)
			ModelKit.cyl(mb, cc - Vector3(0.025, 0, 0), cc + Vector3(0.025, 0, 0), h * 0.3, h * 0.3, 14, c1)
		"cross":
			_frect(mb, top, 0, 0, w, h, c0)
			_frect(mb, top, w * 0.42, h * 0.18, w * 0.58, h * 0.82, c1, 0.04)
			_frect(mb, top, w * 0.3, h * 0.42, w * 0.7, h * 0.58, c1, 0.04)
		"canton":
			for i in 7:
				_frect(mb, top, 0, h * i / 7.0, w, h * (i + 1) / 7.0, c0 if i % 2 == 0 else c1)
			_frect(mb, top, 0, 0, w * 0.42, h * 4.0 / 7.0, c2, 0.04)
		"hoist":
			var n3 := cols.size() - 1
			for i in n3:
				_frect(mb, top, w * 0.28, h * i / n3, w, h * (i + 1) / n3, cols[i + 1])
			_frect(mb, top, 0, 0, w * 0.28, h, c0)
		"uk":
			_frect(mb, top, 0, 0, w, h, c0)
			_frect(mb, top, w * 0.42, 0, w * 0.58, h, c1, 0.04)
			_frect(mb, top, 0, h * 0.38, w, h * 0.62, c1, 0.04)
			_frect(mb, top, w * 0.46, 0, w * 0.54, h, c2, 0.05)
			_frect(mb, top, 0, h * 0.44, w, h * 0.56, c2, 0.05)
		"canada":
			_frect(mb, top, 0, 0, w * 0.25, h, c0)
			_frect(mb, top, w * 0.25, 0, w * 0.75, h, c1)
			_frect(mb, top, w * 0.75, 0, w, h, c0)
			_frect(mb, top, w * 0.4, h * 0.3, w * 0.6, h * 0.7, c0, 0.04)
		"star":
			_frect(mb, top, 0, 0, w, h, c0)
			_frect(mb, top, w * 0.08, h * 0.1, w * 0.3, h * 0.42, c1, 0.04)
		"diamond":
			_frect(mb, top, 0, 0, w, h, c0)
			var cc2 := top + Vector3(0, -h * 0.5, w * 0.5)
			mb.add_box_xf(Transform3D(Basis(Vector3.RIGHT, PI * 0.25).scaled(Vector3(1, 0.7, 1.25)), cc2), Vector3(0.04, h * 0.6, h * 0.6), c1)
			ModelKit.cyl(mb, cc2 - Vector3(0.03, 0, 0), cc2 + Vector3(0.03, 0, 0), h * 0.2, h * 0.2, 12, c2)
		_:
			_frect(mb, top, 0, 0, w, h, c0)


# ------------------------------------------------------------------ instanced props
static func _palm() -> ArrayMesh:
	if _palm_mesh:
		return _palm_mesh
	var mb := MeshBuilder.new()
	var trunk := Color(0.5, 0.42, 0.32)
	var h := 9.0
	var prev := Vector3.ZERO
	for k in 6:
		var t := float(k + 1) / 6.0
		var p := Vector3(sin(t * 1.2) * 0.6, t * h, 0)
		ModelKit.cyl(mb, prev, p, lerpf(0.26, 0.16, t - 1.0 / 6.0), lerpf(0.26, 0.16, t), 6, trunk if k % 2 == 0 else trunk.darkened(0.12), false)
		prev = p
	var crown := prev
	mb.add_sphere(crown, Vector3(0.4, 0.45, 0.4), 6, 4, Color(0.4, 0.36, 0.2))
	var greens := [Color(0.2, 0.42, 0.16), Color(0.26, 0.5, 0.2), Color(0.18, 0.36, 0.14)]
	for f in 9:
		var a := TAU * float(f) / 9.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		# frond: two drooping segments, wide in the middle
		var p0 := crown
		var p1 := crown + d * 2.0 + Vector3(0, 0.6, 0)
		var p2 := crown + d * 3.8 - Vector3(0, 1.0, 0)
		var c: Color = greens[f % 3]
		ModelKit.quad(mb, p0 - side * 0.12, p0 + side * 0.12, p1 + side * 0.65, p1 - side * 0.65, Vector3(0, 1, 0), c)
		ModelKit.quad(mb, p0 - side * 0.12, p0 + side * 0.12, p1 + side * 0.65, p1 - side * 0.65, Vector3(0, -1, 0), c.darkened(0.2))
		ModelKit.quad(mb, p1 - side * 0.65, p1 + side * 0.65, p2 + side * 0.08, p2 - side * 0.08, Vector3(0, 1, 0), c)
		ModelKit.quad(mb, p1 - side * 0.65, p1 + side * 0.65, p2 + side * 0.08, p2 - side * 0.08, Vector3(0, -1, 0), c.darkened(0.2))
	_palm_mesh = mb.commit()
	return _palm_mesh


static func _tree() -> ArrayMesh:
	if _tree_mesh:
		return _tree_mesh
	var mb := MeshBuilder.new()
	ModelKit.cyl(mb, Vector3.ZERO, Vector3(0, 2.6, 0), 0.18, 0.13, 6, Color(0.36, 0.28, 0.2), false)
	mb.add_sphere(Vector3(0, 3.8, 0), Vector3(1.9, 1.7, 1.9), 8, 5, Color(0.22, 0.38, 0.17))
	mb.add_sphere(Vector3(0.7, 4.6, 0.3), Vector3(1.3, 1.2, 1.3), 7, 4, Color(0.26, 0.44, 0.2))
	mb.add_sphere(Vector3(-0.6, 4.4, -0.5), Vector3(1.2, 1.1, 1.2), 7, 4, Color(0.19, 0.34, 0.15))
	_tree_mesh = mb.commit()
	return _tree_mesh


static func _lamp() -> ArrayMesh:
	## Street lamp: tapered pole, an arm reaching over the road (-x) and a flat LED head.
	if _lamp_mesh:
		return _lamp_mesh
	var mb := MeshBuilder.new()
	var steel := Color(0.55, 0.57, 0.6)
	ModelKit.cyl(mb, Vector3.ZERO, Vector3(0, 9.0, 0), 0.13, 0.08, 6, steel, false)
	ModelKit.cyl(mb, Vector3(0, 0, 0), Vector3(0, 0.4, 0), 0.22, 0.2, 6, steel.darkened(0.3), false)
	ModelKit.bar(mb, Vector3(0, 8.8, 0), Vector3(1.8, 9.3, 0), 0.06, steel, 4)
	mb.add_box(Vector3(2.2, 9.3, 0), Vector3(1.0, 0.14, 0.4), Color(0.25, 0.26, 0.28))
	mb.add_box(Vector3(2.2, 9.22, 0), Vector3(0.8, 0.02, 0.3), Color(1.0, 0.97, 0.88))
	_lamp_mesh = mb.commit()
	return _lamp_mesh


static func _bollard() -> ArrayMesh:
	if _bollard_mesh:
		return _bollard_mesh
	var mb := MeshBuilder.new()
	ModelKit.cyl(mb, Vector3.ZERO, Vector3(0, 0.95, 0), 0.11, 0.11, 8, Color(0.72, 0.73, 0.75), true)
	ModelKit.cyl(mb, Vector3(0, 0.8, 0), Vector3(0, 0.86, 0), 0.115, 0.115, 8, Color(0.95, 0.75, 0.1), false)
	_bollard_mesh = mb.commit()
	return _bollard_mesh


static func _mi(view: Node3D, mb: MeshBuilder, mat: Material, vis_end: float, shadow: bool) -> void:
	if mb.verts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	mi.name = "Landside"
	view.add_child(mi)


static func _mm(view: Node3D, mesh: Mesh, xfs: Array[Transform3D], mat: Material, vis_end: float) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = vis_end
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vis_end > 2000.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(mmi)
