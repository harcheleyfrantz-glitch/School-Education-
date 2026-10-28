extends Node
## Renders the terminal interior from several spots for visual checks.
## Usage: -- <out_dir> [icao] [hour]
var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var icao := a[1] if a.size() > 1 else "SKPC"
	var hour := float(a[2]) if a.size() > 2 else 11.0
	Game.settings.quality = "medium"
	Game.settings.tts = false
	var s := FlightSession.new()
	add_child(s)
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-TRM", "dep": icao, "arr": "SKRV" if icao != "SKRV" else "SKPC",
		"callsign": "Skyfall 451", "flight_id": "TERM-%s" % icao, "start": "gate", "instant_boarding": true,
		"clock": U.date_to_clock(2027, 6, 14, hour)})
	await s.view.warm_up(10.0)
	var av: AirportView = s.view.airports.get_view(icao)
	var t0 := Time.get_ticks_msec()
	var ti := av.build_terminal_interior()
	print("interior built in %d ms: %d gates, %d seats, %d obstacles, %d spots" % [Time.get_ticks_msec() - t0, ti.gates.size(), ti.seats.size(), ti.obstacles.size(), ti.spots.size()])
	var hud := s.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	s.rig.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	var g: Dictionary = ti.gate(s.stand)
	if g.is_empty():
		g = ti.gates[0]
	var sd: float = g.s
	var door: Vector3 = g.door
	var conc_x := sd * (ti.depth * 0.5 - (24.0 if ti.hub else 18.0) - (6.5 if ti.hub else 4.5))
	var shots := [
		["gate", door + Vector3(-sd * 13.0, 1.65, 7.0), door + Vector3(sd * 10.0, 0.2, -3.0)],
		["lounge", Vector3(door.x - sd * 3.0, ti.FLOOR + 1.65, float(g.z) - 14.0), Vector3(door.x - sd * 14.0, ti.FLOOR + 1.0, float(g.z) + 10.0)],
		["concourse", Vector3(conc_x, ti.FLOOR + 1.7, float(g.z) - 40.0), Vector3(conc_x, ti.FLOOR + 1.6, float(g.z) + 40.0)],
	]
	if not ti.sec.is_empty():
		var lanes: Array = ti.sec.lanes
		var lz: float = lanes[0] if lanes.size() > 0 else 0.0
		if String(ti.sec.axis) == "x":
			var xl: float = ti.sec.at
			shots.append(["security", Vector3(xl + ti.land_s * 12.0, ti.FLOOR + 1.7, lz - 6.0), Vector3(xl, ti.FLOOR + 1.0, lz + 4.0)])
			shots.append(["checkin", Vector3(xl + ti.land_s * 4.0, ti.FLOOR + 1.7, 20.0), Vector3(ti.land_s * ti.depth * 0.5, ti.FLOOR + 2.0, -10.0)])
	for sp in ti.spots:
		if String(sp.kind) == "cafe":
			var p: Vector3 = sp.p
			shots.append(["cafe", p + Vector3(-sd * 8.0, 1.65, -6.0), p + Vector3(sd * 2.0, 0.8, 2.0)])
			break
	for sp2 in ti.spots:
		if String(sp2.kind) == "fids":
			var p2: Vector3 = sp2.p
			var bd: Vector3 = sp2.board
			var back := Vector3(p2.x - bd.x, 0, p2.z - bd.z).normalized()
			shots.append(["fids", p2 + back * 1.5 + Vector3(0, 1.65, 0), bd])
			break
	for sh in shots:
		var from: Vector3 = ti.global_transform * (sh[1] as Vector3)
		var to: Vector3 = ti.global_transform * (sh[2] as Vector3)
		cam.global_position = from
		cam.look_at(to, Vector3.UP)
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("term_%s_%s.png" % [icao, sh[0]]))
		print("shot ", sh[0])
	get_tree().quit()
