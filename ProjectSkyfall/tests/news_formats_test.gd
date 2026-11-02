extends Node
## The newer news formats: the studio debate after a crash and a plane spotter's vlog. Builds
## and plays each; with an output directory it also saves a frame from every segment.
## Usage: -- [out_dir]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.tts = false
	WorldSim.clock = U.date_to_clock(2027, 6, 14, 14.0)
	var inc := News.npc_accident(U.rng(4242))
	var vlog_clip := {}
	for k in 30:
		News._spotter_vlog(int(WorldSim.clock / 86400.0), U.rng(9 + k))
		for p in News.posts:
			if String((p.get("clip", {}) as Dictionary).get("type", "")) == "vlog":
				vlog_clip = p.clip
		if not vlog_clip.is_empty():
			break
	var progs := [NewsScript.build({"type": "debate", "incident": inc.id}, {"headline": "Is flying still safe?", "t": WorldSim.clock + 30.0 * 3600.0}),
		NewsScript.build(vlog_clip, {"id": "vlog-test"})]
	for prog in progs:
		if prog.is_empty():
			print("EMPTY PROGRAM")
			continue
		print("PROGRAM %s %.1fs %s" % [prog.kind, float(prog.duration), str(prog.segments.map(func(s): return s.kind))])
		for l in prog.lines.slice(0, 14):
			print("    %5.1f %-9s %s" % [float(l.t0), l.who, String(l.text).left(110)])
		var p := BroadcastPlayer.new()
		add_child(p)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.open(prog, {"autoplay": false})
		var guard := 0
		while not p.loaded and guard < 3000:
			await get_tree().process_frame
			guard += 1
		var j := 0
		for s in prog.segments:
			p.seek((float(s.t0) + float(s.t1)) * 0.5)
			p.set_playing(false)
			for i in (3 if a.is_empty() else 14):
				await get_tree().process_frame
			if not a.is_empty():
				p.get("_big").visible = false
				get_viewport().get_texture().get_image().save_png(a[0].path_join("f_%s_%d_%s.png" % [prog.kind, j, s.kind]))
			j += 1
		p.queue_free()
		await get_tree().process_frame
	print("NEWS FORMATS TEST DONE")
	get_tree().quit()
