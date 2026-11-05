extends Node
## Debug a gate start: where the player and the parked traffic sit, collisions, and the first
## node whose transform goes non-finite. Usage: -- airline type dep arr mode [flight_id]
var session: FlightSession
var t := 0.0
var reported := false
var frames := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.quality = a[6] if a.size() > 6 else "low"
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.start({"mode": a[4], "type": a[1], "airline": a[0], "reg": "N123DL", "dep": a[2], "arr": a[3], "callsign": "Delta 1942",
		"flight_id": a[5] if a.size() > 5 else "PHONE-2", "start": "gate", "instant_boarding": false, "clock": U.date_to_clock(2027, 6, 14, 10.0)})
	session.toast.connect(func(text, kind): print("TOAST t=%.1f [%s] %s" % [t, kind, text]))
	session.view.origin_shifted.connect(func(sh):
		print("SHIFT t=%.2f by %s -> origin (%.0f, %.0f) ac.position %s fdm %s" % [t, str(sh), session.view.origin_x, session.view.origin_z, str(session.ac.position), str(session.ac.fdm.pos)])
		print_stack())
	Engine.time_scale = 8.0


func _process(delta: float) -> void:
	t += delta
	frames += 1
	if frames == 3 or frames == 40:
		_dump()
	if frames % 3 == 0 and t < 5.0:
		var cam := get_viewport().get_camera_3d()
		print("CAM t=%.2f %s at %s view.camera=%s" % [t, str(cam.get_path()) if cam else "none", str(cam.global_position) if cam else "-", str(session.view.camera.get_path()) if session.view.camera else "null"])
	if frames % 15 == 0 and t < 14.0:
		var f := session.ac.fdm
		print("AC t=%.1f pos %s vel %s pitch %.1f hdg %.1f gear_contact %s" % [t, str(f.pos), str(f.vel), session.ac.fdm.pitch_deg(), f.heading_deg(), str(session.ac.fdm.on_ground)])
	if frames % 5 == 0 and not reported:
		var bad := _find_bad(session)
		if bad != "":
			reported = true
			print("NONFINITE at t=%.1f: %s" % [t, bad])
	if frames == 60:
		# no two parked aircraft (or a parked one and the player) may overlap
		var fps := []
		for item in session.traffic.parked:
			fps.append([String(item.stand), AirportLayout.parked_footprint(item.sd, AircraftTypes.get_type(String(item.type)))])
		var L := AirportLayout.get_layout(session.dep_icao)
		fps.append(["PLAYER " + session.stand, AirportLayout.parked_footprint(AirportLayout.stand_by_name(L, session.stand), session.ac.spec)])
		var clashes := 0
		for i in fps.size():
			for j in range(i + 1, fps.size()):
				if AirportLayout.footprints_clash(fps[i][1], fps[j][1]):
					clashes += 1
					print("OVERLAP %s / %s" % [fps[i][0], fps[j][0]])
		print("PARKED %d aircraft, overlaps %d" % [session.traffic.parked.size(), clashes])
	if t > 120.0:
		print("DEBUG done t=%.0f reported=%s ac=%s" % [t, reported, str(session.ac.fdm.pos)])
		get_tree().quit()


func _dump() -> void:
	var ap: Dictionary = Airports.get_ap(session.dep_icao)
	var me := Vector2(session.ac.world_x() - float(ap.x), session.ac.world_z() - float(ap.z))
	print("PLAYER stand %s at (%.1f, %.1f) hdg %.0f type %s" % [session.stand, me.x, me.y, session.ac.fdm.heading_deg(), session.ac.type_id])
	var L := AirportLayout.get_layout(session.dep_icao)
	var sd := AirportLayout.stand_by_name(L, session.stand)
	print("  stand data stop %s hdg %.0f max_span %.0f pose %s" % [str(sd.get("stop")), float(sd.get("hdg", 0)), float(sd.get("max_span", 0)), str(session._stand_pose(sd))])
	for item in session.traffic.parked:
		var m = item.get("model")
		var pos := Vector2(float(item.get("x", 0.0)) - float(ap.x), float(item.get("z", 0.0)) - float(ap.z))
		if pos.distance_to(me) < 150.0:
			print("  parked %s %s at (%.1f, %.1f) %.0f m away, model %s" % [item.stand, item.type, pos.x, pos.y, pos.distance_to(me), "yes" if m != null else "no"])


func _find_bad(n: Node) -> String:
	if n is Node3D:
		var xf: Transform3D = (n as Node3D).transform
		if not (xf.origin.is_finite() and xf.basis.x.is_finite() and xf.basis.y.is_finite() and xf.basis.z.is_finite()):
			return str(n.get_path())
	for c in n.get_children():
		var r := _find_bad(c)
		if r != "":
			return r
	return ""
