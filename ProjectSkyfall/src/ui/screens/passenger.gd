extends ScreenBase
## Book a seat on any scheduled flight and ride along: board with the other passengers, watch the
## crew work, walk the cabin, talk to people, look out of the window.

var dep := "SKPC"
var seat_pref := "window"
var _list: VBoxContainer


func setup(_params: Dictionary) -> void:
	frame("Fly as a passenger", "Pick a departure board and take a seat", "menu", 0.62)
	var c := card("Departures")
	var aps: Array = Airports.ORDER
	c.add_child(option(aps.map(func(a): return "%s  %s" % [a, Airports.get_ap(a).name]), aps.find(dep), func(i):
		dep = aps[i]
		_fill()))
	var prefs := ["window", "aisle", "any"]
	c.add_child(option(["Window seat", "Aisle seat", "Any seat"], 0, func(i): seat_pref = prefs[i]))
	_list = UIStyle.vbox(6)
	c.add_child(_list)
	_fill()


func _fill() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var rows := WorldSim.fids(dep, true, 14)
	if rows.is_empty():
		_list.add_child(UIStyle.label("No departures in the next hours.", 14, UIStyle.DIM))
	for row in rows:
		var f: Dictionary = row.flight
		var st: Dictionary = row.status
		if bool(f.cargo) or bool(f.training):
			continue
		var h := UIStyle.hbox(10)
		var t := AircraftTypes.get_type(String(f.type))
		h.add_child(UIStyle.rich("[b]%s[/b]  %s  → %s   [color=#9fb1c2]%s · %s · %s[/color]" % [U.fmt_clock(float(f.dep)), f.number,
			Airports.get_ap(String(f.to)).short, t.short, Airlines.get_al(String(f.airline)).name, st.status], 15))
		var b := UIStyle.button("Book", func(): _board(f), 80, UIStyle.ACCENT)
		b.disabled = String(st.status) in ["Departed", "Approaching", "Landed", "Arrived", "Cancelled"]
		h.add_child(b)
		_list.add_child(h)


func _board(f: Dictionary) -> void:
	var lay := CabinLayout.get_layout(String(f.type))
	var seats: Array = lay.seats.filter(func(s): return seat_pref == "any" or (seat_pref == "window" and bool(s.window)) or (seat_pref == "aisle" and bool(s.aisle)))
	var seat_id := ""
	if not seats.is_empty():
		seat_id = String(seats[randi() % seats.size()].id)
	Game.goto("flight", {"mode": "passenger", "type": f.type, "airline": f.airline, "reg": f.reg if String(f.reg) != "" else "CR-PAX",
		"dep": f.from, "arr": f.to, "callsign": f.callsign, "flight_id": f.id, "clock": maxf(WorldSim.clock, float(f.dep) - 30.0 * 60.0),
		"sched_arr": float(f.arr), "pax": maxi(int(f.pax), 1), "seat": seat_id, "start": "gate"})
