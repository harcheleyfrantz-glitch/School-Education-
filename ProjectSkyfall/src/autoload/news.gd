extends Node
## The world's media. Turns what happens - the player's flights, accidents, incidents and the
## background life of the airlines - into articles from several outlets, social media posts from
## the persistent population, and stories that keep evolving over game days and weeks (victims
## named, survivors' accounts, the investigation, the pilot's fate, memorials, the final report,
## the anniversary). Major stories carry an in-engine video (a reconstruction rendered live from
## the flight recorder, or news footage staged at the airport). Everything is saved with the world.

signal published(article: Dictionary)
signal posted(post: Dictionary)

const OUTLETS := {
	"skyline": {"name": "Skyline News", "kind": "tv", "color": "c0262d", "handle": "@SkylineNews"},
	"herald": {"name": "Calderra Herald", "kind": "paper", "color": "1f3b66", "handle": "@CalderraHerald"},
	"westmark": {"name": "Westmark Post", "kind": "paper", "color": "2d6a4f", "handle": "@WestmarkPost"},
	"aeroweek": {"name": "AeroWeek", "kind": "trade", "color": "3a4a5c", "handle": "@AeroWeek"},
	"gazette": {"name": "Port Calder Gazette", "kind": "local", "color": "8a5a2b", "handle": "@PCGazette"},
	"skywatch": {"name": "SkyWatch", "kind": "blog", "color": "6b3fa0", "handle": "@SkyWatchBlog"},
}
const MAX_ARTICLES := 400
const MAX_POSTS := 700
const MAX_REPLAYS := 12

var incidents: Array = []
var articles: Array = []
var stories: Array = []
var posts: Array = []
## The player's own recent flights, kept as compact flight-recorder tracks for replays.
var replays: Array = []
var _next := 1
var _last_day := -1


# ================================================================== publishing
func _id(prefix: String) -> String:
	_next += 1
	return "%s%d" % [prefix, _next]


func publish(outlet: String, kind: String, headline: String, lede: String, body: Array, extra: Dictionary = {}) -> Dictionary:
	var a := {"id": _id("A"), "t": float(extra.get("t", WorldSim.clock)), "outlet": outlet, "kind": kind, "headline": headline,
		"lede": lede, "body": body, "story": String(extra.get("story", "")), "importance": int(extra.get("importance", 1)),
		"video": extra.get("video", {}), "tags": extra.get("tags", []), "place": String(extra.get("place", "")),
		"incident": String(extra.get("incident", ""))}
	articles.append(a)
	if articles.size() > MAX_ARTICLES:
		articles = articles.slice(articles.size() - MAX_ARTICLES)
	published.emit(a)
	return a


func post(author: Dictionary, text: String, extra: Dictionary = {}) -> Dictionary:
	var imp := int(extra.get("importance", 1))
	var r := U.rng(U.hash_str(text + str(WorldSim.clock)))
	var base = [8, 60, 900, 9000][clampi(imp, 0, 3)]
	var p := {"id": _id("P"), "t": float(extra.get("t", WorldSim.clock)) + r.randf_range(0.0, 1800.0) * float(extra.get("spread", 0.0)),
		"name": String(author.get("name", "")), "handle": String(author.get("handle", "@someone")), "verified": bool(author.get("verified", false)),
		"text": text, "likes": int(base * r.randf_range(0.2, 2.5)), "reposts": int(base * r.randf_range(0.02, 0.4)),
		"replies": int(base * r.randf_range(0.01, 0.15)), "story": String(extra.get("story", "")), "person": int(author.get("id", -1)),
		"video": bool(extra.get("video", false))}
	posts.append(p)
	if posts.size() > MAX_POSTS:
		posts = posts.slice(posts.size() - MAX_POSTS)
	posted.emit(p)
	return p


func _citizen(r: RandomNumberGenerator, near_city: String = "") -> Dictionary:
	## A random member of the persistent population as a social media author.
	for i in 6:
		var id := r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1)
		var p := WorldSim.person(id)
		if near_city == "" or String(p.home) == near_city or i == 5:
			return {"name": p.name, "handle": Names.handle(r, p), "id": id}
	return {"name": "Someone", "handle": "@someone"}


func _outlet_author(key: String) -> Dictionary:
	var o: Dictionary = OUTLETS[key]
	return {"name": o.name, "handle": o.handle, "verified": true}


func _airline_author(code: String) -> Dictionary:
	var al := Airlines.get_al(code)
	return {"name": String(al.get("name", code)), "handle": "@" + String(al.get("name", code)).replace(" ", ""), "verified": true}


func _pick(r: RandomNumberGenerator, arr: Array) -> String:
	return String(arr[r.randi() % arr.size()])


# ================================================================== flights finished by the player
func on_flight_result(res: Dictionary, cons: Dictionary) -> void:
	var outcome := String(res.get("outcome", ""))
	_store_replay(res)
	if outcome in ["crashed", "ditched"]:
		_accident(res, cons)
	elif outcome in ["landed", "diverted"]:
		_flight_story(res, cons)


func _flight_desc(res: Dictionary) -> Dictionary:
	var al := Airlines.get_al(String(res.get("airline", "")))
	var t := AircraftTypes.get_type(String(res.get("type", "s320")))
	var num := String(res.get("callsign", "")).split(" ")[-1] if String(res.get("callsign", "")) != "" else ""
	return {"airline": String(al.get("name", "An airline")), "code": String(res.get("airline", "")), "num": "%s%s" % [al.get("iata", ""), num],
		"type": "%s %s" % [t.maker, t.name], "short": String(t.short), "from": Airports.get_ap(String(res.get("dep", ""))).get("short", ""),
		"to": Airports.get_ap(String(res.get("planned_arr", res.get("arr", "")))).get("short", ""),
		"landed_at": Airports.get_ap(String(res.get("arr", ""))).get("short", ""), "pilot": String(res.get("captain", Game.player.get("name", "the captain") if Game.has_character() else "the captain"))}


## Keeps the last five minutes of every finished flight (the approach and landing, or the
## accident) so the player can watch them again from the video library.
func _store_replay(res: Dictionary) -> void:
	var rec: Dictionary = res.get("recorder", {})
	var smp: Array = rec.get("samples", [])
	if smp.size() < 20:
		return
	var t_end := float(smp[smp.size() - 1][0])
	var keep := []
	for sm in smp:
		if float(sm[0]) >= t_end - 300.0:
			keep.append(sm)
	var cvr := []
	for v in rec.get("cvr", []):
		if float(v.get("t", 0.0)) >= t_end - 300.0:
			cvr.append(v)
	var outcome := String(res.get("outcome", "landed"))
	replays.append({"id": _id("R"), "t": WorldSim.clock, "type": String(res.get("type", "s320")), "airline": String(res.get("airline", "SKF")),
		"reg": String(res.get("reg", "")), "callsign": String(res.get("callsign", "")), "dep": String(res.get("dep", "")), "arr": String(res.get("arr", "")),
		"clock": float(res.get("clock", WorldSim.clock)) - (t_end - float(keep[0][0])), "outcome": outcome, "weather": res.get("weather", {}),
		"samples": keep, "cvr": cvr, "grade": String(res.get("grade", "")),
		"label": {"crashed": "Accident", "ditched": "Ditching", "diverted": "Diversion and landing"}.get(outcome, "Approach and landing")})
	if replays.size() > MAX_REPLAYS:
		replays = replays.slice(replays.size() - MAX_REPLAYS)


func _accident(res: Dictionary, cons: Dictionary) -> void:
	var d := _flight_desc(res)
	var af: Dictionary = res.get("aftermath", {})
	var c: Dictionary = af.get("counts", {})
	var inv: Dictionary = res.get("investigation", {})
	var crash: Dictionary = res.get("crash", {})
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	var ditch := String(res.outcome) == "ditched"
	var place := String(af.get("place", crash.get("place", "")))
	var rec_src: Dictionary = res.get("recorder", {})
	var samples: Array = rec_src.get("samples", [])
	var inc := {"id": _id("I"), "clock": WorldSim.clock, "num": d.num, "title": "%s %s %s" % [d.airline, d.num, "ditching" if ditch else "accident"],
		"airline": d.code, "type": res.get("type", ""), "reg": res.get("reg", ""), "dep": res.get("dep", ""), "arr": res.get("arr", ""),
		"place": place, "counts": c, "cause": inv.get("probable_cause", ""), "pilot": d.pilot, "fire": af.get("fire", false),
		"ditching": ditch, "victims": af.get("victims", []), "x": crash.get("x", 0.0), "z": crash.get("z", 0.0),
		"heading": crash.get("heading", 0.0), "weather": res.get("weather", {}), "samples": samples.slice(maxi(samples.size() - 420, 0)),
		"player_died": bool(cons.get("dead", false)) and String(res.get("mode", "pilot")) == "pilot", "hero": bool(cons.get("hero", false)), "criminal": bool(cons.get("criminal", false)),
		"license": String(cons.get("license", "")), "pilot_share": float(inv.get("pilot_share", 0.0)), "report_days": int(inv.get("report_days", 120)),
		"summary": "%d of %d aboard killed" % [fatal, aboard] if fatal > 0 else "all %d aboard survived" % aboard}
	incidents.append(inc)
	var r := U.rng(U.hash_str(String(inc.id)))
	var video := {"type": "reconstruction", "incident": inc.id}
	var verb := "ditches" if ditch else ("crashes" if fatal > 0 or float(af.get("severity", 0.5)) > 0.4 else "crash-lands")
	var a1 := publish("skyline", "breaking", "BREAKING: %s flight %s %s %s" % [d.airline, d.num, verb, place],
		"A %s operated by %s with %d people on board has %s %s. Emergency services are on the scene." % [d.type, d.airline, aboard,
			"come down in the water" if ditch else "crashed", place],
		["The flight was operating from %s to %s." % [d.from, d.to],
		"Witnesses describe %s." % (_pick(r, ["a loud bang followed by a column of black smoke", "the aircraft coming in very low and fast", "a huge splash and people climbing onto the wings"]) if not ditch else "the aircraft gliding down and skimming across the water"),
		"%s said it was \"aware of an incident\" and that its priority was the passengers, crew and their families." % d.airline],
		{"importance": 3, "video": video, "incident": inc.id, "place": place, "tags": ["accident", d.code]})
	var sid := _id("S")
	stories.append({"id": sid, "kind": "accident", "incident": inc.id, "stage": 0, "next_t": WorldSim.clock + 4.0 * 3600.0})
	a1.story = sid
	# the first wave on social media
	for i in 5 + mini(aboard / 20, 8):
		var who := _citizen(r)
		var txt := _pick(r, ["Just heard a massive bang near %s. Sirens everywhere. Praying for everyone on that plane." % _place_noun(place),
			"Smoke visible from miles away. What happened?? #%s" % d.num, "My cousin was supposed to fly %s today. Can't reach her. Please share. #%s" % [d.airline, d.num],
			"Thoughts with everyone on %s %s." % [d.airline, d.num], "Speculating now is pointless. Wait for the investigators.",
			"That's the %s fleet. Wasn't there an incident last year?" % d.short, "Emergency services were incredibly fast. Respect."])
		if ditch:
			txt = _pick(r, ["People standing on the wings in the water!! Boats everywhere #%s" % d.num, "The pilot put it down in the water. Unbelievable.",
				"Everyone seems to be getting off. Please let them all be okay."])
		post(who, txt, {"story": sid, "importance": 2, "video": r.randf() < 0.25, "spread": 1.0})
	post(_airline_author(d.code), "We can confirm that flight %s from %s to %s has been involved in an accident. A family assistance line is open. More information will follow." % [d.num, d.from, d.to],
		{"story": sid, "importance": 3})


func _flight_story(res: Dictionary, cons: Dictionary) -> void:
	var d := _flight_desc(res)
	var r := U.rng(U.hash_str(String(res.get("flight_id", "")) + "news"))
	var incs: Array = res.get("incidents", [])
	var evs: Array = res.get("events", [])
	var td: Dictionary = res.get("touchdown", {})
	var vs := absf(float(td.get("vs_fpm", 300.0)))
	var pax := int(res.get("pax", 0))
	var place := String(d.landed_at)
	var big := false
	for e in evs:
		var lab := String(e.get("label", ""))
		if float(e.get("severity", 0.0)) >= 0.6:
			big = true
			publish("gazette", "incident", "%s flight lands safely after %s" % [d.airline, lab.to_lower()],
				"%s %s from %s landed at %s after the crew dealt with %s. %s" % [d.airline, d.num, d.from, place, lab.to_lower(),
					"Nobody was hurt." if incs.is_empty() else "The aircraft has been taken out of service for inspection."],
				["Passengers praised the crew's calm announcements.", "The airline thanked passengers for their patience."],
				{"importance": 2, "video": {"type": "report", "airport": res.get("arr", ""), "airline": d.code, "type_id": res.get("type", ""), "scene": "emergency_landing"},
					"place": place, "tags": ["incident", d.code]})
			for i in 3:
				post(_citizen(r), _pick(r, ["Scariest flight of my life on %s today. Huge thanks to the crew." % d.num,
					"Fire trucks waiting for us on the runway. Everyone clapped when we stopped.", "Crew were amazing. Captain kept us informed the whole time."]),
					{"importance": 2, "video": r.randf() < 0.4, "spread": 1.0})
	for k in incs:
		match String(k):
			"tailstrike", "gear_collapse", "wingstrike", "engine_strike":
				big = true
				publish("aeroweek", "incident", "%s %s damaged in %s at %s" % [d.airline, d.short, String(k).replace("_", " "), place],
					"A %s operated by %s suffered damage on %s. The regulator has opened an investigation into the serious incident." % [d.type, d.airline, "landing" if k != "tailstrike" else "takeoff or landing"],
					["No injuries were reported.", "The aircraft remains grounded pending repairs."], {"importance": 2, "tags": ["incident", d.code]})
	if not big and pax > 40 and vs < 70.0 and r.randf() < 0.35:
		post(_citizen(r), _pick(r, ["Did we even land?? Butter. Absolute butter. #%s" % d.num, "That landing into %s was so smooth the whole plane clapped." % place,
			"Whoever flew %s today: chef's kiss." % d.num]), {"importance": 2, "video": true})
	elif not big and vs > 600.0 and pax > 20:
		post(_citizen(r), _pick(r, ["That landing at %s rattled my teeth. Everyone OK?" % place, "Pretty sure the pilot was trying to plant the plane in the runway lol"]),
			{"importance": 1})
	if float(res.get("late_min", 0.0)) > 45.0 and pax > 0:
		post(_citizen(r), "%d minutes late on %s again. Missed my connection. #%s" % [int(res.get("late_min", 0.0)), d.airline.replace(" ", ""), d.code], {"importance": 1})
	for m in cons.get("messages", []):
		if String(m).begins_with("Promoted") or String(m).begins_with("Command upgrade"):
			publish("aeroweek", "people", "People moves: %s promoted at %s" % [d.pilot, d.airline], String(m), [], {"importance": 1, "tags": ["people"]})


# ================================================================== evolving stories
func on_clock(t0: float, t1: float) -> void:
	# a long skip (rest, medical leave, waiting out a suspension) can pass several story beats
	for s in stories.duplicate():
		var guard := 0
		while float(s.next_t) <= t1 and s in stories and guard < 12:
			_advance_story(s)
			guard += 1
	var day := int(t1 / 86400.0)
	if day != _last_day:
		if _last_day >= 0:
			_daily(day)
		_last_day = day


static func _place_noun(place: String) -> String:
	## "12 km east of Rivermouth" -> "Rivermouth", "over the Southern Sea" -> "Southern Sea".
	var p := place
	if " of " in p:
		p = p.substr(p.rfind(" of ") + 4)
	for pre in ["in the sea ", "over the ", "in the ", "in rural ", "in ", "near ", "at "]:
		if p.begins_with(pre):
			p = p.substr(pre.length())
	return p


func _find_incident(id: String) -> Dictionary:
	for i in incidents:
		if String(i.id) == id:
			return i
	return {}


func _advance_story(s: Dictionary) -> void:
	if String(s.kind) != "accident":
		stories.erase(s)
		return
	var inc := _find_incident(String(s.incident))
	if inc.is_empty():
		stories.erase(s)
		return
	var r := U.rng(U.hash_ints(U.hash_str(String(s.id)), int(s.stage)))
	var al := Airlines.get_al(String(inc.airline))
	var aname := String(al.get("name", "the airline"))
	var c: Dictionary = inc.counts
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	var place := String(inc.place)
	var sid := String(s.id)
	var tpl := AircraftTypes.get_type(String(inc.type))
	s.stage = int(s.stage) + 1
	var at := float(s.next_t)
	match int(s.stage):
		1:
			var head := "%d killed as %s jet crashes %s" % [fatal, aname, place] if fatal > 0 else ("All %d on board survive %s %s" % [aboard, aname, "ditching" if bool(inc.ditching) else "crash"])
			publish("herald", "news", head, "%s %s. %d people were on board the %s." % [aname, "confirmed the deaths of %d people" % fatal if fatal > 0 else "said everyone on board had been accounted for", aboard, tpl.name],
				["%s, chief executive of %s, said: \"Our hearts are with the families. We will cooperate fully with the investigation.\"" % [al.get("ceo", "The chief executive"), aname],
				"%d people were taken to hospital, %d of them in a critical condition." % [int(c.get("serious", 0)) + int(c.get("critical", 0)), int(c.get("critical", 0))],
				"The National Transport Safety Board has opened an investigation. The flight recorders have been recovered."],
				{"t": at, "story": sid, "importance": 3, "incident": inc.id, "place": place, "video": {"type": "reconstruction", "incident": inc.id}, "tags": ["accident"]})
			s.next_t = at + 18.0 * 3600.0
		2:
			var victims: Array = inc.victims
			if victims.is_empty():
				s.next_t = at + 24.0 * 3600.0
				return
			var names := []
			for v in victims.slice(0, 8):
				names.append("%s, %d, from %s" % [v.name, int(v.age), v.home])
			publish("herald", "news", "The victims of flight %s: the people we lost" % String(inc.get("num", "")),
				"Families have begun paying tribute to the %d people who died %s." % [fatal, place],
				["Among those who died were %s." % "; ".join(names)] + _tributes(victims, r),
				{"t": at, "story": sid, "importance": 3, "incident": inc.id, "tags": ["accident", "victims"]})
			for v2 in victims.slice(0, 6):
				var fam := WorldSim.family_of(int(v2.get("id", -1))) if int(v2.get("id", -1)) >= 0 else []
				if fam.is_empty():
					continue
				var m: Dictionary = fam[r.randi() % fam.size()]
				if String(m.get("status", "alive")) != "alive" or int(m.get("age", 30)) < 14:
					continue
				var rel := WorldSim.relation_word(m, WorldSim.person(int(v2.id)))
				post({"name": m.name, "handle": Names.handle(r, m), "id": m.id}, _pick(r, ["My %s %s was on that plane. I can't believe I'm writing this." % [rel, String(v2.name).split(" ")[0]],
					"Rest in peace, %s. You were the best %s anyone could ask for." % [String(v2.name).split(" ")[0], rel],
					"Please stop sending me the videos. That was my %s." % rel]), {"t": at, "story": sid, "importance": 2, "spread": 2.0})
			s.next_t = at + 30.0 * 3600.0
		3:
			publish("skyline", "feature", "\"I thought I was going to die\": survivors of the %s crash speak" % _place_noun(place),
				"Passengers who escaped the %s have described the final moments of the flight." % ("wreckage" if not bool(inc.ditching) else "aircraft as it sank"),
				_survivor_quotes(inc, r), {"t": at, "story": sid, "importance": 2, "incident": inc.id, "video": {"type": "reconstruction", "incident": inc.id, "angle": "witness"}, "tags": ["accident", "survivors"]})
			s.next_t = at + 3.0 * 86400.0
		4:
			publish("aeroweek", "analysis", "Preliminary report: %s" % String(inc.cause).trim_suffix("."),
				"Investigators have released their preliminary findings into the loss of the %s %s." % [aname, tpl.short],
				["Flight data shows the aircraft's final moments in detail; the report includes a reconstruction of the flight path.",
				"Probable cause (preliminary): %s" % inc.cause, "The final report is expected within %d months." % maxi(int(inc.report_days) / 30, 2)],
				{"t": at, "story": sid, "importance": 2, "incident": inc.id, "video": {"type": "reconstruction", "incident": inc.id, "angle": "analysis"}, "tags": ["investigation"]})
			post(_outlet_author("skywatch"), "The preliminary report on the %s %s is out. Key line: %s" % [aname, tpl.short, inc.cause], {"t": at, "story": sid, "importance": 2})
			s.next_t = at + 4.0 * 86400.0
		5:
			var pilot := String(inc.pilot)
			if bool(inc.player_died):
				publish("herald", "obituary", "Captain %s remembered" % pilot, "Colleagues have paid tribute to %s, who was at the controls of the flight." % pilot,
					["\"A dedicated aviator who loved flying,\" a colleague said.", "The investigation into the cause of the accident continues."],
					{"t": at, "story": sid, "importance": 2, "tags": ["pilot"]})
			elif bool(inc.hero):
				publish("skyline", "feature", "Hero pilot %s: \"I just did my job\"" % pilot, "The pilot who brought the aircraft down safely has spoken for the first time.",
					["Passengers have started a campaign to have the crew honoured.", "%s thanked the cabin crew, who evacuated everyone in minutes." % pilot],
					{"t": at, "story": sid, "importance": 3, "tags": ["pilot", "hero"]})
				for i in 4:
					post(_citizen(r), _pick(r, ["%s is a hero. That's all." % pilot, "Give that crew a medal.", "Watched the landing video ten times. Incredible airmanship."]),
						{"t": at, "story": sid, "importance": 2, "spread": 2.0})
			elif bool(inc.criminal):
				publish("herald", "news", "Prosecutors open case against pilot of doomed flight", "Authorities are investigating %s over the deaths of %d people." % [pilot, fatal],
					["The pilot's licence has been revoked.", "Families welcomed the decision. \"We want answers,\" one relative said."],
					{"t": at, "story": sid, "importance": 2, "tags": ["pilot", "court"]})
			elif String(inc.license) != "":
				publish("aeroweek", "news", "Pilot of %s flight %s" % [aname, "loses licence" if String(inc.license) == "revoked" else "suspended pending inquiry"],
					"The regulator has taken action against the pilot in command of the accident flight.", [], {"t": at, "story": sid, "importance": 1, "tags": ["pilot"]})
			s.next_t = at + 7.0 * 86400.0
		6:
			if fatal > 0:
				publish("gazette", "news", "Hundreds gather to remember the victims of the %s crash" % _place_noun(place), "A memorial service was held for the %d people who died." % fatal,
					["Candles and flowers lined the road near the crash site.", "Survivors attended alongside families of the victims."],
					{"t": at, "story": sid, "importance": 2, "tags": ["memorial"]})
			s.next_t = at + maxf(float(inc.report_days) - 18.0, 20.0) * 86400.0
		7:
			publish("aeroweek", "analysis", "Final report: %s" % String(inc.cause).trim_suffix("."), "The investigation into the accident %s has concluded." % place,
				["Investigators attributed %d%% of the causal factors to the flight crew." % int(float(inc.pilot_share) * 100.0),
				"%s has issued safety recommendations to the operator, the manufacturer and the regulator." % "The board"],
				{"t": at, "story": sid, "importance": 2, "incident": inc.id, "video": {"type": "reconstruction", "incident": inc.id, "angle": "analysis"}, "tags": ["investigation", "final report"]})
			s.next_t = at + 300.0 * 86400.0
		_:
			publish("herald", "news", "One year on: %s remembers" % _place_noun(place), "A year after the accident, families and survivors return to the site.",
				["Several survivors are still recovering from their injuries."], {"t": at, "story": sid, "importance": 1, "tags": ["anniversary"]})
			stories.erase(s)


func _tributes(victims: Array, r: RandomNumberGenerator) -> Array:
	var out := []
	for v in victims.slice(0, 3):
		var first := String(v.name).split(" ")[0]
		var job := String(v.get("job", ""))
		out.append(_pick(r, ["%s, a %s, was described by friends as \"the life of every party\"." % [first, job],
			"%s's family said %s \"lived for the people around them\"." % [first, "they"],
			"Colleagues of %s, who worked as a %s, left flowers outside their office." % [first, job]]))
	return out


func _survivor_quotes(inc: Dictionary, r: RandomNumberGenerator) -> Array:
	var out := []
	var c: Dictionary = inc.counts
	var lines_crash := ["\"There was a bang and then everything went sideways. I just remember the smell of fuel.\"",
		"\"The crew were shouting 'heads down, stay down'. I owe them my life.\"",
		"\"I unbuckled and the smoke was already at the ceiling. A man pulled me toward the exit.\"",
		"\"It went completely silent for a second. Then the screaming started.\""]
	var lines_ditch := ["\"The water came in so fast. We climbed onto the wing and waited for the boats.\"",
		"\"The captain said brace, and then it felt like hitting a wall of water.\"", "\"Everyone helped each other. Strangers held hands on the wing.\""]
	for i in 3:
		var p := WorldSim.person(r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1))
		out.append("%s, %d, from %s: %s" % [p.name, int(p.age), p.home, _pick(r, lines_ditch if bool(inc.ditching) else lines_crash)])
	out.append("%d survivors remain in hospital." % (int(c.get("critical", 0)) + int(c.get("serious", 0))))
	return out


# ================================================================== background world
func background_story(kind: String, f: Dictionary, t: float, seed_v: int) -> void:
	var r := U.rng(seed_v)
	var al := Airlines.get_al(String(f.airline))
	var aname := String(al.get("name", "An airline"))
	var tpl := AircraftTypes.get_type(String(f.type))
	var from := Airports.get_ap(String(f.from)).get("short", "")
	var to := Airports.get_ap(String(f.to)).get("short", "")
	var num := String(f.number)
	var video := {"type": "report", "airport": f.to, "airline": f.airline, "type_id": f.type, "scene": "arrival"}
	match kind:
		"medical_diversion":
			var div = Airports.get_ap(String(Airports.ORDER[r.randi() % Airports.ORDER.size()])).short
			publish("gazette", "news", "%s flight diverts to %s for passenger medical emergency" % [aname, div],
				"Flight %s from %s to %s diverted after a passenger fell ill on board." % [num, from, to], ["Paramedics met the aircraft on arrival.", "The flight later continued."],
				{"t": t, "importance": 1, "video": {"type": "report", "airport": f.from, "airline": f.airline, "type_id": f.type, "scene": "emergency_landing"}, "tags": ["diversion"]})
			post(_citizen(r), "Our flight diverted because someone got sick. Crew were brilliant. Hope they're okay. #%s" % num, {"t": t, "importance": 1})
		"bird_strike_return":
			publish("aeroweek", "news", "%s %s returns to %s after bird strike" % [aname, tpl.short, from], "The crew of %s declared an emergency shortly after takeoff." % num,
				["The aircraft landed safely; engineers found damage to one engine."], {"t": t, "importance": 1, "video": {"type": "report", "airport": f.from, "airline": f.airline, "type_id": f.type, "scene": "emergency_landing"}, "tags": ["incident"]})
			post(_citizen(r), "Heard a bang on takeoff and we came straight back. Bird strike apparently! #%s" % num, {"t": t, "importance": 1, "video": r.randf() < 0.3})
		"turbulence_injuries":
			var n := r.randi_range(2, 9)
			publish("skyline", "news", "%d hurt as %s flight hits severe turbulence" % [n, aname], "Passengers and crew were injured when %s encountered severe turbulence." % num,
				["Several were not wearing seatbelts.", "The airline reminded passengers to keep belts fastened when seated."], {"t": t, "importance": 2, "video": video, "tags": ["turbulence"]})
			for i in 2:
				post(_citizen(r), _pick(r, ["Drinks on the ceiling. People screaming. Worst 10 seconds of my life.", "WEAR YOUR SEATBELT. Seriously. #%s" % num]), {"t": t, "importance": 2, "video": true})
		"tech_return":
			publish("gazette", "news", "%s flight returns to %s with technical problem" % [aname, from], "Flight %s turned back as a precaution." % num, [], {"t": t, "importance": 1, "tags": ["incident"]})
		"unruly_passenger":
			publish("gazette", "news", "Police meet %s flight after disruptive passenger" % aname, "A passenger was removed from flight %s at %s." % [num, to],
				["Cabin crew restrained the passenger with help from others on board."], {"t": t, "importance": 1, "tags": ["cabin"]})
			post(_citizen(r), "Some guy on %s tried to open the door mid-flight. Crew handled it like pros." % num, {"t": t, "importance": 2, "video": true})
		"weather_diversion":
			publish("skyline", "news", "Storms force diversions at %s" % to, "Several flights including %s were unable to land at %s." % [num, to],
				["Thunderstorms brought heavy rain and gusts.", "Delays are expected to continue into the evening."], {"t": t, "importance": 1, "video": video, "tags": ["weather"]})
		"record_traffic":
			publish("herald", "business", "%s airport handles record passenger numbers" % from, "Airport bosses say demand has never been higher.", [], {"t": t, "importance": 1, "tags": ["business"]})
		"new_route":
			publish("aeroweek", "business", "%s to launch new %s - %s service" % [aname, from, to], "The airline will deploy the %s on the route." % tpl.name, [], {"t": t, "importance": 1, "tags": ["routes"]})


func _daily(day: int) -> void:
	## One look at the world each day: storms closing airports, aviation chatter.
	var r := U.rng(U.hash_ints(WorldSim.world_seed, day, 919))
	for icao in Airports.ORDER:
		var ap: Dictionary = Airports.get_ap(icao)
		var w := WeatherModel.sample(float(ap.x), float(ap.z), float(day) * 86400.0 + 15.0 * 3600.0)
		if float(w.get("storm", 0.0)) > 0.8 and r.randf() < 0.35 and WorldSim.airport_open(icao):
			WorldSim.close_airport(icao, r.randf_range(1.0, 3.0), "thunderstorms")
			publish("skyline", "news", "Thunderstorms halt flights at %s" % ap.short, "Departures and arrivals were suspended as storms passed over %s." % ap.short,
				[], {"t": float(day) * 86400.0 + 15.0 * 3600.0, "importance": 1, "tags": ["weather"]})
	if r.randf() < 0.5:
		var who := _citizen(r)
		post(who, _pick(r, ["Window seat, sunset, %s coastline. Never gets old." % Airports.get_ap(Airports.ORDER[r.randi() % 5]).short,
			"Spotted a %s on short final today, what a beauty." % AircraftTypes.get_type(AircraftTypes.ORDER[r.randi() % AircraftTypes.ORDER.size()]).name,
			"Why is airport coffee always this expensive", "Delayed again. At least the gate has power sockets."]), {"t": float(day) * 86400.0 + r.randf() * 86400.0, "importance": 0})


# ================================================================== queries and persistence
func latest(count: int = 20, filter_kind: String = "") -> Array:
	var out := []
	for i in range(articles.size() - 1, -1, -1):
		var a: Dictionary = articles[i]
		if float(a.t) > WorldSim.clock + 60.0:
			continue
		if filter_kind == "" or String(a.kind) == filter_kind or filter_kind in a.get("tags", []):
			out.append(a)
			if out.size() >= count:
				break
	return out


func feed(count: int = 40, story: String = "") -> Array:
	var out := []
	for i in range(posts.size() - 1, -1, -1):
		var p: Dictionary = posts[i]
		if float(p.t) > WorldSim.clock + 60.0:
			continue
		if story == "" or String(p.story) == story:
			out.append(p)
			if out.size() >= count:
				break
	return out


func article(id: String) -> Dictionary:
	for a in articles:
		if String(a.id) == id:
			return a
	return {}


func incident(id: String) -> Dictionary:
	return _find_incident(id)


func replay(id: String) -> Dictionary:
	for rp in replays:
		if String(rp.get("id", "")) == id:
			return rp
	return {}


func serialize() -> Dictionary:
	return {"incidents": incidents, "articles": articles, "stories": stories, "posts": posts, "next": _next, "last_day": _last_day,
		"replays": replays}


func deserialize(d: Dictionary) -> void:
	incidents = d.get("incidents", [])
	articles = d.get("articles", [])
	stories = d.get("stories", [])
	posts = d.get("posts", [])
	replays = d.get("replays", [])
	_next = int(d.get("next", 1))
	_last_day = int(d.get("last_day", -1))


func reset() -> void:
	incidents.clear()
	articles.clear()
	stories.clear()
	posts.clear()
	replays.clear()
	_next = 1
	_last_day = -1
