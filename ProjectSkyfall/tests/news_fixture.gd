extends Node
## Flies a real accident (like crash_test), applies the result, lets the news story run for a
## number of days and saves the world's news, the clock and the flight result as JSON, so the
## news-video tests can load a genuine incident without flying again.
## godot --headless --fixed-fps 60 --path . res://tests/news_fixture.tscn -- out.json [type] [pitch] [scenario] [days]

var session: FlightSession
var t := 0.0
var _result := {}
var pitch := -0.45
var scenario := "dive"
var out_path := "/tmp/news_fixture.json"
var days := 40.0
var _crashed := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = a[0] if a.size() > 0 else out_path
	var type_id := a[1] if a.size() > 1 else "s320"
	pitch = float(a[2]) if a.size() > 2 else -0.45
	scenario = a[3] if a.size() > 3 else "dive"
	days = float(a[4]) if a.size() > 4 else 40.0
	Game.settings.quality = "low"
	Game.settings.tts = false
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.finished.connect(func(r): _result = r)
	var belly := scenario == "belly"
	session.start({"mode": "passenger" if belly else "pilot", "type": type_id, "airline": String(Game.player.airline), "reg": "CR-CRT", "dep": "SKPC", "arr": "SKRV",
		"callsign": "Skyfall 451", "flight_id": "FIX-%s-%s" % [type_id, scenario], "start": "air", "alt_ft": 6000.0 if belly else 2500.0,
		"dist_km": 40.0 if belly else 12.0, "instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 15.0)})
	if belly:
		Engine.time_scale = 4.0


func _process(delta: float) -> void:
	if session == null:
		return
	t += delta
	var ac := session.ac
	if scenario == "belly":
		if ac.ra < 250.0 and not ac.crashed_state:
			ac.sys.gear_down_cmd = false
	elif t > 3.0 and not ac.crashed_state:
		if ac.ap.engaged:
			ac.ap.engage(false)
		ac.ap.at_engaged = false
		ac.player_controlled = false
		ac.in_pitch = pitch
		ac.in_roll = 0.15
		ac.throttle_lever = 0.6
	if ac.crashed_state and not _crashed:
		_crashed = true
		Engine.time_scale = 1.0
	var aft := session.get_node_or_null("Aftermath")
	if aft and aft.get("t") != null and float(aft.get("t")) > 40.0 and aft.has_method("_finalize"):
		aft.call("_finalize")
	if not _result.is_empty():
		_save()
		get_tree().quit()
	if t > 2400.0:
		print("TIMEOUT")
		get_tree().quit()


func _save() -> void:
	var r := _result
	var res_copy := r.duplicate(true)
	CareerRules.apply_result(r)
	var crash_clock := WorldSim.clock
	WorldSim.advance(days * 86400.0)
	var data := {"news": News.serialize(), "clock": WorldSim.clock, "crash_clock": crash_clock, "result": res_copy}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("FIXTURE SAVED %s incidents=%d articles=%d posts=%d" % [out_path, News.incidents.size(), News.articles.size(), News.posts.size()])
	for a in News.articles:
		if String(a.get("incident", "")) != "" or String(a.get("story", "")) != "":
			print("  %s [%s] %s %s" % [a.id, a.outlet, a.headline, str(a.get("video", {}))])
