class_name NewsScript
extends RefCounted
## Writes the rundown of a video: which sets and shots it cuts between, what the anchors,
## reporters, witnesses and investigators say (generated from the incident and article data),
## the lower thirds, the headline strap and the ticker. The result is a plain dictionary - a
## "program" - that the BroadcastPlayer plays, seeks and speaks. Same input, same program.

const WPS := 2.55          # narration pace (words per second) used to time captions and speech
const PAUSE := 0.4

var prog := {}
var segs: Array = []
var lines: Array = []
var thirds: Array = []
var cues: Array = []
var t := 0.0
var r := RandomNumberGenerator.new()
var ctx := {}
var outlet := "skyline"
var _cur := {}
var _cursor := 0.0


# ================================================================== entry points
## Program for a video dictionary as stored on articles, posts and in the library.
static func build(video: Dictionary, article: Dictionary = {}) -> Dictionary:
	var b := NewsScript.new()
	return b._build(video, article)


## Investigation report video straight from a flight result (the debrief, before the world
## has published anything about it).
static func for_result(res: Dictionary) -> Dictionary:
	var inc := NewsScript.incident_from_result(res)
	var b := NewsScript.new()
	if String(res.get("outcome", "")) in ["crashed", "ditched"]:
		return b._inv_report(inc, true)
	return b._replay({"samples": res.get("recorder", {}).get("samples", []), "type": res.get("type", "s320"), "airline": res.get("airline", "SKF"),
		"callsign": res.get("callsign", ""), "dep": res.get("dep", ""), "arr": res.get("arr", ""), "clock": res.get("clock", WorldSim.clock),
		"outcome": res.get("outcome", "landed"), "reg": res.get("reg", ""), "weather": res.get("weather", {}), "cvr": res.get("recorder", {}).get("cvr", [])})


## An accident record (the same shape News stores) built from a finished flight's result.
static func incident_from_result(res: Dictionary) -> Dictionary:
	var al := Airlines.get_al(String(res.get("airline", "")))
	var af: Dictionary = res.get("aftermath", {})
	var inv: Dictionary = res.get("investigation", {})
	var crash: Dictionary = res.get("crash", {})
	var rec: Dictionary = res.get("recorder", {})
	var samples: Array = rec.get("samples", [])
	var c: Dictionary = af.get("counts", {})
	var num := String(res.get("callsign", "")).split(" ")[-1] if String(res.get("callsign", "")) != "" else ""
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	var t_end := float(samples[samples.size() - 1][0]) if not samples.is_empty() else 0.0
	var cvr := []
	for v in rec.get("cvr", []):
		if float(v.get("t", 0.0)) > t_end - 240.0:
			cvr.append({"t": float(v.get("t", 0.0)) - t_end, "who": String(v.get("who", "")), "text": String(v.get("text", ""))})
	var marks := []
	for m in rec.get("events", []):
		if float(m.get("t", 0.0)) > t_end - 240.0:
			marks.append({"t": float(m.get("t", 0.0)) - t_end, "kind": String(m.get("kind", "")), "text": String(m.get("text", ""))})
	return {"id": "R" + String(res.get("flight_id", "")), "clock": float(res.get("clock", WorldSim.clock)), "num": "%s%s" % [al.get("iata", ""), num],
		"title": "%s %s%s %s" % [al.get("name", ""), al.get("iata", ""), num, "ditching" if String(res.get("outcome", "")) == "ditched" else "accident"],
		"airline": String(res.get("airline", "")), "type": String(res.get("type", "s320")), "reg": String(res.get("reg", "")),
		"dep": String(res.get("dep", "")), "arr": String(res.get("planned_arr", res.get("arr", ""))), "place": String(af.get("place", crash.get("place", ""))),
		"counts": c, "cause": String(inv.get("probable_cause", "")), "pilot": String(res.get("captain", "the captain")), "fire": bool(af.get("fire", crash.get("fire", false))),
		"ditching": String(res.get("outcome", "")) == "ditched", "victims": af.get("victims", []), "x": float(crash.get("x", 0.0)), "z": float(crash.get("z", 0.0)),
		"heading": float(crash.get("heading", 0.0)), "weather": res.get("weather", {}), "samples": samples.slice(maxi(samples.size() - 480, 0)),
		"summary": "%d of %d aboard killed" % [fatal, aboard] if fatal > 0 else "all %d aboard survived" % aboard,
		"findings": inv.get("findings", []), "factors": inv.get("factors", []), "recommendations": inv.get("recommendations", []),
		"shares": inv.get("shares", {}), "timeline": inv.get("timeline", []), "pilot_share": float(inv.get("pilot_share", 0.0)),
		"report_days": int(inv.get("report_days", 120)), "cvr": cvr, "marks": marks, "phase": String(res.get("phase", "")),
		"crash": {"speed_kt": float(crash.get("speed_kt", 0.0)), "vs_fpm": float(crash.get("vs_fpm", 0.0)), "pitch": float(crash.get("pitch", 0.0)),
			"bank": float(crash.get("bank", 0.0)), "surface": String(crash.get("surface", "")), "severity": float(crash.get("severity", af.get("severity", 0.6))),
			"gear_down": bool(crash.get("gear_down", true)), "breakup": String(crash.get("breakup", "")), "engines_running": int(crash.get("engines_running", 2))},
		"severity": float(af.get("severity", crash.get("severity", 0.6))), "mode": String(res.get("mode", "pilot"))}


# ================================================================== dispatch
func _build(video: Dictionary, art: Dictionary) -> Dictionary:
	var vt := String(video.get("type", ""))
	r.seed = U.hash_str(str(video) + String(art.get("id", "")))
	if art.has("outlet"):
		outlet = String(art.outlet)
	match vt:
		"replay":
			return _replay(News.replay(String(video.get("replay", ""))) if video.has("replay") else video)
		"phone":
			var inc0 := News.incident(String(video.get("incident", "")))
			return _phone_clip(inc0, video) if not inc0.is_empty() else {}
		"investigation":
			var inc1 := News.incident(String(video.get("incident", "")))
			return _inv_report(inc1, false) if not inc1.is_empty() else {}
		"report":
			return _benign(video, art)
	# accident coverage ("reconstruction" from older saves, or a package)
	var inc := News.incident(String(video.get("incident", "")))
	if inc.is_empty():
		return {}
	var pkg := String(video.get("pkg", ""))
	if pkg == "":
		pkg = _pkg_for_article(art, String(video.get("angle", "")))
	if pkg == "final":
		return _inv_report(inc, false)
	return _accident(inc, art, pkg)


static func _pkg_for_article(art: Dictionary, angle: String) -> String:
	var tags: Array = art.get("tags", [])
	var kind := String(art.get("kind", ""))
	if "final report" in tags:
		return "final"
	if "investigation" in tags or angle == "analysis":
		return "prelim"
	if "survivors" in tags or angle == "witness":
		return "survivors"
	if "victims" in tags:
		return "victims"
	if "memorial" in tags:
		return "memorial"
	if "anniversary" in tags:
		return "anniversary"
	if "hero" in tags or "pilot" in tags or "court" in tags:
		return "pilot"
	if kind == "breaking" or art.is_empty():
		return "breaking"
	return "confirmed"


# ================================================================== building blocks
func _begin(kind: String, title: String) -> void:
	prog = {"kind": kind, "outlet": outlet, "title": title, "segments": segs, "lines": lines, "thirds": thirds, "cues": cues,
		"ticker": [], "headline": "", "sub": "", "tag": "", "air_clock": WorldSim.clock, "world": {}}


func _dur(text: String) -> float:
	var words := text.split(" ", false).size()
	return maxf(1.6, float(words) / WPS + 0.25)


func _seg(kind: String, stage: String, min_dur: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"kind": kind, "stage": stage, "t0": t, "t1": t + min_dur, "shots": [], "label": "", "live": false, "amb": "", "music": ""}
	s.merge(extra, true)
	segs.append(s)
	_cur = s
	_cursor = t + float(extra.get("lead", 0.6))
	return s


func _line(who: String, name: String, text: String, opts: Dictionary = {}) -> Dictionary:
	var d := float(opts.get("dur", _dur(text)))
	var l := {"t0": _cursor, "t1": _cursor + d, "who": who, "name": name, "text": text, "speak": bool(opts.get("speak", true)),
		"style": String(opts.get("style", "narr")), "voice": String(opts.get("voice", who))}
	lines.append(l)
	_cursor += d + float(opts.get("gap", PAUSE))
	return l


func _hold(seconds: float) -> void:
	_cursor += seconds


func _end(tail: float = 0.7) -> Dictionary:
	_cur.t1 = maxf(float(_cur.t1), _cursor - PAUSE + tail)
	t = float(_cur.t1)
	return _cur


## Cuts within the current segment at fractions of its length: [[cam, frac_start, extra], ...].
func _shots(seg: Dictionary, list: Array) -> void:
	var d := float(seg.t1) - float(seg.t0)
	var out := []
	for s in list:
		var sh := {"cam": String(s[0]), "t": float(s[1]) * d}
		if s.size() > 2:
			sh.merge(s[2], true)
		out.append(sh)
	seg.shots = out


func _third(kind: String, a: String, b: String, t0: float, t1: float, tag: String = "") -> void:
	thirds.append({"kind": kind, "a": a, "b": b, "t0": t0, "t1": t1, "tag": tag})


func _cue(at: float, sfx: String, vol_db: float = 0.0) -> void:
	cues.append({"t": at, "sfx": sfx, "db": vol_db})


func _pick(arr: Array) -> String:
	return String(arr[r.randi() % arr.size()])


func _finish(duration_pad: float = 0.0) -> Dictionary:
	prog.duration = t + duration_pad
	var ch := []
	var last := ""
	for s in segs:
		var lab := _chapter_name(s)
		if lab != last:
			ch.append({"t": float(s.t0), "label": lab})
			last = lab
	prog.chapters = ch
	return prog


static func _chapter_name(s: Dictionary) -> String:
	match String(s.kind):
		"bumper", "studio", "outro":
			return "Studio"
		"recon":
			return "Reconstruction"
		"fdr":
			return "Flight data"
		"impact":
			return "Impact"
		"phone":
			return "Witness video"
		"aerial":
			return "Aerial"
		"standup":
			return "Reporter"
		"interview":
			return "Eyewitness"
		"presser":
			return "Press conference"
		"memorial":
			return "Memorial"
		"title", "cards", "findings", "cause", "factors", "recs", "remember":
			return "Report"
		"spotter", "arrival":
			return "Footage"
		"terminal":
			return "Terminal"
		"replay":
			return "Replay"
	return String(s.kind).capitalize()


# ================================================================== context
func _context(inc: Dictionary) -> Dictionary:
	var al := Airlines.get_al(String(inc.get("airline", "SKF")))
	var tpl := AircraftTypes.get_type(String(inc.get("type", "s320")))
	var c: Dictionary = inc.get("counts", {})
	var fatal := int(c.get("fatal", 0))
	var aboard := int(c.get("aboard", 0))
	var clock := float(inc.get("clock", WorldSim.clock))
	var dt := U.clock_to_date(clock)
	var hour := float(dt.hours_f)
	var w: Dictionary = inc.get("weather", {})
	var samples: Array = inc.get("samples", [])
	var place := String(inc.get("place", ""))
	var crash: Dictionary = inc.get("crash", {})
	var last: Array = samples[samples.size() - 1] if not samples.is_empty() else []
	var impact_kt := float(crash.get("speed_kt", last[4] if last.size() > 4 else 0.0))
	var impact_fpm := absf(float(crash.get("vs_fpm", absf(float(last[5]) / U.FPM) if last.size() > 5 else 0.0)))
	var wx := "in good weather"
	var precip := String(w.get("precip", "none"))
	var wind := int(w.get("wind_kt", 0.0))
	if precip == "thunderstorm":
		wx = "with thunderstorms in the area"
	elif precip == "rain":
		wx = "in rain and low cloud"
	elif precip == "snow":
		wx = "in snow"
	elif float(w.get("vis", 10000.0)) < 1500.0:
		wx = "in thick fog"
	elif wind > 22:
		wx = "in strong, gusty winds"
	elif float(w.get("cover", 0.2)) > 0.8:
		wx = "under a low, grey overcast"
	var tod := "this morning"
	if hour >= 12.0 and hour < 17.5:
		tod = "this afternoon"
	elif hour >= 17.5 and hour < 21.0:
		tod = "this evening"
	elif hour >= 21.0 or hour < 5.0:
		tod = "tonight"
	var dep := Airports.get_ap(String(inc.get("dep", "")))
	var arr := Airports.get_ap(String(inc.get("arr", "")))
	var cause := String(inc.get("cause", "")).strip_edges().trim_suffix(".")
	return {"airline": String(al.get("name", "the airline")), "code": String(inc.get("airline", "")), "num": String(inc.get("num", "")),
		"type": "%s %s" % [tpl.maker, tpl.name], "type_name": String(tpl.name), "short": String(tpl.short), "maker": String(tpl.maker),
		"cat": String(tpl.category), "reg": String(inc.get("reg", "")), "from": String(dep.get("short", "")), "to": String(arr.get("short", "")),
		"to_icao": String(inc.get("arr", "")), "from_icao": String(inc.get("dep", "")),
		"place": place, "noun": News._place_noun(place), "fatal": fatal, "aboard": aboard, "survivors": maxi(aboard - fatal, 0),
		"critical": int(c.get("critical", 0)), "serious": int(c.get("serious", 0)), "minor": int(c.get("minor", 0)), "uninjured": int(c.get("uninjured", 0)),
		"injured": int(c.get("critical", 0)) + int(c.get("serious", 0)) + int(c.get("minor", 0)),
		"cause": cause, "ditching": bool(inc.get("ditching", false)), "fire": bool(inc.get("fire", false)), "hero": bool(inc.get("hero", false)),
		"criminal": bool(inc.get("criminal", false)), "died": bool(inc.get("player_died", false)), "pilot": String(inc.get("pilot", "the captain")),
		"ceo": String(al.get("ceo", "the chief executive")), "spokes": String(al.get("spokes", "a spokesperson")), "clock": clock,
		"hhmm": U.fmt_clock(clock), "date": U.fmt_date(clock), "weekday": String(U.DAY_NAMES[int(dt.weekday)]), "tod": tod,
		"night": hour >= 20.5 or hour < 5.5, "wx": wx, "wind": wind, "vis": int(w.get("vis", 10000.0)), "precip": precip,
		"impact_kt": int(impact_kt), "impact_fpm": int(impact_fpm), "impact_pitch": int(crash.get("pitch", last[6] if last.size() > 6 else 0.0)),
		"impact_bank": int(crash.get("bank", last[7] if last.size() > 7 else 0.0)), "severity": float(inc.get("severity", crash.get("severity", 0.6))),
		"license": String(inc.get("license", "")), "report_days": int(inc.get("report_days", 120)), "pilot_share": float(inc.get("pilot_share", 0.0))}


## Words for numbers in narration: "139", "all 72", "nobody".
static func _n(v: int) -> String:
	return U.fmt_int(v)


func _hello(hour_clock: float) -> String:
	var h := float(U.clock_to_date(hour_clock).hours_f)
	if h < 12.0:
		return "Good morning."
	if h < 18.0:
		return "Good afternoon."
	return "Good evening."


## A few facts about the final minutes taken from the flight recorder samples.
func _track_facts(samples: Array) -> Dictionary:
	if samples.size() < 4:
		return {}
	var last: Array = samples[samples.size() - 1]
	var t_end := float(last[0])
	var first: Array = samples[0]
	for s in samples:
		if float(s[0]) >= t_end - 90.0:
			first = s
			break
	var max_vs := 0.0
	var ap_off := -1.0
	var prev_ap := -1
	var steep_from := -1.0
	for s2 in samples:
		if float(s2[0]) < t_end - 120.0:
			continue
		max_vs = minf(max_vs, float(s2[5]))
		if prev_ap == 1 and int(s2[12]) == 0:
			ap_off = t_end - float(s2[0])
		prev_ap = int(s2[12])
		if steep_from < 0.0 and float(s2[5]) / U.FPM < -3000.0:
			steep_from = t_end - float(s2[0])
	return {"alt0": int(roundf(float(first[3]) / U.FT / 50.0) * 50.0), "ias0": int(first[4]), "max_vs": int(absf(max_vs / U.FPM)),
		"ap_off": int(ap_off), "steep": int(steep_from), "span": int(t_end - float(first[0])), "gear": int(last[11]), "flap": int(last[10])}


# ================================================================== accident coverage
func _world_spec(inc: Dictionary, air_clock: float) -> Dictionary:
	return {"mode": "incident", "incident": inc.get("id", ""), "x": float(inc.get("x", 0.0)), "z": float(inc.get("z", 0.0)),
		"heading": float(inc.get("heading", 0.0)), "type": String(inc.get("type", "s320")), "airline": String(inc.get("airline", "SKF")),
		"reg": String(inc.get("reg", "")), "samples": inc.get("samples", []), "ending": "ditch" if bool(inc.get("ditching", false)) else "crash",
		"clock": float(inc.get("clock", WorldSim.clock)), "air_clock": air_clock, "weather": inc.get("weather", {}),
		"fire": bool(inc.get("fire", true)), "severity": float(inc.get("severity", inc.get("crash", {}).get("severity", 0.7))),
		"fatal": int(inc.get("counts", {}).get("fatal", 0)), "aboard": int(inc.get("counts", {}).get("aboard", 0)), "seed": U.hash_str(String(inc.get("id", "")))}


func _accident(inc: Dictionary, art: Dictionary, pkg: String) -> Dictionary:
	ctx = _context(inc)
	var air := float(art.get("t", float(inc.get("clock", WorldSim.clock)) + 3600.0))
	if not art.has("outlet"):
		outlet = "skyline" if pkg in ["breaking", "survivors", "pilot"] else ("aeroweek" if pkg in ["prelim"] else ("gazette" if pkg in ["memorial", "anniversary"] else "herald"))
	_begin("accident_" + pkg, String(art.get("headline", inc.get("title", "Accident"))))
	prog.air_clock = air
	prog.world = _world_spec(inc, air)
	prog.incident = String(inc.get("id", ""))
	var c := ctx
	var noun := String(c.noun) if String(c.noun) != "" else String(c.to)
	var hours_after := (air - float(c.clock)) / 3600.0
	var days_after := int(hours_after / 24.0)
	prog.tag = {"breaking": "BREAKING NEWS", "confirmed": "DEVELOPING STORY", "victims": "REMEMBERED", "survivors": "SURVIVORS SPEAK",
		"prelim": "INVESTIGATION", "pilot": "THE PILOT", "memorial": "MEMORIAL", "anniversary": "ONE YEAR ON"}.get(pkg, "LATEST")
	var verb := "DITCHES" if bool(c.ditching) else "CRASHES"
	prog.headline = {"breaking": "%s JET %s %s" % [String(c.airline).to_upper(), verb, ("NEAR " + noun.to_upper()) if noun != "" else ""],
		"confirmed": ("%d KILLED IN %s CRASH" % [c.fatal, noun.to_upper()]) if int(c.fatal) > 0 else ("ALL %d SURVIVE %s" % [c.aboard, "DITCHING" if c.ditching else "CRASH"]),
		"victims": "THE VICTIMS OF FLIGHT %s" % c.num, "survivors": "\"I THOUGHT I WAS GOING TO DIE\"",
		"prelim": "PRELIMINARY REPORT: FLIGHT %s" % c.num, "pilot": "THE PILOT OF FLIGHT %s" % c.num,
		"memorial": "%s REMEMBERS" % noun.to_upper(), "anniversary": "ONE YEAR SINCE FLIGHT %s" % c.num}.get(pkg, "FLIGHT %s" % c.num)
	prog.sub = "%s %s · %s → %s · %s ON BOARD" % [String(c.airline).to_upper(), c.short, String(c.from).to_upper(), String(c.to).to_upper(), _n(int(c.aboard))]
	prog.ticker = _accident_ticker(c, pkg, days_after)
	var anchor := NewsStyle.anchor(outlet, U.hash_str(String(inc.get("id", ""))) % 2)
	var rep := NewsStyle.reporter(outlet, U.hash_str(String(inc.get("id", "")) + pkg))
	var a_name := String(anchor[0])
	var r_name := String(rep[0])
	var st := NewsStyle.get_style(outlet)
	var samples: Array = inc.get("samples", [])
	var has_track := samples.size() >= 8
	var tf := _track_facts(samples)
	var site_phase := "response" if hours_after < 6.0 else ("aftermath" if hours_after < 72.0 else "investigation")
	# ---------------------------------------------------------------- open
	if pkg == "breaking":
		var b := _seg("bumper", "studio", 3.8, {"graphic": "bumper", "music": "sting", "lead": 3.8})
		_shots(b, [["wide", 0.0]])
		_cue(0.05, "whoosh")
		_end(0.0)
	var s1 := _seg("studio", "studio", 6.0, {"music": "bed", "graphic": "story"})
	var open_lines := []
	match pkg:
		"breaking":
			open_lines.append("%s We begin with breaking news." % _hello(air))
			if bool(c.ditching):
				open_lines.append("A %s passenger jet with %s people on board has come down in the water %s." % [c.airline, _n(int(c.aboard)), c.place])
			else:
				open_lines.append("A %s %s with %s people on board has crashed %s." % [c.airline, c.short, _n(int(c.aboard)), c.place])
			open_lines.append("Flight %s was flying from %s to %s. It went down %s, at %s local time, %s." % [c.num, c.from, c.to, c.tod, c.hhmm, c.wx])
			open_lines.append(_pick(["Emergency services are at the scene. There is no official word yet on casualties.",
				"Fire crews and ambulances are at the scene, and the number of casualties is not yet known.",
				"Rescue teams are still at the site and we do not yet know how many people have been hurt."]))
		"confirmed":
			open_lines.append(_hello(air))
			if int(c.fatal) > 0:
				open_lines.append("%s has confirmed that %s people died when flight %s crashed %s %s." % [c.airline, _n(int(c.fatal)), c.num, c.place, "yesterday" if hours_after > 14.0 else c.tod])
				open_lines.append("%s people survived. %s of them are in hospital, %s in a critical condition." % [_n(int(c.survivors)), _n(int(c.injured)), _n(int(c.critical))])
			else:
				open_lines.append("It is being called a miracle: all %s people on board flight %s survived when the %s %s %s." % [_n(int(c.aboard)), c.num, c.short, "ditched" if c.ditching else "crashed", c.place])
				open_lines.append("%s people are being treated in hospital." % _n(int(c.injured)))
			open_lines.append("The Calderra Transport Safety Board has opened an investigation, and both flight recorders have been recovered.")
		"victims":
			open_lines.append("Tonight, the families of the %s people who died on flight %s are sharing the stories of the people they lost." % [_n(int(c.fatal)), c.num])
			var vic: Array = inc.get("victims", [])
			if not vic.is_empty():
				var v0: Dictionary = vic[0]
				open_lines.append("Among them, %s, %d, from %s. Friends describe a %s who lived for the people around them." % [v0.get("name", ""), int(v0.get("age", 30)), v0.get("home", ""), String(v0.get("job", "person")) if String(v0.get("job", "")) != "" else "person"])
		"survivors":
			open_lines.append("For the first time, survivors of the %s crash are speaking about the final moments of flight %s." % [noun, c.num])
			open_lines.append("%s of the %s people on board made it out. Their accounts paint a picture of chaos, and of extraordinary courage." % [_n(int(c.survivors)), _n(int(c.aboard))])
		"prelim":
			open_lines.append("Investigators have released their preliminary report into the loss of %s flight %s." % [c.airline, c.num])
			open_lines.append("And it points to one key finding: %s." % String(c.cause).to_lower() if String(c.cause) != "" else "The report sets out the final minutes of the flight in detail.")
		"pilot":
			if bool(c.died):
				open_lines.append("Colleagues are paying tribute to %s, the pilot at the controls of flight %s, who died in the crash." % [c.pilot, c.num])
			elif bool(c.hero):
				open_lines.append("The pilot who brought flight %s down %s is being called a hero." % [c.num, "on the water" if c.ditching else "and saved lives"])
			elif bool(c.criminal):
				open_lines.append("Prosecutors have opened a criminal case against the pilot of flight %s, %s." % [c.num, c.pilot])
			else:
				open_lines.append("The aviation regulator has acted against the pilot in command of flight %s." % c.num)
		"memorial", "anniversary":
			open_lines.append("%s %s, hundreds of people gathered near %s to remember the %s people who died on flight %s." % [_hello(air).trim_suffix("."), "and tonight" if pkg == "memorial" else "and a year on", noun, _n(int(c.fatal)), c.num])
	for tx in open_lines:
		_line("anchor", a_name, tx, {"voice": "anchor"})
	var lead_out := _pick(["Here's what we know about the final minutes of the flight.", "Let's look at what happened.", "This is how the flight unfolded."])
	if pkg in ["breaking", "confirmed", "survivors", "prelim"] and has_track:
		_line("anchor", a_name, lead_out, {"voice": "anchor"})
	var e1 := _end()
	_shots(e1, [["wide", 0.0], ["single_a", 0.34], ["wall", 0.78]] if pkg == "breaking" else [["two", 0.0], ["single_a", 0.4]])
	_third("name", a_name.to_upper(), String(st.show), e1.t0 + 1.2, minf(e1.t0 + 7.0, e1.t1))
	_third("strap", String(prog.headline), String(prog.sub), e1.t0 + 2.0, 1e9, String(prog.tag))
	# ---------------------------------------------------------------- the flight
	if has_track and pkg in ["breaking", "confirmed", "survivors"]:
		var rs := _seg("recon", "world", 10.0, {"label": "RECONSTRUCTION", "music": "tension", "amb": "wind", "site": "none"})
		var recon_lines := []
		var span := clampf(float(tf.get("span", 60)), 30.0, 90.0)
		if int(tf.get("steep", -1)) > 0:
			recon_lines.append("Flight data show the %s at about %s feet when, %d seconds before impact, it began to descend steeply." % [c.short, _n(int(tf.alt0)), int(tf.steep)])
		else:
			recon_lines.append("Flight data show the %s at about %s feet and %d knots in its final minute and a half." % [c.short, _n(int(tf.get("alt0", 2000))), int(tf.get("ias0", 200))])
		if int(tf.get("max_vs", 0)) > 2500:
			recon_lines.append("At its worst the aircraft was dropping at more than %s feet per minute." % _n(int(tf.max_vs) / 100 * 100))
		if int(tf.get("ap_off", -1)) > 0:
			recon_lines.append("The autopilot had been switched off %d seconds earlier." % int(tf.ap_off))
		recon_lines.append("It struck the %s at around %d knots." % ["water" if c.ditching else "ground", int(c.impact_kt)])
		for tx2 in recon_lines:
			_line("vo", a_name, tx2, {"voice": "anchor"})
		var e2 := _end(1.5)
		# the reconstruction plays the last part of the track in real time and ends on impact
		e2.recon = {"span": maxf(span, float(e2.t1) - float(e2.t0) - 4.0), "post": 4.0}
		_shots(e2, [["recon_aerial", 0.0], ["recon_side", 0.3], ["recon_chase", 0.58], ["recon_ground", 0.82]])
		_third("label", "RECONSTRUCTION", "BASED ON FLIGHT TRACKING DATA", e2.t0 + 0.5, e2.t1 - 0.5)
	# ---------------------------------------------------------------- witness video
	if has_track and pkg in ["breaking", "survivors"] and not bool(c.night):
		var wit := WorldSim.person(r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1))
		var handle := Names.handle(r, wit)
		var ph := _seg("phone", "world", 9.0, {"label": "VIEWER VIDEO", "amb": "outdoor", "site": "impact", "handle": handle, "phone_seed": r.randi()})
		_line("vo", a_name, _pick(["This video, filmed by a witness near %s, shows the final seconds of the flight." % noun,
			"A warning: some viewers may find these pictures distressing. This was filmed by a witness near %s." % noun]), {"voice": "anchor"})
		_line("witness", "Witness", _pick(["Oh my God... it's so low.", "Is that plane okay? It's way too low.", "Look at that plane - look!"]), {"speak": false, "style": "nat"})
		_line("witness", "Witness", _pick(["No, no, no, no...", "Oh my God! Oh my God!", "It's going down - it's going down!"]), {"speak": false, "style": "nat"})
		_hold(1.5)
		_line("witness", "Witness", _pick(["Call emergency! Somebody call emergency!", "Oh my God, there's fire... there's fire everywhere.", "Everyone's running toward it..."]), {"speak": false, "style": "nat"})
		var e3 := _end(0.8)
		e3.recon = {"span": 9.0, "post": maxf(float(e3.t1) - float(e3.t0) - 9.0, 3.0)}
		_shots(e3, [["phone", 0.0]])
		_third("credit", "VIEWER VIDEO", "Credit: %s" % handle, e3.t0 + 0.6, e3.t1 - 0.4)
		_cue(e3.t0 + 9.0, "impact", -4.0)
	# ---------------------------------------------------------------- aerial
	if pkg in ["breaking", "confirmed", "survivors", "prelim"]:
		var live := pkg == "breaking"
		var ae := _seg("aerial", "world", 12.0, {"label": String(st.chopper), "live": live, "amb": "heli", "site": site_phase if not live else "response", "air": air})
		var al_lines := []
		if live:
			al_lines.append(_pick(["We're over the crash site now.", "These are live pictures from %s." % String(st.chopper).to_lower().capitalize(), "You're looking at live pictures from above the crash site."]))
			if bool(c.ditching):
				al_lines.append("The aircraft is still floating, and you can see boats alongside it and people standing on the wings.")
			elif bool(c.fire):
				al_lines.append("Wreckage is spread over a wide area, and several fires are still burning. Fire crews are pouring foam onto what is left of the fuselage.")
			else:
				al_lines.append("The aircraft has broken apart. You can see the tail section, largely intact, a few hundred metres from the main wreckage.")
			al_lines.append("We can count at least %d fire engines and a long line of ambulances. Police have closed every road into the area." % (4 + r.randi() % 6))
		else:
			al_lines.append(_pick(["This is the scene from the air %s." % ("today" if hours_after < 30.0 else "this week"), "From above, the scale of the accident becomes clear."]))
			if site_phase == "investigation":
				al_lines.append("Investigators in white suits are working through the debris field, marking and photographing every piece of wreckage.")
			else:
				al_lines.append("The fires are out, but smoke still drifts over the wreckage, and the cordon remains in place.")
		for tx3 in al_lines:
			_line("reporter" if live else "vo", r_name if live else a_name, tx3, {"voice": "reporter" if live else "anchor"})
		var e4 := _end(1.0)
		_shots(e4, [["heli_wide", 0.0], ["heli_close", 0.45], ["heli_orbit", 0.75]])
		_third("place", ("LIVE · " if live else "") + String(c.place).to_upper(), String(st.chopper), e4.t0 + 0.6, e4.t1 - 0.3, "LIVE" if live else "")
	# ---------------------------------------------------------------- reporter at the scene
	if pkg in ["breaking", "confirmed", "victims", "survivors", "pilot"]:
		var at_site := pkg in ["breaking", "confirmed"]
		var su := _seg("standup", "world", 10.0, {"amb": "sirens" if at_site and hours_after < 8.0 else "outdoor", "site": site_phase, "where": "site" if at_site else "terminal", "air": air})
		var sl := []
		if at_site:
			sl.append(_pick(["This is as close as police will let us get.", "I'm at the edge of the police cordon.", "We're about a kilometre from the crash site."]))
			sl.append(_pick(["Behind me you can see the emergency lights of the crews that have been working here all %s." % ("night" if bool(c.night) else "day"),
				"The smell of burning fuel still hangs in the air, and the sirens have not stopped since the crash.",
				"Ambulances have been leaving in a steady stream, taking the injured to hospitals in %s." % c.to]))
			sl.append("%s says it has opened a family assistance line, and relatives are being taken to a reception centre at %s airport." % [c.airline, c.to])
		else:
			sl.append(_pick(["Here at %s airport, the departures board carries on as normal." % c.to, "At %s airport, a quiet corner of the terminal has been set aside for families." % c.to]))
			sl.append(_pick(["But for the families who waited here for flight %s, nothing will be normal again." % c.num,
				"Some have been here since the flight was due to land, waiting for news.", "Counsellors and airline staff have been with them through the night."]))
		sl.append("%s, %s News, %s." % [r_name, String(st.name).split(" ")[0], noun if at_site else c.to])
		for tx4 in sl:
			_line("reporter", r_name, tx4, {"voice": "reporter"})
		var e5 := _end(0.8)
		_shots(e5, [["standup", 0.0], ["standup_wide", 0.62]])
		_third("name", r_name.to_upper(), "%s · %s" % [String(st.name).to_upper(), (noun if at_site else c.to).to_upper()], e5.t0 + 0.8, minf(e5.t0 + 7.5, e5.t1))
	# ---------------------------------------------------------------- eyewitness / survivor interview
	if pkg in ["breaking", "survivors", "victims"]:
		var who := WorldSim.person(r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1))
		var role := "Eyewitness" if pkg == "breaking" else ("Survivor" if pkg == "survivors" else "Friend of a victim")
		var iv := _seg("interview", "world", 8.0, {"amb": "outdoor", "site": site_phase, "person": who.get("id", 0), "where": "site" if pkg == "breaking" else "terminal", "air": air})
		var q := []
		match pkg:
			"breaking":
				q.append(_pick(["I was in my garden when I heard the engines. It was so loud, much louder than normal.", "I was driving home and I saw it come over the trees, really low, way too low.",
					"I heard this roar and I looked up and it was already turning, like it was falling sideways."]))
				q.append(_pick(["Then there was a bang, and the whole sky behind the trees went orange.", "And then it just disappeared behind the hill, and there was this enormous bang.",
					"I've never heard anything like it. The ground shook."]))
			"survivors":
				q.append(_pick(["There was a bang and then everything went sideways. I just remember the smell of fuel.", "The crew were shouting heads down, stay down. I owe them my life.",
					"I unbuckled and the smoke was already at the ceiling. A man pulled me toward the exit."]))
				q.append(_pick(["I keep thinking about the people who didn't make it.", "When I got outside I just sat in the field and shook.", "I don't think I'll ever fly again."]))
			_:
				q.append(_pick(["She was on her way home. She'd texted me from the gate - just see you soon.", "He was the kindest person I knew. He'd do anything for anyone.",
					"We'd been friends since school. I still can't believe I'm talking about her in the past tense."]))
		for tx5 in q:
			_line("interview", String(who.get("name", "")), tx5, {"voice": "witness", "style": "sot"})
		var e6 := _end(0.6)
		_shots(e6, [["interview", 0.0]])
		_third("name", String(who.get("name", "")).to_upper(), role.to_upper(), e6.t0 + 0.5, e6.t1 - 0.3)
	# ---------------------------------------------------------------- the investigation (prelim) / statement
	if pkg in ["confirmed", "prelim"]:
		var speaker: Array = NewsStyle.BOARD_CHAIR if pkg == "prelim" else [String(c.ceo), "x", "Chief executive, %s" % c.airline]
		var pr := _seg("presser", "press", 10.0, {"amb": "room", "speaker": speaker, "board": pkg == "prelim", "airline": c.code})
		var pl := []
		if pkg == "prelim":
			pl.append("Our preliminary analysis of the flight data recorder and the cockpit voice recorder is complete.")
			if String(c.cause) != "":
				pl.append("At this stage, the evidence indicates that %s." % String(c.cause).to_lower())
			pl.append("The final report will follow in about %d months. Our thoughts remain with everyone affected." % maxi(int(c.report_days) / 30, 2))
		else:
			pl.append("Our hearts are with the families and friends of everyone on board flight %s." % c.num)
			pl.append("We are cooperating fully with the Transport Safety Board, and we will not speculate about the cause.")
			pl.append("Our family assistance team is with the relatives now, and will be for as long as they need us.")
		for tx6 in pl:
			_line("official", String(speaker[0]), tx6, {"voice": "official", "style": "sot"})
		var e7 := _end(0.8)
		_shots(e7, [["presser_wide", 0.0], ["presser_close", 0.22], ["presser_press", 0.7], ["presser_close", 0.82]])
		_third("name", String(speaker[0]).to_upper(), String(speaker[2]).to_upper(), e7.t0 + 0.8, minf(e7.t0 + 7.0, e7.t1))
		_cue(e7.t0 + 0.2, "shutter", -8.0)
	# ---------------------------------------------------------------- investigation animation (prelim)
	if pkg == "prelim" and has_track:
		var fd := _seg("fdr", "world", 14.0, {"label": "INVESTIGATION ANIMATION", "amb": "", "music": "tension", "fdr": true, "site": "none"})
		var an: Array = NewsStyle.get_style(outlet).analyst
		_line("analyst", String(an[0]), "The animation released with the report shows the final %d seconds of the flight." % int(clampf(float(tf.get("span", 60)), 30.0, 90.0)), {"voice": "analyst"})
		var fnd: Array = inc.get("findings", [])
		for f in fnd.slice(0, 2):
			_line("analyst", String(an[0]), String(f), {"voice": "analyst"})
		var e8 := _end(1.5)
		e8.recon = {"span": maxf(float(e8.t1) - float(e8.t0) - 3.0, 20.0), "post": 3.0}
		_shots(e8, [["analysis", 0.0], ["recon_chase", 0.4], ["analysis", 0.7]])
		_third("label", "INVESTIGATION ANIMATION", "SOURCE: CTSB PRELIMINARY REPORT", e8.t0 + 0.5, e8.t1 - 0.5)
	# ---------------------------------------------------------------- memorial
	if pkg in ["victims", "memorial", "anniversary"] or (pkg == "pilot" and bool(c.died)):
		var me := _seg("memorial", "memorial", 10.0, {"amb": "candles", "music": "somber", "night": true})
		var ml := []
		if pkg == "anniversary":
			ml.append("A year on, the candles are lit again at the edge of the field where flight %s came down." % c.num)
			ml.append("Survivors stood alongside the families of the %s people who did not come home." % _n(int(c.fatal)))
		else:
			ml.append(_pick(["Flowers, candles and photographs now line the road near the crash site.", "All day, people have come to leave flowers and light candles."]))
			ml.append(_pick(["Many of those who came did not know the victims. They just wanted to be here.", "Some stood in silence. Others held each other and wept."]))
		for tx7 in ml:
			_line("vo", a_name, tx7, {"voice": "anchor"})
		var e9 := _end(1.6)
		_shots(e9, [["memorial_candles", 0.0], ["memorial_wide", 0.38], ["memorial_mourners", 0.7]])
		_third("place", "%s · MEMORIAL" % noun.to_upper(), "FLIGHT %s · %s" % [c.num, U.fmt_date(air).to_upper()], e9.t0 + 0.8, e9.t1 - 0.5)
	# ---------------------------------------------------------------- outro
	var ou := _seg("outro", "studio", 5.0, {"music": "bed_out", "graphic": "story"})
	var outro := {"breaking": "We'll bring you more on this story as soon as we have it. %s has opened a family assistance line." % c.airline,
		"confirmed": "The investigation is expected to take months. We'll stay with this story.",
		"victims": "Our thoughts are with all of the families tonight.", "survivors": "Remarkable stories of survival.",
		"prelim": "The full report is due in %d months. You can read the preliminary findings on our website." % maxi(int(c.report_days) / 30, 2),
		"pilot": "We'll follow that story as it develops.", "memorial": "Gone, but not forgotten.", "anniversary": "Never forgotten."}.get(pkg, "More as we get it.")
	_line("anchor", a_name, outro, {"voice": "anchor"})
	var e10 := _end(1.2)
	_shots(e10, [["single_a", 0.0], ["wide_out", 0.55]])
	_cue(e10.t1 - 2.4, "outro", -6.0)
	return _finish()


func _accident_ticker(c: Dictionary, pkg: String, days_after: int) -> Array:
	var tk := []
	tk.append("%s FLIGHT %s %s %s" % [String(c.airline).to_upper(), c.num, "DITCHED" if c.ditching else "CRASHED", String(c.place).to_upper()])
	if pkg != "breaking":
		tk.append("%s ON BOARD · %s KILLED · %s SURVIVORS" % [_n(int(c.aboard)), _n(int(c.fatal)), _n(int(c.survivors))])
	tk.append("FAMILY ASSISTANCE LINE OPEN · %s" % String(c.airline).to_upper())
	tk.append("CTSB INVESTIGATORS ON SITE · FLIGHT RECORDERS %s" % ("RECOVERED" if pkg != "breaking" else "BEING SEARCHED FOR"))
	tk.append("%s %s FLEET: OPERATOR SAYS AIRCRAFT WAS FULLY MAINTAINED" % [String(c.airline).to_upper(), c.short])
	tk.append("ROADS AROUND %s CLOSED · AVOID THE AREA" % String(c.noun).to_upper())
	tk.append("WEATHER: %s" % String(c.wx).to_upper())
	if days_after > 1:
		tk.append("MEMORIAL SERVICE PLANNED FOR THE VICTIMS OF FLIGHT %s" % c.num)
	tk.append("MARKETS: AIRLINE SHARES FALL AFTER %s CRASH" % String(c.noun).to_upper())
	return tk


# ================================================================== official investigation report video
func _inv_report(inc: Dictionary, from_debrief: bool) -> Dictionary:
	outlet = "ctsb"
	ctx = _context(inc)
	var c := ctx
	_begin("inv_report", "Investigation report · %s flight %s" % [c.airline, c.num])
	var air := float(c.clock) + float(c.report_days) * 86400.0 if not from_debrief else float(c.clock) + 3600.0
	prog.air_clock = air
	prog.world = _world_spec(inc, air)
	prog.incident = String(inc.get("id", ""))
	prog.headline = "AIRCRAFT ACCIDENT REPORT"
	prog.sub = "%s FLIGHT %s · %s %s %s" % [String(c.airline).to_upper(), c.num, c.short, String(c.reg).to_upper(), String(c.place).to_upper()]
	prog.tag = "PRELIMINARY" if from_debrief else "FINAL REPORT"
	prog.no_ticker = true
	prog.cvr = inc.get("cvr", [])
	prog.marks = inc.get("marks", [])
	var narr := "Narrator"
	var samples: Array = inc.get("samples", [])
	var tf := _track_facts(samples)
	# title card over the site
	var ti := _seg("title", "world", 7.0, {"site": "investigation", "music": "somber", "card": "title", "lead": 1.4})
	_line("narrator", narr, "Calderra Transport Safety Board. Aircraft accident report.", {"voice": "narrator"})
	_line("narrator", narr, "%s flight %s, %s, %s." % [c.airline, c.num, c.date, c.place], {"voice": "narrator"})
	var e1 := _end(0.8)
	_shots(e1, [["site_orbit", 0.0]])
	# history of the flight
	var ov := _seg("overview", "world", 8.0, {"site": "none", "card": "", "label": "INVESTIGATION ANIMATION", "path": true})
	_line("narrator", narr, "On %s %s, at %s local time, %s flight %s, a %s registered %s, was operating from %s to %s with %s people on board." % [
		c.weekday, c.date, c.hhmm, c.airline, c.num, c.type, c.reg, c.from, c.to, _n(int(c.aboard))], {"voice": "narrator"})
	_line("narrator", narr, "The flight took place %s. Wind was %d knots, visibility %s." % [c.wx, int(c.wind), ("%s metres" % _n(int(c.vis))) if int(c.vis) < 9000 else "more than ten kilometres"], {"voice": "narrator"})
	var e2 := _end(0.8)
	e2.recon = {"span": 3.0, "post": 0.0, "freeze": true}
	_shots(e2, [["overview", 0.0]])
	# flight data sequence with the FDR overlay and CVR captions
	if samples.size() >= 8:
		var span := clampf(float(samples[samples.size() - 1][0]) - float(samples[0][0]), 30.0, 100.0)
		var fd := _seg("fdr", "world", span + 3.0, {"label": "INVESTIGATION ANIMATION", "fdr": true, "site": "none", "music": "", "amb": "wind"})
		var fdt0 := float(fd.t0)
		# narrated findings timed against the data
		var fl := []
		fl.append("The animation shows the final %d seconds of the flight, reconstructed from the flight data recorder." % int(span))
		if int(tf.get("ap_off", -1)) > 0:
			fl.append("%d seconds before impact, the autopilot was disconnected." % int(tf.ap_off))
		if int(tf.get("steep", -1)) > 0:
			fl.append("%d seconds before impact, the rate of descent exceeded three thousand feet per minute." % int(tf.steep))
		if int(tf.get("gear", 1)) == 0 and String(c.cat) != "trainer":
			fl.append("The landing gear was not extended.")
		fl.append("The ground proximity warning system issued repeated alerts, which were not followed by a recovery." if int(tf.get("max_vs", 0)) > 3000 else "Recorded parameters were within normal limits until the final seconds.")
		for tx in fl:
			_line("narrator", narr, tx, {"voice": "narrator"})
		_cursor = maxf(_cursor, fdt0 + span + 1.0)
		var e3 := _end(1.8)
		e3.recon = {"span": span, "post": maxf(float(e3.t1) - float(e3.t0) - span, 1.8)}
		var sl := [["fdr_chase", 0.0], ["fdr_side", 0.22], ["analysis", 0.42], ["fdr_cockpit", 0.6], ["fdr_side", 0.74], ["fdr_ground", 0.88]]
		_shots(e3, sl)
		_cvr_lines(inc, fdt0, span)
		_cue(fdt0 + span, "impact", -6.0)
	# impact
	var im := _seg("impact", "world", 7.0, {"site": "impact", "card": "impact", "label": "IMPACT"})
	_line("narrator", narr, "The aircraft struck the %s at %d knots, descending at %s feet per minute, with %d degrees of pitch and %d degrees of bank." % [
		"water" if c.ditching else "ground", int(c.impact_kt), _n(int(c.impact_fpm)), int(c.impact_pitch), int(c.impact_bank)], {"voice": "narrator"})
	var e4 := _end(0.8)
	e4.recon = {"span": 0.0, "post": float(e4.t1) - float(e4.t0), "after": true}
	_shots(e4, [["impact_site", 0.0]])
	# findings
	var fnd: Array = inc.get("findings", [])
	if not fnd.is_empty():
		var fs := _seg("findings", "world", 6.0, {"site": "investigation", "card": "findings"})
		_line("narrator", narr, "Findings.", {"voice": "narrator", "gap": 0.6})
		var fi := 0
		for f in fnd.slice(0, 5):
			var l := _line("narrator", narr, String(f), {"voice": "narrator"})
			l.item = fi
			fi += 1
		var e5 := _end(1.0)
		_shots(e5, [["site_orbit", 0.0]])
	# probable cause
	var cs := _seg("cause", "world", 6.0, {"site": "investigation", "card": "cause"})
	_line("narrator", narr, "Probable cause.", {"voice": "narrator", "gap": 0.5})
	_line("narrator", narr, String(c.cause) + "." if String(c.cause) != "" else "The investigation could not determine the probable cause with certainty.", {"voice": "narrator"})
	var e6 := _end(1.4)
	_shots(e6, [["site_high", 0.0]])
	# factors and responsibility
	var fac: Array = inc.get("factors", [])
	var sh: Dictionary = inc.get("shares", {})
	var ff := _seg("factors", "world", 7.0, {"site": "investigation", "card": "factors"})
	_line("narrator", narr, "Contributing factors." if not fac.is_empty() else "Distribution of causal factors.", {"voice": "narrator", "gap": 0.5})
	for f2 in fac.slice(0, 3):
		_line("narrator", narr, String(f2), {"voice": "narrator"})
	var top := []
	for k in ["pilot", "maintenance", "weather", "atc", "manufacturer"]:
		if float(sh.get(k, 0.0)) > 0.04:
			top.append("%s %d percent" % [{"pilot": "flight crew", "atc": "air traffic control"}.get(k, k), int(float(sh[k]) * 100.0)])
	if not top.is_empty():
		_line("narrator", narr, "The board attributes the causal factors as follows: %s." % ", ".join(top), {"voice": "narrator"})
	var e7 := _end(1.0)
	_shots(e7, [["site_orbit", 0.0]])
	# safety recommendations
	var recs: Array = inc.get("recommendations", [])
	if not recs.is_empty():
		var rc := _seg("recs", "world", 6.0, {"site": "investigation", "card": "recs"})
		_line("narrator", narr, "Safety recommendations.", {"voice": "narrator", "gap": 0.5})
		for rr in recs.slice(0, 3):
			_line("narrator", narr, String(rr), {"voice": "narrator"})
		var e8 := _end(1.0)
		_shots(e8, [["site_high", 0.0]])
	# in memory
	if int(c.fatal) > 0:
		var mm := _seg("remember", "world", 7.0, {"site": "investigation", "card": "remember", "music": "somber"})
		_line("narrator", narr, "This report is dedicated to the %s people who lost their lives, and to their families." % _n(int(c.fatal)), {"voice": "narrator"})
		var e9 := _end(2.2)
		_shots(e9, [["site_high", 0.0]])
	prog.victims = inc.get("victims", [])
	prog.findings = fnd
	prog.factors = fac
	prog.recommendations = recs
	prog.shares = sh
	prog.cause = String(c.cause)
	prog.ctx = c
	return _finish()


## CVR transcript lines inside the flight-data segment: recorded transmissions plus the aural
## warnings the data imply (autopilot disconnect, sink rate, pull up, stall).
func _cvr_lines(inc: Dictionary, seg_t0: float, span: float) -> void:
	var samples: Array = inc.get("samples", [])
	if samples.is_empty():
		return
	var t_end := float(samples[samples.size() - 1][0])
	var start := t_end - span
	var out := []
	for v in inc.get("cvr", []):
		var vt := float(v.get("t", 0.0))   # seconds relative to impact (negative)
		if vt >= -span and vt <= 0.0:
			out.append([span + vt, _cvr_who(String(v.get("who", ""))), String(v.get("text", ""))])
	# synthetic aural alerts derived from the data
	var prev_ap := -1
	var last_alert := -100.0
	for s in samples:
		var st := float(s[0])
		if st < start:
			prev_ap = int(s[12])
			continue
		var rel := st - start
		if prev_ap == 1 and int(s[12]) == 0:
			out.append([rel, "AURAL", "[autopilot disconnect warning]"])
		prev_ap = int(s[12])
		var agl := float(s[3]) - Geo.ground_height(float(s[1]), float(s[2]))
		var vs_fpm := float(s[5]) / U.FPM
		if rel - last_alert > 3.2 and agl < 2500.0 * U.FT and agl > 30.0:
			if vs_fpm < -6000.0 or (vs_fpm < -3000.0 and agl < 1000.0 * U.FT):
				out.append([rel, "GPWS", "PULL UP. PULL UP."])
				last_alert = rel
			elif vs_fpm < -2400.0:
				out.append([rel, "GPWS", "SINK RATE. SINK RATE."])
				last_alert = rel
		var tpl := AircraftTypes.get_type(String(inc.get("type", "s320")))
		if float(s[4]) < float(tpl.vs1) * 1.02 and float(s[4]) > 30.0 and float(s[6]) > 5.0 and rel - last_alert > 3.0:
			out.append([rel, "AURAL", "[stall warning] STALL. STALL."])
			last_alert = rel
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var next_free := 0.0
	for o in out:
		var at := maxf(float(o[0]), next_free)
		if at > span:
			continue
		var d := clampf(_dur(String(o[2])) * 0.8, 1.6, 4.0)
		lines.append({"t0": seg_t0 + at, "t1": seg_t0 + at + d, "who": "cvr", "name": String(o[1]), "text": String(o[2]), "speak": false, "style": "cvr", "voice": "cvr"})
		next_free = at + 0.3


static func _cvr_who(w: String) -> String:
	match w:
		"FO":
			return "F/O"
		"PA":
			return "PA"
		"PILOT", "pilot":
			return "CAPT"
	if w.length() <= 4:
		return w.to_upper()
	# station names ("Rivermouth Tower") become TWR, APP...
	if "Tower" in w:
		return "TWR"
	if "Approach" in w or "Radar" in w:
		return "APP"
	if "Ground" in w:
		return "GND"
	if "Delivery" in w:
		return "DEL"
	if "Control" in w or "Center" in w:
		return "CTR"
	return "CAPT"


# ================================================================== short witness phone clip
func _phone_clip(inc: Dictionary, video: Dictionary) -> Dictionary:
	ctx = _context(inc)
	outlet = "skyline"
	_begin("phone", "Phone video · %s" % String(inc.get("place", "")))
	prog.world = _world_spec(inc, float(inc.get("clock", WorldSim.clock)))
	prog.incident = String(inc.get("id", ""))
	prog.raw = true
	prog.no_ticker = true
	var handle := String(video.get("author", "@witness"))
	var p := _seg("phone", "world", 12.0, {"label": "", "amb": "outdoor", "site": "impact", "handle": handle, "phone_seed": int(video.get("seed", 1)), "raw": true, "lead": 1.2})
	_line("witness", handle, _pick(["What is that plane doing?", "Look how low that plane is!", "Is that plane okay?"]), {"speak": false, "style": "nat"})
	_line("witness", handle, _pick(["Oh no. Oh no no no...", "It's going down!", "Oh my God!"]), {"speak": false, "style": "nat"})
	_hold(2.5)
	_line("witness", handle, _pick(["Oh my God. Oh my God.", "Call emergency! Call emergency now!", "There's smoke everywhere..."]), {"speak": false, "style": "nat"})
	_line("witness", handle, _pick(["Those poor people...", "I can't... I can't watch this.", "Everyone's running over there."]), {"speak": false, "style": "nat"})
	var e := _end(1.0)
	var dur := float(e.t1) - float(e.t0)
	e.recon = {"span": minf(9.0, dur - 3.0), "post": maxf(dur - 9.0, 3.0)}
	_shots(e, [["phone", 0.0]])
	_cue(float(e.t0) + minf(9.0, dur - 3.0), "impact", -2.0)
	return _finish()


# ================================================================== the player's own flight
func _replay(rp: Dictionary) -> Dictionary:
	outlet = "skyline"
	var samples: Array = rp.get("samples", [])
	if samples.size() < 2:
		return {}
	_begin("replay", "Flight replay · %s" % String(rp.get("callsign", "")))
	prog.raw = true
	prog.no_ticker = true
	var outcome := String(rp.get("outcome", "landed"))
	var t_end := float(samples[samples.size() - 1][0])
	var t_start := float(samples[0][0])
	prog.world = {"mode": "replay", "samples": samples, "type": String(rp.get("type", "s320")), "airline": String(rp.get("airline", "SKF")),
		"reg": String(rp.get("reg", "")), "ending": "crash" if outcome == "crashed" else ("ditch" if outcome == "ditched" else "landed"),
		"clock": float(rp.get("clock", WorldSim.clock)), "air_clock": float(rp.get("clock", WorldSim.clock)), "weather": rp.get("weather", {}),
		"x": float(samples[samples.size() - 1][1]), "z": float(samples[samples.size() - 1][2]), "heading": float(samples[samples.size() - 1][8]),
		"dep": String(rp.get("dep", "")), "arr": String(rp.get("arr", "")), "fire": outcome == "crashed", "severity": 0.7, "seed": U.hash_str(String(rp.get("callsign", "")))}
	var s := _seg("replay", "world", t_end - t_start + (10.0 if outcome in ["crashed", "ditched"] else 6.0), {"label": "", "replay": true, "site": "none", "amb": "wind", "lead": 0.0})
	s.recon = {"span": t_end - t_start, "post": float(s.t1) - float(s.t0) - (t_end - t_start)}
	s.shots = [{"cam": "director", "t": 0.0}]
	_end(0.0)
	prog.callsign = String(rp.get("callsign", ""))
	prog.cvr = rp.get("cvr", [])
	return _finish()


# ================================================================== everyday stories
func _benign(video: Dictionary, art: Dictionary) -> Dictionary:
	var icao := String(video.get("airport", "SKPC"))
	var ap := Airports.get_ap(icao)
	var al := Airlines.get_al(String(video.get("airline", "SKF")))
	var tpl := AircraftTypes.get_type(String(video.get("type_id", "s320")))
	var tags: Array = art.get("tags", [])
	var scene := String(video.get("scene", "arrival"))
	var air := float(art.get("t", WorldSim.clock))
	if not art.has("outlet"):
		outlet = "gazette"
	var topic := "arrival"
	if "diversion" in tags:
		topic = "medical"
	elif "turbulence" in tags:
		topic = "turbulence"
	elif "weather" in tags:
		topic = "weather"
	elif "cabin" in tags:
		topic = "unruly"
	elif "business" in tags or "routes" in tags:
		topic = "business"
	elif scene == "storm_landing":
		topic = "storm"
	elif "incident" in tags or scene == "emergency_landing":
		topic = "emergency"
	_begin("report_" + topic, String(art.get("headline", "News report")))
	prog.air_clock = air
	var emergency := topic in ["emergency", "medical", "turbulence"]
	prog.world = {"mode": "airport", "icao": icao, "type": String(tpl.get("id", video.get("type_id", "s320"))) if tpl.has("id") else String(video.get("type_id", "s320")),
		"airline": String(video.get("airline", "SKF")), "clock": air - 1800.0, "air_clock": air, "emergency": emergency, "storm": topic in ["weather", "storm"],
		"seed": U.hash_str(String(art.get("id", "x")) + icao), "ending": "landed"}
	var anchor := NewsStyle.anchor(outlet, U.hash_str(String(art.get("id", ""))) % 2)
	var rep := NewsStyle.reporter(outlet, U.hash_str(String(art.get("id", "")) + "rep"))
	var a_name := String(anchor[0])
	var r_name := String(rep[0])
	var st := NewsStyle.get_style(outlet)
	var num := ""
	var hl := String(art.get("headline", ""))
	var lede := String(art.get("lede", ""))
	for w in lede.split(" ", false):
		if w.length() >= 3 and w.length() <= 7 and w.substr(0, 2) == w.substr(0, 2).to_upper() and w.substr(2).is_valid_int():
			num = w.trim_suffix(".").trim_suffix(",")
	if num == "":
		num = "%s%d" % [al.get("iata", ""), 100 + r.randi() % 800]
	prog.tag = {"emergency": "TRAVEL NEWS", "medical": "TRAVEL NEWS", "turbulence": "BREAKING", "weather": "WEATHER WATCH", "unruly": "TRAVEL NEWS",
		"business": "BUSINESS", "storm": "WATCH", "arrival": "TRAVEL NEWS"}.get(topic, "NEWS")
	prog.headline = hl.to_upper() if hl.length() < 60 else hl.substr(0, 57).to_upper() + "..."
	prog.sub = "%s · %s" % [String(ap.get("name", "")).to_upper(), U.fmt_date(air).to_upper()]
	prog.ticker = ["%s: DEPARTURES AND ARRIVALS %s" % [String(ap.get("short", "")).to_upper(), "DELAYED" if topic == "weather" else "OPERATING NORMALLY"],
		"%s ON-TIME PERFORMANCE %d%% THIS WEEK" % [String(al.get("name", "")).to_upper(), 70 + r.randi() % 26],
		"WEATHER: %s" % ["STORMS EASING OVERNIGHT", "SHOWERS CLEARING", "FOG EXPECTED ON THE COAST AT DAWN", "BRIGHT AND BREEZY"][r.randi() % 4],
		"AIRPORT TIP: ARRIVE TWO HOURS BEFORE INTERNATIONAL DEPARTURES", "%s REPORTS RECORD SUMMER BOOKINGS" % String(Airlines.get_al(Airlines.ORDER[r.randi() % 5]).name).to_upper()]
	var s1 := _seg("studio", "studio", 5.0, {"music": "bed", "graphic": "story"})
	var intro := []
	match topic:
		"emergency":
			intro.append("%s A scare for passengers on a %s flight today." % [_hello(air), al.get("name", "")])
			intro.append(lede if lede != "" else "The crew declared an emergency and returned to %s." % ap.get("short", ""))
		"medical":
			intro.append("A %s flight made an unscheduled stop today after a passenger fell seriously ill on board." % al.get("name", ""))
			intro.append(lede)
		"turbulence":
			intro.append("Several people are in hospital after a %s flight hit severe turbulence." % al.get("name", ""))
			intro.append(lede)
		"weather":
			intro.append("Storms have caused disruption for travellers at %s today." % ap.get("short", ""))
			intro.append(lede)
		"unruly":
			intro.append("Police met a %s flight on arrival today after trouble on board." % al.get("name", ""))
			intro.append(lede)
		"business":
			intro.append(hl + ".")
			intro.append(lede)
		"storm":
			intro.append("Passengers on one %s flight are praising their pilots tonight after a landing in some of the worst weather of the year." % al.get("name", ""))
			intro.append(lede)
		_:
			intro.append(hl + ".")
			intro.append(lede)
	for tx in intro:
		if tx.strip_edges() != "":
			_line("anchor", a_name, tx, {"voice": "anchor"})
	var e1 := _end()
	_shots(e1, [["two", 0.0], ["single_a", 0.35]])
	_third("name", a_name.to_upper(), String(st.show), e1.t0 + 1.0, minf(e1.t0 + 6.5, e1.t1))
	_third("strap", String(prog.headline), String(prog.sub), e1.t0 + 1.8, 1e9, String(prog.tag))
	# footage of the aircraft
	var sp := _seg("spotter", "world", 10.0, {"label": "", "amb": "airport", "music": "", "storm": topic in ["weather", "storm"]})
	var fl := []
	match topic:
		"emergency":
			fl.append("This was the moment the %s touched down, with fire crews following it along the runway as a precaution." % tpl.get("short", ""))
			fl.append("Engineers are now inspecting the aircraft.")
		"medical":
			fl.append("Paramedics were waiting at the stand when the aircraft arrived.")
			fl.append("The airline said the crew's priority was the passenger's welfare.")
		"turbulence":
			fl.append("Ambulances met the %s when it landed. Witnesses say drinks trolleys hit the ceiling." % tpl.get("short", ""))
		"weather", "storm":
			fl.append("Video shared online shows aircraft battling gusts of more than thirty knots on the approach.")
			fl.append("Some crews abandoned their landings and tried again; others diverted to other airports.")
		_:
			fl.append("The %s will operate the route, the airline says, with daily flights from next month." % tpl.get("name", ""))
	for tx2 in fl:
		_line("vo", a_name, tx2, {"voice": "anchor"})
	var e2 := _end(1.5)
	_shots(e2, [["spotter_long", 0.0], ["spotter_track", 0.4], ["spotter_rollout", 0.75]])
	_third("label", "%s · %s" % [String(ap.get("short", "")).to_upper(), U.fmt_date(air).to_upper()], "FOOTAGE: %s" % String(Names.handle(r)).to_upper(), e2.t0 + 0.5, e2.t1 - 0.5)
	# passenger / reporter at the terminal
	var pax := WorldSim.person(r.randi_range(WorldSim.FREQUENT_FLYERS * 5, WorldSim.POPULATION - 1))
	var iv := _seg("interview", "world", 6.0, {"amb": "terminal", "where": "terminal", "person": pax.get("id", 0)})
	var q := {"emergency": ["There was a loud bang just after we took off, and the captain came on and said we were going back.", "The crew were brilliant. Very calm. Everyone clapped when we landed."],
		"medical": ["A doctor on board helped. You could tell it was serious.", "Honestly, nobody minded the delay. You just hope the person is okay."],
		"turbulence": ["One second we were having a coffee, the next everything was on the ceiling.", "Wear your seatbelt. That's all I'll say."],
		"weather": ["We've been here six hours. They keep saying another hour.", "I'd rather be late than in the air in that."],
		"storm": ["It was the bumpiest landing I've ever had, but it was so smooth at the end.", "Whoever was flying that, thank you."],
		"unruly": ["He was shouting and trying to get to the door. A few of us helped the crew.", "It was frightening, but the crew were incredible."],
		"business": ["It'll make visiting family so much easier.", "Finally. We've been waiting years for this route."],
		"arrival": ["Good flight, nice crew, on time. Can't complain.", "It was a lovely flight."]}.get(topic, ["It was a lovely flight."])
	for tx3 in q:
		_line("interview", String(pax.get("name", "")), String(tx3), {"voice": "witness", "style": "sot"})
	var e3 := _end(0.6)
	_shots(e3, [["interview", 0.0]])
	_third("name", String(pax.get("name", "")).to_upper(), "PASSENGER" if topic != "business" else "LOCAL RESIDENT", e3.t0 + 0.5, e3.t1 - 0.3)
	if topic in ["emergency", "weather", "turbulence", "unruly"]:
		var su := _seg("standup", "world", 6.0, {"amb": "airport", "where": "terminal"})
		_line("reporter", r_name, {"emergency": "%s says the aircraft will stay on the ground until engineers are satisfied it is safe." % al.get("name", ""),
			"weather": "The airport says it hopes to clear the backlog by tomorrow morning, but warns there may be more cancellations.",
			"turbulence": "Investigators will look at whether the crew had any warning of the turbulence.",
			"unruly": "Police say a man has been arrested and will appear in court on Monday."}.get(topic, "") + " %s, %s News, %s." % [r_name, String(st.name).split(" ")[0], ap.get("short", "")], {"voice": "reporter"})
		var e4 := _end(0.8)
		_shots(e4, [["standup", 0.0]])
		_third("name", r_name.to_upper(), String(ap.get("name", "")).to_upper(), e4.t0 + 0.6, e4.t1 - 0.3)
	var ou := _seg("outro", "studio", 4.0, {"music": "bed_out", "graphic": "story"})
	var lighter := {"emergency": "Glad to hear everyone was safe.", "medical": "We hope the passenger makes a full recovery.", "turbulence": "Keep those belts fastened.",
		"weather": "If you're flying tonight, check with your airline before you travel.", "storm": "Not a bad bit of flying.", "unruly": "Behave yourselves up there.",
		"business": "One for the travel plans.", "arrival": "And that's the travel news."}.get(topic, "That's the travel news.")
	_line("anchor", a_name, lighter, {"voice": "anchor"})
	var e5 := _end(1.0)
	_shots(e5, [["single_a", 0.0], ["wide_out", 0.5]])
	_cue(e5.t1 - 2.2, "outro", -6.0)
	return _finish()
