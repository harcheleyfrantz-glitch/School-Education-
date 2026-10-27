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
