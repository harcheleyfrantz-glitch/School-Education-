class_name CareerRules
## Career paths, ranks, pay and progression rules.

const START_PATHS := {
	"student": {"label": "Flight School Student", "airline": "HFA", "rank": "Student Pilot", "base": "SKWF",
		"hours": 12.0, "money": 6500.0, "license": "Student", "ratings": ["t172"],
		"desc": "Start at Horizon Flight Academy with 12 hours in your logbook. Earn your licences, build hours and get hired."},
	"regional_fo": {"label": "Regional First Officer", "airline": "CLK", "rank": "First Officer", "base": "SKPC",
		"hours": 650.0, "money": 14000.0, "license": "CPL/IR", "ratings": ["t172", "tp72"],
		"desc": "Freshly hired by Coastal Link to fly the Kestrel TP-72 between the islands and the mainland."},
	"cargo": {"label": "Cargo First Officer", "airline": "NWC", "rank": "First Officer", "base": "SKNG",
		"hours": 2800.0, "money": 32000.0, "license": "ATPL", "ratings": ["t172", "f4"],
		"desc": "Night freight in the Titan F4 out of Northgate. Heavy aircraft, long nights, no passengers."},
	"charter": {"label": "Business Jet Captain", "airline": "APX", "rank": "Captain", "base": "SKPC",
		"hours": 3200.0, "money": 48000.0, "license": "ATPL", "ratings": ["t172", "bj6"],
		"desc": "Command a Vantage BJ-6 for Apex Executive. Demanding clients and short-notice trips."},
	"mainline_captain": {"label": "Mainline Captain", "airline": "SKF", "rank": "Captain", "base": "SKPC",
		"hours": 9800.0, "money": 92000.0, "license": "ATPL", "ratings": ["t172", "s320"],
		"desc": "A veteran Skyfall Air captain on the Stratos 320, one step from the wide-body fleet."},
}

const RANKS := ["Student Pilot", "Private Pilot", "Commercial Pilot", "Flight Instructor", "First Officer",
	"Senior First Officer", "Captain", "Senior Captain", "Training Captain"]

const RANK_PAY := {
	"Student Pilot": -180.0, "Private Pilot": -150.0, "Commercial Pilot": 30.0, "Flight Instructor": 45.0,
	"First Officer": 88.0, "Senior First Officer": 115.0, "Captain": 165.0, "Senior Captain": 215.0,
	"Training Captain": 240.0,
}


static func pay_rate(rank: String, airline: String) -> float:
	var base: float = RANK_PAY.get(rank, 50.0)
	if base < 0.0:
		return base
	return base * float(Airlines.get_al(airline).pay)


static func is_command(rank: String) -> bool:
	return rank in ["Student Pilot", "Private Pilot", "Commercial Pilot", "Flight Instructor", "Captain", "Senior Captain", "Training Captain"]


static func can_fly_type(p: Dictionary, type_id: String) -> bool:
	return type_id in p.get("ratings", [])


## Evaluates promotions after each flight. Returns a list of human readable changes.
static func evaluate_progression(p: Dictionary) -> Array:
	var msgs := []
	var hrs: float = p.hours
	var rep: float = p.reputation
	var rank: String = p.rank
	if rank == "Student Pilot" and hrs >= 45.0 and int(p.landings) >= 20:
		p.rank = "Private Pilot"
		p.license = "PPL"
		msgs.append("Checkride passed: you now hold a Private Pilot Licence.")
	elif rank == "Private Pilot" and hrs >= 150.0 and rep >= 45.0:
		p.rank = "Commercial Pilot"
		p.license = "CPL/IR"
		msgs.append("Commercial licence and instrument rating issued. You can now be paid to fly.")
	elif rank == "Commercial Pilot" and hrs >= 220.0:
		p.rank = "Flight Instructor"
		msgs.append("Horizon Flight Academy has hired you as a flight instructor.")
	elif rank == "First Officer" and hrs >= 1500.0 and rep >= 60.0:
		p.rank = "Senior First Officer"
		msgs.append("Promoted to Senior First Officer.")
	elif rank == "Senior First Officer" and hrs >= 3000.0 and rep >= 65.0 and float(p.safety) >= 80.0:
		p.rank = "Captain"
		msgs.append("Command upgrade approved. Congratulations, Captain.")
	elif rank == "Captain" and hrs >= 8000.0 and rep >= 72.0 and float(p.safety) >= 90.0:
		p.rank = "Senior Captain"
		msgs.append("Promoted to Senior Captain.")
	elif rank == "Senior Captain" and hrs >= 14000.0 and rep >= 85.0 and float(p.safety) >= 95.0:
		p.rank = "Training Captain"
		msgs.append("Appointed Training Captain. Others will now learn from you.")
	if hrs >= 1500.0 and p.license == "CPL/IR":
		p.license = "ATPL"
		msgs.append("Airline Transport Pilot Licence issued.")
	return msgs


## Airlines willing to hire this pilot (for the career hub job board).
static func hiring_offers(p: Dictionary) -> Array:
	var out := []
	var hrs: float = p.hours
	var rep: float = p.reputation
	var safety: float = p.safety
	for code in Airlines.ORDER:
		if code == p.airline:
			continue
		var al: Dictionary = Airlines.get_al(code)
		var need_hours := 0.0
		var need_rep := 40.0
		var type_id := ""
		match code:
			"HFA":
				need_hours = 0.0
				type_id = "t172"
			"CLK":
				need_hours = 250.0
				need_rep = 45.0
				type_id = "tp72"
			"LMN":
				need_hours = 1200.0
				need_rep = 50.0
				type_id = "s320"
			"NWC":
				need_hours = 1800.0
				need_rep = 50.0
				type_id = "f4"
			"APX":
				need_hours = 2000.0
				need_rep = 62.0
				type_id = "bj6"
			"SKF":
				need_hours = 2500.0
				need_rep = 65.0
				type_id = "s320"
			"WMA":
				need_hours = 2200.0
				need_rep = 60.0
				type_id = "s320"
		if code == "HFA" and p.rank != "Commercial Pilot" and p.rank != "Flight Instructor":
			continue
		if hrs >= need_hours and rep >= need_rep and safety >= 60.0:
			out.append({"airline": code, "type": type_id, "rank": "First Officer" if code != "HFA" else "Flight Instructor",
				"base": al.hubs[0], "pay": pay_rate("First Officer", code)})
	return out


static func type_rating_cost(type_id: String) -> float:
	match AircraftTypes.get_type(type_id).category:
		"turboprop": return 9000.0
		"regional": return 16000.0
		"narrowbody": return 24000.0
		"widebody": return 32000.0
		"bizjet": return 21000.0
		"cargo": return 30000.0
	return 0.0


## What a finished flight means for the pilot: licence action, employment, medical leave,
## fines, a criminal referral, reputation/safety/public standing. Uses the debrief and, after
## an accident, the investigation's share of responsibility.
static func consequences(res: Dictionary) -> Dictionary:
	var out := {"license": "", "suspension_days": 0, "employment": "kept", "medical_days": 0, "fine": 0.0,
		"criminal": false, "reputation": float(res.get("reputation", 0.0)), "safety": 0.0, "public": 0.0,
		"messages": [], "dead": false, "hero": false}
	var outcome := String(res.get("outcome", "landed"))
	var inv: Dictionary = res.get("investigation", {})
	var af: Dictionary = res.get("aftermath", {})
	var counts: Dictionary = af.get("counts", {})
	var fatal := int(counts.get("fatal", 0))
	var pilot_share := float(inv.get("pilot_share", 0.0))
	var negligent := bool(inv.get("negligent", false))
	var msgs: Array = out.messages
	match outcome:
		"landed", "diverted":
			for inc in res.get("incidents", []):
				match String(inc):
					"hard_landing":
						out.safety -= 3.0
						msgs.append("A hard landing report was filed; the aircraft needs a structural inspection.")
					"tailstrike":
						out.safety -= 8.0
						out.reputation -= 2.0
						msgs.append("Tail strike: you have been called to an interview with the chief pilot.")
					"overstress":
						out.safety -= 10.0
						msgs.append("The airframe was overstressed. The aircraft is grounded for inspection.")
					"gear_collapse", "wingstrike", "engine_strike":
						out.safety -= 15.0
						out.suspension_days = maxi(int(out.suspension_days), 14)
						msgs.append("Serious incident under investigation: you are stood down for 14 days.")
			for dv in res.get("deviations", []):
				if float(dv.get("severity", 0.0)) >= 0.6:
					out.safety -= 8.0
					out.suspension_days = maxi(int(out.suspension_days), 7)
					msgs.append("ATC filed a report (%s). Pending review you are suspended for 7 days." % String(dv.get("text", "")).to_lower())
			if float(res.get("score", 70.0)) >= 90.0:
				out.safety += 1.0
			if outcome == "diverted" and res.get("emergency_declared", false):
				out.public += 2.0
				msgs.append("Your handling of the emergency was noted favourably.")
		"crashed", "ditched":
			var inj := int(af.get("player_injury", 0))
			match inj:
				4:
					out.dead = true
				3:
					out.medical_days = 270
				2:
					out.medical_days = 90
				1:
					out.medical_days = 14
			out.safety -= 30.0 + 50.0 * pilot_share
			if outcome == "ditched" and fatal == 0:
				out.hero = true
				out.public += 25.0
				out.reputation += 5.0
				msgs.append("Everyone survived the ditching. The press is calling it a miracle.")
			elif negligent and pilot_share > 0.5:
				out.license = "revoked"
				out.employment = "terminated"
				out.reputation -= 40.0
				out.public -= 35.0
				if fatal > 0:
					out.criminal = true
					msgs.append("Prosecutors have opened a criminal investigation into the deaths of %d people." % fatal)
				msgs.append("The aviation authority has revoked your licence. The airline has terminated your employment.")
			elif pilot_share > 0.5:
				out.license = "suspended"
				out.suspension_days = 180
				out.employment = "terminated" if fatal > 0 else "suspended"
				out.reputation -= 25.0
				out.public -= 20.0
				msgs.append("The investigation found pilot error. Your licence is suspended for 180 days.")
			elif pilot_share > 0.25:
				out.license = "suspended"
				out.suspension_days = 60
				out.reputation -= 10.0
				msgs.append("Contributing crew factors were found: 60 days off flying and mandatory retraining.")
			else:
				out.reputation -= 3.0
				out.public += 5.0
				msgs.append("The investigation cleared you of blame.")
			if fatal > 0:
				out.fine = 0.0
				msgs.append("%d people lost their lives." % fatal)
		"abandoned":
			out.reputation -= 1.0
	return out


## Writes a finished flight to the character: logbook, hours, pay, standing, licence and job
## actions, injuries - and permanent death.
static func apply_result(res: Dictionary) -> Dictionary:
	var cons := consequences(res)
	if Game.player.is_empty():
		return cons
	var p: Dictionary = Game.player
	var hours := float(res.get("hours", 0.0))
	var type_id := String(res.get("type", ""))
	p.hours = float(p.hours) + hours
	var by_type: Dictionary = p.get("hours_by_type", {})
	by_type[type_id] = float(by_type.get(type_id, 0.0)) + hours
	p.hours_by_type = by_type
	p.flights = int(p.flights) + 1
	if String(res.get("outcome", "")) in ["landed", "diverted"]:
		p.landings = int(p.landings) + 1
		p.location = String(res.get("arr", p.location))
		Game.add_money(float(res.get("pay", 0.0)) + float(res.get("bonus", 0.0)), "Flight %s" % res.get("callsign", ""))
	p.reputation = clampf(float(p.reputation) + float(cons.reputation), 0.0, 100.0)
	p.safety = clampf(float(p.safety) + float(cons.safety), 0.0, 100.0)
	p.public = clampf(float(p.get("public", 50.0)) + float(cons.public), 0.0, 100.0)
	var log: Array = p.logbook
	log.append({"t": WorldSim.clock, "flight": res.get("callsign", ""), "type": type_id, "reg": res.get("reg", ""),
		"from": res.get("dep", ""), "to": res.get("arr", ""), "hours": hours, "grade": res.get("grade", ""),
		"outcome": res.get("outcome", ""), "score": res.get("score", 0.0)})
	if log.size() > 500:
		p.logbook = log.slice(log.size() - 500)
	if int(cons.suspension_days) > 0:
		p.suspended_until = maxf(float(p.get("suspended_until", 0.0)), WorldSim.clock + float(cons.suspension_days) * 86400.0)
	if int(cons.medical_days) > 0:
		p.recovery_until = WorldSim.clock + float(cons.medical_days) * 86400.0
		p.injury = "critical" if int(cons.medical_days) > 200 else ("serious" if int(cons.medical_days) > 60 else "minor")
	match String(cons.license):
		"revoked":
			p.license = "Revoked"
		"suspended":
			p.license_suspended = true
	match String(cons.employment):
		"terminated":
			p.airline = ""
			p.employment = "unemployed"
		"suspended":
			p.employment = "suspended"
	if bool(cons.criminal):
		p.criminal_case = {"opened": WorldSim.clock, "flight": res.get("flight_id", "")}
	if not res.get("incidents", []).is_empty() or String(res.get("outcome", "")) in ["crashed", "ditched"]:
		var incs: Array = p.incidents
		incs.append({"t": WorldSim.clock, "outcome": res.get("outcome", ""), "incidents": res.get("incidents", []),
			"cause": res.get("investigation", {}).get("probable_cause", "")})
	var msgs: Array = cons.messages
	if not bool(cons.dead):
		msgs.append_array(evaluate_progression(p))
	WorldSim.record_flight_on_aircraft(String(res.get("reg", "")), hours, clampf(float(res.get("max_g", 1.0)) - 1.0, 0.0, 3.0))
	if News.has_method("on_flight_result"):
		News.call("on_flight_result", res, cons)
	if bool(cons.dead):
		Game.retire_character("deceased", {"flight": res.get("flight_id", ""), "place": res.get("aftermath", {}).get("place", ""),
			"cause": res.get("investigation", {}).get("probable_cause", "")})
	else:
		Game.career_changed.emit()
		Game.save_game()
	return cons
