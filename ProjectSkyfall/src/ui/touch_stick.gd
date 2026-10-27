extends Control
## On-screen flight stick for touch screens: drag inside the ring; springs back to centre.
## Writes PilotInput.stick (x roll right, y pitch up = pull back).

var _touch := -1
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var r := size.x * 0.5
	var c := size * 0.5
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch < 0:
			_touch = t.index
			_set_from(t.position - c, r)
		elif not t.pressed and t.index == _touch:
			_touch = -1
			_set_from(Vector2.ZERO, r)
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			_set_from(d.position - c, r)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_touch = 0 if mb.pressed else -1
			_set_from((mb.position - c) if mb.pressed else Vector2.ZERO, r)
			accept_event()
	elif event is InputEventMouseMotion and _touch == 0:
		_set_from((event as InputEventMouseMotion).position - c, r)
		accept_event()


func _set_from(v: Vector2, r: float) -> void:
	_knob = v.limit_length(r * 0.8)
	var n := _knob / (r * 0.8)
	# gentle centre: a little expo for fine control
	PilotInput.stick = Vector2(signf(n.x) * pow(absf(n.x), 1.4), signf(n.y) * pow(absf(n.y), 1.4))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.x * 0.5
	draw_circle(c, r, Color(0.05, 0.08, 0.12, 0.45))
	draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(0.29, 0.74, 1.0, 0.5), 2.0, true)
	draw_line(c - Vector2(r * 0.8, 0), c + Vector2(r * 0.8, 0), Color(1, 1, 1, 0.08), 1.0)
	draw_line(c - Vector2(0, r * 0.8), c + Vector2(0, r * 0.8), Color(1, 1, 1, 0.08), 1.0)
	draw_circle(c + _knob, r * 0.28, Color(0.29, 0.74, 1.0, 0.75))
	draw_circle(c + _knob, r * 0.18, Color(0.85, 0.95, 1.0, 0.9))
