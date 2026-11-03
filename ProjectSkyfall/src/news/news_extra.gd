class_name NewsExtra
extends RefCounted
## More news topics on top of News: natural disasters around the world (earthquakes, volcanic
## eruptions, hurricanes, tornado outbreaks, blizzards, heatwaves) that really close airports;
## airline business (orders, new routes, strikes, liveries) and a monthly safety league table;
## celebrities, feel-good stories, spotters and travel; and stories about the player's own
## flight: hazards they flew through, what happened in the cabin and what passengers said.

const HURRICANE_NAMES := ["Arlene", "Bertrand", "Celeste", "Dorian", "Esme", "Fabian", "Greta", "Hector", "Imelda", "Jasper", "Kendra", "Leon",
	"Marisol", "Nestor", "Ophelia", "Pablo", "Rosalind", "Stellan", "Tamsin", "Victor", "Wanda"]
const CELEBS := ["pop star Kayla Brooks", "Hollywood actor Daniel Reyes", "football legend Marco Silva", "tennis champion Anya Volkova", "TV chef Jamie Okafor",
	"rapper Lil Comet", "Oscar winner Helen Marlowe", "F1 driver Luca Benedetti", "YouTuber SkyKid", "astronaut Commander Rhea Patel"]


static func _ap_city(icao: String) -> String:
	var a := Airports.get_ap(icao)
	return String(a.get("city", a.get("short", icao)))


static func _t(day: int, hour: float) -> float:
	return float(day) * 86400.0 + hour * 3600.0


# ================================================================== the world, every day
static func daily(day: int, r: RandomNumberGenerator) -> void:
	var date := U.clock_to_date(float(day) * 86400.0)
	var month := int(date.month)
	_disasters(day, r, month)
	if r.randf() < 0.25:
		_business(day, r)
	if day % 30 == 0:
		_safety_table(day)
	if r.randf() < 0.2:
		_feelgood(day, r)
	if r.randf() < 0.08:
		_celebrity_sighting(day, r)
	if r.randf() < 0.1:
		_spotters(day, r)
	if r.randf() < 0.1:
		_travel(day, r)


static func _close(icao: String, days: float, why: String) -> void:
	if WorldSim.airport_open(icao):
		WorldSim.close_airport(icao, days, why)


static func _posts(r: RandomNumberGenerator, lines: Array, n: int, t: float, sid: String = "") -> void:
	for k in n:
		var extra := {"importance": 1, "spread": 1.0, "t": t + 600.0 * k}
		if sid != "":
			extra.story = sid
		News.post(News._citizen(r), String(lines[r.randi() % lines.size()]), extra)


static func _disasters(day: int, r: RandomNumberGenerator, month: int) -> void:
	# earthquakes: anywhere on a fault line
	if r.randf() < 0.03:
		var icao := String(["KSFO", "KLAX", "KSEA", "LIRF", "BIKF", "LPPD", "SKNG", "KLAS", "LSZH", "LPPT"][r.randi() % 10])
		var mag := snappedf(r.randf_range(5.6, 7.8), 0.1)
		var city := _ap_city(icao)
		var closed := mag >= 6.6
		if closed:
			_close(icao, 1.0 + (mag - 6.6) * 1.5, "an earthquake")
		News.publish("skyline", "breaking", "Magnitude %.1f earthquake strikes near %s%s" % [mag, city, " - airport closed" if closed else ""],
			"A powerful earthquake shook %s. %s" % [city, "The airport has been closed while engineers inspect the runways for cracks." if closed else "Flights are operating with delays while buildings are checked."],
			["Buildings swayed across the city and thousands of people spent the night outside.", "Aftershocks are expected for several days.",
			"Relief flights carrying tents, water and medical teams are being prioritised.", "Airlines are waiving change fees for passengers booked to %s." % city],
			{"importance": 3 if mag >= 7.0 else 2, "t": _t(day, r.randf_range(2.0, 22.0)), "place": city, "tags": ["earthquake", "disaster"]})
		_posts(r, ["The whole building just shook in %s. Everyone OK?" % city, "Earthquake!! Felt it for a solid 30 seconds. Never been so scared.",
			"Airport in %s evacuated, everyone standing on the apron." % city, "The aftershocks keep coming. Nobody is sleeping tonight."], 4, _t(day, 12.0))
	# volcanic eruptions: Iceland, the Azores, Italy
	if r.randf() < 0.012:
		var site: Array = [["BIKF", "Iceland's Reykjanes peninsula", ["BIKF", "EKVG", "EGPH", "ENGM"]], ["LIRF", "Mount Etna in Sicily", ["LIRF"]],
			["LPPD", "the Azores", ["LPPD", "LPMA"]]][r.randi() % 3]
		for c in site[2]:
			_close(String(c), r.randf_range(1.0, 3.0), "volcanic ash")
		News.publish("herald", "breaking", "Volcano erupts on %s - ash cloud closes airspace" % String(site[1]),
			"A volcanic eruption has sent a column of ash kilometres into the sky. Airspace has been closed around %s." % String(site[1]),
			["Volcanic ash melts inside jet engines and can make them fail - airlines are not allowed to fly through it.",
			"Thousands of passengers are stranded as flights are cancelled across the region.", "Forecasters are tracking the ash cloud as it drifts east."],
			{"importance": 3, "t": _t(day, r.randf_range(4.0, 20.0)), "tags": ["volcano", "disaster"]})
		_posts(r, ["The sky glowing red over the volcano tonight. Unreal.", "All flights cancelled. Ash cloud. Here we go again.", "Ash falling like grey snow on the car."], 3, _t(day, 14.0))
	# hurricanes: late summer and autumn, the south-east US and the islands
	var hurricane_odds := 0.08 if month in [8, 9, 10] else 0.004
	if r.randf() < hurricane_odds:
		var icao2 := String(["KMIA", "KMCO", "KMSY", "TXKF"][r.randi() % 4])
		var cat := 1 + r.randi() % 5
		var nm := String(HURRICANE_NAMES[(day / 7) % HURRICANE_NAMES.size()])
		_close(icao2, 1.5 + cat * 0.4, "Hurricane %s" % nm)
		News.publish("skyline", "breaking", "Hurricane %s makes landfall near %s as a category %d storm" % [nm, _ap_city(icao2), cat],
			"Hurricane %s has come ashore with winds of up to %d mph. %s airport is closed." % [nm, 75 + cat * 25, _ap_city(icao2)],
			["Airlines flew their aircraft out of the hurricane's path before it arrived.", "Storm surge flooding is expected along the coast.",
			"Hurricane hunter aircraft flew through the eye to measure the storm."],
			{"importance": 3 if cat >= 3 else 2, "t": _t(day, r.randf_range(6.0, 20.0)), "tags": ["hurricane", "disaster", "weather"]})
		_posts(r, ["Boarded up and waiting. Stay safe everyone. #%s" % nm, "Last flight out before the hurricane. Turbulence was wild.",
			"Power is out across the whole neighbourhood. #Hurricane%s" % nm], 3, _t(day, 15.0))
	# tornado outbreaks: spring on the plains
	if r.randf() < (0.06 if month in [4, 5, 6] else 0.008):
		var icao3 := String(["KDFW", "KATL", "KORD", "KDEN"][r.randi() % 4])
		_close(icao3, 0.4, "tornado warnings")
		News.publish("skyline", "news", "Tornado outbreak near %s - passengers sheltered in terminal basements" % _ap_city(icao3),
			"Several tornadoes touched down around %s. Flights were halted and travellers moved to shelters." % _ap_city(icao3),
			["Storm chasers filmed at least three funnels on the ground at once.", "Aircraft parked at the gates were checked for hail damage."],
			{"importance": 2, "t": _t(day, r.randf_range(14.0, 21.0)), "tags": ["tornado", "disaster", "weather"]})
		_posts(r, ["Tornado sirens in the terminal. Everyone sent to the basement.", "Saw the funnel from the plane window as we taxied. Pilot stopped. Smart.",
			"The sky turned green. Never seen anything like it."], 3, _t(day, 18.0))
	# blizzards: winter in the north
	if r.randf() < (0.07 if month in [12, 1, 2] else 0.002):
		var icao4 := String(["ENGM", "ESSA", "EKCH", "CYYZ", "KBOS", "KDEN", "KORD"][r.randi() % 7])
		_close(icao4, 0.7, "a blizzard")
		News.publish("gazette", "news", "Blizzard grounds hundreds of flights at %s" % _ap_city(icao4),
			"Heavy snow and gale-force winds closed the runways at %s." % _ap_city(icao4),
			["Snowploughs worked through the night in convoy.", "De-icing queues stretched for hours before the airport finally shut."],
			{"importance": 2, "t": _t(day, r.randf_range(5.0, 18.0)), "tags": ["blizzard", "disaster", "weather"]})
	# heatwaves: summer in the desert and the south of Europe
	if r.randf() < (0.06 if month in [6, 7, 8] else 0.002):
		var icao5 := String(["KLAS", "LEMD", "LIRF", "KDFW", "LEBL"][r.randi() % 5])
		News.publish("gazette", "news", "Too hot to fly: heatwave forces cancellations at %s" % _ap_city(icao5),
			"Temperatures above 45 degrees mean some aircraft cannot take off fully loaded at %s." % _ap_city(icao5),
			["Hot air is thin air: wings make less lift and engines less thrust.", "Airlines are moving departures to the cooler early morning."],
			{"importance": 1, "t": _t(day, 14.0), "tags": ["heatwave", "weather"]})


static func _business(day: int, r: RandomNumberGenerator) -> void:
	var codes := Airlines.all_codes()
	var code := String(codes[r.randi() % codes.size()])
	var al := Airlines.get_al(code)
	var name := String(al.get("name", ""))
	var t := _t(day, r.randf_range(8.0, 18.0))
	match r.randi() % 7:
		0:
			var ty := AircraftTypes.get_type(String(["w390", "w280", "s319", "rj100", "tp90", "bj8"][r.randi() % 6]))
			var n := 5 + r.randi() % 40
			News.publish("aeroweek", "business", "%s orders %d %s" % [name, n, String(ty.name)],
				"%s has placed an order for %d %s aircraft, worth billions at list prices." % [name, n, String(ty.name)],
				[String(ty.get("blurb", "")), "Deliveries are expected to start in two years."], {"importance": 1, "t": t, "tags": ["business", "newtype", code]})
		1:
			News.publish("aeroweek", "business", "%s unveils new livery" % name, "%s has revealed a new paint scheme at a ceremony in its hangar." % name,
				["Opinions online are, as always, divided."], {"importance": 1, "t": t, "tags": ["business", "spotter", code]})
		2:
			News.publish("herald", "business", "Cabin crew at %s announce strike" % name, "Flights could be disrupted next week after talks over pay and rest periods broke down.",
				["The airline says it will try to protect as many flights as possible."], {"importance": 2, "t": t, "tags": ["business", "travel", code]})
		3:
			News.publish("aeroweek", "business", "%s reports record profits" % name, "Strong demand and full planes have pushed %s to its best year ever." % name,
				["The airline will hire 300 new pilots."], {"importance": 1, "t": t, "tags": ["business", code]})
		4:
			var hubs: Array = al.get("hubs", ["SKPC"])
			var from := _ap_city(String(hubs[0]))
			var to := _ap_city(String(Airports.ORDER[r.randi() % Airports.ORDER.size()]))
			News.publish("aeroweek", "business", "%s launches %s - %s" % [name, from, to], "A new route from %s to %s starts next month." % [from, to],
				["Introductory fares sold out within hours."], {"importance": 1, "t": t, "tags": ["business", "routes", code]})
		5:
			News.publish("herald", "business", "Pilot shortage: %s offers signing bonus" % name, "Airlines are competing hard for experienced captains.",
				["Flight schools report record applications."], {"importance": 1, "t": t, "tags": ["business", code]})
		_:
			News.publish("aeroweek", "business", "%s named airline of the year" % name, "Passengers voted %s best for service, punctuality and comfort." % name,
				["The award was collected by the airline's longest-serving flight attendant."], {"importance": 1, "t": t, "tags": ["feelgood", code]})


static func _safety_table(day: int) -> void:
	## The monthly airline safety league table: best and worst by safety rating.
	var codes := Airlines.all_codes()
	codes.sort_custom(func(a, b): return float(Airlines.get_al(String(a)).get("standards", 0.7)) > float(Airlines.get_al(String(b)).get("standards", 0.7)))
	var best := []
	var worst := []
	for i in 3:
		best.append("%s - %s" % [Airlines.get_al(String(codes[i])).name, Airlines.safety_label(String(codes[i]))])
		var j := codes.size() - 1 - i
		worst.append("%s - %s" % [Airlines.get_al(String(codes[j])).name, Airlines.safety_label(String(codes[j]))])
	News.publish("herald", "news", "Airline safety league table: %s tops the ranking again" % Airlines.get_al(String(codes[0])).name,
		"Our monthly ranking of every airline by training, maintenance and operating standards.",
		["Safest: " + ", ".join(best) + ".", "Bottom of the table: " + ", ".join(worst) + ".",
		"Experts say regional and island airlines face the hardest conditions - short runways, strong winds and many takeoffs a day.",
		"Every airline on the list meets the legal minimum. The best go far beyond it."],
		{"importance": 2, "t": _t(day, 9.0), "tags": ["safety"]})


static func _feelgood(day: int, r: RandomNumberGenerator) -> void:
	var codes := Airlines.all_codes()
	var name := String(Airlines.get_al(String(codes[r.randi() % codes.size()])).get("name", ""))
	var city := _ap_city(String(Airports.ORDER[r.randi() % Airports.ORDER.size()]))
	var stories := [
		["Captain's last flight: water cannon salute for retiring %s pilot after 38 years" % name, "Fire crews at %s formed an arch of water over the aircraft on its final taxi in." % city],
		["Lost teddy bear flies home after two weeks at %s airport" % city, "Staff posted photos of the bear's adventures around the terminal before reuniting it with its owner, aged 4."],
		["Meet Biscuit, the beagle who sniffs out trouble at %s airport" % city, "The airport's most popular employee has a fan club and her own staff pass."],
		["%s crew sing happy birthday to 100-year-old passenger" % name, "The whole cabin joined in, and the captain made an announcement from the flight deck."],
		["Soldiers welcomed home with applause at %s arrivals" % city, "Hundreds of passengers stopped to clap as the troops walked through the terminal."],
		["Wedding at gate 12: couple marries at %s airport during six-hour delay" % city, "A pilot with a celebrant's licence happened to be waiting for the same flight."],
		["Boy with leukaemia becomes honorary %s captain for the day" % name, "He did the walkaround, sat in the left seat and made the welcome announcement."],
	]
	var s: Array = stories[r.randi() % stories.size()]
	News.publish("gazette", "people", String(s[0]), String(s[1]), ["Photos of the moment have been shared thousands of times."],
		{"importance": 1, "t": _t(day, r.randf_range(9.0, 19.0)), "tags": ["feelgood"]})


static func _celebrity_sighting(day: int, r: RandomNumberGenerator) -> void:
	var who := String(CELEBS[r.randi() % CELEBS.size()])
	var codes := Airlines.all_codes()
	var name := String(Airlines.get_al(String(codes[r.randi() % codes.size()])).get("name", ""))
	var city := _ap_city(String(Airports.ORDER[r.randi() % Airports.ORDER.size()]))
	News.publish("gazette", "people", "%s spotted flying %s to %s" % [who.capitalize(), name, city],
		"Fellow passengers could not believe it when %s took their seat." % who,
		["Fans were waiting at arrivals in %s with banners and phones." % city], {"importance": 1, "t": _t(day, r.randf_range(8.0, 22.0)), "tags": ["celebrity"]})


static func _spotters(day: int, r: RandomNumberGenerator) -> void:
	var ty := AircraftTypes.get_type(String(["w390", "w280", "w380", "tp90", "bj8"][r.randi() % 5]))
	var city := _ap_city(String(Airports.ORDER[r.randi() % Airports.ORDER.size()]))
	News.publish("aeroweek", "news", "Spotters flock to %s for the %s's first visit" % [city, String(ty.name)],
		"Hundreds of enthusiasts lined the fences to see the %s land for the first time." % String(ty.name),
		["Some had driven for six hours to be there.", "The crew rocked the wings as they taxied past the crowd."],
		{"importance": 1, "t": _t(day, r.randf_range(10.0, 18.0)), "tags": ["spotter", "newtype"]})


static func _travel(day: int, r: RandomNumberGenerator) -> void:
	var city := _ap_city(String(Airports.ORDER[r.randi() % Airports.ORDER.size()]))
	var stories := [
		["Busiest travel weekend of the year: what you need to know", "Arrive early, check in online and keep your bag small."],
		["The world's best airport lounges, ranked", "%s came top for its spa, its food and its runway views." % city],
		["Why your flight is cheaper on a Tuesday", "Airline pricing experts explain how fares really work."],
		["Ten tips for nervous flyers from a real captain", "Turbulence is uncomfortable, not dangerous - and other things pilots wish you knew."],
		["%s airport opens new terminal" % city, "The building has more gates, faster security and a rooftop spotting terrace."],
	]
	var s: Array = stories[r.randi() % stories.size()]
	News.publish("gazette", "news", String(s[0]), String(s[1]), [], {"importance": 1, "t": _t(day, r.randf_range(7.0, 20.0)), "tags": ["travel"]})


# ================================================================== the player's own flight
static func on_flight(res: Dictionary, d: Dictionary) -> void:
	var r := U.rng(U.hash_str(String(res.get("flight_id", "")) + "extra"))
	var place := String(d.get("landed_at", ""))
	var hz: Dictionary = res.get("hazards", {})
	var airline := String(d.get("airline", ""))
	var num := String(d.get("num", ""))
	if hz.has("ash"):
		News.publish("skyline", "breaking", "%s jet loses all engines in volcanic ash - and glides to safety" % airline,
			"Flight %s flew into an ash cloud and every engine flamed out. The crew glided down out of the ash, relit the engines and landed at %s." % [num, place],
			["Passengers described a smell of sulphur and blue sparks dancing across the windows.", "\"We are doing our damnedest to get them going again,\" the captain told the cabin.",
			"Aviation experts called it one of the finest pieces of airmanship in years."],
			{"importance": 3, "place": place, "tags": ["incident", "volcano", d.get("code", "")]})
		_posts(r, ["I was on %s. All the engines stopped. Silence. Then they came back. I'm shaking." % num, "Give that crew every medal there is.",
			"Gliding a jet out of an ash cloud. Absolute legends."], 4, WorldSim.clock + 900.0)
	if hz.has("earthquake"):
		var q: Dictionary = hz.earthquake
		News.publish("skyline", "news", "Flight %s lands in the middle of a magnitude %.1f earthquake" % [num, float(q.get("mag", 6.5))],
			"The %s flight was %s when the quake struck %s.%s" % [airline, "on the ground" if float(q.get("alt", 0.0)) < 1.0 else "on approach", place,
				" Runway %s was closed after cracks appeared." % String(q.get("closed", "")) if String(q.get("closed", "")) != "" else ""],
			["Passengers felt the aircraft rock on its gear.", "Dust rose over the city as the ground shook."],
			{"importance": 2, "place": place, "tags": ["earthquake", "disaster", d.get("code", "")]})
	if hz.has("hail"):
		News.publish("gazette", "incident", "Hail cracks windscreen of %s jet" % airline, "Flight %s flew through a hailstorm that cracked the windscreen and dented the nose before landing safely at %s." % [num, place],
			["Engineers will inspect every panel of the airframe."], {"importance": 2, "place": place, "tags": ["incident", "weather", d.get("code", "")]})
	if hz.has("lightning"):
		_posts(r, ["Lightning hit our wing on the way into %s. Huge flash. Pilot: 'that was lightning, all normal'. Okay then!" % place,
			"Filmed the lightning strike on %s from my window. Unbelievable." % num], 2, WorldSim.clock + 600.0)
	var wx := String(res.get("weather_preset", ""))
	if wx in ["hurricane", "tornado", "blizzard"]:
		News.publish("skyline", "news", "Crew lands %s flight in %s at %s" % [airline, {"hurricane": "a hurricane", "tornado": "a tornado outbreak", "blizzard": "a blizzard"}[wx], place],
			"While most flights diverted, %s made it in." % num, ["Passengers applauded on touchdown."], {"importance": 2, "place": place, "tags": ["weather", wx]})
	# what happened in the cabin
	for e in res.get("events", []):
		match String(e.get("id", "")):
			"celebrity":
				News.publish("gazette", "people", "%s flies %s to %s" % [String(e.get("who", "A star")).capitalize(), airline, place],
					"Fellow passengers on %s got a surprise when %s boarded." % [num, String(e.get("who", "a celebrity"))], [],
					{"importance": 1, "tags": ["celebrity"]})
			"proposal":
				News.publish("gazette", "people", "She said yes! Mid-air proposal on flight %s" % num, "A passenger proposed over the PA at 35,000 feet. The cabin erupted.", [],
					{"importance": 1, "tags": ["feelgood"]})
			"birth":
				News.publish("gazette", "people", "Baby girl born at 37,000 feet on %s flight" % airline, "Mother and baby are doing well after the birth on flight %s, helped by cabin crew and a passenger who is a midwife." % num,
					["The airline has offered the baby free flights for life."], {"importance": 2, "tags": ["feelgood"]})
	# the president landed safely
	if bool(res.get("presidential", false)):
		var ic := int(res.get("escort_intercepts", 0))
		News.publish("herald", "news", "Calderra One lands safely in %s%s" % [place, " after escorts shoot down hostile drone" if ic > 0 else ""],
			"The presidential aircraft arrived on schedule with its fighter escort.%s" % (" Defence officials confirmed %d unidentified drone%s was intercepted on the way." % [ic, "" if ic == 1 else "s"] if ic > 0 else ""),
			["The president thanked the crew personally on the steps of the aircraft."], {"importance": 3 if ic > 0 else 2, "place": place, "tags": ["president"]})
	_reviews(res, d, r)


static func review_stars(res: Dictionary) -> int:
	## What passengers thought of the flight: the landing, the bumps, the delay, the drama.
	var td: Dictionary = res.get("touchdown", {})
	var vs := absf(float(td.get("vs_fpm", 250.0)))
	var s := 5.0
	if vs > 600.0:
		s -= 2.0
	elif vs > 350.0:
		s -= 1.0
	elif vs < 120.0:
		s += 0.5
	s -= clampf(float(res.get("late_min", 0.0)) / 60.0, 0.0, 2.0)
	for e in res.get("events", []):
		if String(e.get("id", "")) == "turbulence":
			s -= 0.6
		if float(e.get("severity", 0.0)) >= 0.6:
			s -= 0.5
	if not (res.get("incidents", []) as Array).is_empty():
		s -= 1.5
	return clampi(int(round(s)), 1, 5)


static func _reviews(res: Dictionary, d: Dictionary, r: RandomNumberGenerator) -> void:
	if int(res.get("pax", 0)) < 1:
		return
	var stars := review_stars(res)
	var lines := {
		5: ["★★★★★ Smooth as silk into %s. Did we even land?" % d.landed_at, "★★★★★ Best flight I've had in years. Thank you %s crew!" % d.airline,
			"★★★★★ On time, friendly crew, perfect landing. No notes."],
		4: ["★★★★☆ Good flight, a few bumps, nice landing at %s." % d.landed_at, "★★★★☆ Solid. Crew were lovely. Coffee could be hotter.",
			"★★★★☆ Would fly %s again." % d.airline],
		3: ["★★★☆☆ Fine. Bit of a firm landing.", "★★★☆☆ Late, but the crew kept us informed.", "★★★☆☆ Average. Seats were tight."],
		2: ["★★☆☆☆ Turbulence the whole way and a landing that rattled my fillings.", "★★☆☆☆ Very late and nobody told us why.",
			"★★☆☆☆ The landing at %s was something else. Not in a good way." % d.landed_at],
		1: ["★☆☆☆☆ Never again.", "★☆☆☆☆ Worst flight of my life. My drink ended up on the ceiling.", "★☆☆☆☆ I thought we'd crashed. We hadn't. Barely."],
	}
	var pool: Array = lines[stars]
	for k in 2 + r.randi() % 2:
		News.post(News._citizen(r), "%s #%s" % [String(pool[r.randi() % pool.size()]), String(d.num)], {"importance": 1, "spread": 1.0, "t": WorldSim.clock + 1800.0 + 900.0 * k})
