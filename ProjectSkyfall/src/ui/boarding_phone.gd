class_name BoardingPhone
extends PanelContainer
## The phone in your pocket (F2): the operating airline's own app, branded in its livery
## colours, with the live boarding status of this flight: how many people are aboard, who is
## still on the jet bridge and who has not turned up yet.

var session: FlightSession
var _t := 0.0
var _title: Label
var _flight: Label
var _status: Label
var _count: Label
var _bar: ProgressBar
var _classes: Label
var _list: VBoxContainer
var _clock: Label
var _head: PanelContainer


func setup(sess: FlightSession) -> void:
	session = sess
	var al := Airlines.get_al(String(session.ac.airline))
	var liv := Airlines.livery_colors(String(session.ac.airline))
	var brand: Color = liv.tail
	var accent: Color = liv.logo
	if brand.get_luminance() > 0.8:
		brand = liv.text
	custom_minimum_size = Vector2(300, 560)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -320.0
	offset_right = -20.0
	offset_top = -680.0
	offset_bottom = -120.0
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.05, 0.05, 0.06)
	body.set_corner_radius_all(34)
	body.set_content_margin_all(12)
	body.border_color = Color(0.25, 0.26, 0.28)
	body.set_border_width_all(3)
	add_theme_stylebox_override("panel", body)
	var screen := VBoxContainer.new()
	screen.add_theme_constant_override("separation", 0)
	add_child(screen)
	# status bar
	var sb := HBoxContainer.new()
	_clock = _lbl("", 12, Color.WHITE)
	sb.add_child(_clock)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_child(sp)
	sb.add_child(_lbl("5G  87%", 12, Color.WHITE))
	screen.add_child(sb)
	# app header in the airline's colours
	_head = PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = brand
	hs.set_corner_radius_all(14)
	hs.set_content_margin_all(12)
	_head.add_theme_stylebox_override("panel", hs)
	var hv := VBoxContainer.new()
	_head.add_child(hv)
	_title = _lbl(String(al.name).to_upper(), 20, accent if accent.get_luminance() > 0.35 else Color.WHITE)
	hv.add_child(_title)
	hv.add_child(_lbl("My trips  >  Boarding", 12, Color(1, 1, 1, 0.8)))
	screen.add_child(_gap(8))
	screen.add_child(_head)
	screen.add_child(_gap(10))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	screen.add_child(card)
	_flight = _lbl("", 16, Color.WHITE)
	card.add_child(_flight)
	_status = _lbl("", 14, Color(0.5, 0.9, 0.6))
	card.add_child(_status)
	_count = _lbl("", 26, Color.WHITE)
	card.add_child(_count)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = brand.lerp(Color.WHITE, 0.2)
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.22)
	bg.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background", bg)
	card.add_child(_bar)
	_classes = _lbl("", 12, Color(0.75, 0.77, 0.8))
	card.add_child(_classes)
	card.add_child(_gap(6))
	card.add_child(_lbl("STILL TO BOARD", 12, Color(1.0, 0.75, 0.3)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	card.add_child(scroll)
	visible = false
	_refresh()


func _lbl(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible or session == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_refresh()


func _refresh() -> void:
	if session == null or session.ac == null:
		return
	var tod := fmod(WorldSim.clock / 3600.0, 24.0)
	_clock.text = "%02d:%02d" % [int(tod), int(fmod(tod * 60.0, 60.0))]
	_flight.text = "%s   %s > %s\nGate %s  -  %s" % [session.callsign, session.dep_icao, session.arr_icao, session.stand if session.stand != "" else "-",
		AircraftTypes.get_type(session.ac.type_id).name]
	var pax: Array = session.people.pax if session.people else []
	var total := pax.size()
	var aboard := 0
	var walking := []
	var away := []
	var by_cls := {}
	for p in pax:
		var cls := String(p.seat.get("cls", "economy"))
		if not by_cls.has(cls):
			by_cls[cls] = [0, 0]
		by_cls[cls][1] += 1
		match String(p.state):
			"seated", "stand", "lav", "evacuating":
				aboard += 1
				by_cls[cls][0] += 1
			"walking":
				walking.append(p)
			_:
				away.append(p)
	var ph := session.phase
	var board_state := "Boarding" if aboard < total else "Boarding complete"
	if ph in ["pushback", "taxi_out", "taxi", "takeoff", "climb", "cruise", "descent", "approach", "final", "landing_roll", "taxi_in"]:
		board_state = "Doors closed  -  " + ph.replace("_", " ").capitalize()
	elif ph in ["arrived", "deboarding"]:
		board_state = "Arrived  -  welcome to " + String(Airports.get_ap(session.arr_icao).get("city", session.arr_icao))
	_status.text = board_state
	_count.text = "%d / %d aboard" % [aboard, total]
	_bar.max_value = maxf(total, 1)
	_bar.value = aboard
	var parts := []
	for c in by_cls.keys():
		parts.append("%s %d/%d" % [String(c).capitalize(), by_cls[c][0], by_cls[c][1]])
	_classes.text = "  ".join(parts)
	for ch in _list.get_children():
		ch.queue_free()
	if walking.is_empty() and away.is_empty():
		_list.add_child(_lbl("Everyone is on board.", 13, Color(0.5, 0.9, 0.6)))
		return
	for p in walking.slice(0, 12):
		_list.add_child(_lbl("%s  %s  - on the jet bridge" % [String(p.seat.get("id", "")), String(p.get("name", "Passenger"))], 13, Color(0.85, 0.88, 0.92)))
	for p in away.slice(0, 30):
		var why := "not at the gate yet" if _rng_flag(p) else "checked in, at the gate"
		_list.add_child(_lbl("%s  %s  - %s" % [String(p.seat.get("id", "")), String(p.get("name", "Passenger")), why], 13, Color(1.0, 0.7, 0.55)))
	if away.size() > 30:
		_list.add_child(_lbl("+ %d more" % (away.size() - 30), 12, Color(0.7, 0.7, 0.72)))


func _rng_flag(p: Dictionary) -> bool:
	return U.hash_str(String(p.get("name", ""))) % 4 == 0
