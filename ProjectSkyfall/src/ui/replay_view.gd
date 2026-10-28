extends Node3D
## In-engine video player. Plays back a flight (from the flight recorder) in the real world at
## the real time and weather, with a director that cuts between shots like a news report:
## aerial establishing views, tracking shots, a shaky witness phone, an investigation animation
## with the flight path drawn in the sky. Also stages "news footage" for background stories.
## Real controls: play/pause, scrub, speed, camera choice, restart, close.

var view: WorldView
var model: AircraftModel
var cam: Camera3D
var samples: Array = []
var duration := 1.0
var t := 0.0
var speed := 1.0
var playing := true
var mode := "replay"            # replay | reconstruction | report
var cam_choice := "auto"
var ending := ""                # "" | crash | ditch | landed
var title := ""
var outlet := ""
var back_to := "menu"
var params: Dictionary = {}
var _type_id := "s320"
var _airline := "SKF"
var _ui: Control
var _seek: HSlider
var _time_label: Label
var _play_btn: Button
var _shot_label: Label
var _data_label: Label
var _ignore_seek := false
var _shake := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _witness := Vector3.ZERO
var _aerial := Vector3.ZERO
var _orbit_yaw := 30.0
var _drag := false
var _fx: Node3D
var _path_mesh: MeshInstance3D
var _vehicles: Array = []
var _base_clock := 0.0
var _impact_t := -1.0


func setup(p: Dictionary) -> void:
	params = p
	back_to = String(p.get("back", "menu"))
	var video: Dictionary = p.get("video", {})
	if p.has("result"):
		mode = "replay"
		var res: Dictionary = p.result
		samples = res.get("recorder", {}).get("samples", [])
		_type_id = String(res.get("type", "s320"))
		_airline = String(res.get("airline", "SKF"))
		_base_clock = float(res.get("clock", WorldSim.clock)) - (float(samples[samples.size() - 1][0]) if not samples.is_empty() else 0.0)
		ending = "crash" if String(res.get("outcome", "")) == "crashed" else ("ditch" if String(res.get("outcome", "")) == "ditched" else "landed")
		title = "Flight replay · %s" % res.get("callsign", "")
	elif String(video.get("type", "")) == "reconstruction":
		mode = "reconstruction"
		var inc := News.incident(String(video.get("incident", "")))
		samples = inc.get("samples", [])
		_type_id = String(inc.get("type", "s320"))
		_airline = String(inc.get("airline", "SKF"))
		_base_clock = float(inc.get("clock", WorldSim.clock)) - (float(samples[samples.size() - 1][0]) if not samples.is_empty() else 0.0)
		ending = "ditch" if bool(inc.get("ditching", false)) else "crash"
		title = String(inc.get("title", "Reconstruction"))
		outlet = "aeroweek" if String(video.get("angle", "")) == "analysis" else "skyline"
		cam_choice = "analysis" if String(video.get("angle", "")) == "analysis" else ("witness" if String(video.get("angle", "")) == "witness" else "auto")
	else:
		mode = "report"
		_type_id = String(video.get("type_id", "s320"))
		_airline = String(video.get("airline", "SKF"))
		samples = _synth_arrival(String(video.get("airport", "SKPC")))
		_base_clock = WorldSim.clock - 600.0
		ending = "landed"
		title = String(video.get("scene", "arrival")).replace("_", " ").capitalize()
		outlet = "skyline"
	if samples.size() < 2:
		Game.goto(back_to)
		return
	if mode != "replay":
		# trim reconstructions to the final few minutes
		var t_end := float(samples[samples.size() - 1][0])
		var keep := []
		for s in samples:
			if float(s[0]) >= t_end - 180.0:
				keep.append(s)
		samples = keep
	var t0 := float(samples[0][0])
	for s2 in samples:
		s2[0] = float(s2[0]) - t0
	duration = float(samples[samples.size() - 1][0]) + (12.0 if ending in ["crash", "ditch"] else 6.0)
	_impact_t = float(samples[samples.size() - 1][0]) if ending in ["crash", "ditch"] else -1.0
	_rng.seed = U.hash_str(title)
	_build_world()
	_build_ui()
	if mode == "report" and String(video.get("scene", "")) == "emergency_landing":
		_stage_emergency_vehicles(String(video.get("airport", "SKPC")))


# ================================================================== world
func _build_world() -> void:
	var s0: Array = samples[0]
	var sl: Array = samples[samples.size() - 1]
	view = WorldView.new()
	add_child(view)
	view.setup(float(sl[1]), float(sl[2]), _base_clock + float(sl[0]), true)
	model = AircraftModel.new()
	view.dynamic_root.add_child(model)
	model.build(_type_id, _airline, "", 1.0)
	cam = Camera3D.new()
	cam.near = 0.5
	cam.far = 80000.0
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	# fixed camera spots: a witness on the ground beside the final part of the track, and an
	# aerial establishing point
	var a := Vector2(float(s0[1]), float(s0[2]))
	var b := Vector2(float(sl[1]), float(sl[2]))
	var dir := (b - a).normalized() if a.distance_to(b) > 10.0 else Vector2(1, 0)
	var side := Vector2(-dir.y, dir.x)
	var wpos := b - dir * 900.0 + side * 650.0
	_witness = Vector3(wpos.x, Geo.ground_height(wpos.x, wpos.y) + 1.6, wpos.y)
	var apos := b - dir * 2500.0 - side * 1800.0
	_aerial = Vector3(apos.x, float(sl[3]) + 900.0, apos.y)
	if mode == "reconstruction" or cam_choice == "analysis":
		_build_path_ribbon()
	_fx = Node3D.new()
	view.dynamic_root.add_child(_fx)


func _build_path_ribbon() -> void:
	var mb := MeshBuilder.new()
	for i in samples.size() - 1:
		var s: Array = samples[i]
		var n: Array = samples[i + 1]
		var p0 := view.world_to_local(float(s[1]), float(s[3]), float(s[2]))
		var p1 := view.world_to_local(float(n[1]), float(n[3]), float(n[2]))
		var vs := float(s[5])
		var col := Color(0.3, 0.9, 1.0) if vs > -6.0 else (Color(1.0, 0.75, 0.2) if vs > -15.0 else Color(1.0, 0.25, 0.2))
		var up := Vector3(0, 1.2, 0)
		mb.add_quad(p0 - up, p1 - up, p1 + up, p0 + up, col)
		mb.add_quad(p0 + up, p1 + up, p1 - up, p0 - up, col)
	_path_mesh = MeshInstance3D.new()
	_path_mesh.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.65)
	_path_mesh.material_override = m
	_path_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.dynamic_root.add_child(_path_mesh)
	_path_mesh.visible = cam_choice == "analysis"


func _synth_arrival(icao: String) -> Array:
	## Builds a believable approach and landing for staged news footage.
	var ap: Dictionary = Airports.get_ap(icao)
	var w := WeatherModel.sample(float(ap.x), float(ap.z), WorldSim.clock)
	var e := Airports.best_runway(icao, float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)), 1200.0)
	if e.is_empty():
		return []
	var spec := AircraftTypes.get_type(_type_id)
	var d := Vector2(sin(deg_to_rad(e.hdg)), -cos(deg_to_rad(e.hdg)))
	var thr := Vector2(e.thr_x, e.thr_z)
	var out := []
	var v := float(spec.vapp) * U.KT
	var tt := 0.0
	var dist := -7000.0
	var gh := float(spec.gear_height)
	while dist < 1800.0:
		var h := maxf((-dist + 300.0) * tan(deg_to_rad(3.0)), 0.0) if dist < 350.0 else 0.0
		var pitch := 2.5 if dist < 200.0 else (4.5 if dist < 400.0 else 0.5)
		var p := thr + d * dist
		out.append([tt, p.x, p.y, float(e.elev) + gh + h, v / U.KT, -v * 0.052 if h > 0.0 else 0.0, pitch, 0.0, float(e.hdg), 0.3, spec.flaps.size() - 1, 1, 0, 0, 1.0, v])
		var step := v * 0.5
		dist += step
		tt += 0.5
		if dist > 350.0:
			v = maxf(v - 1.4, 12.0)
	return out


func _stage_emergency_vehicles(icao: String) -> void:
	var mid: Array = samples[samples.size() / 2]
	var last: Array = samples[samples.size() - 1]
	var dir := Vector2(float(last[1]) - float(mid[1]), float(last[2]) - float(mid[2])).normalized()
	var side := Vector2(-dir.y, dir.x)
	for i in 3:
		var kind := "arff" if i < 2 else "ambulance"
		var p := Vector2(float(last[1]), float(last[2])) - dir * (300.0 + i * 25.0) + side * 70.0
		var veh := VehicleBuilder.build(kind, {"main": VehicleBuilder.LIME} if kind == "arff" else {})
		view.dynamic_root.add_child(veh)
		veh.position = view.world_to_local(p.x, Geo.ground_height(p.x, p.y), p.y)
		veh.rotation.y = atan2(-dir.x, -dir.y)
		VehicleBuilder.set_lamps(veh, true, view.night > 0.4)
		_vehicles.append(veh)


# ================================================================== playback
func _sample_at(tt: float) -> Array:
	if tt <= float(samples[0][0]):
		return samples[0]
	var lo := 0
	var hi := samples.size() - 1
	if tt >= float(samples[hi][0]):
		return samples[hi]
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(samples[mid][0]) <= tt:
			lo = mid
		else:
			hi = mid
	var a: Array = samples[lo]
	var b: Array = samples[hi]
	var f := (tt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
	var out := []
	for k in a.size():
		if k == 8:
			out.append(float(a[k]) + U.angle_diff_deg(float(b[k]), float(a[k])) * f)
		elif typeof(a[k]) == TYPE_FLOAT or typeof(a[k]) == TYPE_INT:
			out.append(lerpf(float(a[k]), float(b[k]), f))
		else:
			out.append(a[k])
	return out


func _process(delta: float) -> void:
	if model == null:
		return
	if playing:
		t = minf(t + delta * speed, duration)
		if t >= duration:
			playing = false
			_play_btn.text = "▶"
	var s := _sample_at(t)
	var pos := view.world_to_local(float(s[1]), float(s[3]), float(s[2]))
	if ending in ["crash", "ditch"] and _impact_t >= 0.0 and t > _impact_t:
		# wreckage settles; the fire burns
		var g := Geo.ground_height(float(s[1]), float(s[2]))
		pos.y = maxf(g + 1.2, pos.y - (t - _impact_t) * 2.0)
		_ensure_fire()
	if pos.length() > 4000.0:
		view.rebase(pos)
		pos = view.world_to_local(float(s[1]), float(s[3]), float(s[2]))
	model.position = pos
	model.basis = Basis(Vector3.UP, -deg_to_rad(float(s[8]))) * Basis(Vector3.RIGHT, deg_to_rad(float(s[6]))) * Basis(Vector3(0, 0, -1), deg_to_rad(float(s[7])))
	model.animate_simple(float(s[11]), float(s[10]), 30.0 + float(s[9]) * 30.0, {"nav": true, "strobe": true, "beacon": true, "landing": float(s[3]) < 3000.0},
		view.night, delta * speed, float(s[15]) if float(s[11]) > 0.5 else 0.0)
	view.set_time(_base_clock + t)
	_update_camera(delta, s)
	_update_ui(s)


func _update_camera(delta: float, s: Array) -> void:
	var shot := cam_choice
	if shot == "auto":
		var f := t / maxf(duration, 1.0)
		if mode == "replay":
			shot = "chase"
		elif mode == "report":
			shot = "spotter"
		else:
			shot = "aerial" if f < 0.18 else ("chase" if f < 0.55 else "witness")
	var target := model.global_position
	var witness := view.world_to_local(_witness.x, _witness.y, _witness.z)
	var aerial := view.world_to_local(_aerial.x, _aerial.y, _aerial.z)
	match shot:
		"chase":
			var back := model.global_transform.basis.z
			back.y = 0.0
			back = back.normalized()
			var L := float(AircraftTypes.get_type(_type_id).length)
			var want := target + back.rotated(Vector3.UP, deg_to_rad(_orbit_yaw * 0.3)) * L * 2.2 + Vector3(0, L * 0.45, 0)
			cam.global_position = cam.global_position.lerp(want, clampf(delta * 2.5, 0.0, 1.0)) if cam.global_position.distance_to(want) < 400.0 else want
			cam.look_at(target, Vector3.UP)
			cam.fov = 55.0
			_shot_label.text = ""
		"orbit":
			var L2 := float(AircraftTypes.get_type(_type_id).length)
			_orbit_yaw += delta * 6.0
			cam.global_position = target + Vector3(sin(deg_to_rad(_orbit_yaw)), 0.35, cos(deg_to_rad(_orbit_yaw))) * L2 * 2.4
			cam.look_at(target, Vector3.UP)
			cam.fov = 50.0
			_shot_label.text = ""
		"aerial":
			cam.global_position = aerial
			cam.look_at(target, Vector3.UP)
			cam.fov = clampf(rad_to_deg(2.0 * atan(250.0 / maxf(aerial.distance_to(target), 1.0))), 6.0, 60.0)
			_shot_label.text = "RECONSTRUCTION"
		"witness", "spotter":
			# hand-held camera with breathing shake and lagging zoom
			_shake = _shake.lerp(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * (0.6 if shot == "witness" else 0.15), clampf(delta * 3.0, 0.0, 1.0))
			cam.global_position = witness
			cam.look_at(target + Vector3(_shake.x, _shake.y, 0.0) * 4.0, Vector3.UP)
			var dist := witness.distance_to(target)
			var want_fov := clampf(rad_to_deg(2.0 * atan(float(AircraftTypes.get_type(_type_id).span) * 1.8 / maxf(dist, 1.0))), 4.0, 65.0)
			cam.fov = lerpf(cam.fov, want_fov, clampf(delta * 1.5, 0.0, 1.0))
			_shot_label.text = "WITNESS VIDEO" if shot == "witness" else "LIVE"
		"analysis":
			var c2 := target + Vector3(0, -150.0, 0)
			_orbit_yaw += delta * 4.0
			cam.global_position = c2 + Vector3(sin(deg_to_rad(_orbit_yaw)), 0.55, cos(deg_to_rad(_orbit_yaw))) * 1800.0
			cam.look_at(c2, Vector3.UP)
			cam.fov = 45.0
			_shot_label.text = "INVESTIGATION ANIMATION"
		"cockpit":
			var spec := AircraftTypes.get_type(_type_id)
			var eye := Vector3(-0.5, float(spec.fuse_h) * 0.18, -float(spec.length) * float(spec.cg_frac) + AircraftModel.pilot_eye_station(spec))
			cam.global_transform = model.global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-6.0), 0, 0)), eye)
			cam.fov = 70.0
			_shot_label.text = ""
	if _path_mesh:
		_path_mesh.visible = shot == "analysis"
	var g := Geo.ground_height(view.wx(cam.global_position), view.wz(cam.global_position)) + 1.2
	if cam.global_position.y < g:
		cam.global_position.y = g


func _ensure_fire() -> void:
	if _fx.get_child_count() > 0:
		return
	_fx.global_position = model.global_position
	if ending == "ditch":
		return
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 10.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 8.0
	pm.scale_min = 5.0
	pm.scale_max = 9.0
	pm.color = Color(0.12, 0.11, 0.1, 0.7)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(4, 4)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	_fx.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 5.0
	light.omni_range = 70.0
	light.position.y = 3.0
	_fx.add_child(light)


# ================================================================== UI and controls
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UIStyle.theme()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	if outlet != "":
		var o: Dictionary = News.OUTLETS.get(outlet, {"name": outlet, "color": "c0262d"})
		var bug := PanelContainer.new()
		bug.add_theme_stylebox_override("panel", UIStyle.box(Color.html(String(o.color)), 4, Color(0, 0, 0, 0), 0, 10))
		bug.add_child(UIStyle.label(String(o.name).to_upper(), 16, Color.WHITE, true))
		bug.position = Vector2(24, 20)
		_ui.add_child(bug)
		var lower := PanelContainer.new()
		lower.add_theme_stylebox_override("panel", UIStyle.box(Color(0.02, 0.03, 0.05, 0.85), 2, Color.html(String(o.color)), 0, 12))
		lower.add_child(UIStyle.label(title, 20, Color.WHITE, true))
		lower.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		lower.position = Vector2(24, -150)
		_ui.add_child(lower)
	_shot_label = UIStyle.label("", 15, Color(1, 1, 1, 0.85), true)
	_shot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_shot_label.position = Vector2(-300, 24)
	_shot_label.custom_minimum_size = Vector2(280, 0)
	_shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_shot_label)
	_data_label = UIStyle.label("", 14, Color(0.85, 0.95, 1.0), false)
	_data_label.add_theme_font_override("font", UIStyle.mono())
	_data_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_data_label.position = Vector2(-300, 52)
	_data_label.custom_minimum_size = Vector2(280, 0)
	_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_data_label)
	var bar := UIStyle.panel(Vector2(0, 0), Color(0.02, 0.03, 0.05, 0.85))
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -72
	_ui.add_child(bar)
	var h := UIStyle.hbox(10)
	bar.add_child(h)
	_play_btn = UIStyle.button("❚❚", func():
		playing = not playing
		if playing and t >= duration:
			t = 0.0
		_play_btn.text = "❚❚" if playing else "▶", 52)
	h.add_child(_play_btn)
	h.add_child(UIStyle.button("⟲", func():
		t = 0.0
		playing = true
		_play_btn.text = "❚❚", 44))
	_seek = HSlider.new()
	_seek.min_value = 0.0
	_seek.max_value = duration
	_seek.step = 0.1
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.custom_minimum_size = Vector2(200, 30)
	_seek.value_changed.connect(func(v):
		if not _ignore_seek:
			t = v)
	h.add_child(_seek)
	_time_label = UIStyle.label("0:00 / 0:00", 14, UIStyle.TEXT)
	h.add_child(_time_label)
	var speeds := [0.5, 1.0, 2.0, 4.0, 16.0]
	h.add_child(ScreenBase.option(["0.5×", "1×", "2×", "4×", "16×"], 1, func(i): speed = speeds[i]))
	var cams := ["auto", "chase", "orbit", "witness", "aerial", "cockpit", "analysis"]
	h.add_child(ScreenBase.option(["Director", "Chase", "Orbit", "Ground", "Aerial", "Cockpit", "Flight path"], cams.find(cam_choice), func(i): cam_choice = cams[i]))
	h.add_child(UIStyle.button("Close", func(): Game.goto(back_to), 80))


func _update_ui(s: Array) -> void:
	_ignore_seek = true
	_seek.value = t
	_ignore_seek = false
	_time_label.text = "%s / %s" % [_mmss(t), _mmss(duration)]
	_data_label.text = "ALT %5d ft\nIAS %3d kt\nV/S %+5d fpm" % [int(float(s[3]) / U.FT), int(float(s[4])), int(float(s[5]) / U.FPM)] if mode != "report" else ""


static func _mmss(x: float) -> String:
	return "%d:%02d" % [int(x) / 60, int(x) % 60]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE):
		playing = not playing
		_play_btn.text = "❚❚" if playing else "▶"
	elif event is InputEventMouseButton:
		_drag = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _drag:
		_orbit_yaw -= (event as InputEventMouseMotion).relative.x * 0.3
