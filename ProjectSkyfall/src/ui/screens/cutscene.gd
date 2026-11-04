extends Control
## In-engine story cutscenes (Story.CHAPTERS): letterboxed shots of the real game world - the
## airport at the right time of day and weather, an aircraft parked, taking off, on approach or in
## cruise, and a moving camera - with a chapter title card and subtitled dialogue.
## Space, Enter or a click advances the line; Esc or Skip ends the scene. An intro scene leads into
## the chapter's flight; an outro scene returns to the story screen.

var chapter := 0
var part := "intro"
var shots: Array = []
var stage: Node3D
var view: WorldView
var ac: Aircraft
var cam: Camera3D
var _shot_i := -1
var _line_i := -1
var _line_t := 0.0
var _line_dur := 3.0
var _busy := true
var _done := false
var _loc := ""
var _t := 0.0
var _shot_t := 0.0
var _acs := {}          # aircraft state: world position, heading, speed, motion
var _cams := {}         # camera state for the shot
var _fade: ColorRect
var _name_l: Label
var _text_l: Label
var _title_box: VBoxContainer
var _title_a: Label
var _title_b: Label
var _type_tw: Tween


func setup(params: Dictionary) -> void:
	chapter = clampi(int(params.get("chapter", 0)), 0, Story.CHAPTERS.size() - 1)
	part = String(params.get("part", "intro"))
	shots = (Story.CHAPTERS[chapter] as Dictionary).get(part, [])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIStyle.theme()
	_build_ui()
	stage = Node3D.new()
	stage.name = "CutsceneStage"
	Game.main.add_child(stage)
	_next_shot()


func _exit_tree() -> void:
	if stage and is_instance_valid(stage):
		stage.queue_free()


# ================================================================== interface
func _build_ui() -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.88
		bar.anchor_bottom = 0.12 if top else 1.0
		add_child(bar)
	# subtitles over the lower bar
	var sub := VBoxContainer.new()
	sub.anchor_left = 0.12
	sub.anchor_right = 0.88
	sub.anchor_top = 0.74
	sub.anchor_bottom = 0.86
	sub.alignment = BoxContainer.ALIGNMENT_END
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	_name_l = UIStyle.caps("", 14, UIStyle.ACCENT, 800, 3)
	_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_child(_name_l)
	_text_l = UIStyle.label("", 23, Color.WHITE)
	_text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_text_l.add_theme_constant_override("outline_size", 6)
	sub.add_child(_text_l)
	# chapter title card
	_title_box = VBoxContainer.new()
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title_box.offset_left = -420
	_title_box.offset_right = 420
	_title_box.offset_top = -70
	_title_box.offset_bottom = 70
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.modulate.a = 0.0
	add_child(_title_box)
	_title_a = UIStyle.caps("", 16, UIStyle.ACCENT, 800, 6)
	_title_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(_title_a)
	_title_b = UIStyle.title("", 54, Color.WHITE)
	_title_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title_b.add_theme_constant_override("shadow_offset_y", 3)
	_title_box.add_child(_title_b)
	# controls
	var skip := UIStyle.button("Skip scene", func(): _finish(), 150)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -176
	skip.offset_right = -24
	skip.offset_top = 22
	skip.offset_bottom = 58
	add_child(skip)
	var hint := UIStyle.caps("Space · next line      Esc · skip", 10, Color(1, 1, 1, 0.45), 700, 2)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 0.95
	hint.anchor_bottom = 0.99
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _fade_to(a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, dur)
	await tw.finished


func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
	elif e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if _busy:
		return
	if _type_tw and _type_tw.is_running():
		_type_tw.kill()
		_text_l.visible_ratio = 1.0
		return
	_next_line()


# ================================================================== shots and lines
func _next_shot() -> void:
	_shot_i += 1
	if _shot_i >= shots.size():
		_finish()
		return
	_busy = true
	_name_l.text = ""
	_text_l.text = ""
	await _fade_to(1.0, 0.35)
	if _done:
		return
	var sh: Dictionary = shots[_shot_i]
	await _load_shot(sh)
	if _done:
		return
	_line_i = -1
	_shot_t = 0.0
	var delay := 0.0
	if bool(sh.get("title", false)):
		var ch: Dictionary = Story.CHAPTERS[chapter]
		_title_a.text = "%s  ·  CHAPTER %s" % [Story.TITLE.to_upper(), String(ch.num).to_upper()]
		_title_b.text = String(ch.title)
		var tw := create_tween()
		tw.tween_property(_title_box, "modulate:a", 1.0, 0.9)
		tw.tween_interval(2.2)
		tw.tween_property(_title_box, "modulate:a", 0.0, 0.9)
		delay = 3.4
	await _fade_to(0.0, 0.7)
	if _done:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay - 0.7).timeout
	_busy = false
	_next_line()


func _next_line() -> void:
	if _done:
		return
	_line_i += 1
	var lines: Array = (shots[_shot_i] as Dictionary).get("lines", [])
	if _line_i >= lines.size():
		_next_shot()
		return
	var ln: Array = lines[_line_i]
	var who := Story.fill(String(ln[0]))
	var text := Story.fill(String(ln[1]))
	_name_l.text = who
	_text_l.text = text if who != "" else "— " + text + " —"
	_text_l.visible_ratio = 0.0
	_type_tw = create_tween()
	_type_tw.tween_property(_text_l, "visible_ratio", 1.0, clampf(text.length() / 48.0, 0.4, 3.5))
	_line_dur = 2.4 + text.length() * 0.05
	_line_t = 0.0


func _finish() -> void:
	if _done:
		return
	_done = true
	_busy = true
	await _fade_to(1.0, 0.4)
	if part == "intro":
		var scn := Activities.get_scenario(String((Story.CHAPTERS[chapter] as Dictionary).id))
		Activities.launch(scn)
	else:
		WeatherModel.override_preset = ""
		Game.goto("story", {"finished": chapter})


func _process(delta: float) -> void:
	if view == null or _done:
		return
	_t += delta
	_shot_t += delta
	_move_aircraft(delta)
	_move_camera(delta)
	if not _busy:
		_line_t += delta
		if _line_t >= _line_dur:
			_next_line()


# ================================================================== staging
func _load_shot(sh: Dictionary) -> void:
	var icao := String(sh.get("at", "SKPC"))
	var ap: Dictionary = Airports.get_ap(icao)
	var key := "%s|%.2f|%s" % [icao, float(sh.get("hour", 12.0)), String(sh.get("weather", "few"))]
	if ac and is_instance_valid(ac):
		ac.queue_free()
	ac = null
	if key != _loc:
		if view and is_instance_valid(view):
			view.queue_free()
		view = null
		cam = null
		await get_tree().process_frame
		WeatherModel.override_preset = String(sh.get("weather", "few"))
		view = WorldView.new()
		view.name = "World"
		stage.add_child(view)
		view.setup(float(ap.x), float(ap.z), Activities.next_clock(float(sh.get("hour", 12.0))), true)
		view.airports.ensure_loaded(icao)
		cam = Camera3D.new()
		cam.fov = 46.0
		cam.near = 0.3
		cam.far = 60000.0
		view.dynamic_root.add_child(cam)
		cam.current = true
		view.camera = cam
		_loc = key
		cam.global_position = view.world_to_local(float(ap.x) + 3000.0, float(ap.elev) + 900.0, float(ap.z) + 3000.0)
		cam.look_at(view.world_to_local(float(ap.x), float(ap.elev), float(ap.z)), Vector3.UP)
		# let the terrain and the airport stream in under the black
		for i in 45:
			await get_tree().process_frame
	_acs = {}
	var acd: Dictionary = sh.get("ac", {})
	if not acd.is_empty():
		ac = Aircraft.new()
		ac.name = "StoryAircraft"
		view.dynamic_root.add_child(ac)
		ac.setup(String(acd.type), String(acd.get("reg", "CR-STY")), String(acd.airline), view, true)
		ac.player_controlled = false
		ac.set_physics_process(false)
		_stage_aircraft(acd, icao, ap)
	_cams = (sh.get("cam", {}) as Dictionary).duplicate()
	_cams.ang = randf() * TAU
	_cams.fixed = Vector3.INF
	for i in 6:
		await get_tree().process_frame


func _stage_aircraft(acd: Dictionary, icao: String, ap: Dictionary) -> void:
	var pose := String(acd.get("pose", "stand"))
	var L := AirportLayout.get_layout(icao)
	var spec := AircraftTypes.get_type(String(acd.type))
	var elev := float(ap.elev)
	var o := Vector2(float(ap.x), float(ap.z))
	var lights: Dictionary = ac.sys.lights
	lights.nav = true
	lights.logo = true
	lights.beacon = pose != "stand"
	var st := {"pose": pose, "speed": 0.0, "climb": 0.0, "pitch": 0.0, "ground": true, "delay": float(acd.get("delay", 0.0))}
	match pose:
		"stand":
			var stands: Array = L.stands
			var sd: Dictionary = stands[clampi(int(acd.get("stand", 0)), 0, stands.size() - 1)]
			var n: Vector2 = sd.normal
			var face: Vector2 = sd.get("facade_origin", sd.stop)
			var p2 := face + n * (7.0 + float(spec.length) * float(spec.cg_frac))
			st.pos = Vector3(o.x + p2.x, elev, o.y + p2.y)
			st.hdg = float(sd.hdg)
			st.apron = n
		"runway", "takeoff":
			var e: Dictionary = (L.runways[0] as Dictionary).ends[0]
			var thr: Vector2 = e.thr
			var d: Vector2 = e.dir
			var p3 := thr + d * 140.0
			st.pos = Vector3(o.x + p3.x, elev, o.y + p3.y)
			st.hdg = float(e.hdg)
			lights.landing = true
			lights.strobe = true
		"approach":
			var e2: Dictionary = (L.runways[0] as Dictionary).ends[0]
			var thr2: Vector2 = e2.thr
			var d2: Vector2 = e2.dir
			var dist := float(acd.get("dist", 6000.0))
			var p4 := thr2 - d2 * dist
			st.pos = Vector3(o.x + p4.x, elev + 15.0 + dist * tan(deg_to_rad(3.0)), o.y + p4.y)
			st.hdg = float(e2.hdg)
			st.speed = 72.0 if String(spec.category) in ["widebody", "cargo"] else 66.0
			if String(spec.category) == "trainer":
				st.speed = 34.0
			st.climb = -st.speed * tan(deg_to_rad(3.0))
			st.ground = false
			lights.landing = true
			lights.strobe = true
		_:
			# cruise: off to one side of the airport, level, gear up
			var off: Vector2 = acd.get("off", Vector2(-2500.0, 2500.0))
			st.pos = Vector3(o.x + off.x, elev + float(acd.get("alt", 3000.0)), o.y + off.y)
			st.hdg = float(acd.get("hdg", 20.0))
			st.speed = float(acd.get("speed", 120.0))
			st.ground = false
			lights.strobe = true
	if not st.ground and pose != "approach":
		ac.sys.gear_down_cmd = false
		ac.sys.gear_pos = [0.0, 0.0, 0.0]
	st.start = st.pos
	_acs = st
	_place()


func _fwd(hdg: float) -> Vector3:
	var h := deg_to_rad(hdg)
	return Vector3(sin(h), 0.0, -cos(h))


func _place() -> void:
	if ac == null or _acs.is_empty():
		return
	var p: Vector3 = _acs.pos
	ac.place_at(view.world_to_local(p.x, p.y, p.z), float(_acs.hdg), bool(_acs.ground), float(_acs.speed))
	if absf(float(_acs.pitch)) > 0.01:
		ac.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(_acs.pitch)))


func _move_aircraft(delta: float) -> void:
	if ac == null or _acs.is_empty():
		return
	var pose := String(_acs.pose)
	if pose == "takeoff":
		if _shot_t > float(_acs.delay):
			var spec := ac.spec
			var vr := 70.0 if String(spec.category) in ["widebody", "cargo"] else (32.0 if String(spec.category) == "trainer" else 62.0)
			_acs.speed = minf(float(_acs.speed) + delta * (2.4 if vr > 40.0 else 3.2), vr + 12.0)
			if float(_acs.speed) > vr:
				_acs.ground = false
				_acs.pitch = minf(float(_acs.pitch) + delta * 3.0, 9.0)
				_acs.climb = minf(float(_acs.climb) + delta * 2.5, float(_acs.speed) * 0.14)
				if float(_acs.pos.y) > float(_acs.start.y) + 30.0:
					ac.sys.gear_down_cmd = false
	elif pose == "approach":
		_acs.pitch = 2.5
	if float(_acs.speed) > 0.0:
		var f := _fwd(float(_acs.hdg))
		_acs.pos = (_acs.pos as Vector3) + f * float(_acs.speed) * delta + Vector3(0, float(_acs.climb) * delta, 0)
	_place()
	ac.model.animate(ac, delta)


func _target() -> Vector3:
	if ac and is_instance_valid(ac):
		return ac.global_position + Vector3(0, 2.0, 0)
	var ap: Dictionary = Airports.get_ap(String((shots[_shot_i] as Dictionary).get("at", "SKPC")))
	return view.world_to_local(float(ap.x), float(ap.elev) + 30.0, float(ap.z))


func _move_camera(delta: float) -> void:
	if cam == null or _shot_i < 0 or _shot_i >= shots.size() or _cams.is_empty():
		return
	var tg := _target()
	var mode := String(_cams.get("mode", "orbit"))
	var p := cam.global_position
	match mode:
		"aerial":
			_cams.ang = float(_cams.ang) + delta * 0.035
			var r := float(_cams.get("dist", 3800.0))
			p = tg + Vector3(sin(float(_cams.ang)) * r, float(_cams.get("height", 1100.0)), cos(float(_cams.ang)) * r)
		"orbit":
			_cams.ang = float(_cams.ang) + delta * float(_cams.get("speed", 0.07))
			if _acs.has("apron"):
				# at a gate: sweep to and fro on the apron side, never behind the terminal
				var an: Vector2 = _acs.apron
				_cams.ang = atan2(an.x, an.y) + sin(_shot_t * 0.12 + 0.4) * 0.95
			var r2 := float(_cams.get("dist", 40.0))
			p = tg + Vector3(sin(float(_cams.ang)) * r2, float(_cams.get("height", 6.0)), cos(float(_cams.ang)) * r2)
		"low", "flyby":
			if (_cams.fixed as Vector3) == Vector3.INF:
				var f := _fwd(float(_acs.get("hdg", 0.0)))
				var side := Vector3(-f.z, 0.0, f.x)
				var base: Vector3 = tg
				var q := base + f * float(_cams.get("ahead", 400.0)) + side * float(_cams.get("side", 60.0))
				if mode == "low":
					var wq := Vector2(view.wx(q), view.wz(q))
					q.y = view.world_to_local(wq.x, Geo.ground_height(wq.x, wq.y) + 1.8, wq.y).y
				else:
					q.y += float(_cams.get("up", 25.0))
				_cams.fixed = q
			p = _cams.fixed
		"chase":
			var f2 := ac.global_transform.basis.z if ac else Vector3(0, 0, 1)
			p = tg + f2.normalized() * float(_cams.get("dist", 60.0)) + Vector3(0, float(_cams.get("height", 8.0)), 0)
		"side":
			var f3 := _fwd(float(_acs.get("hdg", 0.0)))
			var side2 := Vector3(-f3.z, 0.0, f3.x)
			p = tg + side2 * float(_cams.get("dist", 40.0)) + Vector3(0, float(_cams.get("height", 4.0)), 0) - f3 * float(_cams.get("dist", 40.0)) * 0.25
	# never below the ground
	var gw := Vector2(view.wx(p), view.wz(p))
	var gy := view.world_to_local(gw.x, Geo.ground_height(gw.x, gw.y) + 1.5, gw.y).y
	p.y = maxf(p.y, gy)
	cam.global_position = p
	if p.distance_to(tg) > 0.5:
		cam.look_at(tg, Vector3.UP)
