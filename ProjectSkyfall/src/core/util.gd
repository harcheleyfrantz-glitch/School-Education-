class_name U
## Shared helpers: units, angles, formatting, deterministic randomness, calendar.

const KT := 0.514444          # m/s per knot
const FT := 0.3048            # m per foot
const FPM := 0.00508          # m/s per ft/min
const NM := 1852.0            # m per nautical mile
const G0 := 9.80665
const LB := 0.453592

const EPOCH_YEAR := 2027
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]
const MONTH_SHORT := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const DAY_NAMES := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


# ---------------------------------------------------------------- angles
static func wrap_deg(a: float) -> float:
	a = fmod(a, 360.0)
	if a < 0.0:
		a += 360.0
	return a


static func angle_diff_deg(target: float, current: float) -> float:
	var d := fmod(target - current + 540.0, 360.0) - 180.0
	return d


static func heading_to_dir(heading_deg: float) -> Vector3:
	var h := deg_to_rad(heading_deg)
	return Vector3(sin(h), 0.0, -cos(h))


static func dir_to_heading(v: Vector3) -> float:
	return wrap_deg(rad_to_deg(atan2(v.x, -v.z)))


static func bearing_deg(from_x: float, from_z: float, to_x: float, to_z: float) -> float:
	return wrap_deg(rad_to_deg(atan2(to_x - from_x, -(to_z - from_z))))


static func dist2d(ax: float, az: float, bx: float, bz: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))


# ---------------------------------------------------------------- smoothing / math
static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(target, current, exp(-rate * dt))


static func damp_v3(current: Vector3, target: Vector3, rate: float, dt: float) -> Vector3:
	return target.lerp(current, exp(-rate * dt))


static func remap_clamped(v: float, a0: float, a1: float, b0: float, b1: float) -> float:
	if is_equal_approx(a0, a1):
		return b0
	return lerpf(b0, b1, clampf((v - a0) / (a1 - a0), 0.0, 1.0))


static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func approach(current: float, target: float, max_delta: float) -> float:
	if current < target:
		return minf(current + max_delta, target)
	return maxf(current - max_delta, target)


# ---------------------------------------------------------------- deterministic randomness
static func hash_str(s: String) -> int:
	# FNV-1a 32 bit, stable across platforms and runs.
	var h := 2166136261
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h


static func hash_ints(a: int, b: int = 0, c: int = 0) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16)) & 0x7FFFFFFF


static func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[r.randi_range(0, arr.size() - 1)]


static func pick_weighted(r: RandomNumberGenerator, items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return pick(r, items)
	var x := r.randf() * total
	for i in items.size():
		x -= float(weights[i])
		if x <= 0.0:
			return items[i]
	return items[items.size() - 1]


static func chance(r: RandomNumberGenerator, p: float) -> bool:
	return r.randf() < p


static func shuffle(r: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ---------------------------------------------------------------- formatting
static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func fmt_money(n: float) -> String:
	return ("-$" if n < 0 else "$") + fmt_int(int(round(absf(n))))


static func fmt_duration(seconds: float) -> String:
	var s := int(seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s % 60]


static func fmt_alt_ft(meters: float) -> String:
	var ft := meters / FT
	if ft >= 18000.0:
		return "FL%03d" % int(round(ft / 100.0))
	return "%s ft" % fmt_int(int(round(ft / 10.0) * 10.0))


static func fl_or_ft(feet: float) -> String:
	if feet >= 18000.0:
		return "FL%03d" % int(round(feet / 100.0))
	return "%s feet" % fmt_int(int(round(feet / 100.0) * 100.0))


static func spoken_number(n: int) -> String:
	# Aviation style digit-by-digit read out ("two seven zero").
	const WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
	var s := str(n)
	var parts: PackedStringArray = []
	for ch in s:
		if ch >= "0" and ch <= "9":
			parts.append(WORDS[int(ch)])
	return " ".join(parts)


static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return str(n) + suf


static func plural(n: int, word: String, plural_word: String = "") -> String:
	if n == 1:
		return "1 " + word
	return "%s %s" % [fmt_int(n), plural_word if plural_word != "" else word + "s"]


static func number_words(n: int) -> String:
	const SMALL := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
		"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
	const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
	if n < 0:
		return "minus " + number_words(-n)
	if n < 20:
		return SMALL[n]
	if n < 100:
		return TENS[n / 10] + ("" if n % 10 == 0 else "-" + SMALL[n % 10])
	if n < 1000:
		return SMALL[n / 100] + " hundred" + ("" if n % 100 == 0 else " and " + number_words(n % 100))
	return fmt_int(n)


static func capitalize_first(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


# ---------------------------------------------------------------- calendar (world clock = seconds since EPOCH_YEAR-01-01 00:00)
static func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func days_in_month(y: int, m: int) -> int:
	const D := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m == 2 and is_leap(y):
		return 29
	return D[m - 1]


static func clock_to_date(t: float) -> Dictionary:
	var total_days := int(floor(t / 86400.0))
	var sec_of_day := t - float(total_days) * 86400.0
	var y := EPOCH_YEAR
	var d := total_days
	while true:
		var ylen := 366 if is_leap(y) else 365
		if d < ylen:
			break
		d -= ylen
		y += 1
	var day_of_year := d
	var m := 1
	while d >= days_in_month(y, m):
		d -= days_in_month(y, m)
		m += 1
	var weekday := (total_days + 4) % 7   # 1 Jan 2027 is a Friday (index 4)
	return {
		"year": y, "month": m, "day": d + 1, "doy": day_of_year,
		"hour": int(sec_of_day / 3600.0), "minute": int(fmod(sec_of_day, 3600.0) / 60.0),
		"second": int(fmod(sec_of_day, 60.0)), "weekday": weekday, "hours_f": sec_of_day / 3600.0,
	}


static func date_to_clock(y: int, m: int, d: int, hour: float = 0.0) -> float:
	var days := 0
	for yy in range(EPOCH_YEAR, y):
		days += 366 if is_leap(yy) else 365
	for mm in range(1, m):
		days += days_in_month(y, mm)
	days += d - 1
	return float(days) * 86400.0 + hour * 3600.0


static func fmt_clock(t: float) -> String:
	var dt := clock_to_date(t)
	return "%02d:%02d" % [dt.hour, dt.minute]


static func fmt_date(t: float) -> String:
	var dt := clock_to_date(t)
	return "%d %s %d" % [dt.day, MONTH_NAMES[dt.month - 1], dt.year]


static func fmt_date_short(t: float) -> String:
	var dt := clock_to_date(t)
	return "%02d %s %d" % [dt.day, MONTH_SHORT[dt.month - 1], dt.year]


static func fmt_datetime(t: float) -> String:
	var dt := clock_to_date(t)
	return "%s %d %s %d, %02d:%02d" % [DAY_NAMES[dt.weekday].substr(0, 3), dt.day, MONTH_SHORT[dt.month - 1], dt.year, dt.hour, dt.minute]


static func fmt_zulu(t: float) -> String:
	var dt := clock_to_date(t)
	return "%02d%02d%02dZ" % [dt.day, dt.hour, dt.minute]


static func fmt_ago(now: float, then: float) -> String:
	var d := now - then
	if d < 60.0:
		return "just now"
	if d < 3600.0:
		return "%d min ago" % int(d / 60.0)
	if d < 86400.0:
		return "%d h ago" % int(d / 3600.0)
	if d < 86400.0 * 60.0:
		return "%d days ago" % int(d / 86400.0)
	return fmt_date_short(then)


# ---------------------------------------------------------------- color helpers
static func hex(c: String) -> Color:
	return Color.html(c)


static func vary_color(c: Color, r: RandomNumberGenerator, amount: float) -> Color:
	return Color(clampf(c.r + r.randf_range(-amount, amount), 0, 1),
		clampf(c.g + r.randf_range(-amount, amount), 0, 1),
		clampf(c.b + r.randf_range(-amount, amount), 0, 1), c.a)
