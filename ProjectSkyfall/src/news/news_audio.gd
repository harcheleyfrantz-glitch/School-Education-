class_name NewsAudio
extends RefCounted
## Sound for the news videos, synthesised once on a worker thread: the channel sting, music
## beds (news pulse, tension, somber), transition whooshes, a distant impact, camera shutters,
## and ambience loops (news helicopter, sirens and crowd, wind, outdoor, press room, vigil,
## airport, terminal). No audio files.

const RATE := 22050

static var _streams := {}
static var _task := -1
static var _done := false


static func prepare() -> void:
	if _done or _task != -1:
		return
	_task = WorkerThreadPool.add_task(_synth_all, false, "news audio")


static func is_ready() -> bool:
	if _done:
		return true
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_done = true
	return _done


static func stream(name: String) -> AudioStream:
	if not is_ready():
		return null
	return _streams.get(name, null)


static func _synth_all() -> void:
	var s := {}
	var r := RandomNumberGenerator.new()
	r.seed = 4401
	s.sting = _wav(_sting(r), false)
	s.outro = _wav(_outro(r), false)
	s.whoosh = _wav(_whoosh(r, 1.1), false)
	s.impact = _wav(_impact(r), false)
	s.shutter = _wav(_shutter(r), false)
	s.bed = _wav(_bed(r), true)
	s.tension = _wav(_tension(r), true)
	s.somber = _wav(_somber(r), true)
	s.heli = _wav(_heli(r), true)
	s.sirens = _wav(_sirens(r), true)
	s.wind = _wav(_wind(r, 6.0, 0.8), true)
	s.outdoor = _wav(_outdoor(r), true)
	s.room = _wav(_room(r), true)
	s.candles = _wav(_vigil(r), true)
	s.airport = _wav(_airport(r), true)
	s.terminal = _wav(_terminal(r), true)
	_streams = s


# ================================================================== helpers
static func _wav(src: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(src.size() * 2)
	for i in src.size():
		bytes.encode_s16(i * 2, int(clampf(src[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = src.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * RATE))
	a.fill(0.0)
	return a


static func _noise(r: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = r.randf_range(-1.0, 1.0)
	return a


static func _biquad(src: PackedFloat32Array, kind: String, f: float, q: float = 0.707) -> PackedFloat32Array:
	var w0 := TAU * clampf(f, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	match kind:
		"lp":
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
		"hp":
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
		_:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	b0 /= a0
	b1 /= a0
	b2 /= a0
	a1 /= a0
	a2 /= a0
	var out := PackedFloat32Array()
	out.resize(src.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in src.size():
		var x := src[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y
	return out


static func _norm(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in a.size():
		a[i] *= k
	return a


static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	for i in src.size():
		var j := at + i
		if j >= 0 and j < dst.size():
			dst[j] += src[i] * gain


## Wraps the tail of a buffer over its head so it loops without a click.
static func _loopify(a: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var fade := int(fade_s * RATE)
	var n := a.size() - fade
	var out := a.slice(0, n)
	for i in fade:
		var k := float(i) / fade
		out[i] = a[i] * k + a[n + i] * (1.0 - k)
	return out


static func _tone(freq: float, seconds: float, harmonics: int, attack: float, decay: float, bright: float = 1.0) -> PackedFloat32Array:
	var a := _buf(seconds)
	for i in a.size():
		var t := float(i) / RATE
		var env := minf(t / maxf(attack, 0.001), 1.0) * exp(-t / maxf(decay, 0.01))
		var v := 0.0
		for h in range(1, harmonics + 1):
			v += sin(TAU * freq * h * t + h * 0.7) / pow(float(h), 1.0 + (1.0 - bright))
		a[i] = v * env
	return a


static func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


# ================================================================== music and stings
static func _sting(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(4.2)
	# riser into the hit
	var rise := _noise(r, int(1.05 * RATE))
	var rs := PackedFloat32Array()
	rs.resize(rise.size())
	var y := 0.0
	for i in rise.size():
		var k := float(i) / rise.size()
		var cut := 0.02 + k * k * 0.5
		y += (rise[i] - y) * cut
		rs[i] = y * k * k
	_mix(out, rs, 0, 0.9)
	var hit := int(1.0 * RATE)
	# low boom
	var boom := _buf(1.8)
	for i2 in boom.size():
		var t := float(i2) / RATE
		var f := 48.0 + 50.0 * exp(-t * 9.0)
		boom[i2] = sin(TAU * f * t) * exp(-t * 2.2)
	_mix(out, boom, hit, 1.0)
	# brass-like chord stabs: D major, then a second stab a fifth higher
	for stab in [[0.0, [50, 57, 62, 66, 69]], [0.5, [52, 59, 64, 68, 71]], [1.0, [50, 57, 62, 66, 74]]]:
		for n in stab[1]:
			var tone := _tone(_midi(float(n)), 1.9, 9, 0.012, 0.55 if float(stab[0]) < 0.9 else 1.1, 0.7)
			_mix(out, tone, hit + int(float(stab[0]) * RATE), 0.16)
	# timpani rolls
	for k2 in 6:
		var tp := _buf(0.8)
		for i3 in tp.size():
			var t2 := float(i3) / RATE
			tp[i3] = (sin(TAU * 73.4 * t2) + 0.4 * sin(TAU * 110.0 * t2)) * exp(-t2 * 6.0) + r.randf_range(-1, 1) * exp(-t2 * 40.0) * 0.4
		_mix(out, tp, hit - int(0.35 * RATE) + k2 * int(0.06 * RATE), 0.18 + k2 * 0.04)
	# cymbal
	var cy := _biquad(_noise(r, int(2.6 * RATE)), "hp", 5000.0)
	for i4 in cy.size():
		cy[i4] *= exp(-float(i4) / RATE * 1.8)
	_mix(out, cy, hit, 0.35)
	return _norm(_biquad(out, "lp", 9000.0), 0.9)


static func _outro(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(3.0)
	for n in [50, 57, 62, 66, 69, 74]:
		_mix(out, _tone(_midi(float(n)), 2.8, 8, 0.02, 0.9, 0.6), 0, 0.15)
	var boom := _buf(1.5)
	for i in boom.size():
		var t := float(i) / RATE
		boom[i] = sin(TAU * (50.0 + 30.0 * exp(-t * 10.0)) * t) * exp(-t * 3.0)
	_mix(out, boom, 0, 0.8)
	_mix(out, _whoosh(r, 0.8), int(0.05 * RATE), 0.3)
	return _norm(out, 0.85)


static func _whoosh(r: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var n := _noise(r, int(seconds * RATE))
	var out := PackedFloat32Array()
	out.resize(n.size())
	var y := 0.0
	var y2 := 0.0
	for i in n.size():
		var k := float(i) / n.size()
		var env := sin(PI * pow(k, 0.7))
		var cut := 0.03 + 0.4 * env
		y += (n[i] - y) * cut
		y2 += (y - y2) * cut
		out[i] = (y - y2 * 0.5) * env
	return _norm(out, 0.8)


static func _bed(r: RandomNumberGenerator) -> PackedFloat32Array:
	## 120 bpm news pulse: staccato synth eighths over a low string pad, soft kick and ticks.
	var bars := 4
	var beat := 0.5
	var out := _buf(bars * 4 * beat + 0.4)
	var chords := [[50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 57, 61]]
	for b in bars:
		var ch: Array = chords[b]
		var t0 := int(b * 4 * beat * RATE)
		# pad
		for n in ch:
			var pad := _buf(4 * beat + 0.4)
			var f := _midi(float(n) - 12.0)
			for i in pad.size():
				var t := float(i) / RATE
				var env := minf(t / 0.3, 1.0) * minf((pad.size() - i) / (0.3 * RATE), 1.0)
				pad[i] = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.003 * t) + 0.25 * sin(TAU * f * 3.0 * t)) * env
			_mix(out, pad, t0, 0.07)
		# plucks on eighths
		for e in 8:
			var n2 := int(ch[[0, 2, 1, 3, 2, 1, 3, 2][e]]) + 12
			var pl := _tone(_midi(float(n2)), 0.3, 6, 0.004, 0.09, 0.8)
			_mix(out, pl, t0 + int(e * beat * 0.5 * RATE), 0.14 if e % 2 == 0 else 0.1)
		# kick on 1 and 3, ticks on eighths
		for k in 2:
			var kick := _buf(0.35)
			for i2 in kick.size():
				var t2 := float(i2) / RATE
				kick[i2] = sin(TAU * (45.0 + 80.0 * exp(-t2 * 30.0)) * t2) * exp(-t2 * 9.0)
			_mix(out, kick, t0 + int(k * 2 * beat * RATE), 0.5)
		for e2 in 8:
			var tick := _biquad(_noise(r, int(0.05 * RATE)), "hp", 7000.0)
			for i3 in tick.size():
				tick[i3] *= exp(-float(i3) / RATE * 80.0)
			_mix(out, tick, t0 + int(e2 * beat * 0.5 * RATE), 0.12)
	return _norm(_loopify(out, 0.4), 0.8)


static func _tension(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(8.4)
	for i in out.size():
		var t := float(i) / RATE
		var sw := 0.6 + 0.4 * sin(TAU * t / 8.0)
		out[i] = (sin(TAU * 41.2 * t) * 0.6 + sin(TAU * 82.4 * t) * 0.25 + sin(TAU * 87.3 * t) * 0.12 * sw + sin(TAU * 123.5 * t + sin(t)) * 0.08) * sw
	for k in 16:
		var tick := _tone(1760.0, 0.12, 2, 0.002, 0.03, 1.0)
		_mix(out, tick, int(k * 0.5 * RATE), 0.08 if k % 4 else 0.14)
		var thud := _tone(55.0, 0.4, 2, 0.003, 0.12, 1.0)
		if k % 2 == 0:
			_mix(out, thud, int(k * 0.5 * RATE), 0.3)
	var air := _biquad(_noise(r, out.size()), "bp", 900.0, 0.5)
	_mix(out, air, 0, 0.05)
	return _norm(_loopify(out, 0.4), 0.75)


static func _somber(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(8.6)
	var notes := [[0.0, 57], [0.0, 45], [1.0, 60], [2.0, 64], [3.0, 62], [4.0, 53], [4.0, 41], [5.0, 57], [6.0, 60], [7.0, 59]]
	for nt in notes:
		var p := _tone(_midi(float(nt[1])), 2.5, 7, 0.006, 0.9, 0.5)
		_mix(out, p, int(float(nt[0]) * RATE), 0.22)
	for ch in [[0.0, [45, 52, 57, 60]], [4.0, [41, 48, 53, 57]]]:
		for n in ch[1]:
			var pad := _buf(4.4)
			var f := _midi(float(n))
			for i in pad.size():
				var t := float(i) / RATE
				var env := minf(t / 1.2, 1.0) * minf((pad.size() - i) / (1.0 * RATE), 1.0)
				pad[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 1.004 * t + 1.0)) * env
			_mix(out, pad, int(float(ch[0]) * RATE), 0.06)
	return _norm(_loopify(_biquad(out, "lp", 3500.0), 0.6), 0.7)


# ================================================================== effects
static func _impact(r: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _noise(r, int(3.2 * RATE))
	var lp := _biquad(_biquad(n, "lp", 300.0), "lp", 220.0)
	for i in lp.size():
		var t := float(i) / RATE
		lp[i] = lp[i] * exp(-t * 1.3) * minf(t * 60.0, 1.0) + sin(TAU * (34.0 + 30.0 * exp(-t * 6.0)) * t) * exp(-t * 2.0) * 0.6
	return _norm(lp, 0.95)


static func _shutter(r: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(1.2)
	var at := 0.0
	for k in 7:
		var c := _biquad(_noise(r, int(0.03 * RATE)), "bp", 3200.0, 1.5)
		for i in c.size():
			c[i] *= exp(-float(i) / RATE * 160.0)
		_mix(out, c, int(at * RATE), 0.8)
		_mix(out, c, int((at + 0.04) * RATE), 0.5)
		at += r.randf_range(0.09, 0.2)
	return _norm(out, 0.8)


# ================================================================== ambience loops
static func _wind(r: RandomNumberGenerator, seconds: float, amount: float) -> PackedFloat32Array:
	var n := _noise(r, int((seconds + 0.5) * RATE))
	var lp := _biquad(_biquad(n, "lp", 520.0), "lp", 380.0)
	for i in lp.size():
		var t := float(i) / RATE
		lp[i] *= (0.55 + 0.45 * sin(TAU * t / 3.1 + sin(t * 0.7))) * amount
	return _norm(_loopify(lp, 0.5), 0.6)


static func _heli(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 6.5
	var out := _buf(dur)
	var slap := 1.0 / 5.4
	var n := _biquad(_noise(r, out.size()), "bp", 420.0, 0.8)
	var t := 0.0
	var next := 0.0
	var env := 0.0
	for i in out.size():
		t = float(i) / RATE
		if t >= next:
			env = 1.0
			next += slap
		env *= 0.9988
		out[i] = n[i] * env * 1.2 + sin(TAU * 18.0 * t) * env * 0.5 + sin(TAU * (2350.0 + 30.0 * sin(t * 2.0)) * t) * 0.03
	var w := _wind(r, dur - 0.5, 0.6)
	_mix(out, w, 0, 0.35)
	return _norm(_loopify(_biquad(out, "lp", 4200.0), 0.5), 0.8)


static func _sirens(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 8.5
	var out := _buf(dur)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var f1 := 950.0 + 420.0 * sin(TAU * t / 4.0)
		var f2 := 920.0 if int(t / 0.6) % 2 == 0 else 690.0
		ph1 += TAU * f1 / RATE
		ph2 += TAU * f2 / RATE
		var dist1 := 0.35 + 0.25 * sin(TAU * t / 8.0)
		var dist2 := 0.18 + 0.12 * sin(TAU * t / 8.0 + 2.0)
		out[i] = (sin(ph1) + 0.3 * sin(2.0 * ph1)) * dist1 * 0.5 + (sin(ph2) + 0.25 * sin(3.0 * ph2)) * dist2 * 0.4
	out = _biquad(out, "lp", 2600.0)
	_mix(out, _murmur(r, dur, 0.6), 0, 0.5)
	_mix(out, _wind(r, dur - 0.5, 0.5), 0, 0.25)
	return _norm(_loopify(out, 0.5), 0.7)


static func _murmur(r: RandomNumberGenerator, seconds: float, amount: float) -> PackedFloat32Array:
	## Many voices far away: band-limited noise with syllable-rate modulation.
	var out := _buf(seconds)
	for v in 6:
		var n := _biquad(_noise(r, out.size()), "bp", r.randf_range(280.0, 900.0), 2.5)
		var rate := r.randf_range(3.0, 5.5)
		var ph := r.randf() * TAU
		for i in out.size():
			var t := float(i) / RATE
			out[i] += n[i] * maxf(sin(TAU * rate * t + ph + sin(t * 1.3 + v)), 0.0) * amount
	return out


static func _outdoor(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 7.0
	var out := _wind(r, dur - 0.5, 0.5)
	out = out.slice(0, out.size())
	var full := _buf(dur)
	_mix(full, out, 0, 0.5)
	for k in 9:
		var at := r.randf_range(0.2, dur - 0.8)
		var f0 := r.randf_range(2800.0, 4200.0)
		var chirp := _buf(0.16)
		for i in chirp.size():
			var t := float(i) / RATE
			chirp[i] = sin(TAU * (f0 + 1800.0 * t / 0.16) * t) * sin(PI * t / 0.16)
		_mix(full, chirp, int(at * RATE), 0.08)
	var traffic := _biquad(_noise(r, full.size()), "lp", 160.0)
	_mix(full, traffic, 0, 0.6)
	return _norm(_loopify(full, 0.5), 0.5)


static func _room(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 7.0
	var out := _murmur(r, dur, 0.4)
	var tone := _biquad(_noise(r, out.size()), "lp", 120.0)
	_mix(out, tone, 0, 0.7)
	for k in 5:
		var c := _biquad(_noise(r, int(0.025 * RATE)), "bp", 3000.0, 1.5)
		for i in c.size():
			c[i] *= exp(-float(i) / RATE * 180.0)
		_mix(out, c, int(r.randf_range(0.3, dur - 0.8) * RATE), 0.5)
	return _norm(_loopify(out, 0.5), 0.45)


static func _vigil(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 7.0
	var out := _murmur(r, dur, 0.18)
	_mix(out, _wind(r, dur - 0.5, 0.4), 0, 0.4)
	return _norm(_loopify(out, 0.5), 0.35)


static func _airport(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 7.0
	var out := _buf(dur)
	for i in out.size():
		var t := float(i) / RATE
		var sw := 0.6 + 0.4 * sin(TAU * t / 7.0)
		out[i] = (sin(TAU * 1180.0 * t) * 0.05 + sin(TAU * 590.0 * t) * 0.03) * sw
	var roar := _biquad(_noise(r, out.size()), "bp", 300.0, 0.6)
	_mix(out, roar, 0, 0.5)
	_mix(out, _wind(r, dur - 0.5, 0.5), 0, 0.3)
	return _norm(_loopify(out, 0.5), 0.5)


static func _terminal(r: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 8.0
	var out := _murmur(r, dur, 0.5)
	var ch := _tone(_midi(76.0), 1.2, 3, 0.005, 0.4, 0.6)
	var ch2 := _tone(_midi(72.0), 1.2, 3, 0.005, 0.5, 0.6)
	_mix(out, ch, int(2.0 * RATE), 0.25)
	_mix(out, ch2, int(2.45 * RATE), 0.25)
	var tone := _biquad(_noise(r, out.size()), "lp", 140.0)
	_mix(out, tone, 0, 0.6)
	return _norm(_loopify(out, 0.5), 0.45)
