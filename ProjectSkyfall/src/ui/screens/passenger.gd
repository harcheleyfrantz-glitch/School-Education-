extends ScreenBase
## PASSENGER JOURNEY: an airport departures board. Book a seat on any scheduled flight and ride
## along: board with the other passengers, watch the crew work, walk the cabin, talk to people,
## look out of the window.

const AMBER_FIDS := Color(1.0, 0.78, 0.25)

var dep := "SKPC"
var seat_pref := "window"
var cabin_class := "economy"
var _list: VBoxContainer
var _board_title: Label
var _wallet: Label


func setup(_params: Dictionary) -> void:
	if Game.has_character():
		dep = String(Game.player.get("location", dep))
	frame("Passenger Journey", "Pick a departure, choose your seat and ride along in the cabin", "menu", 0.74)
	var top := UIStyle.hbox(12)
	content.add_child(top)
	var aps: Array = Airports.ORDER
	var o := option(aps.map(func(a): return "%s  ·  %s" % [a, Airports.get_ap(a).name]), aps.find(dep), func(i):
		dep = aps[i]
		_fill())
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(o)
	var prefs := [["window", "Window seat"], ["aisle", "Aisle seat"], ["any", "Any seat"]]
	for pr in prefs:
		var key := String(pr[0])
		var b := UIStyle.button(String(pr[1]), Callable(), 0)
		b.toggle_mode = true
		b.button_pressed = key == seat_pref
		b.set_meta("key", key)
		b.pressed.connect(func():
			seat_pref = key
			for c in top.get_children():
				if c is Button and (c as Button).has_meta("key"):
					(c as Button).button_pressed = String(c.get_meta("key")) == seat_pref)
		top.add_child(b)
	for k2 in [["economy", "Economy"], ["business", "Business"]]:
		var key2 := String(k2[0])
		var cb := UIStyle.button(String(k2[1]), Callable(), 0)
		cb.toggle_mode = true
		cb.button_pressed = key2 == cabin_class
		cb.set_meta("cls", key2)
		cb.pressed.connect(func():
			cabin_class = key2
			for c in top.get_children():
				if c is Button and (c as Button).has_meta("cls"):
					(c as Button).button_pressed = String(c.get_meta("cls")) == cabin_class
			_fill())
		top.add_child(cb)
	if Game.has_character():
		_wallet = UIStyle.label("", 14, UIStyle.GREEN)
		top.add_child(_wallet)
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UIStyle.box(Color(0.008, 0.01, 0.014, 0.94), 4, Color(1, 1, 1, 0.1), 1, 16))
	content.add_child(board)
	var bv := UIStyle.vbox(4)
	board.add_child(bv)
	var hh := UIStyle.hbox(10)
	_board_title = UIStyle.title("", 26, AMBER_FIDS)
	_board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(_board_title)
	var clk := UIStyle.label(U.fmt_clock(WorldSim.clock), 24, AMBER_FIDS)
	clk.add_theme_font_override("font", UIStyle.mono())
	hh.add_child(clk)
	bv.add_child(hh)
	bv.add_child(UIStyle.rule(Color(AMBER_FIDS, 0.3)))
	var head := UIStyle.hbox(10)
	for col in [["Time", 70], ["Flight", 80], ["Destination", 0], ["Aircraft", 70], ["Airline", 150], ["Status", 110], ["Fare", 80], ["", 96]]:
		var l := UIStyle.caps(String(col[0]), 10, Color(AMBER_FIDS, 0.65), 800, 2)
		l.custom_minimum_size = Vector2(float(col[1]), 0)
		if int(col[1]) == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	bv.add_child(head)
	_list = UIStyle.vbox(2)
	bv.add_child(_list)
	_fill()


func _fill() -> void:
	_board_title.text = "DEPARTURES  ·  %s" % String(Airports.get_ap(dep).name).to_upper()
	if _wallet:
		_wallet.text = "Wallet %s" % U.fmt_money(float(Game.player.get("money", 0.0)))
	for ch in _list.get_children():
		ch.queue_free()
	var rows := WorldSim.fids(dep, true, 14)
	var shown := 0
	for row in rows:
		var f: Dictionary = row.flight
		var st: Dictionary = row.status
		if bool(f.cargo) or bool(f.training):
			continue
		shown += 1
		var h := UIStyle.hbox(10)
		h.custom_minimum_size = Vector2(0, 38)
		var t := AircraftTypes.get_type(String(f.type))
		h.add_child(_mono(U.fmt_clock(float(f.dep)), 70, AMBER_FIDS))
		h.add_child(_mono(String(f.number), 80, Color.WHITE))
		var dest := _mono(String(Airports.get_ap(String(f.to)).city).to_upper(), 0, AMBER_FIDS)
		dest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(dest)
		h.add_child(_mono(String(t.short), 70, Color(1, 1, 1, 0.7)))
		h.add_child(_mono(String(Airlines.get_al(String(f.airline)).name), 150, Color(1, 1, 1, 0.7)))
		var status := String(st.status)
		var sc := UIStyle.GREEN
		if status in ["Delayed", "Cancelled"]:
			sc = UIStyle.RED
		elif status in ["Boarding", "Final call", "Gate open"]:
			sc = AMBER_FIDS
		elif status in ["Departed", "Approaching", "Landed", "Arrived"]:
			sc = Color(1, 1, 1, 0.4)
		h.add_child(_mono(status.to_upper(), 110, sc))
		var price := Airlines.fare(String(f.airline), Airports.distance_nm(String(f.from), String(f.to)), cabin_class)
		h.add_child(_mono(U.fmt_money(float(price)), 80, Color(0.6, 1.0, 0.7)))
		var b := UIStyle.button("Book", func(): _book(f, price), 96, UIStyle.ACCENT)
		b.custom_minimum_size = Vector2(96, 32)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = status in ["Departed", "Approaching", "Landed", "Arrived", "Cancelled"] or (Game.has_character() and float(Game.player.get("money", 0.0)) < float(price))
		h.add_child(b)
		_list.add_child(h)
		_list.add_child(UIStyle.rule(Color(1, 1, 1, 0.05)))
	if shown == 0:
		_list.add_child(UIStyle.label("No passenger departures in the next hours.", 14, UIStyle.DIM))


func _mono(text: String, w: float, col: Color) -> Label:
	var l := UIStyle.label(text, 15, col)
	l.add_theme_font_override("font", UIStyle.mono())
	l.custom_minimum_size = Vector2(w, 0)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _seat_ok(s: Dictionary) -> bool:
	return seat_pref == "any" or (seat_pref == "window" and bool(s.window)) or (seat_pref == "aisle" and bool(s.aisle))


func _book(f: Dictionary, price: int = 0) -> void:
	var lay := CabinLayout.get_layout(String(f.type))
	var want_biz := cabin_class == "business"
	var seats: Array = lay.seats.filter(func(s): return _seat_ok(s) and (String(s.get("cls", "economy")) in ["business", "vip", "premium"]) == want_biz)
	if seats.is_empty():
		seats = lay.seats.filter(func(s): return seat_pref == "any" or (seat_pref == "window" and bool(s.window)) or (seat_pref == "aisle" and bool(s.aisle)))
	if Game.has_character() and price > 0:
		Game.add_money(-float(price), "Ticket %s %s" % [String(f.number), cabin_class])
		Game.save_game()
		Game.notify("Ticket booked: %s, %s class, %s." % [String(f.number), cabin_class, U.fmt_money(float(price))], "success")
	var seat_id := ""
	if not seats.is_empty():
		seat_id = String(seats[randi() % seats.size()].id)
	var params := {"mode": "passenger", "type": f.type, "airline": f.airline, "reg": f.reg if String(f.reg) != "" else "CR-PAX",
		"dep": f.from, "arr": f.to, "callsign": f.callsign, "flight_id": f.id, "clock": maxf(WorldSim.clock, float(f.dep) - 30.0 * 60.0),
		"sched_arr": float(f.arr), "pax": maxi(int(f.pax), 1), "seat": seat_id, "start": "gate"}
	launch_with_loading("%s to %s" % [f.number, Airports.get_ap(String(f.to)).city], "%s · seat %s" % [Airlines.get_al(String(f.airline)).name, seat_id],
		"home_passenger", func(): Game.goto("flight", params))
