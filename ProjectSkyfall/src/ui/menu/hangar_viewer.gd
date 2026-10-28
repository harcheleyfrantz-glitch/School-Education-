class_name HangarViewer
extends SubViewportContainer
## Live 3D hangar for the aircraft viewer: a polished floor, a hall lined with light strips,
## warm key, cool rim and soft fill lights, and an orbit camera. Drag (mouse or one finger) to
## turn around the aircraft, wheel or pinch to zoom; it drifts slowly on its own when idle.

const HALL := 90.0

var vp: SubViewport
var root: Node3D
var cam: Camera3D
var model: AircraftModel
var type_id := ""
var airline := ""
var yaw := -38.0
var pitch := 9.0
var zoom := 1.0
var _size := 40.0
var _target := Vector3.ZERO
var _drag := false
var _idle := 0.0
var _touches := {}
var _pinch0 := 0.0
var _zoom0 := 1.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X if Game.is_mobile else Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	root = Node3D.new()
	vp.add_child(root)
	_build_set()
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.2
	cam.far = 1000.0
	root.add_child(cam)
	cam.current = true


func _build_set() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.03, 0.04, 0.055)
	psm.sky_horizon_color = Color(0.12, 0.14, 0.17)
	psm.ground_horizon_color = Color(0.1, 0.11, 0.13)
	psm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	psm.sun_angle_max = 1.0
	psm.sky_energy_multiplier = 0.8
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.1
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = Game.renderer == "forward_plus" and not Game.is_mobile
	e.ssr_enabled = Game.renderer == "forward_plus" and not Game.is_mobile
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.05
	e.adjustment_color_correction = PhotoStudio.grade()
	var we := WorldEnvironment.new()
	we.environment = e
	root.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALL * 2.6, HALL * 2.6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.075, 0.085)
	fm.roughness = 0.36
	fm.metallic_specular = 0.3
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var hall := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var marks := MeshBuilder.new()
	var R := HALL * 1.25
	var H := HALL * 0.55
	# walls of a square hall with pilasters and vertical light strips, a ceiling grid of panels
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		hall.add_box_xf(Transform3D(b, b * Vector3(0, H * 0.5, -R)), Vector3(R * 2.0, H, 1.0), Color(0.12, 0.13, 0.15))
		for i in 13:
			var x := (float(i) - 6.0) * R * 0.15
			glow.add_box_xf(Transform3D(b, b * Vector3(x, H * 0.42, -R + 0.7)), Vector3(0.5, H * 0.7, 0.1), Color(1, 1, 1))
			hall.add_box_xf(Transform3D(b, b * Vector3(x + R * 0.075, H * 0.5, -R + 0.8)), Vector3(1.0, H, 1.0), Color(0.18, 0.19, 0.21))
	hall.add_box(Vector3(0, H, 0), Vector3(R * 2.0, 0.6, R * 2.0), Color(0.07, 0.075, 0.085))
	for gx in 6:
		for gz in 6:
			glow.add_box(Vector3((float(gx) - 2.5) * R * 0.3, H - 0.4, (float(gz) - 2.5) * R * 0.3), Vector3(R * 0.16, 0.08, 1.2), Color(1, 1, 1))
	marks.add_box(Vector3(0, 0.006, 0), Vector3(0.3, 0.012, R * 1.6), Color(0.95, 0.74, 0.16))
	for k in [-1.0, 1.0]:
		marks.add_box(Vector3(k * HALL * 0.42, 0.006, 0), Vector3(0.22, 0.012, R * 1.2), Color(0.8, 0.82, 0.86))
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true
	wm.roughness = 0.7
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mb in [hall, marks]:
		var mi := MeshInstance3D.new()
		mi.mesh = (mb as MeshBuilder).commit()
		mi.material_override = wm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.92, 0.95, 1.0)
	var gl := MeshInstance3D.new()
	gl.mesh = glow.commit()
	gl.material_override = gm
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gl)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(-PhotoStudio._dir(-80.0, 45.0), Vector3.UP)
	key.light_energy = 1.5
	key.light_specular = 0.4
	key.light_color = Color(1.0, 0.91, 0.8)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 160.0
	root.add_child(key)
	var key2 := DirectionalLight3D.new()
	key2.basis = Basis.looking_at(-PhotoStudio._dir(110.0, 40.0), Vector3.UP)
	key2.light_energy = 0.9
	key2.light_specular = 0.2
	key2.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(key2)
	var top := DirectionalLight3D.new()
	top.basis = Basis.looking_at(Vector3(0.1, -1.0, 0.05).normalized(), Vector3.FORWARD)
	top.light_energy = 0.45
	top.light_specular = 0.6
	root.add_child(top)


func show_aircraft(t: String, al: String) -> void:
	if t == type_id and al == airline and model != null:
		return
	var new_type := t != type_id
	type_id = t
	airline = al
	if model:
		model.queue_free()
	var spec := AircraftTypes.get_type(t)
	model = AircraftModel.new()
	root.add_child(model)
	model.build(t, al, String(Airlines.get_al(al).get("reg_prefix", "CR-")) + "HGR", 1.0)
	model.position = Vector3(0, float(spec.gear_height) - 0.05, 0)
	for i in 3:
		model.animate_simple(1.0, 0.0, 0.0, {"nav": true, "beacon": false, "cabin": true}, 0.15, 0.05)
	_size = maxf(float(spec.length), float(spec.span))
	_target = Vector3(0, float(spec.height) * 0.38, -float(spec.length) * 0.04)
	if new_type:
		var z0 := 1.55
		zoom = z0
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "zoom", 1.0, 0.9)
		tw.tween_property(self, "yaw", yaw + 35.0, 0.9)


func _process(delta: float) -> void:
	if cam == null:
		return
	_idle += delta
	if not _drag and _idle > 2.5:
		yaw += delta * 6.0
	pitch = clampf(pitch, 2.0, 50.0)
	zoom = clampf(zoom, 0.55, 1.8)
	var d := _size * 1.2 * zoom
	var p := _target + PhotoStudio._dir(yaw, pitch) * d
	p.y = maxf(p.y, 0.8)
	cam.position = p
	cam.look_at(_target, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_idle = 0.0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 0.92
			_idle = 0.0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= 1.08
			_idle = 0.0
	elif event is InputEventMouseMotion and _drag:
		yaw += event.relative.x * 0.35
		pitch += event.relative.y * 0.2
		_idle = 0.0
	elif event is InputEventMagnifyGesture:
		zoom /= maxf(event.factor, 0.01)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_drag = _touches.size() == 1
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch0 = (pts[0] as Vector2).distance_to(pts[1])
			_zoom0 = zoom
		_idle = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch0 > 1.0:
			var pts2: Array = _touches.values()
			zoom = _zoom0 * _pinch0 / maxf((pts2[0] as Vector2).distance_to(pts2[1]), 1.0)
		elif _touches.size() == 1:
			yaw += event.relative.x * 0.35
			pitch += event.relative.y * 0.2
		_idle = 0.0
