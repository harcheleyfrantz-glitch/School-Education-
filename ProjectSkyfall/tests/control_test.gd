extends Node
## Inner/outer loop response tests at altitude for each aircraft type.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var types := AircraftTypes.ORDER.duplicate()
	if args.size() > 0 and args[0] != "all":
		types = [args[0]]
	for t in types:
		_test(t)
	get_tree().quit()

func _make(type_id: String, alt: float, ias_kt: float) -> Aircraft:
	var ac := Aircraft.new()
	add_child(ac)
	ac.setup(type_id, "T", "SKF", null, false)
	ac.player_controlled = false
	ac.set_load(AircraftTypes.seat_count(type_id) * 8 / 10, 0.0, float(ac.spec.max_fuel) * 0.5)
	var tas := Atmo.ias_to_tas(ias_kt * U.KT, alt)
	ac.place_at(Vector3(0, alt, 0), 90.0, false, tas)
	# trim: find pitch where lift = weight
	var w := ac.total_mass() * U.G0
	var q := 0.5 * Atmo.density(alt) * tas * tas
	var cl := w / (q * float(ac.spec.wing_area))
	var a := (cl - float(ac.spec.cl0)) / float(ac.spec.cla)
	ac.fdm.set_attitude(90.0, rad_to_deg(a), 0.0)
	ac.fdm.vel = U.heading_to_dir(90.0) * tas
	ac.laws.reset_to_current(ac.fdm)
	ac.throttle_lever = 0.6
	ac.ap.at_engaged = true
	ac.ap.spd_sel = ias_kt
	ac.ap.out_throttle = 0.6
	ac.ap.alt_sel = alt
	ac.ap.hdg_sel = 90.0
	ac.ap.set_lat("HDG")
	ac.ap.set_vert("ALT")
	ac.ap.out_pitch = ac.fdm.pitch_deg()
	ac.ap.engage(true)
	return ac

func _run(ac: Aircraft, secs: float, cb: Callable = Callable()) -> Dictionary:
	var dt := 1.0 / 60.0
	var t := 0.0
	var st := {"max_g": 1.0, "min_g": 1.0, "max_pitch": -99.0, "min_pitch": 99.0, "max_bank": 0.0, "alt_dev": 0.0, "spd_dev": 0.0}
	while t < secs:
		if cb.is_valid():
			cb.call(t)
		ac._physics_process(dt)
		t += dt
		var n := ac.nav_state()
		st.max_g = maxf(st.max_g, ac.fdm.nz)
		st.min_g = minf(st.min_g, ac.fdm.nz)
		st.max_pitch = maxf(st.max_pitch, n.pitch)
		st.min_pitch = minf(st.min_pitch, n.pitch)
		st.max_bank = maxf(st.max_bank, absf(n.bank))
		if t > secs * 0.6:
			st.alt_dev = maxf(st.alt_dev, absf(n.alt - ac.ap.alt_sel))
			st.spd_dev = maxf(st.spd_dev, absf(n.true_ias_kt - ac.ap.target_ias(n)))
	return st

func _test(type_id: String) -> void:
	var spec := AircraftTypes.get_type(type_id)
	var cruise_alt := float(spec.cruise_alt) * U.FT * 0.5
	var ias := float(spec.cruise_ias) * 0.9
	# 1) altitude hold steady
	var ac := _make(type_id, cruise_alt, ias)
	var s1 := _run(ac, 60.0)
	print("%s ALT HOLD    g=[%.2f..%.2f] pitch=[%.1f..%.1f] altdev=%.0fm spddev=%.1fkt" % [type_id, s1.min_g, s1.max_g, s1.min_pitch, s1.max_pitch, s1.alt_dev, s1.spd_dev])
	# 2) altitude change +1000 m with VS 1500 fpm then hold
	ac.ap.alt_sel = cruise_alt + 600.0
	ac.ap.vs_sel = 7.6
	ac.ap.set_vert("VS")
	var s2 := _run(ac, 120.0)
	print("%s VS CLIMB    g=[%.2f..%.2f] pitch=[%.1f..%.1f] altdev=%.0fm spddev=%.1fkt alt=%.0f" % [type_id, s2.min_g, s2.max_g, s2.min_pitch, s2.max_pitch, s2.alt_dev, s2.spd_dev, ac.fdm.pos.y])
	# 3) FLCH descent 600 m
	ac.ap.alt_sel = cruise_alt
	ac.ap.set_vert("FLCH")
	ac.ap.set_thr("IDLE")
	var s3 := _run(ac, 150.0, func(t):
		if ac.ap.vert_mode == "ALT" and ac.ap.thr_mode != "SPD":
			ac.ap.set_thr("SPD"))
	print("%s FLCH DESC   g=[%.2f..%.2f] pitch=[%.1f..%.1f] altdev=%.0fm spddev=%.1fkt alt=%.0f mode=%s" % [type_id, s3.min_g, s3.max_g, s3.min_pitch, s3.max_pitch, s3.alt_dev, s3.spd_dev, ac.fdm.pos.y, ac.ap.vert_mode])
	# 4) heading change 90 degrees
	ac.ap.hdg_sel = 180.0
	var s4 := _run(ac, 90.0)
	print("%s HDG 90     g=[%.2f..%.2f] bank<=%.1f hdg=%.1f altdev=%.0fm" % [type_id, s4.min_g, s4.max_g, s4.max_bank, ac.fdm.heading_deg(), s4.alt_dev])
	# 5) manual assisted pitch step: pilot holds full back stick for 2 s then releases
	ac.ap.engage(false)
	ac.laws.reset_to_current(ac.fdm)
	var s5 := _run(ac, 20.0, func(t):
		ac.in_pitch = 1.0 if t < 2.0 else 0.0
		ac.in_roll = 0.0)
	print("%s STICK STEP g=[%.2f..%.2f] pitch=[%.1f..%.1f]" % [type_id, s5.min_g, s5.max_g, s5.min_pitch, s5.max_pitch])
	ac.queue_free()
