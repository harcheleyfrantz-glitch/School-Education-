extends Node
## Unlimited skip: from the gate, press skip every few seconds until the flight is over.
var s: FlightSession
var done := false
func _ready() -> void:
	Game.settings.tts = false
	Game.settings.quality = "potato"
	Game.new_character({"first": "Sam", "last": "Lee", "name": "Sam Lee", "gender": "m", "age": 33, "path": "regional_fo"})
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): if String(tx).begins_with("Skipped"): print("  [toast] ", tx))
	s.finished.connect(func(res): print("FINISHED outcome=%s vs=%s" % [res.get("outcome", "?"), res.get("touchdown", {}).get("vs_fpm", "?")]); done = true)
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-SKP", "dep": "SKPC", "arr": "SKRV", "callsign": "Skyfall 3",
		"flight_id": "SKIP", "start": "gate", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	await s.view.warm_up(3.0)
	var t := 0.0
	var next := 2.0
	while not done and t < 400.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > next:
			next = t + 6.0
			print("%4.0fs phase=%s ai=%s ra=%.0f crashed=%s -> skip" % [t, s.phase, s.ai.phase if s.ai else "-", s.ac.ra, s.ac.crashed_state])
			s.skip_ahead()
	print("SKIP TEST DONE")
	get_tree().quit()
