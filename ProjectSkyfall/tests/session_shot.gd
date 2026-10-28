extends Node
## Renders a live flight session from several cameras for visual checks.
## Usage: -- <out_dir> [gate|air] [type] [hour]
var out_dir := "/tmp"


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var start := a[1] if a.size() > 1 else "gate"
	var type_id := a[2] if a.size() > 2 else "s320"
	var hour := float(a[3]) if a.size() > 3 else 10.0
	Game.settings.quality = "medium"
	Game.settings.tts = false
	var al := "SKF"
	for c in Airlines.all_codes():
		if Airlines.operates_type(c, type_id):
			al = c
			break
	var mode := "passenger" if start == "pax" else "pilot"
	var s := FlightSession.new()
	add_child(s)
	s.start({"mode": mode, "type": type_id, "airline": al, "reg": "CR-SHT", "dep": "SKPC", "arr": "SKRV", "callsign": "Skyfall 451",
		"flight_id": "SHOT-%s" % type_id, "start": "air" if start == "air" else "gate", "alt_ft": 7000.0, "dist_km": 45.0,
		"instant_boarding": true, "clock": U.date_to_clock(2027, 6, 14, hour)})
	await s.view.warm_up(10.0)
	var dbg := OS.get_environment("DBG")
	if dbg != "":
		s.view.set_process(false)
		s.set_process(false)
		match dbg:
			"nofog": s.view.env.fog_enabled = false
			"noglow": s.view.env.glow_enabled = false
			"nosun": s.view.sun.visible = false
			"noamb": s.view.env.ambient_light_energy = 0.0
			"nolights": s.cabin.set_light_mode("off")
			"noext": s.ac.model.exterior.visible = false
			"near": s.rig.cam.near = 0.1
			"grey", "grey_nosun", "grey_noprobe":
				s.cabin.mat_shell.vertex_color_use_as_albedo = false
				s.cabin.mat_shell.albedo_color = Color(0.5, 0.5, 0.5)
				if dbg == "grey_nosun":
					s.view.sun.light_energy = 0.0
				if dbg == "grey_noprobe":
					var pb: ReflectionProbe = s.cabin.get_node("InteriorProbe")
					pb.ambient_color_energy = 0.0
					pb.intensity = 0.0
			"lights":
				for n in get_tree().root.find_children("*", "Light3D", true, false):
					var l := n as Light3D
					print("LIGHT %s %s vis=%s e=%.2f pos=%s range=%s" % [l.get_class(), l.get_path(), l.is_visible_in_tree(), l.light_energy, str(l.global_position.snapped(Vector3.ONE * 0.1)), str(l.get("omni_range") if l is OmniLight3D else l.get("spot_range"))])
				for n2 in get_tree().root.find_children("*", "ReflectionProbe", true, false):
					print("PROBE ", n2.get_path())
				print("CAM ", s.rig.cam.global_position.snapped(Vector3.ONE * 0.1), " env amb ", s.view.env.ambient_light_energy, " src ", s.view.env.ambient_light_source, " sky_contrib ", s.view.env.ambient_light_sky_contribution, " exposure ", s.view.env.tonemap_exposure, " bg_energy ", s.view.env.background_energy_multiplier)
			"red":
				s.cabin.mat_shell.vertex_color_use_as_albedo = false
				s.cabin.mat_shell.albedo_color = Color(1, 0, 0)
				s.cabin.set_light_mode("off")
				s.view.sun.visible = false
				s.view.env.ambient_light_energy = 0.0
				s.view.env.fog_enabled = false
				print("cabin children: ", s.cabin.get_child_count(), " vis ", s.cabin.visible, " ", s.cabin.get_parent().name)
				print("light mode ", s.cabin.light_mode, " lights ", s.cabin.lights.map(func(l): return l.light_energy))
			"noclouds":
				for c in s.view.get_children():
					if c is MeshInstance3D and c != s.view.terrain:
						print("hide ", c.name)
						c.visible = false
			"nospec":
				s.cabin.mat_shell.metallic_specular = 0.0
				s.view.env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			"nocabin": s.cabin.visible = false
			"noprobe":
				var pr := s.cabin.get_node_or_null("InteriorProbe")
				if pr:
					pr.queue_free()
			"black":
				s.cabin.set_light_mode("off")
				s.view.sun.visible = false
				s.view.env.ambient_light_energy = 0.0
				s.view.env.fog_enabled = false
				s.view.env.glow_enabled = false
				var pr3 := s.cabin.get_node_or_null("InteriorProbe")
				if pr3:
					pr3.queue_free()
				print("fog density was ", s.view.env.fog_density, " sky_affect ", s.view.env.fog_sky_affect, " vol ", s.view.env.volumetric_fog_enabled)
			"dark":
				s.cabin.set_light_mode("off")
				s.view.sun.visible = false
				s.view.env.ambient_light_energy = 0.0
				var pr2 := s.cabin.get_node_or_null("InteriorProbe")
				if pr2:
					pr2.queue_free()
		print("dbg ", dbg)
	for i in 40:
		await get_tree().process_frame
	var views: Array = ["cockpit", "chase", "wing", "tower"] if start == "air" else ["orbit", "cockpit", "tower"]
	if mode == "passenger":
		views = ["cabin", "wing", "orbit"]
	for v in views:
		s.set_view(v)
		if dbg == "near":
			s.rig.cam.near = 0.1
		if v == "orbit":
			s.rig.set("orbit_dist", 75.0)
			s.rig.set("orbit_pitch", 18.0)
		for i in 45:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("sess_%s_%s_%s%s.png" % [start, type_id, v, OS.get_environment("DBG")]))
		print("shot ", v)
	get_tree().quit()
