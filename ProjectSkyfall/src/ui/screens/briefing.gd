extends ScreenBase
## Flight briefing: route, schedule, aircraft and its open defects, weather at both ends and the
## alternate, the load, and the fuel decision. Starts the flight from the gate.

var f: Dictionary
var fuel_kg := 0.0
var fuel_min := 0.0
var fuel_label: Label
var start_kind := "gate"


func setup(params: Dictionary) -> void:
	f = params.get("flight", {})
	if f.is_empty():
		Game.goto("hub")
		return
	var t := AircraftTypes.get_type(String(f.type))
	var al := Airlines.get_al(String(f.airline))
	frame("Flight %s" % f.number, "%s · %s → %s" % [al.get("name", ""), Airports.get_ap(String(f.from)).name, Airports.get_ap(String(f.to)).name], "hub", 0.66)
	_route_card(t)
	_aircraft_card(t)
	_weather_card()
	_fuel_card(t)
	var row := UIStyle.hbox(10)
	row.add_child(option(["Start at the gate (full turnaround)", "Start lined up on the runway"], 0, func(i): start_kind = ["gate", "runway"][i]))
	row.add_child(UIStyle.button("Go to the aircraft", _start, 240, UIStyle.ACCENT))
	content.add_child(row)


func _route_card(t: Dictionary) -> void:
	var c := card("Schedule and route")
	var dist := Airports.distance_nm(String(f.from), String(f.to))
	stat_row(c, "Callsign", String(f.callsign))
	stat_row(c, "Departure", "%s  %s (gate %s)" % [U.fmt_clock(float(f.dep)), f.from, f.gate])
	stat_row(c, "Arrival", "%s  %s" % [U.fmt_clock(float(f.arr)), f.to])
	stat_row(c, "Distance / block", "%d NM · %s" % [int(dist), U.fmt_duration(float(f.block))])
	var cruise := clampf(dist * 180.0, 9000.0, float(t.cruise_alt)) if String(t.category) != "trainer" else 4500.0
	stat_row(c, "Planned cruise", U.fl_or_ft(roundf(cruise / 1000.0) * 1000.0))
	var st := WorldSim.flight_status(f)
	if String(st.get("note", "")) != "":
		stat_row(c, "Notice", String(st.note), UIStyle.AMBER)


func _aircraft_card(t: Dictionary) -> void:
	var c := card("Aircraft")
	var rec := WorldSim.aircraft(String(f.reg))
	stat_row(c, "Type", "%s %s" % [t.maker, t.name])
	stat_row(c, "Registration", "%s%s" % [f.reg, ("  \"%s\"" % rec.name) if String(rec.get("name", "")) != "" else ""])
	if not rec.is_empty():
		stat_row(c, "Age / condition", "%d years · %d%%" % [int(rec.age), int(rec.condition)], UIStyle.GREEN if float(rec.condition) > 80.0 else UIStyle.AMBER)
		var defects: Array = rec.get("defects", [])
		if defects.is_empty():
			stat_row(c, "Tech log", "No open items")
		else:
			for d in defects:
				stat_row(c, "Deferred item", String(d.text), UIStyle.AMBER if int(d.get("severity", 1)) < 2 else UIStyle.RED)
	stat_row(c, "Load", ("%d passengers" % int(f.pax)) if int(f.pax) > 0 else ("cargo flight" if bool(f.cargo) else "training flight"))


func _weather_card() -> void:
	var c := card("Weather")
	for icao in [String(f.from), String(f.to)]:
		var tm := float(f.dep) if icao == String(f.from) else float(f.arr)
		var l := UIStyle.label(WeatherModel.metar(icao, tm), 14, UIStyle.TEXT)
		l.add_theme_font_override("font", UIStyle.mono())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(l)
		var ap: Dictionary = Airports.get_ap(icao)
		var w := WeatherModel.sample(float(ap.x), float(ap.z), tm)
		c.add_child(UIStyle.label("%s: %s (%s)" % [ap.short, WeatherModel.describe(w), WeatherModel.flight_category(w, float(ap.elev) / U.FT)], 13, UIStyle.DIM))


func _fuel_card(t: Dictionary) -> void:
	var c := card("Fuel")
	var dist := Airports.distance_m(String(f.from), String(f.to))
	var trip_h := dist / (float(t.cruise_tas) * U.KT) / 3600.0
	var endurance_h := float(t.range_nm) * U.NM / (float(t.cruise_tas) * U.KT) / 3600.0
	var burn := float(t.max_fuel) / maxf(endurance_h, 1.0)
	fuel_min = clampf((trip_h + 0.75) * burn, float(t.max_fuel) * 0.15, float(t.max_fuel))
	fuel_kg = fuel_min
	c.add_child(UIStyle.label("Trip %.0f kg · reserve and alternate %.0f kg · minimum %.0f kg" % [trip_h * burn, 0.75 * burn, fuel_min], 14, UIStyle.DIM))
	var sl := HSlider.new()
	sl.min_value = fuel_min * 0.6
	sl.max_value = float(t.max_fuel)
	sl.step = 50.0
	sl.value = fuel_kg
	sl.custom_minimum_size = Vector2(360, 30)
	fuel_label = UIStyle.label("", 15, UIStyle.TEXT, true)
	sl.value_changed.connect(func(v):
		fuel_kg = v
		_update_fuel_label())
	c.add_child(sl)
	c.add_child(fuel_label)
	_update_fuel_label()


func _update_fuel_label() -> void:
	var extra := fuel_kg - fuel_min
	var warn := fuel_kg < fuel_min
	fuel_label.text = "Block fuel %.0f kg (%s%.0f kg extra)%s" % [fuel_kg, "+" if extra >= 0.0 else "", extra,
		"  — BELOW MINIMUM: illegal and dangerous" if warn else ""]
	fuel_label.add_theme_color_override("font_color", UIStyle.RED if warn else UIStyle.TEXT)


func _start() -> void:
	var p: Dictionary = Game.player
	Game.goto("flight", {
		"mode": "pilot", "type": f.type, "airline": f.airline, "reg": f.reg if String(f.reg) != "" else "CR-SFX",
		"dep": f.from, "arr": f.to, "callsign": f.callsign, "flight_id": f.id, "clock": maxf(WorldSim.clock, float(f.dep) - 35.0 * 60.0),
		"sched_arr": float(f.arr), "pax": int(f.pax), "fuel": fuel_kg, "start": start_kind, "stand": "",
		"cargo": 2500.0 if not bool(f.cargo) else float(AircraftTypes.get_type(String(f.type)).max_payload) * 0.7,
		"pilot_name": p.get("name", ""),
	})
