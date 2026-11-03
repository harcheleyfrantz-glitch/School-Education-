class_name WeatherHazards
extends Node
## Natural hazards during a flight, on top of wind and turbulence:
##  - earthquakes: the ground shakes (hard on the runway), dust and fires rise over the city,
##    cracks open across a runway, ATC closes it, and aftershocks follow
##  - volcanic ash: sulphur smell, St Elmo's fire, then every engine flames out; they relight
##    once the aircraft has descended out of the ash
##  - hail: hammering on the airframe until the windscreen cracks
##  - lightning strikes in thunderstorms: a flash, a bang and sometimes a lost generator
## Everything that happens is logged for the debrief and the news.

signal hazard(kind: String, text: String)

var session: Node
var ac: Aircraft
var view: WorldView
var events_log: Array = []                 # [{kind, text, clock, ...}] for the news and the debrief
var quake := {}                     # the active earthquake: {t, dur, mag, icao}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _ash_t := 0.0
var _ash_stage := 0
var _hail_t := 0.0
var _hail_cracked := false
var _bolt_t := 0.0
var _quake_t := -1.0
var _aftershocks: Array = []
var _fx: Array = []
var _main_mag := 6.5


func setup(sess: Node, aircraft: Aircraft, world_view: WorldView) -> void:
	session = sess
	ac = aircraft
	view = world_view
	_rng.seed = U.hash_str(String(sess.get("flight_id")) + "hazards")
	_bolt_t = _rng.randf_range(40.0, 140.0)
	if WeatherModel.override_preset == "earthquake":
		_quake_t = _rng.randf_range(25.0, 70.0)


func _preset() -> String:
	return WeatherModel.override_preset


func _say(kind: String, text: String, level: String = "warning") -> void:
	events_log.append({"kind": kind, "text": text, "clock": WorldSim.clock})
	hazard.emit(kind, text)
	if session.has_signal("toast"):
		session.toast.emit(text, level)
	var rec = session.get("recorder")
	if rec:
		rec.mark("hazard", text)


func _atc(text: String) -> void:
	var atc: Node = session.get("atc")
	if atc and atc.has_method("traffic_advisory"):
		atc.call("traffic_advisory", text, text)


func _process(delta: float) -> void:
	if ac == null or ac.crashed_state:
		return
	_t += delta
	var agl := float(ac.ra)
	var p := _preset()
	# ---------------------------------------------------------------- earthquakes
	if _quake_t >= 0.0:
		_quake_t -= delta
		if _quake_t < 0.0:
			start_quake(_rng.randf_range(6.4, 7.6), true)
	for i in range(_aftershocks.size() - 1, -1, -1):
		_aftershocks[i] = float(_aftershocks[i]) - delta
		if float(_aftershocks[i]) <= 0.0:
			_aftershocks.remove_at(i)
			if quake.is_empty():
				start_quake(_main_mag - _rng.randf_range(1.0, 1.8), false)
	if not quake.is_empty():
		_update_quake(delta)
	# ---------------------------------------------------------------- volcanic ash
	if p == "volcanic_ash" and not ac.fdm.on_ground:
		var in_ash := ac.fdm.pos.y > 2500.0
		if in_ash:
			_ash_t += delta
		if _ash_stage == 0 and _ash_t > 20.0:
			_ash_stage = 1
			_say("ash", "A smell of sulphur fills the cockpit and blue St Elmo's fire dances across the windscreen. You are in volcanic ash.")
		elif _ash_stage == 1 and _ash_t > 42.0:
			_ash_stage = 2
			for i in ac.sys.n_eng:
				get_tree().create_timer(1.5 * i).timeout.connect(func():
					if is_instance_valid(ac) and not ac.crashed_state:
						ac.sys.fail("eng_flameout", i))
			_say("ash", "ALL ENGINES HAVE FLAMED OUT. Volcanic ash has choked the engines. Descend out of the ash cloud - below 8,000 feet - to relight them.", "warning")
			_atc("%s, roger your emergency. Turn left heading 180, descend at your discretion, the ash is reported tops one five thousand." % String(session.get("callsign")))
		elif _ash_stage == 2 and not in_ash:
			_ash_stage = 3
			for e in ac.sys.eng:
				if not bool(e.running) and String(e.failed) == "flameout":
					e.starting = true
			_say("ash", "Out of the ash. Relight attempt... the engines are spooling back up.", "success")
	# ---------------------------------------------------------------- hail
	if p == "hail" and not ac.fdm.on_ground and agl > 150.0:
		_hail_t += delta
		if fmod(_hail_t, 0.6) < delta:
			var rig = session.get("rig")
			if rig:
				rig.add_shake(0.15)
		if not _hail_cracked and _hail_t > 25.0:
			_hail_cracked = true
			ac.damage["windshield"] = true
			ac.damage["radome"] = true
			_say("hail", "Hailstones the size of golf balls are hammering the aircraft. The captain's windscreen has cracked and the nose cone is dented.")
	# ---------------------------------------------------------------- lightning
	var stormy := p in ["storm", "hurricane", "tornado", "hail"] or String(ac.weather.get("precip", "")) == "thunderstorm"
	if stormy and not ac.fdm.on_ground and agl > 300.0:
		_bolt_t -= delta * (1.6 if ac.in_cloud else 0.6)
		if _bolt_t <= 0.0:
			_bolt_t = _rng.randf_range(70.0, 220.0)
			_lightning()


# ================================================================== lightning
func _lightning() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.85, 0.9, 1.0)
	flash.light_energy = 40.0
	flash.omni_range = 400.0
	view.dynamic_root.add_child(flash)
	flash.global_position = ac.global_position + Vector3(0, 10, 0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	var rig = session.get("rig")
	if rig:
		rig.add_shake(1.2)
	if _rng.randf() < 0.25 and ac.sys.has_method("fail"):
		ac.sys.fail("gen", _rng.randi() % maxi(ac.sys.n_eng, 1))
		_say("lightning", "LIGHTNING STRIKE! A deafening bang and a flash of white - a generator has dropped off line.")
	else:
		_say("lightning", "Lightning strike! A blinding flash and a loud bang. The systems check out normal.", "caution")


# ================================================================== earthquakes
func start_quake(mag: float, main_shock: bool) -> void:
	## A quake centred near the closest airport: strongest on the ground, felt as turbulence low
	## down, invisible from cruise apart from the dust and fires over the city.
	var icao := Airports.nearest(ac.world_x(), ac.world_z())
	if icao == "":
		return
	mag = clampf(mag, 4.5, 8.2)
	quake = {"t": 0.0, "dur": 14.0 + (mag - 5.0) * 9.0, "mag": mag, "icao": icao}
	var ap := Airports.get_ap(icao)
	var city := String(ap.get("city", ap.get("short", icao)))
	var text := "EARTHQUAKE! A magnitude %.1f earthquake is shaking %s." % [mag, city] if main_shock else "Aftershock! Magnitude %.1f near %s." % [mag, city]
	_say("earthquake", text, "warning")
	events_log[events_log.size() - 1]["mag"] = mag
	events_log[events_log.size() - 1]["icao"] = icao
	events_log[events_log.size() - 1]["main"] = main_shock
	events_log[events_log.size() - 1]["alt"] = 0.0 if ac.fdm.on_ground else float(ac.ra)
	if main_shock:
		_main_mag = mag
		_aftershocks = [_rng.randf_range(70.0, 120.0), _rng.randf_range(160.0, 260.0)]
		_quake_damage(icao, mag)


func _quake_damage(icao: String, mag: float) -> void:
	var ap := Airports.get_ap(icao)
	var cc := Airports.city_center(icao)
	var r := float(ap.get("city_info", {}).get("radius", 4000.0))
	var wind := Vector3(2, 0, 1)
	# dust from collapsing buildings and a few fires in the city
	for k in clampi(int((mag - 5.5) * 5.0), 2, 10):
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.1, 0.8) * r
		var x := cc.x + cos(a) * d
		var z := cc.y + sin(a) * d
		var fire := _rng.randf() < 0.35
		var col := NewsFX.smoke_column(1.0 + mag * 0.1, wind, 1.0 if fire else 0.35, 90)
		view.dynamic_root.add_child(col)
		col.position = view.world_to_local(x, Geo.ground_height(x, z) + 5.0, z)
		_fx.append(col)
		if fire:
			var f := NewsFX.flames(1.4)
			view.dynamic_root.add_child(f)
			f.position = view.world_to_local(x, Geo.ground_height(x, z) + 1.0, z)
			_fx.append(f)
	# cracks across a runway: it is closed for inspection
	var closed := ""
	var rw_list: Array = ap.get("runways", [])
	if mag >= 6.3 and not rw_list.is_empty():
		var rw: Dictionary = rw_list[_rng.randi() % rw_list.size()]
		closed = String(rw.id)
		var hdg := deg_to_rad(float(rw.hdg))
		var dirv := Vector2(sin(hdg), -cos(hdg))
		var side := Vector2(-dirv.y, dirv.x)
		var c := Vector2(float(ap.x), float(ap.z)) + side * float(rw.get("off", 0.0)) + dirv * float(rw.get("along", 0.0))
		for k in 3:
			var p := c + dirv * _rng.randf_range(-0.35, 0.35) * float(rw.len)
			var dc := NewsFX.decal("scar", Vector3(float(rw.wid) * 1.6, 20.0, _rng.randf_range(18.0, 40.0)))
			view.dynamic_root.add_child(dc)
			dc.position = view.world_to_local(p.x, Geo.ground_height(p.x, p.y), p.y)
			dc.rotation.y = -hdg + PI * 0.5 + _rng.randf_range(-0.3, 0.3)
			_fx.append(dc)
	if closed != "":
		events_log[events_log.size() - 1]["closed"] = closed
		get_tree().create_timer(6.0).timeout.connect(func():
			_atc("All stations, %s tower. Following the earthquake, runway %s is closed - cracks reported on the surface. Expect delays. Other runways are being inspected." % [String(ap.get("short", icao)), closed]))


func _update_quake(delta: float) -> void:
	quake.t = float(quake.t) + delta
	var f := float(quake.t) / float(quake.dur)
	if f >= 1.0:
		quake = {}
		return
	# a sharp onset, a long rolling peak, a fading tail
	var env := clampf(f * 6.0, 0.0, 1.0) * clampf((1.0 - f) * 2.5, 0.0, 1.0)
	var k := env * pow(10.0, (float(quake.mag) - 6.0) * 0.5) * 0.6
	var agl := float(ac.ra)
	var rig = session.get("rig")
	if ac.fdm.on_ground or agl < 5.0:
		if rig:
			rig.add_shake(k * 1.6 * delta * 10.0)
		ac.fdm.vel += Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * k * 3.0 * delta
	elif agl < 300.0:
		if rig:
			rig.add_shake(k * 0.2 * delta * 10.0)


func summary() -> Dictionary:
	## What the news should know.
	var out := {}
	for l in events_log:
		var kd := String(l.kind)
		if kd == "earthquake" and bool(l.get("main", false)):
			out.earthquake = l
		elif kd in ["ash", "hail", "lightning"]:
			out[kd] = l
	return out
