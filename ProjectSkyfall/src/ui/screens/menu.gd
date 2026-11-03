extends ScreenBase
## HOME: the welcome grid. A rotating featured card, then big picture cards for the career,
## the world map (free flight), activities, the passenger journey, the hangar and the news.


func setup(params: Dictionary) -> void:
	var act := Activities.consume(params)
	if not act.is_empty():
		Game.goto("activity", {"category": act.category, "focus": act.id, "result": act})
		return
	page("", "soft")
	var grid := UIStyle.vbox(16)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(grid)
	var row1 := UIStyle.hbox(16)
	row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row1.size_flags_stretch_ratio = 1.08
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(row1)
	var row2 := UIStyle.hbox(16)
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(row2)
	var feat := Carousel.new()
	feat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feat.size_flags_stretch_ratio = 2.06
	row1.add_child(feat)
	for f in _featured():
		feat.add_card(f)
	row1.add_child(_career_card())
	row1.add_child(ImageCard.make("World Map", "Free flight: any aircraft, any airport, any time of day", "home_worldmap",
		func(): Game.goto("world_map"), {"icon_name": "globe"}))
	var done := Activities.completed_count()
	var total := Activities.SCENARIOS.size()
	row2.add_child(ImageCard.make("Activities", "Discovery flights, landing challenges, bush trips and special missions", "act_bush",
		func(): Game.goto("activities"), {"ribbon": "NEW", "progress": float(done) / float(total), "progress_text": "%d/%d" % [done, total],
			"icon_name": "trophy"}))
	row2.add_child(ImageCard.make("Passenger Journey", "Book a seat on any departure and ride along in the cabin", "home_passenger",
		func(): Game.goto("passenger"), {"icon_name": "user"}))
	row2.add_child(ImageCard.make("Hangar", "Seventeen aircraft and their liveries, up close", "home_hangar",
		func(): Game.goto("hangar"), {"icon_name": "hangar"}))
	row2.add_child(ImageCard.make("Achievements", "%d of %d unlocked: butter landings, landmarks, island hopping and more" % [Achievements.unlocked_count(), Achievements.LIST.size()],
		"act_landing", func(): Game.goto("achievements"), {"icon_name": "medal", "progress": float(Achievements.unlocked_count()) / float(Achievements.LIST.size()),
			"progress_text": "%d/%d" % [Achievements.unlocked_count(), Achievements.LIST.size()]}))
	var arts := News.latest(1)
	var headline := String(arts[0].get("headline", "")) if not arts.is_empty() else "What Calderra is talking about today"
	row2.add_child(ImageCard.make("News", headline, "home_news", func(): Game.goto("news"), {"icon_name": "news"}))


func _career_card() -> ImageCard:
	if Game.has_character():
		var p: Dictionary = Game.player
		var al := Airlines.get_al(String(p.get("airline", ""))) if String(p.get("airline", "")) != "" else {}
		return ImageCard.make("Career", "Continue as %s %s · %s" % [p.get("rank", ""), p.get("last", p.get("name", "")), al.get("name", "Unemployed")],
			PhotoStudio.pilot_id("career"), func(): Game.goto("hub"), {"icon_name": "plane"})
	return ImageCard.make("Career", "Create your pilot and choose where your story begins", PhotoStudio.pilot_id("career"),
		func(): Game.goto("create"), {"ribbon": "START HERE", "ribbon_color": UIStyle.ACCENT, "icon_name": "plane"})


func _featured() -> Array:
	var out := []
	out.append(ImageCard.make("Fly the Stratos 320", "Golden hour over the Port Calder coast. Pick an aircraft, an airport and a time of day on the world map.",
		"home_featured", func(): Game.goto("world_map", {"type": "s320", "airline": "SKF"}), {"ribbon": "FEATURED", "ribbon_color": UIStyle.ACCENT,
			"title_size": 28, "kenburns": true}))
	var daily := Activities.get_scenario(Activities.daily_id())
	if not daily.is_empty():
		var done_today := Achievements.has_daily(Activities.daily_key())
		out.append(ImageCard.make("Daily Challenge: %s" % String(daily.title), ("Done for today - come back tomorrow for a new one. " if done_today else "A new challenge every day. ") + String(daily.place),
			"scn:" + String(daily.id), func(): Game.goto("activity", {"category": String(daily.category), "focus": String(daily.id)}),
			{"ribbon": "DONE TODAY" if done_today else "DAILY", "ribbon_color": UIStyle.GREEN if done_today else UIStyle.RED, "title_size": 28, "kenburns": true}))
	out.append(ImageCard.make("Be the Controller", "Run the tower at any airport: clear arrivals to land, departures for takeoff, handle MAYDAYs - and never put two jets on one runway.",
		"ap:KJFK", func(): Game.goto("tower", {"icao": String(Game.settings.get("tower_airport", "KJFK"))}), {"ribbon": "NEW · ATC", "ribbon_color": UIStyle.GREEN, "title_size": 28, "kenburns": true}))
	out.append(ImageCard.make("Special Missions", "Fly the president with a fighter escort, glide out of a volcanic ash cloud, land in a hurricane, an earthquake or a blizzard.",
		"scn:ash_iceland", func(): Game.goto("activity", {"category": "special"}), {"ribbon": "NEW", "ribbon_color": UIStyle.RED, "title_size": 28, "kenburns": true}))
	out.append(ImageCard.make("New York, London, Paris", "The real world: 41 airports from JFK, Atlanta and Las Vegas to Heathrow, Berlin and Stockholm, with the Statue of Liberty, the Space Needle and the Eiffel Tower to fly past.",
		"scn:hudson_run", func(): Game.goto("activity", {"category": "discovery", "focus": "hudson_run"}), {"ribbon": "NEW WORLD", "ribbon_color": UIStyle.GOLD,
			"title_size": 28, "kenburns": true}))
	out.append(ImageCard.make("Landing Challenges", "Trade-wind crosswinds, fog, mountain gusts and night approaches. How good is your touchdown?",
		"scn:trade_winds", func(): Game.goto("activity", {"category": "landing"}), {"ribbon": "NEW", "title_size": 28, "kenburns": true}))
	if Game.has_character():
		var nxt: Array = HubScreen.upcoming_for(Game.player) if Game.has_character() else []
		if not nxt.is_empty():
			var f: Dictionary = nxt[0]
			out.append(ImageCard.make("Your next flight", "%s %s → %s · departs %s · %s" % [f.number, Airports.get_ap(String(f.from)).short,
				Airports.get_ap(String(f.to)).short, U.fmt_clock(float(f.dep)), AircraftTypes.get_type(String(f.type)).name],
				"ap:" + String(f.to), func(): Game.goto("briefing", {"flight": f}), {"ribbon": "CAREER", "ribbon_color": UIStyle.GREEN,
					"title_size": 28, "kenburns": true}))
	else:
		out.append(ImageCard.make("Discovery: Into the High Valley", "A sunset charter between the peaks to Highpass, Calderra's mountain airport.",
			"scn:highpass_valley", func(): Game.goto("activity", {"category": "discovery", "focus": "highpass_valley"}),
			{"ribbon": "DISCOVERY", "ribbon_color": UIStyle.ACCENT, "title_size": 28, "kenburns": true}))
	return out


## Featured cards that cross-fade every few seconds (paused while hovered), with page dots.
class Carousel extends Control:
	var cards: Array = []
	var index := 0
	var _t := 0.0
	var _dots: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_dots = Dots.new()
		_dots.carousel = self
		_dots.anchor_left = 1.0
		_dots.anchor_right = 1.0
		_dots.offset_left = -96
		_dots.offset_right = -16
		_dots.offset_top = 16
		_dots.offset_bottom = 30
		add_child(_dots)

	func add_card(c: ImageCard) -> void:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
		cards.append(c)
		c.visible = cards.size() == 1
		if _dots:
			move_child(_dots, get_child_count() - 1)
			_dots.offset_top = 46 if c.ribbon != "" else 16

	func _process(delta: float) -> void:
		if cards.size() < 2:
			return
		var hovered := false
		for c in cards:
			if c.visible and (c as Control).get_global_rect().has_point(get_global_mouse_position()):
				hovered = true
		if hovered or (cards[index] as Control).has_focus():
			return
		_t += delta
		if _t > 7.5:
			show_card((index + 1) % cards.size())

	func show_card(i: int) -> void:
		_t = 0.0
		if i == index:
			return
		var old: ImageCard = cards[index]
		var nw: ImageCard = cards[i]
		index = i
		nw.visible = true
		nw.modulate.a = 0.0
		move_child(nw, get_child_count() - 2)
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(nw, "modulate:a", 1.0, 0.7)
		tw.tween_callback(func():
			old.visible = false
			old.modulate.a = 1.0)
		_dots.queue_redraw()

	class Dots extends Control:
		var carousel: Control

		func _gui_input(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				var n: int = carousel.cards.size()
				var i := clampi(int((e.position.x - (size.x - n * 18.0)) / 18.0), 0, n - 1)
				carousel.show_card(i)

		func _draw() -> void:
			var n: int = carousel.cards.size()
			if n < 2:
				return
			for i in n:
				var c := Vector2(size.x - (n - i) * 18.0 + 9.0, size.y * 0.5)
				var on: bool = i == carousel.index
				draw_rect(Rect2(c - Vector2(7, 2), Vector2(14, 4)), Color(1, 1, 1, 0.95 if on else 0.35))
