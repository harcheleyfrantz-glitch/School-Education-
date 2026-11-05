extends Node
## The persistent living world: clock, airline fleets, daily schedules, population and airport status.
## The world keeps running whether or not the player is involved.

signal clock_advanced(seconds: float)
signal airport_status_changed(icao: String)

const START_CLOCK := 14200000.0   # ~ 14 June 2027 morning (computed precisely in reset_world)
const POPULATION := 240000
const FREQUENT_FLYERS := 600

var world_seed := 20270614
var clock := 0.0
var fleet := {}            # reg -> aircraft record
var airport_status := {}   # icao -> {closed_until, reason, delay_min}
var people_mods := {}      # str(person id) -> {status, flights, last_flight, notes}
var flight_overrides := {} # flight id -> {status, note, delay}
var world_events := []     # background events already generated (ids)
var sim_running := false   # true while a flight scene drives the clock
var _schedule_cache := {}  # day index -> Array


func _ready() -> void:
	reset_world()


func reset_world() -> void:
	world_seed = 20270614
	clock = U.date_to_clock(2027, 6, 14, 6.75)
	fleet.clear()
	airport_status.clear()
	people_mods.clear()
	flight_overrides.clear()
	world_events.clear()
	_schedule_cache.clear()
	_build_fleet()


func on_new_character(_p: Dictionary) -> void:
	pass


# ------------------------------------------------------------------ clock
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var before := clock
	clock += seconds
	_update_airports()
	_maybe_world_events(before, clock)
	News.on_clock(before, clock)
	clock_advanced.emit(seconds)


func day_index(t: float = -1.0) -> int:
	return int(floor((clock if t < 0.0 else t) / 86400.0))


func local_hour(t: float = -1.0) -> float:
	var tt := clock if t < 0.0 else t
	return fmod(tt, 86400.0) / 3600.0


# ------------------------------------------------------------------ fleet
func _build_fleet() -> void:
	var r := U.rng(world_seed + 11)
	for code in Airlines.ORDER:
		var al: Dictionary = Airlines.get_al(code)
		var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ"
		var n := 0
		for type_id in al.fleet.keys():
			for i in int(al.fleet[type_id]):
				var reg: String
				if String(al.reg_prefix).ends_with("-"):
					reg = al.reg_prefix + letters[(n / 576) % 24] + letters[(n / 24) % 24] + letters[n % 24]
				else:
					reg = al.reg_prefix + letters[(n / 24) % 24] + letters[n % 24]
				n += 1
				var age := r.randi_range(1, 19)
				fleet[reg] = {
					"reg": reg, "type": type_id, "airline": code, "base": al.hubs[n % al.hubs.size()],
					"location": al.hubs[n % al.hubs.size()], "age": age,
					"condition": clampf(100.0 - age * 1.6 - r.randf() * 12.0, 55.0, 100.0),
					"hours": float(age) * r.randf_range(2200.0, 3600.0), "cycles": age * r.randi_range(900, 1800),
					"status": "active", "defects": [], "incidents": [], "name": _aircraft_name(code, r),
				}
				if r.randf() < 0.18:
					fleet[reg].defects.append(_random_defect(r, type_id))


func _aircraft_name(code: String, r: RandomNumberGenerator) -> String:
	const NAMES := ["Spirit of Calderra", "Harbor Light", "Northern Star", "City of Oren Falls", "Island Breeze",
		"Westward Ho", "Silver Gull", "Morning Tide", "Highland Wind", "Sable Dawn", "Aurora", "Meridian",
		"Pioneer", "Wanderer", "Kestrel", "Seafarer", "Dawn Chorus", "Long Reach", "Constellation", "Firefly"]
	if code in ["SKF", "WMA", "CLK"]:
		return U.pick(r, NAMES)
	return ""


func _random_defect(r: RandomNumberGenerator, type_id: String) -> Dictionary:
	var pool := [
		{"id": "apu_inop", "text": "APU inoperative (MEL 49-1)", "system": "apu", "severity": 1},
		{"id": "pack_degraded", "text": "Air conditioning pack 2 degraded", "system": "packs", "severity": 1},
		{"id": "tire_wear", "text": "Main gear tyre #3 worn near limits", "system": "gear", "severity": 2},
		{"id": "hyd_seep", "text": "Minor hydraulic seep, left main gear bay", "system": "hydraulics", "severity": 2},
		{"id": "eng_vib", "text": "Engine 1 vibration trend increasing", "system": "engine", "severity": 2},
		{"id": "fuel_qty", "text": "Centre tank fuel quantity indication erratic", "system": "fuel", "severity": 1},
		{"id": "wx_radar", "text": "Weather radar intermittent", "system": "radar", "severity": 1},
		{"id": "lav_smoke_det", "text": "Aft lavatory smoke detector deferred", "system": "cabin", "severity": 2},
	]
	if AircraftTypes.get_type(type_id).category == "trainer":
		pool = [
			{"id": "mag_drop", "text": "Right magneto RPM drop slightly high", "system": "engine", "severity": 1},
			{"id": "tire_wear", "text": "Nose tyre worn", "system": "gear", "severity": 1},
			{"id": "radio_static", "text": "COM2 radio static", "system": "radio", "severity": 1},
		]
	var d: Dictionary = U.pick(r, pool).duplicate()
	d["since"] = clock
	return d


func fleet_for(airline: String, type_id: String = "") -> Array:
	var out := []
	for reg in fleet.keys():
		var a: Dictionary = fleet[reg]
		if a.airline == airline and a.status != "written_off" and (type_id == "" or a.type == type_id):
			out.append(a)
	return out


func aircraft(reg: String) -> Dictionary:
	return fleet.get(reg, {})


func record_flight_on_aircraft(reg: String, hours: float, stress: float) -> void:
	if not fleet.has(reg):
		return
	var a: Dictionary = fleet[reg]
	a.hours = float(a.hours) + hours
	a.cycles = int(a.cycles) + 1
	a.condition = clampf(float(a.condition) - 0.15 - stress * 4.0, 0.0, 100.0)


# ------------------------------------------------------------------ schedule
const ROUTES := {
	"DAL": [["KATL", "KJFK", "b738", 4], ["KATL", "KLAX", "a21n", 3], ["KATL", "KMIA", "b738", 3], ["KATL", "KORD", "a20n", 3], ["KATL", "KBOS", "a20n", 2],
		["KATL", "EGLL", "a359", 1], ["KATL", "LFPG", "a359", 1], ["KJFK", "LFPG", "b77w", 1], ["KDTW", "RJTT", "a359", 1], ["KSEA", "RJTT", "a359", 1],
		["KMSP", "KDEN", "e175", 2], ["KSLC", "KSFO", "e175", 2], ["KATL", "KCLT", "e175", 3]],
	"AAL": [["KDFW", "KLAX", "a21n", 4], ["KDFW", "KORD", "b738", 4], ["KDFW", "KMIA", "b738", 3], ["KCLT", "KJFK", "a21n", 3], ["KPHX", "KDFW", "b38m", 3],
		["KDFW", "EGLL", "b77w", 1], ["KMIA", "KJFK", "b738", 3], ["KDFW", "RJTT", "b789", 1], ["KPHL", "LFPG", "b789", 1], ["KCLT", "KBOS", "e175", 2]],
	"UAL": [["KORD", "KSFO", "b38m", 4], ["KORD", "KDEN", "a20n", 4], ["KEWR", "KLAX", "b789", 2], ["KIAD", "KORD", "a20n", 3], ["KDEN", "KLAS", "b38m", 3],
		["KSFO", "RJTT", "b77w", 1], ["KEWR", "EGLL", "b789", 1], ["KSFO", "WSSS", "b789", 1], ["KIAD", "EDDF", "b77w", 1], ["KORD", "KDTW", "e175", 2]],
	"SWA": [["KDEN", "KLAS", "b738", 5], ["KDEN", "KPHX", "b38m", 4], ["KLAS", "KLAX", "b738", 5], ["KBWI", "KATL", "b738", 3], ["KBNA", "KDEN", "b38m", 2],
		["KPHX", "KSFO", "b738", 3], ["KBWI", "KMCO", "b38m", 3], ["KDFW", "KDEN", "b738", 2]],
	"BAW": [["EGLL", "KJFK", "b77w", 3], ["EGLL", "LFPG", "a20n", 4], ["EGLL", "EDDF", "a20n", 3], ["EGLL", "KLAX", "a388", 1], ["EGLL", "OMDB", "a388", 1],
		["EGLL", "WSSS", "a359", 1], ["EGLL", "RJTT", "b789", 1], ["EGLL", "LEMD", "a21n", 3], ["EGLL", "KMIA", "b789", 1]],
	"DLH": [["EDDF", "EDDM", "a20n", 5], ["EDDF", "KJFK", "b744", 1], ["EDDF", "KORD", "a359", 1], ["EDDM", "KLAX", "a388", 1], ["EDDF", "EGLL", "a20n", 3],
		["EDDF", "LFPG", "e175", 3], ["EDDM", "RJTT", "a359", 1], ["EDDF", "WSSS", "a388", 1], ["EDDM", "LSZH", "e175", 3]],
	"AFR": [["LFPG", "KJFK", "b77w", 2], ["LFPG", "EGLL", "a20n", 4], ["LFPG", "LEMD", "a20n", 3], ["LFPG", "RJTT", "a359", 1], ["LFPG", "OMDB", "b789", 1],
		["LFPG", "KLAX", "b77w", 1], ["LFPG", "EDDF", "a21n", 2], ["LFPG", "LIRF", "a20n", 3]],
	"UAE": [["OMDB", "EGLL", "a388", 3], ["OMDB", "KJFK", "a388", 2], ["OMDB", "LFPG", "b77w", 2], ["OMDB", "WSSS", "a388", 2], ["OMDB", "RJTT", "b77w", 1],
		["OMDB", "KLAX", "a388", 1], ["OMDB", "EDDF", "b77w", 2], ["OMDB", "VIDP", "b77w", 3]],
	"JAL": [["RJTT", "RJBB", "b738", 6], ["RJTT", "KJFK", "b77w", 1], ["RJTT", "KLAX", "b789", 1], ["RJTT", "EGLL", "a359", 1], ["RJTT", "WSSS", "b789", 1],
		["RJTT", "RKSI", "b738", 2], ["RJTT", "VHHH", "a359", 2]],
	"SIN": [["WSSS", "EGLL", "a388", 2], ["WSSS", "KJFK", "a359", 1], ["WSSS", "RJTT", "b789", 2], ["WSSS", "VHHH", "a359", 3], ["WSSS", "OMDB", "b77w", 1],
		["WSSS", "LFPG", "a388", 1], ["WSSS", "KLAX", "a359", 1], ["WSSS", "WMKK", "b789", 4]],
	"SKF": [["SKPC", "KJFK", "w350", 1], ["SKPC", "EGLL", "w350", 1], ["SKPC", "SKNG", "s320", 4], ["SKPC", "SKOF", "s320", 3], ["SKPC", "SKSB", "s320", 3], ["SKPC", "WMIA", "w350", 3],
		["SKPC", "WMIA", "s320", 2], ["SKPC", "SKHP", "rj90", 2], ["SKPC", "SKRV", "rj90", 3], ["SKPC", "SKIM", "rj90", 2],
		["SKPC", "WMSK", "rj90", 1], ["SKNG", "WMIA", "w350", 1], ["SKAU", "KJFK", "w380", 2], ["SKAU", "EGLL", "w380", 2], ["SKAU", "SKPC", "s321", 6], ["SKAU", "SKNG", "s320", 3], ["SKAU", "OMDB", "w350", 1], ["SKAU", "RJTT", "w390", 1], ["SKAU", "WSSS", "w390", 1], ["SKAU", "LFPG", "w350", 1], ["SKAU", "KLAX", "w390", 1]],
	"CLK": [["SKPC", "SKIM", "tp72", 4], ["SKPC", "SKRV", "tp72", 3], ["SKSB", "SKIM", "tp72", 2], ["SKSB", "SKOF", "rj90", 2],
		["SKPC", "SKHP", "tp72", 2], ["SKPC", "SKSB", "rj90", 2], ["SKOF", "SKHP", "tp72", 1], ["SKAU", "SKRV", "tp72", 3], ["SKAU", "SKOF", "tp72", 2], ["SKAU", "SKSB", "rj90", 2]],
	"LMN": [["SKNG", "SKPC", "s320", 4], ["SKNG", "SKSB", "s320", 2], ["SKNG", "SKOF", "s320", 2], ["SKPC", "WMIA", "s320", 2],
		["SKNG", "WMIA", "s320", 1], ["SKPC", "SKSB", "s320", 2]],
	"NWC": [["SKNG", "WMIA", "f4", 1], ["SKNG", "SKPC", "f4", 2], ["SKNG", "SKOF", "f4", 1], ["SKAU", "SKNG", "f4", 1], ["SKAU", "KJFK", "f4", 1]],
	"APX": [["SKPC", "SKSB", "bj6", 2], ["SKSB", "WMIA", "bj6", 1], ["SKPC", "SKHP", "bj6", 1], ["SKPC", "SKIM", "bj6", 1]],
	"HFA": [["SKWF", "SKWF", "t172", 6], ["SKWF", "SKPC", "t172", 2], ["SKWF", "SKOF", "t172", 1], ["SKWF", "SKSB", "t172", 1]],
	"AUR": [["WMSK", "SKPC", "w380", 2], ["WMIA", "SKPC", "w380", 1], ["WMSK", "WMIA", "s321", 3], ["WMSK", "SKNG", "w350", 2], ["WMIA", "SKSB", "w350", 1],
		["WMSK", "EGLL", "w380", 1], ["WMIA", "LFPG", "w350", 1], ["WMSK", "RJTT", "w380", 1], ["WMSK", "WSSS", "w390", 1], ["WMSK", "OMDB", "w350", 1], ["SKAU", "WMSK", "s321", 2], ["SKAU", "WMIA", "s321", 3]],
	"PEL": [["SKIM", "SKSB", "tp50", 4], ["SKIM", "SKOF", "tp50", 2], ["SKSB", "SKHP", "tp50", 2], ["SKIM", "SKPC", "tp72", 2], ["SKSB", "SKIM", "tp72", 2]],
	"VTX": [["SKOF", "SKPC", "s321", 4], ["SKOF", "SKNG", "s321", 2], ["SKHP", "SKPC", "s320", 3], ["SKOF", "WMIA", "s321", 1], ["SKHP", "SKRV", "rj70", 3], ["SKAU", "SKHP", "s320", 2], ["SKAU", "SKOF", "s321", 2]],
	"LBA": [["KJFK", "EGLL", "w380", 2], ["KJFK", "LFPG", "w350", 2], ["KJFK", "KLAX", "s321", 3], ["KJFK", "KMIA", "s321", 3], ["KJFK", "KORD", "s320", 4],
		["KBOS", "EGLL", "w350", 1], ["KJFK", "KBOS", "rj70", 4], ["KJFK", "KIAD", "rj70", 3], ["KJFK", "TXKF", "s320", 1], ["KJFK", "BIKF", "s320", 1],
		["KBOS", "EIDW", "s321", 1], ["KJFK", "SKPC", "w350", 1], ["KJFK", "KATL", "s319", 3], ["KJFK", "KSEA", "s321", 1], ["KJFK", "KLAS", "s321", 2],
		["KJFK", "EDDF", "w390", 1], ["KJFK", "LEBL", "w280", 1], ["KJFK", "RJTT", "w390", 1], ["KJFK", "WSSS", "w390", 1], ["KJFK", "OMDB", "w380", 1], ["KJFK", "KPHL", "rj70", 3], ["KJFK", "KBWI", "rj70", 2], ["KJFK", "KPWM", "rj70", 2], ["KJFK", "KBTV", "rj70", 1], ["KJFK", "KCLT", "s320", 3], ["KJFK", "KDTW", "s320", 2], ["KJFK", "KCLE", "rj90", 2], ["KJFK", "KBDL", "rj70", 1], ["KJFK", "KILG", "tp72", 1], ["KEWR", "KORD", "s320", 3], ["KEWR", "KATL", "s320", 2], ["KEWR", "KMIA", "s321", 2], ["KEWR", "EGLL", "w350", 1], ["KEWR", "KSFO", "s321", 1], ["KEWR", "PHNL", "w350", 1], ["KPHL", "KMCO", "s320", 2], ["KBWI", "KATL", "s320", 2], ["KBOS", "KBTV", "tp72", 1], ["KBOS", "KPWM", "tp72", 2], ["KBDL", "KMCO", "s320", 1], ["KPVD", "KMCO", "s320", 1], ["KBOS", "KMHT", "tp72", 1], ["KORD", "KMKE", "tp72", 3], ["KORD", "KMSP", "s320", 3], ["KORD", "KDTW", "s320", 3], ["KORD", "KIND", "rj90", 3], ["KORD", "KCLE", "rj90", 2], ["KORD", "KSTL", "rj90", 3], ["KORD", "KDSM", "rj90", 2], ["KORD", "KOMA", "rj90", 2], ["KORD", "KSDF", "rj90", 1], ["KORD", "KFSD", "rj90", 1], ["KPHL", "KCRW", "tp72", 1], ["KEWR", "KPVD", "rj70", 1], ["KJFK", "SKAU", "w350", 1]],
	"THA": [["EGLL", "KJFK", "w380", 2], ["EGLL", "LFPG", "s320", 4], ["EGLL", "EHAM", "s320", 3], ["EGLL", "EIDW", "s320", 3], ["EGLL", "LEMD", "s321", 2],
		["EGLL", "LIRF", "s321", 2], ["EGLL", "KMIA", "w350", 1], ["EGLL", "CYYZ", "w350", 1], ["EGLL", "BIKF", "s320", 1], ["EGLL", "LPMA", "s320", 1], ["EGLL", "WMIA", "w350", 1],
		["EGLL", "EDDF", "s320", 3], ["EGLL", "EGPH", "s319", 4], ["EGLL", "EGCC", "s319", 3], ["EGLL", "LEBL", "s320", 2], ["EGLL", "LPPT", "s320", 2], ["EGLL", "KLAS", "w390", 1], ["EGLL", "SKAU", "w350", 1]],
	"LUE": [["LFPG", "KJFK", "w350", 2], ["LFPG", "LIRF", "s320", 3], ["LFPG", "LEMD", "s320", 3], ["LFPG", "EHAM", "rj90", 3], ["LFPG", "EGLL", "s320", 2],
		["LFPG", "KMIA", "w350", 1], ["LFPG", "LPMA", "s320", 1], ["LFPG", "EBBR", "s319", 3], ["LFPG", "LSZH", "s319", 2], ["LFPG", "LEBL", "s320", 2], ["LFPG", "KATL", "w280", 1]],
	"GGP": [["KSFO", "KLAX", "rj70", 5], ["KLAX", "KJFK", "s321", 3], ["KSFO", "KJFK", "s321", 2], ["KLAX", "KMIA", "s320", 2], ["KSFO", "KORD", "s320", 2],
		["KLAX", "KORD", "s320", 2], ["KSFO", "CYYZ", "s320", 1], ["KSFO", "KSEA", "s319", 4], ["KLAX", "KLAS", "s319", 5], ["KSFO", "KDEN", "s320", 2], ["KSEA", "KLAS", "s320", 2], ["KLAX", "WSSS", "w390", 1], ["KSFO", "VHHH", "w390", 1], ["KLAX", "RJTT", "w390", 1], ["KLAX", "KPHX", "s320", 5], ["KSFO", "KPDX", "s320", 3], ["KSEA", "PANC", "s321", 2], ["KSEA", "KPDX", "tp72", 3], ["KLAX", "PHNL", "w350", 2], ["KSFO", "PHNL", "w350", 2], ["KSEA", "PHNL", "s321", 1], ["KPHX", "KDEN", "s320", 2], ["KPHX", "KSLC", "s320", 2], ["KSLC", "KBOI", "rj90", 3], ["KSLC", "KJAC", "rj70", 2], ["KSLC", "KBZN", "rj70", 2], ["KLAX", "KABQ", "s320", 2], ["KPHX", "KABQ", "rj90", 2], ["KSLC", "KLAX", "s320", 3], ["KPDX", "KBOI", "tp72", 2], ["PANC", "PHNL", "s321", 1], ["KSFO", "KSLC", "s320", 2], ["KSEA", "KBOI", "tp72", 2], ["KLAX", "KLAS", "s320", 4], ["PANC", "KLAX", "s321", 1]],
	"MPN": [["CYYZ", "KJFK", "rj90", 4], ["CYYZ", "KORD", "rj90", 3], ["CYYZ", "KBOS", "tp72", 2], ["CYYZ", "CYQX", "tp72", 2], ["CYYZ", "KMIA", "s320", 2], ["CYYZ", "EGLL", "s320", 1]],
	"AUN": [["BIKF", "EKVG", "tp72", 2], ["BIKF", "BGGH", "tp72", 2], ["BIKF", "EGLL", "s320", 2], ["BIKF", "KJFK", "s320", 1], ["BIKF", "EIDW", "rj90", 2],
		["EKVG", "EGLL", "rj90", 1], ["BIKF", "CYQX", "tp50", 1]],
	"IHA": [["TXKF", "KJFK", "rj70", 2], ["TXKF", "LPPD", "tp72", 1], ["LPPD", "LPMA", "tp72", 2], ["LPPD", "LEMD", "rj70", 1], ["LPMA", "LEMD", "rj70", 1], ["TXKF", "KMIA", "tp72", 1]],
	"SOL": [["LEMD", "LIRF", "s320", 3], ["LEMD", "LFPG", "s320", 3], ["LEMD", "EGLL", "s321", 3], ["LEMD", "EHAM", "s320", 2], ["LEMD", "LPMA", "s320", 2],
		["LEMD", "EIDW", "s320", 1], ["LEMD", "KMIA", "s321", 1], ["LEBL", "LEMD", "s319", 5], ["LEBL", "LIRF", "s320", 2], ["LEBL", "LPPT", "s319", 2], ["LEBL", "EGCC", "s321", 2]],
	"LSA": [["KDFW", "KMSY", "tp90", 3], ["KATL", "KMCO", "tp90", 3], ["KDFW", "KDEN", "tp90", 1], ["KDFW", "KATL", "s321", 4], ["KDFW", "KDEN", "s320", 3], ["KDFW", "KLAS", "s320", 3], ["KDFW", "KJFK", "s321", 2], ["KATL", "KMCO", "rj100", 4],
		["KATL", "KMSY", "rj100", 3], ["KATL", "KMIA", "s320", 2], ["KDFW", "KLAX", "s320", 2], ["KDFW", "KMSY", "rj100", 2], ["KATL", "EGLL", "w280", 1], ["KDEN", "KSEA", "s320", 2], ["KDFW", "KOKC", "rj100", 4], ["KDFW", "KLIT", "rj100", 3], ["KDFW", "KJAN", "tp90", 2], ["KDFW", "KICT", "rj100", 2], ["KDFW", "KOMA", "s320", 2], ["KDFW", "KSTL", "s320", 3], ["KDFW", "KMSP", "s320", 2], ["KDFW", "KBNA", "s320", 3], ["KDFW", "KPHX", "s320", 3], ["KATL", "KBHM", "tp90", 4], ["KATL", "KCLT", "s320", 4], ["KATL", "KBNA", "s320", 3], ["KATL", "KCHS", "rj100", 3], ["KATL", "KJAN", "tp90", 2], ["KATL", "KSDF", "rj100", 2], ["KATL", "KIND", "s320", 2], ["KATL", "KCRW", "tp90", 1], ["KDEN", "KDSM", "rj100", 2], ["KDEN", "KFSD", "rj100", 2], ["KDEN", "KFAR", "rj100", 1], ["KDEN", "KBZN", "rj100", 2], ["KDEN", "KJAC", "rj100", 2], ["KDEN", "KABQ", "rj100", 3], ["KDEN", "KMSP", "s320", 2], ["KDEN", "KSLC", "s320", 3], ["KDFW", "PHNL", "w350", 1], ["KDFW", "SKAU", "w350", 1]],
	"RHA": [["EDDF", "KJFK", "w390", 1], ["EDDF", "EGLL", "s320", 3], ["EDDF", "LFPG", "s319", 3], ["EDDM", "LIRF", "s320", 2], ["EDDF", "EDDM", "s319", 4],
		["EDDF", "EDDB", "s320", 4], ["EDDM", "LEBL", "s320", 2], ["EDDF", "KATL", "w350", 1], ["EDDM", "KORD", "w350", 1], ["EDDF", "LPPT", "s321", 1], ["EDDF", "EKCH", "s319", 2]],
	"NRD": [["ENGM", "ESSA", "tp90", 4], ["ENGM", "EKCH", "rj100", 3], ["ESSA", "EKCH", "tp90", 3], ["ENGM", "BIKF", "s319", 1], ["EKCH", "EGCC", "rj100", 2],
		["ESSA", "EDDB", "rj100", 2], ["EKCH", "EGPH", "tp90", 1]],
	"ALP": [["LSZH", "LOWW", "rj90", 3], ["LSZH", "LFPG", "rj100", 3], ["LSZH", "EGLL", "s319", 2], ["LOWW", "EDDM", "rj90", 2], ["LSZH", "LEBL", "rj100", 2],
		["LOWW", "EBBR", "rj100", 1], ["LSZH", "KJFK", "bj8", 1]],
	"SKA": [["RJTT", "RJBB", "s320", 6], ["RJTT", "RKSI", "s321", 4], ["RJTT", "ZSPD", "s321", 3], ["RJTT", "VHHH", "w280", 2], ["RJTT", "WSSS", "w390", 2], ["RJTT", "KSEA", "w390", 1],
		["RJTT", "KLAX", "w390", 1], ["RJBB", "RCTP", "s320", 3], ["RJTT", "EGLL", "q740", 1], ["RJTT", "KJFK", "w390", 1], ["RJTT", "SKAU", "w350", 1]],
	"HAN": [["RKSI", "RJTT", "s321", 5], ["RKSI", "ZBAA", "s321", 3], ["RKSI", "VHHH", "s321", 3], ["RKSI", "WSSS", "w350", 2], ["RKSI", "KLAX", "w390", 1], ["RKSI", "EDDF", "w350", 1]],
	"JDA": [["ZBAA", "ZSPD", "s320", 8], ["ZBAA", "VHHH", "s321", 4], ["ZSPD", "RJTT", "s321", 3], ["ZBAA", "RKSI", "s320", 3], ["ZBAA", "EGLL", "w390", 1], ["ZSPD", "KSFO", "w390", 1],
		["ZBAA", "UUEE", "w350", 2], ["ZSPD", "WSSS", "w350", 2], ["ZBAA", "VIDP", "s321", 1]],
	"PDA": [["VHHH", "RCTP", "s321", 6], ["VHHH", "WSSS", "w350", 4], ["VHHH", "VTBS", "s321", 4], ["VHHH", "RPLL", "s321", 3], ["VHHH", "RJTT", "w350", 3], ["VHHH", "EGLL", "w380", 1],
		["VHHH", "KSFO", "w350", 1], ["VHHH", "OMDB", "w350", 1]],
	"MER": [["WSSS", "WMKK", "s321", 6], ["WSSS", "WIII", "s321", 5], ["WSSS", "VTBS", "w280", 4], ["WSSS", "VHHH", "w280", 3], ["WSSS", "RJTT", "w390", 2], ["WSSS", "EGLL", "w380", 2],
		["WSSS", "KLAX", "w390", 1], ["WSSS", "KJFK", "w390", 1], ["WSSS", "VABB", "w280", 2], ["WSSS", "OMDB", "w350", 1]],
	"SIA": [["VTBS", "WSSS", "s320", 4], ["VTBS", "VHHH", "s320", 4], ["VTBS", "WMKK", "tp90", 3], ["VTBS", "VIDP", "w350", 2], ["VTBS", "RJTT", "w350", 1], ["VTBS", "EDDM", "w350", 1]],
	"DFN": [["OMDB", "EGLL", "w380", 4], ["OMDB", "KJFK", "w380", 2], ["OMDB", "KLAX", "w390", 1], ["OMDB", "WSSS", "w350", 3], ["OMDB", "VIDP", "w350", 4], ["OMDB", "VABB", "w350", 4],
		["OMDB", "LFPG", "w380", 2], ["OMDB", "RJTT", "w390", 1], ["OMDB", "OTHH", "w350", 5], ["OMDB", "LTFM", "w350", 2], ["OMDB", "HECA", "w350", 2], ["OMDB", "SKPC", "q740", 1], ["OMDB", "SKAU", "w380", 1]],
	"PGA": [["OTHH", "EGLL", "w350", 3], ["OTHH", "VIDP", "w280", 3], ["OTHH", "WSSS", "w390", 2], ["OTHH", "KJFK", "w390", 1], ["OTHH", "OMDB", "w280", 4], ["OTHH", "HECA", "w280", 2],
		["OTHH", "VTBS", "w350", 2], ["OTHH", "EDDF", "w350", 2]],
	"MON": [["VIDP", "VABB", "s320", 10], ["VIDP", "OMDB", "s321", 4], ["VABB", "OMDB", "s321", 4], ["VIDP", "VTBS", "s321", 2], ["VABB", "WSSS", "s321", 2], ["VIDP", "OTHH", "s320", 2]],
	"BOS": [["LTFM", "EGLL", "s321", 5], ["LTFM", "LFPG", "s321", 4], ["LTFM", "EDDF", "s320", 4], ["LTFM", "LGAV", "s320", 4], ["LTFM", "HECA", "s320", 3], ["LTFM", "OMDB", "w350", 2],
		["LTFM", "UUEE", "s321", 3], ["LTFM", "KJFK", "w390", 1], ["LTFM", "VIDP", "w350", 1], ["LTFM", "RJTT", "w390", 1]],
	"NIL": [["HECA", "LGAV", "s320", 3], ["HECA", "LTFM", "s320", 3], ["HECA", "OMDB", "s320", 2], ["HECA", "EGLL", "w350", 1], ["HECA", "LFPG", "s320", 1]],
	"HSK": [["LGAV", "LTFM", "s319", 3], ["LGAV", "LIRF", "rj100", 3], ["LGAV", "HECA", "tp90", 2], ["LGAV", "EGLL", "s319", 2], ["LGAV", "LFPG", "s319", 1]],
	"TGA": [["UUEE", "LTFM", "s321", 3], ["UUEE", "ZBAA", "w350", 2], ["UUEE", "EDDB", "s320", 3], ["UUEE", "LFPG", "s320", 2], ["UUEE", "OMDB", "s321", 2], ["UUEE", "ESSA", "rj90", 2]],
	"ARC": [["RPLL", "WIII", "s319", 2], ["RPLL", "VHHH", "tp90", 2], ["WIII", "WSSS", "s319", 4], ["WIII", "WMKK", "tp90", 3], ["RPLL", "RCTP", "tp72", 2]],
	"TFX": [["KORD", "EHAM", "f4", 1], ["KJFK", "EHAM", "f4", 1], ["KORD", "KLAX", "f4", 1], ["EHAM", "LIRF", "f4", 1], ["KSDF", "PANC", "f4", 1], ["KSDF", "KORD", "f4", 1], ["PANC", "RJTT", "f4", 1], ["PANC", "KLAX", "f4", 1], ["KSDF", "EHAM", "f4", 1]],
	"WMA": [["WMIA", "SKPC", "w350", 2], ["WMIA", "KJFK", "w350", 1], ["WMIA", "SKPC", "s320", 2], ["WMIA", "WMSK", "tp72", 3], ["WMIA", "SKNG", "s320", 1],
		["WMIA", "SKSB", "s320", 1]],
}


func schedule_for_day(day: int) -> Array:
	if _schedule_cache.has(day):
		return _schedule_cache[day]
	var out := []
	var r := U.rng(U.hash_ints(world_seed, day, 5))
	for code in ROUTES.keys():
		var al: Dictionary = Airlines.get_al(code)
		var num_base := 100 + Airlines.ORDER.find(code) * 37
		var ri := 0
		for route in ROUTES[code]:
			var from: String = route[0]
			var to: String = route[1]
			var type_id: String = route[2]
			var freq: int = route[3]
			for k in freq:
				var cargo := String(al.get("kind", "")) == "cargo"
				var dep_h := r.randf_range(5.5, 22.5)
				if cargo:
					dep_h = fmod(r.randf_range(19.0, 30.0), 24.0)
				if from == to:
					dep_h = 7.0 + k * 1.8 + r.randf() * 0.5
				for leg in 2:
					var a: String = from if leg == 0 else to
					var b: String = to if leg == 0 else from
					if from == to and leg == 1:
						continue
					var t: Dictionary = AircraftTypes.get_type(type_id)
					var dist := Airports.distance_m(a, b)
					var block := 900.0 + dist / (float(t.cruise_tas) * U.KT * 0.82) + 600.0
					if from == to:
						block = 3600.0 * r.randf_range(0.8, 1.4)
					var dep := float(day) * 86400.0 + (dep_h + float(leg) * (block / 3600.0 + 1.0)) * 3600.0
					var number := num_base + ri * 6 + k * 2 + leg
					var fid := "%s%d-%d" % [al.iata, number, day]
					var f := {
						"id": fid, "number": "%s%d" % [al.iata, number], "callsign": "%s %d" % [al.callsign, number],
						"airline": code, "type": type_id, "from": a, "to": b, "dep": dep, "arr": dep + block,
						"block": block, "pax": 0 if cargo else int(AircraftTypes.seat_count(type_id) * r.randf_range(0.55, 0.98)),
						"gate": _gate_for(a, r), "cargo": cargo, "training": from == to, "status": "scheduled",
						"reg": "", "delay": 0.0,
					}
					var regs := fleet_for(code, type_id)
					if not regs.is_empty():
						f.reg = regs[U.hash_ints(number, day) % regs.size()].reg
					out.append(f)
			ri += 1
	out.sort_custom(func(x, y): return x.dep < y.dep)
	_schedule_cache[day] = out
	if _schedule_cache.size() > 6:
		var keys := _schedule_cache.keys()
		keys.sort()
		_schedule_cache.erase(keys[0])
	return out


func _gate_for(icao: String, r: RandomNumberGenerator) -> String:
	var gates := int(Airports.get_ap(icao).terminal.gates)
	if gates <= 0:
		return "Apron"
	var letters := ["A"] if gates < 8 else (["A", "B", "C", "D"] if gates >= 24 else ["A", "B"])
	var letter: String = letters[r.randi_range(0, letters.size() - 1)]
	return "%s%d" % [letter, r.randi_range(1, maxi(gates / letters.size(), 1))]


func flight_status(f: Dictionary) -> Dictionary:
	## Live status derived from the clock plus any overrides (incidents, closures, delays).
	var st := {"status": "Scheduled", "delay": 0.0, "note": ""}
	if flight_overrides.has(f.id):
		var o: Dictionary = flight_overrides[f.id]
		st.merge(o, true)
		if o.has("status") and o.status in ["Cancelled", "Diverted", "Incident"]:
			return st
	var dep: float = f.dep + float(st.delay)
	var arr: float = f.arr + float(st.delay)
	var closed_from := _closure_reason(f.from)
	var closed_to := _closure_reason(f.to)
	if clock < dep and closed_from != "":
		return {"status": "Delayed", "delay": float(airport_status[f.from].closed_until) - f.dep, "note": closed_from}
	if clock < dep and closed_to != "":
		return {"status": "Delayed", "delay": float(airport_status[f.to].closed_until) - f.dep, "note": closed_to}
	if clock < dep - 2700.0:
		st.status = "Scheduled" if st.delay <= 0.0 else "Delayed"
	elif clock < dep - 600.0:
		st.status = "Boarding"
	elif clock < dep:
		st.status = "Final call"
	elif clock < arr:
		st.status = "Departed" if clock < arr - 900.0 else "Approaching"
	elif clock < arr + 1800.0:
		st.status = "Landed"
	else:
		st.status = "Arrived"
	return st


func _closure_reason(icao: String) -> String:
	if airport_status.has(icao) and clock < float(airport_status[icao].closed_until):
		return String(airport_status[icao].reason)
	return ""


func fids(icao: String, departures: bool, count: int = 14) -> Array:
	var rows := []
	for d in [day_index() - 1, day_index(), day_index() + 1]:
		for f in schedule_for_day(d):
			if (departures and f.from == icao) or (not departures and f.to == icao):
				var tref: float = f.dep if departures else f.arr
				if tref > clock - 3600.0 and tref < clock + 14.0 * 3600.0:
					var st := flight_status(f)
					rows.append({"flight": f, "status": st, "time": tref})
	rows.sort_custom(func(x, y): return x.time < y.time)
	return rows.slice(0, count)


func airborne_flights() -> Array:
	## AI flights currently in the air (for traffic and radio chatter).
	var out := []
	for d in [day_index() - 1, day_index()]:
		for f in schedule_for_day(d):
			var st := flight_status(f)
			if st.status in ["Departed", "Approaching"]:
				out.append(f)
	return out


func set_flight_override(fid: String, data: Dictionary) -> void:
	if not flight_overrides.has(fid):
		flight_overrides[fid] = {}
	flight_overrides[fid].merge(data, true)


func close_airport(icao: String, hours: float, reason: String) -> void:
	airport_status[icao] = {"closed_until": clock + hours * 3600.0, "reason": reason}
	airport_status_changed.emit(icao)


func airport_open(icao: String) -> bool:
	return _closure_reason(icao) == ""


func _update_airports() -> void:
	for icao in airport_status.keys():
		if clock > float(airport_status[icao].closed_until) + 3600.0:
			airport_status.erase(icao)
			airport_status_changed.emit(icao)


# ------------------------------------------------------------------ population
func person(id: int) -> Dictionary:
	## Deterministic identity for a member of the population, merged with any persistent changes.
	var family := id / 5
	var role := id % 5
	var fr := U.rng(U.hash_ints(world_seed, family, 77))
	var surname: String = U.pick(fr, Names.LAST)
	var home: String = U.pick(fr, Names.HOMETOWNS)
	var parent_age := fr.randi_range(28, 62)
	var r := U.rng(U.hash_ints(world_seed, id, 13))
	var p := Names.person(r)
	p.last = surname
	p.name = String(p.first) + " " + surname
	p.home = home
	match role:
		0, 1:
			p.age = clampi(parent_age + r.randi_range(-4, 4), 22, 90)
			p.role = "partner"
		2, 3:
			p.age = clampi(parent_age - r.randi_range(22, 34), 2, 40)
			p.role = "child"
			if int(p.age) < 18:
				p.job = "student" if int(p.age) > 5 else "child"
		4:
			p.age = clampi(parent_age + r.randi_range(24, 32), 50, 96)
			p.role = "elder"
			p.job = "retired"
	p.id = id
	p.family = family
	p.frequent = id < FREQUENT_FLYERS * 5 and role <= 1 and (U.hash_ints(id, 3) % 3 == 0)
	p.status = "alive"
	p.flights = 0
	var key := str(id)
	if people_mods.has(key):
		p.merge(people_mods[key], true)
	return p


func family_of(id: int) -> Array:
	var fam := id / 5
	var out := []
	for k in 5:
		var pid := fam * 5 + k
		if pid != id:
			out.append(person(pid))
	return out


func relation_word(p: Dictionary, other: Dictionary) -> String:
	if p.role == "partner" and other.role == "partner":
		return "partner"
	if p.role == "partner" and other.role == "child":
		return "son" if other.gender == "m" else ("daughter" if other.gender == "f" else "child")
	if p.role == "child" and other.role == "partner":
		return "father" if other.gender == "m" else ("mother" if other.gender == "f" else "parent")
	if p.role == "child" and other.role == "child":
		return "brother" if other.gender == "m" else ("sister" if other.gender == "f" else "sibling")
	if other.role == "elder":
		return "grandfather" if other.gender == "m" else ("grandmother" if other.gender == "f" else "grandparent")
	if p.role == "elder":
		return "grandson" if other.gender == "m" else ("granddaughter" if other.gender == "f" else "grandchild")
	return "relative"


func modify_person(id: int, data: Dictionary) -> void:
	var key := str(id)
	if not people_mods.has(key):
		people_mods[key] = {}
	people_mods[key].merge(data, true)


func is_available(id: int) -> bool:
	var key := str(id)
	if people_mods.has(key):
		var st: String = people_mods[key].get("status", "alive")
		return st == "alive" or st == "injured_minor"
	return true


## Builds a passenger manifest for a flight: families, couples and solo travellers.
func build_manifest(flight_id: String, from: String, to: String, count: int) -> Array:
	var r := U.rng(U.hash_str(flight_id) ^ world_seed)
	var out := []
	var used := {}
	var guard := 0
	var hub_cities := [Airports.get_ap(from).city, Airports.get_ap(to).city]
	while out.size() < count and guard < count * 6:
		guard += 1
		var kind := U.pick_weighted(r, ["solo", "couple", "family", "frequent", "group"], [40, 22, 18, 10, 6])
		var base_id: int
		if kind == "frequent":
			base_id = r.randi_range(0, FREQUENT_FLYERS - 1) * 5 + r.randi_range(0, 1)
			var fp := person(base_id)
			if not (fp.home in hub_cities) and r.randf() < 0.6:
				continue
		else:
			base_id = r.randi_range(FREQUENT_FLYERS * 5, POPULATION - 6)
		var fam := base_id / 5
		var members := []
		match kind:
			"solo", "frequent":
				members = [base_id]
			"couple":
				members = [fam * 5, fam * 5 + 1]
			"family":
				members = [fam * 5, fam * 5 + 1, fam * 5 + 2]
				if r.randf() < 0.6:
					members.append(fam * 5 + 3)
				if r.randf() < 0.15:
					members.append(fam * 5 + 4)
			"group":
				members = [base_id, base_id + 5, base_id + 10]
		var group_id := out.size()
		for pid in members:
			if out.size() >= count:
				break
			if used.has(pid) or not is_available(pid):
				continue
			used[pid] = true
			var p := person(pid)
			if kind == "frequent":
				p.purpose = "business"
			elif kind == "family":
				p.purpose = U.pick(r, ["holiday", "visiting family", "wedding"])
			else:
				p.purpose = U.pick(r, Names.PURPOSES)
			p.group = group_id
			p.group_kind = kind
			out.append(p)
	return out


func record_passenger_flight(pid: int, flight_no: String) -> void:
	var p := person(pid)
	modify_person(pid, {"flights": int(p.flights) + 1, "last_flight": flight_no})


# ------------------------------------------------------------------ background world events
var _template_sched: Array = []


func _maybe_world_events(t0: float, t1: float) -> void:
	# Roughly one minor aviation story every few days somewhere in the world.
	var d0 := int(floor(t0 / 21600.0))
	var d1 := int(floor(t1 / 21600.0))
	for slot in range(d0 + 1, d1 + 1):
		var r := U.rng(U.hash_ints(world_seed, slot, 404))
		if r.randf() < 0.11:
			# the timetable repeats every day: reuse one day's schedule instead of building a new
			# one for every simulated day (long time skips stay fast)
			var day_i := int(slot * 21600.0 / 86400.0)
			var sched: Array = _schedule_cache.get(day_i, [])
			if sched.is_empty():
				if _template_sched.is_empty():
					_template_sched = schedule_for_day(day_i)
				sched = _template_sched
			if sched.is_empty():
				continue
			var f: Dictionary = sched[r.randi_range(0, sched.size() - 1)]
			if f.training:
				continue
			var kinds := ["medical_diversion", "bird_strike_return", "turbulence_injuries", "tech_return", "unruly_passenger", "weather_diversion", "record_traffic", "new_route"]
			var kind: String = U.pick_weighted(r, kinds, [20, 14, 10, 14, 12, 12, 6, 6])
			var key := "W%d" % slot
			if key in world_events:
				continue
			world_events.append(key)
			News.background_story(kind, f, float(slot) * 21600.0 + r.randf() * 21600.0, r.randi())


# ------------------------------------------------------------------ persistence
func serialize() -> Dictionary:
	return {
		"seed": world_seed, "clock": clock, "fleet": fleet, "airport_status": airport_status,
		"people_mods": people_mods, "flight_overrides": flight_overrides, "world_events": world_events,
	}


func deserialize(d: Dictionary) -> void:
	if d.is_empty():
		return
	world_seed = int(d.get("seed", world_seed))
	clock = float(d.get("clock", clock))
	fleet = d.get("fleet", fleet)
	airport_status = d.get("airport_status", {})
	people_mods = d.get("people_mods", {})
	flight_overrides = d.get("flight_overrides", {})
	world_events = d.get("world_events", [])
	_schedule_cache.clear()
