extends Node
## Third-person walking: the player's skinned pilot on the apron at golden hour and in the cabin.
## Usage: -- <out_dir> [type] [hour]

var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var type_id := a[1] if a.size() > 1 else "s320"
	var hour := float(a[2]) if a.size() > 2 else 18.4
	Game.settings.quality = "medium"
	Game.settings.tts = false
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	Game.player.appearance = {"skin": 4, "hair_color": 0, "hair": 4, "build": 0.82}
	var s := FlightSession.new()
	add_child(s)
	s.start({"mode": "pilot", "type": type_id, "airline": String(Game.player.airline), "reg": "CR-TPV", "dep": "SKPC", "arr": "SKRV",
		"callsign": "Skyfall 451", "flight_id": "TP-1", "start": "gate", "instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, hour)})
	await s.view.warm_up(10.0)
	var hud := s.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	s.walk_to_apron()
	s.rig.toggle_third_person()
	s.walker.yaw += deg_to_rad(150.0)
	s.walker.move_input = Vector2(0, 1)
	await _wait(2.5)
	_shot("tp_apron_walk")
	s.walker.move_input = Vector2.ZERO
	s.walker.yaw -= deg_to_rad(120.0)
	await _wait(1.5)
	_shot("tp_apron_idle")
	s.walker.running = true
	s.walker.move_input = Vector2(0, 1)
	await _wait(1.2)
	_shot("tp_apron_run")
	s.walker.move_input = Vector2.ZERO
	s.end_walk("cockpit")
	await _wait(0.5)
	s.toggle_walk()
	s.walker.yaw = 0.0
	s.walker.move_input = Vector2(0, -1)
	await _wait(2.0)
	s.walker.move_input = Vector2.ZERO
	await _wait(0.6)
	_shot("tp_cabin")
	get_tree().quit()


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
