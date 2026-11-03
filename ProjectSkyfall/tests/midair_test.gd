extends Node
## Puts an AI airliner head-on to the player at cruise and checks the mid-air collision:
## both break up, the wreck falls, the ground phase runs and the flight ends as a crash.
## Usage: -- [out_dir]   (out_dir: save frames; needs a display)
var s: FlightSession
var t := 0.0
var spawned := false
var crashed_t := -1.0
var ground_t := -1.0
var out := ""
var shots := 0
var gap := 2600.0
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else ""
	Game.settings.quality = "low"
	Game.settings.tts = false
	Game.settings.graphic_crashes = true
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-MID", "dep": "SKPC", "arr": "SKRV", "start": "air", "alt_ft": 9000.0, "dist_km": 60.0,
		"callsign": "Skyfall 9", "flight_id": "MID", "clock": U.date_to_clock(2027, 6, 14, 12.0)})
	s.ac.crashed.connect(func(info):
		crashed_t = t
		print("CRASHED: ", info.get("cause_hint"), " midair=", info.get("midair"), " sev=", info.get("severity"), " ra=", s.ac.ra))
func _snap(tag: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, shots, tag])
	shots += 1
func _process(delta: float) -> void:
	t += delta
	var tm: TrafficManager = s.traffic
	if not spawned and t > 4.0:
		spawned = true
		var ac := s.ac
		var hdg := fposmod(rad_to_deg(atan2(ac.fdm.vel.x, -ac.fdm.vel.z)), 360.0)
		var d := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
		var p := Vector2(ac.world_x(), ac.world_z()) + d * 2600.0
		tm.airborne.append({"callsign": "Liberty 404", "x": p.x, "z": p.y, "alt": ac.fdm.pos.y + 1.0, "vs": 0.0, "hdg": fposmod(hdg + 180.0, 360.0), "spd": 240.0,
			"type": "s320", "airline": "LBA", "model": null, "phase": "airborne", "hdg_t": fposmod(hdg + 180.0, 360.0), "alt_t": ac.fdm.pos.y + 1.0,
			"bank": 0.0, "react": false, "tcas": false, "called": false, "man_t": 999.0})
		print("spawned head-on traffic 2.6 km ahead")
	if int(t) != int(t - delta):
		var aft := s.get_node_or_null("Aftermath")
		print("%3ds alt=%.0f ra=%.0f falling=%s stage=%s pieces=%d/%d sky=%d" % [int(t), s.ac.fdm.pos.y, s.ac.ra, s.ac.has_meta("falling"),
			aft.stage if aft else "-", s.wreck.falling_count() if s.wreck else 0, s.wreck.pieces.size() if s.wreck else 0, tm.sky_items().size()])
		if out != "" and spawned and (int(t) % 3 == 0):
			_snap("t%d" % int(t))
	if spawned and crashed_t < 0.0:
		# keep the traffic exactly on our flight path, closing at ~250 m/s
		gap -= 125.0 * delta
		for it2 in tm.airborne:
			if String(it2.callsign) == "Liberty 404":
				var vd := s.ac.fdm.vel.normalized()
				it2.x = s.ac.world_x() + vd.x * gap
				it2.z = s.ac.world_z() + vd.z * gap
				it2.alt = s.ac.fdm.pos.y + vd.y * gap
	for it in tm.sky_items():
		var md: float = (it.model as Node3D).global_position.distance_to(s.ac.global_position)
		var wd := Vector3(float(it.x) - s.ac.world_x(), float(it.alt) - s.ac.fdm.pos.y, float(it.z) - s.ac.world_z()).length()
		if md < 400.0 or wd < 400.0:
			print("   close: model_d=%.0f world_d=%.0f" % [md, wd])
	var aft2 := s.get_node_or_null("Aftermath")
	if aft2 and ground_t < 0.0 and String(aft2.stage) in ["settling", "evacuation", "rescue"]:
		ground_t = t
		print("GROUND PHASE at ", int(t), "s severity=", aft2.severity)
	if ground_t > 0.0 and t > ground_t + 8.0:
		_snap("ground")
		aft2.call("_finalize")
		print("RESULT outcome=", s.get("result").get("outcome", "?") if s.get("result") is Dictionary else "?")
		print("MIDAIR TEST DONE")
		get_tree().quit()
	if t > 150.0 or (crashed_t < 0.0 and t > 40.0):
		print("MIDAIR TEST TIMEOUT crashed=", crashed_t)
		get_tree().quit()
