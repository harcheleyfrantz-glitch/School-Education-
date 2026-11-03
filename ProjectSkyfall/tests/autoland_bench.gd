extends Node
## Auto-fly landing quality: starts on a long final with auto-fly on and records the touchdown.
## Usage: -- type airport weather [dist_km]   prints LANDING type wx vs centreline dist go_arounds
var s: FlightSession
var done := false
var res := {}

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var type_id := a[0] if a.size() > 0 else "s320"
	var arr := a[1] if a.size() > 1 else "SKRV"
	var wx := a[2] if a.size() > 2 else "few"
	var dist := float(a[3]) if a.size() > 3 else 22.0
	Game.settings.tts = false
	Game.settings.quality = "potato"
	Game.settings.event_rate = "off"
	WeatherModel.override_preset = wx
	if wx == "crosswind":
		var e := Airports.best_runway(arr, 0.0, 0.0)
		WeatherModel.override_dir = fposmod(float(e.get("hdg", 0.0)) + 70.0, 360.0)
	s = FlightSession.new()
	add_child(s)
	s.finished.connect(func(r): res = r; done = true)
	var dep := "SKPC" if arr != "SKPC" else "SKRV"
	if Airports.get_ap(arr).get("region", "") == "world":
		dep = "KJFK" if arr != "KJFK" else "KBOS"
	s.start({"mode": "pilot", "type": type_id, "airline": "SKF", "reg": "CR-ALB", "dep": dep, "arr": arr, "callsign": "Skyfall 7",
		"flight_id": "ALB", "start": "air", "alt_ft": 3000.0 if dist < 30.0 else 5000.0, "dist_km": dist, "weather": wx, "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	await s.view.warm_up(3.0)
	s.set_autofly(true)
	var t := 0.0
	while not done and t < 900.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if s.ai and s.ai.phase in ["landed"] or s.ac.crashed_state:
			break
		if OS.get_environment("TRACE2") != "" and int(t) % 15 == 0 and int(t) != int(t - 1.0 / 60.0):
			var nv := s.ac.nav_state()
			print("   p=%.1f op=%.1f tp=%.1f a=%.1f as=%.1f t=%d ai=%s ra=%.0f dthr=%.0f ias=%.0f bank=%.0f lat=%s vert=%s leg=%d/%d xte=%.0f hdg=%.0f trk=%.0f outbank=%.0f bl=%.0f eng=%s alt=%.0f sel=%.0f thr=%.2f" % [nv.pitch, s.ac.ap.out_pitch, s.ac.laws.target_pitch, rad_to_deg(s.ac.fdm.alpha), rad_to_deg(s.ac.fdm.alpha_stall), int(t), s.ai.phase, s.ac.ra,
				s.ac.ap.dist_thr, nv.true_ias_kt, nv.bank, s.ac.ap.lat_mode, s.ac.ap.vert_mode, s.ac.ap.leg, s.ac.ap.plan.size(), s.ac.ap.xte, s.ac.fdm.heading_deg(), nv.track,
				s.ac.ap.out_bank, s.ac.ap.bank_limit, s.ac.ap.engaged, s.ac.fdm.pos.y, s.ac.ap.alt_sel, s.ac.throttle_lever])
		if OS.get_environment("TRACE") != "" and s.ac.ra < 40.0 and s.ac.ra > -1.0 and s.touchdown.is_empty() and int(t * 4.0) != int((t - 1.0 / 60.0) * 4.0):
			var n := s.ac.nav_state()
			print("   ra %5.1f vs %5.2f pitch %5.2f fp %5.2f tgt %5.2f thr %4.2f ias %5.1f vapp %d mode %s/%s ai %s dthr %5.0f" % [s.ac.ra, n.vs, n.pitch, s.ac.ap.flare_pitch, s.ac.ap.out_pitch,
				s.ac.throttle_lever, n.true_ias_kt, int(s.ac.spec.vapp), s.ac.ap.vert_mode, s.ac.ap.thr_mode, s.ai.phase, s.ac.ap.dist_thr])
	var td: Dictionary = s.touchdown
	if s.ac.crashed_state:
		print("CRASH INFO ", s.ac.crash_info.get("cause_hint", ""), " speed ", int(float(s.ac.crash_info.get("speed_kt", 0.0))), " surface ", s.ac.crash_info.get("surface", ""))
	print("END ai=%s phase=%s" % [s.ai.phase if s.ai else "-", s.phase])
	print("LANDING %-6s %-5s %-10s vs=%5.0f cl=%5.1f thr=%5.0f bank=%4.1f pitch=%4.1f ga=%d crashed=%s t=%.0f" % [type_id, arr, wx, absf(float(td.get("vs_fpm", -1.0))),
		float(td.get("centerline", 0.0)), float(td.get("dist_from_thr", -1.0)), float(td.get("bank", 0.0)), float(td.get("pitch", 0.0)),
		s.ai.go_around_count if s.ai else -1, s.ac.crashed_state, t])
	get_tree().quit()
