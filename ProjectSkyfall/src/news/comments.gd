class_name NewsComments
extends RefCounted
## Comment sections for news stories and videos. Every article gets hundreds of comments,
## written lazily and deterministically from the story itself (same story, same thread) and
## filling in as the story ages: grief and condolences, anger at the airline, enthusiasts'
## technical takes on the aircraft and the weather, pilots defending the crew, misinformation
## and the people correcting it, eyewitnesses, families, nervous flyers, and jokes only when
## nobody was hurt. Authors come from the persistent population, plus verified pilots,
## experts, outlets and airlines.

const PAGE := 20

## Thread moods and how often each tone appears in them.
const MIX := {
	"fatal": {"condolence": 30, "anger": 14, "technical": 12, "pilot": 7, "misinfo": 7, "eyewitness": 6, "family": 5, "nervous": 6, "media": 5, "question": 8},
	"survived": {"survived": 30, "technical": 14, "pilot": 9, "anger": 7, "misinfo": 5, "eyewitness": 7, "family": 4, "nervous": 8, "media": 4, "question": 8, "praise": 10},
	"incident": {"relief": 24, "joke": 16, "technical": 16, "complaint": 10, "praise": 12, "nervous": 8, "question": 8},
	"weather": {"weather": 40, "complaint": 18, "technical": 12, "joke": 10, "praise": 8, "question": 8},
	"business": {"business": 50, "complaint": 15, "technical": 15, "joke": 8, "question": 10},
	"general": {"general": 45, "joke": 15, "technical": 15, "complaint": 10, "question": 10},
}
## Which tones answer which.
const REPLIES := {
	"condolence": ["amen", "amen", "amen", "hug"],
	"anger": ["agree_anger", "defend", "wait", "airline", "agree_anger"],
	"technical": ["tech_more", "armchair", "agree", "tech_more"],
	"pilot": ["thanks_pilot", "thanks_pilot", "pushback", "agree"],
	"misinfo": ["correction", "correction", "double_down", "correction", "correction"],
	"eyewitness": ["ask_witness", "investigators", "amen"],
	"family": ["hug", "hug", "amen"],
	"nervous": ["reassure", "reassure", "nervous_too", "reassure"],
	"media": ["agree", "defend_media"],
	"question": ["answer", "answer", "dont_know"],
	"survived": ["agree", "amen", "praise_crew"],
	"praise": ["agree", "praise_crew"],
	"relief": ["agree", "lol", "praise_crew"],
	"joke": ["lol", "lol", "too_soon", "agree"],
	"complaint": ["complaint_reply", "agree", "lol"],
	"weather": ["agree", "complaint_reply", "reassure"],
	"business": ["agree", "complaint_reply", "lol"],
	"general": ["agree", "lol"],
	"pinned": ["amen", "agree"],
}

const PILOT_TITLES := ["%s captain", "%s first officer", "Retired airline captain", "Flight instructor", "Cargo pilot", "%s line training captain"]
const EXPERT_TITLES := ["Aviation safety analyst", "Former CTSB investigator", "Aerospace engineer", "Air traffic controller", "Aviation journalist", "Licensed aircraft engineer"]

static var _cache := {}


# ================================================================== thread setup
## Everything a thread needs to know about its story, worked out once per article.
static func context(art: Dictionary) -> Dictionary:
	var key := String(art.get("id", ""))
	if _cache.has(key):
		return _cache[key]
	var inc := News.incident(String(art.get("incident", "")))
	if inc.is_empty() and String(art.get("story", "")) != "":
		for s in News.stories:
			if String(s.get("id", "")) == String(art.story) and String(s.get("incident", "")) != "":
				inc = News.incident(String(s.incident))
				break
	var tags: Array = art.get("tags", [])
	var mood := "general"
	var c: Dictionary = inc.get("counts", {})
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	if not inc.is_empty():
		mood = "fatal" if fatal > 0 else "survived"
	elif tags.has("weather"):
		mood = "weather"
	elif tags.has("business") or tags.has("routes") or String(art.get("kind", "")) == "business":
		mood = "business"
	elif tags.has("incident") or tags.has("turbulence") or tags.has("diversion") or tags.has("cabin") or String(art.get("kind", "")) == "incident":
		mood = "incident"
	var seed_v := U.hash_str(key + String(art.get("headline", "")))
	var r := U.rng(seed_v)
	var imp := int(art.get("importance", 1))
	var total := 60
	match mood:
		"fatal":
			total = 650 + mini(fatal, 200) * 7 + imp * 120 + r.randi_range(0, 260)
		"survived":
			total = 380 + imp * 90 + r.randi_range(0, 240)
		"incident":
			total = 140 + imp * 70 + r.randi_range(0, 160)
		"weather":
			total = 90 + imp * 40 + r.randi_range(0, 110)
		"business":
			total = 45 + imp * 30 + r.randi_range(0, 90)
		_:
			total = 30 + imp * 25 + r.randi_range(0, 70)
	var ctx := {"seed": seed_v, "mood": mood, "total": total, "t0": float(art.get("t", WorldSim.clock)), "tau": 9.0 * 3600.0 if mood in ["fatal", "survived"] else 5.0 * 3600.0,
		"likes": {"fatal": 5200.0, "survived": 2600.0, "incident": 700.0, "weather": 260.0, "business": 180.0}.get(mood, 120.0) * (0.6 + 0.4 * float(imp)),
		"outlet": String(art.get("outlet", "skyline")), "tags": tags, "f": _facts(art, inc, r)}
	_cache[key] = ctx
	return ctx


static func _facts(art: Dictionary, inc: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var code := String(inc.get("airline", ""))
	var type_id := String(inc.get("type", ""))
	if code == "":
		for c in Airlines.all_codes():
			if String(art.get("headline", "")).contains(String(Airlines.get_al(c).get("name", "?#"))):
				code = c
				break
	if code == "":
		code = String(U.pick(r, Airlines.all_codes()))
	if type_id == "":
		for tid in AircraftTypes.ORDER:
			var tt := AircraftTypes.get_type(tid)
			if String(art.get("headline", "")).contains(String(tt.short)) or String(art.get("lede", "")).contains(String(tt.name)):
				type_id = tid
				break
	if type_id == "":
		type_id = "s320"
	var al := Airlines.get_al(code)
	var t := AircraftTypes.get_type(type_id)
	var c: Dictionary = inc.get("counts", {})
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	var injured := int(c.get("critical", 0)) + int(c.get("serious", 0)) + int(c.get("minor", 0))
	var w: Dictionary = inc.get("weather", {})
	var wind := int(float(w.get("wind_kt", 0.0)))
	var vis := float(w.get("vis", 10000.0))
	var wx := "calm and clear"
	if float(w.get("storm", 0.0)) > 0.5:
		wx = "thunderstorms with %d-knot winds" % maxi(wind, 18)
	elif vis < 1500.0:
		wx = "thick fog, visibility around %d metres" % int(snappedf(vis, 50.0))
	elif float(w.get("precip", 0.0)) > 0.4:
		wx = "heavy rain and %d knots of wind" % wind
	elif wind >= 18:
		wx = "gusty, %d knots of wind" % wind
	elif not w.is_empty():
		wx = "fairly benign, %d knots of wind" % wind
	var crash: Dictionary = inc.get("crash", {})
	var smp: Array = inc.get("samples", [])
	var vs := absf(float(crash.get("vs_fpm", 0.0)))
	var spd := float(crash.get("speed_kt", 0.0))
	if smp.size() > 2:
		var last: Array = smp[smp.size() - 1]
		if vs < 1.0 and last.size() > 5:
			vs = absf(float(last[5])) * 196.85
		if spd < 1.0 and last.size() > 4:
			spd = float(last[4])
	var place := String(inc.get("place", art.get("place", "")))
	if place == "":
		place = "the airport"
	var dep := Airports.get_ap(String(inc.get("dep", ""))).get("short", "")
	var arr := Airports.get_ap(String(inc.get("arr", ""))).get("short", "")
	if String(dep) == "":
		dep = Airports.get_ap(Airports.ORDER[r.randi() % Airports.ORDER.size()]).get("short", "Port Calder")
	if String(arr) == "":
		arr = Airports.get_ap(Airports.ORDER[r.randi() % Airports.ORDER.size()]).get("short", "Rivera")
	var cause := String(inc.get("cause", ""))
	var o: Dictionary = News.OUTLETS.get(String(art.get("outlet", "skyline")), {"name": "the news"})
	return {"airline": String(al.get("name", "the airline")), "iata": String(al.get("iata", "")), "num": String(inc.get("num", "")) if String(inc.get("num", "")) != "" else "the flight",
		"type": "%s %s" % [t.maker, t.name], "short": String(t.short), "maker": String(t.maker), "place": place.trim_prefix("in ").trim_prefix("near "),
		"fatal": str(fatal), "aboard": str(aboard), "survivors": str(maxi(aboard - fatal, 0)), "injured": str(injured), "from": String(dep), "to": String(arr),
		"pilot": String(inc.get("pilot", "the captain")), "cause": cause.to_lower() if cause != "" else "", "wx": wx, "wind": str(wind),
		"wx_hard": wx if not (wx.begins_with("calm") or wx.begins_with("fairly")) else "",
		"cause_s": (cause.substr(0, 1).to_upper() + cause.substr(1).trim_suffix(".") + ".") if cause != "" else "",
		"vs": U.fmt_int(int(snappedf(vs, 100.0))) if vs > 50.0 else "", "speed": str(int(snappedf(spd, 5.0))) if spd > 20.0 else "",
		"reg": String(inc.get("reg", "")) if String(inc.get("reg", "")) != "" else "the aircraft", "outlet": String(o.name),
		"year": str(2008 + int(U.hash_str(String(inc.get("reg", "x")))) % 17), "fire": bool(inc.get("fire", false)), "ditch": bool(inc.get("ditching", false)),
		"mins": str(8 + r.randi() % 40)}


## Total comments the thread will reach, and how many have been written by now.
static func total(art: Dictionary) -> int:
	return int(context(art).total)


static func count(art: Dictionary) -> int:
	var ctx := context(art)
	var age := WorldSim.clock - float(ctx.t0)
	if age <= 0.0:
		return 0
	var n := float(ctx.total) * (1.0 - exp(-age / float(ctx.tau))) / 0.97
	return clampi(int(n), mini(3, int(ctx.total)), int(ctx.total))


# ================================================================== comments
## One page of top-level comments (with reply counts; replies come from replies()).
## sort: "top" or "new".
static func page(art: Dictionary, sort: String, offset: int, n: int = PAGE) -> Array:
	var ctx := context(art)
	var have := count(art)
	var idx := []
	if sort == "new":
		for i in range(have - 1, -1, -1):
			idx.append(i)
		if have > 0 and String(ctx.mood) in ["fatal", "survived", "incident"]:
			idx.erase(0)
			idx.push_front(0)
	else:
		var heads := []
		for i in have:
			heads.append([_likes(ctx, i), i])
		heads.sort_custom(func(a, b): return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
		for h in heads:
			idx.append(h[1])
		if have > 0 and String(ctx.mood) in ["fatal", "survived", "incident"]:
			idx.erase(0)
			idx.push_front(0)
	var out := []
	for k in range(offset, mini(offset + n, idx.size())):
		out.append(comment(art, int(idx[k])))
	return out


## Top-level comment number i of the thread.
static func comment(art: Dictionary, i: int) -> Dictionary:
	var ctx := context(art)
	var f: Dictionary = ctx.f
	var r := U.rng(U.hash_ints(int(ctx.seed), i, 11))
	var mood := String(ctx.mood)
	var tone := "pinned" if i == 0 and mood in ["fatal", "survived", "incident"] else _tone(ctx, r)
	var author := _author(r, tone, ctx)
	var text := _text(tone, r, f, mood)
	var likes := _likes(ctx, i)
	var hr := U.rng(U.hash_ints(int(ctx.seed), i, 3))
	var nrep := int(minf(90.0, sqrt(float(likes)) * hr.randf_range(0.05, 0.6) + hr.randf() * 2.5))
	if tone == "misinfo":
		nrep = maxi(nrep, 3 + hr.randi() % 6)
	elif tone in ["question", "nervous", "anger"]:
		nrep = maxi(nrep, 1 + hr.randi() % 4)
	return {"i": i, "tone": tone, "author": author, "text": text, "likes": likes, "t": _time(ctx, i), "replies": nrep,
		"edited": hr.randf() < 0.05, "pinned": tone == "pinned", "depth": 0}


## Replies to top-level comment `parent` (a page of them, with nested answers flattened in
## order and marked by depth).
static func replies(art: Dictionary, parent: Dictionary, offset: int, n: int = 6) -> Array:
	var ctx := context(art)
	var f: Dictionary = ctx.f
	var out := []
	var pt := String(parent.tone)
	var pool: Array = REPLIES.get(pt, ["agree"])
	for j in range(offset, mini(offset + n, int(parent.replies))):
		var r := U.rng(U.hash_ints(int(ctx.seed), int(parent.i) * 1000 + j, 29))
		var tone := String(pool[r.randi() % pool.size()])
		var t := float(parent.t) + 60.0 * pow(r.randf(), 2.0) * 600.0 + float(j) * 240.0
		var likes := int(float(parent.likes) * 0.25 * pow(r.randf(), 3.0))
		out.append({"i": j, "tone": tone, "author": _author(r, tone, ctx), "text": _reply_text(tone, r, f, parent, int(parent.i) * 7 + j), "likes": likes,
			"t": minf(t, WorldSim.clock - 30.0), "replies": 0, "edited": r.randf() < 0.03, "pinned": false, "depth": 1})
		# a short exchange under some replies
		if r.randf() < 0.22 and tone in ["correction", "double_down", "pushback", "armchair", "defend", "agree_anger", "answer", "too_soon"]:
			var back := {"correction": "double_down", "double_down": "correction", "pushback": "thanks_pilot", "armchair": "tech_more",
				"defend": "agree_anger", "agree_anger": "wait", "answer": "agree", "too_soon": "lol"}
			var t2 := String(back.get(tone, "agree"))
			var r2 := U.rng(U.hash_ints(int(ctx.seed), int(parent.i) * 1000 + j, 31))
			out.append({"i": j, "tone": t2, "author": parent.author if t2 in ["double_down", "agree_anger"] and r2.randf() < 0.6 else _author(r2, t2, ctx),
				"text": _reply_text(t2, r2, f, parent), "likes": int(float(likes) * r2.randf()), "t": minf(t + 900.0 * r2.randf(), WorldSim.clock - 20.0),
				"replies": 0, "edited": false, "pinned": false, "depth": 2})
	return out


static func _likes(ctx: Dictionary, i: int) -> int:
	if i == 0 and String(ctx.mood) in ["fatal", "survived", "incident"]:
		return int(float(ctx.likes) * 0.8)
	var r := U.rng(U.hash_ints(int(ctx.seed), i, 7))
	var early := 1.7 - 0.9 * float(i) / maxf(float(ctx.total), 1.0)
	return int(float(ctx.likes) * pow(r.randf(), 4.2) * early + r.randf() * 6.0)


static func _time(ctx: Dictionary, i: int) -> float:
	var u := (float(i) + 0.5) / (float(ctx.total) + 1.0) * 0.97
	var r := U.rng(U.hash_ints(int(ctx.seed), i, 13))
	return float(ctx.t0) + float(ctx.tau) * -log(1.0 - u) + r.randf_range(0.0, 90.0)


static func _tone(ctx: Dictionary, r: RandomNumberGenerator) -> String:
	var mix: Dictionary = MIX.get(String(ctx.mood), MIX.general)
	var tags: Array = ctx.tags
	var keys := mix.keys()
	var w := []
	for k in keys:
		var v := float(mix[k])
		if k == "family" and (tags.has("victims") or tags.has("memorial")):
			v *= 3.0
		if k == "pilot" and (tags.has("pilot") or tags.has("hero") or tags.has("court")):
			v *= 3.0
		if k == "technical" and (tags.has("investigation") or tags.has("final report")):
			v *= 2.5
		if k == "condolence" and tags.has("memorial"):
			v *= 2.0
		w.append(v)
	return String(U.pick_weighted(r, keys, w))


# ================================================================== authors
static func _author(r: RandomNumberGenerator, tone: String, ctx: Dictionary) -> Dictionary:
	var f: Dictionary = ctx.f
	if tone == "pinned":
		var o: Dictionary = News.OUTLETS.get(String(ctx.outlet), {"name": "News", "handle": "@news", "color": "4aa3df"})
		return {"name": String(o.name), "handle": String(o.handle), "badge": "outlet", "title": "", "color": Color.html(String(o.color))}
	if tone == "airline":
		return {"name": String(f.airline), "handle": "@" + String(f.airline).replace(" ", ""), "badge": "airline", "title": "Official account", "color": Color(0.2, 0.45, 0.8)}
	var badge := ""
	var title := ""
	if tone in ["pilot", "thanks_pilot"] and r.randf() < (0.85 if tone == "pilot" else 0.3):
		badge = "pilot"
		title = String(U.pick(r, PILOT_TITLES))
		if title.contains("%s"):
			title = title % String(f.short)
	elif tone in ["technical", "tech_more", "correction", "answer"] and r.randf() < 0.28:
		badge = "expert"
		title = String(U.pick(r, EXPERT_TITLES))
	var p := {}
	for k in 4:
		var id := r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1)
		p = WorldSim.person(id)
		if int(p.get("age", 30)) >= 16:
			break
	var name := String(p.get("name", "Someone"))
	if badge == "pilot" and r.randf() < 0.5:
		name = "Capt. " + name
	var col := Color.from_hsv(float(U.hash_str(name) % 360) / 360.0, 0.55, 0.78)
	return {"name": name, "handle": Names.handle(r, p), "badge": badge if badge != "" else ("verified" if r.randf() < 0.015 else ""), "title": title, "color": col,
		"home": String(p.get("home", ""))}


# ================================================================== text
static func _say(r: RandomNumberGenerator, list: Array, f: Dictionary, k: int = -1) -> String:
	var ok := []
	for s in list:
		var good := true
		for key in f:
			if str(f[key]) == "" and String(s).contains("{" + String(key) + "}"):
				good = false
				break
		if good:
			ok.append(s)
	if ok.is_empty():
		ok = list
	var i := r.randi() % ok.size() if k < 0 else k % ok.size()
	return String(ok[i]).format(f)


static func _join(r: RandomNumberGenerator, f: Dictionary, a: Array, b: Array, c: Array = []) -> String:
	var s := _say(r, a, f)
	if not b.is_empty() and r.randf() < 0.75:
		s += " " + _say(r, b, f)
	if not c.is_empty() and r.randf() < 0.5:
		var tail := _say(r, c, f)
		if tail != "":
			s += " " + tail
	return s.strip_edges()


static func _text(tone: String, r: RandomNumberGenerator, f: Dictionary, mood: String) -> String:
	# about half the time, a line from the larger bank (where it suits the story)
	var accident_only := tone in ["technical", "question", "eyewitness", "family", "misinfo", "condolence", "survived"]
	if CommentBank.LINES.has(tone) and r.randf() < 0.5 and (not accident_only or mood in ["fatal", "survived"]):
		return _say(r, CommentBank.LINES[tone], f)
	return _text_base(tone, r, f, mood)


static func _text_base(tone: String, r: RandomNumberGenerator, f: Dictionary, mood: String) -> String:
	match tone:
		"pinned":
			if mood == "fatal":
				return "Our live page on {num} has the latest verified information, including the number for families. Please be respectful - many people reading these comments lost someone. Comments are moderated.".format(f)
			if mood == "survived":
				return "All updates on {num} are on our live page. The {airline} family assistance line is open around the clock. Please keep comments respectful.".format(f)
			return "Thanks for your comments. Please keep it civil - we remove abuse and misinformation.".format(f)
		"condolence":
			return _join(r, f, [
				"Rest in peace to the {fatal} people on {num}.", "Heartbreaking news from {place}.", "Just saw this. I can't stop thinking about the families.",
				"Thinking of everyone who lost someone on {num}.", "{fatal} lives. Every one of them somebody's whole world.", "Praying for the families of everyone aboard {num}.",
				"This one hurts. I fly {airline} every month.", "So incredibly sad.", "My heart goes out to the crew's families too. They were doing their jobs.",
				"Absolutely devastating.", "I keep looking at the pictures from {place} and I can't believe it.", "Woke up to this news. My heart is broken.",
				"Somebody's mum, somebody's son, somebody's best friend. {fatal} times over.", "I was on {num} last month. Same route, same time. Chills.",
				"There are no words for this.", "The whole of {place} is grieving tonight."],
				["Hold your loved ones close tonight.", "No one should ever get that phone call.", "I hope the survivors pull through.",
				"Thank you to the firefighters and paramedics who worked through the night.", "The people of {place} have been amazing, opening their homes to relatives.",
				"Some of them were just going home.", "Fly high.", "May they rest in peace.", "Sending love from {to}.", "Thank you to everyone who rushed to help."],
				["Fly high.", "RIP.", "Never forgotten.", "Heartbroken.", "Praying for them all."])
		"survived":
			return _join(r, f, [
				"All {aboard} people walked away from that. Incredible.", "Whatever the crew did in those last seconds, it worked.",
				"Look at the pictures of that {short} and then remember everyone survived. Modern certification works.",
				"The cabin crew got everyone out. Heroes, every one of them.", "Glad everyone's okay, but I want to know how this happened.",
				"I'd buy {pilot} a drink every day for the rest of my life.", "{injured} injured but everyone alive. Thank God.",
				"A miracle at {place}.", "Seats, belts, brace positions, fast evacuation. That's why everyone is alive.",
				"I've watched the footage ten times. How did nobody die?", "Wreck like that and {aboard} survivors. Unreal."],
				["Listen to the safety briefing, people.", "The crew training paid off.", "Respect to the fire crews who were there in minutes.",
				"Wishing the injured a fast recovery.", "Let's hear what the investigation says."], ["Bravo.", "Thank God.", ""])
		"anger":
			return _join(r, f, [
				"{airline} has been cutting corners for years. Everyone in the industry knows it.", "How many more before {airline} is grounded?",
				"Funny how {airline} found money for a new livery but not for maintenance.", "Fly {airline}? Never again.", "The CEO should resign. Today.",
				"{airline} posting 'thoughts and prayers' while their lawyers are already drafting statements.", "Pilots have been warning about fatigue at {airline} for months. Nobody listened.",
				"Ticket prices go up every year and this is what we get?", "I want to see the maintenance records for {reg}. All of them.",
				"Regulators are asleep. This is on them too.", "Why was {num} even allowed to fly in {wx_hard}?", "Somebody at {airline} needs to go to prison for this."],
				["Disgraceful.", "Enough is enough.", "Follow the money.", "Ground the fleet until we know.", "Nobody will be held accountable, as usual.", ""])
		"technical":
			if mood == "incident":
				return _join(r, f, ["Bird strikes happen thousands of times a year and most are harmless. Turning back was the textbook call.",
					"Severe turbulence can exceed 1.5 g in an instant. Belts on whenever you're seated.", "The {short}'s engines are tested by firing frozen birds into them. Seriously.",
					"Diversions for medical emergencies are routine. Crews talk to doctors on the ground through the whole thing.",
					"A precautionary return is the system working, not failing. Nobody was in danger.", "The {type} can fly perfectly well on one engine. Returning on one is a non-event for the crew.",
					"Clear-air turbulence doesn't show on radar. That's why the belt sign matters."], ["Source: 20 years in maintenance.", "Good airmanship.", ""])
			if mood == "weather":
				return _join(r, f, ["Storm cells like that build 40,000 ft high in an hour. You don't fly through them; you go around or you wait.",
					"Windshear near a thunderstorm can eat 40 knots of airspeed in seconds. Holding is the right call.",
					"Lightning strikes on aircraft are surprisingly common and almost always harmless. Hail is the real problem.",
					"Diverting costs the airline a fortune. They only do it when they have to."], ["Patience, people.", ""])
			if mood in ["business", "general"]:
				return _join(r, f, ["The {short} burns a lot less fuel per seat than what flew this route before.", "Route economics are brutal. Load factors decide everything.",
					"The {type} is a great fit for a route this length.", "Slots at {to} are the real constraint, not aircraft.",
					"Watch the fares when a second airline starts flying it."], ["Just my two cents.", ""])
			return _join(r, f, [
				"Looking at the tracking data, they were descending at over {vs} ft/min at the end. That is not a normal approach.",
				"The {short} has an excellent safety record. Whatever happened is probably a chain of events, not one thing.",
				"Weather at the time was {wx_hard}. Not impossible, but a demanding approach.", "Impact speed was around {speed} knots according to the preliminary data.",
				"The {type} can fly perfectly well on one engine. An engine problem alone should not bring it down.",
				"Classic Swiss cheese model: weather, workload, maybe a technical issue - and all the holes lined up.",
				"The recorders will tell the real story. Everything else right now is speculation.", "Note the debris field. A compact one means a steep impact; a long one, a shallow slide.",
				"If they were configured for landing with the gear down, look at the final two minutes: energy, stability, configuration.",
				"{reg} was delivered in {year}. Not an old airframe by any measure.", "Preliminary findings: {cause_s} That fits the radar track.",
				"The flight path in the last minute is the key: look at the vertical speed as they got close to the ground."],
				["Wait for the preliminary report.", "Source: 20 years in maintenance.", "Happy to be corrected, but that's my reading.", ""])
		"pilot":
			return _join(r, f, [
				"Airline pilot here. Please wait for the report before blaming the crew.", "Every pilot I know is sick reading this. We train for exactly this and it still happens.",
				"People shouting 'pilot error' an hour after the event have never flown an approach at night in {wx_hard}.",
				"{pilot} had thousands of hours. Experience doesn't make anyone immune, but let's not judge from a news clip.",
				"The crew of {num} were somebody's colleagues and friends. Show some respect.", "Pilot error is almost never the full story. Why did the error happen? That's what investigations are for.",
				"Captain here, 18 years on the line. The system is built so one mistake doesn't kill you. Something else went wrong too.",
				"As a {short} pilot: the aircraft gives you a lot of warning. I want to know what they were dealing with in that cockpit."],
				["Fly safe, colleagues.", "Thoughts with everyone at {airline}.", ""])
		"misinfo":
			return _say(r, [
				"I heard the engine fell off before takeoff and they flew anyway.", "They're not telling us the real number of people on board.",
				"This was shot down, mark my words. Watch how fast they clean up the site.", "My cousin works at the airport and says the pilots were drunk.",
				"That plane was 40 years old!! They keep flying junk.", "Why is nobody talking about the lights people saw over {place} that night?",
				"Signal interference from the new towers. Look it up.", "{airline} already paid off the investigators.", "The real cause is being covered up to protect {maker}.",
				"They knew about the problem with {reg} for weeks."], f)
		"eyewitness":
			if bool(f.ditch):
				return _say(r, ["We watched from the beach. It came down flat on the water and stayed up. Boats were there in minutes.",
					"I saw the slides go out and people standing on the wings. Unreal.", "Fishing boats from the harbour went straight out. Real heroes."], f)
			return _say(r, ["I live a couple of kilometres from {place}. The whole house shook.", "I saw it come in really low over the trees, engines screaming. Then nothing.",
				"We heard sirens for hours. The sky was orange.", "I was on the road when it happened. People stopped their cars and ran towards it to help.",
				"Drove past the site this morning. Police everywhere and the smell of fuel in the air.", "It was so low I could read the {airline} titles on the side.",
				"My kids saw it from the school playground. They haven't stopped asking questions."], f)
		"family":
			if f.fatal != "0":
				return _say(r, ["My uncle was on {num}. We're still waiting for news. Please pray for us.", "My best friend's mum was on this flight. She was coming home.",
					"We lost our neighbour. She was 74 and had just retired.", "My father worked for {airline} for 30 years. He's devastated.",
					"My cousin was a flight attendant on {num}. She loved her job more than anything.", "My sister was on her way to {to} for a job interview. She was 26."], f)
			return _say(r, ["My brother was on {num}. He's in hospital with a broken arm and he's alive. I can't stop crying.",
				"My parents were in row 14. They got out through the over-wing exit. Thank you to the crew.", "My daughter was on board. She called from the tarmac. Best phone call of my life."], f)
		"nervous":
			return _say(r, ["I'm flying {airline} next week. Should I be worried?", "This is exactly why I'm terrified of flying.",
				"I have a flight from {from} on Friday and I'm shaking reading this.", "Guess I'm taking the train from now on.", "Can someone explain how often this actually happens?"], f)
		"media":
			return _say(r, ["Can {outlet} stop showing the wreckage on loop? Families are watching.", "Why do journalists always interview the most hysterical person they can find?",
				"Good, sober reporting from {outlet}. Thank you.", "Love how the headline changed three times in an hour.",
				"Respect to the reporter for not naming victims before the families were told."], f)
		"question":
			if mood in ["incident", "weather"]:
				return _say(r, ["Does anyone know if the flight continued later?", "Will passengers get compensation for this?", "Is {to} airport back to normal now?",
					"How often does this happen? Asking for a nervous friend.", "Was anyone hurt?", "What happens to the aircraft now?"], f)
			if mood in ["business", "general"]:
				return _say(r, ["When do tickets go on sale?", "Which aircraft will they use?", "Is this daily or just weekends?", "Any idea on prices?", "Will it connect to anything at {to}?"], f)
			return _say(r, ["Does anyone know which runway they were using?", "Were there children on board?", "Why would they try to land in {wx_hard}?",
				"How long does an investigation like this usually take?", "Is the airport open again?", "Where can I donate to help the families?",
				"Does anyone know what happened to the crew?", "Is {airline} still flying the {short} today?"], f)
		"praise":
			return _join(r, f, ["{airline} crew were amazing on this flight. I was on it.", "The captain came out and explained everything. Class act.",
				"Calm voices on the PA the whole way down. Thank you.", "Hats off to {pilot} and the crew.", "That's what all the training is for."], ["Legends.", "Bravo.", ""])
		"relief":
			return _join(r, f, ["Glad everyone's safe.", "Textbook handling by the crew.", "Good on the crew for turning back.", "Better a delay than a disaster.",
				"Scary for the passengers, but it ended exactly how it should."], ["Well done.", "Good job.", ""])
		"joke":
			if mood in ["business", "general"]:
				return _say(r, ["Can't wait to be delayed on a brand new route.", "Finally I can be stuck at {to} instead of {from}.", "Free legroom not included.",
					"New route, same sandwiches.", "I'll believe it when I'm on it."], f)
			return _say(r, ["Bird: 0. Engine: 0. Pilots: 1.", "The bird wanted an upgrade to business.", "Free extra landing, nice.", "Most expensive way to get a goose dinner.",
				"Seatbelt sign: exists. Passengers: apparently not.", "Plot twist: the snack trolley was the real victim.", "Somebody tell the weather we have places to be.",
				"Another day, another {from} delay. Bring a book.", "I've had worse flights on {airline} and nothing even happened."], f)
		"complaint":
			if mood in ["business", "general"]:
				return _say(r, ["The last route they launched lasted four months.", "Great, more noise over my house.", "They should fix delays on existing routes first.",
					"Prices on this route are already ridiculous.", "Customer service at {airline} is still a nightmare, new route or not."], f)
			return _say(r, ["Was on this flight. They gave us a 10 crown voucher. Ten.", "Three hours on the apron with no air conditioning.", "Still waiting for my bag.",
				"Nobody told us anything for two hours. Communication was terrible.", "The rebooking queue at {to} was 300 people long.", "My connection is gone, my hotel is gone, my patience is gone."], f)
		"weather":
			return _join(r, f, ["Stuck at a {to} gate for three hours, but better late than inside a thunderstorm.", "Pilots don't fly into storms for fun. Be patient.",
				"Saw the lightning from the terminal. No thanks!", "Delays everywhere tonight.", "Respect to air traffic control tonight.",
				"The storm cell over {to} was massive on the radar."], ["Stay safe everyone.", "Wild night out there.", ""])
		"business":
			return _say(r, ["Finally a direct {from} to {to} flight!", "Prices will double within a year, watch.", "{airline} always launches routes and cancels them six months later.",
				"The {short} is perfect for that route.", "More flights, more noise over my house. Great.", "Booked already!", "Will there be a lounge?",
				"Good news for {from}. Tourism needs this."], f)
	return _say(r, ["Interesting.", "Didn't expect that.", "Good to know.", "Thanks for the update.", "Never a dull day in aviation."], f)


static func _reply_text(tone: String, r: RandomNumberGenerator, f: Dictionary, parent: Dictionary, k: int = -1) -> String:
	var t := _reply_pick(tone, r, f, k)
	return t


static func _reply_pick(tone: String, r: RandomNumberGenerator, f: Dictionary, k: int) -> String:
	match tone:
		"amen":
			return _say(r, ["Praying for them.", "So sad.", "Rest in peace.", "Heartbreaking.", "Thinking of them all.", "Words fail.", "Couldn't have said it better.", "Beautifully put."], f, k)
		"hug":
			return _say(r, ["Sending you all the strength in the world.", "I'm so sorry. Please update us when you can.", "Holding you and your family in my thoughts.",
				"I'm so, so sorry for your loss."], f, k)
		"agree_anger":
			return _say(r, ["100%. Ground the fleet until we know.", "Exactly. Follow the money.", "Same. Never flying them again.", "Say it louder."], f, k)
		"defend":
			return _say(r, ["{airline} has flown millions of passengers safely. Let the investigators work.", "You have no idea what caused this yet.",
				"Blaming before facts is how rumours start."], f, k)
		"wait":
			return _say(r, ["Wait for the preliminary report.", "Let's not speculate while families are still waiting for news."], f, k)
		"airline":
			return "We hear you. Our focus right now is the families and full cooperation with the investigation. We will share what we learn.".format(f)
		"tech_more":
			return _say(r, ["Good analysis. You can see the speed decay in the last minute of the track too.", "Agreed, and the timing of the configuration changes will be telling.",
				"Spot on. The {short} gives you plenty of warning, so the question is why it wasn't heeded or wasn't seen.", "Best comment in this thread."], f, k)
		"armchair":
			return _say(r, ["Ah yes, another armchair investigator.", "Did you get your type rating from YouTube?", "Let the professionals do their job."], f, k)
		"thanks_pilot":
			return _say(r, ["Thank you for saying this.", "Respect from a fellow pilot.", "This needs to be the top comment.", "Thank you for keeping us safe."], f, k)
		"pushback":
			return _say(r, ["Pilots always protect each other.", "If they made a mistake, they made a mistake.", "With respect, people died. Questions have to be asked."], f, k)
		"correction":
			return _say(r, ["Source? The preliminary data says nothing like that.", "{reg} was delivered in {year}. It is not 40 years old.",
				"This is false. Please stop spreading rumours while families are grieving.", "{outlet} confirmed {aboard} people on board. Stop it.",
				"There's a radar track. It flew normally until the final minutes.", "Your cousin should talk to the investigators then, not the internet.",
				"Reported. This is how misinformation spreads."], f, k)
		"double_down":
			return _say(r, ["That's exactly what they want you to believe.", "Do your own research.", "Watch, it'll all come out in a few years.", "Keep sleeping."], f, k)
		"ask_witness":
			return _say(r, ["Please contact the investigators. They're asking for any photos or video.", "Did you see any fire before it went down?", "Are you okay? That must have been terrifying."], f, k)
		"investigators":
			return "The Transport Safety Board has a witness line. Please call them."
		"reassure":
			return _say(r, ["Statistically you're far safer in the air than on the drive to the airport.", "Flying is still the safest way to travel, and every accident makes it safer.",
				"Talk to the crew when you board. They'll put you at ease.", "I fly over 100 times a year. You'll be fine."], f, k)
		"nervous_too":
			return _say(r, ["Same. I'm flying next month and I'm dreading it.", "You're not alone."], f, k)
		"answer":
			return _say(r, ["Usually 12 to 18 months for a final report, with a preliminary one in about a month.", "The airport reopened this morning, with delays.",
				"There's a fund set up by the city. Link in the article.", "{airline} has a family assistance line open around the clock.",
				"From the arrival recordings it sounds like they were cleared to land normally."], f, k)
		"dont_know":
			return _say(r, ["No idea, waiting like everyone else.", "Nothing official yet."], f, k)
		"agree":
			return _say(r, ["This.", "Exactly.", "Well said.", "Agreed.", "100%.", "Underrated comment."], f, k)
		"defend_media":
			return _say(r, ["They're reporting the news. That's literally their job.", "This coverage has been pretty respectful, honestly."], f, k)
		"praise_crew":
			return _say(r, ["The crew deserve medals.", "Training saves lives.", "{pilot} is a legend."], f, k)
		"lol":
			return _say(r, ["Haha", "lmao", "I needed that today.", "Comment of the day.", "Stop, I'm crying"], f, k)
		"too_soon":
			return _say(r, ["Bit soon for jokes, no?", "Read the room."], f, k)
		"complaint_reply":
			return _say(r, ["Claim compensation, you're entitled to it.", "Same thing happened to me last year.", "At least you're safe."], f, k)
	return _say(r, ["Interesting.", "Good point."], f, k)


## Short count label: 1.2K.
static func short(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (float(n) / 1000000.0)
	if n >= 10000:
		return "%dK" % (n / 1000)
	if n >= 1000:
		return "%.1fK" % (float(n) / 1000.0)
	return str(n)


## Views on a video: grows with the story's comments and age.
static func views(art: Dictionary) -> int:
	var ctx := context(art)
	var r := U.rng(int(ctx.seed) + 5)
	return int(float(count(art)) * r.randf_range(140.0, 420.0) + r.randf_range(200.0, 900.0))


## Replies other people leave on the player's own comment: a handful straight away and more
## as the story's clock moves on, answering what the player actually said.
static func player_replies(art: Dictionary, pc: Dictionary) -> Array:
	var ctx := context(art)
	var f: Dictionary = ctx.f
	var text := String(pc.get("text", ""))
	var kind := CommentBank.classify(text)
	var seed_v := U.hash_str(text + str(pc.get("t", 0.0)))
	var r := U.rng(seed_v)
	var total := 3 + r.randi() % 9
	var out := []
	var pool: Array = CommentBank.TO_PLAYER.get(kind, CommentBank.TO_PLAYER.other)
	for j in total:
		var delay := 20.0 + pow(float(j), 1.8) * 240.0
		var t := float(pc.get("t", WorldSim.clock)) + delay
		if j >= 3 and t > WorldSim.clock:
			continue
		var rr := U.rng(seed_v + j * 31)
		var tone := "agree" if kind != "question" else "answer"
		var line := _say(rr, pool, f, seed_v + j)
		if rr.randf() < 0.3:
			line = _reply_text(["agree", "amen", "lol", "reassure", "answer", "correction"][["other", "grief", "joke", "fear", "question", "blame"].find(kind) if kind in ["other", "grief", "joke", "fear", "question", "blame"] else 0], rr, f, {"i": j, "tone": tone}, seed_v + j)
		out.append({"i": j, "tone": tone, "author": _author(rr, tone, ctx), "text": "@%s %s" % [String(pc.get("name", "you")).replace(" ", ""), line],
			"likes": int(pow(rr.randf(), 2.0) * 40.0), "t": minf(t, WorldSim.clock), "replies": 0, "edited": false, "pinned": false, "depth": 1})
	return out
