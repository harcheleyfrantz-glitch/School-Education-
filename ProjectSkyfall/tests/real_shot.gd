extends Node3D
## Views of a real airport's terminal area: wide aerial, closer aerial and a low view along the
## gates. Usage: -- out_dir ICAO[,ICAO] [hour]
var view: WorldView
var cam: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var hour := float(a[2]) if a.size() > 2 else 14.0
	Game.settings.quality = OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "medium"
	Game.apply_settings()
	WeatherModel.override_preset = "few"
	for icao in a[1].split(","):
		var ap: Dictionary = Airports.get_ap(icao)
		var L := AirportLayout.get_layout(icao)
		var c := Vector2.ZERO
		for s in L.stands:
			c += s.facade_origin
		c /= maxf(L.stands.size(), 1)
		var o := Vector2(float(ap.x), float(ap.z))
		var sd: Dictionary = L.stands[L.stands.size() / 2]
		var views := [
			[c, 200.0, 2600.0, 1100.0, "wide"],
			[c, 140.0, 1100.0, 330.0, "close"],
			[(sd.facade_origin as Vector2) + (sd.normal as Vector2) * 60.0, U.dir_to_heading(Vector3(-sd.normal.x, 0, -sd.normal.y)) + 35.0, 260.0, 45.0, "gate"],
		]
		var only := a[3].split(",") if a.size() > 3 else PackedStringArray()
		for vw in views:
			if not only.is_empty() and not String(vw[4]) in only:
				continue
			var tgt: Vector2 = o + (vw[0] as Vector2)
			var hdg: float = vw[1]
			var back := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
			var ty := float(ap.elev)
			var from := Vector3(tgt.x - back.x * float(vw[2]), ty + float(vw[3]), tgt.y - back.y * float(vw[2]))
			if view == null:
				view = WorldView.new()
				add_child(view)
				view.setup(from.x, from.z, U.date_to_clock(2027, 6, 14, hour), true)
				cam = Camera3D.new()
				add_child(cam)
				cam.far = 120000.0
				cam.current = true
				view.camera = cam
			cam.position = view.world_to_local(from.x, from.y, from.z)
			cam.look_at(view.world_to_local(tgt.x, ty + 10.0, tgt.y), Vector3.UP)
			cam.fov = 55.0
			for i in 8:
				await get_tree().process_frame
			await view.warm_up(40.0)
			for i in 20:
				await get_tree().process_frame
			# the floating origin may have moved while the view warmed up: pose the camera again
			cam.position = view.world_to_local(from.x, from.y, from.z)
			cam.look_at(view.world_to_local(tgt.x, ty + 10.0, tgt.y), Vector3.UP)
			await view.warm_up(20.0)
			for i in 10:
				await get_tree().process_frame
			cam.position = view.world_to_local(from.x, from.y, from.z)
			cam.look_at(view.world_to_local(tgt.x, ty + 10.0, tgt.y), Vector3.UP)
			for i in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("real_%s_%s.png" % [icao, vw[4]]))
			print("shot ", icao, " ", vw[4])
		view.queue_free()
		view = null
		await get_tree().process_frame
	get_tree().quit()
