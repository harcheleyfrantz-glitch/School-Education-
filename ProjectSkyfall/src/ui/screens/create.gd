extends ScreenBase
## Character creation: identity, appearance (with a live 3D preview in uniform) and the career
## path to start on.

var data := {"first": "", "last": "", "gender": "f", "age": 29, "home": "Port Calder", "skin": 2, "hair_color": 1,
	"hair": 4, "build": 0.8, "path": "regional_fo"}
var preview_crowd: Crowd
var preview_vp: SubViewport
var _paths_box: VBoxContainer
var _yaw := 0.0
var _drag := false


func setup(_params: Dictionary) -> void:
	var r := U.rng(Time.get_ticks_usec())
	var p := Names.person(r, 24, 40)
	data.first = p.first
	data.last = p.last
	data.gender = p.gender
	data.build = 0.82 if p.gender == "f" else (0.12 if p.gender == "m" else 0.45)
	data.hair = HumanMesh.hair_style_for(String(p.gender), 30, r.randf())
	data.skin = r.randi_range(0, 6)
	data.hair_color = r.randi_range(0, 5)
	data.home = String(p.home)
	frame("Create your pilot", "Who are you, and where does your story begin?", "menu", 0.58)
	_build_identity()
	_build_appearance()
	_build_paths()
	var go := UIStyle.button("Begin career", _create, 260, UIStyle.ACCENT)
	content.add_child(go)
	_build_preview()


func _build_identity() -> void:
	var c := card("Identity")
	var names := UIStyle.hbox(8)
	var fe := LineEdit.new()
	fe.text = data.first
	fe.placeholder_text = "First name"
	fe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fe.text_changed.connect(func(t): data.first = t)
	var le := LineEdit.new()
	le.text = data.last
	le.placeholder_text = "Last name"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t): data.last = t)
	names.add_child(fe)
	names.add_child(le)
	c.add_child(names)
	var row := UIStyle.hbox(8)
	var genders := ["f", "m", "x"]
	row.add_child(option(["Woman", "Man", "Non-binary"], genders.find(String(data.gender)), func(i):
		data.gender = genders[i]
		data.build = [0.82, 0.12, 0.45][i]
		_refresh_preview()))
	var age := SpinBox.new()
	age.min_value = 21
	age.max_value = 62
	age.value = int(data.age)
	age.prefix = "Age"
	age.value_changed.connect(func(v): data.age = int(v))
	row.add_child(age)
	var towns: Array = Names.HOMETOWNS
	row.add_child(option(towns, towns.find(String(data.home)), func(i): data.home = towns[i]))
	c.add_child(row)


func _build_appearance() -> void:
	var c := card("Appearance")
	c.add_child(UIStyle.label("Skin", 14, UIStyle.DIM))
	c.add_child(_swatches([Color(0.86, 0.68, 0.57), Color(0.80, 0.60, 0.47), Color(0.71, 0.51, 0.37), Color(0.60, 0.42, 0.29),
		Color(0.47, 0.32, 0.21), Color(0.36, 0.24, 0.16), Color(0.26, 0.17, 0.12)], "skin"))
	c.add_child(UIStyle.label("Hair colour", 14, UIStyle.DIM))
	c.add_child(_swatches([Color(0.035, 0.03, 0.028), Color(0.11, 0.07, 0.045), Color(0.24, 0.15, 0.08), Color(0.42, 0.28, 0.15),
		Color(0.70, 0.56, 0.34), Color(0.48, 0.18, 0.07), Color(0.6, 0.6, 0.6)], "hair_color"))
	var styles := ["Crop", "Side part", "Long", "Bun", "Ponytail", "Curly", "Bob", "Receding"]
	var row := UIStyle.hbox(8)
	row.add_child(UIStyle.label("Hair style", 14, UIStyle.DIM))
	row.add_child(option(styles, int(data.hair), func(i):
		data.hair = i
		_refresh_preview()))
	row.add_child(UIStyle.label("Build", 14, UIStyle.DIM))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 0.99
	sl.step = 0.01
	sl.value = float(data.build)
	sl.custom_minimum_size = Vector2(160, 28)
	sl.value_changed.connect(func(v):
		data.build = v
		_refresh_preview())
	row.add_child(sl)
	c.add_child(row)


func _swatches(cols: Array, key: String) -> HBoxContainer:
	var h := UIStyle.hbox(6)
	for i in cols.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.focus_mode = Control.FOCUS_NONE
		var col: Color = cols[i]
		b.add_theme_stylebox_override("normal", UIStyle.box(col, 18, Color(1, 1, 1, 0.25), 2, 0))
		b.add_theme_stylebox_override("hover", UIStyle.box(col, 18, Color(1, 1, 1, 0.8), 2, 0))
		b.add_theme_stylebox_override("pressed", UIStyle.box(col, 18, UIStyle.ACCENT, 3, 0))
		var idx := i
		b.pressed.connect(func():
			data[key] = idx
			_refresh_preview())
		h.add_child(b)
	return h


func _build_paths() -> void:
	var c := card("Where your career begins")
	_paths_box = c
	_refresh_paths()


func _refresh_paths() -> void:
	for ch in _paths_box.get_children():
		if ch is PanelContainer:
			ch.queue_free()
	for key in CareerRules.START_PATHS.keys():
		var sp: Dictionary = CareerRules.START_PATHS[key]
		var sel = key == String(data.path)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UIStyle.box(Color(0.1, 0.17, 0.24, 0.95) if sel else Color(0.07, 0.1, 0.14, 0.9), 10,
			UIStyle.ACCENT if sel else Color(1, 1, 1, 0.06), 2 if sel else 1, 12))
		var v := UIStyle.vbox(4)
		p.add_child(v)
		var al := Airlines.get_al(String(sp.airline))
		v.add_child(UIStyle.label("%s — %s" % [sp.label, al.get("name", "")], 16, UIStyle.TEXT, true))
		var d := UIStyle.label(String(sp.desc), 14, UIStyle.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		v.add_child(UIStyle.label("%d hours · %s · %s" % [int(sp.hours), sp.license, U.fmt_money(float(sp.money))], 13, UIStyle.ACCENT))
		var k: String = key
		p.gui_input.connect(func(e):
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
				data.path = k
				_refresh_paths())
		_paths_box.add_child(p)


func _build_preview() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.anchor_left = 0.6
	holder.anchor_right = 0.98
	holder.anchor_top = 0.08
	holder.anchor_bottom = 0.95
	add_child(holder)
	preview_vp = SubViewport.new()
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	preview_vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(preview_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	preview_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	preview_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	preview_vp.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.75
	disc.height = 0.04
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.16, 0.22)
	fm.metallic = 0.4
	fm.roughness = 0.3
	floor_mi.material_override = fm
	floor_mi.position.y = -0.02
	preview_vp.add_child(floor_mi)
	preview_crowd = Crowd.new()
	preview_vp.add_child(preview_crowd)
	preview_crowd.setup(1, 0, "SKF", true)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.15, 3.9)
	preview_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	holder.gui_input.connect(func(ev):
		if ev is InputEventMouseButton:
			_drag = ev.pressed
		elif (ev is InputEventMouseMotion and _drag) or ev is InputEventScreenDrag:
			_yaw += ev.relative.x * 0.01)
	_refresh_preview()


func _refresh_preview() -> void:
	if preview_crowd == null:
		return
	var path: Dictionary = CareerRules.START_PATHS[String(data.path)]
	var uc := Crowd.uniform_colors(String(path.airline))
	preview_crowd.set_instance_shader_parameter("uniform_color", uc[0])
	preview_crowd.set_instance_shader_parameter("uniform_trim", uc[1])
	preview_crowd.set_instance_shader_parameter("skin_override", (float(data.skin) + 0.5) / 7.0)
	preview_crowd.set_instance_shader_parameter("hair_override", (float(data.hair_color) + 0.5) / 7.0)


func _process(delta: float) -> void:
	if preview_crowd == null:
		return
	if not _drag:
		_yaw += delta * 0.25
	var flags := Crowd.FLAG_HAT | Crowd.FLAG_TIE
	var xf := Transform3D(Basis(Vector3.UP, _yaw + PI), Vector3.ZERO)
	preview_crowd.set_person(0, xf, HumanMesh.POSES["stand"], 0.0, 1.0, Color(0.95, 0.95, 0.97), Crowd.Outfit.FLIGHT,
		float(data.hair) + 0.37, flags, float(data.build))
	preview_crowd.flush()


func _create() -> void:
	if String(data.first).strip_edges() == "":
		data.first = "Alex"
	if String(data.last).strip_edges() == "":
		data.last = "Morgan"
	data.name = "%s %s" % [String(data.first).strip_edges(), String(data.last).strip_edges()]
	Game.new_character(data)
	Game.player.appearance = {"skin": data.skin, "hair_color": data.hair_color, "hair": data.hair, "build": data.build}
	Game.save_game()
	Game.goto("hub", {"welcome": true})
