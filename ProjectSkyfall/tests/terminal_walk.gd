extends Node
## End-to-end walk from the kerb to the seat: a passenger trip with "start": "terminal" where
## a simple bot steers the walker to check-in, through security, to the gate, down the jet
## bridge, aboard and into the assigned seat, taking screenshots on the way.
## Usage: -- <out_dir> [icao] [type] [hour]

var out_dir := "/tmp"
var s: FlightSession
var stage := "checkin"
var target := Vector3.ZERO
var _stuck := 0.0
var _last := Vector3.ZERO
var _turn := 0.0
var _t := 0.0
var _stage_t := 0.0
var _shots := {}
var _done := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "/tmp"
	var icao := a[1] if a.size() > 1 else "SKPC"
	var type_id := a[2] if a.size() > 2 else "s320"
	var hour := float(a[3]) if a.size() > 3 else 17.0
	Game.settings.quality = "medium"
	Game.settings.tts = false
	Game.new_character({"first": "Maya", "last": "Okafor", "name": "Maya Okafor", "gender": "f", "age": 31, "path": "regional_fo"})
	s = FlightSession.new()
	add_child(s)
	s.toast.connect(func(tx, _k): print("  [toast] ", tx))
	s.start({"mode": "passenger", "type": type_id, "airline": "SKF", "reg": "CR-WLK", "dep": icao, "arr": "SKRV" if icao != "SKRV" else "SKPC",
		"callsign": "Skyfall 451", "flight_id": "WALK-%s" % icao, "start": "terminal", "clock": U.date_to_clock(2027, 6, 14, hour)})
	await s.view.warm_up(10.0)
	var hud := s.get_node_or_null("HUD")
	if hud:
		hud.visible = OS.get_environment("HUD") != ""
	Engine.time_scale = 3.0
	print("walker at ", s.walker.where, " gate ", s.walker.gate_name, " seat ", s.pax_seat, " bridge ", s.view.airports.get_view(s.dep_icao).bridge_state(s.stand))
	_shot("walk_0_kerb")
	_set_stage("checkin")


func _set_stage(st: String) -> void:
	stage = st
	_stage_t = 0.0
	var w := s.walker
	match st:
		"checkin":
			target = _nearest_spot("checkin")
		"security":
			target = _nearest_spot("security")
		"gate":
			for sp in w.ti.spots:
				if String(sp.kind) == "gate_door" and String(sp.get("gate", "")) == w.gate_name:
					target = sp.p
		"bridge":
			target = w.bridge_pts[w.bridge_pts.size() - 1]
		"cabin":
			var me: Dictionary = s.people.person_at_seat(s.pax_seat) if s.people else {}
			var lay: Dictionary = w.lay
			if me.is_empty():
				stage = "done"
				return
			var aisle := 0.0
			var ax: Array = lay.get("aisles", [0.0])
			if not ax.is_empty():
				aisle = float(ax[0]) if typeof(ax[0]) != TYPE_DICTIONARY else float(ax[0].get("x", 0.0))
			target = Vector3(aisle, float(lay.floor_y), float(me.seat.pos.z))
	print("%6.1fs STAGE %s -> target %s (walker %s at %s)" % [_t, st, target, w.where, w.pos])


func _nearest_spot(kind: String) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for sp in s.walker.ti.spots:
		if String(sp.kind) == kind:
			var d := (sp.p as Vector3).distance_to(s.walker.pos)
			if d < bd:
				bd = d
				best = sp.p
	return best


func _process(delta: float) -> void:
	if s == null or s.walker == null or _done:
		return
	_t += delta
	_stage_t += delta
	var w := s.walker
	if _t > 1500.0 or _stage_t > 420.0:
		print("GAVE UP at stage %s, walker %s at %s" % [stage, w.where, w.pos])
		if w.ti:
			for o in w.ti.obstacles:
				var tq := Vector2(target.x, target.z)
				if o.has("h") and not o.has("door"):
					var dd: Vector2 = (tq - (o.c as Vector2)).abs() - (o.h as Vector2)
					if dd.x < 0.3 and dd.y < 0.3:
						print("   blocked by rect c=%s h=%s" % [o.c, o.h])
				elif o.has("r") and tq.distance_to(o.c) < float(o.r) + 0.3:
					print("   blocked by circle c=%s r=%s" % [o.c, o.r])
			print("   depth %.1f length %.1f hub %s land_s %s sec %s" % [w.ti.depth, w.ti.length, w.ti.hub, w.ti.land_s, w.ti.sec])
			var row := ""
			for dz in range(-8, 9):
				row = ""
				for dx in range(-8, 9):
					var q := Vector2(target.x + dx * 0.5, target.z + dz * 0.5)
					row += ("T" if dx == 0 and dz == 0 else ("." if w.ti.walkable(q, 0.3) else "#"))
				print("   ", row)
		_finish()
		return
	if stage == "done":
		w.move_input = Vector2.ZERO
		if s.phase != "preflight" or _stage_t > 40.0:
			print("%6.1fs phase %s, on_foot %s, camera %s" % [_t, s.phase, s.on_foot, s.rig.mode])
			_shot("walk_9_seated")
			_finish()
		return
	var to := target - w.pos
	to.y = 0.0
	var reach := 3.0 if stage in ["checkin", "security", "gate"] else (1.2 if stage == "bridge" else 0.5)
	if to.length() < reach:
		w.move_input = Vector2.ZERO
		_arrive()
		return
	var yaw := atan2(-to.x, -to.z)
	if _turn > 0.0:
		_turn -= delta
		yaw += 1.2
	w.yaw = lerp_angle(w.yaw, yaw, clampf(delta * 8.0, 0.0, 1.0))
	w.move_input = Vector2(0, 1)
	if w.pos.distance_to(_last) < 0.005:
		_stuck += delta
		if _stuck > 0.6:
			_turn = 0.7
			_stuck = 0.0
	else:
		_stuck = 0.0
	_last = w.pos
	if stage == "gate" and not _shots.has("concourse") and _stage_t > 6.0:
		_shot("walk_3_concourse")
	if stage == "bridge" and not _shots.has("bridge") and _stage_t > 2.5:
		_shot("walk_5_bridge")


func _arrive() -> void:
	var w := s.walker
	match stage:
		"checkin":
			_shot("walk_1_checkin")
			w.interact()
			_set_stage("security")
		"security":
			_shot("walk_2_security")
			w.interact()
			_set_stage("gate")
		"gate":
			if not _shots.has("gate"):
				_shot("walk_4_gate")
			var av := s.view.airports.get_view(s.dep_icao)
			if av.bridge_state(s.stand) != "docked" and av.bridge_state(s.stand) != "none":
				return
			w.interact()
			if w.where == "bridge":
				_set_stage("bridge")
			elif w.where == "apron":
				print("no bridge: walked out to the stand")
				_set_stage_done()
		"bridge":
			_shot("walk_6_door")
			w.interact()
			if w.where == "cabin":
				_set_stage("cabin")
		"cabin":
			_shot("walk_7_aisle")
			w.interact()
			print("seated: %s" % w.seated)
			_set_stage_done()


func _set_stage_done() -> void:
	stage = "done"
	_stage_t = 0.0


func _shot(n: String) -> void:
	_shots[n.get_slice("_", 2)] = true
	if DisplayServer.get_name() == "headless":
		print("%6.1fs (headless) at %s %s" % [_t, s.walker.where, s.walker.pos])
		return
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("%6.1fs shot %s" % [_t, n])


func _finish() -> void:
	_done = true
	get_tree().quit()
