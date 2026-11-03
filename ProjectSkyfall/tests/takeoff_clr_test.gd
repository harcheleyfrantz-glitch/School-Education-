extends Node
## Lined up on the runway without calling the tower: the clearance must come by itself and the
## takeoff must not be a deviation.
var s: FlightSession
func _ready() -> void:
	Game.settings.tts = false
	Game.settings.quality = "potato"
	s = FlightSession.new()
	add_child(s)
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-TOC", "dep": "SKPC", "arr": "SKRV", "start": "runway", "callsign": "Skyfall 5",
		"flight_id": "TOC", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	s.atc.transmission.connect(func(st, who, tx): print("  [radio] %s: %s" % [st, tx]))
	await s.view.warm_up(2.0)
	s.ac.sys.parking_brake = false
	var t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 6.0:
			s.ac.throttle_lever = 1.0
	print("cleared=", s.atc.clearance.takeoff, " airborne=", not s.ac.fdm.on_ground, " deviations=", s.deviations.map(func(d): return "%s %.1f" % [d.text, d.severity]))
	print("TAKEOFF CLR TEST DONE")
	get_tree().quit()
