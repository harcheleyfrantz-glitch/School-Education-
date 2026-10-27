class_name AircraftTypes
## Aircraft type database. Geometry in metres, masses in kg, speeds in knots, altitudes in feet.
## Aerodynamic derivatives are per radian. Elevator/aileron/rudder derivatives use the
## convention "positive input = nose up / roll right / nose right".

const ORDER := ["t172", "tp72", "rj90", "s320", "w350", "bj6", "f4"]

const TYPES := {
	"t172": {
		"name": "Aerolite T-172", "short": "T172", "maker": "Aerolite", "category": "trainer",
		"role": "Single-engine training aircraft",
		"blurb": "A forgiving high-wing four-seater. Every career begins with stalls, circuits and crosswind practice in one of these.",
		"length": 8.3, "span": 11.0, "height": 2.7, "fuse_w": 1.12, "fuse_h": 1.45,
		"wing_area": 16.2, "mac": 1.49, "wing_pos": "high", "sweep": 0.0, "dihedral": 1.5, "taper": 0.68,
		"winglet": "none", "tail": "conventional", "nose": "ga", "cg_frac": 0.33,
		"engine_type": "piston", "engine_count": 1, "engine_mount": "nose",
		"power_kw": 134.0, "static_thrust": 2350.0, "prop_diam": 1.9, "max_rpm": 2700.0, "spool": 2.6,
		"tsfc": 0.0, "bsfc": 7.8e-8,
		"empty_mass": 767.0, "mtow": 1111.0, "max_fuel": 145.0, "max_payload": 320.0,
		"cl0": 0.30, "cla": 4.8, "clmax": 1.55, "cd0": 0.031, "oswald": 0.74,
		"cm0": 0.05, "cma": -1.0, "cmq": -14.0, "cmde": 1.25, "max_elev": 24.0,
		"clb": -0.09, "clp": -0.48, "clr": 0.10, "clda": 0.13, "max_ail": 18.0,
		"cnb": 0.07, "cnr": -0.11, "cnp": -0.03, "cndr": 0.075, "cnda": -0.006, "max_rud": 20.0,
		"cyb": -0.31, "cydr": 0.18, "inertia_k": [0.21, 0.30, 0.36],
		"flaps": [
			{"label": "0", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 160},
			{"label": "10", "deg": 10.0, "dcl": 0.22, "dclmax": 0.22, "dcd": 0.008, "dcm": -0.02, "vfe": 110},
			{"label": "20", "deg": 20.0, "dcl": 0.42, "dclmax": 0.40, "dcd": 0.025, "dcm": -0.04, "vfe": 85},
			{"label": "30", "deg": 30.0, "dcl": 0.58, "dclmax": 0.52, "dcd": 0.05, "dcm": -0.06, "vfe": 85},
		],
		"gear_retract": false, "gear_cd": 0.012, "spoilers": false, "spoiler_cd": 0.0, "reverser": false,
		"gear_height": 1.35, "nose_gear_x": -1.55, "main_gear_x": 0.55, "gear_track": 2.5,
		"vs0": 48, "vs1": 53, "vr": 55, "v2": 65, "vref": 65, "vapp": 70, "vmo": 163, "mmo": 0.0,
		"climb_ias": 75, "cruise_ias": 110, "cruise_tas": 122, "descent_ias": 100,
		"cruise_alt": 6500, "ceiling": 14000, "climb_fpm": 700,
		"autopilot": true, "fbw": false, "ils": true, "autoland": false,
		"pilots": 1, "fa": 0, "cabin": [{"cls": "ga", "rows": 2, "layout": "1-1", "pitch": 0.95, "seat_w": 0.5}],
		"doors": [0.36], "cockpit": "ga", "sound": "piston", "cargo_door": false, "hump": false,
		"hourly_cost": 180, "rating_hours": 0.0, "range_nm": 640, "tailstrike": 14.0,
	},
	"tp72": {
		"name": "Kestrel TP-72", "short": "TP72", "maker": "Kestrel Aerospace", "category": "turboprop",
		"role": "Twin-engine regional turboprop",
		"blurb": "The backbone of island hopping and short regional sectors. Rugged, efficient and happy on short runways.",
		"length": 27.2, "span": 27.1, "height": 7.7, "fuse_w": 2.87, "fuse_h": 2.95,
		"wing_area": 61.0, "mac": 2.3, "wing_pos": "high", "sweep": 3.0, "dihedral": 2.0, "taper": 0.55,
		"winglet": "none", "tail": "t_tail", "nose": "regional", "cg_frac": 0.46,
		"engine_type": "turboprop", "engine_count": 2, "engine_mount": "wing_prop",
		"power_kw": 2050.0, "static_thrust": 34000.0, "prop_diam": 3.93, "max_rpm": 1200.0, "spool": 3.5,
		"tsfc": 0.0, "bsfc": 7.9e-8,
		"empty_mass": 13500.0, "mtow": 23000.0, "max_fuel": 5000.0, "max_payload": 7500.0,
		"cl0": 0.32, "cla": 5.2, "clmax": 1.55, "cd0": 0.027, "oswald": 0.80,
		"cm0": 0.03, "cma": -1.2, "cmq": -24.0, "cmde": 1.45, "max_elev": 22.0,
		"clb": -0.10, "clp": -0.50, "clr": 0.12, "clda": 0.12, "max_ail": 20.0,
		"cnb": 0.11, "cnr": -0.17, "cnp": -0.02, "cndr": 0.085, "cnda": -0.006, "max_rud": 25.0,
		"cyb": -0.6, "cydr": 0.22, "inertia_k": [0.27, 0.34, 0.45],
		"flaps": [
			{"label": "0", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 250},
			{"label": "15", "deg": 15.0, "dcl": 0.38, "dclmax": 0.45, "dcd": 0.018, "dcm": -0.05, "vfe": 185},
			{"label": "30", "deg": 30.0, "dcl": 0.72, "dclmax": 0.82, "dcd": 0.055, "dcm": -0.09, "vfe": 150},
		],
		"gear_retract": true, "gear_cd": 0.02, "spoilers": true, "spoiler_cd": 0.03, "reverser": true,
		"gear_height": 2.1, "nose_gear_x": -10.2, "main_gear_x": 0.9, "gear_track": 4.1,
		"vs0": 95, "vs1": 110, "vr": 112, "v2": 118, "vref": 115, "vapp": 120, "vmo": 250, "mmo": 0.55,
		"climb_ias": 170, "cruise_ias": 210, "cruise_tas": 275, "descent_ias": 230,
		"cruise_alt": 17000, "ceiling": 25000, "climb_fpm": 1600,
		"autopilot": true, "fbw": false, "ils": true, "autoland": false,
		"pilots": 2, "fa": 2, "cabin": [{"cls": "economy", "rows": 18, "layout": "2-2", "pitch": 0.79, "seat_w": 0.46}],
		"doors": [0.06, 0.9], "cockpit": "turboprop", "sound": "turboprop", "cargo_door": true, "hump": false,
		"hourly_cost": 2400, "rating_hours": 60.0, "range_nm": 820, "tailstrike": 10.0,
	},
	"rj90": {
		"name": "Meridian RJ-90", "short": "RJ90", "maker": "Meridian", "category": "regional",
		"role": "Regional passenger jet",
		"blurb": "A nimble 88-seat jet connecting secondary cities to the hubs. Fast, quiet and a stepping stone to mainline flying.",
		"length": 31.7, "span": 26.0, "height": 9.8, "fuse_w": 3.0, "fuse_h": 3.35,
		"wing_area": 72.7, "mac": 3.2, "wing_pos": "low", "sweep": 24.0, "dihedral": 5.0, "taper": 0.3,
		"winglet": "blended", "tail": "conventional", "nose": "airliner", "cg_frac": 0.47,
		"engine_type": "turbofan", "engine_count": 2, "engine_mount": "wing",
		"static_thrust": 63000.0, "fan_diam": 1.45, "bypass": 5.0, "spool": 4.5, "tsfc": 1.35e-5,
		"empty_mass": 21800.0, "mtow": 38800.0, "max_fuel": 9300.0, "max_payload": 10000.0,
		"cl0": 0.24, "cla": 5.3, "clmax": 1.45, "cd0": 0.022, "oswald": 0.79,
		"cm0": 0.02, "cma": -1.15, "cmq": -24.0, "cmde": 1.4, "max_elev": 24.0,
		"clb": -0.12, "clp": -0.48, "clr": 0.13, "clda": 0.11, "max_ail": 24.0,
		"cnb": 0.13, "cnr": -0.19, "cnp": -0.02, "cndr": 0.08, "cnda": -0.004, "max_rud": 25.0,
		"cyb": -0.7, "cydr": 0.2, "inertia_k": [0.27, 0.36, 0.46],
		"flaps": [
			{"label": "UP", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 320},
			{"label": "1", "deg": 7.0, "dcl": 0.2, "dclmax": 0.35, "dcd": 0.008, "dcm": -0.02, "vfe": 230},
			{"label": "2", "deg": 10.0, "dcl": 0.32, "dclmax": 0.52, "dcd": 0.014, "dcm": -0.03, "vfe": 215},
			{"label": "3", "deg": 20.0, "dcl": 0.55, "dclmax": 0.78, "dcd": 0.03, "dcm": -0.05, "vfe": 200},
			{"label": "5", "deg": 32.0, "dcl": 0.85, "dclmax": 1.12, "dcd": 0.065, "dcm": -0.08, "vfe": 180},
		],
		"gear_retract": true, "gear_cd": 0.022, "spoilers": true, "spoiler_cd": 0.04, "reverser": true,
		"gear_height": 2.45, "nose_gear_x": -12.0, "main_gear_x": 1.1, "gear_track": 5.2,
		"vs0": 105, "vs1": 125, "vr": 135, "v2": 142, "vref": 128, "vapp": 135, "vmo": 320, "mmo": 0.82,
		"climb_ias": 280, "cruise_ias": 270, "cruise_tas": 450, "descent_ias": 290,
		"cruise_alt": 35000, "ceiling": 41000, "climb_fpm": 2400,
		"autopilot": true, "fbw": false, "ils": true, "autoland": true,
		"pilots": 2, "fa": 2,
		"cabin": [
			{"cls": "business", "rows": 3, "layout": "1-2", "pitch": 0.97, "seat_w": 0.56},
			{"cls": "economy", "rows": 19, "layout": "2-2", "pitch": 0.79, "seat_w": 0.47},
		],
		"doors": [0.07, 0.92], "cockpit": "boeing", "sound": "fan_small", "cargo_door": true, "hump": false,
		"hourly_cost": 4200, "rating_hours": 250.0, "range_nm": 2000, "tailstrike": 11.0,
	},
	"s320": {
		"name": "Stratos 320", "short": "S320", "maker": "Stratos Industries", "category": "narrowbody",
		"role": "Narrow-body commercial airliner",
		"blurb": "The world's workhorse: 174 seats, fly-by-wire, and the aircraft most mainline captains know best.",
		"length": 37.6, "span": 35.8, "height": 11.8, "fuse_w": 3.95, "fuse_h": 4.14,
		"wing_area": 122.6, "mac": 4.2, "wing_pos": "low", "sweep": 25.0, "dihedral": 5.5, "taper": 0.24,
		"winglet": "sharklet", "tail": "conventional", "nose": "airliner", "cg_frac": 0.47,
		"engine_type": "turbofan", "engine_count": 2, "engine_mount": "wing",
		"static_thrust": 120000.0, "fan_diam": 1.98, "bypass": 6.0, "spool": 5.5, "tsfc": 1.25e-5,
		"empty_mass": 42600.0, "mtow": 78000.0, "max_fuel": 18700.0, "max_payload": 19000.0,
		"cl0": 0.25, "cla": 5.4, "clmax": 1.5, "cd0": 0.021, "oswald": 0.80,
		"cm0": 0.02, "cma": -1.2, "cmq": -28.0, "cmde": 1.4, "max_elev": 25.0,
		"clb": -0.11, "clp": -0.5, "clr": 0.13, "clda": 0.10, "max_ail": 25.0,
		"cnb": 0.12, "cnr": -0.20, "cnp": -0.02, "cndr": 0.08, "cnda": -0.004, "max_rud": 25.0,
		"cyb": -0.8, "cydr": 0.2, "inertia_k": [0.27, 0.38, 0.46],
		"flaps": [
			{"label": "0", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 350},
			{"label": "1", "deg": 0.0, "dcl": 0.12, "dclmax": 0.35, "dcd": 0.006, "dcm": -0.01, "vfe": 230, "slats_only": true},
			{"label": "1+F", "deg": 10.0, "dcl": 0.3, "dclmax": 0.55, "dcd": 0.012, "dcm": -0.03, "vfe": 215},
			{"label": "2", "deg": 15.0, "dcl": 0.48, "dclmax": 0.8, "dcd": 0.025, "dcm": -0.05, "vfe": 200},
			{"label": "3", "deg": 20.0, "dcl": 0.68, "dclmax": 1.05, "dcd": 0.04, "dcm": -0.07, "vfe": 185},
			{"label": "FULL", "deg": 35.0, "dcl": 0.98, "dclmax": 1.37, "dcd": 0.075, "dcm": -0.1, "vfe": 177},
		],
		"gear_retract": true, "gear_cd": 0.022, "spoilers": true, "spoiler_cd": 0.045, "reverser": true,
		"gear_height": 3.15, "nose_gear_x": -12.6, "main_gear_x": 1.4, "gear_track": 7.6,
		"vs0": 105, "vs1": 140, "vr": 145, "v2": 152, "vref": 133, "vapp": 138, "vmo": 350, "mmo": 0.82,
		"climb_ias": 290, "cruise_ias": 270, "cruise_tas": 450, "descent_ias": 300,
		"cruise_alt": 36000, "ceiling": 39800, "climb_fpm": 2500,
		"autopilot": true, "fbw": true, "ils": true, "autoland": true,
		"pilots": 2, "fa": 4,
		"cabin": [
			{"cls": "business", "rows": 3, "layout": "2-2", "pitch": 0.96, "seat_w": 0.56},
			{"cls": "economy", "rows": 27, "layout": "3-3", "pitch": 0.79, "seat_w": 0.46},
		],
		"doors": [0.07, 0.92], "overwing": [0.43, 0.48], "cockpit": "airbus", "sound": "fan_med", "cargo_door": true, "hump": false,
		"hourly_cost": 7200, "rating_hours": 900.0, "range_nm": 3300, "tailstrike": 11.5,
	},
	"w350": {
		"name": "Atlas W-350", "short": "W350", "maker": "Atlas Aeronautics", "category": "widebody",
		"role": "Wide-body long-haul airliner",
		"blurb": "A carbon-fibre twin-aisle flagship for the long sea crossings. 296 passengers, 10 cabin crew, and a lot of responsibility.",
		"length": 62.8, "span": 60.1, "height": 17.0, "fuse_w": 5.77, "fuse_h": 5.96,
		"wing_area": 360.0, "mac": 7.2, "wing_pos": "low", "sweep": 31.0, "dihedral": 6.0, "taper": 0.2,
		"winglet": "raked", "tail": "conventional", "nose": "airliner_round", "cg_frac": 0.47,
		"engine_type": "turbofan", "engine_count": 2, "engine_mount": "wing",
		"static_thrust": 330000.0, "fan_diam": 2.95, "bypass": 10.0, "spool": 7.0, "tsfc": 1.12e-5,
		"empty_mass": 128000.0, "mtow": 254000.0, "max_fuel": 101000.0, "max_payload": 53000.0,
		"cl0": 0.24, "cla": 5.6, "clmax": 1.45, "cd0": 0.019, "oswald": 0.82,
		"cm0": 0.02, "cma": -1.25, "cmq": -32.0, "cmde": 1.35, "max_elev": 25.0,
		"clb": -0.12, "clp": -0.5, "clr": 0.13, "clda": 0.09, "max_ail": 25.0,
		"cnb": 0.13, "cnr": -0.21, "cnp": -0.02, "cndr": 0.075, "cnda": -0.004, "max_rud": 25.0,
		"cyb": -0.85, "cydr": 0.2, "inertia_k": [0.28, 0.39, 0.47],
		"flaps": [
			{"label": "UP", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 340},
			{"label": "1", "deg": 0.0, "dcl": 0.12, "dclmax": 0.35, "dcd": 0.005, "dcm": -0.01, "vfe": 255, "slats_only": true},
			{"label": "5", "deg": 5.0, "dcl": 0.28, "dclmax": 0.55, "dcd": 0.01, "dcm": -0.03, "vfe": 235},
			{"label": "15", "deg": 15.0, "dcl": 0.5, "dclmax": 0.82, "dcd": 0.024, "dcm": -0.05, "vfe": 215},
			{"label": "20", "deg": 20.0, "dcl": 0.66, "dclmax": 1.02, "dcd": 0.035, "dcm": -0.07, "vfe": 200},
			{"label": "30", "deg": 30.0, "dcl": 0.92, "dclmax": 1.32, "dcd": 0.068, "dcm": -0.1, "vfe": 180},
		],
		"gear_retract": true, "gear_cd": 0.02, "spoilers": true, "spoiler_cd": 0.045, "reverser": true,
		"gear_height": 4.6, "nose_gear_x": -23.0, "main_gear_x": 2.4, "gear_track": 9.8,
		"vs0": 115, "vs1": 150, "vr": 158, "v2": 166, "vref": 142, "vapp": 147, "vmo": 340, "mmo": 0.90,
		"climb_ias": 300, "cruise_ias": 275, "cruise_tas": 488, "descent_ias": 300,
		"cruise_alt": 39000, "ceiling": 43000, "climb_fpm": 2200,
		"autopilot": true, "fbw": true, "ils": true, "autoland": true,
		"pilots": 2, "fa": 10,
		"cabin": [
			{"cls": "business", "rows": 7, "layout": "1-2-1", "pitch": 1.15, "seat_w": 0.62},
			{"cls": "premium", "rows": 5, "layout": "2-3-2", "pitch": 0.97, "seat_w": 0.5},
			{"cls": "economy", "rows": 25, "layout": "3-3-3", "pitch": 0.81, "seat_w": 0.45},
		],
		"doors": [0.06, 0.3, 0.62, 0.9], "cockpit": "boeing", "sound": "fan_large", "cargo_door": true, "hump": false,
		"hourly_cost": 16500, "rating_hours": 3000.0, "range_nm": 7600, "tailstrike": 9.5,
	},
	"bj6": {
		"name": "Vantage BJ-6", "short": "BJ6", "maker": "Vantage Aviation", "category": "bizjet",
		"role": "Private long-range business jet",
		"blurb": "Leather, walnut and Mach 0.9. Your passengers are executives, celebrities and the occasional head of state.",
		"length": 30.4, "span": 30.4, "height": 7.8, "fuse_w": 2.6, "fuse_h": 2.75,
		"wing_area": 119.0, "mac": 4.6, "wing_pos": "low", "sweep": 36.0, "dihedral": 4.5, "taper": 0.3,
		"winglet": "blended", "tail": "t_tail", "nose": "pointy", "cg_frac": 0.55,
		"engine_type": "turbofan", "engine_count": 2, "engine_mount": "rear",
		"static_thrust": 75000.0, "fan_diam": 1.25, "bypass": 4.4, "spool": 4.0, "tsfc": 1.4e-5,
		"empty_mass": 24500.0, "mtow": 45000.0, "max_fuel": 20000.0, "max_payload": 2900.0,
		"cl0": 0.22, "cla": 5.0, "clmax": 1.4, "cd0": 0.019, "oswald": 0.78,
		"cm0": 0.02, "cma": -1.1, "cmq": -24.0, "cmde": 1.45, "max_elev": 24.0,
		"clb": -0.12, "clp": -0.46, "clr": 0.12, "clda": 0.13, "max_ail": 22.0,
		"cnb": 0.13, "cnr": -0.19, "cnp": -0.02, "cndr": 0.08, "cnda": -0.004, "max_rud": 24.0,
		"cyb": -0.6, "cydr": 0.2, "inertia_k": [0.25, 0.36, 0.44],
		"flaps": [
			{"label": "0", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 340},
			{"label": "10", "deg": 10.0, "dcl": 0.3, "dclmax": 0.45, "dcd": 0.012, "dcm": -0.03, "vfe": 250},
			{"label": "20", "deg": 20.0, "dcl": 0.55, "dclmax": 0.78, "dcd": 0.03, "dcm": -0.05, "vfe": 220},
			{"label": "39", "deg": 39.0, "dcl": 0.88, "dclmax": 1.12, "dcd": 0.07, "dcm": -0.08, "vfe": 180},
		],
		"gear_retract": true, "gear_cd": 0.02, "spoilers": true, "spoiler_cd": 0.045, "reverser": true,
		"gear_height": 2.25, "nose_gear_x": -11.2, "main_gear_x": 1.0, "gear_track": 4.3,
		"vs0": 100, "vs1": 125, "vr": 128, "v2": 136, "vref": 120, "vapp": 127, "vmo": 340, "mmo": 0.925,
		"climb_ias": 290, "cruise_ias": 260, "cruise_tas": 488, "descent_ias": 300,
		"cruise_alt": 43000, "ceiling": 51000, "climb_fpm": 3200,
		"autopilot": true, "fbw": true, "ils": true, "autoland": true,
		"pilots": 2, "fa": 1, "cabin": [{"cls": "vip", "rows": 4, "layout": "1-1", "pitch": 1.9, "seat_w": 0.75}],
		"doors": [0.12], "cockpit": "bizjet", "sound": "fan_small", "cargo_door": false, "hump": false,
		"hourly_cost": 6200, "rating_hours": 700.0, "range_nm": 7000, "tailstrike": 12.0,
	},
	"f4": {
		"name": "Titan F4 Freighter", "short": "TF4", "maker": "Titan Heavy Industries", "category": "cargo",
		"role": "Four-engine heavy cargo freighter",
		"blurb": "A humpbacked four-engine giant with a nose that swings open. 130 tonnes of freight and no passengers to complain.",
		"length": 70.6, "span": 64.4, "height": 19.4, "fuse_w": 6.5, "fuse_h": 7.0,
		"wing_area": 520.0, "mac": 8.9, "wing_pos": "low", "sweep": 37.5, "dihedral": 7.0, "taper": 0.25,
		"winglet": "raked", "tail": "conventional", "nose": "airliner_round", "cg_frac": 0.45,
		"engine_type": "turbofan", "engine_count": 4, "engine_mount": "wing",
		"static_thrust": 296000.0, "fan_diam": 2.6, "bypass": 8.0, "spool": 7.0, "tsfc": 1.2e-5,
		"empty_mass": 197000.0, "mtow": 447000.0, "max_fuel": 120000.0, "max_payload": 130000.0,
		"cl0": 0.24, "cla": 5.4, "clmax": 1.45, "cd0": 0.02, "oswald": 0.8,
		"cm0": 0.02, "cma": -1.3, "cmq": -34.0, "cmde": 1.35, "max_elev": 25.0,
		"clb": -0.13, "clp": -0.5, "clr": 0.14, "clda": 0.085, "max_ail": 25.0,
		"cnb": 0.14, "cnr": -0.22, "cnp": -0.02, "cndr": 0.08, "cnda": -0.004, "max_rud": 25.0,
		"cyb": -0.9, "cydr": 0.2, "inertia_k": [0.29, 0.40, 0.48],
		"flaps": [
			{"label": "UP", "deg": 0.0, "dcl": 0.0, "dclmax": 0.0, "dcd": 0.0, "dcm": 0.0, "vfe": 365},
			{"label": "1", "deg": 0.0, "dcl": 0.12, "dclmax": 0.35, "dcd": 0.005, "dcm": -0.01, "vfe": 280, "slats_only": true},
			{"label": "5", "deg": 5.0, "dcl": 0.28, "dclmax": 0.55, "dcd": 0.01, "dcm": -0.03, "vfe": 260},
			{"label": "10", "deg": 10.0, "dcl": 0.4, "dclmax": 0.7, "dcd": 0.018, "dcm": -0.04, "vfe": 240},
			{"label": "20", "deg": 20.0, "dcl": 0.64, "dclmax": 1.0, "dcd": 0.035, "dcm": -0.07, "vfe": 230},
			{"label": "30", "deg": 30.0, "dcl": 0.9, "dclmax": 1.3, "dcd": 0.07, "dcm": -0.1, "vfe": 180},
		],
		"gear_retract": true, "gear_cd": 0.022, "spoilers": true, "spoiler_cd": 0.045, "reverser": true,
		"gear_height": 5.2, "nose_gear_x": -26.0, "main_gear_x": 2.6, "gear_track": 11.0,
		"vs0": 125, "vs1": 165, "vr": 168, "v2": 176, "vref": 152, "vapp": 158, "vmo": 365, "mmo": 0.90,
		"climb_ias": 300, "cruise_ias": 280, "cruise_tas": 490, "descent_ias": 300,
		"cruise_alt": 35000, "ceiling": 43000, "climb_fpm": 1800,
		"autopilot": true, "fbw": false, "ils": true, "autoland": true,
		"pilots": 2, "fa": 0, "cabin": [{"cls": "crew_rest", "rows": 1, "layout": "2-2", "pitch": 1.2, "seat_w": 0.55}],
		"doors": [0.12], "cockpit": "boeing", "sound": "fan_large", "cargo_door": true, "hump": true,
		"hourly_cost": 21000, "rating_hours": 2500.0, "range_nm": 4400, "tailstrike": 10.5,
	},
}


static func get_type(id: String) -> Dictionary:
	return TYPES.get(id, TYPES["s320"])


static func all_ids() -> Array:
	return ORDER.duplicate()


static func seat_count(id: String) -> int:
	var t := get_type(id)
	var n := 0
	for sec in t.cabin:
		var per_row := 0
		for part in String(sec.layout).split("-"):
			per_row += int(part)
		n += per_row * int(sec.rows)
	if t.category == "trainer":
		return 3
	if t.category == "cargo":
		return 0
	return n


static func is_passenger(id: String) -> bool:
	var c: String = get_type(id).category
	return c != "cargo"


static func category_label(cat: String) -> String:
	match cat:
		"trainer": return "Training"
		"turboprop": return "Turboprop"
		"regional": return "Regional Jet"
		"narrowbody": return "Narrow-body"
		"widebody": return "Wide-body"
		"bizjet": return "Business Jet"
		"cargo": return "Cargo"
	return cat.capitalize()


static func stall_speed_kt(t: Dictionary, mass: float, flap_index: int) -> float:
	var clmax: float = t.clmax + float(t.flaps[flap_index].dclmax)
	var v := sqrt(2.0 * mass * U.G0 / (Atmo.RHO0 * float(t.wing_area) * clmax))
	return v / U.KT
