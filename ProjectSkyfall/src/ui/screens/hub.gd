extends ScreenBase
## Career hub: the pilot's standing, what they can fly next, job offers, training, rest, and
## what the world is talking about.


func setup(params: Dictionary) -> void:
	if not Game.has_character():
		Game.goto("menu")
		return
	var p: Dictionary = Game.player
	var al := Airlines.get_al(String(p.get("airline", ""))) if String(p.get("airline", "")) != "" else {}
	frame("%s %s" % [p.rank, p.name], "%s · %s · %s" % [al.get("name", "Unemployed"), Airports.get_ap(String(p.location)).get("name", p.location),
		U.fmt_datetime(WorldSim.clock)], "menu", 0.64)
	if params.get("welcome", false):
		var w := card("")
		w.add_child(UIStyle.rich("[b]Welcome, %s.[/b] Your first flights are listed below. Brief a flight to see the aircraft, the weather and the load, then take it from the gate. Fly safely - everything you do here is remembered." % p.first, 15))
	_status_card(p, al)
	_assignments(p)
	_actions(p)
	_news()


func _status_card(p: Dictionary, al: Dictionary) -> void:
	var c := card("Pilot")
	var grid := UIStyle.hbox(30)
	var a := UIStyle.vbox(4)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.custom_minimum_size = Vector2(380, 0)
	stat_row(a, "Licence", String(p.license) + (" (suspended)" if bool(p.get("license_suspended", false)) else ""),
		UIStyle.RED if String(p.license) == "Revoked" or bool(p.get("license_suspended", false)) else UIStyle.TEXT)
	stat_row(a, "Flight hours", "%s h (%d flights, %d landings)" % [U.fmt_int(int(float(p.hours))), int(p.flights), int(p.landings)])
	stat_row(a, "Type ratings", ", ".join(p.ratings.map(func(t): return AircraftTypes.get_type(t).short)))
	stat_row(a, "Money", U.fmt_money(float(p.money)), UIStyle.GREEN if float(p.money) >= 0.0 else UIStyle.RED)
	stat_row(a, "Base", "%s (now at %s)" % [p.base, p.location])
	grid.add_child(a)
	var b := UIStyle.vbox(4)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter(b, "Reputation", float(p.reputation))
	meter(b, "Safety record", float(p.safety), UIStyle.GREEN if float(p.safety) > 70.0 else UIStyle.AMBER)
	meter(b, "Public image", float(p.get("public", 50.0)), UIStyle.MAGENTA)
	grid.add_child(b)
	c.add_child(grid)
	var block := _blocked_reason(p)
	if block != "":
		c.add_child(UIStyle.rich("[color=#ffb347]%s[/color]" % block, 15))


static func _blocked_reason(p: Dictionary) -> String:
	if String(p.license) == "Revoked":
		return "Your licence has been revoked. You cannot fly as a pilot."
	if float(p.get("recovery_until", 0.0)) > WorldSim.clock:
		return "On medical leave (%s injuries) until %s." % [p.get("injury", ""), U.fmt_date(float(p.recovery_until))]
	if float(p.get("suspended_until", 0.0)) > WorldSim.clock:
		return "Suspended from flying until %s." % U.fmt_date(float(p.suspended_until))
	if String(p.get("airline", "")) == "":
		return "You are not employed by an airline. Check the job board."
	return ""


func _assignments(p: Dictionary) -> void:
	var c := card("Your next flights")
	var flights := upcoming_for(p)
	var blocked := _blocked_reason(p) != ""
	if flights.is_empty():
		c.add_child(UIStyle.label("No flights for you from %s in the next day." % p.location, 15, UIStyle.DIM))
		if String(p.location) != String(p.base):
			c.add_child(UIStyle.button("Positioning flight to base %s" % p.base, func():
				WorldSim.advance(3.0 * 3600.0)
				p.location = p.base
				Game.save_game()
				Game.goto("hub")))
		return
	for f in flights:
		var h := UIStyle.hbox(10)
		var t := AircraftTypes.get_type(String(f.type))
		var txt := "[b]%s[/b]  %s → %s   [color=#9fb1c2]%s · dep %s · %s · %s[/color]" % [f.number, f.from, f.to, t.short,
			U.fmt_clock(float(f.dep)), U.fmt_duration(float(f.block)), ("%d pax" % int(f.pax)) if int(f.pax) > 0 else ("training" if bool(f.training) else "cargo")]
		var r := UIStyle.rich(txt, 15)
		h.add_child(r)
		var b := UIStyle.button("Brief", func(): Game.goto("briefing", {"flight": f}), 90, UIStyle.ACCENT)
		b.disabled = blocked
		h.add_child(b)
		c.add_child(h)


static func upcoming_for(p: Dictionary) -> Array:
	var out := []
	var day := WorldSim.day_index()
	for d in [day, day + 1]:
		for f in WorldSim.schedule_for_day(d):
			if String(f.airline) != String(p.airline) or String(f.from) != String(p.location):
				continue
			if not String(f.type) in p.ratings:
				continue
			if float(f.dep) < WorldSim.clock + 20.0 * 60.0:
				continue
			out.append(f)
			if out.size() >= 6:
				return out
	return out


func _actions(p: Dictionary) -> void:
	var c := card("Time and career")
	var row := UIStyle.hbox(8)
	row.add_child(UIStyle.button("Rest 8 hours", func():
		WorldSim.advance(8.0 * 3600.0)
		Game.save_game()
		Game.goto("hub")))
	var block := _blocked_reason(p)
	if block != "" and String(p.license) != "Revoked":
		var until := maxf(float(p.get("recovery_until", 0.0)), float(p.get("suspended_until", 0.0)))
		if until > WorldSim.clock:
			row.add_child(UIStyle.button("Wait until cleared", func():
				WorldSim.advance(until - WorldSim.clock + 3600.0)
				p.license_suspended = false
				p.injury = ""
				Game.save_game()
				Game.goto("hub")))
	row.add_child(UIStyle.button("Job board", func(): Game.goto("jobs")))
	row.add_child(UIStyle.button("Logbook", func(): Game.goto("logbook")))
	row.add_child(UIStyle.button("World news", func(): Game.goto("news")))
	row.add_child(UIStyle.button("Settings", func(): Game.goto("settings", {"back": "hub"})))
	c.add_child(row)
	var notes: Array = p.get("notes", [])
	if not notes.is_empty():
		var txt := ""
		for n in notes.slice(maxi(notes.size() - 4, 0)):
			txt += "%s  %s  %s\n" % [U.fmt_date_short(float(n.t)), ("+" if float(n.money) >= 0.0 else "") + U.fmt_money(float(n.money)), n.reason]
		c.add_child(UIStyle.rich("[color=#9fb1c2]%s[/color]" % txt, 13))


func _news() -> void:
	var arts: Array = News.articles
	if arts.is_empty():
		return
	var c := card("In the news")
	for a in arts.slice(maxi(arts.size() - 4, 0)):
		var h := String(a.get("headline", ""))
		var b := UIStyle.button(h, func(): Game.goto("news", {"article": a.get("id", "")}))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		c.add_child(b)
