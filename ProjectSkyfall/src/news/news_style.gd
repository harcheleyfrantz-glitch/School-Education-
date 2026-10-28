class_name NewsStyle
extends RefCounted
## The on-air look of every outlet: colours, typefaces, show names, presenters and reporters,
## plus the safety board's own look for investigation videos. Broadcast graphics, studio sets,
## thumbnails and the comment section all read from here so each outlet stays recognisable.

const STYLES := {
	"skyline": {"name": "Skyline News", "short": "SKYLINE", "show": "SKYLINE NEWS TONIGHT", "kind": "tv",
		"primary": "c8102e", "secondary": "101622", "accent": "ffffff", "hi": "ffd400", "ticker_bg": "0a0e16", "ticker_fg": "f2f2f2",
		"type": "sans", "italic": true, "bug": "skyline", "web": "skylinenews.cal",
		"anchors": [["Maya Rennick", "f"], ["Daniel Achebe", "m"]], "reporters": [["Jonas Varga", "m"], ["Selin Ortega", "f"], ["Kofi Mensah", "m"]],
		"analyst": ["Capt. Ruth Holloway", "f", "Aviation analyst, former airline captain"], "chopper": "SKYLINE CHOPPER 7", "set_tint": "c8102e"},
	"herald": {"name": "Calderra Herald", "short": "HERALD", "show": "HERALD VIDEO", "kind": "paper",
		"primary": "1f3b66", "secondary": "0d182b", "accent": "efe6d2", "hi": "c9a227", "ticker_bg": "0d182b", "ticker_fg": "efe6d2",
		"type": "serif", "italic": false, "bug": "herald", "web": "calderraherald.cal",
		"anchors": [["Eleanor Whitfield", "f"], ["Tomas Lindqvist", "m"]], "reporters": [["Grace Abara", "f"], ["Callum Keane", "m"]],
		"analyst": ["Dr. Henrik Sorensen", "m", "Transport safety researcher"], "chopper": "HERALD AERIAL", "set_tint": "2a5298"},
	"westmark": {"name": "Westmark Post", "short": "POST", "show": "THE POST TODAY", "kind": "paper",
		"primary": "2d6a4f", "secondary": "0f241b", "accent": "f1f5f2", "hi": "e9c46a", "ticker_bg": "0f241b", "ticker_fg": "eef3ef",
		"type": "serif", "italic": false, "bug": "post", "web": "westmarkpost.wm",
		"anchors": [["Sigrun Halvorsen", "f"], ["Edmund Achterberg", "m"]], "reporters": [["Ines Moreno", "f"], ["Rowan Hartley", "m"]],
		"analyst": ["Capt. Idris Mbeki", "m", "Former chief pilot"], "chopper": "POST AERIAL", "set_tint": "2d6a4f"},
	"aeroweek": {"name": "AeroWeek", "short": "AEROWEEK", "show": "AEROWEEK ANALYSIS", "kind": "trade",
		"primary": "f28c28", "secondary": "1c2633", "accent": "e8eef4", "hi": "f28c28", "ticker_bg": "121a24", "ticker_fg": "dfe7ef",
		"type": "mono", "italic": false, "bug": "aeroweek", "web": "aeroweek.aero",
		"anchors": [["Nadia Petrov", "f"], ["Oscar Bergstrom", "m"]], "reporters": [["Arjun Kaur", "m"], ["Linnea Strand", "f"]],
		"analyst": ["Viktor Novak", "m", "Accident investigator (ret.)"], "chopper": "AEROWEEK", "set_tint": "f28c28"},
	"gazette": {"name": "Port Calder Gazette", "short": "GAZETTE", "show": "GAZETTE LOCAL", "kind": "local",
		"primary": "b5651d", "secondary": "2a1b10", "accent": "fff6ea", "hi": "ffcf70", "ticker_bg": "21160d", "ticker_fg": "fff1df",
		"type": "sans", "italic": false, "bug": "gazette", "web": "pcgazette.cal",
		"anchors": [["Joanna Quinlan", "f"], ["Malik Osei", "m"]], "reporters": [["Bea Castellano", "f"], ["Teo Rossi", "m"]],
		"analyst": ["Sam Fitzgerald", "x", "Local aviation historian"], "chopper": "GAZETTE DRONE", "set_tint": "b5651d"},
	"skywatch": {"name": "SkyWatch", "short": "SKYWATCH", "show": "SKYWATCH", "kind": "blog",
		"primary": "7b4fd0", "secondary": "160f26", "accent": "f3efff", "hi": "34d1bf", "ticker_bg": "140e22", "ticker_fg": "efe9ff",
		"type": "sans", "italic": false, "bug": "skywatch", "web": "skywatch.blog",
		"anchors": [["Ezra Lambert", "m"], ["Mei Chen", "f"]], "reporters": [["Ezra Lambert", "m"]],
		"analyst": ["Ezra Lambert", "m", "Pilot and aviation vlogger"], "chopper": "SKYWATCH DRONE", "set_tint": "7b4fd0"},
	"ctsb": {"name": "Calderra Transport Safety Board", "short": "CTSB", "show": "INVESTIGATION REPORT", "kind": "authority",
		"primary": "1d4e89", "secondary": "08111f", "accent": "f4f7fb", "hi": "ffb000", "ticker_bg": "08111f", "ticker_fg": "f4f7fb",
		"type": "sans", "italic": false, "bug": "ctsb", "web": "ctsb.gov.cal",
		"anchors": [["Ingrid Solberg", "f"], ["Anton Dubois", "m"]], "reporters": [["Ingrid Solberg", "f"]],
		"analyst": ["Ingrid Solberg", "f", "Investigator-in-charge"], "chopper": "CTSB", "set_tint": "1d4e89"},
}

## The people speaking for the safety board at press conferences.
const BOARD_CHAIR := ["Ingrid Solberg", "f", "Investigator-in-charge, CTSB"]
const BOARD_MEMBER := ["Anton Dubois", "m", "Board member, CTSB"]

static var _fonts := {}


static func get_style(outlet: String) -> Dictionary:
	return STYLES.get(outlet, STYLES["skyline"])


static func col(outlet: String, key: String) -> Color:
	return Color.html(String(get_style(outlet).get(key, "ffffff")))


## Typeface for an outlet: "sans", "serif", "mono" or "display" (heavy condensed-feeling sans).
static func font(kind: String, weight: int = 400, italic: bool = false) -> SystemFont:
	var key := "%s|%d|%s" % [kind, weight, italic]
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	match kind:
		"serif":
			f.font_names = PackedStringArray(["Caladea", "Liberation Serif", "DejaVu Serif", "Noto Serif", "Georgia", "Times New Roman", "serif"])
		"mono":
			f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Consolas", "monospace"])
		"display":
			f.font_names = PackedStringArray(["Inter Display", "Inter", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"])
		_:
			f.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans", "Liberation Sans", "Arial", "Helvetica", "sans-serif"])
	f.font_weight = weight
	f.font_italic = italic
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.generate_mipmaps = true
	_fonts[key] = f
	return f


## Headline face of an outlet.
static func head_font(outlet: String, weight: int = 800) -> SystemFont:
	var s := get_style(outlet)
	var kind := String(s.type)
	if kind == "mono":
		kind = "display"
	return font(kind, weight, bool(s.italic))


static func body_font(outlet: String, weight: int = 500) -> SystemFont:
	var s := get_style(outlet)
	return font("display" if String(s.type) == "mono" else String(s.type), weight, false)


## A presenter or reporter of the outlet, stable for a seed.
static func anchor(outlet: String, i: int = 0) -> Array:
	var a: Array = get_style(outlet).anchors
	return a[absi(i) % a.size()]


static func reporter(outlet: String, seed_v: int) -> Array:
	var a: Array = get_style(outlet).reporters
	return a[absi(seed_v) % a.size()]


## Stable avatar colour for a name or handle.
static func avatar_color(key: String) -> Color:
	var h := float(U.hash_str(key) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.78)


static func initials(name: String) -> String:
	var parts := name.replace("Capt. ", "").replace("Dr. ", "").strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].substr(0, 2).to_upper()
	return (parts[0].substr(0, 1) + parts[parts.size() - 1].substr(0, 1)).to_upper()
