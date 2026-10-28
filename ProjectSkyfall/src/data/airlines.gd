class_name Airlines
## Fictional operators. Livery colours feed the aircraft paint shader.

const ORDER := ["SKF", "CLK", "LMN", "NWC", "APX", "HFA", "WMA"]

const DATA := {
	"SKF": {
		"name": "Skyfall Air", "callsign": "SKYFALL", "iata": "SF", "kind": "mainline",
		"hubs": ["SKPC"], "country": "Calderra", "reg_prefix": "CR-S",
		"fleet": {"s320": 18, "w350": 6, "rj90": 8},
		"livery": {"body": "f4f6f9", "belly": "1c3f74", "stripe": "f28c28", "tail": "1c3f74", "logo": "f6a03c", "logo_shape": 0, "engine": "1c3f74", "text": "1c3f74"},
		"pay": 1.0, "reputation": 72, "ceo": "Helena Marsh", "spokes": "Daniel Okoro",
		"desc": "Calderra's flag carrier. Premium service, strict standards, and the fastest route to the left seat of a wide-body.",
		"standards": 0.85,
	},
	"CLK": {
		"name": "Coastal Link", "callsign": "COASTAL", "iata": "CL", "kind": "regional",
		"hubs": ["SKPC", "SKSB"], "country": "Calderra", "reg_prefix": "CR-C",
		"fleet": {"tp72": 10, "rj90": 6},
		"livery": {"body": "ffffff", "belly": "e8eef0", "stripe": "13a6a6", "tail": "0f8f94", "logo": "ffffff", "logo_shape": 1, "engine": "dfe5e8", "text": "0f8f94"},
		"pay": 0.75, "reputation": 64, "ceo": "Marco Bellweather", "spokes": "Priya Venkat",
		"desc": "The regional network that links every island and valley. Short sectors, many landings, great training.",
		"standards": 0.7,
	},
	"LMN": {
		"name": "Lumen Airways", "callsign": "LUMEN", "iata": "LU", "kind": "lowcost",
		"hubs": ["SKNG", "SKPC"], "country": "Calderra", "reg_prefix": "CR-L",
		"fleet": {"s320": 12},
		"livery": {"body": "ffffff", "belly": "ffd21f", "stripe": "ffd21f", "tail": "5b2a86", "logo": "ffd21f", "logo_shape": 2, "engine": "5b2a86", "text": "5b2a86"},
		"pay": 0.82, "reputation": 51, "ceo": "Viktor Lindqvist", "spokes": "Amara Diallo",
		"desc": "Bright yellow and always on the move. Quick turnarounds and tight schedules are the norm.",
		"standards": 0.6,
	},
	"NWC": {
		"name": "Northwind Cargo", "callsign": "NORTHWIND", "iata": "NW", "kind": "cargo",
		"hubs": ["SKNG"], "country": "Calderra", "reg_prefix": "CR-N",
		"fleet": {"f4": 5},
		"livery": {"body": "d9dde2", "belly": "8e959c", "stripe": "c0262d", "tail": "c0262d", "logo": "ffffff", "logo_shape": 3, "engine": "8e959c", "text": "c0262d"},
		"pay": 1.05, "reputation": 66, "ceo": "Gunnar Halvorsen", "spokes": "Lucia Ferreira",
		"desc": "Heavy freight through the night. No passengers, long hours, the biggest aircraft in the region.",
		"standards": 0.75,
	},
	"APX": {
		"name": "Apex Executive", "callsign": "APEX", "iata": "AX", "kind": "charter",
		"hubs": ["SKPC", "SKSB"], "country": "Calderra", "reg_prefix": "CR-X",
		"fleet": {"bj6": 6},
		"livery": {"body": "fbfaf7", "belly": "1d1d1f", "stripe": "c9a227", "tail": "1d1d1f", "logo": "c9a227", "logo_shape": 4, "engine": "1d1d1f", "text": "1d1d1f"},
		"pay": 1.1, "reputation": 70, "ceo": "Isabelle Fontaine", "spokes": "Rafael Moreno",
		"desc": "Private aviation for people whose schedules cannot wait. Discretion and perfection are expected.",
		"standards": 0.9,
	},
	"HFA": {
		"name": "Horizon Flight Academy", "callsign": "HORIZON", "iata": "HZ", "kind": "school",
		"hubs": ["SKWF"], "country": "Calderra", "reg_prefix": "CR-H",
		"fleet": {"t172": 12},
		"livery": {"body": "ffffff", "belly": "ffffff", "stripe": "d3302f", "tail": "ffffff", "logo": "d3302f", "logo_shape": 5, "engine": "ffffff", "text": "d3302f"},
		"pay": 0.25, "reputation": 60, "ceo": "Ruth Abernathy", "spokes": "Tomas Reyes",
		"desc": "Where it all begins. Build hours, earn your licences and get noticed by the airlines.",
		"standards": 0.6,
	},
	"WMA": {
		"name": "Westmark Airways", "callsign": "WESTMARK", "iata": "WM", "kind": "mainline",
		"hubs": ["WMIA"], "country": "Westmark", "reg_prefix": "WM-",
		"fleet": {"w350": 4, "s320": 10, "tp72": 4},
		"livery": {"body": "ffffff", "belly": "dfe6e3", "stripe": "1f6d4a", "tail": "1f6d4a", "logo": "ffffff", "logo_shape": 3, "engine": "1f6d4a", "text": "1f6d4a"},
		"pay": 0.95, "reputation": 68, "ceo": "Edmund Carrow", "spokes": "Sigrid Holm",
		"desc": "Westmark's proud national airline, flying the Western Sea crossing since the propeller age.",
		"standards": 0.8,
	},
}


static func get_al(code: String) -> Dictionary:
	return DATA.get(code, DATA["SKF"])


static func all_codes() -> Array:
	return ORDER.duplicate()


static func livery_colors(code: String) -> Dictionary:
	var l: Dictionary = get_al(code).livery
	var out := {}
	for k in l.keys():
		if k == "logo_shape":
			out[k] = l[k]
		else:
			out[k] = Color.html(l[k])
	return out


static func operates_type(code: String, type_id: String) -> bool:
	return get_al(code).fleet.has(type_id)


static func types_for(code: String) -> Array:
	return get_al(code).fleet.keys()


## Airline code of a livery key ("SKF.retro" -> "SKF").
static func base_code(lv: String) -> String:
	return lv.get_slice(".", 0)


## Livery worn by an airframe: the airline's own scheme, or a special scheme for some registrations.
static func livery_for(code: String, reg: String, type_id: String) -> String:
	return code
