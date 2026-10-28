class_name WorldView
extends Node3D
## A self-contained view of the simulated world: environment, sun/moon, sky, fog, clouds,
## precipitation, water, terrain and airports, with a floating origin so the camera can travel
## hundreds of kilometres without precision loss. Used by flights, menus and cinematics alike.

signal origin_shifted(shift: Vector3)

const REBASE_DIST := 2048.0
const LATITUDE := 39.5

var origin_x := 0.0
var origin_z := 0.0
var dynamic_root: Node3D
var static_root: Node3D
var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var terrain: TerrainManager
var airports: AirportManager
var ocean: MeshInstance3D
var water_mat: ShaderMaterial
var inland_water_mat: ShaderMaterial
var cloud_mat: ShaderMaterial
var cloud_low: MeshInstance3D
var cloud_high: MeshInstance3D
var storm_root: Node3D
var storm_mat: ShaderMaterial
var precip: MeshInstance3D
var precip_mat: ShaderMaterial
var camera: Camera3D = null

var time := 0.0                   # world clock (seconds)
var weather := {}                 # weather at the camera
var weather_override := {}        # optional fixed weather (menus, cinematics)
var day_factor := 1.0
var night := 0.0
var sun_dir := Vector3.UP
var inside_cloud := 0.0
var cloud_base := 1500.0
var cloud_top := 2600.0
var cam_world := Vector3.ZERO     # x/z world (double precision as floats), y altitude
var view_distance := 100000.0
var static_items := []            # [node, wx, wy, wz]
var storm_cells := []             # [{x, z, r, top}]
var _sky_timer := 0.0
var _wx_timer := 0.0
var _storm_timer := 0.0
var _flash := 0.0
var _next_flash := 6.0
var _wind_off := Vector2.ZERO
var _last_sky_sun := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func setup(start_x: float, start_z: float, clock: float, with_airports: bool = true) -> void:
	_rng.seed = 77
	time = clock
	Geo.set_season(U.clock_to_date(clock).doy)
	origin_x = snappedf(start_x, 1024.0)
	origin_z = snappedf(start_z, 1024.0)
	view_distance = float(Game.q("view"))
	static_root = Node3D.new()
	static_root.name = "Static"
	add_child(static_root)
	dynamic_root = Node3D.new()
	dynamic_root.name = "Dynamic"
	add_child(dynamic_root)
	_build_environment()
	terrain = TerrainManager.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(self)
	_build_water()
	_build_clouds()
	_build_precip()
	if with_airports:
		airports = AirportManager.new()
		airports.name = "Airports"
		add_child(airports)
		airports.setup(self)
	update_weather(true)
	update_lighting(true)


# ------------------------------------------------------------------ coordinates
func world_to_local_xz(wx: float, wz: float) -> Vector3:
	return Vector3(wx - origin_x, 0.0, wz - origin_z)


func world_to_local(wx: float, wy: float, wz: float) -> Vector3:
	return Vector3(wx - origin_x, wy, wz - origin_z)


func wx(local: Vector3) -> float:
	return local.x + origin_x


func wz(local: Vector3) -> float:
	return local.z + origin_z


func register_static(node: Node3D, world_x: float, world_y: float, world_z: float) -> void:
	static_items.append([node, world_x, world_y, world_z])
	node.position = world_to_local(world_x, world_y, world_z)


func unregister_static(node: Node3D) -> void:
	for i in range(static_items.size() - 1, -1, -1):
		if static_items[i][0] == node:
			static_items.remove_at(i)


func rebase(focus_local: Vector3) -> void:
	var sx := snappedf(focus_local.x, 1024.0)
	var sz := snappedf(focus_local.z, 1024.0)
	if sx == 0.0 and sz == 0.0:
		return
	var shift := Vector3(sx, 0.0, sz)
	origin_x += sx
	origin_z += sz
	for child in dynamic_root.get_children():
		if child is Node3D:
			child.position -= shift
	for item in static_items:
		if is_instance_valid(item[0]):
			item[0].position = world_to_local(item[1], item[2], item[3])
	terrain.reposition()
	_update_origin_uniforms()
	origin_shifted.emit(shift)


func _update_origin_uniforms() -> void:
	var o := Vector3(origin_x, 0.0, origin_z)
	terrain.material.set_shader_parameter("world_origin", o)
	water_mat.set_shader_parameter("world_origin", o)
	inland_water_mat.set_shader_parameter("world_origin", o)
	cloud_mat.set_shader_parameter("world_origin", o)
	if airports:
		airports.set_origin(o)


# ------------------------------------------------------------------ build
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_tex", TexGen.cloud_tex(256))
	sky.sky_material = sky_mat
	var rs := int(Game.q("sky_res"))
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if rs <= 64 else (Sky.RADIANCE_SIZE_128 if rs <= 128 else Sky.RADIANCE_SIZE_256)
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = bool(Game.q("glow"))
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.18
	env.fog_density = 0.00005
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.15
	env.fog_height = -200.0
	env.fog_height_density = 0.0
	env.ssao_enabled = bool(Game.q("ssao")) and Game.renderer == "forward_plus"
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.02
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.3
	sun.shadow_enabled = int(Game.q("shadows")) > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(Game.q("shadows")) >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = float(Game.q("shadow_distance"))
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_blend_splits = int(Game.q("shadows")) >= 2
	sun.light_angular_distance = 0.5
	add_child(sun)


var interior := false


func set_interior(on: bool) -> void:
	## Camera inside a cabin or flight deck: only the view through the windows is outdoors, so
	## the sun's shadows are concentrated on the few metres around the camera. Sharp, tightly
	## biased shadows keep sunlight from leaking through the thin interior shells (even on low
	## quality, where outdoor shadows are off).
	if on == interior:
		return
	interior = on
	var q_shadows := int(Game.q("shadows"))
	sun.shadow_enabled = on or q_shadows > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if on or q_shadows < 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 45.0 if on else float(Game.q("shadow_distance"))
	sun.shadow_normal_bias = 0.5 if on else 1.2
	sun.shadow_bias = 0.02 if on else 0.04


func _build_water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("normal_tex", TexGen.normal_tex(256, 0.025, 3, 5.0))
	var mt := TexGen.macro_depth_tex()
	water_mat.set_shader_parameter("macro_tex", mt)
	water_mat.set_shader_parameter("map_half", Geo.MAP_HALF)
	inland_water_mat = water_mat.duplicate()
	inland_water_mat.set_shader_parameter("use_macro", 0.0)
	inland_water_mat.set_shader_parameter("flat_shallow", 0.55)
	inland_water_mat.set_shader_parameter("shallow_color", Color(0.07, 0.2, 0.17))
	inland_water_mat.set_shader_parameter("wave_scale", 0.45)
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(view_distance * 2.2, view_distance * 2.2)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	ocean.mesh = pm
	ocean.material_override = water_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.extra_cull_margin = 4000.0
	add_child(ocean)
	# lakes
	for lk in Geo.lakes:
		var mb := MeshBuilder.new()
		var segs := 64
		var center := mb.add_vertex(Vector3.ZERO, Vector3.UP, Color.WHITE)
		for i in segs + 1:
			var a := TAU * i / segs
			mb.add_vertex(Vector3(cos(a) * lk.rx * 1.3, 0.0, sin(a) * lk.rz * 1.3), Vector3.UP, Color.WHITE)
		for i in segs:
			mb.add_tri_idx(center, center + 1 + i, center + 2 + i)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = inland_water_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		static_root.add_child(mi)
		register_static(mi, lk.x, lk.level, lk.z)
	# rivers as ribbons following their water level
	for rv in Geo.rivers:
		var pts: PackedVector2Array = rv.pts
		var levels: PackedFloat32Array = rv.levels
		var start := 0
		while start < pts.size() - 1:
			var stop := mini(start + 8, pts.size() - 1)
			var o := pts[start]
			var mb2 := MeshBuilder.new()
			var half: float = rv.width * 0.5 + 8.0
			for i in range(start, stop + 1):
				var dir: Vector2
				if i < pts.size() - 1:
					dir = (pts[i + 1] - pts[i]).normalized()
				else:
					dir = (pts[i] - pts[i - 1]).normalized()
				var side := Vector2(-dir.y, dir.x) * half
				var p := pts[i] - o
				mb2.add_vertex(Vector3(p.x + side.x, levels[i], p.y + side.y), Vector3.UP, Color.WHITE)
				mb2.add_vertex(Vector3(p.x - side.x, levels[i], p.y - side.y), Vector3.UP, Color.WHITE)
			for k in stop - start:
				var a0 := k * 2
				mb2.add_tri_idx(a0, a0 + 1, a0 + 2)
				mb2.add_tri_idx(a0 + 1, a0 + 3, a0 + 2)
			var rmi := MeshInstance3D.new()
			rmi.mesh = mb2.commit()
			rmi.material_override = inland_water_mat
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			static_root.add_child(rmi)
			register_static(rmi, o.x, 0.0, o.y)
			start = stop


func _build_clouds() -> void:
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://shaders/clouds.gdshader")
	cloud_mat.set_shader_parameter("cloud_tex", TexGen.cloud_tex(256))
	var q := int(Game.q("clouds"))
	cloud_mat.set_shader_parameter("steps", [1, 1, 16, 22][clampi(q, 0, 3)])
	var extent := minf(view_distance * 0.7, 70000.0)
	cloud_mat.set_shader_parameter("extent", extent)
	var pm := PlaneMesh.new()
	pm.size = Vector2(extent * 2.0, extent * 2.0)
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	cloud_low = MeshInstance3D.new()
	cloud_low.mesh = pm
	cloud_low.material_override = cloud_mat
	cloud_low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_low.extra_cull_margin = 20000.0
	add_child(cloud_low)
	cloud_high = MeshInstance3D.new()
	cloud_high.mesh = pm
	cloud_high.material_override = cloud_mat
	cloud_high.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_high.extra_cull_margin = 20000.0
	add_child(cloud_high)
	storm_root = Node3D.new()
	storm_root.name = "Storms"
	add_child(storm_root)
	storm_mat = ShaderMaterial.new()
	storm_mat.shader = load("res://shaders/cumulonimbus.gdshader")
	storm_mat.set_shader_parameter("noise_tex", TexGen.noise_tex(128, 0.05, 3, 21))


func _build_precip() -> void:
	precip_mat = ShaderMaterial.new()
	precip_mat.shader = load("res://shaders/precip.gdshader")
	precip = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 14.0
	cm.bottom_radius = 14.0
	cm.height = 40.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 16
	precip.mesh = cm
	precip.material_override = precip_mat
	precip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	precip.visible = false
	add_child(precip)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if terrain == null:
		return
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	cam_world = Vector3(cp.x + origin_x, cp.y, cp.z + origin_z)
	if absf(cp.x) > REBASE_DIST or absf(cp.z) > REBASE_DIST:
		rebase(cp)
		cp = cam.global_position
	var ground := Geo.height(cam_world.x, cam_world.z)
	terrain.set_camera(cam_world.x, cam_world.z, cp.y, cp.y - maxf(ground, 0.0))
	if airports:
		airports.update_focus(cam_world.x, cam_world.z, cp.y)
	ocean.position = Vector3(snappedf(cp.x, 2000.0), 0.0, snappedf(cp.z, 2000.0))
	_wind_off += Vector2(0.000004, 0.0000025) * delta * maxf(float(weather.get("wind_kt", 10.0)), 3.0)
	_update_clouds(cp)
	_update_precip(cp)
	_update_lightning(delta)
	_wx_timer -= delta
	if _wx_timer <= 0.0:
		_wx_timer = 2.0
		update_weather(false)
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 0.5
		update_lighting(false)
	_storm_timer -= delta
	if _storm_timer <= 0.0:
		_storm_timer = 8.0
		_update_storms()


func set_time(clock: float) -> void:
	time = clock


func update_weather(force: bool) -> void:
	if not weather_override.is_empty():
		weather = weather_override.duplicate()
	else:
		weather = WeatherModel.sample(cam_world.x, cam_world.z, time)
	var cover: float = weather.cover
	var base_m: float = float(weather.base_ft) * U.FT
	var thick := lerpf(500.0, 2600.0, cover)
	if weather.precip == "thunderstorm":
		thick = 3000.0
	if float(weather.vis) < 1500.0 and weather.precip == "none":
		thick = 260.0
	cloud_base = base_m
	cloud_top = base_m + thick
	cloud_mat.set_shader_parameter("base_y", cloud_base)
	cloud_mat.set_shader_parameter("top_y", cloud_top)
	cloud_mat.set_shader_parameter("coverage", clampf(cover * 1.05, 0.0, 0.98))
	cloud_mat.set_shader_parameter("storm", float(weather.storm))
	sky_mat.set_shader_parameter("cirrus", 0.45 if cover < 0.6 else 0.15)
	var wet := 1.0 if weather.precip in ["rain", "thunderstorm"] else 0.0
	terrain.material.set_shader_parameter("wetness", wet * 0.8)
	var snowc := 1.0 if (weather.precip == "snow" or float(weather.temp_c) < -2.0) else 0.0
	terrain.material.set_shader_parameter("snow_cover", snowc)
	water_mat.set_shader_parameter("roughness_boost", 0.05 + float(weather.wind_kt) / 140.0)
	if force:
		_update_storms()


func _update_clouds(cp: Vector3) -> void:
	var cover: float = weather.get("cover", 0.0)
	var show := cover > 0.08
	var snap := Vector3(snappedf(cp.x, 500.0), 0.0, snappedf(cp.z, 500.0))
	cloud_low.visible = show and cp.y < cloud_top
	cloud_high.visible = show and cp.y > cloud_base
	cloud_low.position = Vector3(snap.x, cloud_base, snap.z)
	cloud_high.position = Vector3(snap.x, cloud_top, snap.z)
	cloud_mat.set_shader_parameter("wind_off", _wind_off)
	# inside the cloud slab: white-out fog
	var target := 0.0
	if show and cp.y > cloud_base and cp.y < cloud_top:
		var tex_cov := clampf((cover - 0.25) / 0.6, 0.0, 1.0)
		var hf := (cp.y - cloud_base) / maxf(cloud_top - cloud_base, 1.0)
		target = tex_cov * smoothstep(0.0, 0.12, hf) * (1.0 - smoothstep(0.75, 1.0, hf))
	inside_cloud = U.damp(inside_cloud, target, 2.5, get_process_delta_time())
	_apply_fog()


func _apply_fog() -> void:
	var vis: float = maxf(float(weather.get("vis", 40000.0)), 150.0)
	var cam_alt := cam_world.y
	var density := 1.6 / vis
	# visibility restrictions are a low-level phenomenon; above the layer the air is clear
	var low_vis_top := float(weather.get("base_ft", 3000.0)) * U.FT + 150.0
	if vis < 8000.0 and cam_alt > low_vis_top:
		density = lerpf(density, 2.6 / 60000.0, U.smooth01((cam_alt - low_vis_top) / 800.0))
	density = minf(density, 0.02)
	density = maxf(density, 2.2 / maxf(view_distance * 0.9, 20000.0))
	# thinner air aloft: looking down from cruise the haze is mostly below you
	density *= lerpf(1.0, 0.3, U.smooth01(cam_alt / 7000.0))
	density = lerpf(density, 0.012, inside_cloud)
	env.fog_density = density
	env.fog_sky_affect = clampf(0.1 + (1.0 - vis / 20000.0) * 0.8 + inside_cloud, 0.0, 1.0)


func _update_precip(cp: Vector3) -> void:
	var p: String = weather.get("precip", "none")
	var intensity := 0.0
	match p:
		"rain": intensity = 0.55
		"thunderstorm": intensity = 0.95
		"snow": intensity = 0.7
	if cp.y > cloud_top:
		intensity = 0.0
	precip.visible = intensity > 0.01
	if precip.visible:
		precip.global_position = cp
		precip_mat.set_shader_parameter("intensity", intensity)
		precip_mat.set_shader_parameter("snow", 1.0 if p == "snow" else 0.0)
		var lc := Color(0.75, 0.78, 0.82) * (0.25 + day_factor * 0.75)
		precip_mat.set_shader_parameter("light_col", lc)


func _update_lightning(delta: float) -> void:
	if not weather.get("lightning", false):
		_flash = 0.0
	else:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_next_flash = _rng.randf_range(3.0, 14.0)
			_flash = _rng.randf_range(0.6, 1.4)
			var dist := _rng.randf_range(1.0, 12.0)
			get_tree().create_timer(dist * 2.9).timeout.connect(func():
				if Audio.has_method("thunder"):
					Audio.thunder(dist))
		_flash = maxf(_flash - delta * 6.0, 0.0)
	var f := _flash * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.09))
	sky_mat.set_shader_parameter("flash", f * 0.6)
	storm_mat.set_shader_parameter("flash", f)
	if f > 0.01:
		env.ambient_light_energy = 1.0 + f * 2.0
	elif env.ambient_light_energy > 1.0:
		env.ambient_light_energy = 1.0


func _update_storms() -> void:
	for c in storm_root.get_children():
		unregister_static(c)
		c.queue_free()
	storm_cells.clear()
	if weather_override.is_empty():
		var grid := 16000.0
		var cx := snappedf(cam_world.x, grid)
		var cz := snappedf(cam_world.z, grid)
		for gz in range(-4, 5):
			for gx in range(-4, 5):
				var px := cx + gx * grid
				var pz := cz + gz * grid
				var w := WeatherModel.sample(px, pz, time)
				if w.precip == "thunderstorm" and storm_cells.size() < 6:
					var h := U.hash_ints(int(px / grid), int(pz / grid), 3)
					var jx := (float(h % 1000) / 1000.0 - 0.5) * grid * 0.6
					var jz := (float((h / 1000) % 1000) / 1000.0 - 0.5) * grid * 0.6
					storm_cells.append({"x": px + jx, "z": pz + jz, "r": 4200.0 + float(h % 2000), "top": 11000.0 + float(h % 3000)})
	elif weather_override.get("precip", "") == "thunderstorm":
		for i in 3:
			var a := TAU * i / 3.0 + 0.7
			storm_cells.append({"x": cam_world.x + cos(a) * 18000.0, "z": cam_world.z + sin(a) * 18000.0, "r": 4500.0, "top": 11500.0})
	for cell in storm_cells:
		var mi := MeshInstance3D.new()
		mi.mesh = _storm_mesh(cell.r, cell.top, U.hash_ints(int(cell.x), int(cell.z)))
		mi.material_override = storm_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 5000.0
		storm_root.add_child(mi)
		register_static(mi, cell.x, maxf(cloud_base - 300.0, 400.0), cell.z)


static var _storm_cache := {}


func _storm_mesh(r: float, top: float, seed_value: int) -> ArrayMesh:
	var key := "%d_%d_%d" % [int(r), int(top), seed_value % 7]
	if _storm_cache.has(key):
		return _storm_cache[key]
	var mb := MeshBuilder.new()
	var rr := U.rng(seed_value % 7 + 1)
	var layers := 7
	for l in layers:
		var t := float(l) / (layers - 1)
		var y := t * top
		var rad := r * (0.55 + 0.45 * sin(t * PI * 0.8 + 0.3))
		if l == layers - 1:
			# anvil
			mb.add_sphere(Vector3(r * 0.4, y, 0), Vector3(r * 2.2, r * 0.25, r * 1.6), 12, 6, Color.WHITE)
			continue
		var puffs := 3 + l % 2
		for k in puffs:
			var a := rr.randf() * TAU
			var off := Vector3(cos(a), 0, sin(a)) * rad * 0.45
			var pr := rad * rr.randf_range(0.55, 0.8)
			mb.add_sphere(Vector3(off.x, y, off.z), Vector3(pr, pr * 0.85, pr), 10, 6, Color.WHITE)
	var mesh := mb.commit()
	_storm_cache[key] = mesh
	return mesh


func update_lighting(force: bool) -> void:
	var dt := U.clock_to_date(time)
	var hour: float = dt.hours_f
	var doy: int = dt.doy
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var ha := deg_to_rad(15.0 * (hour - 12.0))
	var lat := deg_to_rad(LATITUDE)
	var east := -cos(decl) * sin(ha)
	var north := sin(decl) * cos(lat) - cos(decl) * cos(ha) * sin(lat)
	var up := sin(decl) * sin(lat) + cos(decl) * cos(ha) * cos(lat)
	var s := Vector3(east, up, -north).normalized()
	sun_dir = s
	# moon: offset along its orbit by lunar phase
	var phase := fmod(float(time) / 86400.0 / 29.53 + 0.35, 1.0)
	var mha := ha - phase * TAU
	var m_e := -cos(-decl) * sin(mha)
	var m_n := sin(-decl) * cos(lat) - cos(-decl) * cos(mha) * sin(lat)
	var m_u := sin(-decl) * sin(lat) + cos(-decl) * cos(mha) * cos(lat)
	var moon := Vector3(m_e, m_u, -m_n).normalized()
	day_factor = U.smooth01((s.y + 0.08) / 0.3)
	night = 1.0 - U.smooth01((s.y + 0.1) / 0.18)
	var cover: float = weather.get("cover", 0.2)
	var storm: float = weather.get("storm", 0.0)
	# above the cloud deck the sky is clear and the sun unobstructed
	var above := U.smooth01((cam_world.y - cloud_base) / maxf(cloud_top - cloud_base, 1.0))
	cover = lerpf(cover, 0.0, above)
	storm = lerpf(storm, 0.0, above)
	var light_dir := s
	var energy := 0.0
	var col := Color(1, 0.97, 0.92)
	if s.y > -0.03:
		var elev := clampf(s.y, 0.0, 1.0)
		energy = U.smooth01((s.y + 0.03) / 0.2) * (1.25 - cover * 0.65 - storm * 0.3)
		col = Color(1.0, 0.5, 0.25).lerp(Color(1.0, 0.96, 0.9), U.smooth01(elev / 0.35))
	elif moon.y > 0.0:
		light_dir = moon
		energy = 0.22 * (1.0 - cover * 0.8) * (0.4 + 0.6 * absf(sin(phase * PI)))
		col = Color(0.62, 0.7, 0.95)
	var basis_up := Vector3.UP if absf(light_dir.y) < 0.98 else Vector3.FORWARD
	if force or light_dir.distance_to(_last_sky_sun) > 0.002:
		sun.basis = Basis.looking_at(-light_dir, basis_up)
		_last_sky_sun = light_dir
	sun.light_energy = maxf(energy, 0.0)
	sun.light_color = col
	sun.visible = energy > 0.005
	sky_mat.set_shader_parameter("moon_dir", moon)
	sky_mat.set_shader_parameter("sun_dir", s)
	var amb := lerpf(0.16, 1.0, day_factor) * (1.0 - storm * 0.3)
	env.ambient_light_energy = maxf(amb, 0.12) if _flash < 0.01 else env.ambient_light_energy
	sky_mat.set_shader_parameter("cover", cover * 0.35 if cover < 0.85 else cover * 0.9)
	sky_mat.set_shader_parameter("storm", storm)
	env.background_energy_multiplier = lerpf(0.4, 1.0, day_factor)
	# at night the sky radiance is nearly black; blend in a faint blue airglow so terrain reads
	env.ambient_light_color = Color(0.09, 0.12, 0.2)
	env.ambient_light_sky_contribution = lerpf(0.55, 1.0, day_factor)
	var horizon := _horizon_color(s, cover)
	env.fog_light_color = horizon
	env.fog_sun_scatter = 0.25 * (1.0 - cover) * (1.0 - night)
	env.tonemap_exposure = lerpf(1.6, 1.0, day_factor)
	terrain.material.set_shader_parameter("night", night)
	terrain.building_material.set_shader_parameter("night", night)
	var sc := Color(col.r, col.g, col.b) * maxf(energy, 0.0) * 0.9
	# clouds stay sunlit a little after sunset (they are higher than you are)
	var ce := U.smooth01((s.y + 0.12) / 0.16)
	var csun := Color(1.0, 0.38, 0.2).lerp(Color(1.0, 0.95, 0.88), U.smooth01((s.y - 0.02) / 0.3)) * ce * (1.15 - cover * 0.5)
	if ce < 0.02 and moon.y > 0.0:
		csun = Color(0.5, 0.56, 0.75) * 0.18
	cloud_mat.set_shader_parameter("sun_dir", s if s.y > -0.12 else moon)
	cloud_mat.set_shader_parameter("sun_col", csun)
	var twilight := U.smooth01((s.y + 0.2) / 0.16) * (1.0 - U.smooth01((s.y - 0.05) / 0.2))
	var ambc := Color(horizon.r, horizon.g, horizon.b) * (lerpf(0.25, 1.0, day_factor) + twilight * 0.5)
	cloud_mat.set_shader_parameter("amb_col", ambc.lerp(Color(0.85, 0.87, 0.9) * lerpf(0.08, 0.95, day_factor), 0.5))
	storm_mat.set_shader_parameter("sun_dir", s)
	storm_mat.set_shader_parameter("sun_col", sc)
	storm_mat.set_shader_parameter("amb_col", ambc)
	if airports:
		airports.set_night(night)


func _horizon_color(s: Vector3, cover: float) -> Color:
	var day := U.smooth01((s.y + 0.14) / 0.32)
	var twilight := U.smooth01((s.y + 0.22) / 0.2) * (1.0 - U.smooth01((s.y - 0.02) / 0.3))
	var c := Color(0.018, 0.03, 0.055).lerp(Color(0.62, 0.72, 0.84), day)
	c = c.lerp(Color(0.85, 0.55, 0.38), twilight * 0.45)
	var lum := c.get_luminance()
	c = c.lerp(Color(lum, lum, lum * 1.04), clampf(cover * 0.85, 0.0, 0.95))
	return c


## Blocks until the terrain around the camera is fully refined (used behind loading screens).
func warm_up(max_seconds: float = 8.0) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(max_seconds * 1000.0):
		await get_tree().process_frame
		if terrain.is_settled() and terrain.pending_count() == 0:
			break
