extends Node
## Headless end-to-end flight session. Usage:
## godot --headless --fixed-fps 60 --path . res://tests/session_test.tscn -- [mode] [type] [dep] [arr] [start] [max_minutes]

var session: FlightSession
var t := 0.0
var max_t := 7200.0
var _next := 0.0
var _last_phase := ""
var _result := {}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var mode := a[0] if a.size() > 0 else "passenger"
	var type_id := a[1] if a.size() > 1 else "s320"
	var dep := a[2] if a.size() > 2 else "SKPC"
	var arr := a[3] if a.size() > 3 else "SKRV"
	var start := a[4] if a.size() > 4 else "gate"
	max_t = (float(a[5]) if a.size() > 5 else 120.0) * 60.0
	Game.settings.quality = "low"
	var al := "SKF"
	for c in Airlines.all_codes():
		if Airlines.operates_type(c, type_id):
			al = c
			break
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.toast.connect(func(tx, k): print("  [toast:%s] %s" % [k, tx]))
	session.finished.connect(func(r): _result = r)
	session.start({"mode": mode, "type": type_id, "airline": al, "reg": "CR-TST", "dep": dep, "arr": arr, "callsign": "Skyfall 451",
		"flight_id": "TEST-%s-%s" % [type_id, dep], "start": start, "instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, 10.0)})
	session.atc.transmission.connect(func(st, who, tx): print("  [%s %s] %s" % [st, who, tx]))
	Engine.time_scale = float(OS.get_environment("TS")) if OS.get_environment("TS") != "" else 3.0
	print("session started: %s %s %s->%s stand=%s arr_stand=%s" % [mode, type_id, dep, arr, session.stand, session.arr_stand])


func _process(delta: float) -> void:
	if session == null:
		return
	t += delta
	if session.phase != _last_phase:
		_last_phase = session.phase
		print("%6.0fs PHASE %s" % [t, session.phase])
	if t >= _next:
		_next += 20.0
		var ac := session.ac
		var n := ac.nav_state()
		print("%6.0fs %-12s ai=%-12s taxi=%-8s alt=%5.0fft ias=%3.0f gs=%4.1f hdg=%3.0f thr=%.2f brk=%.2f pk=%s eng=%d ra=%.0f atc=%s tug=%s veh=%d" % [
			t, session.phase, session.ai.phase if session.ai else "-", session.ai_taxi.stage if session.ai_taxi else "-",
			float(n.alt) / U.FT, n.ias_kt, ac.fdm.ground_speed(), n.hdg, ac.throttle_lever, ac.sys.brake_input,
			ac.sys.parking_brake, ac.sys.running_engines(), ac.ra, session.atc.state, session.ground_ops.tug_state,
			session.ground_ops.vehicles.size()])
		if session.ai_taxi and not session.ai_taxi.pts.is_empty():
			print("        pos=(%.0f,%.0f) pts=%s tiller=%.2f" % [ac.world_x(), ac.world_z(), str(session.ai_taxi.pts.slice(0, 4)), ac.in_tiller])
	if not _result.is_empty():
		print("===== RESULT =====")
		print("outcome=%s grade=%s score=%.0f hours=%.2f td=%s notes=%s" % [_result.outcome, _result.grade, _result.score, _result.hours, str(_result.touchdown.get("vs_fpm", "-")), str(_result.notes)])
		get_tree().quit()
	elif t > max_t:
		print("===== TIMEOUT at phase %s =====" % session.phase)
		get_tree().quit()
