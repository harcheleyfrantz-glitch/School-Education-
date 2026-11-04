extends RefCounted
## Per-airport architectural style: terminal plan, roof, cladding colours, levels, control tower
## and signature landmark. Real airports echo their real character; anything not listed falls
## back to a deterministic pick from the ICAO hash so no two airports look the same.
##
## plan:  linear | arc (curved landside hall) | midfield (head house + satellites on a people mover)
## roof:  arch (big ribbed truss, Indianapolis) | vault (very wide flat arch, Heathrow T5) | wave |
##        saw (sawtooth skylights) | shell (overlapping curved shells) | flat (deep canopy) |
##        gable (regional pitched) | tent (peaked membrane, Denver) | sag (upturned catenary eaves)
## tower: torch | flared | slender | cylinder | box | classic | lantern
## sig:   "" | theme (LAX arch) | drum (CDG T1) | jewel (Changi dome) | loop (extra unit terminals)

const ROOFS := ["arch", "vault", "wave", "saw", "shell", "flat", "sag", "tent"]
const TOWERS := ["torch", "flared", "slender", "cylinder", "lantern", "classic"]
const CLADS := [Color(0.93, 0.93, 0.92), Color(0.82, 0.83, 0.85), Color(0.86, 0.82, 0.74), Color(0.7, 0.72, 0.75),
	Color(0.9, 0.88, 0.84), Color(0.62, 0.64, 0.67), Color(0.95, 0.94, 0.9)]
const ROOF_COLS := [Color(0.94, 0.95, 0.96), Color(0.78, 0.8, 0.82), Color(0.66, 0.69, 0.72), Color(0.85, 0.86, 0.84),
	Color(0.58, 0.6, 0.63)]
const FRAME_COLS := [Color(0.92, 0.93, 0.94), Color(0.3, 0.32, 0.35), Color(0.62, 0.65, 0.68), Color(0.85, 0.85, 0.82)]

## gates/sats override the data for the terminal plan (sats = satellite concourses in a row);
## garages = multi-storey car parks on the landside; scale stretches the hall.
const TABLE := {
	# --- Calderra / Westmark (fictional)
	"SKPC": {"plan": "midfield", "roof": "arch", "tower": "lantern", "levels": 3, "gates": 44, "sats": 2, "garages": 3, "hotel": 2, "cargo": true, "sig": "jewel",
		"clad": Color(0.94, 0.94, 0.93), "roof_col": Color(0.95, 0.96, 0.97), "frame": Color(0.95, 0.96, 0.97), "accent": Color(0.1, 0.45, 0.75), "tower_h": 92.0},
	"SKRV": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.78, 0.7, 0.6), "roof_col": Color(0.38, 0.4, 0.44)},
	"SKNG": {"roof": "saw", "tower": "cylinder", "levels": 2, "gates": 12, "garages": 1, "cargo": true, "clad": Color(0.6, 0.62, 0.66), "roof_col": Color(0.55, 0.57, 0.6), "frame": Color(0.25, 0.27, 0.3)},
	"SKHP": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.55, 0.42, 0.3), "roof_col": Color(0.3, 0.25, 0.22)},
	"SKOF": {"roof": "wave", "tower": "classic", "levels": 1, "clad": Color(0.88, 0.86, 0.8), "roof_col": Color(0.4, 0.55, 0.6)},
	"SKIM": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.96, 0.92, 0.82), "roof_col": Color(0.62, 0.36, 0.25)},
	"SKSB": {"roof": "shell", "tower": "flared", "levels": 1, "hotel": 1, "clad": Color(0.97, 0.95, 0.9), "roof_col": Color(0.97, 0.97, 0.95)},
	"WMIA": {"roof": "vault", "tower": "classic", "levels": 2, "gates": 16, "garages": 1, "hotel": 1, "cargo": true, "clad": Color(0.8, 0.74, 0.62), "roof_col": Color(0.42, 0.5, 0.46), "frame": Color(0.3, 0.3, 0.28)},
	"WMSK": {"roof": "flat", "tower": "box", "levels": 1, "clad": Color(0.75, 0.76, 0.78)},
	# --- North America
	"KJFK": {"plan": "midfield", "roof": "flat", "tower": "flared", "levels": 3, "gates": 40, "sats": 1, "sig": "loop", "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.8, 0.82, 0.84), "frame": Color(0.35, 0.37, 0.4)},
	"KBOS": {"roof": "flat", "tower": "slender", "levels": 2, "garages": 2, "hotel": 1, "clad": Color(0.72, 0.74, 0.76)},
	"KIAD": {"plan": "midfield", "roof": "sag", "tower": "lantern", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.9, 0.89, 0.86), "roof_col": Color(0.86, 0.86, 0.84)},
	"KORD": {"plan": "midfield", "roof": "vault", "tower": "cylinder", "levels": 3, "gates": 40, "sats": 2, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.82, 0.84, 0.88), "frame": Color(0.4, 0.5, 0.62)},
	"CYYZ": {"plan": "arc", "roof": "arch", "tower": "slender", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "clad": Color(0.85, 0.86, 0.88)},
	"KMIA": {"plan": "midfield", "roof": "flat", "tower": "flared", "levels": 3, "gates": 64, "sats": 2, "garages": 3, "hotel": 1, "cargo": true, "tower_h": 100.0,
		"clad": Color(0.96, 0.95, 0.92), "roof_col": Color(0.92, 0.92, 0.9), "accent": Color(0.15, 0.6, 0.65)},
	"KLAX": {"plan": "arc", "roof": "flat", "tower": "flared", "levels": 3, "gates": 36, "sats": 1, "sig": "theme", "garages": 3, "hotel": 1, "cargo": true,
		"clad": Color(0.88, 0.86, 0.82), "roof_col": Color(0.78, 0.78, 0.76)},
	"KSFO": {"roof": "sag", "tower": "torch", "levels": 3, "garages": 2, "hotel": 1, "clad": Color(0.86, 0.87, 0.88), "roof_col": Color(0.82, 0.84, 0.86)},
	"KATL": {"plan": "midfield", "roof": "flat", "tower": "slender", "levels": 2, "gates": 48, "sats": 3, "garages": 3, "hotel": 1, "cargo": true, "clad": Color(0.78, 0.76, 0.72)},
	"KDFW": {"plan": "arc", "roof": "flat", "tower": "flared", "levels": 2, "sats": 2, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.86, 0.82, 0.74)},
	"KDEN": {"plan": "midfield", "roof": "tent", "tower": "flared", "levels": 3, "gates": 36, "sats": 2, "garages": 2, "hotel": 1, "roof_col": Color(0.98, 0.98, 0.97)},
	"KSEA": {"roof": "arch", "tower": "lantern", "levels": 2, "sats": 1, "garages": 2, "clad": Color(0.7, 0.74, 0.76)},
	"KLAS": {"roof": "flat", "tower": "slender", "levels": 2, "sats": 1, "garages": 2, "hotel": 2, "clad": Color(0.92, 0.86, 0.74)},
	"KMSY": {"roof": "shell", "tower": "box", "levels": 2, "garages": 1, "clad": Color(0.88, 0.86, 0.82)},
	"KMCO": {"roof": "flat", "tower": "flared", "levels": 3, "sats": 2, "garages": 2, "hotel": 1, "clad": Color(0.94, 0.92, 0.86)},
	"CYQX": {"roof": "flat", "tower": "classic", "levels": 1, "clad": Color(0.84, 0.82, 0.76)},
	"BGGH": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.7, 0.18, 0.15), "roof_col": Color(0.2, 0.22, 0.25)},
	"TXKF": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.96, 0.8, 0.8), "roof_col": Color(0.97, 0.97, 0.97)},
	# --- Europe
	"EGLL": {"plan": "midfield", "roof": "vault", "tower": "cylinder", "levels": 3, "gates": 44, "sats": 2, "garages": 2, "hotel": 2, "cargo": true,
		"clad": Color(0.86, 0.87, 0.88), "roof_col": Color(0.8, 0.82, 0.84), "frame": Color(0.88, 0.89, 0.9)},
	"LFPG": {"plan": "midfield", "roof": "shell", "tower": "slender", "levels": 3, "sats": 1, "sig": "drum", "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.78, 0.78, 0.76)},
	"EHAM": {"roof": "flat", "tower": "flared", "levels": 2, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.82, 0.84, 0.86), "accent": Color(0.1, 0.25, 0.55)},
	"EIDW": {"roof": "arch", "tower": "slender", "levels": 2, "garages": 1, "clad": Color(0.84, 0.85, 0.86)},
	"LEMD": {"plan": "midfield", "roof": "wave", "tower": "flared", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "rainbow": true,
		"clad": Color(0.88, 0.85, 0.78), "roof_col": Color(0.82, 0.7, 0.52)},
	"LIRF": {"roof": "vault", "tower": "box", "levels": 2, "sats": 1, "garages": 2, "clad": Color(0.9, 0.86, 0.78)},
	"BIKF": {"roof": "flat", "tower": "box", "levels": 1, "clad": Color(0.72, 0.74, 0.78)},
	"LPPD": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.95, 0.94, 0.9)},
	"LPMA": {"roof": "flat", "tower": "box", "levels": 1, "clad": Color(0.96, 0.95, 0.92)},
	"EKVG": {"roof": "gable", "tower": "box", "levels": 1, "clad": Color(0.25, 0.28, 0.3), "roof_col": Color(0.3, 0.42, 0.25)},
	"EDDF": {"plan": "midfield", "roof": "flat", "tower": "slender", "levels": 3, "sats": 2, "garages": 3, "hotel": 1, "cargo": true, "clad": Color(0.78, 0.8, 0.84)},
	"EDDM": {"roof": "shell", "tower": "classic", "levels": 2, "sats": 1, "garages": 2, "hotel": 1, "clad": Color(0.86, 0.87, 0.88)},
	"LSZH": {"roof": "wave", "tower": "cylinder", "levels": 2, "garages": 1, "clad": Color(0.84, 0.84, 0.84)},
	"LOWW": {"roof": "flat", "tower": "lantern", "levels": 2, "garages": 1, "clad": Color(0.88, 0.88, 0.86)},
	"EKCH": {"roof": "wave", "tower": "box", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.74, 0.62, 0.48)},
	"ENGM": {"roof": "wave", "tower": "cylinder", "levels": 2, "garages": 1, "clad": Color(0.76, 0.6, 0.42), "roof_col": Color(0.6, 0.62, 0.64)},
	"ESSA": {"roof": "flat", "tower": "flared", "levels": 2, "garages": 1, "clad": Color(0.82, 0.8, 0.74)},
	"EDDB": {"roof": "flat", "tower": "box", "levels": 2, "garages": 2, "hotel": 1, "clad": Color(0.72, 0.62, 0.48)},
	"LEBL": {"roof": "flat", "tower": "slender", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.9, 0.88, 0.84)},
	"EBBR": {"roof": "shell", "tower": "classic", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.82, 0.83, 0.85)},
	"LPPT": {"roof": "flat", "tower": "box", "levels": 2, "garages": 1, "clad": Color(0.94, 0.92, 0.86)},
	"EGCC": {"roof": "flat", "tower": "cylinder", "levels": 2, "garages": 2, "clad": Color(0.66, 0.6, 0.56)},
	"EGPH": {"roof": "saw", "tower": "flared", "levels": 1, "garages": 1, "clad": Color(0.7, 0.7, 0.68)},
	"LGAV": {"roof": "flat", "tower": "box", "levels": 2, "garages": 1, "clad": Color(0.94, 0.93, 0.9)},
	"UUEE": {"roof": "flat", "tower": "cylinder", "levels": 2, "sats": 1, "garages": 2, "clad": Color(0.82, 0.84, 0.86)},
	"LTFM": {"plan": "midfield", "roof": "saw", "tower": "torch", "levels": 3, "gates": 46, "sats": 2, "garages": 3, "hotel": 1, "cargo": true,
		"clad": Color(0.86, 0.86, 0.85), "roof_col": Color(0.78, 0.8, 0.82)},
	"HECA": {"roof": "flat", "tower": "box", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.88, 0.82, 0.68)},
	# --- Asia / Middle East
	"RJTT": {"roof": "wave", "tower": "slender", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "clad": Color(0.86, 0.87, 0.9)},
	"RJBB": {"roof": "shell", "tower": "cylinder", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.78, 0.8, 0.84), "roof_col": Color(0.72, 0.75, 0.78)},
	"RKSI": {"plan": "midfield", "roof": "sag", "tower": "torch", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.88, 0.9, 0.92)},
	"ZBAA": {"plan": "midfield", "roof": "arch", "tower": "slender", "levels": 3, "gates": 40, "sats": 2, "garages": 2, "cargo": true,
		"clad": Color(0.84, 0.76, 0.66), "roof_col": Color(0.85, 0.55, 0.3), "accent": Color(0.75, 0.12, 0.1)},
	"ZSPD": {"roof": "shell", "tower": "flared", "levels": 3, "sats": 1, "garages": 2, "cargo": true, "clad": Color(0.82, 0.84, 0.86)},
	"VHHH": {"plan": "midfield", "roof": "vault", "tower": "torch", "levels": 3, "sats": 1, "garages": 1, "hotel": 1, "cargo": true, "clad": Color(0.8, 0.82, 0.84)},
	"RCTP": {"roof": "sag", "tower": "slender", "levels": 2, "sats": 1, "garages": 1, "clad": Color(0.86, 0.85, 0.82)},
	"WSSS": {"plan": "midfield", "roof": "saw", "tower": "flared", "levels": 3, "gates": 40, "sats": 2, "sig": "jewel", "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.88, 0.88, 0.86)},
	"WMKK": {"roof": "tent", "tower": "torch", "levels": 2, "sats": 1, "garages": 1, "hotel": 1, "clad": Color(0.92, 0.9, 0.86), "roof_col": Color(0.82, 0.84, 0.86)},
	"VTBS": {"plan": "midfield", "roof": "vault", "tower": "slender", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.78, 0.8, 0.84)},
	"RPLL": {"roof": "flat", "tower": "box", "levels": 2, "garages": 1, "clad": Color(0.92, 0.9, 0.84)},
	"WIII": {"roof": "gable", "tower": "classic", "levels": 1, "sats": 1, "garages": 1, "clad": Color(0.9, 0.86, 0.78), "roof_col": Color(0.4, 0.26, 0.2)},
	"VIDP": {"roof": "flat", "tower": "slender", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "clad": Color(0.86, 0.84, 0.8)},
	"VABB": {"roof": "shell", "tower": "flared", "levels": 3, "garages": 2, "hotel": 1, "clad": Color(0.92, 0.9, 0.86), "roof_col": Color(0.9, 0.86, 0.72)},
	"OMDB": {"plan": "midfield", "roof": "arch", "tower": "slender", "levels": 3, "gates": 44, "sats": 2, "garages": 3, "hotel": 2, "cargo": true,
		"clad": Color(0.95, 0.94, 0.9), "roof_col": Color(0.9, 0.9, 0.88), "tower_h": 100.0},
	"OTHH": {"plan": "midfield", "roof": "wave", "tower": "slender", "levels": 3, "sats": 1, "garages": 2, "hotel": 1, "cargo": true, "clad": Color(0.94, 0.93, 0.9), "tower_h": 88.0},
}


static func style_for(icao: String, size: String) -> Dictionary:
	var h := U.hash_str(icao + "style")
	var hub := size == "hub"
	var s := {
		"plan": "midfield" if hub else "linear",
		"roof": (ROOFS[h % ROOFS.size()] if hub else (["gable", "flat", "wave", "shell", "saw"][h % 5])),
		"tower": TOWERS[(h / 7) % TOWERS.size()] if hub else (["box", "classic", "box", "cylinder"][(h / 7) % 4]),
		"levels": 3 if hub else (2 if size == "regional" and (h / 11) % 3 == 0 else 1),
		"sats": 1 if hub else 0, "gates": 0, "garages": 2 if hub else (1 if size == "regional" else 0),
		"hotel": 1 if hub else 0, "cargo": hub, "sig": "", "rainbow": false,
		"clad": CLADS[(h / 13) % CLADS.size()], "roof_col": ROOF_COLS[(h / 17) % ROOF_COLS.size()],
		"frame": FRAME_COLS[(h / 19) % FRAME_COLS.size()], "accent": Color.from_hsv(float((h / 23) % 360) / 360.0, 0.55, 0.6),
		"tower_h": 0.0,
	}
	if TABLE.has(icao):
		var t: Dictionary = TABLE[icao]
		for k in t.keys():
			s[k] = t[k]
	return s
