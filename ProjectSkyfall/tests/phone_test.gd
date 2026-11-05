extends Node
## The airline boarding app: live counts while passengers board. Usage: -- airline type dep arr
var session: FlightSession
var phone: BoardingPhone
var t := 0.0
var next := 5.0
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.settings.quality = "low"
	session = FlightSession.new()
	add_child(session)
	session.set_meta("test_fast", true)
	session.start({"mode": "passenger", "type": a[1], "airline": a[0], "reg": "N123DL", "dep": a[2], "arr": a[3], "callsign": "Delta 1942",
		"flight_id": "PHONE-1", "start": "gate", "instant_boarding": false, "clock": U.date_to_clock(2027, 6, 14, 10.0)})
	phone = BoardingPhone.new()
	add_child(phone)
	phone.setup(session)
	phone.visible = true
	Engine.time_scale = 4.0
func _process(delta: float) -> void:
	t += delta
	if t >= next:
		next += 25.0
		phone._refresh()
		var missing := phone._list.get_child_count()
		print("PHONE t=%3.0fs  %s | %s | %s | %s | list rows %d" % [t, phone._title.text, phone._status.text, phone._count.text, phone._classes.text, missing])
	if t > 130.0:
		get_tree().quit()
