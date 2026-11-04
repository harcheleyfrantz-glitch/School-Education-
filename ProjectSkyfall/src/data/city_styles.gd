extends RefCounted
## City styles: street pattern, block size, building mix from core to edge, facade and roof
## palettes for every airport city. Pure data - read by TerrainManager.build_chunk on worker
## threads, so prepare() fills the cache once on the main thread and style_for() never writes.
##
## pattern: grid (rotated by rot degrees), radial (rings and avenues around center),
##   canal (radial rings with canals), organic (warped old-town lanes), strip (grid with
##   towers along an axis), hillside (small warped blocks that climb steep ground).
## core/mid/edge: weighted building fills [[fill, weight], ...] (see TerrainManager._fill_lot).
## roof: roof families for the building shader (0 terracotta, 1 slate, 2 zinc, 3 brown tile,
##   4 dark glazed, 5 light metal, 6 shingle, 7 painted Nordic metal).


static var _cache := {}

# ------------------------------------------------------------------ palettes
const CREAM := [Color(0.92, 0.87, 0.76), Color(0.88, 0.83, 0.72), Color(0.94, 0.9, 0.82), Color(0.86, 0.8, 0.68), Color(0.9, 0.86, 0.78)]
const BRICK := [Color(0.62, 0.32, 0.24), Color(0.55, 0.3, 0.24), Color(0.7, 0.42, 0.3), Color(0.5, 0.28, 0.22), Color(0.66, 0.5, 0.38), Color(0.86, 0.84, 0.78)]
const DUTCH := [Color(0.42, 0.22, 0.18), Color(0.5, 0.26, 0.2), Color(0.3, 0.2, 0.18), Color(0.62, 0.36, 0.26), Color(0.85, 0.82, 0.74), Color(0.24, 0.22, 0.22)]
const MED := [Color(0.95, 0.92, 0.85), Color(0.92, 0.78, 0.56), Color(0.88, 0.66, 0.44), Color(0.94, 0.86, 0.7), Color(0.82, 0.55, 0.38), Color(0.96, 0.95, 0.92)]
const ROMAN := [Color(0.86, 0.6, 0.36), Color(0.8, 0.5, 0.3), Color(0.92, 0.76, 0.52), Color(0.74, 0.42, 0.28), Color(0.9, 0.82, 0.66)]
const STUCCO := [Color(0.9, 0.86, 0.78), Color(0.84, 0.8, 0.72), Color(0.92, 0.88, 0.8), Color(0.78, 0.72, 0.62), Color(0.86, 0.84, 0.8)]
const GERMAN := [Color(0.88, 0.84, 0.76), Color(0.82, 0.76, 0.64), Color(0.9, 0.88, 0.82), Color(0.76, 0.66, 0.54), Color(0.84, 0.78, 0.7), Color(0.72, 0.7, 0.68)]
const NORDIC := [Color(0.72, 0.2, 0.16), Color(0.9, 0.78, 0.4), Color(0.92, 0.92, 0.88), Color(0.3, 0.45, 0.6), Color(0.45, 0.55, 0.4), Color(0.85, 0.5, 0.3), Color(0.6, 0.15, 0.12)]
const SOVIET := [Color(0.82, 0.8, 0.76), Color(0.74, 0.74, 0.72), Color(0.86, 0.84, 0.8), Color(0.7, 0.66, 0.6), Color(0.8, 0.76, 0.66)]
const CONCRETE := [Color(0.8, 0.8, 0.78), Color(0.72, 0.72, 0.7), Color(0.86, 0.85, 0.82), Color(0.66, 0.66, 0.66), Color(0.78, 0.76, 0.72)]
const US_CITY := [Color(0.78, 0.74, 0.68), Color(0.66, 0.62, 0.58), Color(0.82, 0.8, 0.76), Color(0.6, 0.5, 0.42), Color(0.55, 0.6, 0.66), Color(0.86, 0.82, 0.7)]
const US_HOUSE := [Color(0.92, 0.9, 0.86), Color(0.8, 0.84, 0.86), Color(0.86, 0.8, 0.66), Color(0.7, 0.76, 0.72), Color(0.76, 0.6, 0.5), Color(0.9, 0.86, 0.74), Color(0.62, 0.66, 0.72)]
const SUNBELT := [Color(0.95, 0.9, 0.8), Color(0.92, 0.84, 0.7), Color(0.96, 0.94, 0.9), Color(0.88, 0.78, 0.66), Color(0.82, 0.86, 0.84), Color(0.95, 0.82, 0.72)]
const PASTEL := [Color(0.98, 0.84, 0.82), Color(0.82, 0.9, 0.96), Color(0.96, 0.94, 0.78), Color(0.84, 0.94, 0.86), Color(0.96, 0.96, 0.96), Color(0.9, 0.84, 0.94)]
const SAND := [Color(0.9, 0.82, 0.66), Color(0.86, 0.76, 0.6), Color(0.94, 0.9, 0.8), Color(0.82, 0.7, 0.54), Color(0.96, 0.94, 0.88)]
const CAIRO := [Color(0.76, 0.6, 0.44), Color(0.68, 0.5, 0.36), Color(0.82, 0.72, 0.58), Color(0.62, 0.42, 0.3), Color(0.86, 0.8, 0.68)]
const ASIA := [Color(0.88, 0.88, 0.86), Color(0.8, 0.8, 0.8), Color(0.92, 0.9, 0.86), Color(0.7, 0.7, 0.72), Color(0.84, 0.8, 0.74), Color(0.62, 0.64, 0.66)]
const TROPIC := [Color(0.92, 0.9, 0.84), Color(0.86, 0.8, 0.7), Color(0.8, 0.84, 0.82), Color(0.94, 0.86, 0.72), Color(0.76, 0.74, 0.7), Color(0.9, 0.78, 0.7)]
const INDIA := [Color(0.9, 0.82, 0.68), Color(0.86, 0.72, 0.56), Color(0.92, 0.88, 0.8), Color(0.82, 0.62, 0.5), Color(0.78, 0.8, 0.74), Color(0.94, 0.78, 0.66)]
const GLASS := [Color(0.42, 0.52, 0.62), Color(0.35, 0.45, 0.5), Color(0.55, 0.6, 0.65), Color(0.3, 0.38, 0.48), Color(0.5, 0.56, 0.52)]
const GLASS_GULF := [Color(0.5, 0.62, 0.72), Color(0.6, 0.66, 0.7), Color(0.42, 0.56, 0.66), Color(0.66, 0.62, 0.52)]

const LOT_PAVE := Color(0.6, 0.58, 0.55)
const LOT_GARDEN := Color(0.36, 0.44, 0.26)
const LOT_SAND := Color(0.8, 0.72, 0.58)
const LOT_DUST := Color(0.66, 0.6, 0.5)


static func _base() -> Dictionary:
	return {
		"pattern": "grid", "rot": 0.0, "bx": 95.0, "bz": 95.0, "core_frac": 0.16, "inner": 0.0,
		"core": [["boxes", 3], ["tower", 1]], "mid": [["boxes", 3], ["midrise", 2], ["sheds", 0.4]],
		"edge": [["houses", 4], ["boxes", 0.5], ["sheds", 0.4]],
		"h_core": [18.0, 45.0], "h_mid": [10.0, 22.0], "tower_h": [60.0, 140.0],
		"facade": US_CITY, "house": US_HOUSE, "glass": GLASS, "roof": [6, 1, 3],
		"box": "box_office", "house_mesh": "house", "court": "court_pitched",
		"lot": LOT_PAVE, "garden": LOT_GARDEN, "park_p": 0.04, "plaza_p": 0.02, "tree": "broad", "tree_p": 0.6,
		"avenues": 0, "ring_w": 120.0, "arc": 125.0, "warp": 0.0, "slope": 7.0,
	}


static func _preset(name: String) -> Dictionary:
	var s := _base()
	match name:
		"us_metro":
			s.merge({"bx": 90.0, "bz": 170.0, "core": [["tower", 3], ["boxes", 2], ["plaza", 0.2]],
				"mid": [["boxes", 3], ["terrace", 1], ["sheds", 0.5]], "edge": [["houses", 5], ["sheds", 0.3]],
				"h_core": [25.0, 70.0], "h_mid": [9.0, 24.0], "tower_h": [90.0, 220.0]}, true)
		"us_sunbelt":
			s.merge({"bx": 110.0, "bz": 140.0, "core": [["tower", 3], ["boxes", 2], ["plaza", 0.3]],
				"mid": [["boxes", 2], ["sheds", 1], ["houses", 2]], "edge": [["houses", 6], ["sheds", 0.4]],
				"h_core": [18.0, 50.0], "h_mid": [7.0, 16.0], "tower_h": [70.0, 180.0], "core_frac": 0.1,
				"house": SUNBELT, "facade": SUNBELT, "house_mesh": "hip_house", "roof": [0, 6, 3], "tree": "palm", "tree_p": 0.5}, true)
		"us_town":
			s.merge({"bx": 100.0, "bz": 120.0, "core": [["boxes", 3], ["shops", 2]], "mid": [["houses", 3], ["shops", 1], ["sheds", 0.4]],
				"edge": [["houses", 6]], "h_core": [8.0, 16.0], "h_mid": [6.0, 10.0], "tower_h": [20.0, 30.0], "core_frac": 0.1,
				"house_mesh": "wood_house", "tree_p": 0.9}, true)
		"paris":
			s.merge({"pattern": "radial", "ring_w": 118.0, "arc": 130.0, "avenues": 12, "inner": 0.5,
				"core": [["court_mansard", 8], ["park", 0.4], ["plaza", 0.3]], "mid": [["court_mansard", 6], ["midrise", 1], ["park", 0.3]],
				"edge": [["slabs", 2], ["houses", 3], ["midrise", 1], ["sheds", 0.4]],
				"h_core": [20.0, 26.0], "h_mid": [17.0, 24.0], "tower_h": [60.0, 110.0],
				"facade": CREAM, "court": "court_mansard", "roof": [2, 2, 1], "house": STUCCO, "house_mesh": "hip_house",
				"lot": Color(0.66, 0.62, 0.56), "park_p": 0.03}, true)
		"london":
			s.merge({"pattern": "organic", "bx": 110.0, "bz": 80.0, "warp": 1.0, "rot": 8.0,
				"core": [["boxes", 3], ["court_pitched", 2], ["terrace", 2], ["tower", 0.5], ["park", 0.3]],
				"mid": [["terrace", 7], ["court_pitched", 1], ["park", 0.4]], "edge": [["terrace", 5], ["houses", 2]],
				"h_core": [18.0, 34.0], "h_mid": [9.0, 12.0], "tower_h": [60.0, 140.0],
				"facade": BRICK, "house": BRICK, "roof": [1, 1, 3], "court": "court_pitched", "park_p": 0.06}, true)
		"amsterdam":
			s.merge({"pattern": "canal", "ring_w": 96.0, "arc": 110.0, "inner": 0.32,
				"core": [["canal", 9], ["plaza", 0.3]], "mid": [["canal", 5], ["court_pitched", 2], ["park", 0.3]],
				"edge": [["terrace", 3], ["slabs", 1], ["houses", 2]], "h_core": [14.0, 18.0], "h_mid": [12.0, 18.0],
				"facade": DUTCH, "house": DUTCH, "roof": [1, 3, 0], "tree": "broad", "bx": 90.0, "bz": 110.0, "rot": 12.0}, true)
		"med":
			s.merge({"pattern": "organic", "bx": 95.0, "bz": 85.0, "warp": 1.2,
				"core": [["court_pitched", 5], ["midrise", 3], ["plaza", 0.6]], "mid": [["midrise", 4], ["court_pitched", 2], ["boxes", 1]],
				"edge": [["villas", 3], ["midrise", 2], ["houses", 1]], "h_core": [14.0, 22.0], "h_mid": [10.0, 22.0],
				"facade": ROMAN, "house": MED, "roof": [0, 0, 3], "house_mesh": "hip_house", "box": "box_stucco",
				"lot": Color(0.72, 0.64, 0.52), "tree": "palm", "tree_p": 0.4}, true)
		"barcelona":
			s.merge({"bx": 113.0, "bz": 113.0, "rot": 45.0, "core": [["court_flat", 9], ["plaza", 0.3]],
				"mid": [["court_flat", 8], ["park", 0.2]], "edge": [["midrise", 3], ["boxes", 1]], "h_core": [18.0, 24.0], "h_mid": [16.0, 22.0],
				"facade": MED, "court": "court_flat", "roof": [0], "box": "box_stucco", "tree": "palm", "tree_p": 0.3}, true)
		"central":
			s.merge({"pattern": "organic", "bx": 105.0, "bz": 95.0, "warp": 0.8,
				"core": [["court_pitched", 7], ["plaza", 0.4], ["tower", 0.3]], "mid": [["court_pitched", 5], ["midrise", 2], ["park", 0.3]],
				"edge": [["houses", 4], ["slabs", 1], ["sheds", 0.6]], "h_core": [16.0, 24.0], "h_mid": [13.0, 20.0],
				"facade": GERMAN, "house": GERMAN, "roof": [0, 3, 0, 1], "house_mesh": "house"}, true)
		"nordic":
			s.merge({"pattern": "organic", "bx": 95.0, "bz": 85.0, "warp": 0.7,
				"core": [["court_pitched", 5], ["midrise", 2], ["plaza", 0.3]], "mid": [["court_pitched", 2], ["slabs", 1], ["houses", 2]],
				"edge": [["houses", 6]], "h_core": [14.0, 22.0], "h_mid": [10.0, 18.0],
				"facade": GERMAN, "house": NORDIC, "roof": [7, 1, 3], "house_mesh": "wood_house", "tree": "birch", "tree_p": 0.7}, true)
		"nordic_town":
			s.merge({"pattern": "organic", "bx": 100.0, "bz": 90.0, "warp": 1.0, "core": [["houses", 3], ["midrise", 1]],
				"mid": [["houses", 4], ["slabs", 0.5]], "edge": [["houses", 5]], "h_core": [8.0, 12.0], "h_mid": [8.0, 14.0],
				"facade": NORDIC, "house": NORDIC, "roof": [7], "house_mesh": "wood_house", "tree": "birch", "tree_p": 0.25, "box": "box_panel"}, true)
		"moscow":
			s.merge({"pattern": "radial", "ring_w": 160.0, "arc": 170.0, "avenues": 10, "inner": 0.25,
				"core": [["court_pitched", 4], ["court_flat", 2], ["plaza", 0.3]], "mid": [["slabs", 6], ["court_flat", 1], ["park", 0.4]],
				"edge": [["slabs", 6], ["sheds", 1]], "h_core": [18.0, 30.0], "h_mid": [27.0, 50.0], "tower_h": [60.0, 120.0],
				"bx": 160.0, "bz": 140.0, "rot": -15.0,
				"facade": SOVIET, "house": SOVIET, "roof": [2, 5], "court": "court_flat", "box": "box_panel", "tree": "birch", "lot": Color(0.42, 0.46, 0.3)}, true)
		"tokyo":
			s.merge({"bx": 95.0, "bz": 85.0, "rot": 0.0, "pattern": "organic", "warp": 0.6,
				"core": [["tower", 3], ["boxes", 4], ["slim", 1]], "mid": [["boxes", 3], ["houses", 3], ["midrise", 2]],
				"edge": [["houses", 6], ["boxes", 1]], "h_core": [25.0, 70.0], "h_mid": [8.0, 26.0], "tower_h": [100.0, 220.0],
				"facade": ASIA, "house": ASIA, "roof": [4, 4, 5], "house_mesh": "house", "tree_p": 0.15, "lot": Color(0.58, 0.58, 0.56),
				"garden": Color(0.5, 0.5, 0.47)}, true)
		"seoul":
			s.merge({"bx": 150.0, "bz": 120.0, "rot": 12.0, "core": [["tower", 3], ["boxes", 3]],
				"mid": [["slabs", 6], ["boxes", 1]], "edge": [["slabs", 4], ["houses", 2]], "h_core": [30.0, 70.0], "h_mid": [45.0, 70.0],
				"tower_h": [100.0, 200.0], "facade": CONCRETE, "house": ASIA, "roof": [4, 5], "box": "box_panel"}, true)
		"china":
			s.merge({"bx": 170.0, "bz": 150.0, "rot": 0.0, "core": [["tower", 4], ["boxes", 2], ["plaza", 0.3]],
				"mid": [["slim", 4], ["slabs", 2]], "edge": [["slabs", 3], ["court_pitched", 1], ["sheds", 1]],
				"h_core": [30.0, 80.0], "h_mid": [40.0, 80.0], "tower_h": [120.0, 260.0],
				"facade": CONCRETE, "house": ASIA, "roof": [4, 5], "box": "box_panel", "court": "court_pitched"}, true)
		"hongkong":
			s.merge({"pattern": "hillside", "bx": 90.0, "bz": 80.0, "warp": 1.0, "slope": 30.0,
				"core": [["tower", 3], ["slim", 4]], "mid": [["slim", 6], ["boxes", 1]], "edge": [["slim", 3], ["villas", 1]],
				"h_core": [40.0, 90.0], "h_mid": [30.0, 60.0], "tower_h": [110.0, 240.0],
				"facade": CONCRETE, "house": TROPIC, "roof": [4, 5], "box": "box_stucco", "tree": "broad"}, true)
		"tropic_asia":
			s.merge({"pattern": "organic", "bx": 90.0, "bz": 80.0, "warp": 0.9,
				"core": [["tower", 3], ["slim", 2], ["boxes", 2]], "mid": [["shops", 5], ["boxes", 2], ["slim", 1]],
				"edge": [["shops", 3], ["houses", 3], ["sheds", 0.6]], "h_core": [30.0, 80.0], "h_mid": [10.0, 18.0],
				"tower_h": [100.0, 220.0], "facade": TROPIC, "house": TROPIC, "roof": [5, 0, 3], "box": "box_stucco",
				"house_mesh": "hip_house", "tree": "palm", "tree_p": 0.5}, true)
		"singapore":
			s.merge({"bx": 160.0, "bz": 130.0, "rot": 20.0, "pattern": "organic", "warp": 0.6,
				"core": [["tower", 4], ["boxes", 1], ["park", 0.4]], "mid": [["slim", 4], ["slabs", 3], ["park", 0.5]],
				"edge": [["slabs", 3], ["slim", 2], ["villas", 1]], "h_core": [40.0, 90.0], "h_mid": [40.0, 70.0],
				"tower_h": [120.0, 250.0], "facade": TROPIC, "house": TROPIC, "roof": [0, 5], "box": "box_panel",
				"tree": "palm", "tree_p": 0.8, "park_p": 0.08, "lot": Color(0.44, 0.52, 0.32)}, true)
		"india":
			s.merge({"pattern": "organic", "bx": 95.0, "bz": 85.0, "warp": 1.3,
				"core": [["boxes", 3], ["court_flat", 2], ["tower", 0.5]], "mid": [["boxes", 4], ["shops", 3]],
				"edge": [["shops", 3], ["boxes", 2], ["villas", 1]], "h_core": [12.0, 30.0], "h_mid": [8.0, 16.0],
				"facade": INDIA, "house": INDIA, "roof": [5, 0], "box": "box_stucco", "court": "court_flat",
				"lot": LOT_DUST, "tree": "broad", "tree_p": 0.3}, true)
		"gulf":
			s.merge({"pattern": "strip", "bx": 130.0, "bz": 110.0, "rot": 40.0,
				"core": [["tower", 6], ["slim", 2]], "mid": [["boxes", 2], ["villas", 3], ["sheds", 0.4]],
				"edge": [["villas", 6], ["sheds", 0.5]], "h_core": [30.0, 70.0], "h_mid": [8.0, 16.0], "tower_h": [140.0, 320.0],
				"facade": SAND, "house": SAND, "glass": GLASS_GULF, "roof": [5], "box": "box_stucco",
				"lot": LOT_SAND, "garden": Color(0.74, 0.66, 0.5), "tree": "palm", "tree_p": 0.5}, true)
		"cairo":
			s.merge({"pattern": "organic", "bx": 90.0, "bz": 80.0, "warp": 1.3,
				"core": [["boxes", 4], ["court_flat", 3]], "mid": [["boxes", 5], ["shops", 2]], "edge": [["boxes", 3], ["shops", 2]],
				"h_core": [15.0, 35.0], "h_mid": [12.0, 30.0], "facade": CAIRO, "house": CAIRO, "roof": [5],
				"box": "box_stucco", "court": "court_flat", "lot": LOT_DUST, "tree": "palm", "tree_p": 0.15, "park_p": 0.01}, true)
		"island":
			s.merge({"pattern": "organic", "bx": 95.0, "bz": 85.0, "warp": 1.2, "slope": 14.0,
				"core": [["midrise", 2], ["shops", 2], ["plaza", 0.3]], "mid": [["villas", 2], ["houses", 3]],
				"edge": [["houses", 4], ["villas", 2]], "h_core": [9.0, 14.0], "h_mid": [6.0, 10.0],
				"facade": MED, "house": MED, "roof": [0], "house_mesh": "hip_house", "box": "box_stucco", "tree": "palm"}, true)
	return s


## Per-city preset plus overrides. center: optional absolute world [x, z] for the street pattern.
const CITY := {
	"New York": ["us_metro", {"rot": 29.0, "bx": 80.0, "bz": 230.0, "facade": [Color(0.66, 0.42, 0.32), Color(0.78, 0.72, 0.62), Color(0.58, 0.36, 0.28), Color(0.82, 0.8, 0.74), Color(0.6, 0.58, 0.56)],
		"mid": [["boxes", 4], ["terrace", 2], ["sheds", 0.4]], "h_mid": [12.0, 26.0], "core_frac": 0.22}],
	"Boston": ["us_metro", {"pattern": "organic", "bx": 90.0, "bz": 110.0, "warp": 1.0, "facade": BRICK, "house": US_HOUSE,
		"mid": [["terrace", 5], ["boxes", 1]], "edge": [["houses", 5]], "house_mesh": "wood_house"}],
	"Washington": ["us_metro", {"pattern": "radial", "ring_w": 120.0, "arc": 125.0, "avenues": 8, "inner": 0.45,
		"core": [["court_flat", 4], ["boxes", 3], ["park", 0.5]], "mid": [["terrace", 4], ["boxes", 2]], "h_core": [20.0, 40.0],
		"tower_h": [35.0, 45.0], "facade": CREAM, "court": "court_flat"}],
	"Chicago": ["us_metro", {"bx": 100.0, "bz": 200.0, "rot": 0.0}],
	"Toronto": ["us_metro", {"rot": -17.0, "bx": 100.0, "bz": 180.0, "mid": [["boxes", 2], ["terrace", 2], ["slim", 1]]}],
	"Miami": ["us_sunbelt", {"rot": 0.0, "facade": PASTEL, "house": PASTEL, "core": [["slim", 3], ["tower", 3]]}],
	"Los Angeles": ["us_sunbelt", {"bx": 120.0, "bz": 200.0, "rot": 0.0, "core_frac": 0.05}],
	"San Francisco": ["us_metro", {"bx": 85.0, "bz": 140.0, "rot": 0.0, "slope": 16.0, "facade": PASTEL, "house": PASTEL,
		"mid": [["terrace", 6], ["boxes", 1]], "edge": [["terrace", 4], ["houses", 2]]}],
	"Seattle": ["us_metro", {"rot": -10.0, "bx": 100.0, "bz": 120.0, "house_mesh": "wood_house", "tree": "spruce"}],
	"Denver": ["us_sunbelt", {"rot": 45.0, "house": US_HOUSE, "facade": US_CITY, "tree": "broad", "house_mesh": "house", "roof": [6, 3]}],
	"Las Vegas": ["us_sunbelt", {"pattern": "strip", "rot": 0.0, "lot": LOT_SAND, "facade": SAND, "house": SAND,
		"core": [["tower", 5], ["boxes", 2]], "tree_p": 0.15}],
	"Atlanta": ["us_sunbelt", {"tree": "broad", "tree_p": 1.0, "house": US_HOUSE, "house_mesh": "house", "roof": [6]}],
	"Dallas": ["us_sunbelt", {"house": US_HOUSE, "tree": "broad", "roof": [6, 3]}],
	"Orlando": ["us_sunbelt", {"core": [["boxes", 3], ["tower", 1]], "tower_h": [60.0, 110.0]}],
	"New Orleans": ["us_sunbelt", {"pattern": "organic", "warp": 1.0, "bx": 90.0, "bz": 90.0, "facade": PASTEL, "house": PASTEL,
		"mid": [["terrace", 3], ["houses", 4]], "tree": "broad", "house_mesh": "house"}],
	"Gander": ["us_town", {"house": NORDIC, "tree": "spruce"}],
	"Oren Falls": ["us_town", {}],
	"Willowbrook": ["us_town", {"house_mesh": "house", "tree_p": 1.2}],
	"Port Calder": ["us_metro", {"rot": 15.0, "bx": 110.0, "bz": 150.0}],
	"Northgate": ["central", {}],
	"Rivermouth": ["london", {"pattern": "organic", "core": [["terrace", 3], ["court_pitched", 2]], "mid": [["terrace", 5], ["houses", 2]]}],
	"Aldmoor": ["london", {}],
	"Highpass": ["nordic_town", {"house": GERMAN, "roof": [3, 1], "tree": "spruce", "slope": 14.0}],
	"Skerra": ["nordic_town", {}],
	"Marea": ["island", {}],
	"Sable Bay": ["tropic_asia", {"core": [["slim", 2], ["boxes", 2]], "mid": [["villas", 3], ["houses", 2]], "facade": PASTEL, "house": PASTEL}],
	"London": ["london", {"center": [634640.0, 1157420.0]}],
	"Manchester": ["london", {"core": [["boxes", 3], ["court_pitched", 2], ["sheds", 1], ["tower", 0.4]]}],
	"Edinburgh": ["london", {"facade": [Color(0.62, 0.58, 0.52), Color(0.56, 0.52, 0.48), Color(0.7, 0.66, 0.58)], "house": GERMAN, "roof": [1]}],
	"Dublin": ["london", {"facade": [Color(0.6, 0.3, 0.22), Color(0.66, 0.36, 0.26), Color(0.54, 0.28, 0.22), Color(0.88, 0.84, 0.76)]}],
	"Paris": ["paris", {"center": [661570.0, 1221120.0]}],
	"Brussels": ["paris", {"pattern": "organic", "warp": 1.0, "bx": 100.0, "bz": 80.0, "roof": [1, 2, 3], "facade": GERMAN,
		"core": [["court_mansard", 3], ["court_pitched", 3], ["canal", 1]], "mid": [["terrace", 4], ["court_pitched", 2]]}],
	"Amsterdam": ["amsterdam", {}],
	"Madrid": ["med", {"pattern": "grid", "bx": 110.0, "bz": 100.0, "rot": 8.0, "facade": STUCCO,
		"core": [["court_flat", 4], ["court_pitched", 3], ["plaza", 0.4]], "mid": [["court_flat", 3], ["slabs", 2], ["midrise", 2]]}],
	"Barcelona": ["barcelona", {}],
	"Rome": ["med", {}],
	"Lisbon": ["med", {"facade": [Color(0.95, 0.9, 0.8), Color(0.92, 0.82, 0.6), Color(0.82, 0.56, 0.48), Color(0.7, 0.78, 0.86), Color(0.96, 0.95, 0.92)], "slope": 14.0}],
	"Athens": ["med", {"facade": [Color(0.94, 0.93, 0.9), Color(0.9, 0.88, 0.82), Color(0.86, 0.84, 0.8)], "roof": [5],
		"core": [["boxes", 5], ["court_flat", 2]], "mid": [["boxes", 5], ["midrise", 1]], "box": "box_stucco", "h_mid": [12.0, 22.0]}],
	"Istanbul": ["med", {"facade": [Color(0.92, 0.88, 0.8), Color(0.86, 0.8, 0.7), Color(0.8, 0.72, 0.62), Color(0.9, 0.86, 0.84)],
		"mid": [["boxes", 4], ["midrise", 3]], "slope": 14.0, "h_mid": [14.0, 26.0]}],
	"Ponta Delgada": ["island", {"house": [Color(0.97, 0.97, 0.95), Color(0.95, 0.95, 0.92)]}],
	"Funchal": ["island", {"slope": 22.0}],
	"Hamilton": ["island", {"house": PASTEL, "facade": PASTEL, "roof": [5]}],
	"Frankfurt": ["central", {"core": [["tower", 4], ["boxes", 2], ["court_pitched", 2]], "tower_h": [100.0, 200.0]}],
	"Munich": ["central", {"facade": [Color(0.92, 0.88, 0.76), Color(0.88, 0.8, 0.62), Color(0.9, 0.86, 0.82), Color(0.84, 0.74, 0.6)], "roof": [0, 0, 3]}],
	"Berlin": ["central", {"pattern": "grid", "bx": 140.0, "bz": 120.0, "rot": 6.0, "court": "court_pitched",
		"mid": [["court_pitched", 6], ["slabs", 2], ["park", 0.4]], "roof": [0, 1, 3]}],
	"Zurich": ["central", {"slope": 14.0}],
	"Vienna": ["central", {"pattern": "radial", "ring_w": 120.0, "arc": 125.0, "avenues": 0, "inner": 0.4,
		"facade": [Color(0.94, 0.88, 0.72), Color(0.9, 0.86, 0.8), Color(0.92, 0.84, 0.62), Color(0.86, 0.82, 0.78)]}],
	"Copenhagen": ["nordic", {"facade": [Color(0.86, 0.66, 0.4), Color(0.92, 0.86, 0.7), Color(0.66, 0.36, 0.26), Color(0.88, 0.8, 0.6)], "roof": [0, 1]}],
	"Oslo": ["nordic", {"slope": 14.0}],
	"Stockholm": ["nordic", {"facade": [Color(0.86, 0.6, 0.3), Color(0.9, 0.82, 0.62), Color(0.72, 0.36, 0.24), Color(0.92, 0.9, 0.84)], "roof": [2, 1, 0]}],
	"Reykjavik": ["nordic_town", {"tree_p": 0.1, "house": [Color(0.92, 0.92, 0.9), Color(0.82, 0.2, 0.16), Color(0.94, 0.86, 0.4), Color(0.3, 0.42, 0.6)]}],
	"Torshavn": ["nordic_town", {"slope": 16.0}],
	"Nuuk": ["nordic_town", {"tree_p": 0.0, "mid": [["slabs", 3], ["houses", 3]]}],
	"Moscow": ["moscow", {}],
	"Tokyo": ["tokyo", {}],
	"Osaka": ["tokyo", {"pattern": "grid", "rot": 0.0, "bx": 95.0, "bz": 95.0}],
	"Seoul": ["seoul", {}],
	"Beijing": ["china", {"core": [["court_pitched", 4], ["tower", 2], ["park", 0.6]], "h_core": [5.0, 9.0], "roof": [4],
		"facade": [Color(0.5, 0.5, 0.52), Color(0.56, 0.54, 0.5), Color(0.46, 0.44, 0.44)]}],
	"Shanghai": ["china", {"rot": 15.0, "core": [["tower", 6], ["slim", 2]]}],
	"Taipei": ["china", {"bx": 120.0, "bz": 100.0, "mid": [["boxes", 4], ["shops", 3], ["slim", 1]], "h_mid": [12.0, 30.0], "box": "box_stucco"}],
	"Hong Kong": ["hongkong", {}],
	"Singapore": ["singapore", {}],
	"Kuala Lumpur": ["singapore", {"park_p": 0.04, "mid": [["slim", 3], ["shops", 3]]}],
	"Bangkok": ["tropic_asia", {}],
	"Manila": ["tropic_asia", {"roof": [5, 5, 0]}],
	"Jakarta": ["tropic_asia", {"roof": [0, 0, 5]}],
	"Delhi": ["india", {"pattern": "radial", "ring_w": 110.0, "arc": 120.0, "avenues": 8, "inner": 0.12,
		"facade": [Color(0.94, 0.94, 0.9), Color(0.9, 0.88, 0.8), Color(0.86, 0.82, 0.74)]}],
	"Mumbai": ["india", {"core": [["slim", 3], ["tower", 2], ["boxes", 2]], "mid": [["boxes", 3], ["slim", 2], ["shops", 2]], "h_mid": [12.0, 40.0]}],
	"Dubai": ["gulf", {}],
	"Doha": ["gulf", {"rot": 20.0, "core": [["tower", 5], ["boxes", 2]]}],
	"Cairo": ["cairo", {}],
}

const COUNTRY := {
	"United States": "us_metro", "Canada": "us_metro", "United Kingdom": "london", "Ireland": "london", "France": "paris",
	"Germany": "central", "Austria": "central", "Switzerland": "central", "Belgium": "central", "Netherlands": "amsterdam",
	"Spain": "med", "Italy": "med", "Portugal": "med", "Greece": "med", "Turkey": "med", "Iceland": "nordic_town",
	"Norway": "nordic", "Sweden": "nordic", "Denmark": "nordic", "Russia": "moscow", "Japan": "tokyo", "South Korea": "seoul",
	"China": "china", "Taiwan": "china", "Hong Kong": "hongkong", "Singapore": "singapore", "Malaysia": "singapore",
	"Thailand": "tropic_asia", "Philippines": "tropic_asia", "Indonesia": "tropic_asia", "India": "india",
	"United Arab Emirates": "gulf", "Qatar": "gulf", "Egypt": "cairo", "Calderra": "us_metro", "Westmark": "london",
}


## Countries that drive on the left.
const LEFT_HAND := ["United Kingdom", "Ireland", "Japan", "Hong Kong", "Singapore", "Malaysia", "Thailand", "India",
	"Indonesia", "Westmark"]
## Traffic mix by city preset: [sedan, suv, hatch, van, bus] weights.
const CAR_MIX := {
	"default": [5.0, 2.0, 3.0, 1.0, 0.4], "us_metro": [5.0, 5.0, 0.6, 0.8, 0.4], "us_sunbelt": [4.0, 6.0, 0.4, 0.8, 0.3],
	"us_town": [4.0, 6.0, 0.5, 0.6, 0.1], "tokyo": [3.0, 0.8, 6.0, 1.4, 0.5], "seoul": [5.0, 2.0, 3.0, 1.0, 0.6],
	"gulf": [4.0, 6.0, 0.6, 0.8, 0.3], "paris": [3.0, 1.0, 6.0, 1.2, 0.5], "london": [3.5, 1.5, 5.0, 1.2, 0.6],
	"central": [4.0, 1.5, 4.5, 1.2, 0.5], "amsterdam": [3.0, 1.0, 6.0, 1.0, 0.5], "med": [3.0, 0.8, 6.0, 1.0, 0.5],
	"india": [3.0, 1.0, 5.0, 1.5, 1.2], "cairo": [4.0, 1.0, 4.0, 1.5, 1.0], "china": [5.0, 3.0, 2.5, 1.0, 0.8],
}
## Car colour palette by country: 0 mixed, 1 Japan (white, silver, black), 2 Gulf (white SUVs), 3 New York (yellow cabs).
const CAR_PAL := {"Japan": 1, "United Arab Emirates": 2, "Qatar": 2, "Saudi Arabia": 2, "South Korea": 1, "China": 1}


## Build every city's style on the main thread (worker threads only read the cache).
static func prepare(cities: Array) -> void:
	for c in cities:
		var key := String(c.get("name", ""))
		if not _cache.has(key):
			_cache[key] = _make(c)


static func style_for(city: Dictionary) -> Dictionary:
	var key := String(city.get("name", ""))
	if _cache.has(key):
		return _cache[key]
	return _make(city)       # not cached: keeps worker threads read-only


static func _make(city: Dictionary) -> Dictionary:
	var name := String(city.get("name", ""))
	var entry: Array = CITY.get(name, [COUNTRY.get(String(city.get("country", "")), "us_metro"), {}])
	var s := _preset(String(entry[0]))
	var over: Dictionary = entry[1]
	s.merge(over, true)
	var r := float(city.get("r", 5000.0))
	var rc := float(city.get("r_core", r))
	if rc < 3000.0 and String(entry[0]) in ["us_metro", "us_sunbelt"]:
		s.merge(_preset("us_town"), true)
	var cen: Array = s.get("center", [float(city.get("x", 0.0)), float(city.get("z", 0.0))])
	s["cx"] = float(cen[0])
	s["cz"] = float(cen[1])
	s["r"] = r
	s["r_core"] = rc
	s["tall"] = clampf(float(city.get("tall", 0.7)), 0.15, 2.2)
	s["name"] = name
	# secondary business districts across a big metro (Shinjuku, La Defense, Canary Wharf)
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash_str(name + "subs")
	var subs := []
	var pop := int(city.get("pop", 0))
	var n_sub := 0 if r < rc * 1.5 else clampi(pop / 1500000 + 1, 1, 7)
	for k in n_sub:
		var ang := rng.randf() * TAU
		var dist := r * rng.randf_range(0.22, 0.62)
		subs.append([s.cx + cos(ang) * dist, s.cz + sin(ang) * dist, rng.randf_range(650.0, 1300.0)])
	s["subs"] = subs
	var country := String(city.get("country", ""))
	s["lht"] = country in LEFT_HAND
	s["cars"] = CAR_MIX.get(String(entry[0]), CAR_MIX["default"])
	s["car_pal"] = int(CAR_PAL.get(country, 0))
	# shop signs and neon: East Asian cities and the Las Vegas Strip
	s["signs"] = 1 if String(entry[0]) in ["tokyo", "seoul", "china", "hongkong", "tropic_asia"] or name == "Las Vegas" else 0
	# cumulative weights for the three zones
	for z in ["core", "mid", "edge"]:
		var lst: Array = s[z]
		var tot := 0.0
		for e in lst:
			tot += float(e[1])
		s[z + "_w"] = tot
	return s


static func pick_fill(s: Dictionary, zone: String, roll: float) -> String:
	var lst: Array = s[zone]
	var t := roll * float(s[zone + "_w"])
	for e in lst:
		t -= float(e[1])
		if t <= 0.0:
			return String(e[0])
	return String(lst[lst.size() - 1][0]) if not lst.is_empty() else "boxes"
