extends Node
## Renders photo-studio shots to PNG for visual checks.
## Usage: -- <out_dir> <id,id,...|all> [scale] [fresh]
var out_dir := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var ids: Array = []
	if args.size() > 1 and args[1] != "all":
		ids = Array(args[1].split(","))
	else:
		ids = PhotoStudio.SHOTS.keys()
	PhotoStudio.scale = float(args[2]) if args.size() > 2 else 0.5
	if args.size() > 3 and args[3] == "fresh":
		for id in ids:
			PhotoStudio.invalidate(String(id))
	Game.settings.quality = "high"
	var studio := PhotoStudio.instance()
	await get_tree().process_frame
	for id in ids:
		var t0 := Time.get_ticks_msec()
		var tex := PhotoStudio.get_shot(String(id))
		while tex == null:
			var got: Array = await studio.shot_ready
			if String(got[0]) == String(id):
				tex = got[1]
		tex.get_image().save_png(out_dir.path_join("studio_%s.png" % String(id).replace(":", "_")))
		print("shot %s %d ms" % [id, Time.get_ticks_msec() - t0])
	print("studio shots done")
	get_tree().quit()
