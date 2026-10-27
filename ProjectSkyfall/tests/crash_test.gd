extends Node
## Headless crash pipeline: a pilot-mode flight is flown into the ground on approach, then the
## aftermath, investigation, career consequences and the evolving news story are printed.
## godot --headless --fixed-fps 60 --path . res://tests/crash_test.tscn -- [type] [pitch] [severity_hint]

var session: FlightSession
var t := 0.0
var _result := {}
var pitch := -0.45
var scenario := "dive"
var _crashed := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var type_id := a[0] if a.size() > 0 else "s320"
	pitch = float(a[1]) if a.size() > 1 else -0.45
	scenario = a[2] if a.size() > 2 else "dive"
	Game.settings.quality = "low"
	Game.settings.tts = false
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.toast.connect(func(tx, k): print("  [toast:%s] %s" % [k, tx]))
	session.finished.connect(func(r): _result = r)
	var belly := scenario == "belly"
	session.start({"mode": "passenger" if belly else "pilot", "type": type_id, "airline": String(Game.player.airline), "reg": "CR-CRT", "dep": "SKPC", "arr": "SKRV",
		"callsign": "Skyfall 451", "flight_id": "CRASH-%s-%s" % [type_id, scenario], "start": "air", "alt_ft": float(OS.get_environment("ALT")) if OS.get_environment("ALT") != "" else (6000.0 if belly else 2500.0), "dist_km": float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else (40.0 if belly else 12.0),
		"instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, 15.0)})
	if belly:
		Engine.time_scale = 4.0
	print("session started, pax=%d" % (session.people.pax.size() if session.people else 0))


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
		print("%5.1fs CRASH info=%s" % [t, str(session.crash_info)])
	if int(t * 2.0) != int((t - delta) * 2.0) and int(t) % 5 == 0 and not _crashed:
		var n := ac.nav_state()
		print("%5.1fs alt=%5.0fft ias=%3.0f vs=%5.0f pitch=%4.1f" % [t, float(n.alt) / U.FT, n.ias_kt, float(n.vs) / U.FPM, float(n.pitch)])
	var aft := session.get_node_or_null("Aftermath")
	if aft and int(t) % 10 == 0 and int(t * 2.0) != int((t - delta) * 2.0):
		var pp := session.people
		print("%5.1fs aftermath stage=%s fire=%.2f exited=%d evac=%d trapped=%d assembled=%d" % [t, aft.get("stage"), float(aft.get("fire_level")),
			pp.count_state("exited"), pp.count_state("evac"), pp.count_state("trapped"), session.ground_ops.assembled_count() if session.ground_ops else -1])
		var ov = aft.get("_overlay")
		if aft.get("t") != null and float(aft.get("t")) > 150.0 and aft.has_method("_finalize"):
			aft.call("_finalize")
	if not _result.is_empty():
		_report()
		get_tree().quit()
	if t > 2400.0:
		print("TIMEOUT")
		get_tree().quit()


func _report() -> void:
	var r := _result
	print("===== RESULT =====")
	print("outcome=%s" % r.outcome)
	var af: Dictionary = r.get("aftermath", {})
	print("counts=%s place=%s" % [str(af.get("counts", {})), af.get("place", "")])
	for v in af.get("victims", []).slice(0, 5):
		print("  victim: %s (%d) %s" % [v.name, int(v.age), v.home])
	var inv: Dictionary = r.get("investigation", {})
	print("probable cause: %s" % inv.get("probable_cause", ""))
	for f in inv.get("findings", []):
		print("  finding: %s" % f)
	print("shares=%s blame=%s negligent=%s" % [str(inv.get("shares", {})), inv.get("blame", ""), inv.get("negligent", "")])
	var cons := CareerRules.apply_result(r)
	print("consequences: dead=%s licence=%s susp=%s employment=%s criminal=%s" % [cons.get("dead"), cons.get("licence", cons.get("license", "")),
		cons.get("suspension_days", cons.get("suspension", "")), cons.get("employment", ""), cons.get("criminal", "")])
	for m in cons.get("messages", []):
		print("  msg: %s" % m)
	print("player status=%s licence=%s rep=%.0f" % [Game.player.get("status", "?"), Game.player.get("license", "?"), float(Game.player.get("reputation", 0.0))])
	print("--- news now ---")
	for art in News.latest(8):
		print("  [%s] %s" % [art.get("outlet", ""), art.get("headline", "")])
	var shown := {}
	for d in [1, 3, 10, 40, 400]:
		WorldSim.advance(float(d) * 86400.0)
		print("--- news after +%d days (%d articles total) ---" % [d, News.articles.size()])
		for art2 in News.articles:
			if (String(art2.get("story", "")) != "" or String(art2.get("incident", "")) != "") and not shown.has(art2.id):
				shown[art2.id] = true
				print("  %s [%s] %s" % [U.fmt_date(float(art2.t)), art2.get("outlet", ""), art2.get("headline", "")])
	print("social posts: %d" % News.feed(200).size())
	for p in News.feed(6):
		print("  %s: %s" % [str(p.get("author", {}).get("handle", p.get("author", {}).get("name", "?"))), String(p.get("text", "")).left(110)])
