class_name Activities
## Hand-made scenarios for the ACTIVITIES menu: discovery flights (scenic routes), landing
## challenges (scored approaches in hard conditions) and bush trips (multi-leg journeys between
## small fields). Each one launches a real free flight; the debrief result comes back to the
## menu, is scored here and the best score and medal are kept in Game.settings.

const CATEGORIES := {
	"discovery": {"title": "Discovery Flights", "shot": "act_discovery", "accent": Color(0.33, 0.78, 1.0),
		"blurb": "Scenic flights through the most beautiful corners of Calderra and Westmark. No pressure - just you, the light and the view."},
	"landing": {"title": "Landing Challenges", "shot": "act_landing", "accent": Color(1.0, 0.72, 0.22),
		"blurb": "Short final, hard conditions, one chance. Crosswinds, gusts, fog, night and short strips - every touchdown is scored."},
	"bush": {"title": "Bush Trips", "shot": "act_bush", "accent": Color(0.42, 0.9, 0.55),
		"blurb": "Multi-leg journeys between small fields in the trainer and the turboprop. Navigate by sight, leg by leg."},
}
const ORDER := ["discovery", "landing", "bush"]
const MEDALS := [["gold", 90.0], ["silver", 78.0], ["bronze", 60.0]]
const MEDAL_COLORS := {"gold": Color(1.0, 0.8, 0.28), "silver": Color(0.8, 0.85, 0.9), "bronze": Color(0.85, 0.55, 0.32), "": Color(0.45, 0.5, 0.56)}
const SETTINGS_KEY := "activity_records"

## start: "runway" (lined up), "gate" or "air" (dist_km out on final to arr_rwy at alt_ft MSL).
## hour: local time; weather: WeatherModel preset; wind: fixed wind direction (crosswind preset).
const SCENARIOS := [
	# ------------------------------------------------------------ discovery flights
	{"id": "golden_coast", "category": "discovery", "title": "The Golden Coast", "place": "Willow Field → Port Calder",
		"type": "t172", "airline": "HFA", "dep": "SKWF", "arr": "SKPC", "start": "runway", "dep_rwy": "21", "hour": 18.1, "weather": "few",
		"difficulty": 1, "cruise_ft": 3500.0,
		"desc": "Lift off from Willow Field as the sun drops toward the Western Sea and follow Calder Creek down to the coast. Port Calder's towers catch the last light as you join the circuit for the big international runway.",
		"objective": "Land at Port Calder International.", "tags": ["Golden hour", "VFR", "45 min"]},
	{"id": "highpass_valley", "category": "discovery", "title": "Into the High Valley", "place": "Approach to Highpass",
		"type": "bj6", "airline": "APX", "dep": "SKNG", "arr": "SKHP", "start": "air", "arr_rwy": "06", "dist_km": 42.0, "alt_ft": 11500.0,
		"hour": 18.75, "weather": "clear", "difficulty": 3,
		"desc": "An Apex charter into the mountains. The valley narrows as you descend between snow-streaked ridges toward Highpass, a one-way ILS and terrain on every side, while the peaks glow orange above you.",
		"objective": "Fly the valley approach and land on runway 06.", "tags": ["Mountains", "Sunset", "ILS 06"]},
	{"id": "lake_oren", "category": "discovery", "title": "Lake Oren Evening", "place": "Oren Falls local flight",
		"type": "t172", "airline": "HFA", "dep": "SKOF", "arr": "SKOF", "start": "runway", "dep_rwy": "31", "hour": 19.0, "weather": "clear",
		"difficulty": 1, "cruise_ft": 2500.0,
		"desc": "A calm summer evening at Oren Falls. Take the trainer out over the great lake, trace its shoreline and the falls that gave the city its name, then come home before dark.",
		"objective": "Explore the lake and land back at Oren Falls.", "tags": ["Calm air", "Lake", "Local flight"]},
	{"id": "island_dawn", "category": "discovery", "title": "Dawn Over the Islands", "place": "Sable Bay → Isla Marea",
		"type": "bj6", "airline": "APX", "dep": "SKSB", "arr": "SKIM", "start": "runway", "dep_rwy": "34", "hour": 6.15, "weather": "few",
		"difficulty": 2, "cruise_ft": 9000.0,
		"desc": "A sunrise hop for a client who wants breakfast on Isla Marea. Climb out of Sable Bay over the resort coast and cross the turquoise shallows to the island's short runway by the sea.",
		"objective": "Land at Isla Marea.", "tags": ["Sunrise", "Over water", "Short runway"]},
	{"id": "aldmoor_night", "category": "discovery", "title": "Aldmoor by Night", "place": "Night approach to Aldmoor",
		"type": "bj6", "airline": "APX", "dep": "WMSK", "arr": "WMIA", "start": "air", "arr_rwy": "08", "dist_km": 34.0, "alt_ft": 7000.0,
		"hour": 22.3, "weather": "clear", "difficulty": 2,
		"desc": "Westmark's capital spreads out below like a circuit board. Descend over the city lights onto the four-kilometre runway of Aldmoor's grand old airport.",
		"objective": "Land on runway 08 at Aldmoor.", "tags": ["Night", "City lights", "ILS 08"]},
	# ------------------------------------------------------------ landing challenges
	{"id": "trade_winds", "category": "landing", "title": "Trade Wind Crosswind", "place": "Isla Marea · runway 29",
		"type": "tp72", "airline": "CLK", "dep": "SKPC", "arr": "SKIM", "start": "air", "arr_rwy": "29", "dist_km": 11.0, "alt_ft": 2000.0,
		"hour": 15.5, "weather": "crosswind", "wind": 200.0, "difficulty": 4,
		"desc": "The afternoon trade winds blow straight across Isla Marea's short runway, 26 knots gusting to 38. Crab down final, kick it straight at the last moment and keep the wing down. The runway ends at the sea.",
		"objective": "Touch down on the centreline in the touchdown zone.", "tags": ["Crosswind 26G38", "2000 m runway"]},
	{"id": "short_field", "category": "landing", "title": "Grass Strip Short Field", "place": "Willow Field · grass 30",
		"type": "t172", "airline": "HFA", "dep": "SKWF", "arr": "SKWF", "start": "air", "arr_rwy": "30", "dist_km": 4.5, "alt_ft": 950.0,
		"hour": 9.5, "weather": "few", "difficulty": 3,
		"desc": "Willow Field's grass strip is only 750 metres long. Fly a stabilised approach at the bottom of the speed range, plant it on the numbers and stop well before the hedge.",
		"objective": "Land on the first third of the grass strip.", "tags": ["750 m grass", "Precision"]},
	{"id": "night_rivermouth", "category": "landing", "title": "Black Hole Approach", "place": "Rivermouth · runway 32 at night",
		"type": "rj90", "airline": "CLK", "dep": "SKPC", "arr": "SKRV", "start": "air", "arr_rwy": "32", "dist_km": 13.0, "alt_ft": 2400.0,
		"hour": 23.4, "weather": "clear", "difficulty": 3,
		"desc": "A moonless night over the river mouth: no lights below you until the runway, a classic black-hole illusion that pulls pilots low. Trust the instruments, not your eyes.",
		"objective": "Fly a stable approach and land in the touchdown zone.", "tags": ["Night", "Visual illusion", "ILS 32"]},
	{"id": "northgate_fog", "category": "landing", "title": "Northgate Fog", "place": "Northgate · runway 36 in fog",
		"type": "s320", "airline": "LMN", "dep": "SKPC", "arr": "SKNG", "start": "air", "arr_rwy": "36", "dist_km": 14.0, "alt_ft": 2900.0,
		"hour": 6.6, "weather": "fog", "difficulty": 4,
		"desc": "Freezing fog has settled over Northgate with 350 metres of visibility. Capture the ILS, decide at minimums and land - by hand or with the autoland - without seeing the runway until the last seconds.",
		"objective": "Land on runway 36 in low visibility.", "tags": ["Fog 350 m", "CAT III", "ILS 36"]},
	{"id": "highpass_gusts", "category": "landing", "title": "Mountain Gusts", "place": "Highpass · runway 06",
		"type": "tp72", "airline": "CLK", "dep": "SKNG", "arr": "SKHP", "start": "air", "arr_rwy": "06", "dist_km": 12.0, "alt_ft": 6000.0,
		"hour": 16.2, "weather": "crosswind", "wind": 105.0, "difficulty": 5,
		"desc": "Wind spills over the ridges into the Highpass valley in violent gusts, with downdrafts on short final. Carry extra speed, fight the turbulence and get it down on the one-way runway.",
		"objective": "Survive the gusts and land on runway 06.", "tags": ["Gusts 38 kt", "Turbulence", "High altitude"]},
	{"id": "sable_storm", "category": "landing", "title": "Storm Front", "place": "Sable Bay · runway 16 in rain",
		"type": "s320", "airline": "SKF", "dep": "SKPC", "arr": "SKSB", "start": "air", "arr_rwy": "16", "dist_km": 13.0, "alt_ft": 2300.0,
		"hour": 17.2, "weather": "rain", "difficulty": 3,
		"desc": "A squall line is sweeping across Sable Bay. Heavy rain, a low ceiling and a wet runway: fly the ILS, keep it stable and land firmly enough to break through the water on the runway.",
		"objective": "Land on runway 16 in heavy rain.", "tags": ["Rain", "Low ceiling", "Wet runway"]},
	# ------------------------------------------------------------ bush trips
	{"id": "grand_tour", "category": "bush", "title": "Calderra Grand Tour", "place": "Willow Field · Oren Falls · Highpass",
		"type": "t172", "airline": "HFA", "legs": [["SKWF", "SKOF"], ["SKOF", "SKHP"], ["SKHP", "SKNG"]], "start": "runway", "hour": 9.0,
		"weather": "few", "difficulty": 2, "cruise_ft": 4500.0,
		"desc": "Three legs across the heart of Calderra in the trusty T-172: over the farmland to Lake Oren, up into the mountains to Highpass, then down the long valley to Northgate.",
		"objective": "Complete all three legs.", "tags": ["3 legs", "VFR navigation", "Mountains"]},
	{"id": "island_hopper", "category": "bush", "title": "Island Hopper", "place": "Port Calder · Isla Marea · Sable Bay",
		"type": "tp72", "airline": "CLK", "legs": [["SKPC", "SKIM"], ["SKIM", "SKSB"], ["SKSB", "SKPC"]], "start": "runway", "hour": 11.0,
		"weather": "scattered", "difficulty": 2, "cruise_ft": 9000.0,
		"desc": "The Coastal Link island run in the Kestrel TP-72: out across the sea to Isla Marea, east along the islands to the resort of Sable Bay, then home to Port Calder.",
		"objective": "Complete all three legs.", "tags": ["3 legs", "Over water", "Turboprop"]},
	{"id": "river_run", "category": "bush", "title": "Calder River Run", "place": "Port Calder · Rivermouth · Willow Field",
		"type": "t172", "airline": "HFA", "legs": [["SKPC", "SKRV"], ["SKRV", "SKWF"]], "start": "runway", "hour": 16.8,
		"weather": "few", "difficulty": 1, "cruise_ft": 2500.0,
		"desc": "Follow the coast north to the mouth of the Calder, then turn inland and trace the river valley home to the flight academy at Willow Field before sunset.",
		"objective": "Complete both legs.", "tags": ["2 legs", "River navigation"]},
	{"id": "mountain_mail", "category": "bush", "title": "Mountain Mail", "place": "Northgate · Highpass · Oren Falls",
		"type": "tp72", "airline": "CLK", "legs": [["SKNG", "SKHP"], ["SKHP", "SKOF"]], "start": "runway", "hour": 8.2,
		"weather": "scattered", "difficulty": 4, "cruise_ft": 12000.0,
		"desc": "The morning mail run over the Calder Range: climb out of Northgate and thread the passes to Highpass, then descend across the plateau to Lake Oren.",
		"objective": "Complete both legs.", "tags": ["2 legs", "High terrain", "Turboprop"]},
	{"id": "western_sea", "category": "bush", "title": "Across the Western Sea", "place": "Aldmoor · Skerra · Port Calder",
		"type": "tp72", "airline": "WMA", "legs": [["WMIA", "WMSK"], ["WMSK", "SKPC"]], "start": "runway", "hour": 13.5,
		"weather": "few", "difficulty": 3, "cruise_ft": 15000.0,
		"desc": "Down Westmark's rugged coast to the fishing town of Skerra, then the long crossing of the Western Sea to Calderra, with nothing but water below until the coast appears.",
		"objective": "Complete both legs.", "tags": ["2 legs", "Ocean crossing", "Long leg"]},
]


static func by_category(cat: String) -> Array:
	return SCENARIOS.filter(func(s): return String(s.category) == cat)


static func get_scenario(id: String) -> Dictionary:
	for s in SCENARIOS:
		if String(s.id) == id:
			return s
	return {}


static func legs(scn: Dictionary) -> Array:
	if scn.has("legs"):
		return scn.legs
	return [[String(scn.dep), String(scn.arr)]]


static func aircraft_name(scn: Dictionary) -> String:
	return String(AircraftTypes.get_type(String(scn.type)).name)


# ------------------------------------------------------------------ records
static func records() -> Dictionary:
	## Best scores live in Game.settings; the settings loader only knows its default keys, so
	## the dictionary is read back from the settings file the first time.
	if not Game.settings.has(SETTINGS_KEY):
		var recs := {}
		var cf := ConfigFile.new()
		if cf.load(Game.SETTINGS_PATH) == OK and cf.has_section_key("settings", SETTINGS_KEY):
			var v: Variant = cf.get_value("settings", SETTINGS_KEY)
			if typeof(v) == TYPE_DICTIONARY:
				recs = v
		Game.settings[SETTINGS_KEY] = recs
	return Game.settings[SETTINGS_KEY]


static func record(id: String) -> Dictionary:
	return records().get(id, {})


static func medal_for(score: float) -> String:
	for m in MEDALS:
		if score >= float(m[1]):
			return String(m[0])
	return ""


static func completed_count(cat: String = "") -> int:
	var n := 0
	for s in SCENARIOS:
		if cat != "" and String(s.category) != cat:
			continue
		if int(record(String(s.id)).get("done", 0)) > 0:
			n += 1
	return n


static func next_leg(scn: Dictionary) -> int:
	var r := record(String(scn.id))
	var n := legs(scn).size()
	return clampi(int(r.get("leg", 0)), 0, n - 1) if int(r.get("leg", 0)) < n else 0


# ------------------------------------------------------------------ launching
## The next time the world clock reaches this local hour (time never runs backwards).
static func next_clock(hour: float) -> float:
	var t := floorf(WorldSim.clock / 86400.0) * 86400.0 + hour * 3600.0
	if t < WorldSim.clock:
		t += 86400.0
	return t


static func launch(scn: Dictionary, leg: int = -1) -> void:
	var lg := legs(scn)
	if leg < 0:
		leg = next_leg(scn)
	var pair: Array = lg[clampi(leg, 0, lg.size() - 1)]
	var dep := String(pair[0])
	var arr := String(pair[1])
	var t := String(scn.type)
	var al := Airlines.get_al(String(scn.airline))
	var spec := AircraftTypes.get_type(t)
	var p := {"mode": "pilot", "free_flight": true, "type": t, "airline": String(scn.airline),
		"reg": "%sA%02d" % [String(al.get("reg_prefix", "CR-")), absi(U.hash_str(String(scn.id))) % 90 + 10],
		"dep": dep, "arr": arr, "start": String(scn.get("start", "runway")),
		"callsign": "%s %d" % [String(al.get("callsign", "SKYFALL")).capitalize(), 100 + absi(U.hash_str(String(scn.id) + str(leg))) % 800],
		"flight_id": "ACT-%s-%d-%d" % [String(scn.id), leg, Time.get_ticks_msec()],
		"clock": next_clock(float(scn.get("hour", 12.0))),
		"weather": String(scn.get("weather", "few")), "instant_boarding": true,
		"pax": mini(AircraftTypes.seat_count(t), 2 if spec.category == "trainer" else 40) if AircraftTypes.is_passenger(t) else 0,
		"fuel": float(spec.max_fuel) * (0.55 if lg.size() > 1 else 0.4)}
	if scn.has("dep_rwy"):
		p.dep_rwy = String(scn.dep_rwy)
	if scn.has("arr_rwy"):
		p.arr_rwy = String(scn.arr_rwy)
	if scn.has("cruise_ft"):
		p.cruise_ft = float(scn.cruise_ft)
	if p.start == "air":
		p.alt_ft = float(scn.get("alt_ft", 3000.0))
		p.dist_km = float(scn.get("dist_km", 12.0))
	# the activity's weather, with its wind fixed across the runway where the scenario asks for it
	WeatherModel.override_preset = String(p.weather)
	WeatherModel.override_dir = float(scn.get("wind", -1.0))
	# no random failures in a scenario: switched off for this flight only (read at flight start)
	var old_rate: Variant = Game.settings.get("event_rate", "realistic")
	Game.settings.event_rate = "off"
	Game.goto("flight", p)
	Game.settings.event_rate = old_rate


## Called by the screens the debrief returns to. Scores an activity flight once, stores the
## record and returns a summary ({} when the result was not an activity).
static func consume(params: Dictionary) -> Dictionary:
	var res: Dictionary = params.get("last_result", {})
	var fid := String(res.get("flight_id", ""))
	if not fid.begins_with("ACT-"):
		return {}
	params.erase("last_result")
	WeatherModel.override_dir = -1.0
	var body := fid.substr(4)
	var tail := body.rfind("-")
	body = body.substr(0, tail)
	var dash := body.rfind("-")
	var id := body.substr(0, dash)
	var leg := int(body.substr(dash + 1))
	var scn := get_scenario(id)
	if scn.is_empty():
		return {}
	var score := score_result(scn, res, leg)
	var recs := records()
	var r: Dictionary = recs.get(id, {}).duplicate()
	var lg := legs(scn)
	var outcome := String(res.get("outcome", ""))
	var leg_ok := outcome in ["landed"] and String(res.get("arr", "")) == String(lg[clampi(leg, 0, lg.size() - 1)][1])
	var complete := false
	var final_score := score
	if lg.size() > 1:
		var scores: Array = r.get("leg_scores", [])
		while scores.size() < lg.size():
			scores.append(-1.0)
		if leg_ok:
			scores[leg] = maxf(float(scores[leg]), score)
			r.leg = leg + 1
		r.leg_scores = scores
		complete = leg_ok and leg == lg.size() - 1
		if complete:
			var tot := 0.0
			for s in scores:
				tot += maxf(float(s), 0.0)
			final_score = tot / float(lg.size())
			r.leg = 0
	else:
		complete = leg_ok or (String(scn.category) == "landing" and score > 0.0)
	var prev := float(r.get("best", -1.0))
	var new_best := complete and final_score > prev
	if complete:
		r.done = int(r.get("done", 0)) + 1
		if new_best:
			r.best = final_score
			r.medal = medal_for(final_score)
	r.last = final_score
	r.last_t = Time.get_unix_time_from_system()
	recs[id] = r
	Game.settings[SETTINGS_KEY] = recs
	Game.save_settings()
	return {"id": id, "category": String(scn.category), "score": final_score, "leg_score": score, "leg": leg, "legs": lg.size(),
		"complete": complete, "leg_ok": leg_ok, "new_best": new_best, "medal": medal_for(final_score) if complete else "",
		"best": float(r.get("best", final_score)), "outcome": outcome, "touchdown": res.get("touchdown", {})}


static func score_result(scn: Dictionary, res: Dictionary, leg: int) -> float:
	var outcome := String(res.get("outcome", ""))
	if outcome in ["crashed", "ditched", "abandoned"]:
		return 0.0
	var cats: Dictionary = res.get("categories", {})
	var lg := legs(scn)
	var want := String(lg[clampi(leg, 0, lg.size() - 1)][1])
	var on_target := String(res.get("arr", "")) == want
	if String(scn.category) == "landing":
		if (res.get("touchdown", {}) as Dictionary).is_empty() or not on_target:
			return 0.0
		return clampf(float(cats.get("landing", 0.0)) * 0.65 + float(cats.get("approach", 0.0)) * 0.2 + float(cats.get("safety", 0.0)) * 0.15, 0.0, 100.0)
	var s := float(res.get("score", 0.0))
	return s if on_target else minf(s, 40.0)


# ------------------------------------------------------------------ card art
## Photo-studio recipe for a scenario's picture: the aircraft on final for a landing challenge,
## or flying the route's most scenic stretch for the others.
static func shot_recipe(scn: Dictionary) -> Dictionary:
	var t := String(scn.type)
	var lg := legs(scn)
	var hour := float(scn.get("hour", 12.0))
	var wx := String(scn.get("weather", "few"))
	if wx == "crosswind":
		wx = "scattered"
	if String(scn.category) == "landing" or String(scn.get("start", "")) == "air":
		var rw := String(scn.get("arr_rwy", ""))
		if rw == "":
			var e := Airports.best_runway(String(lg[0][1]), 270.0, 5.0)
			rw = String(e.get("name", ""))
		return {"kind": "final", "size": Vector2i(960, 540), "type": t, "airline": String(scn.airline), "icao": String(lg[0][1]), "rwy": rw,
			"dist_km": 1.3 if t != "t172" else 0.7, "hour": hour, "weather": wx, "cam": Vector3(200.0, 9.0, 2.4), "fov": 40.0,
			"aim": Vector2(0.0, -0.12), "bright": 1.12 if hour > 21.0 or hour < 5.0 else 1.0}
	var a := Airports.pos2(String(lg[0][0]))
	var b := Airports.pos2(String(lg[0][1]))
	var at := a.lerp(b, 0.35) if a.distance_to(b) > 1000.0 else a + Vector2(6000, -4000)
	var big := t != "t172"
	return {"kind": "air", "size": Vector2i(960, 540), "type": t, "airline": String(scn.airline), "at": at, "agl": 1100.0 if big else 420.0,
		"hour": hour, "weather": wx, "sun_rel": 95.0, "pitch": 3.0, "bank": -12.0, "cam": Vector3(-52.0, 5.0, 1.75 if big else 2.0),
		"fov": 36.0, "airports": false}
