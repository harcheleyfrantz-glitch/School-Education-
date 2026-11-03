extends Node
## One-shot check for the Asia update: new airport elevations and layouts, ultra-long-haul block
## times, every new landmark built, Asian news and comments, and three short flights in Asia.

const NEW := ["RJTT", "RJBB", "RKSI", "ZBAA", "ZSPD", "VHHH", "RCTP", "WSSS", "WMKK", "VTBS", "RPLL", "WIII", "VIDP", "VABB", "OMDB", "OTHH", "LTFM", "HECA", "LGAV", "UUEE"]
const KINDS := ["burj", "petronas", "mbs", "taipei101", "pyramids", "parthenon", "pagoda", "onion_domes"]


func _ready() -> void:
	Game.settings.quality = "low"
	Game.settings.tts = false
	Engine.time_scale = 4.0
	Geo.init_world()
	# ---- elevations and layouts
	var bad := 0
	for icao in NEW:
		var a: Dictionary = Airports.get_ap(icao)
		var hs := []
		for k in 24:
			var ang := TAU * k / 24.0
			var x := float(a.x) + cos(ang) * 6000.0
			var z := float(a.z) + sin(ang) * 6000.0
			if not Geo.is_water(x, z):
				hs.append(Geo.height(x, z))
		hs.sort()
		var med: float = hs[hs.size() / 2] if not hs.is_empty() else 0.0
		var L := AirportLayout.get_layout(icao)
		var msg := ""
		if L.stands.is_empty():
			msg += " NO-STANDS"
		if absf(med - float(a.elev)) > 120.0 and not hs.is_empty():
			msg += " ELEV-DIFF"
		print("AP %s %-18s elev=%4.0f ring=%5.0f land=%2d stands=%2d rw=%d%s" % [icao, String(a.short), float(a.elev), med, hs.size(), L.stands.size(), L.runways.size(), msg])
		if msg != "":
			bad += 1
	print("AIRPORTS WITH PROBLEMS: %d" % bad)
	# ---- ultra long haul
	for pr in [["KLAX", "RJTT", "w390"], ["KJFK", "WSSS", "w390"], ["OMDB", "KLAX", "w380"], ["EGLL", "OMDB", "w350"]]:
		var d := Airports.distance_m(pr[0], pr[1])
		var spec := AircraftTypes.get_type(pr[2])
		print("ROUTE %s-%s %.0f km  %.1f h at %s" % [pr[0], pr[1], d / 1000.0, d / (float(spec.cruise_tas) * U.KT) / 3600.0, pr[2]])
	# ---- news and comments
	var n0 := News.articles.size()
	for day in range(100, 160):
		NewsExtra.daily(day, U.rng(day * 7 + 1))
	var asia := 0
	for art in News.articles:
		if (art.get("tags", []) as Array).has("asia"):
			asia += 1
			if asia <= 3:
				print("NEWS ", art.get("title", "?"))
				for c in NewsComments.page(art, "top", 0, 2):
					print("   > ", String(c.get("text", "")).left(110))
	print("NEWS: %d new articles, %d Asia" % [News.articles.size() - n0, asia])
	# ---- flights in Asia (the world view builds the landmarks near each one)
	var flights := [
		{"mode": "pilot", "type": "q740", "dep": "RJTT", "arr": "WSSS", "start": "gate", "airline": "GOV"},
		{"mode": "pilot", "type": "w380", "dep": "OTHH", "arr": "OMDB", "start": "air", "alt_ft": 3000.0, "dist_km": 14.0, "airline": "DFN"},
		{"mode": "pilot", "type": "s321", "dep": "RCTP", "arr": "VHHH", "start": "air", "alt_ft": 3000.0, "dist_km": 14.0, "airline": "PDA"},
	]
	for cfg: Dictionary in flights:
		var p := cfg.duplicate()
		p.merge({"reg": "CR-ASA", "callsign": "Skyfall 88", "flight_id": "ASIA-" + String(cfg.type), "instant_boarding": true,
			"clock": U.date_to_clock(2027, 8, 2, 15.0)})
		var s := FlightSession.new()
		s.set_meta("test_fast", true)
		add_child(s)
		var t0 := Time.get_ticks_msec()
		s.start(p)
		print("FLIGHT %s %s %s started in %d ms" % [cfg.type, cfg.dep, cfg.start, Time.get_ticks_msec() - t0])
		var t := 0.0
		while t < 24.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		var n: Dictionary = s.ac.nav_state() if s.ac else {}
		var lm: Node = s.view.landmarks if s.get("view") else null
		print("   phase=%s alt=%.0fft ias=%.0f landmarks=%s" % [s.phase, float(n.get("alt", 0.0)) / U.FT, float(n.get("ias_kt", 0.0)), str(lm.built.keys()) if lm else "?"])
		# build every new landmark kind once, to catch errors in the builders
		if lm and cfg.type == "q740":
			for l in RealWorld.LANDMARKS:
				if String(l.kind) in KINDS and not lm.built.has(String(l.id)):
					lm._build(l)
					print("   built %s (%s): %d boxes" % [l.name, l.kind, (lm.built[String(l.id)].boxes as Array).size()])
		remove_child(s)
		s.queue_free()
		for i in 5:
			await get_tree().process_frame
	print("ASIA CHECK DONE")
	get_tree().quit()
