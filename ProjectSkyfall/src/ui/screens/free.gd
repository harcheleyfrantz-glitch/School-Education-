extends ScreenBase
## Free flight: any aircraft, any livery, any airport pair, time of day, weather and events.

var cfg := {"type": "s320", "airline": "SKF", "dep": "SKPC", "arr": "SKRV", "start": "gate", "hour": 10.0, "weather": "live", "events": "realistic"}
var _airline_opt: OptionButton


func setup(_params: Dictionary) -> void:
	frame("Free flight", "Fly anything, anywhere. Nothing here affects your career.", "menu", 0.6)
	var c := card("Aircraft")
	var types: Array = AircraftTypes.ORDER
	var tnames := types.map(func(t): return "%s %s" % [AircraftTypes.get_type(t).maker, AircraftTypes.get_type(t).name])
	c.add_child(option(tnames, types.find(cfg.type), func(i):
		cfg.type = types[i]
		_fill_airlines()))
	_airline_opt = OptionButton.new()
	_airline_opt.custom_minimum_size = Vector2(0, 38)
	c.add_child(_airline_opt)
	_fill_airlines()
	var r := card("Route")
	var aps: Array = Airports.ORDER
	var anames := aps.map(func(a): return "%s  %s" % [a, Airports.get_ap(a).name])
	r.add_child(UIStyle.label("From", 13, UIStyle.DIM))
	r.add_child(option(anames, aps.find(cfg.dep), func(i): cfg.dep = aps[i]))
	r.add_child(UIStyle.label("To", 13, UIStyle.DIM))
	r.add_child(option(anames, aps.find(cfg.arr), func(i): cfg.arr = aps[i]))
	var starts := ["gate", "runway", "air"]
	r.add_child(option(["Start at a gate", "Start on the runway", "Start on approach (40 km out)"], 0, func(i): cfg.start = starts[i]))
	var e := card("Conditions")
	var hl := UIStyle.label("", 14)
	var hs := HSlider.new()
	hs.min_value = 0.0
	hs.max_value = 23.75
	hs.step = 0.25
	hs.value = cfg.hour
	hs.custom_minimum_size = Vector2(300, 28)
	hs.value_changed.connect(func(v):
		cfg.hour = v
		hl.text = "Local time %02d:%02d" % [int(v), int(fmod(v, 1.0) * 60.0)])
	hl.text = "Local time %02d:%02d" % [int(cfg.hour), 0]
	e.add_child(hl)
	e.add_child(hs)
	var presets: Array = ["live"] + WeatherModel.PRESETS.keys()
	e.add_child(option(presets.map(func(p): return "Weather: " + String(p).capitalize()), 0, func(i): cfg.weather = presets[i]))
	var rates := ["off", "realistic", "frequent"]
	e.add_child(option(["Events: off", "Events: realistic", "Events: frequent"], 1, func(i): cfg.events = rates[i]))
	content.add_child(UIStyle.button("Fly", _fly, 220, UIStyle.ACCENT))


func _fill_airlines() -> void:
	_airline_opt.clear()
	var codes := []
	for c in Airlines.all_codes():
		if Airlines.operates_type(c, cfg.type):
			codes.append(c)
	if codes.is_empty():
		codes = ["SKF"]
	for c2 in codes:
		_airline_opt.add_item(Airlines.get_al(c2).name)
	cfg.airline = codes[0]
	for sig in _airline_opt.item_selected.get_connections():
		_airline_opt.item_selected.disconnect(sig.callable)
	_airline_opt.item_selected.connect(func(i): cfg.airline = codes[i])


func _fly() -> void:
	Game.set_setting("event_rate", cfg.events)
	var day := floorf(WorldSim.clock / 86400.0) * 86400.0
	var al := Airlines.get_al(cfg.airline)
	var params := {"mode": "pilot", "free_flight": true, "type": cfg.type, "airline": cfg.airline,
		"reg": "%sFF%d" % [String(al.get("reg_prefix", "CR-")), randi() % 9], "dep": cfg.dep, "arr": cfg.arr,
		"callsign": "%s %d" % [String(al.get("callsign", "SKYFALL")).capitalize(), randi_range(100, 999)],
		"flight_id": "FREE-%d" % Time.get_ticks_msec(), "clock": day + cfg.hour * 3600.0, "start": cfg.start}
	if cfg.weather != "live":
		params.weather = cfg.weather
	Game.goto("flight", params)
