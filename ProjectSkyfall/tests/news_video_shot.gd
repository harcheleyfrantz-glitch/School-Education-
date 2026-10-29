extends Node
## Renders frames of a news video from a fixture made by news_fixture.gd.
## godot --path . --resolution 1280x720 res://tests/news_video_shot.tscn -- out_dir fixture.json which times
##   which: breaking | confirmed | victims | survivors | prelim | final | memorial | pilot | phone | inv | report:<topic> | replay
##   times: comma-separated seconds, or "chapters" (a frame in the middle of every chapter)

var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var fixture := a[1] if a.size() > 1 else ""
	var which := a[2] if a.size() > 2 else "breaking"
	var times := a[3] if a.size() > 3 else "chapters"
	Game.settings.quality = OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "medium"
	Game.settings.tts = false
	Game.apply_settings()
	var data := {}
	if fixture != "" and FileAccess.file_exists(fixture):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	if not data.is_empty():
		News.deserialize(data.get("news", {}))
		WorldSim.clock = float(data.get("clock", WorldSim.clock))
	var prog := _program(which, data)
	if prog.is_empty():
		print("NO PROGRAM for ", which)
		get_tree().quit()
		return
	print("PROGRAM %s outlet=%s duration=%.1f segments=%d lines=%d" % [prog.kind, prog.outlet, float(prog.duration), prog.segments.size(), prog.lines.size()])
	for s in prog.segments:
		print("  %6.1f-%6.1f %-10s %-9s shots=%s" % [float(s.t0), float(s.t1), s.kind, s.stage, str(s.shots.map(func(x): return x.cam))])
	for l in prog.lines.slice(0, 60):
		print("    %6.1f %-9s %s" % [float(l.t0), l.who, String(l.text).left(110)])
	var p := BroadcastPlayer.new()
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.open(prog, {"autoplay": false})
	var guard := 0
	while not p.loaded and guard < 4000:
		await get_tree().process_frame
		guard += 1
	p.set_playing(false)
	var list := []
	if times == "chapters":
		var segs: Array = prog.segments
		for s2 in segs:
			list.append((float(s2.t0) + float(s2.t1)) * 0.5)
	else:
		for x in times.split(","):
			list.append(float(x))
	for tt in list:
		p.seek(float(tt))
		p.set_playing(false)
		p.get("_big").visible = false
		for i in int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "10"):
			await get_tree().process_frame
		var seg: Dictionary = prog.segments[p.segment_at(float(tt))]
		var st: Node = p.stages.get(String(seg.stage), null)
		if st and st.has_method("settled"):
			var g := 0
			while not st.call("settled") and g < 240:
				await get_tree().process_frame
				g += 1
			for i2 in 4:
				await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var name := "%s_%05.1f.png" % [which.replace(":", "_"), float(tt)]
		img.save_png(out_dir.path_join(name))
		print("shot ", name)
	get_tree().quit()


func _program(which: String, data: Dictionary) -> Dictionary:
	if which == "inv":
		return NewsScript.for_result(data.get("result", {}))
	if which == "replay":
		var r: Dictionary = data.get("result", {})
		var copy := r.duplicate(true)
		copy.outcome = "landed"
		return NewsScript.build({"type": "replay", "samples": r.get("recorder", {}).get("samples", []), "type_id": r.get("type", "s320"),
			"airline": r.get("airline", "SKF"), "callsign": r.get("callsign", ""), "clock": r.get("clock", 0.0), "outcome": "crashed"})
	if which == "phone":
		var inc: Dictionary = News.incidents[News.incidents.size() - 1]
		return NewsScript.build({"type": "phone", "incident": inc.id, "author": "@skyspotter77", "seed": 3})
	if which.begins_with("report"):
		var topic := which.substr(7) if which.length() > 7 else "incident"
		var f: Dictionary = WorldSim.schedule_for_day(WorldSim.day_index())[5]
		var art := {"id": "T1", "outlet": "gazette", "kind": "news", "headline": "%s flight returns to %s after bird strike" % [Airlines.get_al(String(f.airline)).name, Airports.get_ap(String(f.from)).short],
			"lede": "The crew of %s declared an emergency shortly after takeoff." % f.number, "tags": [topic], "t": WorldSim.clock - 3600.0}
		return NewsScript.build({"type": "report", "airport": f.from, "airline": f.airline, "type_id": f.type, "scene": "emergency_landing"}, art)
	var pkg := which
	for a in News.articles:
		var v: Dictionary = a.get("video", {})
		if v.is_empty():
			continue
		if NewsScript._pkg_for_article(a, String(v.get("angle", ""))) == pkg or String(v.get("pkg", "")) == pkg:
			return NewsScript.build(v, a)
	if not News.incidents.is_empty():
		var inc2: Dictionary = News.incidents[News.incidents.size() - 1]
		return NewsScript.build({"type": "package", "pkg": pkg, "incident": inc2.id}, {})
	return {}
