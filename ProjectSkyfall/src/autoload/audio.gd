extends Node
## Procedural audio. Every sound is synthesized at start-up into short seamless loops and
## one-shots (no recorded assets): turbofan whine and roar, propeller buzz, piston rumble, APU,
## airflow, runway rumble, rain, cabin hum, fire; chimes, master warning/caution, stall clacker,
## gear and touchdown thumps, tyre squeal, switch clicks, radio squelch, bangs, impacts, thunder
## and a soft generative pad for the menus. Loops are driven every frame from the aircraft state
## through pitch and volume, muffled by a low-pass when the camera is inside the aircraft.
## GPWS and cabin callouts use the platform text-to-speech voice.

const RATE := 22050

var _loops := {}          # name -> AudioStreamWAV
var _shots := {}          # name -> AudioStreamWAV
var _players := {}        # loop name -> AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var ac: Aircraft = null
var rig: Node = null
var _ready_done := false
var _warning_t := 0.0
var _caution_pending := false
var _gpws_last := {}
var _last_ra := 9999.0
var _callouts_done := {}
var _music: AudioStreamPlayer
var _belt_sign := false
var _rng := RandomNumberGenerator.new()
var _srng := RandomNumberGenerator.new()   # synthesis only (runs on a worker thread)
var _synth_task := -1
var _music_task := -1
var _music_stream: AudioStreamWAV = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 2027
	_srng.seed = 2027
	_synth_task = WorkerThreadPool.add_task(_synthesize, false, "audio synthesis")
	_setup_buses()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)


func _setup_buses() -> void:
	for b in ["SFX", "Engines", "Ambience", "Music", "UI"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master" if b in ["SFX", "Music", "UI"] else "SFX")
	var eng := AudioServer.get_bus_index("Engines")
	if AudioServer.get_bus_effect_count(eng) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(eng, lp)
	var amb := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var lp2 := AudioEffectLowPassFilter.new()
		lp2.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, lp2)
	apply_volumes()


func apply_volumes() -> void:
	var s: Dictionary = Game.settings if Game else {}
	var sfx := AudioServer.get_bus_index("SFX")
	var mus := AudioServer.get_bus_index("Music")
	if sfx == -1 or mus == -1:
		return      # buses not created yet; _ready applies the volumes
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(float(s.get("sfx_volume", 1.0)), 0.0001)))
	AudioServer.set_bus_volume_db(mus, linear_to_db(maxf(float(s.get("music_volume", 0.6)) * 0.5, 0.0001)))


func _ensure_assets() -> void:
	## Waits for the background synthesis started in _ready (or runs it now if it never started).
	if _ready_done:
		return
	if _synth_task != -1:
		WorkerThreadPool.wait_for_task_completion(_synth_task)
		_synth_task = -1
	else:
		_synthesize()
	_ready_done = true


func _synthesize() -> void:
	var t0 := Time.get_ticks_msec()
	var loops := {}
	var shots := {}
	# turbofan: fan blade-pass tone with its harmonics over a band of hiss
	loops.fan = _tone_loop(1.0, [[880.0, 0.5], [1760.0, 0.2], [2640.0, 0.08], [440.0, 0.16], [3520.0, 0.04]], 0.9, 900.0, 5500.0)
	# jet exhaust roar: broadband with slow turbulent swell
	loops.roar = _band_loop(2.0, true, 140.0, 2400.0, 2, 0.5, 0.15)
	loops.buzz = _buzz_loop(1.0, 96.0, 0.6)
	loops.piston = _piston_loop(1.0, 40.0)
	loops.apu = _tone_loop(1.0, [[1180.0, 0.4], [2360.0, 0.12], [590.0, 0.1]], 0.6, 600.0, 4000.0)
	loops.wind = _band_loop(3.0, true, 250.0, 2200.0, 1, 0.34, 0.3)
	loops.rumble = _rumble_loop(1.6)
	loops.rain = _rain_loop(2.0)
	# cabin: pack air and slipstream, mostly broadband low-mids with a faint tonal core
	loops.hum = _tone_loop(2.0, [[115.0, 0.08], [230.0, 0.06], [400.0, 0.03]], 1.0, 120.0, 900.0)
	loops.fire = _fire_loop(2.0)
	loops.gear_motor = _tone_loop(1.0, [[300.0, 0.4], [600.0, 0.22], [900.0, 0.1]], 0.35, 200.0, 1500.0)
	shots.chime = _chime([1046.5, 784.0], 0.5)
	shots.ding = _chime([1318.5], 0.6)
	shots.caution = _chime([880.0], 0.45)
	shots.warning = _warning_tone()
	shots.clacker = _clacker()
	shots.thump = _thump(0.4, 110.0, 45.0)
	shots.gear_lock = _clunk()
	shots.screech = _screech()
	shots.click = _click(0.012, 3200.0)
	shots.switch = _click(0.02, 1800.0)
	shots.squelch = _squelch()
	shots.bang = _bang()
	shots.impact = _impact()
	shots.thunder = _thunder()
	_loops = loops
	_shots = shots
	print("audio synthesized in %d ms" % (Time.get_ticks_msec() - t0))


# ================================================================== synthesis
static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _normalize(s: PackedFloat32Array, peak: float = 0.85) -> void:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in s.size():
		s[i] *= k


static func _seamless(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	## Crossfades the tail of an over-long buffer into its head so the loop has no click.
	var n := s.size() - fade
	var out := s.slice(0, n)
	for i in fade:
		var f := float(i) / fade
		out[i] = s[i] * f + s[n + i] * (1.0 - f)
	return out


static func _biquad(s: PackedFloat32Array, kind: String, f: float, q: float = 0.707) -> void:
	## RBJ biquad in place: "lp", "hp" or "bp" (0 dB peak).
	var w0 := TAU * clampf(f, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var b1 := 0.0
	var b2 := -alpha
	if kind == "lp":
		b0 = (1.0 - cw) * 0.5
		b1 = 1.0 - cw
		b2 = b0
	elif kind == "hp":
		b0 = (1.0 + cw) * 0.5
		b1 = -(1.0 + cw)
		b2 = b0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw / a0
	var a2 := (1.0 - alpha) / a0
	b0 /= a0
	b1 /= a0
	b2 /= a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in s.size():
		var x := s[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		s[i] = y


static func _band(s: PackedFloat32Array, lo: float, hi: float, stages: int = 1) -> void:
	for k in stages:
		if lo > 0.0:
			_biquad(s, "hp", lo)
		if hi > 0.0:
			_biquad(s, "lp", hi)


func _noise(n: int, pink: bool) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(n)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var w := _srng.randf_range(-1.0, 1.0)
		if pink:
			b0 = 0.99765 * b0 + w * 0.099
			b1 = 0.963 * b1 + w * 0.2965
			b2 = 0.57 * b2 + w * 1.0527
			s[i] = (b0 + b1 + b2 + w * 0.1848) * 0.25
		else:
			s[i] = w
	return s


static func _am(s: PackedFloat32Array, seconds: float, rate_hz: float, depth: float) -> void:
	## Slow amplitude swell with a whole number of cycles per loop (stays seamless).
	if depth <= 0.0:
		return
	var f := maxf(roundf(rate_hz * seconds), 1.0) / seconds
	var f2 := maxf(roundf(rate_hz * 2.7 * seconds), 1.0) / seconds
	for i in s.size():
		var t := float(i) / RATE
		s[i] *= 1.0 - depth * (0.5 + 0.35 * sin(TAU * f * t) + 0.15 * sin(TAU * f2 * t + 1.3))


func _band_loop(seconds: float, pink: bool, lo: float, hi: float, stages: int, am_hz: float, am_depth: float) -> AudioStreamWAV:
	var fade := int(RATE * 0.2)
	var s := _noise(int(RATE * seconds) + fade, pink)
	_band(s, lo, hi, stages)
	var out := _seamless(s, fade)
	_am(out, seconds, am_hz, am_depth)
	_normalize(out, 0.75)
	return _to_wav(out, true)


func _tone_loop(seconds: float, partials: Array, noise: float, lo: float, hi: float) -> AudioStreamWAV:
	## Tonal partials (whole cycles per loop) over band-limited noise.
	var n := int(RATE * seconds)
	var fade := int(RATE * 0.15)
	var nb := _noise(n + fade, true)
	_band(nb, lo, hi, 2)
	nb = _seamless(nb, fade)
	_normalize(nb, 1.0)
	var fr := []
	for p in partials:
		fr.append([roundf(float(p[0]) * seconds) / seconds, float(p[1]), _srng.randf() * TAU])
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p2 in fr:
			v += sin(TAU * float(p2[0]) * t + float(p2[2])) * float(p2[1])
		s[i] = v + nb[i] * noise * 0.5
	_normalize(s, 0.7)
	return _to_wav(s, true)


func _buzz_loop(seconds: float, f0: float, roughness: float) -> AudioStreamWAV:
	## Propeller blade-pass buzz: a band-limited sawtooth with a little throb.
	var n := int(RATE * seconds)
	var f := roundf(f0 * seconds) / seconds
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in range(1, 14):
			v += sin(TAU * f * k * t) / pow(k, 0.8) * (1.0 if k % 2 == 1 else 0.7)
		v *= 1.0 + roughness * 0.25 * sin(TAU * (f / 8.0) * t)
		s[i] = v
	_normalize(s, 0.7)
	return _to_wav(s, true)


func _piston_loop(seconds: float, f0: float) -> AudioStreamWAV:
	## Four-cylinder exhaust: a train of barks (band noise plus firing harmonics), uneven per cylinder.
	var n := int(RATE * seconds)
	var count := int(maxf(roundf(f0 * seconds / 4.0), 1.0)) * 4
	var period := float(n) / count
	var bark := _noise(n, false)
	_band(bark, 110.0, 950.0, 1)
	_normalize(bark, 1.0)
	var cyl := [1.0, 0.82, 0.93, 0.76]
	var f := count / seconds
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var k := fmod(float(i), period)
		var e := exp(-k / (period * 0.24))
		var c: float = cyl[int(float(i) / period) % 4]
		var t := float(i) / RATE
		s[i] = (bark[i] * 0.9 + sin(TAU * f * 2.0 * t) * 0.35 + sin(TAU * f * 3.0 * t) * 0.15) * e * c + sin(TAU * f * t) * 0.05
	_normalize(s, 0.75)
	return _to_wav(s, true)


func _rumble_loop(seconds: float) -> AudioStreamWAV:
	## Tyres on pavement: low band noise with the knock of joints and grooves.
	var fade := int(RATE * 0.15)
	var n := int(RATE * seconds) + fade
	var s := _noise(n, false)
	for i in n:
		s[i] *= 0.35
		if _srng.randf() < 0.0007:
			for k in 120:
				if i + k < n:
					s[i + k] += _srng.randf_range(-1.0, 1.0) * exp(-k / 25.0) * 3.0
	_band(s, 70.0, 420.0, 2)
	var out := _seamless(s, fade)
	_normalize(out, 0.75)
	return _to_wav(out, true)


func _rain_loop(seconds: float) -> AudioStreamWAV:
	var fade := int(RATE * 0.1)
	var n := int(RATE * seconds) + fade
	var s := _noise(n, false)
	for i in n:
		s[i] *= 0.3
		if _srng.randf() < 0.004:
			var a := _srng.randf_range(0.3, 1.0)
			for k in 50:
				if i + k < n:
					s[i + k] += _srng.randf_range(-1.0, 1.0) * exp(-k / 10.0) * a
	_band(s, 1100.0, 8500.0, 1)
	var out := _seamless(s, fade)
	_normalize(out, 0.6)
	return _to_wav(out, true)


func _fire_loop(seconds: float) -> AudioStreamWAV:
	## Flames: a breathing broadband roar with sharp crackles.
	var fade := int(RATE * 0.15)
	var n := int(RATE * seconds) + fade
	var s := _noise(n, true)
	_band(s, 160.0, 2600.0, 1)
	_normalize(s, 0.5)
	var cr := PackedFloat32Array()
	cr.resize(n)
	for i in n:
		if _srng.randf() < 0.0018:
			var a := _srng.randf_range(0.3, 1.0)
			for k in 90:
				if i + k < n:
					cr[i + k] += _srng.randf_range(-1.0, 1.0) * exp(-k / 14.0) * a
	_biquad(cr, "hp", 1200.0)
	for i in n:
		s[i] += cr[i]
	var out := _seamless(s, fade)
	_am(out, seconds, 1.5, 0.35)
	_normalize(out, 0.7)
	return _to_wav(out, true)


func _chime(freqs: Array, dur: float) -> AudioStreamWAV:
	var per := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(per * freqs.size())
	for j in freqs.size():
		var f := float(freqs[j])
		for i in per:
			var t := float(i) / RATE
			var e := exp(-t * 3.2) * minf(t * 200.0, 1.0)
			s[j * per + i] = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.01 * t) + 0.12 * sin(TAU * f * 3.0 * t)) * e
	_normalize(s, 0.6)
	return _to_wav(s, false)


func _warning_tone() -> AudioStreamWAV:
	## Continuous repetitive chime (master warning).
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t, 0.5)
		var e := exp(-ph * 9.0) * minf(ph * 300.0, 1.0)
		s[i] = (sin(TAU * 1500.0 * t) * 0.6 + sin(TAU * 750.0 * t) * 0.4) * e
	_normalize(s, 0.55)
	return _to_wav(s, false)


func _clacker() -> AudioStreamWAV:
	## Stall warning clacker: a mechanical rattle at 14 Hz.
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var period := int(RATE / 14.0)
	for i in n:
		var k := i % period
		s[i] = _srng.randf_range(-1.0, 1.0) * exp(-float(k) / 110.0) + sin(TAU * 520.0 * k / RATE) * exp(-float(k) / 160.0) * 0.6
	_band(s, 300.0, 3500.0, 1)
	_normalize(s, 0.6)
	return _to_wav(s, false)


func _thump(dur: float, f_start: float, f_end: float) -> AudioStreamWAV:
	## Touchdown: a falling low thud with a burst of gear and structure noise.
	var n := int(RATE * dur)
	var body := _noise(n, false)
	_band(body, 90.0, 800.0, 1)
	_normalize(body, 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f_start, f_end, minf(t / dur * 2.0, 1.0))
		ph += TAU * f / RATE
		s[i] = (sin(ph) * exp(-t * 9.0) + body[i] * 1.3 * exp(-t * 13.0)) * minf(t * 800.0, 1.0)
	_normalize(s, 0.9)
	return _to_wav(s, false)


func _clunk() -> AudioStreamWAV:
	## Gear uplock / downlock: short metallic clunk.
	var n := int(RATE * 0.2)
	var s := _noise(n, false)
	for i in n:
		var t := float(i) / RATE
		s[i] = (s[i] * 0.8 + sin(TAU * 170.0 * t) * 0.8 + sin(TAU * 610.0 * t) * 0.25) * exp(-t * 28.0)
	_band(s, 120.0, 2500.0, 1)
	_normalize(s, 0.85)
	return _to_wav(s, false)


func _screech() -> AudioStreamWAV:
	## Tyre chirp: a gliding squeal over band noise.
	var n := int(RATE * 0.4)
	var nb := _noise(n, false)
	_biquad(nb, "bp", 1900.0, 3.0)
	_normalize(nb, 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(2300.0, 1650.0, t / 0.4) / RATE
		var e := exp(-t * 7.0) * minf(t * 120.0, 1.0)
		s[i] = (nb[i] * 0.7 + sin(ph) * 0.3 + sin(ph * 1.5) * 0.1) * e
	_normalize(s, 0.55)
	return _to_wav(s, false)


func _click(dur: float, f: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * f * t) * 0.6 + _srng.randf_range(-0.4, 0.4)) * exp(-t * 400.0)
	_normalize(s, 0.5)
	return _to_wav(s, false)


func _squelch() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := _noise(n, false)
	_band(s, 1500.0, 6000.0, 1)
	for i in n:
		s[i] *= exp(-float(i) / RATE * 30.0) * minf(float(i) / 40.0, 1.0)
	_normalize(s, 0.35)
	return _to_wav(s, false)


func _bang() -> AudioStreamWAV:
	## Compressor stall / structural bang: sharp attack, short boom.
	var n := int(RATE * 0.6)
	var s := _noise(n, false)
	_band(s, 60.0, 1400.0, 1)
	for i in n:
		var t := float(i) / RATE
		s[i] = (s[i] + sin(TAU * 70.0 * t) * 0.5) * exp(-t * 9.0) * minf(t * 1500.0, 1.0)
	_normalize(s, 0.95)
	return _to_wav(s, false)


func _impact() -> AudioStreamWAV:
	## Crash: a heavy boom, then tearing metal and debris over a long low rumble.
	var n := int(RATE * 2.8)
	var boom := _noise(n, false)
	_band(boom, 40.0, 500.0, 2)
	_normalize(boom, 1.0)
	var tear := _noise(n, false)
	_biquad(tear, "bp", 1500.0, 1.2)
	_normalize(tear, 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var grain := 0.0
	for i in n:
		var t := float(i) / RATE
		if _srng.randf() < 0.004 * exp(-t * 1.2):
			grain = _srng.randf_range(0.4, 1.0)
		grain *= 0.9993
		s[i] = boom[i] * exp(-t * 1.6) * minf(t * 1500.0, 1.0) + tear[i] * grain * 0.55 + sin(TAU * 55.0 * t) * exp(-t * 6.0) * 0.6
	_normalize(s, 0.95)
	return _to_wav(s, false)


func _thunder() -> AudioStreamWAV:
	## Distant thunder: a crack that rolls into a long, uneven rumble.
	var n := int(RATE * 4.0)
	var s := _noise(n, false)
	_band(s, 35.0, 420.0, 2)
	_normalize(s, 1.0)
	var swells := []
	for k in 4:
		swells.append([_srng.randf_range(0.0, 2.2), _srng.randf_range(0.4, 1.0)])
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 1.6) * 0.8
		for sw in swells:
			var d := t - float(sw[0])
			if d > 0.0:
				env += float(sw[1]) * exp(-d * 1.4) * minf(d * 6.0, 1.0) * 0.6
		s[i] *= env * minf(t * 300.0, 1.0)
	_normalize(s, 0.85)
	return _to_wav(s, false)


# ================================================================== playback
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	_ensure_assets()
	if not _shots.has(name):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _shots[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	p.play()


func _loop_player(name: String, bus: String) -> AudioStreamPlayer:
	if _players.has(name):
		return _players[name]
	var p := AudioStreamPlayer.new()
	p.stream = _loops[name]
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play()
	_players[name] = p
	return p


func _set_loop(name: String, bus: String, volume: float, pitch: float) -> void:
	var p := _loop_player(name, bus)
	p.volume_db = linear_to_db(maxf(volume, 0.00001))
	p.pitch_scale = clampf(pitch, 0.05, 4.0)


func attach(aircraft: Aircraft, camera_rig: Node) -> void:
	_ensure_assets()
	detach()
	ac = aircraft
	rig = camera_rig
	_callouts_done.clear()
	_last_ra = 9999.0
	_belt_sign = bool(ac.sys.lights.get("seatbelt", false))
	ac.touchdown.connect(_on_touchdown)
	ac.gear_changed.connect(func(_down):
		play("gear_lock", -8.0, 0.9)
		_set_loop("gear_motor", "Engines", 0.25, 1.0)
		get_tree().create_timer(7.0).timeout.connect(func():
			if _players.has("gear_motor"):
				_players.gear_motor.volume_db = -80.0
			play("gear_lock", -4.0, 1.0)))
	ac.sys.alert.connect(func(_id, level, _text):
		if level >= 2:
			_warning_t = 3.0
		elif level == 1:
			play("caution", -6.0))
	ac.crashed.connect(func(_info):
		play("impact", 0.0)
		_set_loop("fire", "Ambience", 0.0, 1.0))
	ac.incident.connect(func(kind, _info):
		if kind in ["tailstrike", "wingstrike", "engine_strike", "gear_collapse"]:
			play("bang", -2.0, 0.8))


func detach() -> void:
	for k in _players.keys():
		(_players[k] as AudioStreamPlayer).queue_free()
	_players.clear()
	ac = null
	rig = null


func _on_touchdown(info: Dictionary) -> void:
	var vs := absf(float(info.get("vs_fpm", 200.0)))
	play("thump", linear_to_db(clampf(vs / 500.0, 0.25, 1.4)), 0.9)
	play("screech", -6.0 + clampf(vs / 200.0, 0.0, 4.0), _rng.randf_range(0.9, 1.1))


func click() -> void:
	play("click", -10.0, _rng.randf_range(0.9, 1.15), "UI")


func squelch() -> void:
	play("squelch", -14.0, 1.0, "UI")


func thunder(dist: float) -> void:
	get_tree().create_timer(dist / 340.0).timeout.connect(func(): play("thunder", linear_to_db(clampf(3000.0 / maxf(dist, 300.0), 0.05, 1.0)), _rng.randf_range(0.8, 1.1)))


func callout(text: String, key: String = "", cooldown: float = 6.0) -> void:
	## GPWS / aircraft voice through text-to-speech.
	var k := key if key != "" else text
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_gpws_last.get(k, -100.0)) < cooldown:
		return
	_gpws_last[k] = now
	if not bool(Game.settings.get("tts", true)) or not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return
	DisplayServer.tts_speak(text, voices[0], int(clampf(float(Game.settings.get("voice_volume", 1.0)) * 100.0, 0.0, 100.0)), 1.0, 1.25)


# ================================================================== per frame
func _process(delta: float) -> void:
	_poll_music()
	if ac == null or not is_instance_valid(ac):
		ac = null
		return
	var sys := ac.sys
	var fdm := ac.fdm
	var inside := rig != null and is_instance_valid(rig) and String(rig.get("mode")) in ["cockpit", "cabin", "walk"]
	var cam: Camera3D = rig.get("cam") if rig else null
	var dist := 30.0
	if cam and not inside:
		dist = cam.global_position.distance_to(ac.global_position)
	var att := 1.0 if inside else clampf(60.0 / maxf(dist, 20.0), 0.02, 1.4)
	var lp_hz := 2200.0 if inside else clampf(18000.0 - dist * 6.0, 2500.0, 18000.0)
	var bus := AudioServer.get_bus_index("Engines")
	(AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter).cutoff_hz = lp_hz
	var amb := AudioServer.get_bus_index("Ambience")
	(AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter).cutoff_hz = 3500.0 if inside else 16000.0
	# engines
	var etype := String(ac.spec.engine_type)
	var n1 := 0.0
	var thrust := 0.0
	for e in sys.eng:
		n1 = maxf(n1, float(e.n1))
		thrust += absf(float(e.thrust))
	var tnorm := clampf(thrust / maxf(float(ac.spec.static_thrust) * sys.n_eng, 1.0), 0.0, 1.0)
	if etype == "turbofan":
		_set_loop("fan", "Engines", (0.08 + n1 / 100.0 * 0.5) * att * (0.55 if inside else 1.0) * clampf(n1 / 8.0, 0.0, 1.0), 0.35 + n1 / 100.0 * 1.15)
		_set_loop("roar", "Engines", (0.05 + tnorm * 0.9) * att * clampf(n1 / 20.0, 0.0, 1.0), 0.75 + tnorm * 0.5)
	elif etype == "turboprop":
		_set_loop("buzz", "Engines", (0.1 + tnorm * 0.6) * att * clampf(n1 / 15.0, 0.0, 1.0), 0.55 + n1 / 100.0 * 0.6)
		_set_loop("fan", "Engines", 0.12 * att * clampf(n1 / 15.0, 0.0, 1.0), 0.6 + n1 / 100.0 * 0.8)
	else:
		var rpm := 0.0
		for e2 in sys.eng:
			rpm = maxf(rpm, float(e2.get("rpm", float(e2.n1) * 27.0)))
		_set_loop("piston", "Engines", (0.15 + tnorm * 0.7) * att * clampf(n1 / 10.0, 0.0, 1.0), 0.45 + rpm / 2700.0 * 0.85)
	_set_loop("apu", "Engines", (0.12 if sys.apu_n > 5.0 else 0.0) * sys.apu_n / 100.0 * (0.4 if inside else att), 0.5 + sys.apu_n / 200.0)
	# airflow, runway, weather, cabin
	var ias := fdm.ias / U.KT
	_set_loop("wind", "Ambience", clampf(pow(ias / 260.0, 2.0), 0.0, 1.0) * (0.55 if inside else 0.3) + float(ac.turbulence) * 0.15, 0.6 + ias / 400.0)
	_set_loop("rumble", "Ambience", clampf(fdm.ground_speed() / 60.0, 0.0, 1.0) * (0.7 if fdm.on_ground else 0.0), 0.7 + fdm.ground_speed() / 150.0)
	var precip := String(ac.weather.get("precip", "none"))
	_set_loop("rain", "Ambience", (0.35 if precip in ["rain", "thunderstorm"] and ac.in_cloud or (precip != "none" and ac.ra < 1500.0) else 0.0), 1.0)
	_set_loop("hum", "Ambience", 0.12 if inside and sys.ac_power else 0.0, 1.0)
	_set_loop("fire", "Ambience", 0.6 * att if bool(ac.damage.get("fire", false)) or ac.crashed_state else 0.0, 1.0)
	# alerts
	if _warning_t > 0.0 or sys.master_warning:
		_warning_t -= delta
		if not _pool.any(func(p): return p.playing and p.stream == _shots.get("warning")):
			play("warning", -4.0)
	if sys.stall_warning and not fdm.on_ground and not _pool.any(func(p): return p.playing and p.stream == _shots.get("clacker")):
		play("clacker", -3.0)
		callout("Stall, stall", "stall", 3.0)
	# cabin signs: the familiar single ding when the seat-belt sign changes
	var belt := bool(sys.lights.get("seatbelt", false))
	if belt != _belt_sign:
		_belt_sign = belt
		if sys.ac_power or sys.battery:
			play("ding", -10.0 if inside else -24.0)
	_gpws(delta)


func _gpws(_delta: float) -> void:
	## Radio altitude callouts on approach and the basic ground proximity warnings.
	if ac.spec.category == "trainer" or ac.fdm.on_ground:
		_last_ra = ac.ra
		if ac.fdm.on_ground:
			_callouts_done.clear()
		return
	var ra_ft := ac.ra / U.FT
	var vs_fpm := ac.fdm.vel.y / U.FPM
	if vs_fpm < -200.0:
		for h in [1000, 500, 100, 50, 40, 30, 20, 10]:
			if ra_ft <= h and _last_ra / U.FT > h and not _callouts_done.has(h):
				_callouts_done[h] = true
				callout(("One thousand" if h == 1000 else ("Five hundred" if h == 500 else ("One hundred" if h == 100 else str(h)))), "ra%d" % h, 2.0)
				if h == 20 and ac.ap.vert_mode != "FLARE" and ac.throttle_lever > 0.15:
					callout("Retard, retard", "retard", 3.0)
	if ra_ft < 2500.0 and ra_ft > 50.0:
		if vs_fpm < -min(6000.0, 1500.0 + ra_ft * 1.6):
			callout("Pull up", "pullup", 2.5)
		elif vs_fpm < -min(5000.0, 1000.0 + ra_ft * 1.1):
			callout("Sink rate", "sink", 4.0)
		if not ac.sys.gear_down_cmd and ra_ft < 500.0 and bool(ac.spec.gear_retract) and ac.fdm.ias / U.KT < 190.0:
			callout("Too low, gear", "gear", 5.0)
	_last_ra = ac.ra


# ================================================================== menu music
var _music_want := false
var _music_tween: Tween


func music(on: bool) -> void:
	_music_want = on
	if _music_tween:
		_music_tween.kill()
	if not on:
		if _music.playing:
			_music_tween = create_tween()
			_music_tween.tween_property(_music, "volume_db", -60.0, 1.5)
			_music_tween.tween_callback(_music.stop)
		return
	if _music_stream == null:
		if _music_task == -1:
			_music_task = WorkerThreadPool.add_task(func(): _music_stream = _pad_music(), false, "menu music")
		return      # _process starts it once the worker has finished
	_start_music()


func _start_music() -> void:
	if _music.stream == null:
		_music.stream = _music_stream
	if not _music.playing:
		_music.volume_db = -60.0
		_music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -6.0, 3.0)


func _poll_music() -> void:
	if _music_task != -1 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		if _music_want:
			_start_music()


static func _pad_music() -> AudioStreamWAV:
	## A slow, warm progression (Imaj7 - vi9 - IVmaj7 - V6/4): detuned soft pad, a low bass and a
	## gentle bell arpeggio in eighth notes. 16 seconds, loops seamlessly.
	var chords := [[261.63, 329.63, 392.0, 493.88], [220.0, 261.63, 329.63, 493.88], [174.61, 220.0, 261.63, 329.63], [196.0, 246.94, 293.66, 392.0]]
	var arp := [0, 1, 2, 3, 2, 1, 2, 3]
	var bar := 4.0
	var n := int(RATE * bar * chords.size())
	var pad := PackedFloat32Array()
	pad.resize(n)
	var bell := PackedFloat32Array()
	bell.resize(n)
	var step := int(bar / 8.0 * RATE)
	for ci in chords.size():
		var notes: Array = chords[ci]
		var start := int(ci * bar * RATE)
		var len := int(bar * RATE)
		for k in len:
			var t := float(k) / RATE
			var env := minf(t / 1.2, 1.0) * minf((bar - t) / 1.0, 1.0)
			var v := 0.0
			for f in notes:
				var ff := float(f)
				v += sin(TAU * ff * t) * 0.45 + sin(TAU * ff * 1.004 * t + 1.0) * 0.3 + sin(TAU * ff * 2.0 * t + 0.5) * 0.06
			v += sin(TAU * float(notes[0]) * 0.5 * t) * 0.55 + sin(TAU * float(notes[0]) * 0.25 * t) * 0.25
			pad[start + k] = v * env
		# bell arpeggio, an octave up, every other bar slightly varied
		for e in 8:
			var f2 := float(notes[arp[(e + ci) % 8]]) * 2.0
			var s0 := start + e * step
			var amp := 0.55 if e % 2 == 0 else 0.4
			for k2 in int(1.6 * RATE):
				var idx := (s0 + k2) % n
				var t2 := float(k2) / RATE
				var env2 := exp(-t2 * 2.6) * minf(t2 * 400.0, 1.0)
				bell[idx] += (sin(TAU * f2 * t2) + 0.25 * sin(TAU * f2 * 2.0 * t2) + 0.08 * sin(TAU * f2 * 3.01 * t2)) * env2 * amp
	_biquad(pad, "lp", 1600.0)
	_biquad(bell, "lp", 4500.0)
	for i in n:
		pad[i] = pad[i] * 0.55 + bell[i] * 0.35
	_normalize(pad, 0.5)
	return _to_wav(pad, true)
