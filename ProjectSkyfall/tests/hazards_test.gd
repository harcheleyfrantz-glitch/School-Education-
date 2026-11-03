extends Node
## Natural hazards: -- ash   (all engines flame out in volcanic ash, relight below the ash)
##                   -- quake (an earthquake near the arrival airport while on approach)
var s: FlightSession
var t := 0.0
var mode := "ash"
var dropped := false
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	mode = a[0] if a.size() > 0 else "ash"
	Game.settings.quality = "low"
	Game.settings.tts = false
	WeatherModel.override_preset = "volcanic_ash" if mode == "ash" else "earthquake"
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	if mode == "ash":
		s.start({"mode": "pilot", "type": "w350", "airline": "THA", "reg": "G-ASHH", "dep": "EGLL", "arr": "BIKF", "start": "air", "alt_ft": 30000.0, "dist_km": 120.0,
			"callsign": "Thames 9", "flight_id": "ASH", "weather": "volcanic_ash", "clock": U.date_to_clock(2027, 6, 14, 22.5)})
	else:
		s.start({"mode": "pilot", "type": "s320", "airline": "GGP", "reg": "N320GG", "dep": "KLAX", "arr": "KSFO", "start": "air", "alt_ft": 4000.0, "dist_km": 30.0,
			"callsign": "Golden Gate 5", "flight_id": "QUAKE", "weather": "earthquake", "clock": U.date_to_clock(2027, 6, 14, 11.0)})
	s.ac.crashed.connect(func(info): print("CRASHED: ", info.get("cause_hint")))
func _process(delta: float) -> void:
	t += delta
	if s.hazards and mode == "quake" and t > 3.0 and s.hazards._quake_t > 5.0:
		s.hazards._quake_t = 2.0
	if int(t) != int(t - delta):
		var run := 0
		for e in s.ac.sys.eng:
			if bool(e.running):
				run += 1
		print("%3ds alt=%.0f engines_running=%d quake=%s fx=%d" % [int(t), s.ac.fdm.pos.y, run, str(not s.hazards.quake.is_empty()) if s.hazards else "-", s.hazards._fx.size() if s.hazards else 0])
	if mode == "ash" and s.hazards and s.hazards._ash_stage == 2 and not dropped and t > 48.0:
		dropped = true
		s.ac.fdm.pos.y = 2200.0
		print("descended below the ash")
	if t > (75.0 if mode == "ash" else 60.0):
		print("SUMMARY ", s.hazards.summary() if s.hazards else {})
		print("HAZARDS TEST DONE")
		get_tree().quit()
