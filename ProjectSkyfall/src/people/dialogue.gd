class_name Dialogue
extends RefCounted
## Conversation lines for passengers and crew, built from each person's persistent identity
## (name, home town, job, trait, reason for travelling, travel companions) and the moment
## (phase of flight, turbulence, delays, emergencies, how frightened they are).

const TOPICS := ["trip", "job", "home", "flight", "reassure"]


static func _r(p: Dictionary, salt: String) -> RandomNumberGenerator:
	return U.rng(U.hash_ints(int(p.get("id", 0)), U.hash_str(salt + str(int(WorldSim.clock / 600.0)))))


## A spontaneous line when the player walks past or looks at someone.
static func ambient(p: Dictionary, ctx: Dictionary) -> String:
	var r := _r(p, "amb")
	var fear := float(p.get("fear", 0.0))
	var phase := String(ctx.get("phase", "cruise"))
	var trait_ := String(p.get("trait", "calm"))
	if fear > 0.65:
		return U.pick(r, ["Is this normal? Please tell me this is normal.", "Oh God. Oh God.", "Why are we shaking like this?",
			"I want to get off this plane.", "Hold my hand. Please.", "Are we going to be okay?"])
	if fear > 0.35:
		return U.pick(r, ["That was a big bump...", "I hate turbulence.", "Should the wings move like that?",
			"Did the captain say anything?", "I'm fine. I'm fine. I'm fine."])
	match phase:
		"boarding", "preflight", "gate":
			match trait_:
				"impatient":
					return U.pick(r, ["Can people please just sit down?", "We're going to be late, I can feel it.", "Why does boarding always take forever?"])
				"chatty":
					return U.pick(r, ["Hi! Window or aisle person? I'm a window person.", "Is this your first time flying with them? The coffee is good."])
				"anxious":
					return U.pick(r, ["I always count the rows to the exit.", "Do you know how old this plane is?"])
			return U.pick(r, ["Excuse me, I think that's my seat.", "Is there room in the bin up there?", "Finally.", "Sorry, just squeezing past."])
		"taxi":
			return U.pick(r, ["Here we go.", "I love this part.", "Phones on flight mode, everyone.", "Long line for the runway today."])
		"takeoff", "climb":
			return U.pick(r, ["Look at the city!", "My ears are popping.", "Wheee.", "...", "Bye, %s." % String(ctx.get("dep_city", "home"))])
		"cruise":
			match trait_:
				"grumpy":
					return U.pick(r, ["The wifi doesn't work. Of course it doesn't.", "These seats get smaller every year."])
				"curious":
					return U.pick(r, ["How high do you think we are? Ten kilometres?", "Is that a river down there?"])
				"cheerful":
					return U.pick(r, ["What a view!", "I could get used to this."])
			return U.pick(r, ["Could I get some water?", "How long until we land?", "Finally some quiet.", "zzz..."])
		"landing":
			return U.pick(r, ["Almost there.", "Tray tables up, I know, I know.", "I can see the runway lights!"])
		"taxi_in", "arrived":
			return U.pick(r, ["Smooth landing!", "Is everyone clapping? Are we clapping?", "Welcome to %s." % String(ctx.get("arr_city", "town"))])
	return "Hello."


## What someone says about the trip once the aircraft is on blocks (shown in the passenger debrief).
static func review(p: Dictionary, ctx: Dictionary) -> String:
	var r := _r(p, "review")
	var trait_ := String(p.get("trait", "calm"))
	var vs := float(ctx.get("landing_fpm", 200.0))
	var late := float(ctx.get("late_min", 0.0))
	var bumps := int(ctx.get("bumps", 0))
	var ga := int(ctx.get("go_arounds", 0))
	var city := String(ctx.get("arr_city", "home"))
	if vs > 650.0:
		return U.pick(r, ["That landing loosened a few fillings.", "I think we bounced. Did we bounce?", "I've had smoother bus rides.",
			"My coffee is now on the ceiling."]) if trait_ != "anxious" else "I'm never flying again. Never."
	if ga > 0:
		return U.pick(r, ["When the engines roared on the way down my heart stopped - but the captain explained it well.",
			"A go-around! I've read about those. Honestly, glad they were careful.", "Second time lucky, I suppose."])
	if bumps > 1 and trait_ in ["anxious", "grumpy"]:
		return U.pick(r, ["Those bumps... I gripped the armrest the whole way.", "Couldn't they have flown around the weather?"])
	if late > 20.0:
		return U.pick(r, ["%d minutes late. I'm going to miss my connection." % int(late), "Late again. Every single time.",
			"At least they kept us informed."]) if trait_ != "cheerful" else "Late, but who cares - we're in %s!" % city
	if vs < 180.0:
		return U.pick(r, ["Didn't even feel the touchdown. Butter.", "Best landing I've had in years!", "Was that it? Are we down?",
			"Somebody give that pilot a raise."])
	match trait_:
		"grumpy":
			return U.pick(r, ["Fine. It was fine. Can we get off now?", "The seat in front reclined into my lap the whole way."])
		"chatty":
			return U.pick(r, ["Lovely crew, lovely flight. I made three new friends!", "The view over the coast was incredible - did you see it?"])
		"cheerful":
			return U.pick(r, ["What a great flight. Hello, %s!" % city, "Ten out of ten, would fly again."])
		"anxious":
			return U.pick(r, ["Made it. I'm proud of myself.", "That wasn't so bad. Don't tell anyone I said that."])
		"curious":
			return U.pick(r, ["I timed the takeoff roll: thirty-one seconds.", "I could hear the flaps going out on approach. Fascinating."])
	return U.pick(r, ["A good flight, thanks.", "Smooth enough. Glad to be here.", "Right on schedule.", "Nothing to complain about."])


## The player's choice of topic -> the person's answer.
static func answer(p: Dictionary, topic: String, ctx: Dictionary) -> String:
	var r := _r(p, "ans" + topic)
	var first := String(p.get("first", "I"))
	var job := String(p.get("job", "work"))
	var home := String(p.get("home", "around here"))
	var purpose := String(p.get("purpose", "holiday"))
	var arr_city := String(ctx.get("arr_city", "the city"))
	var trait_ := String(p.get("trait", "calm"))
	var fear := float(p.get("fear", 0.0))
	match topic:
		"trip":
			match purpose:
				"business":
					return U.pick(r, ["Meetings all day in %s. I'll be back on the evening flight." % arr_city, "Client visit. I practically live on this route.",
						"Conference. Three days of slides about %s." % ("logistics" if job == "logistics coordinator" else "the future")])
				"holiday":
					return U.pick(r, ["A whole week off! First real holiday in two years.", "Beaches, food, nothing else.", "My %s booked it as a surprise." % ("partner" if int(p.get("age", 30)) > 25 else "parents")])
				"visiting family":
					return U.pick(r, ["Going to see my %s. It's been too long." % ["mother", "father", "sister", "brother", "grandmother"][r.randi() % 5], "Family dinner on Sunday. Wouldn't miss it."])
				"wedding":
					return "My cousin's getting married in %s. I'm giving a speech, which terrifies me more than flying." % arr_city
				"funeral":
					return "A funeral. My old teacher. ...Sorry, I don't really want to talk about it."
				"study":
					return "Starting a course at the university in %s. New city, new everything." % arr_city
				"conference":
					return "A conference. I'm presenting, actually. Wish me luck."
			return "Just a trip. Nothing exciting."
		"job":
			if job == "retired":
				return U.pick(r, ["Retired! I spent forty years working, now I travel.", "I used to be an engineer. Now I'm a professional grandparent."])
			if job == "student" or job == "child":
				return "I'm still at school. I want to be a pilot when I grow up!" if int(p.get("age", 20)) < 14 else "I'm a student. Exams next month, so this trip is badly timed."
			return "I'm a %s. %s" % [job, U.pick(r, ["It pays the bills.", "I love it, honestly.", "Long hours, but good people.", "Don't ask me about work today."])]
		"home":
			return "I'm from %s. %s" % [home, U.pick(r, ["Have you been?", "Best bakery in the country.", "Quiet place, I like it.", "You'd hate the winters."])]
		"flight":
			if fear > 0.4:
				return "Honestly? I'm terrified. Every noise makes me jump."
			if trait_ == "anxious":
				return "I never really relax on planes. I keep listening to the engines."
			return U.pick(r, ["It's been a nice flight so far.", "The crew are lovely.", "Smoother than my last trip!", "I always sleep on planes."])
		"reassure":
			p.fear = maxf(float(p.get("fear", 0.0)) - 0.25, 0.0)
			if fear > 0.4:
				return U.pick(r, ["...Thank you. That actually helps.", "You really think so? Okay. Okay.", "Thanks, %s. I needed that." % ctx.get("player_name", "friend")])
			return "Oh, I'm fine, but thank you!"
	return "Sorry?"


## Cabin crew lines for the player (passenger mode or a pilot visiting the cabin).
static func crew(fa: Dictionary, request: String, ctx: Dictionary) -> String:
	var r := _r(fa, "crew" + request)
	var phase := String(ctx.get("phase", "cruise"))
	match request:
		"drink":
			if phase in ["takeoff", "climb", "landing", "taxi"]:
				return "I'm sorry, we're about to %s. I'll bring you something as soon as the seatbelt sign is off." % ("land" if phase == "landing" else "take off")
			if bool(ctx.get("seatbelt", false)) and float(ctx.get("turbulence", 0.0)) > 0.3:
				return "The service is paused for the turbulence, but I'll come round as soon as it's smooth."
			return U.pick(r, ["Of course! Water, juice, coffee or tea?", "Coming right up.", "We have orange juice, apple juice, and a very questionable coffee."])
		"status":
			var mins := int(ctx.get("minutes_left", 40))
			if mins <= 0:
				return "We'll be on the ground shortly."
			return "About %d minutes to %s. The captain expects %s." % [mins, String(ctx.get("arr_city", "destination")), ctx.get("arr_weather", "good weather")]
		"nervous":
			return U.pick(r, ["Turbulence is uncomfortable but the aircraft is built for much worse. Keep your belt fastened and you're perfectly safe.",
				"I've done this thousands of times. Those bumps are like a car on a gravel road.", "If you'd like, you can sit up front near me for a while."])
		"emergency":
			return U.pick(r, ["Please stay in your seat and listen to my instructions.", "Keep your seatbelt fastened, tight and low.", "We are trained for this. Follow my instructions."])
	return "How can I help?"


## One line the purser reports to the flight deck about the cabin.
static func purser_report(mood: float, fear: float, injuries: int, pax: int) -> String:
	if injuries > 0:
		return "Captain, %d passenger%s injured in the cabin. We're attending to them." % [injuries, "" if injuries == 1 else "s"]
	if fear > 0.5:
		return "The cabin is very frightened. Some passengers are crying. An announcement would help."
	if fear > 0.25:
		return "A few nervous passengers, nothing we can't handle."
	if mood > 0.8:
		return "Cabin is calm and happy. %d on board, all settled." % pax
	return "Cabin is fine, %d passengers on board." % pax
