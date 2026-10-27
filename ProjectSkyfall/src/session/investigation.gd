class_name Investigation
extends RefCounted
## Accident investigation. Reads the flight data recorder, the cockpit voice transcript, the
## event log, ATC deviations, the aircraft's maintenance record and the conditions, and writes a
## report: findings, a probable cause, contributing factors, how responsibility is shared and
## safety recommendations. Its conclusions drive the career consequences and the news coverage.

# sample layout written by FlightRecorder
const S_T := 0
const S_ALT := 3
const S_IAS := 4
const S_VS := 5
const S_PITCH := 6
const S_BANK := 7
const S_THR := 9
const S_FLAP := 10
const S_GEAR := 11
const S_AP := 12
const S_NZ := 14


static func analyse(d: Dictionary) -> Dictionary:
	var crash: Dictionary = d.get("crash", {})
	var rec: Dictionary = d.get("recorder", {})
	var samples: Array = rec.get("samples", [])
	var marks: Array = rec.get("events", [])
	var events: Array = d.get("events", [])
	var devs: Array = d.get("deviations", [])
	var incidents: Array = d.get("incidents", [])
	var spec := AircraftTypes.get_type(String(d.get("type", "s320")))
	var findings: Array = []
	var factors: Array = []
	var recs: Array = []
	var share := {"pilot": 0.0, "maintenance": 0.0, "weather": 0.0, "atc": 0.0, "manufacturer": 0.0}
	var negligent := false
	var t_end: float = samples[samples.size() - 1][S_T] if not samples.is_empty() else 0.0
	var last := []
	for s in samples:
		if float(s[S_T]) > t_end - 75.0:
			last.append(s)
	# ---- flight data analysis over the final 75 seconds
	var vs1 := float(spec.vs1)
	var vs0 := float(spec.vs0)
	var stalled := false
	var overspeed := false
	var max_bank := 0.0
	var min_ias := 999.0
	var max_nz := 1.0
	var min_nz := 1.0
	var ap_off_at := -1.0
	var prev_ap := -1
	for s2 in last:
		var flap := int(s2[S_FLAP])
		var vstall := vs1 if flap == 0 else lerpf(vs1, vs0, clampf(float(flap) / maxf(spec.flaps.size() - 1, 1), 0.0, 1.0))
		if float(s2[S_IAS]) < vstall * 1.0 and float(s2[S_PITCH]) > 6.0 and float(s2[S_IAS]) > 20.0:
			stalled = true
		if float(s2[S_IAS]) > float(spec.vmo) + 15.0:
			overspeed = true
		max_bank = maxf(max_bank, absf(float(s2[S_BANK])))
		min_ias = minf(min_ias, float(s2[S_IAS]))
		max_nz = maxf(max_nz, float(s2[S_NZ]))
		min_nz = minf(min_nz, float(s2[S_NZ]))
		if prev_ap == 1 and int(s2[S_AP]) == 0:
			ap_off_at = float(s2[S_T])
		prev_ap = int(s2[S_AP])
	# sustained hand-flown dive: autopilot off, nose well down, descending fast, no recovery
	var dive_s := 0.0
	for s3 in last:
		if int(s3[S_AP]) == 0 and float(s3[S_PITCH]) < -5.0 and float(s3[S_VS]) < -20.0:
			dive_s += 0.5
	var ev_ids := []
	for e in events:
		ev_ids.append(String(e.get("id", "")))
	var ditch := bool(crash.get("ditching", false))
	var breakup := String(crash.get("breakup", ""))
	var engines_running := int(crash.get("engines_running", 2))
	var fuel := float(crash.get("fuel_kg", 1000.0))
	var gear_down := bool(crash.get("gear_down", true))
	var vs_fpm := float(crash.get("vs_fpm", 0.0))
	var speed_kt := float(crash.get("speed_kt", 0.0))
	var surface := String(crash.get("surface", "terrain"))
	var on_runway := surface == "runway"
	var phase := String(d.get("phase", ""))
	var outcome := String(d.get("outcome", "crashed"))
	# ---- probable cause, most specific first
	var cause := ""
	if breakup != "":
		var glim := 3.8 if String(spec.category) == "trainer" else 2.5
		if max_nz > glim + 0.4 or overspeed or breakup.contains("overload") or breakup.contains("dive speed"):
			cause = "In-flight structural failure after the airframe was flown beyond its design load and speed limits."
			share.pilot += 0.8
			negligent = true
		else:
			cause = "In-flight structural failure originating from pre-existing damage."
			share.maintenance += 0.7
			share.manufacturer += 0.2
	elif "engine_fire" in ev_ids or "smoke" in ev_ids:
		cause = "In-flight fire that could not be contained, leading to loss of the aircraft."
		share.maintenance += 0.5
		share.manufacturer += 0.2
	elif fuel < 60.0 and engines_running == 0:
		cause = "Fuel exhaustion and total loss of engine power."
		share.pilot += 0.85
		negligent = true
		findings.append("The aircraft departed with %d kg less fuel than the planned minimum." % int(maxf(float(d.get("fuel_planned", 0.0)) - float(d.get("fuel_start", 0.0)), 0.0)) if float(d.get("fuel_start", 0.0)) < float(d.get("fuel_planned", 0.0)) else "Fuel was consumed faster than planned and no diversion was made in time.")
	elif ditch:
		cause = "Ditching on water following %s." % ("a loss of engine power" if engines_running < int(spec.engine_count) else "the crew's decision to land on water")
		share.pilot += 0.2
	elif stalled:
		cause = "Loss of control in flight following an aerodynamic stall."
		share.pilot += 0.75
		findings.append("Airspeed decayed to %d kt, below the stall speed for the configuration." % int(min_ias))
		if ap_off_at >= 0.0:
			findings.append("The autopilot disconnected %d seconds before impact." % int(t_end - ap_off_at))
	elif dive_s > 8.0 and engines_running > 0 and not on_runway:
		cause = "The aircraft was flown into the ground in a steep, sustained descent with the autopilot disengaged; no recovery was attempted."
		share.pilot += 0.9
		negligent = true
		findings.append("For %d seconds before impact the aircraft descended at more than 4,000 ft/min with the nose %d° down." % [int(dive_s), int(absf(float(crash.get("pitch", 0.0))))])
		findings.append("The flight data show sustained nose-down control inputs and no attempt to level off.")
		if ap_off_at >= 0.0:
			findings.append("The autopilot was disconnected %d seconds before impact." % int(t_end - ap_off_at))
	elif not on_runway and engines_running > 0 and absf(float(crash.get("bank", 0.0))) < 30.0 and float(crash.get("pitch", 0.0)) > -15.0 and not gear_down:
		cause = "Controlled flight into terrain: an airworthy aircraft was flown into the ground."
		share.pilot += 0.8
		negligent = true
	elif on_runway and not gear_down:
		cause = "Landing with the landing gear retracted."
		share.pilot += 0.85
		negligent = true
	elif on_runway and vs_fpm > 900.0:
		cause = "Hard landing beyond the structural limits of the landing gear and fuselage."
		share.pilot += 0.7
	elif on_runway or surface == "grass":
		cause = "Runway excursion during the landing roll." if phase in ["landing_roll", "final"] else "Loss of control on the ground."
		share.pilot += 0.55
	elif "windshear" in ev_ids or "microburst" in ev_ids:
		cause = "Encounter with severe windshear at low altitude."
		share.weather += 0.6
		share.pilot += 0.2
	elif max_bank > 70.0 or min_nz < -0.5:
		cause = "Loss of control in flight with excessive bank and pitch attitudes."
		share.pilot += 0.65
	else:
		cause = "Collision with terrain. The investigation could not establish the sequence of events with certainty."
		share.pilot += 0.4
	# ---- contributing factors
	var unstable := int(d.get("unstable_points", 0))
	if unstable >= 3:
		factors.append("The approach was not stabilised at 1000 ft and the crew did not go around.")
		share.pilot += 0.15
		if unstable >= 6:
			negligent = true
	for dv in devs:
		var k := String(dv.get("kind", ""))
		if k in ["landing", "takeoff", "runway"]:
			factors.append("ATC clearance was not followed: %s." % String(dv.get("text", k)).to_lower())
			share.pilot += 0.15
			negligent = true
		elif k == "altitude":
			factors.append("The aircraft deviated from its assigned altitude.")
			share.pilot += 0.05
	var cls: Array = d.get("checklists", [])
	if not cls.is_empty():
		var avg := 0.0
		for c in cls:
			avg += float(c)
		avg /= cls.size()
		if avg < 0.5:
			factors.append("Several normal checklists were not completed.")
			share.pilot += 0.1
	for df in d.get("accepted_defects", []):
		factors.append("The aircraft was accepted with a known defect: %s." % String(df.get("text", "")))
		share.pilot += 0.1
		share.maintenance += 0.1
	var rec_ac: Dictionary = d.get("aircraft_record", {})
	for df2 in rec_ac.get("defects", []):
		if int(df2.get("severity", 1)) >= 2:
			factors.append("Open maintenance item: %s." % String(df2.get("text", "")))
			share.maintenance += 0.1
	var w: Dictionary = d.get("weather", {})
	if float(w.get("vis", 10000.0)) < 1500.0:
		factors.append("Visibility was %d m." % int(w.get("vis", 0.0)))
		share.weather += 0.15
	if float(w.get("wind_kt", 0.0)) > 25.0:
		factors.append("Strong and gusty winds (%d kt)." % int(w.get("wind_kt", 0.0)))
		share.weather += 0.15
	if float(w.get("storm", 0.0)) > 0.5:
		factors.append("Thunderstorm activity near the flight path.")
		share.weather += 0.2
	for e2 in events:
		var lab := String(e2.get("label", ""))
		if lab != "" and float(e2.get("severity", 0.0)) >= 0.4:
			factors.append("%s occurred during the flight." % lab)
	var type_hours := float(d.get("pilot_type_hours", 500.0))
	if type_hours < 100.0:
		factors.append("The pilot had %d hours on type." % int(type_hours))
	if d.get("emergency_declared", false):
		findings.append("The crew declared an emergency and ATC provided priority handling.")
	# ---- recommendations
	if stalled:
		recs.append("Operators should reinforce upset prevention and recovery training, including stall recovery at low altitude.")
	if unstable >= 3:
		recs.append("The operator should enforce its stabilised approach criteria and a no-fault go-around policy.")
	if share.maintenance > 0.3:
		recs.append("The maintenance organisation should review its deferred defect process and inspection intervals.")
	if share.weather > 0.3:
		recs.append("Airports should improve low-level windshear and storm warnings to crews.")
	if negligent:
		recs.append("The authority should review the pilot's licence and the operator's oversight of crew compliance.")
	if recs.is_empty():
		recs.append("No new safety recommendations; existing procedures were considered adequate.")
	# ---- normalise the shares
	var tot := 0.0
	for k2 in share.keys():
		tot += float(share[k2])
	if tot > 0.0:
		for k3 in share.keys():
			share[k3] = float(share[k3]) / tot
	var timeline := []
	for m in marks.slice(maxi(marks.size() - 14, 0)):
		timeline.append({"t": float(m.t) - t_end, "text": String(m.text)})
	var blame := "pilot"
	var best := -1.0
	for k4 in share.keys():
		if float(share[k4]) > best:
			best = float(share[k4])
			blame = k4
	findings.append("Impact at %d kt with a descent rate of %d ft/min, %d° pitch and %d° bank." % [int(speed_kt), int(vs_fpm), int(crash.get("pitch", 0.0)), int(crash.get("bank", 0.0))])
	if outcome != "crashed" and outcome != "ditched":
		findings.append("The aircraft was evacuated on the ground.")
	return {"probable_cause": cause, "findings": findings, "factors": factors, "recommendations": recs, "shares": share,
		"blame": blame, "negligent": negligent, "timeline": timeline, "pilot_share": float(share.pilot),
		"report_days": 120 + int(d.get("fatalities", 0)) * 3}
