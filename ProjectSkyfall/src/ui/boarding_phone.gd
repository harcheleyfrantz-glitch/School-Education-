class_name BoardingPhone
extends PanelContainer
## The phone in your pocket (F2). Home screen with your trip card and five apps:
##   - the operating airline's own app, in its livery colours: live boarding (aboard / total,
##     by cabin), a seat map of the whole cabin, who is still to board, passengers who never
##     turned up, no-shows taken off the flight, and the flight status once the doors close
##   - FlightTrack: a live map of this flight with the traffic around it, altitude, speed, ETA
##   - Weather: conditions, temperature and the METAR at both ends of the trip
##   - Feed: the latest posts on the social network
##   - Camera: takes a photo (same as F10) and shows your camera roll

var session: FlightSession
var page := "home"
var _t := 0.0
var _clock: Label
var _body: VBoxContainer
var _brand := Color(0.1, 0.3, 0.6)
var _accent := Color.WHITE
var _al_name := ""
var _al_code := ""
# home widgets
var _big_clock: Label
var _date: Label
var _card_status: Label
# airline app widgets
var _status: Label
var _count: Label
var _bar: ProgressBar
var _classes: Label
var _list: VBoxContainer
var _seatmap: SeatMap
var _flight: Label
# tracker widgets
var _map: TrackMap
var _track_info: Label
# weather widgets
var _wx_rows: Array = []      # [icao, WxIcon, temp Label, text Label]
# camera
var _roll: GridContainer


func setup(sess: FlightSession) -> void:
	session = sess
	_al_code = String(session.ac.airline)
	var al := Airlines.get_al(_al_code)
	var liv := Airlines.livery_colors(_al_code)
	_brand = liv.tail
	_accent = liv.logo
	if _brand.get_luminance() > 0.8:
		_brand = liv.text
	if _brand.get_luminance() > 0.8:
		_brand = Color(0.12, 0.2, 0.35)
	_al_name = String(al.name)
	# bottom right, clear of the HUD's top bar (the HUD lays out on a 1280 x 720 canvas)
	custom_minimum_size = Vector2(320, 610)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -340.0
	offset_right = -20.0
	offset_top = -650.0
	offset_bottom = -40.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.05, 0.05, 0.06)
	body.set_corner_radius_all(34)
	body.set_content_margin_all(12)
	body.border_color = Color(0.25, 0.26, 0.28)
	body.set_border_width_all(3)
	add_theme_stylebox_override("panel", body)
	var screen := VBoxContainer.new()
	screen.add_theme_constant_override("separation", 6)
	add_child(screen)
	var sb := HBoxContainer.new()
	_clock = _lbl("", 12, Color.WHITE)
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	sb.add_child(_clock)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.add_child(sp)
	var net := _lbl("5G   87%", 12, Color.WHITE)
	net.autowrap_mode = TextServer.AUTOWRAP_OFF
	sb.add_child(net)
	screen.add_child(sb)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	screen.add_child(_body)
	# home bar
	var home := Button.new()
	home.flat = true
	home.custom_minimum_size = Vector2(0, 22)
	home.focus_mode = Control.FOCUS_NONE
	home.tooltip_text = "Home"
	var bar := HomeBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(bar)
	home.pressed.connect(func(): open("home"))
	screen.add_child(home)
	visible = false
	open("home")


# ------------------------------------------------------------------ helpers
func _lbl(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _card(col: Color, radius: int = 14) -> PanelContainer:
	var c := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(10)
	c.add_theme_stylebox_override("panel", st)
	return c


func _header(title: String, sub: String, col: Color, fg: Color) -> PanelContainer:
	var head := _card(col)
	var hv := VBoxContainer.new()
	head.add_child(hv)
	hv.add_child(_lbl(title, 19, fg))
	if sub != "":
		hv.add_child(_lbl(sub, 12, Color(fg, 0.8)))
	return head


func _scroll() -> Array:
	## [ScrollContainer, VBoxContainer inside it]
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return [sc, v]


func _app_tile(title: String, col: Color, kind: String, id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var icon := AppIcon.new()
	icon.kind = kind
	icon.col = col
	icon.custom_minimum_size = Vector2(64, 64)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.tooltip_text = title
	icon.tapped.connect(func(): open(id))
	v.add_child(icon)
	var l := _lbl(title, 11, Color(0.92, 0.93, 0.95))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.custom_minimum_size = Vector2(88, 0)
	v.add_child(l)
	return v


func _flight_no() -> String:
	var al := Airlines.get_al(_al_code)
	var digits := ""
	for ch in String(session.callsign):
		if ch >= "0" and ch <= "9":
			digits += ch
	return ("%s %s" % [String(al.get("iata", "")), digits]).strip_edges() if digits != "" else String(session.callsign)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func open(id: String) -> void:
	page = id
	for c in _body.get_children():
		c.queue_free()
	_status = null
	_map = null
	_card_status = null
	_big_clock = null
	_roll = null
	_wx_rows = []
	match id:
		"home":
			_build_home()
		"airline":
			_build_airline()
		"tracker":
			_body.add_child(_header("FlightTrack", "Live  ·  %s  ·  %s to %s" % [_flight_no(), session.dep_icao, session.arr_icao],
				Color(0.95, 0.65, 0.1), Color(0.1, 0.08, 0.02)))
			_map = TrackMap.new()
			_map.custom_minimum_size = Vector2(0, 330)
			_map.phone = self
			_body.add_child(_map)
			_track_info = _lbl("", 14, Color.WHITE)
			_body.add_child(_track_info)
		"weather":
			_build_weather()
		"feed":
			_build_feed()
		"camera":
			_build_camera()
	_refresh()


# ------------------------------------------------------------------ pages
func _build_home() -> void:
	_big_clock = _lbl("", 46, Color.WHITE)
	_big_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_big_clock)
	_date = _lbl("", 13, Color(0.8, 0.82, 0.86))
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_date)
	# the trip card, in the airline's colours: tap to open its app
	var fg := _accent if _accent.get_luminance() > 0.35 else Color.WHITE
	var card := _card(_brand, 18)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			open("airline"))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	cv.add_child(_lbl(_al_name.to_upper(), 11, Color(fg, 0.85)))
	cv.add_child(_lbl("%s     %s  to  %s" % [_flight_no(), session.dep_icao, session.arr_icao], 20, fg))
	var dep_city := String(Airports.get_ap(session.dep_icao).get("city", session.dep_icao))
	var arr_city := String(Airports.get_ap(session.arr_icao).get("city", session.arr_icao))
	cv.add_child(_lbl("%s  to  %s" % [dep_city, arr_city], 12, Color(fg, 0.85)))
	_card_status = _lbl("", 13, fg)
	cv.add_child(_card_status)
	for c in cv.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(card)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_body.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_child(_app_tile(_al_name.split(" ")[0], _brand, "airline", "airline"))
	grid.add_child(_app_tile("FlightTrack", Color(0.95, 0.62, 0.1), "tracker", "tracker"))
	grid.add_child(_app_tile("Weather", Color(0.2, 0.55, 0.92), "weather", "weather"))
	grid.add_child(_app_tile("Feed", Color(0.16, 0.17, 0.2), "feed", "feed"))
	grid.add_child(_app_tile("Camera", Color(0.32, 0.34, 0.37), "camera", "camera"))
	_body.add_child(grid)


func _build_airline() -> void:
	var fg := _accent if _accent.get_luminance() > 0.35 else Color.WHITE
	_body.add_child(_header(_al_name.to_upper(), "My trips  ›  %s  ›  Boarding" % _flight_no(), _brand, fg))
	_flight = _lbl("", 13, Color.WHITE)
	_body.add_child(_flight)
	_status = _lbl("", 14, Color(0.5, 0.9, 0.6))
	_body.add_child(_status)
	_count = _lbl("", 22, Color.WHITE)
	_body.add_child(_count)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _brand.lerp(Color.WHITE, 0.3)
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.18, 0.19, 0.22)
	bg.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bg)
	_body.add_child(_bar)
	_classes = _lbl("", 11, Color(0.75, 0.77, 0.8))
	_body.add_child(_classes)
	_seatmap = SeatMap.new()
	_seatmap.custom_minimum_size = Vector2(0, 132)
	_seatmap.phone = self
	_body.add_child(_seatmap)
	var s := _scroll()
	_list = s[1]
	_body.add_child(s[0])


func _build_weather() -> void:
	_body.add_child(_header("Weather", "Your trip today", Color(0.2, 0.55, 0.92), Color.WHITE))
	for icao in [session.dep_icao, session.arr_icao]:
		var ap: Dictionary = Airports.get_ap(icao)
		var card := _card(Color(0.11, 0.16, 0.24))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var icon := WxIcon.new()
		icon.custom_minimum_size = Vector2(54, 46)
		h.add_child(icon)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.add_child(_lbl("%s  ·  %s" % [String(ap.get("city", icao)), icao], 13, Color(0.8, 0.86, 0.95)))
		var temp := _lbl("", 28, Color.WHITE)
		tv.add_child(temp)
		h.add_child(tv)
		v.add_child(h)
		var txt := _lbl("", 12, Color(0.9, 0.92, 0.95))
		v.add_child(txt)
		_body.add_child(card)
		_wx_rows.append([icao, icon, temp, txt])


func _build_feed() -> void:
	_body.add_child(_header("Feed", "What everyone is talking about", Color(0.16, 0.17, 0.2), Color.WHITE))
	var s := _scroll()
	var v: VBoxContainer = s[1]
	_body.add_child(s[0])
	var posts: Array = News.feed(16)
	if posts.is_empty():
		v.add_child(_lbl("Nothing new yet. Check back after your flight.", 13, Color(0.7, 0.7, 0.72)))
	for p in posts:
		var card := _card(Color(0.1, 0.1, 0.12), 10)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 2)
		card.add_child(pv)
		var ago := maxf(WorldSim.clock - float(p.get("t", WorldSim.clock)), 0.0) / 60.0
		var when := "now" if ago < 1.0 else ("%dm" % int(ago) if ago < 60.0 else ("%dh" % int(ago / 60.0) if ago < 1440.0 else "%dd" % int(ago / 1440.0)))
		var who := String(p.get("name", ""))
		if bool(p.get("verified", false)):
			who += " (verified)"
		pv.add_child(_lbl("%s  %s  ·  %s" % [who, String(p.get("handle", "")), when], 11, Color(0.55, 0.75, 1.0)))
		pv.add_child(_lbl(String(p.get("text", "")), 13, Color.WHITE))
		pv.add_child(_lbl("%s replies   %s reposts   %s likes" % [_short(int(p.get("replies", 0))), _short(int(p.get("reposts", 0))), _short(int(p.get("likes", 0)))],
			11, Color(0.6, 0.6, 0.64)))
		v.add_child(card)


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)


func _build_camera() -> void:
	_body.add_child(_header("Camera", "Photos are saved to your screenshots folder", Color(0.32, 0.34, 0.37), Color.WHITE))
	var shoot := Button.new()
	shoot.text = "Take photo"
	shoot.custom_minimum_size = Vector2(0, 58)
	shoot.add_theme_font_size_override("font_size", 20)
	shoot.focus_mode = Control.FOCUS_NONE
	shoot.pressed.connect(_take_photo)
	_body.add_child(shoot)
	_body.add_child(_lbl("Tip: F10 takes a photo at any time, without the phone in the way.", 11, Color(0.7, 0.7, 0.72)))
	_body.add_child(_lbl("CAMERA ROLL", 11, Color(0.75, 0.77, 0.8)))
	_roll = GridContainer.new()
	_roll.columns = 2
	_roll.add_theme_constant_override("h_separation", 6)
	_roll.add_theme_constant_override("v_separation", 6)
	_body.add_child(_roll)
	_fill_roll()


func _fill_roll() -> void:
	if _roll == null:
		return
	for c in _roll.get_children():
		c.queue_free()
	var files := []
	var d := DirAccess.open("user://screenshots")
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				files.append(f)
	files.sort()
	files.reverse()
	if files.is_empty():
		_roll.add_child(_lbl("No photos yet.", 12, Color(0.6, 0.6, 0.64)))
		return
	for f in files.slice(0, 4):
		var img := Image.load_from_file("user://screenshots/" + String(f))
		if img == null or img.is_empty():
			continue
		img.resize(140, maxi(int(140.0 * img.get_height() / maxf(img.get_width(), 1.0)), 1), Image.INTERPOLATE_BILINEAR)
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.custom_minimum_size = Vector2(140, 79)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_roll.add_child(tr)


func _take_photo() -> void:
	# the session hides the whole HUD (and this phone with it) for the shot
	await session._photo()
	if page == "camera":
		_fill_roll()


func _process(delta: float) -> void:
	if not visible or session == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_refresh()


# ------------------------------------------------------------------ refresh
func _refresh() -> void:
	if session == null or session.ac == null:
		return
	_clock.text = U.fmt_clock(WorldSim.clock)
	match page:
		"home":
			_refresh_home()
		"airline":
			_refresh_airline()
		"tracker":
			_refresh_tracker()
		"weather":
			_refresh_weather()


func _boarding_counts() -> Dictionary:
	var cp: CabinPeople = session.people
	var out := {"total": 0, "aboard": 0, "walking": [], "away": [], "noshow": [], "cls": {}}
	if cp == null:
		return out
	out.total = cp.pax.size()
	for p in cp.pax:
		var cls := String(p.seat.get("cls", "economy"))
		if not out.cls.has(cls):
			out.cls[cls] = [0, 0]
		out.cls[cls][1] += 1
		var st := String(p.state)
		if st == "walking":
			out.walking.append(p)
		elif st == "away":
			if bool(p.get("noshow", false)):
				out.noshow.append(p)
			else:
				out.away.append(p)
		else:
			out.aboard += 1
			out.cls[cls][0] += 1
	return out


func _status_text(bc: Dictionary) -> String:
	var ph := String(session.phase)
	var arr_city := String(Airports.get_ap(session.arr_icao).get("city", session.arr_icao))
	const AWAY := {"pushback": "Pushing back", "taxi_out": "Taxiing out", "taxi": "Taxiing", "lineup": "Lining up",
		"takeoff_roll": "Taking off", "takeoff": "Taking off", "initial_climb": "Climbing", "climb": "Climbing",
		"cruise": "Cruising", "descent": "Descending", "approach": "On approach", "final": "On final approach", "landing": "Landing"}
	if AWAY.has(ph):
		return "Departed  ·  %s" % String(AWAY[ph])
	if ph in ["landing_roll", "rollout", "landed", "taxi_in"]:
		return "Landed in %s  ·  taxiing to the gate" % arr_city
	if ph in ["arrived", "deboarding"]:
		return "Arrived  ·  welcome to %s" % arr_city
	if session.pushback_active:
		return "Departed  ·  Pushing back"
	var cp: CabinPeople = session.people
	if cp and cp.holding_door():
		return "Final call  ·  holding the door"
	if int(bc.aboard) >= int(bc.total):
		return "Boarding complete  ·  doors closing"
	if (bc.walking as Array).is_empty() and (bc.away as Array).is_empty() and not (bc.noshow as Array).is_empty():
		var n := (bc.noshow as Array).size()
		return "Final call  ·  %d passenger%s missing" % [n, "" if n == 1 else "s"]
	return "Boarding  ·  gate %s" % (session.stand if session.stand != "" else "open")


func _refresh_home() -> void:
	if _big_clock == null:
		return
	_big_clock.text = U.fmt_clock(WorldSim.clock)
	var dt := U.clock_to_date(WorldSim.clock)
	_date.text = "%s %d %s" % [U.DAY_NAMES[int(dt.weekday)], int(dt.day), U.MONTH_NAMES[int(dt.month) - 1]]
	var bc := _boarding_counts()
	_card_status.text = "%s\n%d of %d aboard" % [_status_text(bc), int(bc.aboard), int(bc.total)]


func _refresh_airline() -> void:
	if _status == null:
		return
	_flight.text = "%s   %s to %s   ·   Gate %s\n%s  ·  %s" % [_flight_no(), session.dep_icao, session.arr_icao, session.stand if session.stand != "" else "-",
		AircraftTypes.get_type(session.ac.type_id).name, String(session.ac.reg)]
	var bc := _boarding_counts()
	var total := int(bc.total)
	var aboard := int(bc.aboard)
	var walking: Array = bc.walking
	var away: Array = bc.away
	var noshow: Array = bc.noshow
	_status.text = _status_text(bc)
	_count.text = "%d / %d aboard" % [aboard, total]
	_bar.max_value = maxf(total, 1)
	_bar.value = aboard
	var parts := []
	for c in ["first", "business", "premium", "economy", "vip"]:
		if bc.cls.has(c):
			parts.append("%s %d/%d" % [String(c).capitalize(), bc.cls[c][0], bc.cls[c][1]])
	_classes.text = "   ".join(parts)
	_seatmap.queue_redraw()
	for ch in _list.get_children():
		ch.queue_free()
	var cp: CabinPeople = session.people
	if cp and not cp.offloaded.is_empty():
		_list.add_child(_lbl("DID NOT TRAVEL  ·  bags offloaded", 11, Color(1.0, 0.45, 0.4)))
		for nm in cp.offloaded:
			_list.add_child(_lbl("   " + String(nm), 13, Color(1.0, 0.65, 0.6)))
	if walking.is_empty() and away.is_empty() and noshow.is_empty():
		_list.add_child(_lbl("Everyone is on board.", 13, Color(0.5, 0.9, 0.6)))
		return
	if not noshow.is_empty():
		_list.add_child(_lbl("NOT AT THE GATE", 11, Color(1.0, 0.45, 0.4)))
		for p in noshow:
			_list.add_child(_lbl("%s  %s" % [String(p.seat.get("id", "")), String(p.get("name", "Passenger"))], 13, Color(1.0, 0.55, 0.5)))
	if not walking.is_empty():
		_list.add_child(_lbl("BOARDING NOW", 11, Color(1.0, 0.82, 0.3)))
		for p in walking.slice(0, 10):
			_list.add_child(_lbl("%s  %s%s" % [String(p.seat.get("id", "")), String(p.get("name", "Passenger")),
				"  ·  running!" if bool(p.get("running", false)) else ""], 13, Color(0.9, 0.9, 0.8)))
		if walking.size() > 10:
			_list.add_child(_lbl("+ %d more" % (walking.size() - 10), 12, Color(0.7, 0.7, 0.72)))
	if not away.is_empty():
		_list.add_child(_lbl("CHECKED IN  ·  STILL AT THE GATE", 11, Color(0.75, 0.77, 0.8)))
		for p in away.slice(0, 24):
			_list.add_child(_lbl("%s  %s" % [String(p.seat.get("id", "")), String(p.get("name", "Passenger"))], 13, Color(0.85, 0.86, 0.9)))
		if away.size() > 24:
			_list.add_child(_lbl("+ %d more" % (away.size() - 24), 12, Color(0.7, 0.7, 0.72)))


func _refresh_tracker() -> void:
	if _map == null:
		return
	_map.queue_redraw()
	var ac: Aircraft = session.ac
	var ap: Dictionary = Airports.get_ap(session.arr_icao)
	var d_m := Vector2(ac.world_x() - float(ap.x), ac.world_z() - float(ap.z)).length()
	var v: Vector3 = ac.fdm.vel
	var gs_ms := Vector2(v.x, v.z).length()
	var alt_ft := ac.fdm.pos.y / U.FT
	var eta_min := d_m / maxf(gs_ms, 120.0) / 60.0
	_track_info.text = "ALT %s ft     GS %d kt     HDG %03d\n%.0f nm to %s  ·  ETA %s" % [_thousands(int(round(alt_ft / 10.0) * 10.0)), int(gs_ms / U.KT),
		int(ac.fdm.heading_deg()) % 360, d_m / 1852.0, String(ap.get("city", session.arr_icao)), U.fmt_clock(WorldSim.clock + eta_min * 60.0) if gs_ms > 30.0 else "--:--"]


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _refresh_weather() -> void:
	for row in _wx_rows:
		var ap: Dictionary = Airports.get_ap(String(row[0]))
		var w := WeatherModel.sample(float(ap.x), float(ap.z), WorldSim.clock)
		var icon: WxIcon = row[1]
		icon.wx = w
		var dt := U.clock_to_date(WorldSim.clock)
		icon.night = float(dt.hours_f) < 6.0 or float(dt.hours_f) > 19.5
		icon.queue_redraw()
		(row[2] as Label).text = "%d°C" % int(round(float(w.temp_c)))
		(row[3] as Label).text = "%s\n%s" % [WeatherModel.describe(w), WeatherModel.metar(String(row[0]), WorldSim.clock)]


# ------------------------------------------------------------------ shapes
static func plane_poly(c: Vector2, s: float, hdg_rad: float) -> PackedVector2Array:
	## Airliner silhouette seen from above, nose along the heading (0 = up the screen).
	var f := Vector2(sin(hdg_rad), -cos(hdg_rad))
	var r := Vector2(-f.y, f.x)
	var half := [Vector2(0.0, 1.0), Vector2(0.09, 0.84), Vector2(0.1, 0.26), Vector2(0.95, -0.12), Vector2(0.95, -0.26), Vector2(0.1, -0.1),
		Vector2(0.08, -0.62), Vector2(0.38, -0.84), Vector2(0.38, -0.96), Vector2(0.0, -0.88)]
	var pts := PackedVector2Array()
	for p in half:
		pts.append(c + (r * p.x + f * p.y) * s)
	for i in range(half.size() - 2, 0, -1):
		var q: Vector2 = half[i]
		pts.append(c + (r * -q.x + f * q.y) * s)
	return pts


class HomeBar extends Control:
	func _draw() -> void:
		var w := 110.0
		draw_rect(Rect2(Vector2((size.x - w) * 0.5, size.y * 0.5 - 2.5), Vector2(w, 5)), Color(0.85, 0.86, 0.9))


class AppIcon extends Control:
	## A rounded app icon with a simple drawn glyph.
	signal tapped
	var kind := "airline"
	var col := Color.GRAY
	var _box: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tapped.emit()
			accept_event()

	func _draw() -> void:
		if _box == null:
			_box = StyleBoxFlat.new()
			_box.set_corner_radius_all(16)
			_box.bg_color = col
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		var c := size * 0.5
		var k := minf(size.x, size.y) / 64.0
		var white := Color(1, 1, 1)
		match kind:
			"airline":
				draw_colored_polygon(BoardingPhone.plane_poly(c, 22.0 * k, deg_to_rad(45.0)), white)
			"tracker":
				for rr in [8.0, 15.0, 22.0]:
					draw_arc(c, rr * k, 0.0, TAU, 40, Color(0.12, 0.08, 0.02, 0.75), 2.0 * k)
				draw_line(c, c + Vector2(cos(-0.8), sin(-0.8)) * 22.0 * k, Color(0.12, 0.08, 0.02), 2.5 * k)
				draw_colored_polygon(BoardingPhone.plane_poly(c + Vector2(-9, 8) * k, 7.0 * k, deg_to_rad(40.0)), white)
				draw_circle(c + Vector2(10, -11) * k, 3.0 * k, white)
			"weather":
				draw_circle(c + Vector2(6, -7) * k, 11.0 * k, Color(1.0, 0.85, 0.25))
				var cc := Color(0.97, 0.98, 1.0)
				draw_circle(c + Vector2(-9, 6) * k, 8.0 * k, cc)
				draw_circle(c + Vector2(1, 1) * k, 10.0 * k, cc)
				draw_circle(c + Vector2(11, 7) * k, 7.0 * k, cc)
				draw_rect(Rect2(c + Vector2(-9, 7) * k, Vector2(20, 7) * k), cc)
			"feed":
				var b := Rect2(c + Vector2(-19, -15) * k, Vector2(38, 26) * k)
				var sb := StyleBoxFlat.new()
				sb.bg_color = white
				sb.set_corner_radius_all(int(8 * k))
				draw_style_box(sb, b)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 10) * k, c + Vector2(-2, 10) * k, c + Vector2(-13, 19) * k]), white)
				for i in 3:
					draw_circle(c + Vector2(-9 + i * 9, -2) * k, 2.6 * k, col)
			"camera":
				var b2 := Rect2(c + Vector2(-21, -12) * k, Vector2(42, 28) * k)
				var sb2 := StyleBoxFlat.new()
				sb2.bg_color = Color(0.92, 0.93, 0.95)
				sb2.set_corner_radius_all(int(6 * k))
				draw_style_box(sb2, b2)
				draw_rect(Rect2(c + Vector2(-8, -17) * k, Vector2(14, 6) * k), Color(0.92, 0.93, 0.95))
				draw_circle(c + Vector2(0, 2) * k, 10.0 * k, Color(0.15, 0.16, 0.18))
				draw_circle(c + Vector2(0, 2) * k, 6.5 * k, Color(0.3, 0.45, 0.7))
				draw_circle(c + Vector2(-2, 0) * k, 2.0 * k, Color(1, 1, 1, 0.8))
				draw_circle(c + Vector2(14, -7) * k, 2.2 * k, Color(1.0, 0.75, 0.2))


class WxIcon extends Control:
	## Sun or moon, cloud, rain, snow or lightning for a weather sample.
	var wx: Dictionary = {}
	var night := false

	func _draw() -> void:
		if wx.is_empty():
			return
		var c := size * 0.5
		var k := minf(size.x / 54.0, size.y / 46.0)
		var cover := float(wx.get("cover", 0.0))
		var precip := String(wx.get("precip", "none"))
		if cover < 0.9:
			var sc := c + Vector2(-8, -6) * k
			if night:
				draw_circle(sc, 11.0 * k, Color(0.92, 0.92, 0.85))
				draw_circle(sc + Vector2(5, -3) * k, 9.5 * k, Color(0.11, 0.16, 0.24))
			else:
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(sc + Vector2(cos(a), sin(a)) * 13.0 * k, sc + Vector2(cos(a), sin(a)) * 17.0 * k, Color(1.0, 0.82, 0.25), 2.0 * k)
				draw_circle(sc, 10.0 * k, Color(1.0, 0.82, 0.25))
		if cover > 0.15:
			var grey := 1.0 - clampf((cover - 0.5) * 0.6, 0.0, 0.3) - (0.25 if precip in ["rain", "thunderstorm"] else 0.0)
			var cc := Color(grey, grey, grey + 0.03)
			var o := c + Vector2(4, 4) * k
			draw_circle(o + Vector2(-11, 2) * k, 8.0 * k, cc)
			draw_circle(o + Vector2(-1, -4) * k, 11.0 * k, cc)
			draw_circle(o + Vector2(11, 2) * k, 8.0 * k, cc)
			draw_rect(Rect2(o + Vector2(-11, 2) * k, Vector2(22, 8) * k), cc)
			var base := o + Vector2(0, 13) * k
			match precip:
				"rain":
					for i in 4:
						var p := base + Vector2(-9 + i * 6, 0) * k
						draw_line(p, p + Vector2(-2, 6) * k, Color(0.45, 0.7, 1.0), 2.0 * k)
				"snow":
					for i in 4:
						draw_circle(base + Vector2(-9 + i * 6, 3 + (i % 2) * 3) * k, 1.8 * k, Color.WHITE)
				"thunderstorm":
					draw_colored_polygon(PackedVector2Array([base + Vector2(-1, -1) * k, base + Vector2(5, -1) * k, base + Vector2(1, 5) * k,
						base + Vector2(5, 5) * k, base + Vector2(-4, 15) * k, base + Vector2(-1, 7) * k, base + Vector2(-5, 7) * k]), Color(1.0, 0.85, 0.2))


class SeatMap extends Control:
	## The whole cabin from above, nose on the left: every seat, coloured by who sits in it.
	const COLS := {"aboard": Color(0.3, 0.85, 0.45), "bridge": Color(1.0, 0.82, 0.2), "gate": Color(0.5, 0.52, 0.57),
		"noshow": Color(0.95, 0.3, 0.25), "you": Color(0.35, 0.65, 1.0), "empty": Color(0.22, 0.23, 0.27)}
	var phone: BoardingPhone
	var _seats: Array = []
	var _lo := Vector2.ZERO          # (z, x) of the cabin's front-left corner
	var _hi := Vector2.ONE
	var _cell := Vector2(0.6, 0.45)  # one seat in metres (along, across)
	var _body: StyleBoxFlat

	func _prep(cp: CabinPeople) -> void:
		_seats = cp.lay.get("seats", [])
		if _seats.is_empty():
			return
		var zs := []
		var w := 0.45
		_lo = Vector2(INF, INF)
		_hi = Vector2(-INF, -INF)
		for s in _seats:
			var p: Vector3 = s.pos
			_lo = Vector2(minf(_lo.x, p.z), minf(_lo.y, p.x))
			_hi = Vector2(maxf(_hi.x, p.z), maxf(_hi.y, p.x))
			w = float(s.get("width", w))
			var zr := snappedf(p.z, 0.05)
			if not zr in zs:
				zs.append(zr)
		zs.sort()
		var gaps := []
		for i in range(1, zs.size()):
			if float(zs[i]) - float(zs[i - 1]) > 0.3:
				gaps.append(float(zs[i]) - float(zs[i - 1]))
		gaps.sort()
		var pitch: float = gaps[int(gaps.size() / 2.0)] if not gaps.is_empty() else 0.8
		_cell = Vector2(pitch * 0.72, w * 0.8)
		_lo -= Vector2(pitch * 0.5, w * 0.5)
		_hi += Vector2(pitch * 0.5, w * 0.5)

	func _draw() -> void:
		if phone == null or phone.session == null or phone.session.people == null:
			return
		var cp: CabinPeople = phone.session.people
		if _seats.is_empty():
			_prep(cp)
		if _seats.is_empty():
			return
		var font := ThemeDB.fallback_font
		var leg_h := 18.0
		var area := Rect2(Vector2(24, 10), Vector2(size.x - 34, size.y - leg_h - 20))
		var sx := area.size.x / maxf(_hi.x - _lo.x, 0.5)
		var sy := area.size.y / maxf(_hi.y - _lo.y, 0.5)
		# fuselage: rounded nose on the left, tapering tail on the right
		if _body == null:
			_body = StyleBoxFlat.new()
			_body.bg_color = Color(0.13, 0.14, 0.17)
			_body.border_color = Color(0.32, 0.34, 0.38)
			_body.set_border_width_all(1)
		var fr := Rect2(area.position - Vector2(18, 7), area.size + Vector2(26, 14))
		_body.corner_radius_top_left = int(fr.size.y * 0.5)
		_body.corner_radius_bottom_left = int(fr.size.y * 0.5)
		_body.corner_radius_top_right = int(fr.size.y * 0.22)
		_body.corner_radius_bottom_right = int(fr.size.y * 0.22)
		draw_style_box(_body, fr)
		# cockpit windows
		draw_line(fr.position + Vector2(9, fr.size.y * 0.36), fr.position + Vector2(9, fr.size.y * 0.64), Color(0.4, 0.55, 0.75), 3.0)
		var who := {}
		var mine := String(phone.session.pax_seat) if phone.session.mode == "passenger" else ""
		for p in cp.pax:
			who[String(p.seat.id)] = p
		var cell := Vector2(maxf(_cell.x * sx, 1.5), maxf(_cell.y * sy, 1.5))
		for s in _seats:
			var sp: Vector3 = s.pos
			var col: Color = COLS.empty
			if String(s.id) == mine:
				col = COLS.you
			elif who.has(String(s.id)):
				var p: Dictionary = who[String(s.id)]
				match String(p.state):
					"walking":
						col = COLS.bridge
					"away":
						col = COLS.noshow if bool(p.get("noshow", false)) else COLS.gate
					"player":
						col = COLS.you
					_:
						col = COLS.aboard
			var q := area.position + Vector2((sp.z - _lo.x) * sx, (sp.x - _lo.y) * sy)
			draw_rect(Rect2(q - cell * 0.5, cell), col)
		# legend
		var x := 4.0
		var items := [["aboard", "Aboard"], ["bridge", "Boarding"], ["gate", "At gate"], ["noshow", "No-show"]]
		if mine != "":
			items.append(["you", "You"])
		for it in items:
			draw_rect(Rect2(x, size.y - 13, 9, 9), COLS[it[0]])
			draw_string(font, Vector2(x + 12, size.y - 4), String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.81, 0.85))
			x += 12.0 + font.get_string_size(String(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 9.0


class TrackMap extends Control:
	## Live map: the route, your aircraft and the traffic around it, with a scale bar.
	var phone: BoardingPhone

	func _draw() -> void:
		if phone == null or phone.session == null:
			return
		var s: FlightSession = phone.session
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.13))
		var a: Dictionary = Airports.get_ap(s.dep_icao)
		var b: Dictionary = Airports.get_ap(s.arr_icao)
		var pa := Vector2(float(a.x), float(a.z))
		var pb := Vector2(float(b.x), float(b.z))
		var me := Vector2(s.ac.world_x(), s.ac.world_z())
		var lo := Vector2(minf(minf(pa.x, pb.x), me.x), minf(minf(pa.y, pb.y), me.y))
		var hi := Vector2(maxf(maxf(pa.x, pb.x), me.x), maxf(maxf(pa.y, pb.y), me.y))
		var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 30000.0) * 1.3
		var c := (lo + hi) * 0.5
		var k := minf(size.x, size.y) / span
		var to := func(p: Vector2) -> Vector2: return size * 0.5 + (p - c) * k
		# graticule
		for i in range(1, 8):
			draw_line(Vector2(size.x * i / 8.0, 0), Vector2(size.x * i / 8.0, size.y), Color(1, 1, 1, 0.045))
			draw_line(Vector2(0, size.y * i / 8.0), Vector2(size.x, size.y * i / 8.0), Color(1, 1, 1, 0.045))
		# planned route (dashed) and the track flown so far
		var A: Vector2 = to.call(pa)
		var B: Vector2 = to.call(pb)
		draw_dashed_line(A, B, Color(0.95, 0.65, 0.1, 0.55), 2.0, 8.0)
		var M: Vector2 = to.call(me)
		draw_line(A, M, Color(0.95, 0.65, 0.1), 3.0)
		for ap in [[A, String(s.dep_icao)], [B, String(s.arr_icao)]]:
			var q: Vector2 = ap[0]
			draw_circle(q, 5.0, Color.WHITE)
			draw_circle(q, 3.0, Color(0.06, 0.09, 0.13))
			draw_string(font, q + Vector2(8, -7), String(ap[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		# other traffic
		var box := Rect2(Vector2.ZERO, size)
		if s.traffic:
			for t in s.traffic.airborne:
				if not (t is Dictionary) or not t.has("x"):
					continue
				var q2: Vector2 = to.call(Vector2(float(t.x), float(t.z)))
				if box.has_point(q2):
					draw_colored_polygon(BoardingPhone.plane_poly(q2, 5.0, deg_to_rad(float(t.get("hdg", 0.0)))), Color(0.6, 0.8, 1.0, 0.85))
		# you
		draw_circle(M, 13.0, Color(1.0, 0.85, 0.2, 0.15))
		draw_colored_polygon(BoardingPhone.plane_poly(M, 11.0, deg_to_rad(s.ac.fdm.heading_deg())), Color(1.0, 0.85, 0.2))
		# north arrow and scale bar
		draw_string(font, Vector2(size.x - 18, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
		draw_line(Vector2(size.x - 14, 34), Vector2(size.x - 14, 22), Color(1, 1, 1, 0.7), 2.0)
		var nm_px := 1852.0 * k
		var nice := 1.0
		for step in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]:
			if step * nm_px <= size.x * 0.3:
				nice = step
		var y := size.y - 12.0
		draw_line(Vector2(10, y), Vector2(10 + nice * nm_px, y), Color(1, 1, 1, 0.8), 2.0)
		draw_line(Vector2(10, y - 4), Vector2(10, y + 4), Color(1, 1, 1, 0.8), 2.0)
		draw_line(Vector2(10 + nice * nm_px, y - 4), Vector2(10 + nice * nm_px, y + 4), Color(1, 1, 1, 0.8), 2.0)
		draw_string(font, Vector2(14, y - 6), "%d nm" % int(nice), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
