extends Node
## Presidential flight with tornado weather: escorts join, a drone is intercepted, tornadoes
## spawn; then the player is flown into an escort and the presidential news is checked.
var s: FlightSession
var t := 0.0
var rammed := false
var last_res := {}
func _ready() -> void:
	Game.settings.quality = "low"
	Game.settings.tts = false
	WeatherModel.override_preset = "tornado"
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.start({"mode": "pilot", "type": "w380", "airline": "GOV", "reg": "CR-GOV", "dep": "SKPC", "arr": "SKRV", "start": "air", "alt_ft": 6000.0, "dist_km": 50.0,
		"callsign": "Calderra One", "flight_id": "PRES", "presidential": true, "weather": "tornado", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	s.finished.connect(func(r): last_res = r)
	s.ac.crashed.connect(func(info): print("CRASHED: ", info.get("cause_hint")))
	print("safety: VTX ", Airlines.safety_label("VTX"), "  AUR ", Airlines.safety_label("AUR"), "  IHA w=", Airlines.crash_weight("IHA"), " AUR w=", Airlines.crash_weight("AUR"))
func _process(delta: float) -> void:
	t += delta
	var e: Escorts = s.escorts
	if e and t > 8.0 and e._threat_t > 3.0 and e.intercepts == 0 and e.threats.is_empty():
		e._threat_t = 1.0
	if int(t) != int(t - delta) and e:
		print("%3ds jets=%s threats=%d intercepts=%d tornadoes=%d" % [int(t), str(e.jets.map(func(j): return j.state)), e.threats.size(), e.intercepts,
			s.view.dynamic_root.get_children().filter(func(c): return c is Tornado).size()])
	if e and e.intercepts >= 1 and not rammed:
		rammed = true
		var j: Dictionary = e.jets[0]
		(j.node as Node3D).global_position = s.ac.global_position + Vector3(0, 0, 0.5)
		print("ramming escort")
	if s.ended or t > 150.0:
		if not last_res.is_empty():
			News.on_flight_result(last_res, {"dead": true})
		for a in News.articles.slice(maxi(News.articles.size() - 8, 0)):
			print("  ARTICLE ", a.headline)
		print("SPECIAL TEST DONE ended=", s.ended)
		get_tree().quit()
	var aft := s.get_node_or_null("Aftermath")
	if aft and String(aft.stage) == "evacuation" and aft.t > 2.0:
		aft.call("_finalize")
