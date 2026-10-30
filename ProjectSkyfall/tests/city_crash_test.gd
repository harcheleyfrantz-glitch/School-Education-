extends Node
## Other airlines' crashes: generates NPC accidents until one lands in a city, then a repeat at
## the same site, and plays the city coverage and the security camera clip.
## Usage: -- [out_dir]   (out_dir: save frames; needs a display)

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.tts = false
	WorldSim.clock = U.date_to_clock(2027, 6, 14, 15.0)
	var inc := {}
	for i in 40:
		inc = News.npc_accident(U.rng(1000 + i))
		print("NPC crash %s %s %s urban=%s fatal=%d/%d" % [inc.title, inc.place, inc.cause, inc.get("urban", false), int(inc.counts.fatal), int(inc.counts.aboard)])
		if bool(inc.get("urban", false)):
			break
	var rep := News.npc_accident(U.rng(77), true)
	print("REPEAT: ", rep.get("repeat_of", "none"), " ", rep.place)
	for ar in News.articles.slice(News.articles.size() - 3):
		print("  ARTICLE ", ar.headline)
	var clips: Array = inc.get("clips", [])
	var cc := {}
	for c in clips:
		if String(c.variant) == "cctv":
			cc = c
	print("clips ", clips.map(func(c): return c.variant))
	var progs := [NewsScript.build({"type": "reconstruction", "incident": inc.id, "pkg": "breaking"}, {})]
	if not cc.is_empty():
		progs.append(NewsScript.build(cc, {"id": "cctv"}))
	for prog in progs:
		print("PROGRAM %s %.1fs %s" % [prog.kind, float(prog.duration), str(prog.segments.map(func(s): return s.kind))])
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
			if String(s.stage) != "world" and a.size() > 0:
				continue
			for frac in ([0.5] if String(s.kind) != "phone" else [0.45, 0.8]):
				p.seek(lerpf(float(s.t0), float(s.t1), frac))
				p.set_playing(false)
				p.get("_big").visible = false
				for i in (4 if a.size() < 1 else 14):
					await get_tree().process_frame
				var ws = p.stages.get("world", null)
				if ws:
					print("   cam ", ws.cam.global_position, " fwd ", -ws.cam.global_transform.basis.z, " fov ", ws.cam.fov, " impact ", ws._local(ws.impact_w), " wit ", ws._local(ws.witness_w), " var ", ws.phone_variant, " model ", ws.model.visible if ws.model else null)
				if ws and String(s.kind) == "aerial" and not ws.torn_spots.is_empty() and a.size() > 0:
					var h: Vector3 = ws._local(ws.torn_spots[0])
					var ws_cam: Camera3D = ws.cam
					for k in 2:
						var off := Vector3(55, 18, 40) if k == 0 else Vector3(-30, 6, 70)
						ws.set_meta("closeup", off)
						p.seek(p.t + 0.01)
						p.set_playing(false)
						for i2 in 10:
							await get_tree().process_frame
						ws.remove_meta("closeup")
						get_viewport().get_texture().get_image().save_png(a[0].path_join("close_%d.png" % k))
				if a.size() > 0:
					get_viewport().get_texture().get_image().save_png(a[0].path_join("c_%s_%d_%s.png" % [prog.kind, j, s.kind]))
				j += 1
		p.queue_free()
		await get_tree().process_frame
	print("CITY TEST DONE")
	get_tree().quit()
