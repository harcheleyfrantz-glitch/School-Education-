extends ScreenBase
## News hub: headlines from every outlet; articles with their video playing inline and a
## comment section hundreds deep; the video library (news packages, investigation reports
## and replays of your own landings); the social feed; and the accident record.

var _tab := "headlines"
var _body: VBoxContainer
var _back := "menu"
var _player: BroadcastPlayer = null
var _3d_off := false
var _tab_btns := {}


func setup(params: Dictionary) -> void:
	_back = "hub" if Game.has_character() else "menu"
	frame("World news", U.fmt_datetime(WorldSim.clock), _back, 0.74)
	var tabs := UIStyle.hbox(8)
	for t in [["Headlines", "headlines"], ["Videos", "videos"], ["Social", "social"], ["Accidents", "accidents"]]:
		var key: String = t[1]
		var b := UIStyle.button(t[0], func():
			_tab = key
			_render(), 120)
		_tab_btns[key] = b
		tabs.add_child(b)
	content.add_child(tabs)
	_body = UIStyle.vbox(12)
	content.add_child(_body)
	_tab = String(params.get("tab", _tab))
	if params.has("article"):
		var a := News.article(String(params.article))
		if not a.is_empty():
			_show_article(a, bool(params.get("play", false)))
			return
	_render()


func _exit_tree() -> void:
	_stop_player()


func _clear() -> void:
	_stop_player()
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func _paint_tabs() -> void:
	for k in _tab_btns:
		(_tab_btns[k] as Button).modulate = Color.WHITE if k == _tab else Color(1, 1, 1, 0.55)


func _render() -> void:
	_clear()
	_paint_tabs()
	match _tab:
		"headlines":
			var arts := News.latest(40)
			if arts.is_empty():
				_body.add_child(UIStyle.label("A quiet day. Nothing in the news yet.", 15, UIStyle.DIM))
			var lead := {}
			for a in arts:
				if not (a.get("video", {}) as Dictionary).is_empty() and int(a.get("importance", 1)) >= 2:
					lead = a
					break
			if not lead.is_empty():
				var card := _video_card(lead, 300.0, 24)
				_body.add_child(card)
			for a in arts:
				if a != lead:
					_body.add_child(_headline_row(a))
		"videos":
			_videos()
		"social":
			_social()
		"accidents":
			_accidents()


# ================================================================== headlines
func _headline_row(a: Dictionary) -> Control:
	var o: Dictionary = News.OUTLETS.get(String(a.outlet), {"name": a.outlet, "color": "888888"})
	var p := PanelContainer.new()
	var col := Color.html(String(o.color))
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(0.06, 0.09, 0.13, 0.92), 10, Color(col, 0.9), 0, 12))
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := UIStyle.hbox(10)
	p.add_child(h)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(5, 0)
	h.add_child(bar)
	var v := UIStyle.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var has_video := not (a.get("video", {}) as Dictionary).is_empty()
	var meta := "%s · %s%s" % [o.name, U.fmt_ago(WorldSim.clock, float(a.t)), "   ▶ VIDEO" if has_video else ""]
	v.add_child(UIStyle.label(meta, 12, col.lightened(0.3)))
	var hl := UIStyle.label(String(a.headline), 17 if int(a.importance) >= 2 else 15, UIStyle.TEXT, int(a.importance) >= 2)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hl)
	var n := NewsComments.count(a)
	if n > 0:
		v.add_child(UIStyle.label("%s comments" % NewsComments.short(n), 12, UIStyle.DIM))
	h.add_child(v)
	p.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_show_article(a))
	return p


## Shot id for a story's picture: the aircraft and airline involved.
func _shot_for(a: Dictionary) -> String:
	var v: Dictionary = a.get("video", {})
	var inc := News.incident(String(a.get("incident", v.get("incident", ""))))
	var t := String(inc.get("type", v.get("type_id", "")))
	var al := String(inc.get("airline", v.get("airline", "")))
	if t != "" and al != "":
		return "type:%s:%s" % [t, al]
	return "home_news"


func _video_card(a: Dictionary, h: float, title_size: int = 17) -> Control:
	var o: Dictionary = News.OUTLETS.get(String(a.outlet), {"name": a.outlet})
	var kind := String(a.get("kind", ""))
	var tags: Array = a.get("tags", [])
	var ribbon := "BREAKING" if kind == "breaking" else ("REPORT" if tags.has("final report") or tags.has("investigation") else "")
	var head := String(a.headline)
	if head.length() > 74:
		head = head.substr(0, 72) + "…"
	var sub := "%s · %s views · %s comments · %s" % [o.name, NewsComments.short(NewsComments.views(a)), NewsComments.short(NewsComments.count(a)),
		U.fmt_ago(WorldSim.clock, float(a.t))]
	var c := ImageCard.make(head, sub, _shot_for(a), func(): _show_article(a, true),
		{"ribbon": ribbon, "ribbon_color": UIStyle.RED, "icon_name": "news", "title_size": title_size})
	c.custom_minimum_size = Vector2(0, h)
	return c


# ================================================================== article + video
func _show_article(a: Dictionary, autoplay: bool = false) -> void:
	_clear()
	var o: Dictionary = News.OUTLETS.get(String(a.outlet), {"name": a.outlet, "color": "888888"})
	var back := UIStyle.button("‹ All news", func(): _render(), 130)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(back)
	_body.add_child(UIStyle.label("%s · %s" % [o.name, U.fmt_datetime(float(a.t))], 13, Color.html(String(o.color)).lightened(0.35)))
	var hl := UIStyle.label(String(a.headline), 26, UIStyle.TEXT, true)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hl)
	var video: Dictionary = a.get("video", {})
	if not video.is_empty():
		var prog := NewsScript.build(video, a)
		if not prog.is_empty():
			_body.add_child(UIStyle.label("▶ %s · %s · %s views" % [String(prog.get("title", "Video")), BroadcastPlayer._mmss(float(prog.get("duration", 0.0))),
				U.fmt_int(NewsComments.views(a))], 13, UIStyle.DIM))
			_embed(prog, autoplay)
		else:
			_body.add_child(UIStyle.button("▶  Watch video", func(): Game.goto("replay", {"video": video, "article": String(a.id), "back": "news"}), 220, UIStyle.ACCENT))
	var lede := UIStyle.label(String(a.lede), 17, UIStyle.TEXT)
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(lede)
	for para in a.get("body", []):
		var l := UIStyle.label(String(para), 15, UIStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)
	if String(a.get("story", "")) != "":
		var related := News.feed(8, String(a.story))
		if not related.is_empty():
			_body.add_child(ScreenBase.section("Reactions"))
			for p in related:
				_body.add_child(_post_card(p))
	_body.add_child(UIStyle.rule())
	var cs := CommentSection.new()
	_body.add_child(cs)
	cs.setup(a)


func _embed(prog: Dictionary, autoplay: bool) -> void:
	var w := minf(get_viewport_rect().size.x * 0.74 - MARGIN * 2.0 - 40.0, 1100.0)
	_player = BroadcastPlayer.new()
	_player.custom_minimum_size = Vector2(w, w * 9.0 / 16.0)
	_player.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(_player)
	_player.open(prog, {"autoplay": autoplay, "closable": false})
	# the menu backdrop does not need drawing while a video plays over it
	var vp := get_viewport()
	if vp and not _3d_off:
		_3d_off = true
		vp.disable_3d = true


func _stop_player() -> void:
	if _player and is_instance_valid(_player):
		_player.close()
		if _player.get_parent():
			_player.get_parent().remove_child(_player)
		_player.queue_free()
	_player = null
	if _3d_off:
		_3d_off = false
		var vp := get_viewport()
		if vp:
			vp.disable_3d = false


func _play_view(prog: Dictionary, title: String, sub: String, back_tab: String) -> void:
	_clear()
	_body.add_child(UIStyle.button("‹ Back", func():
		_tab = back_tab
		_render(), 110))
	var hl := UIStyle.label(title, 24, UIStyle.TEXT, true)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hl)
	_body.add_child(UIStyle.label(sub, 13, UIStyle.DIM))
	_embed(prog, true)


# ================================================================== video library
func _videos() -> void:
	var arts := []
	for a in News.latest(80):
		if not (a.get("video", {}) as Dictionary).is_empty():
			arts.append(a)
	_body.add_child(ScreenBase.section("News videos"))
	if arts.is_empty():
		_body.add_child(UIStyle.label("No video reports yet.", 14, UIStyle.DIM))
	var grid := GridContainer.new()
	grid.columns = 3 if get_viewport_rect().size.x > 1100.0 else 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(grid)
	for a in arts.slice(0, 24):
		grid.add_child(_video_card(a, 200.0, 15))
	_body.add_child(ScreenBase.section("Your flights"))
	if News.replays.is_empty():
		_body.add_child(UIStyle.label("Fly a trip and its approach and landing will be kept here to watch again.", 14, UIStyle.DIM))
		return
	var g2 := GridContainer.new()
	g2.columns = grid.columns
	g2.add_theme_constant_override("h_separation", 14)
	g2.add_theme_constant_override("v_separation", 14)
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(g2)
	for i in range(News.replays.size() - 1, -1, -1):
		var rp: Dictionary = News.replays[i]
		var title := "%s  %s → %s" % [String(rp.get("callsign", "")), Airports.get_ap(String(rp.get("dep", ""))).get("short", ""),
			Airports.get_ap(String(rp.get("arr", ""))).get("short", "")]
		var sub := "%s · %s · %s" % [String(rp.get("label", "Landing")), AircraftTypes.get_type(String(rp.get("type", "s320"))).name, U.fmt_ago(WorldSim.clock, float(rp.get("t", WorldSim.clock)))]
		var rid := String(rp.get("id", ""))
		var c := ImageCard.make(title, sub, "type:%s:%s" % [String(rp.get("type", "s320")), String(rp.get("airline", "SKF"))], func():
			var prog := NewsScript.build({"type": "replay", "replay": rid})
			if not prog.is_empty():
				_play_view(prog, title, sub, "videos"),
			{"icon_name": "plane", "title_size": 15, "ribbon": "REPLAY", "ribbon_color": UIStyle.ACCENT})
		c.custom_minimum_size = Vector2(0, 200)
		g2.add_child(c)


# ================================================================== social
func _social() -> void:
	var items := []
	for p in News.feed(60):
		items.append({"t": float(p.t), "post": p})
	# the most liked comments of the day's stories surface in the feed too
	var n := 0
	for a in News.latest(12):
		if NewsComments.count(a) < 4:
			continue
		for c in NewsComments.page(a, "top", 1, 3):
			items.append({"t": float(c.t), "comment": c, "art": a})
		n += 1
		if n >= 6:
			break
	items.sort_custom(func(x, y): return float(x.t) > float(y.t))
	for it in items.slice(0, 80):
		if it.has("post"):
			_body.add_child(_post_card(it.post))
		else:
			_body.add_child(_comment_post(it.comment, it.art))


func _post_card(p: Dictionary) -> Control:
	var pc := UIStyle.panel()
	var row := UIStyle.hbox(12)
	pc.add_child(row)
	row.add_child(CommentSection.Avatar.make(String(p.name), Color.from_hsv(float(U.hash_str(String(p.name)) % 360) / 360.0, 0.55, 0.78), 42.0))
	var v := UIStyle.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var h := UIStyle.hbox(6)
	h.add_child(UIStyle.label(String(p.name), 15, UIStyle.TEXT, true))
	if bool(p.get("verified", false)):
		h.add_child(UIStyle.label("✔", 13, UIStyle.ACCENT))
	h.add_child(UIStyle.label("%s · %s" % [p.handle, U.fmt_ago(WorldSim.clock, float(p.t))], 13, UIStyle.DIM))
	v.add_child(h)
	var t := UIStyle.label(String(p.text), 15, UIStyle.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	if bool(p.get("video", false)):
		v.add_child(UIStyle.label("▶ phone video", 12, UIStyle.ACCENT))
	v.add_child(UIStyle.label("♥ %s   ⟳ %s   %s replies" % [U.fmt_int(int(p.likes)), U.fmt_int(int(p.reposts)), U.fmt_int(int(p.replies))], 12, UIStyle.DIM))
	return pc


func _comment_post(c: Dictionary, a: Dictionary) -> Control:
	var au: Dictionary = c.author
	var pc := UIStyle.panel()
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := UIStyle.hbox(12)
	pc.add_child(row)
	row.add_child(CommentSection.Avatar.make(String(au.name), au.get("color", UIStyle.ACCENT), 42.0))
	var v := UIStyle.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var h := UIStyle.hbox(6)
	h.add_child(UIStyle.label(String(au.name), 15, UIStyle.TEXT, true))
	if String(au.get("badge", "")) == "pilot":
		h.add_child(UIStyle.chip("PILOT", UIStyle.AMBER))
	h.add_child(UIStyle.label("%s · %s" % [au.get("handle", ""), U.fmt_ago(WorldSim.clock, float(c.t))], 13, UIStyle.DIM))
	v.add_child(h)
	var t := UIStyle.label(String(c.text), 15, UIStyle.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var on := UIStyle.label("on “%s”" % String(a.headline), 12, UIStyle.ACCENT)
	on.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(on)
	v.add_child(UIStyle.label("♥ %s   %s replies" % [NewsComments.short(int(c.likes)), NewsComments.short(int(c.replies))], 12, UIStyle.DIM))
	pc.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_show_article(a))
	return pc


# ================================================================== accidents
func _accidents() -> void:
	if News.incidents.is_empty():
		_body.add_child(UIStyle.label("No accidents on record.", 15, UIStyle.DIM))
	for i in range(News.incidents.size() - 1, -1, -1):
		var inc: Dictionary = News.incidents[i]
		var p := UIStyle.glass_panel(16)
		var row := UIStyle.hbox(14)
		p.add_child(row)
		var pic := ShotRect.make("type:%s:%s" % [String(inc.get("type", "s320")), String(inc.get("airline", "SKF"))], Vector2(220, 124))
		row.add_child(pic)
		var v := UIStyle.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(UIStyle.label(String(inc.title), 18, UIStyle.TEXT, true))
		var meta := UIStyle.label("%s · %s · %s" % [U.fmt_date(float(inc.clock)), inc.place, inc.summary], 14, UIStyle.DIM)
		meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(meta)
		if String(inc.get("cause", "")) != "":
			var cl := UIStyle.label("Probable cause: " + String(inc.cause), 14, UIStyle.AMBER)
			cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(cl)
		var btns := UIStyle.hbox(8)
		var iid := String(inc.id)
		var title := String(inc.title)
		btns.add_child(UIStyle.button("▶  News coverage", func(): _coverage(iid), 0, UIStyle.ACCENT))
		btns.add_child(UIStyle.button("▶  Investigation report", func():
			var prog := NewsScript.build({"type": "investigation", "incident": iid})
			if not prog.is_empty():
				_play_view(prog, title, "Calderra Transport Safety Board · investigation report", "accidents")))
		btns.add_child(UIStyle.button("All coverage", func(): _story_for(iid)))
		v.add_child(btns)
		_body.add_child(p)


## The most recent article about an incident, played straight away.
func _coverage(incident_id: String) -> void:
	for i in range(News.articles.size() - 1, -1, -1):
		var a: Dictionary = News.articles[i]
		if (String(a.get("incident", "")) == incident_id or (String(a.get("story", "")) != "" and _story_incident(String(a.story)) == incident_id)) \
				and not (a.get("video", {}) as Dictionary).is_empty() and float(a.t) <= WorldSim.clock + 60.0:
			_show_article(a, true)
			return
	var prog := NewsScript.build({"type": "reconstruction", "incident": incident_id})
	if not prog.is_empty():
		_play_view(prog, "Coverage", "", "accidents")


func _story_for(incident_id: String) -> void:
	_clear()
	_body.add_child(UIStyle.button("‹ Back", func(): _render(), 100))
	for a in News.articles:
		if String(a.get("incident", "")) == incident_id or (String(a.get("story", "")) != "" and _story_incident(String(a.story)) == incident_id):
			_body.add_child(_headline_row(a))


func _story_incident(sid: String) -> String:
	for s in News.stories:
		if String(s.id) == sid:
			return String(s.incident)
	for a in News.articles:
		if String(a.story) == sid and String(a.get("incident", "")) != "":
			return String(a.incident)
	return ""
