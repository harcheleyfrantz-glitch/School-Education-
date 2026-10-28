extends Node3D
## Renders aircraft for visual checks.
## Usage: -- <out_dir> [type|all|t1,t2] [mode] [hour] [livery]
##   row     every type side by side on the Port Calder apron plus one close-up each (default)
##   beauty  one aircraft at a time on the apron, posed against the sun: hero (3/4 front low), side,
##           top, rear, nose / flight deck, engine inlet, main gear, wingtip and tail; saves
##           <type>_<shot>.png. hour 18.9 = golden hour, 12.5 = midday, 22.5 = night (all lights on).
##           livery: airline code or special scheme key ("NWC.tanker"); default per type.
var out_dir := "/tmp"
var view: WorldView
var cam: Camera3D

const DEFAULT_AIRLINE := {"t172": "HFA", "tp72": "CLK", "rj90": "SKF", "s320": "LMN", "w350": "WMA", "bj6": "APX", "f4": "NWC"}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var which := args[1] if args.size() > 1 else "all"
	var mode := args[2] if args.size() > 2 else "row"
	var hour := float(args[3]) if args.size() > 3 else (10.5 if mode == "row" else 18.9)
	var livery := args[4] if args.size() > 4 else ""
	WeatherModel.override_preset = "few"
	view = WorldView.new()
	add_child(view)
	var ap: Dictionary = Airports.get_ap("SKPC")
	view.setup(ap.x, ap.z - 300.0, U.date_to_clock(2027, 6, 14, hour), true)
	view.airports.ensure_loaded("SKPC")
	cam = Camera3D.new()
	cam.far = 120000.0
	cam.near = 0.1
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	if mode == "beauty":
		await _beauty(ap, which, hour, livery)
	else:
		await _row(ap, which)
	print("model shots done")
	get_tree().quit()


func _row(ap: Dictionary, which: String) -> void:
	var types := AircraftTypes.ORDER if which == "all" else [which]
	var x0: float = ap.x - 250.0
	var models := []
	var i := 0
	for t in types:
		var ac := Aircraft.new()
		view.dynamic_root.add_child(ac)
		ac.setup(t, "CR-T%d" % i, ["SKF", "CLK", "LMN", "NWC", "APX", "HFA", "WMA"][i % 7] if t != "t172" else "HFA", view, true)
		var lp := view.world_to_local(x0 + i * 75.0, float(ap.elev), float(ap.z) - 330.0)
		ac.place_at(lp, 160.0, true)
		ac.sys.lights.nav = true
		ac.sys.lights.beacon = true
		ac.player_controlled = false
		ac.set_physics_process(false)
		ac.model.animate(ac, 0.016)
		models.append(ac)
		i += 1
	cam.position = view.world_to_local(x0 + 120.0, float(ap.elev) + 22.0, float(ap.z) - 230.0)
	cam.look_at(view.world_to_local(x0 + 200.0, float(ap.elev) + 3.0, float(ap.z) - 330.0))
	await view.warm_up(20.0)
	for k in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("models_row.png"))
	for ac in models:
		var L: float = ac.spec.length
		var p: Vector3 = ac.position
		cam.position = p + Vector3(L * 0.75, L * 0.18 + 2.0, L * 0.55)
		cam.look_at(p + Vector3(0, 1.0, 0))
		for k in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("model_%s.png" % ac.type_id))


func _beauty(ap: Dictionary, which: String, hour: float, livery: String) -> void:
	var types: Array = AircraftTypes.ORDER if which == "all" else Array(which.split(","))
	var lay := AirportLayout.get_layout("SKPC")
	var sd: Dictionary = lay.stands[0]
	for s in lay.stands:
		if bool(s.get("heavy", false)):
			sd = s
			break
	var nrm: Vector2 = sd.normal
	var face: Vector2 = sd.get("facade_origin", sd.stop)
	var spot := face + nrm * 80.0
	var night := hour > 20.5 or hour < 5.0
	await view.warm_up(20.0)
	for t in types:
		var al: String = livery if livery != "" else String(DEFAULT_AIRLINE.get(t, "SKF"))
		var ac := Aircraft.new()
		view.dynamic_root.add_child(ac)
		var t0 := Time.get_ticks_msec()
		ac.setup(t, "CR-SKY", al, view, true)
		print("%s built in %d ms" % [t, Time.get_ticks_msec() - t0])
		# pose the aircraft so the low sun lights the hero side (front left)
		var s := view.sun_dir
		var sun_hdg := U.dir_to_heading(Vector3(s.x, 0.0, s.z))
		var hdg := wrapf(sun_hdg + 55.0, 0.0, 360.0)
		var lp := view.world_to_local(float(ap.x) + spot.x, float(ap.elev), float(ap.z) + spot.y)
		ac.place_at(lp, hdg, true)
		ac.player_controlled = false
		ac.set_physics_process(false)
		var Lt: Dictionary = ac.sys.lights
		Lt.nav = true
		Lt.beacon = true
		if night:
			for k in ["strobe", "landing", "taxi", "logo", "wing", "cabin"]:
				Lt[k] = true
		for k in 3:
			ac.model.animate(ac, 0.016)
		var shots := _shots(ac)
		if night:
			shots = shots.filter(func(x): return String(x[0]) in ["hero", "side", "nose", "rear", "tail"])
		for sh in shots:
			cam.fov = float(sh[3])
			cam.global_position = ac.global_transform * (sh[1] as Vector3)
			cam.look_at(ac.global_transform * (sh[2] as Vector3))
			for k in 5:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [t, sh[0]]))
		ac.queue_free()
		await get_tree().process_frame


## Camera stations in the aircraft's body frame: [name, position, target, fov].
func _shots(ac: Aircraft) -> Array:
	var sp: Dictionary = ac.spec
	var L: float = sp.length
	var S: float = sp.span
	var H: float = sp.gear_height
	var fh: float = sp.fuse_h
	var fw: float = sp.fuse_w
	var nz := -L * float(sp.cg_frac)
	var an: Dictionary = ac.model.anchors
	var big := maxf(L, S)
	var g := -H
	var out := []
	out.append(["hero", Vector3(-0.36 * big, g + 1.7, nz - 0.4 * big), Vector3(0, g + H * 0.8, nz * 0.2), 40.0])
	out.append(["side", Vector3(-1.05 * big, g + H * 0.95, 0.0), Vector3(0, g + H * 0.95 + fh * 0.15, 0.03 * L), 40.0])
	out.append(["top", Vector3(-0.42 * big, 0.95 * big, 0.5 * big), Vector3(0, 0, 0.05 * L), 40.0])
	out.append(["rear", Vector3(0.5 * big, g + 1.9, 0.6 * big), Vector3(0, g + H, 0.0), 42.0])
	var eye := nz + AircraftModel.pilot_eye_station(sp)
	out.append(["nose", Vector3(-fw * 1.5, fh * 0.12, nz - fh * 1.5), Vector3(0, fh * 0.16, eye - 0.7), 38.0])
	var e0: Vector3 = an.get("engine_0", Vector3(0, 0, nz))
	var ed: float = an.get("engine_d_0", 1.5)
	out.append(["engine", e0 + Vector3(-ed * 0.8 - 0.4, ed * 0.15 + 0.1, -ed * 2.6 - 0.8), e0 + Vector3(0, 0, ed * 0.35), 40.0])
	var mg: Vector3 = an.get("main_gear_L", Vector3(-2, -H, 1))
	out.append(["gear", Vector3(mg.x * 0.25, g + 0.75, mg.z - 2.6 - H * 0.9), mg + Vector3(0.0, H * 0.3, 0.2), 50.0])
	var wt: Vector3 = an.get("wingtip_L", Vector3(-S * 0.5, 0, 0))
	out.append(["wingtip", wt + Vector3(-1.4 - S * 0.03, 1.0 + S * 0.03, -2.8 - S * 0.06), wt + Vector3(0.9, 0.3, 0.9), 45.0])
	var ft: Vector3 = an.get("fin_top", Vector3(0, fh, nz + L * 0.9))
	out.append(["tail", Vector3(-fh * 2.8 - 2.5, ft.y * 0.5, ft.z - fh * 1.2), Vector3(0, ft.y * 0.62, ft.z - fh * 0.4), 42.0])
	return out
