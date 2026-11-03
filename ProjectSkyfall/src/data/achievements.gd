class_name Achievements
extends RefCounted
## Goals across the whole game: landings, places, landmarks, drama in the news, activities.
## Progress lives in Game.settings (shared by every character) and unlocks pop up as toasts.

const LIST := [
	# ---------------------------------------------------------------- flying
	{"id": "first_flight", "title": "Wheels Up", "desc": "Complete your first flight.", "icon": "plane", "group": "Flying"},
	{"id": "butter", "title": "Butter", "desc": "Land at less than 100 feet per minute.", "icon": "trophy", "group": "Flying"},
	{"id": "silk", "title": "Silk Touch", "desc": "Make ten landings under 150 feet per minute.", "icon": "trophy", "group": "Flying", "goal": 10, "stat": "soft_landings"},
	{"id": "night_owl", "title": "Night Owl", "desc": "Land between 22:00 and 05:00.", "icon": "moon", "group": "Flying"},
	{"id": "zero_vis", "title": "Zero Visibility", "desc": "Land with less than 800 metres of visibility.", "icon": "fog", "group": "Flying"},
	{"id": "crab", "title": "Crabbing Master", "desc": "Land with a crosswind of 20 knots or more.", "icon": "wind", "group": "Flying"},
	{"id": "logbook", "title": "Logbook", "desc": "Fly ten hours in total.", "icon": "clock", "group": "Flying", "goal": 10, "stat": "hours"},
	{"id": "type_rated", "title": "Type Rated", "desc": "Fly five different aircraft types.", "icon": "plane", "group": "Flying", "goal": 5, "stat": "types"},
	{"id": "queen", "title": "Queen of the Skies", "desc": "Fly the four-engine Atlas W-380 Skyliner.", "icon": "plane", "group": "Flying"},
	{"id": "crew_rest", "title": "Crew Rest", "desc": "Let auto-fly bring the aircraft in to land.", "icon": "user", "group": "Flying"},
	{"id": "butter_streak", "title": "Butter Streak", "desc": "Make five landings in a row under 150 feet per minute.", "icon": "trophy", "group": "Flying"},
	{"id": "fresh_off_line", "title": "Fresh Off the Line", "desc": "Fly three of the new types: S319, RJ-100, TP-90, W-280, W-390, BJ-8.", "icon": "plane", "group": "Flying", "goal": 3, "stat": "new_types"},
	{"id": "five_star", "title": "Five Stars", "desc": "Earn a five-star review from your passengers.", "icon": "star", "group": "Flying"},
	{"id": "autopilot_ace", "title": "Autopilot Ace", "desc": "Let auto-fly land under 100 feet per minute.", "icon": "user", "group": "Flying"},
	{"id": "personal_best", "title": "Personal Best", "desc": "Beat your softest landing at an airport.", "icon": "trophy", "group": "Flying"},
	{"id": "skipper", "title": "Skipper", "desc": "Skip ahead ten times.", "icon": "clock", "group": "Flying", "goal": 10, "stat": "skips"},
	{"id": "close_call", "title": "Close Call", "desc": "Have a near miss with another airliner.", "icon": "bell", "group": "Drama"},
	{"id": "shutterbug", "title": "Shutterbug", "desc": "Take a photo in flight (F10).", "icon": "star", "group": "Flying"},
	# ---------------------------------------------------------------- places
	{"id": "big_apple", "title": "The Big Apple", "desc": "Land at New York JFK.", "icon": "pin", "group": "Places"},
	{"id": "mind_gap", "title": "Mind the Gap", "desc": "Land at London Heathrow.", "icon": "pin", "group": "Places"},
	{"id": "bonjour", "title": "Bonjour Paris", "desc": "Land at Paris Charles de Gaulle.", "icon": "pin", "group": "Places"},
	{"id": "hollywood", "title": "Hollywood Ending", "desc": "Land at Los Angeles.", "icon": "pin", "group": "Places"},
	{"id": "islands", "title": "Island Life", "desc": "Land at Bermuda, the Azores and Madeira.", "icon": "pin", "group": "Places", "goal": 3, "stat": "atlantic_islands"},
	{"id": "collector", "title": "Collector", "desc": "Land at ten different airports.", "icon": "globe", "group": "Places", "goal": 10, "stat": "airports"},
	{"id": "globetrotter", "title": "Globetrotter", "desc": "Land in five different countries.", "icon": "globe", "group": "Places", "goal": 5, "stat": "countries"},
	{"id": "new_horizons", "title": "New Horizons", "desc": "Fly from Calderra or Westmark to the real world.", "icon": "globe", "group": "Places"},
	{"id": "the_pond", "title": "Across the Pond", "desc": "Fly between North America and Europe in one flight.", "icon": "globe", "group": "Places"},
	{"id": "coast_to_coast", "title": "Coast to Coast", "desc": "Land at five of the new cities: Atlanta, Dallas, Denver, Seattle, Las Vegas, Berlin, Stockholm and more.", "icon": "globe", "group": "Places", "goal": 5, "stat": "new_airports"},
	{"id": "mile_high", "title": "Mile High", "desc": "Land at Denver, a mile above sea level.", "icon": "pin", "group": "Places"},
	{"id": "viking", "title": "Viking Route", "desc": "Land at Oslo, Stockholm and Copenhagen.", "icon": "pin", "group": "Places", "goal": 3, "stat": "nordic"},
	# ---------------------------------------------------------------- sightseeing
	{"id": "sightseer", "title": "Sightseer", "desc": "Fly low past three famous landmarks.", "icon": "star", "group": "Sightseeing", "goal": 3, "stat": "landmarks"},
	{"id": "seen_it_all", "title": "Seen It All", "desc": "Fly low past fifteen landmarks.", "icon": "star", "group": "Sightseeing", "goal": 15, "stat": "landmarks"},
	{"id": "liberty", "title": "Lady Liberty", "desc": "Fly past the Statue of Liberty.", "icon": "star", "group": "Sightseeing"},
	{"id": "iron_lady", "title": "The Iron Lady", "desc": "Fly past the Eiffel Tower.", "icon": "star", "group": "Sightseeing"},
	{"id": "golden_gate", "title": "Golden Gate", "desc": "Fly past the Golden Gate Bridge.", "icon": "star", "group": "Sightseeing"},
	{"id": "big_ben", "title": "Bong!", "desc": "Fly past Big Ben.", "icon": "star", "group": "Sightseeing"},
	# ---------------------------------------------------------------- drama
	{"id": "front_page", "title": "Front Page", "desc": "Make the news with a crash.", "icon": "news", "group": "Drama"},
	{"id": "survivor", "title": "Survivor", "desc": "Walk away from a crash.", "icon": "user", "group": "Drama"},
	{"id": "big_sky", "title": "Big Sky Theory", "desc": "Collide with another aircraft in flight.", "icon": "bell", "group": "Drama"},
	{"id": "state_pilot", "title": "Calderra One", "desc": "Fly the president safely to their destination.", "icon": "star", "group": "Flying"},
	{"id": "history", "title": "History Books", "desc": "Crash the presidential aircraft.", "icon": "bell", "group": "Drama"},
	{"id": "not_the_tower", "title": "Not The Tower!", "desc": "Crash into a famous landmark.", "icon": "bell", "group": "Drama"},
	{"id": "keyboard_pilot", "title": "Keyboard Pilot", "desc": "Post a comment under a story.", "icon": "news", "group": "Drama"},
	{"id": "talk_of_town", "title": "Talk of the Town", "desc": "Get comments written by Claude under a story.", "icon": "news", "group": "Drama"},
	{"id": "couch_pilot", "title": "Couch Pilot", "desc": "Watch a news report.", "icon": "play", "group": "Drama"},
	# ---------------------------------------------------------------- nature
	{"id": "solid_ground", "title": "Solid Ground?", "desc": "Land through an earthquake.", "icon": "bell", "group": "Nature"},
	{"id": "gliding", "title": "We Are Gliding", "desc": "Survive an all-engine flameout in volcanic ash and land.", "icon": "plane", "group": "Nature"},
	{"id": "hail_mary", "title": "Hail Mary", "desc": "Land after hail has cracked your windscreen.", "icon": "storm", "group": "Nature"},
	{"id": "zapped", "title": "Zapped", "desc": "Get hit by lightning.", "icon": "storm", "group": "Nature"},
	{"id": "eye_of_storm", "title": "Eye of the Storm", "desc": "Land in a hurricane.", "icon": "wind", "group": "Nature"},
	{"id": "twister", "title": "Twister", "desc": "Land in a tornado outbreak.", "icon": "wind", "group": "Nature"},
	{"id": "whiteout", "title": "Whiteout", "desc": "Land in a blizzard.", "icon": "snow", "group": "Nature"},
	{"id": "stork", "title": "Special Delivery", "desc": "A baby is born on board your flight.", "icon": "user", "group": "Drama"},
	{"id": "cupid", "title": "Cupid", "desc": "Someone proposes on your flight.", "icon": "user", "group": "Drama"},
	# ---------------------------------------------------------------- air traffic control
	{"id": "tower_rookie", "title": "Tower Rookie", "desc": "Handle ten movements as a tower controller.", "icon": "user", "group": "Air Traffic Control", "goal": 10, "stat": "tower_moves"},
	{"id": "busy_tower", "title": "Busy Tower", "desc": "Handle a hundred movements as a tower controller.", "icon": "user", "group": "Air Traffic Control", "goal": 100, "stat": "tower_moves"},
	{"id": "mayday_saved", "title": "Priority Landing", "desc": "Bring a MAYDAY flight safely onto the runway.", "icon": "bell", "group": "Air Traffic Control"},
	{"id": "runway_collision", "title": "Suspended", "desc": "Clear two aircraft onto the same runway... and watch them collide.", "icon": "bell", "group": "Air Traffic Control"},
	{"id": "night_shift", "title": "Night Shift", "desc": "Work a night shift in the tower.", "icon": "moon", "group": "Air Traffic Control"},
	{"id": "rush_hour", "title": "Rush Hour", "desc": "Survive a rush-hour shift with ten movements and no collisions.", "icon": "trophy", "group": "Air Traffic Control"},
	{"id": "good_catch", "title": "Good Catch", "desc": "Survive an ATC mistake: the runway you were cleared onto was not clear.", "icon": "bell", "group": "Drama"},
	# ---------------------------------------------------------------- activities
	{"id": "daily", "title": "Daily Pilot", "desc": "Complete a daily challenge.", "icon": "clock", "group": "Activities"},
	{"id": "regular", "title": "Regular", "desc": "Complete seven daily challenges.", "icon": "clock", "group": "Activities", "goal": 7, "stat": "dailies"},
	{"id": "challenger", "title": "Challenger", "desc": "Complete five activities.", "icon": "trophy", "group": "Activities", "goal": 5, "stat": "activities"},
	{"id": "gold", "title": "Gold Standard", "desc": "Win a gold medal in an activity.", "icon": "trophy", "group": "Activities"},
]

## Landmark ids that count for the sightseeing goals (skyline clusters do not).
const LANDMARK_IDS := {"liberty": "liberty", "eiffel": "iron_lady", "ggb": "golden_gate", "bigben": "big_ben"}


static func _store() -> Dictionary:
	var d: Variant = Game.settings.get("achievements", {})
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
	if not d.has("done"):
		d["done"] = {}
	if not d.has("stats"):
		d["stats"] = {}
	Game.settings["achievements"] = d
	return d


static func unlocked(id: String) -> bool:
	return (_store().done as Dictionary).has(id)


static func unlocked_count() -> int:
	return (_store().done as Dictionary).size()


static func stat(name: String) -> float:
	var v: Variant = (_store().stats as Dictionary).get(name, 0.0)
	return float((v as Array).size()) if typeof(v) == TYPE_ARRAY else float(v)


static func progress(a: Dictionary) -> float:
	if unlocked(String(a.id)):
		return 1.0
	if a.has("goal"):
		return clampf(stat(String(a.stat)) / float(a.goal), 0.0, 1.0)
	return 0.0


static func unlock(id: String) -> void:
	var st := _store()
	if (st.done as Dictionary).has(id):
		return
	st.done[id] = Time.get_unix_time_from_system()
	Game.save_settings()
	for a in LIST:
		if String(a.id) == id:
			var text := "Achievement unlocked: %s - %s" % [a.title, a.desc]
			var s: Node = Game.main.get("session") if Game.main else null
			if s and is_instance_valid(s) and s.has_signal("toast"):
				s.emit_signal("toast", text, "success")
			else:
				Game.notify(text, "success")
			break


static func _add(name: String, v: Variant) -> void:
	## Counters add numbers; set-like stats collect unique strings.
	var st: Dictionary = _store().stats
	if typeof(v) == TYPE_STRING:
		var arr: Array = st.get(name, [])
		if not v in arr:
			arr.append(v)
		st[name] = arr
	else:
		st[name] = float(st.get(name, 0.0)) + float(v)


static func _check_goals() -> void:
	for a in LIST:
		if a.has("goal") and stat(String(a.stat)) >= float(a.goal):
			unlock(String(a.id))
	Game.save_settings()


# ------------------------------------------------------------------ hooks
static func on_flight_result(res: Dictionary, cons: Dictionary = {}) -> void:
	var outcome := String(res.get("outcome", ""))
	if outcome == "abandoned":
		return
	var type_id := String(res.get("type", ""))
	if type_id != "":
		_add("types", type_id)
	if type_id == "w380":
		unlock("queen")
	_add("hours", float(res.get("block_hours", 0.0)))
	var hz: Dictionary = res.get("hazards", {})
	if hz.has("lightning"):
		unlock("zapped")
	if bool(res.get("atc_mistake", false)) and outcome in ["landed", "diverted"]:
		unlock("good_catch")
	for e in res.get("events", []):
		match String(e.get("id", "")):
			"birth":
				unlock("stork")
			"proposal":
				unlock("cupid")
	if type_id in ["s319", "rj100", "tp90", "w280", "w390", "bj8"]:
		_add("new_types", type_id)
	if outcome in ["crashed", "ditched"]:
		unlock("front_page")
		if bool(res.get("presidential", false)):
			unlock("history")
		if not bool(cons.get("dead", false)):
			unlock("survivor")
		if bool(res.get("crash", {}).get("midair", false)):
			unlock("big_sky")
		var hint := String(res.get("crash", {}).get("cause_hint", "")) + " " + String(res.get("crash", {}).get("collision", ""))
		for lm in RealWorld.LANDMARKS:
			if hint.contains(String(lm.name)):
				unlock("not_the_tower")
		_check_goals()
		return
	if outcome not in ["landed", "diverted"]:
		_check_goals()
		return
	unlock("first_flight")
	if bool(res.get("presidential", false)):
		unlock("state_pilot")
	var td: Dictionary = res.get("touchdown", {})
	var vs := absf(float(td.get("vs_fpm", 999.0)))
	if not td.is_empty():
		if vs < 100.0:
			unlock("butter")
		if vs < 150.0:
			_add("soft_landings", 1.0)
		var st: Dictionary = _store().stats
		st["butter_run"] = (float(st.get("butter_run", 0.0)) + 1.0) if vs < 150.0 else 0.0
		if float(st.butter_run) >= 5.0:
			unlock("butter_streak")
	var hour := float(U.clock_to_date(float(res.get("clock", WorldSim.clock))).hours_f)
	if hour >= 22.0 or hour < 5.0:
		unlock("night_owl")
	var wx: Dictionary = res.get("weather", {})
	if float(wx.get("vis", 99999.0)) < 800.0:
		unlock("zero_vis")
	var arr := String(res.get("arr", ""))
	var ap := Airports.get_ap(arr)
	if not ap.is_empty():
		# crosswind component on the runway they landed on
		var e := Airports.best_runway(arr, float(wx.get("wind_dir", 0.0)), float(wx.get("wind_kt", 0.0)))
		if not e.is_empty() and absf(sin(deg_to_rad(float(wx.get("wind_dir", 0.0)) - float(e.hdg)))) * float(wx.get("wind_kt", 0.0)) >= 20.0:
			unlock("crab")
		_add("airports", arr)
		_add("countries", String(ap.get("country", "")))
		match arr:
			"KJFK":
				unlock("big_apple")
			"EGLL":
				unlock("mind_gap")
			"LFPG":
				unlock("bonjour")
			"KLAX":
				unlock("hollywood")
			"TXKF", "LPPD", "LPMA":
				_add("atlantic_islands", arr)
		var dep := Airports.get_ap(String(res.get("dep", "")))
		if not dep.is_empty():
			var dep_world := String(dep.get("region", "")) == "world"
			var arr_world := String(ap.get("region", "")) == "world"
			if arr_world and not dep_world:
				unlock("new_horizons")
			if dep_world and arr_world:
				var lo_a := RealWorld.to_lonlat(float(dep.x), float(dep.z)).x
				var lo_b := RealWorld.to_lonlat(float(ap.x), float(ap.z)).x
				if (lo_a < -40.0) != (lo_b < -40.0):
					unlock("the_pond")
	if bool(res.get("autofly_landed", false)):
		unlock("crew_rest")
		if vs < 100.0 and not td.is_empty() and not bool(td.get("skipped", false)):
			unlock("autopilot_ace")
	if hz.has("earthquake"):
		unlock("solid_ground")
	if hz.has("ash"):
		unlock("gliding")
	if hz.has("hail"):
		unlock("hail_mary")
	match String(res.get("weather_preset", "")):
		"hurricane":
			unlock("eye_of_storm")
		"tornado":
			unlock("twister")
		"blizzard":
			unlock("whiteout")
	if arr in ["KATL", "KDFW", "KDEN", "KSEA", "KLAS", "KMSY", "KMCO", "EDDF", "EDDM", "LSZH", "LOWW", "EKCH", "ENGM", "ESSA", "EDDB", "LEBL", "EBBR", "LPPT", "EGCC", "EGPH"]:
		_add("new_airports", arr)
	if arr == "KDEN":
		unlock("mile_high")
	if arr in ["ENGM", "ESSA", "EKCH"]:
		_add("nordic", arr)
	if int(res.get("pax", 0)) > 0 and NewsExtra.review_stars(res) >= 5:
		unlock("five_star")
	_check_goals()


static func on_landmark(id: String) -> void:
	_add("landmarks", id)
	if LANDMARK_IDS.has(id):
		unlock(String(LANDMARK_IDS[id]))
	_check_goals()


static func on_activity(score: float, medal: String) -> void:
	if score > 0.0:
		_add("activities", 1.0)
	if medal == "gold":
		unlock("gold")
	_check_goals()


static func on_daily(key: String) -> void:
	_add("dailies", key)
	unlock("daily")
	_check_goals()


static func has_daily(key: String) -> bool:
	var v: Variant = (_store().stats as Dictionary).get("dailies", [])
	return typeof(v) == TYPE_ARRAY and key in (v as Array)


static func on_photo() -> void:
	unlock("shutterbug")


static func on_skip() -> void:
	_add("skips", 1.0)
	_check_goals()


static var _tower_last := 0


static func on_tower(moves: int) -> void:
	## Called with the shift's running total; counts only the new movements.
	if moves < _tower_last:
		_tower_last = 0
	_add("tower_moves", float(moves - _tower_last))
	_tower_last = moves
	_check_goals()
