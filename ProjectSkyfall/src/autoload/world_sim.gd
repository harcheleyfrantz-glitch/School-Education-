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
	"SKF": [["SKPC", "SKNG", "s320", 4], ["SKPC", "SKOF", "s320", 3], ["SKPC", "SKSB", "s320", 3], ["SKPC", "WMIA", "w350", 3],
		["SKPC", "WMIA", "s320", 2], ["SKPC", "SKHP", "rj90", 2], ["SKPC", "SKRV", "rj90", 3], ["SKPC", "SKIM", "rj90", 2],
		["SKPC", "WMSK", "rj90", 1], ["SKNG", "WMIA", "w350", 1]],
	"CLK": [["SKPC", "SKIM", "tp72", 4], ["SKPC", "SKRV", "tp72", 3], ["SKSB", "SKIM", "tp72", 2], ["SKSB", "SKOF", "rj90", 2],
		["SKPC", "SKHP", "tp72", 2], ["SKPC", "SKSB", "rj90", 2], ["SKOF", "SKHP", "tp72", 1]],
	"LMN": [["SKNG", "SKPC", "s320", 4], ["SKNG", "SKSB", "s320", 2], ["SKNG", "SKOF", "s320", 2], ["SKPC", "WMIA", "s320", 2],
		["SKNG", "WMIA", "s320", 1], ["SKPC", "SKSB", "s320", 2]],
	"NWC": [["SKNG", "WMIA", "f4", 1], ["SKNG", "SKPC", "f4", 2], ["SKNG", "SKOF", "f4", 1]],
	"APX": [["SKPC", "SKSB", "bj6", 2], ["SKSB", "WMIA", "bj6", 1], ["SKPC", "SKHP", "bj6", 1], ["SKPC", "SKIM", "bj6", 1]],
	"HFA": [["SKWF", "SKWF", "t172", 6], ["SKWF", "SKPC", "t172", 2], ["SKWF", "SKOF", "t172", 1], ["SKWF", "SKSB", "t172", 1]],
	"AUR": [["WMSK", "SKPC", "w380", 2], ["WMIA", "SKPC", "w380", 1], ["WMSK", "WMIA", "s321", 3], ["WMSK", "SKNG", "w350", 2], ["WMIA", "SKSB", "w350", 1]],
	"PEL": [["SKIM", "SKSB", "tp50", 4], ["SKIM", "SKOF", "tp50", 2], ["SKSB", "SKHP", "tp50", 2], ["SKIM", "SKPC", "tp72", 2], ["SKSB", "SKIM", "tp72", 2]],
	"VTX": [["SKOF", "SKPC", "s321", 4], ["SKOF", "SKNG", "s321", 2], ["SKHP", "SKPC", "s320", 3], ["SKOF", "WMIA", "s321", 1], ["SKHP", "SKRV", "rj70", 3]],
	"WMA": [["WMIA", "SKPC", "w350", 2], ["WMIA", "SKPC", "s320", 2], ["WMIA", "WMSK", "tp72", 3], ["WMIA", "SKNG", "s320", 1],
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
				var cargo = code == "NWC"
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
	var letter = "A" if gates < 8 else ["A", "B"][r.randi_range(0, 1)]
	return "%s%d" % [letter, r.randi_range(1, gates)]


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
func _maybe_world_events(t0: float, t1: float) -> void:
	# Roughly one minor aviation story every few days somewhere in the world.
	var d0 := int(floor(t0 / 21600.0))
	var d1 := int(floor(t1 / 21600.0))
	for slot in range(d0 + 1, d1 + 1):
		var r := U.rng(U.hash_ints(world_seed, slot, 404))
		if r.randf() < 0.11:
			var sched := schedule_for_day(int(slot * 21600.0 / 86400.0))
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
