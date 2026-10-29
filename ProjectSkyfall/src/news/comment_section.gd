class_name CommentSection
extends VBoxContainer
## The comment section under an article or a video: the running count, Top/Newest sorting,
## a box to add your own comment, pages of comments with avatars, badges, likes and
## expandable reply threads, and "load more" until the whole thread has been read.

var art: Dictionary = {}
var sort := "top"
var shown := 0
var _list: VBoxContainer
var _more: Button
var _count_lbl: Label
var _sort_btns := {}
var _input: LineEdit
var _liked := {}


func setup(a: Dictionary) -> void:
	art = a
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UIStyle.hbox(10)
	_count_lbl = UIStyle.label("", 21, UIStyle.TEXT, true)
	head.add_child(_count_lbl)
	head.add_child(UIStyle.spacer())
	head.add_child(UIStyle.label("Sort by", 13, UIStyle.DIM))
	for s in [["Top", "top"], ["Newest", "new"]]:
		var key: String = s[1]
		var b := UIStyle.button(s[0], func(): _set_sort(key), 86)
		_sort_btns[key] = b
		head.add_child(b)
	add_child(head)
	add_child(_composer())
	_list = UIStyle.vbox(14)
	add_child(_list)
	_more = UIStyle.button("Load more comments", _load_more, 280)
	_more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_more)
	_set_sort("top")


func _composer() -> Control:
	var row := UIStyle.hbox(10)
	var me := String(Game.player.get("name", "You")) if Game.has_character() else "You"
	row.add_child(Avatar.make(me, UIStyle.ACCENT, 38.0))
	_input = LineEdit.new()
	_input.placeholder_text = "Add a comment..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 40)
	_input.max_length = 400
	_input.text_submitted.connect(func(_t): _post())
	row.add_child(_input)
	row.add_child(UIStyle.button("Post", _post, 80, UIStyle.ACCENT))
	return row


func _post() -> void:
	var tx := _input.text.strip_edges()
	if tx == "":
		return
	var me := String(Game.player.get("name", "You")) if Game.has_character() else "You"
	var mine: Array = art.get("player_comments", [])
	mine.append({"name": me, "text": tx, "t": WorldSim.clock})
	art["player_comments"] = mine
	_input.text = ""
	_set_sort(sort)


func _set_sort(key: String) -> void:
	sort = key
	for k in _sort_btns:
		var b: Button = _sort_btns[k]
		b.modulate = Color.WHITE if k == key else Color(1, 1, 1, 0.55)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	shown = 0
	for pc in art.get("player_comments", []):
		var me := String(pc.get("name", "You"))
		_list.add_child(_card({"author": {"name": me, "handle": "@you", "badge": "", "title": "", "color": UIStyle.ACCENT}, "text": String(pc.get("text", "")),
			"likes": 0, "t": float(pc.get("t", WorldSim.clock)), "replies": 0, "edited": false, "pinned": false, "depth": 0, "tone": "mine", "i": -1}))
	_load_more()


func _load_more() -> void:
	var page := NewsComments.page(art, sort, shown, NewsComments.PAGE)
	for c in page:
		_list.add_child(_card(c))
	shown += page.size()
	var n := NewsComments.count(art) + (art.get("player_comments", []) as Array).size()
	_count_lbl.text = "%s comments" % U.fmt_int(n)
	_more.visible = shown < NewsComments.count(art)
	_more.text = "Load more comments  (%s more)" % U.fmt_int(NewsComments.count(art) - shown)


func _card(c: Dictionary) -> Control:
	var depth := int(c.get("depth", 0))
	var au: Dictionary = c.author
	var outer := UIStyle.vbox(6)
	var row := UIStyle.hbox(12)
	outer.add_child(row)
	row.add_child(Avatar.make(String(au.name), au.get("color", UIStyle.ACCENT), 40.0 if depth == 0 else 30.0))
	var v := UIStyle.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 7)
	h.add_child(UIStyle.label(String(au.name), 15 if depth == 0 else 14, UIStyle.TEXT, true))
	match String(au.get("badge", "")):
		"pilot":
			h.add_child(UIStyle.chip("PILOT", UIStyle.AMBER))
		"expert":
			h.add_child(UIStyle.chip("EXPERT", UIStyle.ACCENT))
		"outlet", "airline", "verified":
			h.add_child(UIStyle.label("✔", 13, UIStyle.ACCENT, true))
	if String(au.get("title", "")) != "":
		h.add_child(UIStyle.label(String(au.title), 12, UIStyle.AMBER))
	h.add_child(UIStyle.label("%s · %s%s" % [au.get("handle", ""), U.fmt_ago(WorldSim.clock, float(c.t)), " · edited" if bool(c.get("edited", false)) else ""], 12, UIStyle.DIM))
	if bool(c.get("pinned", false)):
		h.add_child(UIStyle.chip("PINNED", UIStyle.GOLD))
	v.add_child(h)
	var tx := UIStyle.label(String(c.text), 15 if depth == 0 else 14, UIStyle.TEXT)
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tx)
	var act := UIStyle.hbox(4)
	var key := "%d:%d:%d" % [int(c.get("i", 0)), depth, U.hash_str(String(c.text))]
	var likes := int(c.likes)
	var lb := Button.new()
	lb.flat = true
	lb.focus_mode = Control.FOCUS_NONE
	lb.add_theme_font_size_override("font_size", 13)
	var paint := func():
		var on := bool(_liked.get(key, false))
		lb.text = "♥ %s" % NewsComments.short(likes + (1 if on else 0))
		lb.add_theme_color_override("font_color", UIStyle.RED if on else UIStyle.DIM)
	paint.call()
	lb.pressed.connect(func():
		_liked[key] = not bool(_liked.get(key, false))
		paint.call())
	act.add_child(lb)
	var rb := Button.new()
	rb.flat = true
	rb.focus_mode = Control.FOCUS_NONE
	rb.text = "Reply"
	rb.add_theme_font_size_override("font_size", 13)
	rb.add_theme_color_override("font_color", UIStyle.DIM)
	rb.pressed.connect(func():
		if _input:
			_input.text = "@%s " % String(au.get("handle", "")).trim_prefix("@")
			_input.grab_focus()
			_input.caret_column = _input.text.length())
	act.add_child(rb)
	v.add_child(act)
	if depth == 0 and int(c.get("replies", 0)) > 0:
		var holder := MarginContainer.new()
		holder.add_theme_constant_override("margin_left", 52)
		var rv := UIStyle.vbox(10)
		holder.add_child(rv)
		holder.visible = false
		var tb := Button.new()
		tb.flat = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tb.add_theme_font_size_override("font_size", 13)
		tb.add_theme_color_override("font_color", UIStyle.ACCENT)
		var n := int(c.replies)
		tb.text = "▾  %s %s" % [U.fmt_int(n), "reply" if n == 1 else "replies"]
		var state := {"shown": 0}
		var more_btn := Button.new()
		more_btn.flat = true
		more_btn.focus_mode = Control.FOCUS_NONE
		more_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more_btn.add_theme_font_size_override("font_size", 13)
		more_btn.add_theme_color_override("font_color", UIStyle.ACCENT)
		var fill := func():
			var got := NewsComments.replies(art, c, int(state.shown), 6)
			for rc in got:
				var card := _card(rc)
				if int(rc.depth) > 1:
					var m := MarginContainer.new()
					m.add_theme_constant_override("margin_left", 42)
					m.add_child(card)
					card = m
				rv.add_child(card)
			state.shown = mini(int(state.shown) + 6, n)
			rv.move_child(more_btn, rv.get_child_count() - 1)
			more_btn.visible = int(state.shown) < n
			more_btn.text = "Show more replies (%d)" % (n - int(state.shown))
		rv.add_child(more_btn)
		more_btn.pressed.connect(fill)
		tb.pressed.connect(func():
			holder.visible = not holder.visible
			tb.text = ("▴  Hide replies" if holder.visible else "▾  %s %s" % [U.fmt_int(n), "reply" if n == 1 else "replies"])
			if holder.visible and int(state.shown) == 0:
				fill.call())
		v.add_child(tb)
		outer.add_child(holder)
	return outer


## Round avatar with initials.
class Avatar extends Control:
	var initials := ""
	var col := Color.GRAY

	static func make(n: String, c: Color, d: float) -> Avatar:
		var a := Avatar.new()
		var parts := n.replace("Capt. ", "").split(" ", false)
		a.initials = (parts[0].substr(0, 1) + (parts[parts.size() - 1].substr(0, 1) if parts.size() > 1 else "")).to_upper() if parts.size() > 0 else "?"
		a.col = c
		a.custom_minimum_size = Vector2(d, d)
		a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return a

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := Vector2(r, r)
		draw_circle(c, r, col.darkened(0.15))
		draw_circle(c, r - 1.5, col)
		var f := UIStyle.font(true)
		var fs := int(r * 0.78)
		var w := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(r - w * 0.5, r + fs * 0.36), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
