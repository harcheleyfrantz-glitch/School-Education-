class_name WeatherModel
## Deterministic weather: a pure function of (x, z, time). Synoptic systems drift across the map,
## convection builds on summer afternoons, fog forms on calm coastal mornings. Because it is a
## function, replays and news reconstructions can recreate the exact conditions of any moment.

const PRESETS := {
	"clear": {"cover": 0.05, "base_ft": 6000.0, "wind": 6.0, "dir": 270.0, "vis": 50000.0, "precip": "none", "turb": 0.05, "storm": 0.0, "temp_off": 0.0},
	"few": {"cover": 0.25, "base_ft": 4500.0, "wind": 9.0, "dir": 250.0, "vis": 40000.0, "precip": "none", "turb": 0.12, "storm": 0.0, "temp_off": 0.0},
	"scattered": {"cover": 0.45, "base_ft": 3500.0, "wind": 12.0, "dir": 240.0, "vis": 30000.0, "precip": "none", "turb": 0.18, "storm": 0.0, "temp_off": -1.0},
	"overcast": {"cover": 0.95, "base_ft": 1800.0, "wind": 14.0, "dir": 220.0, "vis": 12000.0, "precip": "none", "turb": 0.2, "storm": 0.1, "temp_off": -3.0},
	"rain": {"cover": 1.0, "base_ft": 1200.0, "wind": 18.0, "dir": 210.0, "vis": 5000.0, "precip": "rain", "turb": 0.3, "storm": 0.35, "temp_off": -5.0},
	"storm": {"cover": 0.9, "base_ft": 2200.0, "wind": 24.0, "dir": 230.0, "vis": 4000.0, "precip": "thunderstorm", "turb": 0.65, "storm": 0.9, "temp_off": -4.0},
	"fog": {"cover": 1.0, "base_ft": 200.0, "wind": 2.0, "dir": 180.0, "vis": 350.0, "precip": "none", "turb": 0.02, "storm": 0.0, "temp_off": -2.0},
	"snow": {"cover": 1.0, "base_ft": 1500.0, "wind": 15.0, "dir": 340.0, "vis": 3000.0, "precip": "snow", "turb": 0.25, "storm": 0.2, "temp_off": -24.0},
	"crosswind": {"cover": 0.35, "base_ft": 3800.0, "wind": 26.0, "dir": 0.0, "vis": 25000.0, "precip": "none", "turb": 0.45, "storm": 0.1, "temp_off": 0.0},
}

static var _syn: FastNoiseLite
static var _loc: FastNoiseLite
static var _dir: FastNoiseLite
static var _conv: FastNoiseLite
static var override_preset := ""
static var override_dir := -1.0


static func _ensure() -> void:
	if _syn != null:
		return
	_syn = FastNoiseLite.new()
	_syn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_syn.seed = 2027
	_syn.frequency = 1.0
	_syn.fractal_octaves = 2
	_loc = FastNoiseLite.new()
	_loc.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_loc.seed = 61
	_loc.frequency = 1.0
	_loc.fractal_octaves = 3
	_dir = FastNoiseLite.new()
	_dir.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dir.seed = 808
	_dir.frequency = 1.0
	_dir.fractal_octaves = 1
	_conv = FastNoiseLite.new()
	_conv.noise_type = FastNoiseLite.TYPE_CELLULAR
	_conv.seed = 1717
	_conv.frequency = 1.0
	_conv.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_conv.fractal_type = FastNoiseLite.FRACTAL_NONE


static func season_temp_c(doy: int) -> float:
	# Mean sea-level temperature for the region (northern hemisphere, ~40N).
	return 14.0 + 10.0 * sin((float(doy) - 105.0) / 365.0 * TAU)


## Full weather report at a position/time.
static func sample(x: float, z: float, t: float) -> Dictionary:
	_ensure()
	var dt := U.clock_to_date(t)
	var hour: float = dt.hours_f
	var th := t / 3600.0
	var w: Dictionary
	var elev := maxf(Geo.height(x, z), 0.0) if Geo.ready else 0.0
	if override_preset != "" and PRESETS.has(override_preset):
		var p: Dictionary = PRESETS[override_preset]
		w = {
			"cover": p.cover, "base_ft": p.base_ft + elev / U.FT, "wind_kt": p.wind,
			"wind_dir": p.dir if override_dir < 0.0 else override_dir, "vis": p.vis,
			"precip": p.precip, "turb": p.turb, "storm": p.storm,
			"temp_c": season_temp_c(dt.doy) + p.temp_off - elev * 0.0065 + 4.0 * sin((hour - 9.0) / 24.0 * TAU),
		}
		if override_preset == "crosswind":
			w.gust_kt = w.wind_kt + 12.0
	else:
		# synoptic scale: systems ~500 km across drifting east at ~25 km/h
		var drift := th * 25000.0
		var syn := _syn.get_noise_3d((x - drift) / 520000.0, z / 520000.0, th / 60.0)
		var loc := _loc.get_noise_3d(x / 70000.0, z / 70000.0, th / 6.0)
		var dirn := _dir.get_noise_3d(x / 900000.0, z / 900000.0, th / 40.0)
		var coast := 1.0 - U.smooth01(absf(Geo.height(x, z) if Geo.ready else 10.0) / 80.0)
		var mountain := U.smooth01((elev - 300.0) / 900.0)
		var summer := clampf(sin((float(dt.doy) - 80.0) / 365.0 * TAU), 0.0, 1.0)
		var afternoon := U.smooth01(1.0 - absf(hour - 16.0) / 4.5)
		var morning := U.smooth01(1.0 - absf(hour - 6.5) / 3.0)
		var storm := clampf(syn * 1.3 + 0.1, -1.0, 1.0)
		var cover := clampf(0.32 + storm * 0.55 + loc * 0.35 + mountain * 0.15, 0.0, 1.0)
		var wind := 5.0 + maxf(storm, 0.0) * 22.0 + absf(loc) * 7.0 + mountain * 6.0 + coast * 3.0
		var wdir := U.wrap_deg(255.0 + dirn * 140.0 + storm * 30.0)
		var temp := season_temp_c(dt.doy) - elev * 0.0065 + 5.0 * sin((hour - 9.0) / 24.0 * TAU) - maxf(storm, 0.0) * 4.0
		var vis := 45000.0 - cover * 18000.0
		var precip := "none"
		if cover > 0.82 and storm > 0.25:
			precip = "snow" if temp < 1.0 else "rain"
			vis = minf(vis, 6000.0 - storm * 2500.0)
		# convective cells on warm afternoons
		var conv := (1.0 - _conv.get_noise_3d(x / 45000.0, z / 45000.0, th / 3.0) * 1.0)
		var conv_potential := summer * afternoon * clampf(storm + 0.55, 0.0, 1.0) * (0.6 + mountain * 0.6)
		var cb := conv_potential > 0.35 and conv > 1.35 and temp > 12.0
		if cb:
			precip = "thunderstorm"
			cover = maxf(cover, 0.75)
			wind += 8.0
			vis = minf(vis, 3500.0)
		# coastal fog on calm mornings
		var fogp := coast * morning * clampf(0.6 - wind / 20.0, 0.0, 1.0) * clampf(loc + 0.4, 0.0, 1.0)
		if fogp > 0.18 and precip == "none":
			vis = lerpf(2500.0, 300.0, clampf((fogp - 0.18) / 0.25, 0.0, 1.0))
			cover = 1.0
		var base_ft := 900.0 + (1.0 - cover) * 4200.0 + temp * 40.0 + elev / U.FT
		if vis < 1500.0:
			base_ft = elev / U.FT + maxf(100.0, vis * 0.25)
		w = {
			"cover": cover, "base_ft": base_ft, "wind_kt": wind, "wind_dir": wdir, "vis": vis,
			"precip": precip, "turb": clampf(wind / 45.0 + mountain * 0.25 + (0.45 if cb else 0.0), 0.0, 1.0),
			"storm": clampf(storm, 0.0, 1.0) * 0.6 + (0.6 if cb else 0.0), "temp_c": temp,
		}
	if not w.has("gust_kt"):
		w.gust_kt = w.wind_kt + (0.0 if w.wind_kt < 12.0 else w.wind_kt * 0.45 * float(w.turb))
	w.top_ft = w.base_ft + 1500.0 + float(w.cover) * 5000.0 + (25000.0 if w.precip == "thunderstorm" else 0.0)
	w.dew_c = float(w.temp_c) - (1.0 if w.vis < 3000.0 else 4.0 + (1.0 - float(w.cover)) * 8.0)
	w.qnh = int(round(1013.0 - float(w.storm) * 22.0 + _loc.get_noise_2d(th / 30.0, 3.0) * 6.0))
	w.icing = float(w.temp_c) - (float(w.base_ft) / 1000.0 * 2.0) < 2.0 and float(w.cover) > 0.6
	w.lightning = w.precip == "thunderstorm"
	return w


## Wind vector (m/s, world frame, direction the air moves TOWARDS) at altitude.
static func wind_at_alt(w: Dictionary, alt_m: float, ground_elev: float) -> Vector3:
	var agl := maxf(alt_m - ground_elev, 0.0)
	var speed_kt: float = w.wind_kt * (0.65 + 0.35 * U.smooth01(agl / 600.0)) + agl / U.FT / 1000.0 * 1.6
	speed_kt = minf(speed_kt, 140.0)
	var from := deg_to_rad(float(w.wind_dir) + clampf(agl / 3000.0, 0.0, 1.0) * 25.0)
	# wind blows FROM wind_dir, so it moves toward wind_dir + 180
	return Vector3(-sin(from), 0.0, cos(from)) * speed_kt * U.KT


static func cover_code(cover: float) -> String:
	if cover < 0.12:
		return "SKC"
	if cover < 0.3:
		return "FEW"
	if cover < 0.55:
		return "SCT"
	if cover < 0.88:
		return "BKN"
	return "OVC"


static func metar(icao: String, t: float) -> String:
	var a := Airports.get_ap(icao)
	var w := sample(a.x, a.z, t)
	var wind := "%03d%02dKT" % [int(round(float(w.wind_dir) / 10.0) * 10) % 360, int(round(w.wind_kt))]
	if w.gust_kt > w.wind_kt + 8.0:
		wind = "%03d%02dG%02dKT" % [int(round(float(w.wind_dir) / 10.0) * 10) % 360, int(round(w.wind_kt)), int(round(w.gust_kt))]
	var vis := "9999" if w.vis >= 10000.0 else "%04d" % (int(w.vis / 100.0) * 100)
	var wx := ""
	match w.precip:
		"rain": wx = " RA" if w.vis > 5000 else " +RA"
		"snow": wx = " SN"
		"thunderstorm": wx = " TSRA"
	if w.vis < 1000.0 and w.precip == "none":
		wx = " FG"
	elif w.vis < 5000.0 and w.precip == "none":
		wx = " BR"
	var agl_base := maxf(float(w.base_ft) - float(a.elev) / U.FT, 100.0)
	var cc := cover_code(w.cover)
	var clouds := "SKC" if cc == "SKC" else "%s%03d" % [cc, int(agl_base / 100.0)]
	if w.precip == "thunderstorm":
		clouds += "CB"
	var temp := int(round(w.temp_c))
	var dew := int(round(w.dew_c))
	var ts := ("M%02d" % absi(temp)) if temp < 0 else "%02d" % temp
	var ds := ("M%02d" % absi(dew)) if dew < 0 else "%02d" % dew
	return "%s %s %s %s%s %s %s/%s Q%d" % [icao, U.fmt_zulu(t), wind, vis, wx, clouds, ts, ds, w.qnh]


static func describe(w: Dictionary) -> String:
	var parts := []
	match cover_code(w.cover):
		"SKC": parts.append("Clear skies")
		"FEW": parts.append("Mostly clear")
		"SCT": parts.append("Scattered clouds")
		"BKN": parts.append("Broken clouds")
		"OVC": parts.append("Overcast")
	match w.precip:
		"rain": parts.append("rain")
		"snow": parts.append("snow")
		"thunderstorm": parts.append("thunderstorms")
	if w.vis < 1000.0:
		parts.append("fog")
	elif w.vis < 5000.0:
		parts.append("reduced visibility")
	parts.append("wind %03d° at %d kt" % [int(w.wind_dir), int(round(w.wind_kt))])
	if w.gust_kt > w.wind_kt + 8.0:
		parts.append("gusting %d" % int(round(w.gust_kt)))
	return ", ".join(parts)


static func flight_category(w: Dictionary, elev_ft: float) -> String:
	var ceiling := float(w.base_ft) - elev_ft if float(w.cover) > 0.55 else 99999.0
	if w.vis < 1600.0 or ceiling < 500.0:
		return "LIFR"
	if w.vis < 5000.0 or ceiling < 1000.0:
		return "IFR"
	if w.vis < 8000.0 or ceiling < 3000.0:
		return "MVFR"
	return "VFR"
