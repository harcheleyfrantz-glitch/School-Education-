class_name LongHaul
extends Node
## Life on a long flight. Position reports name the country or sea below, the local time there and
## the distance and time to go. There are messages for crossing into a new continent, the equator
## and the halfway point. Flights of 90 minutes or more also get cabin service on the PA: drinks, a
## meal, the cabin lights dimmed at night, the duty-free trolley and breakfast before the descent.
## Pilots flying three hours or more get a relief crew, and high northern flights at night can see
## the aurora. The countries and seas crossed are kept for the debrief and the achievements.

var session: Node
var ac: Aircraft
var overflown: Array = []          # countries and seas below, in the order they were crossed
var continents: Array = []         # continents crossed
var crossed_equator := false
var saw_aurora := false
var est_hours := 0.0
var _t := 0.0
var _cruise_t := 0.0
var _report_t := 45.0
var _dep := Vector2.ZERO
var _arr := Vector2.ZERO
var _total := 1.0
var _said := {}
var _last_area := ""
var _last_cont := ""
var _last_lat := 999.0
var _peak_dist := 0.0
var _aurora: MeshInstance3D = null
var _aurora_mat: ShaderMaterial = null
var _aurora_fade := 0.0

const AURORA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform float fade = 0.0;
void fragment() {
	float t = TIME * 0.06;
	float x = UV.x;
	float v = UV.y;
	float folds = sin(x * 38.0 + sin(x * 6.0 + t * 5.0) * 3.0 + t * 3.0) * 0.5 + 0.5;
	folds = pow(folds, 2.5);
	float rays = sin(x * 300.0 + sin(x * 21.0 + t) * 5.0) * 0.5 + 0.5;
	float flicker = 0.75 + 0.25 * sin(t * 9.0 + x * 13.0);
	float base = smoothstep(0.0, 0.07, v) * (1.0 - smoothstep(0.2, 1.0, v));
	float ends = smoothstep(0.0, 0.12, x) * smoothstep(1.0, 0.88, x);
	vec3 col = mix(vec3(0.12, 1.0, 0.42), vec3(0.75, 0.22, 0.75), smoothstep(0.5, 1.0, v));
	col = mix(col, vec3(0.6, 1.0, 0.8), smoothstep(0.08, 0.0, v) * 0.6);
	ALBEDO = col * (0.3 + 0.7 * folds) * (0.55 + 0.45 * rays) * flicker * base * ends * fade * 1.4;
}
"""

static var _polys: Array = []

# Rough boxes (lon0, lon1, lat0, lat1) for countries without an airport in the game, checked in
# order (small ones first). Places within 150 km of a game city take that city's country instead.
const BOXES := [
	["Qatar", 50.7, 51.7, 24.4, 26.2], ["United Arab Emirates", 51.5, 56.4, 22.6, 26.1], ["Kuwait", 46.5, 48.5, 28.5, 30.1],
	["Israel", 34.2, 35.9, 29.5, 33.3], ["Lebanon", 35.1, 36.6, 33.0, 34.7], ["Sri Lanka", 79.6, 82.0, 5.9, 9.9],
	["Bangladesh", 88.0, 92.7, 20.6, 26.6], ["Nepal", 80.0, 88.2, 26.3, 30.5], ["Bhutan", 88.7, 92.1, 26.7, 28.3],
	["Singapore", 103.6, 104.1, 1.15, 1.47], ["Taiwan", 120.0, 122.1, 21.9, 25.4], ["South Korea", 125.0, 129.6, 34.0, 38.6],
	["North Korea", 124.2, 130.7, 37.7, 43.0], ["Japan", 129.4, 146.0, 30.9, 45.6], ["Cambodia", 102.3, 107.6, 10.4, 14.7],
	["Laos", 100.1, 107.7, 13.9, 22.5], ["Vietnam", 102.1, 109.5, 8.5, 23.4], ["Thailand", 97.3, 105.6, 5.6, 20.5],
	["Myanmar", 92.2, 101.2, 9.8, 28.5], ["Malaysia", 99.6, 119.3, 0.85, 7.4], ["Philippines", 116.9, 126.6, 4.6, 21.1],
	["Indonesia", 95.0, 141.0, -11.0, 6.0], ["Pakistan", 60.9, 77.8, 23.7, 37.1], ["Afghanistan", 60.5, 74.9, 29.4, 38.5],
	["India", 68.1, 97.4, 6.7, 35.5], ["Oman", 52.0, 59.8, 16.6, 26.4], ["Yemen", 42.6, 53.1, 12.6, 19.0],
	["Iran", 44.0, 63.3, 25.1, 39.8], ["Iraq", 38.8, 48.6, 29.1, 37.4], ["Syria", 35.7, 42.4, 32.3, 37.3],
	["Jordan", 34.9, 39.3, 29.2, 33.4], ["Saudi Arabia", 34.5, 55.7, 16.4, 32.2], ["Egypt", 24.7, 36.9, 22.0, 31.7],
	["Sudan", 21.8, 38.6, 8.7, 22.0], ["Ethiopia", 33.0, 48.0, 3.4, 14.9], ["Kenya", 33.9, 41.9, -4.7, 5.0],
	["Libya", 9.3, 25.2, 19.5, 33.2], ["Tunisia", 7.5, 11.6, 30.2, 37.5], ["Algeria", -8.7, 12.0, 19.0, 37.1],
	["Morocco", -13.2, -1.0, 27.7, 35.9], ["Cyprus", 32.2, 34.6, 34.5, 35.7], ["Georgia", 40.0, 46.7, 41.0, 43.6],
	["Armenia", 43.4, 46.6, 38.8, 41.3], ["Azerbaijan", 44.8, 50.4, 38.4, 41.9], ["Turkey", 26.0, 44.8, 35.8, 42.1],
	["Greece", 19.4, 28.3, 34.8, 41.8], ["Bulgaria", 22.4, 28.6, 41.2, 44.2], ["Serbia", 18.8, 23.0, 42.2, 46.2],
	["Croatia", 13.5, 19.4, 42.4, 46.5], ["Romania", 20.3, 29.7, 43.6, 48.3], ["Hungary", 16.1, 22.9, 45.7, 48.6],
	["Czechia", 12.1, 18.9, 48.6, 51.1], ["Poland", 14.1, 24.2, 49.0, 54.9], ["Lithuania", 21.0, 26.8, 53.9, 56.5],
	["Latvia", 21.0, 28.2, 55.7, 58.1], ["Estonia", 21.8, 28.2, 57.5, 59.7], ["Belarus", 23.2, 32.8, 51.3, 56.2],
	["Ukraine", 22.1, 40.2, 44.4, 52.4], ["Finland", 20.6, 31.6, 59.8, 70.1], ["Turkmenistan", 52.4, 66.7, 35.1, 42.8],
	["Uzbekistan", 56.0, 73.1, 37.2, 45.6], ["Tajikistan", 67.3, 75.2, 36.7, 41.0], ["Kyrgyzstan", 69.3, 80.3, 39.2, 43.3],
	["Kazakhstan", 46.5, 87.4, 40.6, 55.4], ["Mongolia", 87.7, 119.9, 41.6, 52.2], ["China", 73.5, 135.1, 18.2, 53.6],
	["Russia", 27.0, 180.0, 41.2, 82.0], ["Mexico", -117.1, -86.7, 14.5, 32.7],
]


func setup(sess: Node, aircraft: Aircraft) -> void:
	session = sess
	ac = aircraft
	var d := Airports.get_ap(String(sess.get("dep_icao")))
	var a := Airports.get_ap(String(sess.get("arr_icao")))
	_dep = Vector2(float(d.x), float(d.z))
	_arr = Vector2(float(a.x), float(a.z))
	_total = maxf(_dep.distance_to(_arr), 1.0)
	est_hours = _total / maxf(float(ac.spec.cruise_tas) * U.KT, 60.0) / 3600.0
	var here := _area(_dep.x, _dep.y)
	if here != "":
		overflown.append(here)
		_last_area = here
	_last_cont = continent(_dep.x, _dep.y)
	if _last_cont != "":
		continents.append(_last_cont)
	_last_lat = RealWorld.to_lonlat(_dep.x, _dep.y).y


# ================================================================== where are we
static func continent(x: float, z: float) -> String:
	if not Geo.in_world_region(x, z):
		return ""
	if _polys.is_empty():
		for p in RealWorld.POLYS:
			_polys.append(PackedVector2Array(p))
	var pk := Vector2(x, z) / 1000.0
	for i in _polys.size():
		if Geometry2D.is_point_in_polygon(pk, _polys[i]):
			var n: String = RealWorld.POLY_NAMES[i]
			match n:
				"Baffin Island", "Greenland", "Newfoundland", "Cuba":
					return "North America"
				"Great Britain", "Ireland", "Iceland":
					return "Europe"
			return n
	return ""


static func country_at(x: float, z: float) -> String:
	if not Geo.in_world_region(x, z):
		return Geo.region_country(x, z)
	var c := Geo.nearest_city(x, z)
	if not c.is_empty() and float(c.get("dist", INF)) < 150000.0 and String(c.get("country", "")) != "":
		return String(c.country)
	var ll := RealWorld.to_lonlat(x, z)
	for b in BOXES:
		if ll.x >= float(b[1]) and ll.x <= float(b[2]) and ll.y >= float(b[3]) and ll.y <= float(b[4]):
			return String(b[0])
	if not c.is_empty() and float(c.get("dist", INF)) < 450000.0:
		return String(c.get("country", ""))
	return ""


func _area(x: float, z: float) -> String:
	if Geo.is_water(x, z):
		if Geo.in_world_region(x, z):
			return RealWorld.sea_name(x, z)
		return "the open sea"
	return country_at(x, z)


func _local_time(x: float, z: float) -> String:
	## Solar time below the aircraft: an hour for every 15 degrees east of Greenwich.
	var lon := RealWorld.to_lonlat(x, z).x if Geo.in_world_region(x, z) else 0.0
	var secs := fposmod(WorldSim.clock + lon / 15.0 * 3600.0, 86400.0)
	return "%02d:%02d" % [int(secs / 3600.0), int(fmod(secs, 3600.0) / 60.0)]


func _say(key: String, text: String, kind: String = "info") -> void:
	if _said.has(key):
		return
	_said[key] = true
	if session.has_signal("toast"):
		session.toast.emit(text, kind)
	var rec = session.get("recorder")
	if rec and rec.has_method("mark"):
		rec.mark("cabin", text)


func _mood(dv: float) -> void:
	var p = session.get("people")
	if p and is_instance_valid(p):
		p.mood = clampf(float(p.mood) + dv, 0.0, 1.2)


# ================================================================== the flight
func _process(delta: float) -> void:
	if ac == null or not is_instance_valid(ac) or ac.crashed_state:
		return
	_t += delta
	var ph := String(session.get("phase"))
	var x := ac.world_x()
	var z := ac.world_z()
	var here := Vector2(x, z)
	var to_go := here.distance_to(_arr)
	var flown := clampf(_total - to_go, 0.0, _total)
	_peak_dist = maxf(_peak_dist, flown)
	var airborne := not ac.fdm.on_ground
	if ph == "cruise":
		_cruise_t += delta
	# ---- borders, continents, the equator
	_report_t -= delta
	if airborne and _report_t <= 0.0:
		_report_t = 20.0
		var area := _area(x, z)
		if area != "" and area != _last_area:
			_last_area = area
			if not area in overflown:
				overflown.append(area)
				if overflown.size() > 1 and float(ac.ra) > 1500.0:
					_report(area, x, z, to_go)
		var cont := continent(x, z)
		if cont != "" and cont != _last_cont:
			if _last_cont != "" and float(ac.ra) > 1500.0:
				_say("cont_" + cont, "You've crossed from %s into %s." % [_last_cont, cont], "success")
			_last_cont = cont
			if not cont in continents:
				continents.append(cont)
		if Geo.in_world_region(x, z):
			var lat := RealWorld.to_lonlat(x, z).y
			if _last_lat < 900.0 and signf(lat) != signf(_last_lat) and not crossed_equator:
				crossed_equator = true
				_say("equator", "You've just crossed the equator! The cabin crew hand out certificates to everyone crossing the line for the first time.", "success")
				_mood(0.03)
			_last_lat = lat
			# the aurora: high north, dark sky, clear of cloud
			var view = session.get("view")
			if not saw_aurora and lat > 57.0 and view and float(view.get("night")) > 0.6 and float(ac.ra) > 6000.0:
				saw_aurora = true
				_say("aurora", "Look north: the aurora borealis! Green curtains of light ripple across the sky. The cabin goes quiet as everyone stares out of the windows.", "success")
				_mood(0.05)
	_update_aurora(delta, x, z)
	_seasonal(x, z)
	# ---- the halfway point
	if est_hours >= 1.0 and flown > _total * 0.5 and airborne:
		_say("half", "Halfway there: %s km behind you, %s km to go to %s." % [U.fmt_int(int(flown / 1000.0)), U.fmt_int(int(to_go / 1000.0)), String(Airports.get_ap(String(session.get("arr_icao"))).get("city", ""))], "info")
	if est_hours < 1.5 or not airborne:
		return
	# ---- cabin life on long flights
	var mins := _cruise_t / 60.0
	var view2 = session.get("view")
	var night := float(view2.get("night")) if view2 else 0.0
	var tod_min := to_go / maxf(float(ac.spec.cruise_tas) * U.KT, 60.0) / 60.0    # minutes of flying left
	if ph == "cruise":
		if mins > 4.0:
			_say("drinks", "Cabin: the seat-belt sign is off and the drinks trolley is on its way. Juice, water, wine or something stronger?")
		if mins > 14.0 and tod_min > 40.0:
			_say("meal", "Cabin: the meal service has started. Tonight's choice: chicken with rice or pasta with mushrooms. Economy is out of chicken by row 30, as always." if night > 0.5 else "Cabin: the meal service has started - chicken with rice or pasta with mushrooms. The smell drifts all the way to the flight deck.")
			_mood(0.03)
		if mins > 40.0 and night > 0.5 and tod_min > 70.0:
			_say("lights", "Cabin: the lights are dimmed for the night. Window blinds come down, blankets come out and most of the cabin is asleep within half an hour.")
		if mins > 55.0 and tod_min > 50.0:
			_say("dutyfree", "Cabin: the duty-free trolley is rolling down the aisle - perfume, chocolate and a model of this very aircraft.")
		if est_hours >= 3.0 and mins > 70.0 and tod_min > 60.0 and String(session.get("mode")) == "pilot":
			_say("rest", "The relief crew is on the flight deck. Your first officer heads to the crew bunk above the cabin for a rest - you could let auto-fly take a shift too.")
		if est_hours >= 2.5 and mins > 25.0 and tod_min < 45.0 and tod_min > 20.0:
			_say("breakfast", "Cabin: the lights come up and breakfast is served before the descent - coffee, warm croissants and fruit." if night < 0.5 or _said.has("lights") else "Cabin: a light snack is served before the descent - sandwiches, fruit and coffee.")
			_mood(0.02)
	if ph == "descent" and est_hours >= 2.0:
		_say("arrive_pa", "Cabin: \"Ladies and gentlemen, we've started our descent into %s. The local time is %s. Please return to your seats and fasten your seat belts.\"" % [String(Airports.get_ap(String(session.get("arr_icao"))).get("city", "")), _local_time(_arr.x, _arr.y)])


func _seasonal(x: float, z: float) -> void:
	## Christmas Eve and New Year's Eve in the air.
	if ac.fdm.on_ground or float(ac.ra) < 2500.0 or _t < 60.0:
		return
	var d := U.clock_to_date(WorldSim.clock)
	var lon := RealWorld.to_lonlat(x, z).x if Geo.in_world_region(x, z) else 0.0
	var local_h := fposmod(float(d.hours_f) + lon / 15.0, 24.0)
	if int(d.month) == 12 and int(d.day) == 24 and (local_h > 19.0 or local_h < 2.0):
		_say("santa", "ATC: \"%s, unidentified traffic, twelve o'clock, five miles, opposite direction, no transponder... it appears to be a sleigh with nine reindeer. The lead one has a red light.\" Merry Christmas!" % String(session.get("callsign")), "success")
		if _said.has("santa") and not Achievements.unlocked("santa"):
			Achievements.unlock("santa")
	if (int(d.month) == 12 and int(d.day) == 31 and local_h > 23.5) or (int(d.month) == 1 and int(d.day) == 1 and local_h < 0.5):
		_say("newyear", "Happy New Year! Fireworks are bursting over the cities below - the whole cabin counts down from ten and cheers.", "success")
		_mood(0.05)


func _update_aurora(delta: float, x: float, z: float) -> void:
	## Green and violet curtains hanging 20 km north of the aircraft once the aurora is spotted,
	## while it stays dark and far enough north.
	var view = session.get("view")
	if view == null:
		return
	var want := 0.0
	if saw_aurora and Geo.in_world_region(x, z) and RealWorld.to_lonlat(x, z).y > 55.0 and float(view.get("night")) > 0.5:
		want = 1.0
	_aurora_fade = move_toward(_aurora_fade, want, delta * 0.08)
	if _aurora_fade <= 0.001:
		if _aurora:
			_aurora.visible = false
		return
	if _aurora == null:
		_build_aurora(view)
	_aurora.visible = true
	_aurora_mat.set_shader_parameter("fade", _aurora_fade)
	_aurora.position = view.world_to_local(x, ac.fdm.pos.y + 4000.0, z)


func _build_aurora(view: Node) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 64
	var half := 34000.0
	for band in 2:
		var dist := 21000.0 + band * 6000.0
		var top := 13000.0 - band * 3000.0
		for i in n:
			var a := float(i) / float(n)
			var b := float(i + 1) / float(n)
			var xa := lerpf(-half, half, a)
			var xb := lerpf(-half, half, b)
			var za := -dist + xa * xa / 90000.0 + sin(a * 11.0 + band) * 1800.0
			var zb := -dist + xb * xb / 90000.0 + sin(b * 11.0 + band) * 1800.0
			var ua := a * 0.97 + band * 0.31
			var ub := b * 0.97 + band * 0.31
			st.set_uv(Vector2(ua, 0.0)); st.add_vertex(Vector3(xa, 0.0, za))
			st.set_uv(Vector2(ub, 0.0)); st.add_vertex(Vector3(xb, 0.0, zb))
			st.set_uv(Vector2(ub, 1.0)); st.add_vertex(Vector3(xb, top, zb))
			st.set_uv(Vector2(ua, 0.0)); st.add_vertex(Vector3(xa, 0.0, za))
			st.set_uv(Vector2(ub, 1.0)); st.add_vertex(Vector3(xb, top, zb))
			st.set_uv(Vector2(ua, 1.0)); st.add_vertex(Vector3(xa, top, za))
	var sh := Shader.new()
	sh.code = AURORA_SHADER
	_aurora_mat = ShaderMaterial.new()
	_aurora_mat.shader = sh
	_aurora = MeshInstance3D.new()
	_aurora.name = "Aurora"
	_aurora.mesh = st.commit()
	_aurora.material_override = _aurora_mat
	_aurora.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aurora.extra_cull_margin = 40000.0
	view.dynamic_root.add_child(_aurora)


func _exit_tree() -> void:
	if _aurora and is_instance_valid(_aurora):
		_aurora.queue_free()


func _report(area: String, x: float, z: float, to_go: float) -> void:
	var tas := maxf(float(ac.spec.cruise_tas) * U.KT, 60.0)
	var mins := int(to_go / tas / 60.0)
	var eta := "%d h %02d min" % [mins / 60, mins % 60] if mins >= 60 else "%d min" % mins
	var text := "Now over %s · local time %s · %s km and %s to %s" % [area, _local_time(x, z), U.fmt_int(int(to_go / 1000.0)), eta,
		String(Airports.get_ap(String(session.get("arr_icao"))).get("city", ""))]
	if session.has_signal("toast"):
		session.toast.emit(text, "info")


# ================================================================== the debrief
func debrief_notes() -> Array:
	var out := []
	var crossed := overflown.filter(func(a): return String(a) != "")
	if crossed.size() >= 2:
		out.append("Below you on the way: %s." % ", ".join(PackedStringArray(crossed)))
	if continents.size() >= 2:
		out.append("A %d-continent flight: %s." % [continents.size(), " to ".join(PackedStringArray(continents))])
	if crossed_equator:
		out.append("You crossed the equator.")
	if saw_aurora:
		out.append("The northern lights put on a show on the way.")
	if Geo.in_world_region(_dep.x, _dep.y) and Geo.in_world_region(_arr.x, _arr.y):
		var zones := int(round(absf(RealWorld.to_lonlat(_arr.x, _arr.y).x - RealWorld.to_lonlat(_dep.x, _dep.y).x) / 15.0))
		if zones >= 3:
			out.append("You crossed about %d time zones - expect jet lag tomorrow. Local time in %s is %s." % [zones, String(Airports.get_ap(String(session.get("arr_icao"))).get("city", "")), _local_time(_arr.x, _arr.y)])
	var km := int(_peak_dist / 1000.0)
	var best := int(Game.settings.get("longest_flight_km", 0))
	if km > 500 and km > best:
		Game.settings["longest_flight_km"] = km
		Game.save_settings()
		out.append("Your longest flight yet: %s km." % U.fmt_int(km))
	return out
