extends Node
## Root screen manager. Menus sit over a live 3D backdrop (an airliner being turned around at a
## gate at golden hour); a flight replaces the backdrop with a full FlightSession.

const MENU_SCREENS := ["menu", "create", "hub", "briefing", "free", "passenger", "news", "archive", "settings", "jobs", "logbook",
	"activities", "activity", "profile", "hangar", "world_map"]

var current: Node = null
var backdrop: Node3D = null
var session: FlightSession = null
var ui_layer: CanvasLayer


func _ready() -> void:
	Game.main = self
	get_tree().set_auto_accept_quit(true)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)
	# draw a loading screen first, so a slow machine never shows a frozen blank window
	var boot := _boot_screen()
	ui_layer.add_child(boot)
	await get_tree().process_frame
	await get_tree().process_frame
	Game.load_game()
	var start := "menu"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].begins_with("screen="):
		start = args[0].substr(7)
	show_screen(start, {})
	await get_tree().process_frame
	var tw := boot.create_tween()
	tw.tween_property(boot, "modulate:a", 0.0, 0.6)
	tw.tween_callback(boot.queue_free)


func _boot_screen() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.03, 0.05, 0.08)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var t := Label.new()
	t.text = "SKYFALL"
	t.add_theme_font_size_override("font_size", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := Label.new()
	l.text = "Loading the world..."
	l.add_theme_color_override("font_color", Color(0.62, 0.68, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return c


func show_screen(screen_name: String, params: Dictionary) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if current and is_instance_valid(current):
		current.queue_free()
	current = null
	if screen_name == "flight":
		_free_backdrop()
		_free_session()
		session = FlightSession.new()
		session.name = "Flight"
		add_child(session)
		session.start(params)
		current = session
		return
	if screen_name == "replay":
		_free_session()
		_free_backdrop()
		var rs: GDScript = load("res://src/ui/replay_view.gd")
		var rv: Node = rs.new()
		add_child(rv)
		rv.call("setup", params)
		current = rv
		return
	_free_session()
	Audio.music(screen_name in MENU_SCREENS and bool(Game.settings.get("menu_music", true)))
	_static_bg(screen_name in MENU_SCREENS and not bool(Game.q("backdrop")))
	if screen_name in MENU_SCREENS and backdrop == null and bool(Game.q("backdrop")):
		var bs: GDScript = load("res://src/ui/screens/menu_backdrop.gd")
		backdrop = bs.new()
		backdrop.name = "Backdrop"
		add_child(backdrop)
		move_child(backdrop, 0)
	var path := "res://src/ui/screens/%s.gd" % screen_name
	if not ResourceLoader.exists(path):
		path = "res://src/ui/screens/menu.gd"
	var script: GDScript = load(path)
	var scr: Control = script.new()
	scr.name = screen_name.capitalize()
	ui_layer.add_child(scr)
	scr.call("setup", params)
	current = scr
	if backdrop and backdrop.has_method("focus"):
		backdrop.call("focus", screen_name)


func _free_backdrop() -> void:
	if backdrop and is_instance_valid(backdrop):
		backdrop.queue_free()
	backdrop = null


func _free_session() -> void:
	if session and is_instance_valid(session):
		session.queue_free()
	session = null
	WorldSim.sim_running = false
	PilotInput.reset()
	PilotInput.touch_active = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if Game.has_character():
			Game.save_game()


var _bg: CanvasLayer = null


## On the lightest preset the menus sit on a painted sky instead of the live 3D airport.
func _static_bg(on: bool) -> void:
	if not on:
		if _bg:
			_bg.queue_free()
			_bg = null
		return
	if _bg:
		return
	_bg = CanvasLayer.new()
	_bg.layer = -5
	add_child(_bg)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.13, 0.22, 0.38), Color(0.55, 0.47, 0.5), Color(0.92, 0.62, 0.38)])
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(tr)
