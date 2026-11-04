extends Node3D
## Close-ups of the see-through glazing: cabin windows from the side and the flight deck from
## the front quarter. Usage: -- out_dir [type] [hour]
var view: WorldView

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp"
	var t := a[1] if a.size() > 1 else "s320"
	var hour := float(a[2]) if a.size() > 2 else 14.0
	Game.settings.quality = "high"
	WeatherModel.override_preset = "few"
	view = WorldView.new()
	add_child(view)
	var ap: Dictionary = Airports.get_ap("SKPC")
	var wx := float(ap.x) + 900.0
	var wz := float(ap.z) - 1400.0
	view.setup(wx, wz, U.date_to_clock(2027, 6, 14, hour), true)
	var m := AircraftModel.new()
	view.dynamic_root.add_child(m)
	m.build(t, "SKF", "CR-WIN", 1.0)
	var spec := AircraftTypes.get_type(t)
	m.position = view.world_to_local(wx, Geo.ground_height(wx, wz) + 4.0, wz)
	var cam := Camera3D.new()
	cam.fov = 50.0
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	var lay := CabinLayout.get_layout(t)
	var nose: float = lay.nose_z
	var shots := [
		["cabin", Vector3(-7.5, 0.9, nose * 0.25), Vector3(0, 0.3, nose * 0.25)],
		["cabin_low", Vector3(-5.0, -0.2, nose * 0.05), Vector3(1.0, 0.5, nose * 0.1)],
		["deck", Vector3(-4.5, 1.6, nose - 3.5), Vector3(0, 0.4, nose + 3.0)],
		["deck_front", Vector3(-1.2, 1.4, nose - 6.0), Vector3(0, 0.5, nose + 3.0)],
	]
	for s in shots:
		cam.position = m.position + (s[1] as Vector3)
		cam.look_at(m.position + (s[2] as Vector3), Vector3.UP)
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("win_%s_%s.png" % [t, s[0]]))
	get_tree().quit()
