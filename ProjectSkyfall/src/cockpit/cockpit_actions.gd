class_name CockpitActions
extends RefCounted
## What every clickable flight-deck control does. dir: +1 click / scroll up, -1 right click /
## scroll down. Returns a short feedback string for the HUD ("" for silent controls).

static func apply(ac: Aircraft, session: Node, id: String, dir: int = 1) -> String:
	var sys := ac.sys
	var ap := ac.ap
	match id:
		"strobe", "beacon", "nav_lt", "land_lt", "taxi_lt", "wing_lt", "rwy_lt", "seatbelt", "nosmoking", "emer_lt":
			var key = {"strobe": "strobe", "beacon": "beacon", "nav_lt": "nav", "land_lt": "landing", "taxi_lt": "taxi",
				"wing_lt": "wing", "rwy_lt": "runway", "seatbelt": "seatbelt", "nosmoking": "nosmoking", "emer_lt": "emergency"}[id]
			sys.lights[key] = not bool(sys.lights.get(key, false))
			if key == "nav":
				sys.lights["logo"] = sys.lights[key]
			if key == "seatbelt" and session and session.has_method("on_seatbelt_sign"):
				session.call("on_seatbelt_sign", sys.lights[key])
			return "%s %s" % [_label(id), "ON" if sys.lights[key] else "OFF"]
		"wing_ai":
			sys.wing_anti_ice = not sys.wing_anti_ice
			return "Wing anti-ice " + ("ON" if sys.wing_anti_ice else "OFF")
		"eng_ai":
			sys.eng_anti_ice = not sys.eng_anti_ice
			return "Engine anti-ice " + ("ON" if sys.eng_anti_ice else "OFF")
		"probe_heat":
			sys.pitot_heat = not sys.pitot_heat
			return "Probe heat " + ("ON" if sys.pitot_heat else "OFF")
		"apu_master":
			sys.apu_on = not sys.apu_on
			return "APU master " + ("ON" if sys.apu_on else "OFF")
		"apu_start":
			if sys.apu_on and sys.apu_avail:
				return "APU starting"
			return "Set APU master first"
		"pack1", "pack2":
			var pi := 0 if id == "pack1" else 1
			sys.packs[pi] = not sys.packs[pi]
			return "Pack %d %s" % [pi + 1, "ON" if sys.packs[pi] else "OFF"]
		"xfeed":
			sys.crossfeed = not sys.crossfeed
			return "Crossfeed " + ("OPEN" if sys.crossfeed else "SHUT")
		"bat", "master":
			sys.battery = not sys.battery
			return "Battery " + ("ON" if sys.battery else "OFF")
		"ext_pwr":
			if not ac.fdm.on_ground:
				return "External power not available in flight"
			sys.ext_power = not sys.ext_power
			return "External power " + ("ON" if sys.ext_power else "OFF")
		"gen1", "gen2":
			var gi := 0 if id == "gen1" else 1
			if gi < sys.gen_fail.size():
				sys.gen_fail[gi] = not sys.gen_fail[gi]
				return "Generator %d %s" % [gi + 1, "OFF" if sys.gen_fail[gi] else "ON"]
		"fire1", "fire2", "agent1", "agent2":
			var ei := 0 if id in ["fire1", "agent1"] else 1
			if ei < sys.eng.size():
				var e: Dictionary = sys.eng[ei]
				if id.begins_with("fire"):
					e.handle = true
					e.cutoff = true
					return "Engine %d fire handle pulled - fuel and bleed shut off" % (ei + 1)
				if int(e.bottles) > 0:
					e.bottles = int(e.bottles) - 1
					if bool(e.handle) or e.cutoff:
						e.fire_t = -999.0
						if randf() < 0.85:
							e.fire = false
					return "Agent discharged on engine %d" % (ei + 1)
				return "No extinguisher agent left"
		"pax_oxy":
			sys.masks_deployed = true
			if session and session.has_method("deploy_masks"):
				session.call("deploy_masks")
			return "Passenger oxygen masks deployed"
		"crew_oxy", "crew_mask":
			sys.pilot_mask = not sys.pilot_mask
			return "Crew oxygen mask " + ("ON" if sys.pilot_mask else "OFF")
		"cabin_call":
			if session and session.has_method("call_cabin"):
				session.call("call_cabin")
			return ""
		"pa":
			if session and session.has_method("open_pa"):
				session.call("open_pa")
			return ""
		"evac":
			if session and session.has_method("command_evacuation"):
				session.call("command_evacuation")
			return "EVACUATE, EVACUATE"
		"dome":
			ac.set_meta("dome_light", not bool(ac.get_meta("dome_light", false)))
			return ""
		"flood":
			return ""
		# --------------------------------------------------- autopilot panel
		"ap":
			ac.toggle_autopilot()
			return "Autopilot " + ("ENGAGED" if ap.engaged else "DISCONNECTED")
		"athr":
			ac.toggle_autothrottle()
			return "Autothrust " + ("ON" if ap.at_engaged else "OFF")
		"spd_knob":
			if ap.use_mach:
				ap.mach_sel = clampf(ap.mach_sel + 0.01 * dir, 0.4, float(ac.spec.mmo))
				return "Mach .%02d" % int(ap.mach_sel * 100.0)
			ap.spd_sel = clampf(ap.spd_sel + 5.0 * dir, 60.0, float(ac.spec.vmo))
			return "Speed %d" % int(ap.spd_sel)
		"spd_mach":
			ap.use_mach = not ap.use_mach
			return "Speed in " + ("MACH" if ap.use_mach else "KNOTS")
		"hdg_knob":
			ap.hdg_sel = fposmod(ap.hdg_sel + 5.0 * dir, 360.0)
			return "Heading %03d" % int(ap.hdg_sel)
		"hdg_mode":
			ap.set_lat("HDG")
			return "HDG SEL"
		"lnav":
			if not ap.plan.is_empty():
				ap.set_lat("LNAV")
				return "LNAV"
			return "No route loaded"
		"loc":
			ap.arm_loc = true
			return "LOC armed"
		"appr":
			ap.arm_loc = true
			ap.arm_gs = true
			return "APPROACH armed"
		"alt_knob":
			ap.alt_sel = clampf(ap.alt_sel + 100.0 * U.FT * dir * (10.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0), 0.0, float(ac.spec.ceiling) * U.FT)
			return "Altitude %d ft" % int(round(ap.alt_sel / U.FT / 100.0) * 100.0)
		"flch":
			ap.set_vert("FLCH")
			ap.set_thr("CLB" if ap.alt_sel > ac.fdm.pos.y else "IDLE")
			return "LEVEL CHANGE"
		"alt_hold":
			ap.alt_sel = ac.fdm.pos.y
			ap.set_vert("ALT")
			ap.set_thr("SPD")
			return "ALT HOLD"
		"vs_mode":
			ap.set_vert("VS")
			ap.vs_sel = clampf(ac.fdm.vel.y, -15.0, 15.0)
			return "V/S"
		"vs_wheel":
			ap.vs_sel = clampf(ap.vs_sel + 100.0 * U.FPM * dir, -30.0, 25.0)
			if ap.vert_mode != "VS":
				ap.set_vert("VS")
			return "V/S %+d fpm" % int(round(ap.vs_sel / U.FPM / 100.0) * 100.0)
		"fd_l", "fd_r":
			ap.fd_on = not ap.fd_on
			return "Flight director " + ("ON" if ap.fd_on else "OFF")
		"master_warn", "master_caut":
			sys.ack_master()
			return ""
		"nd_range_l", "nd_range_r":
			if session and session.get("cockpit"):
				var cv: CockpitDisplays = session.get("cockpit").canvas
				var ranges := [5.0, 10.0, 20.0, 40.0, 80.0, 160.0, 320.0]
				var i := ranges.find(cv.nd_range)
				cv.nd_range = ranges[clampi(i + dir, 0, ranges.size() - 1)]
				return "ND range %d NM" % int(cv.nd_range)
		"baro_l", "baro_r":
			return "QNH %d" % int(round(float(ac.weather.get("qnh", 1013.0))))
		# --------------------------------------------------- main panel / pedestal
		"gear":
			ac.toggle_gear()
			return "Gear " + ("DOWN" if sys.gear_down_cmd else "UP")
		"autobrake_1", "autobrake_2", "autobrake_3":
			var lvl := int(id.substr(10))
			sys.autobrake = 0 if sys.autobrake == lvl else lvl
			return "Autobrake " + ["OFF", "LO", "MED", "MAX"][sys.autobrake]
		"thrust":
			ac.throttle_lever = clampf(ac.throttle_lever + 0.05 * dir, 0.0, 1.0)
			if ap.at_engaged and dir != 0:
				ap.at_engaged = false
			return "Thrust %d%%" % int(ac.throttle_lever * 100.0)
		"flaps":
			ac.set_flaps(clampi(sys.flap_lever + dir, 0, ac.spec.flaps.size() - 1))
			return "Flaps " + ac.flap_label()
		"speedbrake":
			ac.cycle_spoilers()
			return "Speed brake " + ("ARMED" if sys.ground_spoilers_armed and sys.spoiler_lever < 0.05 else ("%d%%" % int(sys.spoiler_lever * 100.0)))
		"park_brake":
			sys.parking_brake = not sys.parking_brake
			return "Parking brake " + ("SET" if sys.parking_brake else "RELEASED")
		"trim":
			sys.trim = clampf(sys.trim + 0.04 * dir, -1.0, 1.0)
			return "Trim %+.1f" % (sys.trim * 10.0)
		"eng_start":
			for i in sys.n_eng:
				if not sys.eng[i].running and not sys.eng[i].starting:
					if not sys.eng[i].cutoff:
						sys.eng[i].starting = true
						sys.eng[i].start_t = 0.0
						return "Starting engine %d" % (i + 1)
			return "Set an engine master switch ON to start"
		"mixture":
			sys.eng[0].cutoff = not sys.eng[0].cutoff
			return "Mixture " + ("IDLE CUT-OFF" if sys.eng[0].cutoff else "RICH")
		"avionics":
			return "Avionics master"
		"radio":
			if session and session.has_method("open_atc"):
				session.call("open_atc")
			return ""
		"xpdr":
			if session and session.has_method("open_xpdr"):
				session.call("open_xpdr")
			return "Squawk " + sys.squawk
		"checklist":
			if session and session.has_method("open_checklist"):
				session.call("open_checklist")
			return ""
		"cockpit_door":
			ac.set_meta("cockpit_door_open", not bool(ac.get_meta("cockpit_door_open", false)))
			return "Flight deck door " + ("OPEN" if ac.get_meta("cockpit_door_open") else "CLOSED")
		"mcdu":
			if session and session.has_method("open_fms"):
				session.call("open_fms")
			return ""
	if id.begins_with("eng_master_"):
		var idx := int(id.substr(11))
		if idx < sys.eng.size():
			var e2: Dictionary = sys.eng[idx]
			e2.cutoff = not e2.cutoff
			if not e2.cutoff and not e2.running:
				e2.starting = true
				e2.start_t = 0.0
				return "Engine %d master ON - starting" % (idx + 1)
			return "Engine %d master %s" % [idx + 1, "OFF" if e2.cutoff else "ON"]
	if id.begins_with("sd_"):
		if session and session.get("cockpit"):
			var cv2: CockpitDisplays = session.get("cockpit").canvas
			cv2.sd_page = id.substr(3) if cv2.sd_page != id.substr(3) else "AUTO"
			return "System page " + cv2.sd_page
	if id.begins_with("screen_"):
		return ""
	return _label(id)


static func _label(id: String) -> String:
	return id.replace("_", " ").to_upper()
