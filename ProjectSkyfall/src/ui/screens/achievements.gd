extends ScreenBase
## ACHIEVEMENTS: every goal in the game, grouped, with progress bars and unlock dates.


func setup(_params: Dictionary) -> void:
	page("menu", "soft")
	var v := UIStyle.vbox(14)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(v)
	var head := UIStyle.hbox(18)
	var tv := UIStyle.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UIStyle.caps("Your pilot story", 12, UIStyle.ACCENT, 800, 3))
	tv.add_child(UIStyle.title("Achievements", 40, Color.WHITE))
	head.add_child(tv)
	var tot := UIStyle.vbox(0)
	tot.size_flags_vertical = Control.SIZE_SHRINK_END
	tot.add_child(UIStyle.caps("Unlocked", 11, UIStyle.DIM, 700, 2))
	tot.add_child(UIStyle.title("%d / %d" % [Achievements.unlocked_count(), Achievements.LIST.size()], 26, UIStyle.GOLD))
	head.add_child(tot)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UIStyle.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var groups := []
	for a in Achievements.LIST:
		if not String(a.group) in groups:
			groups.append(String(a.group))
	for g in groups:
		list.add_child(ScreenBase.section(g))
		var grid := GridContainer.new()
		grid.columns = 2 if get_viewport_rect().size.x > 1000.0 else 1
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(grid)
		for a in Achievements.LIST:
			if String(a.group) == g:
				grid.add_child(_tile(a))


func _tile(a: Dictionary) -> Control:
	var done := Achievements.unlocked(String(a.id))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(1, 1, 1, 0.07) if done else Color(0, 0, 0, 0.35), 6,
		Color(UIStyle.GOLD, 0.55) if done else Color(1, 1, 1, 0.08), 1, 14))
	var h := UIStyle.hbox(14)
	p.add_child(h)
	h.add_child(UIIcon.make(String(a.icon) if done else "lock", 34, UIStyle.GOLD if done else Color(1, 1, 1, 0.35), 1.6))
	var tv := UIStyle.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UIStyle.label(String(a.title), 17, Color.WHITE if done else Color(1, 1, 1, 0.7), true))
	var d := UIStyle.label(String(a.desc), 13, UIStyle.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(d)
	if done:
		var t := float((Game.settings.achievements.done as Dictionary).get(String(a.id), 0.0))
		tv.add_child(UIStyle.label("Unlocked %s" % Time.get_date_string_from_unix_time(int(t)), 12, UIStyle.GOLD))
	elif a.has("goal"):
		var bar := Bar.new()
		bar.frac = clampf(Achievements.stat(String(a.stat)) / float(a.goal), 0.0, 1.0)
		bar.custom_minimum_size = Vector2(0, 7)
		tv.add_child(bar)
		tv.add_child(UIStyle.label("%d / %d" % [int(Achievements.stat(String(a.stat))), int(a.goal)], 12, UIStyle.DIM))
	h.add_child(tv)
	return p


## A flat progress bar (no rounded fill, which breaks at very small widths).
class Bar extends Control:
	var frac := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12))
		if frac > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * frac, size.y)), UIStyle.ACCENT)
