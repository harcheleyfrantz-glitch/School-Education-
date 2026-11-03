class_name Airlines
## Fictional operators. Livery colours feed the aircraft paint shader.

const ORDER := ["SKF", "CLK", "LMN", "NWC", "APX", "HFA", "WMA", "AUR", "PEL", "VTX", "LBA", "THA", "LUE", "GGP", "MPN", "AUN", "IHA", "SOL", "TFX", "LSA", "RHA", "NRD", "ALP"]

const DATA := {
	"GOV": {
		"name": "Calderra State Flight", "callsign": "CALDERRA", "iata": "CS", "kind": "government",
		"hubs": ["SKPC"], "country": "Calderra", "reg_prefix": "CR-G",
		"fleet": {"w380": 1, "s321": 1},
		"livery": {"body": "f7f7f2", "belly": "1d3a6e", "stripe": "c9a227", "stripe2": "1d3a6e", "tail": "1d3a6e", "tail2": "c9a227", "logo": "c9a227", "logo_shape": 7,
			"art": "c9a227", "engine": "1d3a6e", "engine2": "c9a227", "engine_style": 3, "tip": "c9a227", "text": "1d3a6e",
			"belly_h": -0.35, "nose_dip": 0.05, "rise_t": 0.55, "rise_h": 0.6, "stripes": [0.05, 0.02, 0.1, 0.006], "stripe_t": [0.04, 0.96],
			"title": "REPUBLIC OF CALDERRA", "title_style": "serif", "title_size": 0.95},
		"pay": 2.0, "reputation": 99, "ceo": "The Presidential Office", "spokes": "Marta Ellison",
		"desc": "The presidential transport squadron: the head of state, two fighter escorts, no margin for error.",
		"standards": 0.99,
	},
	"SKF": {
		"name": "Skyfall Air", "callsign": "SKYFALL", "iata": "SF", "kind": "mainline",
		"hubs": ["SKPC"], "country": "Calderra", "reg_prefix": "CR-S",
		"fleet": {"s320": 18, "s321": 6, "w350": 6, "w380": 2, "rj90": 8, "s319": 4, "w280": 3},
		"livery": {"body": "f4f6f9", "belly": "1c3f74", "stripe": "f28c28", "stripe2": "f6a03c", "tail": "1c3f74", "tail2": "f28c28", "logo": "f6a03c", "logo_shape": 0,
			"art": "f28c28", "engine": "1c3f74", "engine2": "f28c28", "engine_style": 1, "tip": "1c3f74", "text": "1c3f74",
			"belly_h": -0.62, "nose_dip": -0.12, "rise_t": 0.6, "rise_h": 0.9, "stripes": [0.07, 0.022, 0.125, 0.008], "stripe_t": [0.08, 0.97],
			"title": "SKYFALL", "title_style": "wide", "title_size": 1.05},
		"pay": 1.0, "reputation": 72, "ceo": "Helena Marsh", "spokes": "Daniel Okoro",
		"desc": "Calderra's flag carrier. Premium service, strict standards, and the fastest route to the left seat of a wide-body.",
		"standards": 0.85,
	},
	"CLK": {
		"name": "Coastal Link", "callsign": "COASTAL", "iata": "CL", "kind": "regional",
		"hubs": ["SKPC", "SKSB"], "country": "Calderra", "reg_prefix": "CR-C",
		"fleet": {"tp72": 10, "tp50": 6, "rj90": 6, "rj70": 4, "tp90": 3, "rj100": 2},
		"livery": {"body": "ffffff", "belly": "e8eef0", "stripe": "13a6a6", "tail": "0f8f94", "tail2": "13a6a6", "logo": "ffffff", "logo_shape": 1,
			"art": "ffffff", "engine": "e6ebee", "engine_style": 3, "tip": "0f8f94", "text": "0f8f94",
			"belly_h": -0.75, "stripes": [0.6, 0.012, 0.0, 0.0], "flow_t": 0.64, "flow_h": 1.2, "title": "COASTAL LINK", "title_style": "italic"},
		"pay": 0.75, "reputation": 64, "ceo": "Marco Bellweather", "spokes": "Priya Venkat",
		"desc": "The regional network that links every island and valley. Short sectors, many landings, great training.",
		"standards": 0.7,
	},
	"LMN": {
		"name": "Lumen Airways", "callsign": "LUMEN", "iata": "LU", "kind": "lowcost",
		"hubs": ["SKNG", "SKPC"], "country": "Calderra", "reg_prefix": "CR-L",
		"fleet": {"s320": 12, "s321": 6},
		"livery": {"body": "ffffff", "belly": "ffd21f", "stripe": "5b2a86", "tail": "5b2a86", "tail2": "ffd21f", "logo": "ffd21f", "logo_shape": 2,
			"art": "ffffff", "engine": "5b2a86", "engine2": "ffd21f", "engine_style": 1, "tip": "ffd21f", "text": "5b2a86",
			"belly_h": -0.45, "nose_dip": 0.25, "rise_t": 0.5, "rise_h": 1.3, "stripes": [0.05, 0.035, 0.0, 0.0], "flow_t": 0.82, "flow_h": 0.8,
			"title": "LUMEN", "title_style": "italic", "title_size": 2.0, "title_pos": 0.08},
		"pay": 0.82, "reputation": 51, "ceo": "Viktor Lindqvist", "spokes": "Amara Diallo",
		"desc": "Bright yellow and always on the move. Quick turnarounds and tight schedules are the norm.",
		"standards": 0.6,
	},
	"NWC": {
		"name": "Northwind Cargo", "callsign": "NORTHWIND", "iata": "NW", "kind": "cargo",
		"hubs": ["SKNG"], "country": "Calderra", "reg_prefix": "CR-N",
		"fleet": {"f4": 5},
		"livery": {"body": "d9dde2", "belly": "8e959c", "stripe": "c0262d", "stripe2": "c0262d", "tail": "c0262d", "tail2": "ffffff", "logo": "ffffff",
			"logo_shape": 3, "art": "ffffff", "engine": "8e959c", "engine_style": 3, "tip": "c0262d", "text": "c0262d", "wing": "c4c8cc",
			"belly_h": -0.7, "stripes": [0.06, 0.03, 0.12, 0.008], "flow_t": 0.86, "flow_h": 0.6, "title": "NORTHWIND", "title_style": "wide"},
		"pay": 1.05, "reputation": 66, "ceo": "Gunnar Halvorsen", "spokes": "Lucia Ferreira",
		"desc": "Heavy freight through the night. No passengers, long hours, the biggest aircraft in the region.",
		"standards": 0.75,
	},
	"APX": {
		"name": "Apex Executive", "callsign": "APEX", "iata": "AX", "kind": "charter",
		"hubs": ["SKPC", "SKSB"], "country": "Calderra", "reg_prefix": "CR-X",
		"fleet": {"bj6": 6, "bj8": 2},
		"livery": {"body": "fbfaf7", "belly": "1d1d1f", "stripe": "c9a227", "stripe2": "c9a227", "tail": "1d1d1f", "tail2": "c9a227", "logo": "c9a227",
			"logo_shape": 4, "art": "c9a227", "engine": "1d1d1f", "tip": "1d1d1f", "text": "1d1d1f", "reg_col": "1d1d1f",
			"belly_h": -0.82, "nose_dip": -0.1, "rise_t": 0.5, "rise_h": 0.7, "stripes": [0.035, 0.012, 0.07, 0.005],
			"title": "APEX", "title_style": "light", "title_size": 0.75},
		"pay": 1.1, "reputation": 70, "ceo": "Isabelle Fontaine", "spokes": "Rafael Moreno",
		"desc": "Private aviation for people whose schedules cannot wait. Discretion and perfection are expected.",
		"standards": 0.9,
	},
	"HFA": {
		"name": "Horizon Flight Academy", "callsign": "HORIZON", "iata": "HZ", "kind": "school",
		"hubs": ["SKWF"], "country": "Calderra", "reg_prefix": "CR-H",
		"fleet": {"t172": 12},
		"livery": {"body": "ffffff", "belly": "ffffff", "stripe": "d3302f", "stripe2": "1c3f74", "tail": "ffffff", "tail2": "d3302f", "logo": "d3302f",
			"logo_shape": 5, "art": "1c3f74", "engine": "ffffff", "tip": "d3302f", "text": "d3302f",
			"belly_h": -0.4, "rise_t": 0.45, "rise_h": 0.6, "stripes": [0.12, 0.06, 0.25, 0.025], "title": "HORIZON"},
		"pay": 0.25, "reputation": 60, "ceo": "Ruth Abernathy", "spokes": "Tomas Reyes",
		"desc": "Where it all begins. Build hours, earn your licences and get noticed by the airlines.",
		"standards": 0.6,
	},
	"WMA": {
		"name": "Westmark Airways", "callsign": "WESTMARK", "iata": "WM", "kind": "mainline",
		"hubs": ["WMIA"], "country": "Westmark", "reg_prefix": "WM-",
		"fleet": {"w350": 4, "s320": 10, "tp72": 4},
		"livery": {"body": "ffffff", "belly": "dfe6e3", "stripe": "1f6d4a", "stripe2": "c9a227", "tail": "1f6d4a", "tail2": "c9a227", "logo": "ffffff",
			"logo_shape": 6, "art": "1f6d4a", "engine": "1f6d4a", "tip": "1f6d4a", "text": "1f6d4a", "wing": "c3c8c6",
			"belly_h": -0.72, "stripes": [0.06, 0.03, 0.115, 0.008], "title": "WESTMARK"},
		"pay": 0.95, "reputation": 68, "ceo": "Edmund Carrow", "spokes": "Sigrid Holm",
		"desc": "Westmark's proud national airline, flying the Western Sea crossing since the propeller age.",
		"standards": 0.8,
	},
	"AUR": {
		"name": "Aurelia International", "callsign": "AURELIA", "iata": "AU", "kind": "mainline",
		"hubs": ["WMSK", "WMIA"], "country": "Westmark", "reg_prefix": "WM-A",
		"fleet": {"w380": 4, "w350": 6, "s321": 4, "w390": 2, "w280": 2},
		"livery": {"body": "f7f3ea", "belly": "6b1d2f", "stripe": "c9a24b", "stripe2": "6b1d2f", "tail": "6b1d2f", "tail2": "c9a24b", "logo": "c9a24b", "logo_shape": 4,
			"art": "c9a24b", "engine": "6b1d2f", "engine2": "c9a24b", "engine_style": 1, "tip": "c9a24b", "text": "6b1d2f",
			"belly_h": -0.55, "nose_dip": -0.05, "rise_t": 0.62, "rise_h": 1.0, "stripes": [0.04, 0.015, 0.09, 0.006], "stripe_t": [0.1, 0.96],
			"title": "AURELIA", "title_style": "light", "title_size": 1.2},
		"pay": 1.15, "reputation": 80, "ceo": "Octavia Laurent", "spokes": "Julien Moreau",
		"desc": "Long-haul luxury from Westmark: double-deck Skyliners, champagne in first, and the most demanding captains in the business.",
		"standards": 0.92,
	},
	"PEL": {
		"name": "Pelican Island Air", "callsign": "PELICAN", "iata": "PI", "kind": "regional",
		"hubs": ["SKIM", "SKSB"], "country": "Calderra", "reg_prefix": "CR-P",
		"fleet": {"tp50": 8, "tp72": 4, "tp90": 2},
		"livery": {"body": "ffffff", "belly": "35b6e8", "stripe": "ff7a3d", "stripe2": "ffd23f", "tail": "35b6e8", "tail2": "ff7a3d", "logo": "ffd23f", "logo_shape": 1,
			"art": "ff7a3d", "engine": "35b6e8", "engine2": "ffffff", "engine_style": 2, "tip": "ff7a3d", "text": "1d6f9a",
			"belly_h": -0.35, "nose_dip": 0.3, "rise_t": 0.45, "rise_h": 1.5, "stripes": [0.0, 0.0, 0.0, 0.0], "flow_t": 0.7, "flow_h": 1.1,
			"title": "pelican", "title_style": "italic", "title_size": 1.6},
		"pay": 0.7, "reputation": 58, "ceo": "Kofi Mensah", "spokes": "Lena Ostrova",
		"desc": "Bright little turboprops hopping between beaches and islands. Short runways, crosswinds and lots of landings.",
		"standards": 0.62,
	},
	"VTX": {
		"name": "Vortex Air", "callsign": "VORTEX", "iata": "VX", "kind": "lowcost",
		"hubs": ["SKOF", "SKHP"], "country": "Calderra", "reg_prefix": "CR-V",
		"fleet": {"s321": 8, "s320": 6, "rj70": 4},
		"livery": {"body": "16161a", "belly": "16161a", "stripe": "e6ff2e", "stripe2": "ff2e88", "tail": "e6ff2e", "tail2": "16161a", "logo": "16161a", "logo_shape": 2,
			"art": "ff2e88", "engine": "e6ff2e", "engine2": "ff2e88", "engine_style": 1, "tip": "ff2e88", "text": "e6ff2e", "reg_col": "e6ff2e", "wing": "9aa0a6",
			"belly_h": -0.95, "nose_dip": 0.0, "rise_t": 0.5, "rise_h": 0.0, "stripes": [0.12, 0.03, 0.0, 0.0], "flow_t": 0.78, "flow_h": 0.9,
			"title": "VORTEX", "title_style": "wide", "title_size": 1.8, "title_pos": 0.06},
		"pay": 0.78, "reputation": 47, "ceo": "Dex Calloway", "spokes": "Nina Park",
		"desc": "Black and neon, cheap and fast. The newest airline in Calderra, growing quickly and always short of pilots.",
		"standards": 0.55,
	},
	"LBA": {
		"name": "Liberty Atlantic", "callsign": "LIBERTY", "iata": "LT", "kind": "mainline",
		"hubs": ["KJFK", "KBOS"], "country": "United States", "reg_prefix": "N",
		"fleet": {"w380": 2, "w350": 8, "s321": 10, "s320": 12, "rj70": 6, "w390": 2, "s319": 4},
		"livery": {"body": "f6f7f9", "belly": "15264a", "stripe": "c8102e", "stripe2": "15264a", "tail": "15264a", "tail2": "c8102e", "logo": "ffffff", "logo_shape": 6,
			"art": "c8102e", "engine": "15264a", "engine2": "c8102e", "engine_style": 1, "tip": "c8102e", "text": "15264a",
			"belly_h": -0.5, "nose_dip": -0.1, "rise_t": 0.62, "rise_h": 0.8, "stripes": [0.05, 0.02, 0.1, 0.008], "title": "LIBERTY ATLANTIC", "title_style": "wide", "title_size": 0.95},
		"pay": 1.12, "reputation": 76, "ceo": "Grace Holloway", "spokes": "Marcus Bell",
		"desc": "New York's own flag carrier across the Atlantic: big jets, busy hubs and the toughest slots in the world.",
		"standards": 0.86,
	},
	"THA": {
		"name": "Thames Air", "callsign": "THAMES", "iata": "TQ", "kind": "mainline",
		"hubs": ["EGLL"], "country": "United Kingdom", "reg_prefix": "G-T",
		"fleet": {"w380": 3, "w350": 6, "s321": 8, "s320": 10, "w390": 2, "s319": 3},
		"livery": {"body": "ffffff", "belly": "3b1f5c", "stripe": "c9a227", "stripe2": "3b1f5c", "tail": "3b1f5c", "tail2": "c9a227", "logo": "c9a227", "logo_shape": 4,
			"art": "c9a227", "engine": "3b1f5c", "engine2": "c9a227", "engine_style": 1, "tip": "c9a227", "text": "3b1f5c",
			"belly_h": -0.6, "rise_t": 0.55, "rise_h": 1.1, "stripes": [0.04, 0.012, 0.08, 0.006], "title": "THAMES AIR", "title_style": "light", "title_size": 1.1},
		"pay": 1.08, "reputation": 74, "ceo": "Sir Alistair Penrose", "spokes": "Imogen Clarke",
		"desc": "London's premium airline, flying from Heathrow to six continents with a famously stiff upper lip.",
		"standards": 0.88,
	},
	"LUE": {
		"name": "Air Lumiere", "callsign": "LUMIERE", "iata": "LQ", "kind": "mainline",
		"hubs": ["LFPG"], "country": "France", "reg_prefix": "F-L",
		"fleet": {"w350": 6, "s320": 12, "s321": 6, "rj90": 6, "w280": 2, "s319": 4},
		"livery": {"body": "ffffff", "belly": "ffffff", "stripe": "1aa39a", "stripe2": "ff6f61", "tail": "1aa39a", "tail2": "ff6f61", "logo": "ffffff", "logo_shape": 1,
			"art": "ff6f61", "engine": "ffffff", "engine2": "1aa39a", "engine_style": 3, "tip": "ff6f61", "text": "1aa39a",
			"belly_h": -0.8, "stripes": [0.0, 0.0, 0.0, 0.0], "flow_t": 0.7, "flow_h": 1.0, "title": "air lumiere", "title_style": "italic", "title_size": 1.4},
		"pay": 1.0, "reputation": 71, "ceo": "Camille Durand", "spokes": "Hugo Marchand",
		"desc": "Parisian style from Charles de Gaulle: elegant cabins, excellent food and a very long taxi to runway 27L.",
		"standards": 0.82,
	},
	"GGP": {
		"name": "Golden Gate Pacific", "callsign": "GOLDEN GATE", "iata": "GG", "kind": "mainline",
		"hubs": ["KSFO", "KLAX"], "country": "United States", "reg_prefix": "N",
		"fleet": {"w350": 4, "s321": 8, "s320": 8, "rj70": 6, "w280": 2},
		"livery": {"body": "fdf6ec", "belly": "b22a1e", "stripe": "f39c2b", "stripe2": "ffd166", "stripe3": "b22a1e", "tail": "b22a1e", "tail2": "f39c2b", "logo": "ffd166", "logo_shape": 0,
			"art": "f39c2b", "engine": "b22a1e", "engine2": "f39c2b", "engine_style": 2, "tip": "f39c2b", "text": "b22a1e",
			"belly_h": -0.4, "nose_dip": 0.2, "rise_t": 0.5, "rise_h": 1.4, "stripes": [0.06, 0.02, 0.0, 0.0], "flow_t": 0.74, "flow_h": 0.9, "title": "GOLDEN GATE", "title_style": "wide"},
		"pay": 1.0, "reputation": 68, "ceo": "Danny Reyes", "spokes": "Kim Nakamura",
		"desc": "West Coast sunshine from San Francisco and Los Angeles: coast-to-coast flying and Pacific fog.",
		"standards": 0.78,
	},
	"MPN": {
		"name": "Maple Northern", "callsign": "MAPLE", "iata": "MN", "kind": "regional",
		"hubs": ["CYYZ"], "country": "Canada", "reg_prefix": "C-M",
		"fleet": {"s320": 6, "rj90": 8, "tp72": 6, "tp90": 4, "rj100": 3},
		"livery": {"body": "ffffff", "belly": "e8eaec", "stripe": "d52b1e", "tail": "d52b1e", "tail2": "ffffff", "logo": "ffffff", "logo_shape": 5,
			"art": "d52b1e", "engine": "d52b1e", "engine_style": 1, "tip": "d52b1e", "text": "d52b1e",
			"belly_h": -0.75, "stripes": [0.08, 0.025, 0.0, 0.0], "title": "MAPLE NORTHERN", "title_style": "bold"},
		"pay": 0.85, "reputation": 66, "ceo": "Evelyn Tremblay", "spokes": "Liam O'Connor",
		"desc": "Toronto's regional network: lake-effect snow, short hops and the long haul to Gander.",
		"standards": 0.74,
	},
	"AUN": {
		"name": "Aurora Nordic", "callsign": "AURORA", "iata": "AN", "kind": "regional",
		"hubs": ["BIKF", "EKVG"], "country": "Iceland", "reg_prefix": "TF-",
		"fleet": {"s320": 4, "rj90": 4, "tp72": 4, "tp50": 4, "tp90": 3},
		"livery": {"body": "0d1b3d", "belly": "081129", "stripe": "39e5a1", "stripe2": "7a5cff", "stripe3": "39e5a1", "tail": "0d1b3d", "tail2": "39e5a1", "logo": "39e5a1", "logo_shape": 2,
			"art": "39e5a1", "engine": "7a5cff", "engine2": "39e5a1", "engine_style": 1, "tip": "39e5a1", "text": "ffffff", "reg_col": "ffffff",
			"belly_h": -0.9, "rise_h": 0.0, "event_art": 1.0, "title": "AURORA NORDIC", "title_style": "light", "title_size": 1.1},
		"pay": 0.9, "reputation": 69, "ceo": "Sigrun Magnusdottir", "spokes": "Einar Olsen",
		"desc": "Flying the North Atlantic stepping stones: Iceland, the Faroes and Greenland, in every kind of weather.",
		"standards": 0.8,
	},
	"IHA": {
		"name": "Island Hopper Atlantic", "callsign": "HOPPER", "iata": "IH", "kind": "regional",
		"hubs": ["TXKF", "LPPD"], "country": "Portugal", "reg_prefix": "CS-",
		"fleet": {"tp72": 6, "tp50": 6, "rj70": 2},
		"livery": {"body": "ffffff", "belly": "17b2c4", "stripe": "ffcd3c", "tail": "17b2c4", "tail2": "ffcd3c", "logo": "ffffff", "logo_shape": 1,
			"art": "ffcd3c", "engine": "17b2c4", "engine_style": 2, "tip": "ffcd3c", "text": "17b2c4",
			"belly_h": -0.3, "nose_dip": 0.3, "rise_t": 0.42, "rise_h": 1.6, "flow_t": 0.68, "flow_h": 1.0, "title": "island hopper", "title_style": "italic", "title_size": 1.5},
		"pay": 0.72, "reputation": 60, "ceo": "Rui Carvalho", "spokes": "Ines Moreira",
		"desc": "Turboprops between Bermuda, the Azores and Madeira: short runways, big swells and nowhere to divert.",
		"standards": 0.66,
	},
	"SOL": {
		"name": "Sol Iberica", "callsign": "SOLAR", "iata": "SI", "kind": "lowcost",
		"hubs": ["LEMD"], "country": "Spain", "reg_prefix": "EC-",
		"fleet": {"s320": 10, "s321": 6, "s319": 3},
		"livery": {"body": "ffd23f", "belly": "ff7b00", "stripe": "c1121f", "tail": "ff7b00", "tail2": "c1121f", "logo": "ffd23f", "logo_shape": 2,
			"art": "c1121f", "engine": "c1121f", "engine2": "ffd23f", "engine_style": 1, "tip": "c1121f", "text": "c1121f", "reg_col": "c1121f",
			"belly_h": -0.55, "rise_t": 0.5, "rise_h": 1.2, "stripes": [0.0, 0.0, 0.0, 0.0], "flow_t": 0.8, "flow_h": 0.8, "title": "SOL", "title_style": "wide", "title_size": 2.2, "title_pos": 0.07},
		"pay": 0.78, "reputation": 55, "ceo": "Javier Ortega", "spokes": "Lucia Navarro",
		"desc": "Bright, cheap and always on time (mostly): Madrid to the sun spots of Europe.",
		"standards": 0.6,
	},
	"LSA": {
		"name": "Lone Star Airways", "callsign": "LONE STAR", "iata": "LS", "kind": "mainline",
		"hubs": ["KDFW", "KATL"], "country": "United States", "reg_prefix": "N",
		"fleet": {"s320": 8, "s321": 6, "w280": 3, "rj100": 6, "tp90": 5},
		"livery": {"body": "f6f4ef", "belly": "8c1d18", "stripe": "1f3b73", "stripe2": "c8a24a", "tail": "8c1d18", "tail2": "f6f4ef", "logo": "f6f4ef", "logo_shape": 7,
			"art": "c8a24a", "engine": "1f3b73", "engine2": "c8a24a", "engine_style": 1, "tip": "8c1d18", "text": "1f3b73",
			"belly_h": -0.7, "stripes": [0.06, 0.02, 0.11, 0.008], "title": "LONE STAR", "title_style": "wide", "title_size": 1.1},
		"pay": 1.0, "reputation": 66, "ceo": "Ray Holloway", "spokes": "Carmen Diaz",
		"desc": "Big Texas hospitality from Dallas and Atlanta to every corner of the United States. Thunderstorms included.",
		"standards": 0.8,
	},
	"RHA": {
		"name": "Rheinland Air", "callsign": "RHEINLAND", "iata": "RH", "kind": "mainline",
		"hubs": ["EDDF", "EDDM"], "country": "Germany", "reg_prefix": "D-",
		"fleet": {"s319": 4, "s320": 8, "s321": 4, "w350": 3, "w390": 2},
		"livery": {"body": "ffffff", "belly": "0f2a4a", "stripe": "f2b705", "tail": "0f2a4a", "tail2": "f2b705", "logo": "f2b705", "logo_shape": 4,
			"art": "f2b705", "engine": "0f2a4a", "engine2": "ffffff", "engine_style": 3, "tip": "f2b705", "text": "0f2a4a",
			"belly_h": -0.8, "stripes": [0.0, 0.0, 0.0, 0.0], "title": "RHEINLAND", "title_style": "bold", "title_size": 1.15},
		"pay": 1.08, "reputation": 80, "ceo": "Katrin Vogel", "spokes": "Jonas Becker",
		"desc": "Punctual to the minute: Frankfurt and Munich to the world, with the strictest training department in Europe.",
		"standards": 0.93,
	},
	"NRD": {
		"name": "Nordlys", "callsign": "NORDLYS", "iata": "NL", "kind": "regional",
		"hubs": ["ENGM", "ESSA", "EKCH"], "country": "Norway", "reg_prefix": "LN-",
		"fleet": {"tp90": 6, "rj100": 4, "s319": 3},
		"livery": {"body": "f4f7fa", "belly": "f4f7fa", "stripe": "33c3a0", "stripe2": "6a5acd", "tail": "1b2f4b", "tail2": "33c3a0", "logo": "33c3a0", "logo_shape": 3,
			"art": "6a5acd", "engine": "1b2f4b", "engine2": "33c3a0", "engine_style": 2, "tip": "33c3a0", "text": "1b2f4b",
			"belly_h": -0.6, "stripes": [0.0, 0.0, 0.0, 0.0], "flow_t": 0.82, "flow_h": 0.7, "title": "nordlys", "title_style": "light", "title_size": 1.3},
		"pay": 0.9, "reputation": 70, "ceo": "Ingrid Solberg", "spokes": "Erik Lund",
		"desc": "Northern lights on the tail: short hops between Oslo, Stockholm and Copenhagen, in snow, wind and endless winter night.",
		"standards": 0.86,
	},
	"ALP": {
		"name": "Alpenflug", "callsign": "ALPINE", "iata": "AP", "kind": "regional",
		"hubs": ["LSZH", "LOWW"], "country": "Switzerland", "reg_prefix": "HB-",
		"fleet": {"rj90": 4, "rj100": 4, "s319": 2, "bj8": 1},
		"livery": {"body": "ffffff", "belly": "ffffff", "stripe": "d1201f", "tail": "d1201f", "tail2": "ffffff", "logo": "ffffff", "logo_shape": 5,
			"art": "d1201f", "engine": "d1201f", "engine2": "ffffff", "engine_style": 0, "tip": "d1201f", "text": "d1201f",
			"belly_h": -0.9, "stripes": [0.0, 0.0, 0.0, 0.0], "title": "ALPENFLUG", "title_style": "bold", "title_size": 1.0},
		"pay": 1.05, "reputation": 77, "ceo": "Matthias Keller", "spokes": "Sophie Brunner",
		"desc": "Mountain flying specialists: Zurich and Vienna, steep approaches, foehn winds and spotless cabins.",
		"standards": 0.9,
	},
	"TFX": {
		"name": "Transatlantic Freight", "callsign": "FREIGHTER", "iata": "TX", "kind": "cargo",
		"hubs": ["KORD", "EHAM"], "country": "United States", "reg_prefix": "N",
		"fleet": {"f4": 5},
		"livery": {"body": "eeeeee", "belly": "4a4e54", "stripe": "2b6cb0", "tail": "2b6cb0", "tail2": "ffffff", "logo": "ffffff", "logo_shape": 3,
			"art": "ffffff", "engine": "4a4e54", "engine_style": 3, "tip": "2b6cb0", "text": "2b6cb0", "wing": "c4c8cc",
			"belly_h": -0.7, "stripes": [0.07, 0.03, 0.0, 0.0], "title": "TRANSATLANTIC FREIGHT", "title_style": "wide", "title_size": 0.8},
		"pay": 1.05, "reputation": 64, "ceo": "Walter Brandt", "spokes": "Nadia Kowalski",
		"desc": "Night freight between Chicago and Amsterdam on four-engine jumbos. Coffee, crosswinds and very long nights.",
		"standards": 0.76,
	},
}

const COLOR_KEYS := ["body", "belly", "stripe", "stripe2", "stripe3", "tail", "tail2", "logo", "engine", "engine2", "wing", "tip", "gear", "art", "text", "reg_col"]

## Paint layout defaults (heights are normalised: -1 keel .. 1 crown, relative to the window line).
const DEFAULT_LIVERY := {"wing": "c4c8cd", "gear": "d6d9dc", "belly_h": -0.6, "nose_dip": 0.0, "rise_t": 0.72, "rise_h": 0.2,
	"stripes": [0.0, 0.0, 0.0, 0.0], "stripe3_at": [0.0, 0.0], "stripe_t": [0.06, 0.985], "flow_t": 2.0, "flow_h": 0.0, "tail_band": 0.0,
	"mask": -1.0, "metal_belly": 0.0, "nose_paint": 0.0, "event_art": 0.0, "engine_style": 0, "title": "", "title_style": "bold",
	"title_size": 1.0, "title_pos": 0.0, "reg_col": "2a2c30"}

## Special schemes, worn by some airframes of the airline (see SPECIAL_FOR).
const SPECIALS := {
	"NWC.tanker": {"body": "ffffff", "belly": "d42a1e", "stripe": "e3b341", "tail": "d42a1e", "tail2": "ffffff", "logo": "ffffff", "logo_shape": 7,
		"art": "ffffff", "engine": "d42a1e", "engine2": "ffffff", "engine_style": 2, "tip": "d42a1e", "text": "d42a1e", "wing": "c4c8cc",
		"belly_h": -0.12, "nose_dip": 0.2, "rise_t": 0.55, "rise_h": 1.4, "stripes": [0.03, 0.01, 0.0, 0.0], "flow_t": 2.0, "flow_h": 0.0,
		"title": "NORTHWIND SUPERTANKER", "title_style": "italic", "title_size": 0.8},
	"SKF.retro": {"body": "ffffff", "belly": "c3c8ce", "metal_belly": 1.0, "stripe": "f28c28", "stripe2": "c0392b", "stripe3": "7a4a24",
		"tail": "ffffff", "tail2": "c0392b", "logo": "f28c28", "logo_shape": 8, "art": "c0392b", "engine": "c3c8ce", "engine_style": 0,
		"tip": "f28c28", "text": "7a4a24", "belly_h": -0.5, "nose_dip": 0.0, "rise_h": 0.0, "stripes": [0.4, 0.045, 0.5, 0.045],
		"stripe3_at": [0.6, 0.045], "stripe_t": [0.03, 0.9], "title": "SKYFALL", "title_style": "retro", "title_size": 1.15},
	"LMN.aurora": {"body": "1b1035", "belly": "120a26", "stripe": "2bd4a8", "stripe2": "7b3fe4", "stripe3": "ffd21f", "tail": "1b1035",
		"tail2": "2bd4a8", "logo": "ffd21f", "logo_shape": 2, "art": "2bd4a8", "engine": "7b3fe4", "engine2": "2bd4a8", "engine_style": 1,
		"tip": "2bd4a8", "text": "ffffff", "reg_col": "ffffff", "belly_h": -0.9, "nose_dip": 0.0, "rise_h": 0.0, "stripes": [0.0, 0.0, 0.0, 0.0],
		"flow_t": 2.0, "event_art": 1.0, "title": "LUMEN", "title_style": "italic", "title_size": 2.0, "title_pos": 0.08},
	"WMA.100": {"body": "ffffff", "belly": "1f6d4a", "stripe": "c9a227", "stripe2": "c9a227", "tail": "1f6d4a", "tail2": "c9a227",
		"logo": "c9a227", "logo_shape": 9, "art": "ffffff", "engine": "c9a227", "engine_style": 3, "tip": "c9a227", "text": "1f6d4a",
		"belly_h": -0.62, "rise_t": 0.55, "rise_h": 1.1, "stripes": [0.05, 0.02, 0.1, 0.01], "title": "WESTMARK 100 YEARS"},
	"SKF.flagship": {"body": "0f2547", "belly": "0a1a33", "stripe": "f28c28", "stripe2": "ffffff", "tail": "f28c28", "tail2": "0f2547", "logo": "ffffff",
		"logo_shape": 0, "art": "f28c28", "engine": "f28c28", "engine2": "0f2547", "engine_style": 2, "tip": "f28c28", "text": "ffffff", "reg_col": "ffffff",
		"belly_h": -0.9, "nose_dip": 0.0, "rise_h": 0.0, "stripes": [0.3, 0.02, 0.36, 0.006], "stripe_t": [0.05, 0.98], "title": "SKYFALL FLAGSHIP", "title_style": "wide", "title_size": 1.0},
	"CLK.reef": {"body": "ffffff", "belly": "0f8f94", "stripe": "ff8a5c", "stripe2": "ffd166", "stripe3": "13a6a6", "tail": "13a6a6", "tail2": "ff8a5c",
		"logo": "ffd166", "logo_shape": 1, "art": "ff8a5c", "engine": "0f8f94", "engine_style": 2, "tip": "ff8a5c", "text": "0f8f94",
		"belly_h": -0.3, "nose_dip": 0.3, "rise_t": 0.4, "rise_h": 1.6, "event_art": 1.0, "title": "SAVE OUR REEFS", "title_style": "italic"},
	"AUR.gold": {"body": "c9a24b", "belly": "6b1d2f", "stripe": "ffffff", "stripe2": "6b1d2f", "tail": "6b1d2f", "tail2": "ffffff", "logo": "ffffff",
		"logo_shape": 4, "art": "ffffff", "engine": "6b1d2f", "engine_style": 1, "tip": "ffffff", "text": "6b1d2f",
		"belly_h": -0.7, "stripes": [0.05, 0.01, 0.0, 0.0], "title": "AURELIA 25 GOLDEN YEARS", "title_style": "light"},
	"VTX.inverse": {"body": "e6ff2e", "belly": "16161a", "stripe": "ff2e88", "stripe2": "16161a", "tail": "16161a", "tail2": "e6ff2e", "logo": "e6ff2e",
		"logo_shape": 2, "art": "ff2e88", "engine": "16161a", "engine2": "ff2e88", "engine_style": 1, "tip": "ff2e88", "text": "16161a", "reg_col": "16161a",
		"belly_h": -0.55, "stripes": [0.1, 0.03, 0.0, 0.0], "title": "VORTEX", "title_style": "wide", "title_size": 1.8, "title_pos": 0.06},
}

## [special key, types it appears on, 1 in N airframes]
const SPECIAL_FOR := {
	"NWC": [["NWC.tanker", ["f4"], 3]],
	"SKF": [["SKF.retro", ["s320", "w350"], 8], ["SKF.flagship", ["w380"], 2]],
	"CLK": [["CLK.reef", ["tp72", "tp50"], 5]],
	"AUR": [["AUR.gold", ["w380", "w350"], 4]],
	"VTX": [["VTX.inverse", ["s321", "s320"], 5]],
	"LMN": [["LMN.aurora", ["s320"], 6]],
	"WMA": [["WMA.100", ["w350", "s320"], 6]],
}


static func get_al(code: String) -> Dictionary:
	return DATA.get(code, DATA["SKF"])


static func all_codes() -> Array:
	return ORDER.duplicate()


static func livery_colors(code: String) -> Dictionary:
	var l: Dictionary = DEFAULT_LIVERY.duplicate(true)
	l.merge(get_al(base_code(code)).livery, true)
	if SPECIALS.has(code):
		l.merge(SPECIALS[code], true)
	for pair in [["stripe2", "stripe"], ["stripe3", "stripe"], ["tail2", "tail"], ["tip", "tail"], ["art", "logo"], ["engine2", "body"]]:
		if not l.has(pair[0]):
			l[pair[0]] = l[pair[1]]
	var out := {}
	for k in l.keys():
		if k in COLOR_KEYS:
			out[k] = Color.html(String(l[k]))
		else:
			out[k] = l[k]
	return out


static func safety_stars(code: String) -> int:
	## 1..5 stars from the airline's operating standards (training, maintenance, pressure).
	return clampi(int(round((float(get_al(code).get("standards", 0.75)) - 0.45) / 0.1)), 1, 5)


static func safety_label(code: String) -> String:
	var n := safety_stars(code)
	return "%s %s" % ["★".repeat(n) + "☆".repeat(5 - n), ["", "Poor", "Below average", "Average", "Good", "Excellent"][n]]


static func crash_weight(code: String) -> float:
	## How likely this airline is to be the one in the next accident: weaker standards and
	## busier short-haul flying (more takeoffs and landings) both push it up.
	var al := get_al(code)
	var w := pow(1.12 - float(al.get("standards", 0.75)), 2.0) * 10.0
	match String(al.get("kind", "")):
		"regional", "lowcost":
			w *= 1.4
		"school":
			w *= 1.2
		"cargo":
			w *= 1.15
	if code == "IHA":
		w *= 1.3   # the hardest island airports in the world
	return w


static func pick_for_accident(r: RandomNumberGenerator) -> String:
	var total := 0.0
	for c in ORDER:
		total += crash_weight(c)
	var x := r.randf() * total
	for c2 in ORDER:
		x -= crash_weight(c2)
		if x <= 0.0:
			return c2
	return ORDER[0]


static func operates_type(code: String, type_id: String) -> bool:
	return get_al(code).fleet.has(type_id)


static func types_for(code: String) -> Array:
	return get_al(code).fleet.keys()


## Airline code of a livery key ("SKF.retro" -> "SKF").
static func base_code(lv: String) -> String:
	return lv.get_slice(".", 0)


## Livery worn by an airframe: the airline's own scheme, or (for a few registrations) one of its
## special schemes. A special key ("NWC.tanker") may also be asked for directly.
static func livery_for(code: String, reg: String, type_id: String) -> String:
	if SPECIALS.has(code):
		return code
	var base := base_code(code)
	if reg == "":
		return base
	for sp in SPECIAL_FOR.get(base, []):
		if type_id in sp[1] and U.hash_str(reg + String(sp[0])) % int(sp[2]) == 0:
			return sp[0]
	return base
