class_name AirportManager
extends Node3D
## Streams airports around the camera. Geometry is built on worker threads and swapped in when
## ready; shared materials live here so every airport reacts to night, rain and fog together.

var view: Node = null
var load_radius := 60000.0
var unload_radius := 78000.0
var views := {}           # icao -> AirportView
var _building := {}       # icao -> true
var _ready_products := []
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _materials := {}
var _pave: Array[ShaderMaterial] = []
var light_material: ShaderMaterial
var instanced_material: ShaderMaterial
var car_mesh: ArrayMesh
var night := 0.0
var wetness := 0.0
var _wind_timer := 0.0
var detail := 1.0


func setup(world_view: Node) -> void:
	view = world_view
	detail = float(Game.q("buildings"))
	load_radius = 60000.0 if not Game.is_mobile else 38000.0
	unload_radius = load_radius + 18000.0
	light_material = ShaderMaterial.new()
	light_material.shader = load("res://shaders/airport_light.gdshader")
	instanced_material = ShaderMaterial.new()
	instanced_material.shader = load("res://shaders/instanced_color.gdshader")
	var cb := MeshBuilder.new()
	cb.add_box(Vector3(0, 0.62, 0), Vector3(1.8, 0.75, 4.4), Color(1, 1, 1, 1))
	cb.add_box(Vector3(0, 1.22, -0.2), Vector3(1.6, 0.55, 2.3), Color(0.12, 0.14, 0.16, 0.0))
	for wx in [-0.8, 0.8]:
		for wz in [-1.4, 1.4]:
			cb.add_box(Vector3(wx, 0.32, wz), Vector3(0.25, 0.64, 0.64), Color(0.05, 0.05, 0.05, 0.0))
	car_mesh = cb.commit()


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


func material_for(key: String, params: Dictionary, _owner: Node) -> Material:
	if key in ["runway", "taxiway", "apron", "road"]:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/pavement.gdshader")
		m.set_shader_parameter("noise_tex", TexGen.noise_tex(256, 0.04, 4, 11))
		for k in params.keys():
			m.set_shader_parameter(k, params[k])
		m.set_shader_parameter("flood", 1.0 if key == "apron" else 0.0)
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("wetness", wetness)
		m.set_shader_parameter("world_origin", Vector3(view.origin_x, 0.0, view.origin_z))
		_pave.append(m)
		return m
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	match key:
		"paint":
			var sm := StandardMaterial3D.new()
			sm.vertex_color_use_as_albedo = true
			sm.vertex_color_is_srgb = true
			sm.roughness = 0.75
			mat = sm
		"vcolor", "vcolor_2s":
			var sm2 := StandardMaterial3D.new()
			sm2.vertex_color_use_as_albedo = true
			sm2.vertex_color_is_srgb = true
			sm2.roughness = 0.65
			if key == "vcolor_2s":
				sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = sm2
		"glass", "concrete", "metal", "cab":
			var fm := ShaderMaterial.new()
			fm.shader = load("res://shaders/facility.gdshader")
			match key:
				"glass":
					fm.set_shader_parameter("kind", 0)
					fm.set_shader_parameter("base_color", Color(0.78, 0.8, 0.82))
				"concrete":
					fm.set_shader_parameter("kind", 1)
					fm.set_shader_parameter("base_color", Color(0.74, 0.73, 0.7))
				"metal":
					fm.set_shader_parameter("kind", 2)
					fm.set_shader_parameter("base_color", Color(0.62, 0.67, 0.72))
				"cab":
					fm.set_shader_parameter("kind", 3)
			mat = fm
		_:
			mat = StandardMaterial3D.new()
	_materials[key] = mat
	return mat


func update_focus(x: float, z: float, _alt: float) -> void:
	# start builds for airports coming into range, drop those far away
	for icao in Airports.ORDER:
		var a: Dictionary = Airports.DATA[icao]
		var d := U.dist2d(x, z, a.x, a.z)
		if d < load_radius and not views.has(icao) and not _building.has(icao):
			_building[icao] = true
			var det := detail
			_tasks.append(WorkerThreadPool.add_task(func():
				var prod := AirportBuilder.build(icao, det)
				_mutex.lock()
				_ready_products.append(prod)
				_mutex.unlock(), false, "airport " + icao))
		elif d > unload_radius and views.has(icao):
			var v: AirportView = views[icao]
			view.unregister_static(v)
			v.queue_free()
			views.erase(icao)
	var prod_list := []
	_mutex.lock()
	if not _ready_products.is_empty():
		prod_list.append(_ready_products.pop_front())
	_mutex.unlock()
	for prod in prod_list:
		var icao2: String = prod.icao
		_building.erase(icao2)
		if views.has(icao2):
			continue
		var av := AirportView.new()
		add_child(av)
		av.build_from(prod, self)
		var ap: Dictionary = Airports.DATA[icao2]
		view.register_static(av, ap.x, ap.elev, ap.z)
		views[icao2] = av
		av.update_wind(float(view.weather.get("wind_dir", 270.0)), float(view.weather.get("wind_kt", 5.0)))
	_wind_timer -= get_process_delta_time()
	if _wind_timer <= 0.0:
		_wind_timer = 3.0
		var w: Dictionary = view.weather
		var wet := 1.0 if w.get("precip", "none") in ["rain", "thunderstorm"] else 0.0
		if wet != wetness:
			wetness = wet
			for m in _pave:
				if is_instance_valid(m):
					m.set_shader_parameter("wetness", wetness)
		light_material.set_shader_parameter("fog_density", float(view.env.fog_density) * 0.7)
		light_material.set_shader_parameter("intensity", 1.0 + clampf((8000.0 - float(w.get("vis", 20000.0))) / 8000.0, 0.0, 1.0))
		for icao3 in views.keys():
			views[icao3].update_wind(float(w.get("wind_dir", 270.0)), float(w.get("wind_kt", 5.0)))
	_cleanup_tasks()


func _cleanup_tasks() -> void:
	if _tasks.size() < 8:
		return
	var still: Array[int] = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			still.append(t)
	_tasks = still


func set_night(n: float) -> void:
	night = n
	light_material.set_shader_parameter("night", n)
	for m in _pave:
		if is_instance_valid(m):
			m.set_shader_parameter("night", n)
	for key in ["glass", "cab"]:
		if _materials.has(key):
			_materials[key].set_shader_parameter("night", n)


func set_origin(o: Vector3) -> void:
	for m in _pave:
		if is_instance_valid(m):
			m.set_shader_parameter("world_origin", o)


func get_view(icao: String) -> AirportView:
	return views.get(icao, null)


func is_loaded(icao: String) -> bool:
	return views.has(icao)


## Synchronous build (loading screens): ensures an airport is present right now.
func ensure_loaded(icao: String) -> AirportView:
	if views.has(icao):
		return views[icao]
	var prod := AirportBuilder.build(icao, detail)
	var av := AirportView.new()
	add_child(av)
	av.build_from(prod, self)
	var ap: Dictionary = Airports.DATA[icao]
	view.register_static(av, ap.x, ap.elev, ap.z)
	views[icao] = av
	_building.erase(icao)
	return av
