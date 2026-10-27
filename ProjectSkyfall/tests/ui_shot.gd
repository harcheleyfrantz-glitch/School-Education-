extends Node
## Screenshots of the menu screens over the live backdrop.
var out_dir := "/tmp"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var screens := args[1].split(",") if args.size() > 1 else PackedStringArray(["menu", "create", "hub", "free", "passenger", "news", "settings"])
	Game.settings.quality = "medium"
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	for sname in screens:
		if sname == "hub" and not Game.has_character():
			Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
		if sname == "news" and News.articles.is_empty():
			News.background_story("turbulence_injuries", WorldSim.schedule_for_day(WorldSim.day_index())[3], WorldSim.clock - 3600.0, 7)
			News.background_story("bird_strike_return", WorldSim.schedule_for_day(WorldSim.day_index())[8], WorldSim.clock - 7200.0, 9)
		Game.goto(sname)
		var view: WorldView = main.backdrop.view if main.backdrop else null
		if view:
			await view.warm_up(6.0)
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("ui_%s.png" % sname))
		print("shot ", sname)
	get_tree().quit()
