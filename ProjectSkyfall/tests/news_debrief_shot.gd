extends Node
## Renders the accident debrief with its investigation video for the crash in a news fixture.
## godot --path . --resolution 1280x720 res://tests/news_debrief_shot.tscn -- out_dir fixture.json [kinds]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp"
	var fixture := a[1] if a.size() > 1 else ""
	var kinds := (a[2] if a.size() > 2 else "title,fdr,impact,findings,cause,factors,remember").split(",")
	Game.settings.quality = "medium"
	Game.settings.tts = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	WorldSim.clock = float(data.get("crash_clock", WorldSim.clock))
	var res: Dictionary = data.get("result", {})
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var dv_script: GDScript = load("res://src/ui/debrief_view.gd")
	var dv: Control = dv_script.new()
	add_child(dv)
	dv.call("show_result", res)
	var p: BroadcastPlayer = dv.get("player")
	var guard := 0
	while p and not p.loaded and guard < 4000:
		await get_tree().process_frame
		guard += 1
	if p == null:
		print("no player")
		get_tree().quit()
		return
	p.set_playing(false)
	var done := {}
	for s in p.program.segments:
		var k := String(s.kind)
		if not k in kinds or done.has(k):
			continue
		done[k] = true
		var tt := float(s.t0) + (float(s.t1) - float(s.t0)) * (0.62 if k == "fdr" else 0.7)
		p.seek(tt)
		p.set_playing(false)
		p.get("_big").visible = false
		for i in 8:
			await get_tree().process_frame
		var st: Node = p.stages.get(String(s.stage), null)
		var g := 0
		while st and st.has_method("settled") and not st.call("settled") and g < 240:
			await get_tree().process_frame
			g += 1
		for i2 in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("debrief_%s.png" % k))
		p.capture_frame().save_png(out.path_join("debrief_frame_%s.png" % k))
		print("shot ", k, " t=", tt)
	get_tree().quit()
