extends Node
## Ground-level views of an airport's kerbside and jet bridges for visual checks.
## Usage: -- <out_dir> [icao] [hour]
## Saves kerb_<icao>_{street,deck,flags,bridge,bridges,gse}.png
const Landside := preload("res://src/world/models/airports/landside.gd")
var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var icao := a[1] if a.size() > 1 else "KMIA"
	var hour := float(a[2]) if a.size() > 2 else 16.5
	Game.settings.quality = "medium"
	Game.settings.tts = false
	var s := FlightSession.new()
	add_child(s)
	s.start({"mode": "pilot", "type": "s320", "airline": "SKF", "reg": "CR-KRB", "dep": icao, "arr": "SKRV" if icao != "SKRV" else "SKPC",
		"callsign": "Skyfall 452", "flight_id": "KERB-%s" % icao, "start": "gate", "instant_boarding": true,
		"clock": U.date_to_clock(2027, 6, 14, hour)})
	await s.view.warm_up(10.0)
	var av: AirportView = s.view.airports.get_view(icao)
	var hud := s.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	s.rig.set_process(false)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1
	cam.far = 20000.0
	add_child(cam)
	cam.current = true
	var L: Dictionary = av.layout
	var term: Dictionary = {}
	for b in L.buildings:
		if String(b.kind) == "terminal":
			term = b
			break
	var fr: Dictionary = Landside._kerb_frame(L, term)
	var o: Vector2 = fr.origin
	var out: Vector2 = fr.out
	var al: Vector2 = fr.along
	var w1 := 26.0 if bool(fr.end) else 15.0
	var hw: float = fr.hw
	var shots := []
	var P := func(x: float, z: float, y: float) -> Vector3:
		var p2: Vector2 = o + out * x + al * z
		return Vector3(p2.x, y, p2.y)
	shots.append(["street", P.call(w1 + 30.0, -hw * 0.75, 1.7), P.call(w1 - 5.0, hw * 0.1, 3.0)])
	shots.append(["flags", P.call(w1 + 52.0, hw * 0.2, 1.8), P.call(w1 * 0.3, -hw * 0.25, 4.0)])
	shots.append(["deck", P.call(w1 - 3.0, -hw * 0.6, 6.2), P.call(w1 + 6.0, hw * 0.2, 5.0)])
	shots.append(["overview", P.call(w1 + 140.0, -hw * 1.2, 45.0), P.call(0.0, 0.0, 6.0)])
	# jet bridges: our stand and its neighbours from the apron
	var st: Dictionary = av.stand_local(s.stand)
	if not st.is_empty():
		var fo: Vector2 = st.facade_origin
		var nn: Vector2 = st.normal
		var lf := Vector2(-nn.y, nn.x)
		var Q := func(x: float, z: float, y: float) -> Vector3:
			var p3: Vector2 = fo + nn * z + lf * x
			return Vector3(p3.x, y, p3.y)
		shots.append(["bridge", Q.call(22.0, 30.0, 3.0), Q.call(4.0, 9.0, 4.5)])
		shots.append(["bridges", Q.call(-30.0, 75.0, 22.0), Q.call(40.0, 5.0, 4.0)])
		shots.append(["gse", Q.call(-12.0, 32.0, 2.2), Q.call(-34.0, 6.0, 1.5)])
	for sh in shots:
		var from: Vector3 = av.global_transform * (sh[1] as Vector3)
		var to: Vector3 = av.global_transform * (sh[2] as Vector3)
		cam.global_position = from
		cam.look_at(to, Vector3.UP)
		for i in 24:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("kerb_%s_%s.png" % [icao, sh[0]]))
		print("shot ", sh[0])
	get_tree().quit()
