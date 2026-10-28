extends Node
## Screenshots of the front-end screens over the live backdrop, waiting for the photo studio.
## Usage: -- <out_dir> <screen[:arg],...> [studio_scale] [char|nochar] [hover]
## Screen args: activity:<category>, hangar:<type>, world_map:<dep>-<arr>, profile, ...
var out_dir := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var screens := args[1].split(",") if args.size() > 1 else PackedStringArray(["menu"])
	PhotoStudio.scale = float(args[2]) if args.size() > 2 else 0.5
	var with_char := args.size() <= 3 or args[3] != "nochar"
	var hover := args.size() > 4 and args[4] == "hover"
	Game.settings.quality = "medium"
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	if with_char and not Game.has_character():
		Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
		Game.player.appearance = {"skin": 2, "hair_color": 1, "hair": 4, "build": 0.8}
		Game.player.hours = 1840.0
		Game.player.flights = 212
		Game.player.landings = 208
		var log: Array = Game.player.logbook
		var routes := [["SKPC", "SKRV"], ["SKRV", "SKPC"], ["SKPC", "SKIM"], ["SKIM", "SKSB"], ["SKSB", "SKPC"], ["SKPC", "SKHP"]]
		for i in 14:
			var r: Array = routes[i % routes.size()]
			log.append({"t": WorldSim.clock - (14 - i) * 86400.0 * 0.7, "flight": "CL%d" % (140 + i), "type": "tp72", "reg": "CR-CKT",
				"from": r[0], "to": r[1], "hours": 0.7 + (i % 3) * 0.2, "grade": ["A", "B", "A", "C", "B"][i % 5], "outcome": "landed",
				"score": 92.0 - (i % 5) * 6.0})
		Game.player.hours_by_type = {"tp72": 1320.0, "t172": 520.0}
	if News.articles.is_empty():
		News.background_story("turbulence_injuries", WorldSim.schedule_for_day(WorldSim.day_index())[3], WorldSim.clock - 3600.0, 7)
		News.background_story("bird_strike_return", WorldSim.schedule_for_day(WorldSim.day_index())[8], WorldSim.clock - 7200.0, 9)
	var recs := Activities.records()
	if recs.is_empty():
		recs["trade_winds"] = {"done": 2, "best": 91.4, "medal": "gold", "last": 88.0}
		recs["short_field"] = {"done": 1, "best": 72.0, "medal": "bronze", "last": 72.0}
		recs["golden_coast"] = {"done": 1, "best": 84.0, "medal": "silver", "last": 84.0}
		recs["grand_tour"] = {"leg": 1, "leg_scores": [86.0, -1.0, -1.0]}
	for spec in screens:
		var parts := String(spec).split(":")
		var sname := parts[0]
		var params := {}
		match sname:
			"activity":
				params = {"category": parts[1] if parts.size() > 1 else "landing"}
			"hangar":
				if parts.size() > 1:
					params = {"type": parts[1]}
			"world_map":
				if parts.size() > 1:
					var dp := parts[1].split("-")
					params = {"dep": dp[0], "arr": dp[1] if dp.size() > 1 else dp[0]}
		Game.goto(sname, params)
		var view: WorldView = main.backdrop.view if main.backdrop else null
		if view:
			await view.warm_up(6.0)
		for i in 10:
			await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		while PhotoStudio.instance().pending() > 0 and Time.get_ticks_msec() - t0 < 400000:
			await get_tree().create_timer(0.5).timeout
		for i in 50:
			await get_tree().process_frame
		var tag := String(spec).replace(":", "_")
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_%s.png" % tag))
		print("shot ", tag, " ", Time.get_ticks_msec() - t0, " ms")
		if hover:
			_hover_first(main)
			for i in 40:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_%s_hover.png" % tag))
	print("menu shots done")
	get_tree().quit()


func _hover_first(main: Node) -> void:
	var scr: Node = main.get("current")
	var cards := scr.find_children("*", "ImageCard", true, false)
	if not cards.is_empty():
		(cards[0] as Control).grab_focus()
