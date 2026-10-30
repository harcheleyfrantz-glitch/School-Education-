extends Node
## Global game state: settings, quality presets, input map, player career, persistence, navigation.

signal settings_changed
signal toast(text: String, kind: String)
signal career_changed

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://skyfall_world.json"
const SAVE_VERSION := 1

const QUALITY := {
	"potato": {"label": "Very low (old PCs)", "render_scale": 0.6, "msaa": 0, "fxaa": false, "shadows": 0, "shadow_distance": 250.0,
		"ssao": false, "glow": false, "lod": 0.9, "min_leaf": 4000.0, "view": 28000.0, "trees": 0.12,
		"buildings": 0.3, "clouds": 0, "crowd": 0.25, "lights": false, "fps": 30, "sky_res": 32, "fog_vol": false,
		"backdrop": false, "studio": false},
	"low": {"label": "Low", "render_scale": 0.7, "msaa": 0, "fxaa": true, "shadows": 0, "shadow_distance": 400.0,
		"ssao": false, "glow": true, "lod": 1.15, "min_leaf": 2000.0, "view": 45000.0, "trees": 0.25,
		"buildings": 0.45, "clouds": 0, "crowd": 0.4, "lights": false, "fps": 30, "sky_res": 64, "fog_vol": false, "backdrop": true, "studio": true},
	"medium": {"label": "Medium", "render_scale": 0.85, "msaa": 0, "fxaa": true, "shadows": 1, "shadow_distance": 700.0,
		"ssao": false, "glow": true, "lod": 1.4, "min_leaf": 1000.0, "view": 70000.0, "trees": 0.55,
		"buildings": 0.7, "clouds": 1, "crowd": 0.7, "lights": true, "fps": 60, "sky_res": 128, "fog_vol": false, "backdrop": true, "studio": true},
	"high": {"label": "High", "render_scale": 1.0, "msaa": 1, "fxaa": false, "shadows": 2, "shadow_distance": 1200.0,
		"ssao": true, "glow": true, "lod": 1.8, "min_leaf": 1000.0, "view": 110000.0, "trees": 1.0,
		"buildings": 1.0, "clouds": 2, "crowd": 1.0, "lights": true, "fps": 0, "sky_res": 256, "fog_vol": false, "backdrop": true, "studio": true},
	"ultra": {"label": "Ultra", "render_scale": 1.0, "msaa": 2, "fxaa": false, "shadows": 3, "shadow_distance": 2000.0,
		"ssao": true, "glow": true, "lod": 2.3, "min_leaf": 500.0, "view": 160000.0, "trees": 1.4,
		"buildings": 1.2, "clouds": 3, "crowd": 1.0, "lights": true, "fps": 0, "sky_res": 256, "fog_vol": true, "backdrop": true, "studio": true},
}

var settings := {
	"quality": "",
	"master_volume": 0.85, "sfx_volume": 1.0, "music_volume": 0.6, "voice_volume": 1.0,
	"tts": true, "subtitles": true,
	"assist": "assisted",          # assisted | realistic
	"auto_rudder": true,
	"event_rate": "realistic",     # off | realistic | frequent
	"npc_crashes": "normal",       # other airlines' accidents: off | low | normal | high | extreme
	"repeat_crashes": "normal",    # odds a crash comes down at an earlier crash site
	"auto_atc": false,
	"units_metric": false,
	"mouse_sens": 1.0, "invert_pitch": false,
	"touch_tilt": false, "touch_scale": 1.0,
	"show_fps": false,
	"crash_realism": true,
	"hud_mode": "full",            # full | minimal | off
}

var is_mobile := false
var has_touch := false
var renderer := "forward_plus"

## Player career data (current character). Empty when no active character.
var player := {}
## Archive of previous characters (deceased, retired, or abandoned).
var archive := []
## Parameters for the next screen (set before navigating).
var nav_params := {}
var main: Node = null
var flight_count_session := 0
var _autosave_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	has_touch = DisplayServer.is_touchscreen_available()
	renderer = str(RenderingServer.get_current_rendering_method())
	_setup_input()
	_load_settings()
	if settings.quality == "":
		settings.quality = _detect_quality()
	Geo.init_world()
	apply_settings()


func _detect_quality() -> String:
	## First launch: pick a preset the machine can carry. Integrated graphics, the OpenGL
	## fallback and machines with few CPU threads start low; only strong desktops start high.
	var cores := OS.get_processor_count()
	var adapter := RenderingServer.get_video_adapter_type()
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var integrated := adapter == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or gpu.contains("intel") or gpu.contains("uhd") or gpu.contains(" hd graphics") or gpu.contains("vega 8")
	if is_mobile:
		return "low" if renderer == "gl_compatibility" or cores < 6 else "medium"
	if renderer == "gl_compatibility" or cores <= 2 or adapter == RenderingDevice.DEVICE_TYPE_CPU:
		return "potato"
	if integrated or cores <= 4:
		return "low"
	if cores >= 8 and adapter == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return "high"
	return "medium"


func q(key: String) -> Variant:
	var preset: Dictionary = QUALITY.get(settings.quality, QUALITY["medium"])
	return preset.get(key)


func apply_settings() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = float(q("render_scale"))
		if renderer != "gl_compatibility" and float(q("render_scale")) < 0.99 and not is_mobile:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		var msaa := int(q("msaa"))
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(msaa, 0, 2)]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q("fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = renderer == "forward_plus" and String(settings.quality) == "ultra"
	Engine.max_fps = int(q("fps"))
	_apply_audio()
	settings_changed.emit()


func _apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(float(settings.master_volume), 0.0001)))
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.call("apply_volumes")


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		if cf.has_section_key("settings", k):
			settings[k] = cf.get_value("settings", k)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func notify(text: String, kind: String = "info") -> void:
	toast.emit(text, kind)


# ------------------------------------------------------------------ input map
func _setup_input() -> void:
	var keys := {
		# W/S drive the aircraft forward (thrust), A/D roll in the air and steer on the ground,
		# the arrow keys fly pitch and roll
		"pitch_down": [KEY_UP], "pitch_up": [KEY_DOWN],
		"roll_left": [KEY_A, KEY_LEFT], "roll_right": [KEY_D, KEY_RIGHT],
		"yaw_left": [KEY_Q, KEY_KP_0], "yaw_right": [KEY_E, KEY_KP_ENTER],
		"throttle_up": [KEY_W, KEY_SHIFT, KEY_PAGEUP, KEY_KP_ADD], "throttle_down": [KEY_S, KEY_CTRL, KEY_PAGEDOWN, KEY_KP_SUBTRACT],
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"throttle_idle": [KEY_F1], "throttle_full": [KEY_F4],
		"flaps_down": [KEY_F, KEY_F7], "flaps_up": [KEY_V, KEY_F6],
		"gear": [KEY_G], "brakes": [KEY_B, KEY_PERIOD], "parking_brake": [KEY_P],
		"spoilers": [KEY_X, KEY_SLASH], "reverse": [KEY_R],
		"autopilot": [KEY_Z], "autothrottle": [KEY_T],
		"trim_up": [KEY_END, KEY_KP_1], "trim_down": [KEY_HOME, KEY_KP_7],
		"camera_next": [KEY_C], "cam_cockpit": [KEY_1], "cam_external": [KEY_2], "cam_chase": [KEY_3],
		"cam_tower": [KEY_4], "cam_flyby": [KEY_5], "cam_cabin": [KEY_6], "cam_wing": [KEY_7], "cam_free": [KEY_8],
		"atc": [KEY_TAB], "checklist": [KEY_K], "map": [KEY_M], "hud": [KEY_H], "lights_landing": [KEY_L],
		"pause": [KEY_ESCAPE], "simrate_up": [KEY_EQUAL], "simrate_down": [KEY_MINUS],
		"interact": [KEY_SPACE], "help": [KEY_F12], "walk_run": [KEY_SHIFT],
		"tiller_left": [KEY_COMMA, KEY_A], "tiller_right": [KEY_SEMICOLON, KEY_D], "pa": [KEY_J], "crew": [KEY_U],
		"seatbelt": [KEY_O], "oxygen_mask": [KEY_Y], "look_back": [KEY_BACKSPACE], "autofly": [KEY_I], "skip_ahead": [KEY_N],
	}
	for action in keys.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var pad_buttons := {
		"gear": JOY_BUTTON_Y, "brakes": JOY_BUTTON_B, "autopilot": JOY_BUTTON_X, "camera_next": JOY_BUTTON_BACK,
		"pause": JOY_BUTTON_START, "flaps_down": JOY_BUTTON_RIGHT_SHOULDER, "flaps_up": JOY_BUTTON_LEFT_SHOULDER,
		"atc": JOY_BUTTON_DPAD_UP, "checklist": JOY_BUTTON_DPAD_DOWN, "spoilers": JOY_BUTTON_DPAD_LEFT,
		"interact": JOY_BUTTON_A, "reverse": JOY_BUTTON_DPAD_RIGHT,
	}
	for action in pad_buttons.keys():
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad_buttons[action]
		InputMap.action_add_event(action, jb)
	var axes := {
		"roll_left": [JOY_AXIS_LEFT_X, -1.0], "roll_right": [JOY_AXIS_LEFT_X, 1.0],
		"pitch_down": [JOY_AXIS_LEFT_Y, -1.0], "pitch_up": [JOY_AXIS_LEFT_Y, 1.0],
		"throttle_up": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "throttle_down": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	}
	for action in axes.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		var ja := InputEventJoypadMotion.new()
		ja.axis = axes[action][0]
		ja.axis_value = axes[action][1]
		InputMap.action_add_event(action, ja)


# ------------------------------------------------------------------ career / character
func has_character() -> bool:
	return not player.is_empty() and player.get("status", "") == "active"


func new_character(data: Dictionary) -> void:
	if not player.is_empty() and player.get("status", "") == "active":
		retire_character("abandoned")
	var start: Dictionary = CareerRules.START_PATHS.get(data.get("path", "student"), CareerRules.START_PATHS["student"])
	player = {
		"id": "P%d" % (Time.get_ticks_usec() % 100000000),
		"name": data.get("name", "Alex Morgan"), "first": data.get("first", "Alex"), "last": data.get("last", "Morgan"),
		"gender": data.get("gender", "x"), "age": int(data.get("age", 28)), "home": data.get("home", "Port Calder"),
		"skin": int(data.get("skin", 2)), "hair": int(data.get("hair", 1)),
		"path": data.get("path", "student"), "airline": start.airline, "rank": start.rank,
		"ratings": start.ratings.duplicate(), "hours": float(start.hours), "hours_by_type": {},
		"money": float(start.money), "reputation": 50.0, "safety": 100.0, "public": 50.0,
		"location": start.base, "base": start.base, "status": "active",
		"created": WorldSim.clock, "flights": 0, "landings": 0, "incidents": [], "logbook": [],
		"suspended_until": 0.0, "injury": "", "recovery_until": 0.0, "warnings": 0, "commendations": 0,
		"license": start.license, "checkride_due": "", "notes": [],
	}
	WorldSim.on_new_character(player)
	career_changed.emit()
	save_game()


func retire_character(reason: String, details: Dictionary = {}) -> void:
	if player.is_empty():
		return
	var rec := player.duplicate(true)
	rec["ended"] = WorldSim.clock
	rec["end_reason"] = reason
	rec["end_details"] = details
	rec["status"] = reason
	archive.append(rec)
	player = {}
	career_changed.emit()
	save_game()


func add_money(amount: float, reason: String) -> void:
	if player.is_empty():
		return
	player.money = float(player.money) + amount
	player.notes.append({"t": WorldSim.clock, "money": amount, "reason": reason})
	if player.notes.size() > 200:
		player.notes = player.notes.slice(player.notes.size() - 200)


# ------------------------------------------------------------------ persistence
func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"player": player,
		"archive": archive,
		"world": WorldSim.serialize(),
		"news": News.serialize(),
	}
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var d := DirAccess.open("user://")
	if d:
		if d.file_exists(SAVE_PATH.get_file()):
			d.remove(SAVE_PATH.get_file())
		d.rename(SAVE_PATH.get_file() + ".tmp", SAVE_PATH.get_file())


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	player = data.get("player", {})
	archive = data.get("archive", [])
	WorldSim.deserialize(data.get("world", {}))
	News.deserialize(data.get("news", {}))
	career_changed.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func wipe_world() -> void:
	player = {}
	archive = []
	WorldSim.reset_world()
	News.reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	career_changed.emit()


func goto(screen: String, params: Dictionary = {}) -> void:
	nav_params = params
	if main and main.has_method("show_screen"):
		main.show_screen(screen, params)


## Clock driving crowd animation in shaders; the news video player overrides it while rendering.
var crowd_clock := 0.0
var crowd_clock_override := -1.0


func _process(delta: float) -> void:
	crowd_clock = fmod(crowd_clock + delta, 7200.0)
	RenderingServer.global_shader_parameter_set("crowd_time", crowd_clock if crowd_clock_override < 0.0 else crowd_clock_override)
	_autosave_timer += delta
	if _autosave_timer > 120.0:
		_autosave_timer = 0.0
		if main and main.has_method("can_autosave") and main.can_autosave():
			save_game()
