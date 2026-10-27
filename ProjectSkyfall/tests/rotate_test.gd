extends Node
func _ready() -> void:
	var t: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "t172"
	var ac := Aircraft.new()
	add_child(ac)
	ac.setup(t, "T", "HFA", null, false)
	ac.player_controlled = false
	ac.set_load(2, 0.0, float(ac.spec.max_fuel) * 0.6)
	var dep := Airports.runway_end("SKWF", "21") if t == "t172" else Airports.runway_end("SKPC", "27R")
	var d := Vector3(sin(deg_to_rad(dep.hdg)), 0, -cos(deg_to_rad(dep.hdg)))
	ac.place_at(Vector3(dep.thr_x, dep.elev, dep.thr_z) + d * 50.0, dep.hdg, true)
	ac.sys.parking_brake = false
	ac.set_flaps(1)
	ac.throttle_lever = 1.0
	var dt := 1.0 / 60.0
	for i in 60 * 40:
		var ias := ac.fdm.ias / U.KT
		ac.in_pitch = 1.0 if ias > float(ac.spec.vr) else 0.0
		ac._physics_process(dt)
		if i % 30 == 0:
			var f := ac.fdm
			print("t=%4.1f ias=%5.1f pitch=%5.2f q=%5.2f elev=%5.2f alpha=%5.2f wow=%s loads=[%.0f %.0f %.0f] mass=%.0f thrust=%.0f agl=%.2f cl=%.2f" % [i * dt, ias, f.pitch_deg(), rad_to_deg(f.omega.x), f.elevator, rad_to_deg(f.alpha), str(f.wow), f.gear_load[0], f.gear_load[1], f.gear_load[2], f.mass, f.thrust[0], f.agl, f.cl_now])
	get_tree().quit()
