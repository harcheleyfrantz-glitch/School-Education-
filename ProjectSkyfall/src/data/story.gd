class_name Story
extends RefCounted
## Story mode, "Wings of Calderra": five chapters from a first solo flight to captain of the very
## first arrival at Auera International. Each chapter is an in-engine cutscene (screens/cutscene.gd),
## a flight (an Activities scenario with category "story") and a closing scene. Progress lives in
## Game.settings.story = {"done": [chapter indices], "seen": [...]}.
##
## Cutscene shots: {at: ICAO, hour, weather, title: bool, ac: {type, airline, pose, ...}, cam: {mode,
## ...}, lines: [[speaker, text], ...]}. Poses: stand, runway (still), takeoff, approach, cruise.
## Camera modes: aerial (orbit the airport), orbit, low (beside the runway), flyby, chase, side.
## "{name}" in a line is the player's pilot.

const TITLE := "Wings of Calderra"

const CHAPTERS := [
	{
		"id": "story1", "num": "One", "title": "First Solo", "place": "Port Calder · dawn · Aerolite T-172",
		"synopsis": "Sixty hours in the logbook and nobody in the right seat. Your first solo flight, from Port Calder up the coast to Rivermouth.",
		"intro": [
			{"at": "SKPC", "hour": 6.6, "weather": "few", "title": true, "cam": {"mode": "aerial"},
				"lines": [["", "Port Calder, Calderra. Twenty to seven in the morning."], ["", "Sixty hours in the logbook - and today there is no instructor in the right seat."]]},
			{"at": "SKPC", "hour": 6.6, "weather": "few", "ac": {"type": "t172", "airline": "HFA", "pose": "stand", "stand": 2}, "cam": {"mode": "orbit", "dist": 13.0, "height": 3.0},
				"lines": [["Captain Mara Voss", "{name}! You look like you haven't slept. Good - neither did I before my first solo."], ["Captain Mara Voss", "Walkaround done? Fuel checked? Then she's all yours."]]},
			{"at": "SKPC", "hour": 6.6, "weather": "few", "ac": {"type": "t172", "airline": "HFA", "pose": "takeoff", "delay": 4.0}, "cam": {"mode": "low", "ahead": 380.0, "side": 45.0},
				"lines": [["Port Calder Tower", "Aerolite four-two-one, wind calm, cleared for take-off."], ["{name}", "Cleared for take-off, Aerolite four-two-one... here we go."]]},
			{"at": "SKPC", "hour": 6.6, "weather": "few", "ac": {"type": "t172", "airline": "HFA", "pose": "cruise", "alt": 450.0, "speed": 55.0}, "cam": {"mode": "side", "dist": 16.0, "height": 2.0},
				"lines": [["Captain Mara Voss", "(radio) Follow the coast north to Rivermouth and put her down gently. I'll be listening."], ["{name}", "Just me and the sky."]]},
		],
		"outro": [
			{"at": "SKRV", "hour": 7.6, "weather": "few", "ac": {"type": "t172", "airline": "HFA", "pose": "stand", "stand": 0}, "cam": {"mode": "orbit", "dist": 12.0, "height": 2.5},
				"lines": [["Captain Mara Voss", "Rivermouth Tower says that was the smoothest landing they've seen all week."], ["Captain Mara Voss", "Welcome to the sky, {name}. This is only the beginning."]]},
		],
		"mission": {"type": "t172", "airline": "HFA", "dep": "SKPC", "arr": "SKRV", "start": "air", "dist_km": 14.0, "alt_ft": 2500.0, "hour": 7.0, "weather": "few",
			"objective": "Land your first solo at Rivermouth."},
	},
	{
		"id": "story2", "num": "Two", "title": "The Night Run", "place": "Northgate to Port Calder · storm · Kestrel TP-72",
		"synopsis": "Two years on. The captain has gone home sick, a storm line is rolling in, and a hospital is waiting for the night mail.",
		"intro": [
			{"at": "SKNG", "hour": 22.6, "weather": "storm", "title": true, "cam": {"mode": "aerial"},
				"lines": [["", "Northgate. Eleven at night, and a storm line rolling in from the west."], ["", "Two years later: first officer at Calder Link, the island hopper."]]},
			{"at": "SKNG", "hour": 22.6, "weather": "storm", "ac": {"type": "tp72", "airline": "CLK", "pose": "stand", "stand": 1}, "cam": {"mode": "orbit", "dist": 30.0, "height": 6.0},
				"lines": [["Dispatcher", "{name}, Captain Okafor's gone home sick. You're the most senior pilot left in the building."], ["Dispatcher", "Thirty-eight passengers, the night mail and a medical delivery for Port Calder General. Can you take it?"], ["{name}", "Get me a weather briefing and a strong coffee."]]},
			{"at": "SKNG", "hour": 22.6, "weather": "storm", "ac": {"type": "tp72", "airline": "CLK", "pose": "cruise", "alt": 3600.0, "speed": 125.0}, "cam": {"mode": "chase", "dist": 42.0, "height": 8.0},
				"lines": [["{name}", "Calderra Control, Calder Link two-one-four, level one-two-zero, deviating left of the cells."], ["Calderra Control", "Two-one-four, deviation approved. Port Calder reports heavy rain and gusts to thirty-five knots."]]},
		],
		"outro": [
			{"at": "SKPC", "hour": 23.6, "weather": "rain", "ac": {"type": "tp72", "airline": "CLK", "pose": "stand", "stand": 1}, "cam": {"mode": "orbit", "dist": 28.0, "height": 5.0},
				"lines": [["Ground crew", "The hospital van's here. They say the medicine will be in theatre within the hour."], ["Captain Mara Voss", "(phone) I heard about tonight. Skyfall Airways is hiring long-haul pilots - I gave them your name."]]},
		],
		"mission": {"type": "tp72", "airline": "CLK", "dep": "SKNG", "arr": "SKPC", "start": "air", "dist_km": 24.0, "alt_ft": 4000.0, "hour": 23.1, "weather": "storm",
			"objective": "Bring the night run into Port Calder through the storm."},
	},
	{
		"id": "story3", "num": "Three", "title": "Across the Pond", "place": "New York to London · fog · Atlas W-350",
		"synopsis": "Your first transatlantic crossing in the right seat of a widebody - and a foggy morning at Heathrow at the end of it.",
		"intro": [
			{"at": "KJFK", "hour": 19.4, "weather": "few", "title": true, "cam": {"mode": "aerial"},
				"lines": [["", "New York, John F. Kennedy International."], ["", "Skyfall One to London: your first transatlantic crossing, first officer on the W-350."]]},
			{"at": "KJFK", "hour": 19.4, "weather": "few", "ac": {"type": "w350", "airline": "SKF", "pose": "stand", "stand": 3}, "cam": {"mode": "orbit", "dist": 75.0, "height": 12.0},
				"lines": [["Chief Pilot Ilsa Moreau", "Captain Hart has the radios tonight. Seven hours to London - and the landing is yours."], ["Captain Daniel Hart", "Heathrow's forecasting fog in the morning. I hope you like a proper instrument approach."]]},
			{"at": "KJFK", "hour": 19.4, "weather": "few", "ac": {"type": "w350", "airline": "SKF", "pose": "takeoff", "delay": 3.0}, "cam": {"mode": "low", "ahead": 900.0, "side": 120.0},
				"lines": [["Kennedy Tower", "Skyfall One, cleared for take-off. Good night."], ["{name}", "Cleared for take-off, Skyfall One. See you on the other side."]]},
			{"at": "EGLL", "hour": 6.8, "weather": "fog", "ac": {"type": "w350", "airline": "SKF", "pose": "approach", "dist": 6500.0}, "cam": {"mode": "chase", "dist": 85.0, "height": 14.0},
				"lines": [["", "Seven hours and three thousand miles later."], ["Heathrow Director", "Skyfall One, fog at the field, runway visual range three hundred metres. Cleared for the ILS approach."]]},
		],
		"outro": [
			{"at": "EGLL", "hour": 7.4, "weather": "fog", "ac": {"type": "w350", "airline": "SKF", "pose": "stand", "stand": 5}, "cam": {"mode": "orbit", "dist": 70.0, "height": 10.0},
				"lines": [["Captain Daniel Hart", "Three hundred metres of visibility and you greased it. I'm telling Moreau."], ["Chief Pilot Ilsa Moreau", "(message) Welcome to the long-haul fleet, {name}."]]},
		],
		"mission": {"type": "w350", "airline": "SKF", "dep": "KJFK", "arr": "EGLL", "start": "air", "dist_km": 22.0, "alt_ft": 4000.0, "hour": 6.8, "weather": "fog",
			"objective": "Land at London Heathrow in the fog."},
	},
	{
		"id": "story4", "num": "Four", "title": "Mayday", "place": "North Atlantic · night · engine failure",
		"synopsis": "Four hours out of London, south of Iceland, with three hundred and two people on board. Then an engine fails.",
		"intro": [
			{"at": "EGLL", "hour": 21.0, "weather": "few", "title": true, "cam": {"mode": "aerial"},
				"lines": [["", "London Heathrow, nine at night."], ["", "Skyfall One to New York. Three hundred and two people on board."]]},
			{"at": "BIKF", "hour": 1.2, "weather": "few", "ac": {"type": "w350", "airline": "SKF", "pose": "cruise", "alt": 10600.0, "speed": 240.0, "off": Vector2(0.0, 60000.0), "hdg": 280.0}, "cam": {"mode": "side", "dist": 90.0, "height": 6.0},
				"lines": [["", "Four hours later. Somewhere south of Iceland."], ["Captain Daniel Hart", "Quiet night. Coffee?"]]},
			{"at": "BIKF", "hour": 1.2, "weather": "few", "ac": {"type": "w350", "airline": "SKF", "pose": "cruise", "alt": 10600.0, "speed": 240.0, "off": Vector2(0.0, 60000.0), "hdg": 280.0}, "cam": {"mode": "chase", "dist": 70.0, "height": 9.0},
				"lines": [["", "BANG."], ["Captain Daniel Hart", "Engine failure, engine two! Thrust lever idle... fuel control switch to cutoff... it's shut down."], ["{name}", "Keflavik is the nearest suitable airport. One hundred and eighty miles."], ["Captain Daniel Hart", "Then Keflavik it is. Declare the emergency. Your aircraft, {name} - I'll run the checklists."], ["{name}", "Mayday, mayday, mayday. Skyfall One, engine failure, diverting to Keflavik."]]},
		],
		"outro": [
			{"at": "BIKF", "hour": 2.4, "weather": "snow", "ac": {"type": "w350", "airline": "SKF", "pose": "stand", "stand": 1}, "cam": {"mode": "orbit", "dist": 70.0, "height": 10.0},
				"lines": [["Keflavik Tower", "Skyfall One, welcome to Iceland. The fire crews say your remaining engine looks perfect."], ["Captain Daniel Hart", "Three hundred and two people are going home because of you tonight, {name}."], ["Chief Pilot Ilsa Moreau", "Get some sleep. When you're back, there's a captain's uniform with your name on it."]]},
		],
		"mission": {"type": "w350", "airline": "SKF", "dep": "EGLL", "arr": "BIKF", "start": "air", "dist_km": 55.0, "alt_ft": 11000.0, "hour": 1.6, "weather": "snow",
			"force_event": "engine_failure", "objective": "Bring the crippled widebody down safely at Keflavik."},
	},
	{
		"id": "story5", "num": "Five", "title": "Auera", "place": "Auera International · opening night · Q-740 Monarch",
		"synopsis": "The biggest airport in the world opens tonight, and Skyfall Airways' youngest captain flies the very first arrival.",
		"intro": [
			{"at": "SKAU", "hour": 19.0, "weather": "few", "title": true, "cam": {"mode": "aerial"},
				"lines": [["News anchor", "Good evening. Tonight Calderra opens the biggest airport in the world: Auera International."], ["News anchor", "Six runways, a hundred and sixty gates - and the first arrival is flown by Skyfall Airways' youngest captain."]]},
			{"at": "SKPC", "hour": 18.4, "weather": "few", "ac": {"type": "q740", "airline": "SKF", "pose": "stand", "stand": 4}, "cam": {"mode": "orbit", "dist": 85.0, "height": 14.0},
				"lines": [["Chief Pilot Ilsa Moreau", "Captain {name}. The Monarch is fuelled, the world's press is waiting, and the President is in seat one-A."], ["Captain Mara Voss", "From a little Aerolite to the Monarch. Go on - they're all watching."]]},
			{"at": "SKAU", "hour": 19.2, "weather": "few", "ac": {"type": "q740", "airline": "SKF", "pose": "approach", "dist": 6000.0}, "cam": {"mode": "flyby", "ahead": 2600.0, "side": 260.0, "up": 40.0},
				"lines": [["Auera Tower", "Skyfall One, welcome to Auera International. You are the very first. Cleared to land."], ["{name}", "Cleared to land, Skyfall One. Let's make history."]]},
		],
		"outro": [
			{"at": "SKAU", "hour": 19.8, "weather": "few", "ac": {"type": "q740", "airline": "SKF", "pose": "stand", "stand": 10}, "cam": {"mode": "orbit", "dist": 95.0, "height": 16.0},
				"lines": [["News anchor", "And there it is: the first aircraft ever to land at Auera International - right on time, to a standing ovation."], ["Captain Mara Voss", "I knew it the morning of your first solo, {name}. The sky was always yours."], ["", "WINGS OF CALDERRA - THE END. Thank you for playing."]]},
		],
		"mission": {"type": "q740", "airline": "SKF", "dep": "SKPC", "arr": "SKAU", "start": "air", "dist_km": 20.0, "alt_ft": 4000.0, "hour": 19.4, "weather": "few",
			"objective": "Fly the first ever arrival into Auera International."},
	},
]


static func _store() -> Dictionary:
	if not Game.settings.has("story") or typeof(Game.settings.story) != TYPE_DICTIONARY:
		Game.settings["story"] = {"done": [], "seen": []}
	return Game.settings.story


static func is_done(i: int) -> bool:
	return i in (_store().get("done", []) as Array)


static func unlocked(i: int) -> bool:
	return i == 0 or is_done(i - 1)


static func done_count() -> int:
	return (_store().get("done", []) as Array).size()


static func mark_done(i: int) -> void:
	var st := _store()
	var d: Array = st.get("done", [])
	if not i in d:
		d.append(i)
	st.done = d
	Game.save_settings()
	Achievements.unlock("story_ch%d" % (i + 1))
	if d.size() >= CHAPTERS.size():
		Achievements.unlock("story_done")


static func chapter_of(scenario_id: String) -> int:
	for i in CHAPTERS.size():
		if String(CHAPTERS[i].id) == scenario_id:
			return i
	return -1


static func player_name() -> String:
	if Game.has_character():
		var p: Dictionary = Game.player
		return String(p.get("first", p.get("name", "Captain")))
	return "Cadet"


static func fill(text: String) -> String:
	return text.replace("{name}", player_name())


static func scenarios() -> Array:
	## The chapter flights as Activities scenarios (category "story": not listed on the Activities
	## screen; scored and recorded like any other activity).
	var out := []
	for i in CHAPTERS.size():
		var c: Dictionary = CHAPTERS[i]
		var m: Dictionary = (c.mission as Dictionary).duplicate()
		m.id = String(c.id)
		m.category = "story"
		m.title = "Chapter %s: %s" % [c.num, c.title]
		m.place = String(c.place)
		m.desc = String(c.synopsis)
		m.difficulty = 1 + i
		m.tags = ["Story", "Chapter %s" % c.num]
		out.append(m)
	return out
