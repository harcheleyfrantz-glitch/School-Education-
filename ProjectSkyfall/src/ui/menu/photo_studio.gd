class_name PhotoStudio
extends Node
## Offscreen photo studio for the front end. Card images are real in-engine renders - aircraft
## over the world at golden hour, flight decks at dusk, cabins, airports from the air, the
## player's pilot - each built in a SubViewport with its own World3D (a full WorldView when the
## shot needs the world), rendered once, then cached in memory and on disk so menus stay fast.
## Shots render one at a time, and only while a menu (not a flight) is on screen.

signal shot_ready(id: String, tex: Texture2D)

const CACHE_DIR := "user://studio_cache"
const VERSION := 3
const WIDE := Vector2i(1024, 576)
const HERO := Vector2i(1280, 600)
const CARD := Vector2i(768, 640)
const TALL := Vector2i(600, 800)
const DATE := [2027, 6, 21]

## Fixed shots used by the menus. Dynamic ids are resolved in recipe(): "ap:ICAO" (an airport
## from the air), "type:TYPE:AIRLINE" (an aircraft in the hangar studio), "scn:ID" (an activity
## scenario, see Activities), "pilot:..." and "career:..." (the player's pilot).
## Air shots: the aircraft flies at `at` (world x/z) `agl` metres up with its heading `sun_rel`
## degrees from the sun's azimuth; cam = (azimuth from the nose, elevation, distance in aircraft
## lengths); aim = where the subject sits in the frame (-1..1, +x right, +y up).
const SHOTS := {
	"home_featured": {"kind": "air", "size": HERO, "type": "s320", "airline": "SKF", "at": Vector2(-50500, 8000), "agl": 900.0,
		"hour": 18.95, "weather": "scattered", "look_rel": 125.0, "heading_rel": 128.0, "el": -9.0, "dist": 1.6, "pitch": 9.0,
		"bank": -16.0, "fov": 26.0, "aim": Vector2(0.14, 0.04)},
	"home_featured_b": {"kind": "air", "size": HERO, "type": "s320", "airline": "SKF", "at": Vector2(-50500, 8000), "agl": 1400.0,
		"hour": 15.6, "weather": "scattered", "look_rel": 150.0, "heading_rel": 120.0, "el": -6.0, "dist": 1.45, "pitch": 7.0,
		"bank": -12.0, "fov": 26.0, "aim": Vector2(0.2, 0.05)},
	"home_worldmap": {"kind": "map", "size": CARD, "dep": "SKPC", "arr": "SKHP", "zoom": 1.55, "center": Vector2(10, -30)},
	"home_activities": {"kind": "air", "size": CARD, "type": "t172", "airline": "HFA", "at": Vector2(55000, 77000), "agl": 260.0,
		"hour": 18.7, "weather": "few", "look_rel": 135.0, "heading_rel": 120.0, "el": 6.0, "dist": 2.0, "pitch": 2.0, "bank": -14.0,
		"fov": 34.0},
	"home_passenger": {"kind": "cabin", "size": CARD, "type": "s320", "airline": "SKF", "at": Vector2(-20000, 60000), "agl": 3600.0,
		"hour": 18.85, "weather": "scattered", "sun_rel": 80.0, "view": "aisle", "bright": 1.1},
	"home_hangar": {"kind": "studio", "size": CARD, "type": "bj6", "airline": "APX", "cam": Vector3(-35.0, 7.0, 1.45), "fov": 32.0},
	"home_news": {"kind": "ground", "place": "runway", "size": CARD, "type": "w350", "airline": "WMA", "icao": "SKPC", "rwy": "27R",
		"along": 1500.0, "lift": 4.0, "pitch": 9.0, "hour": 18.6, "weather": "few", "cam_side": 130.0, "cam_h": 2.5, "cam_ahead": 70.0,
		"fov": 17.0},
	"act_discovery": {"kind": "air", "size": TALL, "type": "bj6", "airline": "APX", "at": Vector2(212000, -182000), "agl": 1100.0,
		"hour": 18.8, "weather": "clear", "look_rel": 130.0, "heading_rel": 140.0, "el": 10.0, "dist": 2.5, "pitch": 4.0, "bank": -22.0,
		"fov": 40.0, "aim": Vector2(0.0, 0.22), "airports": false},
	"act_landing": {"kind": "final", "size": TALL, "type": "s320", "airline": "LMN", "icao": "SKIM", "rwy": "11", "dist_km": 1.6,
		"hour": 18.4, "weather": "few", "cam": Vector3(190.0, 12.0, 2.6), "fov": 40.0, "aim": Vector2(0.0, -0.32)},
	"act_bush": {"kind": "air", "size": TALL, "type": "t172", "airline": "HFA", "at": Vector2(-31500, 251000), "agl": 160.0,
		"hour": 10.2, "weather": "few", "look_rel": 150.0, "heading_rel": 110.0, "el": 9.0, "dist": 2.4, "pitch": 2.0, "bank": 15.0,
		"fov": 40.0, "aim": Vector2(0.0, 0.08), "airports": false},
	"prof_hangar": {"kind": "studio", "size": HERO, "type": "w350", "airline": "SKF", "cam": Vector3(-42.0, 5.0, 1.05), "fov": 34.0,
		"aim": Vector2(0.18, 0.0)},
	"prof_logbook": {"kind": "cockpit", "size": CARD, "type": "s320", "airline": "SKF", "at": Vector2(-60000, -30000), "agl": 3200.0,
		"hour": 19.3, "weather": "scattered", "sun_rel": 40.0, "view": "wide"},
	"prof_career": {"kind": "ground", "place": "apron", "size": CARD, "type": "s320", "airline": "SKF", "icao": "SKPC", "stand": 5,
		"apron": 75.0, "hour": 18.95, "weather": "few", "pilot": true, "look_rel": 25.0, "heading_rel": 28.0, "dist": 1.25, "cam_h": 1.5,
		"fov": 42.0, "aim": Vector2(0.0, -0.08)},
}

static var _mem := {}
static var _node: PhotoStudio = null
## Render scale (tests render smaller); part of the cache key.
static var scale := 1.0
static var use_disk := true

var _queue: Array[String] = []
var _busy := false
var _current := ""
var _vp: SubViewport = null
var _view: WorldView = null
var _cam: Camera3D = null
var _props: Array = []
var _settled := true


static func instance() -> PhotoStudio:
	if _node == null or not is_instance_valid(_node):
		_node = PhotoStudio.new()
		_node.name = "PhotoStudio"
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.add_child.call_deferred(_node)
	return _node


## The image for a shot: from memory, from the disk cache, or null while it is being rendered
## (listen to shot_ready).
static func get_shot(id: String, priority: bool = false) -> Texture2D:
	if _mem.has(id):
		return _mem[id]
	if not bool(Game.q("studio")):
		return null
	var rec := recipe(id)
	if rec.is_empty():
		return null
	if use_disk:
		var path := _cache_path(id, rec)
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				var tex := _to_texture(img)
				_mem[id] = tex
				return tex
	instance().request(id, priority)
	return null


## Drops a shot from memory and from the disk cache (it is rendered again on the next request).
static func invalidate(id: String) -> void:
	_mem.erase(id)
	var rec := recipe(id)
	if not rec.is_empty() and FileAccess.file_exists(_cache_path(id, rec)):
		DirAccess.remove_absolute(_cache_path(id, rec))


static func has_shot(id: String) -> bool:
	return _mem.has(id)


static func forget(id: String) -> void:
	_mem.erase(id)


static func recipe(id: String) -> Dictionary:
	if SHOTS.has(id):
		return SHOTS[id]
	var parts := id.split(":")
	match parts[0]:
		"ap":
			return _airport_recipe(parts[1] if parts.size() > 1 else "SKPC")
		"type":
			var t := parts[1] if parts.size() > 1 else "s320"
			var al := parts[2] if parts.size() > 2 else "SKF"
			var spec := AircraftTypes.get_type(t)
			return {"kind": "studio", "size": WIDE, "type": t, "airline": al, "cam": Vector3(-40.0, 6.0, 1.12 if float(spec.span) < 40.0 else 1.0),
				"fov": 34.0, "aim": Vector2(0.0, 0.0)}
		"scn":
			var scn := Activities.get_scenario(parts[1] if parts.size() > 1 else "")
			if scn.is_empty():
				return {}
			return Activities.shot_recipe(scn)
		"pilot":
			# pilot:skin:hair_color:hair:build:airline
			return {"kind": "portrait", "size": Vector2i(320, 320), "look": _look_from(parts)}
		"career":
			# career:airline:type:skin:hair_color:hair:build
			var al2 := parts[1] if parts.size() > 1 else "SKF"
			var t2 := parts[2] if parts.size() > 2 else "s320"
			var r: Dictionary = (SHOTS["prof_career"] as Dictionary).duplicate()
			r.size = CARD
			r.airline = al2
			r.type = t2
			r.look = _look_from(["career", parts[3] if parts.size() > 3 else "2", parts[4] if parts.size() > 4 else "1",
				parts[5] if parts.size() > 5 else "1", parts[6] if parts.size() > 6 else "0.5", al2])
			return r
	return {}


## Shot id for the player's pilot (portrait or career card), stable for an appearance.
static func pilot_id(kind: String = "pilot") -> String:
	var p: Dictionary = Game.player
	var a: Dictionary = p.get("appearance", {})
	var al := String(p.get("airline", "SKF"))
	if al == "":
		al = "SKF"
	var look := "%d:%d:%d:%.2f" % [int(a.get("skin", p.get("skin", 2))), int(a.get("hair_color", 1)), int(a.get("hair", p.get("hair", 1))),
		float(a.get("build", 0.5))]
	if kind == "career":
		var t := "s320"
		var ratings: Array = p.get("ratings", [])
		for r in ratings:
			if String(r) != "t172":
				t = String(r)
		if p.is_empty():
			return "career:SKF:s320:2:1:1:0.50"
		return "career:%s:%s:%s" % [al, t, look]
	return "pilot:%s:%s" % [look, al]


static func _look_from(parts: Array) -> Dictionary:
	return {"skin": int(parts[1]) if parts.size() > 1 else 2, "hair_color": int(parts[2]) if parts.size() > 2 else 1,
		"hair": int(parts[3]) if parts.size() > 3 else 1, "build": float(parts[4]) if parts.size() > 4 else 0.5,
		"airline": String(parts[5]) if parts.size() > 5 else "SKF"}


static func _airport_recipe(icao: String) -> Dictionary:
	var ap: Dictionary = Airports.get_ap(icao)
	var big := String(ap.get("size", "regional")) == "hub"
	return {"kind": "aerial", "size": WIDE, "icao": icao, "hour": 18.4, "weather": "few", "cam_alt": 900.0 if big else 620.0,
		"cam_dist": 3300.0 if big else 2300.0, "sun_rel": 205.0, "fov": 44.0, "aim": Vector2(0.0, 0.08)}


static func _cache_path(id: String, rec: Dictionary) -> String:
	var key := "%s|%d|%.2f|%s" % [id, VERSION, scale, var_to_str(rec)]
	return "%s/%s_%08x.webp" % [CACHE_DIR, id.replace(":", "_").replace("/", "_").replace(".", "_"), key.hash() & 0x7FFFFFFF]


static func _to_texture(img: Image) -> ImageTexture:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	if not img.has_mipmaps():
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func request(id: String, priority: bool = false) -> void:
	if _mem.has(id) or id == _current:
		return
	if _queue.has(id):
		if priority:
			_queue.erase(id)
			_queue.push_front(id)
		return
	if priority:
		_queue.push_front(id)
	else:
		_queue.append(id)


func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty() or not _menu_active():
		return
	_busy = true
	_current = _queue.pop_front()
	_render(_current)


static func _menu_active() -> bool:
	var m: Node = Game.main
	if m == null or not is_instance_valid(m):
		return true
	return m.get("session") == null


# ================================================================== rendering
func _render(id: String) -> void:
	var rec := recipe(id)
	var size: Vector2i = rec.get("size", WIDE)
	size = Vector2i(maxi(int(size.x * scale), 64), maxi(int(size.y * scale), 64))
	# supersampled: the volumetric clouds and foliage dither, and the downsample resolves it
	var ss := 1 if Game.is_mobile else 2
	_vp = SubViewport.new()
	_vp.name = "Shot"
	_vp.size = size * ss
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.positional_shadow_atlas_size = 2048
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 220000.0
	var ok := false
	_settled = true
	match String(rec.get("kind", "")):
		"air", "final", "ground", "aerial", "cockpit", "cabin":
			ok = await _world_shot(rec)
		"studio":
			ok = await _studio_shot(rec)
		"portrait":
			ok = await _portrait_shot(rec)
		"map":
			ok = await _map_shot(rec)
	if ok and is_instance_valid(_vp) and _menu_active():
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if is_instance_valid(_vp):
			var img := _vp.get_texture().get_image()
			if img != null and not img.is_empty():
				img.convert(Image.FORMAT_RGB8)
				if img.get_size() != size:
					img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
				# a render whose terrain had not finished streaming is shown but not kept
				if use_disk and _settled:
					DirAccess.make_dir_recursive_absolute(CACHE_DIR)
					img.save_webp(_cache_path(id, rec), true, 0.88)
				var tex := _to_texture(img)
				_mem[id] = tex
				_cleanup()
				_busy = false
				_current = ""
				shot_ready.emit(id, tex)
				return
	_cleanup()
	if not ok and not _menu_active():
		_queue.push_front(id)
	_busy = false
	_current = ""


func _cleanup() -> void:
	_props.clear()
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_view = null
	_cam = null


## True when the render may go on (the menu is still up and the viewport exists).
func _alive() -> bool:
	return is_instance_valid(_vp) and _menu_active()


static func _weather(preset: String, at: Vector2, clock: float) -> Dictionary:
	var old := WeatherModel.override_preset
	var old_dir := WeatherModel.override_dir
	WeatherModel.override_preset = preset
	WeatherModel.override_dir = -1.0
	var w := WeatherModel.sample(at.x, at.y, clock)
	WeatherModel.override_preset = old
	WeatherModel.override_dir = old_dir
	return w


## Gentle split-tone grade: cool shadows, warm highlights, a soft S-curve.
static var _grade: GradientTexture1D


static func grade() -> GradientTexture1D:
	if _grade == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.0, 0.012, 0.03))
		g.set_color(1, Color(1.0, 0.985, 0.95))
		g.add_point(0.22, Color(0.17, 0.2, 0.235))
		g.add_point(0.5, Color(0.515, 0.5, 0.485))
		g.add_point(0.78, Color(0.83, 0.79, 0.74))
		_grade = GradientTexture1D.new()
		_grade.gradient = g
		_grade.width = 256
	return _grade


static func _att(hdg: float, pitch: float, bank: float) -> Basis:
	var b := Basis(Vector3.UP, -deg_to_rad(hdg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.FORWARD, deg_to_rad(bank))
	return b.orthonormalized()


static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _focus(rec: Dictionary) -> Vector2:
	if rec.has("at"):
		return rec.at
	var ap: Dictionary = Airports.get_ap(String(rec.get("icao", "SKPC")))
	return Vector2(float(ap.x), float(ap.z))


func _world_shot(rec: Dictionary) -> bool:
	var kind := String(rec.kind)
	var clock := U.date_to_clock(int(DATE[0]), int(DATE[1]), int(DATE[2]), float(rec.get("hour", 18.5)))
	var focus := _focus(rec)
	_view = WorldView.new()
	_view.name = "World"
	_vp.add_child(_view)
	var old_q := String(Game.settings.quality)
	Game.settings.quality = "low" if old_q in ["low", "potato"] or Game.is_mobile else "medium"
	var old_snow := Geo.snowline
	_view.setup(focus.x, focus.y, clock, bool(rec.get("airports", kind in ["ground", "final", "aerial"])))
	Geo.snowline = old_snow
	Game.settings.quality = old_q
	_view.weather_override = _weather(String(rec.get("weather", "few")), focus, clock)
	_view.update_weather(true)
	_view.update_lighting(true)
	_view.dynamic_root.add_child(_cam)
	_cam.current = true
	_view.camera = _cam
	_view.sun.shadow_enabled = true
	_view.env.glow_enabled = true
	_view.env.glow_intensity = float(rec.get("glow", 0.7))
	_view.env.glow_bloom = 0.06
	_view.env.adjustment_brightness = float(rec.get("bright", 1.0))
	_view.env.adjustment_saturation = float(rec.get("sat", 1.16))
	_view.env.adjustment_contrast = float(rec.get("contrast", 1.1))
	_view.env.adjustment_color_correction = grade()
	var sun_az := U.dir_to_heading(Vector3(_view.sun_dir.x, 0.0, _view.sun_dir.z))
	var icao := String(rec.get("icao", ""))
	match kind:
		"air":
			_setup_air(rec, sun_az)
		"final":
			_setup_final(rec)
		"ground":
			_setup_ground(rec, sun_az)
		"aerial":
			_setup_aerial(rec, sun_az)
		"cockpit":
			_setup_cockpit(rec, sun_az)
		"cabin":
			_setup_cabin(rec, sun_az)
	# stream the terrain (and the airport) around the camera before the exposure
	if icao != "" and _view.airports:
		var t0 := Time.get_ticks_msec()
		while not _view.airports.is_loaded(icao) and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
			if not _alive():
				return false
	await _view.warm_up(60.0)
	if not _alive():
		return false
	_settled = _view.terrain.is_settled()
	# a few frames for the sky radiance, shadows and LOD to settle
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await get_tree().process_frame
	return _alive()


func _aircraft(rec: Dictionary, xf: Transform3D, on_ground: bool, approach: bool = false) -> AircraftModel:
	var t := String(rec.get("type", "s320"))
	var al := String(rec.get("airline", "SKF"))
	var m := AircraftModel.new()
	m.name = "Subject"
	_view.dynamic_root.add_child(m)
	m.build(t, al, String(rec.get("reg", Airlines.get_al(al).get("reg_prefix", "CR-") + "SKY")), 1.0)
	m.transform = xf
	var spec := AircraftTypes.get_type(t)
	var flaps := float(rec.get("flaps", (spec.flaps as Array).size() - 1 if approach else 0))
	var gear := 1.0 if on_ground or approach else 0.0
	var fan := 0.0 if on_ground and not approach else 90.0
	var lit := {"nav": true, "beacon": not on_ground or approach, "strobe": false, "landing": approach, "cabin": true}
	for i in 3:
		m.animate_simple(gear, flaps, fan, lit, _view.night, 0.05)
	_props.append(m)
	return m


func _frame(target: Vector3, hdg: float, size: float, rec: Dictionary) -> void:
	var c: Vector3 = rec.get("cam", Vector3(-50.0, -3.0, 2.0))
	_cam.fov = float(rec.get("fov", 35.0))
	_cam.position = target + _dir(hdg + c.x, c.y) * c.z * size
	_aim(target, rec.get("aim", Vector2.ZERO))
	var sd := clampf(c.z * size * 3.0 + size * 2.0, 60.0, 1200.0)
	_view.sun.directional_shadow_max_distance = sd


func _aim(target: Vector3, aim: Vector2) -> void:
	_cam.look_at_from_position(_cam.position, target, Vector3.UP)
	if aim == Vector2.ZERO:
		return
	var tv := tan(deg_to_rad(_cam.fov) * 0.5)
	var aspect := float(_vp.size.x) / float(_vp.size.y)
	_cam.rotate_object_local(Vector3.UP, atan(aim.x * tv * aspect))
	_cam.rotate_object_local(Vector3.RIGHT, -atan(aim.y * tv))


## Air shots are framed from the camera: it looks `look_rel` degrees from the sun's azimuth
## (180 = sun behind the camera), the aircraft flies `heading_rel` degrees from the look
## direction (90 = left to right, 130 = to the right and towards the camera), the camera sits
## `el` degrees above (+) or below (-) it, `dist` aircraft lengths away.
func _setup_air(rec: Dictionary, sun_az: float) -> void:
	var at: Vector2 = rec.at
	var alt := maxf(Geo.ground_height(at.x, at.y), 0.0) + float(rec.get("agl", 500.0))
	var look := U.wrap_deg(sun_az + float(rec.get("look_rel", 140.0)))
	var hdg := U.wrap_deg(look + float(rec.get("heading_rel", 120.0)))
	var xf := Transform3D(_att(hdg, float(rec.get("pitch", 3.0)), float(rec.get("bank", 0.0))), _view.world_to_local(at.x, alt, at.y))
	var m := _aircraft(rec, xf, false)
	var size := float(m.spec.length)
	var d := float(rec.get("dist", 1.8)) * size
	_cam.fov = float(rec.get("fov", 30.0))
	_cam.position = xf.origin + _dir(look + 180.0, float(rec.get("el", -4.0))) * d
	_aim(xf.origin, rec.get("aim", Vector2.ZERO))
	_view.sun.directional_shadow_max_distance = clampf(d * 3.0 + size * 2.0, 60.0, 1200.0)


func _setup_final(rec: Dictionary) -> void:
	var e := Airports.runway_end(String(rec.icao), String(rec.rwy))
	var hdg := float(e.hdg)
	var dir := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
	var d := float(rec.get("dist_km", 2.0)) * 1000.0
	var p := Vector2(float(e.thr_x), float(e.thr_z)) - dir * d
	var alt := float(e.elev) + 15.0 + d * tan(deg_to_rad(3.0))
	var xf := Transform3D(_att(hdg, float(rec.get("pitch", 2.5)), float(rec.get("bank", 0.0))), _view.world_to_local(p.x, alt, p.y))
	var m := _aircraft(rec, xf, false, true)
	_frame(xf.origin, hdg, float(m.spec.length), rec)


func _setup_ground(rec: Dictionary, sun_az: float) -> void:
	var icao := String(rec.icao)
	var ap: Dictionary = Airports.get_ap(icao)
	var spec := AircraftTypes.get_type(String(rec.get("type", "s320")))
	var elev := float(ap.elev)
	var place := String(rec.get("place", "stand"))
	var hdg := 0.0
	var pos := Vector2.ZERO          # airport-local x/z
	var lift := 0.0
	var pitch := 0.0
	if place == "runway":
		var e := Airports.runway_end(icao, String(rec.rwy))
		hdg = float(e.hdg)
		var d := Vector2(sin(deg_to_rad(hdg)), -cos(deg_to_rad(hdg)))
		pos = Vector2(float(e.thr_x) - float(ap.x), float(e.thr_z) - float(ap.z)) + d * float(rec.get("along", 1000.0))
		lift = float(rec.get("lift", 0.0))
		pitch = float(rec.get("pitch", 0.0))
	else:
		var L := AirportLayout.get_layout(icao)
		var sd: Dictionary = L.stands[clampi(int(rec.get("stand", 0)), 0, L.stands.size() - 1)]
		var n: Vector2 = sd.normal
		var face: Vector2 = sd.get("facade_origin", sd.stop)
		pos = face + n * (7.0 + float(spec.length) * float(spec.cg_frac) + float(rec.get("apron", 0.0)))
		hdg = float(sd.hdg)
	var look := 0.0
	if rec.has("look_rel"):
		look = U.wrap_deg(sun_az + float(rec.look_rel))
		if place != "runway":
			hdg = U.wrap_deg(look + 180.0 + float(rec.get("heading_rel", 25.0)))
	var on_ground := lift < 0.5
	var y := elev + float(spec.gear_height) - 0.05 + lift
	var xf := Transform3D(_att(hdg, pitch, 0.0), _view.world_to_local(float(ap.x) + pos.x, y, float(ap.z) + pos.y))
	var m := _aircraft(rec, xf, on_ground, not on_ground)
	if place == "stand":
		m.set_door("L1", 1.0)
	var lit := {"nav": true, "beacon": place != "stand", "strobe": false, "landing": place == "runway", "cabin": true}
	for i in 30:
		m.animate_simple(1.0, 1.0 if place == "runway" else 0.0, 0.0 if place == "stand" else 60.0, lit, _view.night, 0.1)
	var o := xf.origin
	o.y = _view.world_to_local(0, elev, 0).y
	_cam.fov = float(rec.get("fov", 40.0))
	var target := o + Vector3(0, float(spec.height) * 0.45, 0)
	if place == "runway":
		# a spotter beside the runway with a long lens
		var b := _att(hdg, 0.0, 0.0)
		_cam.position = o + b * Vector3(float(rec.get("cam_side", -120.0)), float(rec.get("cam_h", 2.0)), -float(rec.get("cam_ahead", 50.0)))
		target = xf.origin
	elif rec.has("look_rel"):
		var d2 := float(rec.get("dist", 2.0)) * float(spec.length)
		_cam.position = o + _dir(look + 180.0, 0.0) * d2 + Vector3(0, float(rec.get("cam_h", 1.6)), 0)
	else:
		var b2 := _att(hdg, 0.0, 0.0)
		_cam.position = o + b2 * (rec.get("cam_local", Vector3(-20.0, 1.6, -36.0)) as Vector3)
		target = o + b2 * (rec.get("look_local", Vector3(0.0, 3.0, -10.0)) as Vector3)
	_aim(target, rec.get("aim", Vector2.ZERO))
	_view.sun.directional_shadow_max_distance = 260.0
	if bool(rec.get("pilot", false)):
		# the pilot walks out to the aircraft, seen from behind
		var to_ac := target - _cam.position
		to_ac.y = 0.0
		var side := Vector3(-to_ac.z, 0.0, to_ac.x).normalized()
		var pp := _cam.position + to_ac.normalized() * float(rec.get("pilot_dist", 6.0)) + side * float(rec.get("pilot_side", 1.1))
		pp.y = o.y
		var face_yaw := atan2(to_ac.x, to_ac.z) + PI
		_person(rec.get("look", {"skin": 2, "hair_color": 1, "hair": 1, "build": 0.5, "airline": rec.get("airline", "SKF")}),
			Transform3D(Basis(Vector3.UP, face_yaw), pp), HumanMesh.POSES["walk"], 0.3)


func _setup_aerial(rec: Dictionary, sun_az: float) -> void:
	var target := _focus(rec)
	var ty := 0.0
	if rec.has("icao"):
		ty = float(Airports.get_ap(String(rec.icao)).elev)
	else:
		ty = maxf(Geo.ground_height(target.x, target.y), 0.0)
	var az := U.wrap_deg(sun_az + float(rec.get("sun_rel", 200.0)))
	var d := float(rec.get("cam_dist", 3000.0))
	var off := Vector2(sin(deg_to_rad(az)), -cos(deg_to_rad(az))) * d
	var cam_w := target + off
	var cam_y := ty + float(rec.get("cam_alt", 800.0))
	_cam.fov = float(rec.get("fov", 45.0))
	_cam.position = _view.world_to_local(cam_w.x, cam_y, cam_w.y)
	_aim(_view.world_to_local(target.x, ty, target.y), rec.get("aim", Vector2.ZERO))
	# re-centre the floating origin on the camera so the terrain streams around it
	_view.rebase(_cam.position)


func _setup_cockpit(rec: Dictionary, sun_az: float) -> void:
	var at: Vector2 = rec.at
	var hdg := U.wrap_deg(sun_az + float(rec.get("sun_rel", 40.0)))
	var alt := maxf(Geo.ground_height(at.x, at.y), 0.0) + float(rec.get("agl", 3000.0))
	var t := String(rec.get("type", "s320"))
	var ac := Aircraft.new()
	ac.name = "Subject"
	_view.dynamic_root.add_child(ac)
	ac.setup(t, "CR-SKY", String(rec.get("airline", "SKF")), _view, true)
	ac.player_controlled = false
	ac.set_physics_process(false)
	var spec := ac.spec
	ac.place_at(_view.world_to_local(at.x, alt, at.y), hdg, false, float(spec.cruise_ias) * U.KT)
	ac.model.show_exterior_fuselage(false)
	ac.sys.lights.landing = false
	ac.ap.engaged = true
	ac.ap.alt_sel = alt
	ac.ap.hdg_sel = hdg
	ac.ap.spd_sel = float(spec.cruise_ias)
	var ck := CockpitInterior.new()
	ac.add_child(ck)
	ck.build(t, String(rec.get("airline", "SKF")), "high")
	ck.attach(ac)
	ck.set_night(_view.night)
	_props.append(ac)
	var e: Vector3 = ck.E
	var view_kind := String(rec.get("view", "wide"))
	var from := e + Vector3(0.62, 0.16, 0.9) if view_kind == "wide" else e
	var to := e + Vector3(0.45, -0.32, -1.0) if view_kind == "wide" else e + Vector3(0.05, -0.1, -1.0)
	_cam.fov = 64.0 if view_kind == "wide" else 70.0
	_cam.near = 0.02
	_cam.position = ac.transform * from
	_aim(ac.transform * to, Vector2.ZERO)
	_view.set_interior(true)


func _setup_cabin(rec: Dictionary, sun_az: float) -> void:
	var at: Vector2 = rec.at
	var hdg := U.wrap_deg(sun_az + float(rec.get("sun_rel", 80.0)))
	var alt := maxf(Geo.ground_height(at.x, at.y), 0.0) + float(rec.get("agl", 3000.0))
	var t := String(rec.get("type", "s320"))
	var al := String(rec.get("airline", "SKF"))
	var xf := Transform3D(_att(hdg, 2.0, 0.0), _view.world_to_local(at.x, alt, at.y))
	var m := _aircraft(rec, xf, false)
	m.show_exterior_fuselage(false)
	var cab := CabinInterior.new()
	m.add_child(cab)
	cab.build(t, al)
	cab.set_signs(false)
	cab.set_light_mode("cruise")
	var lay := cab.lay
	var crowd := Crowd.new()
	m.add_child(crowd)
	crowd.setup(lay.seats.size() + 2, 0, al)
	var r := U.rng(91)
	var seats: Array = lay.seats
	# window seat on the sunny side, over the wing
	var side := 1
	var ws: Dictionary = seats[0]
	var wing_z := -float(m.spec.length) * (float(m.spec.cg_frac) - 0.02)
	var best := INF
	for s in seats:
		if bool(s.window) and int(s.side) == side:
			var dz := absf(float((s.pos as Vector3).z) - (wing_z + 1.6))
			if dz < best:
				best = dz
				ws = s
	for i in seats.size():
		var s2: Dictionary = seats[i]
		if s2 == ws or r.randf() > 0.8:
			continue
		var ap := Crowd.appearance_for({"id": i * 37 + 11, "gender": "f" if r.randf() < 0.5 else "m", "age": r.randi_range(14, 78)})
		var pxf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(ap.scale)), s2.pos)
		var pose: int = [HumanMesh.POSES["sit"], HumanMesh.POSES["sit_read"], HumanMesh.POSES["sit_sleep"], HumanMesh.POSES["sit_talk"]][r.randi() % 4]
		crowd.set_person(i, pxf, pose, r.randf(), 0.0, ap.top, ap.outfit, ap.seed, ap.flags, ap.build)
	crowd.flush()
	_cam.near = 0.03
	if String(rec.get("view", "aisle")) == "aisle":
		var ax: float = lay.aisles[0]
		var rows: Array = lay.rows
		var z_back := float(rows[mini(rows.size() - 1, int(rows.size() * 0.72))].z1)
		var z_front := float(rows[0].z0)
		var eye2 := Vector3(ax + 0.12, float(lay.floor_y) + 1.5, z_back)
		_cam.fov = 58.0
		_cam.position = xf * eye2
		_aim(xf * Vector3(ax - 0.2, float(lay.floor_y) + 1.05, z_front), Vector2.ZERO)
	else:
		var eye: Vector3 = (ws.pos as Vector3) + Vector3(-0.28 * side, 1.18, 0.32)
		_cam.fov = 62.0
		_cam.position = xf * eye
		_aim(xf * (eye + Vector3(1.6 * side, -0.32, 0.9)), Vector2.ZERO)
	_view.set_interior(true)


func _person(look: Dictionary, xf: Transform3D, pose: int, phase: float, parent: Node3D = null) -> SkinnedHuman:
	var h := SkinnedHuman.new()
	h.name = "Pilot"
	if parent == null:
		_view.dynamic_root.add_child(h)
	else:
		parent.add_child(h)
	h.setup(_skinned_look(look, String(look.get("airline", "SKF"))))
	h.transform = xf
	var clip := "walk" if pose == int(HumanMesh.POSES["walk"]) else ("sit" if pose == int(HumanMesh.POSES["sit"]) else "idle")
	h.play(clip, 0.0)
	h.anim.seek(phase * float(SkinnedHuman.CLIPS[clip][0]), true)
	h.anim.pause()
	_props.append(h)
	return h


static func _skinned_look(look: Dictionary, al: String) -> Dictionary:
	return {"top": Color(0.95, 0.95, 0.97), "outfit": Crowd.Outfit.FLIGHT, "seed": float(look.get("hair", 1)) + 0.37,
		"flags": Crowd.FLAG_HAT | Crowd.FLAG_TIE, "build": float(look.get("build", 0.5)), "skin": int(look.get("skin", 2)),
		"hair_color": int(look.get("hair_color", 1)), "airline": al}


# ================================================================== studio sets (no world)
func _studio_env(top: Color, horizon: Color, energy: float) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = top
	psm.sky_horizon_color = horizon
	psm.ground_horizon_color = horizon.darkened(0.2)
	psm.ground_bottom_color = top.darkened(0.4)
	psm.sun_angle_max = 1.0
	psm.sky_energy_multiplier = energy
	psm.ground_energy_multiplier = energy
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.1
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = Game.renderer == "forward_plus"
	e.ssr_enabled = Game.renderer == "forward_plus"
	e.ssr_max_steps = 96
	e.ssr_fade_in = 0.05
	e.ssr_fade_out = 1.5
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = e
	_vp.add_child(we)
	return e


func _studio_shot(rec: Dictionary) -> bool:
	## A hangar showroom: polished dark floor, a back wall of light strips behind the aircraft,
	## a ceiling of light panels, a warm key light and cool rim lights.
	_studio_env(Color(0.035, 0.045, 0.06), Color(0.11, 0.13, 0.16), 0.75)
	var root := Node3D.new()
	_vp.add_child(root)
	root.add_child(_cam)
	_cam.current = true
	var t := String(rec.get("type", "s320"))
	var spec := AircraftTypes.get_type(t)
	var L := float(spec.length)
	var S := maxf(L, float(spec.span))
	var c: Vector3 = rec.get("cam", Vector3(-40.0, 6.0, 1.15))
	var target := Vector3(0, float(spec.height) * 0.36, -L * 0.04)
	var cam_dir := _dir(c.x, c.y)
	_cam.fov = float(rec.get("fov", 34.0))
	_cam.position = target + cam_dir * c.z * S
	_cam.position.y = maxf(_cam.position.y, 0.6)
	_aim(target, rec.get("aim", Vector2.ZERO))
	# the set is built around the camera's line of sight so every angle has a backdrop
	var fwd := Vector3(-cam_dir.x, 0.0, -cam_dir.z).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var set_basis := Basis(side, Vector3.UP, -fwd)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(S * 10.0, S * 10.0)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.065, 0.075)
	fm.roughness = 0.38
	fm.metallic_specular = 0.25
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var wall := MeshBuilder.new()
	# floor markings: centreline and stand edge lines
	mb.add_box(Vector3(0, 0.006, 0), Vector3(0.22, 0.012, S * 3.0), Color(0.95, 0.74, 0.16))
	for k in [-1.0, 1.0]:
		mb.add_box(Vector3(k * S * 0.66, 0.006, 0), Vector3(0.16, 0.012, S * 2.2), Color(0.8, 0.82, 0.86))
	var back := S * 1.25
	wall.add_box(Vector3(0, S * 0.7, -back), Vector3(S * 9.0, S * 1.4, 0.6), Color(0.13, 0.14, 0.16))
	wall.add_box(Vector3(0, S * 1.42, 0), Vector3(S * 9.0, 0.4, S * 6.0), Color(0.08, 0.085, 0.095))
	for i in 15:
		var x := (float(i) - 7.0) * S * 0.3
		glow.add_box(Vector3(x, S * 0.62, -back + 0.35), Vector3(0.28, S * 1.0, 0.08), Color(1, 1, 1))
		wall.add_box(Vector3(x + S * 0.15, S * 0.7, -back + 0.4), Vector3(0.5, S * 1.4, 0.5), Color(0.2, 0.21, 0.23))
	for gx in 7:
		for gz in 5:
			glow.add_box(Vector3((float(gx) - 3.0) * S * 0.45, S * 1.2, (float(gz) - 2.5) * S * 0.5), Vector3(S * 0.28, 0.06, 0.9), Color(1, 1, 1))
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true
	wm.roughness = 0.7
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall.commit()
	wall_mi.transform = Transform3D(set_basis, Vector3.ZERO)
	wall_mi.material_override = wm
	wall_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wall_mi)
	var deco := MeshInstance3D.new()
	deco.mesh = mb.commit()
	deco.material_override = wm
	root.add_child(deco)
	var strips := MeshInstance3D.new()
	strips.mesh = glow.commit()
	strips.transform = Transform3D(set_basis, Vector3.ZERO)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.92, 0.95, 1.0)
	strips.material_override = sm
	strips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(strips)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(-_dir(c.x - 50.0, 40.0), Vector3.UP)
	key.light_energy = 1.6
	key.light_specular = 0.25
	key.light_color = Color(1.0, 0.91, 0.8)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = S * 3.0
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(-_dir(c.x + 160.0, 42.0), Vector3.UP)
	rim.light_energy = 1.2
	rim.light_specular = 0.2
	rim.light_color = Color(0.6, 0.75, 1.0)
	root.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(-_dir(c.x + 25.0, 12.0), Vector3.UP)
	fill.light_energy = 0.45
	fill.light_specular = 0.0
	fill.light_color = Color(0.8, 0.86, 1.0)
	root.add_child(fill)
	var m := AircraftModel.new()
	root.add_child(m)
	var al := String(rec.get("airline", "SKF"))
	m.build(t, al, String(Airlines.get_al(al).get("reg_prefix", "CR-")) + "SKY", 1.0)
	m.position = Vector3(0, float(spec.gear_height) - 0.05, 0)
	for i in 3:
		m.animate_simple(1.0, 0.0, 0.0, {"nav": true, "beacon": false, "cabin": true}, 0.2, 0.05)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await get_tree().process_frame
	return _alive()


func _map_shot(rec: Dictionary) -> bool:
	## The world map itself (shaded relief, airports and a route) for the WORLD MAP card.
	_vp.disable_3d = true
	var m := WorldMapView.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(m)
	m.dep = String(rec.get("dep", ""))
	m.arr = String(rec.get("arr", ""))
	await get_tree().process_frame
	m.fit_all(0.0)
	m.px_per_km *= float(rec.get("zoom", 1.0))
	if rec.has("center"):
		m.center = rec.center
	m._redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 3:
		await get_tree().process_frame
	return _alive()


func _portrait_shot(rec: Dictionary) -> bool:
	## Head-and-shoulders portrait of a pilot in uniform for avatars.
	_studio_env(Color(0.05, 0.08, 0.14), Color(0.16, 0.22, 0.32), 0.45)
	var root := Node3D.new()
	_vp.add_child(root)
	root.add_child(_cam)
	_cam.current = true
	var look: Dictionary = rec.get("look", {})
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(-Vector3(-0.7, 0.45, -1.0).normalized(), Vector3.UP)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.93, 0.84)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(-Vector3(0.9, 0.3, 0.9).normalized(), Vector3.UP)
	rim.light_energy = 1.3
	rim.light_color = Color(0.55, 0.75, 1.0)
	root.add_child(rim)
	var al := String(look.get("airline", "SKF"))
	var h := SkinnedHuman.new()
	root.add_child(h)
	h.setup(_skinned_look(look, al))
	h.rotation.y = deg_to_rad(18.0)
	h.play("idle", 0.0)
	h.anim.seek(1.8, true)
	_cam.fov = 24.0
	_cam.position = Vector3(0.0, 1.62, -1.85)
	_aim(Vector3(0.0, 1.5, 0.0), Vector2.ZERO)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await get_tree().process_frame
	return _alive()
