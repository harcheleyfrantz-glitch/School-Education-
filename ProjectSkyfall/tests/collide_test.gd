extends Node
## Drives the player's aircraft at the terminal from its gate to check that it crashes.
var s: FlightSession
var t := 0.0
func _ready() -> void:
	Game.settings.quality = "low"
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-COL", "dep": "SKPC", "arr": "SKRV", "start": "gate",
		"callsign": "Skyfall 9", "flight_id": "COL", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	s.ac.crashed.connect(func(info): print("CRASHED: ", info.get("cause_hint"), " at ", int(info.speed_kt), " kt"))
	Input.action_press("throttle_up")
func _process(delta: float) -> void:
	t += delta
	if int(t) != int(t - delta):
		print("%3ds gs=%.1f crashed=%s" % [int(t), s.ac.fdm.ground_speed(), s.ac.crashed_state])
	if s.ac.crashed_state or t > 40.0:
		get_tree().quit()
