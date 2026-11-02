extends Node
## What happens after an impact. Works out every person's injuries from the impact energy, the
## part of the fuselage they sat in, the direction of the impact, bracing and age; lights fires
## and smoke; scatters debris; runs the evacuation against a spreading fire; brings the crash
## tenders and ambulances; then hands the investigation, the per-person outcomes and the
## consequences for the pilot back to the flight session.

signal progress(text: String)

const INJ_NONE := 0
const INJ_MINOR := 1
const INJ_SERIOUS := 2
const INJ_CRITICAL := 3
const INJ_FATAL := 4

var session: FlightSession
var ac: Aircraft
var info: Dictionary
var t := 0.0
var stage := "impact"
var fire_level := 0.0
var fire_growth := 0.0
var severity := 0.5
var ditching := false
var player_injury := 0
var crew_out: Array = []
var counts := {}
var report: Dictionary = {}
var _fire_root: Node3D
var _flames: Array = []
var _smoke: GPUParticles3D
var _evac_started := false
var _rng := RandomNumberGenerator.new()
var _done := false
var _overlay: Control
var _overlay_label: RichTextLabel
var _lc: Dictionary = {}
var _fall_alt := 0.0


func begin(sess: Node, crash_info: Dictionary) -> void:
	session = sess
	ac = session.ac
	info = crash_info
	severity = float(info.get("severity", 0.5))
	ditching = bool(info.get("ditching", false))
	_rng.seed = U.hash_str(session.flight_id + "crash")
	_lc = CrashDebris.opts_for(ac.spec, ac.airline, 0.3, severity)
	Engine.time_scale = 0.4
	get_tree().create_timer(1.2, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	# external view of the scene
	var rig: CameraRig = session.rig
	if rig:
		rig.set_mode("orbit")
		rig.orbit_dist = maxf(float(ac.spec.span) * 1.5, 30.0)
		rig.orbit_pitch = 14.0
	if session.cockpit:
		session.cockpit.visible = false
	if ac.model:
		ac.model.show_exterior_fuselage(true)
	_build_overlay()
	if float(ac.ra) > 25.0 and not ditching:
		_begin_fall()
		return
	_ground_phase()


func _begin_fall() -> void:
	## Mid-air collision or in-flight breakup: the airframe comes apart in the air and the
	## pieces fall. The ground part of the accident starts when the main wreck hits.
	stage = "falling"
	_fall_alt = float(ac.ra)
	info.airborne = true
	var pieces := session.wreck_pieces()
	var hit := String(info.get("part", info.get("hit_part", "")))
	var plan := {"tail": _rng.randf() < 0.55 or hit in ["tail", "fin"], "wing": 0, "nose": _rng.randf() < 0.2}
	if hit.contains("left") or (hit == "" and _rng.randf() < 0.35):
		plan.wing = -1
	elif hit.contains("right") or (hit == "engine" and _rng.randf() < 0.5):
		plan.wing = 1
	if ac.model:
		var res := pieces.break_up(ac.model, ac.model.global_transform, ac.fdm.vel, ac.type_id, ac.airline, ac.reg, plan, _rng, true)
		var roll := float(res.get("roll_rate", 0.0))
		ac.set_meta("tumble", -ac.global_transform.basis.z * (roll * 1.4 + _rng.randf_range(-0.4, 0.4)) + ac.global_transform.basis.x * _rng.randf_range(-0.6, 0.2))
	ac.set_meta("falling", true)
	ac.set_meta("fall_drag", 0.0022)
	pieces.burst(ac.global_position, ac.fdm.vel, 26 + int(severity * 20), _lc, _rng)
	for i in mini(FlightModel.engine_positions(ac.spec).size(), 1 + _rng.randi() % 2):
		if _rng.randf() < 0.6:
			var ep: Vector3 = ac.global_transform * (FlightModel.engine_positions(ac.spec)[i] as Vector3)
			pieces.engine_piece(ep, ac.fdm.vel, float(_lc.eng_d), _lc.accent, _rng, true)
	_impact_burst()
	_start_fire(0.55)
	progress.emit("In-flight breakup")


func _ground_phase() -> void:
	## Impact on the ground or water: debris, fire, the responders and the injuries.
	if stage == "falling":
		Engine.time_scale = 0.5
		get_tree().create_timer(1.0, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
		var fi: Dictionary = ac.get_meta("fall_impact", {})
		var water := bool(fi.get("water", false))
		info.surface = "water" if water else String(info.get("surface", ""))
		info.place = Geo.place_name(ac.world_x(), ac.world_z())
		info.x = ac.world_x()
		info.z = ac.world_z()
		severity = maxf(severity, 0.98 if _fall_alt > 150.0 else 0.9)
		info.severity = severity
		if session.rig:
			session.rig.add_shake(3.0)
	stage = "impact"
	var pieces := session.wreck_pieces()
	if not ditching and severity >= 0.55 and not bool(info.get("airborne", false)) and ac.model:
		# the airframe breaks apart as it hits: the tail and, in the worst impacts, a wing come off
		var plan := {"tail": true, "wing": (-1 if _rng.randf() < 0.5 else 1) if severity >= 0.78 else 0, "nose": severity >= 0.9 and _rng.randf() < 0.5}
		var v := ac.fdm.vel
		pieces.break_up(ac.model, ac.model.global_transform, Vector3(v.x, maxf(v.y, 0.0) + 3.0, v.z) * 0.8, ac.type_id, ac.airline, ac.reg, plan, _rng, bool(info.get("fire", false)))
		for i in FlightModel.engine_positions(ac.spec).size():
			if _rng.randf() < severity - 0.35:
				var ep: Vector3 = ac.global_transform * (FlightModel.engine_positions(ac.spec)[i] as Vector3)
				pieces.engine_piece(ep, v * 0.9 + Vector3(0, 6, 0), float(_lc.eng_d), _lc.accent, _rng, bool(info.get("fire", false)))
	if not ditching and severity >= 0.3:
		var v2 := ac.fdm.vel
		pieces.burst(ac.global_position + Vector3(0, 1.5, 0), Vector3(v2.x, absf(v2.y) * 0.4 + 4.0, v2.z), int(10 + severity * 40), _lc, _rng)
	_spawn_debris()
	if bool(info.get("fire", false)) or bool(info.get("airborne", false)):
		if _fire_root == null:
			_start_fire(0.35 + severity * 0.5)
		else:
			fire_level = maxf(fire_level, 0.7)
	if not ditching and severity > 0.2:
		_impact_burst()
	_compute_injuries()
	var site := ac.global_position
	if session.ground_ops:
		session.ground_ops.emergency_response(site, bool(info.get("fire", false)) or _fire_root != null, 25.0 if _near_airport() else 240.0)
	stage = "settling"
	t = 0.0


func _near_airport() -> bool:
	var near := Airports.nearest(ac.world_x(), ac.world_z())
	return near != "" and U.dist2d(ac.world_x(), ac.world_z(), Airports.get_ap(near).x, Airports.get_ap(near).z) < 5000.0


# ================================================================== injuries
func _zone_factor(z: float) -> float:
	## How hard the impact hits a fuselage station: nose-first impacts load the front, tail
	## strikes the rear; the wing box is the strongest part of the airframe.
	var L := float(ac.spec.length)
	var nose_z := -L * float(ac.spec.cg_frac)
	var f := clampf((z - nose_z) / L, 0.0, 1.0)
	var pitch := float(info.get("pitch", 0.0))
	var k := 1.0
	if pitch < -6.0:
		k = 0.7 + 0.65 * (1.0 - f)
	elif pitch > 9.0:
		k = 0.7 + 0.65 * f
	if f > 0.33 and f < 0.55:
		k *= 0.85
	for bz in info.get("breaks", []):
		if absf(z - float(bz)) < 1.6:
			k += 0.35
	return k


func _injury_for(z: float, age: int, standing: bool, braced: bool) -> int:
	var s := severity * _zone_factor(z)
	if age >= 70:
		s += 0.08
	elif age < 12:
		s += 0.04
	if braced:
		s -= 0.12
	if standing:
		s += 0.25
	s += _rng.randf_range(-0.14, 0.14)
	if ditching:
		s = minf(s, 0.55)
	if s < 0.22:
		return INJ_NONE
	if s < 0.42:
		return INJ_MINOR
	if s < 0.6:
		return INJ_SERIOUS
	if s < 0.78:
		return INJ_CRITICAL
	return INJ_FATAL


func _compute_injuries() -> void:
	var breaks := []
	if severity > 0.55 and not ditching:
		var L := float(ac.spec.length)
		var nose_z := -L * float(ac.spec.cg_frac)
		breaks.append(nose_z + L * _rng.randf_range(0.18, 0.3))
		if severity > 0.75:
			breaks.append(nose_z + L * _rng.randf_range(0.6, 0.72))
	info.breaks = breaks
	var people: CabinPeople = session.people
	var braced := people != null and people.brace
	if people:
		for p in people.pax:
			var standing: bool = String(p.state) in ["walking", "to_lav", "from_lav", "stowing", "in_lav"]
			var inj := _injury_for(float(p.seat.pos.z), int(p.get("age", 35)), standing, braced)
			_apply_injury(p, inj)
		for fa in people.crew:
			var z := float(fa.pos.z) if fa.has("pos") else 0.0
			var inj2 := _injury_for(z, int(fa.get("age", 35)), String(fa.state) in ["service", "demo_walk", "to_station"], false)
			_apply_injury(fa, inj2)
	# the player sits in the flight deck (or in their cabin seat on a passenger flight)
	var pz := float(CabinLayout.get_layout(ac.type_id).cockpit.eye_z)
	if session.mode == "passenger" and people:
		var me := people.person_at_seat(session.pax_seat)
		if not me.is_empty():
			pz = float(me.seat.pos.z)
	player_injury = _injury_for(pz, int(Game.player.get("age", 35)) if Game.has_character() else 35, false, braced and session.mode == "passenger")
	if severity > 0.92 and not ditching:
		player_injury = INJ_FATAL


func _apply_injury(p: Dictionary, inj: int) -> void:
	p.injury_level = inj
	match inj:
		INJ_FATAL:
			p.state = "deceased"
			p.injury = "fatal"
			p.pose = HumanMesh.POSES["sit_sleep"]
		INJ_CRITICAL:
			p.injury = "trapped"
			if String(p.state) == "seated":
				p.pose = HumanMesh.POSES["brace"]
		INJ_SERIOUS:
			p.injury = "serious"
		INJ_MINOR:
			p.injury = "minor"
		_:
			p.injury = ""
	p.fear = 1.0
	p.soot = bool(info.get("fire", false)) and _rng.randf() < 0.6


# ================================================================== effects
func _start_fire(level: float) -> void:
	fire_level = level
	fire_growth = 0.012 + severity * 0.02
	_fire_root = Node3D.new()
	_fire_root.name = "Fire"
	ac.add_child(_fire_root)
	var spots: Array = []
	var engines := FlightModel.engine_positions(ac.spec)
	for e in engines:
		spots.append(e)
	spots.append(Vector3(float(ac.spec.span) * 0.18, -float(ac.spec.fuse_h) * 0.4, 1.5))
	spots.append(Vector3(-float(ac.spec.span) * 0.2, -float(ac.spec.fuse_h) * 0.4, 2.0))
	for sp in spots:
		_flames.append(_make_flames(sp))
	_smoke = _make_smoke()
	_smoke.position = Vector3(0, float(ac.spec.fuse_h) * 0.6, 2.0)
	_fire_root.add_child(_smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 6.0
	light.omni_range = 60.0
	light.position = Vector3(0, 2.0, 2.0)
	light.name = "FireLight"
	_fire_root.add_child(light)


func _make_flames(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90 if String(Game.settings.get("quality", "high")) in ["high", "ultra"] else 40
	p.lifetime = 1.1
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, 4.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.6
	pm.scale_min = 1.6
	pm.scale_max = 3.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.add_point(0.35, Color(1.0, 0.55, 0.12, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.08, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.8)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	_fire_root.add_child(p)
	return p


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 140 if String(Game.settings.get("quality", "high")) in ["high", "ultra"] else 60
	p.lifetime = 14.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, 1.2, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(ac.spec.span) * 0.2, 1.0, float(ac.spec.length) * 0.25)
	pm.scale_min = 4.0
	pm.scale_max = 7.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 3.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.09, 0.08, 0.85))
	grad.set_color(grad.get_point_count() - 1, Color(0.35, 0.34, 0.33, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	return p


func _impact_burst() -> void:
	## Dust or spray thrown up at the moment of impact.
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 120
	p.lifetime = 3.5
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 2.0
	pm.scale_max = 5.0
	var water := String(info.get("surface", "")) == "water"
	var col := Color(0.85, 0.9, 0.95, 0.7) if water else Color(0.45, 0.4, 0.32, 0.7)
	pm.color = col
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.5, 2.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = GroundOps._soft_dot()
	q.material = m
	p.draw_pass_1 = q
	ac.add_child(p)
	p.emitting = true


func _spawn_debris() -> void:
	## The debris field along the slide path: skin panels, seats and seat rows, luggage, engine
	## parts, wheels and wing fragments; with graphic crash scenes on, stylised remains too.
	if severity < 0.3 or ditching:
		return
	var back := ac.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 1e-4:
		back = Vector3.BACK
	back = back.normalized()
	var side := Vector3(back.z, 0, -back.x)
	var origin := ac.global_position
	var vw := session.view
	var reach := 60.0 + severity * 220.0
	if bool(info.get("airborne", false)):
		reach = 120.0
	var place := func(_i: int, rr: RandomNumberGenerator) -> Vector3:
		var along := rr.randf_range(4.0, reach)
		var lat := rr.randf_range(-1.0, 1.0) * (6.0 + along * 0.15)
		if bool(info.get("airborne", false)):
			along = rr.randf_range(-reach, reach)
			lat = rr.randf_range(-1.0, 1.0) * reach * 0.8
		var p := origin + back * along + side * lat
		p.y = Geo.ground_height(vw.wx(p), vw.wz(p)) + 0.05
		return p - origin
	var opts := _lc.duplicate()
	opts.scorch = 0.5 if bool(info.get("fire", false)) else 0.2
	opts.sev = severity
	opts.tail = false
	var people: CabinPeople = session.people
	var aboard := people.pax.size() + people.crew.size() if people else 0
	opts.victims = int(aboard * clampf((severity - 0.5) * 2.0, 0.0, 1.0))
	var mb := MeshBuilder.new()
	CrashDebris.scatter(mb, _rng, place, int(14 + severity * 60), opts)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = CrashDebris.material()
	vw.dynamic_root.add_child(mi)
	mi.position = origin


# ================================================================== evacuation and fire
func _start_evacuation() -> void:
	_evac_started = true
	if session.people == null or severity > 0.85:
		return
	session.command_evacuation()
	progress.emit("Evacuation in progress")


func _process(delta: float) -> void:
	if session == null or _done:
		return
	t += delta
	# fire grows unless crash tenders are spraying it
	if fire_level > 0.0:
		var spray := 0.0
		if session.ground_ops:
			spray = session.ground_ops.spray_power
		fire_level = clampf(fire_level + (fire_growth - spray * 0.02) * delta, 0.0, 1.0)
		var k := clampf(fire_level, 0.0, 1.0)
		for f in _flames:
			(f as GPUParticles3D).amount_ratio = k
			(f as GPUParticles3D).emitting = k > 0.04
		if _smoke:
			_smoke.amount_ratio = clampf(k + 0.2, 0.0, 1.0)
		var fl := _fire_root.get_node_or_null("FireLight") as OmniLight3D
		if fl:
			fl.light_energy = 6.0 * k * (0.8 + 0.4 * sin(t * 13.0) * sin(t * 7.3))
		if session.cabin:
			session.cabin.smoke = clampf(fire_level * 1.2 - 0.2, 0.0, 1.0)
	if stage == "falling":
		_update_overlay()
		if not ac.has_meta("falling") or t > 150.0:
			if ac.has_meta("falling"):
				ac.remove_meta("falling")
			_ground_phase()
		return
	if stage == "settling" and (t > 4.0 or ac.fdm.vel.length() < 1.0):
		stage = "evacuation"
		_start_evacuation()
	if stage == "evacuation":
		_fire_casualties(delta)
		_update_overlay()
		var people: CabinPeople = session.people
		var still_moving := people != null and people.count_state("evac") > 0
		if (t > 30.0 and not still_moving) or t > 240.0:
			stage = "rescue"
			t = 0.0
	elif stage == "rescue":
		_update_overlay()
		if t > 20.0:
			_finalize()


func _fire_casualties(delta: float) -> void:
	## People still inside a burning cabin are overcome by smoke after a few minutes; rescue
	## crews reach trapped people once the fire is knocked down.
	var people: CabinPeople = session.people
	if people == null:
		return
	var inside_hazard := clampf(fire_level - 0.35, 0.0, 1.0)
	for p in people.pax:
		if String(p.state) in ["exited", "deceased"]:
			continue
		if inside_hazard > 0.0:
			p.smoke = float(p.get("smoke", 0.0)) + inside_hazard * delta * 0.012
			if float(p.smoke) > 1.0:
				_apply_injury(p, INJ_FATAL)
		elif String(p.get("injury", "")) == "trapped" and t > 90.0 and fire_level < 0.2:
			p.state = "exited"
			p.rescued = true


# ================================================================== overlay
func _build_overlay() -> void:
	var layer := session.get_node_or_null("HUD")
	if layer == null:
		return
	_overlay = UIStyle.panel(Vector2(420, 0), Color(0.06, 0.02, 0.02, 0.85))
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay.position = Vector2(16, 60)
	_overlay.theme = UIStyle.theme()
	layer.add_child(_overlay)
	var v := UIStyle.vbox(8)
	_overlay.add_child(v)
	v.add_child(UIStyle.label("ACCIDENT", 22, UIStyle.RED, true))
	_overlay_label = UIStyle.rich("", 15)
	_overlay_label.custom_minimum_size = Vector2(390, 0)
	v.add_child(_overlay_label)
	v.add_child(UIStyle.button("Skip to the report", func(): _finalize()))


func _update_overlay() -> void:
	if _overlay_label == null:
		return
	var people: CabinPeople = session.people
	var aboard := people.pax.size() + people.crew.size() if people else 0
	var out := 0
	if people:
		out = people.count_state("exited")
	var gops := session.ground_ops
	var lines := []
	if stage == "falling":
		lines.append("[color=#ff9a50]In-flight breakup[/color] - %s" % String(info.get("cause_hint", "")))
		lines.append("Falling through %d ft" % int(maxf(float(ac.fdm.pos.y) - Geo.ground_height(ac.world_x(), ac.world_z()), 0.0) / 0.3048))
		_overlay_label.text = "\n".join(lines)
		return
	lines.append("%s at %s" % ["Ditching" if ditching else "Impact", String(info.get("place", "unknown location"))])
	if aboard > 0:
		lines.append("[b]%d[/b] of %d people out of the aircraft" % [out, aboard])
	if fire_level > 0.02:
		lines.append("[color=#ff9a50]Fire: %d%%[/color]" % int(fire_level * 100.0))
	if gops and gops.arff.size() > 0:
		var arrived := 0
		for v in gops.arff:
			if (v.path as Array).is_empty() and float(v.wait) <= 0.0:
				arrived += 1
		lines.append("Fire & rescue: %s" % ("on scene" if arrived > 0 else "responding"))
	match player_injury:
		INJ_FATAL:
			lines.append("[color=#ff6b60]You did not survive.[/color]")
		INJ_CRITICAL:
			lines.append("[color=#ffb347]You are critically injured.[/color]")
		INJ_SERIOUS:
			lines.append("You are seriously injured.")
		INJ_MINOR:
			lines.append("You have minor injuries.")
		_:
			lines.append("You are unhurt.")
	_overlay_label.text = "\n".join(lines)


# ================================================================== result
func _finalize() -> void:
	if _done:
		return
	_done = true
	var people: CabinPeople = session.people
	var c := {"aboard": 0, "fatal": 0, "critical": 0, "serious": 0, "minor": 0, "uninjured": 0}
	var victims := []
	var survivors := []
	if people:
		for p in people.pax + people.crew:
			c.aboard += 1
			var lvl := int(p.get("injury_level", 0))
			if String(p.state) == "deceased":
				lvl = INJ_FATAL
			match lvl:
				INJ_FATAL:
					c.fatal += 1
					victims.append(p)
				INJ_CRITICAL:
					c.critical += 1
					survivors.append(p)
				INJ_SERIOUS:
					c.serious += 1
					survivors.append(p)
				INJ_MINOR:
					c.minor += 1
					survivors.append(p)
				_:
					c.uninjured += 1
					survivors.append(p)
			_persist_person(p, lvl)
	# the pilot counts too
	c.aboard += 1
	match player_injury:
		INJ_FATAL:
			c.fatal += 1
		INJ_CRITICAL:
			c.critical += 1
		INJ_SERIOUS:
			c.serious += 1
		INJ_MINOR:
			c.minor += 1
		_:
			c.uninjured += 1
	counts = c
	var rec := WorldSim.aircraft(ac.reg)
	if not rec.is_empty():
		rec.status = "written_off" if severity > 0.4 or ditching else "damaged"
		rec.incidents.append({"t": WorldSim.clock, "kind": "accident", "flight": session.flight_id})
	session.aftermath = {
		"counts": c, "player_injury": player_injury, "severity": severity, "ditching": ditching,
		"fire": fire_level > 0.0 or bool(info.get("fire", false)), "place": String(info.get("place", "")),
		"victims": victims.map(func(v): return {"id": v.get("id", -1), "name": v.get("name", ""), "age": v.get("age", 0), "home": v.get("home", ""), "job": v.get("job", "")}),
		"survivors": survivors.size(),
	}
	if _overlay:
		_overlay.queue_free()
	session.finish_flight("ditched" if ditching else "crashed")


func _persist_person(p: Dictionary, lvl: int) -> void:
	var pid := int(p.get("id", -1))
	if pid < 0 or pid >= 900000:
		return
	var status := "alive"
	match lvl:
		INJ_FATAL:
			status = "deceased"
		INJ_CRITICAL:
			status = "injured_critical"
		INJ_SERIOUS:
			status = "injured_serious"
		INJ_MINOR:
			status = "injured_minor"
	WorldSim.modify_person(pid, {"status": status, "accident_flight": session.flight_id, "accident_time": WorldSim.clock})
