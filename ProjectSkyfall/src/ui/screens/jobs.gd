extends ScreenBase
## Job board and type ratings.


func setup(_params: Dictionary) -> void:
	var p: Dictionary = Game.player
	frame("Job board", "Airlines hiring a pilot with your record", "hub", 0.6)
	var c := card("Offers")
	var offers := CareerRules.hiring_offers(p)
	if offers.is_empty():
		c.add_child(UIStyle.label("Nobody is hiring someone with your experience and record right now.", 14, UIStyle.DIM))
	for o in offers:
		var al := Airlines.get_al(String(o.airline))
		var h := UIStyle.hbox(10)
		h.add_child(UIStyle.rich("[b]%s[/b] — %s on the %s, based at %s. %s/h\n[color=#9fb1c2]%s[/color]" % [al.name, o.rank,
			AircraftTypes.get_type(String(o.type)).name, o.base, U.fmt_money(float(o.pay)), al.get("desc", "")], 14))
		h.add_child(UIStyle.button("Accept", func():
			p.airline = o.airline
			p.rank = o.rank
			p.base = o.base
			p.location = o.base
			p.employment = "employed"
			if not String(o.type) in p.ratings:
				p.ratings.append(o.type)
				WorldSim.advance(14.0 * 86400.0)
			Game.save_game()
			Game.goto("hub"), 100, UIStyle.ACCENT))
		c.add_child(h)
	var t := card("Type ratings (self-funded)")
	for type_id in AircraftTypes.ORDER:
		if type_id in p.ratings:
			continue
		var cost := CareerRules.type_rating_cost(type_id)
		if cost <= 0.0:
			continue
		var h2 := UIStyle.hbox(10)
		h2.add_child(UIStyle.label("%s — %s, 3 weeks" % [AircraftTypes.get_type(type_id).name, U.fmt_money(cost)], 14))
		var b := UIStyle.button("Train", func():
			Game.add_money(-cost, "Type rating " + type_id)
			p.ratings.append(type_id)
			WorldSim.advance(21.0 * 86400.0)
			Game.save_game()
			Game.goto("jobs"), 90)
		b.disabled = float(p.money) < cost or float(p.hours) < 200.0
		h2.add_child(b)
		t.add_child(h2)
