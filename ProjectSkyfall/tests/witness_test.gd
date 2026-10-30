extends Node
## Bystander phone videos and the filmer's press conference: generates the clips for a fixture
## crash, advances the clock to the briefing, builds every program and plays through each one.
## Usage: -- fixture.json [out_dir]  (out_dir: save a frame per segment; needs a display)

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.tts = false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	News.deserialize(data.get("news", {}))
	WorldSim.clock = float(data.get("clock", WorldSim.clock))
	var inc: Dictionary = News.incidents[News.incidents.size() - 1]
	inc.erase("clips")
	News._phone_footage(inc, U.rng(7), {"num": String(inc.num)}, String(inc.place), false, "S-test")
	var clips: Array = inc.get("clips", [])
	print("CLIPS ", clips.size(), " ", clips.map(func(c): return "%s/%s/%s" % [c.variant, c.name, c.gender]))
	News.on_clock(WorldSim.clock, WorldSim.clock + 8.0 * 3600.0)
	WorldSim.clock += 8.0 * 3600.0
	var pres := {}
	for ar in News.articles:
		if String(ar.get("video", {}).get("type", "")) == "witness_presser":
			pres = ar
	print("PRESSER ARTICLE: ", pres.get("headline", "NONE"))
	var progs := []
	for c in clips:
		progs.append(NewsScript.build(c, {"id": "P-" + String(c.variant)}))
	progs.append(NewsScript.build(pres.video, pres))
	for prog in progs:
		if prog.is_empty():
			print("EMPTY PROGRAM")
			continue
		print("PROGRAM %s %.1fs: %s" % [prog.kind, float(prog.duration), str(prog.segments.map(func(s): return "%s/%s%s" % [s.kind, s.stage, ("/" + String(s.variant)) if s.has("variant") else ""]))])
		for l in prog.lines:
			print("    %5.1f %-9s %s" % [float(l.t0), l.who, String(l.text).left(100)])
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
			for i in (4 if a.size() < 2 else 12):
				await get_tree().process_frame
			if a.size() > 1:
				get_viewport().get_texture().get_image().save_png(a[1].path_join("w_%s_%s.png" % [String(prog.segments[0].get("variant", prog.kind)) if prog.kind == "phone" else "presser", s.kind]))
		p.queue_free()
		await get_tree().process_frame
	print("WITNESS TEST DONE")
	get_tree().quit()
