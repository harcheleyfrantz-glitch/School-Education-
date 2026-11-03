extends Node
## One-shot check after the model upgrade and the long-haul features:
##  - every aircraft type at full and low detail, and every ground vehicle, builds
##    (with triangle counts and build times)
##  - a hub airport loads with its terminals and jet bridges
##  - every landmark builds
##  - a night flight near Iceland runs the new cruise features: position reports, the aurora
##    and the debrief notes
##  - Skyfall Miles credits a trip

func _tris(n: Node) -> int:
	var c := 0
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for ch in list:
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				c += (idx as PackedInt32Array).size() / 3
			else:
				c += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return c


func _ready() -> void:
	Game.settings.quality = "low"
	Game.settings.tts = false
	Engine.time_scale = 4.0
	Geo.init_world()
	var root := Node3D.new()
	add_child(root)
	# ---- aircraft
	for t in AircraftTypes.ORDER:
		var al := "SKF"
		for c in Airlines.all_codes():
			if Airlines.operates_type(String(c), String(t)):
				al = String(c)
				break
		for det in [1.0, 0.4]:
			var m := AircraftModel.new()
			root.add_child(m)
			var t0 := Time.get_ticks_usec()
			m.build(String(t), al, "CR-TST", float(det))
			print("AC %-6s %-4s detail %.1f  %7d tris  %6.1f ms" % [t, al, det, _tris(m), (Time.get_ticks_usec() - t0) / 1000.0])
			root.remove_child(m)
			m.free()
	# ---- vehicles
	for k in ["tug", "tractor", "cart", "uld_dolly", "belt_loader", "fuel_truck", "catering", "stairs", "gpu", "arff", "ambulance", "follow_me", "bus"]:
		var t1 := Time.get_ticks_usec()
		var v := VehicleBuilder.build(k)
		root.add_child(v)
		print("VEH %-12s %6d tris  %5.1f ms" % [k, _tris(v), (Time.get_ticks_usec() - t1) / 1000.0])
		root.remove_child(v)
		v.free()
	# ---- Skyfall Miles
	var ff := Loyalty.earn("KLAX", "RJTT", "business")
	print("MILES +%d -> %s" % [int(ff.miles), Loyalty.summary()])
	for p in [[51.4, 35.7], [67.0, 24.9], [70.0, 48.0], [100.5, 13.7], [-20.0, 50.0]]:
		var w := RealWorld.to_world(float(p[1]), float(p[0]))
		print("BELOW lon %.1f lat %.1f: %s / %s" % [p[0], p[1], LongHaul.country_at(w.x, w.y), LongHaul.continent(w.x, w.y)])
	# ---- flights
	var flights := [
		{"mode": "pilot", "type": "w350", "dep": "EGLL", "arr": "OMDB", "start": "gate", "airline": "BOS", "secs": 12.0,
			"clock": U.date_to_clock(2027, 6, 14, 13.0)},
		{"mode": "pilot", "type": "bj6", "dep": "BIKF", "arr": "BGGH", "start": "air", "alt_ft": 31000.0, "dist_km": 160.0, "airline": "APX", "secs": 90.0,
			"clock": U.date_to_clock(2027, 1, 15, 1.0)},
	]
	for cfg: Dictionary in flights:
		var p := cfg.duplicate()
		p.merge({"reg": "CR-FIN", "callsign": "Skyfall 12", "flight_id": "FIN-" + String(cfg.type), "instant_boarding": true})
		var s := FlightSession.new()
		s.set_meta("test_fast", true)
		add_child(s)
		var msgs := []
		s.toast.connect(func(text, _kind): msgs.append(String(text)))
		var t0 := Time.get_ticks_msec()
		s.start(p)
		print("FLIGHT %s %s %s started in %d ms" % [cfg.type, cfg.dep, cfg.start, Time.get_ticks_msec() - t0])
		var t := 0.0
		while t < float(cfg.secs):
			await get_tree().process_frame
			t += get_process_delta_time()
		var n: Dictionary = s.ac.nav_state() if s.ac else {}
		print("   phase=%s alt=%.0fft ias=%.0f" % [s.phase, float(n.get("alt", 0.0)) / U.FT, float(n.get("ias_kt", 0.0))])
		for mtext in msgs:
			print("   toast: ", String(mtext).left(150))
		if s.longhaul:
			var au: Node = s.longhaul.get("_aurora")
			print("   overflown=%s aurora=%s visible=%s notes=%s" % [str(s.longhaul.overflown), s.longhaul.saw_aurora, au != null and (au as Node3D).visible, str(s.longhaul.debrief_notes())])
		if String(cfg.type) == "w350":
			var lm: Landmarks = s.view.landmarks
			var n_lm := 0
			for l in RealWorld.LANDMARKS:
				if not lm.built.has(String(l.id)):
					var t2 := Time.get_ticks_usec()
					lm._build(l)
					n_lm += 1
					var tri := _tris(lm.built[String(l.id)].root)
					if tri > 60000 or n_lm % 12 == 0:
						print("   landmark %-28s %7d tris  %6.1f ms" % [l.name, tri, (Time.get_ticks_usec() - t2) / 1000.0])
			print("   built %d landmarks" % n_lm)
		remove_child(s)
		s.queue_free()
		for i in 5:
			await get_tree().process_frame
	print("FINAL CHECK DONE")
	get_tree().quit()
