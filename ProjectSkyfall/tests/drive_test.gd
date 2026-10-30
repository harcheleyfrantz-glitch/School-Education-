extends Node
## Presses W at the gate like a player would and checks the aircraft starts moving.
var s: FlightSession
var t := 0.0
func _ready() -> void:
	Game.settings.quality = "low"
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-DRV", "dep": "SKPC", "arr": "SKRV", "start": "runway",
		"callsign": "Skyfall 1", "flight_id": "DRV", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	Input.action_press("throttle_up")
func _process(delta: float) -> void:
	t += delta
	if t > 3.0:
		Input.action_release("throttle_up")
	if int(t * 2.0) != int((t - delta) * 2.0):
		print("%4.1fs thr=%.2f eng=%d pk=%s gs=%.1f" % [t, s.ac.throttle_lever, s.ac.sys.running_engines(), s.ac.sys.parking_brake, s.ac.fdm.ground_speed()])
	if t > 20.0:
		get_tree().quit()
