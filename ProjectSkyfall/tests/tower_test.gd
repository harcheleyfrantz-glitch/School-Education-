extends Node
## Tower mode: auto-clears every arrival and departure for a while, then forces a runway
## collision by clearing a departure while an arrival is landing. -- [out_dir] for screenshots
var tw: TowerSession
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.tts = false
	Game.settings.quality = "low"
	tw = TowerSession.new()
	add_child(tw)
	tw.setup({"icao": "KJFK", "traffic": "rush", "hour": 15.0})
	tw.speed = 4.0
	var t := 0.0
	var shot := 0
	while t < 900.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		for it in tw.traffic.moving.duplicate():
			if String(it.phase) == "final" and float(it.get("dist", 0.0)) < 6000.0 and t < 600.0:
				tw.clear_land(it)
			if String(it.phase) == "hold":
				if t < 600.0:
					tw.clear_takeoff(it)
				else:
					# collision test: release departures even with someone landing
					it.clear_takeoff = true
		if a.size() > 0 and shot < 3 and t > 200.0 * (shot + 1):
			for it2 in tw.traffic.moving:
				if it2.get("model") != null and String(it2.phase) in ["final", "takeoff", "rollout", "hold"]:
					tw.selected = it2
					break
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/tower_%d.png" % [a[0], shot])
			shot += 1
		if int(t) % 100 == 0 and int(t) != int(t - get_process_delta_time()):
			print("%3ds moving=%d parked=%d score=%d stats=%s" % [int(t), tw.traffic.moving.size(), tw.traffic.parked.size(), tw.score, str(tw.stats)])
	print("RADIO:\n", "\n".join(tw.log_lines.slice(maxi(tw.log_lines.size() - 6, 0))))
	print("TOWER TEST DONE")
	get_tree().quit()
