class_name WorldStage
extends NewsStage
## Field footage shot in the real world: the recorded flight reconstructed over the actual
## terrain at the actual time and weather; the crash site (airframe broken into sections,
## debris field, ground scar, fuel fires and smoke columns, fire tenders spraying, ambulances,
## police cars, cordon tape, light towers, tents, responders, survivors, onlookers filming,
## investigators); a ditched aircraft with rafts and boats; news-helicopter aerials; a
## witness's phone; the reporter's stand-up and interviews; airport spotter footage and the
## terminal. Everything is posed from the playhead, so the video can be scrubbed.

var view: WorldView
var model: AircraftModel
var world: Dictionary = {}
var mode := "incident"
var stage_name := "world"
var samples: Array = []
var spec: Dictionary = {}
var t_end := 0.0
var site_w := Vector3.ZERO          # main wreckage (world x, ground y, world z)
var impact_w := Vector3.ZERO        # first impact point
var dir2 := Vector2(0, -1)          # direction of travel at impact (x, z)
var side2 := Vector2(1, 0)
var wind := Vector3(2, 0, 1)
var ditch := false
var severity := 0.7
var night_site := false
var wreck: Node3D
var site_root: Node3D
var fires: Node3D
var smoke: Node3D
var fireball: Node3D
var ribbon: MeshInstance3D
var standup_w := Vector3.ZERO
var standup_face := Vector3.ZERO
var witness_w := Vector3.ZERO
var phone_variant := ""
var city_torn: Node3D       # damaged buildings, shown from the moment of impact
var city_intact: Node3D     # the same buildings before the aircraft hit them
var torn_spots: Array = []  # world positions of the holes (for close-ups)
var terminal_w := Vector3.ZERO
var terminal_look := Vector3.ZERO
var _cars: Array = []
var _fire_lights: Array = []
var _towers: Array = []
var _walkers: Array = []            # [crowd index, a(world), b(world), speed, pose]
var _site_people := {}              # phase -> [crowd indices]
var _phase := ""
var _clock_set := -1.0
var _rng := RandomNumberGenerator.new()
var _spotter_w := Vector3.ZERO
var _tower_w := Vector3.ZERO
var _touch_t := -1.0
var _lift_t := -1.0
var _ground_flags: PackedByteArray = PackedByteArray()
var _cam_w := Vector3.ZERO           # camera world position (for smoothing)
var _emergency := false
var _buf0 := PackedFloat32Array()


func build(prog: Dictionary) -> void:
	super.build(prog)
	stage_name = String(get_meta("stage_name", "world"))
	world = prog.get("airport_world", {}) if stage_name == "airport" else prog.get("world", {})
	mode = String(world.get("mode", "incident"))
	_rng.seed = int(world.get("seed", 7))
	spec = AircraftTypes.get_type(String(world.get("type", "s320")))
	if mode == "airport":
		samples = _synth_arrival(String(world.get("icao", "SKPC")))
		_emergency = bool(world.get("emergency", false))
	else:
		samples = world.get("samples", [])
	if samples.size() >= 2:
		t_end = float(samples[samples.size() - 1][0])
		var last: Array = samples[samples.size() - 1]
		var prev: Array = samples[maxi(samples.size() - 6, 0)]
		var d := Vector2(float(last[1]) - float(prev[1]), float(last[2]) - float(prev[2]))
		dir2 = d.normalized() if d.length() > 1.0 else Vector2(sin(deg_to_rad(float(last[8]))), -cos(deg_to_rad(float(last[8]))))
	side2 = Vector2(-dir2.y, dir2.x)
	var cx := float(world.get("x", 0.0))
	var cz := float(world.get("z", 0.0))
	if (cx == 0.0 and cz == 0.0) and samples.size() >= 1:
		cx = float(samples[samples.size() - 1][1])
		cz = float(samples[samples.size() - 1][2])
	if mode == "airport":
		var ap: Dictionary = Airports.get_ap(String(world.get("icao", "SKPC")))
		cx = float(samples[samples.size() - 1][1]) if not samples.is_empty() else float(ap.x)
		cz = float(samples[samples.size() - 1][2]) if not samples.is_empty() else float(ap.z)
	impact_w = Vector3(cx, Geo.ground_height(cx, cz), cz)
	severity = float(world.get("severity", 0.7))
	ditch = String(world.get("ending", "")) == "ditch" or (mode == "incident" and Geo.is_water(cx, cz))
	var slide := 0.0 if ditch else clampf(40.0 + (1.0 - severity) * 260.0, 40.0, 300.0) if mode == "incident" else 0.0
	var sx := cx + dir2.x * slide
	var sz := cz + dir2.y * slide
	site_w = Vector3(sx, Geo.ground_height(sx, sz), sz)
	var clock := float(world.get("air_clock", world.get("clock", WorldSim.clock)))
	view = WorldView.new()
	add_child(view)
	view.setup(site_w.x, site_w.z, clock, true)
	view.weather_override = _weather_at(site_w.x, site_w.z, float(world.get("clock", clock)))
	var w: Dictionary = view.weather_override
	var wd := deg_to_rad(float(w.get("wind_dir", 250.0)) + 180.0)
	wind = Vector3(sin(wd), 0, -cos(wd)) * clampf(float(w.get("wind_kt", 8.0)) * 0.35, 1.0, 9.0)
	model = AircraftModel.new()
	view.dynamic_root.add_child(model)
	model.build(String(world.get("type", "s320")), String(world.get("airline", "SKF")), String(world.get("reg", "")), 1.0)
	people = Crowd.new()
	view.dynamic_root.add_child(people)
	people.setup(150, 0, String(world.get("airline", "")), true)
	_make_camera()
	view.camera = cam
	cam.far = 90000.0
	cam.near = 0.3
	if mode == "incident" or mode == "replay":
		_build_ribbon()
	if mode == "incident":
		_build_wreck()
		_spots()
		_build_site()
	elif mode == "airport":
		_build_airport_scene()
	elif mode == "replay":
		_replay_spots()
		if String(world.get("ending", "")) in ["crash", "ditch"]:
			_build_wreck()
			fireball = NewsFX.fireball()
			view.dynamic_root.add_child(fireball)
	people.flush()
	_buf0 = people.buf.duplicate()
	view.origin_shifted.connect(func(_s): _restart_particles())


func is_ready() -> bool:
	if view == null or view.terrain == null:
		return true
	return view.terrain.is_settled() and view.terrain.pending_count() == 0


func settled() -> bool:
	return is_ready()


func on_seek() -> void:
	_clock_set = -1.0


func _restart_particles() -> void:
	for p in find_children("*", "GPUParticles3D", true, false):
		(p as GPUParticles3D).restart()


func _weather_at(x: float, z: float, clock: float) -> Dictionary:
	var saved := WeatherModel.override_preset
	WeatherModel.override_preset = ""
	var s := WeatherModel.sample(x, z, clock)
	WeatherModel.override_preset = saved
	var rec: Dictionary = world.get("weather", {})
	for k in rec.keys():
		if s.has(k) and typeof(rec[k]) == typeof(s[k]):
			s[k] = rec[k]
	if bool(world.get("storm", false)):
		s.precip = "thunderstorm"
		s.cover = 0.95
		s.storm = 0.85
		s.wind_kt = 28.0
		s.vis = 4000.0
		s.base_ft = 1400.0
	return s


func _local(w: Vector3) -> Vector3:
	return view.world_to_local(w.x, w.y, w.z)


func _wv(x: float, z: float, up: float = 0.0) -> Vector3:
	return Vector3(x, Geo.ground_height(x, z) + up, z)


# ================================================================== reconstruction track
func _build_ribbon() -> void:
	if samples.size() < 2:
		return
	var mb := MeshBuilder.new()
	var step := maxi(1, samples.size() / 600)
	var i := 0
	while i + step < samples.size():
		var s: Array = samples[i]
		var n: Array = samples[i + step]
		var p0 := _local(Vector3(float(s[1]), float(s[3]), float(s[2])))
		var p1 := _local(Vector3(float(n[1]), float(n[3]), float(n[2])))
		var vs := float(s[5]) / U.FPM
		var col := Color(0.3, 0.9, 1.0) if vs > -1500.0 else (Color(1.0, 0.78, 0.2) if vs > -3500.0 else Color(1.0, 0.25, 0.2))
		var up := Vector3(0, 3.0, 0)
		mb.add_quad(p0 - up, p1 - up, p1 + up, p0 + up, col)
		# drop lines to the ground every few seconds
		if i % (step * 16) == 0:
			var g := _local(_wv(float(s[1]), float(s[2])))
			var sd := Vector3(1.2, 0, 0)
			mb.add_quad(g - sd, g + sd, p0 + sd, p0 - sd, Color(col, 0.35))
		i += step
	ribbon = MeshInstance3D.new()
	ribbon.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.7)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon.material_override = m
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribbon.visible = false
	view.dynamic_root.add_child(ribbon)


func _pose_aircraft(st: float, delta: float) -> Array:
	var s := BroadcastPlayer.sample_at(samples, st)
	if s.is_empty():
		return s
	model.position = _local(Vector3(float(s[1]), float(s[3]), float(s[2])))
	model.basis = Basis(Vector3.UP, -deg_to_rad(float(s[8]))) * Basis(Vector3.RIGHT, deg_to_rad(float(s[6]))) * Basis(Vector3(0, 0, -1), deg_to_rad(float(s[7])))
	var on_ground := float(s[3]) - Geo.ground_height(float(s[1]), float(s[2])) < float(spec.gear_height) + 1.5
	model.animate_simple(float(s[11]), float(s[10]), 30.0 + float(s[9]) * 40.0, {"nav": true, "strobe": not on_ground, "beacon": true,
		"landing": float(s[3]) - Geo.ground_height(float(s[1]), float(s[2])) < 900.0}, view.night, delta, float(s[15]) if on_ground else 0.0)
	return s


func _synth_arrival(icao: String) -> Array:
	## A believable approach and landing at an airport for staged footage.
	var ap: Dictionary = Airports.get_ap(icao)
	var w := WeatherModel.sample(float(ap.x), float(ap.z), float(world.get("clock", WorldSim.clock)))
	var e := Airports.best_runway(icao, float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)), 1200.0)
	if e.is_empty():
		return []
	var d := Vector2(sin(deg_to_rad(float(e.hdg))), -cos(deg_to_rad(float(e.hdg))))
	var thr := Vector2(float(e.thr_x), float(e.thr_z))
	var out := []
	var v := float(spec.vapp) * U.KT
	var tt := 0.0
	var dist := -9000.0
	var gh := float(spec.gear_height)
	while dist < 1900.0:
		var h := maxf((-dist + 300.0) * tan(deg_to_rad(3.0)), 0.0) if dist < 350.0 else 0.0
		var pitch := 2.5 if dist < 200.0 else (4.5 if dist < 420.0 else 0.6)
		var p := thr + d * dist
		var gs := v
		out.append([tt, p.x, p.y, float(e.elev) + gh + h, v / U.KT, -v * 0.052 if h > 0.0 else 0.0, pitch, sin(tt * 0.3) * 1.5 if h > 30.0 else 0.0,
			float(e.hdg), 0.3, spec.flaps.size() - 1, 1, 0, 0, 1.0, gs])
		dist += v * 0.5
		tt += 0.5
		if dist > 350.0:
			v = maxf(v - 1.35, 12.0)
	return out


# ================================================================== wreckage
static var _wreck_shader: Shader


static func wreck_shader() -> Shader:
	## The airframe paint shader, clipped to a fuselage section, open at the cut (dark inside),
	## charred and glowing along the break. Derived at runtime so it tracks the paint shader.
	if _wreck_shader != null:
		return _wreck_shader
	var src: String = (load("res://shaders/aircraft_paint.gdshader") as Shader).code
	src = src.replace("render_mode cull_back;", "render_mode cull_disabled;")
	src = src.replace("uniform float scorch = 0.0;", "uniform float scorch = 0.0;\nuniform vec2 keep_z = vec2(-1000.0, 1000.0);\nuniform float char_w = 1.8;\nuniform float embers = 0.0;")
	src = src.replace("void fragment() {", "void fragment() {\n\tif (lpos.z < keep_z.x || lpos.z > keep_z.y) { discard; }\n\tfloat cut_d = min(lpos.z - keep_z.x, keep_z.y - lpos.z);\n\tfloat char_k = 1.0 - smoothstep(0.0, char_w, cut_d);\n\tbool inside = !FRONT_FACING;")
	src = src.replace("\tALBEDO = col;", "\tcol = mix(col, vec3(0.035, 0.03, 0.025), char_k * 0.95);\n\tALBEDO = inside ? vec3(0.03, 0.026, 0.022) : col;")
	src = src.replace("\tROUGHNESS = rough;", "\tROUGHNESS = inside ? 0.95 : rough;")
	src = src.replace("\tMETALLIC = metal;", "\tMETALLIC = inside ? 0.0 : metal;")
	src = src.replace("\tEMISSION = emit;", "\tEMISSION = (inside ? vec3(0.0) : emit) + vec3(1.0, 0.3, 0.05) * embers * (1.0 - smoothstep(0.0, inside ? 0.6 : 0.35, cut_d)) * 3.0;")
	var sh := Shader.new()
	sh.code = src
	_wreck_shader = sh
	return sh


func _section(z0: float, z1: float, scorch: float, embers: float) -> AircraftModel:
	var m := AircraftModel.new()
	m.build(String(world.get("type", "s320")), String(world.get("airline", "SKF")), String(world.get("reg", "")), 1.0)
	var src: ShaderMaterial = m.mat
	var wm := ShaderMaterial.new()
	wm.shader = wreck_shader()
	for u in src.shader.get_shader_uniform_list():
		var nm := String(u.name)
		wm.set_shader_parameter(nm, src.get_shader_parameter(nm))
	wm.set_shader_parameter("keep_z", Vector2(z0, z1))
	wm.set_shader_parameter("scorch", scorch)
	wm.set_shader_parameter("dirt", 0.6)
	wm.set_shader_parameter("embers", embers)
	wm.set_shader_parameter("cabin_lights", 0.0)
	m.fuselage_mi.material_override = wm
	m.airframe.material_override = wm
	for g in m.gear:
		(g.pivot as Node3D).visible = false
	for ln in m.label_nodes:
		var lz := float((ln as Node3D).position.z)
		(ln as Node3D).visible = lz > z0 + 0.5 and lz < z1 - 0.5
		if scorch > 0.5 and ln is Label3D:
			(ln as Label3D).modulate = Color(0.25, 0.22, 0.2)
	for k in m.lights.keys():
		(m.lights[k] as Node3D).visible = false
	for sl in m.landing_lights:
		(sl as Node3D).visible = false
	for pd in m.prop_discs:
		if pd != null:
			(pd as Node3D).visible = false
	return m


func _place_section(m: AircraftModel, zc: float, at_w: Vector3, yaw_deg: float, pitch_deg: float, roll_deg: float, sink: float) -> void:
	var h := atan2(dir2.x, -dir2.y)
	var b := Basis(Vector3.UP, -h + deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Basis(Vector3(0, 0, -1), deg_to_rad(roll_deg))
	var r := float(spec.fuse_h) * 0.5
	var pos := _local(at_w) + Vector3(0, r * (1.0 - sink), 0) - b * Vector3(0, 0, zc)
	m.transform = Transform3D(b, pos)


func _build_wreck() -> void:
	wreck = Node3D.new()
	view.dynamic_root.add_child(wreck)
	var L := float(spec.length)
	var nose_z := -L * float(spec.cg_frac)
	if ditch:
		var m := _section(-1000.0, 1000.0, 0.0, 0.0)
		wreck.add_child(m)
		var h := atan2(dir2.x, -dir2.y)
		var b := Basis(Vector3.UP, -h + deg_to_rad(8.0)) * Basis(Vector3.RIGHT, deg_to_rad(2.5)) * Basis(Vector3(0, 0, -1), deg_to_rad(-3.0))
		var wl := Geo.water_level(site_w.x, site_w.z)
		m.transform = Transform3D(b, _local(Vector3(site_w.x, wl - float(spec.fuse_h) * 0.18, site_w.z)))
		# slides and rafts at the doors
		for side in [-1.0, 1.0]:
			for k in 2:
				var rf := NewsProps.raft()
				var off := Vector3(side * (float(spec.fuse_w) * 0.5 + 3.5), 0, nose_z + L * (0.2 + k * 0.55))
				rf.transform = Transform3D(b, m.position + b * off)
				rf.position.y = _local(Vector3(0, wl - 0.1, 0)).y
				wreck.add_child(rf)
		return
	var sev := severity
	var r := _rng
	var scorch := 0.65 if bool(world.get("fire", true)) else 0.25
	var trail := site_w.distance_to(impact_w)
	if sev >= 0.88:
		# high-energy impact: the airframe is destroyed; the tail is the largest piece left
		var tail := _section(nose_z + L * 0.7, 1000.0, scorch, 1.0)
		wreck.add_child(tail)
		_place_section(tail, nose_z + L * 0.86, _wv(site_w.x - dir2.x * 25.0, site_w.z - dir2.y * 25.0), 160.0 + r.randf_range(-25, 25), -18.0, 62.0, 0.55)
		var mid := _section(nose_z + L * 0.36, nose_z + L * 0.52, 0.9, 1.0)
		wreck.add_child(mid)
		_place_section(mid, nose_z + L * 0.44, _wv(site_w.x + side2.x * 22.0, site_w.z + side2.y * 22.0), r.randf_range(40, 80), 6.0, 120.0, 0.6)
	elif sev >= 0.5:
		var b1 := r.randf_range(0.2, 0.3)
		var b2 := r.randf_range(0.6, 0.7)
		var nose := _section(-1000.0, nose_z + L * b1, scorch * 0.8, 0.6)
		var center := _section(nose_z + L * b1, nose_z + L * b2, scorch, 1.0)
		var tail2 := _section(nose_z + L * b2, 1000.0, scorch * 0.6, 0.4)
		for m2 in [nose, center, tail2]:
			wreck.add_child(m2)
		var fw := site_w + Vector3(dir2.x, 0, dir2.y) * L * 0.7
		_place_section(nose, nose_z + L * b1 * 0.5, _wv(fw.x + side2.x * 9.0, fw.z + side2.y * 9.0), r.randf_range(25, 50), -3.0, r.randf_range(50, 95), 0.25)
		_place_section(center, nose_z + L * (b1 + b2) * 0.5, site_w, r.randf_range(-12, 12), 1.5, r.randf_range(-12, 12), 0.35)
		var bw := site_w - Vector3(dir2.x, 0, dir2.y) * L * 0.55
		_place_section(tail2, nose_z + L * (b2 + 1.0) * 0.5, _wv(bw.x - side2.x * 7.0, bw.z - side2.y * 7.0), r.randf_range(-35, -15), 4.0, r.randf_range(-20, 20), 0.2)
	else:
		var b3 := r.randf_range(0.55, 0.68)
		var front := _section(-1000.0, nose_z + L * b3, scorch * 0.5, 0.3)
		var rear := _section(nose_z + L * b3, 1000.0, scorch * 0.3, 0.2)
		wreck.add_child(front)
		wreck.add_child(rear)
		_place_section(front, nose_z + L * b3 * 0.5, site_w, r.randf_range(-15, 15), -1.5, r.randf_range(-6, 6), 0.3)
		var bw2 := site_w - Vector3(dir2.x, 0, dir2.y) * L * 0.55
		_place_section(rear, nose_z + L * (b3 + 1.0) * 0.5, _wv(bw2.x, bw2.z), r.randf_range(-20, 20), 2.0, r.randf_range(-8, 8), 0.2)
	# debris field along the slide path and fanning ahead of the main wreckage
	var lc := Airlines.livery_colors(String(world.get("airline", "SKF")))
	var body_c: Color = lc.get("body", Color(0.9, 0.9, 0.92))
	var acc_c: Color = lc.get("tail", Color(0.2, 0.3, 0.6))
	var mb := MeshBuilder.new()
	var n := int(60 + sev * 140)
	for i in n:
		var along := r.randf_range(-trail - 30.0, 160.0 * sev + 40.0)
		var spread := (12.0 + absf(along) * 0.25) * r.randf_range(-1.0, 1.0)
		var px := site_w.x + dir2.x * along + side2.x * spread
		var pz := site_w.z + dir2.y * along + side2.y * spread
		var gy := Geo.ground_height(px, pz)
		var big := r.randf() < 0.12
		var sz := Vector3(r.randf_range(0.3, 2.4), r.randf_range(0.05, 0.6), r.randf_range(0.3, 3.0)) * (2.2 if big else 1.0)
		var b2b := Basis.from_euler(Vector3(r.randf_range(-0.7, 0.7), r.randf() * TAU, r.randf_range(-0.7, 0.7)))
		var col := body_c if r.randf() < 0.6 else (acc_c if r.randf() < 0.5 else Color(0.25, 0.25, 0.27))
		col = col.darkened(r.randf_range(0.0, 0.75) * scorch)
		mb.add_rounded_box(_local(Vector3(px, gy + sz.y * 0.3, pz)), sz, col, 0.12, 6, 4, b2b)
		if r.randf() < 0.05:
			# an engine nacelle or a wheel
			var ep := _local(Vector3(px, gy + 1.0, pz))
			var ed := Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 0.2), r.randf_range(-1, 1)).normalized()
			mb.add_cylinder(ep - ed * 1.8, ep + ed * 1.8, 1.0, 0.85, 14, Color(0.3, 0.3, 0.32).darkened(scorch * 0.5))
		elif r.randf() < 0.08:
			var cp := _local(Vector3(px, gy + 0.35, pz))
			mb.add_box(cp, Vector3(0.7, 0.45, 0.5), [Color(0.1, 0.12, 0.3), Color(0.5, 0.1, 0.1), Color(0.15, 0.15, 0.15), Color(0.6, 0.45, 0.2)][r.randi() % 4])
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.vertex_color_is_srgb = true
	dm.roughness = 0.6
	dm.metallic = 0.3
	var debris := MeshInstance3D.new()
	debris.mesh = mb.commit()
	debris.material_override = dm
	wreck.add_child(debris)
	# ground scar from first impact to the wreckage, and scorched earth around the fires
	var mid_w := (impact_w + site_w) * 0.5
	var scar := NewsFX.decal("scar", Vector3(26.0 + sev * 20.0, 30.0, trail + 70.0))
	scar.position = _local(Vector3(mid_w.x, Geo.ground_height(mid_w.x, mid_w.z), mid_w.z))
	scar.rotation.y = atan2(dir2.x, dir2.y)
	wreck.add_child(scar)
	for k2 in 3 + int(sev * 4):
		var sc := NewsFX.decal("scorch", Vector3.ONE * r.randf_range(30.0, 70.0) * (0.6 + sev * 0.6) + Vector3(0, 30, 0))
		var al := r.randf_range(-trail * 0.3, 60.0)
		var sp := r.randf_range(-25.0, 25.0)
		sc.position = _local(_wv(site_w.x + dir2.x * al + side2.x * sp, site_w.z + dir2.y * al + side2.y * sp))
		sc.rotation.y = r.randf() * TAU
		wreck.add_child(sc)
	if sev >= 0.88:
		var crater := NewsFX.decal("scorch", Vector3(48.0, 40.0, 60.0))
		crater.position = _local(impact_w)
		wreck.add_child(crater)


# ================================================================== the response at the site
func _build_site() -> void:
	site_root = Node3D.new()
	view.dynamic_root.add_child(site_root)
	fires = Node3D.new()
	view.dynamic_root.add_child(fires)
	smoke = Node3D.new()
	view.dynamic_root.add_child(smoke)
	fireball = NewsFX.fireball()
	view.dynamic_root.add_child(fireball)
	var r := _rng
	var burning := bool(world.get("fire", true)) and not ditch
	if burning:
		var spots := [site_w, site_w - Vector3(dir2.x, 0, dir2.y) * 18.0 + Vector3(side2.x, 0, side2.y) * 8.0, (impact_w + site_w) * 0.5]
		for i in spots.size():
			var sw: Vector3 = spots[i]
			var f := NewsFX.flames(2.4 - i * 0.5)
			f.position = _local(_wv(sw.x, sw.z, 1.0))
			fires.add_child(f)
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.55, 0.2)
			fl.omni_range = 90.0
			fl.light_energy = 6.0
			fl.position = f.position + Vector3(0, 6.0, 0)
			fl.shadow_enabled = i == 0
			fires.add_child(fl)
			_fire_lights.append(fl)
		var col := NewsFX.smoke_column(1.6, wind, 1.0, 200)
		col.position = _local(_wv(site_w.x, site_w.z, 6.0))
		col.name = "Main"
		smoke.add_child(col)
		var col2 := NewsFX.smoke_column(1.0, wind, 0.85, 110)
		col2.position = _local(_wv(impact_w.x, impact_w.z, 3.0))
		smoke.add_child(col2)
	else:
		var wisp := NewsFX.smoke_column(0.6, wind, 0.4, 60)
		wisp.position = _local(_wv(site_w.x, site_w.z, 2.0))
		smoke.add_child(wisp)
	# fire tenders around the wreckage, monitors on the fire
	var lime := {"main": VehicleBuilder.LIME}
	var n_arff := 4 + r.randi() % 3
	for i2 in n_arff:
		var a := float(i2) / n_arff * TAU + r.randf_range(-0.2, 0.2)
		var rad := 38.0 + r.randf_range(0.0, 14.0)
		var px := site_w.x + cos(a) * rad
		var pz := site_w.z + sin(a) * rad
		var v := VehicleBuilder.build("arff", lime)
		site_root.add_child(v)
		v.position = _local(_wv(px, pz))
		var to := Vector2(site_w.x - px, site_w.z - pz).normalized()
		v.rotation.y = atan2(-to.x, -to.y)
		v.set_meta("phase", "response")
		if burning and i2 < 3:
			var jt := NewsFX.jet(Vector3(to.x, 0.32, to.y), 26.0, i2 % 2 == 0)
			jt.position = v.position + Vector3(to.x * 3.0, 3.2, to.y * 3.0)
			jt.set_meta("phase", "response")
			site_root.add_child(jt)
	# foam on the ground near the wreck
	for k in 4:
		var fo := NewsFX.decal("foam", Vector3(r.randf_range(14, 26), 20, r.randf_range(14, 26)))
		fo.position = _local(_wv(site_w.x + r.randf_range(-20, 20), site_w.z + r.randf_range(-20, 20)))
		fo.set_meta("phase", "response")
		site_root.add_child(fo)
	# ambulances lined up along the access route, a command vehicle
	var access := Vector2(-side2.x, -side2.y)
	for i3 in 5:
		var d := 140.0 + i3 * 13.0
		var px2 := site_w.x + access.x * d + dir2.x * 20.0
		var pz2 := site_w.z + access.y * d + dir2.y * 20.0
		var amb := VehicleBuilder.build("ambulance", {})
		site_root.add_child(amb)
		amb.position = _local(_wv(px2, pz2))
		amb.rotation.y = atan2(-dir2.x, -dir2.y) + PI * 0.5
		amb.set_meta("phase", "late2")
	var cmdv := VehicleBuilder.build("follow_me", {})
	site_root.add_child(cmdv)
	cmdv.position = _local(_wv(site_w.x + access.x * 110.0 - dir2.x * 30.0, site_w.z + access.y * 110.0 - dir2.y * 30.0))
	# triage and investigation tents
	var tri := NewsProps.tent(Vector3(8, 3.2, 6), Color(0.95, 0.95, 0.95), true)
	site_root.add_child(tri)
	tri.position = _local(_wv(site_w.x + access.x * 120.0 - dir2.x * 12.0, site_w.z + access.y * 120.0 - dir2.y * 12.0))
	tri.rotation.y = atan2(access.x, access.y)
	tri.set_meta("phase", "response")
	var inv_tent := NewsProps.tent(Vector3(10, 3.6, 7), Color(0.92, 0.94, 0.96), false)
	site_root.add_child(inv_tent)
	inv_tent.position = _local(_wv(site_w.x + access.x * 80.0 + dir2.x * 40.0, site_w.z + access.y * 80.0 + dir2.y * 40.0))
	inv_tent.set_meta("phase", "late")
	# light towers (lit at night)
	var night := view.night > 0.4
	for i4 in 4:
		var a2 := float(i4) / 4.0 * TAU + 0.6
		var lp := _local(_wv(site_w.x + cos(a2) * 70.0, site_w.z + sin(a2) * 70.0))
		var lt := NewsProps.light_tower(lp, _local(site_w) + Vector3(0, 2, 0), true)
		site_root.add_child(lt)
		_towers.append(lt)
	# evidence markers on the debris
	var mk := MeshBuilder.new()
	for i5 in 40:
		var al := r.randf_range(-site_w.distance_to(impact_w) - 20.0, 120.0)
		var sp := r.randf_range(-30.0, 30.0)
		var mp := _local(_wv(site_w.x + dir2.x * al + side2.x * sp, site_w.z + dir2.y * al + side2.y * sp))
		var one := NewsProps.marker(Color(1.0, 0.85, 0.05))
		mk.add_mesh_builder(one, Transform3D(Basis(Vector3.UP, r.randf() * TAU), mp))
	var mmi := MeshInstance3D.new()
	mmi.mesh = mk.commit()
	mmi.material_override = NewsStage.vcolor_mat(0.5, 0.0)
	mmi.set_meta("phase", "investigation")
	site_root.add_child(mmi)
	_cordon_and_people(night)
	_city_damage(burning)


## A crash in town: the buildings it went through are torn open, floors hanging and burning,
## with fire crews on the ground and on an aerial ladder fighting the building fires.
func _city_damage(burning: bool) -> void:
	var urban := float(Geo.main_sampler.landuse(site_w.x, site_w.z).urban) if Geo.main_sampler else 0.0
	if urban < 0.3 and not bool(world.get("force_urban", false)):
		return
	var r := U.rng(int(world.get("seed", 1)) + 4242)
	var fwd := Vector3(dir2.x, 0, dir2.y)
	var side := Vector3(side2.x, 0, side2.y)
	var idx := int(people.get_meta("count", 0))
	var mat := NewsStage.vcolor_mat(0.85, 0.0)
	city_torn = Node3D.new()
	view.dynamic_root.add_child(city_torn)
	city_intact = Node3D.new()
	city_intact.visible = false
	view.dynamic_root.add_child(city_intact)
	for b in 9:
		# torn ones straddle the path the aircraft took through the block; intact ones further out
		var torn := b < 4
		var along := r.randf_range(-70.0, 30.0) if torn else r.randf_range(-160.0, 120.0)
		var across := (r.randf_range(18.0, 34.0) if torn else r.randf_range(55.0, 120.0)) * (1.0 if b % 2 == 0 else -1.0)
		var bw := site_w + fwd * along + side * across
		var base := _local(_wv(bw.x, bw.z))
		var w := r.randf_range(14.0, 24.0)
		var d := r.randf_range(14.0, 22.0)
		var floors := r.randi_range(3, 9)
		var fh := 3.3
		var wall := Color.from_hsv(r.randf_range(0.05, 0.12), r.randf_range(0.08, 0.25), r.randf_range(0.55, 0.8))
		var mb := MeshBuilder.new()
		# the bite: where the wing or fuselage went through, on the face toward the wreck path
		var to_path := -side * signf(across)
		var bite := to_path * (w * 0.5) + fwd * r.randf_range(-w * 0.3, w * 0.3) + Vector3(0, r.randf_range(1.0, floors * fh * 0.6), 0)
		var bite_r := r.randf_range(6.0, 11.0) if torn else 0.0
		var ax := Basis.looking_at(fwd, Vector3.UP)
		for fl in floors:
			var y0 := fl * fh
			# slab
			var slab_c := Vector3(0, y0 + fh - 0.15, 0)
			if torn and (slab_c - bite).length() < bite_r * 0.8:
				# broken slab hanging down into the hole
				var hang := Transform3D(Basis(fwd.normalized(), deg_to_rad(r.randf_range(14.0, 32.0)) * signf(across)), slab_c + to_path * 2.0 + Vector3(0, -1.2, 0))
				mb.add_box_xf(hang, Vector3(w * 0.55, 0.3, d * 0.5), Color(0.38, 0.36, 0.34))
			else:
				mb.add_box(slab_c, Vector3(w, 0.3, d), wall.darkened(0.25))
			# walls as a grid of panels, leaving out the ones inside the bite
			for face in 4:
				var n := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][face] as Vector3
				var span := d if face < 2 else w
				var cols := 5
				for k in cols:
					var u := (float(k) + 0.5) / cols - 0.5
					var off := n * ((w if face < 2 else d) * 0.5)
					var t := Vector3(n.z, 0, n.x) * u * span
					var pc := off + t + Vector3(0, y0 + fh * 0.5, 0)
					var hole := torn and (pc - bite).length() < bite_r
					var near := torn and (pc - bite).length() < bite_r + 3.0
					if hole:
						continue
					var col := wall.darkened(0.55) if near else wall
					var sz := Vector3(0.35, fh, span / cols) if face < 2 else Vector3(span / cols, fh, 0.35)
					mb.add_box(pc, sz, col)
					# a window band, lit inside, blown out and black near the hole
					var wc := Color(0.08, 0.08, 0.08) if near else (Color(0.95, 0.82, 0.5) if r.randf() < 0.25 else Color(0.2, 0.26, 0.32))
					mb.add_box(pc + n * 0.2 + Vector3(0, 0.2, 0), Vector3(0.05, 1.3, span / cols * 0.6) if face < 2 else Vector3(span / cols * 0.6, 1.3, 0.05), wc)
		# roof
		mb.add_box(Vector3(0, floors * fh + 0.4, 0), Vector3(w, 0.8, d), wall.darkened(0.35))
		if torn:
			# rubble spilling out of the hole into the street, scorched interior
			for k2 in 26:
				var rp := Vector3(bite.x, 0, bite.z) + to_path * r.randf_range(0.0, 14.0) + fwd * r.randf_range(-7.0, 7.0)
				var rs := r.randf_range(0.6, 2.6)
				mb.add_box_xf(Transform3D(Basis(Vector3(r.randf(), 1, r.randf()).normalized(), r.randf() * TAU), rp + Vector3(0, rs * 0.3, 0)),
					Vector3(rs, rs * 0.6, rs * r.randf_range(0.6, 1.4)), [Color(0.4, 0.38, 0.35), wall.darkened(0.4), Color(0.12, 0.11, 0.1)][k2 % 3])
			mb.add_box(bite - to_path * 3.0, Vector3(w * 0.4, bite_r, d * 0.4), Color(0.05, 0.045, 0.04))
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = mat
		mi.position = base
		(city_torn if torn else view.dynamic_root).add_child(mi)
		if not torn:
			continue
		var whole := MeshBuilder.new()
		whole.add_box(Vector3(0, floors * fh * 0.5, 0), Vector3(w, floors * fh, d), wall)
		for fl3 in floors:
			whole.add_box(Vector3(0, fl3 * fh + 1.8, 0), Vector3(w + 0.1, 1.3, d + 0.1), Color(0.2, 0.26, 0.32))
		whole.add_box(Vector3(0, floors * fh + 0.4, 0), Vector3(w, 0.8, d), wall.darkened(0.35))
		var wi := MeshInstance3D.new()
		wi.mesh = whole.commit()
		wi.material_override = mat
		wi.position = base
		city_intact.add_child(wi)
		var hole_l := base + bite
		torn_spots.append(_world_of(hole_l))
		if burning:
			var fl2 := NewsFX.flames(1.6 + r.randf() * 0.8)
			fl2.position = hole_l
			fires.add_child(fl2)
			var lt := OmniLight3D.new()
			lt.light_color = Color(1.0, 0.55, 0.2)
			lt.light_energy = 4.0
			lt.omni_range = 30.0
			lt.position = hole_l + to_path * 3.0
			fires.add_child(lt)
			_fire_lights.append(lt)
			var col2 := NewsFX.smoke_column(1.1, wind, 0.9, 90)
			col2.position = hole_l + Vector3(0, 3, 0)
			smoke.add_child(col2)
		# an engine in the street and firefighters with hoses on the hole, an aerial ladder on the tall ones
		var truck_p := base + to_path * (w * 0.5 + 9.0) + fwd * r.randf_range(-6.0, 6.0)
		var v := VehicleBuilder.build("arff", {"main": Color(0.78, 0.08, 0.06)})
		v.position = Vector3(truck_p.x, _local(_wv(bw.x, bw.z)).y, truck_p.z)
		v.rotation.y = atan2(-fwd.x, -fwd.z)
		v.set_meta("phase", "response")
		site_root.add_child(v)
		if floors >= 5:
			var boom := MeshBuilder.new()
			var top := hole_l + to_path * 6.0 + Vector3(0, 2.0, 0)
			var foot := v.position + Vector3(0, 3.2, 0)
			var mid := (top + foot) * 0.5
			var bx := Basis.looking_at((top - foot).normalized(), Vector3.UP)
			boom.add_box_xf(Transform3D(bx, mid), Vector3(0.8, 0.6, foot.distance_to(top)), Color(0.85, 0.85, 0.82))
			boom.add_box(top + Vector3(0, -0.6, 0), Vector3(1.8, 1.1, 1.4), Color(0.8, 0.1, 0.06))
			var bm := MeshInstance3D.new()
			bm.mesh = boom.commit()
			bm.material_override = mat
			bm.set_meta("phase", "response")
			site_root.add_child(bm)
			if burning:
				var jt0 := NewsFX.jet(((hole_l - top).normalized() + Vector3(0, 0.15, 0)).normalized(), 22.0, false)
				jt0.position = top
				jt0.set_meta("phase", "response")
				site_root.add_child(jt0)
		for k3 in 3:
			if idx >= 148:
				break
			var fp := base + to_path * (w * 0.5 + r.randf_range(5.0, 9.0)) + fwd * (float(k3) - 1.0) * 3.5
			var fw := _world_of(fp)
			_person(idx, _local(_wv(fw.x, fw.z)), atan2(hole_l.x - fp.x, hole_l.z - fp.z) + PI, "push", Crowd.Outfit.FIRE, 76000 + b * 7 + k3, Crowd.FLAG_HELMET)
			_site_people[idx] = "response"
			idx += 1
			if burning and k3 != 1:
				var aim := (hole_l - (fp + Vector3(0, 1.2, 0))).normalized()
				var jt := NewsFX.jet((aim + Vector3(0, 0.25, 0)).normalized(), 17.0, false)
				jt.position = fp + Vector3(0, 1.2, 0) + aim * 0.6
				jt.set_meta("phase", "response")
				site_root.add_child(jt)
	people.set_meta("count", idx)


func _world_of(l: Vector3) -> Vector3:
	return Vector3(view.wx(l), l.y, view.wz(l))


func _spots() -> void:
	## Where the witness films from and where the reporter does the stand-up: on open ground
	## with a clear line of sight to the wreckage.
	var best := -1e9
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var d := 560.0 + (i % 3) * 120.0
		var p := Vector2(site_w.x + cos(a) * d, site_w.z + sin(a) * d)
		if Geo.is_water(p.x, p.y):
			continue
		var g := Geo.ground_height(p.x, p.y)
		var score := _visibility(Vector3(p.x, g + 1.7, p.y), site_w + Vector3(0, 6, 0)) - absf(g - site_w.y) * 0.02
		var side_ok := absf(Vector2(cos(a), sin(a)).dot(dir2)) < 0.85
		if side_ok:
			score += 2.0
		if score > best:
			best = score
			standup_w = Vector3(p.x, g, p.y)
	# the witness stood beside the final part of the flight path
	# (a bystander's own clip picks its own spot: how far away, and from which side)
	var vseed := 0
	for sg in program.get("segments", []):
		if String(sg.kind) == "phone" and sg.has("variant"):
			vseed = int(sg.get("phone_seed", 1))
			phone_variant = String(sg.variant)
			break
	var vr := U.rng(vseed)
	var vdist: float = {"balcony": 950.0, "car": 520.0, "zoom": 2100.0, "runner": 480.0, "cctv": 110.0}.get(phone_variant, 750.0) * vr.randf_range(0.85, 1.15)
	var vang := vr.randf() * TAU
	if samples.size() > 4:
		var tgt := BroadcastPlayer.sample_at(samples, t_end - (1.0 if phone_variant == "cctv" else 6.0))
		var mid := Vector2(float(tgt[1]), float(tgt[2]))
		var best2 := -1e9
		for j in 16:
			var a2 := float(j) / 16.0 * TAU
			var p2 := mid + Vector2(cos(a2), sin(a2)) * vdist
			if Geo.is_water(p2.x, p2.y):
				continue
			var g2 := Geo.ground_height(p2.x, p2.y)
			var sc := _visibility(Vector3(p2.x, g2 + 1.6, p2.y), site_w + Vector3(0, 30, 0)) + _visibility(Vector3(p2.x, g2 + 1.6, p2.y), Vector3(mid.x, float(tgt[3]), mid.y))
			if vseed != 0:
				sc += cos(a2 - vang) * 0.7
			if sc > best2:
				best2 = sc
				witness_w = Vector3(p2.x, g2, p2.y)
	else:
		witness_w = standup_w


func _visibility(from: Vector3, to: Vector3) -> float:
	## Fraction of the sight line that clears the terrain (1 = fully visible).
	var ok := 0
	for k in 12:
		var f := (float(k) + 0.5) / 12.0
		var p := from.lerp(to, f)
		if Geo.height(p.x, p.z) < p.y - 1.0:
			ok += 1
	return float(ok) / 12.0


func _cordon_and_people(night: bool) -> void:
	var r := _rng
	var to_site := Vector2(site_w.x - standup_w.x, site_w.z - standup_w.z).normalized()
	var perp := Vector2(-to_site.y, to_site.x)
	# tape across the approach, a few metres behind the reporter
	var tape_c := Vector2(standup_w.x, standup_w.z) + to_site * 9.0
	var pts := []
	for i in 13:
		var o := float(i - 6) * 3.6
		var p := tape_c + perp * o + to_site * sin(float(i) * 0.7) * 0.6
		pts.append(_local(_wv(p.x, p.y)))
	var tape := NewsProps.cordon(pts, 1)
	site_root.add_child(tape)
	# police cars at the cordon with flashing bars
	for k in 3:
		var car := NewsProps.police_car()
		site_root.add_child(car)
		var cp := tape_c + to_site * (5.0 + k * 3.0) + perp * (-14.0 + k * 13.0)
		car.position = _local(_wv(cp.x, cp.y))
		car.rotation.y = atan2(-perp.x, -perp.y) + r.randf_range(-0.4, 0.4)
		_cars.append(car)
	var amb := VehicleBuilder.build("ambulance", {})
	site_root.add_child(amb)
	var ap := tape_c + to_site * 16.0 + perp * 22.0
	amb.position = _local(_wv(ap.x, ap.y))
	amb.rotation.y = atan2(-to_site.x, -to_site.y)
	VehicleBuilder.set_lamps(amb, true, night)
	_cars.append(amb)
	for v in site_root.get_children():
		if v.has_meta("phase") and v is Node3D and (v as Node3D).find_children("Lamps", "MeshInstance3D", true, false).size() > 0:
			VehicleBuilder.set_lamps(v, true, night)
	var idx := 0
	# reporter and camera operator at the stand-up spot
	standup_face = Vector3(-to_site.x, 0, -to_site.y)
	_person(idx, _local(standup_w), atan2(to_site.x, to_site.y), "talk", Crowd.Outfit.CIVIL, 30001, 0, Color(0.12, 0.2, 0.35))
	_site_people[idx] = "reporter"
	idx += 1
	# interviewee (eyewitness) a little further along the tape
	var iw := tape_c - to_site * 5.0 + perp * 9.0
	_person(idx, _local(_wv(iw.x, iw.y)), atan2(perp.x, perp.y) + PI * 0.5, "talk", Crowd.Outfit.CIVIL, 40000 + r.randi() % 9000)
	_site_people[idx] = "interviewee"
	idx += 1
	# police officers at the tape
	for k2 in 4:
		var pp := tape_c + to_site * 1.5 + perp * (-10.0 + k2 * 6.5)
		_person(idx, _local(_wv(pp.x, pp.y)), atan2(-to_site.x, -to_site.y), "stand", Crowd.Outfit.POLICE, 50000 + k2, Crowd.FLAG_HAT)
		_site_people[idx] = "any"
		idx += 1
	# onlookers along the tape, many filming
	for k3 in 16:
		var o2 := r.randf_range(-20.0, 20.0)
		var pp2 := tape_c - to_site * r.randf_range(1.2, 6.0) + perp * o2
		if pp2.distance_to(Vector2(standup_w.x, standup_w.z)) < 3.0:
			continue
		var pose: String = "film" if r.randf() < 0.55 else ["stand", "grief", "talk"][r.randi() % 3]
		_person(idx, _local(_wv(pp2.x, pp2.y)), atan2(-to_site.x, -to_site.y) + PI + r.randf_range(-0.4, 0.4), pose, Crowd.Outfit.CIVIL,
			60000 + r.randi() % 100000, Crowd.FLAG_PHONE if pose == "film" else 0)
		_site_people[idx] = "onlooker"
		idx += 1
	# firefighters and paramedics at the wreckage (response), investigators later
	for k4 in 14:
		var a := r.randf() * TAU
		var d := r.randf_range(18.0, 55.0)
		var fp := Vector2(site_w.x + cos(a) * d, site_w.z + sin(a) * d)
		var walk := k4 % 3 == 0
		var face := atan2(site_w.x - fp.x, site_w.z - fp.y) + PI
		_person(idx, _local(_wv(fp.x, fp.y)), face, "walk" if walk else ["stand", "push", "stand"][k4 % 3], Crowd.Outfit.FIRE, 70000 + k4, Crowd.FLAG_HELMET)
		_site_people[idx] = "response"
		if walk:
			var fp2 := fp + Vector2(cos(a), sin(a)) * -12.0
			_walkers.append([idx, Vector3(fp.x, 0, fp.y), Vector3(fp2.x, 0, fp2.y), 1.3])
		idx += 1
	var tri_c := Vector2(site_w.x, site_w.z) - side2 * 118.0 - dir2 * 6.0
	var survivors := maxi(int(world.get("aboard", 0)) - int(world.get("fatal", 0)), 0)
	for k5 in mini(12, 4 + survivors):
		var tp := tri_c + Vector2(r.randf_range(-12, 12), r.randf_range(-12, 12))
		if k5 % 3 == 0:
			_person(idx, _local(_wv(tp.x, tp.y)), r.randf() * TAU, "kneel", Crowd.Outfit.MEDIC, 80000 + k5)
		elif k5 % 3 == 1 and survivors > 0:
			_person(idx, _local(_wv(tp.x, tp.y)), r.randf() * TAU, "lie", Crowd.Outfit.CIVIL, 90000 + r.randi() % 50000, Crowd.FLAG_SOOT)
		else:
			_person(idx, _local(_wv(tp.x, tp.y)), r.randf() * TAU, "walk", Crowd.Outfit.MEDIC, 80100 + k5)
			_walkers.append([idx, Vector3(tp.x, 0, tp.y), Vector3(tp.x + 9.0, 0, tp.y + 4.0), 1.1])
		_site_people[idx] = "response"
		idx += 1
	for k6 in 9:
		var al := r.randf_range(-60.0, 80.0)
		var sp := r.randf_range(-25.0, 25.0)
		var ip := Vector2(site_w.x + dir2.x * al + side2.x * sp, site_w.z + dir2.y * al + side2.y * sp)
		_person(idx, _local(_wv(ip.x, ip.y)), r.randf() * TAU, ["kneel", "stand", "walk", "film"][k6 % 4], Crowd.Outfit.OFFICIAL, 95000 + k6, Crowd.FLAG_PHONE if k6 % 4 == 3 else 0)
		_site_people[idx] = "investigation"
		idx += 1
	# the witness who filmed the crash, and the people with them
	if witness_w != Vector3.ZERO and phone_variant != "car":
		for k7 in 3:
			var wp := Vector2(witness_w.x, witness_w.z) + Vector2(r.randf_range(-4, 4), r.randf_range(-4, 4))
			var target: Array = BroadcastPlayer.sample_at(samples, t_end - 3.0) if samples.size() > 2 else []
			var face2 := 0.0
			if not target.is_empty():
				face2 = atan2(float(target[1]) - wp.x, float(target[2]) - wp.y) + PI
			_person(idx, _local(_wv(wp.x, wp.y)), face2, ["film", "stand", "wave"][k7], Crowd.Outfit.CIVIL, 120000 + k7 * 7, Crowd.FLAG_PHONE if k7 == 0 else 0)
			_site_people[idx] = "witness"
			idx += 1
	people.set_meta("count", idx)


# ================================================================== airports (benign stories, terminals)
func _build_airport_scene() -> void:
	var icao := String(world.get("icao", "SKPC"))
	view.airports.ensure_loaded(icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var r := _rng
	if samples.size() > 4:
		# the spotter's spot: beside the approach, a kilometre before the threshold
		var s_thr: Array = samples[0]
		for s in samples:
			if float(s[3]) - float(ap.elev) < 40.0:
				s_thr = s
				break
		var p := Vector2(float(s_thr[1]), float(s_thr[2]))
		var d := Vector2(sin(deg_to_rad(float(s_thr[8]))), -cos(deg_to_rad(float(s_thr[8]))))
		var sd := Vector2(-d.y, d.x)
		var sp := p - d * 700.0 + sd * 380.0
		_spotter_w = _wv(sp.x, sp.y, 1.7)
		var tw := p + d * 500.0 + sd * 260.0
		_tower_w = _wv(tw.x, tw.y, 6.0)
		if _emergency:
			for i in 3:
				var kind := "arff" if i < 2 else "ambulance"
				var vp := p + d * (900.0 + i * 30.0) + sd * 75.0
				var veh := VehicleBuilder.build(kind, {"main": VehicleBuilder.LIME} if kind == "arff" else {})
				view.dynamic_root.add_child(veh)
				veh.position = _local(_wv(vp.x, vp.y))
				veh.rotation.y = atan2(-d.x, -d.y)
				VehicleBuilder.set_lamps(veh, true, view.night > 0.4)
	# the terminal for stand-ups and interviews
	var L := AirportLayout.get_layout(icao)
	var stands: Array = L.get("stands", [])
	if not stands.is_empty():
		var sd2: Dictionary = stands[mini(2, stands.size() - 1)]
		var n: Vector2 = sd2.normal
		var face: Vector2 = sd2.get("facade_origin", sd2.stop)
		var spot := face + n * 48.0
		terminal_w = Vector3(float(ap.x) + spot.x, float(ap.elev), float(ap.z) + spot.y)
		terminal_look = Vector3(float(ap.x) + face.x, float(ap.elev) + 6.0, float(ap.z) + face.y)
		var parked := AircraftModel.new()
		view.dynamic_root.add_child(parked)
		parked.build(String(world.get("type", "s320")), String(world.get("airline", "SKF")), "", 1.0)
		var pp := face + n * (7.0 + float(spec.length) * float(spec.cg_frac))
		parked.position = view.world_to_local(float(ap.x) + pp.x, float(ap.elev) + float(spec.gear_height), float(ap.z) + pp.y)
		parked.rotation.y = -deg_to_rad(float(sd2.hdg))
		parked.animate_simple(1.0, 0.0, 0.0, {"nav": true, "beacon": false}, view.night, 0.0)
		var to_t := (terminal_look - terminal_w)
		var yaw := atan2(to_t.x, to_t.z)
		_person(0, _local(terminal_w), yaw + PI, "talk", Crowd.Outfit.CIVIL, 30001, 0, Color(0.12, 0.2, 0.35))
		_site_people[0] = "reporter"
		_person(1, _local(terminal_w + Vector3(n.x, 0, n.y) * -1.0 + Vector3(-n.y, 0, n.x) * 6.0), yaw + PI + 0.5, "talk", Crowd.Outfit.CIVIL, 40000 + r.randi() % 9000, Crowd.FLAG_BAG)
		_site_people[1] = "interviewee"
		for k in 10:
			var wp := terminal_w + Vector3(r.randf_range(-25, 25), 0, r.randf_range(-8, 8))
			_person(2 + k, _local(wp), r.randf() * TAU, ["walk", "stand", "stand"][k % 3], Crowd.Outfit.GROUND if k % 2 == 0 else Crowd.Outfit.CIVIL, 140000 + k)
			_site_people[2 + k] = "any"
			if k % 3 == 0:
				_walkers.append([2 + k, wp, wp + Vector3(r.randf_range(-20, 20), 0, r.randf_range(-6, 6)), 1.2])
		people.set_meta("count", 12)


func _replay_spots() -> void:
	## Ground cameras for the player's replay: by the runway at liftoff and at touchdown.
	_ground_flags.resize(samples.size())
	var was := true
	for i in samples.size():
		var s: Array = samples[i]
		var g := float(s[3]) - Geo.ground_height(float(s[1]), float(s[2])) < float(spec.gear_height) + 2.0
		_ground_flags[i] = 1 if g else 0
		if was and not g and _lift_t < 0.0:
			_lift_t = float(s[0])
		if not was and g:
			_touch_t = float(s[0])
		was = g
	for k in [[_lift_t, "lift"], [_touch_t, "touch"]]:
		if float(k[0]) < 0.0:
			continue
		var s2 := BroadcastPlayer.sample_at(samples, float(k[0]))
		var d := Vector2(sin(deg_to_rad(float(s2[8]))), -cos(deg_to_rad(float(s2[8]))))
		var sd := Vector2(-d.y, d.x)
		var p := Vector2(float(s2[1]), float(s2[2])) + sd * 180.0 + d * 120.0
		if String(k[1]) == "touch":
			_tower_w = _wv(p.x, p.y, 2.0)
		else:
			_spotter_w = _wv(p.x, p.y, 2.0)


# ================================================================== per frame
func enter(seg: Dictionary) -> void:
	_clock_set = -1.0
	var phase := String(seg.get("site", "none"))
	_set_phase(phase)


func _seg_clock(seg: Dictionary, lt: float, st: float) -> float:
	var crash_clock := float(world.get("clock", WorldSim.clock))
	var kind := String(seg.kind)
	if st >= 0.0 and kind in ["recon", "phone", "fdr", "overview", "impact", "replay"]:
		return crash_clock - (t_end - st)
	if kind in ["title", "findings", "cause", "factors", "recs", "remember"]:
		var d0 := floorf(crash_clock / 86400.0) * 86400.0 + 86400.0
		return d0 + 11.0 * 3600.0 + lt
	if mode == "airport":
		return float(world.get("air_clock", crash_clock)) - 1800.0 + lt + (1800.0 if kind in ["standup", "interview"] else 0.0)
	return float(seg.get("air", world.get("air_clock", crash_clock))) + lt


func _set_phase(phase: String) -> void:
	if phase == _phase:
		return
	_phase = phase
	if site_root == null:
		if not _buf0.is_empty():
			people.buf = _buf0.duplicate()
			people.dirty = true
			people.flush()
		return
	var late := phase in ["aftermath", "investigation"]
	for c in site_root.get_children():
		if not c.has_meta("phase"):
			continue
		var ph := String(c.get_meta("phase"))
		var vis := true
		match ph:
			"response":
				vis = phase in ["response", "impact"] and phase != "impact"
			"late":
				vis = late
			"investigation":
				vis = phase == "investigation"
			"late2":
				vis = phase in ["response", "aftermath", "investigation"]
		(c as Node3D).visible = vis
	var burning := bool(world.get("fire", true)) and not ditch
	if fires:
		fires.visible = burning and phase in ["impact", "response", "none"]
	if smoke:
		smoke.visible = phase in ["impact", "response", "aftermath", "none"]
		for p in smoke.get_children():
			var gp := p as GPUParticles3D
			gp.amount_ratio = 1.0 if phase in ["impact", "response", "none"] else 0.25
	if not _buf0.is_empty():
		people.buf = _buf0.duplicate()
		people.dirty = true
	for i in _site_people.keys():
		var role := String(_site_people[i])
		var show := true
		match role:
			"response":
				show = phase == "response"
			"investigation":
				show = phase in ["aftermath", "investigation"]
			"onlooker", "reporter", "interviewee", "any":
				show = phase in ["response", "aftermath", "investigation"] or mode == "airport"
			"witness":
				show = phase in ["pre", "impact", "none"]
		if not show:
			people.hide_person(int(i))
		if hero_slots.has(i):
			(hero_slots[i] as Node3D).visible = show
	people.flush()


func apply(seg: Dictionary, shot: Dictionary, lt: float, st: float, delta: float) -> void:
	if view == null:
		return
	var sample_t := BroadcastPlayer.seg_sample_time(seg, lt, samples)
	var clock := _seg_clock(seg, lt, sample_t)
	if _clock_set < 0.0 or absf(clock - _clock_set) > 30.0:
		view.set_time(clock)
		view.weather_override = _weather_at(site_w.x, site_w.z, clock)
		view.update_weather(true)
		view.update_lighting(true)
	else:
		view.set_time(clock)
	_clock_set = clock
	var kind := String(seg.kind)
	var recon_kind := not (seg.get("recon", {}) as Dictionary).is_empty()
	var after := recon_kind and sample_t >= t_end - 0.05 and mode != "airport" and String(world.get("ending", "")) in ["crash", "ditch"]
	var show_plane := recon_kind and not after and not samples.is_empty()
	if mode == "airport" and not samples.is_empty():
		show_plane = true
		if sample_t < 0.0:
			sample_t = float(samples[samples.size() - 1][0])
	if show_plane:
		model.visible = true
		_pose_aircraft(sample_t, delta)
	else:
		model.visible = false
	if wreck:
		wreck.visible = after or not recon_kind
	if city_torn:
		city_torn.visible = after or not recon_kind
		city_intact.visible = not city_torn.visible
	if mode == "incident" and recon_kind:
		_set_phase("impact" if after else "pre")
		if site_root:
			site_root.visible = false
		if fires:
			fires.visible = after and bool(world.get("fire", true)) and not ditch
		if smoke:
			smoke.visible = after and sample_t - t_end > 1.5
	elif site_root:
		site_root.visible = true
	if fireball:
		NewsFX.fireball_pose(fireball, (sample_t - t_end) if after and not ditch else -1.0, 18.0 + severity * 22.0)
		fireball.position = _local(impact_w)
	if ribbon:
		ribbon.visible = bool(seg.get("path", false)) or String(shot.get("cam", "")) in ["analysis", "overview"]
	var night := view.night
	for i in _cars.size():
		var car: Node3D = _cars[i]
		if car.has_node("Red"):
			NewsProps.flash(car, lt + i * 0.37, float(i) * 0.31, night)
	for k in _fire_lights.size():
		var fl: OmniLight3D = _fire_lights[k]
		fl.light_energy = (5.0 + 3.0 * night) * (0.75 + 0.25 * sin(lt * 13.0 + k) * sin(lt * 7.3 + k * 2.0))
	for tw in _towers:
		(tw as Node3D).visible = night > 0.35 and _phase in ["response", "aftermath", "investigation"]
	_update_walkers(lt)
	_camera(seg, shot, lt, st, sample_t, delta)
	if has_meta("closeup") and not torn_spots.is_empty():
		# test hook: frame the first torn building
		var h := _local(torn_spots[0])
		_look(h + (get_meta("closeup") as Vector3), h + Vector3(0, -3, 0), 50.0)


func _update_walkers(lt: float) -> void:
	for w in _walkers:
		var i := int(w[0])
		if people.buf[i * Crowd.STRIDE + 7] < -9000.0:
			continue
		var a: Vector3 = w[1]
		var b: Vector3 = w[2]
		var dist := a.distance_to(b)
		var period := dist / float(w[3]) * 2.0
		var ph := fmod(lt + i * 1.7, period) / period
		var f := ph * 2.0 if ph < 0.5 else 2.0 - ph * 2.0
		var p := a.lerp(b, f)
		var dirv := (b - a) if ph < 0.5 else (a - b)
		var pos := _local(_wv(p.x, p.z))
		var o := i * Crowd.STRIDE
		var sc := Vector3(people.buf[o + 0], people.buf[o + 4], people.buf[o + 8]).length()
		var yaw := atan2(-dirv.x, -dirv.z)
		people.set_transform_only(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), pos))
	people.flush()


# ================================================================== cameras
func _camera(seg: Dictionary, shot: Dictionary, lt: float, st: float, sample_t: float, delta: float) -> void:
	var c := String(shot.get("cam", "default"))
	var sd := float(shot.get("dur", 6.0))
	var f := ease01(st / maxf(sd, 0.1))
	var target := model.global_position
	var L := float(spec.length)
	var site_l := _local(site_w)
	var shake := Vector2.ZERO
	_dof(false)
	cam.far = 15000.0 if c in ["standup", "standup_wide", "interview"] else 90000.0
	cam.near = 0.1 if c in ["standup", "interview"] else 0.3
	if c == "director":
		c = _director(sample_t, lt)
	match c:
		"recon_aerial":
			var s_end: Array = samples[samples.size() - 1] if not samples.is_empty() else []
			var b := Vector2(float(s_end[1]), float(s_end[2])) if not s_end.is_empty() else Vector2(site_w.x, site_w.z)
			var ap := b - dir2 * 2600.0 - side2 * 1900.0
			var from := _local(Vector3(ap.x, Geo.ground_height(ap.x, ap.y) + 700.0, ap.y))
			var dist := from.distance_to(target)
			_look(from, target, clampf(rad_to_deg(2.0 * atan(L * 6.0 / maxf(dist, 1.0))), 3.0, 50.0))
		"recon_side", "fdr_side":
			var back := Vector3(dir2.x, 0, dir2.y)
			var sv := Vector3(side2.x, 0, side2.y)
			var from2 := target + sv * L * 2.6 + back * L * 0.4 + Vector3(0, L * 0.25, 0)
			_look(from2, target + back * L * 0.3, 40.0)
		"recon_chase", "fdr_chase", "chase":
			var bk := model.global_transform.basis.z
			bk.y = 0.0
			bk = bk.normalized() if bk.length() > 0.01 else Vector3(0, 0, 1)
			var want := target + bk.rotated(Vector3.UP, deg_to_rad(18.0)) * L * 2.3 + Vector3(0, L * 0.5, 0)
			_look(want, target, 52.0)
		"recon_ground", "fdr_ground":
			var gp := impact_w - Vector3(dir2.x, 0, dir2.y) * 260.0 + Vector3(side2.x, 0, side2.y) * 300.0
			var from3 := _local(_wv(gp.x, gp.z, 1.8))
			var aim := target if model.visible else _local(impact_w) + Vector3(0, 30.0 + clampf(sample_t - t_end, 0.0, 8.0) * 8.0, 0)
			var dist3 := from3.distance_to(aim)
			_look(from3, aim, clampf(rad_to_deg(2.0 * atan(L * 2.2 / maxf(dist3, 1.0))), 14.0, 55.0) if model.visible else 40.0)
		"fdr_cockpit", "cockpit":
			var eye := Vector3(-0.5, float(spec.fuse_h) * 0.18, -L * float(spec.cg_frac) + AircraftModel.pilot_eye_station(spec))
			cam.global_transform = model.global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-6.0), 0, 0)), eye)
			cam.fov = 68.0
		"analysis", "orbit":
			var c2 := target + Vector3(0, -120.0, 0) if c == "analysis" else target
			var yaw := deg_to_rad(30.0 + lt * 5.0)
			var rad := 1700.0 if c == "analysis" else L * 2.6
			_look(c2 + Vector3(sin(yaw), 0.5, cos(yaw)) * rad, c2, 44.0 if c == "analysis" else 50.0)
		"overview":
			var mid_s: Array = BroadcastPlayer.sample_at(samples, (float(samples[0][0]) + t_end) * 0.5) if not samples.is_empty() else []
			var mid := _local(Vector3(float(mid_s[1]), float(mid_s[3]), float(mid_s[2]))) if not mid_s.is_empty() else site_l
			var span := 4000.0
			if samples.size() > 1:
				span = maxf(Vector2(float(samples[0][1]), float(samples[0][2])).distance_to(Vector2(site_w.x, site_w.z)), 2000.0)
			var yaw2 := atan2(side2.x, side2.y) + lt * 0.02
			_look(mid + Vector3(sin(yaw2) * span * 0.9, span * 0.55, cos(yaw2) * span * 0.9), mid + Vector3(0, -150, 0), 42.0)
		"phone":
			var pv := String(seg.get("variant", phone_variant))
			var hold := _local(witness_w) + Vector3(0, {"balcony": 13.5, "car": 1.25}.get(pv, 1.55), 0)
			var after := maxf(sample_t - t_end, 0.0)
			var impact_l := _local(impact_w)
			if pv == "runner" and after > 1.5:
				# the filmer starts running toward the smoke, phone still up
				var run := impact_l - hold
				run.y = 0.0
				hold += run.normalized() * minf((after - 1.5) * 4.2, run.length() * 0.4)
				hold.y += absf(sin(lt * 9.0)) * 0.09
				shake = handheld(lt, 2.4, 5.0) + Vector2(sin(lt * 9.0) * 0.8, cos(lt * 18.0) * 0.5)
			elif pv == "car":
				shake = handheld(lt, 0.12, 6.0) + Vector2(0, sin(lt * 31.0) * 0.05)
			else:
				var k := {"zoom": 1.6, "balcony": 0.7}.get(pv, 1.1) as float
				shake = handheld(lt, k, 3.0) + Vector2(sin(lt * 23.0) * 0.12, cos(lt * 19.0) * 0.12) * k
			var aim2 := target if model.visible else impact_l + Vector3(0, 25.0 + clampf(after, 0.0, 6.0) * 12.0, 0)
			var fill := {"zoom": 1.6, "car": 9.0, "balcony": 4.5}.get(pv, 3.5) as float
			var zoom := clampf(rad_to_deg(2.0 * atan(float(spec.span) * fill / maxf(hold.distance_to(aim2), 1.0))), 2.5 if pv == "zoom" else 5.0, 62.0)
			if not model.visible:
				zoom = {"zoom": 12.0, "car": 58.0}.get(pv, 34.0)
			if pv == "cctv":
				# a security camera bolted to a building: fixed, wide, aimed across the street
				var mount := _local(witness_w) + Vector3(0, 9.0, 0)
				_look(mount, impact_l + Vector3(0, 14.0, 0), 62.0)
				shake = Vector2.ZERO
			elif pv == "car":
				# dashcam: fixed wide lens looking down the road, the crash happens off to one side
				var fwd := (aim2 - hold)
				fwd.y = 0.0
				var side := Vector3(fwd.z, 0, -fwd.x).normalized() * fwd.length() * 0.35
				_look(hold, hold + fwd + side + Vector3(0, fwd.length() * 0.06, 0), 64.0)
			else:
				_look(hold, aim2, lerpf(cam.fov, zoom, 0.15) if delta > 0.0 else zoom)
		"heli_wide", "heli_close", "heli_orbit", "site_orbit", "site_high", "impact_site":
			var yaw3 := deg_to_rad(40.0 + (lt + float(seg.t0) * 3.0) * (2.2 if c == "heli_orbit" else 1.0))
			var rad2: float = {"heli_wide": 950.0, "heli_close": 820.0, "heli_orbit": 760.0, "site_orbit": 420.0, "site_high": 650.0, "impact_site": 260.0}[c]
			var hgt: float = {"heli_wide": 380.0, "heli_close": 330.0, "heli_orbit": 300.0, "site_orbit": 160.0, "site_high": 420.0, "impact_site": 70.0}[c]
			var from4 := site_l + Vector3(sin(yaw3) * rad2, hgt, cos(yaw3) * rad2)
			var fov: float = {"heli_wide": 26.0, "heli_close": 9.0 + 3.0 * (1.0 - f), "heli_orbit": 15.0, "site_orbit": 36.0, "site_high": 30.0, "impact_site": 44.0}[c]
			if c.begins_with("heli"):
				shake = handheld(lt, 0.18, 7.0)
			_look(from4, site_l + Vector3(0, 6, 0), fov)
		"standup", "standup_wide":
			if mode == "airport" or String(seg.get("where", "")) == "terminal":
				_terminal_shot(c, lt, f)
			else:
				var rep := _local(standup_w) + Vector3(0, 1.6, 0)
				var face := standup_face
				var dist5 := 3.4 if c == "standup" else 7.5
				var from5 := rep + face * dist5 + Vector3(face.z, 0, -face.x) * (0.6 if c == "standup" else 2.0) + Vector3(0, -0.05, 0)
				shake = handheld(lt, 0.05, 1.0)
				_look(from5, rep + Vector3(-face.z, 0, face.x) * 0.25 - Vector3(0, 0.1, 0), 30.0 if c == "standup" else 44.0)
				_dof(c == "standup", dist5, 0.05)
		"interview":
			if mode == "airport" or String(seg.get("where", "")) == "terminal":
				_terminal_shot("interview", lt, f)
			else:
				var iv := Vector3.ZERO
				for k in _site_people.keys():
					if String(_site_people[k]) == "interviewee":
						var o := int(k) * Crowd.STRIDE
						iv = Vector3(people.buf[o + 3], people.buf[o + 7], people.buf[o + 11])
				var head := people.to_global(iv) + Vector3(0, 1.58, 0)
				var away := (head - site_l)
				away.y = 0.0
				away = away.normalized()
				var from6 := head + away * 2.2 + Vector3(away.z, 0, -away.x) * 0.7
				shake = handheld(lt, 0.04, 2.0)
				_look(from6, head + Vector3(-away.z, 0, away.x) * 0.2, 26.0)
				_dof(true, 2.3, 0.08)
		"spotter_long", "tower":
			var sp := _local(_spotter_w if c == "spotter_long" else _tower_w)
			var d7 := sp.distance_to(target)
			shake = handheld(lt, 0.12, 4.0)
			_look(sp, target, clampf(rad_to_deg(2.0 * atan(L * 1.6 / maxf(d7, 1.0))), 2.5, 50.0))
		"spotter_track", "flyby":
			var tp := _local(_tower_w)
			var d8 := tp.distance_to(target)
			shake = handheld(lt, 0.08, 5.0)
			_look(tp, target, clampf(rad_to_deg(2.0 * atan(L * 2.2 / maxf(d8, 1.0))), 4.0, 55.0))
		"spotter_rollout":
			var rp := _local(_tower_w) + Vector3(0, 8, 0)
			_look(rp, target, 34.0)
		_:
			_look(site_l + Vector3(300, 160, 300), site_l, 40.0)
	if shake != Vector2.ZERO:
		cam.rotate_object_local(Vector3.UP, deg_to_rad(shake.x))
		cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(shake.y))
	var g := Geo.ground_height(view.wx(cam.global_position), view.wz(cam.global_position)) + 1.2
	if cam.global_position.y < g:
		cam.global_position.y = g


func _terminal_shot(c: String, lt: float, f: float) -> void:
	var rep := _local(terminal_w) + Vector3(0, 1.6, 0)
	var look := _local(terminal_look)
	var away := rep - look
	away.y = 0.0
	away = away.normalized()
	if c == "interview":
		var ip := Vector3.ZERO
		for k in _site_people.keys():
			if String(_site_people[k]) == "interviewee":
				var o := int(k) * Crowd.STRIDE
				ip = people.to_global(Vector3(people.buf[o + 3], people.buf[o + 7], people.buf[o + 11])) + Vector3(0, 1.58, 0)
		_look(ip + away * 2.3 + Vector3(away.z, 0, -away.x) * 0.6, ip, 26.0)
		_dof(true, 2.3, 0.08)
	else:
		var d := 3.4 if c == "standup" else 8.0
		_look(rep + away * d + Vector3(away.z, 0, -away.x) * 0.5, rep - Vector3(0, 0.1, 0) + Vector3(-away.z, 0, away.x) * 0.3, 30.0 if c == "standup" else 46.0)
		_dof(c == "standup", d, 0.04)
	var sh := handheld(lt, 0.05, 2.0)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(sh.x))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(sh.y))


func _director(sample_t: float, lt: float) -> String:
	## The replay's automatic camera: by the runway for takeoff and landing, chase and orbit
	## in the air, a look from the flight deck on final.
	if samples.is_empty():
		return "chase"
	var s := BroadcastPlayer.sample_at(samples, sample_t)
	var agl := float(s[3]) - Geo.ground_height(float(s[1]), float(s[2]))
	if _lift_t >= 0.0 and absf(sample_t - _lift_t) < 18.0 and _spotter_w != Vector3.ZERO:
		return "spotter_long"
	if _touch_t >= 0.0 and sample_t > _touch_t - 22.0 and sample_t < _touch_t + 25.0 and _tower_w != Vector3.ZERO:
		return "flyby"
	if agl < 400.0 and sample_t < t_end - 30.0 and sample_t > (_touch_t - 60.0 if _touch_t > 0.0 else t_end - 90.0):
		return "cockpit"
	var block := int(lt / 14.0) % 3
	return ["chase", "orbit", "recon_side"][block]
