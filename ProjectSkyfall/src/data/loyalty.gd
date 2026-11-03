class_name Loyalty
extends RefCounted
## The Skyfall Miles frequent flyer programme for passenger trips.
## - Every trip earns miles for the real-world distance, doubled in business class.
## - Status tiers add a bonus on top of that.
## - Gold members and above get a chance of a free upgrade to business when they book economy,
##   and lounge access before the flight.
## Status is based on lifetime miles, so it never drops.

const TIERS := [
	{"name": "Blue", "need": 0, "bonus": 0.0, "upgrade": 0.0, "perk": "Welcome to Skyfall Miles."},
	{"name": "Silver", "need": 15000, "bonus": 0.25, "upgrade": 0.05, "perk": "Priority check-in and +25% miles."},
	{"name": "Gold", "need": 40000, "bonus": 0.5, "upgrade": 0.2, "perk": "Lounge access, priority boarding, +50% miles and upgrade chances."},
	{"name": "Platinum", "need": 90000, "bonus": 0.75, "upgrade": 0.4, "perk": "First in line for upgrades, +75% miles and fast track security."},
	{"name": "Diamond", "need": 200000, "bonus": 1.0, "upgrade": 0.7, "perk": "Double miles, almost-guaranteed upgrades and a chauffeur to the aircraft."},
]


static func _store() -> Dictionary:
	if not Game.settings.has("loyalty") or typeof(Game.settings.loyalty) != TYPE_DICTIONARY:
		Game.settings["loyalty"] = {"miles": 0, "lifetime": 0, "trips": 0, "upgrades": 0}
	return Game.settings.loyalty


static func miles() -> int:
	return int(_store().get("miles", 0))


static func lifetime() -> int:
	return int(_store().get("lifetime", 0))


static func tier_index() -> int:
	var lt := lifetime()
	var idx := 0
	for i in TIERS.size():
		if lt >= int(TIERS[i].need):
			idx = i
	return idx


static func tier() -> String:
	return String(TIERS[tier_index()].name)


static func tier_color() -> Color:
	match tier():
		"Silver":
			return Color(0.78, 0.8, 0.86)
		"Gold":
			return Color(1.0, 0.8, 0.3)
		"Platinum":
			return Color(0.75, 0.9, 1.0)
		"Diamond":
			return Color(0.6, 1.0, 0.95)
	return Color(0.45, 0.65, 1.0)


static func summary() -> String:
	## "Gold · 52,310 miles · 37,690 to Platinum"
	var i := tier_index()
	var s := "%s · %s miles" % [tier(), U.fmt_int(miles())]
	if i < TIERS.size() - 1:
		s += " · %s to %s" % [U.fmt_int(int(TIERS[i + 1].need) - lifetime()), String(TIERS[i + 1].name)]
	return s


static func trip_miles(dep: String, arr: String, cls: String) -> int:
	## Real-world miles for the route (the game world is drawn at about 1:5), with class and tier bonuses.
	var nm := Airports.distance_nm(dep, arr)
	var real_mi := nm * 1.1508 * (5.0 if Airports.get_ap(dep).get("region", "") == "world" else 1.0)
	var m := maxf(real_mi, 250.0)
	if cls in ["business", "first", "vip", "premium"]:
		m *= 2.0
	m *= 1.0 + float(TIERS[tier_index()].bonus)
	return int(round(m / 10.0) * 10.0)


static func upgrade_roll(rng_value: float) -> bool:
	## A free upgrade to business for an economy booking?
	return rng_value < float(TIERS[tier_index()].upgrade)


static func earn(dep: String, arr: String, cls: String) -> Dictionary:
	## Credits a completed trip. Returns {miles, tier, new_tier} for the debrief.
	var st := _store()
	var before := tier()
	var m := trip_miles(dep, arr, cls)
	st.miles = int(st.get("miles", 0)) + m
	st.lifetime = int(st.get("lifetime", 0)) + m
	st.trips = int(st.get("trips", 0)) + 1
	Game.save_settings()
	var after := tier()
	return {"miles": m, "tier": after, "new_tier": after != before}


static func note_upgrade() -> void:
	var st := _store()
	st.upgrades = int(st.get("upgrades", 0)) + 1
	Game.save_settings()
