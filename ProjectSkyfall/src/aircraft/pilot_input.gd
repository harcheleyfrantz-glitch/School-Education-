class_name PilotInput
## Shared pilot input state written by on-screen touch controls and read by the aircraft.

static var touch_active := false
static var stick := Vector2.ZERO        # x roll (+right), y pitch (+nose up)
static var pedal := 0.0
static var throttle := -1.0             # absolute lever 0..1 from the touch slider (-1 = unused)
static var brake := 0.0
static var tilt := false
static var tilt_ref := Vector3.ZERO


static func reset() -> void:
	stick = Vector2.ZERO
	pedal = 0.0
	throttle = -1.0
	brake = 0.0
