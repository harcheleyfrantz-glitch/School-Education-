class_name Phraseology
extends RefCounted
## Standard radiotelephony formatting: written (subtitle) forms and spoken (text-to-speech) forms.

const DIGITS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
const ALPHA := {"A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot", "G": "Golf",
	"H": "Hotel", "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima", "M": "Mike", "N": "November", "O": "Oscar",
	"P": "Papa", "Q": "Quebec", "R": "Romeo", "S": "Sierra", "T": "Tango", "U": "Uniform", "V": "Victor",
	"W": "Whiskey", "X": "X-ray", "Y": "Yankee", "Z": "Zulu"}


static func digits(s: String) -> String:
	var out := []
	for ch in s:
		if ch >= "0" and ch <= "9":
			out.append(DIGITS[int(ch)])
		elif ch == ".":
			out.append("decimal")
		elif ALPHA.has(ch):
			out.append(ALPHA[ch])
	return " ".join(out)


static func runway(name: String) -> String:
	var num := ""
	var suffix := ""
	for ch in name:
		if ch >= "0" and ch <= "9":
			num += ch
		else:
			suffix = {"L": "left", "R": "right", "C": "center"}.get(ch, "")
	return "runway " + digits(num) + (" " + suffix if suffix != "" else "")


static func flight_level(fl: int) -> String:
	return "flight level " + digits("%03d" % fl)


static func altitude_ft(ft: int) -> String:
	var th := ft / 1000
	var hu := (ft % 1000) / 100
	var parts := []
	if th > 0:
		parts.append(digits(str(th)) + " thousand")
	if hu > 0:
		parts.append(digits(str(hu)) + " hundred")
	return " ".join(parts) + " feet"


## Altitude as cleared: flight levels above the transition altitude (5000 ft here).
static func level_text(alt_m: float) -> Array:
	var ft := int(round(alt_m / U.FT / 100.0)) * 100
	if ft >= 6000:
		var fl := ft / 100
		return ["FL%03d" % fl, flight_level(fl)]
	return ["%d ft" % ft, altitude_ft(ft)]


static func heading(h: float) -> String:
	var hh := int(round(h)) % 360
	if hh == 0:
		hh = 360
	return "heading " + digits("%03d" % hh)


static func freq(f: String) -> String:
	return digits(f)


static func wind(dir_deg: float, kt: float) -> Array:
	if kt < 3.0:
		return ["wind calm", "wind calm"]
	var d := int(round(dir_deg / 10.0)) * 10 % 360
	if d == 0:
		d = 360
	return ["wind %03d/%d" % [d, int(kt)], "wind " + digits("%03d" % d) + " degrees, " + digits(str(int(kt))) + " knots"]


static func squawk(code: String) -> String:
	return "squawk " + digits(code)


static func callsign_spoken(callsign: String) -> String:
	## "Skyfall 123" -> "Skyfall one two three"
	var parts := callsign.split(" ")
	if parts.size() < 2:
		return callsign
	return parts[0] + " " + digits(parts[1])


static func taxi_route(names: Array) -> String:
	var out := []
	for n in names:
		var s := String(n)
		if s.begins_with("RWY") or s == "" or s == "apron":
			continue
		if out.is_empty() or out[out.size() - 1] != s:
			out.append(s)
	return ", ".join(out)


static func spoken_route(names_text: String) -> String:
	var out := []
	for part in names_text.split(", "):
		var p := String(part)
		var letters := ""
		var nums := ""
		for ch in p:
			if ch >= "0" and ch <= "9":
				nums += ch
			else:
				letters += ch
		var sp := ""
		for ch2 in letters:
			sp += String(ALPHA.get(ch2, ch2)) + " "
		out.append((sp + digits(nums)).strip_edges())
	return ", ".join(out)
