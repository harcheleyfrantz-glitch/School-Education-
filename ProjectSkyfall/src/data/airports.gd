class_name Airports
## Airport database for the Calderra / Westmark region.
## Positions are world metres (x = east, z = south). Runway "hdg" is the true heading of the
## first-named runway end; "off" shifts the runway sideways (positive = right of hdg).

const ORDER := ["SKPC", "SKRV", "SKNG", "SKHP", "SKOF", "SKWF", "SKIM", "SKSB", "WMIA", "WMSK"]

const DATA := {
	"SKPC": {
		"iata": "PCI", "name": "Port Calder International", "short": "Port Calder", "city": "Port Calder",
		"country": "Calderra", "x": -40000.0, "z": 0.0, "elev": 8.0, "size": "hub",
		"runways": [
			{"id": "09L/27R", "hdg": 90.0, "len": 3800.0, "wid": 60.0, "off": -700.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "09R/27L", "hdg": 90.0, "len": 3300.0, "wid": 45.0, "off": 700.0, "along": 300.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": true, "side": 1, "gates": 14, "style": "hub"},
		"freq": {"atis": "128.050", "del": "121.900", "gnd": "121.750", "twr": "118.300", "app": "119.450", "dep": "124.350"},
		"city_info": {"dx": -9000.0, "dz": 11000.0, "radius": 9500.0, "pop": 2400000, "tall": 1.0, "coastal": true},
		"desc": "Calderra's busy coastal hub with twin parallel runways and a sweeping glass terminal.",
		"arff": 9, "fuel": true, "pax_per_day": 68000,
	},
	"SKRV": {
		"iata": "RVM", "name": "Rivermouth Regional", "short": "Rivermouth", "city": "Rivermouth",
		"country": "Calderra", "x": -30000.0, "z": -120000.0, "elev": 6.0, "size": "regional",
		"runways": [
			{"id": "14/32", "hdg": 140.0, "len": 2600.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 5, "style": "regional"},
		"freq": {"atis": "127.200", "del": "121.650", "gnd": "121.650", "twr": "118.700", "app": "120.300", "dep": "120.300"},
		"city_info": {"dx": -6000.0, "dz": -7000.0, "radius": 4800.0, "pop": 340000, "tall": 0.45, "coastal": true},
		"desc": "A port city at the mouth of the Calder river. Sea fog rolls in on summer mornings.",
		"arff": 7, "fuel": true, "pax_per_day": 6200,
	},
	"SKNG": {
		"iata": "NGT", "name": "Northgate International", "short": "Northgate", "city": "Northgate",
		"country": "Calderra", "x": 30000.0, "z": -260000.0, "elev": 125.0, "size": "hub",
		"runways": [
			{"id": "18/36", "hdg": 180.0, "len": 3500.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "06/24", "hdg": 60.0, "len": 2400.0, "wid": 45.0, "off": 1500.0, "along": -500.0, "ils": [false, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 9, "style": "hub"},
		"freq": {"atis": "126.400", "del": "121.800", "gnd": "121.700", "twr": "119.100", "app": "125.250", "dep": "125.250"},
		"city_info": {"dx": 9000.0, "dz": -8000.0, "radius": 7000.0, "pop": 820000, "tall": 0.75, "coastal": false},
		"desc": "Industrial northern hub and home of Northwind Cargo. Harsh winters and gusty crosswinds.",
		"arff": 9, "fuel": true, "pax_per_day": 21000,
	},
	"SKHP": {
		"iata": "HPS", "name": "Highpass Regional", "short": "Highpass", "city": "Highpass",
		"country": "Calderra", "x": 230000.0, "z": -170000.0, "elev": 1150.0, "size": "regional",
		"runways": [
			{"id": "06/24", "hdg": 62.0, "len": 2500.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 4, "style": "regional"},
		"freq": {"atis": "127.650", "del": "121.600", "gnd": "121.600", "twr": "118.950", "app": "119.850", "dep": "119.850"},
		"city_info": {"dx": 6000.0, "dz": -5000.0, "radius": 2600.0, "pop": 45000, "tall": 0.25, "coastal": false},
		"desc": "A high mountain valley airport. Terrain on all sides, a one-way ILS and notorious downdrafts.",
		"arff": 6, "fuel": true, "pax_per_day": 2100,
	},
	"SKOF": {
		"iata": "OFL", "name": "Oren Falls Airport", "short": "Oren Falls", "city": "Oren Falls",
		"country": "Calderra", "x": 180000.0, "z": 60000.0, "elev": 215.0, "size": "regional",
		"runways": [
			{"id": "13/31", "hdg": 128.0, "len": 2900.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 6, "style": "regional"},
		"freq": {"atis": "126.850", "del": "121.850", "gnd": "121.850", "twr": "118.450", "app": "121.100", "dep": "121.100"},
		"city_info": {"dx": 6000.0, "dz": 11000.0, "radius": 5200.0, "pop": 510000, "tall": 0.55, "coastal": false},
		"desc": "Lakeside city airport beside the great Lake Oren. Calm mornings, thunderstorms on summer afternoons.",
		"arff": 7, "fuel": true, "pax_per_day": 8800,
	},
	"SKWF": {
		"iata": "WLF", "name": "Willow Field", "short": "Willow Field", "city": "Willowbrook",
		"country": "Calderra", "x": 40000.0, "z": 70000.0, "elev": 45.0, "size": "ga",
		"runways": [
			{"id": "03/21", "hdg": 30.0, "len": 1250.0, "wid": 25.0, "off": 0.0, "along": 0.0, "ils": [false, false], "surface": "asphalt"},
			{"id": "12/30", "hdg": 120.0, "len": 750.0, "wid": 30.0, "off": 380.0, "along": 150.0, "ils": [false, false], "surface": "grass"},
		],
		"terminal": {"between": false, "side": -1, "gates": 0, "style": "ga"},
		"freq": {"atis": "124.100", "del": "122.800", "gnd": "122.800", "twr": "122.800", "app": "119.450", "dep": "119.450"},
		"city_info": {"dx": 5000.0, "dz": 5000.0, "radius": 1800.0, "pop": 18000, "tall": 0.15, "coastal": false},
		"desc": "A friendly general aviation field and home of the Horizon Flight Academy.",
		"arff": 2, "fuel": true, "pax_per_day": 0,
	},
	"SKIM": {
		"iata": "IMR", "name": "Isla Marea Airport", "short": "Isla Marea", "city": "Marea",
		"country": "Calderra", "x": -20000.0, "z": 250000.0, "elev": 5.0, "size": "regional",
		"runways": [
			{"id": "11/29", "hdg": 110.0, "len": 2000.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [false, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 3, "style": "island"},
		"freq": {"atis": "127.000", "del": "121.700", "gnd": "121.700", "twr": "118.150", "app": "119.000", "dep": "119.000"},
		"city_info": {"dx": -5000.0, "dz": 4000.0, "radius": 2400.0, "pop": 60000, "tall": 0.3, "coastal": true},
		"desc": "A short island runway that ends at the sea. Trade winds bring strong crosswinds every afternoon.",
		"arff": 6, "fuel": true, "pax_per_day": 3200,
	},
	"SKSB": {
		"iata": "SBY", "name": "Sable Bay International", "short": "Sable Bay", "city": "Sable Bay",
		"country": "Calderra", "x": 160000.0, "z": 255000.0, "elev": 12.0, "size": "regional",
		"runways": [
			{"id": "16/34", "hdg": 160.0, "len": 2700.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 6, "style": "resort"},
		"freq": {"atis": "126.200", "del": "121.750", "gnd": "121.750", "twr": "118.800", "app": "124.700", "dep": "124.700"},
		"city_info": {"dx": 10000.0, "dz": 7000.0, "radius": 4200.0, "pop": 210000, "tall": 0.6, "coastal": true},
		"desc": "Resort city on a sheltered southern bay. Charter season keeps the ramp full of business jets.",
		"arff": 7, "fuel": true, "pax_per_day": 9800,
	},
	"WMIA": {
		"iata": "ALD", "name": "Aldmoor Westmark International", "short": "Aldmoor", "city": "Aldmoor",
		"country": "Westmark", "x": -420000.0, "z": -80000.0, "elev": 30.0, "size": "hub",
		"runways": [
			{"id": "08/26", "hdg": 80.0, "len": 4000.0, "wid": 60.0, "off": 0.0, "along": 0.0, "ils": [true, true], "surface": "asphalt"},
			{"id": "17/35", "hdg": 170.0, "len": 2800.0, "wid": 45.0, "off": 1600.0, "along": 900.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": 1, "gates": 12, "style": "hub"},
		"freq": {"atis": "128.650", "del": "121.950", "gnd": "121.800", "twr": "118.550", "app": "120.800", "dep": "127.900"},
		"city_info": {"dx": 12000.0, "dz": -10000.0, "radius": 9000.0, "pop": 1900000, "tall": 0.95, "coastal": false},
		"desc": "Westmark's gateway across the Western Sea, a long four-kilometre runway and a grand old terminal.",
		"arff": 9, "fuel": true, "pax_per_day": 52000,
	},
	"WMSK": {
		"iata": "SKR", "name": "Skerra Airport", "short": "Skerra", "city": "Skerra",
		"country": "Westmark", "x": -470000.0, "z": 60000.0, "elev": 18.0, "size": "regional",
		"runways": [
			{"id": "04/22", "hdg": 40.0, "len": 1900.0, "wid": 45.0, "off": 0.0, "along": 0.0, "ils": [true, false], "surface": "asphalt"},
		],
		"terminal": {"between": false, "side": -1, "gates": 3, "style": "regional"},
		"freq": {"atis": "127.400", "del": "121.600", "gnd": "121.600", "twr": "118.200", "app": "120.100", "dep": "120.100"},
		"city_info": {"dx": -4000.0, "dz": 6000.0, "radius": 2800.0, "pop": 75000, "tall": 0.3, "coastal": true},
		"desc": "A windswept fishing town airport on Westmark's rugged western coast.",
		"arff": 6, "fuel": true, "pax_per_day": 1800,
	},
}

const CENTER_FREQ := {"Calderra": "128.200", "Westmark": "131.450", "Oceanic": "126.950"}


static func get_ap(icao: String) -> Dictionary:
	return DATA.get(icao, {})


static func all_icao() -> Array:
	return ORDER.duplicate()


static func pos2(icao: String) -> Vector2:
	var a: Dictionary = DATA[icao]
	return Vector2(a.x, a.z)


static func distance_m(a: String, b: String) -> float:
	return pos2(a).distance_to(pos2(b))


static func distance_nm(a: String, b: String) -> float:
	return distance_m(a, b) / U.NM


static func nearest(x: float, z: float, exclude: String = "", min_runway: float = 0.0) -> String:
	var best := ""
	var bd := INF
	for icao in ORDER:
		if icao == exclude:
			continue
		if longest_runway(icao) < min_runway:
			continue
		var a: Dictionary = DATA[icao]
		var d := U.dist2d(x, z, a.x, a.z)
		if d < bd:
			bd = d
			best = icao
	return best


static func longest_runway(icao: String) -> float:
	var best := 0.0
	for r in DATA[icao].runways:
		if r.surface == "asphalt":
			best = maxf(best, r.len)
	return best


## Returns a list of runway ends: each {name, rwy_index, hdg, thr_x, thr_z, end_x, end_z, len, wid, ils, elev, surface}
static func runway_ends(icao: String) -> Array:
	var a: Dictionary = DATA[icao]
	var out := []
	var idx := 0
	for r in a.runways:
		var names: PackedStringArray = String(r.id).split("/")
		var dir := Vector2(sin(deg_to_rad(r.hdg)), -cos(deg_to_rad(r.hdg)))
		var right := Vector2(-dir.y, dir.x)
		var c := Vector2(a.x, a.z) + right * float(r.off) + dir * float(r.along)
		var half := float(r.len) * 0.5
		var t1 := c - dir * half
		var t2 := c + dir * half
		out.append({"name": names[0], "rwy": idx, "hdg": float(r.hdg), "thr_x": t1.x, "thr_z": t1.y,
			"end_x": t2.x, "end_z": t2.y, "len": float(r.len), "wid": float(r.wid), "ils": bool(r.ils[0]),
			"elev": float(a.elev), "surface": r.surface, "airport": icao})
		out.append({"name": names[1], "rwy": idx, "hdg": U.wrap_deg(float(r.hdg) + 180.0), "thr_x": t2.x, "thr_z": t2.y,
			"end_x": t1.x, "end_z": t1.y, "len": float(r.len), "wid": float(r.wid), "ils": bool(r.ils[1]),
			"elev": float(a.elev), "surface": r.surface, "airport": icao})
		idx += 1
	return out


static func runway_end(icao: String, name: String) -> Dictionary:
	for e in runway_ends(icao):
		if e.name == name:
			return e
	return {}


## Picks the runway end best aligned with the wind (largest headwind), preferring paved runways.
static func best_runway(icao: String, wind_from_deg: float, wind_kt: float, min_len: float = 0.0) -> Dictionary:
	var best := {}
	var best_score := -INF
	for e in runway_ends(icao):
		if e.surface != "asphalt" and min_len > 900.0:
			continue
		var head := cos(deg_to_rad(wind_from_deg - e.hdg)) * wind_kt
		var score = head * 2.0 + (e.len / 1000.0) + (3.0 if e.ils else 0.0)
		if e.len < min_len:
			score -= 100.0
		if e.surface != "asphalt":
			score -= 20.0
		if score > best_score:
			best_score = score
			best = e
	return best


static func city_center(icao: String) -> Vector2:
	var a: Dictionary = DATA[icao]
	return Vector2(a.x + a.city_info.dx, a.z + a.city_info.dz)
