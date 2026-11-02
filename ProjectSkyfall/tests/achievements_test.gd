extends Node
## Achievement unlocks from simulated flight results and events.

func _ready() -> void:
	Game.settings.achievements = {}
	WorldSim.clock = U.date_to_clock(2027, 6, 14, 23.0)
	Achievements.on_flight_result({"outcome": "landed", "type": "w380", "dep": "SKPC", "arr": "KJFK", "block_hours": 2.5, "clock": WorldSim.clock,
		"touchdown": {"vs_fpm": -82.0}, "weather": {"vis": 600.0, "wind_dir": 220.0, "wind_kt": 28.0}, "autofly_landed": true}, {})
	Achievements.on_flight_result({"outcome": "landed", "type": "s321", "dep": "KJFK", "arr": "EGLL", "block_hours": 1.3, "clock": WorldSim.clock - 6.0 * 3600.0,
		"touchdown": {"vs_fpm": -140.0}, "weather": {}}, {})
	Achievements.on_flight_result({"outcome": "crashed", "type": "bj6", "dep": "EGLL", "arr": "LFPG", "crash": {"cause_hint": "collided with the Eiffel Tower"}}, {"dead": false})
	for id in ["liberty", "eiffel", "ggb", "bigben"]:
		Achievements.on_landmark(id)
	Achievements.on_activity(93.0, "gold")
	var got := []
	for a in Achievements.LIST:
		if Achievements.unlocked(String(a.id)):
			got.append(String(a.id))
	print("unlocked %d: %s" % [got.size(), ", ".join(got)])
	print("stats: types %d airports %d countries %d landmarks %d hours %.1f" % [Achievements.stat("types"), Achievements.stat("airports"), Achievements.stat("countries"), Achievements.stat("landmarks"), Achievements.stat("hours")])
	print("ACHIEVEMENTS TEST DONE")
	get_tree().quit()
