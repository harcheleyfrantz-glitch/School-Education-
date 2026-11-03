class_name TowerSession
extends Node3D
## AIR TRAFFIC CONTROL: you are the tower controller at any airport. Arrivals call in on final
## and need a landing clearance (or they go around); departures hold short until you clear them
## for takeoff. Put two aircraft on the runway at once and they collide. Emergencies need
## priority. A shift scores every safe movement and ends with a rating and a news story.

signal toast(text: String, kind: String)

const LEVELS := {"quiet": [70.0, 120.0, 4], "normal": [38.0, 75.0, 6], "rush": [18.0, 40.0, 9]}
const RATINGS := [[2500, "Chief of the Watch"], [1500, "Senior Controller"], [700, "Controller"], [200, "Assistant"], [-99999, "Trainee"]]

# what TrafficManager reads from its session
var ac = null
var atc: Node = null
var flight_id := "TOWER"
var dep_icao := ""
var arr_icao := ""
var callsign := "Tower"
var stand := ""
var arr_stand := ""
var dep_end: Dictionary = {}
var arr_end: Dictionary = {}

var icao := "KJFK"
var level := "normal"
var hour := 14.0
var view: WorldView
var cam: Camera3D
var traffic: TrafficManager
var score := 0
var stats := {"landed": 0, "departed": 0, "go_around": 0, "collision": 0, "saved": 0, "lost_emergency": 0}
var shift_t := 0.0
var shift_len := 900.0
var log_lines: Array = []
var selected: Dictionary = {}
var speed := 1.0
var wx := "few"
var paused := false
var _yaw := 0.0
var _pitch := -6.0
var _fov := 45.0
var _eye := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _emerg_t := 150.0
var _ui_t := 0.0
var _ended := false
var _layer: CanvasLayer
var _strips: VBoxContainer
var _log: RichTextLabel
var _status: Label
var _result: Control


func setup(p: Dictionary) -> void:
	icao = String(p.get("icao", Game.settings.get("tower_airport", "KJFK")))
	if not Airports.DATA.has(icao):
		icao = "KJFK"
	level = String(p.get("traffic", "normal"))
	hour = float(p.get("hour", 14.0))
	wx = String(p.get("weather", "few"))
	shift_len = float(p.get("shift", 900.0))
	Game.settings["tower_airport"] = icao
	dep_icao = icao
	arr_icao = icao
	flight_id = "TWR-%s-%d" % [icao, Time.get_ticks_msec()]
	_rng.randomize()
	atc = self
	WeatherModel.override_preset = wx
	var ap := Airports.get_ap(icao)
	var day0 := floorf(WorldSim.clock / 86400.0) * 86400.0
	view = WorldView.new()
	add_child(view)
	view.setup(float(ap.x), float(ap.z), day0 + hour * 3600.0, true)
	view.airports.ensure_loaded(icao)
	cam = Camera3D.new()
	cam.far = 90000.0
	cam.near = 0.5
	view.dynamic_root.add_child(cam)
	cam.current = true
	view.camera = cam
	# the tower cab, looking over the runways
	var L := AirportLayout.get_layout(icao)
	var tp: Vector2 = L.get("tower", Vector2.ZERO)
	_eye = view.world_to_local(float(ap.x) + tp.x, float(ap.elev) + float(L.get("tower_h", 40.0)) + 4.0, float(ap.z) + tp.y)
	_yaw = rad_to_deg(atan2(-tp.x, tp.y)) if tp.length() > 1.0 else 0.0
	var lv: Array = LEVELS.get(level, LEVELS.normal)
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	traffic.atc_mode = true
	traffic.atc_airport = icao
	traffic.spawn_range = Vector2(float(lv[0]), float(lv[1]))
	traffic.max_moving = int(lv[2])
	view.dynamic_root.add_child(traffic)
	traffic.setup(self, view)
	traffic._spawn_t = 2.0
	traffic.movement.connect(_on_movement)
	_build_ui()
	_radio("%s Tower" % String(ap.get("short", icao)), "Tower is open. Runway in use: %s. Good luck, controller." % _runway_name())


func _params(extra: Dictionary = {}) -> Dictionary:
	var d := {"icao": icao, "traffic": level, "hour": hour, "weather": wx, "shift": shift_len}
	d.merge(extra, true)
	return d


func _runway_name() -> String:
	var ap := Airports.get_ap(icao)
	var w := WeatherModel.sample(float(ap.x), float(ap.z), WorldSim.clock)
	var e := Airports.best_runway(icao, float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)))
	return String(e.get("name", "?"))


# ================================================================== radio (TrafficManager talks through these)
func traffic_call(_icao: String, cs: String, atc_text: String, reply: String) -> void:
	if atc_text != "":
		_radio("Tower", atc_text)
	if reply != "":
		_radio(cs, reply)


func traffic_advisory(text: String, _spoken: String) -> void:
	_radio("Tower", text)


func _radio(who: String, text: String) -> void:
	log_lines.append("[b]%s:[/b] %s" % [who, text])
	if log_lines.size() > 9:
		log_lines.pop_front()
	if _log:
		_log.text = "\n".join(log_lines)


# ================================================================== commands
func clear_land(item: Dictionary) -> void:
	if String(item.phase) != "final" or bool(item.get("clear_land", false)):
		return
	item.clear_land = true
	var e: Dictionary = item.end
	_radio("Tower", "%s, runway %s, cleared to land." % [item.callsign, e.name])
	_radio(String(item.callsign), "Cleared to land runway %s, %s." % [e.name, item.callsign])


func go_around(item: Dictionary) -> void:
	if not String(item.phase) in ["final", "flare"]:
		return
	item.phase = "go_around"
	_radio("Tower", "%s, go around, I say again, go around." % item.callsign)
	_radio(String(item.callsign), "Going around, %s." % item.callsign)
	_on_movement(item, "go_around")


func clear_takeoff(item: Dictionary) -> void:
	if String(item.phase) != "hold" or bool(item.get("clear_takeoff", false)):
		return
	item.clear_takeoff = true
	var e: Dictionary = item.end
	_radio("Tower", "%s, runway %s, cleared for takeoff." % [item.callsign, e.name])
	_radio(String(item.callsign), "Cleared for takeoff %s, %s." % [e.name, item.callsign])


func hold_position(item: Dictionary) -> void:
	if String(item.phase) == "hold" and bool(item.get("clear_takeoff", false)):
		item.clear_takeoff = false
		_radio("Tower", "%s, hold position, cancel takeoff clearance." % item.callsign)
		_radio(String(item.callsign), "Holding position, %s." % item.callsign)


func _on_movement(item: Dictionary, kind: String) -> void:
	var emerg := bool(item.get("emergency", false))
	match kind:
		"landed":
			stats.landed += 1
			score += 250 if emerg else 100
			if emerg:
				stats.saved += 1
				_radio(String(item.callsign), "On the ground, thank you Tower. You saved our day.")
				Achievements.unlock("mayday_saved")
		"departed":
			stats.departed += 1
			score += 100
		"go_around":
			stats.go_around += 1
			score -= 200 if emerg else 30
			if emerg:
				stats.lost_emergency += 1
		"collision":
			if int(item.get("_counted", 0)) == 0:
				item._counted = 1
				stats.collision += 1
				score -= 600
				_radio("Tower", "ALL STATIONS, ALL STATIONS, RUNWAY CLOSED. CRASH CREWS ROLLING.")
				toast.emit("RUNWAY COLLISION involving %s!" % String(item.callsign), "warning")
				Achievements.unlock("runway_collision")
	var moves := int(stats.landed) + int(stats.departed)
	Achievements.on_tower(moves)


# ================================================================== frame
func _process(delta: float) -> void:
	if view == null or _ended:
		return
	get_tree().paused = false
	Engine.time_scale = 0.0 if paused else speed
	shift_t += delta
	view.set_time(floorf(WorldSim.clock / 86400.0) * 86400.0 + hour * 3600.0 + shift_t)
	# camera: free look from the tower cab, or follow the selected aircraft
	var look_dir := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(-_yaw), 0.0)) * Vector3.FORWARD
	cam.global_position = _eye
	var m = selected.get("model") if not selected.is_empty() else null
	if m != null and is_instance_valid(m) and selected.has("x"):
		cam.look_at((m as Node3D).global_position + Vector3(0, 3, 0), Vector3.UP)
	else:
		cam.look_at(_eye + look_dir, Vector3.UP)
	cam.fov = lerpf(cam.fov, _fov, clampf(delta * 6.0, 0.0, 1.0))
	_tags()
	_emergencies(delta)
	_ui_t -= delta
	if _ui_t <= 0.0:
		_ui_t = 0.4
		_refresh_ui()
	if shift_t >= shift_len:
		_end_shift()


func _tags() -> void:
	for item in traffic.moving:
		var m = item.get("model")
		if m == null or not is_instance_valid(m) or (m as Node).has_node("Tag"):
			continue
		var lb := Label3D.new()
		lb.name = "Tag"
		lb.text = String(item.callsign)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.pixel_size = 0.0012
		lb.font_size = 26
		lb.outline_size = 6
		lb.modulate = Color(1.0, 0.9, 0.4) if bool(item.get("emergency", false)) else Color(0.85, 0.95, 1.0)
		lb.position = Vector3(0, float(AircraftTypes.get_type(String(item.type)).fuse_h) + 6.0, 0)
		(m as Node3D).add_child(lb)


func _emergencies(delta: float) -> void:
	_emerg_t -= delta
	if _emerg_t > 0.0:
		return
	_emerg_t = _rng.randf_range(200.0, 340.0)
	for item in traffic.moving:
		if String(item.phase) == "final" and float(item.get("dist", 0.0)) > 7000.0 and not bool(item.get("emergency", false)):
			item.emergency = true
			var why: String = ["an engine failure", "smoke in the cabin", "a sick passenger", "low fuel", "a hydraulic failure"][_rng.randi() % 5]
			_radio(String(item.callsign), "MAYDAY MAYDAY MAYDAY, %s, %s, request priority landing!" % [item.callsign, why])
			toast.emit("MAYDAY: %s has %s - clear them to land!" % [item.callsign, why], "warning")
			var tag = (item.model as Node).get_node_or_null("Tag") if item.get("model") != null else null
			if tag:
				(tag as Label3D).modulate = Color(1.0, 0.35, 0.3)
			return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		selected = {}
		_yaw += (event as InputEventMouseMotion).relative.x * 0.15
		_pitch = clampf(_pitch - (event as InputEventMouseMotion).relative.y * 0.12, -60.0, 20.0)
	elif event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP:
			_fov = clampf(_fov * 0.88, 4.0, 70.0)
		elif (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_fov = clampf(_fov / 0.88, 4.0, 70.0)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_exit()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_P, KEY_SPACE]:
		paused = not paused


# ================================================================== UI
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.theme()
	_layer.add_child(root)
	# left: shift panel
	var lp := UIStyle.panel(Vector2(300, 0), Color(0.03, 0.05, 0.08, 0.86))
	lp.position = Vector2(14, 14)
	root.add_child(lp)
	var lv := UIStyle.vbox(8)
	lp.add_child(lv)
	lv.add_child(UIStyle.caps("Air traffic control", 12, UIStyle.ACCENT, 800, 3))
	lv.add_child(UIStyle.title("%s Tower" % String(Airports.get_ap(icao).get("short", icao)), 24, Color.WHITE))
	_status = UIStyle.label("", 14, UIStyle.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_status)
	var ids: Array = Airports.ORDER.duplicate()
	var names := ids.map(func(i): return "%s - %s" % [i, Airports.get_ap(String(i)).get("short", i)])
	var aps := OptionButton.new()
	for n in names:
		aps.add_item(String(n))
	aps.select(maxi(ids.find(icao), 0))
	aps.item_selected.connect(func(i): Game.goto("tower", _params({"icao": String(ids[i])})))
	lv.add_child(aps)
	var lvls := ["quiet", "normal", "rush"]
	var tr := OptionButton.new()
	for n2 in ["Quiet", "Normal", "Rush hour"]:
		tr.add_item(n2)
	tr.select(lvls.find(level))
	tr.item_selected.connect(func(i): Game.goto("tower", _params({"traffic": lvls[i]})))
	lv.add_child(tr)
	var hrs := [8.0, 14.0, 19.0, 23.0]
	var tod := OptionButton.new()
	for n3 in ["Morning", "Afternoon", "Sunset", "Night shift"]:
		tod.add_item(n3)
	tod.select(maxi(hrs.find(hour), 1))
	tod.item_selected.connect(func(i): Game.goto("tower", _params({"hour": hrs[i]})))
	lv.add_child(tod)
	var wxs := ["clear", "few", "rain", "fog", "storm", "snow", "crosswind"]
	var wo := OptionButton.new()
	for n4 in ["Clear", "Fair", "Rain", "Fog", "Thunderstorms", "Snow", "Strong crosswind"]:
		wo.add_item(n4)
	wo.select(maxi(wxs.find(wx), 1))
	wo.item_selected.connect(func(i): Game.goto("tower", _params({"weather": wxs[i]})))
	lv.add_child(wo)
	var lens := [600.0, 900.0, 1800.0]
	var lo := OptionButton.new()
	for n5 in ["10 minute shift", "15 minute shift", "30 minute shift"]:
		lo.add_item(n5)
	lo.select(maxi(lens.find(shift_len), 1))
	lo.item_selected.connect(func(i): Game.goto("tower", _params({"shift": lens[i]})))
	lv.add_child(lo)
	var sp := UIStyle.hbox(6)
	sp.add_child(UIStyle.button("Pause", func(): paused = not paused, 80))
	for f in [1.0, 2.0, 4.0]:
		var ff: float = f
		sp.add_child(UIStyle.button("x%d" % int(ff), func(): speed = ff, 60))
	lv.add_child(sp)
	var eb := UIStyle.hbox(6)
	eb.add_child(UIStyle.button("End shift", func(): _end_shift(), 130, UIStyle.ACCENT))
	eb.add_child(UIStyle.button("Exit", func(): _exit(), 90))
	lv.add_child(eb)
	lv.add_child(UIStyle.label("Right-drag to look around, wheel to zoom. Click a strip to follow an aircraft.", 12, UIStyle.DIM))
	# right: flight strips
	var rp := UIStyle.panel(Vector2(420, 0), Color(0.03, 0.05, 0.08, 0.86))
	rp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rp.position = Vector2(-434, 14)
	rp.custom_minimum_size = Vector2(420, 560)
	root.add_child(rp)
	var rv := UIStyle.vbox(6)
	rp.add_child(rv)
	rv.add_child(UIStyle.caps("Flight strips", 12, UIStyle.ACCENT, 800, 3))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(400, 510)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	_strips = UIStyle.vbox(6)
	_strips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_strips)
	# bottom: radio
	var bp := UIStyle.panel(Vector2(640, 0), Color(0.02, 0.03, 0.05, 0.82))
	bp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bp.position = Vector2(14, -214)
	bp.custom_minimum_size = Vector2(640, 200)
	root.add_child(bp)
	_log = UIStyle.rich("", 13)
	_log.custom_minimum_size = Vector2(620, 186)
	bp.add_child(_log)


func _phase_text(item: Dictionary) -> String:
	var p := String(item.phase)
	match p:
		"final":
			return "Final %.1f km%s" % [float(item.get("dist", 0.0)) / 1000.0, " - CLEARED" if bool(item.get("clear_land", false)) else " - awaiting clearance"]
		"flare", "rollout":
			return "Landing"
		"go_around":
			return "Going around"
		"taxi_in":
			return "Taxiing to the gate"
		"pushback":
			return "Pushing back"
		"taxi_out":
			return "Taxiing out"
		"hold":
			return "Holding short - %s" % ("CLEARED" if bool(item.get("clear_takeoff", false)) else "ready for departure")
		"lineup":
			return "Lining up"
		"takeoff":
			return "Taking off"
		"climb":
			return "Climbing out"
	return p.capitalize()


func _refresh_ui() -> void:
	var left := maxf(shift_len - shift_t, 0.0)
	var best := int((Game.settings.get("tower_best", {}) as Dictionary).get(icao, 0))
	var ap := Airports.get_ap(icao)
	var w := WeatherModel.sample(float(ap.x), float(ap.z), WorldSim.clock)
	_status.text = "Score  %d   (best here %d)%s\nShift  %d:%02d left\nRunway %s · wind %03d° %d kt\nLanded %d   Departed %d\nGo-arounds %d   Collisions %d   MAYDAYs saved %d" % [score, best,
		"   PAUSED" if paused else "", int(left / 60.0), int(left) % 60, _runway_name(), int(w.get("wind_dir", 0.0)), int(w.get("wind_kt", 0.0)),
		stats.landed, stats.departed, stats.go_around, stats.collision, stats.saved]
	for c in _strips.get_children():
		c.queue_free()
	var list: Array = traffic.moving.filter(func(it): return String(it.phase) in ["final", "flare", "rollout", "go_around", "pushback", "taxi_out", "hold", "lineup", "takeoff", "climb", "taxi_in"])
	list.sort_custom(func(a, b): return _urgency(a) > _urgency(b))
	if list.is_empty():
		_strips.add_child(UIStyle.label("No traffic yet - it's coming.", 14, UIStyle.DIM))
	for item in list:
		var it: Dictionary = item
		var arr := String(it.phase) in ["final", "flare", "rollout", "go_around", "taxi_in"]
		var emerg := bool(it.get("emergency", false))
		var p := UIStyle.panel(Vector2(392, 0), Color(0.35, 0.08, 0.06, 0.9) if emerg else (Color(0.08, 0.16, 0.28, 0.9) if arr else Color(0.1, 0.2, 0.12, 0.9)))
		var v := UIStyle.vbox(4)
		p.add_child(v)
		var top := Button.new()
		top.flat = true
		top.alignment = HORIZONTAL_ALIGNMENT_LEFT
		top.text = "%s %s  ·  %s  ·  %s" % ["MAYDAY" if emerg else ("ARR" if arr else "DEP"), String(it.callsign), String(AircraftTypes.get_type(String(it.type)).short), _phase_text(it)]
		top.pressed.connect(func(): selected = it)
		v.add_child(top)
		var h := UIStyle.hbox(6)
		if String(it.phase) == "final":
			if not bool(it.get("clear_land", false)):
				h.add_child(UIStyle.button("Cleared to land", func(): clear_land(it), 150, UIStyle.GREEN))
			h.add_child(UIStyle.button("Go around", func(): go_around(it), 110, UIStyle.RED))
		elif String(it.phase) == "hold":
			if not bool(it.get("clear_takeoff", false)):
				h.add_child(UIStyle.button("Cleared for takeoff", func(): clear_takeoff(it), 170, UIStyle.GREEN))
			else:
				h.add_child(UIStyle.button("Hold position", func(): hold_position(it), 140, UIStyle.AMBER))
		if h.get_child_count() > 0:
			v.add_child(h)
		_strips.add_child(p)


func _urgency(it: Dictionary) -> float:
	var u := 0.0
	if bool(it.get("emergency", false)):
		u += 100.0
	match String(it.phase):
		"final":
			u += 50.0 - float(it.get("dist", 0.0)) / 1000.0
		"hold":
			u += 30.0
		"flare", "rollout", "takeoff", "lineup":
			u += 20.0
	return u


# ================================================================== end of shift
func _end_shift() -> void:
	if _ended:
		return
	_ended = true
	Engine.time_scale = 1.0
	var rating := "Trainee"
	for r in RATINGS:
		if score >= int(r[0]):
			rating = String(r[1])
			break
	if int(stats.collision) > 0:
		rating = "Suspended"
	var moves := int(stats.landed) + int(stats.departed)
	var short := String(Airports.get_ap(icao).get("short", icao))
	if int(stats.collision) > 0:
		News.publish("skyline", "breaking", "Runway collision at %s: controller error blamed" % short,
			"Two aircraft collided on the runway at %s after the tower cleared both onto it. Emergency services are at the scene." % short,
			["The airport has been closed while investigators examine the wreckage.", "The controller on duty has been suspended pending the investigation."],
			{"importance": 3, "place": short, "tags": ["incident", "atc"]})
	elif moves >= 15:
		News.publish("aeroweek", "people", "Record shift for the tower at %s" % short,
			"Controllers handled %d movements in one session without a single incident%s." % [moves, (" and saved %d emergency flights" % int(stats.saved)) if int(stats.saved) > 0 else ""],
			["\"It's like playing chess at 150 knots,\" one controller said."], {"importance": 1, "tags": ["feelgood", "atc"]})
	var bests: Dictionary = Game.settings.get("tower_best", {})
	var new_best := score > int(bests.get(icao, 0))
	if new_best:
		bests[icao] = score
		Game.settings["tower_best"] = bests
	if (hour >= 21.0 or hour < 5.0) and moves >= 5:
		Achievements.unlock("night_shift")
	if level == "rush" and int(stats.collision) == 0 and moves >= 10:
		Achievements.unlock("rush_hour")
	Game.save_settings()
	_result = UIStyle.panel(Vector2(460, 0), Color(0.03, 0.05, 0.08, 0.95))
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.position -= Vector2(230, 170)
	_layer.get_child(0).add_child(_result)
	var v := UIStyle.vbox(10)
	_result.add_child(v)
	v.add_child(UIStyle.caps("Shift complete", 12, UIStyle.ACCENT, 800, 3))
	v.add_child(UIStyle.title(rating, 30, UIStyle.RED if rating == "Suspended" else Color.WHITE))
	if new_best:
		v.add_child(UIStyle.label("New best score at %s!" % short, 16, UIStyle.GOLD, true))
	v.add_child(UIStyle.label("Score %d\nLandings %d · Departures %d\nGo-arounds %d · Collisions %d\nEmergencies saved %d" % [score, stats.landed, stats.departed, stats.go_around, stats.collision, stats.saved], 16, UIStyle.TEXT))
	var h := UIStyle.hbox(10)
	h.add_child(UIStyle.button("Another shift", func(): Game.goto("tower", _params()), 170, UIStyle.ACCENT))
	h.add_child(UIStyle.button("Main menu", func(): _exit(), 140))
	v.add_child(h)


func _exit() -> void:
	Engine.time_scale = 1.0
	paused = false
	WeatherModel.override_preset = ""
	Game.goto("menu")


func _exit_tree() -> void:
	Engine.time_scale = 1.0
