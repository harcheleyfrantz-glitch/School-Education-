class_name EventDirector
extends Node
## Schedules and runs contextual events for one flight. Probabilities depend on the event
## setting, aircraft condition, airline maintenance standards, weather, route and phase.
## Every event is logged for the debrief, the investigation and the news.

signal event_started(ev: Dictionary)
signal decision_needed(ev: Dictionary, choices: Array)
signal message(text: String, kind: String)

const CATALOG := {
	# id: [phases, base chance per flight (realistic), severity 0..1, label]
	"turbulence": [["climb", "cruise", "descent"], 0.45, 0.15, "Turbulence"],
	"headwind": [["cruise"], 0.2, 0.05, "Stronger headwinds than forecast"],
	"storm_route": [["cruise", "descent"], 0.12, 0.3, "Thunderstorm on the route"],
	"medical": [["cruise", "climb", "descent"], 0.05, 0.35, "Medical emergency"],
	"disruptive": [["cruise"], 0.03, 0.25, "Disruptive passenger"],
	"slot_delay": [["gate"], 0.12, 0.05, "Departure slot delay"],
	"runway_change": [["descent", "approach"], 0.1, 0.1, "Runway change"],
	"tech_warning": [["climb", "cruise"], 0.08, 0.2, "Technical caution"],
	"engine_failure": [["takeoff", "climb", "cruise"], 0.006, 0.8, "Engine failure"],
	"engine_fire": [["takeoff", "climb", "cruise"], 0.003, 0.9, "Engine fire"],
	"electrical": [["cruise"], 0.008, 0.5, "Electrical failure"],
	"hydraulic": [["climb", "cruise"], 0.008, 0.5, "Hydraulic failure"],
	"pressurization": [["cruise"], 0.01, 0.7, "Loss of cabin pressure"],
	"smoke": [["cruise"], 0.004, 0.85, "Smoke in the cabin"],
	"gear_unsafe": [["approach"], 0.01, 0.6, "Landing gear unsafe indication"],
	"bird_strike": [["takeoff", "climb", "approach"], 0.02, 0.4, "Bird strike"],
	"windshear": [["approach"], 0.02, 0.6, "Windshear"],
	"icing": [["climb", "cruise", "descent"], 0.05, 0.3, "Airframe icing"],
	"fuel_leak": [["cruise"], 0.004, 0.6, "Fuel leak"],
	"crosswind": [["approach"], 0.12, 0.2, "Strong gusty crosswind"],
	"dest_closed": [["cruise"], 0.015, 0.4, "Destination closed"],
	"maintenance": [["gate"], 0.15, 0.1, "Maintenance finding"],
}

var session: Node
var ac: Aircraft
var scheduled: Array = []
var active: Array = []
var history: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var rate_scale := 1.0


func setup(sess: Node, aircraft: Aircraft, context: Dictionary) -> void:
	session = sess
	ac = aircraft
	_rng.seed = U.hash_str(String(context.get("flight_id", "")) + str(WorldSim.clock))
	match String(Game.settings.get("event_rate", "realistic")):
		"off":
			rate_scale = 0.0
		"frequent":
			rate_scale = 4.0
		_:
			rate_scale = 1.0
	if context.has("force_event"):
		_schedule(String(context.force_event), 1.0)
	if rate_scale <= 0.0:
		return
	var rec: Dictionary = context.get("aircraft_record", {})
	var condition := float(rec.get("condition", 0.9))
	var standards := float(Airlines.get_al(ac.airline).get("standards", 0.8))
	var weather: Dictionary = context.get("weather", {})
	var stormy := String(weather.get("precip", "")) == "thunderstorm"
	var hours := float(context.get("block_hours", 1.5))
	for id in CATALOG.keys():
		var info: Array = CATALOG[id]
		var p := float(info[1]) * rate_scale
		var technical = id in ["tech_warning", "engine_failure", "engine_fire", "electrical", "hydraulic", "pressurization", "smoke", "gear_unsafe", "fuel_leak", "maintenance"]
		if technical:
			p *= lerpf(2.2, 0.6, condition) * lerpf(1.6, 0.7, standards)
		if id in ["turbulence", "storm_route", "windshear", "icing"] and stormy:
			p *= 2.5
		if id in ["medical", "disruptive", "turbulence", "headwind"]:
			p *= clampf(hours / 1.5, 0.5, 3.0)
		if ac.spec.category == "trainer" and id in ["medical", "disruptive", "slot_delay", "pressurization", "smoke", "dest_closed"]:
			p *= 0.1
		if ac.spec.category == "cargo" and id in ["medical", "disruptive"]:
			p = 0.0
		if _rng.randf() < clampf(p, 0.0, 0.95):
			_schedule(id, _rng.randf())


func _schedule(id: String, frac: float) -> void:
	var info: Array = CATALOG[id]
	var phases: Array = info[0]
	var ph: String = phases[_rng.randi() % phases.size()]
	scheduled.append({"id": id, "phase": ph, "frac": frac, "label": info[3], "severity": float(info[2]),
		"delay": _rng.randf_range(20.0, 600.0) if ph in ["cruise"] else _rng.randf_range(5.0, 90.0), "started": false})


func phase_changed(ph: String) -> void:
	for ev in scheduled:
		if ev.phase == ph and not ev.started:
			ev.armed_at = _t


func _process(delta: float) -> void:
	if ac == null or ac.crashed_state:
		return
	_t += delta
	var ph := String(session.get("phase"))
	for ev in scheduled:
		if ev.started or not ev.has("armed_at"):
			continue
		if _phase_family(ph) != ev.phase:
			continue
		if _t - float(ev.armed_at) >= float(ev.delay) or (ev.phase in ["takeoff", "approach", "gate"] and _t - float(ev.armed_at) > 3.0):
			if _conditions_ok(ev):
				ev.started = true
				_start(ev)
	for a in active:
		_tick(a, delta)


func _phase_family(ph: String) -> String:
	match ph:
		"preflight", "boarding", "gate":
			return "gate"
		"takeoff_roll", "takeoff", "initial_climb":
			return "takeoff"
		"climb":
			return "climb"
		"cruise":
			return "cruise"
		"descent":
			return "descent"
		"approach", "final":
			return "approach"
	return ph


func _conditions_ok(ev: Dictionary) -> bool:
	match String(ev.id):
		"bird_strike":
			return ac.ra < 900.0 and not ac.fdm.on_ground and ac.fdm.ias > 40.0
		"engine_failure", "engine_fire":
			return not ac.fdm.on_ground or ac.fdm.ias / U.KT > 60.0
		"icing":
			return ac.oat < 3.0
		"pressurization":
			return ac.fdm.pos.y > 6000.0
	return true


# ---------------------------------------------------------------- effects
func _start(ev: Dictionary) -> void:
	ev.t0 = _t
	ev.time = WorldSim.clock
	ev.alt = ac.fdm.pos.y
	ev.place = Geo.place_name(ac.world_x(), ac.world_z())
	active.append(ev)
	history.append(ev)
	event_started.emit(ev)
	var cp: CabinPeople = session.get("people")
	match String(ev.id):
		"turbulence":
			ev.level = _rng.randf_range(0.35, 0.65) if _rng.randf() < 0.8 else _rng.randf_range(0.75, 1.0)
			ev.duration = _rng.randf_range(60.0, 300.0)
			session.set("turb_boost", ev.level)
			message.emit("Turbulence ahead reported by preceding traffic." if ev.level < 0.7 else "Severe turbulence encountered!", "caution" if ev.level < 0.7 else "warning")
		"headwind":
			session.set("wind_bias", _rng.randf_range(25.0, 60.0))
			message.emit("Dispatch: winds aloft stronger than forecast, check fuel.", "info")
		"storm_route":
			if session.has_method("place_storm_ahead"):
				session.call("place_storm_ahead")
			message.emit("Weather radar: thunderstorm cell ahead on the route.", "caution")
		"medical":
			var p := _random_pax(cp)
			if p.is_empty():
				return
			var conds := ["is unresponsive with chest pain", "is having a severe allergic reaction", "has collapsed and is struggling to breathe", "is having a seizure", "is in labour"]
			ev.person = p.get("id", -1)
			ev.person_name = p.get("name", "a passenger")
			ev.seat = p.seat.id
			ev.condition = conds[_rng.randi() % conds.size()]
			ev.critical = _rng.randf() < 0.5
			p.injury = "medical"
			if cp:
				for q in cp.pax:
					if absf(float(q.seat.pos.z) - float(p.seat.pos.z)) < 2.5:
						q.fear = clampf(float(q.fear) + 0.25, 0.0, 1.0)
			decision_needed.emit(ev, [["divert", "Divert to the nearest airport"], ["continue", "Continue to destination with medical support"]])
			message.emit("Cabin crew: passenger in %s %s. A doctor on board is helping." % [ev.seat, ev.condition], "warning")
		"disruptive":
			var p2 := _random_pax(cp)
			if p2.is_empty():
				return
			ev.person = p2.get("id", -1)
			ev.person_name = p2.get("name", "a passenger")
			ev.seat = p2.seat.id
			p2.anger = 1.0
			decision_needed.emit(ev, [["police", "Request police on arrival"], ["divert", "Divert and offload"], ["restrain", "Crew restrain the passenger"]])
			message.emit("Cabin crew: an aggressive passenger in %s is threatening others." % ev.seat, "warning")
		"slot_delay":
			ev.minutes = _rng.randi_range(8, 45)
			message.emit("ATC: expect start-up in %d minutes due to flow control." % ev.minutes, "info")
			session.set("slot_delay_min", ev.minutes)
		"runway_change":
			if session.has_method("change_arrival_runway"):
				session.call("change_arrival_runway")
			message.emit("ATC: runway change due to wind shift. Re-brief the approach.", "info")
		"tech_warning":
			var w = ["pack", "gen", "pitot"][_rng.randi() % 3]
			ac.sys.fail(w, _rng.randi_range(0, 1))
			ev.system = w
			message.emit("Caution on the upper display. Run the abnormal checklist.", "caution")
		"engine_failure":
			var i := _rng.randi_range(0, ac.sys.n_eng - 1)
			ac.sys.fail("eng_seize" if _rng.randf() < 0.3 else "eng_flameout", i)
			ev.engine = i
			message.emit("ENGINE %d FAILURE" % (i + 1), "warning")
		"engine_fire":
			var j := _rng.randi_range(0, ac.sys.n_eng - 1)
			ac.sys.fail("eng_fire", j)
			ev.engine = j
			message.emit("ENGINE %d FIRE" % (j + 1), "warning")
		"electrical":
			ac.sys.fail("gen", 0)
			if _rng.randf() < 0.3:
				ac.sys.fail("gen", 1)
			message.emit("Electrical generator failure.", "caution")
		"hydraulic":
			ac.sys.fail("hyd", _rng.randi_range(0, 1))
			message.emit("Hydraulic system pressure loss.", "caution")
		"pressurization":
			var rapid := _rng.randf() < 0.35
			ac.sys.fail("press_rapid" if rapid else "press_slow")
			ev.rapid = rapid
			if rapid and cp:
				cp.on_shock(0.8, "decompression")
			message.emit("CABIN PRESSURE LOSS" + (" - RAPID DECOMPRESSION" if rapid else ""), "warning")
		"smoke":
			ac.sys.fail("smoke")
			if cp:
				cp.on_shock(0.6, "smoke")
			message.emit("Cabin crew: smoke from the rear lavatory!", "warning")
		"gear_unsafe":
			ac.sys.fail("gear_unsafe", _rng.randi_range(0, 2))
			message.emit("L/G GEAR NOT DOWNLOCKED", "warning")
		"bird_strike":
			var k := _rng.randi_range(0, ac.sys.n_eng - 1)
			var bad := _rng.randf() < 0.35
			if bad:
				ac.sys.fail("eng_damage" if _rng.randf() < 0.7 else "eng_flameout", k)
			if cp:
				cp.on_shock(0.5, "bang")
			ev.engine = k
			ev.damaging = bad
			message.emit("Loud bang! Bird strike" + (" - engine %d damaged" % (k + 1) if bad else ""), "warning" if bad else "caution")
		"windshear":
			session.set("windshear", 1.0)
			message.emit("WINDSHEAR AHEAD", "warning")
		"icing":
			session.set("icing_boost", 1.0)
			message.emit("Icing conditions. Check anti-ice.", "caution")
		"fuel_leak":
			ac.sys.fail("fuel_leak")
			message.emit("Fuel quantity dropping faster than planned.", "caution")
		"crosswind":
			session.set("crosswind_boost", _rng.randf_range(12.0, 25.0))
			message.emit("ATIS: wind gusting, strong crosswind on the runway.", "caution")
		"dest_closed":
			var arr: String = String(session.get("arr_icao"))
			WorldSim.close_airport(arr, 2.0, ["a disabled aircraft on the runway", "a security alert", "a runway inspection", "fog below minima"][_rng.randi() % 4])
			decision_needed.emit(ev, [["divert", "Divert to the alternate"], ["hold", "Hold and wait"]])
			message.emit("ATC: %s is closed. State intentions." % Airports.get_ap(arr).short, "warning")
		"maintenance":
			var finding = ["a worn main tyre", "a hydraulic seep on the nose gear", "a cracked landing light lens", "an inoperative APU generator"][_rng.randi() % 4]
			ev.finding = finding
			decision_needed.emit(ev, [["fix", "Ask engineering to fix it (delay)"], ["mel", "Dispatch under the MEL"]])
			message.emit("Engineer: during the walkaround we found %s." % finding, "info")


func _tick(ev: Dictionary, delta: float) -> void:
	match String(ev.id):
		"turbulence":
			if _t - float(ev.t0) > float(ev.duration):
				session.set("turb_boost", 0.0)
				active.erase(ev)
		"windshear":
			if _t - float(ev.t0) > 25.0:
				session.set("windshear", 0.0)
				active.erase(ev)
		_:
			if _t - float(ev.t0) > 1.0 and not ev.id in ["medical", "disruptive"]:
				active.erase(ev)


func resolve(ev: Dictionary, choice: String) -> void:
	ev.choice = choice
	match String(ev.id):
		"medical":
			if choice == "divert" and session.has_method("divert_nearest"):
				session.call("divert_nearest", "medical emergency")
			ev.outcome_bonus = 0.35 if choice == "divert" else 0.0
		"disruptive":
			if choice == "divert" and session.has_method("divert_nearest"):
				session.call("divert_nearest", "disruptive passenger")
		"dest_closed":
			if choice == "divert" and session.has_method("divert_alternate"):
				session.call("divert_alternate")
		"maintenance":
			if choice == "fix":
				session.set("slot_delay_min", int(session.get("slot_delay_min")) + _rng.randi_range(20, 50))
	active.erase(ev)


func _random_pax(cp: CabinPeople) -> Dictionary:
	if cp == null:
		return {}
	var seated := []
	for p in cp.pax:
		if p.state == "seated":
			seated.append(p)
	if seated.is_empty():
		return {}
	return seated[_rng.randi() % seated.size()]
