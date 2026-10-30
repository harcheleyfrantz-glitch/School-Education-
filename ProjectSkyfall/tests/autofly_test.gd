extends Node
## Pilot flight from the runway with auto-fly on: takeoff, skip ahead, approach and landing.
## With a crash target the aircraft is flown into it instead.
## Usage: -- [route|city|terminal|sea|mountain|ahead] [type]

var s: FlightSession
var done := false

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var target := a[0] if a.size() > 0 else "route"
	var type_id := a[1] if a.size() > 1 else "s320"
	Game.settings.tts = false
	Game.settings.quality = "potato"
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.finished.connect(func(res): print("FINISHED outcome=%s" % res.get("outcome", "?")); done = true)
	s.start({"mode": "pilot", "type": type_id, "airline": "SKF", "reg": "CR-AFT", "dep": "SKPC", "arr": "SKRV", "callsign": "Skyfall 12",
		"flight_id": "AF-1", "start": "runway", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	await s.view.warm_up(5.0)
	s.set_autofly(true)
	var t := 0.0
	var skipped := false
	var targeted := false
	var last := -100.0
	while not done and t < 3600.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * Engine.time_scale
		if not targeted and s.ac.ra > 400.0 and target != "route":
			targeted = true
			s.set_crash_target(target)
		if not skipped and s.ac.ra > 900.0:
			skipped = true
			s.skip_ahead()
		var dd := Vector2(s.ac.world_x(), s.ac.world_z()).distance_to(Vector2(s._crash_pt.x, s._crash_pt.z)) if s._crash_pt != Vector3.ZERO else 1e9
		if dd < 4000.0 and int(t * 2.0) != int((t - 1.0 / 60.0 * Engine.time_scale) * 2.0):
			print("   dive dist %5.0f agl %5.0f vs %6.1f sel %6.1f hdg %5.1f sel %5.1f ias %3.0f" % [dd, s.ac.fdm.pos.y - s._crash_pt.y, s.ac.fdm.vel.y, s.ac.ap.vs_sel, s.ac.fdm.heading_deg(), s.ac.ap.hdg_sel, s.ac.fdm.ias / U.KT])
		if t - last > 30.0:
			last = t
			print("%6.0fs phase %-10s ai %-10s alt %5.0f ra %5.0f ias %3.0f crashed %s" % [t, s.phase, s.ai.phase if s.ai else "-", s.ac.fdm.pos.y, s.ac.ra, s.ac.nav_state().ias_kt, s.ac.crashed_state])
		if s.ac.crashed_state and not done:
			print("CRASHED at %s, %.0f m from target, meta %s" % [Geo.place_name(s.ac.world_x(), s.ac.world_z()), Vector2(s.ac.world_x(), s.ac.world_z()).distance_to(Vector2(s._crash_pt.x, s._crash_pt.z)), s.ac.get_meta_list().map(func(k): return "%s=%s" % [k, s.ac.get_meta(k)])])
			done = true
		if target == "route" and s.ai and s.ai.phase == "landed":
			print("LANDED at t=%.0f" % t)
			done = true
	print("AUTOFLY TEST DONE")
	get_tree().quit()
