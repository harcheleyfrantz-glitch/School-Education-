extends Node
## Runs two weeks of the news world, then builds and plays every everyday report type and the
## weekly roundup. Usage: -- [out_dir]  (out_dir: save a frame from each; needs a display)

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.tts = false
	Game.settings.npc_crashes = "off"
	WorldSim.clock = U.date_to_clock(2027, 6, 1, 6.0)
	var day0 := int(WorldSim.clock / 86400.0)
	for d in 15:
		WorldSim.clock = float(day0 + d) * 86400.0 + 60.0
		News._daily(day0 + d)
	WorldSim.clock = float(day0 + 15) * 86400.0
	var seen := {}
	for ar in News.articles:
		var tags: Array = ar.get("tags", [])
		print("%-9s %-10s %s" % [ar.outlet, tags[1] if tags.size() > 1 else (tags[0] if tags.size() > 0 else ""), ar.headline])
		var key := String(tags[1]) if tags.size() > 1 and String(tags[0]) == "aviation" else ("roundup" if "roundup" in tags else "")
		if key != "" and not seen.has(key) and not (ar.get("video", {}) as Dictionary).is_empty():
			seen[key] = ar
	print("TYPES: ", seen.keys())
	for k in seen:
		var ar: Dictionary = seen[k]
		var prog := NewsScript.build(ar.video, ar)
		if prog.is_empty():
			print("EMPTY ", k)
			continue
		print("PROGRAM %s %.1fs %s" % [prog.kind, float(prog.duration), str(prog.segments.map(func(s): return s.kind))])
		var p := BroadcastPlayer.new()
		add_child(p)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.open(prog, {"autoplay": false})
		var guard := 0
		while not p.loaded and guard < 3000:
			await get_tree().process_frame
			guard += 1
		for s in prog.segments:
			p.seek((float(s.t0) + float(s.t1)) * 0.5)
			p.set_playing(false)
			for i in (3 if a.is_empty() else 12):
				await get_tree().process_frame
			if not a.is_empty() and String(s.kind) in ["spotter", "studio"] and String(s.kind) != "":
				p.get("_big").visible = false
				get_viewport().get_texture().get_image().save_png(a[0].path_join("v_%s_%s.png" % [k, s.kind]))
		p.queue_free()
		await get_tree().process_frame
	print("VARIETY TEST DONE")
	get_tree().quit()
