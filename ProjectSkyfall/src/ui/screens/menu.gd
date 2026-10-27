extends ScreenBase
## Title screen.


func setup(_params: Dictionary) -> void:
	var c := frame("", "", "", 0.42)
	header_title.visible = false
	var title := UIStyle.label("PROJECT SKYFALL", 46, UIStyle.TEXT, true)
	title.add_theme_constant_override("outline_size", 0)
	c.add_child(title)
	c.add_child(UIStyle.label("An aviation life simulator", 17, UIStyle.ACCENT))
	c.add_child(UIStyle.spacer(false))
	if Game.has_character():
		var p: Dictionary = Game.player
		var al := Airlines.get_al(String(p.get("airline", ""))) if String(p.get("airline", "")) != "" else {}
		var card := UIStyle.panel()
		var v := UIStyle.vbox(4)
		card.add_child(v)
		v.add_child(UIStyle.label("%s %s" % [p.get("rank", ""), p.get("name", "")], 18, UIStyle.TEXT, true))
		v.add_child(UIStyle.label("%s · %d hours · %s" % [al.get("name", "Unemployed"), int(float(p.get("hours", 0.0))), U.fmt_money(float(p.get("money", 0.0)))], 14, UIStyle.DIM))
		c.add_child(card)
		c.add_child(UIStyle.button("Continue career", func(): Game.goto("hub"), 300, UIStyle.ACCENT))
	c.add_child(UIStyle.button("New career", func(): Game.goto("create"), 300, Color(0, 0, 0, 0) if Game.has_character() else UIStyle.ACCENT))
	c.add_child(UIStyle.button("Free flight", func(): Game.goto("free"), 300))
	c.add_child(UIStyle.button("Fly as a passenger", func(): Game.goto("passenger"), 300))
	c.add_child(UIStyle.button("World news", func(): Game.goto("news"), 300))
	c.add_child(UIStyle.button("Archive", func(): Game.goto("archive"), 300))
	c.add_child(UIStyle.button("Settings", func(): Game.goto("settings", {"back": "menu"}), 300))
	if not Game.is_mobile:
		c.add_child(UIStyle.button("Quit", func():
			if Game.has_character():
				Game.save_game()
			get_tree().quit(), 300))
	c.add_child(UIStyle.spacer(false))
	c.add_child(UIStyle.label("%s · %s" % [U.fmt_date(WorldSim.clock), "v" + String(ProjectSettings.get_setting("application/config/version", "1.0"))], 13, UIStyle.DIM))
