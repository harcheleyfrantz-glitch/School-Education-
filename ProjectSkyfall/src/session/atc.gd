class_name AtcController
extends Node
## Air traffic control for the player's flight. Walks through delivery, ground, tower,
## departure, centre and approach; offers response options (correct and incorrect readbacks,
## requests, emergencies); reacts to readbacks; monitors deviations; adds background traffic.

signal transmission(station: String, who: String, text: String)
signal options_changed(options: Array)
signal deviation(kind: String, severity: float, text: String)
signal cleared(kind: String)

const TRANSITION_FT := 5000.0

var session: Node
var ac: Aircraft
var callsign := "Skyfall 123"
var spoken_cs := ""
var dep := ""
var arr := ""
var dep_end: Dictionary = {}
var arr_end: Dictionary = {}
var stand := ""
var arr_stand := ""
var cruise_m := 9000.0
var route: Array = []
var vfr := false
var squawk := "4521"
var station := "DEL"
var state := "delivery"
var _spd_t := 0.0
var _desc_verb := "descend"
var _vec_verb := "descend"
var _alt_clr_last := -1.0
var _alt_clr_t := 0.0
var clearance := {"alt_m": 0.0, "hdg": -1.0, "takeoff": false, "landing": false, "lineup": false, "taxi": false,
	"pushback": false, "approach": false}
var options: Array = []
var queue: Array = []          # pending transmissions {t, station, who, text, spoken, then}
var transcript: Array = []
var emergency := ""
var awaiting := ""             # clearance id waiting for a readback
var expect_rb := {}            # key items of the expected readback
var silence_t := 0.0
var _t := 0.0
var _chatter_t := 30.0
var _dev_cool := {}
var _rng := RandomNumberGenerator.new()
var _voice_ids := {}
var auto_atc := false
var go_around_issued := false
var vector_hdg := -1.0
var _vector_t := 0.0
var spoken := true
var _opt_timer := 0.0
var _auto_pending := ""
var _last_choice := ""
var _last_choice_t := -100.0


func setup(sess: Node, aircraft: Aircraft, params: Dictionary) -> void:
	session = sess
	ac = aircraft
	callsign = String(params.get("callsign", "Skyfall 123"))
	spoken_cs = Phraseology.callsign_spoken(callsign)
	dep = params.dep
	arr = params.arr
	dep_end = params.dep_end
	arr_end = params.arr_end
	stand = String(params.get("stand", ""))
	arr_stand = String(params.get("arr_stand", ""))
	cruise_m = float(params.get("cruise_m", 9000.0))
	route = params.get("route", [])
	vfr = ac.spec.category == "trainer"
	auto_atc = bool(params.get("auto", Game.settings.get("auto_atc", false)))
	_rng.seed = U.hash_str(callsign + str(WorldSim.clock))
	squawk = "%d%d%d%d" % [_rng.randi_range(1, 6), _rng.randi_range(0, 7), _rng.randi_range(0, 7), _rng.randi_range(0, 7)]
	_pick_voices()
	if params.get("start", "gate") == "runway":
		state = "holding"
		station = "TWR"
		clearance.taxi = true
	elif params.get("start", "gate") == "air":
		state = "cruise"
		station = "CTR"
		clearance.alt_m = ac.fdm.pos.y
	_refresh_options()


# ---------------------------------------------------------------- names and frequencies
func _ap_freq(icao: String, kind: String) -> String:
	var f: Dictionary = Airports.get_ap(icao).get("freq", {})
	return String(f.get(kind, "121.500"))


func station_name(st: String) -> String:
	var city: String = Airports.get_ap(dep).short
	var acity: String = Airports.get_ap(arr).short
	match st:
		"DEL": return city + " Delivery"
		"GND": return city + " Ground"
		"TWR": return city + " Tower"
		"DEP": return city + " Departure"
		"CTR": return "Calderra Control"
		"APP": return acity + " Approach"
		"ATWR": return acity + " Tower"
		"AGND": return acity + " Ground"
	return st


func station_freq(st: String) -> String:
	match st:
		"DEL": return _ap_freq(dep, "del")
		"GND": return _ap_freq(dep, "gnd")
		"TWR": return _ap_freq(dep, "twr")
		"DEP": return _ap_freq(dep, "dep")
		"CTR": return "132.600"
		"APP": return _ap_freq(arr, "app")
		"ATWR": return _ap_freq(arr, "twr")
		"AGND": return _ap_freq(arr, "gnd")
	return "121.500"


func _pick_voices() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		spoken = false
		return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		spoken = false
		return
	var st := ["DEL", "GND", "TWR", "DEP", "CTR", "APP", "ATWR", "AGND", "PILOT", "OTHER"]
	for i in st.size():
		_voice_ids[st[i]] = voices[(i * 3 + U.hash_str(dep)) % voices.size()]


# ---------------------------------------------------------------- transmissions
func _say(st: String, text: String, spoken_text: String, delay: float = 1.6, then: String = "") -> void:
	for q in queue:
		if String(q.text) == text:
			return      # already waiting to be said
	queue.append({"t": _t + delay + _rng.randf_range(0.0, 1.2), "station": st, "who": "atc", "text": text, "spoken": spoken_text, "then": then})


func _pilot(text: String, spoken_text: String = "") -> void:
	_emit(station, "pilot", text, spoken_text if spoken_text != "" else text)


func _emit(st: String, who: String, text: String, spoken_text: String, speaker: String = "") -> void:
	var entry := {"t": WorldSim.clock, "station": station_name(st) if who == "atc" else (speaker if speaker != "" else callsign), "who": who, "text": text}
	transcript.append(entry)
	transmission.emit(entry.station, who, text)
	if spoken and Game.settings.get("tts", true):
		var vkey := st if who == "atc" else ("PILOT" if who == "pilot" else "OTHER")
		var vol := int(clampf(float(Game.settings.get("voice_volume", 1.0)) * float(Game.settings.get("master_volume", 0.85)) * 100.0, 0.0, 100.0))
		DisplayServer.tts_speak(spoken_text, String(_voice_ids.get(vkey, "")), vol, 1.0 if who != "pilot" else 0.95, 1.12)
	silence_t = 0.0


func choose(opt_id: String) -> void:
	_auto_pending = ""
	_last_choice = opt_id
	_last_choice_t = _t
	## Called by the UI (or the auto copilot) with one of the current option ids.
	for o in options:
		if o.id == opt_id:
			_pilot(String(o.text), String(o.get("spoken", o.text)))
			_handle(o)
			return


# ---------------------------------------------------------------- state machine
func _opt(id: String, label: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "label": label, "text": text}
	d.merge(extra, true)
	return d


func _lvl(alt_m: float) -> Array:
	return Phraseology.level_text(alt_m)


func _refresh_options() -> void:
	options.clear()
	var cs := callsign
	match state:
		"delivery":
			if vfr:
				options.append(_opt("req_taxi_vfr", "Request taxi (VFR)", "%s, %s, at %s, VFR local flight, request taxi." % [station_name("GND"), cs, stand]))
			else:
				options.append(_opt("req_clr", "Request IFR clearance", "%s, %s, stand %s, request IFR clearance to %s." % [station_name("DEL"), cs, stand, Airports.get_ap(arr).short]))
		"clr_rb":
			var l := _lvl(clearance.alt_m)
			options.append(_opt("rb_ok", "Read back", "Cleared to %s, runway %s, climb %s, squawk %s, %s." % [Airports.get_ap(arr).short, dep_end.name, l[0], squawk, cs], {"correct": true}))
			var wrong_sq := squawk.substr(0, 2) + squawk.substr(3, 1) + squawk.substr(2, 1)
			options.append(_opt("rb_bad", "Read back (squawk %s)" % wrong_sq, "Cleared to %s, runway %s, climb %s, squawk %s, %s." % [Airports.get_ap(arr).short, dep_end.name, l[0], wrong_sq, cs], {"correct": false, "fix": "squawk %s" % squawk}))
			options.append(_opt("say_again", "Say again", "Say again, %s." % cs))
		"ground_push":
			options.append(_opt("req_push", "Request pushback & start", "%s, %s, stand %s, request pushback and start-up." % [station_name("GND"), cs, stand]))
		"push_rb":
			options.append(_opt("rb_ok", "Read back", "Pushback and start-up approved, %s." % cs, {"correct": true}))
		"pushing":
			if session.get("pushback_done") and ac.sys.running_engines() > 0:
				options.append(_opt("req_taxi", "Request taxi", "%s, request taxi." % cs))
		"taxi_rb":
			options.append(_opt("rb_ok", "Read back", "Taxi holding point runway %s via %s, hold short runway %s, %s." % [dep_end.name, String(expect_rb.get("route", "")), dep_end.name, cs], {"correct": true}))
			options.append(_opt("rb_bad", "Read back (cross runway)", "Taxi via %s, cross runway %s, %s." % [String(expect_rb.get("route", "")), dep_end.name, cs], {"correct": false, "fix": "hold short runway %s" % dep_end.name}))
		"taxiing":
			options.append(_opt("ready_dep", "Ready for departure", "%s, %s, holding point runway %s, ready for departure." % [station_name("TWR"), cs, dep_end.name], {"station": "TWR"}))
		"lineup_rb":
			options.append(_opt("rb_ok", "Read back", "Line up and wait runway %s, %s." % [dep_end.name, cs], {"correct": true}))
		"to_rb":
			options.append(_opt("rb_ok", "Read back", "Cleared for takeoff runway %s, %s." % [dep_end.name, cs], {"correct": true}))
		"airborne_twr":
			pass
		"dep_contact":
			options.append(_opt("checkin_dep", "Check in with Departure", "%s, %s, passing %s, climbing %s." % [station_name("DEP"), cs, _lvl(ac.fdm.pos.y)[0], _lvl(clearance.alt_m)[0]], {"station": "DEP"}))
		"climb_rb":
			options.append(_opt("rb_ok", "Read back", "Climb %s, %s." % [_lvl(clearance.alt_m)[0], cs], {"correct": true}))
			options.append(_opt("rb_bad", "Read back (wrong level)", "Climb %s, %s." % [_lvl(clearance.alt_m + 610.0)[0], cs], {"correct": false, "fix": "climb %s" % _lvl(clearance.alt_m)[0]}))
		"ctr_contact":
			options.append(_opt("checkin_ctr", "Check in with Control", "%s, %s, climbing %s." % [station_name("CTR"), cs, _lvl(clearance.alt_m)[0]], {"station": "CTR"}))
		"cruise":
			options.append(_opt("req_descent", "Request descent", "%s, request descent." % cs))
		"desc_rb":
			options.append(_opt("rb_ok", "Read back", "%s %s, expect ILS runway %s, %s." % [_desc_verb.capitalize(), _lvl(clearance.alt_m)[0], arr_end.name, cs], {"correct": true}))
		"app_contact":
			options.append(_opt("checkin_app", "Check in with Approach", "%s, %s, %s %s, information received." % [station_name("APP"), cs, {"descend": "descending", "climb": "climbing"}.get(_desc_verb, "maintaining"), _lvl(clearance.alt_m)[0]], {"station": "APP"}))
		"vec_rb":
			options.append(_opt("rb_ok", "Read back", "%s %s, %s, %s." % [_vec_verb.capitalize(), _lvl(clearance.alt_m)[0], Phraseology.heading(vector_hdg), cs], {"correct": true}))
		"app_clr_rb":
			options.append(_opt("rb_ok", "Read back", "%s, cleared ILS approach runway %s, %s." % [Phraseology.heading(vector_hdg), arr_end.name, cs], {"correct": true}))
		"twr_contact":
			options.append(_opt("checkin_twr", "Check in with Tower", "%s, %s, established ILS runway %s." % [station_name("ATWR"), cs, arr_end.name], {"station": "ATWR"}))
		"land_rb":
			options.append(_opt("rb_ok", "Read back", "Cleared to land runway %s, %s." % [arr_end.name, cs], {"correct": true}))
		"ga_rb":
			options.append(_opt("rb_ok", "Read back", "Going around, climb 3000 feet, %s." % cs, {"correct": true}))
		"vacated":
			options.append(_opt("checkin_gnd", "Contact Ground", "%s, %s, runway vacated." % [station_name("AGND"), cs], {"station": "AGND"}))
		"taxi_in_rb":
			options.append(_opt("rb_ok", "Read back", "Taxi to stand %s via %s, %s." % [arr_stand, String(expect_rb.get("route", "")), cs], {"correct": true}))
	# requests always available in flight
	if not ac.fdm.on_ground:
		if emergency == "":
			options.append(_opt("mayday", "Declare MAYDAY", "MAYDAY, MAYDAY, MAYDAY, %s, %s, request immediate return / nearest suitable airport." % [station_name(station), cs], {"kind": "emergency"}))
			options.append(_opt("pan", "Declare PAN-PAN", "PAN-PAN, PAN-PAN, PAN-PAN, %s, %s, request priority." % [station_name(station), cs], {"kind": "emergency"}))
		if state in ["cruise", "ctr_contact"]:
			options.append(_opt("req_higher", "Request higher", "%s, request %s." % [cs, _lvl(clearance.alt_m + 610.0)[0]]))
			options.append(_opt("req_lower", "Request lower (ride)", "%s, moderate turbulence, request %s." % [cs, _lvl(clearance.alt_m - 610.0)[0]]))
	if state.ends_with("_rb") or state in ["climb_rb"]:
		if not options.any(func(o): return o.id == "say_again"):
			options.append(_opt("say_again", "Say again", "Say again, %s." % cs))
	options_changed.emit(options)
	if auto_atc and not options.is_empty():
		for o in options:
			if o.get("correct", false) or (String(o.id).begins_with("checkin") or String(o.id) in ["req_clr", "req_push", "req_taxi", "ready_dep", "req_taxi_vfr"]):
				var pick := String(o.id)
				# the crew only calls ready once they reach the holding point
				if pick == "ready_dep" and session.has_method("near_holding_point") and not bool(session.call("near_holding_point")):
					continue
				if _auto_pending == pick or (pick == _last_choice and _t - _last_choice_t < 25.0):
					break
				_auto_pending = pick
				get_tree().create_timer(2.0).timeout.connect(func():
					if _auto_pending == pick and options.any(func(x): return x.id == pick):
						choose(pick))
				break


func _handle(o: Dictionary) -> void:
	var id := String(o.id)
	var cs := callsign
	if o.has("station"):
		station = String(o.station)
	if id == "say_again":
		_repeat_last()
		return
	if id == "mayday" or id == "pan":
		_declare_emergency(id)
		return
	if id.begins_with("rb_"):
		if not o.get("correct", false):
			_say(station, "%s, negative, %s." % [cs, String(o.get("fix", "I say again"))], "%s, negative, %s." % [spoken_cs, String(o.get("fix", "I say again"))])
			_deviate("readback", 0.1, "Incorrect readback")
			return
		_readback_ok()
		return
	match id:
		"req_clr":
			station = "DEL"
			clearance.alt_m = 1524.0
			var l := _lvl(clearance.alt_m)
			var sid := String(route[0].name) + " 1" if not route.is_empty() else "radar vectors"
			_say("DEL", "%s, cleared to %s via %s departure, runway %s, climb %s, squawk %s." % [cs, Airports.get_ap(arr).short, sid, dep_end.name, l[0], squawk],
				"%s, cleared to %s via %s departure, %s, climb %s, %s." % [spoken_cs, Airports.get_ap(arr).short, sid, Phraseology.runway(dep_end.name), l[1], Phraseology.squawk(squawk)], 2.0, "clr_rb")
			ac.sys.squawk = squawk
		"req_taxi_vfr":
			station = "GND"
			_issue_taxi()
		"req_push":
			station = "GND"
			var face := _push_face_text()
			_say("GND", "%s, pushback and start-up approved, %s." % [cs, face], "%s, pushback and start up approved, %s." % [spoken_cs, face], 2.0, "push_rb")
		"req_taxi":
			station = "GND"
			_issue_taxi()
		"ready_dep":
			_tower_departure()
		"checkin_dep":
			clearance.alt_m = minf(cruise_m, 7315.0)
			var wp := String(route[0].name) if not route.is_empty() else ""
			var l2 := _lvl(clearance.alt_m)
			_say("DEP", "%s, radar contact, climb %s%s." % [cs, l2[0], (", proceed direct " + wp) if wp != "" else ""],
				"%s, radar contact, climb %s%s." % [spoken_cs, l2[1], (", proceed direct " + wp) if wp != "" else ""], 2.0, "climb_rb")
		"checkin_ctr":
			clearance.alt_m = cruise_m
			var l3 := _lvl(clearance.alt_m)
			_say("CTR", "%s, %s, climb %s." % [cs, station_name("CTR"), l3[0]], "%s, Calderra Control, climb %s." % [spoken_cs, l3[1]], 2.0, "climb_rb")
		"req_descent":
			_issue_descent()
		"req_higher":
			var hi = clearance.alt_m + 610.0
			if hi < float(ac.spec.ceiling) * U.FT:
				clearance.alt_m = hi
				_say(station, "%s, climb %s." % [cs, _lvl(hi)[0]], "%s, climb %s." % [spoken_cs, _lvl(hi)[1]], 2.0, "climb_rb")
			else:
				_say(station, "%s, unable, maintain %s." % [cs, _lvl(clearance.alt_m)[0]], "%s, unable, maintain %s." % [spoken_cs, _lvl(clearance.alt_m)[1]])
		"req_lower":
			clearance.alt_m = maxf(clearance.alt_m - 610.0, 3000.0)
			_say(station, "%s, descend %s." % [cs, _lvl(clearance.alt_m)[0]], "%s, descend %s." % [spoken_cs, _lvl(clearance.alt_m)[1]], 2.0, "climb_rb")
		"checkin_app":
			var elev := float(arr_end.elev)
			clearance.alt_m = elev + 914.0
			vector_hdg = _vector_heading()
			_vec_verb = _alt_verb(clearance.alt_m)
			var qnh := int(round(float(ac.weather.get("qnh", 1013.0))))
			var l4 := _lvl(clearance.alt_m)
			_say("APP", "%s, %s, %s %s QNH %d, turn %s, vectors ILS runway %s." % [cs, station_name("APP"), _vec_verb, l4[0], qnh, Phraseology.heading(vector_hdg), arr_end.name],
				"%s, %s, %s %s, QNH %s, turn %s, vectors I L S %s." % [spoken_cs, station_name("APP"), _vec_verb, l4[1], Phraseology.digits(str(qnh)), Phraseology.heading(vector_hdg), Phraseology.runway(arr_end.name)], 2.0, "vec_rb")
		"checkin_twr":
			_tower_landing()
		"checkin_gnd":
			_issue_taxi_in()
	_set_state_waiting()


func _set_state_waiting() -> void:
	# while a reply is pending the options collapse to nothing
	options.clear()
	options_changed.emit(options)


func _repeat_last() -> void:
	for i in range(transcript.size() - 1, -1, -1):
		if transcript[i].who == "atc":
			_say(station, "%s, I say again: %s" % [callsign, String(transcript[i].text)], "I say again, " + String(transcript[i].text), 1.5)
			return


func _readback_ok() -> void:
	match state:
		"clr_rb":
			_say("DEL", "%s, readback correct, contact Ground %s for push." % [callsign, station_freq("GND")], "%s, readback correct, contact ground %s." % [spoken_cs, Phraseology.freq(station_freq("GND"))], 1.5, "ground_push")
		"push_rb":
			clearance.pushback = true
			cleared.emit("pushback")
			_goto("pushing")
		"taxi_rb":
			clearance.taxi = true
			cleared.emit("taxi")
			_goto("taxiing")
		"lineup_rb":
			clearance.lineup = true
			cleared.emit("lineup")
			_goto("lineup_wait")
		"to_rb":
			clearance.takeoff = true
			cleared.emit("takeoff")
			_goto("takeoff_roll")
		"climb_rb":
			cleared.emit("altitude")
			_goto("climbing" if ac.fdm.pos.y < clearance.alt_m - 300.0 else "cruise")
		"desc_rb":
			cleared.emit("altitude")
			_goto("descending")
		"vec_rb":
			cleared.emit("vectors")
			_goto("vectors")
		"app_clr_rb":
			clearance.approach = true
			cleared.emit("approach")
			_goto("established")
		"land_rb":
			clearance.landing = true
			cleared.emit("landing")
			_goto("landing")
		"ga_rb":
			cleared.emit("go_around")
			go_around_issued = false
			_goto("vectors")
		"taxi_in_rb":
			_goto("taxi_in")


func _goto(s: String) -> void:
	state = s
	awaiting = ""
	_refresh_options()


# ---------------------------------------------------------------- clearances
func _push_face_text() -> String:
	var sd: Dictionary = AirportLayout.stand_by_name(AirportLayout.get_layout(dep), stand)
	if sd.is_empty():
		return "face west"
	var n: Vector2 = sd.normal
	var away := rad_to_deg(atan2(n.x, -n.y))
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return "face " + String(dirs[int(round(fposmod(away + 90.0, 360.0) / 45.0)) % 8])


func _issue_taxi() -> void:
	var L := AirportLayout.get_layout(dep)
	var p := Vector2(ac.world_x() - float(Airports.get_ap(dep).x), ac.world_z() - float(Airports.get_ap(dep).z))
	var from := AirportLayout.nearest_node(L, p, ["apron", "stand", "taxi"])
	var to := AirportLayout.hold_node_for(L, String(dep_end.name))
	var path := AirportLayout.find_path(L, from, to)
	var names := Phraseology.taxi_route(AirportLayout.route_names(path))
	if names == "":
		names = "A"
	expect_rb = {"route": names}
	session.set("taxi_path", path)
	_say("GND", "%s, taxi to holding point runway %s via %s, hold short runway %s." % [callsign, dep_end.name, names, dep_end.name],
		"%s, taxi to holding point %s via %s, hold short %s." % [spoken_cs, Phraseology.runway(dep_end.name), Phraseology.spoken_route(names), Phraseology.runway(dep_end.name)], 2.0, "taxi_rb")


func _issue_taxi_in() -> void:
	var L := AirportLayout.get_layout(arr)
	var ap: Dictionary = Airports.get_ap(arr)
	var p := Vector2(ac.world_x() - float(ap.x), ac.world_z() - float(ap.z))
	var from := AirportLayout.nearest_node(L, p, ["taxi", "hold", "apron"])
	var sd := AirportLayout.stand_by_name(L, arr_stand)
	if sd.is_empty() and not L.stands.is_empty():
		sd = L.stands[0]
		arr_stand = sd.name
	var path := AirportLayout.find_path(L, from, int(sd.get("node", from)))
	var names := Phraseology.taxi_route(AirportLayout.route_names(path))
	if names == "":
		names = "A"
	expect_rb = {"route": names}
	session.set("taxi_path", path)
	_say("AGND", "%s, taxi to stand %s via %s." % [callsign, arr_stand, names],
		"%s, taxi to stand %s via %s." % [spoken_cs, Phraseology.digits(arr_stand), Phraseology.spoken_route(names)], 2.0, "taxi_in_rb")


func _tower_departure() -> void:
	station = "TWR"
	var w := Phraseology.wind(float(ac.weather.get("wind_dir", 0.0)), float(ac.weather.get("wind_kt", 0.0)))
	var landing_traffic := bool(session.call("runway_traffic_soon", dep, 90.0)) if session.has_method("runway_traffic_soon") else false
	if landing_traffic and not clearance.lineup:
		_say("TWR", "%s, line up and wait runway %s, traffic on short final." % [callsign, dep_end.name], "%s, line up and wait %s." % [spoken_cs, Phraseology.runway(dep_end.name)], 2.0, "lineup_rb")
		return
	_say("TWR", "%s, %s, runway %s, cleared for takeoff." % [callsign, w[0], dep_end.name], "%s, %s, %s, cleared for take off." % [spoken_cs, w[1], Phraseology.runway(dep_end.name)], 2.0, "to_rb")


func _alt_verb(target_m: float) -> String:
	var cur := ac.fdm.pos.y
	return "climb" if target_m > cur + 60.0 else ("descend" if target_m < cur - 60.0 else "maintain")


func _issue_descent() -> void:
	station = "CTR"
	# FL120, or the next thousand feet below us when we are already lower (airborne starts, low
	# cruise); never below the initial approach altitude, and never a "descent" upwards
	var cur := ac.fdm.pos.y
	var below := floorf((cur - 150.0) / 304.8) * 304.8
	clearance.alt_m = maxf(minf(3658.0, below), float(arr_end.elev) + 914.0)
	if clearance.alt_m > cur - 60.0:
		clearance.alt_m = snappedf(cur, 30.48)
	_desc_verb = _alt_verb(clearance.alt_m)
	_say("CTR", "%s, %s %s, expect ILS runway %s at %s." % [callsign, _desc_verb, _lvl(clearance.alt_m)[0], arr_end.name, Airports.get_ap(arr).short],
		"%s, %s %s, expect I L S %s." % [spoken_cs, _desc_verb, _lvl(clearance.alt_m)[1], Phraseology.runway(arr_end.name)], 2.0, "desc_rb")


func _tower_landing() -> void:
	station = "ATWR"
	var w := Phraseology.wind(float(ac.weather.get("wind_dir", 0.0)), float(ac.weather.get("wind_kt", 0.0)))
	var occupied := bool(session.call("runway_occupied", arr)) if session.has_method("runway_occupied") else false
	if occupied:
		_say("ATWR", "%s, continue approach, one departure ahead." % callsign, "%s, continue approach, one departure ahead." % spoken_cs, 2.0)
		state = "continue_app"
		return
	_say("ATWR", "%s, %s, runway %s, cleared to land." % [callsign, w[0], arr_end.name], "%s, %s, %s, cleared to land." % [spoken_cs, w[1], Phraseology.runway(arr_end.name)], 2.0, "land_rb")


func _vector_heading() -> float:
	# downwind-ish heading towards a point 18 km out on the extended centreline
	var d := Vector2(sin(deg_to_rad(arr_end.hdg)), -cos(deg_to_rad(arr_end.hdg)))
	var faf := Vector2(arr_end.thr_x, arr_end.thr_z) - d * 18000.0
	var to := faf - Vector2(ac.world_x(), ac.world_z())
	var h := rad_to_deg(atan2(to.x, -to.y))
	return snappedf(fposmod(h, 360.0), 10.0)


func _declare_emergency(kind: String) -> void:
	emergency = kind
	var nearest := Airports.nearest(ac.world_x(), ac.world_z(), "", float(ac.spec.get("min_runway", 1200.0)))
	if session.has_method("on_emergency_declared"):
		session.call("on_emergency_declared", kind, nearest)
	var word := "Mayday" if kind == "mayday" else "Pan-pan"
	_say(station, "%s, %s, %s acknowledged. Turn %s for %s, descend at your discretion. Say souls on board and fuel remaining. Emergency services are alerted." % [callsign, station_name(station), word, Phraseology.heading(_heading_to(nearest)), Airports.get_ap(nearest).short],
		"%s, %s acknowledged, turn %s for %s, descend at your discretion. Say souls on board and fuel remaining." % [spoken_cs, word, Phraseology.heading(_heading_to(nearest)), Airports.get_ap(nearest).short], 2.5)


func _heading_to(icao: String) -> float:
	var ap: Dictionary = Airports.get_ap(icao)
	var to := Vector2(float(ap.x) - ac.world_x(), float(ap.z) - ac.world_z())
	return fposmod(rad_to_deg(atan2(to.x, -to.y)), 360.0)


func issue_go_around(reason: String) -> void:
	if go_around_issued:
		return
	go_around_issued = true
	station = "ATWR"
	clearance.landing = false
	clearance.alt_m = float(arr_end.elev) + 914.0
	_say("ATWR", "%s, go around, I say again, go around, climb 3000 feet, %s." % [callsign, reason], "%s, go around, I say again, go around, climb three thousand feet, %s." % [spoken_cs, reason], 0.8, "ga_rb")


# ---------------------------------------------------------------- per-frame logic
func _process(delta: float) -> void:
	if ac == null:
		return
	_t += delta
	silence_t += delta
	# deliver queued transmissions
	for i in range(queue.size() - 1, -1, -1):
		var q: Dictionary = queue[i]
		if _t >= float(q.t):
			queue.remove_at(i)
			_emit(String(q.station), "atc", String(q.text), String(q.spoken))
			if String(q.then) != "":
				_goto(String(q.then))
	if ac.crashed_state:
		return
	_opt_timer -= delta
	if _opt_timer <= 0.0 and (state in ["pushing", "taxiing", "cruise"] or (auto_atc and queue.is_empty())):
		_opt_timer = 1.5
		var before := options.size()
		_refresh_options()
		if options.size() == before:
			pass
	_auto_progress(delta)
	_monitor(delta)
	_chatter(delta)


func _auto_progress(delta: float) -> void:
	var n := ac.nav_state()
	var agl: float = ac.ra
	match state:
		"takeoff_roll":
			if not ac.fdm.on_ground and agl > 300.0:
				_say("TWR", "%s, contact Departure %s, good day." % [callsign, station_freq("DEP")], "%s, contact departure %s, good day." % [spoken_cs, Phraseology.freq(station_freq("DEP"))], 1.0, "dep_contact")
				state = "airborne_twr"
		"climbing":
			if n.alt > 4500.0 and station == "DEP" and cruise_m > 5000.0:
				_say("DEP", "%s, contact Calderra Control %s." % [callsign, station_freq("CTR")], "%s, contact Calderra Control %s." % [spoken_cs, Phraseology.freq(station_freq("CTR"))], 1.0, "ctr_contact")
				state = "handoff"
			elif absf(n.alt - clearance.alt_m) < 150.0 and clearance.alt_m >= cruise_m - 1.0:
				_goto("cruise")
		"cruise":
			var dist := U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z)
			var need := (float(n.alt) - float(arr_end.elev) - 900.0) / tan(deg_to_rad(3.0)) + 25000.0
			if dist < need and not vfr:
				_issue_descent()
				state = "desc_pending"
		"descending":
			if n.alt < 4600.0 or U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z) < 60000.0:
				_say("CTR", "%s, contact %s %s." % [callsign, station_name("APP"), station_freq("APP")], "%s, contact %s %s." % [spoken_cs, station_name("APP"), Phraseology.freq(station_freq("APP"))], 1.0, "app_contact")
				state = "handoff"
		"vectors":
			_vector_t += delta
			var dist2 := U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z)
			var d := Vector2(sin(deg_to_rad(arr_end.hdg)), -cos(deg_to_rad(arr_end.hdg)))
			var rel := Vector2(n.x - arr_end.thr_x, n.z - arr_end.thr_z)
			var along := -rel.dot(d)
			if (along > 9000.0 and dist2 < 32000.0 and _vector_t > 20.0) or _vector_t > 240.0:
				vector_hdg = fposmod(float(arr_end.hdg) + (30.0 if rel.dot(Vector2(-d.y, d.x)) < 0.0 else -30.0), 360.0)
				_say("APP", "%s, turn %s, cleared ILS approach runway %s." % [callsign, Phraseology.heading(vector_hdg), arr_end.name], "%s, turn %s, cleared I L S approach %s." % [spoken_cs, Phraseology.heading(vector_hdg), Phraseology.runway(arr_end.name)], 1.0, "app_clr_rb")
				state = "clr_pending"
		"established":
			var dist3 := U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z)
			if (ac.ap.lat_mode == "LOC" or absf(ac.ap.loc_dev) < 1.0) and dist3 < 16000.0:
				_say("APP", "%s, contact %s %s." % [callsign, station_name("ATWR"), station_freq("ATWR")], "%s, contact tower %s." % [spoken_cs, Phraseology.freq(station_freq("ATWR"))], 1.0, "twr_contact")
				state = "handoff"
		"continue_app":
			var dist4 := U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z)
			var occ := bool(session.call("runway_occupied", arr)) if session.has_method("runway_occupied") else false
			if not occ:
				_tower_landing()
			elif dist4 < 1500.0:
				issue_go_around("runway occupied")
		"landing":
			if ac.fdm.on_ground and ac.fdm.ground_speed() < 25.0:
				_say("ATWR", "%s, vacate when able, contact Ground %s." % [callsign, station_freq("AGND")], "%s, vacate when able, contact ground %s." % [spoken_cs, Phraseology.freq(station_freq("AGND"))], 1.0, "vacated")
				state = "handoff"
		"lineup_wait":
			var traffic := bool(session.call("runway_traffic_soon", dep, 25.0)) if session.has_method("runway_traffic_soon") else false
			if not traffic and silence_t > 8.0:
				_tower_departure()
				state = "to_pending"


# ---------------------------------------------------------------- deviations
func _deviate(kind: String, severity: float, text: String) -> bool:
	## Reports a deviation at most once a minute per kind; true when it was reported (and the
	## controller should say something about it).
	if float(_dev_cool.get(kind, -1000.0)) > _t - 60.0:
		return false
	_dev_cool[kind] = _t
	deviation.emit(kind, severity, text)
	return true


func _monitor(delta: float) -> void:
	var n := ac.nav_state()
	if emergency != "":
		return
	var on_rwy := _on_active_runway(n)
	if ac.fdm.on_ground:
		var gs: float = ac.fdm.ground_speed()
		if gs > 3.0 and not clearance.taxi and not clearance.pushback and not vfr and state in ["delivery", "clr_rb", "ground_push", "push_rb"]:
			if _deviate("taxi", 0.3, "Taxiing without clearance"):
				_say("GND", "%s, stop immediately, you are not cleared to taxi." % callsign, "%s, stop immediately, you are not cleared to taxi." % spoken_cs, 0.6)
		if on_rwy and gs > 2.0 and not (clearance.lineup or clearance.takeoff or clearance.landing) and not state in ["landing", "handoff", "vacated", "taxi_in", "taxi_in_rb"]:
			if _deviate("incursion", 0.8, "Runway incursion: entered runway %s without clearance" % dep_end.name):
				_say("TWR", "%s, you entered the runway without clearance, hold position! Pilot deviation, report on arrival." % callsign, "%s, hold position! You entered the runway without clearance." % spoken_cs, 0.5)
		if gs > 40.0 and not clearance.takeoff and on_rwy and state != "landing" and not ac.get_meta("rejecting", false):
			if _deviate("takeoff_noclr", 1.0, "Takeoff roll without takeoff clearance"):
				_say("TWR", "%s, STOP, cancel takeoff, I say again, cancel takeoff!" % callsign, "%s, stop immediately, cancel take off, I say again, cancel take off!" % spoken_cs, 0.3)
	else:
		if absf(clearance.alt_m - _alt_clr_last) > 1.0:
			_alt_clr_last = clearance.alt_m
			_alt_clr_t = _t
		# once cleared for the approach the glideslope, not the last level, governs the descent
		var on_approach: bool = clearance.approach and float(n.vs) < 0.5
		if clearance.alt_m > 0.0 and _t - _alt_clr_t > 75.0 and not on_approach and state in ["climbing", "cruise", "descending", "vectors", "established"]:
			var bust = float(n.alt) - clearance.alt_m
			var heading_for = (float(n.vs) > 0.5 and bust < 0.0) or (float(n.vs) < -0.5 and bust > 0.0)
			if absf(bust) > 92.0 and not heading_for and absf(bust) < 4000.0 and (state != "climbing" or bust > 0.0) and (state != "descending" or bust < 0.0):
				var sev := 0.25 if absf(bust) < 300.0 else 0.6
				if _deviate("altitude", sev, "Altitude deviation of %d ft from the cleared level" % int(absf(bust) / U.FT)):
					_say(station, "%s, check altitude, you were cleared %s." % [callsign, _lvl(clearance.alt_m)[0]], "%s, check altitude, cleared %s." % [spoken_cs, _lvl(clearance.alt_m)[1]], 0.8)
		_spd_t = _spd_t + delta if float(n.alt) < 3050.0 and float(n.ias_kt) > 262.0 and ac.ra > 300.0 else 0.0
		if _spd_t > 15.0:
			if _deviate("speed", 0.15, "Speed above 250 kt below 10,000 ft"):
				_say(station, "%s, reduce speed two five zero knots." % callsign, "%s, reduce speed two five zero knots." % spoken_cs, 0.8)
		if ac.ra < 15.0 and not clearance.landing and n.vs < -1.0 and U.dist2d(n.x, n.z, arr_end.thr_x, arr_end.thr_z) < 2500.0 and state in ["handoff", "continue_app", "twr_contact", "established", "vectors"]:
			_deviate("land_noclr", 0.7, "Landed without landing clearance")


func _on_active_runway(n: Dictionary) -> bool:
	for e in [dep_end, arr_end]:
		if e.is_empty():
			continue
		var d := Vector2(sin(deg_to_rad(e.hdg)), -cos(deg_to_rad(e.hdg)))
		var rel := Vector2(float(n.x) - float(e.thr_x), float(n.z) - float(e.thr_z))
		var along := rel.dot(d)
		var lat := absf(rel.dot(Vector2(-d.y, d.x)))
		if along > -30.0 and along < float(e.len) + 30.0 and lat < float(e.wid) * 0.5 + 2.0:
			return true
	return false


# ---------------------------------------------------------------- background radio
const OTHER_CALLS := ["Coastal", "Lumen", "Northwind", "Westmark", "Apex", "Skyfall", "Horizon"]


func traffic_call(icao: String, cs: String, atc_text: String, reply: String) -> void:
	## A tower exchange with AI traffic, heard when we are on that tower's frequency.
	var st := "TWR" if icao == dep else "ATWR"
	if station != st:
		return
	_emit(st, "atc", atc_text, atc_text)
	get_tree().create_timer(_rng.randf_range(1.5, 2.5)).timeout.connect(func(): _emit(st, "other", reply, reply, cs))


func _chatter(delta: float) -> void:
	_chatter_t -= delta
	if _chatter_t > 0.0 or not queue.is_empty() or silence_t < 6.0:
		return
	_chatter_t = _rng.randf_range(28.0, 75.0)
	var cs := "%s %d" % [OTHER_CALLS[_rng.randi() % OTHER_CALLS.size()], _rng.randi_range(10, 989)]
	var sp := Phraseology.callsign_spoken(cs)
	var lines := []
	match station:
		"DEL":
			var dest := String(Airports.ORDER[_rng.randi() % Airports.ORDER.size()])
			var sq := "%d%d%d%d" % [_rng.randi_range(1, 6), _rng.randi_range(0, 7), _rng.randi_range(0, 7), _rng.randi_range(0, 7)]
			lines = [["%s, cleared to %s, climb %s feet, squawk %s." % [cs, dest, 5000, sq], "%s, cleared to %s, climb five thousand feet, squawk %s." % [sp, dest, Phraseology.squawk(sq)]]]
		"GND", "AGND":
			var rwy := String((dep_end if station == "GND" else arr_end).name)
			lines = [["%s, taxi to holding point runway %s via A." % [cs, rwy], "%s, taxi to holding point %s via alpha." % [sp, Phraseology.runway(rwy)]],
				["%s, pushback approved." % cs, "%s, push back approved." % sp]]
		"TWR", "ATWR":
			lines = [["%s, runway %s, cleared to land." % [cs, (dep_end if station == "TWR" else arr_end).name], "%s, %s, cleared to land." % [sp, Phraseology.runway(String((dep_end if station == "TWR" else arr_end).name))]],
				["%s, line up and wait." % cs, "%s, line up and wait." % sp]]
		"APP":
			var alt_ft := _rng.randi_range(3, 7) * 1000
			var hdg := _rng.randi_range(1, 36) * 10
			var spd = [180, 190, 210, 220][_rng.randi() % 4]
			lines = [["%s, descend %d feet." % [cs, alt_ft], "%s, descend %s." % [sp, Phraseology.altitude_ft(alt_ft)]],
				["%s, reduce speed %d knots." % [cs, spd], "%s, reduce speed %s knots." % [sp, Phraseology.digits(str(spd))]],
				["%s, turn left heading %03d, vectors ILS." % [cs, hdg], "%s, turn left %s, vectors I L S." % [sp, Phraseology.heading(hdg)]],
				["%s, contact Tower 118.7." % cs, "%s, contact tower one one eight decimal seven." % sp]]
		_:
			var climbing := station == "DEP" or _rng.randf() < 0.5
			var fl := _rng.randi_range(12, 24) * 10 if station == "DEP" else _rng.randi_range(18, 39) * 10
			var hdg2 := _rng.randi_range(1, 36) * 10
			lines = [["%s, %s FL%03d." % [cs, "climb" if climbing else "descend", fl], "%s, %s %s." % [sp, "climb" if climbing else "descend", Phraseology.flight_level(fl)]],
				["%s, turn right heading %03d, traffic." % [cs, hdg2], "%s, turn right %s, traffic." % [sp, Phraseology.heading(hdg2)]]]
			if station == "DEP":
				lines.append(["%s, contact Calderra Control 128.9." % cs, "%s, contact Calderra Control one two eight decimal niner." % sp])
	var l: Array = lines[_rng.randi() % lines.size()]
	_emit(station, "atc", String(l[0]), String(l[1]))
	# the other pilot reads back
	var rb := String(l[0]).replace(cs + ", ", "").trim_suffix(".") + ", " + cs + "."
	var rb_spoken := String(l[1]).replace(sp + ", ", "").trim_suffix(".") + ", " + sp + "."
	get_tree().create_timer(_rng.randf_range(1.8, 3.2)).timeout.connect(func(): _emit(station, "other", rb.left(1).to_upper() + rb.substr(1), rb_spoken, cs))
