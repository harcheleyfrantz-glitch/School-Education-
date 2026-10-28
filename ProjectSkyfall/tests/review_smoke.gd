extends Node
## Headless review smoke test: opens every menu screen, then runs a matrix of short flight
## sessions back to back (as the game does when returning to the menu between flights).
## Usage: godot --headless --fixed-fps 60 --path . res://tests/review_smoke.tscn -- [screens|sessions|all] [seconds_per_session]
## Script errors are printed by the engine; grep the output for "SCRIPT ERROR" / "ERROR:".

const SESSIONS := [
	{"mode": "pilot", "type": "s320", "dep": "SKPC", "arr": "SKRV", "start": "gate"},
	{"mode": "pilot", "type": "t172", "dep": "SKPC", "arr": "SKRV", "start": "runway"},
	{"mode": "pilot", "type": "w350", "dep": "SKPC", "arr": "SKRV", "start": "air", "alt_ft": 3000.0, "dist_km": 16.0},
	{"mode": "passenger", "type": "rj90", "dep": "SKPC", "arr": "SKRV", "start": "gate"},
	{"mode": "passenger", "type": "s320", "dep": "SKPC", "arr": "SKRV", "start": "terminal"},
	{"mode": "pilot", "type": "tp72", "dep": "SKPC", "arr": "SKRV", "start": "air", "alt_ft": 2500.0, "dist_km": 12.0},
	{"mode": "pilot", "type": "bj6", "dep": "SKPC", "arr": "SKRV", "start": "gate"},
	{"mode": "pilot", "type": "tf4", "dep": "SKPC", "arr": "SKRV", "start": "runway"},
]

var _secs := 40.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var what := a[0] if a.size() > 0 else "all"
	_secs = float(a[1]) if a.size() > 1 else 40.0
	Game.settings.quality = "low"
	Game.settings.tts = false
	Engine.time_scale = float(OS.get_environment("TS")) if OS.get_environment("TS") != "" else 4.0
	if what in ["screens", "all"]:
		await _screens()
	if what in ["sessions", "all"]:
		await _sessions()
	print("REVIEW SMOKE DONE")
	get_tree().quit()


func _screen_names() -> PackedStringArray:
	var out := PackedStringArray()
	var base: Script = load("res://src/ui/screens/screen_base.gd")
	for f in DirAccess.get_files_at("res://src/ui/screens"):
		if not f.ends_with(".gd"):
			continue
		var s: Script = load("res://src/ui/screens/" + f)
		var b := s
		while b != null and b != base:
			b = b.get_base_script()
		if b == base and s != base:
			out.append(f.get_basename())
	return out


func _screens() -> void:
	if not Game.has_character():
		Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	if News.articles.is_empty():
		var day: Array = WorldSim.schedule_for_day(WorldSim.day_index())
		News.background_story("turbulence_injuries", day[3], WorldSim.clock - 3600.0, 7)
		News.background_story("bird_strike_return", day[8], WorldSim.clock - 7200.0, 9)
	var main_script: GDScript = load("res://src/main.gd")
	var main: Node = main_script.new()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	for sname in _screen_names():
		print("SCREEN ", sname)
		Game.goto(sname, {})
		for i in 20:
			await get_tree().process_frame
	Game.goto("menu", {})
	for i in 10:
		await get_tree().process_frame
	remove_child(main)
	main.queue_free()
	await get_tree().process_frame


func _sessions() -> void:
	for cfg: Dictionary in SESSIONS:
		var al := "SKF"
		for c in Airlines.all_codes():
			if Airlines.operates_type(c, String(cfg.type)):
				al = c
				break
		var p := cfg.duplicate()
		p.merge({"airline": al, "reg": "CR-RVW", "callsign": "Skyfall 451", "flight_id": "RVW-%s-%s" % [cfg.type, cfg.start],
			"instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, 17.5)})
		var s := FlightSession.new()
		s.set_meta("test_fast", true)
		add_child(s)
		var t0 := Time.get_ticks_msec()
		s.start(p)
		print("SESSION %s %s %s started in %d ms" % [cfg.mode, cfg.type, cfg.start, Time.get_ticks_msec() - t0])
		var t := 0.0
		var last := ""
		while t < _secs:
			await get_tree().process_frame
			t += get_process_delta_time()
			if s.phase != last:
				last = s.phase
				print("   %5.1fs phase %s" % [t, last])
		var n: Dictionary = s.ac.nav_state() if s.ac else {}
		print("   end: phase=%s alt=%.0fft ias=%.0f" % [s.phase, float(n.get("alt", 0.0)) / U.FT, float(n.get("ias_kt", 0.0))])
		remove_child(s)
		s.queue_free()
		for i in 5:
			await get_tree().process_frame
