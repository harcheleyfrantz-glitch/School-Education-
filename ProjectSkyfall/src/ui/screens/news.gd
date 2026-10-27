extends ScreenBase
## News hub: headlines from every outlet, an article reader with in-engine video, the social
## feed, and the accident archive with each story's full timeline.

var _tab := "headlines"
var _body: VBoxContainer
var _back := "menu"


func setup(params: Dictionary) -> void:
	_back = "hub" if Game.has_character() else "menu"
	frame("World news", U.fmt_datetime(WorldSim.clock), _back, 0.66)
	var tabs := UIStyle.hbox(8)
	for t in [["Headlines", "headlines"], ["Social", "social"], ["Accidents", "accidents"]]:
		var key: String = t[1]
		tabs.add_child(UIStyle.button(t[0], func():
			_tab = key
			_render(), 120))
	content.add_child(tabs)
	_body = UIStyle.vbox(10)
	content.add_child(_body)
	if params.has("article"):
		var a := News.article(String(params.article))
		if not a.is_empty():
			_show_article(a)
			return
	_render()


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func _render() -> void:
	_clear()
	match _tab:
		"headlines":
			var arts := News.latest(40)
			if arts.is_empty():
				_body.add_child(UIStyle.label("A quiet day. Nothing in the news yet.", 15, UIStyle.DIM))
			for a in arts:
				_body.add_child(_headline_row(a))
		"social":
			for p in News.feed(60):
				_body.add_child(_post_card(p))
		"accidents":
			if News.incidents.is_empty():
				_body.add_child(UIStyle.label("No accidents on record.", 15, UIStyle.DIM))
			for i in range(News.incidents.size() - 1, -1, -1):
				var inc: Dictionary = News.incidents[i]
				var p := UIStyle.panel()
				var v := UIStyle.vbox(4)
				p.add_child(v)
				v.add_child(UIStyle.label(String(inc.title), 17, UIStyle.TEXT, true))
				v.add_child(UIStyle.label("%s · %s · %s" % [U.fmt_date(float(inc.clock)), inc.place, inc.summary], 14, UIStyle.DIM))
				if String(inc.get("cause", "")) != "":
					var cl := UIStyle.label("Probable cause: " + String(inc.cause), 14, UIStyle.AMBER)
					cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					v.add_child(cl)
				var row := UIStyle.hbox(8)
				row.add_child(UIStyle.button("Watch reconstruction", func(): _watch({"type": "reconstruction", "incident": inc.id}), 0, UIStyle.ACCENT))
				row.add_child(UIStyle.button("Coverage", func(): _story_for(String(inc.id))))
				v.add_child(row)
				_body.add_child(p)


func _headline_row(a: Dictionary) -> Control:
	var o: Dictionary = News.OUTLETS.get(String(a.outlet), {"name": a.outlet, "color": "888888"})
	var p := PanelContainer.new()
	var col := Color.html(String(o.color))
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(0.06, 0.09, 0.13, 0.92), 10, Color(col, 0.9), 0, 12))
	var h := UIStyle.hbox(10)
	p.add_child(h)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(5, 0)
	h.add_child(bar)
	var v := UIStyle.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var meta := "%s · %s%s" % [o.name, U.fmt_ago(WorldSim.clock, float(a.t)), "  ▶ video" if not (a.get("video", {}) as Dictionary).is_empty() else ""]
	v.add_child(UIStyle.label(meta, 12, col.lightened(0.3)))
	var hl := UIStyle.label(String(a.headline), 17 if int(a.importance) >= 2 else 15, UIStyle.TEXT, int(a.importance) >= 2)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hl)
	h.add_child(v)
	p.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_show_article(a))
	return p


func _show_article(a: Dictionary) -> void:
	_clear()
	var o: Dictionary = News.OUTLETS.get(String(a.outlet), {"name": a.outlet, "color": "888888"})
	_body.add_child(UIStyle.button("‹ All news", func(): _render(), 120))
	_body.add_child(UIStyle.label("%s · %s" % [o.name, U.fmt_datetime(float(a.t))], 13, Color.html(String(o.color)).lightened(0.35)))
	var hl := UIStyle.label(String(a.headline), 26, UIStyle.TEXT, true)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(hl)
	var lede := UIStyle.label(String(a.lede), 17, UIStyle.TEXT)
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(lede)
	var video: Dictionary = a.get("video", {})
	if not video.is_empty():
		_body.add_child(UIStyle.button("▶  Watch video", func(): _watch(video, String(a.id)), 220, UIStyle.ACCENT))
	for para in a.get("body", []):
		var l := UIStyle.label(String(para), 15, UIStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)
	if String(a.get("story", "")) != "":
		var related := News.feed(12, String(a.story))
		if not related.is_empty():
			_body.add_child(UIStyle.label("Reactions", 17, UIStyle.ACCENT, true))
			for p in related:
				_body.add_child(_post_card(p))


func _post_card(p: Dictionary) -> Control:
	var pc := UIStyle.panel()
	var v := UIStyle.vbox(4)
	pc.add_child(v)
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
	v.add_child(UIStyle.label("♥ %s   ⟳ %s   💬 %s" % [U.fmt_int(int(p.likes)), U.fmt_int(int(p.reposts)), U.fmt_int(int(p.replies))], 12, UIStyle.DIM))
	return pc


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


func _watch(video: Dictionary, article_id: String = "") -> void:
	Game.goto("replay", {"video": video, "article": article_id, "back": "news"})
