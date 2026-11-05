extends Node
## Renders every page of the phone during a real boarding, with forced no-shows and a late
## runner, and checks the final boarding call ends boarding.
## Usage: -- airline type dep arr outdir
var session: FlightSession
var phone: BoardingPhone
var out := "user://"
var t := 0.0
var step := 0
var asked := false
var result := ""
var done := false
var shots := []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[4] if a.size() > 4 else "user://"
	Game.settings.quality = "low"
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.start({"mode": "passenger", "type": a[1], "airline": a[0], "reg": "N123DL", "dep": a[2], "arr": a[3], "callsign": "Delta 1942",
		"flight_id": "PHONE-2", "start": "gate", "instant_boarding": false, "clock": U.date_to_clock(2027, 6, 14, 10.0)})
	var cp := session.people
	# force the story: two passengers never show, one of them is running late
	var n := 0
	for i in range(cp.pax.size() - 1, 0, -7):
		var p: Dictionary = cp.pax[i]
		if String(p.state) == "player":
			continue
		p.noshow = true
		p.late = n == 0
		n += 1
		if n >= 2:
			break
	# most of the cabin is already aboard
	var seated := int(cp.pax.size() * 0.7)
	for i in seated:
		var p: Dictionary = cp.pax[i]
		if not bool(p.get("noshow", false)):
			cp._seat_person(p)
	cp._board_next = seated
	cp.noshow_check.connect(func(names):
		asked = true
		print("PHONE noshow_check: ", names)
		_shot("final_call")
		await get_tree().create_timer(1.0).timeout
		cp.resolve_noshows(true))
	cp.noshow_result.connect(func(outcome, runner, names):
		result = outcome
		print("PHONE noshow_result: %s runner=%s offloaded=%s" % [outcome, runner, str(names)]))
	cp.boarding_done.connect(func():
		done = true
		print("PHONE boarding_done at t=%.0f, pax %d, offloaded %s" % [t, cp.pax.size(), str(cp.offloaded)]))
	phone = BoardingPhone.new()
	add_child(phone)
	phone.setup(session)
	phone.visible = true
	Engine.time_scale = 8.0


func _shot(name: String) -> void:
	phone._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out.path_join("phone_%s.png" % name)
	img.save_png(path)
	shots.append(path)
	print("PHONE shot ", path)


func _process(delta: float) -> void:
	t += delta
	if step == 0 and t > 6.0:
		step = 1
		phone.open("home")
		_shot("home")
	elif step == 1 and t > 8.0:
		step = 2
		phone.open("airline")
		_shot("airline_boarding")
	elif step == 2 and done:
		step = 3
		phone.open("airline")
		await get_tree().create_timer(0.5).timeout
		_shot("airline_done")
	elif step == 3 and t > 0.0:
		step = 4
		await get_tree().create_timer(1.0).timeout
		phone.open("tracker")
		await get_tree().create_timer(0.5).timeout
		_shot("tracker")
		phone.open("weather")
		await get_tree().create_timer(0.5).timeout
		_shot("weather")
		phone.open("feed")
		await get_tree().create_timer(0.5).timeout
		_shot("feed")
		phone.open("camera")
		await get_tree().create_timer(0.5).timeout
		_shot("camera")
		print("PHONE RESULT asked=%s result=%s done=%s shots=%d" % [asked, result, done, shots.size()])
		get_tree().quit()
	if t > 900.0:
		print("PHONE TIMEOUT asked=%s result=%s done=%s state=%s" % [asked, result, done, session.people.state])
		get_tree().quit()
