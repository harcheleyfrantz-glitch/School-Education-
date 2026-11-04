extends RefCounted
## Passenger boarding bridges and stand dressing. A bridge is a fixed corridor from the terminal
## glass to a glazed rotunda (with service stairs down to the apron), three telescoping tunnel
## sections, a level cab with a bellows canopy at the aircraft door, and a drive column on a
## wheel bogie under the outer tunnel. Finishes differ per airport: all-glass tunnels on white
## frames, stainless corrugated tunnels with a window band, or painted panels.
## AirportView owns the state (dock / undock / walk path); this file builds the nodes and poses
## them (apply).

const FLOOR := 4.5        # TerminalInterior.FLOOR
const W := 2.6            # inside width
const H := 2.45           # inside height
const CAB_D := 3.0
const ROT_R := 2.3
const SECTIONS := 3
const OVERLAP := 0.7
const GROW := 0.09        # each outer tunnel section is this much wider / taller per side

const GLASS_HUBS := ["KLAX", "KMIA", "KJFK", "KATL", "EGLL", "OMDB", "WSSS", "RJTT", "LFPG", "SKPC", "OTHH", "VHHH", "RKSI", "LTFM", "EDDM", "ZSPD"]


static func finish_for(icao: String) -> Dictionary:
	var kind: String = "glass" if icao in GLASS_HUBS else ["metal", "painted", "metal", "glass", "painted"][U.hash_str(icao + "jb") % 5]
	var r := U.rng(U.hash_str(icao + "jbcol"))
	var paint: Color = [Color(0.78, 0.8, 0.82), Color(0.55, 0.58, 0.62), Color(0.86, 0.84, 0.78), Color(0.32, 0.36, 0.42), Color(0.9, 0.9, 0.9)][r.randi() % 5]
	match kind:
		"glass":
			return {"kind": kind, "shell": Color(0.93, 0.94, 0.95), "trim": Color(0.82, 0.84, 0.86), "glass": Color(0.2, 0.32, 0.38),
				"inner": Color(0.88, 0.88, 0.86), "carpet": [Color(0.16, 0.19, 0.26), Color(0.32, 0.1, 0.12), Color(0.2, 0.22, 0.24)][r.randi() % 3]}
		"metal":
			return {"kind": kind, "shell": Color(0.72, 0.74, 0.76), "trim": Color(0.55, 0.57, 0.6), "glass": Color(0.12, 0.17, 0.22),
				"inner": Color(0.85, 0.84, 0.81), "carpet": Color(0.18, 0.2, 0.26)}
		_:
			return {"kind": kind, "shell": paint, "trim": paint.darkened(0.25), "glass": Color(0.1, 0.14, 0.18),
				"inner": Color(0.86, 0.85, 0.82), "carpet": Color(0.2, 0.18, 0.22)}


static func corridor(mb: MeshBuilder, z0: float, z1: float, f: Dictionary, grow: float = 0.0, ring: bool = false) -> void:
	## Hollow corridor along +z with its floor at y = 0 (double-sided material). Glass finish:
	## floor-to-roof glazing between a low sill and the roof band; metal: horizontal corrugations
	## with a window band; painted: flat panels with a window band. ring adds a frame at z1.
	var hw := W * 0.5 + grow
	var h := H + grow
	var L := z1 - z0
	var zc := (z0 + z1) * 0.5
	var shell: Color = f.shell
	var trim: Color = f.trim
	var glass: Color = f.glass
	var kind := String(f.kind)
	mb.add_box(Vector3(0, -0.12, zc), Vector3(W + 0.3 + grow * 2.0, 0.24, L), shell.darkened(0.15))
	mb.add_box(Vector3(0, 0.005, zc), Vector3(W - 0.1, 0.01, L), f.carpet)
	mb.add_box(Vector3(0, h + 0.14, zc), Vector3(hw * 2.0 + 0.3, 0.28, L), shell)
	mb.add_box(Vector3(0, H - 0.01, zc), Vector3(W - 0.2, 0.02, L), f.inner)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hw + 0.07)
		match kind:
			"glass":
				mb.add_box(Vector3(x, 0.2, zc), Vector3(0.14, 0.4, L), trim)
				mb.add_box(Vector3(x, 0.4 + (h - 0.6) * 0.5, zc), Vector3(0.05, h - 0.6, L), glass)
				mb.add_box(Vector3(x, h - 0.1, zc), Vector3(0.14, 0.2, L), shell)
			"metal":
				mb.add_box(Vector3(x, 0.45, zc), Vector3(0.14, 0.9, L), shell)
				mb.add_box(Vector3(x, 0.9 + 0.55, zc), Vector3(0.05, 1.1, L), glass)
				mb.add_box(Vector3(x, 2.0 + (h - 2.0) * 0.5, zc), Vector3(0.14, h - 2.0, L), shell)
				for ry in [0.15, 0.35, 0.55, 0.75]:
					mb.add_box(Vector3(x + sx * 0.08, ry, zc), Vector3(0.03, 0.06, L), trim)
				mb.add_box(Vector3(x + sx * 0.08, 2.2, zc), Vector3(0.03, 0.06, L), trim)
			_:
				mb.add_box(Vector3(x, 0.5, zc), Vector3(0.14, 1.0, L), shell)
				mb.add_box(Vector3(x, 1.0 + 0.5, zc), Vector3(0.05, 1.0, L), glass)
				mb.add_box(Vector3(x, 2.0 + (h - 2.0) * 0.5, zc), Vector3(0.14, h - 2.0, L), shell)
				mb.add_box(Vector3(x + sx * 0.08, 0.95, zc), Vector3(0.02, 0.08, L), trim)
		mb.add_box(Vector3(sx * (W * 0.5 - 0.02), 0.06, zc), Vector3(0.04, 0.12, L), Color(0.18, 0.19, 0.2))
		# handrail
		mb.add_box(Vector3(sx * (W * 0.5 - 0.06), 0.95, zc), Vector3(0.05, 0.05, L), Color(0.7, 0.72, 0.75))
	if ring:
		var rl := minf(0.06, L * 0.5)
		var rz := z1 - rl * 0.5
		var rc: Color = trim.darkened(0.2)
		mb.add_box(Vector3(0, h + 0.33, rz), Vector3(hw * 2.0 + 0.5, 0.12, rl), rc)
		mb.add_box(Vector3(0, -0.28, rz), Vector3(hw * 2.0 + 0.5, 0.1, rl), rc)
		for sx2 in [-1.0, 1.0]:
			mb.add_box(Vector3(sx2 * (hw + 0.2), h * 0.5, rz), Vector3(0.12, h + 0.6, rl), rc)


static func _mi(parent: Node3D, mb: MeshBuilder, mat: Material, vis: float = 4000.0, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	mi.visibility_range_end = vis
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func make(view: Node3D, b: Dictionary, mat: Material, f: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "JetBridge"
	var rp: Vector2 = b.root
	var nrm: Vector2 = b.normal
	root.position = Vector3(rp.x, 0, rp.y)
	view.add_child(root)
	var emit: Material = TerminalInterior.material("emit")
	var light := Color(1.0, 0.96, 0.88)
	var yaw_n := atan2(nrm.x, nrm.y)
	var rot := rp + nrm * 9.0
	var rl := Vector3(rot.x - rp.x, 0, rot.y - rp.y)
	var steel := Color(0.48, 0.49, 0.52)
	# fixed corridor from the terminal glass to the rotunda, floor level with departures
	var stub := MeshBuilder.new()
	stub.xf = Transform3D(Basis(Vector3.UP, yaw_n), Vector3(0, FLOOR, 0))
	corridor(stub, 0.0, 9.0 - ROT_R + 0.3, f)
	# its support legs
	for zz in [3.0, 6.0]:
		for sx in [-1.0, 1.0]:
			ModelKit.cyl(stub, Vector3(sx * 1.0, -FLOOR, zz), Vector3(sx * 1.0, -0.24, zz), 0.13, 0.13, 6, steel, false)
	# rotunda: round floor and roof, glazed drum on mullions, a big support column
	stub.xf = Transform3D(Basis(), rl + Vector3(0, FLOOR, 0))
	ModelKit.cyl(stub, Vector3(0, -0.3, 0), Vector3(0, 0.0, 0), ROT_R + 0.15, ROT_R + 0.15, 18, f.shell.darkened(0.15))
	stub.add_cylinder(Vector3(0, 0.0, 0), Vector3(0, 0.01, 0), ROT_R - 0.05, ROT_R - 0.05, 18, f.carpet, false)
	ModelKit.cyl(stub, Vector3(0, H, 0), Vector3(0, H + 0.45, 0), ROT_R + 0.25, ROT_R + 0.2, 18, f.shell)
	ModelKit.cyl(stub, Vector3(0, H + 0.45, 0), Vector3(0, H + 0.6, 0), ROT_R + 0.1, ROT_R - 0.6, 18, f.trim)
	stub.add_cylinder(Vector3(0, 0.6, 0), Vector3(0, H, 0), ROT_R, ROT_R, 18, f.glass, false)
	stub.add_cylinder(Vector3(0, 0.0, 0), Vector3(0, 0.6, 0), ROT_R + 0.02, ROT_R + 0.02, 18, f.shell, false)
	for k in 9:
		var a := float(k) / 9.0 * TAU
		stub.add_box(Vector3(cos(a) * ROT_R, H * 0.5, sin(a) * ROT_R), Vector3(0.1, H, 0.1), f.trim)
	stub.xf = Transform3D.IDENTITY
	ModelKit.cyl(stub, rl, rl + Vector3(0, FLOOR - 0.3, 0), 0.6, 0.55, 12, Color(0.6, 0.6, 0.62), false)
	ModelKit.cyl(stub, rl, rl + Vector3(0, 0.3, 0), 1.0, 1.0, 12, Color(0.55, 0.55, 0.56))
	# service stairs from the rotunda down to the apron (switchback with a landing and rails)
	var side := Vector3(-nrm.y, 0, nrm.x)       # the bridge's own "left": away from the aircraft
	var s_yaw := atan2(side.x, side.z)
	stub.xf = Transform3D(Basis(Vector3.UP, s_yaw), rl + side * (ROT_R + 0.05))
	var tread := Color(0.4, 0.41, 0.43)
	var rail := Color(0.95, 0.75, 0.1)
	var steps := 12
	var y_mid := (FLOOR - 0.3) * 0.5
	for s in steps:
		var y := FLOOR - 0.3 - (float(s) + 1.0) * (y_mid / steps)
		stub.add_box(Vector3(-0.6, y, 0.4 + float(s) * 0.27), Vector3(1.0, 0.06, 0.28), tread)
	stub.add_box(Vector3(-1.15, y_mid, 4.0), Vector3(2.3, 0.12, 1.2), tread)
	for s2 in steps:
		var y2 := y_mid - (float(s2) + 1.0) * (y_mid / steps)
		stub.add_box(Vector3(-1.7, y2, 3.3 - float(s2) * 0.27), Vector3(1.0, 0.06, 0.28), tread)
	ModelKit.bar(stub, Vector3(-0.08, FLOOR + 0.7, 0.3), Vector3(-0.08, y_mid + 1.0, 3.5), 0.03, rail, 4)
	ModelKit.bar(stub, Vector3(-2.22, y_mid + 1.0, 3.5), Vector3(-2.22, 1.0, 0.3), 0.03, rail, 4)
	ModelKit.bar(stub, Vector3(-0.08, y_mid + 1.0, 4.6), Vector3(-2.22, y_mid + 1.0, 4.6), 0.03, rail, 4)
	for px in [-0.08, -2.22]:
		ModelKit.cyl(stub, Vector3(px, 0.0, 4.5), Vector3(px, y_mid, 4.5), 0.06, 0.06, 4, steel, false)
	stub.xf = Transform3D.IDENTITY
	_mi(root, stub, mat)
	# lights: corridor trough, rotunda ring
	var lights := MeshBuilder.new()
	lights.xf = Transform3D(Basis(Vector3.UP, yaw_n), Vector3(0, FLOOR, 0))
	lights.add_box(Vector3(0, H - 0.03, (9.0 - ROT_R) * 0.5), Vector3(0.3, 0.03, 9.0 - ROT_R - 0.8), light)
	lights.xf = Transform3D.IDENTITY
	lights.add_cylinder(rl + Vector3(0, FLOOR + H - 0.04, 0), rl + Vector3(0, FLOOR + H - 0.02, 0), 0.8, 0.8, 12, light, true)
	_mi(root, lights, emit, 1200.0, false)
	# telescoping tunnel: sections share a unit-length mesh scaled along z by apply()
	var pivot := Node3D.new()
	pivot.position = rl + Vector3(0, FLOOR, 0)
	root.add_child(pivot)
	var tunnel := Node3D.new()
	pivot.add_child(tunnel)
	var sections: Array = []
	for k2 in SECTIONS:
		var sec := Node3D.new()
		tunnel.add_child(sec)
		var tb := MeshBuilder.new()
		corridor(tb, 0.0, 1.0, f, GROW * k2, true)
		_mi(sec, tb, mat)
		var tl := MeshBuilder.new()
		tl.add_box(Vector3(0, H - 0.03, 0.5), Vector3(0.3, 0.03, 0.8), light)
		_mi(sec, tl, emit, 600.0, false)
		sections.append(sec)
	# cab: stays level, opens onto the aircraft door through a dark bellows canopy
	var cab := Node3D.new()
	pivot.add_child(cab)
	var cb := MeshBuilder.new()
	var g2 := GROW * (SECTIONS - 1)
	corridor(cb, 0.0, CAB_D - 0.4, f, g2 + 0.12)
	var dark := Color(0.07, 0.07, 0.08)
	# bellows: accordion ribs around the door opening
	for k3 in 4:
		var zr := CAB_D - 0.42 + k3 * 0.13
		var gw := W * 0.5 + 0.3 + (0.05 if k3 % 2 == 0 else 0.0)
		cb.add_box(Vector3(0, H + 0.2, zr), Vector3(gw * 2.0, 0.22, 0.1), dark)
		for sx3 in [-1.0, 1.0]:
			cb.add_box(Vector3(sx3 * gw, H * 0.5 + 0.05, zr), Vector3(0.22, H + 0.4, 0.1), dark)
	cb.add_box(Vector3(0, -0.05, CAB_D - 0.2), Vector3(W, 0.1, 0.4), Color(0.85, 0.7, 0.1))
	# cab drum under the floor, operator's window, amber beacon and a floodlight on the roof
	ModelKit.cyl(cb, Vector3(0, -0.85, CAB_D * 0.45), Vector3(0, -0.24, CAB_D * 0.45), 1.4, 1.5, 14, f.shell.darkened(0.1))
	cb.add_box(Vector3(W * 0.5 + 0.2 + g2, 1.5, CAB_D - 0.9), Vector3(0.06, 0.9, 1.0), Color(0.08, 0.12, 0.16))
	ModelKit.cyl(cb, Vector3(-0.8, H + 0.28, 0.6), Vector3(-0.8, H + 0.48, 0.6), 0.12, 0.1, 8, Color(1.0, 0.55, 0.05))
	cb.add_box(Vector3(0.8, H + 0.38, CAB_D - 0.7), Vector3(0.4, 0.2, 0.25), Color(0.3, 0.3, 0.32))
	# hazard stripes across the cab nose
	for k4 in 6:
		cb.add_box(Vector3(-W * 0.5 + 0.25 + k4 * 0.5, -0.22, CAB_D - 0.42), Vector3(0.25, 0.14, 0.04), Color(0.95, 0.75, 0.1) if k4 % 2 == 0 else dark)
	# pre-conditioned air hose and power cable hanging under the cab
	ModelKit.cyl(cb, Vector3(1.2, -0.3, 0.5), Vector3(1.3, -2.2, 0.9), 0.17, 0.17, 8, Color(0.92, 0.75, 0.15), false)
	ModelKit.cyl(cb, Vector3(-1.2, -0.3, 0.5), Vector3(-1.25, -1.8, 0.7), 0.05, 0.05, 5, dark, false)
	_mi(cab, cb, mat)
	var cl := MeshBuilder.new()
	cl.add_box(Vector3(0, H - 0.03, (CAB_D - 0.4) * 0.5), Vector3(0.3, 0.03, CAB_D - 0.8), light)
	ModelKit.cyl(cl, Vector3(-0.8, H + 0.47, 0.6), Vector3(-0.8, H + 0.5, 0.6), 0.1, 0.1, 6, Color(1.0, 0.6, 0.1))
	_mi(cab, cl, emit, 1200.0, false)
	# drive column: twin legs, scaled to the cab height each update, on a wheel bogie
	var col := Node3D.new()
	cab.add_child(col)
	col.position = Vector3(0, -0.24, -0.6)
	var colb := MeshBuilder.new()
	for sx4 in [-1.0, 1.0]:
		ModelKit.cyl(colb, Vector3(sx4 * 1.0, -1.0, 0), Vector3(sx4 * 1.0, 0, 0), 0.2, 0.2, 8, Color(0.42, 0.42, 0.44), false)
		ModelKit.cyl(colb, Vector3(sx4 * 1.0, -1.0, 0), Vector3(sx4 * 1.0, -0.55, 0), 0.26, 0.26, 8, Color(0.3, 0.3, 0.32), false)
	colb.add_box(Vector3(0, -0.06, 0), Vector3(2.4, 0.12, 0.4), Color(0.42, 0.42, 0.44))
	_mi(col, colb, mat)
	var bogie := MeshBuilder.new()
	bogie.add_box(Vector3(0, 0.55, 0), Vector3(2.9, 0.45, 1.3), Color(0.3, 0.3, 0.32))
	for k5 in 6:
		bogie.add_box(Vector3(-1.25 + k5 * 0.5, 0.55, 0.66), Vector3(0.25, 0.4, 0.03), Color(0.95, 0.75, 0.1) if k5 % 2 == 0 else dark)
	for sx5 in [-1.0, 1.0]:
		for wz in [-0.42, 0.42]:
			ModelKit.cyl(bogie, Vector3(sx5 * 1.05 - 0.17, 0.4, wz), Vector3(sx5 * 1.05 + 0.17, 0.4, wz), 0.4, 0.4, 12, Color(0.06, 0.06, 0.06))
			ModelKit.cyl(bogie, Vector3(sx5 * 1.05 - 0.18, 0.4, wz), Vector3(sx5 * 1.05 + 0.18, 0.4, wz), 0.2, 0.2, 8, Color(0.6, 0.6, 0.6))
	var bmi := _mi(cab, bogie, mat, 2500.0)
	# parked: swung along the facade toward the aircraft's side
	var left: Vector2 = b.left
	var park_dir := (nrm * 0.55 - left * 0.6).normalized()
	var rest_yaw := atan2(park_dir.x, park_dir.y)
	return {"root": root, "pivot": pivot, "tunnel": tunnel, "sections": sections, "cab": cab, "column": col, "bogie": bmi, "rest_yaw": rest_yaw,
		"stand": b.stand, "docked": false, "length": 12.0, "yaw": rest_yaw, "target_len": 12.0, "target_yaw": rest_yaw, "pitch": 0.0, "target_pitch": 0.0}


static func apply(br: Dictionary) -> void:
	var pitch := float(br.pitch)
	var L := float(br.length)
	br.pivot.basis = Basis(Vector3.UP, float(br.yaw)) * Basis(Vector3.RIGHT, -pitch)
	var secs: Array = br.get("sections", [])
	if secs.is_empty():
		br.tunnel.scale = Vector3(1, 1, L)
	else:
		var n := secs.size()
		var sl := (L + OVERLAP * (n - 1)) / n
		for k in n:
			var s: Node3D = secs[k]
			s.position = Vector3(0, 0, k * (sl - OVERLAP))
			s.scale = Vector3(1, 1, maxf(sl, 0.5))
	br.cab.position = Vector3(0, 0, L)
	br.cab.basis = Basis(Vector3.RIGHT, pitch)
	var cab_h := FLOOR + L * sin(pitch) - 0.24
	br.column.scale = Vector3(1, maxf(cab_h - 0.9, 0.1), 1)
	br.bogie.position = Vector3(0, -cab_h - 0.24, -0.6)


# ------------------------------------------------------------------ stand dressing
static func dress_stands(view: Node3D, layout: Dictionary, icao: String, mat: Material) -> void:
	## Ground equipment parked beside each contact stand (tug and baggage train, belt loader,
	## ground power unit, pushback tractor), cones and chocks, an equipment parking box, and a
	## docking guidance display on the facade above the stand.
	var mb := MeshBuilder.new()
	var em := MeshBuilder.new()
	var paint := MeshBuilder.new()
	var r := U.rng(U.hash_str(icao + "gse"))
	var handler: Color = [Color(0.95, 0.75, 0.1), Color(0.9, 0.9, 0.9), Color(0.15, 0.3, 0.6), Color(0.8, 0.2, 0.1), Color(0.2, 0.45, 0.25)][U.hash_str(icao) % 5]
	var labels := []
	for st in layout.get("stands", []):
		if not bool(st.get("bridge", false)):
			continue
		var nn: Vector2 = (st.normal as Vector2).normalized()
		var left := Vector2(-nn.y, nn.x)
		var fo: Vector2 = st.facade_origin
		var yaw := atan2(nn.x, nn.y)
		# stand frame: +z out from the facade, +x = -left (away from the bridge)
		var basis := Basis(Vector3.UP, yaw)
		var xv := basis * Vector3(1, 0, 0)
		var sgn := 1.0 if Vector2(xv.x, xv.z).dot(-left) > 0.0 else -1.0
		var xf := Transform3D(basis, Vector3(fo.x, 0.0, fo.y))
		var gx := 22.0 * sgn
		mb.xf = xf
		em.xf = xf
		paint.xf = xf
		# equipment parking box (white outline) and the restraint line (red) across the stand
		for e in [[gx, 2.0, gx, 20.0], [gx + 7.0 * sgn, 2.0, gx + 7.0 * sgn, 20.0], [gx, 20.0, gx + 7.0 * sgn, 20.0]]:
			var a := Vector3(float(e[0]), 0.09, float(e[1]))
			var b2 := Vector3(float(e[2]), 0.09, float(e[3]))
			paint.add_box((a + b2) * 0.5, Vector3(maxf(absf(b2.x - a.x), 0.18), 0.01, maxf(absf(b2.z - a.z), 0.18)), Color(0.92, 0.92, 0.9))
		paint.add_box(Vector3(0, 0.09, 24.0), Vector3(30.0, 0.01, 0.2), Color(0.75, 0.12, 0.1))
		var ex := gx + 3.5 * sgn
		# baggage tug and a train of carts
		var z := 4.0
		_tug(mb, Vector3(ex, 0, z), handler)
		for k in 2 + r.randi() % 3:
			z += 3.4
			_cart(mb, Vector3(ex, 0, z), r)
		# belt loader alongside, GPU and pushback tractor near the facade
		_belt_loader(mb, Vector3(ex + 4.5 * sgn, 0, 9.0), handler)
		_gpu(mb, Vector3(gx - 3.0 * sgn, 0, 4.0))
		_pushback(mb, Vector3(gx + 11.5 * sgn, 0, 8.0 + r.randf_range(0.0, 4.0)), handler)
		# cones and chocks
		for cz in [2.5, 3.5]:
			ModelKit.cone(mb, Vector3(gx - 1.0 * sgn, 0.0, cz), Vector3(gx - 1.0 * sgn, 0.7, cz), 0.18, 6, Color(1.0, 0.4, 0.05))
		for k2 in 3:
			var cp := Vector3(-sgn * 4.0 + k2 * 0.7 * sgn, 0.0, 6.0)
			mb.add_box(cp + Vector3(0, 0.1, 0), Vector3(0.4, 0.2, 0.25), Color(0.95, 0.75, 0.1))
		# docking guidance display on the facade above the stand centreline
		var dp := Vector3(0, FLOOR + 6.8, 0.7)
		mb.add_box(dp, Vector3(2.6, 1.9, 0.4), Color(0.08, 0.08, 0.09))
		em.add_box(dp + Vector3(0, 0.2, 0.21), Vector3(2.2, 1.0, 0.02), Color(0.95, 0.65, 0.1))
		em.add_box(dp + Vector3(0, -0.55, 0.21), Vector3(0.18, 0.5, 0.02), Color(0.95, 0.65, 0.1))
		labels.append([String(st.name), xf * (dp + Vector3(0, 1.4, 0.22)), basis * Vector3(0, 0, 1)])
		mb.add_box(dp + Vector3(0, 1.4, 0.0), Vector3(1.6, 0.8, 0.3), Color(0.05, 0.1, 0.25))
	mb.xf = Transform3D.IDENTITY
	em.xf = Transform3D.IDENTITY
	paint.xf = Transform3D.IDENTITY
	if not mb.verts.is_empty():
		var mi := _mi(view, mb, mat, 1600.0, true)
		mi.name = "StandEquipment"
	if not paint.verts.is_empty():
		var pm := _mi(view, paint, mat, 1500.0, false)
		pm.name = "StandPaint"
	if not em.verts.is_empty():
		var emi := _mi(view, em, TerminalInterior.material("emit"), 1800.0, false)
		emi.name = "StandGuidance"
	for lb in labels:
		var l := Label3D.new()
		l.text = String(lb[0])
		l.font_size = 64
		l.pixel_size = 0.6 / 64.0 * 1.4
		l.modulate = Color(1, 1, 1)
		l.double_sided = false
		l.position = lb[1]
		var fwd: Vector3 = lb[2]
		l.basis = Basis.looking_at(-fwd, Vector3.UP)
		l.visibility_range_end = 700.0
		view.add_child(l)


static func _wheels(mb: MeshBuilder, p: Vector3, hx: float, hz: float, rr: float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := p + Vector3(sx * hx, rr, sz * hz)
			ModelKit.cyl(mb, c - Vector3(0.1, 0, 0), c + Vector3(0.1, 0, 0), rr, rr, 8, Color(0.05, 0.05, 0.05))


static func _tug(mb: MeshBuilder, p: Vector3, c: Color) -> void:
	mb.add_box(p + Vector3(0, 0.6, 0), Vector3(1.4, 0.6, 2.4), c)
	mb.add_box(p + Vector3(0, 1.25, 0.3), Vector3(1.3, 0.7, 1.0), Color(0.1, 0.12, 0.14))
	mb.add_box(p + Vector3(0, 1.62, 0.3), Vector3(1.4, 0.06, 1.2), c)
	_wheels(mb, p, 0.65, 0.8, 0.3)


static func _cart(mb: MeshBuilder, p: Vector3, r: RandomNumberGenerator) -> void:
	mb.add_box(p + Vector3(0, 0.45, 0), Vector3(1.4, 0.12, 2.8), Color(0.35, 0.36, 0.38))
	mb.add_box(p + Vector3(0, 1.15, 0), Vector3(1.35, 1.3, 2.6), [Color(0.2, 0.3, 0.55), Color(0.6, 0.62, 0.64), Color(0.15, 0.4, 0.3)][r.randi() % 3])
	if r.randf() < 0.6:
		mb.add_box(p + Vector3(0.05, 0.85, 0), Vector3(1.3, 0.6, 2.2), [Color(0.1, 0.1, 0.12), Color(0.5, 0.15, 0.12), Color(0.2, 0.3, 0.5)][r.randi() % 3])
	_wheels(mb, p, 0.55, 1.0, 0.22)


static func _belt_loader(mb: MeshBuilder, p: Vector3, c: Color) -> void:
	mb.add_box(p + Vector3(0, 0.55, 0), Vector3(1.6, 0.5, 6.0), c)
	mb.add_box_xf(Transform3D(Basis(Vector3.RIGHT, -0.32), p + Vector3(0, 1.6, -0.4)), Vector3(0.9, 0.15, 7.5), Color(0.12, 0.12, 0.13))
	for sx in [-1.0, 1.0]:
		mb.add_box_xf(Transform3D(Basis(Vector3.RIGHT, -0.32), p + Vector3(sx * 0.5, 1.95, -0.4)), Vector3(0.05, 0.05, 7.5), Color(0.85, 0.85, 0.85))
	mb.add_box(p + Vector3(0.45, 1.3, 2.0), Vector3(0.7, 0.9, 1.0), Color(0.1, 0.12, 0.14))
	_wheels(mb, p, 0.75, 2.2, 0.3)


static func _gpu(mb: MeshBuilder, p: Vector3) -> void:
	mb.add_box(p + Vector3(0, 0.95, 0), Vector3(1.4, 1.3, 2.4), Color(0.85, 0.86, 0.87))
	mb.add_box(p + Vector3(0.71, 1.0, 0), Vector3(0.02, 0.8, 1.6), Color(0.3, 0.32, 0.35))
	_wheels(mb, p, 0.6, 0.85, 0.28)


static func _pushback(mb: MeshBuilder, p: Vector3, c: Color) -> void:
	mb.add_box(p + Vector3(0, 0.7, 0), Vector3(2.8, 0.9, 6.0), c)
	mb.add_box(p + Vector3(-0.8, 1.5, -1.6), Vector3(1.0, 0.8, 1.3), Color(0.1, 0.12, 0.14))
	mb.add_box(p + Vector3(0, 0.4, 3.3), Vector3(0.4, 0.3, 1.2), Color(0.25, 0.25, 0.27))
	_wheels(mb, p, 1.3, 1.9, 0.55)
