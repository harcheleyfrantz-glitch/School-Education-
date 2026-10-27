class_name Checklists
extends RefCounted
## Normal and abnormal checklists. Items verify themselves from the aircraft state where they
## can; the rest are confirmed by the pilot (click). Completion feeds the debrief score.

const NORMAL_JET := [
	["BEFORE START", [["Parking brake", "SET", "park_set"], ["Doors", "CLOSED", "doors_closed"], ["Beacon", "ON", "beacon_on"], ["Transponder code", "SET", "xpdr_set"], ["Seat belt signs", "ON", "belts_on"], ["Fuel quantity", "CHECKED", "manual"]]],
	["AFTER START", [["Engines", "RUNNING", "engines_running"], ["Flaps", "TAKEOFF", "flaps_takeoff"], ["Pitch trim", "SET", "trim_set"], ["Ground spoilers", "ARMED", "spoilers_armed"], ["Anti-ice", "AS REQUIRED", "manual"]]],
	["BEFORE TAKEOFF", [["Takeoff clearance", "RECEIVED", "to_clearance"], ["Cabin", "SECURE", "cabin_secure"], ["Autobrake", "RTO", "autobrake_rto"], ["Landing lights", "ON", "landing_on"], ["Strobes", "ON", "strobe_on"], ["Takeoff config", "NORMAL", "config_ok"]]],
	["AFTER TAKEOFF", [["Landing gear", "UP", "gear_up"], ["Flaps", "UP", "flaps_up"], ["Autopilot", "AS REQUIRED", "manual"]]],
	["APPROACH", [["Approach", "BRIEFED", "manual"], ["Altimeters", "QNH SET", "below_transition"], ["Autobrake", "SET", "autobrake_landing"], ["Seat belt signs", "ON", "belts_on"], ["Landing lights", "ON", "landing_on"]]],
	["LANDING", [["Landing gear", "DOWN 3 GREEN", "gear_down"], ["Flaps", "LANDING", "flaps_landing"], ["Ground spoilers", "ARMED", "spoilers_armed"], ["Landing clearance", "RECEIVED", "land_clearance"]]],
	["AFTER LANDING", [["Ground spoilers", "RETRACTED", "spoilers_in"], ["Flaps", "UP", "flaps_up"], ["Strobes", "OFF", "strobe_off"], ["Landing lights", "OFF", "landing_off"]]],
	["SHUTDOWN", [["Parking brake", "SET", "park_set"], ["Engines", "OFF", "engines_off"], ["Seat belt signs", "OFF", "belts_off"], ["Beacon", "OFF", "beacon_off"]]],
]

const NORMAL_GA := [
	["BEFORE START", [["Parking brake", "SET", "park_set"], ["Master switch", "ON", "battery_on"], ["Fuel selector", "BOTH", "manual"], ["Beacon", "ON", "beacon_on"]]],
	["RUN-UP", [["Engine", "RUNNING", "engines_running"], ["Flight controls", "FREE AND CORRECT", "manual"], ["Trim", "TAKEOFF", "trim_set"], ["Magnetos", "CHECKED", "manual"]]],
	["BEFORE TAKEOFF", [["Flaps", "10", "flaps_takeoff"], ["Landing light", "ON", "landing_on"], ["Strobes", "ON", "strobe_on"], ["Doors and windows", "LATCHED", "doors_closed"]]],
	["CLIMB", [["Flaps", "UP", "flaps_up"], ["Mixture", "AS REQUIRED", "manual"]]],
	["LANDING", [["Mixture", "RICH", "manual"], ["Flaps", "AS REQUIRED", "flaps_down"], ["Landing light", "ON", "landing_on"]]],
	["SHUTDOWN", [["Parking brake", "SET", "park_set"], ["Mixture", "IDLE CUT-OFF", "engines_off"], ["Master switch", "OFF", "battery_off"]]],
]

const ABNORMAL := {
	"eng_fire": ["ENG FIRE", [["Thrust lever (affected)", "IDLE", "aff_idle"], ["Engine master (affected)", "OFF", "aff_off"], ["Fire push button", "PUSH", "manual"], ["Agent 1", "DISCHARGE", "manual"], ["Land", "AT NEAREST SUITABLE AIRPORT", "manual"]]],
	"eng_fail": ["ENG FAILURE", [["Thrust lever (affected)", "IDLE", "aff_idle"], ["Engine master (affected)", "OFF", "aff_off"], ["Rudder trim", "AS REQUIRED", "manual"], ["Land", "AT NEAREST SUITABLE AIRPORT", "manual"]]],
	"cabin_alt": ["CABIN ALTITUDE / EMERGENCY DESCENT", [["Crew oxygen masks", "ON", "masks_on"], ["Signs", "ON", "belts_on"], ["Emergency descent", "INITIATE", "descending"], ["Pax oxygen masks", "MANUAL ON", "pax_masks"], ["Squawk", "7700", "squawk7700"]]],
	"smoke": ["SMOKE / FIRE", [["Crew oxygen masks", "ON", "masks_on"], ["Divert", "INITIATE", "manual"], ["Cabin crew", "FIGHT FIRE", "manual"], ["Land", "ASAP", "manual"]]],
	"gear_unsafe": ["L/G NOT DOWNLOCKED", [["Landing gear lever", "RECYCLE", "manual"], ["Gravity extension", "PERFORM", "manual"], ["Go around", "IF NEEDED", "manual"]]],
	"stall": ["STALL RECOVERY", [["Nose", "DOWN", "nose_down"], ["Thrust", "AS REQUIRED", "manual"], ["Wings", "LEVEL", "wings_level"]]],
}

var lists: Array
var index := 0
var done := {}          # "list:item" -> true
var abnormal_id := ""
var completions := {}   # list name -> fraction completed when the phase passed


func _init(category: String) -> void:
	lists = NORMAL_GA if category == "trainer" else NORMAL_JET


func current() -> Array:
	if abnormal_id != "":
		return ABNORMAL[abnormal_id]
	return lists[clampi(index, 0, lists.size() - 1)]


func select(i: int) -> void:
	index = clampi(i, 0, lists.size() - 1)


func show_abnormal(id: String) -> void:
	if ABNORMAL.has(id):
		abnormal_id = id


func confirm(item: int) -> void:
	var cl := current()
	done["%s:%d" % [cl[0], item]] = true


func evaluate(ac: Aircraft, session: Node) -> Array:
	## Returns [[label, value, state]] with state "done" | "open" | "manual".
	var cl := current()
	var out := []
	var items: Array = cl[1]
	for i in items.size():
		var it: Array = items[i]
		var key := "%s:%d" % [cl[0], i]
		var ok := false
		if String(it[2]) == "manual":
			ok = done.has(key)
		else:
			ok = check(String(it[2]), ac, session) or done.has(key)
		if ok:
			done[key] = true
		out.append([it[0], it[1], "done" if ok else ("manual" if String(it[2]) == "manual" else "open")])
	return out


func fraction(name: String) -> float:
	for cl in lists:
		if cl[0] == name:
			var n := 0
			var items: Array = cl[1]
			for i in items.size():
				if done.has("%s:%d" % [name, i]):
					n += 1
			return float(n) / maxf(items.size(), 1)
	return 0.0


func check(key: String, ac: Aircraft, session: Node) -> bool:
	var sys := ac.sys
	var atc: AtcController = session.get("atc")
	match key:
		"park_set": return sys.parking_brake
		"doors_closed": return not bool(session.call("any_door_open")) if session.has_method("any_door_open") else true
		"beacon_on": return sys.lights.get("beacon", false)
		"beacon_off": return not sys.lights.get("beacon", false)
		"xpdr_set": return sys.squawk != "2000" and sys.squawk != "7000"
		"belts_on": return sys.lights.get("seatbelt", false)
		"belts_off": return not sys.lights.get("seatbelt", false)
		"engines_running": return sys.running_engines() == sys.n_eng
		"engines_off": return sys.running_engines() == 0
		"flaps_takeoff": return sys.flap_lever >= 1 and sys.flap_lever < ac.spec.flaps.size() - 1
		"flaps_up": return sys.flap_lever == 0
		"flaps_down": return sys.flap_lever >= 1
		"flaps_landing": return sys.flap_lever >= ac.spec.flaps.size() - 2
		"trim_set": return absf(sys.trim) < 0.45
		"spoilers_armed": return sys.ground_spoilers_armed or not bool(ac.spec.spoilers)
		"spoilers_in": return sys.spoiler_lever < 0.05
		"to_clearance": return atc != null and bool(atc.clearance.takeoff)
		"land_clearance": return atc != null and bool(atc.clearance.landing)
		"cabin_secure":
			var cp: CabinPeople = session.get("people")
			return cp == null or cp.count_state("seated") >= cp.pax.size() - cp.count_state("away")
		"autobrake_rto": return sys.autobrake == 4 or ac.spec.category in ["trainer", "turboprop"]
		"autobrake_landing": return sys.autobrake in [1, 2, 3] or ac.spec.category in ["trainer", "turboprop"]
		"landing_on": return sys.lights.get("landing", false)
		"landing_off": return not sys.lights.get("landing", false)
		"strobe_on": return sys.lights.get("strobe", false)
		"strobe_off": return not sys.lights.get("strobe", false)
		"config_ok": return sys.config_warning == ""
		"gear_up": return not sys.gear_down_cmd or not bool(ac.spec.gear_retract)
		"gear_down": return sys.gear_down_cmd and sys.gear_pos[0] > 0.99 and sys.gear_pos[1] > 0.99 and sys.gear_pos[2] > 0.99
		"below_transition": return ac.fdm.pos.y < 5500.0 * U.FT + float(ac.ground_elev)
		"battery_on": return sys.battery
		"battery_off": return not sys.battery
		"masks_on": return sys.pilot_mask
		"descending": return ac.fdm.vel.y < -10.0 or ac.fdm.pos.y < 3300.0
		"pax_masks": return sys.masks_deployed
		"squawk7700": return sys.squawk == "7700"
		"nose_down": return ac.fdm.pitch_deg() < 5.0
		"wings_level": return absf(ac.fdm.bank_deg()) < 10.0
		"aff_idle":
			for i in sys.n_eng:
				if (sys.eng[i].fire or sys.eng[i].failed != "") and float(sys.throttle[i]) > 0.05:
					return false
			return true
		"aff_off":
			for i in sys.n_eng:
				if (sys.eng[i].fire or sys.eng[i].failed != "") and not sys.eng[i].cutoff:
					return false
			return true
	return false
