extends Node
func _ready() -> void:
	var t := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "s320"
	var ac := Aircraft.new()
	add_child(ac)
	ac.setup(t, "T", "SKF", null, false)
	ac.player_controlled = false
	ac.set_load(AircraftTypes.seat_count(t) * 8 / 10, 0.0, float(ac.spec.max_fuel) * 0.5)
	var alt := 5000.0
	var ias := 240.0 if t != "t172" else 100.0
	var tas := Atmo.ias_to_tas(ias * U.KT, alt)
	ac.place_at(Vector3(0, alt, 0), 90.0, false, tas)
	var w := ac.total_mass() * U.G0
	var q := 0.5 * Atmo.density(alt) * tas * tas
	var cl := w / (q * float(ac.spec.wing_area))
	var a := (cl - float(ac.spec.cl0)) / float(ac.spec.cla)
	print("trim alpha=%.2f deg cl=%.3f mass=%.0f" % [rad_to_deg(a), cl, ac.total_mass()])
	ac.fdm.set_attitude(90.0, rad_to_deg(a), 0.0)
	ac.fdm.vel = U.heading_to_dir(90.0) * tas
	ac.laws.reset_to_current(ac.fdm)
	ac.throttle_lever = 0.55
	ac.ap.set_vert("HOLD")
	ac.ap.set_lat("ROLL")
	ac.ap.out_pitch = rad_to_deg(a) + 1.0
	ac.ap.engage(true)
	var dt := 1.0 / 60.0
	for i in 60 * 40:
		ac._physics_process(dt)
		if i % 30 == 0:
			var n := ac.nav_state()
			print("t=%5.1f pitch=%6.2f tgt=%6.2f elev=%6.3f q=%6.2f alpha=%5.2f nz=%5.2f vs=%6.0f ias=%5.1f trim_i=%6.3f" % [i * dt, n.pitch, ac.laws.target_pitch, ac.fdm.elevator, rad_to_deg(ac.fdm.omega.x), n.alpha, ac.fdm.nz, n.vs / U.FPM, n.true_ias_kt, ac.laws._pitch_i])
	get_tree().quit()
