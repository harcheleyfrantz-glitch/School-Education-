extends Node
## Root screen manager. Menus sit over a live 3D backdrop (an airliner being turned around at a
## gate at golden hour); a flight replaces the backdrop with a full FlightSession.

const MENU_SCREENS := ["menu", "create", "hub", "briefing", "free", "passenger", "news", "archive", "settings", "jobs", "logbook"]

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
	Game.load_game()
	var start := "menu"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].begins_with("screen="):
		start = args[0].substr(7)
	show_screen(start, {})


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
	if screen_name in MENU_SCREENS and backdrop == null:
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
