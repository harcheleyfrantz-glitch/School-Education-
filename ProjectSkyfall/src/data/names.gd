class_name Names
## Name and identity pools for the simulated population.

const FIRST_F := ["Amelia", "Sofia", "Hana", "Leila", "Grace", "Mei", "Aisha", "Clara", "Ingrid", "Priya",
	"Olivia", "Nadia", "Yuki", "Camila", "Freya", "Zara", "Elena", "Mira", "Ruth", "Lucia", "Chloe", "Ama",
	"Isabel", "Ana", "Sana", "Maya", "Noor", "Eva", "Rosa", "Imani", "Keira", "Linnea", "Tessa", "Fatima",
	"Harriet", "Joanna", "Bea", "Selin", "Daria", "Marisol", "Ines", "Wren", "Aiko", "Thandi", "Esme", "Kalani",
	"Margot", "Paloma", "Siobhan", "Yara"]
const FIRST_M := ["Oliver", "Mateo", "Kenji", "Omar", "Lucas", "Arjun", "Elias", "Theo", "Kwame", "Ivan",
	"Daniel", "Samuel", "Hugo", "Rafael", "Jonas", "Malik", "Felix", "Tomas", "Ravi", "Leon", "Noah", "Dmitri",
	"Kofi", "Andre", "Marco", "Yusuf", "Liam", "Henrik", "Diego", "Sami", "Benedict", "Caleb", "Emre", "Joao",
	"Alistair", "Viktor", "Ezra", "Tariq", "Bruno", "Hiro", "Oscar", "Matias", "Nikolai", "Idris", "Callum",
	"Anton", "Rowan", "Silas", "Teo", "Wiremu"]
const FIRST_X := ["Alex", "Robin", "Jordan", "Sam", "Rowan", "Quinn", "Ari", "Kai", "River", "Sasha", "Morgan", "Avery"]
const LAST := ["Marsh", "Okafor", "Lindqvist", "Tanaka", "Haddad", "Moreau", "Novak", "Fernandes", "Kowalski",
	"Nakamura", "Abara", "Castellano", "Brennan", "Sorensen", "Chen", "Mensah", "Petrov", "Alvarez", "Kaur",
	"Whitfield", "Dubois", "Oyelaran", "Varga", "Holloway", "Rahman", "Bergstrom", "Costa", "Ivanova", "Delgado",
	"Ashworth", "Mbeki", "Yilmaz", "Larsen", "Sato", "Fitzgerald", "Adeyemi", "Romano", "Kim", "Svensson",
	"Morales", "Hartley", "Nkosi", "Ferreira", "Park", "Quinlan", "Rossi", "Halvorsen", "Abiodun", "Calloway",
	"Strand", "Ortega", "Lennox", "Achterberg", "Bianchi", "Kader", "Thorne", "Vasquez", "Ito", "Winslow",
	"Osei", "Lambert", "Moreno", "Ekstrom", "Hughes", "Santos", "Aldana", "Keane", "Nowak", "Pereira", "Grant"]
const HOMETOWNS := ["Port Calder", "Rivermouth", "Northgate", "Highpass", "Oren Falls", "Willowbrook", "Marea",
	"Sable Bay", "Aldmoor", "Skerra", "Port Calder", "Port Calder", "Northgate", "Aldmoor"]
const OCCUPATIONS := ["teacher", "software engineer", "nurse", "student", "retired engineer", "sales manager",
	"architect", "chef", "musician", "accountant", "doctor", "journalist", "photographer", "construction worker",
	"lawyer", "fisherman", "police officer", "farmer", "pharmacist", "consultant", "graphic designer",
	"marine biologist", "shop owner", "electrician", "pilot (off duty)", "civil servant", "economist", "paramedic",
	"film producer", "university lecturer", "mechanic", "hotel manager", "veterinarian", "data analyst"]
const PURPOSES := ["business", "holiday", "visiting family", "conference", "study", "wedding", "funeral",
	"medical appointment", "commute", "honeymoon", "sports event", "job interview", "backpacking", "concert"]
const TRAITS := ["calm", "anxious", "chatty", "grumpy", "friendly", "impatient", "curious", "quiet", "demanding", "cheerful"]
const HANDLE_WORDS := ["sky", "plane", "spotter", "avgeek", "jet", "wing", "runway", "cloud", "travel", "nomad",
	"coffee", "harbor", "pixel", "north", "wander", "radar", "vapor", "atlas", "metro", "local"]


static func person(r: RandomNumberGenerator, age_min: int = 18, age_max: int = 82) -> Dictionary:
	var g := r.randf()
	var gender := "f" if g < 0.48 else ("m" if g < 0.96 else "x")
	var first: String
	match gender:
		"f": first = U.pick(r, FIRST_F)
		"m": first = U.pick(r, FIRST_M)
		_: first = U.pick(r, FIRST_X)
	var last: String = U.pick(r, LAST)
	return {
		"first": first, "last": last, "name": first + " " + last, "gender": gender,
		"age": r.randi_range(age_min, age_max), "home": U.pick(r, HOMETOWNS),
		"job": U.pick(r, OCCUPATIONS), "trait": U.pick(r, TRAITS),
	}


static func pronoun(gender: String, kind: String = "subj") -> String:
	match gender:
		"f":
			return {"subj": "she", "obj": "her", "pos": "her", "Subj": "She"}.get(kind, "she")
		"m":
			return {"subj": "he", "obj": "him", "pos": "his", "Subj": "He"}.get(kind, "he")
	return {"subj": "they", "obj": "them", "pos": "their", "Subj": "They"}.get(kind, "they")


static func handle(r: RandomNumberGenerator, p: Dictionary = {}) -> String:
	var base := ""
	if not p.is_empty() and r.randf() < 0.5:
		base = (String(p.first) + String(p.last).substr(0, 1)).to_lower()
	else:
		base = String(U.pick(r, HANDLE_WORDS)) + String(U.pick(r, HANDLE_WORDS)).capitalize()
	if r.randf() < 0.6:
		base += str(r.randi_range(1, 99))
	return "@" + base


static func flight_attendant(r: RandomNumberGenerator) -> Dictionary:
	var p := person(r, 22, 58)
	p["job"] = "flight attendant"
	return p


static func pilot(r: RandomNumberGenerator) -> Dictionary:
	var p := person(r, 26, 62)
	p["job"] = "airline pilot"
	return p
